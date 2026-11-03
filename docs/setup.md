# Setup guide

This guide takes a repository from nothing to a working pipeline, then through a first end-to-end test. Each step
says what to do, where to click, and what you should see when it worked. Allow about 30 minutes, plus the first
build.

**Contents**

1. [Before you start](#1-before-you-start)
2. [Copy the files into your repository](#2-copy-the-files-into-your-repository)
3. [Configure the checks](#3-configure-the-checks)
4. [Configure the build toolchain](#4-configure-the-build-toolchain)
5. [Write CLAUDE.md](#5-write-claudemd)
6. [Push to the default branch](#6-push-to-the-default-branch)
7. [Add the Claude credential](#7-add-the-claude-credential)
8. [Create the status labels](#8-create-the-status-labels)
9. [Recommended repository settings](#9-recommended-repository-settings)
10. [First test, stage by stage](#10-first-test-stage-by-stage)
11. [Day-to-day use](#11-day-to-day-use)
12. [Try a stage locally](#12-try-a-stage-locally)
13. [Troubleshooting](#13-troubleshooting)
14. [Updating and removing](#14-updating-and-removing)

---

## 1. Before you start

You need:

| What | Why | Check |
| --- | --- | --- |
| A GitHub repository you are an **admin** of | to add the secret, labels and settings | the repository shows a **Settings** tab |
| **GitHub Actions** enabled for it | the pipeline is four workflows | **Settings → Actions → General**: "Allow all actions" (or allow `anthropics/*`, `actions/*` and any toolchain actions you add) |
| Workflows **allowed to create pull requests** | the build stage opens the pull request | **Settings → Actions → General → Workflow permissions**: tick "Allow GitHub Actions to create and approve pull requests". Greyed out? The organization's setting overrides it: an organization owner ticks the same box at `https://github.com/organizations/<org>/settings/actions` first (if it's greyed out there too, an enterprise policy controls it). |
| [Claude Code](https://code.claude.com) installed locally | to create the credential (step 7) | `claude --version` |
| A Claude **Pro / Max** subscription, or a Claude API key | the agents run on it | — |
| [GitHub CLI](https://cli.github.com), signed in (optional) | creates the labels in one command (step 8); without it, create them on github.com | `gh auth status` |
| `bash` and `jq` | the installer and tests | `jq --version` |
| A build and test command that works on Linux | the build stage runs it on GitHub's Ubuntu runners | — |

**How it fits together** (details in [architecture](architecture.md#how-a-stage-runs)): you start every stage with a
comment command such as `/plan`. A comment is a GitHub *event*; each one starts the pipeline's workflows on fresh
GitHub machines, and the workflow that matches the command does the work. The workflow's
scripts prepare the input, Claude Code does the stage's work and answers with JSON, and the scripts act on that answer
(comment, commit, open a pull request). You start every stage; you merge every change.

## 2. Copy the files into your repository

```bash
git clone https://github.com/<you>/claude-code-dev-pipeline
claude-code-dev-pipeline/scripts/install.sh /path/to/your-repo
```

The installer copies everything under `templates/` into the repository and prints each file:

```text
  copy    .github/workflows/ai-plan.yml
  copy    .github/workflows/ai-build.yml
  ...
  skip    CLAUDE.md (exists)
```

- It **never overwrites** a file that already exists (`--force` replaces them).
- `CLAUDE.md` is created from `CLAUDE.md.example` only when the repository has none.
- It does **not** commit anything.

What was added:

| Path | Purpose | Edit it? |
| --- | --- | --- |
| `.github/workflows/ai-plan.yml`, `ai-build.yml`, `ai-review.yml` | plan; build and fix; review | only the toolchain section of `ai-build.yml` (step 4) |
| `.github/workflows/ai-cancel.yml` | the `/cancel` command | no |
| `.github/ISSUE_TEMPLATE/ai-change-request.yml` | the change-request form | optional |
| `.claude/skills/pipeline-*/SKILL.md` | each stage's instructions to Claude | optional |
| `pipeline/scripts/run-checks.sh` | your build and test gate | **yes** (step 3) |
| `pipeline/scripts/*` (everything else), `pipeline/schemas/*`, `pipeline/claude-settings.json` | the pipeline's machinery | no |

## 3. Configure the checks

`pipeline/scripts/run-checks.sh` is the quality gate. The build agent may run **only** this command (it can't run
anything else in the shell), and the build workflow runs it again itself before it opens a pull request. Make it:

- build and test the whole project;
- exit `0` only when everything passes;
- run without prompts (no interactive input, no watch mode).

Keep the block at the top of the template: in CI it removes the GitHub, cloud and Claude credentials from the
environment and the git remote before any project code (including tests the agent wrote) runs.

Replace the rest of the template body with your commands. Examples:

```bash
# Node
npm ci && npm run lint && npm test

# .NET
dotnet build -warnaserror && dotnet test --no-build

# Android
./gradlew --no-daemon testDebugUnitTest

# Python
pip install -r requirements.txt && pytest -q
```

Several projects in one repository? Run each in turn with `set -euo pipefail` at the top, so the first failure stops
the script.

**Check:** run it locally from the repository root. It should pass on a clean checkout:

```bash
./pipeline/scripts/run-checks.sh; echo "exit=$?"
```

### Test database migrations

If the repository has database migrations, test them in `run-checks.sh` too, otherwise a broken migration is only
found when someone applies it. On GitHub's runner, start a throwaway database container, apply every migration, and
remove it; skip it locally so developers' machines and databases are never touched:

```bash
if [[ "${CI:-}" == "true" ]]; then
  db="checks-db-$(date +%s)-$RANDOM"   # unique, so it never collides with another container
  docker run -d --rm --name "$db" -e POSTGRES_PASSWORD=checks -p 127.0.0.1::5432 postgres:16 > /dev/null
  trap 'docker rm -f "$db" > /dev/null 2>&1 || true' EXIT
  port="$(docker port "$db" 5432/tcp | head -n 1 | sed 's/.*://')"
  # Wait for TCP (Postgres restarts once during its first start); stop with a clear error if it never comes up.
  ready=false
  for _ in $(seq 1 90); do
    if docker exec "$db" pg_isready -h 127.0.0.1 > /dev/null 2>&1; then ready=true; break; fi
    sleep 1
  done
  if [[ "$ready" != "true" ]]; then echo "::error::Postgres did not start for the migration check."; exit 1; fi
  # apply your migrations to 127.0.0.1:$port, for example with Flyway:
  docker run --rm --network host -v "$PWD/db/migrations:/flyway/sql:ro" flyway/flyway:10 \
    -url="jdbc:postgresql://127.0.0.1:${port}/postgres" -user=postgres -password=checks migrate
fi
```

GitHub sets `CI=true` on its runners. Use the same tool and settings you use for real databases.

## 4. Configure the build toolchain

GitHub's Ubuntu runners include common tools, but you should pin the versions your checks need. Open
`.github/workflows/ai-build.yml` and replace the comment block marked **Your toolchain** with setup steps:

```yaml
      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
```

| Stack | Step |
| --- | --- |
| Node | `actions/setup-node@v4` with `node-version` |
| .NET | `actions/setup-dotnet@v4` with `dotnet-version: 8.0.x` |
| Java / Android | `actions/setup-java@v4` (`distribution: temurin`, `java-version`) and `gradle/actions/setup-gradle@v4` with `cache-read-only: true`; the runner already has the Android SDK |
| Python | `actions/setup-python@v5` with `python-version` |

Only the build stage needs this. Plan and review only read code.

**Keep caches read-only.** Code the agent wrote (its tests) runs in the build job, so a cache saved from that job
could carry something it left behind into later runs. Use the setup actions' read-only cache option where there is
one (`cache-read-only: true` for Gradle), and leave caching off where there isn't (no `cache:` for setup-node).

### Private packages and cloud credentials

If your build needs credentials (a private package feed such as AWS CodeArtifact, Azure Artifacts or GitHub
Packages), get them in the toolchain section and keep them away from the agent:

1. Authenticate the usual way for your CI, for example OIDC with `aws-actions/configure-aws-credentials`. The cloud
   side must trust this repository; for AWS that means the IAM role's trust policy allows
   `repo:<owner>/<repo>:ref:refs/heads/<default-branch>` (issue comments run on the default branch). OIDC also needs
   `id-token: write` in the **build** job's `permissions:` (the template leaves it out).
   Some organizations customise this subject to include IDs (`repo:<owner>@<owner-id>/<repo>@<repo-id>:…`); copy the
   format of the subjects your trust policy already lists. A repository's ID is in its page source on github.com
   (search for `repository_id`).
2. Write any config that holds a token (`NuGet.Config`, `.npmrc`, `pip.conf`) to `$RUNNER_TEMP/secrets/`, outside the
   workspace; `pipeline/claude-settings.json` denies the agent reading that folder. Pass its path to `run-checks.sh`
   through `$GITHUB_ENV`.
3. Blank the cloud credentials before the agent's step, so neither the agent nor the code it runs gets them.

```yaml
      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_ROLE_TO_ASSUME }}
          aws-region: ${{ vars.AWS_REGION }}

      - name: Prepare the package feed
        run: |
          token="$(aws codeartifact get-authorization-token --domain my-domain --query authorizationToken --output text)"
          mkdir -p "${RUNNER_TEMP}/secrets"
          # ... write "${RUNNER_TEMP}/secrets/NuGet.Config" with the token ...
          echo "PACKAGE_CONFIG=${RUNNER_TEMP}/secrets/NuGet.Config" >> "$GITHUB_ENV"

      - name: Drop the cloud credentials
        run: |
          { echo "AWS_ACCESS_KEY_ID="; echo "AWS_SECRET_ACCESS_KEY="; echo "AWS_SESSION_TOKEN="; } >> "$GITHUB_ENV"
```

`run-checks.sh` then uses the config when it's set and falls back to the developer's own setup locally:

```bash
dotnet restore ${PACKAGE_CONFIG:+--configfile "$PACKAGE_CONFIG"}
```

Add the secret and variable the steps use (here `AWS_ROLE_TO_ASSUME`, `AWS_REGION`) as in step 7.

## 5. Write CLAUDE.md

`CLAUDE.md` holds your project's rules: architecture, conventions, commit format and things never to do. Claude Code
loads it automatically in every session, so every pipeline agent follows it, and so do your own interactive sessions.

- Start from the generated file (or the example in this repository) and replace the examples with real rules.
- Keep it short and specific; agents read it on every run.
- It's written for developers too. Steps an agent can't do in the pipeline (deploying, running the app, using a
  database) are fine to keep: the build agent skips them and lists anything a person should do after merging.

You don't need to mention the pipeline or its skills in it. Each workflow names its skill directly.

## 6. Push to the default branch

```bash
git add .github .claude pipeline CLAUDE.md
git commit -m "ci(pipeline): add the ai plan, build and review pipeline"
git push
```

The files must be on the repository's **default branch** (shown under **Settings → General → Default branch**).
GitHub runs workflows started by issue comments **only from the default branch**, and the Actions tab
lists only workflows found there. Files pushed to a feature branch do nothing yet. If your work is on a feature
branch, merge it, or move just the pipeline commit:

```bash
git switch <default-branch> && git pull
git cherry-pick <pipeline-commit-hash>
git push
```

**Check:** the repository's **Actions** tab lists **AI Plan**, **AI Build**, **AI Review** and **AI Cancel**.

## 7. Add the Claude credential

The agents run on a Claude account. GitHub can't sign in to Claude as you, so you give it a **token**: a long code that works like a spare key to your
Claude account. Every pipeline run uses it, and its usage counts against that account's plan, just as if you were
using Claude Code yourself.

**Which Claude account?** The one Claude Code on your computer is signed in to. Check it with `/status` inside
Claude Code. If it's the wrong account, sign out and in again (`/logout`, then `claude`) before creating the token.

**With a Claude Pro / Max subscription** (what the templates use):

```bash
claude setup-token
```

A browser opens to sign in, then the terminal prints a long-lived token. It's shown once: copy it now.

Then on GitHub: **Settings → Secrets and variables → Actions → New repository secret**

| Field | Value |
| --- | --- |
| Name | `CLAUDE_CODE_OAUTH_TOKEN` |
| Secret | the token |

What to know about this token:

- **It is you.** It belongs to the account that created it; pipeline runs count against that plan's usage limits,
  shared with that person's own Claude use.
- **It lasts about a year.** When it expires, the Claude step fails with an authentication error. Renew it: run
  `claude setup-token` again and update the secret (**Settings → Secrets and variables → Actions →
  `CLAUDE_CODE_OAUTH_TOKEN` → Update**). Put a reminder in your calendar.
- **Treat it like a password.** Store it only as a GitHub secret. If it's ever exposed, create a new one the same way
  and replace the secret straight away.
- **Removing access:** delete the secret, and the pipeline can no longer use your account.

**With a Claude API key** (better for a team): create a key at [platform.claude.com](https://platform.claude.com), add it
as the secret `ANTHROPIC_API_KEY`, and in each workflow with a Claude step (plan, build, review) replace

```yaml
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

with

```yaml
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

**Check:** **Settings → Secrets and variables → Actions** lists the secret (its value is never shown again).

**No Claude GitHub App.** The pipeline doesn't use Anthropic's Claude GitHub App: each Claude step is given its job's
own GitHub token, which can do only what that job's `permissions:` allow (the build job's can only read). If the app is
installed on this repository (for example by `/install-github-app` in Claude Code) and you don't use it for anything
else, uninstall it under **Settings → GitHub Apps**.

## 8. Create the status labels

The pipeline labels issues so you can see a plan's status in the issue list. You never add these yourself; you start
every stage with a comment command. A label must exist before the pipeline can set it, so create the two below once,
either way:

**On github.com:** **Issues → Labels → New label**, once per label. Only the names must match exactly; colors and
descriptions are up to you.

**Or with the GitHub CLI:**

```bash
claude-code-dev-pipeline/scripts/create-labels.sh <owner>/<repo>
```

| Label | Set by the pipeline when |
| --- | --- |
| `ai:needs-answers` | the plan has questions for you |
| `ai:plan-ready` | the plan has no open questions and is ready for `/approve` |

**Check:** **Issues → Labels** shows both.

## 9. Recommended repository settings

- **Branch protection** on the default branch (**Settings → Branches** or **Rules**): require a pull request and at
  least one approval. The pipeline never merges; this makes sure nothing else does either.
  - Free for public repositories; private repositories need a paid GitHub plan (Pro, Team or Enterprise). Without
    it, the pipeline still works: it never merges, so merging stays a person's choice.
  - Working alone? GitHub doesn't let you approve your own pull requests, so a required approval would block yours.
    Allow administrators to bypass the rule, or require a pull request without an approval. The pipeline's pull
    requests are opened by `github-actions[bot]`, so you can approve those.
- **Allow-list (optional):** **Settings → Secrets and variables → Actions → Variables → New repository variable**,
  name `PIPELINE_ALLOWED_USERS`, value a comma-separated list of GitHub usernames. Only they can then start a stage,
  on top of the write-access check.
- **Public repositories:** read issues from people outside the project before you plan them. Their comments never
  reach the agent, but the issue body you choose to plan does. Anyone who can comment can type a command; the job
  refuses them, but their comment can still replace a queued run or cancel a running plan or review. If that becomes a
  problem, limit who can comment (**Settings → Moderation options → Interaction limits**).
- **Self-hosted runners:** `pipeline/claude-settings.json` denies reading `/home/runner/work/_temp/secrets`, the
  location on GitHub-hosted runners. Change it to your runner's `RUNNER_TEMP`.

- **Delete merged branches automatically:** **Settings → General → Pull Requests →** tick "Automatically delete head
  branches", so merged `ai/issue-N-…` branches disappear.
- **Show "Update branch" on pull requests:** **Settings → General → Pull Requests →** tick "Always suggest updating
  pull request branches". Without branch protection that requires up-to-date branches, GitHub only shows the
  **Update branch** button with this setting on. You need it when `/fix` asks you to update a branch yourself (see
  "Updating a pull request's branch" under [Troubleshooting](#13-troubleshooting)).
- **Your own CI on the pipeline's pull requests:** GitHub doesn't start workflows from pushes or pull requests made
  with the workflow token, so CI that runs on `pull_request` won't start by itself on the pipeline's pull requests.
  The pipeline already runs `run-checks.sh` twice per build. To also run your CI automatically, change
  `publish.sh` to push with a token from a GitHub App you create (or a fine-grained token stored as a secret) instead
  of `GITHUB_TOKEN`; or run your CI manually from the pull request.

### Choosing the model and limits

Every stage uses Claude Opus (`claude-opus-5-5`) by default, with limits sized for real features. Change any of them
with a repository variable (**Settings → Secrets and variables → Actions → Variables**), no code change needed:

| Variable | Default | What it sets |
| --- | --- | --- |
| `PIPELINE_MODEL_PLAN` / `_BUILD` / `_REVIEW` | `claude-opus-5-5` | the model per stage (build also covers fix) |
| `PIPELINE_MAX_TURNS_PLAN` / `_BUILD` / `_REVIEW` | 60 / 200 / 60 | how many steps the agent may take before it stops |
| `PIPELINE_TIMEOUT_PLAN` / `_BUILD` / `_REVIEW` | 30 / 120 / 30 | minutes before GitHub stops the job |

The review runs four agents, so it is the largest share of usage: set `PIPELINE_MODEL_REVIEW` to `claude-sonnet-5-5`
if your plan's limits get tight. Raise the build limits for very large changes, or better, split the issue.

## 10. First test, stage by stage

Use something small and safe the first time, such as adding one unit test, so you see the whole loop before trusting
it with a feature. If a step doesn't behave as described, see [Troubleshooting](#13-troubleshooting).

### 10.1 Plan (about 2–5 minutes)

1. **Issues → New issue → Change request (AI pipeline)**. Fill in:
   - **Goal:** for example "Add a unit test for the date formatter's handling of empty input".
   - **Acceptance criteria:** "A new test covers empty input; no production code changes".
2. Comment **`/plan`** on the issue. Commands only work at the very start of a comment.
3. Open the **Actions** tab: an **AI Plan** run appears. Click it to watch the steps; the **Plan** step is Claude.
4. When it finishes, the issue has a **🗺️ Implementation plan** comment and the label `ai:plan-ready` or
   `ai:needs-answers`.
5. If it asked questions: reply in **one comment that starts with `/plan`**, with your answers on the following lines.
   `/plan` is this pipeline's command (not a GitHub feature): a comment starting with it re-runs the plan stage, and
   the agent reads the whole thread, your answers included. A new plan appears that uses your answers. Repeat until
   `ai:plan-ready`.

Each stage posts **⏳ started · follow the run** on the issue or pull request when it begins.

### 10.2 Build (about 10–30 minutes)

1. Comment **`/approve`** on the issue. That comment is your approval of the latest plan.
2. **Actions** tab: an **AI Build** run appears with these jobs:
   - **prepare** checks you may run it and posts **⏳ started**;
   - **build** is the long one: the **Build or fix** step is Claude implementing the plan and running your checks
     until they pass, then **Run the checks again** (the pipeline verifying for itself) and **Commit the change for
     publishing**. This job can only read the repository;
   - **publish** pushes the branch and opens the pull request (the only job that can push);
   - **review** reviews the pull request (10.3).
3. When it finishes:
   - a pull request titled in the commit format, for example `test(dates): cover empty input in the date formatter`;
   - its description lists the changes, the checks and any follow-ups;
   - the issue has a **🔧 Built the approved plan** comment linking to it.
4. If the agent couldn't finish, the issue gets a **⚠️ The build stage failed** comment (posted by a **report** job)
   and nothing was pushed. The run's **Build or fix** step log explains why.

> Your repository's own CI workflows won't start on this pull request by themselves: GitHub doesn't start workflows
> from pushes made with the workflow token. The build stage already ran your checks; re-run CI manually if you need
> it. See [design decisions](design-decisions.md#known-limits).

### 10.3 Review (about 5 minutes)

1. Nothing to do: the build run reviews the pull request as soon as it's open (its **review** jobs). To review again
   later, for example after pushing changes yourself, comment **`/review`** on the pull request: that starts a
   separate **AI Review** run.
2. Either way the review is a **gate** job, four **review** jobs in parallel (correctness, security, tests,
   requirements) and a **summarize** job.
3. The pull request gets one **🔍 AI review** comment: a verdict per lens and the findings ranked by severity.
4. After changing the pull request, comment **`/review`** again. Each review posts a new comment at the bottom and folds the earlier ones away, marked outdated.

### 10.4 Fix (about 10–30 minutes)

When the review (or you) finds something to change, fix it on the same pull request:

1. Comment on the pull request: **`/fix`** alone fixes the AI review's findings; **`/fix` followed by text** does what
   you ask, for example `/fix add a test for the JSON mapping`. Comments you leave on lines of code are included.
2. **Actions** tab: an **AI Build** run in fix mode, with the same jobs as a build. It first brings the branch up to
   date with its base (the agent resolves any conflicts), then fixes, runs the checks, and the workflow checks again.
3. The pull request gets a new commit and a **🔧** comment saying what changed (and why any finding was left), and
   the review runs again on its own.
4. Repeat `/fix` until you're happy.

### 10.5 Merge

Read the pull request and the review, then merge it yourself (or close it). Do anything listed under follow-ups, such
as applying a database migration.

## 11. Day-to-day use

Everything is a comment whose **first word is** a command (any letter case; `/approved` or `/planning` don't count).
Only people with write access to the repository can run them; anyone else's command is ignored.

| Command | Where | What it does |
| --- | --- | --- |
| `/plan` + text | issue | plan, or re-plan with your answers / changes |
| `/approve` | issue | build the latest plan (this is your approval); each `/approve` opens a new pull request, so close an older one you no longer want |
| `/fix` + text | pull request | fix the review's findings, or what you ask; brings the branch up to date first |
| `/review` | pull request | review again (the first review is automatic) |
| `/cancel` | issue or pull request | stop a running plan, build, fix or review |

| You want to | Do this |
| --- | --- |
| Ask for a change | open an issue with the form, then `/plan` |
| Answer the plan's questions | `/plan`, answers on the next lines |
| Change your mind about the plan | `/plan`, then what should change |
| Approve and build | `/approve` |
| Get review findings fixed | `/fix` on the pull request |
| Ask for a specific change on the pull request | `/fix` + what to change, or comments on lines of code then `/fix` |
| Stop something | `/cancel` |
| See what happened | the **⏳ started** comment links to the run; the **Actions** tab shows all runs |

## 12. Try a stage locally

The skills live in the repository, so you can run a stage in your own terminal to see what the agent would do, with
no GitHub involved:

1. Write the request to `.pipeline/issue.md` (the file the workflows generate), for example:

   ```markdown
   # Issue #0: Add a unit test for empty input
   ## Request
   Add a unit test for the date formatter's handling of empty input. No production changes.
   ```

2. Run `claude` in the repository root and type `/pipeline-plan`.

Use this to try changes to a skill's instructions before they reach the pipeline. Delete `.pipeline/` afterwards.

## 13. Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| A failed build left an `ai/issue-N-…` branch | Each build pushes a new branch before opening its pull request. Delete leftover branches under **Code → Branches**. |
| Nothing appears in Actions after a command | The workflow files aren't on the default branch (step 6); Actions are disabled (step 1); or the command isn't the comment's first word (the run then stops at **Check the requester may run the pipeline** saying so). |
| The plan step fails to set a label | The status labels don't exist yet (step 8). |
| **GitHub Actions is not permitted to create or approve pull requests** | Tick "Allow GitHub Actions to create and approve pull requests" (step 1). The branch was already pushed: open its pull request from the link in the log and comment `/review`. |
| The run fails at **Check the requester may run the pipeline** | The person who wrote the command lacks write access, or isn't in `PIPELINE_ALLOWED_USERS`. |
| The run fails in the **Plan / Build or fix / Review** (Claude) step with an authentication error | The secret is missing or misnamed (step 7), or the token expired (`claude setup-token` again). Test the token locally with `claude`. |
| `/approve` fails with **There is no plan on this issue yet** | Comment `/plan` first. |
| **is not configured for this repository yet** | `pipeline/scripts/run-checks.sh` still has the template body (step 3). |
| The Claude step stops at the turn limit, or a comment says **stopped at its time limit** | The change is too big for one run. Split the issue, or raise `PIPELINE_MAX_TURNS_*` / `PIPELINE_TIMEOUT_*` (see "Choosing the model and limits"). |
| Fix fails with **changed workflow files since this branch was made** | GitHub doesn't let a workflow's token push changes to `.github/workflows/`, so the pipeline can't bring those into the branch. Update the branch yourself (below), then `/fix` again. This happens only when the default branch's workflows changed after the pull request was opened, for example after you updated the pipeline. |
| **Pushing to … was refused** or **don't sit on top of** | Fix: someone pushed to the pull request while the fix ran; `/fix` again. Build: rare (the commits didn't build on the recorded start commit); `/approve` again. The default branch moving during a build is fine. |
| **The change touches workflow files** | GitHub doesn't let the pipeline push `.github/workflows/` changes. Make that part yourself; ask the pipeline only for the rest. |
| Fix fails with **conflicts in files the agent may not change**, **in binary files** or **where one side deleted a file** | The agent can't resolve those. Update the branch yourself (below), resolving the conflicts, then `/fix` again. |
| **Unresolved merge conflicts remain in: …** (fix) | The agent couldn't resolve every conflict with the base branch. Resolve them locally on the branch and push, or `/fix` with guidance on which side to keep. |
| `/fix` fails with **This pull request is not open** | Reopen it first, or start over with `/approve` on the issue. |
| Fix says **Nothing to change** | The agent found nothing to do for the request; its reason is in the comment. Be more specific after `/fix`. |
| `/cancel` | Posts **⏹ Cancelling…**; the stopped run posts nothing else. If it was already publishing, its branch or pull request may exist: check the pull request or **Code → Branches**. |
| A database migration fails in **Run the checks** | The migration has an error; the log shows the SQL error. `/fix` with the error, or fix it yourself. |
| Build reports **blocked** | The agent explains why in the failure comment and the run log. Clarify in a comment starting with `/plan`, then `/approve` again. |
| **Run the checks again** fails after the agent said they passed | The checks aren't deterministic (flaky tests, network). Fix `run-checks.sh` or the tests; nothing was committed. |
| A toolchain or package restore step fails | A missing setup step or credential (step 4). For cloud credentials, check the cloud side trusts this repository and branch. |
| **commit header is not in the Conventional Commits format** / **commit title is not a Conventional Commits header** | The agent's commit fields didn't form a valid header. Comment the command again; if it repeats, open an issue on this repository. |
| You re-ran a failed **publish** job | Works: it pushes to a new branch named with the run attempt. Delete a branch an earlier attempt left behind. |
| Your CI doesn't run on the pipeline's pull request | Expected (see 10.2). |
| A build's pull request couldn't be opened after the push | The failure comment names the branch: open a pull request from it yourself, or delete it and `/approve` again. |
| A review lens failed | The summary still posts the other lenses and a ⚠️ comment links to the run. Comment `/review` to retry. |

To read a run's details: **Actions** → the run → the failed job → expand the failed step.

**Updating a pull request's branch** (bringing in the latest default branch yourself):

- **On github.com:** the **Update branch** button in the pull request's merge box (needs "Always suggest updating
  pull request branches", step 9).
- **Or locally:**

  ```bash
  git switch <pr-branch> && git pull
  git merge origin/<default-branch>      # resolve any conflicts, then git commit
  git push
  ```

## 14. Updating and removing

**Updating** to a newer version of this repository: pull it, then compare its `templates/` with your repository.

1. Copy over every file you haven't customised: everything except `pipeline/scripts/run-checks.sh`,
   `.github/workflows/ai-build.yml` and your `CLAUDE.md`.
2. `ai-build.yml`: take the new template, paste your toolchain section back into the marked step, and re-add
   `id-token: write` to the build job if your toolchain uses OIDC.
3. `run-checks.sh`: keep your commands, but make its `if [[ "${CI:-}" == "true" ]]` block at the top match the
   template's. That block keeps tokens away from the code the checks run.
4. Delete pipeline files the new version no longer has (compare `pipeline/scripts/`, `.claude/skills/pipeline-*` and
   `.github/workflows/ai-*.yml` with `templates/`).
5. Run your checks, review the diff, and commit.
6. If the update changed `.github/workflows/`, open pull requests from the pipeline need their branch updated
   (Troubleshooting, "Updating a pull request's branch") before `/fix` works on them.

**Upgrading from the label-based version** (labels `ai:plan`, `ai:approved`, `ai:review` started stages): after
updating as above, delete those three labels (**Issues → Labels**); they do nothing now. Use `/plan`, `/approve` and
`/review` instead. The pipeline also no longer uses the Claude GitHub App: uninstall it from the repository unless
something else uses it (**Settings → GitHub Apps → Claude → Configure**).

**Pausing:** disable the workflows under **Actions** → workflow → **⋯ → Disable workflow**.

**Removing:** delete `.github/workflows/ai-*.yml` (plan, build, review, cancel), `.github/ISSUE_TEMPLATE/ai-change-request.yml`,
`.claude/skills/pipeline-*` and `pipeline/`; delete the `CLAUDE_CODE_OAUTH_TOKEN` (or `ANTHROPIC_API_KEY`) secret
and the `ai:needs-answers` / `ai:plan-ready` labels.

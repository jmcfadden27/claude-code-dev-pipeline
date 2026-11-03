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
7. [Install the Claude GitHub App](#7-install-the-claude-github-app)
8. [Add the Claude credential](#8-add-the-claude-credential)
9. [Create the labels](#9-create-the-labels)
10. [Recommended repository settings](#10-recommended-repository-settings)
11. [First test, stage by stage](#11-first-test-stage-by-stage)
12. [Day-to-day use](#12-day-to-day-use)
13. [Try a stage locally](#13-try-a-stage-locally)
14. [Troubleshooting](#14-troubleshooting)
15. [Updating and removing](#15-updating-and-removing)

---

## 1. Before you start

You need:

| What | Why | Check |
| --- | --- | --- |
| A GitHub repository you are an **admin** of | to add secrets, labels and the GitHub App | the repository shows a **Settings** tab |
| **GitHub Actions** enabled for it | the pipeline is four workflows | **Settings → Actions → General**: "Allow all actions" (or allow `anthropics/*`, `actions/*` and any toolchain actions you add) |
| Workflows **allowed to create pull requests** | the build stage opens the pull request | **Settings → Actions → General → Workflow permissions**: tick "Allow GitHub Actions to create and approve pull requests". Greyed out? The organization's setting overrides it: an organization owner ticks the same box at `https://github.com/organizations/<org>/settings/actions` first (if it's greyed out there too, an enterprise policy controls it). |
| [Claude Code](https://code.claude.com) installed locally | to create the credential (step 8) | `claude --version` |
| A Claude **Pro / Max** subscription, or a Claude API key | the agents run on it | — |
| [GitHub CLI](https://cli.github.com), signed in (optional) | creates the labels in one command (step 9); without it, create them on github.com | `gh auth status` |
| `bash` and `jq` | the installer and tests | `jq --version` |
| A build and test command that works on Linux | the build stage runs it on GitHub's Ubuntu runners | — |

**How it fits together** (details in [architecture](architecture.md#how-a-stage-runs)): adding a label or posting a
`/command` is a GitHub *event*. Each event starts one of the three workflows on a fresh GitHub machine. The workflow's
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
| Java / Android | `actions/setup-java@v4` (`distribution: temurin`, `java-version`) and `gradle/actions/setup-gradle@v4`; the runner already has the Android SDK |
| Python | `actions/setup-python@v5` with `python-version` |

Only the build stage needs this. Plan and review only read code.

### Private packages and cloud credentials

If your build needs credentials (a private package feed such as AWS CodeArtifact, Azure Artifacts or GitHub
Packages), get them in the toolchain section and keep them away from the agent:

1. Authenticate the usual way for your CI, for example OIDC with `aws-actions/configure-aws-credentials`. The cloud
   side must trust this repository; for AWS that means the IAM role's trust policy allows
   `repo:<owner>/<repo>:ref:refs/heads/<default-branch>` (labels and issue comments run on the default branch).
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

Add the secret and variable the steps use (here `AWS_ROLE_TO_ASSUME`, `AWS_REGION`) as in step 8.

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
GitHub runs workflows started by labels and issue comments **only from the default branch**, and the Actions tab
lists only workflows found there. Files pushed to a feature branch do nothing yet. If your work is on a feature
branch, merge it, or move just the pipeline commit:

```bash
git switch <default-branch> && git pull
git cherry-pick <pipeline-commit-hash>
git push
```

**Check:** the repository's **Actions** tab lists **AI Plan**, **AI Build**, **AI Review** and **AI Cancel**.

## 7. Install the Claude GitHub App

A *GitHub App* is GitHub's name for an outside service you allow to work with your repositories. Nothing is
downloaded; it's a permission, like a key card. The Claude GitHub App is Anthropic's: when a workflow reaches its
Claude step, `claude-code-action` uses it to prove to GitHub that Claude may work in this repository. Without it,
that step fails.

1. Signed in to GitHub, open <https://github.com/apps/claude>.
2. Click **Install** (or **Configure** if it's installed elsewhere already).
3. Pick the account that owns the repository (your user or an organization; an organization owner may need to
   approve).
4. Under **Repository access** choose **Only select repositories** and pick this repository.
5. Review the permissions and click **Install**.

GitHub shows one permission set shared by all of Claude's GitHub features and doesn't allow accepting part of it.
Each workflow's `permissions:` block limits what a run can actually do.

**Check:** the repository's **Settings → GitHub Apps** lists **Claude**.

**Managing the connection later:**

| Where | What you manage there |
| --- | --- |
| GitHub: repository **Settings → GitHub Apps**, or your account / organization **Settings → Applications → Installed GitHub Apps** | which repositories the app is installed on, its permissions, uninstalling |
| Claude: [claude.ai → Customize → Connectors → GitHub](https://claude.ai/customize/connectors/yours/id/integration-github) | your Claude account's GitHub integration |

Alternative: running `/install-github-app` inside Claude Code installs the app and stores the credential (step 8)
for you. It also offers to add Anthropic's own example workflows; you don't need those.

## 8. Add the Claude credential

**Two separate sign-ins.** The pipeline needs access in two directions, and each is set up once:

| Direction | What grants it | Set up in |
| --- | --- | --- |
| Claude may work in the repository | the Claude GitHub App, installed on the repository | step 7 |
| The work runs on (and is billed to) a Claude account | a token for that account, stored as a repository secret | this step |

GitHub can't sign in to Claude as you, so you give it a **token**: a long code that works like a spare key to your
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
as the secret `ANTHROPIC_API_KEY`, and in each of the three workflows replace

```yaml
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

with

```yaml
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

**Check:** **Settings → Secrets and variables → Actions** lists the secret (its value is never shown again).

## 9. Create the labels

A label must exist in the repository before it can be added to an issue. Create the five below once, either way:

**On github.com:** **Issues → Labels → New label**, once per label. Only the names must match exactly; colors and
descriptions are up to you.

**Or with the GitHub CLI:**

```bash
claude-code-dev-pipeline/scripts/create-labels.sh <owner>/<repo>
```

| Label | Added by | Meaning |
| --- | --- | --- |
| `ai:plan` | you | plan this issue |
| `ai:needs-answers` | the pipeline | the plan has questions for you |
| `ai:plan-ready` | the pipeline | the plan has no open questions |
| `ai:approved` | you | build the latest plan (this is your approval) |
| `ai:review` | you | review this pull request again (the first review runs automatically after the build) |

**Check:** **Issues → Labels** shows all five.

## 10. Recommended repository settings

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
- **Public repositories:** read issues from people outside the project before you label them. Their comments never
  reach the agent, but the issue body you choose to plan does. Anyone who can comment can type a command; the job
  refuses them, but their comment can still replace a queued run or cancel a running plan or review. If that becomes a
  problem, limit who can comment (**Settings → Moderation options → Interaction limits**).
- **Self-hosted runners:** `pipeline/claude-settings.json` denies reading `/home/runner/work/_temp/secrets`, the
  location on GitHub-hosted runners. Change it to your runner's `RUNNER_TEMP`.

- **Delete merged branches automatically:** **Settings → General → Pull Requests →** tick "Automatically delete head
  branches", so merged `ai/issue-N-…` branches disappear.
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

## 11. First test, stage by stage

Use something small and safe the first time, such as adding one unit test, so you see the whole loop before trusting
it with a feature. If a step doesn't behave as described, see [Troubleshooting](#14-troubleshooting).

### 11.1 Plan (about 2–5 minutes)

1. **Issues → New issue → Change request (AI pipeline)**. Fill in:
   - **Goal:** for example "Add a unit test for the date formatter's handling of empty input".
   - **Acceptance criteria:** "A new test covers empty input; no production code changes".
2. Add the label **`ai:plan`**.
3. Open the **Actions** tab: an **AI Plan** run appears. Click it to watch the steps; the **Plan** step is Claude.
4. When it finishes, the issue has a **🗺️ Implementation plan** comment and the label `ai:plan-ready` or
   `ai:needs-answers`.
5. If it asked questions: reply in **one comment that starts with `/plan`**, with your answers on the following lines.
   `/plan` is this pipeline's command (not a GitHub feature): a comment starting with it re-runs the plan stage, and
   the agent reads the whole thread, your answers included. A new plan appears that uses your answers. Repeat until
   `ai:plan-ready`.

Each stage posts **⏳ started · follow the run** on the issue or pull request when it begins.

### 11.2 Build (about 10–30 minutes)

1. Add the label **`ai:approved`** to the issue, or comment **`/approve`**.
2. **Actions** tab: an **AI Build** run appears. The **Build** step is Claude implementing the plan and running your
   checks until they pass; it's the longest step. Then **Run the checks again** (the pipeline verifying for itself)
   and **Commit the change for publishing**. A second job, **publish**, then pushes the branch and opens the pull
   request (it's the only job with write access).
3. When it finishes:
   - a pull request titled in the commit format, for example `test(dates): cover empty input in the date formatter`;
   - its description lists the changes, the checks and any follow-ups;
   - the issue has a **🔧 Built the approved plan** comment linking to it.
4. If the agent couldn't finish, the issue gets a **⚠️ The build stage failed** comment and nothing was committed.
   The run's **Build** step log explains why.

> Your repository's own CI workflows won't start on this pull request by themselves: GitHub doesn't start workflows
> from pushes made with the workflow token. The build stage already ran your checks; re-run CI manually if you need
> it. See [design decisions](design-decisions.md#known-limits).

### 11.3 Review (about 5 minutes)

1. Nothing to do: the build workflow starts the review as soon as it opens the pull request (the **Build** run gets a
   **review** part). To review again later, for example after pushing changes, comment **`/review`** or add the
   **`ai:review`** label.
2. **Actions** tab: **AI Review** runs a **gate** job, four **review** jobs in parallel (correctness, security, tests,
   requirements) and a **summarize** job.
3. The pull request gets one **🔍 AI review** comment: a verdict per lens and the findings ranked by severity.
4. After changing the pull request, comment **`/review`** again; the same comment is updated.

### 11.4 Fix (about 10–30 minutes)

When the review (or you) finds something to change, fix it on the same pull request:

1. Comment on the pull request: **`/fix`** alone fixes the AI review's findings; **`/fix` followed by text** does what
   you ask, for example `/fix add a test for the JSON mapping`. Comments you leave on lines of code are included.
2. **Actions** tab: an **AI Build** run in fix mode. It first brings the branch up to date with its base (the agent
   resolves any conflicts), then fixes, runs the checks, and the workflow checks again.
3. The pull request gets a new commit and a **🔧** comment saying what changed (and why any finding was left), and
   the review runs again on its own.
4. Repeat `/fix` until you're happy.

### 11.5 Merge

Read the pull request and the review, then merge it yourself (or close it). Do anything listed under follow-ups, such
as applying a database migration.

## 12. Day-to-day use

**Commands** (comments that start with them; only people with write access):

| Command | Where | What it does |
| --- | --- | --- |
| `/plan` + text | issue | plan, or re-plan with your answers / changes |
| `/approve` | issue | build the latest plan (same as the `ai:approved` label) |
| `/fix` + text | pull request | fix the review's findings, or what you ask; brings the branch up to date first |
| `/review` | pull request | review again (the first review is automatic) |
| `/cancel` | issue or pull request | stop a running plan, build, fix or review; nothing half-done is pushed |

| You want to | Do this |
| --- | --- |
| Ask for a change | open an issue with the form, add `ai:plan` |
| Answer the plan's questions | `/plan`, answers on the next lines |
| Change your mind about the plan | `/plan`, then what should change |
| Approve and build | `/approve` (or add `ai:approved`) |
| Get review findings fixed | `/fix` on the pull request |
| Ask for a specific change on the pull request | `/fix` + what to change, or comments on lines of code then `/fix` |
| Stop something | `/cancel` |
| See what happened | the **⏳ started** comment links to the run; the **Actions** tab shows all runs |

## 13. Try a stage locally

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

## 14. Troubleshooting

| Symptom | Cause and fix |
| --- | --- |
| Removing and re-adding a label started nothing | GitHub saves label changes when the label menu closes: unticking and re-ticking in one open menu changes nothing. Untick, close the menu, then open it again and tick. |
| A failed build left an `ai/issue-N-…` branch | Each build pushes a new branch before opening its pull request. Delete leftover branches under **Code → Branches**. |
| Nothing appears in Actions after adding a label | The workflow files aren't on the default branch (step 6); Actions are disabled (step 1); or the label name doesn't match exactly. |
| **GitHub Actions is not permitted to create or approve pull requests** | Tick "Allow GitHub Actions to create and approve pull requests" (step 1). The branch was already pushed: open its pull request from the link in the log and comment `/review`. |
| The run fails at **Check the requester may run the pipeline** | The person who added the label or wrote the command lacks write access, or isn't in `PIPELINE_ALLOWED_USERS`. |
| The run fails in the **Plan / Build or fix / Review** (Claude) step with an authentication error | The secret is missing or misnamed (step 8), the token expired (`claude setup-token` again), or the Claude GitHub App isn't installed on this repository (step 7). Test the token locally with `claude`. |
| **Work out what to do** fails with "No plan on this issue yet" | The issue has no plan comment yet. Add `ai:plan` (or comment `/plan`) first. |
| **is not configured for this repository yet** | `pipeline/scripts/run-checks.sh` still has the template body (step 3). |
| The Claude step stops at the turn limit, or the job at its timeout | The change is too big for one run. Split the issue, or raise `PIPELINE_MAX_TURNS_*` / `PIPELINE_TIMEOUT_*` (see "Choosing the model and limits"). |
| Fix fails with **changed workflow files since this branch was made** | The pipeline's workflow token can't push changes to `.github/workflows/`. Click **Update branch** on the pull request (or merge the base into it yourself), then `/fix` again. |
| Fix fails with **Push refused** | Someone pushed to the branch while the fix ran: `/fix` again. If the log mentions workflows, see the row above. |
| `/fix` on a pull request opened before you updated the pipeline | The pipeline's scripts always come from the default branch, but if the update changed `.github/workflows/` the fix stops and asks you to click **Update branch** first (see above). |
| **Unresolved merge conflicts remain** (fix) | The agent couldn't resolve every conflict with the base branch. Resolve them locally on the branch and push, or `/fix` with guidance on which side to keep. |
| Fix says **Nothing to change** | The agent found nothing to do for the request; its reason is in the comment. Be more specific after `/fix`. |
| A `/cancel` left a **⚠️ … failed or was cancelled** comment | Expected: the cancelled run reports itself. Nothing was pushed. |
| A database migration fails in **Run the checks** | The migration has an error; the log shows the SQL error. `/fix` with the error, or fix it yourself. |
| Build reports **blocked** | The agent explains why in the failure comment and the run log. Clarify in a comment starting with `/plan`, then approve again. |
| **Run the checks again** fails after the agent said they passed | The checks aren't deterministic (flaky tests, network). Fix `run-checks.sh` or the tests; nothing was committed. |
| A toolchain or package restore step fails | A missing setup step or credential (step 4). For cloud credentials, check the cloud side trusts this repository and branch. |
| **The commit header is not in the Conventional Commits format** | The agent's commit fields didn't form a valid header. Re-run the build; if it repeats, open an issue on this repository. |
| Your CI doesn't run on the pipeline's pull request | Expected (see 11.2). |
| A review lens failed | The summary still posts the other lenses and a ⚠️ comment links to the run. Comment `/review` to retry. |

To read a run's details: **Actions** → the run → the failed job → expand the failed step.

## 15. Updating and removing

**Updating** to a newer version of this repository: pull it, then compare its `templates/` with your repository.

1. Copy over every file you haven't customised: everything except `pipeline/scripts/run-checks.sh`,
   `.github/workflows/ai-build.yml` and your `CLAUDE.md`.
2. `ai-build.yml`: take the new template and paste your toolchain section back into the marked step.
3. `run-checks.sh`: keep your commands, but make its `if [[ "${CI:-}" == "true" ]]` block at the top match the
   template's. That block keeps tokens away from the code the checks run.
4. Delete pipeline files the new version no longer has (compare `pipeline/scripts/`, `.claude/skills/pipeline-*` and
   `.github/workflows/ai-*.yml` with `templates/`).
5. Run your checks, review the diff, and commit.

**Pausing:** disable the workflows under **Actions** → workflow → **⋯ → Disable workflow**.

**Removing:** delete `.github/workflows/ai-*.yml` (plan, build, review, cancel), `.github/ISSUE_TEMPLATE/ai-change-request.yml`,
`.claude/skills/pipeline-*` and `pipeline/`; delete the `CLAUDE_CODE_OAUTH_TOKEN` (or `ANTHROPIC_API_KEY`) secret
and the `ai:*` labels; and uninstall the Claude GitHub App from the repository if nothing else uses it.

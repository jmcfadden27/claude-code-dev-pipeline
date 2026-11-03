# Security model

![Trust boundaries](images/trust-boundaries.svg)

Two principles shape the design:

1. **The agent decides; deterministic steps act.** Agents read and, in the build stage, edit files. Everything with
   an effect outside the runner (comments, labels, commits, pushes, pull requests) is a plain workflow step.
2. **Only the project's people steer the agent.** Who can start a run, and whose text reaches the agent, is limited
   to collaborators.

## Threats and mitigations

| Threat | Mitigation | Where |
| --- | --- | --- |
| A stranger triggers runs on a public repository (cost, abuse) | Write access required, checked by the pipeline before any step and by `claude-code-action` before the agent; optional `PIPELINE_ALLOWED_USERS` allow-list; bots rejected by the action unless allowed | `require-write-access.sh`, action defaults |
| Prompt injection through issue comments | Comments from people without write access (checked through the API, since GitHub reports private organization members as CONTRIBUTOR) are replaced with a "withheld" note before the agent sees the thread | `trusted-authors.sh`, `issue-context.jq`, `pr-context.jq` (tested) |
| A pull request's branch changes the pipeline's own scripts | In fix mode the pipeline copies its scripts and settings from the default branch before checking out the pull request's branch, and runs those; only `run-checks.sh` (the project's checks) runs from the branch | `ai-build.yml` |
| Strangers start runs with command comments | Every job checks write access through the API before doing anything; `/cancel` acts only after that check | workflows, `require-write-access.sh` |
| Code the agent writes (tests) pushes, comments or labels | The build job, where that code runs, holds only a read-only token, and the agent's step is given that token (`github_token`) so `claude-code-action` mints no Claude GitHub App token. Comments happen in `prepare` (before any agent code exists) and `report`; pushing happens only in `publish`, a fresh runner | `ai-build.yml` |
| Code the agent writes redirects the push (rewrites the artifact so commits go to `main` or another pull request) | `publish.sh` takes the target only from `prepare` (the issue's new branch, or the pull request's own branch looked up through the API); the commits must sit on top of that branch; a build may only create a new branch, never overwrite one | `publish.sh` (tested) |
| The agent plants git hooks or config that run during the commit | Guardrails, not a boundary (the build job is untrusted anyway): the agent's tools can't edit `.git/` or common tool config in the home directory, and `commit-change.sh` ignores hooks, `core.fsmonitor` and global / system git config | `claude-settings.json`, `commit-change.sh` |
| A read-only agent (plan, review) is talked into copying a credential from its environment into its answer, which the pipeline then posts | The agents' Read tool is denied `/proc`, `/sys`, `$RUNNER_TEMP` and `~/.claude` | `claude-settings.json` |
| Text from the build job (which code the agent wrote can set) is posted as a pipeline comment and later trusted | Failure notices are capped, their @mentions broken, and the context scripts never treat them as pipeline text | `comment-failure.sh`, `issue-context.jq`, `pr-context.jq` |
| A command-like comment (`/approved`, `please /plan`) starts a stage | The gate checks the comment's first word is exactly the command | `require-write-access.sh` (tested) |
| Tokens reach the code the checks run | `run-checks.sh` drops the GitHub, OIDC, cloud and Claude variables and resets the `origin` URL before running project code; the agent can't read `.git/` or `$RUNNER_TEMP/secrets`, nor write under `$RUNNER_TEMP` (best effort; see residual risks) | `run-checks.sh`, `claude-settings.json` |
| Prompt injection through the issue body | A collaborator decides to run the pipeline on an issue; the docs say to read a stranger's issue before planning it | process |
| A pull request rewrites its own review prompts or scripts | Review jobs run prompts, settings and scripts from the base branch; the PR's code is checked out read-only in `pr/` without credentials | `ai-review.yml` |
| Fork pull requests | Rejected by the review gate and the fix stage (`isCrossRepository`); GitHub also withholds secrets from fork runs | `ai-review.yml`, `ai-build.yml` |
| A fix pushes something the PR's people didn't ask for | `/fix` needs write access; the request and the context come only from collaborators' comments; the fix pushes only to that pull request's own branch, never to the base | `gather-pr-context.sh`, `publish.sh` |
| A fix pushes unresolved merge conflicts | `commit-change.sh` refuses to commit while conflict markers remain in the files that conflicted; conflicts in files the agent may not change, or in binary files, stop the fix before the agent runs | `commit-change.sh`, `merge-base.sh` (tested) |
| The agent pushes, calls GitHub or exfiltrates over the network | No git, `gh`, curl, web or MCP tools: allowed tools are listed per stage, and deny rules block the rest | `--allowedTools`, `--disallowedTools`, `claude-settings.json` |
| The build agent weakens the quality gate | `run-checks.sh` and everything under `pipeline/`, `.github/` and `.claude/` are denied to `Edit` / `Write`; the workflow re-runs the checks itself; the tests reviewer looks for tests that can't fail | `claude-settings.json`, `ai-build.yml`, review lens |
| The agent reports success that isn't true | The workflow re-runs the checks and confirms files changed before it opens a pull request | `ai-build.yml`, `commit-change.sh` |
| Secrets leak into code or logs | Credentials only in GitHub secrets; `.env` files denied to `Read`; the build skill forbids writing secrets; `show_full_output` left off (public logs) | settings, skill |
| Runaway cost | Turn limits per agent, job timeouts, concurrency groups, runs start only from a person's command (the review follows a build the person approved) | workflows |
| Shell injection from issue text | Event text reaches scripts only through environment variables, never interpolated into `run:` blocks | workflows (checked by `tests/run.sh`) |
| An agent change merges without a person | The pipeline never approves or merges; branch protection should require a human approval | [setup](setup.md#9-recommended-repository-settings) |

## Permissions per job

| Workflow · job | `contents` | `issues` | `pull-requests` | Runs agent code? |
| --- | --- | --- | --- | --- |
| plan | read | write | — | no (read-only agent) |
| build · prepare | read | write | write | no |
| build · build | read | read | read | **yes** (agent + checks) |
| build · report | read | write | write | no |
| build · publish | **write** | write | write | no (fresh runner) |
| review · gate | read | write | write | no |
| review · reviewers | read | read | read | no (read-only agents) |
| review · summarize | read | write | write | no |
| cancel · gate | read | write | write | no |

No job has `id-token: write`: every Claude step is given its job's own token, so `claude-code-action` needs no OIDC
exchange and no Claude GitHub App. If your toolchain signs in to a cloud with OIDC, the build job needs
`id-token: write` (setup step 4); the cloud role should then allow only what the checks need.

## Residual risks

- **The issue body is trusted once a collaborator runs `/plan` on the issue.** Read requests from outside the project before
  starting the pipeline on them.
- **Code the agent writes runs in the build job.** Removing variables in `run-checks.sh` is a best effort: code
  running as the same user can still read its parent processes' environment. So assume that code can reach whatever
  the build job holds:
  - the job's read-only GitHub token (it can read the repository, nothing more);
  - the **Claude credential** (`CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY`), which it could use or send out.
    Review the tests in every pipeline pull request, keep tests free of network calls, and prefer an API key with a
    spending limit for repositories where that matters; rotate the credential if you suspect misuse;
  - anything your toolchain adds: a package-feed config (for example a CodeArtifact token in `$RUNNER_TEMP/secrets/`)
    or cloud credentials from OIDC. Give the build only **read** access to package feeds.

  It can also change files later steps of the build job use (the commit, the artifact), which is why nothing from
  that job decides where commits go.
- **Caches.** Code in the build job can reach the runner's cache token and save cache entries for the default branch,
  which other workflows on any branch may restore. Keep the setup actions' caches read-only in the build (setup
  step 4), and don't restore dependency caches in privileged workflows (release, deploy) of repositories that use the
  pipeline.
- **Command comments from strangers.** Concurrency groups are resolved before any job can check who commented, so on a
  public repository anyone's `/plan` or `/review` can cancel a run in progress (and `/approve` or `/fix` replace a
  queued one). Nothing runs for them. Limit interactions if needed (setup step 9).
- **Prompt-injection defences are layered, not absolute.** The agents' limited tools are what bound the damage if
  an injection succeeds: no agent can push, comment or reach the network.

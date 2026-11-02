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
| Prompt injection through issue comments | Comments from non-collaborators are replaced with a "withheld" note before the agent sees the thread | `issue-context.jq` (tested) |
| Prompt injection through the issue body | A collaborator decides to run the pipeline on an issue; the docs say to read a stranger's issue before labelling it | process |
| A pull request rewrites its own review prompts or scripts | Review jobs run prompts, settings and scripts from the base branch; the PR's code is checked out read-only in `pr/` without credentials | `ai-review.yml` |
| Fork pull requests | Rejected by the review gate (`isCrossRepository`); GitHub also withholds secrets from fork runs | `ai-review.yml` |
| The agent pushes, calls GitHub or exfiltrates over the network | No git, `gh`, curl, web or MCP tools: allowed tools are listed per stage, and deny rules block the rest | `--allowedTools`, `--disallowedTools`, `claude-settings.json` |
| Code the agent writes (tests) reaches GitHub | `GH_TOKEN` is set only on steps that call GitHub; checkouts use `persist-credentials: false`; the push step sets up git credentials after the agent has finished | workflows |
| The build agent weakens the quality gate | `run-checks.sh` and everything under `pipeline/`, `.github/` and `.claude/` are denied to `Edit` / `Write`; the workflow re-runs the checks itself; the tests reviewer looks for tests that can't fail | `claude-settings.json`, `ai-build.yml`, review lens |
| The agent reports success that isn't true | The workflow re-runs the checks and confirms files changed before it opens a pull request | `ai-build.yml`, `open-pr.sh` |
| Secrets leak into code or logs | Credentials only in GitHub secrets; `.env` files denied to `Read`; the build skill forbids writing secrets; `show_full_output` left off (public logs) | settings, skill |
| Runaway cost | Turn limits per agent, job timeouts, concurrency groups, runs start only from a person's label or command (the review follows a build the person approved) | workflows |
| Shell injection from issue text | Event text reaches scripts only through environment variables, never interpolated into `run:` blocks | workflows (checked by `tests/run.sh`) |
| An agent change merges without a person | The pipeline never approves or merges; branch protection should require a human approval | [setup](setup.md#10-recommended-repository-settings) |

## Permissions per job

| Job | `contents` | `issues` | `pull-requests` | `id-token` |
| --- | --- | --- | --- | --- |
| plan | read | write | — | write |
| build | write | write | write | write |
| review: gate | read | — | read | — |
| review: reviewers | read | read | read | write |
| review: summarize | read | write | write | — |

`id-token: write` is required by `claude-code-action` for its GitHub App authentication. Jobs that don't run the
action don't get it.

## Residual risks

- **The issue body is trusted once a collaborator labels the issue.** Read requests from outside the project before
  starting the pipeline on them.
- **`run-checks.sh` runs project code, including tests the agent wrote.** The workflows give `GH_TOKEN` only to the
  steps that call GitHub and check out without stored git credentials, so that code gets no credential from the
  workflow, in its environment or in `.git/config`. `claude-code-action` manages its own GitHub App token
  internally; see its [security documentation](https://github.com/anthropics/claude-code-action/blob/main/docs/security.md)
  for how it handles subprocess environments. Keep other secrets out of the build job; the Claude credential is
  passed only to the action step.
- **Prompt-injection defences are layered, not absolute.** The agents' limited tools are what bound the damage if
  an injection succeeds: no agent can push, comment or reach the network.

# Changelog

All notable changes to this project are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [semantic versioning](https://semver.org).

## [0.1.0] - 2026-11-12

First public release.

### Pipeline

- One GitHub Actions workflow runs every comment command: `/plan`, `/approve`, `/fix`, `/review` and `/cancel`. Each
  run is named after its command and the issue, and answers with a reaction and one status comment that ends as done
  or failed.
- **Plan:** the agent studies the code and posts a plan with questions; acceptance criteria are made checkable, and a
  plan with open questions or no criteria is not ready. `/approve` builds only a ready plan, and every later stage
  reads the issue thread only up to that `/approve`.
- **Build:** the agent can edit files and run the project's checks only; the workflow runs the checks again, and a
  separate publish job with the only write token pushes the branch and opens the pull request.
- **Review:** four independent reviewers (correctness, security, tests, requirements) run in parallel; findings with
  confidence 80+ are merged into one new comment per review. A re-review checks the last review's findings first and
  reports which were fixed.
- **Fix:** `/fix` on the pull request merges the latest base, resolves conflicts, fixes the review's findings or what
  was asked, and pushes to the same pull request.
- Every commit and pull request title follows Conventional Commits, assembled and checked by the workflow.
- Trust rules: only collaborators can trigger the pipeline, comments from anyone else are withheld from the agents,
  fork pull requests are never handled, and review prompts always come from the base branch.

### Tooling

- `scripts/install.sh` copies the pipeline into a repository; `scripts/create-labels.sh` creates its status labels.
- `tests/run.sh` checks the deterministic parts offline: scripts, schemas, renderers, trust rules, merging,
  committing, publishing and the installer.

[0.1.0]: https://github.com/jmcfadden27/claude-code-dev-pipeline/releases/tag/v0.1.0

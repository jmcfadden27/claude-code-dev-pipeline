# Claude Code Dev Pipeline

A reference implementation of an **AI development pipeline on GitHub**: a person describes a change in an issue, and
[Claude Code](https://code.claude.com) agents plan it, ask questions, build it, test it, open a pull request and
review it — with a person approving every stage and merging every change.

![Pipeline overview](docs/images/pipeline-overview.svg)

This repository contains everything needed to add the pipeline to a project: GitHub Actions workflows, agent
prompts (Claude Code skills), JSON output contracts, the glue scripts, an installer and an offline test suite.
The workflow files live under [`templates/`](templates/) so nothing runs in this repository itself.

## Why

Coding agents can write code. The hard part in a real team is everything around it: knowing what to build,
keeping a person in control, limiting what an agent can touch, proving the result works, and getting an honest
review. This pipeline is built around those concerns rather than around the agent:

| Concern | How the pipeline handles it |
| --- | --- |
| Building the wrong thing | A **plan stage** studies the code and posts a plan with questions on the issue. Nothing is built until a person approves it. |
| Losing control | **A person starts every stage** (a label or a `/command`) and **merges every change**. Agents never approve or merge. |
| Agents with too much power | **Least privilege per stage**: the planner and reviewers can only read; the builder can edit files and run one script. No agent has git, GitHub or network tools. |
| "It works on my machine" | **Trust, but verify**: the builder runs the checks until they pass, then the workflow runs them again itself before it opens a pull request. |
| Unstructured agent output | Every agent returns **JSON validated against a schema**. Deterministic workflow steps turn it into comments, labels, commits and pull requests. |
| One reviewer's blind spots | **Four independent reviewers** (correctness, security, tests, requirements) run in parallel without seeing each other's findings; their results are merged and ranked. |
| Prompt injection from strangers | Only collaborators can trigger the pipeline, comments from anyone else are withheld from the agents, fork pull requests are never reviewed, and review prompts always come from the base branch. |

## How it works

```mermaid
sequenceDiagram
    autonumber
    actor You
    participant GH as GitHub (issue / PR)
    participant WF as Workflow steps
    participant AG as Claude Code agent

    You->>GH: Open issue, add label ai:plan
    GH->>WF: issues.labeled
    WF->>WF: Write-access check, gather issue thread
    WF->>AG: /pipeline-plan (read-only tools)
    AG-->>WF: plan.json (summary, steps, files, risks, questions)
    WF->>GH: Plan comment + ai:needs-answers
    You->>GH: Answer, comment /plan
    GH->>WF: issue_comment
    WF->>AG: /pipeline-plan with the answers
    AG-->>WF: plan.json (no questions)
    WF->>GH: Plan comment + ai:plan-ready
    You->>GH: Add label ai:approved
    GH->>WF: issues.labeled
    WF->>AG: /pipeline-build (edit files, run checks)
    AG-->>WF: build-report.json
    WF->>WF: Run checks again, commit, push branch
    WF->>GH: Pull request "Closes #N"
    You->>GH: Add label ai:review
    par Four independent reviewers
        WF->>AG: /pipeline-review correctness
        WF->>AG: /pipeline-review security
        WF->>AG: /pipeline-review tests
        WF->>AG: /pipeline-review requirements
    end
    AG-->>WF: findings.json ×4
    WF->>GH: One merged review comment
    You->>GH: Review and merge
```

| Stage | Started by | Agent can | Workflow does | Result |
| --- | --- | --- | --- | --- |
| **Plan** | label `ai:plan` or comment `/plan` | read the code and the issue thread | posts the plan, labels the issue | plan + questions on the issue |
| **Build** | label `ai:approved` | edit files, run `run-checks.sh` | re-runs checks, commits, pushes, opens the PR | pull request that closes the issue |
| **Review** | label `ai:review` or comment `/review` | read the diff and the code (×4 lenses) | merges and ranks findings, posts one comment | review comment on the PR |
| **Merge** | you | — | — | merged change |

The issue thread is the pipeline's memory. Agents keep nothing between runs: each run reads the request, earlier
plans, answers and approvals from the thread, so every decision is visible and auditable on GitHub.

More detail: [architecture](docs/architecture.md) · [security model](docs/security.md) ·
[design decisions](docs/design-decisions.md) · [worked example](docs/walkthrough.md)

## Commit messages

Every commit and pull request title the pipeline creates follows
[Conventional Commits](https://www.conventionalcommits.org):

```text
type(scope)!: summary

Implements the approved plan on #12.

BREAKING CHANGE: what breaks and what to do about it     (breaking changes only)
Closes #12
```

| Part | Rule | Example |
| --- | --- | --- |
| `type` | One of the types below | `feat` |
| `scope` | The area changed, lowercase | `api`, `android`, `infra` |
| `!` | Only for a breaking change, together with a `BREAKING CHANGE:` footer | `feat(api)!:` |
| `summary` | Imperative, lowercase start, no trailing period, at most 72 characters | `add optional due dates to tasks` |

| Type | Use for |
| --- | --- |
| `feat` | A new capability |
| `fix` | A bug fix |
| `refactor` | A code change without a behaviour change |
| `perf` | A performance improvement |
| `test` | Tests only |
| `docs` | Documentation only |
| `ci` | CI pipeline or workflow changes |
| `chore` | Maintenance and tooling |

Examples: `feat(tasks): add optional due dates to tasks` · `fix(api)!: reject past due dates` ·
`ci(infra): include the documents stack in plan and apply`

**How it is enforced:** the build agent doesn't write the message. It returns the type, scope, summary and
breaking-change details as separate fields, which the schema constrains (the type must be one from the table). The
workflow assembles the message ([`commit-message.jq`](templates/pipeline/scripts/commit-message.jq)), checks the
header against the format, and stops instead of committing if it doesn't match. The same rules are in
[`CLAUDE.md.example`](templates/CLAUDE.md.example), so interactive Claude Code sessions follow them too.

## Repository layout

```text
templates/                         copied into your repository by scripts/install.sh
├── .github/workflows/
│   ├── ai-plan.yml                stage 1: plan
│   ├── ai-build.yml               stage 2: build, verify, open the PR
│   └── ai-review.yml              stage 3: 4 parallel reviewers + merged comment
├── .github/ISSUE_TEMPLATE/
│   └── ai-change-request.yml      structured change request (goal, acceptance criteria, scope)
├── .claude/skills/
│   ├── pipeline-plan/SKILL.md     agent prompt for each stage
│   ├── pipeline-build/SKILL.md
│   └── pipeline-review/SKILL.md
├── pipeline/
│   ├── claude-settings.json       deny rules for every agent run
│   ├── schemas/                   JSON contracts for agent output
│   └── scripts/                   deterministic glue (bash + jq): gate, context, render, post, open PR
└── CLAUDE.md.example              project rules every agent follows
scripts/
├── install.sh                     copy the templates into a repository (never overwrites)
└── create-labels.sh               create the pipeline's labels
tests/run.sh                       offline checks: syntax, schemas, renderers, trust rules, installer, shellcheck
docs/                              architecture, security, design decisions, setup, walkthrough, diagrams
```

## Quick start

```bash
git clone https://github.com/<you>/claude-code-dev-pipeline
claude-code-dev-pipeline/scripts/install.sh /path/to/your-repo
```

Then follow [docs/setup.md](docs/setup.md): set your build and test command in `pipeline/scripts/run-checks.sh`,
install the Claude GitHub App, add a `CLAUDE_CODE_OAUTH_TOKEN` secret (from `claude setup-token`, using a Claude
Pro / Max subscription) or an `ANTHROPIC_API_KEY`, create the labels, and open an issue.

## Cost and limits

- **On demand only.** Nothing runs on push or on a schedule; every run starts from a person's label or command.
- **Bounded runs.** Each agent has a turn limit (`--max-turns`) and each job a timeout; concurrency groups cancel
  superseded plan and review runs.
- **Subscription or API.** With a subscription token, runs count against that person's plan limits, shared with
  their interactive use. The multi-agent review is the most expensive stage, so it only runs when asked for.
- **GitHub Actions minutes** are used by every job.

## Testing

```bash
tests/run.sh
```

Runs offline, with no GitHub access and no AI: script syntax and shellcheck, JSON and YAML validity, fixtures
against the schemas, the renderers against expected output, the trust rules (an outsider's comment never reaches
the agent; duplicate findings merge at the highest severity), and the installer (never overwrites an existing file).

## Status

A reference implementation, written against the documented inputs of
[`anthropics/claude-code-action@v1`](https://github.com/anthropics/claude-code-action) and the Claude Code CLI
(November 2026). The deterministic parts are covered by `tests/run.sh`; the GitHub and agent interactions should be
tried in a sandbox repository before relying on them. Known limits are listed in
[design decisions](docs/design-decisions.md#known-limits).

## Disclaimer

This is a reference implementation shared for learning and demonstration. It is provided **as is, without warranty
of any kind**, under the [MIT License](LICENSE). You use it entirely at your own risk:

- You are responsible for reviewing and testing it before using it in any repository, and for every change it
  produces. AI-generated code can be wrong, insecure or incomplete; review it before merging.
- You are responsible for your own credentials, access settings and security configuration.
- You are responsible for any costs it incurs, including Claude usage, API charges and GitHub Actions minutes.
- It is an independent project, not affiliated with or endorsed by Anthropic or GitHub.

The author is not liable for any damages, losses, costs or other consequences arising from its use.

## Author

**Jim McFadden**

Released under the [MIT License](LICENSE).

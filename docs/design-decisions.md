# Design decisions

Short records of the choices behind the pipeline, with the alternatives considered.

### 1. A person starts the work

**Decision:** a label or `/plan` starts planning and a label approves the build; the review then runs automatically on
the pull request the build opened, and can be re-run with `/review`. Nothing runs on push or on a schedule.
**Why:** the expensive mistakes in AI-assisted development are building the wrong thing and merging something
nobody understood. Explicit gates keep the requester in the loop at the two points that matter (plan approval and
merge) and keep cost proportional to use.
**Alternative:** fully automatic issue-to-PR. Faster, but it removes the approval step and spends agent time on
requests nobody has confirmed.

### 2. Plan, then build — in separate runs

**Decision:** the plan stage can't edit anything; the build stage implements only an approved plan.
**Why:** a plan is cheap to review and cheap to change. Separating them also means the build agent starts from a
written, approved specification in the thread rather than from its own first reading of the request.
**Alternative:** one agent that asks questions and builds in the same run. Agents in CI can't wait for an answer,
so questions would end the run anyway.

### 3. The issue thread is the memory

**Decision:** each run rebuilds its context from the issue thread; nothing is stored between runs.
**Why:** it is auditable (every input is on GitHub), it survives runner restarts, and it makes "re-plan with my
answers" a simple re-run.

### 4. Agents decide; workflow steps act

**Decision:** agents return JSON validated against a schema; jq and the GitHub CLI turn it into comments, labels,
commits and pull requests. No agent has git, GitHub or network tools.
**Why:** side effects become deterministic, testable and reviewable code. The blast radius of a confused or
manipulated agent is limited to files in the runner's working tree.
**Alternative:** let the agent use the GitHub MCP tools directly. Fewer moving parts, but every capability the agent
holds is one a prompt injection could use.

### 5. Trust, but verify

**Decision:** the build workflow runs `run-checks.sh` itself after the agent reports success, and confirms files
changed.
**Why:** an agent's report is a claim. The pull request is opened only on evidence the pipeline produced.

### 6. Independent reviewers with one lens each

**Decision:** four parallel reviewers (correctness, security, tests, requirements), each unaware of the others,
merged by a deterministic step.
**Why:** a single reviewer anchors on the first problems it finds. Narrow lenses go deeper, parallel jobs keep wall
time flat, and agreement between independent reviewers is a useful signal (the summary shows which lenses found
each issue). The requirements lens checks the diff against the approved plan, closing the loop with stage 1.
**Alternative:** one reviewer with a long checklist. Cheaper, and a reasonable setting for small changes: drop lenses
from the matrix.

### 7. Prompts as Claude Code skills

**Decision:** each stage's prompt is a skill in `.claude/skills/`, invoked as the action's `prompt`.
**Why:** prompts are versioned and reviewed with the code, and can be tried locally in an interactive session
before they reach CI.

### 8. Subscription token or API key

**Decision:** the templates use `claude_code_oauth_token` (from `claude setup-token`) and document the switch to an
API key.
**Why:** an individual developer can run the pipeline on their own Claude Pro / Max plan without API billing. For a
team, an API key avoids tying the pipeline to one person's subscription and limits.

### 9. Fix on the same pull request

**Decision:** `/fix` updates the existing pull request: the base is merged in first, the agent resolves conflicts and
fixes the review's findings or the request, the workflow re-checks and pushes to the same branch, and the review runs
again.
**Why:** that is how a team works with a human reviewer. Starting over from a new plan for a one-line change wastes a
full build and loses the review history.

### 10. Commands for every step, and `/cancel`

**Decision:** `/plan`, `/approve`, `/fix`, `/review` and `/cancel`, alongside the labels.
**Why:** a comment is quicker than the label menu (which only saves when it closes), works on mobile, leaves a visible
record, and gives a way to stop a run that's going wrong.

### 11. Build without write access, publish separately

**Decision:** the build job (agent and checks) has read-only repository access and commits locally; a separate
publish job on a fresh runner, the only one that can push, applies the bundled commits and opens or updates the pull
request.
**Why:** the checks run code the agent wrote. Anything sharing a runner with a write token could reach it, by
changing later steps or the environment they inherit. Separating the jobs removes that path entirely.

## Known limits

- **The repository's own CI doesn't start on the pipeline's pull requests.** GitHub doesn't start workflows from
  pushes made with `GITHUB_TOKEN`. The build stage runs the checks itself; to also run CI automatically, push with a
  GitHub App token or a fine-grained token instead (`publish.sh`; see setup step 10).
- **Review is advisory.** The reviewers comment; they don't request changes through GitHub's review API or block a
  merge. Branch protection and the human reviewer do that.
- **Single repository.** Changes that span repositories aren't supported.

# Walkthrough: one change, end to end

A small tasks API gets due dates. Every comment and description below is what the pipeline's renderers produce from
the agents' JSON. The same JSON is used as test fixtures, so these examples are checked by `tests/run.sh`.

| Step | Who | What happens | Artifact |
| --- | --- | --- | --- |
| 1 | Requester | Opens issue #12 with the change-request form, adds `ai:plan` | [01-issue.md](../examples/01-issue.md) |
| 2 | Plan agent | Reads the issue and the code; returns a plan with two questions | [02-plan-with-questions.md](../examples/02-plan-with-questions.md) |
| 3 | Pipeline | Posts the plan, labels the issue `ai:needs-answers` | |
| 4 | Requester | Answers in one comment starting with `/plan` | [03-answers.md](../examples/03-answers.md) |
| 5 | Plan agent | Re-plans with the answers; no questions left | [04-plan-ready.md](../examples/04-plan-ready.md) |
| 6 | Pipeline | Posts the plan, labels the issue `ai:plan-ready` | |
| 7 | Requester | Adds `ai:approved` | |
| 8 | Build agent | Implements the plan; one ordering test fails, it fixes it; checks pass | |
| 9 | Pipeline | Runs the checks again, commits to `ai/issue-12-…`, opens the pull request | [05-pull-request.md](../examples/05-pull-request.md) |
| 10 | Pipeline | Starts the review stage on the new pull request automatically | |
| 11 | 4 review agents | Review in parallel; correctness and tests independently find the same time-zone bug | |
| 12 | Pipeline | Merges the findings into one comment, ranked by severity | [06-review.md](../examples/06-review.md) |
| 13 | Requester | Comments `/fix compare dates in UTC, and add the time-zone test` on the pull request | [07-fix.md](../examples/07-fix.md) |
| 14 | Fix agent | Merges the latest base, fixes the comparison, adds the test; checks pass | |
| 15 | Pipeline | Runs the checks again, pushes to the same pull request, comments what changed; the review runs again with no findings | [07-fix.md](../examples/07-fix.md) |
| 16 | Requester | Merges | |

## What to notice

- **The agent asked instead of guessing** (step 2). Whether past due dates are valid and whether completed tasks
  count as overdue are product decisions, so the plan stage asked. It decided the technical details itself.
- **The thread is the memory** (step 5). The second plan run had no memory of the first; it read the plan and the
  answers from the issue.
- **An outsider's comment never reached the agent** (step 4). See [03-answers.md](../examples/03-answers.md).
- **The pull request was opened on evidence** (step 9). The agent reported passing checks; the workflow ran them
  again before opening it.
- **Independent reviewers agreeing is a signal** (step 11). The time-zone bug is listed once, at the highest
  severity either reviewer gave it, with both lenses named.
- **Findings were fixed where they were found** (steps 13–15). No new plan or new pull request: `/fix` changed the
  same pull request and the review ran again.
- **A person decided at every gate**: asking for a plan (step 1), approving it (step 7), asking for the fix (step 13)
  and merging (step 16).

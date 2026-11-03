# Fixing the review's finding on the pull request

_The requester comments on the pull request:_

> /fix compare dates in UTC, and add the time-zone test

_The fix stage brings the branch up to date with `main`, the agent makes the change and runs the checks, the workflow
runs them again, then pushes one commit to the same pull request:_

```text
fix(tasks): compare due dates in utc

Updates pull request #14 from its review and comments.

Refs #12
```

_and comments on the pull request:_

> 🔧 **fix(tasks): compare due dates in utc**
>
> The overdue check now compares against the start of today in UTC, so a task due today is never overdue in any time
> zone. Added a test that runs the ordering with `TZ=America/Los_Angeles`.
>
> - `src/tasks/task-routes.ts`: compare against the start of today in UTC
> - `test/tasks.test.ts`: time-zone test for the overdue ordering

_The review runs again in the same run and updates the review comment: no findings. The `/fix` comment has 👀 and
then 👍, and its status comment reads:_

> ✅ **Fix** done · [pushed the fix](#) · [AI review](#): no blocking findings · [run](#)

_The requester merges._

The commit message is built by [`commit-message.jq`](../templates/pipeline/scripts/commit-message.jq) and checked by
`tests/run.sh` (`tests/expected/commit-message-fix.md`).

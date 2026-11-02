_Pull request description written by the pipeline. Title: **feat(tasks): add optional due dates to tasks**._

<!-- ai-pipeline:pr -->
Closes #12

## Summary

Tasks can now have an optional due date. GET /tasks lists open overdue tasks first, then by due date, then by creation time. Past due dates are accepted; completed tasks are never overdue.

## Changes

- `migrations/0007_add_task_due_date.sql`: Adds the nullable due_date column
- `src/tasks/task.ts`: dueDate on the model and the request types
- `src/tasks/task-validator.ts`: Validates dueDate as an ISO date
- `src/tasks/task-routes.ts`: New ordering for GET /tasks
- `test/tasks.test.ts`: 9 new tests: create, update, validation, ordering

## Checks

- Agent run: passed. Lint and 58 tests passed on the second run (first run: one ordering test failed, fixed).
- Pipeline re-run: passed (the pipeline runs `pipeline/scripts/run-checks.sh` itself before opening this PR).

## Follow-ups (not in this PR)

- Show due dates in the web client

---
_Opened by the AI pipeline from the approved plan on #12. Add the `ai:review` label or comment `/review` for an AI review. A person reviews and merges._

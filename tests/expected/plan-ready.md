<!-- ai-pipeline:plan -->
## 🗺️ Implementation plan

Add an optional due date to tasks and list overdue open tasks first.

### Approach

As before, with the answers applied: due dates in the past are allowed, and only open tasks count as overdue.

### Steps

1. Add migration 0007_add_task_due_date with a nullable due_date column
2. Add dueDate to the Task model, the create and update request types and TaskValidator
3. Sort GET /tasks: open overdue tasks first, then by due date, then by creation time
4. Add tests for create, update, validation and ordering (including completed overdue tasks)

### Files

- `migrations/0007_add_task_due_date.sql` (create)
- `src/tasks/task.ts` (modify)
- `src/tasks/task-validator.ts` (modify)
- `src/tasks/task-routes.ts` (modify)
- `test/tasks.test.ts` (modify)

### Risks

_None._

### ✅ Ready to build

_Add the `ai:approved` label to build this plan._

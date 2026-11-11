_Comment posted by the pipeline on issue #12 after the answers._

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

### Acceptance criteria

1. A task can be created and updated with an optional due date, including one in the past  
   _Check:_ API tests create and update tasks with no due date, a future date and a past date
2. GET /tasks lists open overdue tasks first; completed tasks are never overdue  
   _Check:_ An API test lists open and completed tasks with past, future and no due dates and checks the order

### Risks

_None._

### ✅ Ready to build

_Comment `/approve` to build this plan._

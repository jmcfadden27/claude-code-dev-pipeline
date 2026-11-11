<!-- ai-pipeline:plan -->
## 🗺️ Implementation plan

Add an optional due date to tasks and list overdue tasks first.

### Approach

Add a nullable due_date column through a new migration, expose it on the task model and the create/update endpoints, and sort GET /tasks by overdue first, then by due date, then by creation time. Validation follows the existing TaskValidator pattern.

### Steps

1. Add migration 0007_add_task_due_date with a nullable due_date column
2. Add dueDate to the Task model, the create and update request types and TaskValidator
3. Sort GET /tasks: overdue first, then by due date, then by creation time
4. Add tests for create, update, validation and ordering

### Files

- `migrations/0007_add_task_due_date.sql` (create)
- `src/tasks/task.ts` (modify)
- `src/tasks/task-validator.ts` (modify)
- `src/tasks/task-routes.ts` (modify)
- `test/tasks.test.ts` (modify)

### Acceptance criteria

1. A task can be created and updated with an optional due date  
   _Check:_ API tests create and update tasks with and without dueDate
2. GET /tasks lists overdue tasks first  
   _Check:_ An API test lists tasks with past, future and no due dates and checks the order

### Risks

- Existing API clients ignore the new field; ordering of GET /tasks changes for everyone

### ❓ Questions before I build

1. Should a due date in the past be rejected when a task is created, or allowed?
2. Should completed tasks that are past their due date still count as overdue?

_Reply in one comment that starts with `/plan` followed by your answers; the plan is updated from them._

<!-- ai-pipeline:review -->
## 🔍 AI review of 3f9c2e1

| Lens | Verdict | Findings |
| --- | --- | --- |
| correctness | ❌ changes requested | 1 |
| requirements | ✅ approve | 0 |
| security | ✅ approve | 0 |
| tests | ✅ approve | 2 |

### 🔴 Overdue check compares dates in the server's time zone

`src/tasks/task-routes.ts:42` · high · correctness, tests

A task due 2026-11-02 created by a user in UTC-8 is listed as overdue at 16:00 their time, because new Date() is compared with a date-only value parsed as UTC midnight.

**Suggestion:** Compare against the start of today in UTC, or store and compare date-only values.

### 🟡 Ordering test relies on insertion order for equal due dates

`test/tasks.test.ts` · low · tests

Two tasks with the same due date are expected in creation order, but they are created in the same millisecond on fast machines.

**Suggestion:** Give the two tasks explicit, different createdAt values.

**Result: changes requested** by 1 of 4 reviewers.

_Independent reviewers, one per lens, each without the others' output. Advisory only: a person reviews and merges._

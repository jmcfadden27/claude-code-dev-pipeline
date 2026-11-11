<!-- ai-pipeline:review -->
## 🔍 AI review of 3f9c2e1

| Lens | Verdict | Findings | Files checked |
| --- | --- | --- | --- |
| correctness | ❌ changes requested | 1 | 2 |
| requirements | ✅ approve | 0 | 2 |
| security | ✅ approve | 0 | 2 |
| tests | ✅ approve | 2 | 3 |

### 🔴 Overdue check compares dates in the server's time zone

`src/tasks/task-routes.ts:42` · high · confidence 95 · correctness, tests

A task due 2026-11-02 created by a user in UTC-8 is listed as overdue at 16:00 their time, because new Date() is compared with a date-only value parsed as UTC midnight.

**Suggestion:** Compare against the start of today in UTC, or store and compare date-only values.

### 🟡 Ordering test relies on insertion order for equal due dates

`test/tasks.test.ts` · low · confidence 88 · tests

Two tasks with the same due date are expected in creation order, but they are created in the same millisecond on fast machines.

**Suggestion:** Give the two tasks explicit, different createdAt values.

**Result: changes requested** by 1 of 4 reviewers.

_1 finding(s) below 80 confidence left out._

### ⚠️ Not checked

- `test/fixtures/large-dataset.json` (tests): too large to read in the time available

_Independent reviewers, one per lens, each without the others' output. Advisory only: a person reviews and merges._
<!-- ai-pipeline:findings W3sibGVuc2VzIjpbImNvcnJlY3RuZXNzIiwidGVzdHMiXSwic2V2ZXJpdHkiOiJoaWdoIiwiZmlsZSI6InNyYy90YXNrcy90YXNrLXJvdXRlcy50cyIsImxpbmUiOjQyLCJ0aXRsZSI6Ik92ZXJkdWUgY2hlY2sgY29tcGFyZXMgZGF0ZXMgaW4gdGhlIHNlcnZlcidzIHRpbWUgem9uZSIsImRldGFpbCI6IkEgdGFzayBkdWUgMjAyNi0xMS0wMiBjcmVhdGVkIGJ5IGEgdXNlciBpbiBVVEMtOCBpcyBsaXN0ZWQgYXMgb3ZlcmR1ZSBhdCAxNjowMCB0aGVpciB0aW1lLCBiZWNhdXNlIG5ldyBEYXRlKCkgaXMgY29tcGFyZWQgd2l0aCBhIGRhdGUtb25seSB2YWx1ZSBwYXJzZWQgYXMgVVRDIG1pZG5pZ2h0LiJ9LHsibGVuc2VzIjpbInRlc3RzIl0sInNldmVyaXR5IjoibG93IiwiZmlsZSI6InRlc3QvdGFza3MudGVzdC50cyIsImxpbmUiOjAsInRpdGxlIjoiT3JkZXJpbmcgdGVzdCByZWxpZXMgb24gaW5zZXJ0aW9uIG9yZGVyIGZvciBlcXVhbCBkdWUgZGF0ZXMiLCJkZXRhaWwiOiJUd28gdGFza3Mgd2l0aCB0aGUgc2FtZSBkdWUgZGF0ZSBhcmUgZXhwZWN0ZWQgaW4gY3JlYXRpb24gb3JkZXIsIGJ1dCB0aGV5IGFyZSBjcmVhdGVkIGluIHRoZSBzYW1lIG1pbGxpc2Vjb25kIG9uIGZhc3QgbWFjaGluZXMuIn1d -->

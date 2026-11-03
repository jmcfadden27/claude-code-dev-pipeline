# Pull request #14: feat(tasks): add optional due dates to tasks

## What you were asked to fix

compare dates in UTC, and add the time-zone test

## Description

<!-- ai-pipeline:pr -->
Closes #12

## Summary

Tasks can now have an optional due date.

## Conversation (oldest first; the AI review starts with <!-- ai-pipeline:review -->)

### @github-actions · 2026-11-02T16:10:00Z

<!-- ai-pipeline:review -->
## 🔍 AI review of 3f9c2e1

(review text)

### @drive-by-user · 2026-11-02T16:20:00Z

_(withheld: not from a repository collaborator)_

### @jim · 2026-11-02T16:30:00Z

/fix compare dates in UTC, and add the time-zone test

### @github-actions · 2026-11-02T16:10:00Z

_(the pipeline's status notice: not shown)_

### @jim · 2026-11-02T16:30:00Z

/fixed it locally, ignore this

## Comments on lines of code

### `src/tasks/task-routes.ts:42` · @jim

This should use the start of today in UTC.

### `README.md:1` · @drive-by-user

_(withheld: not from a repository collaborator)_

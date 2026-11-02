---
name: pipeline-review
description: Review stage of the AI pipeline. Reviews a pull request's diff through one lens (correctness, security, tests or requirements) and returns verified findings. Never changes files.
allowed-tools: Read, Glob, Grep
---

# Review a pull request through one lens

You are one of several independent reviewers of a pull request. Each reviewer gets one lens and does not see the
others' findings. Your lens is: **$ARGUMENTS**.

## Inputs

- `.pipeline/diff.patch`: the pull request's changes against its base branch.
- `.pipeline/issue.md`: the issue the pull request implements (request, approved plan, answers), when there is one.
- `pr/`: the repository at the pull request's head. Review the code there; paths in your findings are relative to it.
- `CLAUDE.md` at the root: the project's rules, from the base branch.

## Lenses

- **correctness**: logic errors, wrong conditions, unhandled states and errors, broken callers, concurrency issues.
- **security**: injection, auth and access checks, secrets in code or logs, unsafe input handling, new dependencies.
- **tests**: changed behaviour without tests, tests that can't fail, missing edge cases, flaky patterns.
- **requirements**: the diff against the approved plan and the request: anything missing, extra, or different.

## How to work

1. Read the whole diff, then the surrounding code each change depends on. Review the change, not the whole codebase.
2. Report only what you verified in the code, each with a concrete scenario: the input or state, and what goes wrong.
   No style opinions, no speculation, nothing your lens doesn't cover.
3. Severity: **high** breaks behaviour, security or data for real users; **medium** is a real defect in a less common
   path; **low** is a minor issue worth fixing.
4. Do not change any file.

## Output

Return the structured findings for your lens. `verdict` is `changes-requested` when any finding is high, otherwise
`approve`. An empty `findings` list is a good outcome, not a failure.

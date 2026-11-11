---
name: pipeline-review
description: Review stage of the AI pipeline. Reviews a pull request's diff through one lens (correctness, security, tests or requirements) and returns verified findings. Never changes files.
allowed-tools: Read, Glob, Grep
---

# Review a pull request through one lens

You are one of several independent reviewers of a pull request. Each reviewer gets one lens and does not see the
others' findings. Your lens is: **$ARGUMENTS**.

## Inputs

- `.pipeline/diff.patch`: the pull request's changes against its base branch; `.pipeline/diff-files.txt` lists the
  changed files.
- `.pipeline/pr.md`: the pull request's description (the build agent's summary, checks and follow-ups, including
  anything it says it could not verify) and the collaborators' conversation.
- `.pipeline/issue.md`: the issue the pull request implements (request, approved plan, answers), when there is one,
  up to the `/approve` the pull request was built from.
- `pr/`: the repository at the pull request's head. Review the code there; paths in your findings are relative to it.
- `CLAUDE.md` at the root: the project's rules, from the base branch.

## Lenses

- **correctness**: logic errors, wrong conditions, unhandled states and errors, broken callers, concurrency issues.
- **security**: injection, auth and access checks, secrets in code or logs, unsafe input handling, new dependencies.
- **tests**: changed behaviour without tests, tests that can't fail, missing edge cases, flaky patterns.
- **requirements**: the diff against the approved plan and the request: anything missing, extra, or different. Check
  each of the plan's acceptance criteria: is it met, and does the check the plan names for it exist and test it?

## How to work

1. Read the whole diff, then every changed file your lens covers **in full** in `pr/`, and the surrounding code each
   change depends on. Review the change, not the whole codebase. On a large change, start with the riskiest files
   (database migrations, access checks, anything that writes data) so they are never the ones left unchecked.
   - When the change **copies or redefines existing code** (for example a migration that redefines a function an
     earlier migration created), find the earlier version and compare the two line by line, by reading both: any
     difference other than the intended one is a finding.
   - When the description or follow-ups in `.pipeline/pr.md` say something **was not verified** (for example "the
     reviewer should diff …"), check it yourself if your lens covers it, and report what you found.
2. Report only what you verified in the code, each with a concrete scenario: the input or state, and what goes wrong.
   No style opinions, no speculation, nothing your lens doesn't cover.
3. Severity: **high** breaks behaviour, security or data for real users; **medium** is a real defect in a less common
   path; **low** is a minor issue worth fixing.
4. Confidence (0–100): how sure you are, after checking the code, that the finding is a real defect a person would
   want fixed. Findings below the pipeline's minimum (80 by default) are not posted, so don't pad the list: an empty list
   is a good result.
5. Do not change any file.
6. Report your coverage honestly: `coverage.filesChecked` lists every changed file you read in full and checked;
   `coverage.notChecked` lists every relevant file or claim you did not check (for example you ran out of time, or a
   comparison you could not make) and why. An empty `findings` list with an honest coverage is a good result; an
   empty list that hides what you skipped is not.

## Output

Return the structured findings for your lens. `verdict` is `changes-requested` when any finding with confidence
80 or more is high, otherwise `approve`. An empty `findings` list is a good outcome, not a failure.

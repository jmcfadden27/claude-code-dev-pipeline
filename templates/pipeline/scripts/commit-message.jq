# Input: the agent's report (schemas/build-report.schema.json). Args: $kind = build | fix, $issue = the issue number
# (may be empty for a fix), $pr = the pull request number (fix only), $note = an extra body line (may be empty).
# Output: the commit message in the Conventional Commits format. For a build, the first line is also the pull request
# title.
#
#   type(scope)!: summary
#
#   Implements the approved plan on #N.            (fix: Updates pull request #P from its review and comments.)
#
#   BREAKING CHANGE: ...      (only when breaking)
#   Closes #N                 (build only)

.commit as $c
| "\($c.type)(\($c.scope))\(if $c.breaking then "!" else "" end): \($c.summary)",
  "",
  (if $kind == "fix" then "Updates pull request #\($pr) from its review and comments."
   else "Implements the approved plan on #\($issue)." end),
  (if ($note // "") != "" then $note else empty end),
  "",
  (if $c.breaking then "BREAKING CHANGE: \($c.breakingChange)" else empty end),
  (if $kind == "fix" then (if $issue != "" then "Refs #\($issue)" else empty end) else "Closes #\($issue)" end)

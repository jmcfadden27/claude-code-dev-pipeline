# Input: the build agent's report (schemas/build-report.schema.json); $issue = the issue number.
# Output: the commit message in the Conventional Commits format. The first line is also the pull request title.
#
#   type(scope)!: summary
#
#   Implements the approved plan on #N.
#
#   BREAKING CHANGE: ...      (only when breaking)
#   Closes #N

.commit as $c
| "\($c.type)(\($c.scope))\(if $c.breaking then "!" else "" end): \($c.summary)",
  "",
  "Implements the approved plan on #\($issue).",
  "",
  (if $c.breaking then "BREAKING CHANGE: \($c.breakingChange)" else empty end),
  "Closes #\($issue)"

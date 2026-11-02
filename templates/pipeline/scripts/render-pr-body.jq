# Input: the build agent's report (schemas/build-report.schema.json); $issue = the issue number.
# Output: the pull request description as markdown.

"<!-- ai-pipeline:pr -->",
"Closes #\($issue)",
"",
"## Summary",
"",
.summary,
"",
"## Changes",
"",
(.changes | map("- `\(.path)`: \(.what)") | join("\n")),
"",
"## Checks",
"",
"- Agent run: \(if .checks.passed then "passed" else "failed" end). \(.checks.notes)",
"- Pipeline re-run: passed (the pipeline runs `pipeline/scripts/run-checks.sh` itself before opening this PR).",
"",
(if (.followUps | length) > 0 then
  "## Follow-ups (not in this PR)", "", (.followUps | map("- " + .) | join("\n")), ""
else empty end),
"---",
"_Opened by the AI pipeline from the approved plan on #\($issue). The AI review runs automatically; comment `/review` to run it again. A person reviews and merges._"

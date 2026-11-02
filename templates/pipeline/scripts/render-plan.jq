# Input: the planning agent's structured output (schemas/plan.schema.json). Output: the plan comment as markdown.
# The first line is a marker the build stage and re-plans use to find pipeline comments.

def bullets: if length == 0 then "_None._" else map("- " + .) | join("\n") end;
def numbered: if length == 0 then "_None._" else to_entries | map("\(.key + 1). \(.value)") | join("\n") end;

"<!-- ai-pipeline:plan -->",
"## 🗺️ Implementation plan",
"",
.summary,
"",
"### Approach",
"",
.approach,
"",
"### Steps",
"",
(.steps | numbered),
"",
"### Files",
"",
(if (.files | length) == 0 then "_None._" else (.files | map("- `\(.path)` (\(.change))") | join("\n")) end),
"",
"### Risks",
"",
(.risks | bullets),
"",
(if (.questions | length) > 0 then
  "### ❓ Questions before I build",
  "",
  (.questions | numbered),
  "",
  "_Reply in one comment that starts with `/plan` followed by your answers; the plan is updated from them._"
else
  "### ✅ Ready to build",
  "",
  "_Comment `/approve` (or add the `ai:approved` label) to build this plan._"
end)

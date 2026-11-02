# Input: an array of the review agents' outputs (schemas/review-findings.schema.json), one per lens; $sha = the
# reviewed commit. Output: one review summary comment as markdown.
#
# Findings that several lenses report for the same file, line and title are merged. Order: high, medium, low.

def rank: {"high": 0, "medium": 1, "low": 2}[.];
def icon: {"high": "🔴", "medium": "🟠", "low": "🟡"}[.];
def where: if .line > 0 then "`\(.file):\(.line)`" else "`\(.file)`" end;

. as $reviews
| ($reviews | map(.lens as $lens | .findings[] | . + {lens: $lens})
   | group_by([.file, .line, (.title | ascii_downcase)])
   | map(.[0] + {lenses: (map(.lens) | unique), severity: (map(.severity) | min_by(rank))})
   | sort_by([(.severity | rank), .file, .line])) as $findings
| ($reviews | map(select(.verdict == "changes-requested")) | length) as $blocking
|
"<!-- ai-pipeline:review -->",
"## 🔍 AI review of \($sha[0:7])",
"",
"| Lens | Verdict | Findings |",
"| --- | --- | --- |",
($reviews | sort_by(.lens)[] | "| \(.lens) | \(if .verdict == "approve" then "✅ approve" else "❌ changes requested" end) | \(.findings | length) |"),
"",
(if ($findings | length) == 0 then "No findings.", "" else
  ($findings[] |
    "### \(.severity | icon) \(.title)",
    "",
    "\(where) · \(.severity) · \(.lenses | join(", "))",
    "",
    .detail,
    "",
    "**Suggestion:** \(.suggestion)",
    "")
end),
(if $blocking > 0 then "**Result: changes requested** by \($blocking) of \($reviews | length) reviewers."
 else "**Result: no blocking findings.**" end),
"",
"_Independent reviewers, one per lens, each without the others' output. Advisory only: a person reviews and merges._"

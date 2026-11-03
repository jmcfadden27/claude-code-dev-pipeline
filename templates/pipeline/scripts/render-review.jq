# Input: an array of the review agents' outputs (schemas/review-findings.schema.json), one per lens; $sha = the
# reviewed commit; $min = the lowest confidence posted (80). Output: one review summary comment as markdown.
#
# Findings below $min are left out (counted at the end). Findings that several lenses report for the same file, line
# and title are merged. Order: high, medium, low. A lens requests changes when it has a posted high finding.

def rank: {"high": 0, "medium": 1, "low": 2}[.];
def icon: {"high": "🔴", "medium": "🟠", "low": "🟡"}[.];
def where: if .line > 0 then "`\(.file):\(.line)`" else "`\(.file)`" end;

. as $all
| ($all | map(.findings |= map(select((.confidence // 100) >= $min)))) as $reviews
| (([$all[].findings[]] | length) - ([$reviews[].findings[]] | length)) as $hidden
| ($reviews | map(.lens as $lens | .findings[] | . + {lens: $lens})
   | group_by([.file, .line, (.title | ascii_downcase)])
   | map(.[0] + {lenses: (map(.lens) | unique), severity: (map(.severity) | min_by(rank))})
   | sort_by([(.severity | rank), .file, .line])) as $findings
| def blocking: any(.findings[]; .severity == "high");
  ($reviews | map(select(blocking)) | length) as $blocking
|
"<!-- ai-pipeline:review -->",
"## 🔍 AI review of \($sha[0:7])",
"",
"| Lens | Verdict | Findings |",
"| --- | --- | --- |",
($reviews | sort_by(.lens)[] | "| \(.lens) | \(if blocking then "❌ changes requested" else "✅ approve" end) | \(.findings | length) |"),
"",
(if ($findings | length) == 0 then "No findings.", "" else
  ($findings[] |
    "### \(.severity | icon) \(.title)",
    "",
    "\(where) · \(.severity) · confidence \(.confidence // 100) · \(.lenses | join(", "))",
    "",
    .detail,
    "",
    "**Suggestion:** \(.suggestion)",
    "")
end),
(if $blocking > 0 then "**Result: changes requested** by \($blocking) of \($reviews | length) reviewers."
 else "**Result: no blocking findings.**" end),
"",
(if $hidden > 0 then "_\($hidden) finding(s) below \($min) confidence left out._", "" else empty end),
"_Independent reviewers, one per lens, each without the others' output. Advisory only: a person reviews and merges._"

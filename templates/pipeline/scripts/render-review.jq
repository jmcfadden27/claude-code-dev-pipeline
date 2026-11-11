# Input: an array of the review agents' outputs (schemas/review-findings.schema.json), one per lens; $sha = the
# reviewed commit; $min = the lowest confidence posted (80); $previous = the link to the last review comment ("" for
# none). Output: one review summary comment as markdown, posted as a new comment (earlier reviews are never edited).
#
# Each lens first reports what happened to its findings from the last review (previous); those are merged per file and
# title, the worst status winning, and listed under "Since the last review". The posted findings are kept in the last
# line, base64-encoded in an HTML comment, for the next review to check (previous-findings.sh reads them).
#
# Findings below $min are left out (counted at the end). Each lens also reports what it checked (coverage): the table
# shows how many changed files it checked, and anything a lens did not check is listed, so a skimmed review shows. Findings that several lenses report for the same file, line
# and title are merged. Order: high, medium, low. A lens requests changes when it has a posted high finding.

def rank: {"high": 0, "medium": 1, "low": 2}[.];
def icon: {"high": "🔴", "medium": "🟠", "low": "🟡"}[.];
def where: if .line > 0 then "`\(.file):\(.line)`" else "`\(.file)`" end;
def status_rank: {"still-present": 0, "no-longer-applies": 1, "fixed": 2}[.];
def status_label: {"still-present": "❌ Still there", "no-longer-applies": "➖ No longer applies", "fixed": "✅ Fixed"}[.];

. as $all
# A finding the lens says is still there from the last review is always posted, whatever its confidence: it was
# verified, and dropping it would hide it and make the next review forget it.
| ($all | map(([(.previous // [])[] | select(.status == "still-present") | [.file, (.title | ascii_downcase)]]) as $kept
   | .findings |= map(select((.confidence // 100) >= $min or ([.file, (.title | ascii_downcase)] as $k | $kept | index([$k]) != null)))))
  as $reviews
| (([$all[].findings[]] | length) - ([$reviews[].findings[]] | length)) as $hidden
| ($all | map(.lens as $lens | (.coverage.notChecked // [])[] | . + {lens: $lens})
   | group_by(.item) | map({item: .[0].item, reason: (map(.reason) | unique | join("; ")), lenses: (map(.lens) | unique)})) as $unchecked
| ($reviews | map(.lens as $lens | .findings[] | . + {lens: $lens})
   | group_by([.file, .line, (.title | ascii_downcase)])
   | map(.[0] + {lenses: (map(.lens) | unique), severity: (map(.severity) | min_by(rank))})
   | sort_by([(.severity | rank), .file, .line])) as $findings
| ($all | map(.lens as $lens | (.previous // [])[] | . + {lens: $lens})
   | group_by([.file, (.title | ascii_downcase)])
   | map(.[0] + {lenses: (map(.lens) | unique), status: (map(.status) | min_by(status_rank)), note: (map(.note) | unique | join("; "))})
   | sort_by([(.status | status_rank), .file])) as $since
| def blocking: any(.findings[]; .severity == "high");
  ($reviews | map(select(blocking)) | length) as $blocking
|
"<!-- ai-pipeline:review -->",
"## 🔍 AI review of \($sha[0:7])",
"",
"| Lens | Verdict | Findings | Files checked |",
"| --- | --- | --- | --- |",
($reviews | sort_by(.lens)[] | "| \(.lens) | \(if blocking then "❌ changes requested" else "✅ approve" end) | \(.findings | length) | \(.coverage.filesChecked // [] | length) |"),
"",
(if ($since | length) > 0 then
  (if $previous != "" then "### Since the [last review](\($previous))" else "### Since the last review" end),
  "",
  ($since[] | "- \(.status | status_label): **\(.title)** · `\(.file)` (\(.lenses | join(", "))): \(.note)"),
  ""
 else empty end),
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
(if ($unchecked | length) > 0 then
  "### ⚠️ Not checked",
  "",
  ($unchecked[] | "- `\(.item)` (\(.lenses | join(", "))): \(.reason)"),
  ""
 else empty end),
"_Independent reviewers, one per lens, each without the others' output. Advisory only: a person reviews and merges._",
"<!-- ai-pipeline:findings \($findings | map({lenses, severity, file, line, title, detail}) | tojson | @base64) -->"

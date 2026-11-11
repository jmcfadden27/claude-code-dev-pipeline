# Input: `gh issue view --json number,title,body,author,comments`. Output: the issue thread as markdown.
# Untrusted authors' text is withheld (see gather-issue-context.sh), and so are the pipeline's status comments, which can
# carry text from the build job. $approved: the /approve comment's ID ("" for none); comments after it are left out.

def trusted_association: . as $a | ["OWNER", "MEMBER", "COLLABORATOR"] | index($a) != null;
# $trusted: logins verified to have write access (trusted-authors.sh).
def status_notice: (.author.login | IN("github-actions", "github-actions[bot]"))
  and (.body | startswith("<!-- ai-pipeline:status") or startswith("<!-- ai-pipeline:failed -->"));
def trusted_comment:
  (.author.login as $l | $trusted | index($l) != null)
  or (.authorAssociation | trusted_association)
  or ((.author.login | IN("github-actions", "github-actions[bot]"))
      and (.body | startswith("<!-- ai-pipeline:status") or startswith("<!-- ai-pipeline:failed -->") | not));
# The comment's REST ID, from its URL (…#issuecomment-123); null when it has none, and then it is left out of a
# pinned thread.
def comment_id: [.url // "" | capture("issuecomment-(?<id>[0-9]+)$").id | tonumber] | first;

(if $approved != "" then .comments |= map(select(comment_id as $id | $id != null and $id <= ($approved | tonumber)))
 else . end) |
"# Issue #\(.number): \(.title)",
"",
"## Request (by @\(.author.login))",
"",
(.body // "" | if . == "" then "_(empty)_" else . end),
"",
"## Comments (oldest first)",
"",
(if $approved != "" then "_The thread up to the `/approve` this change was built from; later comments are not shown._", "" else empty end),
(if (.comments | length) == 0 then "_(none)_" else
  (.comments[] |
    "### @\(.author.login) · \(.createdAt)",
    "",
    (if trusted_comment then .body
     elif status_notice then "_(the pipeline's status notice: not shown)_"
     else "_(withheld: not from a repository collaborator)_" end),
    "")
end)

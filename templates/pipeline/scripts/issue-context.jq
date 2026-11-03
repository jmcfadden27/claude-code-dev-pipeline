# Input: `gh issue view --json number,title,body,author,comments`. Output: the issue thread as markdown.
# Untrusted authors' text is withheld (see gather-issue-context.sh).

def trusted_association: . as $a | ["OWNER", "MEMBER", "COLLABORATOR"] | index($a) != null;
# $trusted: logins verified to have write access (trusted-authors.sh).
def trusted_comment:
  (.author.login as $l | $trusted | index($l) != null)
  or (.authorAssociation | trusted_association)
  or ((.author.login | IN("github-actions", "github-actions[bot]"))
      and (.body | startswith("<!-- ai-pipeline:failed -->") | not));

"# Issue #\(.number): \(.title)",
"",
"## Request (by @\(.author.login))",
"",
(.body // "" | if . == "" then "_(empty)_" else . end),
"",
"## Comments (oldest first)",
"",
(if (.comments | length) == 0 then "_(none)_" else
  (.comments[] |
    "### @\(.author.login) · \(.createdAt)",
    "",
    (if trusted_comment then .body else "_(withheld: not from a repository collaborator)_" end),
    "")
end)

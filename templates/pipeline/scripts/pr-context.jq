# Inputs: $pr = `gh pr view --json number,title,body,comments`; $inline = the pull request's review comments on lines
# of code (`GET /repos/{owner}/{repo}/pulls/{n}/comments`); $trusted = verified logins. Output: the pull request as markdown for the fix agent.
# Untrusted authors' text is withheld (see gather-pr-context.sh).

def trusted: . as $a | ["OWNER", "MEMBER", "COLLABORATOR"] | index($a) != null;
def pipeline: IN("github-actions", "github-actions[bot]");
# $trusted: logins verified to have write access (trusted-authors.sh).
def verified: . as $l | $trusted | index($l) != null;
def trusted_comment: (.author.login | verified) or (.authorAssociation | trusted) or (.author.login | pipeline);
def trusted_inline: (.user.login | verified) or (.author_association | trusted) or (.user.login | pipeline);

($pr.comments | map(select(trusted_comment and (.body | ascii_downcase | startswith("/fix")))) | last) as $request
|
"# Pull request #\($pr.number): \($pr.title)",
"",
"## What you were asked to fix",
"",
(if $request == null then "_(no /fix comment found)_"
 else ($request.body | sub("^/[Ff][Ii][Xx]\\s*"; "") | if . == "" then "_(nothing specific: fix the AI review's findings)_" else . end)
 end),
"",
"## Description",
"",
($pr.body // "" | if . == "" then "_(empty)_" else . end),
"",
"## Conversation (oldest first; the AI review starts with <!-- ai-pipeline:review -->)",
"",
(if ($pr.comments | length) == 0 then "_(none)_" else
  ($pr.comments[] |
    "### @\(.author.login) · \(.createdAt)",
    "",
    (if trusted_comment then .body else "_(withheld: not from a repository collaborator)_" end),
    "")
end),
"## Comments on lines of code",
"",
(if ($inline | length) == 0 then "_(none)_" else
  ($inline[] |
    "### `\(.path):\(.line // .original_line // 0)` · @\(.user.login)",
    "",
    (if trusted_inline then .body else "_(withheld: not from a repository collaborator)_" end),
    "")
end)

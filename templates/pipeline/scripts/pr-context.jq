# Inputs: $pr = `gh pr view --json number,title,body,comments`; $inline = the pull request's review comments on lines
# of code (`GET /repos/{owner}/{repo}/pulls/{n}/comments`); $trusted = verified logins. Output: the pull request as markdown for the fix agent.
# Untrusted authors' text is withheld (see gather-pr-context.sh).

def trusted: . as $a | ["OWNER", "MEMBER", "COLLABORATOR"] | index($a) != null;
def pipeline: IN("github-actions", "github-actions[bot]");
# $trusted: logins verified to have write access (trusted-authors.sh).
def verified: . as $l | $trusted | index($l) != null;
# Status comments, fix notes and the older failure notices can carry text from the build job, where code the agent
# wrote runs: never treat them as pipeline text.
def pipeline_text: (.author.login | pipeline)
  and (.body | startswith("<!-- ai-pipeline:status") or startswith("<!-- ai-pipeline:fixed")
       or startswith("<!-- ai-pipeline:failed -->") | not);
def trusted_comment: (.author.login | verified) or (.authorAssociation | trusted) or pipeline_text;
def status_notice: (.author.login | pipeline) and (pipeline_text | not);
# A review's saved findings (for the next review to check) are data, not text to read.
def readable: gsub("\n<!-- ai-pipeline:findings [A-Za-z0-9+/=]* -->\\s*$"; "");
def trusted_inline: (.user.login | verified) or (.author_association | trusted) or (.user.login | pipeline);

# The request: the latest trusted comment whose first word is exactly /fix (as parse-command.sh reads it).
($pr.comments | map(select(trusted_comment and (.body | gsub("\r"; "") | test("^/fix(\\s|$)"; "i")))) | last) as $request
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
"## Conversation (oldest first; each AI review starts with <!-- ai-pipeline:review -->, the last is the latest)",
"",
(if ($pr.comments | length) == 0 then "_(none)_" else
  ($pr.comments[] |
    "### @\(.author.login) · \(.createdAt)",
    "",
    (if trusted_comment then .body | readable
     elif status_notice then "_(the pipeline's status notice: not shown)_"
     else "_(withheld: not from a repository collaborator)_" end),
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

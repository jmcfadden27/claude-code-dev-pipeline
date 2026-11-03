#!/usr/bin/env bash
# Writes the pull request the fix agent works on to .pipeline/pr.md: its description, the conversation (including the
# AI review and the /fix request) and the comments on lines of code.
#
# As with the issue thread, only text from people with write access (checked through the API), repository owners,
# members and collaborators, and the pipeline's own comments, reaches the agent; anything else is replaced by a note.
#
# Env: PR_NUMBER, GH_TOKEN, GITHUB_REPOSITORY; optional OUT (default .pipeline/pr.md).
set -euo pipefail

: "${PR_NUMBER:?PR_NUMBER is required}"
out="${OUT:-.pipeline/pr.md}"
mkdir -p "$(dirname "$out")"

pr="$(gh pr view "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --json number,title,body,comments)"
inline="$(gh api --paginate "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/comments" --jq '.[]' | jq -s .)"

trusted="$( { jq -r '.comments[].author.login' <<< "$pr"; jq -r '.[].user.login' <<< "$inline"; } | "$(dirname "$0")/trusted-authors.sh")"
# Files, not arguments: a long pull request thread can exceed the size of one command-line argument.
tmp="$(mktemp -d)"
printf '%s' "$pr" > "$tmp/pr.json"
printf '%s' "$inline" > "$tmp/inline.json"
jq -n -r --slurpfile prs "$tmp/pr.json" --slurpfile inlines "$tmp/inline.json" --argjson trusted "$trusted" \
  '$prs[0] as $pr | $inlines[0] as $inline | '"$(cat "$(dirname "$0")/pr-context.jq")" > "$out"
rm -rf "$tmp"
echo "Wrote $(wc -l < "$out") lines of pull request context to $out."

#!/usr/bin/env bash
# Checks an /approve: the plan it approves is the latest of the pipeline's own plan comments before the /approve (the
# one the requester saw; a plan posted after it doesn't count), and that plan must be ready to build.
#
# Ready means the comment's last line is render-plan.jq's ready footer: the renderer writes it only for a ready plan,
# and the agent's text never comes last. Line endings are normalised first (a comment edited on GitHub can come back
# with \r\n).
#
# Env: ISSUE_NUMBER, COMMENT_ID (the /approve comment), GH_TOKEN, GITHUB_REPOSITORY.
set -euo pipefail

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${COMMENT_ID:?COMMENT_ID is required}"
footer='_Comment `/approve` to build this plan._'
reason() { echo "$1" > "${RUNNER_TEMP:-/tmp}/failure-reason"; echo "::error::$1"; exit 1; }

# (--paginate prints one array per page.)
plan="$(gh api "repos/${GITHUB_REPOSITORY}/issues/${ISSUE_NUMBER}/comments" --paginate \
  | jq -s -r --argjson approve "$COMMENT_ID" '[add // [] | .[] | select(.id < $approve and .user.login == "github-actions[bot]"
    and (.body | startswith("<!-- ai-pipeline:plan -->")))] | last | .body // empty')"
[[ -n "$plan" ]] || reason "There is no plan on this issue yet. Comment \`/plan\` first."
[[ "$(jq -Rsr 'gsub("\r"; "") | rtrimstr("\n") | split("\n") | last' <<< "$plan")" == "$footer" ]] \
  || reason "The latest plan isn't ready to build. Comment \`/plan\` with your answers first."
echo "The plan before comment ${COMMENT_ID} is ready to build."

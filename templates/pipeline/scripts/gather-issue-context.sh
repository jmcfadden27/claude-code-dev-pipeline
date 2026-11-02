#!/usr/bin/env bash
# Writes the issue thread the agent works from to .pipeline/issue.md: the title, the request and the comments.
#
# The issue body is the request: a collaborator chose to run the pipeline on it, so review a stranger's issue before
# labelling it. Comments reach the agent only from people with write access to the repository (checked through the
# API), repository owners, members and collaborators, or the pipeline itself (github-actions, whose comments carry
# the plan). Anything else is replaced by a note, so text from strangers
# can't steer the agent (prompt injection).
#
# The agent keeps no memory between runs; this file is the whole conversation (request, plan, answers, approval).
#
# Env: ISSUE_NUMBER, GH_TOKEN, GITHUB_REPOSITORY; optional OUT (default .pipeline/issue.md).
set -euo pipefail

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
out="${OUT:-.pipeline/issue.md}"
mkdir -p "$(dirname "$out")"

here="$(dirname "$0")"
issue="$(gh issue view "$ISSUE_NUMBER" --repo "$GITHUB_REPOSITORY" --json number,title,body,author,comments)"
trusted="$(jq -r '.comments[].author.login' <<< "$issue" | "$here/trusted-authors.sh")"
jq -r --argjson trusted "$trusted" -f "$here/issue-context.jq" <<< "$issue" > "$out"

echo "Wrote $(wc -l < "$out") lines of issue context to $out."

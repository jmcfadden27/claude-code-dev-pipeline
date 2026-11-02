#!/usr/bin/env bash
# Writes the issue thread the agent works from to .pipeline/issue.md: the title, the request and the comments.
#
# The issue body is the request: a collaborator chose to run the pipeline on it, so review a stranger's issue before
# labelling it. Comments reach the agent only from repository owners, members and collaborators, or from the pipeline
# itself (github-actions, whose comments carry the plan). Anything else is replaced by a note, so text from strangers
# can't steer the agent (prompt injection).
#
# The agent keeps no memory between runs; this file is the whole conversation (request, plan, answers, approval).
#
# Env: ISSUE_NUMBER, GH_TOKEN; optional OUT (default .pipeline/issue.md).
set -euo pipefail

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
out="${OUT:-.pipeline/issue.md}"
mkdir -p "$(dirname "$out")"

gh issue view "$ISSUE_NUMBER" --json number,title,body,author,comments \
  | jq -r -f "$(dirname "$0")/issue-context.jq" > "$out"

echo "Wrote $(wc -l < "$out") lines of issue context to $out."

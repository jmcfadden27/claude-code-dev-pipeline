#!/usr/bin/env bash
# Posts the planning agent's plan on the issue and labels it: ai:needs-answers while the agent has questions,
# ai:plan-ready when it has none. The agent itself has no GitHub access; this step does the writing.
#
# Env: PLAN_JSON (the action's structured_output), ISSUE_NUMBER, GH_TOKEN, GITHUB_REPOSITORY.
set -euo pipefail

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
if [[ -z "${PLAN_JSON:-}" ]]; then
  echo "::error::The planning agent returned no plan."
  exit 1
fi

here="$(dirname "$0")"
body="$(jq -r -f "$here/render-plan.jq" <<< "$PLAN_JSON")"
gh issue comment "$ISSUE_NUMBER" --repo "$GITHUB_REPOSITORY" --body "$body"

# Separate calls: removing a label the issue doesn't have fails, and must not stop the other label being added.
if [[ "$(jq -r '.readyToBuild and (.questions | length == 0)' <<< "$PLAN_JSON")" == "true" ]]; then
  add="ai:plan-ready"; remove="ai:needs-answers"
else
  add="ai:needs-answers"; remove="ai:plan-ready"
fi
gh issue edit "$ISSUE_NUMBER" --repo "$GITHUB_REPOSITORY" --add-label "$add"
gh issue edit "$ISSUE_NUMBER" --repo "$GITHUB_REPOSITORY" --remove-label "$remove" 2>/dev/null || true

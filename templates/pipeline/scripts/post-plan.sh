#!/usr/bin/env bash
# Posts the planning agent's plan on the issue and labels it: ai:needs-answers while the agent has questions or the plan
# has no acceptance criteria, ai:plan-ready otherwise. The agent itself has no GitHub access; this step does the writing.
#
# Env: PLAN_JSON (the action's structured_output), ISSUE_NUMBER, GH_TOKEN, GITHUB_REPOSITORY. Step outputs: url (the plan
# comment), ready (true when it has no questions and has acceptance criteria).
set -euo pipefail

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
if [[ -z "${PLAN_JSON:-}" ]]; then
  echo "::error::The planning agent returned no plan."
  echo "The planning agent returned no plan (see the run log)." > "${RUNNER_TEMP:-/tmp}/failure-reason"
  exit 1
fi

here="$(dirname "$0")"
body="$(jq -r -f "$here/render-plan.jq" <<< "$PLAN_JSON")"
url="$(gh issue comment "$ISSUE_NUMBER" --repo "$GITHUB_REPOSITORY" --body "$body")"
ready="$(jq -r '.readyToBuild and (.questions | length == 0) and (.acceptanceCriteria | length > 0)' <<< "$PLAN_JSON")"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then { echo "url=${url}"; echo "ready=${ready}"; } >> "$GITHUB_OUTPUT"; fi

# Separate calls: removing a label the issue doesn't have fails, and must not stop the other label being added.
if [[ "$ready" == "true" ]]; then
  add="ai:plan-ready"; remove="ai:needs-answers"
else
  add="ai:needs-answers"; remove="ai:plan-ready"
fi
# A missing label must not turn a posted plan into a failure (create the labels: setup step 8).
gh issue edit "$ISSUE_NUMBER" --repo "$GITHUB_REPOSITORY" --add-label "$add" \
  || echo "::warning::Couldn't add the label ${add}; create the pipeline's status labels (setup guide, step 8)."
gh issue edit "$ISSUE_NUMBER" --repo "$GITHUB_REPOSITORY" --remove-label "$remove" 2>/dev/null || true

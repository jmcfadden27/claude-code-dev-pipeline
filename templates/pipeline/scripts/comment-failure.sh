#!/usr/bin/env bash
# Tells the requester a pipeline stage failed, with a link to the run, so nothing fails silently.
#
# Env: STAGE (plan | build | fix | review), NUMBER (issue or pull request), GITHUB_SERVER_URL, GITHUB_REPOSITORY,
# GITHUB_RUN_ID, GH_TOKEN; optional REPORT_JSON (an agent's report: a blocked agent's reason is included).
set -euo pipefail

run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
reason=""
if [[ -n "${REPORT_JSON:-}" ]] && [[ "$(jq -r '.status // empty' <<< "$REPORT_JSON" 2>/dev/null)" == "blocked" ]]; then
  reason="

**The agent stopped:** $(jq -r '.summary' <<< "$REPORT_JSON")"
fi
gh issue comment "$NUMBER" --repo "$GITHUB_REPOSITORY" --body "<!-- ai-pipeline:failed -->
⚠️ The **${STAGE}** stage failed or was cancelled. Nothing was changed. [See the run](${run_url}) for details, then try again.${reason}"

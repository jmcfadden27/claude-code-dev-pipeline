#!/usr/bin/env bash
# Tells the requester a pipeline stage failed, with a link to the run, so nothing fails silently.
#
# Env: STAGE (plan | build | fix | review), NUMBER (issue or pull request), GITHUB_SERVER_URL, GITHUB_REPOSITORY,
# GITHUB_RUN_ID, GH_TOKEN; optional REPORT_JSON (an agent's report: a blocked agent's reason is included). The reason
# and report may also come as files in $RUNNER_TEMP (failure-reason, report.json), e.g. handed over by the build job.
set -euo pipefail

if [[ -z "${REPORT_JSON:-}" && -s "${RUNNER_TEMP:-/tmp}/report.json" ]]; then
  REPORT_JSON="$(cat "${RUNNER_TEMP:-/tmp}/report.json")"
fi

run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
reason=""
# The reason can come from the build job, where code the agent wrote runs: keep it short and break @mentions.
if [[ -s "${RUNNER_TEMP:-/tmp}/failure-reason" ]]; then
  reason="

$(head -c 1500 "${RUNNER_TEMP:-/tmp}/failure-reason" | sed 's/@/@\xe2\x80\x8b/g')"
fi
if [[ -n "${REPORT_JSON:-}" ]] && [[ "$(jq -r '.status // empty' <<< "$REPORT_JSON" 2>/dev/null)" == "blocked" ]]; then
  reason="

**The agent stopped:** $(jq -r '.summary' <<< "$REPORT_JSON")"
fi
gh issue comment "$NUMBER" --repo "$GITHUB_REPOSITORY" --body "<!-- ai-pipeline:failed -->
⚠️ The **${STAGE}** stage failed. [See the run](${run_url}) for details, then try again.${reason}"

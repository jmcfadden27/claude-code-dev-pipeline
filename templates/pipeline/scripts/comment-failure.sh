#!/usr/bin/env bash
# Tells the requester a pipeline stage failed, with a link to the run, so nothing fails silently.
#
# Env: STAGE (plan | build | review), NUMBER (issue or pull request), GITHUB_SERVER_URL, GITHUB_REPOSITORY,
# GITHUB_RUN_ID, GH_TOKEN.
set -euo pipefail

run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
gh issue comment "$NUMBER" --body "<!-- ai-pipeline:failed -->
⚠️ The **${STAGE}** stage failed. Nothing was changed. [See the run](${run_url}) for details, then try again."

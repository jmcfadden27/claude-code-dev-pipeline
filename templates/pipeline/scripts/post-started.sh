#!/usr/bin/env bash
# Posts "⏳ <stage> started" with a link to the run on the issue or pull request, so the requester can follow it.
#
# Env: STAGE (Plan | Build | Fix | Review), NUMBER (issue or pull request), GITHUB_SERVER_URL, GITHUB_REPOSITORY,
# GITHUB_RUN_ID, GH_TOKEN.
set -euo pipefail

: "${STAGE:?STAGE is required}"
: "${NUMBER:?NUMBER is required}"
run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
gh issue comment "$NUMBER" --repo "$GITHUB_REPOSITORY" --body "<!-- ai-pipeline:started -->
⏳ **${STAGE}** started · [follow the run](${run_url}) · comment \`/cancel\` to stop it"

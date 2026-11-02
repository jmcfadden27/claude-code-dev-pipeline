#!/usr/bin/env bash
# Stops the job unless ACTOR may run the pipeline: write, maintain or admin access to this repository and, when the
# PIPELINE_ALLOWED_USERS repository variable is set, listed in it (comma separated).
#
# claude-code-action makes the same write-access check before Claude starts. This runs first so that none of the
# pipeline's own steps (gathering context, posting comments) run for anyone else either.
#
# Env: ACTOR, GITHUB_REPOSITORY, GH_TOKEN; optional PIPELINE_ALLOWED_USERS.
set -euo pipefail

: "${ACTOR:?ACTOR is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

permission="$(gh api "repos/${GITHUB_REPOSITORY}/collaborators/${ACTOR}/permission" --jq '.permission' 2>/dev/null || echo none)"
case "$permission" in
  admin | maintain | write) ;;
  *)
    echo "::error::${ACTOR} does not have write access to ${GITHUB_REPOSITORY} (permission: ${permission})."
    exit 1
    ;;
esac

if [[ -n "${PIPELINE_ALLOWED_USERS:-}" ]]; then
  allowed=",${PIPELINE_ALLOWED_USERS// /},"
  if [[ "$allowed" != *",${ACTOR},"* ]]; then
    echo "::error::${ACTOR} is not in PIPELINE_ALLOWED_USERS."
    exit 1
  fi
fi

echo "${ACTOR} may run the pipeline (${permission})."

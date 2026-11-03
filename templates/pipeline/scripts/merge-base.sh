#!/usr/bin/env bash
# Brings the pull request's branch up to date with its base before the fix agent runs. A clean merge is committed
# here; on conflicts the merge is left in progress, the conflicted files are listed in .pipeline/conflicts.txt, and
# the agent resolves them (commit-change.sh refuses to commit while conflict markers remain).
#
# Env: BASE_REF.
set -euo pipefail

: "${BASE_REF:?BASE_REF is required}"
mkdir -p .pipeline
rm -f .pipeline/conflicts.txt

if git merge-base --is-ancestor "origin/${BASE_REF}" HEAD; then
  echo "Already up to date with ${BASE_REF}."
  exit 0
fi

# The workflow token can't push changes to workflow files, so a merge that brings in the base's workflow changes could
# never be pushed. Stop early with what to do instead.
since="$(git merge-base HEAD "origin/${BASE_REF}")"
if [[ -n "$(git diff --name-only "$since" "origin/${BASE_REF}" -- .github/workflows)" ]]; then
  reason="${BASE_REF} changed workflow files since this branch was made, and the pipeline can't push those. Click **Update branch** on the pull request (or merge ${BASE_REF} into it yourself), then comment \`/fix\` again."
  echo "::error::${reason}"
  echo "$reason" > "${RUNNER_TEMP:-/tmp}/failure-reason"
  exit 1
fi

if git merge --no-edit -m "chore(merge): bring in the latest ${BASE_REF}" "origin/${BASE_REF}"; then
  echo "Merged the latest ${BASE_REF}."
else
  git diff --name-only --diff-filter=U > .pipeline/conflicts.txt
  if [[ ! -f .git/MERGE_HEAD || ! -s .pipeline/conflicts.txt ]]; then
    reason="Merging the latest ${BASE_REF} failed for a reason other than conflicts; see the run log."
    echo "::error::${reason}"
    echo "$reason" > "${RUNNER_TEMP:-/tmp}/failure-reason"
    exit 1
  fi
  # The agent can't edit these, so it could never resolve their conflicts.
  if grep -qE '^(CLAUDE(\.local)?\.md|\.claude/|\.github/|pipeline/|\.mcp\.json|\.claude\.json|\.gitmodules|\.ripgreprc|\.husky/)' .pipeline/conflicts.txt; then
    git merge --abort
    reason="Merging the latest ${BASE_REF} conflicts in files the agent may not change ($(grep -E '^(CLAUDE|\.claude/|\.github/|pipeline/|\.mcp|\.gitmodules|\.ripgreprc|\.husky/)' .pipeline/conflicts.txt | paste -sd ',' - | sed 's/,/, /g')). Resolve them yourself (merge ${BASE_REF} into the branch and push), then comment \`/fix\` again."
    echo "::error::${reason}"
    echo "$reason" > "${RUNNER_TEMP:-/tmp}/failure-reason"
    exit 1
  fi
  echo "Merge conflicts for the agent to resolve:"
  cat .pipeline/conflicts.txt
fi

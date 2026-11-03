#!/usr/bin/env bash
# Brings the pull request's branch up to date with its base before the fix agent runs. A clean merge is committed
# here; on conflicts the merge is left in progress, the conflicted files are listed in .pipeline/conflicts.txt, and
# the agent resolves them (commit-change.sh refuses to commit while conflict markers remain).
#
# Env: BASE_REF.
set -euo pipefail

: "${BASE_REF:?BASE_REF is required}"
mkdir -p .pipeline
rm -f .pipeline/conflicts.txt "${RUNNER_TEMP:-/tmp}/conflicts.txt"
fail() { echo "::error::$1"; echo "$1" > "${RUNNER_TEMP:-/tmp}/failure-reason"; exit 1; }
# Files the agent may not change (claude-settings.json), so it could never resolve their conflicts.
protected='^(CLAUDE(\.local)?\.md|\.claude/|\.claude\.json|\.github/|pipeline/|\.mcp\.json|\.gitmodules|\.ripgreprc|\.husky/)'

if git merge-base --is-ancestor "origin/${BASE_REF}" HEAD; then
  echo "Already up to date with ${BASE_REF}."
  exit 0
fi

# The workflow token can't push changes to workflow files, so a merge that brings in the base's workflow changes could
# never be pushed. Stop early with what to do instead.
since="$(git merge-base HEAD "origin/${BASE_REF}")"
if [[ -n "$(git diff --name-only "$since" "origin/${BASE_REF}" -- .github/workflows)" ]]; then
  fail "${BASE_REF} changed workflow files since this branch was made, and the pipeline can't push those. Update the branch yourself (**Update branch** on the pull request, or merge ${BASE_REF} into it locally and push), then comment \`/fix\` again."
fi

if git merge --no-edit -m "chore(merge): bring in the latest ${BASE_REF}" "origin/${BASE_REF}"; then
  echo "Merged the latest ${BASE_REF}."
else
  git diff --name-only --diff-filter=U > .pipeline/conflicts.txt
  if [[ ! -f .git/MERGE_HEAD || ! -s .pipeline/conflicts.txt ]]; then
    fail "Merging the latest ${BASE_REF} failed for a reason other than conflicts; see the run log."
  fi
  yourself="Resolve them yourself (merge ${BASE_REF} into the branch and push), then comment \`/fix\` again."
  list() { paste -sd ',' - | sed 's/,/, /g'; }
  stop() { git merge --abort; fail "Merging the latest ${BASE_REF} conflicts $1. ${yourself}"; }
  # The agent can't edit these, so it could never resolve their conflicts.
  if grep -qE "$protected" .pipeline/conflicts.txt; then
    stop "in files the agent may not change ($(grep -E "$protected" .pipeline/conflicts.txt | list))"
  fi
  # The agent can't delete files, so a file deleted on one side and changed on the other can't be resolved by it.
  deleted="$(git status --porcelain | sed -nE 's/^(DU|UD|DD) //p' | list)"
  if [[ -n "$deleted" ]]; then stop "where one side deleted a file the other changed (${deleted})"; fi
  # A binary file has no conflict markers for the agent to resolve, and either side could be silently kept.
  binary="$(while IFS= read -r f; do
    if git diff --numstat "$since" "origin/${BASE_REF}" -- "$f" | awk '$1 == "-" { found = 1 } END { exit !found }'; then
      echo "$f"
    fi
  done < .pipeline/conflicts.txt | list)"
  if [[ -n "$binary" ]]; then stop "in binary files (${binary})"; fi
  # The agent can rewrite .pipeline/; commit-change.sh checks this copy.
  cp .pipeline/conflicts.txt "${RUNNER_TEMP:-/tmp}/conflicts.txt"
  echo "Merge conflicts for the agent to resolve:"
  cat .pipeline/conflicts.txt
fi

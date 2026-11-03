#!/usr/bin/env bash
# Publish job (the only job with write access, on a fresh runner): pushes the commits the build job bundled, then
# opens the pull request (build) or comments on it (fix). Nothing from the agent's job runs here: only the bundle,
# the report and the metadata are read, and every script comes from this job's own checkout of the default branch.
#
# Note: a push made with the workflow's GITHUB_TOKEN does not start other workflows (GitHub's rule), so the
# repository's own CI won't run on it automatically; the build job ran the checks itself. See docs/design-decisions.md.
#
# Env: IN (the downloaded artifact folder), GH_TOKEN, GITHUB_REPOSITORY.
set -euo pipefail

: "${IN:?IN is required}"
here="$(dirname "$0")"
meta="$(cat "$IN/meta.json")"
report="$(cat "$IN/report.json")"
mode="$(jq -r .mode <<< "$meta")"
branch="$(jq -r .branch <<< "$meta")"
base="$(jq -r .base <<< "$meta")"
pr="$(jq -r .pr <<< "$meta")"
issue="$(jq -r .issue <<< "$meta")"
title="$(jq -r .title <<< "$meta")"
summary="$(jq -r .summary <<< "$report")"

if [[ "$(jq -r .nothing <<< "$meta")" == "true" ]]; then
  gh pr comment "$pr" --repo "$GITHUB_REPOSITORY" --body "<!-- ai-pipeline:fixed -->
ℹ️ Nothing to change: ${summary}"
  exit 0
fi

git bundle verify -q "$IN/change.bundle"
git fetch -q "$IN/change.bundle" "pipeline-result:refs/pipeline/result"
sha="$(git rev-parse refs/pipeline/result)"

git config --local --unset-all http.https://github.com/.extraheader 2>/dev/null || true
if ! git push -q "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "${sha}:refs/heads/${branch}"; then
  echo "::error::Push refused. If someone pushed to the branch meanwhile, comment /fix again. If the message mentions workflows, click \"Update branch\" on the pull request first."
  exit 1
fi

if [[ "$mode" == "build" ]]; then
  body="$(jq -r --arg issue "$issue" -f "$here/render-pr-body.jq" <<< "$report")"
  url="$(gh pr create --repo "$GITHUB_REPOSITORY" --base "$base" --head "$branch" --title "$title" --body "$body")"
  pr="${url##*/}"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then { echo "pr=${pr}"; echo "sha=${sha}"; } >> "$GITHUB_OUTPUT"; fi
  gh issue comment "$issue" --repo "$GITHUB_REPOSITORY" --body "<!-- ai-pipeline:built -->
🔧 Built the approved plan: ${url}. The AI review starts now."
  echo "Opened ${url}"
else
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then { echo "pr=${pr}"; echo "sha=${sha}"; } >> "$GITHUB_OUTPUT"; fi
  changes="$(jq -r '.changes | map("- `\(.path)`: \(.what)") | join("\n")' <<< "$report")"
  gh pr comment "$pr" --repo "$GITHUB_REPOSITORY" --body "<!-- ai-pipeline:fixed -->
🔧 **${title}**

${summary}

${changes}

The AI review runs again now."
fi

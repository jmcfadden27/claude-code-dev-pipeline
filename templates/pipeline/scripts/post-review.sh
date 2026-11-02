#!/usr/bin/env bash
# Combines the review agents' findings into one comment on the pull request. A re-review edits the same comment
# instead of adding another.
#
# Env: FINDINGS_DIR (one JSON file per lens), PR_NUMBER, HEAD_SHA, GITHUB_REPOSITORY, GH_TOKEN.
set -euo pipefail

: "${FINDINGS_DIR:?FINDINGS_DIR is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"
here="$(dirname "$0")"

shopt -s nullglob globstar
files=("$FINDINGS_DIR"/**/*.json)
if (( ${#files[@]} == 0 )); then
  echo "::error::No reviewer returned findings."
  exit 1
fi

body="$(jq -s -r --arg sha "$HEAD_SHA" -f "$here/render-review.jq" "${files[@]}")"

existing="$(gh api "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" --paginate \
  --jq '[.[] | select(.body | startswith("<!-- ai-pipeline:review -->"))] | last | .id // empty')"
if [[ -n "$existing" ]]; then
  gh api -X PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/${existing}" -f body="$body" > /dev/null
  echo "Updated the review comment."
else
  gh pr comment "$PR_NUMBER" --body "$body"
fi

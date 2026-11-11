#!/usr/bin/env bash
# Combines the review agents' findings into one review comment on the pull request. Every review is a new comment:
# earlier ones are a record and are never edited. A re-review links to the last one and says what happened to its
# findings; the status comment of the command links to the new review.
#
# Findings below MIN_CONFIDENCE (default 80) are left out: a reviewer asked to find problems always finds something.
#
# Env: FINDINGS_DIR (one JSON file per lens), PR_NUMBER, HEAD_SHA, GITHUB_REPOSITORY, GH_TOKEN; optional MIN_CONFIDENCE,
# PREVIOUS_URL (the last review, which the reviewers checked: last-review.sh in prepare).
# Step outputs: url (the review comment), result (one line).
set -euo pipefail

: "${FINDINGS_DIR:?FINDINGS_DIR is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"
here="$(dirname "$0")"
min="${MIN_CONFIDENCE:-80}"
if ! [[ "$min" =~ ^[0-9]{1,3}$ ]] || (( 10#$min > 100 )); then
  echo "::warning::PIPELINE_REVIEW_MIN_CONFIDENCE must be a whole number from 0 to 100; using 80."
  min=80
fi
min=$((10#$min))

files=()
while IFS= read -r f; do files+=("$f"); done < <(find "$FINDINGS_DIR" -name '*.json' -type f | sort)
if (( ${#files[@]} == 0 )); then
  echo "::error::No reviewer returned findings."
  echo "No reviewer returned findings (see the run log)." > "${RUNNER_TEMP:-/tmp}/failure-reason"
  exit 1
fi

# Another review of this pull request may have started on a newer commit (a /review or /fix while this one ran). Never
# post a review of an older commit after it.
current="$(gh pr view "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --json headRefOid --jq .headRefOid || true)"
if [[ -n "$current" && "$current" != "$HEAD_SHA" ]]; then
  echo "::warning::The pull request moved on to ${current:0:7} while ${HEAD_SHA:0:7} was reviewed; not posting this review."
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "result=not posted: the pull request has newer commits (comment /review)" >> "$GITHUB_OUTPUT"; fi
  exit 0
fi

body="$(jq -s -r --arg sha "$HEAD_SHA" --argjson min "$min" --arg previous "${PREVIOUS_URL:-}" -f "$here/render-review.jq" "${files[@]}")"
result="$(grep -m1 '^\*\*Result:' <<< "$body" | sed 's/\*\*//g; s/\.$//')"
url="$(gh pr comment "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --body "$body")"
echo "Posted the review comment: ${url}"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then { echo "url=${url}"; echo "result=${result#Result: }"; } >> "$GITHUB_OUTPUT"; fi

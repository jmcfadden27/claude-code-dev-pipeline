#!/usr/bin/env bash
# Writes one lens's findings from the pull request's last AI review to .pipeline/previous-findings.json, for the
# reviewer to check first. The review is the one prepare found (REVIEW_ID, from last-review.sh), so every lens checks
# the same one. Its findings are in its last line, base64-encoded (render-review.jq); the comment is only read, never
# changed. An empty list when there is no earlier review, the comment isn't the pipeline's own review, or it has no
# findings for this lens.
#
# Env: LENS, GH_TOKEN, GITHUB_REPOSITORY; optional REVIEW_ID, OUT (default .pipeline/previous-findings.json).
set -euo pipefail

: "${LENS:?LENS is required}"
out="${OUT:-.pipeline/previous-findings.json}"
mkdir -p "$(dirname "$out")"

body=""
if [[ -n "${REVIEW_ID:-}" ]]; then
  # A review deleted since prepare read it (404) counts as none: the lens starts fresh, as on a first review.
  body="$(gh api "repos/${GITHUB_REPOSITORY}/issues/comments/${REVIEW_ID}" \
    | jq -r 'select(.user.login == "github-actions[bot]" and (.body | startswith("<!-- ai-pipeline:review -->"))) | .body' \
    || true)"
fi
encoded="$(jq -Rsr 'gsub("\r"; "") | [split("\n")[] | capture("^<!-- ai-pipeline:findings (?<b>[A-Za-z0-9+/=]*) -->$").b] | last // empty' <<< "$body")"
if [[ -n "$encoded" ]] && findings="$(jq -Rr '@base64d' <<< "$encoded" | jq -c --arg lens "$LENS" \
  'map(select(.lenses | index($lens)) | del(.lenses))' 2> /dev/null)"; then
  printf '%s\n' "$findings" > "$out"
else
  echo "[]" > "$out"
fi
echo "Wrote $(jq length "$out") earlier ${LENS} finding(s) to $out."

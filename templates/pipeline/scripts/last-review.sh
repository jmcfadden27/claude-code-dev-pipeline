#!/usr/bin/env bash
# Finds the pull request's last AI review: the pipeline's own newest review comment. Read once, when the command
# arrives, so all four lenses check the same review and the new review links to the one they checked, even if another
# review is posted while this one runs.
#
# Env: PR_NUMBER, GH_TOKEN, GITHUB_REPOSITORY. Step outputs: review_id, review_url (both empty when there is none).
set -euo pipefail

: "${PR_NUMBER:?PR_NUMBER is required}"

# (--paginate prints one array per page.)
last="$(gh api "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" --paginate \
  | jq -s -c '[add // [] | .[] | select(.user.login == "github-actions[bot]" and (.body | startswith("<!-- ai-pipeline:review -->")))]
    | last // {} | {id, html_url}')"
id="$(jq -r '.id // empty' <<< "$last")"
url="$(jq -r '.html_url // empty' <<< "$last")"
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then { echo "review_id=${id}"; echo "review_url=${url}"; } >> "$GITHUB_OUTPUT"; fi
echo "Last review: ${url:-none}"

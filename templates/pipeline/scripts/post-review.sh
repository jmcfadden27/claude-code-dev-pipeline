#!/usr/bin/env bash
# Combines the review agents' findings into one comment on the pull request, posted as a new comment so the result
# always appears at the bottom, after "⏳ Review started". Earlier AI reviews on the pull request are then marked
# outdated and folded away, so only the newest carries the review marker (the fix agent works from that one).
#
# Env: FINDINGS_DIR (one JSON file per lens), PR_NUMBER, HEAD_SHA, GITHUB_REPOSITORY, GH_TOKEN.
set -euo pipefail

: "${FINDINGS_DIR:?FINDINGS_DIR is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"
here="$(dirname "$0")"
marker="<!-- ai-pipeline:review -->"

files=()
while IFS= read -r f; do files+=("$f"); done < <(find "$FINDINGS_DIR" -name '*.json' -type f | sort)
if (( ${#files[@]} == 0 )); then
  echo "::error::No reviewer returned findings."
  exit 1
fi

body="$(jq -s -r --arg sha "$HEAD_SHA" -f "$here/render-review.jq" "${files[@]}")"

# The pipeline's earlier reviews, read before posting the new one. (--paginate prints one array per page.)
earlier="$(gh api "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" --paginate \
  | jq -s -c --arg marker "$marker" \
    '[add // [] | .[] | select(.user.login == "github-actions[bot]" and (.body | startswith($marker))) | {id, body}]')"

gh pr comment "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --body "$body"

# Marking is cosmetic: a failure here leaves the new review posted.
while IFS= read -r comment; do
  id="$(jq -r .id <<< "$comment")"
  old="$(jq -r --arg marker "$marker" '.body | ltrimstr($marker)' <<< "$comment")"
  outdated="<!-- ai-pipeline:review-outdated -->
_Outdated: a newer AI review is below._

<details><summary>Earlier AI review</summary>

${old}

</details>"
  gh api -X PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/${id}" -f body="$outdated" > /dev/null \
    || echo "::warning::Couldn't mark the earlier review ${id} as outdated."
done < <(jq -c '.[]' <<< "$earlier")
echo "Posted the review; marked $(jq length <<< "$earlier") earlier review(s) outdated."

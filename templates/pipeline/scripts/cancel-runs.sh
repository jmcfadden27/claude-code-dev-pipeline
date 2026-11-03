#!/usr/bin/env bash
# /cancel: cancels this workflow's runs still going for the same issue or pull request (through GitHub's REST API),
# marks their status comments cancelled, and reacts 👍 on the /cancel comment (😕 when nothing was running).
#
# Runs are found by their name, which ai-pipeline.yml sets as "/<command> #<number> · <title>". On a pull request this
# includes the /approve run of the issue it closes (that run opened the pull request and may still be reviewing it).
# A status is marked only when GitHub accepted the cancel and the status still says running.
#
# Env: NUMBER, IS_PR (true | false), ACTOR, COMMENT_ID, WORKFLOW_FILE (ai-pipeline.yml), GH_TOKEN, GITHUB_REPOSITORY,
# GITHUB_RUN_ID.
set -euo pipefail

: "${NUMBER:?NUMBER is required}"
: "${WORKFLOW_FILE:?WORKFLOW_FILE is required}"
here="$(dirname "$0")"
repo="repos/${GITHUB_REPOSITORY}"

gh api "${repo}/issues/comments/${COMMENT_ID}/reactions" -f content=eyes > /dev/null || true

issue=""
if [[ "${IS_PR:-false}" == "true" ]]; then
  issue="$(gh pr view "$NUMBER" --repo "$GITHUB_REPOSITORY" --json closingIssuesReferences \
    --jq '.closingIssuesReferences[0].number // empty' || true)"
fi

runs="$(for status in in_progress queued waiting pending requested; do
  gh api -X GET "${repo}/actions/workflows/${WORKFLOW_FILE}/runs" -f status="$status" -f per_page=100 --jq '.workflow_runs[]' \
    || echo "::warning::Couldn't list ${status} runs." >&2
done | jq -s -c --arg n "$NUMBER" --arg issue "$issue" --argjson self "$GITHUB_RUN_ID" '
  [.[] | select(.id != $self)
   | select((.display_title | test("^/(plan|approve|fix|review) #\($n)( |$)"))
            or ($issue != "" and (.display_title | test("^/approve #\($issue)( |$)"))))
   | {id, title: .display_title, number: (.display_title | capture("^/[a-z]+ #(?<n>[0-9]+)").n)}] | unique_by(.id)')"

if [[ "$(jq length <<< "$runs")" == "0" ]]; then
  echo "Nothing is running for #${NUMBER}."
  gh api "${repo}/issues/comments/${COMMENT_ID}/reactions" -f content=confused > /dev/null || true
  exit 0
fi

stage_of() {
  case "$1" in
    /plan*) echo Plan ;; /approve*) echo Build ;; /fix*) echo Fix ;; *) echo Review ;;
  esac
}
cancelled=0
while IFS= read -r run; do
  id="$(jq -r .id <<< "$run")"
  title="$(jq -r .title <<< "$run")"
  number="$(jq -r .number <<< "$run")"
  if ! gh api -X POST "${repo}/actions/runs/${id}/cancel" > /dev/null; then
    echo "::warning::Run ${id} (${title}) could not be cancelled; it may have just finished."
    continue
  fi
  echo "Cancelled run ${id} (${title})."
  cancelled=$((cancelled + 1))
  status_id="$({ gh api "${repo}/issues/${number}/comments" --paginate || echo '[]'; } \
    | jq -s -r --arg m "<!-- ai-pipeline:status run=${id} -->" '
    [add // [] | .[] | select(.user.login == "github-actions[bot]" and (.body | startswith($m)) and (.body | contains("⏳")))]
    | last | .id // empty')"
  if [[ -n "$status_id" ]]; then
    STAGE="$(stage_of "$title")" STATUS_ID="$status_id" RUN_ID="$id" NUMBER="$number" COMMENT_ID="" \
      "$here/post-status.sh" cancelled || echo "::warning::Couldn't mark the status of run ${id}."
  fi
done < <(jq -c '.[]' <<< "$runs")

reaction=+1
if (( cancelled == 0 )); then reaction=confused; fi
gh api "${repo}/issues/comments/${COMMENT_ID}/reactions" -f content="$reaction" > /dev/null || true

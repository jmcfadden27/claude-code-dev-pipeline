#!/usr/bin/env bash
# Keeps one status comment per command up to date, and the reaction on the command's comment:
#
#   start      👀 on the command; posts "⏳ <stage> running" (its id goes to the step output status_id). With
#              SUPERSEDE=true, earlier "running" comments of the same stage here are marked replaced (a newer /plan or
#              /review cancels the older run).
#   done       "✅ <stage> done · <DETAILS>"; 👍 on the command.
#   failed     "⚠️ <stage> failed" with the reasons found in $RUNNER_TEMP (failure-reason files, a blocked agent's
#              report); 👎 on the command.
#   incomplete "⚠️ <stage> done, but the review didn't finish · <DETAILS>" with the reasons; 😕 on the command.
#   cancelled  "⏹ <stage> cancelled by @<ACTOR>" (used by /cancel, with RUN_ID set to the cancelled run).
#
# Env: STAGE (Plan | Build | Fix | Review), NUMBER (issue or pull request), COMMENT_ID (the command's comment), GH_TOKEN,
# GITHUB_REPOSITORY, GITHUB_SERVER_URL, GITHUB_RUN_ID; done / failed / incomplete / cancelled: STATUS_ID;
# done / incomplete: DETAILS;
# cancelled: ACTOR; optional RUN_ID (default GITHUB_RUN_ID), SUPERSEDE.
set -euo pipefail

mode="${1:?start | done | failed | incomplete | cancelled}"
: "${STAGE:?STAGE is required}"
: "${NUMBER:?NUMBER is required}"
run_id="${RUN_ID:-$GITHUB_RUN_ID}"
run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${run_id}"
api="repos/${GITHUB_REPOSITORY}/issues"
marker="<!-- ai-pipeline:status run=${run_id} -->"

react() {
  if [[ -n "${COMMENT_ID:-}" ]]; then
    gh api "${api}/comments/${COMMENT_ID}/reactions" -f content="$1" > /dev/null || echo "::warning::Couldn't react."
  fi
}
update() {
  gh api -X PATCH "${api}/comments/${STATUS_ID:?STATUS_ID is required}" -f body="$1" > /dev/null
}
# Reasons can come from the build job, where code the agent wrote runs: keep them short and break @mentions.
reasons() {
  local out="" f
  while IFS= read -r f; do
    out+="
$(head -c 1500 "$f")"
  done < <(find "${RUNNER_TEMP:-/tmp}" -name failure-reason -type f -size +0 2> /dev/null | sort)
  while IFS= read -r f; do
    if [[ "$(jq -r '.status // empty' "$f" 2> /dev/null)" == "blocked" ]]; then
      out+="
**The agent stopped:** $(jq -r '.summary' "$f" | head -c 1500)"
    fi
  done < <(find "${RUNNER_TEMP:-/tmp}" -name report.json -type f 2> /dev/null | sort)
  local zero_width
  zero_width="$(printf '\xe2\x80\x8b')"
  printf '%s' "${out//@/@${zero_width}}"
}

case "$mode" in
  start)
    react eyes
    # Cosmetic: a failure here must not stop the status comment being posted.
    if [[ "${SUPERSEDE:-}" == "true" ]]; then
      { gh api "${api}/${NUMBER}/comments" --paginate \
        | jq -s -r --arg stage "$STAGE" '
            add // [] | .[]
            | select(.user.login == "github-actions[bot]" and (.body | startswith("<!-- ai-pipeline:status ")))
            | select(.body | contains("⏳ **\($stage)** running")) | .id' \
        | while IFS= read -r old; do
            gh api -X PATCH "${api}/comments/${old}" \
              -f body="<!-- ai-pipeline:status replaced -->
⏹ **${STAGE}** replaced by a newer request (below)." > /dev/null || true
          done; } || echo "::warning::Couldn't mark earlier statuses replaced."
    fi
    id="$(gh api "${api}/${NUMBER}/comments" -f body="${marker}
⏳ **${STAGE}** running · [follow the run](${run_url}) · comment \`/cancel\` to stop it" --jq .id)"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "status_id=${id}" >> "$GITHUB_OUTPUT"; fi
    echo "Status comment ${id}."
    ;;
  done)
    update "${marker}
✅ **${STAGE}** done · ${DETAILS:-} · [run](${run_url})"
    react +1
    ;;
  failed)
    update "${marker}
⚠️ **${STAGE}** failed · [see the run](${run_url}), then try again.
$(reasons)"
    react -1
    ;;
  incomplete)
    update "${marker}
⚠️ **${STAGE}** done, but the review didn't finish · ${DETAILS:-} · [run](${run_url})
$(reasons)"
    react confused
    ;;
  cancelled)
    update "${marker}
⏹ **${STAGE}** cancelled by @${ACTOR:-someone}. Nothing more will be pushed by that run; anything it already pushed or
opened (a branch, a pull request) stays as it is."
    ;;
  *)
    echo "::error::Unknown mode: ${mode}"
    exit 2
    ;;
esac

#!/usr/bin/env bash
# Last job of a command's run: turns the jobs' results into the final status comment ("✅ done" with links, or
# "⚠️ failed" with the reasons) and the 👍 / 👎 reaction. When a build or fix was pushed but its review didn't finish,
# the status says what was pushed and that the review is incomplete (so nobody runs /approve again for a second PR).
#
# A job stopped at its time limit reports "cancelled" while the run itself isn't (a /cancel cancels the whole run, and
# then this job doesn't run at all), so a cancelled job here is a timeout.
#
# Env: NEEDS (toJSON(needs) of the workflow), COMMAND (plan | approve | fix | review), STAGE, NUMBER, COMMENT_ID,
# STATUS_ID, and what post-status.sh needs. Failure reasons are read from $RUNNER_TEMP (downloaded artifacts).
set -euo pipefail

: "${NEEDS:?NEEDS is required}"
: "${COMMAND:?COMMAND is required}"
here="$(dirname "$0")"
result() { jq -r --arg j "$1" '.[$j].result // "skipped"' <<< "$NEEDS"; }
output() { jq -r --arg j "$1" --arg o "$2" '.[$j].outputs[$o] // ""' <<< "$NEEDS"; }
# "[text](url)", or just the text when there is no URL.
link() { if [[ -n "$2" ]]; then printf '[%s](%s)' "$1" "$2"; else printf '%s' "$1"; fi; }

zero_width="$(printf '\xe2\x80\x8b')"
broken() { local t="$1"; printf '%s' "${t//@/@${zero_width}}"; }
went_wrong() { [[ "$(result "$1")" == "failure" || "$(result "$1")" == "cancelled" ]]; }
timed_out() {
  if [[ "$(result "$1")" == "cancelled" ]]; then
    mkdir -p "${RUNNER_TEMP:-/tmp}/timeouts/$1"
    echo "The $1 job stopped at its time limit. Raise PIPELINE_TIMEOUT_* (see the setup guide), or narrow the request." \
      > "${RUNNER_TEMP:-/tmp}/timeouts/$1/failure-reason"
  fi
}
for job in plan build publish review summarize; do timed_out "$job"; done

review_url="$(output summarize url)"
review_result="$(output summarize result)"
review=""
if [[ -n "$review_result" ]]; then review=" · $(link "AI review" "$review_url"): ${review_result}"; fi
review_broken=false
if went_wrong review || went_wrong summarize; then
  review_broken=true
  mkdir -p "${RUNNER_TEMP:-/tmp}/review-lens"
  echo "The review didn't finish (a reviewer failed or timed out). Comment \`/review\` on the pull request to run it again." \
    > "${RUNNER_TEMP:-/tmp}/review-lens/failure-reason"
fi

# The command's own work failed: nothing was published.
if went_wrong plan || went_wrong build || went_wrong publish || { [[ "$COMMAND" == "review" ]] && [[ "$review_broken" == "true" ]]; }; then
  exec "$here/post-status.sh" failed
fi

case "$COMMAND" in
  plan)
    plan_link="$(link "the plan" "$(output plan url)")"
    if [[ "$(output plan ready)" == "true" ]]; then
      details="${plan_link} is ready. Comment \`/approve\` to build it."
    else
      details="${plan_link} has questions for you. Answer in a comment starting with \`/plan\`."
    fi
    ;;
  approve)
    details="opened $(output publish url)${review}"
    ;;
  fix)
    note="$(output publish note)"
    if [[ -n "$note" ]]; then
      details="nothing to change: $(broken "$note")"
    else
      details="$(link "pushed the fix" "$(output publish url)")${review}"
    fi
    ;;
  review)
    details="${review# · }"
    ;;
  *)
    echo "::error::Unknown command: ${COMMAND}"
    exit 2
    ;;
esac
if [[ "$review_broken" == "true" ]]; then
  DETAILS="$details" exec "$here/post-status.sh" incomplete
fi
DETAILS="$details" exec "$here/post-status.sh" "done"

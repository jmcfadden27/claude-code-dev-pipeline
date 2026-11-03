#!/usr/bin/env bash
# Build job, no GitHub access: commits the agent's changes locally and writes them, with the agent's report, to
# $OUT for the publish job (a fresh job that alone holds write access) to push.
#
#   OUT/change.bundle  the new commits (branch `pipeline-result`); absent when a fix changed nothing
#   OUT/meta.json      { title, committed (false when a fix only brought in the base) }
#   OUT/report.json    the agent's report
#
# Build mode: on top of the default branch. Fix mode: on top of the pull request's branch, completing a merge with the
# base when one is in progress. Which branch the commits go to is decided by the publish job, not here.
#
# Env: MODE (build | fix), REPORT_JSON, OUT, ISSUE_NUMBER, BASE_REF; build: BASE_SHA (the commit the build started
# from); fix: PR_NUMBER, HEAD_REF, HEAD_SHA (the pull request's commit when /fix was accepted). Writes the reason for a stop to $RUNNER_TEMP/failure-reason for the failure comment.
set -euo pipefail

# Code the agent wrote ran in this job: ignore any git hooks, global or system config it may have left behind.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null \
  GIT_CONFIG_KEY_1=core.fsmonitor GIT_CONFIG_VALUE_1=false

: "${MODE:?MODE is required}"
: "${REPORT_JSON:?REPORT_JSON is required}"
: "${OUT:?OUT is required}"
here="$(dirname "$0")"
fail() { echo "::error::$1"; echo "$1" > "${RUNNER_TEMP:-/tmp}/failure-reason"; exit 1; }
mkdir -p "$OUT"
printf '%s\n' "$REPORT_JSON" > "$OUT/report.json"

if [[ "$(jq -r '.status' <<< "$REPORT_JSON")" != "implemented" ]]; then
  fail "The ${MODE} agent stopped: $(jq -r '.summary' <<< "$REPORT_JSON")"
fi

if [[ "$MODE" == "fix" ]]; then
  # claude-code-action resets CLAUDE.md, .claude/ and similar to the default branch's copies on pull request events;
  # put the branch's own back so the fix never reverts them.
  "$here/snapshot-config.sh" restore
fi

# The action sets its own git identity during the agent step; commit as the pipeline.
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# Only the files that had conflicts are checked: elsewhere a line like `=======` can be legitimate (a Markdown heading).
# merge-base.sh keeps the list in $RUNNER_TEMP too, where the agent can't change it.
conflicts="${RUNNER_TEMP:-/tmp}/conflicts.txt"
[[ -s "$conflicts" ]] || conflicts=.pipeline/conflicts.txt
if [[ "$MODE" == "fix" && -f .git/MERGE_HEAD && -s "$conflicts" ]]; then
  markers='^(<<<<<<<|=======|>>>>>>>)( |$)'
  conflicted=()
  while IFS= read -r f; do [[ -f "$f" ]] && conflicted+=("$f"); done < "$conflicts"
  if (( ${#conflicted[@]} )) && grep -n -E "$markers" -- "${conflicted[@]}" > /dev/null; then
    grep -n -E "$markers" -- "${conflicted[@]}" | head -20
    fail "Unresolved merge conflicts remain in: $(grep -l -E "$markers" -- "${conflicted[@]}" | paste -sd ',' - | sed 's/,/, /g'). Resolve them on the branch yourself, or \`/fix\` with which side to keep."
  fi
fi

note=""
if [[ "$MODE" == "fix" && -f .git/MERGE_HEAD ]]; then note="Also brings in the latest ${BASE_REF}."; fi
message="$(jq -r --arg kind "$MODE" --arg issue "${ISSUE_NUMBER:-}" --arg pr "${PR_NUMBER:-}" --arg note "$note" \
  -f "$here/commit-message.jq" <<< "$REPORT_JSON")"
title="$(head -n 1 <<< "$message")"
# Conventional Commits: type(scope)!: summary. The schema constrains each part; this checks the assembled header.
header_pattern='^(feat|fix|refactor|perf|test|docs|ci|chore)\([a-z0-9][a-z0-9-]*\)!?: [a-z0-9].*[^.]$'
if ! [[ "$title" =~ $header_pattern ]] || (( ${#title} > 100 )); then
  fail "The agent's commit header is not in the Conventional Commits format: ${title}. Comment the command again."
fi

# .pipeline/ (the agent's scratch files) is in .git/info/exclude, so it's never added.
git add -A

if [[ "$MODE" == "build" ]]; then
  if git diff --cached --quiet; then
    fail "The build agent reported success but changed no files."
  fi
  since="${BASE_SHA:-origin/${BASE_REF}}"
  git commit -q -F - <<< "$message"
  committed=true
else
  since="${HEAD_SHA:-origin/${HEAD_REF}}"
  committed=false
  if [[ -f .git/MERGE_HEAD ]] || ! git diff --cached --quiet; then git commit -q -F - <<< "$message"; committed=true; fi
fi

# No bundle means nothing to change (a fix only; a build without changes stopped above).
if [[ -n "$(git log "${since}..HEAD" --oneline)" ]]; then
  git branch -f pipeline-result HEAD
  git bundle create "$OUT/change.bundle" pipeline-result "^${since}"
fi

jq -n --arg title "$title" --argjson committed "$committed" '{title: $title, committed: $committed}' > "$OUT/meta.json"
cat "$OUT/meta.json"

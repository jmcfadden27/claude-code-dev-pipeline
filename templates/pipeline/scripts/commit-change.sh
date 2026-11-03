#!/usr/bin/env bash
# Build job, no GitHub access: commits the agent's changes locally and writes them, with the agent's report, to
# $OUT for the publish job (a fresh job that alone holds write access) to push.
#
#   OUT/change.bundle  the new commits (branch `pipeline-result`); absent when a fix changed nothing
#   OUT/meta.json      { mode, branch, base, pr, issue, title, nothing }
#   OUT/report.json    the agent's report
#
# Build mode: a new branch ai/issue-N-<time> from the default branch. Fix mode: on top of the pull request's branch,
# completing a merge with the base when one is in progress.
#
# Env: MODE (build | fix), REPORT_JSON, OUT, ISSUE_NUMBER; fix: PR_NUMBER, HEAD_REF, BASE_REF; build: BASE_REF.
set -euo pipefail

: "${MODE:?MODE is required}"
: "${REPORT_JSON:?REPORT_JSON is required}"
: "${OUT:?OUT is required}"
here="$(dirname "$0")"
mkdir -p "$OUT"
printf '%s\n' "$REPORT_JSON" > "$OUT/report.json"

if [[ "$(jq -r '.status' <<< "$REPORT_JSON")" != "implemented" ]]; then
  echo "::error::The ${MODE} agent stopped: $(jq -r '.summary' <<< "$REPORT_JSON")"
  exit 1
fi

if [[ "$MODE" == "fix" ]]; then
  # claude-code-action resets CLAUDE.md, .claude/ and similar to the default branch's copies on pull request events;
  # put the branch's own back so the fix never reverts them.
  "$here/snapshot-config.sh" restore
fi

# The action sets its own git identity during the agent step; commit as the pipeline.
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

if [[ "$MODE" == "fix" && -f .git/MERGE_HEAD ]]; then
  markers='^(<<<<<<<|=======|>>>>>>>)( |$)'
  if git grep -n -I -E "$markers" -- . ':!.pipeline' > /dev/null; then
    echo "::error::Unresolved merge conflicts remain:"
    git grep -n -I -E "$markers" -- . ':!.pipeline' | head -20
    exit 1
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
  echo "::error::The commit header is not in the Conventional Commits format: ${title}"
  exit 1
fi

# .pipeline/ (the agent's scratch files) is in .git/info/exclude, so it's never added.
git add -A

if [[ "$MODE" == "build" ]]; then
  if git diff --cached --quiet; then
    echo "::error::The build agent reported success but changed no files."
    exit 1
  fi
  branch="ai/issue-${ISSUE_NUMBER}-$(date -u +%Y%m%d%H%M%S)"
  since="origin/${BASE_REF}"
  git commit -q -F - <<< "$message"
else
  branch="$HEAD_REF"
  since="origin/${HEAD_REF}"
  if [[ -f .git/MERGE_HEAD ]] || ! git diff --cached --quiet; then git commit -q -F - <<< "$message"; fi
fi

nothing=false
if [[ -z "$(git log "${since}..HEAD" --oneline)" ]]; then
  nothing=true
else
  git branch -f pipeline-result HEAD
  git bundle create "$OUT/change.bundle" pipeline-result "^${since}"
fi

jq -n --arg mode "$MODE" --arg branch "$branch" --arg base "${BASE_REF:-}" --arg pr "${PR_NUMBER:-}" \
  --arg issue "${ISSUE_NUMBER:-}" --arg title "$title" --argjson nothing "$nothing" \
  '{mode: $mode, branch: $branch, base: $base, pr: $pr, issue: $issue, title: $title, nothing: $nothing}' > "$OUT/meta.json"
cat "$OUT/meta.json"

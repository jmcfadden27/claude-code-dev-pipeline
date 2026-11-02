#!/usr/bin/env bash
# Commits the fix agent's changes to the pull request's own branch and pushes them, then comments on the pull request.
# The agent has no git or GitHub access; this step owns every side effect.
#
# Env: REPORT_JSON (the action's structured_output), PR_NUMBER, HEAD_REF, BASE_REF, GH_TOKEN, GITHUB_REPOSITORY;
# optional ISSUE_NUMBER (adds "Refs #N").
set -euo pipefail

: "${PR_NUMBER:?PR_NUMBER is required}"
: "${HEAD_REF:?HEAD_REF is required}"
: "${REPORT_JSON:?REPORT_JSON is required}"
here="$(dirname "$0")"

if [[ "$(jq -r '.status' <<< "$REPORT_JSON")" != "implemented" ]]; then
  echo "::error::The fix agent stopped: $(jq -r '.summary' <<< "$REPORT_JSON")"
  exit 1
fi

# claude-code-action resets CLAUDE.md, .claude/ and similar to the default branch's copies on pull request events;
# put the branch's own back so the fix never reverts them.
"$here/snapshot-config.sh" restore

# The action sets its own git identity during the agent step; commit as the pipeline.
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# No conflict markers may remain from merging the base branch.
markers='^(<<<<<<<|=======|>>>>>>>)( |$)'
if [[ -f .git/MERGE_HEAD ]] && git grep -n -I -E "$markers" -- . ':!.pipeline' > /dev/null; then
  echo "::error::Unresolved merge conflicts remain:"
  git grep -n -I -E "$markers" -- . ':!.pipeline' | head -20
  exit 1
fi

git add -A
message="$(jq -r --arg kind fix --arg issue "${ISSUE_NUMBER:-}" --arg pr "$PR_NUMBER" -f "$here/commit-message.jq" <<< "$REPORT_JSON")"
title="$(head -n 1 <<< "$message")"
header_pattern='^(feat|fix|refactor|perf|test|docs|ci|chore)\([a-z0-9][a-z0-9-]*\)!?: [a-z0-9].*[^.]$'
if ! [[ "$title" =~ $header_pattern ]] || (( ${#title} > 100 )); then
  echo "::error::The commit header is not in the Conventional Commits format: ${title}"
  exit 1
fi

if [[ -f .git/MERGE_HEAD ]]; then
  # Conflicts were resolved: one commit completes the merge and carries the fix.
  git commit -q -F - <<< "${message}

Also brings in the latest ${BASE_REF:-base branch}."
elif ! git diff --cached --quiet; then
  git commit -q -F - <<< "$message"
fi

if [[ -z "$(git log "origin/${HEAD_REF}..HEAD" --oneline)" ]]; then
  gh pr comment "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --body "<!-- ai-pipeline:fixed -->
ℹ️ Nothing to change: $(jq -r '.summary' <<< "$REPORT_JSON")"
  exit 0
fi

# Push with the workflow token explicitly (see open-pr.sh).
git config --local --unset-all http.https://github.com/.extraheader 2>/dev/null || true
git config --global --unset-all http.https://github.com/.extraheader 2>/dev/null || true
if ! git push -q "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "HEAD:refs/heads/${HEAD_REF}"; then
  echo "::error::Push refused. If someone pushed to the branch during the fix, comment /fix again. If the message mentions workflows, click \"Update branch\" on the pull request first."
  exit 1
fi

changes="$(jq -r '.changes | map("- `\(.path)`: \(.what)") | join("\n")' <<< "$REPORT_JSON")"
gh pr comment "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --body "<!-- ai-pipeline:fixed -->
🔧 **${title}**

$(jq -r '.summary' <<< "$REPORT_JSON")

${changes}

The AI review runs again now."
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then { echo "pr=${PR_NUMBER}"; echo "sha=$(git rev-parse HEAD)"; } >> "$GITHUB_OUTPUT"; fi

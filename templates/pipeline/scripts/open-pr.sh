#!/usr/bin/env bash
# Commits the build agent's changes to a new branch, pushes it and opens a pull request that closes the issue.
# The agent has no git or GitHub access; it only edits files. This step owns every side effect.
#
# Note: a push made with the workflow's GITHUB_TOKEN does not start other workflows (GitHub's rule), so the
# repository's own CI won't run on this branch automatically. That is why the build workflow runs the checks itself
# before this step. See docs/design-decisions.md.
#
# Env: REPORT_JSON (the action's structured_output), ISSUE_NUMBER, GH_TOKEN, GITHUB_REPOSITORY; optional BASE_BRANCH.
set -euo pipefail

: "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
: "${REPORT_JSON:?REPORT_JSON is required}"
here="$(dirname "$0")"

if [[ "$(jq -r '.status' <<< "$REPORT_JSON")" != "implemented" ]]; then
  echo "::error::The build agent stopped: $(jq -r '.summary' <<< "$REPORT_JSON")"
  exit 1
fi

# The agent's scratch files never go in the commit.
git reset -q -- .pipeline 2>/dev/null || true
if git diff --quiet && [[ -z "$(git ls-files --others --exclude-standard -- . ':!.pipeline')" ]]; then
  echo "::error::The build agent reported success but changed no files."
  exit 1
fi

base="${BASE_BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
branch="ai/issue-${ISSUE_NUMBER}-$(date -u +%Y%m%d%H%M%S)"
message="$(jq -r --arg kind build --arg issue "$ISSUE_NUMBER" --arg pr "" -f "$here/commit-message.jq" <<< "$REPORT_JSON")"
title="$(head -n 1 <<< "$message")"
# Conventional Commits: type(scope)!: summary. The schema constrains each part; this checks the assembled header.
header_pattern='^(feat|fix|refactor|perf|test|docs|ci|chore)\([a-z0-9][a-z0-9-]*\)!?: [a-z0-9].*[^.]$'
if ! [[ "$title" =~ $header_pattern ]] || (( ${#title} > 100 )); then
  echo "::error::The commit header is not in the Conventional Commits format: ${title}"
  exit 1
fi

git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git switch -c "$branch"
# .pipeline/ (the agent's scratch files) is in .git/info/exclude, so it's never added.
git add -A
git commit -q -F - <<< "$message"
# Push with the workflow token explicitly. Earlier steps (claude-code-action) can leave their own short-lived GitHub
# credentials in the git config, revoked by now; clear them so they aren't sent instead.
git config --local --unset-all http.https://github.com/.extraheader 2>/dev/null || true
git config --global --unset-all http.https://github.com/.extraheader 2>/dev/null || true
git push -q "https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "HEAD:refs/heads/${branch}"

body="$(jq -r --arg issue "$ISSUE_NUMBER" -f "$here/render-pr-body.jq" <<< "$REPORT_JSON")"
url="$(gh pr create --base "$base" --head "$branch" --title "$title" --body "$body")"

gh issue comment "$ISSUE_NUMBER" --body "<!-- ai-pipeline:built -->
🔧 Built the approved plan: ${url}. The AI review starts now."
echo "Opened ${url}"
# The pull request number, for the review stage that runs next.
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then echo "pr=${url##*/}" >> "$GITHUB_OUTPUT"; fi

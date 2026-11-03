#!/usr/bin/env bash
# Publish job (the only job with write access, on a fresh runner): pushes the commits the build job bundled, then
# opens the pull request (build) or comments on it (fix).
#
# The build job ran code the agent wrote, so its artifact is untrusted: where to push comes only from the prepare job
# (MODE, ISSUE_NUMBER, PR_NUMBER, HEAD_REF, BASE_REF), and the bundled commits must sit on top of that branch. From the
# artifact only the commits and text (title, report) are used. Every script comes from this job's own checkout of the
# default branch.
#
# Note: a push made with the workflow's GITHUB_TOKEN does not start other workflows (GitHub's rule), so the
# repository's own CI won't run on it automatically; the build job ran the checks itself. See docs/design-decisions.md.
#
# Env: IN (the downloaded artifact folder), MODE (build | fix), ISSUE_NUMBER, PR_NUMBER (fix), HEAD_REF, BASE_REF,
# BASE_SHA (build: the commit the build started from), GH_TOKEN, GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT.
set -euo pipefail

: "${IN:?IN is required}"
: "${MODE:?MODE is required}"
: "${BASE_REF:?BASE_REF is required}"
here="$(dirname "$0")"
reason_file="${RUNNER_TEMP:-/tmp}/failure-reason"
fail() { echo "::error::$1"; echo "$1" > "$reason_file"; exit 1; }

meta="$(cat "$IN/meta.json")"
report="$(cat "$IN/report.json")"
title="$(jq -r '.title | tostring' <<< "$meta")"
committed="$(jq -r '.committed // true' <<< "$meta")"
summary="$(jq -r '.summary | tostring' <<< "$report")"

if [[ "$MODE" == "fix" ]]; then
  : "${PR_NUMBER:?PR_NUMBER is required}"
  : "${HEAD_REF:?HEAD_REF is required}"
  branch="$HEAD_REF"
  on_top_of="origin/${HEAD_REF}"
  again="If someone pushed to the pull request meanwhile, comment \`/fix\` again."
  onto="${HEAD_REF}"
else
  : "${ISSUE_NUMBER:?ISSUE_NUMBER is required}"
  : "${BASE_SHA:?BASE_SHA is required}"
  # The run attempt keeps a re-run of this job from colliding with the branch an earlier attempt pushed.
  branch="ai/issue-${ISSUE_NUMBER}-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:-1}"
  on_top_of="$BASE_SHA"
  again="Comment \`/approve\` again."
  onto="the ${BASE_REF} commit the build started from"
fi

# The title comes from the build job's artifact: accept only a Conventional Commits header (as commit-change.sh made).
header_pattern='^(feat|fix|refactor|perf|test|docs|ci|chore)\([a-z0-9][a-z0-9-]*\)!?: [a-z0-9].*[^.]$'
if ! [[ "$title" =~ $header_pattern ]] || (( ${#title} > 100 )); then
  fail "The build's commit title is not a Conventional Commits header. ${again}"
fi

if [[ ! -f "$IN/change.bundle" ]]; then
  [[ "$MODE" == "fix" ]] || fail "The build produced no commits. ${again}"
  gh pr comment "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --body "<!-- ai-pipeline:fixed -->
ℹ️ Nothing to change: ${summary}"
  exit 0
fi

if ! git bundle verify -q "$IN/change.bundle" > /dev/null || ! git fetch -q "$IN/change.bundle" "pipeline-result:refs/pipeline/result"; then
  fail "The build's commits couldn't be read (the branch they build on may have been rewritten). ${again}"
fi
sha="$(git rev-parse refs/pipeline/result)"

# The commits must build on what prepare chose (the build's start commit, or the pull request's branch); anything else
# (another branch's history, a rewrite) is refused. For a build that commit must also be on the base branch.
if ! git merge-base --is-ancestor "$on_top_of" "$sha" \
  || { [[ "$MODE" == "build" ]] && ! git merge-base --is-ancestor "$BASE_SHA" "origin/${BASE_REF}"; }; then
  fail "The commits don't sit on top of ${onto}. ${again}"
fi
# GitHub refuses workflow-file changes pushed with the workflow token; say so instead of a generic push error.
workflows="$(git diff --name-only "$on_top_of" "$sha" -- .github/workflows | paste -sd ',' - | sed 's/,/, /g')"
if [[ -n "$workflows" ]]; then
  fail "The change touches workflow files (${workflows}), which the pipeline can't push. Make that part of the change yourself."
fi

git config --local --unset-all http.https://github.com/.extraheader 2>/dev/null || true
# PIPELINE_PUSH_URL: tests only (a local repository).
remote="${PIPELINE_PUSH_URL:-https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git}"
if [[ "$MODE" == "build" ]]; then
  # A new branch only: refuse if it already exists.
  push_args=(--force-with-lease="refs/heads/${branch}:" "${sha}:refs/heads/${branch}")
else
  push_args=("${sha}:refs/heads/${branch}")
fi
if ! git push -q "$remote" "${push_args[@]}"; then
  fail "Pushing to ${branch} was refused (see the run log). ${again}"
fi

if [[ "$MODE" == "build" ]]; then
  body="$(jq -r --arg issue "$ISSUE_NUMBER" -f "$here/render-pr-body.jq" <<< "$report")"
  if ! url="$(gh pr create --repo "$GITHUB_REPOSITORY" --base "$BASE_REF" --head "$branch" --title "$title" --body "$body")"; then
    fail "The branch ${branch} was pushed, but opening the pull request failed (see the run log). Open it from the branch yourself, or delete the branch and comment \`/approve\` again."
  fi
  pr="${url##*/}"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then { echo "pr=${pr}"; echo "sha=${sha}"; } >> "$GITHUB_OUTPUT"; fi
  gh issue comment "$ISSUE_NUMBER" --repo "$GITHUB_REPOSITORY" --body "<!-- ai-pipeline:built -->
🔧 Built the approved plan: ${url}. The AI review starts now." || echo "::warning::Couldn't comment on the issue."
  echo "Opened ${url}"
else
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then { echo "pr=${PR_NUMBER}"; echo "sha=${sha}"; } >> "$GITHUB_OUTPUT"; fi
  if [[ "$committed" == "true" ]]; then
    changes="$(jq -r '.changes | map("- `\(.path)`: \(.what)") | join("\n")' <<< "$report")"
    body="🔧 **${title}**

${summary}

${changes}"
  else
    body="🔄 Brought in the latest ${BASE_REF}; nothing else to change: ${summary}"
  fi
  gh pr comment "$PR_NUMBER" --repo "$GITHUB_REPOSITORY" --body "<!-- ai-pipeline:fixed -->
${body}

The AI review runs again now." || echo "::warning::Couldn't comment on the pull request."
fi

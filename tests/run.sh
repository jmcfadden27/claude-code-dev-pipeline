#!/usr/bin/env bash
# Offline checks for the pipeline's deterministic parts. No GitHub, no network, no AI.
#
#   tests/run.sh            run every check
#   tests/run.sh --update   rewrite the expected outputs from the current renderers (review the diff!)
#
# Needs bash and jq. Uses shellcheck, and python3 with jsonschema / PyYAML, when they are installed.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
scripts="$root/templates/pipeline/scripts"
schemas="$root/templates/pipeline/schemas"
fixtures="$root/tests/fixtures"
expected="$root/tests/expected"
update="${1:-}"
failures=0

pass() { printf '  \033[32mpass\033[0m  %s\n' "$1"; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; failures=$((failures + 1)); }
skip() { printf '  \033[33mskip\033[0m  %s\n' "$1"; }

# Compares a renderer's output with tests/expected/<name>.md (or rewrites it with --update).
check_render() {
  local name="$1" actual="$2"
  if [[ "$update" == "--update" ]]; then
    printf '%s\n' "$actual" > "$expected/$name.md"
    pass "$name (updated)"
  elif diff -u "$expected/$name.md" <(printf '%s\n' "$actual") > /tmp/pipeline-test-diff.$$ 2>&1; then
    pass "$name"
  else
    fail "$name"; cat /tmp/pipeline-test-diff.$$
  fi
  rm -f /tmp/pipeline-test-diff.$$
}

echo "Syntax"
for f in "$root"/scripts/*.sh "$scripts"/*.sh "$root"/tests/*.sh; do
  if bash -n "$f"; then pass "bash -n ${f#"$root"/}"; else fail "bash -n ${f#"$root"/}"; fi
done
for f in "$schemas"/*.json "$fixtures"/*.json "$fixtures"/review/*.json "$root"/templates/pipeline/claude-settings.json; do
  if jq empty "$f" 2>/dev/null; then pass "json ${f#"$root"/}"; else fail "json ${f#"$root"/}"; fi
done
for f in "$scripts"/*.jq; do
  # Compile only: wrap the program so it never runs.
  if jq -n --arg sha x --arg issue 1 --arg kind x --arg pr 1 --arg note x --argjson inline '[]' --argjson trusted '[]' "empty | ($(cat "$f")
)" > /dev/null 2>&1; then
    pass "jq compiles ${f#"$root"/}"
  else
    fail "jq compiles ${f#"$root"/}"
  fi
done

echo "Schemas"
for f in "$schemas"/*.json; do
  # The workflows pass each schema inside single quotes in claude_args.
  if grep -q "'" "$f"; then fail "no single quotes in ${f#"$root"/}"; else pass "no single quotes in ${f#"$root"/}"; fi
done
if python3 -c 'import jsonschema' 2>/dev/null; then
  validate() {
    if python3 - "$1" "$2" <<'PY'
import json, sys, jsonschema
jsonschema.validate(json.load(open(sys.argv[2])), json.load(open(sys.argv[1])))
PY
    then pass "$(basename "$2") matches $(basename "$1")"; else fail "$(basename "$2") matches $(basename "$1")"; fi
  }
  validate "$schemas/plan.schema.json" "$fixtures/plan-with-questions.json"
  validate "$schemas/plan.schema.json" "$fixtures/plan-ready.json"
  validate "$schemas/build-report.schema.json" "$fixtures/build-report.json"
  for f in "$fixtures"/review/*.json; do validate "$schemas/review-findings.schema.json" "$f"; done
else
  skip "fixture validation against the schemas (pip install jsonschema)"
fi

echo "Workflows"
if python3 -c 'import yaml' 2>/dev/null; then
  for f in "$root"/templates/.github/workflows/*.yml "$root"/templates/.github/ISSUE_TEMPLATE/*.yml; do
    if python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$f" 2>/dev/null; then
      pass "yaml ${f#"$root"/}"
    else
      fail "yaml ${f#"$root"/}"
    fi
  done
else
  skip "YAML parsing (pip install pyyaml)"
fi
for f in "$root"/templates/.github/workflows/*.yml; do
  # Untrusted event text must reach scripts through env, never through ${{ }} inside a run block.
  if grep -nE '^\s+run:.*\$\{\{ *github\.event\.(comment|issue|pull_request)\.(body|title)' "$f" > /dev/null; then
    fail "no event text interpolated into run: ${f#"$root"/}"
  else
    pass "no event text interpolated into run: ${f#"$root"/}"
  fi
done

echo "Renderers"
check_render plan-with-questions "$(jq -r -f "$scripts/render-plan.jq" "$fixtures/plan-with-questions.json")"
check_render plan-ready "$(jq -r -f "$scripts/render-plan.jq" "$fixtures/plan-ready.json")"
check_render pr-body "$(jq -r --arg issue 12 -f "$scripts/render-pr-body.jq" "$fixtures/build-report.json")"
check_render review "$(jq -s -r --arg sha 3f9c2e1a7b -f "$scripts/render-review.jq" "$fixtures"/review/*.json)"
check_render commit-message "$(jq -r --arg kind build --arg issue 12 --arg pr "" --arg note "" -f "$scripts/commit-message.jq" "$fixtures/build-report.json")"
check_render commit-message-breaking "$(jq '.commit.breaking = true | .commit.breakingChange = "GET /tasks no longer sorts by creation time first."' "$fixtures/build-report.json" \
  | jq -r --arg kind build --arg issue 12 --arg pr "" --arg note "" -f "$scripts/commit-message.jq")"
check_render commit-message-fix "$(jq '.commit.type = "fix" | .commit.summary = "compare due dates in utc"' "$fixtures/build-report.json" \
  | jq -r --arg kind fix --arg issue 12 --arg pr 14 --arg note "Also brings in the latest main." -f "$scripts/commit-message.jq")"
check_render pr-context "$(jq -n -r --argjson pr "$(cat "$fixtures/pr-view.json")" --argjson inline "$(cat "$fixtures/pr-inline-comments.json")" --argjson trusted '["jim"]' \
  -f "$scripts/pr-context.jq")"
check_render issue-context "$(jq -r --argjson trusted '["jim"]' -f "$scripts/issue-context.jq" "$fixtures/issue-view.json")"

echo "Examples"
# examples/ shows the renderers' real output: each file is a two-line caption, then the expected output.
for pair in "02-plan-with-questions:plan-with-questions" "04-plan-ready:plan-ready" "05-pull-request:pr-body" "06-review:review"; do
  example="${pair%%:*}"; name="${pair##*:}"
  if diff -q <(tail -n +3 "$root/examples/$example.md") "$expected/$name.md" > /dev/null; then
    pass "examples/$example.md matches the renderer"
  else
    fail "examples/$example.md matches the renderer (copy tests/expected/$name.md)"
  fi
done

echo "Behaviour"
context="$(jq -r --argjson trusted '["jim"]' -f "$scripts/issue-context.jq" "$fixtures/issue-view.json")"
if grep -q "crypto wallet" <<< "$context"; then fail "untrusted comments are withheld"; else pass "untrusted comments are withheld"; fi
if grep -q "Allow past dates" <<< "$context"; then pass "owner answers reach the agent"; else fail "owner answers reach the agent"; fi
if grep -q "ai-pipeline:plan" <<< "$context"; then pass "the pipeline's plan reaches the agent"; else fail "the pipeline's plan reaches the agent"; fi
prctx="$(jq -n -r --argjson pr "$(cat "$fixtures/pr-view.json")" --argjson inline "$(cat "$fixtures/pr-inline-comments.json")" --argjson trusted '["jim"]' \
  -f "$scripts/pr-context.jq")"
if grep -q "delete the tests folder\|Add my link" <<< "$prctx"; then fail "outsiders' PR comments are withheld"; else pass "outsiders' PR comments are withheld"; fi
if grep -A2 "What you were asked to fix" <<< "$prctx" | grep -q "compare dates in UTC"; then pass "the latest collaborator /fix is the request"; else fail "the latest collaborator /fix is the request"; fi
if grep -q "src/tasks/task-routes.ts:42" <<< "$prctx"; then pass "line comments reach the agent"; else fail "line comments reach the agent"; fi
review="$(jq -s -r --arg sha 3f9c2e1a7b -f "$scripts/render-review.jq" "$fixtures"/review/*.json)"
if [[ "$(grep -c "Overdue check compares dates" <<< "$review")" == "1" ]]; then
  pass "duplicate findings across lenses are merged"
else
  fail "duplicate findings across lenses are merged"
fi
if grep -q "high · correctness, tests" <<< "$review"; then
  pass "a merged finding keeps the highest severity and every lens"
else
  fail "a merged finding keeps the highest severity and every lens"
fi

# The header check in commit-change.sh, against good and bad headers.
header_pattern="$(sed -n "s/^header_pattern='\\(.*\\)'$/\\1/p" "$scripts/commit-change.sh")"
for good in "feat(tasks): add optional due dates to tasks" "fix(api)!: reject past due dates" "ci(infra): include lease-documents stack"; do
  if [[ "$good" =~ $header_pattern ]]; then pass "accepts: $good"; else fail "accepts: $good"; fi
done
for bad in "Add due dates" "feat: add due dates" "feat(Tasks): add due dates" "feat(tasks): Add due dates" "feat(tasks): add due dates." "feature(tasks): add due dates"; do
  if [[ "$bad" =~ $header_pattern ]]; then fail "rejects: $bad"; else pass "rejects: $bad"; fi
done

echo "Fix: merge with the base branch"
tmp="$(mktemp -d)"
if (
  cd "$tmp" && git init -q -b main && git config user.email t@t && git config user.name t
  printf 'a\nb\n' > f.txt && git add f.txt && git commit -q -m base
  git switch -q -c feature && printf 'a\nfeature\n' > f.txt && git commit -qam feature
  git switch -q main && printf 'a\nmain\n' > f.txt && git commit -qam main
  git switch -q feature && git update-ref refs/remotes/origin/main main
  BASE_REF=main "$scripts/merge-base.sh" > /dev/null
  [[ -s .pipeline/conflicts.txt ]] && grep -q f.txt .pipeline/conflicts.txt
) then pass "a conflicting base is left for the agent, files listed"; else fail "a conflicting base is left for the agent, files listed"; fi
rm -rf "$tmp"
tmp="$(mktemp -d)"
if (
  cd "$tmp" && git init -q -b main && git config user.email t@t && git config user.name t
  printf 'a\n' > f.txt && git add f.txt && git commit -q -m base
  git switch -q -c feature && printf 'x\n' > g.txt && git add g.txt && git commit -qm feature
  git switch -q main && printf 'b\n' > h.txt && git add h.txt && git commit -qm main
  git switch -q feature && git update-ref refs/remotes/origin/main main
  BASE_REF=main "$scripts/merge-base.sh" > /dev/null
  [[ ! -s .pipeline/conflicts.txt ]] && [[ -f h.txt ]]
) then pass "a clean base is merged before the agent runs"; else fail "a clean base is merged before the agent runs"; fi
rm -rf "$tmp"

echo "Commit for publishing"
report_ok="$(jq -c . "$fixtures/build-report.json")"
tmp="$(mktemp -d)"
if (
  cd "$tmp" && git init -q -b main && git config user.email t@t && git config user.name t
  printf 'a\n' > f.txt && git add f.txt && git commit -q -m base && git update-ref refs/remotes/origin/main main
  printf 'b\n' > g.txt
  MODE=build REPORT_JSON="$report_ok" OUT="$tmp.out" ISSUE_NUMBER=12 BASE_REF=main "$scripts/commit-change.sh" > /dev/null
  git bundle verify -q "$tmp.out/change.bundle" 2> /dev/null &&
    [[ "$(jq -r .nothing "$tmp.out/meta.json")" == "false" ]] &&
    [[ "$(jq -r .branch "$tmp.out/meta.json")" == ai/issue-12-* ]] &&
    [[ "$(jq -r .title "$tmp.out/meta.json")" == "feat(tasks): add optional due dates to tasks" ]]
); then pass "a build's change is committed and bundled for the publish job"; else fail "a build's change is committed and bundled for the publish job"; fi
rm -rf "$tmp" "$tmp.out"
tmp="$(mktemp -d)"
if (
  cd "$tmp" && git init -q -b main && git config user.email t@t && git config user.name t
  printf 'a\n' > f.txt && git add f.txt && git commit -q -m base && git update-ref refs/remotes/origin/feature main
  MODE=fix REPORT_JSON="$report_ok" OUT="$tmp.out" PR_NUMBER=14 HEAD_REF=feature BASE_REF=main RUNNER_TEMP="$tmp/rt" \
    "$scripts/commit-change.sh" > /dev/null
  [[ "$(jq -r .nothing "$tmp.out/meta.json")" == "true" ]] && [[ ! -e "$tmp.out/change.bundle" ]]
); then pass "a fix with nothing to change produces no bundle"; else fail "a fix with nothing to change produces no bundle"; fi
rm -rf "$tmp"
tmp="$(mktemp -d)"
if (
  cd "$tmp" && git init -q -b main && git config user.email t@t && git config user.name t
  printf 'a\n' > f.txt && git add f.txt && git commit -q -m base && git update-ref refs/remotes/origin/main main
  printf 'b\n' > g.txt
  ! MODE=build REPORT_JSON="$(jq -c '.status = "blocked"' "$fixtures/build-report.json")" OUT="$tmp.out" ISSUE_NUMBER=12 \
    BASE_REF=main "$scripts/commit-change.sh" > /dev/null 2>&1
); then pass "a blocked report commits nothing"; else fail "a blocked report commits nothing"; fi
rm -rf "$tmp"

echo "Installer"
tmp="$(mktemp -d)"
git init -q "$tmp"
echo "# Existing rules" > "$tmp/CLAUDE.md"
if "$root/scripts/install.sh" "$tmp" > /dev/null; then
  if [[ -x "$tmp/pipeline/scripts/publish.sh" ]]; then pass "installs executable scripts"; else fail "installs executable scripts"; fi
  if [[ -f "$tmp/.github/workflows/ai-build.yml" ]]; then pass "installs the workflows"; else fail "installs the workflows"; fi
  if [[ "$(cat "$tmp/CLAUDE.md")" == "# Existing rules" ]]; then pass "keeps an existing CLAUDE.md"; else fail "keeps an existing CLAUDE.md"; fi
else
  fail "install.sh runs"
fi
rm -rf "$tmp"

echo "Lint"
if command -v shellcheck > /dev/null; then
  if shellcheck "$root"/scripts/*.sh "$scripts"/*.sh "$root"/tests/*.sh; then pass "shellcheck"; else fail "shellcheck"; fi
else
  skip "shellcheck (brew install shellcheck)"
fi

echo
if (( failures > 0 )); then echo "${failures} check(s) failed."; exit 1; fi
echo "All checks passed."

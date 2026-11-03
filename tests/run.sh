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
  if jq -n --arg sha x --arg issue 1 --arg kind x --arg pr 1 --arg note x --argjson min 80 --argjson inline '[]' --argjson trusted '[]' "empty | ($(cat "$f")
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
check_render review "$(jq -s -r --arg sha 3f9c2e1a7b --argjson min 80 -f "$scripts/render-review.jq" "$fixtures"/review/*.json)"
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
if grep -q "STATUS-INJECTION" <<< "$context"; then fail "status comments (which can carry build-job text) are withheld from the agent"; else pass "status comments (which can carry build-job text) are withheld from the agent"; fi
prctx="$(jq -n -r --argjson pr "$(cat "$fixtures/pr-view.json")" --argjson inline "$(cat "$fixtures/pr-inline-comments.json")" --argjson trusted '["jim"]' \
  -f "$scripts/pr-context.jq")"
if grep -q "delete the tests folder\|Add my link" <<< "$prctx"; then fail "outsiders' PR comments are withheld"; else pass "outsiders' PR comments are withheld"; fi
if grep -A2 "What you were asked to fix" <<< "$prctx" | grep -q "compare dates in UTC"; then pass "the latest collaborator /fix is the request"; else fail "the latest collaborator /fix is the request"; fi
if grep -q "src/tasks/task-routes.ts:42" <<< "$prctx"; then pass "line comments reach the agent"; else fail "line comments reach the agent"; fi
if grep -q "STATUS-INJECTION" <<< "$prctx"; then fail "status comments are withheld from the fix agent"; else pass "status comments are withheld from the fix agent"; fi
if grep -A2 "What you were asked to fix" <<< "$prctx" | grep -q "fixed it locally"; then fail "'/fixed …' is not a fix request"; else pass "'/fixed …' is not a fix request"; fi
review="$(jq -s -r --arg sha 3f9c2e1a7b --argjson min 80 -f "$scripts/render-review.jq" "$fixtures"/review/*.json)"
if [[ "$(grep -c "Overdue check compares dates" <<< "$review")" == "1" ]]; then
  pass "duplicate findings across lenses are merged"
else
  fail "duplicate findings across lenses are merged"
fi
if grep -q "high · confidence 95 · correctness, tests" <<< "$review"; then
  pass "a merged finding keeps the highest severity and every lens"
else
  fail "a merged finding keeps the highest severity and every lens"
fi
if ! grep -q "Due date might be logged" <<< "$review" && grep -q "1 finding(s) below 80 confidence left out" <<< "$review"; then
  pass "findings below 80 confidence are left out and counted"
else
  fail "findings below 80 confidence are left out and counted"
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
tmp="$(mktemp -d)"
if (
  cd "$tmp" && git init -q -b main && git config user.email t@t && git config user.name t
  printf '\x00a' > img.bin && git add img.bin && git commit -q -m base
  git switch -q -c feature && printf '\x00feature' > img.bin && git commit -qam feature
  git switch -q main && printf '\x00main' > img.bin && git commit -qam main
  git switch -q feature && git update-ref refs/remotes/origin/main main
  ! BASE_REF=main RUNNER_TEMP="$tmp" "$scripts/merge-base.sh" > /dev/null 2>&1 &&
    [[ ! -f .git/MERGE_HEAD ]] && grep -q "binary files (img.bin)" "$tmp/failure-reason"
) then pass "a binary conflict stops with a reason"; else fail "a binary conflict stops with a reason"; fi
rm -rf "$tmp"
tmp="$(mktemp -d)"
if (
  cd "$tmp" && git init -q -b main && git config user.email t@t && git config user.name t
  printf 'a\n' > f.txt && git add f.txt && git commit -q -m base
  git switch -q -c feature && printf 'feature\n' > f.txt && git commit -qam feature
  git switch -q main && git rm -q f.txt && git commit -qm "delete f"
  git switch -q feature && git update-ref refs/remotes/origin/main main
  ! BASE_REF=main RUNNER_TEMP="$tmp" "$scripts/merge-base.sh" > /dev/null 2>&1 &&
    [[ ! -f .git/MERGE_HEAD ]] && grep -q "deleted a file the other changed (f.txt)" "$tmp/failure-reason"
) then pass "a delete/modify conflict stops with a reason"; else fail "a delete/modify conflict stops with a reason"; fi
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
    [[ "$(jq -r .title "$tmp.out/meta.json")" == "feat(tasks): add optional due dates to tasks" ]]
); then pass "a build's change is committed and bundled for the publish job"; else fail "a build's change is committed and bundled for the publish job"; fi
rm -rf "$tmp" "$tmp.out"
tmp="$(mktemp -d)"
if (
  cd "$tmp" && git init -q -b main && git config user.email t@t && git config user.name t
  printf 'a\n' > f.txt && git add f.txt && git commit -q -m base && git update-ref refs/remotes/origin/feature main
  MODE=fix REPORT_JSON="$report_ok" OUT="$tmp.out" PR_NUMBER=14 HEAD_REF=feature BASE_REF=main RUNNER_TEMP="$tmp/rt" \
    "$scripts/commit-change.sh" > /dev/null
  [[ ! -e "$tmp.out/change.bundle" ]] && [[ "$(jq -r .committed "$tmp.out/meta.json")" == "false" ]]
); then pass "a fix with nothing to change produces no bundle"; else fail "a fix with nothing to change produces no bundle"; fi
rm -rf "$tmp" "$tmp.out"
tmp="$(mktemp -d)"
if (
  cd "$tmp" && git init -q -b main && git config user.email t@t && git config user.name t
  printf 'a\n' > f.txt && git add f.txt && git commit -q -m base && git update-ref refs/remotes/origin/main main
  printf 'b\n' > g.txt
  ! MODE=build REPORT_JSON="$(jq -c '.status = "blocked"' "$fixtures/build-report.json")" OUT="$tmp.out" ISSUE_NUMBER=12 \
    BASE_REF=main "$scripts/commit-change.sh" > /dev/null 2>&1
); then pass "a blocked report commits nothing"; else fail "a blocked report commits nothing"; fi
rm -rf "$tmp" "$tmp.out"

# A fix whose merge conflicted: markers left in a conflicted file block the commit; a `=======` line elsewhere doesn't.
conflicted_fix() {
  cd "$1" && git init -q -b main && git config user.email t@t && git config user.name t
  printf 'Title\n=======\n' > README.md && printf 'a\nb\n' > f.txt && git add . && git commit -q -m base
  git switch -q -c feature && printf 'a\nfeature\n' > f.txt && git commit -qam feature
  git switch -q main && printf 'a\nmain\n' > f.txt && git commit -qam main
  git switch -q feature && git update-ref refs/remotes/origin/main main && git update-ref refs/remotes/origin/feature feature
  mkdir -p .pipeline "$1/rt" && echo ".pipeline/" >> .git/info/exclude
  BASE_REF=main RUNNER_TEMP="$1/rt" "$scripts/merge-base.sh" > /dev/null
}
tmp="$(mktemp -d)"
if (
  conflicted_fix "$tmp"
  : > .pipeline/conflicts.txt  # the agent emptying its copy of the list changes nothing
  ! MODE=fix REPORT_JSON="$report_ok" OUT="$tmp.out" PR_NUMBER=14 HEAD_REF=feature BASE_REF=main RUNNER_TEMP="$tmp/rt" \
    "$scripts/commit-change.sh" > /dev/null 2>&1 && grep -q "Unresolved merge conflicts remain in: f.txt" "$tmp/rt/failure-reason"
); then pass "unresolved conflict markers block the fix, with a reason"; else fail "unresolved conflict markers block the fix, with a reason"; fi
rm -rf "$tmp" "$tmp.out"
tmp="$(mktemp -d)"
if (
  conflicted_fix "$tmp"
  printf 'a\nboth\n' > f.txt
  MODE=fix REPORT_JSON="$report_ok" OUT="$tmp.out" PR_NUMBER=14 HEAD_REF=feature BASE_REF=main RUNNER_TEMP="$tmp/rt" \
    "$scripts/commit-change.sh" > /dev/null 2>&1 && git bundle verify -q "$tmp.out/change.bundle" 2> /dev/null
); then pass "a resolved conflict commits, a heading underline elsewhere is fine"; else fail "a resolved conflict commits, a heading underline elsewhere is fine"; fi
rm -rf "$tmp" "$tmp.out"

echo "Publish"
# A stand-in gh: `pr create` prints a pull request URL; everything else succeeds quietly.
fakebin="$(mktemp -d)"
cat > "$fakebin/gh" <<'GH'
#!/usr/bin/env bash
if [[ "$1 $2" == "pr create" ]]; then echo "https://github.com/o/r/pull/7"; fi
GH
chmod +x "$fakebin/gh"
# Sets up $1/remote.git (main, feature), a build in $1/work, and a fresh clone in $1/pub for the publish job.
publish_setup() {
  local t="$1"
  git init -q --bare -b main "$t/remote.git"
  git clone -q "$t/remote.git" "$t/seed" 2> /dev/null
  (cd "$t/seed" && git config user.email t@t && git config user.name t &&
    printf 'a\n' > f.txt && git add f.txt && git commit -q -m base && git push -q origin main &&
    git switch -q -c feature && printf 'x\n' > x.txt && git add x.txt && git commit -q -m feature && git push -q origin feature)
  git clone -q "$t/remote.git" "$t/work" 2> /dev/null
  git clone -q "$t/remote.git" "$t/pub" 2> /dev/null
}
publish() { # dir, then env assignments
  local dir="$1"; shift
  (cd "$dir" && env PATH="$fakebin:$PATH" GH_TOKEN=x GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=99 RUNNER_TEMP="$dir/rt" \
    PIPELINE_PUSH_URL="$(cd "$dir/../remote.git" && pwd)" GITHUB_OUTPUT="$dir/out.txt" "$@" "$scripts/publish.sh")
}
tmp="$(mktemp -d)"
if (
  publish_setup "$tmp"
  cd "$tmp/work" && git config user.email t@t && git config user.name t && printf 'b\n' > g.txt
  MODE=build REPORT_JSON="$report_ok" OUT="$tmp/in" ISSUE_NUMBER=12 BASE_REF=main "$scripts/commit-change.sh" > /dev/null
  # Whatever the build job claims, publish decides where the commits go.
  jq '. + {branch: "main", mode: "fix", pr: "3"}' "$tmp/in/meta.json" > "$tmp/m" && mv "$tmp/m" "$tmp/in/meta.json"
  mkdir -p "$tmp/pub/rt"
  base_sha="$(git -C "$tmp/seed" rev-parse main)"
  # main moves on while the build runs.
  (cd "$tmp/seed" && git switch -q main && printf 'n\n' > n.txt && git add n.txt && git commit -q -m newer && git push -q origin main)
  git -C "$tmp/pub" fetch -q origin
  publish "$tmp/pub" IN="$tmp/in" MODE=build ISSUE_NUMBER=12 BASE_REF=main BASE_SHA="$base_sha" > /dev/null
  [[ "$(git -C "$tmp/remote.git" rev-parse ai/issue-12-99-1)" == "$(git -C "$tmp/work" rev-parse HEAD)" ]] &&
    [[ "$(git -C "$tmp/remote.git" rev-parse main)" == "$(git -C "$tmp/seed" rev-parse main)" ]] &&
    grep -q "^pr=7$" "$tmp/pub/out.txt"
); then pass "a build is pushed to a new branch chosen by publish, never where the artifact says, even after main moved"; else fail "a build is pushed to a new branch chosen by publish, never where the artifact says, even after main moved"; fi
rm -rf "$tmp"
tmp="$(mktemp -d)"
if (
  publish_setup "$tmp"
  cd "$tmp/work" && git config user.email t@t && git config user.name t
  git switch -q --orphan other && printf 'z\n' > z.txt && git add z.txt && git commit -q -m other
  git branch -f pipeline-result HEAD && mkdir -p "$tmp/in" && git bundle create -q "$tmp/in/change.bundle" pipeline-result 2> /dev/null
  echo '{"title":"feat(x): add y"}' > "$tmp/in/meta.json" && printf '%s' "$report_ok" > "$tmp/in/report.json"
  mkdir -p "$tmp/pub/rt"
  ! publish "$tmp/pub" IN="$tmp/in" MODE=build ISSUE_NUMBER=12 BASE_REF=main BASE_SHA="$(git -C "$tmp/seed" rev-parse main)" > /dev/null 2>&1 &&
    ! git -C "$tmp/remote.git" rev-parse -q --verify ai/issue-12-99-1 > /dev/null && grep -q "don't sit on top of" "$tmp/pub/rt/failure-reason"
); then pass "commits that don't sit on the base are refused"; else fail "commits that don't sit on the base are refused"; fi
rm -rf "$tmp"
tmp="$(mktemp -d)"
if (
  publish_setup "$tmp"
  cd "$tmp/work" && git config user.email t@t && git config user.name t && printf 'b\n' > g.txt
  MODE=build REPORT_JSON="$report_ok" OUT="$tmp/in" ISSUE_NUMBER=12 BASE_REF=main "$scripts/commit-change.sh" > /dev/null
  git -C "$tmp/seed" push -q origin main:refs/heads/ai/issue-12-99-1
  mkdir -p "$tmp/pub/rt"
  ! publish "$tmp/pub" IN="$tmp/in" MODE=build ISSUE_NUMBER=12 BASE_REF=main BASE_SHA="$(git -C "$tmp/seed" rev-parse main)" > /dev/null 2>&1 &&
    [[ "$(git -C "$tmp/remote.git" rev-parse ai/issue-12-99-1)" == "$(git -C "$tmp/seed" rev-parse main)" ]]
); then pass "a build never overwrites an existing branch"; else fail "a build never overwrites an existing branch"; fi
rm -rf "$tmp"
tmp="$(mktemp -d)"
if (
  publish_setup "$tmp"
  head_sha="$(git -C "$tmp/seed" rev-parse feature)"
  cd "$tmp/work" && git config user.email t@t && git config user.name t && git switch -q feature && printf 'y\n' > y.txt
  MODE=fix REPORT_JSON="$report_ok" OUT="$tmp/in" PR_NUMBER=14 HEAD_REF=feature HEAD_SHA="$head_sha" BASE_REF=main \
    RUNNER_TEMP="$tmp/rt" "$scripts/commit-change.sh" > /dev/null
  mkdir -p "$tmp/pub/rt"
  publish "$tmp/pub" IN="$tmp/in" MODE=fix PR_NUMBER=14 HEAD_REF=feature HEAD_SHA="$head_sha" BASE_REF=main > /dev/null
  [[ "$(git -C "$tmp/remote.git" rev-parse feature)" == "$(git -C "$tmp/work" rev-parse HEAD)" ]] && grep -q "^pr=14$" "$tmp/pub/out.txt"
); then pass "a fix is pushed to the pull request's branch"; else fail "a fix is pushed to the pull request's branch"; fi
rm -rf "$tmp"
tmp="$(mktemp -d)"
if (
  publish_setup "$tmp"
  head_sha="$(git -C "$tmp/seed" rev-parse feature)"
  cd "$tmp/work" && git config user.email t@t && git config user.name t && git switch -q feature && printf 'y\n' > y.txt
  MODE=fix REPORT_JSON="$report_ok" OUT="$tmp/in" PR_NUMBER=14 HEAD_REF=feature HEAD_SHA="$head_sha" BASE_REF=main \
    RUNNER_TEMP="$tmp/rt" "$scripts/commit-change.sh" > /dev/null
  # Someone pushes to the pull request while the fix runs.
  (cd "$tmp/seed" && git switch -q feature && printf 'z\n' > z.txt && git add z.txt && git commit -q -m theirs && git push -q origin feature)
  git -C "$tmp/pub" fetch -q origin
  mkdir -p "$tmp/pub/rt"
  ! publish "$tmp/pub" IN="$tmp/in" MODE=fix PR_NUMBER=14 HEAD_REF=feature HEAD_SHA="$head_sha" BASE_REF=main > /dev/null 2>&1 &&
    [[ "$(git -C "$tmp/remote.git" rev-parse feature)" == "$(git -C "$tmp/seed" rev-parse feature)" ]]
); then pass "a fix never overwrites commits pushed after /fix was accepted"; else fail "a fix never overwrites commits pushed after /fix was accepted"; fi
rm -rf "$tmp"
tmp="$(mktemp -d)"
if (
  publish_setup "$tmp"
  cd "$tmp/work" && git config user.email t@t && git config user.name t && mkdir -p .github/workflows && printf 'x\n' > .github/workflows/ci.yml
  MODE=build REPORT_JSON="$report_ok" OUT="$tmp/in" ISSUE_NUMBER=12 BASE_REF=main "$scripts/commit-change.sh" > /dev/null
  mkdir -p "$tmp/pub/rt"
  ! publish "$tmp/pub" IN="$tmp/in" MODE=build ISSUE_NUMBER=12 BASE_REF=main BASE_SHA="$(git -C "$tmp/seed" rev-parse main)" > /dev/null 2>&1 &&
    grep -q "touches workflow files (.github/workflows/ci.yml)" "$tmp/pub/rt/failure-reason"
); then pass "a change to workflow files is refused with a reason"; else fail "a change to workflow files is refused with a reason"; fi
rm -rf "$tmp"
tmp="$(mktemp -d)"
if (
  publish_setup "$tmp"
  cd "$tmp/work" && git config user.email t@t && git config user.name t && printf 'b\n' > g.txt
  MODE=build REPORT_JSON="$report_ok" OUT="$tmp/in" ISSUE_NUMBER=12 BASE_REF=main "$scripts/commit-change.sh" > /dev/null
  echo '{"title":"Update everything @someone"}' > "$tmp/in/meta.json"
  mkdir -p "$tmp/pub/rt"
  ! publish "$tmp/pub" IN="$tmp/in" MODE=build ISSUE_NUMBER=12 BASE_REF=main BASE_SHA="$(git -C "$tmp/seed" rev-parse main)" > /dev/null 2>&1 &&
    ! git -C "$tmp/remote.git" rev-parse -q --verify ai/issue-12-99-1 > /dev/null
); then pass "a title that isn't a Conventional Commits header is refused"; else fail "a title that isn't a Conventional Commits header is refused"; fi
rm -rf "$tmp"
tmp="$(mktemp -d)"
if (
  publish_setup "$tmp"
  head_sha="$(git -C "$tmp/seed" rev-parse feature)"
  (cd "$tmp/seed" && git switch -q main && printf 'n\n' > n.txt && git add n.txt && git commit -q -m newer && git push -q origin main)
  # A fix that only brought in the base: the merge commit is its only new commit.
  cd "$tmp/work" && git config user.email t@t && git config user.name t && git switch -q feature && git fetch -q origin &&
    git merge -q --no-edit origin/main && git branch -f pipeline-result HEAD && mkdir -p "$tmp/in" &&
    git bundle create -q "$tmp/in/change.bundle" pipeline-result "^${head_sha}" 2> /dev/null
  echo '{"title":"fix(tasks): compare due dates in utc","committed":false}' > "$tmp/in/meta.json"
  printf '%s' "$report_ok" > "$tmp/in/report.json"
  # shellcheck disable=SC2016 # the stand-in's own $* and $0
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$(dirname "$0")/calls"\n' > "$tmp/gh" && chmod +x "$tmp/gh"
  git -C "$tmp/pub" fetch -q origin && mkdir -p "$tmp/pub/rt"
  (cd "$tmp/pub" && env PATH="$tmp:$PATH" GH_TOKEN=x GITHUB_REPOSITORY=o/r GITHUB_RUN_ID=99 RUNNER_TEMP="$tmp/pub/rt" \
    PIPELINE_PUSH_URL="$tmp/remote.git" IN="$tmp/in" MODE=fix PR_NUMBER=14 HEAD_REF=feature HEAD_SHA="$head_sha" \
    BASE_REF=main "$scripts/publish.sh") > /dev/null
  grep -q "Brought in the latest main" "$tmp/calls"
); then pass "a fix that only brought in the base says so"; else fail "a fix that only brought in the base says so"; fi
rm -rf "$tmp" "$fakebin"

echo "Review comment"
# A stand-in gh that records what's posted; $1 = the comments the pull request already has.
review_gh() {
  cat > "$1/gh" <<GH
#!/usr/bin/env bash
log="\$(dirname "\$0")/calls"
if [[ "\$1 \$2" == "pr comment" ]]; then echo "NEW" >> "\$log"; echo "https://github.com/o/r/pull/14#issuecomment-9"
elif [[ "\$1 \$2" == "api -X" ]]; then echo "PATCH \$4" >> "\$log"; echo "https://github.com/o/r/pull/14#issuecomment-1"
elif [[ "\$1 \$2" == "pr view" ]]; then echo '${3:-3f9c2e1a7b}'
else echo '$2'
fi
GH
  chmod +x "$1/gh"
}
for case in "none:[]:NEW" "existing:[{\"id\":1,\"user\":{\"login\":\"github-actions[bot]\"},\"body\":\"<!-- ai-pipeline:review -->\\nold\"},{\"id\":2,\"user\":{\"login\":\"jim\"},\"body\":\"<!-- ai-pipeline:review -->\\nquoted\"}]:PATCH repos/o/r/issues/comments/1"; do
  name="${case%%:*}"; rest="${case#*:}"; comments="${rest%:*}"; want="${rest##*:}"
  tmp="$(mktemp -d)"; review_gh "$tmp" "$comments"
  if (
    PATH="$tmp:$PATH" FINDINGS_DIR="$fixtures/review" PR_NUMBER=14 HEAD_SHA=3f9c2e1a7b GITHUB_REPOSITORY=o/r GH_TOKEN=x \
      GITHUB_OUTPUT="$tmp/out" "$scripts/post-review.sh" > /dev/null
    [[ "$(cat "$tmp/calls")" == "$want" ]] && grep -q "^url=https://github.com/o/r/pull/14#issuecomment-" "$tmp/out" &&
      grep -q "^result=changes requested by 1 of 4 reviewers" "$tmp/out"
  ); then pass "the review comment: ${name} → ${want%% *}, its link and result returned"; else fail "the review comment: ${name} → ${want%% *}, its link and result returned"; cat "$tmp/calls" "$tmp/out"; fi
  rm -rf "$tmp"
done
tmp="$(mktemp -d)"; review_gh "$tmp" "[]" "9999999newer"
if (
  PATH="$tmp:$PATH" FINDINGS_DIR="$fixtures/review" PR_NUMBER=14 HEAD_SHA=3f9c2e1a7b GITHUB_REPOSITORY=o/r GH_TOKEN=x \
    GITHUB_OUTPUT="$tmp/out" "$scripts/post-review.sh" > /dev/null 2>&1
  [[ ! -s "$tmp/calls" ]] && grep -q "^result=not posted" "$tmp/out"
); then pass "an older review never replaces a newer one"; else fail "an older review never replaces a newer one"; fi
rm -rf "$tmp"
tmp="$(mktemp -d)"; review_gh "$tmp" "[]"
if (
  PATH="$tmp:$PATH" FINDINGS_DIR="$fixtures/review" PR_NUMBER=14 HEAD_SHA=3f9c2e1a7b GITHUB_REPOSITORY=o/r GH_TOKEN=x \
    MIN_CONFIDENCE=08 GITHUB_OUTPUT="$tmp/out" "$scripts/post-review.sh" > /dev/null 2>&1
  grep -q "^result=" "$tmp/out"
); then pass "a confidence minimum like 08 is read as 8"; else fail "a confidence minimum like 08 is read as 8"; fi
rm -rf "$tmp"

echo "Status"
# A stand-in gh that records every call's arguments.
status_gh() {
  cat > "$1/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$(dirname "$0")/calls"
if [[ "$*" == *"--jq .id"* ]]; then echo 555; fi
if [[ "$*" == *"/comments --paginate"* ]]; then echo '[]'; fi
GH
  chmod +x "$1/gh"
}
status_env=(GH_TOKEN=x GITHUB_REPOSITORY=o/r GITHUB_SERVER_URL=https://github.com GITHUB_RUN_ID=77 NUMBER=12 COMMENT_ID=4 STAGE=Plan)
tmp="$(mktemp -d)"; status_gh "$tmp"
if (
  env PATH="$tmp:$PATH" "${status_env[@]}" GITHUB_OUTPUT="$tmp/out" SUPERSEDE=true "$scripts/post-status.sh" start > /dev/null
  grep -q "comments/4/reactions -f content=eyes" "$tmp/calls" && grep -q "⏳ \*\*Plan\*\* running" "$tmp/calls" &&
    grep -q "run=77" "$tmp/calls" && grep -q "^status_id=555$" "$tmp/out"
); then pass "start: 👀 on the command and one status comment"; else fail "start: 👀 on the command and one status comment"; cat "$tmp/calls"; fi
rm -rf "$tmp"
finish() { # $1 = command, $2 = needs JSON, $3 = what the status comment must say
  local tmp; tmp="$(mktemp -d)"; status_gh "$tmp"
  if (
    env PATH="$tmp:$PATH" "${status_env[@]}" RUNNER_TEMP="$tmp/rt" STATUS_ID=555 COMMAND="$1" NEEDS="$2" \
      "$scripts/finish.sh" > /dev/null
    grep -q -- "$3" "$tmp/calls"
  ); then pass "finish ($1): $3"; else fail "finish ($1): $3"; cat "$tmp/calls"; fi
  rm -rf "$tmp"
}
finish plan '{"plan":{"result":"success","outputs":{"url":"https://x/c1","ready":"true"}}}' "Comment \`/approve\` to build it"
finish approve '{"build":{"result":"success"},"publish":{"result":"success","outputs":{"url":"https://x/pull/5"}},"review":{"result":"success"},"summarize":{"result":"success","outputs":{"url":"https://x/r","result":"no blocking findings"}}}' 'opened https://x/pull/5 · \[AI review\](https://x/r): no blocking findings'
finish fix '{"build":{"result":"success"},"publish":{"result":"success","outputs":{"note":"Already done."}}}' 'nothing to change: Already done.'
finish fix '{"build":{"result":"failure"}}' '⚠️ \*\*Plan\*\* failed'
finish approve '{"build":{"result":"cancelled"}}' 'build job stopped at its time limit'
finish approve '{"build":{"result":"success"},"publish":{"result":"success","outputs":{"url":"https://x/pull/5"}},"review":{"result":"failure"},"summarize":{"result":"success","outputs":{"url":"https://x/r","result":"no blocking findings"}}}' "\*\* done, but the review didn't finish · opened https://x/pull/5"
finish review '{"review":{"result":"failure"},"summarize":{"result":"skipped"}}' '⚠️ \*\*Plan\*\* failed'
tmp="$(mktemp -d)"
cat > "$tmp/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$(dirname "$0")/calls"
if [[ "$*" == *"status=in_progress"* ]]; then
  echo '{"id":101,"display_title":"/fix #12 · Add due dates"}'
  echo '{"id":102,"display_title":"/fix #120 · Other #12 issue"}'
  echo '{"id":103,"display_title":"/review #12 · Add due dates"}'
  echo '{"id":77,"display_title":"/cancel #12 · Add due dates"}'
fi
if [[ "$*" == *"runs/103/cancel"* ]]; then exit 1; fi
if [[ "$*" == *"/comments --paginate"* ]]; then
  echo '[{"id":9,"user":{"login":"github-actions[bot]"},"body":"<!-- ai-pipeline:status run=101 -->\n⏳ **Fix** running"},
         {"id":10,"user":{"login":"github-actions[bot]"},"body":"<!-- ai-pipeline:status run=103 -->\n✅ **Fix** done"}]'
fi
GH
chmod +x "$tmp/gh"
if (
  env PATH="$tmp:$PATH" "${status_env[@]}" ACTOR=jim WORKFLOW_FILE=ai-pipeline.yml "$scripts/cancel-runs.sh" > /dev/null
  grep -q "runs/101/cancel" "$tmp/calls" && ! grep -q "runs/102/cancel\|runs/77/cancel" "$tmp/calls" &&
    grep -q "comments/9 -f body=<!-- ai-pipeline:status run=101 -->" "$tmp/calls" && grep -q "⏹ \*\*Fix\*\* cancelled by @jim" "$tmp/calls" &&
    ! grep -q "comments/10 " "$tmp/calls"
); then pass "/cancel cancels only this issue's runs, and marks only the ones it really cancelled"; else fail "/cancel cancels only this issue's runs, and marks only the ones it really cancelled"; cat "$tmp/calls"; fi
rm -rf "$tmp"

echo "Commands"
parse() { COMMENT_BODY="$1" IS_PR="$2" "$scripts/parse-command.sh"; }
for c in "/plan:false:plan" "/Plan:false:plan" "/plan use UTC:false:plan" $'/plan\nAnswers: yes:false:plan' \
  $'/plan\r\nAnswers: yes:false:plan' $'/approve\r\n:false:approve' $'/fix\r\n- add a test:true:fix' "/approve:false:approve" \
  "/fix add a test:true:fix" "/review:true:review" "/cancel:true:cancel" "/cancel:false:cancel" \
  "/planning:false:" "/approved:false:" "please /plan:false:" "/fix:false:" "/plan:true:" "/approve:true:" "/review:false:" ":false:"; do
  want="${c##*:}"; rest="${c%:*}"; is_pr="${rest##*:}"; body="${rest%:*}"
  if [[ "$(parse "$body" "$is_pr")" == "$want" ]]; then pass "'${body%%$'\n'*}' on $([[ $is_pr == true ]] && echo a PR || echo an issue) → ${want:-nothing}"
  else fail "'${body%%$'\n'*}' on $([[ $is_pr == true ]] && echo a PR || echo an issue) → ${want:-nothing}"; fi
done

echo "Installer"
tmp="$(mktemp -d)"
git init -q "$tmp"
echo "# Existing rules" > "$tmp/CLAUDE.md"
if "$root/scripts/install.sh" "$tmp" > /dev/null; then
  if [[ -x "$tmp/pipeline/scripts/publish.sh" ]]; then pass "installs executable scripts"; else fail "installs executable scripts"; fi
  if [[ -f "$tmp/.github/workflows/ai-pipeline.yml" ]]; then pass "installs the workflow"; else fail "installs the workflow"; fi
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

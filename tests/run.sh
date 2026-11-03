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
  cd "$tmp/work" && git config user.email t@t && git config user.name t && git switch -q feature && printf 'y\n' > y.txt
  MODE=fix REPORT_JSON="$report_ok" OUT="$tmp/in" PR_NUMBER=14 HEAD_REF=feature BASE_REF=main RUNNER_TEMP="$tmp/rt" \
    "$scripts/commit-change.sh" > /dev/null
  mkdir -p "$tmp/pub/rt"
  publish "$tmp/pub" IN="$tmp/in" MODE=fix PR_NUMBER=14 HEAD_REF=feature BASE_REF=main > /dev/null
  [[ "$(git -C "$tmp/remote.git" rev-parse feature)" == "$(git -C "$tmp/work" rev-parse HEAD)" ]] && grep -q "^pr=14$" "$tmp/pub/out.txt"
); then pass "a fix is pushed to the pull request's branch"; else fail "a fix is pushed to the pull request's branch"; fi
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
rm -rf "$tmp" "$fakebin"

echo "Commands"
gate() { env -i PATH="$PATH" ACTOR=jim GITHUB_REPOSITORY=o/r GH_TOKEN=x COMMAND=/plan COMMENT_BODY="$1" "$scripts/require-write-access.sh" > /dev/null 2>&1; }
for bad in "/planning" "/approve" "please /plan" ""; do
  if gate "$bad"; then fail "rejects the comment: '$bad'"; else pass "rejects the comment: '$bad'"; fi
done
fakebin="$(mktemp -d)"
printf '#!/usr/bin/env bash\necho write\n' > "$fakebin/gh" && chmod +x "$fakebin/gh"
for good in "/plan" "/Plan" "/plan use UTC" $'/plan\nAnswers: yes'; do
  if PATH="$fakebin:$PATH" gate "$good"; then pass "accepts the comment: '${good%%$'\n'*}'"; else fail "accepts the comment: '${good%%$'\n'*}'"; fi
done
rm -rf "$fakebin"

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

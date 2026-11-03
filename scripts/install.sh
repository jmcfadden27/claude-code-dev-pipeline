#!/usr/bin/env bash
# Copies the pipeline's template files into a target repository.
#
#   scripts/install.sh /path/to/your-repo [--force]
#
# Existing files are never overwritten unless --force is given (--force also replaces your run-checks.sh, ai-build.yml
# and CLAUDE.md: to update an installed pipeline, follow docs/setup.md "Updating" instead). Nothing is committed or pushed: review the copied
# files, configure pipeline/scripts/run-checks.sh and the toolchain step in ai-build.yml, then commit them yourself.
set -euo pipefail

usage() { echo "Usage: $0 <target-repo> [--force]" >&2; exit 2; }
[[ $# -ge 1 ]] || usage
target="$1"
force="${2:-}"
[[ -z "$force" || "$force" == "--force" ]] || usage
[[ -d "$target/.git" ]] || { echo "Not a git repository: $target" >&2; exit 1; }

src="$(cd "$(dirname "$0")/../templates" && pwd)"
copied=0
skipped=0

while IFS= read -r -d '' file; do
  rel="${file#"$src"/}"
  dest="$target/$rel"
  # CLAUDE.md.example is installed as CLAUDE.md only when the repository has none.
  if [[ "$rel" == "CLAUDE.md.example" ]]; then dest="$target/CLAUDE.md"; fi
  if [[ -e "$dest" && "$force" != "--force" ]]; then
    echo "  skip    ${dest#"$target"/} (exists)"
    skipped=$((skipped + 1))
    continue
  fi
  mkdir -p "$(dirname "$dest")"
  cp "$file" "$dest"
  [[ "$dest" == *.sh ]] && chmod +x "$dest"
  echo "  copy    ${dest#"$target"/}"
  copied=$((copied + 1))
done < <(find "$src" -type f -print0 | sort -z)

cat <<EOF

Copied ${copied} file(s), skipped ${skipped}.

Next steps (see docs/setup.md):
  1. Edit pipeline/scripts/run-checks.sh with your build and test commands.
  2. Add your toolchain setup to the marked step in .github/workflows/ai-build.yml.
  3. Fill in CLAUDE.md with your project's rules.
  4. Add the CLAUDE_CODE_OAUTH_TOKEN secret.
  5. Repository settings: allow GitHub Actions to create pull requests.
  6. Create the status labels: scripts/create-labels.sh <owner/repo>
  7. Commit, push, open an issue with the "Change request (AI pipeline)" form, and comment /plan.
EOF

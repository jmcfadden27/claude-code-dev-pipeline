#!/usr/bin/env bash
# Saves and restores the files claude-code-action replaces with the default branch's copies on pull request events
# (CLAUDE.md, .claude/ and similar), so a fix commit keeps the pull request's own versions.
#
#   snapshot-config.sh save      after merging the base, before the agent runs
#   snapshot-config.sh restore   before committing the fix
#
# Env: RUNNER_TEMP (or TMPDIR).
set -euo pipefail

paths=(CLAUDE.md CLAUDE.local.md .claude .mcp.json .claude.json .gitmodules .ripgreprc .husky)
store="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/config-snapshot"

case "${1:-}" in
  save)
    rm -rf "$store" && mkdir -p "$store"
    for p in "${paths[@]}"; do
      if [[ -e "$p" ]]; then cp -a "$p" "$store/"; fi
    done
    ;;
  restore)
    [[ -d "$store" ]] || { echo "No snapshot to restore."; exit 0; }
    for p in "${paths[@]}"; do
      rm -rf "$p"
      if [[ -e "$store/$p" ]]; then cp -a "$store/$p" "$p"; fi
    done
    rm -rf .claude-pr
    ;;
  *)
    echo "Usage: $0 save|restore" >&2
    exit 2
    ;;
esac

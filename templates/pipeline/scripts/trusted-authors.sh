#!/usr/bin/env bash
# Prints a JSON array of the logins, among those given on stdin (one per line), that have write, maintain or admin
# access to the repository: the people whose comments may reach the agents.
#
# Comment metadata (author_association) isn't enough on its own: GitHub reports private organization members as
# CONTRIBUTOR or NONE, which would wrongly withhold the requester's own comments.
#
# Env: GITHUB_REPOSITORY, GH_TOKEN.
set -euo pipefail

trusted=()
while IFS= read -r login; do
  [[ -z "$login" ]] && continue
  permission="$(gh api "repos/${GITHUB_REPOSITORY}/collaborators/${login}/permission" --jq '.permission' 2>/dev/null || echo none)"
  case "$permission" in
    admin | maintain | write) trusted+=("$login") ;;
  esac
done < <(sort -u)

if (( ${#trusted[@]} == 0 )); then echo '[]'; else printf '%s\n' "${trusted[@]}" | jq -R . | jq -s -c .; fi

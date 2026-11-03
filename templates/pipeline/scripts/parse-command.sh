#!/usr/bin/env bash
# Prints the pipeline command a comment gives (plan, approve, fix, review or cancel), or nothing when it gives none.
#
# The comment's first word must be the command itself, in any letter case (`/approved` or `please /plan` are not
# commands). /plan and /approve work on issues, /fix and /review on pull requests, /cancel on both.
#
# Env: COMMENT_BODY, IS_PR (true | false).
set -euo pipefail

# Comments typed in GitHub's editor end lines with CRLF: drop the carriage returns first.
body="${COMMENT_BODY:-}"
read -r first _ <<< "${body//$'\r'/}" || true
word="$(tr '[:upper:]' '[:lower:]' <<< "${first:-}")"
case "${word}:${IS_PR:-false}" in
  /plan:false | /approve:false | /fix:true | /review:true | /cancel:*) echo "${word#/}" ;;
  *) ;;
esac

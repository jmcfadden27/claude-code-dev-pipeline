#!/usr/bin/env bash
# Creates the status labels the pipeline sets on issues (you start every stage with a comment command, not a label).
# Needs the GitHub CLI, signed in with access to the repository.
#
#   scripts/create-labels.sh owner/repo
set -euo pipefail

repo="${1:?Usage: $0 owner/repo}"

create() {
  gh label create "$1" --repo "$repo" --color "$2" --description "$3" --force
}

create "ai:needs-answers" "FBCA04" "The AI pipeline has questions on its plan"
create "ai:plan-ready"    "0E8A16" "The AI plan has no open questions"

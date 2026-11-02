#!/usr/bin/env bash
# Creates the labels the pipeline uses in a repository. Needs the GitHub CLI, signed in with access to the repository.
#
#   scripts/create-labels.sh owner/repo
set -euo pipefail

repo="${1:?Usage: $0 owner/repo}"

create() {
  gh label create "$1" --repo "$repo" --color "$2" --description "$3" --force
}

create "ai:plan"          "1D76DB" "Ask the AI pipeline for an implementation plan"
create "ai:needs-answers" "FBCA04" "The AI pipeline has questions on its plan"
create "ai:plan-ready"    "0E8A16" "The AI plan has no open questions"
create "ai:approved"      "5319E7" "Approve the latest AI plan and build it"
create "ai:review"        "D93F0B" "Ask for an AI review of this pull request"

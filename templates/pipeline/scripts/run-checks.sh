#!/usr/bin/env bash
# The project's build and test gate. Edit this file for your repository.
#
# The build agent is allowed to run exactly this script and nothing else in the shell
# (--allowedTools "Bash(./pipeline/scripts/run-checks.sh)"), and the build workflow runs it again itself before it
# opens a pull request. Keep it deterministic and non-interactive: exit 0 only when everything passes.
set -euo pipefail

# In CI, keep the tokens the pipeline and claude-code-action hold out of the project's code (tests the agent wrote
# included), and the token the action writes into the origin URL. (A best effort: the build job holds nothing that can
# push or comment either; see docs/security.md.)
if [[ "${CI:-}" == "true" ]]; then
  unset GITHUB_TOKEN GH_TOKEN DEFAULT_WORKFLOW_TOKEN OVERRIDE_GITHUB_TOKEN ALL_INPUTS CLAUDE_ARGS \
    ACTIONS_ID_TOKEN_REQUEST_TOKEN ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_RUNTIME_TOKEN \
    CLAUDE_CODE_OAUTH_TOKEN INPUT_CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY INPUT_ANTHROPIC_API_KEY
  git remote set-url origin "https://github.com/${GITHUB_REPOSITORY}.git" 2> /dev/null || true
fi

# Examples — uncomment and adapt one:
#
#   npm ci && npm run lint && npm test
#   dotnet build -warnaserror && dotnet test --no-build
#   ./gradlew assembleDebug testDebugUnitTest
#   python -m pip install -r requirements.txt && pytest -q

echo "::error::pipeline/scripts/run-checks.sh is not configured for this repository yet."
exit 1

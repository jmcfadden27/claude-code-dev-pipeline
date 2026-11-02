#!/usr/bin/env bash
# The project's build and test gate. Edit this file for your repository.
#
# The build agent is allowed to run exactly this script and nothing else in the shell
# (--allowedTools "Bash(./pipeline/scripts/run-checks.sh)"), and the build workflow runs it again itself before it
# opens a pull request. Keep it deterministic and non-interactive: exit 0 only when everything passes.
set -euo pipefail

# Examples — uncomment and adapt one:
#
#   npm ci && npm run lint && npm test
#   dotnet build -warnaserror && dotnet test --no-build
#   ./gradlew assembleDebug testDebugUnitTest
#   python -m pip install -r requirements.txt && pytest -q

echo "::error::pipeline/scripts/run-checks.sh is not configured for this repository yet."
exit 1

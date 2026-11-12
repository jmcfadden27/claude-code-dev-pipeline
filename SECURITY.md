# Security policy

The pipeline runs AI agents with access to a repository's code, so security issues matter here: for example a way for
someone without write access to start a run or steer an agent, for an agent to reach a token, or for a change to be
pushed somewhere other than where the publish job decides.

## Reporting a vulnerability

Please report security issues privately, not in a public issue: use GitHub's
[private vulnerability reporting](https://github.com/jmcfadden27/claude-code-dev-pipeline/security/advisories/new)
for this repository.

Include what you found, how to reproduce it, and the version or commit affected. You'll get a reply as soon as
possible, and a fix or advice will be published once the issue is understood.

The pipeline's threat model and the controls behind each trust boundary are described in
[docs/security.md](docs/security.md).

## Supported versions

Fixes go into the latest release.

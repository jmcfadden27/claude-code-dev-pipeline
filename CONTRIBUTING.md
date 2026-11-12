# Contributing

Issues and pull requests are welcome.

- **Bugs:** open an issue with what happened, what you expected, and the command, comment or workflow run that shows
  it (with secrets removed).
- **Changes:** for anything beyond a small fix, open an issue first to agree on the approach.
- **Security issues:** don't open a public issue; see [SECURITY.md](SECURITY.md).

## Making a change

```bash
git clone https://github.com/jmcfadden27/claude-code-dev-pipeline.git
cd claude-code-dev-pipeline
tests/run.sh
```

`tests/run.sh` needs bash and jq. It also uses shellcheck, and python3 with `jsonschema` and `PyYAML`, when they are
installed; install them so every check runs.

- Keep the trust boundaries in [docs/security.md](docs/security.md) intact: agents get no git, GitHub or network
  tools, and only the publish job can push.
- Add or update tests for behaviour you change. When a renderer's output changes on purpose, run
  `tests/run.sh --update`, review the diff of `tests/expected/`, and copy it into `examples/` where the tests say so.
- Follow the style in `.editorconfig` and the surrounding scripts.
- Commit messages follow [Conventional Commits](README.md#commit-messages), like the commits the pipeline writes.
- Update the docs in `docs/` and `CHANGELOG.md` when behaviour or setup changes.

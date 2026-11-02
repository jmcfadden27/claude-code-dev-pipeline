# Setup

Adding the pipeline to a repository takes about 15 minutes. You need admin access to the repository, the
[GitHub CLI](https://cli.github.com) (`gh auth login`) and [Claude Code](https://code.claude.com) installed locally.

## 1. Copy the files

```bash
git clone https://github.com/<you>/claude-code-dev-pipeline
claude-code-dev-pipeline/scripts/install.sh /path/to/your-repo
```

The installer copies `templates/` into the repository and never overwrites an existing file (pass `--force` to
replace). It does not commit anything.

## 2. Configure the checks

Edit `pipeline/scripts/run-checks.sh` so it builds and tests your project and exits 0 only when everything passes:

```bash
npm ci && npm run lint && npm test
```

This script is the quality gate. The build agent may run only this command, and the build workflow runs it again
itself before it opens a pull request.

Then add the matching toolchain to the marked step in `.github/workflows/ai-build.yml`, for example:

```yaml
- uses: actions/setup-node@v4
  with: { node-version: 22, cache: npm }
```

## 3. Write CLAUDE.md

`CLAUDE.md` holds the project's rules: architecture, conventions and things never to do. Every agent reads it on
every run, so keep it short and specific. The installer creates it from `CLAUDE.md.example` when the repository has
none.

## 4. Connect Claude

1. Install the [Claude GitHub App](https://github.com/apps/claude) on the repository.
2. Create a credential and store it as a repository secret (**Settings → Secrets and variables → Actions**):

   | Plan | Create it with | Secret name |
   | --- | --- | --- |
   | Claude Pro / Max subscription | `claude setup-token` (prints a long-lived token, shown once) | `CLAUDE_CODE_OAUTH_TOKEN` |
   | Claude API (Console) | an API key from [platform.claude.com](https://platform.claude.com) | `ANTHROPIC_API_KEY` |

   The workflows use `claude_code_oauth_token`. For an API key, change that line in the three workflows to
   `anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}`.

   A subscription token belongs to the person who created it, and runs count against their plan. For a team, use an
   API key.

Alternatively, run `/install-github-app` in Claude Code, which installs the app and stores the secret for you.

## 5. Create the labels

```bash
claude-code-dev-pipeline/scripts/create-labels.sh <owner>/<repo>
```

| Label | Meaning |
| --- | --- |
| `ai:plan` | Ask for a plan (you add it) |
| `ai:needs-answers` | The plan has questions (the pipeline adds it) |
| `ai:plan-ready` | The plan has no open questions (the pipeline adds it) |
| `ai:approved` | Build the latest plan (you add it) |
| `ai:review` | Review this pull request (you add it) |

## 6. Recommended repository settings

- **Branch protection** on the default branch: require a pull request and at least one human approval. The pipeline
  never merges, and this makes sure nothing else does either.
- **Optional allow-list**: set the repository variable `PIPELINE_ALLOWED_USERS` (comma separated) to limit who may
  run the pipeline, on top of the write-access check.

## 7. First run

1. Commit and push the copied files to the default branch.
2. Open an issue with the **Change request (AI pipeline)** form.
3. Add the `ai:plan` label and watch the **Actions** tab. The plan appears as a comment on the issue.
4. Answer any questions in a comment, then comment `/plan`.
5. When the plan is ready, add `ai:approved`. A pull request appears when the build passes.
6. Add `ai:review` to the pull request for the AI review, then review and merge it yourself.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Nothing happens after adding a label | The workflow files are on the default branch; Actions are enabled; the label name matches exactly. |
| "does not have write access" | The person who added the label or comment needs write access (and must be in `PIPELINE_ALLOWED_USERS` if set). |
| "is not configured for this repository yet" | `pipeline/scripts/run-checks.sh` still has the template body. |
| Build reports `blocked` | Read the failure comment on the issue: the agent explains why it stopped. Clarify on the issue and re-plan. |
| The repository's own CI doesn't run on the pipeline's PR | Expected: pushes made with `GITHUB_TOKEN` don't start other workflows. The build stage runs the checks itself; push an empty commit or re-run CI manually if you need it. See [design decisions](design-decisions.md#known-limits). |
| Authentication errors | Test the token locally with `claude`; tokens from `claude setup-token` expire after a year. |

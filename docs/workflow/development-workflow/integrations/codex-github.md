# Integration: Codex GitHub Reviewer

`codex-github` is the default ready-phase GitHub reviewer for this template.
It is triggered by `scripts/development-workflow/codex-github-reviewer.sh`,
which posts the configured Codex trigger phrase to the pull request and waits
for Codex review evidence on the current head commit.

## Prerequisites

Before a repository keeps `codex-github` in `review.on_ready.github`, verify:

1. The Codex GitHub integration is installed and enabled for the target
   repository or organization.
2. The account or team running the workflow has access to Codex GitHub PR
   reviews.
3. The default trigger phrase works for the repository:

   ```bash
   @codex review
   ```

4. The bot login returned by GraphQL matches the default expected by the
   reviewer, or `CODEX_GITHUB_BOT_LOGIN` is set accordingly:

   ```bash
   CODEX_GITHUB_BOT_LOGIN=chatgpt-codex-connector[bot]
   ```

Do not store account tokens or secrets in `.ai-dev-workflow.yaml`. Use local
environment variables, CI secrets, or a local untracked config when an override
is needed.

## Workflow Configuration

The template default is:

```yaml
review:
  on_draft:
    github:
      - pr-agent
  on_ready:
    github:
      - codex-github
```

If Codex GitHub is not available in a downstream repository, remove
`codex-github` from that repository's shared `.ai-dev-workflow.yaml` or override
the ready-phase reviewer list locally in `.ai-dev-workflow.local.yaml` until the
integration is installed.

## Verification

Use a disposable or already-open PR and run:

```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> \
  --platform pr-agent,codex-github \
  --ready-phase codex-github \
  --post-final-summary \
  --max-wait 600
```

Expected successful evidence:

- `PLATFORM_1_RESULT=clean` for PR-Agent, or `skipped` only when intentionally
  unavailable.
- `PLATFORM_2_NAME=codex-github`.
- `PLATFORM_2_RESULT=clean`.
- `RESULT=clean`.

If the result is `needs_fixes`, address the reported review threads and rerun
the reviewer loop. If the result is `escalate` or `skipped` with an availability
reason, treat that as integration setup evidence rather than a clean review.

## Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| The loop waits until timeout after posting `@codex review` | Codex GitHub is not installed, not enabled for the repository, or the account cannot run reviews | Install/enable the integration, confirm account access, then rerun the loop |
| Codex review threads remain open after a fix commit | GitHub did not auto-resolve a fixed thread | Verify the current head addresses the finding, then resolve the thread or rerun review if unsure |
| Thread authors do not match the default bot login | Repository uses a different Codex bot identity | Set `CODEX_GITHUB_BOT_LOGIN` to the observed bot login |
| Old threads are still visible but marked outdated | GitHub marked the original diff location stale after the fix | Outdated threads are non-blocking in workflow readiness audits |

## Related Files

- [Workflow Configuration](../README.md#workflow-configuration)
- [Automated PR Review Platforms](pr-review-platform.md)
- `scripts/development-workflow/codex-github-reviewer.sh`
- `.ai-dev-workflow.yaml`

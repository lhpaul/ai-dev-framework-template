# Integration: Codex GitHub Reviewer

`codex-github` is the default ready-phase GitHub reviewer for this template.
It is triggered by `scripts/development-workflow/codex-github-reviewer.sh`,
which posts the configured Codex trigger phrase to the pull request and waits
for Codex review evidence on the current head commit.

The reviewer requires terminal evidence that can be tied to the current PR head:
a submitted GitHub review whose `commit_id` matches the current `headRefOid`, or
current-head inline review comments. Codex-authored root PR comments are terminal
only when they include a `Reviewed commit` marker matching the current head;
otherwise they are used for acknowledgement, usage-limit, and setup-failure
detection only. A thumbs-up reaction on the trigger comment is only an
acknowledgement and does not make the PR clean by itself.

When the SHA-pinned root comment and a submitted review are both terminal
evidence, the strictly newer one wins; on an exact timestamp tie, any
response that is not a clean approval — blocking or unrecognized format,
either of which the verdict classifier would not exit `APPROVED` for —
always wins over an approved one, regardless of which side supplied it, and
a later non-terminal (ancillary) root comment never discards an earlier
SHA-pinned blocking one. A failed fetch of Codex root PR comments — including
during the async grace-period poll — is treated as unavailable, not as
absence of evidence, so it cannot be silently overridden by a clean
submitted review.

## Prerequisites

Before a repository keeps `codex-github` in `review.on_ready.github`, verify:

1. The Codex GitHub integration is installed and enabled for the target
   repository or organization.
2. The account or team running the workflow has access to Codex GitHub PR
   reviews.
3. The default trigger phrase works for the repository:

   ```text
   @codex review
   ```

4. The bot login returned by GraphQL matches the default expected by the
   reviewer, or `CODEX_GITHUB_BOT_LOGIN` is set accordingly:

   <!-- workflow-shell-contract: bash-zsh -->

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

<!-- workflow-shell-contract: bash-zsh -->

```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> \
  --platform pr-agent,codex-github \
  --ready-phase codex-github \
  --post-final-summary \
  --max-wait 1800 \
  --poll-interval 60
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

Codex may also respond to `@codex review` with a setup message such as
`To use Codex here, create an environment for this repo`. That is an unavailable
review path, not a clean result. Create the Codex cloud environment or remove
`codex-github` from the configured reviewer list until the integration can
produce current-head review evidence. Within a single invocation's poll
window, a recorded environment-setup error cannot be silently overridden by
a later thumbs-up reaction or by review/comment evidence that is not
strictly newer than the recorded error — but a genuinely fresh, strictly
newer current-head review (e.g. after an operator creates the environment
mid-poll) is allowed to supersede it, following the same newest-wins rule
applied to every other evidence type.

## Troubleshooting

| Symptom | Likely cause | Action |
| --- | --- | --- |
| The loop waits until timeout after posting `@codex review` | Codex GitHub is not installed, not enabled for the repository, or the account cannot run reviews | Install/enable the integration, confirm account access, then rerun the loop |
| Codex leaves only a thumbs-up reaction on the trigger comment | Codex acknowledged the trigger but did not publish SHA-pinned review evidence | Treat the run as unavailable; do not mark the PR clean from the reaction alone |
| Codex says to create an environment for this repo | Manual trigger path is missing a Codex cloud environment | Create the environment or remove `codex-github` from the reviewer list until it is available |
| Codex review threads remain open after a fix commit | GitHub did not auto-resolve a fixed thread | Verify the current head addresses the finding, then resolve the thread or rerun review if unsure |
| Codex submitted a review for an older commit | Review arrived for a stale head SHA | Push or retrigger only if needed, then wait for a submitted review whose `commit_id` matches the current head |
| Thread authors do not match the default bot login | Repository uses a different Codex bot identity | Set `CODEX_GITHUB_BOT_LOGIN` to the observed bot login |
| Old threads are still visible but marked outdated | GitHub marked the original diff location stale after the fix | Outdated threads are non-blocking in workflow readiness audits |

## Related Files

- [Workflow Configuration](../README.md#workflow-configuration)
- [Automated PR Review Platforms](pr-review-platform.md)
- `scripts/development-workflow/codex-github-reviewer.sh`
- `.ai-dev-workflow.yaml`

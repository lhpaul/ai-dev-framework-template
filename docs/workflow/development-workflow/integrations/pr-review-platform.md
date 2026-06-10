# Integration: Automated PR Review Platforms (Generic)

This document defines **platform-agnostic** expectations for how agents use one or more automated PR review tools in this workflow.

Platform-specific setup lives in each platform's own integration doc. See:

- [`integrations/claude-code-action.md`](claude-code-action.md)
- [`integrations/coderabbit.md`](coderabbit.md)
- [`integrations/greptile.md`](greptile.md)
- [`integrations/devin.md`](devin.md)
- [`integrations/haystack-triage.md`](haystack-triage.md)

---

## Review Model

Automated PR reviewer tools are **post-push validation**. They do not replace the pre-PR review gate defined in [`REVIEW.md`](../../../../REVIEW.md).

Default policy is **sequential gating**:

- Configure reviewer tools in a fixed order
- Run the first configured reviewer tool
- Only continue to the next reviewer tool when the current one is `clean` or `skipped`
- If any reviewer tool returns blocking PR feedback, stop the loop, fix the branch, push, and start again from the first configured reviewer tool
- If any reviewer tool escalates, the overall loop escalates

Readiness requires every configured reviewer tool to be `clean` or `skipped`.

---

## What a Platform Must Provide

For `scripts/development-workflow/pr-review-loop.sh` to support a platform, the platform integration must define:

1. How the platform identifies itself on the PR
2. How to trigger a re-review after fixes are pushed
3. How to detect review completion
4. How to fetch new inline comments or blocking review summaries
5. How to distinguish platform findings from human comments

If a platform does not yet meet that contract in this repository, it should be documented as **planned but unsupported** and the helper script should report it as `skipped`.

---

## Aggregation Rules

The aggregate loop result is:

- `clean` when every configured reviewer tool is `clean` or `skipped`
- `needs_fixes` when the first unfinished reviewer tool reports blocking PR feedback
- `escalate` when the first unfinished reviewer tool times out or otherwise escalates
- `skipped` when no automated reviewer tool is configured at all

Additional rules:

- Suggestions are non-blocking regardless of platform
- `needs_fixes` summaries should include the blocking reviewer tool identity
- Unsupported configured platforms may be reported as `skipped` with a reason such as `unsupported-platform`
- CI starts only after the aggregate reviewer result is `clean` or `skipped`

---

## Platform Configuration

The active review platforms for a repository are declared in `.ai-dev-workflow.yaml` at the repo root:

```yaml
schema_version: 2

review:
  on_draft:
    github:
      - pr-agent
    # claude-code-action: own-key, own-CI reviewer with no per-hour vendor cap.
    # Requires ANTHROPIC_API_KEY secret and .github/workflows/claude-code-review.yml.
    # See integrations/claude-code-action.md for setup instructions.
    # - claude-code-action
  on_ready:
    github:
    # haystack: Haystack triage CLI reviewer. Requires `haystack` CLI installed
    # and authenticated via `haystack setup`. No GitHub App required.
    # See integrations/haystack-triage.md for setup instructions.
      - haystack
```

The helper script reads this file automatically when no `--platform` flag is
passed. If the file is absent, or if both `review.on_draft.github` and
`review.on_ready.github` are omitted or empty, no reviewer tool runs and the
result is skipped. Explicit `--platform` flags always override the config file.

`review.on_ready.github` is optional. Platforms listed there run only after
draft GitHub reviewers are clean and the PR has been converted with
`gh pr ready`. `pr-review-loop.sh` emits `READY_PHASE_*` telemetry showing
whether those platforms found net-new blockers after earlier platforms were
already clean. This is intended for measuring whether a ready-phase reviewer
still adds value.

Legacy `review.platforms` and `review.phase_after_clean` config remains accepted
for one transition release and maps into the lifecycle buckets above.

---

## Script Interface

The repository helper supports ordered multi-platform review:

```bash
# Uses platforms from .ai-dev-workflow.yaml (recommended)
./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name>

# Explicit override via flags
./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name> --platform greptile --platform devin
```

It also accepts comma-separated platform lists:

```bash
./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name> --platform greptile,devin
```

The script emits:

- One aggregate `RESULT=...`
- Ordered `PLATFORM_<n>_NAME` / `PLATFORM_<n>_RESULT` records
- Platform-specific counts and blocking summaries for the platform that stopped the loop

---

## Without Automated Reviewer Tools

If no automated reviewer tool is configured, skip the PR review loop and report `Automated review: ⏭️ skipped (not configured)`.

The pre-PR review gate from [`REVIEW.md`](../../../../REVIEW.md) still applies.

# Smoke test: Resolved Codex findings no longer block reviewer loop (#1757)

**Related spec**: `docs/specs/developments/20260915075927_1757-resolved-codex-findings/1_1757-resolved-codex-findings_specs.md`
**Related plan**: `docs/specs/developments/20260915075927_1757-resolved-codex-findings/2_1757-resolved-codex-findings_implementation-plan.md`

Run after the implementation PR merges to `develop`.

## Prerequisites

- A pull request with Codex GitHub review enabled and at least one **resolved**
  inline Codex review thread still visible on the current head.
- `gh` authenticated with permission to read PR reviews and GraphQL threads.

## Automated regression (required)

From the repository root:

```bash
bash scripts/development-workflow/tests/test-pr-review-loop.sh
```

Confirm the run completes with no failures and that cases named
`codex_resolved_visible_finding_waits_after_revision_push` pass.

## Manual PR exercise (recommended)

1. Open or select a PR where Codex left findings and you resolved every inline
   thread on the current head without pushing a new commit.
2. Run the reviewer loop for that PR (or resume `/run-reviewer-loop` for the
   implementation branch).
3. Confirm the Codex platform line shows `RESULT=waiting_on_reviewer` with
   `REASON=codex-github-review-pending` (or proceeds to clean after a fresh
   terminal Codex review), **not** `RESULT=needs_fixes` with
   `REASON=existing_findings` solely from resolved threads.
4. Resolve one thread but leave another applicable unresolved thread on the same
   head; rerun and confirm `RESULT=needs_fixes` still routes to the fix path.

## Escalation spot check (optional)

On a test PR, if Codex posts a root comment with an empty `Reviewed commit:`
field on the live head, confirm the loop escalates with
`codex_current_verdict_malformed_revision_marker` rather than waiting or fixing.

## Pass criteria

- Automated harness green.
- Manual PR shows resolved visible findings do not alone produce `needs_fixes`.
- No regression in existing Codex availability handling (usage-limit still
  terminates as unavailable, not unrecognized).

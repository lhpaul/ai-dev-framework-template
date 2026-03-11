# Protocol: Review Implementation Plan (Compatibility Wrapper)

**Purpose**: Run the implementation-plan review gate using the repository's canonical review contract in [`REVIEW.md`](../../../../REVIEW.md).

Use this protocol when:
- A workflow stage says to run the plan review gate
- A legacy command or agent still points to this file
- You want a repo-specific wrapper around a tool's native review feature

---

## Source of Truth

Read and follow:
- [`REVIEW.md`](../../../../REVIEW.md) → `Plan Review Checklist`
- The corresponding spec
- The target implementation plan
- Relevant code, architecture docs, and smoke-test runbook when present

`REVIEW.md` is authoritative. If this wrapper and `REVIEW.md` ever differ, follow `REVIEW.md`.

---

## Runner Guidance

- Claude Code: prefer the native review flow against `REVIEW.md`.
- Codex: prefer the native review flow against `REVIEW.md`.
- Cursor: use `/review-implementation-plan`, which should manually review the plan against `REVIEW.md`.
- Other tools: perform a manual review against `REVIEW.md`.

If invoked in a fix loop for a pushed branch or open PR:
- Apply all deterministic `blocking` and `important` fixes directly
- Commit and push if repo-tracked files changed
- Return approval only when no fixable `blocking` issues remain
- Escalate only when a real product or architecture decision is required

---

## Output

Produce a concise review report with:
- Overall assessment
- Direct fixes applied
- Remaining issues requiring human input
- Verdict: `APPROVED` or `NEEDS REVISION`

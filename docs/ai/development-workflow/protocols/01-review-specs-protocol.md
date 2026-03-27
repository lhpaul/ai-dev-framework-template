# Protocol: Review Feature Spec (Compatibility Wrapper)

**Purpose**: Run the spec review gate using the repository's canonical review contract in [`REVIEW.md`](../../../../REVIEW.md).

Use this protocol when:
- A workflow stage says to run the spec review gate
- A legacy command or agent still points to this file
- You want a repo-specific wrapper around a tool's native review feature

---

## Source of Truth

Read and follow:
- [`REVIEW.md`](../../../../REVIEW.md) → `Spec Review Checklist`
- `docs/project/1-business-domain.md`
- `docs/project/3-software-architecture.md`
- The target spec

`REVIEW.md` is authoritative. If this wrapper and `REVIEW.md` ever differ, follow `REVIEW.md`.

---

## Runner Guidance

- Claude Code: prefer the native review flow against `REVIEW.md`.
- Codex: prefer the native review flow against `REVIEW.md`.
- Cursor: use `/review-spec`, which should manually review the spec against `REVIEW.md`.
- Other tools: perform a manual review against `REVIEW.md`.

If invoked in a fix loop for a pushed branch or open PR:
- Apply all deterministic `blocking` and `important` fixes directly
- Commit and push if repo-tracked files changed
- Return approval only when no fixable `blocking` findings remain
- Escalate only when a real product decision is required

---

## Output

Produce a concise review report with:
- Overall assessment
- Direct fixes applied
- Remaining findings requiring human input
- Verdict: `APPROVED` or `NEEDS REVISION`

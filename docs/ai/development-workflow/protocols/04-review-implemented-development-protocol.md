# Protocol: Review Implemented Development (Compatibility Wrapper)

**Purpose**: Run the implementation review gate using the repository's canonical review contract in [`REVIEW.md`](../../../../REVIEW.md).

Use this protocol when:
- A workflow stage says to run the implementation review gate before opening a PR
- A legacy command or agent still points to this file
- You want a repo-specific wrapper around a tool's native review feature

---

## Source of Truth

Read and follow:
- [`REVIEW.md`](../../../../REVIEW.md) → `Code Review Checklist`
- The corresponding spec
- The implementation plan
- Relevant best-practice docs
- The changed code

`REVIEW.md` is authoritative. If this wrapper and `REVIEW.md` ever differ, follow `REVIEW.md`.

---

## Runner Guidance

- Claude Code: prefer the native review flow against `REVIEW.md`.
- Codex: prefer the native review flow against `REVIEW.md`.
- Cursor: use `/review-code`, which should manually review the branch against `REVIEW.md`.
- Other tools: perform a manual review against `REVIEW.md`.

If a runner also has a stronger built-in PR/code-review feature, use it first and then normalize the findings through `REVIEW.md`.

If invoked in a fix loop for a pushed branch or open PR:
- Apply all deterministic `blocking` and `important` fixes directly
- Commit and push if repo-tracked files changed
- Return approval only when no fixable `blocking` issues remain
- Escalate only when a real product, design, or architecture decision is required

---

## Output

Produce a concise review report with:
- Overall assessment
- Direct fixes applied
- Remaining issues requiring human input
- Verdict: `APPROVED` or `NEEDS REVISION`

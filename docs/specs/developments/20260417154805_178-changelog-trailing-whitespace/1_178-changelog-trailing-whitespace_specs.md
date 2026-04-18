# Developer Agent CHANGELOG Trailing-Whitespace Prevention — Spec

**Depends on**: 173-markdown-lint-plan-spec-docs (merged — provides the CI enforcement gate)

---

## Overview

AI developer agents writing `CHANGELOG.md` entries consistently produce trailing blank lines or trailing whitespace at the end of list items. The CI markdown lint check introduced in issue #173 catches these violations after the fact, but each catch costs a Devin review cycle and a fix push (observed near-100% recurrence rate across recent batches). This feature adds an upstream guardrail — an explicit CHANGELOG format verification step in the developer agent's pre-commit workflow — so the agent actively normalizes CHANGELOG entries before committing, eliminating the CI failure entirely rather than merely catching it after it occurs.

---

## Use Cases

### Use Case 1: Developer Agent Writes a CHANGELOG Entry

**Actor**: Developer agent (AI agent executing `03-implement-development-protocol.md`)
**Preconditions**: The developer agent has completed implementation work and is about to commit and push a feature or fix branch that modifies `CHANGELOG.md`.

**Steps**:
1. Developer agent writes a new `CHANGELOG.md` entry under `[Unreleased]` following the existing format.
2. Before staging the file for commit, the agent runs the CHANGELOG verification step defined in the protocol.
3. The verification step checks the written entry for trailing whitespace and trailing blank lines.
4. If violations are found, the agent fixes them immediately (removes trailing whitespace and extra blank lines) before staging.
5. If no violations are found, the agent proceeds to stage and commit normally.

**Postconditions**:
- The committed `CHANGELOG.md` entry contains no trailing whitespace or trailing blank lines.
- The CI markdown lint check passes on the first push without requiring a fix commit.

**Information shown**:
- If violations were auto-fixed: the agent's internal reasoning notes the fix was applied; no separate commit is required (fix happens before staging).
- If no violations: the agent proceeds silently.

**Actions available**:
- Agent corrects trailing whitespace or blank lines in the CHANGELOG entry before staging.

**Considerations**:
- The verification step must not strip intentional two-space hard line breaks (Markdown line-break syntax).
- The step must check the specific lines added or modified in the CHANGELOG, not the entire file, to avoid touching pre-existing content that may already be covered by inline suppressions.
- If the agent is running inside a worktree and the CHANGELOG was not modified in this work item, skip the verification step.

---

### Use Case 2: Human or Agent Updates the CHANGELOG Update Step

**Actor**: Human developer or AI agent reviewing the implementation protocol
**Preconditions**: The implementation protocol (`03-implement-development-protocol.md`) currently lacks an explicit CHANGELOG format check in the CHANGELOG update step (Step 6 in Full Pipeline, and the equivalent step in Refactor, Fast Track, and Hotfix paths).

**Steps**:
1. The protocol is updated to include an explicit CHANGELOG format verification instruction immediately after the CHANGELOG entry is written, in every implementation path.
2. When a developer agent reads the updated protocol before implementation, it understands it must verify the CHANGELOG entry before staging (i.e., after writing the entry in Step 6, before committing in Step 7).

**Postconditions**:
- The CHANGELOG update step in every implementation path (Full Pipeline, Refactor, Fast Track, Hotfix) includes a clear, actionable instruction for verifying CHANGELOG trailing whitespace.
- Any agent reading and following the protocol will apply the check without needing to infer it.

**Information shown**:
- The instruction in the protocol specifies what to check (trailing whitespace, trailing blank lines at end of entry) and how to verify (visual inspection of the diff or a simple shell check).

**Actions available**:
- Agent follows the step as written; no human intervention required during normal operation.

**Considerations**:
- The instruction must be concrete enough that an LLM agent can follow it deterministically — e.g., "after writing the CHANGELOG entry, verify no line ends with whitespace characters and the entry does not end with two or more consecutive blank lines."
- The instruction should be integrated into the existing CHANGELOG update step rather than a separate standalone section, to preserve protocol readability.
- The check is positioned after writing the CHANGELOG entry and before the commit/push step in every path, matching the logical flow: write entry → verify format → stage and commit.

---

## Business Rules

- The CHANGELOG format verification step is added to the CHANGELOG update step in `03-implement-development-protocol.md` (Step 6 in the Full Pipeline path, and the equivalent CHANGELOG update step in the Refactor, Fast Track, and Hotfix paths). It applies to every implementation path that modifies `CHANGELOG.md`. The check runs after the CHANGELOG entry is written and before the file is staged for commit.
- The verification covers exactly two defect patterns:
  1. Trailing whitespace (one or more whitespace characters at the end of a line, excluding intentional two-space Markdown hard line breaks).
  2. Trailing blank lines after a CHANGELOG entry (two or more consecutive blank lines at the end of the modified entry, and before end-of-file if applicable).
- The check is applied before staging, not as a separate commit. The agent fixes in-place if violations are found; no additional "fix commit" is created.
- The rule does not replace the CI lint check from issue #173 — both mechanisms coexist. The agent-level check prevents failures upstream; the CI check (MD009 trailing-space and MD047 EOF-newline rules) is the durable enforcement gate for trailing-whitespace violations. Consecutive-blank-line defects within CHANGELOG entries are not caught by the current CI config (MD012 is not enabled), so the agent-level pre-commit step is the primary guard for that defect class.
- The developer agent definition (`.claude/agents/developer.md`) is updated to surface the CHANGELOG format rule at agent initialization, alongside the existing CHANGELOG update reminder.

---

## Acceptance Criteria

- [ ] AC1: `03-implement-development-protocol.md` includes an explicit, actionable CHANGELOG format verification instruction in every implementation path (Full Pipeline Step 6, and the equivalent CHANGELOG update step in the Refactor, Fast Track, and Hotfix paths), directing the agent to verify the written CHANGELOG entry for trailing whitespace and trailing blank lines before staging.
- [ ] AC2: `.claude/agents/developer.md` key rules section includes a note that the CHANGELOG entry must have no trailing whitespace or trailing blank lines before commit.
- [ ] AC3: The instruction in the protocol is concrete and unambiguous — it specifies both defect patterns (trailing whitespace, trailing blank lines at end of entry) and the timing (after writing the CHANGELOG entry, before staging for commit).
- [ ] AC4: The instruction explicitly states that intentional two-space Markdown hard line breaks must not be treated as trailing whitespace violations.
- [ ] AC5: The changes do not remove or conflict with any existing CHANGELOG update instructions in the protocol or agent definition.

---

## Out of Scope (MVP)

- Pre-commit hook scripts (shell/Python) that automatically strip trailing whitespace — this is a separate enforcement layer already deferred to a follow-on by the #173 spec.
- Extending the verification to non-CHANGELOG markdown files touched by the implementation (e.g., spec or plan documents) — those are already covered by the CI check from #173.
- Auto-fixing violations without the agent being aware of the fix (invisible normalization) — the agent must explicitly verify and apply fixes so the behavior is auditable in the agent's reasoning trace.
- Changes to `pr-review-loop.sh`, `post-merge-cleanup.sh`, Protocol 90 batching logic, or Protocol 91 orchestration logic — out of scope per the issue brief.

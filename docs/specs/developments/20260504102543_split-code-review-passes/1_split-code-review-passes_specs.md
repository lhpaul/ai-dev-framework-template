# Split Code Review into Spec-Compliance and Code-Quality Passes — Spec

**Depends on**: <!-- no dependencies -->

---

## Overview

The current internal code review gate (Step 7a of Protocol 91) performs a single combined pass that evaluates both spec compliance and code quality simultaneously. This spec introduces a two-stage review pattern that separates "does the implementation match the spec?" from "is the code well-built?" into two sequential, focused passes. The separation reduces cognitive load for reviewers, makes findings easier to categorize and act on, and mirrors a pattern used in high-quality open-source review workflows.

**Language**: Outcomes are described in workflow and agent-process terms. Technical identifiers are deferred to the implementation plan.

---

## Use Cases

### Use Case 1: Running Step 7a on an Implementation PR

**Actor**: Work Item Runner (automated orchestrator) executing the internal review gate for an implementation PR (`feature/*`, `fix/*`, `refactor/*`, or `hotfix/*` branch)
**Preconditions**:
- A draft implementation PR is open
- The spec document for the item is available on the target branch (for Full Pipeline items) or the work item brief is accessible (for Refactor items)
- At least one internal reviewer is configured and reachable

**Steps**:
1. The Work Item Runner opens the draft PR and initiates Step 7a.
2. The runner dispatches **Pass 1 (Spec-Compliance Pass)**: the reviewer evaluates whether the implementation matches the spec (or work item brief for Refactor items) — checking that all acceptance criteria are addressed, no out-of-scope behavior is introduced, and there are no missing or extra behaviors.
3. If Pass 1 returns findings, the runner applies fixes, pushes, and re-runs Pass 1 until it approves.
4. Once Pass 1 approves, the runner dispatches **Pass 2 (Code-Quality Pass)**: the reviewer evaluates structural quality — readability, maintainability, project conventions, security boundaries, and test coverage.
5. If Pass 2 returns findings, the runner applies fixes, pushes, and re-runs Pass 2 (and Pass 1 if any fix is non-trivial) until it approves.
6. When both passes have approved for the same commit, the runner posts the Step 7a summary comment and converts the PR from draft to non-draft.

**Postconditions**:
- Both passes have approved the PR at the same commit SHA
- The Step 7a summary comment distinguishes findings from Pass 1 and Pass 2
- The PR is non-draft and ready for Step 7 (external automated reviewers)

**Information shown** (in the Step 7a summary comment):
- Which passes ran (Pass 1: Spec Compliance, Pass 2: Code Quality)
- Findings from each pass, labeled by pass
- Final verdict (APPROVED, escalated, or hard-fail)

**Actions available**:
- Reviewer may approve each pass independently
- Reviewer may return findings requiring fixes before proceeding

**Considerations**:
- If Pass 1 finds a spec-compliance issue during a Pass 2 fix cycle (because the fix introduced a regression), Pass 1 must re-approve before Pass 2 continues
- If the implementation is a Refactor item (no spec), Pass 1 evaluates against the work item brief instead
- The trivial-fix skip rule applies to Pass 2 re-runs after Step 7 fixer pushes (same conditions as the existing trivial-fix rule in Protocol 91)

---

### Use Case 2: Running Step 7a on a Spec or Plan PR

**Actor**: Work Item Runner executing the internal review gate for a `spec/*` or `implementation-plan/*` PR
**Preconditions**:
- A draft spec or plan PR is open

**Steps**:
1. The Work Item Runner initiates Step 7a as currently defined — single-pass review.
2. The single-pass reviewer evaluates the spec or plan against the review checklist in `REVIEW.md`.
3. The runner follows the existing gate outcome logic.

**Postconditions**:
- The gate runs as a single pass (no split), unchanged from current behavior

**Considerations**:
- The two-pass split applies only to implementation PRs; spec and plan PRs remain single-pass

---

### Use Case 3: Reviewing the Step 7a Summary Comment

**Actor**: Human reviewer reading the PR on GitHub
**Preconditions**: Step 7a has completed for an implementation PR

**Steps**:
1. The human opens the PR and reads the Step 7a summary comment.
2. The comment clearly labels findings by pass (Pass 1: Spec Compliance vs. Pass 2: Code Quality).
3. The human can immediately see whether the failures were about spec alignment or code structure.

**Postconditions**:
- Human reviewer has a clear categorized view of what was found and fixed during Step 7a

**Information shown**:
- Pass 1 findings and their resolution status
- Pass 2 findings and their resolution status
- Per-reviewer results for each pass (when multiple internal reviewers are configured)

---

## Business Rules

- The two-pass split applies exclusively to implementation PRs (`feature/*`, `fix/*`, `refactor/*`, `hotfix/*`). Spec and plan PRs (`spec/*`, `implementation-plan/*`) are unaffected and continue with single-pass review.
- Pass 1 must approve before Pass 2 is dispatched. Pass 2 is never run in parallel with Pass 1 or before Pass 1 approves.
- Both passes must approve at the same commit SHA before the PR is converted from draft to non-draft.
- If a fix applied during Pass 2 is non-trivial (does not meet the trivial-fix conditions in Protocol 91), Pass 1 must re-approve the new commit before Pass 2 can proceed.
- If a fix applied during Pass 2 is trivial (meets all three trivial-fix conditions), Pass 1 re-run is skipped and Pass 2 re-runs directly.
- The existing `max_internal_review_cycles` limit governs the combined number of full review restarts (both passes together), not each pass independently. Restarting means re-running from Pass 1.
- The Step 7a summary comment must distinguish findings from Pass 1 and Pass 2, showing each pass's verdict separately.
- The two-pass rule is independent of which internal reviewers are configured (e.g., `claude`, `codex`, `codex-github`). Each configured reviewer runs both passes in sequence.
- When multiple internal reviewers are configured, each reviewer runs Pass 1 and Pass 2 independently. All Pass 1 results from all reviewers must approve before any reviewer's Pass 2 is dispatched.

---

## Acceptance Criteria

- [ ] For an implementation PR with a configured internal reviewer, Step 7a runs Pass 1 (Spec Compliance) before Pass 2 (Code Quality). Pass 2 is not dispatched until Pass 1 approves.
- [ ] For an implementation PR, both Pass 1 and Pass 2 must approve (at the same commit SHA) before the PR is converted from draft to non-draft via `gh pr ready`.
- [ ] The Step 7a summary comment for an implementation PR labels findings separately for Pass 1 and Pass 2, and shows the verdict for each pass.
- [ ] For a spec PR (`spec/*`) or plan PR (`implementation-plan/*`), Step 7a runs a single pass without any change to existing behavior.
- [ ] If Pass 2 introduces a non-trivial fix, Pass 1 re-runs on the new commit before Pass 2 continues.
- [ ] If Pass 2 introduces a trivial fix (meets the trivial-fix conditions in Protocol 91), Pass 1 re-run is skipped and a note is posted to the PR indicating the skip.
- [ ] The `max_internal_review_cycles` limit is applied to full restart cycles (from Pass 1), not to individual pass runs.
- [ ] The feature works correctly for Refactor items (no spec): Pass 1 evaluates against the work item brief.

---

## Out of Scope (MVP)

- Running Pass 1 and Pass 2 in parallel (they must remain sequential: Pass 1 → Pass 2)
- Introducing separate cycle counters or per-pass escalation thresholds (the single `max_internal_review_cycles` counter governs both passes)
- Adding new reviewer types or changing which reviewer tools are supported
- Applying the two-pass split to spec or plan PRs
- UI or dashboard changes for tracking pass-level findings across PRs
- Configuring which passes run on a per-repo or per-PR basis (the split is always enabled for implementation PRs)

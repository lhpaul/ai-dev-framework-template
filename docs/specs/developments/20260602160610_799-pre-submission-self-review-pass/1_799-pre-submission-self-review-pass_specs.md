# Pre-Submission Self-Review Pass Before Opening PR — Spec

---

## Overview

This feature adds an explicit pre-submission self-review step to Protocol 03 (implementation) that runs **before** the agent opens the PR. The agent diffs the working branch against the base branch, then systematically checks each changed file for: stale debug comments or review markers left in the code, sibling and caller functions that must stay consistent with the changed logic, and full coverage of every spec acceptance criterion. The step fires on every implementation path (Full Pipeline, Refactor, Fast Track Fix) and runs before the `gh pr create` call.

Closed issue #614 ("agents miss test harness edge cases during impl self-review") already shipped test-harness-specific self-review guidance (the Test Harness Coverage Checklist) targeting bash trap patterns and BASH_SOURCE guard placement. This spec builds on that foundation rather than replacing it: #614 addressed the test-harness dimension; issue #799 addresses the **broader pre-PR diff review** — stale review markers, sibling/caller consistency across any changed code, and full AC coverage — that applies to every implementation PR regardless of whether a test harness is involved.

---

## Use Cases

### Use Case 1: Agent completes implementation and is about to open a draft PR

**Actor**: Developer agent (or human developer) following Protocol 03, any path (Full Pipeline, Refactor, or Fast Track Fix).

**Preconditions**:

- All implementation work is committed or staged.
- The agent has not yet opened the PR (is between the "commit and push" step and the `gh pr create` call).

**Steps**:

1. Agent runs `git diff <base-branch>...HEAD` (where `<base-branch>` is the item's base branch, e.g., `develop`) to obtain the full diff of the working branch.
2. For each file that appears in the diff, the agent performs three targeted checks:
   a. **Stale markers check**: scan the diff for debug statements, TODO/FIXME comments added during implementation, temporary workarounds, or review-marker comments (`# TODO: remove`, `// REVIEW:`, `# DEBUG:`, etc.) that were not present before the change and have not been cleaned up.
   b. **Sibling/caller consistency check**: identify functions, variables, or data structures that the changed code calls or depends on. Verify that those sibling and caller sites are internally consistent with the changed behavior (e.g., if a function's return shape changed, all call sites in the diff handle the new shape).
   c. **AC coverage check** (Full Pipeline and Refactor paths only): re-read the spec's acceptance criteria list. For each AC item, confirm that at least one change in the diff directly addresses it. Flag any AC with no corresponding change. <!-- markdown-heuristic-disable COUNT001 -->
3. If all three checks are clean, the agent proceeds to open the PR. <!-- markdown-heuristic-disable COUNT001 -->
4. If any check finds an issue, the agent resolves it (fix the code, update a call site, or add missing coverage for an AC) and repeats the check for the affected file before opening the PR.

**Postconditions**:

- No debug comments or stale review markers remain in the changed files.
- All functions that call or depend on changed code are consistent with the change.
- Every spec AC is addressed by at least one change in the diff (Full Pipeline and Refactor paths).
- The PR is opened only after all three checks pass.

**Information shown**:

- A brief self-review log appended to the PR description summarizing the outcome of each check (pass or specific finding resolved).

**Actions available**:

- Proceed to open the PR after all checks pass.
- If an AC is identified as uncovered: add the missing implementation before opening the PR.
- If a stale marker is found: remove or address it before opening the PR.
- If a caller inconsistency is found: fix the caller or document the intentional behavior difference before opening the PR.

**Considerations**:

- The diff command must use the three-dot form (`git diff <base>...HEAD`) to compare the branch tip against the merge-base, not `git diff <base> HEAD` (two-dot form), which includes unrelated changes on the base branch.
- The base branch is `develop` by default; items carrying an `integration-branch:<slug>` label use `develop-<slug>` instead.
- The sibling/caller consistency check is scoped to files within the diff — it does not require a full-repository audit of every caller across the codebase.
- The AC coverage check applies only to paths that have a spec (Full Pipeline, Refactor). Fast Track Fix items use the issue body's stated problem and proposed fix as the coverage reference instead of a spec file.
- This step is a pre-PR gate, not a replacement for the internal review gate (Step 7a) or the external automated reviewer loop (Step 7). Passing this check does not exempt the PR from those gates.

---

### Use Case 2: Code reviewer or automated reviewer evaluates a PR that should have had a pre-submission pass

**Actor**: Code reviewer (human or code-reviewer agent) or automated reviewer (CodeRabbit, Codex GitHub App) evaluating an implementation PR.

**Preconditions**:

- A PR is open on an implementation branch (`feature/*`, `fix/*`, `refactor/*`, `hotfix/*`).
- The PR description does or does not contain a self-review summary.

**Steps**:

1. Reviewer scans the PR diff for debug statements, TODO/FIXME comments added in this PR, or review-marker comments not present before the change.
2. Reviewer scans the diff for call sites of changed functions to verify consistency.
3. Reviewer cross-references the diff against the spec's acceptance criteria (when a spec exists).
4. If any gap is found that should have been caught by a pre-submission pass, reviewer raises a blocking finding citing the specific gap.

**Postconditions**:

- PRs with stale markers, inconsistent call sites, or uncovered ACs are flagged by the reviewer and require a fix round.
- PRs that passed the pre-submission check are expected to have a clean reviewer pass for this class of finding.

**Information shown**:

- Reviewer finding citing the specific stale marker, inconsistent call site, or uncovered AC.

**Actions available**:

- Request changes (blocking finding).

**Considerations**:

- The reviewer applies this check regardless of whether the PR description includes a self-review log. The log is informational; its absence does not block the finding.

---

## Business Rules

- BR-1: Every implementation path in Protocol 03 (Full Pipeline Path 1, Refactor Path 2, Fast Track Fix Path 3, Hotfix Path 4) MUST include the pre-submission self-review pass as an explicit step that runs before `gh pr create`.
- BR-2: The pre-submission self-review pass consists of three checks: (a) stale-markers check, (b) sibling/caller consistency check, and (c) AC coverage check. All three must be completed before the PR is opened. <!-- markdown-heuristic-disable COUNT001 -->
- BR-3: The AC coverage check (BR-2c) is required for Full Pipeline and Refactor paths, where a spec file with ACs exists. For Fast Track Fix and Hotfix paths, the equivalent coverage check uses the issue body's stated problem and proposed fix as the reference.
- BR-4: The diff command used in the pre-submission pass MUST be `git diff <base-branch>...HEAD` (three-dot form). The `<base-branch>` is the item's actual base branch (typically `develop`; `develop-<slug>` when the `integration-branch:<slug>` label is present; `main` for hotfixes).
- BR-5: The pre-submission pass builds on — and does not replace — the Test Harness Coverage Checklist introduced by #614. When an implementation includes a test script or validation harness, both the Test Harness Coverage Checklist and this pre-submission pass apply. The pre-submission pass covers the broader diff; the Test Harness Coverage Checklist covers bash-harness-specific edge cases.
- BR-6: If the pre-submission pass finds an issue, the agent resolves it and re-runs the check for the affected portion of the diff before proceeding. The agent must not open the PR with a known gap identified during this pass.
- BR-7: A brief self-review log must be appended to the PR description after the pass completes, confirming the outcome of each check. If all three checks are clean, a one-line summary is sufficient (e.g., "Pre-submission self-review: stale markers — none, caller consistency — verified, AC coverage — all N ACs addressed"). If a finding was identified and resolved, the log must note the finding and the commit that addressed it.

---

## Acceptance Criteria

- [ ] AC-1: Protocol 03 Path 1 (Full Pipeline) includes an explicit pre-submission self-review step between the "commit and push" step and the "open draft PR" step. The step's instructions include: run `git diff develop...HEAD`, check each changed file for stale markers, verify sibling/caller consistency, and confirm all spec ACs are covered.
- [ ] AC-2: Protocol 03 Path 2 (Refactor) includes the same pre-submission self-review step as AC-1, with AC coverage referencing the implementation plan's acceptance criteria rather than a separate spec file.
- [ ] AC-3: Protocol 03 Path 3 (Fast Track Fix) includes the pre-submission self-review step with the stale-markers and sibling/caller checks. The AC coverage check is replaced by a "stated-fix coverage check" that confirms the diff addresses the issue body's described problem and proposed fix.
- [ ] AC-4: Protocol 03 Path 4 (Hotfix) includes the pre-submission self-review step with the same three checks applied, using `main` as the base branch in the diff command. <!-- markdown-heuristic-disable COUNT001 -->
- [ ] AC-5: The pre-submission self-review step explicitly cites `git diff <base-branch>...HEAD` (three-dot form) as the diff command, not the two-dot `git diff <base-branch> HEAD` form, and notes that `<base-branch>` is `develop` by default (or `develop-<slug>` / `main` as applicable to the path).
- [ ] AC-6: The pre-submission self-review step includes a cross-reference to the existing Test Harness Coverage Checklist (from #614) explaining that both apply when a test harness is involved, and that the pre-submission pass does not replace the harness-specific checklist.
- [ ] AC-7: The PR description requirement (self-review log summarizing each check's outcome) is stated in the pre-submission step so agents include it when opening the PR.
- [ ] AC-8: `REVIEW.md` Pass 1 (Spec Compliance) and/or Pass 2 (Code Quality) includes a checking item for code reviewers to verify that debug comments, TODO/FIXME markers added in the PR, and call-site inconsistencies have been cleaned up before the PR was opened. This item is distinct from and additive to any existing checklist items.

---

## Out of Scope (MVP)

- Automated static analysis or CI tooling that detects stale markers or uncovered ACs without agent action — enforcement is via protocol text and review contract, not a lint-time check.
- Changes to the internal review gate (Step 7a) protocol text beyond the REVIEW.md update in AC-8 — Step 7a is not being restructured by this feature.
- Scanning callers outside the diff boundary (i.e., files not included in `git diff <base>...HEAD`) — the consistency check is scoped to changed files only.
- Retroactive enforcement on already-merged PRs that lacked a pre-submission pass.
- Changes to developer-agent guidance files (`.claude/agents/developer.md`, `.cursor/agents/developer.md`, `.codex/skills/`) beyond what is naturally derived from the Protocol 03 update — downstream agent files are updated only if they contain a dedicated self-review section that would become inconsistent.

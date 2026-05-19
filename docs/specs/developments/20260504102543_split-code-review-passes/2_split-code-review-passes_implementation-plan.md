# Split Code Review into Spec-Compliance and Code-Quality Passes — Implementation Plan

**Spec**: [`1_split-code-review-passes_specs.md`](./1_split-code-review-passes_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/split-code-review-passes.smoke-test.md`](../../../testing/workflow/split-code-review-passes.smoke-test.md)

---

## Summary

**Approach**: Extend the Step 7a internal review gate in `91-orchestrate-work-protocol.md` so that when the target PR is an implementation PR (`feature/*`, `fix/*`, `refactor/*`, `hotfix/*`), the gate dispatches two sequential passes — Pass 1 (Spec-Compliance) followed by Pass 2 (Code-Quality) — instead of a single undifferentiated review. Spec and plan PRs remain single-pass with no change. The `REVIEW.md` Code Review Checklist is split into two named sub-sections to provide reviewers with clear per-pass scope. All agent files and Codex skill files that describe Step 7a behavior receive lightweight wording updates to reference the two-pass behaviour.

**Estimated complexity**: M

**Rationale**: The change is concentrated in one section of Protocol 91 (Step 7a Multi-reviewer execution rules), with secondary updates to `REVIEW.md` and a handful of agent/skill definition files. No scripting infrastructure is added; the two-pass logic is expressed entirely in protocol prose and checked by the orchestrating agent at runtime. Testing is manual/smoke-based: verify the pass sequence and summary comment by running a test PR through the updated gate.

**Dependencies**: None

---

## Verification Log

| Check                                      | Command / query                                                                                                                          | Result                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| ------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Repo revision                              | `git rev-parse --short HEAD`                                                                                                             | `ff2a19c`                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Files referencing Step 7a in agents/skills | `grep -rl "Step 7a\|internal.*review.*gate\|code-reviewer\|implementation-plan-reviewer" .claude/agents/ .cursor/agents/ .codex/skills/` | `.claude/agents/automated-reviewer-loop.md`, `.claude/agents/code-reviewer.md`, `.claude/agents/implementation-plan-reviewer.md`, `.cursor/agents/automated-reviewer-loop.md`, `.cursor/agents/code-reviewer.md`, `.cursor/agents/implementation-plan-reviewer.md`, `.codex/skills/workflow-code-reviewer/SKILL.md`, `.codex/skills/workflow-item-orchestrator/SKILL.md`, `.codex/skills/workflow-orchestrator/SKILL.md`, `.codex/skills/workflow-reviewer-loop/SKILL.md` |
| Existing `Pass 1` / `Pass 2` mentions      | `grep -c "Pass 1\|Pass 2\|two.pass" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`                        | `0` — two-pass logic does not yet exist                                                                                                                                                                                                                                                                                                                                                                                                                                   |

---

## Layer-by-Layer Changes

### Protocol Documents

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`** — Step 7a: add branch-type detection for implementation vs. spec/plan PRs; replace the existing "Multi-reviewer execution rules" block with two-pass execution rules (Pass 1 → Pass 2 sequential dispatch, restart semantics, trivial-fix skip applicability, `max_internal_review_cycles` scope); update the Step 7a summary comment template to label findings by pass; update the loop-parameters table.
- [ ] **`REVIEW.md`** — split the `Code Review Checklist` into two named sub-checklists: `### Pass 1: Spec Compliance` and `### Pass 2: Code Quality`; move existing items to the appropriate pass; add a preamble noting that Pass 1 runs first and Pass 2 runs only after Pass 1 approves (for implementation PRs only).

### Agent Definition Files

- [ ] **`.claude/agents/code-reviewer.md`** — add a note that when invoked for a Pass 1 cycle the reviewer evaluates spec compliance only, and when invoked for a Pass 2 cycle evaluates code quality only; the orchestrating protocol (91) passes which pass is active.
- [ ] **`.cursor/agents/code-reviewer.md`** — same as above (Cursor mirror).
- [ ] **`.claude/agents/automated-reviewer-loop.md`** — update the Step 7a description bullet to mention the two-pass sequence for implementation PRs.
- [ ] **`.cursor/agents/automated-reviewer-loop.md`** — same as above (Cursor mirror).

### Codex Skill Files

- [ ] **`.codex/skills/workflow-code-reviewer/SKILL.md`** — add a note mirroring the `.claude/agents/code-reviewer.md` update: the pass identity is determined by the orchestrator at dispatch time.
- [ ] **`.codex/skills/workflow-item-orchestrator/SKILL.md`** — no wording change needed (already defers entirely to Protocol 91).
- [ ] **`.codex/skills/workflow-orchestrator/SKILL.md`** — no wording change needed.
- [ ] **`.codex/skills/workflow-reviewer-loop/SKILL.md`** — no wording change needed (this skill runs Step 7, not Step 7a).

---

## Testing Strategy

**Test types**: Smoke / Manual

**Key scenarios to test**:

1. **Pass sequence enforced (implementation PR)** — maps to AC 1: given an implementation PR with a configured internal reviewer, confirm that Pass 1 (Spec Compliance) runs first and Pass 2 (Code Quality) is not dispatched until Pass 1 approves.
2. **Non-draft conversion requires both passes (AC 2)** — confirm that `gh pr ready` is not called until both passes have approved; when both passes run without a trivial-fix skip, both must approve at the same commit SHA; when Pass 1 is skipped under the trivial-fix path, only Pass 2 must approve at the current SHA.
3. **Summary comment labels findings by pass (AC 3)** — verify the Step 7a summary comment contains distinct "Pass 1" and "Pass 2" sections with individual verdicts.
4. **Spec/plan PRs unaffected (AC 4)** — run a `spec/*` or `implementation-plan/*` PR through Step 7a and confirm a single-pass review runs with no change to existing behaviour.
5. **Non-trivial fix re-triggers Pass 1 (AC 5)** — after a non-trivial fix during the Pass 2 cycle, confirm Pass 1 re-runs before Pass 2 continues.
6. **Trivial fix skips Pass 1 re-run (AC 6)** — after a trivial fix (all three trivial-fix conditions met), confirm Pass 1 is skipped and a skip note is posted.
7. **`max_internal_review_cycles` counted as full restarts (AC 7)** — confirm the cycle counter increments on full Pass 1 → Pass 2 restart, not on individual pass runs.
8. **Refactor item (no spec) — Pass 1 uses work item brief (AC 8)** — confirm Pass 1 evaluates the work item brief for a Refactor item with no spec.

**Smoke test runbook**: `docs/testing/workflow/split-code-review-passes.smoke-test.md`

---

## Seed Data

| Entity                 | Values / Scenario                                       | File                            |
| ---------------------- | ------------------------------------------------------- | ------------------------------- |
| Test implementation PR | Any `fix/*` PR with a merged spec and plan on `develop` | n/a — created during smoke test |
| Test spec PR           | Any `spec/*` PR open as draft                           | n/a — created during smoke test |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — primary change (described in Layer-by-Layer Changes above)
- [ ] `REVIEW.md` — split Code Review Checklist into Pass 1 and Pass 2 sub-sections

No other project docs (`docs/project/`, `AGENTS.md`) require updates — this change is internal to the review gate workflow and introduces no new domain concepts.

---

## Risks & Mitigations

| Risk                                                             | Likelihood | Impact | Mitigation                                                                                                                                                                                            |
| ---------------------------------------------------------------- | ---------- | ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Pass identity context lost when orchestrator dispatches reviewer | Low        | High   | Protocol 91 must explicitly state that the orchestrator passes the active pass name (`Pass 1` or `Pass 2`) in the dispatch prompt; reviewer agents reference this to scope their checklist evaluation |
| Trivial-fix skip rule applied incorrectly in two-pass context    | Low        | Med    | Plan clearly states trivial-fix skip only suppresses Pass 1 re-run after Pass 2 fixer pushes; never applies to the initial full Step 7a run                                                           |
| `max_internal_review_cycles` semantics misunderstood             | Low        | Med    | Add an explicit clarifying sentence to the Step 7a loop-parameters table: the counter tracks full-restart cycles (Pass 1 → Pass 2), not individual pass runs                                          |
| Reviewer agent ignores pass-identity prompt                      | Low        | Med    | Document in the code-reviewer agent file that pass identity is a first-class instruction; reviewer must scope findings to the named pass                                                              |

---

## Code Samples

> **All samples below are illustrative — adapt during implementation.**

### Illustrative: Step 7a two-pass dispatch logic (Protocol 91 prose description)

```
# Illustrative — adapt during implementation
if IS_IMPLEMENTATION_PR:
    # Pass 1: Spec Compliance
    for reviewer in resolved_reviewers:
        outcome = dispatch(reviewer, pass="Pass 1: Spec Compliance")
        if outcome == NEEDS_REVISION:
            increment cycle and restart from Pass 1
    # Pass 2: Code Quality (only reached when all Pass 1 approvals received)
    for reviewer in resolved_reviewers:
        outcome = dispatch(reviewer, pass="Pass 2: Code Quality")
        if outcome == NEEDS_REVISION:
            if fix_is_trivial:
                skip Pass 1 re-run, restart from Pass 2
            else:
                increment cycle and restart from Pass 1
    post_step7a_summary_comment()
    gh pr ready <pr_number>
else:
    # Spec/plan PRs: single-pass unchanged
    run_single_pass_review()
    post_step7a_summary_comment()
    gh pr ready <pr_number>
```

### Illustrative: Step 7a summary comment format for implementation PR

```markdown
# Illustrative — adapt during implementation

### Step 7a Internal Review Gate Summary

**PR type**: Implementation (two-pass)
**Effective reviewer set**: claude
**Skipped reviewers**: codex-github (timed out — treated as unavailable)

**Pass 1 (Spec Compliance)**

- claude: APPROVED (0 findings)

**Pass 2 (Code Quality)**

- claude: APPROVED after 1 fix cycle (1 finding resolved)

**Verdict**: APPROVED
All passes approved at commit `abc1234`.
```

---

## Implementation Order

1. **Update Protocol 91 — Step 7a branch-type detection**

   In the "Step 7a: Internal Review Gate" section of `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`, add a preamble under "Multi-reviewer execution rules" that defines implementation PR detection:

   > An **implementation PR** is any PR whose branch matches `feature/*`, `fix/*`, `refactor/*`, or `hotfix/*`. A **non-implementation PR** matches `spec/*` or `implementation-plan/*`. Non-implementation PRs continue with the existing single-pass review; implementation PRs follow the two-pass procedure below.

   Verify: confirm the section now contains the branch-type classification preamble.

2. **Update Protocol 91 — two-pass execution rules**

   Replace the existing single-pass "Multi-reviewer execution rules" table and surrounding prose with a two-pass description. The new rules must express:
   - Pass 1 (Spec Compliance) dispatches all configured reviewers; each reviewer evaluates only spec-compliance criteria from `REVIEW.md §Pass 1`.
   - Pass 2 (Code Quality) dispatches all configured reviewers; each reviewer evaluates only code-quality criteria from `REVIEW.md §Pass 2`.
   - Pass 2 is never dispatched until all Pass 1 runs for the current commit are `APPROVED`.
   - When both passes complete without any trivial-fix skip, both must approve at the same commit SHA before `gh pr ready` is called. When Pass 1 is skipped under the trivial-fix path (see below), only Pass 2 must approve at the current commit SHA — Pass 1's earlier approval (at a prior SHA) remains valid for that cycle.
   - If a fix applied during Pass 2 is **non-trivial** (does not meet all three trivial-fix conditions): increment `internal_review_cycle` and restart from Pass 1.
   - If a fix applied during Pass 2 is **trivial** (all three trivial-fix conditions met): skip Pass 1 re-run, post the skip note, restart Pass 2 only. In this case the same-SHA requirement does not apply to Pass 1 — only Pass 2 must approve at the current commit SHA before `gh pr ready` is called.
   - The `max_internal_review_cycles` counter counts full restart cycles (Pass 1 restart), not individual pass runs.
   - When multiple internal reviewers are configured, all reviewers' Pass 1 results must approve before any reviewer's Pass 2 is dispatched.

   Verify: confirm the section contains explicit Pass 1 / Pass 2 dispatch rules and the restart semantics described above.

3. **Update Protocol 91 — Step 7a summary comment template**

   Update the "Step 7a summary comment" example in Protocol 91 to show the two-pass format for implementation PRs (see Code Samples above). Retain the existing single-pass format as the template for non-implementation PRs.

   Verify: confirm the updated template distinguishes Pass 1 and Pass 2 findings sections.

4. **Update Protocol 91 — loop-parameters table**

   Update the `max_internal_review_cycles` description in the Step 7a loop-parameters table to clarify: "Max times the full two-pass cycle (Pass 1 → Pass 2) is restarted before escalating (for implementation PRs); for non-implementation PRs, counts full single-pass restarts as before."

   Verify: confirm the table row is updated.

5. **Update `REVIEW.md` — split Code Review Checklist into Pass 1 and Pass 2**

   In `REVIEW.md`, under `## Code Review Checklist`:

   a. Add a preamble: "For implementation PRs, this checklist is divided into two sequential passes (Pass 1 then Pass 2). Spec and plan PRs use a single-pass review and are not affected by this split."

   b. Create `### Pass 1: Spec Compliance` sub-section containing:
   - Does the implementation match the approved spec and plan (or work item brief for Refactor items)? All acceptance criteria addressed, no out-of-scope behaviour, no missing or extra behaviours.
   - CHANGELOG and workflow-specific artifacts updated when required.

   c. Create `### Pass 2: Code Quality` sub-section containing all remaining existing checklist items: project and stack conventions, logic and edge cases, security boundaries, tests, new patterns, shell script checks, database migration checks, concurrent event source checks.

   d. Typical `blocking` / `important` / `suggestion` severity examples remain under their respective pass (move existing spec-compliance blocking examples to Pass 1 section; code quality blocking examples to Pass 2 section).

   Verify: confirm `REVIEW.md` Code Review Checklist has the two sub-sections and the preamble.

6. **Update `.claude/agents/code-reviewer.md`**

   After the existing "Follow the code review protocol…" instruction, add:

   > When dispatched for **Pass 1 (Spec Compliance)**: evaluate only the `### Pass 1: Spec Compliance` sub-checklist from `REVIEW.md`. Do not evaluate code quality items.
   > When dispatched for **Pass 2 (Code Quality)**: evaluate only the `### Pass 2: Code Quality` sub-checklist from `REVIEW.md`. Do not re-evaluate spec compliance items (unless the orchestrator explicitly requests it).
   > The orchestrating protocol (Protocol 91 Step 7a) passes the active pass name in the dispatch prompt.

   Verify: confirm the file contains pass-scoped evaluation instructions.

7. **Mirror update to `.cursor/agents/code-reviewer.md`**

   Apply the identical change from Step 6 to `.cursor/agents/code-reviewer.md`.

   Verify: both agent files contain matching pass-scoped evaluation instructions.

8. **Update `.claude/agents/automated-reviewer-loop.md`**

   Update the Step 7a description in the agent definition to note: "Step 7a runs **two sequential passes** for implementation PRs (Pass 1: Spec Compliance, then Pass 2: Code Quality) before converting to non-draft. Spec and plan PRs remain single-pass."

   Verify: confirm the description references the two-pass sequence.

9. **Mirror update to `.cursor/agents/automated-reviewer-loop.md`**

   Apply the identical change from Step 8 to `.cursor/agents/automated-reviewer-loop.md`.

   Verify: both files contain matching two-pass descriptions.

10. **Update `.codex/skills/workflow-code-reviewer/SKILL.md`**

    After the existing step that says "Follow that protocol exactly," add:

    > When dispatched for a specific pass (Pass 1: Spec Compliance or Pass 2: Code Quality), restrict evaluation to the corresponding `REVIEW.md` sub-checklist. The pass name is provided in the dispatch prompt by the orchestrating skill.

    Verify: confirm the skill file contains pass-scoped evaluation instruction.

11. **Write smoke test runbook**

    Create `docs/testing/workflow/split-code-review-passes.smoke-test.md` using the template. Cover all eight smoke test scenarios listed in the Testing Strategy section above.

    Verify: confirm the file exists and each acceptance criterion from the spec maps to at least one testable step.

12. **Pre-commit lint check**

    Run `markdownlint-cli2` on all modified docs files and the smoke test runbook. Fix any reported violations before committing.

    ```bash
    REPO_ROOT=$(git rev-parse --git-common-dir)/..
    "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
      "docs/specs/developments/20260504102543_split-code-review-passes/2_split-code-review-passes_implementation-plan.md" \
      "docs/testing/workflow/split-code-review-passes.smoke-test.md"
    ```

    Verify: markdownlint-cli2 exits clean (no violations).

13. **Update `CHANGELOG.md` under `[Unreleased]`**

    Add an entry:

    ```
    - **Split code review into spec-compliance and code-quality passes** (#449): Step 7a internal review gate now runs two sequential passes for implementation PRs — Pass 1 (Spec Compliance) before Pass 2 (Code Quality). Spec and plan PRs remain single-pass. REVIEW.md Code Review Checklist is split accordingly.
    ```

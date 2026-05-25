# Integration Branch Graduation Ceremony — Implementation Plan

**Spec**: [1_integration-branch-graduation-ceremony_specs.md](./1_integration-branch-graduation-ceremony_specs.md)
**Smoke test runbook**: [docs/testing/workflow/727-integration-branch-graduation-ceremony.smoke-test.md](../../../../testing/workflow/727-integration-branch-graduation-ceremony.smoke-test.md)

---

## Summary

**Approach**: Update `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md` to align with all spec requirements (CHANGELOG handling, epic issue lifecycle, optional sub-item disposition, human approval requirement, and post-cleanup scope); add a reference to Protocol 05b in Protocol 90's Step 1 portfolio scan so graduation eligibility is surfaced in normal batch runs; update Protocol 91's `ready-for-regression` table to explicitly exempt graduation PRs (`develop-<slug>` → `develop`); and update Protocol 90's Step 5.1 verification check to skip the `ready-for-regression` requirement for graduation PRs.

**Estimated complexity**: M

**Rationale**: The changes are entirely documentation and protocol updates — no code changes to shell scripts are required. Four protocol/agent documents need targeted edits. The scope is bounded: no new scripts, no database changes, no frontend. Medium complexity reflects the need to carefully update multiple cross-referencing protocol documents without introducing cross-section contradictions.

**Dependencies**: None — all referenced documents already exist.

---

## Verification Log

| Check | Command / query | Result |
| ----- | --------------- | ------ |
| Repo revision | `git rev-parse --short HEAD` | `d6d5f86` |
| Protocol 05b exists | `ls docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md` | exists (3.2K) |
| Protocol 90 references to `develop-<slug>` / graduation | `grep -c "develop-\|integration.branch\|graduation\|graduate" docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | 19 matches across file |
| Protocol 90 Step 1 graduation eligibility check | `grep -n "graduation\|05b\|graduate" docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | 0 matches — graduation eligibility not yet surfaced in Step 1 |
| Protocol 91 ready-for-regression table | `grep -n "ready-for-regression\|develop-" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | 17 lines; `develop-<slug>` PR type not listed in branch-prefix table |
| Protocol 05b CHANGELOG / epic lifecycle / optional sub-item handling | `grep -n "CHANGELOG\|optional\|epic\|human.approval\|BR-" docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md` | 0 matches — these spec requirements not yet codified in 05b |
| Step 5.1 `ready-for-regression` table branch prefixes | `grep -n "ready-for-regression\|graduation" docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md \| grep -i "branch prefix\|graduation\|develop-<slug>"` | `develop-<slug>` graduation PRs not listed as exempt |

---

## Layer-by-Layer Changes

### Documentation / Protocol Layer

- [ ] **Protocol 05b** (`docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`): Expand to incorporate all spec requirements:
  - Add Step 0: Human Approval Gate — require explicit human approval before opening any graduation PR (BR-1, AC-2)
  - Expand Step 2: Add check for divergence between `develop-<slug>` and `develop` before proceeding (Use Case 2 Step 2)
  - Add Step 2.5: CHANGELOG handling — verify that `[Unreleased]` CHANGELOG entries from `develop-<slug>` are present in the graduation PR diff; include the note from BR-5 about not pre-absorbing them separately from the graduation PR (AC-6)
  - Expand Step 3: PR body requirements — list each sub-item with issue number, title, and implementation PR number (AC-3, AC-4, AC-5)
  - Expand Step 4: Explicitly note that `ready-for-regression` is NOT required for graduation PRs (BR-6, AC-7)
  - Expand Step 5 (Post-Merge Cleanup): Add epic issue closure step (BR-8, AC-9), optional sub-item disposition step (Use Case 3, AC-10), and stale worktree cleanup guidance (Use Case 3 consideration)
  - Update Non-Goals to mention autonomous graduation explicitly per spec
  - Add a Business Rules section reference (or inline notes) for the key BRs that affect agent behavior: BR-1 through BR-9

- [ ] **Protocol 90** (`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`): Add graduation eligibility surfacing in Step 1 portfolio scan (AC-11, AC-12):
  - In Step 1b (Enrich with VCS state), after the integration branch enumeration, add a "Graduation eligibility check" sub-step: for each `develop-<slug>` found, query sub-items labeled `integration-branch:<slug>`, check whether all planned sub-items have merged implementation PRs targeting `develop-<slug>`, and surface eligible branches to the human with the required information (list of sub-items, included PRs, any deferred/optional sub-items)
  - In Step 1c portfolio map, add a row for "Integration branch graduation-eligible" as a distinct state

- [ ] **Protocol 90 Step 5.1** (`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`): Update the `ready-for-regression` check in the Step 5.1 verification table:
  - Explicitly note that graduation PRs (head branch matching `^develop-`) are exempt from the `ready-for-regression` requirement (BR-6, AC-7)
  - Update the check description: "Present in the `labels` array on `feature/*`, `fix/*`, `refactor/*`, `hotfix/*` PRs; not required for `spec/*`, `implementation-plan/*`, or graduation PRs (`develop-<slug>` → `develop`)"

- [ ] **Protocol 91 Step 7b / Step 8a** (`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`): Update the `ready-for-regression` branch-prefix table:
  - Add a row for graduation PRs: head branch `develop-<slug>` (base branch `develop`) → `ready-for-regression` NOT required (BR-6, AC-7)
  - Update the "any branch that does not match a recognized prefix" note to include graduation branches as a known/expected non-implementation PR type, not a configuration anomaly

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:

1. Protocol 05b step coverage — simulate a graduation run and verify each new step is reachable (maps to AC-1 through AC-10)
2. Protocol 90 Step 1 graduation eligibility surfacing — verify the new sub-step appears in the portfolio scan description (maps to AC-11, AC-12)
3. `ready-for-regression` exemption — verify graduation PRs are not flagged for the missing label (maps to AC-7)

**Smoke test runbook**: `docs/testing/workflow/727-integration-branch-graduation-ceremony.smoke-test.md`

---

## Seed Data

None — all changes are to protocol documents. No application seed data is required.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md` — updated as primary output (see Layer-by-Layer Changes)
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — updated for graduation eligibility surfacing and Step 5.1 exemption
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — updated for `ready-for-regression` branch-prefix table

No changes required to `docs/project/`, `AGENTS.md`, or stack-specific docs — this is a workflow protocol update only.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| Cross-section contradiction between Protocol 90 Step 1 graduation check and Protocol 05b agent role | Low | Medium | Cross-section consistency self-check required before commit; ensure Step 1 surfaces eligibility but does not initiate graduation autonomously |
| `ready-for-regression` exemption added to Protocol 91 table conflicts with the "any unrecognized prefix is an anomaly" catch-all | Low | Low | Update the catch-all note to explicitly list graduation branches as a known/expected non-implementation PR type |
| Protocol 05b expansion introduces ambiguity about when "human approval" is separate from "integration testing complete" | Low | Medium | Keep the prerequisite "human has approved graduation" as a gating precondition at the top of Step 0, aligned with spec BR-1 |

---

## Code Samples

No code samples — all changes are to Markdown protocol documents.

---

## Implementation Order

1. **Update Protocol 05b** (`docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`):
   - Add Step 0: Human Approval Gate before the current Step 1. State that the agent must not proceed unless the human has explicitly approved graduation after reviewing the list of included sub-items (per BR-1 and AC-2).
   - Expand Step 2 (Verify All Sub-Items Are Merged): after the existing sub-item check, add a divergence check — if `develop-<slug>` is behind `develop` in a way that would cause conflicts, surface this to the human before proceeding.
   - Add Step 2.5 (CHANGELOG): state that the graduation PR must carry all `[Unreleased]` CHANGELOG entries accumulated on `develop-<slug>`; include the BR-5 note that the absorb commit must be part of the graduation branch itself, not a separate prior merge.
   - Expand Step 3 (Open the Graduation PR): ensure the PR body requirements match AC-3 through AC-5 exactly — title format, sub-item list format, merge-commit statement.
   - Expand Step 4 (Run the Standard Review Loop): add an explicit note that `ready-for-regression` is NOT required for graduation PRs per BR-6.
   - Expand Step 5 (Post-Merge Cleanup): add sub-steps for epic issue closure (BR-8, AC-9), optional sub-item disposition (Use Case 4, AC-10), and stale worktree cleanup guidance.
   - Verify: read the updated file from top to bottom and confirm all AC-1 through AC-10 are reachable from the protocol steps.

2. **Update Protocol 90 Step 1b** (`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`):
   - Locate the integration branch enumeration passage in Step 1b (around line 193): "When gathering VCS state, also collect the set of open `develop-<slug>` integration branches..."
   - After that existing paragraph, add a "Graduation eligibility check" block:
     - For each `develop-<slug>` found, query sub-items labeled `integration-branch:<slug>`.
     - For each sub-item, check whether a merged implementation PR exists targeting `develop-<slug>`.
     - If all planned (non-optional, non-cancelled) sub-items have merged implementation PRs, mark the integration branch as graduation-eligible in the portfolio map.
     - Surface eligible branches to the human with: the integration branch name, a list of all sub-items (issue number, title, implementation PR number), and a note on any optional/deferred sub-items.
   - Verify: confirm the new block does NOT auto-graduate (human approval must still be explicit) and confirms to AC-12.

3. **Update Protocol 90 Step 1c** (`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`):
   - In the portfolio map bullet list, add: "Integration branches (`develop-<slug>`) that are graduation-eligible (all planned sub-items merged)"
   - Verify: confirm the new entry is distinct from regular in-flight items and clearly labeled as human-decision-required.

4. **Update Protocol 90 Step 5.1** (`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`):
   - Locate the `ready-for-regression` row in the Step 5.1 verification table (around line 954).
   - Update the "Pass condition" cell to add: "not required for `spec/*`, `implementation-plan/*`, or graduation PRs (head branch `develop-<slug>`, base branch `develop`)"
   - Verify: confirm the updated table row correctly exempts graduation PRs from triggering the direct-apply remediation.

5. **Update Protocol 91 Step 7b / Step 8a** (`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`):
   - Locate the `ready-for-regression` branch-prefix table (around line 1518).
   - Add a new row: `develop-<slug>` (graduation PR) → `ready-for-regression` NOT required — because graduation PRs carry no new implementation code.
   - Update the catch-all note below the table to state that graduation branches (`develop-<slug>` → `develop`) are a known/expected non-implementation PR type and should NOT be treated as a configuration anomaly.
   - Verify: confirm the table is internally consistent — the new row does not conflict with the `feature/*`/`fix/*`/`refactor/*`/`hotfix/*` "Yes" rows.

6. **Cross-section consistency self-check** (mandatory before commit):
   - Confirm "graduation-eligible" is defined consistently across Protocol 90 Step 1b, Step 1c, and Step 5.1.
   - Confirm "ready-for-regression NOT required for graduation PRs" is stated consistently in Protocol 90 Step 5.1 and Protocol 91 Step 7b / Step 8a.
   - Confirm the merge strategy requirement ("merge commit, not squash or rebase") appears consistently in Protocol 05b Step 0 (or Step 3) and the Non-Goals section where referenced.
   - Fix any cross-section contradictions found.

7. **Pre-commit lint check** — run `markdownlint-cli2` on all modified files before committing:

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/specs/developments/20260524190405_integration-branch-graduation-ceremony/2_integration-branch-graduation-ceremony_implementation-plan.md" \
     "docs/testing/workflow/727-integration-branch-graduation-ceremony.smoke-test.md" \
     "docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md" \
     "docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md" \
     "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"
   ```

   Fix any trailing whitespace, broken relative links, or missing trailing newlines before proceeding.

8. Update `CHANGELOG.md` under `[Unreleased]`:
   - `- **docs: integration branch graduation ceremony** (#727): Expands Protocol 05b (graduate-development) with human-approval gate, CHANGELOG handling, divergence check, optional sub-item disposition, and epic issue closure; adds graduation eligibility surfacing to Protocol 90 Step 1 portfolio scan; exempts graduation PRs from ready-for-regression requirement in Protocol 90 Step 5.1 and Protocol 91 Step 7b/8a.`

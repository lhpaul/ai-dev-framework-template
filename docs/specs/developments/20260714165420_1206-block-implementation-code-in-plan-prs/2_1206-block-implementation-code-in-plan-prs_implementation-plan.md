# Block Implementation Code in Plan PRs - Implementation Plan

**Spec**: [1_1206-block-implementation-code-in-plan-prs_specs.md](1_1206-block-implementation-code-in-plan-prs_specs.md)
**Smoke test runbook**: [1206-block-implementation-code-in-plan-prs.smoke-test.md](../../../testing/workflow/1206-block-implementation-code-in-plan-prs.smoke-test.md)

---

## Summary

**Approach**: Add a documentation-stage alignment gate to the existing PR
readiness path. The implementation should introduce a reusable shell checker
that classifies `spec/*` and `implementation-plan/*` PR diffs, posts or updates
a stable PR warning comment when unexpected implementation files are present,
and blocks `ready-for-human-review` in Protocol 91 Step 8a until the mismatch is
corrected or explicitly escalated.

**Estimated complexity**: M

**Rationale**: The behavior is small in product scope, but it is a shared
workflow guard. It touches the readiness checklist, reviewer documentation,
agent and skill guidance, a new script, and a script test harness.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `d26edf4` |
| Template-fit check | Read `.ai-dev-workflow.yaml` and issue #1206/spec text | `template.is_template: true`; item is template-generic workflow tooling, not framework-specific product code |
| Cross-cutting planning references | `grep -rl "02-generate-implementation-plan-protocol\|03-implement-development-protocol" .claude/agents/ .cursor/agents/ .codex/skills/ \| sort` | 6 files: `.claude/agents/developer.md`, `.claude/agents/tech-lead.md`, `.codex/skills/workflow-implementer/SKILL.md`, `.codex/skills/workflow-plan-writer/SKILL.md`, `.cursor/agents/developer.md`, `.cursor/agents/tech-lead.md` |
| Readiness references | `grep -rl "ready-for-human-review\|needs-fixes\|92-pr-readiness-signal-protocol" .claude/agents/ .cursor/agents/ .codex/skills/ .agents/skills/ docs/workflow/development-workflow/protocols scripts/development-workflow REVIEW.md \| sort` | Confirmed readiness logic is concentrated in Protocols 91/92/93, `pr-review-loop.sh`, `batch-merge.sh`, runner skills, and reviewer docs |
| Existing script test harnesses | `find scripts/development-workflow/tests -maxdepth 1 -type f -name 'test-*.sh' \| sort \| wc -l` | 34 shell harnesses exist; add the new checker harness beside them |
| Current development artifacts | `find docs/specs/developments/20260714165420_1206-block-implementation-code-in-plan-prs -maxdepth 1 -type f -print \| sort` | Spec exists; plan and runbook are created by this PR |
| Readiness gate insertion point | `rg -n "Step 8a|ready-for-human-review|Pre-merge Setup|human-checkpoint-required" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` | Protocol 91 Step 8a is the hard gate before applying `ready-for-human-review`; Protocol 92 defines readiness conditions |

---

## Layer-by-Layer Changes

### Workflow Scripts

- [ ] Add `scripts/development-workflow/check-documentation-stage-alignment.sh`
      as the shared checker for spec and plan branch PRs. The script should
      accept `--pr <number>` for live PRs and `--input <file>` for tests, plus
      `--json` for machine-readable output.
- [ ] Implement branch-stage detection from the PR head branch:
      `spec/*` maps to `spec`, `implementation-plan/*` maps to `plan`, and all
      other prefixes return `not_applicable` without blocking.
- [ ] For live PR mode, read PR metadata with `gh pr view` and changed files
      with `gh pr diff --name-only`, following the same bounded-file-list
      pattern used by `run-epic-risk-classifier.sh`.
- [ ] Classify documentation-stage diffs as aligned only when every changed file
      belongs to the expected documentation-stage artifact set:
      `docs/specs/developments/**/1_*_specs.md` for spec branches,
      `docs/specs/developments/**/2_*_implementation-plan.md` for plan
      branches, and `docs/testing/**/*.smoke-test.md` for plan-stage runbooks.
- [ ] Treat an empty changed-file list on `spec/*` or `implementation-plan/*`
      PRs as a documentation-stage mismatch, not as aligned. The checker should
      report that no stage artifact was found and block readiness until the diff
      can be corrected or investigated.
- [ ] Treat all other changed paths as unexpected implementation or
      stage-collapse evidence. The first implementation may report file paths
      directly instead of trying to infer every possible file category.
- [ ] Add a stable PR comment marker, for example
      `<!-- documentation-stage-alignment -->`, so reruns update one warning
      comment instead of posting duplicates.
- [ ] Return Step 8a exit code `8` for documentation-stage mismatch from the
      checker itself. Reserve separate non-zero exits for usage errors and
      failed GitHub/diff reads so the runner can distinguish a real mismatch
      from an infrastructure problem without remapping ambiguous checker exits.
- [ ] Define the explicit exception path as escalation only: the checker should
      print the mismatch and leave readiness blocked. It should not implement a
      bypass label in the first implementation.

### Work Item Runner / Readiness Protocols

- [ ] Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      Step 8a to run the stage-alignment checker after CI and reviewer-loop
      evidence is clean but before `ready-for-human-review` is applied.
- [ ] Add the next unused Step 8a exit code, `8`, for documentation-stage
      mismatch, and require `check-documentation-stage-alignment.sh` to emit that
      same code for mismatch outcomes. The action should be: leave the PR
      without `ready-for-human-review`, post or update the warning, apply
      `needs-fixes` if the implementation chooses to use labels for blockers,
      and report a human/workflow correction action.
- [ ] Make the gate run on every pass through Step 8a, including resumed PRs and
      fix cycles, so contaminated existing branches cannot bypass inspection.
- [ ] Update `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`
      so `ready-for-human-review` requires documentation-stage alignment for
      `spec/*` and `implementation-plan/*` PRs.
- [ ] Update `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
      only to route standalone readiness users back to the Protocol 91 Step 8a
      gate when they are preparing spec or plan PRs.

### Review Contracts and Agent Guidance

- [ ] Update `REVIEW.md` so spec and plan review checklists flag implementation
      artifacts on documentation-stage PRs as a workflow-stage blocker.
- [ ] Update tech-lead and developer guidance so agents do not put
      implementation files on `spec/*` or `implementation-plan/*` branches, and
      so they know a mismatch must be corrected or escalated before readiness.
- [ ] Update item-orchestrator guidance and Codex runner skills that invoke the
      affected readiness stage so runner summaries include the stage-alignment
      result when readiness is blocked.

### Tests

- [ ] Add `scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh`.
- [ ] Cover the required examples: mismatched plan PR, mismatched spec PR, and
      aligned documentation-stage PR.
- [ ] Cover resume behavior by using input fixtures that represent an existing
      PR diff rather than only files generated during the current run.
- [ ] Cover stable warning behavior by asserting the checker uses one marker
      comment and updates it on rerun.

### Database / Data Layer

- [ ] Not applicable. This workflow-process item does not change database
      schema, migrations, seed data, or product persistence.

### Backend / API

- [ ] Not applicable. No product API or service layer changes are planned.

### Shared Packages / Libraries

- [ ] Not applicable. The shared surface is workflow shell tooling and protocol
      documentation, not an application package.

### Frontend / UI

- [ ] Not applicable. There is no user interface change.

### Infrastructure / Configuration

- [ ] No new secrets or deployment infrastructure are required.
- [ ] If the implementation uses `needs-fixes` for stage mismatches, verify the
      label already exists before relying on it. Do not add new required
      repository secrets or GitHub Apps.

---

## Files to Modify

### Required Implementation Files

- [ ] `scripts/development-workflow/check-documentation-stage-alignment.sh` -
      new shared checker.
- [ ] `scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh` -
      new shell harness.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` -
      Step 8a hard gate and exit-code table.
- [ ] `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` -
      readiness condition for documentation-stage alignment.
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` -
      standalone-loop guidance to preserve the Step 8a gate.
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` -
      developer pre-submission guidance that implementation files belong on
      implementation branches, not spec or plan branches.
- [ ] `REVIEW.md` - spec and plan review checklist updates.
- [ ] `.claude/agents/item-orchestrator.md` - runner guidance for blocked
      documentation-stage readiness.
- [ ] `.cursor/agents/item-orchestrator.md` - runner guidance for blocked
      documentation-stage readiness.
- [ ] `.claude/agents/automated-reviewer-loop.md` - standalone reviewer-loop
      guidance.
- [ ] `.cursor/agents/automated-reviewer-loop.md` - standalone reviewer-loop
      guidance.
- [ ] `.claude/agents/tech-lead.md` - plan-stage branch discipline.
- [ ] `.cursor/agents/tech-lead.md` - plan-stage branch discipline.
- [ ] `.claude/agents/developer.md` - implementation-stage branch discipline.
- [ ] `.cursor/agents/developer.md` - implementation-stage branch discipline.
- [ ] `.codex/skills/workflow-item-orchestrator/SKILL.md` - Codex runner
      readiness guidance.
- [ ] `.codex/skills/workflow-orchestrator/SKILL.md` - batch runner readiness
      handoff guidance.
- [ ] `.codex/skills/workflow-reviewer-loop/SKILL.md` - standalone reviewer-loop
      guidance.
- [ ] `.codex/skills/workflow-plan-writer/SKILL.md` - plan-stage discipline.
- [ ] `.codex/skills/workflow-implementer/SKILL.md` - implementation-stage
      discipline.
- [ ] `.agents/skills/run-item/SKILL.md` - command-style runner guidance.
- [ ] `.agents/skills/run-items/SKILL.md` - bounded-batch readiness guidance.
- [ ] `.agents/skills/run-items/agents/openai.yaml` - bounded-batch default
      prompt readiness handoff wording.

### Explicitly Not Required

- [ ] `CHANGELOG.md` is not modified by this plan PR. The later implementation
      PR should add the changelog entry listed in the Implementation Order.
- [ ] Product app files, database migrations, UI components, and framework
      configuration are not part of this workflow-template change.

---

## Cross-Cutting Checklist Coverage

This plan introduces a new workflow quality gate that applies across independent
spec and plan PRs, so it is a cross-cutting checklist plan.

- [ ] Developer implementation protocol coverage:
      `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
      must add pre-submission branch-stage discipline wording so
      implementation work stays on implementation branches.
- [ ] Planning protocol coverage:
      `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
      does not need new plan-writing behavior, but it already requires this
      cross-cutting enumeration and should remain consistent if the feature
      changes the plan-stage artifact boundary.
- [ ] Review contract coverage: `REVIEW.md` must explicitly flag stage collapse
      on spec and plan PRs.
- [ ] Agent and skill coverage: the files listed in **Files to Modify** include
      the tech-lead, developer, item-orchestrator, reviewer-loop, and Codex skill
      surfaces that can create or mark documentation-stage PRs ready.
- [ ] Runner protocol coverage: Protocol 91 is the authoritative enforcement
      point because it owns the final readiness label gate.

---

## Parser-Risk Addendum

The implementation is parser-risk because it adds a scanner-like shell script
that classifies branch names and changed file paths.

### Edge-Case Enumeration

1. Boundary branch prefixes:
   - `spec/1206-example`
   - `implementation-plan/1206-example`
   - `feature/1206-example`
   - `docs/spec-example`
2. Allowed spec paths:
   - `docs/specs/developments/20260714165420_1206-block-implementation-code-in-plan-prs/1_1206-block-implementation-code-in-plan-prs_specs.md`
3. Allowed plan paths:
   - `docs/specs/developments/20260714165420_1206-block-implementation-code-in-plan-prs/2_1206-block-implementation-code-in-plan-prs_implementation-plan.md`
   - `docs/testing/workflow/1206-block-implementation-code-in-plan-prs.smoke-test.md`
4. Negative lookalikes:
   - `docs/specs/developments/20260714165420_1206-block-implementation-code-in-plan-prs/src/example.ts`
   - `src/components/PlanView.tsx`
   - `supabase/migrations/20260714000000_example.sql`
   - `.github/workflows/stage-alignment.yml`
5. Multiple unexpected paths in one PR:
   - `src/example.ts`
   - `supabase/migrations/20260714000000_example.sql`
6. Empty or unreadable diff:
   - empty changed-file list on a documentation-stage PR
   - `gh pr diff --name-only` failure
7. Stable warning rerun:
   - existing `<!-- documentation-stage-alignment -->` comment present
   - no existing marker comment present

### Unit Test Mapping

Create `scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh`
with at least these cases:

1. `spec_branch_allows_spec_doc` covers Edge cases 1 and 2.
2. `plan_branch_allows_plan_doc_and_runbook` covers Edge cases 1 and 3.
3. `implementation_branch_not_applicable` covers Edge case 1.
4. `spec_branch_blocks_source_file` covers Edge case 4.
5. `plan_branch_blocks_migration_and_source_file` covers Edge cases 4 and 5.
6. `documentation_stage_empty_diff_blocks_readiness` covers Edge case 6 empty
   changed-file lists.
7. `diff_read_failure_exits_infrastructure_error` covers Edge case 6
   infrastructure failures.
8. `warning_comment_uses_stable_marker` covers Edge case 7.

### Suppression Semantics

No inline suppression directive is introduced. The explicit exception path is
human escalation: the runner reports the mismatch, the PR warning names the
unexpected files, and automatic readiness remains blocked until the diff is
corrected or a human decides how to proceed outside the automatic ready path.

---

## Concurrency Safety

The feature does not introduce concurrent event sources, but the checklist is
recorded for completeness because the gate runs in automation that can be
restarted.

- **Shared mutable state guards**: Not applicable. The checker reads PR metadata
  and writes only one stable PR comment keyed by a marker.
- **Re-entrancy / in-flight tracking**: Not applicable. Reruns are idempotent
  because the marker comment is updated rather than duplicated.
- **Event deduplication**: Not applicable. Duplicate runs produce the same
  classification from the current PR diff.
- **Listener and resource cleanup**: Not applicable. No listeners, timers, or
  long-lived handles are introduced.
- **Race conditions at initialization**: Not applicable. The checker evaluates
  the current PR state at invocation time.
- **Race conditions at teardown**: Not applicable. No teardown sequence is
  introduced.
- **Error propagation across async boundaries**: Not applicable. The shell
  script should use explicit exit codes and stderr/stdout output; no async
  callback boundary is introduced.

---

## Testing Strategy

**Test types**: Shell unit harness, protocol self-review, markdown lint, smoke
runbook.

**Key scenarios to test**:

1. Aligned plan-stage PR continues through readiness. Maps to AC1 and AC8.
2. Mismatched plan-stage PR blocks readiness and reports unexpected files. Maps
   to AC2, AC4, AC5, and AC6.
3. Mismatched spec-stage PR blocks readiness and reports unexpected files. Maps
   to AC3, AC4, AC5, and AC6.
4. Resumed contaminated PR is evaluated from the current diff. Maps to AC7.
5. Empty changed-file lists on documentation-stage branches block readiness
   instead of passing vacuously. Maps to AC8 and AC10.
6. Selected enforcement mechanism and exception behavior are documented. Maps to
   AC9.
7. Verification examples include mismatched plan, mismatched spec, and aligned
   documentation-stage fixtures. Maps to AC10.

**Smoke test runbook**:
`docs/testing/workflow/1206-block-implementation-code-in-plan-prs.smoke-test.md`

**Regression suite**: Add the shell harness to
`scripts/development-workflow/tests/` and run it directly. Also run the broader
workflow shell test set if the implementation changes shared helper functions.

---

## Seed Data

No database seed data is required.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| PR fixture JSON | Head branch, changed-file list, existing comments, expected verdict | Generated inside `scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh` |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      - document the new readiness gate, exit code, warning behavior, and runner
      summary obligation.
- [ ] `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`
      - add documentation-stage alignment to readiness conditions.
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
      - point standalone reviewer-loop users back to the readiness gate before
      applying labels.
- [ ] `REVIEW.md` - add review checklist expectations for stage collapse in
      spec and plan PRs.
- [ ] `.claude/agents/*.md`, `.cursor/agents/*.md`, `.codex/skills/**/*.md`,
      and `.agents/skills/**/*.md` listed above - keep agent guidance aligned
      with the new gate.
- [ ] `docs/project/*` - no update required; this is workflow-template behavior,
      not project domain, architecture, or database model.
- [ ] `AGENTS.md` - no update required unless the implementation changes the
      public workflow command table or branch policy.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Overly narrow allowlist blocks legitimate documentation-stage artifacts | Medium | Medium | Keep the MVP allowlist focused on the current workflow artifacts, report exact unexpected paths, and require human correction or escalation rather than silent bypass |
| Stage mismatch warning duplicates on rerun | Medium | Low | Use a stable HTML marker comment and update the existing comment |
| Gate is documented but not enforced by runners | Low | High | Put enforcement in Protocol 91 Step 8a and update runner/skill guidance that can apply readiness labels |
| Script failures are mistaken for stage mismatch | Low | Medium | Use distinct exit codes for mismatch, usage errors, and GitHub/diff read failures |
| Valid implementation PRs are affected | Low | High | Gate only `spec/*` and `implementation-plan/*`; all other branch prefixes return `not_applicable` |

---

## Code Samples

No code samples are included in this plan. The implementation PR should write
the checker and tests directly.

---

## Implementation Order

1. Create `scripts/development-workflow/check-documentation-stage-alignment.sh`
   with live PR mode, fixture input mode, JSON output, branch-stage detection,
   changed-file classification, stable warning comment handling, mismatch exit
   code `8`, and distinct usage/infrastructure exit codes.
2. Add `scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh`
   with fixture-based coverage for the parser-risk edge cases and required
   acceptance examples.
3. Run the new test harness and confirm it passes.
4. Update Protocol 91 Step 8a to call the checker before
   `ready-for-human-review`, document the new exit code, and require runner
   summaries to include the stage-alignment result when blocked.
5. Update Protocol 92 readiness conditions and Protocol 93 standalone guidance
   so all readiness paths preserve the gate.
6. Update `REVIEW.md` with spec and plan review expectations for documentation
   stage collapse.
7. Update the agent and skill guidance files listed in **Files to Modify** so
   creators, runners, and reviewer-loop aliases do not bypass the new gate.
8. Add the implementation changelog entry under `[Unreleased]` using this exact
   format:
   `- **Block Implementation Code in Plan PRs** (#1206): Add a documentation-stage alignment gate that blocks spec and plan PR readiness when implementation files are present.`
9. Run `bash scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh`.
10. Run markdown lint on changed markdown files.
11. If any `.sh` files changed, run ShellCheck and
    `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`.
12. Run the smoke test runbook and record the results in the implementation PR.

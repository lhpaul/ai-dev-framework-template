# Consumer Workflow Test Portability — Implementation Plan

**Issue**: [#1873](https://github.com/lhpaul/ai-dev-framework-template/issues/1873)
**Spec**: [Consumer Workflow Test Portability](./1_1873-consumer-test-portability_specs.md)
**Smoke test runbook**: [Consumer portability](../../../testing/workflow/1873-consumer-test-portability.smoke-test.md)

## Summary

**Approach**: Keep live template-policy assertions mode-specific, while testing
shared behavior with explicit fixture configuration. Supply deterministic
historical-document substitutes in the reviewer harness. Runtime scripts and
consumer policy remain unchanged.

**Estimated complexity**: S.
**Rationale**: Bounded test-harness changes within the existing Bash/Python toolchain.
**Dependencies**: Spec PR #1901 is MERGED at
`915b65447cd49d122fe43a922ecc527c12e332da`, verified live on 2026-10-07.
Before implementation, re-read its merge state and the plan PR state; stop if
either required prerequisite is not merged.
**Template fit**: Applicable and passed; the change targets this framework's own
test toolchain and is independent of consumer application stacks.

## Verification Log

Evidence was gathered at `298eaf7835dea9acb88df4130ceafad68df87d8e`
(unless a different revision is explicitly named).

| Check | Command / query | Result |
| --- | --- | --- |
| Targets and affected statements | `rg -n 'is_template_live_repo_config|D-9|framework_creation_type_exact_match|consumer_mode|guidance_mirror|Scenario 15 reverse' scripts/development-workflow/tests/test-{consumer-tree-test-gating,step7a-surface-consistency,add-backlog-item,framework-mode-type-routing,local-ai-reviewer}.sh` | Locates the issue's bounded test surfaces; see Files to Modify. |
| Mode helper and configuration semantics | `rg -n 'workflow_template_is_template|workflow_config_file|AI_DEV_WORKFLOW_CONFIG_FILE' scripts/development-workflow/workflow-lib.sh` | The existing mode helper accepts an explicit config path; its default uses the repository config. Test fixture paths can reuse that contract. |
| Helper edge cases and cleanup | `rg -n 'is_template_|trap .*EXIT|mktemp|path_with_spaces' scripts/development-workflow/tests/test-{consumer-tree-test-gating,add-backlog-item,framework-mode-type-routing,local-ai-reviewer}.sh` | Existing helper edge cases and cleanup traps support the parser-risk and isolation mappings. |
| Existing historical fallback | `sed -n '1690,1702p' scripts/development-workflow/tests/test-local-ai-reviewer.sh` | Earlier scenario supplies stub plan/spec after failed copies; reverse scenario does not. |
| Guidance ownership | `rg -n 'AGENTS.md|GEMINI.md|docs/testing/workflow|docs/specs/developments' sync-manifest.yaml scripts/development-workflow/tests/test-framework-mode-type-routing.sh` | Agent guidance is project-owned; #1874 added the named runbooks with hub_only scope, so they are not available in every sync profile. Historical #1655 development documents are absent from the shipped tree. Original-mode gating already exists for agent guidance. |
| Checks consumers | `rg -n 'checks\(fixture\)|checks\(root\)|guidance_check_all_pass' scripts/development-workflow/tests/test-{step7a-surface-consistency,framework-mode-type-routing}.sh` | D-9 is consumed by the baseline, clean copied fixture, planted result, and repaired result. Guidance is consumed by clean, planted, and repaired checks. |
| Reproduction | Execute Files to Modify suites in a committed scratch copy of versioned workflow files with consumer mode, a different supported reviewer, project-owned guidance, and no template historical spec/plan/runbooks | Live-mode/config assertions fail; guidance fails on absent runbooks; reviewer reverse scenario aborts on the absent #1655 plan. Commit the scratch fixture before reviewer tests so HEAD resolution is valid. |

## Cross-Cutting Operational Assumption Check

**Result**: `Verified`.

| Surface | Value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact owner and base | Current template repository; develop | Bounded prelude for #1873; .ai-dev-workflow.yaml | 2026-10-07; recorded revision in Verification Log | Invocation item list: #1873; own spec PR #1901 | Verified |
| Consumer ownership | Consumer owns configuration and historical artifacts | sync-manifest.yaml; mode helper | Same verification revision/time | The issue's enumerated suites; #1874's guidance update already on develop | Verified |

Implementation re-reads these sources before edits and records `Still valid`.

## Files to Modify

All suite paths below are under `scripts/development-workflow/tests/`.
This target list is indicative scaffolding with equivalent coverage permitted.

| File | Change and observed outcome |
| --- | --- |
| test-consumer-tree-test-gating.sh | Gate the live-template assertion with workflow_template_is_template; emit an explicit skip for consumers. Preserve existing helper input cases. |
| test-step7a-surface-consistency.sh | Use the shared mode helper for D-9. Enforce the shipped-runner equality only in template mode; retain supported-reviewer validation in D-4 in both modes. Gate its README plant consistently and print a consumer skip. |
| test-add-backlog-item.sh | Replace the ambient-config assumption in the exact Workflow refusal block with an explicit framework fixture, restoring the original file afterward and on abort. Retain lowercase negative and consumer Workflow positive cases. |
| test-framework-mode-type-routing.sh | Install the existing framework fixture for ambient framework scenarios; cleanup restores the original config. Determine guidance ownership from the untouched backup. Gate historical runbook greps on original template mode and retain synced orchestrator/protocol checks and their planted violation in both modes. |
| test-local-ai-reviewer.sh | Give Scenario 15 reverse the same missing-plan/spec fallback as the earlier scenario, retaining spec-sibling reverse-path assertions. |
| changelog.d/1873.fixed.consumer-test-portability.md | Describe the consumer-portability repair without editing CHANGELOG.md. |

## Testing Strategy

Coverage intent is to eliminate repository-state dependencies without deleting
shared behavior tests. No additional CI workflow is planned.

| Scenario | Verification surface | Spec coverage |
| --- | --- | --- |
| Template baseline | Execute the affected suites in a clean versioned scratch tree | AC5 |
| Consumer config and alternate supported reviewer | Execute the same suites and the Step 7a plant mode in a consumer scratch tree | AC1, AC3, AC5 |
| Absent template history and consumer-owned guidance | Omit historical docs/runbooks; use consumer-owned AGENTS/GEMINI content | AC2 |
| Framework refusal and routing remain meaningful | Existing exact/lowercase refusal, consumer positive, stop/hold/reclassification assertions run with controlled configs | AC3 |
| Planted detection survives gating | Step 7a --prove-plants in template and consumer modes; guidance suite clean/plant/repaired assertions | AC4 |
| Mode and policy boundaries | Existing true/false, missing, empty, whitespace, quoted/case/commented helper cases plus D-4 unsupported-reviewer plant; runbook Step 4 grep assertions require every consumer skip marker | AC5 |

### Parser-risk addendum

Classification: applies because test checks scan structured configuration and
policy prose. Reuse workflow_template_is_template rather than adding a mode parser.

| Edge case | Automated mapping |
| --- | --- |
| True, false, missing key/section/file | Existing Area 1 cases in test-consumer-tree-test-gating.sh |
| Empty and whitespace-only config | Existing Area 1 empty/blank cases in the same suite |
| Quoted/case variants and header/value comments | Existing Area 1 variant cases in the same suite |
| Consumer alternate reviewer versus template shipped list mismatch | D-9 baseline and template README plant in test-step7a-surface-consistency.sh; consumer fixture run |
| Unsupported reviewer value remains rejected | D-4 plant in test-step7a-surface-consistency.sh |
| Missing historical runbooks and development documents | Consumer scratch run of routing and local reviewer suites |

No suppression feature is introduced.

### Isolation and harness safety

Run suites that swap repository files sequentially in a disposable versioned
scratch tree; template and consumer runs use different scratch roots. Preserve
one EXIT cleanup trap in each changed shell harness. Quoted paths and existing
space/glob cases remain. No new runtime environment variables are required.
No concurrent event sources or cross-cutting checklist changes are introduced.

## Seed Data

Use versioned files selected by git ls-files, excluding ignored credentials,
local overrides, dependencies, and .git. Initialize and commit each scratch tree.
The consumer fixture sets consumer mode, selects Codex instead of the shipped
runner, supplies its own guidance, and omits docs/specs/developments and
historical docs/testing/workflow. Tests create their own mocked tracker data.

## Documentation Updates

Only the release-note fragment in Files to Modify; product/project guidance and
runtime workflow protocols do not change. This plan's smoke runbook records
reproduction and planted verification.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Gating hides shared failures | Medium | Medium | Keep D-4, protocol/mirror checks, fixture routing and refusal tests active in both modes; execute plants. |
| A suite leaves config swapped | Low | Medium | Use existing backups and EXIT cleanup; compare scratch configuration before/after. |
| An uncommitted fixture creates unrelated HEAD failures | Medium | Low | Commit fixtures before running the local reviewer suite. |

## Factual Claim Evidence

**Rule 5 composed sites**: The Checks consumers search in Verification Log is the
bounded enumeration for the changed validation units. In Step 7a, consumer
D-9 follows an explicit template-only skip at each baseline/copied/repair check;
its template plant still fails only D-9, while D-4 and other plants run in both
modes. In guidance, original-mode ownership controls historical runbook checks
at clean, planted, and repaired sites; the synced-mirror plant is still evaluated
in a consumer. Inputs formerly failing from absent project-owned artifacts are
absorbed only by those mode-specific branches; shared checks keep their outcome.

**Rule 6 scoped obligations**: D-9 equality and its README plant bind only to
fixture/source configurations recognized as template by the shared helper;
Step 7a checks and the plant loop discharge that obligation. Historical runbook
greps bind only to the original template configuration saved before swaps;
guidance_check_all_pass discharges it. Restoration binds to every config-swap
exit in the backlog/routing harnesses and is discharged by immediate restore
and their existing EXIT cleanup traps.

## Implementation Order

1. Reverify Operational Assumption sources and the current approved base.
2. Repair live-mode/default checks and the backlog framework fixture. Verify
   consumer-tree gating, Step 7a consistency/plants, and backlog creation in both
   modes; commit that coherent checkpoint. Routing is deferred to the next step.
3. Repair the routing framework fixture and historical guidance/document
   dependencies. Verify all affected suites and plants in both modes, including
   the runbook skip-output assertions, and commit the repair and release fragment.
4. Run ShellCheck, shell guard, relevant markdown lint, and git diff --check.
5. Review the exact PR diff against REVIEW.md; open the draft implementation PR
   with reproduction, repaired outcomes, and planted file/line evidence.

## Residual Verification

Use scope-residual-gate.sh with the live issue title/body before readiness.
Record disposition for each issue-listed failing surface from Files to Modify:
repaired and verified, already handled by #1874, or explicitly out of scope.
The optional CI job and unrelated post-merge advisory are the only intended
scope exclusions. Missing coverage of an issue-listed failure blocks readiness.

## Completion Checklist

- [ ] Spec criteria covered by Testing Strategy.
- [ ] Both repository modes pass with original configuration restored.
- [ ] Planted violations fail and repaired fixtures pass at concrete lines.
- [ ] Lint and shell checks pass.
- [ ] No runtime or project-owned policy changes in the implementation diff.

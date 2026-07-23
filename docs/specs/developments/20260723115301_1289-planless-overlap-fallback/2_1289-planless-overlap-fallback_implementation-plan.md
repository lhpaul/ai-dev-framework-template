# Planless Batch Overlap Fallback - Implementation Plan

**Spec**: [1_1289-planless-overlap-fallback_specs.md](1_1289-planless-overlap-fallback_specs.md)

**Smoke test runbook**: [1289-planless-overlap-fallback.smoke-test.md](../../../testing/workflow/1289-planless-overlap-fallback.smoke-test.md)

---

## Summary

**Approach**: Add a provider-neutral overlap classifier that consumes the
current batch items, their plan-derived file sets, and tracker-sourced titles
and briefs as structured JSON. Preserve exact plan-file intersections as the
highest-confidence result. For missing plan evidence, extract explicit file,
route, function, and named-module signals, compare every implementation pair,
and emit concrete, suspected, or no-actionable-overlap dispositions. Protocol
90 will place concrete pairs in serial lanes, require pair-scoped confirmation
before suspected pairs can run in parallel, and carry the disposition into the
confirmation and final batch summaries.

**Estimated complexity**: M

**Rationale**: The existing batch planner already emits plan-derived
`FILE_SET` evidence and Protocol 90 owns lane assignment, but `unknown` currently
continues with only a warning. A separate structured helper keeps heuristic
brief parsing testable and provider-neutral while allowing Protocol 90 to
preserve its existing priority, tool-fix, isolation, and file-conflict gates.

**Dependencies**: Python 3 and the repository's existing shell/JSON tooling.
The orchestrator already gathers current tracker descriptions before proposing
a batch.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `21f23e3` |
| Template-fit check | Read `.ai-dev-workflow.yaml`, issue #1289, and the approved spec | Provider-neutral workflow orchestration behavior belongs in the template |
| Current plan evidence | Read `extract_file_set` and `detect_file_conflicts` in `scripts/development-workflow/workflow-batch-plan.sh` | Implementation plans emit normalized `FILE_SET`; exact intersections serialize known pairs |
| Current planless behavior | Read Protocol 90 “Same-batch file-level conflict detection” | `FILE_SET=unknown` is warned but remains in the batch without a brief-derived disposition |
| Tracker evidence availability | Read Protocol 90 Step 1 | Portfolio gathering already requires the latest tracker title and brief/description |
| Lane integration | Read `scripts/development-workflow/workflow-batch-lanes.sh` and its harness | Stage/capacity lanes exist, but no pairwise overlap disposition is consumed |
| Existing tests | `find scripts/development-workflow/tests -maxdepth 1 -type f -name '*batch*' -print` | `test-workflow-batch-lanes.sh` covers batch planner/lane integration; add a focused classifier harness and targeted lane assertions |
| Supported multi-item surfaces | `rg -l "90-batch-orchestrate-work-protocol|Protocol 90" .agents/skills .codex/skills .claude/commands .claude/agents .cursor/commands .cursor/agents` | Canonical protocol plus run-work/run-items command and orchestrator mirrors must preserve the gate |

---

## Layer-by-Layer Changes

### Brief-Overlap Classifier

- [ ] Add `scripts/development-workflow/workflow-batch-overlap.sh`.
- [ ] Accept `--input <json-file>` and optional `--decision-file <jsonl-file>`;
      support `--json` plus stable key-value output for shell callers.
- [ ] Define each input item with:
      `id`, `title`, `brief`, `fileSet`, `priority`, `createdAt`, and
      `nextAction`. Treat titles/briefs as current tracker evidence supplied by
      the orchestrator; do not perform provider-specific network reads in the
      helper.
- [ ] Restrict pair classification to implementation-stage actions. Spec, plan,
      review-only, skipped, tool-fix-serialized, and otherwise held items remain
      outside the current overlap input.
- [ ] Normalize plan file-set paths as repo-relative forward-slash strings and
      preserve exact file intersections as `concrete` with `source=plan`.
- [ ] For items whose plan file set is `unknown` or empty, extract only explicit
      implementation targets from the title and brief:
      - repo-like file paths;
      - HTTP method plus route, or explicit route/path literals;
      - function/method identifiers identified by `name()` or an adjacent
        function/method cue;
      - explicitly cued module, package, component, helper, script, or service
        names.
- [ ] Normalize signal type and value without collapsing distinct target
      classes. A route and a module with similar words must not become an exact
      match.
- [ ] Maintain a small documented generic-term stoplist for workflow vocabulary
      such as `workflow`, `review`, `batch`, `item`, `plan`, and
      `implementation`. Generic words without an explicit target cue must
      produce no signal.
- [ ] Classify the exact same typed signal in both briefs as `concrete`.
      Same-route and same-function matches are mandatory concrete cases.
- [ ] Classify meaningful but non-conclusive relationships as `suspected`, for
      example a specific module signal that contains a specific path basename,
      or two route literals where one is a parent of the other. Include both
      original signals and the uncertainty reason.
- [ ] Return `no_actionable_overlap` when targets are distinct or only generic
      terminology overlaps. State explicitly that this is not proof of
      independence.
- [ ] Preserve plan evidence precedence:
      - an exact plan file intersection always remains concrete;
      - fallback evidence cannot downgrade it;
      - a non-concrete disagreement between plan and brief evidence becomes
        suspected and reports both sources.
- [ ] Compare every meaningful implementation candidate pair exactly once using
      a stable sorted pair ID.
- [ ] Emit for each pair: item IDs, classification, confidence/source, typed
      shared signals, explanation, default dispatch, confirmation requirement,
      and required next action.
- [ ] Emit an aggregate list of serial groups so transitive concrete overlaps
      such as A-B and B-C cannot be split into concurrent lanes.

### Pair-Scoped Human Decisions

- [ ] Define an invocation-scoped JSONL decision record with batch fingerprint,
      sorted pair ID, decision (`allow_parallel` or `serialize`), evidence hash,
      and recorded human instruction.
- [ ] Accept a decision only when its batch fingerprint, pair ID, and evidence
      hash match the current proposal. Ignore stale records from another batch,
      pair, or changed brief and keep the suspected pair serialized.
- [ ] Permit `allow_parallel` only for `suspected` pairs. Concrete overlap
      remains serial under the current batch approval.
- [ ] Default every suspected pair to serial when no matching explicit decision
      exists.
- [ ] Include accepted and rejected/stale decisions in structured output so the
      confirmation and final summaries are auditable.

### Batch Planner and Lane Integration

- [ ] Keep `workflow-batch-plan.sh` as the source of plan-derived `FILE_SET`.
      Do not replace its exact conflict detector.
- [ ] Update the Protocol 90 caller to assemble classifier JSON from batch-plan
      output plus current tracker title/brief evidence gathered in Step 1.
- [ ] Run the classifier after dependency/tool-fix filtering and before lane
      dispatch or batch confirmation.
- [ ] Extend `workflow-batch-lanes.sh` to consume overlap dispositions or an
      enriched batch-plan stream:
      - hold lower-priority members of concrete serial groups;
      - hold suspected pairs unless a matching pair-scoped parallel decision is
        present;
      - leave `no_actionable_overlap` items eligible for normal capacity and
        isolation checks.
- [ ] Preserve Protocol 90 priority ordering: Urgent/High/Normal/Low, then
      creation date, then lexicographic ID determines which serial-group item
      remains in the current lane.
- [ ] For a serialized implementation item, require the prior item's
      implementation PR to merge into the approved base before the later item
      starts from a refreshed base.
- [ ] Keep dependency, tool-fix, local-runtime, stage-capacity, worktree
      isolation, and nested-artifact gates independent. An overlap result does
      not satisfy or waive any of them.

### Protocol and Supported Surfaces

- [ ] Replace Protocol 90's `FILE_SET=unknown` “warning and proceed” rule with
      the brief-derived pair classification and default-serial behavior.
- [ ] Add the structured overlap evidence to the pre-dispatch confirmation
      summary: pair, typed signals, classification, uncertainty, and next
      action.
- [ ] Add overlap disposition and accepted pair-scoped human decisions to the
      final batch summary.
- [ ] Update the canonical run-work/run-items and orchestrator surfaces so every
      multi-item proposal or execution consumes the same Protocol 90 overlap
      gate:
      - `.agents/skills/run-work/SKILL.md`
      - `.agents/skills/run-items/SKILL.md`
      - `.codex/skills/workflow-orchestrator/SKILL.md`
      - `.claude/agents/orchestrator.md`
      - `.cursor/agents/orchestrator.md`
      - `.claude/commands/run-work.md`
      - `.cursor/commands/run-work.md`
      - `.claude/commands/run-items.md`
      - `.cursor/commands/run-items.md`
- [ ] Keep command metadata files unchanged unless their default prompt
      duplicates the parallel-safety rules. If a live implementation query
      finds duplicated wording there, update the exact matching metadata mirror
      and record it in the PR.

### Tests

- [ ] Add
      `scripts/development-workflow/tests/test-workflow-batch-overlap.sh`.
- [ ] Use JSON fixtures for plan-known, planless, mixed-evidence, generic-term,
      and decision-file cases.
- [ ] Extend `scripts/development-workflow/tests/test-workflow-batch-lanes.sh`
      with focused classifier-to-lane assertions.
- [ ] Cover same route, same function, same explicit module, exact plan file,
      suspected parent route, unrelated targets, and generic workflow wording.
- [ ] Cover transitive concrete groups and priority/createdAt/lexicographic
      serial ordering.
- [ ] Cover missing, matching, stale-pair, stale-batch, and stale-evidence human
      decision records.
- [ ] Cover mixed plan/fallback evidence without downgrading concrete plan
      overlap.
- [ ] Assert output order and pair IDs are stable when input item order changes.

### Database / Data Layer

- [ ] Not applicable. No schema, migration, seed, or persisted product data.

### Backend / API

- [ ] Not applicable. The helper consumes a local JSON contract and does not add
      a network API.

### Shared Packages / Libraries

- [ ] Not applicable. This is workflow shell/Python tooling.

### Frontend / UI

- [ ] Not applicable. Operator-visible output is CLI/protocol text.

### Infrastructure / Configuration

- [ ] No secrets or deployment resources.
- [ ] No new repository config key is required. Existing concurrency caps and
      priority rules remain authoritative.

---

## Files to Modify

### Required Implementation Files

- [ ] `scripts/development-workflow/workflow-batch-overlap.sh` - new structured
      classifier and decision validator.
- [ ] `scripts/development-workflow/tests/test-workflow-batch-overlap.sh` - new
      parser/decision harness.
- [ ] `scripts/development-workflow/workflow-batch-lanes.sh` - apply pair/group
      dispositions to implementation lanes.
- [ ] `scripts/development-workflow/tests/test-workflow-batch-lanes.sh` -
      classifier-to-lane integration tests.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      - evidence gathering, classification, confirmation, serialization,
      resume, and final-summary contract.
- [ ] `.agents/skills/run-work/SKILL.md` - scan/proposal overlap gate.
- [ ] `.agents/skills/run-items/SKILL.md` - bounded execution overlap gate.
- [ ] `.codex/skills/workflow-orchestrator/SKILL.md` - canonical Codex
      orchestrator behavior.
- [ ] `.claude/agents/orchestrator.md` - Claude batch handoff behavior.
- [ ] `.cursor/agents/orchestrator.md` - Cursor batch handoff behavior.
- [ ] `.claude/commands/run-work.md` and `.cursor/commands/run-work.md` -
      read-only proposal evidence.
- [ ] `.claude/commands/run-items.md` and `.cursor/commands/run-items.md` -
      pre-dispatch pair decision behavior.

### Verify During Implementation

- [ ] `.agents/skills/run-work/agents/openai.yaml`,
      `.agents/skills/run-items/agents/openai.yaml`, and
      `.codex/skills/workflow-orchestrator/agents/openai.yaml` - update only if
      the live query finds duplicated parallel-safety wording rather than a
      generic pointer to the parent skill.

### Explicitly Not Required

- [ ] `scripts/development-workflow/workflow-batch-plan.sh` retains
      plan-derived file extraction and exact intersection as the authoritative
      source. The new classifier consumes its output.
- [ ] Single-item `/run-item` surfaces do not make multi-item parallelization
      decisions.
- [ ] `CHANGELOG.md` is exempt from this plan PR. The implementation PR adds
      the literal in **Implementation Order**.
- [ ] `docs/project/*`, database files, and product source are not affected.

---

## Overlap and Dispatch Consistency Matrix

| Available evidence | Pair classification | Default dispatch | Required next action | Mirror surfaces | Test |
| --- | --- | --- | --- | --- | --- |
| Plan file sets intersect exactly | Concrete, source `plan` | Serial | Keep higher-priority item; hold later item until merge into approved base | Classifier, Protocol 90, lanes, all run-work/run-items mirrors | `plan_overlap_remains_concrete` |
| No usable plan; same normalized route | Concrete, source `brief` | Serial | Show route and serialize pair | Same | `same_route_is_concrete` |
| No usable plan; same normalized function | Concrete, source `brief` | Serial | Show function and serialize pair | Same | `same_function_is_concrete` |
| No usable plan; same explicitly cued module | Concrete, source `brief` | Serial | Show module and serialize pair | Same | `same_module_is_concrete` |
| Specific signals are related but not identical | Suspected | Serial unless current pair decision allows parallel | Show uncertainty and request pair-scoped choice | Same plus decision record | `parent_route_is_suspected` |
| Plan and fallback disagree, with no plan concrete intersection | Suspected | Serial unless explicitly allowed | Report both sources; do not claim independence | Same | `mixed_evidence_disagreement_is_suspected` |
| Plan proves concrete overlap while brief appears unrelated | Concrete, source `plan` | Serial | Preserve plan result; fallback cannot downgrade | Same | `fallback_cannot_downgrade_plan` |
| Specific targets are distinct | No actionable overlap found | Parallel-eligible | Continue all other gates; do not claim proven independence | Same | `unrelated_targets_remain_eligible` |
| Only generic workflow terms overlap | No actionable overlap found | Parallel-eligible | Continue all other gates | Same | `generic_terms_do_not_overlap` |
| Suspected pair plus matching current decision `allow_parallel` | Suspected, decision accepted | Parallel-eligible | Record decision in confirmation and final summary | Classifier, Protocol 90, lanes | `matching_pair_decision_allows_parallel` |
| Suspected pair plus missing/stale decision | Suspected, no valid decision | Serial | Hold pair and request current decision | Same | `stale_decision_does_not_apply` |

---

## Cross-Cutting Checklist Coverage

This plan modifies a complex workflow decision gate but does not introduce a
new review/planning checklist category.

- [ ] Protocol 90 is the canonical decision owner.
- [ ] Read-only scan and bounded execution surfaces consume the same
      classifier.
- [ ] Claude, Cursor, and Codex orchestrator mirrors preserve pair-scoped
      confirmation and default serialization.
- [ ] Lane and helper tests map every decision-matrix row.
- [ ] Single-item and stage-specific creator surfaces remain unaffected.

---

## Parser-Risk Addendum

The new helper is parser-risk because it extracts typed targets from
semi-structured work item prose.

### Edge-Case Enumeration

1. File paths:
   - `scripts/development-workflow/pr-review-loop.sh`
   - backticked `src/routes/users.ts`
   - Windows-looking `src\jobs\worker.ts` normalized to forward slashes
   - sentence punctuation after a path
2. Routes:
   - `GET /api/users/:id`
   - backticked `/api/users`
   - `/api/users` versus `/api/users/:id` as suspected, not exact
   - plain word `route` with no literal target
3. Functions:
   - `resolvePolicy()`
   - “function `resolvePolicy`”
   - “workflow resolution” without an identifier cue
4. Modules:
   - “module `reviewer-loop`”
   - “helper `checkpoint-resume-gate.sh`”
   - generic “reviewer workflow module” without a delimited/specific name
5. Negative/generic text:
   - shared `workflow`, `batch`, `review`, `plan`, and `implementation`
   - unrelated explicit targets in otherwise similar briefs
6. Multiple targets:
   - one pair shares a route but has distinct files
   - A-B and B-C produce one transitive serial group
7. Evidence precedence:
   - exact plan intersection plus unrelated briefs
   - distinct plan files plus related brief signals
8. Decision records:
   - same pair/current batch/current evidence
   - reversed pair ordering
   - different batch fingerprint
   - changed evidence hash
   - decision for another pair
9. Input safety:
   - empty title/brief
   - missing optional fields
   - duplicate item ID
   - invalid JSON
   - input order reversed

### Unit Test Mapping

Create `scripts/development-workflow/tests/test-workflow-batch-overlap.sh`
with:

1. `file_path_variants_normalize` for Edge case 1.
2. `same_route_is_concrete`, `parent_route_is_suspected`, and
   `route_word_without_literal_is_ignored` for Edge case 2.
3. `same_function_is_concrete` and
   `generic_resolution_text_is_ignored` for Edge case 3.
4. `same_module_is_concrete` and
   `generic_module_word_is_ignored` for Edge case 4.
5. `generic_terms_do_not_overlap` and
   `unrelated_targets_remain_eligible` for Edge case 5.
6. `multiple_signals_keep_concrete_result` and
   `transitive_overlaps_form_one_serial_group` for Edge case 6.
7. `fallback_cannot_downgrade_plan` and
   `mixed_evidence_disagreement_is_suspected` for Edge case 7.
8. `matching_pair_decision_allows_parallel`,
   `reversed_pair_order_matches`, and
   `stale_decision_does_not_apply` for Edge case 8.
9. `empty_brief_is_no_actionable_overlap`,
   `missing_fields_fail_closed`, `duplicate_ids_rejected`,
   `invalid_json_rejected`, and `input_order_is_stable` for Edge case 9.

### Suppression Semantics

No inline prose suppression is introduced. Pair-scoped parallel approval is a
separate structured human decision whose batch and evidence identity must match
the current proposal.

---

## Concurrency Safety

This feature controls concurrent dispatch and therefore requires explicit
safety treatment.

- **Shared mutable state guards**: The classifier is read-only. Protocol 90 and
  the isolation manifest remain the only dispatch-state owners.
- **Re-entrancy / in-flight tracking**: Stable pair IDs, evidence hashes, and
  batch fingerprints make reruns deterministic and prevent a prior decision
  from silently moving to changed evidence.
- **Event deduplication**: Each sorted item pair is emitted once; transitive
  concrete overlaps are collapsed into one serial group.
- **Listener and resource cleanup**: Not applicable; no listeners or background
  processes.
- **Race conditions at initialization**: Build all classifications from one
  current tracker snapshot before confirmation. If the snapshot cannot be
  assembled, default affected unknown pairs to serial.
- **Race conditions at teardown**: Before dispatch, verify the classifier
  evidence hash still matches the confirmed proposal; changed evidence requires
  a new disposition.
- **Error propagation across async boundaries**: Not applicable inside the
  synchronous helper. Child dispatch begins only after the full gate returns.

---

## Testing Strategy

**Test types**: Parser unit harness, batch-lane integration harness, protocol
and mirror self-review, shell lint, markdown lint, and smoke runbook.

**Key scenarios to test**:

1. Same planless route becomes concrete and serial. Maps to AC-1, AC-3, AC-5.
2. Same planless function becomes concrete and serial. Maps to AC-2, AC-3,
   AC-5.
3. Suspected pair defaults serial and only current pair approval unlocks
   parallel. Maps to AC-4 and AC-9.
4. Plan intersections remain authoritative. Maps to AC-6.
5. Unrelated and generic-only briefs remain parallel-eligible. Maps to AC-7 and
   AC-8.
6. Confirmation and final summaries carry typed evidence and disposition. Maps
   to AC-5 and AC-9.
7. Run-work and run-items mirrors preserve the same result. Maps to AC-10.

**Regression suite**:

- `bash scripts/development-workflow/tests/test-workflow-batch-overlap.sh`
- `bash scripts/development-workflow/tests/test-workflow-batch-lanes.sh`
- `bash scripts/development-workflow/tests/test-run-work-router.sh`
- `bash scripts/development-workflow/tests/test-run-bounded-prelude.sh`
- `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`

**Smoke test runbook**:
`docs/testing/workflow/1289-planless-overlap-fallback.smoke-test.md`

---

## Seed Data

No database seed data is required.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Batch item fixtures | Known/unknown file sets, titles, briefs, priorities, creation dates, and next actions | Generated by `test-workflow-batch-overlap.sh` |
| Human decision fixtures | Matching and stale batch/pair/evidence identities | Generated by `test-workflow-batch-overlap.sh` |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      - replace unknown-set warning behavior with fallback classification,
      confirmation, serial handoff, and final-summary evidence.
- [ ] Run-work/run-items skills, commands, and orchestrator agents listed under
      **Files to Modify** - preserve the gate across supported entry points.
- [ ] `scripts/development-workflow/README.md` - add the new helper's purpose,
      input/output contract, and placement before lane dispatch.
- [ ] `AGENTS.md` and `docs/project/*` need no updates because command names,
      repository architecture, and public branch rules do not change.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Generic prose creates false overlap | Medium | Medium | Require typed explicit target cues and maintain negative generic-term tests |
| Heuristic misses an unstated real conflict | Medium | High | Report “no actionable overlap found,” never “independent,” and preserve all existing merge/conflict gates |
| Brief fallback downgrades exact plan evidence | Low | High | Make concrete plan intersections monotonic and test precedence |
| Human approval leaks to another pair or batch | Medium | High | Validate sorted pair ID, batch fingerprint, and evidence hash |
| Transitive pair overlaps dispatch concurrently | Low | High | Emit connected serial groups and test A-B/B-C grouping |
| Provider-specific tracker behavior enters helper | Low | Medium | Require Protocol 90 to supply a provider-neutral current snapshot |
| Mirror surfaces diverge | Medium | Medium | Enumerate every multi-item command/skill/agent and add a live residual query |

---

## Code Samples

No code samples are included. The implementation should establish the helper's
JSON schema alongside its tests rather than copying speculative code from the
plan.

---

## Implementation Order

1. Define the classifier input/output and decision-record schemas in
   `workflow-batch-overlap.sh`.
2. Implement typed target extraction, normalization, exact pair matching,
   suspected relationships, plan precedence, and stable pair ordering.
3. Add parser-risk fixtures and run
   `test-workflow-batch-overlap.sh`.
4. Implement batch/evidence decision validation and transitive serial grouping,
   then add the matching/stale decision tests.
5. Integrate overlap dispositions into `workflow-batch-lanes.sh` and extend its
   harness for priority and hold behavior.
6. Update Protocol 90 evidence gathering, unknown-set handling, confirmation,
   serial resume, and final-summary rules.
7. Update all run-work/run-items command, skill, and orchestrator surfaces
   listed under **Files to Modify**; run a residual query and update metadata
   mirrors only when they duplicate affected wording.
8. Update `scripts/development-workflow/README.md` for the helper.
9. Add the implementation changelog entry under `[Unreleased]` using this exact
   format:
   `- **Add Planless Batch Overlap Fallback** (#1289): Derive explicit brief targets for planless implementation pairs and serialize concrete or unconfirmed suspected overlaps.`
10. Run the classifier, lane, router, bounded-prelude, and shell guard tests.
11. Run ShellCheck and Markdown lint on changed files.
12. Execute
    `docs/testing/workflow/1289-planless-overlap-fallback.smoke-test.md` and
    record the results in the implementation PR.

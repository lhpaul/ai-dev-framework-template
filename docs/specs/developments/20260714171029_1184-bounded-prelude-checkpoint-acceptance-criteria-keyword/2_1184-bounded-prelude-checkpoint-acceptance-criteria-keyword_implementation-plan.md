# Bounded Prelude Acceptance Criteria Checkpoint Parsing - Implementation Plan

**Spec**: [1_1184-bounded-prelude-checkpoint-acceptance-criteria-keyword_specs.md](1_1184-bounded-prelude-checkpoint-acceptance-criteria-keyword_specs.md)
**Smoke test runbook**: [1184-bounded-prelude-checkpoint-acceptance-criteria-keyword.smoke-test.md](../../../testing/workflow/1184-bounded-prelude-checkpoint-acceptance-criteria-keyword.smoke-test.md)

---

## Summary

**Approach**: Replace the broad spec-stage checkpoint regex in
`run-epic-policy-recommender.sh` with section-aware product ambiguity helpers.
The recommender should treat a populated Acceptance Criteria section as normal
issue structure, while still recommending a product checkpoint for unresolved
language, open questions, empty criteria, or placeholder criteria. Add focused
unit coverage for the shared recommender because `/run-item`, `/run-items`, and
`/run-epic` all consume it through the bounded prelude.

**Estimated complexity**: M

**Rationale**: The behavior change is localized to one shell helper and its
tests, but it is parser-risk because it changes structured-text scanning over
issue bodies. The implementation needs careful fixtures for headings,
boundaries, placeholders, and ambiguity lookalikes so the checkpoint signal does
not become too permissive.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `38829f7` |
| Current checkpoint classifier | `nl -ba scripts/development-workflow/run-epic-policy-recommender.sh \| sed -n '229,245p'` | The spec-stage checkpoint condition currently matches `ambiguous`, `unclear`, `tbd`, `open question`, `acceptance criteria`, and `unresolved product` in one text-wide regex. |
| Shared prelude entry point | `sed -n '1,95p' docs/workflow/development-workflow/bounded-run-prelude.md` | `/run-item`, `/run-items`, and `/run-epic` share `run-bounded-prelude.sh`, which delegates checkpoint policy to `run-epic-policy-recommender.sh`. |
| Existing checkpoint tests | `nl -ba scripts/development-workflow/tests/test-run-epic-policy-recommender.sh \| sed -n '267,376p'` | Existing focused tests cover schema, sensitive-change, explicit checkpoint override, text output, and blocked-item cases, but not acceptance-criteria parsing. |
| Existing documentation wording | `sed -n '95,145p' docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | Protocol 95 documents spec/product checkpoints as "unresolved product or acceptance-criteria ambiguity", which should be preserved but clarified after implementation. |

---

## Layer-by-Layer Changes

### Workflow Tooling

- [ ] `scripts/development-workflow/run-epic-policy-recommender.sh` — add jq
      helper definitions that classify product checkpoint signals from each
      item's title, body, type, labels, and integration branch label without
      treating the phrase `acceptance criteria` as a standalone ambiguity
      signal. Maps to AC1, AC2, AC3, AC4, AC5, AC6, AC7, and AC8.
- [ ] Keep the existing checkpoint object shape unchanged:
      `item_number`, `stage`, `domain`, `reason`, `required_human_action`, and
      `satisfaction_state`. This preserves the downstream lifecycle helpers and
      bounded prelude JSON contract. Maps to AC5 and AC6.
- [ ] For incomplete criteria, emit product checkpoint reason text that names
      the concrete problem, such as empty acceptance criteria or placeholder
      acceptance criteria, rather than saying the section heading exists. Maps
      to AC3, AC4, and AC6.

### Tests

- [ ] `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`
      — add focused fixtures for complete, ambiguous, empty, and placeholder
      Backlog issue bodies. Maps to AC1 through AC8.
- [ ] Reuse the existing `recommend_json` and `run_test` helpers so the new
      assertions run in the same read-only harness that already guards against
      unexpected `gh` or `git` calls. Maps to AC5 and AC7.

### Documentation

- [ ] `docs/workflow/development-workflow/bounded-run-prelude.md` — update the
      shared prelude contract to explain that populated Acceptance Criteria
      sections are normal structure, while unresolved, empty, or placeholder
      criteria remain checkpoint-worthy. Maps to AC1, AC3, AC4, AC6, and AC7.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` —
      clarify the human-checkpoint recommendation wording so it distinguishes
      acceptance-criteria ambiguity from a populated Acceptance Criteria
      heading. Maps to AC1, AC2, AC3, AC4, AC6, and AC8.

### Database / Data Layer

- [ ] Not applicable - workflow shell tooling only; no database, migration, or
      seed data changes.

### Backend / API

- [ ] Not applicable - no application API changes.

### Frontend / UI

- [ ] Not applicable - no UI changes.

### Infrastructure / Configuration

- [ ] Not applicable - no environment variables, CI configuration, or
      infrastructure changes.

---

## Parser-Risk Addendum

This plan is parser-risk because it changes structured-text scanning and
regex-style classification in `run-epic-policy-recommender.sh`.

### Edge-Case Enumeration

1. **Populated criteria heading**: a Backlog item body with `## Acceptance
   Criteria` followed by at least one concrete checkbox or bullet must not
   recommend a spec/product checkpoint when no other ambiguity signal exists.
2. **Case and heading variants**: `Acceptance Criteria`, `Acceptance criteria`,
   and `ACCEPTANCE CRITERIA` headings should be handled consistently.
3. **Empty section boundary**: an Acceptance Criteria heading followed only by
   blank lines or the next markdown heading must recommend a spec/product
   checkpoint.
4. **Placeholder criteria**: criteria containing placeholder-only language such
   as `TBD`, `TODO`, `N/A`, `placeholder`, or `to be defined` must recommend a
   spec/product checkpoint.
5. **Real ambiguity marker outside criteria**: a body with populated criteria
   plus `Open question`, `unclear`, `ambiguous`, or `unresolved product` must
   still recommend a spec/product checkpoint.
6. **Negative lookalike**: wording such as "acceptance criteria are listed
   below" or a populated checklist item containing the words "acceptance
   criteria" must not recommend a checkpoint by itself.
7. **Multiple occurrences**: if one Acceptance Criteria section is populated
   but a later criteria section is empty or placeholder-only, the item should
   recommend a checkpoint because incomplete criteria remain.
8. **Non-Backlog stage boundary**: acceptance-criteria parsing should only
   create the spec/product checkpoint on Backlog or spec-stage items, matching
   the existing stage guard.

### Unit Test Mapping

Add automated tests to
`scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`:

| Edge case | Required test |
| --- | --- |
| Populated criteria heading | `complete_acceptance_criteria_has_no_product_checkpoint` |
| Case and heading variants | `acceptance_criteria_heading_case_variants_are_normal_structure` |
| Empty section boundary | `empty_acceptance_criteria_recommends_product_checkpoint` |
| Placeholder criteria | `placeholder_acceptance_criteria_recommends_product_checkpoint` |
| Real ambiguity marker outside criteria | `populated_criteria_with_open_question_still_recommends_checkpoint` |
| Negative lookalike | `acceptance_criteria_phrase_in_complete_body_is_not_checkpoint_signal` |
| Multiple occurrences | `second_empty_acceptance_criteria_section_recommends_checkpoint` |
| Non-Backlog stage boundary | `plan_stage_acceptance_criteria_body_does_not_create_spec_checkpoint` |

### Suppression Semantics

Not applicable - this feature does not add inline or directive suppressions.

---

## Testing Strategy

**Test types**: Unit, workflow smoke, markdown lint, and shell quality checks.

**Key scenarios to test**:

1. Complete downstream Backlog issue shape with problem statement, goal, scope,
   proposed solution, and populated testable acceptance criteria produces no
   spec/product checkpoint solely from the heading. Maps to AC1, AC5, AC6, and
   AC7.
2. Backlog issue with explicit unresolved product language still produces a
   spec/product checkpoint. Maps to AC2, AC6, and AC8.
3. Backlog issue with an empty Acceptance Criteria section produces a
   spec/product checkpoint with incomplete-criteria reason text. Maps to AC3,
   AC6, and AC8.
4. Backlog issue with placeholder acceptance criteria produces a spec/product
   checkpoint with incomplete-criteria reason text. Maps to AC4, AC6, and AC8.
5. Existing schema, sensitive-change, override, blocked-item, and text-output
   tests continue to pass so unrelated checkpoint categories are not regressed.
   Maps to AC2 and AC5.

**Smoke test runbook**:
`docs/testing/workflow/1184-bounded-prelude-checkpoint-acceptance-criteria-keyword.smoke-test.md`

**Regression suite**: The implementation should extend the committed shell test
suite in `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`.

---

## Seed Data

No persistent seed data is required. The implementation should add deterministic
JSON fixtures inside `test-run-epic-policy-recommender.sh` for:

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Scope resolver JSON fixture | Complete downstream Backlog issue with problem statement, goal, scope, proposed solution, and populated criteria | `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh` |
| Scope resolver JSON fixture | Backlog issue with explicit unresolved product marker | `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh` |
| Scope resolver JSON fixture | Backlog issue with empty Acceptance Criteria section | `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh` |
| Scope resolver JSON fixture | Backlog issue with placeholder Acceptance Criteria content | `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh` |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/bounded-run-prelude.md` — describe
      the acceptance-criteria checkpoint distinction in the shared prelude
      contract.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` —
      update the human-checkpoint recommendation wording and examples as needed.
- [ ] `CHANGELOG.md` — implementation PR only; add a `[Unreleased]` `Fixed`
      entry with the literal format below:
      `- **Fix bounded-prelude acceptance criteria checkpoints** (#1184): Stop treating populated Acceptance Criteria sections as standalone product checkpoint signals while preserving checkpoints for unresolved, empty, or placeholder criteria.`
- [ ] `AGENTS.md` — not required; no repository-level command, branching,
      tracker, or workflow convention changes.
- [ ] `docs/project/` — not required; this change affects workflow helper
      behavior, not project architecture, software architecture, or data model.
- [ ] `docs/best-practices/` — not required; no general engineering standard is
      changing.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Section parser misses a valid criteria heading variant | Medium | Medium | Cover heading case variants and markdown boundary behavior in the recommender unit tests. |
| Placeholder detection becomes too broad and flags valid criteria | Medium | Medium | Limit placeholder detection to criteria section contents and concrete placeholder tokens, not arbitrary prose elsewhere in the issue body. |
| Real ambiguity markers are accidentally weakened | Low | High | Keep explicit unresolved-language checks separate from criteria-heading checks and add a populated-criteria plus open-question fixture. |
| Downstream prelude JSON consumers break | Low | High | Preserve checkpoint schema and only change recommendation criteria and reason text. |

---

## Code Samples

No code samples are included. Implementation details should be written directly
in the implementation PR and verified by the focused shell tests.

---

## Implementation Order

1. In `scripts/development-workflow/run-epic-policy-recommender.sh`, split the
   spec/product checkpoint decision into named jq helpers for unresolved
   product language and acceptance-criteria incompleteness. Preserve the
   existing Backlog/spec-stage guard and checkpoint object schema.
2. Implement section-aware Acceptance Criteria detection over item body text.
   Treat populated checkbox or bullet content as complete, and treat a missing,
   empty, or placeholder-only criteria section as incomplete only when the item
   is Backlog or spec-stage.
3. Update product checkpoint reason selection so empty or placeholder criteria
   produce reason text that names incomplete acceptance criteria, while
   unresolved language produces reason text about unresolved product
   requirements.
4. Extend `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`
   with the parser-risk unit tests listed above. Confirm the output by reading
   each `run_test` assertion and verifying the expected checkpoint count,
   stage/domain, and reason text.
5. Update `docs/workflow/development-workflow/bounded-run-prelude.md` and
   `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` so the
   documented checkpoint signal matches the implemented classifier.
6. Update `CHANGELOG.md` under `[Unreleased]` > `Fixed` with:
   `- **Fix bounded-prelude acceptance criteria checkpoints** (#1184): Stop treating populated Acceptance Criteria sections as standalone product checkpoint signals while preserving checkpoints for unresolved, empty, or placeholder criteria.`
7. Run focused verification:
   `bash scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`.
8. Run workflow shell quality checks for the changed shell helper and test:
   `shellcheck scripts/development-workflow/run-epic-policy-recommender.sh scripts/development-workflow/tests/test-run-epic-policy-recommender.sh` and `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`.
9. Run markdown checks for changed docs and runbook:
   `npx markdownlint-cli2 "docs/workflow/development-workflow/bounded-run-prelude.md" "docs/workflow/development-workflow/protocols/95-run-epic-protocol.md" "docs/testing/workflow/1184-bounded-prelude-checkpoint-acceptance-criteria-keyword.smoke-test.md"`.
10. Execute the smoke test runbook and attach the focused command output to the
    implementation PR evidence before requesting review.

---

## Residual Verification Strategy

This is pattern-sensitive parser work, so implementation readiness should cite
the focused unit-test output and the exact recommender fixtures added for
complete, unresolved, empty, and placeholder criteria. Residual evidence should
also include a short before/after note confirming that `/run-item`, `/run-items`,
and `/run-epic` still consume the same shared recommender through
`run-bounded-prelude.sh`; no separate command-specific classifier should remain
untested.

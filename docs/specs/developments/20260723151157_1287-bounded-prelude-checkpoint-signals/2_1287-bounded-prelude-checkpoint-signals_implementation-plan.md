# Bounded Prelude Data-Model Checkpoint Signals — Implementation Plan

**Spec**: [Bounded Prelude Data-Model Checkpoint Signals](1_1287-bounded-prelude-checkpoint-signals_specs.md)
**Smoke test runbook**: [Bounded Prelude Data-Model Checkpoint Signals](../../../testing/workflow/1287-bounded-prelude-checkpoint-signals.smoke-test.md)

---

## Summary

**Approach**: Replace the recommender's combined free-text regular expression
with source-aware jq helpers that collect strong data-model signals from
explicit migration labels, action-oriented title phrases, and
migration-specific body phrases. Keep the checkpoint record schema and
human-selected override path unchanged, but build the technical checkpoint
reason from the exact matched signals so the shared bounded prelude remains
explainable for `/run-item`, `/run-items`, and `/run-epic`.

**Estimated complexity**: M

**Rationale**: The production edit is localized to one shell helper, but its jq
structured-text classifier has a high false-positive cost. The change therefore
needs explicit boundary semantics, a broad negative/positive fixture matrix,
shared-consumer verification, documentation parity, and shell quality checks.

**Dependencies**: None. Spec PR
[#1316](https://github.com/lhpaul/ai-dev-framework-template/pull/1316) is
merged to `develop`; no other work item is required first.

**Design assets**: None discovered. The issue has no `## Design assets` section,
no tracker attachment or linked visual file, and the development folder has no
`assets/` directory. This workflow-only change needs no fidelity step.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `21f23e3` |
| Existing data-model classifier | `rg -n 'schema\|migration\|database\|data\[ -\]\?model\|\\bsql\\b\|persistent data' scripts/development-workflow/run-epic-policy-recommender.sh` | One combined body/title/type/label match in `recommend_checkpoints_for_item`; it uses `item_signal_text` and cannot attribute a source-specific reason. |
| Existing fixed reason | `rg -n -F 'issue signals database schema, migration, or persistent data-model changes' scripts/development-workflow` | The fixed reason appears in the recommender and its override fixture only. |
| Shared consumer path | `rg -n 'run-epic-policy-recommender\.sh' scripts/development-workflow/run-bounded-prelude.sh docs/workflow/development-workflow/bounded-run-prelude.md docs/workflow/development-workflow/protocols/95-run-epic-protocol.md .agents/skills/run-epic/SKILL.md` | `run-bounded-prelude.sh` invokes the recommender once; the bounded-prelude contract documents that single policy path for all three bounded commands. |
| Current recommender suite | `rg -n '^run_test "' scripts/development-workflow/tests/test-run-epic-policy-recommender.sh` | 55 existing assertions, including positive schema, human override/waiver, audit-shape, sensitive-change, and blocked-item coverage. |
| Spec ordering gate | `gh pr list --state merged --search '1287' --json number,headRefName,baseRefName,mergedAt` | Spec PR #1316 is merged from `spec/1287-bounded-prelude-checkpoint-signals` into `develop`. |
| Existing development artifacts | `find docs/specs/developments/20260723151157_1287-bounded-prelude-checkpoint-signals -maxdepth 2 -type f -print` | Only the approved spec existed before this plan; there are no implementation or design artifacts to reuse. |

---

## Architecture and Decision Boundary

### Decision 1: Preserve one shared classifier

`scripts/development-workflow/run-epic-policy-recommender.sh` remains the only
checkpoint classifier. `run-bounded-prelude.sh` continues to invoke it and
expose its result without adding command-specific rules. This preserves the
one-policy-path mechanism documented in
`docs/workflow/development-workflow/bounded-run-prelude.md` and ensures the same
decision boundary reaches `/run-item`, `/run-items`, and `/run-epic` (AC8).

### Decision 2: Collect typed signals before creating the checkpoint

Add jq helpers that return an ordered, de-duplicated array of display-ready
signal descriptions for one item:

- **Migration label**: match normalized, explicit labels from the bounded
  allowlist `migration`, `database-migration`, `schema-migration`,
  `db-migration`, `schema-change`, and `data-model-change`. Preserve the
  original label text in the reason. A generic label such as `database` is not
  sufficient by itself.
- **Title intent**: match either an explicit migration noun phrase
  (`database migration`, `schema migration`, `data-model migration`, or
  `data model migration`) or an
  action-first phrase in which `add`, `create`, `alter`, `change`, `update`,
  `modify`, `rename`, `drop`, `remove`, or `migrate` targets a schema, table,
  column, database, data model, or persistent model. Requiring the action first
  prevents titles discussing a "false data-model change signal" from being
  interpreted as proposing that change. Preserve the matched title fragment in
  the reason.
- **Body phrase**: match the migration-specific phrases `CREATE TABLE`,
  `ALTER TABLE`, `new column`, and `database migration` case-insensitively with
  word boundaries and flexible internal whitespace. Preserve the matched body
  fragment in the reason.

The checkpoint is recommended only when this array is non-empty. Generic body
terms (`schema`, `database`, `SQL`, `persistent data`, `data model`, or
PostgREST response/schema wording) never enter the array on their own (AC1,
AC2, AC6, AC9).

### Decision 3: Explain positives through the existing `reason` field

Keep the checkpoint keys and object shape unchanged:
`item_number`, `stage`, `domain`, `reason`, `required_human_action`, and
`satisfaction_state`. Build `reason` as:

`data-model checkpoint matched <signal>; <signal>; ...`

Each signal includes its source and exact original match, for example
`label 'database-migration'`, `title phrase 'Add customer schema column'`, or
`body phrase 'ALTER TABLE'`. Ordered de-duplication makes output deterministic;
the array-to-string join is the mechanism that reports every match while
guaranteeing at least one exact signal for every positive checkpoint (AC3-AC5).
No new checkpoint field is needed, so lifecycle, waiver, and audit consumers
keep their current schema (AC7).

### Decision 4: Human control remains a post-recommendation overlay

Do not modify `normalize_checkpoint`, `selected_checkpoints`,
`effective_checkpoints`, `checkpoint_matches`, or checkpoint export/audit
fields. Those functions continue to merge explicit selected or waived records
by item/stage/domain after recommendation. Existing tests will assert the
explicit override reason, satisfaction state, waiver rationale, and
`checkpointPolicy` audit views remain authoritative (AC7).

---

## Workflow Decision-Gate Consistency Matrix

This plan changes a complex workflow decision gate because checkpoint output
depends on several input sources and produces different operator next actions.

| Gate inputs | Allowed outcome | Required next action | Evidence/reason | Mirror surfaces | Example coverage |
| --- | --- | --- | --- | --- | --- |
| Explicit bounded migration label matches | Add `plan/technical` checkpoint | Human satisfies or waives before implementation | Exact original label in `reason` | Recommender JSON/text, bounded-prelude confirmation summary, Protocol 95 | `database-migration` positive; `database` generic-label negative |
| Action-oriented migration/schema title matches | Add `plan/technical` checkpoint | Human satisfies or waives before implementation | Exact matched title fragment in `reason` | Same shared surfaces | `Add users table database migration`; title discussion of a false signal remains negative |
| Body contains `CREATE TABLE`, `ALTER TABLE`, `new column`, or `database migration` | Add `plan/technical` checkpoint | Human satisfies or waives before implementation | Exact matched body phrase in `reason` | Same shared surfaces | One positive per required phrase plus case/whitespace variants |
| Body has only generic data-adjacent terms | No data-model checkpoint from those terms | Continue the otherwise-approved path and evaluate other stops | No invented data-model reason | Same shared surfaces | #1865 resilient-read fixture; separate `schema`, `database`, `SQL`, `persistent data`, and lookalike cases |
| Multiple strong signals match | Add one de-duplicated `plan/technical` checkpoint | Human satisfies or waives once | Deterministic joined reason lists all exact signals | Same shared surfaces | Label + title + body fixture |
| Explicit checkpoint override, satisfaction, or waiver exists | Preserve human-selected checkpoint state | Consume the selected state through existing lifecycle/audit gates | Existing selected/effective policy and rationale fields | Recommender, lifecycle label/comment, delegated gate, audit trail | Existing waiver and audit-shape tests plus explicit reason-preservation assertion |
| No data-model signal but another checkpoint signal matches | Preserve the unrelated checkpoint | Follow that checkpoint's existing required action | Existing product/security/tradeoff reason | Shared recommender and downstream lifecycle | Existing product and sensitive-change regression tests |
| Changed-file evidence is unavailable | Classification still completes from pre-implementation metadata | Do not inspect or require implementation diff | Fixture-only recommender execution | All bounded commands before mutation | Test harness continues to forbid `git`/`gh` calls |

---

## Layer-by-Layer Changes

### Workflow Tooling

- [ ] `scripts/development-workflow/run-epic-policy-recommender.sh` — replace
      the broad data-model regular expression with source-aware jq helpers for
      explicit labels, action-oriented title intent, and migration-specific
      body phrases. Build the existing checkpoint `reason` from the exact
      ordered signal list while leaving override and audit logic unchanged.
      Maps to AC1 through AC10.
- [ ] Do not modify `scripts/development-workflow/run-bounded-prelude.sh`; its
      single invocation of the recommender is the enforcement mechanism for
      consistent `/run-item`, `/run-items`, and `/run-epic` behavior. Verify
      this path with the live search and command-variant tests. Maps to AC8 and
      AC9.

### Tests

- [ ] `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`
      — add deterministic fixtures and assertions for all parser edge cases,
      exact signal reasons, multiple-signal ordering/de-duplication,
      shared-command variants, and preserved overrides/audit behavior. Reuse
      `write_fixture`, `recommend_json`, and `run_test`; the harness's mocked
      `git` and `gh` binaries prove classification does not require changed-file
      evidence. Maps to AC1 through AC10.

### Documentation

- [ ] `docs/workflow/development-workflow/bounded-run-prelude.md` — document
      the source-aware data-model signal boundary, exact reason visibility, and
      the fact that incidental body vocabulary is insufficient. Maps to AC1,
      AC3-AC6, AC8, and AC9.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` —
      replace the broad "wording" description and database/schema example with
      the same label/title/body signal rules and exact-reason expectation. Maps
      to AC1 and AC3-AC8.
- [ ] `CHANGELOG.md` — implementation PR only; add the `[Unreleased]` `Fixed`
      entry listed under **Documentation Updates**. The plan PR itself remains
      exempt.

### Database / Data Layer

- [ ] Not applicable — the feature classifies pre-implementation metadata and
      does not add a database, schema, migration, persistent record, or seed.

### Backend / API

- [ ] Not applicable — no application endpoint or external API contract
      changes. The recommender's existing JSON checkpoint schema is preserved.

### Shared Packages / Libraries

- [ ] Not applicable — no package or dependency is added.

### Frontend / UI

- [ ] Not applicable — this is shell/jq workflow tooling with text and JSON
      output only.

### Infrastructure / Configuration

- [ ] Not applicable — no environment variable, CI workflow, guardrails
      configuration, or infrastructure resource changes.

---

## Parser-Risk Addendum

This plan is parser-risk because it replaces regex-heavy structured-text
classification inside a workflow shell helper.

### Edge-Case Enumeration

1. **Generic body terms**: each of `schema`, `database`, `SQL`, `persistent
   data`, and `data model` in otherwise non-migration body prose produces no
   data-model checkpoint.
2. **Downstream resilient-read regression**: a PostgREST resilient-read issue
   describing raw responses, transient error shapes, database-facing
   responses, and schema-shaped payloads remains negative.
3. **Generic label negative**: label `database` without another strong signal
   remains negative.
4. **Explicit migration labels**: every allowlisted label matches regardless of
   case normalization, and the reason preserves the original label.
5. **Action-oriented title**: action-first migration/schema intent matches;
   a title that merely discusses the words "schema" or "false data-model change
   signal" does not.
6. **Migration noun title**: `database migration`, `schema migration`, and
   `data-model migration` title phrases match with word boundaries.
7. **Required body phrases**: `CREATE TABLE`, `ALTER TABLE`, `new column`, and
   `database migration` each match case-insensitively and report the actual
   matched fragment.
8. **Boundary-character lookalikes**: `CREATE TABLETOP`, `ALTER TABLET`, `new
   columnist`, and `database migration-guide` do not match the required body
   phrases.
9. **Multiple occurrences**: repeated identical phrases are de-duplicated;
   different label/title/body signals are reported in deterministic source
   order in one checkpoint reason.
10. **Unrelated checkpoints**: product ambiguity, sensitive/auth changes, and
    blocked-item eligibility retain existing outcomes when the data-model
    classifier changes.
11. **Human-selected state**: explicit override, satisfaction/waiver rationale,
    and audit policy views preserve their current behavior even though the
    recommended reason text is now dynamic.
12. **Command variants**: the same fixture evaluated with `/run-item`,
    `/run-items`, and `/run-epic` original-command values returns the same
    data-model checkpoint decision and exact reason.

### Unit Test Mapping

All tests belong in
`scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`.

| Edge case | Required automated tests |
| --- | --- |
| Generic body terms | `generic_data_body_terms_do_not_checkpoint` |
| Resilient-read regression | `resilient_read_body_has_no_data_model_checkpoint` |
| Generic label negative | `generic_database_label_does_not_checkpoint` |
| Explicit migration labels | `explicit_migration_labels_checkpoint_with_exact_reason` |
| Action-oriented title | `action_oriented_schema_title_checkpoints`; `false_signal_title_does_not_checkpoint` |
| Migration noun title | `migration_title_phrases_checkpoint` |
| Required body phrases | `migration_body_phrases_checkpoint_with_exact_reason` |
| Boundary lookalikes | `migration_phrase_lookalikes_do_not_checkpoint` |
| Multiple occurrences | `data_model_signals_are_ordered_and_deduplicated` |
| Unrelated checkpoints | Existing product, sensitive, and blocked-item tests remain green; add a mixed unrelated-checkpoint fixture if current coverage cannot isolate the assertion. |
| Human-selected state | Existing `explicit_checkpoint_override_source`, `waived_checkpoint_preserved`, and `checkpoint_policy_audit_fields_present`; add `satisfied_checkpoint_preserved` plus assertions that explicit reasons and rationales are preserved. |
| Command variants | `bounded_command_variants_share_data_model_classifier` |

### Suppression Semantics

Not applicable — this feature introduces no inline or directive suppression.
Negative outcomes follow from the positive-signal boundary, not a suppression
list.

---

## Testing Strategy

**Test types**: Unit, workflow smoke, shell static analysis, workflow shell
guard, and markdown lint.

**Key scenarios to test**:

1. Generic body-only data terms and the #1865-inspired resilient-read fixture
   produce no data-model checkpoint (AC1, AC2, AC6).
2. Every allowlisted migration label produces a `plan/technical` checkpoint
   whose reason names the original label (AC3, AC6).
3. Action-oriented title and explicit migration noun title phrases produce a
   checkpoint whose reason names the title match (AC4, AC6).
4. Each required migration-specific body phrase produces a checkpoint whose
   reason names that phrase, while word-boundary lookalikes remain negative
   (AC5, AC6).
5. Multiple strong signals yield one stable checkpoint with a deterministic,
   de-duplicated exact-signal reason (AC3-AC6).
6. Explicit override, satisfied state, waiver, rationale, audit, unrelated
   checkpoint, and blocked-item tests remain green; downstream lifecycle and
   audit-trail suites also pass (AC7, AC10).
7. `/run-item`, `/run-items`, and `/run-epic` command variants receive the same
   decision from the shared recommender without any changed-file lookup (AC8,
   AC9).

**Smoke test runbook**:
`docs/testing/workflow/1287-bounded-prelude-checkpoint-signals.smoke-test.md`

**Regression suite**: Extend the committed shell suite in
`scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`; do not
rely on smoke-only coverage for this parser-risk change.

---

## Seed Data

No persistent seed data is required. Tests create deterministic local JSON
scope fixtures.

| Entity | Values / scenario | File |
| --- | --- | --- |
| Negative scope fixture | #1865-inspired resilient-read brief plus generic body terms and generic `database` label | `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh` |
| Label signal fixtures | One item per explicit migration-label value, including a mixed-case original label | `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh` |
| Title signal fixtures | Action-first schema changes, migration noun phrases, and false-signal discussion title | `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh` |
| Body signal fixtures | Required migration phrases, whitespace/case variants, and boundary lookalikes | `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh` |
| Multiple-signal fixture | Repeated body phrase plus distinct label and title signals | `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh` |
| Human-control fixture | Explicit waived checkpoint with rationale and custom reason | `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh` |
| Human-control fixture | Explicit satisfied checkpoint with actor/evidence metadata | `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh` |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/bounded-run-prelude.md` — document
      positive, source-aware data-model signals and exact matched-signal output
      on the shared policy path.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` —
      align the checkpoint recommendation list and examples with the
      label/title/body decision boundary.
- [ ] `CHANGELOG.md` — implementation PR only; add under `[Unreleased]` >
      `Fixed`:
      `- **Fix bounded-prelude data-model checkpoint signals** (#1287): Stop incidental data-adjacent issue-body terms from creating technical checkpoints while preserving explainable checkpoints for explicit migration and schema-change evidence.`
- [ ] `AGENTS.md` — not required; command, branching, tracker, and PR
      conventions do not change.
- [ ] `docs/project/` — not required; this is workflow classifier behavior, not
      product repository architecture, software architecture, or a real data
      model.
- [ ] `docs/best-practices/` — not required; no general engineering standard is
      added or modified.
- [ ] `.claude/agents/`, `.cursor/agents/`, `.agents/skills/`, and
      `.codex/skills/` — not required; all bounded entry points already delegate
      checkpoint classification to the shared prelude/recommender and need no
      new agent-local rule.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Title-intent regex still interprets meta-discussion as a schema change | Medium | High | Use action-first matching plus explicit migration noun phrases; cover the #1287-style false-signal title as a negative boundary fixture. |
| Narrowing the classifier loses a genuine migration checkpoint | Medium | High | Test every allowed label, title form, and required body phrase; keep a multiple-signal positive fixture. |
| Exact reason strings become unstable or duplicate matches | Medium | Medium | Collect typed signals, de-duplicate before joining, and assert deterministic source order. |
| Existing selected/waived checkpoint behavior breaks when recommended reasons change | Low | High | Preserve checkpoint schema and merge helpers; keep current override/audit tests and assert the explicit reason survives. |
| Shared bounded commands drift into different behavior | Low | High | Keep the classifier only in the recommender, verify the one invocation in `run-bounded-prelude.sh`, and run command-variant assertions against the same fixture. |
| Regex implementation becomes hard to review | Medium | Medium | Use named jq helpers, simple source-specific patterns, concrete fixture names, ShellCheck, and the workflow shell guard. |

---

## Code Samples

No code samples are included. The implementation should express the decisions
above through named jq helpers and focused fixtures rather than copying
production-ready code from the plan.

---

## Implementation Order

1. In `scripts/development-workflow/run-epic-policy-recommender.sh`, add named
   jq helpers that normalize and collect migration-label, title-intent, and
   migration-body-phrase signals. Keep each source-specific pattern separate
   and return display-ready exact matches.
2. Replace the broad data-model `item_signal_text` test with a non-empty signal
   array check. Build one `plan/technical` checkpoint using the deterministic
   de-duplicated reason described in Decision 3; leave checkpoint selection,
   override, waiver, and audit functions unchanged.
3. Extend
   `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh` with
   every parser-risk test from the Unit Test Mapping. Run the focused suite and
   confirm all existing and new assertions pass.
4. Confirm the command-variant tests use the same fixture and recommender for
   `/run-item`, `/run-items`, and `/run-epic`, and that mocked `git`/`gh`
   invocations remain absent. Read the output to verify identical checkpoint
   decisions and reasons.
5. Update `docs/workflow/development-workflow/bounded-run-prelude.md` and
   `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` with
   the matrix-consistent signal descriptions and exact-reason behavior.
6. Update `CHANGELOG.md` under `[Unreleased]` > `Fixed` with:
   `- **Fix bounded-prelude data-model checkpoint signals** (#1287): Stop incidental data-adjacent issue-body terms from creating technical checkpoints while preserving explainable checkpoints for explicit migration and schema-change evidence.`
7. Run focused behavior verification:
   `bash scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`,
   `bash scripts/development-workflow/tests/test-run-epic-checkpoint-lifecycle.sh`,
   and
   `bash scripts/development-workflow/tests/test-run-epic-audit-trail.sh`.
8. Run shell checks:
   `shellcheck scripts/development-workflow/run-epic-policy-recommender.sh scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`
   and
   `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`.
9. Run markdown checks for the changed workflow docs, CHANGELOG, and smoke
   runbook. Confirm the output is clean rather than relying on a hard-coded
   file count.
10. Execute
    `docs/testing/workflow/1287-bounded-prelude-checkpoint-signals.smoke-test.md`
    and attach focused test, exact-reason, shared-consumer, ShellCheck, shell
    guard, and markdown-lint evidence to the implementation PR.

---

## Residual Verification Strategy

Implementation readiness must include:

- the full focused recommender test summary;
- the exact negative and positive fixture names added for every parser edge;
- representative JSON evidence for a no-checkpoint resilient-read item, a
  positive exact-signal reason, and a multiple-signal de-duplicated reason;
- the live `rg` result showing `run-bounded-prelude.sh` remains the single
  recommender invocation used by all bounded commands; and
- a residual search for the removed broad data-model regex and fixed generic
  reason.

The implementation should classify any remaining broad regex or generic reason
as either completed in scope or explicitly justified. Silent prose deferral is
not sufficient for this pattern-sensitive change.

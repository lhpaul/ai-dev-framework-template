# Smoke Test Runbook: Bounded Prelude Data-Model Checkpoint Signals

**Feature**: Bounded Prelude Data-Model Checkpoint Signals
**Spec**: [Bounded Prelude Data-Model Checkpoint Signals](../../specs/developments/20260723151157_1287-bounded-prelude-checkpoint-signals/1_1287-bounded-prelude-checkpoint-signals_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Use a clean checkout of the implementation branch.
- [ ] `bash`, `jq`, `rg`, `shellcheck`, Python 3, and repository Node
      dependencies are available.
- [ ] No real tracker, branch, PR, checkpoint, or audit mutation is expected;
      recommender tests use local JSON fixtures and mocked `git`/`gh` commands.

---

## Test Data

| Item | Value |
| --- | --- |
| Resilient-read negative fixture | Non-data-model PostgREST work that mentions raw responses, transient error shapes, database-facing responses, and schema-shaped payloads |
| Generic body-term fixtures | `schema`, `database`, `SQL`, `persistent data`, and `data model` used without migration intent |
| Migration labels | `migration`, `database-migration`, `schema-migration`, `db-migration`, `schema-change`, and `data-model-change` |
| Title positives | Action-first schema/table/column intent and explicit database/schema/data-model migration phrases |
| Body positives | `CREATE TABLE`, `ALTER TABLE`, `new column`, and `database migration` |
| Boundary negatives | `CREATE TABLETOP`, `ALTER TABLET`, `new columnist`, and `database migration-guide` |
| Shared helper | `scripts/development-workflow/run-epic-policy-recommender.sh` |

---

## Smoke Test Steps

### Step 1: Run the Focused Recommender Suite

**Maps to**: AC1-AC10

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-run-epic-policy-recommender.sh
   ```

2. Confirm the suite exits successfully.
3. Confirm the output includes the new resilient-read, generic-term, label,
   title, body-phrase, exact-reason, override/audit, and command-variant cases.

**Expected result**: All existing and new assertions pass, with no real `git`
or `gh` call recorded by the fixture harness.

### Step 2: Verify Incidental Body Terms Stay Negative

**Maps to**: AC1, AC2, AC6

1. Inspect the generic body-term and resilient-read fixtures.
2. Confirm the resilient-read title and body describe error classification and
   response shapes, not a migration.
3. Confirm each assertion counts zero `plan/technical` data-model checkpoints.
4. Confirm a generic `database` label also remains negative without another
   strong signal.

**Expected result**: Incidental `schema`, `database`, `SQL`, `persistent data`,
`data model`, and PostgREST wording do not create a data-model checkpoint.

### Step 3: Verify Explicit Migration Labels

**Maps to**: AC3, AC6

1. Inspect the migration-label fixtures.
2. Confirm each allowlisted label produces one `plan/technical` checkpoint.
3. Confirm the reason contains the source `label` and the exact original label
   text, including preserved case where the fixture varies case.

**Expected result**: Explicit migration/data-model labels remain protected and
are explainable; generic `database` alone remains negative.

### Step 4: Verify Title-Level Intent

**Maps to**: AC4, AC6

1. Inspect action-first title fixtures for schema, table, column, database, and
   data-model changes.
2. Inspect explicit database/schema/data-model migration noun-phrase fixtures.
3. Confirm each positive reason contains the exact matched title fragment.
4. Inspect the false-signal discussion title fixture and confirm it expects no
   data-model checkpoint.

**Expected result**: Genuine title-level migration/schema-change intent creates
an explainable checkpoint; meta-discussion of a false signal does not.

### Step 5: Verify Migration-Specific Body Phrases

**Maps to**: AC5, AC6

1. Inspect fixtures for `CREATE TABLE`, `ALTER TABLE`, `new column`, and
   `database migration`.
2. Confirm case and internal-whitespace variants match.
3. Confirm each reason names the actual matched body phrase.
4. Confirm boundary lookalikes such as `CREATE TABLETOP`, `ALTER TABLET`, `new
   columnist`, and `database migration-guide` remain negative.

**Expected result**: Every required migration phrase is positive with an exact
reason, and similar non-migration tokens do not match.

### Step 6: Verify Multiple-Signal Explainability

**Maps to**: AC3, AC4, AC5, AC6

1. Inspect the fixture containing a migration label, title intent, and repeated
   body phrase.
2. Confirm only one `plan/technical` checkpoint is produced.
3. Confirm its reason lists distinct signals in label, title, then body order.
4. Confirm the repeated body phrase appears only once in the reason.

**Expected result**: Multiple positives yield one deterministic,
de-duplicated checkpoint reason that exposes all exact matches.

### Step 7: Verify Human Overrides and Audit Behavior

**Maps to**: AC7

1. Confirm the existing explicit override and waiver fixtures still pass.
2. Confirm an explicit satisfied checkpoint preserves its actor/evidence
   metadata in selected/effective policy.
3. Confirm a waived record without `waiver_rationale` is still rejected.
4. Confirm the explicit record's custom reason, waiver state, and rationale are
   preserved in selected/effective policy.
5. Confirm `checkpointPolicy.recommended`, `.selected`, and `.effective`
   remain present for audit evidence.
6. Run:

   ```bash
   bash scripts/development-workflow/tests/test-run-epic-checkpoint-lifecycle.sh
   bash scripts/development-workflow/tests/test-run-epic-audit-trail.sh
   ```

7. Confirm both downstream suites pass.

**Expected result**: The classifier changes recommendations only; human
selection, satisfaction/waiver, rationale, and audit authority remain unchanged.

### Step 8: Verify Shared Bounded-Command Behavior

**Maps to**: AC8, AC9

1. Inspect the command-variant test that evaluates the same scope fixture with
   `/run-item`, `/run-items`, and `/run-epic` original-command values.
2. Confirm all three outputs have the same checkpoint count, stage/domain, and
   exact reason.
3. Run:

   ```bash
   rg -n 'run-epic-policy-recommender\.sh' \
     scripts/development-workflow/run-bounded-prelude.sh \
     docs/workflow/development-workflow/bounded-run-prelude.md
   ```

4. Confirm `run-bounded-prelude.sh` still has one recommender invocation and no
   command-specific data-model classifier exists.

**Expected result**: All bounded commands share the recommender decision
without requiring an implementation diff or changed-file query.

### Step 9: Verify Unrelated Guardrails Remain Independent

**Maps to**: AC10

1. Confirm existing product ambiguity and sensitive/auth checkpoint cases pass.
2. Confirm blocked items still skip recommendation as before.
3. Confirm the generic data-model negative fixture does not remove a separate
   checkpoint when another domain genuinely applies.

**Expected result**: Narrowing data-model signals does not suppress product,
security, tradeoff, dependency, or other workflow stops.

### Step 10: Run Static and Documentation Checks

**Maps to**: AC1-AC10

1. Run:

   ```bash
   shellcheck \
     scripts/development-workflow/run-epic-policy-recommender.sh \
     scripts/development-workflow/tests/test-run-epic-policy-recommender.sh
   ```

2. Run:

   ```bash
   python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop
   ```

3. Run markdown lint for the changed workflow docs, CHANGELOG, and this
   runbook. Confirm the command reports no violations.

**Expected result**: ShellCheck, the workflow shell guard, and markdown lint
all pass.

### Last Step: Validate & Shut Down

- Verify every assertion below has evidence.
- No application server or persistent data requires cleanup.

---

## Assertions Checklist

- [ ] Incidental data-adjacent body terms do not create a data-model
      checkpoint. AC1
- [ ] The #1865-inspired resilient-read regression remains checkpoint-free.
      AC2
- [ ] Explicit migration labels create a checkpoint with the exact label in
      the reason. AC3
- [ ] Title-level migration/schema-change intent creates a checkpoint with the
      exact title match in the reason. AC4
- [ ] All four required migration-specific body phrases create explainable
      checkpoints. AC5
- [ ] Genuine positives remain checkpointed after generic matching is removed.
      AC6
- [ ] Human override, satisfaction/waiver, rationale, and audit behavior remain
      unchanged. AC7
- [ ] `/run-item`, `/run-items`, and `/run-epic` use the same shared
      classification. AC8
- [ ] Classification requires no changed-file evidence or implementation diff.
      AC9
- [ ] Unrelated checkpoints and guardrail stops remain independent. AC10

---

## Seed Data Reference

| Entity | Scenario | How to load |
| --- | --- | --- |
| Local JSON fixture | Resilient-read and generic-term negatives | Created inside `test-run-epic-policy-recommender.sh` |
| Local JSON fixture | Migration-label positives | Created inside `test-run-epic-policy-recommender.sh` |
| Local JSON fixture | Title and body-phrase positives/negatives | Created inside `test-run-epic-policy-recommender.sh` |
| Local JSON fixture | Multiple signals and human override | Created inside `test-run-epic-policy-recommender.sh` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Focused suite fails before assertions | `jq` or another local shell dependency is missing | Install the repository development dependency and rerun the focused suite. |
| Resilient-read fixture still checkpoints | Generic item text is still used by the data-model branch | Ensure only the source-aware strong-signal array controls that branch. |
| Positive reason is generic | The checkpoint still uses a fixed reason string | Build `reason` from the matched label/title/body signal descriptions. |
| Boundary lookalike matches | Word boundaries or phrase separators are too permissive | Tighten the source-specific matcher and add the observed token as a focused negative fixture. |
| Human waiver changes unexpectedly | Recommendation refactor modified selection/normalization helpers | Revert changes outside signal collection and restore existing override/audit functions. |
| Command variants differ | A command-specific classifier was introduced | Remove the duplicate path and route every bounded command through the shared recommender. |

---

## Known Limitations

- The classifier intentionally uses only metadata available before
  implementation. It does not inspect migration files or implementation diffs.
- The migration-label allowlist is bounded. A downstream repository that uses a
  different label name must add it deliberately with a matching fixture rather
  than restoring broad substring matching.

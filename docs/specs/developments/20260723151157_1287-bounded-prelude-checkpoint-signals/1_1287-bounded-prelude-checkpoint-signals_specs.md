# Bounded Prelude Data-Model Checkpoint Signals - Spec

---

## Overview

Workflow operators need the bounded prelude to reserve data-model checkpoints
for work that actually signals a database migration or persistent data-model
change. Incidental mentions of terms such as "schema", "database", "SQL", or
"persistent data" are common in error-handling and infrastructure briefs and
must not create a technical checkpoint by themselves.

This feature replaces broad free-text matching with structured, explainable
signals available before implementation begins. Strong title, label, or
migration-specific phrase evidence continues to require a checkpoint, while
the prelude reports the exact signal behind every positive classification.
Existing human overrides, checkpoint waivers, and audit behavior remain
unchanged.

## Brief Objective List

Derived from issue #1287 and its backlog-triage refinement:

1. Prevent incidental body mentions of `schema`, `database`, `SQL`, or
   `persistent data` from independently creating a data-model checkpoint.
2. Require stronger structural evidence, such as an explicit migration label,
   title-level migration or schema intent, or a migration-specific phrase.
3. Make every positive checkpoint classification explainable by reporting the
   exact matched signal.
4. Add regression coverage for the downstream resilient-read example that
   should not create a checkpoint.
5. Preserve positive checkpoint behavior for genuine migration and persistent
   data-model work.
6. Preserve explicit human checkpoint overrides, waivers, and audit behavior.
7. Apply the behavior consistently anywhere the shared bounded prelude or
   checkpoint recommender is used.
8. Reduce unnecessary checkpoint pauses that add workflow overhead and expose
   operators to avoidable resume-boundary risk.
9. Recognize that changed-file evidence is unavailable before implementation
   and must not be the primary prelude classifier.

---

## Use Cases

### Use Case 1: Start an issue with incidental data-adjacent wording

**Actor**: Workflow operator starting an approved work item or batch.
**Preconditions**: The issue brief describes non-data-model work but mentions
data-adjacent terms in explanatory body text, such as an error shape returned
by a database-facing service.

**Steps**:

1. The operator invokes or approves a bounded workflow run.
2. The prelude evaluates the issue title, labels, and brief.
3. It finds incidental body wording but no migration label, title-level
   migration or schema intent, or migration-specific phrase.
4. The prelude does not create a data-model checkpoint from those incidental
   terms.
5. The item follows its otherwise-approved workflow path.

**Postconditions**: The item can advance without a false technical checkpoint.

**Information shown**:

- The normal bounded-prelude policy and checkpoint summary.
- No data-model checkpoint reason based solely on incidental body terms.

**Actions available**:

- Continue the approved workflow run.
- Stop for any separate checkpoint or guardrail that genuinely applies.

**Considerations**:

- The resilient-read example from downstream issue #1865 is the required
  regression scenario: describing raw responses and transient error shapes
  must not imply a database change.

### Use Case 2: Stop for genuine migration or data-model intent

**Actor**: Workflow operator starting an item that changes persistent data.
**Preconditions**: The issue has at least one strong signal, such as an
explicit migration label, migration or schema intent in the title, or a
migration-specific phrase such as `CREATE TABLE`, `ALTER TABLE`, `new column`,
or `database migration`.

**Steps**:

1. The operator invokes or approves a bounded workflow run.
2. The prelude evaluates the issue's structured signals.
3. A strong signal matches.
4. The prelude creates the applicable technical checkpoint.
5. The checkpoint summary names the exact signal and required human action.
6. The workflow waits for the checkpoint to be satisfied or waived before the
   guarded stage proceeds.

**Postconditions**: Genuine data-model work remains human-visible at the
technical checkpoint.

**Information shown**:

- The affected item and checkpoint stage.
- The exact label, title intent, or migration-specific phrase that matched.
- The human action required to satisfy or waive the checkpoint.

**Actions available**:

- Review and satisfy the checkpoint.
- Explicitly waive it with a rationale.
- Correct an inaccurate issue title, label, or brief and re-run the prelude.

**Considerations**:

- A positive result must be attributable to at least one strong signal; generic
  data-adjacent vocabulary is insufficient.
- Multiple matching signals may be reported together, but one exact matched
  signal is the minimum explainability requirement.

### Use Case 3: Preserve explicit human checkpoint control

**Actor**: Workflow operator reviewing a bounded-prelude recommendation.
**Preconditions**: The prelude has recommended a checkpoint, or the operator
has supplied an explicit checkpoint override or waiver.

**Steps**:

1. The operator reviews the recommendation and its matched-signal reason.
2. The operator accepts, satisfies, or waives the checkpoint through the
   existing control surface.
3. The workflow records the selected checkpoint state and rationale using the
   existing audit behavior.
4. Later workflow gates consume that recorded state without silently
   reinterpreting the operator's decision.

**Postconditions**: Signal classification improves without weakening or
replacing human checkpoint authority.

**Information shown**:

- Recommended and effective checkpoint state.
- Waiver or satisfaction rationale when supplied.
- Existing audit evidence for the decision.

**Actions available**:

- Keep the recommendation.
- Satisfy or waive the checkpoint.
- Stop the workflow run.

### Use Case 4: Maintainer verifies the decision boundary

**Actor**: Template maintainer reviewing or testing checkpoint behavior.
**Preconditions**: Test cases cover incidental body wording, title and label
signals, migration-specific phrases, and explicit human overrides.

**Steps**:

1. The maintainer runs the shared bounded-prelude checkpoint coverage.
2. Incidental body-only terms produce no data-model checkpoint.
3. Each strong signal produces a checkpoint with an exact reason.
4. Existing human override, waiver, and audit cases continue to pass.
5. The maintainer confirms the same decision boundary is used by every
   bounded workflow entry point that consumes the shared recommender.

**Postconditions**: The maintainer can distinguish false-positive suppression
from genuine migration protection and trace each outcome to test evidence.

**Information shown**:

- The classification result for each issue shape.
- The exact signal reported for each positive case.
- Preserved human-control and audit results.

**Actions available**:

- Accept the behavior.
- Request fixes when any generic term still triggers alone, a positive case
  loses protection, or the reported reason is not exact.

---

## Business Rules

- **BR1**: Incidental body mentions of `schema`, `database`, `SQL`, or
  `persistent data` must not independently create a data-model checkpoint.
- **BR2**: A data-model checkpoint requires at least one strong signal available
  before implementation: an explicit migration label, title-level migration or
  schema intent, or a migration-specific phrase.
- **BR3**: Migration-specific phrases include, at minimum, `CREATE TABLE`,
  `ALTER TABLE`, `new column`, and `database migration`; matching must preserve
  genuine positive cases without treating generic vocabulary as equivalent.
- **BR4**: Every positive classification must report the exact matched signal
  that caused the checkpoint.
- **BR5**: When multiple strong signals match, the workflow may report all of
  them and must report at least one exact match.
- **BR6**: The resilient-read issue shape described in the brief must remain a
  no-checkpoint case even when its body mentions database-facing responses or
  data shapes.
- **BR7**: Explicit human checkpoint overrides, satisfactions, waivers, waiver
  rationales, and audit records must retain their current authority and
  behavior.
- **BR8**: The decision boundary must apply consistently to the shared
  recommender used by bounded single-item, batch, and epic workflow entry
  points.
- **BR9**: Changed-file or implementation-diff evidence must not be required to
  classify a checkpoint before implementation exists.
- **BR10**: A negative data-model classification does not bypass unrelated
  product, security, architecture, review, CI, or destructive-action stops.

---

## Operational Visibility

- **Matched-signal reason**: Every recommended data-model checkpoint names the
  exact label, title intent, or migration-specific phrase that matched.
- **No-checkpoint path**: The summary does not invent a data-model reason when
  only incidental body terminology is present.
- **Human decision visibility**: Existing satisfaction and waiver rationales
  remain visible through the current checkpoint and audit surfaces.
- **Regression visibility**: Maintainers can verify the #1865-inspired negative
  case and genuine migration positive cases through committed coverage.

---

## Workflow Decision-Gate Matrix

| Gate inputs | Allowed outcome | Required next action | Operator-visible evidence | Mirror surfaces |
| --- | --- | --- | --- | --- |
| Explicit migration label is present | Data-model checkpoint required | Human satisfies or waives checkpoint before the guarded stage | Exact matched label | Shared bounded-prelude / checkpoint recommendation used by single-item, batch, and epic entry points |
| Issue title expresses migration or schema-change intent | Data-model checkpoint required | Human satisfies or waives checkpoint before the guarded stage | Exact matched title signal | Shared bounded-prelude / checkpoint recommendation used by single-item, batch, and epic entry points |
| Brief contains `CREATE TABLE`, `ALTER TABLE`, `new column`, or `database migration` | Data-model checkpoint required | Human satisfies or waives checkpoint before the guarded stage | Exact matched phrase | Shared bounded-prelude / checkpoint recommendation used by single-item, batch, and epic entry points |
| Body contains only generic data-adjacent terms such as `schema`, `database`, `SQL`, or `persistent data` | No data-model checkpoint from these terms | Continue the otherwise-approved path; still evaluate other checkpoints and stops | No false data-model reason | Shared bounded-prelude / checkpoint recommendation used by single-item, batch, and epic entry points |
| More than one strong signal matches | Data-model checkpoint required | Human satisfies or waives checkpoint before the guarded stage | At least one exact matched signal; all may be shown | Shared bounded-prelude / checkpoint recommendation used by single-item, batch, and epic entry points |
| Operator explicitly satisfies or waives a recommended checkpoint | Existing human decision remains authoritative | Record and consume the decision through existing lifecycle and audit behavior | Satisfaction or waiver state and rationale | Checkpoint policy, lifecycle labels/comments, and audit records |
| No data-model signal, but another checkpoint or stop applies | Data-model outcome does not override the other gate | Follow the separate gate's required action | Separate checkpoint or named stop reason | Existing bounded workflow guardrails |

---

## Acceptance Criteria

- [ ] **AC1**: An issue whose body incidentally mentions `schema`, `database`,
      `SQL`, or `persistent data`, with no strong data-model signal, does not
      receive a data-model checkpoint from those terms alone.
- [ ] **AC2**: The resilient-read example described in issue #1287 is covered as
      a no-data-model-checkpoint regression case.
- [ ] **AC3**: An explicit migration label creates the applicable data-model
      checkpoint and the recommendation names the exact matched label.
- [ ] **AC4**: Title-level migration or schema-change intent creates the
      applicable data-model checkpoint and the recommendation names the exact
      matched title signal.
- [ ] **AC5**: Each of `CREATE TABLE`, `ALTER TABLE`, `new column`, and
      `database migration` is covered as migration-specific positive evidence,
      with the exact matched phrase visible in the recommendation.
- [ ] **AC6**: Positive migration cases remain checkpointed after generic
      body-term matching is narrowed.
- [ ] **AC7**: Existing explicit human override, satisfaction, waiver,
      rationale, and audit behavior remain unchanged.
- [ ] **AC8**: The same classification behavior is used by the shared
      recommender consumed by bounded single-item, batch, and epic workflows.
- [ ] **AC9**: Prelude classification does not require changed-file evidence or
      an implementation diff.
- [ ] **AC10**: Suppressing a false data-model signal does not suppress any
      unrelated checkpoint or guardrail stop.

---

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| 1. Incidental data-adjacent body terms do not independently create a checkpoint | Use Case 1, BR1 | AC1, AC2 |
| 2. Strong structural evidence remains required | Use Case 2, BR2-BR3 | AC3-AC6 |
| 3. Report the exact matched signal | Use Cases 2 and 4, BR4-BR5, Operational Visibility | AC3-AC5 |
| 4. Cover the resilient-read negative regression | Use Cases 1 and 4, BR6 | AC2 |
| 5. Preserve positive migration cases | Use Cases 2 and 4, BR2-BR3 | AC3-AC6 |
| 6. Preserve human overrides and audit behavior | Use Case 3, BR7 | AC7 |
| 7. Apply behavior consistently across shared recommender consumers | Use Case 4, BR8 | AC8 |
| 8. Reduce unnecessary checkpoint pauses and resume-boundary exposure | Overview, Use Case 1 | AC1-AC2 |
| 9. Do not depend on unavailable changed-file evidence | BR9 | AC9 |

---

## Out of Scope (MVP)

- Using changed files, migration files, or an implementation diff as the
  prelude's primary classifier; that evidence does not exist when a Backlog
  start is evaluated.
- Maintaining an open-ended suppression list as the primary solution; this
  iteration defines positive, explainable signals instead of adding another
  one-off keyword exception.
- Redesigning checkpoint stages, lifecycle labels, human override controls, or
  audit record formats.
- Changing non-data-model checkpoint domains or weakening unrelated workflow
  guardrails.
- Prescribing implementation file names, helper APIs, matching algorithms, or
  storage formats; those decisions belong in the implementation plan.

## PR-Visible Deferral Notes

- **Changed-file and migration-file evidence as the primary prelude
  classifier**: Deferred because the backlog-triage refinement establishes
  that no implementation diff exists when the prelude runs. Human confirmation
  is not requested; this is an explicit timing constraint.
- **Accumulating a suppression list as the primary classifier**: Deferred
  because the refined scope replaces broad negative keyword matching with
  structured positive signals. Human confirmation is not requested.

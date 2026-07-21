# Automate Graduation Closeout on Merge - Spec

---

## Overview

When an integration branch graduates — a graduation pull request from
`develop-<slug>` merges into `develop` — delivered sub-items and the parent
epic must reach a terminal tracker status. Today that reconciliation only
happens if an operator finishes graduate-development Step 5 (graduation
closeout). The merge-time tracker updater intentionally skips graduation head
branches, so skipped Step 5 leaves the board stale.

This feature keeps operator-driven Step 5 as the primary closeout path and adds
an automatic fallback that runs the same closeout reconciler when a graduation
pull request merges. Closeout stays idempotent so agent and automation can both
run safely. Operator controls that defer epic closure or exclude specific
sub-items remain available and authoritative.

## Brief Objective List

Derived from issue #1281:

1. Keep graduate-development Step 5 as the primary closeout path after a
   graduation pull request merges.
2. Add an automatic fallback (repository automation) that invokes the same
   closeout reconciler when a graduation pull request merges.
3. Keep closeout idempotent so agent and automation double-runs are safe.
4. Preserve operator controls that defer epic closure or exclude specific
   sub-items from automatic terminal disposition.
5. Keep terminal Project status resolution order:
   graduated override → merged override → default display label `Merged`.
6. Do not treat sibling workflow items as dependencies of this change.

---

## Use Cases

### Use Case 1: Operator completes graduate-development Step 5 (primary path)

**Actor**: Workflow operator (or Work Item Runner / Portfolio Orchestrator
acting under `/graduate-development`).
**Preconditions**: A graduation pull request from `develop-<slug>` into
`develop` has merged with a merge commit, and the operator is finishing
post-merge cleanup.

**Steps**:

1. The operator runs the existing graduation closeout reconciler with the
   integration slug, merged graduation pull request, and parent epic.
2. The reconciler closes delivered planned sub-items (or reasserts terminal
   Project status for already-closed items) and closes the parent epic unless
   epic closure was deferred.
3. Excluded or optional/deferred sub-items remain open and are surfaced for
   human disposition.
4. The operator reports graduation cleanup complete only when closeout
   succeeds for delivered items.

**Postconditions**: Delivered planned sub-items and the parent epic (unless
deferred) are terminal on the project board. Optional or excluded items remain
open for human disposition.

**Information shown**:

- Closeout result for delivered, skipped/optional, deferred, and failed items.
- Whether the parent epic was closed or left open by deferral.
- The terminal Project status label applied.

**Actions available**:

- Re-run closeout safely if needed (idempotent).
- Defer epic closure or exclude specific issues before/during closeout.
- Stop and repair failed delivered items before claiming cleanup complete.

**Considerations**:

- This path remains the documented primary closeout path; automation is a
  fallback, not a replacement for operator Step 5.

### Use Case 2: Graduation merge triggers automatic closeout fallback

**Actor**: Repository automation (system).
**Preconditions**: A pull request whose head is an integration branch
(`develop-<slug>`) merges into `develop`, and the parent epic / delivered
sub-items can be discovered by the existing closeout reconciler.

**Steps**:

1. Merge-time automation detects a merged graduation pull request (not a
   normal `spec/*`, `implementation-plan/*`, `feature/*`, `fix/*`,
   `refactor/*`, or `hotfix/*` branch).
2. Automation invokes the same graduation closeout reconciler used by
   Step 5, supplying the slug, graduation pull request number, and parent
   epic discovered for that graduation.
3. The reconciler applies the same terminal status rules and epic/sub-item
   disposition rules as the operator path.
4. Automation records success, skip, or failure visibility without requiring
   an operator to be present at merge time.

**Postconditions**: If discovery and closeout succeed, delivered planned
sub-items and the parent epic (unless previously deferred by an operator
control that the reconciler honors) reach terminal status even when Step 5
was never run by an agent.

**Information shown**:

- Workflow/job log showing that graduation closeout ran and its result.
- Failure details when candidate discovery is incomplete or closeout fails
  closed.

**Actions available**:

- Operator may still run Step 5 afterward; a second run must not regress
  already-terminal items.
- Operator repairs failed discovery/closeout and re-runs Step 5 or re-triggers
  the automation path as appropriate.

**Considerations**:

- Automation must not invent a different closeout policy from the agent path.
- Normal non-graduation merges continue to use the existing merge-time tracker
  updater behavior and remain out of this feature's change surface except for
  ensuring graduation heads are no longer silently ignored without fallback.

### Use Case 3: Operator defers epic close or excludes sub-items

**Actor**: Workflow operator.
**Preconditions**: Graduation has merged (or is about to complete Step 5) and
the operator explicitly wants the parent epic left open and/or specific
sub-items left out of automatic terminal disposition.

**Steps**:

1. The operator runs closeout with deferred epic closure and/or excluded
   issue controls (same controls available to Step 5 today).
2. Delivered non-excluded sub-items still reconcile to terminal status.
3. The parent epic remains open when deferral is requested.
4. Excluded issues remain open and are reported for human disposition.

**Postconditions**: Operator controls override automatic epic closure and
automatic terminal disposition for excluded issues on both the agent path and
any automation fallback that can honor those controls.

**Information shown**:

- Explicit notes that epic close was deferred and which issues were excluded
  or skipped as optional/deferred.

**Actions available**:

- Later close the epic or excluded items manually once disposition is decided.

**Considerations**:

- Automation must not silently close an epic or excluded sub-item in a way
  that overrides an explicit operator deferral/exclusion recorded for that
  graduation closeout.

### Use Case 4: Agent Step 5 and automation both run (idempotent double-run)

**Actor**: Workflow operator and repository automation.
**Preconditions**: Graduation has merged; Step 5 closeout and the merge-time
fallback both execute (in either order).

**Steps**:

1. The first successful closeout reconciles delivered items and (unless
   deferred) the epic to terminal status.
2. The second closeout observes already-terminal delivered items and does not
   move them backward.
3. The second closeout does not reopen closed issues or undo deferred/excluded
   dispositions.

**Postconditions**: Board state remains correct after both runs; no
duplicate-destructive side effects.

**Information shown**:

- Already-terminal items reported without regressive status changes.

---

## Business Rules

- BR-1: Graduate-development Step 5 remains the primary documented closeout
  path after a graduation merge.
- BR-2: When a graduation pull request (`develop-<slug>` → `develop`) merges,
  repository automation must invoke the same closeout reconciler used by
  Step 5 (fallback path).
- BR-3: Closeout must be idempotent across agent and automation runs: already
  terminal delivered items are reported, not moved backward; closed issues are
  not reopened by a second run.
- BR-4: Operator controls that defer epic closure or exclude specific issues
  remain available on the primary path and must be preserved as authoritative
  disposition controls (automation must not invent a conflicting policy).
- BR-5: Terminal Project status resolution order is: graduated override →
  merged override → default display label `Merged`.
- BR-6: Closeout fails closed when delivered-candidate discovery is incomplete
  or no delivered sub-items can be identified; operators must repair before
  claiming graduation cleanup complete.
- BR-7: Optional, deferred, cancelled, or explicitly excluded sub-items are
  not silently closed; they are surfaced for human disposition.
- BR-8: Non-graduation merge-time tracker updates for `spec/*`,
  `implementation-plan/*`, `feature/*`, `fix/*`, `refactor/*`, and
  `hotfix/*` remain unchanged in product behavior.
- BR-9: This feature does not depend on sibling backlog items #1282 or #1284;
  treat those relationships as orthogonal.

---

## Statuses / Enum Values

| Code / override | Display label | Description |
| --- | --- | --- |
| Graduated override (when configured) | Repository-configured graduated label | Preferred terminal Project status for graduated work |
| Merged override (when configured) | Repository-configured merged label | Fallback terminal Project status when graduated override is unset |
| Default | Merged | Final default terminal Project status display label |

**Valid transitions**:

- Delivered planned sub-item (open or closed-but-non-terminal) → terminal
  Project status (resolution order above) when graduation closeout succeeds.
- Parent epic → closed (and terminal Project status) after delivered planned
  sub-items reconcile, unless epic closure is deferred.
- Already-terminal delivered sub-item → remains terminal (no backward move) on
  re-run.
- Excluded / optional / deferred sub-item → remains open for human disposition.

---

## Operational Visibility

- **Logs**: Agent Step 5 and merge-time automation both emit a closeout result
  covering delivered, skipped/optional, deferred, failed, and epic disposition.
- **Automation visibility**: The merge-time fallback job/log must show whether
  graduation closeout ran, skipped (non-graduation), or failed.
- **Failure signal**: Incomplete discovery or failed delivered reconciliation
  is an actionable stop condition; operators must not claim graduation cleanup
  complete while failures remain.
- **Audit**: Re-runs report already-terminal items without regressive updates.

---

## Workflow Decision-Gate Matrix

| Trigger | Epic deferral / exclusions | Closeout discovery | Required outcome | Next action | Mirror surfaces |
| --- | --- | --- | --- | --- | --- |
| Operator runs Step 5 after graduation merge | None | Delivered candidates found | Reconcile delivered sub-items + close epic | Report cleanup complete | Graduate-development protocol Step 5, closeout reconciler output |
| Operator runs Step 5 with defer epic and/or exclusions | Present | Delivered non-excluded candidates found | Reconcile delivered non-excluded items; leave epic/excluded open as requested | Surface disposition notes | Graduate-development protocol Step 5, closeout reconciler output |
| Graduation PR merges; automation fallback | No conflicting operator deferral/exclusion for that run | Delivered candidates found | Same reconciliation as Step 5 | Record automation success | Merge-time automation log, closeout reconciler |
| Graduation PR merges; automation fallback | N/A | Discovery incomplete / no delivered items | Fail closed; do not invent terminal status | Operator repairs and re-runs Step 5 (or re-triggers automation) | Merge-time automation log, closeout reconciler |
| Step 5 and automation both run | Same disposition rules | Already reconciled | Idempotent no-op / report already terminal | No regressive status moves | Both paths' closeout output |
| Non-graduation PR merges to `develop` | N/A | N/A for this feature | Existing merge-time tracker behavior unchanged | Continue current path | Existing merge-time tracker updater |

---

## Acceptance Criteria

- [ ] AC1: Given a merged graduation pull request and an operator finishing
      graduate-development Step 5, closeout reconciles delivered planned
      sub-items to the terminal Project status and closes the parent epic
      unless deferred.
- [ ] AC2: Given a graduation pull request merges and Step 5 was not run,
      repository automation invokes the same closeout reconciler and performs
      the equivalent delivered-item / epic reconciliation.
- [ ] AC3: Given closeout runs twice (agent then automation, or the reverse),
      the second run does not reopen issues or move already-terminal delivered
      items backward.
- [ ] AC4: Given the operator requests deferred epic closure, the parent epic
      remains open after closeout on the primary path, and automation does not
      apply a conflicting "always close epic" policy.
- [ ] AC5: Given one or more issues are excluded (or classified optional /
      deferred for human disposition), those issues remain open and are
      reported for disposition rather than silently closed.
- [ ] AC6: Given graduated and merged status overrides may be configured,
      terminal Project status resolution order is graduated override → merged
      override → default display label `Merged`.
- [ ] AC7: Given delivered-candidate discovery is incomplete, closeout fails
      closed and graduation cleanup is not claimed complete.
- [ ] AC8: Given a non-graduation workflow branch merges to `develop`, existing
      merge-time tracker status behavior for that branch type remains unchanged.
- [ ] AC9: Spec and follow-on work treat #1282 and #1284 as orthogonal; no
      cross-item dependency is introduced from shared wording alone.

---

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| Keep Step 5 as primary closeout path | Use Case 1, BR-1 | AC1 |
| Automatic fallback on graduation merge | Use Case 2, BR-2, Decision-Gate Matrix | AC2 |
| Idempotent agent + CI double-runs | Use Case 4, BR-3 | AC3 |
| Preserve defer-epic-close / exclude controls | Use Case 3, BR-4, BR-7 | AC4, AC5 |
| Terminal status resolution order | Statuses / Enum Values, BR-5 | AC6 |
| Fail closed on incomplete discovery | BR-6, Decision-Gate Matrix | AC7 |
| Leave non-graduation merge updater behavior intact | BR-8 | AC8 |
| Orthogonal to sibling batch items | BR-9 | AC9 |

---

## Out of Scope (MVP)

- Changing how graduation pull requests are created, reviewed, or merged
  (merge-commit requirement and graduate-development Steps 0–4 stay as today).
- Autonomous disposition of optional/deferred sub-items (humans still decide).
- Extending `post-merge-cleanup` into a full graduation/epic handler beyond
  what is required to invoke or document the same closeout reconciler.
- Changing terminal status behavior for ordinary `feature/*`, `fix/*`,
  `refactor/*`, `hotfix/*`, `spec/*`, or `implementation-plan/*` merges.
- Designing the concrete workflow file layout, secrets wiring, or helper CLI
  flags beyond the product constraints above (implementation plan owns that).
- Work on sibling items #1282 and #1284.

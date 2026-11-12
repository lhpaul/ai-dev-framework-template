# Backlog review protocol (`/review-backlog`), tracker-agnostic — Spec

## Overview

The template can advance one item, a batch, or an epic, but it has no way to
ask whether the backlog it advances from is still true. Items keep a status
their evidence no longer supports, epics stay unstarted after their children
ship, and untriaged items sort as if someone had ranked them. This feature adds
a periodic backlog review, invoked as `/review-backlog`, that audits the whole
backlog in three confirmed turns: clean the data, question the order, record
the outcome.

The review already exists in one consumer repository, where a run over 57
items found 13 shipped items still queued, an epic with four of five children
merged, and 43 items without a priority. The template version must work for
every supported tracker configuration, including repositories with no tracker
at all. It decides what a check can do by asking the tracker what it exposes,
never by the tracker's name.

Source: issue #2155 and the owner's resolved decisions in its 2026-11-10
comment "Decisiones resueltas", which are product constraints for this spec.
The origin protocol and its rationale are in the consumer repository's issue
#869.

## Resolved Decisions

These were decided by the template owner on 2026-11-10 and are not reopened by
this spec:

- **D1 — Three gates, not one report.** Gate 1 cleans the set, Gate 2 orders
  the cleaned set, Gate 3 closes out. Cancelling or merging an item changes
  the live set and every rank below it, so ordering before cleaning ranks data
  that is about to move. A small backlog may group findings by class, but the
  confirmations are never removed.
- **D2 — Conversational confirmation is the write authority; no apply flag.**
  Before writing, the run shows the exact set (item identifiers and values).
  After writing, it reads every item back and reports the observed value; a
  write whose returned value differs from the request is drift, not applied.
  Cancelling, merging duplicates, and creating items each require an explicit
  confirmation for that item or that named group. Body edits are shown as
  proposed text and are never applied by the run.
- **D3 — Complements `/run-work`, does not replace it.** `/run-work` decides
  what to advance now and mutates nothing. The backlog review asks whether the
  data and order that decision uses are still right. The intended sequence is a
  periodic backlog review, then `/run-work` chooses the batch. The workflow
  guide must say so.
- **D4 — Capability detection, not provider lists.** The review asks the
  configured tracker what it exposes (parent/child hierarchy, a priority field,
  labels, and the other capabilities below). A check whose capability is
  missing reports "no aplica" and names the missing capability. No check fails
  because a capability is absent, and none assumes a capability from the
  provider's name. Capabilities are documented in one table organized by
  capability, not by provider.

## Use Cases

### Use Case 1: Review a backlog on a fully capable tracker

**Actor**: Repository maintainer (the backlog owner or someone with authority
over scope).
**Preconditions**: The repository has a configured tracker, the tracker scope
(project, milestone, or whole repository) resolves, and the tracker budget is
enough to read the scope.

**Steps**:

1. The maintainer runs `/review-backlog` from any supported runner.
2. The run states the resolved scope, the capabilities it detected, the
   coverage of its read, and the tracker budget.
3. The run delivers Gate 1, the structural ledger, split into three blocks:
   findings it can apply once confirmed, findings it only reports, and
   questions that need the maintainer's judgement, each with one
   recommendation.
4. The maintainer answers by finding identifier or by class.
5. The run shows the exact confirmed write set, applies it, reads each item
   back, and reports applied, drift, and unapplied counts.
6. When Gate 1 closed clean on a full read, the run re-reads the board and
   delivers Gate 2: the order the dispatcher would produce today, the defects in
   that order, and a proposed queue with a named signal per rank change.
7. The maintainer confirms priority, type, and label changes; the run applies
   and reads them back as in step 5.
8. The run delivers Gate 3: what was applied, what is pending for the
   maintainer, the precedents from this run, and the final backlog state.

**Postconditions**: Every confirmed status, classification, priority, and
label change is either applied and read back with the requested value, or
reported as drift or unapplied. Nothing outside the confirmed set changed.

**Information shown**:

- Run header: scope, detected capabilities, coverage, budget, counts, the
  oldest live item, and the number of items without a priority (when that
  capability exists).
- Per finding: identifier, current and proposed value, and inline evidence.
- Per open question: recommendation, evidence, cost of overriding, confidence.

**Actions available**:

- Confirm or reject findings by identifier, range, or class.
- Accept a recommendation with "recomendación".
- Override a recommendation; the override becomes a precedent in Gate 3.
- Explicitly confirm a cancellation, duplicate merge, or item creation for a
  named item or group.
- Ask to rank the set as-is while confirmed set-changing actions are still
  outstanding; the queue then flags those items, and the choice is recorded as
  an override.

**Considerations**:

- A tracker rejection mid-write stops the gate immediately; the applied prefix
  and every unapplied identifier are reported, and the next gate does not open.
- Confirmed set-changing actions the run did not perform hold Gate 2 by
  default: the run ends at the Gate 1 close, names them as pending for the
  maintainer, and a later run opens Gate 2.

### Use Case 2: Review a repository with no tracker

**Actor**: Repository maintainer.
**Preconditions**: The repository declares no tracker.

**Steps**:

1. The maintainer runs `/review-backlog`.
2. The run declares repository-only mode in its header.
3. Gate 1 runs only the repository-evidence checks: merged work, where it
   merged, released changelog coverage, and development folders or pull
   requests with no item identifier.
4. Every tracker-dependent check reports "no aplica" with the missing
   capability named; the tracker side of any finding is marked unverified.
5. Gate 2 reports "no aplica" (no board to rank). Gate 3 closes out Gate 1
   alone.

**Postconditions**: The run completes without failing, writes nothing, and
does not present itself as a complete board review.

### Use Case 3: Review on a tracker missing some capabilities

**Actor**: Repository maintainer.
**Preconditions**: The tracker lacks one or more capabilities (for example, no
parent/child hierarchy, no priority field that can be unset, or no labels).

**Steps**:

1. The maintainer runs `/review-backlog`.
2. The header lists each detected capability and each missing one.
3. Each check that depends on a missing capability reports "no aplica" and
   names that capability; the remaining checks run normally.

**Postconditions**: The run completes; no check fails or substitutes a
convention (a label, a body marker) for a missing capability.

### Use Case 4: Run under a limited tracker budget

**Actor**: Repository maintainer.
**Preconditions**: The tracker's remaining budget is low, or the tracker
exposes no readable budget.

**Steps**:

1. The run samples the budget before reading.
2. It declares one coverage value and acts on it (see Statuses).
3. Before the first write of a gate, when the budget is measurable, it decides
   once whether the whole confirmed set fits; if not, it writes nothing and
   reports the projected cost and reset time. When the budget is not
   measurable, it applies the set in order and stops at the first rejection.

**Postconditions**: The run never applies a self-chosen partial prefix of a
confirmed set, and never presents a partial read as full.

## Business Rules

- BR1 (gates): The three gates run in order and each waits for the
  maintainer. Gate 2 opens only after Gate 1 closed clean on a full read
  (coverage `full` or `full-unmetered`): no rejected, drifted, or unapplied
  confirmed write, and no confirmed cancel, merge, or create action still
  outstanding unless the maintainer explicitly asked to rank the set as-is
  (that choice is recorded as an override). Gate 3 opens only after Gate 2
  closed clean, except in repository-only mode, where Gate 3 closes Gate 1
  alone. A partial read (the initial read, or the board re-read after the
  Gate 1 writes) ends at the Gate 1 close; a partial board re-read after the
  Gate 2 writes only marks Gate 3's final backlog state `partial`. Grouping
  findings by class is allowed; removing a confirmation is not.
- BR2 (confirmation is the authority): No mutation happens before the
  maintainer answers the gate that proposes it. No flag is required or
  accepted as a substitute. Before writing, the exact set (identifiers and
  values) is shown.
- BR3 (readback): Every write is read back and the observed value is
  reported. A returned value different from the requested value is drift and
  counts as unapplied. A readback that fails or cannot be read is treated as a
  rejection: the item counts as unapplied and the gate stops.
- BR4 (writable actions): A gate confirmation authorizes only upward status
  changes, classification changes, priority changes, and the narrow label
  corrections the review defines (removing a superseded classification hint,
  adding a missing integration-branch label shared by an epic's siblings).
- BR5 (explicit-confirmation actions): Cancelling or closing an item, merging
  duplicates, and creating items each need an explicit confirmation naming that
  item or a group the run presented by name (such as a duplicate group); a
  class, range, or gate-wide confirmation does not authorize them.
  Creation goes through the existing backlog-item protocol. When the tracker
  cannot perform the action, it is delivered as pending for the maintainer.
- BR6 (never performed by the run): Body, title, and description edits are
  delivered as proposed text. Status regressions, dependency edits, and
  tracker rank fields are reported only. An epic is never moved to a child's
  stage.
- BR7 (write admission): Writes are admitted once per gate, before its first
  write. When the budget is measurable, admission uses a budget sample taken
  after that gate's reads, and the projection covers every confirmed write,
  its readback, and the board re-read that follows; either the whole confirmed
  set fits and is applied, or nothing is applied. When it is not measurable, the set is
  applied in order and the first rejection stops it. A partial prefix is only
  ever the result of a tracker rejection.
- BR8 (capability detection): The run detects each capability from the
  configured tracker before using it. A check whose capability is missing
  reports "no aplica" naming the capability. Missing capabilities never fail
  the run, and no capability is inferred from the provider's name.
- BR9 (scope): Scope is resolved by capability: the configured project when the
  tracker supports projects; the configured milestone when it does not and a
  milestone is configured; otherwise the whole repository. A project-capable
  tracker with no project configured stops before reading and asks once (or
  accepts an explicit widen-to-all-projects instruction). Conflicting
  configured scopes (two configured identifiers naming different projects, or
  different milestones) stop and ask. Scope is never widened silently.
- BR10 (provider-neutral text): The protocol's normative text names no tracker
  product. Any provider-specific vocabulary appears only in the single
  capability-resolution reference. Tracker reads and writes go through the
  template's generic tracker contract, with the configured provider resolved
  by the runner as the other orchestration protocols do.
- BR11 (shared vocabulary): Status values come from the template's canonical
  tracker-status mapping; classification values and the framework-mode rule
  come from the existing backlog-item and type-routing rules. The review
  references them and does not redefine them.
- BR12 (evidence over claims): A finding that relies on an item being done,
  superseded, or duplicated cites the repository or tracker evidence checked.
  An item's own text is a claim, not evidence. A finding whose evidence would
  be an unread item (on a `partial` read) is held, never guessed. Two sweeps
  are mandatory on every full run: shipped work still queued, and epics whose
  children have shipped.
- BR13 (recommendations): Every question that needs the maintainer's judgement
  carries one recommendation, the evidence for it, the cost of overriding it,
  and a declared confidence. A menu of options is not a recommendation.
- BR14 (dispatcher fidelity): Gate 2 reconstructs the order the dispatcher
  actually produces, using only the priority values the dispatcher recognizes.
  Priority tier is the durable deliverable; order within a tier is labelled
  advisory.
- BR15 (precedents): The run reads the repository's recorded backlog-review
  precedents when they exist. Gate 3 emits override lines for that record (the
  gate close report emits them when the run ends before Gate 3), but the run
  never writes repository files.
- BR16 (relationship to `/run-work`): The review never dispatches, starts, or
  runs an item. The workflow guide and the protocol both state that the review
  complements `/run-work` and precedes batch selection.
- BR17 (distribution): The protocol and its command aliases reach consumer
  repositories through ordinary template synchronization, and are available
  from every runner that exposes workflow commands.

## Statuses / Enum Values

The run reports with fixed labels. They are part of the contract that the
aliases and the smoke runbook rely on; the report labels are Spanish by design
because the report is answered by the backlog owner in the language they work
in.

| Code value | Display label | Description |
| --- | --- | --- |
| `full` | full | Every item in scope read; budget sampled |
| `full-unmetered` | full (sin presupuesto) | Every item read; the tracker exposes no readable budget |
| `partial` | partial | Budget-limited read that is not `deferred`; omitted items named (when the listing itself was cut short, the unlisted remainder of the scope is declared unread); run ends at Gate 1 close, except a re-read after the Gate 2 writes, which only marks Gate 3's final state |
| `deferred` | deferred | The measured budget sampled before the read cannot cover listing every item in scope (the minimum a `partial` read needs to name its omitted items); run ends, nothing proposed. An unmeasurable budget is never `deferred` |
| `repository-only` | n/a (sin tracker) | No tracker; repository evidence only; a budget-limited repository read names what it omitted |
| `ready-to-confirm` | LISTO PARA CONFIRMAR | Evidence-only findings the run applies once confirmed |
| `report-only` | SOLO REPORTE | Delivered, never applied by a gate confirmation |
| `needs-judgement` | NECESITA TU CRITERIO | Questions with one recommendation each |
| `not-applicable` | no aplica | Check skipped because a named capability is missing |
| `applied` | aplicado | Written and read back with the requested value |
| `drift` | drift | Written, but read back with a different value; counts as unapplied |
| `unapplied` | not applied | Confirmed but not written (after a rejection, or refused for budget), or written but its readback failed; the reason is shown |
| `pending-maintainer` | PENDIENTE DE TI | Confirmed or proposed action the run does not perform (proposed body text, an action the tracker cannot perform); delivered in Gate 3, or in the gate close report when the run ends before Gate 3 |
| `unverified` | unverified | Repository-only mode: the tracker side of a finding could not be checked |

**Valid transitions** (per gate):

- Gate 1 → Gate 2 when the confirmed set is fully applied without drift (or
  nothing was confirmed), no confirmed set-changing action is outstanding (or
  the maintainer chose to rank as-is), and coverage is `full` or
  `full-unmetered`, including on the board re-read after the Gate 1 writes.
  A re-read that downgrades coverage to `partial` ends the run at the Gate 1
  close.
- Gate 1 → Gate 3 (Gate 1 closeout only) when coverage is `repository-only`.
- Gate 1 → end when coverage is `partial` (after the Gate 1 close, with Gate 2
  named as deferred pending a full read) or `deferred`, or the set was rejected, drifted,
  or refused for budget (recovery step reported), or a confirmed set-changing
  action is outstanding and the maintainer did not ask to rank as-is (outstanding
  actions named as pending for the maintainer; a later run opens Gate 2).
- Gate 2 → Gate 3 when the confirmed set is fully applied without drift, or
  nothing was confirmed. A board re-read after the Gate 2 writes that
  downgrades coverage to `partial` still opens Gate 3, which marks its final
  backlog state `partial` and names the omitted items.
- Gate 2 → end when the set was rejected, drifted, or refused for budget.

## Decision-Gate Consistency Matrix

Precedence, highest first: missing or conflicting scope stops before reading;
`deferred` ends the run; repository-only mode; `partial` read (the initial
read or the board re-read after the Gate 1 writes; a `partial` re-read after
the Gate 2 writes only marks Gate 3's final state); write outcome
of the current gate; then, at the Gate 1 close only, a confirmed cancel,
merge, or create action still outstanding, which holds Gate 2 even after a
clean application or when nothing else was confirmed. Within a gate, a
rejection outranks drift, and drift outranks clean application. Missing capabilities never change a gate outcome;
they only turn the dependent check into "no aplica".

| Inputs | Allowed outcome | Required next action | Mirror surfaces |
| --- | --- | --- | --- |
| Project-capable tracker, project configured | Scope = that project | Read and continue | Protocol, aliases, smoke runbook |
| Project-capable tracker, no project configured | Stop before reading | Ask once, or accept explicit widen-to-all-projects | Protocol, aliases, smoke runbook |
| Two configured identifiers name different projects (or different milestones) | Stop before reading | Ask which governs | Protocol, smoke runbook |
| Configured scope does not resolve | Stop before reading | Ask once, naming what is missing | Protocol, smoke runbook |
| No project concept, milestone configured | Scope = that milestone | Read and continue | Protocol |
| No project concept, no milestone configured (or no milestone concept) | Scope = whole repository, stated in header | Read and continue | Protocol |
| No tracker | Repository-only mode | Gate 1 repository checks; Gate 2 "no aplica"; Gate 3 closes Gate 1; nothing written | Protocol, aliases, smoke runbook |
| Measured pre-read budget cannot cover listing every item in scope | `deferred` | End; report budget and reset | Protocol, smoke runbook |
| A read that is not `deferred` and does not reach every item in scope (initial read, or the board re-read after the Gate 1 writes), including a listing cut short after the pre-read sample or under an unmeasurable budget | `partial` | Ledger of what was read; omitted items named, or, when the listing itself was cut short, the unlisted remainder of the scope declared unread; no queue; end at Gate 1 close | Protocol, smoke runbook |
| Board re-read after the Gate 2 writes is `partial` | Gate 3 opens | Closeout with final backlog state marked `partial`, omitted items named | Protocol, smoke runbook |
| No readable budget, all read | `full-unmetered` | Proceed; ordered apply, stop at first rejection | Protocol, smoke runbook |
| Capability missing (hierarchy, priority, priority that can be left unset, labels, classification carrier, budget surface) | Dependent check "no aplica", capability named | Continue other checks | Protocol, smoke runbook |
| Gate confirmed set fits (or unmetered), all read back equal | Applied | Re-read board; open next gate | Protocol, aliases |
| Measured budget insufficient for the confirmed set | Nothing written | Report cost and reset; next gate not opened; end | Protocol, smoke runbook |
| Tracker rejects mid-write | Applied prefix + unapplied list | Stop; next gate not opened; report recovery step; end | Protocol, smoke runbook |
| Readback differs from request | Drift (unapplied) | Next gate not opened; report drifted identifiers and recovery step; end | Protocol, smoke runbook |
| Nothing confirmed in Gate 1 | No write | Open Gate 2 (when coverage is `full` or `full-unmetered`) | Protocol |
| Nothing confirmed in Gate 2 | No write | Open Gate 3 | Protocol |
| Confirmed cancel/merge/create outstanding | Gate 2 held | Name outstanding actions as pending for the maintainer and end (a later run opens Gate 2); or rank as-is on explicit request, flagging those items | Protocol, aliases |
| Cancel/merge/create confirmed only by class, range, or gate | Not authorized | Ask for explicit per-item or per-group confirmation | Protocol, aliases, smoke runbook |
| Body edit accepted | Not applied | Deliver proposed text as pending | Protocol, aliases, smoke runbook |
| Gate 3 with overrides / without overrides | Precedent lines emitted / none | Closeout; no repository file written | Protocol |

Unknown or malformed tracker responses are treated as unread items (they lower
coverage) or as rejections (during writes and their readback); they never count as a missing
capability or as applied.

## Operational Visibility

- **Run header**: scope and how it was resolved, detected and missing
  capabilities, coverage, budget, and admission type (measured or unmetered).
- **Gate close reports**: applied, drift, and unapplied counts with
  identifiers; the recovery step when a gate did not close clean.
- **Audit trail**: the tracker's own history records each applied write; Gate 3
  records what was applied, what is pending for the maintainer, and the
  precedent lines for the repository's precedent record. No new notification
  channel or audit store is introduced.

## Acceptance Criteria

- [ ] AC1: The protocol's normative text names no tracker product. A text search
  of the protocol for the tracker product names "Linear", "Jira", "GitHub
  Issues", and "GitHub Projects" (and their provider configuration values)
  finds matches only inside the single capability-resolution reference.
- [ ] AC2: The capability reference is organized by capability (one row per
  capability), and each row states how the capability is detected, which checks
  depend on it, and the "no aplica" outcome that names it when missing.
- [ ] AC3: With no tracker configured, a smoke run completes without failing:
  the header declares repository-only mode, every tracker-dependent check
  reports "no aplica" naming its missing capability, Gate 2 reports "no aplica",
  Gate 3 closes Gate 1 alone, and nothing is written.
- [ ] AC4: For each of the template's GitHub Issues and GitHub Projects
  provider configurations, the smoke runbook records the capabilities the run
  detected and shows the epic sweep listing children through the detected
  hierarchy (or "no aplica" naming the hierarchy capability when it is not
  detected) and the order reconstruction using the tracker's own priority
  values, naming which of them the dispatcher recognizes (or "no aplica"
  naming the priority capability when no priority field is detected).
- [ ] AC5: On a tracker missing hierarchy, a priority that can be left unset,
  or labels, the corresponding check reports "no aplica" naming that
  capability, and no other check fails.
- [ ] AC6: The protocol states three gates in order (ledger, order, closeout),
  that each waits for confirmation, and that grouping by class never removes a
  confirmation.
- [ ] AC7: The protocol states that conversational confirmation is the write
  authority with no apply flag; that the exact set is shown before writing; that
  every write is read back with the observed value reported, drift counts as
  unapplied, and a failed readback counts as a rejection; that cancel, duplicate
  merge, and item creation need explicit per-item or per-group confirmation;
  that a gate confirmation authorizes only the writable actions of BR4; that
  status regressions, dependency edits, and tracker rank fields are reported
  only; and that body edits are delivered as proposed text and never applied.
- [ ] AC8: The workflow guide and the protocol both state that the backlog
  review complements `/run-work` and does not replace it, and give the intended
  sequence.
- [ ] AC9: `/review-backlog` is available as a command alias for Claude Code,
  Cursor, and the shared skills directory used by Codex and DSH, each pointing to
  the protocol rather than restating it; the repository agent guide and the
  workflow guide list it.
- [ ] AC10: Every new file is covered by the synchronization manifest, and the
  manifest coverage check passes.
- [ ] AC11: A smoke-test runbook for the backlog review exists, and a test suite
  that reads it (and the protocol and aliases) passes in CI.
- [ ] AC12: The implementation includes a changelog fragment.
- [ ] AC13: The protocol states scope resolution by capability (configured
  project, else configured milestone, else whole repository), and that a
  project-capable tracker with no project configured, conflicting configured
  scopes, or an unresolvable scope stop before reading and ask.
- [ ] AC14: The protocol takes status values from the canonical tracker-status
  mapping and classification values from the existing backlog-item and
  type-routing rules by reference, without restating their value lists.
- [ ] AC15: The protocol makes the shipped-work-still-queued and
  epics-with-shipped-children sweeps mandatory on every full run, requires each
  done, superseded, or duplicate finding to cite repository or tracker
  evidence, and holds a finding that depends on an unread item.
- [ ] AC16: The protocol requires every question that needs the maintainer's
  judgement to carry exactly one recommendation, its evidence, the cost of
  overriding it, and a declared confidence.
- [ ] AC17: The protocol states write admission once per gate (whole confirmed
  set or nothing when the budget is measurable; ordered apply stopping at the
  first rejection when it is not) and the gate-opening conditions of the Valid
  transitions above, including that a partial initial read or post-Gate-1
  re-read ends at the Gate 1 close and a partial post-Gate-2 re-read only marks
  Gate 3's final backlog state `partial`.

## Brief Objective List and Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| Port the protocol into the template without coupling it to one tracker | AC1, AC2; BR8, BR10 |
| Tracker read/write path through the generic tracker contract | BR10, BR11; AC1 |
| Scope resolution without a provider-only project field | AC13; BR9; matrix scope rows |
| Epic sweep through detected hierarchy, "no aplica" when absent | AC4, AC5; BR8, BR12 |
| Order reconstruction with the tracker's own priority vocabulary | AC4; BR14 |
| "No priority" check degrades when priority cannot be unset | AC5; BR8 |
| Labels check degrades when labels do not exist | AC3, AC5; BR8 |
| Status and Type referenced, not redefined | AC14; BR11 |
| Shipped-but-queued and epic-with-shipped-children sweeps | AC15; BR12 |
| One recommendation per judgement question | AC16; BR13 |
| Decision 1: three gates | AC6, AC17; BR1 |
| Decision 2: conversational confirmation, explicit confirmation classes, body edits as text | AC7, AC17; BR2–BR7 |
| Decision 3: complements `/run-work`, README says so | AC8; BR16 |
| Correction: capability detection, table by capability | AC2, AC5; BR8 |
| Aliases for each runner | AC9; BR17 |
| Agent-guide and workflow-guide rows | AC9 |
| Synchronization manifest entries and coverage check | AC10 |
| Smoke runbook and suite that reads it | AC11 |
| Changelog fragment | AC12 |
| `provider: none` runs with "no aplica" | AC3 |
| GitHub issue/project providers run epic sweep and order with correct vocabulary | AC4 |

## Out of Scope (MVP)

- Any helper script that automates the review's reads or writes; the run is
  agent-executed against the generic tracker contract.
- Shipping a precedent record file in the template; each repository creates its
  own record from Gate 3 output.
- Automated scheduling of periodic reviews.
- Changing `/run-work`, the dispatcher's ordering, the canonical status
  mapping, the classification rules, or any workflow, CI, or configuration file.
- Writing tracker rank fields, dependency relations, or epic stages.
- Editing the consumer repository where the protocol originated.

## Deferral Notes

- A helper script was not requested by the brief; agent execution against the
  existing tracker contract satisfies every acceptance criterion. No human
  confirmation requested.
- A template-shipped precedent record would be overwritten or diverge on
  synchronization because its content is repository-specific. No human
  confirmation requested.

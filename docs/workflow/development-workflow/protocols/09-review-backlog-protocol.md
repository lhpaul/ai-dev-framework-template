# Protocol: Review Backlog

**Agent role**: Backlog reviewer
**Command**: `/review-backlog`
**Stage**: Backlog maintenance

---

## Purpose

Periodically re-examine the backlog as a whole instead of one item at a time.
Item-level work (specs, plans, implementation) assumes the backlog is already
coherent. It is not: items arrive with no classification, a status that
stopped matching their evidence, missing body sections, and a priority nobody
re-read after the item landed. Orchestration then sorts a fiction.

`/run-work` (Protocol 96) reads the backlog to decide what to advance now. This
protocol asks whether the backlog's data and order are worth advancing at all.
The review complements `/run-work`; it does not replace it. The intended
sequence is a periodic backlog review, then `/run-work` selects the batch.

The run is **three gates in order**, not one report:

1. **Gate 1 — structural ledger**: fix what is verifiably wrong.
2. **Gate 2 — order**: question the order the dispatcher would produce.
3. **Gate 3 — closeout**: record what was applied, what is pending, and the
   precedents.

Each gate waits for the maintainer's confirmation. The run never orders a set
Gate 1 has not cleaned, because cancelling or merging an item changes the live
set and every rank below it. A small backlog may group findings by class, but
grouping by class never removes a confirmation.

This protocol never names a tracker product outside the capability-resolution
reference below. Every check is keyed to a **capability** the run detects from
the configured tracker, never to the provider's name.

---

## Prerequisites

Read:

- [`issue-tracker.md`](../integrations/issue-tracker.md) — the generic tracker
  contract every read and write goes through, including its deferred-action
  protocol for trackers the shell cannot reach directly.
- [`tracker-status-mapping.md`](../tracker-status-mapping.md) — the canonical
  Status vocabulary and the (stage, event) mapping this protocol resolves
  through.
- [`00-add-backlog-item-protocol.md`](00-add-backlog-item-protocol.md) — the
  classification values, the classification heuristics, and the framework-mode
  rule.
- `.ai-dev-workflow.yaml` — the configured tracker and the scope identifiers
  it names. The provider is resolved by the runner, as the other orchestration
  protocols do; this protocol never branches on its name.
- `docs/project/backlog-review-precedents.md`, when it exists (see Gate 3).

Thresholds: `--aged-days N` (default 90), `--recent-days N` (default 14).

### Status shorthand

Status values are never spelled out here. `S(stage, event)` means the Status
the canonical mapping resolves for that pair, through
[`tracker-status-mapping.md`](../tracker-status-mapping.md) or
`./scripts/development-workflow/tracker-status-for.sh --event <event> --stage <stage>`.
Two shorthands recur:

- **the merged status** = `S(implementation, merged)`;
- **the released status** = `S(implementation, released)`.

Both are terminal for this review: they mean no work is left in the backlog.
**The initial backlog status** is the Status an item carries before any
`dispatch` event. The out-of-band cancellation Status is named by the mapping
page and is only ever written by an explicit-confirmation action.

### Capability detection

Before reading any item, the run probes the configured tracker for each
capability in the reference below and lists, in the run header, every
capability it detected and every one it found missing.

- A **missing** capability turns every check that depends on it into
  `no aplica — <capability>`. No check fails because a capability is absent,
  and no check substitutes a convention (a label, a body marker) for it.
- A probe that **errors or returns a malformed response** does not prove the
  capability is missing. The capability is marked `unverified`, every check
  that depends on it is held and named in the header, and coverage drops to
  `partial`. Detection failure never yields `no aplica`.
- A capability is never inferred from the provider's name. The last column of
  the reference only tells the runner where a configured integration exposes
  the capability; the probe decides.
- **Probes target the configured tracker**, not every surface the same API
  happens to offer: a tracker configured without projects does not detect
  project scope because the API behind it also serves projects.
- **Write capabilities** (item closure, duplicate relation, label editing,
  field writes) are detected from what the read surface advertises — the
  operation exists for the configured tracker and the run's credentials are
  permitted to perform it — never by test-writing. A write that later fails is
  a rejection under the Write contract, not a missing capability.
- A **definite not-found** answer to a configured identifier (the tracker
  answers that it does not exist) is "cannot find" under Scope; only a
  transport error or a malformed answer makes a capability `unverified`.
- When the run stops at Scope before reading any item, capabilities whose
  probe needs an item are listed as `no sondeadas`, not as detected or
  missing.

<!-- capability-resolution:start -->

### Capability-resolution reference

This is the only section of this protocol that names a provider or a provider
configuration value. Every other section refers to a capability by its row
name.

| Capability | How the run detects it | Checks that depend on it | Outcome when missing | Where configured integrations expose it |
| --- | --- | --- | --- | --- |
| project scope | The configured tracker is project-based: its configuration takes a project identifier (resolved when one is configured). A tracker configured without projects does not detect it, even when the same API also serves projects | Scope resolution | Scope falls through to milestone scope; see Scope | GitHub Projects (`github_projects`): `project_number`, see [`github-projects.md`](../integrations/github-projects.md). Linear (`linear`): `project_url` or the project key in `issue_tracker.custom_fields`, see [`linear.md`](../integrations/linear.md) |
| milestone scope | The tracker exposes a milestone or release field for items | Scope resolution | Scope is the whole repository | GitHub Issues (`github_issues`) milestones, see [`issue-tracker.md`](../integrations/issue-tracker.md) |
| parent/child hierarchy | Reading a known item returns a parent field or a child list the API can traverse | 1j epic sweep; `integration-branch:<slug>` sibling check in 1c | `no aplica — parent/child hierarchy` | GitHub Projects and GitHub Issues: native sub-issues, see [`github-projects.md`](../integrations/github-projects.md). Linear: parent/sub-issues, see [`linear.md`](../integrations/linear.md) |
| priority field | Items expose a priority field with a readable option list | 2a sort key 2; Gate 2 priority writes; header "sin prioridad" count | `no aplica — priority field`; the order sorts by due date then creation date | GitHub Projects: a single-select Priority field. Linear: native priority. GitHub Issues without a project: none, see [`issue-tracker.md`](../integrations/issue-tracker.md) |
| priority that can be left unset | The priority field accepts and returns an empty value | 2a "priority as a hiding place" | `no aplica — priority that can be left unset`; a forced default is never counted as untriaged | GitHub Projects: empty single-select. Linear: "No priority" value |
| classification carrier | Items expose a native type field, a single-select classification field, or exactly one known classification label | 1c classification and its write | `no aplica — classification carrier`: the inferred classification is reported as context, nothing written | GitHub Projects: the Type field, see [`github-projects.md`](../integrations/github-projects.md). Linear: labels or custom field per [`linear.md`](../integrations/linear.md). GitHub Issues: labels, see [`issue-tracker.md`](../integrations/issue-tracker.md) |
| free-form labels | Items expose a label set the API can read and edit | 1c label half; label corrections | `no aplica — free-form labels`; the classification half of 1c still runs | GitHub Issues and GitHub Projects: repository labels. Linear: team labels |
| item closure | The API can close or cancel an item | Explicit-confirmation cancel/close | The confirmed action is delivered under `PENDIENTE DE TI` naming `item closure` | GitHub Issues and GitHub Projects: close the issue. Linear: the cancelled state, see [`linear.md`](../integrations/linear.md) |
| duplicate relation | The API can mark an item as a duplicate of another | Explicit-confirmation duplicate merge | The confirmed merge is delivered under `PENDIENTE DE TI` naming `duplicate relation` | GitHub Issues and GitHub Projects: close as duplicate. Linear: the duplicate relation |
| readable rate-limit surface | The tracker returns a remaining budget and a reset time | Read and write budget | Coverage `full (sin presupuesto)` with unmetered admission when everything was read; never `no aplica` | GitHub Issues and GitHub Projects: the API rate-limit endpoint and headers. Linear: rate-limit response headers |

With `issue_tracker.provider: none` no tracker is configured: no capability is
detected and the run is in repository-only mode.

<!-- capability-resolution:end -->

---

## Scope

Scope is resolved by capability, before the first item read, and stated in
the run header together with how it was resolved:

| Situation | Scope |
| --- | --- |
| project scope detected, a project configured | That project |
| project scope detected, no project configured | **Stop before reading.** Ask once which project to use, or accept an explicit `--all-projects` instruction to widen to every project. A project-capable tracker with no project named is a configuration gap, not a capability gap |
| Two configured identifiers name different projects (or different milestones) | **Stop before reading** and ask which one governs. Never intersect or union them |
| A configured scope the tracker rejects or cannot find (a project identifier that does not resolve, a milestone that does not exist) | **Stop before reading** and ask once, naming the identifier that could not be resolved |
| No project scope, milestone scope detected and a milestone configured | That milestone |
| No project scope, and no milestone configured or no milestone scope | The whole repository's items, stated in the header. This is a supported combination, not a missing configuration: resolve it and say so, do not ask |
| No tracker configured | Repository-only mode, below |

Scope is never widened silently. The scope obligation binds Step 1 before the
first item read and is discharged by the run header's scope line.

A project-capable tracker never falls through to "whole repository": that
tracker can express a scope decision nobody made, and the run has no evidence
to make it.

### Repository-only mode

With no tracker configured, the run is a different, smaller run and says so
instead of pretending a board exists:

- **Header** declares repository-only mode; the coverage field reads
  `n/a (sin tracker)`.
- **Step 1** reads no items. It reads the repository: workflow branches, their
  PRs, development folders under `docs/specs/developments/`, `changelog.d/`
  fragments and released `CHANGELOG.md` sections.
- **Gate 1** runs only the checks whose evidence lives in the repository. The
  landed-work sweep runs from the evidence instead of the claim: every merged
  implementation PR and `changelog.d/` fragment is matched back to an
  identifier by branch, PR title and body.
  - **Established**: the merged work exists, where it merged, and whether a
    released `CHANGELOG.md` section carries it. Orphaned work — a development
    folder or a merged PR with no identifier — is fully verifiable from the
    repository.
  - **Not established**: whether a tracker item exists for that work. Those
    are reported as `unverified`, never as findings.
  - Every tracker-dependent check (status drift, completeness, classification
    and labels, duplicates, dependencies, the epic sweep) reports
    `no aplica` naming the capability it needs.
- **Gate 2** reports `no aplica`: there is no board to rank.
- **Gate 3** closes out Gate 1 alone, with no applied counts, because nothing
  is writable without a tracker. Every finding is `SOLO REPORTE` by
  construction, and the run does not present itself as a complete board review.

---

## Read and write budget

A review reads more than any other workflow and then writes one confirmed
mutation per finding. Either half can run out.

Sample the tracker's budget before the first read and again after each gate's
reads, through the readable rate-limit surface. Without that surface, record
the budget as **unmeasured** rather than guessing one. In repository-only mode
the repository reads still consume the forge's own rate-limit surface, which
is sampled the same way; a read cut short there names the repository evidence
it did not reach.

Declare **coverage** and **budget** in the header:

| Coverage | Meaning | What the run may do |
| --- | --- | --- |
| `full` | Every item in scope read; budget sampled | Full ledger, then the order |
| `full (sin presupuesto)` | Every item in scope read; the readable rate-limit surface is missing, so the budget could not be measured | Full ledger, then the order, under unmetered admission |
| `partial` | A read that is not `deferred` and misses items for any reason: budget, a listing cut short, malformed responses, an `unverified` capability | Ledger of what was read; omitted items named, or, when the listing itself was cut short, the unlisted remainder of the scope declared unread; no order; no finding whose evidence is an unread item |
| `deferred` | Only for the initial read: the measured budget sampled before reading cannot cover listing every item in scope (the minimum a `partial` read needs to name what it omitted) | End the run before Gate 1 is delivered. Report remaining budget and reset time. Propose nothing |
| `n/a (sin tracker)` | Repository-only mode | Repository evidence only; a budget-limited repository read names what it omitted |

An unmeasurable budget is never `deferred`.

**A `partial` read ends at the Gate 1 close.** The ledger is still worth
delivering and its confirmed subset is still worth applying, but there is no
order: Gate 2 ranks the board, and a board only partly read cannot be ranked
without inventing the rest. Say that Gate 2 is deferred pending a full read and
what budget would allow one. The same holds when the board re-read after the
Gate 1 writes comes back `partial`. A board re-read after the Gate 2 writes
that comes back `partial` only marks Gate 3's final backlog state `partial`,
with the omitted items named by the same rule.

### Write admission

Writes are admitted **once per gate, before its first write**.

- **Measured budget.** Admission uses a sample taken after that gate's reads.
  The projection covers every confirmed write, its readback, and the board
  re-read that follows. Either the whole confirmed set fits and is applied, or
  nothing is applied and the run reports the projected cost and the reset
  time.
- **Unmeasured budget.** The set is applied in order and the first rejection
  stops it.

The header states which admission applies (`presupuesto: medido|sin medir`).
A partial prefix is only ever the result of a tracker rejection, never of a
choice the run made: the next reader cannot tell which findings landed.

---

## Mutation authority

Confirmation **in the conversation** is the write authority. There is no flag:
no flag is required, and no flag is accepted as a substitute. No mutation
happens before the maintainer answers the gate that proposes it, and before
writing, the run shows the exact set — item identifiers and values — it is
about to write.

Every action the run can propose belongs to exactly one class:

| Class | Actions | What authorizes it |
| --- | --- | --- |
| Gate-confirmable writes | Upward status changes; classification changes; the two label corrections of 1c (remove a superseded classification hint, add a missing `integration-branch:<slug>` shared by an epic's siblings); priority changes — **only in Gate 2**. Gate 1 may recommend a priority, never write it | A gate answer by identifier, range, or class |
| Explicit-confirmation actions | Cancel or close an item; merge duplicates; create an item | A confirmation naming that item, or a group the run presented by name (such as a duplicate group). A class, range, or gate-wide answer is refused, and the run asks for the explicit per-item or per-group form |
| Report-only | Body, title and description edits (delivered as proposed text); status regressions; dependency edits; tracker rank fields; any epic status write | Nothing. No answer makes them applied |

Rules for the explicit-confirmation class:

- Item creation runs [`00-add-backlog-item-protocol.md`](00-add-backlog-item-protocol.md)
  once per confirmed item.
- Cancel/close needs the item closure capability; duplicate merge needs the
  duplicate relation capability. When the capability is missing, the confirmed
  action is not performed and is delivered under `PENDIENTE DE TI` naming the
  missing capability.
- The obligation binds every Gate 1 and Gate 2 answer and is discharged at the
  gate close, before admission: the run checks each explicit-confirmation
  action against the answer that authorized it and refuses any that a class,
  range, or gate-wide answer would otherwise cover.
- Confirmed explicit-confirmation actions end, like every other write, as
  `aplicado`, `drift`, `not applied`, or `PENDIENTE DE TI`.

Body edits are always delivered as proposed text under `PENDIENTE DE TI`,
even when the maintainer answers `recomendación` to them. Status regressions,
dependency edits and tracker rank fields are reported only. An epic's status
is never written (1j).

### Write contract

Applies to every gate close:

- Show the exact confirmed set before the first write.
- Admit once per gate (Write admission above).
- Read every written item back and print the **observed value** per row.
- A returned value different from the requested one is `drift` and counts as
  unapplied.
- A readback that fails or cannot be read is a rejection: the item is
  `not applied (readback failed — outcome unknown)` and the gate stops. The
  write may still have landed, so the report says the outcome is unknown, not
  that the write did not happen.
- A tracker rejection mid-write stops the gate at once: report the applied
  prefix (the last identifier that read back clean), list everything after it
  as `not applied (<reason>)`, and report the recovery step that resumes from
  the first unapplied identifier. Do not retry inside the run.
- **Reconcile before resubmitting.** The recovery step re-reads every
  `not applied` item whose write was sent (a failed readback, a malformed or
  timed-out response) and resubmits only a write the re-read proves did not
  take effect. An item creation is never replayed until the tracker has been
  searched for the item the first attempt may have created, so a recovery
  never produces a duplicate.
- Malformed tracker responses during writes and their readback are
  rejections; they never count as applied.

---

## Step 1: Read the board

Resolve scope (Scope above) and capabilities (Capability detection) first.
Then fetch every item in scope whose status is not terminal, plus every item
carrying the merged status, plus every item that is still open in the tracker
and has children (an **open epic**, whatever its status), with: identifier, title, status, priority (when
the priority field is detected), classification and labels (when their
capabilities are detected), assignee, `createdAt`, `updatedAt`, due date,
description, **every comment posted after the body's last edit**, and
parent/child or dependency links when those capabilities are detected.

Items carrying the merged status are read because the landed-work sweep
promotes them to the released status once a release section carries their
whole scope; a read set that stops at non-terminal items misses that drift.

A fixed tail of comments is not a substitute: a scope decision can be followed
by any number of unrelated comments. Read to the body's last edit. When the
tracker does not expose the body's last-edit time, read **every** comment
instead, say so once in the header (`historial: sin hora de edición del
body`), and apply conditions 2 and 3 below without condition 1; hold an item
only when two comments that each pass conditions 2 and 3 disagree.

Comments can supersede the body, but recency alone is not authority. Let a
comment supersede the body only when all three hold, and otherwise hold the
item with the conflict named:

1. The comment is newer than the body's last edit.
2. The comment reads as a decision ("Decision: …", "We will …", "Out of scope:
   …"), not a question or a proposal.
3. The comment comes from someone entitled to decide: the item's owner, the
   requester, or whoever holds the scope.

Also read repository evidence that can contradict the tracker:

- `docs/project/backlog-review-precedents.md`, when it exists — the decisions
  earlier runs recorded, so a settled shape of finding is not re-argued. The
  template ships no copy; each repository creates its own from Gate 3 output.
- workflow branches (`spec/*`, `implementation-plan/*`, `feature/*`, `fix/*`,
  `refactor/*`, `hotfix/*`) mapped to their identifier;
- development folders under `docs/specs/developments/`;
- open, merged, and closed PRs that reference an identifier;
- the release sections of `CHANGELOG.md` and pending `changelog.d/` fragments.

Unknown or malformed tracker responses during reads are unread items: they
lower coverage to `partial` and are named. They never count as a missing
capability.

---

## Gate 1 — Structural ledger

This is the **first output** of the run. Nothing is applied before it.

Run every check below that applies to the detected capabilities. Report each
as `ok`, as numbered findings, or as `no aplica — <capability>`.

### 1a. Status drift against evidence

Compare the tracker Status with what the repository proves. The tracker wins
when evidence is ambiguous; the evidence wins when it is unambiguous. Each row
maps evidence to a (stage, event) pair; resolve the expected Status through
[`tracker-status-mapping.md`](../tracker-status-mapping.md) or
`tracker-status-for.sh`, never from memory.

| Evidence | Expected Status |
| --- | --- |
| No branch, no folder, brief only | the initial backlog status |
| Spec branch or PR, never yet human-ready | `S(spec, dispatch)` |
| Spec PR ready for human review | `S(spec, ready-for-human-review)` |
| Spec PR merged, no plan | `S(spec, merged)` |
| Plan branch or PR, never yet human-ready | `S(plan, dispatch)` |
| Plan PR ready for human review | `S(plan, ready-for-human-review)` |
| Plan PR merged, no implementation branch | `S(plan, merged)` |
| Implementation branch or PR, never yet human-ready | `S(implementation, dispatch)` |
| Implementation PR ready for human review | `S(implementation, ready-for-human-review)` |
| Implementation PR returned for fixes (`needs-fixes`) | unchanged: `needs-fixes` maps to no change |
| Implementation PR merged | the merged status |
| Shipped in a release section of `CHANGELOG.md` | the released status |

A PR that was **reviewed and returned for fixes** keeps the status its review
put it at. Moving it back to the `dispatch` status of its stage would be a
status regression. Draw the line on the review phase, not the label: a PR that
never carried `ready-for-human-review` is still at `dispatch`; a PR that
carried it and was later labelled `needs-fixes` stays at
`ready-for-human-review`. When the label history cannot establish the review
phase, propose no move in either direction and raise a status question.

The evidence co-exists, so **the most advanced evidence that is currently true
wins**, highest first: released, merged, implementation stage events, plan
stage events, spec stage events, the initial backlog status. Consequences:

- A merged implementation PR proves only that its own scope landed. An item
  with several parts keeps a non-terminal status for the uncovered scope.
  Read the PR's diff or description against the item's scope; a matching
  title is not scope coverage.
- Earlier-stage evidence never downgrades a later stage.
- Only **open** PRs and **unmerged, non-stale** branches hold an item below
  the merged status. A branch whose PR closed without merging is absent.
- **Where it merged is a separate fact.** A child PR merged only into an
  integration branch (`develop-<slug>`) has not reached the branch the rest of
  the backlog builds against; Protocol 95 holds that branch until
  `/graduate-development <slug>` runs. Say so in the row —
  `merged a develop-<slug>, sin graduar` — and do not treat it as available to
  work targeting `develop`.
- Release notes are the authority for the released status only when the
  released section covers the item's **whole** scope. A partially shipped item
  takes neither terminal status: it keeps the non-terminal status of its
  remaining work, with the shipped half named. If the remaining scope is large
  enough to be its own item, propose the split.
- When the advanced evidence cannot be confirmed, the item keeps its current
  status and the gap is reported.

A title that claims its own state ("… — FIXED", "[DONE]", "[duplicate of X]")
is a finding: the claim belongs in Status, not in the title.

### 1b. Completeness

An item is actionable when the next agent can start from it without asking.
Check for: a body that states the problem and the expected outcome; an
acceptance signal; a scope boundary when the title could be read two ways; a
`## Design assets` section for visual work; a verification hint when the
change is user-visible. Report missing sections per item as proposed text.
Never write them.

### 1c. Classification and labels

Classification values, the heuristics for inferring them, and the
framework-mode rule are defined in
[`00-add-backlog-item-protocol.md`](00-add-backlog-item-protocol.md). This
protocol does not restate them. Infer the classification with those
heuristics; where the item's shape does not resolve, raise a
`NECESITA TU CRITERIO` question instead of guessing.

**The classification carrier is a detected capability.** State which carrier
was detected in the run header:

| Carrier | How to read it | How the write is applied and read back |
| --- | --- | --- |
| Native type field | The field value | Set the field; the returned value must match |
| Single-select classification field | The selected option | Set the option; the returned option must match |
| One dedicated classification label per item | Which known classification label the item carries | Replace the label; read back and assert exactly one known classification label remains |
| None detected | — | `no aplica — classification carrier`: report the inferred classification as context, write nothing |

On a label-carried classification the label **is** the classification: never
report it as a superseded hint.

**Labels** (only when free-form labels are detected; otherwise
`no aplica — free-form labels` for this half, and the classification half
still runs):

| Label family | Owner | What the review checks |
| --- | --- | --- |
| Superseded classification hints (the legacy labels Protocol 00 says not to apply) | Legacy | Removable **only when** a field carrier holds the classification. Never proposed for addition |
| `integration-branch:<slug>` | Protocol 00 epic creation | Present and consistent on every child of an epic that has one; a missing or divergent slug is a finding (needs parent/child hierarchy to list siblings) |
| `epic` | Protocol 00 epic creation | Present on containers, absent on leaves |
| Readiness and closeout labels written by other protocols (`ready-for-human-review`, `needs-fixes`, `reviewer-failed`, `hotfix`) | The protocol that wrote them | Read-only. A stale one is reported, never removed |

Label corrections are exactly two: **remove** a superseded classification
hint, or **add** a missing `integration-branch:<slug>` that the epic's
siblings already carry. Anything another runner may consume is reported.

### 1d. Duplicates and near-duplicates

Group candidates by shared tokens in title and body. A group is `confirmed`
only with concrete evidence: the same reproduction, the same file and symptom,
or an explicit "duplicate of" reference. Token overlap alone is `suspected`.

Report each group with the survivor, the members to merge, and what each would
contribute. The merge is an explicit-confirmation action for that named group;
the survivor's rewritten scope is a body edit and stays proposed text.

A member of a confirmed duplicate group never also appears as a status row in
`LISTO PARA CONFIRMAR`, even when its scope already shipped: the explicit
group confirmation governs it, so a range or class answer can never stamp a
duplicate with a terminal status. Cite the shipped evidence in the group row.

### 1e. Dependencies

- A dependency on an item carrying the merged or released status is satisfied:
  report it for removal. **Check the merge target first**: a prerequisite
  merged only into an ungraduated integration branch is satisfied on that
  branch only and stays blocking for work targeting `develop`.
- Two items where one is a hard prerequisite of the other but no link exists
  are a `missing_dependency` finding, using Protocol 90's `Dependent` /
  `Orthogonal` / `Unclear` vocabulary.
- A cycle is always a finding.

Dependency edits are report-only.

### 1f. Aging and size

- `updatedAt` older than `--aged-days` while still at the initial backlog
  status: schedule it or stop pretending it is queued.
- Created long ago, never specified, superseded by later items: propose
  cancel (explicit-confirmation action).
- Scope that reads as XL with no plan and no split: propose a split.

Aging is a question, not a verdict.

### 1g. Every open question carries a recommendation

Every question that needs the maintainer's judgement carries exactly one
recommendation:

- **Recomiendo:** one concrete action, not a menu.
- **Por qué:** the evidence from this run that decided it.
- **Si no:** what overriding it costs, or plainly that it costs nothing.
- **Confianza:** `alta` when the evidence is verifiable in the repository,
  `media` when it rests on reading intent, `baja` when the run could not
  verify the enabling fact — and `baja` names what it could not verify.

A restatement of the options is not a recommendation. When the evidence does
not decide, recommend the reversible option and say why reversibility breaks
the tie. A missing recommendation is a defect. When the maintainer overrides
one, Gate 3 records the override as a precedent.

### 1h. Verify the item's own claim before recommending on it

An item's title and body are a claim, not evidence. Before a finding that
relies on an item being done, superseded, or duplicated, check the claim and
cite what was checked:

| Claim | Where to check |
| --- | --- |
| "fixed" / "landed" / "guarded" | the named behaviour exists, is wired, and is on the target branch |
| "superseded by X" | X exists, is further along, and covers this scope |
| "duplicate of X" | the bodies describe the same defect, not the same topic |
| "blocked on X" | the tracker relation exists |
| "this is just a record" | whether the item still produces work someone could pick up |

When claim and evidence disagree, the evidence wins and the disagreement is a
finding. A finding whose evidence would be an unread item (on a `partial`
read) is held, never guessed.

### 1i. Landed-work sweep (mandatory)

The commonest real drift is an item whose own body says the fix shipped while
its status never caught up. Run this sweep on the whole live set on every full
run, not on a sample:

1. Search bodies **and comments** for landed-but-filed phrases. The list is a **seed, not
   exhaustive**: `fixed in this branch`, `landed in the same change`,
   `already fixed`, `fixed on <date>`, `fixed in the same change`,
   `FIXED —`, `file it anyway`, `for the record`. A phrase only nominates a
   candidate; items with no phrase are still covered by 1a.
2. For each candidate, decide first whether the text is a claim about the
   item's own work. A negated match ("not already fixed"), an incidental token
   match, a classification label, quoted template prose, or a statement about
   another item is **no claim**: report the candidate as `no claim` and move
   on.
3. For a real claim, locate the **implemented behaviour** on the target
   branch. The sentence is not the evidence. A merged spec, plan or test does
   not prove the implementation shipped.
4. Classify by the 1a precedence. Per candidate, the artifact is: merged and
   covering the whole scope (the merged status, or the released status when a
   release section carries that whole scope); merged but partial (the item
   survives on the uncovered half at its non-terminal stage); on a **live**
   unmerged branch (`S(implementation, dispatch)`, naming the branch and its
   PR state); on an abandoned branch (treated as absent); or absent (the claim
   is wrong and the body needs correcting).
5. Report status changes in `LISTO PARA CONFIRMAR` with the artifact and
   where it was found; body corrections and retitles in `SOLO REPORTE` as
   proposed text.

### 1j. Epic sweep (mandatory)

Needs the parent/child hierarchy capability; without it, report
`no aplica — parent/child hierarchy` and move on. Never substitute a label or
a body convention for real hierarchy.

For each open epic (read in Step 1 whatever its status, so an epic whose
status already reads terminal while it still has open children is swept):

1. List its children and their states through the hierarchy. The list must be
   **nonempty and successfully read** before any conclusion; an empty list is
   held, not closed. Record each child's merge target.
2. **Precedence: case 7 wins.** When any child's only merge is an ungraduated
   integration branch, that is the epic's single outcome.
3. Every child carries the merged or released status on the trunk (or on a
   graduated integration branch) **and** the epic's body has no remaining
   scope → the epic is done. Closing it is an explicit-confirmation action
   under the item closure capability; it writes no workflow stage Status.
4. Every child shipped **but** the epic's body still carries scope →
   `NECESITA TU CRITERIO`, quoting the remaining scope, recommending a split
   or the stage that remaining work is at. Confianza `media`.
5. Some children shipped, some live → report in `SOLO REPORTE`, naming the
   remaining child. Do not move the parent.
6. No child shipped → if none is dispatchable, report it as not dispatchable
   naming the blocker; if one is, recommend dispatching that child
   (`/run-item <child>`).
7. A child merged only into an ungraduated `develop-<slug>` → report the
   integration branch, the children waiting on it, and
   `/graduate-development <slug>`. Do not close or move the parent.

**The run writes no epic status.** Every epic status outcome is report-only,
whatever the answer, so the same confirmation never produces a write on one
runner and a report on another. The run never infers a parent's stage from a
child's artifact in either direction, and an epic is never moved to a child's
stage. Every open epic leaves this check with exactly one reported outcome or
`no aplica`; an epic that matches no case is a finding about the check itself.

A container whose children are all high priority while it carries none will
not sort with them: recommend the priority; Gate 1 never writes it.

### Ledger format

Three blocks, split by what happens after the maintainer answers. Prose in
this protocol is English; the report labels are Spanish by design, because the
report is answered by the backlog owner in the language they work in. The
labels (`LISTO PARA CONFIRMAR`, `SOLO REPORTE`, `NECESITA TU CRITERIO`,
`Recomiendo`, `Por qué`, `Si no`, `Confianza`, `no aplica`, `PENDIENTE DE TI`)
are part of the contract the aliases and the smoke runbook rely on.

```text
Backlog Review — <scope> (<cómo se resolvió>)
Capacidades: detectadas <lista> · faltantes <lista> · unverified <lista o "ninguna">
Clasificación: carrier <tipo detectado> (o no aplica — classification carrier)
Leí: <n> abiertos · <k> en estado merged · <m> branches · <p> PRs · <q> releases · cobertura: full|full (sin presupuesto)|partial|deferred|n/a (sin tracker)
Presupuesto: <n> restantes · reset <iso> · presupuesto: medido|sin medir
Más viejo: <ID> (<n>d) · Sin prioridad: <n>/<n> (o no aplica — priority field)
Omitidos: <IDs, "resto no listado", o "ninguno"> (<razón>)

LISTO PARA CONFIRMAR (<n>) — evidencia, sin criterio de producto, el run lo aplica
  A. estado  (<n>)
     A1 <ID> <actual>→<esperado> · <evidencia> · <check de origen>
  B. clasificación/labels  (<n>)
     B1 <ID> → <clasificación> · <razón>
     B2 <ID> quitar <hint heredado> · <qué carrier ya lo cubre>
     B3 <ID> +integration-branch:<slug> · <hermanos que ya lo llevan>
  → responde por ID, rango o clase: "A1 A3 B2-B5 sí, A2 no"

SOLO REPORTE (<n>) — no lo aplica una respuesta de gate
  C. cierres (solo con confirmación explícita por ID)
     C1 <ID> · <evidencia verificada (1h)>
  D. duplicados confirmados (solo con confirmación explícita por grupo)
     D1 <sobreviviente> ← <IDs> · <qué aporta cada uno> · <evidencia>
  E. ediciones de body/título (texto propuesto, nunca aplicado)
     E1 <ID> · <texto propuesto>
  F. dependencias, regresiones de estado, epics
     F1 <ID> · <hallazgo> · <evidencia>
  G. items a crear (solo con confirmación explícita por ID; Protocol 00)
     G1 <título propuesto> · <por qué>

NECESITA TU CRITERIO (<n>)
  1. <ID> <pregunta>
     Recomiendo: <acción> · Confianza: alta|media|baja
     Por qué: <evidencia de este run>
     Si no: <costo concreto, o "sin costo">

ORDEN: no lo propongo todavía. Gate 2 sigue a Gate 1.
```

Rules:

- Every row carries its evidence inline.
- Block letters group by action, not by check; the originating check is cited
  in each row.
- IDs are stable within the run and are what the maintainer answers with.
- `SOLO REPORTE` makes the mutation boundary visible before the maintainer
  answers. A gate answer by range or class never covers rows C, D or G; those
  need the explicit per-item or per-group form, and E and F are never applied.
- When `LISTO PARA CONFIRMAR` exceeds about 30 rows, group by class and let the
  maintainer confirm the class. Grouping never removes the confirmation.
- When `NECESITA TU CRITERIO` exceeds about 7 rows, the read was insufficient;
  say which evidence is missing.
- `recomendación` alone accepts a recommendation as proposed. An accepted
  recommendation whose action is a gate-confirmable write joins the gate's
  confirmed set; one whose action is an explicit-confirmation action still
  needs the explicit form; one whose action is report-only stays report-only.
- Never emit the order here.

### Gate 1 close

Apply exactly the confirmed gate-confirmable writes and the explicitly
confirmed actions, through the configured tracker per
[`issue-tracker.md`](../integrations/issue-tracker.md) (use its deferred-action
protocol when the shell cannot reach the tracker), under the Write contract.
Gate 1 never writes a priority.

Report applied, drift, and not-applied counts with identifiers and the
observed value per row.

**Gate transitions** out of Gate 1:

| Condition | Next |
| --- | --- |
| Coverage `deferred` | End before Gate 1 is delivered; report budget and reset |
| Repository-only mode | Gate 3, closing Gate 1 alone; Gate 2 reported as `no aplica` |
| Coverage `partial` (initial read or the board re-read after the Gate 1 writes) | End at the Gate 1 close; Gate 2 deferred pending a full read |
| Confirmed set rejected, drifted, or refused for budget | End; report the applied prefix, the unapplied identifiers and the recovery step |
| A confirmed cancel, merge, or create action still outstanding (the run could not perform it) | End at the Gate 1 close by default, naming the outstanding actions under `PENDIENTE DE TI`; a later run opens Gate 2. Rank as-is only when the maintainer explicitly asks: record that choice as an override and flag those items in the queue as `retirado — incluido solo porque confirmaste rankear el set tal como está` |
| Everything confirmed applied and read back equal (or nothing confirmed), coverage `full` or `full (sin presupuesto)` | Re-read the board; if the re-read is still full, open Gate 2 with `set vivo: <n> → <m>` |

Grouping findings by class never removes a confirmation, and no transition
skips a gate.

**Early-end delivery.** Any run that ends before Gate 3 prints, in its last
gate close report, the `PENDIENTE DE TI` list (proposed body text, actions the
tracker cannot perform, outstanding explicit-confirmation actions) and the
precedent lines for the overrides recorded so far. A `deferred` run ends before
Gate 1 is delivered, so it has no gate close report and records no overrides.

---

## Gate 2 — Order

Runs only after Gate 1 closed clean on a full read (above). Gate 2 is the only
gate that writes priorities.

### 2a. Reconstruct the order in force

State the order the dispatcher would produce today.

- **Eligibility.** Take the eligible set from Protocol 90's portfolio map
  (Step 1c) and its "can advance" rules, not from status alone. Do not restate
  that table; list wait-only items separately as
  `no despachables (esperando humano)`.
- **Holds.** Items held by an unmet dependency, a missing required input, or
  a tool-fix ordering constraint are named before the order.

The remaining set sorts:

1. **Due date within 2 weeks**, earliest first — outranks priority.
2. **Priority**, highest first, using only the values the dispatcher
   recognizes: the keys of `PRIORITY_RANK` in
   `scripts/development-workflow/workflow-portfolio-scan.py`, read at run
   time. Every other value falls into the routine tier. Read the tracker's own
   priority option list and state which of its values the dispatcher
   recognizes and which collapse to routine; never map a custom value to a
   higher tier by judgement. Unrecognized values are reported as a
   configuration defect with a rename recommendation.
   Without the priority field, the order reconstruction reports
   `no aplica — priority field`: the dispatcher's order cannot be reproduced.
   The run may print the due-date and creation-date order beneath it,
   labelled `solo contexto`, and proposes no queue.
3. **Creation date**, earliest first.

Print that order, then name its defects:

- **Priority as a hiding place.** Untriaged items tie with deliberately
  routine ones. Count them and say what the default does to the order. Needs
  the priority that can be left unset capability; otherwise
  `no aplica — priority that can be left unset`.
- **Age as rank.** The creation-date tiebreak puts the oldest routine item
  first by accident.

### 2b. Scrutinize recent items first

For each item created within `--recent-days`: which item above it does it
beat, and why; which below it does it lose to, and why. Without either
answer, it has no defensible rank yet.

### 2c. Question each rank with named signals

Every priority change cites one signal by name:

| Signal | Effect |
| --- | --- |
| Blocks another in-flight item | raise |
| Blocks a pending release or a stated deadline | raise; due date outranks priority |
| Defect in the path of work currently in flight | raise, ahead of new features |
| Cost grows with delay (security exposure, data loss, legal, dependency rot) | raise |
| Prerequisite for a larger batch | raise to the batch start |
| No cost to delay, nothing depends on it | keep or lower |
| Superseded by later work | propose cancel (explicit-confirmation action) |
| Value unclear after reading the brief | `needs_human` — unclear is not low |

How recently an item was discussed and how easy it looks are not signals.

### 2d. Guard against priority inflation

- **Movement**: more than about a third of live items moving up is the run's
  own doing; re-open the proposal.
- **Concentration**: a tier holding more than half the backlog is reported as
  a property of the backlog; it blocks presentation only when the proposal
  caused or worsened it.

### 2e. Queue format

```text
SET LIMPIO: <n> → <m> tras Gate 1

ORDEN ACTUAL (dispatcher, sin criterio)
  1. <ID> · <título> · <prioridad> · <edad>d
  Valores de prioridad reconocidos: <lista> · colapsan a rutina: <lista>

DEFECTOS DE ESE ORDEN
  - <modo de falla> · <n> items afectados

COLA PROPUESTA — orden dentro del tier: advisory
  1. <ID> <título> — <razón> — <actual → propuesto> — señal: <nombre>
  Sin cambios: <IDs>

DECISIONES ABIERTAS (<n>)
  1. <ID-a> vs <ID-b> → <el trade-off real>
     Recomiendo: <orden> · Por qué: <evidencia> · Si no: <costo> · Confianza: <nivel>
```

Every unchanged item is listed under `Sin cambios`. The **priority tier** is
the durable deliverable; numbering within a tier is advisory because the
dispatcher's tiebreak is creation date. Never write a tracker rank field, even
when the tracker has one. Where order between two items matters because one
blocks the other, name the dependency instead. Open decisions follow 1g.

### Gate 2 close

Apply the confirmed priority, classification, and label changes under the
Write contract. A Gate 2 answer by range or class never authorizes an
explicit-confirmation action.

| Condition | Next |
| --- | --- |
| Confirmed set rejected, drifted, or refused for budget | End; report the applied prefix, unapplied identifiers and the recovery step. Gate 3 does not open |
| Everything applied and read back equal, or nothing confirmed | Re-read the board, print the new effective order next to the proposed queue, open Gate 3 |
| That re-read comes back `partial` | Gate 3 still opens, with its final backlog state marked `partial` and the omitted items named (or the unlisted remainder declared unread) |

---

## Gate 3 — Closeout

```text
APLICADO
  Gate 1: estado <n> · clasificación/labels <n> · acciones explícitas <n>
  Gate 2: prioridad <n> · clasificación <n> · labels <n>
  drift: <n> · not applied: <n> (<razón>)

PENDIENTE DE TI
  <textos de body propuestos, acciones que el tracker no puede hacer (con la
   capacidad faltante), acciones explícitas pendientes, dependencias a editar,
   con el comando dueño y la recomendación de 1g aceptada o sobrescrita>

PRECEDENTES DE ESTA REVISIÓN
  <una línea por override>

ESTADO FINAL  (cobertura: full|full (sin presupuesto)|partial — omitidos: <IDs>)
  set vivo: <n> · sin prioridad: <n> · más viejo: <ID> (<n>d)
  próxima revisión sugerida: <cuándo y por qué>
```

In repository-only mode Gate 3 closes Gate 1 alone: no applied counts, the
repository findings, and the `unverified` tracker side.

Gate 3 never introduces new findings; anything discovered while applying goes
back to the gate that owns it and is reported as pending.

### Precedents

The run **never writes repository files**. It emits the override lines for
the repository's precedent record, `docs/project/backlog-review-precedents.md`
(project-owned; the template ships no copy, and the record never lives under
the template-owned `docs/workflow/` tree, which synchronization overwrites):

```text
- <YYYY-MM-DD> · <forma del hallazgo> · <qué eligió el humano> · <dónde aplica>
```

Only overrides are emitted; accepted recommendations are already in the
tracker. The maintainer folds the lines into their next docs PR. Later runs
read the record in Step 1 and start from the recorded answer; when a
precedent stops applying, say so and emit its removal. When the run ends
before Gate 3, the last gate close report emits these lines (Early-end
delivery).

---

## Non-goals

- Do not dispatch, start, or run any item. Advancing work is Protocols 90, 91
  and 95.
- Do not rewrite item bodies; deliver proposed text.
- Do not reorder by gut: every rank change names a signal.
- Do not ask a question without a recommendation (1g).
- Do not recommend closing, merging, or cancelling on the strength of the
  item's own text (1h).
- Do not skip the landed-work sweep (1i) or the epic sweep (1j) on a full run.
- Do not move an epic to a child's stage.
- Do not skip Gate 1 to deliver an order faster.
- Do not present a `partial` read as full, or apply a self-chosen prefix.
- Do not re-argue a precedent the repository already records.
- Do not let a clean report imply the backlog is small: report counts and the
  oldest live item in the header.

---

## Relationship to other protocols

- **Protocol 96 `/run-work`** is the per-cycle dispatcher entrypoint: a
  read-only scan that decides what to advance now and proposes a batch. This
  review complements `/run-work` and does not replace it: it asks whether the
  set and its order are worth advancing at all. Run the review periodically,
  before batch selection; `/run-work` then selects the batch from the
  reviewed backlog. The review never dispatches.
- **Protocols 90 and 91** consume the order this review examines and advance
  items. When the order is wrong, the fix belongs here, so `/run-work` cannot
  silently disagree with a review.
- **Protocol 00 `/add-backlog-item`** creates items; this review asks whether
  they are actionable and runs Protocol 00 only for an explicitly confirmed
  creation.
- **Protocol 06 `/retrospective`** reviews how work was delivered; this review
  examines what is queued.
- **Protocol 07 feedback triage** promotes outside feedback into items; this
  review keeps the resulting set coherent.

# Cursor Dispatch Profiles

**Spec**: [Cursor Dispatch Profiles](../../../specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md)

This document is the canonical, single source of truth for how a bounded
workflow command behaves when Cursor's handoff behavior differs from what the
framework assumes by default. It applies **only in a Cursor environment**;
other runners are unchanged (see § Cursor scoping). It does not restate the
role and protocol contracts it refers to — where this document and a role's
own contract or protocol disagree about that role's obligations, the role's
contract and protocol prevail, and this document is corrected (see § Pointer
precedence).

---

## Why this document exists

The framework's bounded commands assume that when a run needs a specialist
role — a portfolio orchestrator, an epic runner, a work item runner, a spec
writer, an implementer, a reviewer — the runner can hand the work to that role
as a separate, freshly-scoped context. In Cursor that assumption holds on the
desktop application and breaks under Remote Control, where the orchestration
context a command hands off to frequently cannot hand off again. A context
that absorbs an orchestration role in that situation absorbs that role's
**entire** contract, not a reduced version of it, and absorbing an
orchestration role never grants permission to write or review the work
product inline.

---

## The three profiles

| Code value | Display label | Description |
| --- | --- | --- |
| `cursor-native-handoff` | Native handoff | The current context can hand orchestration to a separate role, and that role can hand stage work onward. Roles run in their own contexts, as designed. |
| `cursor-parent-orchestrated` | Parent orchestrated | Onward handoff is unavailable, so the current context absorbs the full orchestration contract for the active layer and hands off stage work only. |
| `cursor-inline-fallback` | Inline fallback | No handoff is available for the current mutating action — either because no handoff of any kind is available to the run at all, or because, under parent-orchestrated, the specific stage handoff the current action requires has become unavailable (the stage role cannot be reached — not merely that a reachable stage role refused that one action by a tool or permission denial; that case does not transition this profile. When the refusal is a missing credential, GitHub permission, or access token, it is instead handled by the `missing_required_secret_or_permission` named stop condition. When the refusal is a harness tool or local file-path permission denial reported by a stage role dispatched as a subagent, no existing mechanism recovers it; that gap is Out of Scope for this feature and tracked separately as issue #1746) even though the current context's own initial handoff remains available for other actions. The run is read-only: it reports what it can determine and stops before any mutating action. |

**Valid transitions** (the exact wording of the spec's Statuses / Enum Values
section — this document does not add or remove a transition):

- Native handoff → Parent orchestrated when, mid-run, the orchestration role
  the current context handed off to can no longer be relied on for the
  two-hop native path — either because it becomes unreachable outright, or
  because it remains reachable but loses its own onward-handoff capability to
  hand stage work on in turn — while the current context's own initial
  handoff to one further role remains confirmed available at the point of
  discovery.
- Parent orchestrated → Inline fallback when stage handoff also proves
  unavailable — the stage role cannot be reached at all, not merely that a
  reachable stage role reports a specific delegated action was refused by a
  tool or permission denial.
- Native handoff → Inline fallback when, mid-run, the orchestration role the
  current context handed off to can no longer be relied on for the two-hop
  native path, and the current context's own initial handoff has also been
  lost or cannot be confirmed at the point of discovery, so no handoff of any
  kind remains available.
- Any transition is a re-declaration: the run states the new profile and the
  reason before continuing under it.
- Transitions in the permissive direction do not occur mid-run. A run that
  wants a more capable profile than it declared ends and starts again with a
  fresh declaration.
- A declared value that is not one of the three code values above, or a
  declaration with no accountable orchestrator role, does not put any of
  these three profiles in force. It is treated as no declaration at all, and
  does not create a fourth code value.

---

## Declared, not detected

The framework does not promise automatic environment detection, and a run
never treats an undetectable environment as permission to proceed. Profile
selection is **declared** by the run, informed by published indicators of the
environment's behavior, not automatically detected. The indicators an
operator uses to decide which profile applies:

- **Which desktop/session type is this?** Cursor Desktop application sessions
  are native-handoff capable at every layer (confirmed by observation — see
  `agent-model-config.md`). Cursor Remote Control sessions are the
  environment where onward handoff frequently fails. Cursor Cloud Agents have
  not been observed at all.
- **Has this session, or a documented prior session, seen a role fail to hand
  work onward?** If yes, treat onward-handoff capability as unavailable for
  this run (parent-orchestrated) rather than assuming it will work this time.
- **Can the current context reach even one further role at all?** If this
  cannot be confirmed, treat it exactly like "no handoff of any kind
  available" (inline-fallback), never like the more permissive
  parent-orchestrated default.
- **Is the command itself read-only?** A portfolio scan (`/run-work`) is
  read-only under every profile: it always uses the observing posture and
  never escalates itself into execution.

A run never picks a more permissive profile than these indicators support,
and never assumes an unconfirmed fact silently resolves in the permissive
direction.

---

## Handoff availability evaluation order

Handoff availability is evaluated in a fixed order. First, the run confirms
whether the current context can hand orchestration to one further role at all
(**initial handoff**). **Only once initial handoff is confirmed** does the
run go on to evaluate whether that receiving role can hand stage work onward
in turn (**onward-handoff capability**). A profile decision **never evaluates
onward-handoff capability before initial handoff is confirmed**.

- When onward-handoff capability cannot be confirmed once initial handoff is
  confirmed available, the run **treats it as unavailable** and declares
  **`cursor-parent-orchestrated`** as the conservative default until
  confirmed.
- When **initial handoff availability itself cannot be confirmed** as
  available or unavailable, the run treats it the same as no handoff of any
  kind being available: it declares **`cursor-inline-fallback`**, and the run
  stays **read-only** for the remainder of that run. A later confirmation
  that initial handoff is actually available **never upgrades a run in
  place**; the next run declares afresh against the now-confirmed fact.

For an environment or orchestration layer whose handoff behavior has not been
directly observed — including Cursor Cloud Agents — the profile recorded for
it in `agent-model-config.md` is an **explicit assumption**, not an observed
fact, and follows this same conservative-default pattern: the more
restrictive of the profiles under consideration is assumed until confirmed by
observation.

---

## Accountability postures

A declaration states, for the orchestration role that this document names
for the active layer, exactly one of three accountability postures:

- **Personally accountable (absorbed)**: this profile absorbs the role; the
  current context performs it.
- **Handed off intact**: the role is being handed off to a separate context,
  unchanged.
- **Observing**: the current context names the role without claiming
  personal accountability for its mutating work and without asserting it was
  handed off.

`observing` is valid **only at a read-only checkpoint** — a portfolio scan
under any profile (`/run-work`), or any command under `cursor-inline-fallback`
before it stops or completes. A run that reaches a **mutating action** always
declares `absorbed` or `handed off intact`; it never declares `observing` for
a mutating action. The required posture always follows the run's **current
checkpoint**, never whether the run mutated at any earlier point under a
different profile. A declaration of `absorbed` or `handed off intact` at a
checkpoint confined to read-only work does not satisfy the accountability
requirement either — the checkpoint categorically prohibits claiming or
asserting mutating-work accountability there. Both mismatches, and a
declaration naming no role at all under any posture, are treated as a missing
declaration and stop with `dispatch_profile_declaration_missing`.

---

## The declaration block (normative)

Every bounded run states the following block, with these **four field
names**, before its first mutating action (or before it reports, for a
read-only checkpoint). Only the values change per run; the field names and
label spellings below are normative:

```markdown
**Dispatch profile**: Native handoff (`cursor-native-handoff`)
**Accountable orchestration role**: Work Item Runner (item layer)
**Accountability posture**: handed off intact
**Canonical reference**: docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md
```

Re-declarations repeat the block with a **Reason** line when the profile
changes mid-run. Prelude read-only work (`bounded-run-prelude.md`) may
precede this declaration; the declaration itself must still appear
immediately before the first mutating action.

A resumed run in a fresh context declares again — the previous context's
declaration does not carry over.

---

## The three orchestration layers

Each layer names the role it is accountable to, the commands that enter at
that layer, the contract that governs it, and what happens when a
constrained environment prevents a mutating run at that layer.

### Portfolio layer

- **Governing contract**: `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
  and `.cursor/agents/orchestrator.md` / `.claude/agents/orchestrator.md` /
  `.codex/skills/workflow-orchestrator/SKILL.md`.
- **Entering commands**: `/run-work` (read-only scan, always `observing`),
  `/run-items` (explicit multi-item batch, mutating).
- **Constrained-environment behavior**: when onward handoff to a per-item
  Work Item Runner is unavailable, the current context absorbs the portfolio
  layer and follows `91-orchestrate-work-protocol.md` for each item **one at
  a time**, absorbing the item layer per item in turn (see § Per-command
  dispatch decision).

### Epic layer

- **Governing contract**: `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`.
- **Entering commands**: `/run-epic` (mutating; delegated-merge decisions).
- **Constrained-environment behavior**: when onward handoff to a per-item
  Work Item Runner is unavailable, the current context absorbs the epic layer
  and, for each item in turn, the item layer, one item at a time, dispatching
  no Work Item Runner.

### Item layer

- **Governing contract**: `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
  and `.cursor/agents/item-orchestrator.md` / `.claude/agents/item-orchestrator.md`
  / `.codex/skills/workflow-item-orchestrator/SKILL.md`.
- **Entering commands**: `/run-item` (single item, mutating).
- **Constrained-environment behavior**: when onward handoff to the
  Work Item Runner is unavailable, the current context absorbs the item
  layer itself and delegates every stage of product work (spec, plan,
  implement, review) to its stage role.

---

## Perform / hand off / prohibit matrix

Each row points to the governing role contract or protocol instead of
restating it.

| Layer | Current context performs itself | Current context hands off | Prohibited inline |
| --- | --- | --- | --- |
| Portfolio | Scope resolution, eligibility/gate checks, isolation assignments, audit and tracker obligations, completion verification (`90-batch-orchestrate-work-protocol.md`) | Every stage of product work for each item (spec, plan, implement, review), performed by that item's stage roles | Authoring or reviewing product changes; dispatching a Work Item Runner when onward handoff is unavailable |
| Epic | Delegated-merge gates, epic ledger audit, per-item eligibility (`95-run-epic-protocol.md`) | Every stage of product work for each item, and the item layer's own orchestration obligations once absorbed | Authoring or reviewing product changes; dispatching a Work Item Runner when onward handoff is unavailable |
| Item | Branch/PR guards, item eligibility, isolation assignment, review-gate and CI-loop coordination, completion verification (`91-orchestrate-work-protocol.md`) | Spec writing, plan writing, implementation, and review — each to its stage role, with full handoff metadata | Authoring implementation changes inline; reviewing a change inline instead of handing it to the reviewing role |

---

## The context an absorbing role carries

When a context absorbs an orchestration role under `cursor-parent-orchestrated`,
it carries exactly three things:

1. **The governing contract, by reference** — the absorbed role's own agent
   document and protocol, unchanged and in full. The absorbing context does
   not read a summary; it follows the same document the role would have
   followed had it run natively.
2. **The resolved scope of the run** — the item, batch, or epic scope
   already resolved before the profile was declared, unaffected by which
   context is now accountable for the orchestration role.
3. **The handoff arrangement in force** — which layers are absorbed
   (portfolio, epic, item, or a combination when nested layers are absorbed
   together), and which stage roles remain reachable for delegation.

---

## Stage-handoff metadata (parent-orchestrated)

Every stage of work handed off under `cursor-parent-orchestrated` carries the
same handoff metadata the stage would receive through the normal path:

- `BATCH_CONTEXT` (the batch-context marker)
- isolation classification (`isolation`)
- expected worktree path
- expected branch
- approved base branch
- artifact-owning repository (artifact repository root)
- mutation classification

Today's receiving stage-role contracts already stop the stage, using their
own existing contract and protocol, on incomplete metadata for the
isolation-related fields — the isolation flag, worktree path, expected
branch, artifact repository root, approved base, and mutation
classification. This is the receiving stage role's **pre-existing** behavior
toward any handoff it receives, native or absorbed — not a new or reused
named stop condition this document's decision gate introduces.

**Batch-context marker honesty**: the batch-context marker is an exception to
that pre-existing behavior. Today's stage-role isolation rules are keyed on
`BATCH_CONTEXT=true` being explicitly present, so a handoff that **omits**
the marker does not stop the stage today — it falls through to the stage's
main-tree return path instead, because absence and an explicit `false` are
not distinguished there. This document does not change that stage-role
behavior and does not claim the marker's absence already stops the stage;
closing that gap is Out of Scope here and tracked separately as **issue
#1745**.

---

## Repository arrangement (`workflow_hub`)

Obligations tied to repository arrangement — which repository owns
artifacts, where tracker and cleanup work happens, and post-merge cleanup —
follow the **absorbed role's contract**, not the environment. Absorbing a
role under `cursor-parent-orchestrated` in a `workflow_hub` arrangement never
relocates artifact ownership, tracker updates, or post-merge cleanup: a
product-owned item's implementation artifacts still mutate the selected
product repository, and a hub-owned item's artifacts still mutate the hub,
exactly as the absorbed role's own protocol already requires. The absorbing
context resolves `ROUTING_ARTIFACT_OWNER` and the selected product repository
the same way the role would have, before its first mutating action, and
stops on the same missing-routing conditions the role's own protocol already
defines.

---

## Per-command dispatch decision (Decision 7)

| Command | `cursor-native-handoff` | `cursor-parent-orchestrated` (current context absorbs) | `cursor-inline-fallback` |
| --- | --- | --- | --- |
| `/run-item` | Hands the item to the Work Item Runner (`item-orchestrator`), which dispatches stage roles | Absorbs the **item layer** (Protocol 91); dispatches **no** Work Item Runner; delegates each stage to its stage role with full handoff metadata | Read-only; stops at the first mutation with `dispatch_handoff_unavailable` |
| `/run-items` | Absorbs nothing beyond its own routing; dispatches one Work Item Runner per item (Protocol 90 Step 4, parallel where the runner supports it) | Absorbs the **portfolio layer** (Protocol 90) **and**, per item in turn, the **item layer** (Protocol 91); dispatches **no** Work Item Runner; runs the listed items **one at a time**; delegates every stage to its stage role | Read-only; stops at the first mutation with `dispatch_handoff_unavailable` |
| `/run-epic` | Hands each advanceable item to a Work Item Runner | Absorbs the **epic layer** (Protocol 95) **and**, per item in turn, the **item layer** (Protocol 91), one item at a time; dispatches **no** Work Item Runner; delegates every stage | Read-only; stops at the first mutation with `dispatch_handoff_unavailable` |
| `/run-work` | Read-only scan in the current context, `observing` | Same | Same |

Why absorbing both layers under parent-orchestrated: the receiving role (the
Work Item Runner) is reachable but **cannot hand stage work onward**, so
dispatching it risks the recorded environment-level failure. Its item-layer
work is therefore performed by the absorbing context, and only stage work is
handed off. This feature adds no concurrent-scheduling behavior:
parent-orchestrated batch and epic runs are sequential by construction.

---

## Decision gate — full row text (canonical, normative)

The profile declaration is a decision gate: the same inputs must produce the
same outcome and the same next action wherever the gate is described. **The
authoritative matrix is the merged spec's Decision-Gate Consistency Matrix**;
this table reproduces it verbatim so a Cursor session with only this document
in context has the full gate.

**Evaluation order**: declaration validity is checked before handoff
availability. A missing declaration, a declared value outside the three
defined profiles, a declaration with no accountable orchestrator role named,
a declared posture that does not match the run's checkpoint (`observing`
declared at a mutating action, or `absorbed`/`handed off intact` declared at
a read-only checkpoint), or a declared profile that does not match the
profile outcome the rows below already assign to the run's known handoff
facts at the point of declaration — whether more permissive or less
permissive than that assigned outcome — produces
`dispatch_profile_declaration_missing` regardless of what the initial-handoff
or onward-handoff facts are otherwise. This coarse-facts mismatch check
governs the run's initial declaration and any environment-wide re-declaration
of the coarse initial-handoff or onward-handoff-capability facts themselves;
it does **not** supersede the mid-run recovery rows below (native-handoff
mid-run-failure rows and the parent-orchestrated stage-handoff-unavailable
row), each of which validates its re-declaration against its own
action-specific or role-specific reachability fact rather than against this
coarse check. Only once the declaration is structurally valid does the gate
go on to evaluate initial orchestration-handoff availability. Only when
initial handoff is confirmed available does the gate go on to evaluate
onward-handoff capability.

### § Decision gate

| Input observed at any declaration checkpoint (run start or mid-run) | Profile outcome | Required next action for the current context | Prohibited |
| --- | --- | --- | --- |
| Orchestration handoff available, the receiving role can hand stage work onward, and the command is not a read-only portfolio scan | Native handoff | Declare the profile, record that orchestration is handed off intact, hand off, and follow the existing protocol unchanged | Absorbing the orchestration role when handoff is available |
| Orchestration handoff available, the receiving role can hand stage work onward, and the command is a read-only portfolio scan | Native handoff | Declare the profile and the observing posture for the orchestration role, run the scan in the current context instead of handing it off, report | Escalating the scan into execution; treating the scan exception as licence to absorb other orchestration work |
| Orchestration handoff available, but the receiving role cannot hand stage work onward, and the command is not a read-only portfolio scan | Parent orchestrated | Declare the profile and the absorbed layers, perform the absorbed contract in full, hand every stage of product work to its stage role | Authoring or reviewing product changes inline; dropping any absorbed obligation |
| Orchestration handoff available, but the receiving role cannot hand stage work onward, and the command is a read-only portfolio scan | Parent orchestrated | Declare the profile and the observing posture for the orchestration role, run the scan in the current context, report | Escalating the scan into execution |
| Initial orchestration handoff is confirmed available, but onward-handoff capability — whether the receiving role can hand stage work onward — cannot be confirmed as available or unavailable, and the command is not a read-only portfolio scan | Parent orchestrated (conservative default until confirmed) | Declare the profile as parent-orchestrated, record that onward-handoff capability is unconfirmed, perform the absorbed contract in full, hand off stage work only | Declaring native handoff, or any profile more permissive than parent-orchestrated, based on unconfirmed onward-handoff capability; evaluating onward-handoff capability before initial handoff is confirmed available |
| Initial orchestration handoff is confirmed available, but onward-handoff capability — whether the receiving role can hand stage work onward — cannot be confirmed as available or unavailable, and the command is a read-only portfolio scan | Parent orchestrated (conservative default until confirmed) | Declare the profile as parent-orchestrated, record that onward-handoff capability is unconfirmed and the observing posture for the orchestration role, run the scan in the current context, report | Escalating the scan into execution; declaring native handoff based on unconfirmed onward-handoff capability |
| A run currently declared native handoff discovers, mid-run, that the orchestration role it handed off to can no longer be relied on for the two-hop native path (it becomes unreachable outright, or remains reachable but loses its own onward-handoff capability), and initial handoff to one further role remains confirmed available at the point of discovery | Parent orchestrated (re-declared) | Re-declare as parent-orchestrated, absorb the orchestration role per Use Case 3, hand off stage work only from that point forward; mutations already completed before the failure are preserved as they stand and are not undone or retroactively re-verified as a whole | Continuing to depend on the role for the two-hop native path it can no longer support; performing the orchestration role's work inline instead of re-declaring and absorbing it under the parent-orchestrated contract |
| A run currently declared native handoff discovers, mid-run, that the orchestration role it handed off to can no longer be relied on for the two-hop native path (it becomes unreachable outright, or remains reachable but loses its own onward-handoff capability), and the invoking context's own initial handoff capability is also lost or cannot be confirmed at the point of discovery | Inline fallback (re-declared) | Re-declare as inline-fallback with the reason, then stop the next mutating action with the `dispatch_handoff_unavailable` named stop condition (see § Named stop reporting below), the affected work item, and the conditions for proceeding; mutations already completed before the failure are preserved as they stand and are not undone or retroactively re-verified as a whole | Assuming parent-orchestrated is still reachable and absorbing the role; performing the next mutating action inline instead of stopping |
| A run currently declared parent-orchestrated discovers, mid-run, that stage handoff for a specific action is no longer available | Inline fallback (re-declared) | Re-declare as inline-fallback with the reason, then stop that action with the `dispatch_handoff_unavailable` named stop condition (see § Named stop reporting below), the affected work item, and the conditions for proceeding; mutations already completed under parent-orchestrated before this point are preserved as they stand and are not undone or retroactively re-verified as a whole | Performing the affected stage's work inline instead of re-declaring; continuing to declare parent-orchestrated once stage handoff has proven unavailable for that action |
| A run currently declared parent-orchestrated delegates a specific action to the stage role that owns it, and that stage role is reachable and receives the delegation but reports that this specific action was refused because a credential, GitHub permission, or access token it needs is absent — not an inability to reach the role at all, and not a harness tool or local file-path permission denial (Out of Scope; see issue #1746) | Parent orchestrated (unchanged — no re-declaration) | Stop that specific action with the `missing_required_secret_or_permission` named stop condition (see § Named stop reporting below), naming the denied target and the credential or permission the stage role's report identified as needed; remain declared parent-orchestrated, because the stage role's onward-handoff capability for other actions is unaffected | Performing the denied action inline instead of stopping it; retrying the same denied action unchanged; treating this as stage-handoff unavailability and re-declaring inline-fallback |
| No handoff of any kind available, or initial orchestration-handoff availability itself cannot be confirmed as available or unavailable, and the command is read-only | Inline fallback | Declare the profile and the observing posture for the orchestration role, complete the read-only work in the current context, report; when initial handoff availability is unconfirmed rather than confirmed unavailable, record that it is unconfirmed | Escalating the scan into execution; declaring parent-orchestrated or native handoff on unconfirmed initial handoff |
| No handoff of any kind available, or initial orchestration-handoff availability itself cannot be confirmed as available or unavailable, and the command would mutate | Inline fallback | Declare the profile and the observing posture for the orchestration role, report what was determined, stop with the `dispatch_handoff_unavailable` named stop condition (see § Named stop reporting below), the affected work item, and the conditions for proceeding; when initial handoff availability is unconfirmed rather than confirmed unavailable, record that it is unconfirmed | Performing the mutation inline; declaring parent-orchestrated or native handoff on unconfirmed initial handoff |
| Declaration missing at the first mutating action | None in force | Stop before mutating with the `dispatch_profile_declaration_missing` named stop condition (see § Named stop reporting below), the affected work item, and the missing declaration | Assuming a profile and continuing |
| Declared profile value does not match one of the three defined profiles | None in force (treated as a missing declaration) | Stop before mutating with the `dispatch_profile_declaration_missing` named stop condition, the affected work item, and the invalid value alongside the three valid profile values | Assuming a profile and continuing; treating an unrecognized value as any defined profile |
| Declared profile has no accountable orchestrator role named, including an empty or blank value | None in force (treated as a missing declaration) | Stop before mutating with the `dispatch_profile_declaration_missing` named stop condition, the affected work item, and a report that the accountable role is missing | Assuming an accountable role and continuing |
| Declaration missing, invalid, or missing an accountable orchestrator role, and the command is at a read-only checkpoint (a portfolio scan under any profile, or any single-item, multi-item, or epic command operating under the inline-fallback profile before it stops or completes) | None in force (treated as a missing declaration) | Stop before reporting or before the run's next action — the checkpoint's equivalent of "before mutating," since neither a scan nor an inline-fallback run before it stops ever reaches a mutating action — with the `dispatch_profile_declaration_missing` named stop condition, the affected work item, and which part of the declaration was missing or invalid | Reporting scan results, or continuing an inline-fallback run's read-only work, without a valid declaration on record; treating the checkpoint's read-only nature as exempting it from the declaration requirement |
| Declared posture does not match the run's checkpoint: `observing` declared at a mutating action, or `absorbed` or `handed off intact` declared at a read-only checkpoint (a portfolio scan under any profile, or any command under the inline-fallback profile before it stops or completes) | None in force (treated as a missing declaration) | Stop before mutating, or before reporting for a read-only checkpoint, with the `dispatch_profile_declaration_missing` named stop condition, the affected work item, and which posture was invalid for the checkpoint | Assuming the declared posture is valid for a different checkpoint and continuing; substituting the correct posture for the checkpoint without a new declaration |
| Declared profile does not match the profile outcome the rows above already assign to the run's known handoff facts at the point of declaration — whether **more permissive** than that outcome (for example, native handoff declared while initial handoff is already known unavailable, native handoff declared while onward-handoff capability is already known unavailable or merely unconfirmed, or parent-orchestrated declared while initial handoff is already known unavailable) or **less permissive** than that outcome (for example, parent-orchestrated or inline-fallback declared while the facts already assign native handoff, or inline-fallback declared while the facts already assign parent-orchestrated) — **evaluated for the run's initial declaration, or for an environment-wide re-declaration of the coarse initial-handoff or onward-handoff-capability facts themselves.** This row does not apply to a re-declaration produced by one of the mid-run recovery rows above (native-handoff mid-run failure, or parent-orchestrated stage-handoff-unavailable for a specific action): those rows are validated against their own action-specific or role-specific reachability fact, not against this row's coarse outcome, and remain valid even when the coarse facts this row checks have not themselves changed | None in force (treated as a missing declaration) | Stop before mutating, or before reporting for a read-only checkpoint, with the `dispatch_profile_declaration_missing` named stop condition, the affected work item, and the known fact and the outcome it required | Proceeding under the declared profile; treating a known fact as irrelevant to declaration validity; assuming a more conservative or more permissive profile than the facts require is acceptable; inventing correction or acceptance semantics instead of stopping; rejecting a mid-run recovery row's re-declaration under this row's coarse-facts check |

**Mirror surfaces**: every surface below states the same gate and points to
this document rather than restating its rules: the single-item, multi-item,
epic, and portfolio-scan command entrypoints; the portfolio and item
orchestration role documents; the portfolio, single-item, and epic
orchestration protocols; the agent model configuration document; and the
repository's workflow rule file.

**Examples**: see § Worked examples below — this document carries at least
one worked example per profile for a named layer.

### § Absorbed contract

Under `cursor-parent-orchestrated`, the context that absorbs an orchestration
role assumes that role's **complete** published contract — every decision,
guard, gate, isolation assignment, audit obligation, tracker obligation, and
completion verification it owes. A reduced or best-effort version of the
contract is a failed run, not a lighter one. The absorbing context hands off
every stage of product work — specification, planning, implementation, and
review of a change — and never performs it inline.

### § Scan exception

A read-only portfolio scan is permitted in the current context under every
profile — including when orchestration handoff to another role is otherwise
available — because the scan itself changes nothing and is not the
orchestration role's work being absorbed. Under every profile, the scan
declares the observing posture (not absorbed, not handed off) for the
orchestration role named for the active layer. It never escalates itself
into execution.

### § Conservative defaults

See § Handoff availability evaluation order above; the same rules apply at
every declaration checkpoint.

### § Transitions

See § The three profiles → Valid transitions above.

### § Delegation failures

The prohibition on performing product work inline for a context that has
absorbed an orchestration role under `cursor-parent-orchestrated` is **not**
relaxed by any other document's inline-fix fast lane, permission-denial
inline-fallback promise, or similar provision written for a different
dispatch profile or a different accountable context. When a situation arises
that such a provision would normally resolve by acting on the work product
inline, the absorbing context instead **delegates that specific action to
the stage role that owns it**, carrying the same handoff metadata the stage
would receive through the normal path, and then follows one of three
distinct outcomes depending on a fact about that delegation:

1. **Stage role unreachable** — delegation cannot be attempted, or the role
   cannot be reached at all. This is a stable environment fact for the
   remainder of the run: the run applies the Parent orchestrated → Inline
   fallback transition, re-declaring as inline-fallback and stopping the
   mutating action with the `dispatch_handoff_unavailable` named stop
   condition, rather than performing the action itself.
2. **Stage role reachable but reports a missing credential, GitHub
   permission, or access token** — this is a per-action policy fact, not a
   loss of onward-handoff capability. The same stage role may well succeed at
   other actions, so the run does **not** re-declare inline-fallback and does
   not treat this as stage-handoff unavailability. The absorbing context does
   not perform the denied action itself and does not retry the same action
   unchanged; instead it stops that specific action — remaining declared
   parent-orchestrated — with the `missing_required_secret_or_permission`
   named stop condition, naming the denied target and the credential or
   permission the stage role's report identified as needed.
3. **Stage role reachable but reports a harness tool (`Edit`, `Write`, or
   `Bash`) or local file-path permission denial**, dispatched as a subagent
   under Protocol 90/91's batch dispatch mechanism — a failure observably
   similar to, but not covered by, the `SUBAGENT_PERMISSION_DENIAL` contract
   `91-orchestrate-work-protocol.md` defines, which governs solely a Work
   Item Runner subagent reporting that denial to the Portfolio Orchestrator
   and does not define a corresponding contract for a stage role dispatched
   by an item-orchestrator. `missing_required_secret_or_permission` does not
   apply because no credential, GitHub permission, or access token is
   missing; `dispatch_handoff_unavailable` does not apply because the stage
   role was reached. This is not a named stop condition at all. Protocol 90
   Step 4.1's existing inline-fallback path recovers a denied **Work Item
   Runner** at the Portfolio Orchestrator level; it does not cover a denied
   **stage role** dispatched by an item-orchestrator, and routing this case
   there would itself be the inline product work this section prohibits. No
   mechanism in the framework today recovers a denied stage role at this
   level, and this document does not invent one. **This sub-case is Out of
   Scope for this feature** and is tracked separately as **issue #1746**; the
   prohibition on performing product work inline for the absorbing context
   applies to it unqualified, exactly as it applies to every other situation
   this section covers.

### § Named stop reporting

Every stop this decision gate produces reports the exact stop-condition
string, the affected work item, and a concrete human unblocking action, per
`REVIEW.md`'s named-stop contract and `guardrails-enforcement.md` section 4.
This document defines two new condition names — `dispatch_profile_declaration_missing`
and `dispatch_handoff_unavailable` — and reuses the existing
`missing_required_secret_or_permission` condition for the reachable-but-denied-
for-a-credential case, rather than inventing a third new string.

**Pre-branch, explicit-list `/run-items` declaration stops.** For a
declaration stop on an explicit-list `/run-items` invocation **before any
item-scoped artifact exists**, the affected work item is a **single** string:

```text
explicit_list_invocation_targets=<t1>,<t2>,...
```

one `<ti>` per target of the router's normalized target list, in that order.
The serialization is defined over what `run-work-router.sh` actually accepts
(the router, not the Protocol 90 detection prose, is authoritative at this
gate):

- **Router grammar**: arguments are split on commas, edge whitespace is
  trimmed, empty pieces are dropped, and duplicates are removed keeping the
  first occurrence. Each remaining token must resolve as one of: a positive
  integer, optionally `#`-prefixed, that `gh` confirms as a PR or an issue;
  an existing directory under `docs/specs/developments/` (a leading `./` is
  stripped only for the existence test); or a branch that starts with a
  workflow prefix (`feature/`, `fix/`, `refactor/`, `hotfix/`, `spec/`,
  `implementation-plan/`, `plan/`) and exists locally or on `origin`.
  Anything else, including a **tracker identifier such as `ENG-123`**, stops
  at `MODE=ambiguous` before the declaration gate, so the serialization is
  not defined for it.
- Each `<ti>` is the token **exactly as it appears in the router's normalized
  list — verbatim**, with no rewriting: a `#` is never added or removed, case
  is preserved, a `/` in a branch name is kept, and a leading `./` on a
  development-folder path is kept.
- The delimiter is a single comma with no surrounding spaces. **A comma
  cannot occur inside an accepted target** — the router splits every
  argument on commas before resolution, so an input like `feature/x,y`
  becomes the two tokens `feature/x` and `y`. The `,` → `%2C` rule below is
  therefore a **defensive, unreachable-at-the-gate** rule kept only so the
  output stays unambiguously decodable.
- Escaping is **percent-encoded**, applied per target, `%` first so it is not
  double-encoded: `%` becomes `%25`, `,` becomes `%2C`, and any ASCII
  whitespace or control character inside a target becomes `%XX` (uppercase
  hex of the UTF-8 byte). All other bytes are emitted **unchanged**
  (non-ASCII bytes included).
- **Duplicates never reach the gate**: the router removes them before
  resolution (first occurrence kept), by exact string, so `1462` and `#1462`
  are **distinct** tokens and both are rendered as typed; the serialization
  never merges them.
- **A line feed can never appear inside a target**: the router normalizes
  each argument with `IFS=',' read -ra parts <<< "$t"`, which reads only
  through the first newline, so anything after the first line of an argument
  is silently dropped before resolution. This document states this instead
  of showing a `%0A` case. A carriage return is not a line separator for
  `read`, so it stays inside the token and, on the defensive path above,
  would be encoded as `%0D`.
- Encoding is **not idempotent by design**: a target that already contains
  `%25` text is encoded again (`%` becomes `%25`), so decoding once always
  returns the original bytes.
- A single target and an empty target are **unreachable** at this gate (the
  router stops at `MODE=redirect_item` or `MODE=ambiguous` before any
  declaration gate), so the serialization is undefined for them and this
  document never renders a one-target or empty form.

Example: invoked as `/run-items #1462 feature/cursor-dispatch,1771 #1462`
(the comma-separated argument is split and the repeated `#1462` removed by
the router) yields:

```text
explicit_list_invocation_targets=#1462,feature/cursor-dispatch,1771
```

**Report once for the whole invocation**; do not emit one stop per target.
This rule is mirrored verbatim in `guardrails-enforcement.md` section 4's
`dispatch_profile_declaration_missing` row text, in Protocol 90's
explicit-list preamble, and in the merged spec's Named Stop-Condition
Mapping table (each carrying the identical
`explicit_list_invocation_targets=<t1>,<t2>,...` format string).

### § No-named-stop denial treatment

A reachable stage role's harness tool or local file-path permission denial on
a specific delegated action **is not a named stop condition condition at
all** — `missing_required_secret_or_permission` does not apply to it. This
failure is only **observably similar** to the `SUBAGENT_PERMISSION_DENIAL`
contract `91-orchestrate-work-protocol.md` defines, which governs solely a
Work Item Runner subagent reporting that denial to the Portfolio
Orchestrator; no corresponding contract exists today for a stage role
dispatched by an item-orchestrator. It is declared **Out of Scope** and
tracked separately as **#1746**.

---

## Worked examples (one per profile, item layer, plus read-only scan)

**Native handoff, `/run-item`** (Cursor Desktop):

```markdown
**Dispatch profile**: Native handoff (`cursor-native-handoff`)
**Accountable orchestration role**: Work Item Runner (item layer)
**Accountability posture**: handed off intact
**Canonical reference**: docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md
```

The run hands the item to the Work Item Runner (`item-orchestrator`), which
dispatches stage roles per Protocol 91 unchanged.

**Parent orchestrated, `/run-item`** (Cursor Remote Control):

```markdown
**Dispatch profile**: Parent orchestrated (`cursor-parent-orchestrated`)
**Accountable orchestration role**: Work Item Runner (item layer) — absorbed by the current context
**Accountability posture**: personally accountable
**Canonical reference**: docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md
```

The current context performs every Protocol 91 obligation itself and
delegates spec/plan/implement/review work to stage roles with full handoff
metadata; it dispatches no Work Item Runner.

**Inline fallback, `/run-item`** (no handoff of any kind):

```markdown
**Dispatch profile**: Inline fallback (`cursor-inline-fallback`)
**Accountable orchestration role**: Work Item Runner (item layer) — observing only
**Accountability posture**: observing
**Canonical reference**: docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md
```

The run reports what it can determine about the item and stops at the first
mutating action with `dispatch_handoff_unavailable`.

**Read-only scan, `/run-work`** (any profile — shown here under
parent-orchestrated):

```markdown
**Dispatch profile**: Parent orchestrated (`cursor-parent-orchestrated`)
**Accountable orchestration role**: Portfolio Orchestrator (portfolio layer) — observing only
**Accountability posture**: observing
**Canonical reference**: docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md
```

The scan runs in the current context regardless of profile, reports its
findings, and never escalates itself into execution. Acting on the results
requires a **new bounded run with its own declaration**.

---

## Pointer precedence

This document describes how roles behave under each profile; it does not
restate the roles' own contracts. When this document and a role's own
contract disagree about that role's obligations, **the role's contract and
the protocol it follows prevail**, and this document is corrected. This
precedence settles which document is correct about a role's obligations; it
is **not** a licence for a role's own contract or protocol — an inline-fix
fast lane, a permission-denial inline-fallback promise, or any similar
provision written for a different dispatch profile or a different
accountable context — to override `cursor-parent-orchestrated`'s prohibition
on performing product work inline for the context that absorbed the
orchestration role. A context in that position reconciles such a provision
by delegating the affected action to its stage role, per § Delegation
failures above.

Choosing a profile never relaxes an existing guardrail, gate, stop condition,
permission requirement, or human decision point. Profiles determine who
performs the work, not whether the rules apply.

---

## Cursor scoping

The requirement to declare a dispatch profile, and every rule in this
document, applies **only in a Cursor environment**; **other runners are
unchanged** — Claude Code and Codex behavior is unaffected, because the
recorded failure and every named surface are Cursor-specific and the other
supported runners have not been shown to have the same limitation. The
`cursor-parent-orchestrated` stage-delegation rule likewise attaches only to
a declared `cursor-parent-orchestrated` profile, never to a runner that
merely lacks native Work Item Runner handoff.

---

## Related gaps (Out of Scope, tracked separately)

- **#1745** — the batch-context marker's absence does not stop a receiving
  stage role today (see § Stage-handoff metadata → Batch-context marker
  honesty).
- **#1746** — no mechanism today recovers a denied stage role at the
  individual-action level under `cursor-parent-orchestrated` when the denial
  is a harness tool or local file-path permission denial (see § Delegation
  failures, outcome 3, and § No-named-stop denial treatment).

Neither gap is solved by this document; both are referenced so an operator
does not mistake the absence of a mechanism for an oversight.

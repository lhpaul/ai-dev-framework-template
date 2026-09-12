# Cursor Dispatch Profiles — Spec

---

## Overview

The framework's bounded commands assume that when a run needs a specialist role — a portfolio orchestrator, an epic runner, a work item runner, a spec writer, an implementer, a reviewer — the runner can hand the work to that role as a separate, freshly-scoped context. In Cursor that assumption holds on the desktop application and breaks under Remote Control, where the orchestration context a command hands off to frequently cannot hand off again. The framework has never named this situation, so operators discover it mid-run, improvise, and in the recorded case ended up with one context doing orchestration and implementation at once — which collapses the role and model separation the workflow depends on and required a human to intervene.

This feature gives the situation a name and a contract. Every bounded command declares, before it changes anything, which **dispatch profile** is in force and, for the orchestration role that profile names for the active layer, whether the current context is personally accountable for that role or is handing it off intact. Each profile states exactly what the current context must do itself, what it must hand off, and what it must never do inline. The central rule is that a context which absorbs an orchestration role absorbs that role's **entire** contract — every decision, guard, gate, and verification the role owes — and not a reduced version of it; and that absorbing an orchestration role never grants permission to write or review the work product inline.

The guarantee this feature owes its operators is self-service: someone running the workflow under Remote Control should be able to start a single item, an explicit multi-item batch, or an epic, and complete it correctly using the published documentation alone, without a human rescuing the run and without inventing a fallback that quietly drops a gate.

---

## Use Cases

### Use Case 1: A run declares its dispatch profile and accountable role before touching anything

**Actor**: The operator — a human or agent invoking a bounded workflow command in Cursor.
**Preconditions**: A bounded command has been invoked. Its scope is resolved. Nothing has been mutated yet: no file written, no branch created, no pull request or tracker state changed.

**Steps**:

1. The operator reads the published guidance on how to tell which handoff behavior this environment actually supports.
2. The run states which dispatch profile is in force.
3. For the orchestration role named after the layer the command operates at, the run states whether the current context is personally accountable for that role — because this profile absorbs it — or whether the role is being handed off intact to a separate context — because this profile does not absorb it.
4. Only then does the run proceed toward its first mutating action.

**Postconditions**: The profile and the named role's accountability — personally accepted by the current context, or handed off intact — are on the record for this run, before any mutation. Anyone reading the run output afterwards can tell which contract the run was operating under.

**Information shown**:

- The dispatch profile in force, by its display label.
- The orchestration role the current context has taken personal accountability for, or a statement that the role is being handed off intact.
- Where the operator can read what that combination requires.

**Actions available**:

- Accept the stated profile and let the run continue.
- Correct the profile when the operator knows the environment behaves differently from what was assumed, and let the run re-state it.

**Considerations**:

- The declaration is required at the start of every bounded run, including read-only scans, so the record is uniform. What differs by command is what the profile then permits, not whether it was declared.
- A run that reaches a mutating action without a declaration on the record stops. This is the enforcement point: the absence of the declaration is itself a failure, not a detail to be filled in later.
- A resumed run in a fresh context declares again. The previous context's declaration does not carry over, because the environment that produced it may no longer be the environment executing the work.

---

### Use Case 2: Handoff works, and each role runs in its own context

**Actor**: The operator, plus the orchestration and stage roles the command hands work to.
**Preconditions**: A bounded command has been invoked in an environment where the current context can hand work to a separate role, and that role can hand work onward in turn.

**Steps**:

1. The run declares the native-handoff profile and records that the orchestration role is being handed off rather than absorbed.
2. The command hands the run to the orchestration role named for its layer.
3. That role follows its own published contract and hands each stage of work to the stage role that owns it.
4. The run proceeds to a terminal condition under the existing rules.

**Postconditions**: Every role ran in its own context, at its own assigned model tier. The run behaved exactly as it does today.

**Information shown**:

- The profile in force and the fact that orchestration was handed off intact.

**Considerations**:

- This use case exists to establish that the feature changes nothing about the environment where handoff already works. The only addition is the declaration.
- If a handoff that was expected to succeed fails partway through the run — after the orchestration role has already run or mutated state — control returns to the context that invoked the run, rather than the run continuing to depend on a role that has stopped being reachable. Mutations already completed before the failure are preserved as they stand; this transition does not undo or retroactively re-verify them as a whole. The invoking context re-declares before its next mutating action, applying the profile re-declaration Business Rule ("Exactly one profile is in force at a time..."), and from that re-declaration forward it absorbs the orchestration role under the parent-orchestrated profile per Use Case 3, whose contract — including its stage handoffs and its own gates and verification — governs the rest of the run.

---

### Use Case 3: Onward handoff is unavailable, and the current context absorbs the orchestration role

**Actor**: The operator running a mutating bounded command in an environment where the orchestration role cannot hand work onward.
**Preconditions**: A bounded command that may change artifacts has been invoked. The current context can hand work to one further role, but that role cannot hand work onward. This use case is reached either at the start of a run, with nothing yet mutated, or via the mid-run handoff-failure re-declaration described in Use Case 2's Considerations, in which case any mutations completed before that re-declaration are preserved and this profile's contract governs only what happens from the re-declaration forward.

**Steps**:

1. The run declares the parent-orchestrated profile and names the orchestration role it is personally accountable for — the portfolio layer for an explicit multi-item batch, the epic layer for an epic run, the item layer for a single item. Nested layers are absorbed together when a single run spans more than one.
2. The current context performs that role's own work itself: the orchestration decisions, the state inspections and helper invocations the role owns, the guards, the eligibility and gate checks, the isolation assignments, the audit and tracker obligations, and the completion verification the role is required to perform before reporting a run terminal.
3. For each stage of work the role would normally delegate — writing a spec, writing a plan, implementing, reviewing — the current context hands that stage to its stage role, passing the full handoff metadata that stage would have received through the normal path.
4. The run continues to a terminal condition, with every gate and stop condition applied exactly as the absorbed contract requires.

**Postconditions**: The run completed, or stopped at a real terminal condition, with orchestration performed by the current context and every stage of work performed by the role that owns it. No stage of work was authored or reviewed inline by the orchestrating context.

**Information shown**:

- The profile in force and the orchestration role absorbed.
- For each stage handed off, that it was handed off rather than performed inline.

**Actions available**:

- Let the run continue under the absorbed contract.
- Stop the run if the operator does not accept the absorbed accountability.

**Considerations**:

- Absorbing the role does not reduce it. Every obligation the role's published contract carries applies unchanged, including the ones that are easy to skip when a human is watching the run proceed: the guards that run before a branch or pull request is created, the checks that decide whether an item is eligible to start, the delegated-merge gates, and the verification that a reported completion actually happened.
- Absorbing an orchestration role grants no authority over the work product. Authoring implementation changes inline, or reviewing a change inline instead of handing it to the reviewing role, is prohibited under this profile even when the orchestrating context could technically do it.
- When a single run spans more than one orchestration layer, the current context is accountable for all absorbed layers at once, and says so. It does not silently collapse an outer layer's obligations into an inner one's.
- The stage handoff carries the same scope, isolation, branch, base, and repository metadata the stage would have received natively. A stage role that receives less than that stops, as it does today.
- The obligations that belong to a specific repository arrangement — which repository owns artifacts, where tracker and cleanup work happens — follow the absorbed contract rather than the environment. Absorbing a role in a constrained environment never relocates those obligations.

---

### Use Case 4: No handoff is possible at all

**Actor**: The operator in an environment where the current context cannot hand work to any other role.
**Preconditions**: A bounded command has been invoked. No handoff of any kind is available.

**Steps**:

1. The run declares the inline-fallback profile.
2. The run performs only work that changes nothing: reading state, classifying what could advance, and reporting.
3. When the run reaches a point where the next correct action would change an artifact, it stops and reports why.

**Postconditions**: Nothing was mutated. The operator has a report of what the run found and a named reason for the stop, together with what would let the work proceed.

**Information shown**:

- The profile in force.
- What the run was able to determine without mutating anything.
- The named stop reason, and the environments or conditions under which this work can proceed.

**Actions available**:

- Move the work to an environment where handoff is available and re-run.
- Accept the read-only result as the outcome of this invocation.

**Considerations**:

- This profile never becomes a licence to do the work inline because no one else is available. The absence of a capable stage role is a reason to stop, not a reason to substitute the orchestrating context for it.
- A read-only portfolio scan is legitimate and complete under this profile, because scanning mutates nothing. A scan that finishes here has not failed.

---

### Use Case 5: A read-only portfolio scan under a constrained environment

**Actor**: The operator asking what work could advance, without committing to advancing it.
**Preconditions**: The portfolio scan command has been invoked in any environment.

**Steps**:

1. The run declares its dispatch profile.
2. The scan proceeds in the current context regardless of which profile is in force, because it changes nothing.
3. The scan reports what it found and which follow-on commands would act on it.

**Postconditions**: The operator has the scan result and the proposed follow-on commands. No artifact, branch, pull request, label, or tracker field changed.

**Information shown**:

- The profile in force, and that the scan is read-only under every profile.
- The scan result and the commands that would execute the proposed work.

**Considerations**:

- The scan never converts itself into execution. A request to act on what the scan found is a new bounded run, with its own declaration.
- A scan that omits its declaration, or whose declared value is invalid or names no accountable orchestrator role, stops before reporting its findings, with the `dispatch_profile_declaration_missing` named stop condition, the affected work item, and the missing or invalid part of the declaration — the same requirement every bounded run carries under Use Case 1, applied at the scan's own checkpoint since a scan never reaches a mutating action.

---

### Use Case 6: An operator new to the constrained environment runs the workflow from the documentation alone

**Actor**: An operator who has not run this workflow under a constrained environment before, and has no one to ask.
**Preconditions**: The operator has access to the repository documentation and the workflow commands. No prior knowledge of the limitation.

**Steps**:

1. The operator opens a bounded command's documentation, or the orchestration role's documentation, and finds the profile requirement stated there with a pointer to the full guidance.
2. The operator reads the guidance and determines which profile applies to their environment.
3. The operator finds, in one place, what the current context must do itself, what it must hand off, and what is prohibited inline for the layer they are operating at.
4. The operator runs a single item, an explicit multi-item batch, and an epic to a terminal condition without a human rescuing the run.

**Postconditions**: The runs reached terminal conditions under the correct profile. Nothing had to be invented, and no gate was dropped for lack of guidance.

**Information shown**:

- The profile requirement at each entrypoint the operator might start from.
- A single canonical description of the profiles, the orchestration layers, and the do-itself / hand-off / prohibited split.

**Considerations**:

- The canonical guidance describes how roles behave under each profile; it does not restate the roles' own contracts. When the guidance and a role's own contract disagree about that role's obligations, the role's contract and the protocol it follows prevail, and the guidance is corrected. This precedence settles which document is correct about a role's obligations; it is not a licence for a role's own contract or protocol — an inline-fix fast lane, a permission-denial inline-fallback promise, or any similar provision written for a different dispatch profile or a different accountable context — to override the parent-orchestrated profile's prohibition on performing product work inline for the context that absorbed the orchestration role. A context in that position reconciles such a provision by delegating the affected action to its stage role, or, if no stage role is reachable, by following the profile's own stage-handoff-unavailable path — never by performing the action itself (see Business Rules).
- Discoverability is part of the guarantee. Guidance that exists but is only reachable if the operator already knows it exists does not satisfy this use case.

---

## Business Rules

- Every bounded workflow run declares exactly one dispatch profile and, for the orchestration role that profile names for the active layer, whether the current context is personally accountable for that role or is handing it off intact, before its first mutating action.
- A run that has not declared a profile and the named role's accountability stops before mutating anything, rather than proceeding under an assumed profile. A read-only portfolio scan, which never reaches a mutating action, applies this same requirement at its own equivalent checkpoint: it stops before reporting its findings, rather than reporting without a declaration on record, because a scan is a bounded run and Use Case 1's declaration requirement covers every bounded run including read-only scans.
- A declared profile value that does not match one of the three defined profiles, and a declaration whose accountable-role field names no accountable orchestrator role (including an empty value), each count as a missing declaration. The run stops before mutating anything, exactly as it does for an absent declaration, and reports which part of the declaration was invalid.
- Handoff availability is evaluated in a fixed order. First, the run confirms whether the current context can hand orchestration to one further role at all (initial handoff). Only when initial handoff is confirmed available does the run go on to evaluate whether that receiving role can hand stage work onward in turn (onward-handoff capability). A profile decision never evaluates onward-handoff capability before initial handoff is confirmed.
- When initial handoff availability itself cannot be confirmed as available or unavailable, the run treats it the same as no handoff being available at all: it declares inline-fallback, not parent-orchestrated or native handoff, and stays read-only until initial handoff is confirmed by a later declaration.
- When initial handoff is confirmed available but onward-handoff capability — whether the orchestration role the current context hands off to can hand stage work onward in turn — cannot be confirmed as available, the run treats onward-handoff capability as unavailable rather than assuming it works. This is the environment's more conservative capable profile: the run declares parent-orchestrated, not native handoff, until onward-handoff capability is confirmed by a later declaration.
- Exactly one profile is in force at a time. When the environment proves to behave differently from the declared profile, the run re-declares with the reason before continuing, and applies the new profile from that point.
- Under the parent-orchestrated profile, the context that absorbs an orchestration role assumes that role's complete published contract — every decision, guard, gate, isolation assignment, audit obligation, tracker obligation, and completion verification it owes. A reduced or best-effort version of the contract is a failed run, not a lighter one.
- Under the parent-orchestrated profile, the absorbing context hands off every stage of product work — specification, planning, implementation, and review of a change — and never performs it inline.
- The previous rule's prohibition is not relaxed by any other document's inline-fix fast lane, permission-denial inline-fallback promise, or similar provision written for a different dispatch profile or a different accountable context. When the current context has absorbed an orchestration role under the parent-orchestrated profile and a situation arises that such a provision would normally resolve by acting on the work product inline, the absorbing context instead delegates that specific action to the stage role that owns it, carrying the same handoff metadata the stage would receive through the normal path. If no stage role is reachable to receive that delegation, the run applies the parent-orchestrated → inline-fallback transition defined in Statuses / Enum Values: it re-declares as inline-fallback and stops the mutating action with the `dispatch_handoff_unavailable` named stop condition, rather than performing the action itself.
- Stage work handed off under the parent-orchestrated profile carries the same handoff metadata the stage would receive through the normal path, including the batch-context marker, isolation classification, expected branch, approved base, artifact-owning repository, and mutation classification. Incomplete handoff metadata stops the stage, as it does today.
- Under the inline-fallback profile, the run performs only non-mutating work and stops with a named reason at the first point a mutating action would be required.
- A read-only portfolio scan is permitted in the current context under every profile — including when orchestration handoff to another role is otherwise available — because the scan itself changes nothing and is not the orchestration role's work being absorbed. It never escalates itself into execution.
- Choosing a profile never relaxes an existing guardrail, gate, stop condition, permission requirement, or human decision point. Profiles determine who performs the work, not whether the rules apply.
- Profile selection is declared by the run, informed by published indicators of the environment's behavior. The framework does not promise automatic environment detection, and a run never treats an undetectable environment as permission to proceed.
- The canonical profiles guidance describes behavior by reference to the roles' own contracts and protocols and does not duplicate them. Where they conflict, the role contract and protocol prevail. This does not relax the parent-orchestrated profile's prohibition on performing product work inline for a context that absorbed the orchestration role; see the dedicated carve-out rule above.
- Every entrypoint an operator can legitimately start a bounded run from states the profile requirement and points to the canonical guidance, so the requirement cannot be missed by choosing a different starting point.
- Obligations tied to repository arrangement — artifact ownership, tracker updates, and post-merge cleanup — follow the absorbed role's contract and are unaffected by which profile is in force.
- For an environment or orchestration layer whose handoff behavior has not been directly observed — including Cursor Cloud Agents — the profile recorded for it in the agent model configuration document is an explicit assumption, not an observed fact, and follows the same conservative-default pattern as an unconfirmed handoff capability observed mid-run: the more restrictive of the profiles under consideration is assumed until confirmed by observation. The agent model configuration document states, for each environment and orchestration layer it covers, whether the recorded profile is confirmed by observation or is an explicit assumption.

---

## Statuses / Enum Values

| Code value                   | Display label      | Description                                                                                                                                               |
| ---------------------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cursor-native-handoff`      | Native handoff     | The current context can hand orchestration to a separate role, and that role can hand stage work onward. Roles run in their own contexts, as designed.     |
| `cursor-parent-orchestrated` | Parent orchestrated | Onward handoff is unavailable, so the current context absorbs the full orchestration contract for the active layer and hands off stage work only.          |
| `cursor-inline-fallback`     | Inline fallback     | No handoff is available. The run is read-only: it reports what it can determine and stops before any mutating action.                                       |

**Valid transitions**:

- Native handoff → Parent orchestrated when an onward handoff that was assumed available proves unavailable during the run.
- Parent orchestrated → Inline fallback when stage handoff also proves unavailable.
- Native handoff → Inline fallback when no handoff of any kind is available.
- Any transition is a re-declaration: the run states the new profile and the reason before continuing under it.
- Transitions in the permissive direction do not occur mid-run. A run that wants a more capable profile than it declared ends and starts again with a fresh declaration.
- A declared value that is not one of the three code values above, or a declaration with no accountable orchestrator role, does not put any of these three profiles in force. It is treated as no declaration at all, per the missing-declaration business rule, and does not create a fourth code value.

---

## Operational Visibility

- **Run output**: the dispatch profile and the accountable orchestration role appear in the run's output before its first mutating action, and any re-declaration appears at the point it takes effect with its reason.
- **Run summary**: the summary of a completed or stopped run records the profile in force at the end, every profile transition that occurred, and — under the parent-orchestrated profile — which orchestration layers were absorbed and which stages were handed off.
- **Stop reporting**: a run stopped by a missing or invalid declaration (an unrecognized profile value or no accountable orchestrator role named), or by a mutating action required under the inline-fallback profile, reports the exact named stop condition from the Decision-Gate Consistency Matrix section's Named Stop-Condition Mapping (sourced from `guardrails-enforcement.md` section 4), the affected work item, and the concrete human action to unblock — rather than a generic failure or an invented message.

---

## Decision-Gate Consistency Matrix

The profile declaration is a decision gate: the same inputs must produce the same outcome and the same next action wherever the gate is described.

**Evaluation order**: declaration validity is checked before handoff availability. A missing declaration, a declared value outside the three defined profiles, or a declaration with no accountable orchestrator role named produces `dispatch_profile_declaration_missing` regardless of what the initial-handoff or onward-handoff facts are, because an invalid or absent declaration leaves no declared profile to weigh against those facts. Only once the declaration is structurally valid does the gate go on to evaluate initial orchestration-handoff availability — whether the current context can hand orchestration to one further role at all. Only when initial handoff is confirmed available does the gate go on to evaluate onward-handoff capability — whether that receiving role can hand stage work onward in turn. The rows below describing an unconfirmed onward-handoff capability apply only once initial handoff is confirmed available. When initial handoff availability itself cannot be confirmed as available or unavailable, the gate treats it exactly as it treats "no handoff of any kind available" — see those rows below — rather than selecting parent-orchestrated on an unconfirmed initial hop.

| Input observed at run start                                                                                                | Profile outcome                                          | Required next action for the current context                                                                                                | Prohibited                                                                                                |
| --------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| Orchestration handoff available, the receiving role can hand stage work onward, and the command is not a read-only portfolio scan | Native handoff                                            | Declare the profile, record that orchestration is handed off intact, hand off, and follow the existing protocol unchanged                    | Absorbing the orchestration role when handoff is available                                                 |
| Orchestration handoff available, the receiving role can hand stage work onward, and the command is a read-only portfolio scan     | Native handoff                                            | Declare the profile, run the scan in the current context instead of handing it off, report                                                    | Escalating the scan into execution; treating the scan exception as licence to absorb other orchestration work |
| Orchestration handoff available, but the receiving role cannot hand stage work onward, and the command is not a read-only portfolio scan | Parent orchestrated                                    | Declare the profile and the absorbed layers, perform the absorbed contract in full, hand every stage of product work to its stage role         | Authoring or reviewing product changes inline; dropping any absorbed obligation                            |
| Orchestration handoff available, but the receiving role cannot hand stage work onward, and the command is a read-only portfolio scan     | Parent orchestrated                                    | Declare the profile, run the scan in the current context, report                                                                               | Escalating the scan into execution                                                                         |
| Initial orchestration handoff is confirmed available, but onward-handoff capability — whether the receiving role can hand stage work onward — cannot be confirmed as available or unavailable, and the command is not a read-only portfolio scan | Parent orchestrated (conservative default until confirmed) | Declare the profile as parent-orchestrated, record that onward-handoff capability is unconfirmed, perform the absorbed contract in full, hand off stage work only | Declaring native handoff, or any profile more permissive than parent-orchestrated, based on unconfirmed onward-handoff capability; evaluating onward-handoff capability before initial handoff is confirmed available |
| Initial orchestration handoff is confirmed available, but onward-handoff capability — whether the receiving role can hand stage work onward — cannot be confirmed as available or unavailable, and the command is a read-only portfolio scan | Parent orchestrated (conservative default until confirmed) | Declare the profile as parent-orchestrated, record that onward-handoff capability is unconfirmed, run the scan in the current context, report | Escalating the scan into execution; declaring native handoff based on unconfirmed onward-handoff capability |
| A run currently declared parent-orchestrated discovers, mid-run, that stage handoff for a specific action is no longer available | Inline fallback (re-declared) | Re-declare as inline-fallback with the reason, then stop that action with the `dispatch_handoff_unavailable` named stop condition (see Named Stop-Condition Mapping below), the affected work item, and the conditions for proceeding; mutations already completed under parent-orchestrated before this point are preserved as they stand and are not undone or retroactively re-verified as a whole | Performing the affected stage's work inline instead of re-declaring; continuing to declare parent-orchestrated once stage handoff has proven unavailable for that action |
| No handoff of any kind available, or initial orchestration-handoff availability itself cannot be confirmed as available or unavailable, and the command is read-only | Inline fallback | Declare the profile, complete the read-only work in the current context, report; when initial handoff availability is unconfirmed rather than confirmed unavailable, record that it is unconfirmed | Escalating the scan into execution; declaring parent-orchestrated or native handoff on unconfirmed initial handoff |
| No handoff of any kind available, or initial orchestration-handoff availability itself cannot be confirmed as available or unavailable, and the command would mutate | Inline fallback | Declare the profile, report what was determined, stop with the `dispatch_handoff_unavailable` named stop condition (see Named Stop-Condition Mapping below), the affected work item, and the conditions for proceeding; when initial handoff availability is unconfirmed rather than confirmed unavailable, record that it is unconfirmed | Performing the mutation inline; declaring parent-orchestrated or native handoff on unconfirmed initial handoff |
| Declaration missing at the first mutating action                                                                           | None in force                                             | Stop before mutating with the `dispatch_profile_declaration_missing` named stop condition (see Named Stop-Condition Mapping below), the affected work item, and the missing declaration | Assuming a profile and continuing                                                                           |
| Declared profile value does not match one of the three defined profiles                                                    | None in force (treated as a missing declaration)          | Stop before mutating with the `dispatch_profile_declaration_missing` named stop condition, the affected work item, and the invalid value alongside the three valid profile values | Assuming a profile and continuing; treating an unrecognized value as any defined profile                   |
| Declared profile has no accountable orchestrator role named, including an empty or blank value                            | None in force (treated as a missing declaration)          | Stop before mutating with the `dispatch_profile_declaration_missing` named stop condition, the affected work item, and a report that the accountable role is missing | Assuming an accountable role and continuing                                                                |
| Declaration missing, invalid, or missing an accountable orchestrator role, and the command is a read-only portfolio scan   | None in force (treated as a missing declaration)          | Stop before reporting the scan's findings — the scan's equivalent of "before mutating," since a scan never reaches a mutating action — with the `dispatch_profile_declaration_missing` named stop condition, the affected work item, and which part of the declaration was missing or invalid | Reporting scan results without a valid declaration on record; treating the scan's read-only nature as exempting it from the declaration requirement |

**Mirror surfaces** — every surface below states the same gate and points to the canonical guidance rather than restating its rules: the single-item, multi-item, epic, and portfolio-scan command entrypoints; the portfolio and item orchestration role documents; the portfolio, single-item, and epic orchestration protocols; the agent model configuration document; and the repository's workflow rule file.

**Examples**: the canonical guidance carries at least one worked example per profile, showing the declaration and the resulting split of work for a named layer. Examples are part of the changed surface and must agree with this matrix.

**Named Stop-Condition Mapping**: every stop this matrix produces reports the exact stop-condition string named below, the affected work item, and a concrete human unblocking action, per `REVIEW.md`'s named-stop contract and `docs/workflow/development-workflow/guardrails-enforcement.md` section 4. This feature adds the two condition names below to that section's table under its additive rule; an implementation must not invent a different string for either scenario.

| Matrix row(s) | Named stop condition (added to `guardrails-enforcement.md` section 4) | Affected work item | Human unblocking action |
| --- | --- | --- | --- |
| Declaration missing at the first mutating action; declared profile value outside the three defined profiles; declared profile with no accountable orchestrator role named; declaration missing, invalid, or missing an accountable orchestrator role for a read-only portfolio scan (checkpoint: before the scan reports its findings) | `dispatch_profile_declaration_missing` | The branch, pull request, or development-folder path the bounded run was invoked against | Supply a valid declaration — one of the three defined profile values and a named accountable orchestrator role — before the run is allowed to continue past this point |
| No handoff of any kind available, or initial orchestration-handoff availability itself unconfirmed, and the command would mutate; a run already declared parent-orchestrated whose stage handoff for a specific action proves unavailable mid-run | `dispatch_handoff_unavailable` | The branch, pull request, or development-folder path the mutating action would have applied to | Move the run to an environment where initial handoff is confirmed available (native-handoff or parent-orchestrated capable) and re-run, or explicitly accept the read-only result reported for this invocation |

---

## Acceptance Criteria

- [ ] A canonical Cursor dispatch profiles document exists in the framework documentation, published alongside the other integration guidance, and defines the native-handoff, parent-orchestrated, and inline-fallback profiles with the display labels in this spec.
- [ ] The canonical document defines the three orchestration layers — portfolio, epic, and item — and, for each, states the contract that governs it, the commands that enter at that layer, and whether a constrained environment prevents a mutating run at that layer.
- [ ] The canonical document contains a matrix that states, for each layer, what the current context performs itself, what it hands off, and what is prohibited inline; each entry points to the governing role contract or protocol instead of restating it.
- [ ] The canonical document states explicitly that under the parent-orchestrated profile the current context assumes the **full** contract of the role for the active layer, and that absorbing a role confers no authority to author or review product changes inline.
- [ ] The canonical document lists the indicators an operator uses to decide which profile applies at the start of a bounded run, and states that the decision is declared rather than automatically detected.
- [ ] The canonical document describes the context an absorbing role must carry: the governing contract by reference, the resolved scope of the run, and the handoff arrangement in force.
- [ ] The canonical document states the handoff metadata every delegated stage receives under the parent-orchestrated profile, including the batch-context marker, and states that a stage receiving less stops.
- [ ] The canonical document states how artifact-ownership, tracker, and post-merge cleanup obligations behave when a role is absorbed in a repository arrangement where artifacts and product code live in different repositories.
- [ ] Invoking the single-item command, the explicit multi-item command, or the epic command produces a declaration of the dispatch profile and the accountable orchestration role before any mutating action, and a run that reaches a mutating action without one stops with a named reason. Invoking the portfolio-scan command produces the same declaration before the scan reports its findings, and a scan that reaches that checkpoint without a valid declaration stops with the `dispatch_profile_declaration_missing` named stop condition instead of reporting.
- [ ] The canonical document and its mirror surfaces state that handoff availability is evaluated in order — initial handoff first, then onward-handoff capability only once initial handoff is confirmed available — and state the outcome for each of: onward-handoff capability that cannot be confirmed once initial handoff is confirmed available (treated as unavailable, declared parent-orchestrated as the conservative default until confirmed), initial handoff availability that itself cannot be confirmed (treated the same as no handoff of any kind available, declared inline-fallback and read-only), a declared profile value outside the three defined profiles, and a declared profile with no accountable orchestrator role named — with the latter two stated explicitly as equivalent to a missing declaration that stops the run before mutation, matching the Decision-Gate Consistency Matrix.
- [ ] The canonical document and its mirror surfaces state the exact named stop condition (`dispatch_profile_declaration_missing` or `dispatch_handoff_unavailable`, as defined in the Decision-Gate Consistency Matrix section's Named Stop-Condition Mapping), the affected work item, and the concrete human unblocking action for every stop this feature introduces, and `docs/workflow/development-workflow/guardrails-enforcement.md` section 4 is updated to add both named stop conditions with these definitions.
- [ ] The portfolio-scan command documents that scanning runs in the current context and is read-only under every profile — including when orchestration handoff to another role is otherwise available — and that acting on its results requires a new bounded run with its own declaration.
- [ ] The portfolio orchestration role document and the item orchestration role document each state what to do when onward handoff is unavailable: return the run to the context that invoked it rather than proceeding, and perform no product work inline.
- [ ] The portfolio, single-item, and epic orchestration protocols each reference the canonical document at the point a run establishes its execution arrangement, before dispatch or mutation.
- [ ] The agent model configuration document states which profile and which model assignment apply for each combination of supported Cursor environment and orchestration layer, and states for each combination whether that profile assignment is confirmed by observation or is an explicit assumption, per the conservative-default Business Rule for environments and layers whose handoff behavior has not been directly observed.
- [ ] The repository's workflow rule file states the profile-declaration requirement and points to the canonical document.
- [ ] An operator who has never run the workflow under a constrained environment can reach the canonical guidance from any bounded command entrypoint or orchestration role document, and can run a single item, an explicit multi-item batch, and an epic to a terminal condition using the documentation alone, with no gate dropped and no human rescue.
- [ ] Every profile, layer, and orchestration-role name is spelled and labelled identically across the canonical document, the command entrypoints, the role documents, the protocols, the model configuration document, and the workflow rule file.
- [ ] The canonical document states that no other document's inline-fix fast lane, permission-denial inline-fallback promise, or similar provision relaxes the parent-orchestrated profile's prohibition on inline product work for the context that absorbed the orchestration role, and states that such a situation is resolved by delegating the affected action to the stage role that owns it or, if no stage role is reachable, by applying the parent-orchestrated → inline-fallback transition and stopping with the `dispatch_handoff_unavailable` named stop condition.

---

## Out of Scope (MVP)

1. **An explicit profile-override flag on the bounded commands.** The brief offers this as an optional later phase. Deferral rationale: the declaration requirement and the profile contracts are what unblock the operator; an override flag is an ergonomic addition that only makes sense once the declared-profile behavior is in use, and adding a flag surface now would spread the contract across command syntax before it has settled. Human confirmation requested before it is scheduled.

2. **Changing how Cursor Remote Control or Cloud Agents behave.** Declared out of scope in the brief. Deferral rationale: the product behavior is not the framework's to change; this feature adapts the workflow to it. No human confirmation requested.

3. **Automatic detection of the environment from the repository or the shell.** Declared out of scope in the brief, which records that no reliable signal exists. Deferral rationale: a detector that is wrong is worse than a declaration that is explicit, because it would silently pick a profile that permits work the environment cannot support. No human confirmation requested.

4. **Restating role and protocol contracts inside the canonical document.** Declared out of scope in the brief. Deferral rationale: duplicated contracts drift, and the drift would be invisible until a run followed the stale copy. The canonical document refers to the contracts instead. No human confirmation requested.

5. **Documenting the repository-identifier format used by the retrospective cross-reference step.** Raised as a closing note in the brief. Deferral rationale: it concerns retrospective cross-referencing and template configuration commentary, and shares no surface with dispatch profiles; folding it in would widen this item's blast radius across unrelated files. Human confirmation requested on whether to open a separate work item for it.

6. **Dispatch profiles for runners other than Cursor.** Deferral rationale: the recorded failure and every named surface in the brief are Cursor-specific, and the other supported runners have not been shown to have the same limitation. Generalizing without evidence would invent contracts for environments no one has observed failing. Human confirmation requested if other runners are later found to be affected.

7. **Changing any model tier assignment.** Deferral rationale: this feature records which assignment applies in which environment and layer; deciding that a tier should change is a separate product decision with its own cost and quality trade-offs. No human confirmation requested.

8. **An inline-fallback mutation escape hatch for operators with no capable environment available.** Raised as Open Question 1 in an earlier draft of this spec. Deferral rationale: every other current-scope rule — Use Case 4, the Business Rules, the `cursor-inline-fallback` enum definition, and the acceptance criteria — categorically requires inline-fallback to stay read-only and stop; an implementation cannot both enforce that invariant and preserve an exception, so the MVP contract keeps inline-fallback categorically read-only and defers the escape-hatch question rather than deciding it here. Human confirmation requested on whether to schedule an approved escape hatch as a later feature.

---

## Open Questions

1. Under the parent-orchestrated profile, one context is accountable for the portfolio layer for an entire explicit multi-item batch. Should such a batch still run its items concurrently, or should it be documented as running items one at a time in this environment, given that a single context is supervising every item itself?

> Resolved — this note closes the **former** Open Question 2 (Cursor Cloud Agents' profile-per-layer assignment), not the current Open Question 1 above (batch concurrency), which remains open: the former question is answered by the new Business Rule on unobserved environments and by Acceptance Criterion 15 — the agent model configuration document records Cloud Agents' assignment as an explicit assumption under the same conservative-default pattern used elsewhere, unless and until it is confirmed by observation, rather than leaving it undecided.

> Resolved — this note closes the **former** Open Question 1 (whether an operator with no capable environment available should have an explicitly approved, recorded escape hatch that permits inline-fallback to mutate): Out of Scope item 8 above defers that decision rather than leaving it open as an unresolved contradiction. For the current MVP scope, the answer is categorical and matches every other current-scope rule: there is no escape hatch, and inline-fallback stays read-only and stops with the `dispatch_handoff_unavailable` named stop condition, exactly as Use Case 4, the Business Rules, the enum definition, and the acceptance criteria already require. Whether to build an approved escape hatch later is preserved as the human-facing deferral question in Out of Scope item 8, not as an open contradiction in this contract.

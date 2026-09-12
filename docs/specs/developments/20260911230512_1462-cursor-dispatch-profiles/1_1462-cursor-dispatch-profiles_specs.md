# Cursor Dispatch Profiles — Spec

---

## Overview

The framework's bounded commands assume that when a run needs a specialist role — a portfolio orchestrator, an epic runner, a work item runner, a spec writer, an implementer, a reviewer — the runner can hand the work to that role as a separate, freshly-scoped context. In Cursor that assumption holds on the desktop application and breaks under Remote Control, where the orchestration context a command hands off to frequently cannot hand off again. The framework has never named this situation, so operators discover it mid-run, improvise, and in the recorded case ended up with one context doing orchestration and implementation at once — which collapses the role and model separation the workflow depends on and required a human to intervene.

This feature gives the situation a name and a contract. Every bounded command declares, before it changes anything, which **dispatch profile** is in force and which orchestration role the current context is personally accountable for. Each profile states exactly what the current context must do itself, what it must hand off, and what it must never do inline. The central rule is that a context which absorbs an orchestration role absorbs that role's **entire** contract — every decision, guard, gate, and verification the role owes — and not a reduced version of it; and that absorbing an orchestration role never grants permission to write or review the work product inline.

The guarantee this feature owes its operators is self-service: someone running the workflow under Remote Control should be able to start a single item, an explicit multi-item batch, or an epic, and complete it correctly using the published documentation alone, without a human rescuing the run and without inventing a fallback that quietly drops a gate.

---

## Use Cases

### Use Case 1: A run declares its dispatch profile and accountable role before touching anything

**Actor**: The operator — a human or agent invoking a bounded workflow command in Cursor.
**Preconditions**: A bounded command has been invoked. Its scope is resolved. Nothing has been mutated yet: no file written, no branch created, no pull request or tracker state changed.

**Steps**:

1. The operator reads the published guidance on how to tell which handoff behavior this environment actually supports.
2. The run states which dispatch profile is in force.
3. The run states which orchestration role the current context is personally accountable for under that profile, named after the layer the command operates at.
4. Only then does the run proceed toward its first mutating action.

**Postconditions**: The profile and the accountable role are on the record for this run, before any mutation. Anyone reading the run output afterwards can tell which contract the run was operating under.

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
- If a handoff that was expected to succeed fails partway through the run, the run moves to the situation in Use Case 3 and re-declares rather than continuing under a profile that is no longer true.

---

### Use Case 3: Onward handoff is unavailable, and the current context absorbs the orchestration role

**Actor**: The operator running a mutating bounded command in an environment where the orchestration role cannot hand work onward.
**Preconditions**: A bounded command that may change artifacts has been invoked. The current context can hand work to one further role, but that role cannot hand work onward. Nothing has been mutated yet.

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

- The canonical guidance describes how roles behave under each profile; it does not restate the roles' own contracts. When the guidance and a role's own contract disagree about that role's obligations, the role's contract and the protocol it follows prevail, and the guidance is corrected.
- Discoverability is part of the guarantee. Guidance that exists but is only reachable if the operator already knows it exists does not satisfy this use case.

---

## Business Rules

- Every bounded workflow run declares exactly one dispatch profile and the orchestration role the current context is personally accountable for, before its first mutating action.
- A run that has not declared a profile and accountable role stops before mutating anything, rather than proceeding under an assumed profile.
- Exactly one profile is in force at a time. When the environment proves to behave differently from the declared profile, the run re-declares with the reason before continuing, and applies the new profile from that point.
- Under the parent-orchestrated profile, the context that absorbs an orchestration role assumes that role's complete published contract — every decision, guard, gate, isolation assignment, audit obligation, tracker obligation, and completion verification it owes. A reduced or best-effort version of the contract is a failed run, not a lighter one.
- Under the parent-orchestrated profile, the absorbing context hands off every stage of product work — specification, planning, implementation, and review of a change — and never performs it inline.
- Stage work handed off under the parent-orchestrated profile carries the same handoff metadata the stage would receive through the normal path, including the batch-context marker, isolation classification, expected branch, approved base, artifact-owning repository, and mutation classification. Incomplete handoff metadata stops the stage, as it does today.
- Under the inline-fallback profile, the run performs only non-mutating work and stops with a named reason at the first point a mutating action would be required.
- A read-only portfolio scan is permitted in the current context under every profile, and never escalates itself into execution.
- Choosing a profile never relaxes an existing guardrail, gate, stop condition, permission requirement, or human decision point. Profiles determine who performs the work, not whether the rules apply.
- Profile selection is declared by the run, informed by published indicators of the environment's behavior. The framework does not promise automatic environment detection, and a run never treats an undetectable environment as permission to proceed.
- The canonical profiles guidance describes behavior by reference to the roles' own contracts and protocols and does not duplicate them. Where they conflict, the role contract and protocol prevail.
- Every entrypoint an operator can legitimately start a bounded run from states the profile requirement and points to the canonical guidance, so the requirement cannot be missed by choosing a different starting point.
- Obligations tied to repository arrangement — artifact ownership, tracker updates, and post-merge cleanup — follow the absorbed role's contract and are unaffected by which profile is in force.

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

---

## Operational Visibility

- **Run output**: the dispatch profile and the accountable orchestration role appear in the run's output before its first mutating action, and any re-declaration appears at the point it takes effect with its reason.
- **Run summary**: the summary of a completed or stopped run records the profile in force at the end, every profile transition that occurred, and — under the parent-orchestrated profile — which orchestration layers were absorbed and which stages were handed off.
- **Stop reporting**: a run stopped by a missing declaration, or by a mutating action required under the inline-fallback profile, reports a named reason and the conditions under which the work can proceed, rather than a generic failure.

---

## Decision-Gate Consistency Matrix

The profile declaration is a decision gate: the same inputs must produce the same outcome and the same next action wherever the gate is described.

| Input observed at run start                                                             | Profile outcome     | Required next action for the current context                                                                                                  | Prohibited                                                                     |
| ----------------------------------------------------------------------------------------- | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| Orchestration handoff available, and the receiving role can hand stage work onward       | Native handoff      | Declare the profile, record that orchestration is handed off intact, hand off, and follow the existing protocol unchanged                      | Absorbing the orchestration role when handoff is available                      |
| Orchestration handoff available, but the receiving role cannot hand stage work onward    | Parent orchestrated | Declare the profile and the absorbed layers, perform the absorbed contract in full, hand every stage of product work to its stage role          | Authoring or reviewing product changes inline; dropping any absorbed obligation |
| No handoff of any kind available, and the command is read-only                            | Inline fallback     | Declare the profile, complete the read-only work in the current context, report                                                                | Escalating the scan into execution                                              |
| No handoff of any kind available, and the command would mutate                             | Inline fallback     | Declare the profile, report what was determined, stop with a named reason and the conditions for proceeding                                    | Performing the mutation inline                                                  |
| Declaration missing at the first mutating action                                          | None in force       | Stop before mutating and report the missing declaration                                                                                       | Assuming a profile and continuing                                               |

**Mirror surfaces** — every surface below states the same gate and points to the canonical guidance rather than restating its rules: the single-item, multi-item, epic, and portfolio-scan command entrypoints; the portfolio and item orchestration role documents; the portfolio, single-item, and epic orchestration protocols; the agent model configuration document; and the repository's workflow rule file.

**Examples**: the canonical guidance carries at least one worked example per profile, showing the declaration and the resulting split of work for a named layer. Examples are part of the changed surface and must agree with this matrix.

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
- [ ] Invoking the single-item command, the explicit multi-item command, or the epic command produces a declaration of the dispatch profile and the accountable orchestration role before any mutating action, and a run that reaches a mutating action without one stops with a named reason.
- [ ] The portfolio-scan command documents that scanning is read-only under every profile and that acting on its results requires a new bounded run with its own declaration.
- [ ] The portfolio orchestration role document and the item orchestration role document each state what to do when onward handoff is unavailable: return the run to the context that invoked it rather than proceeding, and perform no product work inline.
- [ ] The portfolio, single-item, and epic orchestration protocols each reference the canonical document at the point a run establishes its execution arrangement, before dispatch or mutation.
- [ ] The agent model configuration document states which profile and which model assignment apply for each combination of supported Cursor environment and orchestration layer.
- [ ] The repository's workflow rule file states the profile-declaration requirement and points to the canonical document.
- [ ] An operator who has never run the workflow under a constrained environment can reach the canonical guidance from any bounded command entrypoint or orchestration role document, and can run a single item, an explicit multi-item batch, and an epic to a terminal condition using the documentation alone, with no gate dropped and no human rescue.
- [ ] Every profile, layer, and orchestration-role name is spelled and labelled identically across the canonical document, the command entrypoints, the role documents, the protocols, the model configuration document, and the workflow rule file.

---

## Out of Scope (MVP)

1. **An explicit profile-override flag on the bounded commands.** The brief offers this as an optional later phase. Deferral rationale: the declaration requirement and the profile contracts are what unblock the operator; an override flag is an ergonomic addition that only makes sense once the declared-profile behavior is in use, and adding a flag surface now would spread the contract across command syntax before it has settled. Human confirmation requested before it is scheduled.

2. **Changing how Cursor Remote Control or Cloud Agents behave.** Declared out of scope in the brief. Deferral rationale: the product behavior is not the framework's to change; this feature adapts the workflow to it. No human confirmation requested.

3. **Automatic detection of the environment from the repository or the shell.** Declared out of scope in the brief, which records that no reliable signal exists. Deferral rationale: a detector that is wrong is worse than a declaration that is explicit, because it would silently pick a profile that permits work the environment cannot support. No human confirmation requested.

4. **Restating role and protocol contracts inside the canonical document.** Declared out of scope in the brief. Deferral rationale: duplicated contracts drift, and the drift would be invisible until a run followed the stale copy. The canonical document refers to the contracts instead. No human confirmation requested.

5. **Documenting the repository-identifier format used by the retrospective cross-reference step.** Raised as a closing note in the brief. Deferral rationale: it concerns retrospective cross-referencing and template configuration commentary, and shares no surface with dispatch profiles; folding it in would widen this item's blast radius across unrelated files. Human confirmation requested on whether to open a separate work item for it.

6. **Dispatch profiles for runners other than Cursor.** Deferral rationale: the recorded failure and every named surface in the brief are Cursor-specific, and the other supported runners have not been shown to have the same limitation. Generalizing without evidence would invent contracts for environments no one has observed failing. Human confirmation requested if other runners are later found to be affected.

7. **Changing any model tier assignment.** Deferral rationale: this feature records which assignment applies in which environment and layer; deciding that a tier should change is a separate product decision with its own cost and quality trade-offs. No human confirmation requested.

---

## Open Questions

1. When an operator is in an environment where no handoff of any kind is available and the work genuinely must proceed, is stopping and moving to a capable environment the only sanctioned remedy, or should there be an explicitly approved, recorded escape hatch that permits mutation in the current context? The brief states the read-only rule without addressing the operator who has no other environment available.

2. Cursor Cloud Agents are named as a distinct environment in the model configuration requirement, but the recorded failure is from Remote Control only. Which profile should the documentation state as expected for Cloud Agents at each orchestration layer, and is that expectation confirmed by observation or assumed?

3. Under the parent-orchestrated profile, one context is accountable for the portfolio layer for an entire explicit multi-item batch. Should such a batch still run its items concurrently, or should it be documented as running items one at a time in this environment, given that a single context is supervising every item itself?

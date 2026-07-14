# Fast Track Blast Radius Call-Site Volume — Spec

---

## Overview

This workflow improvement strengthens Fast Track routing so agents consider how widely a proposed change is used before skipping the plan stage. The existing Fast Track cross-layer check catches changes that clearly span multiple architectural layers, but it can miss a simple-looking rename or field change with many call sites inside one or two layers. The updated routing behavior should help agents promote high-volume changes to the Full Pipeline before implementation begins, while keeping truly small, low-blast-radius fixes eligible for Fast Track.

The implementation plan will decide the exact search mechanism, thresholds, and protocol text placement. This spec defines the expected workflow behavior, visible decision evidence, and coverage obligations.

---

## Brief Objective List

1. Before Fast Track classification, inspect the primary entity being renamed or modified and consider call-site volume across non-test source files.
2. When call-site volume exceeds the configured threshold, promote the item to Full Pipeline with a note explaining the detected high call-site volume.
3. Document call-site volume as a complement to the existing cross-layer scope check: cross-layer checks architectural spread; call-site volume checks propagation breadth regardless of layer count.
4. Add a Fast Track routing prompt for live external system configuration, such as workflow automation, third-party API schemas, or other external config that may not be visible in a repository search.

---

## Use Cases

### Use Case 1: Agent evaluates a simple-looking change for Fast Track

**Actor**: Work Item Runner deciding whether a bug or simple change may use the Fast Track path.

**Preconditions**:

- A tracker item or human brief suggests a bug fix or simple change.
- The item has not yet been dispatched to implementation.
- The item names, or allows the agent to infer, the primary entity being renamed or modified.

**Steps**:

1. Agent reads the current item title, body, recent comments, and any linked spec or plan.
2. Agent applies the existing Fast Track eligibility checks, including the cross-layer scope check.
3. Agent identifies the primary entity that would be renamed or modified, when the brief makes one identifiable.
4. Agent checks whether the entity appears widely enough in non-test source files to indicate high call-site volume.
5. Agent records the routing decision: either Fast Track remains eligible, or the item is promoted to Full Pipeline because high call-site volume was detected.

**Postconditions**:

- Fast Track is used only when both layer spread and call-site volume look bounded.
- High-volume changes are routed to spec and plan work before implementation.

**Information shown**:

- The routing summary names the blast-radius check outcome.
- When high call-site volume is detected, the summary includes the number of affected source files or occurrences available to the agent.
- When the primary entity cannot be identified from the brief, the summary says so and explains whether that uncertainty blocks Fast Track.

**Actions available**:

- Continue with Fast Track when all eligibility checks remain satisfied.
- Promote to Full Pipeline when call-site volume indicates broad propagation.
- Ask the human for clarification when the primary entity is ambiguous and that ambiguity prevents a defensible routing decision.

**Considerations**:

- The call-site check is supplementary. It does not weaken the existing cross-layer rule; either check can disqualify Fast Track.
- The check should avoid counting test-only references as proof that production blast radius is high.
- The check should not require a perfect static analysis result before routing. It needs enough evidence to avoid obviously under-scoped Fast Track work.
- The plan stage should define the exact threshold and command or helper used to gather evidence.

### Use Case 2: Agent handles a high-volume rename with limited layer diversity

**Actor**: Work Item Runner evaluating a rename or field change that appears to touch only one or two architectural layers.

**Preconditions**:

- The brief describes a primary field, type, function, workflow variable, or similar entity that will change.
- The existing cross-layer check does not find enough concrete layer-spanning signals to block Fast Track.
- The entity is referenced in many source files or occurrences.

**Steps**:

1. Agent completes the cross-layer check and notes that it did not independently block Fast Track.
2. Agent completes the call-site volume check.
3. Agent determines that the call-site volume exceeds the configured high-volume threshold.
4. Agent routes the item to Full Pipeline and records the reason in the routing summary.

**Postconditions**:

- The item does not enter Fast Track solely because it has low layer diversity.
- The next workflow stage has enough planning space to audit the affected call sites before implementation.

**Information shown**:

- A visible note such as: "High call-site volume detected: N files or occurrences; routing to Full Pipeline so scope can be audited before implementation."
- The note appears wherever the Work Item Runner reports the selected next action.

**Actions available**:

- Continue into Writing Spec for Full Pipeline work.
- If the evidence is clearly a false positive, ask the human for an explicit override rather than silently using Fast Track.

**Considerations**:

- High volume does not need to prove every reference requires a code change. It is a planning-risk signal.
- The plan stage should decide how to reduce false positives without making the pre-dispatch gate expensive or brittle.

### Use Case 3: Agent checks for live external system configuration impact

**Actor**: Work Item Runner deciding whether Fast Track is safe for a change whose impact may extend outside the repository.

**Preconditions**:

- A tracker item or human brief describes a change that may affect live automation, third-party API schemas, integration contracts, workflow configuration, or sibling repositories.
- Repository search may not reveal all affected external configuration.

**Steps**:

1. Agent reads the brief and recent comments for external-system indicators.
2. Agent explicitly asks, in the routing decision, whether the change affects live external system configuration or contracts.
3. If the answer is yes or strongly indicated by the brief, agent does not proceed as a simple Fast Track item without a plan-stage audit.
4. If the answer is unknown but plausible and material, agent asks the human for clarification or records a follow-up requirement before implementation begins.

**Postconditions**:

- External configuration scope is considered before Fast Track dispatch.
- Known external-system impact routes to Full Pipeline or to a clearly tracked pre-flight follow-up, rather than being discovered mid-implementation.

**Information shown**:

- The routing summary includes an external-system check result: no signal found, signal found, or clarification required.

**Actions available**:

- Continue with Fast Track when no external-system signal exists and other criteria pass.
- Promote to Full Pipeline when external-system impact is known or likely.
- Create or request a pre-flight follow-up when the external-system work is intentionally separate from the current item.

**Considerations**:

- This check is about workflow routing, not direct modification of external systems.
- The plan stage should decide the exact wording and location of the external-system prompt.

---

## Business Rules

- BR-1: Fast Track routing must consider call-site volume before dispatching a bug or simple change directly to implementation.
- BR-2: The call-site volume check must be additive to the existing cross-layer scope check. A positive signal from either check is enough to disqualify Fast Track.
- BR-3: Call-site volume must be evaluated against non-test source references when the primary entity is identifiable from the item brief or linked artifacts.
- BR-4: If call-site volume exceeds the configured high-volume threshold, the item must be promoted to Full Pipeline unless a human explicitly overrides the route.
- BR-5: The routing summary must include a visible note when high call-site volume causes promotion to Full Pipeline.
- BR-6: When the primary entity cannot be identified and the item otherwise appears Fast Track eligible, the agent must either explain why the absence of an entity does not matter or ask for clarification if it prevents a defensible routing decision.
- BR-7: Fast Track routing must include an explicit check for live external system configuration or integration-contract impact that may not be visible through repository search.
- BR-8: Known or likely external-system impact must route to Full Pipeline or to an explicitly tracked pre-flight follow-up before implementation begins.
- BR-9: Exact search commands, parser choices, thresholds, and file-exclusion mechanics are implementation-plan decisions. The spec must not require a particular technical mechanism.

---

## Acceptance Criteria

- [ ] AC-1: The Work Item Runner Fast Track eligibility guidance requires a call-site volume check before dispatching bug or simple-change items to Fast Track implementation.
- [ ] AC-2: The Fast Track eligibility guidance states that call-site volume is supplementary to the existing cross-layer scope check and that either high call-site volume or concrete cross-layer signals routes the item to Full Pipeline.
- [ ] AC-3: The guidance requires the agent to identify the primary entity being renamed or modified when the brief makes one identifiable.
- [ ] AC-4: The guidance requires the call-site check to focus on non-test source references so test coverage does not inflate production blast-radius evidence.
- [ ] AC-5: The guidance defines the expected routing outcome when high call-site volume is detected: promote to Full Pipeline and include a visible routing note with the observed volume evidence.
- [ ] AC-6: The guidance defines the expected routing outcome when the primary entity is ambiguous: explain why the check is not applicable or ask for clarification when ambiguity blocks a defensible Fast Track decision.
- [ ] AC-7: The development workflow overview or Fast Track criteria document call-site volume as a blast-radius check distinct from layer presence.
- [ ] AC-8: The Fast Track routing guidance includes an explicit external-system configuration prompt covering live automation, third-party API schemas, integration contracts, sibling repositories, or similar external config that repository search may miss.
- [ ] AC-9: The guidance states that known or likely external-system impact blocks immediate Fast Track implementation and requires either Full Pipeline routing or a tracked pre-flight follow-up before any later Fast Track dispatch.
- [ ] AC-10: The implementation plan identifies where thresholds and search mechanics will be configured or documented, without the spec prescribing the exact technical implementation.

---

## Out of Scope (MVP)

- Implementing the actual protocol, script, or helper changes. This spec captures workflow requirements; the implementation plan will choose exact files and mechanics.
- Defining the final numeric threshold for "high" call-site volume. The plan stage will decide the threshold and whether it is configurable.
- Mandating a specific search technology, such as grep, ripgrep, AST parsing, language-server analysis, or a custom helper.
- Performing a complete cross-repository search automatically. The MVP requires a prompt and routing behavior for external-system impact, not universal discovery of sibling-repository configuration.
- Changing already-merged Fast Track PRs or retroactively reclassifying completed work.
- Changing CHANGELOG policy for spec-only PRs.

---

## Coverage Matrix

| Brief objective | Spec coverage |
| --- | --- |
| Before Fast Track classification, inspect the primary entity being renamed or modified and consider call-site volume across non-test source files. | Use Case 1, Use Case 2, BR-1, BR-3, BR-6, AC-1, AC-3, AC-4, AC-6 |
| When call-site volume exceeds the configured threshold, promote the item to Full Pipeline with a note explaining the detected high call-site volume. | Use Case 2, BR-4, BR-5, AC-2, AC-5, AC-10 |
| Document call-site volume as a complement to the existing cross-layer scope check: cross-layer checks architectural spread; call-site volume checks propagation breadth regardless of layer count. | Overview, Use Case 1, Use Case 2, BR-2, AC-2, AC-7 |
| Add a Fast Track routing prompt for live external system configuration, such as workflow automation, third-party API schemas, or other external config that may not be visible in a repository search. | Use Case 3, BR-7, BR-8, AC-8, AC-9 |

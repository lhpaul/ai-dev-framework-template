# React Hooks Safety Checklist — Spec

**Depends on**: <!-- No dependencies -->

---

## Overview

This feature adds a **React Hooks Safety** conditional section to the implementation plan protocol template (`docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`) and a corresponding reviewer checklist to `REVIEW.md`. The additions are conditional: they activate only when a plan describes React or React Native components that use state, effects, or async operations. The goal is to prevent a known class of React anti-patterns from reaching external review, reducing fix-commit ratio and reviewer thread volume on React / React Native features.

---

## Use Cases

### Use Case 1: Tech Lead writes an implementation plan for a React or React Native feature

**Actor**: Tech Lead agent (or human following the plan-writing protocol)
**Preconditions**: The approved spec describes a React or React Native feature that involves component state, side effects, or async operations

**Steps**:
1. The Tech Lead reads the spec and identifies that the plan involves React / React Native component state, effects, or async operations.
2. The Tech Lead opens the implementation plan protocol (`02-generate-implementation-plan-protocol.md`) and sees a clearly marked conditional section: "React Hooks Safety Checklist (include when the plan describes React / React Native components with state, effects, or async operations)".
3. The Tech Lead evaluates each item in the React Hooks Safety Checklist against the plan's proposed implementation and addresses each one explicitly.
4. The written implementation plan includes the React Hooks Safety section with each checklist item either addressed (showing the planned solution) or marked not applicable with a brief rationale.

**Postconditions**: The implementation plan explicitly documents how each React hooks safety concern is handled, preventing downstream anti-pattern bugs during coding.

**Information shown**:
- The conditional section heading and activation condition (when to include)
- Each checklist item with a short description of the failure mode it prevents
- Guidance on how to document each item in the plan

**Actions available**:
- Include the section when the plan involves React / React Native state, effects, or async operations
- Mark individual items as not applicable (with rationale) when they do not apply to the specific plan

**Considerations**:
- The Tech Lead must include the section whenever any React component state, effect, or async operation is described in the plan; omitting it when the activation condition is met is itself a plan deficiency
- If a plan mixes React and non-React work, the checklist applies to the React-specific components only

---

### Use Case 2: Plan reviewer (human or automated) checks a React / React Native implementation plan

**Actor**: Plan reviewer (human or `implementation-plan-reviewer` agent)
**Preconditions**: A plan PR exists for a React / React Native feature; the plan includes components with state, effects, or async operations

**Steps**:
1. The reviewer reads the plan and identifies that it describes React / React Native components with state, effects, or async operations.
2. The reviewer opens `REVIEW.md` and finds the React Hooks Safety checklist items listed under "Plan Review Checklist" as a conditional block.
3. The reviewer verifies that the plan's React Hooks Safety section is present and that each required item is addressed.
4. If any checklist item is missing or unaddressed, the reviewer raises a finding at the appropriate severity level.

**Postconditions**: Plans with React / React Native content that fail to address React hooks safety concerns are caught at the review stage, before implementation begins.

**Information shown**:
- The conditional checklist items in `REVIEW.md` and the condition under which they apply
- The specific concern each item addresses and the severity of a missing or inadequate response

**Actions available**:
- Raise a finding if the React Hooks Safety section is absent from a plan that should include it
- Raise a finding if any individual checklist item is unaddressed or clearly inadequate
- Accept a "not applicable" notation if it includes a brief rationale

**Considerations**:
- A plan that omits the section entirely when the activation condition is met is a blocking finding
- Individual items marked "not applicable" with a plausible rationale are acceptable

---

### Use Case 3: Code reviewer checks a React / React Native implementation PR

**Actor**: Code reviewer (human or `code-reviewer` agent)
**Preconditions**: A code PR exists that implements a React / React Native feature with state, effects, or async operations; the corresponding plan includes a React Hooks Safety section

**Steps**:
1. The code reviewer reads the plan's React Hooks Safety section and the changed code.
2. The reviewer opens `REVIEW.md` and finds the React Hooks Safety items listed under "Code Review Checklist" as a conditional block.
3. The reviewer verifies that the implementation matches the documented approach for each checklist item.

**Postconditions**: Code that introduces React hooks anti-patterns is caught during code review before external automated reviewers see it.

**Information shown**:
- The conditional checklist items in `REVIEW.md` under "Code Review Checklist"

**Actions available**:
- Raise a blocking finding for code that reproduces a documented anti-pattern
- Accept code that correctly addresses each concern

**Considerations**:
- The code review checklist applies at the implementation stage; the plan review checklist applies at the plan stage — both may be triggered independently by the same activation condition

---

## Business Rules

- **BR-1: Conditional activation.** The React Hooks Safety section in the implementation plan protocol and the React Hooks Safety checklist items in `REVIEW.md` apply only when a plan describes React or React Native components that use state (`useState`, `useReducer`, or similar), side effects (`useEffect`, `useLayoutEffect`), or async operations within component lifecycle.
- **BR-2: Mandatory when activated.** When the activation condition is met, the React Hooks Safety section is required in the written plan. A plan that meets the activation condition but omits the section is treated as incomplete.
- **BR-3: Individual item opt-out requires rationale.** A checklist item may be marked "not applicable" only with a brief explanation of why the concern does not apply to the specific plan. Silent omission of an individual item is not acceptable.
- **BR-4: Checklist scope.** The checklist covers exactly six concerns derived from the observed failure modes in issue #384: (1) `useEffect` dependency arrays, (2) cleanup in async effects, (3) input component stability, (4) async form submit ordering, (5) exclusion parameters in validators, and (6) design token imports. No other concerns are added in this iteration.
- **BR-5: Template change scope.** Only two documents are modified: `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` and `REVIEW.md`. No other workflow documents, agent files, or scripts are changed in this feature.
- **BR-6: No retroactive plan updates.** This feature does not require updating any previously written implementation plans. The new checklist applies to plans written or updated after this feature is merged.

---

## UX Rules

This feature has no end-user UI. The "UX" here refers to the developer-agent experience when reading the updated protocol and review documents.

- The conditional section heading in the implementation plan protocol must clearly state the activation condition so that a reader can determine in one sentence whether the section applies to their plan.
- Each checklist item must include the failure mode it prevents (in plain language) so a Tech Lead agent can understand the risk without reading external references.
- Checklist items must be formatted consistently with existing checklist patterns in the implementation plan protocol and `REVIEW.md`.

---

## Acceptance Criteria

- [ ] `02-generate-implementation-plan-protocol.md` contains a new conditional section titled "React Hooks Safety Checklist" (or equivalent clear title) with an explicit activation condition that references React / React Native component state, effects, or async operations.
- [ ] The React Hooks Safety section in `02-generate-implementation-plan-protocol.md` includes all six checklist items from BR-4: (1) `useEffect` dependency arrays, (2) cleanup in async effects, (3) input component stability, (4) async form submit ordering, (5) exclusion parameters in validators, and (6) design token imports.
- [ ] Each checklist item in `02-generate-implementation-plan-protocol.md` states the failure mode it prevents in one or two plain-language sentences.
- [ ] `REVIEW.md`'s Plan Review Checklist section contains a conditional block listing the React Hooks Safety items that a plan reviewer must verify when the activation condition is met.
- [ ] `REVIEW.md`'s Code Review Checklist section contains a conditional block listing the React Hooks Safety items that a code reviewer must verify when the activation condition is met.
- [ ] Both `REVIEW.md` additions are formatted consistently with the existing conditional checklist patterns already present in that document.
- [ ] No files other than `02-generate-implementation-plan-protocol.md` and `REVIEW.md` are modified by this feature's implementation PR.
- [ ] The CHANGELOG is updated in the implementation PR with an entry under `[Unreleased]` following the project's "Bold Title (#N)" format.

---

## Out of Scope (MVP)

- Updating any previously written implementation plans to include the new checklist.
- Adding the React Hooks Safety checklist to the spec-writing protocol (`01-generate-spec-protocol.md`) — the spec stage is intentionally product-focused and does not address technical implementation patterns.
- Adding React Hooks Safety guidance to `docs/best-practices/` or stack-specific best practices files; that is a separate, broader improvement outside this issue's scope.
- Adding automated lint rules or static analysis checks for React hooks anti-patterns.
- Expanding the checklist beyond the six items identified in issue #384.
- Covering React hooks patterns specific to state management libraries (e.g., Redux, Zustand, MobX) beyond the core React API.

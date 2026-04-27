# Async/Concurrency Safety Checklist — Spec

**Depends on**: <!-- none -->

---

## Overview

This feature adds explicit async/concurrency safety checklists to two workflow documents: the implementation plan protocol and the code review contract. The goal is to ensure that features involving concurrent event sources (e.g., real-time listeners, timers, TCP callbacks) are evaluated for async safety at plan time — so these issues are caught proactively — and again at code review time, so reviewers have a systematic rubric rather than relying on ad-hoc knowledge.

The motivation is a concrete downstream case where shared mutable state accessed from three concurrent event sources required 6 automated review rounds and 5 fix commits before systemic async safety gaps were resolved. All findings were in the same file and shared the same root pattern. Adding structured checklists at plan and review time prevents this class of defect from reaching the review stage.

---

## Use Cases

### Use Case 1: Tech Lead Reviews Async Safety During Plan Writing

**Actor**: Tech Lead (AI or human) writing an implementation plan for a feature with concurrent event sources.

**Preconditions**:
- The feature spec is approved.
- The feature involves at least one of: real-time data listeners (e.g., database change streams), network socket callbacks, timers or scheduled callbacks, or any other pattern where multiple execution contexts can concurrently read or write shared state.

**Steps**:
1. The tech lead reads the implementation plan protocol.
2. The protocol presents an async/concurrency safety checklist as part of the plan-writing guidance.
3. The tech lead works through each checklist item, determining whether each concern applies to the feature being planned.
4. For each applicable concern, the tech lead documents the design decision (e.g., guard pattern chosen, cleanup approach, error propagation boundary) in the implementation plan.
5. For concerns that are not applicable, the tech lead may note "not applicable" with a brief rationale, or omit the item silently.
6. The completed plan includes an explicit concurrency safety section when the feature is concurrent-event-source eligible.

**Postconditions**: The implementation plan addresses each relevant async safety concern, or explicitly documents why a concern does not apply.

**Information shown**:
- The async/concurrency safety checklist embedded in the plan-writing section of the implementation plan protocol.

**Actions available**:
- Tech lead documents each item inline within the plan.
- Tech lead flags an item as an open question when the safe design is ambiguous.

**Considerations**:
- If the feature has no concurrent event sources, the checklist section may be omitted without comment.
- If the feature introduces new concurrent patterns not previously present in the codebase, the tech lead should note this explicitly.

---

### Use Case 2: Code Reviewer Applies Async Safety Rubric During PR Review

**Actor**: Code reviewer (AI or human) reviewing a PR for a feature with concurrent event sources.

**Preconditions**:
- An implementation PR exists for a feature that involves shared mutable state or multiple concurrent execution paths.

**Steps**:
1. The reviewer reads the code review checklist in the review contract.
2. The review contract presents a conditional async/concurrency safety checklist.
3. The reviewer determines whether the PR involves concurrent event sources, shared mutable state, or async boundary crossing.
4. When any trigger condition is met, the reviewer works through each checklist item against the actual code changes.
5. The reviewer raises blocking findings for any unguarded shared state, missed cleanup, or unhandled async error propagation.
6. The reviewer raises important findings for patterns that are technically safe but fragile or poorly structured for future maintenance.

**Postconditions**: Every async safety concern applicable to the PR has been evaluated. Blocking issues are raised as blocking findings; the PR cannot reach ready-for-human-review until they are addressed.

**Information shown**:
- The async/concurrency safety checklist in the Code Review Checklist section of `REVIEW.md`.

**Actions available**:
- Reviewer raises a blocking finding.
- Reviewer raises an important finding.
- Reviewer notes a pattern is clean and moves on.

**Considerations**:
- The checklist is conditional: it applies only when the PR introduces or modifies code with concurrent event sources or shared mutable state. A reviewer should not apply it mechanically to all PRs.
- If the implementation plan already documents the concurrency safety design, the reviewer can use it as a reference to confirm the code matches the plan.

---

## Business Rules

- BR-1: The async/concurrency safety checklist in the implementation plan protocol applies to any feature where the plan introduces or modifies code with two or more concurrent event sources that share mutable state.
- BR-2: The async/concurrency safety checklist in the code review contract applies to any PR that introduces or modifies code where multiple execution contexts (listeners, timers, callbacks, async queues) can access shared mutable state.
- BR-3: The checklist items are not exhaustive — they cover the most common patterns. Reviewers and tech leads may identify additional concerns beyond the checklist.
- BR-4: A failing checklist item in the code review context is treated as a blocking finding by default; the reviewer may downgrade to important only when the safety concern is demonstrably mitigated by surrounding architecture (e.g., single-threaded event loop with no interleaving risk).
- BR-5: The checklists must remain concise enough to be actionable without becoming a compliance checklist that is robotically ticked without judgment.
- BR-6: The plan-time checklist focuses on design decisions; the review-time checklist focuses on verifying that the code matches the design and has no unsafe patterns.

---

## Acceptance Criteria

- [ ] AC-1: The implementation plan protocol (`02-generate-implementation-plan-protocol.md`) includes a new conditional section that triggers when the feature has concurrent event sources. The section lists the async/concurrency safety checklist items and instructs the tech lead to document each applicable item in the plan.
- [ ] AC-2: The code review contract (`REVIEW.md`) Code Review Checklist includes a new conditional block for async/concurrency safety. The block specifies the trigger conditions and lists the checklist items that the reviewer must evaluate when the trigger applies.
- [ ] AC-3: The checklist in both documents covers at minimum: shared mutable state guards, re-entrancy / in-flight operation tracking, event deduplication, listener/resource cleanup on teardown, race conditions at initialization and teardown, and error propagation across async boundaries.
- [ ] AC-4: The checklist items in both documents use plain-language descriptions that are understandable without knowledge of any specific language or framework.
- [ ] AC-5: The async/concurrency safety checklist in `REVIEW.md` is presented as a conditional additional check block, parallel in structure to the existing "Additional checks for shell scripts" and "Additional checks for database migrations" blocks in the Code Review Checklist.
- [ ] AC-6: The async/concurrency safety checklist in `02-generate-implementation-plan-protocol.md` is presented as conditional guidance (similar in form to the existing "Parser-risk plans" block), triggered only when the plan involves concurrent event sources.
- [ ] AC-7: Both documents remain internally consistent — if a term or concept is named in one, the same name is used in the other.

---

## Out of Scope (MVP)

- Automated static analysis or linting rules to detect concurrent patterns (this spec covers documentation checklists only).
- Language- or framework-specific async safety guidance (the checklists must be language-agnostic).
- Updates to spec-writing guidance — async safety is a technical concern and belongs in the plan and review stages, not the spec stage.
- Smoke test runbook updates — this feature modifies workflow documentation, not application behavior.
- Retroactive audits of existing implementation plans or PRs against the new checklists.
- Guidance on thread-safe data structures, atomic operations, or language-specific concurrency primitives — these are implementation-level details that belong in stack-specific best-practice docs, not the general workflow checklist.

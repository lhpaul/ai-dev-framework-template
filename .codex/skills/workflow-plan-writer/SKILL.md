---
name: workflow-plan-writer
description: Write an implementation plan for a feature (after spec approval) or a refactor (plan only, no spec). Use when a work item needs to advance into the implementation plan stage.
---

# Workflow Plan Writer

Recommended model tier: `premium`

1. Read `AGENTS.md` for repository-wide rules and branch overrides.
2. Read `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`.
3. Follow that protocol exactly.
4. Use the plan to make technical decisions that the spec intentionally avoids. For Refactor items, use the work item brief instead of a spec.
5. When the spec implies pattern-based completeness, run a live repo query, record a Verification Log, and only use frozen enumerations when explicitly authorized in the spec.
6. Before finalizing Step 3, classify parser-risk using the deterministic signals in protocol 02 (tooling-path parser/lint changes, parser/scanner-oriented module naming, or explicit regex/structured-text scanning behavior). When parser-risk applies, include the mandatory edge-case enumeration and unit-test mapping subsections before deep Layer-by-Layer walkthroughs. If suppressions are part of the feature, include suppression semantics (recognized directives, placement, and multi-suppression behavior).
7. Before finalizing Step 3, also classify concurrent-event-source using the deterministic signals in protocol 02 (two or more concurrent event listeners/socket callbacks/timers/async queues, shared mutable state across execution contexts, or initialization/teardown sequences that race with incoming events). When concurrent-event-source applies, include the mandatory concurrency safety checklist section with design decisions for each of the seven items.
8. When the branch is created, continue through reviewer gate, PR creation, and PR readiness unless the protocol surfaces a real human decision.

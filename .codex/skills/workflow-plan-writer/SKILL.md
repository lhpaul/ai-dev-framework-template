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
5. Before any other planning work, run the Step 0 Template-Fit Check: read `.ai-dev-workflow.yaml` and if `template.is_template` is `true`, evaluate whether the spec is generic enough for a framework template. If the spec references a framework-specific language or runtime not used by the template's own toolchain (e.g., React, Rails, Django), surface the structured warning from Step 0 and halt until the human responds. Do not write any plan content while this check is pending.
6. When the spec implies pattern-based completeness, run a live repo query, record a Verification Log, and only use frozen enumerations when explicitly authorized in the spec.
7. Before finalizing Step 3, classify parser-risk using the deterministic signals in protocol 02 (tooling-path parser/lint changes, parser/scanner-oriented module naming, or explicit regex/structured-text scanning behavior). When parser-risk applies, include the mandatory edge-case enumeration and unit-test mapping subsections before deep Layer-by-Layer walkthroughs. If suppressions are part of the feature, include suppression semantics (recognized directives, placement, and multi-suppression behavior).
8. Before finalizing Step 3, also classify concurrent-event-source using the deterministic signals in protocol 02 (two or more concurrent event listeners/socket callbacks/timers/async queues, shared mutable state across execution contexts, or initialization/teardown sequences that race with incoming events). When concurrent-event-source applies, include the mandatory concurrency safety checklist section with design decisions for each of the seven items.
9. Before finalizing Step 3, also check whether the plan introduces or modifies a cross-cutting checklist (a safety, quality, or compliance category that applies across multiple feature implementations). When cross-cutting checklist applies, enumerate ALL files that need updating — including the developer protocol, all agent/skill guidance files, `REVIEW.md`, and any Codex skill files that invoke the affected stage. Run the live search defined in protocol 02's "Cross-cutting checklist plans" block before writing the enumeration.
10. Before opening the draft plan PR, complete Protocol 02's Document Quality Gate and include the gate log in the PR description.
11. Before opening the draft plan PR, call `ensure_on_project_board <issue_number> "Writing Plan"` from `scripts/development-workflow/workflow-lib.sh`. This is a no-op when the issue is already on the board.
12. When the branch is created, continue through reviewer gate, PR creation, and PR readiness unless the protocol surfaces a real human decision.
13. Resolve repository mode, artifact owner, and artifact base branch before
    writing: `single_repo` uses the current repository; `workflow_hub` keeps
    plans and plan PRs hub-owned on the hub artifact base branch, even when the
    product implementation base is different; `product_repo` should report the
    configured hub owner or stop if ownership is ambiguous.

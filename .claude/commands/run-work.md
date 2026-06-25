---
description: "Primary adaptive workflow entrypoint. Routes to no-target scan, single-item, explicit-list, or epic behavior based on your request. Usage: /run-work [<target> ...] — with no target it proposes the largest safe plan; with one target it advances that item; with multiple targets it treats them as a hard bounded scope; with an epic it does read-only scope resolution first."
---

# Claude Code Command: Run Work

`/run-work` is the **primary adaptive entrypoint** for workflow orchestration.
It inspects the request, tracker/repository state, and repository configuration,
then routes to the appropriate behavior via the routing classifier
(`scripts/development-workflow/run-work-router.sh`, Protocol 96):

| Routing mode     | When it applies                                      | Protocol entered            |
| ---------------- | ---------------------------------------------------- | --------------------------- |
| `no_target_scan` | No target supplied                                   | Protocol 90 (portfolio)     |
| `single_item`    | Exactly one non-epic target                          | `/run-item` (prelude + Protocol 91) |
| `explicit_list`  | Two or more explicit targets (hard bounded scope)    | Protocol 90 (bounded)       |
| `epic`           | Epic-like target or `--epic` flag                    | Protocol 95 (epic resolver) |
| `ambiguous`      | Cannot resolve deterministically — stops for human   | No mutation                 |

Every invocation emits a routing-decision record showing the inferred mode,
resolved scope, and the inputs that drove the decision.

> **Bounded commands**: `/run-item` is the canonical single-item command (shared
> prelude + Protocol 91). `/run-epic` runs bounded epic scope with explicit
> delegation flags. `/run-item-work` is a deprecated alias for `/run-item`.
> `/run-work` routes portfolio, explicit-list, single-item, and epic targets via
> Protocol 96 (portfolio-only narrowing is tracked in #1051).

## Routing Classifier

Run before entering any underlying protocol:

```bash
./scripts/development-workflow/run-work-router.sh [<target>...] [--json]
```

## Underlying Protocols

Follow the appropriate protocol based on the classified routing mode:

- `no_target_scan` / `explicit_list` → `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
- `single_item` → `.claude/commands/run-item.md` (bounded prelude + Protocol 91)
- `epic` → `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
- Routing specification → `docs/workflow/development-workflow/protocols/96-run-work-routing-protocol.md`

## Tracker Classification

When `issue_tracker.provider: github_projects` is configured, the GitHub
Projects **Type** field is the source of truth for work-item classification:
`Feature`, `Bug`, `Refactor`, or `Workflow`. Use `Workflow` for
AI-development-framework/process/tooling items. Do not use legacy repository
classification labels (`workflow`, `bug`, `enhancement`, or `type:*`) for new
automation; keep operational labels such as `ready-for-human-review`,
`needs-fixes`, `ready-for-regression`, `reviewer-failed`, and
`integration-branch:<slug>`.

Key responsibilities:

- Run the routing classifier to determine mode and emit a routing-decision record
- Read current state from the issue tracker (if configured) and `docs/specs/developments/`
- When using an issue tracker, read the current brief per `docs/workflow/development-workflow/integrations/issue-tracker.md`
- Respect dependencies declared in specs
- Prioritize: due within 2 weeks → priority level → creation date
- Flag conflicts to the human rather than choosing silently
- Use the helper scripts in `scripts/development-workflow/` to inspect state, plan batches, resume partial work, poll automated review, and poll CI
- In `workflow_hub`, include selected product repository context in implementation handoffs; missing mode or `single_repo` does not require `--repo`
- Dispatch `/item-orchestrator` for each selected item when possible
- Report a summary of what was started, what is ready for review, what was serialized, and what is blocked

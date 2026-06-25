---
name: run-work
description: "Primary adaptive workflow entrypoint. Routes to no-target scan, single-item, explicit-list, or epic behavior based on your request. Use when the user asks for /run-work, run-work, or wants to batch-orchestrate workflow items. Usage: /run-work [<target> ...] — with no target it proposes the largest safe plan; with one target it advances that item; with multiple targets it treats them as a hard bounded scope; with an epic it does read-only scope resolution first."
---

# Run Work

This is the Codex command-style alias for Claude Code `/run-work`.

`/run-work` is the **primary adaptive entrypoint** for workflow orchestration.
It inspects the request, tracker/repository state, and repository configuration,
then routes to the appropriate behavior via the routing classifier
(`scripts/development-workflow/run-work-router.sh`, Protocol 96):

| Routing mode     | When it applies                                      | Protocol entered            |
| ---------------- | ---------------------------------------------------- | --------------------------- |
| `no_target_scan` | No target supplied                                   | Protocol 90 (portfolio)     |
| `single_item`    | Exactly one non-epic target                          | Protocol 91 (single item)   |
| `explicit_list`  | Two or more explicit targets (hard bounded scope)    | Protocol 90 (bounded)       |
| `epic`           | Epic-like target or `--epic` flag                    | Protocol 95 (epic resolver) |
| `ambiguous`      | Cannot resolve deterministically — stops for human   | No mutation                 |

> **Bounded commands**: `/run-item` is the canonical single-item command (shared
> prelude + Protocol 91). `/run-epic` runs bounded epic scope with explicit
> delegation flags. `/run-item-work` is a deprecated alias for `/run-item`.

1. Read `AGENTS.md` for repository-wide rules.
2. Run `./scripts/development-workflow/run-work-router.sh [<target>...] [--json]`
   to classify the routing mode and emit a routing-decision record.
3. Route to the appropriate protocol based on the classified mode:
   - `no_target_scan` / `explicit_list` → read `.codex/skills/workflow-orchestrator/SKILL.md` and follow it.
   - `single_item` → read `.agents/skills/run-item/SKILL.md` or Protocol 91.
   - `epic` → read `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` and follow it.
   - `ambiguous` → stop and report the ambiguity to the human. No mutation.
4. For `workflow_hub` implementation work, preserve selected product repository
   context in item handoffs; missing mode or `single_repo` does not require
   `--repo`.
5. **Guardrails enforcement**: Before any artifact-mutating action, resolve the
   effective guardrails (three-layer precedence: repo config → session overrides →
   invocation overrides) and report them. The routed protocol enforces the six
   gates defined in `docs/workflow/development-workflow/guardrails-enforcement.md`.
   When no `guardrails` section is found in `.ai-dev-workflow.yaml`, conservative
   defaults apply automatically.

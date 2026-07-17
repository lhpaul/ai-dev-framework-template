---
name: workflow-orchestrator
description: Batch-orchestrate the repository's staged AI development workflow. Use when the user wants Codex to discover what can advance or start across multiple items, propose the largest safe batch by priority and parallelization feasibility, and supervise approved item work until it reaches a real terminal condition.
---

# Workflow Orchestrator

Recommended model tier: `economy`

1. Read `AGENTS.md` for repository-wide rules, branch overrides, and terminal-condition expectations.
2. Read `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`.
3. Prefer the helper scripts in `scripts/development-workflow/` for state discovery, batch planning, next-action classification, resume behavior, CI polling, and automated review polling before using ad hoc shell commands.
4. Treat the protocol as canonical. Use `workflow-item-orchestrator` for each selected or approved item when your runner supports skill-to-skill handoff; otherwise continue in the current session by following `91-orchestrate-work-protocol.md` item by item.
5. Keep batching and prioritization decisions explicit, especially when work must be serialized because the runner cannot execute multiple item orchestrators concurrently.
6. Before dispatching an explicit-list batch where any runner may mutate, including sequential fallback, build the Protocol 90 isolation manifest and require a distinct absolute worktree path plus `isolation: "worktree"` for every mutating item. Stop before dispatch on missing isolation assignment or duplicate worktree path; non-isolated runners are allowed only when explicitly classified `read_only` and will not edit files, switch branches, commit, push, mutate PRs, change labels, or update tracker state.
7. Include the incremental commit requirement in every substantial or
   multi-part mutating item handoff: commit immediately after each completed
   logical sub-part, do not intentionally batch all completed sub-parts into one
   final commit, and never commit incomplete or failing work only to satisfy the
   rule.
8. Do not stop after dispatching a batch if any selected or approved item still has a deterministic next action.
9. For `workflow_hub` implementation work, include workflow mode, artifact owner, selected product repository, local path or remote identity, and mutation target in item handoffs; stop before mutation-oriented dispatch when product repository context is missing or ambiguous. Missing mode or `single_repo` does not require `--repo`.
   Include the parent-approved base branch in mutation-oriented handoffs; child runners must use it with `run-nested-artifact-guard.sh --approved-base` before branch or PR creation.
10. **Guardrails enforcement**: Before any artifact-mutating action, resolve the effective guardrails (three-layer precedence: repo config → session overrides → invocation overrides) and report them in the portfolio run summary. Enforce the six gates described in `docs/workflow/development-workflow/guardrails-enforcement.md`: load+report at run start, backlog-start gate, per-stage PR-open gate, delegated review gate, delegated merge gate, and completion gate. When no `guardrails` section is found, state "conservative defaults in effect."
11. With `merge_granted`, readiness is not terminal; continue through delegated
   merge and report each in-scope PR as `merged`, `merge_blocked`, or
   `policy_inconsistent`. With `merge_denied`, ready PRs report
   `ready_human_merge`. Discovered unrelated PRs are `out_of_scope` and are not
   merged.
12. When supervising sweep, batch, helper-extraction, numeric-target, or
   pattern-completeness items, require residual gate evidence before accepting
   `ready-for-human-review` as terminal.
13. When supervising `spec/*` or `implementation-plan/*` PRs, require Protocol
    91 Step 8a's documentation-stage alignment checker before accepting
    readiness. A mismatch keeps the item under supervision until corrected or
    escalated.
14. Before accepting any item as terminal in a batch summary, require the
    Work Item Runner's `## Ground-Truth Completion Verification` section from
    `scripts/development-workflow/item-completion-self-check.sh` or run the
    helper directly from current artifact state. Do not declare the batch item
    complete when the section is missing, reports `discrepancy`, or reports
    `unavailable_required`.

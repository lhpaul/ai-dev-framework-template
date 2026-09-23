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
6. Before dispatching any Backlog item into Writing Spec, run `scripts/development-workflow/spec-dispatch-context.sh` for the selected item and in-scope batch. Pass non-blocking confirmed decisions and relationship outcomes to the item/spec handoff; stop on `blocking=true` and report the helper's `humanAction`. Shared keywords alone are not dependency evidence.
7. Before parallel implementation dispatch, run Protocol 90's planless overlap
   gate from the current tracker snapshot and plan-derived file sets. Concrete
   pairs and unconfirmed suspected pairs serialize by default; carry pair IDs,
   typed evidence, evidence hashes, decisions, and held-item reasons in the
   confirmation and final summaries.
8. Before dispatching an explicit-list batch where any runner may mutate, including sequential fallback, build the Protocol 90 isolation manifest and require a distinct absolute worktree path plus `isolation: "worktree"` for every mutating item. Stop before dispatch on missing isolation assignment or duplicate worktree path; non-isolated runners are allowed only when explicitly classified `read_only` and will not edit files, switch branches, commit, push, mutate PRs, change labels, or update tracker state.
9. Include the incremental commit requirement in every substantial or
   multi-part mutating item handoff: commit immediately after each completed
   logical sub-part, do not intentionally batch all completed sub-parts into one
   final commit, and never commit incomplete or failing work only to satisfy the
   rule.
   For checkpoint-resume redispatch, include checkpoint state with the complete
   Protocol 90 isolation assignment, use a fresh runner, and require the child
   to invoke `checkpoint-resume-gate.sh` before mutation. Do not resume a paused
   runner while sibling runners remain active.
10. For plan-writing handoffs, include the exact current-batch item list and any
   known same-surface open PR evidence for Protocol 02's
   `Cross-Cutting Operational Assumption Check`. Keep returned `Conflict`
   evidence visible until it is `Resolved` by the parent or stopped for
   `unclear_requirements` and request `Human decision required`; do not let
   planners replace this bounded context with an unbounded scan of every open PR.
11. Do not stop after dispatching a batch if any selected or approved item still has a deterministic next action.
12. For `workflow_hub` implementation work, include workflow mode, artifact owner, selected product repository, local path or remote identity, and mutation target in item handoffs; stop before mutation-oriented dispatch when product repository context is missing or ambiguous. Missing mode or `single_repo` does not require `--repo`.
   Include the parent-approved base branch in mutation-oriented handoffs; child runners must use it with `run-nested-artifact-guard.sh --approved-base` before branch or PR creation.
13. **Guardrails enforcement**: Before any artifact-mutating action, resolve the effective guardrails (three-layer precedence: repo config → session overrides → invocation overrides) and report them in the portfolio run summary. Enforce the six gates described in `docs/workflow/development-workflow/guardrails-enforcement.md`: load+report at run start, backlog-start gate, per-stage PR-open gate, delegated review gate, delegated merge gate, and completion gate. When no `guardrails` section is found, state "conservative defaults in effect."
14. With `merge_granted`, readiness is not terminal; continue through delegated
   merge and report each in-scope PR as `merged`, `merge_blocked`, or
   `policy_inconsistent`. With `merge_denied`, ready PRs report
   `ready_human_merge`. Discovered unrelated PRs are `out_of_scope` and are not
   merged.
   Delegated batch merge authority never authorizes force-pushing a PR branch;
   if a destructive PR branch update would be required, stop before mutation and
   route the exact operation through
   `scripts/development-workflow/workflow-branch-push-guard.sh`. In
   `workflow_hub`, resolve the helper from `WORKFLOW_TOOL_ROOT` and pass the
   pushed checkout as `--repo-root "$ARTIFACT_REPO_ROOT"`.
15. For Protocol 94 batch merges, keep the explicit in-scope PR list frozen and
   run `batch-merge.sh recheck-remaining --prs <list> --after-merged-pr <pr>
   --base <base> --approved-unready-prs <human-included-unready-list>` after
   each successful sibling merge before selecting the next PR. Apply Protocol 94
   Step 4.2 as the source of truth for post-recheck admission semantics.
16. When supervising sweep, batch, helper-extraction, numeric-target, or
   pattern-completeness items, require residual gate evidence before accepting
   `ready-for-human-review` as terminal.
17. When supervising `spec/*` or `implementation-plan/*` PRs, require Protocol
    91 Step 8a's documentation-stage alignment checker before accepting
    readiness. A mismatch keeps the item under supervision until corrected or
    escalated.
18. Before accepting any item as terminal in a batch summary, require the
    Work Item Runner's `## Ground-Truth Completion Verification` section from
    `scripts/development-workflow/item-completion-self-check.sh` or run the
    helper directly from current artifact state. When Step 7 was configured, pass
    `--require-review-summary true` and `--require-review-threads true` (helper
    defaults are false). Do not declare the batch item complete when the section
    is missing, reports `discrepancy`, or reports `unavailable_required`.

---

## Cursor dispatch profile

This command runs only in a Cursor environment; other runners are unchanged by this requirement -- Claude Code and Codex behavior is unaffected. Before any mutating action, declare which dispatch profile is in force per `docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md` (the canonical, normative source): `cursor-native-handoff`, `cursor-parent-orchestrated`, or `cursor-inline-fallback`, naming the Portfolio Orchestrator (portfolio layer) as the accountable orchestration role.

Evaluation order: initial handoff -- whether the current context can hand orchestration to the Portfolio Orchestrator at all -- is evaluated first; onward-handoff capability -- whether the Portfolio Orchestrator can hand stage work onward -- is evaluated only once initial handoff is confirmed. A profile decision never evaluates onward-handoff capability before initial handoff is confirmed.

Unconfirmed-handoff outcomes: once initial handoff is confirmed available, onward-handoff capability that cannot be confirmed is treated as unavailable, and the run declares `cursor-parent-orchestrated` as the conservative default until confirmed. Separately, initial handoff availability that itself cannot be confirmed is treated the same as no handoff of any kind: the run declares `cursor-inline-fallback` and stays read-only for the remainder of the run. A later confirmation never upgrades a run in place; the next run declares afresh.

Accountability postures: a declaration states exactly one of personally accountable (absorbed), handed off intact, or observing for the Portfolio Orchestrator role. Observing is valid only at a read-only checkpoint; a mutating action always declares absorbed or handed off. The required posture follows the run's current checkpoint, never its earlier mutation history; a mismatch in either direction is a missing declaration.

When onward handoff to a per-item Work Item Runner is unavailable and this agent has not itself declared `cursor-parent-orchestrated` for the current run, return the run to the context that invoked it rather than proceeding, and perform no product work inline. When this agent is itself the context that has absorbed the portfolio layer under `cursor-parent-orchestrated` (Protocol 90), it performs the portfolio layer's own obligations and delegates every stage of product work to its stage role -- never inline.

Named stop conditions (exact strings): `dispatch_profile_declaration_missing`, `dispatch_handoff_unavailable`, and the reused `missing_required_secret_or_permission`.

- `dispatch_profile_declaration_missing` -- affected work item: the branch, pull request, or development-folder path this invocation targets. Human unblocking action: the stopped run is not resumed or corrected in place; start a fresh invocation supplying a valid profile, a named accountable role, a posture valid for the checkpoint, and, when rejected for a fact mismatch, the profile the known facts assign.
- `dispatch_handoff_unavailable` -- affected work item: the branch, pull request, or development-folder path the mutating action would have applied to. Human unblocking action: move to an environment where initial handoff is confirmed available and re-run, or explicitly accept the read-only result; for the parent-orchestrated stage-handoff-unavailable cause, first confirm the specific stage role the action needed is reachable in the target environment.
- `missing_required_secret_or_permission` (reused) -- when a reachable stage role reports a specific delegated action refused for a missing credential, GitHub permission, or access token: grant the identified credential or permission and re-run the same delegated action, or, for a structural restriction, reassign to the same stage role in a different context or explicitly accept the action does not proceed; the absorbing context never performs the action inline. This path never extends to a harness tool or local file-path permission denial.

No named stop for a harness or local-path denial: a reachable stage role's harness tool or local file-path permission denial on a delegated action is not a named stop condition; it is only observably similar to the `SUBAGENT_PERMISSION_DENIAL` contract (Work Item Runner to Portfolio Orchestrator only), and is Out of Scope, tracked as #1746.

Invalid-declaration boundaries: an invalid profile value, an invalid accountable role (none named, including empty), an invalid posture for the checkpoint, and a coarse-fact mismatch in either direction (more permissive or less permissive than the assigned outcome) are each a missing declaration. The coarse check governs the initial declaration and coarse-fact re-declarations only; it does not govern the mid-run recovery transitions (stage-handoff loss, native-handoff mid-run failure), which remain valid re-declarations.

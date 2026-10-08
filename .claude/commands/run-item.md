---
description: "Primary bounded command: advance exactly one non-epic workflow item with shared prelude before Protocol 91. Usage: /run-item <target> [--base <branch>] [--delegate-review|--no-delegate-review] [--may-merge|--no-may-merge] [--may-start-backlog <true|false>] [--max-risk <low|medium|high>]"
---

# Claude Code Command: Run Item

## Merge-session admission and recovery

After ordinary review/CI/readiness and before any merge-operation audit, hold, bypass, merge or follow-up mutation, follow [Protocol 94 section 3.6](../../docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md#36-merge-session-admission-and-recovery). Freeze the entire selected ordered set in one authoritative owner-bound session; an unaffordable set admits no prefix. Supply the same `--merge-session` to mutating merge/cleanup helpers, and `--operation merge` to operation-owned audit calls. Direct authorized `gh pr merge` commands run through `workflow-merge-budget.py run-step` with their existing argv unchanged. Read-only risk classification remains separate; delegated merge requires the durable session plus all existing gates.

Deferred reports quota/reset, recorded PR states and pending follow-up without operation-owned remote writes; fresh selected PRs stay unmerged, while recovery deferral retains historical merged/uncertain facts. Waiting records a verified queue/auto-merge submission, stops subsequent selected merges and leaves merge-dependent follow-up pending. Interrupted retains completed/uncertain/pending work locally even if every API fails; stop further selected merges and use explicit verified recovery without duplicate submission or uncertain mutation replay. Completed requires all owned planned follow-up independently verified, including tracker and audit. Budget admission grants no risk, checkpoint, admin or deletion authority. Report the session recovery command together with the existing Ground-Truth Completion Verification before claiming a workflow terminal outcome.

`/run-item` is the **canonical single-item bounded command**. It runs the shared
bounded prelude before any mutation, then advances exactly one non-epic item
through Protocol 91 until a real terminal condition.

`/run-item-work` is a deprecated compatibility alias with identical behavior.

## Bounded prelude and Protocol 91

Run the shared bounded prelude and single-item loop per
`docs/workflow/development-workflow/bounded-run-prelude.md` and Protocol 91
(`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`).
The prelude command flags mirror this command's scope flags (`--target`, `--issue`,
`--branch`, `--pr`, `--development`, policy overrides, `--json`).

- Print `policyRecommendation.confirmationSummary` before mutation, including
  effective policy, field sources, pending checkpoint guidance, copy-paste
  equivalent, and the read-only guarantee.
- After explicit autonomy flags or human acceptance, record the
  invocation-scoped `RUN_ITEM_POLICY_CONFIRMED` item/policy binding and do not
  re-prompt for the same selected policy.
- Pending checkpoints, guardrail stops, review/CI failures, risk violations, and
  missing permissions still stop the run.
- When resuming after a human-checkpoint pause from a prior worktree-isolated
  run, invoke Protocol 91's fail-closed checkpoint-resume gate before any
  mutation with item, expected branch, expected worktree, main repo root, and
  checkpoint state. Continue only on `RESULT=continue`; pending checkpoints and
  unclear isolation stop. The gate never satisfies or waives checkpoint state,
  and main-clone resumes must not change directories.
- Resolve exactly one non-epic workflow item
- Use `scripts/development-workflow/` helpers for next-action classification
- After candidate discovery and the nested-artifact guard, require a
  `compatible` result from `validate-branch-reuse.sh` before reusing an existing
  branch. Stop distinctly on incompatible or unverifiable evidence; never
  delete or rewrite the branch automatically, and keep tracking divergence
  diagnostic only.
- In `workflow_hub`, state product repository and mutation target before implementation mutation
- Continue until waiting on human, blocked, or escalated
- If delegated merge authority is active and the merge gate returns
  `merge_allowed`, continue through merge, branch cleanup,
  `post-merge-cleanup.sh`, and live tracker verification before reporting
  terminal
- If the merge gate returns `exceptional_bypass_authorized`, follow the
  canonical exceptional-bypass policy in
  `docs/workflow/development-workflow/guardrails-enforcement.md` Gate 5;
  delegated merge authority is not enough
- Treat merge authority explicitly: `merge_granted` means readiness is
  intermediate and the runner continues through merge; `merge_denied` means the
  ready PR stops as `ready_human_merge` and no merge command is run. Stopping
  at readiness without a named blocker in a merge-granted run is
  `policy_inconsistent`
- Epic-like targets → use `/run-epic` instead

---

## Cursor dispatch profile

In a Cursor environment only, declare the dispatch profile in force before any
mutating action — `cursor-native-handoff`, `cursor-parent-orchestrated`, or
`cursor-inline-fallback` — naming the Work Item Runner (item layer) as the
accountable orchestration role, with a posture valid for the current checkpoint. Other runners are unaffected by
this requirement.

Evaluation order, unconfirmed-handoff outcomes, accountability postures, the
named stop conditions and their human unblocking actions, and the
invalid-declaration boundaries are defined once, normatively, in
`docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md`.
Follow that document; this surface deliberately does not restate it.

Stage-agent models in Cursor: before dispatching a stage subagent, read that
agent's `model:` field from `.cursor/agents/<agent>.md` in the checkout being
run and use it. Do not pick models from the template tables in
`docs/workflow/development-workflow/agent-model-config.md`. Downstream
repositories may pin other model families (for example Grok or Composer), and
those pins are honored as written. See that document's "Cursor model source of
truth" section.


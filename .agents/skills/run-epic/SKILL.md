---
name: run-epic
description: "Compatibility/advanced alias: resolve a native GitHub epic into a bounded workflow execution scope, with optional delegated review and merge gates. For the recommended starting point, use /run-work <epic-target> instead. Use /run-epic when you need direct control over delegation flags (--delegate-review, --may-merge, --max-risk). For explicit item lists, use /run-items."
---

# Run Epic

This is the Codex command-style alias for Claude Code `/run-epic`.

> **Compatibility/advanced alias**: `/run-epic` bypasses the `/run-work`
> routing layer and invokes the bounded epic scope resolver directly with
> explicit delegation flags. If you are not sure which command to use, start
> with `/run-work <epic-number>` — it will route to this protocol automatically
> when the target is epic-like.

1. Read `AGENTS.md` for repository-wide rules.
2. Read `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`.
3. Run `./scripts/development-workflow/run-epic-scope-resolver.sh` with the
   `--epic <issue-number>` argument plus any invocation policy flags:
   `--delegate-review`, `--may-merge`, `--may-start-backlog <true|false>`,
   `--max-risk <low|medium|high>`, and `--base <branch>`.
   For explicit item lists, use `/run-items` instead of `--items`.
   In `workflow_hub` mode, treat the resolver's base as the product
   implementation base. Do not block because that branch is absent from the hub
   repository; validate it only after the owning product repository is selected.
4. Treat resolver output as the bounded scope contract. The resolver itself is
   read-only: do not update tracker status, create branches, open PRs, merge
   PRs, close issues, or delete branches from the resolver phase.
   The resolver also emits `continuation`; after every later rediscovery, obey
   that object before closeout: `continue` means advance the named
   `remainingItems`, `needs_resolution` means stop with the named
   `stopCondition` / `humanAction`, and `complete` is the only closeout-ready
   outcome.
5. When autonomy policy values are missing or ambiguous, run
   `./scripts/development-workflow/run-epic-policy-recommender.sh --scope <resolver-json> --original-command "<requested command>"`
   with any supplied policy flags, including `--no-delegate-review` or
   `--no-may-merge` for explicit negative selections. Present the recommended
   policy, checkpoint policy, risk rationale, base branch, scoped items, and
   copy-paste equivalent command before mutation. Continue in the same run when
   the human accepts the recommendation or supplies custom values. Exact fully
   specified invocations may skip the prompt but still record original,
   recommended, selected, and effective policy in later audit evidence.
6. When a later delegated run reaches a candidate PR merge decision, run
   `./scripts/development-workflow/run-epic-risk-classifier.sh --pr <pr-number>`
   with the invocation's `--max-risk` before merge. The classifier is also
   read-only and does not replace reviewer-loop, CI-loop, thread, merge-state,
   readiness-label, or repository merge-protocol checks.
7. After delegated review, fix, merge, block, or escalation decisions, use
   `./scripts/development-workflow/run-epic-audit-trail.sh` to create or update
   stable PR disposition and epic ledger comments, including checkpoint state:
   - `render-pr-disposition --input <file>`
   - `apply-pr-disposition --input <file> --pr <pr-number>`
   - `render-epic-ledger --input <file>`
   - `apply-epic-ledger --input <file> --epic <issue-number>`
8. Before any delegated merge, run
   `./scripts/development-workflow/run-epic-delegated-gate.sh` with current
   scope, reviewer, CI, risk, and audit evidence; pass `--policy <file>` when
   the resolver policy is captured separately. Merge only when the gate reports
   `merge_allowed`.
   If it reports `exceptional_bypass_authorized`, follow the canonical
   exceptional-bypass policy in
   `docs/workflow/development-workflow/guardrails-enforcement.md` Gate 5;
   delegated epic policy does not authorize `--admin`.
   After `merge_allowed`, follow Protocol 95 Step 11 through merge, merge
   verification, branch deletion/pruning, `post-merge-cleanup.sh`, live tracker
   verification, audit update, rediscovery, and the continuation result before
   treating that PR as complete.
   Treat merge authority explicitly: `merge_granted` makes readiness
   intermediate for in-scope child PRs; `merge_denied` stops at
   `ready_human_merge`; unexplained stalled-at-ready child PRs are
   `policy_inconsistent`; discovered unrelated PRs remain `out_of_scope`.
   When resuming an epic-scoped item after a human-checkpoint pause from a
   prior worktree-isolated run, run the Protocol 95/91 checkpoint-resume gate
   before any mutation with complete item, branch, worktree, main-root, and
   checkpoint-state context. Continue only on `RESULT=continue`; pending
   checkpoints and unclear isolation are stops. Isolation verification does not
   satisfy, waive, or clear checkpoint state, and a main-clone resume must not
   re-enter the worktree itself.
   For substantial or multi-part mutating child work, commit immediately after
   each completed logical sub-part, do not intentionally batch all completed
   sub-parts into one end-of-run commit, and never commit incomplete, failing,
   or incoherent edits only to satisfy the requirement.
   For sweep, batch, helper-extraction, numeric-target, or pattern-completeness
   sub-items, include residual gate status in item/epic summaries and do not
   treat blocked or escalated residuals as complete.
9. Before any child item creates a branch or opens a PR, run
   `run-nested-artifact-guard.sh --mode <pre-create|pre-pr> --issue <number>
   --expected-branch <branch> --approved-base <branch>
   --repo-root "$ARTIFACT_REPO_ROOT"`. Stop on missing base, duplicate
   artifacts, wrong-base PRs, or scan failures unless an explicit split is
   approved and recorded.
10. **Guardrails layer context**: The `--delegate-review`, `--may-merge`,
   `--may-start-backlog`, and `--max-risk` flags are the **invocation-override**
   layer (highest priority) of the three-layer guardrails precedence. The
   repository `guardrails` config in `.ai-dev-workflow.yaml` is the base layer.
   An invocation override may narrow or widen authority only within what the mode
   permits. This protocol shares **one policy path** with Protocols 90 and 91 —
   the same run-epic helpers and enforcement gates defined in
   `docs/workflow/development-workflow/guardrails-enforcement.md`.

---

## Cursor dispatch profile

This command runs only in a Cursor environment; other runners are unchanged by this requirement -- Claude Code and Codex behavior is unaffected. Before any mutating action, declare which dispatch profile is in force per `docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md` (the canonical, normative source): `cursor-native-handoff`, `cursor-parent-orchestrated`, or `cursor-inline-fallback`, naming the Epic Runner (epic layer) as the accountable orchestration role.

Evaluation order: initial handoff -- whether the current context can hand orchestration to the Epic Runner at all -- is evaluated first; onward-handoff capability -- whether the Epic Runner can hand stage work onward -- is evaluated only once initial handoff is confirmed. A profile decision never evaluates onward-handoff capability before initial handoff is confirmed.

Unconfirmed-handoff outcomes: once initial handoff is confirmed available, onward-handoff capability that cannot be confirmed is treated as unavailable, and the run declares `cursor-parent-orchestrated` as the conservative default until confirmed. Separately, initial handoff availability that itself cannot be confirmed is treated the same as no handoff of any kind: the run declares `cursor-inline-fallback` and stays read-only for the remainder of the run. A later confirmation never upgrades a run in place; the next run declares afresh.

Accountability postures: a declaration states exactly one of personally accountable (absorbed), handed off intact, or observing for the Epic Runner role. Observing is valid only at a read-only checkpoint; a mutating action always declares absorbed or handed off. The required posture follows the run's current checkpoint, never its earlier mutation history; a mismatch in either direction is a missing declaration.

Under `cursor-parent-orchestrated`: the current context absorbs the epic layer (Protocol 95) and, per item in turn, the item layer (Protocol 91), one item at a time, dispatches no Work Item Runner, and delegates every stage of product work to its stage role with full handoff metadata -- never inline.

Named stop conditions (exact strings): `dispatch_profile_declaration_missing`, `dispatch_handoff_unavailable`, and the reused `missing_required_secret_or_permission`.

- `dispatch_profile_declaration_missing` -- affected work item: the branch, pull request, or development-folder path this invocation targets. Human unblocking action: the stopped run is not resumed or corrected in place; start a fresh invocation supplying a valid profile, a named accountable role, a posture valid for the checkpoint, and, when rejected for a fact mismatch, the profile the known facts assign.
- `dispatch_handoff_unavailable` -- affected work item: the branch, pull request, or development-folder path the mutating action would have applied to. Human unblocking action: move to an environment where initial handoff is confirmed available and re-run, or explicitly accept the read-only result; for the parent-orchestrated stage-handoff-unavailable cause, first confirm the specific stage role the action needed is reachable in the target environment.
- `missing_required_secret_or_permission` (reused) -- when a reachable stage role reports a specific delegated action refused for a missing credential, GitHub permission, or access token: grant the identified credential or permission and re-run the same delegated action, or, for a structural restriction, reassign to the same stage role in a different context or explicitly accept the action does not proceed; the absorbing context never performs the action inline. This path never extends to a harness tool or local file-path permission denial.

No named stop for a harness or local-path denial: a reachable stage role's harness tool or local file-path permission denial on a delegated action is not a named stop condition; it is only observably similar to the `SUBAGENT_PERMISSION_DENIAL` contract (Work Item Runner to Portfolio Orchestrator only), and is Out of Scope, tracked as #1746.

Invalid-declaration boundaries: an invalid profile value, an invalid accountable role (none named, including empty), an invalid posture for the checkpoint, and a coarse-fact mismatch in either direction (more permissive or less permissive than the assigned outcome) are each a missing declaration. The coarse check governs the initial declaration and coarse-fact re-declarations only; it does not govern the mid-run recovery transitions (stage-handoff loss, native-handoff mid-run failure), which remain valid re-declarations.

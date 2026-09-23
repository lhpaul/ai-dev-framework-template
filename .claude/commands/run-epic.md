---
description: "Compatibility/advanced alias: resolve a native GitHub epic or explicit item list into a bounded workflow execution scope, with optional delegated review and merge gates. For the recommended starting point, use /run-work <epic-target> instead. Usage: /run-epic --epic <issue-number> | --items <issue-number>[,<issue-number>...] [--base <branch>] [--delegate-review] [--may-merge] [--may-start-backlog <true|false>] [--max-risk <low|medium|high>] [--json]"
---

# Claude Code Command: Run Epic

> **Compatibility/advanced alias**: `/run-epic` bypasses the `/run-work`
> routing layer and invokes the bounded epic scope resolver directly with
> explicit delegation flags. If you are not sure which command to use, start
> with `/run-work <epic-number>` — it will route to this protocol automatically
> when the target is epic-like. Use `/run-epic` when you need direct control
> over delegation flags (`--delegate-review`, `--may-merge`, `--max-risk`).

Follow the resolver protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`

Key responsibilities:

- Require exactly one of `--epic` or `--items`.
- Resolve native GitHub sub-issues for `--epic`; keep `--items` exact.
- Infer the execution base branch from `--base`, shared
  `integration-branch:<slug>`, or the applicable default.
- In `workflow_hub` mode, treat that base as the product implementation base;
  do not block because it is absent from the hub repository.
- Group items as `eligible`, `blocked`, `already_merged`, `in_review`,
  `ambiguous`, or `out_of_scope`.
- Read the resolver's `continuation` object after initial scope resolution and
  every later rediscovery. `continue` advances the named `remainingItems`;
  `needs_resolution` stops with the named `stopCondition` / `humanAction`;
  `complete` is the only closeout-ready outcome.
- Keep the resolver phase read-only: no tracker updates, branches, PRs, merges,
  issue closure, or cleanup during scope resolution.
- When autonomy policy is missing or ambiguous, run the read-only policy
  recommender, present the recommended config and checkpoint policy in-place,
  and continue the same run when the human accepts or customizes it.
- Before any child item creates a branch or opens a PR, run
  `run-nested-artifact-guard.sh --mode <pre-create|pre-pr> --issue <number>
  --expected-branch <branch> --approved-base <branch>
  --repo-root "$ARTIFACT_REPO_ROOT"`. Stop on missing base, duplicate
  artifacts, wrong-base PRs, or scan failures unless an explicit split is
  approved and recorded.
- On checkpoint resume from a prior worktree-isolated item run, perform the
  Protocol 95/91 fail-closed checkpoint-resume gate before mutation with
  complete item, branch, worktree, main-root, and checkpoint-state context.
  Pending checkpoints and unclear isolation stop; the gate never satisfies or
  waives checkpoint state, and main-clone resumes must not change directories.
- Before any later delegated merge decision, run the PR risk classifier and
  respect its `--max-risk` gate.
- After delegated review, fix, merge, block, or escalation decisions, update
  stable PR disposition and epic ledger audit comments, including original,
  recommended, selected, and effective policy plus checkpoint state.
- Before merge, run the delegated gate with current scope, policy, reviewer,
  CI, risk, and audit evidence. Merge only when it reports `merge_allowed`.
- If the gate reports `exceptional_bypass_authorized`, follow the canonical
  exceptional-bypass policy in
  `docs/workflow/development-workflow/guardrails-enforcement.md` Gate 5;
  delegated epic policy is not enough.
- After `merge_allowed`, continue through Protocol 95 Step 11: merge, merge
  verification, branch deletion/pruning, `post-merge-cleanup.sh`, live tracker
  verification, audit update, rediscovery, and continuation inspection.
- Treat merge authority explicitly: `merge_granted` makes readiness
  intermediate for in-scope child PRs; `merge_denied` stops at
  `ready_human_merge`; unexplained stalled-at-ready child PRs are
  `policy_inconsistent`; discovered unrelated PRs remain `out_of_scope`.

Use the helper script:

```bash
./scripts/development-workflow/run-epic-scope-resolver.sh "$@"
```

Optional delegation policy flags:

```bash
--delegate-review
--may-merge
--may-start-backlog <true|false>
--max-risk <low|medium|high>
```

Use the read-only policy recommender before mutation when policy is missing or
ambiguous:

```bash
./scripts/development-workflow/run-epic-policy-recommender.sh --scope <resolver-json> --original-command "<requested command>"
```

Pass `--no-delegate-review` or `--no-may-merge` to the recommender when the
selected policy explicitly disables a recommended positive default.

Use the read-only risk helper before delegated merge decisions:

```bash
./scripts/development-workflow/run-epic-risk-classifier.sh --pr <pr-number> --max-risk <low|medium|high>
```

Use the final delegated gate before merge:

```bash
./scripts/development-workflow/run-epic-delegated-gate.sh --input <file> [--policy <file>]
```

Use the audit helper after delegated decisions:

```bash
./scripts/development-workflow/run-epic-audit-trail.sh render-pr-disposition --input <file>
./scripts/development-workflow/run-epic-audit-trail.sh apply-pr-disposition --input <file> --pr <pr-number>
./scripts/development-workflow/run-epic-audit-trail.sh render-epic-ledger --input <file>
./scripts/development-workflow/run-epic-audit-trail.sh apply-epic-ledger --input <file> --epic <issue-number>
```

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

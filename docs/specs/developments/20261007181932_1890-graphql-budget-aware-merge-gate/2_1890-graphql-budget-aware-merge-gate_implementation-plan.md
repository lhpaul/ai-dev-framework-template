# GraphQL budget-aware delegated merging — Implementation Plan

**Issue**: [#1890](https://github.com/lhpaul/ai-dev-framework-template/issues/1890)
**Spec**: [Approved spec](1_1890-graphql-budget-aware-merge-gate_specs.md)
**Smoke test runbook**: [Workflow smoke runbook](../../../testing/workflow/1890-graphql-budget-aware-merge-gate.smoke-test.md)

## Summary

Add an invocation-scoped budget/session helper around the existing delegated and batch merge workflows. Admission uses a conservative heuristic for the entire frozen selected sequence, an explicit estimation margin, and an independent reserve; durable local step records retain completed, uncertain, and pending work after interruption. Existing `gh` merge, queue, admin, already-merged, tracker ownership, readiness, risk, and cleanup semantics remain authoritative.

**Estimated complexity**: L. The arithmetic is small; first-mutation ordering, nested cleanup, interrupted responses, recovery, and command/skill propagation span composed consumers.
**Dependencies**: The option C spec amendment is merged as PR #1928. No dependency on further #1505 work, no live portfolio scan, no new remote service, and no API adapter or CLI-version allowlist.
**Template fit**: Generic workflow tooling using the repository's existing Bash/Python toolchain; `template.is_template: true` does not trigger a framework-specific stop.
**Alignment**: Luis's recorded option C in the spec's Approved Amendment resolves the prior hard-bound-versus-adapter choice. The estimate is intentionally heuristic and cannot guarantee quota or atomicity.

## Verification Log

Source snapshot: `f5162a5fa5246b630e7bfd632654a9eae70ddfda`, inspected 2026-10-07T22:14:12+00:00. Plan artifact stays in the existing development folder as `2_1890-graphql-budget-aware-merge-gate_implementation-plan.md`; the parent uses `implementation-plan/1890-graphql-budget-heuristic-merge-gate` from amended `develop` and preserves the earlier empty plan branch. Spec amendment PR #1928 is merged at this source snapshot; recorded source checks were rerun before committing the plan.

| Check | Reproducible command/query | Source result affecting design |
| --- | --- | --- |
| Configuration and ownership | `cat .ai-dev-workflow.yaml` | Template mode, default single-repository mode, GitHub Projects provider, portfolio reserve, and delegated guardrails are declared; merge reserve is proposed separately. |
| Available config parser | `rg -n '^def load_configs|^def resolve_local_config|^def parse_yaml_subset' scripts/development-workflow/workflow-config-resolver.py` | Existing shared/local YAML-subset loading can be reused; do not create a competing YAML parser. |
| Budget convention | `sed -n '190,222p' scripts/development-workflow/workflow-portfolio-scan.py` | Reader uses `/rate_limit` `resources.graphql`; its invalid-reserve fallback is not reusable for merge admission. |
| Tracker query envelopes | `rg -n 'page_count.*20|first: 100|updateProjectV2ItemFieldValue|TRACKER_STATUS_' scripts/development-workflow/workflow-lib.sh` and `rg -n 'range\(20\)|first:100|strict_cost|def fallback' scripts/development-workflow/workflow-project-reader.py` | Targeted tracker/card/field reads have finite envelopes; status helpers expose outcome markers but are often best effort. |
| Actual merge boundaries | `rg -n 'git push|gh pr merge|MERGE_RESULT|post_state' scripts/development-workflow/batch-merge.sh` | Base push and GitHub merge call are separate boundaries; local clean output alone does not verify MERGED. |
| Remote mutation sites | `rg -n 'gh issue close|update_tracker_status_best_effort|gh pr view|gh pr list|reenter_args' scripts/development-workflow/post-merge-cleanup.sh` and `rg -n 'apply_comment|patch_marker_comment|post_marker_comment' scripts/development-workflow/run-epic-audit-trail.sh` | Cleanup owns tracker/issue actions and worktree reentry; audit writes use stable markers. |
| Composed consumers | `rg -l 'run-epic-delegated-gate.sh|run-epic-risk-classifier.sh|batch-merge.sh|95-run-epic-protocol|94-batch-merge-protocol' .agents/skills .codex/skills .claude .cursor docs/workflow scripts/development-workflow` | Consumer classification and required updates are recorded in the sections below; hits that only classify/inspect do not gain mutation authority. |
| Alias/mirror existence | `rg --files .agents/skills .codex/skills .claude/commands .cursor/commands .claude/agents .cursor/agents` | The explicit mirror inventory below includes shared and legacy skill surfaces; there is no proposed Cursor skill tree. |
| Suite selection/distribution | `rg -n 'covers:|COVERS_HEADER_LINES' scripts/development-workflow/select-test-suites.sh` and `rg -n 'product_repo_injection|workflow-lib|post-merge-cleanup|workflow-project-reader' sync-manifest.yaml scripts/development-workflow/tests/test-sync-template-mode-scopes.sh` | Test headers select suites; the new helper must ship to product runtime because cleanup invokes it. |
| Design references | `rg --files docs/specs/developments/20261007181932_1890-graphql-budget-aware-merge-gate docs/testing` | Current item has no supplied graphical reference; smoke uses textual structured outcomes and no invented visual baseline. |

### Factual claim evidence and authoring rules

Rule 1 uses producer contracts rather than sampling error prose: GitHub publishes the structured [REST rate-limit response](https://docs.github.com/en/rest/rate-limit/rate-limit#get-rate-limit-status-for-the-authenticated-user), [GraphQL rate-limit fields](https://docs.github.com/en/graphql/reference/meta#ratelimit), and [pull-request state enum](https://docs.github.com/en/graphql/reference/pulls#pullrequeststate). Parse fields and enum values; reject malformed/unknown evidence. Subprocess nonzero, unavailable JSON, or journal failure interrupts admitted work regardless of the wording of stderr. Retain redacted diagnostic text for display only; do not classify service errors by free-text substrings.

Rule 2: Definitions in Admission, Durable Execution, Recovery, and Consumer Integration are normative; later steps refer to them. Rule 3: This plan does not assert a count of existing artifacts; the numbered weights and proposed test classes are design values, not repository counts. Rule 4: existence claims reference the direct searches in this log. Rule 5: Consumer Integration states the observable result at each composed site, including read-only consumers intentionally left unchanged. Rule 6: Session scope and discharge sites are explicit in the lifecycle and consumer tables; permissions remain discharged by the current owning workflow gates.

## Cross-Cutting Operational Assumption Check

| Surface | Recorded value | Source | Verified at | Bounded scope | Result |
| --- | --- | --- | --- | --- | --- |
| Architecture boundary | Option C, existing `gh` semantics, no CLI-version pin | Spec Approved Amendment, parent handoff | Snapshot above | #1890 and its spec amendment only | Verified |
| Artifact owner/base | Current repository, `develop` for implementation | AGENTS.md and mode default in `.ai-dev-workflow.yaml` | Snapshot above | Current invocation | Verified |
| Canonical tracker/config | GitHub Projects here; downstream provider selected from effective owning config | `.ai-dev-workflow.yaml`, config resolver, cleanup ownership routines | Snapshot above | Current invocation and amendment PR | Verified |
| Same-surface concurrent changes | PR #1928 merged; #1505 implementation is already on this base; no additional #1890/#1557 branch PR identified in the bounded results | `gh pr view 1928 --json state,mergeCommit`; `gh pr list --state open --search "1890" --json number,headRefName`; same bounded query for 1505/1557, filter exact numeric branch prefix | 2026-10-07T22:14:12+00:00 | Current item and explicitly related helper surface only; no board scan | Verified |

At implementation start, rerun the relevant searches and confirm the approved amendment, base, config ownership, and consumer inventory remain valid. Changed or unverifiable operational assumptions are `Stale or conflicting`; stop before implementation edits and return the evidence to the parent.

## Classifications

Parser-risk applies to structured JSON/session/config validation and identity parsing. Concurrent-event-source applies because multiple helper processes and worktrees access a shared journal and a process can terminate while its subprocess still runs. Cross-cutting checklist is not applicable: this item adds a merge-operation runtime contract, not a new category every feature plan must implement or a new REVIEW.md checklist. Existing review guidance remains unchanged.

## Admission and Estimation Contract

Create `scripts/development-workflow/workflow-merge-budget.py`, using the Python standard library and existing config-loader API. Expose `begin --input <manifest>`, `run-step --session <path> --step <id> -- <argv...>`, `resume --session <path>`, and `report --session <path>`; internal hook operations `before-step` and `after-step` share the same state engine. No command accepts shell source, evaluates a command string, or adds an automatic wait-until-reset mode.

`begin` accepts selected identity/operation declarations, but never accepts caller-supplied quota, success, or admission booleans. Obtain quota and GitHub PR/issue/tracker evidence through the actual `gh` executable; tests replace that executable. The existing Linear MCP bridge is the sole provider-specific evidence route described below. `begin` constructs and freezes an operation manifest from read-only evidence: operation kind, selected ordered `(repo, PR, base, reviewed head)` identities, hub/product/cleanup roots, existing policy reference, owned issue targets and expected branch-specific status, planned audit targets, and execution route. Use cleanup's existing branch/closing-reference ownership rules through a new read-only `post-merge-cleanup.sh --inspect-targets` mode, extracted from its present functions. This mode does not fetch/pull/create/delete branches or update trackers. Unknown closing references, unresolved repository ownership, unsupported tracker provider, or absent plan identity means unknown projection and Deferred. Freeze every selected PR rather than admitting a prefix.

Supported tracker projections are `github_projects`, `github_issues`, `none`, and explicitly resolved `linear`. Linear retains its existing deferred MCP action route: a known owned Linear issue can be estimated, but shell cleanup cannot call its pending status action complete. Unrecognized provider or unknown owning issue identity defers. Required Linear follow-up uses the existing bridge in `docs/workflow/development-workflow/integrations/linear.md`. Before the owning orchestrator invokes its MCP status mutation it records `before-step` intent; after the call it independently reads the issue via MCP and submits `record-provider-result --session <path> --step <id> --evidence <json>` with the captured mutation/read request identifiers, observation time, exact provider issue identity and returned status ID/name. Validate the declared provider/owner/target, observation after intent, and equality to the planned status using the actual read result, not a success boolean or the mutation response alone. Store only the normalized provenance/status evidence. This is the existing trusted orchestrator bridge, not a new Linear API client or authentication mechanism. Unavailable MCP or read-back mismatch leaves pending/uncertain reconciliation and reports Interrupted; no additional selected merge starts. Explicit resume reads Linear again through the bridge and can discharge the verified step; it must not replay a status write already verified. Without the owning bridge verification, the CLI cannot mark the session Completed. Mock bridge transcripts exercise intent-before-mutation, successful independent read-back and unavailable/mismatched read-back.

Read GraphQL quota from `gh api rate_limit` `resources.graphql`, using the existing convention without editing portfolio behavior. Validate object shape, nonboolean nonnegative integer remaining/reset/limit, positive limit, remaining <= limit, and a usable future reset window. Malformed, inconsistent, transport/error, REST-core-only, or missing evidence defers. Preserve individually readable fields when reporting unavailable evidence.

Resolve `merge_budget.graphql_reserve` with precedence CLI override > effective local owning config > shared owning config > omitted-setting default 1000. Accept a nonnegative integer or decimal integer string; reject booleans, explicit null/empty, signs, fractional values, mappings/lists, malformed config keys. Missing setting uses the default; explicit invalid setting never does. Config loading errors defer. This setting is independent of `portfolio_scan.graphql_reserve`.

Heuristic version 1 has the following built-in positive weights, with no operator-supplied free-form cost override:

| Component | Design weight | Reason for conservative sizing |
| --- | --- | --- |
| Shared admission/execution/final-read overhead | 25 points | Covers identity/config/gate and final evidence overhead across helpers. |
| Each PR's outstanding gate/audit/merge/verification/branch-cleanup sequence | 50 points | Allows repeated metadata reads, actual CLI merge overhead, MERGED checks, and audit bookkeeping. |
| Each owned GitHub Projects issue reconciliation execution | 250 points | Uses the source-derived current tracker pagination/call envelope as sizing input and adds issue/repository/closure allowance; this is a heuristic weight, not an upper bound. |
| Each owned GitHub-issues-only reconciliation execution | 15 points | Provides room for issue reads, closure/comment and read-back without project queries. |
| Each resolved Linear issue reconciliation execution | 15 points | Allows GitHub-side ownership/closure evidence; Linear MCP completion remains separately pending. |
| Each frozen remaining-PR sibling recheck event | 5 points | Covers post-merge metadata/CI revalidation at that composed site. |

Count reconciliation executions as actually planned per PR, not merely unique issue numbers: a multi-PR chain can process the same owned issue again. For a fresh ordered batch, count recheck events by enumerating each `(merged predecessor, remaining selected PR)` pair. For recovery, enumerate only outstanding verified steps. `none` adds no tracker term, but closure/audit duties still reside in their PR/issue components. Do not subtract an uncertain step or an unknown issue from the estimate.

Let `rawCost` be the sum of outstanding weighted components. Set `estimationMargin = max(50, ceil(rawCost / 2))`, and `projectedCost = rawCost + estimationMargin`. Admit exactly when `remaining >= projectedCost + reserve`. Reports carry the version, component breakdown, raw cost, margin, projected cost, reserve, and readable samples. The weights are deliberately conservative estimates of existing calls, not a query-count proof or hard limit, and may be exceeded by pagination or concurrent consumption. Any such execution failure follows Durable Execution; no CLI transport or supported-version restriction is introduced.

Admission happens after readiness has already been established and before the merge operation's first audit/readiness/hold/merge/follow-up mutation. Readiness changes are prohibited inside this sequence: changed readiness/head evidence stops the operation under existing policy and routes back to the owning review phase. The helper does not call or replace `apply-readiness-labels.sh`.

An admission is invocation-specific. `begin` and every explicit `resume` take a new sample. The begin assessment is provisional. The first-mutation hook checks the manifest binding and takes the definitive fresh initial admission sample immediately before dispatching that first mutation, evaluating the full remaining sequence once for that execution attempt. Until that hook commits admission evidence locally, no selected remote mutation runs. Once execution starts, later hooks validate scope/state but do not pretend to reserve quota or reclassify earlier merged PRs as Deferred.

## Durable Execution and Recovery

The authoritative session owner is the invocation's artifact repository, resolved with the existing workflow config context: hub for hub-orchestrated work, current repository for single-repository or standalone product work. Freeze its physical root and git-common directory alongside the allowed product/cleanup roots in the manifest. Product/worktree hooks resolve the existing owning hub/reentry context and validate the supplied session against that frozen owner directory, not their current product directory; also validate their current physical root is a declared participant. They cannot replace the owner or create a cheaper session when reentered. A composed hub-to-product-to-worktree test proves these hooks use one journal.

Store sessions in `<owner-git-common-dir>/workflow-merge-budget/<session-id>/state.json`, with private directories/files and a separate advisory lock file. Resolve physical roots and reject symlinks, traversal, foreign-owned directories, or a supplied session outside the authoritative owner common directory. Use a unique session identifier; preserve all operator-owned prior sessions. No committed state or new history deletion mechanism.

Atomic journal update: acquire `fcntl.flock`, validate schema/revision, write a temporary sibling, flush and fsync it, replace the state, and fsync the directory before releasing the lock. Journal creation/write/locking failure blocks the next mutation. Read-only report obtains a consistent snapshot. State includes manifest fingerprint, journal revision, active process/operation token, attempts/samples, per-PR last verified state, and individual completed/in-flight/uncertain/pending/skipped-by-policy follow-up steps.

`run-step` validates a known selected step and scope, records intent, executes argv unchanged via subprocess with inherited normal authentication/context, captures exit status and structured evidence, and commits its outcome. Inner helper hooks use explicit `--merge-session` scope plus the inherited execution token and append substeps to the same parent operation. Mutating merge entrypoints have no production disable flag: missing session at standalone batch merge creates/admit a complete one-PR session before any mutation; a supplied but invalid session is refused, never replaced by a cheaper one-PR admission. Session declarations for audit calls use explicit `--operation merge`; they require the same admitted full manifest. Existing pre-stage non-merge audit calls stay on their separate established route. Canonical epic/item orchestration always uses the explicit merge-operation route before calling its mutating audit helper. Never hold the journal lock across network/subprocess execution; an active execution token prevents another executor from starting a conflicting step. Tokens and scopes, not caller-provided success booleans, authorize journal transitions.

For batch merge, journal `local_merge`, `base_push`, `merge_api`, and `merge_verify` separately. Successful local merge/push retains its commit SHA and remote target even when the GitHub call/read fails. A failed mutation response is uncertain until independently verified; subprocess success also requires the existing MERGED verification. Preserve queue/admin/already-merged CLI behavior; a queued PR is Waiting, verifiably unmerged with successful submission recorded, not MERGED or Completed. Determine queued/auto-merge state from live structured `PullRequest.isInMergeQueue` / `autoMergeRequest` evidence through a read-only `gh api graphql` query, using the published PullRequest schema rather than CLI stderr or version checks. Unavailable evidence after a successful command is Interrupted with an uncertain submission, not invented Waiting. A successful auto-merge/queue submission pauses this bounded sequence; it does not change the underlying gh submission behavior. No further selected merge starts until explicit recovery verifies the queued PR MERGED; never repeat the submission.

Cleanup substeps distinguish remote deletion, local/worktree cleanup, issue closure, tracker status before/after closure, final status verification, PR disposition, and epic ledger. Keep existing cleanup and destructive-action authorization checks; this feature grants none. Track the two possible outcomes of `gh issue close --comment`: comment may exist while closure failed. Failed/unavailable or best-effort tracker markers never establish completion. Completion requires existing live verification/self-check evidence for each planned target and the provider bridge read-back above; Linear `TRACKER_ACTION_REQUIRED` remains pending.

Any execution error, signal, quota loss, uncertain response, or required follow-up failure records Interrupted locally and prevents starting another selected merge. Attempt no compensating rollback and no additional API writes solely to report an interruption. Optional final quota read may fail without erasing progress. Existing readiness stops remain policy stops, with actual verified PR state and outstanding steps recorded; they do not create merge authority.

`resume` reads the prior record and verifies potentially completed work through existing live PR state, remote base ancestry for pushed-but-unverified batch commits, stable audit markers, branch/worktree existence, owning issue state, and owning tracker status. A failed read retains the last verified fact plus unavailable current evidence; it does not overwrite merged/unmerged/uncertain state. Unknown outstanding work defers. After verified outstanding steps are identified, recalculate Admission and rerun existing current-head gates. Never repeat an uncertain merge, close-comment, audit create, or delete until live evidence resolves it. Completed steps are not replayed. Incomplete follow-up on a verified merged PR can resume without requiring its deleted head branch to exist.

`report` is usable with every remote call failing. It distinguishes Admitted, Deferred, Waiting, Completed, Interrupted, and the underlying policy stop; prints per-PR verified/uncertain state, completed/pending duties, reset/readability and an explicit recovery command. Observed spend is available only for matching limit/reset windows and nonincreasing remaining; it is an aggregate sample difference possibly including concurrent consumers. Increased balance, reset, changed limit, or unavailable final evidence yields an explicit unavailable-spend reason while preserving readable samples.

### Coordinated reversal policy

A deployment reversal reverts the helper, dependent runtime consumers, configuration/sync entry and session-aware guidance together through the normal reviewed PR path. Do not remove a gate while a dependent consumer still assumes it. Before disabling the new execution path, stop new merge operations and resolve active Waiting/Interrupted sessions through live verification and authorized follow-up; retain all journals and recovery/report evidence. Reversal does not roll back remote merges or delete branches, worktrees or session history. Preserve a schema-compatible report/recovery reader for existing sessions; if a reverted release cannot read their schema, it must refuse execution and direct the operator to the retained compatible reader rather than migrate, discard or replay state. New schema versions require explicit compatible-reader/recovery validation before rollout. Test coordinated consumer shipment and unknown-schema refusal; manually verify the retained reader reports a pre-reversal Interrupted fixture without replay.

### Concurrency safety checklist

| Required item | Decision |
| --- | --- |
| Shared mutable state guards | Advisory filesystem lock plus atomic revisioned journal publication; root/scope validation precedes every write. This locks session bookkeeping, not GitHub quota. |
| Reentrancy / in-flight tracking | One active execution token per session; nested helper hooks inherit it. Another executor defers while recorded owner/child processes are live. No timeout-based lease stealing. |
| Event deduplication | Stable `(session, repo, PR/issue, phase, attempt)` step identities; live verification discharges stale intents rather than trusting duplicate completion messages. |
| Listener/resource cleanup | Close lock/temp/process descriptors in finally paths; forward termination to active child and record uncertainty. No recurring timers/listeners. Keep durable state on exit. |
| Initialization races | Publish complete manifest before admission; no helper dispatch against a partially initialized session. Concurrent creator collision uses exclusive creation. |
| Teardown races | Mark stopping before child termination; reject new steps. Surviving child processes keep recovery blocked until live process/state verification succeeds. |
| Error propagation | Nonzero child/hook/persist exits return structured Interrupted/Deferred; raw diagnostics are display-only. SIGKILL is recovered from the durable in-flight intent. |

## Consumer Integration and Files to Modify

### Runtime files

| File | Change and composed observable result | AC |
| --- | --- | --- |
| `scripts/development-workflow/workflow-merge-budget.py` (new) | Admission, manifest/heuristic, step execution, locked journal, verification-driven recovery and reporting as defined above. | AC1–AC7 |
| `scripts/development-workflow/workflow-lib.sh` | Small session hook wrappers, existing-target config/ownership reuse and tracker mutation/read-back hooks; normal non-session callers retain existing routing. | AC4–AC6, AC8 |
| `scripts/development-workflow/run-epic-risk-classifier.sh` | Optional `--merge-session` binding and budget metadata; maintain read-only classification and risk computation. Budget denial never becomes risk permission. | AC1–AC4, AC8 |
| `scripts/development-workflow/run-epic-delegated-gate.sh` | Consume session/manifest/current PR binding; delegated merge permission requires admitted budget plus existing gates. Static `--input` DTO evaluation can remain read-only but must verify referenced durable session evidence, never a caller-provided admitted boolean; missing binding reports `budget_deferred`. Missing/unreadable binding returns Deferred with ordinary blockers retained. | AC1–AC4, AC8 |
| `scripts/development-workflow/run-epic-audit-trail.sh` | Merge-session audit/ledger/bypass writes require first-mutation hook and durable before/after markers; explicit merge-operation audit calls require `--merge-session`; existing pre-stage non-merge audits remain allowed on their established route. | AC1, AC2, AC5, AC6, AC8 |
| `scripts/development-workflow/batch-merge.sh` | Support session across merge, delete-branch, annotate-hold, and `recheck-remaining --annotate`; per-PR merge validates membership in the frozen set, journals actual boundaries, and prevents the next merge after interruption. Standalone merge obtains a one-PR manifest; Protocol 94 always supplies its whole batch session. | AC1–AC6, AC8 |
| `scripts/development-workflow/post-merge-cleanup.sh` | Read-only target inspection; preserve session on hub/product/worktree reentry; journal fine-grained follow-up and verify existing markers/live state before completion. Standalone cleanup recovery builds a follow-up-only session; missing-session behavior cannot skip admission at a tracker or remote-cleanup mutation. | AC2–AC6, AC8 |
| `.ai-dev-workflow.yaml` | Add independently documented optional `merge_budget.graphql_reserve`; default resolution lives in helper. | AC3, AC4 |
| `sync-manifest.yaml` | Ship new helper as product runtime because injected cleanup/workflow-lib call it; retain existing hub/shared glob coverage and project-owned config treatment. | AC8 |
| `changelog.d/1890.added.graphql-budget-aware-merge-gate.md` (new) | Add normal release-note fragment with repository bold-title/issue format. | AC8 |

`workflow-config-resolver.py`, `workflow-project-reader.py`, and `workflow-portfolio-scan.py` are reused unchanged unless integration exposes a missing stable config-loader interface; that specific need is reported before expanding implementation scope. Do not edit `.github/workflows/` or suite selector behavior: new tests use existing self-declaration.

### Canonical documentation and mirrors

List these paths for implementation updates; this plan does not perform the updates:

- `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
- `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
- `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md`
- `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
- `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
- `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
- `docs/workflow/development-workflow/integrations/linear.md`
- `docs/workflow/development-workflow/guardrails-enforcement.md`
- `docs/workflow/development-workflow/README.md`
- `scripts/development-workflow/README.md`
- `AGENTS.md`
- `.claude/commands/run-item.md`, `.cursor/commands/run-item.md`, `.agents/skills/run-item/SKILL.md`
- `.claude/commands/run-epic.md`, `.cursor/commands/run-epic.md`, `.agents/skills/run-epic/SKILL.md`
- `.claude/commands/run-items.md`, `.cursor/commands/run-items.md`, `.agents/skills/run-items/SKILL.md`
- `.claude/commands/batch-merge.md`, `.cursor/commands/batch-merge.md`, `.codex/skills/batch-merge/SKILL.md`, `.agents/skills/batch-merge/SKILL.md`
- `.claude/skills/post-merge-cleanup.md`, `.claude/commands/post-merge-cleanup.md`, `.cursor/commands/post-merge-cleanup.md`, `.codex/skills/post-merge-cleanup/SKILL.md`, `.agents/skills/post-merge-cleanup/SKILL.md`
- `.claude/agents/item-orchestrator.md`, `.cursor/agents/item-orchestrator.md`, `.codex/skills/workflow-item-orchestrator/SKILL.md`, `.agents/skills/workflow-item-orchestrator/SKILL.md`
- `.claude/agents/orchestrator.md`, `.cursor/agents/orchestrator.md`, `.codex/skills/workflow-orchestrator/SKILL.md`, `.agents/skills/workflow-orchestrator/SKILL.md`
- `.codex/skills/workflow-implementer/SKILL.md`, `.agents/skills/workflow-implementer/SKILL.md`

Aliases `.claude/commands/run-item-work.md`, `.cursor/commands/run-item-work.md`, and `.agents/skills/run-item-work/SKILL.md` retain their canonical forwarding; update only if the residual check finds duplicated merge instructions rather than forwarding. `apply-readiness-labels.sh`, `workflow-batch-plan.sh`, `security-advisory-classifier.sh`, and `workflow-next-action.sh` remain read-only decision/pre-stage consumers; they do not acquire a session requirement merely because they refer to risk/gate/batch concepts. Existing portfolio scan/run-work routing remains outside scope. `REVIEW.md`, planning/spec protocols, project-domain/database placeholders, and design assets receive no new global checklist.

At Protocol 91/95, readiness -> frozen manifest -> admission -> operation-owned audit -> ordinary current-head risk/delegated gate -> existing merge -> verified follow-up -> report is the observable ordered path. At Protocol 94, discovery/readiness exclusions -> frozen batch -> whole-set admission -> one PR at a time with sibling rechecks is the path; previously documented continuation after API/cleanup failure now routes to Interrupted. Risk holds and exceptional bypass audit writes are covered after admission; denied budget writes neither holds nor remote deferral comments. An authorized bypass still executes exactly the named current-head action once through `run-step`, followed by live state/audit verification.

### Rule 5 complete direct-consumer enumeration

Population: runtime helpers and active command/skill/protocol surfaces that name the affected executable helpers; historical development artifacts and executable test fixtures are excluded from this runtime population and covered separately by Testing Strategy. At the Verification Log snapshot, the following exact query produced the complete classified result below (proposed parallel guidance mirrors are listed separately above):

`rg -l '(^|[^[:alnum:]_-])(run-epic-delegated-gate|run-epic-risk-classifier|batch-merge|post-merge-cleanup|run-epic-audit-trail)\.sh' .agents/skills .codex/skills .claude .cursor docs/workflow/development-workflow/protocols scripts/development-workflow --glob '!**/tests/**' | sort`

| Matching consumer | Required observable disposition |
| --- | --- |
| `.agents/skills/run-epic/SKILL.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.agents/skills/run-item/SKILL.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.agents/skills/run-items/SKILL.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.agents/skills/run-items/agents/openai.yaml` | Unchanged UI metadata; no executable merge operation or admission authority. |
| `.claude/agents/item-orchestrator.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.claude/agents/orchestrator.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.claude/commands/batch-merge.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.claude/commands/post-merge-cleanup.md` | Update cleanup and subsequent CLI/MCP tracker reconciliation to remain in the same session; independent live bridge read-back precedes completion. |
| `.claude/commands/run-epic.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.claude/commands/run-item.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.claude/commands/run-items.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.claude/skills/post-merge-cleanup.md` | Update cleanup and subsequent CLI/MCP tracker reconciliation to remain in the same session; independent live bridge read-back precedes completion. |
| `.codex/skills/batch-merge/SKILL.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.codex/skills/post-merge-cleanup/SKILL.md` | Update cleanup and subsequent CLI/MCP tracker reconciliation to remain in the same session; independent live bridge read-back precedes completion. |
| `.codex/skills/workflow-item-orchestrator/SKILL.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.codex/skills/workflow-orchestrator/SKILL.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.codex/skills/workflow-orchestrator/agents/openai.yaml` | Unchanged UI metadata; no executable merge operation or admission authority. |
| `.cursor/agents/item-orchestrator.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.cursor/agents/orchestrator.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.cursor/commands/batch-merge.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.cursor/commands/post-merge-cleanup.md` | Update cleanup and subsequent CLI/MCP tracker reconciliation to remain in the same session; independent live bridge read-back precedes completion. |
| `.cursor/commands/run-epic.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.cursor/commands/run-item.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `.cursor/commands/run-items.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `scripts/development-workflow/README.md` | Update merge execution/handoff guidance to the canonical session-before-audit route and durable outcomes. |
| `scripts/development-workflow/apply-readiness-labels.sh` | Unchanged pre-stage readiness/risk consumer; completes before the merge session. |
| `scripts/development-workflow/batch-merge.sh` | Update mutating boundaries to journal and honor selected whole-set admission; Interrupted/Waiting stop additional merges. |
| `scripts/development-workflow/closing-keyword-lib.sh` | Unchanged ownership/closing-reference parser; comment-only cleanup references, no mutation entrypoint. |
| `scripts/development-workflow/post-merge-cleanup.sh` | Update inspection/reentry and all cleanup mutations to the authoritative session; verify owned tracker outcomes before completion. |
| `scripts/development-workflow/run-epic-audit-trail.sh` | Update explicit merge-operation audit mutations to require admission and journal intent/read-back; pre-stage audit route remains separate. |
| `scripts/development-workflow/run-epic-delegated-gate.sh` | Update actual merge decision: require durable admission plus unchanged readiness/risk gates. |
| `scripts/development-workflow/run-epic-risk-classifier.sh` | Update optional session binding/metadata; ordinary classification stays read-only. |
| `scripts/development-workflow/security-advisory-classifier.sh` | Unchanged read-only security evidence/classification; existing gate still enforces its result. |
| `scripts/development-workflow/select-test-suites.sh` | Unchanged test registry/selection consumer; new suite self-declares runtime coverage. |
| `scripts/development-workflow/validate-workflow-hub-skeletons.py` | Unchanged required-runtime inventory validation; helper path remains shipped, no merge authority. |
| `scripts/development-workflow/workflow-batch-plan.sh` | Unchanged read-only batch planning; execution handoff admits the selected full set. |

### Shared tracker-helper consumer enumeration

The changed existing `workflow-lib.sh` entrypoint is `update_tracker_status_best_effort`; newly introduced session wrappers have no pre-existing callers. Independently reproduce its existing caller population with:

`rg -l 'update_tracker_status_best_effort' .agents .codex .claude .cursor docs/workflow scripts/development-workflow --glob '!**/tests/**' | sort`

| Matching consumer | Required observable disposition |
| --- | --- |
| `docs/workflow/development-workflow/integrations/github-projects.md` | Unchanged provider/status reference; existing helper markers and canonical event vocabulary remain valid. Merge-operation lifecycle requirements reside in updated owning protocols. |
| `docs/workflow/development-workflow/integrations/linear.md` | Update existing owning protocol/provider guidance to carry session and independently verify pending tracker work before completion. |
| `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | Update existing owning protocol/provider guidance to carry session and independently verify pending tracker work before completion. |
| `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Update existing owning protocol/provider guidance to carry session and independently verify pending tracker work before completion. |
| `docs/workflow/development-workflow/tracker-status-mapping.md` | Unchanged provider/status reference; existing helper markers and canonical event vocabulary remain valid. Merge-operation lifecycle requirements reside in updated owning protocols. |
| `scripts/development-workflow/add-backlog-item.sh` | Unchanged backlog creation route outside merge-operation scope; no session means existing best-effort behavior. |
| `scripts/development-workflow/graduation-closeout.sh` | Unchanged integration graduation route outside this delegated/batch merge operation; no session means existing status behavior. |
| `scripts/development-workflow/post-merge-cleanup.sh` | Update composed merge follow-up to carry the authoritative session and honor journal failure/pending state. |
| `scripts/development-workflow/prepare-release-post-merge-cleanup.sh` | Update composed merge follow-up to carry the authoritative session and honor journal failure/pending state. |
| `scripts/development-workflow/tracker-status-for.sh` | Unchanged canonical status resolver/marker adapter. It captures helper output, reports TRACKER_STATUS_RESULT=failed/deferred, and can still exit zero for best-effort failure. A supplied-session workflow-lib hook persists Interrupted/pending before returning; run-step inspects authoritative journal plus independent target read-back and fails regardless of this adapter exit. The canonical merge caller never treats its zero exit as completion. |
| `scripts/development-workflow/workflow-lib.sh` | Update owning function with session-bound intent and independent read-back; preserve existing non-session routing and machine markers. |

Session-bound failure propagation is journal-first: inability to persist intent prevents a tracker mutation; unavailable/mismatched read-back records Interrupted/pending before emitting the existing failure/deferred markers. A surrounding `run-step` returns nonzero for journal failure/pending even when `tracker-status-for.sh` preserves its best-effort zero exit. Test the actual adapter composition with mutation failure, skipped update and unavailable read-back, asserting durable pending reconciliation and no subsequent selected merge. Non-session backlog/graduation/release callers keep their existing contracts.

## Testing Strategy

Use mocked Python unit tests and shell integration tests against real helper composition, with fake `gh` and private temporary Git repositories. No real merges, destructive user worktree operations, tracker writes, or portfolio scans. Test case enumerations below express coverage intent, not binding fixture counts.

New files:

- `scripts/development-workflow/tests/test-workflow-merge-budget.sh` — selectable shell entrypoint invoking Python tests.
- `scripts/development-workflow/tests/test_workflow_merge_budget.py` — unit/state/locking and composed helper tests.
- `scripts/development-workflow/tests/fixtures/workflow-merge-budget/` — synthetic selected manifests, quota/PR/tracker responses and fake command event logs, each fixture tied to a coverage class.

Update existing integration suites `test-run-epic-delegated-gate.sh`, `test-run-epic-risk-classifier.sh`, `test-run-epic-audit-trail.sh`, `test-batch-merge-recheck-remaining.sh`, `test-batch-merge-checkpoints.sh`, `test-batch-merge-changelog-race.sh`, `test-post-merge-cleanup.sh`, `test-select-test-suites.sh`, `test-sync-template-mode-scopes.sh`, `test-sync-template-apply-modes.sh`, and `test-check-sync-manifest-coverage.sh` for budget-aware compositions/runtime shipment. Existing bare merge tests add mocked `gh api rate_limit` responses and obtain real helper-created synthetic sessions rather than passing a test-only disable option or caller-trusted admission payload. Add `# covers:` headers in the new selectable shell suite for the runtime files, effective config, and fixture directory; provide focused selector proof that helper changes select it. Do not introduce prose-matching documentation tests or a new CI workflow.

| Coverage class | Observable consumer proof | AC |
| --- | --- | --- |
| Sufficient quota, exact equality, one below, whole unaffordable batch | Mock event log shows quota before first mutation; lower-budget run has no remote mutation and no merged prefix. | AC1–AC3 |
| Malformed quota/reserve/config/provider/owned target | `begin` and delegated/batch handoffs produce Deferred, preserve states and never use core quota. | AC2, AC4 |
| Interrupted merge response and pushed-base/GitHub divergence | Base push intent/SHA survives failed merge/state reads; no subsequent selected merge starts. | AC5, AC6 |
| Cleanup/tracker/audit failure, best-effort zero exit, Linear pending/read-back | Actual composed cleanup retains merged fact and pending per-target reconciliation rather than reporting completion; bridge proof must follow recorded intent and an independent matching live read-back. | AC5, AC6, AC8 |
| Resume with live merged/unmerged/uncertain evidence | Verified merge is not duplicated; unavailable reads preserve old states; projection covers verified remaining work only. | AC2, AC6 |
| Final samples | Reset/limit/increase/unavailable cases retain individual samples and explain unavailable spend/concurrent consumption. | AC7 |
| Policy and CLI behavior | Existing risk/head/CI/checkpoint/ownership stops persist; mock argv confirms merge/queue/admin route unchanged; budget adds no authority. | AC8 |
| Queue/auto-merge submission and explicit recovery (`test_composed_queue_waiting_recovery`) | Actual batch/delegated composition records Waiting, verified unmerged state and pending follow-up after one submission; no next selected merge starts. Explicit resume verifies live MERGED before follow-up/next PR and never resubmits the queued merge. Unavailable queue evidence is Interrupted/uncertain. | AC5, AC6, AC8 |
| Journal restart/race/signal | Parallel executors, nested hooks, torn-write simulation, stale intent, kill/restart and root/path mismatch stop safely with retained local evidence. | AC5, AC6 |

### Parser-risk edge cases and unit mapping

`test_workflow_merge_budget.py` covers these concrete input classes:

| Input | Expected validation/test class |
| --- | --- |
| Reserve omitted versus explicit `null`, empty string, `-1`, `+1`, `1.5`, `true`, list/map | Omitted default; explicit invalid values Deferred (`test_reserve_resolution`). |
| Quota with core-only resource, string/bool remaining, negative reset, remaining > limit, zero limit, past reset, errors/partial object | Quota unavailable/Deferred without remote mutations (`test_quota_validation`). |
| Selected IDs `12`, `"12"`, `"#12"`, `"12x"`, duplicate repo/PR entries, same number in different repositories, short/uppercase/invalid head | Strict typed scoped identity; no accidental cross-repo coalescing (`test_manifest_identity`). |
| Multi-issue refs, qualified foreign repo ref, nested config mappings and shared/local overrides | Existing ownership extraction preserved, malformed/ambiguous projection Deferred (`test_target_ownership_and_config`). |
| Missing/unknown step, completion without intent, duplicate completion, uncertain step declared completed without live evidence | Schema/state-machine rejection (`test_journal_transition_validation`). |
| Session `../` path, symlinked parent/state, wrong common directory, foreign-owned storage | Block before mutation (`test_session_storage_validation`). |
| JSON duplicate keys, nonfinite numeric tokens, unrecognized schema version | Reject rather than accepting last-key overwrite (`test_json_contract_validation`). |

No suppression directive is introduced. Structured enum/field contracts govern parsing; unseen external text remains diagnostics, not a classification trigger.

### Seed data and smoke

Synthetic fixtures cover single PR, ordered batch, product/hub ownership, multi-issue cleanup, no-tracker and Linear pending cases; no production data or credentials. The smoke runbook walks sufficient/equality admission, unaffordable whole batch, interrupted-after-merge, offline local report, explicit recovery, and unavailable final sample. Implement it with the corresponding mocked integration suite, not a live merge or an invented visual baseline.

## Implementation Order

1. Revalidate Operational Assumptions, merged amendment and source/consumer inventory; confirm the active implementation branch/worktree and owning repository before edits.
2. Implement Admission, config reuse, manifest inspection and component arithmetic; add unit coverage for boundary/default/unknown evidence behavior (AC1–AC4).
3. Implement Durable Execution/Recovery, atomic state/locks/argv execution and offline reporting; prove interrupted intent survives remote outage and process restart (AC5–AC7).
4. Wire runtime consumers from the runtime table, including nested cleanup/hub reentry and separate base-push/merge verification. Preserve CLI argv and provider ownership; prove first-mutation ordering at delegated and full-batch composed sites (AC1–AC6, AC8).
5. Update the canonical/mirrored documentation inventory, smoke runbook, release fragment and product runtime sync entry (AC8). New executable snippets explicitly launch Bash and declare a `bash` contract; portable caller snippets use `bash-zsh` with both-shell evidence when positional splitting/iteration appears.
6. Run selected workflow suites, normal shell/Python checks, `git diff --check`, Markdown lint for the plan/runbook/fragment, and `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`. Validate suite selection and runtime sync coverage; fix failures before readiness. Run `python3 scripts/lint/lint-graphql-query-literals.py scripts` and perform one read-only live validation of every new/changed GraphQL query returning data against an explicitly known PR/issue. Queue verification uses a known PR and never submits a merge or mutates a tracker; preserve redacted query/result/head evidence. Mock-only merge smoke remains mandatory.
7. Prove admission enforcement by temporarily planting a first-mutation/session-binding violation at the definitive admission predicate in `workflow-merge-budget.py`. Record the actual file/line and revision, demonstrate the composed mocked zero-mutation test fails, remove the plant and show the same test passes. Do not commit the plant or exercise it against real GitHub mutations.
8. Produce residual evidence: rerun the Consumer Log search, enumerate every operation-owned remote mutation path, and show each runs through a session intent hook or is explicitly outside merge operation scope. Include mocked logs for initial deferral, interruption, and recovery and the unchanged CLI-argument proof. Existing policy readiness gates/reviewer requirements still apply before the implementation PR is human-ready.

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Heuristic underestimates deep pagination/concurrent spending | Explicit margin/reserve, honest reporting and durable interruption; no upper-bound or atomicity claim. |
| Missed mutation before admission | Composed event-log tests and residual mutation inventory cover audit/hold/bypass/merge/cleanup, not only the final gate. |
| Cleanup loses journal context when changing checkout | Physical git-common-dir session binding and explicit inherited session/token on reentry. |
| CLI success hides pending queue or reconciliation | Existing live verification establishes MERGED/status/audit outcomes; local success never implies completion. |
| Ledger failure after successful merge | Local journal persists merged fact and pending audit; report/recovery works without GitHub. |
| Parallel recovery repeats an uncertain action | Session execution tokens, liveness checks and independent live reconciliation before new admission. |

## Document Quality Gate Preparation

Complex workflow decision-gate matrix applies. The plan PR records a six-check matrix coherence preflight against the amended spec: initial rows partition unknown/insufficient/sufficient evidence; equality belongs to admitted; policy stops do not grant permission; admitted failures are Interrupted; successful queue submission is Waiting without replay; recovery retains historical states; Completed requires every owned planned follow-up verified. Attach per-rule outcomes and the actual committed plan revision SHA in the PR description.

Gate B: runtime/state/locking behavior justifies executable mocked tests; prose-only artifacts receive ordinary lint and review, not a custom documentation parser. All fixture enumerations are indicative coverage intent. The bounded same-surface check above is discharged; final documentation-stage alignment is required before readiness.

# Paired release merge sessions — Implementation Plan

**Spec**: [Approved requirements](1_1941-paired-release-budget_specs.md)
**Smoke test runbook**: [Isolated release-session checks](../../../testing/workflow/1941-paired-release-budget.smoke-test.md)

## Summary

**Approach**: Extend the existing owner-bound merge journal with an explicitly
validated release pair and release-specific verification duties. Reuse the release
cleanup helper's scope extraction and provider routing, adding a read-only scope
projection and session-aware mutation boundaries. Preserve ordinary sequential
admission and every existing authority gate.

**Estimated complexity**: L. Admission, ordering, reconciliation and recovery cross
the Python journal and Bash cleanup boundary; their failure paths need composed
tests. The approved spec settles the sequencing; no architectural decision is open.

**Dependencies**: Spec PR #1943 merged at `d175cb371e3d7787da5fca722f065c9aa602150a`.
No other work item is part of this invocation.

## Verification Log

All repository observations below were gathered at
`d175cb371e3d7787da5fca722f065c9aa602150a`, on 2026-10-10 at 17:35 UTC.

| Check | Reproducible command | Result |
| --- | --- | --- |
| Journal sequencing and verification | `rg -n -e 'def before' -e 'def verify' -e 'def resume' -e 'preceding selected' -e 'def estimate' scripts/development-workflow/workflow-merge-budget.py` | `before` blocks later selected PRs on every earlier duty; `verify` and `resume` own independent discharge/reconciliation. |
| Release cleanup scope and provider mutations | `rg -n -e 'append_issues_from_changelog' -e 'detect_omitted_merged_items' -e 'record_release_for_issue' -e 'update_tracker_status' -e 'finalize_release_marker' -e 'merge-session' scripts/development-workflow/prepare-release-post-merge-cleanup.sh` | Scope can expand during cleanup; stamping, tracker updates and finalization exist; no session argument exists. |
| Stamp evidence | `rg -n -e 'record_release_for_issue' -e 'milestone' -e 'finalize_release_marker' scripts/development-workflow/workflow-lib.sh` | GitHub stamping assigns a version milestone; finalization closes that milestone. Linear emits deferred guidance. |
| Runtime consumers | `rg -l -e 'workflow-merge-budget.py' -e 'workflow_merge_budget_' scripts --glob '*.sh' --glob '*.py' --glob '!**/tests/**'` | Consumer enumeration and expected paths are recorded below. |
| Release protocol entrypoints | `rg -n 'prepare-release-post-merge-cleanup.sh' docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md scripts/development-workflow/README.md` | Protocol 05 and the helper reference contain the release-cleanup invocation guidance. |
| Regression harnesses | `rg --files scripts/development-workflow/tests -g '*merge*budget*' -g '*prepare-release*'` | Existing Python journal suite and Bash release-cleanup suite provide the extension points listed below. |
| Template delivery | `rg -n 'workflow-merge-budget.py' sync-manifest.yaml` | Existing helper is already delivered through the manifest; this plan adds no runtime module. |
| Design assets | `rg -n 'Design assets' .git/devsession-1941/issue-body.md`; `rg --files docs/specs/developments/20261010120648_1941-paired-release-budget` | No UI or reference asset is supplied; smoke tests require no visual baseline. |
| Application E2E fixture obligation | `rg -n -i 'E2E regression|placeholder' .github/workflows/e2e-regression.yml`; `rg -n 'path/to/committed/spec|TODO.*path convention' docs/testing/README.md` | CI names its job `E2E regression (placeholder)`; the testing guide still has an unfilled committed-spec path and TODO convention. The application E2E fixture obligation is not applicable; workflow harness coverage remains required. |

### Consumer outcomes at the composed call site

The runtime-consumer search above yields the following execution surfaces. Test
consumers remain covered by their existing harnesses plus the new release cases.

| Consumer | Expected composed behavior |
| --- | --- |
| `workflow-merge-budget.py` | `begin` freezes pair duties; `before` scopes the ordering exception; `after` verifies each duty; `resume` resolves unknown outcomes before retry. |
| `workflow-lib.sh` | Existing before/after hooks and tracker bridge retain their contracts; the release caller supplies the frozen session and owning PR. |
| `post-merge-cleanup.sh` | Ordinary cleanup remains sequential; paired releases use their dedicated release cleanup route. |
| `batch-merge.sh` | Ordinary selected sequences retain the earlier-follow-up barrier; no implicit pair detection. |
| `run-epic-audit-trail.sh` | Explicit frozen pre/final markers continue through admitted audit steps. |
| `run-epic-delegated-gate.sh` | Durable selected-head binding still supplements all ordinary gates. |
| `run-epic-risk-classifier.sh` | Read-only risk classification and merge limits are unchanged. |
| `validate-workflow-hub-skeletons.py` | Existing runtime delivery/ownership checks still validate the same helper path. |

## Cross-Cutting Operational Assumption Check

| Surface | Recorded value | Source | Verified at | Bounded scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact ownership and base | This single repository owns spec, plan and implementation; development PRs target `develop` | `.ai-dev-workflow.yaml`, `AGENTS.md`, current prelude | Verification Log revision/time | Invocation item #1941 and its merged spec #1943; no competing same-surface PR evidence in the handoff | Verified |
| Delegated authority | Luis authorizes squash of #1941 stage PRs at high or lower; branch deletion, protected-file edits and scope expansion remain excluded | Explicit session decision, durable invocation binding and spec disposition | 2026-10-10 current run | All three #1941 stages only | Verified |

Implementation rechecks these sources before editing and records `Still valid`;
changed or unverifiable evidence at that start gate stops advancement.

## Layer-by-Layer Changes

### Journal and release coordination

Modify `scripts/development-workflow/workflow-merge-budget.py`:

- Add an optional explicit `releasePair` manifest contract, binding version,
  production PR and backport PR to the selected ordered pair. Validate unique PRs,
  shared repository/root/reviewed release head and branch, production `main`,
  distinct approved backport base, matching version and complete scope projection.
  Reject unknown/malformed pairing inputs; a branch name alone is insufficient.
- Freeze finalized changelog scope from the reviewed release commit, including
  confirmed omitted shipped items. Assign shared duties to the backport participant
  once; production retains a cleanup-completion barrier rather than early deletion.
- Add explicit publication, per-issue release-stamp and release-marker-finalization
  phases. Derive owning tracker duties using the existing provider configuration.
  Weight every release duty and audit in the operation's conservative projection.
- Permit the backport edge only for this validated pair after fresh independent
  production merge and publication verification. All other selected sequences
  remain governed by the current preceding-follow-up rule.
- Verify regular merge ancestry for the release pair, dereference annotated or
  lightweight tags, compare the version tag with the production merge commit,
  and require a published, non-draft GitHub Release. Use structured GitHub evidence,
  with failure or unknown evidence stopping progression.
- Preserve completed/uncertain/pending facts in recovery. Resolve each attempted
  mutation by live read-back; only independently known outstanding duties can
  become retryable. Queue submissions retain Waiting and prohibit resubmission.
- Independently verify GitHub issue milestone assignments, Released tracker state,
  milestone finalization and audit bodies. Deferred Linear/provider work cannot
  imply Completed; preserve the existing owning-provider bridge and routing.

### Release cleanup boundary

Modify `scripts/development-workflow/prepare-release-post-merge-cleanup.sh`:

- Add read-only `--inspect-targets` with a reviewed `--release-head`. It emits
  finalized scope/provider duties without deleting, stamping, updating or locking
  mutation resources. Read the changelog from that commit, use commit ancestry
  for omitted-shipped membership and fail closed on unavailable projection inputs.
- For this inspection route, replace the legacy publication-date window with
  exhaustive, validated pagination of the owning GitHub Project's issue items
  currently in `Merged`. Filter candidates to the owning issue repository,
  exclude references already present in the exact version's changelog section,
  then resolve each candidate's closing merged PR evidence and test its merge
  commit against the reviewed release head. Add only proven ancestors; proven
  non-ancestors remain outside the frozen scope. This deliberately uses no current
  tag, Release timestamp, issue-close time window or previous-tag date. Missing,
  malformed, truncated or ambiguous membership evidence defers admission rather
  than silently dropping candidates. Preserve the legacy date-window algorithm
  for non-session cleanup and the existing non-GitHub-Projects provider routes.
- Add `--merge-session`; validate the frozen pair, owner, version, branch, base
  and item scope before any affected mutation. Carry the same session through
  component-repository routing and linked checkout reentry.
- Wrap the shared cleanup in its declared executor and journal actual remote/local
  cleanup, each release stamp, tracker duty and milestone finalization. Read back
  the owning duties instead of trusting best-effort stdout or zero exit.
- Refuse cleanup until both regular merges and production publication independently
  verify. Consume frozen scope; never auto-add post-admission work. Honor declared
  retention policy without granting deletion authority.
- Keep the existing non-session/single-release route and component evidence
  validation intact. Session completion remains stricter than a legacy best-effort
  helper result. Session JSON mode must not mix progress logs with JSON evidence.

### Concurrency safety

Multiple executor processes can access the journal. The release extension uses
the existing process coordination contract; it introduces no listener/timer API.

| Safety item | Decision for paired-session execution |
| --- | --- |
| Shared mutable state | Keep journal locking, atomic publication and revision comparison around state transitions; remote reads never authorize overwriting a changed revision. |
| Re-entrancy / in-flight tracking | Durable active executor identity/token permits declared owning nested duties and rejects unrelated executors or replay. |
| Deduplication | Completed/uncertain step identities require reconciliation; a verified queue submission cannot be submitted again. |
| Listener/resource cleanup | No listeners are registered; preserve child-process liveness and existing cancellation bookkeeping until verified recovery. |
| Initialization races | Pair identity, scope and duty projection are durable before execution; the first owned hook verifies inputs/quota before launching mutation. |
| Teardown races | Cancellation/interruption retains attempted intent and child identities; no next merge runs until the existing recovery gate proves executor termination and live outcomes. |
| Async error propagation | No new callback boundary; subprocess failure or failed independent evidence propagates to a stopped journal outcome, preserving pending/uncertain duties. |

The existing Bash hooks accept arbitrary declared phase/step arguments; modify
`workflow-lib.sh` only if composed tests demonstrate an essential hook integration
gap. Any such change stays limited to release-session duty execution.

### Files to modify

The execution scope is the journal and cleanup files above, these existing test
surfaces, the Documentation Updates list, and the #1941 changelog fragment:

- `scripts/development-workflow/tests/test_workflow_merge_budget.py`
- `scripts/development-workflow/tests/fixtures/workflow-merge-budget/fake-gh.py`
- `scripts/development-workflow/tests/test-workflow-merge-budget.sh` — suite coverage metadata as needed.
- `scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh`
- `changelog.d/1941.fixed.paired-release-budget.md`

No application, database, UI, CI workflow, local configuration, checkpoint-policy,
agent guidance or risk-classifier changes are needed. There is no new cross-cutting
review checklist. Existing journal delivery in `sync-manifest.yaml` suffices.

### Scoped lifecycle contract

This table is ordered. It applies to explicit paired-release execution; ordinary
sequences continue through the existing journal gate. Authorizing review/merge,
and authorizing deletion, remain separate inputs.

| Input at the owning execution edge | Decision | Discharge point |
| --- | --- | --- |
| Identity/scope/projection missing, malformed or changed | Refuse admission/affected mutation | `begin` and first operation-owned hook |
| Outstanding operation plus reserve exceeds observed quota | Deferred; no fresh operation-owned writes | Whole-set admission |
| Waiting, Interrupted, unrelated/stale executor or uncertain mutation outcome | Stop execution; require verified recovery | `before` / `resume` |
| Existing next-action authority/readiness gate fails or is unknown | Refuse that action | Delegated gate and current-head readiness outside the journal |
| Admitted pair, production known unmerged/not submitted, ordinary gates pass | Allow production regular merge | Session merge executor and independent verification |
| Production merge/publication unknown or mismatched | Refuse backport and shared cleanup | Publication verifier at the pair edge |
| Admitted pair, production/publication verified, backport known unmerged/not submitted, ordinary gates pass | Allow backport regular merge | Pair-scoped ordering gate and independent verification |
| Either regular merge not independently verified | Refuse shared cleanup | Release cleanup entry and each release duty |
| Both merges/publication verified, frozen follow-up pending | Execute only authorized outstanding duties | Shared cleanup executor and per-duty read-back |
| All owned duties independently verified | Completed | Existing completion predicate over all participants |

An owning live executor may advance declared nested duties with the same session
and execution token under the existing lock. This is authorized continuation,
not uncertain mutation replay; the executor-stop row excludes that path.

## Testing Strategy

**Coverage intent**: Extend the existing journal and release-cleanup harnesses with
real temporary Git repositories and deterministic boundary mocks. The following
scenario classes are indicative, not a binding fixture enumeration. They cover
observable ordering, accounting and recovery behavior without constructing a
separate validation framework.

| Coverage class | Automated evidence | Spec AC |
| --- | --- | --- |
| Valid pair; publication before backport; shared cleanup after both | Python journal suite plus Bash cleanup entrypoint | AC1, AC4, AC7 |
| Whole-set quota and scope-duty projection | Python admission tests, additional shipped items and independently readable frozen manifest | AC2, AC3 |
| Pre-publication omitted scope | Admission with both current tag and Release absent; exhaustive owning-project Merged candidates include proven ancestors, exclude non-ancestors and defer unknown membership | AC2, AC3 |
| Invalid identities, stale heads/version/scope, unknown publication | Plant each violation at the actual composed journal/cleanup boundary, show refusal, remove it and show permission | AC3, AC4 |
| Recovery after production merge, during publication, after backport and during partial cleanup | Persist journals, interrupt fixture executors, resume with live boundary state; assert no duplicate merge/stamp submissions | AC5 |
| Offline evidence and verified queue submission | Existing failure/Waiting fixtures extended to paired routes | AC6 |
| Stamp/tracker/finalization mismatch or deferred provider work | Independently observable milestone/tracker mocks; component/Linear route regressions | AC7, AC9 |
| Ordinary earlier cleanup remains incomplete | Existing sequential test plus a planted release-like branch without explicit pairing | AC8 |

Parser-risk applies to finalized changelog scope extraction. Cover concrete inputs:
`#12` beside punctuation; `thing#12` and `#0` negative lookalikes; `#12 #13 #12`
on one line; version sections `[1.2.3]` versus `[1.2.30]`; omitted items merged
into an unrelated integration branch; and unknown/malformed scope responses.
Map these to the existing Bash cleanup tests and Python admission tests. Suppression
directives are not introduced. See Concurrency safety for the process-level
shared-state obligations.

The following indicative unit-test mapping lives in
`scripts/development-workflow/tests/test_workflow_merge_budget.py`; its tests
exercise the read-only scope boundary with the existing Bash harness providing
provider-routing integration coverage.

| Concrete input | Planned automated unit test |
| --- | --- |
| `(#12), #13.` boundary punctuation | `test_release_scope_boundary_references` |
| `thing#12`, `#0`, and absent matching section | `test_release_scope_negative_references` |
| `#12 #13 #12` on a line | `test_release_scope_multiple_references_deduplicated` |
| `[1.2.3]` beside `[1.2.30]` | `test_release_scope_exact_version_section` |
| Omitted issue merged outside the selected head ancestry | `test_release_scope_omitted_unshipped_item_excluded` |
| Unavailable/malformed projection response | `test_release_scope_unknown_response_defers` |

Run the focused suites, ShellCheck for modified shell files, workflow shell guard,
GraphQL literal lint, Markdown and heuristic lint, and the diff-aware workflow
shell snippet lint against `origin/develop`. New/changed GraphQL literals require
one live read-only validation; unchanged query structure can cite its exemption.
Protocol snippets declare `bash`; use explicit Bash invocations without introducing
unverified zsh iteration behavior. CI then exercises selected workflow harnesses.

**Gate B**: Scaffolding extends existing behavior harnesses and fixture mocks. Its
volume is proportionate to durable merge ordering and failure recovery; no custom
parser is proposed merely to validate prose.

## Seed Data

Extend the versioned existing fake GitHub state and temporary-repository factories
with a shared release head, production/backport identities, regular merge commits,
tag/publication state, scoped milestones and owning tracker states. Rebuilding from
the same fixture inputs produces the same initial state; tests use no production
release mutations. The repository's e2e job is a placeholder, so there is no
application functional-suite fixture obligation.

## Documentation Updates

- `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`
- `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md`
- `scripts/development-workflow/README.md`

These identify the affected operator contract. Do not edit them in this plan PR.
Project architecture placeholders and `AGENTS.md` require no update for this fix.

## Risks & Mitigations

### Reversal handling

The optional pair contract leaves ordinary sessions readable without migration.
A code revert cannot undo completed merges, publication, stamps or tracker changes.
Before reverting, stop new paired admissions and retain the implementation revision
and owner-bound journals. Recover outstanding paired sessions with that revision's
helper and their recorded recovery command, under the original authority gates;
do not feed release-specific phases to the older helper or replay uncertain intent.
If recovery cannot independently verify all duties, preserve the journal as
Interrupted/Deferred and require a human disposition before rollback proceeds.
Completed paired journals remain immutable historical evidence. Reversal never
deletes journals, branches or releases to make an unfinished session appear complete.

| Risk | Mitigation |
| --- | --- |
| Pair exception weakens ordinary sequencing | Explicit pair validation plus composed negative regression at the backport edge. |
| Scope broadens after admission | Freeze reviewed-commit scope, verify it again before mutation and refuse drift. |
| Recovery replays an uncertain mutation | Independent read-back preserves uncertainty; retry only verified outstanding intent. |
| Legacy best-effort output implies success | Verify each owning external state before journal completion. |
| Shared branch removed prematurely | Both-merge/publication gate precedes cleanup and honors caller retention policy. |

## Implementation Order

1. Recheck the operational assumption records, approved scope and artifact ownership.
2. Implement explicit pairing, frozen release projection and phase/accounting
   support with admission tests (AC2, AC3).
3. Add production/publication/backport ordering and recovery proofs; preserve the
   ordinary sequential barrier (AC1, AC4–AC6, AC8).
4. Wire session-aware release cleanup and independent stamp/tracker/finalization
   verification through the existing provider route; test partial failures (AC7, AC9).
5. Update the files in Documentation Updates and add the changelog fragment:
   `- **Paired release merge sessions** (#1941): Coordinate production and backport merges with complete budget admission and verified release cleanup recovery.`
6. Run the smoke runbook and required checks. Produce residual evidence mapping
   every spec AC to delivered behavior/tests; any unmatched objective blocks readiness.

Completed coherent sub-parts get checkpoint commits after their checks pass;
incomplete or failing code is never committed solely for a checkpoint.

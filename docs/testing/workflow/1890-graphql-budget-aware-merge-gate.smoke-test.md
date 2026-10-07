# Smoke Test Runbook: GraphQL budget-aware delegated merging

**Feature**: #1890
**Spec**: [Approved spec](../../specs/developments/20261007181932_1890-graphql-budget-aware-merge-gate/1_1890-graphql-budget-aware-merge-gate_specs.md)
**Plan**: [Implementation plan](../../specs/developments/20261007181932_1890-graphql-budget-aware-merge-gate/2_1890-graphql-budget-aware-merge-gate_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage, when the mocked harness commands are implemented

## Prerequisites

- Use a private temporary fixture repository and fake `gh` executable first on PATH. Unexpected commands/endpoints fail; the fake must never forward to installed `gh`.
- Run the composed delegated and batch consumers, replacing only remote service/process boundaries with recording fixtures. Arithmetic-only testing does not satisfy this runbook.
- Maintain a command/event ledger recording quota reads, selected identities, audit writes, base pushes, merge calls, state verification, deletion, cleanup and tracker actions. Capture session journals separately from remote mutation counts.
- Scope all fake Git branches, worktrees, subprocesses and files to the fixture root. No live merge, issue/board write, portfolio scan, whole-board read or deletion of user resources is authorized by this runbook.
- The implementation supplies `bash scripts/development-workflow/tests/test-workflow-merge-budget.sh`, which runs the composed Python harness. Before implementation, these instructions describe coverage intent; they do not claim that an unimplemented scenario flag is available.
- Read the amended spec's Waiting/merge-queue contract and use the final plan's state names. This draft expects Waiting for verified pending/queued merge behavior, distinct from uncertain/error interruption.
- The item has no supplied graphical design reference. No login, application server, production seed data or visual-fidelity baseline is required.

## Test Data

| Input | Fixture intent |
| --- | --- |
| Single item | Ready reviewed PR, owning issue/status and normal authorized merge route |
| Epic | Ready selected PRs, bounded policy, disposition/ledger and owning hub/product scopes |
| Batch | Frozen ordered ready PR set containing an affordable prefix but unaffordable complete set in one scenario |
| Ownership | Qualified owning issue refs, multiple owned issues, foreign same-number issue, GitHub Projects/GitHub issues/none and known Linear pending route |
| Quota | GraphQL resource remaining/limit/reset independent of REST core resource; same-window and changed-window final samples |
| Failure | Quota/API outage after a verified merge, failed merge response after base push, required cleanup/tracker/audit failure and unavailable recovery reads |
| Queue | Successful unchanged `gh` argv followed by live OPEN/pending/queued evidence; later same-PR MERGED evidence |
| Journal | Durable in-flight intent, completed/uncertain/pending steps, nested cleanup context and restart after terminated process |

Use synthetic identities and deterministic timestamps. Load them through the committed fixture harness; quota/admission booleans are not accepted as production caller-supplied evidence.

## Smoke Test Steps

### Step 0: Verify fixture isolation

1. Confirm the harness resolves fake `gh` and every Git/storage root stays inside its temporary directory.
2. Inject an unexpected API call and assert that it fails locally instead of forwarding.
3. Start with empty command ledgers and a new session directory.

**Expected result**: The test cannot contact or mutate production resources. The journal and event evidence can be inspected without relying on chat history.

### Step 1: Sufficient quota reaches the existing gates

**Maps to**: AC1, AC3, AC7, AC8

1. Load sufficient GraphQL quota and the ready single-item fixture. Exercise the normal delegated composition with the existing risk, review, CI, checkpoint and ownership gates.
2. Inspect the component estimate, conservative margin, projected total, reserve, initial sample and reset in the report.
3. Verify the quota read/admission occurs before the first operation-owned audit/readiness/hold/base-push/merge/follow-up mutation. Readiness is already established; the merge sequence does not apply readiness labels.
4. Verify the merge command argv/method/head/admin policy is unchanged and MERGED is independently confirmed before cleanup/reconciliation is called complete.
5. Repeat the composition for the bounded epic path with disposition and ledger ownership.

**Expected result**: Admitted work can complete through the current gates; passing budget alone grants no merge permission. Reports label the estimate as heuristic, show margin/reserve, and identify every selected PR's verified result and required follow-up.

### Step 2: Equality admits; one point below defers the full set

**Maps to**: AC2, AC3, AC8

1. Read the harness's projected cost plus reserve for the frozen fixture. Set GraphQL remaining exactly to that threshold and rerun admission with fresh evidence.
2. Assert Admitted and ordinary gate execution. Do not assert that estimated cost is a proven bound on all future API calls.
3. Start a fresh attempt one point below that threshold. Keep REST core remaining high.
4. Assert Deferred, reported reset/recovery action, every selected PR still verified unmerged, and zero new remote/workflow mutation calls. Local journal creation is permitted and is counted separately.
5. Use the ordered batch fixture with enough points for the first PR but not the full selected set. Invoke the Protocol 94 whole-batch admission before its loop.
6. Assert the same zero-mutation result: no affordable prefix, audit/hold mutation, base push, merge, deletion or tracker action starts.

**Expected result**: Equality belongs to admission; an insufficient attempt defers its whole outstanding selected set and does not wait/poll until reset.

### Step 3: Unknown evidence never becomes affordable zero work

**Maps to**: AC2, AC4

1. Exercise missing/malformed/partial GraphQL quota, core-only response, invalid limit/reset and internally inconsistent remaining values.
2. Exercise reserve omitted separately from explicit null/empty/negative/boolean/fractional/list/map values, including local/shared/CLI resolution.
3. Exercise unknown projection from unreadable owned closing targets, unresolved repository/tracker scope or unrecognized provider.
4. Inspect mutation ledger and report for each attempt.

**Expected result**: An omitted setting may use its defined default. Explicit invalid resolved reserve or unreadable quota/projection defers with reason, available fields and zero mutation calls. REST core quota is never substituted.

### Step 4: Interruption preserves merged and pushed-but-unverified facts

**Maps to**: AC5, AC6, AC8

1. Run the admitted batch fixture. Let the first selected PR be independently verified MERGED, then fail every subsequent remote call during required cleanup/audit/tracker work.
2. Assert Interrupted, durable merged state for that PR, explicit pending follow-up and verified unmerged state for the next PR. Assert no subsequent selected merge starts.
3. In a separate fresh fixture, allow the batch base push but fail the GitHub merge response and its verification read.
4. Inspect separate base-push intent/completion/commit evidence, merge intent and uncertain outcome. Do not infer MERGED from local `MERGE_RESULT=clean`.
5. Exercise a best-effort cleanup/tracker path returning zero while a required outcome marker or live status verification is unavailable.
6. Terminate an executing fixture process after a durable intent; restart the helper against that record.

**Expected result**: The durable record survives API outage/process restart. Successful prior boundaries remain recorded; uncertain outcomes remain uncertain; required follow-up is not silently abandoned or called complete. Existing cleanup/destructive-action policy is retained.

### Step 5: Offline local report and explicit recovery

**Maps to**: AC2, AC5, AC6, AC7

1. With all fake remote calls still failing, run `report` against the Step 4 durable session. Preserve its output and journal.
2. Request explicit resume while live reads are unavailable or quota is insufficient. Verify Deferred retains prior merged/unmerged/uncertain and pending states and performs no new mutations.
3. Restore live evidence showing the prior uncertain merge actually completed; provide remote-base ancestry evidence where a base push was recorded.
4. Resume explicitly. Verify fresh budget assessment for only independently verified outstanding work, current-head ordinary gate revalidation and no repeated completed merge.
5. Restore evidence for branch, issue state, tracker status and stable audit markers. Verify already-completed closure/comment/deletion/audit actions are not duplicated; pending work alone is executed.
6. Repeat with live evidence still unable to resolve one uncertain action. Assert no blind replay and an explicit recovery action.

**Expected result**: Offline reporting works; explicit retries use new admission evidence. Recovery derives outstanding work from verified live state, preserves old facts on unavailable reads and avoids duplicate potentially completed mutations.

### Step 6: Queued work is Waiting and pauses the selected sequence

**Maps to**: AC6, AC8 and the amended spec's Waiting contract

1. Run the first selected PR through unchanged `gh` merge behavior. Return successful command status followed by valid live evidence that the PR remains OPEN and queued/pending.
2. Assert Waiting, verified current PR state and pending merge completion/follow-up. Assert no subsequent selected merge begins and no automatic queue/reset polling is introduced.
3. Verify that Waiting is not reported as MERGED, Completed, Deferred or an uncertain/error Interrupted outcome merely because `gh` returned success.
4. Resume explicitly with fresh quota and live evidence that the PR is still queued. Assert Waiting remains visible, no duplicate queue/merge submission and no next selected merge.
5. Restore live MERGED evidence and resume explicitly. Verify no repeated merge; complete verified outstanding follow-up before considering remaining selected PRs under the fresh gates/admission.
6. Separately inject unreadable/contradictory queue evidence after the command. Assert uncertainty follows Interrupted/recovery rather than manufacturing a known Waiting fact.

**Expected result**: Existing queue behavior is preserved and the caller has a complete Waiting outcome; success without MERGED never advances the rest of the sequence.

### Step 7: Final samples and concurrent consumption

**Maps to**: AC7

1. Exercise comparable initial/final samples with matching quota limit/reset and nonincreasing remaining. Inspect aggregate observed difference and concurrent-consumption wording.
2. Exercise final reset changed, limit changed, remaining increased and final evidence unavailable independently.
3. Verify reports retain each readable sample, show unavailable spend with the matching reason and do not attribute the observed difference solely to this run.
4. Make the final budget read unavailable after all required merge/follow-up facts were independently verified. Confirm this does not erase progress or create an unverified result.

**Expected result**: Spend is shown only when comparable; unavailable final quota is visible without overwriting the verified workflow outcome.

### Step 8: Existing policy and provider routing remain effective

**Maps to**: AC8

1. Exercise risk denial, stale reviewed head, failed CI, unresolved review, unsatisfied checkpoint and wrong owning repository despite sufficient budget.
2. Verify the owning consumer preserves its existing stop and does not merge. Operation-owned audit/hold attempts still occur only after admission where permitted.
3. Exercise normal, already-merged and expressly authorized exceptional-admin route fixtures. Compare recorded argv and independent result verification with the existing route.
4. Exercise qualified hub/product/multi-issue cleanup and a foreign issue with the same numeric identifier. Confirm only the existing owning targets are reconciled.
5. Exercise known Linear routing. Confirm its existing MCP action is pending until the owning orchestrator actually verifies completion; shell success or a caller-supplied boolean cannot erase pending work.
6. Verify an invalid supplied whole-batch session cannot fall back to cheaper single-PR admission. A standalone merge uses genuine helper admission and mock quota rather than an opt-out.

**Expected result**: Budget is an additional requirement. It changes neither authority, CLI semantics nor tracker ownership, and no compatibility/version pin or production disable switch is introduced.

### Last Step: Validate and shut down

- Run the committed shell suite and relevant existing delegated/batch/cleanup suites selected by the normal suite selector.
- Save fixture event logs, session records and failure reasons as implementation evidence. Record simulated verification explicitly; do not claim live merges or quota behavior were measured.
- Stop fixture subprocesses and release handles. Remove only harness-owned temporary resources; preserve durable evidence needed to inspect failed/recovery scenarios.

## Assertions Checklist

- [ ] AC1: Sufficient quota precedes the first composed mutation in delegated single-item and epic paths.
- [ ] AC2: One below/full-batch deferral makes zero mutations and recovery deferral preserves historical state.
- [ ] AC3: Equality admits and the heuristic includes all selected gates/merge/follow-up, explicit margin and reserve.
- [ ] AC4: Malformed/unavailable evidence, unknown projection and invalid resolved reserve defer; core quota is not a substitute.
- [ ] AC5: Completed/uncertain/pending local evidence survives outage and restart.
- [ ] AC6: Interruption/Waiting starts no additional merge; explicit live-verified resume avoids duplicate completed/uncertain actions.
- [ ] AC7: Reports show estimate/margin/reserve/samples and comparable aggregate spend or explicit unavailable reason.
- [ ] AC8: Delegated/batch paths retain existing readiness, risk, CI, ownership, checkpoint, audit, queue/admin/already-merged behavior.

## Seed Data Reference

| Fixture class | Scenario | How to load |
| --- | --- | --- |
| Synthetic PR/issue/project evidence | Selected singleton/epic/batch and owning target variants | Committed `tests/fixtures/workflow-merge-budget/` through the shell/Python harness |
| Fake quota/service responses | Admission boundaries, unknown evidence, outage/final-sample variants | Deterministic fake `gh` dispatch; never forward |
| Private Git/process/session resources | Push/merge divergence, restart and queued recovery | Harness creates within its temporary fixture root |

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Live endpoint or user root appears | PATH/root isolation escaped | Stop fixture execution and repair fail-closed isolation before rerun. |
| Remote audit appears before quota | Admission inserted at final gate only | Correct the composed first-mutation path and repeat event-log proof. |
| Second PR merges after failure/queue | Old continuation branch or Waiting handled as success | Route the actual caller to Interrupted/Waiting stop before its next selected merge. |
| Cleanup says complete with pending tracker | Best-effort exit status treated as verification | Consume markers and independently verify owning live target state. |
| Resume repeats completed action | Intent considered failure or stale success boolean trusted | Restore uncertainty/live-verification recovery and stable step identities. |
| Report cannot run offline | Reporting depends on a remote comment/read | Read durable local state and mark optional final evidence unavailable. |

## Known Limitations

The runbook verifies mocked composed behavior, not live GitHub quota guarantees or real merges. The conservative estimate is heuristic; remote pagination, CLI internals, concurrency and service behavior can exceed it. The feature supplies durable interruption/recovery rather than a global quota reservation or atomic rollback. Scenario selectors/fixture commands are finalized during implementation and recorded with actual evidence. No graphical reference was supplied.

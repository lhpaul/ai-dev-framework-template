# Smoke Test Runbook: GraphQL budget-aware portfolio scanning

**Feature**: #1505
**Spec**: [Approved spec](../../specs/developments/20261002145704_1505-graphql-budget-aware-scan/1_1505-graphql-budget-aware-scan_specs.md)
**Plan**: [Implementation plan](../../specs/developments/20261002145704_1505-graphql-budget-aware-scan/2_1505-graphql-budget-aware-scan_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage, when fixture commands are implemented

## Prerequisites

- Use an isolated temporary fixture repository with fake `gh` first on PATH.
  Unexpected API calls and mutations must fail; do not forward to real `gh`.
- Load deterministic fake issues, project cards, PR evidence, budget samples,
  and local/remote branch/folder inputs described in the plan's test layer.
- Use a request ledger recording endpoint/query, target, charged GraphQL cost,
  complete-record publication, and forbidden mutation attempts.
- Do not run a live `/run-work`, whole-board listing, real bounded dispatch,
  or actual archival. This invocation authorizes fixture/stub testing only.
- The proposed automated entrypoint is
  `bash scripts/development-workflow/tests/test-workflow-portfolio-scan.sh`.
  Implementation may group equivalent cases differently while preserving the
  assertions below; update this runbook to the delivered command names.
- The runner entrypoint is composed: router → canonical scan coordinator →
  snapshot-aware batch/next-action classification → report/proposal. A test
  of just budget arithmetic or a no-argument historical folder sweep is
  insufficient.

## Test Data

| Input | Fixture intent |
| --- | --- |
| Large history | At least 500 board cards, 41 current open issue identities, mostly closed terminal history, at least one valid proposal |
| Growth comparison | Identical active/in-flight identities with 50 versus 1000 terminal cards |
| Targeted commands | Single target, two-target list, epic with two children; org-project primary-empty case and foreign repository's same issue number |
| Budget | Before/after GraphQL samples with initial 4500 or greater; REST resource deliberately independent |
| Projection boundaries | Values around reserve and projection ceiling, full/partial admission equality, unknown projections, maximum membership pages |
| Failures | Projection/first-item/later-item rate limiting; non-rate API error; unavailable samples; reset/concurrent account spending |
| Titles/configuration | Parser edge cases from the plan's checklist |
| Archived card | Released item visible in primary archived-aware lookup; supported fallback and unsupported/capped limitation |

These are invented identities and generated fixtures, not production seed data.
There is no login, application server, database, or visual fidelity baseline.

## Smoke Test Steps

### Step 1: Large-board scan followed by bounded start

**Maps to**: AC1, AC2, AC6

1. Set the large-history fixture and a single quota window with sufficient
   initial budget. Reset all ledgers and use the default reserve.
2. Exercise the composed no-target scan and inspect its report and request log.
3. Assert Full scan, complete discovery of current active work, a valid proposal,
   the spec's spend labels, total GraphQL cost no greater than 1000, and after
   remaining at least the reserve.
4. Execute the recommended bounded command against the same fake budget ledger
   and tracker state. With one proposal use the single-item path; otherwise use
   at least two targets. Run genuine resolution and pre-mutation checks, with
   the first stage's mutation/dispatch replaced by a recording stub.
5. Assert correct fresh target Status/Type, no Tracker unavailable/rate-limit
   result, and a recorded first-stage start without quota reset.

**Expected result**: The composed fixture demonstrates scan-to-start cost and
fresh target resolution. Record fixture evidence explicitly; this invocation
has not verified a live board or spent real quota to test AC1/AC2.

### Step 2: Terminal history has no effect on discovery reads

**Maps to**: AC3, AC4, AC5

1. Repeat the composed scan with both growth-comparison histories.
2. Compare board-read request count and current eligible identities. Retained
   closed folders/branches must not trigger item reads.
3. For each history, resolve the single-item, pair, and epic/children paths.
   Assert current Status/Type and absence of exhaustive board calls.
4. Repeat with primary membership empty and a supported organization fallback,
   including the foreign repository's same-number card before the exact match.
5. Inject target-resolution rate limiting and inspect existing router output
   with a fake reset timestamp.

**Expected result**: Request counts stay constant for the same current work;
org target reads succeed by exact identity; rejection still reports Tracker
unavailable with reset time. No scan snapshot is consumed by later commands.

### Step 3: Partial, deferred, and bounded projection

**Maps to**: AC9, AC10, AC11, AC13, AC17

1. Set REST remaining high while GraphQL remaining is 900. Assert Deferred,
   the named low-budget reason, no projection or board requests, no proposal,
   and unchanged after GraphQL remaining.
2. Exercise reserve/projection-gate boundaries from D2, including equality.
   Below the gate no projection occurs. At the gate projection can occur but
   must stay within the fixed ceiling.
3. Set budget admitting partial but not full. Assert in-flight-only reads,
   explicit skipped Backlog discovery, and no new-start Backlog proposals.
4. Set budget passing projection gate but admitting neither coverage. Assert
   no board reads and no batch, with reset time in the report.
5. Exercise complete, unknown, and ceiling-exceeding projection inputs. Count
   whole projection spend in both costs and assert partial cost does not exceed
   full cost. Unknown must not become a zero estimate.
6. Parameterize readable starting budgets at/above reserve around every
   admitted threshold and verify the reserve invariant using charged ledger
   costs. Assert mutation counter zero for every run.

**Expected result**: Coverage follows the spec's ordered matrix and the plan's
query-bound proof; REST quota never substitutes for GraphQL quota.

### Step 4: Budget samples, reset, and other consumers

**Maps to**: AC6, AC7, AC8

1. Exercise before-only, after-only, and both budget-sample failures with no
   rate rejection. Assert spec coverage, warning and Unavailable fields for
   each permutation.
2. Repeat after-sample failure on admitted Full, Partial, and Deferred states;
   the decided coverage must remain unchanged.
3. Change reset time between samples without increasing remaining, then
   separately increase remaining without changing reset time. Both yield
   Unavailable (budget reset during scan) for spent; newer remaining/reset stand.
4. Simulate other-consumer spend reducing after remaining below reserve without
   rejecting a scan read. Full/Partial retain their coverage and show the
   below-reserve warning; Deferred does not show that warning.
5. Confirm every report, including Deferred, carries all three spend labels.

**Expected result**: Reporting reflects after evidence and observed account
spend, with no fabricated exclusive scan accounting.

### Step 5: Mid-scan rejection and incomplete evidence

**Maps to**: AC12, AC13

1. Reject a projection request, then separately the first board/evidence read.
   Assert Deferred, reason GraphQL budget ran out during the scan, no proposal,
   and no later read requests.
2. Reject a later read after publishing an in-flight fully read item. Assert
   Partial with the same exhaustion reason and only fully read eligibility.
3. Reject after fully reading a new Backlog item during an attempted Full scan.
   Assert that item is removed from new-start proposals under Partial coverage.
4. Supply incomplete Status/Type or required PR evidence. Assert HELD/unreadable
   and no actionable resume or proposed-batch record for the incomplete item.
5. Supply wrong repository/invocation snapshot and malformed JSON. Assert failure
   before classifier fallthrough to live reads. Non-rate failures retain their
   existing error semantics, not successful Deferred/full completion.
6. Inspect forbidden mutation counters and the full downstream request ledger.

**Expected result**: Atomic publication and narrowing protect proposals; scan
performs no tracker, branch, PR, board, or archival mutation and never retries
inside the invocation after rejection.

### Step 6: Bounded fallback safety and archived items

**Maps to**: AC4, AC13, AC16

1. Exercise escaped title inputs, multiple title matches, exact card at the
   candidate cap, conflicting exact cards, and no exact match with next page.
2. Assert one capped candidate request, exact identity join, and no unrestricted
   query or additional page. Unknown/capped membership must not be treated as
   absence by board-membership or update consumers.
3. Read an archived Released card through the primary connection, then supported
   archived-aware org fallback. Assert Status is preserved.
4. Exercise unsupported host/schema and archived card outside the capped
   candidate response. Assert explicit unreadable limitation without live or
   automated restore/archive action.
5. Repeat updates in the isolated fixture through existing best-effort/required
   paths, recording intended item IDs and invalidation of target caches.

**Expected result**: Supported org reads/updates preserve #1801 and identity
isolation preserves #1804; unavailable archival reads use the plan's documented
AC16 limitation instead of universal claims. Fixture updates in this step are
bounded-command regression proofs, not mutations performed by a scan.

### Step 7: Guidance and entrypoint inspection

**Maps to**: AC14, AC15

1. Read Protocol 90's subsection directly beside Step 1a rate-limit guidance.
   Confirm safe Released/Cancelled statuses, Merged/in-flight exclusion,
   canonical reconciliation of legacy Done, manual/auto-archive options, and
   restoring reopened items.
2. Confirm the integration performance note links to that subsection and states
   the archived fallback limitation tested in Step 6.
3. Search those documents for the obsolete unavoidable-full-board and
   ~3.5-minute pause claims; confirm no current scan guidance retains them.
4. Inspect each plan-listed scan mirror and confirm it routes to the canonical
   coordinator contract, rendering the distinct report categories and proposals
   solely from complete invocation evidence.
5. Confirm Linear and out-of-scope exhaustive release/retrospective readers
   retain existing contracts; framework classification regression remains green.

**Expected result**: Guidance matches delivered behavior without automatic
archival or widened workflow policy.

### Last Step: Validate and clean fixture resources

Run the delivered fixture suite and relevant regression suites; save a compact
AC/result table, coverage report, request/cost ledger, and any omission reasons
as implementation evidence. Remove only temporary fixture resources. Do not
clean user branches, change live tracker state, or present simulated acceptance
as a real board benchmark.

## Assertions Checklist

- [ ] AC1/AC2: large-history composed scan and same-window simulated first start.
- [ ] AC3/AC4/AC5: constant reads, bounded target/epic resolution, router failure.
- [ ] AC6/AC7/AC8/AC9: every spend summary, unavailable/reset/concurrent samples,
  GraphQL-specific decisions.
- [ ] AC10/AC11/AC12/AC13/AC17: matrix, projection bounds, reserve, partial
  exclusions, immediate rejection stop, and scan mutation count zero.
- [ ] AC14/AC15/AC16: adjacent archival guidance, integration cross-reference,
  archived-read support or precise limitation.

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| A real endpoint appears in the ledger | Fake `gh` forwards or PATH escaped | Stop fixture execution and restore fail-closed API stubbing |
| Scan costs more than projection | Hidden classifier call or changed query shape | Inspect composed ledger and revise/bound the call before readiness |
| Old folder is actionable | Candidate identity intersection bypassed | Enforce D1 open identities and D4 complete records |
| Foreign same-number card is selected | Number-only join | Apply shared repository-aware identity semantics |
| Target fallback cap is reported as absence | Missing unknown/absent distinction | Correct consumer branch before running mutation proofs |

## Known Limitations

This runbook is fixture-only under the user's testing scope. Live AC1/AC2 board
performance is not verified here. Project title filtering cannot prove issue
identity; unsupported/capped archival lookup behavior is the AC16 documented
alternative. No design assets were supplied, so visual fidelity is inapplicable.

# A portfolio scan must leave budget for the command it recommends — Spec

## Overview

A `/run-work` no-target scan is the documented first half of the primary
workflow: scan the portfolio, then run the recommended `/run-items` command.
Both halves draw on the same hourly GitHub GraphQL budget (5,000 points on
this repository). Today the scan reads every item on the GitHub Projects
board, including every item that finished long ago. At 514 board items, of
which only 41 belong to open issues, one scan spent the whole budget. The
`/run-items` command it had just recommended then failed, and the operator
waited about 32 minutes for the budget to reset.

This feature makes a scan's cost follow the work that is still open, not the
board's whole history. Bounded commands (`/run-item`, `/run-items`,
`/run-epic`) resolve only their own targets. Before it spends anything, the
scan checks the remaining budget. When the budget is too low for a full scan,
it narrows the scan or defers it, and says why, instead of spending the last
points. Every scan reports what it spent and what is left. Guidance on
archiving finished board items sits beside the existing rate-limit section of
the portfolio-scan protocol, because archiving is the only remedy for the
board's growth.

---

## Context and Decisions

There was no live human alignment conversation for this run. The human
accepted the run policy, which confirmed the spec checkpoint. The decisions
below were taken from the issue's acceptance criteria and the current
workflow behavior. Each one is recorded here so a reviewer can challenge it.

- **D1 — Combined fix.** The issue offers five fixes and says "pick one or
  combine". This spec combines four of them:
  - per-item reads for bounded commands (fix 2);
  - budget-aware scanning (fix 4);
  - reporting the spend (fix 5);
  - archival guidance (fix 3, as documentation only).

  It also requires the scan's own board read to scale with active items, not
  with terminal items. The issue frames the single full-board fetch as
  unavoidable. This spec treats that as the defect to fix, not as a fixed
  constraint, and leaves the mechanism to the implementation plan.
- **D2 — No cross-command snapshot reuse (fix 1 deferred).** A `/run-items`
  run makes mutating decisions such as tracker updates, branch creation, and
  dispatch. Reusing a scan snapshot taken earlier would let those decisions
  rest on stale tracker state. Once D1 makes the scan and the target
  resolution cheap, a snapshot cache is no longer needed to meet the
  acceptance criteria. See the Deferral Notes.
- **D3 — "Completes within one quota window" covers getting started, not the
  whole pipeline.** A `/run-items` run can last hours across many stages and
  review loops. No single quota window can hold all of that work. The
  measurable promise is narrower. The scan's own projected spend leaves at
  least the reserve unspent; spending by other consumers on the same account
  is outside the scan's control and is reported, not prevented (rule 10).
  The recommended `/run-items` command then resolves its targets,
  passes its pre-mutation checks, and starts its first item, all without a
  rate-limit stop. This matches the failure the issue reported.
- **D4 — Archival stays a documented operator action.** The workflow does
  not archive board items itself. Archiving changes a live, shared board. The
  guidance tells the operator which items are safe to archive and how.
- **D5 — The budget check reads the GraphQL budget specifically.** A retro
  comment on the issue (PR #1857) records a merge gate that ran out of
  GraphQL budget while the general API budget still showed points left. The
  scan's budget check therefore never uses the general (REST) API budget in
  place of the GraphQL budget.
- **Related work (reference only).** Issue #1503, now closed, made the
  `/run-work` router report a rate-limit failure as **Tracker unavailable**
  instead of **Ambiguous**. This spec keeps that behavior as it is. Open
  issue #1801 changes the same shared tracker-read helpers, for Status and
  Type reads on organization-owned projects. The two are orthogonal, but the
  implementation plan should coordinate changes to that shared surface.

---

## Definitions

- **GraphQL budget**: the hourly GitHub GraphQL points allowance of the
  account the workflow runs as. It is 5,000 points per hour on this
  repository. The budget is shared by every consumer on that account:
  parallel agents, scripts, and CI jobs.
- **Quota window**: the period between two resets of the GraphQL budget,
  one hour on GitHub.
- **Board**: the GitHub Projects board that serves as the workflow tracker
  when the tracker provider is GitHub Projects.
- **Active item**: a board item linked to an open issue in this repository.
- **Terminal item**: a board item whose linked issue is closed, or whose
  Status is `Released` or `Cancelled`. An item that meets both definitions
  (an open issue whose Status is `Released` or `Cancelled`) counts as an
  active item.
- **In-flight item**: an active item with a development folder, a workflow
  branch, or an open workflow pull request. A terminal item is never
  in-flight, even though its development folder and branches remain in the
  repository after it finishes.
- **Fully read item**: an item for which the scan has read every input the
  Protocol 90 categorization needs (its board fields and its in-flight
  evidence). An item with any of those inputs still unread is not fully read.
- **Reserve**: the GraphQL points a scan's own projected spend must leave
  unspent so the command it recommends can start. Spending by other
  consumers during the scan is reported, not prevented (rule 10). The
  default is 1,000 points. This matches the existing Protocol 90 Step 1a
  low-budget warning threshold.
- **Bounded command**: `/run-item`, `/run-items`, or `/run-epic`. Each acts
  on an explicit set of targets.
- **Scan coverage**: how much of the portfolio a scan actually read. The
  values are in Statuses / Enum Values.

---

## Use Cases

### Use Case 1: Scan, then run the recommended items, on a large board

**Actor**: Workflow operator. In an unattended session, the item orchestrator
acting for the operator.
**Preconditions**: The tracker provider is GitHub Projects. The board holds
500 or more items, and most of them are terminal. A new quota window has
started, so the GraphQL budget is close to full.

**Steps**:

1. The operator runs `/run-work` with no target.
2. The scan checks the remaining GraphQL budget. A full scan fits and still
   leaves the reserve.
3. The scan reads the active items and the in-flight work, and proposes a
   batch.
4. The scan summary reports the scan coverage, the points this scan spent,
   the points left, and when the budget resets.
5. The operator runs the recommended `/run-items` command.
6. `/run-items` resolves each target, passes its pre-mutation checks, and
   starts the first item.

**Postconditions**: When no other consumer spent budget during the scan,
the scan has left at least the reserve unspent. The
`/run-items` command has started without a rate-limit stop and without
waiting for the budget to reset.

**Information shown**:

- Scan coverage: **Full scan**.
- GraphQL points spent by this scan, points remaining, and the reset time.
- The warning **GraphQL budget below reserve after scan** when other
  consumers' spending left less than the reserve (rule 10).
- The usual Protocol 90 report categories (informational, actionable resume,
  proposed batch, held).

**Actions available**:

- Run the recommended `/run-items` command, or any bounded command.

**Considerations**:

- Other consumers on the same account can spend budget at the same time as
  the scan. The reported spend is what was observed during the scan, and the
  report says it may include spending by those other consumers.

---

### Use Case 2: Run a bounded command against a large board

**Actor**: Workflow operator or item orchestrator
**Preconditions**: The tracker provider is GitHub Projects. The board holds
500 or more items. The operator names explicit targets: one item, a list of
items, or one epic.

**Steps**:

1. The operator runs `/run-item <target>`, `/run-items <targets>`, or
   `/run-epic <epic>`.
2. The command resolves each target and reads that target's board fields
   (Status and Type) without reading the rest of the board.
3. The command continues with its normal pre-mutation checks and execution.

**Postconditions**: Target resolution has spent budget in proportion to the
number of targets (and, for `/run-epic`, the epic's child items). The total
board size did not affect the cost.

**Information shown**:

- The same target-resolution output as today.

**Actions available**:

- Unchanged from today.

**Considerations**:

- If a target-resolution read fails because the budget is exhausted, the
  existing behavior is kept. The router reports **Tracker unavailable** with
  the reset time, not **Ambiguous** (#1503).

---

### Use Case 3: Scan when the budget is too low for a full scan

**Actor**: Workflow operator or item orchestrator
**Preconditions**: The remaining GraphQL budget is too small to run a full
scan and still leave the reserve.

**Steps**:

1. The operator runs `/run-work` with no target.
2. If the remaining budget is below the projection ceiling plus the reserve
   (rule 5), the scan does no projection work and goes straight to step 4.
   Otherwise it works out the projections within the ceiling, checks the
   remaining budget against the projected cost of a full scan plus the
   reserve, and finds it too low.
3. If a partial scan fits and still leaves the reserve, the scan reads only
   the in-flight items and skips Backlog discovery. Scan coverage is
   **Partial scan (budget-limited)**.
4. If even a partial scan does not fit, the scan reads nothing from the
   board. Scan coverage is **Scan deferred (budget too low)**.
5. The summary names the reason, the points remaining, the reset time, and
   what was not covered.

**Postconditions**: The scan's own spend, including the points spent working
out the projections (rule 5), has not pushed the remaining budget below the
reserve. When the scan started below the projection ceiling plus the
reserve, it did no projection work at all. Spending by other consumers during the
scan is reported, not prevented (rule 10). The operator knows what the scan
did not cover and when a full scan will be possible again.

**Information shown**:

- Scan coverage label and the named reason (see Statuses / Enum Values).
- Points remaining and reset time.
- For **Partial scan**: what was skipped, which is Backlog discovery, so no
  new-start proposals are made. The warning **GraphQL budget below reserve
  after scan** when other consumers' spending left less than the reserve
  (rule 10).
- For **Scan deferred**: a statement that no batch is proposed. The operator
  can re-run the scan after the reset time, or run bounded commands on
  targets they already know.

**Actions available**:

- Act on the partial proposal.
- Re-run the scan after the reset time.
- Run a bounded command on known targets.

**Considerations**:

- A partial scan must never present Backlog items as new-start proposals,
  because it did not read Backlog discovery.

---

### Use Case 4: The budget runs out partway through a scan

**Actor**: Workflow operator or item orchestrator
**Preconditions**: The budget check allowed the scan. Other consumers then
spent budget at the same time, and a GraphQL read during the scan was
rejected for rate limiting.

**Steps**:

1. The scan detects the rate-limit rejection.
2. The scan stops reading the board.
3. The scan reports coverage based on what it had fully read before the
   rejection.

**Postconditions**: No item whose state was not fully read appears in the
proposed batch or under actionable resume. The operator sees the reason and
the reset time.

**Information shown**:

- Scan coverage **Partial scan (budget-limited)** when at least one item was
  fully read, or **Scan deferred (budget too low)** when none was. In both
  cases the named reason is **GraphQL budget ran out during the scan**.
- The items, or the categories, that were not covered.
- Reset time.

**Actions available**:

- Re-run the scan after the reset time.
- Act on what was fully read.

**Considerations**:

- The scan does not wait and retry inside the same invocation. The reset can
  be up to an hour away, and `/run-work` is a read-only discovery command.

---

### Use Case 5: Operator archives terminal board items

**Actor**: Workflow operator (repository maintainer with board admin rights)
**Preconditions**: The board has built up many terminal items.

**Steps**:

1. The operator reads the archival guidance beside the Protocol 90 Step 1a
   rate-limit section.
2. The operator archives the items the guidance marks as safe to archive,
   either manually or by enabling the board's built-in auto-archive rule for
   those statuses.

**Postconditions**: Active items and in-flight items stay on the active
board. Workflow status transitions still waiting to happen (for example
`Merged` to `Released` at release closeout) are not disrupted.

**Information shown**:

- Which statuses are safe to archive, which must not be archived yet, and
  why.
- How to restore an archived item whose issue is reopened.

**Actions available**:

- Archive manually, configure auto-archive, or restore an item.

**Considerations**:

- A `Merged` item is waiting for release closeout to set `Released`. It is
  not safe to archive until then.
- Items left with statuses outside the canonical vocabulary (for example a
  legacy `Done`) are not covered automatically. The guidance tells the
  operator to reconcile such an item to a canonical status before archiving
  it.

---

## Business Rules

1. **Scan cost follows active work.** The board reads in a no-target scan
   cost an amount that grows with the number of active items and in-flight
   items. It does not grow with the number of terminal items.
2. **Bounded commands never read the whole board.** `/run-item`, `/run-items`,
   and `/run-epic` resolve their targets and read those targets' board fields
   without reading every board item. Their cost grows only with the number of
   targets, plus the child items for `/run-epic`.
3. **Budget check before spending.** Before its first board read, a no-target
   scan reads the current remaining GraphQL budget. It never uses the general
   (REST) API budget in its place. It never uses a value read earlier in the
   session; the reading is taken immediately before the scan.
4. **Coverage decision.** The scan picks its coverage with the decision table
   in Complex Workflow Decision-Gate Matrix, using the remaining budget, the
   projected cost of a full scan, the projected cost of a partial scan, and
   the reserve. The table's rows do not overlap, and they are checked in the
   order listed.
5. **Conservative projection.** The projected scan costs must not
   underestimate. Working out the projections is itself bounded by the
   budget above the reserve:
   - **Projection ceiling.** Working out the projections has a fixed upper
     bound on its spend, the projection ceiling (**P**). P is known before
     any projection read, and it does not grow with terminal items. The
     implementation plan sets its value.
   - **Projection gate.** Before its first projection read, the scan checks
     the before-scan reading (rule 3) against P plus the reserve. When the
     remaining budget is below P plus the reserve, the scan does no
     projection work and reads no board items. Its coverage is **Scan
     deferred (budget too low)**, with reason **GraphQL budget too low to
     scan**. This always applies when the remaining budget is already at or
     below the reserve.
   - **Stop at the ceiling.** Projection work never spends more than P. When
     a projection cannot be worked out within P, the scan stops estimating
     and uses a conservative upper bound in its place. When no conservative
     upper bound can be derived without further reads, that projection is
     treated as exceeding the remaining budget, so the scan picks a narrower
     coverage or defers (rows 3 to 5 of the decision table).
   - **Spend accounting.** Each projected cost includes the points spent
     working out the projections. That spend happens after the before-scan
     reading, so it counts in points spent (rule 10).

   Taken together, when no other consumer spends budget during the scan, the
   scan's own spend (projection work plus board reads) never leaves fewer
   points remaining than the reserve, whatever the coverage. When the scan
   starts below P plus the reserve, its only GraphQL reads are the budget
   readings themselves (rules 3 and 10). A rate-limit rejection during
   projection work is handled as a mid-scan rejection with no item fully
   read (rule 8). The projected partial-scan cost never exceeds the
   projected full-scan cost: when the partial projection (or its
   conservative bound) would exceed the full projection, the full projection
   is used for both.
6. **Reserve default.** The reserve defaults to 1,000 points. Operators can
   configure it through one optional key in `.ai-dev-workflow.yaml`; the
   implementation plan names the key. The reserve is not configured by an
   environment variable alone. A
   configured value that is empty, not a whole number, or outside 0 to 5,000
   points is ignored with a warning, and the default is used.
7. **Partial scan content.** A partial scan reads in-flight items only. It
   skips Backlog discovery. A scan whose coverage is **Partial scan
   (budget-limited)**, for either reason, never proposes a not-yet-started
   Backlog item. This holds even when a mid-scan rejection (rule 8) cut short
   a full scan after some Backlog items were fully read, because an
   incomplete Backlog discovery cannot rank them.
8. **Mid-scan exhaustion.** A rate-limit rejection during a scan ends the
   scan's board reads. Evidence from the rejection overrides the outcome of
   the pre-scan budget check. An item that was not fully read is never
   proposed and never listed under actionable resume. A board read that
   fails for any reason other than rate limiting keeps today's error
   handling; this spec does not change it.
9. **Unreadable budget.** When the before-scan budget reading fails, the scan
   still runs at full coverage, because rule 1 keeps it cheap. It shows the
   warning **GraphQL budget could not be read**, and points spent reads
   **Unavailable**. Points remaining and the reset time come from the
   after-scan reading, and read **Unavailable** when that reading also
   fails.
10. **Spend report.** Every scan summary, whatever the coverage, reports the
    GraphQL points spent during the scan, the points remaining, and the
    reset time. Points remaining and the reset time always come from the
    after-scan reading. When the after-scan reading fails, all three fields
    read **Unavailable** and the summary shows the warning **GraphQL budget
    could not be read**; the coverage already decided stands. The reserve
    bounds the scan's own projected spend only. When the scan read the board
    (coverage **Full scan** or **Partial scan (budget-limited)**), no
    rate-limit rejection occurred, and the after-scan reading shows fewer
    points remaining than the reserve, the coverage already decided stands
    and the summary shows the warning **GraphQL budget below reserve after
    scan**, which says that other consumers on the same account may have
    spent budget during the scan. A **Scan deferred (budget too low)** scan
    never shows this warning, because it read no board items and its
    reason already states that the budget is below the reserve.
11. **Spend across a reset.** If the budget resets between the before-scan
    and after-scan readings (the remaining budget went up, or the reset time
    changed), the scan does not compute a figure for points spent. That
    field reads **Unavailable (budget reset during scan)**. Points remaining
    and the reset time are still reported from the newer reading.
12. **Existing low-budget warnings are kept.** The Protocol 90 warnings after
    discovery stay in force for batch dispatch: a warning below 1,000 points
    and a pause below 200 points.
13. **Read-only boundary.** The budget check, coverage decision, and spend
    report add no tracker, branch, pull-request, or board mutation to
    `/run-work`.
14. **No automated archival.** No workflow command or script archives,
    unarchives, or deletes board items.
15. **Archival safety.** The guidance marks only `Released` and `Cancelled`
    items as safe to archive. `Merged` items are not safe to archive until
    they are `Released`. Items at any in-flight status are never safe to
    archive.
16. **Archived items stay readable.** Archiving an item does not break the
    workflow's single-item tracker reads or updates for that item. The
    implementation plan verifies this, or the guidance states the limit.

---

## Statuses / Enum Values

### Scan coverage

| Code value | Display label | Description |
| --- | --- | --- |
| `full` | Full scan | All active items, in-flight items, and Backlog discovery were read. |
| `partial` | Partial scan (budget-limited) | Only in-flight items were read, or the read stopped partway. Backlog discovery, or the named items, were not covered. |
| `deferred` | Scan deferred (budget too low) | No board item was fully read: either the pre-scan check allowed no board reads, or a rate-limit rejection stopped the reads before any item was fully read. No batch is proposed. |

### Coverage reason

| Code value | Display label | Applies to coverage |
| --- | --- | --- |
| `budget_sufficient` | GraphQL budget sufficient | Full scan |
| `budget_unreadable` | GraphQL budget could not be read | Full scan (shown as a warning; set only when the before-scan reading fails) |
| `budget_below_full_scan` | GraphQL budget too low for a full scan | Partial scan |
| `budget_below_any_scan` | GraphQL budget too low to scan | Scan deferred |
| `rate_limited_during_scan` | GraphQL budget ran out during the scan | Partial scan or Scan deferred |

### Spend report fields

| Field | Display label | Value when not computable |
| --- | --- | --- |
| Points spent | GraphQL points spent by this scan | Unavailable, or Unavailable (budget reset during scan) |
| Points remaining | GraphQL points remaining | Unavailable |
| Reset time | GraphQL budget resets at | Unavailable |

**Valid transitions**: Coverage is decided once per scan invocation, and can
only narrow after that:

- `full` → `partial` when a rate-limit rejection occurs after at least one
  item was fully read.
- `full` → `deferred` when a rate-limit rejection occurs before any item was
  fully read.
- `partial` → `deferred` when a rate-limit rejection occurs before any item
  was fully read.
- `partial` stays `partial` when a rate-limit rejection occurs after at
  least one item was fully read. The reason changes to
  `rate_limited_during_scan`.
- Coverage never widens within an invocation.

---

## Operational Visibility

- **Scan summary**: shows the scan coverage label, the coverage reason, and
  the three spend report fields on every no-target scan.
- **Warnings**: **GraphQL budget could not be read** appears on the scan
  summary whenever the before-scan or after-scan budget reading fails.
  **GraphQL budget below reserve after scan** appears on a Full or Partial
  scan when the after-scan reading is below the reserve without a
  rate-limit rejection (rule 10). It is a warning, not a coverage reason.
  The existing Protocol 90 warnings for low budget after discovery are
  unchanged.
- **Audit trail**: none added. `/run-work` stays read-only and posts no
  comments.

---

## Acceptance Criteria

### Scan then execute in one quota window

- [ ] **AC1** — On this repository's board with 500 or more items, most of
  them terminal, and with no other consumer spending budget during the scan
  (so no rate-limit rejection occurs), a no-target `/run-work` scan that
  uses the default reserve (1,000 points) and starts in a quota window with
  at least 4,500 points remaining finishes with coverage **Full scan**,
  reports spending no more than 1,000 GraphQL points, and reports points
  remaining of at least the reserve. Other consumers' spending and mid-scan
  rejections are covered by rules 8 and 10, AC8, and AC12.
- [ ] **AC2** — Right after AC1's scan, in the same quota window, running the
  recommended `/run-items` command (or `/run-items` with two of the proposed
  items when the proposal is larger) resolves every target, passes its
  pre-mutation checks, and starts its first item without a rate-limit stop or
  a **Tracker unavailable** routing result. When the proposal holds a single
  item, `/run-item` on that item is used instead. The board state for this
  check must yield at least one proposed item.
- [ ] **AC3** — In a test environment with a simulated board, raising the
  number of terminal items from 50 to 1,000 with the same active and
  in-flight items does not raise the number of board read requests a
  no-target scan makes.

### Bounded commands resolve targets without a full-board read

- [ ] **AC4** — In a test environment with a simulated board, `/run-item`,
  `/run-items` (two targets), and `/run-epic` (an epic with two child items)
  each resolve their targets, with the correct Status and Type, without
  reading the whole board. Raising the number of terminal items from 50 to
  1,000 does not raise the number of board read requests any of them makes.
- [ ] **AC5** — When a bounded command's target-resolution read is rejected
  for rate limiting, the router still reports **Tracker unavailable** with
  the reset time. The existing #1503 behavior and its tests stay green.

### Spend report

- [ ] **AC6** — Every no-target scan summary, at each coverage value, shows
  **GraphQL points spent by this scan**, **GraphQL points remaining**, and
  **GraphQL budget resets at**. Each shows a numeric or time value when both
  budget readings succeed and the budget did not reset during the scan; the
  other cases are covered by AC7 and AC8.
- [ ] **AC7** — In a test environment where every budget reading fails, the
  scan finishes with coverage **Full scan**, shows the warning **GraphQL
  budget could not be read**, and reports all three spend fields as
  **Unavailable**. Where only the before-scan reading fails, points spent
  reads **Unavailable** and points remaining and the reset time come from
  the after-scan reading. Where only the after-scan reading fails, the
  coverage chosen from the before-scan reading stands, the warning is shown,
  and all three spend fields read **Unavailable**. In each case the board
  reads meet no rate-limit rejection; when one occurs, the mid-scan override
  (rule 8, AC12) sets the coverage instead.
- [ ] **AC8** — In a test environment where the simulated budget resets
  between the before-scan and after-scan readings, points spent reads
  **Unavailable (budget reset during scan)**. Points remaining and the reset
  time come from the newer reading. In a test environment where simulated
  spending by another consumer leaves the after-scan points remaining below
  the reserve with no rate-limit rejection, the coverage chosen before the
  scan stands and the summary shows the warning **GraphQL budget below
  reserve after scan**. A scan with coverage **Scan deferred (budget too
  low)** never shows that warning.
- [ ] **AC9** — In a test environment where the general (REST) API budget
  shows points left and the GraphQL budget does not, the scan's budget check
  uses the GraphQL budget and picks its coverage from it.

### Graceful degradation with a named reason

- [ ] **AC10** — In a test environment where the remaining GraphQL budget is
  below the projected full-scan cost plus the reserve, but at or above the
  projected partial-scan cost plus the reserve, the scan finishes with
  coverage **Partial scan (budget-limited)** and reason **GraphQL budget too
  low for a full scan**. It proposes no not-yet-started Backlog item, and it
  states that Backlog discovery was skipped.
- [ ] **AC11** — In a test environment where the remaining GraphQL budget is
  below the projected partial-scan cost plus the reserve, the scan reads no
  board items, finishes with coverage **Scan deferred (budget too low)** and
  reason **GraphQL budget too low to scan**, proposes no batch, and shows the
  reset time.
- [ ] **AC12** — In a test environment where a simulated rate-limit
  rejection occurs partway through a scan, the scan stops its board reads and
  reports reason **GraphQL budget ran out during the scan**. It reports
  coverage **Partial scan (budget-limited)** when at least one item was fully
  read, and **Scan deferred (budget too low)** otherwise. No item that was
  not fully read appears under the proposed batch or actionable resume, and
  no not-yet-started Backlog item is proposed even when it was fully read.
- [ ] **AC13** — In AC10, AC11, AC12, and AC17, the scan performs no
  tracker, branch, pull-request, or board mutation.
- [ ] **AC17** — In a test environment with a simulated board, the default
  reserve (1,000 points), and no other consumer spending budget, projection
  work stays within the budget above the reserve:
  - With 900 points remaining before the scan, the scan makes no projection
    read and no board read. It finishes with coverage **Scan deferred
    (budget too low)** and reason **GraphQL budget too low to scan**, and
    the after-scan reading shows the same 900 points remaining.
  - With points remaining at or above the reserve but below the projection
    ceiling plus the reserve, the scan makes no projection read and no board
    read, and finishes with the same coverage and reason.
  - Where working out a projection would need more than the projection
    ceiling, the scan stops projection work once it has spent the ceiling.
    It then uses a conservative upper bound or defers, and never spends more
    than the ceiling on projection work.
  - For every starting budget at or above the reserve, at every coverage
    value, the after-scan reading shows at least the reserve remaining.

### Archival guidance

- [ ] **AC14** — Protocol 90 has a terminal-item archival subsection
  directly beside its Step 1a GitHub Projects rate-limit section. The
  subsection:
  - names `Released` and `Cancelled` as safe to archive;
  - says `Merged` is not safe to archive until it becomes `Released`, and
    that in-flight statuses are never safe to archive;
  - tells the operator to reconcile non-canonical statuses (such as a
    legacy `Done`) before archiving;
  - describes manual archival and the board's built-in auto-archive option;
  - explains how to restore an item whose issue is reopened.
- [ ] **AC15** — The GitHub Projects integration guide's performance note
  points to that subsection. Neither document still says a full-board fetch
  is unavoidable for portfolio discovery, and neither still describes the
  cost as a "~3.5-minute pause" (with or without "hard").
- [ ] **AC16** — An archived `Released` item can still be read by the
  workflow's single-item tracker status read. Alternatively, the guidance
  states the exact limit the implementation plan found.

---

## Out of Scope (MVP)

- Reusing a scan's board snapshot in a later bounded command (fix 1). See
  Deferral Notes.
- Automated archival, unarchival, or deletion of board items by any workflow
  command or script (rule 14).
- Budget checks before or during bounded commands beyond today's behavior. A
  `/run-items` run that runs out of budget mid-pipeline is still governed by
  existing guardrails.
- Making the merge gate (Gate 5) and other mid-pipeline GraphQL consumers
  budget-aware. This comes from the PR #1857 retro comment.
- Making the full-board reads used by release preparation, release cleanup,
  and retrospective "open framework items" lookups cheaper. Those reads are
  not part of the scan-then-execute session. They still benefit from
  archival.
- Changing how the `/run-work` router classifies probe failures. That was
  delivered by #1503 and is kept as is.
- The Linear provider. Its Step 1a discovery path does not use GitHub
  Projects pagination.

---

## Open Questions

None. Both questions raised in review were answered by the human and are
recorded here:

1. **AC1 thresholds: resolved.** Keep the targets as written: at most 1,000
   points per scan (20% of the hourly budget) on a 500-plus item board, and a
   1,000-point reserve. A reserve that scales with the batch size is not
   adopted. Revisit only if a scan followed by `/run-items` still hits the
   rate limit.
2. **Reserve configurability: resolved.** Operators can configure the reserve
   through one optional key in `.ai-dev-workflow.yaml` (rule 6).

---

## Brief Objective List

Taken from issue #1505's acceptance criteria, its proposed fixes, and its
comments:

1. O1 — A `/run-work` scan followed by `/run-items` completes within one
   quota window on a 500-plus item board.
2. O2 — Bounded commands do not require a full-board fetch to resolve their
   targets.
3. O3 — The scan reports GraphQL points consumed and remaining.
4. O4 — When the remaining budget is too low for a full scan, the command
   degrades gracefully with a named reason instead of exhausting the budget.
5. O5 — Guidance for terminal-item archival is documented beside the Step 1a
   rate-limit section.
6. O6 — Proposed fix 1: cache the board snapshot for reuse by a later
   `/run-items`.
7. O7 — Proposed fix 2: per-item reads for bounded target lists.
8. O8 — Proposed fix 3: archive terminal board items.
9. O9 — Proposed fix 4: budget-aware scanning with a pre-check.
10. O10 — Proposed fix 5: report the spend in the scan summary.
11. O11 — Comment (PR #1857 retro): budget pre-checks read the GraphQL
    budget, not the general API budget, which showed stale points.
12. O12 — Comment (PR #1857 retro): the merge gate is also a GraphQL
    consumer that exhausted the budget.
13. O13 — Related: the router's misclassification of quota exhaustion as
    **Ambiguous**.

---

## Coverage Matrix

| Objective | Covered by | Notes |
| --- | --- | --- |
| O1 | AC1, AC2, AC3 | Scope of "completes" set by D3. |
| O2 | AC4, AC5 | Business rule 2. |
| O3 | AC6, AC7, AC8 | Business rules 9, 10, and 11. |
| O4 | AC9, AC10, AC11, AC12, AC13, AC17 | Business rules 3, 4, 5, 7, 8. AC17 covers the projection ceiling and gate (rule 5). |
| O5 | AC14, AC15, AC16 | Business rules 15 and 16. |
| O6 | Out of Scope (snapshot reuse) | Deferral Note DN1. |
| O7 | AC4 | Combined with O2. |
| O8 | AC14, AC15, AC16; Out of Scope (automated archival) | Documentation only (D4); Deferral Note DN2. |
| O9 | AC9, AC10, AC11, AC12, AC17 | Combined with O4. |
| O10 | AC6, AC7, AC8 | Combined with O3. |
| O11 | AC9 | Business rule 3; D5. |
| O12 | Out of Scope (merge gate budget awareness) | Deferral Note DN3. |
| O13 | AC5; Out of Scope (router classification) | Delivered by #1503; regression-guarded only. |

## Deferral Notes

- **DN1 — Snapshot reuse (O6).** Deferred. A mutating bounded command should
  decide from current tracker state, not from a snapshot taken earlier.
  Rules 1 and 2 make both the scan and the target resolution cheap enough
  that a cache is not needed to meet O1. Human confirmed: stays deferred.
- **DN2 — Automated archival (O8, automation part).** Deferred. Archiving
  changes a live, shared board, and the safe set depends on release
  closeout timing. The guidance (AC14) delivers the hygiene part of the
  objective. Human confirmation requested: no; the issue presents archival
  as operational hygiene.
- **DN3 — Merge gate budget awareness (O12).** Deferred to a separate item.
  The merge gate runs mid-pipeline, not in the scan-then-execute discovery
  phase this issue targets. The objective's transferable lesson, reading the
  GraphQL budget specifically, is adopted for the scan (AC9). Human
  confirmed: filed as follow-up backlog item #1890.

---

## Complex Workflow Decision-Gate Matrix

This spec adds a scan-coverage gate to the no-target `/run-work` scan.

### Gate inputs

- **R**: the remaining GraphQL budget, read immediately before the scan. It
  can be unreadable.
- **C_full**: the projected cost of a full scan.
- **C_partial**: the projected cost of a partial scan. Always
  C_partial ≤ C_full (rule 5).
- **S**: the reserve (default 1,000).
- **P**: the projection ceiling, the most the scan may spend working out
  C_full and C_partial (rule 5). It is known before any projection read.
- **Mid-scan evidence**: a rate-limit rejection observed during the scan
  (yes or no), and whether at least one item was fully read before it.

### Pre-scan decision

Rows are checked in order, and the first match wins.

| # | Condition | Coverage | Reason | Required next action |
| --- | --- | --- | --- | --- |
| 1 | R unreadable (the before-scan reading fails) | Full scan | GraphQL budget could not be read (warning) | Run the full scan. Report points spent as Unavailable. Take points remaining and the reset time from the after-scan reading (rule 9). |
| 2 | R < P + S (checked before any projection read) | Scan deferred (budget too low) | GraphQL budget too low to scan | Do no projection work. Read no board items. Propose no batch. Report the remaining budget and reset time. |
| 3 | R ≥ C_full + S | Full scan | GraphQL budget sufficient | Run the full scan. Report the spend. |
| 4 | C_partial + S ≤ R < C_full + S | Partial scan (budget-limited) | GraphQL budget too low for a full scan | Read in-flight items only. Skip Backlog discovery. Report the spend and what was skipped. |
| 5 | R < C_partial + S | Scan deferred (budget too low) | GraphQL budget too low to scan | Read no board items. Propose no batch. Report the remaining budget and reset time. |

Row 2 is evaluated before the projections are worked out, so projection
work only starts when R ≥ P + S, and it never spends more than P (rule 5).
Rows 3 to 5 are evaluated after the projections. Each projection includes
its share of the projection spend, and a projection that cannot be worked
out within P is replaced by a conservative upper bound, or treated as
exceeding R when no bound can be derived (rule 5), so rows 3 to 5 always
have inputs once R is readable. Because C_partial ≤ C_full (rule 5), rows 3
to 5 split the readable values of R ≥ P + S into ranges that do not overlap
and leave no gaps. When the two projections are equal, row 4's range is
empty. With no other consumer spending, every row from 2 to 5 leaves at
least S points remaining after the scan when R ≥ S before it.

### Mid-scan override

Mid-scan evidence takes precedence over the pre-scan decision.

| # | Mid-scan evidence | Coverage | Reason | Required next action |
| --- | --- | --- | --- | --- |
| 6 | Rate-limit rejection, at least one item fully read | Partial scan (budget-limited) | GraphQL budget ran out during the scan | Stop board reads. Propose only from fully read items, and never a not-yet-started Backlog item (rule 7). List what was not covered. Report the reset time. |
| 7 | Rate-limit rejection, no item fully read (including a rejection during projection work) | Scan deferred (budget too low) | GraphQL budget ran out during the scan | Stop projection work and board reads. Propose no batch. Report the reset time. |
| 8 | No rate-limit rejection | Pre-scan decision stands | Pre-scan reason stands | As in the pre-scan row. If the coverage is Full scan or Partial scan and the after-scan reading is below the reserve, also show the warning **GraphQL budget below reserve after scan** (rule 10). Scan deferred never shows it. |

Only a rate-limit rejection triggers rows 6 and 7. A board read that fails
for any other reason keeps today's error handling (rule 8). A failed
after-scan budget reading never changes the coverage; it only affects the
spend report (rule 10).

### Outcome classes

Every row ends in one of three terminal outcomes for the read-only scan
invocation:

- a proposal (Full scan);
- a narrowed proposal (Partial scan);
- no proposal with a retry time (Scan deferred).

None of the rows waits or escalates. `/run-work` is read-only, so the
operator's next command is always named.

### Examples

The examples use an illustrative P = 50; the implementation plan sets the
real value.

- Fresh window, R = 4,980, C_full = 600, S = 1,000 → 4,980 ≥ 1,050, so the
  projections run; then row 3, Full scan.
- R = 1,400, C_full = 600, C_partial = 150 → 1,400 ≥ 1,050, so the
  projections run; then 1,400 < 1,600 and 1,400 ≥ 1,150 → row 4, Partial
  scan.
- R = 900, S = 1,000 → 900 < 1,050 → row 2, Scan deferred. No projection
  work runs, so the scan spends none of the 900 points on board or
  projection reads.
- R = 1,030, S = 1,000 → 1,030 < 1,050 → row 2, Scan deferred, even though
  R is above the reserve, because projection work could take up to 50
  points and leave less than the reserve.
- R = 1,100, S = 1,000, C_partial = 150 → the projections run (at most 50
  points), then 1,100 < 1,150 → row 5, Scan deferred. At least 1,050 points
  remain, above the reserve.
- Row 3 chosen, but a concurrent consumer drains the budget after 10 items
  were fully read → row 6, Partial scan, reason "GraphQL budget ran out
  during the scan".
- R = 2,000, C_full = 600, S = 1,000 → row 3, Full scan. Another consumer
  spends 500 during the scan with no rejection, leaving 900 → row 8, Full
  scan stands, with the warning **GraphQL budget below reserve after scan**.

### Mirror surfaces

The implementation plan confirms the exact edits.

- Protocol 90 Step 1a rate-limit section, plus the new archival subsection
  (normative).
- The GitHub Projects integration guide's performance note.
- The `/run-work` command and skill surfaces for each runner: Claude Code
  command, Cursor command, the shared agents skill, and the Codex
  orchestrator skill. These change only where they describe what the scan
  summary contains.
- Protocol 96 `no_target_scan` row. This is not applicable unless that row
  describes the scan summary's contents. Router modes are unchanged.

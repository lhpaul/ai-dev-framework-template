# A reviewer that has not answered yet is not a failed reviewer — Spec

## Overview

The automated reviewer loop waits a bounded time for each configured review
platform to return a verdict on the pull request's current revision. Today,
when that wait runs out before a platform answers, the loop records a timeout
escalation and applies the `reviewer-failed` label. On PR #1787 this happened
to Bugbot on a pull request that Bugbot then reviewed clean on the same
revision, once it was given more time. The escalation looked the same as a
real reviewer failure, stopped an unattended run, and left a label a human had
to remove by hand.

This feature separates **"the reviewer has not answered yet"** from **"the
reviewer failed"** for every supported review platform, not only Bugbot. It
matches each platform's default wait to that platform's own response time. It
keeps the `reviewer-failed` label in step with the latest outcome for the
current revision. It records how long each platform took, so the defaults can
be tuned from data. Workflow operators and unattended item runners
(`/run-item`, `/run-items`, `/run-epic`) get outcomes they can act on without
checking whether a failure is real.

---

## Use Cases

### Use Case 1: Reviewer answers after the old default wait would have expired

**Actor**: Workflow operator or unattended item runner
**Preconditions**: A pull request is at the ready-phase review stage. A review
platform is configured. That platform normally answers later than the loop's
previous one-size-fits-all wait, including on documentation (`spec/*` and
`implementation-plan/*`) branches.

**Steps**:

1. The loop requests or awaits a review from the platform for the current
   revision.
2. The loop waits up to that platform's own wait budget.
3. The platform returns a verdict within that budget.

**Postconditions**: The loop records the platform's verdict (clean or
findings) and continues as it does today for that verdict. No timeout, no
escalation, and no `reviewer-failed` label result from the platform's normal
response time.

**Information shown**:

- The platform's outcome for the current revision.
- How long the platform took from the review request (or the start of the
  wait, for platforms that review without a request) to its verdict.

**Actions available**:

- Continue to the next readiness gate on a clean verdict, or to the fix loop
  on findings.

**Considerations**:

- A shortened wait intended for a platform that never reviews documentation
  branches must not shorten the wait of a platform that does review them.

---

### Use Case 2: Reviewer has not answered when its wait budget runs out

**Actor**: Workflow operator or unattended item runner
**Preconditions**: A review was requested (or awaited) for the current
revision. The platform's wait budget ran out. The platform has returned no
verdict for that revision, and no failure evidence exists.

**Steps**:

1. The loop's wait budget for the platform runs out with no verdict.
2. The loop records the platform's outcome as **No verdict yet**.
3. The item runner automatically waits once more on the same revision, without
   posting a duplicate review request while one is still outstanding.
4. If a verdict arrives during that extra wait, the run continues as in Use
   Case 1. If not, the run stops as **Waiting on reviewer**.

**Postconditions**: The pull request does not get the `reviewer-failed` label
for this outcome. It does not get `ready-for-human-review`. No fixer is
dispatched. The stop names the platform that is still pending and is reported
as a waiting state, not as an escalation or a failure.

**Information shown**:

- The platform that has not answered, the revision it was asked to review, when
  the request (or wait) started, and how long the loop waited in total.
- A clear statement that no failure was detected.

**Actions available**:

- Re-run the reviewer loop later on the same revision. It picks up a verdict
  that has since arrived.
- Look into the platform if it still has not answered after repeated waits.

**Considerations**:

- A verdict that covers an older revision does not count as an answer for the
  current revision.
- If the pull request's revision changes during the wait, the existing
  head-moved handling applies instead.

---

### Use Case 3: Reviewer genuinely fails

**Actor**: Workflow operator or unattended item runner
**Preconditions**: A review platform returns positive evidence that it could
not review the current revision.

**Steps**:

1. The loop detects failure evidence from the platform.
2. The loop records the platform's outcome as **Reviewer failed** and
   escalates.

**Postconditions**: The `reviewer-failed` label is applied and the run stops
for a human, as today.

**Information shown**:

- The platform and the failure evidence that was observed.

**Actions available**:

- Fix the underlying platform problem and re-run the loop.

**Considerations**:

- A platform outcome that already has its own shipped handling keeps it. This
  covers usage-limit, spend-limit, account-not-connected, and rate-limit
  outcomes. This feature does not reclassify them.

---

### Use Case 4: A later run on the same revision comes back clean

**Actor**: Workflow operator or unattended item runner
**Preconditions**: An earlier loop run on the pull request left the
`reviewer-failed` label. A later run on the same revision finishes with a
clean verdict from every configured platform.

**Steps**:

1. The later run finishes clean.
2. The loop updates the label to match the latest outcome.

**Postconditions**: The `reviewer-failed` label is removed no matter which
path the clean run took to finish.

**Information shown**:

- The loop summary shows the clean result for the current revision.

**Actions available**:

- Continue to the remaining readiness gates.

**Considerations**:

- A clean result is enough to remove the label, whether the loop reviewed the
  revision again or reused a verdict it had already recorded for that same
  revision.

---

### Use Case 5: Operator tunes wait budgets from recorded latency

**Actor**: Workflow maintainer
**Preconditions**: Loop runs have recorded response latency per platform.

**Steps**:

1. The maintainer reads the per-platform latency in loop summaries and run
   output.
2. The maintainer changes a platform's wait budget through the existing
   configuration surfaces when the data supports it.

**Postconditions**: Later runs use the tuned budget for that platform only.

**Information shown**:

- For each platform that ran: its outcome, the wait budget that applied and
  where that budget came from, and either the time from request to verdict or
  the time waited without a verdict.

**Actions available**:

- Configure a wait budget for a single platform (Business Rule 8).
- Set a one-run override that applies to every platform in one invocation, as
  the loop allows today.

**Considerations**:

- Platforms whose verdict was reused from an earlier run on the same revision
  are marked as reused, not as having a latency of zero.

---

## Business Rules

1. **Three outcome classes.** For each platform in a loop run, the outcome for
   the current revision is exactly one of:
   - **Verdict received**: the platform returned a clean or findings verdict
     for the current revision.
   - **Reviewer failed**: the platform returned positive evidence that it
     could not review the current revision.
   - **No verdict yet**: the platform's wait budget ran out with neither a
     verdict nor failure evidence for the current revision.

   Platforms that are skipped, not configured, or excluded keep their existing
   handling and are outside these three classes.
2. **Failure needs evidence.** Only positive evidence makes a platform
   **Reviewer failed**. Examples: a failed or errored review result, a review
   request that could not be posted, an authorization or permission refusal,
   the reviewer being unreachable, a local reviewer ending with an error or
   with output the loop cannot read, a malformed verdict, or the platform's
   own review run reporting that it timed out or failed. Running out of the
   loop's wait budget is never failure evidence on its own. A platform that
   shows no sign of having started a review for the current revision when its
   budget ends is **No verdict yet** too, unless the platform itself reports
   that it is unavailable, for example because it is not installed or not
   connected.
3. **Same rule on every platform.** Rules 1 and 2 apply the same way to every
   supported platform: `greptile`, `devin`, `coderabbit`, `coderabbit-cli`,
   `local-ai-reviewer`, `pr-agent`, `codex-github`, `claude-code-action`,
   `haystack`, `copilot`, `bugbot`, and `ronda`. This holds in both the draft
   and ready phases. For a reviewer the loop runs on the local machine, **No
   verdict yet** means the loop stopped the reviewer at the end of its budget
   while the reviewer was still working and had reported no error. The next
   run starts that review again. An existing platform-specific wait outcome
   keeps its name. Codex GitHub's review-pending and reaction-without-review
   outcomes are examples.
4. **No verdict yet is a wait, not a failure.** A **No verdict yet** outcome
   never applies `reviewer-failed`. It is never reported as an escalation. It
   never dispatches a fixer. It never allows `ready-for-human-review`. The loop
   reports it as the existing **Waiting on reviewer** result and names the
   pending platform. One exception keeps today's progression: a platform whose
   expired wait is currently treated as a non-blocking skip (for example, a
   CodeRabbit CLI review still running when its budget ends) keeps that
   non-blocking skip. Its outcome is still reported as **No verdict yet**, and
   it no longer applies `reviewer-failed`.
5. **Precedence across platforms.** When a run has more than one platform
   outcome, the run's overall result follows this order, and the first match
   wins:
   1. Any **Reviewer failed**: escalate.
   2. Any findings: needs fixes.
   3. Any **No verdict yet**: waiting on reviewer.
   4. All clean or skipped: clean.

   A **No verdict yet** outcome kept as a non-blocking skip under the
   exception in Business Rule 4 counts as skipped at step 4, not as waiting at
   step 3. Existing loop-level escalations keep their current precedence over
   all of these. Examples: ownership refusal, cycle-limit exhaustion, and a
   lost summary record.
6. **Current-revision evidence only.** A verdict or failure that covers an
   older revision counts neither as an answer nor as a failure for the current
   revision.
7. **Automatic re-wait before stopping.** When the loop reports **Waiting on
   reviewer** because of **No verdict yet**, the item runner re-runs the loop
   automatically **once** on the same revision before it stops. The allowance
   is once per revision within an item run: a new revision (for example, after
   a fixer push) gets its own single re-wait. The re-run must
   not post a duplicate review request while a request for that revision is
   still outstanding. If the re-run still reports **No verdict yet**, the runner
   stops as **Waiting on reviewer**. That stop is a waiting state with a named
   human action, never an escalation. The automatic re-wait does not count
   toward the reviewer loop's fix-cycle caps.
8. **Wait budget per platform.** Each platform has its own default wait budget,
   matched to its observed response time. The budget that applies to a
   platform is decided in this order, and the first available value wins:
   1. An explicit one-run override that the operator passes to the loop for
      that invocation. It applies to every platform in the run, as today.
   2. A wait budget configured for that platform.
   3. That platform's built-in default.

   The shortened wait for documentation branches applies only to platforms
   that do not review documentation branches. It never shortens the wait of a
   platform that does review them. The same scoping applies to the existing
   larger wait for large diffs: it may lengthen a platform's budget but never
   shorten it.
9. **Minimum defaults.** No platform's built-in default may be shorter than
   the default wait that applied to it before this feature on implementation
   branches: 20 minutes in general, and 30 minutes for Codex GitHub.
   Bugbot's built-in default must be at least **25 minutes**, which covers the
   latency observed on PR #1787 when it returned clean.
10. **Invalid budget values.** An explicit one-run override that is not a
    positive whole number of seconds is refused before any review request is
    posted, as today. A configured per-platform budget that is not a positive
    whole number of seconds is ignored with a visible warning, and the
    platform's built-in default applies.
11. **The label follows the latest outcome.** After each loop run, the
    `reviewer-failed` label is present on the pull request only when at least
    one platform in that run carries failure evidence for the current
    revision. That is a platform outcome of **Reviewer failed**, or a
    non-blocking skip whose reason is failure evidence, such as an
    unavailable, unauthorized, or forbidden platform, as today. This is judged
    per platform, so it holds even when the run's overall result is needs
    fixes or clean. The label is absent after a run in which no platform
    carries failure evidence: every platform has a verdict, **No verdict yet**,
    a non-blocking skip caused only by an expired wait, or another skip that is
    not failure evidence. This holds on every exit path that evaluates reviewers for the current
    revision. That includes a run that reuses a recorded verdict for the same
    revision instead of reviewing it again. A run refused before any reviewer
    is evaluated (for example, an ownership refusal or a concurrent-run lock)
    leaves the label unchanged, as today. A failed attempt to add or remove the label
    is reported as a warning. It does not change the run's result.
12. **Latency is recorded.** For every platform that ran, the loop summary
    comment and the loop's run output record:
    - the platform's outcome;
    - the wait budget that applied and where it came from (one-run override,
      configured value, or built-in default);
    - the time the review request was posted, or the time the loop started
      waiting for platforms that review without a request;
    - either the time from request to verdict (for **Verdict received** and
      **Reviewer failed**) or the time waited without a verdict (for **No
      verdict yet**).

    A platform whose verdict was reused from an earlier run on the same
    revision is marked as reused, with no latency value.

---

## Statuses / Enum Values

No tracker statuses change. The operator-visible reviewer-loop outcomes this
feature affects are:

| Code value | Display label | Description |
| --- | --- | --- |
| `waiting_on_reviewer` | Waiting on reviewer | Existing loop result, now used by every platform. At least one platform has **No verdict yet** (or an existing platform-specific wait outcome) and no platform has failed or reported findings |
| `reviewer-no-verdict-yet` | No verdict yet | New platform-neutral reason. The platform's wait budget ran out with no verdict and no failure evidence for the current revision |
| `escalate` | Escalated | Existing loop result. Used for **Reviewer failed** and for the existing loop-level escalations. It is no longer used when a platform simply ran out of wait budget |
| `reviewer-failed` | Reviewer failed (PR label) | Existing label. Present only while at least one platform in the latest run carries failure evidence (Business Rule 11) |

Codex GitHub's existing wait reasons (`codex-github-review-pending` and
`codex-github-reaction-without-review`) keep their names and meaning. They
belong to the **No verdict yet** class.

**Valid transitions** (per platform, within one revision):

- No verdict yet → Verdict received, when a later poll or re-run on the same
  revision finds the verdict.
- No verdict yet → Reviewer failed, when failure evidence for the same
  revision appears later.
- Any outcome → re-evaluated from scratch when the pull request's revision
  changes.
- Verdict received and Reviewer failed are final for a run. A later run on the
  same revision may record a new outcome, and the label follows that latest
  outcome (Business Rule 11).

---

## Operational Visibility

- **Logs**: The loop's run output names each platform's outcome class, its
  wait budget and where that budget came from, and its latency or time waited.
- **Notifications**: The existing reviewer-loop summary comment shows the
  per-platform outcome and latency. It also shows a **Waiting on reviewer**
  result with the pending platform, and makes clear that no failure was
  detected.
- **Audit trail**: The per-platform latency record in each summary is the data
  that wait-budget tuning relies on (Use Case 5).

---

## Acceptance Criteria

- [ ] AC-1: For each supported platform, a simulated run where the wait budget
      runs out with no verdict and no failure evidence reports **Waiting on
      reviewer** with the pending platform named. It does not apply
      `reviewer-failed`, does not report an escalation, and does not dispatch a
      fixer. This covers `local-ai-reviewer`, which is the configured
      ready-phase reviewer, and `bugbot`.
- [ ] AC-2: For each supported platform, a simulated run with positive failure
      evidence reports **Reviewer failed**, escalates, and applies
      `reviewer-failed`, as it does today.
- [ ] AC-3: Reproducing PR #1787 on an `implementation-plan/*` branch: a Bugbot
      review that answers clean 25 minutes or less after the request, with no
      explicit one-run override, is recorded as a clean verdict. It is not a
      timeout.
- [ ] AC-4: A platform that does not review documentation branches still gets
      the shortened documentation-branch wait. A platform that does review
      them keeps its own default budget on those branches.
- [ ] AC-5: The applied wait budget follows Business Rule 8's order: an
      explicit one-run override first, then a configured per-platform value,
      then the built-in default. An invalid configured value falls back to the
      default with a warning. An invalid one-run override is refused before any
      review request is posted.
- [ ] AC-6: No platform's built-in default is shorter than the default wait
      that applied to it on implementation branches before this feature (20
      minutes in general, 30 minutes for Codex GitHub), and Bugbot's default
      is at least 25 minutes.
- [ ] AC-7: A pull request carrying `reviewer-failed` from an earlier run has
      the label removed after a later clean run on the same revision. This is
      verified both when the later run reviews the revision again and when it
      reuses a verdict it had already recorded for that revision.
- [ ] AC-8: The label is absent after a run whose overall result is needs
      fixes or waiting on reviewer when no platform carries failure evidence,
      and after a non-blocking skip caused only by an expired wait. It is
      present after a run in which any platform is **Reviewer failed** or has
      a non-blocking skip whose reason is failure evidence, including a mixed
      run whose overall result is needs fixes or clean. A platform whose expired wait is treated today as a
      non-blocking skip (a CodeRabbit CLI review still running) keeps that non-blocking
      progression, is reported as **No verdict yet**, and does not apply
      `reviewer-failed`.
- [ ] AC-9: With several platforms configured, the overall result follows
      Business Rule 5's order. Examples: one platform failed while another has
      no verdict yet gives an escalation; findings on one platform while
      another has no verdict yet gives needs fixes; no verdict yet on one
      platform while the others are clean gives waiting on reviewer.
- [ ] AC-10: A verdict that covers an older revision is not accepted as the
      current revision's answer. The platform stays in **No verdict yet**
      until a current-revision verdict or failure appears.
- [ ] AC-11: When the loop reports **Waiting on reviewer** because of **No
      verdict yet**, the item runner re-runs the loop once on the same
      revision without posting a duplicate review request. It continues if a
      verdict arrives. Otherwise it stops as **Waiting on reviewer**, which is
      not an escalation. The re-wait happens at most once per revision and
      does not count toward fix-cycle caps.
- [ ] AC-12: The loop summary comment and run output record, for every
      platform that ran, the outcome, the applied wait budget and its source,
      the request (or wait-start) time, and either the request-to-verdict
      latency or the time waited without a verdict. Reused verdicts are marked
      as reused.
- [ ] AC-13: Usage-limit, spend-limit, account-not-connected, and rate-limit
      outcomes keep their current results, reasons, and label behavior.
- [ ] AC-14: The workflow documentation that describes reviewer-loop results
      and the `reviewer-failed` label states the three outcome classes, the
      precedence, the automatic re-wait, and the label rule. This covers the
      reviewer-loop protocol, the item-runner protocol, and the per-platform
      integration guides that describe wait behavior.

---

## Out of Scope (MVP)

- Changing how fast any vendor reviews, or which platforms a repository
  configures.
- Changing the shipped handling of usage-limit, spend-limit,
  account-not-connected, or rate-limit outcomes.
- Changing the internal review gate (Step 7a) or its reviewers.
- Changing the reviewer loop's fix-cycle caps or the settle and quiet-period
  rules that come after a clean verdict.
- Automatically retuning defaults from recorded latency. This feature records
  the data. Maintainers change budgets through existing configuration.
- Removing `reviewer-failed` labels from historical pull requests that no loop
  run revisits.

---

## Brief Objective List

1. Raise the default ready-phase wait to match observed vendor latency, or make
   the default per-platform.
2. Distinguish **No verdict yet** from **Reviewer failed** in the result
   vocabulary, and do not apply `reviewer-failed` for the former.
3. Do not leave a `reviewer-failed` label behind when a later run on the same
   revision comes back clean.
4. Record trigger-to-verdict latency per platform in the loop summary.
5. Acceptance criterion: a reviewer that has not answered within the wait
   budget is reported distinctly from one that failed, and does not apply
   `reviewer-failed`.
6. Acceptance criterion: the default ready-phase wait does not time out on a
   Bugbot review that later returns clean on the same revision.
7. Acceptance criterion: a clean run clears a `reviewer-failed` label left by
   an earlier run on the same revision.
8. Acceptance criterion: the loop summary records trigger-to-verdict latency
   per platform.
9. Run constraint: the distinction and per-platform wait apply to every
   platform, not only Bugbot, because the configured ready-phase reviewer is
   `local-ai-reviewer`.

## Coverage Matrix

| Brief objective | Coverage |
| --- | --- |
| 1. Per-platform or matched default wait | AC-3, AC-4, AC-5, AC-6; Business Rules 8-10; Use Case 1 |
| 2. Distinct no-verdict-yet vocabulary, no label | AC-1, AC-2, AC-8, AC-9, AC-10, AC-11; Business Rules 1-7; Use Cases 2-3 |
| 3. No stale label after a clean run | AC-7, AC-8; Business Rule 11; Use Case 4 |
| 4. Record latency per platform | AC-12; Business Rule 12; Use Case 5 |
| 5. Reported distinctly, no label | AC-1, AC-2 |
| 6. No timeout on a Bugbot review that later returns clean | AC-3, AC-6 |
| 7. Clean run clears the label | AC-7 |
| 8. Latency in the summary | AC-12 |
| 9. Every platform, not only Bugbot | AC-1, AC-2, AC-4; Business Rule 3 |

## Deferral Notes

- No brief objective is deferred. Automatic retuning from recorded latency is
  out of scope, because the brief asks only to record the data "so the default
  can be tuned". No human confirmation is requested for this deferral.

## Complex Workflow Decision-Gate Matrix

This spec changes a workflow decision gate: how the reviewer loop and the item
runner act when a platform's wait budget runs out. Row order is presentational.
Business Rule 5 sets the precedence between rows when several platforms
contribute outcomes, and existing loop-level escalations stay above all rows.
For a single platform, the non-blocking-skip row wins over the general
no-verdict rows for the platforms it covers. The usage-limit and similar
availability row wins over every other row for the platform whose outcome it
describes.

| Gate input | Allowed outcome | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- |
| Platform returns a clean verdict for the current revision within its budget | Verdict received (clean) | Continue to the next platform or readiness gate. Record the latency. Remove any `reviewer-failed` label if no platform in the run carries failure evidence (Business Rule 11) | Reviewer loop, Protocol 93, Protocol 91 Step 7, loop summary | Bugbot answers clean 20 minutes after the request on a plan branch |
| Platform returns findings for the current revision within its budget | Verdict received (findings) | Needs fixes. Dispatch the fixer through the existing fix loop. Record the latency. No `reviewer-failed` label | Reviewer loop, Protocol 93, Protocol 91 Step 7 | `local-ai-reviewer` reports a blocking finding |
| Platform returns positive failure evidence for the current revision | Reviewer failed | Escalate. Apply `reviewer-failed`. Stop for a human | Reviewer loop, Protocol 93, Protocol 91 Step 7, `reviewer-failed` label | The review request cannot be posted, or a local reviewer exits with an error |
| Platform's wait budget runs out with no verdict and no failure evidence for the current revision (first occurrence for this revision in this item run) | No verdict yet, loop result Waiting on reviewer | The item runner re-runs the loop once on the same revision, with no duplicate request. No label, no fixer, no readiness | Reviewer loop, Protocol 91 Step 7, Protocol 93, integration guides | Bugbot has not answered 25 minutes after the request |
| Wait runs out for a platform whose expired wait is treated today as a non-blocking skip | No verdict yet, non-blocking skip kept | Continue as today. Report **No verdict yet** and do not apply `reviewer-failed` | Reviewer loop, CodeRabbit CLI integration guide | A CodeRabbit CLI review still running when its budget ends |
| No verdict yet again after the automatic re-wait | Waiting on reviewer (stop) | Stop the run as a waiting state that names the pending platform and the human action (re-run later or investigate the platform). Not an escalation | Protocol 91 Step 7 and Work Item Runner summary, Protocol 93, reviewer-loop completion guard and readiness helpers (which already treat a non-clean result as not ready) | The platform is down with no error reported |
| Only evidence for the platform covers an older revision | No verdict yet | Same as the no-verdict rows above. Never counted as clean or failed for the current revision | Reviewer loop, Protocol 93 | A clean verdict from before the last push |
| Platform shows no sign of having started a review when its budget ends and reports no unavailability | No verdict yet | Same as the no-verdict rows above | Reviewer loop, Bugbot integration guide | No Bugbot check run has appeared yet for the current revision |
| Platform's own review run reports that it timed out or failed | Reviewer failed | Escalate and apply `reviewer-failed` | Reviewer loop, Bugbot integration guide | Bugbot's check run concludes as timed out |
| Pull request revision changes during the wait | Existing head-moved handling | Re-run for the new revision, as today | Reviewer loop, Protocol 91 Step 7 | A fixer push lands while Bugbot is pending |
| Platform returns a usage-limit, spend-limit, account-not-connected, or rate-limit outcome | Existing shipped handling, unchanged | Existing next action and label behavior, unchanged | Reviewer loop, integration guides | Bugbot posts a spend-limit notice |
| Several platforms contribute outcomes in one run | First match in Business Rule 5's order | Act on the overall result per its own row | Reviewer loop, Protocol 93 | One platform clean and one with no verdict yet gives waiting on reviewer |
| Configured per-platform budget is missing | Built-in default applies | Continue | Reviewer loop, `.ai-dev-workflow.yaml` comments, integration guides | No per-platform value is configured for Bugbot |
| Configured per-platform budget is invalid (not a positive whole number of seconds) | Built-in default applies, with a warning | Continue and show the warning in run output | Reviewer loop, integration guides | A configured wait of `abc` |
| Explicit one-run override is invalid | Refused before any review request is posted | Operator corrects the invocation, as today | Reviewer loop usage text | `--max-wait 0` |
| A later run on the same revision is clean, with no platform carrying failure evidence, while `reviewer-failed` is present | Clean, label removed | Continue to readiness gates | Reviewer loop, Protocol 91 Step 8a | Run 2 on PR #1787 |

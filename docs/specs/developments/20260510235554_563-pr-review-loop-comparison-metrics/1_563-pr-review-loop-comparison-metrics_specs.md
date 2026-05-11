# PR Review Loop Comparison Mode and Platform Metrics Tracking — Spec

**Depends on**: structured-retro-metrics

---

## Overview

The automated reviewer loop currently runs platforms sequentially and stops as soon as one platform returns a blocking verdict. This short-circuit behavior prevents any measurement of whether different platforms catch different issues — making it impossible to evaluate platform value, reduce false positives, or build a data-driven case for dropping or replacing a platform.

This feature adds a `--compare` flag to the reviewer loop that runs all configured platforms to completion regardless of individual verdicts, records per-platform results, and appends a structured row to a platform metrics log after each run. A set of pre-agreed graduation criteria (documented in the metrics file) defines the conditions under which a platform can be safely removed.

---

## Use Cases

### Use Case 1: Run the Reviewer Loop in Compare Mode

**Actor**: Orchestrator agent (or human operator) running the automated reviewer loop for a PR
**Preconditions**: The reviewer loop is configured with two or more review platforms. The `--compare` flag is passed on invocation.

**Steps**:
1. The operator invokes the reviewer loop with the `--compare` flag for a specific PR number.
2. The loop runs every configured platform to completion, regardless of whether an earlier platform returned a blocking verdict.
3. After all platforms have run, the loop determines the overall exit result: the first platform that would have caused a block under normal (non-compare) mode governs the overall exit code.
4. For each platform, the per-platform verdict (clean, blocking, advisory, timed out) is recorded in the loop output alongside the overall result.
5. The loop appends one structured row to the platform comparison metrics log, capturing the PR number, branch type, and each platform's verdict for this run.
6. The loop exits with the same overall result it would have produced in normal mode.

**Postconditions**: All platforms have run. A new row exists in the metrics log. The exit code reflects the result that normal mode would have produced.

**Information shown**:
- Per-platform verdict for each platform that ran (clean / blocking / advisory / timed out)
- Overall result (same semantics as normal mode)
- Confirmation that a metrics row was appended

**Actions available**:
- Proceed with fixes if the overall result is blocking (same as normal mode)
- Review the metrics log to see the accumulated per-platform history

**Considerations**:
- If a platform times out in compare mode, its verdict is recorded as "timed out" in the metrics log; the run continues with remaining platforms.
- If a platform's configuration is missing or the platform is unavailable, its verdict is recorded as "unavailable" and the run continues.
- The overall exit code in compare mode is identical to what normal mode would produce: the first blocking platform (in configuration order) wins. Compare mode does not change whether the PR needs fixes.

---

### Use Case 2: View Accumulated Platform Comparison Metrics

**Actor**: Retrospective Analyst (agent or human) reviewing platform performance over time
**Preconditions**: At least one reviewer loop run in compare mode has completed, producing at least one row in the metrics log.

**Steps**:
1. The analyst reads the platform comparison metrics log.
2. The log shows one row per compare-mode run, with columns for PR number, branch type, and each platform's verdict.
3. The analyst identifies runs where one platform blocked but another was clean (platform-exclusive blocks).
4. The analyst assesses whether platform-exclusive blocks resulted in actual code fixes or were resolved without any code change.
5. The analyst uses this data to evaluate platform value against the graduation criteria documented in the log header.

**Postconditions**: The analyst has a structured dataset to support a data-driven platform evaluation decision.

**Information shown**:
- One row per compare-mode run: PR number, branch type, per-platform verdicts, whether a platform-exclusive block resulted in a code fix
- Log header documenting the graduation criteria for safely removing a platform

**Actions available**:
- Update the "block was a real bug" field for a past row if a fix was later determined to be real (manual update by the analyst)
- Use the accumulated data in a meta-retrospective platform evaluation step

**Considerations**:
- The "block was a real bug" field cannot be filled automatically at run time — it requires post-hoc human or analyst judgment about whether a fix was genuinely necessary. The field defaults to blank and must be filled in manually.
- The metrics log is append-only. Rows must not be deleted or edited except to fill in the "block was a real bug" field.

---

### Use Case 3: Meta-Retrospective Platform Evaluation Step

**Actor**: Retrospective Analyst running a meta-retrospective
**Preconditions**: The meta-retrospective protocol includes a platform evaluation step. The platform comparison metrics log has at least one row.

**Steps**:
1. During the meta-retrospective, the analyst reads the platform comparison metrics log.
2. The analyst computes the running rate of platform-exclusive blocking findings (cases where one platform blocked but at least one other did not) across all logged runs.
3. The analyst compares this rate against the graduation criteria documented in the log header.
4. The analyst reports whether any platform meets the graduation threshold for removal.
5. The human reviews the finding and decides whether to initiate a platform removal or continue collecting data.

**Postconditions**: The meta-retrospective output includes a platform evaluation section with the computed rate and a recommendation.

**Information shown**:
- Total runs logged in compare mode
- Per-platform exclusive-block count and rate
- Whether any platform meets the graduation criteria
- Recommendation (continue collecting / safe to evaluate removal / data insufficient)

**Actions available**:
- Accept the recommendation as-is
- Request additional data collection before deciding
- Initiate a backlog item to remove a platform

**Considerations**:
- The graduation criteria are documented in the log header and are not evaluated automatically — the analyst reads them and applies them to the data.
- Fewer than 30 runs is always insufficient data; the analyst must explicitly flag this if the log has fewer than 30 rows.

---

## Business Rules

- **BR-1: Compare mode does not change the overall exit code.** The exit code and overall result in compare mode are identical to what normal mode would produce. The first platform that would have blocked in normal mode still governs the overall result.
- **BR-2: All platforms run to completion in compare mode.** No platform is skipped or short-circuited based on another platform's verdict.
- **BR-3: A metrics row is appended after every compare-mode run.** Each invocation with `--compare` appends exactly one row to the platform comparison metrics log, regardless of the overall result.
- **BR-4: Normal (non-compare) mode is unaffected.** Invocations without `--compare` behave identically to today's behavior: sequential platforms, short-circuit on first block.
- **BR-5: The metrics log is append-only.** Existing rows must not be deleted or rewritten by the reviewer loop. The "block was a real bug" field is the only field that may be manually updated by an analyst after the fact.
- **BR-6: The log header documents the graduation criteria.** The criteria are fixed at the time this feature ships: zero platform-exclusive blocking findings across 30 or more consecutive compare-mode runs, covering at least one run each of fix, feature, and refactor branch types.
- **BR-7: "Timed out" and "unavailable" are valid verdict values.** When a platform cannot complete (timeout, misconfiguration, service outage), its verdict is recorded as "timed out" or "unavailable" respectively, not as "clean" or "blocking".
- **BR-8: The meta-retrospective protocol includes a platform evaluation step.** Every 5 batches, the meta-retrospective reads the comparison metrics log and reports the running exclusive-block rate for each platform against the graduation criteria.

---

## Acceptance Criteria

- [ ] Invoking the reviewer loop with `--compare` runs all configured platforms to completion and records per-platform verdicts in the loop output key-value pairs.
- [ ] The overall exit code and `RESULT` output value from a `--compare` run are identical to what a normal run would produce for the same PR and the same platform verdicts.
- [ ] After each `--compare` run, one row is appended to `docs/workflow/retro-metrics-platforms.md` containing: PR number, branch type, and the verdict for each configured platform.
- [ ] The platform comparison metrics log (`docs/workflow/retro-metrics-platforms.md`) includes a header section documenting the graduation criteria: zero platform-exclusive blocking findings across 30 or more consecutive compare-mode runs, covering at least one fix, feature, and refactor run.
- [ ] A run where one platform blocks and another is clean is correctly identified as a platform-exclusive block in the appended metrics row.
- [ ] Normal (non-`--compare`) invocations are not affected: behavior, output, and exit codes are unchanged.
- [ ] The meta-retrospective protocol (`06b-meta-retrospective-protocol.md`) includes a platform evaluation step that reads `docs/workflow/retro-metrics-platforms.md` and reports the running exclusive-block rate for each platform against the graduation criteria.
- [ ] When fewer than 30 compare-mode runs have been logged, the meta-retrospective platform evaluation step explicitly states that data is insufficient for a graduation decision.

---

## Out of Scope (MVP)

- Automatic determination of whether a platform-exclusive block resulted in a real bug fix — the "block was a real bug" assessment is a manual post-hoc field filled by the analyst.
- Automatic platform removal or disabling when graduation criteria are met — the threshold triggers a recommendation, not an automated action.
- Compare mode for a subset of configured platforms (e.g., `--compare platform-a,platform-b`) — compare mode always runs all configured platforms.
- Visualization or dashboard for the comparison metrics — the log is a plain Markdown table.
- Cross-repository or cross-project metrics aggregation.
- Statistical significance testing or confidence intervals.
- Appending platform comparison rows to the existing structured retro metrics log (`docs/workflow/retro-metrics.md`). The brief names `retro-metrics.md` as the target file, but that file stores per-batch workflow health metrics (human interventions, violations, escalations). Mixing platform comparison data into the same table would conflate two distinct measurement concerns and make both harder to query. A dedicated file (`docs/workflow/retro-metrics-platforms.md`) is used instead. Human confirmation is requested if the single-file approach is strongly preferred.
- Configuring graduation criteria per-repository or per-platform without a protocol update.

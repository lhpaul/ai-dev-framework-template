# Structured Retro Metrics and Meta-Retrospective Protocol — Spec

---

## Overview

Retrospective action items currently have no feedback loop. A fix gets implemented but nothing verifies whether it reduced the failure mode it targeted. The same issues (protocol violations, unresolved review threads, missing labels) recur across multiple batches, suggesting that improvements are not consistently sticking.

This feature adds two complementary protocol enhancements: a required metrics block in the retrospective output format that captures per-batch signal numbers, and a periodic meta-retrospective protocol that trends those metrics across batches to verify whether prior improvements actually worked.

---

## Use Cases

### Use Case 1: Capture Retro Metrics During a Retrospective Run

**Actor**: Retrospective Analyst (the agent running protocol `06-retrospective-protocol.md`, or a human following it)
**Preconditions**: At least one batch or item run has just completed and the retrospective analyst is synthesizing findings.

**Steps**:

1. The analyst runs the retrospective as normal (Steps 1–3 of the current protocol).
2. After synthesizing findings, the analyst fills in the required metrics block covering the batch just analyzed.
3. For each prior retrospective action item that targeted the same failure modes observed in this batch, the analyst records whether each mode recurred.
4. The analyst presents the metrics block alongside the improvement opportunities in Step 4.
5. The human reviews and approves the retrospective output including the metrics block.
6. After executing Step 5 actions, the analyst appends the finalized metrics block to the running metrics log.

**Postconditions**: The metrics log contains one new entry for this batch with all required fields populated.

**Information shown**:

- The batch identifier (PR numbers or batch date)
- Counts for each tracked metric (human interventions, Step 5.2 violations, retry loops, escalations)
- A recurrence assessment for each prior action item relevant to this batch

**Actions available**:

- Approve the metrics block as-is
- Correct a metric value before finalizing

**Considerations**:

- If a metric cannot be determined from available data (e.g., PR event history is unavailable), the field is marked "unavailable" rather than left blank or guessed.
- Metrics are additive: if a batch produced zero human interventions, that is a valid and useful data point.

---

### Use Case 2: Run a Meta-Retrospective to Verify Improvement Effectiveness

**Actor**: Retrospective Analyst (running on-demand by the human, or triggered by the Portfolio Orchestrator after a configured cadence)
**Preconditions**: At least one prior retrospective entry exists in the metrics log. (When fewer than the default analysis window — 5 entries — are available, the meta-retrospective runs with all available entries and explicitly notes the limited data; it does not require a minimum of 3 entries to proceed.)

**Steps**:

1. The analyst reads the N most recent entries from the metrics log (default window: last 5 entries, configurable by the human).
2. For each action item recorded across those entries, the analyst classifies the item's outcome based on the metric trend:
   - "Verified fixed": the targeted failure mode has not recurred in any subsequent batch
   - "Partially fixed": the targeted failure mode recurred less frequently than before the fix
   - "Still recurring": the targeted failure mode recurred at the same or higher rate after the fix
3. The analyst presents the classification table to the human alongside the raw metric trend data.
4. For each item classified as "Still recurring", the analyst drafts an escalated finding at severity "high" to be included in the next retrospective.
5. The human reviews the classifications and any escalated findings.
6. If the human approves, the analyst creates backlog items for escalated findings or amends existing ones.

**Postconditions**: Each action item from the review window has a recorded outcome. Unresolved recurring failure modes are escalated into the active backlog.

**Information shown**:

- A trend table: batch identifiers across columns, tracked metrics as rows, values filled in for each batch
- A per-action-item outcome classification
- Escalated findings list (items classified "Still recurring")

**Actions available**:

- Override a classification if the human disagrees with the analyst's reading
- Accept escalated findings into the backlog
- Skip creating a backlog item for a specific finding (with optional note)

**Considerations**:

- The analysis window is configurable. If fewer entries than the default window exist, the analyst uses all available entries and notes the limited data.
- Trend data is directional, not statistically rigorous. The analyst must not overstate confidence (e.g., one clean batch after a fix does not definitively verify the fix).
- The meta-retrospective does not replace the regular retrospective. It is a periodic verification layer on top of the existing protocol.

---

## Business Rules

- **BR-1: Metrics block is required in every retrospective**. When protocol `06` runs, the metrics block must be populated before the retrospective is considered complete. A retrospective with no metrics block is incomplete.
- **BR-2: Metrics block is appended to a persistent log**. Each completed metrics block is appended to a designated tracking file (`docs/workflow/retro-metrics.md`). The file must not be cleared between batches; it is cumulative.
- **BR-3: Prior action item recurrence check is mandatory when priors exist**. If any prior retrospective action item targeted a failure mode observed in the current batch, the analyst must explicitly record whether that mode recurred — even if the recurrence is zero.
- **BR-4: Escalation threshold for meta-retrospective**. Any action item classified "Still recurring" in a meta-retrospective is automatically considered severity "high" in the next regular retrospective, regardless of its original severity.
- **BR-5: Meta-retrospective does not modify the metrics log**. The meta-retrospective reads from the metrics log but writes only to the backlog (via issues) and to the current retrospective's output. It must not edit historical entries.
- **BR-6: Metrics block fields are defined and stable**. The required fields in the metrics block are fixed (see Acceptance Criteria). Custom fields may be added by the human, but no required field may be removed without a protocol update.
- **BR-7: "Unavailable" is a valid metric value**. When a metric cannot be reliably determined from GitHub data or conversation context, "unavailable" is recorded. The analyst must not substitute a guess.
- **BR-8: Cadence for meta-retrospective is advisory, not mandatory**. The recommended cadence is every 5 batches, but the human may trigger it at any time. Nothing in the protocol prevents running it more or less frequently.

---

## Out of Scope (MVP)

- A dedicated dashboard or visualization tool for metrics trends (the tracking file is a simple Markdown table).
- Automated metric capture (metrics are filled by the analyst based on available GitHub and conversation data — no background data collection runs).
- Integration with external observability or analytics platforms.
- Alerting or notifications when a failure mode crosses a threshold.
- Statistical significance testing or confidence intervals for trend data.
- Cross-repository or cross-project metric aggregation.
- Automated triggering of the meta-retrospective on a fixed schedule; the cadence is advisory and manually invoked.
- Versioning or archiving of historical metrics log entries (the log is append-only in the Markdown file).

---

## Acceptance Criteria

- [ ] Protocol `06-retrospective-protocol.md` includes a required metrics block step. The step defines the exact fields that must be populated: batch identifier, count of human interventions, count of Step 5.2 violations, count of automated-reviewer retry loops, count of escalations, and a per-prior-action-item recurrence assessment.
- [ ] The metrics block format is specified clearly enough that any analyst (human or agent) produces a structurally consistent entry across batches without ambiguity about field definitions.
- [ ] The metrics block step in protocol `06` instructs the analyst to append the finalized block to `docs/workflow/retro-metrics.md` after the retrospective's Step 5 (action execution) completes.
- [ ] A new file `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md` (or `docs/workflow/development-workflow/protocols/06-meta-retrospective-protocol.md`) exists and defines the full meta-retrospective procedure: scope resolution (reading the metrics log), trend analysis, classification of prior action items into "Verified fixed" / "Partially fixed" / "Still recurring", escalation of "Still recurring" items, and a human-approval gate before writing to the backlog.
- [ ] The meta-retrospective protocol specifies the default analysis window (5 entries) and documents how to override it.
- [ ] The meta-retrospective protocol produces a classification table and an escalated findings list in a format consistent with the regular retrospective's improvement opportunity format.
- [ ] `docs/workflow/retro-metrics.md` exists as an initial (empty or example-seeded) tracking file with the column headers matching the required metrics block fields, committed alongside the protocol changes.
- [ ] The regular retrospective protocol (`06`) references the meta-retrospective protocol (`06b` or equivalent) in its closing section so that operators know when and how to trigger the periodic verification pass.
- [ ] The regular retrospective protocol documents that metrics blocks written before this feature existed will naturally be absent from the log; the meta-retrospective gracefully handles a log with fewer entries than its analysis window by analyzing whatever is available.

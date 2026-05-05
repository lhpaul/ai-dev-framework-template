# Protocol: Run Meta-Retrospective

**Agent role**: Retrospective Analyst
**Purpose**: Periodic verification of whether prior retrospective improvement action items are actually working, by trending per-batch metrics across multiple completed retrospectives

This protocol is a periodic verification layer on top of the regular retrospective (`06-retrospective-protocol.md`). It does not replace the regular retrospective — it reads from the persistent metrics log that the regular retrospective populates and determines whether past improvements are holding.

---

## Prerequisites

- `docs/workflow/retro-metrics.md` must exist (created when this feature ships).
- At least one prior retrospective entry must be present in the metrics log. If fewer than the default analysis window (5 entries) are available, the meta-retrospective runs with all available entries and explicitly notes the limited data. It does not require a minimum number of entries to proceed.

---

## Analysis Window

**Default window**: the 5 most recent entries in `docs/workflow/retro-metrics.md`.

**Override**: the human may specify a different count at invocation time (e.g., "run meta-retro on the last 10 entries"). Use the human-provided count instead of the default.

If fewer entries than the window size are available, use all available entries and note the limited data explicitly in the output (e.g., "Note: Only N entries available — analysis window reduced from 5 to N. Trend conclusions should be treated with additional caution.").

---

## Step 1: Resolve Scope

Read the N most recent entries from `docs/workflow/retro-metrics.md` (N = window size, default 5).

```bash
# Inspect the metrics log
cat docs/workflow/retro-metrics.md
```

Extract from each entry:
- Batch identifier
- Human interventions count
- Step 5.2 violations count
- Automated-reviewer retry loops count
- Escalations count
- Prior action item recurrence assessment (which items recurred vs. did not)

If the file does not exist, stop and report:

> `docs/workflow/retro-metrics.md` was not found. This file is created by the first completed retrospective run after the structured retro metrics feature (#458) is deployed. No meta-retrospective can be run until at least one retrospective entry exists.

---

## Step 2: Trend Analysis

Build a trend table with batch identifiers across columns and tracked metrics as rows. Fill in the value from each batch's entry for each metric row.

Example format:

```markdown
## Trend Table

| Metric | Batch A | Batch B | Batch C | Batch D | Batch E |
|---|---|---|---|---|---|
| Human Interventions Count | 2 | 1 | 0 | 1 | 0 |
| Step 5.2 Violations Count | 3 | 1 | 0 | 0 | 0 |
| Automated-Reviewer Retry Loops Count | 5 | 3 | 2 | 1 | 2 |
| Escalations Count | 1 | 0 | 0 | 0 | 0 |
```

Where a field value is `unavailable`, carry it through to the table as-is. Do not substitute a guess or a zero.

**Important**: Trend data is directional, not statistically rigorous. The analyst must not overstate confidence. One clean batch after a fix does not definitively verify the fix; one bad batch does not definitively disprove it. State this caveat clearly in the output.

---

## Step 3: Classify Prior Action Items

For each action item recorded in the retrospective entries within the analysis window, classify its outcome based on the metric trend:

| Outcome | Label | Condition |
|---|---|---|
| Fixed | `Verified fixed` | The targeted failure mode has not recurred in any batch within the analysis window |
| Improving | `Partially fixed` | The targeted failure mode recurred less frequently than before the fix was applied |
| Not resolved | `Still recurring` | The targeted failure mode recurred at the same or higher rate after the fix was applied |

If a failure mode cannot be matched to a specific action item (e.g., the failure mode appeared but no prior action item targeted it), note it as a new observation rather than forcing a classification.

If fewer window entries than the default are available, treat all classifications with explicit caution. One clean batch is not sufficient to classify as `Verified fixed`.

---

## Step 4: Escalation

For each action item classified as `Still recurring`:

1. Draft an escalated finding at severity **high** to be included in the next regular retrospective.
2. Use the same format as the regular retrospective's improvement opportunities (category, severity, observed, impact, recommended action).
3. Explicitly note that this item is escalated from the meta-retrospective because the targeted failure mode persisted through the analysis window despite a prior action item.

Constraints:
- Severity for `Still recurring` items is always `high`, regardless of the original severity assigned when the action item was first created.
- Do not create backlog items, edit existing issues, or push changes before the human-approval gate in Step 5.
- The meta-retrospective must not edit any entries in `docs/workflow/retro-metrics.md`. This file is append-only and is written exclusively by the regular retrospective in its Step 6 close action.

---

## Step 5: Human Review Gate

Present the following to the human and wait for approval before proceeding to Step 6:

1. **Limited-data note** (if applicable): "Only N entries available; window reduced."
2. **Trend table** (from Step 2).
3. **Classification table**: one row per action item with batch identifier, action item description, and outcome label (`Verified fixed`, `Partially fixed`, `Still recurring`).
4. **Escalated findings list**: formatted improvement opportunities for each `Still recurring` item, ready to include in the next retrospective.
5. **Caveat**: "Trend data is directional, not statistically rigorous."

Prompt the human:

> For each "Still recurring" item above, please choose:
> - **Create backlog item**: create a new issue with the escalated finding
> - **Expand existing**: add the escalated finding to an existing issue
> - **Skip**: acknowledge and move on (with optional note)
>
> Please also confirm or override any classifications you disagree with.

Wait for explicit human choices before executing Step 6.

---

## Step 6: Backlog Update

For each human-approved escalated finding (items the human chose **Create backlog item** or **Expand existing** for):

**If expanding an existing issue**: append the escalated finding as an additional observation. Use the same `gh issue edit` flow as `06-retrospective-protocol.md` Step 5 (Add to backlog — Expand existing path).

**If creating a new issue**: use the same `gh issue create` flow as `06-retrospective-protocol.md` Step 5 (Add to backlog — Create new path), with label `workflow`. Use this issue body format:

```markdown
## Observed

[Failure mode description — specific, factual]
[State that this item is escalated from the meta-retrospective because it persisted through the analysis window]

## Impact

[What it has continued to cause across multiple batches]

## Category

[Category display label] — High

## Source

Meta-retrospective analysis (window: N entries, batches: [list of batch identifiers]) on [date]
Prior action item: #NNN — [original action item title or description]
```

Report each created or updated issue with its URL.

**Constraints**:
- Do not write to `docs/workflow/retro-metrics.md`. Only the regular retrospective (Step 6 close) appends to that file.
- Do not close or edit historical retrospective output documents.

---

## Closing Summary

After Step 6 completes, provide a summary:

```markdown
## Meta-Retrospective Complete

**Analysis window**: N entries (batches: [list])
**Data note**: [Full data | Limited data — only N of default-5 entries available]
**Trend caveat**: Trend data is directional, not statistically rigorous.

### Classification Results

| Action Item | Outcome | Escalated? |
|---|---|---|
| [description] | Verified fixed | No |
| [description] | Partially fixed | No |
| [description] | Still recurring | Yes — Issue #NNN created |

### Escalated Findings

[List of issues created or expanded, with URLs]
```

---

## See Also

- Regular retrospective protocol: `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`
- Metrics log: `docs/workflow/retro-metrics.md`

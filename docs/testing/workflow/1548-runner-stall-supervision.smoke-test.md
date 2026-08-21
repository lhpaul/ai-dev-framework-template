# Smoke Test Runbook: Runner-Stall Supervision (`stalled` Classification)

**Feature**: Item-runner stall prevention and parent-side `stalled` report classification (issue #1548)
**Spec**: N/A (Fast Track — process/documentation fix; see [GitHub issue #1548](https://github.com/lhpaul/ai-dev-framework-template/issues/1548))
**Implementation plan**: N/A (Fast Track)
**Created in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The updated protocol files (`91-orchestrate-work-protocol.md` and `90-batch-orchestrate-work-protocol.md`) and the updated agent/skill files (`.claude/agents/item-orchestrator.md`, `.cursor/agents/item-orchestrator.md`, `.codex/skills/workflow-item-orchestrator/SKILL.md`) are present in the branch under test.

---

## Known Limitations

This runbook validates **protocol and agent-instruction prose**, not executable
code. There is no automated test harness in this repository that parses free
text and asserts a classification outcome — the check below is a manual,
human-run (or agent-run-on-request) walkthrough, following the same convention
used by `protocol-90-tracker-status-update.smoke-test.md`. It confirms the
required text is present and unambiguous, and that a human tracing the rule by
hand against each fixture reaches the classification the acceptance criteria
require. It does not prove that every future runner will actually comply — no
protocol-prose test can. If this repository later gains a fixture-runner (e.g.
a script that feeds report text to a classifier function and asserts
`stalled`/`terminal`), the fixtures below should move there unchanged; until
then, this is the testable mechanism available.

---

## Test Data — Report Fixtures

These are the fixtures required by issue #1548's AC-4. Three are the verbatim
stall reports from the 2026-08-20/21 overnight run (issue #1548's own evidence
table); the fourth is a genuine terminal report used as the negative case.

### Fixture 1 — must classify as `stalled` (item #1508)

> "I will resume automatically when notified that the background run has finished"

No PR number is paired with `ready-for-human-review`, `blocked`, or
`escalated`. The report describes waiting on a notification that (per
`91-orchestrate-work-protocol.md`, "Execution Discipline: A Paused Turn Does
Not Resume") will never arrive at this runner.

### Fixture 2 — must classify as `stalled` (item #1333)

> "I'll wait here and process its output as soon as the completion notification arrives"

Same shape as Fixture 1: a background step (`pr-review-loop.sh 1546`) with no
named terminal state, waiting on a notification the runner itself will never
receive.

### Fixture 3 — must classify as `stalled` (item #1400)

> "I'll pause here and wait for the background task notification before continuing"

Same shape again, for `pr-review-loop.sh 1543`.

### Fixture 4 — must NOT classify as `stalled` (genuine terminal report)

> "PR #1546 is ready for human review. `pr-review-loop.sh` completed with `RESULT=clean`, `gh pr ready` was applied, CI is green, and `ready-for-human-review` was applied. Tracker status is `Development in Review`. Stopping here — waiting on human review/merge."

This report names a PR number paired with `ready-for-human-review` (a named
terminal state under Protocol 90 Step 5 item 1). It must classify as
terminal, not `stalled`.

---

## Smoke Test Steps

### Step 1: Verify the runner-side rule exists and is general

- Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.
- Confirm an "Execution Discipline: A Paused Turn Does Not Resume" section (or
  equivalent) appears before Step 0, stating plainly that a paused turn does
  not resume, and prescribing foreground-or-poll for **every** long step (not
  only `pr-review-loop.sh` / `pr-ci-loop.sh`).
- Confirm the section (or Step 7) warns against re-invoking `pr-review-loop.sh`
  for a PR whose loop is already running, names the `lock_contention` / exit
  `75` behavior, and describes reading the outcome from PR state instead.

**Expected result**: Both AC-1 and AC-2 requirements are present, in a section
a runner reads as part of its own instructions (not only in an appendix).

### Step 2: Verify the same rule reaches agent/skill instruction files

- Open `.claude/agents/item-orchestrator.md`, `.cursor/agents/item-orchestrator.md`,
  and `.codex/skills/workflow-item-orchestrator/SKILL.md`.
- Confirm each contains the "a paused turn does not resume" statement and the
  `pr-review-loop.sh` re-invocation warning, not only a pointer to Protocol 91.

**Expected result**: All three surfaces state the rule directly, since these
files (not the protocol document) are what is loaded directly into a runner's
context in each tool.

### Step 3: Verify Protocol 90's parent-side `stalled` classification

- Open `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`.
- Navigate to **Step 5: Supervise Until Terminal**.
- Confirm item 1 of the numbered list defines `stalled`: a returned report
  naming no terminal state (no PR number paired with
  `ready-for-human-review`/`blocked`/`escalated`) is classified `stalled`.
- Confirm the text requires resume/re-dispatch rather than acceptance, and
  states plainly that `stalled` is not itself a stop condition (not `blocked`,
  not `escalated`).

**Expected result**: The classification rule and its required action
(resume/re-dispatch, not acceptance) are both present and unambiguous.

### Step 4: Trace each fixture against the Step 5 item 1 rule by hand

For each fixture in **Test Data** above, apply the mechanical test from Step 5
item 1: does the report name a PR number paired with `ready-for-human-review`,
`blocked`, or `escalated`?

| Fixture | Contains a named terminal state? | Required classification |
| ------- | --------------------------------- | ------------------------ |
| 1 (#1508) | No | `stalled` |
| 2 (#1333) | No | `stalled` |
| 3 (#1400) | No | `stalled` |
| 4 (genuine terminal) | Yes — PR #1546, `ready-for-human-review` | terminal (not `stalled`) |

**Expected result**: Applying the Step 5 item 1 rule by hand to each fixture
produces exactly the classification in the table above.

### Last Step: Assertions Checklist

- Verify all assertions below are met before closing.

---

## Assertions Checklist

- [ ] Protocol 91 states plainly that a paused turn does not resume, generalized beyond `pr-review-loop.sh`/`pr-ci-loop.sh` (AC-1)
- [ ] Protocol 91 warns against re-invoking `pr-review-loop.sh` on a PR whose loop is already running, names `lock_contention`/exit 75, and describes reading outcome from PR state instead (AC-2)
- [ ] `.claude/agents/item-orchestrator.md`, `.cursor/agents/item-orchestrator.md`, and `.codex/skills/workflow-item-orchestrator/SKILL.md` each state both rules directly (not only via a pointer)
- [ ] Protocol 90 Step 5 defines a `stalled` classification for a runner report lacking a named terminal state (AC-3)
- [ ] Protocol 90 Step 5 requires resume/re-dispatch for a `stalled` report rather than acceptance, and states `stalled` is not itself a stop condition
- [ ] Fixtures 1–3 (the verbatim #1508/#1333/#1400 reports) trace to `stalled` under the classification rule (AC-4)
- [ ] Fixture 4 (genuine terminal report) traces to terminal, not `stalled`, under the same rule (AC-4)
- [ ] `CHANGELOG.md` has an `[Unreleased]` → `### Fixed` entry for this change

---

## Seed Data Reference

Not applicable — this smoke test validates protocol and agent-instruction
documentation only; no application seed data is required.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| "Execution Discipline" section not found in Protocol 91 | Change not yet merged into the branch under test | Confirm `fix/1548-runner-stall-supervision` (or its merged commit) is present |
| Agent/skill files only reference Protocol 91 without restating the rule | Edit applied to the protocol but not propagated to the duplicated agent-instruction copies | Re-apply the rule text directly in each of the three files |
| Step 5 item 1 missing from Protocol 90 | Change not yet merged, or numbered-list items were renumbered incorrectly during a later edit | Restore item 1 as the `stalled` classification and confirm items 2–7 still match their original content in order |

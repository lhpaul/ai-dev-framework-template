# Smoke Test Runbook: Security-Sensitive Advisory Human Decision Requirement

**Feature**: Security-Sensitive Advisory Human Decision Requirement
**Spec**:
[1_1432-security-advisory-human-decision_specs.md](../../specs/developments/20260811131628_1432-security-advisory-human-decision/1_1432-security-advisory-human-decision_specs.md)
**Created in**: Plan Ready stage
**Updated in**: Plan Ready stage

---

## Prerequisites

- [ ] You are reviewing the implementation PR for #1432.
- [ ] The PR targets `develop`.
- [ ] Fixture tests are available and do not require live GitHub mutation
      (mocked `gh` binary, following the existing
      `test-run-epic-delegated-gate.sh` pattern).

---

## Test Data

| Item                          | Value                                                                              |
| ------------------------------ | ------------------------------------------------------------------------------------ |
| Classifier script              | `scripts/development-workflow/security-advisory-classifier.sh`                     |
| Tracker/reconciliation script  | `scripts/development-workflow/security-advisory-tracker.sh`                        |
| Delegated gate                 | `scripts/development-workflow/run-epic-delegated-gate.sh`                          |
| Audit helper                   | `scripts/development-workflow/run-epic-audit-trail.sh`                             |
| Classifier tests               | `scripts/development-workflow/tests/test-security-advisory-classifier.sh`          |
| Tracker tests                  | `scripts/development-workflow/tests/test-security-advisory-tracker.sh`             |
| Delegated gate tests (extended) | `scripts/development-workflow/tests/test-run-epic-delegated-gate.sh`              |
| Audit trail tests (extended)   | `scripts/development-workflow/tests/test-run-epic-audit-trail.sh`                  |
| Reviewer-loop protocol         | `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` |
| Orchestrate-work protocol      | `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`     |
| Run-epic protocol              | `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`             |
| Guardrails enforcement doc     | `docs/workflow/development-workflow/guardrails-enforcement.md`                     |
| Guardrails config doc          | `docs/workflow/development-workflow/guardrails.md`                                 |
| Label                          | `security-advisory-decision-required`                                              |
| Stop condition                 | `security_sensitive_advisory_pending`                                              |

---

## Smoke Test Steps

### Step 1: Classification is narrow and conjunctive (BR1, BR2, BR3, AC1)

**Maps to**: AC1.

1. Run `security-advisory-classifier.sh classify` with a finding that matches
   only the content-category test (e.g., an auth-bypass-shaped finding
   against an application file **not** on the enforcement-surface allowlist).
2. Confirm `securitySensitive: false`.
3. Run it again with a finding that matches only the file-location test
   (e.g., a code-style finding against
   `scripts/development-workflow/run-epic-delegated-gate.sh`).
4. Confirm `securitySensitive: false`.

**Expected result**: A match on only one part of BR1's two-part test never
classifies as security-sensitive.

### Step 2: Zero-of-three on this batch's real non-security findings (BR2, BR3, AC2)

**Maps to**: AC2.

1. Run the classifier against fixture reconstructions of PR-Agent's jq
   iteration claim (PR #1459), CodeRabbit's JSON key-type claim (PR #1460),
   and PR-Agent's quote-escaping claim (PR #1467), each against their actual
   (non-enforcement-surface) target files.
2. Confirm all three return `securitySensitive: false`.

**Expected result**: The classifier does not fire on ordinary code-quality
advisory findings from this batch's real history, matching the spec's stated
≤5% expected trigger rate.

### Step 3: Positive match on the motivating PR #1431 shape (BR1, AC3)

**Maps to**: AC3.

1. Run the classifier against fixture findings shaped like PR #1431's two
   findings (unsafe force semantics without a lease; permissive remote URL
   parsing), targeted at
   `scripts/development-workflow/workflow-branch-push-guard.sh`.
2. Confirm both return `securitySensitive: true` with the expected matched
   category and matched file.

**Expected result**: The exact class of finding that motivated this issue is
correctly classified as security-sensitive.

### Step 4: Delegated merge is blocked regardless of authority (BR5, AC4, AC5)

**Maps to**: AC4, AC5.

1. Assemble a fixture Gate 5 evidence file for a PR that is otherwise fully
   green (clean reviewer loop, green CI, `ready-for-human-review` +
   `ready-for-regression` present, no unresolved threads, no risk blockers)
   with `policy.mayMerge: true` and `mode: delegated`, plus one
   `.securityAdvisories[]` entry with `status: "pending"`.
2. Run `run-epic-delegated-gate.sh --input <evidence-file> --json`.
3. Confirm `decision == "human_required"` (the exact string, not merely
   `!= "merge_allowed"` — the gate's decision-classification chain requires
   an explicit keyword match to produce `"human_required"` rather than
   falling through to the generic `"blocked"` value) and `reasons[]` includes
   a string starting with `security_sensitive_advisory_pending:`.
4. Re-run with the same entry's `status` set to `"fixed"` and a `fixCommit`
   present, and separately with a verified
   `.securityAdvisoryDecisionEvents[]` entry resolving it as
   `human-accepted` with rationale.
5. Confirm both re-runs allow `decision: "merge_allowed"` (assuming every
   other gate condition remains green).

**Expected result**: A delegated agent cannot merge past an unresolved
security-sensitive finding under any authority grant; a fix or a verified
human decision unblocks it.

### Step 5: A blanket checkpoint waiver does not resolve it (BR4, AC6, AC7)

**Maps to**: AC6, AC7.

1. Reuse Step 4's blocking fixture evidence file and add a `waived`
   bounded-prelude checkpoint for an unrelated item/stage on the same PR.
2. Run the gate again.
3. Confirm the PR is still blocked with the same
   `security_sensitive_advisory_pending` reason, and confirm the reasons list
   contains no `human_checkpoint_required` text for this finding.
4. Confirm the label string `security-advisory-decision-required` and the
   stop-condition string `security_sensitive_advisory_pending` are both
   textually distinct from `human-checkpoint-required` /
   `human_checkpoint_required` (grep the modified files for accidental reuse).

**Expected result**: The two mechanisms are provably independent — a
checkpoint waiver recorded for unrelated work cannot resolve a
security-sensitive advisory finding it was never about.

### Step 6: Coverage is identical across invocation surfaces (BR8, BR9, AC8, AC9)

**Maps to**: AC8, AC9.

1. Run the same blocking fixture evidence file from Step 4 three times, each
   time with a different `.pr.inScope` value: absent, `true`, `false`.
2. Confirm absent and `true` both still block with the
   `security_sensitive_advisory_pending` reason.
3. Confirm `false` short-circuits to `decision: "not_applicable"` exactly the
   same way the pre-existing scope short-circuit already behaves for every
   other reason (no new behavior specific to this feature in that branch).

**Expected result**: The security-sensitive-advisory check runs inside the
gate's normal reasons cascade for every non-explicitly-excluded PR, on every
invocation surface (`/run-item`, `/run-items`, `/run-epic`) that assembles
Gate 4/5 evidence the same way.

### Step 7: Human decision verification is specific and fail-closed (BR6, AC10, AC11)

**Maps to**: AC10, AC11.

1. Run `github_verified_security_advisory_decisions` fixture tests (via the
   extended `test-run-epic-delegated-gate.sh`) with: a correctly-authored,
   correctly-permissioned, exact-text-match decision comment (resolves); a
   comment from a `Bot`-typed author (does not resolve); a comment from a
   human with `read`/`triage` permission only (does not resolve); a comment
   whose finding id, PR number, or head SHA does not match the current
   evidence (does not resolve); a generic prior PR approval or unrelated
   comment (does not resolve).
2. Confirm every negative case leaves the finding `pending`, never silently
   `human-accepted`/`human-rejected`.

**Expected result**: Only a decision verifiably tied to the exact finding,
PR, and current head commit — authored by a human with sufficient repository
permission — resolves a pending finding.

### Step 8: Every push re-evaluates every tracked finding, regardless of status (BR7, AC12, AC13)

**Maps to**: AC12, AC13.

1. Run `security-advisory-tracker.sh reconcile` fixture tests covering all
   four prior statuses (`pending`, `fixed`, `human-accepted`,
   `human-rejected`) at a new head SHA, once where the finding still matches
   BR1 at the new head and once where it no longer matches.
2. Confirm: still-matching → status resets to `pending` with a
   `superseded_by_new_commit` audit reason (not a separate `stale` status);
   no-longer-matching → the finding exits the reconciled output entirely,
   from every prior status including `pending`.

**Expected result**: No prior fix or human decision silently carries forward
across a push, and no finding that no longer matches BR1 keeps blocking Gate
5.

### Step 9: Distinct, visible summary section (BR4, AC14)

**Maps to**: AC14.

1. Run `run-epic-audit-trail.sh render-pr-disposition` fixture tests with
   both non-empty `.advisories[]` and non-empty `.securityAdvisories[]`.
2. Confirm both the existing "Advisory Decisions" section and the new
   "Security-Sensitive Advisory Findings" section render, are visibly
   distinct (different headings, no nesting), and each lists only its own
   entries.

**Expected result**: A human or future retrospective can see security-
sensitive findings and their disposition state at a glance, separate from
ordinary advisory dispositions.

### Step 10: Protocol and guardrails documentation consistency (cross-document)

1. Grep `docs/workflow/development-workflow/guardrails-enforcement.md` and
   `docs/workflow/development-workflow/guardrails.md` for
   `security_sensitive_advisory_pending` and confirm both list it with
   matching descriptions.
2. Grep `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`,
   `91-orchestrate-work-protocol.md`, and `95-run-epic-protocol.md` for the
   `security-advisory-decision-required` label and confirm consistent usage.
3. Confirm `REVIEW.md`'s guardrails-enforcement-behavior checklist includes
   the new BR5 carve-out bullet.

**Expected result**: All six modified/created documents use the same label,
stop-condition, and evidence-field names with no drift.

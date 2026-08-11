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
- [ ] The implementation PR's scripts and tests (`security-advisory-classifier.sh`,
      `security-advisory-tracker.sh`, the modified `run-epic-delegated-gate.sh`
      / `run-epic-audit-trail.sh`, and every `test-*.sh` file listed in Test
      Data below) are present and committed on the branch being validated —
      this runbook's steps assume the implementation has already landed, not
      only the plan.
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

1. Run:

   ```bash
   scripts/development-workflow/security-advisory-classifier.sh classify \
     --finding-text "this endpoint bypasses the auth check for admin users" \
     --file-path "src/app/admin-controller.ts"
   ```

2. Confirm the output is `{"securitySensitive": false, ...}` — the content
   category (a) matches, but `src/app/admin-controller.ts` is not on the
   Part B enforcement-surface allowlist.
3. Run:

   ```bash
   scripts/development-workflow/security-advisory-classifier.sh classify \
     --finding-text "this jq filter could be written more concisely" \
     --file-path "scripts/development-workflow/run-epic-delegated-gate.sh"
   ```

4. Confirm the output is `{"securitySensitive": false, ...}` — the file is
   on the Part B allowlist, but the finding text matches no Part A category.

**Expected result**: A match on only one part of BR1's two-part test never
classifies as security-sensitive.

### Step 2: Zero-of-three on this batch's real non-security findings (BR2, BR3, AC2)

**Maps to**: AC2.

1. Run the classifier against fixture reconstructions of this batch's three
   real non-security findings, each against its actual
   (non-enforcement-surface) target file, e.g.:

   ```bash
   scripts/development-workflow/security-advisory-classifier.sh classify \
     --finding-text "this jq iteration could produce duplicate entries if the array contains repeated keys" \
     --file-path "scripts/development-workflow/run-epic-audit-trail.sh"
   # PR #1459 (PR-Agent) — adapt file path to the file that finding actually
   # targeted if different.

   scripts/development-workflow/security-advisory-classifier.sh classify \
     --finding-text "this JSON key is typed as a string but consumed as a number downstream" \
     --file-path "scripts/development-workflow/run-epic-risk-classifier.sh"
   # PR #1460 (CodeRabbit)

   scripts/development-workflow/security-advisory-classifier.sh classify \
     --finding-text "this quote is not escaped consistently with the rest of the string" \
     --file-path "scripts/development-workflow/pr-review-loop.sh"
   # PR #1467 (PR-Agent)
   ```

2. Confirm all three return `securitySensitive: false`.

**Expected result**: The classifier does not fire on ordinary code-quality
advisory findings from this batch's real history, matching the spec's stated
≤5% expected trigger rate.

### Step 3: Positive match on the motivating PR #1431 shape (BR1, AC3)

**Maps to**: AC3.

1. Run:

   ```bash
   scripts/development-workflow/security-advisory-classifier.sh classify \
     --finding-text "raw git push --force is used here without a safety lease" \
     --file-path "scripts/development-workflow/workflow-branch-push-guard.sh"
   ```

2. Confirm the output is `{"securitySensitive": true, "matchedCategory": "c", "matchedFile": "scripts/development-workflow/workflow-branch-push-guard.sh"}`.
3. Run:

   ```bash
   scripts/development-workflow/security-advisory-classifier.sh classify \
     --finding-text "the remote URL parsing here is too permissive and could let a spoofed remote bypass the push guard's validation check" \
     --file-path "scripts/development-workflow/workflow-branch-push-guard.sh"
   ```

4. Confirm the output is `{"securitySensitive": true, "matchedCategory": "e", "matchedFile": "scripts/development-workflow/workflow-branch-push-guard.sh"}`.

**Expected result**: The exact class of finding that motivated this issue is
correctly classified as security-sensitive, with the expected matched
category for each finding.

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
   present. Separately, re-run with the entry's `status` left `"pending"`
   but `.securityAdvisoryDecisionEvents[]` carrying one raw candidate
   reference in the declared `{id, type}` shape (mirroring
   `.authorizationEvents[]`), e.g. `{"id": "1234567890", "type": "review_comment"}`,
   with the mocked `gh` binary configured to return, for that comment id, a
   fetched comment body matching the decision-recording template exactly
   (finding id + PR + head SHA embedded) and author metadata satisfying
   BR6 (human author, `write` or `admin` permission) — e.g.: `I record a
   human decision for security-sensitive advisory finding <finding-id> on
   PR #<pr> at head <head-sha>: accept — <rationale>`. Confirm
   `github_verified_security_advisory_decisions` (exercised via the gate
   run) resolves this to `human-accepted` with the rationale extracted from
   the fetched comment body, and that the resulting `.securityAdvisories[]`
   entry's `status` is `human-accepted`.
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
5. Label add/remove is a Protocol 93 step, not `security-advisory-tracker.sh
   apply` — verify both transitions directly against the documented
   procedure with a mocked `gh` binary: run
   `security-advisory-tracker.sh reconcile` with `--current` containing one
   fresh finding (yielding a `pending` reconciled entry), then simulate the
   Protocol 93 label step and confirm it invokes
   `gh pr edit --add-label security-advisory-decision-required` (label now
   present). Re-run `reconcile` with `--current` containing zero findings
   for that PR (the finding no longer matches BR1) and confirm the
   simulated label step instead invokes `gh pr edit --remove-label
   security-advisory-decision-required` (label now absent).

**Expected result**: The two mechanisms are provably independent — a
checkpoint waiver recorded for unrelated work cannot resolve a
security-sensitive advisory finding it was never about. The
`security-advisory-decision-required` label is added when reconciliation
yields at least one `pending` entry and removed when it yields zero,
verified in both directions.

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
Gate 4/5 evidence the same way. Note: this step proves the **gate** is
invocation-surface-agnostic (it evaluates whatever evidence it receives); it
does not by itself prove all three surfaces' documentation actually
instructs them to assemble that evidence identically — see Step 10, item 2,
for the documentation-consistency check that closes that gap.

### Step 7: Human decision verification is specific and fail-closed (BR6, AC10, AC11)

**Maps to**: AC10, AC11.

1. Run `github_verified_security_advisory_decisions` fixture tests (via the
   extended `test-run-epic-delegated-gate.sh`) with:
   - A correctly-authored, exact-text-match decision comment from a human
     author with `write` permission (resolves).
   - A correctly-authored, exact-text-match decision comment from a human
     author with `admin` permission (resolves) — both accepted permission
     levels must have their own positive fixture, not just `write`.
   - A comment from a `Bot`-typed author (does not resolve).
   - A comment from a human with `read`/`triage` permission only (does not
     resolve).
   - A comment whose finding id, PR number, or head SHA does not match the
     current evidence (does not resolve).
   - A generic prior PR approval or unrelated comment (does not resolve).
2. Confirm every negative case leaves the finding `pending`, never silently
   `human-accepted`/`human-rejected`, and confirm both positive cases
   (`write` and `admin`) resolve to the decision recorded in the comment.

**Expected result**: Only a decision verifiably tied to the exact finding,
PR, and current head commit — authored by a human with sufficient repository
permission — resolves a pending finding.

### Step 8: Every push re-evaluates every tracked finding, regardless of status (BR7, AC12, AC13)

**Maps to**: AC12, AC13.

1. Run `security-advisory-tracker.sh reconcile` fixture tests covering all
   four prior statuses (`pending`, `fixed`, `human-accepted`,
   `human-rejected`) at a **new** head SHA (`--head-sha` differs from the
   prior entry's `headSha`), once where the finding still matches BR1 at the
   new head and once where it no longer matches.
2. Confirm: still-matching → status resets to `pending` with a
   `superseded_by_new_commit` audit reason (not a separate `stale` status);
   no-longer-matching → the finding exits the reconciled output entirely,
   from every prior status including `pending`.
3. Run `security-advisory-tracker.sh reconcile` fixture tests covering the
   **same-head** case (`--head-sha` equals the prior entry's `headSha`) for
   all four prior statuses (`pending`, `fixed`, `human-accepted`,
   `human-rejected`), each with the finding still matching BR1 at that head.
4. Confirm for every same-head case: the entry's `status`, decision metadata
   (`decider`/`decidedAt`/`rationale` for human-decided entries, `fixCommit`
   for the fixed entry), and audit reason are all byte-for-byte unchanged
   from the prior entry — no reset to `pending`, no `superseded_by_new_commit`
   reason, confirming reconciliation is idempotent at a stable head SHA.

**Expected result**: No prior fix or human decision silently carries forward
across a push, and no finding that no longer matches BR1 keeps blocking Gate
5. Reconciliation at an unchanged head SHA never mutates a tracked finding's
status or metadata, for any of the four persisted statuses.

### Step 9: Distinct, visible summary section (BR4, AC14)

**Maps to**: AC14.

1. Run `run-epic-audit-trail.sh render-pr-disposition` fixture tests with
   both non-empty `.advisories[]` and non-empty `.securityAdvisories[]`.
2. Confirm both the existing "Advisory Decisions" section and the new
   "Security-Sensitive Advisory Findings" section render, are visibly
   distinct (different headings, no nesting), and each lists only its own
   entries.
3. Add a `human-accepted` entry and a `human-rejected` entry to
   `.securityAdvisories[]`, each with `decider`, `decidedAt`, and
   `rationale` populated. Confirm the rendered output contains all three
   fields' actual values for each entry (not just the row existing) —
   assert on the literal decider name, timestamp, and rationale text
   appearing in the rendered section.
4. Run `run-epic-audit-trail.sh apply-pr-disposition` (or the equivalent
   validation entry point) with a `human-accepted` entry and a
   `human-rejected` entry that each omit `rationale`. Confirm both cases
   hard-fail with `error_exit` (mirroring the existing "non-fixed advisory
   decisions require rationale" rule), and that the process does not
   silently render or persist a rationale-less resolved entry.

**Expected result**: A human or future retrospective can see security-
sensitive findings and their disposition state at a glance, separate from
ordinary advisory dispositions. Decider, timestamp, and rationale actually
render for resolved entries, and a `human-accepted`/`human-rejected` entry
without rationale is rejected, never silently accepted.

### Step 10: Protocol and guardrails documentation consistency (cross-document)

1. Extract the `security_sensitive_advisory_pending` row/description text
   from `docs/workflow/development-workflow/guardrails-enforcement.md`
   § 4 Named Stop Conditions and from `docs/workflow/development-workflow/guardrails.md`
   Stop Conditions table (do not just grep for the token's presence —
   copy each document's actual description text). Diff the two extracted
   descriptions and confirm they match; a token-presence grep alone would
   pass even if the two documents described the condition inconsistently
   or used a stale spelling in one place.
2. Extract the paragraph text describing `.securityAdvisories[]` /
   `.securityAdvisoryDecisionEvents[]` evidence assembly from
   `91-orchestrate-work-protocol.md`'s Step 7a/Gate-5-evidence-assembly
   guidance and from `95-run-epic-protocol.md`'s Step 8/9/10 updates. Diff
   the two extracted paragraphs and confirm they describe the same evidence
   fields with matching wording — this is the check that closes the gap
   Step 6 above notes: the gate itself is proven surface-agnostic by
   fixture test, but only this diff proves the *documentation* instructs
   `/run-item`, `/run-items`, and `/run-epic` to assemble that evidence
   identically (AC8).
3. Grep `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`,
   `91-orchestrate-work-protocol.md`, and `95-run-epic-protocol.md` for the
   `security-advisory-decision-required` label and confirm consistent
   usage (token presence is sufficient here since this check is only
   confirming the same label string is referenced, not that surrounding
   descriptive text matches).
4. Confirm `REVIEW.md`'s guardrails-enforcement-behavior checklist includes
   the new BR5 carve-out bullet, and that its wording matches the BR5
   carve-out sentence added to Gate 4 in `guardrails-enforcement.md`.

**Expected result**: All six modified/created documents use the same label,
stop-condition, and evidence-field names with no drift, verified by
comparing the actual documented text/values against each other — not only
confirming a token string appears somewhere in each document.

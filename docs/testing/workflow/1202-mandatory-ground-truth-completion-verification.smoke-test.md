# Smoke Test Runbook: Mandatory Ground-Truth Completion Verification

**Feature**: Mandatory Ground-Truth Completion Verification (#1202)
**Spec**: [`../../specs/developments/20260714164841_1202-mandatory-ground-truth-completion-verification/1_1202-mandatory-ground-truth-completion-verification_specs.md`](../../specs/developments/20260714164841_1202-mandatory-ground-truth-completion-verification/1_1202-mandatory-ground-truth-completion-verification_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch for #1202 is checked out.
- [ ] The new completion self-check helper exists and is executable.
- [ ] Protocols 90, 91, and 92 plus mirrored item-orchestrator and orchestrator
      guidance have been updated.
- [ ] `gh` is authenticated if testing against a real PR. Stubbed command
      fixtures are acceptable for the automated shell tests.
- [ ] The implementation PR test log includes the shell test command for the new
      helper and markdown lint for changed docs.

> This is a workflow/protocol feature. No application server, database seed, or
> browser session is required unless a completion report explicitly claims an
> external runtime was verified.

---

## Test Data

| Item | Value |
| --- | --- |
| PR-backed item fixture | A plan/spec/implementation PR with expected base branch, labels, changed files, reviewer-loop evidence, and green checks |
| No-PR item fixture | A workflow branch or local terminal state with no PR number |
| Parallel worktree fixture | A dedicated worktree path and `git worktree list` output showing that branch |
| Discrepancy fixture | A PR or stubbed PR response with wrong base branch, missing label, unexpected file, dirty workspace, failing CI, or unresolved review state |
| External claim fixture | A completion report claim for runtime/database/browser/deployment evidence, with and without observed evidence |

---

## Smoke Test Steps

### Step 1: PR-backed terminal report includes live evidence

**Maps to**: AC1, AC2, AC4, AC6, AC10

1. Run the completion self-check helper for a PR-backed item with the expected
   branch, worktree path, PR number, and base branch.
2. Inspect the emitted `Ground-Truth Completion Verification` section.

**Expected result**: The report includes verified evidence for current branch,
HEAD SHA, workspace/worktree path, PR number, PR base branch, draft/readiness
state, labels, changed-file summary, review evidence, and CI/check status. It
does not say that review, CI, readiness-label, tracker, or guardrail gates were
replaced by the self-check.

### Step 2: No-PR terminal report marks PR fields not applicable

**Maps to**: AC3, AC6

1. Run the helper for an item state that has no PR.
2. Include current branch and worktree/workspace path.

**Expected result**: The report verifies branch, HEAD SHA, workspace/worktree
path, and tracker status when available. PR number, base branch, labels,
changed files, and CI fields are marked `not_applicable` with a short rationale.

### Step 3: Parallel worktree evidence is visible

**Maps to**: AC2, AC7

1. Run the helper from a dedicated worktree path.
2. Include the assigned worktree path in the invocation.
3. Inspect the worktree evidence in the output.

**Expected result**: The report shows the assigned worktree path, current branch,
current HEAD, and `git worktree list` evidence sufficient for a parent
orchestrator to detect wrong-worktree or duplicate-worktree execution.

### Step 4: Discrepancy blocks success

**Maps to**: AC5, AC9

1. Run the helper against a fixture where one expected value is wrong, such as an
   unexpected PR base branch, missing `ready-for-human-review` label, unexpected
   changed file, dirty workspace, failing CI, unresolved review state, or
   unavailable required surface.
2. Inspect the exit code and report body.

**Expected result**: The helper exits non-zero, marks the affected surface as
`discrepancy` or `unavailable`, prints expected and observed values, and does
not claim the item is successful, ready, done, blocked, escalated, or waiting on
a human without naming the failed evidence.

### Step 5: External runtime claims require observed evidence

**Maps to**: AC8

1. Add an external-runtime, database, browser, deployment, or environment claim
   to the completion report.
2. Repeat once with direct observed evidence and once without it.

**Expected result**: The claim with evidence is marked `verified` and includes
the observed result. The claim without evidence is marked not verified or
unavailable with a reason; it is not silently treated as successful.

### Step 6: Batch summary consumes item evidence

**Maps to**: AC1, AC4, AC6, AC7, AC10

1. Follow Protocol 90 final-summary instructions for a bounded batch that
   includes the item under test.
2. Confirm the parent summary references the item self-check evidence and still
   performs Protocol 90 Step 5.1 direct PR verification.

**Expected result**: The batch summary is grounded in item self-check evidence
and direct artifact queries. It does not rely solely on subagent status text or
prior command output.

---

## Assertions Checklist

- [ ] AC1: A self-check is required before Work Item Runner terminal reports.
- [ ] AC2: PR-backed reports include raw/verbatim branch, HEAD, worktree, PR,
      label, changed-file, and CI/check evidence.
- [ ] AC3: No-PR reports include repository/tracker evidence and PR
      not-applicable rationale.
- [ ] AC4: PR readiness claims are verified from live PR/check surfaces.
- [ ] AC5: Discrepancies block successful completion claims.
- [ ] AC6: Every checked surface is verified, not applicable, or unavailable.
- [ ] AC7: Parallel batch reports include worktree evidence.
- [ ] AC8: External-runtime claims include direct observed evidence or are
      explicitly not verified.
- [ ] AC9: The mismatch scenario reports a discrepancy instead of success.
- [ ] AC10: Existing review, CI, readiness-label, tracker, guardrails, and merge
      gates remain in force.

---

## Seed Data Reference

No application seed data is required.

| Entity | Scenario | How to load |
| --- | --- | --- |
| Stub command fixtures | Shell tests for `git`, `gh`, GraphQL, tracker, and external claim output | Created by `scripts/development-workflow/tests/test-item-completion-self-check.sh` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Helper says tracker evidence is unavailable | The configured tracker provider cannot be read from the current runner context | Confirm the report names the provider limitation and does not mark the field verified |
| PR evidence is missing | `gh` is not authenticated or no PR number was supplied | Authenticate `gh`, supply `--pr`, or verify the fields are marked `not_applicable` for no-PR states |
| Worktree path does not match | The helper was run from the main checkout or wrong worktree | Re-run from the assigned worktree and confirm `git worktree list` includes the branch |
| CI status appears stale | The PR has pending or recently triggered checks | Re-run the existing CI loop and repeat the completion self-check after checks settle |

---

## Known Limitations

- The smoke test validates workflow behavior and helper output. It does not
  require a live downstream product application.
- Providers without CLI-accessible tracker reads may legitimately report tracker
  evidence as unavailable with rationale.


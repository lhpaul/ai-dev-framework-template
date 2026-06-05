# Smoke Test Runbook: Reviewer-Failed Label

**Feature**: Reviewer-failed PR label for automated reviewer platform failures
**Spec**: [1_reviewer-failed-label_specs.md](../../specs/developments/20260602154734_reviewer-failed-label/1_reviewer-failed-label_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] A test PR exists in the repository.
- [ ] `pr-review-loop.sh` can be run locally with `gh` authenticated.
- [ ] The test PR can safely receive and remove labels.

---

## Test Data

| Item | Value |
| --- | --- |
| Test PR | Any non-production PR used for reviewer-loop validation |
| Failure label | `reviewer-failed` |

---

## Smoke Test Steps

### Step 1: Simulate Platform Failure

**Maps to**: AC-1, AC-5

1. Run the reviewer-loop test harness or a controlled local loop scenario where one platform returns `RESULT=escalate` or `RESULT=skipped` with `REASON=unavailable`.
2. Inspect the PR labels.

**Expected result**: The repository label `reviewer-failed` exists and is present on the PR.

### Step 2: Simulate Haystack Pending Timeout

**Maps to**: Additional Haystack acceptance criteria

1. Run the Haystack reviewer path with a timeout budget short enough to produce `REASON=pending_timeout`, or use the unit harness case that simulates this result.
2. Inspect the PR labels.

**Expected result**: The PR has the `reviewer-failed` label and the reviewer-loop summary shows the Haystack pending-timeout reason.

### Step 3: Verify Not-Configured Does Not Apply Label

**Maps to**: AC-3

1. Run a loop or unit harness case where the only skipped platform reason is `not_configured`.
2. Inspect the PR labels.

**Expected result**: `reviewer-failed` is not applied. If it was already present from a prior failure, it is removed.

### Step 4: Verify Self-Heal On Healthy Run

**Maps to**: AC-2

1. Start with a PR that has `reviewer-failed`.
2. Run the reviewer loop with no platform-health failures. Healthy `clean`, `needs_fixes`, or `needs_rerun` outputs are acceptable for this check.
3. Inspect the PR labels.

**Expected result**: `reviewer-failed` is removed.

### Step 5: Verify Label Coexistence

**Maps to**: AC-4

1. Apply `ready-for-human-review` to the test PR.
2. Trigger a platform-failure loop result.
3. Inspect the PR labels.

**Expected result**: Both `ready-for-human-review` and `reviewer-failed` can be present; the reviewer-failed sync does not remove readiness labels.

---

## Assertions Checklist

- [ ] Platform `escalate` applies `reviewer-failed`.
- [ ] Platform `skipped/unavailable` applies `reviewer-failed`.
- [ ] Haystack `pending_timeout` applies `reviewer-failed`.
- [ ] `skipped/not_configured` does not apply `reviewer-failed`.
- [ ] Later healthy loop runs remove stale `reviewer-failed`.
- [ ] Label creation is idempotent and non-blocking.
- [ ] `reviewer-failed` can coexist with `ready-for-human-review`.

---

## Seed Data Reference

No seed data is required.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Label is not applied on `skipped/unavailable`. | Logic used only aggregate result, which normalized skipped to clean. | Track per-platform failure state before aggregate normalization. |
| Label is applied for `not_configured`. | Reason classification is too broad. | Add or fix the explicit `not_configured` negative case. |
| Reviewer loop exits non-zero only because label creation failed. | Label sync is not best-effort. | Make label creation/add/remove warn and continue. |

---

## Known Limitations

- The label is an aggregate reviewer-health signal; it does not identify the failed platform without reading the reviewer-loop summary.

# Paired release merge sessions — Smoke Test Runbook

## Preconditions

- Run from the repository root with Python 3, Bash, Git and jq available.
- Use the committed workflow harnesses and isolated temporary repositories.
- No production release, branch deletion or real tracker mutation is part of this smoke test.

## Test Data

The journal test factories and fake GitHub state create a production PR, backport
PR, shared release head, version tag, publication and scoped issue/provider states.
See the implementation plan's Seed Data section for their ownership.

## Smoke Test Steps

### Step 1: Admission and identity

Run `bash scripts/development-workflow/tests/test-workflow-merge-budget.sh`.
Confirm valid-pair admission and refusal for unavailable quota, unaffordable complete
scope, malformed identities and changed release scope. Added shipped duties must
increase projection; refused admission must submit neither merge nor audit.

**Maps to**: AC2, AC3.

### Step 2: Merge ordering and publication

In that suite, confirm the backport is denied before independently verified
production regular merge and matching tag/published non-draft Release. Confirm
shared cleanup remains denied until both regular merges verify, then the full
valid operation completes while honoring declared retention policy.

**Maps to**: AC1, AC4.

### Step 3: Recovery and Waiting

Confirm interrupted journal cases after production merge, during publication,
after backport and during cleanup resume only verified outstanding work. Confirm
completed/submitted merges are never submitted again; offline reports retain
historical facts and pending work; queue submissions stop subsequent merges.

**Maps to**: AC5, AC6.

### Step 4: Cleanup and provider evidence

Run `bash scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh`.
Confirm session binding/scope validation, each stamp and tracker read-back, marker
finalization and partial-failure recovery. Confirm existing component and Linear
routes retain their ownership checks and do not count deferred work as Completed.

**Maps to**: AC7, AC9.

### Step 5: Ordinary sequencing regression

Confirm the journal suite refuses the next ordinary implementation merge while
the preceding cleanup or tracker duty remains incomplete. A release-like branch
without explicit validated pairing must not gain the exception.

**Maps to**: AC8.

## Assertions Checklist

- [ ] Both merges and authorized shared cleanup finish in the required order.
- [ ] Admission accounts for finalized shipped duties and refuses unsafe input.
- [ ] Publication and both-merge checks fail closed.
- [ ] Recovery preserves facts and avoids duplicate submissions.
- [ ] Every owning release duty independently verifies before Completed.
- [ ] Ordinary sequencing and existing provider routing remain intact.

## Known Limitations

The suites simulate GitHub and tracker boundaries; they do not publish a live
release. Current-head PR CI and review validate the delivered change separately.

# Smoke Test Runbook: Access-Restricted Reviewer Checks at the Merge Gate

**Feature**: Access-restricted reviewer checks at the merge gate
**Spec**:
[Access-restricted reviewer checks spec](../../specs/developments/20260723112258_access-restricted-reviewer-checks/1_access-restricted-reviewer-checks_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] Use the implementation branch for issue #1288.
- [ ] `jq`, `gh`, Bash, and the repository workflow test dependencies are
      available.
- [ ] Test scripts use mocked `gh` for comment and merge commands; no test
      targets a production pull request.
- [ ] The implementation PR's current head SHA is known.
- [ ] The implementation-stage security checkpoint is visible as pending until
      a human reviews the security-sensitive implementation approach.

---

## Test Data

| Item | Value |
| --- | --- |
| Eligible pull request | `#42`, head `abc123`, current green CI |
| Configured reviewer check | `Haystack / Review`, non-green |
| Verified denial | Haystack `REASON=forbidden` / provider HTTP 403 evidence |
| Clean reviewer disposition | Current head, zero blocking findings |
| Stale authorization | PR `#42`, old head `abc122` or old evidence fingerprint |
| Genuine CI failure | `Unit Tests` conclusion `FAILURE` |
| Genuine review failure | Reviewer blocking count `1` |
| Mock authorizer | `named-human` in fixture data only |

Fixtures may use different deterministic values if their meaning remains
equivalent.

---

## Smoke Test Steps

### Step 1: Verify structured reviewer-check evidence stays separate from CI

**Maps to**: AC-1, AC-2

1. Run the focused test covering `pr-ci-loop.sh` reviewer checks:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh
   ```

2. Inspect the fixture with green Unit Tests and a failing configured
   `Haystack / Review`.
3. Confirm CI result remains green and counts only genuine CI checks.
4. Confirm the additive structured reviewer-check field preserves name,
   state/conclusion, details URL when present, and current observation/head
   metadata.
5. Confirm a real failing Unit Tests check still returns red even when Haystack
   is access-restricted.

**Expected result**: Reviewer infrastructure evidence is available to the merge
gate without being collapsed into CI health.

### Step 2: Verify the access-restriction classification

**Maps to**: AC-1, AC-5

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-run-epic-delegated-gate.sh
   ```

2. Inspect the fixture with current green required CI, zero blocking findings,
   a non-green configured reviewer check, and `REASON=forbidden`.
3. Confirm the result classifies `access_restricted`, keeps normal
   `mergePermitted` false, and names repository/organization App-access
   remediation as the primary action.
4. Confirm the result includes the named PR, exact head SHA, required evidence,
   and a deterministic material-evidence fingerprint.

**Expected result**: A verified access restriction is reported separately and
does not become normal delegated merge approval.

### Step 3: Verify CI and review blockers take precedence

**Maps to**: AC-2, AC-3

1. In the delegated-gate test output, locate the fixture with a failing or
   incomplete required CI check plus the same denial evidence.
2. Confirm the outcome is `ci_blocker` / `fix_required`, with no admin option.
3. Locate the fixture with at least one blocking reviewer finding or unresolved
   blocking thread plus denial evidence.
4. Confirm the outcome is `review_blocker` / `fix_required`, with no admin
   option.
5. Confirm a second unrelated non-green reviewer check prevents the
   access-restricted check from being considered the sole blocker.

**Expected result**: Genuine CI or review failures can never be bypassed through
the access-restriction path.

### Step 4: Verify missing, stale, and contradictory evidence fails closed

**Maps to**: AC-4, AC-8

1. Inspect delegated-gate cases for:
   - non-green reviewer check without verified access-denial evidence;
   - denial evidence for an older head;
   - clean reviewer status with a positive blocking count;
   - unknown/malformed check state;
   - authorization for another PR, SHA, or material-evidence fingerprint.
2. Confirm each case returns `insufficient_evidence` or
   `authorization_stale`.
3. Confirm the next action requires evidence refresh/investigation and no admin
   merge is authorized.

**Expected result**: Exact current-revision evidence is required; the gate never
guesses.

### Step 5: Verify remediation remains primary

**Maps to**: AC-5, AC-11

1. Inspect
   `docs/workflow/development-workflow/integrations/haystack-triage.md`.
2. Confirm setup guidance separately verifies organization approval and
   repository App selection.
3. Confirm it states that local CLI installation/authentication does not prove
   GitHub App repository access.
4. Confirm it names an expected usable reviewer signal on a test PR and
   troubleshooting for HTTP 403 / `REASON=forbidden`.
5. Inspect Protocols 91, 94, and 95 and confirm verified restriction first
   recommends restoring access and rerunning the reviewer.

**Expected result**: The normal protected merge path is the preferred recovery.

### Step 6: Verify the human-only authorization boundary

**Maps to**: AC-6, AC-7, AC-10

1. Inspect the eligible-but-unauthorized gate fixture.
2. Confirm the fixture records that access remediation was attempted, cannot
   unblock in the required timeframe, and includes a non-empty bypass reason.
3. Confirm it presents the evidence fingerprint and exact proposed
   `gh pr merge <pr> --admin --match-head-commit <authorized-head-sha>` action
   but remains `human_required`.
4. Set only ordinary delegated/epic/batch merge policy fields in the fixture.
5. Confirm they do not change the result to exceptional authorization.
6. Supply a current named authorization fixture but omit the pre-attempt audit.
7. Confirm the result is `audit_required`, not authorized.
8. Confirm tests intercept mutating `gh` commands and that the delegated gate
   never calls `gh pr merge --admin`.

**Expected result**: Only a separate human authorization naming the current PR
and evidence can advance the exceptional path, and no gate helper performs the
privileged action.

### Step 7: Verify authorization freshness and one-attempt scope

**Maps to**: AC-8

1. Start from an eligible fixture with matching PR/SHA/fingerprint
   authorization and pre-attempt audit.
2. Confirm the gate returns `exceptional_bypass_authorized` for only that named
   action.
3. Change the head SHA and rerun; confirm authorization is stale.
4. Restore the SHA but change a material CI, reviewer, or blocked-check field;
   confirm fingerprint mismatch requires reauthorization.
5. Mark an attempted command as failed and confirm protocol/fixture guidance
   requires a new human decision before any retry.

**Expected result**: Authorization cannot survive revision/evidence changes or
silently authorize retries.

### Step 8: Verify two-phase audit ordering and content

**Maps to**: AC-9

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-run-epic-audit-trail.sh
   ```

2. Confirm `render-reviewer-access-bypass` /
   `apply-reviewer-access-bypass` rejects a record missing authorization, PR/SHA,
   fingerprint, CI state, reviewer disposition, blocked check, denial evidence,
   remediation/bypass reason, proposed action, or result state.
3. Confirm the pre-attempt record uses one stable marker and includes
   `authorized_pending_attempt`.
4. Confirm reruns update the same comment for `rejected`, `merged`, and `failed`
   rather than creating duplicates.
5. Confirm token-like strings and local paths are redacted.
6. Confirm a simulated comment API failure prevents exceptional authorization.

**Expected result**: The durable record exists before action and contains the
required final disposition afterward.

### Step 9: Verify single, batch, and epic protocol consistency

**Maps to**: AC-7, AC-10, AC-13

1. Search the implemented merge-gate surfaces:

   ```bash
   rg -n "access_restricted|exceptional_bypass_authorized|--admin" \
     docs/workflow/development-workflow/protocols \
     docs/workflow/development-workflow/guardrails-enforcement.md \
     .agents/skills .codex/skills .claude/agents .cursor/agents
   ```

2. Confirm single-item, explicit-batch, and epic paths use the same gate
   classifications and required next actions.
3. Confirm each says delegated/batch/epic authority does not substitute for the
   fresh named human authorization.
4. Confirm Protocol 94 limits the direct admin exception to the named affected
   PR, refreshes/discovers the base after it, and leaves unaffected PRs in the
   normal batch route.
5. Confirm canonical protocols, thin mirrors, operator output, and audit use
   the same field/outcome names.

**Expected result**: The spec decision matrix is consistent across every
changed workflow surface.

### Step 10: Verify the implementation-stage security checkpoint

**Maps to**: AC-12

1. Inspect the implementation plan and implementation PR handoff.
2. Confirm issue #1288 has one pending `implementation/security` checkpoint
   requiring human review of the security-sensitive implementation approach.
3. Confirm the plan-stage PR did not treat the future-stage checkpoint as
   currently blocking.
4. Confirm the implementation PR cannot pass delegated merge while that
   checkpoint remains pending.

**Expected result**: The checkpoint is preserved across stages and blocks only
when the implementation stage reaches its merge gate.

### Step 11: Run shell and documentation validation

**Maps to**: AC-1–AC-13

1. Run ShellCheck on every changed shell script.
2. Run:

   ```bash
   python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop
   ```

3. Run Markdown lint and heuristic lint for changed development/runbook/
   CHANGELOG surfaces.
4. Run the full relevant workflow shell test suite or CI entrypoint.
5. Confirm no test or helper executed a real mutating `gh` command.

**Expected result**: Focused and regression validation pass with no unguarded
shell mutation or documentation inconsistency.

### Last Step: Validate and Shut Down

- Verify all assertions below are checked.
- Remove only temporary local fixtures created by the test scripts.
- Do not execute a real admin merge as part of this smoke runbook.

---

## Assertions Checklist

- [ ] Access restriction is distinct from CI/review failure (AC-1).
- [ ] Failing/incomplete CI blocks and hides the bypass option (AC-2).
- [ ] Blocking reviewer findings/threads block and hide the bypass option
      (AC-3).
- [ ] Missing/stale/contradictory evidence fails closed (AC-4).
- [ ] App-access remediation is the primary action (AC-5).
- [ ] Eligible output shows exact evidence and named admin action without
      executing it (AC-6).
- [ ] No named human authorization means no admin bypass (AC-7).
- [ ] PR revision/material evidence changes invalidate authorization (AC-8).
- [ ] Audit is present before attempt and updated after disposition (AC-9).
- [ ] Delegated/batch/epic authority cannot substitute for authorization
      (AC-10).
- [ ] Haystack guidance includes organization/repository App preflight
      (AC-11).
- [ ] Implementation security checkpoint remains pending until reviewed
      (AC-12).
- [ ] Decision matrix is consistent across all mirror surfaces (AC-13).

---

## Test Data Reference

| Entity | Scenario | How to load |
| --- | --- | --- |
| Delegated-gate fixtures | Eligible, blocker, stale, contradictory, authorized | Created by `test-run-epic-delegated-gate.sh` |
| CI rollup fixtures | Green CI plus failing reviewer; real CI failure | Created by `test-workflow-orchestration-product-repo-aware.sh` |
| Audit fixtures | Pre-attempt, rejected, merged, failed | Created by `test-run-epic-audit-trail.sh` |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Access fixture reports insufficient evidence | Missing/current-head mismatch in reviewer or denial fields | Inspect fixture SHA and required typed denial source |
| CI fixture reports red unexpectedly | Configured reviewer check name did not match | Check `.ai-dev-workflow.yaml` / `HAYSTACK_CHECK_NAME` fixture |
| Authorization fixture is stale | SHA or material-evidence fingerprint changed | Regenerate evidence and use a fresh authorization fixture |
| Audit apply test fails | Mock comment mode or required field is missing | Inspect helper stderr and fixture completeness |
| Workflow shell guard fails | New shell code violates guarded command/parsing rules | Fix the reported line; do not suppress blindly |

---

## Known Limitations

- The smoke runbook intentionally does not execute a real branch-protection
  bypass. Mocked command interception and live read-only evidence validate the
  boundary without mutating a production repository.
- Organization approval and repository App selection remain administrator
  actions outside this workflow.
- The feature recognizes verified provider access denial; it does not
  generalize every reviewer outage into an access restriction.

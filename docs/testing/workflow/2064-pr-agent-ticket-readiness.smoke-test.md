# Smoke Test Runbook: PR-Agent ticket readiness

**Feature**: #2064
**Spec**: [Merged approved spec f62b494c](https://github.com/lhpaul/ai-dev-framework-template/blob/f62b494c54abca0d57cd3528e7d18fdf4bd3b6f5/docs/specs/developments/20261028174727_2064-pr-agent-ticket-readiness/1_2064-pr-agent-ticket-readiness_specs.md)
**Created in**: Plan Ready stage
**Updated in**: Implementation must record actual execution revision/results.

## Prerequisites

- Use a disposable synthetic repository and mocked GitHub/peer-reviewer responses
  through existing workflow test drivers; no remote writes or billed reviewers.
- Use the implementation revision containing #2064 and unchanged normal reviewer
  scheduling. Do not force expensive reviewers or disable readiness gates.
- No real project/private configuration is a fixture. Seed only fabricated TOML
  values and fake head/comment identities. No graphical baseline was supplied.

## Test Data

| Class | Synthetic values / location |
| --- | --- |
| Review | Existing PR-Agent table/Markdown fixture builders with populated ticket requirements; fake epic/context issue references. |
| Head and proof | Head-bound mocked summary; valid ticket-only verification with no matching ticket proof. |
| Independent blockers | Code Must Fix, outside verification, unavailable/malformed evidence, security and human blocker variants. |
| Consumer TOML | Absent key/file, true, false, malformed and unreadable fixtures; sentinel credentials used only to prove non-disclosure. |

## Smoke Test Steps

### Step 1: Normal downstream reviewer progression

**Maps to**: AC1–AC2.

1. Seed an existing downstream TOML with ticket analysis enabled or unspecified.
2. Produce a current-head, structurally valid PR-Agent ticket analysis for fully,
   partially and non-compliant cases, plus PR Code Verified with ticket-only
   verification lacking matched proof. Keep code reviewers and CI clean.
3. Exercise actual loop classification, configured peer-reviewer dispatch and
   readiness CLI through the existing mocked drivers.

**Expected result**: Every case follows normal reviewer progression and reaches
readiness after all other gates pass. No forced-reviewer override or TOML edit
is needed. Ticket commentary remains visible; no epic completion is asserted.

### Step 2: Preserve independent refusal

**Maps to**: AC3–AC4.

1. Replace the ticket body with malformed, duplicate, unknown-status, empty or
   truncated analysis and run the same classifier/loop path.
2. Restore a valid informational ticket section; add each independent blocker
   from Test Data and run classifier plus readiness.
3. Include independent verification alongside code findings to check precedence.

**Expected result**: Malformed output escalates. Each independent blocker keeps
its existing blocking, pending or escalation result; readiness is refused.
Escalation wins over needs-fixes when both apply. No ticket exception grants
proof, resolves threads or clears human checkpoints.

### Step 3: Ordinary sync diagnostic

**Maps to**: AC5.

1. Run ordinary `sync-template-merge.py preview` through the existing disposable
   sync fixture driver, selecting the synthetic consumer root explicitly.
2. Exercise enabled/absent, boolean false, malformed, unreadable and parser-
   unavailable cases. Inspect static messages and resulting sync exit status.
3. Compare consumer TOML bytes before and after preview and permitted synthetic
   apply. Check reports and plan artifacts for fabricated secret sentinels.

**Expected result**: Only explicit boolean false suppresses the ticket-setting
warning. Other cases name the setting or repair action safely; sync's existing
blocked/error behavior remains. No configuration overwrite or secret echo occurs.

### Step 4: Documentation and residual scope

**Maps to**: AC6.

1. Cross-check the configuration comment, integration guide and sync procedure
   mirror against implementation and approved spec matrix.
2. Confirm changelog fragment format and rerun plan Verification Log consumer
   queries against the implementation revision.
3. Record any additional consumer/surface and its demonstrated outcome; retain
   fixture file/line plus before/after proof in the implementation review.

**Expected result**: Guidance agrees with behavior; no unaccounted-for consumer
or stale ticket-only blocking assertion remains.

### Last Step: Record results and clean up

Record PASS/FAIL, implementation SHA, exact commands, tested fixture identities
and expected/actual discrepancy for every failure. Remove only disposable test
fixtures using their existing teardown. Preserve owned workflow worktrees and
branches. No merge or tracker update belongs to this runbook.

## Assertions Checklist

- [ ] AC1: Clean ticket-only cases progress through peers and readiness.
- [ ] AC2: Valid fully compliant, partially compliant, non-compliant and
  ticket-only human-verification cases classify as clean, including ticket-only
  requests without matching verified proof, when the remaining review is clean.
- [ ] AC3: Malformed/unknown ticket output still escalates.
- [ ] AC4: Outside evidence, code, security and human blockers retain refusal.
- [ ] AC5: Sync warns safely and preserves project-owned TOML.
- [ ] AC6: Configuration guidance, synchronized docs and fragment agree.

## Troubleshooting

| Symptom | Check / response |
| --- | --- |
| Classifier clean but loop pending | Inspect shared inspection flags and proof branch in the synthetic case; preserve independent evidence refusals. |
| TOML warning absent | Confirm selected synthetic consumer root and boolean type; quoted false is not boolean false. |
| Readiness refuses a clean synthetic case | Inspect the independent configured reviewer/CI/head/checkpoint gate; do not bypass it. |

## Known Limitations

Synthetic smoke proves workflow composition without running external models.
It does not certify an epic's requirements or mutate a live downstream project.

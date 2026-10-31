# Smoke Test Runbook: PR-Agent ticket readiness

**Feature**: #2064
**Spec**: [Merged approved spec f62b494c](https://github.com/lhpaul/ai-dev-framework-template/blob/f62b494c54abca0d57cd3528e7d18fdf4bd3b6f5/docs/specs/developments/20261028174727_2064-pr-agent-ticket-readiness/1_2064-pr-agent-ticket-readiness_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development; actual synthetic execution recorded below.

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

## Historical Execution Record — 2026-10-29 UTC

**Tested checkpoint**: `82f50ee931a26cab542ac0f6b8c482328f073985`.
The following required readiness suites ran serially with all scripts, tests and
goldens frozen at this checkpoint. This record is a later documentation-only
change; it does not claim live reviewer, CI or merge readiness.

| Exact command | Actual result |
| --- | --- |
| `bash scripts/development-workflow/tests/test-apply-readiness-labels.sh` | 410 passed, 0 failed |
| `bash scripts/development-workflow/tests/test-readiness-label-matrix-part-1.sh` | 503 passed, 0 failed |
| `bash scripts/development-workflow/tests/test-readiness-label-matrix-part-2.sh` | 476 passed, 0 failed |
| `bash scripts/development-workflow/tests/test-readiness-label-matrix-part-3.sh` | 499 passed, 0 failed |
| `bash scripts/development-workflow/tests/test-readiness-label-matrix-part-4.sh` | 483 passed, 0 failed |
| `bash scripts/development-workflow/tests/test-consumer-readiness-matrix-part-1.sh` | 503 passed, 0 failed |
| `bash scripts/development-workflow/tests/test-consumer-readiness-matrix-part-2.sh` | 476 passed, 0 failed |
| `bash scripts/development-workflow/tests/test-consumer-readiness-matrix-part-3.sh` | 499 passed, 0 failed |
| `bash scripts/development-workflow/tests/test-consumer-readiness-matrix-part-4.sh` | 483 passed, 0 failed |

**Step 1 / AC1**: PASS. The actual bound PR-Agent handler/processor permits the
normal configured peer pre-dispatch without a force override; standalone and
consumer readiness fixtures permit the clean ticket-only case. The missing-ledger
case asserts absence before invocation, clears the prior result and verifies a
fresh issue-comment read before checking the actual readiness result.

**Separate AC2 check**: PASS. Full, partial, non-compliant and PR Code Verified
cases exercise informational classification, including ticket-only verification
without matching proof. The existing acquisition suite ran with
`bash scripts/development-workflow/tests/test-pr-review-loop-pr-agent-coderabbit.sh --area 1946`
and reported 1230 passed, 0 failed. That earlier run overlapped focused prefix
hardening edits; it is supplemental rather than an immutable-checkpoint proof.
The final prefix behavior was separately verified by
`python3 scripts/development-workflow/tests/test-review-evidence-context.py`
(11 tests OK); scripts exercised by the serial table above include that behavior.

**Step 2 / AC3–AC4**: PASS. Malformed/unknown ticket analyses and independent code,
verification, security, evidence and human refusal controls remain exercised in
the serial suites. The scoped missing-ledger correction was also checked through
the existing mocked readiness driver: 11 focused assertions passed, including
outside verification and security refusals.

**Step 3 / AC5**: PASS. `python3 scripts/development-workflow/tests/test_sync_template_merge.py`
reported 28 tests OK. Subsequent platform/parser-limit diagnostic hardening was
checked with
`python3 scripts/development-workflow/tests/test_sync_template_merge.py SyncTests.test_ticket_setting_semantics_and_safe_diagnostics SyncTests.test_ticket_warning_is_delivered_by_normal_preview_without_plan_leak`
(2 tests OK). Those diagnostic sources are unchanged at the tested checkpoint.
Enabled/absent settings warn, boolean false suppresses the warning, invalid or
unreadable settings receive safe advice, and configuration bytes and sentinel
non-disclosure controls pass. No live downstream configuration was inspected.

**Step 4 / AC6**: PASS. Configuration comment, integration guide, canonical Claude
command, full Claude skill procedure, Cursor procedure and release fragment were
cross-checked; delegating Codex wrappers require no duplicated policy. Final
tracked-file consumer/mirror queries found no unaccounted scoped consumer or
procedure mirror. Markdownlint and heuristic checks were clean before this
execution-record update and are repeated for this documentation-only change.

Earlier runs with helper edits in flight produced transient empty-output
failures and stale expected-policy assertions; those results were retained and
were superseded by the complete serial frozen-checkpoint execution above. No
unrelated production logic or expectations were changed to clear those failures.
Disposable fixture teardown completed; owned branches/worktrees were retained.

## Final Allowlist Execution Record — 2026-10-29 UTC

**Updated in**: documentation-only follow-up to tested checkpoint
`ea6703aac525041da3f063728086ac64d013e6e5`.
**Outcome**: PASS for local synthetic verification; remote review, CI and merge
readiness remain separate parent-owned gates. The historical record above does
not certify this later parser revision.

The final policy consumes the complete ticket slice: recognized status and
analysis scaffold plus complete requirement bullets. Allowed inline HTML is
balanced, attribute-free `em`, `strong`, `b` and `span`. Known heading presentation
may use `<br>` before the first ticket. HTML breaks inside or after a requirement,
unknown markup, unconsumed text and independent control headings (including list
or numbered prefixes) fail closed. This deliberately hardens earlier permissive
embedded-break controls under Luis's latest authorization; ticket-only
“Requires further human verification” remains informational without ticket proof.

**AC1–AC4**: PASS. The following exact commands ran serially with sources and
goldens frozen at the tested checkpoint:

| Exact command | Actual result |
| --- | --- |
| `python3 scripts/development-workflow/tests/test-review-evidence-context.py` | 14 tests OK |
| `bash scripts/development-workflow/tests/test-apply-readiness-labels.sh` | 410 passed, 0 failed |
| `bash scripts/development-workflow/tests/test-readiness-label-matrix-part-1.sh` | 503 passed, 0 failed |
| `bash scripts/development-workflow/tests/test-readiness-label-matrix-part-2.sh` | 476 passed, 0 failed |
| `bash scripts/development-workflow/tests/test-readiness-label-matrix-part-3.sh` | 499 passed, 0 failed |
| `bash scripts/development-workflow/tests/test-readiness-label-matrix-part-4.sh` | 483 passed, 0 failed |
| `bash scripts/development-workflow/tests/test-consumer-readiness-matrix-part-1.sh` | 503 passed, 0 failed |
| `bash scripts/development-workflow/tests/test-consumer-readiness-matrix-part-2.sh` | 476 passed, 0 failed |
| `bash scripts/development-workflow/tests/test-consumer-readiness-matrix-part-3.sh` | 499 passed, 0 failed |
| `bash scripts/development-workflow/tests/test-consumer-readiness-matrix-part-4.sh` | 483 passed, 0 failed |
| `python3 scripts/development-workflow/tests/test_pr_agent_runtime.py` | 56 tests OK, 8 skipped |

Separate AC2 controls include full/partial/non-compliance, PR Code Verified and
missing ticket proof. AC4 regressions cover same-line HTML headings, empty blocks
and rendered separators, list/number verification and security headings, unknown
markup and independent outside-section controls. Synthetic before/after fixtures
show the formerly clean `<br>`/empty-`p` plus list/number pending-verification
variants now escalate; known inline formatting and heading scaffold stay clean.

**AC5**: PASS. The sync implementation is unchanged by the allowlist repair.
The earlier sync suite passed 28 tests. Its synthetic consumer filename now uses
the checker's existing fixture-data mapping contract; manifest coverage passed
56 assertions. This repairs a fixture-path false positive without changing the
checker, manifest, repository configuration or any genuine read dependency.

**AC6**: PASS. Tracked runtime consumers and all three full sync procedures were
accounted for; thin Codex wrappers retain delegation. No scoped residual is
deferred. Final documentation lints and partition inventory are recorded in the
local author handoff. All fixture/process teardown completed; no remote writes
or implementation merge were performed by this implementer.

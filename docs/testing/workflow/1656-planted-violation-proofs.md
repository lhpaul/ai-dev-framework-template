# Planted-Violation Proofs: Second Local Pass (#1656)

**Item**: [#1656](https://github.com/lhpaul/ai-dev-framework-template/issues/1656)

**Restored harness** (all rows below must pass):

<!-- workflow-shell-contract: bash -->

```bash
bash scripts/development-workflow/tests/test-pr-review-loop.sh --area 1656
```

**Demonstrated output** (2026-09-01, current PR head):

```text
PASS: 1656_s8c_failed_head_count
PASS: 1656_s8c_guard_refuse
PASS: 1656_s8c_guard_no_dispatch
PASS: 1656_s8c_guard_escalate
PASS: 1656_s8c_guard_failed_reason
PASS: 1656_s8c_phase_not_started
PASS: 1656_pv_P2_plant
PASS: 1656_pv_P2_correct
PASS: 1656_pv_P2_plant_differs
PASS: 1656_s5_no_evidence
PASS: 1656_s9_dispatch_cycle_count
PASS: 1656_s10_refuse_cycle_count
PASS: 1656_s10_refuse_lifetime_count
PASS: 1656_s7_phase_not_started
PASS: 1656_s7a_phase_not_started
PASS: 1656_s7b_phase_not_started
PASS: 1656_s7c_phase_not_started
PASS: 1656_s7d_phase_not_started
PASS: 1656_s8d_phase_not_started
PASS: 1656_s3a_phase_not_started
PASS: 1656_s3c_phase_not_started
PASS: 1656_s3d_phase_not_started
PASS: 1656_s13_guard_noop
PASS: 1656_s13_guard_no_dispatch
PASS: 1656_s4_guard_proceed
PASS: 1656_s4_guard_no_dispatch
PASS: 1656_s4a_not_required_head_moved
PASS: 1656_s4b_not_required_unread_head
PASS: 1656_s4c_no_local_head_moved
PASS: 1656_s5b_output_head_current
PASS: 1656_s5a_extraction_byte_identical
PASS: 1656_s5a_no_second_pass_keys
PASS: 1656_s5a_platform_result
PASS: 1656_pv_P10_plant
PASS: 1656_pv_P10_correct
PASS: 1656_pv_P10_plant_differs
PASS: 1656_s6_no_local_reviewer
PASS: 1656_s2b_repo_configured
PASS: 1656_s2c_local_ai_configured
PASS: 1656_s3a_guard_blocked
PASS: 1656_s3d_guard_unavailable
PASS: 1656_s3c_guard_no_reviewed_head
PASS: 1656_s3a_aggregate_reason
PASS: 1656_s3a_guard_reason
PASS: 1656_s7a_guard_unavailable
PASS: 1656_s7b_guard_unavailable
PASS: 1656_s7d_guard_unavailable
PASS: 1656_s7c_guard_telemetry
PASS: 1656_s3d_no_failed_head_record
```

Line numbers refer to `scripts/development-workflow/pr-review-loop.sh` at this
proofs commit (production citations verified after the
`LOCAL_SECOND_PASS_REASON` help-text insert; this file does not shift those
lines). Test-path line numbers refer to
`scripts/development-workflow/tests/test-pr-review-loop.sh`.

Recorded fail-under-plant on 2026-09-01 against that restored harness
(`bash scripts/development-workflow/tests/test-pr-review-loop.sh --area 1656`).
Each plant was applied to production, the area-1656 run captured, then the
file was restored. A proof whose plant cannot change a test's answer is not
included here as a recorded fail.

## P1 — per-head dispatch cap (loop/cost)

- **Production**: `:8454` (`local_second_pass_failed_head_record="$loop_head_sha"`); refusal at `:8404-8412`
- **Plant**: `:8454` → `local_second_pass_failed_head_record=""`
- **Fail run**: `FAIL: 1656_s7_guard_failed_head — expected 'ffffffffffffffffffffffffffffffffffffffff', got ''`
- **Pass restored**: `PASS: 1656_s7_guard_failed_head`, `PASS: 1656_s8c_guard_refuse`

## P2 — silent history must not read as satisfied (fail-open)

- **Production**: `:8302` (`not_yet_run|unknown) printf 'no_evidence'`)
- **Plant**: `:8302` → `printf 'not_required'`
- **Fail run**: `FAIL: 1656_s5_no_evidence — expected 'no_evidence', got 'not_required'`; `FAIL: 1656_pv_P2_correct — expected 'no_evidence', got 'not_required'`; `FAIL: 1656_pv_P2_plant_differs — expected 'different', got 'same'`
- **Pass restored**: `PASS: 1656_s5_no_evidence`, `PASS: 1656_pv_P2_correct`, `PASS: 1656_pv_P2_plant_differs`

## P3 — pass must not increment caps (loop/cost)

- **Production**: `:8415-8468` (guard dispatch and refusal; no `cycle_count` / `lifetime_cycle_count` mutation)
- **Plant**: add `cycle_count=$((cycle_count + 1))` at `:8415`
- **Fail when planted**: `1656_s9_dispatch_cycle_count` (`:18102`) reads `3` instead of `2`
- **Pass restored**: `1656_s9_dispatch_cycle_count`, `1656_s10_refuse_cycle_count`

## P4 — ready gate after pass result (fail-open)

- **Production**: `:11792` (`reviewer_loop_second_local_pass_before_ready_gate` before ready transition)
- **Plant**: call `ensure_pr_ready_for_ready_phase` before `:8448-8468` gate handling
- **Fail when planted**: `1656_s7_phase_not_started` (`:18031`) would read `1`
- **Pass restored**: all `1656_s7*_phase_not_started` assert `0`

## P5 — no ready-phase → no guard (loop/cost)

- **Production**: `:8375-8376` (`phase_after_clean_enabled` early `return 0`)
- **Plant**: delete `:8375-8377`
- **Fail when planted**: `1656_s13_guard_no_dispatch` (`:18129`) reads `>0`
- **Pass restored**: `1656_s13_guard_noop`, `1656_s13_guard_no_dispatch`

## P6 — failed pass must refuse, not suppress only (fail-open)

- **Production**: `:8404-8412` (`failed_for_head` escalate refusal without dispatch)
- **Plant**: set `local_second_pass=0` at `:8405` without `:8407-8412` aggregate refusal
- **Fail when planted**: `1656_s8c_guard_escalate` (`:17997`) does not read `escalate`
- **Pass restored**: `1656_s8c_guard_refuse`, `1656_s8c_guard_escalate`, `1656_s8c_guard_failed_reason`

## P7 — compose current round before selector (fail-open)

- **Production**: `:8383` (`reviewer_loop_compose_current_round_payload`) feeding `:8384`
- **Plant**: pass `_sl_prior_payload` directly to `:8384` (drop `:8383`)
- **Fail when planted**: `1656_s4_guard_no_dispatch` (`:17960`) reads `>0`
- **Pass restored**: `1656_s4_guard_proceed`, `1656_s4_guard_no_dispatch`, `1656_s5b_output_head_current`

## P8 — shared processor extraction (integration)

- **Production**: `:8475-8671` (`reviewer_loop_process_platform_output`)
- **Plant**: inline duplicate parser omitting `PLATFORM_*` keys
- **Fail when planted**: `1656_s5a_extraction_byte_identical` (`:17775`) diverges
- **Pass restored**: `1656_s5a_extraction_byte_identical`, `1656_s5a_no_second_pass_keys`, `1656_s5a_platform_result`

## P9 — failed head in ledger, not shell (integration)

- **Production**: `:8454` (`local_second_pass_failed_head_record="$loop_head_sha"`) read back at `:8404`
- **Plant**: in-memory flag instead of `:8454` ledger write
- **Fail when planted**: `1656_s8c_guard_no_dispatch` fails on second invocation
- **Pass restored**: `1656_s8c_guard_refuse`, `1656_s8c_failed_head_count` (`:17726-17727`)

## P10 — `not_configured` ≠ `no_evidence` (fail-open)

- **Production**: `:8291-8293` (repo-config pre-check → `no_local_reviewer`)
- **Plant**: `test-pr-review-loop.sh:17813-17824` (`_1656_pv_plant_p10_pass_required`)
- **Fail when planted**: `1656_pv_P10_plant_differs` (`:17837-17839`); plant returns `no_evidence` (`:17835-17836`)
- **Pass restored**: `1656_pv_P10_correct`, `1656_s6_no_local_reviewer` (`:17837-17838`, `:17684`)

## P11 — repo configured list, not invocation filter (fail-open)

- **Production**: `:8382` (`reviewer_loop_repo_configured_platforms`) passed to `:8384`
- **Plant**: pass invocation `platforms[]` to `:8384` instead of `:8382` output
- **Fail when planted**: `1656_s2b_repo_configured` (`:17741-17742`) reads `no_local_reviewer`
- **Pass restored**: `1656_s2b_repo_configured`, `1656_s2c_local_ai_configured`

## P12 — failed pass refusal is `escalate` (loop/cost)

- **Production**: `:8407-8408` (`aggregate_result=escalate`, `aggregate_reason=failed_for_head`)
- **Plant**: map `:8404-8412` refusal to `needs_fixes`
- **Fail when planted**: lifetime/per-run caps stall (`1656_s10_refuse_*`)
- **Pass restored**: `1656_s8c_guard_escalate`, `1656_s10_refuse_cycle_count`, `1656_s10_refuse_lifetime_count`

## P13 — head re-read before every proceed path (fail-open)

- **Production**: `:8334-8360` (`reviewer_loop_second_local_pass_confirm_live_head`); called for `not_required` / `no_local_reviewer` at `:8387-8391` and after a clean pass at `:8442-8444`
- **Plant**: `:8387-8391` → `return 0` on `not_required` / `no_local_reviewer` without the live-head re-read
- **Fail run**: `FAIL: 1656_s4a_not_required_head_moved — expected '1', got '0'`; `FAIL: 1656_s4b_not_required_unread_head — expected '1', got '0'`; `FAIL: 1656_s4c_no_local_head_moved — expected '1', got '0'`
- **Pass restored**: `PASS: 1656_s4a_not_required_head_moved`, `PASS: 1656_s4b_not_required_unread_head`, `PASS: 1656_s4c_no_local_head_moved`

## P14 — reuse `head_moved_during_run` (integration)

- **Production**: `:8354` (`aggregate_reason=head_moved_during_run`)
- **Plant**: `:8354` → `aggregate_reason="head_moved_during_second_pass"`
- **Fail run**: `FAIL: 1656_s4a_not_required_aggregate — expected 'head_moved_during_run', got 'head_moved_during_second_pass'`; `FAIL: 1656_s3a_aggregate_reason — expected 'head_moved_during_run', got 'head_moved_during_second_pass'`
- **Pass restored**: `PASS: 1656_s4a_not_required_aggregate`, `PASS: 1656_s3a_aggregate_reason`

## P15 — non-clean pass must override processor skip semantics (fail-open)

- **Production**: `:8451-8452` (`local_second_pass_reason=local_pass_unavailable` on escalate)
- **Plant**: skip assigning `local_pass_unavailable` when `_sl_gate_result=escalate`
- **Fail run**: `FAIL: 1656_s7a_guard_unavailable — expected 'local_pass_unavailable', got 'no_evidence'`; `FAIL: 1656_s7b_guard_unavailable — expected 'local_pass_unavailable', got 'no_evidence'`; `FAIL: 1656_s7c_guard_telemetry — expected 'local_pass_unavailable', got 'no_evidence'`; `FAIL: 1656_s7d_guard_unavailable — expected 'local_pass_unavailable', got 'no_evidence'`
- **Pass restored**: `PASS: 1656_s7a_guard_unavailable`, `PASS: 1656_s7b_guard_unavailable`, `PASS: 1656_s7c_guard_telemetry`, `PASS: 1656_s7d_guard_unavailable`

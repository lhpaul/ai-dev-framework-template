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

Line numbers refer to `scripts/development-workflow/pr-review-loop.sh` at the
current PR head unless a test path is given.

## P1 — per-head dispatch cap (loop/cost)

- **Production**: `:8363-8371` (`failed_for_head` refusal without dispatch); ledger write at `:8430`
- **Plant**: omit `:8430` on a failed pass so `:8363` cannot refuse on the next invocation
- **Fail when planted**: second invocation reaches `:8376` (`run_platform_review`) instead of `:8363`
- **Pass restored**: `1656_s8c_failed_head_count`, `1656_s8c_guard_refuse`, `1656_s8c_guard_no_dispatch` (demonstrated above)

## P2 — silent history must not read as satisfied (fail-open)

- **Production**: `:8299` (`not_yet_run|unknown) printf 'no_evidence'`)
- **Plant**: `test-pr-review-loop.sh:17795-17812` (`_1656_pv_plant_p2_pass_required` maps unknown → `not_required`)
- **Fail when planted**: `1656_pv_P2_plant` (`:17825-17826`) returns `not_required`; `1656_pv_P2_plant_differs` (`:17829-17831`) stays `different`
- **Pass restored**: `1656_pv_P2_correct`, `1656_s5_no_evidence` (`:17827-17828`, `:17682`)

## P3 — pass must not increment caps (loop/cost)

- **Production**: `:8374-8445` (guard dispatch and refusal; no `cycle_count` / `lifetime_cycle_count` mutation)
- **Plant**: add `cycle_count=$((cycle_count + 1))` at `:8374`
- **Fail when planted**: `1656_s9_dispatch_cycle_count` (`:17973-17974`) reads `3` instead of `2`
- **Pass restored**: `1656_s9_dispatch_cycle_count`, `1656_s10_refuse_cycle_count`

## P4 — ready gate after pass result (fail-open)

- **Production**: `:11768` (`reviewer_loop_second_local_pass_before_ready_gate` before ready transition)
- **Plant**: call `ensure_pr_ready_for_ready_phase` before `:8426-8445` gate handling
- **Fail when planted**: `1656_s7_phase_not_started` (`:17903`) would read `1`
- **Pass restored**: all `1656_s7*_phase_not_started` assert `0`

## P5 — no ready-phase → no guard (loop/cost)

- **Production**: `:8337-8338` (`phase_after_clean_enabled` early `return 0`)
- **Plant**: delete `:8337-8339`
- **Fail when planted**: `1656_s13_guard_no_dispatch` (`:18100-18101`) reads `>0`
- **Pass restored**: `1656_s13_guard_noop`, `1656_s13_guard_no_dispatch`

## P6 — failed pass must refuse, not suppress only (fail-open)

- **Production**: `:8363-8371` (`failed_for_head` escalate refusal without dispatch)
- **Plant**: set `local_second_pass=0` at `:8364` without `:8366-8371` aggregate refusal
- **Fail when planted**: `1656_s8c_guard_escalate` (`:17969`) does not read `escalate`
- **Pass restored**: `1656_s8c_guard_refuse`, `1656_s8c_guard_escalate`, `1656_s8c_guard_failed_reason`

## P7 — compose current round before selector (fail-open)

- **Production**: `:8345` (`reviewer_loop_compose_current_round_payload`) feeding `:8346`
- **Plant**: pass `_sl_prior_payload` directly to `:8346` (drop `:8345`)
- **Fail when planted**: `1656_s4_guard_no_dispatch` (`:17960`) reads `>0`
- **Pass restored**: `1656_s4_guard_proceed`, `1656_s4_guard_no_dispatch`, `1656_s5b_output_head_current`

## P8 — shared processor extraction (integration)

- **Production**: `:8451-8528` (`reviewer_loop_process_platform_output`)
- **Plant**: inline duplicate parser omitting `PLATFORM_*` keys
- **Fail when planted**: `1656_s5a_extraction_byte_identical` (`:17775`) diverges
- **Pass restored**: `1656_s5a_extraction_byte_identical`, `1656_s5a_no_second_pass_keys`, `1656_s5a_platform_result`

## P9 — failed head in ledger, not shell (integration)

- **Production**: `:8430` (`local_second_pass_failed_head_record="$loop_head_sha"`) read back at `:8363`
- **Plant**: in-memory flag instead of `:8430` ledger write
- **Fail when planted**: `1656_s8c_guard_no_dispatch` fails on second invocation
- **Pass restored**: `1656_s8c_guard_refuse`, `1656_s8c_failed_head_count` (`:17726-17727`)

## P10 — `not_configured` ≠ `no_evidence` (fail-open)

- **Production**: `:8288-8290` (repo-config pre-check → `no_local_reviewer`)
- **Plant**: `test-pr-review-loop.sh:17813-17824` (`_1656_pv_plant_p10_pass_required`)
- **Fail when planted**: `1656_pv_P10_plant_differs` (`:17837-17839`); plant returns `no_evidence` (`:17835-17836`)
- **Pass restored**: `1656_pv_P10_correct`, `1656_s6_no_local_reviewer` (`:17837-17838`, `:17679-17680`)

## P11 — repo configured list, not invocation filter (fail-open)

- **Production**: `:8344` (`reviewer_loop_repo_configured_platforms`) passed to `:8346`
- **Plant**: pass invocation `platforms[]` to `:8346` instead of `:8344` output
- **Fail when planted**: `1656_s2b_repo_configured` (`:17741-17742`) reads `no_local_reviewer`
- **Pass restored**: `1656_s2b_repo_configured`, `1656_s2c_local_ai_configured`

## P12 — failed pass refusal is `escalate` (loop/cost)

- **Production**: `:8366-8367` (`aggregate_result=escalate`, `aggregate_reason=failed_for_head`)
- **Plant**: map `:8363-8371` refusal to `needs_fixes`
- **Fail when planted**: lifetime/per-run caps stall (`1656_s10_refuse_*`)
- **Pass restored**: `1656_s8c_guard_escalate`, `1656_s10_refuse_cycle_count`, `1656_s10_refuse_lifetime_count`

## P13 — head re-read after clean pass (fail-open)

- **Production**: `:8403-8414` (`gh pr view` head equality after clean pass)
- **Plant**: skip `:8402-8421` re-read block
- **Fail when planted**: `1656_s3a_guard_blocked` (`:18051`) returns `0`
- **Pass restored**: `1656_s3a_guard_blocked`, `1656_s3d_guard_unavailable`, `1656_s3c_guard_no_reviewed_head`

## P14 — reuse `head_moved_during_run` (integration)

- **Production**: `:8417` (`aggregate_reason=head_moved_during_run`)
- **Plant**: mint a new reason token at `:8417`
- **Fail when planted**: `1656_s3a_aggregate_reason` (`:18054`) diverges
- **Pass restored**: `1656_s3a_aggregate_reason`, `1656_s3a_guard_reason=head_moved_during_pass`

## P15 — non-clean pass must override processor skip semantics (fail-open)

- **Production**: `:8428` (`local_second_pass_reason=local_pass_unavailable` on escalate)
- **Plant**: skip `:8427-8428` and let skipped processor result proceed
- **Fail when planted**: `1656_s7a_guard_unavailable` (`:17989-17992`) reads `not_required`
- **Pass restored**: `1656_s7a_guard_unavailable`, `1656_s7b_guard_unavailable`, `1656_s7d_guard_unavailable`, `1656_s7c_guard_telemetry` (`:18023`)

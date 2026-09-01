# Planted-Violation Proofs: Second Local Pass (#1656)

**Item**: [#1656](https://github.com/lhpaul/ai-dev-framework-template/issues/1656)

**Harness command** (all restored checks):

<!-- workflow-shell-contract: bash -->

```bash
bash scripts/development-workflow/tests/test-pr-review-loop.sh --area 1656
```

Each row cites the production guard location, the harness plant (when embedded),
and the fail-then-pass evidence required by `REVIEW.md`.

## P1 — per-head dispatch cap (loop/cost)

- **Production**: `scripts/development-workflow/pr-review-loop.sh:8363` (`local_second_pass_failed_head_record` before dispatch) and `:8369` (`reviewer_loop_local_second_pass_failed_for_head` refusal)
- **Plant**: omit ledger write at `:8396`; second invocation dispatches again (plan scenario 8c)
- **Fail when planted**: manual two-invocation run at same head dispatches twice
- **Pass restored**: `1656_s8c_guard_refuse`, `1656_s8c_guard_no_dispatch` (`test-pr-review-loop.sh:17967-17968`)

## P2 — silent history must not read as satisfied (fail-open)

- **Production**: `scripts/development-workflow/pr-review-loop.sh:8295-8296` (`not_yet_run|unknown` → `no_evidence`)
- **Plant**: `test-pr-review-loop.sh:17795-17812` (`_1656_pv_plant_p2_pass_required` maps unknown → `not_required`)
- **Fail when planted**: `1656_pv_P2_plant_differs` expects `different` (`:17829-17831`); plant alone returns `not_required` (`:17825-17826`)
- **Pass restored**: `1656_pv_P2_correct`, `1656_s5_no_evidence` (`:17827-17828`, `:17682`)

## P3 — pass must not increment caps (loop/cost)

- **Production**: `scripts/development-workflow/pr-review-loop.sh:8330-8375` (guard body; no `cycle_count` mutation)
- **Plant**: increment `cycle_count` inside `:8340` dispatch block
- **Fail when planted**: `1656_s9_dispatch_cycle_count` would read `3` instead of `2` (`:17973-17974`)
- **Pass restored**: same tests pass with counts unchanged

## P4 — ready gate after pass result (fail-open)

- **Production**: `scripts/development-workflow/pr-review-loop.sh:11770-11774` (guard before `ensure_pr_ready_for_ready_phase`)
- **Plant**: call ready gate before `:8426-8445` gate-result handling
- **Fail when planted**: `1656_s7_guard_needs_fixes` + `1656_s7_phase_not_started` (`:17900-17903`) would see `phase_after_clean_started=1`
- **Pass restored**: all `1656_s7*_phase_not_started` assert `0`

## P5 — no ready-phase → no guard (loop/cost)

- **Production**: `scripts/development-workflow/pr-review-loop.sh:8337-8339` (`phase_after_clean_enabled` early return)
- **Plant**: remove `:8337-8339` guard
- **Fail when planted**: `1656_s13_guard_no_dispatch` would read `>0` (`:18100-18101`)
- **Pass restored**: `1656_s13_guard_noop`, `1656_s13_guard_no_dispatch`

## P6 — failed pass must refuse, not suppress only (fail-open)

- **Production**: `scripts/development-workflow/pr-review-loop.sh:8369-8381` (`failed_for_head` escalate refusal)
- **Plant**: set `local_second_pass=0` without setting `aggregate_result=escalate`
- **Fail when planted**: `1656_s8c_guard_escalate` would not read `escalate` (`:17969`)
- **Pass restored**: `1656_s8c_guard_refuse`, `1656_s8c_guard_escalate`, `1656_s8c_guard_failed_reason`

## P7 — compose current round before selector (fail-open)

- **Production**: `scripts/development-workflow/pr-review-loop.sh:8345-8346` (`reviewer_loop_compose_current_round_payload`)
- **Plant**: pass `_sl_prior_payload` directly to `:8346` without compose
- **Fail when planted**: `1656_s4_guard_proceed` would dispatch (`:17959-17960` → calls `>0`)
- **Pass restored**: `1656_s4_guard_proceed`, `1656_s4_guard_no_dispatch`, `1656_s5b_output_head_current`

## P8 — shared processor extraction (integration)

- **Production**: `scripts/development-workflow/pr-review-loop.sh:8453-8530` (`reviewer_loop_process_platform_output`)
- **Plant**: duplicate inline parsing without shared function (drops keys)
- **Fail when planted**: `1656_s5a_extraction_byte_identical` (`:17775`) diverges between runs
- **Pass restored**: `1656_s5a_extraction_byte_identical`, `1656_s5a_no_second_pass_keys`, `1656_s5a_platform_result`

## P9 — failed head in ledger, not shell (integration)

- **Production**: `scripts/development-workflow/pr-review-loop.sh:8369` (`reviewer_loop_local_second_pass_failed_for_head` on prior payload)
- **Plant**: in-memory flag instead of ledger field (plan scenario 8c cross-invocation)
- **Fail when planted**: second invocation dispatches; `1656_s8c_guard_no_dispatch` fails
- **Pass restored**: `1656_s8c_guard_refuse`, `1656_s8c_failed_head_count` (`:17726-17727`)

## P10 — `not_configured` ≠ `no_evidence` (fail-open)

- **Production**: `scripts/development-workflow/pr-review-loop.sh:8288-8291` (repo-config pre-check → `no_local_reviewer`)
- **Plant**: `test-pr-review-loop.sh:17813-17824` (`_1656_pv_plant_p10_pass_required` folds unconfigured into `no_evidence`)
- **Fail when planted**: `1656_pv_P10_plant_differs` (`:17837-17839`); plant returns `no_evidence` for unconfigured repo (`:17835-17836`)
- **Pass restored**: `1656_pv_P10_correct`, `1656_s6_no_local_reviewer` (`:17679-17680`)

## P11 — repo configured list, not invocation filter (fail-open)

- **Production**: `scripts/development-workflow/pr-review-loop.sh:8344` (`reviewer_loop_repo_configured_platforms`)
- **Plant**: pass `platforms[]` to `:8346` instead
- **Fail when planted**: `1656_s2b_repo_configured` would read `no_local_reviewer` (`:17741-17742`)
- **Pass restored**: `1656_s2b_repo_configured`, `1656_s2c_local_ai_configured`

## P12 — failed pass refusal is `escalate` (loop/cost)

- **Production**: `scripts/development-workflow/pr-review-loop.sh:8375-8381` (`aggregate_result=escalate`, `aggregate_reason=failed_for_head`)
- **Plant**: map failed-head refusal to `needs_fixes`
- **Fail when planted**: `1656_s10_refuse_cycle_count` stuck; caps never advance (plan scenario 10)
- **Pass restored**: `1656_s8c_guard_escalate`, `1656_s10_refuse_cycle_count`, `1656_s10_refuse_lifetime_count`

## P13 — head re-read after clean pass (fail-open)

- **Production**: `scripts/development-workflow/pr-review-loop.sh:8402-8421` (`gh pr view` equality check after clean pass)
- **Plant**: skip `:8402-8421` re-read
- **Fail when planted**: `1656_s3a_guard_blocked` opens gate on moved head (`:18051-18055`)
- **Pass restored**: `1656_s3a_guard_blocked`, `1656_s3d_guard_unavailable`, `1656_s3c_guard_no_reviewed_head`

## P14 — reuse `head_moved_during_run` (integration)

- **Production**: `scripts/development-workflow/pr-review-loop.sh:8414-8418` (`aggregate_reason=head_moved_during_run`)
- **Plant**: mint new reason token at `:8414`
- **Fail when planted**: `1656_s3a_aggregate_reason` would not read `head_moved_during_run` (`:18054`)
- **Pass restored**: `1656_s3a_aggregate_reason`, `1656_s3a_guard_reason=head_moved_during_pass`

## P15 — non-clean pass must override processor skip semantics (fail-open)

- **Production**: `scripts/development-workflow/pr-review-loop.sh:8426-8445` (gate override after shared processor)
- **Plant**: skip override; propagate processor `skipped` as proceed
- **Fail when planted**: `1656_s7a_guard_unavailable` would read `not_required` or proceed (`:17989-17992`)
- **Pass restored**: `1656_s7a_guard_unavailable`, `1656_s7b_guard_unavailable`, `1656_s7d_guard_unavailable`, `1656_s7c_guard_telemetry`

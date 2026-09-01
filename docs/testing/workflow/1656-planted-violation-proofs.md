# Planted-Violation Proofs: Second Local Pass (#1656)

**Item**: [#1656](https://github.com/lhpaul/ai-dev-framework-template/issues/1656)  
**Harness**: `bash scripts/development-workflow/tests/test-pr-review-loop.sh --area 1656`

Each proof names a plant (wrong behavior embedded only in the harness), the
restored check that must pass, and the scenario test that guards production
code. Run the area filter after any change to `pr-review-loop.sh` second-pass
logic.

| # | Group | Plant (fails if restored check regresses) | Restored check |
| --- | --- | --- | --- |
| P1 | loop/cost | Per-cycle boolean instead of per-head key (manual: dispatch twice same head) | `1656_s9_dispatch_cycle_count`, guard dispatch count tests |
| P2 | fail-open | `1656_pv_P2_plant` → `not_required` for silent history | `1656_pv_P2_correct`, `1656_s5_no_evidence` |
| P3 | loop/cost | Increment caps when pass runs | `1656_s9_dispatch_cycle_count`, `1656_s10_refuse_cycle_count` |
| P4 | fail-open | Call ready gate before pass result | `1656_s7*` guard blocked + phase not started |
| P5 | loop/cost | Run guard with no ready-phase platform | `1656_s13_guard_noop` |
| P6 | fail-open | Suppress dispatch without refusing gate | `1656_s8c_guard_refuse`, `1656_s8a` aggregate escalate |
| P7 | fail-open | Read persisted payload without composing current round | `1656_s4_guard_proceed`, `1656_s5b` composed round |
| P8 | integration | Process pass output without shared processor | `1656_s5a_extraction_byte_identical` |
| P9 | integration | Hold failed head in shell variable only | `1656_s8c_guard_refuse` cross-invocation |
| P10 | fail-open | Fold `not_configured` into `no_evidence` | `1656_pv_P10_plant` vs `1656_pv_P10_correct`, `1656_s6_no_local_reviewer` |
| P11 | fail-open | Pass invocation `platforms[]` instead of repo config | `1656_s2b_repo_configured` |
| P12 | loop/cost | Refuse failed pass with `needs_fixes` | `1656_s8c_guard_escalate`, `1656_s10_refuse_*` |
| P13 | fail-open | Open gate on clean pass without head re-read | `1656_s3a_guard_blocked`, `1656_s3d_guard_unavailable` |
| P14 | integration | New token for mid-pass head move | `1656_s3a_aggregate_reason` → `head_moved_during_run` |
| P15 | fail-open | Let skipped pass result reach aggregate unchanged | `1656_s7a_guard_unavailable`, `1656_s7d_guard_unavailable` |

**Commands**

<!-- workflow-shell-contract: bash -->

```bash
bash scripts/development-workflow/tests/test-pr-review-loop.sh --area 1656
```

Explicit plant-vs-restored pairs (must stay `different` / pass respectively):

- P2: `1656_pv_P2_plant`, `1656_pv_P2_correct`, `1656_pv_P2_plant_differs`
- P10: `1656_pv_P10_plant`, `1656_pv_P10_correct`, `1656_pv_P10_plant_differs`

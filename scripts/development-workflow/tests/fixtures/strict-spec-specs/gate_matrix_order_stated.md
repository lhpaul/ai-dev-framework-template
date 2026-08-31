# Spec fixture: gate_matrix negative (AC-6a)

## Decision Matrix
Inputs are evaluated in this order: (1) stage resolved?, (2) stage is spec?,
(3) checklist available?. Later inputs are not evaluated when an earlier answer
makes them unreachable.

| Stage resolves | Stage | Checklist | Outcome |
| --- | --- | --- | --- |
| No | — | — | unavailable |
| Yes | not spec | — | not_applicable |
| Yes | spec | No | unavailable |
| Yes | spec | Yes | applied |

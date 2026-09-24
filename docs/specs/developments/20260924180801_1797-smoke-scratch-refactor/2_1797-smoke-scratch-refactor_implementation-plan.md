# Smoke Scratch Refactor: rename `_parse_number` — Implementation Plan

**Spec**: None (Refactor item, no spec)
**Smoke test runbook**: N/A — scratch item created solely to exercise the
#1496 plan-authoring-rigor smoke runbook. Not merged.

---

## Summary

**Approach**: Rename the private helper `_parse_number` in
`scripts/lint/markdown-heuristic-lint.py` to `_parse_int_token` for clarity,
and update its one call site.

**Estimated complexity**: S

**Rationale**: Single-file rename with one call site.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `d79d41dc` |
| Helper definition count | `grep -n "_parse_number" scripts/lint/markdown-heuristic-lint.py` | 2 matches: line 160 (definition), line 284 (one call site) — the population counted is occurrences of the exact identifier `_parse_number` in this one file |
| No other consumers | `grep -rn "_parse_number" scripts/ .github/` | Only the 2 matches above; no other file references this identifier |

---

## Cross-Cutting Operational Assumption Check

### Not applicable

**Result**: `Not applicable` — this scratch refactor has no environment
target, approved base, linked resource, artifact owner, or canonical
configuration value dependency.

---

## Layer-by-Layer Changes

### Shared Packages / Libraries

- [ ] Rename `_parse_number` to `_parse_int_token` in
      `scripts/lint/markdown-heuristic-lint.py` (definition at line 160).
- [ ] Update the one call site at line 284 to use the new name.

---

## Files to modify

| File | Change |
| --- | --- |
| `scripts/lint/markdown-heuristic-lint.py` | Rename helper and its one call site |

---

## Testing Strategy

**Test types**: Manual (scratch item; no automated suite change).

**Key scenarios to test**:

1. Run `python3 scripts/lint/markdown-heuristic-lint.py` against a sample
   markdown file and confirm output is unchanged after the rename.

**Regression suite**: Not applicable — pure rename, no behavior change.

---

## Documentation Updates

- [ ] None — private helper, no doc references its name.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Missed call site | Low | Low | Rule 5 enumeration above confirms exactly one call site |

---

## Implementation Order

1. Rename the function definition and its one call site.
2. Run the manual smoke check.

**Changelog fragment**: Not applicable — scratch smoke-test item, never merged.

---

## Document Quality Gate

- Spec/brief coverage: Checked - this Refactor item has no spec; the brief is "rename `_parse_number` for clarity", fully addressed by the one Layer-by-Layer step.
- Implementation-order consistency: Checked - file list and order agree.
- Verification support: Checked - the rename count and call-site count cite the Verification Log commands above.
- Complex workflow decision-gate matrix: Not applicable - this plan does not add or modify workflow decision-gate behavior.
- Parser/API/concurrency checklist: Not applicable - no parser, API-surface, snapshot, or concurrent-event signals.

### Plan authoring rigor — per-rule outcome record

Plan revision: `<to be filled with this branch's HEAD short SHA after commit>`

| Rule | Outcome | Rationale / first external inspection finding |
| --- | --- | --- |
| Rule 1 | Not applicable | No design depends on externally produced free text. |
| Rule 2 | Satisfied | Each fact (helper name, line numbers, call-site count) is asserted once, in the Verification Log; the Layer-by-Layer step references it rather than restating it. |
| Rule 3 | Satisfied | The call-site count (1) is derived by the recorded `grep -rn` command at revision `d79d41dc`, over the population "occurrences of the literal identifier `_parse_number` under `scripts/` and `.github/`". |
| Rule 4 | Satisfied | "No other consumers" is supported by the recorded repo-wide `grep -rn` search in the Verification Log, covering the plausible locations (`scripts/`, `.github/`) where a caller of this helper could live. |
| Rule 5 | Satisfied | The single consumer (line 284) is enumerated by the recorded search, and the expected behavior (updated call to the renamed helper) is stated at that exact consumer site. |
| Rule 6 | Not applicable | This plan states no conditional obligation ("required when X", "checkable once Y", "must hold after Z"). |

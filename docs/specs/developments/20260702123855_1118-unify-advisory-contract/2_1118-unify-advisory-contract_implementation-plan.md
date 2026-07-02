# Unified Advisory Contract — Implementation Plan

**Spec**: [1_1118-unify-advisory-contract_specs.md](1_1118-unify-advisory-contract_specs.md)
**Smoke test runbook**: [1118-unify-advisory-contract.smoke-test.md](../../../testing/workflow/1118-unify-advisory-contract.smoke-test.md)

---

## Summary

**Approach**: Introduce `ADVISORY_FINDINGS` as the canonical shell
key-value contract for non-blocking reviewer findings, with a compact JSON array
as the value. Emit it from PR-Agent and Haystack paths, aggregate it in
`pr-review-loop.sh`, render summaries from the unified list, and keep
`ADVISORY_LABELS` plus `ADVISORY_FINDINGS_JSON` as compatibility aliases for one
transition release.

**Estimated complexity**: M

**Rationale**: The change is bounded to workflow shell tooling, tests, and docs,
but it touches structured output parsing and reviewer-loop summary generation.
Those paths require careful compatibility handling because external adapters and
existing tests consume key-value stdout.

**Dependencies**: #1113 Structured Haystack Advisory Findings is merged and
available on the integration branch.

---

## Verification Log

| Check | Command / query | Result |
| ----- | --------------- | ------ |
| Repo revision | `git rev-parse --short HEAD` | `0857a8b` |
| Spec source | `sed -n '1,220p' docs/specs/developments/20260702123855_1118-unify-advisory-contract/1_1118-unify-advisory-contract_specs.md` | Spec defines `ADVISORY_FINDINGS` as canonical and requires PR-Agent, Haystack, summary, disposition, and Protocol 93 coverage. |
| Current advisory signals | `rg -n "ADVISORY_LABELS\|ADVISORY_FINDINGS_JSON\|SUGGESTION_COUNT\|ADVISORY_DISPOSITION_REQUIRED" scripts/development-workflow/pr-review-loop.sh scripts/development-workflow/haystack-reviewer.sh docs/workflow/development-workflow/integrations/pr-review-platform.md docs/workflow/development-workflow/integrations/haystack-triage.md docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md scripts/development-workflow/tests/test-pr-review-loop.sh scripts/development-workflow/tests/test-haystack-reviewer.sh` | PR-Agent currently emits `ADVISORY_LABELS`; Haystack emits `ADVISORY_FINDINGS_JSON`; `pr-review-loop.sh` aggregates both separately and emits `ADVISORY_DISPOSITION_REQUIRED`. |
| Reviewer-loop aggregation points | `sed -n '430,500p' scripts/development-workflow/pr-review-loop.sh && sed -n '5400,5545p' scripts/development-workflow/pr-review-loop.sh && sed -n '5730,5835p' scripts/development-workflow/pr-review-loop.sh && sed -n '6235,6305p' scripts/development-workflow/pr-review-loop.sh` | Existing helpers compact structured advisory JSON, track aggregate advisory arrays, render advisory summary rows, and emit final aggregate counts. |
| Haystack wrapper output points | `sed -n '1,120p' scripts/development-workflow/haystack-reviewer.sh && sed -n '740,820p' scripts/development-workflow/haystack-reviewer.sh && sed -n '930,1000p' scripts/development-workflow/haystack-reviewer.sh` | Haystack normalization preserves severity, category, summary, detail, location, fix hints, and false-positive disposition metadata in `ADVISORY_FINDINGS_JSON`. |

---

## Layer-by-Layer Changes

### Database / Data Layer

- [ ] No database, migration, or seed-data changes.

### Backend / API

- [ ] No application backend or public API changes.

### Workflow Scripts

- [ ] `scripts/development-workflow/haystack-reviewer.sh`: emit
      `ADVISORY_FINDINGS=<json-array>` anywhere a completed review currently
      emits `ADVISORY_FINDINGS_JSON`, while retaining
      `ADVISORY_FINDINGS_JSON` as a compatibility alias.
- [ ] `scripts/development-workflow/pr-review-loop.sh`: add helper logic that
      prefers `ADVISORY_FINDINGS`, falls back to `ADVISORY_FINDINGS_JSON`, and
      validates compact JSON arrays with the existing jq-based parsing path.
- [ ] `scripts/development-workflow/pr-review-loop.sh`: convert PR-Agent
      advisory labels into normalized `ADVISORY_FINDINGS` objects with
      `source`, `category`, `summary`, and optional `url` fields while still
      emitting `ADVISORY_LABELS`.
- [ ] `scripts/development-workflow/pr-review-loop.sh`: aggregate all platform
      advisory arrays into one final `ADVISORY_FINDINGS=<json-array>` output,
      derive `ADVISORY_DISPOSITION_REQUIRED` from the unified list, and render
      the summary from that list without duplicating legacy alias rows.

### Shared Packages / Libraries

- [ ] No shared package changes.

### Frontend / UI

- [ ] No frontend or browser UI changes.

### Infrastructure / Configuration

- [ ] No workflow configuration schema changes.

### Tests

- [ ] `scripts/development-workflow/tests/test-haystack-reviewer.sh`: assert
      completed Haystack reviews emit both `ADVISORY_FINDINGS` and the
      transition alias `ADVISORY_FINDINGS_JSON`, with identical JSON.
- [ ] `scripts/development-workflow/tests/test-pr-review-loop.sh`: add unit
      coverage for PR-Agent label normalization, Haystack alias fallback,
      mixed-platform aggregation, summary rendering from the unified list, and
      disposition-required output from `ADVISORY_FINDINGS`.

---

## Testing Strategy

**Test types**: Shell unit tests, markdown lint, workflow shell guard, smoke.

**Key scenarios to test**:

1. PR-Agent advisory labels produce a normalized unified advisory list while
   retaining `ADVISORY_LABELS`. Maps to AC-2, AC-4, AC-7.
2. Haystack completed reviews emit `ADVISORY_FINDINGS` without losing existing
   fields or false-positive disposition metadata. Maps to AC-3, AC-7.
3. The reviewer loop aggregates PR-Agent and Haystack advisories into one
   canonical list and renders one advisory summary section. Maps to AC-4.
4. `ADVISORY_DISPOSITION_REQUIRED=1` and disposition inputs are derivable from
   the unified list without parsing provider-specific aliases. Maps to AC-5.
5. Protocol and integration docs define the contract and transition aliases.
   Maps to AC-1, AC-6.

**Smoke test runbook**:
`docs/testing/workflow/1118-unify-advisory-contract.smoke-test.md`

**Regression suite**: No browser regression suite applies. The shell tests are
the regression suite for this workflow behavior.

### Parser-risk Addendum

This plan is parser-risk because it changes shell key-value parsing, JSON
transport, and structured reviewer-output scanning.

**Edge-case enumeration**:

1. Boundary-character variants: advisory summaries and details containing
   quotes, pipes, equals signs, dollar signs, and escaped newlines remain one
   valid JSON value after the first `=`.
2. Negative lookalikes: malformed JSON, non-array JSON, and empty alias fields
   do not produce a false successful unified list.
3. Multiple occurrences: a platform output containing both `ADVISORY_FINDINGS`
   and `ADVISORY_FINDINGS_JSON` prefers the canonical field and does not double
   count the alias.
4. Nested or overlapping constructs: PR-Agent pipe-delimited labels with a
   comment URL are converted into multiple finding objects without treating the
   URL separator as part of a label.
5. Optional-provider fields: Haystack findings that include `disposition`,
   `disposition_rule`, `disposition_rationale`, `path`, `line`, and `fix_hint`
   preserve those fields in the unified output.
6. Missing optional fields: PR-Agent advisories that only expose a label and URL
   still produce a finding with required `source`, `category`, and `summary`.

**Unit test mapping**:

- `scripts/development-workflow/tests/test-haystack-reviewer.sh`
  covers edge cases 1 and 5 by extending the existing structured advisory tests
  to read `ADVISORY_FINDINGS` and verify alias equality.
- `scripts/development-workflow/tests/test-pr-review-loop.sh`
  covers edge case 2 with malformed and non-array unified advisory JSON
  rejection tests.
- `scripts/development-workflow/tests/test-pr-review-loop.sh`
  covers edge case 3 with canonical-plus-alias platform output and aggregation
  count assertions.
- `scripts/development-workflow/tests/test-pr-review-loop.sh`
  covers edge cases 4 and 6 with PR-Agent label-to-finding normalization tests.
- `scripts/development-workflow/tests/test-pr-review-loop.sh`
  covers edge case 5 with mixed Haystack structured findings that include
  disposition metadata and location fields.

**Suppression semantics**: Not applicable. This feature does not add inline
suppression directives or scanner suppressions.

---

## Seed Data

No persistent seed data is required.

| Entity | Values / Scenario | File |
| ------ | ----------------- | ---- |
| Shell test fixture | Mock PR-Agent and Haystack reviewer outputs with advisory-only findings | `scripts/development-workflow/tests/test-pr-review-loop.sh` and `scripts/development-workflow/tests/test-haystack-reviewer.sh` |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/pr-review-platform.md`:
      define the provider-agnostic `ADVISORY_FINDINGS` JSON array contract,
      required fields, optional fields, and transition aliases.
- [ ] `docs/workflow/development-workflow/integrations/haystack-triage.md`:
      document that Haystack emits `ADVISORY_FINDINGS` canonically and
      `ADVISORY_FINDINGS_JSON` as a temporary compatibility alias.
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`:
      reference the unified advisory contract for advisory discovery, summary
      rendering, and disposition handling.
- [ ] `CHANGELOG.md`: add an `[Unreleased]` entry during implementation using
      the literal format `- **Unify advisory contract** (#1118): Add a provider-agnostic reviewer advisory contract while preserving transition aliases.`
- [ ] `AGENTS.md`: not required because repository commands and conventions do
      not change.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| Existing adapters still read `ADVISORY_FINDINGS_JSON` or `ADVISORY_LABELS`. | Medium | Medium | Keep both aliases for one transition release and document the canonical field. |
| Unified JSON aggregation double-counts findings when aliases are present. | Medium | Medium | Prefer canonical `ADVISORY_FINDINGS` per platform and add tests for canonical-plus-alias output. |
| Shell key-value parsing corrupts JSON values containing separators. | Medium | High | Continue parsing the full value after the first `=`, compact with jq, and cover quotes, pipes, equals signs, and newlines in tests. |
| Summary output hides provider-specific context. | Low | Medium | Require `source` on each unified finding and preserve optional detail, location, fix hint, and disposition fields. |

---

## Code Samples

No production code samples are included. Implementation should follow the
existing shell helper style in `pr-review-loop.sh` and `haystack-reviewer.sh`.

---

## Implementation Order

1. Update `docs/workflow/development-workflow/integrations/pr-review-platform.md`
   to define `ADVISORY_FINDINGS` as the canonical advisory contract. Include
   required fields `source`, `category`, and `summary`; optional fields
   `detail`, `url`, `path`, `line`, `fix_hint`, `disposition`,
   `disposition_rule`, and `disposition_rationale`; and transition alias notes.
2. Update `scripts/development-workflow/haystack-reviewer.sh` to emit
   `ADVISORY_FINDINGS` alongside `ADVISORY_FINDINGS_JSON` on completed review
   paths. Verify `test-haystack-reviewer.sh` can read both fields.
3. Update `scripts/development-workflow/pr-review-loop.sh` with a platform
   output reader that prefers `ADVISORY_FINDINGS`, falls back to
   `ADVISORY_FINDINGS_JSON`, compacts valid JSON arrays, and fails closed on
   malformed non-empty canonical JSON.
4. Add PR-Agent advisory normalization in `pr-review-loop.sh`. Convert each
   advisory label plus optional comment URL into a finding object with
   `source:"pr-agent"`, `category:<label>`, `summary:<label>`, and `url` when
   available, while retaining `ADVISORY_LABELS`.
5. Replace summary rendering inputs so `_post_review_summary` renders from the
   aggregate unified list. Keep legacy alias rendering only as fallback for
   old platform output that lacks `ADVISORY_FINDINGS`.
6. Emit aggregate `ADVISORY_FINDINGS=<json-array>` from `pr-review-loop.sh` on
   final output and ensure `ADVISORY_DISPOSITION_REQUIRED` is derived from the
   unified list plus existing policy-review signals.
7. Update `scripts/development-workflow/tests/test-haystack-reviewer.sh` and
   `scripts/development-workflow/tests/test-pr-review-loop.sh` for every
   parser-risk edge case listed above.
8. Update `docs/workflow/development-workflow/integrations/haystack-triage.md`
   and `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
   to reference the unified contract and transition aliases.
9. Add the implementation `CHANGELOG.md` entry exactly as listed in the
   Documentation Updates section.
10. Run verification:
    - `bash scripts/development-workflow/tests/test-haystack-reviewer.sh`
    - `bash scripts/development-workflow/tests/test-pr-review-loop.sh`
    - `bash scripts/development-workflow/validate-workflow-config.sh`
    - `bash -n scripts/development-workflow/haystack-reviewer.sh`
    - `bash -n scripts/development-workflow/pr-review-loop.sh`
    - `shellcheck scripts/development-workflow/haystack-reviewer.sh scripts/development-workflow/pr-review-loop.sh`
    - `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop-external-review-loop-hardening`
    - `npx markdownlint-cli2 "docs/workflow/development-workflow/integrations/pr-review-platform.md" "docs/workflow/development-workflow/integrations/haystack-triage.md" "docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md" "docs/testing/workflow/1118-unify-advisory-contract.smoke-test.md" "CHANGELOG.md"`
    - `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`
    - `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`
    - `git diff --check`
11. Execute the smoke runbook at
    `docs/testing/workflow/1118-unify-advisory-contract.smoke-test.md` and
    record the results in the implementation PR.

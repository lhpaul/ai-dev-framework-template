# Implementation Plan: Structured Haystack Advisory Findings

**Spec**: [Structured Haystack Advisory Findings](1_1113-structured-advisory-findings_specs.md)
**Smoke test runbook**: [Structured Haystack Advisory Findings](../../../testing/workflow/1113-structured-advisory-findings.smoke-test.md)

---

## Summary

**Approach**: Extend the Haystack reviewer wrapper so it normalizes Haystack
findings into two compact JSON arrays: one for advisory findings and one for
blocking findings. Preserve the existing result and count fields for current
review-loop consumers, add focused parser-risk tests to the Haystack reviewer
harness, and document the new contract in the Haystack triage integration guide.

**Estimated complexity**: M

**Rationale**: The change is localized to one shell wrapper, one test harness,
and one integration guide, but it is parser-risk because it adds structured JSON
normalization, shell key-value emission, and escaping expectations that later
workflow stages will consume.

**Dependencies**: Issue #1113 spec merged into `develop-external-review-loop-hardening`.

---

## Verification Log

| Check | Command / query | Result |
| ----- | --------------- | ------ |
| Repo revision | `git rev-parse --short HEAD` | `3113217` |
| Existing Haystack output contract | `rg -n "SUGGESTION_COUNT|BLOCKING_COUNT|COMMENT_COUNT" scripts/development-workflow/haystack-reviewer.sh` | Existing wrapper emits count-only review fields and no structured finding arrays. |
| Existing finding parser | `sed -n '480,720p' scripts/development-workflow/haystack-reviewer.sh` | Findings are currently read from `.findings[]`, categorized by `.category`, and counted into `BLOCKING_COUNT` / `SUGGESTION_COUNT`. |
| Existing Haystack tests | `rg -n "advisory_only|Rules violation|Logic error|POLICY_REVIEW_REQUIRED" scripts/development-workflow/tests/test-haystack-reviewer.sh` | The harness already covers advisory-only, rules-violation advisory, blocking, and policy-verdict cases; it can be extended for structured arrays. |
| Review-loop consumer scope | `sed -n '2040,2140p' scripts/development-workflow/pr-review-loop.sh` | `pr-review-loop.sh` currently parses only result/count fields from `haystack-reviewer.sh`; listing advisories in the PR summary is deferred to #1114. |
| Documentation targets | `rg -n "Severity Mapping|Exit Code Contract|Script Interface" docs/workflow/development-workflow/integrations/*.md` | `haystack-triage.md` owns Haystack-specific contract docs; `pr-review-platform.md` has the generic platform interface for later #1118 work. |

---

## Layer-by-Layer Changes

### Workflow Script

- [ ] Update `scripts/development-workflow/haystack-reviewer.sh` to build
      `ADVISORY_FINDINGS_JSON` and `BLOCKING_FINDINGS_JSON` from the same
      `.findings[]` snapshot used for count classification.
- [ ] Keep `RESULT`, `BLOCKING_COUNT`, `SUGGESTION_COUNT`, `COMMENT_COUNT`,
      `POLICY_*`, and `DISPLAY_RESULT` output unchanged for existing consumers.
- [ ] Emit each structured JSON array as a single compact `KEY=<json>` line
      after the count fields for both clean and needs-fixes results.
- [ ] Normalize each finding object with these fields:
  - `severity`: `advisory` or `blocking`.
  - `category`: Haystack category string, or `__UNKNOWN__` when missing.
  - `summary`: short finding summary, or an empty string when absent.
  - `detail`: detailed finding text, or an empty string when absent.
  - `path`: optional source path when Haystack supplies one.
  - `line`: optional numeric source line when Haystack supplies one.
  - `fix_hint`: optional fix guidance from Haystack's agent fix prompt.
- [ ] Treat optional source fields as best-effort normalization. Missing,
      `null`, or differently-shaped source data must not invalidate the
      structured arrays or change the blocking/advisory counts.

### Tests

- [ ] Extend `scripts/development-workflow/tests/test-haystack-reviewer.sh`
      with a dedicated structured-finding section.
- [ ] Add tests for multi-advisory payloads, mixed blocking/advisory payloads,
      missing optional source fields, newline/quote escaping, missing category
      safe-fail behavior, and `HAYSTACK_MAJOR_IS_BLOCKING=1`.
- [ ] Keep existing tests for policy verdicts, pending retries, unavailable
      states, and count fields passing unchanged.

### Documentation

- [ ] Update `docs/workflow/development-workflow/integrations/haystack-triage.md`
      with a "Structured Finding Output" section documenting required fields,
      optional fields, example output, and compatibility with existing count
      fields.
- [ ] Mention that `pr-review-loop.sh` does not list Haystack advisory details
      until #1114 consumes the new structured output.

### Smoke Test Runbook

- [ ] Add `docs/testing/workflow/1113-structured-advisory-findings.smoke-test.md`
      covering all acceptance criteria from the spec.

---

## Testing Strategy

**Test types**: Unit, lint, and smoke.

**Key scenarios to test**:

1. Multi-advisory Haystack payload emits one structured advisory entry per
   finding while preserving `RESULT=clean`, `SUGGESTION_COUNT`, and
   `COMMENT_COUNT`. Maps to AC-1, AC-2, AC-4, and AC-5.
2. Mixed blocking/advisory payload emits both structured arrays and preserves
   `RESULT=needs_fixes` with accurate counts. Maps to AC-3 and AC-4.
3. Findings with missing optional source data still produce valid JSON entries.
   Maps to AC-2.
4. Findings containing quotes, newlines, and shell-sensitive characters remain
   valid single-line JSON in the key-value output. Maps to AC-1 and AC-6.
5. Haystack triage documentation describes the contract and optional fields.
   Maps to AC-7.

**Smoke test runbook**:
`docs/testing/workflow/1113-structured-advisory-findings.smoke-test.md`

**Regression suite**:

- [ ] `bash scripts/development-workflow/tests/test-haystack-reviewer.sh`
- [ ] `npx markdownlint-cli2 "docs/specs/developments/20260702083004_1113-structured-advisory-findings/2_1113-structured-advisory-findings_implementation-plan.md" "docs/testing/workflow/1113-structured-advisory-findings.smoke-test.md"`
- [ ] `python3 scripts/lint/markdown-heuristic-lint.py docs/specs/developments/20260702083004_1113-structured-advisory-findings/2_1113-structured-advisory-findings_implementation-plan.md docs/testing/workflow/1113-structured-advisory-findings.smoke-test.md`

### Parser-Risk Addendum

This plan is parser-risk because it changes structured-text parsing and
machine-readable shell output in `haystack-reviewer.sh`.

**Edge-case enumeration**:

1. Empty `.findings` array produces `[]` for both structured arrays and keeps
   both count fields at zero.
2. Multiple advisory findings on one payload preserve ordering and one output
   object per finding.
3. Mixed blocking and advisory findings partition into the correct arrays while
   preserving total counts.
4. Missing or empty category maps to `__UNKNOWN__`, safe-fails to blocking, and
   appears in `BLOCKING_FINDINGS_JSON`.
5. Unrecognized category safe-fails to blocking and is represented in the
   blocking array.
6. `Major` appears in the advisory array by default and in the blocking array
   when `HAYSTACK_MAJOR_IS_BLOCKING=1`.
7. `source: null`, missing `source`, and source objects without path/line still
   emit valid entries with optional fields omitted.
8. Source path and line variants are best-effort: known path-like and line-like
   fields populate `path` and `line`; unknown shapes do not fail parsing.
9. Summary, detail, and fix guidance containing quotes, backslashes, newlines,
   pipes, equals signs, and shell metacharacters remain valid JSON on one
   output line.
10. Policy-status-only review output with no findings still emits empty
    structured arrays and preserves existing `POLICY_*` fields.
11. Reviewer skipped/unavailable paths keep existing skip output and may omit
    structured arrays; consumers must not rely on arrays when no review result
    exists.

**Unit test mapping**:

| Edge case | Test file | Planned assertion |
| --------- | --------- | ----------------- |
| 1 | `scripts/development-workflow/tests/test-haystack-reviewer.sh` | Empty findings output contains `ADVISORY_FINDINGS_JSON=[]` and `BLOCKING_FINDINGS_JSON=[]`. |
| 2 | `scripts/development-workflow/tests/test-haystack-reviewer.sh` | Multi-advisory payload produces advisory array length 2 and preserves order. |
| 3 | `scripts/development-workflow/tests/test-haystack-reviewer.sh` | Mixed payload produces one advisory and one blocking entry with matching counts. |
| 4 | `scripts/development-workflow/tests/test-haystack-reviewer.sh` | Missing category increments blocking count and emits category `__UNKNOWN__`. |
| 5 | `scripts/development-workflow/tests/test-haystack-reviewer.sh` | Unknown category appears in blocking array. |
| 6 | `scripts/development-workflow/tests/test-haystack-reviewer.sh` | `Major` category moves between arrays based on `HAYSTACK_MAJOR_IS_BLOCKING`. |
| 7 | `scripts/development-workflow/tests/test-haystack-reviewer.sh` | Null/missing source omits optional location fields without JSON parse failure. |
| 8 | `scripts/development-workflow/tests/test-haystack-reviewer.sh` | Known source path/line fields populate normalized `path` and `line`. |
| 9 | `scripts/development-workflow/tests/test-haystack-reviewer.sh` | Output line parses with `jq` and preserves escaped text values. |
| 10 | `scripts/development-workflow/tests/test-haystack-reviewer.sh` | Policy-only result keeps empty arrays and existing policy fields. |
| 11 | `scripts/development-workflow/tests/test-haystack-reviewer.sh` | Existing unavailable/skipped tests remain unchanged. |

**Suppression semantics**: Not applicable. This feature does not introduce
inline suppression directives.

---

## Seed Data

No persistent seed data is required. Tests use deterministic mocked Haystack
JSON payloads inside `scripts/development-workflow/tests/test-haystack-reviewer.sh`.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/haystack-triage.md` -
      document the structured finding output contract, required and optional
      fields, and example key-value output.
- [ ] `docs/testing/workflow/1113-structured-advisory-findings.smoke-test.md` -
      add the smoke runbook during Plan Ready and keep it aligned after
      implementation.
- [ ] `AGENTS.md` - no update required; this feature changes review wrapper
      output, not repository-wide agent instructions.
- [ ] `docs/project/` - no update required; placeholder project-domain,
      architecture, and database docs are not affected by this workflow wrapper
      contract.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| JSON output breaks shell key-value parsing | Medium | High | Emit compact single-line JSON and add tests that extract the value after the first `=` and parse it with `jq`. |
| Structured arrays drift from count classification | Medium | High | Build both arrays from the same `.findings[]` categorization snapshot used for counts. |
| Optional Haystack source shapes are overfit to one sample | Medium | Medium | Normalize known fields best-effort and omit unknown optional fields instead of failing. |
| Later review-loop summary work assumes this issue lists advisories in PR comments | Low | Medium | Document that PR summary consumption is deferred to #1114. |

---

## Code Samples

No production code samples are included. The implementer should derive exact
`jq` filters and shell helpers from the existing `haystack-reviewer.sh` style.

---

## Implementation Order

1. Update `scripts/development-workflow/haystack-reviewer.sh` with a small
   normalization helper that converts a Haystack finding into a compact JSON
   object with `severity`, `category`, `summary`, `detail`, optional `path`,
   optional `line`, and optional `fix_hint`.
2. Refactor the existing category-count loop so the same classification result
   appends each normalized finding to either the advisory or blocking array.
   Preserve current category behavior, including default advisory `Major`,
   optional blocking `Major`, advisory `Rules violation`, and unknown-category
   safe-fail blocking behavior.
3. Emit `ADVISORY_FINDINGS_JSON=<compact-json-array>` and
   `BLOCKING_FINDINGS_JSON=<compact-json-array>` in clean and needs-fixes
   result paths after the existing count fields. Keep skipped/unavailable paths
   unchanged unless the implementer finds a low-risk way to emit empty arrays
   without disturbing current consumers.
4. Extend `scripts/development-workflow/tests/test-haystack-reviewer.sh` with
   the parser-risk cases listed above. For each array assertion, extract the
   value after the first `=` and parse it with `jq`; do not compare raw escaped
   JSON strings by hand.
5. Update `docs/workflow/development-workflow/integrations/haystack-triage.md`
   with the structured output contract, example output, compatibility note for
   existing count fields, and the explicit deferral that #1114 will consume the
   arrays in `pr-review-loop.sh` summaries.
6. Verify the smoke test runbook manually or by following its command steps.
7. Run:
   `bash scripts/development-workflow/tests/test-haystack-reviewer.sh`
8. Run markdown lint on changed plan/docs/runbook files.
9. Update `CHANGELOG.md` under `[Unreleased]` with:
   `- **Structured Haystack advisory findings** (#1113): Added structured Haystack finding output for downstream review summaries and delegated advisory dispositions.`

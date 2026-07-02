# Implementation Plan: Advisory Disposition Triggers

**Spec**: [Advisory Disposition Triggers](1_1114-advisory-disposition-triggers_specs.md)
**Smoke test runbook**: [Advisory Disposition Triggers](../../../testing/workflow/1114-advisory-disposition-triggers.smoke-test.md)

---

## Summary

**Approach**: Extend `pr-review-loop.sh` so clean reviewer-loop output carries
Haystack structured advisory details, policy-review-required metadata, and an
explicit advisory-disposition-required signal. Update the reviewer-loop summary
to render Haystack advisories alongside existing PR-Agent advisory-label
entries, then update Protocol 93 so post-clean advisory dispositions are
required for advisory count, policy-review-required, or advisory-label evidence.

**Estimated complexity**: M

**Rationale**: The change is localized to one shell workflow script, one test
harness, and one protocol document, but it is parser-risk because compact JSON
must remain valid while moving through shell key-value output and Markdown
summary rendering.

**Dependencies**: #1113 is merged and supplies Haystack structured advisory
fields from `haystack-reviewer.sh`.

## Verification Log

| Check | Command / query | Result |
| ----- | --------------- | ------ |
| Repo revision | `git rev-parse --short HEAD` | `bf1cb6b` |
| Haystack wrapper handoff | `sed -n '2040,2165p' scripts/development-workflow/pr-review-loop.sh` | `run_haystack_review` currently forwards counts but not `ADVISORY_FINDINGS_JSON`, `BLOCKING_FINDINGS_JSON`, or `POLICY_*` metadata. |
| Summary rendering surface | `sed -n '5520,5765p' scripts/development-workflow/pr-review-loop.sh` | `_post_review_summary` renders advisory-label entries only; no structured Haystack advisory section exists. |
| Aggregate output surface | `sed -n '5300,5488p' scripts/development-workflow/pr-review-loop.sh` | Main loop aggregates counts and advisory labels, and reads `POLICY_*` metadata only when platform output exposes it. |
| Existing advisory protocol | `sed -n '660,710p' docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` | Protocol 93 post-clean disposition currently triggers on non-empty `ADVISORY_LABELS` only. |
| Existing tests | `rg -n "haystack|ADVISORY_LABELS|SUGGESTION_COUNT|Automated Reviewer Loop Summary|advisory" scripts/development-workflow/tests/test-pr-review-loop.sh` | The harness already covers Haystack dispatch, policy display snippets, and summary advisory-label rendering; it can be extended for Haystack structured advisories. |

## Layer-by-Layer Changes

### Reviewer Loop Script

- [ ] Update `run_haystack_review` in
      `scripts/development-workflow/pr-review-loop.sh` to forward these
      completed-review fields from `haystack-reviewer.sh` when present:
  - `ADVISORY_FINDINGS_JSON`
  - `BLOCKING_FINDINGS_JSON`
  - `POLICY_STATUS_AVAILABLE`
  - `POLICY_REVIEW_REQUIRED`
  - `POLICY_DISPOSITION`
  - `POLICY_VERDICT`
  - `POLICY_ANALYSIS_STATUS`
  - `POLICY_BUCKET`
  - `POLICY_RATING`
  - `POLICY_HAS_REVIEWER`
  - `POLICY_NEEDS_HUMAN`
  - `DISPLAY_RESULT`
- [ ] Preserve current result, blocking count, advisory count, comment count,
      and skip/escalation behavior for existing consumers.
- [ ] In the main platform aggregation loop, compute
      `ADVISORY_DISPOSITION_REQUIRED=1` when any clean platform output includes
      one or more of:
  - `SUGGESTION_COUNT` greater than zero.
  - `POLICY_REVIEW_REQUIRED=1`.
  - non-empty `ADVISORY_LABELS`.
- [ ] Aggregate Haystack advisory finding JSON from platform output into a
      summary-rendering input without splitting JSON on spaces, commas, pipes,
      equals signs, or newlines inside values.
- [ ] Emit `ADVISORY_DISPOSITION_REQUIRED=<0|1>` in final key-value output so
      orchestrators can trigger Protocol 93 disposition handling without
      re-parsing platform-specific fields.
- [ ] Pass aggregated Haystack advisory data and the disposition-required flag
      to `_post_review_summary`.
- [ ] Render Haystack advisory findings under the existing
      `Advisory findings (non-blocking)` section with enough detail for a
      human disposition:
  - Platform/source label.
  - Category.
  - Summary.
  - Detail when available.
  - Path and line when available.
  - Fix hint when available.
- [ ] Render policy-review-required evidence as an advisory finding entry when
      policy metadata is present but no concrete advisory finding is available.

### Protocol Documentation

- [ ] Update
      `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
      so the post-clean advisory disposition step triggers when:
  - `ADVISORY_DISPOSITION_REQUIRED=1`,
  - `SUGGESTION_COUNT > 0`,
  - `POLICY_REVIEW_REQUIRED=1`, or
  - `ADVISORY_LABELS` is non-empty.
- [ ] Update the procedure to mention Haystack structured advisory entries in
      addition to linked PR-Agent advisory comments.
- [ ] Keep the existing requirement that accepted, deferred, or rejected
      advisories include rationale.

### Tests

- [ ] Extend `scripts/development-workflow/tests/test-pr-review-loop.sh` with
      focused unit coverage for:
  - Haystack clean result with `SUGGESTION_COUNT=1` and
    `ADVISORY_FINDINGS_JSON=[...]` sets `ADVISORY_DISPOSITION_REQUIRED=1`.
  - Haystack structured advisory details render in the summary comment.
  - `POLICY_REVIEW_REQUIRED=1` sets the disposition-required signal even when
    advisory count is zero.
  - Existing PR-Agent `ADVISORY_LABELS` summary behavior remains intact.
- [ ] Keep existing Haystack wrapper tests in
      `scripts/development-workflow/tests/test-haystack-reviewer.sh` unchanged
      unless implementation reveals a wrapper contract mismatch.

### Smoke Test Runbook

- [ ] Add `docs/testing/workflow/1114-advisory-disposition-triggers.smoke-test.md`
      covering all acceptance criteria from the spec.

### Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
      must be updated during implementation.
- [ ] No `docs/project/` updates are required because the project docs are
      placeholders and this feature is workflow-specific.
- [ ] `AGENTS.md` is not required because command routing does not change.
- [ ] `docs/workflow/development-workflow/integrations/haystack-triage.md` is
      not required unless implementation changes the Haystack reviewer output
      contract from #1113.

## Testing Strategy

**Test types**: Shell unit tests, markdown lint, and smoke.

**Key scenarios to test**:

1. Haystack-only clean result with one structured advisory sets
   `ADVISORY_DISPOSITION_REQUIRED=1`, preserves `RESULT=clean`, and keeps the
   advisory count non-blocking. Maps to AC-1, AC-4, AC-6, and AC-7.
2. Haystack structured advisory summary rendering includes category, summary,
   detail, optional source location, and optional fix hint. Maps to AC-4 and
   AC-5.
3. Policy-review-required clean result sets `ADVISORY_DISPOSITION_REQUIRED=1`
   and remains non-blocking. Maps to AC-2 and AC-6.
4. PR-Agent advisory labels continue to render as linked advisory findings and
   still trigger disposition handling. Maps to AC-3 and AC-5.

**Smoke test runbook**:
`docs/testing/workflow/1114-advisory-disposition-triggers.smoke-test.md`

**Regression suite**:

- [ ] `bash scripts/development-workflow/tests/test-pr-review-loop.sh`
- [ ] `bash scripts/development-workflow/tests/test-haystack-reviewer.sh`
- [ ] `shellcheck -S warning -x scripts/development-workflow/pr-review-loop.sh scripts/development-workflow/tests/test-pr-review-loop.sh`
- [ ] `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
- [ ] `npx markdownlint-cli2 "docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md" "docs/specs/developments/20260702095847_1114-advisory-disposition-triggers/2_1114-advisory-disposition-triggers_implementation-plan.md" "docs/testing/workflow/1114-advisory-disposition-triggers.smoke-test.md"`
- [ ] `python3 scripts/lint/markdown-heuristic-lint.py docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md docs/specs/developments/20260702095847_1114-advisory-disposition-triggers/2_1114-advisory-disposition-triggers_implementation-plan.md docs/testing/workflow/1114-advisory-disposition-triggers.smoke-test.md`

### Parser-Risk Addendum

This plan is parser-risk because it moves structured JSON through shell
key-value output and renders it into Markdown summary comments.

**Edge-case enumeration**:

1. Empty or missing `ADVISORY_FINDINGS_JSON` with `SUGGESTION_COUNT=0` leaves
   `ADVISORY_DISPOSITION_REQUIRED=0`.
2. `SUGGESTION_COUNT=1` with one structured Haystack advisory sets
   `ADVISORY_DISPOSITION_REQUIRED=1`.
3. `SUGGESTION_COUNT=0` with `POLICY_REVIEW_REQUIRED=1` sets
   `ADVISORY_DISPOSITION_REQUIRED=1`.
4. Non-empty `ADVISORY_LABELS` sets `ADVISORY_DISPOSITION_REQUIRED=1`.
5. Haystack advisory values containing quotes, backslashes, newlines, pipes,
   commas, and equals signs remain parseable and render without corrupting
   summary structure.
6. Multiple Haystack advisory findings preserve one rendered entry per finding.
7. Advisory entries with missing optional path, line, or fix hint still render
   usable category and summary text.
8. Malformed structured advisory JSON escalates with a specific reason such as
   `advisory_json_parse_failed` rather than silently treating the clean review
   as fully dispositioned.

**Unit test mapping**:

| Edge case | Test file | Planned assertion |
| --------- | --------- | ----------------- |
| 1 | `scripts/development-workflow/tests/test-pr-review-loop.sh` | No advisory evidence leaves the disposition-required signal unset. |
| 2 | `scripts/development-workflow/tests/test-pr-review-loop.sh` | Haystack advisory count and structured array set `ADVISORY_DISPOSITION_REQUIRED=1`. |
| 3 | `scripts/development-workflow/tests/test-pr-review-loop.sh` | Policy-required clean output sets `ADVISORY_DISPOSITION_REQUIRED=1`. |
| 4 | `scripts/development-workflow/tests/test-pr-review-loop.sh` | Existing advisory-label path still sets or implies disposition required. |
| 5 | `scripts/development-workflow/tests/test-pr-review-loop.sh` | Rendered summary preserves special characters in advisory text. |
| 6 | `scripts/development-workflow/tests/test-pr-review-loop.sh` | Two Haystack advisories produce two rendered summary bullets. |
| 7 | `scripts/development-workflow/tests/test-pr-review-loop.sh` | Missing optional fields do not suppress rendered advisory text. |
| 8 | `scripts/development-workflow/tests/test-pr-review-loop.sh` | Malformed structured JSON exits through the explicit escalation path and does not silently misrepresent findings. |

**Suppression semantics**: Not applicable. This feature does not introduce
inline suppression directives.

## Seed Data

No persistent seed data is required. Tests should use deterministic mocked
reviewer-loop platform output and mocked PR summary comment calls.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| JSON corruption in shell key-value parsing | Medium | High | Extract values after the first `=` and parse with `jq`; add special-character tests. |
| Summary becomes noisy for many advisories | Medium | Medium | Render compact bullets with summary first and details on following indented text only when available. |
| Existing PR-Agent advisory flow regresses | Low | High | Keep `ADVISORY_LABELS` rendering intact and add regression coverage. |
| Policy-required clean output lacks concrete finding text | Medium | Medium | Render a policy-review-required advisory entry from policy metadata. |

## Implementation Order

1. Update `run_haystack_review` to forward structured advisory fields,
   structured blocking fields, display override, and `POLICY_*` fields from the
   companion script output.
2. Add aggregate advisory-disposition tracking in the main loop. The mechanism
   should set `ADVISORY_DISPOSITION_REQUIRED=1` when advisory count, policy
   review required, or advisory labels are present.
3. Add helper logic to render Haystack structured advisory findings into the
   existing advisory findings section of `_post_review_summary`.
4. Add an explicit malformed-advisory-JSON escalation path, using a stable
   reason such as `advisory_json_parse_failed`.
5. Add policy-review-required fallback rendering when no concrete advisory
   finding exists but policy metadata requires a disposition.
6. Update final key-value output to include `ADVISORY_DISPOSITION_REQUIRED`.
7. Update Protocol 93's post-clean advisory disposition trigger language to
   include advisory count, policy-review-required, and advisory labels.
8. Add or update `scripts/development-workflow/tests/test-pr-review-loop.sh`
   cases for the parser-risk scenarios listed above.
9. Add the implementation CHANGELOG entry under `[Unreleased]`:
   `- **Advisory disposition triggers** (#1114): Added reviewer-loop advisory disposition triggers for Haystack advisory counts, policy-review-required results, and advisory labels.`
10. Run the regression suite listed in the Testing Strategy and update the smoke
   runbook if implementation details refine the manual verification steps.

## Cross-Section Consistency Log

- `ADVISORY_DISPOSITION_REQUIRED` consistently names the aggregate signal used
  by script output, protocol trigger text, and tests.
- `ADVISORY_FINDINGS_JSON` consistently refers to structured Haystack advisory
  entries produced by #1113 and forwarded by `pr-review-loop.sh`.
- `POLICY_REVIEW_REQUIRED` consistently refers to non-blocking policy attention
  evidence from Haystack `pr-status`.

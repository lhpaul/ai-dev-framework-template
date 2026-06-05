# Reviewer-Failed Label — Implementation Plan

**Spec**: [1_reviewer-failed-label_specs.md](1_reviewer-failed-label_specs.md)
**Smoke test runbook**: [804-reviewer-failed-label.smoke-test.md](../../../../docs/testing/workflow/804-reviewer-failed-label.smoke-test.md)

---

## Summary

**Approach**: Add best-effort `reviewer-failed` label synchronization to `pr-review-loop.sh` based on per-platform reviewer health. The script will create the label idempotently when a failure needs to be shown, apply it when any platform fails, and remove it when the current loop run has no platform-health failure, while preserving existing `needs-fixes` and `ready-for-human-review` semantics.

**Estimated complexity**: M

**Rationale**: The code change is localized to one shell script plus its harness tests, but it must reason over structured per-platform `RESULT` and `REASON` values without confusing healthy reviewer findings (`needs_fixes`, `needs_rerun`) with platform failures.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `ea483b0` |
| Reviewer-loop platform result flow | `rg -n "platform_result_tokens|platform_result=|aggregate_result|_post_review_summary|RESULT=skipped|RESULT=escalate" scripts/development-workflow/pr-review-loop.sh` | The main platform loop records per-platform results before aggregate short-circuiting; label logic must hook into this per-platform loop so skipped/unavailable platforms are not lost when the aggregate remains clean. |
| Existing label mutation pattern | `rg -n "restore_regression_label_if_missing|gh pr edit .*label|gh label" scripts/development-workflow/pr-review-loop.sh scripts/development-workflow/tests/test-pr-review-loop.sh` | `restore_regression_label_if_missing()` provides the closest existing best-effort label pattern and is already directly unit-tested by the shell harness. |
| Haystack transient output contract | `rg -n "pending_timeout|Rating synthesis|REASON=unavailable|REASON=timeout" scripts/development-workflow/haystack-reviewer.sh docs/workflow/development-workflow/integrations/haystack-triage.md scripts/development-workflow/tests/test-haystack-reviewer.sh` | Haystack `pending_timeout` and `Rating synthesis not available` are represented as transient reviewer failures that surface through `pr-review-loop.sh` as `RESULT=escalate` with `REASON=pending_timeout`; unavailable CLI/auth is `RESULT=skipped` with `REASON=unavailable`. |
| Test harness reachability | `sed -n '1,140p' scripts/development-workflow/tests/test-pr-review-loop.sh` | The test harness mocks `gh`, sources `pr-review-loop.sh` in `HARNESS_MODE=1`, and can call helper functions defined before the harness return point. New label helpers should be defined before that return. |

---

## Layer-by-Layer Changes

### Files To Modify

- `scripts/development-workflow/pr-review-loop.sh`
- `scripts/development-workflow/tests/test-pr-review-loop.sh`
- `docs/workflow/development-workflow/integrations/haystack-triage.md`
- `CHANGELOG.md`

### Workflow Script

- [ ] `scripts/development-workflow/pr-review-loop.sh` — add constants for `reviewer-failed`, its label color, and its label description.
- [ ] `scripts/development-workflow/pr-review-loop.sh` — add a helper such as `reviewer_failed_label_required_for_result <result> <reason>` that returns true for:
  - `RESULT=escalate` with any reason, including `timeout`, `thread-check-failed`, `pending_timeout`, and Haystack synthesis errors that map to `pending_timeout`.
  - `RESULT=skipped` only when `REASON` is a non-trivial platform-health failure: `unavailable`, `timeout`, `thread-check-failed`, or `pending_timeout`.
  - Not true for `RESULT=skipped` with `REASON=not_configured`, `RESULT=needs_fixes`, `RESULT=needs_rerun`, or `RESULT=clean`.
- [ ] `scripts/development-workflow/pr-review-loop.sh` — add `ensure_reviewer_failed_label_exists` and `sync_reviewer_failed_label <pr> <required>` helpers. Both helpers must be best-effort: warn and continue on GitHub API failures, never change the reviewer-loop exit code.
- [ ] `scripts/development-workflow/pr-review-loop.sh` — track a `reviewer_failed_required=0|1` flag inside the per-platform loop immediately after parsing each platform's `RESULT` and `REASON`. This is the enforcement mechanism that preserves skipped/unavailable failures even when aggregate result would otherwise become `clean`.
- [ ] `scripts/development-workflow/pr-review-loop.sh` — call `sync_reviewer_failed_label` on every terminal path after all platform state for the run is known and before exit:
  - Apply/create the label when `reviewer_failed_required=1`.
  - Remove the label when `reviewer_failed_required=0`, including runs that end with `clean`, `needs_fixes`, `needs_rerun`, or `skipped/not_configured`.
- [ ] `scripts/development-workflow/pr-review-loop.sh` — include a short summary note or key-value line when the label sync is attempted, if this can be done without destabilizing existing output parsers.

### Tests

- [ ] `scripts/development-workflow/tests/test-pr-review-loop.sh` — extend the mock `gh` stub to distinguish `gh label view`, `gh label create`, `gh pr edit --add-label`, and `gh pr edit --remove-label` calls through existing `MOCK_GH_CALL_LOG` logging.
- [ ] `scripts/development-workflow/tests/test-pr-review-loop.sh` — add a new test area for `reviewer-failed` label behavior that directly calls the new helpers in harness mode.
- [ ] `scripts/development-workflow/tests/test-pr-review-loop.sh` — test per-platform classification inputs for all parser-risk cases listed below.

### Documentation

- [ ] `docs/workflow/development-workflow/integrations/haystack-triage.md` — document that `pending_timeout` / synthesis-error reviewer failures cause `pr-review-loop.sh` to apply `reviewer-failed` until a later clean Haystack run removes it.
- [ ] `CHANGELOG.md` — add `- **Reviewer failure label** (#804): Adds a self-healing reviewer-failed PR label when automated reviewer platforms time out, escalate, or are unavailable.` under `[Unreleased]` in the implementation PR.

---

## Testing Strategy

**Test types**: Shell unit tests, markdown lint, smoke/manual GitHub-label validation.

**Key scenarios to test**:

1. `RESULT=escalate` with `REASON=timeout` applies `reviewer-failed` (AC-1).
2. `RESULT=escalate` with `REASON=pending_timeout` applies `reviewer-failed` for Haystack pending/synthesis timeout behavior (additional Haystack ACs).
3. `RESULT=skipped` with `REASON=unavailable` applies `reviewer-failed` (AC-1).
4. `RESULT=skipped` with `REASON=not_configured` does not apply the label and removes a stale label (AC-2, AC-3).
5. A clean run with no platform failure removes an existing `reviewer-failed` label (AC-2).
6. `RESULT=needs_fixes` and `RESULT=needs_rerun` do not keep the label applied when no platform-health failure occurred (AC-2).
7. The label can coexist with `ready-for-human-review` and `needs-fixes` because the script only adds/removes `reviewer-failed` (AC-4).
8. Missing label creation is idempotent and non-blocking (AC-5).

**Smoke test runbook**: `docs/testing/workflow/804-reviewer-failed-label.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-pr-review-loop.sh`
- `bash scripts/development-workflow/tests/test-haystack-reviewer.sh` if Haystack documentation or reason mapping is edited

### Parser-Risk Addendum

This plan is parser-risk because it classifies structured `RESULT=` and `REASON=` key-value output from reviewer platform handlers.

**Edge-case enumeration**:

1. `RESULT=escalate`, `REASON=timeout` must require the label.
2. `RESULT=escalate`, empty or unknown `REASON` must still require the label.
3. `RESULT=escalate`, `REASON=pending_timeout` must require the label.
4. `RESULT=skipped`, `REASON=unavailable` must require the label.
5. `RESULT=skipped`, `REASON=thread-check-failed` must require the label.
6. `RESULT=skipped`, `REASON=not_configured` must not require the label.
7. `RESULT=clean`, any reason must not require the label.
8. `RESULT=needs_fixes` must not require the label.
9. `RESULT=needs_rerun` must not require the label.
10. Multiple platform results in one run must OR together: one failing platform keeps `reviewer_failed_required=1` even if a later or earlier platform is clean.

**Unit test mapping**:

- Add tests in `scripts/development-workflow/tests/test-pr-review-loop.sh`.
- Map cases 1 through 9 to direct helper tests for `reviewer_failed_label_required_for_result`.
- Map case 10 to a shell-level accumulator test that simulates two platform classifications and asserts the accumulated flag remains `1`.
- Add label sync tests:
  - Required label: `gh label create` is attempted when `gh label view` fails, then `gh pr edit --add-label reviewer-failed` is called.
  - Not required: `gh pr edit --remove-label reviewer-failed` is called.
  - Label create failure: helper returns success and logs a warning, preserving the loop exit contract.

**Suppression semantics**: Not applicable. No inline suppression directives are introduced.

---

## Seed Data

No seed data is required.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/haystack-triage.md` — document label behavior for `pending_timeout`, unavailable, and later clean self-heal.
- [ ] `CHANGELOG.md` — add the `Reviewer failure label` entry listed above.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The implementation relies only on aggregate result and misses `skipped/unavailable` because aggregate becomes clean. | Medium | High | Track `reviewer_failed_required` inside the per-platform loop before aggregate result normalization. |
| Label API failure blocks the reviewer loop. | Low | High | Keep label creation/add/remove best-effort and return success from label helpers regardless of API failure. |
| `not_configured` platforms are incorrectly treated as failures. | Medium | Medium | Unit-test `skipped/not_configured` as a negative parser-risk case. |
| The label is not removed after healthy `needs_fixes` findings. | Medium | Medium | Unit-test `needs_fixes` and `needs_rerun` as non-failure cases and remove stale labels whenever no platform-health failure occurred. |

---

## Code Samples

No production-ready code samples are required. Any shell snippets added during implementation must remain bash 3.2 compatible and pass ShellCheck.

---

## Implementation Order

1. Add constants and helper functions in `scripts/development-workflow/pr-review-loop.sh` before the `HARNESS_MODE` return point:
   - `REVIEWER_FAILED_LABEL="reviewer-failed"`
   - `REVIEWER_FAILED_LABEL_COLOR` with a distinct non-conflicting color
   - `reviewer_failed_label_required_for_result`
   - `ensure_reviewer_failed_label_exists`
   - `sync_reviewer_failed_label`
2. In the main platform loop, parse `_reviewer_failed_reason` from each platform output and OR the helper result into `reviewer_failed_required`. Do this before any branch that may short-circuit on `needs_fixes` or `escalate`.
3. Call `sync_reviewer_failed_label "$pr_number" "$reviewer_failed_required"` on all terminal paths where `pr_number` is present:
   - No platforms configured (`skipped/not_configured`) removes stale label.
   - Clean removes stale label.
   - Needs fixes removes stale label unless a prior platform-health failure was recorded.
   - Needs rerun removes stale label unless a platform-health failure was recorded.
   - Escalate applies label.
4. Add Area 12 tests to `scripts/development-workflow/tests/test-pr-review-loop.sh` for parser-risk classification and label add/remove/create behavior.
5. Update `docs/workflow/development-workflow/integrations/haystack-triage.md` with the `reviewer-failed` behavior for `pending_timeout`, unavailable, and later clean self-heal.
6. Update `CHANGELOG.md` under `[Unreleased]` with:
   `- **Reviewer failure label** (#804): Adds a self-healing reviewer-failed PR label when automated reviewer platforms time out, escalate, or are unavailable.`
7. Run validation:
   - `bash scripts/development-workflow/tests/test-pr-review-loop.sh`
   - `bash scripts/development-workflow/tests/test-haystack-reviewer.sh`
   - `shellcheck --severity=warning scripts/development-workflow/pr-review-loop.sh scripts/development-workflow/tests/test-pr-review-loop.sh scripts/development-workflow/haystack-reviewer.sh scripts/development-workflow/tests/test-haystack-reviewer.sh`
   - `npx markdownlint-cli2 "docs/specs/developments/20260602154734_reviewer-failed-label/2_reviewer-failed-label_implementation-plan.md" "docs/testing/workflow/804-reviewer-failed-label.smoke-test.md" "docs/workflow/development-workflow/integrations/haystack-triage.md" "CHANGELOG.md"`
   - `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`


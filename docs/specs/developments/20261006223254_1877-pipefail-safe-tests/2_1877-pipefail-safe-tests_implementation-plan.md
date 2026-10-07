# Pipefail-safe test assertions — Implementation Plan

**Issue**: [#1877](https://github.com/lhpaul/ai-dev-framework-template/issues/1877)
**Spec**: [Approved spec](1_1877-pipefail-safe-tests_specs.md)
**Smoke test runbook**: [Runbook](../../../testing/workflow/1877-pipefail-safe-tests.smoke-test.md)

## Summary

**Approach**: Replace the affected text assertions without changing their match
expectations. Extend the existing diff-based shell guard with SH006 for
premature-exit grep in printf-fed test pipelines, using the existing diagnostics
and suppression mechanism. No new service, workflow lifecycle rule or shell parser.

**Estimated complexity**: S. The implementation is a mechanical test sweep and a
bounded heuristic lint extension; its file count exceeds Fast Track eligibility.
**Dependencies**: None remaining; PR #1896 and spec PR #1897 are merged.
**Template fit**: Pass — shell tests and lint belong to the template's own
Bash/Python toolchain and benefit consumers independent of their application stack.

## Verification Log

Evidence revision: `e1ca032561a9b6c8fcfb88f9cf2776fb2f2e3986`.

| Check | Reproducible command or query | Result |
| --- | --- | --- |
| Test-tree candidates | `rg -n 'printf.*\|.*grep\s+-[A-Za-z]*q' scripts/development-workflow/tests scripts/lint/tests` | 130 candidate lines in 32 files; file enumeration below. This is a line inventory, not a frozen count of edits. |
| Existing guard | `rg -n 'CHECKED_PATH|def lint_logical_line|def logical_lines|SUPPRESSION_DIRECTIVE' scripts/lint/workflow-shell-guard-lint.py` | Diff-based rules SH001–SH005 and logical continuation joining already exist. |
| Lint integration | `rg -n 'workflow-shell-guard-lint' .github/workflows/shellcheck.yml scripts/lint/tests/test-workflow-shell-guard-lint.sh scripts/lint/README.md` | CI invokes the existing linter and its unit suite; no job or invocation change is needed. |
| Help regression target | `rg -n 'help_documents_skip_reason|_1574_help' scripts/development-workflow/tests` | Reported check now lives in test-pr-review-loop-pr-agent-coderabbit.sh after suite splitting. |
| Synchronization | `rg -n 'scripts/lint/|scripts/development-workflow/' sync-manifest.yaml` | Existing directory sync surfaces carry lint and workflow tests. |
| Consumer enumeration | `rg -n 'workflow-shell-guard-lint' .github scripts docs .agents/skills .codex/skills .claude .cursor AGENTS.md REVIEW.md` | Runtime CI: shellcheck.yml lint-test step then lint step. Developer protocol paths and mirrored developer instructions invoke the same CLI; README and runbooks reference it. CLI shape and SH001–SH005 behavior remain unchanged. |

The implementation reruns the candidate query over all shell tests before editing
and before readiness, also checking continuations and long quiet-option spellings.
The current inventory is indicative and may grow when equivalent variants are found.

## Cross-Cutting Operational Assumption Check

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact owner and base | Current repository; develop | Authorized invocation, workflow manifest and live spec PR #1897 | 2026-10-07 UTC, evidence revision above | Item #1877; merged spec #1897 and its target base | Verified |
| Consumer runtime | Bash 3.2 and existing Python 3 lint runtime | Protocol 03 shell checklist and existing linter | Same revision | Changed test and lint surfaces for #1877 | Verified |

No deployment environment, secret, external account or shared resource is changed.
Before implementation, reread these sources and record Still valid for both rows.

## Layer-by-Layer Changes

### Shell tests — AC1, AC2, AC4

For every candidate below, preserve assertion names, expected values and grep
matching options. Direct single-string printf inputs use a here-string on grep.
Filtered or multi-stage pipelines use a grep that consumes its entire input with
output redirected to /dev/null, retaining pipefail's genuine upstream failures.
Executable mocks and shared helpers receive the same correction. Do not add exit
141 forgiveness or suppress failed assertions.

Files to modify, based on the live candidate inventory:

- `scripts/development-workflow/tests/lib/pr-review-loop-harness.sh`
- `scripts/development-workflow/tests/test-actions-cost-audit.sh`
- `scripts/development-workflow/tests/test-apply-readiness-labels.sh`
- `scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh`
- `scripts/development-workflow/tests/test-check-tracker-merge-mapping.sh`
- `scripts/development-workflow/tests/test-expensive-reviewer-gate.sh`
- `scripts/development-workflow/tests/test-framework-mode-type-routing.sh`
- `scripts/development-workflow/tests/test-local-ai-reviewer.sh`
- `scripts/development-workflow/tests/test-local-http-review-command.sh`
- `scripts/development-workflow/tests/test-pr-review-loop-cycles-labels.sh`
- `scripts/development-workflow/tests/test-pr-review-loop-failure-paths-1.sh`
- `scripts/development-workflow/tests/test-pr-review-loop-failure-paths-3.sh`
- `scripts/development-workflow/tests/test-pr-review-loop-failure-paths-4.sh`
- `scripts/development-workflow/tests/test-pr-review-loop-no-verdict-yet.sh`
- `scripts/development-workflow/tests/test-pr-review-loop-pr-agent-coderabbit.sh`
- `scripts/development-workflow/tests/test-pr-review-loop-release-bugbot.sh`
- `scripts/development-workflow/tests/test-pr-review-loop-staged-gates.sh`
- `scripts/development-workflow/tests/test-pr-review-loop.sh`
- `scripts/development-workflow/tests/test-review-doctrine-lint.sh`
- `scripts/development-workflow/tests/test-reviewer-effectiveness-report.sh`
- `scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh`
- `scripts/development-workflow/tests/test-run-epic-audit-trail.sh`
- `scripts/development-workflow/tests/test-run-epic-delegated-gate.sh`
- `scripts/development-workflow/tests/test-run-epic-policy-recommender.sh`
- `scripts/development-workflow/tests/test-run-work-router.sh`
- `scripts/development-workflow/tests/test-select-test-suites.sh`
- `scripts/development-workflow/tests/test-sync-template-apply-modes.sh`
- `scripts/development-workflow/tests/test-validate-closing-keyword-scope.sh`
- `scripts/development-workflow/tests/test-workflow-batch-lanes.sh`
- `scripts/development-workflow/tests/test-workflow-batch-overlap.sh`
- `scripts/development-workflow/tests/test-workflow-branch-filters.sh`
- `scripts/development-workflow/tests/test-worktree-recipe.sh`

In test-pr-review-loop-pr-agent-coderabbit.sh, extend the help assertions with
matching and absent-text cases using captured real help plus at least 1 MiB of
padding. Assert the safe read succeeds for a match near the beginning and rejects
an absent token. Keep the existing help checks intact.

### Existing shell guard — AC3, AC5

- `scripts/lint/workflow-shell-guard-lint.py`: Add SH006 for added shell-test lines
  containing a printf-fed pipeline ending in quiet grep. Scan test directories
  under scripts, including shared helpers; keep SH001–SH005 scoped as before.
  Widen diff collection/line selection only enough to examine these test paths.
  Recognize short-option clusters containing q, --quiet and --silent before the
  grep pattern, including filtered pipelines and existing continuation joining.
  Stop option interpretation at -- or a positional pattern, and skip arguments
  to -e/-f/--regexp/--file so pattern text is not mistaken for a quiet flag.
  Do not flag production non-test paths, file/here-string reads or consuming grep.
- `scripts/lint/tests/test-workflow-shell-guard-lint.sh`: Exercise the edge classes
  in the testing table below through the real diff CLI, including path and line
  diagnostics and git diff mode. Use runtime-materialized fixture placeholders
  for intentionally unsafe pipelines so the linter's own tests stay safe.

This remains a line-oriented heuristic, not proof of arbitrary shell syntax.
Dynamic command construction and arbitrary multiline commands without explicit
backslash continuations remain outside this rule's detection guarantee. Whole-line
comments are ignored; literal examples that resemble commands use the existing
local exception mechanism or materialized fixture text.

## Parser-Risk Edge Cases and Unit Test Mapping

All scanner cases map to `scripts/lint/tests/test-workflow-shell-guard-lint.sh`;
large-output matching maps to the help regression suite named above. Enumeration
is indicative; coverage classes must remain even if case tables are consolidated.

| Input class | Expected result / unit coverage |
| --- | --- |
| Direct printf to grep -q | SH006; diagnostic path and line asserted |
| Short clusters -Fq, -qiE and separated flags | SH006 for each flag shape |
| Long --quiet / --silent | SH006 |
| printf through jq or consuming grep to quiet grep | SH006 |
| Backslash continuation | SH006 at the joined command's first added line |
| Two unsafe assertions on one line | Report the line, without losing either recognition path |
| Here-string, file input, consuming grep redirected to /dev/null | Pass |
| -q as grep pattern after --, -e or --regexp | Pass |
| Comment, non-test production path and intentional fixture data | Pass or explicit fixture-only suppression |
| Existing SH001–SH005 and multiple suppressions | Existing behavior retained; only named rules suppressed |
| Large output with early match and absent text | Correct yes/no result under pipefail |

**Suppression semantics**: `# workflow-shell-guard: allow SH006 - <reason>` on
that logical line only. Continuation-line comments belong to the joined logical
line. Multiple directives independently suppress their named rules, matching
existing has_suppression behavior. No global or previous-line exemption is added.

## Testing Strategy

Run the affected workflow suites and the existing lint unit suite, checking their
explicit pass/fail totals rather than exit 0 alone. Run Bash 3.2 syntax checks and
ShellCheck on every changed shell file. Run shell guard against the committed PR
diff, markdown lint/heuristics, and git diff --check.

For each new enforcement path (direct and git-diff CLI), plant an unsafe assertion
at a concrete temporary test file/line, observe SH006 with exit 1, correct that
same assertion and observe exit 0. Record commands and both results in the
implementation PR. Do not rely on a description-only lint proof.

**Residual strategy**: Save a fresh all-test-tree pattern audit in the PR evidence,
with remaining groups classified as completed, explicitly out of scope or linked
follow-up. Feed structured evidence to scope-residual-gate.sh before readiness.
An untreated executable test assertion is a blocker. Production matches are out
of scope by the approved spec; intentional lint fixtures are data, not assertions.

**Seed data**: No database or product E2E seed applies. Versioned shell fixtures
are generated deterministically in the existing test harness temporary directory.
The repository's E2E workflow is a placeholder, not a product fixture suite.
**Concurrent-event-source classifier**: Not applicable — no new shared-state
listeners, timers, asynchronous handlers or mutable concurrent runtime are added.
**Cross-cutting checklist classifier**: Not applicable — extends one existing
validation mechanism, without changing reviewer or implementation policy checklists.

## Documentation Updates

- `scripts/lint/README.md`: Document SH006 scope, remedies, exception syntax and
  heuristic limitations beside existing rules.
- `changelog.d/1877.fixed.pipefail-safe-tests.md`: Add a finished release-note bullet
  in the existing bold-title format.
- No project architecture, agent mirrors or workflow protocol changes: the current
  lint command, runtime contract and reviewer checklist already cover this change.

## Plan Authoring Rigor Record

- Rule 1: Not applicable — no external-output distribution or closed-world
  external-producer claim; candidates come from repository text at the recorded revision.
- Rule 2: Satisfied — one authoritative instruction per change above; testing
  and runbook sections reference those decisions rather than redefine them.
- Rule 3: Satisfied — candidate-line/file counts derive from the Verification Log
  query and the file list is enumerated above.
- Rule 4: Satisfied — each existing-component assertion carries its direct search.
- Rule 5: Satisfied — existing CLI consumers are enumerated by the recorded search;
  the ShellCheck CI job runs unit tests then the extended guard, whose nonzero
  finding exit fails that step. Developer CLI calls receive the same new SH006
  diagnostic; documentation references retain the unchanged command.
- Rule 6: Satisfied — SH006 binds only to added shell-test logical lines; regression
  and residual obligations bind to this implementation PR and are discharged
  before readiness by the tests and scope gate above.

## Risks and Mitigations

| Risk | Mitigation |
| --- | --- |
| Match semantics change during sweep | Preserve options and expected values; review each diff; run affected suites. |
| Heuristic false positives on fixture text | Materialized fixture placeholders or local reasoned exception; negative cases. |
| Scanner silently misses quiet-option variants | Unit cases cover option clusters, long names, intermediate filters and continuations. |
| Consumer compatibility | Bash 3.2 checks, unchanged CLI and existing sync directories; no app-specific changes. |

## Implementation Order

1. Reverify plan assumptions and rerun the complete candidate audit on the implementation branch.
2. Correct the test assertions and add large-output help regressions; validate and
   commit this coherent sub-part immediately.
3. Add SH006 and its unit/proof fixtures; document the rule in the lint README,
   add the changelog fragment, validate and commit this coherent sub-part.
4. Run the runbook and residual gate; record proof evidence and complete
   pre-submission self-review before opening the implementation draft PR.
5. Complete current-head reviewer/CI gates and delegated merge audit; retain
   branches as required by the authorized session instructions.

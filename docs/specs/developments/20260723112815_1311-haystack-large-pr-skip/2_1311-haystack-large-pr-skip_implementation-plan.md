# Haystack Large-PR Analysis Skip - Implementation Plan

**Spec**: [1_1311-haystack-large-pr-skip_specs.md](1_1311-haystack-large-pr-skip_specs.md)
**Smoke test runbook**: [1311-haystack-large-pr-skip.smoke-test.md](../../../testing/workflow/1311-haystack-large-pr-skip.smoke-test.md)

---

## Summary

**Approach**: Teach the Haystack adapter to recognize an explicit file-limit
decline on the current pull-request head as a terminal, healthy skip. Probe that
authoritative signal during each normal polling observation, emit a distinct
skip reason and display value, and let the existing reviewer-loop aggregation
and history machinery preserve the result without weakening any other gate.

**Estimated complexity**: M

**Rationale**: The behavior is localized to the Haystack adapter, but correctness
depends on strict current-attempt correlation, fail-closed text classification,
reviewer aggregation, durable summary history, and synchronized operator
guidance.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse HEAD` | `21f23e39a88ccb2bcbad19752c731ffbd7690ad0` |
| Existing artifact state | `find docs/specs/developments/20260723112815_1311-haystack-large-pr-skip -maxdepth 1 -type f -print` | The approved spec exists; no implementation plan existed before this branch. |
| Existing Haystack polling | `rg -n "fetch_haystack_check_run_json\|emit_haystack_check_run_result\|HAYSTACK_POLL_INTERVAL" scripts/development-workflow/haystack-reviewer.sh` | The adapter already fetches the latest `Haystack / Review` check run for the current PR head, but only uses it as a late fallback and has no file-limit classification. |
| Existing aggregate behavior | `rg -n "run_haystack_review\|DISPLAY_RESULT\|reviewer_failed_label_required_for_result" scripts/development-workflow/pr-review-loop.sh` | Companion exit `3` maps to a permissive platform skip; display overrides are preserved in platform tokens; only enumerated unhealthy skip reasons require `reviewer-failed`. |
| Existing durable history | `rg -n "reviewer_loop_history.v1\|_post_review_summary" scripts/development-workflow/pr-review-loop.sh` | The script-owned summary appends one history entry per completed loop iteration and stores per-platform display tokens in the entry. |
| Live oversized-PR evidence | `gh api repos/zeki-cl/zeki-platform/commits/e135dff4fdfb69b0f2432b5f233e3be348647ef1/check-runs` and `gh api repos/zeki-cl/zeki-platform/issues/449/comments` | PR `zeki-cl/zeki-platform#449` changed 168 files. Its current-head `Haystack / Review` check completed with `action_required`, title `PR exceeds the Haystack analysis limit`, and summary stating 168 files exceeded the 100-file limit. The Haystack bot also posted a head-correlated analysis-start comment followed by `Analysis Skipped` with the same explicit reason. |
| Existing focused tests | `rg -n "check.run\|haystack platform\|reviewer_loop_history.v1" scripts/development-workflow/tests/test-haystack-reviewer.sh scripts/development-workflow/tests/test-pr-review-loop.sh` | The Haystack harness already mocks current-head check runs; the reviewer-loop harness covers adapter mapping, display tokens, aggregate outcomes, labels, and durable history. |
| Sync-template mirrors | `rg -n "Run the automated reviewer loop" .claude/commands/sync-template.md .cursor/commands/sync-template.md .claude/skills/sync-template.md` and `rg -n "automated reviewer loop" .codex/skills/workflow-sync-template/SKILL.md .agents/skills/workflow-sync-template/SKILL.md` | Three full command/skill bodies and the Codex plus `.agents` wrapper guidance describe the same post-PR reviewer/readiness sequence. |
| Design assets | `find docs/specs/developments/20260723112815_1311-haystack-large-pr-skip -maxdepth 2 -type d -name assets` | None. This is a shell workflow and documentation change with no UI surface. |
| Template fit | `sed -n '1,80p' .ai-dev-workflow.yaml` | The repository is the framework template and the requested reviewer behavior is generic across downstream repositories. |

The live PR query is diagnostic evidence only. Implementation tests must use
deterministic local fixtures and must not depend on `zeki-cl/zeki-platform#449`
remaining available.

---

## Layer-by-Layer Changes

### Haystack Adapter

- [ ] Update `scripts/development-workflow/haystack-reviewer.sh` with a
  fail-closed classifier for the current-head `Haystack / Review` check run.
  Accept only a completed check whose title/summary explicitly says the PR
  exceeds Haystack's analysis/file limit. Do not infer the result from
  `action_required`, a generic `Analysis Skipped` string, numeric file count
  alone, or unrelated comments. Maps to BR-1, AC-1, and AC-7.
- [ ] Emit the stable terminal contract
  `RESULT=skipped`, `REASON=analysis_skipped_file_limit`,
  `DISPLAY_RESULT=skipped (analysis file limit)`, zero finding counts, and the
  existing check-run metadata, then exit `3`. This distinguishes limited
  coverage from both a clean Haystack analysis and an unhealthy reviewer
  failure. Maps to BR-3, AC-1, and AC-5.
- [ ] Probe the current-head check at the beginning of each poll observation and
  once more after a transient triage response before sleeping. A skip that
  appears during a triage call must therefore terminate by the next standard
  observation boundary instead of consuming the remaining
  `LARGE_DIFF_MAX_WAIT` budget. Maps to BR-2, BR-7, AC-2, and AC-6.
- [ ] Reuse `fetch_haystack_check_run_json()` so evidence is bound to the
  current PR head SHA. Do not add a loose all-comments fallback: the observed
  bot comment is useful corroboration, but the current-head check run is the
  authoritative machine-readable signal and automatically rejects prior-head
  comments. Maps to BR-1 and AC-7.
- [ ] Preserve the existing completed-review, pending, authentication,
  unavailable, findings, and timeout classifications whenever the exact
  file-limit predicate does not match.

### Reviewer-Loop Aggregation and History

- [ ] Update the `run_haystack_review()` exit-contract comments in
  `scripts/development-workflow/pr-review-loop.sh` and add focused mapping
  assertions for `analysis_skipped_file_limit`. The existing exit-`3` mapping
  should keep the platform permissively skipped while forwarding its reason
  and display override. Maps to BR-3 and AC-3.
- [ ] Verify in code and tests that
  `reviewer_failed_label_required_for_result()` does not classify
  `analysis_skipped_file_limit` as unhealthy. The new reason must not add or
  retain `reviewer-failed`; timeout, unavailable, authorization, and other
  existing unhealthy results remain unchanged.
- [ ] Exercise the real aggregate loop with Haystack skipped plus:
  (a) every other reviewer clean/permissibly skipped and (b) another reviewer
  blocking or escalated. Only case (a) may finish clean; case (b) must preserve
  the existing blocker and readiness prohibition. Maps to BR-4, BR-5, AC-3,
  and AC-4.
- [ ] Verify the script-owned `### Automated Reviewer Loop Summary` records the
  distinct Haystack display token in `reviewer_loop_history.v1`. A same-head
  rerun must append another stable terminal observation without waiting for
  Haystack or replacing prior history. Maps to BR-6, BR-7, AC-5, and AC-6.

### Documentation and Operator Guidance

- [ ] Update
  `docs/workflow/development-workflow/integrations/haystack-triage.md` with the
  exact current-head evidence requirement, terminal output contract, prompt
  polling behavior, healthy-skip label semantics, and rejection of ambiguous
  or stale text.
- [ ] Update
  `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
  to explain that the file-limit skip is permissive only for Haystack, remains
  visible in the workflow-owned summary/history, and never bypasses another
  reviewer, CI, thread-resolution, or readiness gate.
- [ ] Update the full sync-template guidance bodies at
  `.claude/commands/sync-template.md`,
  `.cursor/commands/sync-template.md`, and
  `.claude/skills/sync-template.md` beside Step 6.2. Explain that oversized
  sync PRs may receive the recognized Haystack skip by design, but the
  reviewer loop must still finish and every other configured reviewer, CI,
  unresolved-thread, regression, and readiness check remains mandatory.
- [ ] Update `.codex/skills/workflow-sync-template/SKILL.md` and
  `.agents/skills/workflow-sync-template/SKILL.md` with the same concise
  invariant because both wrappers independently summarize the terminal
  post-PR sequence. Keep the full command bodies behaviorally aligned.
- [ ] Add the implementation PR's entry under `[Unreleased]` in
  `CHANGELOG.md`; do not add it to this plan PR.

### Database / API / UI / Infrastructure

- [ ] None. The change adds no application data, service endpoint, user
  interface, workflow configuration key, or external dependency.

---

## Decision-Gate Consistency Matrix

| Current-attempt evidence | Haystack result | Other reviewer/gate state | Aggregate action | Durable evidence |
| --- | --- | --- | --- | --- |
| Completed current-head check explicitly says the PR exceeds Haystack's analysis/file limit | `Skipped` / `analysis_skipped_file_limit` | All other reviewers clean or permissibly skipped; later gates pass | Stop Haystack polling and continue the normal readiness sequence | Summary platform token plus new `reviewer_loop_history.v1` entry |
| Same authoritative skip | `Skipped` / `analysis_skipped_file_limit` | Any reviewer blocks/escalates or CI/thread/readiness gate fails | Preserve that blocker; do not apply readiness | Summary/history retain both Haystack skip and the blocking outcome |
| Generic `action_required`, generic skip text, unrelated human comment, or prior-head evidence | Existing classification | Any | Continue normal polling/classification; never apply the exception | Existing summary/history behavior |
| Same authoritative skip on rerun | Same terminal skip | Same or updated remaining gates | Reclassify promptly without a new extended Haystack wait | Append a stable new iteration; retain earlier history |

---

## Testing Strategy

**Test types**: Shell unit/integration harnesses, documentation mirror checks,
markdown lint, shell static analysis, and the workflow smoke runbook.

### Focused Automated Scenarios

1. A completed current-head check with `action_required`, the observed title,
   and an explicit `168 > 100` summary exits `3` with the new result, reason,
   display, counts, and check metadata. Maps to AC-1.
2. A transient CLI response followed by the authoritative check skips before
   the harness records a sleep or second full polling window. Maps to AC-2.
3. A same-head rerun returns the same terminal skip with one observation in
   each invocation. Maps to AC-6.
4. `action_required` with parseable findings, generic `Analysis Skipped`,
   file-count-only text, an unrelated limit phrase, an incomplete check, and a
   check available only on a prior head do not match the exception. Maps to
   AC-7.
5. The reviewer-loop adapter forwards the exact reason/display, does not
   require `reviewer-failed`, and produces aggregate clean when all other
   reviewers are clean/permissibly skipped. Maps to AC-3.
6. Another platform's `needs_fixes` or escalation remains the aggregate result
   when Haystack has the file-limit skip. Maps to AC-4.
7. The workflow-owned summary and its `reviewer_loop_history.v1` payload retain
   the distinct skip display across two reruns. Maps to AC-5 and AC-6.
8. Documentation assertions confirm all full sync-template bodies and both
   wrapper surfaces state that other gates remain mandatory. Maps to AC-8.

### Parser-Risk Addendum

The change is parser-risk because it classifies structured check-run JSON and a
bounded piece of externally generated prose.

- **Boundary variants**: Accept the observed `PR exceeds the Haystack analysis
  limit` title and explicit summaries with variable file counts and normal
  whitespace/case variation. Require both an exceeded/over-limit relationship
  and an analysis/file-limit subject.
- **Negative lookalikes**: Reject `action_required` alone, `Analysis Skipped`
  alone, a generic timeout, “near the file limit,” a human-authored comment, or
  text saying analysis exceeded a time limit.
- **Multiple occurrences**: If title and summary both contain the file-limit
  evidence, emit one terminal result.
- **Nested/overlapping outcomes**: If a matching current-head file-limit check
  also contains generic failure text, the explicit terminal skip wins for
  Haystack; if findings are present without the exact limit predicate, existing
  blocking parsing wins.
- **Current-attempt boundary**: A matching check on a previous SHA or a stale
  bot comment must not match because the fetch is scoped to the current head.
- **Suppression semantics**: Not applicable. There is no inline suppression or
  user-authored override.

Add these cases to
`scripts/development-workflow/tests/test-haystack-reviewer.sh`; add aggregate,
label, display, and history cases to
`scripts/development-workflow/tests/test-pr-review-loop.sh`.

### Concurrent-Event-Source Addendum

Not applicable. The adapter polls synchronously and adds no listener, socket,
timer callback, queue, or shared mutable state across execution contexts.

### Commands

- `bash scripts/development-workflow/tests/test-haystack-reviewer.sh`
- `bash scripts/development-workflow/tests/test-pr-review-loop.sh`
- `bash scripts/development-workflow/tests/test-sync-template-apply-modes.sh`
- `shellcheck scripts/development-workflow/haystack-reviewer.sh scripts/development-workflow/pr-review-loop.sh`
- `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
- `npx markdownlint-cli2 "docs/workflow/development-workflow/integrations/haystack-triage.md" "docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md" "docs/testing/workflow/1311-haystack-large-pr-skip.smoke-test.md" ".claude/commands/sync-template.md" ".cursor/commands/sync-template.md" ".claude/skills/sync-template.md" ".codex/skills/workflow-sync-template/SKILL.md" ".agents/skills/workflow-sync-template/SKILL.md"`

---

## Seed Data

No application seed data is required. The focused shell harnesses should create
current-head, prior-head, transient, ambiguous, clean-aggregate, and
blocked-aggregate fixtures in temporary directories and remove them on exit.

---

## Smoke-Test Scope

The implementation must keep
`docs/testing/workflow/1311-haystack-large-pr-skip.smoke-test.md` synchronized
with final helper names and output fields. The runbook uses local mock fixtures
for deterministic classification and aggregation. A live disposable PR is
optional corroboration, not a required or mutating dependency.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/haystack-triage.md`
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
- [ ] `.claude/commands/sync-template.md`
- [ ] `.cursor/commands/sync-template.md`
- [ ] `.claude/skills/sync-template.md`
- [ ] `.codex/skills/workflow-sync-template/SKILL.md`
- [ ] `.agents/skills/workflow-sync-template/SKILL.md`
- [ ] `docs/testing/workflow/1311-haystack-large-pr-skip.smoke-test.md`
- [ ] `CHANGELOG.md` under `[Unreleased]` in the implementation PR

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Broad text matching converts a real review failure into a skip | Medium | High | Require a completed current-head check plus explicit exceeded-limit semantics; cover negative lookalikes. |
| The adapter notices the skip only after the extended timeout | Medium | High | Probe every observation and after transient triage output before sleeping; assert call/sleep counts. |
| A permissive skip masks another reviewer or readiness blocker | Low | High | Exercise full aggregate paths and keep post-review CI/thread/readiness contracts unchanged. |
| Operators mistake the skip for completed code review | Medium | Medium | Emit and document `Skipped` with a distinct file-limit reason and visible history token. |
| Sync-template guidance drifts across command/skill mirrors | Medium | Medium | Update every enumerated full body and wrapper; extend the existing sync-template documentation harness. |

---

## Implementation Order

1. Add the strict current-head file-limit classifier and stable terminal output
   to `haystack-reviewer.sh`. Verify the exact live-shaped fixture and negative
   lookalikes in `test-haystack-reviewer.sh`.
2. Invoke the classifier at each polling observation and after transient triage
   results before sleep. Verify bounded termination with mocked call and sleep
   counts and verify same-head rerun stability.
3. Update reviewer-loop contract comments and tests for reason/display
   forwarding, healthy label semantics, permissive aggregation, preserved
   blockers, and durable history.
4. Update Haystack and Protocol 93 guidance with the exact evidence, polling,
   aggregation, and history contracts.
5. Update every enumerated sync-template command/skill surface and its existing
   documentation parity test.
6. Reconcile the smoke runbook with final implementation names, then run all
   focused tests, shell/static checks, and markdown lint.
7. Add this literal `[Unreleased]` changelog entry:

   `- **Handle Haystack large-PR analysis skips** (#1311): Recognize authoritative current-head file-limit declines as terminal Haystack skips while preserving other reviewer gates and durable loop history.`

8. Run the full pre-PR and reviewer/readiness workflow required by Protocol 91.

---

## Cross-Section Consistency Self-Check

- The terminal reason is consistently `analysis_skipped_file_limit`.
- The operator display is consistently `skipped (analysis file limit)`.
- Authoritative evidence is consistently the completed `Haystack / Review`
  check fetched for the current PR head by
  `fetch_haystack_check_run_json()`.
- Prompt termination is consistently enforced by probing at the observation
  start and after a transient triage result before sleep.
- The skip is consistently permissive only for Haystack; every other reviewer,
  CI, thread-resolution, regression, and readiness gate retains its existing
  authority.
- Durable evidence is consistently the script-owned summary plus its
  `reviewer_loop_history.v1` platform token.

---

## Document Quality Gate

- Spec coverage: Checked - AC-1 through AC-8 map to implementation layers,
  focused tests, and smoke assertions.
- Decision-gate coverage: Checked - authoritative, permissive, blocking,
  ambiguous/stale, and rerun paths are enumerated with required next actions.
- Verification support: Checked - runtime behavior, affected files, mirror
  surfaces, and live signal shape cite reproducible source or query evidence.
- Behavioral guarantees: Checked - current-head API scoping enforces attempt
  correlation; two observation probes enforce bounded recognition; existing
  aggregate precedence preserves other blockers.
- Parser/API/concurrency checklist: Checked - parser edge cases and automated
  test files are named; suppression and concurrent event sources are not
  applicable with rationale.
- Cross-section consistency: Checked - result/reason/display values, source
  function, tests, documentation files, and changelog literal agree throughout.
- Stage purity: Checked - the plan PR contains only this implementation plan and
  its plan-stage smoke runbook.

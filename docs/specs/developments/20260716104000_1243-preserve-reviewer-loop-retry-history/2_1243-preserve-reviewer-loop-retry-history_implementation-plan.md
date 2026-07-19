# Reviewer Loop Retry History Preservation - Implementation Plan

**Spec**: [1_1243-preserve-reviewer-loop-retry-history_specs.md](1_1243-preserve-reviewer-loop-retry-history_specs.md)
**Smoke test runbook**: [1243-preserve-reviewer-loop-retry-history.smoke-test.md](../../../testing/workflow/1243-preserve-reviewer-loop-retry-history.smoke-test.md)

---

## Summary

**Approach**: Preserve reviewer-loop history in the durable PR comment surface that already gates readiness. Extend `pr-review-loop.sh` so each terminal reviewer-loop invocation reads the existing script-owned summary comment, appends a compact machine-readable history entry, and updates the same comment with the current human summary plus a collapsed history section. Update the retrospective protocol and retrospective agent/skill guidance to prefer this history block for retry metrics before falling back to older comment/review timestamp heuristics.

**Estimated complexity**: M

**Rationale**: The change is small in file count but touches shell comment-update logic, GitHub API read/write behavior, and retrospective parsing guidance. The main implementation risk is preserving old history safely when the existing summary comment is malformed, missing, or temporarily unreadable.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `060e056` |
| Template-fit check | Read `.ai-dev-workflow.yaml` and issue `#1243` / approved spec | `template.is_template: true`; scope is generic workflow tooling and applies to all downstream template consumers |
| Reviewer-loop summary implementation | `rg -l "^_post_review_summary\\(\\)\\|Automated Reviewer Loop Summary\\|platform_result_tokens\\|UNRESOLVED_THREAD_COUNT\\|LATE_THREADS_FOUND\\|needs_rerun" scripts/development-workflow/pr-review-loop.sh scripts/development-workflow/tests/test-pr-review-loop.sh` | 2 files: `scripts/development-workflow/pr-review-loop.sh`, `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Retrospective retry-metric surfaces | `rg -l "Automated-reviewer retry loops count\\|Review iteration count\\|retro-metrics.md\\|workflow-retrospective\\|retrospective" docs/workflow/development-workflow/protocols/06-retrospective-protocol.md .claude/agents/retrospective.md .cursor/agents/retrospective.md .codex/skills/workflow-retrospective/SKILL.md .agents/skills/retrospective/SKILL.md` | 5 files: retrospective protocol plus Claude, Cursor, Codex, and shared retrospective guidance |
| Retrospective wrapper fan-out | `grep -rl "06-retrospective-protocol\\|Automated-reviewer retry loops count" .claude/agents .cursor/agents .cursor/commands .codex/skills .agents/skills 2>/dev/null` | Direct metrics guidance appears in 4 retrospective files; post-merge wrappers reference retrospective entrypoints but do not define retry metric extraction |
| Parser/concurrency classification | Reviewed spec and target surfaces | Parser-risk applies because implementation will parse a structured JSON block from PR comment Markdown. Concurrent-event-source is not applicable: no listeners, timers, queues, or shared mutable async state are introduced |

---

## Layer-by-Layer Changes

### Workflow Script Runtime

- [ ] Update `scripts/development-workflow/pr-review-loop.sh` to add a script-owned reviewer-loop history payload to the existing `### Automated Reviewer Loop Summary` comment rather than creating a separate timeline comment.
- [ ] Define a schema-stamped JSON payload, `reviewer_loop_history.v1`, with:
  - `schema`
  - `pr_number`
  - `updated_at`
  - `history_status`
  - `history_unavailable_reason`
  - `entries`
- [ ] For each completed terminal invocation, append one entry containing:
  - `iteration`
  - `recorded_at`
  - `head_sha`
  - `result`
  - `reason`
  - `platforms`
  - `blocking_count`
  - `suggestion_count`
  - `unresolved_thread_count`
  - `late_threads_found`
  - `phase_after_clean` fields already emitted by the loop when applicable
- [ ] Treat `clean`, `needs_fixes`, `needs_rerun`, `escalate`, and `skipped` terminal paths as history-recordable. `needs_rerun` must record a history entry before exiting with code `3`, even though the existing human summary is primarily updated on `clean`, `needs_fixes`, and `escalate`.
- [ ] Preserve the existing human-readable terminal summary at the top of the comment. Add the history after it in a compact `<details>` section with a fenced `json` block so humans can inspect it without burying the current result.
- [ ] When the prior history block cannot be read, parsed, or written, keep readiness semantics unchanged but expose `history_status: unavailable` and a specific `history_unavailable_reason` in the summary comment. Do not silently treat missing history as zero retries.
- [ ] Keep the existing single-summary-comment update-in-place behavior. The implementation must not create duplicate reviewer-loop summary comments for normal reruns.

### Retrospective Protocol and Guidance

- [ ] Update `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md` Step 2 / Step 3d to read the latest `Automated Reviewer Loop Summary` comment via the PR comments API and parse the `reviewer_loop_history.v1` JSON block before using timestamp heuristics.
- [ ] Define retry metric calculation as:
  - `iteration_count = entries.length`
  - `automated_reviewer_retry_loops_count = max(iteration_count - 1, 0)` when the latest history has `history_status: available`
  - `unavailable (<reason>)` when the history block is absent, malformed, unreadable, or explicitly reports unavailable
- [ ] Require retrospective output to include exact per-iteration result, blocker count, and timestamp evidence when history is available.
- [ ] Update `.claude/agents/retrospective.md`, `.cursor/agents/retrospective.md`, `.codex/skills/workflow-retrospective/SKILL.md`, and `.agents/skills/retrospective/SKILL.md` so direct retrospective runners follow the new durable-history-first metric extraction rule.

### Tests and Smoke Coverage

- [ ] Extend `scripts/development-workflow/tests/test-pr-review-loop.sh` with unit-style shell harness coverage for history rendering, parsing, append order, unavailable reasons, and duplicate-comment prevention.
- [ ] Add or update a retrospective-protocol documentation test/check where the repo normally validates protocol text, if no executable retrospective parser exists.
- [ ] Use the smoke test runbook to validate a multi-iteration reviewer loop, a single clean reviewer loop, unavailable-history handling, and retrospective metric extraction.

### Not Modified

- `CHANGELOG.md` is not modified in this plan PR. The later implementation PR must add an `[Unreleased]` entry.
- CI requirements, readiness labels, tracker transitions, merge authority, reviewer severity mapping, and retry budgets must remain unchanged.
- No database, application frontend, API endpoint, or infrastructure configuration changes are required.

---

## Parser-Risk Edge Cases

**Classification**: Applies. The implementation parses structured JSON embedded in Markdown PR comments and must avoid losing historical entries during summary updates.

The implementation must cover these concrete inputs:

1. Missing history block: a legacy summary comment with no `reviewer_loop_history.v1` payload.
2. Malformed JSON block: a fenced `json` block whose contents are not valid JSON.
3. Wrong schema block: valid JSON with `schema` set to an unknown value.
4. Empty entries array: valid schema with no entries.
5. Multiple history blocks: a comment containing more than one matching schema block.
6. Markdown fence boundary: JSON containing escaped backticks or text adjacent to the closing fence.
7. Prior unavailable state: existing payload has `history_status: unavailable` and a reason.
8. Needs-rerun terminal path: `RESULT=needs_rerun` exits before the final clean rerun.
9. Duplicate terminal rerun on same head SHA: the loop runs twice against the same commit after a transient reviewer platform failure.
10. Comment API read failure: fetching existing comments fails before the update.
11. Comment API write failure: the summary update cannot be patched or posted.

**Unit test mapping**:

| Edge case | Required test in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| --- | --- |
| Missing history block | Appending creates iteration `1` and reports zero retries after a clean first run |
| Malformed JSON block | Summary exposes `history_status: unavailable` with a parse-specific reason |
| Wrong schema block | Wrong schema is ignored or marked unavailable without corrupting the current summary |
| Empty entries array | Append produces a valid first entry rather than reporting a negative retry count |
| Multiple history blocks | Parser chooses the latest script-owned block deterministically and records that choice |
| Markdown fence boundary | Extractor reads the fenced JSON only and does not consume adjacent summary Markdown |
| Prior unavailable state | Next update preserves the unavailable reason and appends only if safe |
| Needs-rerun terminal path | Exit code `3` path records a history entry before returning |
| Duplicate terminal rerun on same head SHA | Entries remain ordered and do not overwrite prior iterations |
| Comment API read failure | Summary includes `history_unavailable_reason=comment_read_failed` or equivalent |
| Comment API write failure | Script emits a visible warning and does not report false history availability |

**Suppression semantics**: Not applicable. The feature does not add inline suppression directives.

---

## Parser, API, and Concurrency Classification

**Parser-risk**: Applies; see the dedicated edge-case section above.

**API-surface changes**: Applies internally to the script-owned PR comment schema only. No new public CLI flags are required. The schema name and fields above are the compatibility contract for retrospective readers.

**Concurrent-event-source**: Not applicable. The script executes as a single reviewer-loop process and does not introduce event listeners, timers, sockets, queues, or shared mutable state across execution contexts.

---

## Testing Strategy

**Test types**: Shell unit/harness tests, markdown/protocol validation, and smoke runbook execution.

**Key scenarios to test**:

1. Multi-iteration reviewer loop appends every completed iteration and retains prior entries after the final clean summary update - maps to AC1, AC2, AC3.
2. Retrospective reads preserved history and reports exact retry count, per-iteration result, blocker count, and timestamp/order evidence - maps to AC3.
3. First-pass clean reviewer loop records one clean entry and retrospective reports zero retries - maps to AC4.
4. Missing, malformed, or unreadable history reports a specific unavailable reason - maps to AC5.
5. Blocking-review, CI, readiness-label, tracker-status, and merge-authority behavior remain unchanged - maps to AC6.
6. Human summary remains focused on the latest terminal result while exposing compact history access - maps to AC7.

**Smoke test runbook**: `docs/testing/workflow/1243-preserve-reviewer-loop-retry-history.smoke-test.md`

**Regression suite**: Run `bash scripts/development-workflow/tests/test-pr-review-loop.sh`. Also run the repository's markdown validation for changed docs.

---

## Seed Data

No database seed data is required. Tests should use mocked PR comment JSON fixtures in `scripts/development-workflow/tests/test-pr-review-loop.sh` and real or mock PR numbers in the smoke runbook.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md` - document durable history extraction and unavailable-history handling for retry metrics.
- [ ] `.claude/agents/retrospective.md` - mirror durable-history-first retry metric guidance.
- [ ] `.cursor/agents/retrospective.md` - mirror durable-history-first retry metric guidance.
- [ ] `.codex/skills/workflow-retrospective/SKILL.md` - mirror durable-history-first retry metric guidance.
- [ ] `.agents/skills/retrospective/SKILL.md` - mirror durable-history-first retry metric guidance.
- [ ] `docs/testing/workflow/1243-preserve-reviewer-loop-retry-history.smoke-test.md` - update if implementation details differ from this plan.
- [ ] `CHANGELOG.md` - add an `[Unreleased]` `Changed` entry in the implementation PR.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Existing summary update logic overwrites history | Medium | High | Read existing script-owned summary before rendering the new body and include append-preservation tests |
| Malformed history causes false zero-retry metrics | Medium | High | Treat parse/read failures as `unavailable (<reason>)`, never as zero |
| History section makes the human summary noisy | Low | Medium | Keep the current result at the top and place history in a collapsed details section |
| Shell JSON manipulation is brittle | Medium | Medium | Use `jq` for payload creation/parsing and add parser-risk tests for malformed and boundary cases |
| `needs_rerun` exits before summary update | Medium | Medium | Add an explicit history-record call before the existing exit-code-3 path |
| Retrospective runners keep using old heuristics | Medium | Medium | Update protocol and all direct retrospective agent/skill guidance that names retry metrics |

---

## Code Samples

No production code samples are included. The implementation may include illustrative JSON examples in documentation or tests, but executable shell behavior belongs in the implementation PR.

---

## Implementation Order

1. Add reviewer-loop history helper functions in `scripts/development-workflow/pr-review-loop.sh` before the `HARNESS_MODE` return point so tests can call them directly:
   - Locate the existing script-owned summary comment.
   - Extract the latest `reviewer_loop_history.v1` fenced JSON block.
   - Build the next history entry from current aggregate variables and emitted counts.
   - Render the updated human summary plus collapsed history section.
2. Update `_post_review_summary` so `clean`, `needs_fixes`, `escalate`, and `skipped` summary paths append history before patching or posting the single script-owned summary comment.
3. Add a dedicated `needs_rerun` history-record path before the existing exit-code-3 return so a PR-Agent fix-pushed iteration is durable even though the loop immediately reruns.
4. Preserve existing readiness behavior:
   - Do not change exit codes.
   - Do not change `ready-for-human-review`, `ready-for-regression`, `needs-fixes`, or `reviewer-failed` label logic.
   - Do not change CI or merge-authority gates.
5. Extend `scripts/development-workflow/tests/test-pr-review-loop.sh` with the parser-risk test mapping above, using mocked `gh api` / `gh pr comment` fixtures already present in the harness.
6. Update `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md` to parse `reviewer_loop_history.v1` from PR comments and calculate retry metrics from history entries before falling back to legacy heuristics.
7. Update `.claude/agents/retrospective.md`, `.cursor/agents/retrospective.md`, `.codex/skills/workflow-retrospective/SKILL.md`, and `.agents/skills/retrospective/SKILL.md` with the same durable-history-first rule.
8. Run validation:
   - `bash scripts/development-workflow/tests/test-pr-review-loop.sh`
   - `npx markdownlint-cli2 "docs/workflow/development-workflow/protocols/06-retrospective-protocol.md" ".claude/agents/retrospective.md" ".cursor/agents/retrospective.md" ".codex/skills/workflow-retrospective/SKILL.md" ".agents/skills/retrospective/SKILL.md" "docs/testing/workflow/1243-preserve-reviewer-loop-retry-history.smoke-test.md"`
   - `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`
   - Run the smoke test runbook and record the result in the implementation PR.
9. Update `CHANGELOG.md` under `[Unreleased]` in the implementation PR using:
   - `### Changed`
   - `- **Reviewer-loop retry history** (#1243): Preserved machine-readable reviewer-loop iteration history so retrospectives can report exact retry metrics.`

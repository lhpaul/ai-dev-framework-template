# Batch PR Mergeability Recheck - Implementation Plan

**Spec**: [Batch PR Mergeability Recheck - Spec](1_1424-batch-pr-mergeability-recheck_specs.md)
**Smoke test runbook**: [Batch mergeability recheck smoke test](../../../testing/workflow/1424-batch-pr-mergeability-recheck.smoke-test.md)

---

## Summary

**Approach**: Extend the batch merge pipeline with an explicit post-sibling-merge
recheck for every remaining PR in the frozen in-scope list. The helper should
emit refreshed per-PR state before each subsequent merge, classify retryable and
terminal non-clean states, hold blocked PRs as `merge_blocked`, preserve the
original order, and continue only with later PRs that independently recheck
clean.

**Estimated complexity**: M

**Rationale**: The core change belongs in `batch-merge.sh` and Protocol 94, but
the behavior is a multi-input workflow decision gate with retry, skip, summary,
and delegated `/run-items` semantics. It needs focused shell tests plus mirrored
orchestrator/skill documentation to avoid stale readiness assumptions.

**Dependencies**: None. The approved spec for issue #1424 is merged into
`develop` and is orthogonal to #1423. Conflict recovery must still respect the
existing no-force-push policy, and later implementation should reuse #1423 if it
has already landed.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `54f1e0e` |
| Template-fit check | Read `.ai-dev-workflow.yaml` and approved spec | `template.is_template: true`; spec changes generic workflow orchestration, so it passes. |
| Current batch scope | Parent `/run-items` invocation | Frozen scope: `#1423,#1424`; relationship decision recorded as orthogonal. |
| Same-surface open PRs | `gh pr list --base develop --state open --json number,title,headRefName,files --jq '.[] | {number,title,headRefName,files:[.files[].path]}'` | No open PRs targeting `develop`; no same-surface operational conflict. |
| Batch merge surface search | `rg -n "batch-merge.sh|mergeability|mergeStateStatus|MERGE_RESULT|CHANGELOG_DEDUPED|ready_human_merge|merge_blocked" scripts/development-workflow/batch-merge.sh docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md .agents/skills/run-items/SKILL.md .codex/skills/batch-merge/SKILL.md scripts/development-workflow/tests` | 104 matches across `batch-merge.sh`, Protocols 90/94, run-items and batch-merge skills, and existing tests. |
| Batch command and orchestration mirror search | `rg -l "batch-merge.sh|Batch Merge|merge_blocked|ready_human_merge|remaining PR|Sequential Merge" .agents/skills .codex/skills .claude/commands .cursor/commands .claude/agents .cursor/agents` | Matching mirror files include `.agents/skills/batch-merge/SKILL.md`, `.claude/commands/batch-merge.md`, `.cursor/commands/batch-merge.md`, run-item/run-items/run-epic commands and skills, item-orchestrator/orchestrator agents, and Codex orchestration skills. |
| Current merge helper state | `sed -n '520,780p' scripts/development-workflow/batch-merge.sh` | `merge --pr` revalidates only the PR being merged, pushes base, and marks the PR merged; it has no remaining-PR recheck subcommand. |
| Current Protocol 94 loop | `sed -n '1,680p' docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md` | Sequential loop processes one PR at a time, then cleanup, then proceeds; it does not require a recheck of unmerged siblings after each success. |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact owner and base branch for this template workflow item | `single_repo`, artifact base `develop` | `.ai-dev-workflow.yaml`, parent bounded prelude, `git rev-parse --short origin/develop` | `2026-08-01T18:57:58Z`, repo `54f1e0e` | Current invocation items `#1423,#1424`; no open PRs targeting `develop` at plan start | `Verified` |
| Frozen batch scope semantics | Only the explicit in-scope PR list may be rechecked for mutation | Approved spec #1424, `.agents/skills/run-items/SKILL.md`, Protocol 90 | `2026-08-01T18:57:58Z`, repo `54f1e0e` | Same current batch only; #1423 changes branch-history safety, not mergeability rechecks | `Verified` |

---

## Complex Workflow Decision-Gate Matrix

| Gate input | Allowed outcome | Required next action | Mirror surfaces |
| --- | --- | --- | --- |
| Sibling PR merged successfully and remaining PR rechecks clean with required checks passing | `continue` | Record refreshed clean state and attempt the next PR in original order | `batch-merge.sh`, Protocol 94, Protocol 90, run-items skill |
| Remaining PR has pending checks still legitimately in progress | `hold` | Classify as `retryable`; poll within bounded timeout; merge only after clean; otherwise hold as `merge_blocked` | `batch-merge.sh`, Protocol 94 |
| Remaining PR state is temporarily unknown | `hold` | Classify as `retryable`; re-query within bounded timeout; exhausted attempts or deadline becomes `merge_blocked` | `batch-merge.sh`, Protocol 94 |
| Remaining PR becomes dirty, conflicted, blocked, behind, failing, or exhausted pending | `hold` | Classify as `merge_blocked`; do not merge; record invalidating sibling merge and refreshed state; skip without reordering | `batch-merge.sh`, Protocol 94, Protocol 90 |
| Out-of-scope PR is visible during recheck | `observe` | Classify as `out_of_scope_observation`; do not mutate, label, merge, or add to the recheck set | Protocol 90, run-items skill, summary output |
| Base push or MERGED-state verification fails after sibling merge | `error` or `hold` depending on PR state | Classify helper failures as `helper_failed`; stop processing affected PR until base/GitHub state is authoritative | `batch-merge.sh`, Protocol 94 |

---

## Layer-by-Layer Changes

### Workflow Scripts

- [ ] Extend `scripts/development-workflow/batch-merge.sh` with this exact
  Bash 3.2-compatible recheck CLI contract:
  `batch-merge.sh recheck-remaining --prs <comma-separated-pr-list> --after-merged-pr <number> --base <branch>`.
  `--prs` accepts decimal PR numbers separated by commas with no spaces; the
  implementation must reject duplicate, empty, nonnumeric, or space-delimited
  entries.
- [ ] The recheck subcommand must:
  - Parse only the frozen explicit PR list supplied by the caller.
  - Fetch authoritative live state for each remaining PR: `state`, `isDraft`,
    labels, base ref, `mergeStateStatus`, and required status rollup.
  - Run a separate read-only observation query for open PRs targeting
    `TARGET_BASE` that are absent from the frozen `--prs` list; emit those
    observations under the `out_of_scope_observation` classification only, and
    never add them to the mutation, retry, merge, or label set.
  - Validate base ref equals the selected `TARGET_BASE`.
  - Classify clean, retryable pending/unknown, terminal non-clean, and
    out-of-scope observations into the canonical JSONL output schema below.
  - Include the invalidating sibling PR number in every non-clean or retryable
    remaining-PR record.
  - Preserve original order; do not sort by refreshed status.
  - Exit non-zero only for helper or input failures. A `merge_blocked` PR is a
    valid classified result, not a script crash.
- [ ] Update `cmd_merge` or its caller contract so every successful
  `MERGE_RESULT=clean` is followed by `recheck-remaining` before another
  `merge --pr` call.
- [ ] Add a bounded retry helper for pending and temporarily unknown states.
  Keep defaults short enough for operator feedback and configurable through
  environment variables if needed. Defaults: 3 attempts, 10 seconds between
  attempts, and a 60-second wall-clock deadline per remaining PR. Retry stops at
  whichever bound is reached first; if both are reached on the same refresh,
  `reason` must be `retry_attempts_exhausted`, `retryable` must be `false`, and
  the record must be classified as `merge_blocked`.
- [ ] Keep existing CHANGELOG deduplication and MERGED-state checks intact.

### Recheck Output Contract

`batch-merge.sh recheck-remaining` must write one compact JSON object per line
to stdout. Records are emitted in this order: remaining in-scope PRs in the
same order they appeared in the frozen `--prs` list, followed by any
`out_of_scope_observation` records ordered by PR number ascending.

Required fields for every record:

| Field | Values |
| --- | --- |
| `record_type` | `remaining_pr`, `out_of_scope_observation`, or `error` |
| `pr` | Pull request number; `null` only for helper-wide `error` records |
| `original_index` | Zero-based index in frozen `--prs`; `null` for out-of-scope observations and helper-wide errors |
| `invalidating_sibling_pr` | The just-merged sibling PR number; never `null` after input validation succeeds |
| `base_ref` | Refreshed PR base; `null` only when unavailable because of `helper_failed` |
| `head_ref` | Refreshed PR head; `null` only when unavailable because of `helper_failed` |
| `merge_state` | Raw GitHub `mergeStateStatus`, upper-case; `null` only when unavailable because of `helper_failed` |
| `checks_state` | `success`, `pending`, `failure`, `unknown`, or `not_required`; `null` only when unavailable because of `helper_failed` |
| `classification` | `clean`, `retryable`, `merge_blocked`, `out_of_scope_observation`, or `helper_failed` |
| `retryable` | Boolean |
| `attempts` | Number of refresh attempts used |
| `deadline_seconds` | Effective per-PR retry deadline |
| `outcome` | `continue`, `hold`, `observe`, or `error` |
| `reason` | Stable snake_case reason |

Classification precedence for in-scope `remaining_pr` records:

| Precedence | Refreshed condition | Classification | Outcome | Reason |
| --- | --- | --- | --- | --- |
| 1 | GitHub fetch, authentication, JSON parsing, or required-field guard fails | `helper_failed` | `error` | `github_query_failed`, `auth_failed`, `malformed_response`, or `missing_required_field` |
| 2 | `state` is `CLOSED` or `MERGED` | `merge_blocked` | `hold` | `pr_not_open` |
| 3 | `isDraft` is true | `merge_blocked` | `hold` | `draft_pr` |
| 4 | Required merge label is absent, or a blocking label such as `needs-fixes` or `do-not-merge` is present | `merge_blocked` | `hold` | `label_gate_failed` |
| 5 | `base_ref` differs from selected `TARGET_BASE` | `merge_blocked` | `hold` | `base_ref_mismatch` |
| 6 | Required checks are `failure` | `merge_blocked` | `hold` | `checks_failed` |
| 7 | Required checks are `pending` or `unknown`, before retry bound | `retryable` | `hold` | `checks_not_settled` |
| 8 | Required checks are `pending` or `unknown`, after retry bound | `merge_blocked` | `hold` | `retry_attempts_exhausted` or `retry_deadline_exhausted` |
| 9 | `merge_state` is `DIRTY`, `BLOCKED`, `BEHIND`, `UNSTABLE`, or `HAS_HOOKS` | `merge_blocked` | `hold` | `merge_state_non_clean` |
| 10 | `merge_state` is `UNKNOWN` or empty, before retry bound | `retryable` | `hold` | `merge_state_unknown` |
| 11 | `merge_state` is `UNKNOWN` or empty, after retry bound | `merge_blocked` | `hold` | `retry_attempts_exhausted` or `retry_deadline_exhausted` |
| 12 | `merge_state` is `CLEAN` and checks are `success` or `not_required` | `clean` | `continue` | `refreshed_clean` |
| 13 | Any remaining combination | `helper_failed` | `error` | `unclassified_state` |

`out_of_scope_observation` records bypass in-scope eligibility and mutation
rules. They must still include the selected `TARGET_BASE`, the
`invalidating_sibling_pr`, the observed PR number, and the observed head/base
refs when available.

The subcommand exits `0` when all records were fetched and classified, including
when one or more in-scope PRs are `merge_blocked`. It exits non-zero only for
invalid input, authentication failures, malformed GitHub responses, missing
required fields after guarded parsing, or other helper failures. Non-zero helper
failures must emit a final `helper_failed` JSON record before exit when stdout
is still available. That record must use `record_type: "error"`,
`classification: "helper_failed"`, `outcome: "error"`, `retryable: false`,
`attempts: 0` unless a per-PR retry was already in progress, and nullable state
fields exactly as defined in the schema table.

### Protocols and Workflow Documentation

- [ ] Update `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md`
  Step 4.2 to require a remaining-PR recheck after each successful merge and
  before selecting the next PR.
- [ ] Update Protocol 94 Step 5 summary outcomes to include
  `merge_blocked` for PRs held by refreshed non-clean state, with the
  invalidating sibling merge and refreshed state.
- [ ] Update `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
  Step 5.5 so delegated `/run-items` batch merge handoff preserves the frozen
  in-scope PR list and consumes the refreshed outcome contract.
- [ ] Update `.agents/skills/batch-merge/SKILL.md`,
  `.codex/skills/batch-merge/SKILL.md`, `.claude/commands/batch-merge.md`, and
  `.cursor/commands/batch-merge.md` so every batch-merge command surface
  requires the post-sibling-merge recheck before selecting the next PR.
- [ ] Update delegated orchestration mirrors that can invoke batch merge:
  `.agents/skills/run-items/SKILL.md`,
  `.agents/skills/run-items/agents/openai.yaml`,
  `.agents/skills/run-item/SKILL.md`, `.agents/skills/run-epic/SKILL.md`,
  `.codex/skills/workflow-orchestrator/SKILL.md`,
  `.codex/skills/workflow-orchestrator/agents/openai.yaml`,
  `.codex/skills/workflow-item-orchestrator/SKILL.md`,
  `.codex/skills/workflow-item-orchestrator/agents/openai.yaml`,
  `.claude/agents/orchestrator.md`, `.cursor/agents/orchestrator.md`,
  `.claude/agents/item-orchestrator.md`,
  `.cursor/agents/item-orchestrator.md`, `.claude/commands/run-items.md`,
  `.cursor/commands/run-items.md`, `.claude/commands/run-item.md`,
  `.cursor/commands/run-item.md`, `.claude/commands/run-epic.md`, and
  `.cursor/commands/run-epic.md`.
- [ ] Rerun the batch command and orchestration mirror search from the
  Verification Log before submitting; every hit must be updated or explicitly
  documented as out of scope in the implementation PR's self-review log.
- [ ] Update `scripts/development-workflow/README.md` with the new subcommand,
  output fields, retry semantics, and caller sequence.

### Tests and Validation

- [ ] Add `scripts/development-workflow/tests/test-batch-merge-recheck-remaining.sh`.
- [ ] Extend `scripts/development-workflow/tests/test-batch-merge-checkpoints.sh`
  only if the new recheck subcommand touches checkpoint-labeled PR behavior.
- [ ] Update `scripts/development-workflow/tests/test-may-merge-terminal-contract.sh`
  if new or mirrored terminal outcome language is added to protocols/skills.
- [ ] Add or update the smoke runbook at
  `docs/testing/workflow/1424-batch-pr-mergeability-recheck.smoke-test.md`.

---

## Testing Strategy

**Test types**: Unit / Integration-style shell tests / Smoke

**Key scenarios to test**:

1. Two initially clean PRs are discovered; after PR A is marked merged, PR B
   rechecks `DIRTY` and is held as `merge_blocked`. Maps to AC1, AC2, AC3,
   AC5, AC9, AC10.
2. Pending and temporarily unknown states are retried until clean, terminal
   non-clean, or timeout. Maps to AC4.
3. A refreshed-clean later PR can continue without new human approval when the
   delegated policy still permits merge. Maps to AC6.
4. Original order is preserved when one PR becomes blocked; later PRs merge only
   after independent refreshed-clean evidence. Maps to AC7.
5. Out-of-scope PRs visible during recheck are observation-only. Maps to AC8.
6. Summary output distinguishes merged PRs, `merge_blocked` PRs, failed helper
   states, and out-of-scope observations. Maps to AC9.

**Smoke test runbook**: `docs/testing/workflow/1424-batch-pr-mergeability-recheck.smoke-test.md`

**Regression suite**: Add a committed shell test under
`scripts/development-workflow/tests/` with a mocked `gh` command and disposable
Git fixture that simulates the sibling-merge invalidation.

### Parser-Risk Addendum

This plan is not parser-risk. It adds structured shell output and mocked GitHub
state classification, but it does not introduce a regex-heavy scanner,
structured-text parser, lint rule, or tokenizer. The implementation must still
guard every `jq` extraction and empty structured input per the shell quality
checklist.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Mock PR A | Initially clean; selected and merged first | Created in `test-batch-merge-recheck-remaining.sh` fake `gh` output |
| Mock PR B | Initially clean; refreshed to `DIRTY`, pending, unknown, failing, and clean variants | Created in `test-batch-merge-recheck-remaining.sh` fake `gh` output |
| Mock out-of-scope PR | Visible in broad queries but absent from frozen `--prs` list | Created in fake `gh` output |

---

## Documentation Updates

Use the authoritative documentation checklist in "Protocols and Workflow
Documentation" above. The implementation PR self-review must state whether
`REVIEW.md` changed; update it only if the implementation adds
reviewer-visible checks for stale mergeability evidence.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Recheck mutates or expands out-of-scope PRs | Low | High | Accept only the frozen `--prs` list for mutation; report out-of-scope observations separately. |
| Pending or unknown states are treated as immediately terminal | Med | Med | Add bounded retry classification with explicit timeout behavior. |
| Blocked PRs reorder the batch | Med | High | Preserve original order in helper output and protocol text; tests must assert order. |
| Summary still reports stale clean evidence | Med | High | Make refreshed state and invalidating sibling PR required summary fields. |
| Existing CHANGELOG deduplication regresses | Low | Med | Keep existing merge path tests and run the new recheck tests alongside checkpoint tests. |

---

## Code Samples

No production-ready code samples are included. The implementation PR should add
the shell helper changes and tests directly.

---

## Implementation Order

1. Add the `recheck-remaining` subcommand to
   `scripts/development-workflow/batch-merge.sh` with stable output fields for
   PR number, original order, invalidating sibling PR, refreshed merge state,
   required check state, classification, retryability, and outcome.
2. Add `scripts/development-workflow/tests/test-batch-merge-recheck-remaining.sh`
   with mocked `gh` responses for clean, pending, unknown, dirty, blocked,
   behind, failing, timeout, and out-of-scope cases. The test must assert the
   exact JSONL field names, classification values, order, retry attempt count,
   and non-zero helper-failure behavior defined above.
3. Update Protocol 94 so the sequential loop rechecks all remaining in-scope
   PRs after every successful merge and before each next merge attempt.
4. Update Protocol 90 and Codex/command skill guidance so delegated `/run-items`
   passes the frozen PR list and reports refreshed terminal outcomes.
5. Update `scripts/development-workflow/README.md` with the helper contract.
6. Add the smoke runbook and ensure it maps every acceptance criterion to a
   testable step.
7. Update `CHANGELOG.md` under `[Unreleased]` in the implementation PR using:
   `- **Recheck batch mergeability after sibling merges** (#1424): Refresh remaining PR mergeability after each batch merge and hold stale or non-clean PRs.`
8. Run verification:
   - `bash scripts/development-workflow/tests/test-batch-merge-recheck-remaining.sh`
   - `bash scripts/development-workflow/tests/test-batch-merge-checkpoints.sh`
   - `bash scripts/development-workflow/tests/test-may-merge-terminal-contract.sh`
   - `shellcheck --severity=warning scripts/development-workflow/batch-merge.sh scripts/development-workflow/tests/test-batch-merge-recheck-remaining.sh`
   - `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
   - `npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "CHANGELOG.md"`
   - `bash -c 'set -euo pipefail; tmp="$(mktemp)"; trap "rm -f \"$tmp\"" EXIT; find docs/specs/developments docs/testing/workflow -name "*.md" -print0 > "$tmp"; test -s "$tmp"; xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md < "$tmp"'`
9. Complete the Protocol 03 Pre-Submission Self-Review Pass, including the
   complex decision-gate matrix above, before opening the implementation PR.

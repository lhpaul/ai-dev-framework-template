# Resolved Codex Findings No Longer Block Reviewer Loop — Implementation Plan

**Spec**: [`1_1757-resolved-codex-findings_specs.md`](./1_1757-resolved-codex-findings_specs.md)
**Smoke test runbook**: [`../../../testing/workflow/1757-resolved-codex-findings.smoke-test.md`](../../../testing/workflow/1757-resolved-codex-findings.smoke-test.md)

---

## Summary

**Approach**: Align the Codex GitHub reviewer path with the spec’s fail-closed
evidence model. Today, `run_codex_github_review()` in `pr-review-loop.sh` can
emit `RESULT=needs_fixes` / `REASON=existing_findings` or
`REASON=unresolved_review_threads` while every applicable Codex review
conversation is resolved, because (a) phase 1 counts any non-outdated bot
thread before live-revision applicability is established, and (b) on companion
exit `1`, the wrapper forces `COMMENT_COUNT` to at least `1` even when a strict
thread recount returns zero. The companion script (`codex-github-reviewer.sh`)
also safe-fails unrecognized terminal verdicts to `NEEDS_REVISION` (exit `1`)
instead of the spec’s terminal escalation outcomes, and its blocking-path logic
does not yet implement the full newest-evidence matrix (cleared-findings wait,
malformed-marker escalation, correlation-missing, head evidence windows).

Implementation centralizes head-level Codex classification in
`codex-github-reviewer.sh` (new helper functions + structured `REASON=` /
`VERDICT=` output), then makes `run_codex_github_review()` a thin adapter that
maps companion outcomes to `RESULT=clean|needs_fixes|waiting_on_reviewer|escalate`
without re-counting resolved or stale findings. Regression coverage extends the
existing Area 13 harness in `test-pr-review-loop.sh` (mock-`gh` direct invocations
of the companion) plus one harness case for `run_codex_github_review()` proving
a resolved-but-visible finding yields `waiting_on_reviewer` /
`codex-github-review-pending`, not `needs_fixes`.

**Estimated complexity**: L

**Rationale**: The spec’s decision-gate matrix spans thread resolution,
review-head SHA correlation, submitted-review GitHub state, root-comment marker
grammar, freshness boundaries, evidence-window attribution, tie precedence,
cycle-limit interaction, and four new escalation reason codes. The companion
script is already ~2.5k lines with ~150+ harness cases; this item extends the
classifier and loop adapter without changing rate limits or polling budgets.
CodeRabbit reuse is assessment-only (AC-16).

**Dependencies**: Spec PR #1758 merged to `develop` (verified). No other batch
item in the current invocation list modifies the same Codex classification
surfaces (see Cross-Cutting Operational Assumption Check).

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision (worktree) | `git rev-parse --short HEAD` | `32605700` |
| Spec merged | `gh pr view 1758 --json state,baseRefName,mergedAt` | `MERGED` into `develop` at `2026-09-16T23:05:22Z` |
| Phase-1 existing-findings gate | `sed -n '2167,2203p' scripts/development-workflow/pr-review-loop.sh` | Uses `check_unresolved_threads … provisional`; returns `needs_fixes` / `existing_findings` when count > 0 |
| Companion exit-1 wrapper floor | `sed -n '2252,2290p' scripts/development-workflow/pr-review-loop.sh` | On script exit `1`, sets `unresolved_count=1` when strict recount is `0` |
| Cleared-thread retrigger (partial) | `sed -n '1532,1541p' scripts/development-workflow/codex-github-reviewer.sh` | Posts fresh trigger when review has only cleared inline threads and body is non-blocking — does not cover full spec matrix |
| Unrecognized safe-fail today | Header + tests grep `unrecognized response format — safe-fail` in `codex-github-reviewer.sh` / Area 13 | Terminal unrecognized evidence exits `NEEDS_REVISION` (1), not escalate |
| Harness surface | `grep -c '^run_test.*codex' scripts/development-workflow/tests/test-pr-review-loop.sh` | 418 `codex`-named tests (Area 13) |
| CodeRabbit thread API | `grep -n 'check_unresolved_threads' scripts/development-workflow/pr-review-loop.sh \| head` | CodeRabbit pass uses same GraphQL `isResolved` / `isOutdated` model — candidate for `shared` assessment |
| Integration doc | `docs/workflow/development-workflow/integrations/codex-github.md` | Documents pre-trigger scan and template approval; lacks new escalation/wait reason codes |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch | `develop` | Parent handoff + `gh pr view 1758` | 2026-09-17, SHA `32605700` | Item #1757 only | `Verified` |
| Same-surface concurrent PRs | none | Parent batch dispatch (`1757,1462,1496,1515,1561,1583,1529`) | 2026-09-17 | Same-surface open PRs at dispatch: none | `Verified` |
| Codex companion exit-code contract | `0/1/2/3/4` documented in companion header | `codex-github-reviewer.sh` lines 29–34 | 2026-09-17 | No batch peer targets `codex-github-reviewer.sh` classification | `Verified` |

**Conflict evidence**: none.

---

## Layer-by-Layer Changes

> Database, shared packages, frontend, and infrastructure layers do not apply.

### Script layer — `codex-github-reviewer.sh` (primary)

Record the **provider fields** the plan relies on (spec Business Rule 1):

| Concept | GitHub surface | Fields / identifiers |
| --- | --- | --- |
| Conversation resolution | GraphQL `reviewThreads` | `isResolved`, `isOutdated`, `comments(first:1)` author login + body, `comments(last:1)` author + `createdAt` |
| Live revision | REST reviews + PR head | Review `commit_id`, `state` (`CHANGES_REQUESTED` short-circuit), `submitted_at`; PR `headRefOid` |
| Thread correlation | GraphQL / REST | Review thread `id` (databaseId) matched to inline review comments on current head |
| Dismissed review | REST reviews | `state: DISMISSED` excluded from terminal evidence selection |
| Root comment terminal evidence | REST issue comments | `Reviewed commit` marker, `created_at`, comment `id` ordering vs trigger comment |
| Availability (unchanged) | Root comment body | Usage-limit, account-not-connected, environment-setup patterns already recognized |

- [ ] **Bounded evidence query** (AC-1–4, 7–9, 14–16): Extend
  `codex_review_thread_evidence_counts()` (or successor) to return structured
  status on GraphQL failure (`evidence_unavailable_codex_thread_state`) after
  one retry, and to classify each non-outdated Codex thread as
  `applicable_unresolved`, `applicable_resolved`, `cleared`, `outdated`, or
  `dismissed_review_attached` using head SHA + review `commit_id` equality (not
  merely `isOutdated`). Provisional “reply after head push” relaxation remains
  **only** for re-trigger eligibility, never for declaring clean (preserve #1508
  contract).

- [ ] **Terminal evidence collector** (AC-3–4, 10–13): Normalize submitted
  reviews and root PR comments into a sorted list of evidence items for the
  live head (timestamp, source, review state, marker parse result, clean vs
  blocking vs unrecognized vs availability). Implement marker well-formedness
  (exactly one hex token, unambiguous resolution, prefix-at-offset-zero rule,
  interior-substring / superstring rejection) and freshness boundary (after
  latest live-head trigger; same-second comment ID ordering).

- [ ] **Head evidence window attribution** (AC-13, 16): For trigger-less root
  comments, assign each comment to the head that was current when authored; if
  chronology cannot be established, escalate `evidence_unavailable_codex_thread_state`
  rather than attributing to live head.

- [ ] **Decision function** (spec matrix): Implement
  `codex_classify_live_head_evidence()` returning one of:
  `clean`, `needs_fixes`, `waiting_on_reviewer` (+ reason), `escalate` (+ reason).
  Apply newest-non-dismissed timestamp selection among live-head-covering items,
  then tie precedence: malformed-marker → unrecognized → correlation-missing →
  evidence-unavailable → actionable blocker → availability hard stop →
  cleared-findings wait → clean. Preserve immediate-precedence for usage-limit and
  account-not-connected notices (spec: never superseded by clean in same fetch).

- [ ] **Outcome mapping** (Statuses table): Emit companion stdout keys:
  - `VERDICT: APPROVED` → exit `0`
  - Actionable blocker → exit `1` with blocking summary (unchanged shape)
  - Timed out / hard unavailable → exit `2` / `3` (unchanged)
  - `waiting_on_reviewer` → exit `4` with `REASON=codex-github-review-pending` or
    `REASON=codex-github-reaction-without-review`
  - Fail-closed escalations → exit `2` with `REASON=` one of
    `evidence_unavailable_codex_thread_state`,
    `codex_current_verdict_malformed_revision_marker`,
    `codex_finding_thread_correlation_missing`,
    `codex_current_verdict_unrecognized`
  Replace “unrecognized → NEEDS_REVISION safe-fail” path (AC-7).

- [ ] **Cleared-findings retrigger** (AC-8): When terminal finding verdict’s
  findings all correlate to resolved applicable conversations and no other
  applicable unresolved conversation exists, return exit `4` /
  `codex-github-review-pending` (post fresh trigger when appropriate), never exit
  `1`. `CHANGES_REQUESTED` submitted review remains exit `1` even if every
  thread is resolved.

- [ ] **CHANGES_REQUESTED + correlation-missing** (AC-7, matrix row): When
  structured state is `CHANGES_REQUESTED` and any finding lacks thread identity,
  escalate `codex_finding_thread_correlation_missing` (precedence over structured
  blocker).

### Script layer — `pr-review-loop.sh`

- [ ] **`run_codex_github_review()` phase 1** (AC-1–2): Stop using raw
  `check_unresolved_threads` provisional count as the sole `existing_findings`
  gate. Instead call a shared classifier hook (sourced from companion helpers or
  duplicate-minimal wrapper) that counts only **applicable unresolved** Codex
  conversations for the live head. Resolved, outdated, and dismissed-attached
  threads must not increment blocker counts.

- [ ] **Companion exit adapter** (AC-1–2, 7–9): On companion exit `1`, remove
  the `unresolved_count=1` floor when strict applicable-unresolved count is
  zero; map companion `REASON=` to loop `RESULT`/`REASON` without upgrading waits
  or escalations to `needs_fixes`. On exit `2`, propagate spec escalation reason
  codes to `RESULT=escalate` (not `timeout` unless reason says so).

- [ ] **Cycle-limit interaction** (AC-5–6): In the reviewer-loop cap check
  (`reviewer_loop_cap_exceeded` / max_cycles block ~10958+), evaluate current
  head evidence **before** escalating for exhausted allowance: canonical terminal
  clean evidence in the final permitted cycle proceeds to readiness; exhausted
  allowance with cleared-findings retrigger or remaining actionable findings
  escalates (cleared wait must not bypass cap — spec precedence).

- [ ] **Telemetry** (Operational Visibility): Ensure `print_kv` lines include
  `REVIEWED_HEAD`, `REASON`, and when waiting, existing `PENDING_REVIEW_*` keys.
  Escalation reasons must flow to PR summary unchanged via
  `emit_prefixed_platform_output`.

- [ ] **CodeRabbit assessment** (AC-16): In implementation PR description /
  test evidence comment, record whether CodeRabbit’s existing
  `check_unresolved_threads` pass exposes the same resolution + head correlation
  (`shared`) or document missing capability (`not_applicable`). No CodeRabbit
  behavior change unless assessment proves identical invariant already holds.

### Tests — `scripts/development-workflow/tests/test-pr-review-loop.sh`

- [ ] **Primary regression** (AC-15, Operational Visibility): Add harness case
  `codex_resolved_visible_finding_waits_not_fixes`: mock GraphQL with
  `isResolved=true` non-outdated Codex thread + current-head review body that
  still lists blocking markers; expect companion exit `4` and
  `REASON=codex-github-review-pending`, not exit `1`.

- [ ] **Matrix spot checks** (AC-7–14): Add focused mock-`gh` cases (one per
  escalation reason, cleared-findings wait vs clean tie, stale-head malformed
  ignored, `CHANGES_REQUESTED` with all threads resolved, empty reviewed-commit
  field, freshness-failing marker-pinned comment). Update existing Area 13 tests
  that expect `NEEDS_REVISION (unrecognized response format — safe-fail)` to
  expect escalate / `codex_current_verdict_unrecognized` instead.

- [ ] **`run_codex_github_review` integration**: One HARNESS_MODE case mocking
  companion output + GraphQL threads proving phase 1 no longer emits
  `existing_findings` when all threads resolved.

### Documentation

- [ ] **`docs/workflow/development-workflow/integrations/codex-github.md`**: Document
  new wait/escalation reason codes, cleared-findings retrigger, newest-evidence
  precedence, and resolved-thread exclusion from blocker counts.

- [ ] **`docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`**:
  Cross-link Codex phase outcomes to the spec matrix rows (short normative summary).

- [ ] **Smoke runbook** (new): `docs/testing/workflow/1757-resolved-codex-findings.smoke-test.md`
  — operator-visible checks after merge (see Testing Strategy).

**Documentation Updates (post-implementation, developer-owned)**:

- [ ] `docs/workflow/development-workflow/integrations/codex-github.md` — as above
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` — Codex phase outcome table
- [ ] None in `docs/project/` or `AGENTS.md` unless implementation reveals a command-surface change worth listing in Common Commands

---

## Testing Strategy

**Test types**: Shell harness unit tests (Area 13 + one loop integration case);
manual smoke runbook for operator verification on a real PR with resolved Codex
threads.

**Key scenarios** (map to acceptance criteria):

1. Resolved applicable Codex thread + visible historical blocking text →
   `waiting_on_reviewer` / `codex-github-review-pending` (AC-1, 2, 8, 15)
2. All threads resolved, no terminal clean evidence → wait, not `needs_fixes` (AC-2, 8)
3. Current-head clean submitted review with full SHA → `APPROVED` / loop clean (AC-3)
4. Prior-revision clean review after push → stale / pending (AC-4)
5. Cycle cap with canonical clean in final cycle → readiness; cap with cleared wait → escalate (AC-5–6)
6. Unrecognized terminal body → escalate `codex_current_verdict_unrecognized` (AC-7, 14)
7. Finding without thread id → escalate `codex_finding_thread_correlation_missing` (AC-7, 14)
8. Malformed marker on live head → escalate `codex_current_verdict_malformed_revision_marker` (AC-10, 13)
9. GraphQL thread state failure → escalate `evidence_unavailable_codex_thread_state` (AC-14)
10. Acknowledgement-only → `codex-github-reaction-without-review` precedence (AC-9)
11. `CHANGES_REQUESTED` with resolved threads → `needs_fixes` (AC-1, 2)
12. CodeRabbit assessment recorded `shared` or `not_applicable` (AC-16)

**Smoke test runbook**: `docs/testing/workflow/1757-resolved-codex-findings.smoke-test.md`

**Regression suite**: Extend `scripts/development-workflow/tests/test-pr-review-loop.sh`
only (existing workflow regression surface for Codex).

---

## Seed Data

Harness tests use inline mock `gh` fixtures (no repo seed files). Manual smoke
uses any PR where Codex left resolved inline threads on the current head.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Mock GraphQL review thread | `isResolved: true`, `isOutdated: false`, bot first comment | Inline in `test-pr-review-loop.sh` |
| Mock submitted review | `state: COMMENTED`, blocking body, `commit_id` = live head | Inline harness |
| Mock submitted review | `state: CHANGES_REQUESTED`, clean-template body | Inline harness |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Area 13 mass-update breaks unrelated Codex cases | Med | Med | Change expectations incrementally; run full `test-pr-review-loop.sh` before PR |
| Classifier divergence between companion and loop phase 1 | Med | High | Share one bash function file sourced by both scripts |
| False clean from provisional reply relaxation | Low | High | Keep provisional mode only on re-trigger path; strict on clean declaration |
| Escalation reasons not surfaced in PR summary | Low | Med | Assert `REASON=` in harness + Step 7a alignment check |

---

## Code Samples

Illustrative only — adapt during implementation.

```bash
# Illustrative — map companion escalation to loop KV
case "$script_exit" in
  2)
    codex_reason="$(kv_value_default REASON "$script_output" timeout)"
    print_kv RESULT escalate
    print_kv REASON "$codex_reason"
    return 2
    ;;
esac
```

---

## Implementation Order

1. Extract shared Codex thread + evidence helpers (new file or bottom of
   companion) with unit-testable functions; commit.
2. Implement terminal evidence collector + marker parser + window attribution; commit.
3. Implement `codex_classify_live_head_evidence()` decision matrix and wire all
   companion exit paths; commit.
4. Update `run_codex_github_review()` adapter (phase 1 + exit mapping + remove
   count floor); commit.
5. Adjust cycle-limit block to evaluate canonical clean before cap escalation; commit.
6. Add/update Area 13 harness cases + one `run_codex_github_review` case; commit.
7. Update `codex-github.md` and Protocol 93 cross-links; commit.
8. Run `bash scripts/development-workflow/tests/test-pr-review-loop.sh` (or CI
   equivalent) and fix failures.
9. Add `changelog.d/1757.fix.resolved-codex-findings.md` fragment:

   ```markdown
   - **Resolved Codex findings no longer block reviewer loop** (#1757): Count only applicable unresolved Codex review conversations toward `needs_fixes`; treat cleared findings as a wait for fresh terminal clean evidence; add fail-closed Codex escalation reason codes per spec.
   ```

10. Verify smoke runbook steps on a test PR when possible.

---

## Cross-Cutting Operational Assumption Check — Implementation-start records

| Assumption | Plan record | Implementation-start check |
| --- | --- | --- |
| Base branch `develop` | Verified 2026-09-17 | Re-verify `origin/develop` before PR |
| No concurrent Codex classifier PRs in batch | Verified at dispatch | `Still valid` unless a same-surface PR merged mid-batch |
| Companion exit codes unchanged for availability | Verified | `Still valid` — preserve exits `2`/`3` for timeout/unavailable |

Implementer must mark `Still valid` or stop with evidence if stale.

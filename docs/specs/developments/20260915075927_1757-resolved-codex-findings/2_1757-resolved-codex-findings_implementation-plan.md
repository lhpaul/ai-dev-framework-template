# Resolved Codex Findings No Longer Block Reviewer Loop — Implementation Plan

**Spec**: [`1_1757-resolved-codex-findings_specs.md`](./1_1757-resolved-codex-findings_specs.md)
**Smoke test runbook**: [`../../../testing/workflow/1757-resolved-codex-findings.smoke-test.md`](../../../testing/workflow/1757-resolved-codex-findings.smoke-test.md)

---

## Summary

**Approach**: Align the Codex GitHub reviewer path with the spec’s fail-closed
evidence model. Today, `run_codex_github_review()` in `pr-review-loop.sh` can
emit `RESULT=needs_fixes` / `REASON=existing_findings` or
`REASON=unresolved_review_threads` while every applicable Codex review
conversation is resolved, because (a) phase 1 relies on
`check_unresolved_threads` (`isResolved` / `isOutdated` / provisional reply
relaxation) without live-head `commit_id` / dismissed-review applicability, and
(b) on companion exit `1`, the wrapper forces `COMMENT_COUNT` to at least `1`
even when a strict thread recount returns zero. The companion script
(`codex-github-reviewer.sh`) also safe-fails unrecognized terminal verdicts to
`NEEDS_REVISION` (exit `1`) instead of the spec’s terminal escalation outcomes,
and its blocking-path logic does not yet implement the full newest-evidence
matrix (cleared-findings wait, malformed-marker escalation, correlation-missing,
head evidence windows).

Implementation centralizes head-level Codex classification in a new shared
library `scripts/development-workflow/codex-github-evidence-lib.sh` (functions
only — no argv parsing or top-level `exit`), sourced by both
`codex-github-reviewer.sh` and `pr-review-loop.sh`. The companion keeps
structured `REASON=` / `VERDICT=` output; `run_codex_github_review()` becomes a
thin adapter that maps companion outcomes to
`RESULT=clean|needs_fixes|waiting_on_reviewer|escalate` without re-counting
resolved or stale findings. Do **not** source `codex-github-reviewer.sh` from
the loop — it runs unconditional argument parsing and can `exit` at load time.
Regression coverage extends the existing Area 13 harness in
`test-pr-review-loop.sh` (mock-`gh` direct invocations of the companion) plus
one harness case for `run_codex_github_review()` proving a resolved-but-visible
finding yields `waiting_on_reviewer` / `codex-github-review-pending`, not
`needs_fixes`.

**Estimated complexity**: L

**Rationale**: The spec’s decision-gate matrix spans thread resolution,
review-head SHA correlation, submitted-review GitHub state, root-comment marker
grammar, freshness boundaries, evidence-window attribution, tie precedence,
cycle-limit interaction, and four new escalation reason codes. The companion
script is already ~2.5k lines, and Area 13 of `test-pr-review-loop.sh` carries
418 `codex`-named `run_test` cases (see Verification Log); this item extends the
classifier and loop adapter without changing rate limits or polling budgets.
CodeRabbit reuse is assessment-only (AC-16).

**Dependencies**: Spec PR #1758 merged to `develop` (verified). No other batch
item in the current invocation list modifies the same Codex classification
surfaces (see Cross-Cutting Operational Assumption Check).

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision (worktree) | `git rev-parse --short HEAD` | `1d9cd0e0` — this plan branch's own revision while authoring (not on `develop`); refresh at implementation start. Distinct from the `develop` ancestor `32605700` cited in the Cross-Cutting Operational Assumption Check, which pins the base-branch assumption, not this worktree |
| Spec merged | `gh pr view 1758 --json state,baseRefName,mergedAt` | `MERGED` into `develop` at `2026-09-16T23:05:22Z` |
| Phase-1 existing-findings gate | `sed -n '2167,2203p' scripts/development-workflow/pr-review-loop.sh` | Uses `check_unresolved_threads … provisional`; returns `needs_fixes` / `existing_findings` when count > 0 |
| Companion exit-1 wrapper floor | `sed -n '2252,2290p' scripts/development-workflow/pr-review-loop.sh` | On script exit `1`, sets `unresolved_count=1` when strict recount is `0` |
| Cleared-thread retrigger (partial) | `sed -n '1532,1541p' scripts/development-workflow/codex-github-reviewer.sh` | Posts fresh trigger when review has only cleared inline threads and body is non-blocking — does not cover full spec matrix |
| Unrecognized safe-fail today | Header + tests grep `unrecognized response format — safe-fail` in `codex-github-reviewer.sh` / Area 13 | Terminal unrecognized evidence exits `NEEDS_REVISION` (1), not escalate |
| Harness surface | `grep -c '^run_test.*codex' scripts/development-workflow/tests/test-pr-review-loop.sh` | 418 `codex`-named tests (Area 13) |
| CodeRabbit thread API | `grep -n 'check_unresolved_threads' scripts/development-workflow/pr-review-loop.sh \| head` | CodeRabbit pass uses same GraphQL `isResolved` / `isOutdated` model — candidate for `shared` assessment |
| Integration doc | `docs/workflow/development-workflow/integrations/codex-github.md` | Documents pre-trigger scan and template approval; lacks new escalation/wait reason codes |
| Evidence-counts symbol | `grep -n 'codex_review_thread_evidence_counts' scripts/development-workflow/codex-github-reviewer.sh` | Defined at `codex-github-reviewer.sh:273`; sole caller at `:1497` — extend in place, no successor needed |
| Cycle-cap enforcement block | `grep -n 'reviewer_loop_cap_exceeded\\|max_cycles enforcement' scripts/development-workflow/pr-review-loop.sh` | Enforcement block at `pr-review-loop.sh:10958` (`#1502` dual-cap); escalation predicate is `reviewer_loop_cap_exceeded`, reason string `max_cycles_exceeded` |
| Cycle-cap defaults | `sed -n '11201,11250p' scripts/development-workflow/pr-review-loop.sh` | `reviewer_loop_resolve_max_cycles` defaults to **10** (`:11211`, `:11216`); `reviewer_loop_resolve_max_total_cycles` defaults to **25** (`:11242`, `:11247`). Note: the comment at `:1091` still says “default 3” and is stale — do not encode it |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch | `develop` | Parent handoff + `gh pr view 1758` | 2026-09-17, `develop` ancestor SHA `32605700` (not the plan worktree revision `1d9cd0e0` in the Verification Log — different surfaces, both intentional) | Item #1757 only | `Verified` |
| Same-surface concurrent PRs | none | Parent batch dispatch (`1757,1462,1496,1515,1561,1583,1529`) | 2026-09-17 | Same-surface open PRs at dispatch: none | `Verified` |
| Codex companion exit-code contract | `0/1/2/3/4` documented in companion header | `codex-github-reviewer.sh` lines 29–34 | 2026-09-17 | No batch peer targets `codex-github-reviewer.sh` classification | `Verified` |

**Conflict evidence**: none.

---

## Layer-by-Layer Changes

> Database, shared packages, frontend, and infrastructure layers do not apply.

### Script layer — `codex-github-evidence-lib.sh` (new, shared) + `codex-github-reviewer.sh`

Create `scripts/development-workflow/codex-github-evidence-lib.sh` for the
classifier helpers below. Source that file from both the companion and
`pr-review-loop.sh`. Keep poll/trigger orchestration in the companion.

Record the **provider fields** the plan relies on (spec Business Rule 1):

| Concept | GitHub surface | Fields / identifiers |
| --- | --- | --- |
| Conversation resolution | GraphQL `reviewThreads` | `isResolved`, `isOutdated`, `comments(first:1)` author login + body, `comments(last:1)` author + `createdAt` |
| Live revision | REST reviews + PR head | Review `commit_id`, `state` (`CHANGES_REQUESTED` short-circuit), `submitted_at`; PR `headRefOid` |
| Thread correlation | GraphQL + REST join | See **Finding–thread correlation contract** below |
| Dismissed review | REST reviews | `state: DISMISSED` excluded from terminal evidence selection |
| Root comment terminal evidence | REST issue comments | `Reviewed commit` marker, `created_at`, comment `id` ordering vs trigger comment |
| Availability (unchanged) | Root comment body | Usage-limit, account-not-connected, environment-setup patterns already recognized |
| Head evidence window bounds | REST PR object + issue timeline | PR `created_at`; `GET repos/{owner}/{repo}/issues/{pr}/timeline` (paginated) `head_ref_force_pushed.created_at` and `committed` events' `sha` + `committer.date` — see **Head evidence window attribution** for the derivation and its mandatory escalation cases |

**Finding–thread correlation contract** (AC-7, spec Business Rules 4–6):

1. **Thread index (GraphQL)**: Paginate `reviewThreads` and record per thread:
   `thread_graphql_id`, `isResolved`, `isOutdated`, first-comment
   `comments(first:1).nodes[0].databaseId`, first-comment `author.login`, review
   attachment via parent review `commit_id` when available from REST review fetch.
   Applicability: thread is **applicable** to live head when `isOutdated` is false
   and the anchoring review’s `commit_id` equals `headRefOid` (or inline comment
   `commit_id` equals `headRefOid` when review object lacks commit).
2. **Inline comment index (REST)**: `GET repos/{owner}/{repo}/pulls/{pr}/comments`
   (paginated); keep Codex-bot rows where `commit_id == headRefOid`.
3. **Join key**: REST comment `id` **equals** GraphQL first-comment
   `databaseId` for the same thread (same join `pr-review-loop.sh` already uses
   for thread audit fixtures in `test-item-completion-self-check.sh`).
4. **Finding extraction**: For a terminal blocking review, treat each distinct
   inline comment on the current head (step 2) as one finding with stable thread
   id = comment `id`. Review-body-only blocking sections with **no** matching
   inline comment id in the index are **correlation-missing** findings (escalate
   `codex_finding_thread_correlation_missing`), including top-level-only blocking
   text like `codex_cleared_thread_top_level_blocker`. **Exception (orthogonal):**
   GitHub `state == CHANGES_REQUESTED` on a current-head submitted review is an
   actionable blocker by structured state even when no inline finding maps to a
   thread — but if that same review body also contains a separate uncorrelated
   finding marker, correlation-missing escalation takes precedence (spec matrix
   row).

- [ ] **Bounded evidence query** (AC-1–4, 7–9, 14–16): Extend
  `codex_review_thread_evidence_counts()` (`codex-github-reviewer.sh:273`,
  confirmed in the Verification Log) to return structured
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

- [ ] **Head evidence window attribution** (AC-14): For trigger-less root
  comments, assign each comment to the head that was current when authored,
  using the **head-transition timeline** below as the sole chronology source; if
  the window boundary cannot be established deterministically from it, escalate
  `evidence_unavailable_codex_thread_state` rather than attributing to live head.

  **Head-transition timeline (deterministic source).** Build the window
  boundaries from `GET repos/{owner}/{repo}/issues/{pr}/timeline` (paginated,
  `Accept: application/vnd.github+json`) joined with the PR object's
  `created_at`:

  The spec fixes the two boundaries from **different** sources. Use each only
  where named; do not substitute one for the other.

  1. **Lower bound `L(H)`** comes from *triggers*, never from transition
     instants — per spec Business Rule "after any review trigger for that head,
     or — for a trigger-less head — after the previous head's last review
     trigger or the pull request's creation, whichever is later":
     - `H` has at least one review trigger → `L(H)` is that trigger's
       `created_at` (the latest such trigger for `H`).
     - `H` is trigger-less → `L(H) = max(previous head's last review trigger,
       PR created_at)`. When `H` is the first head, the PR `created_at` alone
       applies.
  2. **Upper bound `U(H)`** comes from *transition instants* — per the spec's
     "and before any later head becomes current". `U(H)` is the instant the
     **next** head became current, which is, in order of preference: (a) the
     `created_at` of the `head_ref_force_pushed` timeline event that introduced
     that next head, when one exists; otherwise (b) the `committer.date` of the
     `committed` timeline event whose `sha` is that next head.
  3. **A comment's window** is therefore `[L(H), U(H))`. **The live head's
     window is open-ended**: no later head exists, so `U(live)` is unbounded and
     a missing next-transition event is the expected state for it, never an
     indeterminate one. Only a *superseded* head has a finite `U(H)`.

  **Mandatory escalation cases.** These concern `U(H)` only, because `L(H)` is
  trigger-derived and exact. `U(H)` source (b) is a commit-authoring timestamp,
  not a push timestamp, so it is only a *lower bound* on when the next head
  became current. Attribution is *indeterminate* — escalate
  `evidence_unavailable_codex_thread_state`, do not guess — whenever any of:
  - the timeline read fails or is truncated after one retry;
  - **(superseded heads only)** no `head_ref_force_pushed` or `committed` event
    introduces the next head, so `U(H)` cannot be derived at all;
  - **(superseded heads only)** `U(H)` came from source (b) and the comment's
    `created_at` falls at or after it, so the commit-date lower bound does not
    prove the comment preceded the next head; or
  - two candidate boundaries share the comment's timestamp second and no
    comment-ID ordering resolves them.

  A comment is attributed to head `H` when `L(H) <= created_at` and either
  `U(H)` is unbounded (live head) or source (a), or an unambiguous source (b),
  places `created_at` strictly before `U(H)`. The second and third cases above
  cannot arise for the live head, which has no `U(H)`: a comment at or after
  `L(live)` is attributed to the live head, not escalated.

- [ ] **Decision function** (spec matrix): Implement
  `codex_classify_live_head_evidence()` returning one of:
  `clean`, `needs_fixes`, `waiting_on_reviewer` (+ reason), `escalate` (+ reason).
  **Pre-selection guard:** before newest-evidence timestamp selection, first
  classify every item in the fetched batch, then scan for genuine usage-limit or
  account-not-connected notices. Terminate immediately with the shipped
  unavailable outcome (same as today’s `codex_return_usage_limit` /
  account-not-connected path) **only when the batch contains neither**:

  - blocking evidence or a `CHANGES_REQUESTED` submitted review, **nor**
  - any fail-closed evidence — malformed-marker, unrecognized-verdict,
    correlation-missing, or evidence-unavailable.

  When either is present alongside the notice, the availability hard stop does
  **not** short-circuit: fall through to the tie precedence below, which ranks
  all four fail-closed escalations and the actionable blocker above the
  availability hard stop. This preserves the spec’s rule that “an availability
  response never outranks an escalation or an actionable blocker”; a guard that
  short-circuits on fail-closed evidence would invert it, and would contradict
  the `codex_tied_usage_limit_then_unrecognized` regression, which must expect
  escalation rather than the unavailable outcome. Only a notice standing alone
  — with no blocker and no fail-closed evidence — skips the timestamp
  tournament. Otherwise apply newest-non-dismissed
  timestamp selection among live-head-covering items, then tie precedence:
  malformed-marker → unrecognized → correlation-missing → evidence-unavailable →
  actionable blocker → availability hard stop (usage-limit or
  account-not-connected) → cleared-findings wait → clean. A retained
  environment-setup response participates only when it is itself the newest
  evidence and is superseded by any strictly newer terminal or review item
  (spec BR-8); it is not the hard-stop tier above.

- [ ] **Outcome mapping** (Statuses table): Emit companion stdout keys:
  - `VERDICT: APPROVED` → exit `0`
  - Actionable blocker → exit `1` with blocking summary (unchanged shape)
  - Timed out → exit `2` with **exactly** `REASON=timeout`;
    hard unavailable → exit `3` (unchanged)
  - `waiting_on_reviewer` → exit `4` with `REASON=codex-github-review-pending` or
    `REASON=codex-github-reaction-without-review`
  - Fail-closed escalations → exit `2` with `REASON=` one of
    `evidence_unavailable_codex_thread_state`,
    `codex_current_verdict_malformed_revision_marker`,
    `codex_finding_thread_correlation_missing`,
    `codex_current_verdict_unrecognized`
    (reuse exit `2` with distinct `REASON=`; the loop adapter already maps
    non-`0/1/3/4` exits via `kv_value_default REASON … timeout` to
    `RESULT=escalate` — preserve that contract)
  - **Exit `2` `REASON=` is a closed set of exactly five values**: `timeout`,
    `evidence_unavailable_codex_thread_state`,
    `codex_current_verdict_malformed_revision_marker`,
    `codex_finding_thread_correlation_missing`, and
    `codex_current_verdict_unrecognized`. The companion must emit one of these
    verbatim on every exit-`2` path. This is load-bearing, not stylistic:
    `pr-review-loop.sh:2322` reads the reason via
    `kv_value_default REASON "$script_output" timeout`, so an absent,
    misspelled, or out-of-set `REASON` **silently degrades a fail-closed
    escalation into `timeout`** — which the loop may retry rather than stop for
    human review. Add a harness assertion that every exit-`2` path emits a
    member of this set.
  - Update the companion header exit-code comment block so exit `2` documents
    both timeout and fail-closed escalation (discriminated by `REASON=`), and
    remove the “unrecognized → NEEDS_REVISION safe-fail” wording (AC-7).

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
  gate. Instead call the shared classifier from
  `codex-github-evidence-lib.sh` that counts only **applicable unresolved**
  Codex conversations for the live head (head SHA / review `commit_id`
  correlation, not merely `isOutdated`). Resolved, outdated, and
  dismissed-attached threads must not increment blocker counts.

- [ ] **Companion exit adapter** (AC-1–2, 7–9): On companion exit `1`, remove
  the `unresolved_count=1` floor when strict applicable-unresolved count is
  zero; map companion `REASON=` to loop `RESULT`/`REASON` without upgrading waits
  or escalations to `needs_fixes`. On exit `2`, propagate spec escalation reason
  codes to `RESULT=escalate` (not `timeout` unless reason says so).

- [ ] **Cycle-limit interaction** (AC-5–6): In the reviewer-loop cap check
  (`reviewer_loop_cap_exceeded`, the enforcement block confirmed in the
  Verification Log), evaluate current
  head evidence **before** escalating for exhausted allowance: canonical terminal
  clean evidence in the final permitted cycle proceeds to readiness; exhausted
  allowance with cleared-findings retrigger or remaining actionable findings
  escalates (cleared wait must not bypass cap — spec precedence).

- [ ] **Independent allowance resolution** (AC-6): No change to
  `reviewer_loop_resolve_max_cycles` / `reviewer_loop_resolve_max_total_cycles`
  semantics — add harness coverage in `test-pr-review-loop.sh` that omits
  `review.max_cycles` (defaults per-run to 10, lifetime stays configured/25),
  sets only invalid `review.max_cycles` (warn + default 10 while lifetime keeps
  explicit value), and sets only invalid `review.max_total_cycles` (warn + default
  25 while per-run keeps explicit value). Assert WARN lines and resolved caps via
  existing resolver helpers.

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
  `codex_resolved_visible_finding_waits_after_revision_push`: fixture with **prior
  head** `cccc…` where Codex left a blocking inline thread, operator resolves it
  (`isResolved=true`), then PR advances to **live head** `ffff…` with the old
  review/comment still visible (outdated or resolved-on-new-head). Expect companion
  exit `4` / `REASON=codex-github-review-pending` — not `needs_fixes` from
  historical visibility alone. Include a second sub-assertion on current head
  `ffff…` with resolved non-outdated thread + current-head COMMENTED review body
  listing blocking markers (cleared-findings retrigger path).

- [ ] **Matrix spot checks** (AC-7–14): Add focused mock-`gh` cases (one per
  escalation reason, cleared-findings wait vs clean tie, stale-head malformed
  ignored, `CHANGES_REQUESTED` with all threads resolved, empty reviewed-commit
  field, freshness-failing marker-pinned comment). Update existing Area 13 tests
  that expect `NEEDS_REVISION (unrecognized response format — safe-fail)` to
  expect escalate / `codex_current_verdict_unrecognized` instead, and update
  `codex_cleared_thread_top_level_blocker_*` expectations from exit `1` /
  `NEEDS_REVISION` to the correlation-missing escalation path when the body has
  unthreaded blocking text with no matching inline comment id.

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

1. Resolved thread after revision push + visible prior-head blocking artifact →
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

### Parser-risk addendum (`Reviewed commit` marker + blocking-body scan)

**Edge-case enumeration** (concrete inputs for `codex_parse_reviewed_commit_marker`
and head-attribution helpers):

| Case | Example marker / input | Expected class |
| --- | --- | --- |
| Valid prefix | Live head `abc1234…`, marker `abc1234` | Well-formed, live-head |
| Prior revision well-formed | Marker resolves to parent SHA, not live head | Stale / pending, not malformed |
| Empty value | `Reviewed commit:` with no token | Malformed |
| Non-hex token | `Reviewed commit: not-a-sha` | Malformed |
| Multiple tokens | `Reviewed commit: abc def` | Malformed |
| Ambiguous prefix | Two commits share prefix `abc1234` | Malformed |
| Interior substring | Live `deadbeef…`, marker `adbeef` at offset > 0 | Malformed |
| Superstring | Marker token strictly longer than live head containing live head | Malformed |
| Freshness fail | Marker names live head but comment predates trigger | Stale pending |
| Same-second tie | Trigger and comment share `created_at` second; lower comment id | Stale pending |
| Same-second tie win | Comment id orders after trigger id | Fresh terminal |
| Stale-head window | Malformed marker authored under prior head | Ignored for live head |
| Indeterminate window | Cannot place trigger-less comment relative to prior head | Evidence unavailable |

**Unit test mapping** (all in `scripts/development-workflow/tests/test-pr-review-loop.sh`
Area 13 — one `run_test` per row):

| Test name prefix | Edge case row |
| --- | --- |
| `codex_marker_valid_prefix` | Valid prefix |
| `codex_marker_prior_revision_stale` | Prior revision well-formed |
| `codex_marker_empty_value` | Empty value |
| `codex_marker_non_hex` | Non-hex |
| `codex_marker_multiple_tokens` | Multiple tokens |
| `codex_marker_ambiguous_prefix` | Ambiguous prefix |
| `codex_marker_interior_substring` | Interior substring |
| `codex_marker_superstring` | Superstring |
| `codex_marker_freshness_fail` | Freshness fail |
| `codex_marker_same_second_stale` | Same-second tie (stale) |
| `codex_marker_same_second_fresh` | Same-second tie win |
| `codex_marker_stale_head_window` | Stale-head window |
| `codex_marker_indeterminate_window` | Indeterminate window |
| `codex_tied_usage_limit_then_unrecognized` | Availability notice tied with fail-closed evidence — **existing test, update to expect escalation** (not the unavailable outcome) |
| `codex_tied_usage_limit_then_blocker` | Availability notice tied with an actionable blocker — expect `needs_fixes` |

**Suppression semantics**: Not applicable — no inline suppressions for marker parsing.

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
| Classifier divergence between companion and loop phase 1 | Med | High | Single shared `codex-github-evidence-lib.sh` sourced by both; never source the companion executable |
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

1. Create `scripts/development-workflow/codex-github-evidence-lib.sh` with
   unit-testable Codex thread + evidence helpers (no top-level side effects);
   source it from `codex-github-reviewer.sh` and `pr-review-loop.sh`; commit.
2. Implement terminal evidence collector + marker parser + window attribution; commit.
3. Implement `codex_classify_live_head_evidence()` decision matrix and wire all
   companion exit paths; commit.
4. Update `run_codex_github_review()` adapter (phase 1 + exit mapping + remove
   count floor); commit.
5. Adjust cycle-limit block to evaluate canonical clean before cap escalation; commit.
6. Add independent `review.max_cycles` / `review.max_total_cycles` resolver harness
   cases (AC-6); commit.
7. Add/update Area 13 harness cases (marker table + primary regression) + one
   `run_codex_github_review` case; commit.
8. Update `codex-github.md` and Protocol 93 cross-links; commit.
9. Run `bash scripts/development-workflow/tests/test-pr-review-loop.sh` (or CI
   equivalent) and fix failures.
10. Add `changelog.d/1757.fix.resolved-codex-findings.md` fragment:

   ```markdown
   - **Resolved Codex findings no longer block reviewer loop** (#1757): Count only applicable unresolved Codex review conversations toward `needs_fixes`; treat cleared findings as a wait for fresh terminal clean evidence; add fail-closed Codex escalation reason codes per spec.
   ```

11. Verify smoke runbook steps on a test PR when possible.

---

## Document Quality Gate

- Spec/brief coverage: Checked — plan maps spec acceptance criteria 1–16 and the
  decision-gate matrix to layer tasks, tests, and docs; CodeRabbit assessment is
  explicit (AC-16).
- Implementation-order consistency: Checked — shared evidence lib extraction
  precedes classifier, adapter, caps, tests, docs; step numbers updated after
  AC-6 harness addition.
- Verification support: Checked — Verification Log commands are reproducible from
  repo root; thread-correlation join cites GraphQL `databaseId` + REST `id`.
- Parser-risk completeness: Checked — dedicated addendum with 13 enumerated
  marker cases and 1:1 Area 13 test name mapping.
- Complex workflow decision-gate matrix: Checked — spec matrix is authoritative;
  implementation mirrors spec rows via `codex_classify_live_head_evidence()`; tie
  precedence matches BR-8 (usage-limit / account-not-connected hard-stop tier;
  environment-setup retained separately); no contradictory next actions in plan
  layers.
- Concurrent-event-source: Not applicable — single-threaded bash polling, no shared
  mutable async listeners.
- CHANGELOG literal format: Checked — step 10 uses `**Bold Title** (#1757):` bullet.
- Plan-stage artifacts only: Checked — plan + smoke runbook only on this branch.
- Cross-section naming: Checked — primary regression harness name
  `codex_resolved_visible_finding_waits_after_revision_push` matches the smoke
  runbook; shared lib path is `codex-github-evidence-lib.sh` everywhere.

### Decision-gate matrix (plan mirror — normative source is spec)

The merged spec’s **Complex Workflow Decision-Gate Matrix** is the authoritative
row set. Implementation must not invent alternate outcomes. Mirror surfaces:
`codex-github-reviewer.sh` exit/`REASON=`, `run_codex_github_review()` `print_kv`,
Protocol 93, `codex-github.md`, PR summary.

| Gate input (abbrev.) | Allowed outcome | Required next action |
| --- | --- | --- |
| Applicable unresolved thread on live head | Actionable blocker → `needs_fixes` | Fix loop |
| All findings cleared, no other unresolved thread | `waiting_on_reviewer` / `codex-github-review-pending` | Retrigger / await clean verdict |
| Terminal clean evidence for live head | Clean | Continue readiness |
| Fail-closed escalation tiers | `escalate` + spec reason code | Human review |
| Cycle cap exhausted after evidence requires another cycle | Escalate | Human review |
| Canonical clean in final allowed cycle | Clean | Continue readiness |

Full row detail, examples, and precedence ordering remain in the spec; the
implementation plan’s classifier step implements that table verbatim.

---

## Cross-Cutting Operational Assumption Check — Implementation-start records

| Assumption | Plan record | Implementation-start check |
| --- | --- | --- |
| Base branch `develop` | Verified 2026-09-17 | Re-verify `origin/develop` before PR |
| No concurrent Codex classifier PRs in batch | Verified at dispatch | `Still valid` unless a same-surface PR merged mid-batch |
| Companion exit codes unchanged for availability | Verified | `Still valid` — preserve exits `2`/`3` for timeout/unavailable |

Implementer must mark `Still valid` or stop with evidence if stale.

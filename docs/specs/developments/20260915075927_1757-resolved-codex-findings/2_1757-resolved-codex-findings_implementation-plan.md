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
| Evidence-counts symbol | `grep -n 'codex_review_thread_evidence_counts' scripts/development-workflow/codex-github-reviewer.sh` | Defined at `codex-github-reviewer.sh:273`; sole caller at `:1497`. Today's only definition — the plan **moves** it to `codex-github-evidence-lib.sh` under the same name and repoints `:1497`, rather than extending it in place, so both scripts share one implementation |
| Cycle-cap enforcement block | `grep -n 'reviewer_loop_cap_exceeded\\|max_cycles enforcement' scripts/development-workflow/pr-review-loop.sh` | Enforcement block at `pr-review-loop.sh:10958` (`#1502` dual-cap); escalation predicate is `reviewer_loop_cap_exceeded`, reason string `max_cycles_exceeded` |
| Timeline event fields | `gh api repos/{owner}/{repo}/issues/1768/timeline -H 'Accept: application/vnd.github+json'` | `committed` events carry `sha` and `committer.date`; their own `created_at` is `null`. No `head_ref_force_pushed` events exist in this repo to sample (force-push on shared branches is prohibited), so the force-push event→head join is **unverified** — see source (a) above |
| Environment-setup outcome | `sed -n '1372,1382p' scripts/development-workflow/codex-github-reviewer.sh` | `codex_return_environment_error` emits `REASON=codex-github-environment-missing` and `exit 2`; retained unchanged by this item (see the exit-`2` retained-contract table) |
| Exit-2 reason inventory | `grep -n 'exit 2' scripts/development-workflow/codex-github-reviewer.sh` plus the nearest preceding `REASON=` per hit, and `grep -n 'run_test "codex_[a-z0-9_]*" "2"' scripts/development-workflow/tests/test-pr-review-loop.sh` | 52 `exit 2` sites. Only five sites emit a reason, covering four distinct reasons: `codex-github-environment-missing` (`:1381`), `codex-github-reaction-without-review` (`:1402`), `codex-github-head-changed` (`:1411`), and `codex-github-head-unavailable` (`:1420`, `:1428`). Of the remaining 47, 18 are usage/argument-validation/`gh auth`/HEAD-resolution exits (`:94`–`:214`) and 29 are reason-less `VERDICT: TIMED_OUT …` fetch/poll/trigger failures. 17 harness cases assert a codex exit code of `2`; `codex_pre_trigger_head_changed_*` (`tests:5348`, `:5351`) and `codex_head_changed_*` (`tests:10335`, `:10336`) pin `codex-github-head-changed`, and `codex_reaction_only_exit_unavailable` (`tests:5435`) pins exit `2` for the acknowledgement wait. Exit `4` exists on exactly one shipped path (`:2508`, `REASON=codex-github-review-pending`) |
| Exit-2 reason default | `sed -n '2320,2333p' scripts/development-workflow/pr-review-loop.sh` | `codex_reason="$(kv_value_default REASON "$script_output" timeout)"` at `:2322`; `print_kv RESULT escalate` (`:2323`) and `return 2` (`:2332`) are unconditional — an out-of-set `REASON` loses the reason string, not the escalation |
| Inline-comment review join | `gh api repos/{owner}/{repo}/pulls/1768/comments?per_page=1 --jq '.[0] \| {id, pull_request_review_id, commit_id}'` and the matching GraphQL `reviewThreads → comments(first:1) → pullRequestReview.databaseId` | REST returns `id=4056981858`, `pull_request_review_id=5260609621`, `commit_id=37d5bd35…` for a `chatgpt-codex-connector[bot]` comment; GraphQL returns `databaseId=4056981858` with `pullRequestReview.databaseId=5260609621` for the same thread. Both review-scoping joins exist and agree |
| Exit-`3` reason hardcode | `sed -n '2292,2302p' scripts/development-workflow/pr-review-loop.sh` | `print_kv REASON codex-github-usage-limit` is unconditional at `:2294`, discarding the companion's `REASON=`; the companion's `codex_return_account_not_connected` emits `REASON=codex-github-account-not-connected` then `exit 3` (`codex-github-reviewer.sh:1384–1393`), so that outcome is reported today as a usage limit |
| Push-proving anchor availability | `gh api repos/{owner}/{repo}/commits/9d98fe2f/check-runs --jq '.check_runs[0].started_at'` and `gh api repos/{owner}/{repo}/statuses/9d98fe2f` | Check runs return `started_at` (`2026-09-20T16:17:04Z`) and commit statuses return `created_at` for a head SHA; both are attached only after a push, so either is a valid `P(H)`. Availability is repo-dependent — a trigger-less head with no CI has no anchor and takes the indeterminate-escalation path |
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
| Head evidence window bounds | REST PR object + issue timeline | PR `created_at`; `GET repos/{owner}/{repo}/issues/{pr}/timeline` (paginated) `head_ref_force_pushed.created_at` and `committed` events' `sha` + `committer.date`; check-run `started_at` / commit-status `created_at` for the head SHA as the push-proving anchor `P(H)` — see **Head evidence window attribution** for the derivation and its mandatory escalation cases |

**Finding–thread correlation contract** (AC-7, spec Business Rules 4–6):

1. **Thread index (GraphQL)**: Paginate `reviewThreads` and record per thread:
   `thread_graphql_id`, `isResolved`, `isOutdated`, first-comment
   `comments(first:1).nodes[0].databaseId`, first-comment
   `comments(first:1).nodes[0].pullRequestReview.databaseId` (the **owning
   review**), first-comment `author.login`, review
   attachment via parent review `commit_id` when available from REST review fetch.
   Applicability: thread is **applicable** to live head when `isOutdated` is false
   and the anchoring review’s `commit_id` equals `headRefOid` (or inline comment
   `commit_id` equals `headRefOid` when review object lacks commit).
2. **Inline comment index (REST)**: `GET repos/{owner}/{repo}/pulls/{pr}/comments`
   (paginated); keep Codex-bot rows where `commit_id == headRefOid`, and record
   each row's `pull_request_review_id` alongside its `id` and `commit_id`. Index
   the rows **by `pull_request_review_id`**, not by head alone — a head-only
   index is what allows an unrelated review's comment to supply false
   correlation.
3. **Join keys** (both verified live — see Verification Log):
   - *thread join*: REST comment `id` **equals** GraphQL first-comment
     `databaseId` for the same thread (same join `pr-review-loop.sh` already
     uses for thread audit fixtures in `test-item-completion-self-check.sh`);
   - *review-scoping join*: REST comment `pull_request_review_id` **equals** the
     REST review `id` that reported it, and equals GraphQL
     `comments(first:1).nodes[0].pullRequestReview.databaseId` for the same
     thread. Use it to attribute each inline comment to exactly one review.
4. **Finding extraction — scoped to the owning review**: a finding belongs to
   the terminal verdict that reported it, so extraction is per review, never per
   head. For terminal blocking review `R` (REST review `id`), the findings of
   `R` are exactly the step-2 rows whose `pull_request_review_id == R.id`
   **and** `commit_id == headRefOid`; each such row is one finding with stable
   thread id = comment `id`. An inline comment on the live head belonging to a
   *different* review — an earlier Codex review, or another bot — is not a
   finding of `R` and **must never supply correlation for `R`**; correlating
   against the head-wide comment index would turn a review-body-only finding
   into a false `needs_fixes` or a false cleared-findings wait instead of the
   spec-required escalation. Review-body-only blocking sections of `R` with
   **no** inline comment of `R` to match are **correlation-missing** findings
   (escalate `codex_finding_thread_correlation_missing`), including
   top-level-only blocking text like `codex_cleared_thread_top_level_blocker`.
   A terminal verdict delivered as a **root pull-request comment** owns no
   review at all, so any blocking finding it carries has no review-thread
   identifier and is correlation-missing by the same rule (spec: "A review-level
   finding or comment without a review-thread identifier is incomplete
   evidence, not an actionable blocker"). The cleared-findings rule consumes
   this same per-review finding set: "every matching conversation is resolved"
   is evaluated over `R`'s own findings, never over unrelated live-head
   threads. **Exception (orthogonal)
   — canonical wording, restated verbatim in the "CHANGES_REQUESTED +
   correlation-missing" step below:** GitHub `state == CHANGES_REQUESTED` on a
   current-head submitted review is an actionable blocker by structured state
   when the review carries **no finding requiring correlation at all** — the
   structured state alone is the blocker, and the absence of inline findings is
   not correlation-missing. If the review carries **any** finding that lacks a
   stable thread identifier or has no identifiable matching conversation,
   `codex_finding_thread_correlation_missing` escalation takes precedence over
   the structured blocker — including when *every* such finding lacks thread
   identity, not only when one lacks it alongside a correlated one (spec: "when
   such a review also carries a finding with no stable review-thread identifier
   or no identifiable matching conversation, the correlation-missing escalation
   takes precedence").

- [ ] **Bounded evidence query** (AC-1–4, 7–9, 14–16): **Move**
  `codex_review_thread_evidence_counts()` out of the companion
  (`codex-github-reviewer.sh:273`, confirmed in the Verification Log) **into**
  `codex-github-evidence-lib.sh`, keeping the name so the move is traceable.
  This is a move, not a copy — the Risks table's mitigation is a single shared
  lib sourced by both and "never a second implementation", so no classification
  logic may remain in the companion. Update its sole caller
  (`codex-github-reviewer.sh:1497`) to call the sourced function, and have
  `run_codex_github_review()` phase 1 in `pr-review-loop.sh` call **this same
  function**; no second function is introduced. Extend it to return structured
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
  using the **head-transition timeline** below as the chronology source; if
  the window boundary cannot be established deterministically from it, escalate
  `evidence_unavailable_codex_thread_state` rather than attributing to live head.

  **Head-transition timeline (deterministic source).** Build the window
  boundaries from `GET repos/{owner}/{repo}/issues/{pr}/timeline` (paginated,
  `Accept: application/vnd.github+json`) joined with the PR object's
  `created_at`:

  The two boundaries draw on different sources and must not be substituted for
  one another: `L(H)` combines a *trigger-derived* bound with `H`'s own
  transition instant, while `U(H)` is purely a transition instant.

  1. **Lower bound `L(H)`** starts from a *trigger-derived* bound — per spec
     Business Rule "after any review trigger for that head, or — for a
     trigger-less head — after the previous head's last review trigger or the
     pull request's creation, whichever is later":
     - `H` has at least one review trigger → `L(H)` is that trigger's
       `created_at` (the latest such trigger for `H`).
     - `H` is trigger-less → `L(H) = max(previous head's last review trigger,
       PR created_at)`. When `H` is the first head, the PR `created_at` alone
       applies.
     **`L(H)` is additionally floored by `T(H)`, the instant `H` itself became
     current**: `L(H) = max(trigger-derived bound, T(H))`. The spec's governing
     clause is "the live head that was **current when the comment was
     authored**", and a comment authored before `H` was pushed was not authored
     while `H` was current. The trigger-derived bound alone does not enforce
     this — for a trigger-less head it can sit well before the push, which would
     sweep prior-head comments (including malformed ones) into `H` and escalate
     against the wrong head. **This floor applies to the live head too.** When
     `T(H)` comes from source (b) — the normal case — the floor is raised
     further to the push-proving anchor `P(H)` of item 3, because a commit date
     alone does not prove the push preceded the comment.
  2. **Transition instant `T(X)`** — the instant head `X` became current — is
     derived as:
     - **(b) — the stated path, verified.** The `committer.date` of the
       `committed` timeline event whose `sha` is `X`. Confirmed against live
       data (Verification Log): `committed` events carry `sha` and
       `committer.date`. Note the event's own `created_at` is `null`; use
       `committer.date`.
     - **(a) — an optimization, UNVERIFIED — implementer must confirm before
       relying on it.** The `created_at` of the `head_ref_force_pushed` event
       that introduced `X`, *if* that payload can be joined to `X` at all. This
       could not be confirmed: no `head_ref_force_pushed` events exist in this
       repository to sample (its safety rules forbid force-pushing shared
       branches), and the event's `commit_id` is reported to be commonly
       `null`, which would make the event→SHA join impossible. **Implement
       source (b) plus the escalation cases below as the complete path.** Adopt
       (a) only after confirming on real data that the payload identifies the
       head it introduced; until then a force-push is simply a case where (b)
       governs or the escalation cases fire.
  3. **Push-proving anchor `P(H)`** — an instant that can only exist *after*
     `H` was pushed, which is exactly what source (b) cannot supply. Source (b)
     is a commit-authoring timestamp: it is a lower bound on the push, so a
     comment authored after `T(H)` but before the push belonged to the previous
     head and `T(H)` alone cannot prove otherwise. Establish `P(H)` from the
     earliest available of:
     - the `created_at` of the `head_ref_force_pushed` event that introduced
       `H` (source (a) — an actual push instant, still UNVERIFIED; adopt only
       after confirming the event-to-SHA join on real data);
     - the `created_at` of the earliest review trigger comment naming `H`, since
       a trigger for `H` can only be authored once `H` is current;
     - the earliest `started_at` of a check run for SHA `H`
       (`GET repos/{owner}/{repo}/commits/{sha}/check-runs`) or the earliest
       `created_at` of a commit status for it
       (`GET repos/{owner}/{repo}/statuses/{sha}`), since CI attaches both only
       after the push (verified — see Verification Log).
     `P(H)` is the source that establishes actual transition ordering. A comment
     is proven to follow `H`'s push only when `P(H) <= created_at`; when no
     `P(H)` source exists for `H`, no comment can be proven to fall inside `H`'s
     window and the attribution is indeterminate.
  4. **Upper bound `U(H)`** is `T(next head)`, per the spec's "and before any
     later head becomes current".
  5. **A comment's window** is therefore `[L(H), U(H))` with
     `L(H) = max(trigger-derived bound, T(H), P(H))`, where `P(H)` participates
     whenever `T(H)` came from source (b). **Only the live head's *upper*
     bound is open-ended**: no later head exists, so `U(live)` is unbounded and
     a missing next-transition event is expected for it, never indeterminate.
     The live head's *lower* bound still requires `T(live)` like any other.

  **Mandatory escalation cases.** Both bounds depend on transition instants, and
  `T(X)` source (b) is a commit-authoring timestamp, not a push timestamp, so it
  is only a *lower bound* on when `X` became current. Attribution is
  *indeterminate* — escalate `evidence_unavailable_codex_thread_state`, do not
  guess — whenever any of:
  - the timeline read fails or is truncated after one retry, or the check-run /
    commit-status read used for `P(H)` fails after one retry;
  - **`T(H)` cannot be derived** — no `head_ref_force_pushed` or `committed`
    event introduces `H`. This applies to the live head as well: without
    `T(live)` there is no floor, and a prior-head comment could be escalated
    against the live head;
  - **`T(H)` came from source (b) and no `P(H)` orders at or before the
    comment** — either no push-proving anchor exists for `H` at all, or the
    earliest one is strictly later than the comment's `created_at`. The
    commit-date bound alone never proves the comment followed `H`'s push, so
    this single case covers both `created_at <= T(H)` and the ambiguous
    `T(H) < created_at < push(H)` interval in which the comment was still
    authored under the previous head;
  - **(superseded heads only)** `U(H)` cannot be derived, or came from source
    (b) and the comment's `created_at` falls at or after it, so the bound does
    not prove the comment preceded the next head; or
  - two candidate boundaries share the comment's timestamp second and no
    comment-ID ordering resolves them.

  A comment is attributed to head `H` only when `L(H) <= created_at` — with
  `T(H)` established either by source (a) or by source (b) plus a push-proving
  anchor `P(H) <= created_at` — **and** either `U(H)` is unbounded (live head)
  or `created_at` falls strictly before an equally well-established `U(H)`. The
  live head is exempt from the `U(H)` cases only; it is never exempt from the
  `T(H)` / `P(H)` cases.

- [ ] **Decision function** (spec matrix): Implement
  `codex_classify_live_head_evidence()` returning one of:
  `clean`, `needs_fixes`, `waiting_on_reviewer` (+ reason), `escalate` (+ reason).
  **Pre-selection guard (early exit only):** before newest-evidence timestamp
  selection, classify every item in the fetched batch, then scan for genuine
  usage-limit or account-not-connected notices. Terminate immediately with the
  shipped unavailable outcome (same as today’s `codex_return_usage_limit` /
  account-not-connected path) **only when the batch contains none of**:

  - an applicable unresolved live-head conversation;
  - blocking evidence or a `CHANGES_REQUESTED` submitted review; or
  - any fail-closed evidence — malformed-marker, unrecognized-verdict,
    correlation-missing, or evidence-unavailable.

  When any of those is present alongside the notice, the early exit is skipped
  and the full order below decides — which frequently ends at the **same**
  unavailable outcome through the hard-stop restoration rule, because mere
  presence of a competitor is not enough to displace a hard stop; only a
  *canonical* competitor is. The guard is an optimization for the unambiguous
  case and must never be the reason a hard stop is dropped. Classification then
  runs in **three phases, in this order**, executed as the normative
  Evaluation-order list at the end of this step. Phase 1 carries only the
  classes the spec exempts from newest-evidence selection; every other terminal
  class is decided by timestamp in phase 2, because the spec applies its tier
  list *after* selection: "Later
  non-dismissed terminal evidence for the same live head supersedes earlier
  current-head evidence before that precedence ordering is applied."

  **Phase 1 — absolute exceptions (timestamp-independent).** Only these classes
  bypass newest-evidence selection. Take the highest one present and stop. The
  phases are a *precedence* description, not an execution order: classes 2 and 3
  are evaluated against the phase-2 winner where their deferral bullets say so,
  so the implementation always computes the phase-2 winner first and then
  applies the Evaluation-order list below, which is normative wherever the
  narrative and the list could be read differently.

  1. **Indeterminate evidence** → `escalate`
     `evidence_unavailable_codex_thread_state`. A bounded-query failure after
     its retry, or a head-window attribution that cannot be established, is not
     a timestamped evidence item at all — there is nothing to enter into a
     timestamp selection — so this fail-closed escalation is absolute. (An
     evidence-unavailable *item* that does carry a timestamp still competes in
     phase 2 at tier 4.)
  2. **Applicable unresolved live-head conversation** → `needs_fixes`. Spec:
     "This timestamp selection governs terminal verdict evidence only: an
     applicable unresolved Codex conversation for the live head remains an
     actionable blocker regardless of which terminal evidence item is newest, so
     a later availability response or clean verdict does not erase it." One
     deferral applies:
     - **A fail-closed terminal item that wins phase 2** (tiers 1–4) takes
       precedence over this blocker — spec: unrecognized evidence "takes
       precedence over otherwise applicable unresolved conversations", and when
       a verdict mixes a correlated finding with an uncorrelated one "the
       incomplete finding evidence takes precedence". So: if a live-head
       fail-closed item exists, resolve phase 2 first — when that item survives
       newest-evidence selection, its escalation is the outcome; when newer
       clean, wait, or availability evidence supersedes it, this blocker stands
       and the outcome is `needs_fixes`. A phase-2 winner in tiers 5–8 never
       displaces this blocker.
  3. **Availability hard stop** — genuine usage-limit notice or
     account-not-connected refusal → shipped unavailable outcome (exit `3`),
     because the spec makes the two hard stops "bypass newest-evidence selection
     entirely … and [they] are never superseded by a same-fetch or later
     clean/newer review verdict". A hard stop present anywhere in the batch
     therefore beats clean, cleared-findings-wait, and environment-setup
     evidence of **any** timestamp, including strictly newer ones. It yields
     only to a **canonical** competitor, which is exactly one of:
     - an applicable unresolved live-head conversation (class 2 — canonical by
       definition, since conversation state is not timestamped terminal
       evidence): spec, "Blocking or `CHANGES_REQUESTED` evidence always wins
       over any availability notice, including those hard stops"; or
     - a **phase-2 winner in tiers 1–5** — a fail-closed escalation or an
       actionable blocker that actually survives newest-evidence selection:
       spec, "an availability response never outranks an escalation or an
       actionable blocker".

     **Hard-stop restoration (load-bearing).** "Canonical" is decided by
     newest-evidence selection, never by mere presence in the batch. If the
     competing blocker or fail-closed item is itself superseded —
     {`CHANGES_REQUESTED` at T1, clean at T2, usage-limit notice} or {malformed
     marker at T1, clean at T2, notice} — then the phase-2 winner is clean, the
     competitor is no longer canonical, and the hard-stop outcome is
     **restored**: the run ends unavailable (exit `3`), never clean. Letting the
     superseded item suppress the hard stop would contradict "never superseded
     by a same-fetch or later clean/newer review verdict". Regression:
     `codex_hard_stop_restored_when_competitor_superseded`.

  **A phase-1 class beats a newer availability notice or clean verdict — but
  only these classes do.** Everything else is *terminal verdict evidence* and is
  therefore subject to selection: malformed-marker, unrecognized-verdict,
  correlation-missing, `CHANGES_REQUESTED` and other terminal finding evidence,
  cleared-findings wait, and clean. Making those tiers absolute would let an
  *older* malformed, unrecognized, or correlation-missing item override *newer*
  clean evidence for the same head, which the spec forbids twice over: "any
  newer non-dismissed terminal evidence for the same live head — of any tier,
  not only valid evidence — supersedes earlier malformed-marker evidence", and
  "A newer current-head finding, malformed-marker, unrecognized, or
  incomplete-correlation evidence supersedes it under the newest-evidence rule"
  (the converse direction). The inversion the phase order still prevents is the
  narrow one the spec names: a later usage-limit notice burying an earlier
  `CHANGES_REQUESTED` review.

  **Phase 2 — newest-evidence selection, then tie aggregation (always computed;
  it decides whenever phase 1 does not).** Ignore dismissed reviews, keep only
  live-head-covering items (evidence covering an earlier revision never
  competes), take the newest
  non-dismissed terminal timestamp, and aggregate the items sharing exactly that
  timestamp by the spec's tier order:

  | Tie tier (highest first) | Outcome when it wins | Exit / `REASON=` |
  | --- | --- | --- |
  | 1. Malformed marker | `escalate` | `2` / `codex_current_verdict_malformed_revision_marker` |
  | 2. Unrecognized verdict | `escalate` | `2` / `codex_current_verdict_unrecognized` |
  | 3. Incomplete correlation | `escalate` | `2` / `codex_finding_thread_correlation_missing` |
  | 4. Evidence unavailable | `escalate` | `2` / `evidence_unavailable_codex_thread_state` |
  | 5. Actionable blocker (incl. `CHANGES_REQUESTED`) | `needs_fixes` | `1` |
  | 6. Availability hard stop | Shipped unavailable outcome | `3` |
  | 7. Cleared-findings wait | `waiting_on_reviewer` | `4` / `codex-github-review-pending` |
  | 8. Clean | `clean` | `0` |
  | (unranked) Retained environment-setup response | Unavailable (shipped handling, not a hard stop) | `2` / `codex-github-environment-missing` (`codex_return_environment_error`, Verification Log) |

  **Tie rule**: tiers 1–8 resolve strictly in the order above, so on an equal
  newest timestamp cleared-findings wait beats clean. Tier 6 appears here as
  well as in phase 1 so that a hard stop tied at the newest timestamp still
  outranks the wait and clean tiers; a hard stop at an *older* timestamp is
  handled by the hard-stop restoration rule instead, which reaches the same
  unavailable outcome. The
  environment-setup response **loses every tie** — spec BR-8 lets it
  participate "only when it is itself the newest evidence" and it is
  "superseded by any strictly newer terminal or review item", so it wins only
  when *strictly* newest. It is **not** an availability hard stop and never
  enters phase 1; that is the whole difference between it and a usage-limit
  notice, which terminates immediately and is never superseded.

  **Phase 3 — no terminal live-head evidence at all (phases 1 and 2 both
  empty).** Acknowledgement-only signals — a thumbs-up reaction, a draft review,
  or a clean-looking root comment omitting any reviewed revision — are **not
  terminal evidence**, so they never compete in phase 1 or phase 2 and have no
  rank against those tiers. They are evaluated only here:

  - an acknowledgement signal is present for the live-head attempt →
    `waiting_on_reviewer`, exit `4`, `REASON=codex-github-reaction-without-review`;
  - otherwise (only stale, prior-revision, freshness-failing, or no evidence)
    → `waiting_on_reviewer`, exit `4`, `REASON=codex-github-review-pending`.

  This is the spec's acknowledgement-precedence rule: the reaction reason "takes
  precedence over `codex-github-review-pending` whenever an acknowledgement
  signal is present". That precedence is **between the two phase-3 reasons
  only** — it never promotes acknowledgement above a phase-1 or phase-2 class.

  **Evaluation order (normative).** The phases above state *precedence*; this is
  the order the implementation executes, and it is the tie-breaker for any
  reading dispute between them:

  1. Classify every fetched item; if evidence is indeterminate (bounded-query
     failure after its retry, or an unestablishable head window) → `escalate`
     `evidence_unavailable_codex_thread_state` (phase-1 class 1).
  2. Compute the phase-2 winner `W`: the newest non-dismissed timestamp among
     live-head-covering terminal items, with items sharing exactly that
     timestamp aggregated by tiers 1–8. `W` may be empty.
  3. `W` is a fail-closed escalation (tiers 1–4) → that escalation.
  4. An applicable unresolved live-head conversation exists → `needs_fixes`.
  5. `W` is an actionable blocker (tier 5) → `needs_fixes`.
  6. The batch contains an availability hard stop (tier 6 at any timestamp) →
     shipped unavailable outcome, exit `3`. **This step is the hard-stop
     restoration rule**; it fires whether the hard stop won step 2 or lost it to
     a clean, wait, or environment-setup item.
  7. `W` exists (tiers 7–8, or a retained environment-setup response) → its
     outcome from the phase-2 table.
  8. Otherwise → phase 3 (acknowledgement vs pending wait).

  The pre-selection guard is **step 6 hoisted to the front** for batches where
  steps 3–5 are provably empty, so the guard and the full order cannot disagree
  for any batch. Worked examples, all consistent both ways: {usage-limit at T1,
  strictly newer clean at T2} → unavailable (step 6; guard also fires);
  {`CHANGES_REQUESTED` at T1, clean at T2, notice} → unavailable (guard skipped,
  step 5 does not fire because the blocker is superseded, step 6 restores);
  {malformed at T1, clean at T2, notice} → unavailable (same path);
  {notice and unrecognized tied at the newest timestamp} → escalate (step 3,
  tier 2 outranks tier 6 — the `codex_tied_usage_limit_then_unrecognized`
  regression); {notice and blocker tied} → `needs_fixes` (step 5 —
  `codex_tied_usage_limit_then_blocker`); {unresolved live-head conversation +
  notice} → `needs_fixes` (step 4).

- [ ] **Outcome mapping** (Statuses table): Emit companion stdout keys:
  - `VERDICT: APPROVED` → exit `0`
  - Actionable blocker → exit `1` with blocking summary (unchanged shape)
  - Timed out → exit `2`. The shipped timeout paths emit **no** `REASON=` at
    all and the loop supplies `timeout` through
    `kv_value_default REASON "$script_output" timeout`; keep that behaviour and
    do **not** add a `REASON=timeout` line to the 29 reason-less
    `VERDICT: TIMED_OUT …` paths (Verification Log row `Exit-2 reason
    inventory`). Hard unavailable → exit `3` (unchanged, but see the Exit-`3`
    reason propagation step)
  - `waiting_on_reviewer` → exit `4` with `REASON=codex-github-review-pending`
    (already shipped at `codex-github-reviewer.sh:2508`) or
    `REASON=codex-github-reaction-without-review` (**remapped from exit `2` by
    this item** — see the retained-contract table below)
  - Fail-closed escalations → exit `2` with `REASON=` one of
    `evidence_unavailable_codex_thread_state`,
    `codex_current_verdict_malformed_revision_marker`,
    `codex_finding_thread_correlation_missing`,
    `codex_current_verdict_unrecognized`
    (reuse exit `2` with distinct `REASON=`; the loop adapter already maps
    non-`0/1/3/4` exits via `kv_value_default REASON … timeout` to
    `RESULT=escalate` — preserve that contract)
  - **Exit-`2` contract — retained, remapped, and added.** Exit `2` is *not* a
    closed six-value reason set: the shipped companion already emits four other
    reasons there — three retained by this item, one remapped — and leaves 47 of
    its 52 exit-`2` sites reason-less, so a blanket "every exit-`2` path emits
    one of the new codes" rule would break established behaviour and pinned
    tests. The complete contract after this item (source
    line numbers from the Verification Log row `Exit-2 reason inventory`):

    | Exit-`2` path | `REASON=` today | After this item | Test impact |
    | --- | --- | --- | --- |
    | `codex_return_environment_error` (`:1372–1382`) | `codex-github-environment-missing` | **Retained unchanged** — availability handling, not a fail-closed escalation, and never converted into one | Keeps exit `2`: `codex_environment_missing_exit_unavailable` (`tests:10634`), `codex_async_reaction_environment_exit_unavailable` (`:6092`), `codex_ack_repoll_env_then_reaction_exit_unavailable` (`:6155`), `codex_main_loop_env_then_review_exit_unavailable` (`:6239`), `codex_same_poll_newer_env_error_wins_exit_unavailable` (`:6462`), `codex_env_error_survives_later_ack_exit_unavailable` (`:6511`), `codex_terminal_comment_vs_newer_env_error_exit_unavailable` (`:6559`), `codex_environment_then_clean_comment_exit_unavailable` (`:10417`), `codex_same_second_root_comment_exit_unavailable` (`:10675`) |
    | `codex_return_head_changed` (`:1405–1412`) | `codex-github-head-changed` | **Retained unchanged** — outside this item's evidence model (the head moved, so there is no live-head verdict to classify) | Unchanged: `codex_head_changed_exit_unavailable` / `codex_head_changed_reason` (`tests:10335–10336`), `codex_pre_trigger_head_changed_exit_unavailable` / `codex_pre_trigger_head_changed_reason` (`tests:5348–5351`) |
    | `codex_require_current_head` (`:1414–1434`; exits at `:1420` and `:1428`) | `codex-github-head-unavailable` | **Retained unchanged** | No test pins this reason today — add `codex_head_unavailable_reason_retained` so the retained contract is covered before the classifier work lands |
    | `codex_return_reaction_without_review` (`:1396–1403`) | `codex-github-reaction-without-review` | **Remapped to exit `4`** — the only intentional change on this surface. AC-9 requires `waiting_on_reviewer` for acknowledgement-only evidence, and the loop's exit-`2` arm returns `RESULT=escalate`, so the shipped pairing turns that wait into an escalation. The reason string keeps its shipped name, per the spec's "the two waiting codes are the shipped reason codes and keep their existing names and tests" | `codex_reaction_only_exit_unavailable` (`tests:5435`) expectation `2` → `4`, renamed `codex_reaction_only_exit_waiting`; `codex_reaction_only_reason` (`tests:5436`) unchanged |
    | 29 reason-less `VERDICT: TIMED_OUT …` fetch / poll / trigger failures (`:1500`, `:1522`, `:1628`, `:1633`, `:1688`–`:1698`, `:1773`, `:1821`, `:1865`, `:1877`, `:2022`–`:2138`, `:2206`–`:2412`) | *(none)* | **Retained reason-less** — the loop's `kv_value_default … timeout` supplies `timeout` | Unchanged: `codex_existing_fetch_failure_exit_unavailable` (`tests:4903`), `codex_async_root_fetch_failure_exit_unavailable` (`:5906`), `codex_review_query_failure_exit_unavailable` (`:10156`), `codex_thread_check_failure_exit_code` (`:13158`) |
    | 18 usage, argument-validation, `gh auth`, and HEAD-resolution exits (`:94`–`:214`) | *(none)* | **Retained reason-less** — they fire before any review classification and are not review outcomes | None |
    | New classifier fail-closed escalations | *(new)* | Exit `2` with one of `evidence_unavailable_codex_thread_state`, `codex_current_verdict_malformed_revision_marker`, `codex_finding_thread_correlation_missing`, `codex_current_verdict_unrecognized` | One new Area 13 case per code (matrix spot checks) |

  - **Scoped harness assertion.** The "emits a member of the set" assertion is
    scoped to the **new classifier exit-`2` paths**: every exit `2` returned by
    `codex_classify_live_head_evidence()` must carry one of the four new codes
    verbatim. Do not assert it file-wide — that is exactly the rule that would
    break the retained reason-less paths. Add the complementary non-regression
    assertion that `codex-github-environment-missing`,
    `codex-github-head-changed`, and `codex-github-head-unavailable` still
    appear on their own paths with exit `2`.
  - **Why the reason string matters (for the four new codes).**
    `pr-review-loop.sh:2322` (Verification Log) reads the reason via
    `kv_value_default REASON "$script_output" timeout`. `RESULT=escalate` and
    the `return 2` are unconditional at that site, so a missing `REASON` does
    **not** change control flow or cause a retry — the run still stops for human
    review. What is lost is the *reason string*: the escalation is reported as
    `timeout` in `REASON=`, the Automated Reviewer Loop Summary, and
    `reviewer_loop_history.v1`, making the four fail-closed escalations
    indistinguishable from a poll-budget timeout and from each other. That
    directly defeats this item's own acceptance criterion that every fail-closed
    escalation "is recorded as a terminal human-review escalation".
  - **Adapter safety net for the remapped wait** (AC-9): the loop's exit-`2` arm
    must map a stray `REASON=codex-github-reaction-without-review` to
    `RESULT=waiting_on_reviewer` rather than `escalate`, so a missed companion
    path can never convert that wait into an escalation — the spec lists the
    fail-closed escalations as a complete set that excludes the two wait codes.
    Test: `codex_adapter_exit2_reaction_reason_maps_to_waiting`.
  - Update the companion header exit-code comment block
    (`codex-github-reviewer.sh:29–34`) so exit `2` documents all of its
    discriminated `REASON=` outcomes — reason-less timeout, the retained
    `codex-github-environment-missing`, `codex-github-head-changed`, and
    `codex-github-head-unavailable`, and the four new fail-closed escalation
    codes — so exit `4` lists both wait reasons after the acknowledgement remap,
    and so the “unrecognized → NEEDS_REVISION safe-fail” wording is removed
    (AC-7).
  - **Reversal path for this published contract.** The exit-code / `REASON=`
    surface is consumed by `run_codex_github_review()`, the Automated Reviewer
    Loop Summary, and `reviewer_loop_history.v1`; all three live in this
    repository, so a reversal is an ordinary `git revert` of the companion and
    adapter commits (Implementation Order steps 3–4) together with the Area 13
    expectation updates (step 7) and the doc updates (step 8). No schema
    migration, external publication, or consumer outside this repo is involved,
    and downstream template consumers pick the revert up through
    `/sync-template` like any other change. Two residues do **not** revert and
    are accepted here: history records already written with the new reason codes
    stay on their pull requests (append-only human-readable audit text — a
    revert only stops new ones), and any pull request escalated under a new code
    is simply re-evaluated by the restored behaviour on its next loop run,
    because the Statuses table declares these outcomes are decided per
    evaluation with no valid transitions. Partial reversal of the four
    fail-closed codes alone is **not** supported: the classifier emits them from
    one decision function, so reverting must take steps 3–4 together.

- [ ] **Cleared-findings retrigger** (AC-8): When terminal finding verdict’s
  findings all correlate to resolved applicable conversations and no other
  applicable unresolved conversation exists, return exit `4` /
  `codex-github-review-pending` (post fresh trigger when appropriate), never exit
  `1`. `CHANGES_REQUESTED` submitted review remains exit `1` even if every
  thread is resolved.

- [ ] **CHANGES_REQUESTED + correlation-missing** (AC-7, matrix row) —
  canonical wording, identical to the Finding-extraction exception above: a
  `CHANGES_REQUESTED` current-head review carrying **no finding requiring
  correlation at all** is an actionable blocker by structured state alone. If it
  carries **any** finding lacking a stable thread identifier or an identifiable
  matching conversation — including when *every* finding lacks one — escalate
  `codex_finding_thread_correlation_missing` (precedence over the structured
  blocker).

### Script layer — `pr-review-loop.sh`

- [ ] **`run_codex_github_review()` phase 1** (AC-1–2): Stop using raw
  `check_unresolved_threads` provisional count as the sole `existing_findings`
  gate. Instead call `codex_review_thread_evidence_counts()` — the shared
  classifier moved into `codex-github-evidence-lib.sh` by the Bounded evidence
  query step above, not a new function — which counts only **applicable
  unresolved** Codex conversations for the live head (head SHA / review `commit_id`
  correlation, not merely `isOutdated`). Resolved, outdated, and
  dismissed-attached threads must not increment blocker counts.

- [ ] **Companion exit adapter** (AC-1–2, 7–9): On companion exit `1`, remove
  the `unresolved_count=1` floor when strict applicable-unresolved count is
  zero; map companion `REASON=` to loop `RESULT`/`REASON` without upgrading waits
  or escalations to `needs_fixes`. On exit `2`, propagate spec escalation reason
  codes to `RESULT=escalate` (not `timeout` unless reason says so).

- [ ] **Exit-`3` reason propagation** (Operational Visibility, spec availability
  matrix): the exit-`3` branch prints `print_kv REASON codex-github-usage-limit`
  unconditionally (`pr-review-loop.sh:2294`, Verification Log), so the *other*
  hard-unavailable outcome is mislabelled: the companion's
  `codex_return_account_not_connected` emits
  `REASON=codex-github-account-not-connected` before its own `exit 3`
  (`codex-github-reviewer.sh:1384–1393`), and the loop overwrites it with the
  usage-limit code. Read the companion reason instead —
  `kv_value_default REASON "$script_output" codex-github-usage-limit`, keeping
  today's value as the fallback so a reason-less exit `3` is unchanged — so both
  hard-unavailable outcomes keep their shipped reason codes in `REASON=`, the
  Automated Reviewer Loop Summary, and `reviewer_loop_history.v1`.
  `RESULT=escalate` and `return 2` stay unchanged; this is a reason-string fix,
  not a control-flow change. Exit `3` has exactly two sites in the shipped
  companion — `codex_return_usage_limit` (`:1369`) and
  `codex_return_account_not_connected` (`:1393`), confirmed in the Verification
  Log — so its reason set is closed at `codex-github-usage-limit` and
  `codex-github-account-not-connected`, and this item adds no exit-`3` path.

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

- [ ] **AC-11 — empty vs absent `Reviewed commit` field**: two cases, since the
  two shapes diverge. A root comment carrying the field **with no value**
  escalates `codex_current_verdict_malformed_revision_marker`; a root comment
  that **never carries the field** is acknowledgement evidence and takes the
  wait path (`codex-github-reaction-without-review`). Named explicitly so the
  pair is not read as one case.

- [ ] **AC-12 — freshness-failing marker-pinned comment**: a root comment whose
  well-formed marker names the live head but falls outside the freshness
  boundary is neither acknowledgement nor clean evidence. Expect
  `waiting_on_reviewer` / `REASON=codex-github-review-pending` — explicitly
  **not** an escalation, which is the easy wrong answer here.

- [ ] **AC-13 — trigger-less marker-pinned clean: supersession and collapse**,
  three named cases, because the matrix spot-check bullet below does not prove
  either half of this criterion:
  `codex_triggerless_clean_superseded_by_newer_finding` (a marker-pinned clean
  root comment for a trigger-less live head, followed by strictly newer
  non-dismissed live-head evidence — run the case once per superseding class:
  finding, malformed-marker, unrecognized, incomplete-correlation — expects that
  newer class's outcome, never clean);
  `codex_triggerless_repeated_clean_collapses_to_newest` (three clean comments
  for the same head at distinct timestamps collapse to the newest one, which
  alone decides `clean`); and
  `codex_triggerless_clean_tie_orders_by_comment_id` (two clean comments sharing
  a `created_at` second resolve to the later comment `id`).

- [ ] **AC-5 — cycle-allowance boundary**, three named cases, since the criterion
  has three distinct outcomes:
  `codex_cap_final_cycle_canonical_clean_ready` (canonical terminal clean
  evidence in the final permitted evaluation → readiness, not escalation);
  `codex_cap_exhausted_cleared_findings_escalates` (exhausted allowance whose
  evaluation needs a cleared-findings retrigger → escalate `max_cycles_exceeded`,
  never `waiting_on_reviewer`); and
  `codex_cap_exhausted_actionable_finding_escalates` (exhausted allowance with a
  remaining applicable unresolved live-head finding → escalate
  `max_cycles_exceeded`, never `needs_fixes` and never clean). The third case is
  AC-5's "an exhausted allowance with any remaining actionable finding still
  escalates" clause and has no other named coverage. Run each against both the
  per-run and the lifetime cap (`reviewer_loop_cap_exceeded`, Verification Log).

- [ ] **Exit-`3` reason propagation**, two named cases:
  `codex_exit3_usage_limit_reason_preserved` (companion emits
  `REASON=codex-github-usage-limit` → loop prints the same, unchanged
  behaviour) and `codex_exit3_account_not_connected_reason_preserved`
  (companion emits `REASON=codex-github-account-not-connected` → loop prints
  that code, not the usage-limit code). Assert on the loop's `REASON=` output,
  since the bug is invisible in `RESULT=` / the return code.

- [ ] **Hard-stop restoration ordering** (spec: hard stops are "never superseded
  by a same-fetch or later clean/newer review verdict"), one named case with two
  fixtures: `codex_hard_stop_restored_when_competitor_superseded` — (a)
  `CHANGES_REQUESTED` review at T1, clean live-head verdict at T2, usage-limit
  notice in the same batch, and (b) malformed-marker comment at T1, clean
  verdict at T2, account-not-connected notice in the same batch. Both expect the
  shipped unavailable outcome (exit `3`, availability `REASON=`), **not** clean
  and not the superseded competitor's outcome. This is the case the
  presence-based pre-selection guard alone would get wrong.

- [ ] **Owning-review correlation scoping** (AC-7, spec Business Rule 4):
  `codex_body_finding_unrelated_review_comment_not_correlated` — a terminal
  `R` whose blocking text appears only in the review body, while an unrelated
  earlier review has an inline comment on the same live head. Expect
  `codex_finding_thread_correlation_missing`, proving the join runs on
  `pull_request_review_id`, not on the head-wide comment index. Pair it with
  `codex_body_finding_own_review_comment_correlates` (the same shape where the
  inline comment does belong to `R`) so the join is proved in both directions.

- [ ] **Exit-`2` retained contract and the one remap** (see the retained-contract
  table): update `codex_reaction_only_exit_unavailable` (`tests:5435`) from `2`
  to `4` and rename it `codex_reaction_only_exit_waiting`, leaving
  `codex_reaction_only_reason` (`tests:5436`) untouched; add
  `codex_head_unavailable_reason_retained` for the otherwise untested
  `codex-github-head-unavailable` path; add
  `codex_adapter_exit2_reaction_reason_maps_to_waiting` for the adapter safety
  net; and leave every other exit-`2` expectation in the table unchanged — their
  presence in the run is the non-regression evidence that the retained reasons
  and the reason-less timeout paths survived.

- [ ] **Matrix spot checks** (AC-7–10 and AC-14 — AC-11, AC-12, and AC-13 have
  their own rows above; this bullet covers the remainder of the range, not all
  of it): Add
  focused mock-`gh` cases (one per escalation reason, cleared-findings wait vs
  clean tie, stale-head malformed ignored, `CHANGES_REQUESTED` with all threads
  resolved). Update existing Area 13 tests
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
5. Cycle cap with canonical clean in final cycle → readiness; cap with cleared
   wait → escalate; cap with a remaining actionable finding → escalate (AC-5–6)
6. Unrecognized terminal body → escalate `codex_current_verdict_unrecognized` (AC-7, 14)
7. Finding without thread id → escalate `codex_finding_thread_correlation_missing` (AC-7, 14)
8. Malformed marker on live head → escalate `codex_current_verdict_malformed_revision_marker` (AC-10, 13)
9. GraphQL thread state failure → escalate `evidence_unavailable_codex_thread_state` (AC-14)
10. Acknowledgement-only → `codex-github-reaction-without-review` precedence (AC-9)
11. `CHANGES_REQUESTED` with resolved threads → `needs_fixes` (AC-1, 2)
12. CodeRabbit assessment recorded `shared` or `not_applicable` (AC-16)
13. Trigger-less marker-pinned clean superseded by newer live-head evidence, and
    repeated clean comments collapsing to the newest (comment-ID tie) (AC-13)
14. Account-not-connected hard stop keeps its own exit-`3` reason code instead of
    being reported as a usage limit (Operational Visibility)

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
| Push-unproven window | Comment `created_at` after `T(H)` (commit date) but no `P(H)` anchor orders before it | Evidence unavailable |
| Superseded malformed | Live-head malformed comment older than live-head clean evidence | Ignored — newer clean wins |

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
| `codex_marker_push_unproven_window` | Push-unproven window |
| `codex_tied_usage_limit_then_unrecognized` | Availability notice tied with fail-closed evidence — **existing test, update to expect escalation** (not the unavailable outcome) |
| `codex_tied_usage_limit_then_blocker` | Availability notice tied with an actionable blocker — expect `needs_fixes` |
| `codex_older_malformed_superseded_by_newer_clean` | Older live-head malformed-marker comment with strictly newer live-head clean evidence — expect `clean` (newest-evidence selection precedes tier aggregation), **not** the malformed escalation |
| `codex_hard_stop_restored_when_competitor_superseded` | Availability hard stop with a *superseded* blocker or malformed item and a newer clean verdict — expect the unavailable outcome (exit `3`), never clean |
| `codex_body_finding_unrelated_review_comment_not_correlated` | Review-body-only finding with an unrelated review's inline comment on the same head — expect correlation-missing |
| `codex_body_finding_own_review_comment_correlates` | Same shape, inline comment owned by the terminal review — expect correlation (no escalation) |

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
| Retained exit-`2` reasons regress while adding the new codes | Med | High | Retained-contract table names every retained reason and its pinned test; scoped harness assertion plus a non-regression assertion for the three retained reasons |
| Published exit / `REASON=` contract is hard to unwind | Low | Med | Revert is code-only (Implementation Order steps 3–4 + Area 13 expectations + docs); residues documented in the Outcome-mapping reversal note |
| No push-proving anchor on trigger-less heads makes window attribution escalate often | Med | Med | Anchor sources are ordered cheapest-first (trigger, check run, status); escalation is the spec-mandated fail-closed outcome, and harness case `codex_marker_push_unproven_window` pins it |

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
10. **Additional repository requirement (not spec-derived)** — add the
   `changelog.d/1757.fix.resolved-codex-findings.md` fragment. No acceptance
   criterion or use case asks for it; it is required by `CLAUDE.md`
   ("CHANGELOG & Versioning"), which makes a `changelog.d/` release-note
   fragment mandatory for every feature, fix, and refactor pull request merged
   into `develop`. It therefore belongs to the implementation pull request only
   — this plan-only pull request is exempt under the same rule, so no fragment
   is added on this branch (see the Document Quality Gate's plan-stage-artifacts
   entry). Fragment content:

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
- Parser-risk completeness: Checked — dedicated addendum with 15 enumerated
  marker and window cases (14 carrying a `codex_marker_` test name, plus the
  superseded-malformed case whose test is a precedence name) and 20 mapped test
  names in total, each row mapped 1:1 to an Area 13 test name.
- Complex workflow decision-gate matrix: Checked — spec matrix is authoritative;
  implementation mirrors spec rows via `codex_classify_live_head_evidence()`.
  Newest-evidence selection runs **before** tier aggregation, per the spec's
  "Later non-dismissed terminal evidence for the same live head supersedes
  earlier current-head evidence before that precedence ordering is applied";
  the only timestamp-independent exceptions are indeterminate evidence, an
  applicable unresolved live-head conversation, and the two availability hard
  stops, which yield only to a *canonical* competitor — an applicable
  unresolved live-head conversation or a phase-2 winner in tiers 1–5 — and are
  otherwise restored by the hard-stop restoration rule). Environment-setup is
  retained separately and is never a hard stop. The normative Evaluation-order
  list is the single tie-breaker between the phase narrative and the
  pre-selection guard, and its worked examples agree with the guard for every
  listed batch. No contradictory next actions across plan layers.
- Shipped-contract inventory: Checked — every companion `exit 2` site was
  enumerated from source (Verification Log row `Exit-2 reason inventory`) and
  classified as retained, remapped, or added, with the pinned harness cases
  named for each; the only behavioural remap is the acknowledgement wait moving
  from exit `2` to exit `4`, which AC-9 requires.
- Correlation scoping: Checked — finding extraction, the cleared-findings rule,
  and the `CHANGES_REQUESTED` exception all consume the same per-review finding
  set keyed on `pull_request_review_id`; no section correlates against the
  head-wide inline-comment index.
- Reversal risk: Checked — the outcome-mapping step states the revert path
  (Implementation Order steps 3–4 + 7–8), the two residues that do not revert,
  and that partial reversal of individual reason codes is unsupported.
- Additional (non-spec) requirements declared: Checked — the only step that
  traces to no acceptance criterion is the `changelog.d/` fragment
  (Implementation Order step 10), declared there as a `CLAUDE.md` repository
  requirement scoped to the implementation pull request.
- Concurrent-event-source: Not applicable — single-threaded bash polling, no shared
  mutable async listeners.
- CHANGELOG literal format: Checked — step 10 uses `**Bold Title** (#1757):` bullet.
- Plan-stage artifacts only: Checked — plan + smoke runbook only on this branch.
- Cross-section naming: Checked — primary regression harness name
  `codex_resolved_visible_finding_waits_after_revision_push` matches the smoke
  runbook; shared lib path is `codex-github-evidence-lib.sh` everywhere; every
  named harness case in the Tests section appears once and only once, and the
  marker/window cases in the parser-risk mapping table use the `codex_marker_`
  prefix while the precedence cases use `codex_tied_` / `codex_triggerless_` /
  `codex_cap_` / `codex_exit3_` / `codex_older_` / `codex_hard_stop_` /
  `codex_body_finding_` / `codex_head_unavailable_` / `codex_reaction_only_` /
  `codex_adapter_`. Phase names (`Phase 1`
  absolute exceptions, `Phase 2` newest-evidence selection, `Phase 3`
  acknowledgement) are used consistently in the decision-function step, the
  pre-selection-guard paragraph, and the decision-gate mirror; the unrelated
  “`run_codex_github_review()` phase 1” wording always names that function, so
  the two numbering schemes never appear unqualified in the same sentence.

### Decision-gate matrix (plan mirror — normative source is spec)

The merged spec’s **Complex Workflow Decision-Gate Matrix** is the authoritative
row set. Implementation must not invent alternate outcomes. Mirror surfaces:
`codex-github-reviewer.sh` exit/`REASON=`, `run_codex_github_review()` `print_kv`,
Protocol 93, `codex-github.md`, PR summary.

| Gate input (abbrev.) | Allowed outcome | Required next action |
| --- | --- | --- |
| Applicable unresolved thread on live head | Actionable blocker → `needs_fixes`, unless a fail-closed item wins phase 2 | Fix loop (or human review on that escalation) |
| All findings cleared, no other unresolved thread | `waiting_on_reviewer` / `codex-github-review-pending` | Retrigger / await clean verdict |
| Terminal clean evidence for live head | Clean | Continue readiness |
| Newer non-dismissed live-head terminal evidence vs older same-head evidence | Newest timestamp decides before tier aggregation | Winning tier's action |
| Fail-closed escalation tiers | `escalate` + spec reason code | Human review |
| Cycle cap exhausted after evidence requires another cycle | Escalate | Human review |
| Canonical clean in final allowed cycle | Clean | Continue readiness |

**Deliberately deferred to the spec** (abbreviated mirror — these outcomes are
*not* omitted by oversight and must still be implemented):

- Availability hard stop (usage-limit / account-not-connected) → exit `3`
  unavailable, ranked below a *canonical* fail-closed escalation or actionable
  blocker and above every wait or clean outcome; a superseded competitor
  restores the hard stop (see the Decision-function Evaluation order above).
- Acknowledgement-only wait → exit `4`,
  `REASON=codex-github-reaction-without-review` (key scenario 10, AC-9), which
  takes precedence over `codex-github-review-pending`.
- Environment-setup supersession (BR-8): retained through the poll window,
  superseded by any strictly newer terminal or review evidence.

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

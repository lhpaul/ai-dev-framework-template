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
live-head evidence windows).

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
script is 2,508 lines and `pr-review-loop.sh` is 13,708, while Area 13 of
`test-pr-review-loop.sh` carries 418 `codex`-named `run_test` cases (all three
measured at `39327e36`; see Verification Log); this item extends the
classifier and loop adapter without changing rate limits or polling budgets.
CodeRabbit reuse is assessment-only (AC-16).

**Dependencies**: Spec PR #1758 merged to `develop` at merge commit
`7a97d571` (verified). No other batch item in the current invocation list
modifies the same Codex classification surfaces (see Cross-Cutting Operational
Assumption Check).

**If the dependency is absent from the implementation base**: before writing
code, confirm the merged spec is reachable from the base with
`git merge-base --is-ancestor 7a97d571 HEAD` **and** that
`docs/specs/developments/20260915075927_1757-resolved-codex-findings/1_1757-resolved-codex-findings_specs.md`
exists at that base. If either check fails — the branch was cut from a base
that predates the spec merge, or the implementation base is not `develop` —
**stop and report rather than proceeding**: every acceptance-criterion number,
reason code, and matrix row in this plan is quoted from that merged spec, so
implementing against a base without it would silently re-derive the contract.
Recovery is to rebase the implementation branch onto a base containing
`7a97d571`, not to copy the spec text forward. Record the outcome of both
checks in the implementation-start assumption table below.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision (worktree) | `git rev-parse --short HEAD`; `git merge-base HEAD origin/develop` | `39327e36` — this plan branch's revision at the last re-measurement of this table (2026-09-21). Every row below was re-run against this revision. The branch's `develop` merge base is `32605700`, which is what the Cross-Cutting Operational Assumption Check pins; the two are different surfaces. Line numbers in this table are **`pr-review-loop.sh` and `codex-github-reviewer.sh` as of `39327e36`** — re-measure at implementation start, because `pr-review-loop.sh` grows on `develop` (the cycle-cap call sites moved from `:10958` when this plan was first drafted to `:13555` here) |
| Spec merged | `gh pr view 1758 --json state,baseRefName,mergedAt` | `MERGED` into `develop` at `2026-09-16T23:05:22Z` |
| Phase-1 existing-findings gate | `sed -n '2167,2203p' scripts/development-workflow/pr-review-loop.sh` | Uses `check_unresolved_threads … provisional`; returns `needs_fixes` / `existing_findings` when count > 0 |
| Companion exit-1 wrapper floor | `grep -n 'unresolved_count=1' scripts/development-workflow/pr-review-loop.sh` | Two floors: the Codex adapter at `pr-review-loop.sh:2266` (the one this item removes) and a second at `:2427`, inside `run_claude_code_action_review()` (defined at `:2337`), which this item does **not** touch |
| Cleared-thread retrigger (partial) | `grep -n 'only cleared' scripts/development-workflow/codex-github-reviewer.sh` | Posts a fresh trigger at `codex-github-reviewer.sh:1536` (inline-review summary with only cleared findings) and `:1662` (existing trigger that produced only cleared findings) — neither covers the full spec matrix |
| Unrecognized safe-fail today | `grep -n 'unrecognized response format' scripts/development-workflow/codex-github-reviewer.sh`; `grep -c 'unrecognized response format' scripts/development-workflow/tests/test-pr-review-loop.sh` | Three companion sites emit `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)` — `:1560`, `:1992`, `:2322` — and the harness mentions that string on 74 lines, so terminal unrecognized evidence exits `1` today rather than escalating; those expectations are the ones the matrix spot-check step rewrites |
| Harness surface | `grep -c '^run_test.*codex' scripts/development-workflow/tests/test-pr-review-loop.sh` | 418 `codex`-named tests (Area 13) |
| CodeRabbit thread audit (AC-16 surface) | `sed -n '5556,5645p' scripts/development-workflow/pr-review-loop.sh` | The comparable integration is `coderabbit_thread_gate_clean()` at `pr-review-loop.sh:5556`, whose strict audit call is `check_unresolved_threads "$pr_number" "$repo" strict "$graphql_bot_login"` at `:5580` — the comment at `:5578–5579` states it "decides RESULT=clean for CodeRabbit and must never be relaxed by a reply-without-resolve". It fails closed on an incomplete audit (page cap → `unresolved_thread_check_incomplete` at `:5584–5596`; GraphQL failure after retries → `review_thread_audit_failed` at `:5599–5617`) and returns `needs_fixes` / `coderabbit_unresolved_review_threads` when the count is non-zero (`:5637–5640`). **It performs no revision correlation**: the audit filters on `isResolved` / `isOutdated` / `✅ Addressed` only, with no `commit_id == headRefOid` applicability test. The nearest head-scoped mechanism, `coderabbit_success_status_count "$repo" "$head_sha"` (`:5799`, used at `:6804` and `:6920`), counts commit statuses for the head rather than correlating conversations to a revision. The earlier revision of this row cited `:2173` / `:2259`, which are the **Codex** adapter's own calls, not CodeRabbit's |
| Integration doc | `docs/workflow/development-workflow/integrations/codex-github.md` | Documents pre-trigger scan and template approval; lacks new escalation/wait reason codes |
| Evidence-counts symbol | `grep -n 'codex_review_thread_evidence_counts' scripts/development-workflow/codex-github-reviewer.sh` | Defined at `codex-github-reviewer.sh:273`; sole caller at `:1497`. Today's only definition — the plan **moves** it to `codex-github-evidence-lib.sh` under the same name and repoints `:1497`, rather than extending it in place, so both scripts share one implementation |
| Cycle-cap enforcement block | `grep -n 'reviewer_loop_cap_exceeded "' scripts/development-workflow/pr-review-loop.sh` | Two call sites, the `#1502` dual cap: per-run at `pr-review-loop.sh:13555` and lifetime at `:13559`; the predicate is defined at `:11264` and the escalation log at `:13556` carries the reason string `max_cycles_exceeded` |
| Environment-setup outcome | `sed -n '1372,1382p' scripts/development-workflow/codex-github-reviewer.sh` | `codex_return_environment_error` emits `REASON=codex-github-environment-missing` and `exit 2`; retained unchanged by this item (see the exit-`2` retained-contract table) |
| Exit-2 reason inventory | `grep -cE '\bexit 2\b' scripts/development-workflow/codex-github-reviewer.sh` → **53**; `grep -nE '\bexit 2\b' … \| grep -v '^[0-9]*: *#' \| wc -l` → **52**; plus the nearest preceding `REASON=` per hit and `grep -n 'run_test "codex_[a-z0-9_]*" "2"' scripts/development-workflow/tests/test-pr-review-loop.sh` | The raw count is **53** and the executable count is **52**: line `:1681` is a comment (`# Guard with 'if !' to emit TIMED_OUT (exit 2) on failure …`), not an exit. Every count below is of the 52 executable sites. Only five sites emit a reason, covering four distinct reasons: `codex-github-environment-missing` (`:1381`), `codex-github-reaction-without-review` (`:1402`), `codex-github-head-changed` (`:1411`), and `codex-github-head-unavailable` (`:1420`, `:1428`). Of the remaining 47, 18 are usage/argument-validation/`gh auth`/HEAD-resolution exits (`:94`–`:214`) and 29 are reason-less `VERDICT: TIMED_OUT …` fetch/poll/trigger failures. 17 harness cases assert a codex exit code of `2`; `codex_pre_trigger_head_changed_*` (`tests:5348`, `:5351`) and `codex_head_changed_*` (`tests:10335`, `:10336`) pin `codex-github-head-changed`, and `codex_reaction_only_exit_unavailable` (`tests:5435`) pins exit `2` for the acknowledgement wait. Exit `4` exists on exactly one shipped path (`:2508`, `REASON=codex-github-review-pending`) |
| Exit-2 reason default | `sed -n '2320,2333p' scripts/development-workflow/pr-review-loop.sh` | `codex_reason="$(kv_value_default REASON "$script_output" timeout)"` at `:2322`; `print_kv RESULT escalate` (`:2323`) and `return 2` (`:2332`) are unconditional — an out-of-set `REASON` loses the reason string, not the escalation |
| Inline-comment review join | `gh api repos/{owner}/{repo}/pulls/1768/comments?per_page=1 --jq '.[0] \| {id, pull_request_review_id, commit_id}'` and the matching GraphQL `reviewThreads → comments(first:1) → pullRequestReview.databaseId` | REST returns `id=4056981858`, `pull_request_review_id=5260609621`, `commit_id=37d5bd35…` for a `chatgpt-codex-connector[bot]` comment; GraphQL returns `databaseId=4056981858` with `pullRequestReview.databaseId=5260609621` for the same thread. Both review-scoping joins exist and agree |
| Exit-`3` reason hardcode | `sed -n '2292,2302p' scripts/development-workflow/pr-review-loop.sh` | `print_kv REASON codex-github-usage-limit` is unconditional at `:2294`, discarding the companion's `REASON=`; the companion's `codex_return_account_not_connected` emits `REASON=codex-github-account-not-connected` then `exit 3` (`codex-github-reviewer.sh:1384–1393`), so that outcome is reported today as a usage limit |
| Commit-token resolution semantics | `git rev-parse --disambiguate=<prefix>`; `git rev-parse --verify "<token>^{commit}"`; `gh api repos/{owner}/{repo}/commits/<token>` | Unique token `490bde2` → exit `0`, full SHA. Ambiguous prefix `0003` (found via `git rev-list --all --objects \| cut -c1-4 \| sort \| uniq -d`) → exit `128`, `error: short object ID 0003 is ambiguous`. Unknown `deadbee` → exit `128`, `fatal: Needed a single revision`. `--disambiguate=490b` → one line (the full SHA); a 2-character prefix returns zero lines with no error. GitHub REST: `commits/490bde2` and `commits/490b` both return HTTP `200` with a full `.sha` — no ambiguity signal — while `commits/dead` returns HTTP `422` `No commit found for SHA: dead` |
| Head-transition source investigation | `gh api repos/{owner}/{repo}/issues/1768/timeline --paginate --jq '.[].event' \| sort \| uniq -c`; `gh api repos/{owner}/{repo}/events --paginate --jq '.[] \| select(.type=="PushEvent")'` | The pull-request timeline for a four-head pull request contains **no** push- or head-transition event of any kind: only `commented`, `committed`, `labeled`, `unlabeled`, `subscribed`, `mentioned`, `reviewed`, `cross-referenced`. `committed` events carry `sha` + `committer.date` with `created_at: null`. Ordinary (non-force) pushes surface no pull-request-scoped event, so `head_ref_force_pushed` is the only timeline transition event and this repository has none to sample. The repository `events` feed *does* carry `PushEvent` with a true push instant per branch ref — `490bde2c` at `2026-09-21T00:05:21Z` versus its `committer.date` of `00:05:14Z`, empirically confirming the 7-second commit-date-vs-push gap — but the feed is repository-wide and bounded: `--paginate` returned ~286 events reaching back only to `2026-09-16`, entries for one ref came back out of chronological order, and a fork head ref would not appear at all. **Historical — no longer consumed by any step.** Recorded because it is the evidence that a transition instant cannot be sourced at all; the **Live-head evidence window** section no longer needs one, so no substitute is required |
| Sync-manifest scope for a new shared library | `sed -n '105,132p' sync-manifest.yaml`; `grep -n 'product_repo' scripts/development-workflow/tests/test-sync-template-mode-scopes.sh` | `scripts/development-workflow/` is declared `glob: "**/*"`, `mode_scope: hub_only` (`sync-manifest.yaml:105–108`), and each product-repo runtime file overrides it with its **own explicit entry**: `workflow-config-resolver.py` (`:109`), `resolve-reviewer-availability.sh` (`:112`), `validate-workflow-config.sh` (`:115`), `workflow-lib.sh` (`:118–120`, note "shared shell helpers required by product-repo runtime scripts"), `pr-review-loop.sh` (`:121–123`), `pr-ci-loop.sh` (`:124`), `changelog-fragments.sh` (`:127`), `post-merge-cleanup.sh` (`:130`). So a **new** sibling file is `hub_only` by default even though its caller is injected. `workflow-lib.sh` is the precedent to mirror. Selection is testable through `select-sync-manifest-entries.py`, and `test-sync-template-mode-scopes.sh` already asserts against the **real** manifest (`:309–338`) as well as fixtures (`:180`) |
| Trigger comment names the head | `sed -n '1685p;2019p' scripts/development-workflow/codex-github-reviewer.sh` | `codex-github-reviewer.sh:1685` posts `… (review triggered by workflow runner, commit: $CURRENT_SHA)` and `:2019` posts `… (sha: $CURRENT_SHA)` on retrigger, both after `headRefOid` is resolved. Every trigger therefore names its SHA, which is what lets the boundary `B` be computed by string comparison against `headRefOid` with no head enumeration |
| Blocking-marker vocabulary (shipped) | `grep -n 'CODEX_BLOCKING_PATTERN\|codex_response_is_blocking()' scripts/development-workflow/codex-github-reviewer.sh` | `CODEX_BLOCKING_PATTERN` is defined at `codex-github-reviewer.sh:532` (`changes requested`, `blocking issues:`, `blocking finding`, `blocking:`, `must fix`, `action required`, `required:`, `❌`) and extended at `:578` with `CODEX_MERGE_REFUSAL_PATTERN` (`:577`); `codex_response_is_blocking()` at `:698` is the classifier. Body findings reuse this surface, so the plan adds no marker vocabulary — which is what the spec requires |
| Force-push event payload | `gh api repos/kubernetes/kubernetes/issues/142190/timeline --jq '.[] \| select(.event=="head_ref_force_pushed")'` (this repository has no force-pushes to sample; kubernetes/kubernetes used as a live source) | `head_ref_force_pushed` carries `created_at` — a true push instant — and a populated `commit_id` naming the **new** head: on PR 142190 the newest event (`2026-09-17T18:35:21Z`, `commit_id=1a39d080…`) matches that PR's current head, and its commit's own `committer.date` is `18:35:18Z`, three seconds earlier. Populated in 8 of 8 sampled events across 5 pull requests. `head_ref_deleted` also carries `created_at` (with `commit_id: null`); `head_ref_restored` was not sampled. The occupancy guard needs only existence and `created_at`, so it does not depend on `commit_id` being present |
| Reply-after-push relaxation (shipped) | `sed -n '340p' scripts/development-workflow/codex-github-reviewer.sh`; `sed -n '7336,7341p;7354,7355p;7377,7379p' scripts/development-workflow/pr-review-loop.sh` | The companion folds the relaxation into its `cleared` predicate at `codex-github-reviewer.sh:340` (`isResolved` **or** `✅ Addressed` **or** last comment non-bot with `createdAt` later than `headRef.target.committedDate`), with no mode switch. The loop's `check_unresolved_threads` has the switch: `provisional` → `strict` fallback at `:7354-7355`, provisional-only field fetch at `:7377-7379`, and the contract at `:7336-7341` — provisional "exists ONLY to unblock phase-1 gates that decide whether to re-trigger a review; it must never be used by a gate that decides RESULT=clean" |
| Codex marker token width | `gh api repos/{owner}/{repo}/pulls/1768/reviews --paginate --jq '.[] \| select(.user.login\|test("codex")) \| .body'` | The two Codex reviews on this pull request carry `**Reviewed commit:** \`37d5bd35da\`` and `\`76dc7213b8\`` — **10 hex characters**. Abbreviated markers are the production norm, so a rule that fails abbreviations closed would make the clean path unreachable |
| Repository object count | `git count-objects -v` | 40,637 loose + 24,279 packed ≈ 6.5×10⁴ objects; used for the R2 collision arithmetic |
| Cycle-cap defaults | `grep -n 'reviewer_loop_resolve_max_cycles()\|reviewer_loop_resolve_max_total_cycles()' scripts/development-workflow/pr-review-loop.sh` then read each body | `reviewer_loop_resolve_max_cycles` is defined at `:11201` and defaults to **10** (`:11211` unset path, `:11216` invalid-value path with its WARN); `reviewer_loop_resolve_max_total_cycles` is defined at `:11232` and defaults to **25** (`:11242`, `:11247`). Note: the comment at `:1091` says `expensive_gate_resolve_max_deferrals` “mirrors `reviewer_loop_resolve_max_cycles`: default 3”, which no longer matches that resolver — do not encode `3` |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch | `develop` | Parent handoff + `gh pr view 1758` | 2026-09-17, `develop` ancestor SHA `32605700` (not the plan branch revision — `39327e36` at the last Verification Log re-measurement — which pins a different surface) | Item #1757 only | `Verified` |
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
| Live-head evidence window bound | REST PR object + PR issue comments + PR issue timeline | Three reads: PR `created_at`; `GET repos/{owner}/{repo}/issues/{pr}/comments` (paginated) for review trigger `created_at`, body SHA, and comment `id`; and `GET repos/{owner}/{repo}/issues/{pr}/timeline` (paginated) for `head_ref_force_pushed` (and `head_ref_deleted` / `head_ref_restored`) `created_at`, used by the occupancy guard for existence only. The boundary applies to **well-formed live-head markers as well as** unmarked or unusable-marker comments; only a marker naming another SHA bypasses it. No repository-scoped signal — see **Live-head evidence window** |

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
4. **Finding extraction — two independent sources inside review `R`.** A
   finding belongs to the terminal verdict that reported it, so extraction is
   per review, never per head. Review `R` (REST review `id`) can report findings
   in **two** places, and both are always evaluated — neither suppresses the
   other:

   - **(a) Inline findings of `R`**: the step-2 rows whose
     `pull_request_review_id == R.id` **and** `commit_id == headRefOid`. Each
     such row is one finding with stable thread id = comment `id`. An inline
     comment on the live head belonging to a *different* review — an earlier
     Codex review, or another bot — is not a finding of `R` and **must never
     supply correlation for `R`**; correlating against the head-wide comment
     index would turn a review-body-only finding into a false `needs_fixes` or a
     false cleared-findings wait.
   - **(b) Body findings of `R`**: blocking assertions in `R`'s **own body**,
     detected with the shipped classifier `codex_response_is_blocking()`
     (`codex-github-reviewer.sh:698`) over `CODEX_BLOCKING_PATTERN`
     (`:532`, extended at `:578` with `CODEX_MERGE_REFUSAL_PATTERN` from
     `:577`) — applied to the body exactly as shipped, with no added
     preprocessing. This is the vocabulary the spec itself points at ("the
     blocking pattern maintained by the Codex reviewer helper and described in
     its comments"); this plan introduces **no** marker vocabulary of its own.

   **Source (b) is evaluated whether or not source (a) is empty.** This is the
   load-bearing correction: scoping findings to inline rows alone would make a
   review's body invisible as soon as that review had one inline comment, so a
   verdict carrying one correlated inline finding *plus* an unthreaded body
   finding would read as fully correlated and return `needs_fixes`.

   **Precedence — any body finding makes `R` correlation-missing.** A body
   finding carries no review-thread identity by construction, so it can never be
   matched to a conversation. Spec Business Rule 5 (spec line 105) is explicit:
   "If a current terminal verdict contains both a finding correlated to an
   applicable unresolved conversation and a finding that is uncorrelated or has
   no identifiable matching thread, the incomplete finding evidence takes
   precedence. The loop must escalate rather than selectively return
   `needs_fixes` for the correlated finding." Spec matrix row 287 gives this
   exact shape as its example — "A submitted verdict has one unresolved-thread
   finding and one review-level finding with no thread identity" — and requires
   `escalate` with `codex_finding_thread_correlation_missing`, adding "do not
   claim clean or return `needs_fixes` for only other correlated findings".
   Therefore: if `codex_response_is_blocking()` is true for `R`'s body, `R`
   escalates `codex_finding_thread_correlation_missing` **regardless of how many
   of its inline findings correlate**, including the body-only case
   (`codex_cleared_thread_top_level_blocker`) and the mixed case. Only when
   `R`'s body carries no blocking assertion are `R`'s findings exactly its
   inline findings, and only then can correlated findings yield `needs_fixes`.

   **Root-comment verdicts are unchanged**: a terminal verdict delivered as a
   root pull-request comment owns no review at all, so any blocking finding it
   carries has no review-thread identifier and is correlation-missing by the
   same rule (spec: "A review-level finding or comment without a review-thread
   identifier is incomplete evidence, not an actionable blocker").

   **Cleared-findings interaction**: the cleared-findings rule consumes this
   same per-review finding set — "every matching conversation is resolved" is
   evaluated over `R`'s own inline findings, never over unrelated live-head
   threads — and it is reachable only when `R` has no body finding, because a
   body finding has no matching conversation to resolve and escalates first.

   **Exception (orthogonal) — canonical wording, restated verbatim in the
   "CHANGES_REQUESTED + correlation-missing" step below:** GitHub
   `state == CHANGES_REQUESTED` on a current-head submitted review is an
   actionable blocker by structured state when the review carries **no finding
   requiring correlation at all** — neither an inline finding of its own nor a
   blocking assertion in its body. The structured state alone is the blocker,
   and that absence is not correlation-missing. If the review carries **any**
   finding that lacks a stable thread identifier or has no identifiable matching
   conversation — including a body finding —
   `codex_finding_thread_correlation_missing` escalation takes precedence over
   the structured blocker, including when *every* such finding lacks thread
   identity, not only when one lacks it alongside a correlated one (spec: "when
   such a review also carries a finding with no stable review-thread identifier
   or no identifiable matching conversation, the correlation-missing escalation
   takes precedence").

- [ ] **Bounded evidence query** (AC-1–4, 7–9; also the surface the AC-16
  assessment judges): **Move**
  `codex_review_thread_evidence_counts()` out of the companion
  (`codex-github-reviewer.sh:273`, confirmed in the Verification Log) **into**
  `codex-github-evidence-lib.sh`, keeping the name so the move is traceable.
  This is a move, not a copy — the Risks table's mitigation is a single shared
  lib sourced by both and "never a second implementation", so no classification
  logic may remain in the companion. Update its sole caller
  (`codex-github-reviewer.sh:1497`) to call the sourced function, and have
  `run_codex_github_review()` phase 1 in `pr-review-loop.sh` call **this same
  function**; no second function is introduced.

  **Behavioural extension.** Extend the moved function to return structured
  status on GraphQL failure (`evidence_unavailable_codex_thread_state`) after
  one retry, and to classify each non-outdated Codex thread as
  `applicable_unresolved`, `applicable_resolved`, `cleared`, `outdated`, or
  `dismissed_review_attached` using head SHA + review `commit_id` equality (not
  merely `isOutdated`). The “reply after head push” relaxation remains **only**
  for re-trigger eligibility, never for declaring clean (preserve the #1508
  contract) — which is what the explicit `mode` parameter below enforces, rather
  than leaving it to each caller's discipline.

  **Executable interface (required — the two callers do not share a variable
  namespace).** Today the function reads five companion globals and nothing
  else: `OWNER`, `REPO`, `PR_NUMBER`, `BOT_LOGIN`, and `BOT_LOGIN_PLAIN`
  (`codex-github-reviewer.sh:273–368`; `BOT_LOGIN` is set at `:128`,
  `BOT_LOGIN_PLAIN` at `:229`). `run_codex_github_review()` has none of them: it
  works with locals `pr_number`, `branch_name`, `platform`, `bot_login`,
  `graphql_bot_login`, and `repo`, where `repo` is the `owner/name` slug from
  `repo_slug()` (`workflow-lib.sh:197`). Sourcing the function as-is would read
  unset names and abort under `set -u`. Convert it to explicit parameters with
  no global reads:

  ```text
  codex_review_thread_evidence_counts <owner> <repo_name> <pr_number> \
      <graphql_bot_login> <mode> [max_pages]
    mode   : strict | provisional; any other value falls back to strict,
             matching check_unresolved_threads (`pr-review-loop.sh:7354-7355`)
    stdout : "<strict_unresolved>\t<cleared>\t<provisional_relaxed>"
             (tab-separated; three fields, see the mode contract below)
    return : 0 success | 3 scan/pagination failure (unchanged codes)
  ```

  **Mode contract — why two counts are not enough.** The shipped function bakes
  the reply-after-push relaxation into its `cleared` predicate
  (`codex-github-reviewer.sh:340`):
  `cleared: ((.isResolved // false) or ($first_body | test("✅ Addressed")) or
  (($head_date != "") and ($last_author != $bot) and ($last_created >
  $head_date)))`, where `$head_date` is `headRef.target.committedDate`. Its
  `count` is therefore *unresolved after relaxation*. The loop's strict phase-1
  gate must not inherit that: a thread whose last comment is a human reply after
  the push would be counted as cleared and could contribute to a false clean.
  The loop's own `check_unresolved_threads` already draws this line and states
  the contract at `pr-review-loop.sh:7336-7341` — provisional "exists ONLY to
  unblock phase-1 gates that decide whether to re-trigger a review; it must
  never be used by a gate that decides RESULT=clean" — so the shared helper
  adopts the same vocabulary rather than inventing one.

  Field definitions, over non-outdated threads whose first comment is
  Codex-authored:

  | Field | Meaning |
  | --- | --- |
  | `strict_unresolved` | Not `isResolved` and no `✅ Addressed` marker. **No relaxation applied.** |
  | `cleared` | `isResolved` or `✅ Addressed` — the strict notion of cleared |
  | `provisional_relaxed` | Of the `strict_unresolved` threads, those whose last comment is non-bot with `createdAt` later than the head commit's `committedDate`. **Always `0` in strict mode**, where the query does not fetch `lastComment` or the head date (mirroring `pr-review-loop.sh:7377-7379`, which fetches `lastComment` and the head `committedDate` only in provisional mode) |

  Caller mapping, both preserving today's behaviour exactly:

  - **Companion re-trigger eligibility** (`codex-github-reviewer.sh:1497`, in
    `codex_classify_existing_current_head_evidence`): call with
    `mode=provisional` and use `strict_unresolved - provisional_relaxed` as the
    unresolved count and `cleared + provisional_relaxed` as the cleared count —
    algebraically identical to today's two numbers, so the #1508 relaxation is
    preserved on the path that depends on it. **Update the call site's
    `IFS=$'\t' read -r unresolved_thread_count cleared_thread_count` to read
    three fields**; a two-variable `read` would swallow the third into the
    second.
  - **Loop phase 1** (`run_codex_github_review()` in `pr-review-loop.sh`): call
    with `mode=strict` and use `strict_unresolved` alone. Never read
    `provisional_relaxed` there — it is `0` in strict mode anyway, so a caller
    that forgets the mode fails toward *more* blockers, never fewer.

  Tests, one per caller plus the mode guard:
  `codex_evidence_lib_provisional_preserves_relaxation` (a thread with a
  post-push non-bot reply: provisional mode yields today's counts and the
  companion still treats it as eligible for re-trigger),
  `codex_evidence_lib_strict_counts_replied_thread_as_unresolved` (the same
  fixture in strict mode: the thread counts as unresolved, so loop phase 1
  cannot clear it), and `codex_evidence_lib_unknown_mode_falls_back_to_strict`.

  - Parameter 4 is the **GraphQL** login form (no `[bot]` suffix), matching
    today's `BOT_LOGIN_PLAIN`; the REST form is not needed by this function.
  - `max_pages` defaults to today's `20` when omitted.
  - **Companion call site** (`:1497`): pass `"$OWNER" "$REPO" "$PR_NUMBER"
    "$BOT_LOGIN_PLAIN"` — a pure argument move, no behaviour change.
  - **Loop call site**: split the slug once — `owner="${repo%%/*}"`,
    `name="${repo##*/}"` — and pass `"$owner" "$name" "$pr_number"
    "$graphql_bot_login"`. The loop already keeps the stripped form in
    `graphql_bot_login` for `check_unresolved_threads`, so no new derivation is
    introduced.
  - Every other helper moved into `codex-github-evidence-lib.sh` follows the
    same rule: **parameters in, values on stdout, no global reads, no
    `exit`** — the library must be safe to source under `set -eu` from both
    callers.
  - Tests: one Area 13 case per caller —
    `codex_evidence_lib_companion_caller_contract` (companion globals →
    parameters, same effective counts as today) and
    `codex_evidence_lib_loop_caller_contract` (loop slug split → same output),
    plus `codex_evidence_lib_no_unset_globals` running the library under
    `set -u` with none of the companion globals defined, and the three
    mode-contract cases named above.

- [ ] **Terminal evidence collector** (AC-3–4, 10–13): Normalize submitted
  reviews and root PR comments into a sorted list of evidence items for the
  live head (timestamp, source, review state, marker parse result, clean vs
  blocking vs unrecognized vs availability). Implement marker well-formedness
  (exactly one hex token, unambiguous resolution, prefix-at-offset-zero rule,
  interior-substring / superstring rejection) and freshness boundary (after
  latest live-head trigger; same-second comment ID ordering).

  **Abbreviated-token resolution contract** (the spec requires distinguishing
  unique, zero-match, and ambiguous tokens, so the mechanism and its failure
  semantics are named here rather than left to the implementer).

  **Scope first — only half of the readiness test touches the object
  database.** The spec's test is that the marker token is an "unambiguous prefix
  of the live head" (spec line 107), and those are two independent checks:

  - the **prefix** half is a pure string comparison between the token and the
    known 40-character `headRefOid`, including the offset-zero rule and the
    interior-substring / superstring rejections. It needs **no** object
    database, no network call, and no resolution of any kind;
  - only the **ambiguity** half asks whether some *other* commit shares the
    token as a prefix, and that is the only part that consults the object
    database.

  Abbreviated tokens are the production norm, not an edge case: the two Codex
  reviews already on this pull request carry `Reviewed commit: 37d5bd35da` and
  `76dc7213b8` — 10 hex characters (Verification Log row `Codex marker token
  width`). Treating every abbreviation as unresolvable would therefore make the
  **clean** path unreachable for ordinary Codex traffic, which is a strictly
  worse failure than any ambiguity it would avoid.

  Resolution runs in the workflow checkout (`cd_workflow_repo_root`), in this
  order:

  1. **`git rev-parse --disambiguate=<token>`** is the authoritative
     ambiguity test, filtered to commit objects via `git cat-file
     --batch-check`. Observed in this repository (Verification Log row
     `Commit-token resolution semantics`): 0 lines → no local match; 1 line →
     unique; ≥2 lines → ambiguous. Tokens shorter than 4 hex characters cannot
     be tested by `--disambiguate` at all (it returns 0 lines with no error),
     so they can never be proven unique and take the same unprovable-abbreviation
     path below.
  2. **`git rev-parse --verify "<token>^{commit}"`** is the value lookup for the
     unique case: exit `0` with the full SHA on stdout. Its failure modes
     collapse two different conditions — exit `128` with
     `error: short object ID … is ambiguous` for ambiguity and exit `128` with
     `fatal: Needed a single revision` for no match — so it must **not** be the
     ambiguity test; step 1 owns that decision.
  3. **`gh api repos/{owner}/{repo}/commits/{token}`** is used **only for a
     full 40-character token** — never to resolve an abbreviation. A 40-hex
     token cannot be ambiguous, so HTTP `200` answers the only open question
     (existence, and the `.sha` it names) and HTTP `422`
     (`No commit found for SHA: …`) means no such commit. For an abbreviated
     token this endpoint is **not** admissible evidence: observed rather than
     assumed, GitHub resolves the 4-character prefix `490b` to a single SHA with
     HTTP `200` and no ambiguity signal, so a `200` would assert a uniqueness it
     never checked. Spec line 107 makes uniqueness part of well-formedness —
     "A marker is well-formed only when all three hold: it contains exactly one
     hexadecimal commit token, **that token resolves unambiguously to a single
     commit**, and that token functions as a standalone commit reference" — so
     an unproven abbreviation must not authorize readiness.

  **Abbreviated token with no local match — two different outcomes, never one.**
  A local miss has two possible causes and the spec classifies them
  differently, so they must be separated rather than collapsed. Run one
  `git fetch --no-tags --quiet origin` for the pull request's head ref and
  retry step 1; if the local commit count is still `0`, ask the remote the one
  question it *can* answer authoritatively — existence:

  - **`gh api repos/{owner}/{repo}/commits/{token}` → HTTP `422`
    (`No commit found for SHA: …`)**: a **proven zero-match**. GitHub's object
    store is complete for the repository, so a `422` establishes that no commit
    in it starts with that token. Spec line 286 (decision-gate matrix) lists
    "resolves to zero commits" among the syntactically unusable markers that
    `escalate` with `codex_current_verdict_malformed_revision_marker`, and its
    example row names "one valid-looking 40-character token that resolves to no
    commit at all". Classify **malformed-marker**, not evidence-unavailable.
  - **HTTP `200`**: the token *does* match at least one commit, but GitHub
    returns a single `.sha` with no ambiguity signal (`490b` → `200`, observed;
    Verification Log). Existence is settled, **uniqueness is not**, and nothing
    available can settle it once the local store lacks the objects. Classify
    **`evidence_unavailable_codex_thread_state`**.
  - **REST unreachable, rate-limited, or `5xx` after one retry**: neither
    existence nor uniqueness is established →
    **`evidence_unavailable_codex_thread_state`**.

  Do not guess from a length threshold — no abbreviation length guarantees
  uniqueness — and never let an unproven token reach clean, wait, or
  prior-revision evidence.

  Resolution outcomes, by observation:

  | Observation | Class | Outcome |
  | --- | --- | --- |
  | Local `--disambiguate` → exactly 1 commit | Unique | Resolved; continue marker checks |
  | Local `--disambiguate` → ≥2 commits | Ambiguous (proven defect) | `codex_current_verdict_malformed_revision_marker` |
  | Full 40-hex token, local miss, REST `422` | Zero-match (proven defect) | `codex_current_verdict_malformed_revision_marker` |
  | Full 40-hex token, local miss, REST `200` | Unique by construction | Resolved; continue marker checks |
  | Abbreviated token, local miss after fetch + retry, REST `422` | Zero-match (proven defect) | `codex_current_verdict_malformed_revision_marker` |
  | Abbreviated token, local miss after fetch + retry, REST `200` | Exists, uniqueness **unprovable** | `evidence_unavailable_codex_thread_state` |
  | REST unreachable / rate-limited / `5xx` after one retry | Nothing established | `evidence_unavailable_codex_thread_state` |
  | `git` fails for any other reason (not exit `128` with one of the two messages above) | Evidence failure | `evidence_unavailable_codex_thread_state` after one retry |

  The split is the spec's, not a preference: the malformed tier holds **proven**
  marker defects — spec line 286 enumerates them as "empty, non-hex, contains
  multiple commit tokens, ambiguous between candidates, **resolves to zero
  commits**, or matches the live head only at an interior substring or as a
  superstring" — while a token whose uniqueness cannot be established is
  indeterminate evidence and takes the evidence-unavailable escalation. Both are
  fail-closed; neither can reach clean, wait, or `needs_fixes`. Tests:
  `codex_marker_remote_zero_match_malformed` and
  `codex_marker_unprovable_abbreviation`, one per branch.

  **What "unambiguous" is scoped to.** `git rev-parse --disambiguate` is git's
  own uniqueness mechanism, and its guarantee is uniqueness **over the local
  object set** — here, the object set after the head-ref fetch this contract
  already performs. That is the same scope git itself uses when it auto-sizes
  abbreviations through `core.abbrev`: git sizes a short SHA so that it is
  unique among the objects it has, not among objects it has never seen. No
  stronger guarantee exists in git or in the GitHub REST API — the API resolves
  a prefix to one commit and reports no candidate set at all (`490b` → `200`,
  observed) — so "unambiguous" in this plan means, and can only mean, unique
  over the fetched object set. Recorded as an accepted residual below with its
  collision arithmetic.

- [ ] **Live-head evidence window** (AC-13, AC-14): decide which Codex root
  comments count as evidence for the **live head**. The decisive point is
  *which comments the window is for*, and spec line 109 says it in its own
  opening clause:

  > "Every Codex root comment belongs to exactly one head's evidence window,
  > because such a comment **is not inherently revision-bound**."

  **Two questions, both necessary: the marker says *which head*, the window says
  *which occupancy*.** A well-formed marker is revision-bound, so it identifies
  the head a comment reviewed — but a SHA can occupy the head position more than
  once (a revert, or a force-push back), and spec line 109's opening is
  universal: *every* root comment belongs to exactly one head's evidence window.
  Marker identity alone would therefore let a clean comment authored during the
  **first** occupancy of SHA `A` authorize readiness during a **second**
  occupancy of `A`, with no review in between. The window test is applied to
  well-formed live-head markers as an **additional necessary condition**:

  | Marker state | Window test | Outcome |
  | --- | --- | --- |
  | Well-formed, names the live head, comment passes the boundary test | Passes | Live-head evidence |
  | Well-formed, names the live head, comment fails the boundary test | Fails | **Stale-head evidence, ignored** — this is the SHA-reuse case |
  | Well-formed, names a different SHA | Not applied | Prior-revision evidence → stale path, `codex-github-review-pending` — spec line 107: "valid prior-revision evidence and follows the stale path … **never the malformed-marker path**" |
  | Syntactically unusable, **or** no `Reviewed commit` field | See the boundary rule below | Triggered head: `B` decides. Trigger-less head: escalate |

  The marker still does real work — it is what routes row 3 away from the window
  entirely, and row 4 into the trigger-less escalation — but it is never
  sufficient on its own for live-head evidence.

  **Computing the boundary `B`.** Read the pull request object for `created_at`
  and `GET repos/{owner}/{repo}/issues/{pr}/comments` (paginated) for the review
  trigger comments. Every trigger names its SHA —
  `… (review triggered by workflow runner, commit: $CURRENT_SHA)` at
  `codex-github-reviewer.sh:1685` and `… (sha: $CURRENT_SHA)` on retrigger at
  `:2019` (Verification Log row `Trigger comment names the head`) — so a trigger
  is classified as live-head or not by string comparison against `headRefOid`,
  with no head enumeration.

  - **Live head has at least one trigger** — the real-world path, because the
    loop posts a trigger for every head it reviews. `B` is the `created_at` of
    the **latest** trigger naming the live head. This is sound without any
    transition instant: the companion resolves `headRefOid` and *then* posts the
    trigger, so `B` provably post-dates the moment that occupancy began.
    - **Occupancy guard, two inputs.** Raise `B` when either shows the head
      moved after that trigger:
      1. **Terminal evidence naming a different SHA that is newer than the
         trigger** — the head demonstrably moved away after it, so raise `B` to
         that evidence's timestamp. Uses only evidence the classifier already
         reads.
      2. **A `head_ref_force_pushed` event newer than the trigger**
         (`GET repos/{owner}/{repo}/issues/{pr}/timeline`, paginated) — raise
         `B` to the event's `created_at`. **SHA reuse requires a force-push**:
         adding commits always yields a new SHA, so returning the head to a
         previously current SHA can only happen by force-updating the ref, and
         that leaves this event. `head_ref_deleted` and `head_ref_restored`
         count the same way — see the deliberate inclusion note below.

      **Do not filter these events by `commit_id`.** In the A → B → A case the
      final force-push installs `A`, so its `commit_id` equals the live head; a
      guard that skipped events naming the live head would miss exactly the case
      it exists to catch. Any force-push newer than the trigger raises `B`.

      **This is not the anchor rejected in cycle 4.** That rejection was about
      using this event to time *ordinary* pushes — which emit no event at all,
      so its absence proved nothing about them. Here the event is used only for
      what it asserts on its own terms: a force-update of the head ref happened
      at this instant. Its absence reliably means no force-push occurred, and
      SHA reuse cannot occur without one.

      The guard is conservative in the safe direction: a late-arriving
      prior-head review, or a force-push that changed nothing relevant, can
      raise `B` past genuine current evidence, which yields a wait, never a
      clean. A timeline read that fails or truncates after one retry is the
      **boundary unreadable** escalation below, not a silent skip. If such an
      event is present but carries no usable `created_at`, treat it the same
      way — escalate rather than ignoring the event.

      **Include `head_ref_deleted` and `head_ref_restored`, deliberately.** A
      delete-and-restore pair can also return a ref to a SHA it held earlier, so
      the same reasoning applies. `head_ref_deleted` is verified to carry
      `created_at` (Verification Log row `Force-push event payload`);
      `head_ref_restored` could **not** be sampled — roughly 80 pull requests
      across four repositories produced none — so its payload is unverified,
      which is exactly why the missing-`created_at` case above escalates instead
      of being silently skipped.
  - **Live head is trigger-less** — `B` = `max(created_at of the latest trigger
    naming any other SHA, PR created_at)`. A well-formed live-head marker
    authored at or after that trigger-derived `B` — or strictly after it, when
    the occupancy guard raised `B` to an event timestamp — is current-occupancy
    evidence; one before it is stale. A **non-self-identifying** comment at or after `B` cannot be placed at
    all — no boundary exists between the previous head's window and this one.
    Take head `A` triggered at `T1`, a non-self-identifying comment `C` at
    `T2 > T1`, then an untriggered push creating live head `B` at `T3 > T2`: the
    spec's two windows are `[T1, T3)` for `A` and `[T1, ∞)` for `B`, and only
    the transition instant `T3` separates them. No source supplies `T3`
    (Verification Log row `Head-transition source investigation`). Therefore
    such a comment **escalates `evidence_unavailable_codex_thread_state`**. Do
    not guess. This is AC-14's own instruction (spec line 157): "an attribution
    that cannot be established from the available head-and-trigger chronology
    escalates with `evidence_unavailable_codex_thread_state` instead of
    guessing." A non-self-identifying comment **before** `B` is unambiguously
    under an earlier head and stays stale-head evidence.

  **Two boundary kinds, two comparisons — this difference is load-bearing.**

  - At a **trigger-derived** boundary (including the PR-creation fallback), a
    comment qualifies when `created_at >= B`, with a shared second resolved by
    comment ID. That tiebreak is the spec's own (line 107: "fresh only when its
    comment ID orders after the trigger comment") and it works because both
    objects are issue comments with comparable IDs.
  - At an **event-derived** boundary raised by the occupancy guard — a
    `head_ref_force_pushed`, `head_ref_deleted`, or `head_ref_restored` event —
    a comment qualifies only when `created_at` is **strictly greater** than the
    event's `created_at`. GitHub timestamps are second-resolution, and a
    timeline event ID and an issue comment ID are different object types with
    no documented ordering relationship, so a shared second genuinely cannot be
    resolved. Accepting `>=` there would let a prior-occupancy comment that
    shares a second with the force-push be read as current — a false clean.
  - When both boundaries apply, a comment must satisfy **both**.

  The strictly-greater rule costs at most a one-second window of genuine
  post-force-push evidence, and that loss yields a wait — the loop requests or
  awaits a current-head review — never a false clean.

  **`B` and the spec's freshness boundary are one rule, not two.** For a
  triggered live head, spec line 107's freshness boundary — a root comment is
  fresh only when authored after the latest live-head trigger, with the
  comment-ID tiebreak on a shared second — *is* `B`. They coincide by
  construction, so a clean marker-pinned comment satisfies one test, evaluated
  once, using the spec's own tiebreak ("fresh only when its comment ID orders
  after the trigger comment"). For a trigger-less live head, line 107 states no
  freshness boundary at all, and `B` supplies the occupancy test that AC-13's
  supersession and newest-collapse rules then operate on.

  **K1 non-regression check — adding the window test costs nothing for K1.**
  Verified against K1's own scenario before writing: head `A` triggered at `T1`,
  comment `C` authored at `T2` naming `A`, untriggered push to live head `B` at
  `T3`. `C`'s marker names `A`, which is **not** the live head, so `C` takes row
  3 of the table — prior-revision evidence on the stale path — and never reaches
  the window at all. The window test added here applies only to markers naming
  the **live** head, so it cannot reintroduce the defect K1 identified, which
  was about placing a comment whose head is *not* the live one.

  **Scope check — this escalation is rare, not the default.** It requires all
  three of: a trigger-less live head, *and* a root comment that carries no
  well-formed marker, *and* that comment falling at or after the prior
  boundary. A trigger-less head whose comments all carry well-formed markers
  never reaches this escalation — those comments are still boundary-tested for
  occupancy, but a failed test makes them stale-head evidence, not an
  escalation.

  **AC-13 still passes with the window test in place** — verified against the
  spec:

  - AC-13 (spec line 156) is about "a trigger-less live head that has a
    **marker-pinned clean** root comment". Marker-pinned means well-formed and
    naming the head, so such a comment takes row 1 of the table above: its
    marker supplies the head identity and the window supplies the occupancy.
  - For a trigger-less live head, `B` = `max(latest trigger naming another SHA,
    PR created_at)`. A genuine review of the current occupancy is authored after
    that instant, so it passes the window test; only a comment predating it —
    which is precisely a prior-occupancy or prior-head comment — fails.
  - Spec line 107 states the trigger-less clean rule in these terms: "When no
    live-head review trigger exists yet, the newest marker-pinned clean root
    comment **for that head** is the terminal clean evidence for that head only
    when no newer non-dismissed terminal evidence for the same head exists;
    repeated clean comments for the head collapse to that single newest one".
    The window decides *which* comments are for that head's current occupancy;
    the supersession and newest-collapse rules then decide among them exactly as
    AC-13 requires.
  - The trigger-less **escalation** still cannot block AC-13, because it applies
    only to comments with no well-formed marker, and AC-13's evidence is
    marker-pinned by definition.

  **AC-14 is satisfied for the same reason it fails closed.** A
  syntactically-unusable marker is, by definition, a comment that cannot
  self-identify, so it is precisely the input spec line 109 routes through the
  window: it escalates the live head when it falls inside the live head's
  window (triggered head), and it escalates as unattributable when no boundary
  exists (trigger-less head). Both outcomes are fail-closed and neither guesses.

  **The one escalation rule, with two entry conditions.**
  `evidence_unavailable_codex_thread_state` fires when, and only when, the
  attribution of a non-self-identifying comment cannot be established:

  1. **Boundary unreadable** — the pull-request comment read or the timeline
     read used by the occupancy guard fails or is truncated after one retry, or
     a candidate boundary trigger is present but its SHA or `created_at` cannot
     be read from the payload;
  2. **Boundary nonexistent** — the live head is trigger-less and a
     **non-self-identifying** comment falls at or after `B`, the case worked
     through above. A well-formed marker never reaches this condition: it either
     names the live head (and the window test decides it) or names another SHA
     (and takes the stale path).

  Nothing else escalates here, and no branch depends on a push instant or a
  commit date.

  **Accepted residuals** (see **Accepted residuals**): **R1** — on a *triggered*
  live head, a comment authored after the head was pushed but before its trigger
  was posted falls before `B` and is excluded as stale-head evidence; the
  exclusion fails safe in one direction only, since the clean path independently
  requires evidence *after* the trigger under the spec's freshness boundary
  (line 107). No SHA-reuse residual is recorded: the occupancy guard's
  force-push input closes that case, since returning the head to a previously
  current SHA requires a force-update of the ref (see R4, withdrawn).

  No repository-scoped signal is needed or used: the boundary comes from the
  pull request's own triggers, `created_at`, and timeline events, so check runs,
  commit statuses, and the repository `PushEvent` feed play no part
  (Verification Log row `Head-transition source investigation` records why no
  *ordinary-push* transition instant can be sourced at all, which is why the
  trigger-less case escalates rather than approximating). The timeline read the
  occupancy guard performs is a different question with a different answer: it
  asks only whether a force-update of the head ref occurred, which is what
  `head_ref_force_pushed` asserts on its own terms (Verification Log row
  `Force-push event payload`).

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
     its retry, or a live-head window boundary that cannot be identified, is not
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
  | (outside the tie order) Retained environment-setup response | Unavailable (shipped handling, not a hard stop) | `2` / `codex-github-environment-missing` (`codex_return_environment_error`, Verification Log) |

  **Tie rule**: tiers 1–8 resolve strictly in the order above, so on an equal
  newest timestamp cleared-findings wait beats clean. Tier 6 appears here as
  well as in phase 1 so that a hard stop tied at the newest timestamp still
  outranks the wait and clean tiers; a hard stop at an *older* timestamp is
  handled by the hard-stop restoration rule instead, which reaches the same
  unavailable outcome.

  **Environment-setup precedence — one rule, read top to bottom.** Apply these
  three clauses in order; the timing qualifier is part of each, so they cannot
  be read as competing:

  1. **Blocking wins at any timing.** Blocking terminal or review evidence,
     including `CHANGES_REQUESTED`, always defeats a retained environment-setup
     response — whether the blocker is older, newer, or tied. Spec: "Blocking or
     `CHANGES_REQUESTED` evidence always wins over any availability notice", and
     "A blocking terminal or review finding is the one exception to
     newest-wins: it always wins outright over an environment-setup error
     **regardless of timing**."
  2. **Otherwise, strictly newer supersedes.** Among non-blocking competitors, a
     retained environment-setup response is superseded only by **strictly
     newer** terminal or review evidence (spec: "participates only when it is
     itself the newest evidence; a **strictly newer** terminal or review item
     supersedes it").
  3. **Therefore it wins an equal-timestamp tie against clean.** A clean verdict
     sharing the environment response's second is not strictly newer, so it does
     not displace it.

  The environment-setup response is not in the tie order at all — the spec's tie
  list has no environment-setup tier — which is why the table row above sits
  outside it.

  **The enforcing mechanism is the caller's guard, not the selector.** Clause 1
  is enforced *before* any timestamp comparison happens:
  `codex-github-reviewer.sh:1340` tests whether the already-selected evidence is
  `CHANGES_REQUESTED` or `codex_response_is_blocking`, and if so takes the
  no-op branch at `:1349`, so the environment response never replaces it — the
  comment at `:1341–1348` states the contract verbatim ("never discarded by an
  environment-setup error, regardless of timing"). Only when that guard does
  **not** fire does the `elif` at `:1350` consult
  `codex_select_terminal_evidence` (`:997–1014`), which replaces the selection
  when the candidate is strictly newer, or equal-timestamp **and** of strictly
  higher `codex_response_priority` (`:950–972`: blocking / `CHANGES_REQUESTED`
  `3`, unrecognized `2`, availability including environment-setup `1`, approved
  `0`). That is why "priority only breaks ties" is true *within* clause 2 and
  yet clause 1 still holds for an older blocker: the blocking case never reaches
  the selector. The same guard shape protects the usage-limit and
  account-not-connected branches above it. Preserve this structure rather than
  folding clause 1 into the selector.

  Both clauses are pinned by tests. The retained regression
  `codex_main_loop_env_then_review_exit_unavailable` (`tests:6239`) covers
  clause 3 — its fixture has the submitted review at
  `submitted_at: 2026-01-01T00:00:01Z` and the environment-setup root comment at
  `created_at: 2026-01-01T00:00:01Z`, the same second, expecting exit `2` with
  `REASON=codex-github-environment-missing`, which is **consistent** with the
  rule as stated here. Clause 1's older-blocker direction is pinned by the new
  `codex_older_blocker_beats_newer_env_setup` case below. Neither clause changes
  shipped behaviour — the plan's earlier description was incomplete, citing the
  selector as though it were the whole rule; the code already enforces both.

  An environment-setup response is still **not** an availability hard stop and
  never enters phase 1; that is the whole difference between it and a
  usage-limit notice, which terminates immediately and is never superseded.

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
     timestamp aggregated by tiers 1–8. A retained environment-setup response
     is not one of those tiers and is resolved by the **Environment-setup
     precedence** rule above — strictly-newer supersession, so it wins an equal
     timestamp against clean evidence and loses to blocking evidence at any
     timestamp. `W` may be empty.
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
    | `codex_return_reaction_without_review` (`:1396–1403`) | `codex-github-reaction-without-review` | **Remapped to exit `4`** — the only intentional change on this surface. AC-10 requires `waiting_on_reviewer` for acknowledgement-only evidence, and the loop's exit-`2` arm returns `RESULT=escalate`, so the shipped pairing turns that wait into an escalation. The reason string keeps its shipped name, per the spec's "the two waiting codes are the shipped reason codes and keep their existing names and tests" | `codex_reaction_only_exit_unavailable` (`tests:5435`) expectation `2` → `4`, renamed `codex_reaction_only_exit_waiting`; `codex_reaction_only_reason` (`tests:5436`) unchanged |
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
  - **Adapter safety net for the remapped wait** (AC-10, with AC-9's complete
    escalation set): the loop's exit-`2` arm
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
  - **Loop-side ordering change (same surface).** Besides the companion's exit
    and `REASON=` values, this item changes *when* the loop decides
    `needs_fixes`: `run_codex_github_review()` phase 1 currently short-circuits
    on the unresolved count at `pr-review-loop.sh:2190`, before the classifier
    runs at `:2235`, and must instead yield to a current fail-closed escalation
    (see the phase-1 step). Operators see the same `RESULT=` vocabulary; what
    changes is which value a pull request with both an unresolved conversation
    and a malformed or unrecognized current verdict receives.
  - **Reversal path for this published contract.** The exit-code / `REASON=`
    surface is consumed by `run_codex_github_review()`, the Automated Reviewer
    Loop Summary, and `reviewer_loop_history.v1`; all three live in this
    repository, so a reversal is an ordinary `git revert` of the companion and
    adapter commits (Implementation Order steps 3–4, step 4 including the
    phase-1 ordering change that stops the `:2190` short-circuit), the
    cycle-limit change
    (step 5), the AC-6 resolver harness cases (step 6), the Area 13 expectation
    updates (step 7), and the doc updates (step 8). **Step 5 specifically**: it
    changes when `reviewer_loop_cap_exceeded`
    (`pr-review-loop.sh:13555` / `:13559`) escalates, by evaluating current-head
    evidence before the cap fires, so reverting it restores the shipped
    order in which an exhausted allowance escalates unconditionally. That revert
    is self-contained — the cap block reads the classifier's outcome but the
    classifier does not read the cap — so step 5 may be reverted on its own
    without touching steps 3–4, and its only residue is the same append-only
    history text as the rest: runs already recorded as
    `max_cycles_exceeded` under the new order keep that record, and the next run
    re-evaluates under the restored one, because the Statuses table decides each
    outcome per evaluation with no valid transitions. No schema
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

    **The remaining steps, for completeness — all 11 are accounted for.**
    - **Steps 1–2** (create `codex-github-evidence-lib.sh`; move
      `codex_review_thread_evidence_counts()` into it and add the evidence
      collector, marker parser, and window boundary): revert by restoring the
      function to `codex-github-reviewer.sh` at its original call site and
      deleting the library file **and its `sync-manifest.yaml` entry**, which
      must go with it — a manifest entry for a deleted path would offer
      downstream repos a file that no longer exists. The revert order is the
      reverse of the creation order — steps 3–4 must be reverted first, since
      they source the library; reverting 1–2 while 3–4 stand would leave both
      callers sourcing a file that no longer exists. Nothing outside this repository consumes
      the library, and it holds no state.
    - **Step 9** (run the suite, produce the three planted-violation proofs and
      paste them into the pull request): **cannot and should not be undone.**
      The evidence is append-only pull-request text, the same class as the
      history records above; a revert stops new proofs being produced and
      leaves the existing ones as an accurate record of what the code did at
      that commit. Deleting them would destroy audit trail, not restore state.
    - **Step 10** (the `changelog.d/1757.fix.…` fragment): revert by deleting
      the fragment file, but only while it is still unreleased. Once
      `/prepare-release` has assembled it into `CHANGELOG.md` under a version
      heading, the released entry stays — the changelog is a historical record
      — and the revert is instead described in the next release's notes.
    - **Step 11** (verify the smoke runbook on a test pull request): nothing to
      undo; it produces no artefact in this repository beyond the runbook
      already committed on this branch, and re-running it against restored
      behaviour is the correct follow-up rather than a revert.

- [ ] **Cleared-findings retrigger** (AC-8): When terminal finding verdict’s
  findings all correlate to resolved applicable conversations and no other
  applicable unresolved conversation exists, return exit `4` /
  `codex-github-review-pending` (post fresh trigger when appropriate), never exit
  `1`. A `CHANGES_REQUESTED` submitted review remains exit `1` even if every
  thread is resolved — unless it also carries a blocking assertion in its own
  body, which is an uncorrelated finding and escalates
  `codex_finding_thread_correlation_missing` under the canonical
  CHANGES_REQUESTED step below.

- [ ] **CHANGES_REQUESTED + correlation-missing** (AC-7, matrix row 287) —
  canonical wording, identical to the Finding-extraction exception above: a
  `CHANGES_REQUESTED` current-head review carrying **no finding requiring
  correlation at all** — neither an inline finding of its own nor a blocking
  assertion in its body — is an actionable blocker by structured state alone. If
  it carries **any** finding lacking a stable thread identifier or an
  identifiable matching conversation — including a body finding, and including
  when *every* finding lacks one — escalate
  `codex_finding_thread_correlation_missing` (precedence over the structured
  blocker).

### Script layer — `pr-review-loop.sh`

- [ ] **`run_codex_github_review()` phase 1** (AC-1–2, AC-7, AC-9): two changes,
  a **counting** change and an **ordering** change.

  **Counting.** Stop using the raw `check_unresolved_threads` provisional count
  as the `existing_findings` input. Instead call
  `codex_review_thread_evidence_counts()` **with `mode=strict`** — the shared
  classifier moved into `codex-github-evidence-lib.sh` by the Bounded evidence
  query step above, not a new function — and read its `strict_unresolved` field
  only, so the #1508 reply-after-push relaxation can never reach a gate that
  declares clean. It counts only **applicable unresolved** Codex conversations
  for the live head (head SHA / review `commit_id` correlation, not merely
  `isOutdated`). Resolved, outdated, and dismissed-attached threads must not
  increment blocker counts.

  **Ordering — the count is necessary but not sufficient.** Today the gate
  short-circuits: `pr-review-loop.sh:2190` returns `RESULT=needs_fixes` /
  `REASON=existing_findings` with `return 1` as soon as the count exceeds zero,
  and the companion classifier is not invoked until `:2235`. That inverts this
  plan's own precedence contract and the spec's: "Unrecognized evidence
  escalates with `codex_current_verdict_unrecognized`, takes precedence over
  otherwise applicable unresolved conversations", and the Evaluation-order list
  in the Decision-function step resolves a fail-closed winner at step 3, before
  the conversation blocker at step 4. **Phase 1 must therefore classify current
  terminal evidence before choosing an outcome**: with a non-zero count it
  returns `needs_fixes` only when none of the four fail-closed escalations —
  `codex_current_verdict_malformed_revision_marker`,
  `codex_current_verdict_unrecognized`,
  `codex_finding_thread_correlation_missing`, or
  `evidence_unavailable_codex_thread_state` — applies to the live head;
  otherwise it returns that escalation. A zero count still proceeds to the
  trigger-and-wait path exactly as today.

  **This is a behaviour change to a shipped ordering**, not a wording fix, so it
  is recorded in the Outcome-mapping step's reversal note with the rest.
  Regression: `codex_unresolved_thread_with_unrecognized_verdict_escalates`.

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
  (`reviewer_loop_cap_exceeded`, called per-run at `pr-review-loop.sh:13555`
  and lifetime at `:13559` — Verification Log), evaluate current
  head evidence **before** escalating for exhausted allowance: canonical terminal
  clean evidence in the final permitted cycle proceeds to readiness; exhausted
  allowance with cleared-findings retrigger or remaining actionable findings
  escalates (cleared wait must not bypass cap — spec precedence).

- [ ] **Independent allowance resolution** (AC-6): No change to
  `reviewer_loop_resolve_max_cycles` (`pr-review-loop.sh:11201`) /
  `reviewer_loop_resolve_max_total_cycles` (`:11232`) semantics — add harness
  coverage in `test-pr-review-loop.sh` for all **four** independent cases the
  criterion names, two per allowance, so omission and invalidity are each
  proved in both directions:

  | Case | Configuration | Expected |
  | --- | --- | --- |
  | `codex_cap_omit_per_run_keeps_lifetime` | `review.max_cycles` omitted, `review.max_total_cycles` set explicitly | Per-run falls back to **10**; lifetime keeps its configured value; no WARN |
  | `codex_cap_omit_lifetime_keeps_per_run` | `review.max_total_cycles` omitted, `review.max_cycles` set explicitly | Lifetime falls back to **25**; per-run keeps its configured value; no WARN |
  | `codex_cap_invalid_per_run_keeps_lifetime` | `review.max_cycles` invalid, lifetime set explicitly | WARN logged; per-run defaults to **10**; lifetime keeps its configured value |
  | `codex_cap_invalid_lifetime_keeps_per_run` | `review.max_total_cycles` invalid, per-run set explicitly | WARN logged; lifetime defaults to **25**; per-run keeps its configured value |

  Assert the WARN lines only for the two invalid cases (the omitted-value path
  logs none) and read the resolved caps through the existing resolver helpers.

- [ ] **Telemetry** (Operational Visibility): Ensure `print_kv` lines include
  `REVIEWED_HEAD`, `REASON`, and when waiting, existing `PENDING_REVIEW_*` keys.
  Escalation reasons must flow to PR summary unchanged via
  `emit_prefixed_platform_output`.

- [ ] **CodeRabbit assessment** (AC-16): record the assessment in the
  implementation pull request description / test-evidence comment, judged
  against the real comparable path — `coderabbit_thread_gate_clean()`
  (`pr-review-loop.sh:5556`), whose strict audit is at `:5580` (Verification
  Log row `CodeRabbit thread audit (AC-16 surface)`).

  **Expected outcome on the current code: `not_applicable`, with the missing
  capability named as revision correlation.** The invariant this item
  implements has two halves, and CodeRabbit has only one of them:
  - *Resolution state — present.* CodeRabbit already calls the same GraphQL
    helper in `strict` mode and already fails closed when the audit cannot be
    completed, so the resolved-conversation half needs nothing.
  - *Live-revision applicability — absent.* Its audit has no
    `commit_id == headRefOid` test; `isOutdated` is GitHub's own staleness flag,
    not the applicability rule the spec defines, and
    `coderabbit_success_status_count` (`:5799`) answers a different question.

  Re-confirm both halves against the code at implementation time and record
  `shared` only if a revision-correlation test has appeared by then; otherwise
  record `not_applicable` naming that gap. Either way, **no CodeRabbit
  behaviour changes under this item**.

### Tests — `scripts/development-workflow/tests/test-pr-review-loop.sh`

- [ ] **Primary regression** (AC-15, Operational Visibility): Add harness case
  `codex_resolved_visible_finding_waits_after_revision_push`: fixture with **prior
  head** `cccc…` where Codex left a blocking inline thread, operator resolves it
  (`isResolved=true`), then PR advances to **live head** `ffff…` with the old
  review/comment still visible (outdated or resolved-on-new-head). Expect companion
  exit `4` / `REASON=codex-github-review-pending` — not `needs_fixes` from
  historical visibility alone. Include a second sub-assertion on current head
  `ffff…` with a resolved non-outdated thread and a current-head `COMMENTED`
  review whose **body carries no blocking marker** (cleared-findings retrigger
  path). The body constraint is load-bearing, not incidental: under the
  two-source finding rule a blocking body assertion is itself an uncorrelated
  finding, so the same fixture with blocking body text escalates
  `codex_finding_thread_correlation_missing` instead of reaching the
  cleared-findings wait. The subject of this sub-assertion is the resolved
  current-head thread, and it keeps its expected
  `waiting_on_reviewer` / `codex-github-review-pending` outcome.

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
  newer class's outcome, never clean. **Fixture constraint from the marker-first
  routing**: where the superseding item is itself a *root comment*, it must
  carry a well-formed live-head marker so that it self-identifies; a superseding
  root comment with an unusable marker on a trigger-less head does not reach the
  malformed tier at all but escalates `evidence_unavailable_codex_thread_state`,
  which `codex_marker_triggerless_unusable_marker_escalates` covers. A
  superseding *submitted review* is never subject to the window);
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
  per-run and the lifetime cap (`reviewer_loop_cap_exceeded` at
  `pr-review-loop.sh:13555` / `:13559`, Verification Log).

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

- [ ] **Owning-review correlation scoping** (AC-7, spec Business Rule 4),
  two directional cases:
  `codex_body_finding_unrelated_review_comment_not_correlated` — a terminal `R`
  whose blocking text appears only in the review body, while an unrelated
  earlier review has an inline comment on the same live head. Expect
  `codex_finding_thread_correlation_missing`, proving the join runs on
  `pull_request_review_id`, not on the head-wide comment index. And
  `codex_body_finding_own_review_comment_correlates` — the same shape where the
  inline comment **does** belong to `R` **and `R`'s body carries no blocking
  assertion**, so `R`'s findings are its inline findings alone. Expect
  `needs_fixes`. The body-marker condition is part of this fixture, not an
  incidental detail: with a blocking body the mixed-finding rule below would
  escalate instead.

- [ ] **Mixed correlated and uncorrelated findings** (AC-7, spec Business Rule 5
  at spec line 105, matrix row 287): `codex_mixed_inline_and_body_finding_escalates`
  — one submitted current-head review carrying **both** an inline finding whose
  conversation is applicable and unresolved **and** a blocking assertion in its
  own body with no inline comment behind it. Expect `escalate` /
  `codex_finding_thread_correlation_missing`, **not** `needs_fixes` for the
  correlated finding alone and not a cleared-findings wait. Run the same fixture
  once with review state `COMMENTED` and once with `CHANGES_REQUESTED` to prove
  the escalation outranks the structured blocker in both.

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

- [ ] **SHA reuse across occupancies** (L1, spec line 109's "exactly one head's
  evidence window"), three named cases covering both occupancy-guard inputs:
  `codex_marker_sha_reuse_prior_occupancy_not_clean` — head `A` triggered and
  reviewed clean, head `B` pushed **and reviewed**, then the head force-pushed
  back to `A` with no new trigger; the old clean comment naming `A` predates the
  boundary raised by `B`'s newer evidence, so expect `waiting_on_reviewer` /
  `codex-github-review-pending`, not `clean`.
  `codex_marker_sha_reuse_force_push_only_not_clean` — the same shape where the
  intervening head produced **no** Codex evidence and **no** trigger, so the
  only signal is a `head_ref_force_pushed` event newer than `A`'s trigger; it
  must raise the boundary on its own, and the fixture must place the event's
  `commit_id` at the live head to prove the guard does not filter on it. Expect
  the same wait outcome. And `codex_marker_sha_reuse_new_trigger_clean` — a
  fresh trigger for the second occupancy with a new clean comment after it;
  expect `clean`, so the boundary is proved in both directions.

- [ ] **Fail-closed escalation outranks an unresolved conversation in phase 1**
  (P1; AC-7, AC-9; spec: unrecognized evidence "takes precedence over otherwise
  applicable unresolved conversations"):
  `codex_unresolved_thread_with_unrecognized_verdict_escalates` — an applicable
  unresolved current-head conversation **and** a current-head unrecognized
  terminal verdict in the same fixture. Expect `RESULT=escalate` /
  `codex_current_verdict_unrecognized`, **not** `needs_fixes` /
  `existing_findings` from the count alone. Run the same fixture a second time
  with a malformed-marker verdict in place of the unrecognized one, expecting
  `codex_current_verdict_malformed_revision_marker`, so the ordering is proved
  for more than one tier. This is the case today's `pr-review-loop.sh:2190`
  short-circuit gets wrong.

- [ ] **Blocking beats environment-setup at any timing** (R1; spec: a blocking
  finding "always wins outright over an environment-setup error regardless of
  timing"): `codex_older_blocker_beats_newer_env_setup` — a current-head
  blocking review at `T1` and an environment-setup root comment at
  `T2 > T1`. Expect the blocking outcome (exit `1`), **not** the newer
  environment response. Run the same fixture a second time with the blocker
  carried by review state `CHANGES_REQUESTED` and a non-blocking body, so the
  structured-state half of clause 1 is proved too. This is the direction the
  caller's guard at `codex-github-reviewer.sh:1340` enforces before the
  timestamp selector is consulted, and the direction a selector-only reading
  would get wrong.

- [ ] **Sync-manifest mode scope** (U1) — in the **existing** harness
  `scripts/development-workflow/tests/test-sync-template-mode-scopes.sh`, not a
  new file, added to its real-manifest block (`:309–338`) rather than to a
  fixture so it guards the shipped manifest:
  `product_selects_codex_evidence_lib` asserting
  `SELECTED category=always_sync mode_scope=product_repo_injection path=scripts/development-workflow/codex-github-evidence-lib.sh glob=`
  in the `--role product_repo` selector output, mirroring the existing
  `product_selects_product_ci_runtime` assertion at `:180`. Pair it with
  `product_selects_pr_review_loop_with_evidence_lib`, asserting both the caller
  and the library appear in the same output, so the dependency cannot be
  half-injected again.

- [ ] **Matrix spot checks** (AC-7–10 and AC-14 — AC-11, AC-12, and AC-13 have
  their own rows above; this bullet covers the remainder of the range, not all
  of it): Add focused mock-`gh` cases — one per escalation reason, named
  `codex_unrecognized_verdict_escalates`, `codex_malformed_marker_escalates`,
  `codex_correlation_missing_escalates`, and
  `codex_evidence_unavailable_escalates` (the first is the target of a
  planted-violation proof, so it must exist under that name) — plus
  cleared-findings wait vs clean tie, stale-head malformed ignored, and
  `CHANGES_REQUESTED` with all threads resolved — that last fixture's review
  body must carry **no** blocking marker (the Seed Data row already pairs
  `CHANGES_REQUESTED` with a clean-template body), since a blocking body
  assertion is itself an uncorrelated finding and escalates
  `codex_finding_thread_correlation_missing` ahead of the structured blocker. Update existing Area 13 tests
  that expect `NEEDS_REVISION (unrecognized response format — safe-fail)` to
  expect escalate / `codex_current_verdict_unrecognized` instead, and update
  `codex_cleared_thread_top_level_blocker_*` expectations from exit `1` /
  `NEEDS_REVISION` to the correlation-missing escalation path whenever the
  review's body carries a blocking assertion — by the two-source rule that now
  holds whether or not the review also has inline comments, not only in the
  body-only shape.

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
6. Unrecognized terminal body → escalate `codex_current_verdict_unrecognized` (AC-7, 9)
7. Finding without thread id, and the mixed case — one correlated inline
   finding plus an unthreaded body finding in the same review → escalate
   `codex_finding_thread_correlation_missing` (AC-7, 9; spec line 105, matrix
   row 287)
8. Malformed marker on live head → escalate `codex_current_verdict_malformed_revision_marker` (AC-9, 11, 14)
9. GraphQL thread state failure → escalate `evidence_unavailable_codex_thread_state` (AC-9)
10. Acknowledgement-only → `codex-github-reaction-without-review` precedence (AC-10)
11. `CHANGES_REQUESTED` with resolved threads and no blocking body assertion →
    `needs_fixes` (AC-1, 2)
12. CodeRabbit assessment recorded `shared` or `not_applicable` — expected
    `not_applicable` on the current code, missing capability: revision
    correlation (AC-16)
13. Trigger-less marker-pinned clean superseded by newer live-head evidence, and
    repeated clean comments collapsing to the newest (comment-ID tie) (AC-13)
14. Account-not-connected hard stop keeps its own exit-`3` reason code instead of
    being reported as a usage limit (Operational Visibility)

### Planted-violation evidence (REVIEW.md workflow-surface checklist item 4)

This item modifies an automated review guard, so the implementation pull
request must carry same-pull-request planted-violation proof: each new or
modified check is shown to **fail** with a targeted violation in place and to
**pass** after restoration. Record the command, the failing test name, and both
outcomes in the implementation pull request's test-evidence comment. Three
plants, each at a concrete target, chosen so no earlier rule masks them:

| Plant | Concrete target | Expected failing test | Restoration |
| --- | --- | --- | --- |
| Unrecognized verdict is not fail-closed | In `codex-github-evidence-lib.sh`, `codex_classify_live_head_evidence()` tier-2 branch: return `clean` instead of `escalate` | `codex_unrecognized_verdict_escalates` fails (expects `codex_current_verdict_unrecognized`) | Revert the one-line change; test passes |
| Correlation is not scoped to the owning review | In the finding-extraction helper, drop the `pull_request_review_id == R.id` predicate so the head-wide comment index is used | `codex_body_finding_unrelated_review_comment_not_correlated` fails (escalation becomes `needs_fixes`) | Restore the predicate; test passes |
| Exit-`3` reason is hardcoded again | In `pr-review-loop.sh`, the exit-`3` arm at `:2294`: replace the `kv_value_default REASON …` read with the literal `codex-github-usage-limit` | `codex_exit3_account_not_connected_reason_preserved` fails | Restore the `kv_value_default` read; test passes |

Masking check, required by the same checklist item: each plant's fixture must
contain **no other** fail-closed item, no applicable unresolved live-head
conversation, and no availability hard stop, so the planted tier is the one
that decides the outcome. State that explicitly in the evidence comment — a
plant whose answer is supplied by an earlier tier is not a proof.

**Smoke test runbook**: `docs/testing/workflow/1757-resolved-codex-findings.smoke-test.md`

**Regression suite**: Extend `scripts/development-workflow/tests/test-pr-review-loop.sh`
for the Codex behaviour, plus
`scripts/development-workflow/tests/test-sync-template-mode-scopes.sh` for the
packaging assertion above. Both are existing harnesses; this item adds no new
test file.

### Parser-risk addendum (`Reviewed commit` marker + blocking-body scan)

**`Reviewed commit` field grammar — derived from the shipped extractor, not
invented.** The whole grammar is one `sed` expression,
`codex-github-reviewer.sh:496`:

```text
sed -n 's/.*Reviewed commit:[^`]*`\([0-9a-fA-F]\{7,40\}\)`.*/\1/p' | tail -n 1
```

Every statement below is a property of that expression (or of the comparison at
`:497`), so the list is closed by the pattern itself rather than by enumerating
input shapes. The canonical form Codex actually emits —
`**Reviewed commit:** \`37d5bd35da\`` on this pull request (Verification Log row
`Codex marker token width`) — matches it.

| Property | Behaviour, and what establishes it |
| --- | --- |
| Decoration is irrelevant | The leading `.*` absorbs anything before the field name and `[^\`]*` absorbs anything between the colon and the opening backtick, so `**Reviewed commit:**` and a bare `Reviewed commit:` behave identically (`:496`) |
| Field name is literal and case-sensitive | `Reviewed commit:` is a BRE literal with no `I` flag, so `reviewed commit:` does not match; the `-i` at `:497` applies to the SHA comparison only, not the field name |
| Exactly one space, and the colon is required | The literal contains a single space and a trailing colon; a tab, a double space, or a missing colon does not match (`:496`) |
| The token must be backtick-delimited | The capture is bracketed by literal backticks, so `Reviewed commit: 37d5bd35da` extracts nothing (`:496`) |
| Token charset and length | `[0-9a-fA-F]\{7,40\}` — hex only, 7 to 40 characters. A 6-character token fails the lower bound; a 41-character hex run cannot match because the character after a 40-character capture must be a backtick (`:496`) |
| An intervening backticked span defeats extraction | `[^\`]*` cannot cross a backtick, so in `Reviewed commit: \`x\` \`abcdef1\`` the first backtick ends the run and the candidate token is `x`, which fails the charset/length test; the line yields nothing (`:496`) |
| Multiple occurrences on one line: the last wins | The leading `.*` is greedy, so it consumes up to the final `Reviewed commit:` on the line (`:496`) |
| Multiple lines: the last matching line wins | `sed` is line-scoped and `tail -n 1` keeps the final matching line (`:496`) |
| Fenced and quoted text are **not** excluded | Unlike `codex_response_is_account_not_connected` (`:487`), `codex_response_reviews_current_head` (`:493–498`) never calls `codex_response_has_fence_marker`, so a marker inside a code fence or blockquote is extracted like any other (`:493–498`) |
| Head comparison is a mutual prefix test | `:497` accepts when either string is a case-insensitive prefix of the other. The token is hex-constrained by `:496`, which is what makes passing it to `grep` as a pattern safe |

**Three places where the shipped extractor and the spec disagree.** Each is a
change this item must make, not a description to soften:

1. **Multiple tokens.** The spec classifies a marker with "multiple commit
   tokens" as syntactically unusable →
   `codex_current_verdict_malformed_revision_marker`. The extractor instead
   silently takes the last occurrence (line-greedy `.*`, then `tail -n 1`). The
   new classifier must therefore **count occurrences before selecting one**;
   it cannot reuse `:496` as a well-formedness test.
2. **Superstring tokens.** `:497` accepts a token that *contains* the live head
   as a prefix, because the comparison is mutual. The spec calls that
   syntactically unusable. The existing **Superstring** edge-case row already
   pins the spec's answer; this citation records that it is a change to shipped
   behaviour, covered by the classifier revert scope (Implementation Order
   steps 3–4).
3. **Empty versus absent field.** At `:496` both yield no extraction and are
   indistinguishable. AC-11 requires them to diverge — empty escalates
   malformed, absent is acknowledgement evidence — so field **presence** must be
   detected separately from token extraction. The AC-11 test pair already pins
   the two outcomes; this is why it needs new code rather than a reused helper.

Cases the pattern does **not** decide are not invented here. Where a form simply
fails to match (case variants, spacing variants, missing colon, unbackticked or
out-of-range tokens), the result is "no token extracted", which the classifier
treats as an absent value and routes through the empty-versus-absent rule above.

**Edge-case enumeration** (concrete inputs for `codex_parse_reviewed_commit_marker`
and head-attribution helpers):

| Case | Example marker / input | Expected class |
| --- | --- | --- |
| Valid prefix | Live head `abc1234…`, marker `abc1234` | Well-formed, live-head |
| Field grammar: canonical form | `**Reviewed commit:** \`abc1234\`` | Extracted — decoration is absorbed by `.*` / `[^\`]*` |
| Field grammar: no decoration | `Reviewed commit: \`abc1234\`` | Extracted — identical behaviour to the canonical form |
| Field grammar: unbackticked token | `Reviewed commit: abc1234` | Not extracted — the capture requires backticks |
| Field grammar: literal variants | `reviewed commit:`, `Reviewed  commit:`, `Reviewed commit` (no colon) | Not extracted — the field name is a case-sensitive literal with one space and a colon |
| Field grammar: token length bounds | Backticked `abc123` (6) and a 41-character hex run | Not extracted — `[0-9a-fA-F]\{7,40\}` |
| Field grammar: intervening backtick span | `Reviewed commit: \`x\` \`abc1234\`` | Not extracted — `[^\`]*` cannot cross a backtick |
| Field grammar: repeated field | Two `Reviewed commit:` fields on one line, or on two lines | Shipped takes the last; spec requires **malformed** for multiple tokens |
| Field grammar: inside a fence | Marker inside a code fence or blockquote | Extracted — this function has no fence guard |
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
| Stale-head window | Malformed marker authored before the boundary `B` | Ignored for live head |
| Boundary unreadable | The pull-request comment read fails after one retry, or a candidate boundary trigger has no readable SHA or `created_at` | Evidence unavailable |
| Trigger-less live head, marker-pinned clean | Live head has no trigger; a well-formed marker names it, body clean, and it passes the boundary test | Clean — marker gives the head, the boundary gives the occupancy (AC-13) |
| SHA reuse, prior-occupancy clean | Marker names the live head but the comment predates the raised boundary `B` | Stale-head evidence — must not authorize readiness |
| SHA reuse, force-push signal only | Intervening head left no evidence and no trigger; a `head_ref_force_pushed` event is newer than the live-head trigger | Boundary raised by the event alone — prior-occupancy comment ignored |
| Trigger-less live head, unusable marker | Live head has no trigger; a syntactically-unusable-marker comment falls at or after the prior boundary | Evidence unavailable — no boundary exists (AC-14) |
| Untriggered head after a prior trigger | Head `A` triggered, comment `C` authored, untriggered push to live head `B`; `C` carries no well-formed marker | Evidence unavailable — `C` cannot be placed in `A`'s or `B`'s window |
| Pre-trigger comment | Comment authored after the live head was pushed but before its trigger, marker-pinned or not | Stale-head evidence — excluded (residual R1) |
| Proven remote zero-match | Abbreviated marker token, no local match after fetch and retry, REST `422` | Malformed — resolves to zero commits (spec line 286) |
| Unprovable abbreviation | Abbreviated marker token, no local match after fetch and retry, REST `200` | Evidence unavailable — exists, uniqueness unprovable |
| Superseded malformed | Live-head malformed comment older than live-head clean evidence | Ignored — newer clean wins |
| Mixed inline + body finding | One review with a correlated inline finding and a blocking assertion in its body | Correlation-missing escalation (spec line 105, matrix row 287) |
| Older blocker vs newer environment-setup | Blocking review at `T1`, environment-setup comment at `T2 > T1` | Blocker wins — clause 1 applies regardless of timing |

**Unit test mapping** (all in `scripts/development-workflow/tests/test-pr-review-loop.sh`
Area 13 — one `run_test` per row):

| Test name prefix | Edge case row |
| --- | --- |
| `codex_marker_valid_prefix` | Valid prefix |
| `codex_marker_field_canonical_bold_backtick` | Field grammar: canonical form |
| `codex_marker_field_plain_backtick_no_bold` | Field grammar: no decoration |
| `codex_marker_field_unbackticked_token_not_extracted` | Field grammar: unbackticked token |
| `codex_marker_field_literal_variants_not_extracted` | Field grammar: literal variants |
| `codex_marker_field_token_length_bounds` | Field grammar: token length bounds |
| `codex_marker_field_intervening_backtick_span` | Field grammar: intervening backtick span |
| `codex_marker_field_repeated_field_malformed` | Field grammar: repeated field |
| `codex_marker_field_inside_fence_extracted` | Field grammar: inside a fence |
| `codex_marker_prior_revision_stale` | Prior revision well-formed |
| `codex_marker_empty_value` | Empty value |
| `codex_marker_non_hex` | Non-hex token |
| `codex_marker_multiple_tokens` | Multiple tokens |
| `codex_marker_ambiguous_prefix` | Ambiguous prefix |
| `codex_marker_interior_substring` | Interior substring |
| `codex_marker_superstring` | Superstring |
| `codex_marker_freshness_fail` | Freshness fail |
| `codex_marker_same_second_stale` | Same-second tie |
| `codex_marker_same_second_fresh` | Same-second tie win |
| `codex_marker_stale_head_window` | Stale-head window |
| `codex_marker_boundary_unreadable` | Boundary unreadable |
| `codex_marker_triggerless_clean_attributed_by_marker` | Trigger-less live head, marker-pinned clean |
| `codex_marker_sha_reuse_prior_occupancy_not_clean` | SHA reuse, prior-occupancy clean |
| `codex_marker_sha_reuse_force_push_only_not_clean` | SHA reuse, force-push signal only |
| `codex_marker_triggerless_unusable_marker_escalates` | Trigger-less live head, unusable marker |
| `codex_marker_untriggered_head_after_prior_trigger_escalates` | Untriggered head after a prior trigger |
| `codex_marker_pre_trigger_comment_excluded` | Pre-trigger comment |
| `codex_marker_remote_zero_match_malformed` | Proven remote zero-match |
| `codex_marker_unprovable_abbreviation` | Unprovable abbreviation |
| `codex_tied_usage_limit_then_unrecognized` | Availability notice tied with fail-closed evidence — **existing test, update to expect escalation** (not the unavailable outcome) |
| `codex_tied_usage_limit_then_blocker` | Availability notice tied with an actionable blocker — expect `needs_fixes` |
| `codex_older_malformed_superseded_by_newer_clean` | Superseded malformed — older live-head malformed-marker comment with strictly newer live-head clean evidence; expect `clean` (newest-evidence selection precedes tier aggregation), **not** the malformed escalation |
| `codex_hard_stop_restored_when_competitor_superseded` | Availability hard stop with a *superseded* blocker or malformed item and a newer clean verdict — expect the unavailable outcome (exit `3`), never clean |
| `codex_body_finding_unrelated_review_comment_not_correlated` | Review-body-only finding with an unrelated review's inline comment on the same head — expect correlation-missing |
| `codex_body_finding_own_review_comment_correlates` | Same shape, inline comment owned by the terminal review and no blocking body assertion — expect correlation (no escalation) |
| `codex_mixed_inline_and_body_finding_escalates` | Mixed inline + body finding |
| `codex_older_blocker_beats_newer_env_setup` | Older blocker vs newer environment-setup |

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

## Accepted Residuals

Both of this plan's open questions have the same shape — proving a negative with
certainty — and neither the spec nor the available APIs offer a source that
would settle them. They are decided here rather than re-litigated per reviewer
cycle. Each records what is **not** proven, why the spec tolerates it, and which
direction it fails.

### R1 — A comment posted between the head's push and its trigger is excluded

- **Not proven**: that a root comment authored after the live head was pushed
  but before the live-head trigger was posted belongs to the live head's current
  occupancy. It falls before the boundary `B` and is classified as stale-head
  evidence. This applies to marker-pinned comments too, since the window test is
  a necessary condition for live-head evidence — the marker establishes *which*
  head, `B` establishes *which occupancy*.
- **Why the spec tolerates it**: spec line 109 defines the window from triggers
  and the pull request's creation, not from push instants, and it gives
  stale-head evidence no effect on a later head. Nothing in the criteria asks
  for the excluded comment to be recovered.
- **Fails**: toward **wait**. Excluding evidence can only withhold a clean
  result, never manufacture one. The clean path independently requires evidence
  *after* the trigger under the spec's freshness boundary (line 107), so a
  comment excluded by `B` could not have authorized readiness in the first
  place; the loop requests or awaits a current-head review instead.
- **Replaces**: the earlier `committer.date` residual, which is gone with the
  transition-instant machinery. The companion case — a trigger-**less** live
  head carrying a non-self-identifying comment — is not a residual at all: it
  escalates `evidence_unavailable_codex_thread_state`, because there the two
  windows genuinely overlap and no source separates them.

### R2 — Abbreviated-token uniqueness is scoped to the fetched object set

- **Not proven**: that an abbreviated marker token is unique among *all* commits
  that have ever existed for the repository. `git rev-parse --disambiguate`
  proves uniqueness over the local object set after the head-ref fetch, and the
  GitHub REST API reports no candidate set at all, so no stronger check exists.
- **Why the spec tolerates it**: spec line 107 requires the token to "resolve
  unambiguously to a single commit" without naming a resolution source, and git
  itself uses exactly this scope when `core.abbrev` auto-sizes a short SHA —
  unique among the objects it holds.
- **Arithmetic at this repository's size**: `git count-objects -v` reports
  40,637 loose plus 24,279 packed objects ≈ 6.5×10⁴. The expected number of
  colliding prefix pairs is `N² / (2 · 16ᵏ)`: ≈ 7.8 at `k = 7`, ≈ 0.49 at
  `k = 8`, and ≈ 0.0019 at `k = 10` — so at the 10 characters Codex actually
  emits, the chance that *any* colliding pair exists anywhere in the object set
  is about 1 in 500, and the marker would additionally have to collide with the
  live head specifically.
- **Fails**: toward **clean**, in one bounded case — stated plainly rather than
  softened. A collision the local object set *does* contain is detected and
  classified malformed, so that direction is safe; but a colliding commit that
  exists in the repository and was never fetched leaves
  `git rev-parse --disambiguate` reporting a single candidate, and the marker
  then passes as an unambiguous prefix. That is a false-clean direction, not an
  escalation, and the earlier wording in this plan was wrong about it.
- **Bound**: expected colliding prefix pairs are `N² / (2 · 16ᵏ)` over this
  repository's ≈ 6.5×10⁴ objects — ≈ 0.0019 at the `k = 10` characters Codex
  emits, i.e. roughly 1 chance in 500 that *any* colliding pair exists anywhere
  in the object set, and the collider would additionally have to be both
  unfetched and a prefix-match for this specific marker.
- **Decision**: taken by the **repository owner during the cycle-9 review of
  this pull request**, not self-accepted by this plan. The rejected alternative
  was failing abbreviated tokens closed whenever repository-wide uniqueness
  cannot be proven. It was rejected because Codex emits 10-character tokens in
  production — `37d5bd35da` and `76dc7213b8` on this very pull request
  (Verification Log row `Codex marker token width`) — so closing them would make
  the **clean path unreachable for ordinary Codex traffic**, a strictly worse
  failure than the bounded case above. Revisiting this requires another owner
  decision, not a plan edit.

### R3 — A blocking body assertion that only restates inline findings still escalates

- **Not proven**: that a blocking marker in a review's body introduces a finding
  *beyond* the review's inline comments. Detection is by the shipped
  `codex_response_is_blocking()` vocabulary, which reports presence, not
  provenance, so a body that merely summarises its own inline findings
  ("Changes requested — see comments") is treated as a review-level finding
  with no thread identity.
- **Why the spec tolerates it**: spec Business Rule 4 classifies "a review-level
  finding or comment without a review-thread identifier" as incomplete evidence
  rather than an actionable blocker, and Business Rule 5 (spec line 105) makes
  the mixed case escalate outright. The spec offers no way to attribute body
  text to a specific inline finding, and explicitly declines to define a new
  marker vocabulary that could carry one.
- **Fails**: toward **human review**. The outcome is
  `codex_finding_thread_correlation_missing`, which stops the run; it can never
  produce a false clean or silently drop an actionable finding. The opposite
  choice — ignoring body markers whenever an inline finding exists — is the
  defect this residual replaces, and it failed toward `needs_fixes` on
  incomplete evidence.

### R4 — Withdrawn: the SHA-reuse case is closed by a mechanism

Cycle 12 recorded the undetectable SHA-reuse shape as an accepted residual that
failed toward clean. It is **withdrawn**, because the occupancy guard now closes
it: returning the head to a previously current SHA requires a force-update of
the ref, which emits a `head_ref_force_pushed` timeline event, and any such
event newer than the live-head trigger raises `B` past the prior-occupancy
evidence. Verified against live data rather than assumed — Verification Log row
`Force-push event payload`. No residual is recorded here, and no case in this
plan is now knowingly accepted in the false-clean direction except the one R2
records under an explicit human decision.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Area 13 mass-update breaks unrelated Codex cases | Med | Med | Change expectations incrementally; run full `test-pr-review-loop.sh` before PR |
| Classifier divergence between companion and loop phase 1 | Med | High | Single shared `codex-github-evidence-lib.sh` sourced by both; never source the companion executable |
| False clean from provisional reply relaxation | Low | High | Keep provisional mode only on re-trigger path; strict on clean declaration |
| Escalation reasons not surfaced in PR summary | Low | Med | Assert `REASON=` in harness + Step 7a alignment check |
| Marker token unresolvable locally (shallow or unfetched clone) | Med | Med | One `git fetch` of the head ref then retry; then REST settles existence only — `422` is a proven zero-match (malformed tier), `200` leaves uniqueness unprovable (evidence-unavailable), and REST or `git` failures escalate evidence-unavailable |
| Retained exit-`2` reasons regress while adding the new codes | Med | High | Retained-contract table names every retained reason and its pinned test; scoped harness assertion plus a non-regression assertion for the three retained reasons |
| Published exit / `REASON=` contract is hard to unwind | Low | Med | Revert is code-only — Implementation Order steps 3–8 (classifier, adapter, cycle-limit change, AC-6 harness, Area 13 expectations, docs), with step 5 revertible on its own; residues documented in the Outcome-mapping reversal note |
| A comment posted between the head's push and its trigger is excluded as stale-head evidence | Med | Low | Accepted residual R1: exclusion can only withhold a clean result, never create one, because the clean path independently requires post-trigger evidence (spec line 107). `codex_marker_pre_trigger_comment_excluded` and `codex_marker_triggerless_clean_attributed_by_marker` pin the excluded and marker-attributed cases |
| A reused head SHA lets a prior-occupancy clean comment authorize readiness | Low | High | The window test is a necessary condition for live-head marker evidence, and the occupancy guard raises `B` past both newer evidence naming another SHA and any `head_ref_force_pushed` event — which SHA reuse cannot avoid emitting; `codex_marker_sha_reuse_prior_occupancy_not_clean` pins it |
| Shared helper loses the #1508 relaxation, or leaks it into the strict gate | Med | High | Explicit `mode` parameter with strict fallback plus a third output field; both call sites mapped, and three named mode tests pin provisional, strict, and the fallback |
| A trigger-less head that also carries a non-self-identifying comment escalates | Low | Med | Genuine: no source supplies the transition instant that would separate the two windows (Verification Log). Escalation is AC-14's own instruction, it requires all three conditions in the scope check, and `codex_marker_untriggered_head_after_prior_trigger_escalates` pins it |

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
   source it from `codex-github-reviewer.sh` and `pr-review-loop.sh`. **In the
   same commit, declare it in `sync-manifest.yaml`**, mirroring the
   `workflow-lib.sh` precedent at `:118–120` and placed with the other
   product-repo runtime entries:

   ```yaml
   - path: scripts/development-workflow/codex-github-evidence-lib.sh
     mode_scope: product_repo_injection
     note: shared Codex evidence helpers required by pr-review-loop.sh
   ```

   Without it the recursive `hub_only` rule at `:105–108` excludes the file
   while `pr-review-loop.sh` (`:121–123`) is still injected, so a synced
   product repo would receive a loop that **fails at load time** — the library
   is sourced unconditionally, not lazily. Commit.
2. Implement terminal evidence collector + marker parser + marker-first
   routing and the live-head window boundary `B`; commit.
3. Implement `codex_classify_live_head_evidence()` decision matrix and wire all
   companion exit paths; commit.
4. Update `run_codex_github_review()` adapter (phase 1 counting **and**
   ordering, exit mapping, remove count floor); commit.
5. Adjust cycle-limit block to evaluate canonical clean before cap escalation; commit.
6. Add independent `review.max_cycles` / `review.max_total_cycles` resolver harness
   cases (AC-6); commit.
7. Add/update Area 13 harness cases (marker table + primary regression) + one
   `run_codex_github_review` case; commit.
8. Update `codex-github.md` and Protocol 93 cross-links; commit.
9. Run `bash scripts/development-workflow/tests/test-pr-review-loop.sh` (or CI
   equivalent) and fix failures; then produce the three planted-violation
   proofs from the Testing Strategy table — plant, run the named test, record
   the failure, restore, re-run, record the pass — and paste the evidence into
   the implementation pull request before requesting review.
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
- Implementation-order consistency: Checked — 11 steps: shared evidence lib
  extraction precedes classifier, adapter, caps, the AC-6 resolver harness,
  Area 13 cases, and docs; the suite run and the three planted-violation proofs
  are step 9, the changelog fragment step 10, and the smoke runbook step 11.
  Every cross-reference to a step (“Implementation Order steps 3–4”, “step 7”,
  “step 8”) names the list it indexes, so it cannot be read as the classifier's
  evaluation-order steps.
- Verification support: Checked — every Verification Log row was re-run at plan
  revision `39327e36`, and each row states the exact command so its number is
  reproducible rather than asserted (for example the exit-`2` inventory records
  both the raw `grep -c` result, 53, and the executable-site count, 52, with the
  command that produces each). The correlation joins cite GraphQL `databaseId`
  + REST `id` for threads and `pull_request_review_id` +
  `pullRequestReview.databaseId` for review scoping.
- Field-grammar completeness: Checked — the `Reviewed commit` grammar is derived
  from the shipped extractor at `codex-github-reviewer.sh:496` and the head
  comparison at `:497`, with every property citing the line that establishes it
  (decoration, case sensitivity, spacing, backtick delimitation, charset and
  7–40 length bounds, intervening-backtick behaviour, last-occurrence and
  last-line selection, and the absent fence guard). Three spec-versus-shipped
  disagreements are named as changes this item makes — multiple tokens, the
  superstring comparison, and empty-versus-absent field presence — rather than
  described away. No hypothetical syntax is enumerated: forms the pattern simply
  fails to match resolve as "no token extracted".
- Parser-risk completeness: Checked by extraction — the addendum's edge-case
  table has 32 rows and its mapping table has 37 test names, of which 29 carry
  the `codex_marker_` prefix; every edge-case label appears verbatim in the
  mapping table, the superseded-malformed row maps to a precedence name, and
  the eight remaining mapping rows are the tie/precedence and correlation cases
  that have no marker input of their own.
- Complex workflow decision-gate matrix: Checked — spec matrix is authoritative;
  implementation mirrors spec rows via `codex_classify_live_head_evidence()`.
  Newest-evidence selection runs **before** tier aggregation, per the spec's
  "Later non-dismissed terminal evidence for the same live head supersedes
  earlier current-head evidence before that precedence ordering is applied";
  the only timestamp-independent exceptions are indeterminate evidence, an
  applicable unresolved live-head conversation, and the two availability hard
  stops. A hard stop yields only to a *canonical* competitor — that same
  unresolved conversation, or a phase-2 winner in tiers 1–5 — and is otherwise
  restored by the hard-stop restoration rule. Environment-setup is retained
  separately and is never a hard stop. The normative Evaluation-order
  list is the single tie-breaker between the phase narrative and the
  pre-selection guard, and its worked examples agree with the guard for every
  listed batch. No contradictory next actions across plan layers.
- Live-head evidence window: Checked against the spec, not invented — one
  four-row routing contract, stated identically everywhere it appears. The
  marker answers *which head*: a well-formed marker naming another SHA is
  prior-revision evidence on the stale path and **bypasses the window**; a
  well-formed marker naming the live head is live-head evidence **only if it
  also passes the boundary test**: `created_at >= B` at a trigger-derived
  boundary, with the spec's comment-ID tiebreak, and **strictly** greater at an
  event-derived one, where no cross-type tiebreak exists. Spec line 109 binds
  every root comment to one head's evidence window and a SHA can occupy the head
  position twice. A comment with no well-formed marker is decided by `B` alone,
  escalating
  when the live head is trigger-less. `B` is the latest live-head trigger —
  which provably post-dates that occupancy, since the companion resolves
  `headRefOid` before posting — raised by the occupancy guard when newer
  other-SHA evidence or a `head_ref_force_pushed` event shows the head moved.
  AC-13 (spec line 156) still passes: for a trigger-less head `B` is
  `max(prior trigger, PR created_at)` and a genuine current-occupancy review is
  authored after it. AC-14 (spec line 157) supplies the escalation. No head
  enumeration, no head ordering, no transition instant, and no commit date
  appears anywhere in the algorithm.
- Packaging scope: Checked — the new shared library carries its own
  `sync-manifest.yaml` entry with `mode_scope: product_repo_injection`,
  mirroring the `workflow-lib.sh` precedent, because the recursive `hub_only`
  rule on `scripts/development-workflow/` would otherwise exclude it while its
  caller `pr-review-loop.sh` is injected. Declared in Implementation Order step
  1, removed with the library in the reversal path, and guarded by two named
  assertions in the existing `test-sync-template-mode-scopes.sh` real-manifest
  block.
- Executable interfaces: Checked — the shared helper declares parameters,
  stdout shape, and return codes; both call sites are mapped from their actual
  variable names; a `set -u` no-global-reads test is named; and the helper
  carries an explicit `strict|provisional` mode with a third output field, so
  the #1508 reply-after-push relaxation is preserved for re-trigger eligibility
  and cannot leak into the loop's strict blocker count. Unknown modes fall back
  to strict, matching the shipped `check_unresolved_threads`.
- Resolution mechanisms named: Checked — the prefix half of the readiness test
  is a string comparison against `headRefOid` and touches no object database;
  only the ambiguity half does. Commit tokens resolve through
  `git rev-parse --disambiguate` (the only ambiguity test) and `--verify` (value
  lookup), with the GitHub REST endpoint admissible only for a full 40-character
  token, where ambiguity is impossible, and for the existence question alone on
  an abbreviated token. A per-observation outcome table keeps the spec's two
  outcomes distinct: a proven zero-match (REST `422`) is malformed-marker per
  spec line 286, while existence-without-provable-uniqueness (REST `200`) and
  every read failure are `evidence_unavailable_codex_thread_state`.
- Planted-violation evidence: Checked — three plants at concrete targets, each
  with its failing test, its restoration, and the masking check REVIEW.md
  requires.
- Dependency state: Checked — the plan states the two base checks for spec
  #1758 and the stop-and-report behaviour when either fails.
- Shipped-contract inventory: Checked — every companion `exit 2` site was
  enumerated from source (Verification Log row `Exit-2 reason inventory`) and
  classified as retained, remapped, or added, with the pinned harness cases
  named for each; the only behavioural remap is the acknowledgement wait moving
  from exit `2` to exit `4`, which AC-10 requires.
- Correlation scoping: Checked — finding extraction, the cleared-findings rule,
  and the `CHANGES_REQUESTED` exception all consume the same per-review finding
  set keyed on `pull_request_review_id`, and no section correlates against the
  head-wide inline-comment index. Within a review the two finding sources are
  independent: inline rows and body blocking assertions are both always
  evaluated, so the mixed case escalates per spec Business Rule 5 (line 105) and
  matrix row 287 instead of returning `needs_fixes` for the correlated finding
  alone. Body detection reuses the shipped `codex_response_is_blocking()` /
  `CODEX_BLOCKING_PATTERN` surface, so no marker vocabulary is introduced.
- Accepted residuals recorded: Checked — three live residuals plus one
  withdrawn, each stating what is unproven, why it is tolerated, and the
  direction it fails: R1 pre-trigger comment exclusion (fails toward wait), R2
  abbreviation uniqueness scoped to the fetched object set (**fails toward
  clean**, bounded at ≈ 0.0019 expected colliding pairs for a 10-character token
  over this repository's ≈ 6.5×10⁴ objects, and carrying an explicit repository
  owner decision from the cycle-9 review of this pull request), R3 body markers
  that only restate inline findings (fails toward human review), and R4
  withdrawn because the occupancy guard's force-push input closes the SHA-reuse
  case. R2 is the only knowingly accepted false-clean path, and it is a human
  decision rather than a plan self-acceptance.
- Reversal risk: Checked — the outcome-mapping step states the revert path for
  **all 11 Implementation Order steps**: steps 3–8 are the code and docs revert
  (with step 5 self-contained and revertible alone, and steps 3–4 inseparable);
  steps 1–2 revert by restoring the moved function and deleting the library,
  after 3–4 and not before; step 9's planted-violation evidence and step 10's
  already-released changelog entry **cannot and should not be undone**, being
  append-only records; and step 11 leaves nothing to undo. Partial reversal of
  individual reason codes is unsupported.
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
  `codex_adapter_` / `codex_evidence_lib_` / the four
  `codex_*_escalates` reason cases. Phase names (`Phase 1`
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
  `REASON=codex-github-reaction-without-review` (key scenario 10, AC-10), which
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
| Spec #1758 present in base | Merged at `7a97d571` (2026-09-16) | `git merge-base --is-ancestor 7a97d571 HEAD` **and** spec file present; stop and report if either fails |
| No concurrent Codex classifier PRs in batch | Verified at dispatch | `Still valid` unless a same-surface PR merged mid-batch |
| Companion exit codes unchanged for availability | Verified | `Still valid` — preserve exits `2`/`3` for timeout and the two hard-unavailable outcomes. The single intentional exit-code change in this item is the acknowledgement wait moving from exit `2` to exit `4`, which is not an availability outcome (see the exit-`2` retained-contract table) |
| Script line numbers in the Verification Log | Measured at plan revision `39327e36` | Re-measure before editing: `pr-review-loop.sh` grows on `develop`, so cited lines such as `:13555` / `:13559` and `:2294` / `:2322` must be re-confirmed by `grep`, not trusted |

Implementer must mark `Still valid` or stop with evidence if stale.

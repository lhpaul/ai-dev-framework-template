# Smoke Test Runbook: Resolved Codex Findings No Longer Block Reviewer Loop

**Feature**: Do not count resolved Codex findings as current blockers
**Spec**: [`docs/specs/developments/20260915075927_1757-resolved-codex-findings/1_1757-resolved-codex-findings_specs.md`](../../specs/developments/20260915075927_1757-resolved-codex-findings/1_1757-resolved-codex-findings_specs.md)
**Plan**: [`docs/specs/developments/20260915075927_1757-resolved-codex-findings/2_1757-resolved-codex-findings_implementation-plan.md`](../../specs/developments/20260915075927_1757-resolved-codex-findings/2_1757-resolved-codex-findings_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Scope of this smoke test

This runbook covers the full `#1757` specification: applicability-aware
Codex review-thread counting (resolved, outdated, dismissed-review, and
non-live-head-commit threads excluded from blocker counts), removal of the
`unresolved_count=1` floor, the acknowledgement-only wait remap (exit `4`
instead of exit `2`), exit-`3` reason propagation, the `Reviewed commit`
marker well-formedness classifier, the finding-thread correlation contract,
the live-head evidence window, the cleared-findings wait, and all four new
fail-closed escalation reason codes
(`codex_current_verdict_malformed_revision_marker`,
`codex_finding_thread_correlation_missing`,
`codex_current_verdict_unrecognized`,
`evidence_unavailable_codex_thread_state`). See `codex-github.md`'s
"Resolved Codex findings and blocker counting (#1757)" section for the full
contract, including the two narrow disclosed scope notes (abbreviated-marker
ambiguity proof and the force-push occupancy guard) under "Known
Limitations" below.

---

## Prerequisites

Before running this smoke test:

- [ ] `gh` CLI is authenticated (`gh auth status`)
- [ ] `jq` is installed
- [ ] You have a GitHub repository with the Codex GitHub App connected and
      `codex-github` configured as a reviewer platform
- [ ] This feature's branch is checked out or merged (`codex-github-evidence-lib.sh`
      exists under `scripts/development-workflow/`)

---

## Test Data

| Item                    | Value                                                                     |
| ------------------------ | -------------------------------------------------------------------------- |
| Test PR                 | A PR where Codex has posted at least one inline review thread             |
| Bot login (Codex)       | `chatgpt-codex-connector[bot]` (REST) / `chatgpt-codex-connector` (GraphQL) |

---

## Smoke Test Steps

### Step 1: Resolved Codex thread does not block re-triggering (AC-1, AC-2)

1. Find or create a PR where Codex has posted an inline review thread with a
   blocking finding.
2. Resolve the thread in the GitHub UI ("Resolve conversation"), **without**
   pushing a new commit.
3. Run the reviewer loop against the PR:

   ```bash
   ./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name>
   ```

**Expected result**:

- The Codex phase does **not** report `RESULT=needs_fixes` /
  `REASON=existing_findings` from the resolved thread alone.
- Verify directly with the shared counting function:

  ```bash
  source scripts/development-workflow/codex-github-evidence-lib.sh
  codex_review_thread_evidence_counts "<owner>" "<repo>" <pr_number> \
    "chatgpt-codex-connector" strict
  ```

  Output is `<strict_unresolved>\t<cleared>\t<provisional_relaxed>` — confirm
  the resolved thread appears in the `cleared` count, not `strict_unresolved`.

### Step 2: Historical visible finding after a revision push waits, not blocks (AC-2, AC-8, AC-15 — primary regression)

1. On a PR with a Codex-reviewed thread, resolve the thread, then push a new
   commit (revision push) so the PR head changes.
2. Run the reviewer loop:

   ```bash
   ./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch_name>
   ```

**Expected result**:

- If the companion (`codex-github-reviewer.sh`) still reports `NEEDS_REVISION`
  from stale/visible evidence, the loop's post-companion strict recount
  confirms zero applicable unresolved threads and the Codex phase reports
  `RESULT=waiting_on_reviewer` / `REASON=codex-github-review-pending` —
  **not** `RESULT=needs_fixes`.
- Confirm a fresh Codex trigger is posted (or was already posted) for the new
  head, requesting a current-head verdict.

### Step 3: A dismissed review's thread does not count as a blocker

1. On a PR with an unresolved Codex inline thread, have a maintainer
   **dismiss** the review that owns that thread (GitHub review dismissal, not
   thread resolution).
2. Run:

   ```bash
   source scripts/development-workflow/codex-github-evidence-lib.sh
   codex_review_thread_evidence_counts "<owner>" "<repo>" <pr_number> \
     "chatgpt-codex-connector" strict
   ```

**Expected result**:

- The thread attached to the dismissed review does not appear in
  `strict_unresolved`.

### Step 4: A genuinely unresolved current-head thread still blocks (negative case)

1. On a PR with a Codex inline finding on the **current** head that is
   **not** resolved and **not** dismissed, run the reviewer loop.

**Expected result**:

- `RESULT=needs_fixes` / `REASON=existing_findings` (or
  `REASON=unresolved_review_threads` if reached via the post-companion
  recount), with `COMMENT_COUNT` reflecting the true unresolved count — the
  fix must not silently clear a genuine blocker.

### Step 5: Acknowledgement-only evidence waits, does not escalate (AC-10)

1. On a fresh PR, trigger Codex, and have it react with a thumbs-up on the
   trigger comment without ever submitting a review.
2. Run `codex-github-reviewer.sh` directly:

   ```bash
   ./scripts/development-workflow/codex-github-reviewer.sh <pr_number> <owner> <repo> \
     --poll-interval 5 --max-wait 10 --max-retriggers 0
   ```

**Expected result**:

- Exit code `4` (not `2`).
- Output contains `REASON=codex-github-reaction-without-review`.
- When run through `pr-review-loop.sh`, the Codex phase reports
  `RESULT=waiting_on_reviewer`, not `RESULT=escalate`.

### Step 6: Account-not-connected keeps its own reason (Operational Visibility)

1. Simulate (or find a real occurrence of) Codex responding with an
   account-not-connected refusal for the triggering identity.
2. Run the reviewer loop and inspect the Automated Reviewer Loop Summary /
   raw output.

**Expected result**:

- `REASON=codex-github-account-not-connected` is reported — **not**
  `REASON=codex-github-usage-limit`.

---

## Assertions Checklist

- [ ] AC-1: a resolved Codex review conversation is excluded from
      existing-finding and fallback blocker counts.
- [ ] AC-2: historical or re-anchored Codex comments alone cannot
      produce `needs_fixes` once the applicable conversation count is zero.
- [ ] AC-3: a fresh Codex root pull-request comment whose `Reviewed commit`
      marker is an unambiguous prefix of the live head, and whose body is
      clean, authorizes readiness.
- [ ] AC-4: a clean or finding verdict from an older revision is reported as
      stale (`codex-github-review-pending`), not readiness.
- [ ] AC-5: canonical terminal clean evidence in the final permitted cycle
      proceeds to readiness even at cap exhaustion; an exhausted allowance
      whose evaluation would otherwise require another cycle (including a
      cleared-findings retrigger) escalates `max_cycles_exceeded` instead.
- [ ] AC-7, AC-9: a current terminal finding with no stable review-thread
      identifier (a root-comment finding, or a review's own body finding)
      escalates `codex_finding_thread_correlation_missing`; a current
      terminal verdict matching neither an approved template nor the
      documented blocking markers escalates
      `codex_current_verdict_unrecognized`.
- [ ] AC-8: a cleared-findings verdict requests a fresh current-head
      review (`waiting_on_reviewer` / `codex-github-review-pending`) rather
      than dispatching a fixer.
- [ ] AC-10: acknowledgement-only evidence yields `waiting_on_reviewer` /
      `codex-github-reaction-without-review`, never an escalation.
- [ ] AC-11: a root comment carrying the `Reviewed commit` field with no
      value escalates `codex_current_verdict_malformed_revision_marker`; a
      root comment that never carries the field is acknowledgement evidence.
- [ ] AC-12: a well-formed marker naming the live head but missing the
      freshness boundary waits (`codex-github-review-pending`), it does not
      escalate malformed and it is not treated as clean.
- [ ] AC-13: a trigger-less live head's marker-pinned clean root comment is
      superseded by newer non-dismissed terminal evidence for the same head.
- [ ] AC-14: a syntactically unusable marker escalates
      `codex_current_verdict_malformed_revision_marker` when it falls inside
      the live head's evidence window; the bounded evidence query's own
      failure escalates `evidence_unavailable_codex_thread_state`.
- [ ] AC-15: automated regression coverage reproduces a resolved Codex finding
      that remains visible after a later revision and verifies
      `waiting_on_reviewer` / `codex-github-review-pending`
      (`codex_resolved_visible_finding_waits_after_revision_push_*` in
      `scripts/development-workflow/tests/test-pr-review-loop.sh`).
- [ ] Operational Visibility: an account-not-connected hard stop keeps its own
      exit-`3` reason instead of being reported as a usage limit.
- [ ] Negative case: a genuinely unresolved current-head Codex thread still
      produces `needs_fixes` with the true count.

---

## Seed Data Reference

No persistent seed data required. All scenarios use live GitHub PRs with the
Codex GitHub App connected, or the automated regression harness fixtures in
`scripts/development-workflow/tests/test-pr-review-loop.sh` (mocked `gh`).

---

## Troubleshooting

| Symptom                                                        | Likely cause                                                      | Fix                                                                                       |
| ---------------------------------------------------------------- | --------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| `codex_review_thread_evidence_counts` not found                | Running an old checkout without this item's changes                  | Check out this feature branch; confirm `scripts/development-workflow/codex-github-evidence-lib.sh` exists |
| Resolved thread still reported as a blocker                     | Thread's owning review commit does not match live `headRefOid`, and the commit could not be read | Fetch the review via `gh api repos/{owner}/{repo}/pulls/{pr}/reviews` and confirm the `commit_id` field is populated |
| Acknowledgement scenario still exits `2`                        | Running an old build of `codex-github-reviewer.sh`                    | Confirm `codex_return_reaction_without_review` exits `4` in the checked-out script            |

---

## Known Limitations

- This smoke test requires a live GitHub PR with real Codex GitHub App
  activity, or the mocked regression harness for offline verification.
- **Abbreviated-marker ambiguity proof is local-database-first, not
  unconditionally proven remotely.** `codex_marker_classify` proves
  ambiguity/non-existence whenever the local git object database or a
  reachable, matching GitHub REST `commits/{sha}` response can positively
  establish it; an abbreviated token that neither source can prove or
  disprove is trusted at its string classification rather than escalated.
  This is a disclosed, narrow scope note — see `codex-github.md`'s
  "Resolved Codex findings and blocker counting (#1757)" section for the
  full rationale.
- **The force-push/`head_ref_deleted`/`head_ref_restored` occupancy guard
  (SHA-reuse across a revert-and-return) is not implemented.** The
  freshness-boundary implementation itself (trigger-based, or PR
  `created_at` for a trigger-less head) is complete; only this narrower,
  rare residual is out of scope.

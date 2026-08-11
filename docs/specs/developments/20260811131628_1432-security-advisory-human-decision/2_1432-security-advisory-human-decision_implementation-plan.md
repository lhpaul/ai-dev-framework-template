# Security-Sensitive Advisory Human Decision Requirement — Implementation Plan

**Spec**: [1_1432-security-advisory-human-decision_specs.md](1_1432-security-advisory-human-decision_specs.md)
**Smoke test runbook**: [1432-security-advisory-human-decision.smoke-test.md](../../../testing/workflow/1432-security-advisory-human-decision.smoke-test.md)

---

## Summary

**Approach**: Introduce a narrow, conjunctive (content-category AND
file-location) classifier for advisory findings, a distinct
tracked-finding lifecycle persisted on the PR via a stable marker comment,
and a verified human-decision mechanism modeled directly on the existing
reviewer-access-bypass authorization pattern in
`run-epic-delegated-gate.sh`. The classifier and tracker are new, isolated
scripts; the delegated gate gets a new evidence field and reasons-cascade
branch (not a new short-circuit); the reviewer-loop protocol gets a new
pre-disposition classification sub-step that is deliberately kept **out**
of `pr-review-loop.sh` itself (the runner already fetches each finding's
full text and comment metadata when recording dispositions today, so no
change to the 7,000+-line reviewer-loop script's extraction internals is
required).

**Estimated complexity**: L

<!-- S: < 1 day | M: 1-3 days | L: 3+ days -->

**Rationale**: Two new scripts (`security-advisory-classifier.sh`,
`security-advisory-tracker.sh`) and two modified scripts
(`run-epic-delegated-gate.sh`, `run-epic-audit-trail.sh`) — four scripts
total — with new jq logic, a new PR-comment persistence format, a new
verified-decision comment protocol, and updates to five workflow documents
(91, 93, 95, `guardrails-enforcement.md`, `guardrails.md`) plus `REVIEW.md`.
Every new check requires a planted-violation proof in both directions
(fires / does not fire) across at least three new test files, following
`REVIEW.md`'s Verification Discipline rule. This is materially larger than a
single-file gate change.

**Dependencies**: None. All referenced machinery (`run-epic-delegated-gate.sh`
scope-optional `pr.inScope` handling from #1435, `run-epic-audit-trail.sh`'s
"Why Safe to Merge" section from #1436, `REVIEW.md`'s Verification Discipline
from #1443) is already merged to `develop`.

---

## Verification Log

| Check                                                              | Command / query                                                                                          | Result                                                                                                                                                    |
| -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Repo revision                                                       | `git rev-parse --short HEAD`                                                                              | `754db84` (branched from `origin/develop` after the #1432 spec merged as PR #1471)                                                                        |
| `ADVISORY_LABELS` is PR-Agent-only in current code                  | `grep -n "print_kv ADVISORY_LABELS" scripts/development-workflow/pr-review-loop.sh`                        | 4 call sites, all inside PR-Agent-specific comment-handling branches (no CodeRabbit call site exists)                                                     |
| Protocol 93's disposition flow is already platform-agnostic in text | `grep -n "advisory findings from any configured platform" docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` | Line 735 confirms the disposition-recording step is documented platform-agnostically even though only PR-Agent structurally emits `ADVISORY_LABELS` today |
| Candidate security-enforcement-surface scripts                       | `ls scripts/development-workflow \| grep -Ei "guard\|gate\|bypass\|authoriz"`                              | `checkpoint-resume-gate.sh`, `run-epic-delegated-gate.sh`, `run-nested-artifact-guard.sh`, `scope-residual-gate.sh`, `workflow-branch-push-guard.sh`, `worktree-cwd-guard.sh` |
| Additional branch/merge policy scripts not caught by keyword grep    | `ls scripts/development-workflow/validate-branch-reuse.sh scripts/development-workflow/validate-workflow-branch-name.sh scripts/development-workflow/run-epic-risk-classifier.sh scripts/development-workflow/run-epic-audit-trail.sh` | All four exist and enforce branch/merge/authorization policy or render reviewer-access-bypass audit content (`run-epic-audit-trail.sh`'s `render_reviewer_access_bypass`) |
| `.github/workflows/` file count                                     | `ls .github/workflows/`                                                                                    | 10 files: `auto-tag-release.yml`, `claude-code-review.yml`, `deploy.yml`, `e2e-regression.yml`, `markdown-lint.yml`, `pr-agent.yml`, `pr-policy.yml`, `shellcheck.yml`, `test-pr-review-loop.yml`, `update-tracker-on-merge.yml` |
| Existing delegated-gate test pattern (mocked `gh`, `run_test` helper) | `sed -n '1,80p' scripts/development-workflow/tests/test-run-epic-delegated-gate.sh`                        | Confirms the mocked-`gh`-binary + `run_test` pattern this plan's new tests must follow                                                                    |
| PR #1431 motivating finding's file                                   | Spec Overview, paragraph 1                                                                                | `scripts/development-workflow/workflow-branch-push-guard.sh` — already in the enforcement-surface candidate list above                                    |

---

## Cross-Cutting Operational Assumption Check

### Not applicable

**Result**: `Not applicable` — this plan does not depend on a shared
operational assumption (environment target, approved base branch, linked
cloud resource, artifact owner, or canonical configuration value) that
concurrent work in this batch could change. The base branch (`develop`), the
merged spec, and the referenced machinery (`run-epic-delegated-gate.sh`,
`run-epic-audit-trail.sh`, `REVIEW.md`) are all already-merged, stable facts
as of this plan's repo revision, not values another open PR in this batch is
actively changing.

---

## Workflow Decision-Gate Matrix (Implementation-Detail Delta)

The spec's own Workflow Decision-Gate Matrix (`1_1432-security-advisory-human-decision_specs.md`
§ "Workflow Decision-Gate Matrix") is authoritative for gate inputs, outcomes,
and next actions. This section records only the concrete implementation-detail
names the spec deliberately deferred (see "PR-Visible Deferral Notes"):

| Deferred item                                    | Concrete name selected by this plan                                                                                        |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| Label                                              | `security-advisory-decision-required`                                                                                       |
| Stop condition token                               | `security_sensitive_advisory_pending`                                                                                       |
| Gate 4/5 evidence array (distinct from `.advisories[]`) | `.securityAdvisories[]`                                                                                                 |
| Raw candidate decision-comment evidence array (mirrors `.authorizationEvents[]`) | `.securityAdvisoryDecisionEvents[]`                                                                    |
| PR tracking-comment marker (persists findings across pushes, BR7)  | `<!-- security-sensitive-advisory-findings -->`                                                                |
| Finding identifier format                          | `sec-<12-hex-char sha256 prefix of platform\|commentIdOrUrl\|matchedCategory>`                                              |
| Human decision-recording comment template (verified, mirrors the existing authorization-text exact-match pattern) | `I record a human decision for security-sensitive advisory finding <finding-id> on PR #<pr> at head <head-sha>: <accept|reject> — <rationale>` |
| Minimum author permission for a verified decision  | `write` (distinct from the `admin`-only bar used for `gh pr merge --admin` bypass authorization — a security-advisory accept/reject is not an admin merge override) |
| New classifier script                              | `scripts/development-workflow/security-advisory-classifier.sh`                                                            |
| New tracker/reconciliation script                  | `scripts/development-workflow/security-advisory-tracker.sh`                                                               |

This delta table plus the spec's matrix together satisfy REVIEW.md's "complex
workflow decision-gate matrix" requirement for both the spec and this plan.

---

## Layer-by-Layer Changes

> This is workflow tooling (bash scripts + jq + Markdown protocol docs), not
> an application with DB/API/UI layers. Layers below are named for this
> feature's actual surfaces instead of the generic template headings.

### New script: BR1 classifier (Stage 1)

- [ ] `scripts/development-workflow/security-advisory-classifier.sh` (NEW):
  - `classify --finding-text <text-or-@file> --file-path <path|""> --diff-hunk <text-or-@file|"">`
    subcommand. `--diff-hunk` is optional (defaults to `""`) and carries the
    review comment's diff-hunk context when the caller has it (inline PR
    review comments only — PR-level issue comments have no diff hunk and
    pass `""`).
  - Part A (content-category test): five ordered, first-match regexes for
    categories (a)–(e) from BR1. Case-insensitive, applied to the finding
    text.
  - Part B (file-location test): an explicit 10-entry enforcement-surface
    allowlist (exact path match, no prefix/glob matching except the single
    `.github/workflows/*.yml` case), plus a workflow-YAML special case that
    additionally requires the finding text **or** `--diff-hunk` (when
    non-empty) to mention a `permissions:` or `secrets:` YAML key — this
    covers a finding comment that discusses the risk without quoting the
    YAML itself, where the key only appears in the diff hunk CodeRabbit/
    PR-Agent attach to the comment.
  - Output: `{securitySensitive: bool, matchedCategory: "a".."e"|null,
    matchedFile: <path>|null}`.
  - Conjunctive AND: `securitySensitive` is `true` only when both parts
    match (BR1).

### New script: BR7 reconciliation + tracking-comment persistence (Stage 2)

- [ ] `scripts/development-workflow/security-advisory-tracker.sh` (NEW):
  - `reconcile --prior <tracking-comment-json|"none"> --current <fresh-classified-findings-json> --head-sha <sha> --decision-events <verified-decision-events-json|"none">`:
    implements BR7's re-evaluation — matches prior entries to fresh findings
    by `(matchedCategory, matchedFile)`; entries with no fresh match exit
    tracking; entries whose `headSha` differs from the current head reset to
    `pending` with audit reason `superseded_by_new_commit`; entries whose
    `headSha` matches the current head keep their existing status untouched,
    **except** where `--decision-events` (see below) resolves them. Never
    emits a `stale` status — only the four persisted values from the spec's
    Statuses table.
    - **Same-push collision handling**: when `--current` contains more than
      one fresh finding sharing the same `(matchedCategory, matchedFile)`
      key in a single call, `reconcile` does **not** collapse them into one
      entry. It pairs multiple prior/fresh entries sharing a key in stable
      order (first-listed prior entry to first-listed fresh entry for that
      key, and so on); if the prior and fresh counts for a shared key
      differ, unmatched fresh entries become new `pending` entries and
      unmatched prior entries follow the existing no-match "exits tracking"
      rule. Covered by an explicit fixture/test case (see Testing Strategy)
      proving two same-category-same-file findings on one push are tracked
      as two distinct entries, never silently merged or overwritten.
    - **Why `(matchedCategory, matchedFile)` and not the `sec-<hash>` finding
      id**: the finding id is partly derived from `commentIdOrUrl`
      (`sec-<12-hex sha256 of platform|commentIdOrUrl|matchedCategory>`). If
      a review platform posts a *new* comment id for what is conceptually
      the same finding on a later push, matching strictly by finding id
      across pushes would break BR7's cross-push reconciliation (the entry
      would look like a brand-new finding every push instead of continuing
      its existing status). `(matchedCategory, matchedFile)` is stable
      across pushes by construction and is therefore the primary
      cross-push key; the finding id remains useful only as the stable
      per-entry identifier within a single reconciled snapshot (used by
      `render`, `apply`, and `--decision-events` matching below), not as
      the cross-push matching key.
    - **`--decision-events`** (optional, default `"none"`): a JSON array of
      already-verified decision events, each
      `{findingId, decision: "human-accepted"|"human-rejected", decider,
      decidedAt, rationale}` — produced by
      `run-epic-delegated-gate.sh verify-security-advisory-decisions` (see
      Stage 3a), the same verification `github_verified_security_advisory_decisions`
      performs for Gate 5 evidence. For each reconciled entry that is
      currently `pending` at `--head-sha`, if a decision event's
      `findingId` matches that entry's finding id, `reconcile` transitions
      the entry to the event's `decision` value and persists `decider`,
      `decidedAt`, and `rationale` on the entry (the canonical
      resolved-entry schema — see below). Entries that are not `pending`,
      or with no matching decision event, are unaffected by this input.
      This is what allows a verified human decision to actually persist
      into the tracking-comment/audit record instead of only existing as an
      in-memory Gate 5 evaluation result. **Conflicting duplicate events**:
      `--decision-events` must contain at most one verified event per
      `findingId`. If two or more events share the same `findingId` at the
      current head SHA — regardless of whether their `decision`/`rationale`
      values agree or disagree — `reconcile` fails closed: it does not pick
      one arbitrarily or apply either, leaves the entry's status
      unconditionally `pending`, and emits a warning identifying the
      duplicate `findingId` and the conflicting comment references, so the
      ambiguity surfaces as a human-visible signal rather than becoming
      input-order-dependent. This is a hard rule regardless of upstream
      cause (e.g., two different humans posting conflicting decision
      comments) — `github_verified_security_advisory_decisions` passes
      through every verified event it finds; deduplication/conflict
      rejection is `reconcile`'s responsibility, not the gate's.
  - **Canonical resolved-entry schema**: every reconciled entry with status
    `fixed`, `human-accepted`, or `human-rejected` carries `id`, `category`,
    `matchedFile`, `status`, `headSha`, and, when resolved by a human
    decision, `decider`, `decidedAt`, and `rationale` (when resolved by a
    fix, `fixCommit` instead of `decider`/`decidedAt`/`rationale`). These
    exact field names are used consistently by `reconcile`'s output, the
    `.securityAdvisories[]` Gate 5 evidence shape (Stage 3), and
    `run-epic-audit-trail.sh`'s rendered audit section (Stage 3b) — there is
    one schema, not three independently-named ones.
  - `render --input <reconciled-json>`: renders the
    `<!-- security-sensitive-advisory-findings -->` marker-comment body (one
    row per tracked finding: id, category, file, status, decider/decidedAt/
    rationale when resolved by a human decision, fix commit when resolved by
    a fix).
  - `apply --input <reconciled-json> --pr <pr-number>`: upserts the marker
    comment via `gh api` (find-by-marker-then-PATCH-or-POST, same shape as
    `run-epic-audit-trail.sh`'s `apply-pr-disposition`). `apply` only
    upserts the marker comment; it does not add or remove the
    `security-advisory-decision-required` label (see Stage 4's Protocol 93
    update for which component performs that label mutation).

### `scripts/development-workflow/run-epic-delegated-gate.sh` (Stage 3 — gate wiring)

- [ ] Accept two new optional evidence fields: `.securityAdvisories[]`
  (reconciled tracker output — id, category, matchedFile, status, headSha,
  fixCommit, and, for human-resolved entries, decider, decidedAt, rationale —
  the canonical resolved-entry schema defined in Stage 2 above) and
  `.securityAdvisoryDecisionEvents[]` (raw candidate GitHub comment refs,
  same `{id, type}` shape `.authorizationEvents[]` already uses).
- [ ] New function `github_verified_security_advisory_decisions`, structurally
  parallel to the existing `github_verified_authorization_events` (same file,
  ~line 93): for each candidate event, fetch via `gh api`, verify
  `authorType == "User"`, `authorPermission` is `admin` or `write` (not
  `admin`-only), and the comment body exactly matches the finding's expected
  decision-comment text (finding id + PR + head SHA embedded, mirroring the
  existing `expected_authorization_text` exact-match approach at line 127).
  Output shape: one verified-decision object per resolved event —
  `{findingId, decision: "human-accepted"|"human-rejected", decider,
  decidedAt, rationale}` — matching the canonical resolved-entry schema so
  it can be fed directly into `security-advisory-tracker.sh reconcile
  --decision-events`.
- [ ] New subcommand `verify-security-advisory-decisions --input
  <evidence-json>` on `run-epic-delegated-gate.sh` that runs only
  `github_verified_security_advisory_decisions` against
  `.securityAdvisoryDecisionEvents[]` in the given evidence file and prints
  the resulting verified-decision array as JSON, without evaluating the
  rest of the gate. This lets Protocol 93's Stage-4 disposition step (which
  runs earlier than Gate 5, during the reviewer loop) reuse the exact same
  verification logic to compute decisions for tracker persistence, instead
  of duplicating the verification rules in a second place.
- [ ] New reasons-cascade branch inside the **existing** normal-evaluation
  `else` block (the block that already runs whenever `.pr.inScope` is absent
  or `true`, and is skipped only by the pre-existing `scope_value_false`
  short-circuit) — **not** a new short-circuit, satisfying BR8/BR9 with no
  additional scope-wiring: for every `.securityAdvisories[]` entry whose
  reconciled status is `pending` (after applying any verified decision from
  `.securityAdvisoryDecisionEvents[]` matching that entry's exact finding
  id/PR/head SHA), add reason
  `"security_sensitive_advisory_pending: finding <id> (<category> @ <file>) requires a fixed commit or a verified human accept/reject decision at head <sha>"`
  — never `merge_allowed` — regardless of `mode`, `policy.mayMerge`, or
  unrelated checkpoint state (BR5, AC5, AC6). `mergePermitted` already becomes
  `false` automatically once this reason is added (it is computed as
  `$count == 0`), but the `decision` **string** is not: the existing
  `decision`/`nextAction` `elif` chains (same file, ~line 792-793 and
  ~line 805-808) classify accumulated `$reasons` entries by testing them
  against fixed keyword regexes — `test("reviewer blocking|CI checks|
  unresolved blocking|advisories")` selects `"fix_required"`, and
  `test("authority|risk gate|needs-setup|Backlog|human_checkpoint_required|
  human-checkpoint|graduation_approval_required")` selects `"human_required"`
  — not a generic "any reason present → non-merge decision" mapping. The
  `security_sensitive_advisory_pending` reason text does not match either
  existing pattern, so without further wiring it would silently fall through
  to the final catch-all `"blocked"` branch instead of `"human_required"`.
  This step must therefore also extend both `elif` alternatives (decision at
  ~line 793 and nextAction at ~line 808) with an additional match on
  `security_sensitive_advisory_pending`, so the gate's `decision` field is
  verifiably `"human_required"` — not merely a non-`merge_allowed` value —
  matching what this bullet and the spec's Workflow Decision-Gate Matrix
  require, and so `nextAction` gives the human a specific instruction rather
  than the generic `"block until required state is available"` message.
- [ ] This new branch does not read, write, or call any of the existing
  `checkpoint_list` / `pending_checkpoints` / `checkpoint_reason` / `invalid_checkpoint_states`
  functions (BR4) — it is a fully independent code path using its own reason
  string and its own `security-advisory-decision-required` label reference.

### `scripts/development-workflow/run-epic-audit-trail.sh` (Stage 3 — audit rendering)

- [ ] New rendered section "Security-Sensitive Advisory Findings" in
  `render_pr_disposition`, inserted immediately after the existing "Advisory
  Decisions" section and visibly distinct from it (AC14): one row per
  `.securityAdvisories[]` entry — matched category, matched file, status,
  `decider`/`decidedAt`/`rationale` when resolved by a human decision, fix
  commit SHA when resolved by a fix (the same canonical resolved-entry
  schema field names used by `reconcile`'s output and Gate 5 evidence).
- [ ] New `validate_security_advisories()` / `warn_security_advisories()`
  functions parallel to the existing `validate_advisories()` /
  `warn_per_finding_advisories()`: a `human-accepted` or `human-rejected`
  entry without rationale is a hard `error_exit` (mirrors the existing
  "non-fixed advisory decisions require rationale" rule at line 346).
- [ ] Add `"securityAdvisories"` to the `PR_DISPOSITION_KNOWN_KEYS` array
  (lines 18-22) — this array is not merely documentation: it is consumed at
  runtime by `warn_unknown_pr_disposition_keys()` (line 388, called from both
  the `render-pr-disposition` and `apply-pr-disposition` command paths at
  lines 635 and 644) to WARN when a top-level input key is not recognized.
  This is exactly the class of bug issue #1436 introduced this array to catch
  (an unrecognized key silently dropped from the rendered comment); omitting
  `securityAdvisories` from this list would not silently drop the new
  section (the new `render_pr_disposition` jq explicitly consumes
  `.securityAdvisories`, per the bullet above), but it would print a
  misleading `WARN: unrecognized top-level PR disposition field(s) will not
  appear in the rendered audit comment: securityAdvisories` on every run that
  includes the field, contradicting the field actually being rendered. This
  field stays optional at the script's separate required-fields gate, since
  most PRs will legitimately have zero security-sensitive findings; only
  non-empty entries are validated by `validate_security_advisories()`.

### Protocol updates (Stage 4 — orchestration wiring, all docs-only)

- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`:
  new subsection "Security-sensitive advisory classification (mandatory
  before disposition)" inserted immediately before the existing "Advisory
  finding dispositions (post-clean)" section (~line 733). For every advisory
  finding about to receive a disposition (regardless of which platform or
  extraction mechanism produced it — `ADVISORY_LABELS` today is PR-Agent-only,
  but the existing disposition procedure at line 735 is already documented as
  applying "from any configured platform"), run
  `security-advisory-classifier.sh classify` against the finding text, its
  resolved file path, and (when available) its diff-hunk context, all fetched
  via `gh api` on the finding's linked comment (`path` and `diff_hunk` are
  present for inline PR review comments, absent for PR-level issue comments,
  in which case `--file-path ""` and `--diff-hunk ""` are passed and Part B
  always fails by construction). When `securitySensitive: true`:
  - The disposition menu at step 2 (line 745) is restricted to **Fixed** (cite
    commit) or **Pending Human Decision** — never **Accepted**, **Deferred**,
    or **Rejected** by the runner itself (BR5, AC4).
  - Fetch this PR's candidate decision comments (any comment matching the
    decision-recording template shape below, posted since the finding was
    first tracked) and run `run-epic-delegated-gate.sh
    verify-security-advisory-decisions` against them to compute any verified
    decisions (reusing the exact same verification `run-epic-delegated-gate.sh`
    applies for Gate 5, see Stage 3a).
  - Run `security-advisory-tracker.sh reconcile` against the PR's existing
    `<!-- security-sensitive-advisory-findings -->` comment (BR7) and the
    verified decisions just computed (`--decision-events`), so a verified
    human decision is actually persisted into the tracking record — not only
    evaluated in-memory later at Gate 5 — then `render` + `apply` to upsert
    the marker comment.
  - **Label mutation** (this step, not `security-advisory-tracker.sh
    apply`, which only upserts the marker comment): after `reconcile`, call
    `gh pr edit --add-label security-advisory-decision-required` when any
    tracked finding's reconciled status is `pending`, or `gh pr edit
    --remove-label security-advisory-decision-required` when zero tracked
    findings are `pending` (never touch `human-checkpoint-required`,
    BR4/AC7).
  - **Decision-template notification**: when this reconciliation newly
    produces (or re-produces, per BR7's `superseded_by_new_commit` case) at
    least one `pending` entry, upsert (find-by-marker-then-PATCH-or-POST, not
    duplicate) a separate PR comment marked
    `<!-- security-sensitive-advisory-decision-template -->` containing the
    exact expected decision-recording text (see Workflow Decision-Gate
    Matrix delta table) for every currently `pending` finding, so a human
    reviewer can copy it verbatim. This comment is removed (or left in place
    with a "no findings pending" note — implementer's choice, document
    whichever is chosen) once zero tracked findings are `pending`.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`:
  Step 7a/Gate-5-evidence-assembly guidance gets a short paragraph requiring
  `.securityAdvisories[]` / `.securityAdvisoryDecisionEvents[]` in the
  assembled evidence file identically for `/run-item`, `/run-items`, and
  `/run-epic` (AC8), cross-referencing the new stop condition and label.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`:
  - Step 8 item 5 (advisory handling, ~line 564): add the BR5 carve-out —
    security-sensitive findings never get an agent-recorded fix-or-accept
    disposition; only fix-or-pending.
  - Step 9 (audit trail): add security-sensitive finding coverage to the
    required audit content list.
  - Step 10 (final delegated merge gate): add an explicit bullet — "no
    `.securityAdvisories[]` entry remains `pending` after reconciliation
    at the current head SHA."
- [ ] `docs/workflow/development-workflow/guardrails-enforcement.md`:
  - Gate 4 (Delegated Review Gate, ~line 145): add the BR5 carve-out sentence.
  - Gate 5 (Delegated Merge Gate, ~line 163): add a new required-satisfied
    bullet for the new gate branch, and a note that it is independent of
    `mode`/`may_merge_pr`/checkpoint state (mirrors the existing reviewer-access
    exceptional-bypass callout style at line 202).
  - Section 4 (Named Stop Conditions table, ~line 271): add a new row —
    `security_sensitive_advisory_pending` | "A security-sensitive advisory
    finding (per the classifier in
    `scripts/development-workflow/security-advisory-classifier.sh`) lacks a
    fixed commit or a verified human accept/reject decision at the PR's
    current head SHA."
- [ ] `docs/workflow/development-workflow/guardrails.md`: add the same new row
  to the "Stop Conditions" table (~line 211, immediately after
  `human_checkpoint_required`) so the two documents' stop-condition lists stay
  in sync, matching the existing pattern where every `guardrails-enforcement.md`
  §4 row has a `guardrails.md` §"Stop Conditions" counterpart.
- [ ] `REVIEW.md`: add one bullet to the existing "Additional checks for PRs
  that add or modify guardrails enforcement behavior" block (~line 261):
  "**Security-advisory carve-out (BR5)**: confirm the changed code or
  documented behavior never lets a delegated agent record `human-accepted` /
  `human-rejected` for a security-sensitive advisory finding — only a fixed
  commit or a verified human decision resolves it."

---

## Testing Strategy

**Test types**: Bash unit tests (mocked `gh`, following the existing
`test-run-epic-delegated-gate.sh` pattern), fixture-based classifier tests,
manual/documentation-review smoke test (no UI — this is workflow tooling).

**Key scenarios to test**:

1. AC1/BR1: classifier returns `securitySensitive: false` when only one part
   matches (content-category match on a non-enforcement-surface file; or an
   enforcement-surface file with a non-security-category finding).
2. AC2: the three named non-security findings from this batch (PR-Agent's jq
   iteration claim on PR #1459, CodeRabbit's JSON key-type claim on PR #1460,
   PR-Agent's quote-escaping claim on PR #1467) — reconstructed as fixture
   finding text against their actual (non-enforcement-surface) files — return
   `securitySensitive: false`.
3. AC3: fixture findings shaped like the PR #1431 findings, targeted at
   `scripts/development-workflow/workflow-branch-push-guard.sh`, return
   `securitySensitive: true` with the stated `matchedCategory`:
   - Force semantics without a lease, e.g. `"raw git push --force is used
     here without a safety lease"` — expected `matchedCategory: "c"`.
   - Permissive remote URL parsing, e.g. `"the remote URL parsing here is
     too permissive and could let a spoofed remote bypass the push guard's
     validation check"` — expected `matchedCategory: "e"` (matches the
     category (e) `(bypass|weaken|disable|circumvent).*(guard|gate|
     policy|check)` pattern via "bypass ... check"; this fixture text is
     load-bearing — the finding must actually contain a bypass/weaken/
     disable/circumvent keyword co-occurring with a guard/gate/policy/check
     keyword, not just the phrase "permissive ... URL parsing" on its own,
     which matches no category regex as written).
4. AC4/AC5/BR5: gate test — a PR with one `pending` `.securityAdvisories[]`
   entry, `policy.mayMerge: true`, `mode: delegated`, and every other gate
   condition green still returns `decision == "human_required"` (not merely
   `!= "merge_allowed"` — the test must assert the exact string, since the
   gate's `elif` classification chain requires an explicit keyword match to
   produce `"human_required"` rather than falling through to the generic
   `"blocked"` catch-all) and includes the `security_sensitive_advisory_pending`
   reason.
5. AC6: gate test — the same PR additionally carrying a `waived`
   `human-checkpoint-required` checkpoint for an unrelated item/stage still
   blocks on the security-sensitive finding (proves the two mechanisms are
   independent, BR4).
6. AC7: assert the new label string and stop-condition string never equal or
   contain `human-checkpoint-required` / `human_checkpoint_required` (a
   literal string-inequality assertion in the test file).
7. AC8/AC9: gate test matrix — `.pr.inScope` absent, `true`, and `false`,
   each with one `pending` `.securityAdvisories[]` entry; absent/`true` still
   block, `false` short-circuits to `not_applicable` exactly as the existing
   scope short-circuit already does for every other reason (no new behavior
   needed here — the test proves the *placement* inside the normal cascade is
   correct). **Scope of this test vs. AC8's "identically for `/run-item`,
   `/run-items`, and `/run-epic`" wording**: `run-epic-delegated-gate.sh` is
   invocation-surface-agnostic by construction — it evaluates whatever
   evidence JSON it is given, regardless of which surface assembled it — so
   this `.pr.inScope` matrix fully proves the *gate's* AC8/AC9 behavior. What
   it does not prove is that Protocol 91's and Protocol 95's documentation
   actually instruct all three surfaces to assemble the same
   `.securityAdvisories[]` / `.securityAdvisoryDecisionEvents[]` shape; that
   is a documentation-consistency concern, not a fixture-test concern (this
   repository has no existing pattern for testing "evidence-assembly
   equivalence across invocation surfaces" as an automated bash fixture),
   and is instead covered by Stage 5's cross-section consistency pass and
   the smoke test's Step 10 (see below).
8. AC10/AC11/BR6: `github_verified_security_advisory_decisions` tests —
   correct author + correct permission (`write` and `admin` both pass;
   `read`/`triage` do not) + exact finding/PR/head-SHA text match resolves;
   wrong head SHA, wrong finding id, unrelated comment body, or a `Bot`-typed
   author does not resolve.
9. AC12/AC13/BR7: tracker `reconcile` tests — same head SHA keeps status;
   new head SHA with the finding still matching resets `fixed` /
   `human-accepted` / `human-rejected` / `pending` all to `pending` with
   `superseded_by_new_commit`; new head SHA with the finding no longer
   matching (via a fresh `classify` call showing no match) drops the entry
   from the reconciled output entirely, never carrying forward `pending`;
   `--decision-events` transitions a matching `pending` entry to
   `human-accepted`/`human-rejected` with `decider`/`decidedAt`/`rationale`
   persisted, and leaves non-`pending` entries and non-matching events
   unaffected; two fresh findings sharing the same `(matchedCategory,
   matchedFile)` key in one `--current` input are reconciled as two distinct
   entries (stable-order pairing), never silently merged or overwriting one
   another's status; two `--decision-events` entries sharing the same
   `findingId` at the current head SHA — whether they agree
   (`human-accepted` + `human-accepted`) or conflict
   (`human-accepted` + `human-rejected`) — leave that entry `pending`
   (fail-closed) rather than applying either one, and `reconcile` emits a
   duplicate-`findingId` warning identifying both source comment
   references.
10. AC14: `render_pr_disposition` output test — the "Security-Sensitive
    Advisory Findings" heading text never equals or is nested under the
    existing "Advisory Decisions" heading; both are present in the same
    output when both `.advisories[]` and `.securityAdvisories[]` are
    non-empty.

**Smoke test runbook**:
`docs/testing/workflow/1432-security-advisory-human-decision.smoke-test.md`

**Regression suite**: This repository has no committed E2E/functional suite
(`docs/testing/README.md` Section 2 is unfilled; CI's E2E job is the
placeholder). REVIEW.md's "E2E Fixture Contract" rule is therefore not
applicable — no fixture/seed extension is required in the implementation PR.

### Parser-risk addendum (classifier does regex-based content scanning)

The BR1 classifier applies ordered regex matching over free-text advisory
finding content — this is parser-risk per Protocol 02 Step 3's "regex-heavy
scanning ... over ... structured text" signal.

- **Edge-case enumeration** (concrete inputs, mapped to
  `scripts/development-workflow/tests/test-security-advisory-classifier.sh`):
  - Case variance: `"raw git push --FORCE without a lease"` still matches
    category (c).
  - Negative lookalike, category: `"force a component re-render"` does not
    match category (c) (no git/version-control context).
  - Negative lookalike, category (c) safety-lease exclusion: `"the caller
    uses git push --force-with-lease, which is safe"` does **not** match
    category (c) — the safety-lease phrase must suppress the match even
    though the force-push keyword is present, matching BR1c's explicit
    "without a safety lease" qualifier. This is the case the earlier draft of
    this addendum omitted; see the `classify()` sample above for the
    positive-match-AND-NOT-safe-phrase implementation this test proves.
  - Negative lookalike, category (c) safety-lease exclusion, unhyphenated
    phrasing: `"force push with a safety lease"` (no `force-with-lease`
    hyphenated token) also does **not** match category (c) — the NOT-check
    additionally excludes any `with (a|an|the)? (safety )?lease` phrasing, not
    only the literal `force-with-lease`/`--force-with-lease` tokens, so a
    finding phrased without the hyphenated flag name is still correctly
    recognized as describing safe, lease-protected usage. Conversely, the
    positive fixture `"raw git push --force is used here without a safety
    lease"` still matches category (c): "without" is not "with " (no space
    directly follows the substring "with" inside "without"), so the NOT-check
    does not fire on the positive case.
  - Negative lookalike, category: `"the retry count is a secret constant we
    tune later"` does not match category (b) (no credential/token/exposure
    context — the pattern requires "secret"/"credential"/"token"/"password"
    co-occurring with an exposure/logging/handling verb, not the bare word
    "secret").
  - Multiple category keywords on one line: a finding containing both
    "force push" and "secret" text matches the first category tested in the
    classifier's fixed evaluation order (a→b→c→d→e) — the test asserts
    `matchedCategory == "b"` regardless of which keyword phrase appears first
    in the finding text, because category (b)'s exposure-verb pattern is
    tested before category (c)'s force-push pattern in the ordered `elif`
    chain (see Code Samples). This is a fixed category-priority override, not
    text-position-based matching; documenting this precisely means
    implementers do not have to guess whether ordering follows text position
    or category priority — it is category priority, unconditionally.
  - Overlapping categories (a) vs (e): "this change bypasses the auth check"
    — asserted to match category (a) specifically (auth bypass takes
    precedence when both an auth noun and "bypass"/"skip"/"spoof" co-occur,
    **in either text order**), not the more generic category (e). This
    requires category (a)'s regex to match both "auth ... bypass" and
    "bypass ... auth" orderings: a single-direction
    `auth(entication|orization)?.*(bypass|skip|spoof)` pattern does **not**
    match this example (`bypass` appears before `auth` in the text) and would
    incorrectly fall through to category (e)'s
    `(bypass|weaken|disable|circumvent).*(guard|gate|policy|check)` pattern
    instead (since "bypasses ... check" does match category (e) as an
    unrelated substring). The Code Samples illustrative regex below is
    corrected to match both orderings for this reason.
  - File-location exact-match boundary: a finding against
    `scripts/development-workflow/run-epic-risk-classifier-notes.sh` (a
    lookalike, non-enforcement-surface file) does not match Part B even
    though `run-epic-risk-classifier.sh` is on the allowlist — proves exact
    path match, not prefix match.
  - `.github/workflows/*.yml` special case: a finding about
    `.github/workflows/deploy.yml`'s `on: push` trigger (no
    `permissions:`/`secrets:` context) does not match Part B; a finding about
    the same file's `permissions: contents: write` block does.
  - `.github/workflows/*.yml` special case, diff-hunk-only match: a finding
    whose `--finding-text` discusses the risk in prose only (e.g. "this job
    grants broader access than it needs") and does **not** itself mention
    `permissions:`/`secrets:`, but whose `--diff-hunk` contains a
    `permissions: contents: write` line, matches Part B — proving the
    `--finding-text`-OR-`--diff-hunk` check works when the YAML key appears
    only in the diff-hunk context, not the finding text itself.
  - Empty/absent file path (PR-level issue comment, no inline `path`): Part B
    always fails by construction — asserted directly, not inferred.
  - Multiline finding text: a finding text with an embedded newline splitting
    a category regex's two halves across separate lines, e.g. `"this finding
    describes an auth\nbypass on the enforcement surface"` (category (a)'s
    auth/bypass halves on different lines), still matches category (a) — this
    proves `match_re`'s newline-to-space normalization (see `classify()`
    sample above), not a raw `grep -qiE` call, which evaluates a multiline
    string one line at a time and would otherwise miss this exact case.
- **Unit test mapping**: `test-security-advisory-classifier.sh` — one
  `run_test` case per bullet above, plus the AC1/AC2/AC3 fixture cases from
  "Key scenarios to test" items 1–3.
- **Suppression semantics**: not applicable — this feature has no
  inline/directive suppression mechanism (a security-sensitive finding is
  resolved only via a fix commit or a verified human decision comment, never
  a suppression directive in code).

---

## Seed Data

**None.** This is workflow tooling (bash scripts + Markdown protocol docs);
there is no application database or seed-data layer for this repository to
extend.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
      — new "Security-sensitive advisory classification" subsection (see
      Layer-by-Layer Changes, Stage 4).
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      — Gate-5-evidence-assembly paragraph.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      — Step 8/9/10 updates.
- [ ] `docs/workflow/development-workflow/guardrails-enforcement.md` — Gate 4,
      Gate 5, and § 4 Named Stop Conditions table updates.
- [ ] `docs/workflow/development-workflow/guardrails.md` — Stop Conditions
      table row.
- [ ] `REVIEW.md` — new bullet under the guardrails-enforcement-behavior
      "Additional checks" block.
- [ ] `CHANGELOG.md` — new `[Unreleased]` → `### Added` entry (see
      Implementation Order, Stage 7, for the exact entry text). Listed here
      for completeness with Stage 7; this is not "no other documentation
      work" (see Stage 6 below).
- [ ] `AGENTS.md` — no change needed. This feature does not add a new
      top-level workflow command, stage, or agent; it extends the existing
      Step 7/7a/Gate-4/Gate-5 machinery that `AGENTS.md` already references
      indirectly via `guardrails-enforcement.md`.

---

## Risks & Mitigations

| Risk                                                                                       | Likelihood | Impact | Mitigation                                                                                                                                                                                     |
| -------------------------------------------------------------------------------------------- | ---------- | ------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enforcement-surface allowlist goes stale as new guard/gate scripts are added later          | Medium     | Low    | The allowlist is a small, explicit, commented array (not auto-discovered) — out of scope for this PR to auto-maintain; a future issue can add auto-discovery if the list proves to lag in practice. |
| `security-advisory-tracker.sh reconcile` mis-matches findings across a push that renames/moves the flagged file | Low        | Medium | `reconcile` matches on `(matchedCategory, matchedFile)`; a renamed file legitimately produces a "no longer matches" exit for the old path and a fresh `pending` entry for the new one — this is the BR7-correct outcome, not a bug, and is covered by an explicit reconcile test case. |
| Human decision-comment template is easy to mistype, silently failing verification            | Medium     | Low    | Exact-text-match failure is fail-closed (finding stays `pending`, not silently resolved) — mirrors the existing authorization-text pattern's already-accepted UX tradeoff; the runner posts the exact expected template text in a dedicated `<!-- security-sensitive-advisory-decision-template -->` notification comment for the human to copy (see Stage 4's Protocol 93 update, "Decision-template notification" bullet, for the concrete upsert/update behavior). |
| New Gate 5 branch could be mis-ordered relative to the existing scope short-circuit, silently reintroducing a `pr.inScope`-false no-op | Low | High | Implementation Order Step 6 requires an explicit test proving the branch lives inside the normal `else` cascade (AC8/AC9 test matrix), not a new top-level short-circuit. |

---

## Code Samples

> Illustrative only — adapt during implementation.

```bash
# Illustrative — adapt during implementation.
# scripts/development-workflow/security-advisory-classifier.sh classify (shape)

# match_re distinguishes "no match" (grep exit 1) from a genuine command
# error (grep exit >=2, e.g. a malformed pattern or an I/O failure) so a
# `grep` failure is never silently treated as a normal non-match. It also
# normalizes embedded newlines to spaces before matching: `grep -qiE`
# evaluates a multiline string one line at a time, so a category regex whose
# two halves land on different lines (a real shape for Markdown-formatted PR
# review-comment bodies) would otherwise never match even though the finding
# text, read as prose, clearly describes the category. Normalizing here — not
# in each call site — keeps every category test (a)-(e) multiline-safe by
# construction.
match_re() {
  local text="$1" pattern="$2" status normalized
  normalized="${text//$'\n'/ }"
  printf '%s' "$normalized" | grep -qiE "$pattern"
  status=$?
  if (( status >= 2 )); then
    echo "classify: internal error: grep failed evaluating pattern" >&2
    exit 1
  fi
  return "$status"
}

classify() {
  local finding_text="$1" file_path="$2"
  local matched_category=""
  if [[ -z "$finding_text" ]]; then
    echo "classify: --finding-text is required and must be non-empty" >&2
    return 2
  fi
  # file_path may legitimately be "" (PR-level issue comments have no
  # inline path) — Part B always fails by construction in that case, so no
  # validation is required here beyond accepting an empty string.
  # Category (a) matches "auth ... bypass" and "bypass ... auth" order-
  # independently (see Parser-risk addendum, "Overlapping categories (a) vs
  # (e)") so it is tested and matched before the more generic category (e)
  # bypass/guard pattern below, regardless of which token appears first.
  if match_re "$finding_text" 'auth(entication|orization)?.*(bypass|skip|spoof)|(bypass|skip|spoof).*auth(entication|orization)?'; then
    matched_category="a"
  elif match_re "$finding_text" '(secret|credential|token|password).*(expos|log|leak|plaintext)'; then
    matched_category="b"
  # Category (c) requires BOTH an unsafe force/history-rewrite keyword AND the
  # absence of a "force-with-lease" (or equivalent safety-lease) phrase — BR1c
  # is explicitly "a force operation without a safety lease", so a finding
  # that itself states the operation is lease-protected must NOT match. POSIX
  # ERE has no negative lookahead, so this is a positive-match-AND-NOT-safe-
  # phrase check across two `match_re` calls, not a single regex.
  elif match_re "$finding_text" '(force[- ]?push|--force\b|hard reset|history rewrite)' \
    && ! match_re "$finding_text" '(force[- ]?with[- ]?lease|--force-with-lease|with (a |an |the )?(safety[- ]?)?lease)'; then
    matched_category="c"
  elif match_re "$finding_text" '(injection|unsanitized|eval\(|path.traversal)'; then
    matched_category="d"
  elif match_re "$finding_text" '(bypass|weaken|disable|circumvent).*(guard|gate|policy|check)'; then
    matched_category="e"
  fi
  # ... Part B (enforcement-surface allowlist + workflow-yml special case) ...
}
```

```text
# Illustrative — adapt during implementation.
# Expected human decision-recording comment template (BR6/AC11):
I record a human decision for security-sensitive advisory finding sec-4f2a9c1b0d3e on PR #1481 at head 7a1c9e2f4b6d8a0c1e3f5a7b9c1d3e5f7a9b1c3d: accept — force-with-lease already enforced one layer up in the caller; this direct git call is only reachable in the guarded fallback path.
```

---

## Implementation Order

1. **Stage 1 — Classifier core (no wiring, fully self-contained and testable)**:
   Create `scripts/development-workflow/security-advisory-classifier.sh` with
   the `classify` subcommand, the ordered category-A regex set, the 10-entry
   Part B enforcement-surface allowlist, and the `.github/workflows/*.yml`
   permissions/secrets special case. Create
   `scripts/development-workflow/tests/test-security-advisory-classifier.sh`
   covering every case in the "Key scenarios to test" items 1–3 and the
   Parser-risk addendum edge cases. Run the new test file and confirm every
   case passes, including the negative-lookalike and exact-path-match cases
   (planted-violation proof: show a case failing before the corresponding
   regex/allowlist entry exists, then passing after).
2. **Stage 2 — Tracker/reconciliation + persistence (depends on Stage 1's
   classify output shape)**: Create
   `scripts/development-workflow/security-advisory-tracker.sh` with
   `reconcile`, `render`, and `apply` subcommands. Create
   `scripts/development-workflow/tests/test-security-advisory-tracker.sh`
   covering AC12/AC13/BR7 scenarios (same-head idempotence, cross-head
   invalidation for all four prior statuses, exit-tracking when no longer
   matching). No `gh` mutation in `reconcile`/`render` — only `apply` calls
   `gh api`; mock `gh` in the `apply` tests following the existing
   `test-run-epic-delegated-gate.sh` pattern.
3. **Stage 3a — Gate wiring (depends on Stage 1+2 output shapes)**: Modify
   `scripts/development-workflow/run-epic-delegated-gate.sh`: add
   `github_verified_security_advisory_decisions`, the new evidence fields,
   the new reasons-cascade branch inside the existing normal-cascade `else`
   block, **and** the additional `elif` alternatives on the existing
   `decision`/`nextAction` classification chains (~line 793 / ~line 808) that
   recognize `security_sensitive_advisory_pending` and select
   `"human_required"` — this last part is required precisely because those
   chains classify by fixed keyword-regex match, not by "any reason present,"
   as detailed in the Layer-by-Layer Changes bullet above. Extend
   `scripts/development-workflow/tests/test-run-epic-delegated-gate.sh` with
   the AC4/AC5/AC6/AC8/AC9/AC10/AC11 test cases from "Key scenarios to test."
   Planted-violation proof: show `decision: "merge_allowed"` before the new
   branch exists (with a fixture `pending` `.securityAdvisories[]` entry and
   every other gate condition green), and `decision: "human_required"`
   (asserted as the exact string, not merely non-`merge_allowed`) with the
   `security_sensitive_advisory_pending` reason after both the reasons-cascade
   branch and the classification-chain `elif` alternatives exist.
4. **Stage 3b — Audit rendering (depends on Stage 3a's evidence shape)**:
   Modify `scripts/development-workflow/run-epic-audit-trail.sh`: add the
   "Security-Sensitive Advisory Findings" section, `validate_security_advisories()`,
   and `warn_security_advisories()`. Extend
   `scripts/development-workflow/tests/test-run-epic-audit-trail.sh` with the
   AC10/AC14 cases (section distinctness, rationale-required validation).
5. **Stage 4 — Protocol and guardrails documentation (depends on Stage 1–3
   concrete names)**: Update `93-automated-reviewer-loop-protocol.md`,
   `91-orchestrate-work-protocol.md`, `95-run-epic-protocol.md`,
   `guardrails-enforcement.md`, `guardrails.md`, and `REVIEW.md` per
   Layer-by-Layer Changes above. Run the full documented lint surface (per
   this repo's `CLAUDE.md` "Common Commands"), not only the workflow-protocol
   glob, and fix any reported issues:
   - `npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" "REVIEW.md" "docs/specs/developments/20260811131628_1432-security-advisory-human-decision/**/*.md" "docs/testing/workflow/1432-security-advisory-human-decision.smoke-test.md"`
     (standard rules — this development's own plan/smoke-test files, plus
     the six modified protocol/guardrails docs and `REVIEW.md`).
   - `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`
     (heuristic rules — GLOB001/COUNT001).
   - `shellcheck scripts/development-workflow/security-advisory-classifier.sh scripts/development-workflow/security-advisory-tracker.sh scripts/development-workflow/run-epic-delegated-gate.sh scripts/development-workflow/run-epic-audit-trail.sh`
     (the two new scripts and the two modified scripts).
   - `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`
     (covers any new executable shell guidance blocks this feature's doc
     changes introduce, e.g. in the Protocol 93 subsection).
6. **Stage 5 — Cross-section consistency pass and full test run**: Re-read
   every occurrence of the label, stop-condition token, evidence field names,
   and the decision-comment template across all six modified/created
   documents and confirm identical spelling everywhere (this plan's
   Workflow Decision-Gate Matrix delta table is the source of truth).
   Explicitly confirm the new `91-orchestrate-work-protocol.md` and
   `95-run-epic-protocol.md` paragraphs describe the exact same
   `.securityAdvisories[]` / `.securityAdvisoryDecisionEvents[]` evidence
   fields with identical wording, so the AC8 "identically for `/run-item`,
   `/run-items`, and `/run-epic`" requirement is verifiably satisfied at the
   documentation level (the gate-side fixture tests in Testing Strategy item
   7 only prove the gate is surface-agnostic; this step proves the
   documentation instructs every surface to feed it the same evidence). Run
   all new and existing `scripts/development-workflow/tests/test-*.sh` files
   touched by this change and confirm they pass together, not only
   individually (guards against cross-test global state leakage). Re-run the
   full lint surface from Stage 4 after any doc edits made during this pass.
7. **Stage 6 — Update project docs**: `AGENTS.md` needs no change (see
   Documentation Updates above); `CHANGELOG.md` is updated in Stage 7 below,
   not skipped — Stage 6 covers only the remaining "project docs" category
   (`AGENTS.md`), which has no required change for this feature.
8. **Stage 7 — CHANGELOG**: update `CHANGELOG.md` under `[Unreleased]` →
   `### Added` with:

   ```markdown
   - **Require human decision for security-sensitive advisory findings**
     (#1432): a narrow, conjunctive (content-category AND
     file-location) classifier flags advisory findings that describe an
     auth bypass, secret/credential exposure, an unsafe git operation, an
     injection risk, or a workflow-guardrail bypass on the workflow's own
     enforcement-surface files. A security-sensitive finding blocks
     delegated merge (new `security_sensitive_advisory_pending` stop
     condition, `security-advisory-decision-required` label) until it is
     fixed with a cited commit or resolved by a verified human decision —
     never by the delegated agent itself, and never by an unrelated
     checkpoint waiver. Re-evaluated against the exact head SHA on every
     push, matching the existing reviewer-access-bypass authorization
     pattern. Applies identically to `/run-item`, `/run-items`, and
     `/run-epic`.
   ```

**Note on staging**: Stages 1–2 are independently mergeable-quality units
(pure functions over JSON, no live `gh` mutation in the hot path) and should
be committed as separate checkpoints even within a single implementation PR,
per the mandatory incremental-commit discipline. Stage 3 depends on Stage 1–2
output shapes being final; Stage 4 depends on Stage 3's concrete field/label
names being final. Do **not** parallelize Stage 4 ahead of Stage 3 — the
spec's own PR-Visible Deferral Notes make the exact names a Stage 3
implementation decision, and documentation written against a guessed name
before Stage 3 lands risks exactly the cross-section-inconsistency failure
mode REVIEW.md's Plan/Code checklists flag as blocking.

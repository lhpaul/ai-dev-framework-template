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

**Rationale**: Three new/modified scripts with new jq logic, a new PR-comment
persistence format, a new verified-decision comment protocol, and updates to
five workflow documents (91, 93, 95, `guardrails-enforcement.md`,
`guardrails.md`) plus `REVIEW.md`. Every new check requires a planted-violation
proof in both directions (fires / does not fire) across at least three new
test files, following `REVIEW.md`'s Verification Discipline rule. This is
materially larger than a single-file gate change.

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
  - `classify --finding-text <text-or-@file> --file-path <path|"">` subcommand.
  - Part A (content-category test): five ordered, first-match regexes for
    categories (a)–(e) from BR1. Case-insensitive, applied to the finding
    text.
  - Part B (file-location test): an explicit 10-entry enforcement-surface
    allowlist (exact path match, no prefix/glob matching except the single
    `.github/workflows/*.yml` case), plus a workflow-YAML special case that
    additionally requires the finding text or diff-hunk context to mention a
    `permissions:` or `secrets:` YAML key.
  - Output: `{securitySensitive: bool, matchedCategory: "a".."e"|null,
    matchedFile: <path>|null}`.
  - Conjunctive AND: `securitySensitive` is `true` only when both parts
    match (BR1).

### New script: BR7 reconciliation + tracking-comment persistence (Stage 2)

- [ ] `scripts/development-workflow/security-advisory-tracker.sh` (NEW):
  - `reconcile --prior <tracking-comment-json|"none"> --current <fresh-classified-findings-json> --head-sha <sha>`:
    implements BR7's re-evaluation — matches prior entries to fresh findings
    by `(matchedCategory, matchedFile)`; entries with no fresh match exit
    tracking; entries whose `headSha` differs from the current head reset to
    `pending` with audit reason `superseded_by_new_commit`; entries whose
    `headSha` matches the current head keep their existing status untouched.
    Never emits a `stale` status — only the four persisted values from the
    spec's Statuses table.
  - `render --input <reconciled-json>`: renders the
    `<!-- security-sensitive-advisory-findings -->` marker-comment body (one
    row per tracked finding: id, category, file, status, decider/rationale
    when resolved).
  - `apply --input <reconciled-json> --pr <pr-number>`: upserts the marker
    comment via `gh api` (find-by-marker-then-PATCH-or-POST, same shape as
    `run-epic-audit-trail.sh`'s `apply-pr-disposition`).

### `scripts/development-workflow/run-epic-delegated-gate.sh` (Stage 3 — gate wiring)

- [ ] Accept two new optional evidence fields: `.securityAdvisories[]`
  (reconciled tracker output — id, category, matchedFile, status, headSha,
  fixCommit) and `.securityAdvisoryDecisionEvents[]` (raw candidate GitHub
  comment refs, same `{id, type}` shape `.authorizationEvents[]` already
  uses).
- [ ] New function `github_verified_security_advisory_decisions`, structurally
  parallel to the existing `github_verified_authorization_events` (same file,
  ~line 93): for each candidate event, fetch via `gh api`, verify
  `authorType == "User"`, `authorPermission` is `admin` or `write` (not
  `admin`-only), and the comment body exactly matches the finding's expected
  decision-comment text (finding id + PR + head SHA embedded, mirroring the
  existing `expected_authorization_text` exact-match approach at line 127).
- [ ] New reasons-cascade branch inside the **existing** normal-evaluation
  `else` block (the block that already runs whenever `.pr.inScope` is absent
  or `true`, and is skipped only by the pre-existing `scope_value_false`
  short-circuit) — **not** a new short-circuit, satisfying BR8/BR9 with no
  additional scope-wiring: for every `.securityAdvisories[]` entry whose
  reconciled status is `pending` (after applying any verified decision from
  `.securityAdvisoryDecisionEvents[]` matching that entry's exact finding
  id/PR/head SHA), add reason
  `"security_sensitive_advisory_pending: finding <id> (<category> @ <file>) requires a fixed commit or a verified human accept/reject decision at head <sha>"`
  and force `decision: "human_required"` — never `merge_allowed` — regardless
  of `mode`, `policy.mayMerge`, or unrelated checkpoint state (BR5, AC5, AC6).
- [ ] This new branch does not read, write, or call any of the existing
  `checkpoint_list` / `pending_checkpoints` / `checkpoint_reason` / `invalid_checkpoint_states`
  functions (BR4) — it is a fully independent code path using its own reason
  string and its own `security-advisory-decision-required` label reference.

### `scripts/development-workflow/run-epic-audit-trail.sh` (Stage 3 — audit rendering)

- [ ] New rendered section "Security-Sensitive Advisory Findings" in
  `render_pr_disposition`, inserted immediately after the existing "Advisory
  Decisions" section and visibly distinct from it (AC14): one row per
  `.securityAdvisories[]` entry — matched category, matched file, status,
  decider/timestamp/rationale when resolved, fix commit SHA when fixed.
- [ ] New `validate_security_advisories()` / `warn_security_advisories()`
  functions parallel to the existing `validate_advisories()` /
  `warn_per_finding_advisories()`: a `human-accepted` or `human-rejected`
  entry without rationale is a hard `error_exit` (mirrors the existing
  "non-fixed advisory decisions require rationale" rule at line 346).
- [ ] Add `securityAdvisories` to the required-fields documentation comment
  near line 20 (informational only — this field stays optional at the
  script's required-fields gate itself, since most PRs will legitimately have
  zero security-sensitive findings; only non-empty entries are validated).

### Protocol updates (Stage 4 — orchestration wiring, all docs-only)

- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`:
  new subsection "Security-sensitive advisory classification (mandatory
  before disposition)" inserted immediately before the existing "Advisory
  finding dispositions (post-clean)" section (~line 733). For every advisory
  finding about to receive a disposition (regardless of which platform or
  extraction mechanism produced it — `ADVISORY_LABELS` today is PR-Agent-only,
  but the existing disposition procedure at line 735 is already documented as
  applying "from any configured platform"), run
  `security-advisory-classifier.sh classify` against the finding text and its
  resolved file path (fetched via `gh api` on the finding's linked comment;
  `path` is present for inline PR review comments, absent for PR-level issue
  comments, in which case `--file-path ""` is passed and Part B always fails
  by construction). When `securitySensitive: true`:
  - The disposition menu at step 2 (line 745) is restricted to **Fixed** (cite
    commit) or **Pending Human Decision** — never **Accepted**, **Deferred**,
    or **Rejected** by the runner itself (BR5, AC4).
  - Run `security-advisory-tracker.sh reconcile` against the PR's existing
    `<!-- security-sensitive-advisory-findings -->` comment (BR7), then
    `render` + `apply` to upsert it.
  - Apply the `security-advisory-decision-required` label when any tracked
    finding is `pending`; remove it only when zero tracked findings are
    `pending` (never touch `human-checkpoint-required`, BR4/AC7).
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
3. AC3: fixture findings shaped like the PR #1431 findings (force semantics
   without a lease; permissive remote URL parsing) against
   `scripts/development-workflow/workflow-branch-push-guard.sh` return
   `securitySensitive: true`.
4. AC4/AC5/BR5: gate test — a PR with one `pending` `.securityAdvisories[]`
   entry, `policy.mayMerge: true`, `mode: delegated`, and every other gate
   condition green still returns `decision != "merge_allowed"` and includes
   the `security_sensitive_advisory_pending` reason.
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
   correct).
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
   from the reconciled output entirely, never carrying forward `pending`.
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
  - Negative lookalike, category: `"the retry count is a secret constant we
    tune later"` does not match category (b) (no credential/token/exposure
    context — the pattern requires "secret"/"credential"/"token"/"password"
    co-occurring with an exposure/logging/handling verb, not the bare word
    "secret").
  - Multiple category keywords on one line: a finding containing both
    "force push" and "secret" text matches on the first category in priority
    order (a→b→c→d→e) — the test asserts `matchedCategory == "b"` when the
    finding text lists the secret-exposure sentence first, proving ordering
    is text-order-first, not a fixed category-priority override, and
    documents this precisely so implementers do not have to guess.
  - Overlapping categories (a) vs (e): "this change bypasses the auth check"
    — asserted to match category (a) specifically (auth bypass takes
    precedence when both an auth noun and "bypass" co-occur), not the more
    generic category (e).
  - File-location exact-match boundary: a finding against
    `scripts/development-workflow/run-epic-risk-classifier-notes.sh` (a
    lookalike, non-enforcement-surface file) does not match Part B even
    though `run-epic-risk-classifier.sh` is on the allowlist — proves exact
    path match, not prefix match.
  - `.github/workflows/*.yml` special case: a finding about
    `.github/workflows/deploy.yml`'s `on: push` trigger (no
    `permissions:`/`secrets:` context) does not match Part B; a finding about
    the same file's `permissions: contents: write` block does.
  - Empty/absent file path (PR-level issue comment, no inline `path`): Part B
    always fails by construction — asserted directly, not inferred.
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
| Human decision-comment template is easy to mistype, silently failing verification            | Medium     | Low    | Exact-text-match failure is fail-closed (finding stays `pending`, not silently resolved) — mirrors the existing authorization-text pattern's already-accepted UX tradeoff; the runner posts the exact expected template text in its notification comment for the human to copy. |
| New Gate 5 branch could be mis-ordered relative to the existing scope short-circuit, silently reintroducing a `pr.inScope`-false no-op | Low | High | Implementation Order Step 6 requires an explicit test proving the branch lives inside the normal `else` cascade (AC8/AC9 test matrix), not a new top-level short-circuit. |

---

## Code Samples

> Illustrative only — adapt during implementation.

```bash
# Illustrative — adapt during implementation.
# scripts/development-workflow/security-advisory-classifier.sh classify (shape)
classify() {
  local finding_text="$1" file_path="$2"
  local matched_category=""
  if printf '%s' "$finding_text" | grep -qiE 'auth(entication|orization)?.*(bypass|skip|spoof)'; then
    matched_category="a"
  elif printf '%s' "$finding_text" | grep -qiE '(secret|credential|token|password).*(expos|log|leak|plaintext)'; then
    matched_category="b"
  elif printf '%s' "$finding_text" | grep -qiE '(force[- ]?push|--force\b|hard reset|history rewrite).*(lease|atomic|destructive)?'; then
    matched_category="c"
  elif printf '%s' "$finding_text" | grep -qiE '(injection|unsanitized|eval\(|path.traversal)'; then
    matched_category="d"
  elif printf '%s' "$finding_text" | grep -qiE '(bypass|weaken|disable|circumvent).*(guard|gate|policy|check)'; then
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
   and the new reasons-cascade branch inside the existing normal-cascade
   `else` block. Extend
   `scripts/development-workflow/tests/test-run-epic-delegated-gate.sh` with
   the AC4/AC5/AC6/AC8/AC9/AC10/AC11 test cases from "Key scenarios to test."
   Planted-violation proof: show `decision: "merge_allowed"` before the new
   branch exists (with a fixture `pending` `.securityAdvisories[]` entry and
   every other gate condition green), and `decision: "human_required"` with
   the `security_sensitive_advisory_pending` reason after.
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
   Layer-by-Layer Changes above. Run
   `npx markdownlint-cli2 "docs/workflow/development-workflow/**/*.md" "REVIEW.md"`
   and fix any reported issues.
6. **Stage 5 — Cross-section consistency pass and full test run**: Re-read
   every occurrence of the label, stop-condition token, evidence field names,
   and the decision-comment template across all six modified/created
   documents and confirm identical spelling everywhere (this plan's
   Workflow Decision-Gate Matrix delta table is the source of truth). Run all
   new and existing `scripts/development-workflow/tests/test-*.sh` files
   touched by this change and confirm they pass together, not only
   individually (guards against cross-test global state leakage).
7. **Stage 6 — Update project docs**: none required beyond the items already
   listed in **Documentation Updates** above (all are already Stage 4/5
   items).
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

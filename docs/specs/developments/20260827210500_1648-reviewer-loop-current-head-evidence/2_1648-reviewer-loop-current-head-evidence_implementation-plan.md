# Reviewer Loop Current-Head Evidence — Implementation Plan

**Spec**: None — Refactor item. Source brief:
[issue #1648](https://github.com/lhpaul/ai-dev-framework-template/issues/1648)
(epic [#1647](https://github.com/lhpaul/ai-dev-framework-template/issues/1647))
**Smoke test runbook**:
[1648-reviewer-loop-current-head-evidence.smoke-test.md](../../../testing/workflow/1648-reviewer-loop-current-head-evidence.smoke-test.md)

---

## Summary

**Approach**: `local-ai-reviewer.sh` already emits `REVIEWED_HEAD`, and
`pr-review-loop.sh` already forwards it as `PLATFORM_<n>_REVIEWED_HEAD`, but no
consumer surface keeps it: the reviewer-loop summary comment never prints it,
the `reviewer_loop_history.v1` ledger entry records only one loop-level
`head_sha`, and `item-completion-self-check.sh` accepts any clean summary text
without checking which commit it described. This plan threads the value through
those three surfaces: capture reviewed heads per platform in the loop, render a
`Head evidence` block plus a `reviewed_heads[]` ledger field that marks each
reviewer `current` or `not-current`, export an aggregate
`LOCAL_AI_HEAD_CURRENT` / `LOCAL_AI_REVIEWED_HEAD` pair on the loop's key=value
contract, and make a stale local clean result block `ready-for-human-review`
through the existing readiness checklist and ground-truth self-check.

**Estimated complexity**: M

**Rationale**: The data already exists and flows to the boundary of the loop, so
no new reviewer integration is needed. The work is concentrated in one large
script (`pr-review-loop.sh`), one self-check script, two protocol documents, and
their harnesses — a handful of files, but each on a surface where a readiness
gate is enforced, so the tests carry more weight than the edits.

**Dependencies**: None. This is the first item of epic #1647 and no sibling
item's PR is merged. Later siblings (#1649, #1651, #1652, #1656) consume the
`reviewed_heads[]` ledger field this item introduces.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `7998d43d` |
| `REVIEWED_HEAD` producers | `grep -rn "REVIEWED_HEAD" scripts/development-workflow/*.sh \| awk -F: '{print $1}' \| sort \| uniq -c` | 3 in `local-ai-reviewer.sh`, 4 in `pr-review-loop.sh`; no other script |
| Which loop reviewer emits it | `awk '/^run_[a-z_]*_review(_review)?\(\)/{fn=$1} /print_kv REVIEWED_HEAD/{print fn}' scripts/development-workflow/pr-review-loop.sh \| sort \| uniq -c` | 4 occurrences, all inside `run_local_ai_reviewer_review()` — one per exit-code branch (clean, needs_fixes, escalate, skipped) |
| Forwarding to loop stdout | `grep -n -A20 "^emit_prefixed_platform_output()" scripts/development-workflow/pr-review-loop.sh` | Every key except `RESULT`/`PR_NUMBER`/`BRANCH`/`FIX_AGENT`/`PLATFORM` is re-emitted as `PLATFORM_<n>_<KEY>`, so `PLATFORM_<n>_REVIEWED_HEAD` is already on stdout |
| Ledger entry fields | `grep -n "head_sha:" scripts/development-workflow/pr-review-loop.sh` | Single hit at line 6929 inside `reviewer_loop_history_build_entry`; no per-platform reviewed head is stored |
| Ledger head source | `sed -n '6843,6866p' scripts/development-workflow/pr-review-loop.sh` | `reviewer_loop_history_current_head_sha` reads `gh pr view --json headRefOid`, i.e. the live PR head at write time, not the head any reviewer read |
| Summary comment sections | `sed -n '9013,9022p' scripts/development-workflow/pr-review-loop.sh` | Body interpolates `small_findings_section`, `phase_section`, `compare_section`, `advisory_section`, `advisory_checks_section`, `regression_label_section` — no head-evidence section exists |
| Self-check review row | `grep -n "pull_request.review_summary" scripts/development-workflow/item-completion-self-check.sh` | Rows added at lines 701–716; the verified branch only tests the summary text for `Result: clean\|skipped`, never a SHA |
| Existing head conditions in Protocol 92 | `grep -n "POST_CLEAN_HEAD_SHA" docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md` | Present for the aggregate post-clean settle only; no condition names a per-reviewer reviewed head |
| Reviewed head is a full OID | `grep -n 'HEAD_SHA=' scripts/development-workflow/local-ai-reviewer.sh` and `grep -n 'print_kv REVIEWED_HEAD' scripts/development-workflow/local-ai-reviewer.sh` | `HEAD_SHA` is set from `gh pr view --json headRefOid` (line 237) and printed verbatim as `REVIEWED_HEAD` (line 369) — the reviewer emits the full 40-character OID, never an abbreviation |
| Current head is the same field | `sed -n '8515,8521p' scripts/development-workflow/pr-review-loop.sh` | `loop_head_sha` is read from `gh pr view --json headRefOid` before any reviewer is dispatched, so both sides of the comparison come from the same GitHub field |
| Harness entry point | `grep -n "HARNESS_MODE=1 source" scripts/development-workflow/tests/*.sh` | `test-pr-review-loop.sh` and `test-local-ai-reviewer-pr-review-loop-dispatch.sh` both source the loop with `HARNESS_MODE=1`, so new pure functions are unit-testable without network access |
| Suite selection | `head -40 scripts/development-workflow/select-test-suites.sh` | Suites declare coverage with `# covers:` headers; no `.github/workflows` edit is needed to wire a new or edited suite |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch for this item | `develop-internal-reviewer-effectiveness` | `integration-branch:internal-reviewer-effectiveness` label on #1648; Protocol 91 § Integration-branch base override | 2026-08-27, repo SHA `7998d43d` | Epic #1647 items #1648–#1657 only; no other open PR targets this base | `Resolved` |
| Reviewer-loop ledger schema identifier | `reviewer_loop_history.v1` | `REVIEWER_LOOP_HISTORY_SCHEMA` in `pr-review-loop.sh` | 2026-08-27, repo SHA `7998d43d` | Reader paths in `pr-review-loop.sh` and `run-epic-*` helpers | `Verified` |

Resolution note for the base branch row: the run-epic scope resolver reported
`baseBranch=develop` with the warning *"integration branch
develop-internal-reviewer-effectiveness ... was not found on origin; using
develop"*. The branch was missing only because no sibling had created it yet.
All ten epic items carry the same integration-branch label (not a partial or
mixed set), so Protocol 91 § Integration-branch base override step 4 applies:
the branch was created from `origin/develop` and pushed before any item branch,
and `develop-internal-reviewer-effectiveness` is the approved base for this PR.

The ledger schema row stays `v1`: this plan only adds optional fields, and every
reader dereferences ledger fields with `// ""` or `// []` defaults, so an entry
written before this change still parses.

---

## Layer-by-Layer Changes

### Backend / API

Not applicable — this repository ships workflow tooling, not a service.

### Shared Packages / Libraries

`scripts/development-workflow/pr-review-loop.sh` (shell contract: `bash`; the
file declares `#!/usr/bin/env bash` and uses Bash arrays):

- [ ] Add a `platform_reviewed_heads` associative-style parallel array
      (`platform_reviewed_heads+=("${platform_name}:${_reviewed_head}")`)
      alongside the existing `platform_result_tokens` accumulation in the
      per-platform block, populated from
      `kv_value_default REVIEWED_HEAD "$platform_output" ""`. Reviewers that do
      not report a reviewed head record the empty string and are rendered as
      `not-reported`, which is distinct from `not-current`.
- [ ] **Reuse the existing pre-dispatch snapshot — do not add a second lookup.**
      `loop_head_sha` is already captured from
      `gh pr view --json headRefOid` before any reviewer is dispatched
      (`pr-review-loop.sh`, the block introduced by issue #1574), and it is
      already the value the settle emits as `POST_CLEAN_HEAD_SHA`. Every
      consumer added by this plan — the summary block, the ledger field, and
      the two stdout keys — classifies against `loop_head_sha` and nothing
      else. No new `gh` call is introduced, so there is no window in which two
      adjacent lookups could observe different commits and produce
      contradictory per-reviewer and aggregate evidence. Re-reading the live
      head inside any renderer is explicitly out of bounds.
- [ ] **Reconciliation with the ledger's own `head_sha`.** The ledger's
      existing `head_sha` keeps its current source
      (`reviewer_loop_history_current_head_sha`, read at write time): it is the
      identity key both #1502 cap counters bucket on, and re-pointing it would
      change cap accounting, which is outside this item's scope. Instead the
      entry gains `classification_head`, set to `loop_head_sha`, so a reader can
      see exactly which snapshot the `reviewed_heads[]` states were computed
      against and can detect the case where the head moved between dispatch and
      write time. The two fields being equal is the normal case; them differing
      is the head-moved case the existing guard at the end of the loop already
      turns into `needs_fixes` / `head_moved_during_run`.
- [ ] When the pre-dispatch lookup fails, `loop_head_sha` is the empty string
      (its existing documented behavior — the loop already warns that
      `POST_CLEAN_HEAD_SHA` will be empty and Protocol 91 Check 0.6 will refuse
      the verdict). **Precedence is the classifier's step order, which is
      authoritative wherever this plan describes an outcome**: the reviewed head
      is examined first, so a platform that reported *no* head stays
      `not-reported` even when the current head is also empty, and only a
      platform that *did* report a head classifies
      `not-current|unverifiable_current_head`. Both outcomes are blocking —
      `LOCAL_AI_HEAD_CURRENT` is `0` in the second case and empty in the first,
      and the fail-closed readiness rule refuses both — so the empty
      `loop_head_sha` path is fail-closed either way, aligned with the refusal
      Check 0.6 already performs for the same cause. The
      synthetic `unknown-<epoch>-<pid>-<rand>` placeholder never reaches this
      path, because it is produced by `reviewer_loop_history_current_head_sha`
      for the ledger's `head_sha`, not by the pre-dispatch capture; it is still
      covered as an edge case so the predicate rejects it if a future caller
      passes it in.
- [ ] Add pure predicate `reviewer_loop_head_evidence_full_sha <value>`
      returning success only when the value matches `^[0-9a-fA-F]{40}$`.
      **No prefix or abbreviation matching is performed anywhere in this
      feature.** A shared 7-character prefix does not prove two values name the
      same commit — abbreviation uniqueness is a repository-scoped property that
      a fixed minimum length does not establish — and the reviewer this gate
      exists for already emits the full OID: `local-ai-reviewer.sh` sets
      `HEAD_SHA` from `gh pr view --json headRefOid` and prints it verbatim as
      `REVIEWED_HEAD`, and the loop's own `loop_head_sha` comes from the same
      field. Full equality is therefore both the safe rule and the one that
      matches the data actually produced.
- [ ] Add pure function `reviewer_loop_head_evidence_classify <reviewed_head>
      <current_head>` printing `<state>` or `<state>|<reason>`, where state is
      one of `current`, `not-current`, or `not-reported`, in this deterministic
      order:
      1. Reviewed head empty → `not-reported`.
      2. Reviewed head fails `reviewer_loop_head_evidence_full_sha` →
         `not-current|unverifiable_reviewed_head`. A truncated, abbreviated,
         non-hex, or over-length value is not evidence of currency, and the
         reason distinguishes it from a genuine mismatch so the summary does not
         imply the reviewer read a different commit.
      3. Current head fails `reviewer_loop_head_evidence_full_sha` →
         `not-current|unverifiable_current_head`. This is the empty
         `loop_head_sha` path (failed pre-dispatch read) and the synthetic
         placeholder path.
      4. Both are full SHAs → compare for **exact case-insensitive equality**;
         `current` when equal, `not-current|head_mismatch` otherwise.
      Case-insensitive comparison is deliberate — `headRefOid` is lowercase, and
      a reviewer that echoes an uppercase OID is naming the same commit. Every
      non-`current` outcome is fail-closed: `LOCAL_AI_HEAD_CURRENT` is `0` for
      all three reasons, so no unverifiable value can produce a passing
      readiness signal.
- [ ] Add pure function `reviewer_loop_head_evidence_render <current_head>
      <entries…>` producing the Markdown `**Head evidence:**` block, one row per
      platform carrying its state and, for `not-current`, its reason, and
      interpolate it into the summary comment body immediately before
      `${phase_section}`.
- [ ] Add pure function `reviewer_loop_head_evidence_json <current_head>
      <entries…>` producing the `reviewed_heads` array, whose elements carry
      `platform`, `reviewed_head`, `state`, and `reason`, and thread it into
      `reviewer_loop_history_build_entry` as a new `--argjson reviewedHeads`
      parameter following the existing `current_run_id` convention (set by the
      caller in a global, not appended to the positional list).
- [ ] Emit three new top-level key=value pairs on the loop's stdout contract
      next to the existing aggregate keys, **always, on every run**:
      - `LOCAL_AI_CONFIGURED` — `1` when `local-ai-reviewer` is in the resolved
        platform list, `0` when it is not. This is the applicability signal.
      - `LOCAL_AI_REVIEWED_HEAD` — the reviewed head reported by that platform;
        empty when it is not configured or reported none.
      - `LOCAL_AI_HEAD_CURRENT` — `1` when the classification is `current`, `0`
        when `not-current`, empty when `not-reported` or not configured.

      Applicability is carried by `LOCAL_AI_CONFIGURED`, **never by the absence
      of a key**. An absent key means the telemetry did not reach the consumer,
      which is a fail-closed condition, not a pass. All three values stay within
      the `[A-Za-z0-9:_-]` token charset the Protocol 91 carry-forward snippet
      already admits — a 40-character hex OID included — so no pattern widening
      is needed for them.
- [ ] Document both new keys in the `--help` usage block so the contract stays
      discoverable from the script itself.

`scripts/development-workflow/item-completion-self-check.sh` (shell contract:
`bash`):

- [ ] Add a `pull_request.local_reviewer_head` row derived from the newest
      reviewer-loop summary comment. The configured/unconfigured split is what
      decides optional vs. required — a pre-field ledger entry must **not** be
      treated as optional, because that is exactly the stale-verdict hole this
      item closes:

      | Condition | Status |
      | --- | --- |
      | Ledger's newest entry records the `local-ai-reviewer` reviewed head equal to the live `headRefOid` | `verified` |
      | It records a different SHA | `discrepancy` |
      | Platform is configured and review evidence is required, but the entry has no `reviewed_heads` field (pre-field ledger) | `unavailable_required` |
      | Platform is configured and review evidence is required, but the ledger is unreadable | `unavailable_required` |
      | `local-ai-reviewer` is not in the resolved platform list | `unavailable_optional` |
      | Review evidence is not required for this terminal claim (`--require-review-summary` not set) | `unavailable_optional` |

      An `unavailable_required` result keeps the item non-terminal, which is the
      existing contract stated in Protocol 92 § Readiness Labels and Report
      Evidence. Re-running Step 7 on the live head writes a ledger entry with
      the field and clears the row.
- [ ] Keep the existing `pull_request.review_summary` row unchanged so the new
      row is additive evidence rather than a redefinition of an existing one.

### Frontend / UI

Not applicable — no user interface in this repository.

### Infrastructure / Configuration

- [ ] No `.ai-dev-workflow.yaml` change. The behavior keys off whether
      `local-ai-reviewer` appears in the resolved platform list, which the loop
      already computes.

### Documentation

- [ ] `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`
      — add one **fail-closed** bullet under *Conditions for
      `ready-for-human-review`*: when `local-ai-reviewer` is in the resolved
      platform list and Step 7 returned `clean`, `LOCAL_AI_HEAD_CURRENT` must
      be exactly `1`. Both other values block the label: `0` is positive
      not-current evidence, and an empty value means the reviewer ran but
      reported no head at all, which is missing evidence — and missing evidence
      is not a pass. Either way the label waits until Step 7 is re-run on the
      live head. Applicability is read from `LOCAL_AI_CONFIGURED`: `0` means the
      platform is not in the resolved list and the condition does not apply;
      an unset `LOCAL_AI_CONFIGURED` means the loop's telemetry never reached
      the checklist and is itself blocking, so an absent key is never a pass.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      — three coordinated edits, because emitting the keys is not enough on its
      own: the Step 7 carry-forward snippet currently unsets and greps only
      `POST_CLEAN_*`, so without the first edit the new keys never reach the
      checklist and the gate would silently never fire.
      1. **Carry-forward snippet** (§ "Carry the settle verdict forward"):
         widen the unset loop and the grep to
         `^(POST_CLEAN|LOCAL_AI)_[A-Z_]*` and
         `^(POST_CLEAN|LOCAL_AI)_[A-Z_]+=[A-Za-z0-9:_-]*$` respectively, so the
         three new keys are cleared and re-exported on exactly the same
         lifecycle as the settle fields. The surrounding contract is unchanged:
         cleared before the run, exported only on a zero exit, belonging to the
         latest HEAD only.
      2. **Check 0.6** (exit 12): add the local-reviewer condition next to the
         existing `POST_CLEAN_HEAD_SHA` one, evaluated in this order —
         `LOCAL_AI_CONFIGURED` unset → fail closed with "reviewer-loop telemetry
         was not carried forward; re-run Step 7 and export its `POST_CLEAN_*`
         and `LOCAL_AI_*` fields"; `LOCAL_AI_CONFIGURED=0` → condition not
         applicable, continue; `LOCAL_AI_CONFIGURED=1` and
         `LOCAL_AI_HEAD_CURRENT` not exactly `1` → refuse the label and re-run
         Step 7 on the live head. Extend the exit-12 row of the exit-code table
         to name the new cause.
      3. **Work Item Runner summary**: add a reviewed-head row reporting
         `LOCAL_AI_CONFIGURED`, `LOCAL_AI_REVIEWED_HEAD`, and
         `LOCAL_AI_HEAD_CURRENT`.

---

## Testing Strategy

**Test types**: Unit (shell harness), plus the smoke test runbook.

**Key scenarios to test**:

1. `reviewer_loop_head_evidence_classify` returns the required state — and
   reason where the table names one — for every row of the parser-risk
   edge-case table. Maps to brief scope bullets 1 and 2, and is the regression
   coverage for the full-OID equality rule and its three failure reasons.
2. `reviewer_loop_head_evidence_full_sha` accepts a 40-char hex value and
   rejects a 39-char value, a 41-char value, a 7-char abbreviation, a 40-char
   value containing a non-hex character, and the empty string — pins full-OID
   equality as an enforced rule rather than a comment.
3. All consumers classify against the single pre-dispatch `loop_head_sha`
   snapshot: with `gh pr view --json headRefOid` mocked to return a *different*
   SHA on every call, one loop iteration still produces the same current head
   and the same per-platform classification in the rendered block, the ledger
   entry, and `LOCAL_AI_HEAD_CURRENT` — fails if any renderer issues its own
   lookup instead of reading `loop_head_sha`.
4. The ledger entry's `classification_head` equals the `POST_CLEAN_HEAD_SHA`
   emitted by the same run — pins the reconciliation between the new per-reviewer
   evidence and the existing aggregate head evidence, so the two cannot drift
   apart silently.
5. `reviewer_loop_head_evidence_render` prints one row per platform carrying
   that platform's state, and its reason when the state is `not-current`, and
   prints the current PR head exactly once — scope bullet 1.
6. `reviewer_loop_head_evidence_json` emits a `reviewed_heads` array whose
   entries carry `platform`, `reviewed_head`, `state`, and `reason` (empty
   string when the state is `current` or `not-reported`), and an empty array
   when no platform is configured — supports #1651 and #1657 downstream.
7. A ledger entry written without `reviewed_heads` or `classification_head`
   still parses through `reviewer_loop_history_payload_from_existing` —
   backward compatibility of the `v1` schema.
8. `LOCAL_AI_HEAD_CURRENT=0` is emitted when the local reviewer's reviewed head
   differs from `loop_head_sha` — scope bullet 3 (block readiness claims on a
   stale local clean result).
9. With `local-ai-reviewer` configured but reporting no reviewed head, the loop
   emits `LOCAL_AI_CONFIGURED=1` and `LOCAL_AI_HEAD_CURRENT=` (present, empty) —
   the fail-closed "missing evidence" state that must block readiness, distinct
   from scenario 10.
10. With `local-ai-reviewer` absent from the resolved platform list, the loop
    emits `LOCAL_AI_CONFIGURED=0` — the "condition not applicable" state, and
    the automated coverage for the downstream-consumer compatibility mitigation
    in the risk table. All three keys are emitted on every run, so applicability
    never depends on a key being absent.
11. `item-completion-self-check.sh` fills `pull_request.local_reviewer_head`
    with the expected status for **each of the six rows** of its condition
    table, one case per row: `verified` (ledger head equals the live
    `headRefOid`); `discrepancy` (ledger head differs); `unavailable_required`
    for a pre-field ledger with the platform configured and review evidence
    required; `unavailable_required` for an unreadable ledger under the same
    conditions; `unavailable_optional` when `local-ai-reviewer` is not in the
    resolved platform list; and `unavailable_optional` when
    `--require-review-summary` is not set — scope bullet 3 at the
    report-evidence layer.
12. The Protocol 91 carry-forward snippet, run against a captured loop output,
    exports all three `LOCAL_AI_*` keys into the environment, and clears them
    before the next invocation exactly as it clears `POST_CLEAN_*` — this is the
    regression test for the gap where the keys are emitted but never reach
    Check 0.6, which would make the whole gate silently inert.

**Files**:

- `scripts/development-workflow/tests/test-pr-review-loop.sh` — scenarios 1–7,
  added as new cases in the existing `HARNESS_MODE=1` harness.
- `scripts/development-workflow/tests/test-local-ai-reviewer-pr-review-loop-dispatch.sh`
  — scenarios 8, 9, and 10, next to the existing dispatch assertions.
- `scripts/development-workflow/tests/test-item-completion-self-check.sh` —
  scenario 11, one case per row of the six-condition table.
- `scripts/development-workflow/tests/test-pr-review-loop.sh` — scenario 12,
  which needs a `# covers:` header line for
  `docs/workflow/development-workflow/protocols/91-*.md` so a later edit to the
  carry-forward snippet re-runs this suite. This is the one `# covers:` edit
  this plan requires.

Coverage declarations: the three suites already cover the two changed scripts —
`test-pr-review-loop.sh` covers `pr-review-loop.sh` by naming convention, and
the dispatch suite declares both scripts explicitly. The single addition is the
`# covers:` line for the Protocol 91 document noted above, without which an edit
to the carry-forward snippet would not select scenario 12's suite.

**Smoke test runbook**:
`docs/testing/workflow/1648-reviewer-loop-current-head-evidence.smoke-test.md`

**Regression suite**: The repository's regression surface is the
`workflow-tests.yml` harness selection described above; the three suites listed
are the regression coverage for this change. No separate regression spec exists
to update.

### Parser-risk addendum

Applicable — `reviewer_loop_head_evidence_classify` compares two
externally-supplied strings and normalizes length.

- **Edge-case enumeration**, each with its required classification:

  | Reviewed head | Current head | Required result | Why |
  | --- | --- | --- | --- |
  | 40-char SHA | same 40-char SHA | `current` | exact match — the only passing case |
  | uppercase 40-char SHA | same SHA lowercase | `current` | same commit, different casing |
  | 40-char SHA | different 40-char SHA | `not-current` / `head_mismatch` | genuine mismatch |
  | 7-char abbreviation | 40-char SHA sharing the prefix | `not-current` / `unverifiable_reviewed_head` | a shared prefix does not prove identity; this is the negative case for the abbreviation-uniqueness finding |
  | 39-char hex string | 40-char SHA sharing the prefix | `not-current` / `unverifiable_reviewed_head` | one below full length — pins the boundary, not just a value far from it |
  | 41-char hex string | 40-char SHA sharing the prefix | `not-current` / `unverifiable_reviewed_head` | longer than an OID; rejected rather than truncated |
  | 40 chars with one non-hex character | 40-char SHA | `not-current` / `unverifiable_reviewed_head` | correct length but not hex |
  | `""` (empty) | 40-char SHA | `not-reported` | reviewer reported nothing; distinct from a mismatch |
  | 40-char SHA | `""` (empty) | `not-current` / `unverifiable_current_head` | failed pre-dispatch read of `loop_head_sha` |
  | 40-char SHA | `unknown-1756330000-4821-19342` | `not-current` / `unverifiable_current_head` | synthetic placeholder is non-hex and not 40 chars |

- **Unit test mapping**: each row above gets one case in
  `test-pr-review-loop.sh`, asserting the exact state and reason in the
  "Required result" column. The abbreviation, 39-char, 41-char, non-hex, empty
  and placeholder rows are the negative tests that keep an unverifiable value
  from manufacturing a passing readiness signal.
- **Suppression semantics**: not applicable — no suppression directives.

### Concurrent-event-source addendum

Not applicable. The loop is a single sequential process; the new functions are
pure and hold no state across invocations. The only shared mutable state is the
existing `platform_*` accumulation arrays, written in the same sequential
per-platform block that already writes `platform_result_tokens`.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Ledger fixture without `reviewed_heads` or `classification_head` | A `reviewer_loop_history.v1` payload with one entry that predates this change, to prove backward compatibility (scenario 7) | inline heredoc in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Ledger fixture with a stale local head | Newest entry recording a `local-ai-reviewer` reviewed head that differs from the 40-character OID the mocked `gh pr view` returns (scenario 11) | inline mock in `scripts/development-workflow/tests/test-item-completion-self-check.sh` |
| Ledger fixture with no `reviewed_heads` field, platform configured | Same payload as the first row, evaluated with `--require-review-summary true` and `local-ai-reviewer` in the resolved list, to pin `unavailable_required` (scenario 11) | inline mock in `scripts/development-workflow/tests/test-item-completion-self-check.sh` |

No repository fixture files are added; both suites already build their fixtures
inline with mock `gh` commands and require no network access.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`
      — add the `LOCAL_AI_HEAD_CURRENT` condition under *Conditions for
      `ready-for-human-review`*.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      — enforce the same condition in the readiness checklist alongside
      `POST_CLEAN_HEAD_SHA`, and add the reviewed-head row to the Work Item
      Runner summary fields.
- [ ] `REVIEW.md` — no change. The reviewed-head signal is produced by the loop,
      not asserted by a reviewer against the review contract.
- [ ] `AGENTS.md` — no change. It does not enumerate reviewer-loop output keys.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A partial match is mistaken for proof that two values name the same commit | Med | High — it would defeat the gate this item exists to build | No prefix or abbreviation matching exists anywhere in the feature: `reviewer_loop_head_evidence_full_sha` requires a full 40-character hex OID on both sides and the comparison is exact case-insensitive equality. Both producers already emit `headRefOid` in full, so nothing legitimate is rejected; the abbreviation, 39-char, 41-char, and non-hex rows of the edge-case table are the negative tests |
| A failed live-head lookup yields the synthetic `unknown-…` placeholder and is compared against a real SHA | Med | Med — could produce a confusing `not-current` or, if mishandled, a false `current` | The placeholder is non-hex, so it fails the validity predicate and every platform classifies `not-current` for that iteration — fail-closed by construction, pinned by its own edge-case row |
| The summary block, the ledger entry, and the stdout keys classify against different snapshots of the live head | Med | High — the three surfaces would contradict each other, and per-reviewer evidence could disagree with `POST_CLEAN_HEAD_SHA` | No new lookup is added: all consumers read the existing pre-dispatch `loop_head_sha`, the same value the settle emits as `POST_CLEAN_HEAD_SHA`; scenario 3 fails if any renderer issues its own lookup, and scenario 4 pins `classification_head` equal to `POST_CLEAN_HEAD_SHA` |
| Adding fields to `reviewer_loop_history.v1` breaks a reader that validates the entry shape | Low | High — a broken ledger read is fail-closed and would stall every reviewer loop | `reviewed_heads` and `classification_head` are additive and optional; scenario 7 asserts an entry without either still parses through `reviewer_loop_history_payload_from_existing` |
| The new readiness condition blocks PRs in repositories that do not configure `local-ai-reviewer` | Low | High — it would stall downstream consumers of this template | Applicability is read from `LOCAL_AI_CONFIGURED`, which the loop emits on every run: `0` means the platform is not in the resolved list and Check 0.6 continues without evaluating the head condition. Scenario 10 asserts `LOCAL_AI_CONFIGURED=0` for a non-configuring repository, and scenario 9 pins the separate configured-but-no-head state that *does* block |
| The keys are emitted but never reach Check 0.6, leaving the gate inert | Med | High — the item would appear complete while changing nothing about readiness | The Protocol 91 carry-forward snippet is widened to `^(POST_CLEAN\|LOCAL_AI)_` in the same edit that adds the Check 0.6 condition; scenario 12 exports a captured loop output through the snippet and asserts all three keys arrive, and the new `# covers:` line makes a later snippet edit re-run that suite |
| The summary comment grows past what reviewers read | Low | Low | The head-evidence block is one line per configured platform plus one current-head line, in the same style as the existing compare-mode block |

---

## Code Samples

```bash
# Illustrative — adapt during implementation.

# A value is usable head evidence only when it is a full 40-character hex OID.
# No abbreviation or prefix matching: a shared prefix does not prove two values
# name the same commit, and both producers already emit the full headRefOid.
reviewer_loop_head_evidence_full_sha() {
  local value="$1"
  case "$value" in
    ''|*[!0-9a-fA-F]*) return 1 ;;
  esac
  [ "${#value}" -eq 40 ]
}

# Classify one reviewer's reviewed head against the pre-dispatch loop_head_sha.
# Prints "<state>" or "<state>|<reason>". Every non-current outcome is
# fail-closed: LOCAL_AI_HEAD_CURRENT is 0 for all of them.
reviewer_loop_head_evidence_classify() {
  local reviewed="$1"
  local current="$2"

  if [ -z "$reviewed" ]; then
    printf 'not-reported\n'
    return 0
  fi
  if ! reviewer_loop_head_evidence_full_sha "$reviewed"; then
    printf 'not-current|unverifiable_reviewed_head\n'
    return 0
  fi
  if ! reviewer_loop_head_evidence_full_sha "$current"; then
    printf 'not-current|unverifiable_current_head\n'
    return 0
  fi

  reviewed="$(printf '%s' "$reviewed" | tr 'A-F' 'a-f')"
  current="$(printf '%s' "$current" | tr 'A-F' 'a-f')"

  if [ "$reviewed" = "$current" ]; then
    printf 'current\n'
  else
    printf 'not-current|head_mismatch\n'
  fi
}
```

Rendered summary block, illustrative:

```markdown
**Head evidence:** current PR head `82d2f3a844a6c0c417f5c55e8a01eebdf343de45`

- local-ai-reviewer: reviewed `82d2f3a844a6c0c417f5c55e8a01eebdf343de45` — current
- pr-agent: reviewed `29c0e9d2541a85c0e335052de42599f485d51a67` — not-current (head_mismatch)
- codex-github: not-reported
```

Full OIDs are printed rather than abbreviations, matching the comparison rule:
the block shows exactly the values that were compared, so a reader can verify
the verdict without resolving an abbreviation.

---

## Implementation Order

1. Add the four pure helpers (`reviewer_loop_head_evidence_full_sha`,
   `…_classify`, `…_render`, `…_json`) to
   `scripts/development-workflow/pr-review-loop.sh` near the existing
   `reviewer_loop_history_*` helpers. **Verify**: source the script with
   `HARNESS_MODE=1` and call each function directly; confirm every row of the
   parser-risk edge-case table returns its required state and reason.
2. Populate `platform_reviewed_heads` in the per-platform result block next to
   the existing `platform_result_tokens+=(...)` line, and classify each entry
   against the existing pre-dispatch `loop_head_sha` — do not add a lookup.
   **Verify**: run the dispatch suite and confirm the array is populated for a
   mocked `local-ai-reviewer` run, and that mocking `gh pr view --json
   headRefOid` to change on every call does not change the classification.
3. Interpolate the `**Head evidence:**` block into the summary comment body
   before `${phase_section}`. **Verify**: run the harness case that builds the
   comment body and read the output; confirm the block appears once, with one
   row per configured platform.
4. Thread `reviewed_heads` and `classification_head` into
   `reviewer_loop_history_build_entry` via caller-set globals, following the
   `current_run_id` convention already documented in that function. Leave the
   existing `head_sha` field and its source untouched. **Verify**: build an
   entry in the harness and pipe it through `jq` to confirm the array shape and
   that `classification_head` equals the run's `POST_CLEAN_HEAD_SHA`.
5. Emit `LOCAL_AI_CONFIGURED`, `LOCAL_AI_REVIEWED_HEAD`, and
   `LOCAL_AI_HEAD_CURRENT` on the loop's stdout contract on every run, and
   document all three in `--help` including which key carries applicability and
   the `1` / `0` / empty contract for `LOCAL_AI_HEAD_CURRENT`. **Verify**: run
   `pr-review-loop.sh --help` and confirm all three keys and their states are
   described.
6. Add the `pull_request.local_reviewer_head` row to
   `scripts/development-workflow/item-completion-self-check.sh`. **Verify**: run
   the self-check suite and read the emitted Markdown section; confirm the row
   appears with the expected status for each mocked ledger.
7. Update
   `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`
   and
   `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
   per **Documentation Updates** — the carry-forward snippet widening, the
   Check 0.6 condition, the exit-12 table row, and the runner-summary row must
   land together; the Check 0.6 condition without the snippet widening is an
   inert gate. **Verify**: run the carry-forward snippet against a captured loop
   output and confirm all three `LOCAL_AI_*` keys are present in the
   environment afterwards.
8. Add the unit cases to the three suites named in **Testing Strategy**.
   **Verify**: run each suite and confirm it exits 0.
9. Run `bash scripts/development-workflow/select-test-suites.sh` against the
   change set and confirm the three suites are selected. **Verify**: read the
   selection output and confirm it names them.
10. Run `shellcheck` on both changed scripts and `markdownlint-cli2` on both
    changed protocol documents, the plan, and the runbook. **Verify**: both
    tools exit 0.
11. Add a changelog fragment
    `changelog.d/1648.changed.reviewer-loop-current-head-evidence.md` containing
    exactly:

    ```markdown
    - **Reviewer-loop current-head evidence** (#1648): the reviewer-loop summary and history now record which commit each reviewer actually reviewed, and a stale local-ai-reviewer clean result no longer satisfies `ready-for-human-review`.
    ```

12. Update project docs per **Documentation Updates** above (steps 7 covers the
    two protocol files; no other project doc is affected).

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
- [ ] Add pure function `reviewer_loop_head_evidence_classify <reviewed_head>
      <current_head>` returning one of `current`, `not-current`, or
      `not-reported`. `not-reported` when the reviewed head is empty;
      `current` when the two SHAs are equal after normalizing to the shorter
      of the two lengths (the loop compares a 40-char `headRefOid` against a
      value that reviewers may emit abbreviated); `not-current` otherwise.
- [ ] Add pure function `reviewer_loop_head_evidence_render <current_head>
      <entries…>` producing the Markdown `**Head evidence:**` block, and
      interpolate it into the summary comment body immediately before
      `${phase_section}`.
- [ ] Add pure function `reviewer_loop_head_evidence_json <current_head>
      <entries…>` producing the `reviewed_heads` array, and thread it into
      `reviewer_loop_history_build_entry` as a new `--argjson reviewedHeads`
      parameter following the existing `current_run_id` convention (set by the
      caller in a global, not appended to the positional list).
- [ ] Emit two new top-level key=value pairs on the loop's stdout contract next
      to the existing aggregate keys: `LOCAL_AI_REVIEWED_HEAD` (the reviewed
      head reported by the `local-ai-reviewer` platform, empty when the platform
      did not run) and `LOCAL_AI_HEAD_CURRENT` (`1` when the classification is
      `current`, `0` when `not-current`, empty when `not-reported`).
- [ ] Document both new keys in the `--help` usage block so the contract stays
      discoverable from the script itself.

`scripts/development-workflow/item-completion-self-check.sh` (shell contract:
`bash`):

- [ ] Add a `pull_request.local_reviewer_head` row derived from the newest
      reviewer-loop summary comment. `verified` when the ledger's newest entry
      records the `local-ai-reviewer` reviewed head equal to the live
      `headRefOid`; `discrepancy` when it records a different SHA;
      `unavailable_optional` when the platform is not configured or the ledger
      predates this field; `unavailable_required` when
      `--require-review-summary true` is set and the ledger is unreadable.
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
      — add one bullet under *Conditions for `ready-for-human-review`*: when
      `local-ai-reviewer` is a configured platform and Step 7 returned `clean`,
      `LOCAL_AI_HEAD_CURRENT` must be `1`. `LOCAL_AI_HEAD_CURRENT=0` is
      not-current evidence and blocks the label until Step 7 is re-run on the
      live head. An empty value (platform not configured, or it reported no
      head) does not block, and the reason must be named in the runner summary.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      — extend the readiness checklist so the same condition is enforced where
      Check 0.6 already enforces `POST_CLEAN_HEAD_SHA`, and add the reviewed-head
      row to the Work Item Runner summary fields.

---

## Testing Strategy

**Test types**: Unit (shell harness), plus the smoke test runbook.

**Key scenarios to test**:

1. `reviewer_loop_head_evidence_classify` returns `current` for identical SHAs —
   maps to brief scope bullet 1 (show current PR head and reviewed head).
2. It returns `current` when one side is an abbreviation of the other, and
   `not-current` for a same-length-prefix mismatch — guards the normalization
   from turning a real mismatch into a false pass.
3. It returns `not-reported` for an empty reviewed head, distinct from
   `not-current` — maps to scope bullet 2 (mismatch is marked, absence is not
   silently treated as a mismatch).
4. `reviewer_loop_head_evidence_render` prints one row per platform with the
   classification token, and prints the current PR head once — scope bullet 1.
5. `reviewer_loop_head_evidence_json` emits a `reviewed_heads` array whose
   entries carry `platform`, `reviewed_head`, and `state`, and an empty array
   when no platform reported a head — supports #1651 and #1657 downstream.
6. A ledger entry written without `reviewed_heads` still parses through
   `reviewer_loop_history_payload_from_existing` — backward compatibility of the
   `v1` schema.
7. `LOCAL_AI_HEAD_CURRENT=0` is emitted when the local reviewer's reviewed head
   differs from the live head — scope bullet 3 (block readiness claims on a
   stale local clean result).
8. `item-completion-self-check.sh` reports `discrepancy` for
   `pull_request.local_reviewer_head` when the ledger's newest local reviewed
   head is an ancestor of the live head, and `verified` when they match — scope
   bullet 3 at the report-evidence layer.

**Files**:

- `scripts/development-workflow/tests/test-pr-review-loop.sh` — scenarios 1–6,
  added as new cases in the existing `HARNESS_MODE=1` harness.
- `scripts/development-workflow/tests/test-local-ai-reviewer-pr-review-loop-dispatch.sh`
  — scenario 7, next to the existing dispatch assertions.
- `scripts/development-workflow/tests/test-item-completion-self-check.sh` —
  scenario 8.

No `# covers:` header edits are needed: all three suites already declare or
imply coverage of the two scripts this plan changes. `test-pr-review-loop.sh`
covers `pr-review-loop.sh` by naming convention, and the dispatch suite declares
both scripts explicitly.

**Smoke test runbook**:
`docs/testing/workflow/1648-reviewer-loop-current-head-evidence.smoke-test.md`

**Regression suite**: The repository's regression surface is the
`workflow-tests.yml` harness selection described above; the three suites listed
are the regression coverage for this change. No separate regression spec exists
to update.

### Parser-risk addendum

Applicable — `reviewer_loop_head_evidence_classify` compares two
externally-supplied strings and normalizes length.

- **Edge-case enumeration**: equal 40-char SHAs; 7-char abbreviation vs 40-char
  full SHA with matching prefix; 7-char abbreviation vs 40-char full SHA with a
  differing prefix; empty reviewed head; empty current head; a synthetic
  `unknown-<epoch>-<pid>-<rand>` placeholder produced by
  `reviewer_loop_history_current_head_sha` when the live head lookup fails;
  mixed-case hex.
- **Unit test mapping**: each edge case above gets one case in
  `test-pr-review-loop.sh`. The synthetic-placeholder case must classify as
  `not-current`, never `current`, so a failed head lookup can never manufacture
  a passing readiness signal.
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
| Ledger fixture without `reviewed_heads` | A `reviewer_loop_history.v1` payload with one entry that predates this change, to prove backward compatibility (scenario 6) | inline heredoc in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Ledger fixture with a stale local head | Newest entry recording `local-ai-reviewer` reviewed head `aaaaaaa…` while the mocked `gh pr view` returns `bbbbbbb…` (scenario 8) | inline mock in `scripts/development-workflow/tests/test-item-completion-self-check.sh` |

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
| SHA-length normalization turns a genuine mismatch into a false `current` | Med | High — it would defeat the gate this item exists to build | Compare only over the shorter length **and** require the shorter value to be a non-empty prefix of the longer; scenario 2 pins both the pass and the fail case |
| A failed live-head lookup yields the synthetic `unknown-…` placeholder and is compared against a real SHA | Med | Med — could produce a confusing `not-current` or, if mishandled, a false `current` | The placeholder is never hex-equal to a SHA, so it classifies `not-current`; the parser-risk addendum pins this as an explicit test case |
| Adding a field to `reviewer_loop_history.v1` breaks a reader that validates the entry shape | Low | High — a broken ledger read is fail-closed and would stall every reviewer loop | Field is additive and optional; scenario 6 asserts an entry without it still parses through `reviewer_loop_history_payload_from_existing` |
| The new readiness condition blocks PRs in repositories that do not configure `local-ai-reviewer` | Low | High — it would stall downstream consumers of this template | The condition applies only when the platform is in the resolved list; an empty `LOCAL_AI_HEAD_CURRENT` never blocks, and scenario 7 covers the not-configured path |
| The summary comment grows past what reviewers read | Low | Low | The head-evidence block is one line per configured platform plus one current-head line, in the same style as the existing compare-mode block |

---

## Code Samples

```bash
# Illustrative — adapt during implementation.
# Classify one reviewer's reviewed head against the live PR head.
reviewer_loop_head_evidence_classify() {
  local reviewed="$1"
  local current="$2"
  local short long

  if [ -z "$reviewed" ]; then
    printf 'not-reported\n'
    return 0
  fi
  if [ -z "$current" ]; then
    printf 'not-current\n'
    return 0
  fi

  # Compare over the shorter length so an abbreviated SHA still matches, and
  # require a genuine prefix so a same-length mismatch cannot pass.
  short="$reviewed"
  long="$current"
  if [ "${#short}" -gt "${#long}" ]; then
    short="$current"
    long="$reviewed"
  fi

  case "$long" in
    "$short"*) printf 'current\n' ;;
    *)         printf 'not-current\n' ;;
  esac
}
```

Rendered summary block, illustrative:

```markdown
**Head evidence:** current PR head `b3f19c2e`

- local-ai-reviewer: reviewed `b3f19c2e` — current
- pr-agent: reviewed `9a41d0b7` — not-current
- codex-github: not-reported
```

---

## Implementation Order

1. Add the three pure functions
   (`reviewer_loop_head_evidence_classify`, `…_render`, `…_json`) to
   `scripts/development-workflow/pr-review-loop.sh` near the existing
   `reviewer_loop_history_*` helpers. **Verify**: source the script with
   `HARNESS_MODE=1` and call each function directly; confirm the returned tokens
   match the enumerated edge cases.
2. Populate `platform_reviewed_heads` in the per-platform result block, next to
   the existing `platform_result_tokens+=(...)` line. **Verify**: run the
   dispatch suite and confirm the array is populated for a mocked
   `local-ai-reviewer` run.
3. Interpolate the `**Head evidence:**` block into the summary comment body
   before `${phase_section}`. **Verify**: run the harness case that builds the
   comment body and read the output; confirm the block appears once, with one
   row per configured platform.
4. Thread `reviewed_heads` into `reviewer_loop_history_build_entry` via a
   caller-set global, following the `current_run_id` convention already
   documented in that function. **Verify**: build an entry in the harness and
   pipe it through `jq` to confirm the array shape.
5. Emit `LOCAL_AI_REVIEWED_HEAD` and `LOCAL_AI_HEAD_CURRENT` on the loop's
   stdout contract and document both in `--help`. **Verify**: run
   `pr-review-loop.sh --help` and confirm both keys are described.
6. Add the `pull_request.local_reviewer_head` row to
   `scripts/development-workflow/item-completion-self-check.sh`. **Verify**: run
   the self-check suite and read the emitted Markdown section; confirm the row
   appears with the expected status for each mocked ledger.
7. Update
   `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`
   and
   `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
   per **Documentation Updates**.
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

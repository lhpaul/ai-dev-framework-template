# Tighten Small-Finding Terminal Policy — Implementation Plan

**Spec**: None — Refactor item. Source brief:
[issue #1652](https://github.com/lhpaul/ai-dev-framework-template/issues/1652)
(epic [#1647](https://github.com/lhpaul/ai-dev-framework-template/issues/1647))
**Smoke test runbook**:
[1652-small-finding-terminal-policy.smoke-test.md](../../../testing/workflow/1652-small-finding-terminal-policy.smoke-test.md)

---

## Summary

**Approach**: `reviewer_loop_path_is_non_shipped_artifact` classifies a finding
as "small" purely by its path, and `docs/*` and `*.md` are both on the
non-shipped list. In a repository whose product *is* its documentation — specs,
plans, protocols, `REVIEW.md`, the best-practices set — that makes every finding
on the shipped artifact small by construction. Two consecutive such rounds with
no unresolved threads then flip the aggregate to `clean` with reason
`small_findings_terminal`, and the PR proceeds carrying live blocking findings.

This plan makes the classification depend on **what the finding is about**, not
only where it lives. It moves this repository's normative documents onto the
shipped side, adds a contract-surface test that keeps a finding non-small
wherever it lives when it touches acceptance criteria, decision gates, matrices,
parser behavior or scope, and requires the counted rounds to have been on the
current head before the terminal rule may mark clean.

**Estimated complexity**: M

**Rationale**: The change is concentrated in one classifier, one guard, and the
counting call site, all in `pr-review-loop.sh`. What makes it more than small is
that it *loosens a stop condition*: getting it wrong in the permissive direction
reproduces the bug, and in the restrictive direction leaves the loop unable to
terminate on genuinely cosmetic findings. Both directions need planted proofs.

**Dependencies**: **#1648 must be merged to
`develop-internal-reviewer-effectiveness` before this item's implementation PR
opens.** The current-head requirement in the brief's third scope bullet is the
per-reviewer head evidence #1648 introduces. The plan PRs are independent; only
the implementation is ordered.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short origin/develop-internal-reviewer-effectiveness` | `7998d43d` |
| The classifier is path-only | `sed -n '6758,6774p' scripts/development-workflow/pr-review-loop.sh` | `reviewer_loop_path_is_non_shipped_artifact` matches on two `case` blocks over the path string alone; nothing about the finding's content reaches it |
| This repository's normative docs are all classified non-shipped | Sourced the loop with `HARNESS_MODE=1` and called the classifier on six real paths | `docs/specs/developments/**/1_*_specs.md`, `docs/workflow/development-workflow/protocols/91-*.md`, `REVIEW.md`, `docs/best-practices/3-testing.md` and `docs/testing/workflow/*.smoke-test.md` all return non-shipped; only `scripts/development-workflow/pr-review-loop.sh` returns shipped |
| Terminal rule requires two rounds and zero threads | `sed -n '9276,9290p' scripts/development-workflow/pr-review-loop.sh` | The `elif` fires only when `aggregate_result` is `needs_fixes`, `unresolved_thread_count` is 0, and `small_findings_only` is 1; it then flips `aggregate_result` to `clean` with `aggregate_reason=small_findings_terminal` once the consecutive count reaches the required rounds |
| Nothing checks the head of the counted rounds | Same range, plus `grep -n "small_findings" scripts/development-workflow/pr-review-loop.sh` | The consecutive count is read from the ledger by `reviewer_loop_small_findings_prior_consecutive_count`, which selects entries by `small_findings_only` and adjacency only — no head comparison anywhere in the path |
| Round count is configurable and already validated | `sed -n '6776,6787p' scripts/development-workflow/pr-review-loop.sh` | `PR_REVIEW_LOOP_SMALL_FINDINGS_STOP_ROUNDS`, default 2, range 1-999, `WARN`-and-fall-back on anything else — the convention this plan follows for its own new inputs |
| **Live incidence in this epic** | `grep -l "REASON=small_findings_terminal" <loop logs for #1660, #1661, #1662>` cross-referenced with `BLOCKING_COUNT` | **24 loop runs** across the three epic PRs exited `RESULT=clean` with reason `small_findings_terminal` **while carrying live blocking findings** — 5 on #1660, 18 on #1661, 1 on #1662 |
| Those findings were not cosmetic | The fix commits on #1661 | Findings the terminal rule cleared included a deny-list where the contract claimed fail-closed, an empty check set treated as passing, an unvalidated bound that defeated its own cap, and a gate that read its dependency's stdout keys as environment variables |

The last two rows are the justification for this item. The brief cites PR #1646;
this epic's own PRs reproduced the failure 24 times, and the findings involved
were contract defects rather than typographical ones.

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch for this item | `develop-internal-reviewer-effectiveness` | `integration-branch:internal-reviewer-effectiveness` label on #1652; Protocol 91 § Integration-branch base override | 2026-08-28, repo SHA `7998d43d` | Epic #1647 items; open PRs on this base are #1660, #1661, #1662 | `Verified` |
| Source of the current-head evidence | The per-reviewer head evidence from #1648 | #1648's implementation plan on PR #1660 | 2026-08-28, repo SHA `7998d43d` | #1648 and #1652 only | `Conflict` — see below |

**Conflict record.** The third scope bullet requires current-head verification
before the terminal rule may mark clean, and the evidence that makes "current"
decidable per reviewer does not exist on the base branch yet: #1648's plan PR
#1660 is `ready-for-human-review` and unmerged. Affected plan statements: the
current-head guard and every scenario that exercises it.

**Resolution status**: `Resolved` by sequencing. Recorded in **Dependencies** and
enforced by **Implementation Order step 0**, a hard stop before any code change.
Decision owner: LH — if #1648 is rejected or materially changed, this plan must
be revised before implementation rather than adapted during it.

---

## Layer-by-Layer Changes

### Backend / API

Not applicable — this repository ships workflow tooling, not a service.

### Shared Packages / Libraries

`scripts/development-workflow/pr-review-loop.sh` (shell contract: `bash`):

- [ ] **Move this repository's normative documents to the shipped side.** Add
      `reviewer_loop_path_is_normative_document`, matching, in this order:

      | Pattern | Why it is shipped |
      | --- | --- |
      | `REVIEW.md` | the review contract every reviewer is measured against |
      | `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `LLM_RULES.md` | the agent contracts |
      | `docs/workflow/**` | the protocols the workflow executes |
      | `docs/best-practices/**` | the rules reviewers enforce |
      | `docs/specs/developments/**` | specs and plans — the deliverable of two of the three stages |
      | `docs/testing/workflow/**` | the smoke runbooks a human executes |
      | `.ai-dev-workflow.yaml` | the configuration the loop reads |

      `reviewer_loop_path_is_non_shipped_artifact` consults this predicate first
      and returns non-shipped only when it does not match. A path that is both
      `docs/*` and normative is shipped: the normative test wins.
- [ ] **Add a contract-surface test that is independent of path.** Add
      `reviewer_loop_finding_touches_contract_surface <body>`, returning success
      when the finding's text names a contract-bearing surface. The match set is
      an explicit allow-list of surfaces, not an exclusion list of cosmetic ones:

      | Surface | Representative terms |
      | --- | --- |
      | Acceptance criteria | `acceptance criteri`, `AC-` |
      | Decision gates and matrices | `decision gate`, `decision matrix`, `matrix row`, `gate` |
      | Parser and input behavior | `parser`, `regex`, `parse`, `input surface` |
      | Scope and coverage | `scope`, `coverage matrix`, `objective`, `out of scope` |
      | Fail-closed semantics | `fail-closed`, `fail closed`, `allow-list`, `deny-list`, `vacuous` |
      | State and status models | `state`, `status`, `enum`, `transition` |
      | Telemetry and contracts | `telemetry`, `contract`, `stdout key`, `emitted` |
      | Proof obligations | `planted-violation`, `planted violation`, `proof` |

      A finding whose body matches any row is **non-small regardless of its
      path**. The list is an allow-list on purpose: a finding this test does not
      recognise falls through to the path rule, which is the existing behavior,
      so the change can only make the loop stricter and never more permissive.
- [ ] Make `reviewer_loop_all_paths_non_shipped` take the finding bodies
      alongside the paths, and return failure when **any** finding either has a
      shipped path or touches a contract surface. Rename it
      `reviewer_loop_all_findings_are_small` so the name states what it decides;
      keep a thin wrapper under the old name only if an existing caller outside
      this change set needs it, and record in the PR whether one did.
- [ ] **Require the counted rounds to be on the current head.** The terminal
      rule may mark clean only when every ledger round it counted recorded a
      head equal to `loop_head_sha`. Extend
      `reviewer_loop_small_findings_prior_consecutive_count` to take the current
      head and stop counting at the first entry whose head differs, so a round
      on an older commit ends the consecutive run rather than extending it.
- [ ] **Fail closed when the head of a counted round cannot be established.** An
      entry whose recorded head is absent, empty, or the synthetic
      `unknown-<epoch>-<pid>-<rand>` placeholder ends the consecutive run. It is
      not treated as matching, and it is not skipped over: a round whose head is
      unknown cannot be shown to be current, and the terminal rule exists to be
      shown, not assumed.
- [ ] Emit `SMALL_FINDINGS_BLOCKED_BY` naming why a terminal stop did **not**
      happen when the rule would otherwise have fired: one of
      `shipped_path`, `contract_surface`, `stale_head`, or `head_unknown`. Empty
      when the rule fired or was never close to firing. Without it, a maintainer
      cannot tell a loop that is correctly refusing to terminate from one that is
      simply still finding things.
- [ ] Extend the reviewer-loop summary's small-findings line to name the
      contract surface or shipped path that kept the round non-small, so the
      reason is visible on the PR rather than only in the loop's stdout.
- [ ] Document the new predicate, the contract-surface list, the current-head
      requirement, and `SMALL_FINDINGS_BLOCKED_BY` in the `--help` usage block.

### Frontend / UI

Not applicable — no user interface in this repository.

### Infrastructure / Configuration

- [ ] No `.ai-dev-workflow.yaml` change.
      `PR_REVIEW_LOOP_SMALL_FINDINGS_STOP_ROUNDS` keeps its current name,
      default and validation; this plan changes what counts as a qualifying
      round, not how many are required.

### Documentation

- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
      — document the tightened rule: that normative documents are shipped
      artifacts in this repository, that a contract-surface finding is non-small
      wherever it lives, that counted rounds must be on the current head, that an
      unknown head ends the run, and what `SMALL_FINDINGS_BLOCKED_BY` reports.
- [ ] `REVIEW.md` — add one line under the review contract stating that a
      finding on a spec, plan, protocol or the review contract itself is never
      small, so a reviewer knows the classification without reading the loop.

---

## Testing Strategy

**Test types**: Unit (shell harness), plus the smoke test runbook.

**Key scenarios to test**:

1. `reviewer_loop_path_is_normative_document` matches each of the seven patterns
   in the table, one case per row, and rejects `scripts/development-workflow/pr-review-loop.sh`,
   `package.json`, and `docs/project/1-business-domain.md`.
2. `reviewer_loop_path_is_non_shipped_artifact` now returns **shipped** for
   `docs/specs/developments/x/1_x_specs.md`, `REVIEW.md`,
   `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`,
   `docs/best-practices/3-testing.md` and `docs/testing/workflow/x.smoke-test.md`
   — the five paths the Verification Log records as non-shipped today.
3. It still returns **non-shipped** for `docs/project/1-business-domain.md`,
   `tests/fixtures/x.json`, `__snapshots__/x.snap` and `CHANGELOG.md`, so the
   change did not make every documentation finding blocking.
4. `reviewer_loop_finding_touches_contract_surface` matches one case per row of
   the contract-surface table, and rejects three cosmetic bodies: a typo report,
   a trailing-whitespace report, and a heading-capitalisation report.
5. A finding on a non-shipped path whose body touches a contract surface is
   **not** small — this is the path-independent half of the rule.
6. A finding on a non-shipped path with a cosmetic body **is** small, so the
   loop can still terminate on genuinely cosmetic tails.
7. `reviewer_loop_all_findings_are_small` returns failure when any one of three
   findings is non-small, and success only when all three are small.
8. The consecutive count stops at the first ledger entry whose recorded head
   differs from the current head: with two prior small rounds on an older head
   and one on the current head, the count is 1, not 3.
9. The consecutive count stops at an entry whose head is absent, empty, or a
   synthetic `unknown-…` placeholder — three cases, each ending the run rather
   than being skipped.
10. With the required rounds reached but the most recent counted round on a
    stale head, the terminal rule does **not** fire and
    `SMALL_FINDINGS_BLOCKED_BY=stale_head`.
11. `SMALL_FINDINGS_BLOCKED_BY` reports `shipped_path` and `contract_surface`
    for their respective causes, `head_unknown` for the placeholder case, and is
    **empty** when the rule fired.
12. **The #1661 regression.** Replay a ledger built from PR #1661's actual
    history — consecutive rounds whose only findings were on
    `docs/specs/developments/**` with bodies naming fail-closed semantics,
    decision-matrix rows, and acceptance criteria — and assert the terminal rule
    does **not** fire, where today it fires on round two.
13. **The cosmetic counter-case.** Replay the same ledger shape with bodies
    naming only a trailing space and a heading capitalisation, and assert the
    terminal rule **does** fire, so the tightening did not disable the mechanism.
14. A ledger entry written before this change, carrying no head on its
    small-findings entries, ends the consecutive run rather than being counted —
    backward compatibility in the fail-closed direction.

**Files**:

- `scripts/development-workflow/tests/test-pr-review-loop.sh` — scenarios 1
  through 11 and 14, as new cases in the existing `HARNESS_MODE=1` harness.
- `scripts/development-workflow/tests/test-small-finding-terminal-policy.sh` —
  a new suite for scenarios 12 and 13, the two replay regressions, which need
  their own ledger fixtures. It must declare:

  ```text
  # covers: scripts/development-workflow/pr-review-loop.sh
  # covers: docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md
  ```

  Both lines are required. In `select-test-suites.sh` the naming-convention
  fallback runs only when a suite declares nothing (`declared=0`), and the
  convention would map this suite to a
  `scripts/development-workflow/small-finding-terminal-policy.sh` that does not
  exist — so without an explicit declaration it would run only when the test
  file itself changed.

**Smoke test runbook**:
`docs/testing/workflow/1652-small-finding-terminal-policy.smoke-test.md`

**Regression suite**: the `workflow-tests.yml` harness selection; the two suites
above are the regression coverage for this change.

### Planted-violation proofs (mandatory before `ready-for-human-review`)

This plan materially modifies an automated guard, so `REVIEW.md` §
Planted-violation proof applies and the pure-refactor exemption does not. Two
demonstrated runs per proof, each citing a concrete file and line. Note that
four of the six plant the **permissive** direction — reproducing the original
bug — because that is the direction this item exists to close.

| # | Violation to plant | Where | Check that must fail, then pass |
| --- | --- | --- | --- |
| P1 | Remove `docs/specs/developments/**` from the normative-document list | a scratch copy of the predicate | scenario 2 fails and scenario 12 fires the terminal rule on a spec contract finding; restoring the pattern passes |
| P2 | Make the contract-surface test consult the path as well, so a non-shipped path short-circuits it | a scratch copy of the predicate | scenario 5 fails, because a contract finding on a `docs/` path becomes small again; restoring the path-independent test passes |
| P3 | Turn the contract-surface allow-list into a deny-list of cosmetic terms | same scratch copy | scenario 4's three cosmetic bodies still pass, but a contract body using none of the listed cosmetic terms is classified small — the failure mode the allow-list exists to prevent; restoring the allow-list passes |
| P4 | Drop the current-head comparison from the consecutive count | a scratch copy of the counter | scenario 8 fails, because rounds on an older head extend the run; restoring the comparison passes |
| P5 | Treat an entry with an absent or placeholder head as matching the current head | same scratch copy | scenario 9 fails in all three cases, because an unprovable head extends the run; restoring the fail-closed branch passes |
| P6 | Over-tighten: make every `docs/` path shipped, dropping the non-shipped patterns entirely | a scratch copy of the predicate | scenarios 3, 6 and 13 fail, because the loop can no longer terminate on a genuinely cosmetic documentation tail; restoring the narrowed list passes |

P6 is the restrictive-direction proof, and it is not optional. A tightening
that removes the mechanism entirely would pass every other proof here while
leaving the loop unable to terminate on cosmetic findings, which is a different
defect rather than a fix.

### Parser-risk addendum

Applicable — `reviewer_loop_finding_touches_contract_surface` scans
externally-supplied finding text.

- **Edge-case enumeration**: a body containing a listed term as a substring of a
  longer word (`gates` in `delegates`, `scope` in `microscope`); a term in a
  different case (`Acceptance Criteria`, `FAIL-CLOSED`); a term inside a fenced
  code block quoted from the diff; a term inside a URL; an empty body; a body of
  only whitespace; a body containing a listed term in a quoted *negation*
  (\"this is not a decision gate\"); a multi-line body where the term appears
  only on the last line.
- **Required behavior**: matching is case-insensitive and on word boundaries, so
  `delegates` does not match `gate` and `microscope` does not match `scope`. A
  term inside a code fence or URL still matches — a finding that quotes the
  contract it is about is still about the contract, and the failure direction of
  matching too readily here is a round that stays non-small, which is safe. An
  empty or whitespace-only body does not match and falls through to the path
  rule. The negation case matches; the classifier does not attempt to read
  intent, and treating a body that discusses a decision gate as contract-bearing
  is the conservative reading.
- **Unit test mapping**: each case above gets one case in
  `test-pr-review-loop.sh`, asserting match or no-match explicitly. The
  substring cases and the empty-body case are the negative tests.

### Concurrent-event-source addendum

Not applicable. Both predicates are pure functions of their arguments, and the
counting change reads a ledger the sequential loop already reads at the same
point. No listeners, timers, or shared mutable state are introduced.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Path classification fixture | The five paths that change disposition and the four that must not, driving scenarios 1-3 | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Contract-surface body fixture | One body per row of the contract-surface table, three cosmetic bodies, and the eight parser edge cases | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Head-comparison ledger fixture | Ledger payloads with prior small rounds on an older head, on the current head, and with absent, empty and placeholder heads — driving scenarios 8, 9, 10 and 14 | inline heredocs in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| #1661 replay ledger | A `reviewer_loop_history.v1` payload reproducing PR #1661's consecutive small-findings rounds, with the real finding bodies naming fail-closed semantics, matrix rows and acceptance criteria | inline heredoc in `scripts/development-workflow/tests/test-small-finding-terminal-policy.sh` |
| Cosmetic replay ledger | The same ledger shape with cosmetic bodies only, driving scenario 13 | inline heredoc in `scripts/development-workflow/tests/test-small-finding-terminal-policy.sh` |

No repository fixture files are added; both suites build their fixtures inline
and require no network access.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
      — the tightened rule, the current-head requirement, the unknown-head
      behavior, and `SMALL_FINDINGS_BLOCKED_BY`.
- [ ] `REVIEW.md` — one line stating that a finding on a spec, plan, protocol or
      the review contract itself is never small.
- [ ] `AGENTS.md` — no change. It does not describe reviewer-loop internals.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The tightening removes the terminal mechanism entirely | Med | High — every PR with a cosmetic documentation tail would loop to its cycle cap | The non-shipped list is narrowed, not deleted: `docs/project/**`, fixtures, snapshots and `CHANGELOG.md` stay non-shipped. Scenarios 3, 6 and 13 assert the mechanism still fires on cosmetic findings, and proof P6 plants the over-tightening specifically |
| The contract-surface test is written as a deny-list of cosmetic terms | Med | High — an unrecognised contract finding would be classified small, reproducing the bug | The test is an explicit allow-list of surfaces, and a body it does not recognise falls through to the path rule rather than being declared cosmetic; proof P3 plants the inversion |
| Word-boundary matching is missed and substrings match | Med | Med — `delegates` matching `gate` would make almost every finding non-small, effectively disabling the terminal rule by accident | Case-insensitive word-boundary matching is stated in the parser-risk addendum with `delegates`/`gate` and `microscope`/`scope` as named negative tests |
| An old ledger without head data silently counts as current | Med | High — the current-head requirement would be inert on exactly the PRs that predate it | An absent, empty or placeholder head ends the consecutive run; scenarios 9 and 14 and proof P5 pin all three forms |
| A maintainer cannot tell a correctly-refusing loop from a still-failing one | Med | Med | `SMALL_FINDINGS_BLOCKED_BY` names the cause, and the summary line names the contract surface or shipped path; scenario 11 pins all four values and the empty case |
| The rename of `reviewer_loop_all_paths_non_shipped` breaks an unseen caller | Low | Med | The PR records whether any caller outside this change set exists; a thin wrapper is kept only if one does |

---

## Code Samples

The snippet uses Bash `case` and `[[ ]]`, matching `pr-review-loop.sh`'s own
`#!/usr/bin/env bash` shebang; its contract is `bash`, not `bash-zsh`.

<!-- workflow-shell-contract: bash -->

```bash
# Illustrative — adapt during implementation.

# This repository's product is its documentation, so its normative documents
# are shipped artifacts. Checked before the non-shipped patterns.
reviewer_loop_path_is_normative_document() {
  case "$1" in
    REVIEW.md|AGENTS.md|CLAUDE.md|GEMINI.md|LLM_RULES.md|.ai-dev-workflow.yaml)
      return 0 ;;
    docs/workflow/*|docs/best-practices/*|docs/specs/developments/*|docs/testing/workflow/*)
      return 0 ;;
  esac
  return 1
}

# Allow-list of contract-bearing surfaces. A body this does not recognise falls
# through to the path rule, so the test can only make the loop stricter.
reviewer_loop_finding_touches_contract_surface() {
  local body="$1"
  [ -n "${body//[[:space:]]/}" ] || return 1
  # Word-boundary, case-insensitive: "delegates" must not match "gate".
  printf '%s' "$body" | grep -Eqi '\b(acceptance criteri[ao]n?|AC-[0-9]|decision (gate|matrix)|matrix row|gate|parser|regex|parse|input surface|scope|coverage matrix|objective|out of scope|fail.closed|allow.list|deny.list|vacuous|state|status|enum|transition|telemetry|contract|stdout key|emitted|planted.violation|proof)\b'
}
```

---

## Implementation Order

0. **Hard stop — dependency check.** Confirm #1648 is merged into
   `develop-internal-reviewer-effectiveness`. **Verify**:
   `gh pr view 1660 --json state,baseRefName` returns `MERGED` with the
   integration branch as base. If not, stop and report — do not implement the
   current-head requirement against a guessed contract.
1. Add `reviewer_loop_path_is_normative_document` and consult it first from
   `reviewer_loop_path_is_non_shipped_artifact`. **Verify**: scenarios 1-3 — the
   five paths flip to shipped and the four control paths do not.
2. Add `reviewer_loop_finding_touches_contract_surface` with case-insensitive
   word-boundary matching. **Verify**: scenario 4 and every row of the
   parser-risk edge-case list, including the `delegates`/`gate` negative.
3. Rename `reviewer_loop_all_paths_non_shipped` to
   `reviewer_loop_all_findings_are_small`, take finding bodies alongside paths,
   and fail when any finding is shipped-path **or** contract-surface.
   **Verify**: scenarios 5-7. Record in the PR whether any caller outside this
   change set required the old name.
4. Extend `reviewer_loop_small_findings_prior_consecutive_count` to take the
   current head and stop at the first differing, absent, empty or placeholder
   head. **Verify**: scenarios 8, 9 and 14.
5. Wire the current-head requirement into the terminal decision and emit
   `SMALL_FINDINGS_BLOCKED_BY`. **Verify**: scenarios 10 and 11.
6. Extend the summary's small-findings line to name the blocking surface or
   path. **Verify**: read the rendered line for one `contract_surface` case and
   one `shipped_path` case.
7. Add the two replay suites and their ledger fixtures, including both
   `# covers:` lines on the new suite. **Verify**: scenarios 12 and 13, and that
   `select-test-suites.sh` selects the new suite for a change touching only
   `pr-review-loop.sh`.
8. Update
   `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
   and `REVIEW.md` per **Documentation Updates**. **Verify**: both describe the
   same rule, the same current-head requirement and the same four
   `SMALL_FINDINGS_BLOCKED_BY` values.
9. Document the new behavior in the `--help` usage block. **Verify**: run
   `pr-review-loop.sh --help` and confirm the predicate, the contract-surface
   list, the current-head requirement and `SMALL_FINDINGS_BLOCKED_BY` appear.
10. Produce the six planted-violation proofs (P1-P6) and record them in the PR
    under a `Planted-Violation Proofs` heading. **Verify**: each shows two runs
    at a concrete file and line — failing with the violation planted, passing
    once removed. P6 is the restrictive-direction proof and is not optional.
11. Run `shellcheck` on `scripts/development-workflow/pr-review-loop.sh` and
    `markdownlint-cli2` on the two changed documentation files, this plan and
    the runbook. **Verify**: both tools exit 0 on every file named here.
12. Add a changelog fragment
    `changelog.d/1652.changed.small-finding-terminal-policy.md` containing
    exactly:

    ```markdown
    - **Tighten the small-finding terminal policy** (#1652): findings on specs, plans, protocols and the review contract are no longer classified as small, a finding that touches a contract surface is never small wherever it lives, and the terminal rule now requires its counted rounds to be on the current head.
    ```

13. Update project docs per **Documentation Updates** above (step 8 covers them;
    no other project doc is affected).

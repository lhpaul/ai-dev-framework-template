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
that it changes a **stop condition**, and both directions of error are real:
too permissive reproduces the bug the item exists to close, and too restrictive
leaves the loop unable to terminate on genuinely cosmetic findings. Every change
here makes the terminal rule strictly harder to reach; nothing about it is
loosened. Both directions need planted proofs.

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
| **Live incidence in this epic** — *not reproducible from repository files* | Coordinator's transient `pr-review-loop.sh` stdout captures for PRs #1660, #1661 and #1662, filtered for `REASON=small_findings_terminal` together with a non-zero `BLOCKING_COUNT` | **24 loop runs** reported to have exited `RESULT=clean` with reason `small_findings_terminal` while carrying live blocking findings — 5 on #1660, 18 on #1661, 1 on #1662. **Unverified — the implementer must confirm before proceeding.** |
| Those findings were not cosmetic — *not reproducible from repository files* | The `Automated Fix` comments on PR #1661 | Findings the terminal rule cleared are reported to have included a deny-list where the contract claimed fail-closed, an empty check set treated as passing, an unvalidated bound that defeated its own cap, and a gate that read its dependency's stdout keys as environment variables. **Unverified — the implementer must confirm before proceeding.** |

**Provenance of the last two rows.** They come from loop stdout captured during
this epic's own runs, which is transient and lives in neither the repository nor
this branch. They are recorded because they are the strongest available evidence
that the brief's premise generalises beyond PR #1646, and they are marked
unverified because a reviewer reading only this repository cannot reproduce
them. Both are confirmable without special access: the reviewer-loop summary
comments and their embedded `reviewer_loop_history.v1` ledgers on PRs #1660,
#1661 and #1662 carry `small_findings_only`, `small_findings_stop` and per-round
blocking counts, so `gh api repos/lhpaul/ai-dev-framework-template/issues/<n>/comments`
re-derives both rows.

**Nothing in this plan depends on those two rows being true.** The design
follows from the first five rows, which are reproducible from the repository
alone: the classifier is path-only, and every normative document in this
repository currently classifies as non-shipped. The incidence rows establish
urgency, not correctness.

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
      `reviewer_loop_finding_touches_contract_surface <body>`. It returns
      success when the finding's text names a contract-bearing surface, **and
      prints the identity of the surface it matched** — the `Surface` value from
      the table below, lowercased with every space **and hyphen** replaced by an
      underscore — so `Fail-closed semantics` becomes `fail_closed_semantics`
      and `Acceptance criteria` becomes `acceptance_criteria`. The identities
      are fixed strings, listed in full in the illustrative array below, so the
      derivation rule is a description of how they were formed rather than
      something the implementation recomputes. On no match it prints
      nothing and returns failure. The printed identity is what the summary
      renderer needs to name *which* surface kept the round non-small; a bare
      boolean would leave it with nothing to render. When a body matches more
      than one surface, the identity printed is the first matching row in table
      order, so the output is deterministic.

      The match set is an explicit allow-list of surfaces, not an exclusion list
      of cosmetic ones:

      | Surface | Matched terms |
      | --- | --- |
      | Acceptance criteria | `acceptance criterion`, `acceptance criteria`, `AC-<digit>` |
      | Decision gates and matrices | `decision gate`, `decision matrix`, `matrix row`, `readiness gate`, `gate condition`, `gating` |
      | Parser and input behavior | `parser`, `regex`, `input surface`, `word boundary` |
      | Scope and coverage | `out of scope`, `in scope`, `scope creep`, `coverage matrix`, `brief objective` |
      | Fail-closed semantics | `fail-closed`, `fail closed`, `allow-list`, `deny-list`, `vacuous` |
      | State and status models | `state machine`, `state table`, `evidence state`, `valid transition`, `status label`, `status transition` |
      | Telemetry and contracts | `telemetry`, `stdout key`, `key=value contract`, `output contract` |
      | Proof obligations | `planted-violation`, `planted violation`, `proof obligation` |

      **Every term is a phrase or a qualified form, never a bare common word.**
      An earlier draft listed `gate`, `scope`, `state`, `status`, `proof`,
      `parse` and `contract` on their own. Those appear constantly in ordinary
      prose — "the heading state is inconsistent", "a typo in the scope
      section" — so they would have matched cosmetic findings too and made
      almost everything non-small, disabling the terminal rule from the
      restrictive side while appearing to tighten it. The bare forms are
      excluded deliberately, and scenario 6a tests cosmetic bodies that contain
      each of them.

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
- [ ] **Require the counted rounds to be on the current head — including the
      round now being decided.** The consecutive run is `prior entries + 1`, and
      the `+ 1` is this round, so checking only the prior entries would leave
      the deciding round unverified. Two changes:
      1. Extend `reviewer_loop_small_findings_prior_consecutive_count` to take
         the current head and stop counting at the first entry whose head
         differs, so a round on an older commit ends the run rather than
         extending it.
      2. Before the `+ 1`, require the **current** round's findings to have been
         produced on `loop_head_sha`, using the per-reviewer reviewed-head
         evidence #1648 introduces. A round can aggregate blocking findings from
         **several** platforms, so the requirement is per contributor, not per
         round: **every** reviewer that contributed at least one counted finding
         must report a reviewed head equal to `loop_head_sha`. If any single
         contributor reports a different head, or reports none, the current
         round does not contribute and the terminal rule does not fire —
         `stale_head` and `head_unknown` respectively, naming the platform in
         the summary line. Requiring all of them rather than any of them is the
         fail-closed direction: one contributor's current-head evidence says
         nothing about what another contributor was looking at. Without this the
         rule could terminate on a round whose findings describe a commit that
         is no longer the head — the exact staleness the brief's second scope
         bullet names.
- [ ] **Fail closed when the head of a counted round cannot be established.** An
      entry whose recorded head is absent, empty, or the synthetic
      `unknown-<epoch>-<pid>-<rand>` placeholder ends the consecutive run. It is
      not treated as matching, and it is not skipped over: a round whose head is
      unknown cannot be shown to be current, and the terminal rule exists to be
      shown, not assumed.
- [ ] **The counter reports why it stopped, not only how far it counted.**
      `SMALL_FINDINGS_BLOCKED_BY` has to distinguish `stale_head` from
      `head_unknown`, and a bare count cannot. The counter emits two values —
      the count, and a stop reason from a closed set:

      | Stop reason | Meaning |
      | --- | --- |
      | `exhausted` | the walk reached the end of the ledger with every entry matching; the count is not limited by a head mismatch |
      | `not_small` | the walk stopped at an entry that was not a small-findings round, which is the pre-existing behavior |
      | `stale_head` | the walk stopped at an entry whose recorded head differs from `loop_head_sha` |
      | `head_unknown` | the walk stopped at an entry whose head is absent, empty, or a synthetic placeholder |

      The terminal decision maps `stale_head` and `head_unknown` straight to
      `SMALL_FINDINGS_BLOCKED_BY` when they are what prevented the threshold
      being reached. `exhausted` and `not_small` are not blocking reasons — they
      describe an ordinary short run — and leave `SMALL_FINDINGS_BLOCKED_BY`
      empty.
- [ ] Emit `SMALL_FINDINGS_BLOCKED_BY` naming why a terminal stop did **not**
      happen when the rule would otherwise have fired: one of
      `shipped_path`, `contract_surface`, `stale_head`, or `head_unknown`. Empty
      when the rule fired, and empty when the run was simply short
      (`exhausted` or `not_small`), since neither is a blocking reason. Without
      it, a maintainer cannot tell a loop that is correctly refusing to
      terminate from one that is simply still finding things.
- [ ] **Define precedence — some causes can co-occur, and two of them never
      can.** The four causes fall into two groups that are **mutually exclusive
      by construction**, because they are decided at different stages:

      - **Content causes** — `shipped_path` and `contract_surface` — say the
        round's findings are *not small*. They are evaluated first.
      - **Currency causes** — `stale_head` and `head_unknown` — are only
        reachable when the findings *are* all small, since the head of a counted
        round is only asked about once the round qualifies as a small-findings
        round at all.

      A content cause and a currency cause therefore cannot both be present:
      if any finding is non-small the round never reaches the head check, and if
      the round reaches the head check no finding was non-small. There is no
      content-versus-currency boundary to order, and the plan does not invent
      one. Precedence is needed **within** each group, where co-occurrence is
      real:

      | Group | Precedence | Value | Chosen when |
      | --- | --- | --- | --- |
      | Content | 1 | `shipped_path` | any counted finding has a shipped path |
      | Content | 2 | `contract_surface` | no shipped path, but any counted finding touches a contract surface |
      | Currency | 1 | `stale_head` | a counted round or contributor reports a head other than `loop_head_sha` |
      | Currency | 2 | `head_unknown` | as above, but the head is absent, empty, or a synthetic placeholder |

      Within the content group, `shipped_path` outranks `contract_surface`
      because a shipped path is a property of the artifact and needs no reading
      of the finding text to act on. Within the currency group, `stale_head`
      outranks `head_unknown` because a known-different head is the more
      specific statement. The **summary line lists every cause present**, so
      nothing is hidden by the precedence; only the single-valued key is
      reduced.
- [ ] Extend the reviewer-loop summary's small-findings line to name **every**
      cause present — the shipped paths, the matched contract-surface identities
      as printed by the predicate, and the platform responsible for any stale or
      unknown head — so the full picture is visible on the PR rather than only
      the single value the key can carry.
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
6a. Cosmetic bodies containing a **bare common word** that an earlier draft
    would have matched are still small, one case per word: "the heading **state**
    is inconsistent", "a typo in the **scope** section", "the **status** column
    is misaligned", "the **gate** heading needs a capital", "fix the **proof**
    reading typo", "**parse** is misspelled here", "the **contract** section has
    a trailing space". None may match the contract-surface test. This is the
    restrictive-direction guard on the predicate: over-matching common words
    would make almost every finding non-small and disable the terminal rule
    while appearing to tighten it.
7. `reviewer_loop_all_findings_are_small` returns failure when any one of three
   findings is non-small, and success only when all three are small.
8. The consecutive count stops at the first ledger entry whose recorded head
   differs from the current head: with two prior small rounds on an older head
   and one on the current head, the count is 1, not 3, and the stop reason is
   `stale_head`.
8a. The **current** round is verified too, per contributing reviewer. With the
    prior count sufficient and counted findings from two platforms, four
    combinations: both reporting `loop_head_sha` → the rule may fire; one
    reporting a different head → does not fire, `stale_head`; one reporting no
    head → does not fire, `head_unknown`; both stale → does not fire. Checking
    only the prior entries would leave the deciding round — the `+ 1` in
    `prior + 1` — unverified, and checking only one contributor would let a
    second platform's stale evidence through.
9. The consecutive count stops at an entry whose head is absent, empty, or a
   synthetic `unknown-…` placeholder — three cases, each ending the run rather
   than being skipped, each with stop reason `head_unknown`.
9a. The counter reports its stop reason from the closed set, one case each:
    `exhausted` when the walk reaches the end of the ledger, `not_small` when it
    stops at a non-small round, `stale_head`, and `head_unknown`. A bare count
    cannot distinguish the last two, which `SMALL_FINDINGS_BLOCKED_BY` must.
10. With the required rounds reached but the most recent counted round on a
    stale head, the terminal rule does **not** fire and
    `SMALL_FINDINGS_BLOCKED_BY=stale_head`.
10a. Precedence within each group, one case per boundary — and a third case
    proving the two groups cannot co-occur:

    | Situation | Reported value | What it tests |
    | --- | --- | --- |
    | A shipped-path finding **and** a contract-surface finding | `shipped_path` | the content-group boundary |
    | All findings small, one stale contributor **and** one reporting no head | `stale_head` | the currency-group boundary |
    | A contract-surface finding **and** a contributor reporting a stale head | `contract_surface`, and **no** currency cause is recorded at all | that the groups are mutually exclusive: a non-small finding means the head check is never reached |

    In the first two rows the **summary line still names both causes**, so
    precedence reduces only the single-valued key. The third row is the guard
    against re-introducing a content-versus-currency ordering: there is nothing
    to order, because the currency causes are unreachable whenever a content
    cause exists.
10b. `reviewer_loop_finding_touches_contract_surface` prints the matched surface
    identity — `acceptance_criteria`, `fail_closed_semantics` and so on — and
    prints nothing on no match. A body matching two surfaces prints the first in
    table order, so the output is deterministic and the summary renderer has a
    defined input.
11. `SMALL_FINDINGS_BLOCKED_BY` reports each of its four values for the
    corresponding cause — `shipped_path`, `contract_surface`, `stale_head` and
    `head_unknown` — and is **empty** both when the rule fired and when the run
    was simply short (`exhausted` or `not_small`), since neither is a blocking
    reason.
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

- `scripts/development-workflow/tests/test-pr-review-loop.sh` — scenarios 1, 2,
  3, 4, 5, 6, 6a, 7, 8, 8a, 9, 9a, 10, 10a, 10b, 11 and 14, as new cases in the
  existing `HARNESS_MODE=1` harness. Listed individually rather than as a range: the
  sub-lettered scenarios are the ones a range drops, and all five of them
  (6a, 8a, 9a, 10a, 10b) guard a behavior the others do not.
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
demonstrated runs per proof, each citing a concrete file and line. Of the nine
proofs, **six** plant the **permissive** direction — P1 through P5 and P8,
reproducing the original bug; **two** plant the **restrictive** direction —
P6 and P7, where the tightening would disable the mechanism instead of
sharpening it.

| # | Violation to plant | Where | Check that must fail, then pass |
| --- | --- | --- | --- |
| P1 | Remove `docs/specs/developments/**` from the normative-document list | a scratch copy of the predicate | scenario 2 fails and scenario 12 fires the terminal rule on a spec contract finding; restoring the pattern passes |
| P2 | Make the contract-surface test consult the path as well, so a non-shipped path short-circuits it | a scratch copy of the predicate | scenario 5 fails, because a contract finding on a `docs/` path becomes small again; restoring the path-independent test passes |
| P3 | Turn the contract-surface allow-list into a deny-list of cosmetic terms | same scratch copy | scenario 4's three cosmetic bodies still pass, but a contract body using none of the listed cosmetic terms is classified small — the failure mode the allow-list exists to prevent; restoring the allow-list passes |
| P4 | Drop the current-head comparison from the consecutive count | a scratch copy of the counter | scenario 8 fails, because rounds on an older head extend the run; restoring the comparison passes |
| P5 | Treat an entry with an absent or placeholder head as matching the current head | same scratch copy | scenario 9 fails in all three cases, because an unprovable head extends the run; restoring the fail-closed branch passes |
| P6 | Over-tighten by path: make every `docs/` path shipped, dropping the non-shipped patterns entirely | a scratch copy of the predicate | scenarios 3, 6 and 13 fail, because the loop can no longer terminate on a genuinely cosmetic documentation tail; restoring the narrowed list passes |
| P7 | Over-tighten by term: restore the bare common words `gate`, `scope`, `state`, `status`, `proof`, `parse` and `contract` to the contract-surface list | same scratch copy | scenario 6a fails on all seven cosmetic bodies and scenario 13 stops firing, because ordinary prose now reads as contract-bearing; restoring the phrase-only list passes |
| P9 | Invert both within-group precedences: report `contract_surface` over `shipped_path`, and `head_unknown` over `stale_head` | a scratch copy of the blocked-by mapping | scenario 10a's first two rows fail — the content row reports `contract_surface` where a shipped path is present, and the currency row reports `head_unknown` where a known-different head is present. Both are detectable because both are genuine co-occurrences within a group; restoring the order passes |
| P8 | Skip the current round's head check, verifying only the prior ledger entries | a scratch copy of the terminal decision | scenario 8a fails, because the rule terminates on a deciding round whose findings describe a commit that is no longer the head; restoring the check passes |

P6 and P7 are the two restrictive-direction proofs and neither is optional. A
tightening that removes the mechanism — whether by classifying every path as
shipped, or by matching common words that appear in ordinary prose — would pass
every permissive-direction proof here while leaving the loop unable to terminate
on cosmetic findings. That is a different defect, not a fix, and it is the more
likely of the two mistakes because it looks like success.

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
| Contract-surface body fixture | One body per row of the contract-surface table; three cosmetic bodies; the **seven bare-common-word cosmetic bodies** of scenario 6a, one per removed term; the three qualified-phrase controls that must still match; and the eleven parser edge cases, including the two substring negatives, the `failXclosed` wildcard negative and the unhyphenated `allow list` negative | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Multi-contributor round fixture | A single round with counted findings from two platforms, in four combinations — both on the current head, one stale, one reporting no head, and both stale — driving scenario 8a | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Co-occurring-cause fixtures | Three rounds driving scenario 10a: one carrying both a shipped-path and a contract-surface finding; one whose findings are all small with one stale contributor and one reporting no head; and one carrying a contract-surface finding together with a contributor on a stale head, to prove the currency check is never reached | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
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
| The contract-surface test over-matches ordinary prose | **High** | High — matching bare common words like `state`, `scope` or `gate` would make almost every finding non-small, disabling the terminal rule from the restrictive side while appearing to tighten it | Every matched term is a phrase or a qualified form; no bare common word is on the list, and the plan records that an earlier draft's bare terms were removed for this reason. Scenario 6a tests one cosmetic body per removed word, and the parser-risk addendum adds word-boundary negatives (`delegates`/`gate`, `microscope`/`scope`) |
| The current round is decided without checking its own head | Med | High — the rule could terminate on a round whose findings describe a commit that is no longer the head, which is the staleness the brief names | The run is `prior + 1` and both halves are verified: the counter checks prior entries, and **every** reviewer contributing a counted finding to the current round must report `loop_head_sha` before it contributes. Scenario 8a's four combinations pin the `+ 1` half, including the two-platform case where only one contributor is stale; proof P8 plants the omission |
| An old ledger without head data silently counts as current | Med | High — the current-head requirement would be inert on exactly the PRs that predate it | An absent, empty or placeholder head ends the consecutive run; scenarios 9 and 14 and proof P5 pin all three forms |
| A maintainer cannot tell a correctly-refusing loop from a still-failing one, or is shown the less actionable cause | Med | Med | `SMALL_FINDINGS_BLOCKED_BY` names one cause by a documented within-group precedence, and the summary line names **every** cause present — the shipped paths, the matched contract-surface identities, and the platform responsible for any stale or unknown head. Scenario 11 pins all four values and both empty cases, scenario 9a pins the counter's stop reasons that feed the currency pair, scenario 10a pins both within-group boundaries and the groups' mutual exclusivity, and proof P9 plants the inverted precedence |
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

# Allow-list of contract-bearing surfaces, as ordered (identity, pattern) pairs.
# Prints the matched surface identity and returns success; prints nothing and
# returns failure on no match. A bare boolean would leave the summary renderer
# with nothing to name. First match in table order wins, so output is
# deterministic when a body touches more than one surface.
#
# Every pattern is a phrase or a qualified form. Bare common words such as
# "gate", "scope", "state", "status", "proof", "parse" and "contract" are
# deliberately absent: they appear in ordinary cosmetic findings and would make
# almost everything non-small, disabling the terminal rule from the restrictive
# side. See scenario 6a and proof P7.
#
# Separators are literal, never the regex wildcard ".": "fail.closed" would
# match "failXclosed" and reintroduce over-matching. Each pattern lists exactly
# the spellings the normative table names, and no others.
REVIEWER_LOOP_CONTRACT_SURFACES=(
  'acceptance_criteria|acceptance criterion|acceptance criteria|AC-[0-9]'
  'decision_gates_and_matrices|decision gate|decision matrix|matrix row|readiness gate|gate condition|gating'
  'parser_and_input_behavior|parser|regex|input surface|word boundary'
  'scope_and_coverage|out of scope|in scope|scope creep|coverage matrix|brief objective'
  'fail_closed_semantics|fail-closed|fail closed|allow-list|deny-list|vacuous'
  'state_and_status_models|state machine|state table|evidence state|valid transition|status label|status transition'
  'telemetry_and_contracts|telemetry|stdout key|key=value contract|output contract'
  'proof_obligations|planted-violation|planted violation|proof obligation'
)

reviewer_loop_finding_touches_contract_surface() {
  local body="$1"
  local entry identity pattern

  [ -n "${body//[[:space:]]/}" ] || return 1

  for entry in "${REVIEWER_LOOP_CONTRACT_SURFACES[@]}"; do
    identity="${entry%%|*}"
    pattern="${entry#*|}"
    # Case-insensitive, word-boundary: "delegates" must not match "gate".
    if printf '%s' "$body" | grep -Eqi "\\b(${pattern})\\b"; then
      printf '%s\n' "$identity"
      return 0
    fi
  done

  return 1
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
   word-boundary matching over **exactly the spellings the normative table
   lists** — no bare common words, no wildcard separators, and no additional
   variants such as an unhyphenated `allow list`. It **prints the
   matched surface identity** and returns success, printing nothing on no
   match, and resolves ties by first match in table order. **Verify**:
   scenario 4, scenario 6a's seven cosmetic bodies, scenario 10b's identity and
   determinism assertions, and every row of the parser-risk edge-case list
   including the `delegates`/`gate` and `failXclosed` negatives.
3. Rename `reviewer_loop_all_paths_non_shipped` to
   `reviewer_loop_all_findings_are_small`, take finding bodies alongside paths,
   and fail when any finding is shipped-path **or** contract-surface.
   **Verify**: scenarios 5-7. Record in the PR whether any caller outside this
   change set required the old name.
4. Extend `reviewer_loop_small_findings_prior_consecutive_count` to take the
   current head, stop at the first differing, absent, empty or placeholder head,
   and report a stop reason from the closed set. **Verify**: scenarios 8, 9, 9a
   and 14.
5. Wire the current-head requirement into the terminal decision — for the prior
   entries via the counter, and for the deciding round via the per-reviewer
   reviewed head from #1648, requiring **every** contributing reviewer to report
   `loop_head_sha`. **Verify**: scenarios 8a, 10 and 11.
5a. Implement `SMALL_FINDINGS_BLOCKED_BY` as **two within-group precedences**,
   not a four-level global one: `shipped_path` over `contract_surface` in the
   content group, and `stale_head` over `head_unknown` in the currency group.
   The groups are mutually exclusive, so exactly one group is ever populated:
   collect every cause **within the reached group** for the summary line, and
   never evaluate the currency causes when a content cause exists. **Verify**:
   scenarios 10a and 11 — the key carries the first cause of the reached group,
   the collected set carries the rest of that group only, and 10a's third row
   records no currency cause at all.
6. Extend the summary's small-findings line to name every collected cause: the
   shipped paths, the matched contract-surface identities as printed by the
   predicate, and the platform responsible for any stale or unknown head.
   **Verify**: read the rendered line for a `contract_surface` case, a
   `shipped_path` case, and one of scenario 10a's co-occurring cases, confirming
   the last names both causes even though the key reports one.
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
10. Produce the nine planted-violation proofs (P1-P9) and record them in the PR
    under a `Planted-Violation Proofs` heading. **Verify**: each shows two runs
    at a concrete file and line — failing with the violation planted, passing
    once removed. P6 and P7 are the two restrictive-direction proofs and
    neither is optional.
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

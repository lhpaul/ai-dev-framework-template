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
only where it lives, in two tiers. A blocking finding on a **normative
document** — a spec, plan, protocol, `REVIEW.md`, the best-practices set — is
never small, whatever its wording, which is the fail-closed half. On other
non-shipped paths a contract-surface test escalates a finding that would
otherwise be small
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
| Every normative document is classified non-shipped today | Sourced the loop with `HARNESS_MODE=1` and called the classifier on six real paths | `docs/specs/developments/**/1_*_specs.md`, `docs/workflow/development-workflow/protocols/91-*.md`, `REVIEW.md`, `docs/best-practices/3-testing.md` and `docs/testing/workflow/*.smoke-test.md` all return non-shipped; only `scripts/development-workflow/pr-review-loop.sh` returns shipped. This is why a path-only rule classifies every contract finding in this repository as small — and also why reclassifying those paths would make every *cosmetic* finding non-small, which the plan rejects |
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

- [ ] **The path rule is the fail-closed guard; vocabulary is only an
      escalation.** A keyword list cannot be the primary test, because it only
      catches findings that happen to use its words. *"Required error handling
      is missing"* and *"this permits an invalid value"* are contract findings
      that contain none of the listed phrases; under a vocabulary-only rule they
      fall through to the path rule and are cleared as small — the original bug,
      preserved for ordinary wording. A guard that depends on reviewers reaching
      for particular vocabulary is not fail-closed.

      Note also what the small-findings path already filters: `small_findings_paths`
      is built from `reviewer_loop_blocking_paths_from_output`, so **only
      blocking findings ever reach this rule**. Advisory and suggestion-level
      findings are out of scope entirely. The question is therefore not "is this
      finding important" — the reviewer already said it blocks — but "on which
      artifacts may a blocking finding still be treated as a cosmetic tail".

      The rule is therefore two-tier:

      | Finding's path | Blocking finding is small? |
      | --- | --- |
      | A **normative document** — `REVIEW.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `LLM_RULES.md`, `.ai-dev-workflow.yaml`, `docs/workflow/**`, `docs/best-practices/**`, `docs/specs/developments/**`, `docs/testing/workflow/**` | **Never**, whatever it says |
      | Any other non-shipped path — `docs/project/**`, fixtures, snapshots, `CHANGELOG.md` | Small, **unless** its body touches a contract surface |
      | A shipped path | Never — unchanged behavior |

      Add `reviewer_loop_path_is_normative_document` for the first row, consulted
      from `reviewer_loop_path_is_non_shipped_artifact` before the existing
      patterns.

- [ ] **Why the path rule is scoped this way, and what it costs.** An earlier
      revision of this plan removed the path rule entirely on the grounds that
      the brief's scope bullet asks for a content rule and a path rule would
      make *every* finding on a spec non-small. Both halves of that reasoning
      were incomplete:

      - The brief's Outcome line is explicit that the tightening is *"for
        normative docs, specs, plans, and review protocols"*. Reading only the
        scope bullet dropped that.
      - "Every finding" is not what the path rule catches, because only
        **blocking** findings reach this code path at all. A blocking finding on
        a specification is not a cosmetic tail; a reviewer that marks a trailing
        space as blocking on a contract document is making a claim the loop
        should honour rather than override.

      The cost is real and accepted: on this repository, where most pull
      requests touch normative documents, the terminal rule will fire less
      often. That is the intended direction — the rule fired 24 times across
      this epic's own PRs while blocking contract defects were live. Cosmetic-
      tail termination survives where it is actually needed: `docs/project/**`,
      fixtures, snapshots and `CHANGELOG.md`.

- [ ] **Add a contract-surface test as the escalation for the second tier.**
      It applies only to blocking findings on non-normative, non-shipped paths,
      where it promotes a finding that would otherwise be small. It is never the
      only guard, so its vocabulary dependence cannot let a contract finding on
      a normative document through. Add
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
- [ ] **Collect findings as path/body pairs, and say exactly how.** Today
      `reviewer_loop_blocking_paths_from_output` emits only paths, one per line,
      and the caller accumulates them into `aggregate_blocking_paths`. Bodies
      are never collected, so "take the finding bodies alongside the paths" is
      not implementable without a stated representation. The concrete change:

      1. Add `reviewer_loop_blocking_findings_from_output <output> <count> <platform>`,
         emitting **one compact JSON object per line**:
         `{"path":…,"platform":…,"body":…}`, built with
         `jq -c -n --arg path … --arg platform … --arg body …`. Consumers read
         the fields back with `jq -r`.

         The platform is a **third argument**, not read from the output: the
         reviewer output carries no per-finding platform key, and
         `platform_name` exists only in the caller's loop. The call site is the
         per-platform block that already computes it, alongside the existing
         `reviewer_loop_blocking_paths_from_output "$platform_output"
         "$platform_blocking_count"` call, which keeps its two-argument
         signature unchanged.

         **Not a delimiter-separated record.** An earlier revision proposed
         `<path><TAB><platform><TAB><body>` on the reasoning that a path cannot
         contain a tab. That is false — git paths may contain tabs — and
         `local-ai-reviewer.sh` does not escape tabs in finding bodies either,
         so either field could shift the columns and classify a contract-bearing
         blocker against corrupted data. JSON removes the question rather than
         answering it: `jq --arg` escapes every field on the way in and `jq -r`
         decodes on the way out, for tabs, quotes, backslashes and any other
         byte. `jq` is already a hard dependency of this script, so nothing new
         is introduced.
      2. Accumulate those records into `aggregate_blocking_findings`, a parallel
         array to the existing `aggregate_blocking_paths`. **Do not deduplicate.**
         The existing path array may be deduplicated; the findings array must
         not be, because two findings can share a path and differ in body — one
         cosmetic and one contract-bearing — and collapsing them would lose the
         one that decides the outcome.
      3. **Normalise the body for matching — do not attempt to decode it.**
         `local-ai-reviewer.sh` line 468 emits `BLOCKING_<n>_BODY` with real
         newlines replaced by the literal two-character sequence `\n`, and it
         does **not** escape pre-existing backslashes first. That encoding is
         therefore **lossy**: a body that originally contained a newline and one
         that originally contained a literal `\n` are indistinguishable
         afterwards, and no downstream step can recover the difference. JSON
         transport does not help — it preserves exactly the bytes it was given,
         which are already ambiguous.

         The plan does not try to reverse it. Instead, before applying the
         contract-surface test, replace every occurrence of the two-character
         sequence `\n` with a single space. This is a deliberately lossy
         **normalisation for matching only**:

         - It is needed because the sequence leaves an alphanumeric `n` abutting
           the following word — `prose\ndecision matrix` presents as
           `…prosendecision matrix`, so the word boundary before `decision`
           fails and a contract term after a line break would be missed.
         - It is safe because both possible originals — a real newline and a
           literal `\n` — are word separators or noise for this purpose, so
           collapsing them to a space gives the same, correct answer either way.
           The ambiguity is real but immaterial to the question being asked.
         - It is **never** used to reconstruct or store the body. The record and
           the summary carry the raw value as received; only the string handed
           to the matcher is normalised.

         Fixing the encoding at the producer would be the more complete answer
         and is deliberately out of scope: it changes a key=value contract other
         consumers read, which is its own item.
      4. Record the platform on each record so the summary can name which
         reviewer produced the finding that kept the round non-small — the same
         attribution the current-head rule already needs per contributor.
- [ ] Replace `reviewer_loop_all_paths_non_shipped` with
      `reviewer_loop_all_findings_are_small`, taking the path/body/platform
      records and returning failure when **any** finding is on a normative
      document, has a shipped path, or touches a contract surface. Keep a thin
      wrapper under the old name only if a caller outside this change set needs
      it, and record in the PR whether one did.
- [ ] **Require the counted rounds to be on the current head — including the
      round now being decided.** The consecutive run is `prior entries + 1`, and
      the `+ 1` is this round, so checking only the prior entries would leave
      the deciding round unverified. Two changes:
      1. Extend `reviewer_loop_small_findings_prior_consecutive_count` to take
         the current head and stop counting at the first entry that fails the
         check below, so a round on an older commit ends the run rather than
         extending it.

         **Which field, and whose evidence.** #1648's ledger entry carries three
         head-ish values and they mean different things, so "the entry's
         recorded head" is not specific enough to implement:

         | Field | Meaning | Role here |
         | --- | --- | --- |
         | `head_sha` | the live head at ledger **write** time | **not used** — it is the identity key the #1502 cap counters bucket on, and it can differ from what was reviewed |
         | `classification_head` | the `loop_head_sha` that round's states were classified against | the round's subject: must equal the current `loop_head_sha` |
         | `reviewed_heads[]` | per-platform reviewed head and state, for **every configured platform** | the round's evidence — but only the entries for platforms that actually contributed a counted finding |

         **Only contributing platforms are checked.** `reviewed_heads[]` lists
         every configured platform, including ones that returned clean, were
         skipped, or reported no head at all. Requiring a current head from all
         of them would break the count permanently on any repository where a
         reviewer is legitimately not reporting — disabling the terminal rule
         from the restrictive side, and inconsistently with the current-round
         rule, which is already scoped to contributors.

         The ledger does not record that mapping today, so this item adds it:
         each small-findings entry gains **`contributing_platforms[]`**, the set
         of platforms that produced a counted finding in that round. It is
         derived from the `platform` field of the `aggregate_blocking_findings`
         records this item already introduces, so no new source of truth is
         created.

         A prior round counts only when **all three** hold: its
         `classification_head` equals the current `loop_head_sha`; it records a
         non-empty `contributing_platforms[]`; and every platform named there
         has a `reviewed_heads[]` entry whose head is valid and equal to that
         `classification_head`. Entries for non-contributing platforms are
         ignored entirely.

         An entry written before this change carries no
         `contributing_platforms[]` and therefore ends the run — the same
         fail-closed direction as a missing head, and the same as scenario 14.

         Any entry whose `classification_head` is absent, empty or a synthetic
         placeholder ends the run with `head_unknown`; any entry with a
         `reviewed_heads[]` member whose head is absent, empty or invalid does
         the same; a `classification_head` that is a valid but different commit
         ends it with `stale_head`.
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
      — document the two-tier rule: that a blocking finding on a normative
      document is never small whatever its wording; that on other non-shipped
      paths a contract-surface finding is escalated to non-small while a
      cosmetic one still terminates the tail; that only blocking findings reach
      this rule at all; that both the prior counted rounds and the round being
      decided must be on the current head; that an unknown head ends the run;
      and what `SMALL_FINDINGS_BLOCKED_BY` reports.
- [ ] `REVIEW.md` — add a short block under the review contract covering the
      same rule Protocol 93 states, so a reviewer knows the classification
      without reading the loop: that a **blocking** finding on a spec, plan,
      protocol or the review contract itself is never small, whatever it says;
      that on other documentation paths a contract-surface finding is escalated
      while a cosmetic one is not; that the terminal rule requires
      both the prior counted rounds and the round being decided to be on the
      current head; and that `SMALL_FINDINGS_BLOCKED_BY` reports one of
      `shipped_path`, `contract_surface`, `stale_head` or `head_unknown`.
      Protocol 93 remains the normative home and carries the full detail;
      `REVIEW.md` states the rule and points to it.

---

## Testing Strategy

**Test types**: Unit (shell harness), plus the smoke test runbook.

**Key scenarios to test**:

1. `reviewer_loop_path_is_normative_document` matches each of the ten patterns
   in the first tier, one case per pattern, and rejects
   `docs/project/1-business-domain.md`, `tests/fixtures/x.json`,
   `__snapshots__/x.snap`, `CHANGELOG.md` and
   `scripts/development-workflow/pr-review-loop.sh`.
2. A blocking finding on a normative document is **never small, whatever its
   body says** — three cases on `docs/specs/developments/x/1_x_specs.md`: a body
   naming a decision matrix, a body reading only "trailing whitespace", and a
   body reading "required error handling is missing" that contains **no** listed
   contract term. All three are non-small. The third is the fail-closed case: a
   vocabulary-only rule would have cleared it.
3. A blocking finding on a **non-normative, non-shipped** path is still small
   when cosmetic and non-small when it touches a contract surface — two cases on
   `docs/project/1-business-domain.md`, so the second tier's escalation is
   exercised where it actually applies and the cosmetic tail still terminates.
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
7a. Pairing survives collection: with two findings **on the same path** — one
    cosmetic, one naming a decision matrix — the round is non-small. A
    deduplicating collector would keep one record and could keep the cosmetic
    one, making the round small; this is the pairing-loss case.
7b. A body whose original text spanned lines matches after normalisation: a
    body emitted as `some prose\ndecision matrix is wrong` matches, where
    matching the raw string would not, because `\n` leaves an `n` abutting
    `decision` and the word boundary fails.
7b-i. Both possible originals give the same answer: a body whose original text
    contained a **real newline** and one that contained a **literal `\n`**
    arrive identically encoded and both match. The plan does not claim to tell
    them apart — the producer's encoding is lossy — only that the classification
    is correct either way.
7d. Fields survive characters that would break a delimiter-separated record: a
    path containing a tab, a body containing a tab, a body containing a double
    quote, and a body containing a backslash. Each round is classified from
    intact fields, and the contract term is still found. These are the cases a
    `<path><TAB><platform><TAB><body>` representation would corrupt.
7c. Each record carries its platform, and the summary names the platform that
    produced the finding which kept the round non-small.
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
8b. The prior-round check is per **contributing** platform. Four cases on an
    entry whose `classification_head` equals the current head:

    | `contributing_platforms[]` | `reviewed_heads[]` state | Result |
    | --- | --- | --- |
    | two platforms, both named | both on `classification_head` | counts |
    | two platforms, both named | one on an older commit | run ends, `stale_head` |
    | one platform named | that one current; a **non-contributing** platform reports no head | counts — non-contributors are ignored |
    | absent (pre-change entry) | any | run ends |

    The third row is the one that keeps the rule usable: `reviewed_heads[]`
    lists every configured platform, including ones that returned clean or were
    skipped, so requiring a current head from all of them would break the count
    permanently wherever a reviewer legitimately does not report.
8c. The counter reads `classification_head`, never `head_sha`. With an entry
    whose `head_sha` equals the current head but whose `classification_head`
    is an older commit, the run ends with `stale_head`; with the two swapped, it
    counts. `head_sha` is the #1502 cap identity key and can legitimately differ
    from the commit the round described.
4a. The boundary expression is portable: the predicate matches `decision gate`
    and rejects `delegates` under **both** GNU grep and BSD grep. A `\b`-based
    implementation passes the first under GNU and fails it under BSD, so this
    case is what distinguishes a portable implementation from one that only
    works on the CI runner.
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
12. **The #1661 regression — tier 1.** Replay a ledger built from PR #1661's
    actual history: consecutive rounds whose only findings were on
    `docs/specs/developments/**`. Assert the terminal rule does **not** fire,
    where today it fires on round two. This is **tier-1 coverage**: those paths
    are normative documents, so the finding bodies are irrelevant to the
    outcome, and the scenario would pass even if the contract-surface test were
    completely broken. It proves the epic's actual regression is closed; it does
    not prove tier 2 works.
12a. **Tier-2 isolation.** Replay the same ledger shape on
    `docs/project/1-business-domain.md` — a non-normative, non-shipped path —
    with the same #1661 bodies naming fail-closed semantics, decision-matrix
    rows and acceptance criteria. Assert the terminal rule does **not** fire.
    Here the path alone would make the findings small, so only the
    contract-surface test can produce the result: this is the scenario that
    actually exercises tier 2 end to end, and it fails if the vocabulary
    matching is broken.
13. **The cosmetic counter-case.** Replay scenario 12a's ledger exactly — same
    round count, adjacency, head **and the same
    `docs/project/1-business-domain.md` path** — changing only the bodies to
    cosmetic ones. Assert the terminal rule **does** fire.

    Pairing with 12a rather than 12 is what makes this the strong form: the two
    differ in **body alone** on a tier-2 path, so the opposite outcomes isolate
    the contract-surface test exactly. Pairing it with scenario 12 would be
    meaningless, since tier 1 makes those findings non-small whatever the body
    says.
14. A ledger entry written before this change — carrying no head on its
    small-findings entries, or no `contributing_platforms[]` — ends the
    consecutive run rather than being counted. Backward compatibility in the
    fail-closed direction, for both missing fields.

**Files**:

- `scripts/development-workflow/tests/test-pr-review-loop.sh` — scenarios 1, 2,
  3, 4, 4a, 5, 6, 6a, 7, 7a, 7b, 7b-i, 7c, 7d, 8, 8a, 8b, 8c, 9, 9a, 10, 10a,
  10b, 11 and 14, as new cases in the existing `HARNESS_MODE=1` harness. Listed individually rather than as a range: the
  sub-lettered scenarios are the ones a range drops, and all thirteen of them
  (4a, 6a, 7a, 7b, 7b-i, 7c, 7d, 8a, 8b, 8c, 9a, 10a, 10b) guard a behavior the
  others do not.
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
demonstrated runs per proof, each citing a concrete file and line. The nineteen proofs fall into four groups:

| Group | Count | Proofs | What they plant |
| --- | --- | --- | --- |
| Permissive | **13** | P1-P5, P8, P10, P11, P12, P14, P15, P16, P17 | the original bug, in each of the ways it can return |
| Fidelity | **1** | P18 | storing the matching-time normalisation instead of the body as received |
| Restrictive | **4** | P6, P7, P13, P19 | a tightening that disables the mechanism instead of sharpening it |
| Observability | **1** | P9 | an inverted within-group reporting precedence, which hides the more actionable cause without changing whether the rule fires |

| # | Violation to plant | Where | Check that must fail, then pass |
| --- | --- | --- | --- |
| P1 | Remove `docs/specs/developments/**` from the normative-document list | a scratch copy of `reviewer_loop_path_is_normative_document` | scenario 2's second and third cases fail — a trailing-whitespace body and a body with no listed contract term both become small on a spec — and scenario 12 fires the terminal rule; restoring the pattern passes |
| P15 | Deduplicate the findings array by path, keeping the first record | a scratch copy of the collector | scenario 7a fails when the cosmetic finding sorts first: the contract finding is dropped and the round is classified small; restoring the non-deduplicating collection passes |
| P17 | Replace the JSON record with a tab-separated one | a scratch copy of the collector | scenario 7d fails: a path or body containing a tab shifts the columns, the platform and body fields are read from the wrong text, and a contract-bearing blocker is classified against corrupted data; restoring the JSON record passes |
| P16 | Match the contract-surface test against the raw body without normalising `\n` | a scratch copy of the classifier | scenario 7b fails, because a term following a line break abuts the sequence and misses the word boundary; restoring the normalisation passes |
| P18 | Use the normalised body as the stored record and summary value | a scratch copy of the collector | the record no longer carries the body as received, so the summary misreports what the reviewer wrote; restoring the raw value for storage passes while scenario 7b still passes |
| P14 | Break the contract-surface matching entirely, returning failure for every body | a scratch copy of the tier-2 predicate | scenario 12a fails, because a #1661-shaped ledger on a non-normative path terminates; scenario 12 still passes, which is exactly why 12a exists. Restoring the predicate passes both |
| P13 | Replace the character-class boundary with `\b` | a scratch copy of the predicate | scenario 4a fails under BSD grep — `decision gate` no longer matches at all, so tier 2 silently stops escalating anything; restoring the POSIX form passes under both greps |
| P12 | Make the contract-surface test the only guard, dropping the normative-path tier | a scratch copy of the classifier | scenario 2's third case fails: *"required error handling is missing"* contains no listed term, falls through to the path rule, and is cleared as small. This is the vocabulary-dependence failure the two-tier design exists to prevent; restoring the tier passes |
| P2 | Make the contract-surface test consult the path as well, so a non-shipped path short-circuits it | a scratch copy of the predicate | scenario 5 fails, because a contract finding on a `docs/` path becomes small again; restoring the path-independent test passes |
| P3 | Turn the contract-surface allow-list into a deny-list of cosmetic terms | same scratch copy | scenario 4's three cosmetic bodies still pass, but a contract body using none of the listed cosmetic terms is classified small — the failure mode the allow-list exists to prevent; restoring the allow-list passes |
| P4 | Drop the current-head comparison from the consecutive count | a scratch copy of the counter | scenario 8 fails, because rounds on an older head extend the run; restoring the comparison passes |
| P5 | Treat an entry with an absent or placeholder head as matching the current head | same scratch copy | scenario 9 fails in all three cases, because an unprovable head extends the run; restoring the fail-closed branch passes |
| P6 | Over-tighten by path: add `docs/project/**`, fixtures and `CHANGELOG.md` to the normative-document list | a scratch copy of `reviewer_loop_path_is_normative_document` | scenarios 1, 3, 6 and 13 fail, because no documentation finding can be small and the loop runs to its cycle cap on a trailing space; restoring the narrowed list passes |
| P7 | Over-tighten by term: restore the bare common words `gate`, `scope`, `state`, `status`, `proof`, `parse` and `contract` to the contract-surface list | same scratch copy | scenario 6a fails on all seven cosmetic bodies and scenario 13 stops firing, because ordinary prose now reads as contract-bearing; restoring the phrase-only list passes |
| P9 | Invert both within-group precedences: report `contract_surface` over `shipped_path`, and `head_unknown` over `stale_head` | a scratch copy of the blocked-by mapping | scenario 10a's first two rows fail — the content row reports `contract_surface` where a shipped path is present, and the currency row reports `head_unknown` where a known-different head is present. Both are detectable because both are genuine co-occurrences within a group; restoring the order passes |
| P10 | Make the counter read `head_sha` instead of `classification_head` | a scratch copy of the counter | scenario 8c fails, because a round whose write-time head happens to match counts even though it described an older commit; restoring `classification_head` passes |
| P11 | Check only a prior entry's `classification_head` and skip its `reviewed_heads[]` | same scratch copy | scenario 8b's second row fails, because a round classified against the current head counts while one of its contributors reviewed an older commit; restoring the per-contributor check passes |
| P19 | Require a current head from **every** `reviewed_heads[]` entry rather than only the contributing platforms | same scratch copy | scenario 8b's third row fails: a non-contributing reviewer that returned clean or was skipped breaks the count, and on a repository where one reviewer never reports the terminal rule can never fire again. Restoring the contributor scoping passes |
| P8 | Skip the current round's head check, verifying only the prior ledger entries | a scratch copy of the terminal decision | scenario 8a fails, because the rule terminates on a deciding round whose findings describe a commit that is no longer the head; restoring the check passes |

**No proof is optional, and the restrictive group least of all.** A tightening
that removes the mechanism would pass every permissive-direction proof while
leaving the loop unable to terminate on cosmetic findings — a different defect,
not a fix, and the more likely of the two mistakes because the reasoning that
produces it is "be stricter", which sounds like the goal. The group's membership
is the table above; it is not restated here, because a restated count is the
thing that drifts.

### Parser-risk addendum

Applicable — `reviewer_loop_finding_touches_contract_surface` scans
externally-supplied finding text.

- **Edge-case enumeration**: a body containing a listed term as a substring of a
  longer word (`gates` in `delegates`, `scope` in `microscope`); a term in a
  different case (`Acceptance Criteria`, `FAIL-CLOSED`); a term inside a fenced
  code block quoted from the diff; a **listed phrase** inside a URL, and a
  **bare unlisted word** inside a URL; an empty body; a body of only whitespace;
  a body containing a listed term in a quoted *negation* (\"this is not a
  decision gate\"); a multi-line body where the term appears only on the last
  line.
- **Required behavior**: matching is case-insensitive and on word boundaries,
  expressed as `(^|[^[:alnum:]_])(…)([^[:alnum:]_]|$)` rather than `\b`. `\b`
  is a GNU and PCRE extension that BSD grep on stock macOS does not recognise,
  where it would fail even the positive cases; the character-class form is POSIX
  ERE and is the convention this repository already uses for the 401/403
  boundary in `local-ai-reviewer.sh`. With it, `delegates` does not match `gate`
  and `microscope` does not match `scope`. A
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
| Path classification fixture | The ten normative patterns of scenario 1 and the five non-matching controls, plus the three bodies of scenario 2 on one normative path and the two bodies of scenario 3 on `docs/project/1-business-domain.md` | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Path/body pair fixture | Two findings on one identical path — one cosmetic, one naming a decision matrix — a body containing an escaped `\n` sequence, a two-platform record set, and four hostile-character cases (a tab in the path, a tab in the body, a double quote, a backslash), driving scenarios 7a through 7d | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Contract-surface body fixture | One body per row of the contract-surface table; three cosmetic bodies; the **seven bare-common-word cosmetic bodies** of scenario 6a, one per removed term; the three qualified-phrase controls that must still match; and **twelve** parser edge cases — the ten enumerated in the parser-risk addendum, plus the `failXclosed` wildcard negative and the unhyphenated `allow list` negative that the runbook's Step 3 table adds | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Multi-contributor round fixture | A single round with counted findings from two platforms, in four combinations — both on the current head, one stale, one reporting no head, and both stale — driving scenario 8a | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Co-occurring-cause fixtures | Three rounds driving scenario 10a: one carrying both a shipped-path and a contract-surface finding; one whose findings are all small with one stale contributor and one reporting no head; and one carrying a contract-surface finding together with a contributor on a stale head, to prove the currency check is never reached | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Contributing-platform ledger fixture | Entries with two contributors both current, two with one stale, one contributor current alongside a non-contributing platform reporting no head, and a pre-change entry with no `contributing_platforms[]` — driving scenario 8b's four rows | inline heredocs in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Head-comparison ledger fixture | Ledger payloads with prior small rounds on an older head, on the current head, and with absent, empty and placeholder heads — driving scenarios 8, 9, 10 and 14 | inline heredocs in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| #1661 replay ledger | A `reviewer_loop_history.v1` payload reproducing PR #1661's consecutive small-findings rounds, with the real finding bodies naming fail-closed semantics, matrix rows and acceptance criteria | inline heredoc in `scripts/development-workflow/tests/test-small-finding-terminal-policy.sh` |
| Tier-2 replay ledger | The #1661 replay's ledger shape and bodies on `docs/project/1-business-domain.md`, a non-normative non-shipped path, driving scenario 12a — the only replay that exercises the contract-surface test end to end | inline heredoc in `scripts/development-workflow/tests/test-small-finding-terminal-policy.sh` |
| Cosmetic replay ledger | Scenario 12a's ledger with **only the bodies changed** to cosmetic ones — same shape, head and path — driving scenario 13, so the pair differs in body alone on a tier-2 path | inline heredoc in `scripts/development-workflow/tests/test-small-finding-terminal-policy.sh` |

No repository fixture files are added; both suites build their fixtures inline
and require no network access.

---

## Documentation Updates

Both documents state the **same** rule; the Layer-by-Layer entries above carry
the full wording. Neither may describe the classification as vocabulary-only,
and neither may claim that *every* finding on a normative document is non-small
— only blocking ones reach this rule at all.

- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
      — the normative home: the two-tier rule, the current-head requirement
      covering both the prior rounds
      and the round being decided, the unknown-head behavior, and the four
      `SMALL_FINDINGS_BLOCKED_BY` values with their two within-group
      precedences.
- [ ] `REVIEW.md` — a short block stating that a **blocking** finding on a
      spec, plan, protocol or the review contract itself is never small whatever
      it says; that on other documentation paths a contract-surface finding is
      escalated while a cosmetic one is not; and that the terminal rule requires
      current-head evidence — then pointing to Protocol 93 for the detail.
- [ ] `AGENTS.md` — no change. It does not describe reviewer-loop internals.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The tightening removes the terminal mechanism entirely | Med | High — every PR with a cosmetic documentation tail would loop to its cycle cap | The normative-document list is narrow and enumerated: `docs/project/**`, fixtures, snapshots and `CHANGELOG.md` stay in the second tier, where a cosmetic blocking finding is still small. Scenarios 3, 6 and 13 assert the mechanism still fires there, and proof P6 plants the widening |
| The classification depends on reviewers using particular vocabulary | **High** | High — a contract finding worded as *"required error handling is missing"* contains no listed term and would be cleared as small, which is the original bug for ordinary wording | The vocabulary test is never the only guard: tier 1 makes a blocking finding on a normative document non-small whatever it says, and tier 2's escalation applies only where a cosmetic tail is still wanted. Scenario 2's third case uses a contract finding with no listed term, and proof P12 drops tier 1 and requires it to fail |
| The contract-surface test is written as a deny-list of cosmetic terms | Med | High — an unrecognised contract finding would be classified small, reproducing the bug | The test is an explicit allow-list of surfaces, and a body it does not recognise falls through to the path rule rather than being declared cosmetic; proof P3 plants the inversion |
| Path/body pairing is lost in collection | Med | High — a body would be classified against the wrong path, or a contract finding sharing a path with a cosmetic one would be dropped and the round called small | Findings are collected as one compact JSON object per finding in a dedicated array that is explicitly **not** deduplicated, separate from the existing path array; scenarios 7a and 7c and proof P15 pin it |
| A delimiter-separated record is corrupted by its own data | Med | High — git paths may contain tabs and finding bodies are not tab-escaped, so a column shift would classify a blocker against the wrong text | The record is JSON built with `jq --arg` and read with `jq -r`, which escapes and decodes every field including tabs, quotes and backslashes; `jq` is already a hard dependency. Scenario 7d covers all four hostile characters and proof P17 plants the tab-separated form |
| The encoded body is matched without normalisation | Med | Med — a contract term following a line break abuts the `\n` sequence and misses the word boundary, so the finding is classified small | The sequence is replaced with a space before matching; scenario 7b and proof P16 pin it |
| The producer's newline encoding is treated as reversible | Med | Med — `local-ai-reviewer.sh` does not escape pre-existing backslashes, so a real newline and a literal `\n` are indistinguishable downstream, and a plan that claims to decode them would be specifying something impossible | The plan normalises rather than decodes, states the encoding is lossy, and shows the classification is correct for either original; scenario 7b-i pins both. The raw value is still what is stored and displayed, which proof P18 protects |
| The boundary expression is not portable | Med | High — `\b` works on GNU grep and on the CI runner but not on BSD grep, so tier 2 would silently match nothing on a developer's macOS machine while passing CI | The boundary is `(^|[^[:alnum:]_])…([^[:alnum:]_]|$)`, POSIX ERE and the convention this repository already uses in `local-ai-reviewer.sh`; scenario 4a runs the positive and negative cases under both greps and proof P13 plants the `\b` form |
| The contract-surface test over-matches ordinary prose | **High** | High — matching bare common words like `state`, `scope` or `gate` would make almost every finding non-small, disabling the terminal rule from the restrictive side while appearing to tighten it | Every matched term is a phrase or a qualified form; no bare common word is on the list, and the plan records that an earlier draft's bare terms were removed for this reason. Scenario 6a tests one cosmetic body per removed word, and the parser-risk addendum adds word-boundary negatives (`delegates`/`gate`, `microscope`/`scope`) |
| The current round is decided without checking its own head | Med | High — the rule could terminate on a round whose findings describe a commit that is no longer the head, which is the staleness the brief names | The run is `prior + 1` and both halves are verified: the counter checks prior entries, and **every** reviewer contributing a counted finding to the current round must report `loop_head_sha` before it contributes. Scenario 8a's four combinations pin the `+ 1` half, including the two-platform case where only one contributor is stale; proof P8 plants the omission |
| An old ledger without head data silently counts as current | Med | High — the current-head requirement would be inert on exactly the PRs that predate it | An absent, empty or placeholder head ends the consecutive run; scenarios 9 and 14 and proof P5 pin all three forms |
| Requiring evidence from non-contributing reviewers breaks the count permanently | Med | High — `reviewed_heads[]` lists every configured platform including ones that returned clean or were skipped, so an all-platforms rule disables the terminal rule wherever a reviewer legitimately does not report | The check is scoped to `contributing_platforms[]`, a new ledger field derived from the finding records this item already collects; non-contributors are ignored. Scenario 8b's third row and proof P19 pin it, and the current-round rule is scoped the same way so the two halves agree |
| The counter reads the wrong head field, or trusts a round's classification without its evidence | Med | High — a round could count although a contributing platform reviewed an older commit, which is the staleness the item exists to close | The plan names all three of #1648's head fields and their roles: `classification_head` is the subject and must equal the current head, every `reviewed_heads[]` member is the evidence and must equal that `classification_head`, and `head_sha` is never read because it is the #1502 cap identity key. Scenarios 8b and 8c and proofs P10 and P11 pin both halves |
| A maintainer cannot tell a correctly-refusing loop from a still-failing one, or is shown the less actionable cause | Med | Med | `SMALL_FINDINGS_BLOCKED_BY` names one cause by a documented within-group precedence, and the summary line names **every** cause present — the shipped paths, the matched contract-surface identities, and the platform responsible for any stale or unknown head. Scenario 11 pins all four values and both empty cases, scenario 9a pins the counter's stop reasons that feed the currency pair, scenario 10a pins both within-group boundaries and the groups' mutual exclusivity, and proof P9 plants the inverted precedence |
| The rename of `reviewer_loop_all_paths_non_shipped` breaks an unseen caller | Low | Med | The PR records whether any caller outside this change set exists; a thin wrapper is kept only if one does |

---

## Code Samples

The snippet uses Bash `case` and `[[ ]]`, matching `pr-review-loop.sh`'s own
`#!/usr/bin/env bash` shebang; its contract is `bash`, not `bash-zsh`.

<!-- workflow-shell-contract: bash -->

```bash
# Illustrative — adapt during implementation.

# Tier 1, the fail-closed guard: a blocking finding on one of this repository's
# normative documents is never small, whatever its wording. Consulted from
# reviewer_loop_path_is_non_shipped_artifact before the existing patterns.
reviewer_loop_path_is_normative_document() {
  case "$1" in
    REVIEW.md|AGENTS.md|CLAUDE.md|GEMINI.md|LLM_RULES.md|.ai-dev-workflow.yaml)
      return 0 ;;
    docs/workflow/*|docs/best-practices/*|docs/specs/developments/*|docs/testing/workflow/*)
      return 0 ;;
  esac
  return 1
}


# Tier 2, the escalation: applies only to blocking findings on non-normative,
# non-shipped paths. Never the sole guard, so its vocabulary dependence cannot
# clear a contract finding on a normative document.
#
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
    # Case-insensitive, word-boundary. NOT "\b": that is a GNU/PCRE
    # extension and BSD grep on stock macOS does not recognise it, so even
    # "decision gate" would fail to match there. The explicit character-class
    # form below is POSIX ERE and portable, and it is the convention this
    # repository already uses — see the 401/403 boundary in
    # local-ai-reviewer.sh line 406.
    if printf '%s' "$body" \
      | grep -Eqi "(^|[^[:alnum:]_])(${pattern})([^[:alnum:]_]|\$)"; then
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
1. Add `reviewer_loop_path_is_normative_document` covering the ten first-tier
   patterns and consult it from `reviewer_loop_path_is_non_shipped_artifact`
   before the existing patterns. **Verify**: scenarios 1-3 — the ten patterns
   match and the five controls do not; a blocking finding on a normative
   document is non-small whatever its body says, including one with no listed
   contract term; and a cosmetic blocking finding on `docs/project/**` is still
   small.
2. Add `reviewer_loop_finding_touches_contract_surface` with case-insensitive
   word-boundary matching — via `(^|[^[:alnum:]_])…([^[:alnum:]_]|$)`, never
   `\b`, which BSD grep does not support — over **exactly the spellings the
   normative table lists** — no bare common words, no wildcard separators, and no additional
   variants such as an unhyphenated `allow list`. It **prints the
   matched surface identity** and returns success, printing nothing on no
   match, and resolves ties by first match in table order. **Verify**:
   scenario 4, scenario 6a's seven cosmetic bodies, scenario 10b's identity and
   determinism assertions, and every row of the parser-risk edge-case list
   including the `delegates`/`gate` and `failXclosed` negatives.
3. Add `reviewer_loop_blocking_findings_from_output <output> <count> <platform>`
   emitting one compact JSON object per finding via `jq -c -n --arg`, taking the
   platform as its third argument from the caller's `platform_name`, and
   accumulate the records **without deduplication** into
   `aggregate_blocking_findings`. Before matching, **replace** each occurrence
   of the two-character sequence `\n` with a single space — a normalisation
   applied only to the string handed to the matcher. Do **not** decode it: the
   producer's encoding is lossy and not reversible, and the stored and
   summarised body must remain the value as received. Then replace
   `reviewer_loop_all_paths_non_shipped` with
   `reviewer_loop_all_findings_are_small`. **Verify**: scenarios 5, 6, 7, 7a,
   7b, 7b-i, 7c and 7d — in particular that two findings on one path both
   survive collection, that a path or body containing a tab is classified from
   intact fields, and that a real newline and a literal `\n` give the same
   answer. Record in the PR whether any caller outside this
   change set required the old name.
4. Write `contributing_platforms[]` into each small-findings ledger entry,
   derived from the `platform` field of the `aggregate_blocking_findings`
   records, and extend `reviewer_loop_small_findings_prior_consecutive_count` to
   take the current head and stop at the first entry failing any of:
   `classification_head` equal to the current head; a non-empty
   `contributing_platforms[]`; and every platform named there having a valid
   `reviewed_heads[]` head equal to that `classification_head`. Ignore
   non-contributing platforms. Read `classification_head`, never `head_sha`.
   Report a stop reason from the closed set. **Verify**: scenarios 8, 8b's four
   rows, 8c, 9, 9a and 14.
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
7. Add the replay suite and its three ledger fixtures, including both
   `# covers:` lines on the new suite. **Verify**: scenarios 12, 12a and 13, and that
   `select-test-suites.sh` selects the new suite for a change touching only
   `pr-review-loop.sh`.
8. Update
   `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
   and `REVIEW.md` per **Documentation Updates**. **Verify**: both state the
   same **two-tier** rule — a blocking finding on a normative document is never
   small whatever it says, and on other non-shipped paths a contract-surface
   finding is escalated while a cosmetic one is not — both describe the same
   current-head requirement covering the prior rounds and the round being
   decided, and both name the same four `SMALL_FINDINGS_BLOCKED_BY` values with
   their two within-group precedences. Neither may describe the classification
   as vocabulary-only, and neither may claim that *every* finding on a normative
   document is non-small, since only blocking findings reach this rule.
9. Document the new behavior in the `--help` usage block. **Verify**: run
   `pr-review-loop.sh --help` and confirm the predicate, the contract-surface
   list, the current-head requirement and `SMALL_FINDINGS_BLOCKED_BY` appear.
10. Produce the nineteen planted-violation proofs (P1-P19) and record them in the PR
    under a `Planted-Violation Proofs` heading. **Verify**: each shows two runs
    at a concrete file and line — failing with the violation planted, passing
    once removed. Every proof is mandatory, including the whole restrictive
    group; see the proof-group table for its membership.
11. Run `shellcheck` on `scripts/development-workflow/pr-review-loop.sh` and
    `markdownlint-cli2` on the two changed documentation files, this plan and
    the runbook. **Verify**: both tools exit 0 on every file named here.
12. Add a changelog fragment
    `changelog.d/1652.changed.small-finding-terminal-policy.md` containing
    exactly:

    ```markdown
    - **Tighten the small-finding terminal policy** (#1652): a blocking finding on a spec, plan, protocol or the review contract is no longer classified as small whatever its wording, a finding touching a contract surface is escalated on other documentation paths, and the terminal rule now requires both its prior counted rounds and the round being decided to be on the current head.
    ```

13. Update project docs per **Documentation Updates** above (step 8 covers them;
    no other project doc is affected).

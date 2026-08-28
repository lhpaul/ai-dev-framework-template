# Missed-Finding Telemetry — Implementation Plan

**Spec**:
[1_1651-missed-findings-telemetry_specs.md](./1_1651-missed-findings-telemetry_specs.md)
**Smoke test runbook**:
[1651-missed-findings-telemetry.smoke-test.md](../../../testing/workflow/1651-missed-findings-telemetry.smoke-test.md)

---

## Summary

**Approach**: The reviewer loop already writes one `reviewer_loop_history.v1`
entry per iteration, carrying the head commit, the platforms that ran, and the
blocking count. What it does not record is the comparison the spec asks for:
when an external reviewer reports blocking findings, what the **local**
reviewer's most recent verdict was, and on which commit.

This plan adds a `missed_findings` array to each history entry — one element per
external platform that reported blocking findings in that round — carrying the
reviewer, the reviewed commit, the finding count, up to three paths with the
total, and the local evidence state. It adds the derivation that produces that
state: select the local reviewer's most recent verdict first, classify it
second, and when the verdict is clean, decide the ancestry relationship between
its commit and the reviewed one.

**Two properties do the work, and both are about not overclaiming.** The
numerator is narrow: only `clean_same_commit` is a confirmed miss, and the
ancestor case is recorded separately as a possible miss. The denominator is
wide: a record is written on **every** qualifying external round, including the
ones that are not misses at all, because a rate needs both halves and a
telemetry that records only its numerator can only report 100%.

**Estimated complexity**: M

**Rationale**: The write path is an addition to a builder that already exists,
and the render path is one line per record. What makes it more than small is the
derivation. It reads history the loop wrote earlier, orders verdicts by
recency rather than by outcome, and asks git a question — *is this commit an
ancestor of that one* — that has four possible answers plus a fifth,
undecidable one that a naive implementation silently folds into one of the
four. Every one of those confusions inflates or deflates a number that this
feature exists to make trustworthy.

**Dependencies**: **#1648 must be implemented and merged to
`develop-internal-reviewer-effectiveness` before this item's implementation PR
opens.** The derivation needs to know which commit each reviewer's verdict
describes, per reviewer; that per-reviewer head evidence is what #1648
introduces. #1648's plan is merged and its implementation is not, so this is a
sequencing constraint on implementation only — the two plan PRs are independent.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short origin/develop-internal-reviewer-effectiveness` | `903de533` |
| The history entry builder and its shape | `sed -n '6876,6950p' scripts/development-workflow/pr-review-loop.sh` | `reviewer_loop_history_build_entry` produces a flat object of eighteen fields plus one nested object, `phase_after_clean`. The nested object is the precedent this plan follows: a related group of values belongs in one sub-object rather than as five sibling keys |
| The entry carries no per-platform outcome | Same range | `result` is the **aggregate** loop result for the round and `platforms` is a list of names. A round where the local reviewer was clean and an external one reported findings records `needs_fixes` and nothing that separates them, so the local verdict cannot be recovered from a stored entry. #1648 adds per-reviewer *heads*, not per-reviewer *outcomes* — hence `platform_results` in this plan |
| The per-platform outcome exists in memory but is not persisted | `sed -n '9603,9614p' scripts/development-workflow/pr-review-loop.sh` | `platform_result_tokens[]` holds `name:display` pairs for the current round and is used only to build the summary line. `platform_results` is that data written to the ledger, not a new derivation |
| The configured platform list has a source | `grep -n "workflow_config_review_platforms" scripts/development-workflow/pr-review-loop.sh` | Produced at line 8339. It is the only thing that distinguishes `not_configured` from `not_yet_run`, since both look identical in an empty history |
| Writability is already a decided state — and today it **destroys** the history | `sed -n '6960,7030p' scripts/development-workflow/pr-review-loop.sh` | `append_safe`, `history_status` and `history_unavailable_reason` already exist. On malformed history, unknown schema, or a prior unavailable payload the loop builds a **replacement** payload with `entries: []` and renders it over the previous block. The spec's row 4 is this branch, but AC-7a's byte-for-byte preservation is **not** current behavior and needs the change described in Layer-by-Layer |
| The reason vocabulary that already exists | Same range | `malformed_history`, `unknown_schema`, and a pass-through `prior_unavailable`. Row 4's "report why" is satisfied by surfacing these, not by adding new ones |
| Blocking paths are already extracted per platform | `sed -n '6786,6800p' scripts/development-workflow/pr-review-loop.sh` | `reviewer_loop_blocking_paths_from_output` reads `BLOCKING_<n>_PATH` from a platform's output. The record's path list and total come from here; nothing new parses reviewer output |
| Ancestry has a precedent in this repository | `grep -rn "merge-base --is-ancestor" scripts/development-workflow/` | Two call sites — `validate-branch-reuse.sh:408` and `prepare-release-post-merge-cleanup.sh:532` — both using `git merge-base --is-ancestor A B` with output discarded and the **exit status** read. This plan uses the same form and, unlike both, distinguishes the third exit status |
| The local reviewer's platform name is a fixed string | `grep -n "local-ai-reviewer" .ai-dev-workflow.yaml` | The platform is named `local-ai-reviewer` in configuration, and the loop reports it under that name. The record's "is this the local reviewer" test compares against that name |

**What this log does not establish.** It does not establish that misses are
common, or that the local reviewer is or is not effective. That is the question
the feature exists to make answerable, and answering it before building the
measurement would be assuming the conclusion.

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch for this item | `develop-internal-reviewer-effectiveness` | `integration-branch:internal-reviewer-effectiveness` label on #1651 | 2026-08-28, repo SHA `903de533` | Epic #1647 items | `Verified` |
| Per-reviewer head evidence exists | Introduced by #1648 | #1648's implementation plan, merged | 2026-08-28, repo SHA `903de533` | #1648 and #1651 | `Conflict` — see below |
| The history schema is `reviewer_loop_history.v1` and this plan does not bump it | Additive field only | `REVIEWER_LOOP_HISTORY_SCHEMA` at `pr-review-loop.sh:6720` | 2026-08-28, repo SHA `903de533` | every reader of the ledger | `Verified` |

**Conflict record.** The derivation needs each reviewer's reviewed commit, and
that evidence does not exist on the base branch: #1648's plan is merged, its
implementation is not. Affected plan statements: the whole derivation and every
scenario that exercises it.

**Resolution status**: `Resolved` by sequencing. Recorded in **Dependencies**
and enforced by **Implementation Order step 0**, a hard stop before any code
change. Decision owner: LH — if #1648 is implemented differently from its plan,
this plan must be revised rather than adapted during implementation.

### Not applicable

**Overall result for this check**: `Applicable` — the three rows above are the
assumption surfaces and the implementer must re-verify each at implementation
start. This subsection scopes only surfaces carrying no assumption.

**Surfaces with no assumption**: no database, no runtime service, no
user-facing surface, no scheduled job, no external API, no deployment target.

---

## Layer-by-Layer Changes

### Database / Data Layer

Not applicable.

### Backend / API

Not applicable — this repository ships workflow tooling, not a service.

### Shared Packages / Libraries

- [ ] **Persist per-platform verdicts in the ledger entry.** The entry records
      `result` — the **aggregate** loop result for the round — and `platforms`,
      a list of names with no outcomes. Neither says what the *local* reviewer
      concluded, so a round in which the local reviewer was clean and an
      external one reported findings has `result: "needs_fixes"` and nothing to
      distinguish the two. The derivation below cannot be built on that, and
      AC-4a cannot be satisfied by it. #1648 supplies each reviewer's reviewed
      **head**; it does not supply each reviewer's **outcome**.

      Add `platform_results` to the entry, built from `platform_result_tokens`
      — the `name:display` array the loop already assembles for the summary
      comment at `pr-review-loop.sh:9605`:

      ```text
      "platform_results": [
        {"platform": "local-ai-reviewer", "result": "clean",       "reviewed_head": "<40-hex>"},
        {"platform": "codex-github",      "result": "needs_fixes", "reviewed_head": "<40-hex>"}
      ]
      ```

      `reviewed_head` is #1648's per-reviewer evidence, carried here so one
      array answers both questions the derivation asks.

      **Entries written before this change carry no `platform_results`, and
      those entries yield `unknown` — never the aggregate `result`.** Reading
      the aggregate as if it were the local reviewer's verdict is exactly the
      confusion this field exists to end, and a back-compatibility path that
      reintroduces it would put wrong values into the historical half of the
      data, where nobody would look for them. Fail-closed, and scenario 3a pins
      it.

- [ ] **Select the local reviewer's most recent verdict.** Add
      `reviewer_loop_local_latest_verdict <history_payload> <configured_platforms>`,
      returning one compact JSON object:
      `{"outcome":…,"head_sha":…,"iteration":…}`.

      **Two inputs, because two different questions are being asked.** The
      payload answers *what did the local reviewer most recently conclude*; the
      configured-platform list answers *is it configured at all*, which no
      amount of history can establish — an empty history looks identical for a
      repository that has not run the reviewer yet and one that never will. The
      list is the value `workflow_config_review_platforms` already produces at
      `pr-review-loop.sh:8339`, passed in rather than re-read, so the function
      stays testable without a configuration file.

      It scans `entries[]` in **descending iteration order** and returns the
      first entry whose `platform_results` names the local reviewer, taking
      **that platform's** `result` — never the entry's aggregate `result`. Selection by recency, then
      classification — never "the most recent clean verdict", which is the same
      sentence with the search order and the filter swapped, and which AC-4a
      exists to forbid: a reviewer that cleared one commit and then reported
      findings on a later one is `not_clean`, and reaching past that to the
      earlier clean verdict would count a round as missed on a verdict the
      reviewer itself superseded.

      Three results are not verdicts and are returned as such, because the spec
      separates them and summing them would make different repositories look
      alike:

      | Situation | Returned outcome | Why it is distinct |
      | --- | --- | --- |
      | The local reviewer is **not** in the configured platform list | `not_configured` | a repository that will never produce local evidence — checked **first**, because an unconfigured reviewer with an empty history must not read as `not_yet_run` |
      | It is configured and appears in no entry's `platform_results` | `not_yet_run` | a pull request early in its life |
      | It is configured, entries exist, but none carries `platform_results` — or none names it | `unknown` | the history is healthy and silent, including every entry written before this change |

- [ ] **Classify a clean verdict by ancestry.** Add
      `reviewer_loop_commit_ancestry <clean_head> <reviewed_head>`, printing
      exactly one of `same`, `ancestor`, `descendant`, `unrelated`,
      `undecidable`.

      ```text
      clean_head == reviewed_head                        → same
      git merge-base --is-ancestor clean reviewed  → 0   → ancestor
      git merge-base --is-ancestor reviewed clean  → 0   → descendant
      both return 1                                      → unrelated
      either returns anything else, or a commit is absent → undecidable
      ```

      **`undecidable` is the state a naive implementation loses**, and losing it
      is not cosmetic. `git merge-base --is-ancestor` exits 0 for yes, **1 for
      no, and something else for an error** — a missing object after a
      force-push, a corrupt repository, a shallow clone whose history does not
      reach far enough. Treating "not 0" as "no" turns every one of those into
      `unrelated`, which is a *decided* answer meaning a force-push severed the
      relationship. The record would then assert something the repository never
      established. Both existing call sites in this repository — the two named
      in the Verification Log — read only zero versus non-zero, which is safe
      for their yes/no questions and would be wrong here.

      An `undecidable` result maps to the local evidence state **`unknown`**,
      which the spec's Statuses table defines as the closed list's catch-all:
      *any situation not described by a row*. A clean verdict whose ancestry
      cannot be computed is exactly that. It is neither a confirmed nor a
      possible miss, and it is still recorded, so it lands in the denominator
      where it belongs.

      The function also verifies both commits **exist locally** before asking,
      with `git cat-file -e <sha>^{commit}`; an absent commit is `undecidable`
      rather than an error, because a reviewer loop must not fail a pull request
      over telemetry.

- [ ] **Derive the local evidence state.** Add
      `reviewer_loop_local_evidence_state <local_verdict_json> <reviewed_head>`,
      printing one of the spec's ten values. It is a pure mapping over the two
      previous functions and holds no logic of its own beyond the table:

      | Verdict outcome | Ancestry | State |
      | --- | --- | --- |
      | clean | `same` | `clean_same_commit` |
      | clean | `ancestor` | `clean_earlier_commit` |
      | clean | `descendant` | `clean_later_commit` |
      | clean | `unrelated` | `clean_unrelated_commit` |
      | clean | `undecidable` | `unknown` |
      | needs_fixes | — | `not_clean` |
      | skipped | — | `skipped` |
      | escalate / timeout / credentials | — | `unavailable` |
      | `not_yet_run` | — | `not_yet_run` |
      | `not_configured` | — | `not_configured` |
      | anything else | — | `unknown` |

      Eleven rows over ten states: `unknown` is reached two ways, from an
      undecidable ancestry and from an unrecognised outcome, and the plan keeps
      them as separate rows rather than one so that neither is added by
      accident later.

- [ ] **Build the records.** Add
      `reviewer_loop_missed_finding_records <reviewed_head>`, returning a JSON
      array with one object per **external** platform that reported blocking
      findings this round:

      ```text
      {
        "reviewer": "codex-github",
        "reviewed_head": "<40-hex>",
        "blocking_count": 7,
        "paths": ["a.ts", "b.ts", "c.ts"],
        "path_total": 12,
        "local_evidence_state": "clean_same_commit",
        "classification": "confirmed_miss"
      }
      ```

      Four exclusions, each from a spec rule and each an early `continue`
      rather than a filter on the finished array, so a record that must not
      exist is never built:

      1. the platform **is** the local reviewer — a reviewer cannot miss its
         own findings;
      2. the platform reported no **blocking** findings — advisory findings do
         not qualify;
      3. the reviewed commit cannot be established — no unattributable record;
      4. the round is not eligible at all, which rows 1 and 2 of the spec's
         matrix already cover.

      `classification` is written into the record rather than left for a reader
      to re-derive from the state. AC-17a requires the two counts to be
      separable by a later report, and a reader that re-derives it needs its own
      copy of the confirmed/possible mapping — which is the second copy of a
      rule, and the one that drifts.

- [ ] **Write the array into the entry.** Extend
      `reviewer_loop_history_build_entry` with `missed_findings`, defaulting to
      `[]`. Follow the convention the function already uses for
      `unresolved_thread_count` and `current_run_id`: read from a caller-set
      global rather than adding a nineteenth positional parameter.

      **The schema string stays `reviewer_loop_history.v1`.** The change is
      purely additive, every existing field keeps its name, type and meaning,
      and readers that ignore the new key are unaffected. A bump would break a
      reader that validates the string exactly, for no gain. Scenario 14
      asserts field-by-field that the eighteen existing fields and
      `phase_after_clean` are unchanged.

- [ ] **Preserve the existing history when it cannot be appended to, and report
      the failure.** AC-7a requires the existing history to be left
      byte-for-byte unchanged, and **that is not what the code does today**.
      When `append_safe` is 0, `reviewer_loop_history_payload_from_existing`
      builds a replacement payload with `entries: []` and
      `history_status: "unavailable"`, and the render path writes it over the
      previously posted block — so a history that merely failed to parse this
      once is replaced by an empty stub, and the entries it held are gone from
      the pull request.

      The change, therefore, is a real one and not a report bolted onto
      existing behavior:

      1. When `append_safe` is 0, **do not re-render the history section at
         all.** Leave the previously posted block exactly as it stands,
         including a malformed one — a block that failed to parse is the
         evidence of the failure, and overwriting it destroys the only copy.
      2. Report the failure in the summary body instead, naming the reason the
         loop already computed: `malformed_history`, `unknown_schema`, or the
         passed-through `prior_unavailable`. No new reason vocabulary.
      3. Keep `reviewer_loop_history_unavailable_stub_body` for the case it is
         genuinely for — a pull request with **no** prior history block at all,
         where there is nothing to preserve and the stub is the first thing
         written.

      Scenario 11 asserts the byte-for-byte preservation against the prior
      body, and proof **P7** plants the current stub-replacement behavior.

      **And only when something was owed.** AC-7b requires no telemetry-failure
      report when no record was due — the findings came from the local reviewer,
      or were advisory, or the commit could not be established. The eligibility
      test therefore runs **before** the writability test, matching the spec's
      row ordering, and the plan states the order because the natural
      implementation is the other way round: writability is a property of the
      loop and eligibility is a property of the round, so a programmer checks
      the cheap global first and reports a failure nobody was waiting for.

### Frontend / UI

- [ ] **Render one line per record in the reviewer-loop summary**, at most 200
      characters:

      ```text
      missed-finding: codex-github on 6780c658 — 7 blocking, 12 files (a.ts, b.ts, c.ts) — local: clean, same commit [confirmed miss]
      ```

      The bound is enforced by construction rather than by truncating the
      finished line: paths are appended one at a time and the first one that
      would exceed the bound stops the list. **The total file count and the
      state are written before the paths**, so the two values a reader needs
      most cannot be the ones the bound removes. A line that names zero paths
      is valid — AC-14a says so explicitly — and is what a pull request with
      very long paths produces.

### Infrastructure / Configuration

- [ ] Document `missed_findings` in the `--help` block's ledger description and
      in Protocol 93's reviewer-loop history section.

---

## Testing Strategy

**Test types**: Unit (shell harness), plus the smoke test runbook.

**Key scenarios to test**:

1. `reviewer_loop_local_latest_verdict` returns the **most recent** verdict, not
   the most recent clean one: a history with a clean local verdict at iteration
   2 and a `needs_fixes` local verdict at iteration 5 returns the iteration-5
   verdict. This is AC-4a, and it is the single most likely implementation
   error in the item.
2. It returns `not_yet_run` when the local reviewer is configured and appears in
   no entry's `platform_results`, and `not_configured` when it is absent from
   the configured list — **with the same empty history in both calls**, so the
   only thing that differs is the configured-platform argument. The two are
   asserted to be different values, not merely both non-clean.
3. It returns `unknown` when entries exist but none names the local reviewer.
3a. It returns `unknown` for an entry written **before** this change — one with
    `platforms` but no `platform_results` — even when that entry's aggregate
    `result` is `clean`. Reading the aggregate as the local verdict is the
    confusion `platform_results` exists to end, and a back-compatibility path
    that reintroduced it would put wrong values into the historical half of the
    data.
3b. The verdict comes from the **local reviewer's** entry in
    `platform_results`, not the aggregate: an entry whose aggregate `result` is
    `needs_fixes` because an external reviewer failed, while the local
    reviewer's own result is `clean`, yields `clean`.
4. `reviewer_loop_commit_ancestry` returns each of `same`, `ancestor`,
   `descendant` and `unrelated` against a purpose-built fixture repository with
   two branches and a common root.
5. It returns `undecidable` in three cases: a commit absent from the local
   repository, a `--is-ancestor` exit status other than 0 or 1, and an empty
   commit argument. Asserted as `undecidable` specifically, never as
   `unrelated`.
6. `reviewer_loop_local_evidence_state` produces each of the ten states, one
   case per row of its eleven-row table, including both routes to `unknown`.
7. A record is **not** built for the local reviewer's own blocking findings.
8. A record is **not** built for an external platform whose findings are
   advisory only.
9. A record **is** built for an external platform with blocking findings whose
   local evidence state is `not_clean` — the denominator case. A record that
   only appeared for misses is the failure this scenario guards.
10. Two qualifying rounds produce two records; the second does not replace the
    first, and no de-duplication occurs even when reviewer, commit and finding
    count are identical.
11. With `append_safe` at 0 and a prior history block present, no record is
    written, the prior block is **byte-for-byte unchanged** — asserted against a
    saved copy of the prior body, not against a re-render — and the summary body
    names the reason. A separate case with **no** prior block writes the
    unavailable stub, which is what the stub is for.
12. With `append_safe` at 0 **and** no record owed — local-reviewer findings, or
    advisory only — the output contains **no** telemetry-failure report. AC-7b,
    and the scenario that fails if the two tests are ordered the other way.
13. The summary line: one line per record; at most 200 characters; at most three
    paths; the total always stated; and a case with paths long enough that zero
    fit, which must still state the total and the state.
14. The history entry retains all eighteen existing fields and the
    `phase_after_clean` object, unchanged in name and type, and adds exactly
    two: `platform_results` and `missed_findings`. Asserted against an
    enumerated list, not a count.
15. Twenty records add at most twenty lines and 4,000 characters, with paths
    chosen to be long — AC-15, which is only meaningful when the fixture tries
    to break it.
16. A record carries `classification` directly, and the confirmed and possible
    counts are separable by reading records alone, with no reader-side mapping
    from state to classification.

**Files**:

- `scripts/development-workflow/tests/test-pr-review-loop.sh` — scenarios 1
  through 3 and 6 through 16, in the existing `HARNESS_MODE=1` harness.
- `scripts/development-workflow/tests/test-reviewer-loop-commit-ancestry.sh` —
  a new suite for scenarios 4 and 5, which need a real temporary git repository
  with a divergent branch and a deleted object. It must declare:

  ```text
  # covers: scripts/development-workflow/pr-review-loop.sh
  # covers: docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md
  ```

**Smoke test runbook**:
`docs/testing/workflow/1651-missed-findings-telemetry.smoke-test.md`

**Regression suite**: the two shell harnesses named above.

---

## Seed Data

| Fixture | Contents | Location |
| --- | --- | --- |
| Verdict-order history | A `reviewer_loop_history.v1` payload with a clean local verdict at iteration 2 and a `needs_fixes` local verdict at iteration 5 | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Absent-reviewer histories | One payload where the local reviewer appears in no entry, and one where it is absent from the configured platform list | inline in the same file |
| Ancestry repository | A temporary git repository: a root commit, a branch of two commits, a second branch of two commits from the same root, and one commit created then deleted with `git prune` to produce the absent-object case | created and torn down by `test-reviewer-loop-commit-ancestry.sh` |
| Long-path record | A record whose three paths each exceed 60 characters, so no path fits within the 200-character bound | inline in `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Twenty-record entry | Twenty records with long paths and large finding counts, for AC-15 | inline in the same file |

---

## Documentation Updates

- `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
  — the `missed_findings` array, the ten states, and the summary line format.
- The `--help` block of `pr-review-loop.sh`, where the ledger is described.
- No `REVIEW.md` change: this item adds telemetry, not a review rule.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Ancestry errors are folded into `unrelated` | **High** — it is what both existing call sites do | **High** — the record asserts a force-push severed the relationship when the repository simply could not answer, and the number is wrong in a way nobody can see | `reviewer_loop_commit_ancestry` returns five values, not four; only exit status 1 from both directions is `unrelated`; anything else is `undecidable`, which maps to `unknown`. Scenario 5 covers three routes to it and proof **P3** plants the fold |
| The derivation reaches for the most recent **clean** verdict | **High** — it is the more natural sentence, and it reads as more helpful | **High** — a reviewer that cleared one commit and then reported findings on a later one would be recorded as having missed something it had already caught | Selection is by recency and classification is second, stated in that order in the plan and in the function's name. Scenario 1 and proof **P1** |
| Records are written only for misses | Med | **High** — the denominator becomes unknowable and the reported rate is always 100% | A record is written on every qualifying external round, including `not_clean` and `unknown`. Scenario 9 and proof **P2** |
| A telemetry failure is reported when nothing was owed | Med | Low — noise on pull requests where the feature had nothing to do, which erodes trust in the signal | The eligibility test runs before the writability test, matching the spec's row order. Scenario 12 and proof **P5** |
| The summary line's bound is enforced by truncating the finished string | Med | Med — truncation removes the tail, which is where the state and the classification sit | The line is built with the total and the state **before** the paths, and paths stop at the first one that would exceed the bound. Scenario 13's zero-path case and proof **P6** |
| The additive fields break a ledger reader | Low | Med | The schema string is unchanged and every existing field keeps its name and type; scenario 14 asserts them individually |
| A pre-change entry's aggregate result is read as the local reviewer's verdict | **High** — it is the only outcome those entries carry | **High** — rounds the local reviewer never ran become confirmed misses, in the historical half of the data where nobody checks | Entries without `platform_results` yield `unknown`, never the aggregate. Scenario 3a and proof **P8** |
| An unappendable history is replaced by an empty stub | **High** — it is the current behavior | **High** — every entry the pull request held is lost, and the stub looks like a well-formed report rather than a deletion | The render path leaves the prior block untouched; the stub is written only when there is no prior block. Scenario 11 and proof **P7** |

---

## Code Samples

The two functions the whole feature's honesty rests on:

<!-- workflow-shell-contract: bash -->

```bash
# Five answers, not four. `git merge-base --is-ancestor` exits 0 for yes,
# 1 for no, and other for error; folding "other" into "no" would record
# `unrelated` — a decided answer — for a question the repository could not
# answer at all.
reviewer_loop_commit_ancestry() {
  local clean="${1:-}" reviewed="${2:-}" status

  [ -n "$clean" ] && [ -n "$reviewed" ] || { printf 'undecidable\n'; return 0; }
  [ "$clean" = "$reviewed" ] && { printf 'same\n'; return 0; }

  git cat-file -e "${clean}^{commit}" 2>/dev/null || { printf 'undecidable\n'; return 0; }
  git cat-file -e "${reviewed}^{commit}" 2>/dev/null || { printf 'undecidable\n'; return 0; }

  git merge-base --is-ancestor "$clean" "$reviewed" >/dev/null 2>&1
  status=$?
  [ "$status" -eq 0 ] && { printf 'ancestor\n'; return 0; }
  [ "$status" -ne 1 ] && { printf 'undecidable\n'; return 0; }

  git merge-base --is-ancestor "$reviewed" "$clean" >/dev/null 2>&1
  status=$?
  [ "$status" -eq 0 ] && { printf 'descendant\n'; return 0; }
  [ "$status" -ne 1 ] && { printf 'undecidable\n'; return 0; }

  printf 'unrelated\n'
}

# Recency first, outcome second. Never "the most recent clean verdict", and
# never the entry's aggregate `.result` — that is the round's outcome, not the
# local reviewer's. Entries with no platform_results yield unknown.
reviewer_loop_local_latest_verdict() {
  local payload="${1:-}" configured="${2:-}"

  case ",${configured}," in
    *,local-ai-reviewer,*) ;;
    *) printf '{"outcome":"not_configured","head_sha":"","iteration":0}\n'
       return 0 ;;
  esac

  printf '%s' "$payload" | jq -c '
    [ (.entries // [])[]
      | . as $entry
      | ((.platform_results // [])[]
         | select(.platform == "local-ai-reviewer")
         | {outcome: (.result // "unknown"),
            head_sha: (.reviewed_head // $entry.head_sha // ""),
            iteration: $entry.iteration})
    ]
    | sort_by(.iteration)
    | last
    // {outcome: "not_yet_run", head_sha: "", iteration: 0}'
}
```

---

## Planted-Violation Proofs

`REVIEW.md` → Core Rules → Verification Discipline requires two demonstrated
runs per proof, each citing a concrete file and line. The eight proofs fall into
two groups:

| Group | Count | Proofs | What the plant reproduces |
| --- | --- | --- | --- |
| Overclaiming | **5** | P1, P2, P3, P4, P8 | a number asserted on evidence that does not support it |
| Contract | **3** | P5, P6, P7 | a report, a line, or a stored history that breaks its own stated contract |

| # | Violation to plant | Where | Check that must fail, then pass |
| --- | --- | --- | --- |
| P1 | Select the most recent **clean** local verdict instead of the most recent verdict | a scratch copy of `reviewer_loop_local_latest_verdict` | scenario 1 fails: a reviewer that cleared iteration 2 and reported findings at iteration 5 is recorded as `clean_earlier_commit` — a possible miss — on a verdict it had already superseded. The confirmed and possible counts both rise on evidence the reviewer itself withdrew; restoring recency-first selection passes |
| P2 | Write records only when the state is a confirmed or possible miss | a scratch copy of the record builder | scenario 9 fails: the denominator disappears, and every report built on these records reads 100% missed. This is the failure that makes the whole feature worse than nothing, because it produces a confident wrong number rather than no number; restoring the every-qualifying-round rule passes |
| P3 | Treat any non-zero `--is-ancestor` status as "not an ancestor" | a scratch copy of `reviewer_loop_commit_ancestry` | scenario 5 fails in all three cases: an absent commit, a non-0/1 exit, and an empty argument are all recorded as `clean_unrelated_commit`, asserting a severed relationship the repository never established. Scenario 4 still passes, which is the point — the plant is invisible to every test with a healthy repository; restoring the five-way return passes |
| P4 | Merge `not_yet_run` into `not_configured` | a scratch copy of the verdict selector | scenario 2 fails: a pull request early in its life and a repository with no local reviewer become the same value, and the report can no longer tell "has not run yet" from "will never run"; restoring the two values passes |
| P5 | Test writability before eligibility | a scratch copy of the record entry point | scenario 12 fails: a round whose only findings came from the local reviewer reports a telemetry failure on an unwritable history, though no record was owed. Scenario 11 still passes; restoring the spec's row order passes both |
| P7 | Keep the current behavior: re-render the history section with the unavailable stub when `append_safe` is 0 | a scratch copy of the render path | scenario 11 fails: the prior block is replaced by an empty stub, so a history that failed to parse once loses every entry it held — and the loss is invisible, because the stub looks like a well-formed report of a problem; restoring the do-not-re-render rule passes |
| P8 | Fall back to the entry's aggregate `result` when `platform_results` is absent | a scratch copy of the selector | scenario 3a fails: a pre-change entry whose round was aggregate-clean is read as a clean **local** verdict, so rounds the local reviewer never ran are recorded as confirmed misses. The plant only affects historical entries, which is where nobody looks; restoring the `unknown` fallback passes |
| P6 | Enforce the 200-character bound by truncating the finished line | a scratch copy of the renderer | scenario 13's long-path case fails: truncation removes the tail, which is where the local evidence state and the classification sit, so the line that survives is the one carrying paths and no verdict — exactly inverted from what a reader needs; restoring build-order enforcement passes |

Five proofs plant the overclaiming direction because that is the direction with
no symptom: every one of them produces a plausible number, and a number is
believed. P3 is the one to read twice — its plant passes every test written
against a healthy repository, and only a fixture with a deliberately deleted
object exposes it.

---

## Implementation Order

0. **Hard stop**: confirm #1648 is implemented and merged into
   `develop-internal-reviewer-effectiveness`, and that its per-reviewer head
   evidence matches what its plan describes. If it does not, stop and revise
   this plan. **Verify**: the merged commit and the field names it introduced.
1. Add `reviewer_loop_commit_ancestry`. **Verify**: scenarios 4 and 5 in the new
   suite, including the deleted-object fixture.
1a. Add `platform_results` to `reviewer_loop_history_build_entry`, built from
   `platform_result_tokens`. **Verify**: scenario 14 and scenario 3b.
2. Add `reviewer_loop_local_latest_verdict`, taking the history payload and the
   configured-platform list. **Verify**: scenarios 1, 2, 3, 3a and 3b — recency
   over cleanliness, the two absent-reviewer values kept apart by the
   configuration argument alone, and the `unknown` fallback for pre-change
   entries.
3. Add `reviewer_loop_local_evidence_state`. **Verify**: scenario 6 — one case
   per row, including both routes to `unknown`.
4. Add `reviewer_loop_missed_finding_records` with its four exclusions as early
   `continue`s. **Verify**: scenarios 7, 8, 9, 10 and 16.
5. Extend `reviewer_loop_history_build_entry` with `missed_findings`, schema
   string unchanged. **Verify**: scenario 14, field by field.
6. Change the render path so an unappendable history is **not** re-rendered,
   and add the eligibility-then-writability ordering and the row-4 report.
   **Verify**: scenarios 11 and 12, including the byte-for-byte comparison
   against a saved prior body.
7. Add the summary renderer. **Verify**: scenarios 13 and 15, including the
   zero-path line.
8. Update Protocol 93 and the `--help` block. **Verify**: runbook Step 9 reads
   both against the code.
10. Produce the eight planted-violation proofs (P1-P8) and record them in the PR
   with the command, file, line and both outcomes for each.

---

## Rollback

Revert the implementation PR. The change is additive: one array in the history
entry, three derivation functions, one renderer. Reverting leaves the ledger
with `missed_findings` keys on historical entries, which readers ignore, and no
other behavior depends on them.

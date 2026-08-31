# Strict Implementation-Plan Review — Implementation Plan

**Spec**:
[1_1655-strict-plan-review-mode_specs.md](./1_1655-strict-plan-review-mode_specs.md)
**Smoke test runbook**:
[1655-strict-plan-review-mode.smoke-test.md](../../../testing/workflow/1655-strict-plan-review-mode.smoke-test.md)

---

## Summary

**Approach**: #1650 builds a strict pass for **one** stage: one checklist, one
key prefix, one response marker, each hard-coded at the site that uses it. This
item needs a second of all four, and its spec requires both to report a state on
**every** review (AC-24) while never both reaching `applied` (AC-25).

So this plan does not add a parallel copy of the strict pass. It turns #1650's
into a **registry with one entry per strict checklist** — stage, checklist path,
key prefix, response marker, and what the entry supplies to its pass — and adds
the plan entry beside the spec one. The dispatch, the parser, the extraction and
the refusals are #1650's, unchanged in behaviour and read from the entry instead
of from literals.

Three things are new, and all three belong to the plan entry alone:

1. **The documents under review are supplied, at the reviewed head.** The spec
   checks needed nothing but the checklist; the plan checks need the plan
   document itself, and its source. They are read with
   `git show "$HEAD_SHA:<path>"` rather than from the working tree — see the
   Verification Log, which records that the reviewer's working tree is pinned to
   the reviewed head only when `--repo-root` is passed.
2. **The applied set can be a proper subset of the checklist**, and is reported.
   Three of the seven checks compare the plan against its source; when no source
   document is in the repository they are not applied, and a count whose
   denominator is unknown is not a rate.
3. **`not_applicable` carries a reason.** The plan checklist has two ways not to
   apply — a different stage, and a plan-stage pull request that changes only a
   smoke-test runbook — where the spec checklist has one.

**Estimated complexity**: M

**Rationale**: The mechanism exists and this adds a second instance of it, which
is S-shaped work. What makes it M is that the instance does not fit the shape:
the registry is a refactor of code that is **not merged yet**, and the two
behaviours above have no place in #1650's structure to sit. The failure modes
are quiet in the same way #1650's were — a document read from the wrong revision
produces confident findings about text the pull request does not contain, and
nothing in the output shows it.

**Dependencies**: two hard, both restated as step 0 of the Implementation Order
rather than left to it.

- **#1650's implementation.** Not its plan — its code. This item refactors the
  strict pass into a registry, and there is nothing to refactor until #1650 has
  shipped one. Recorded as a `Conflict` below.
- **#1653's implementation**, transitively through #1650 and directly here: the
  checks run at the `plan` stage, and `review_stage` is #1653's.

**#1657 is a consumer, not a dependency.** It reads the counts and the applied
sets this item records; it does not need to exist for this item to ship, and
this item does not need to know its shape beyond producing a denominator.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short origin/develop-internal-reviewer-effectiveness` | `ef0a91cc` — after this item's spec (#1679) merged. Every row below was run at this revision |
| The reviewer's working tree is **not** guaranteed to be at the reviewed head | `sed -n '264,289p' scripts/development-workflow/local-ai-reviewer.sh` | The `HEAD == HEAD_SHA` check and the `cd` into the checkout are both inside `if [ -n "$REPO_ROOT" ]`. Without `--repo-root` the script reviews whatever directory it was started in, and only requires that `REVIEW.md` exist there (line 300). **This is why the documents are read with `git show "$HEAD_SHA:<path>"`** rather than from the working tree |
| The context bundle carries no file contents | `sed -n '339,366p' scripts/development-workflow/local-ai-reviewer.sh` | Thirteen fields: identifiers, branches, `changed_files`, `pr_body` truncated at 20000 characters, `diff_name_status`, `diff_stat`, `graph_context`, and `review_contract` as the string `"REVIEW.md"`. **No field carries the text of any file**, and `changed_files` is a list of paths |
| The bundle carries no issue body | Same range | Nothing derived from the tracker reaches the reviewer. The refactor brief the spec defers under Out of Scope 4 is not merely inconvenient to fetch — no existing field would carry it |
| `graph_context` is a mode name, not content | `grep -n 'graph_context' scripts/development-workflow/local-ai-reviewer.sh` | Twelve matches; the value is one of `none`, `code-review-graph`, `graphify`, `skipped`. It is a strategy label |
| The plan-document path pattern already exists, in another script | `sed -n '124,138p' scripts/development-workflow/check-documentation-stage-alignment.sh` | `path_allowed_for_stage plan` accepts `^docs/specs/developments/.+/2_.+_implementation-plan(\.doc)?\.md$` **or** `^docs/testing/.+\.smoke-test\.md$`. This item needs the first alternative alone, which is why the extraction below splits them rather than reusing the predicate whole |
| Both scripts already source the shared library | `grep -n 'workflow-lib.sh' scripts/development-workflow/{check-documentation-stage-alignment.sh,local-ai-reviewer.sh}` | Lines 6-7 and 10-11. The extracted predicate has a home both callers already load; no new sourcing is introduced |
| The file-level "implementation in a plan-only PR" case is already gated | `sed -n '150,196p' scripts/development-workflow/check-documentation-stage-alignment.sh` | `classify_state` returns `mismatch` with reason `unexpected implementation or non-stage files changed` for any changed path outside the allowlist. It is deterministic and it blocks. **This item adds no check over the changed-file list**, per the spec's Out of Scope 6 |
| `REVIEW.md` has a Plan Review Checklist and this item does not touch it | `awk '/^## /{print NR": "$0}' REVIEW.md` | Five level-2 sections at lines 14, 64, 113, 198, 379. The Plan Review Checklist is line 113 and stays as it is, blocking findings included — the spec's § Relationship to checks that already exist |
| Its items, counted by extraction | `awk 'NR>=122 && NR<=174 && /^- /' REVIEW.md \| wc -l` | 18 top-level items under `Check:`. This is the count the spec cites |
| The review's timeout has one source and a default | `grep -n 'TIMEOUT=' scripts/development-workflow/local-ai-reviewer.sh` | Line 170, `TIMEOUT="${LOCAL_AI_REVIEWER_TIMEOUT:-300}"`, and line 176 for `--timeout`. AC-16c is satisfied by adding nothing here; the plan pass takes what remains of the same value, as #1650's spec pass does |
| The evidence JSON is one fixed `jq -n` object | `sed -n '512,556p' scripts/development-workflow/local-ai-reviewer.sh` | Named arguments only; no map over emitted keys. A `strict_plan` object has to be added explicitly, as #1650 adds `strict_spec` |
| Evidence keys reach the loop **summary** unchanged | `sed -n '754,772p' scripts/development-workflow/pr-review-loop.sh` | `emit_prefixed_platform_output` re-emits every key but five reserved ones, so `STRICT_PLAN_*` reaches the comment with no loop change |
| The **ledger** forwards nothing arbitrary | `sed -n '6876,6952p' scripts/development-workflow/pr-review-loop.sh` | `reviewer_loop_history_build_entry` builds a fixed object from named locals and globals. The `strict_plan` object has to be added there, beside the `strict_spec` object #1650 adds |
| The `markdown-lint` workflow filters by path | `sed -n '12,24p' .github/workflows/markdown-lint.yml` | Eleven `paths` entries; none matches `docs/workflow/**`. A checklist-only change is unlinted until its path is added — the same gap #1654 found and #1650 records |

**What this log does not establish.** It does not show that the seven plan
checks find defects a reader would act on; no such measurement exists yet, and
producing it is #1657's work. It does not establish anything about #1650's
implementation, which does not exist at this revision — see the `Conflict`
below. And it does not bound the cost of supplying whole plan documents to a
reviewer command, which depends on that command; **Risks** records what happens
when it fails rather than claiming it will not.

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch | `develop-internal-reviewer-effectiveness` | `integration-branch:internal-reviewer-effectiveness` label on #1655; Protocol 91 § Integration-branch base override | 2026-08-31, repo SHA `ef0a91cc` | Epic #1647 items; no other epic pull request is open against this base | `Verified` |
| The reviewer's cwd is not pinned to the reviewed head | The `HEAD == HEAD_SHA` guard is conditional on `--repo-root` | `local-ai-reviewer.sh:264-289` | 2026-08-31, repo SHA `ef0a91cc` | `local-ai-reviewer.sh` and its suite | `Verified` — the plan supplies documents by `git show`, not by reading the tree |
| The plan-document path pattern | `^docs/specs/developments/.+/2_.+_implementation-plan(\.doc)?\.md$` | `check-documentation-stage-alignment.sh:131` | 2026-08-31, repo SHA `ef0a91cc` | that script and `local-ai-reviewer.sh` | `Verified` — extracted to `workflow-lib.sh` unchanged |
| A strict pass exists to make a registry of | `review_stage`, the checklist supply, the second invocation, the strict parser, the extraction and its refusals | #1650's merged plan | 2026-08-31, repo SHA `ef0a91cc` | #1650 and #1655 | `Conflict` — see below |

**Conflict record.** This item refactors #1650's strict pass into a registry and
adds an entry to it. #1650's **plan** is merged; its **implementation** is not,
and no strict pass exists on the base branch at `ef0a91cc`. Affected plan
statements: every bullet under Shared Packages / Libraries that says "read from
the entry rather than from a literal", the whole of Testing Strategy's inherited
scenarios, and the Rollback section.

**Resolution status**: `Resolved` by sequencing — **Implementation Order step
0**, a hard stop on #1650's implementation being merged. Decision owner: LH. If
#1650 ships with a different structure — a different key set, a different
extraction contract, or a parser that is not reusable across checklists — this
plan is revised rather than adapted, because a registry over a shape that does
not exist is not a refactor.

### Not applicable

**Overall result for this check**: `Applicable` — the four rows above must be
re-verified at implementation start.

**Surfaces with no assumption**: no database, no runtime service, no
user-facing surface, no scheduled job, no external API and no deployment
target. The change is confined to two workflow scripts, one shared library, two
documents, one CI path filter and two test suites.

---

## Layer-by-Layer Changes

### Database / Data Layer

Not applicable.

### Backend / API

Not applicable — this repository ships workflow tooling, not a service.

### Shared Packages / Libraries

- [ ] **Extract the plan-document path predicate into `workflow-lib.sh`.**
      `workflow_is_plan_document_path <path>` returns success for
      `^docs/specs/developments/.+/2_.+_implementation-plan(\.doc)?\.md$` and
      nothing else. `check-documentation-stage-alignment.sh` calls it in the
      first alternative of `path_allowed_for_stage plan`, keeping its
      smoke-test-runbook alternative where it is; `local-ai-reviewer.sh` calls
      it to decide which changed paths are plan documents.

      **The regex moves unchanged**, and the move is behaviour-preserving for
      the readiness gate by construction rather than by intention: the gate's
      existing fixtures are re-run and must classify identically. Two copies of
      a path contract that decides both what may appear on a plan pull request
      and what gets reviewed on one is the shape that drifts, and the drift
      would be silent in the direction that matters — a path the gate allows and
      the reviewer does not recognise is a plan document nobody checks.

- [ ] **Turn the strict pass into a registry.** One entry per strict checklist,
      each carrying:

      | Field | Spec entry (#1650) | Plan entry (this item) |
      | --- | --- | --- |
      | stage | `spec` | `plan` |
      | checklist | `docs/workflow/development-workflow/strict-spec-checks.md` | `docs/workflow/development-workflow/strict-plan-checks.md` |
      | key prefix | `STRICT_SPEC` | `STRICT_PLAN` |
      | evidence object | `strict_spec` | `strict_plan` |
      | response marker | `strict_spec_checks` | `strict_plan_checks` |
      | extra bundle keys | none | the documents under review and their sources |
      | reports its applied set | no | yes |
      | reason in `not_applicable` | no | yes |

      Every entry runs #1650's logic: the state test that decides dispatch, the
      derived bundle, `LOCAL_AI_REVIEWER_MODE`, the second invocation bounded by
      the remaining `--timeout`, the strict `jq` program with its mode guard,
      the identifier extraction and its three refusals, and the merge that keeps
      the two responses apart. **None of that behaviour changes**; what changes
      is that it reads its four literals from the entry.

      **Every entry computes and reports a state on every review**, which is
      AC-24: on a spec pull request the plan entry reports `not_applicable` with
      reason `stage_not_plan` and the spec entry reports `applied`, and the
      reverse holds on a plan pull request.

      **At most one entry dispatches a pass**, which is AC-25 and follows from
      the entries having distinct stages and a change having one stage. It is
      not a rule the code enforces separately; it is a property of the stage
      test each entry already runs, and the test in scenario 15 asserts the
      property rather than trusting it.

      **The findings block stays `STRICT_<n>_*`**, shared between entries with
      no prefix of its own. That is safe for exactly one reason — AC-25 — and
      the reason is worth writing down because it is the kind of thing a later
      third checklist would break. A checklist whose stage overlapped another's
      would put two sets of findings into one numbered block, and nothing in the
      output would say which came from which.

- [ ] **Add `docs/workflow/development-workflow/strict-plan-checks.md`**, one
      level-3 section per check, in the spec's order, each carrying its
      identifier, its question and the shape of finding it produces:

      ```text
      ### source_declaration
      ### unspecified_step
      ### spec_traceability
      ### ac_test_coverage
      ### phase_ordering
      ### dependency_state
      ### reversal_risk
      ```

      The heading format is #1650's extraction contract — the identifier alone
      on the line, matching `[a-z][a-z0-9_]*` — so the identifiers are read from
      this document and defined nowhere else. Each section also states whether
      the check needs the source, because that is what the applied-set
      computation reads; see the next bullet.

- [ ] **Declare which checks need the source, in the checklist.** Each section
      carries one line, `Source: required` or `Source: not required`, and the
      applied set is computed from those lines rather than from a list in the
      script. An eighth check is then one edit to one document, which is the
      same property #1650 bought with `$known_checks`.

      **Two spellings exist and the boundary between them is one line of `sed`.**
      The document says `not required`, because it is read by people; the
      internal token is `not_required`, because it is compared in `jq` where a
      space is a hazard. The extraction maps one to the other at the point of
      reading — see **Code Samples** — and no other site sees both. Everything
      downstream of the extraction uses `required` and `not_required`; the
      checklist and this plan's prose use `required` and `not required`.

      **The extraction gains a fourth refusal.** #1650 refuses a checklist whose
      headings and identifiers disagree, one that repeats an identifier, and one
      with no headings at all. A section with no `Source:` line, or with a value
      that is neither, is `checklist_unreadable` on the same grounds: a check
      whose applicability is unknown cannot be silently placed in either group,
      and placing it in the applied set would report coverage the pass did not
      have.

- [ ] **Supply the documents, at the reviewed head.** For the plan entry, the
      derived bundle gains two keys beyond #1650's checklist key:

      ```text
      strict_plan_documents: [ { path, text }, ... ]   # the changed plan documents
      strict_plan_sources:   [ { plan_path, source_path, text }, ... ]
      ```

      Each `text` is `git show "$HEAD_SHA:<path>"`. **Not the working tree**:
      the Verification Log records that the tree is pinned to the reviewed head
      only under `--repo-root`, and a plan read from an unpinned tree produces
      findings about text the pull request does not contain — confidently, and
      with nothing in the output to show it. `git show` also makes AC-12's
      "full text at the reviewed head" literal rather than approximate, which
      matters most on an **amendment** pull request whose diff touches three
      lines of a thousand-line document.

      A `git show` that fails for any listed path is AC-12b: `unavailable` with
      reason `strict_pass_failed`, and **no pass is dispatched**, because the
      failure is known before the call.

      The source is resolved by path convention: for
      `docs/specs/developments/<dir>/2_<slug>_implementation-plan.md` the source
      is `docs/specs/developments/<dir>/1_<slug>_specs.md`, supplied when
      `git show` retrieves it and omitted when it does not.

- [ ] **Compute the applied set, and do not try to explain it.** The set is all
      seven when at least one source was supplied, and the four `Source: not
      required` checks when none was.

      **The script cannot tell a Refactor plan from one whose declared spec is
      missing, and must not try.** The spec's source column has three values;
      the script sees two, because whether an absent source is a defect depends
      on what the plan *declares*, which is prose. That is check 1's question,
      and check 1 is applied in all three cases precisely because it needs no
      source. The mapping is exact rather than lossy: the spec requires the
      applied set to be identical across all three (AC-19c), and the script
      computes only the applied set.

      A script that parsed the plan's `**Spec**:` header to make the
      distinction would be answering a checklist question in shell, and would
      answer it wrong on the first plan that phrased the line differently.

- [ ] **Report the state, the reason, the applied set and the count.** Six
      `print_kv` keys — **one** always emitted, five conditional:

      ```text
      # always emitted
      STRICT_PLAN_STATE=applied|not_applicable|unavailable

      # conditional
      STRICT_PLAN_REASON=stage_unresolved|stage_not_plan|no_plan_document_changed
                        |checklist_unreadable|strict_pass_failed
                                          # only when not applied
      STRICT_PLAN_APPLIED=<ids>           # comma-separated; only when applied
      STRICT_PLAN_COUNT=<n>               # only when applied; may be 0
      STRICT_PLAN_CHECKS=<ids>            # comma-separated; only when applied
      STRICT_PLAN_UNKNOWN_COUNT=<n>       # only when applied and above zero
      ```

      Two of these diverge from #1650's key set, and both divergences are
      required by this item's spec rather than chosen:

      1. **`STRICT_PLAN_REASON` is emitted in `not_applicable` too**, where
         `STRICT_SPEC_REASON` is emitted only in `unavailable`. The plan
         checklist has two ways not to apply — `stage_not_plan` and
         `no_plan_document_changed` — and a plan-stage pull request that changed
         only a smoke-test runbook would otherwise be indistinguishable in the
         record from a spec pull request. #1657 has to exclude both from a
         denominator it can name.
      2. **`STRICT_PLAN_APPLIED` exists and `STRICT_SPEC_APPLIED` does not.**
         AC-24 requires #1650's reported values to be unchanged, and adding a
         key to its block would change them. The asymmetry is also true rather
         than merely permitted: the spec checks have no partial-application
         path, so their applied set is the whole checklist on every `applied`
         round, and a key whose value never varies records nothing #1657 cannot
         read from the checklist. The registry carries the behaviour as a
         per-entry field, so if #1650's checks ever gain a partial path the key
         follows — with a #1650 spec amendment, not with a quiet addition here.

      `STRICT_PLAN_COUNT`, `STRICT_PLAN_CHECKS` and `STRICT_PLAN_APPLIED` are
      **absent** outside `applied`, never `0` and never an empty list rendered
      as something. `0` means the applied checks ran and found nothing, and it
      is the only thing separating a clean plan from one the checks never
      examined.

      The same six go into the evidence JSON under a `strict_plan` object and
      into the ledger entry, by #1650's rule: **the object mirrors the output**,
      and a key not emitted is a field that is absent rather than present and
      null.

- [ ] **Carry the six values into the ledger**, in
      `reviewer_loop_history_build_entry`, beside the `strict_spec` object
      #1650 adds there and by the same convention — values read from globals set
      by the caller that already reads `RESULT` and `BLOCKING_COUNT`. The object
      is **absent** on rounds with no local reviewer at all, which is not the
      same fact as `not_applicable`.

- [ ] **Name the document on every finding.** `STRICT_<n>_PATH` carries the plan
      document the finding applies to, including for the three checks that
      compare it against a source: the document under review is the plan, and a
      finding pointing at the spec would send a reader to a file this pull
      request does not change. AC-2 and AC-13.

### Frontend / UI

- [ ] In the reviewer-loop summary, the strict findings section gains the
      applied set on plan-stage rounds — the count is not readable without it.
      The section still appears only when the state is `applied` and the count
      is above zero; the spec's outcome table touches the comment surface in one
      row group.

### Infrastructure / Configuration

- [ ] Document the six keys, the three states, the five reasons, the applied-set
      semantics, the registry and its entries, and the plan entry's response
      marker `strict_plan_checks` in the `--help` block of
      `local-ai-reviewer.sh`, in
      `docs/workflow/development-workflow/integrations/local-ai-reviewer.md`,
      and in Protocol 93.
- [ ] Add both checklists' directory to `markdown-lint.yml`'s `paths` filter.
      `docs/workflow/**` matches neither of the eleven current entries, so a
      checklist-only change is unlinted today. #1650 adds its own file; this
      item adds the directory, which is the fix that does not need a third edit
      for a third checklist.
- [ ] `changelog.d/1655.added.strict-plan-review-mode.md`.

---

## Interaction with #1650

This item **depends on** #1650's implementation and then edits it. The seam is
worth stating precisely, because "refactor into a registry" can mean anything
from renaming two variables to rewriting the pass.

| | #1650 ships | This item changes it to |
| --- | --- | --- |
| Stage test | `[ "$review_stage" = spec ]` | the entry's stage |
| Checklist path | a literal | the entry's checklist |
| Key prefix | `STRICT_SPEC_` in six `print_kv` calls | the entry's prefix |
| Response marker | `strict_spec_checks` in the `jq` guard | the entry's marker |
| Evidence object | `strict_spec` | the entry's object name |
| Bundle derivation | `. + { strict_spec_checks: $checks }` | the entry's checklist key, plus the entry's extra keys |
| Everything else | — | unchanged |

**#1650's behaviour must be identical after the refactor**, and that is asserted
rather than asserted-to-be-obvious: its whole suite runs unchanged, and scenario
18 re-runs it as the acceptance condition for step 1. A registry that quietly
alters when the spec checks dispatch would be this item breaking the item it
depends on, and #1650's own scenarios are the only thing that would catch it.

---

## Testing Strategy

**Test types**: Unit (shell harness), plus the smoke test runbook.

**Key scenarios to test**:

1. One case per row of the spec's **ten**-row matrix: `applied` at the plan
   stage with a plan document changed, a readable checklist and a pass that
   completes; `not_applicable` at other stages and on a plan-stage pull request
   with no plan document; `unavailable` when the stage cannot be resolved, the
   checklist cannot be read, or the pass does not complete.
1a. The **five** reasons are distinguishable and each appears in its own row:
   `stage_unresolved`, `stage_not_plan`, `no_plan_document_changed`,
   `checklist_unreadable`, `strict_pass_failed`. `STRICT_PLAN_REASON` is
   **not** emitted in the `applied` rows. Asserted as five different values,
   since the state alone cannot tell a defect in the pull request's shape from
   one in the repository's contents from one in the reviewer command.
2. `STRICT_PLAN_COUNT`, `STRICT_PLAN_CHECKS` and `STRICT_PLAN_APPLIED` are
   **not emitted** outside `applied`, and are present within it — including
   count `0` and an empty `CHECKS` list when the applied checks found nothing.
   `STRICT_PLAN_APPLIED` is never empty in `applied`. Asserted on key presence,
   not on values.
3. A round recorded as `unavailable` or `not_applicable` is distinguishable from
   one recorded as `applied` with count `0`, by reading the ledger entry alone.
4. A strict-pass finding carrying a **known** `check` is counted, appears in
   `STRICT_<n>_*`, does **not** appear in `BLOCKING_<n>_*`, and does not change
   `RESULT`.
5. A review at a non-plan stage produces **byte-identical** `key=value` output
   to the same review before this change, excluding the one key this item always
   adds, `STRICT_PLAN_STATE`, and its reason. No plan pass is dispatched.
5a. A **plan-stage** review whose strict pass returns no findings produces the
   same ordinary output as the same review whose strict pass produced **no
   result** — verdict, blocking block, order and numbering identical. The second
   review is reached by removing the checklist, which is the `unavailable` row;
   AC-26 forbids a setting that disables the checks, so there is no
   checks-disabled review to compare against and AC-3 is worded against this
   comparison instead.
6. An **unknown** `check` identifier is reported with `STRICT_<n>_CHECK=unknown`,
   excluded from `STRICT_PLAN_COUNT` and `STRICT_PLAN_CHECKS`, counted in
   `STRICT_PLAN_UNKNOWN_COUNT`, and does not become blocking. Asserted in both
   directions.
6a. An identifier that is in the checklist but **not in the applied set** — a
   source-dependent check firing on a round where no source was supplied — is
   treated as unknown and counted there, not silently admitted. This is
   AC-19a's subset requirement enforced at the parser rather than trusted from
   the prompt: a reviewer that answers a question it was not asked must not
   raise that check's incidence.
7. `STRICT_PLAN_APPLIED` is **all seven** when a source document was supplied
   and exactly `source_declaration,phase_ordering,dependency_state,reversal_risk`
   when none was. Asserted as sets, from a plan directory with a sibling
   `1_*_specs.md` and one without.
8. **The documents are supplied at the reviewed head, not from the working
   tree.** The fixture commits a plan document, then rewrites the working-tree
   copy with different text. The supplied `text` must match the committed
   revision. Without this the whole feature reviews the wrong bytes on any run
   without `--repo-root`, and every other scenario passes.
9. **An amendment pull request supplies the whole document.** A diff touching
   three lines of a long plan yields a `text` whose length equals the file's,
   not the diff's. AC-12.
10. **Two changed plan documents** are both supplied, each with its own source
   when one exists, and findings carry their own document's path. AC-13.
11. A `git show` failure for a listed path yields `unavailable` with reason
   `strict_pass_failed`, and the invocation count is **1** — the pass is never
   dispatched, because the failure is known before the call. AC-12b.
12. A plan document that is **empty at the reviewed head** yields `applied`, not
   `unavailable`, and its findings are whatever the pass returns. AC-12a. The
   pair with scenario 11 is the point: retrieved-and-empty and not-retrieved are
   four bytes apart in the fixture and are the two sides of silence versus zero.
13. A **plan-stage pull request changing only a smoke-test runbook** yields
   `not_applicable` with reason `no_plan_document_changed`, and the invocation
   count is **1**. AC-15.
14. The checklist's `Source:` lines are read from the document: flipping one
   section from `not required` to `required` moves that identifier out of the
   no-source applied set, with no change to the script or the tests.
14a. The three inherited refusals plus the new fourth: a level-3 heading the
   identifier pattern does not match; a repeated identifier; no headings at all
   and an empty file; and **a section with a missing or invalid `Source:`
   line**. All four are `unavailable` with `checklist_unreadable`, and in none
   of them is `STRICT_PLAN_COUNT` emitted.
14b. The seven shipped identifiers are extracted from the shipped checklist and
   compared to the spec's list as a set, and their `Source:` values are compared
   to the spec's four/three split — by extraction, not by reading.
15. **Both entries report on every review, and never both `applied`.** On a
   spec-stage pull request: `STRICT_SPEC_STATE=applied` and
   `STRICT_PLAN_STATE=not_applicable` with `stage_not_plan`. On a plan-stage
   one: the reverse. Across every row of both matrices, no round emits two
   `applied` states. AC-24 and AC-25.
16. The `strict_plan` object is present on **every** round that ran the local
   reviewer, at any stage, mirrors the output field for field, and is **absent**
   when no local reviewer ran. Asserted with `has()` on both surfaces — the
   reviewer's output and the ledger entry — since the two are written by
   different scripts.
17. The round is bounded by `--timeout` **in total**, not by twice it, on a
   plan-stage review that dispatches a pass. And no second timeout name exists,
   asserted by grep over the implementation and the `--help` block. AC-16b and
   AC-16c.
18. **#1650's suite passes unchanged.** Every scenario in #1650's plan is
   re-run after the registry refactor, with no edit to its assertions. This is
   step 1's acceptance condition and the only thing that would catch the
   registry altering when the spec checks dispatch.
19. **The readiness gate is unchanged by the predicate extraction.**
   `check-documentation-stage-alignment.sh` classifies its existing fixtures
   identically before and after. Asserted over the fixtures already in its
   suite, not over new ones.
20. **The checks fire on planted violations.** Eleven fixture plan documents:
   seven positives, one per check, each carrying exactly one planted instance of
   that check's shape; and four negative controls — a step declared as an
   addition with its reason (AC-5a), an irreversible step declared irreversible
   (AC-10a), a plan whose every criterion has a falsifying test, and a Refactor
   plan correctly declaring its tracker brief, which must produce **no**
   `source_declaration` finding.
21. The same eleven fixtures with the checklist **absent**: the state is
   `unavailable` and no strict finding is produced. This is what separates *the
   reviewer found it because the checklist told it to look* from *the reviewer
   would have found it anyway*.

**Files**:

- `scripts/development-workflow/tests/test-local-ai-reviewer.sh` — scenarios 1
  through 17, and 16's reviewer-output half. Parser scenarios run the real `jq`
  programs with crafted output; dispatch scenarios use a recording stub for
  `LOCAL_AI_REVIEWER_COMMAND` so invocation counts can be asserted; scenarios 8,
  9 and 11 build a real temporary git repository, since `git show` against a
  committed revision is the thing under test.
- `scripts/development-workflow/tests/test-pr-review-loop.sh` — scenario 16's
  ledger half, beside #1650's `strict_spec` cases.
- `scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh`
  — scenario 19, over its existing fixtures.
- The **smoke runbook** — scenarios 20 and 21, which need a real model.

**Scenarios 20 and 21 are demonstrated in the pull request rather than asserted
in CI**, for #1650's reason: whether a model notices a planted defect is not
deterministic, and a suite that fails the build on a missed detection is red for
reasons no implementer can fix, after which the pressure is to delete the
assertion. What is deterministic — dispatch, supply, coverage, counts, the two
passes never merging — is scenarios 1 through 19, and those are automated.

**A check that cannot demonstrate its pair does not ship.** The repair is to
sharpen its question in the checklist until it detects its own planted
violation, at step 5a and before merge. A check that detects nothing produces a
permanent zero in #1657's data, and a zero reads as *this does not happen*
rather than *this check does not work*.

**Smoke test runbook**:
`docs/testing/workflow/1655-strict-plan-review-mode.smoke-test.md`

**Regression suite**: the three harnesses named above.

---

## Seed Data

| Fixture | Contents | Location |
| --- | --- | --- |
| Fixture plan documents | **Eleven**: seven positives, one per check with a single planted instance of its shape; four negatives — a declared addition (AC-5a), a step declared irreversible (AC-10a), a plan whose criteria all have falsifying tests, and a Refactor plan correctly declaring its tracker brief. Ten sit under `with-source/`; the Refactor negative sits under `no-source/` | `scripts/development-workflow/tests/fixtures/strict-plan-plans/` |
| Fixture source specs | **One** committed `1_*_specs.md`, a sibling of the positives, so the source-dependent checks have something to compare against. The no-source case is a **second fixture directory** containing a plan and no sibling spec — an absence is a directory without a file, not a file | `.../strict-plan-plans/with-source/` and `.../strict-plan-plans/no-source/` |
| Git fixtures | A temporary repository with a plan committed at one revision and rewritten in the working tree, for scenario 8; a path removed from the index, for scenario 11 | built inline in `test-local-ai-reviewer.sh` |
| Reviewer outputs | **Ordinary pass**: clean; two blocking findings. **Strict pass**: no findings; findings from two applied checks; an unknown identifier; an identifier that is in the checklist but not in the applied set; and the failure shapes #1650 enumerates | inline in the same suite |
| Checklist fixtures | A well-formed seven-section checklist with `Source:` lines; one with an eighth section; one with a section missing its `Source:` line; one with an invalid `Source:` value; and #1650's three malformed shapes | `scripts/development-workflow/tests/fixtures/strict-plan-checks/` |

---

## Documentation Updates

- `docs/workflow/development-workflow/strict-plan-checks.md` — the checklist.
- The integration document and Protocol 93 — the keys, states, reasons,
  applied-set semantics and the registry.
- The `--help` block of `local-ai-reviewer.sh`.
- `.github/workflows/markdown-lint.yml` — `docs/workflow/**` in `paths`.
- `changelog.d/1655.added.strict-plan-review-mode.md` — `added`: a class of
  finding that did not exist, and nothing changes for a repository whose
  reviewer emits none.

---

## Cross-Cutting Checklist Classification

**Classification**: `Not applicable`. Protocol 02's three signals are adding or
renaming a checklist category in `REVIEW.md` or a planning document; imposing an
acceptance criterion on every plan; and adding a conditional guidance block to a
planning or implementation protocol.

This item adds a **new document read by one script** and changes no `REVIEW.md`
section — the Plan Review Checklist is untouched, deliberately, and the spec
says why. It requires nothing of any future plan: a plan that produces seven
strict findings is as mergeable as one that produces none.

The contrast with #1653 is the useful one: that item added a section to
`REVIEW.md`, which is the first signal exactly.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The plan is read from the working tree instead of the reviewed head | **High** — reading the file is the obvious implementation and the script already `cd`s into a checkout | **High** — confident findings about text the pull request does not contain, with nothing in the output to show it, on every run without `--repo-root` | `git show "$HEAD_SHA:<path>"`, never a file read. Scenario 8; proof **P1** |
| An amendment pull request is checked against its diff | **High** — the bundle already carries diffs and nothing else | **High** — `spec_traceability` and `ac_test_coverage` report absences that are artifacts of where the diff ends, which is the most common plan pull request in this epic | The whole document is supplied. Scenario 9; proof **P2** |
| The registry refactor changes when the spec checks dispatch | Med | **High** — this item breaks the item it depends on, and only #1650's own scenarios would notice | #1650's suite runs unchanged as step 1's acceptance condition. Scenario 18 |
| The applied set is not reported and a count has no denominator | Med — the count is the obvious thing to emit and coverage reads as redundant | **High** — #1657 computes a rate over a denominator that varies invisibly, and Refactor plans drag three checks' incidence toward zero | `STRICT_PLAN_APPLIED` emitted whenever the state is `applied`. Scenarios 2 and 7; proof **P3** |
| A source-dependent check's finding is counted on a round where it was not applied | Med — the reviewer answers what it was not asked | Med — a check's incidence rises on rounds it never ran, in the flattering direction for whichever check is noisiest | The parser admits only identifiers in the applied set; the rest are `unknown`. Scenario 6a; proof **P4** |
| The script parses the plan's `**Spec**:` header to classify the source | Med — the spec names three source cases and two look like a shell test | Med — a checklist question answered in shell, wrong on the first plan that words the line differently, and a coverage decision made on a regex | The script computes only the applied set, from whether a source was retrieved. Which case obtains is check 1's finding. Scenario 7 asserts the set and not the classification |
| The path predicate drifts between the gate and the reviewer | Med — two copies of one regex | Med — a path the readiness gate allows and the reviewer does not recognise is a plan document nobody checks | One definition in `workflow-lib.sh`, both callers. Scenarios 19 and 13 |
| Supplying whole documents exceeds the reviewer command's limits | **Med to High** on long plans — this epic's own plans run past a thousand lines, and a pull request can change two | Med — the checks routinely produce no result on exactly the plans most worth checking | No truncation and no size setting: a truncated plan produces traceability findings that are wrong rather than absent, which is worse than no result. A pass that cannot complete is `strict_pass_failed`, the same cause and the same owner as any other failed attempt, and #1657 sees it as a rate rather than as silence. **Residual and declared**: this may be the plan checks' most common failure, and the data will say so |
| `not_applicable` is reported without its reason | Med — #1650's does not carry one, so the registry default is to omit it | Med — a runbook-only plan pull request is indistinguishable in the record from a spec pull request, and #1657's denominator quietly includes rounds nothing was asked of | The entry declares that it reports a reason in `not_applicable`. Scenario 1a; proof **P5** |
| A third checklist reuses the shared `STRICT_<n>_*` block | Low today | **High** later — two sets of findings in one numbered block with nothing saying which is which | AC-25 is what makes the shared block safe, and the registry records the dependency in the table above rather than leaving it implicit |
| `0` is written where the checks did not run | **High** — an empty numeric field invites a default | **High** — unexamined rounds enter #1657's denominator and the rate is wrong in the flattering direction | Count, checks and applied set are unemitted outside `applied`. Scenarios 2 and 3; proof **P6** |

---

## Code Samples

The applied-set computation and the parser guard that depends on it. Everything
else is #1650's, read from the registry entry.

```text
# $sections comes from the checklist: one object per level-3 section, carrying
# the identifier and its Source: line, already normalised to `required` or
# `not_required` by the extraction below. The closed set and the split have one
# definition, and it is the document.
#
#   [ { "id": "source_declaration", "source": "not_required" }, ... ]

# Applied set: all seven when a source was supplied, the source-independent
# four when none was.
applied="$(printf '%s' "$sections" | jq -r --argjson have_source "$have_source" '
  map(select($have_source or .source == "not_required") | .id) | join(",")
')"
```

And the parser's admission test, which is the one line that differs from
#1650's:

```text
def known($c): $c != null and ($applied_checks | index($c) != null);
```

**`$applied_checks`, not `$known_checks`.** #1650 admits any identifier the
checklist defines, because every check it defines was applied. Here the two sets
differ on the rounds that matter, and admitting a checklist identifier that was
not applied would let a reviewer raise a check's incidence on a round where the
check never ran — inflating exactly the number #1657 exists to read, and doing
it for whichever check the model is most inclined to volunteer. A finding
carrying an unapplied identifier is `unknown`: visible in
`STRICT_PLAN_UNKNOWN_COUNT`, attributed to no check, and inert. Scenario 6a.

The `Source:` extraction, with the fourth refusal:

```text
# The document's two spellings map to the two internal tokens here and nowhere
# else: `not required` is what a reader writes, `not_required` is what jq
# compares. Two -e expressions rather than one alternation, so the mapping is
# explicit rather than a substitution that happens to preserve the text.
status=0
sources="$(sed -n \
  -e 's/^Source:[[:space:]]*required[[:space:]]*$/required/p' \
  -e 's/^Source:[[:space:]]*not required[[:space:]]*$/not_required/p' \
  "$checklist")" || status=$?
if [ "$status" -ne 0 ]; then
  strict_unreadable; return 0
fi
# One Source: line per section, or the document is refused.
[ "$(printf '%s\n' "$sources" | grep -c .)" -eq "$declared" ] || {
  strict_unreadable; return 0
}
```

The count comparison is the refusal that matters, and it is #1650's heading
comparison applied to a second property. A section whose `Source:` line is
missing or misspelled would otherwise be placed in one group by default, and the
applied set would claim coverage the pass did not have — a number that is wrong
rather than absent, which is the error this whole feature exists to avoid
producing.

`grep -c` is read for its count and not its status here because the surrounding
`|| status=$?` on the `sed` already covers the failure path; the count itself is
compared, and a zero count fails the comparison rather than the script. Under
`set -euo pipefail` this matters: #1650 records the same trap on `grep -c` and
resolves it by reading the status explicitly, which is the pattern the shipped
extraction follows.

---

## Planted-Violation Proofs

`REVIEW.md` → Core Rules → Verification Discipline requires two demonstrated
runs per proof, each citing a concrete file and line. **Thirteen** proofs in two
groups:

| Group | Count | Proofs | What the plant reproduces |
| --- | --- | --- | --- |
| Machinery | **6** | P1-P6 | a supply, a coverage or a count that reports what it did not check |
| Detection | **7** | P7-P13 | a check that does not find the violation it exists to find |

| # | Violation to plant | Where | Check that must fail, then pass |
| --- | --- | --- | --- |
| P1 | Read the plan document with `cat "$path"` instead of `git show "$HEAD_SHA:$path"` | a scratch copy of the supply step | scenario 8 fails: the supplied text is the working tree's, so on any run without `--repo-root` the checks review bytes the pull request does not contain and report findings against them; restoring `git show` passes |
| P2 | Supply the plan's diff hunks instead of its full text | same scratch copy | scenario 9 fails: an amendment pull request supplies three lines, and `spec_traceability` reports every criterion as unaddressed because no step is in scope; restoring the full text passes |
| P3 | Omit `STRICT_PLAN_APPLIED` and emit the count alone | a scratch copy of the print block | scenarios 2 and 7 fail: a count of one on a Refactor plan is indistinguishable from a count of one on a Feature plan, so #1657's rate divides by a denominator that varies invisibly; restoring the key passes |
| P4 | Admit any checklist identifier, not only applied ones — `$known_checks` in place of `$applied_checks` | a scratch copy of the strict `jq` program | scenario 6a fails: a `spec_traceability` finding on a round with no source is counted, raising that check's incidence on rounds it never ran; restoring `$applied_checks` passes |
| P5 | Omit the reason in `not_applicable`, keeping it in `unavailable` as #1650 does | a scratch copy of the print block | scenario 1a fails: `stage_not_plan` and `no_plan_document_changed` collapse, so a runbook-only plan pull request enters #1657's records as a spec pull request; restoring the reason passes |
| P6 | Emit `STRICT_PLAN_COUNT=0` and an empty applied set for `unavailable` and `not_applicable` | same scratch copy | scenarios 2 and 3 fail: a round the checks never examined is indistinguishable from one where they ran and found nothing, so unexamined plans enter the denominator as clean — an error in the flattering direction, which is the one nobody questions; scenario 16 fails with it, since the object mirrors the output; restoring the unemitted keys passes |
| P7-P13 | For each check in turn, remove its planted violation from that check's positive fixture — in the spec's order: `source_declaration`, `unspecified_step`, `spec_traceability`, `ac_test_coverage`, `phase_ordering`, `dependency_state`, `reversal_risk` | the seven positive fixture plans | the check fires on the fixture carrying its violation and does **not** fire on the same fixture with that one violation removed. Both runs recorded with the fixture path, the planted line and the identifier set the round reported. Without the second run a check that fires on everything looks identical to one that works |

P1 is the proof to read first. Every other machinery proof plants a defect that
makes a number wrong; P1's plants a defect that makes the *findings* wrong,
while every count remains internally consistent and every other scenario passes.

---

## Implementation Order

0. **Hard stop**: confirm #1650's **implementation** is merged and that its
   strict pass has the shape the registry table above assumes — the stage test,
   the derived bundle, `LOCAL_AI_REVIEWER_MODE`, the strict parser with its mode
   guard, and the identifier extraction with its three refusals. Confirm #1653
   is merged and `review_stage` carries `plan`. Re-read the merged `print_kv`
   block and the merged `jq -n` bundle site, which #1650 and #1654 both touch.

   If #1650 shipped a different shape, this plan is revised rather than adapted.

1. Extract `workflow_is_plan_document_path` into `workflow-lib.sh` and point
   both callers at it. **Verify**: scenario 19 — the readiness gate classifies
   its existing fixtures identically.
2. Turn the strict pass into a registry with the spec entry alone, changing no
   behaviour. **Verify**: scenario 18 — #1650's suite passes unchanged, with no
   edit to its assertions. This step ships nothing new and is the only step
   whose failure means the refactor was wrong rather than incomplete.
3. Add the plan checklist with its seven sections, identifiers and `Source:`
   lines, and the fourth extraction refusal. **Verify**: scenarios 14b and 14a.
4. Add the plan entry: its stage, checklist, prefix and marker, the document
   supply by `git show`, the source resolution by path convention, and the
   applied-set computation. **Verify**: scenarios 7, 8, 9, 10, 11, 12 and 13.
5. Add the six `print_kv` keys, the evidence object and the `strict_plan` entry
   in `reviewer_loop_history_build_entry`. **Verify**: scenarios 1, 1a, 2, 3, 4,
   5, 5a, 6, 6a, 14, 15, 16 and 17.
5a. Write the eleven fixture plans and run the reviewer against each with the
   checklist supplied and again without it. **Verify**: scenarios 20 and 21 —
   record which checks fired in each run, in the pull request.

   **Not a CI gate, and a readiness gate.** No build goes red when a model
   misses a fixture; but a check that cannot demonstrate its pair does not ship,
   and the repair is to sharpen its question until it does.
6. Update the `--help` block, the integration document, Protocol 93, the `paths`
   filter, and add the changelog fragment. **Verify**: runbook Step 9.
7. Produce the **thirteen** planted-violation proofs and record them in the pull
   request with the command, file, line and both outcomes for each.

---

## Rollback

Revert the implementation pull request. It removes the plan checklist, the plan
registry entry, the document supply, the applied-set computation, six
`key=value` keys, the evidence and ledger objects, the summary addition, the
`paths` entry and the documentation updates.

**Two parts of the revert are not the plan entry**, and both are safe to keep or
to drop:

- The **registry** reverts to #1650's literals. Nothing depends on it but the
  plan entry, and step 2 asserts that the refactor changed no behaviour, so
  reverting it cannot regress the spec checks either.
- `workflow_is_plan_document_path` can stay: the readiness gate calls it and
  behaves identically either way. Reverting it is a second, independent change,
  and mixing the two into one revert is the only way this rollback could touch a
  gate this item never meant to alter.

Plan-stage reviews return to one invocation.

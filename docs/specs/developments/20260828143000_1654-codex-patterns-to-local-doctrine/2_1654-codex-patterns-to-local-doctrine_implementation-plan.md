# Review Doctrine from External Findings — Implementation Plan

**Spec**:
[1_1654-codex-patterns-to-local-doctrine_specs.md](./1_1654-codex-patterns-to-local-doctrine_specs.md)
**Smoke test runbook**:
[1654-codex-patterns-to-local-doctrine.smoke-test.md](../../../testing/workflow/1654-codex-patterns-to-local-doctrine.smoke-test.md)

---

## Summary

**Approach**: `local-ai-reviewer.sh` builds a JSON context bundle and hands it to
`LOCAL_AI_REVIEWER_COMMAND`. The spec asks for one more thing in that bundle —
a catalogue of recurring finding shapes — plus three values reporting whether it
got there, and two repository checks keeping the catalogue well-formed, generic
and within its size bound.

Four pieces: a new document, `docs/workflow/development-workflow/review-doctrine.md`;
a shell lint that parses it; a reader in the reviewer that produces the supply
state; and the bundle, evidence and `key=value` fields that carry the result.

**The design question is not how to read a file — it is where the size bound
lives.** AC-12 requires one source of truth for it, read by both the checker and
the reviewer, and the two are different programs. That is why the lint is a
shell script rather than a Python one like its neighbours: both it and the
reviewer already source `workflow-lib.sh`, so a constant declared there is
literally the same value in both, not two copies that agree today.

**Estimated complexity**: M

**Rationale**: Every individual piece is small. What makes it more than small is
that the feature's failure mode is silence — a review that ran without the
doctrine and said nothing about it looks exactly like one that used it — so the
supply state has to be correct on four paths, three of which are error paths,
and the "never truncated" rule has to hold in the one place where truncating
would be the obvious thing to do.

**Dependencies**: **#1653 must be merged to
`develop-internal-reviewer-effectiveness` before this item's implementation PR
opens.** Both items add fields to the same `jq -n` context-bundle object in
`local-ai-reviewer.sh` and both add `print_kv` lines to the same block; merging
in either order is fine, but implementing in parallel would conflict in two
places. #1653's plan is merged and its implementation is not, so this is a
sequencing constraint on implementation only.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short origin/develop-internal-reviewer-effectiveness` | `92247597` |
| The bundle is built in one `jq -n` call | `sed -n '339,366p' scripts/development-workflow/local-ai-reviewer.sh` | Thirteen fields, one `jq -n` invocation, written to `$context_file`. The doctrine's four fields are added there; nothing new reads or writes the file |
| The command receives the bundle by path | `sed -n '372,384p' scripts/development-workflow/local-ai-reviewer.sh` | `CONTEXT_BUNDLE_PATH` is exported alongside six other variables. A command that reads the bundle gets the doctrine with no change to its own contract |
| `workflow-lib.sh` is sourced by the reviewer | `sed -n '9,11p' scripts/development-workflow/local-ai-reviewer.sh` | `source "$SCRIPT_DIR/workflow-lib.sh"` — the shared library is already in scope, so a constant declared there needs no new plumbing |
| A shell lint has precedent | `sed -n '1,30p' scripts/lint/check-changelog-duplicate-headers.sh` | `scripts/lint/` already contains one Bash linter with a documented usage block and 0/1 exit contract; the two Python linters are not the only convention |
| Lints are wired into CI as explicit steps | `sed -n '80,87p' .github/workflows/markdown-lint.yml` | Each linter is its own `run:` step — `python3 scripts/lint/markdown-heuristic-lint.py …`, `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`. Adding a step is the whole CI change |
| Evidence keys reach the loop summary unchanged | `sed -n '754,772p' scripts/development-workflow/pr-review-loop.sh` | `emit_prefixed_platform_output` re-emits every key except five, so `REVIEW_DOCTRINE_*` appears as `PLATFORM_<n>_REVIEW_DOCTRINE_*` with no loop change |
| The five seed patterns are the brief's | issue #1654, Scope bullet 1 | criteria/matrix mismatch, opt-out ambiguity, parser-surface conflict, trigger ambiguity, examples contradicting rules — five, matching the spec's Statuses table |

**What this log does not establish.** It does not show that supplying the
doctrine changes what a reviewer finds. That is #1657's measurement, and this
item deliberately records the catalogue version with every review so the
comparison is possible later.

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch for this item | `develop-internal-reviewer-effectiveness` | `integration-branch:internal-reviewer-effectiveness` label on #1654 | 2026-08-28, repo SHA `92247597` | Epic #1647 items | `Verified` |
| The context bundle's shape and its single build site | Thirteen fields today, **sixteen** after #1653 merges | `local-ai-reviewer.sh:339-366`; #1653's merged plan for the three it adds | 2026-08-28, repo SHA `92247597` | `local-ai-reviewer.sh` and its two test suites | `Conflict` — see below |
| `workflow-lib.sh` is in scope for both the reviewer and a shell lint | Sourced at `local-ai-reviewer.sh:11` | The file itself | 2026-08-28, repo SHA `92247597` | `scripts/development-workflow/`, `scripts/lint/` | `Verified` |

**Conflict record.** #1653 adds three fields to the same `jq -n` object and
three `print_kv` calls to the same block. Affected plan statements: the bundle
change and the evidence change.

**Resolution status**: `Resolved` by sequencing. Recorded in **Dependencies**
and enforced by **Implementation Order step 0**. Decision owner: LH — if #1653
is implemented differently from its plan, the field list here must be re-read
against the merged code rather than against this plan.

**The unchanged-fields assertion inherits that ordering.** Scenario 7 asserts
every field present *before this change*, which after step 0 is sixteen and not
thirteen. Freezing it at thirteen would let an implementation satisfy the test
while dropping #1653's three fields — the precise shape of AC-14's failure, and
invisible because the number would still look right.

### Not applicable

**Overall result for this check**: `Applicable` — the three rows above are the
assumption surfaces and must be re-verified at implementation start. This
subsection scopes only surfaces carrying no assumption.

**Surfaces with no assumption**: no database, no runtime service, no
user-facing surface, no scheduled job, no external API, no deployment target.

---

## Layer-by-Layer Changes

### Database / Data Layer

Not applicable.

### Backend / API

Not applicable — this repository ships workflow tooling, not a service.

### Shared Packages / Libraries

- [ ] **Declare the size bound once, in `workflow-lib.sh`.**

      ```bash
      # The review doctrine's maximum size, in bytes as `wc -c` measures them.
      # AC-12: one source of truth, read by both the linter and the reviewer.
      readonly REVIEW_DOCTRINE_MAX_BYTES=12000
      ```

      **Fixed, and deliberately not overridable.** An earlier revision of this
      plan wrote `"${REVIEW_DOCTRINE_MAX_BYTES:-12000}"` so a test could move
      the bound. That is withdrawn: the spec fixes 12,000 as the contract, and
      an environment value above it would make **both** CI and the reviewer
      accept an oversized catalogue — defeating AC-11 and the rule the bound
      exists for, that a catalogue which no longer fits is edited rather than
      excused. `readonly` states the intent and makes an accidental
      reassignment fail loudly.

      Proving the two consumers share it therefore cannot work by moving it.
      Scenario 15 proves it structurally instead — neither consumer contains a
      literal bound of its own — and scenario 15b proves it behaviourally, at
      the boundary, with one fixture and both consumers.

      **This is why the linter is a shell script.** AC-12 asks for one value the
      checker and the reviewer both read. Its neighbours in `scripts/lint/` are
      Python, and a Python linter cannot source a Bash constant — it would need
      its own copy, or a third file to hold the number, or a parser for a
      variable assignment. `check-changelog-duplicate-headers.sh` establishes
      that a Bash linter is an accepted shape here, and both consumers already
      source `workflow-lib.sh`, so the constant is literally the same value in
      both rather than two that agree today.

- [ ] **Add the catalogue**, `docs/workflow/development-workflow/review-doctrine.md`,
      in the structure the spec's Business Rules define: a preamble, then one
      level-3 heading per pattern, each followed by exactly one `**Shape**:`,
      one `**Example**:` and one `**Detect**:` paragraph.

      The preamble carries two statements the spec makes acceptance criteria of
      — AC-3, that the catalogue lists shapes worth looking for and is not the
      set of things worth reporting; and AC-3a, the request that a reviewer name
      the pattern it matched — plus the contribution guidance AC-16 requires,
      including what to do when the bound is reached: **merge or remove a
      pattern, never raise the bound in the same change that breaches it.**

      Five seeded patterns, from the brief: criteria/matrix mismatch, opt-out
      ambiguity, parser-surface conflict, trigger ambiguity, and example
      contradicting rule. Each written as a general shape — no pull request
      number, no issue number, no path from the incident.

- [ ] **Add `scripts/lint/review-doctrine-lint.sh`**, three checks and a 0/1
      exit contract, following the usage-block convention of its Bash
      neighbour:

      | Check | Rule | Criterion |
      | --- | --- | --- |
      | Well-formedness | every level-3 heading is followed by exactly one `**Shape**:`, one `**Example**:` and one `**Detect**:` paragraph | AC-2a |
      | Incident references | no **entry** contains any of AC-4's four exact patterns | AC-5 |
      | Size | `wc -c` of the file is at most `REVIEW_DOCTRINE_MAX_BYTES` | AC-11 |

      The incident-reference check runs on **entries only**. The preamble cites
      repository documents by path — that is what contribution guidance is — and
      a check that could not tell the two apart would either reject valid
      guidance or be switched off. The entry boundary is the level-3 heading, so
      one parse serves the well-formedness check, the incident-reference check
      and the pattern count alike.

- [ ] **Read the catalogue in `local-ai-reviewer.sh`.** Add
      `reviewer_doctrine_supply`, returning one compact JSON object:

      ```text
      {"state": "...", "text": "...", "pattern_count": N, "version": "..."}
      ```

      **All four values come from one snapshot.** The function copies the
      catalogue once and derives the size, the hash, the pattern count and the
      supplied text from that copy. Reading the live file four times would let
      an edit land between the hash and the text, producing a `supplied` bundle
      whose `version` identifies different bytes than its `review_doctrine` — a
      record that is internally false and looks entirely normal. The window is
      small and the consequence is permanent: every later report grouping
      reviews by version would group that one wrongly.

      **Every read is attempted, and every read's failure is `unreadable`.** A
      permission-bit test is not a read: an ACL, an I/O error, or a file removed
      between the test and the use all pass `[ -r … ]`, and under `set -euo
      pipefail` the failure that follows would terminate the reviewer rather
      than report a state — which AC-8 forbids, because the review must still
      run. So `wc -c` doubles as the open probe, and the digest, the count and
      `jq --rawfile` each carry their own handler. There is no window in which a
      check has succeeded and the operation it authorised has not been tried.

      Its four states are the spec's, decided by three ordered inputs:

      | # | Present | Readable | Within bound | State | `text` | `pattern_count` | `version` |
      | --- | --- | --- | --- | --- | --- | --- | --- |
      | 1 | no | — | — | `absent` | `""` | 0 | `""` |
      | 2 | yes | no | — | `unreadable` | `""` | 0 | `""` |
      | 3 | yes | yes | no | `oversized` | `""` | 0 | the hash |
      | 4 | yes | yes | yes | `supplied` | the full text | count of level-3 headings | the hash |

      Row 3's two columns are the ones to get right. `text` is **empty** — AC-9
      forbids supplying a truncated doctrine, and "some of it" is the failure
      mode partial doctrine has: it looks complete to the reviewer, and the
      patterns it drops are the most recently added, which are the ones nobody
      has internalised. `version` is **present**, because the file was read and
      *which* version is over the bound is the first thing a maintainer needs.

      `pattern_count` is `0` in every non-`supplied` row — it counts patterns
      **supplied**, not patterns present. An `oversized` catalogue with nine
      entries reports `0`, because zero reached the review.

      **The version is the first twelve hexadecimal characters of the SHA-256 of
      the stored bytes**, and the digest command is resolved once at startup:
      `sha256sum` where it exists, `shasum -a 256` otherwise, and if neither
      does, the state is **`unreadable`** rather than `supplied` with an empty
      version. A supplied doctrine with no version would break the one question
      the version answers — *did this review see the same catalogue as that
      one* — silently, on a machine nobody suspected.

- [ ] **Carry it in the bundle and the evidence.** Four fields added to the
      `jq -n` object, `schema_version` unchanged at
      `local_ai_reviewer_context.v1`:

      ```text
      review_doctrine:               "<the catalogue's stored bytes, or empty>"
      review_doctrine_state:         "supplied" | "absent" | "unreadable" | "oversized"
      review_doctrine_pattern_count: <integer>
      review_doctrine_version:       "<12 hex, or empty>"
      ```

      **The text is the file's bytes, unmodified.** It is read with
      `jq --rawfile`, never through a command substitution: `$(cat …)` strips
      every trailing newline, so the bundle would carry a catalogue that differs
      from the stored one — and the difference is invisible to any test that
      matches an interior sentence. AC-6 asks for the full text; scenario 7a
      asserts byte equality against the file.

      The text is carried **in** the bundle rather than as a path for the
      command to read. The bundle is the command's contract, a command may run
      where the repository is not checked out, and a path would make "supplied"
      mean *the reviewer could have read it* rather than *the reviewer was given
      it* — which is the difference the supply state exists to record.

      Three `print_kv` lines beside the existing `BASE_BRANCH` /
      `REVIEWED_HEAD` / `GRAPH_CONTEXT` block: `REVIEW_DOCTRINE_STATE`,
      `REVIEW_DOCTRINE_PATTERN_COUNT`, `REVIEW_DOCTRINE_VERSION`. **The text is
      not among them** — it is thousands of bytes and the `key=value` contract
      is line-oriented, so a multi-line value would be re-emitted as fabricated
      keys by `emit_prefixed_platform_output`. The same three values go into the
      evidence JSON under a `review_doctrine` object.

### Frontend / UI

Not applicable — no user interface. The reader-facing surfaces are the
catalogue and the reviewer's recorded output.

### Infrastructure / Configuration

- [ ] Add the linter as its own CI step in `.github/workflows/markdown-lint.yml`,
      beside the existing `check-changelog-duplicate-headers.sh` step:
      `bash scripts/lint/review-doctrine-lint.sh`.
- [ ] Document the four fields, the three evidence keys and the four states in
      the `--help` block and in
      `docs/workflow/development-workflow/integrations/local-ai-reviewer.md`.

---

## Testing Strategy

**Test types**: Unit (shell harness), plus the smoke test runbook.

**Key scenarios to test**:

1. `reviewer_doctrine_supply` returns each of the four states, one case per row
   of its table, asserting **all four** returned values and not the state
   alone.
1a. Every file operation's failure yields `unreadable` and the reviewer keeps
   running: the snapshot copy, the size probe, the digest, the pattern count and
   the `jq --rawfile` read, each failed in turn while the others succeed. The
   pattern-count case distinguishes **exit 1** — no matches, a real count of
   zero, still `supplied` — from **exit >1**, an error, which is `unreadable`.
   `grep -c … || true` flattens the two and reports `supplied` with a wrong
   count.
1b. The four values describe **the same bytes**: with the catalogue rewritten
   during collection, the returned `version` is the hash of the returned `text`,
   never of a different revision. Exercised by replacing the file immediately
   after the snapshot is taken. Exercised under
   `set -euo pipefail`, which is how the script runs — a handler that is merely
   present but reached after `set -e` has already aborted is not a handler.
2. The `oversized` row returns empty `text` **and** a non-empty `version`. Both
   halves are asserted: a truncated text is AC-9's failure, and a missing
   version is the maintainer's only clue about which catalogue is too big.
3. `pattern_count` is `0` in all three non-`supplied` states, including an
   `oversized` catalogue that contains nine well-formed patterns.
4. An **empty** catalogue — present, readable, within bound, zero patterns — is
   `supplied` with `pattern_count` 0, not a failure state. Adopting the
   doctrine must not be a two-step operation.
5. The version is the first twelve hex characters of the SHA-256 of the file's
   bytes, asserted against a digest computed independently in the test rather
   than against the function's own output.
6. With **neither** `sha256sum` nor `shasum` on `PATH`, the state is
   `unreadable`, not `supplied` with an empty version. Exercised with a `PATH`
   containing neither.
7a. `review_doctrine` is **byte-identical** to the catalogue on disk, compared
   with `cmp` against the file rather than by matching a sentence inside it. A
   command substitution passes an interior-sentence check and fails this one,
   because what it loses is at the end.
7. The bundle carries all four fields, and **every field present before this
   change** is unchanged in name and type — that is **sixteen**, not thirteen:
   the original thirteen plus the three #1653 adds (`review_stage`,
   `review_stage_source`, `review_checklists`), since step 0 requires #1653 to
   be merged first. Asserted against an enumerated list built by reading the
   merged `jq -n` object at implementation time, not against a count and not
   against this plan's copy of it — a list frozen at thirteen is satisfied by an
   implementation that drops #1653's three, which is exactly AC-14's failure.
8. The `key=value` output carries the three scalar keys and **not** the text,
   and passing that output through the loop's real
   `emit_prefixed_platform_output` yields three `PLATFORM_1_REVIEW_DOCTRINE_*`
   keys and no fabricated ones.
8a. With `LOCAL_AI_REVIEWER_EVIDENCE_FILE` set, the evidence JSON carries a
   `review_doctrine` object with all three values — the state as a string, the
   pattern count as a **number**, the version as a string — and remains valid
   `local_ai_reviewer_evidence.v1`. Asserted in a `supplied` run and in an
   `oversized` one, so the evidence's copy of the count is checked where it
   differs from the catalogue's own. This is AC-15, and it is a different
   surface from the `key=value` output: the evidence file is what a later
   report reads, and nothing else in this plan touches it.
9. The doctrine is supplied at **every** stage the reviewer recognises,
   including the default stage — one case per stage, since the natural
   implementation of a stage-aware reviewer is to make things stage-conditional.
10. The review context that exists today is unchanged when the doctrine is
    supplied: same changed files, same diff metadata, same review contract.
11. `review-doctrine-lint.sh` fails on a malformed entry — a heading missing one
    of its three labelled parts, and a heading carrying one twice — and passes
    on a well-formed catalogue.
12. It fails on an entry containing each of AC-4's four forms, one case per
    form, and passes on the four near-miss controls that must **not** match:
    `# Title`, `PR review`, `docs/specs/`, and `example.com/pull/1`.
13. It **passes** when the preamble contains a `docs/specs/developments/` path,
    which contribution guidance legitimately does. Entry-scoped, not
    file-scoped.
14. It fails at 12,001 bytes and passes at 12,000 — the boundary, not a value
    near it.
15. The bound has exactly one definition, checked **structurally**: the literal
    `12000` appears once in `workflow-lib.sh` and **nowhere** in
    `review-doctrine-lint.sh` or `local-ai-reviewer.sh`, and both name
    `REVIEW_DOCTRINE_MAX_BYTES`. This is the assertion the withdrawn
    environment override was reaching for, and it needs no production hook to
    make it.
15b. The two consumers agree **behaviourally at the boundary**, on one fixture:
    a 12,000-byte catalogue passes the linter and is `supplied`; a 12,001-byte
    one fails the linter and is `oversized`. Two copies of the bound that happen
    to agree today pass this and fail scenario 15, which is why both exist. This is AC-12, and it is the scenario that fails if either
    grows its own copy of the number.
16. The catalogue in the repository passes its own linter, contains exactly the
    five seeded patterns, and its preamble contains the AC-3 statement and the
    AC-3a request.
16a. `REVIEW.md`'s Workflow Policy checklist contains the generality question,
    and the catalogue's contribution guidance contains the same obligation.
    AC-5a names **both** places, and asserting only one would leave the other
    to be dropped silently — which is what happened to this requirement in an
    earlier revision of this plan.

**Files**:

- `scripts/development-workflow/tests/test-local-ai-reviewer.sh` — scenarios 1
  through 10, in the existing harness.
- `scripts/development-workflow/tests/test-review-doctrine-lint.sh` — a new
  suite for scenarios 11 through 16, which need catalogue fixtures on disk. It
  must declare:

  ```text
  # covers: scripts/lint/review-doctrine-lint.sh
  # covers: docs/workflow/development-workflow/review-doctrine.md
  ```

**Smoke test runbook**:
`docs/testing/workflow/1654-codex-patterns-to-local-doctrine.smoke-test.md`

**Regression suite**: the two shell harnesses named above.

---

## Seed Data

| Fixture | Contents | Location |
| --- | --- | --- |
| Well-formed catalogue | A preamble and three patterns in the required structure | `scripts/development-workflow/tests/fixtures/review-doctrine/well-formed.md` |
| Malformed catalogues | One missing a `**Detect**:` paragraph; one with two `**Shape**:` paragraphs under a single heading | same directory |
| Incident-reference catalogues | Four, one per AC-4 form, plus one whose **preamble** carries a `docs/specs/developments/` path and whose entries are clean | same directory |
| Boundary catalogues | One of exactly 12,000 bytes and one of 12,001, padded in the `**Example**:` paragraph so both stay well-formed | generated by the suite, asserted with `wc -c` before use |
| Empty catalogue | A preamble and no patterns | same directory |
| Bundle field fixture | The **sixteen** pre-change `local_ai_reviewer_context.v1` field names — the original thirteen plus #1653's `review_stage`, `review_stage_source` and `review_checklists` — enumerated from the merged object rather than copied from this plan | inline in `scripts/development-workflow/tests/test-local-ai-reviewer.sh` |

---

## Documentation Updates

- `docs/workflow/development-workflow/review-doctrine.md` — the catalogue.
- `REVIEW.md` — one question added to the `## Workflow Policy Review Checklist`
  that #1653 introduces, carrying AC-5a's human-review obligation: *does every
  catalogue entry read generally — no person's name, no document title, no
  wording that only makes sense to someone who saw the original incident?* The
  spec places this obligation in two places, the catalogue's contribution
  guidance **and** that checklist, because the guidance is read by whoever adds
  a pattern and the checklist by whoever reviews the change.
- `docs/workflow/development-workflow/integrations/local-ai-reviewer.md` — the
  four bundle fields, the three evidence keys, the four states, and the fact
  that a custom command may ignore the doctrine.
- `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
  — the `PLATFORM_<n>_REVIEW_DOCTRINE_*` keys now in loop summaries.
- The `--help` block of `local-ai-reviewer.sh`.
- `changelog.d/1654.added.review-doctrine.md` — the release-note fragment
  Protocol 03 Step 6 requires. `added`, because the catalogue and its supply
  are new and nothing changes for a repository that does not adopt one.

---

## Cross-Cutting Checklist Classification

**Classification**: `Applicable`, on the conservative reading. Protocol 02's
first signal is *adding or renaming a checklist category in `REVIEW.md`*. This
item adds one **question inside** an existing category — the Workflow Policy
checklist #1653 introduces — which is a narrower change than adding a category.
An earlier revision of this plan called it `Not applicable` on that ground and
also, wrongly, on the claim that the item changes no checklist at all; AC-5a
requires the change, so the second half was simply false.

The classification is taken as applicable anyway, because the cost of being
wrong is asymmetric: the block's requirement is to enumerate files and say why
each is or is not touched, and doing that on a change that did not need it costs
a table, while skipping it on one that did is how a mirrored surface goes stale.

**Live search**, run at `92247597`:

<!-- workflow-shell-contract: bash -->

```bash
grep -rl "Workflow Policy Review Checklist" .claude .cursor .codex .agents docs
grep -rl "review-doctrine" .claude .cursor .codex .agents
```

Both return **nothing** today — the first because #1653's section is planned and
not yet merged, the second because the catalogue does not exist yet. Both must
be re-run at implementation time, when #1653 has landed: the first will return
the three code-reviewer surfaces #1653 edits, and if any of them enumerates the
checklist's *questions* rather than naming the section, that file needs this
item's question too.

### Files to modify

| File | Change | Why |
| --- | --- | --- |
| `REVIEW.md` | **Edit** | one question in the Workflow Policy checklist, per AC-5a |
| `docs/workflow/development-workflow/review-doctrine.md` | **New** | the catalogue |
| `scripts/lint/review-doctrine-lint.sh` | **New** | the three checks |
| `scripts/development-workflow/workflow-lib.sh` | **Edit** | the shared bound |
| `scripts/development-workflow/local-ai-reviewer.sh` | **Edit** | reader, bundle, evidence, `--help` |
| `.github/workflows/markdown-lint.yml` | **Edit** | the linter's CI step |
| The integration document and Protocol 93 | **Edit** | the fields, keys and states |
| The two test suites and `changelog.d/` | **New** | scenarios and the fragment |

### Enumerated not-applicable surfaces

| File | Result | Rationale |
| --- | --- | --- |
| `docs/workflow/development-workflow/protocols/02-…` and `03-…` | `Not applicable` | neither the planning nor the implementation procedure changes; nothing is required of any future plan |
| `.claude/agents/*`, `.cursor/agents/*`, `.codex/skills/*` | `Not applicable` **pending the re-run above** | none enumerates a checklist's questions today; #1653's three edits name the section, and naming survives a question being added to it |
| `.cursor/commands/review-*.md`, `.cursor/rules/workflow.mdc` | `Not applicable` | each names `REVIEW.md` as the contract without listing sections or questions |
| `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` | `Not applicable` | none enumerates `REVIEW.md`'s contents |

The distinction from #1653 still holds for the catalogue itself: it is not a
checklist and is not consulted by a human following `REVIEW.md`; it is an input
to one script. What makes this item cross-cutting is the single question, not
the document.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A review runs without the doctrine and says nothing | Med | **High** — indistinguishable from a review that used it, so the effectiveness data is silently wrong | Four states, one reported on every run, three of them error states with different owners. Scenario 1 asserts all four values in every state; proof **P1** collapses the three error states into one |
| The doctrine is supplied truncated when over the bound | **High** — truncating is the obvious thing to do with a too-large string | **High** — partial doctrine looks complete, and it drops the newest patterns, which are the ones nobody has internalised | `text` is empty in the `oversized` row, asserted by scenario 2; proof **P2** supplies the first 12,000 bytes instead |
| The bound is duplicated between the linter and the reviewer | **High** if the linter is written in Python like its neighbours | Med — the two drift, and the reviewer accepts a catalogue CI rejects or the reverse | One `readonly` constant in `workflow-lib.sh`, sourced by both; the linter is Bash for that reason. Scenario 15 checks structurally that no second literal exists, 15b checks the boundary in both, and proof **P3** gives the linter its own copy |
| The bound is made overridable so a test can move it | Med — it is the obvious way to test a shared constant | **High** — an environment value above 12,000 makes CI and the reviewer both accept an oversized catalogue, defeating AC-11 | Fixed and `readonly`; the shared-source property is proved structurally instead. Proof **P8** restores the override |
| The incident-reference check is applied to the whole file | Med | Med — contribution guidance legitimately cites repository paths, so the check would reject a valid catalogue and be switched off | Entry-scoped, with the preamble excluded by the same parse that finds the entries. Scenario 13 and proof **P4** |
| The version and the text describe different revisions | Low per review, **certain** across many | **High** — a `supplied` record that is internally false, and every later report grouping by version groups it wrongly | One snapshot, all four values derived from it. Scenario 1b and proof **P11** |
| A file operation fails after a permission-bit test and aborts the reviewer | Med | **High** — under `set -e` the round produces no result at all, which is worse than a review without the doctrine | Every read is attempted with its own handler; `wc -c` is the open probe. Scenario 1a and proof **P10** |
| The digest command is missing and the version is silently empty | Low | Med — two reviews that saw different catalogues become indistinguishable, on one machine, invisibly | No digest means state `unreadable`, not `supplied`. Scenario 6 and proof **P5** |
| The doctrine's text lands in the `key=value` output | Med | Med — a multi-line value is re-emitted as fabricated keys by the loop | Only the three scalars are printed. Scenario 8 runs the loop's real function; proof **P6** prints the text |
| The doctrine is supplied only at some stages | Med | Med — the patterns are stage-independent, and a reviewer looking for them at one stage only finds them there | Supplied at every stage including default. Scenario 9, one case per stage; proof **P7** makes it stage-conditional |

---

## Code Samples

The supply reader, with the two rows that are easy to get wrong:

<!-- workflow-shell-contract: bash -->

```bash
reviewer_doctrine_supply() {
  local path="docs/workflow/development-workflow/review-doctrine.md"
  local snapshot bytes version count status
  local unreadable='{"state":"unreadable","text":"","pattern_count":0,"version":""}'

  [ -f "$path" ] || { printf '{"state":"absent","text":"","pattern_count":0,"version":""}\n'; return 0; }

  # ONE snapshot, and every value below derived from it. Reading the file four
  # times would let an edit land between the hash and the text, producing a
  # `supplied` bundle whose version identifies different bytes than its
  # doctrine — a record that is internally false and looks fine.
  snapshot="$(mktemp)" || { printf '%s\n' "$unreadable"; return 0; }
  cp "$path" "$snapshot" 2>/dev/null || { rm -f "$snapshot"; printf '%s\n' "$unreadable"; return 0; }

  bytes="$(wc -c <"$snapshot" 2>/dev/null)" || { rm -f "$snapshot"; printf '%s\n' "$unreadable"; return 0; }
  bytes="${bytes//[[:space:]]/}"
  [ -n "$bytes" ] || { rm -f "$snapshot"; printf '%s\n' "$unreadable"; return 0; }

  # No digest command is `unreadable`, never `supplied` with an empty version:
  # the version's only job is to tell two reviews apart, and an empty one fails
  # that silently.
  version="$(reviewer_doctrine_version "$snapshot")" || {
    rm -f "$snapshot"; printf '%s\n' "$unreadable"; return 0; }

  if [ "$bytes" -gt "$REVIEW_DOCTRINE_MAX_BYTES" ]; then
    rm -f "$snapshot"
    # text empty (AC-9: never truncated), version present (which catalogue is
    # too big is what the maintainer needs), count 0 (patterns *supplied*).
    jq -n --arg v "$version" '{state:"oversized", text:"", pattern_count:0, version:$v}'
    return 0
  fi

  # grep exits 1 for "no matches", which is a real count of zero, and >1 for an
  # error. `|| true` would flatten both into 0 and report `supplied` with a
  # wrong count — the contract says a failed read is `unreadable`.
  status=0
  count="$(grep -c '^### ' "$snapshot" 2>/dev/null)" || status=$?
  if [ "$status" -eq 1 ]; then
    count=0
  elif [ "$status" -ne 0 ]; then
    rm -f "$snapshot"; printf '%s\n' "$unreadable"; return 0
  fi

  # --rawfile, never --arg with a command substitution: it reads the file's
  # bytes verbatim, trailing newlines included.
  jq -n --rawfile t "$snapshot" --arg v "$version" --argjson c "${count:-0}" \
    '{state:"supplied", text:$t, pattern_count:$c, version:$v}' 2>/dev/null || {
    rm -f "$snapshot"; printf '%s\n' "$unreadable"; return 0; }
  rm -f "$snapshot"
}
```

---

## Planted-Violation Proofs

`REVIEW.md` → Core Rules → Verification Discipline requires two demonstrated
runs per proof, each citing a concrete file and line. The thirteen proofs fall into
three groups:

| Group | Count | Proofs | What the plant reproduces |
| --- | --- | --- | --- |
| Silent | **4** | P1, P2, P5, P7 | a review that used less doctrine than it reports, with nothing to show it |
| Contract | **6** | P3, P4, P6, P8, P9, P13 | a check or an output that breaks its own stated rule |
| Fail-open | **3** | P10, P11, P12 | an error or a race reported as a successful supply |

| # | Violation to plant | Where | Check that must fail, then pass |
| --- | --- | --- | --- |
| P1 | Collapse `absent`, `unreadable` and `oversized` into one `not_supplied` state | a scratch copy of `reviewer_doctrine_supply` | scenario 1 fails: the three states have different owners — a repository that never adopted the catalogue, a broken environment, and a maintainer's edit that needs undoing — and only the third is actionable by anyone reading the pull request; restoring the four states passes |
| P2 | Supply the first `REVIEW_DOCTRINE_MAX_BYTES` of an oversized catalogue | same scratch copy | scenario 2 fails: `text` is non-empty in the `oversized` row, so the reviewer receives a catalogue that looks complete and is missing its most recent patterns. This is AC-9, and the plant is the obvious thing to do with a too-large string; restoring the empty text passes |
| P8 | Make the bound overridable with `"${REVIEW_DOCTRINE_MAX_BYTES:-12000}"` | a scratch copy of `workflow-lib.sh` | scenario 14 fails when the environment carries a larger value: a 12,001-byte catalogue passes the linter and is `supplied`, so an oversized doctrine reaches the reviewer and CI accepts it — the bound exists precisely so a catalogue that no longer fits is edited rather than excused; restoring the fixed `readonly` passes |
| P11 | Derive each value from a fresh read of the live file instead of one snapshot | a scratch copy of `reviewer_doctrine_supply` | scenario 1b fails: with the catalogue rewritten mid-collection, the bundle's `version` is the hash of bytes its `text` does not contain, and every later report that groups reviews by version groups that one wrongly. The plant is invisible whenever nobody edits the file during a review, which is nearly always; restoring the single snapshot passes |
| P13 | Write the evidence file without the `review_doctrine` object | a scratch copy of `write_evidence_file` | scenario 8a fails: the `key=value` output still carries all three values and the loop summary still shows them, so every other check passes — and the artifact a later report actually reads has nothing. AC-15 names the evidence file separately for that reason; restoring the object passes |
| P12 | Count patterns with `grep -c … \|\| true` | same scratch copy | scenario 1a's pattern-count case fails: `grep`'s exit 1 (no matches) and its exit >1 (error) are flattened into count 0, so an unreadable snapshot reports `supplied` with zero patterns instead of `unreadable`. An empty catalogue — the legitimate zero — still passes, which is why the scenario separates the two exits; restoring the status check passes |
| P10 | Replace the read handlers with a single `[ -r "$path" ]` test | a scratch copy of `reviewer_doctrine_supply` | scenario 1a fails: with the file removed after the test, the reviewer aborts under `set -e` instead of reporting `unreadable`, so the round produces no result at all rather than a review that ran without the doctrine. Scenario 1's ordinary unreadable case — a permission bit — still passes, because there the test itself catches it; restoring the per-operation handlers passes both |
| P9 | Read the text with `text="$(cat "$path")"` and pass it as `--arg` | a scratch copy of `reviewer_doctrine_supply` | scenario 7a fails: the bundle's copy loses the file's trailing newlines, so what the reviewer receives is not what the repository stores. Scenario 5's interior-sentence match still passes, which is why 7a compares bytes; restoring `--rawfile` passes |
| P3 | Give `review-doctrine-lint.sh` its own `12000` instead of sourcing `workflow-lib.sh` | a scratch copy of the linter | scenario 15 fails on the structural check — the literal appears in a second file. Scenario 15b still passes, because two copies agree until one is edited, which is exactly the drift the structural check exists to catch before it happens; restoring the source passes |
| P4 | Apply the incident-reference check to the whole file rather than to entries | same scratch copy | scenario 13 fails: a catalogue whose preamble cites `docs/specs/developments/` — which is what contribution guidance does — is rejected, so the check must be either weakened or switched off; restoring the entry scope passes |
| P5 | Return `supplied` with an empty version when no digest command exists | a scratch copy of the version helper | scenario 6 fails: two reviews that saw different catalogues become indistinguishable, and the failure is confined to machines without `sha256sum` or `shasum` — so it would ship green everywhere it was tested; restoring the `unreadable` state passes |
| P6 | Print the doctrine's text as a fourth `key=value` line | a scratch copy of the print block | scenario 8 fails: the loop's `emit_prefixed_platform_output` reads line by line, so every line of the catalogue after the first is re-emitted as a fabricated `PLATFORM_1_<text>` key. The plant looks like completeness — the same value the bundle carries; restoring the three scalars passes |
| P7 | Supply the doctrine only for recognised stages, not the default one | a scratch copy of the bundle build | scenario 9's default-stage case fails: a pull request on an unrecognised branch reviews without the doctrine, which is the case a stage-aware reviewer is most likely to leave out and the one nobody looks at; restoring the unconditional supply passes |

Four proofs plant the **silent** direction, because a review that used less
doctrine than it reports leaves no trace. P5 is the one to read twice: its
failure appears only on a machine with neither digest command, so it ships green
everywhere it is tested.

---

## Implementation Order

0. **Hard stop**: confirm #1653 is implemented and merged, and re-read the
   `jq -n` bundle object and the `print_kv` block against the merged code rather
   than against #1653's plan. **Verify**: the field list in both places.
1. Declare `readonly REVIEW_DOCTRINE_MAX_BYTES=12000` in `workflow-lib.sh`.
   **Verify**: scenarios 15 and 15b — one literal definition and none in either
   consumer, and the same boundary behaviour in both.
2. Add `scripts/lint/review-doctrine-lint.sh` with its three checks and the
   0/1 exit contract. **Verify**: scenarios 11 through 15, including the
   12,000/12,001 boundary and the shared-constant case.
3. Add the catalogue with its preamble and five seeded patterns, and add the
   generality question to `REVIEW.md`'s Workflow Policy checklist. **Verify**:
   scenarios 16 and 16a — the catalogue passes its own linter, has five
   patterns, its preamble carries the AC-3 statement and the AC-3a request, and
   the obligation appears in **both** places AC-5a names.
4. Add `reviewer_doctrine_supply` and its version helper: one snapshot, a
   handler on every file operation, and `grep`'s exit 1 kept distinct from its
   exit >1. **Verify**: scenarios 1, 1a, 1b and 2 through 6 — all four states with all four values, the `oversized` row's
   empty text and present version, and the missing-digest case.
5. Add the four bundle fields and the three `print_kv` lines, plus the evidence
   object. **Verify**: scenarios 7, 7a, 8, 8a and 10 — the enumerated field
   list, the byte-for-byte text comparison, the evidence artifact's three
   values, the real `emit_prefixed_platform_output`, and the unchanged existing
   context.
6. Add the CI step. **Verify**: the linter runs and fails the build on a
   deliberately malformed catalogue.
7. Update the `--help` block, the integration document, Protocol 93, and add
   `changelog.d/1654.added.review-doctrine.md`. **Verify**: runbook **Step 10**,
   which reads all four surfaces against each other — Step 8 tests the linter.
8. Produce the thirteen planted-violation proofs (P1-P13) and record them in the PR
   with the command, file, line and both outcomes for each.

---

## Rollback

Revert the implementation PR. It removes the catalogue, the `REVIEW.md`
question, the linter, its CI step,
the supply reader and version helper, the four bundle fields, the three evidence
keys, the `workflow-lib.sh` constant, the documentation updates and the two test
suites. Reverting restores the stage-agnostic bundle exactly; no other script
reads any of the new fields, and no historical artifact depends on them.

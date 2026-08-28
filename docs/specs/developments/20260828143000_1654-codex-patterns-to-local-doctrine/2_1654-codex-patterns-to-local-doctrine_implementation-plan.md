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
| The context bundle's shape and its single build site | Thirteen fields, one `jq -n` | `local-ai-reviewer.sh:339-366` | 2026-08-28, repo SHA `92247597` | `local-ai-reviewer.sh` and its two test suites | `Conflict` — see below |
| `workflow-lib.sh` is in scope for both the reviewer and a shell lint | Sourced at `local-ai-reviewer.sh:11` | The file itself | 2026-08-28, repo SHA `92247597` | `scripts/development-workflow/`, `scripts/lint/` | `Verified` |

**Conflict record.** #1653 adds three fields to the same `jq -n` object and
three `print_kv` calls to the same block. Affected plan statements: the bundle
change and the evidence change.

**Resolution status**: `Resolved` by sequencing. Recorded in **Dependencies**
and enforced by **Implementation Order step 0**. Decision owner: LH — if #1653
is implemented differently from its plan, the field list here must be re-read
against the merged code rather than against this plan.

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
      # `:-` and not a bare assignment: an unconditional one would overwrite an
      # environment value, and scenario 15 — the only check that the two
      # consumers share a bound — works by setting one. Validation follows
      # PR_REVIEW_LOOP_SMALL_FINDINGS_STOP_ROUNDS: warn and fall back rather
      # than trust an unusable value.
      REVIEW_DOCTRINE_MAX_BYTES="${REVIEW_DOCTRINE_MAX_BYTES:-12000}"
      if ! [[ "$REVIEW_DOCTRINE_MAX_BYTES" =~ ^[1-9][0-9]*$ ]]; then
        echo "WARN: REVIEW_DOCTRINE_MAX_BYTES must be a positive integer; defaulting to 12000" >&2
        REVIEW_DOCTRINE_MAX_BYTES=12000
      fi
      ```

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
7. The bundle carries all four fields, and its thirteen existing
   `local_ai_reviewer_context.v1` fields are unchanged in name and type,
   asserted against an enumerated list.
8. The `key=value` output carries the three scalar keys and **not** the text,
   and passing that output through the loop's real
   `emit_prefixed_platform_output` yields three `PLATFORM_1_REVIEW_DOCTRINE_*`
   keys and no fabricated ones.
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
15. The linter and the reviewer agree about the bound: with
    `REVIEW_DOCTRINE_MAX_BYTES` exported to a small value, both the linter's
    failure and the reviewer's `oversized` state move together, **and the test
    asserts the overridden value took effect** rather than only that the two
    agree — two consumers ignoring the override agree too. The override is the
    scenario's mechanism, which is why the constant uses `:-`.
15a. An **invalid** override — `0`, `-1`, `abc`, empty — warns and falls back to
    12,000 in both consumers, rather than being trusted. Following
    `PR_REVIEW_LOOP_SMALL_FINDINGS_STOP_ROUNDS`'s convention, and asserted in
    both so they cannot diverge on the fallback either. This is AC-12, and it is the scenario that fails if either
    grows its own copy of the number.
16. The catalogue in the repository passes its own linter, contains exactly the
    five seeded patterns, and its preamble contains the AC-3 statement and the
    AC-3a request.

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
| Bundle field fixture | The thirteen `local_ai_reviewer_context.v1` field names, enumerated | inline in `scripts/development-workflow/tests/test-local-ai-reviewer.sh` |

---

## Documentation Updates

- `docs/workflow/development-workflow/review-doctrine.md` — the catalogue.
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

**Classification**: `Not applicable`. Protocol 02's three signals are adding or
renaming a checklist category in `REVIEW.md` or a planning document; imposing an
acceptance criterion on every plan; and adding a conditional guidance block to a
planning or implementation protocol. This item adds a **new document** that a
script reads, changes no checklist, and requires nothing of any future plan.

The distinction from #1653 is worth stating, since the two look similar: #1653
added a section to `REVIEW.md`, which is the first signal exactly. This item's
catalogue is not a checklist and is not consulted by a human reviewer following
`REVIEW.md`; it is an input to one script.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A review runs without the doctrine and says nothing | Med | **High** — indistinguishable from a review that used it, so the effectiveness data is silently wrong | Four states, one reported on every run, three of them error states with different owners. Scenario 1 asserts all four values in every state; proof **P1** collapses the three error states into one |
| The doctrine is supplied truncated when over the bound | **High** — truncating is the obvious thing to do with a too-large string | **High** — partial doctrine looks complete, and it drops the newest patterns, which are the ones nobody has internalised | `text` is empty in the `oversized` row, asserted by scenario 2; proof **P2** supplies the first 12,000 bytes instead |
| The bound is duplicated between the linter and the reviewer | **High** if the linter is written in Python like its neighbours | Med — the two drift, and the reviewer accepts a catalogue CI rejects or the reverse | One constant in `workflow-lib.sh`, sourced by both; the linter is Bash for that reason. Scenario 15 moves the constant and requires both to follow; proof **P3** gives the linter its own copy |
| The incident-reference check is applied to the whole file | Med | Med — contribution guidance legitimately cites repository paths, so the check would reject a valid catalogue and be switched off | Entry-scoped, with the preamble excluded by the same parse that finds the entries. Scenario 13 and proof **P4** |
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
  local bytes version count

  [ -f "$path" ] || { printf '{"state":"absent","text":"","pattern_count":0,"version":""}\n'; return 0; }
  # Readability is probed without capturing: `$(cat …)` strips every trailing
  # newline, and the bundle must carry the catalogue's stored bytes exactly.
  # The text itself is read by `jq --rawfile` below, which preserves them.
  [ -r "$path" ] || {
    printf '{"state":"unreadable","text":"","pattern_count":0,"version":""}\n'; return 0; }

  # No digest command is `unreadable`, never `supplied` with an empty version:
  # the version's only job is to tell two reviews apart, and an empty one fails
  # that silently.
  version="$(reviewer_doctrine_version "$path")" || {
    printf '{"state":"unreadable","text":"","pattern_count":0,"version":""}\n'; return 0; }

  bytes="$(wc -c <"$path" | tr -d ' ')"
  if [ "$bytes" -gt "$REVIEW_DOCTRINE_MAX_BYTES" ]; then
    # text empty (AC-9: never truncated), version present (which catalogue is
    # too big is what the maintainer needs), count 0 (patterns *supplied*).
    jq -n --arg v "$version" \
      '{state:"oversized", text:"", pattern_count:0, version:$v}'
    return 0
  fi

  count="$(grep -c '^### ' "$path" || true)"
  # --rawfile, never --arg with a command substitution: it reads the file's
  # bytes verbatim, trailing newlines included.
  jq -n --rawfile t "$path" --arg v "$version" --argjson c "${count:-0}" \
    '{state:"supplied", text:$t, pattern_count:$c, version:$v}'
}
```

---

## Planted-Violation Proofs

`REVIEW.md` → Core Rules → Verification Discipline requires two demonstrated
runs per proof, each citing a concrete file and line. The nine proofs fall into
two groups:

| Group | Count | Proofs | What the plant reproduces |
| --- | --- | --- | --- |
| Silent | **4** | P1, P2, P5, P7 | a review that used less doctrine than it reports, with nothing to show it |
| Contract | **5** | P3, P4, P6, P8, P9 | a check or an output that breaks its own stated rule |

| # | Violation to plant | Where | Check that must fail, then pass |
| --- | --- | --- | --- |
| P1 | Collapse `absent`, `unreadable` and `oversized` into one `not_supplied` state | a scratch copy of `reviewer_doctrine_supply` | scenario 1 fails: the three states have different owners — a repository that never adopted the catalogue, a broken environment, and a maintainer's edit that needs undoing — and only the third is actionable by anyone reading the pull request; restoring the four states passes |
| P2 | Supply the first `REVIEW_DOCTRINE_MAX_BYTES` of an oversized catalogue | same scratch copy | scenario 2 fails: `text` is non-empty in the `oversized` row, so the reviewer receives a catalogue that looks complete and is missing its most recent patterns. This is AC-9, and the plant is the obvious thing to do with a too-large string; restoring the empty text passes |
| P8 | Declare the bound with a bare `REVIEW_DOCTRINE_MAX_BYTES=12000` instead of `:-` | a scratch copy of `workflow-lib.sh` | scenario 15 fails on its overridden-value assertion. Without that assertion the plant would be invisible — the override is ignored, both consumers keep 12,000, and "the two agree" is still true — which is why the scenario checks the value took effect rather than only that they match; restoring `:-` passes |
| P9 | Read the text with `text="$(cat "$path")"` and pass it as `--arg` | a scratch copy of `reviewer_doctrine_supply` | scenario 7a fails: the bundle's copy loses the file's trailing newlines, so what the reviewer receives is not what the repository stores. Scenario 5's interior-sentence match still passes, which is why 7a compares bytes; restoring `--rawfile` passes |
| P3 | Give `review-doctrine-lint.sh` its own copy of the bound instead of sourcing `workflow-lib.sh` | a scratch copy of the linter | scenario 15 fails: with the constant overridden, the linter and the reviewer disagree about the same catalogue — CI rejects what the reviewer supplies, or the reverse. Scenarios 11, 12 and 14 all pass, because they never move the constant; restoring the source passes |
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
1. Declare `REVIEW_DOCTRINE_MAX_BYTES` in `workflow-lib.sh` with the `:-`
   override form and its validation. **Verify**: scenarios 15 and 15a — the
   override reaches both consumers, and an invalid one warns and falls back in
   both.
2. Add `scripts/lint/review-doctrine-lint.sh` with its three checks and the
   0/1 exit contract. **Verify**: scenarios 11 through 15, including the
   12,000/12,001 boundary and the shared-constant case.
3. Add the catalogue with its preamble and five seeded patterns. **Verify**:
   scenario 16 — it passes its own linter, has five patterns, and its preamble
   carries the AC-3 statement and the AC-3a request.
4. Add `reviewer_doctrine_supply` and its version helper. **Verify**: scenarios
   1 through 6 — all four states with all four values, the `oversized` row's
   empty text and present version, and the missing-digest case.
5. Add the four bundle fields and the three `print_kv` lines, plus the evidence
   object. **Verify**: scenarios 7, 7a, 8 and 10 — the enumerated field list,
   the byte-for-byte text comparison, the
   real `emit_prefixed_platform_output`, and the unchanged existing context.
6. Add the CI step. **Verify**: the linter runs and fails the build on a
   deliberately malformed catalogue.
7. Update the `--help` block, the integration document, Protocol 93, and add
   `changelog.d/1654.added.review-doctrine.md`. **Verify**: runbook Step 8.
8. Produce the nine planted-violation proofs (P1-P9) and record them in the PR
   with the command, file, line and both outcomes for each.

---

## Rollback

Revert the implementation PR. It removes the catalogue, the linter, its CI step,
the supply reader and version helper, the four bundle fields, the three evidence
keys, the `workflow-lib.sh` constant, the documentation updates and the two test
suites. Reverting restores the stage-agnostic bundle exactly; no other script
reads any of the new fields, and no historical artifact depends on them.

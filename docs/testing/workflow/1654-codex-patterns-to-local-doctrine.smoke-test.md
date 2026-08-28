# Smoke Test: Review Doctrine from External Findings (#1654)

**Item**: [#1654](https://github.com/lhpaul/ai-dev-framework-template/issues/1654)
**Spec**: [1_1654-codex-patterns-to-local-doctrine_specs.md](../../specs/developments/20260828143000_1654-codex-patterns-to-local-doctrine/1_1654-codex-patterns-to-local-doctrine_specs.md)
**Plan**: [2_1654-codex-patterns-to-local-doctrine_implementation-plan.md](../../specs/developments/20260828143000_1654-codex-patterns-to-local-doctrine/2_1654-codex-patterns-to-local-doctrine_implementation-plan.md)

Steps 1 through 4 source the reviewer with `HARNESS_MODE=1` — the guard #1653
adds — and call the supply reader directly. Sourcing enables `set -euo pipefail`
in this shell; call anything that returns non-zero as a normal answer inside an
`if` or with `|| true`.

---

## Step 1: Four states, four values each

**Maps to**: AC-7, AC-8.

1. Call `reviewer_doctrine_supply` with **no** catalogue present.
2. Call it with a catalogue whose permissions make it unreadable.
3. Call it with a catalogue of 12,001 bytes.
4. Call it with a well-formed catalogue of three patterns.

5. Call it five more times, each with a **different** file operation failing
   while the others succeed: the snapshot copy, the size probe, the digest, the
   pattern count, and the `jq --rawfile` read — for instance by removing the
   file between the probe and the read, or by putting a failing stub first on
   `PATH`. For the pattern count, fail it two ways: `grep` exiting **1** (no
   matches) and `grep` exiting **>1** (an error).
6. Call it once with the catalogue **replaced** immediately after the snapshot
   is taken, and compare the returned `version` to a hash of the returned
   `text`.

**Expected result**:

| Case | `state` | `text` | `pattern_count` | `version` |
| --- | --- | --- | --- | --- |
| 1 | `absent` | empty | 0 | empty |
| 2 | `unreadable` | empty | 0 | empty |
| 3 | `oversized` | empty | 0 | the hash |
| 4 | `supplied` | the full text | 3 | the hash |

Assert **all four values** in every case, not the state alone. Three of the four
states are error paths with different owners — a repository that never adopted
the catalogue, a broken environment, and a maintainer's edit that needs undoing
— and only the third is actionable by someone reading the pull request.
Collapsing them into one "not supplied" is the tempting simplification. Proof P1.

Case 6's `version` is the hash of its own `text`, never of the replacement.
All four returned values come from **one snapshot**, because reading the live
file four times lets an edit land between the hash and the text — producing a
`supplied` record that is internally false and looks entirely normal, after
which every report grouping reviews by version groups that one wrongly. Proof
P11.

Case 5's runs return `unreadable` **and the reviewer keeps running** — except
for the `grep` exit-1 run, which is a real count of zero and stays `supplied`.
That distinction is the point of failing the count two ways: `grep -c … || true`
flattens "no matches" and "error" into 0, so an unreadable snapshot would report
`supplied` with zero patterns. Proof P12.
This step runs in a shell that has sourced the script, so `set -euo pipefail` is
active — which is how it runs in production, and the reason a permission-bit
test is not enough: an ACL, an I/O error, or a file removed between the test and
the use all pass `[ -r … ]`, and the failure that follows would abort the
reviewer rather than report a state. AC-8 requires the review to still run. A
handler that is present but reached only after `set -e` has aborted is not a
handler. Proof P10.

## Step 2: An oversized catalogue supplies nothing and still names itself

**Maps to**: AC-9.

1. Read case 3's `text` and `version` from Step 1.

**Expected result**: `text` is **empty**; `version` is the twelve-character
hash.

Both halves matter and they pull in opposite directions. Supplying the first
12,000 bytes is the obvious thing to do with a too-large string, and it is the
failure AC-9 names: partial doctrine looks complete to the reviewer, and the
patterns it drops are the most recently added — the ones nobody has internalised
yet. Withholding the version is the opposite over-correction: the file *was*
read, and which version is too big is the first thing the maintainer needs.
Proof P2.

## Step 3: The count is patterns supplied, not patterns present

**Maps to**: AC-7.

1. Call the reader with an oversized catalogue containing **nine** well-formed
   patterns.
2. Call it with an **empty** catalogue — a preamble and no patterns, within
   bound.

**Expected result**: case 1 reports `pattern_count` **0**. Case 2 is `supplied`
with `pattern_count` 0.

Case 1 reporting nine would make the effectiveness data claim coverage that
never happened: zero patterns reached the review. Case 2 is `supplied` and not a
failure state, because adopting the doctrine must not be a two-step operation —
the count beside the state is what distinguishes an empty catalogue from a
missing one.

## Step 4: The version, and what happens without a digest

**Maps to**: AC-7, and the version's only purpose.

1. Compute the SHA-256 of the catalogue independently — not with the function
   under test — and compare its first twelve hex characters to `version`.
2. Call the reader with a `PATH` containing **neither** `sha256sum` nor
   `shasum`.

**Expected result**: case 1 matches. Case 2 returns state **`unreadable`**, not
`supplied` with an empty version.

Case 2 is the one that ships green. Its failure appears only on a machine with
neither digest command, so a `supplied` result with an empty version would pass
everywhere it was tested and then make two reviews that saw *different*
catalogues indistinguishable — which is the single question the version exists
to answer. Proof P5.

## Step 5: The bundle carries the doctrine, and keeps its contract

**Maps to**: AC-6, AC-14.

1. Run the reviewer against a fixture pull request with
   `LOCAL_AI_REVIEWER_COMMAND` set to a stub that copies `CONTEXT_BUNDLE_PATH`
   aside.
2. Read the copied bundle. Assert the four added fields.
3. Assert each of the thirteen `local_ai_reviewer_context.v1` field names is
   present with its original type, and that `schema_version` still reads
   `local_ai_reviewer_context.v1`.
4. Assert `review_doctrine` contains **text from the catalogue** — a sentence
   matched literally — not merely that the field is non-empty.
5. Extract `review_doctrine` to a file and `cmp` it against the catalogue on
   disk: **byte-identical**, trailing newlines included.

**Expected result**: all present and unchanged; four added; version unchanged.

Step 4 is AC-10's requirement and the difference between testing the plumbing
and testing the payload: a field that is non-empty proves a variable was set,
not that the doctrine arrived.

Step 5 is the difference between *some* of the payload and *all* of it. Reading
the file with `text="$(cat …)"` strips every trailing newline, so the bundle
would carry a catalogue that differs from the stored one — and Step 4 would
still pass, because what is lost is at the end. The text is read with
`jq --rawfile`. Proof P9.

The text travels **in** the bundle rather than as a path. A command may run
where the repository is not checked out, and a path would make `supplied` mean
*the reviewer could have read it* instead of *the reviewer was given it* — which
is the distinction the whole supply state exists to record.

## Step 6: Only the scalars reach the `key=value` output

**Maps to**: the line-oriented output contract.

1. Read the reviewer's `key=value` stdout. Confirm `REVIEW_DOCTRINE_STATE`,
   `REVIEW_DOCTRINE_PATTERN_COUNT` and `REVIEW_DOCTRINE_VERSION`, and confirm
   the doctrine's **text** is not among them.
2. Pass that stdout through the loop's real `emit_prefixed_platform_output` with
   index 1.

**Expected result**: three `PLATFORM_1_REVIEW_DOCTRINE_*` keys and no fabricated
ones.

Printing the text as a fourth line looks like completeness — it is the same
value the bundle already carries — and it breaks the contract: the loop reads
line by line, so every line of the catalogue after the first is re-emitted as a
key of its own. Step 2 runs the real function rather than reading its source,
because "no change needed in the loop" is the kind of claim that holds until a
value contains a newline. Proof P6.

## Step 7: Every stage gets the doctrine

**Maps to**: AC-13.

1. Run the reviewer once per stage the resolver recognises — `spec`, `plan`,
   `implementation` — and once on an unrecognised branch, which resolves to
   `default`.
2. Read `review_doctrine_state` in each bundle.

**Expected result**: `supplied` in all four.

The `default` case is the one to watch. The patterns are stage-independent — a
matrix that disagrees with its criteria is a defect in a spec, a plan and a
protocol alike — and a stage-aware reviewer invites making things
stage-conditional. The branch nobody recognises is the one that would be left
out, and it is also the one nobody looks at. Proof P7.

## Step 8: The linter, and its four rules

**Maps to**: AC-2a, AC-5, AC-11, AC-12.

<!-- workflow-shell-contract: bash -->

```bash
bash scripts/lint/review-doctrine-lint.sh; echo "exit=$?"
```

1. Run it on the repository's own catalogue.
2. Run it on a catalogue whose entry is missing its `**Detect**:` paragraph, and
   one whose entry has two `**Shape**:` paragraphs.
3. Run it on four catalogues, one per AC-4 form: `#1646`, a
   `github.com/…/pull/1` URL, `PR 1646`, and a
   `docs/specs/developments/…` path — each inside an **entry**.
4. Run it on four near-miss controls that must **not** trip it: `# Title`,
   `PR review`, `docs/specs/`, and `example.com/pull/1`.
5. Run it on a catalogue whose **preamble** cites a
   `docs/specs/developments/…` path and whose entries are clean.
6. Run it at exactly **12,000** bytes and at **12,001**.
7. Check the bound structurally:

   <!-- workflow-shell-contract: bash -->

   ```bash
   grep -c '12000' scripts/development-workflow/workflow-lib.sh
   grep -c '12000' scripts/lint/review-doctrine-lint.sh
   grep -c '12000' scripts/development-workflow/local-ai-reviewer.sh
   ```

8. Run **both** consumers against the same 12,000-byte catalogue, then against
   the same 12,001-byte one.

**Expected result**: 1 exits 0; 2 and 3 exit 1; 4 exits 0; 5 exits **0**; 6
exits 0 then 1; 7 prints `1`, `0`, `0` — one definition, no second copy; 8 shows
the linter passing and the reviewer `supplied` at 12,000, and the linter failing
and the reviewer `oversized` at 12,001.

Case 5 is the scope rule. Contribution guidance legitimately cites repository
documents by path — that is what guidance is — so a file-scoped check would
reject a valid catalogue and be switched off within a week. Proof P4.

Case 7 is AC-12 and the reason the linter is Bash rather than Python like its
neighbours: both it and the reviewer source `workflow-lib.sh`, so the bound is
literally the same value in both rather than two copies that agree today.
Nothing else in this runbook would notice them drifting. Proof P3.

It is proved **structurally**, not by moving the bound. An earlier revision of
this plan made the constant overridable so a test could change it — which would
also let an environment value above 12,000 make CI and the reviewer both accept
an oversized catalogue, defeating AC-11 and the rule the bound exists for. The
constant is fixed and `readonly`; case 7 asserts no second copy of the literal
exists, and case 8 asserts the same boundary behaviour in both. Two copies that
agree today pass case 8 and fail case 7, which is why both run. Proofs P3
and P8.

Case 6 tests the boundary, not a value near it. A catalogue "about the right
size" passes whatever the comparison operator is.

## Step 9: The catalogue itself

**Maps to**: AC-1, AC-2, AC-3, AC-3a, AC-4, AC-16.

1. Read `docs/workflow/development-workflow/review-doctrine.md`.
2. Confirm five patterns, each with one `**Shape**:`, one `**Example**:` and one
   `**Detect**:`.
3. Confirm the preamble states that the catalogue lists shapes worth looking for
   and is **not** the set of things worth reporting, and that it asks a reviewer
   matching a pattern to name it.
4. Confirm the preamble's contribution guidance says what to do when the bound
   is reached: merge or remove a pattern, never raise the bound in the same
   change that breaches it.
5. Read each entry for incident-specific wording a linter cannot catch — a
   person's name, a document title, a sentence that only makes sense to someone
   who saw the original incident.
6. Confirm that same obligation appears in **both** places AC-5a names: the
   catalogue's contribution guidance, and `REVIEW.md`'s Workflow Policy
   checklist.

**Expected result**: all six present. Step 6 checks both places because AC-5a
names both — the guidance is read by whoever adds a pattern, the checklist by
whoever reviews the change — and an obligation recorded in one place is one a
reviewer never sees. Step 5 is a human judgement and the spec says so — AC-5a assigns it to review rather than to a check, because a person's
name has no reliable machine representation and a check that pretended otherwise
would report clean on the cases it cannot see.

## Step 10: Documentation agrees

**Maps to**: the documentation-drift risk.

1. Read the doctrine section of
   `docs/workflow/development-workflow/integrations/local-ai-reviewer.md`.
2. Read the reviewer-loop history section of
   `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`.
3. Run `scripts/development-workflow/local-ai-reviewer.sh --help`.
4. Read `changelog.d/1654.added.review-doctrine.md`.

**Expected result**: the first three describe the same four fields, the same
three evidence keys and the same four states, and none of them describes the
doctrine as truncated when oversized or as supplied by path. The fragment is
named `<item>.<kind>.<slug>.md` with a bare `1654` and reads as a finished
changelog bullet from the reader's perspective.

## Step 11: Static checks

1. Run `shellcheck` on `scripts/development-workflow/local-ai-reviewer.sh`,
   `scripts/lint/review-doctrine-lint.sh` and
   `scripts/development-workflow/workflow-lib.sh`.
2. Run

   <!-- workflow-shell-contract: bash -->

   ```bash
   python3 scripts/lint/workflow-shell-guard-lint.py \
     --base-ref origin/develop-internal-reviewer-effectiveness
   ```

3. Run `markdownlint-cli2` on the changed documentation, including the new
   catalogue.

**Expected result**: all three exit 0.

## Step 12: Planted-violation proofs

1. Read the implementation PR's `Planted-Violation Proofs` heading.
2. Confirm P1 through P12 each record the command, the file and line of the
   planted violation, and both outcomes.

**Expected result**: twelve proofs in three groups — **four** silent, **five**
contract, **three** fail-open, per the plan's proof-group table.

The silent group carries the weight, because a review that used less doctrine
than it reports leaves no trace anywhere. P5 is the one to read twice: its
failure appears only on a machine with neither `sha256sum` nor `shasum`, so it
ships green everywhere it is tested.

---

## Rollback verification

Revert the implementation PR and re-run Steps 1 and 5. The supply reader must be
absent, and a freshly built bundle must carry none of the four fields and its
original thirteen unchanged.

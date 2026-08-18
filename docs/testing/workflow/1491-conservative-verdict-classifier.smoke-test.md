# Smoke Test Runbook: Conservative Verdict Classifier

**Feature**: Conservative (allow-list) verdict classifier for `codex-github-reviewer.sh` (Issue #1491)
**Spec**: None — Refactor path. Work item brief: [Issue #1491](https://github.com/lhpaul/ai-dev-framework-template/issues/1491)
**Implementation plan**: [`docs/specs/developments/20260817203204_1491-conservative-verdict-classifier/2_1491-conservative-verdict-classifier_implementation-plan.md`](../../specs/developments/20260817203204_1491-conservative-verdict-classifier/2_1491-conservative-verdict-classifier_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch for issue #1491 is checked out
- [ ] `bash`, `grep`, `sed`, `awk`, `jq`, and `gh` are available on `PATH`
- [ ] `gh auth status` succeeds (needed only for Step 5)
- [ ] You know which platform's tooling you are on (macOS/BSD or Linux/GNU) so you can note it in the results

**Design assets**: none. This work item has no `## Design assets` section, no tracker attachments, no linked
design files, and no `assets/` directory in its development folder. No expected-versus-actual fidelity step
is included, and no visual baseline should be invented.

---

## Test Data

| Item | Value |
| --- | --- |
| Reviewer script | `scripts/development-workflow/codex-github-reviewer.sh` |
| Test harness | `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Integration doc | `docs/workflow/development-workflow/integrations/codex-github.md` |
| Reviewer loop protocol | `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` |
| Real clean Codex comment source | PR #1489 in `lhpaul/ai-dev-framework-template` |
| Scratch directory | any writable temporary directory |

---

## Smoke Test Steps

### Step 1: The full harness passes

**Maps to**: Testing Strategy — residual verification evidence item 1

1. From the repository root, run:

   ```bash
   bash scripts/development-workflow/tests/test-pr-review-loop.sh
   ```

2. Read the summary line at the end of the output.

**Expected result**: the run exits 0 and reports zero failures. Note the total assertion count so it can be
compared against the pre-change count recorded in the PR description.

---

### Step 2: Removed symbols are actually gone

**Maps to**: Implementation Order steps 2 and 5

1. Run:

   ```bash
   grep -n "CODEX_NEGATED_APPROVAL\|not_only\|CODEX_APPROVAL_PATTERN\|CODEX_RESIDUE_STARTER_PATTERN" \
     scripts/development-workflow/codex-github-reviewer.sh
   ```

2. Run:

   ```bash
   grep -n "CODEX_CLEAN_SIGNAL_PATTERN\|CODEX_APPROVAL_DISQUALIFIER_PATTERN\|CODEX_RESIDUE_FILLER_WORD_PATTERN\|CODEX_VENDOR_FLAVOR_TOKEN_PATTERN\|CODEX_FOOTER_OPENING_LITERAL\|codex_strip_codex_footer\|codex_strip_vendor_metadata_lines\|codex_response_first_paragraph\|codex_excise_clean_signals\|codex_residue_is_closed_grammar" \
     scripts/development-workflow/codex-github-reviewer.sh
   ```

3. Run, to confirm the audited filler list does not admit vendor-identity or directive-capable tokens
   (Codex GitHub findings `3803050745`/`3803050750`):

   ```bash
   grep -n "^CODEX_RESIDUE_FILLER_WORD_PATTERN=" scripts/development-workflow/codex-github-reviewer.sh \
     | grep -E "codex|review|reviewed|commit|\bthis\b|\bthat\b"
   ```

4. Run, to confirm `codex_strip_codex_footer` is an exact byte-literal match, not a regex (Codex GitHub
   finding `3803189273`):

   ```bash
   grep -n "codex_strip_codex_footer" -A 2 scripts/development-workflow/codex-github-reviewer.sh
   ```

**Expected result**: the first command prints nothing (the three originally-superseded symbols, plus
`CODEX_RESIDUE_STARTER_PATTERN` — added and then deleted again within the same review round after a human
decision rejected the design it supported — are all removed). The second command prints at least one
definition line for each of the ten symbols (the original four plus `CODEX_RESIDUE_FILLER_WORD_PATTERN`,
`CODEX_VENDOR_FLAVOR_TOKEN_PATTERN`, `CODEX_FOOTER_OPENING_LITERAL`, `codex_strip_vendor_metadata_lines`,
`codex_excise_clean_signals`, and `codex_residue_is_closed_grammar`, added during the Step 7 review round for
the zero-tolerance closed residue grammar, iterative excision, and exact-literal footer matching — see the
implementation plan's Decision 2 and Decision 6). The third command prints nothing:
`CODEX_RESIDUE_FILLER_WORD_PATTERN` must not contain `codex`, `review`, `reviewed`, `commit`, `this`, or
`that` — all six were removed this round because they can function as vendor-identity tokens, imperative
verbs, or directive-object pronouns (see Decision 2's "governing asymmetry" note). The fourth command's
`codex_strip_codex_footer` body must compare `$0` against `$CODEX_FOOTER_OPENING_LITERAL` with `==` — it must
**not** contain any regex metacharacters like `[^>]*`, `.*`, or `\|` used for matching the footer; if it does,
the footer strip has regressed back to pattern matching and must be treated as a P1 finding (Decision 6's
standing rule in Risks & Mitigations).

---

### Step 3: The blocking classifier is untouched

**Maps to**: Decision 5

1. Run:

   ```bash
   grep -n "CODEX_BLOCKING_PATTERN=\|CODEX_MERGE_REFUSAL_PATTERN=\|CODEX_NEGATION_WORDS=" \
     scripts/development-workflow/codex-github-reviewer.sh
   ```

2. Compare the printed pattern definitions against the same lines on `develop`:

   ```bash
   git diff origin/develop -- scripts/development-workflow/codex-github-reviewer.sh | grep -n "^[-+].*CODEX_BLOCKING_PATTERN\|^[-+].*CODEX_NEGATION_WORDS\|^[-+].*CODEX_MERGE_REFUSAL_PATTERN"
   ```

**Expected result**: the three blocking-side pattern definitions are present and the diff shows no change to
their values. The only diff touching `codex_response_is_blocking` is the removed
`codex_strip_not_only_idiom` call.

---

### Step 4: A clean response with an unrelated negation now safe-fails

**Maps to**: Test disposition Group C; Operational cost section

1. Create a scratch directory and a mock `gh` that returns a SHA-pinned Codex root comment reading
   `Looks good overall; tests were not run.`, following the mock convention used by the neighbouring
   scenarios in the harness (auth status, `pr view … headRefOid`, empty reviews and inline comments, and the
   comment payload).
2. Run the reviewer with a short poll budget:

   ```bash
   PATH="$SCRATCH:$PATH" scripts/development-workflow/codex-github-reviewer.sh \
     42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0
   ```

**Expected result**: the command exits 1, prints
`VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)`, and emits an
`INFO: Codex clean signal present but disqualified` line naming the negation/hedge/actionable reason. Before
this change the same body returned `VERDICT: APPROVED`; the flip is intended.

---

### Step 5: A real vendor clean response still approves

**Maps to**: Edge case E9; residual verification evidence item 3 — this is the highest-impact check in the
runbook, and also the check that validates `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` (currently just `swish`) still
covers the live wire format's sign-off flourish under the zero-tolerance closed residue grammar (A3 check 2)
— see the implementation plan's Decision 2

1. Capture the current real clean-response body:

   ```bash
   gh api repos/lhpaul/ai-dev-framework-template/issues/1489/comments \
     --jq '.[] | select(.user.login | test("codex"; "i")) | .body'
   ```

2. Confirm it still has the shape the plan recorded: a `Codex Review: Didn't find any major issues.` opening
   line, a `**Reviewed commit:**` marker, and an "About Codex in GitHub" `<details>` footer containing a
   bulleted list.
3. Build a mock `gh` that serves that exact body as a SHA-pinned root comment (with the `Reviewed commit`
   marker rewritten to the mock head SHA) and run the reviewer as in Step 4.

**Expected result**: the command exits 0 and prints `VERDICT: APPROVED`. If the captured body no longer has
the recorded shape, stop and report it — the allow-list may need a reviewed addition rather than a workaround.
If it exits 1 with `residue grammar not closed` in the stderr diagnostic, this can now mean either of two
things (both require re-fetching the live body and comparing byte-for-byte, not guessing): (a) the vendor
changed its sign-off flourish and `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` no longer covers it, or (b) the vendor
changed the footer's exact opening bytes and `CODEX_FOOTER_OPENING_LITERAL` (Decision 6) no longer matches,
so the whole footer stayed in the residue. Either way, stop and report it rather than loosening the grammar
or the footer match unreviewed. The correct fix, per Decision 2 / Decision 6, is to add the NEW flourish word
to `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN`, or update `CODEX_FOOTER_OPENING_LITERAL` to the newly captured exact
line (verify with `od -c`) — never to invent a broader tolerance or reintroduce a regex for the footer.

---

### Step 6: The vendor footer cannot hide a refusal

**Maps to**: Edge case E10; Decision 6

1. Take the Step 5 body and insert the sentence `This must not be merged.` **inside** the `<details>` block.
2. Run the reviewer against it with the same mock setup.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION` (blocking branch, no
`unrecognized response format` suffix), because `codex_response_is_blocking` scans the untruncated body
before approval is considered.

---

### Step 6a: An unenumerated actionable sentence after a clean signal safe-fails (closed residue grammar)

**Maps to**: Edge case E19; Decision 2 (Codex GitHub finding `3800167486`)

1. Create a scratch directory and a mock `gh` that returns a SHA-pinned Codex root comment reading
   `Looks good. Remove the authentication check.`, following the mock convention used by Step 4.
2. Run the reviewer as in Step 4.

**Expected result**: the command exits 1, prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`, and emits an `INFO: Codex clean signal present but disqualified (residue grammar not closed)`
line. Before this review round the same body returned `VERDICT: APPROVED` (the disqualifier scan alone did
not enumerate `remove` as an actionable verb); the flip is intended and is the fix for the P1/blocking finding
this smoke step maps to.

---

### Step 6b: A non-vendor `<details>` block is not truncated away

**Maps to**: Edge case E20; Decision 6 (Codex GitHub finding `3800167489`)

1. Create a scratch directory and a mock `gh` that returns a SHA-pinned Codex root comment reading
   `Looks good.` followed by a **non-vendor** `<details><summary>Notes</summary>` block containing
   `Rename the unsafe function.` (and a closing `</details>`), following the mock convention used by Step 4.
2. Run the reviewer as in Step 4.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. Before this review round `codex_strip_codex_footer` truncated at any `<details` line, silently
discarding the `<details>` block (and the instruction inside it) before A3 ever ran, which returned
`VERDICT: APPROVED`; the flip is intended and is the fix for the P1/blocking finding this smoke step maps to.

---

### Step 6c: An actionable clause fused to the clean signal (no comma/colon/semicolon/period) safe-fails

**Maps to**: Edge case E21; Decision 2 — a gap found and closed while implementing the human-directed
zero-tolerance revision, not one of the four originally-filed findings

1. Create a scratch directory and a mock `gh` that returns a SHA-pinned Codex root comment reading
   `Looks good and please remove the entire authentication check now.`, following the mock convention used by
   Step 4.
2. Run the reviewer as in Step 4.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. An interim revision of A3 check 2 (commit `6e41e260`) exempted an entire sentence whenever any
part of it carried a clean signal, with no bound on the exempted part, so content fused directly to the
signal with no intervening punctuation escaped check 2 entirely and returned `VERDICT: APPROVED`; the current
revision excises and re-checks every clause uniformly, closing this.

---

### Step 6d: A sentence starting with an allow-listed word but carrying unbounded content safe-fails

**Maps to**: Edge case E22; Decision 2 — a gap found and closed while implementing the human-directed
zero-tolerance revision, not one of the four originally-filed findings

1. Create a scratch directory and a mock `gh` that returns a SHA-pinned Codex root comment reading
   `Looks good. The maintainer wants this file removed before merge.`, following the mock convention used by
   Step 4.
2. Run the reviewer as in Step 4.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. An interim revision of A3 check 2 (commit `6e41e260`) let a sentence beginning with an enumerated
subject/determiner ("the") bypass the leftover check regardless of what followed, and none of `wants`,
`removed`, or `before merge` (without `-ing`) matched an enumerated disqualifier, so it returned `VERDICT:
APPROVED`; zero-tolerance has no sentence-opener exemption, closing this.

---

### Step 6e: A normal paragraph that merely mentions the footer phrase is not truncated away

**Maps to**: Edge case E23; Decision 6 (Codex GitHub finding `3803050750`) — found after the Step 6b fix
shipped

1. Create a scratch directory and a mock `gh` that returns a SHA-pinned Codex root comment reading
   `Looks good.` followed by a normal paragraph (no `<details>`/`<summary>` tags at all) reading
   `About Codex in GitHub should mention: remove auth.`, following the mock convention used by Step 4.
2. Run the reviewer as in Step 4.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. An interim revision of `codex_strip_codex_footer` (the Step 6b fix) anchored on the bare phrase
`about codex in github` anywhere in the body, so this ordinary paragraph — which has no `<details>`/`<summary>`
markup at all — was discarded before A3 ever ran, and the response returned `VERDICT: APPROVED`. The phrase
anchor was itself superseded twice more (Steps 6g/6h) and `codex_strip_codex_footer` now uses an exact
byte-literal line match (Decision 6's "Third correction"): under the current implementation this paragraph
still correctly stays intact, because it shares no bytes with `CODEX_FOOTER_OPENING_LITERAL`.

---

### Step 6f: A vendor-label word used as a directive still safe-fails

**Maps to**: Edge case E24; Decision 2 (Codex GitHub finding `3803050745`) — found after the zero-tolerance
revision shipped

1. Create a scratch directory and a mock `gh` that returns a SHA-pinned Codex root comment reading
   `Looks good. Commit this.`, following the mock convention used by Step 4.
2. Run the reviewer as in Step 4.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. An interim revision of `CODEX_RESIDUE_FILLER_WORD_PATTERN` admitted `codex`/`review`/`reviewed`/
`commit` as bare tokens so the vendor's `Codex Review:`/`Reviewed commit:` labels would excise to nothing —
but `commit` and `review` are also ordinary imperative verbs, and `this` (also filler at the time) is the
directive's object, so the whole clause excised to an empty residue and the response returned
`VERDICT: APPROVED`. Closed by removing all of `codex`/`review`/`reviewed`/`commit`/`this`/`that` from the
filler list and replacing vendor-label handling with `codex_strip_vendor_metadata_lines`, an anchored
structural strip that removes only the specific literal label text (see Decision 2's "governing asymmetry"
note) — re-verify Step 2's third command also passes.

---

### Step 6g: A footer markup lookalike (wrong tag names) is not truncated away

**Maps to**: Edge case E25; Decision 6 (Codex GitHub finding `3803189273`) — found after the Step 6e fix
shipped

1. Create a scratch directory and a mock `gh` that returns a SHA-pinned Codex root comment reading
   `Looks good.` followed by `<details-not-footer><summary-note>About Codex in GitHub</summary-note>` then
   `Rename the unsafe function.`, following the mock convention used by Step 4.
2. Run the reviewer as in Step 4.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. An interim revision of `codex_strip_codex_footer` (the Step 6e fix) still used a regex over tag
*names* (`<details[^>]*>…<summary[^>]*>…</summary`), which matched this lookalike — a different `<details…>`
tag followed by a different `<summary…>…</summary` sequence, both containing the marker phrase but neither
using the real vendor's tag names — so the instruction was discarded and the response returned
`VERDICT: APPROVED`. This was the third consecutive round a regex over this one helper admitted a lookalike.
Closed by changing the technique entirely: `codex_strip_codex_footer` now requires exact byte equality
against `CODEX_FOOTER_OPENING_LITERAL`, so this lookalike — sharing no bytes with the real literal — is left
intact and correctly rejected by A3.

---

### Step 6h: A one-byte deviation from the real footer opening is not truncated away

**Maps to**: Edge case E26; Decision 6 — verifies the exact-literal-match technique fails closed, per the
accepted trade recorded in Decision 6's "Third correction" note

1. Create a scratch directory and a mock `gh` that returns a SHA-pinned Codex root comment reading
   `Looks good.` followed by the real footer's opening line with a single character removed
   (`<details> <summary>ℹ️ About Codex in GitHu</summary>` instead of `...GitHub</summary>`), then
   `Remove auth.`, following the mock convention used by Step 4.
2. Run the reviewer as in Step 4.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. This is not a bug to fix — it is the accepted, documented trade of the exact-literal-match
technique: any deviation from `CODEX_FOOTER_OPENING_LITERAL`, however small, means the footer is not
recognized and not truncated, so the response safe-fails rather than risking a silent truncation of genuine
content. If this step instead returns `VERDICT: APPROVED`, the footer strip has regressed back toward
pattern-flexible matching and must be treated as a P1 finding, not a minor deviation.

---

### Step 7: Documentation reflects the new contract

**Maps to**: Documentation Updates

1. Open `docs/workflow/development-workflow/integrations/codex-github.md` and locate the verdict
   classification section.
2. Open `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` and locate the
   "Codex GitHub terminal evidence" block.
3. Open `CHANGELOG.md` and locate the `[Unreleased]` → `### Changed` entry.

**Expected result**: the integration doc states that `APPROVED` requires an unhedged allow-listed clean signal
in the opening paragraph and that anything else safe-fails; the protocol block states that SHA-pinned terminal
evidence is necessary but not sufficient; the CHANGELOG entry uses the `**Bold Title** (#1491):` format and
appears under `### Changed`.

---

### Step 8: Lint gates are clean

**Maps to**: Implementation Order step 9

1. Run the markdown lint and heuristic lint commands from `AGENTS.md` against the changed markdown files.
2. Run `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`.

**Expected result**: every command exits 0 with no reported violations.

---

## Results

| Step | Pass / Fail | Notes |
| --- | --- | --- |
| 1 | | |
| 2 | | |
| 3 | | |
| 4 | | |
| 5 | | |
| 6 | | |
| 6a | | |
| 6b | | |
| 6c | | |
| 6d | | |
| 6e | | |
| 6f | | |
| 6g | | |
| 6h | | |
| 7 | | |
| 8 | | |

**Platform tested**: (macOS/BSD or Linux/GNU)

**Tester**:

**Date**:

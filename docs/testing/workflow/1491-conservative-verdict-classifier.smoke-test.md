# Smoke Test Runbook: Conservative Verdict Classifier

**Feature**: Exact-template verdict classifier for `codex-github-reviewer.sh` (Issue #1491)
**Spec**: None — Refactor path. Work item brief: [Issue #1491](https://github.com/lhpaul/ai-dev-framework-template/issues/1491)
**Implementation plan**: [`docs/specs/developments/20260817203204_1491-conservative-verdict-classifier/2_1491-conservative-verdict-classifier_implementation-plan.md`](../../specs/developments/20260817203204_1491-conservative-verdict-classifier/2_1491-conservative-verdict-classifier_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch for issue #1491 is checked out
- [ ] `bash`, `grep`, `sed`, `awk`, `tr`, `jq`, and `gh` are available on `PATH`
- [ ] `gh auth status` succeeds (needed for Steps 5 and 6)
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
| Real clean Codex root comment source | PR #1489 in `lhpaul/ai-dev-framework-template` |
| Real Codex review-wrapper source (no clean signal) | PR #1490 in `lhpaul/ai-dev-framework-template` (any of its 12 reviews) |
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
compared against the "Reconciled test-disposition counts" table in the implementation plan (that table's
figure is explicitly provisional — report the real count here).

---

### Step 2: Every obsoleted symbol is actually gone, and only the final design's symbols remain

**Maps to**: Implementation Order steps 2–5

1. Run:

   ```bash
   grep -nE "CODEX_NEGATED_APPROVAL|CODEX_APPROVAL_PATTERN|CODEX_CLEAN_SIGNAL|CODEX_APPROVAL_(NEGATION|HEDGE|ACTIONABLE|DISQUALIFIER)|CODEX_RESIDUE_FILLER|CODEX_RESIDUE_STARTER|CODEX_VENDOR_FLAVOR|codex_excise_clean_signals|codex_residue_is_closed_grammar|codex_response_first_paragraph|codex_strip_vendor_metadata_lines|not_only" \
     scripts/development-workflow/codex-github-reviewer.sh
   ```

2. Run:

   ```bash
   grep -n "CODEX_FOOTER_OPENING_LITERAL\|CODEX_APPROVED_TEMPLATES\|codex_strip_codex_footer\|codex_normalize_whitespace" \
     scripts/development-workflow/codex-github-reviewer.sh
   ```

3. Run, to confirm `codex_response_is_approved` itself contains no leftover reference to a deleted symbol or
   mechanism:

   ```bash
   grep -n "codex_response_is_approved" -A 15 scripts/development-workflow/codex-github-reviewer.sh
   ```

**Expected result**: the first command prints nothing — every symbol this plan's four prior revisions ever
introduced or targeted for deletion is gone, with no dormant leftovers. The second command prints at least one
definition line for each of the four symbols the final design actually ships. The third command's output
shows `codex_response_is_approved` calling only `codex_strip_codex_footer`, `codex_normalize_whitespace`, and
a loop over `CODEX_APPROVED_TEMPLATES` — no fence-marker check, no quote-stripping call, and no reference to
any of the symbols the first command searched for.

---

### Step 3: The blocking classifier is untouched

**Maps to**: Decision 4

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
their values. The only diff touching `codex_response_is_blocking` is the removed `codex_strip_not_only_idiom`
call (the function itself is deleted this round, not just its call sites — confirm via Step 2's first command).

---

### Step 4: A response that is not, character-for-character, an evidenced template safe-fails

**Maps to**: Group RETARGETED and Group UNCHANGED-NEEDS_REVISION in Test disposition; Operational cost section

1. Create a scratch directory and a mock `gh` that returns a SHA-pinned Codex root comment reading
   `No blocking issues found.`, following the mock convention used by the neighbouring scenarios in the
   harness (auth status, `pr view … headRefOid`, empty reviews and inline comments, and the comment payload).
2. Run the reviewer with a short poll budget:

   ```bash
   PATH="$SCRATCH:$PATH" scripts/development-workflow/codex-github-reviewer.sh \
     42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0
   ```

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. No stderr diagnostic line is emitted (the final design does not emit one — see Code Samples).
Before every revision of this plan prior to this round, a body reading `No blocking issues found.` returned
`VERDICT: APPROVED`; under the final design it never can, because that wording is not one of the currently
evidenced templates (Decision 2). This is the single most important behavioral fact to internalize about this
revision: this is now true of nearly every wording that would have previously approved.

---

### Step 5: The real vendor clean response still approves, end to end

**Maps to**: Edge case E1; residual verification evidence item 3 — this is the highest-impact check in the
runbook

1. Capture the current real clean-response body:

   ```bash
   gh api repos/lhpaul/ai-dev-framework-template/issues/1489/comments \
     --jq '.[] | select(.user.login | test("codex"; "i")) | .body'
   ```

2. Confirm it still reads, verbatim: `Codex Review: Didn't find any major issues. Swish!`, followed by a
   `**Reviewed commit:**` marker with a lowercase-hex SHA, followed by the `<details> <summary>ℹ️ About Codex
   in GitHub</summary>` footer. **If any of these three components has changed even slightly** (different
   flavor word, different marker format, different footer opening), stop and report it — do not proceed to
   step 3 assuming the existing `CODEX_APPROVED_TEMPLATES` entry still applies.
3. Build a mock `gh` that serves that exact body as a SHA-pinned root comment and run the reviewer as in
   Step 4.

**Expected result**: the command exits 0 and prints `VERDICT: APPROVED`. If it instead exits 1, this is a
total operational failure of the ready phase (the classifier rejects the one response it exists to accept) —
stop and report it. The correct fix, per Decision 2, is to re-capture the live body and add or update the
`CODEX_APPROVED_TEMPLATES` entry with evidence, never to loosen the matching technique (no case-insensitivity,
no optional clauses, no wildcard placeholders beyond the existing bounded SHA field).

---

### Step 6: The real review-wrapper body (no clean signal) is not misclassified

**Maps to**: Edge case E2

1. Capture a real review body from PR #1490 (any of its 12 reviews):

   ```bash
   gh api repos/lhpaul/ai-dev-framework-template/pulls/1490/reviews \
     --jq '.[] | select(.user.login | test("codex"; "i")) | .body' | head -1
   ```

2. Confirm it reads the generic `### 💡 Codex Review\n\nHere are some automated review suggestions for this
   pull request.` wrapper, with **no** clean-signal wording in its visible text.
3. Build a mock `gh` that serves that body via the review endpoint (not the root-comment endpoint) with
   `state: COMMENTED`, and run the reviewer as in Step 4.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. This body was never eligible to become a template (Decision 2) — its verdict is unaffected by
this revision, exactly as it was unaffected by every prior revision.

---

### Step 7: The vendor footer cannot hide a refusal from the composed verdict

**Maps to**: Edge case E22; Decision 3/4

1. Take the Step 5 body and insert the sentence `This must not be merged.` **inside** the `<details>` block.
2. Run the reviewer against it with the same mock setup.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION` (blocking branch, no
`unrecognized response format` suffix), because `codex_response_is_blocking` (unchanged) scans the untruncated
body before approval is considered at every verdict site. Note that `codex_response_is_approved` **alone**
would return `APPROVED` for this exact body (the footer, refusal included, is stripped before matching) — it
is specifically the composition with `codex_response_is_blocking` that produces the correct final verdict.

---

### Step 8: The round-5 exploit that triggered this design replacement is closed

**Maps to**: Edge case E21; Decision 2 (Codex GitHub finding `3803306915`)

1. Create a scratch directory and a mock `gh` that returns a SHA-pinned Codex root comment reading
   `Looks good, or is it?`, following the mock convention used by Step 4.
2. Run the reviewer as in Step 4.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. The prior (residue-grammar) revision of this plan returned `VERDICT: APPROVED` for this body: `or`,
`is`, and `it` were all closed-class filler words the grammar treated as inert, so the residue reduced to
nothing even though the sentence, read as a whole, is a hedge that negates the clean signal. The final design
closes this — and the entire class of construction it represents — trivially: this body is simply not a
reproduction of any evidenced template.

---

### Step 9: The SHA placeholder generalizes within its bound and rejects outside it

**Maps to**: Edge cases E4–E8

1. Using the mock convention from Step 4, run the reviewer four times against the Step 5 template with the
   `Reviewed commit:` SHA replaced, in turn, by: (a) a different 10-character valid hex SHA than the one
   captured live, (b) a 6-character hex SHA, (c) a 41-character hex SHA, and (d) a non-hex string such as
   `not-a-sha!`.

**Expected result**: (a) exits 0, `VERDICT: APPROVED` — confirms the placeholder is not hardcoded to the one
captured value. (b), (c), and (d) all exit 1, `VERDICT: NEEDS_REVISION` — confirms the `{7,40}` bound (git's
documented abbreviated-to-full SHA-1 hex-length range, per Decision 2) is enforced, not merely documented.

---

### Step 10: Documentation reflects the new contract

**Maps to**: Documentation Updates

1. Open `docs/workflow/development-workflow/integrations/codex-github.md` and locate the verdict
   classification section.
2. Open `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` and locate the
   "Codex GitHub terminal evidence" block.
3. Open `CHANGELOG.md` and locate the `[Unreleased]` → `### Changed` entry.

**Expected result**: the integration doc states that `APPROVED` requires an exact, whitespace-normalized match
against a captured clean-response template — no vocabulary list, no grammar, no case-insensitive or
punctuation-tolerant matching — and names the one currently-evidenced template's shape; the protocol block
states that the response must reproduce an evidenced template, not merely carry an "unhedged clean signal"
(the phrase an earlier revision of this plan used); the CHANGELOG entry uses the `**Bold Title** (#1491):`
format, appears under `### Changed`, and describes the exact-template design (not the allow-list or
closed-grammar design an earlier revision of this plan shipped there).

---

### Step 11: Lint gates are clean

**Maps to**: Implementation Order step 8

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
| 7 | | |
| 8 | | |
| 9 | | |
| 10 | | |
| 11 | | |

**Platform tested**: (macOS/BSD or Linux/GNU)

**Tester**:

**Date**:

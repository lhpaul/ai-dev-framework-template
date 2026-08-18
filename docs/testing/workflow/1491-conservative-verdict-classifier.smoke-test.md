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
   grep -nE "CODEX_NEGATED_APPROVAL|CODEX_APPROVAL_PATTERN|CODEX_CLEAN_SIGNAL|CODEX_APPROVAL_(NEGATION|HEDGE|ACTIONABLE|DISQUALIFIER)|CODEX_RESIDUE_FILLER|CODEX_RESIDUE_STARTER|CODEX_VENDOR_FLAVOR|codex_excise_clean_signals|codex_residue_is_closed_grammar|codex_response_first_paragraph|codex_strip_vendor_metadata_lines|CODEX_FOOTER_OPENING_LITERAL|codex_strip_codex_footer|not_only" \
     scripts/development-workflow/codex-github-reviewer.sh
   ```

2. Run:

   ```bash
   grep -n "CODEX_APPROVED_TEMPLATES\|codex_normalize_whitespace" \
     scripts/development-workflow/codex-github-reviewer.sh
   ```

3. Run, to confirm `codex_response_is_approved` itself contains no leftover reference to a deleted symbol or
   mechanism (in particular, no footer-strip call and no `visible` intermediate variable):

   ```bash
   grep -n "codex_response_is_approved" -A 15 scripts/development-workflow/codex-github-reviewer.sh
   ```

**Expected result**: the first command prints nothing — every symbol this plan's five prior revisions ever
introduced or targeted for deletion is gone, with no dormant leftovers. This includes `CODEX_FOOTER_OPENING_LITERAL`
and `codex_strip_codex_footer`, which this round moves from "keep unchanged" to "delete" (Decision 5) — if
either still appears anywhere in the file, this step fails even if every other symbol is gone. The second
command prints at least one definition line for each of the two symbols the final design actually ships. The
third command's output shows `codex_response_is_approved` normalizing whitespace on `$body` directly and
looping over `CODEX_APPROVED_TEMPLATES` — no footer-strip call, no fence-marker check, no quote-stripping call,
and no reference to any of the symbols the first command searched for.

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
Before the exact-template-matching designs of this plan, a body reading `No blocking issues found.` returned
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
   `**Reviewed commit:**` marker with a lowercase-hex SHA, followed by the **complete** `<details> <summary>ℹ️
   About Codex in GitHub</summary>…</details>` footer — not just its opening line. Compare the **entire** footer
   text (bulleted list, settings link, acknowledgement sentence, through the closing `</details>`) against the
   literal baked into `CODEX_APPROVED_TEMPLATES`, not only the opening line. **If any of these components has
   changed even slightly, anywhere in the body including the footer** (different flavor word, different marker
   format, different footer wording anywhere in its text), stop and report it — do not proceed to step 3
   assuming the existing `CODEX_APPROVED_TEMPLATES` entry still applies. This is a stricter check than a prior
   revision of this runbook required, because the footer is now part of the literal being matched, not
   discarded before comparison.
3. Build a mock `gh` that serves that exact body as a SHA-pinned root comment and run the reviewer as in
   Step 4.

**Expected result**: the command exits 0 and prints `VERDICT: APPROVED`. If it instead exits 1, this is a
total operational failure of the ready phase (the classifier rejects the one response it exists to accept) —
stop and report it. The correct fix, per Decision 2, is to re-capture the live body (complete footer included)
and add or update the `CODEX_APPROVED_TEMPLATES` entry with evidence, never to loosen the matching technique
(no case-insensitivity, no optional clauses, no wildcard placeholders beyond the existing bounded SHA field,
and no reintroduction of a truncation step to avoid having to capture the footer).

---

### Step 6: The real review-wrapper body (no clean signal) is not misclassified

**Maps to**: Edge case E2

1. Capture a real review body from PR #1490 (any of its 12 reviews). **Select the first matching review
   inside the jq expression itself, not by piping the emitted bodies through `head -1`** — `head -1` on
   multi-line output stops at the first *line*, not the first *review*, so it would truncate the body to a
   partial `### 💡 Codex Review` header fragment rather than yielding one complete review body (Codex GitHub
   finding `3803807963`, round 7):

   ```bash
   gh api repos/lhpaul/ai-dev-framework-template/pulls/1490/reviews \
     --jq '[.[] | select(.user.login | test("codex"; "i"))][0].body'
   ```

2. Confirm it reads the generic `### 💡 Codex Review\n\nHere are some automated review suggestions for this
   pull request.` wrapper, with **no** clean-signal wording in its visible text.
3. Build a mock `gh` that serves that body via the review endpoint (not the root-comment endpoint) with
   `state: COMMENTED`, and run the reviewer as in Step 4.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. This body was never eligible to become a template (Decision 2) — its verdict is unaffected by
this revision, exactly as it was unaffected by every prior revision.

---

### Step 7: A refusal inserted inside the footer is rejected by `is_approved` alone — `is_blocking` upgrades verdict specificity, but is no longer load-bearing for safety here

**Maps to**: Edge case E22 (rewritten this round); Decision 4/5

**This step's expected result changed this round.** Under the prior (truncate-then-match) revision,
`codex_response_is_approved` **alone** returned `APPROVED` for this body, and only `codex_response_is_blocking`
prevented the composed verdict from being wrong. Under this revision, `is_approved` alone already rejects it.

1. Take the Step 5 body and insert the sentence `This must not be merged.` **inside** the `<details>` block
   (e.g. immediately after `</summary>`).
2. Run the reviewer against it with the same mock setup.
3. **Additionally**, call `codex_response_is_approved` directly (source the script or extract the function) on
   just this body, in isolation from `codex_response_is_blocking`, and confirm its own exit code.

**Expected result**: the full reviewer run in step 2 exits 1 and prints `VERDICT: NEEDS_REVISION` (blocking
branch, no `unrecognized response format` suffix), because `codex_response_is_blocking` (unchanged) recognizes
`must not be merged` and still runs before approval is considered at every verdict site (Decision 3). **The
isolated check in step 3 must also return non-zero (`NEEDS_REVISION`) from `codex_response_is_approved` alone**
— this is the behavioral difference from the prior revision's version of this step, and it is the direct
consequence of removing footer truncation: there is no truncation point left for the inserted sentence to hide
behind, so the whole-body exact match already rejects this body on its own, with no help from `is_blocking`
needed. If step 3 shows `is_approved` alone still returning `APPROVED` for this body, that is a regression to
the prior (truncate-then-match) behavior and Codex GitHub finding `3803545669`'s underlying gap has reopened —
stop and report it immediately, this is the single highest-priority regression this runbook checks for.

---

### Step 8: The round-6 exploit (Codex GitHub finding `3803545669`) is closed — footer-opening-line-only plus trailing content is rejected

**Maps to**: Edge case E23; Decision 1/2/5 (Codex GitHub finding `3803545669`) — **this is the direct
regression test for the finding that motivated this revision; treat a failure here as the highest-priority
result in this runbook**

1. Take the Step 5 template's verdict sentence and `**Reviewed commit:**` line, append **only** the footer's
   opening line (`<details> <summary>ℹ️ About Codex in GitHub</summary>`, not the rest of the footer), then
   append a new paragraph reading `Rename the unsafe function.`
2. Build a mock `gh` that serves this exact body as a SHA-pinned root comment and run the reviewer as in
   Step 4.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. Under the immediately prior revision of this plan, this exact construction reproduced the
*visible* (pre-truncation) template exactly and was classified `APPROVED`, because the footer's opening line
satisfied the truncation trigger and everything after it — including `Rename the unsafe function.` — was
discarded unread. Under this revision there is no truncation trigger: the required literal is the **complete**
footer text, and a body carrying only its opening line does not reproduce it, so the match fails independent
of what follows. If this step returns `APPROVED`, the round-6 finding has reopened — stop and report it
immediately.

---

### Step 9: A one-byte mutation anywhere inside the footer — not only its opening line — is rejected

**Maps to**: Edge case E24

1. Take the Step 5 body (complete real footer included) and, in three separate runs, mutate exactly one byte
   at each of these positions: (a) mid-footer-sentence (e.g. `react with` → `react With`), (b) immediately
   before the closing `</details>` (e.g. the word preceding it), and (c) inside the `chatgpt.com` settings URL.
2. Build a mock `gh` that serves each mutated body as a SHA-pinned root comment and run the reviewer as in
   Step 4, once per mutation.

**Expected result**: all three runs exit 1 and print `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. This confirms the entire footer text is load-bearing for the match, not merely its opening line —
a property the prior (truncate-then-match) revision never needed and never tested, since only the opening line
was ever compared against anything under that design.

---

### Step 10: The round-5 exploit that triggered the prior design replacement is still closed

**Maps to**: Edge case E21; Decision 2 (Codex GitHub finding `3803306915`)

1. Create a scratch directory and a mock `gh` that returns a SHA-pinned Codex root comment reading
   `Looks good, or is it?`, following the mock convention used by Step 4.
2. Run the reviewer as in Step 4.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. An earlier (residue-grammar) revision of this plan returned `VERDICT: APPROVED` for this body:
`or`, `is`, and `it` were all closed-class filler words the grammar treated as inert, so the residue reduced to
nothing even though the sentence, read as a whole, is a hedge that negates the clean signal. The final design
closes this — and the entire class of construction it represents — trivially: this body is simply not a
reproduction of any evidenced template.

---

### Step 11: The SHA placeholder generalizes within its bound and rejects outside it

**Maps to**: Edge cases E4–E8

1. Using the mock convention from Step 4, run the reviewer four times against the Step 5 template (complete
   real footer appended) with the `Reviewed commit:` SHA replaced, in turn, by: (a) a different 10-character
   valid hex SHA than the one captured live, (b) a 6-character hex SHA, (c) a 41-character hex SHA, and (d) a
   non-hex string such as `not-a-sha!`.

**Expected result**: (a) exits 0, `VERDICT: APPROVED` — confirms the placeholder is not hardcoded to the one
captured value. (b), (c), and (d) all exit 1, `VERDICT: NEEDS_REVISION` — confirms the `{7,40}` bound (git's
documented abbreviated-to-full SHA-1 hex-length range, per Decision 2) is enforced, not merely documented.
Every one of these four bodies must include the complete real footer — a body missing the footer would return
`NEEDS_REVISION` for the wrong reason (missing footer, not the SHA bound), confounding this step's result.

---

### Step 12: Documentation reflects the new contract

**Maps to**: Documentation Updates

1. Open `docs/workflow/development-workflow/integrations/codex-github.md` and locate the verdict
   classification section.
2. Open `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` and locate the
   "Codex GitHub terminal evidence" block.
3. Open `CHANGELOG.md` and locate the `[Unreleased]` → `### Changed` entry.

**Expected result**: the integration doc states that `APPROVED` requires an exact, whitespace-normalized match
against the **entire, untruncated** body (footer included, no truncation step) — no vocabulary list, no
grammar, no case-insensitive or punctuation-tolerant matching — and names the one currently-evidenced
template's shape; the protocol block states that the response must reproduce an evidenced template covering
the whole body, not merely carry an "unhedged clean signal" (the phrase an earlier revision of this plan
used); the CHANGELOG entry uses the `**Bold Title** (#1491):` format, appears under `### Changed`, and
describes the whole-body, no-truncation design (not the allow-list, closed-grammar, or truncate-then-match
design an earlier revision of this plan shipped there).

---

### Step 13: Lint gates are clean

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
| 12 | | |
| 13 | | |

**Platform tested**: (macOS/BSD or Linux/GNU)

**Tester**:

**Date**:

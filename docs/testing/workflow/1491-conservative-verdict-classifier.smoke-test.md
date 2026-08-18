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
- [ ] `gh auth status` succeeds (needed for Steps 6 and 7)
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

**Maps to**: Implementation Order steps 2–4 (corrected this round — step 5 is now the acknowledgement-branch
gate, Decision 6, a separate concern from symbol deletion; see the new step below covering it)

1. Run — **corrected this round (Codex GitHub finding `3804088454`, round 9): the unfiltered form is unsound.**
   `codex_response_is_blocking`'s own unchanged rationale comment names `CODEX_NEGATED_APPROVAL_PATTERN` three
   times, `codex_strip_quoted_spans`'s comment names `CODEX_APPROVAL_PATTERN`/`CODEX_NEGATED_APPROVAL_PATTERN`
   once each, and `CODEX_BLOCKING_PATTERN`'s own comment names `CODEX_NEGATED_APPROVAL_PATTERN` twice more — all
   in functions this plan keeps unchanged. Run today, before implementation (`CODEX_APPROVAL_PATTERN` added to
   the search set — an earlier revision of this runbook omitted it even though it is on the deletion list):

   ```bash
   grep -nE "CODEX_APPROVAL_PATTERN|CODEX_NEGATED_APPROVAL|CODEX_CLEAN_SIGNAL|CODEX_APPROVAL_(NEGATION|HEDGE|ACTIONABLE|DISQUALIFIER)|CODEX_RESIDUE_FILLER|CODEX_RESIDUE_STARTER|CODEX_VENDOR_FLAVOR|codex_excise_clean_signals|codex_residue_is_closed_grammar|codex_response_first_paragraph|codex_strip_vendor_metadata_lines|CODEX_FOOTER_OPENING_LITERAL|codex_strip_codex_footer" \
     scripts/development-workflow/codex-github-reviewer.sh
   ```

   → **13** matches today (8 of them comment mentions in functions this plan does not touch; 5 the real code
   being deleted). Comment-filtered:

   ```bash
   grep -v '^[[:space:]]*#' scripts/development-workflow/codex-github-reviewer.sh \
     | grep -nE "CODEX_APPROVAL_PATTERN|CODEX_NEGATED_APPROVAL|CODEX_CLEAN_SIGNAL|CODEX_APPROVAL_(NEGATION|HEDGE|ACTIONABLE|DISQUALIFIER)|CODEX_RESIDUE_FILLER|CODEX_RESIDUE_STARTER|CODEX_VENDOR_FLAVOR|codex_excise_clean_signals|codex_residue_is_closed_grammar|codex_response_first_paragraph|codex_strip_vendor_metadata_lines|CODEX_FOOTER_OPENING_LITERAL|codex_strip_codex_footer"
   ```

   → **5** matches today, all real code (the `CODEX_APPROVAL_PATTERN`/`CODEX_NEGATED_APPROVAL_PATTERN`/
   `CODEX_NEGATED_APPROVAL_TARGET_WORDS` definitions and their two call sites inside the old
   `codex_response_is_approved`). **Use the comment-filtered form as the pass/fail gate** — it must return
   nothing after a correct implementation. The raw form will still show 8 surviving comment lines after a
   correct implementation and must not be used as the gate.

   `codex_strip_not_only_idiom`/`not_only` is deliberately excluded from this search — see Step 3 below. An
   earlier revision of this runbook included it here, which is wrong: the function and its call inside
   `codex_response_is_blocking` are kept (Codex GitHub finding `3803959040`, round 8); only its call inside the
   old `codex_response_is_approved` is gone, as a byproduct of that function's full replacement, not a listed
   deletion.

2. Run:

   ```bash
   grep -n "CODEX_APPROVED_TEMPLATES\|codex_normalize_whitespace" \
     scripts/development-workflow/codex-github-reviewer.sh
   ```

3. Run, to confirm `codex_response_is_approved` itself contains no leftover reference to a deleted symbol or
   mechanism (in particular, no footer-strip call, no `visible` intermediate variable, and no
   `codex_strip_not_only_idiom` call — that call belongs only to `codex_response_is_blocking` now):

   ```bash
   grep -n "codex_response_is_approved" -A 15 scripts/development-workflow/codex-github-reviewer.sh
   ```

4. **Corrected/new this round (Codex GitHub finding `3804395363`, round 10)**: confirm every stale
   approval-path comment named in Implementation Order step 6 was actually rewritten, not just the two Codex
   named:

   ```bash
   grep -c "codex_response_is_approved" scripts/development-workflow/codex-github-reviewer.sh
   grep -n "codex_response_is_approved" scripts/development-workflow/codex-github-reviewer.sh
   ```

**Expected result**: the comment-filtered form of the first command prints nothing — every symbol this plan's
five prior revisions ever introduced or targeted for deletion is gone from the executable code, with no
dormant leftovers. This includes `CODEX_FOOTER_OPENING_LITERAL` and `codex_strip_codex_footer`, which round 6
moved from "keep unchanged" to "delete" (Decision 5) — if either still appears in the executable code anywhere
in the file, this step fails even if every other symbol is gone. The second command prints at least one
definition line for each of the two symbols the final design actually ships. The third command's output shows
`codex_response_is_approved` normalizing whitespace on `$body` directly and looping over
`CODEX_APPROVED_TEMPLATES` — no footer-strip call, no fence-marker check, no quote-stripping call, no
`codex_strip_not_only_idiom` call, and no executable reference to any of the symbols the first command
searched for (comments describing the plan's own history, in functions this plan does not touch, are expected
and are not a failure). **Corrected this round (Codex GitHub finding `3804535205`, round 11): the fourth
command's count must be 8 after a correct implementation, not 11.** 11 is the count *before* this step's own
edits are applied (5 comment mentions, 1 definition line, 5 real call sites); this step's own work removes the
comment at line 390 entirely (inside the deleted `CODEX_NEGATED_APPROVAL_PATTERN` block) and removes
`codex_response_is_approved` from the text at lines 488 and 643 — three fewer mentions, 11 − 3 = **8** (2
comment mentions at lines 258/263, 1 definition line, 5 real call sites). A result of 11 after implementation
means this step's own edits were not applied; a result of 8 is correct. Its output must also show no comment
claiming `codex_response_has_fence_marker`, `codex_strip_quoted_spans`, or `codex_strip_not_only_idiom` is
"used by" `codex_response_is_approved` — per Implementation Order step 6's six named locations (lines 33–45,
~1439–1461, ~246–247, ~535–537, 488, 643–644 as they exist before this step). If any of those six still
describes `codex_response_is_approved` as stripping quotes, checking fences, or calling the not-only idiom,
this step fails even if Step 2's commands 1–3 above all pass.

---

### Step 3: `codex_strip_not_only_idiom` is kept, with exactly one call site — inside `codex_response_is_blocking`

**Maps to**: Decision 4 (corrected round 8, Codex GitHub finding `3803959040`)

1. Run — **corrected this round (Codex GitHub finding `3804088454`, round 9): a bare `grep -c` counts comment
   lines too.** `codex_response_is_blocking`'s own rationale comment names `codex_strip_not_only_idiom` twice.
   Run both forms today (pre-implementation, both call sites still present):

   ```bash
   grep -c "codex_strip_not_only_idiom" scripts/development-workflow/codex-github-reviewer.sh
   ```

   → **5** (2 comments + 1 definition + 2 calls).

   ```bash
   grep -v '^[[:space:]]*#' scripts/development-workflow/codex-github-reviewer.sh \
     | grep -c "codex_strip_not_only_idiom"
   ```

   → **3** (1 definition + 2 calls).

2. Run, to confirm which function the one remaining call lives inside:

   ```bash
   grep -n "codex_response_is_blocking\|codex_strip_not_only_idiom" scripts/development-workflow/codex-github-reviewer.sh
   ```

**Expected result**: **use the comment-filtered count (step 1's second command) as the pass/fail gate.** It
must return exactly **2** after a correct implementation (the function definition, plus its one remaining
call) — not 0, and not 3. If it returns 0, the function was wrongly deleted entirely — a direct regression of
Codex GitHub finding `3803959040` (a genuinely clean response containing "not only … merge" in one clause, e.g.
`This is not only safe to merge but looks good.`, will be misclassified as a merge refusal). If it returns 3,
the old `is_approved`-side call was wrongly left in place. **Do not use the raw (unfiltered) count as the
gate** — it must read **4** after a correct implementation (2 comments + 1 definition + 1 call), not 2, because
of the two comment mentions named above. The second command's output shows the one remaining call appearing
inside `codex_response_is_blocking`'s function body, not inside `codex_response_is_approved`'s.

---

### Step 4: The blocking classifier is untouched — zero diff, not merely an unchanged pattern definition

**Maps to**: Decision 4

**Corrected in round 8 (Codex GitHub finding `3803959040`):** an earlier revision expected a diff here (the
removed `codex_strip_not_only_idiom` call); the call is retained, so there must be **no** functional change to
`codex_response_is_blocking` at all. **Corrected again this round (Codex GitHub finding `3804088461`, round
9): a `grep` over a `git diff` cannot establish "this function is unchanged."** `grep` selects only lines that
match a pattern; any edit on a line that does not contain one of the searched symbols is invisible to it —
confirmed by execution: removing `-i` from the function's own `grep -qiE "$CODEX_BLOCKING_PATTERN"` call
produces zero output from the old check, i.e. the mutation passes undetected. Replaced with extraction and
direct comparison of the complete function range, which cannot have this blind spot because it compares every
line in the range, not just lines containing a searched substring.

1. Run:

   ```bash
   grep -n "CODEX_BLOCKING_PATTERN=\|CODEX_MERGE_REFUSAL_PATTERN=\|CODEX_NEGATION_WORDS=" \
     scripts/development-workflow/codex-github-reviewer.sh
   ```

2. Extract and diff the three pattern-definition lines directly (not a `grep` over the whole-file diff) —
   **corrected this round (Codex GitHub finding `3804535211`, round 11): the `-n` flag must not be used here.**
   This plan deletes a large block of code and comments above these three definitions (`CODEX_APPROVAL_PATTERN`,
   `CODEX_NEGATED_APPROVAL_PATTERN`, `CODEX_NEGATED_APPROVAL_TARGET_WORDS`, and their surrounding comments), so
   `CODEX_NEGATION_WORDS` and `CODEX_MERGE_REFUSAL_PATTERN` shift to earlier line numbers after a correct
   implementation. Confirmed by execution: simulating that shift (deleting an unrelated block of lines above
   these definitions) and diffing with `-n` produces a false-positive change — the line-number prefix differs
   even though the definitions are byte-identical — while the same comparison without `-n` correctly shows no
   difference:

   ```bash
   diff <(git show origin/develop:scripts/development-workflow/codex-github-reviewer.sh \
            | grep '^CODEX_BLOCKING_PATTERN=\|^CODEX_MERGE_REFUSAL_PATTERN=\|^CODEX_NEGATION_WORDS=') \
        <(grep '^CODEX_BLOCKING_PATTERN=\|^CODEX_MERGE_REFUSAL_PATTERN=\|^CODEX_NEGATION_WORDS=' \
            scripts/development-workflow/codex-github-reviewer.sh)
   ```

   Run today against the real tree: **exit 0, no output** (the three definitions are byte-identical to
   `origin/develop`, as expected — this plan has not modified the production script yet). This remains true
   after a correct implementation shifts these definitions to earlier line numbers, because line numbers are no
   longer part of the compared text.

3. Extract and diff the **complete** `codex_response_is_blocking` function range — this is the check that
   actually proves the function is unchanged, not merely that three unrelated constants above it are unchanged:

   ```bash
   diff <(git show origin/develop:scripts/development-workflow/codex-github-reviewer.sh \
            | awk '/^codex_response_is_blocking\(\)/,/^}/') \
        <(awk '/^codex_response_is_blocking\(\)/,/^}/' scripts/development-workflow/codex-github-reviewer.sh)
   ```

   Run today against the real tree: **exit 0, no output.** Run against a deliberately mutated copy (with `-i`
   removed from the function's internal `grep -qiE` call, simulating an accidental edit) to confirm the check
   actually detects a real change: **exit 1**, with output showing exactly the mutated line — confirming this
   form has no blind spot, unlike the `grep`-over-`git diff` form it replaces (which produced no output at all
   for the identical mutation, confirmed by execution this round).

**Expected result**: the three blocking-side pattern definitions are present (step 1). Step 2's diff is empty
(exit 0) — the three pattern definitions are byte-identical to `develop`. **Step 3's diff is empty (exit 0) —
the entire `codex_response_is_blocking` function, not merely the lines mentioning its name or
`codex_strip_not_only_idiom`, is byte-identical to `develop`.** If step 3 shows any output, `is_blocking` has
been edited — whether or not the diff line happens to mention `codex_strip_not_only_idiom`, this form will
catch it, which is exactly the property the prior `grep`-over-diff form lacked.

---

### Step 5: A footer-bearing near-miss safe-fails through the composed chain — it does not wait or time out

**Maps to**: Decision 6 (new this round, Codex GitHub finding `3804535190`, round 11 P1)

**This step exists because expectations for `codex_response_is_approved` alone are not sufficient to prove a
verdict.** The acknowledgement branch immediately after the `is_approved` check at every verdict site
(`grep -qi "If Codex has suggestions, it will comment; otherwise it will react with"`) intercepts any body that
carries the real footer but fails `is_approved` — which, under this plan's whole-body design, is true of nearly
every genuine near-miss response — and routes it to `continue`/`sleep` (wait for more evidence) instead of the
documented safe-fail, unless the acknowledgement branch is gated on non-terminal evidence (Decision 6).

1. Take the Step 7 template's verdict sentence, `**Reviewed commit:**` line, and complete real footer, but omit
   `Swish!` (the E3 construction). Build a mock `gh` that serves it as a SHA-pinned root comment and run the
   reviewer with a short poll budget (as in Step 6 — use `--poll-interval 1 --max-wait 1
   --max-retriggers 0`).
2. Repeat with the E9 construction (unrelated prose immediately before the template) and the E10 construction
   (unrelated prose immediately after the complete footer), each with the complete real footer present.

**Expected result**: all three runs exit **1** and print `VERDICT: NEEDS_REVISION (unrecognized response
format — safe-fail)` — **not** `VERDICT: TIMED_OUT` and **not** a hang until `--max-wait` is exhausted. If any
run instead exits **2** with `VERDICT: TIMED_OUT — no response from '<bot>' after …`, the acknowledgement branch
is not correctly gated on non-terminal evidence — this is the exact regression Codex GitHub finding
`3804535190` identified, and it is the single highest-priority failure mode this runbook checks for in this
step. (Reproduced this round: before the Decision 6 fix, all three of these constructions time out; after the
fix, all three correctly safe-fail — confirmed by running the actual composed chain, not `is_approved` in
isolation, via a patched copy of the real script.)

---

### Step 6: A response that is not, character-for-character, an evidenced template safe-fails

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

### Step 7: The real vendor clean response still approves, end to end

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
   Step 6.

**Expected result**: the command exits 0 and prints `VERDICT: APPROVED`. If it instead exits 1, this is a
total operational failure of the ready phase (the classifier rejects the one response it exists to accept) —
stop and report it. The correct fix, per Decision 2, is to re-capture the live body (complete footer included)
and add or update the `CODEX_APPROVED_TEMPLATES` entry with evidence, never to loosen the matching technique
(no case-insensitivity, no optional clauses, no wildcard placeholders beyond the existing bounded SHA field,
and no reintroduction of a truncation step to avoid having to capture the footer).

---

### Step 8: The real review-wrapper body (no clean signal) is not misclassified

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
   `state: COMMENTED`, and run the reviewer as in Step 6.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. This body was never eligible to become a template (Decision 2) — its verdict is unaffected by
this revision, exactly as it was unaffected by every prior revision.

---

### Step 9: A refusal inserted inside the footer is rejected by `is_approved` alone — `is_blocking` upgrades verdict specificity, but is no longer load-bearing for safety here

**Maps to**: Edge case E22 (rewritten this round); Decision 4/5

**This step's expected result changed this round.** Under the prior (truncate-then-match) revision,
`codex_response_is_approved` **alone** returned `APPROVED` for this body, and only `codex_response_is_blocking`
prevented the composed verdict from being wrong. Under this revision, `is_approved` alone already rejects it.

1. Take the Step 7 body and insert the sentence `This must not be merged.` **inside** the `<details>` block
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

### Step 10: The round-6 exploit (Codex GitHub finding `3803545669`) is closed — footer-opening-line-only plus trailing content is rejected

**Maps to**: Edge case E23; Decision 1/2/5 (Codex GitHub finding `3803545669`) — **this is the direct
regression test for the finding that motivated this revision; treat a failure here as the highest-priority
result in this runbook**

1. Take the Step 7 template's verdict sentence and `**Reviewed commit:**` line, append **only** the footer's
   opening line (`<details> <summary>ℹ️ About Codex in GitHub</summary>`, not the rest of the footer), then
   append a new paragraph reading `Rename the unsafe function.`
2. Build a mock `gh` that serves this exact body as a SHA-pinned root comment and run the reviewer as in
   Step 6.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. Under the immediately prior revision of this plan, this exact construction reproduced the
*visible* (pre-truncation) template exactly and was classified `APPROVED`, because the footer's opening line
satisfied the truncation trigger and everything after it — including `Rename the unsafe function.` — was
discarded unread. Under this revision there is no truncation trigger: the required literal is the **complete**
footer text, and a body carrying only its opening line does not reproduce it, so the match fails independent
of what follows. If this step returns `APPROVED`, the round-6 finding has reopened — stop and report it
immediately.

---

### Step 11: A one-byte mutation anywhere inside the footer — not only its opening line — is rejected

**Maps to**: Edge case E24

1. Take the Step 7 body (complete real footer included) and, in three separate runs, mutate exactly one byte
   at each of these positions: (a) mid-footer-sentence (e.g. `react with` → `react With`), (b) immediately
   before the closing `</details>` (e.g. the word preceding it), and (c) inside the `chatgpt.com` settings URL.
2. Build a mock `gh` that serves each mutated body as a SHA-pinned root comment and run the reviewer as in
   Step 6, once per mutation.

**Expected result**: all three runs exit 1 and print `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. This confirms the entire footer text is load-bearing for the match, not merely its opening line —
a property the prior (truncate-then-match) revision never needed and never tested, since only the opening line
was ever compared against anything under that design.

---

### Step 12: The round-5 exploit that triggered the prior design replacement is still closed

**Maps to**: Edge case E21; Decision 2 (Codex GitHub finding `3803306915`)

1. Create a scratch directory and a mock `gh` that returns a SHA-pinned Codex root comment reading
   `Looks good, or is it?`, following the mock convention used by Step 6.
2. Run the reviewer as in Step 6.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. An earlier (residue-grammar) revision of this plan returned `VERDICT: APPROVED` for this body:
`or`, `is`, and `it` were all closed-class filler words the grammar treated as inert, so the residue reduced to
nothing even though the sentence, read as a whole, is a hedge that negates the clean signal. The final design
closes this — and the entire class of construction it represents — trivially: this body is simply not a
reproduction of any evidenced template.

---

### Step 13: The SHA placeholder generalizes within its bound and rejects outside it

**Maps to**: Edge cases E4–E8

1. For case (a) — a different 10-character valid hex SHA than the one captured live — use the mock convention
   from Step 6: serve the Step 7 template (complete real footer appended, SHA replaced) as a **SHA-pinned root
   comment** (`issues/{PR}/comments`). Extraction of a well-formed hex SHA in this length range succeeds, so
   this body reaches `COMBINED_SOURCE = "review"` the same way Step 6/7's fixtures do.
2. For cases (b) a 6-character hex SHA, (c) a 41-character hex SHA, and (d) a non-hex string such as
   `not-a-sha!`, **do not** use a root comment. `codex_response_reviews_current_head`'s extraction regex
   (`` `\([0-9a-fA-F]\{7,40\}\)` `` against the literal `Reviewed commit:` marker) requires a well-formed
   7–40-character hex string to match at all; a malformed SHA fails extraction outright, so a root-comment
   fixture never becomes SHA-pinned terminal evidence (`is_terminal` stays 0) regardless of the classifier
   design. Because these three bodies still carry the complete real footer, an unpinned ancillary comment
   would instead reach the acknowledgement branch (`COMBINED_SOURCE = "comment"`, gated open by Decision 6) and
   wait for more evidence — producing `VERDICT: TIMED_OUT`, not `NEEDS_REVISION`, and confounding this step's
   result. Serve each of (b), (c), and (d) as a **review** (`pulls/{PR}/reviews`, `state: COMMENTED`) with a
   mocked `commit_id` equal to the current head SHA instead — review pinning is decided by the API's own
   `commit_id` field, independent of the body text, so this correctly isolates what the SHA field inside the
   body is meant to test. (Reproduced this round: the same three malformed-SHA bodies served as SHA-pinned
   root comments all exit 2 `VERDICT: TIMED_OUT`; served as reviews with a pinned `commit_id`, all three exit 1
   `VERDICT: NEEDS_REVISION` as documented below.)

**Expected result**: (a) exits 0, `VERDICT: APPROVED` — confirms the placeholder is not hardcoded to the one
captured value. (b), (c), and (d) all exit 1, `VERDICT: NEEDS_REVISION` — confirms the `{7,40}` bound (git's
documented abbreviated-to-full SHA-1 hex-length range, per Decision 2) is enforced, not merely documented.
Every one of these four bodies must include the complete real footer — a body missing the footer would return
`NEEDS_REVISION` for the wrong reason (missing footer, not the SHA bound), confounding this step's result.

---

### Step 14: Documentation reflects the new contract

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

### Step 15: Lint gates are clean

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
| 14 | | |

**Platform tested**: (macOS/BSD or Linux/GNU)

**Tester**:

**Date**:

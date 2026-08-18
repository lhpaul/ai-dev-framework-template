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
- [ ] `gh auth status` succeeds (needed for Steps 7 and 8)
- [ ] You know which platform's tooling you are on (macOS/BSD or Linux/GNU) so you can note it in the results

**Design assets**: none. This work item has no `## Design assets` section, no tracker attachments, no linked
design files, and no `assets/` directory in its development folder. No expected-versus-actual fidelity step
is included, and no visual baseline should be invented.

**A note on this runbook's numbers.** This document intentionally does not state exact assertion counts,
occurrence counts, or scenario-name lists as expected values. Every one of those, when frozen in a prior
revision of this runbook, went stale or was found wrong within a few review rounds, because the underlying
file changes — including as a direct result of the very steps below. Where a step needs a count, it states
the command to derive that count and the structural property the result must have (e.g. "this must return
nothing," "this diff must be empty," "the total must equal the sum of its parts"), not a specific number.
Fill in the actual figures you observe when you run each step.

---

## Test Data

| Item | Value |
| --- | --- |
| Reviewer script | `scripts/development-workflow/codex-github-reviewer.sh` |
| Test harness | `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Integration doc | `docs/workflow/development-workflow/integrations/codex-github.md` |
| Reviewer loop protocol | `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` |
| Real clean Codex root comment source | PR #1489 in `lhpaul/ai-dev-framework-template` |
| Real Codex review-wrapper source (no clean signal) | PR #1490 in `lhpaul/ai-dev-framework-template` (any of its reviews) |
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

**Expected result**: the run exits 0 and reports zero failures. Record the total assertion count reported —
this is the real, current figure; the implementation plan does not carry a number to compare it against.

---

### Step 2: Every obsoleted symbol is actually gone, and only the final design's symbols remain

**Maps to**: Implementation Order steps 2–4 (step 5 is the acknowledgement-branch gate, Decision 6, a separate
concern from symbol deletion — see Step 5 below)

1. Every prior design this plan has replaced introduced symbols the final design does not ship
   (`CODEX_APPROVAL_PATTERN`, `CODEX_NEGATED_APPROVAL_PATTERN`, `CODEX_CLEAN_SIGNAL_PATTERN`,
   `CODEX_APPROVAL_(NEGATION|HEDGE|ACTIONABLE|DISQUALIFIER)_PATTERN`, `CODEX_RESIDUE_FILLER_WORD_PATTERN`,
   `CODEX_RESIDUE_STARTER_PATTERN`, `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN`, `codex_excise_clean_signals`,
   `codex_residue_is_closed_grammar`, `codex_response_first_paragraph`, `codex_strip_vendor_metadata_lines`,
   `CODEX_FOOTER_OPENING_LITERAL`, `codex_strip_codex_footer` — see the implementation plan's Decision 2/5 for
   the full list and provenance). **A raw occurrence count over these names is unsound**: functions this plan
   keeps unchanged (`codex_response_is_blocking`, `codex_strip_quoted_spans`, the `CODEX_BLOCKING_PATTERN`
   definition) have rationale comments that name several of these symbols by way of explaining an unrelated,
   historical design decision. Filter comment lines before counting:

   ```bash
   grep -v '^[[:space:]]*#' scripts/development-workflow/codex-github-reviewer.sh \
     | grep -nE "CODEX_APPROVAL_PATTERN|CODEX_NEGATED_APPROVAL|CODEX_CLEAN_SIGNAL|CODEX_APPROVAL_(NEGATION|HEDGE|ACTIONABLE|DISQUALIFIER)|CODEX_RESIDUE_FILLER|CODEX_RESIDUE_STARTER|CODEX_VENDOR_FLAVOR|codex_excise_clean_signals|codex_residue_is_closed_grammar|codex_response_first_paragraph|codex_strip_vendor_metadata_lines|CODEX_FOOTER_OPENING_LITERAL|codex_strip_codex_footer"
   ```

   **Use this comment-filtered form as the pass/fail gate — it must return nothing after a correct
   implementation.** Do not use the unfiltered form as a gate: it will still show comment-line matches in
   functions this plan does not touch, and comparing against a frozen "N is expected" number is exactly the
   kind of claim this runbook avoids — the correct check is structural (empty output), not numeric.

   `codex_strip_not_only_idiom`/`not_only` is deliberately excluded from this search — see Step 3 below. It is
   kept, not deleted; only its call inside the old `codex_response_is_approved` is gone, as a byproduct of that
   function's full replacement, not a listed deletion.

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

4. Confirm every stale approval-path comment named in Implementation Order step 6 was actually rewritten, not
   just any one of them:

   ```bash
   grep -n "codex_response_is_approved" scripts/development-workflow/codex-github-reviewer.sh
   ```

**Expected result**: the comment-filtered form of the first command prints nothing — every symbol this plan's
prior revisions ever introduced or targeted for deletion is gone from the executable code, with no dormant
leftovers. This includes `CODEX_FOOTER_OPENING_LITERAL` and `codex_strip_codex_footer` — if either still
appears in the executable code anywhere in the file, this step fails even if every other symbol is gone. The
second command prints at least one definition line for each of the two symbols the final design actually
ships. The third command's output shows `codex_response_is_approved` normalizing whitespace on `$body`
directly and looping over `CODEX_APPROVED_TEMPLATES` — no footer-strip call, no fence-marker check, no
quote-stripping call, no `codex_strip_not_only_idiom` call, and no executable reference to any of the symbols
the first command searched for (comments describing the plan's own history, in functions this plan does not
touch, are expected and are not a failure). The fourth command's output must show only: the function's own
definition, its real call sites — **five, not four** (Codex GitHub finding `3805786163`, P2 — the four verdict
sites plus one more inside `codex_response_priority`, which also calls `codex_response_is_approved` to rank a
body at the approved priority tier; same locations as before this step in both cases —
`codex_response_is_approved` is still invoked the same way everywhere, only its internals changed), and any
comment correctly describing current or historical behavior. **Do not read "call sites" as the four verdict
sites only — a passing result correctly includes the fifth, `codex_response_priority` call, and its absence
would itself be a regression.** **No comment may claim `codex_response_has_fence_marker`,
`codex_strip_quoted_spans`, or `codex_strip_not_only_idiom` is "used by" `codex_response_is_approved`** — per
Implementation Order step 6's list of locations to fix. If any comment still describes
`codex_response_is_approved` as stripping quotes, checking fences, or calling the not-only idiom, this step
fails even if Step 2's commands 1–3 above all pass. Cross-check the fourth command's count against
Implementation Order step 6's stated arithmetic (each edit that removes the phrase from a line, or deletes the
line entirely, reduces the count by exactly one) rather than trusting an absolute number from any document —
if the count and the arithmetic disagree, one of the prescribed edits was skipped or misapplied.

---

### Step 3: `codex_strip_not_only_idiom` is kept, with exactly one call site — inside `codex_response_is_blocking`

**Maps to**: Decision 4

1. `codex_response_is_blocking`'s own rationale comment names `codex_strip_not_only_idiom`, so a raw count over
   this symbol is unsound for the same reason as Step 2. Use the comment-filtered form as the pass/fail gate:

   ```bash
   grep -v '^[[:space:]]*#' scripts/development-workflow/codex-github-reviewer.sh \
     | grep -c "codex_strip_not_only_idiom"
   ```

2. Run, to confirm which function the one remaining call lives inside:

   ```bash
   grep -n "codex_response_is_blocking\|codex_strip_not_only_idiom" scripts/development-workflow/codex-github-reviewer.sh
   ```

**Expected result**: the comment-filtered count from step 1 must equal exactly the function's own definition
plus its one remaining call — not the definition alone (0 calls, meaning the function was wrongly deleted
entirely — a direct regression: a genuinely clean response containing "not only … merge" in one clause, e.g.
`This is not only safe to merge but looks good.`, would be misclassified as a merge refusal), and not the
definition plus two calls (meaning the old `is_approved`-side call was wrongly left in place). **Do not use
the raw (unfiltered) count as the gate** — it includes the comment mention(s) alongside the real code and will
not match the comment-filtered figure. The second command's output shows the one remaining call appearing
inside `codex_response_is_blocking`'s function body, not inside `codex_response_is_approved`'s.

---

### Step 4: The blocking classifier is untouched — zero diff, not merely an unchanged pattern definition

**Maps to**: Decision 4

`codex_response_is_blocking` must have **no** functional change at all under this revision. A `grep` over a
`git diff` cannot establish that: `grep` selects only lines that match a pattern, so any edit on a line that
does not contain one of the searched symbols is invisible to it. The check below instead extracts and compares
the complete region directly, which cannot have that blind spot because it compares every line in the range,
not just lines containing a searched substring.

**Compare against the merge base, not the `origin/develop` branch tip (Codex GitHub finding `3805716206`, P2).**
`origin/develop` is a moving target: if `develop` advances after this implementation branch was created — a
routine, expected event, not an edge case — comparing against its current tip means an untouched
`codex_response_is_blocking` can show a nonempty diff for a change this branch never made, failing this
mandatory gate on valid work. The merge base (the commit this branch actually started from) does not move
regardless of what merges into `develop` afterward, so it is the correct, stable comparison point.

0. **Resolve the merge base once, before either comparison below.** Fetch first, so a stale local
   `origin/develop` (or one that was never fetched at all in this checkout) does not silently resolve to the
   wrong commit:

   ```bash
   git fetch origin
   MERGE_BASE=$(git merge-base HEAD origin/develop) || {
     echo "ERROR: could not resolve merge base against origin/develop — stop here." >&2
     exit 1
   }
   ```

   **If this fails, stop and report it rather than proceeding** — do not fall back to comparing against the
   branch tip (`origin/develop` directly) as a workaround: that reintroduces the exact moving-target problem
   this step exists to avoid, silently, in the one case (a broken or absent remote-tracking ref) where a
   fallback would be most likely to go unnoticed.

1. Locate the three pattern definitions this function depends on:

   ```bash
   grep -n "CODEX_BLOCKING_PATTERN=\|CODEX_MERGE_REFUSAL_PATTERN=\|CODEX_NEGATION_WORDS=" \
     scripts/development-workflow/codex-github-reviewer.sh
   ```

2. Extract and diff the three pattern-definition lines directly (not a `grep` over the whole-file diff), against
   `$MERGE_BASE`. **Do not include line numbers (`-n`) in the extraction.** This plan deletes a block of code
   and comments above these three definitions, so they shift to earlier line numbers after a correct
   implementation; a comparison that embeds line numbers in the compared text produces a false-positive
   difference on a byte-identical region once that shift happens, purely because the numbers themselves differ.

   ```bash
   diff <(git show "$MERGE_BASE":scripts/development-workflow/codex-github-reviewer.sh \
            | grep '^CODEX_BLOCKING_PATTERN=\|^CODEX_MERGE_REFUSAL_PATTERN=\|^CODEX_NEGATION_WORDS=') \
        <(grep '^CODEX_BLOCKING_PATTERN=\|^CODEX_MERGE_REFUSAL_PATTERN=\|^CODEX_NEGATION_WORDS=' \
            scripts/development-workflow/codex-github-reviewer.sh)
   ```

3. Extract and diff the **complete** `codex_response_is_blocking` function range, also against `$MERGE_BASE` —
   this is the check that actually proves the function is unchanged, not merely that three unrelated constants
   above it are unchanged:

   ```bash
   diff <(git show "$MERGE_BASE":scripts/development-workflow/codex-github-reviewer.sh \
            | awk '/^codex_response_is_blocking\(\)/,/^}/') \
        <(awk '/^codex_response_is_blocking\(\)/,/^}/' scripts/development-workflow/codex-github-reviewer.sh)
   ```

**Expected result**: `$MERGE_BASE` resolves to a commit (step 0) — if it does not, stop and report before
proceeding, do not substitute `origin/develop` directly. The three blocking-side pattern definitions are
present (step 1). Step 2's diff is empty (exit 0) — the three pattern definitions are byte-identical to the
merge base, before or after a correct implementation shifts their line numbers, because line numbers are not
part of the compared text. **Step 3's diff is empty (exit 0) — the entire `codex_response_is_blocking`
function, not merely the lines mentioning its name or `codex_strip_not_only_idiom`, is byte-identical to the
merge base.** If step 3 shows any output, `is_blocking` has been edited — this form has no blind spot, unlike
a `grep`-over-`diff` form, which can miss an edit on a line that does not contain a searched substring, and it
does not false-positive merely because `develop` has advanced since this branch started, unlike a
`origin/develop`-tip comparison.

---

### Step 5: A footer-bearing near-miss safe-fails through the composed chain — it does not wait or time out

**Maps to**: Decision 6

**This step exists because expectations for `codex_response_is_approved` alone are not sufficient to prove a
verdict.** The acknowledgement branch immediately after the `is_approved` check at every verdict site
(`grep -qi "If Codex has suggestions, it will comment; otherwise it will react with"`) intercepts any body that
carries the real footer but fails `is_approved` — which, under this plan's whole-body design, is true of nearly
every genuine near-miss response — and routes it to `continue`/`sleep` (wait for more evidence) instead of the
documented safe-fail, unless the acknowledgement branch is gated on non-terminal evidence (Decision 6).

1. Take the Step 7 template's verdict sentence, `**Reviewed commit:**` line, and complete real footer, but omit
   `Swish!` (the E3 construction). Build a mock `gh` that serves it as a SHA-pinned root comment and run the
   reviewer with a short poll budget (as in Step 6 — use `--poll-interval 1 --max-wait 1 --max-retriggers 0`).
2. Repeat with the E9 construction (unrelated prose immediately before the template) and the E10 construction
   (unrelated prose immediately after the complete footer), each with the complete real footer present.

**Expected result (steps 1–2)**: all three runs exit **1** and print `VERDICT: NEEDS_REVISION (unrecognized
response format — safe-fail)` — **not** `VERDICT: TIMED_OUT` and **not** a hang until `--max-wait` is exhausted.
If any run instead exits **2** with `VERDICT: TIMED_OUT — no response from '<bot>' after …`, the acknowledgement
branch is not correctly gated on non-terminal evidence — this is a high-priority failure mode this runbook
checks for in this step: it means a stricter classifier has silently degraded ready-phase throughput (every
near-miss now waits out its poll budget instead of safe-failing promptly) rather than producing the documented
behavior.

**Steps 1–2 only exercise the main-loop verdict site — Decision 6's gate is four separately hand-edited copies,
and a scenario resolving at one site cannot confirm the other three are correct.** Steps 3–5 below route the
same E3 near-miss body through each of the other three sites, so a missed or mistyped gate at any one of them
is caught by exactly that site's run, not masked by the other three passing.

3. **Async-arrival.** Build a mock `gh` whose comment-fetch endpoint returns an empty list for the main poll
   loop's own budget (`--poll-interval 1 --max-wait 1`), then returns the E3 near-miss body (SHA-pinned root
   comment, complete real footer) only on the single grace poll that follows "poll budget exhausted."
4. **Async-final.** Build a mock `gh` whose comment-fetch endpoint returns empty during the main poll loop,
   then returns a **bare acknowledgement comment** (the footer's acknowledgement sentence alone, no
   `**Reviewed commit:**` marker — non-terminal) on the first grace poll, then returns the E3 near-miss body
   only on the second check that follows the resulting one-shot sleep.
5. **Async-reaction-final.** Build a mock `gh` that reports a thumbs-up reaction on the trigger comment from
   the first poll onward, with every comment fetch returning empty until the final check that follows the
   reaction-triggered sleep, where the E3 near-miss body appears.

**Expected result (steps 3–5)**: each run exits **1** and prints `VERDICT: NEEDS_REVISION (unrecognized
response format — safe-fail)` — never `VERDICT: TIMED_OUT`. Confirm from the `INFO:` trace which site actually
resolved each run (`async-arrival bot response detected during grace period` for step 3; `final async bot
response detected after acknowledgement wait` for step 4; `final async reaction bot response detected` for
step 5) — a run that exits 1 via the wrong site's trace does not confirm that site's gate. **This is the
single highest-priority failure mode this runbook checks for in this step**: a footer-bearing near-miss timing
out at any one of the four sites means that site's copy of Decision 6's gate is missing or wrong, even if the
other three (and the full test suite) pass.

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
   literal baked into `CODEX_APPROVED_TEMPLATES`, not only the opening line. **The flavor word/phrase itself
   (`Swish!` here) is no longer a fixed literal to compare against (Decision 2 Second Addendum) — it is a
   bounded placeholder (up to 40 characters, excluding `*`, backtick, and control characters), so any flavor
   text within that bound is expected and not itself a sign of drift.** If the `**Reviewed commit:**` marker
   format, the footer's exact wording, or the flavor text's length/character set (exceeds 40 characters, or
   contains `*`/backtick/a control character) has changed, stop and report it — do not proceed to step 3
   assuming the existing `CODEX_APPROVED_TEMPLATES` entry still applies. This is a stricter check than any
   truncate-then-match revision of this runbook required, because the footer is now part of the literal being
   matched, not discarded before comparison.
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

1. Capture a real review body from PR #1490. **Select the first matching review inside the jq expression
   itself, not by piping the emitted bodies through `head -1`** — `head -1` on multi-line output stops at the
   first *line*, not the first *review*, so it would truncate the body to a partial `### 💡 Codex Review`
   header fragment rather than yielding one complete review body:

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

**Maps to**: Edge case E22; Decision 4/5

**This step's expected result differs from any truncate-then-match revision of this plan.** Under that design,
`codex_response_is_approved` **alone** returned `APPROVED` for this body, and only `codex_response_is_blocking`
prevented the composed verdict from being wrong. Under this design, `is_approved` alone already rejects it.

1. Take the Step 7 body and insert the sentence `This must not be merged.` **inside** the `<details>` block
   (e.g. immediately after `</summary>`).
2. Run the reviewer against it with the same mock setup.
3. **Additionally**, call `codex_response_is_approved` directly (source the script or extract the function) on
   just this body, in isolation from `codex_response_is_blocking`, and confirm its own exit code.

**Expected result**: the full reviewer run in step 2 exits 1 and prints `VERDICT: NEEDS_REVISION` (blocking
branch, no `unrecognized response format` suffix), because `codex_response_is_blocking` (unchanged) recognizes
`must not be merged` and still runs before approval is considered at every verdict site (Decision 3). **The
isolated check in step 3 must also return non-zero (`NEEDS_REVISION`) from `codex_response_is_approved` alone**
— this is the direct consequence of removing footer truncation: there is no truncation point left for the
inserted sentence to hide behind, so the whole-body exact match already rejects this body on its own, with no
help from `is_blocking` needed. If step 3 shows `is_approved` alone still returning `APPROVED` for this body,
that is a regression to a truncate-then-match design and Codex GitHub finding `3803545669`'s underlying gap
has reopened — stop and report it immediately, this is the single highest-priority regression this runbook
checks for.

---

### Step 10: The footer-opening-line-only exploit (Codex GitHub finding `3803545669`) is closed

**Maps to**: Edge case E23; Decision 1/2/5 — **this is the direct regression test for the finding that
motivated this revision; treat a failure here as the highest-priority result in this runbook**

1. Take the Step 7 template's verdict sentence and `**Reviewed commit:**` line, append **only** the footer's
   opening line (`<details> <summary>ℹ️ About Codex in GitHub</summary>`, not the rest of the footer), then
   append a new paragraph reading `Rename the unsafe function.`
2. Build a mock `gh` that serves this exact body as a SHA-pinned root comment and run the reviewer as in
   Step 6.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. Under a truncate-then-match revision, this exact construction reproduced the *visible*
(pre-truncation) template exactly and was classified `APPROVED`, because the footer's opening line satisfied
the truncation trigger and everything after it — including `Rename the unsafe function.` — was discarded
unread. Under this revision there is no truncation trigger: the required literal is the **complete** footer
text, and a body carrying only its opening line does not reproduce it, so the match fails independent of what
follows. If this step returns `APPROVED`, this finding has reopened — stop and report it immediately.

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
a property no truncate-then-match revision ever needed or tested, since only the opening line was ever
compared against anything under that design.

---

### Step 12: The filler-composed-hedge exploit (Codex GitHub finding `3803306915`) is still closed

**Maps to**: Edge case E21; Decision 2

1. Create a scratch directory and a mock `gh` that returns a SHA-pinned Codex root comment reading
   `Looks good, or is it?`, following the mock convention used by Step 6.
2. Run the reviewer as in Step 6.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`. Under an earlier (closed-residue-grammar) design, this body returned `VERDICT: APPROVED`: `or`,
`is`, and `it` were all closed-class filler words the grammar treated as inert, so the residue reduced to
nothing even though the sentence, read as a whole, is a hedge that negates the clean signal. The final design
closes this — and the entire class of construction it represents — trivially: this body is simply not a
reproduction of any evidenced template.

---

### Step 13: The SHA placeholder generalizes within its bound and rejects outside it

**Maps to**: Edge cases E4–E8

1. For case (a) — a different, still-valid hex SHA than the one captured live — use the mock convention from
   Step 6: serve the Step 7 template (complete real footer appended, SHA replaced) as a **SHA-pinned root
   comment** (`issues/{PR}/comments`). Extraction of a well-formed hex SHA in the `{7,40}` length range
   succeeds, so this body reaches `COMBINED_SOURCE = "review"` the same way Step 6/7's fixtures do.
2. For cases (b) a 6-character hex SHA, (c) a 41-character hex SHA, and (d) a non-hex string such as
   `not-a-sha!`, **do not** use a root comment. `codex_response_reviews_current_head`'s extraction regex
   requires a well-formed 7–40-character hex string to match at all; a malformed SHA fails extraction
   outright, so a root-comment fixture never becomes SHA-pinned terminal evidence regardless of the classifier
   design. Because these three bodies still carry the complete real footer, an unpinned ancillary comment
   would instead reach the acknowledgement branch and wait for more evidence — producing `VERDICT: TIMED_OUT`,
   not `NEEDS_REVISION`, and confounding this step's result. Serve each of (b), (c), and (d) as a **review**
   (`pulls/{PR}/reviews`, `state: COMMENTED`) with a mocked `commit_id` equal to the current head SHA instead —
   review pinning is decided by the API's own `commit_id` field, independent of the body text, so this
   correctly isolates what the SHA field inside the body is meant to test.

**Expected result**: (a) exits 0, `VERDICT: APPROVED` — confirms the placeholder is not hardcoded to the one
captured value. (b), (c), and (d) all exit 1, `VERDICT: NEEDS_REVISION` — confirms the `{7,40}` bound (git's
documented abbreviated-to-full SHA-1 hex-length range, per Decision 2) is enforced, not merely documented. If
(b), (c), or (d) instead exits 2 (`VERDICT: TIMED_OUT`), the fixture was built as a root comment rather than a
review-sourced payload — reconstruct it per step 2 above before concluding the SHA bound itself is not
enforced. Every one of these four bodies must include the complete real footer — a body missing the footer
would return `NEEDS_REVISION` for the wrong reason (missing footer, not the SHA bound), confounding this
step's result.

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
describes the whole-body, no-truncation design (not an allow-list, closed-grammar, or truncate-then-match
design any earlier revision of this plan shipped there).

---

### Step 15: Lint gates are clean

**Maps to**: Implementation Order step 10

1. Run the markdown lint and heuristic lint commands from `AGENTS.md` against the changed markdown files.
2. Run `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`.

**Expected result**: every command exits 0 with no reported violations.

---

### Step 16: The bounded flavor placeholder approves every evidenced token, a previously-unevidenced one, and enforces its three guards (Decision 2 Second Addendum, PR #1494 follow-up)

**Maps to**: Decision 2 Second Addendum — this step exists because PR #1494's own Codex review (comment id
`5333550055`) safe-failed on its first real-traffic exercise (the response read `:rocket:`, not the sole
originally-evidenced `Swish!` literal), and the enumeration this repository first shipped to fix that (a
14-token literal alternation) was itself replaced by a bounded placeholder before merge, once a sweep for that
fix found enough token diversity to prove enumeration would not converge either.

1. Re-fetch the live PR #1494 comment and confirm it still reads `Codex Review: Didn't find any major issues.
   :rocket:` followed by the `**Reviewed commit:**` marker and the complete real footer:

   ```bash
   gh api repos/lhpaul/ai-dev-framework-template/issues/comments/5333550055 --jq '.body'
   ```

2. Run the reviewer against that exact body as a SHA-pinned root comment (mock convention from Step 6).
3. For each of the other 13 evidenced flavor tokens (`Swish!`, `Nice work!`, `Chef's kiss.`, `You're on a
   roll.`, `:tada:`, `Another round soon, please!`, `:+1:`, `Bravo.`, `Keep it up!`, `Delightful!`, `Keep them
   coming!`, `Can't wait for the next one!`, `More of your lovely PRs please.`), build a body reproducing the
   template with that token in place of the flavor slot and run the reviewer against it.
4. Build a body using an invented, previously-unevidenced token (e.g. `Fantastic job!`, the same phrase the
   prior alternation design's negative test used) in the flavor slot and run the reviewer against it. This is
   the direct proof of the behavior change: under the alternation this exited `NEEDS_REVISION`; under the
   bounded placeholder it exits `APPROVED`.
5. Confirm the placeholder's structure guards: build a body with `*` inside the flavor slot (e.g.
   `Great **job**`) and confirm it does **not** approve; build a body with a backtick inside the flavor slot
   (e.g. `` Nice `work` ``) and confirm it does **not** approve.
6. Confirm the length cap: build a body with exactly 40 characters in the flavor slot and confirm it **does**
   approve (boundary inclusive); build a body with 41 characters and confirm it does **not** approve.
7. Confirm the length cap is enforced even via a newline-separated injection vector: build a body where a
   paragraph break (blank line) sits inside the flavor position, followed by an extra sentence long enough
   that the flattened (post-normalization) flavor text exceeds 40 characters, and confirm it does **not**
   approve.

**Expected result**: steps 2 and 3 (all 14 evidenced tokens) exit 0 and print `VERDICT: APPROVED`. Step 4
(previously-unevidenced token) now exits 0 and prints `VERDICT: APPROVED` — this is the intended behavior
change, not a regression. Step 5's two structure-guard bodies, the step 6 41-character body, and the step 7
newline-separated body all exit 1 and print `VERDICT: NEEDS_REVISION (unrecognized response format —
safe-fail)`; the step 6 40-character body exits 0. If any structure/length guard case instead approves, the
placeholder's character class or length bound has regressed, and the finding must be treated as `blocking` on
the same footing as a template-level escaping bug — this is the mechanism that keeps the placeholder bounded
rather than a general wildcard.

---

## Results

| Step | Pass / Fail | Notes |
| --- | --- | --- |
| 1 | Pass | `bash scripts/development-workflow/tests/test-pr-review-loop.sh` exits 0, `Tests: 722 passed, 0 failed` (684 baseline; +28 then -28 for the superseded 14-token alternation scenarios; +38 for the 18 bounded-placeholder scenarios) |
| 2 | Pass | Comment-filtered deletion-list search returns nothing; `CODEX_APPROVED_TEMPLATES`/`codex_normalize_whitespace` each show one definition; `codex_response_is_approved` shows no footer-strip/fence/quote/not-only-idiom call; five call sites confirmed (`codex_response_priority` plus the four verdict sites) |
| 3 | Pass | Comment-filtered `codex_strip_not_only_idiom` count = 2 (definition + one call, inside `codex_response_is_blocking`) |
| 4 | Pass | Merge base `a0b8f8c7d9b63ea0f2ace945f78990579ceca828` resolved; `CODEX_BLOCKING_PATTERN`/`CODEX_MERGE_REFUSAL_PATTERN`/`CODEX_NEGATION_WORDS` diffs empty; full `codex_response_is_blocking` function-range diff empty (byte-identical) |
| 5 | Pass | All four `codex_footer_near_miss_*_safe_fails` scenarios exit 1 with the unrecognized-format safe-fail, resolving at their named site per `INFO:` trace; independence verified by reverting only the async-final gate in a scratch copy — only that scenario regressed to `TIMED_OUT`, the other three still passed |
| 6 | Pass | `No blocking issues found.` root comment exits 1, `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)` |
| 7 | Pass | Live-refetched PR #1489 root comment (2026-08-18, repo `26b5dada`) still matches the evidenced template verbatim; `codex_e1_real_pr1489_capture_approved` exits 0, `VERDICT: APPROVED` |
| 8 | Pass | Live-refetched PR #1490 review body still the generic wrapper with no clean-signal text; `codex_e2_real_pr1490_review_not_approved` (review-sourced, state `COMMENTED`) exits 1, safe-fail |
| 9 | Pass | `codex_e22_refusal_inside_footer_blocking` exits 1 with plain `VERDICT: NEEDS_REVISION` (blocking branch); isolated `codex_response_is_approved` call on the same body also returns non-zero on its own |
| 10 | Pass | `codex_e23_footer_opening_line_only_not_approved` exits 1, safe-fail — finding `3803545669`'s construction is rejected |
| 11 | Pass | `codex_e24a/b/c_footer_byte_mutation_*` (mid-sentence, before `</details>`, inside the URL) all exit 1, safe-fail |
| 12 | Pass | `codex_e21_filler_composed_hedge_not_approved` (`Looks good, or is it?`) exits 1, safe-fail |
| 13 | Pass | (a) Group APPROVED's two template-anchored members use distinct valid SHAs (`abcdefab12`, `abcabcabcabc1234567890`) and both exit 0/`APPROVED`; `codex_e7_full_length_sha_approved` (40-char) exits 0/`APPROVED`; (b) `codex_e5_short_sha_not_approved` (6-char, review-sourced), (c) `codex_e6_oversized_sha_not_approved` (41-char, review-sourced), and (d) `codex_e8_non_hex_sha_not_approved` (review-sourced) all exit 1, safe-fail |
| 14 | Pass | `codex-github.md` gained a "Verdict Classification" section stating the whole-body exact-template contract; Protocol 93's "Codex GitHub terminal evidence" block states the template-reproduction requirement; `CHANGELOG.md` `[Unreleased]` → `### Changed` carries the `**Conservative Codex verdict classifier** (#1491):` entry |
| 15 | Pass | `markdownlint-cli2` (changed docs + this runbook + `CHANGELOG.md`): 0 errors; `markdown-heuristic-lint.py`: exit 0; `workflow-shell-snippet-lint.py --base-ref origin/develop`: exit 0; `shellcheck --severity=warning` on both changed `.sh` files: only pre-existing, untouched warnings at unrelated lines (1699-1700 of the test file, unchanged by this PR) |
| 16 | Pass | Live-refetched PR #1494 comment `5333550055` still reads `:rocket:`; all 14 evidenced flavor tokens (including the real `:rocket:` and `Swish!` captures) exit 0/`APPROVED` under the bounded placeholder; a previously-unevidenced token (`Fantastic job!`) now exits 0/`APPROVED` (the intended behavior change); `*`-in-slot and backtick-in-slot both exit 1/safe-fail; 40-char slot exits 0/`APPROVED` (boundary inclusive), 41-char slot exits 1/safe-fail; newline-separated overflow exits 1/safe-fail |

**Platform tested**: macOS/BSD (Darwin 25.5.0)

**Tester**: developer agent (issue #1491 implementation; Step 16 added and then revised by the reviewer agent
after PR #1494's own Codex review falsified the single-flavor-literal assumption during Step 7a review, and
after a follow-up evidence sweep for that fix falsified the enumeration approach itself)

**Date**: 2026-08-18 (original); flavor-token enumeration correction 2026-08-18; bounded-placeholder correction
2026-08-18

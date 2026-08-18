# Conservative Verdict Classifier for `codex-github-reviewer.sh` — Implementation Plan

**Work item**: [Issue #1491](https://github.com/lhpaul/ai-dev-framework-template/issues/1491) — Refactor (plan-only path; no spec file exists and none is expected)
**Smoke test runbook**: [`docs/testing/workflow/1491-conservative-verdict-classifier.smoke-test.md`](../../../testing/workflow/1491-conservative-verdict-classifier.smoke-test.md)

---

## Template-Fit Check (Protocol 02 Step 0)

`.ai-dev-workflow.yaml` sets `template.is_template: true`, so this check is mandatory.

**Result**: **Pass — generic.** The work item changes `scripts/development-workflow/codex-github-reviewer.sh`,
which is framework workflow tooling the template itself ships and runs. The implementation language is
POSIX-ish Bash plus `grep`/`sed`/`awk`, which is the template's own toolchain. No downstream language,
runtime, or framework (React, Rails, Django, etc.) is referenced, and every downstream consumer that keeps
`codex-github` in `review.on_ready.github` benefits regardless of its stack. No human confirmation required.

---

## Summary

**Approach**: Flip `codex_response_is_approved` from a block-list ("look for approval vocabulary, then try to
detect every negation that could invalidate it") to an **allow-list** ("require an unhedged clean signal in the
opening paragraph, and disqualify on the presence of any negation, hedge, or actionable-verb token anywhere
else in the response"). This mirrors the already-accepted conservative pattern of `codex_response_has_fence_marker`,
where mere presence disqualifies and no attempt is made to parse structure. `codex_response_is_blocking` is kept
as a block-list because its failure direction is the opposite one and a false negative there is unsafe.

**Estimated complexity**: **M**

**Rationale**: The code change itself is still small relative to the surface it touches (one function
rewritten, four helpers added — `codex_strip_codex_footer`, `codex_response_first_paragraph`,
`codex_excise_clean_signals`, `codex_residue_is_closed_grammar` — three symbols deleted, one renamed, two new
closed-grammar constants). The work is medium because it changes a contract that 27 existing assertions
depend on: 9 test scenarios change their expected verdict, 1 changes its fixture text, and new regression
coverage must be added for the allow-list contract, its parser edge cases, and — added during the Step 7
review round — the closed residue grammar that makes the disqualifier list's non-exhaustiveness actually safe
(Decision 2). Every disposition must be justified individually so a reviewer can tell an intended contract
change from a regression.

**Dependencies**: None. PR #1490 is merged (`55b2df5d` is its merge commit on `develop`); this plan builds on
top of it and must not modify its commits.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `55b2df5d` |
| Reviewer script size | `wc -l scripts/development-workflow/codex-github-reviewer.sh` | 1996 lines |
| Symbols in scope | `grep -rln "CODEX_NEGATED_APPROVAL\|CODEX_APPROVAL_PATTERN\|CODEX_NEGATION_WORDS\|codex_strip_not_only_idiom" .` | `CHANGELOG.md`, `scripts/development-workflow/codex-github-reviewer.sh`, `scripts/development-workflow/tests/test-pr-review-loop.sh` — no agent, skill, protocol, or doc file references these symbols |
| Test-harness location | `grep -rln "codex_response_is_approved\|codex-github-reviewer" scripts/development-workflow/tests/` | `scripts/development-workflow/tests/test-pr-review-loop.sh` only (single harness) |
| Assertion inventory | `python3 -c "…count run_test lines…"` on `test-pr-review-loop.sh` | 628 total `run_test` assertions; 247 `codex_*` assertions; 27 assert `VERDICT: APPROVED` (re-verified during Step 7a review; independently reproduced by parsing every `run_test "..."` call) |
| Loop coupling | `grep -n "codex-github-reviewer\|codex_response" scripts/development-workflow/pr-review-loop.sh` | single hit at line 790 (script path resolution). `pr-review-loop.sh` consumes only the verdict line and exit code, so no loop change is required |
| Real clean Codex root comment | `gh api repos/lhpaul/ai-dev-framework-template/issues/1489/comments --jq '.[] \| select(.user.login\|test("codex";"i")) \| .body'` | `Codex Review: Didn't find any major issues. Swish!` + `**Reviewed commit:** \`87aaefceff\`` + a `<details>` "About Codex in GitHub" footer that contains a **bulleted list** and straight-quoted phrases |
| Real findings Codex review | `gh api repos/lhpaul/ai-dev-framework-template/pulls/1490/reviews --jq '…'` | body starts `### 💡 Codex Review` (heading marker), `state` is `COMMENTED`, same `<details>` footer |
| Predicate dry-run on the real clean body | prototype `tr`/`sed`/`grep` pipeline in a scratch script (see "Predicate validation" below) | `CLEAN_PRESENT=yes`, no disqualifier matched, verdict-eligible `APPROVED` both with and without footer truncation |
| Open PRs on the same surface | `gh pr list --state open --limit 50` | zero open pull requests in the repository at check time |
| Repository mode | `grep -nE "^mode:\|^workflow_hub:\|^product_repo:" .ai-dev-workflow.yaml` | no key present → `single_repo`; this repository owns the plan |
| Real clean Codex root comment — re-verified during Step 7 review round | `gh api repos/lhpaul/ai-dev-framework-template/issues/1489/comments --jq '.[] \| select(.user.login\|test("codex";"i")) \| .body'` | Unchanged: `Codex Review: Didn't find any major issues. Swish!` + `**Reviewed commit:** \`87aaefceff\`` + the same `<details>` "About Codex in GitHub" footer. Still Valid |
| Real findings Codex review — re-verified during Step 7 review round | `gh api repos/lhpaul/ai-dev-framework-template/pulls/1490/reviews --jq '…'` | Unchanged: body opens `### 💡 Codex Review\n\nHere are some automated review suggestions for this pull request.`, `state` is `COMMENTED`, same `<details>` footer, no clean-signal text in the visible portion (A1 already fails this body regardless of A3). Still Valid |
| Tooling identity confirmed for this review round | `sed 2>&1`, `grep --version`, `awk --version` (via `/usr/bin/{sed,grep,awk}` explicitly) | BSD `sed` (rejects GNU long-option syntax), `grep (BSD grep, GNU compatible) 2.6.0-FreeBSD`, one-true-awk `20200816` — confirms the same macOS BSD toolchain this plan already targets |

### Predicate validation (reproducible)

The decision rule below was executed against the real captured Codex bodies and against every existing
`VERDICT: APPROVED` fixture body on macOS (BSD `sed`, BSD `grep`, BSD `awk`) before this plan was written.
The implementer must re-run the same checks on GNU tooling in CI. The prototype used:

<!-- workflow-shell-contract: bash -->

```bash
CLEAN='(approved|lgtm|looks[[:space:]]+good|didn.t find[[:space:]]+any major[[:space:]]+issues|no[[:space:]]+blocking[[:space:]]+issues?)'
lowered=$(LC_ALL=C tr '[:upper:]' '[:lower:]' <<< "$body")
residue=$(sed -E "s/(^|[^[:alnum:]])${CLEAN}([^[:alnum:]]|\$)/\1 \3/g" <<< "$lowered")
```

Observed residues (clean signals excised) for the two real bodies and the largest synthetic fixtures were
`codex review: . swish!`, `  found. the codex usage limit handling looks correct.`, and
`  found. the docs accurately quote: to use codex here, create an environment for this repo.` —
5, 8, and 16 residue words respectively. This is the evidence behind the
"no length cap" decision recorded under Decision 4.

**Note (Step 7 review round):** the prototype above uses the boundary class `[^[:alnum:]]`, matching the
version of this plan reviewed at Step 7a. That boundary class was found to be incorrect (Codex GitHub finding
`3800167492` — see Decision 2's "Boundary correction" note) and is **not** what the Code Samples section
below ships; the shipped `CODEX_CLEAN_SIGNAL_EXCISION` uses `[^[:alnum:]_]`. The observed residue word counts
above are unaffected by that correction (none of the three sample bodies contain an underscore), so Decision
4's "no length cap" conclusion still holds, but the illustrative regex literal above is intentionally left as
originally written for historical accuracy — do not copy it into an implementation; use the Code Samples
section instead. The residue word counts above were also re-derived, this round, under the full tightened A3
(disqualifier scan plus the new closed residue grammar) with the same result: all three residues still pass —
see the "Test disposition" Group A re-verification note.

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved artifact base branch | `develop` | Parent orchestrator handoff for issue #1491 plus the branching section of `AGENTS.md` | 2026-08-17, repo `55b2df5d` | This invocation (issue #1491) plus same-surface open PRs touching `scripts/development-workflow/codex-github-reviewer.sh`; `gh pr list --state open` returned zero open PRs | `Verified` |
| Artifact owner / repository mode | `single_repo` — this repository owns the plan | `.ai-dev-workflow.yaml` (no `mode`, `workflow_hub`, or `product_repo` key) | 2026-08-17, repo `55b2df5d` | Current invocation only | `Verified` |
| Ready-phase reviewer that consumes this classifier | `review.on_ready.github: [codex-github]` | `.ai-dev-workflow.yaml` | 2026-08-17, repo `55b2df5d` | Current invocation; no open PR modifies `.ai-dev-workflow.yaml` | `Verified` |
| Codex clean-response wire format the allow-list must accept | `Codex Review: Didn't find any major issues. <flavor sentence>` followed by a `**Reviewed commit:**` marker and an "About Codex in GitHub" `<details>` footer | Live GitHub API responses on PRs #1489 and #1490 | 2026-08-17, repo `55b2df5d` | Current invocation; vendor-controlled surface, re-verified at implementation start per Protocol 02 | `Verified` |

No conflict was found. The vendor wire-format row is the one assumption a third party (OpenAI) can change
without notice; the implementation-start re-check for it is Step 1 of the Implementation Order.

---

## Background: why the current design does not converge

`codex_response_is_approved` today does three things in sequence: bail out if a fence marker is present, strip
quoted spans and the "not only" idiom, reject if `CODEX_NEGATED_APPROVAL_PATTERN` matches, then accept if
`CODEX_APPROVAL_PATTERN` matches. `CODEX_NEGATED_APPROVAL_PATTERN` is
`CODEX_NEGATION_WORDS` + a same-clause span + `CODEX_NEGATED_APPROVAL_TARGET_WORDS`. Both vocabularies are
finite enumerations of an infinite natural-language space, so every review cycle that finds one more synonym
(`wouldn't`, `mustn't`, `unable to`, the noun "approval", "cannot be merged") is a genuine bug in the
*unsafe* direction: a missing entry produces a false `APPROVED`.

The same file already solved an identical failure mode once, for Markdown fences: after five rounds of
increasingly precise fence parsing, `codex_response_has_fence_marker` abandoned precision entirely and now
treats the mere presence of a fence-opener as disqualifying. This plan applies that same inversion to the
approval verdict.

---

## Decisions

### Decision 1 — `APPROVED` requires an allow-listed clean signal; everything else safe-fails

A response is `APPROVED` only when **all three** conditions hold. Each is a checkable predicate, not a
judgement call:

- **A1 — Clean signal present in the opening paragraph.** After footer truncation, quoted-span stripping,
  and lowercasing, the **first non-empty paragraph** (lines up to the first blank line, leading blank lines
  skipped) must contain at least one **boundary-anchored** occurrence of `CODEX_CLEAN_SIGNAL_PATTERN` — tested
  via `CODEX_CLEAN_SIGNAL_EXCISION`, not the raw alternation. A raw substring test would match `approved`
  inside `unapproved` (edge case E1) and reintroduce a false `APPROVED`. The boundary class is
  `[^[:alnum:]_]` (underscore is treated as a word character, matching `grep -E`'s `\b`), not bare
  `[^[:alnum:]]` — see the "Boundary correction" note below Decision 2.
- **A2 — No fence marker anywhere.** `codex_response_has_fence_marker` on the **raw, untruncated** body must
  be false. Unchanged from today.
- **A3 — Closed-grammar, disqualifier-free residue.** Two independent checks, both against the
  footer-truncated, quote-stripped, lowercased body (the **residue** after every occurrence of
  `CODEX_CLEAN_SIGNAL_PATTERN` is iteratively excised via `CODEX_CLEAN_SIGNAL_EXCISION` — see the "Iterative
  excision" note below Decision 2):
  1. The residue must not match `CODEX_APPROVAL_DISQUALIFIER_PATTERN` (unchanged mechanism from the original
     draft of this plan).
  2. **New — the closed clean-response grammar.** Every sentence (and, inside a sentence that itself carries
     a clean signal, every comma/colon/semicolon-delimited clause) that does **not** itself carry a clean
     signal must, once punctuation and `CODEX_RESIDUE_FILLER_WORD_PATTERN` tokens are stripped, reduce to at
     most one bare token, or otherwise begin with an allow-listed `CODEX_RESIDUE_STARTER_PATTERN`
     subject/determiner. See Decision 2 for why check 2 exists and what it does not close.

If any condition fails, `codex_response_is_approved` returns non-zero and the caller falls through to the
existing safe-fail branch (`VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)`), or to the
blocking branch when `codex_response_is_blocking` already matched earlier in the chain.

**Excision before scanning is the mechanism that makes the disqualifier check sound.** The recognized clean
phrases themselves contain words that are otherwise disqualifiers (`no` in "no blocking issues", `didn't` in
"didn't find any major issues"). Removing them first lets the disqualifier list be aggressive without
self-contradiction, and removes the need for the existing `didn't`-is-deliberately-excluded special case in
`CODEX_NEGATION_WORDS`. **The closed-grammar check (2) is what makes non-exhaustiveness of the disqualifier
list itself safe — not the fact that the classifier is an allow-list.** See Decision 2.

### Decision 2 — Non-exhaustiveness of the disqualifier list is safe *because the residue grammar is closed*

**Correction from the version of this plan reviewed at Step 7a (Codex GitHub finding `3800167486`,
P1/blocking).** The original text of this decision argued that non-exhaustiveness of
`CODEX_APPROVAL_DISQUALIFIER_PATTERN` was safe merely because the classifier is an allow-list. That argument
does not hold on its own: a response like `Looks good. Remove the authentication check.` satisfies A1 (a
clean signal in the opening paragraph), and after excision the residue `remove the authentication check.`
matches no entry in `CODEX_APPROVAL_DISQUALIFIER_PATTERN` (`remove` is not an enumerated actionable verb), so
the old A3 (disqualifier-scan only) reported `APPROVED` — reintroducing exactly the open-ended-enumeration
correctness dependency this plan exists to eliminate, just moved from the negation vocabulary to the
actionable-verb vocabulary. Verified: `Looks good. Remove the authentication check.` returns `APPROVED` under
the disqualifier-scan-only A3, and under the tightened A3 (closed grammar, below) it correctly returns
`NEEDS_REVISION` — reproduced on BSD `sed`/`grep`/`awk` during this review round, and the fixed behavior is
now the `codex_unenumerated_actionable_sentence_after_signal_root_comment` regression (edge case E19).

**What actually makes non-exhaustiveness safe is A3 check 2, the closed residue grammar — not the fact that
the classifier is called an allow-list.** A grammar is "closed" when it defines the finite set of shapes a
passing residue may take, rather than merely testing the absence of known-bad content. A3 check 2 is closed
in exactly this sense: a sentence (or, inside a signal-bearing sentence, a comma/colon/semicolon clause) that
lacks its own clean signal is required to reduce, after filler stripping, to at most one bare token or to
begin with one of a small enumerated `CODEX_RESIDUE_STARTER_PATTERN` subject/determiner. Both bounds
(`CODEX_RESIDUE_FILLER_WORD_PATTERN`, `CODEX_RESIDUE_STARTER_PATTERN`) are drawn from English's closed word
classes — articles, a handful of prepositions/conjunctions, and demonstrative/locative pronouns — which are
finite and do not grow the way the open-class negation/hedge/actionable vocabulary does. Enumerating a closed
class exhaustively is a categorically different, safe exercise; enumerating an open class never converges,
which is the entire thesis of this plan (see "Background" above).

**Residual, disclosed gap — the residue grammar is not perfectly closed.** A single bare open-class token
left over in a non-signal sentence/clause (the "at most one token" branch above) is tolerated without content
review, because a zero-tolerance grammar was verified during this review round to reject the plan's own real
captured clean root comment (PR #1489: `Codex Review: Didn't find any major issues. Swish!` — the residual
`swish` token, after excising the recognized clean signal and known vendor labels, is a single open-class
word that a strict "filler-only" grammar has no way to distinguish from an unenumerated one-word imperative).
Consequently, a single-word directive with no object (for example `Approved. Revert.`) is a known, narrow,
accepted exposure: verified during this review round to still return `APPROVED`. This is a real, disclosed
trade-off, not a silently reintroduced gap — it is dramatically narrower than the exposure this decision
replaces (any number of unenumerated words in a trailing clause, versus exactly one bare word with no
object), and it is recorded in Risks & Mitigations below. **This is the one item in this plan that a human
reviewer should explicitly confirm is an acceptable trade-off**, since narrowing it further (for example by
also requiring the single leftover token to be checked against a curated flavor-word list) would reintroduce
either an open-ended vocabulary problem or a rejection of the real captured clean response, and this plan
does not attempt to resolve that tension unilaterally.

**Reviewers must not read the non-exhaustive disqualifier list, on its own, as a reintroduction of the old
bug.** The correctness argument no longer depends on the disqualifier list being complete, but it now depends
on the closed-grammar check instead. Concretely:

- Extending `CODEX_APPROVAL_DISQUALIFIER_PATTERN` is **always safe** and never required for correctness. It
  can be done at any time without re-analysis; it only moves the false-`NEEDS_REVISION` rate.
- Extending `CODEX_CLEAN_SIGNAL_PATTERN` is **one of the changes that can create new false-`APPROVED`
  surface** and must receive the same scrutiny the old negation list used to receive. This plan therefore
  adds **no** new clean-signal alternatives: the allow-list keeps exactly the alternatives that
  `CODEX_APPROVAL_PATTERN` has today.
- Extending `CODEX_RESIDUE_FILLER_WORD_PATTERN` or `CODEX_RESIDUE_STARTER_PATTERN` is **the other change that
  can create new false-`APPROVED` surface**, for the same reason: both widen what the closed grammar treats
  as inert. Any addition must be a genuinely closed-class word (an article, preposition, conjunction, or
  demonstrative/locative pronoun) or a specific, reviewed vendor-identity token — never a general content
  word — and must receive the same scrutiny as a `CODEX_CLEAN_SIGNAL_PATTERN` change.

**Boundary correction (Codex GitHub finding `3800167492`, P2).** `CODEX_CLEAN_SIGNAL_EXCISION`'s boundary
class must be `[^[:alnum:]_]`, not `[^[:alnum:]]`: `_` is a word character for `grep -E`'s `\b` (used by the
disqualifier patterns), but the old bare `[^[:alnum:]]` class treated `_` as a boundary character, so
`This remains un_approved.` supplied an A1 clean signal (`approved` matched with `_` accepted as a preceding
boundary) and excision left `this remains un_ .`, which contains no disqualifier and returned `APPROVED`.
Verified: the old boundary class matches `approved` inside `un_approved` on BSD `sed`; `[^[:alnum:]_]` does
not. Fixed edge case E1 already covers the no-underscore prefix (`unapproved`); the underscore-prefixed
variant is new edge case E16, covered by regression scenario
`codex_underscore_prefixed_lookalike_root_comment`.

**Iterative excision (Codex GitHub finding `3800167494`, P2).** A single `sed 's/.../.../g'` pass over
`CODEX_CLEAN_SIGNAL_EXCISION` does not excise every occurrence when two clean signals are adjacent: `sed`'s
`g` flag resumes scanning immediately after the end of the previous match, so the boundary character the
first match's trailing group consumed is unavailable to satisfy the next match's leading-boundary group.
Verified: a single pass over `approved no blocking issues` excises only `approved`, leaving
`no blocking issues` — which then matches `CODEX_APPROVAL_NEGATION_PATTERN`'s `\bno\b` — un-excised, and the
response incorrectly returns `NEEDS_REVISION` (a false-`NEEDS_REVISION`, not a safety bug, but it silently
breaks a response composed entirely of clean signals — e.g. `Approved no blocking issues found.`). The fix is
iterative excision to a fixed point (`codex_excise_clean_signals` below), bounded at 25 iterations as a
defensive cap; verified to converge in 3 iterations even against a body with 20 repeated adjacent occurrences,
with no measurable performance cost. New edge cases E17 (`Approved no blocking issues found.`) and E18
(`LGTM. Didn't find any major issues.`, plus a no-space comma variant) cover this, via regression scenarios
`codex_adjacent_signal_second_contains_no_root_comment` and
`codex_adjacent_signal_second_contains_didnt_root_comment`.

### Decision 3 — Composition with the GitHub review `state` short-circuit from PR #1490

PR #1490 threaded GitHub's structured review `state` through evidence selection. That behavior is **preserved
verbatim**; the allow-list is layered underneath it, not in place of it. The resulting precedence, in the
order each verdict site already evaluates it:

1. `state == "CHANGES_REQUESTED"` on review-sourced evidence → blocking, short-circuit, no prose parsing.
   Unchanged (`codex_response_priority`, `codex_combine_terminal_evidence`, and all four verdict sites).
2. `codex_response_is_blocking(body)` → blocking. Unchanged block-list (see Decision 5).
3. `codex_response_is_usage_limit` / `codex_response_is_environment_error` → unavailable. Unchanged.
4. `codex_response_is_approved(body)` → `APPROVED`. **This is the only function whose contract changes.**
5. Anything else → safe-fail `NEEDS_REVISION`. Unchanged.

Because the classifier only ever moves responses **out of** tier 4 and into tier 5, it cannot weaken the
`CHANGES_REQUESTED` short-circuit, cannot change `codex_response_priority`'s tier ordering (3 > 2 > 1 > 0),
and cannot let blocking evidence be hidden behind an availability notice.

**Explicitly considered and deferred**: adding `state == "APPROVED"` as an independent sufficient condition
(the symmetric complement of PR #1490's `CHANGES_REQUESTED` short-circuit). It is deferred because the
observed Codex wire format submits clean results as `COMMENTED` reviews or root comments, never as an
`APPROVED` review, so the path would be dead code today while widening the approval surface. If the vendor
ever starts submitting `APPROVED` reviews, that is the right follow-up and should be filed as its own item.

### Decision 4 — "Low complexity" is expressed as position plus token-class absence, not a length cap

A sentence-count or word-count cap was considered as the "low complexity" criterion and **rejected**:

- Measured residue sizes are 5 words (real clean root comment), 8 words, and 16 words (largest existing
  fixture). Any cap has to sit well above the largest real value, at which point it stops catching anything a
  token-class disqualifier does not already catch.
- Two existing regression tests deliberately approve 200 000-character bodies to prove the classifier cannot
  SIGPIPE its own input. A length cap would flip them and delete that coverage.
- A cap is an operational cliff: a slightly chattier vendor response format would fail every PR at once,
  with no diagnostic pointing at the cap.

The A1 "clean signal must appear in the opening paragraph" rule delivers the structural-complexity guarantee
instead: a long structured findings report cannot approve by burying a clean-sounding summary line at the
bottom. Every real and synthetic clean body verified above satisfies A1.

### Decision 5 — `codex_response_is_blocking` stays a block-list

`codex_response_is_blocking` is **kept**, and `CODEX_BLOCKING_PATTERN`, `CODEX_MERGE_REFUSAL_PATTERN`, and
`CODEX_NEGATION_WORDS` are **kept unchanged**. Its only edit is dropping the now-deleted
`codex_strip_not_only_idiom` call. Reasons:

- **The failure directions are not symmetric.** A false negative from `is_approved` is safe (extra
  `NEEDS_REVISION`); a false negative from `is_blocking` is unsafe. Protocol 93 and
  `codex_combine_terminal_evidence` both depend on "blocking always wins outright" so that an actionable
  finding is never hidden behind a usage-limit or environment-error `UNAVAILABLE` verdict. Flipping
  `is_blocking` to an allow-list would break that invariant. The file already records this asymmetry: the
  fence guard was deliberately *not* applied to `is_blocking`.
- **Its vocabulary gaps stop being correctness bugs.** `CODEX_MERGE_REFUSAL_PATTERN` existed mainly so that
  "This looks good at first glance, but this should not be merged" would not return `APPROVED`. Under the
  allow-list, `at first glance`, `but`, and `not` each independently disqualify that response. A future
  unenumerated merge-refusal synonym now costs only a tier-3-vs-tier-2 nuance in the rare
  blocking-versus-availability-notice tie, never a false `APPROVED`. Deleting the pattern would trade that
  small nuance for a real regression in the "blocking wins over an unavailable notice" invariant, so it stays.

`codex_strip_not_only_idiom` is deleted from **both** call sites. It exists only to avoid a false
`NEEDS_REVISION` on the rhetorical "not only X, but Y" construction. Keeping a bespoke idiom stripper while
deliberately accepting a higher false-`NEEDS_REVISION` rate everywhere else is incoherent, and the idiom is
one of the enumerated constructs issue #1491 names as evidence that enumeration does not converge.

### Decision 6 — The vendor `<details>` footer is truncated before approval classification only

Every real Codex response ends with a static "About Codex in GitHub" `<details>` footer containing a bulleted
list, straight-quoted phrases, and marketing prose. Today it is inert; nothing in it matches the current
patterns. Under the new aggressive disqualifier list it becomes a standing hazard: one vendor-side wording
change ("Reviews are not triggered for draft pull requests") would disqualify every clean response at once.

`codex_strip_codex_footer` truncates the body at the first line matching the **actual vendor footer marker**
— `about[[:space:]]+codex[[:space:]]+in[[:space:]]+github` (case-insensitive) — and is applied **only inside
`codex_response_is_approved`**. It must not be applied anywhere else, because:

- `codex_response_reviews_current_head` must see the original body for SHA extraction.
- The acknowledgement branch (`grep -qi "If Codex has suggestions, it will comment; otherwise it will react with"`)
  matches text that lives **inside** the footer; truncating before that check would break acknowledgement
  detection.
- `codex_response_is_blocking` must keep scanning the full body, which is also the mitigation for the only
  risk truncation introduces (a refusal placed after the footer): blocking is evaluated before approval at
  every verdict site.

**Correction from the version of this plan reviewed at Step 7a (Codex GitHub finding `3800167489`, P1/
blocking).** The original text of this decision truncated at the first line matching the generic `<details`
(case-insensitive), not the specific vendor marker. That is over-broad: any `<details>` block anywhere in the
response — not just the real vendor footer — silently disappears from the residue before A3 ever runs.
Verified: a response reading `Looks good.` followed by a **non-vendor** `<details>` block containing
`Rename the unsafe function.` loses that instruction to truncation under the generic-marker version; the
instruction is invisible to both A3's disqualifier scan and its closed grammar because it is truncated away
before either runs, and (since `rename` is not in `CODEX_BLOCKING_PATTERN`/`CODEX_MERGE_REFUSAL_PATTERN`
either) `codex_response_is_blocking` does not catch it either, so the response incorrectly returns
`APPROVED`. Anchoring on the specific `about codex in github` marker fixes this: the real vendor footer still
truncates correctly (re-verified against the live `<details> <summary>ℹ️ About Codex in GitHub</summary>`
body captured from PR #1489 during this review round), while the non-vendor `<details>` block above is left
in the residue, where A3's closed grammar (Decision 2) correctly rejects it — `rename the unsafe function` is
a sentence with no clean signal, more than one leftover open-class token, and no allow-listed starter, so it
fails check 2 and the response correctly returns `NEEDS_REVISION`. This is deliberately a **precision** fix,
not something the closed grammar alone can substitute for: over-truncation removes the offending text before
either A3 check ever sees it, so a stray `<details>` block would still hide content even under a maximally
strict grammar. New edge case E20 (`codex_nonfooter_details_block_not_truncated_root_comment`) covers this.

---

## Layer-by-Layer Changes

Only the tooling layer of this repository is affected. There is no database, API, frontend, or infrastructure
surface in scope.

### Shell tooling — `scripts/development-workflow/codex-github-reviewer.sh`

**Shell contract**: `bash` (the script declares `#!/usr/bin/env bash` and uses `<<<` here-strings, `local`,
and `[[ ]]`-free POSIX tests). No portable `bash-zsh` snippet is introduced.

- [ ] **Rename** `CODEX_APPROVAL_PATTERN` → `CODEX_CLEAN_SIGNAL_PATTERN`. Same alternatives, no additions,
      no removals. The rename signals the contract change (it is now an allow-list used for excision, not a
      substring accept-test) and there are no external consumers of the old name.
- [ ] **Delete** `CODEX_NEGATED_APPROVAL_TARGET_WORDS` and `CODEX_NEGATED_APPROVAL_PATTERN`, together with
      their multi-paragraph rationale comments. Replace the comment block with a short note pointing at the
      allow-list rationale so the history is not lost.
- [ ] **Delete** `codex_strip_not_only_idiom` and both of its call sites.
- [ ] **Keep unchanged**: `codex_response_has_fence_marker`, `codex_strip_quoted_spans`,
      `codex_response_is_usage_limit`, `codex_response_is_environment_error`,
      `codex_response_reviews_current_head`, `codex_response_priority`, `codex_select_terminal_evidence`,
      `codex_select_review_evidence`, `codex_combine_terminal_evidence`, `CODEX_BLOCKING_PATTERN`,
      `CODEX_NEGATION_WORDS`, `CODEX_MERGE_REFUSAL_PATTERN`, and all four verdict-emission sites.
- [ ] **Add** `CODEX_CLEAN_SIGNAL_EXCISION` — a portable word-boundary wrapper around the allow-list. It uses
      explicit character classes rather than `\b`, because `\b` is a GNU extension that BSD `sed` (macOS
      default) does not support, and this wrapper — unlike `CODEX_CLEAN_SIGNAL_PATTERN` itself — is fed to
      `sed` at the A3 excision site. It is also the pattern used at the A1 grep presence check, not the raw
      `CODEX_CLEAN_SIGNAL_PATTERN`: `\b` remains fine in `grep -E` in general (the disqualifier patterns below
      use it, and the file already documents it as verified across BSD grep, GNU grep, and ugrep), but
      `CODEX_CLEAN_SIGNAL_PATTERN` specifically must stay `\b`-free because it is shared with the sed-facing
      wrapper — see the code sample and its inline comments. The boundary class is `[^[:alnum:]_]` (see the
      "Boundary correction" note under Decision 2, not bare `[^[:alnum:]]`).
- [ ] **Add** `CODEX_APPROVAL_NEGATION_PATTERN`, `CODEX_APPROVAL_HEDGE_PATTERN`,
      `CODEX_APPROVAL_ACTIONABLE_PATTERN`, and the composite `CODEX_APPROVAL_DISQUALIFIER_PATTERN`
      (the three groups plus `CODEX_BLOCKING_PATTERN`). These must be defined **after** the line that appends
      `CODEX_MERGE_REFUSAL_PATTERN` to `CODEX_BLOCKING_PATTERN`, since the composite reads it.
- [ ] **Add** `CODEX_RESIDUE_FILLER_WORD_PATTERN` and `CODEX_RESIDUE_STARTER_PATTERN` — the closed-class
      filler/starter constants A3 check 2 (the closed residue grammar) is built on. See Decision 2.
- [ ] **Add** `codex_strip_codex_footer`, anchored on the actual `about codex in github` marker (see the
      "Correction" note under Decision 6), not a generic `<details` match.
- [ ] **Add** `codex_response_first_paragraph`.
- [ ] **Add** `codex_excise_clean_signals` — the iterative excision helper (see the "Iterative excision" note
      under Decision 2).
- [ ] **Add** `codex_residue_is_closed_grammar` — A3 check 2 (see Decision 2 and the Code Samples section).
- [ ] **Rewrite** `codex_response_is_approved` per Decision 1.
- [ ] **Update** the file-header "Verdict parsing" comment block (currently describing path 2 as "Approval
      signals present → APPROVED") to state the allow-list contract, the three conditions (including A3's two
      checks), and the deliberate false-`NEEDS_REVISION` tradeoff.

### Tests — `scripts/development-workflow/tests/test-pr-review-loop.sh`

- [ ] Retarget the expected verdict of every scenario listed in Group C of "Test disposition" below.
- [ ] Retarget the fixture body of `codex_inline_backtick_pair_stays_approved_root_comment` (see the updated
      Group B row — the retargeted body itself changed again during this review round; use the current one).
- [ ] Add the new scenarios listed in "Testing Strategy" (17 total, including the 5 added during this review
      round for findings `3800167486`, `3800167489`, `3800167492`, and `3800167494`).
- [ ] Update the explanatory comment above every retargeted scenario so it states the **new** contract reason,
      not the superseded PR #1490 finding. Do not delete the historical finding references — rewrite them as
      "previously fixed by X; now covered structurally by the allow-list".

### Documentation

- [ ] `docs/workflow/development-workflow/integrations/codex-github.md`
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
- [ ] `CHANGELOG.md`

See "Documentation Updates" for exactly what changes in each.

---

## Code Samples

<!-- Illustrative — adapt during implementation. -->

**Revised during the Step 7 review round** to close four Codex GitHub findings
(`3800167486`/`3800167489` P1-blocking, `3800167492`/`3800167494` P2). Every regex and helper below was
re-executed against the same macOS BSD toolchain this plan already targets (`sed`, `grep`, `awk`, invoked via
their `/usr/bin/` paths to avoid any interactive-shell aliasing — confirmed BSD: `sed` rejects GNU's
long-option `--` syntax, `grep --version` reports `BSD grep, GNU compatible`, `awk --version` reports the
one-true-awk `20200816` build). See Decision 2 and Decision 6 for the rationale behind each change; this
block is the resulting code.

```bash
# Illustrative — adapt during implementation.
# Allow-list: the SAME five alternatives CODEX_APPROVAL_PATTERN has today,
# renamed, with the \b word-boundary anchors on `approved`/`lgtm`/`looks good`
# LIFTED OUT of the alternation and pushed into the shared boundary wrapper
# below instead. Do not re-add \b here: this literal is reused verbatim
# inside CODEX_CLEAN_SIGNAL_EXCISION, which sed also consumes, and BSD sed
# (macOS default) does not support \b — it neither errors nor matches, so an
# embedded \b would silently make the A3 excision stop excising genuine clean
# signals on macOS (verified: `sed -E 's/\bapproved\b/X/' <<< "approved"`
# leaves the input unchanged on BSD sed). The boundary wrapper below restores
# equivalent boundary-safety using only portable [^[:alnum:]_] classes.
CODEX_CLEAN_SIGNAL_PATTERN='(approved|lgtm|looks[[:space:]]+good|didn.t find[[:space:]]+any major[[:space:]]+issues|no[[:space:]]+blocking[[:space:]]+issues?)'
# Portable word-boundary wrapper (no \b — unsupported by BSD sed). Used at
# BOTH classifier call sites below: A1's grep presence test AND A3's sed
# excision. Do not call grep or sed with the raw CODEX_CLEAN_SIGNAL_PATTERN
# directly at either site — see the A1 comment in codex_response_is_approved
# for the false-APPROVED gap that reintroduces.
#
# The boundary class is [^[:alnum:]_], NOT bare [^[:alnum:]] (Codex GitHub
# finding 3800167492): `_` is a word character for grep -E's \b (used by the
# disqualifier patterns below), so treating `_` as a boundary here let
# "This remains un_approved." supply an A1 clean signal — verified on BSD sed
# with the bare class; [^[:alnum:]_] correctly leaves it unmatched.
CODEX_CLEAN_SIGNAL_EXCISION='(^|[^[:alnum:]_])'"${CODEX_CLEAN_SIGNAL_PATTERN}"'([^[:alnum:]_]|$)'

# Disqualifiers. Deliberately NON-EXHAUSTIVE: see Decision 2. Lowercase-only,
# because the residue is lowercased before scanning.
CODEX_APPROVAL_NEGATION_PATTERN='(\bnot\b|[[:alpha:]]n.t\b|\bnever\b|\bcannot\b|\bunable\b|\bwithout\b|\bno\b|\bnone\b|\bnor\b|\bneither\b|\blacks?\b|\blacking\b)'
CODEX_APPROVAL_HEDGE_PATTERN='(\bbut\b|\bhowever\b|\balthough\b|\bthough\b|\bunless\b|\buntil\b|\bpending\b|\bcaveats?\b|\bnits?\b|\bminor\b|\bnonetheless\b|\bnevertheless\b|\bexcept\b|\baside from\b|\bapart from\b|\bother than\b|\bassuming\b|\bat first glance\b)'
CODEX_APPROVAL_ACTIONABLE_PATTERN='(\bshould\b|\bmust\b|\bneeds?\b|\brequires?d?\b|\baddress\b|\bconsider\b|\brecommends?\b|\bsuggests?\b|\brevise\b|\bbefore merging\b)'
CODEX_APPROVAL_DISQUALIFIER_PATTERN="(${CODEX_APPROVAL_NEGATION_PATTERN}|${CODEX_APPROVAL_HEDGE_PATTERN}|${CODEX_APPROVAL_ACTIONABLE_PATTERN}|${CODEX_BLOCKING_PATTERN})"

# A3 check 2 — the closed residue grammar (Codex GitHub finding 3800167486;
# see Decision 2). Both patterns are drawn from English's CLOSED word
# classes (articles, a handful of prepositions/conjunctions, demonstrative/
# locative pronouns) plus a small set of specific, reviewed vendor-identity
# tokens ("codex", "review", "reviewed", "commit" — the literal labels the
# real vendor wire format uses, e.g. "Codex Review:" / "**Reviewed
# commit:**"). Extending either pattern needs the SAME scrutiny as extending
# CODEX_CLEAN_SIGNAL_PATTERN — see Decision 2's "Reviewers must not..." list.
CODEX_RESIDUE_FILLER_WORD_PATTERN='^(a|an|the|and|or|to|of|in|on|for|at|is|it|its|this|that|codex|review|reviewed|commit)$'
CODEX_RESIDUE_STARTER_PATTERN='^[[:space:]]*(the|this|that|these|those|it|its|here|there|no|all|everything|nothing|codex)([^[:alnum:]_]|$)'

# Truncates Codex's static "About Codex in GitHub" <details> footer. Applied
# ONLY inside codex_response_is_approved (see Decision 6).
#
# Anchored on the ACTUAL vendor marker (Codex GitHub finding 3800167489), not
# a generic `<details` match: a generic match truncates ANY <details> block,
# including one an attacker (or an unrelated bot) placed elsewhere in the
# body, silently hiding its content from A3 entirely. Verified against the
# live footer captured from PR #1489 (`<details> <summary>ℹ️ About Codex in
# GitHub</summary>`) — still truncates correctly — and against a synthetic
# non-vendor `<details>` block, which this version correctly leaves intact
# for A3 to evaluate.
codex_strip_codex_footer() {
  awk 'tolower($0) ~ /about[[:space:]]+codex[[:space:]]+in[[:space:]]+github/ { exit } { print }' <<< "$1"
}

# First non-empty paragraph, leading blank lines skipped.
codex_response_first_paragraph() {
  awk 'NF == 0 { if (started) exit; next } { started = 1; print }' <<< "$1"
}

# Iteratively excises every CODEX_CLEAN_SIGNAL_EXCISION occurrence (Codex
# GitHub finding 3800167494). A single sed 's///g' pass is NOT sufficient:
# sed's g flag resumes scanning immediately after the previous match, so a
# clean signal immediately adjacent to another one shares the boundary
# character the first match's trailing group already consumed, and the
# second match's leading-boundary group has nothing left to match — verified
# on BSD sed: a single pass over "approved no blocking issues" excises only
# "approved", leaving "no blocking issues" (which then matches
# CODEX_APPROVAL_NEGATION_PATTERN's \bno\b) un-excised. Looping to a fixed
# point closes this. Bounded at 25 iterations as a defensive cap; verified to
# converge in 3 iterations even against 20 repeated adjacent occurrences,
# with no measurable performance cost, and unaffected by the existing
# 200 000-character SIGPIPE-safety fixtures (verified: sub-second).
codex_excise_clean_signals() {
  local text="$1" prev iterations=0
  while :; do
    prev="$text"
    text=$(sed -E "s/${CODEX_CLEAN_SIGNAL_EXCISION}/\1 \3/g" <<< "$text")
    iterations=$((iterations + 1))
    [ "$text" = "$prev" ] && break
    [ "$iterations" -ge 25 ] && break
  done
  printf '%s' "$text"
}

# A3 check 2 — the closed residue grammar (Codex GitHub finding 3800167486;
# see Decision 2). $1 is the lowered, quote-stripped, footer-truncated body
# BEFORE excision — this function needs to know, per sentence, whether the
# sentence itself carried a clean signal, which a fully-excised residue no
# longer records.
#
# A sentence lacking its own clean signal must, after stripping punctuation
# and CODEX_RESIDUE_FILLER_WORD_PATTERN tokens, reduce to at most one bare
# token (a bounded tolerance for vendor sign-off flavor text such as
# "Swish!" — see Decision 2's residual-risk note), or otherwise begin with
# an allow-listed CODEX_RESIDUE_STARTER_PATTERN subject/determiner.
#
# A sentence carrying its own clean signal is further split on [,:;] into
# clauses, and every clause that does NOT itself carry the signal is bound
# by the same rule. Without this inner split, "Looks good: remove the
# authentication check." would exempt the whole sentence (comma/colon/
# semicolon do not end a "sentence" for the outer split, by design — see
# below) and the exploit from finding 3800167486 would survive unclosed;
# verified this inner split closes the colon/comma/semicolon variants
# without affecting the outer split's Group A compatibility.
#
# The outer split is deliberately on [.!?] only, NOT on [,:;] — verified
# that splitting the outer pass on [,:;] too breaks existing Group A bodies
# such as "The docs accurately quote: To use Codex here, create an
# environment for this repo." (a signal-FREE sentence containing legitimate
# elaboration with internal commas/colons); the coarser outer split, plus
# the finer inner split scoped to signal-bearing sentences only, is what
# keeps both the exploit closed and Group A passing.
codex_residue_is_closed_grammar() {
  local lowered="$1" sentence clause stripped leftover
  while IFS= read -r sentence; do
    [ -z "$(tr -d '[:space:]' <<< "$sentence")" ] && continue
    if grep -qE "$CODEX_CLEAN_SIGNAL_EXCISION" <<< "$sentence"; then
      while IFS= read -r clause; do
        [ -z "$(tr -d '[:space:]' <<< "$clause")" ] && continue
        if grep -qE "$CODEX_CLEAN_SIGNAL_EXCISION" <<< "$clause"; then
          continue
        fi
        stripped=$(sed -E 's/[^[:alnum:][:space:]_]/ /g' <<< "$clause")
        leftover=$(awk -v pat="$CODEX_RESIDUE_FILLER_WORD_PATTERN" \
          '{ for (i = 1; i <= NF; i++) if ($i !~ pat) c++ } END { print c + 0 }' <<< "$stripped")
        [ "$leftover" -le 1 ] && continue
        grep -qE "$CODEX_RESIDUE_STARTER_PATTERN" <<< "$clause" && continue
        return 1
      done < <(sed -E 's/[,:;]/\n/g' <<< "$sentence")
      continue
    fi
    stripped=$(sed -E 's/[^[:alnum:][:space:]_]/ /g' <<< "$sentence")
    leftover=$(awk -v pat="$CODEX_RESIDUE_FILLER_WORD_PATTERN" \
      '{ for (i = 1; i <= NF; i++) if ($i !~ pat) c++ } END { print c + 0 }' <<< "$stripped")
    if [ "$leftover" -le 1 ]; then
      continue
    fi
    if grep -qE "$CODEX_RESIDUE_STARTER_PATTERN" <<< "$sentence"; then
      continue
    fi
    return 1
  done < <(sed -E 's/[.!?]/\n/g' <<< "$lowered")
  return 0
}

codex_response_is_approved() {
  local body="$1"
  local visible lowered residue
  visible=$(codex_strip_quoted_spans "$(codex_strip_codex_footer "$body")")
  lowered=$(LC_ALL=C tr '[:upper:]' '[:lower:]' <<< "$visible")

  # A1 — an allow-listed clean signal must appear in the opening paragraph.
  # Uses the boundary-wrapped CODEX_CLEAN_SIGNAL_EXCISION here, NOT the raw
  # CODEX_CLEAN_SIGNAL_PATTERN alternation: the raw alternation has no word
  # boundaries (see the note on CODEX_CLEAN_SIGNAL_PATTERN below for why),
  # so a bare `grep -qE "$CODEX_CLEAN_SIGNAL_PATTERN"` would match "approved"
  # as a substring of "unapproved" and misclassify "This change remains
  # unapproved." as having a clean signal — reintroducing the exact
  # false-APPROVED bug (PR #1490 finding 3789851555) the original \b
  # boundaries existed to prevent. CODEX_CLEAN_SIGNAL_EXCISION supplies the
  # same boundary guarantee using only portable [^[:alnum:]_] classes, so one
  # boundary-safe pattern is reused for both the A1 presence test and the A3
  # excision, and grep is a pure existence test here (the capture groups are
  # unused).
  if ! grep -qE "$CODEX_CLEAN_SIGNAL_EXCISION" \
       <<< "$(codex_response_first_paragraph "$lowered")"; then
    return 1
  fi

  # A2 — a fence marker anywhere disqualifies (unchanged conservative guard).
  if codex_response_has_fence_marker "$body"; then
    echo "INFO: Codex clean signal present but disqualified (fence-marker)" >&2
    return 1
  fi

  # A3 check 1 — excise the clean signals (iteratively — see
  # codex_excise_clean_signals), then reject on any disqualifier in what is
  # left.
  residue=$(codex_excise_clean_signals "$lowered")
  if grep -qE "$CODEX_APPROVAL_DISQUALIFIER_PATTERN" <<< "$residue"; then
    echo "INFO: Codex clean signal present but disqualified (negation/hedge/actionable token)" >&2
    return 1
  fi

  # A3 check 2 — the closed residue grammar (see Decision 2 and
  # codex_residue_is_closed_grammar above). This is what makes
  # non-exhaustiveness of CODEX_APPROVAL_DISQUALIFIER_PATTERN safe.
  if ! codex_residue_is_closed_grammar "$lowered"; then
    echo "INFO: Codex clean signal present but disqualified (residue grammar not closed)" >&2
    return 1
  fi
  return 0
}
```

Notes for the implementer:

- The diagnostic lines go to **stderr**, never stdout. `codex_response_is_approved` is called from inside
  `$( … )` command substitutions in `codex_response_priority`; writing to stdout there would corrupt the
  priority value. Existing tests capture `2>&1` into a file and then select lines with `grep "^VERDICT:"`, so
  the extra lines do not affect assertions.
- The diagnostic fires only when a clean signal was present and something else disqualified it — that is,
  exactly the "would have been `APPROVED` before this change" case. Do not add a diagnostic to the A1 path;
  responses with no clean signal at all are the ordinary case and would flood the poll log.
- `LC_ALL=C tr '[:upper:]' '[:lower:]'` maps only ASCII `A-Z`, so multibyte content (`❌`, `👍`, `💡`) passes
  through byte-identical.
- `codex_residue_is_closed_grammar` is a genuine additional pass over the body (roughly proportional to
  sentence/clause count, not body length), on top of the existing excision/disqualifier passes. Verified
  sub-second even against the two existing 200 000-character SIGPIPE-safety fixtures, both of which contain
  no additional sentence-ending punctuation after the clean signal and so exercise the single-token-leftover
  branch, not a pathological sentence count.
- Every disqualifier, edge case, and Group A/B/C body enumerated in this plan (E1–E20, all 17 existing
  Group A scenarios, the retargeted Group B scenario, and all 9 Group C scenarios) was re-verified against
  this exact implementation on BSD `sed`/`grep`/`awk` during this review round. See "Testing Strategy" for
  the reconciled disposition and Decision 2 / Decision 6 for the two findings that changed behavior beyond
  what a mechanical read of the diff would suggest.

---

## Parser-risk addendum

This plan is **parser-risk**: it materially changes regex-based scanning of structured natural-language text.

### Edge-case enumeration

| # | Input (verbatim) | Expected | Why it is an edge case |
| --- | --- | --- | --- |
| E1 | `This change remains unapproved.` | not approved | Boundary variant: `approved` must not match inside a concatenated prefix, so A1 fails outright |
| E2 | `Approved.` / `Approved!` / `(approved)` | approved | Boundary variant: terminal and bracketing punctuation must satisfy the excision's `([^[:alnum:]_]\|$)` boundary group |
| E3 | `No blocking issues found. The content is consistent and the constant is important.` | approved | Negative lookalike: `content`, `consistent`, `constant`, `important` must not match `[[:alpha:]]n.t\b` |
| E4 | `This looks good; it oughtn't be merged yet.` | not approved | Unenumerated contraction. `oughtn't` is absent from `CODEX_NEGATION_WORDS`; the structural `[[:alpha:]]n.t\b` rule catches the whole contraction class at once |
| E5 | `Looks good and no blocking issues found.` | approved | Multiple occurrences on one line — both must be excised, leaving a disqualifier-free residue |
| E6 | `lgtm approved` | approved | Adjacent/overlapping occurrences. `sed`'s `g` flag resumes scanning after the replacement, so a single pass leaves the second signal un-excised — **corrected** (Codex GitHub finding 3800167494): `codex_excise_clean_signals` loops to a fixed point instead of relying on a single pass, and the assertion covers the outcome, not the residue |
| E7 | `NO BLOCKING ISSUES FOUND.` | approved | Case normalization: the `tr` pass must make the lowercase-only patterns match |
| E8 | `No blocking issues found. 🎉` | approved | Multibyte safety: `LC_ALL=C tr` must not corrupt the emoji into something matching a pattern |
| E9 | Real clean root comment including the `<details>` footer with its bullet list | approved | The vendor footer must be truncated before A3; without truncation this is the single most likely source of a mass false-`NEEDS_REVISION`. Also the case that validates the closed residue grammar (A3 check 2) does not reject genuine vendor flavor text (`Swish!`) — see Decision 2's residual-risk note |
| E10 | `Didn't find any major issues.` + footer whose interior says `This must not be merged.` | not approved | Truncation must not hide a refusal: `codex_response_is_blocking` runs first, on the untruncated body |
| E11 | `Summary of the diff.` blank line `No blocking issues found.` | not approved | A1 position rule: a clean signal outside the opening paragraph does not approve |
| E12 | `` The documented output is: ```text / No blocking issues found / ``` `` | not approved | Fence marker present anywhere (A2), unchanged behavior; the closing fence is never located |
| E13 | `The documented bot response "No blocking issues found" is inaccurate.` | not approved | Quoted span is stripped before A1, so no clean signal survives |
| E14 | `No blocking issues found. The tests correctly cover the` `` `must fix` `` `marker.` | approved | Quoted span stripping must run **before** A3, or the quoted blocker token would disqualify a genuinely clean review |
| E15 | `No blocking issues found. Please address the naming.` | not approved | Actionable-verb group; the residue has no negation and no hedge, so this is the case only that group catches (also independently caught by A3 check 2's closed grammar, since `address the naming` has 2 leftover open-class tokens and no allow-listed starter) |
| E16 | `This remains un_approved.` | not approved | Underscore boundary (Codex GitHub finding 3800167492): `_` is a word character for `\b`, so the old `[^[:alnum:]]` excision boundary incorrectly treated it as a boundary; `[^[:alnum:]_]` correctly leaves `un_approved` unmatched |
| E17 | `Approved no blocking issues found.` | approved | Adjacency where the second signal contains `no` (Codex GitHub finding 3800167494): without iterative excision, `no blocking issues` survives un-excised and its `no` matches `CODEX_APPROVAL_NEGATION_PATTERN`, incorrectly returning `NEEDS_REVISION` |
| E18 | `LGTM. Didn't find any major issues.` | approved | Adjacency where the second signal contains `didn't` (Codex GitHub finding 3800167494); a comma-joined no-space variant (`Approved, no blocking issues found.`) is covered by the same scenario as a second assertion |
| E19 | `Looks good. Remove the authentication check.` (plus colon- and comma-joined variants: `Looks good: remove the authentication check.` / `Looks good, remove the authentication check.`) | not approved | The literal exploit from Codex GitHub finding 3800167486 (P1/blocking): a clean signal followed by an unenumerated actionable sentence. Closed by A3 check 2 (the closed residue grammar) — `remove the authentication check` has more than one leftover open-class token after filler stripping and does not begin with an allow-listed starter, regardless of which punctuation joins it to the signal-bearing sentence |
| E20 | `Looks good.` followed by a **non-vendor** `<details>` block containing `Rename the unsafe function.` | not approved | The exploit from Codex GitHub finding 3800167489 (P1/blocking): over-broad footer truncation (any `<details` line, not the specific vendor marker) hides the instruction from A3 entirely. Closed by anchoring `codex_strip_codex_footer` on the actual `about codex in github` marker; once left intact, A3 check 2 independently rejects the instruction too |

### Unit test mapping

There is one test file for this script: `scripts/development-workflow/tests/test-pr-review-loop.sh`. Each
edge case above gets at least one scenario there, driven through the real script with a mocked `gh` on
`PATH` (the harness convention already used by all 247 `codex_*` assertions). Proposed scenario names:

| Edge case | Scenario name |
| --- | --- |
| E1 | `codex_unapproved_prefix_root_comment` (exists — keep) |
| E2 | `codex_bare_approved_punctuation_root_comment` (new) |
| E3 | `codex_contraction_lookalike_words_root_comment` (new) |
| E4 | `codex_unenumerated_contraction_root_comment` (new) |
| E5 | `codex_two_clean_signals_one_line_root_comment` (new) |
| E6 | `codex_adjacent_clean_signals_root_comment` (new) |
| E7 | `codex_uppercase_clean_signal_root_comment` (new) |
| E8 | `codex_emoji_clean_signal_root_comment` (new) |
| E9 | `codex_real_vendor_footer_clean_root_comment` (new) |
| E10 | `codex_footer_truncation_keeps_blocking_root_comment` (new) |
| E11 | `codex_clean_signal_outside_first_paragraph_root_comment` (new) |
| E12 | `codex_fenced_code_block_phrase_not_approved_root_comment` (exists — keep) |
| E13 | `codex_quoted_clean_phrase_not_approved_root_comment` (exists — keep) |
| E14 | `codex_quoted_blocker_token_stays_approved_root_comment` (exists — keep) |
| E15 | `codex_actionable_verb_after_clean_signal_root_comment` (new) |
| E16 | `codex_underscore_prefixed_lookalike_root_comment` (new — added during Step 7 review round) |
| E17 | `codex_adjacent_signal_second_contains_no_root_comment` (new — added during Step 7 review round) |
| E18 | `codex_adjacent_signal_second_contains_didnt_root_comment` (new — added during Step 7 review round) |
| E19 | `codex_unenumerated_actionable_sentence_after_signal_root_comment` (new — added during Step 7 review round; asserts all three punctuation variants) |
| E20 | `codex_nonfooter_details_block_not_truncated_root_comment` (new — added during Step 7 review round) |

### Suppression semantics

Not applicable — the classifier recognizes no inline suppression or directive syntax, and this plan does not
introduce one.

---

## Concurrent-event-source addendum

Not applicable. `codex_response_is_approved` and its helpers are synchronous, pure string transformations
invoked from a single-threaded polling loop. No listeners, timers, async queues, or shared mutable state are
added; the only new global-ish surface is the stderr diagnostic, which is write-only.

---

## Testing Strategy

**Test types**: Unit/behavioral (via `scripts/development-workflow/tests/test-pr-review-loop.sh`) plus a
manual smoke runbook.

**Command**: `bash scripts/development-workflow/tests/test-pr-review-loop.sh` — must exit 0 with all
assertions passing, on macOS (BSD tooling) and in CI (GNU tooling).

### Test disposition — existing scenarios

Every existing `codex_*` scenario is accounted for below. **No existing test is deleted.** Every Group A/B/C
body in this section was re-executed against the tightened A3 (both the disqualifier scan and the new closed
residue grammar — see Decision 2) on BSD `sed`/`grep`/`awk` during the Step 7 review round that added findings
`3800167486`/`3800167489`/`3800167492`/`3800167494`. **No scenario moved between groups as a result**: the
closed grammar was specifically shaped (via `CODEX_RESIDUE_FILLER_WORD_PATTERN`'s vendor-identity tokens and
`CODEX_RESIDUE_STARTER_PATTERN`'s closed-class starters) so that every Group A body — including the
multi-word "topic mention" and "quote" elaboration bodies below — still passes; see Decision 2's residual-risk
note for the one body that would **not** have passed a naively stricter (zero-tolerance) grammar, and why that
was rejected in favor of the design actually shipped here.

#### Group A — keep as-is, still `VERDICT: APPROVED`

These bodies contain a clean signal in the opening paragraph and a disqualifier-free, closed-grammar residue,
so the new contract preserves them:

| Scenario | Body (abridged) |
| --- | --- |
| `codex_clean_root_review_comment` | `Codex Review: Didn't find any major issues.` |
| `codex_full_root_review_comment` | `Codex Review: Didn't find any major issues.` |
| `codex_reaction_with_current_review` | `No blocking issues found.` |
| `codex_reaction_then_late_review` | `No blocking issues found.` |
| `codex_async_reaction_then_late_review` | `No blocking issues found.` |
| `codex_latest_current_review` | `No blocking issues found.` |
| `codex_environment_with_current_review` | `No blocking issues found.` |
| `codex_main_loop_env_then_newer_review_supersedes` | `No blocking issues found.` |
| `codex_long_review_body_no_sigpipe` | `No blocking issues found. ` + 200 000 chars |
| `codex_long_root_comment_no_sigpipe` | `Codex Review: Didn't find any major issues.` + 200 000 chars |
| `codex_usage_limit_topic_mention_not_quota` | `… The Codex usage limit handling looks correct.` |
| `codex_usage_limit_code_reviews_phrase_mention` | `… The docs correctly explain Codex usage limits for code reviews.` |
| `codex_terminal_comment_quotes_env_error_not_ancillary` | `… The docs accurately quote: To use Codex here, create an environment for this repo.` |
| `codex_quoted_rejection_in_clean_review_root_comment` | `… The tests cover "This change is not approved".` (negation lives inside a stripped quoted span) |
| `codex_terminal_review_quotes_quota_message` | `… The docs accurately quote:` `` `You have reached your Codex usage limits.` `` |
| `codex_quoted_blocker_token_stays_approved_root_comment` | `… The tests correctly cover the` `` `must fix` `` `marker.` |
| `codex_didnt_find_issues_and_looks_good_approved_root_comment` | `Codex didn't find any major issues and looks good.` |

#### Group B — keep the assertion, retarget the fixture body

| Scenario | Change | Reason |
| --- | --- | --- |
| `codex_inline_backtick_pair_stays_approved_root_comment` | Change the body from `` The fix looks good. See `foo.py:42` for a minor nit. `` to `` The fix looks good. See `foo.py:42`. ``; keep `VERDICT: APPROVED` | The scenario's purpose is to prove a **single** inline backtick pair does not trip the fence guard. `minor nit` is a hedge disqualifier, which would flip the verdict for a reason unrelated to the regression being guarded. **Retargeted a second time during the Step 7 review round**: the first retarget candidate (`` The fix looks good. See `foo.py:42` in the diff. ``) was re-verified against the new closed residue grammar (A3 check 2, Decision 2) and found to fail it — after the backtick span is stripped, the trailing sentence `See  in the diff.` leaves 2 open-class leftover tokens (`see`, `diff`) and does not begin with an allow-listed starter. The shorter body verified above leaves only 1 leftover token (`see`) and passes |

#### Group C — retarget the expected verdict from `APPROVED` to `NEEDS_REVISION`

These 9 scenarios were written during PR #1490 to prove that a negation in one clause does **not** leak into
an unrelated clean clause. That precision guarantee is exactly what this change abandons on purpose. Keep
each scenario, keep the body, change the expectation, and rewrite the comment to say the flip is the
deliberate false-`NEEDS_REVISION` cost of the allow-list.

| Scenario | Body | New expected verdict line |
| --- | --- | --- |
| `codex_negation_prior_sentence_does_not_leak_root_comment` | `The variable name is not great. No blocking issues found.` | `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)` |
| `codex_unrelated_later_negation_stays_approved_root_comment` | `Looks good overall; tests were not run.` | `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)` |
| `codex_semicolon_scoped_negation_root_comment` | `Tests are not required for this documentation-only change; looks good.` | `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)` |
| `codex_comma_scoped_negation_root_comment` | `Tests are not required, but looks good.` | `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)` |
| `codex_contraction_apostrophes_not_mangled_root_comment` | `It's fine, doesn't need changes. No blocking issues found.` | `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)` |
| `codex_not_only_idiom_stays_approved_root_comment` | `Not only does this look good, it is approved.` | `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)` |
| `codex_not_only_idiom_uppercase_stays_approved_root_comment` | `NOT ONLY does this look good, it is approved.` | `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)` |
| `codex_unrelated_negation_before_merge_stays_approved_root_comment` | `This is not a blocker; looks good, please merge.` | `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)` |
| `codex_not_only_safe_to_merge_stays_approved_root_comment` | `This is not only safe to merge but looks good.` | `VERDICT: NEEDS_REVISION` (**blocking branch**, no suffix — with `codex_strip_not_only_idiom` gone, `not … merge` matches `CODEX_MERGE_REFUSAL_PATTERN`) |

The last row is the one flip whose verdict **string** differs from the others. Do not assume a uniform
replacement; assert each expectation individually.

Also rename the four scenarios whose names now assert the opposite of their expectation
(`…_stays_approved_…`). Renaming is optional for correctness but required for readability; if renamed, do it
in the same commit so the name and expectation never disagree on `develop`.

#### Group D — keep as-is, still `NEEDS_REVISION`, mechanism changed

These scenarios keep passing, but for a different reason than when they were written. Update their comments
to say so; do **not** delete them, because they are now the regression net proving the allow-list closes the
same class of gap the old block-list enumerated one entry at a time:

- Negated-approval vocabulary: `codex_negated_approval_root_comment`,
  `codex_markdown_negated_approval_root_comment`, `codex_qualifier_negated_approval_root_comment`,
  `codex_negation_beyond_bounded_window_root_comment`,
  `codex_negation_reverse_order_cannot_approve_root_comment`, `codex_unable_to_approve_root_comment`,
  `codex_wouldnt_approve_not_approved_root_comment`, `codex_dont_approve_not_approved_root_comment`,
  `codex_unapproved_prefix_root_comment`, `codex_negated_no_blocking_issues_root_comment`
- Merge-refusal blocking (still resolved by the unchanged `codex_response_is_blocking`):
  `codex_should_not_be_merged_blocking_root_comment`, `codex_shouldnt_be_merged_blocking_root_comment`,
  `codex_do_not_merge_blocking_root_comment`, `codex_cannot_be_merged_blocking_root_comment`
- Quote/fence stripping (resolved by the unchanged `codex_strip_quoted_spans` and
  `codex_response_has_fence_marker`): `codex_quoted_clean_phrase_not_approved_root_comment`,
  `codex_backtick_quoted_phrase_not_approved_root_comment`,
  `codex_blockquoted_clean_phrase_not_approved_root_comment`,
  `codex_single_quoted_phrase_not_approved_root_comment`,
  `codex_multiline_quoted_clean_phrase_not_approved_root_comment`,
  `codex_multiline_single_quoted_whole_line_not_approved_root_comment`,
  `codex_multiline_backtick_span_not_approved_root_comment`,
  `codex_double_backtick_span_not_approved_root_comment`,
  `codex_fenced_code_block_phrase_not_approved_root_comment`,
  `codex_nested_fence_length_phrase_not_approved_root_comment`,
  `codex_fence_close_requires_whitespace_only_root_comment`,
  `codex_tilde_fence_phrase_not_approved_root_comment`

#### Group E — untouched

All remaining `codex_*` scenarios (evidence selection and tie-breaks, usage-limit and environment-error
routing, `CHANGES_REQUESTED` state handling, trigger idempotency, thread audits, timeout and poll-interval
configuration) neither approve nor depend on approval-vocabulary parsing, and must pass unchanged. Any
failure among them is a genuine regression, not an intended contract change.

### New scenarios

**17 new scenarios total**: the eleven from edge cases E2–E11 and E15 in the "Unit test mapping" table above,
plus `codex_disqualifier_diagnostic_emitted`, plus five more added during the Step 7 review round for edge
cases E16–E20 (findings `3800167486`, `3800167489`, `3800167492`, `3800167494`):

- `codex_disqualifier_diagnostic_emitted` — assert that a body with a clean signal plus a disqualifier emits
  the `INFO: Codex clean signal present but disqualified` line, so the operational diagnostic is itself
  covered. (Two diagnostic reasons now exist — `negation/hedge/actionable token` and `residue grammar not
  closed` — assert at least one; asserting both, from two separate bodies, is preferred.)
- `codex_underscore_prefixed_lookalike_root_comment` (E16) — `NEEDS_REVISION`.
- `codex_adjacent_signal_second_contains_no_root_comment` (E17) — `APPROVED`.
- `codex_adjacent_signal_second_contains_didnt_root_comment` (E18) — `APPROVED`.
- `codex_unenumerated_actionable_sentence_after_signal_root_comment` (E19) — `NEEDS_REVISION`, asserted for
  all three punctuation variants (period/colon/comma).
- `codex_nonfooter_details_block_not_truncated_root_comment` (E20) — `NEEDS_REVISION`.

Of the 17 new scenarios, 9 assert `VERDICT: APPROVED` (E2, E3, E5, E6, E7, E8, E9, E17, E18) and 8 assert
`VERDICT: NEEDS_REVISION` (E4, E10, E11, E15, E16, E19, E20, plus `codex_disqualifier_diagnostic_emitted`).

### Reconciled test-disposition counts

Re-derived during the Step 7 review round, since findings `3800167486`/`3800167492`/`3800167494` add
regression coverage and finding `3800167486` also changes what Decision 2 claims about correctness (though,
as verified above, it does **not** move any scenario between Group A/B/C):

| Metric | Before this plan (baseline, `55b2df5d`) | After this plan |
| --- | --- | --- |
| Total `run_test` assertions | 628 | 628 + 17 × 2 = 662 (`codex_disqualifier_diagnostic_emitted` may need a third assertion for the diagnostic line itself — confirm exact per-scenario assertion count against the harness convention at implementation time and report the real total in the PR description; treat any other delta as a finding) |
| `codex_*` assertions | 247 | 247 + 34 = 281 (same caveat as above) |
| Scenarios asserting `VERDICT: APPROVED` | 27 (Group A 17 + Group B 1 + Group C 9) | 27 — composition changes, count does not: Group C's 9 flip out (27 → 18), 9 of the 17 new scenarios flip in (18 → 27). The coincidence in the total is real but incidental; the PR description must state the composition delta explicitly (Group C scenario names out, new E2/E3/E5/E6/E7/E8/E9/E17/E18 scenario names in), not just the unchanged total, or a reviewer skimming only the count would incorrectly conclude nothing changed |

### Residual verification strategy

This is a contract-flip refactor with pattern-completeness characteristics, so the evidence the
implementation must produce before `ready-for-human-review` is:

1. A full `bash scripts/development-workflow/tests/test-pr-review-loop.sh` run exiting 0, with the total
   assertion count reported before and after, reconciled against the "Reconciled test-disposition counts"
   table above (report and explain any discrepancy rather than silently accepting a different number).
2. A reconciliation statement in the PR description: every scenario whose expectation changed appears in
   Group B or Group C above, and no scenario outside those groups changed. Any additional flip discovered
   during implementation must be added to the table with its own justification rather than silently accepted.
3. Confirmation that the real captured Codex clean body (E9) approves — this is the check that guards against
   the highest-impact failure mode, a classifier that rejects every real clean review. Re-verify this
   specifically against the closed residue grammar (A3 check 2), not just the disqualifier scan: this is the
   check a naively strict grammar would fail (see Decision 2's residual-risk note) — confirm the shipped
   `CODEX_RESIDUE_FILLER_WORD_PATTERN`/`CODEX_RESIDUE_STARTER_PATTERN` still let it pass.
4. Confirmation that the four exploits from the Step 7 review round (E16–E20's underlying findings) are
   actually closed against the real script, not just the illustrative prototype in this plan — run
   `codex_unenumerated_actionable_sentence_after_signal_root_comment` and
   `codex_nonfooter_details_block_not_truncated_root_comment` specifically and confirm both report
   `NEEDS_REVISION`.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Real Codex clean root comment | Body captured from PR #1489: `Codex Review: Didn't find any major issues. Swish!`, a `**Reviewed commit:**` marker matching the fixture head SHA, and the full `<details>` "About Codex in GitHub" footer including its bulleted list | `scripts/development-workflow/tests/test-pr-review-loop.sh` (inline `gh` mock heredoc, scenario `codex_real_vendor_footer_clean_root_comment`) |
| Footer-with-refusal variant | The same body with `This must not be merged.` inserted inside the `<details>` block | `scripts/development-workflow/tests/test-pr-review-loop.sh` (scenario `codex_footer_truncation_keeps_blocking_root_comment`) |

Capture the real body with:

<!-- workflow-shell-contract: bash -->

```bash
gh api repos/lhpaul/ai-dev-framework-template/issues/1489/comments \
  --jq '.[] | select(.user.login | test("codex"; "i")) | .body'
```

Escape it for the existing `jq -nc` / `printf` mock convention already used by the neighbouring scenarios;
do not add a fixture file, as the harness is deliberately self-contained.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/codex-github.md` — add a **Verdict classification**
      section stating that `APPROVED` requires an allow-listed clean signal in the opening paragraph of the
      response, that any negation, hedge, or actionable-verb token elsewhere safe-fails to `NEEDS_REVISION`,
      that any sentence/clause lacking its own clean signal must also satisfy the closed residue grammar (at
      most one leftover open-class token, or begin with an allow-listed subject/determiner starter), and that
      the vendor `<details>` footer (matched precisely, not any `<details>` block) is ignored for this
      decision. Note the deliberate false-`NEEDS_REVISION` tradeoff, the disclosed residual gap (a single
      bare-word unenumerated imperative — see Decision 2), and that extending the disqualifier list is always
      safe while extending the clean-signal allow-list or the closed-grammar filler/starter constants is not.
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` — in the
      "Codex GitHub terminal evidence" block (around line 112), add one sentence: SHA-pinned terminal evidence
      is necessary but not sufficient; the response must additionally carry an unhedged clean signal, and a
      hedged or qualified response is treated as `NEEDS_REVISION` rather than clean.
- [ ] `CHANGELOG.md` — `[Unreleased]` → `### Changed` (see Implementation Order step 8 for the literal).
- [ ] `AGENTS.md` — no change. The classifier is not named there and no command, convention, or branching rule
      is affected.
- [ ] `REVIEW.md` — no change. This plan adds no cross-cutting review checklist category.
- [ ] Agent and Codex skill files — no change. The Verification Log confirms no agent, skill, or protocol file
      references the affected symbols, and no workflow stage behavior changes.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Vendor changes the clean-response wording so no allow-listed signal matches, and every PR safe-fails | Low | High | Re-verify the live wire format at implementation start (Implementation Order step 1) and cover it with scenario `codex_real_vendor_footer_clean_root_comment`. Recovery is a one-line addition to `CODEX_CLEAN_SIGNAL_PATTERN`, reviewed with the same care the old negation list received |
| Vendor adds a negation or hedge word to the static `<details>` footer, disqualifying every clean response | Medium | High | `codex_strip_codex_footer` removes the footer before the disqualifier scan (Decision 6), so footer wording cannot influence the approval verdict at all |
| Vendor stops using `<details>` for the footer, so truncation no longer applies | Low | Medium | The disqualifier scan then sees the footer prose. Verified today that the current footer text matches no disqualifier; the `codex_real_vendor_footer_clean_root_comment` scenario would fail loudly if that changed, rather than silently approving |
| Higher false-`NEEDS_REVISION` rate causes extra reviewer-loop cycles | High (by design) | Low–Medium | Accepted and documented. The stderr diagnostic names the reason so a maintainer can distinguish "Codex actually objected" from "the classifier was conservative" without re-deriving the rule |
| A disqualifier token is too broad and rejects a genuinely clean response (`\bno\b`, `\bshould\b`, `\bminor\b` are the widest) | Medium | Low | Safe direction. Every disqualifier can be narrowed later without correctness analysis (Decision 2). All existing and real clean bodies were checked against the proposed list before this plan was written |
| Footer truncation hides a refusal placed after the footer | Very low | High | `codex_response_is_blocking` runs before approval at every verdict site and scans the untruncated body; covered by scenario `codex_footer_truncation_keeps_blocking_root_comment` |
| BSD versus GNU regex divergence (`\b` in `sed`, `tr` locale behavior) | Medium | Medium | `\b` is used only in `grep -E`, where the file already documents cross-implementation verification; `sed` uses explicit `[^[:alnum:]_]` boundary groups; `tr` runs under `LC_ALL=C`. The prototype (including the closed-grammar helper added in the Step 7 review round) was executed on BSD tooling and CI covers GNU |
| Retargeting 9 expectations masks a real regression | Medium | Medium | The Group A–E disposition table is exhaustive; the PR must state that no scenario outside Groups B and C changed |
| **A single unenumerated bare-word imperative with no object (e.g. `Approved. Revert.`) is not caught by A3 check 2's "at most one leftover token" tolerance** | Low | Medium | **Disclosed, accepted, not fixed by this plan** — see Decision 2's residual-risk note. Verified: `Approved. Revert.` returns `APPROVED` under the shipped design. The tolerance exists because a zero-tolerance grammar rejects the real captured clean root comment (`Codex Review: Didn't find any major issues. Swish!`, whose `swish` residue is lexically identical in shape to `revert`) — closing this gap without also rejecting genuine vendor flavor text needs either a curated vendor-flavor allow-list (reintroducing an open-ended-enumeration problem in the safe direction) or a structured verdict signal from GitHub (Decision 3's deferred `state == "APPROVED"` follow-up). **Flagged for explicit human confirmation that this narrower, disclosed trade-off is acceptable**; it is a strict improvement over the pre-this-plan exposure (any number of unenumerated words, not just one bare word with no object) |
| Extending `CODEX_RESIDUE_FILLER_WORD_PATTERN` or `CODEX_RESIDUE_STARTER_PATTERN` with a general content word (rather than a genuinely closed-class word or a specific reviewed vendor-identity token) silently widens the false-`APPROVED` surface | Low | High | Same review discipline as extending `CODEX_CLEAN_SIGNAL_PATTERN` (Decision 2) — flagged explicitly in the Layer-by-Layer checklist and in Decision 2's "Reviewers must not..." list so a future PR touching either constant is held to the same bar |

---

## Operational cost and escape hatch

**What a maintainer should expect.** Responses that are genuinely clean but *chatty* will now be reported
`NEEDS_REVISION` more often than before. Concretely, the constructions that used to approve and no longer
will are: an unrelated negation anywhere in the response ("tests were not run", "not a blocker"), any hedge
("but", "however", "minor nit", "at first glance"), any actionable verb ("please address", "should rename"),
the "not only X" idiom, **and — new in the Step 7 review round — a trailing sentence or clause after a clean
signal that carries more than one open-class content word and does not open with a recognized subject/
determiner** (A3 check 2, the closed residue grammar; see Decision 2). Each of these produces one extra
reviewer-loop cycle: `pr-review-loop.sh` reports the platform as not clean, the item agent inspects the
response, finds nothing actionable, and re-triggers.

**Escape hatch: none, deliberately.** No environment variable, config flag, or CLI option is added to relax
the classifier. A bypass would be indistinguishable from the false-`APPROVED` bug this change exists to
eliminate, and it would be reached for precisely when the classifier is doing its job. The supported
responses to a persistent false `NEEDS_REVISION` are, in order:

1. Read the `INFO: Codex clean signal present but disqualified (…)` line to see which rule fired
   (`negation/hedge/actionable token` vs. `residue grammar not closed`).
2. If a disqualifier is too broad, narrow `CODEX_APPROVAL_DISQUALIFIER_PATTERN` — always safe, no correctness
   analysis needed.
3. If the closed-grammar check (A3 check 2) is too strict for a specific, genuinely inert vendor construction,
   the ONLY safe lever is adding that construction as a specific, reviewed vendor-identity token to
   `CODEX_RESIDUE_FILLER_WORD_PATTERN` or `CODEX_RESIDUE_STARTER_PATTERN` (never a general content word) — the
   same review bar as step 4 below, per Decision 2.
4. If the vendor's clean wording is unrecognized, extend `CODEX_CLEAN_SIGNAL_PATTERN` — one of the two changes
   that widens the approval surface and therefore needs full review.
5. If Codex begins submitting reviews with `state == "APPROVED"`, file the deferred structural-approval
   follow-up from Decision 3 instead of loosening the prose rules.

---

## Implementation Order

1. **Re-verify the vendor wire format** (Protocol 02 implementation-start source check). Re-run the
   `gh api …/issues/1489/comments` and `…/pulls/1490/reviews` queries from the Verification Log and confirm
   the clean-response shape still matches. Record `Still valid` or stop and return evidence to the parent
   orchestrator.
2. **Add the new constants** in `codex-github-reviewer.sh`, immediately after the existing line that appends
   `CODEX_MERGE_REFUSAL_PATTERN` to `CODEX_BLOCKING_PATTERN`: `CODEX_CLEAN_SIGNAL_PATTERN` (renamed from
   `CODEX_APPROVAL_PATTERN`), `CODEX_CLEAN_SIGNAL_EXCISION` (boundary class `[^[:alnum:]_]`, not
   `[^[:alnum:]]`), the three disqualifier groups, the composite `CODEX_APPROVAL_DISQUALIFIER_PATTERN`, and
   `CODEX_RESIDUE_FILLER_WORD_PATTERN`/`CODEX_RESIDUE_STARTER_PATTERN` (A3 check 2's closed-grammar
   constants). Delete `CODEX_NEGATED_APPROVAL_TARGET_WORDS` and `CODEX_NEGATED_APPROVAL_PATTERN`.
   *Verify*: `bash -n scripts/development-workflow/codex-github-reviewer.sh` succeeds and
   `grep -n "CODEX_NEGATED_APPROVAL" scripts/development-workflow/codex-github-reviewer.sh` returns nothing.
3. **Add the four helpers** `codex_strip_codex_footer` (anchored on the `about codex in github` marker, not a
   generic `<details` match), `codex_response_first_paragraph`, `codex_excise_clean_signals` (the iterative
   excision loop), and `codex_residue_is_closed_grammar` (A3 check 2), placed next to the other normalization
   helpers.
4. **Rewrite `codex_response_is_approved`** per Decision 1, including both A3 checks and the three stderr
   diagnostics (`fence-marker`, `negation/hedge/actionable token`, `residue grammar not closed`).
5. **Delete `codex_strip_not_only_idiom`** and remove its call from `codex_response_is_blocking`. Make no
   other change to `codex_response_is_blocking`.
   *Verify*: `grep -n "not_only" scripts/development-workflow/codex-github-reviewer.sh` returns nothing.
6. **Update the file-header "Verdict parsing" comment block** and the rationale comments around the changed
   and deleted symbols.
7. **Update the tests**: apply Group B and Group C changes (using the Group B body as retargeted a second time
   during the Step 7 review round — `` The fix looks good. See `foo.py:42`. ``), refresh Group D comments, then
   add the 17 new scenarios listed in "New scenarios" (the original 12 plus the 5 added for E16–E20).
   *Verify*: run `bash scripts/development-workflow/tests/test-pr-review-loop.sh` and confirm it exits 0, that
   the total assertion count matches the "Reconciled test-disposition counts" table (report any discrepancy),
   and that the failures you fixed are exactly the ones this plan predicted — read the output and confirm no
   unexpected scenario changed.
8. **Update the documentation** listed in "Documentation Updates", then add the CHANGELOG entry under
   `[Unreleased]` → `### Changed`, copied literally:

   ```text
   - **Conservative Codex verdict classifier** (#1491): `codex-github-reviewer.sh` now requires an unhedged,
     allow-listed clean signal in the opening paragraph of a Codex response before returning `APPROVED`, and
     safe-fails to `NEEDS_REVISION` when any negation, hedge, or actionable-verb token appears elsewhere in
     the response. This replaces the open-ended negated-approval vocabulary enumeration
     (`CODEX_NEGATED_APPROVAL_PATTERN`, `CODEX_NEGATED_APPROVAL_TARGET_WORDS`, `codex_strip_not_only_idiom`),
     which could not converge because English negation vocabulary is unbounded. GitHub's structured
     `CHANGES_REQUESTED` review-state short-circuit and the blocking classifier are unchanged.
   ```

9. **Run the markdown and shell lint gates**: `npx markdownlint-cli2` on the changed docs and this plan,
   `python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`,
   `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`, and
   `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`.
10. **Walk the smoke test runbook** and record the results in the PR description.

---

## Document Quality Gate

- Spec/brief coverage: Checked — every objective in issue #1491's Option 2 maps to a decision, an
  implementation step, and test coverage; Options 1 and 3 are addressed explicitly under Decision 3. The
  four Codex GitHub findings from the Step 7 review round (`3800167486`, `3800167489`, `3800167492`,
  `3800167494`) are refinements strictly within Option 2 — none required or introduced a change of approach.
- Implementation-order consistency: Checked — helper names (`codex_strip_codex_footer`,
  `codex_response_first_paragraph`, `codex_excise_clean_signals`, `codex_residue_is_closed_grammar`), constant
  names (`CODEX_CLEAN_SIGNAL_PATTERN`, `CODEX_CLEAN_SIGNAL_EXCISION`, `CODEX_APPROVAL_NEGATION_PATTERN`,
  `CODEX_APPROVAL_HEDGE_PATTERN`, `CODEX_APPROVAL_ACTIONABLE_PATTERN`, `CODEX_APPROVAL_DISQUALIFIER_PATTERN`,
  `CODEX_RESIDUE_FILLER_WORD_PATTERN`, `CODEX_RESIDUE_STARTER_PATTERN`), decision labels (Decision 1–6),
  scenario names (including the 5 added for edge cases E16–E20), and file paths agree across the Summary,
  Decisions, Layer-by-Layer, Code Samples, Parser-risk addendum, Testing Strategy, and Implementation Order
  sections.
- Verification support: Checked — every claim about existing behavior, file coverage, counts, and the vendor
  wire format cites a Verification Log command or a named source file. Every regex/helper introduced or
  changed during the Step 7 review round was re-executed on BSD `sed`/`grep`/`awk` against the reviewer's
  literal counterexamples, the full E1–E20 edge-case set, all 17 Group A bodies, the retargeted Group B body,
  all 9 Group C bodies, and the two real captured Codex bodies (PR #1489/#1490, re-fetched live during this
  review round) — see the Code Samples section's opening note.
- Behavioral guarantees: Checked — the "cannot weaken the `CHANGES_REQUESTED` short-circuit" guarantee names
  its mechanism (the classifier only moves responses from priority tier 0 to tier 2, and blocking is
  evaluated first at every verdict site); the "truncation cannot hide a refusal" guarantee names
  `codex_response_is_blocking` running on the untruncated body; the "non-exhaustiveness of the disqualifier
  list is safe" guarantee now names its actual mechanism (the closed residue grammar, Decision 2) rather than
  merely asserting it, and discloses the one residual gap that mechanism does not close.
- Complex workflow decision-gate matrix: Checked — see the matrix below.
- Parser/API/concurrency checklist: Checked (parser-risk addendum present with edge-case enumeration through
  E20 and per-case unit-test mapping); concurrent-event-source recorded as not applicable with rationale.
- CHANGELOG literal format: Checked — Implementation Order step 8 gives the entry in the project's
  `**Bold Title** (#N):` format under `### Changed`.
- Not-applicable rationale: Checked — suppression semantics and concurrency each carry a rationale.

### Decision-gate matrix

| Gate input | Allowed outcome | Exit code | Required next action | Mirror surface |
| --- | --- | --- | --- | --- |
| Review-sourced evidence with `state == CHANGES_REQUESTED` | `NEEDS_REVISION` | 1 | Loop counts unresolved threads; item agent fixes findings | Unchanged in all four verdict sites and in `codex_response_priority` |
| `codex_response_is_blocking` matches | `NEEDS_REVISION` | 1 | Same as above | Unchanged |
| Usage-limit or environment-error notice | `UNAVAILABLE` | 3 | Platform reported unavailable; loop applies the configured unavailable policy | Unchanged |
| Clean signal in opening paragraph, no fence, disqualifier-free AND closed-grammar residue | `APPROVED` | 0 | Platform reported clean | **Changed** — stricter than today |
| Clean signal present but fence marker, negation, hedge, actionable token found, or the residue grammar is not closed | `NEEDS_REVISION (unrecognized response format — safe-fail)` | 1 | Item agent inspects the stderr diagnostic (`negation/hedge/actionable token` or `residue grammar not closed`) and re-triggers or fixes | **Changed** — this is the new false-`NEEDS_REVISION` surface, now driven by two independent A3 checks |
| No clean signal at all | `NEEDS_REVISION (unrecognized response format — safe-fail)` | 1 | Same as above | Unchanged |
| No terminal evidence within the poll window | `TIMED_OUT` | 2 | Treated as unavailable | Unchanged |

Example bodies for each changed row are enumerated in the Parser-risk addendum (E1–E20) and mapped to named
test scenarios, so the matrix, the examples, and the tests are the same set.

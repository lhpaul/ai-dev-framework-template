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
rewritten, five helpers added — `codex_strip_codex_footer`, `codex_strip_vendor_metadata_lines`,
`codex_response_first_paragraph`, `codex_excise_clean_signals`, `codex_residue_is_closed_grammar` — three
original symbols deleted, one renamed). The closed-grammar constants were revised mid-round:
`CODEX_RESIDUE_STARTER_PATTERN` was added, then deleted again after a human decision rejected the design it
supported, and `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` was added in its place; `CODEX_RESIDUE_FILLER_WORD_PATTERN`
was subsequently narrowed twice more — once to remove vendor-identity tokens that reopened a false `APPROVED`
(Decision 2's "governing asymmetry" note), and `codex_strip_codex_footer` was rewritten a third time, from a
regex over tag names to an exact byte-literal match, after regex-based tag matching itself proved to admit
lookalikes across three consecutive review rounds (Decision 6's "Third correction" note). The work is
medium-to-large because it changes a contract that 27 existing assertions depend on: 18 existing scenarios
change their expected verdict or fixture body (Group A2's 5, Group A3's 3, Group B's 1, Group C's 9), plus new
regression coverage for the allow-list contract, its parser edge cases, and — added during the Step 7 review
round, then tightened again to zero-tolerance after a human decision, then further hardened against vendor-
metadata-token widening and footer-markup lookalikes — the closed residue grammar and footer-anchoring
mechanism that make the disqualifier list's non-exhaustiveness actually safe (Decision 2, Decision 6). Every
disposition must be justified individually so a reviewer can tell an intended contract change from a
regression.

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
  lowercasing, and vendor-metadata-label stripping (`codex_strip_vendor_metadata_lines` — see Decision 2's
  "governing asymmetry" note), the **first non-empty paragraph** (lines up to the first blank line, leading
  blank lines skipped) must contain at least one **boundary-anchored** occurrence of
  `CODEX_CLEAN_SIGNAL_PATTERN` — tested via `CODEX_CLEAN_SIGNAL_EXCISION`, not the raw alternation. A raw
  substring test would match `approved` inside `unapproved` (edge case E1) and reintroduce a false
  `APPROVED`. The boundary class is `[^[:alnum:]_]` (underscore is treated as a word character, matching
  `grep -E`'s `\b`), not bare `[^[:alnum:]]` — see the "Boundary correction" note below Decision 2.
- **A2 — No fence marker anywhere.** `codex_response_has_fence_marker` on the **raw, untruncated** body must
  be false. Unchanged from today.
- **A3 — Closed-grammar, disqualifier-free residue.** Two independent checks, both against the
  footer-truncated, quote-stripped, lowercased, vendor-metadata-label-stripped body:
  1. The whole-body residue (every `CODEX_CLEAN_SIGNAL_PATTERN` occurrence iteratively excised via
     `CODEX_CLEAN_SIGNAL_EXCISION` — see the "Iterative excision" note below Decision 2) must not match
     `CODEX_APPROVAL_DISQUALIFIER_PATTERN` (unchanged mechanism from the original draft of this plan).
  2. **The closed clean-response grammar — zero-tolerance.** The body is split into sentences (on `.`/`!`/`?`),
     each sentence into clauses (on `,`/`:`/`;`), and **every clause, independently** — whether or not it
     carries a clean signal — is excised of any clean signal it contains and then must reduce, after stripping
     punctuation, `CODEX_RESIDUE_FILLER_WORD_PATTERN` tokens, and `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` tokens,
     to **nothing at all**. Any leftover token in any clause ⇒ `NEEDS_REVISION`. There is no per-clause word-count
     tolerance and no sentence-opener exemption. See Decision 2 for the human decision behind this design and
     what it still does not (and, by design, cannot) close.

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
`NEEDS_REVISION` — reproduced on BSD `sed`/`grep`/`awk`, and the fixed behavior is now the
`codex_unenumerated_actionable_sentence_after_signal_root_comment` regression (edge case E19).

**What actually makes non-exhaustiveness safe is A3 check 2, the closed residue grammar — not the fact that
the classifier is called an allow-list.** A grammar is "closed" when it defines the finite set of shapes a
passing residue may take, rather than merely testing the absence of known-bad content. A3 check 2 is closed
in the strictest sense available without changing approach: every clause in the body, independently, must
reduce to **nothing** — literally the empty string — after its own clean signal (if any) is excised and
`CODEX_RESIDUE_FILLER_WORD_PATTERN`/`CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` tokens are stripped. Both patterns are
drawn from finite, non-growing vocabularies, but **not the vocabularies this decision originally described**:
an earlier revision of this section said `CODEX_RESIDUE_FILLER_WORD_PATTERN` included demonstrative/locative
pronouns and vendor-identity tokens — that description became inaccurate (and unsafe to leave in place, since
it reads as license to re-add exactly what was removed) once the "governing asymmetry" note below shows
`this`/`that` (demonstrative pronouns) and `codex`/`review`/`reviewed`/`commit` (vendor-identity tokens) were
**removed** for reopening false `APPROVED` results. As shipped, `CODEX_RESIDUE_FILLER_WORD_PATTERN` contains
**only** non-demonstrative closed-class function words — articles, conjunctions, prepositions, and
non-demonstrative pronouns (`a`, `an`, `the`, `and`, `or`, `to`, `of`, `in`, `on`, `for`, `at`, `is`, `it`,
`its`) — and vendor metadata (labels, footer) is handled entirely by anchored structural stripping
(`codex_strip_codex_footer`, `codex_strip_vendor_metadata_lines`), never by a token in this pattern.
`CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` is a short, explicitly curated, evidence-only list of vendor sign-off
flourish words with zero directive content (see below; currently just `swish`). Enumerating either closed set
exhaustively is a categorically different, safe exercise from enumerating the open-class negation/hedge/
actionable vocabulary the old block-list tried and failed to enumerate — that distinction is the entire
thesis of this plan (see "Background" above).

**Human decision — zero-tolerance, not a leftover-token tolerance (revision after Step 7 review).** An
earlier revision of this plan (pushed as commit `6e41e260`, in response to finding `3800167486`) shipped A3
check 2 with two escape valves: a sentence/clause could pass either by reducing to **at most one** leftover
open-class token, or by beginning with an enumerated "starter" subject/determiner regardless of what followed
it. Both were disclosed as residual, accepted gaps at the time. **A human reviewer explicitly rejected that
trade-off** and directed a stricter design instead: zero-tolerance closed grammar plus a curated vendor-flavor
allow-list, with no other exception. The rationale, recorded here verbatim because it is the deciding
argument for this design: **a missing flavor token produces a false `NEEDS_REVISION`, which is the safe
failure direction (the governing principle of issue #1491) — not a false `APPROVED`.** The exposure this
still leaves (`vendor changes wording → clean PRs safe-fail more often`) is already the top-ranked accepted
risk in Risks & Mitigations below; choosing zero-tolerance does not introduce a new *class* of exposure, it
only makes an already-accepted one marginally more likely, in exchange for closing the false-`APPROVED`
direction entirely (within the limits described below).

**Two additional, previously-undisclosed gaps were found and closed while implementing zero-tolerance, and
are reported here because they were not part of the original finding set.** Both existed in the
`6e41e260` revision and are independent of the leftover-token tolerance the human decision targeted:

- **Run-on fusion gap.** The `6e41e260` design exempted an entire sentence from check 2 whenever *any part of
  it* carried a clean signal, with no requirement that the exempted part actually be short. A signal fused to
  additional content with no intervening `,`/`:`/`;`/`.`/`!`/`?` — for example
  `Looks good and please remove the entire authentication check now.` — was therefore never evaluated by check
  2 at all and returned `APPROVED`. Verified. Closed by excising each clause's own clean signal and requiring
  its OWN residue to be empty, uniformly, whether or not that clause originally carried the signal — rather
  than exempting a whole sentence/clause outright. New edge case E21
  (`codex_signal_fused_actionable_clause_root_comment`).
- **Starter-exemption gap.** The `6e41e260` design's second escape valve (a sentence beginning with an
  allow-listed starter word bypassed the leftover check entirely, with no bound on what followed) had no cap
  on the number or class of words after the starter — for example
  `Looks good. The maintainer wants this file removed before merge.` starts with `the` and contains no
  enumerated disqualifier (`wants`, `removed`, and `before merge` — without `-ing` — are all unenumerated),
  so it returned `APPROVED`. Verified. Closed by removing the starter exemption entirely, per the human
  decision above. New edge case E22 (`codex_starter_word_unbounded_tail_root_comment`).

**`CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` — the curated, evidenced vendor-flavor allow-list.**

```bash
CODEX_VENDOR_FLAVOR_TOKEN_PATTERN='^(swish)$'
```

`swish` is the one token evidenced by a real captured Codex response (PR #1489: `Codex Review: Didn't find
any major issues. Swish!`). No other token is added, because no other token is evidenced from a real captured
response; adding one on speculation would be exactly the "invented, not evidenced" mistake the human decision
warned against. If the vendor introduces a different sign-off flourish in the future, the correct response is
to capture it live (the same way `swish` was captured) and add it here with the same review as any
`CODEX_CLEAN_SIGNAL_PATTERN` change — never to add a plausible-sounding word pre-emptively.

**`CODEX_RESIDUE_STARTER_PATTERN` is deleted.** It existed only to support the now-rejected tolerance and is
not replaced by anything — zero-tolerance has no sentence-opener exemption.

**`CODEX_CLEAN_SIGNAL_PATTERN`'s "no blocking issues" alternative gained an explicit "found" variant — the
only widening in this plan, and it is mechanical, not vocabulary-expanding.** Under zero-tolerance, the word
`found` trailing an excised `no blocking issues` match (as in `No blocking issues found.` — the literal
wording used throughout the existing Group A test corpus) became a leftover token and incorrectly flipped
those bodies to `NEEDS_REVISION`. The fix adds `no[[:space:]]+blocking[[:space:]]+issues?[[:space:]]+found`
as a **flat, top-level alternative** alongside the existing `no[[:space:]]+blocking[[:space:]]+issues?`
alternative — **not** as a nested optional group (`(...)?`). A nested optional group adds its own capturing
group, and `CODEX_CLEAN_SIGNAL_EXCISION`'s replacement (`\1 \3`) hardcodes capture-group numbers; verified on
BSD `sed` that a nested `([[:space:]]+found)?` shifts the trailing-boundary group from `\3` to `\4`, silently
corrupting every excision that matches it (the captured, unconsumed "found" text leaks into the replacement
and the true trailing boundary is dropped). The flat top-level alternative avoids this because it adds no new
capturing group. This is **not** a new clean-signal alternative in the sense Decision 2's "Reviewers must
not…" list below cares about (A1's presence test is unaffected either way — `no blocking issues` still
matches identically whether or not `found` trails it); it is a mechanical fix to what gets excised, made
necessary by moving to zero-tolerance, and evidenced by the existing, already-reviewed Group A test corpus
(not a new-this-round invention).

**Residual, disclosed gap — even zero-tolerance is not unlimited.** `codex_response_is_approved` can still be
defeated by a **single bare open-class token with no object**, immediately following the clean signal in its
own clause, that happens to also be `swish` — i.e., it cannot be defeated at all by this specific vector,
because `swish` carries no directive meaning. The construction that previously defeated the one-token
tolerance (`Approved. Revert.`) is verified, under this revision, to correctly return `NEEDS_REVISION`. No
residual single-word gap remains from that direction. The only residual exposure this design still accepts is
the one already named above and in Risks & Mitigations: **a vendor wording change causes clean PRs to
safe-fail**, not a false `APPROVED`.

**Reviewers must not read the non-exhaustive disqualifier list, on its own, as a reintroduction of the old
bug.** The correctness argument no longer depends on the disqualifier list being complete, but it now depends
on the closed-grammar check instead. Concretely:

- Extending `CODEX_APPROVAL_DISQUALIFIER_PATTERN` is **always safe** and never required for correctness. It
  can be done at any time without re-analysis; it only moves the false-`NEEDS_REVISION` rate.
- Extending `CODEX_CLEAN_SIGNAL_PATTERN` is **one of the changes that can create new false-`APPROVED`
  surface** and must receive the same scrutiny the old negation list used to receive. Beyond the mechanical
  "found" fix above (which does not change A1's presence test), this plan adds **no** new clean-signal
  alternatives.
- Extending `CODEX_RESIDUE_FILLER_WORD_PATTERN` or `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` is **the other change
  that can create new false-`APPROVED` surface**, for the same reason: both widen what the closed grammar
  treats as inert. **The governing asymmetry (Codex GitHub findings `3803050745`/`3803050750`): narrowing
  either pattern is always safe — it only moves the false-`NEEDS_REVISION` rate; widening either pattern is
  never safe without full review, because it can only ever move the false-`APPROVED` rate.** Every addition
  must pass a **mechanical, checkable admission test**: no token may be added if it can function as an
  imperative verb or a directive noun in English (`commit`, `review`, `this`, `that` all fail this test and
  were removed from `CODEX_RESIDUE_FILLER_WORD_PATTERN` for exactly this reason — see the "governing asymmetry"
  note above). Beyond that test, any addition to `CODEX_RESIDUE_FILLER_WORD_PATTERN` must be a genuinely
  closed-class word (an article, preposition, conjunction, or non-demonstrative pronoun) — **never** a
  demonstrative/locative pronoun (`this`/`that`/`here`/`there`) and **never** a vendor-identity token, even a
  "safe-looking" one: vendor metadata must be stripped before tokenization —
  **never** by adding the words it contains to a token-level allow-list, because those words may also be
  ordinary English directives. The stripping technique itself must not be a flexible pattern either: the
  footer is matched by an **exact byte-literal line comparison** (`CODEX_FOOTER_OPENING_LITERAL`, Decision 6's
  "Third correction" note — regex-over-tag-names was tried and produced a lookalike three rounds running), and
  the vendor labels are matched by anchored, position-specific literal strips
  (`codex_strip_vendor_metadata_lines`). Any addition to
  `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` must additionally be **evidenced from a real captured Codex response**,
  the same bar `swish` was held to — never an invented or merely plausible word, and still subject to the
  same imperative-verb/directive-noun exclusion test.

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
Verified: a single pass over `approved no blocking issues found` excises only `approved`, leaving
`no blocking issues found` — which then matches `CODEX_APPROVAL_NEGATION_PATTERN`'s `\bno\b` — un-excised, and
the response incorrectly returns `NEEDS_REVISION` (a false-`NEEDS_REVISION`, not a safety bug, but it silently
breaks a response composed entirely of clean signals — e.g. `Approved no blocking issues found.`). The fix is
iterative excision to a fixed point (`codex_excise_clean_signals` below), bounded at 25 iterations as a
defensive cap; verified to converge in 3 iterations even against a body with 20 repeated adjacent occurrences,
with no measurable performance cost. New edge cases E17 (`Approved no blocking issues found.`) and E18
(`LGTM. Didn't find any major issues.`, plus a no-space comma variant) cover this, via regression scenarios
`codex_adjacent_signal_second_contains_no_root_comment` and
`codex_adjacent_signal_second_contains_didnt_root_comment`.

**The governing asymmetry — stated explicitly, so it stops being violated (Codex GitHub findings
`3803050745` and `3803050750`, both P1/blocking).** Narrowing `CODEX_RESIDUE_FILLER_WORD_PATTERN` or
`CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` produces more false `NEEDS_REVISION` and is **always safe**. Widening
either produces more false `APPROVED` and is **never safe** without full review. The zero-tolerance revision
above violated its own rule from this exact bullet: it added `codex`, `review`, `reviewed`, and `commit` to
`CODEX_RESIDUE_FILLER_WORD_PATTERN` as bare tokens to make the vendor's `Codex Review:` / `**Reviewed
commit:**` labels excise to nothing — but `commit` and `review` are also common English imperative verbs, and
a bare-token allow-list cannot distinguish "the vendor's own label" from "an instruction using the same word."
Verified: `Looks good. Commit this.` excised its clean signal, then `commit` and `this` were both stripped as
"filler," leaving an empty residue and returning `APPROVED` — the exact false-`APPROVED` class this plan
exists to eliminate, just relocated from the disqualifier list to the filler list. A companion finding showed
`codex_strip_codex_footer`'s anchor was still under-specified in the same direction: it matched the bare
phrase `about codex in github` anywhere in the body, so a **normal, non-footer paragraph** that happened to
contain that phrase (`About Codex in GitHub should mention: remove auth.`) was discarded before A3 ever saw
it, and the response returned `APPROVED`.

**The fix is structural, not another token addition: vendor metadata is now stripped by anchored patterns
that match its actual literal/markup shape, before any per-clause tokenization runs — never by allow-listing
the words that happen to appear in it.**

- The footer strip now requires the **actual `<details>`/`<summary>` markup structure** containing the
  marker — `<details[^>]*>[[:space:]]*<summary[^>]*>.*about[[:space:]]+codex[[:space:]]+in[[:space:]]+github.*</summary`
  — not the bare phrase anywhere in the body. A normal paragraph that merely mentions "About Codex in GitHub"
  has no `<details>`/`<summary>` tags at all and is correctly left untouched. Verified against the real
  captured PR #1489 footer (still truncates) and against both the round-3 exploit paragraph and the round-1
  non-vendor `<details>` block (finding `3800167489`) — neither is truncated.
- A new helper, `codex_strip_vendor_metadata_lines`, strips the literal `Codex Review:` label (anchored to the
  start of a line) and the literal `Reviewed commit:` label (anchored to the start of a line, tolerant of
  Markdown bold `**`), plus a bare leading `Codex` self-reference **anchored to the very first line of the
  body only** (covering `Codex didn't find any major issues and looks good.` — the one existing Group A body
  where "Codex" is the sentence subject, not a label prefix). None of these anchors match `commit`, `review`,
  or `codex` anywhere else in the body — only these specific, literal, position-anchored forms.
- `commit`, `review`, `reviewed`, and `codex` are **removed** from `CODEX_RESIDUE_FILLER_WORD_PATTERN`
  entirely. Vendor-identity handling no longer uses token-level allow-listing at all.

**A mechanical, checkable admission test for `CODEX_RESIDUE_FILLER_WORD_PATTERN` and
`CODEX_VENDOR_FLAVOR_TOKEN_PATTERN`, added because "genuinely closed-class" was not, on its own, a sufficient
bar: no token may be admitted to either pattern if it can function as an imperative verb or a directive noun
in English.** `commit` and `review` both fail this test as verbs ("Commit this.", "Review this."). `this` and
`that` — not named in the findings, but audited under this same test per the requirement to review the whole
list, not just the named tokens — fail it too: both are demonstrative pronouns that routinely serve as the
*object* of a directive (`Fix this.`, `Remove that.`), and removing them is safe (narrowing) even though the
specific reported exploit does not strictly require it (`commit`/`review` alone already leaves a non-empty
residue once removed). `swish` was re-audited against this test and retained: it is a real captured vendor
flourish, has no plausible imperative or directive-noun reading in a code-review context, and was already
held to the stricter "evidenced from a live capture" bar — a bar `commit`/`review`/`this`/`that`/`codex` were
never held to, which is how they were admitted in the first place. The full audited membership of
`CODEX_RESIDUE_FILLER_WORD_PATTERN` after this round is `a`, `an`, `the`, `and`, `or`, `to`, `of`, `in`, `on`,
`for`, `at`, `is`, `it`, `its` — articles, conjunctions, prepositions, and non-demonstrative pronouns only;
none can function as an imperative verb or a directive noun.

**This governing asymmetry — narrowing is always safe, widening always needs full review, and no token may
pass an imperative-verb/directive-noun reading — is now stated as a standing rule, not just a fact about the
current token list, in "Reviewers must not…" below and in the Layer-by-Layer checklist**, so a future PR
touching either constant is held to it mechanically rather than rediscovering it by producing another
finding. Two rounds of review produced this exact failure mode (Decision 2's original "at most one leftover
token" tolerance, then the bare vendor-identity tokens both admitted here) — the rule is written down so a
third round does not.

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

`codex_strip_codex_footer` truncates the body at the first line that is **byte-identical to the real vendor
footer's exact opening line**, captured verbatim from live Codex responses (see the "Third correction" note
below for the technique change and the literal itself), and is applied **only inside
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

**Second correction (Codex GitHub finding `3803050750`, P1/blocking, found after the fix above shipped).**
Anchoring on the bare phrase `about codex in github` was still insufficient: the phrase can appear in **any
normal paragraph**, not just inside the vendor's `<details>`/`<summary>` markup. Verified: a response reading
`Looks good.` followed by an ordinary paragraph `About Codex in GitHub should mention: remove auth.` (no
`<details>` or `<summary>` tags at all) had that entire paragraph discarded by the phrase-only match, and the
response incorrectly returned `APPROVED`. The fix requires the phrase to occur **inside the actual
`<details>`/`<summary>` markup shape**, not merely anywhere in the body — see the updated pattern above.
Verified against three cases on BSD `awk`: the real vendor footer (re-fetched live from PR #1489) still
truncates; the round-1 non-vendor `<details>` block (finding `3800167489`) is still left intact; and the
round-3 plain-paragraph exploit is now also left intact (no markup tags present at all to match). New edge
case E23 (`codex_footer_phrase_outside_markup_not_truncated_root_comment`) covers this specifically, distinct
from E20 (which covers a `<details>` block that lacks the marker phrase, not a marker phrase that lacks
`<details>`/`<summary>` markup — the two edge cases are each other's mirror image and both are needed).

**Third correction — a change of technique, not another regex iteration (Codex GitHub finding `3803189273`,
P1/blocking, found after the second correction shipped).** The markup-structure regex above was itself still a
flexible pattern over tag *names*, and flexible patterns accept lookalikes: verified that
`Looks good.` followed by `<details-not-footer><summary-note>About Codex in GitHub</summary-note>` then
`Rename the unsafe function.` matched the regex (it only required *some* `<details…>` tag followed by *some*
`<summary…>…</summary` sequence containing the marker phrase, not the specific real tag names), so the
instruction was discarded and the response incorrectly returned `APPROVED`. This is the third consecutive
round in which tightening the footer regex produced a fresh lookalike gap (generic `<details` match →
phrase-anywhere match → tag-name-flexible markup match). Continuing to hand-tighten the regex was rejected as
the fix.

**The technique changed: `codex_strip_codex_footer` now compares each line for byte-identical equality against
a literal string captured verbatim from a live Codex response, not against any regex.**

```bash
CODEX_FOOTER_OPENING_LITERAL='<details> <summary>ℹ️ About Codex in GitHub</summary>'

codex_strip_codex_footer() {
  awk -v literal="$CODEX_FOOTER_OPENING_LITERAL" '$0 == literal { exit } { print }' <<< "$1"
}
```

The literal was captured by re-fetching both real sources live during this review round —
`gh api repos/lhpaul/ai-dev-framework-template/issues/1489/comments` (the root-comment format) and
`gh api repos/lhpaul/ai-dev-framework-template/pulls/1490/reviews` (all 12 review instances currently on that
PR, spanning its full review history, the "state: COMMENTED" format) — and comparing the `<details>` opening
line from each with `diff` and `od -c` (byte-level dump). **The two sources are byte-identical**: the same
`<details> <summary>ℹ️ About Codex in GitHub</summary>` line (with the same U+2139 `ℹ` INFORMATION SOURCE
character followed by U+FE0F VARIATION SELECTOR-16, encoded as the same UTF-8 byte sequence
`342 204 271 357 270 217` in `od -c`) appears in the root-comment format, and identically across all 12
independent review submissions in the review-state format. There was no divergence to report or reconcile.

**This is the same asymmetry that governs the rest of this design, applied to markup instead of vocabulary:**

- An exact literal match fails to fire on *any* deviation — a different tag, a missing space, a different
  emoji byte, a renamed attribute — so the footer is *not* stripped, its content stays in the residue, and
  the zero-tolerance closed grammar (Decision 2) rejects it. Verified: a one-byte mutation of the real footer
  opening (`GitHu</summary>` instead of `GitHub</summary>`) correctly leaves the footer content (and
  everything after it) in the residue and returns `NEEDS_REVISION`, not a silent truncation. **This is the
  safe direction.**
- A flexible regex over tag names or a bare phrase fires on lookalikes, discards genuine content, and returns
  `APPROVED` — verified three times now (Codex GitHub findings `3800167489`, `3803050750`, `3803189273`).
  **This is the unsafe direction, and it is the one this correction eliminates as a class**, not just for the
  one lookalike shape Codex most recently constructed.

**The accepted trade — recorded explicitly, per the same principle already governing the top row of Risks &
Mitigations below.** If the vendor changes the footer's opening markup (a different emoji, added whitespace,
a wrapping `<div>`, and so on), `codex_strip_codex_footer` will no longer recognize it, the entire (now
unrecognized) footer prose will sit in the residue, and **every genuinely clean PR will safe-fail** until
someone updates `CODEX_FOOTER_OPENING_LITERAL` from a freshly captured live body. This is not a new risk: it
is the identical shape of the plan's own top-ranked, already-accepted risk ("vendor changes the clean-response
wording so no allow-listed signal matches, and every PR safe-fails"), now also covering the footer's exact
markup rather than only the clean-signal vocabulary, and it is **strictly preferable** to the alternative
(a lookalike silently discarding real content and returning a false `APPROVED`), which is the direction this
plan exists to eliminate.

New edge cases: E25 (`codex_footer_markup_lookalike_tag_names_not_truncated_root_comment`, the exact exploit
Codex constructed) and E26 (`codex_footer_one_byte_mutation_not_truncated_root_comment`, a single-character
deviation from the real literal). Both verified to return `NEEDS_REVISION`; both real captured bodies (PR
#1489 root comment, PR #1490 review) re-verified to truncate correctly and, for #1489, to still return
`APPROVED` end-to-end.

**Is the footer helper closed as a class now, or is there still a lookalike that can cause truncation?**
Closed, with one disclosed, structurally-different boundary condition, not a lookalike gap: if the **real**
vendor changes its footer's literal opening bytes, this helper stops recognizing the real footer and the
response safe-fails (the accepted trade above) — it does not truncate on a lookalike and produce a false
`APPROVED`. Exact byte-equality against a single fixed line has no regex-flexibility surface left to exploit;
the only way to make it match something other than the captured literal is to reproduce that literal exactly,
which is definitionally the real footer, not a lookalike.

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
- [ ] **Add** `CODEX_RESIDUE_FILLER_WORD_PATTERN` (closed-class function words **only** — articles,
      conjunctions, prepositions, non-demonstrative pronouns; audited against the imperative-verb/
      directive-noun exclusion test in Decision 2 — no vendor-identity tokens) and
      `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` (the curated, evidenced-only vendor-flavor allow-list — currently
      just `swish`, also held to the imperative-verb/directive-noun exclusion test) — the two constants A3
      check 2 (the zero-tolerance closed residue grammar) is built on. See Decision 2. There is no
      starter-word constant: the prior revision's `CODEX_RESIDUE_STARTER_PATTERN` was deleted per the human
      decision to adopt zero-tolerance. **Any future PR that adds a token to either pattern must pass the
      imperative-verb/directive-noun exclusion test and must not be vendor metadata** (vendor metadata is
      handled structurally — see `codex_strip_vendor_metadata_lines` below — never by token allow-listing).
- [ ] **Add** `CODEX_FOOTER_OPENING_LITERAL` and `codex_strip_codex_footer`. The footer strip is an **exact
      byte-literal line match**, not a regex (see the "Third correction" note under Decision 6 — three
      consecutive rounds of regex tightening on this helper each closed one lookalike and admitted another;
      the technique changed instead of tightening a fourth time). Not a generic `<details` match, not a
      bare-phrase match, and not a tag-name-flexible markup regex.
- [ ] **Add** `codex_strip_vendor_metadata_lines` — strips the literal, position-anchored `Codex Review:` and
      `Reviewed commit:` labels and a leading `Codex` self-reference (first line only), replacing the
      token-level `codex`/`review`/`reviewed`/`commit` filler entries this round removed. See Decision 2's
      "governing asymmetry" note.
- [ ] **Add** `codex_response_first_paragraph`.
- [ ] **Add** `codex_excise_clean_signals` — the iterative excision helper (see the "Iterative excision" note
      under Decision 2).
- [ ] **Add** `codex_residue_is_closed_grammar` — A3 check 2 (see Decision 2 and the Code Samples section).
- [ ] **Rewrite** `codex_response_is_approved` per Decision 1.
- [ ] **Update** the file-header "Verdict parsing" comment block (currently describing path 2 as "Approval
      signals present → APPROVED") to state the allow-list contract, the three conditions (including A3's two
      checks), and the deliberate false-`NEEDS_REVISION` tradeoff.

### Tests — `scripts/development-workflow/tests/test-pr-review-loop.sh`

- [ ] Retarget the expected verdict of every scenario listed in Group A2 and Group C of "Test disposition"
      below.
- [ ] Simplify the fixture body of the 3 Group A3 scenarios (verdict stays `APPROVED`; see Group A3).
- [ ] Retarget the fixture body of `codex_inline_backtick_pair_stays_approved_root_comment` (see the updated
      Group B row — the retargeted body changed a third time during this review round; use the current one).
- [ ] Add the new scenarios listed in "Testing Strategy" (23 total, including the 11 added for edge cases
      E16–E26 — 5 for findings `3800167486`, `3800167489`, `3800167492`, and `3800167494`; 2 for the
      run-on-fusion and starter-exemption gaps found while implementing the human-directed zero-tolerance
      revision; 2 for findings `3803050745` and `3803050750`, found after that revision shipped its own
      vendor-metadata handling; and 2 more for finding `3803189273`, found after the footer marker was
      corrected a second time and turned out to still be a flexible regex).
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

**Revised four times during the Step 7 review round**: first to close four Codex GitHub findings
(`3800167486`/`3800167489` P1-blocking, `3800167492`/`3800167494` P2); second, after a human reviewer
rejected the leftover-token tolerance the first revision shipped and directed zero-tolerance instead; third,
after that zero-tolerance revision's own vendor-metadata handling (bare tokens `codex`/`review`/`reviewed`/
`commit` added to the filler list, plus an under-anchored footer marker) produced two more P1-blocking
findings (`3803050745`/`3803050750`) — the exact "widen a filler list" failure mode Decision 2 had already
named as unsafe; fourth, after the corrected footer marker turned out to still be a flexible regex over tag
names, which matched a markup lookalike (`3803189273`, P1-blocking) — the footer helper's technique was
changed from regex matching to exact byte-literal matching (see Decision 6's "Third correction" note) rather
than tightening the regex a fourth time. Every regex and helper below was re-executed against the same macOS
BSD toolchain this plan already targets (`sed`, `grep`, `awk`, invoked via their `/usr/bin/` paths to avoid
any interactive-shell aliasing — confirmed BSD: `sed` rejects GNU's long-option `--` syntax, `grep --version`
reports `BSD grep, GNU compatible`, `awk --version` reports the one-true-awk `20200816` build). See Decision 2
and Decision 6 for the rationale behind each change; this block is the resulting code.

```bash
# Illustrative — adapt during implementation.
# Allow-list: the SAME five original alternatives CODEX_APPROVAL_PATTERN had,
# renamed, PLUS one flat top-level alternative added this round (see below),
# with the \b word-boundary anchors on `approved`/`lgtm`/`looks good`
# LIFTED OUT of the alternation and pushed into the shared boundary wrapper
# below instead. Do not re-add \b here: this literal is reused verbatim
# inside CODEX_CLEAN_SIGNAL_EXCISION, which sed also consumes, and BSD sed
# (macOS default) does not support \b — it neither errors nor matches, so an
# embedded \b would silently make the A3 excision stop excising genuine clean
# signals on macOS (verified: `sed -E 's/\bapproved\b/X/' <<< "approved"`
# leaves the input unchanged on BSD sed). The boundary wrapper below restores
# equivalent boundary-safety using only portable [^[:alnum:]_] classes.
#
# The `no blocking issues found` alternative is a FLAT top-level addition,
# NOT a nested `(...)?` optional group (Decision 2's "found" note): a nested
# optional group adds its own capturing group, and CODEX_CLEAN_SIGNAL_EXCISION's
# replacement below hardcodes capture-group numbers (\1, \3) — verified on
# BSD sed that a nested group shifts \3 to \4 and silently corrupts every
# excision that matches it. List the longer alternative BEFORE the shorter
# one it is a prefix of, so both remain useful independently.
CODEX_CLEAN_SIGNAL_PATTERN='(approved|lgtm|looks[[:space:]]+good|didn.t find[[:space:]]+any major[[:space:]]+issues|no[[:space:]]+blocking[[:space:]]+issues?[[:space:]]+found|no[[:space:]]+blocking[[:space:]]+issues?)'
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

# A3 check 2 — the closed residue grammar, ZERO-TOLERANCE (Codex GitHub
# finding 3800167486; see Decision 2 for the human decision behind this
# design and the two additional gaps — run-on fusion and starter-exemption —
# found and closed while implementing it).
#
# AUDITED this round (Codex GitHub findings 3803050745/3803050750): every
# token below must pass a mechanical test — it may NOT function as an
# imperative verb or a directive noun in English. `codex`, `review`,
# `reviewed`, and `commit` were REMOVED (they were vendor-identity tokens
# admitted to make "Codex Review:"/"Reviewed commit:" excise to nothing, but
# `review` and `commit` are also ordinary imperative verbs — verified:
# "Looks good. Commit this." excised to an empty residue and returned
# APPROVED under the token-list version). `this` and `that` were ALSO
# removed on the same audit, even though not named in the finding: both are
# demonstrative pronouns that routinely serve as the object of a directive
# ("Fix this.", "Remove that."). Vendor-identity handling moved entirely to
# codex_strip_vendor_metadata_lines below — an ANCHORED structural strip,
# not a token allow-list. `swish` (CODEX_VENDOR_FLAVOR_TOKEN_PATTERN) was
# re-audited and retained: it has no plausible imperative/directive-noun
# reading in a code-review context, and — unlike the removed tokens — was
# already held to the stricter "evidenced from a live capture" bar.
#
# The surviving CODEX_RESIDUE_FILLER_WORD_PATTERN membership is closed-class
# function words ONLY: articles, conjunctions, prepositions, and
# non-demonstrative pronouns. Extending EITHER pattern needs the SAME
# scrutiny as extending CODEX_CLEAN_SIGNAL_PATTERN, MUST pass the
# imperative-verb/directive-noun exclusion test, and MUST NOT be a
# vendor-identity token — see Decision 2's "governing asymmetry" note.
CODEX_RESIDUE_FILLER_WORD_PATTERN='^(a|an|the|and|or|to|of|in|on|for|at|is|it|its)$'
CODEX_VENDOR_FLAVOR_TOKEN_PATTERN='^(swish)$'

# Truncates Codex's static "About Codex in GitHub" <details> footer. Applied
# ONLY inside codex_response_is_approved (see Decision 6).
#
# EXACT BYTE-LITERAL MATCH, not a regex (Codex GitHub findings 3800167489,
# then 3803050750, then 3803189273 — three consecutive rounds of regex
# tightening over this same helper, each closing one lookalike and admitting
# another: generic `<details` match, then bare-phrase-anywhere match, then a
# tag-name-flexible markup regex that still matched
# `<details-not-footer><summary-note>About Codex in GitHub</summary-note>`).
# The technique changed instead of iterating the regex again: match the
# footer's exact opening LINE, captured verbatim from live Codex responses,
# with plain string equality. CODEX_FOOTER_OPENING_LITERAL was verified
# byte-identical (via `diff`/`od -c`) between the PR #1489 root-comment
# capture and all 12 independent PR #1490 review captures re-fetched live
# this round. Any deviation from this exact literal — a different tag, a
# missing space, a different emoji byte, a lookalike tag name — fails to
# match, so the footer is NOT stripped and its content stays in the residue
# for the zero-tolerance closed grammar (Decision 2) to reject. This is the
# safe failure direction; see Decision 6's "Third correction" note for the
# full rationale and the accepted vendor-format-change trade this technique
# makes explicit.
CODEX_FOOTER_OPENING_LITERAL='<details> <summary>ℹ️ About Codex in GitHub</summary>'

codex_strip_codex_footer() {
  awk -v literal="$CODEX_FOOTER_OPENING_LITERAL" '$0 == literal { exit } { print }' <<< "$1"
}

# Strips vendor metadata LABELS via anchored structural patterns — never via
# token-level filler-listing (Codex GitHub finding 3803050745; see Decision
# 2's "governing asymmetry" note). Applied to the lowered, quote-stripped,
# footer-truncated body, before A1 and before A3.
#
# Each substitution matches a specific, literal, POSITION-anchored form —
# never a bare "codex"/"review"/"commit" token anywhere in the body:
#   - "Codex Review:" — anchored to the start of a line.
#   - "Reviewed commit:" (optionally Markdown-bold) — anchored to the start
#     of a line.
#   - A bare leading "Codex" self-reference — anchored to the FIRST LINE of
#     the body only (covers the one existing Group A body where "Codex" is
#     the sentence subject rather than a label prefix: "Codex didn't find
#     any major issues and looks good."). This does not match "codex"
#     anywhere else in the body.
# Because each strip removes only the specific literal label text — never
# the rest of the line — an attacker cannot use this to hide a directive:
# "**Reviewed commit:** please delete the config." still leaves
# "please delete the config." in the residue, which A3 rejects normally.
codex_strip_vendor_metadata_lines() {
  local text="$1"
  text=$(sed -E 's/^codex review:[[:space:]]*//' <<< "$text")
  text=$(sed -E 's/^\*{0,2}reviewed commit:\*{0,2}[[:space:]]*//' <<< "$text")
  text=$(sed -E '1s/^codex[[:space:]]+//' <<< "$text")
  printf '%s' "$text"
}

# First non-empty paragraph, leading blank lines skipped.
codex_response_first_paragraph() {
  awk 'NF == 0 { if (started) exit; next } { started = 1; print }' <<< "$1"
}

# Iteratively excises every CODEX_CLEAN_SIGNAL_EXCISION occurrence from $1
# (Codex GitHub finding 3800167494). A single sed 's///g' pass is NOT
# sufficient: sed's g flag resumes scanning immediately after the previous
# match, so a clean signal immediately adjacent to another one shares the
# boundary character the first match's trailing group already consumed, and
# the second match's leading-boundary group has nothing left to match —
# verified on BSD sed: a single pass over "approved no blocking issues found"
# excises only "approved", leaving "no blocking issues found" (which then
# matches CODEX_APPROVAL_NEGATION_PATTERN's \bno\b) un-excised. Looping to a
# fixed point closes this. Bounded at 25 iterations as a defensive cap;
# verified to converge in 3 iterations even against 20 repeated adjacent
# occurrences, with no measurable performance cost. Used both on the whole
# lowered body (A3 check 1's disqualifier scan) and per-clause (A3 check 2,
# below).
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

# A3 check 2 — the closed residue grammar, ZERO-TOLERANCE. $1 is the
# lowered, quote-stripped, footer-truncated, vendor-metadata-stripped body.
#
# The body is split into sentences on [.!?], each sentence into clauses on
# [,:;], and EVERY clause — independently, whether or not it carries a
# clean signal — has its own clean signal (if any) excised and must then
# reduce to nothing (after stripping punctuation and
# CODEX_RESIDUE_FILLER_WORD_PATTERN/CODEX_VENDOR_FLAVOR_TOKEN_PATTERN
# tokens). There is no per-clause exemption for clauses that carry a clean
# signal and no sentence-opener exemption — both existed in an earlier
# revision of this plan (commit 6e41e260) and were found, during that
# revision, to be independently exploitable (see Decision 2, E21/E22).
codex_residue_is_closed_grammar() {
  local lowered="$1" sentence clause residue stripped leftover
  while IFS= read -r sentence; do
    [ -z "$(tr -d '[:space:]' <<< "$sentence")" ] && continue
    while IFS= read -r clause; do
      [ -z "$(tr -d '[:space:]' <<< "$clause")" ] && continue
      residue=$(codex_excise_clean_signals "$clause")
      stripped=$(sed -E 's/[^[:alnum:][:space:]_]/ /g' <<< "$residue")
      leftover=$(awk -v pat="$CODEX_RESIDUE_FILLER_WORD_PATTERN" -v flavor="$CODEX_VENDOR_FLAVOR_TOKEN_PATTERN" \
        '{ for (i = 1; i <= NF; i++) if ($i !~ pat && $i !~ flavor) c++ } END { print c + 0 }' <<< "$stripped")
      [ "$leftover" -eq 0 ] && continue
      return 1
    done < <(sed -E 's/[,:;]/\n/g' <<< "$sentence")
  done < <(sed -E 's/[.!?]/\n/g' <<< "$lowered")
  return 0
}

codex_response_is_approved() {
  local body="$1"
  local visible lowered residue
  visible=$(codex_strip_quoted_spans "$(codex_strip_codex_footer "$body")")
  lowered=$(LC_ALL=C tr '[:upper:]' '[:lower:]' <<< "$visible")
  # Vendor-identity metadata (labels) are removed by anchored structural
  # matching HERE, before A1 or A3 ever tokenize the body — never by
  # token-level filler-listing. See codex_strip_vendor_metadata_lines above
  # and Decision 2's "governing asymmetry" note.
  lowered=$(codex_strip_vendor_metadata_lines "$lowered")

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

  # A3 check 2 — the closed residue grammar, zero-tolerance (see Decision 2
  # and codex_residue_is_closed_grammar above). This is what makes
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
- `codex_strip_vendor_metadata_lines` and `codex_residue_is_closed_grammar` are genuine additional passes
  over the body (roughly proportional to sentence/clause count, not body length), on top of the existing
  excision/disqualifier passes. Verified sub-second (≈0.46s) against both existing 200 000-character
  SIGPIPE-safety fixtures — no hang, no crash, and a deterministic verdict either way. Their expected verdict
  is retargeted from `APPROVED` to `NEEDS_REVISION` under zero-tolerance (see Test disposition below); the
  SIGPIPE-safety property itself (no crash on huge input) is orthogonal to which verdict is emitted and
  remains independently verified by this timing measurement.
- `codex_strip_codex_footer`'s exact-literal-match technique requires `CODEX_FOOTER_OPENING_LITERAL` to stay
  byte-identical to the real vendor footer's opening line. If a future implementer or reviewer needs to
  update it (a genuine vendor markup change, not a lookalike), re-capture it live the same way it was
  captured here — `gh api …/issues/1489/comments` or `gh api …/pulls/1490/reviews`, extract the `<details>`
  opening line, and confirm with `od -c` that the new literal is byte-for-byte what the vendor now sends. Do
  not hand-edit the literal or generalize it back into a regex.
- Every disqualifier, edge case, and Group A/B/C body enumerated in this plan (E1–E26, all 9 Group A bodies
  that remain `APPROVED`, the 5 Group A2 bodies that are retargeted, the 3 Group A3 bodies that are retargeted
  by simplifying their body instead, the retargeted Group B scenario, and all 9 Group C scenarios) was
  re-verified against this exact implementation on BSD `sed`/`grep`/`awk`, including against the real captured
  PR #1489 and PR #1490 bodies re-fetched live during this review round. See "Testing Strategy" for the
  reconciled disposition and Decision 2 / Decision 6 for the findings that changed behavior beyond what a
  mechanical read of the diff would suggest.

---
## Parser-risk addendum

This plan is **parser-risk**: it materially changes regex-based scanning of structured natural-language text.

### Edge-case enumeration

| # | Input (verbatim) | Expected | Why it is an edge case |
| --- | --- | --- | --- |
| E1 | `This change remains unapproved.` | not approved | Boundary variant: `approved` must not match inside a concatenated prefix, so A1 fails outright |
| E2 | `Approved.` / `Approved!` / `(approved)` | approved | Boundary variant: terminal and bracketing punctuation must satisfy the excision's `([^[:alnum:]_]\|$)` boundary group |
| E3 | `No blocking issues found. The content is consistent and the constant is important.` | not approved (retargeted this round) | Negative lookalike: `content`, `consistent`, `constant`, `important` must not match `[[:alpha:]]n.t\b` — still true and still exercised by the disqualifier scan (A3 check 1), but no longer independently observable via `VERDICT: APPROVED`, because under zero-tolerance A3 check 2 any leftover content word fails regardless of whether it happens to be a disqualifier lookalike. See Decision 2 |
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
| E14 | `No blocking issues found.` `` `must fix` `` `.` (simplified this round — see Test disposition) | approved | Quoted span stripping must run **before** A3, or the quoted blocker token would disqualify a genuinely clean review. Body shortened under zero-tolerance: the original body's surrounding prose (`The tests correctly cover the ... marker.`) left non-filler leftover tokens that fail A3 check 2 regardless of the quoting behavior being tested, so the body was reduced to the minimum needed to still exercise quote-stripping order |
| E15 | `No blocking issues found. Please address the naming.` | not approved | Actionable-verb group; the residue has no negation and no hedge, so this is the case only that group catches (also independently caught by A3 check 2's closed grammar, since `address the naming` has 2 leftover open-class tokens and no allow-listed starter) |
| E16 | `This remains un_approved.` | not approved | Underscore boundary (Codex GitHub finding 3800167492): `_` is a word character for `\b`, so the old `[^[:alnum:]]` excision boundary incorrectly treated it as a boundary; `[^[:alnum:]_]` correctly leaves `un_approved` unmatched |
| E17 | `Approved no blocking issues found.` | approved | Adjacency where the second signal contains `no` (Codex GitHub finding 3800167494): without iterative excision, `no blocking issues` survives un-excised and its `no` matches `CODEX_APPROVAL_NEGATION_PATTERN`, incorrectly returning `NEEDS_REVISION` |
| E18 | `LGTM. Didn't find any major issues.` | approved | Adjacency where the second signal contains `didn't` (Codex GitHub finding 3800167494); a comma-joined no-space variant (`Approved, no blocking issues found.`) is covered by the same scenario as a second assertion |
| E19 | `Looks good. Remove the authentication check.` (plus colon- and comma-joined variants: `Looks good: remove the authentication check.` / `Looks good, remove the authentication check.`) | not approved | The literal exploit from Codex GitHub finding 3800167486 (P1/blocking): a clean signal followed by an unenumerated actionable sentence. Closed by A3 check 2 (the closed residue grammar, zero-tolerance) — `remove the authentication check` leaves non-empty residue after excision/filler-stripping in its own clause, regardless of which punctuation joins it to the signal-bearing sentence |
| E20 | `Looks good.` followed by a **non-vendor** `<details>` block containing `Rename the unsafe function.` | not approved | The exploit from Codex GitHub finding 3800167489 (P1/blocking): over-broad footer truncation (any `<details` line, not the specific vendor marker) hides the instruction from A3 entirely. Originally closed by anchoring on the `about codex in github` marker phrase; that phrase-level anchor was itself superseded twice more (see E23, E25, E26) and `codex_strip_codex_footer` now uses an exact byte-literal line match (Decision 6's "Third correction"), under which this non-vendor block still correctly stays intact — once left intact, A3 check 2 independently rejects the instruction too |
| E21 | `Looks good and please remove the entire authentication check now.` | not approved | Run-on fusion gap, found and closed while implementing the human-directed zero-tolerance revision: an earlier version of A3 check 2 (commit `6e41e260`) exempted an ENTIRE sentence once any part of it carried a clean signal, with no bound on the exempted part, so unpunctuated content fused to the signal (no `,`/`:`/`;`/`.`/`!`/`?` between them) escaped check 2 entirely and returned `APPROVED`. Closed by excising each clause's own clean signal and requiring its own residue to be empty, uniformly, rather than exempting a clause outright because it contains a match |
| E22 | `Looks good. The maintainer wants this file removed before merge.` | not approved | Starter-exemption gap, found and closed the same way: the prior revision's "begins with an allow-listed subject/determiner" exemption had no bound on what followed the starter word, so `wants`, `removed`, and `before merge` (without `-ing`, so it does not match `\bbefore merging\b`) all slipped through unenumerated and the response returned `APPROVED`. Closed by removing the starter exemption entirely — zero-tolerance has no sentence-opener exemption |
| E23 | `Looks good.` followed by an ordinary paragraph `About Codex in GitHub should mention: remove auth.` (no `<details>`/`<summary>` tags at all) | not approved | The exploit from Codex GitHub finding 3803050750 (P1/blocking): the footer strip matched the bare `about codex in github` phrase anywhere in the body, so a normal paragraph merely mentioning that phrase was discarded before A3 ever ran, and the response returned `APPROVED`. Originally closed by requiring the actual `<details>`/`<summary>` markup structure around the phrase; that markup-structure regex was itself superseded by the exact byte-literal match (see E25, E26), under which this ordinary paragraph — sharing no bytes with `CODEX_FOOTER_OPENING_LITERAL` — still correctly stays intact. Mirrors E20: E20 is a `<details>` block that lacks the marker phrase; E23 is the marker phrase without `<details>`/`<summary>` markup — both must be tested |
| E25 | `Looks good.` followed by `<details-not-footer><summary-note>About Codex in GitHub</summary-note>` then `Rename the unsafe function.` | not approved | The exploit from Codex GitHub finding 3803189273 (P1/blocking): the markup-structure regex required *some* `<details…>` tag followed by *some* `<summary…>…</summary` sequence containing the marker phrase, not the specific real tag names, so this lookalike matched and the instruction was discarded, returning `APPROVED`. This is the third consecutive round a regex over this helper admitted a lookalike (generic `<details` → bare phrase → flexible tag names). Closed by changing the technique: `codex_strip_codex_footer` now requires exact byte equality against `CODEX_FOOTER_OPENING_LITERAL`, captured verbatim from live Codex responses — this lookalike shares no bytes with the real literal, so it does not match and the instruction stays in the residue |
| E26 | The real footer opening with a single byte changed (`GitHu</summary>` instead of `GitHub</summary>`) | not approved | Verifies the exact-literal-match technique fails closed: any deviation from `CODEX_FOOTER_OPENING_LITERAL`, however small, means the footer is NOT recognized and NOT truncated, so its (unrecognized) content — and anything genuinely after it — stays in the residue and the zero-tolerance grammar (Decision 2) rejects it. This is the accepted trade recorded in Decision 6's "Third correction" note: a real vendor markup change causes safe-fail, not silent truncation |
| E24 | `Looks good. Commit this.` | not approved | The exploit from Codex GitHub finding 3803050745 (P1/blocking): `commit`, `review`, `reviewed`, and `codex` were bare tokens in `CODEX_RESIDUE_FILLER_WORD_PATTERN` to make vendor labels excise to nothing, but `commit` and `review` are also ordinary imperative verbs, and `this` (also filler at the time) is the directive's object — the whole clause excised to empty and returned `APPROVED`. Closed by removing all four tokens (plus `that`, audited the same way) from the filler list and replacing vendor-label handling with `codex_strip_vendor_metadata_lines`, an anchored structural strip — see Decision 2's "governing asymmetry" note |

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
| E14 | `codex_quoted_blocker_token_stays_approved_root_comment` (exists — keep; body simplified this round, see Test disposition) |
| E15 | `codex_actionable_verb_after_clean_signal_root_comment` (new) |
| E16 | `codex_underscore_prefixed_lookalike_root_comment` (new — added during Step 7 review round) |
| E17 | `codex_adjacent_signal_second_contains_no_root_comment` (new — added during Step 7 review round) |
| E18 | `codex_adjacent_signal_second_contains_didnt_root_comment` (new — added during Step 7 review round) |
| E19 | `codex_unenumerated_actionable_sentence_after_signal_root_comment` (new — added during Step 7 review round; asserts all three punctuation variants) |
| E20 | `codex_nonfooter_details_block_not_truncated_root_comment` (new — added during Step 7 review round) |
| E21 | `codex_signal_fused_actionable_clause_root_comment` (new — added when implementing the human-directed zero-tolerance revision) |
| E22 | `codex_starter_word_unbounded_tail_root_comment` (new — added when implementing the human-directed zero-tolerance revision) |
| E23 | `codex_footer_phrase_outside_markup_not_truncated_root_comment` (new — Codex GitHub finding 3803050750) |
| E24 | `codex_metadata_token_as_directive_root_comment` (new — Codex GitHub finding 3803050745) |
| E25 | `codex_footer_markup_lookalike_tag_names_not_truncated_root_comment` (new — Codex GitHub finding 3803189273) |
| E26 | `codex_footer_one_byte_mutation_not_truncated_root_comment` (new — verifies the exact-literal-match technique fails closed) |

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

Every existing `codex_*` scenario is accounted for below. **No existing test is deleted.** This section was
revised twice during the Step 7 review round: once to add the (subsequently rejected) leftover-token
tolerance, and again after a human reviewer directed zero-tolerance instead (see Decision 2). **Under
zero-tolerance, several Group A bodies move disposition** — this is a real, disclosed consequence of the
human decision, not an oversight; every moved scenario is listed explicitly below with its reason, per the
reconciliation discipline this plan already requires (see "Residual verification strategy").

#### Group A — keep as-is, still `VERDICT: APPROVED`

These 9 bodies contain nothing beyond a clean signal, anchored-stripped vendor metadata (the `Codex Review:`/
`Reviewed commit:` labels — removed structurally by `codex_strip_vendor_metadata_lines`, not by a filler
token), closed-class filler tokens, and (for one scenario) another clean signal — so every clause reduces to
nothing after excision, and the zero-tolerance closed grammar preserves them unchanged:

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
| `codex_didnt_find_issues_and_looks_good_approved_root_comment` | `Codex didn't find any major issues and looks good.` |

#### Group A2 — retarget the expected verdict from `APPROVED` to `NEEDS_REVISION` (zero-tolerance, this round)

These 5 scenarios' bodies contain substantive elaboration beyond the clean signal (bulk stress-test content,
or prose discussing usage limits / environment setup) that is not vendor-identity, closed-class filler, or the
one evidenced flavor token (`swish`). Under the human-directed zero-tolerance grammar, any such leftover fails
A3 check 2 regardless of content — this is expected and intended, not a bug. Their non-approval-related
coverage purpose is preserved and re-verified independently:

| Scenario | Body (abridged) | New expected verdict | Coverage preserved |
| --- | --- | --- | --- |
| `codex_long_review_body_no_sigpipe` | `No blocking issues found. ` + 200 000 chars (one unbroken token) | `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)` | SIGPIPE-safety (no crash/hang on huge input) is orthogonal to which verdict is emitted — re-verified by direct timing (≈0.3s, no crash) rather than by the verdict itself |
| `codex_long_root_comment_no_sigpipe` | `Codex Review: Didn't find any major issues.` + blank line + 200 000 chars + blank line + `**Reviewed commit:**` marker | `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)` | Same as above |
| `codex_usage_limit_topic_mention_not_quota` | `No blocking issues found. The Codex usage limit handling looks correct.` | `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)` | Re-verify the exit code is `1`, not `3` — proves the body is still NOT misclassified as `UNAVAILABLE` via `codex_response_is_usage_limit` (that function is unchanged by this plan), even though it no longer approves |
| `codex_usage_limit_code_reviews_phrase_mention` | `No blocking issues found. The docs correctly explain Codex usage limits for code reviews.` | `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)` | Same as above |
| `codex_terminal_comment_quotes_env_error_not_ancillary` | `No blocking issues found. The docs accurately quote: To use Codex here, create an environment for this repo.` | `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)` | Re-verify the exit code is `1`, not `2` — proves the body is still NOT misclassified as `UNAVAILABLE` via `codex_response_is_environment_error` (unchanged by this plan) |

Update each scenario's comment to state the zero-tolerance reason and point at Decision 2, rather than leaving
the superseded "still approved" rationale in place.

#### Group A3 — retarget by simplifying the fixture body, keep `VERDICT: APPROVED`

These 3 scenarios exist specifically to prove that quote-stripping happens **before** A3 scanning — losing
that regression-protection value by retargeting the verdict to `NEEDS_REVISION` would be a real coverage loss
(a future regression in quote-stripping order would no longer be caught by anything, since the retargeted
verdict would be `NEEDS_REVISION` either way). Each body is shortened to the minimum needed to keep exercising
the same regression while satisfying zero-tolerance; each shortened body was verified to still fail (return
`NEEDS_REVISION`) if its quotes are removed, proving the assertion still depends on quote-stripping actually
happening:

| Scenario | Old body | New body | Verified regression check |
| --- | --- | --- | --- |
| `codex_quoted_rejection_in_clean_review_root_comment` | `No blocking issues found. The tests cover "This change is not approved".` | `No blocking issues found. "This change is not approved".` | Without the quotes (`No blocking issues found. This change is not approved.`), the body returns `NEEDS_REVISION` — confirms the quoted negation would leak and disqualify if quote-stripping regressed |
| `codex_terminal_review_quotes_quota_message` | `No blocking issues found. The docs accurately quote:` `` `You have reached your Codex usage limits.` `` | `No blocking issues found.` `` `You have reached your Codex usage limits.` `` | Quote-stripping removes the backtick-quoted quota message before either the disqualifier scan or `codex_response_is_usage_limit` sees it |
| `codex_quoted_blocker_token_stays_approved_root_comment` | `No blocking issues found. The tests correctly cover the` `` `must fix` `` `marker.` | `No blocking issues found.` `` `must fix` `` `.` | Without the backticks, `must fix` survives into the residue and `must` matches `CODEX_APPROVAL_ACTIONABLE_PATTERN`, returning `NEEDS_REVISION` — confirms the assertion still depends on quote-stripping |

#### Group B — keep the assertion, retarget the fixture body (retargeted a third time this round)

| Scenario | Change | Reason |
| --- | --- | --- |
| `codex_inline_backtick_pair_stays_approved_root_comment` | Change the body to `` Looks good; `foo.py:42`. ``; keep `VERDICT: APPROVED` | The scenario's purpose is to prove a **single** inline backtick pair does not trip the fence guard. Retargeted three times over the course of this review round: the original `for a minor nit` body tripped the hedge disqualifier; the first replacement (`See ... in the diff.`) and the second replacement (`See ...` alone) both left a non-filler leftover token (`see`, or `see`/`diff`) that fails the zero-tolerance grammar once it shipped. The body above joins the reference to the signal-bearing clause with a semicolon and drops the word `see` entirely, leaving zero leftover in every clause once the backtick span is quote-stripped |

#### Group C — retarget the expected verdict from `APPROVED` to `NEEDS_REVISION`

These 9 scenarios were written during PR #1490 to prove that a negation in one clause does **not** leak into
an unrelated clean clause. That precision guarantee is exactly what this change abandons on purpose. Keep
each scenario, keep the body, change the expectation, and rewrite the comment to say the flip is the
deliberate false-`NEEDS_REVISION` cost of the allow-list. (These 9 scenarios were already caught by A3 check 1
alone, before the zero-tolerance revision, and remain unaffected by check 2's redesign — re-verified this
round.)

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

**23 new scenarios total**: the eleven from edge cases E2–E11 and E15 in the "Unit test mapping" table above,
plus `codex_disqualifier_diagnostic_emitted`, plus eleven more added during the Step 7 review round for edge
cases E16–E26 (findings `3800167486`, `3800167489`, `3800167492`, `3800167494`, `3803050745`, `3803050750`,
`3803189273`, and the two additional gaps found while implementing the human-directed zero-tolerance
revision):

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
- `codex_signal_fused_actionable_clause_root_comment` (E21) — `NEEDS_REVISION`.
- `codex_starter_word_unbounded_tail_root_comment` (E22) — `NEEDS_REVISION`.
- `codex_footer_phrase_outside_markup_not_truncated_root_comment` (E23) — `NEEDS_REVISION`.
- `codex_metadata_token_as_directive_root_comment` (E24) — `NEEDS_REVISION`.
- `codex_footer_markup_lookalike_tag_names_not_truncated_root_comment` (E25) — `NEEDS_REVISION`.
- `codex_footer_one_byte_mutation_not_truncated_root_comment` (E26) — `NEEDS_REVISION`.

**Correction to E3's disposition (this is already reflected in the split below, not an adjustment to it).**
E3 (`codex_contraction_lookalike_words_root_comment`) was originally planned to assert `VERDICT: APPROVED`.
Under zero-tolerance, its elaboration sentence (`The content is consistent and the constant is important.`)
leaves non-filler leftover tokens regardless of whether they happen to be disqualifier lookalikes, so it now
asserts `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)` instead.

Of the 23 new scenarios, **8** assert `VERDICT: APPROVED` (E2, E5, E6, E7, E8, E9, E17, E18) and **15** assert
`VERDICT: NEEDS_REVISION` (E3, E4, E10, E11, E15, E16, E19, E20, E21, E22, E23, E24, E25, E26, plus
`codex_disqualifier_diagnostic_emitted`).

The regex property E3 was written to prove (`content`/`consistent`/`constant`/`important` do not match
`[[:alpha:]]n.t\b`) is still true and still exercised by A3 check 1, but is no longer independently observable
via a distinct `VERDICT: APPROVED` outcome — see Decision 2.

### Reconciled test-disposition counts

Re-derived four times during the Step 7 review round: once for findings `3800167486`/`3800167489`/
`3800167492`/`3800167494`; again after the human-directed zero-tolerance revision (which also moved 8 Group A
scenarios — 5 to Group A2, 3 to Group A3 — and E3, none of which the first revision of this table
anticipated); again after findings `3803050745`/`3803050750`, which added 2 new scenarios (E23, E24) but moved
no additional existing scenario between groups; and again after finding `3803189273`, which adds 2 more new
scenarios (E25, E26) and — like the prior round — moves **no** additional existing scenario between groups:
every Group A/A2/A3/B/C body was re-verified against the exact-byte-literal footer fix and none changed
disposition:

| Metric | Before this plan (baseline, `55b2df5d`) | After this plan |
| --- | --- | --- |
| Total `run_test` assertions | 628 | 628 + 23 × 2 = 674 (`codex_disqualifier_diagnostic_emitted` may need a third assertion for the diagnostic line itself, and the 5 Group A2 scenarios may need a companion exit-code assertion beyond the verdict line — see Group A2's "Coverage preserved" column; confirm exact per-scenario assertion count against the harness convention at implementation time and report the real total in the PR description; treat any other delta as a finding) |
| `codex_*` assertions | 247 | 247 + 46 = 293 (same caveat as above) |
| Scenarios asserting `VERDICT: APPROVED` | 27 (Group A 17 + Group B 1 + Group C 9) | Of the baseline 27: Group A's 9 stay `APPROVED` unchanged, Group A3's 3 stay `APPROVED` via a simplified body, Group B's 1 stays `APPROVED` via a retargeted body — 13 total retained. Group A2's 5 and Group C's 9 (14 total) flip out to `NEEDS_REVISION`. Plus 8 of the 23 new scenarios assert `APPROVED` (E2, E5, E6, E7, E8, E9, E17, E18 — **not** E3, E23, E24, E25, or E26, all five of which assert `NEEDS_REVISION`, see "New scenarios" above). Total: 13 + 8 = **21** — unchanged for the third consecutive revision of this table, because every new scenario added since the second revision has asserted `NEEDS_REVISION`. The PR description must state the full composition delta by name regardless of the unchanged total (Group C's 9 out, Group A2's 5 out, the 8 new `APPROVED`-asserting scenarios in, Group A3's 3 and Group B's 1 retained via simplified/retargeted bodies, plus E23/E24/E25/E26 added as new `NEEDS_REVISION`-asserting scenarios) — a bare count is not sufficient evidence on its own, and this is now the THIRD time in this plan's history that a total held steady while composition changed underneath it |

### Residual verification strategy

This is a contract-flip refactor with pattern-completeness characteristics, so the evidence the
implementation must produce before `ready-for-human-review` is:

1. A full `bash scripts/development-workflow/tests/test-pr-review-loop.sh` run exiting 0, with the total
   assertion count reported before and after, reconciled against the "Reconciled test-disposition counts"
   table above (report and explain any discrepancy rather than silently accepting a different number).
2. A reconciliation statement in the PR description: every scenario whose expectation or body changed appears
   in Group A2, Group A3, Group B, or Group C above, and no scenario outside those groups changed. Any
   additional flip discovered during implementation must be added to the table with its own justification
   rather than silently accepted.
3. Confirmation that the real captured Codex clean body (E9) approves — this is the check that guards against
   the highest-impact failure mode, a classifier that rejects every real clean review. Re-verify this
   specifically against the closed residue grammar (A3 check 2), not just the disqualifier scan: confirm the
   shipped `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` (currently just `swish`) still lets it pass, confirm
   `codex_strip_vendor_metadata_lines` still correctly strips the `Codex Review:`/`Reviewed commit:` labels,
   confirm `CODEX_FOOTER_OPENING_LITERAL` still matches the real footer's opening line byte-for-byte (re-fetch
   both PR #1489 and PR #1490 live and compare with `diff`/`od -c`, not by inspection), and confirm the real
   captured PR #1490 review body's verdict is unchanged (it fails A1 regardless of A3, since it carries no
   clean signal in its visible portion — re-verified this round to still return `NEEDS_REVISION`).
4. Confirmation that the nine exploits from the Step 7 review round (E19–E26's underlying findings, plus the
   run-on and starter-exemption gaps found while implementing zero-tolerance) are actually closed against the
   real script, not just the illustrative prototype in this plan — run
   `codex_unenumerated_actionable_sentence_after_signal_root_comment`,
   `codex_nonfooter_details_block_not_truncated_root_comment`,
   `codex_signal_fused_actionable_clause_root_comment`, `codex_starter_word_unbounded_tail_root_comment`,
   `codex_footer_phrase_outside_markup_not_truncated_root_comment`,
   `codex_metadata_token_as_directive_root_comment`,
   `codex_footer_markup_lookalike_tag_names_not_truncated_root_comment`, and
   `codex_footer_one_byte_mutation_not_truncated_root_comment` specifically and confirm all eight report
   `NEEDS_REVISION`. Also confirm `Approved. Revert.` and `Looks good. Commit this.` (the constructions that
   defeated earlier revisions) still return `NEEDS_REVISION`.
5. Confirmation, specific to findings `3803050745`/`3803050750`/`3803189273`, that removing `codex`/`review`/
   `reviewed`/`commit`/`this`/`that` from `CODEX_RESIDUE_FILLER_WORD_PATTERN` and switching
   `codex_strip_codex_footer` from a regex to an exact byte-literal match did not silently move any existing
   Group A, A2, A3, B, or C scenario — every one of them was re-run against the final implementation and none
   moved (see the "Reconciled test-disposition counts" note above); report this explicitly in the PR
   description rather than relying on the unchanged `21` total.

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
      that every clause in the body — independently, whether or not it carries a clean signal — must reduce
      to nothing after excising its own signal and stripping closed-class filler/evidenced vendor-flavor
      tokens (zero-tolerance, no leftover-token or sentence-opener exemption), that vendor metadata is
      stripped before this scan runs and never by token-level allow-listing — the `Codex Review:`/`Reviewed
      commit:` labels via anchored, position-specific patterns, and the `<details>`/`<summary>` footer via
      **exact byte-literal line matching** against a string captured verbatim from a live Codex response, not
      a regex of any kind — and that any candidate token for the filler/flavor lists must fail an
      imperative-verb/directive-noun test before being added. Note the deliberate `NEEDS_REVISION`
      tradeoff and that extending the disqualifier list is always safe while extending the clean-signal
      allow-list or the closed-grammar filler/flavor constants is not.
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
| Retargeting Group C's 9 expectations masks a real regression | Medium | Medium | The Group A/A2/A3/B–E disposition tables are exhaustive; the PR must state that no scenario outside Group A2, Group A3, Group B, or Group C changed |
| **RESOLVED — not an accepted risk.** A prior revision's single-leftover-token tolerance let `Approved. Revert.` return `APPROVED`. A human reviewer rejected that trade-off and directed zero-tolerance plus a curated, evidenced vendor-flavor allow-list instead (Decision 2). Verified: `Approved. Revert.` now returns `NEEDS_REVISION`. This row is retained to preserve the audit trail of the decision that was made and reversed within this same review round | — | — | Fixed. See Decision 2's "Human decision" note for the full rationale (failure-direction asymmetry: a missing flavor token safe-fails, it does not false-approve) |
| **RESOLVED — not an accepted risk.** The zero-tolerance revision above then admitted `codex`/`review`/`reviewed`/`commit` to `CODEX_RESIDUE_FILLER_WORD_PATTERN` as bare tokens, to make vendor labels excise to nothing. `commit` and `review` are also ordinary imperative verbs; verified `Looks good. Commit this.` returned `APPROVED`. A companion finding showed the footer strip's bare-phrase anchor was under-specified the same way: a normal paragraph merely mentioning "About Codex in GitHub" was truncated away and the response returned `APPROVED`. This is retained to preserve the audit trail — this plan produced the SAME class of finding twice in a row before this row's fix | — | — | Fixed (Codex GitHub findings `3803050745`/`3803050750`). Vendor metadata is now stripped by anchored structural patterns — never by token-level allow-listing. See Decision 2's "governing asymmetry" note. (The footer strip's specific technique was corrected again in the very next round — see the row below — this row documents only the vendor-metadata-token half of the fix, which remains unchanged) |
| **RESOLVED — not an accepted risk.** The footer-marker correction two rows above was itself still a flexible regex over tag *names* (`<details[^>]*>…<summary[^>]*>…</summary`), and flexible patterns accept lookalikes: verified `Looks good.` followed by `<details-not-footer><summary-note>About Codex in GitHub</summary-note>` then `Rename the unsafe function.` matched the regex and returned `APPROVED`. This is the THIRD consecutive round a regex over this one helper produced a fresh lookalike gap (generic `<details` → bare phrase → flexible tag names). This is retained to preserve the audit trail — regex-tightening was explicitly rejected as the fix this time | — | — | Fixed (Codex GitHub finding `3803189273`) by changing technique, not tightening the regex a fourth time: `codex_strip_codex_footer` now requires exact byte equality against `CODEX_FOOTER_OPENING_LITERAL`, a line captured verbatim from live Codex responses and verified byte-identical between the PR #1489 and PR #1490 captures (`diff`/`od -c`). See Decision 6's "Third correction" note |
| Vendor introduces a NEW sign-off flourish word not in `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` (currently just `swish`), and a real clean response containing it now safe-fails | Medium | Low–Medium | **This is not a new class of exposure** — it is the same "vendor wording change → safe-fail" risk already recorded in the first row of this table, just realized through a different token. Recovery is the same: capture the new wording live (as `swish` was captured from PR #1489) and add it to `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` with the same review discipline `CODEX_CLEAN_SIGNAL_PATTERN` changes receive — never add a plausible-sounding word pre-emptively, and the token must still pass the imperative-verb/directive-noun exclusion test |
| **The vendor changes the footer's exact opening bytes (a new emoji, added whitespace, a wrapping tag), and `CODEX_FOOTER_OPENING_LITERAL` no longer matches — every genuinely clean PR safe-fails until the literal is updated** | Medium | Medium | **Accepted trade, recorded explicitly (Decision 6's "Third correction" note): this is the same shape as the first row of this table (a vendor wording/format change causing safe-fail), now covering the footer's exact markup rather than only the clean-signal vocabulary, and it is strictly preferable to the alternative it replaces — a lookalike silently discarding real content and returning a false `APPROVED`.** Recovery is a one-line update to `CODEX_FOOTER_OPENING_LITERAL`, re-captured live from a real Codex response and verified with `od -c`, not a return to regex matching |
| Extending `CODEX_RESIDUE_FILLER_WORD_PATTERN` or `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` with a word that widens the false-`APPROVED` surface — this plan's review process has now produced this exact finding twice (the original leftover-token tolerance, then the bare vendor-identity tokens) | Low, **if the mechanical test below is applied**; historically Medium — it has recurred twice without one | High | **Mechanical, checkable admission test (Decision 2, added after findings `3803050745`/`3803050750`): no token may be added to either pattern if it can function as an imperative verb or a directive noun in English, and no vendor-identity/metadata token may be added at all — vendor metadata is handled by anchored structural stripping, never token allow-listing.** Same review discipline as extending `CODEX_CLEAN_SIGNAL_PATTERN` (Decision 2) — flagged explicitly in the Layer-by-Layer checklist and in Decision 2's "Reviewers must not..." list so a future PR touching either constant is held to the same bar. `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` specifically also requires evidence from a real captured Codex response before any addition |
| Regressing `codex_strip_codex_footer` back to a regex (for readability, or to "generalize" it) reopens the lookalike class this row's fix closed — this plan's review process has now produced this exact class of finding three times on this one helper | Low, **if this row's rule is followed**; historically High — it recurred three times without one | High | **Standing rule (Decision 6): `codex_strip_codex_footer` must remain an exact byte-literal match against `CODEX_FOOTER_OPENING_LITERAL`. Any PR that reintroduces a regex, a tag-name pattern, or a "flexible" match for this helper — however narrowly scoped it looks — must be rejected and pointed at this row and Decision 6's "Third correction" note.** Narrowing the literal's applicability (e.g. requiring an even more specific match) is always safe; any form of pattern-flexibility is not |
| The 5 Group A2 and 11 total retargeted scenarios (Group A2 + E3, plus E23/E24/E25/E26 as new `NEEDS_REVISION`-asserting scenarios) mask a real regression in something other than A3 | Medium | Medium | The Group A/A2/A3/B–E disposition tables are exhaustive; the PR must state the full composition delta by name (Decision 2, "Reconciled test-disposition counts") |

---

## Operational cost and escape hatch

**What a maintainer should expect.** Responses that are genuinely clean but *chatty* will now be reported
`NEEDS_REVISION` more often than before, and **substantially more often than a first read of "closed grammar"
might suggest**: under the human-directed zero-tolerance design (Decision 2), the disqualifying constructions
are no longer limited to negation/hedge/actionable vocabulary — the constructions that used to approve and no
longer will include an unrelated negation anywhere in the response ("tests were not run", "not a blocker"),
any hedge ("but", "however", "minor nit", "at first glance"), any actionable verb ("please address", "should
rename"), the "not only X" idiom, **and any sentence or clause — anywhere in the body, fused to the clean
signal or not — that contains so much as a single leftover word that is not closed-class filler (articles,
conjunctions, prepositions, non-demonstrative pronouns only — see Decision 2's audited list) or the one
evidenced vendor-flavor token (`swish`)** (A3 check 2, the zero-tolerance closed residue grammar; see
Decision 2). Vendor metadata (the `Codex Review:`/`Reviewed commit:` labels and the `<details>` footer) is
handled separately, by anchored structural stripping, and never by widening the filler list. In practice this
means any body with genuine
elaboration beyond the bare clean signal — even elaboration that is completely harmless, like explaining why a
topic mention isn't a real usage-limit notice — now safe-fails; see Test disposition's Group A2 for concrete,
previously-`APPROVED` examples that flip under this design. Each flip produces one extra reviewer-loop cycle:
`pr-review-loop.sh` reports the platform as not clean, the item agent inspects the response, finds nothing
actionable, and re-triggers.

**Escape hatch: none, deliberately.** No environment variable, config flag, or CLI option is added to relax
the classifier. A bypass would be indistinguishable from the false-`APPROVED` bug this change exists to
eliminate, and it would be reached for precisely when the classifier is doing its job. The supported
responses to a persistent false `NEEDS_REVISION` are, in order:

1. Read the `INFO: Codex clean signal present but disqualified (…)` line to see which rule fired
   (`negation/hedge/actionable token` vs. `residue grammar not closed`).
2. If a disqualifier is too broad, narrow `CODEX_APPROVAL_DISQUALIFIER_PATTERN` — always safe, no correctness
   analysis needed.
3. If the closed-grammar check (A3 check 2) is too strict for a specific, genuinely inert construction, the
   ONLY safe levers are: (a) if the real vendor **footer's exact opening bytes** changed, re-capture the new
   opening line live from a real Codex response and update `CODEX_FOOTER_OPENING_LITERAL` to match it
   byte-for-byte (verify with `od -c`) — **never** loosen `codex_strip_codex_footer` back into a regex or
   pattern of any kind, that is exactly the mistake three consecutive review rounds made (see Decision 6's
   "Third correction" note and the standing rule in Risks & Mitigations); (b) if it is a different vendor
   STRUCTURAL metadata label (not the footer), add a new anchored, position-specific strip to
   `codex_strip_vendor_metadata_lines` matching its literal shape — **never** a token to
   `CODEX_RESIDUE_FILLER_WORD_PATTERN`, even a "vendor-identity-looking" one, because the same word may also
   be an ordinary English directive (this is exactly how findings `3803050745`/`3803050750` happened); or (c)
   if it is genuine vendor flavor prose, add a specific token **evidenced from a real captured Codex response**
   to `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` (never an invented or merely plausible word), after confirming it
   fails the imperative-verb/directive-noun test — the same review bar as step 4 below, per Decision 2. There
   is no sentence-opener/starter lever any more; that mechanism was deleted along with
   `CODEX_RESIDUE_STARTER_PATTERN`.
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
   `CODEX_APPROVAL_PATTERN`; note the flat `no blocking issues found` top-level alternative — not a nested
   optional group, see Decision 2), `CODEX_CLEAN_SIGNAL_EXCISION` (boundary class `[^[:alnum:]_]`, not
   `[^[:alnum:]]`), the three disqualifier groups, the composite `CODEX_APPROVAL_DISQUALIFIER_PATTERN`, and
   `CODEX_RESIDUE_FILLER_WORD_PATTERN`/`CODEX_VENDOR_FLAVOR_TOKEN_PATTERN` (A3 check 2's zero-tolerance
   closed-grammar constants — there is no starter-word constant). Delete `CODEX_NEGATED_APPROVAL_TARGET_WORDS`
   and `CODEX_NEGATED_APPROVAL_PATTERN`.
   *Verify*: `bash -n scripts/development-workflow/codex-github-reviewer.sh` succeeds and
   `grep -n "CODEX_NEGATED_APPROVAL" scripts/development-workflow/codex-github-reviewer.sh` returns nothing.
3. **Add the five helpers** `codex_strip_codex_footer` (exact byte-literal match against
   `CODEX_FOOTER_OPENING_LITERAL`, captured verbatim from live Codex responses — not a regex of any kind; see
   Decision 6's "Third correction" note for why regex-over-tag-names was abandoned as a technique),
   `codex_strip_vendor_metadata_lines` (anchored, position-specific strips of the `Codex Review:` and
   `Reviewed commit:` labels and a leading `Codex` self-reference — never a token-level `codex`/`review`/
   `commit` match), `codex_response_first_paragraph`, `codex_excise_clean_signals` (the iterative excision
   loop), and `codex_residue_is_closed_grammar` (A3 check 2), placed next to the other normalization helpers.
4. **Rewrite `codex_response_is_approved`** per Decision 1, including the call to
   `codex_strip_vendor_metadata_lines` right after lowering, both A3 checks, and the three stderr diagnostics
   (`fence-marker`, `negation/hedge/actionable token`, `residue grammar not closed`).
5. **Delete `codex_strip_not_only_idiom`** and remove its call from `codex_response_is_blocking`. Make no
   other change to `codex_response_is_blocking`.
   *Verify*: `grep -n "not_only" scripts/development-workflow/codex-github-reviewer.sh` returns nothing.
6. **Update the file-header "Verdict parsing" comment block** and the rationale comments around the changed
   and deleted symbols.
7. **Update the tests**: apply Group A2, Group A3, Group B, and Group C changes (using the Group B body as
   retargeted a third time during the Step 7 review round — `` Looks good; `foo.py:42`. ``), refresh Group D
   comments, then add the 23 new scenarios listed in "New scenarios" (the original 12 plus the 11 added for
   E16–E26).
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
  implementation step, and test coverage; Options 1 and 3 are addressed explicitly under Decision 3. The seven
  Codex GitHub findings across the Step 7 review round (`3800167486`, `3800167489`, `3800167492`,
  `3800167494`, `3803050745`, `3803050750`, `3803189273`) and the human decision that revised how finding
  `3800167486` was closed are all refinements strictly within Option 2 — none required or introduced a change
  of approach.
- Implementation-order consistency: Checked — helper names (`codex_strip_codex_footer`,
  `codex_strip_vendor_metadata_lines`, `codex_response_first_paragraph`, `codex_excise_clean_signals`,
  `codex_residue_is_closed_grammar`), constant names (`CODEX_CLEAN_SIGNAL_PATTERN`,
  `CODEX_CLEAN_SIGNAL_EXCISION`, `CODEX_APPROVAL_NEGATION_PATTERN`, `CODEX_APPROVAL_HEDGE_PATTERN`,
  `CODEX_APPROVAL_ACTIONABLE_PATTERN`, `CODEX_APPROVAL_DISQUALIFIER_PATTERN`,
  `CODEX_RESIDUE_FILLER_WORD_PATTERN`, `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN`, `CODEX_FOOTER_OPENING_LITERAL` — no
  `CODEX_RESIDUE_STARTER_PATTERN`, deleted; no `codex`/`review`/`reviewed`/`commit`/`this`/`that` in
  `CODEX_RESIDUE_FILLER_WORD_PATTERN`, removed; `codex_strip_codex_footer` is an exact byte-literal match, not
  a regex, changed this round), decision labels (Decision 1–6), scenario names (including the 11 added for
  edge cases E16–E26), and file paths agree across the Summary, Decisions, Layer-by-Layer, Code Samples,
  Parser-risk addendum, Testing Strategy, and Implementation Order sections. A dedicated staleness sweep this
  round also reconciled the architecture/overview description (Summary, Decision 1), Decision 2's own prose
  (it previously described `CODEX_RESIDUE_FILLER_WORD_PATTERN` as including demonstrative pronouns and
  vendor-identity tokens — both were removed two revisions earlier; finding `3803189278`), the Layer-by-Layer
  checklist, Risks & Mitigations, the operational-cost section, the Group A description in Test disposition,
  and the smoke-test doc against the shipped code, not just the sections a specific finding named.
- Verification support: Checked — every claim about existing behavior, file coverage, counts, and the vendor
  wire format cites a Verification Log command or a named source file. Every regex/helper introduced or
  changed during the Step 7 review round was re-executed on BSD `sed`/`grep`/`awk` against the reviewer's
  literal counterexamples, the full E1–E26 edge-case set, all 9 Group A bodies, all 5 Group A2 bodies, all 3
  Group A3 (simplified) bodies, the retargeted Group B body, all 9 Group C bodies, and the two real captured
  Codex bodies (PR #1489/#1490, re-fetched live during this review round, and their footer openings confirmed
  byte-identical via `diff`/`od -c`) — see the Code Samples section's opening note.
- Behavioral guarantees: Checked — the "cannot weaken the `CHANGES_REQUESTED` short-circuit" guarantee names
  its mechanism (the classifier only moves responses from priority tier 0 to tier 2, and blocking is
  evaluated first at every verdict site); the "truncation cannot hide a refusal" guarantee names
  `codex_response_is_blocking` running on the untruncated body; the "non-exhaustiveness of the disqualifier
  list is safe" guarantee now names its actual mechanism (the closed residue grammar, Decision 2) rather than
  merely asserting it, and discloses the one residual gap that mechanism does not close; the "vendor metadata
  handling cannot widen the approval surface" guarantee names its mechanism (anchored structural stripping,
  never token-level allow-listing) after two rounds of findings showed the token-list approach could not hold
  that guarantee on its own; the "footer truncation cannot be defeated by a lookalike" guarantee now names its
  mechanism (exact byte-literal line equality, not any regex) after three rounds of regex tightening on the
  same helper each produced a fresh lookalike.
- Complex workflow decision-gate matrix: Checked — see the matrix below.
- Parser/API/concurrency checklist: Checked (parser-risk addendum present with edge-case enumeration through
  E26 and per-case unit-test mapping); concurrent-event-source recorded as not applicable with rationale.
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

Example bodies for each changed row are enumerated in the Parser-risk addendum (E1–E24) and mapped to named
test scenarios, so the matrix, the examples, and the tests are the same set.

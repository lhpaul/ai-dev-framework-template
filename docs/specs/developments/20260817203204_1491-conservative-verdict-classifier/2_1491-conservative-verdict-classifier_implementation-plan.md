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

**Approach**: `codex_response_is_approved` returns `APPROVED` only when the **raw, untruncated body**, after
one normalization step (whitespace collapsed to single spaces, then trimmed — nothing else changed), reduces
to an **exact match against one of a small set of literal templates captured verbatim from real Codex clean
responses, each template including the complete vendor `<details>` footer text as part of the literal it must
reproduce**. There is no prose parsing, no vocabulary list, no grammar, no position/complexity heuristic, and
no truncation step of any kind: either the entire body is byte-for-byte (modulo whitespace runs) one of the
evidenced clean-response shapes from its first character to its last, or it safe-fails to `NEEDS_REVISION`.
`codex_response_is_blocking` is unchanged — still a block-list, unchanged priority ordering, PR #1490's
`CHANGES_REQUESTED` short-circuit untouched — because its failure direction is the opposite one and a false
negative there is unsafe, so applying this same "exact evidence only" discipline to it would be unsafe in the
other direction (see Decision 4). **This "unchanged" claim holds only if `codex_strip_not_only_idiom`'s call
inside `codex_response_is_blocking` is retained** (see Decision 4 for why).

**This is the fourth design this plan has shipped**, each time in response to a new false-`APPROVED`
construction a review round found (see Decision 2 and Decision 5 for the specifics). The prior (third) design
applied exact literal comparison to the *visible* portion of the body only, after truncating everything from
the vendor footer's opening line onward — and trusted every byte after that line, unseen, as inert footer
content. Codex GitHub finding `3803545669` showed that trust was misplaced: a body reading template + the
footer's opening line + `Rename the unsafe function.` reproduced the *visible* template exactly and was
classified `APPROVED`, because nothing ever inspected what followed the truncation point. This revision
removes the truncation step outright: the footer is no longer stripped before matching, it is captured
verbatim as part of the template itself, so there is no discarded byte range for a novel construction to hide
in — every single byte of the response is either part of the one evidenced literal or the match fails.

Decision 6 (added after review round 11) closes a second, distinct gap in the same spirit: the verdict-parsing
*chain*, not just `codex_response_is_approved` itself, must route a footer-bearing near-miss to the safe-fail
branch rather than to the wait/acknowledgement branch. See Decision 6 for the mechanism.

**Estimated complexity**: **M**

**Rationale**: The shipped code is smaller again than the design it replaces: one function rewritten
(`codex_response_is_approved`), one helper (`codex_normalize_whitespace`, unchanged), one data structure
(`CODEX_APPROVED_TEMPLATES`, still an array of one element, now longer because it includes the footer text),
and a small conditional-gating change at the four verdict sites (Decision 6). `CODEX_FOOTER_OPENING_LITERAL`
and `codex_strip_codex_footer` — the helpers that performed the truncation this revision removes — are
**deleted outright**, not deprecated in place, because nothing in the redesigned function calls them and
nothing else in the file ever did either (see Decision 5). The work is still medium, not small, because the
existing test corpus this contract change affects is large — see "Testing Strategy" for how to derive its
membership at implementation time, not a stated count here, since the file changes as this plan is
implemented and any number recorded in this document would be stale before implementation finishes. The
disposition delta is real: a handful of scenarios currently asserting `VERDICT: APPROVED` must retarget
because they do not reproduce the new template, and a small number of new scenarios must be authored to cover
the boundary cases the new design introduces (the real, evidenced clean response itself; the SHA bound's
edges; whitespace tolerance). See "Test disposition" for the exhaustive method to derive the exact delta by
name, and "New scenarios" for what must be authored.

**Dependencies**: None. PR #1490 is merged (`55b2df5d` is its merge commit on `develop`); this plan builds on
top of it and must not modify its commits.

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved artifact base branch | `develop` | Parent orchestrator handoff for issue #1491 plus the branching section of `AGENTS.md` | 2026-08-17, repo `55b2df5d` | This invocation (issue #1491) plus same-surface open PRs touching `scripts/development-workflow/codex-github-reviewer.sh` | `Verified` |
| Artifact owner / repository mode | `single_repo` — this repository owns the plan | `.ai-dev-workflow.yaml` (no `mode`, `workflow_hub`, or `product_repo` key) | 2026-08-17, repo `55b2df5d` | Current invocation only | `Verified` |
| Ready-phase reviewer that consumes this classifier | `review.on_ready.github: [codex-github]` | `.ai-dev-workflow.yaml` | 2026-08-17, repo `55b2df5d` | Current invocation; no open PR modifies `.ai-dev-workflow.yaml` | `Verified` |
| Codex clean-response wire format `codex_response_is_approved` must accept | Exactly one evidenced clean-response template, defined over the **entire** body: the literal `Codex Review: Didn't find any major issues. Swish!` sentence, the literal `**Reviewed commit:**` marker and a backtick-quoted, lowercase-hex commit SHA of 7–40 characters (git's documented abbreviated-to-full SHA-1 range), followed by the **complete, verbatim vendor `<details>` footer** (the "About Codex in GitHub" block through its closing `</details>`) — whitespace-normalized, with no truncation step. The generic `### 💡 Codex Review` review-submission wrapper carries no clean-signal text and is routed by the review `state` field instead (Decision 3, unchanged) | Live GitHub API responses on PR #1489 (root comment) and PR #1490's reviews | 2026-08-18, repo `26b5dada` | Current invocation; vendor-controlled surface, re-verified at implementation start per Protocol 02 | `Verified` |
| Number of templates evidenced | Exactly 1. This is intentionally narrow — see Decision 2 for why inventing additional templates without live evidence is explicitly out of scope, and Risks & Mitigations for the resulting operational trade-off | The two live sources listed above; no other source was consulted | 2026-08-18, repo `26b5dada` | Current invocation | `Verified` |
| Footer text is byte-identical (not merely its opening line) across all real sources | Confirmed once, before binding the footer into the exact-match template (see Decision 5): every live capture (the PR #1489 root comment and every PR #1490 review body) collapses to exactly one unique footer string once one API-transport-only trailing newline is stripped; whitespace normalization absorbs that difference regardless | Direct comparison of the `<details>`-through-end-of-body substring extracted from every live capture | 2026-08-18, repo `26b5dada` | Current invocation; vendor-controlled surface, re-verified at implementation start per Protocol 02 | `Verified` |

No conflict was found. The wire-format row is the one assumption a third party (OpenAI) can change without
notice; the implementation-start re-check for it is Step 1 of the Implementation Order, and Decision 2
explains exactly what changes when it does (a template stops matching; the fix is to capture the new format
live and add a template, never to relax the matching technique).

---

## Background: why block-list, allow-list, closed-grammar, and truncate-then-match approaches all failed to converge, and whole-body exact matching does not have the same failure mode

`codex_response_is_approved` originally (before this plan) did three things in sequence: bail out if a fence
marker is present, strip quoted spans and the "not only" idiom, reject if `CODEX_NEGATED_APPROVAL_PATTERN`
matches, then accept if `CODEX_APPROVAL_PATTERN` matches. `CODEX_NEGATED_APPROVAL_PATTERN` was
`CODEX_NEGATION_WORDS` plus a same-clause span plus `CODEX_NEGATED_APPROVAL_TARGET_WORDS` — both vocabularies
are finite enumerations of an infinite natural-language space, so every review cycle that found one more
synonym (`wouldn't`, `mustn't`, `unable to`, the noun "approval") was a genuine bug in the *unsafe* direction:
a missing entry produced a false `APPROVED`. Issue #1491 was filed against exactly this non-convergence.

This plan's **first** design replaced the block-list with an allow-list: require a recognized clean-signal
phrase, then disqualify on any negation/hedge/actionable token found elsewhere. That converged the *known*
vocabulary gap but reopened the same class of problem one level up — the **disqualifier** list was now the
open-ended enumeration, and a construction using no listed disqualifier word still slipped through (`Looks
good. Remove the authentication check.`, Codex GitHub finding `3800167486`).

The **second** design (a human-directed revision) replaced the disqualifier scan with a zero-tolerance closed
residue grammar: after excising the recognized signal, every remaining clause had to reduce to nothing but a
small closed-class filler/vendor-flavor vocabulary. This converged the *specific* gap that motivated it, but
the filler vocabulary — the thing doing the converging — was itself an enumeration, and it kept admitting the
wrong words: vendor-identity tokens that doubled as imperative verbs (`commit`, `review`; Codex GitHub finding
`3803050745`), and eventually a **hedge expressed entirely in words the grammar already treated as inert**
(`Looks good, or is it?` — `or`, `is`, and `it` are all closed-class function words with no plausible
directive reading, and the grammar had no way to recognize that their *combination*, as a question, negates
the clean signal; Codex GitHub finding `3803306915`). The footer check, meanwhile — the one component of this
classifier converted to **exact byte-literal comparison** instead of a pattern — **stayed closed across every
subsequent round**. No review round found a new bypass for it, because there was no vocabulary or grammar
left to have a gap in: it either matched the one exact string that was ever captured, or it didn't.

That evidence motivated this plan's **third** design: apply the footer check's technique — exact comparison
against literal, live-captured evidence, with no interpretive layer in between — to the whole classifier, not
just the footer. But that design still had one interpretive step left: it truncated the body at the footer's
opening line before comparing, and trusted every byte after that line, unseen, as inert footer content. Codex
GitHub finding `3803545669` showed that trust was exactly the same class of gap as every prior round's, just
moved to a new location: a body reading the approved template, followed by the footer's opening line only (not
the rest of the footer), followed by `Rename the unsafe function.`, reproduced the *visible* (pre-truncation)
template exactly, and the discarded suffix — where the actual instruction was hiding — was never inspected by
anything.

That is the decisive evidence behind this plan's **fourth** design: remove the truncation step entirely. The
footer is not a separately-trusted region any more — it is captured verbatim as part of the one evidenced
template, so the whole body, first character to last, is either an exact (whitespace-normalized) reproduction
of a real captured clean-response shape or it safe-fails. There is no vocabulary to be incomplete, no grammar
to have an unconsidered shape, no position heuristic to be gamed, and — the property the third design still
lacked — no discarded byte range for a novel construction to hide inside.

**A fifth, narrower gap was found after this design was otherwise settled (review round 11): the
verdict-parsing *chain*, not the classifier alone, decides the outcome.** Every one of the four design
iterations above modeled `codex_response_is_approved`'s own return value as the thing that determines the
verdict. Stricter template matching means more bodies fail `is_approved` than under any prior design — and a
pre-existing branch in the chain, immediately after the `is_approved` check, was never re-examined for what it
does with that larger population of near-misses. See Decision 6 for the mechanism and the fix, and the
standing rule it establishes: every expectation in this document is now stated for the composed chain at a
real verdict site, never for a classifier function tested in isolation.

---

## Decisions

### Decision 1 — `APPROVED` requires an exact, whitespace-normalized match against the entire, untruncated body

A response is `APPROVED` if and only if the whitespace-normalized **raw body — no portion of it stripped,
truncated, or otherwise discarded before comparison** — is identical to one of the strings matched by
`CODEX_APPROVED_TEMPLATES` (an array of fully-anchored `^...$` patterns, each representing one evidenced
clean-response shape, footer included, with at most one tightly-bounded placeholder for a field the evidence
itself shows varies — see Decision 2). Concretely:

1. **Whitespace normalization.** `codex_normalize_whitespace` replaces every run of whitespace (spaces, tabs,
   newlines, carriage returns — including blank lines between paragraphs) with a single space, then trims
   leading/trailing whitespace. This is the **only** step performed before matching, and the **only** permitted
   flexibility in the match, per the human decision that produced this design: no case folding, no optional
   clauses, no punctuation tolerance, no synonym alternation, and no truncation.
2. **Exact template match.** The normalized text must satisfy `^...$` for at least one entry in
   `CODEX_APPROVED_TEMPLATES`. Anything else — including a superset (extra trailing or leading text around an
   otherwise-matching template, whether before the visible verdict sentence or after the footer) or a subset (a
   truncated or reworded template, including a body carrying only the footer's opening line rather than its
   complete text) — fails.

There is **no footer-truncation step, no separate fence-marker check, no quoted-span stripping, no
first-paragraph restriction, and no disqualifier scan** in this function. The footer-truncation step the prior
revision of this plan performed here is deleted outright, not merely bypassed — see Decision 5 for why. The
other four were mechanisms that existed to compensate for a parsing layer that no longer exists: a stray fence
marker, a quoted span, or off-position content is now just "extra text that breaks the exact match," and the
match already rejects it without a dedicated check.

**This closes the specific gap Codex GitHub finding `3803545669` identified in the prior revision.** Because
there is no longer a discarded byte range, there is no location left in the body where content can go
uninspected: every byte from the first character of the verdict sentence through the closing `</details>` of
the footer must be part of the one evidenced literal, or the match fails. A body reading the approved template
followed only by the footer's opening line (not its complete text) followed by arbitrary content — the exact
construction the finding raised — does not reproduce the template (the template's literal requires the
complete footer text, not just its first line) and is rejected on that basis alone, independent of what
follows it.

If the match fails, `codex_response_is_approved` returns non-zero and the caller falls through to the existing
safe-fail branch (`VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)`), to the blocking branch
when `codex_response_is_blocking` already matched earlier in the chain (unchanged, Decision 4), or — before
Decision 6's fix — could be misrouted to a wait branch; see Decision 6.

### Decision 2 — Why whole-body exact-template matching converges where every prior design did not, and the rules for extending it safely

**This is a design replacement, not an incremental fix.** The previous designs of this plan (summarized in
"Background" above) are deleted in full: `CODEX_CLEAN_SIGNAL_PATTERN`, `CODEX_CLEAN_SIGNAL_EXCISION`,
`CODEX_APPROVAL_NEGATION_PATTERN`, `CODEX_APPROVAL_HEDGE_PATTERN`, `CODEX_APPROVAL_ACTIONABLE_PATTERN`,
`CODEX_APPROVAL_DISQUALIFIER_PATTERN`, `CODEX_RESIDUE_FILLER_WORD_PATTERN`, `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN`,
`codex_excise_clean_signals`, `codex_residue_is_closed_grammar`, and `codex_response_first_paragraph` are all
removed outright — not deprecated, not left dormant. So are `CODEX_FOOTER_OPENING_LITERAL` and
`codex_strip_codex_footer` (kept by the immediately prior revision; deleted by this one — see Decision 5).
There is nothing in the final design that reads like a vocabulary list, a grammar, a token-class test, or a
truncation boundary, because every one of those was itself the recurring root cause across every prior review
round (see "Background"): each was either an open-ended enumeration over natural language, or — in the
truncation case — a boundary past which bytes were trusted without being read. Neither converges: enumeration
is the literal thesis issue #1491 was filed against, and an unread trust boundary is exactly the same failure
one level removed.

**Why exact matching against live evidence does not have this failure mode.** A regex over vocabulary or
grammar defines an *infinite* language (every sentence some combination of its tokens/rules can produce) and
asks "is this input inside that language" — every prior review round kept finding new sentences inside the
language that shouldn't have been. `CODEX_APPROVED_TEMPLATES` defines a *finite* language (exactly the strings
its anchored patterns can produce, which — because every non-placeholder character is a literal — is either
one exact evidenced string or, for the one bounded field, one of a small enumerable set of exact strings).
There is no "in between" a novel sentence can occupy: it either reproduces a template exactly (whitespace
aside) or it does not, and template membership is decided by direct comparison, not by evaluating whether some
open-ended rule happens to accept it.

**`CODEX_APPROVED_TEMPLATES` — the template, and exactly what evidence it is drawn from.** The single entry
now covers the entire body, footer included:

```bash
CODEX_APPROVED_TEMPLATES=(
  '^Codex Review: Didn'"'"'t find any major issues\. Swish! \*\*Reviewed commit:\*\* `[0-9a-f]{7,40}` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> \[Your team has set up Codex to review pull requests in this repo\]\(https://chatgpt\.com/codex/cloud/settings/general\)\. Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment "@codex review"\. If Codex has suggestions, it will comment; otherwise it will react with 👍\. Codex can also answer questions or update the PR\. Try commenting "@codex address that feedback"\. </details>$'
)
```

- **Template 1** is drawn from the PR #1489 root-comment capture: `Codex Review: Didn't find any major issues.
  Swish!` followed by `**Reviewed commit:** \`87aaefceff\``, followed by the **complete** `<details>` "About
  Codex in GitHub" footer, through its closing `</details>`. Every character is a literal from that capture
  **except** the commit SHA, which is the one field the evidence shows varies.
- **The footer is not a separate, truncated-away region any more — it is part of the literal, evidenced the
  same way the verdict sentence is.** Before binding to it, the footer text (the substring from `<details>`
  through the end of the body) was extracted from every live capture and compared for byte equality (see the
  Cross-Cutting Operational Assumption Check). It is identical across every source, modulo one trailing newline
  present only in the Issues-API capture — an artifact of that endpoint's transport, not a difference in vendor
  content, and one whitespace normalization already absorbs regardless of its source. No field inside the
  footer varies across the evidence, so **no placeholder was introduced anywhere in the footer text** — it is
  bound exactly as tightly as the evidence allows (Decision 5 has the full account of why the footer moved
  from a truncation boundary to part of the literal).
- **The SHA placeholder's bound is `[0-9a-f]{7,40}`, and it is not invented.** It is git's own documented
  abbreviated-to-full SHA-1 commit-id range (`git rev-parse --short` defaults to 7 characters and lengthens
  automatically as a repository grows to avoid collisions; a full SHA-1 is 40 hex characters). This bound is
  wider than the length every real capture happens to show today, deliberately: the SHA's length is a property
  of *this repository's object count*, not of Codex's wording, so a narrower bound tied only to today's
  observation would fail on tomorrow's legitimate response for a reason that has nothing to do with the vendor
  changing anything. This is the **one and only** placeholder in this plan's template. It cannot absorb prose —
  it accepts hex digits and nothing else, within a length range fixed by git's own specification, not by this
  plan's judgment call about what "looks like" a SHA.
- **No other field is a placeholder — not in the verdict sentence, and not anywhere in the footer.** "Swish!"
  is not generalized into "some flavor word," the `**Reviewed commit:**` label is not stripped or made
  optional, and no word, phrase, or markup fragment inside the footer (the settings link, the bulleted list,
  the acknowledgement sentence) is generalized either — every one of those is a literal character in the
  template, exactly as captured. A response reading `Codex Review: Didn't find any major issues.` (no
  "Swish!"), omitting the `Reviewed commit:` line, carrying only the footer's opening line instead of its
  complete text, or carrying the complete footer with any trailing content after `</details>`, does **not**
  match, and returns `NEEDS_REVISION` — see Risks & Mitigations for why this is an accepted, disclosed trade
  rather than an oversight.
- **The generic `### 💡 Codex Review` review-submission wrapper is deliberately not a template.** It carries no
  clean-signal text at all — it is evidence of what a review submission's body looks like, not of what a clean
  verdict in prose looks like — so it is out of scope for this array by definition, not by omission. Decision
  3's `state`-based routing (unchanged) is the correct mechanism for that evidence type, exactly as it already
  was.

**The governing rule for extending `CODEX_APPROVED_TEMPLATES`.** Adding a template is the **only** change that
can widen the approval surface, so it needs the same review discipline `CODEX_CLEAN_SIGNAL_PATTERN` required in
every prior revision:

- A new template must come from a **live capture** of a real Codex response — never invented, never a
  plausible-sounding guess, never a generalization from an existing template ("this probably also happens
  with different wording").
- Any variable field within a new template must be bound as narrowly as the evidence and the field's own known
  specification allow (as the SHA is bound to git's hex-length range, not to an arbitrary wildcard). A
  placeholder that can absorb arbitrary prose is not a bounded field — it is the grammar hole this design
  exists to close, reintroduced in a new shape.
- **Narrowing** — removing a template, or tightening a placeholder's bound — is always safe: it can only
  increase the false-`NEEDS_REVISION` rate. **Widening** — adding a template, or loosening a placeholder's
  bound, or reintroducing any form of truncation before matching — is never safe without the review above,
  because it can only increase the false-`APPROVED` rate. This is the same asymmetry every earlier revision of
  this plan already stated for its own token lists; it applies identically here, at the template level, because
  a template is exactly as much an enumerable admission list as a token was, and a truncation boundary is
  exactly as much an unreviewed trust surface as a vocabulary gap was (Decision 5).

**The residual gap this design accepts, disclosed explicitly.** With one template evidenced, the classifier
will safe-fail on any genuinely clean response that does not reproduce that template's exact wording — a
vendor phrasing change, a different flavor sentence than "Swish!", a missing `Reviewed commit:` line, or a
reworded vendor footer — or the generic review-wrapper format ever gaining clean-signal text of its own.
Binding the footer into the template — rather than continuing to strip it — makes this trade strictly larger
than the prior revision's: a footer wording change now also produces a false `NEEDS_REVISION`, where under the
truncate-then-match design it would not have. This is the accepted trade the human decision made explicitly
(see "Why exact matching…" above and Risks & Mitigations): the failure direction is always safe (more
`NEEDS_REVISION`, never a false `APPROVED`), and the fix — capture the new wording live, add a template with a
stated, evidence-derived bound for any variable field — is the same fix this plan has always prescribed for
its riskiest lever, just now applied to one array instead of several.

### Decision 2 Addendum — PR #1494 live evidence falsified the single-literal flavor assumption (superseded by Decision 2 Second Addendum below; kept for the evidence and history)

**Superseded before merge.** This addendum's own fix — a 14-token literal alternation — was itself replaced by a bounded placeholder (Decision 2 Second Addendum, immediately below) before this PR merged, once the shape of the evidence made clear that enumeration would not converge either. This addendum is kept in full because its evidence-gathering (the 14-token sweep, with full provenance) is exactly what falsified the enumeration approach — it is the record of why the fix below exists, not a stale artifact.

**What happened.** This PR's own first real-world use, PR #1494, received a genuinely clean Codex GitHub
response on its first ready-phase check. The response read `Codex Review: Didn't find any major issues.
:rocket:` — not `Swish!`. `CODEX_APPROVED_TEMPLATES`' one entry hardcoded `Swish!` as a literal, so this
genuinely clean response safe-failed to `NEEDS_REVISION` on the classifier's first real-traffic exercise
(GitHub comment id `5333550055`, PR #1494, 2026-08-18). This is not an implementation defect — the shipped
code does exactly what Decision 2 specified — it is the residual gap Decision 2 already disclosed explicitly
("a vendor phrasing change, a different flavor sentence than `Swish!`... safe-fails") materializing in
practice, faster than expected.

**Live evidence: the flavor slot is a vendor-rotated pool, not a fixed word.** A sweep of every Codex
GitHub clean-verdict root comment reachable in this repository's history (issues/comments across PRs #470–#519,
#683, #869–#872, #1489, #1490, #1492, #1494 — the full set returned by a `commenter:chatgpt-codex-connector[bot]`
search) found **14 distinct flavor tokens**, not the 1–2 anticipated:

| Token (byte-exact) | Evidenced in |
| --- | --- |
| `Swish!` | PR #491 (comment `4381989833`), PR #1489 (comment `5294701769`) |
| `:rocket:` | PR #1494 (comment `5333550055`) — the finding that triggered this correction |
| `Nice work!` | PR #490 (`4381534986`), PR #506 (`4391791674`), PR #871 (`4664586913`) |
| `Chef's kiss.` | PR #503 (`4391484333`), PR #510 (`4392497562`), PR #871 (`4665009816`) |
| `You're on a roll.` | PR #870 (`4664324795`) |
| `:tada:` | PR #869 (`4664269616`) |
| `Another round soon, please!` | PR #500 (`4389724254`), PR #683 (`4500576578`) |
| `:+1:` | PR #481 (`4374386509`), PR #517 (`4396260443`) |
| `Bravo.` | PR #514 (`4392864280`) |
| `Keep it up!` | PR #496 (`4383590778`) |
| `Delightful!` | PR #493 (`4388320805`) |
| `Keep them coming!` | PR #488 (`4380098761`), PR #489 (`4380656798`) |
| `Can't wait for the next one!` | PR #484 (`4374411552`), PR #485 (`4374391710`) |
| `More of your lovely PRs please.` | PR #476 (`4371879954`) |

Every token above was captured verbatim from a live GitHub API response and re-verified byte-for-byte (apostrophe
form, trailing punctuation) before being bound into the pattern — none is invented or paraphrased. The literal
emoji form (`🚀`) was checked for and not found in any capture; every shortcode-style token (`:rocket:`, `:tada:`,
`:+1:`) appears in its raw GitHub shortcode form in the API response body, never as a rendered unicode emoji, so
only the shortcode forms are bound.

**This sample is very likely not exhaustive.** 14 distinct, largely unrelated phrases (single words, full
sentences, GitHub emoji shortcodes, inconsistent trailing punctuation) surfaced from a search covering roughly
40 clean responses — a token discovery rate this high strongly suggests the vendor draws from a large, possibly
still-growing pool, not a small fixed set. This changes the operational cost estimate in "Risks & Mitigations"
below from hypothetical to observed: expect further genuinely clean responses to safe-fail on a
not-yet-evidenced token, and expect this correction cycle (capture live, add to the alternation) to recur.

**Human decision: enumerate, as a bounded alternation, not a wildcard.** The one slot that was a single literal
becomes a parenthesized ERE alternation of every evidenced token
(`(Swish!|:rocket:|Nice work!|Chef's kiss\.|...)`), each token escaped for ERE metacharacters as a literal
string — never a character class, never an open vocabulary, never a "starts with a flavor word" heuristic.
**Rationale for why this is safe where the original disqualifier/vocabulary enumeration (see "Background") was
not**: an incomplete flavor list produces a false `NEEDS_REVISION` — the safe failure direction, identical in
kind to every other residual gap this design already accepts (Decision 2, Risks & Mitigations) — whereas the
disqualifier enumeration that failed across this plan's first three designs produced a false `APPROVED` on every
gap, the unsafe direction. Enumerating the flavor slot is the direct, template-scoped application of the
"capture the new wording live, add a template entry" escape hatch this plan has always prescribed (Decision 2's
extension rule; "Operational cost and escape hatch") — it is not a new mechanism, and it does not reopen the
class of gap the whole-body exact match was designed to close: every character in the body is still either part
of one of the finite literal strings the alternation can produce, or the match fails.

**Standing rule (extends Decision 2's governing rule to the flavor slot specifically).** Adding a flavor token
is, alongside adding a whole new template, the only other lever that can widen the approval surface. It requires
the identical review discipline: a token must come from a **live capture** of a real Codex response, never
invented or guessed by "plausible enthusiasm," and — because unlike the SHA field this slot has no external
specification to bound it — there is no narrower bound available than "the literal set evidenced so far."
Removing a token (if a capture is ever found to be a transcription error) is always safe; adding one requires
the same review this document's history has required for every prior widening.

### Decision 2 Second Addendum — the 14-token alternation was itself replaced by a single bounded placeholder before merge

**Why the first addendum's fix did not survive review.** The enumeration approach (Decision 2 Addendum) was
implemented, verified, committed, and pushed. Before this PR reached human review, the same evidence that
motivated it was re-examined and found to falsify it: **14 distinct flavor tokens surfaced from fewer than 50
historical samples** — single words (`Bravo.`), full sentences (`More of your lovely PRs please.`), GitHub
emoji shortcodes (`:rocket:`, `:tada:`, `:+1:`), with inconsistent trailing punctuation across all of them. A
discovery rate that high, from that few samples, is the signature of **LLM-generated variety**, not a fixed,
enumerable vocabulary. Enumerating it would not converge — this is issue #1491's original complaint (an
open-ended enumeration that a review cycle keeps finding one more case for) **reappearing on a new axis**: the
first three designs this plan shipped failed because a disqualifier/vocabulary list could not keep pace with
negation phrasing; this flavor-token list could not keep pace with the vendor's own enthusiasm phrasing, for
the identical structural reason. The sweep did exactly what it should: it produced evidence, and the evidence
falsified the fix before it shipped, rather than after — the intended function of a Protocol 03 verification
pass, working as designed.

**The fix: one bounded placeholder, not an enumeration.** `CODEX_APPROVED_TEMPLATES`' flavor slot is now:

```text
[^*`[:cntrl:]]{1,40}
```

placed in exactly the position the 14-token alternation and, before that, the `Swish!` literal occupied —
between `Didn't find any major issues. ` and ` **Reviewed commit:**`. Every other character in the template,
including the SHA field's own `[0-9a-f]{7,40}` bound and the complete footer, is unchanged and remains
byte-exact.

**Bound derivation, stated explicitly (not asserted):**

- **Length cap `{1,40}`**: the longest evidenced token is `More of your lovely PRs please.` at **31
  characters**. 40 is 31 rounded up to the nearest 10 with modest headroom — wide enough to admit a somewhat
  longer genuine flavor phrase than any evidenced so far, without being large enough to admit multi-sentence
  injected content (an actionable instruction is realistically longer than 40 characters once it says anything
  concrete).
- **Excluded characters ``[^*`[:cntrl:]]``**: the class excludes exactly three things, each protecting a specific
  piece of adjacent template structure, not a general "looks suspicious" filter:
  - `*` — protects the literal `**Reviewed commit:**` bold-marker syntax immediately following this slot from
    being partially reproduced or spoofed from inside the placeholder.
  - `` ` `` (backtick) — protects the backtick-delimited SHA field that follows.
  - Every control character, via the POSIX `[:cntrl:]` class (covers newline, carriage return, tab, and every
    other C0/C1 control byte in one portable construct, rather than trying to enumerate `\n`/`\r`/`\t`
    individually) — defense in depth. `codex_normalize_whitespace` (Decision 1, unchanged) already guarantees no
    raw control character survives to reach this regex — every whitespace run, including any embedded newline,
    is collapsed to a single space before matching — so this exclusion is currently unreachable in the composed
    pipeline. It is kept explicit anyway, rather than relying solely on that upstream guarantee, because a
    future change to normalization should not silently widen this slot's admitted character set as a side
    effect.
  - No other character is excluded. Apostrophes, colons, commas, periods, exclamation marks, and plain spaces
    are all left admissible, because at least one evidenced token requires each of them (`Chef's kiss.`,
    `:rocket:`, `Another round soon, please!`, `Bravo.`, `Nice work!`, and every multi-word phrase,
    respectively).

**This is a genuine placeholder, unlike the alternation it replaces — the residual risk is stated plainly, not
claimed away.** A false `APPROVED` is now possible if Codex ever emits a response reading `Codex Review: Didn't
find any major issues.` followed by an actual directive inside this 40-character slot, followed by the complete,
exact vendor footer. This requires **self-contradictory vendor output** — the same response asserting "no major
issues" and then, in the same breath, giving an instruction, while still reproducing every other part of the
template verbatim. This is judged an acceptable, disclosed trade for the same reason every other bounded field
in this design is: the alternative (continued enumeration) does not converge, and the alternative to that
(reverting to a vocabulary/grammar scan of the slot's contents) reopens exactly the class of gap this entire
plan exists to close. See Risks & Mitigations for the same row, updated to state this residual risk rather than
the enumeration's now-obsolete "recovery is adding a token" framing.

**Why this differs from a generic wildcard, despite superficially looking like one.** A generic wildcard would
admit the WHOLE body, or an unbounded run, or would sit adjacent to no anchor at all. This placeholder is
bounded on three independent axes simultaneously: **position** (a single fixed slot between two exact literal
anchors, `^Codex Review: Didn't find any major issues. ` before it and ` **Reviewed commit:**` after it —
Decision 1's `^...$` whole-body anchoring is unchanged, so nothing can appear before or after the template as a
whole either), **length** (`{1,40}`, both bounds enforced), and **content** (excludes exactly the three
character classes that could let it interact with adjacent structure). No prior design in this plan's history
had all three properties on the same slot; the SHA field has position and content bounds (git's own hex-length
specification) but its content bound is far narrower (16 possible characters, not "everything except three
exclusions").

**Standing rule (supersedes the first addendum's "adding a token requires review" rule for this slot; the
placeholder is not extended by adding entries).** The two levers that can widen the approval surface for this
specific slot are now: (1) narrowing the length cap or the excluded-character set — always safe, since it can
only shrink what is admitted; (2) widening either — the length cap or the excluded-character set — which
requires the same review discipline as adding a whole new template: a live capture demonstrating the current
bound is too narrow for genuine vendor output, never a guess about what "might" be needed. Reintroducing a
closed enumeration (a list of literal tokens) for this slot, after this correction, must be rejected on sight —
that is precisely the design this second addendum replaced, and re-litigating it requires new evidence that the
bounded-placeholder approach itself has failed, not merely that the enumeration would have been more precise.

### Decision 3 — Composition with the GitHub review `state` short-circuit from PR #1490

PR #1490 threaded GitHub's structured review `state` through evidence selection. That behavior is **preserved
verbatim, unchanged by this or any prior revision of this plan**; template matching is layered underneath it,
not in place of it. The resulting precedence, in the order each verdict site already evaluates it:

1. `state == "CHANGES_REQUESTED"` on review-sourced evidence → blocking, short-circuit, no prose parsing.
   Unchanged (`codex_response_priority`, `codex_combine_terminal_evidence`, and all four verdict sites).
2. `codex_response_is_blocking(body)` → blocking. Unchanged block-list (see Decision 4).
3. `codex_response_is_usage_limit` / `codex_response_is_environment_error` → unavailable. Unchanged.
4. `codex_response_is_approved(body)`, only for terminal (SHA-pinned / review-sourced) evidence → `APPROVED`.
   **This function's contract is the primary thing this plan changes.**
5. Acknowledgement text present, evidence not yet terminal → wait for more evidence (Decision 6 gates this
   condition on non-terminal evidence, so terminal evidence with acknowledgement text falls through to 6).
6. Anything else → safe-fail `NEEDS_REVISION`. Unchanged.

Because the classifier only ever moves responses **out of** tier 4 and into tier 6, it cannot weaken the
`CHANGES_REQUESTED` short-circuit, cannot change `codex_response_priority`'s tier ordering, and cannot let
blocking evidence be hidden behind an availability notice. Since exact template matching can only ever be
**more** restrictive than every prior design, this precedence composition needs no re-verification beyond what
prior revisions already established for tiers 1–3 — Decision 6 covers tier 5, the one link in the chain this
plan's stricter tier-4 behavior newly interacts with.

**Explicitly considered and deferred**: adding `state == "APPROVED"` as an independent sufficient condition
(the symmetric complement of PR #1490's `CHANGES_REQUESTED` short-circuit). It is deferred because the
observed Codex wire format submits clean results as `COMMENTED` reviews or root comments, never as an
`APPROVED` review, so the path would be dead code today while widening the approval surface. If the vendor
ever starts submitting `APPROVED` reviews, that is the right follow-up and should be filed as its own item —
and, notably, would be the one case where a structured signal is *more* trustworthy than prose matching, since
it comes from GitHub's own API rather than from parsing vendor-authored text.

### Decision 4 — `codex_response_is_blocking` stays a block-list

`codex_response_is_blocking` is **kept, with zero edits — not even the drop of a call site.** `CODEX_BLOCKING_PATTERN`,
`CODEX_MERGE_REFUSAL_PATTERN`, `CODEX_NEGATION_WORDS`, `codex_strip_quoted_spans`, and **`codex_strip_not_only_idiom`
and its call inside `codex_response_is_blocking`** are all **kept unchanged** — this redesign does not touch
any of them. The claim "`codex_response_is_blocking` is unchanged" is true **only conditional on retaining
this one call site** — every place that claim appears in this document (this Decision, the Summary, Risks &
Mitigations) states that condition explicitly.

- **The failure directions are not symmetric.** A false negative from `is_approved` is safe (extra
  `NEEDS_REVISION`); a false negative from `is_blocking` is unsafe. Protocol 93 and
  `codex_combine_terminal_evidence` both depend on "blocking always wins outright" so that an actionable
  finding is never hidden behind a usage-limit `UNAVAILABLE` verdict or an environment-error `TIMED_OUT`
  verdict — the two are distinct outcomes with different verdict strings and exit codes (see the
  Decision-gate matrix). Converting
  `is_blocking` to exact-template matching would mean a genuine refusal in ANY wording other than a captured
  template would be **missed entirely** — the opposite of this plan's goal. Exact matching is only safe to
  apply to the direction where a miss is safe; `is_blocking`'s miss direction is unsafe, so it keeps its
  block-list, unchanged.
- **Its vocabulary gaps stop being correctness bugs**, for the same reason every earlier revision of this plan
  already gave: under exact-template `is_approved`, a missing `is_blocking` synonym costs, at worst, a
  tier-4-vs-tier-6 nuance (an unrecognized refusal falls through to the already-conservative
  `NEEDS_REVISION` safe-fail instead of the more specific blocking verdict) — never a false `APPROVED`, since
  `is_approved` independently requires exact template reproduction regardless of what `is_blocking` decided.
- **This revision removes the last case where the approval path depended on `is_blocking` to prevent a false
  `APPROVED`.** Under the prior (truncate-then-match) revision, a refusal placed after the footer's opening
  line was invisible to `is_approved` on its own — `is_approved` alone would have returned `APPROVED` for that
  body, and only `is_blocking`'s independent, untruncated scan of the same raw body (evaluated first at every
  verdict site, Decision 3) kept the composed verdict correct. Under this revision, that case no longer exists:
  `is_approved` reads the entire body itself, so inserting a refusal anywhere — including inside the footer —
  already breaks the whole-body exact match on its own, with no help from `is_blocking` needed. `is_blocking`
  still runs first at every verdict site and still independently flags a recognized refusal, but it is now
  redundant-but-harmless for this specific composition, not load-bearing for it: it upgrades an already-correct
  `NEEDS_REVISION` safe-fail to the more specific blocking verdict, it does not prevent a false `APPROVED` that
  `is_approved` would otherwise have produced. This is a direct consequence of Decision 1's whole-body match,
  not a new mechanism added to `is_blocking` itself.

**`codex_strip_not_only_idiom` is kept — the function definition, and its one remaining call site inside
`codex_response_is_blocking`.** An earlier revision of this document scheduled this call site for deletion
alongside `is_approved`'s (now-fully-replaced) old call site — that would have been a real regression, since
`CODEX_MERGE_REFUSAL_PATTERN` is built from `CODEX_NEGATION_WORDS`' bare `not` alternative plus
`[^.!?;,]*(be[[:space:]]+)?merged?` — the exact same construction that motivated `codex_strip_not_only_idiom`
for `is_approved` in the first place, now inherited by `is_blocking` once `CODEX_BLOCKING_PATTERN` absorbed
`CODEX_MERGE_REFUSAL_PATTERN` (documented in the production script's own comment above
`codex_response_is_blocking`, citing PR #1490 finding `3799277922`). Executing the real, unmodified
`CODEX_MERGE_REFUSAL_PATTERN`/`CODEX_NEGATION_WORDS`/`codex_strip_not_only_idiom` against `This is not only
safe to merge but looks good.` confirms the strip is load-bearing: without it, the pattern matches (false
blocking); with it (the production script's actual, current behavior), it does not match (correct). Deleting
the call reintroduces exactly this false-positive on a genuinely clean response containing "not only … merge"
in the same clause. Before scheduling any other symbol for deletion, check whether it has a real call site
inside `codex_response_is_blocking` specifically — see the standing rule in Risks & Mitigations.

**What is actually removed, and why that removal is still correct.** The call site inside the *original*
`codex_response_is_approved` (the pre-plan function this revision fully replaces, not edits in place) is gone
— but that is a consequence of replacing the entire function body with the whole-body exact-template match
(Decision 1), which performs no prose normalization of any kind and therefore has no use for any stripping
helper. Nothing is deleted from `is_approved` by name; the function that called `codex_strip_not_only_idiom` no
longer exists in its old form at all. This is the same distinction Decision 2 already draws for every other
now-unused prose-matching symbol — the difference for `codex_strip_not_only_idiom` specifically is that,
unlike those other symbols, it still has one real, load-bearing caller left (`is_blocking`), so the function
itself is not obsoleted, only one of its two call sites is.

### Decision 5 — The vendor `<details>` footer is captured verbatim as part of the exact-match template; it is no longer truncated before classification

**This decision reverses the prior revision's Decision 5.** The prior revision truncated the body at the
footer's opening line via `codex_strip_codex_footer`/`CODEX_FOOTER_OPENING_LITERAL`, matched only the visible,
pre-truncation portion, and trusted everything from the opening line onward as inert footer content it never
inspected. Codex GitHub finding `3803545669` showed that trust was exactly the gap this plan's history keeps
finding in a new location: a body reading the approved template, then the footer's opening line only, then
`Rename the unsafe function.`, matched the visible portion exactly and was classified `APPROVED` — the
instruction hiding in the discarded suffix was never read by anything.

**The fix is not a fourth tightening of the truncation boundary — it is removing the boundary.**
`codex_strip_codex_footer` and `CODEX_FOOTER_OPENING_LITERAL` are **deleted outright, not narrowed and not
kept dormant** — see Decision 2's symbol list and the Layer-by-Layer checklist. There is no replacement helper
that performs any form of truncation, partial capture, or "read up to N lines of footer" logic; the footer's
complete text is instead one contiguous literal segment inside `CODEX_APPROVED_TEMPLATES`' single entry
(Decision 2), matched by the exact same whole-body comparison as every other part of the template. Nothing
about the body is discarded before comparison any more (Decision 1) — there is no longer a byte range that is
trusted without being read, because there is no longer a byte range that is not part of the literal being
compared.

**Deleting these two symbols does not affect anything else in the file, because nothing else in the file ever
called them.** `codex_strip_codex_footer` was applied **only** inside `codex_response_is_approved` — never to
`codex_response_reviews_current_head`'s SHA extraction, never to the acknowledgement branch that matches text
living inside the footer, and never to `codex_response_is_blocking`'s scan. All three of those already operated
on the raw, untruncated body before this round, and continue to after it, completely unaffected by this
decision.

**Why the footer's text must be byte-identical across the evidence before being bound into the template.**
Binding a literal from a single capture, without checking whether it is representative, would reintroduce
exactly the risk Decision 2's governing rule forbids: a placeholder or a lucky-guess literal standing in for
content that actually varies. See the Cross-Cutting Operational Assumption Check for the verification method
and result. No field inside the footer was found to vary, so the footer contributes zero placeholders to the
template — every character of it is a literal, exactly as tight a bound as the SHA field's `{7,40}` hex-only
bound is for its one variable field (Decision 2). If a future capture ever shows real variation inside the
footer, the correct response is the same one Decision 2 already prescribes for any template field: bind the
varying part as narrowly as that specific field's own evidence and specification allow, backed by a live
capture — never a wildcard, and never a return to truncation.

**The accepted trade this decision makes, recorded explicitly.** Binding the template to the complete vendor
footer means this classifier now depends on wording that OpenAI controls and could change without notice — the
settings-link text, the bulleted list, the acknowledgement sentence — none of which has anything to do with
whether a given PR is clean. A footer wording change (however cosmetic) will safe-fail every clean PR's
approval until a maintainer re-captures the new footer text live and updates the template. This is accepted,
not overlooked, for the same reason every trade in this plan's history has been accepted: **the failure
direction is safe.** A reworded footer produces more `NEEDS_REVISION`, never a false `APPROVED` — the opposite
of the risk this decision closes. This row is also recorded in Risks & Mitigations.

**This decision removes the last case where `codex_response_is_blocking` was load-bearing for the approval
path's safety, not merely for its specificity.** See the new bullet in Decision 4: under the prior revision,
only `is_blocking`'s independent scan of the untruncated body prevented a false `APPROVED` when a refusal was
placed after the truncation point. Under this revision, `is_approved` alone already rejects that body — the
whole-body match has no truncation point left to place a refusal after. `is_blocking` still runs first at
every verdict site (Decision 3) and still gives the more specific blocking verdict when it recognizes the
refusal's wording, but the approval path no longer needs it to avoid a false `APPROVED` — it needed to, once,
and does not any more.

### Decision 6 — The acknowledgement branch is gated to non-terminal evidence, so a footer-bearing near-miss safe-fails instead of waiting

**This decision corrects Codex GitHub finding `3804535190` (P1, review round 11) and is the first change this
revision makes to the verdict-parsing *chain* itself, not just to `codex_response_is_approved`.** Every prior
decision in this plan (1–5) modeled `codex_response_is_approved`'s own return value as the thing that
determines the verdict. That is wrong: the real verdict is determined by the **composed chain** at each of the
four verdict sites in `codex-github-reviewer.sh` (main loop, async-arrival, async-final, async-reaction-final),
and one step in that chain — immediately after the `is_approved` check — was never accounted for.

**The gap, reproduced by execution, not asserted.** All four verdict sites contain, in this order: blocking →
usage-limit → environment-error → `[ source = "review" ] && is_approved` → **`grep -qi "If Codex has
suggestions, it will comment; otherwise it will react with" <<< body` → `continue`/`sleep` (wait for more
evidence)** → (non-terminal comment) `continue` → else: `NEEDS_REVISION` safe-fail. This acknowledgement branch
predates this plan; it exists to recognize a genuine "Codex hasn't produced a verdict yet" acknowledgement (a
bare, non-terminal comment carrying only the footer, no `Reviewed commit:` marker) and correctly wait for real
evidence rather than safe-failing prematurely. Under the pre-plan block-list `is_approved`, a real verdict body
with genuine content almost always matched the approval vocabulary directly, so this branch was rarely if ever
exercised for *terminal* (SHA-pinned) evidence with real content — it was a dormant assumption, not a tested
one. This plan's whole-body exact-match design is categorically stricter: it requires the complete real footer
as part of the one evidenced literal, so **any genuine Codex response that carries the real footer but is not
the exact template — which is most of them — now also matches this acknowledgement check** and is routed to
`continue`/`sleep` instead of the safe-fail branch. Patching a copy of the production script with only
`is_approved` replaced (Decision 1–5's design, unmodified) and running every footer-bearing case in the
Parser-risk addendum through the real, composed chain via a mocked `gh` confirmed this by execution: several
edge cases beyond the ones Codex specifically named produced `VERDICT: TIMED_OUT`, not the documented
`NEEDS_REVISION` safe-fail — see the Parser-risk addendum for the full case set this affects.

**The fix: gate the acknowledgement check on the evidence being non-terminal.** At all four verdict sites, the
acknowledgement `elif` is changed from an unconditional footer-text match to a conditional one:
`[ SOURCE != "review" ] && grep -qi "…" <<< BODY` (or, in the two sites written with a negated form, `[ SOURCE
= "review" ] || ! grep -qi "…" <<< BODY`). This is a **narrowing** of the acknowledgement branch's trigger
condition, not a widening of anything — it removes exactly the one case (terminal, SHA-pinned evidence) the
branch was never meant to catch, and every case it *was* meant to catch (a bare, non-`Reviewed-commit`-pinned
comment) is untouched, because such a comment can never be `source == "review"` in the first place
(`codex_response_reviews_current_head` requires an extractable `{7,40}`-hex-char SHA from a `Reviewed commit:`
marker; an acknowledgement-only body has none).

**Why this is safe, verified two ways, not asserted.**
1. Swept `test-pr-review-loop.sh` for every scenario whose mocked payload contains the literal acknowledgement
   phrase: every match found is either a separate, later, non-terminal ancillary comment following a distinct
   terminal/blocking comment in the same fetch, or a bare non-terminal comment with no `Reviewed commit:`
   marker at all. No existing scenario combines the acknowledgement phrase with SHA-pinned terminal evidence in
   the same body — the gate touches no currently-tested combination.
2. Applied *only* this gate to an otherwise-completely-unmodified copy of the real production script (real,
   pre-plan `codex_response_is_approved` left untouched) and ran the full, existing test suite against it: it
   passed in full, with no failures. The change is behaviorally inert for every scenario that exists today; it
   only changes behavior for the new class of input this plan's stricter classifier newly produces.

**Exactly which sites change, named precisely**: `codex-github-reviewer.sh`'s main-loop, async-arrival,
async-final, and async-reaction-final verdict sites — the acknowledgement `elif` at each. No other line at any
of the four sites changes. `codex_response_is_blocking`, the usage-limit/environment-error checks, and the
final `else` safe-fail are all unaffected.

**Each of the four copies must be exercised by its own test, not inferred from the others** (Codex GitHub
finding `3805277351`, P2). Because the fix is four hand-edited copies of one conditional, a typo in any one of
them is exactly the kind of defect that survives a test suite where only one copy happens to be exercised —
this is a distinct risk from whether the fix's *logic* is correct, which the reasoning above already
establishes. "New scenarios" adds one terminal, footer-bearing near-miss scenario per site, confirmed this
round by execution to resolve at its named site and to detect a regression when only that site's gate is
reverted (the other three left correct).

**Standing rule**: every edge-case expectation in this document is stated for the **composed verdict chain at
a real verdict site**, never for `codex_response_is_approved` (or any other classifier function) in isolation.
Two review rounds have now found a false claim caused by exactly this modeling error — one earlier round
(`codex_strip_not_only_idiom` load-bearing inside `codex_response_is_blocking`, discovered by testing the
classifier in isolation instead of composed with `is_blocking`) and this decision (discovered by testing
`is_approved` in isolation instead of composed with the full verdict-site chain). This standing rule is also
recorded in Risks & Mitigations. Verification of any future classifier change must patch a copy of the real
production script with only the changed function replaced — everything else, including all four real verdict
sites, left untouched — and run the actual case through the real, composed chain via a mocked `gh`, not
through the function called directly.

---

## Layer-by-Layer Changes

Only the tooling layer of this repository is affected. There is no database, API, frontend, or infrastructure
surface in scope.

### Shell tooling — `scripts/development-workflow/codex-github-reviewer.sh`

**Shell contract**: `bash` (the script declares `#!/usr/bin/env bash` and uses `<<<` here-strings, `local`,
and `[[ ]]`-free POSIX tests). No portable `bash-zsh` snippet is introduced.

- [ ] **Gate the acknowledgement branch on non-terminal evidence, at all four verdict sites** (Decision 6) —
      this is a change to the verdict-parsing **chain**, not to `codex_response_is_approved` itself. At each of
      the main-loop, async-arrival, async-final, and async-reaction-final verdict sites, change the
      acknowledgement `elif` from an unconditional footer-text match to one gated on `source != "review"` (or
      the equivalent negated form at the sites already written with `!`). Without this gate, a genuine Codex
      response that carries the real footer but does not exactly match the evidenced template is misrouted to
      `continue`/`sleep` (wait for more evidence) instead of the documented `NEEDS_REVISION` safe-fail, and
      eventually times out.
      *Verify*: run every footer-bearing edge case in the Parser-risk addendum through the real, patched script
      via a mocked `gh` (not `is_approved` in isolation) and confirm each produces the documented composed
      verdict, never `VERDICT: TIMED_OUT`. **This is not sufficient on its own** — a single scenario per edge
      case resolves at whichever site its default mock sequencing reaches (typically main-loop), so it cannot
      confirm the other three duplicated copies of this gate are each correct. Additionally run the four
      verdict-site near-miss scenarios from "New scenarios" (one routed to each of main-loop, async-arrival,
      async-final, and async-reaction-final) and confirm all four produce `NEEDS_REVISION`, never
      `VERDICT: TIMED_OUT` — a missed or mistyped gate at any one site must be caught by exactly that site's
      scenario. Finally, apply only this gate to an otherwise-unmodified copy of the real script and confirm
      the full existing test suite still passes with no failures.
- [ ] **Rename nothing, delete outright**: `CODEX_APPROVAL_PATTERN` (the original pre-plan symbol) is
      **deleted**, not renamed. Every prior revision of this plan proposed renaming it to
      `CODEX_CLEAN_SIGNAL_PATTERN`; the final design has no equivalent symbol at all, since there is no
      clean-signal vocabulary to match against — matching is against whole-body templates instead.
- [ ] **Delete** `CODEX_NEGATED_APPROVAL_TARGET_WORDS` and `CODEX_NEGATED_APPROVAL_PATTERN`.
- [ ] **Delete** every symbol this plan itself introduced in an earlier revision and no longer ships:
      `CODEX_CLEAN_SIGNAL_PATTERN`, `CODEX_CLEAN_SIGNAL_EXCISION`, `CODEX_APPROVAL_NEGATION_PATTERN`,
      `CODEX_APPROVAL_HEDGE_PATTERN`, `CODEX_APPROVAL_ACTIONABLE_PATTERN`, `CODEX_APPROVAL_DISQUALIFIER_PATTERN`,
      `CODEX_RESIDUE_FILLER_WORD_PATTERN`, `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN`, `CODEX_RESIDUE_STARTER_PATTERN`,
      `codex_excise_clean_signals`, `codex_residue_is_closed_grammar`, `codex_response_first_paragraph`, and
      `codex_strip_vendor_metadata_lines`. None of these has a role in the final design — see Decision 2 for
      why each category (vocabulary, grammar, position) was replaced, not narrowed.
- [ ] **Keep** `codex_strip_not_only_idiom` — **the function definition, and its call inside
      `codex_response_is_blocking`.** See Decision 4 for why this call site is load-bearing and why an earlier
      revision's plan to delete it was wrong. **Only the call site inside `codex_response_is_approved` is
      gone** — not by an explicit deletion instruction, but because the entire function is being replaced by
      the whole-body exact-template match (Decision 1), which performs no prose normalization at all.
      *Verify*: any count-based check of this symbol's occurrences must filter comment lines before counting —
      `codex_response_is_blocking`'s own rationale comment names it too, so a raw count includes non-executable
      matches (`grep -v '^[[:space:]]*#' scripts/development-workflow/codex-github-reviewer.sh | grep -c
      "codex_strip_not_only_idiom"`). After a correct implementation, this comment-filtered count must show
      exactly the definition plus its one remaining call, inside `codex_response_is_blocking` — confirm the
      remaining call is not inside `codex_response_is_approved` by inspecting the surrounding lines directly,
      not by count alone.
- [ ] **Keep unchanged**: `codex_response_has_fence_marker`, `codex_strip_quoted_spans`,
      `codex_response_is_usage_limit`, `codex_response_is_environment_error`,
      `codex_response_reviews_current_head`, `codex_response_priority`, `codex_select_terminal_evidence`,
      `codex_select_review_evidence`, `codex_combine_terminal_evidence`, `codex_response_is_blocking`,
      `CODEX_BLOCKING_PATTERN`, `CODEX_NEGATION_WORDS`, `CODEX_MERGE_REFUSAL_PATTERN`, and all four
      verdict-emission sites (aside from the Decision 6 gating change). Note that `codex_response_has_fence_marker`
      and `codex_strip_quoted_spans` are kept **because other functions still call them** (`is_usage_limit`,
      `is_environment_error`, `is_blocking`) — `is_approved` itself no longer calls either (see Decision 1).
- [ ] **Delete** `CODEX_FOOTER_OPENING_LITERAL` and `codex_strip_codex_footer` — kept unchanged by the
      immediately prior revision, deleted outright by this one (Decision 5). Nothing in the redesigned
      `codex_response_is_approved` calls either, and nothing else in the file ever did (Decision 5 confirms
      no other caller exists).
      *Verify*: a search for either symbol name in the file returns nothing.
- [ ] **Add** `CODEX_APPROVED_TEMPLATES` — a bash array of fully-anchored `^...$` ERE patterns, one entry per
      evidenced clean-response shape (exactly one today, now covering the entire body including the complete
      vendor footer — no separate footer-truncation step exists any more). See Decision 2 for the template, its
      provenance, the one bounded placeholder it contains, and the extension rule. **Any future PR that adds an
      entry must be backed by a live capture and hold any variable field to the narrowest bound the evidence and
      the field's own specification allow, and must not reintroduce any truncation step** — this is the sole
      lever that can widen the approval surface, and is held to the same review discipline
      `CODEX_CLEAN_SIGNAL_PATTERN` required in every prior revision.
- [ ] **Add** `codex_normalize_whitespace` — collapses whitespace runs to a single space and trims. Unchanged
      from the prior revision; still the only permitted flexibility in the match (Decision 1).
- [ ] **Rewrite** `codex_response_is_approved` per Decision 1: normalize whitespace on the **raw, untruncated**
      body, test against every entry in `CODEX_APPROVED_TEMPLATES`, return 0 on the first match or 1 if none
      match. No footer-strip call, and no diagnostic line is emitted (see the Code Samples note on why the
      previous stderr diagnostics are removed).
- [ ] **Update** every source comment that describes the classifier's contract or `codex_response_is_approved`'s
      relationship to other helpers — see the "Update every stale approval-path comment" step in Implementation
      Order for the method to find and fix all of them, rather than a fixed list of line numbers here (source
      line numbers shift as this plan's own edits are applied, so a list frozen in this document goes stale the
      moment implementation starts).

### Tests — `scripts/development-workflow/tests/test-pr-review-loop.sh`

- [ ] **Before starting this work, re-derive which scenarios exist, by name, directly against the real file**
      — do not trust a name list carried forward from an earlier revision of this document without re-running
      the derivation described in "Test disposition." The file changes over time and between rounds of this
      plan's own review; a name list frozen in prose goes stale.
- [ ] Retarget every real, confirmed-existing scenario whose fixture body is not byte-for-byte (whitespace
      aside) `CODEX_APPROVED_TEMPLATES`' one entry, from `VERDICT: APPROVED` to `VERDICT: NEEDS_REVISION` — see
      "Test disposition" for the derivation method. Update each retargeted scenario's fixture-body comment to
      state the new reason (the body is not an exact template reproduction), not the superseded grammar-based
      reason. **Each retargeted scenario also has a paired `*_exit_clean` assertion that must retarget in the
      same commit**, from `"0"` to `"1"` — see "Test disposition" for why this pairing matters and how to find
      every instance.
- [ ] **Update the bodies of every scenario in Group APPROVED** — see "Test disposition" for the full
      membership and per-scenario notes. **All eight members need a full body replacement with the exact
      template's verdict sentence (including the `Swish!` sentence), `**Reviewed commit:**` marker, and
      complete footer — this is not merely a footer append for any of them (Codex GitHub finding
      `3805497682`, P2: the two template-anchored members' real, current bodies read `Codex Review: Didn't
      find any major issues.` followed directly by the SHA marker, with no `Swish!` sentence and no footer at
      all — appending only the footer would leave the verdict sentence short of the template and the
      retained `APPROVED` assertion would fail).** For the routing-testing members kept in this group, the
      full replacement is the same requirement already stated for a different reason (their current bodies
      use entirely different wording, not merely a missing `Swish!`/footer) — while preserving each one's
      distinguishing mock sequencing (poll timing or competing-evidence setup), or the routing behavior it
      tests is no longer exercised. This is a stricter requirement than the prior revision's: under
      truncate-then-match, a fixture body omitting the footer (or reading a close-but-inexact verdict
      sentence) still matched under the old vocabulary-based check; under whole-body exact matching, nothing
      is discarded or approximated any more, so the body must reproduce the template exactly.
- [ ] Add the new scenarios listed in "New scenarios" — see that section for the full list and construction
      notes for each.
- [ ] Consolidate, rather than individually re-litigate, the regression scenarios whose underlying mechanism no
      longer exists but whose scenario **is real** — this is Group UNCHANGED-NEEDS_REVISION; see "Test
      disposition" for the derivation method. These constructions are now trivially rejected because they do
      not reproduce a template, and the assertion itself does not change (already `NEEDS_REVISION`), but their
      comments must be rewritten to say so rather than describing removed machinery. Do **not** delete them:
      they remain valid regression coverage. **Do not touch Group UNTOUCHED** (see "Test disposition") — it
      neither approves nor depends on approval-content parsing, with one exception: any assertion paired with a
      Group RETARGETED scenario is part of that scenario's retargeting, not part of Group UNTOUCHED, even if it
      carries no `VERDICT:` string itself.
      *Verify*: run `bash scripts/development-workflow/tests/test-pr-review-loop.sh` and confirm it exits 0,
      and that only the scenarios named by the "Test disposition" derivation method changed expectation.

### Documentation

- [ ] `docs/workflow/development-workflow/integrations/codex-github.md`
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
- [ ] `CHANGELOG.md`

See "Documentation Updates" for exactly what changes in each.

---

## Code Samples

<!-- Illustrative — adapt during implementation. -->

**Post-implementation note (Decision 2 Second Addendum):** the flavor slot below is shown with the single
`Swish!` literal this plan originally shipped. The shipped code no longer matches this illustration exactly —
the flavor slot is a single bounded placeholder, ``[^*`[:cntrl:]]{1,40}`` (see Decision 2 Second Addendum for the
full derivation of its length cap and excluded-character set), not a single literal and not an enumeration.
This snippet is left as originally illustrative, per its own header, rather than rewritten to track every
subsequent correction; the shipped `codex-github-reviewer.sh` and Decision 2 Second Addendum are authoritative
for the current contract.

**This is the fourth design this plan has shipped**, replacing (not extending) the truncate-then-match design
of the immediately prior revision after Codex GitHub finding `3803545669` showed that design still trusted
every byte after the footer's opening line, unseen (see "Background" and Decisions 1, 2, and 5 for the full
history). Every regex and helper below targets the same macOS BSD toolchain this plan has targeted throughout
(`sed`, `grep`, `awk`, `tr`, invoked via their `/usr/bin/` paths to avoid any interactive-shell aliasing) and
must also be re-verified against GNU tooling in CI at implementation time.

```bash
# Illustrative — adapt during implementation.
#
# Collapses every run of whitespace (spaces, tabs, newlines, carriage
# returns — including blank lines between paragraphs) to a single space,
# then trims leading/trailing whitespace. This is the ONLY step performed
# before matching, and the ONLY permitted flexibility in template matching
# (Decision 1) — no case folding, no optional clauses, no punctuation
# tolerance, no synonym alternation, and no truncation of any kind.
# `tr` first converts every whitespace class this function cares about to
# a literal space (BSD tr does not support `\s`, hence the explicit
# newline/tab/carriage-return class), then `tr -s ' '` squeezes runs of
# spaces to one; `sed` trims the two remaining edges. Unchanged from the
# prior revision.
codex_normalize_whitespace() {
  local text
  text=$(tr '\n\t\r' '   ' <<< "$1" | tr -s ' ')
  sed -E 's/^ //; s/ $//' <<< "$text"
}

# Exact captured clean-response template, covering the ENTIRE body —
# verdict sentence AND the complete vendor footer, with no truncation step
# anywhere in this function. This closes Codex GitHub finding `3803545669`:
# the prior revision truncated the body at the footer's opening line and
# matched only the visible portion, trusting every byte after that line,
# unseen; a body reading the template + the footer's opening line only +
# "Rename the unsafe function." matched the visible portion exactly and was
# classified APPROVED. There is no discarded byte range left for that
# construction (or any construction) to hide in — the entire body, first
# character to last, must be part of this one literal.
#
# See Decision 2 for the full provenance, the ONE bounded placeholder this
# plan permits (a commit SHA, bound to git's own documented
# abbreviated-to-full SHA-1 hex-length range — NOT to the single length
# this round's captures happen to show), and the extension rule (a new
# entry requires a live capture and the same review CODEX_CLEAN_SIGNAL_PATTERN
# required in every prior revision — it is the ONLY lever that can widen the
# approval surface; reintroducing any truncation step is explicitly
# forbidden by that same rule, see Decision 5).
#
# The footer portion of this literal was verified byte-identical across
# every real capture — the PR #1489 root comment and every PR #1490 review
# — modulo one trailing newline present only in the Issues-API capture,
# which whitespace normalization already absorbs. No field inside the
# footer varies, so the footer contributes zero placeholders.
#
# The apostrophe in "Didn't" is a literal straight ASCII apostrophe, NOT a
# regex wildcard — do not replace it with `.` if this pattern is edited; a
# wildcard there would silently widen the match to any character, which is
# exactly the kind of unreviewed widening this design forbids.
CODEX_APPROVED_TEMPLATES=(
  '^Codex Review: Didn'"'"'t find any major issues\. Swish! \*\*Reviewed commit:\*\* `[0-9a-f]{7,40}` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> \[Your team has set up Codex to review pull requests in this repo\]\(https://chatgpt\.com/codex/cloud/settings/general\)\. Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment "@codex review"\. If Codex has suggestions, it will comment; otherwise it will react with 👍\. Codex can also answer questions or update the PR\. Try commenting "@codex address that feedback"\. </details>$'
)

codex_response_is_approved() {
  local body="$1" normalized template
  normalized=$(codex_normalize_whitespace "$body")
  for template in "${CODEX_APPROVED_TEMPLATES[@]}"; do
    if grep -qE "$template" <<< "$normalized"; then
      return 0
    fi
  done
  return 1
}
```

Notes for the implementer:

- **No footer-truncation call, and no separate "visible" variable.** The prior revision computed a `visible`
  intermediate (the body with everything from the footer's opening line onward discarded) and matched only
  that. This revision normalizes and matches the raw `$body` directly — there is nothing left to discard, and
  the removal of that one line **is** the fix for finding `3803545669`, not an unrelated simplification.
- **No stderr diagnostic is emitted on a non-match.** Every prior revision of this plan emitted an
  `INFO: Codex clean signal present but disqualified (…)` line naming which rule fired, because there were
  multiple rules (a disqualifier match vs. an unclosed grammar clause) worth distinguishing operationally.
  Under exact-template matching there is exactly one reason a response fails to approve: it does not
  reproduce an evidenced template. A diagnostic distinguishing "no reason" is not useful, and adding one that
  tried to explain *why* a template didn't match would reintroduce a fuzzy-matching concept this design
  deliberately does not have. If operational visibility into false-`NEEDS_REVISION` cases is wanted later, the
  correct mechanism is the operational-cost logging already described in "Operational cost and escape hatch,"
  not a per-call diagnostic.
- **No fence-marker check, no quote-stripping, and no first-paragraph restriction are performed inside this
  function**, unlike every prior revision. Each was a defense against a specific way a parsing layer could be
  fooled; there is no parsing layer left to fool. A fenced, quoted, or off-position wrapper around the real
  template-plus-footer body all fail to match, with no dedicated check needed — the exact-match requirement
  already rejects any extra or reordered text (verify at implementation time — see "Testing Strategy").
- `codex_response_has_fence_marker` and `codex_strip_quoted_spans` remain defined and used elsewhere in the
  file (by `is_usage_limit`, `is_environment_error`, and `is_blocking`); this function simply no longer calls
  either — unchanged from the prior revision.
- Performance: this implementation is a fixed number of `tr`/`sed`/`grep` passes over the body regardless of
  its structure (no per-sentence or per-clause loop, and — as of this revision — no separate `awk` truncation
  pass either). Confirm at implementation time against a large (e.g. ~200,000-character) SIGPIPE-safety
  fixture that the function completes quickly with no hang or crash and correctly returns `NEEDS_REVISION`.
- Every real captured body, every construction found across this plan's review history (the Parser-risk
  addendum), and every scenario in the existing test corpus (organized as Group APPROVED/RETARGETED/
  UNCHANGED-NEEDS_REVISION/UNTOUCHED — see "Testing Strategy") must be re-verified against this exact
  implementation, on both BSD and GNU `sed`/`grep`/`awk`/`tr`, before this work is considered done.

---

## Parser-risk addendum

This plan is **parser-risk**: it materially changes how the response body is compared against expected
content, even though the final design has deliberately minimal "parsing" left — whitespace normalization only,
applied to the raw, untruncated body (see Decision 1). There is no footer-truncation step any more; the prior
revision's edge cases that specifically exercised truncation (footer-opening-line matching, the "does it get
discarded" question) are superseded by the whole-body edge cases below.

### Edge-case enumeration

**Verification method, stated once, applies to every row below**: an edge case's real disposition must be
proven by running the actual construction through the real, composed verdict chain (the production script,
unmodified except for the Decision 6 gate) via a mocked `gh`, never by evaluating `codex_response_is_approved`
in isolation (standing rule, Decision 6) — a classifier-only test cannot see the acknowledgement branch
downstream of it. **A single scenario resolves at whichever one of the four verdict sites its mock sequencing
reaches — by default, main-loop.** This is sufficient for edge cases that are not specifically about the
acknowledgement gate (E1–E24 below), since the gate's *logic* is the same at every site regardless of which
one a given scenario happens to hit. It is not sufficient to confirm all four hand-edited copies of the gate
are individually correct — that requires the dedicated per-site scenarios in "New scenarios," not an inference
from edge cases that happen to resolve at one site. Two fixture-construction caveats apply to several rows and
are stated once here rather than per row:

- A case whose SHA field is malformed (below or above the `{7,40}` bound, or non-hex) or whose entire body is
  case-folded **cannot be constructed as a SHA-pinned root comment** — `codex_response_reviews_current_head`'s
  extraction regex requires a well-formed, case-sensitive `Reviewed commit:` match, so a malformed/case-folded
  SHA never becomes terminal evidence via that path regardless of what the classifier decides. Construct these
  cases as a **review** instead (`pulls/{PR}/reviews`, pinned via the API's own `commit_id` field, independent
  of the body text) to correctly isolate what the classifier itself does with the malformed value.
- A case that must reach terminal evidence but whose described body has no `**Reviewed commit:**` marker at
  all cannot pin as terminal either, for the more basic reason that there is nothing to extract — add the
  marker to the body before treating the case as terminal-evidence-eligible.
- A case whose SHA differs from the one captured live (to test that the SHA placeholder generalizes, not just
  the one captured value) requires the test fixture's mocked head SHA to agree with (or share a prefix
  relationship with) the body's `Reviewed commit:` SHA, or the response fails to pin as terminal for a reason
  unrelated to the classifier under test.

The edge-case set below is a full replacement of every prior revision's set, renumbered from 1, because most
prior cases tested mechanisms (vocabulary excision, closed-grammar clause splitting, filler-token admission,
footer truncation) that no longer exist. Every construction that was ever found to cause a false `APPROVED`
across this plan's review history is retained below as a regression case (E13–E21, plus E23); the
boundary/shape cases for the final design are E3–E12 (each includes the complete footer where the case
asserts `approved`, since the template requires it); E22 describes the structural relationship between
`is_approved` and `is_blocking`; E24 tests footer-byte-level invariance.

| # | Input (verbatim) | Expected | Why it is an edge case |
| --- | --- | --- | --- |
| E1 | Real captured PR #1489 root comment, in full (with its real `<details>` footer) | approved | The anchor case: the one evidenced clean-response template, in its real, untruncated wire form |
| E2 | A real captured PR #1490 review body, in full | not approved | Confirms the generic review-submission wrapper — which carries no clean-signal text at all — correctly never matches; its verdict is (and remains) driven by the review `state` field, not this function (Decision 3) |
| E3 | `Codex Review: Didn't find any major issues.` (the real template's opening sentence, `Reviewed commit:` line and the complete real footer included, but **without** `Swish!`) | not approved | The template has no optional clauses (Decision 1/2): a response missing the evidenced flavor sentence does not reproduce the template, however close it looks — including when the rest of the body, footer included, is otherwise exact |
| E4 | The real template with a **different**, still-valid SHA (e.g. `deadf00d1234`, not the exact captured value) plus the complete real footer | approved | Confirms the SHA placeholder generalizes across values, not just the one literal value captured — this is what makes it a placeholder rather than a second hardcoded literal |
| E5 | The real template with a 6-character SHA plus the complete real footer | not approved | Below the `{7,40}` bound — verifies the lower edge of git's abbreviated-SHA range is enforced, not just documented |
| E6 | The real template with a 41-character SHA plus the complete real footer | not approved | Above the `{7,40}` bound — verifies the upper edge (one past a full SHA-1) is enforced |
| E7 | The real template with a 40-character (full-length) SHA plus the complete real footer | approved | Confirms the upper bound is inclusive, not an off-by-one exclusion of legitimate full-length SHAs |
| E8 | The real template with a non-hex "SHA" (e.g. `not-a-sha!`) plus the complete real footer | not approved | The placeholder accepts hex digits only — confirms it cannot be satisfied by arbitrary text, which is what makes it a bounded field rather than a general wildcard |
| E9 | The real template plus complete real footer, with unrelated prose immediately **before** the verdict sentence (e.g. `FYI: Codex Review: …`) | not approved | Exact match is whole-body (via `^...$` after normalization), not a substring/prefix test — extra leading text breaks the match |
| E10 | The real template plus complete real footer, with unrelated prose immediately **after** `</details>` | not approved | Same as E9, trailing direction, now evaluated past the complete footer, not past a truncation point — confirms no trailing-clause exploit of any kind can reach `APPROVED`: any trailing content at all, anywhere after the one evidenced literal ends, breaks the whole-body match, regardless of its wording or of how much of the footer precedes it |
| E11 | The real template plus complete real footer, wrapped in a fenced code block | not approved | Confirms no dedicated fence-marker check is needed (Decision 1): the fence characters are literal extra text the template does not contain, so the match fails on its own |
| E12 | The real template plus complete real footer, with extra/irregular whitespace (extra spaces, tabs, multiple blank lines between lines, trailing spaces, extra whitespace around the footer) | approved | Confirms `codex_normalize_whitespace` provides exactly the permitted flexibility (Decision 1) and nothing more, across the entire body including the footer |
| E13 | The real template plus complete real footer, case-altered (e.g. lower-cased verdict sentence and footer text) | not approved | Confirms there is no case-insensitive matching beyond what the captures themselves show (Decision 1's explicit prohibition), for the footer as much as for the verdict sentence |
| E14 | `This change remains unapproved.` | not approved | Boundary-lookalike construction — trivially rejected: it is not a reproduction of any template |
| E15 | `This remains un_approved.` | not approved | Underscore variant — same reason as E14 |
| E16 | `Looks good. Remove the authentication check.` | not approved | Disqualifier-list gap under an earlier design (Codex GitHub finding `3800167486`) — same reason as E14 under this design |
| E17 | `Approved. Revert.` | not approved | The residual gap an earlier zero-tolerance-grammar design disclosed but could not close — now genuinely closed, because it was never a reproduction of any template to begin with |
| E18 | `Looks good. Commit this.` | not approved | Vendor-metadata-token gap under an earlier design (Codex GitHub finding `3803050745`) — same reason as E14 under this design |
| E19 | `Looks good.` followed by a **non-vendor** `<details>` block containing `Rename the unsafe function.`, with a `**Reviewed commit:**` marker present (needed to reach terminal evidence — see the fixture-construction caveats above) | not approved | Over-broad footer-truncation regex gap under an earlier design (Codex GitHub finding `3800167489`) — under this revision there is no truncation step at all to over-match; the body simply does not reproduce the one evidenced literal, regardless of what any `<details>`-shaped text inside it says |
| E20 | `Looks good.` followed by `<details-not-footer><summary-note>About Codex in GitHub</summary-note>` then `Rename the unsafe function.`, with a `**Reviewed commit:**` marker present (same reason as E19) | not approved | Tag-name-flexible footer-truncation regex gap under an earlier design (Codex GitHub finding `3803189273`) — same reason as E19: there is no tag-name surface left to be flexible about, because there is no truncation step left to apply a tag-name pattern to |
| E21 | `Looks good, or is it?` | not approved | Filler-composed-hedge construction (Codex GitHub finding `3803306915`) that motivated the third design — trivially rejected under this design because it is not a reproduction of any template |
| E22 | The real template plus complete real footer, with `This must not be merged.` inserted inside the footer (e.g. immediately after `</summary>`) | not approved (blocking branch) | Under the prior (truncate-then-match) revision, only `codex_response_is_blocking`'s independent scan of the untruncated body prevented this body from reaching `APPROVED`. Under this revision, `is_approved` **alone** already returns `NEEDS_REVISION` for this body — inserting any text inside the footer breaks the whole-body exact match on its own. `is_blocking` (unchanged, Decision 4) still runs first at every verdict site and still independently recognizes the refusal, so the **composed** verdict is still the more specific blocking branch, but `is_blocking` is no longer load-bearing for preventing a false `APPROVED` here, only for verdict specificity (Decision 4/5) |
| E23 | The real template, followed by the footer's **opening line only** (not its complete text), followed by `Rename the unsafe function.` | not approved | The exact construction from Codex GitHub finding `3803545669` — the finding that motivated this revision. Under the prior revision this reproduced the *visible* (pre-truncation) template exactly and was classified `APPROVED`. Under this revision the required literal is the **complete** footer text, and a body carrying only its opening line does not reproduce that literal, so the match fails regardless of what follows the opening line |
| E24 | The real template plus complete real footer, with a single byte changed at each of three separate points **inside the footer body** (not its opening line): mid-sentence, immediately before `</details>`, and inside the settings URL | not approved (all three) | Confirms the entire footer is load-bearing for the match, not merely its opening line — a property the prior revision never needed and never tested, since only the opening line was ever compared against anything |

### Unit test mapping

There is one test file for this script: `scripts/development-workflow/tests/test-pr-review-loop.sh`. Each
edge case above must get at least one scenario there, driven through the real script with a mocked `gh` on
`PATH` (the harness convention already used throughout the file).

**Do not trust a name list of which scenarios already exist versus which are new** — this document has been
wrong about that before. Before writing any test code, derive the real status of each edge case's coverage
directly against the file (e.g. search for the construction's distinguishing text or an obviously-related
scenario name) and treat anything not found as needing to be authored — **this applies to all 24 cases, not
only the ones already flagged in a prior round** (Codex GitHub finding `3805497692`, P2: E2 was previously
missing from this document's coverage plan entirely, found only by walking the full E1–E24 list against the
real file end to end, not by a reviewer spotting it case by case). Apply the fixture-sourcing caveats from
"Edge-case enumeration" above when constructing each scenario: cases with a malformed or case-folded SHA
(E5, E6, E8, E13) must be built as review-sourced fixtures, not root-comment fixtures, or the scenario will
time out instead of exercising the classifier at all; E19 and E20 must include an explicit `**Reviewed
commit:**` marker in their bodies for the same reason; **E2 must also be review-sourced, for a different
reason than E5/E6/E8/E13 — it is naturally drawn from the reviews endpoint (Decision 3), and a review is
always terminal (`SOURCE = "review"`) by construction regardless of its body text, so this is the correct
source type to use rather than a caveat to work around.**

### Suppression semantics

Not applicable — the classifier recognizes no inline suppression or directive syntax, and this plan does not
introduce one.

---

## Concurrent-event-source addendum

Not applicable. `codex_response_is_approved` and its helpers are synchronous, pure string transformations
invoked from a single-threaded polling loop. No listeners, timers, async queues, or shared mutable state are
added; the only behavioral change from the prior revision is that there is no longer even a diagnostic write
to stderr (see the Code Samples note on why).

---

## Testing Strategy

**Test types**: Unit/behavioral (via `scripts/development-workflow/tests/test-pr-review-loop.sh`) plus a
manual smoke runbook.

**Command**: `bash scripts/development-workflow/tests/test-pr-review-loop.sh` — must exit 0 with all
assertions passing, on macOS (BSD tooling) and in CI (GNU tooling).

### Test disposition — method, not a frozen count

**This plan does not state exact scenario or assertion counts.** Every count this document has ever stated
about the existing test file — how many `codex_*` assertions exist, how many assert `VERDICT: APPROVED`, how
many scenarios belong to which group — has needed correction in a later review round, because the number is a
property of the file at one moment in time and the file changes (including as a direct result of this plan's
own instructions). Stating the method to derive a number, and the rule for reconciling it, is durable; stating
the number itself is not. Every group below must be derived by **direct enumeration against the real file at
implementation time**, and every group's membership must sum to the real total exactly — if it does not, the
enumeration is wrong somewhere; the total is never used to derive a group's size by subtraction, because it
contains categories a subtraction could silently sweep in.

**The four groups, and the enumeration command for each:**

- **Group APPROVED** — scenarios that assert `VERDICT: APPROVED` and correctly continue to, because their body
  is (or is updated to be) an exact reproduction of a `CODEX_APPROVED_TEMPLATES` entry. Two real, existing
  scenarios currently assert `VERDICT: APPROVED`. **Their real, current bodies read `Codex Review: Didn't find
  any major issues.` followed directly by the `**Reviewed commit:**` SHA marker — no `Swish!` sentence and no
  footer at all** (corrected this round from a false "verdict sentence and SHA but no footer" description,
  Codex GitHub finding `3805497682`, P2 — confirmed via `grep -c 'Swish' test-pr-review-loop.sh`, which returns
  0). Both need a **full body replacement** with the complete template text (the `Swish!` sentence included)
  plus the complete, verbatim vendor footer — appending only the footer to the current body would leave the
  verdict sentence short of the template and the retained `APPROVED` assertion would fail. Beyond those two,
  this plan adds new scenarios to cover the boundary cases in "New scenarios" below (E1, E7, E12).
  **A further subset of the scenarios that currently assert `VERDICT: APPROVED` belongs in this group too, not
  in Group RETARGETED, even though their body does not reproduce a template** (Codex GitHub finding
  `3805127030`, P2). Retargeting is only correct for a scenario whose assertion is really about approval
  *vocabulary* — whether particular wording, negation, or quoting classifies as clean under the old block-list
  design. A scenario whose assertion is about verdict *routing* (which verdict site resolves it, and under what
  timing/evidence-priority conditions) merely uses an approving body incidentally; retargeting it would delete
  the only coverage for the routing behavior it exists to test, and the routing behavior itself is unaffected
  by this plan. Determine which is which by reading what each scenario's mock sequencing actually exercises —
  not by its name — and treat a scenario as routing, not vocabulary, if it does at least one of: resolve only
  after multiple poll iterations or an async-grace re-check (not on the first evaluation), or assert priority
  between two competing evidence sources (a review versus a reaction, an environment error, or a stale/older
  review) rather than testing whether one body's wording alone is approving. Six such scenarios were found this
  round, each testing routing at a specific verdict site — keep every one asserting `VERDICT: APPROVED`. **Their
  current bodies use different wording than the template entirely (e.g. `"No blocking issues found."`), so this
  is a full body replacement with the exact template's verdict sentence, `**Reviewed commit:**` marker, and
  complete footer** — the same full-replacement treatment the two pre-existing Group APPROVED members also
  need (see above), each for its own reason — while preserving each scenario's distinguishing mock sequencing
  (the poll timing or competing-evidence setup that makes it a routing test, not just its final review/comment
  payload). Do not touch any of these six scenarios' paired `*_exit_clean` assertions (each correctly stays
  `"0"`, unaffected):
  - `codex_reaction_with_current_review` — a current-head review resolves `APPROVED` despite a simultaneous
    reaction-bearing ancillary comment; confirms the review, not the reaction/acknowledgement noise, wins.
    Resolves at the main-loop verdict site.
  - `codex_reaction_then_late_review` — a review arriving on a later main-loop poll iteration (after an
    earlier iteration saw only a reaction) still resolves `APPROVED`. Resolves at the main-loop verdict site.
  - `codex_async_reaction_then_late_review` — a review arriving only after the async-grace re-check that
    follows a detected reaction still resolves `APPROVED`. Resolves at the async-reaction-final verdict site —
    this is the only scenario in the entire suite that exercises that site's positive path.
  - `codex_main_loop_env_then_newer_review_supersedes` — a strictly newer review supersedes a previously
    recorded, now-stale environment error within the same poll. Resolves at the main-loop verdict site.
  - `codex_latest_current_review` — when multiple reviews are returned, the one at the latest timestamp is
    selected and resolves `APPROVED`, not an earlier, non-clean one. Resolves at the main-loop verdict site.
  - `codex_environment_with_current_review` — a current review resolves `APPROVED` despite a simultaneous
    environment-error notice; confirms evidence-priority, not the environment notice, decides the verdict.
    Resolves at the main-loop verdict site.

  **Verdict-site coverage after this split**: the main-loop verdict site retains multiple positive-path
  assertions (the five scenarios above plus Group APPROVED's own two members); the async-reaction-final site
  retains exactly one (`codex_async_reaction_then_late_review`). **The async-arrival and async-final verdict
  sites have no positive-path (`VERDICT: APPROVED`) assertion in the suite today, independent of this plan or
  of this split** — reproduced by running every `VERDICT: APPROVED`-asserting scenario in the current suite and
  observing which verdict site's `INFO:` trace resolves it; none reaches those two sites before a review or
  comment arrives. This is a pre-existing gap, not something this plan's retargeting creates or could fix by
  retargeting decisions alone, and adding new coverage for it is out of scope for this correction — noted here
  so an implementer does not assume the four sites are symmetrically covered.
- **Group RETARGETED** — every other real, existing scenario that currently asserts `VERDICT: APPROVED` — that
  is, every scenario in the enumeration below **except** the two Group APPROVED members and the six
  routing-testing scenarios named above. Enumerate with `grep 'run_test "codex_' test-pr-review-loop.sh | grep
  'VERDICT: APPROVED'`, remove those eight, and read each remaining scenario's body directly (not by name
  pattern) to confirm it is a vocabulary-classification test with no multi-poll or evidence-priority behavior
  of its own — everything left does not reproduce `CODEX_APPROVED_TEMPLATES`' one entry and must retarget to
  `VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)`. **Two known scenarios in this group are
  SIGPIPE-safety fixtures** whose long bodies begin with pre-plan block-list-matching text (`No blocking issues
  found.` / `Codex Review: Didn't find any major issues.` followed by ~200,000 filler characters) — these are
  vocabulary-matching artifacts, not routing tests (single-shot, no poll sequencing), and must retarget along
  with every other member of this group; do not leave them classified as already-`NEEDS_REVISION` without
  checking their real, current disposition first.
  **One scenario in this group has a competing evidence fixture whose priority, not just its own body,
  determines the scenario's regression-detection value** (Codex GitHub finding `3805611400`, P2) —
  `codex_usage_limit_topic_mention_not_quota` mocks both a review (body mentioning "Codex usage limit" only as
  a topic, not an actual quota message) and a SHA-pinned root comment (currently a bare, old-vocabulary clean
  body) at the same timestamp, and relies on `codex_response_priority`'s tie-break to prove the review's
  topic-mention is not misclassified: the scenario passes only if the correctly-classified evidence source
  wins the tie regardless of what the other side is. `codex_response_priority` ranks an unrecognized body at
  priority 2 — **above** usage-limit's priority 1 — so once retargeting leaves the root comment's body an
  unrecognized (non-template) shape, it would win the tie against a misclassified usage-limit review by
  coincidence of tier ordering, not because the review was correctly classified, silently absorbing the exact
  regression the scenario exists to catch. **The competing root-comment fixture must also be updated to the
  new exact template** (not merely retargeted), so it stays classified at priority 0 and the tie remains
  decided by whether the review is correctly classified, not by both sides collapsing into the same
  unrecognized tier. Verified this round by mutation: with the root comment left as its old body, a review
  falsely classified as usage-limit (reverting `codex_response_is_usage_limit`'s third alternative to its
  historical, unguarded pre-fix form) still produces the expected `NEEDS_REVISION` — the regression is not
  caught. With the root comment updated to the new template, the same mutation produces `VERDICT: UNAVAILABLE`
  instead of the expected `NEEDS_REVISION` — caught. **Checked all 18 other Group RETARGETED scenarios for the
  same property this round**: every one of them mocks exactly one non-empty evidence source (the other endpoint
  returns `[]`), confirmed by reading each scenario's mock directly — none has a competing-fixture dependency,
  so none needs this treatment.
  **Every scenario in this group has a paired `*_exit_clean` assertion** (a second `run_test` line, named
  `<scenario>_exit_clean`, checking the scenario's exit code independently of its verdict string) that
  currently expects exit `0` and must retarget to `1` in the same commit, because `VERDICT: NEEDS_REVISION`
  exits 1, not 0. Enumerate these with `grep '_exit_clean"' test-pr-review-loop.sh` and pair each by name with
  its scenario; do not assume a `*_exit_clean` assertion is part of the "untouched, non-verdict" bucket just
  because it carries no `VERDICT:` string — whether it is untouched depends on whether its paired scenario is
  retargeting, not on its own text. **A scenario kept in Group APPROVED per the split above (including the six
  routing-testing scenarios) is not in this group, and its paired `*_exit_clean` assertion does not retarget
  either** — the exit-clean/verdict pairing tracks the scenario's real group membership, not its former
  candidacy. Also rename any scenario whose name now asserts the opposite of its expectation (suffixes like
  `…_stays_approved_…`) in the same commit that retargets it, so the name and expectation never disagree on
  `develop`.
- **Group UNCHANGED-NEEDS_REVISION** — every real scenario that already asserts `VERDICT: NEEDS_REVISION` and
  stays that way. Enumerate with `grep 'run_test "codex_' test-pr-review-loop.sh | grep -c 'VERDICT:
  NEEDS_REVISION'`. None of these bodies has ever reproduced, or now reproduces, the evidenced whole-body
  template — this follows from the same asymmetry Decision 2 establishes (the new design is a strict subset of
  what every prior, more permissive design accepted), not from re-inspecting every body individually. Every
  scenario's explanatory comment must still be rewritten if it currently describes a now-deleted mechanism (a
  disqualifier match, a closed-grammar clause, a fence-marker check) as the reason it passes; under this
  revision, it passes because the body is simply not an exact template reproduction. Scenarios already testing
  `codex_response_is_blocking` specifically are wholly unaffected: that function did not change (Decision 4).
- **Group UNTOUCHED** — every other `codex_*` assertion: exit codes, reason strings, counts, and the four
  `VERDICT: UNAVAILABLE`/`VERDICT: TIMED_OUT` assertions that test evidence-priority/availability routing, not
  approval-content classification. **Excludes** any `*_exit_clean` assertion paired with a Group RETARGETED
  scenario (see above) — membership in "carries no `VERDICT:` string" is not the same claim as "unaffected by
  this plan." Enumerate the non-verdict portion with `grep 'run_test "codex_' test-pr-review-loop.sh | grep -vc
  'VERDICT:'`, then subtract the Group-RETARGETED-paired `*_exit_clean` count (a same-superset subtraction,
  not a heterogeneous one, so it is safe) to get this group's real non-verdict membership; add the 4
  availability/timeout assertions. Everything in this group neither approves nor depends on approval-content
  parsing, and must pass unchanged; any failure among them is a genuine regression, not an intended contract
  change.

**Reconciliation rule, and exactly when it applies (Codex GitHub finding `3805404998`, P2 — corrects a timing
bug in the prior round's own fix).** Both equations below are a **pre-edit classification check**: they prove
the group split (which scenario belongs to Group APPROVED versus Group RETARGETED) is exhaustive and correct
against the file **exactly as it stands before any scenario in this stage is edited** — before any Group
APPROVED body is updated and before any Group RETARGETED scenario is retargeted. **Run them first, before
touching any scenario body or assertion; do not run them after retargeting.** The prior round's fix moved the
*Verify* step to after the edits, which is wrong for the same reason this round's finding identifies: once
Group RETARGETED's scenarios are retargeted, the file's current `VERDICT: APPROVED` count drops from the
pre-edit total to Group APPROVED's count alone (both correctly, by design), so an equation that greps the
*current* `VERDICT: APPROVED` count and expects it to still include Group RETARGETED's members can never
balance post-edit. Grepping before any edit avoids this entirely: at that moment, every Group RETARGETED
candidate still genuinely asserts `VERDICT: APPROVED` in the file, so the count these equations check against
is the same one the group split was derived from.

Group APPROVED's real (pre-existing) verdict-string members — now including the routing-testing scenarios kept
in that group per the split above, not only the two template-anchored ones — plus Group RETARGETED's
verdict-string members must equal the total `VERDICT: APPROVED` count **read from the file before any edit in
this stage**. **A second, independent equation must also hold, read from the same pre-edit file, and must
include every group, Group APPROVED included** (Codex GitHub finding `3805127037`, P2 — an earlier revision of
this equation omitted Group APPROVED's real, pre-existing verdict-string members entirely, so the listed terms
summed short of the total by exactly that many): Group APPROVED's real (pre-existing) verdict-string members +
Group RETARGETED's verdict-string members + Group UNCHANGED-NEEDS_REVISION + Group UNTOUCHED's
availability/timeout members + Group UNTOUCHED's non-verdict members + Group RETARGETED's paired
`*_exit_clean` members must equal the total `codex_*` assertion count **read from the same pre-edit file**,
with every real assertion counted in exactly one group. (This second equation's terms are all membership
counts — how many assertions belong to each group — not "what value each currently asserts," so it is in fact
timing-invariant and would also hold after editing; it is stated as pre-edit here only so both equations share
one unambiguous checkpoint, not because it individually requires it.) **Group APPROVED's own paired
`*_exit_clean` members are not a separate term** — they stay `"0"`, unaffected, and are already inside Group
UNTOUCHED's non-verdict count (only Group RETARGETED's paired `*_exit_clean` members are excluded from that
count, per Group UNTOUCHED's definition above). If the sum does not match the total, re-derive rather than
adjusting either number to force agreement — this is exactly the failure mode every reconciliation finding so
far has identified: a term silently missing from the list, or an equation asserted against a different file
state than the one it describes — never a wrong arithmetic operation.

**After the edits are applied, a different, simpler check confirms they landed correctly — do not re-run the
equations above against the post-edit file; their premise (Group RETARGETED still asserting `APPROVED`) is no
longer true by design at that point.** Confirm by name: every scenario classified as Group RETARGETED now
reads `VERDICT: NEEDS_REVISION` and `"1"` for its paired `*_exit_clean` assertion; every scenario classified as
Group APPROVED (both the two template-anchored members and the routing-testing members kept in that group)
still reads `VERDICT: APPROVED`; and the full test suite exits 0. This is a membership-correctness check, not
a count reconciliation — the post-edit `VERDICT: APPROVED` count is *expected* to equal Group APPROVED's count
alone at this point, not the pre-edit total.

**Post-addition check, separate from the equation above.** After "New scenarios" are added, the `codex_*`
total necessarily grows — the equation above is not re-applied at this point, because none of its terms
account for new assertions. Instead, confirm the growth is accounted for exactly: `grep -c 'run_test "codex_'
test-pr-review-loop.sh` immediately before adding new scenarios, the same count immediately after, and the
count of `run_test` lines actually added for the scenarios named in "New scenarios" (e.g. via `git diff
--stat` on the test file, or by counting the new scenarios' own `run_test` invocations directly) — the
after-total minus the before-total must equal that count exactly, with every new assertion belonging to a
scenario named in "New scenarios," none elsewhere.

**A scenario that was never implemented**: an earlier revision of this document described a
`codex_disqualifier_diagnostic_emitted` scenario as scheduled for deletion. It is not, and has never been, in
the repository — no revision of this plan has ever been implemented, so there is no stderr-diagnostic-emitted
test to delete. Confirm this directly (a name search for the scenario returns nothing) before assuming any
deletion work is needed here.

### New scenarios

**Every edge case in the Parser-risk addendum (E1–E24) must have an automated scenario — confirmed this round
by walking the full E1–E24 list against the real file, not case by case as reviewers happened to spot gaps**
(Codex GitHub finding `3805497692`, P2). Two cases were not previously accounted for correctly:

- **E2 was missing from this list entirely** — a repository-wide search for its distinguishing text (`Here are
  some automated review suggestions`, `💡`) returns zero matches, and the prior list jumped from E1 straight to
  E3. Added below.
- **E4 and E14 are genuinely covered, but only implicitly** — neither needed a new scenario (E4 by the two
  updated Group APPROVED members using distinct SHAs, per "Test disposition"; E14 by the real, pre-existing
  `codex_unapproved_prefix_root_comment`, confirmed present and matching E14's construction), but this
  document did not say so anywhere after removing the old per-case mapping table, leaving their coverage
  unstated rather than confirmed. Stated explicitly below so no case is left ambiguous between "new," "covered
  by an existing scenario," and "not covered at all."

The following must be authored (construction notes only — see the Parser-risk addendum for each edge case's
full rationale and the fixture-sourcing caveats):

- **E1** — the real captured PR #1489 body, in full, including its real `<details>` footer. `APPROVED`. This is
  the classifier's primary real-response anchor and the highest-priority addition in this set.
- **E2** — a real captured PR #1490 review body, in full, verbatim. `NEEDS_REVISION`. **Must be a review-sourced
  fixture** (mocked `commit_id` equal to the current head SHA, `state: COMMENTED`) — the same requirement that
  applies to E5/E6/E8/E13, since a review is always terminal (`SOURCE = "review"`) by construction regardless
  of its body text, and this case specifically needs to reach `is_approved` (and fail it, on wording alone) to
  prove the generic wrapper is correctly never a template match, not merely to reach a safe-fail for an
  unrelated reason (e.g. never pinning as terminal at all).
- **E3, E5, E6, E8, E9, E10, E11, E13** — each a `NEEDS_REVISION`-asserting boundary/shape construction per its
  Parser-risk addendum row, each including the complete real footer (required for the case to isolate what it
  is meant to test). E5, E6, E8, and E13 must be review-sourced fixtures (see the fixture-sourcing caveats).
- **E7** — `APPROVED`, the real template with a full-length (40-character) SHA plus the complete real footer.
- **E12** — `APPROVED`, the real template with irregular whitespace around the complete real footer.
- **E15, E16, E18, E19, E20** — each a `NEEDS_REVISION`-asserting construction per its Parser-risk addendum row.
  E19 and E20 must include an explicit `**Reviewed commit:**` marker (see the fixture-sourcing caveats).
- **E17, E21** — `NEEDS_REVISION`-asserting regression constructions per their Parser-risk addendum rows.
- **E22** — `NEEDS_REVISION` (blocking branch); verifies the structural relationship between `is_approved` and
  `is_blocking` described in that row.
- **E23** — `NEEDS_REVISION`; the direct regression test for Codex GitHub finding `3803545669`.
- **E24** — `NEEDS_REVISION` for all three footer-position mutations; may be implemented as one scenario with
  three assertions or three separate scenarios.

**Not authored as new scenarios, because coverage already exists (confirmed this round, not assumed):**

- **E4** — covered by the two Group APPROVED template-anchored members once their body-replacement fix (see
  "Test disposition") is applied: each already uses a different, valid SHA (`abcdefab12` and
  `abcabcabcabc1234567890`, neither the live-captured value), so once their bodies reproduce the complete
  template the SHA-generalization case is exercised as a side effect of retaining those two distinct values —
  no separate scenario is needed.
- **E14** — covered by the real, pre-existing `codex_unapproved_prefix_root_comment` (confirmed present via a
  direct search of the file this round; its body, `"This change remains unapproved pending further work."`,
  reproduces E14's boundary-lookalike construction). This scenario is in Group UNCHANGED-NEEDS_REVISION and
  needs only its explanatory comment refreshed, per that group's instructions in "Test disposition" — no new
  scenario or body change.

**Four scenarios routing a terminal, footer-bearing near-miss through each of Decision 6's four verdict sites**
(Codex GitHub finding `3805277351`, P2). Decision 6 duplicates the same acknowledgement gate at four separate
call sites in the production script; requiring only one scenario per edge case does not confirm all four
copies are correct, since a single scenario resolves at whichever site its mock sequencing happens to reach —
by default, the main-loop site. A gate that is missing or mistyped at any one of the other three sites still
lets the affected scenario pass (`VERDICT: NEEDS_REVISION`, exit 1) if it resolves at a different site, and
the regression it reintroduces (a footer-bearing near-miss timing out instead of safe-failing) is a real
production gap the round-11 P1 finding already showed is easy to reach. Each of the four scenarios below uses
the same near-miss body (the E3 construction — missing `Swish!`, complete real footer, SHA-pinned) and differs
only in mock sequencing, so that each resolves at a different, named site — reproduced this round by execution
against the real script:

- `codex_footer_near_miss_main_loop_safe_fails` — the near-miss body is present on the first poll (a SHA-pinned
  root comment returned immediately). Resolves at the **main-loop** verdict site. `NEEDS_REVISION`, exit 1.
- `codex_footer_near_miss_async_arrival_safe_fails` — the main poll loop's own comment fetches return empty for
  its entire budget; the near-miss body appears only on the single async-grace poll that follows. Resolves at
  the **async-arrival** verdict site. `NEEDS_REVISION`, exit 1.
- `codex_footer_near_miss_async_final_safe_fails` — the main poll loop returns empty; the first async-grace
  poll finds only a bare acknowledgement comment (the footer's acknowledgement sentence alone, with no
  `**Reviewed commit:**` marker — non-terminal, so it cannot resolve the verdict on its own); this triggers the
  one-shot sleep-and-recheck, and the near-miss body appears only on that second check. Resolves at the
  **async-final** verdict site. `NEEDS_REVISION`, exit 1.
- `codex_footer_near_miss_async_reaction_final_safe_fails` — a thumbs-up reaction is present on the trigger
  comment from the first poll onward, and every comment fetch returns empty until the final check that follows
  the reaction-triggered sleep, where the near-miss body appears. Resolves at the **async-reaction-final**
  verdict site — the same site `codex_async_reaction_then_late_review` (Group APPROVED) exercises for the
  positive path; this scenario is its negative-path counterpart. `NEEDS_REVISION`, exit 1.

**Verified this round, not asserted**: patched a copy of the real production script with Decision 6's fix
applied and ran all four constructions — each correctly resolves `NEEDS_REVISION`, exit 1, with an `INFO:`
trace confirming which site fired (`bot response detected` / `async-arrival bot response detected during
grace period` / `final async bot response detected after acknowledgement wait` / `final async reaction bot
response detected`, respectively). Reverting Decision 6's gate at all four sites simultaneously makes all four
constructions instead time out. Reverting the gate at **only** the async-final site — leaving the other three
correct — makes only the async-final construction time out, while the other three still correctly resolve
`NEEDS_REVISION`; this confirms the four scenarios are independently diagnostic, not incidentally passing
together. This is the intended proof: a missed or mistyped gate at any one site is caught by exactly that
site's scenario.

Before authoring any of the above, re-check whether an equivalent scenario already exists under a different
name — do not assume absence without searching the real file first (this document has previously assumed
scenarios existed, or did not exist, incorrectly in both directions).

### New scenarios addendum — flavor-token enumeration (Decision 2 Addendum, superseded — kept for history)

**This addendum's own 14 `codex_flavor_*` scenarios no longer exist in the shipped test file** — they were
deleted along with the alternation they tested, and replaced by the `codex_placeholder_*` scenarios in the next
addendum below, once the alternation itself was replaced by a bounded placeholder (Decision 2 Second Addendum).
This section is left in place, unedited, as the historical record of what was tried and superseded; do not
treat it as a description of the current test file's contents.

### New scenarios addendum — bounded flavor placeholder (Decision 2 Second Addendum, PR #1494 follow-up)

Eighteen scenarios (38 assertions) cover the bounded placeholder that replaced the 14-token alternation <!-- markdown-heuristic-disable COUNT001 --> (the count is a direct sum of this list's items — the "one scenario per remaining evidenced token" bullet below represents 12 of the 18, not 1, since listing all 12 individually would duplicate the earlier per-token table in the first addendum):

- **`codex_placeholder_rocket_real_pr1494_capture_approved`** — the real, live PR #1494 root comment (comment
  id `5333550055`) that originally falsified the single-literal assumption, verbatim, same real-capture
  convention as `codex_e1_real_pr1489_capture_approved`. `APPROVED`.
- **One scenario per remaining evidenced token** (`Nice work!`, `Chef's kiss.`, `You're on a roll.`, `:tada:`,
  `Another round soon, please!`, `:+1:`, `Bravo.`, `Keep it up!`, `Delightful!`, `Keep them coming!`, `Can't
  wait for the next one!`, `More of your lovely PRs please.`) — a synthetic body reproducing that token in the
  otherwise-exact template, each with its own valid SHA. `APPROVED`. (`Swish!` itself remains covered by
  `codex_e1_real_pr1489_capture_approved`, unchanged.)
- **`codex_placeholder_unevidenced_flavor_now_approved`** — the same previously-unevidenced token
  (`Fantastic job!`) the first addendum's negative test used, now asserting `APPROVED` instead of
  `NEEDS_REVISION`. This is the direct proof of the design's behavior change, not incidental coverage.
- **`codex_placeholder_exactly_cap_length_approved`** — a 40-character flavor slot (the cap, inclusive).
  `APPROVED`. Confirms the upper bound is inclusive, matching the SHA field's own inclusive-bound precedent
  (`codex_e7_full_length_sha_approved`).
- **`codex_placeholder_exceeds_length_cap_not_approved`** — a 41-character flavor slot. `NEEDS_REVISION`.
  Confirms the length cap is enforced, not merely documented.
- **`codex_placeholder_asterisk_not_approved`** — a flavor slot containing `*`. `NEEDS_REVISION`. Confirms the
  excluded-character set protects the `**Reviewed commit:**` bold-marker syntax immediately following the slot.
- **`codex_placeholder_backtick_not_approved`** — a flavor slot containing a backtick. `NEEDS_REVISION`.
  Confirms the excluded-character set protects the backtick-delimited SHA field that follows.
- **`codex_placeholder_newline_separated_overflow_not_approved`** — a paragraph break (blank line) inside the
  flavor position followed by an extra sentence. `NEEDS_REVISION`. Confirms the length cap still catches
  content smuggled in via a newline-separated injection vector, once whitespace normalization (Decision 1,
  unchanged) collapses the break to a single space and the flattened text exceeds 40 characters — a distinct
  injection vector from the same-line overflow case above, not a redundant restatement of it.
- **A raw-literal-newline check against the regex directly, verified out of band, not shipped as a `run_test`
  entry**: confirmed the `[:cntrl:]` exclusion rejects a genuine (non-escaped) newline byte in the flavor
  position when matched against the pattern without whitespace normalization applied first. This is currently
  unreachable through the composed production pipeline (normalization always runs first inside
  `codex_response_is_approved`), so it is not added as a shipped end-to-end scenario — doing so would test an
  isolated regex property, not a reachable composed-chain behavior, and Decision 6's standing rule discourages
  isolated-function assertions as a substitute for composed-chain verification. It is recorded here as
  supplementary evidence that the character-class exclusion is correctly encoded, not merely assumed correct
  because normalization happens to make it unreachable.

### Residual verification strategy


This is a full design replacement, so the evidence the implementation must produce before
`ready-for-human-review` is:

1. A full `bash scripts/development-workflow/tests/test-pr-review-loop.sh` run exiting 0, with the real,
   current total assertion count reported (not a count carried forward from this document).
2. A reconciliation statement in the PR description naming, individually, every scenario in Group APPROVED,
   Group RETARGETED, and "New scenarios" — derived fresh via the "Test disposition" method, not assumed from
   this document's prose. No scenario outside these buckets may change disposition; any that does is a genuine
   regression, not an intended part of this contract change.
3. Confirmation that the real captured PR #1489 body approves end-to-end, through the real script — not just
   via the illustrative snippet in this plan. This is the single highest-impact check: a classifier that
   rejects the one thing it must accept is a total operational failure of the ready phase.
4. Confirmation that real, freshly re-fetched PR #1490 review bodies still correctly return `NEEDS_REVISION`
   (or, for any with `state == "CHANGES_REQUESTED"`, are still routed to the blocking short-circuit unaffected
   by this function) — re-fetch live, do not rely on bodies captured during any prior review round, since the
   whole point of exact-template matching is that it is sensitive to exactly this kind of drift.
5. Confirmation that every construction in the Parser-risk addendum (E14 through E24) still returns
   `NEEDS_REVISION` against the real script, not just an illustrative prototype. E23 specifically re-verifies
   Codex GitHub finding `3803545669` is closed.
6. Confirmation that a one-byte mutation anywhere inside the footer (E24) still returns `NEEDS_REVISION`,
   proving the entire footer text is load-bearing for the match.
7. Confirmation that `codex_response_is_blocking`'s own test coverage (unaffected by this revision, per
   Decision 4) still passes, and specifically that the new E22 scenario resolves to the blocking branch — the
   one remaining case where `is_approved`'s own rejection and `is_blocking`'s independent recognition compose.
8. Every footer-bearing edge case in the Parser-risk addendum run through the real, composed verdict chain
   (Decision 6) — confirm none of them produces `VERDICT: TIMED_OUT`. **In addition, and specifically**, the
   four verdict-site near-miss scenarios in "New scenarios" must each be confirmed to resolve at their named
   site (via the `INFO:` trace) and to produce `NEEDS_REVISION`, not `VERDICT: TIMED_OUT` — one hand-edited
   copy of Decision 6's gate per site is exactly where a typo survives passing tests, so a single edge-case
   scenario resolving at one site by default is not evidence the other three copies are correct.
9. **Before marking any "exists"/"kept"/"unchanged" claim in this document verified, re-derive it by execution
   against the file at implementation time**, not against this document's prose.
10. **(Decision 2 Second Addendum, PR #1494 follow-up) Every evidenced flavor token still approves under the
    bounded placeholder, a previously-unevidenced token now approves too (the intended behavior change), and
    the placeholder's three guards are each independently proven**: a slot containing `*` safe-fails, a slot
    containing a backtick safe-fails, a slot exceeding the 40-character cap safe-fails (with the boundary case
    of exactly 40 characters still approving), and a slot exceeding the cap via a newline-separated injection
    vector still safe-fails once normalization flattens it — confirmed by execution against the real, composed
    chain, not asserted from the pattern's appearance alone.

### Planted-violation proof (REVIEW.md Verification Discipline; PR #1494 review finding `3808305143`)

`REVIEW.md`'s Verification Discipline rule requires, for any PR that materially modifies an automated check —
this classifier and its Decision 6 gate both qualify — a demonstrated run at a concrete file and line showing
the check fails with the targeted violation present and passes once it is removed, in both directions, not a
description. Codex GitHub finding `3808305143` (P1) correctly identified that the evidence posted for this PR
did not meet that bar: it described gate-revert experiments in prose without naming file:line or pasting both
runs' actual output. The full transcripts (mutation, failing-run output, restoration, passing-run output) for
every materially modified check are posted as a PR #1494 comment and are the authoritative record; this section
indexes what each transcript covers and what it found, so the proof is discoverable from the plan, not only
from a comment that could scroll out of view.

**Decision 6 acknowledgement gate — all four verdict sites, each with its own full transcript (not one
transcript generalized to the other three):**

- Main-loop, `codex-github-reviewer.sh:1605` — mutation removes the `[ SOURCE != "review" ]` condition,
  reverting to the unconditional pre-Decision-6 form. Caught by `codex_footer_near_miss_main_loop_safe_fails`.
  **This transcript also found and fixed a real, pre-existing test-isolation gap**: the scenario's mock
  originally returned the near-miss body on every poll call, so a broken main-loop gate was silently rescued by
  the still-correct async-arrival gate one site later, and the mutation produced no detectable failure at all
  on first attempt. Fixed by making the mock call-counted (near-miss body only on call 2, the main poll loop's
  own check; empty on calls 3+), matching the isolation convention the other three sites' mocks already used —
  after the fix, the same mutation is correctly caught.
- Async-arrival, `codex-github-reviewer.sh:1823` — same mutation shape. Caught by
  `codex_footer_near_miss_async_arrival_safe_fails`. **Same rescue gap found and fixed**: the mock originally
  kept returning the near-miss body from call 3 onward (`-ge 3`), letting async-final rescue a broken
  async-arrival gate; tightened to `-eq 3` (near-miss body only on call 3; empty on calls 4+).
- Async-final, `codex-github-reviewer.sh:1929` — mutation removes the `[ SOURCE = "review" ] ||` disjunct from
  the negated-form gate, reverting to the unconditional `! grep` pre-Decision-6 form. Caught by
  `codex_footer_near_miss_async_final_safe_fails`. This scenario's mock was already properly isolated (no
  rescue possible — async-final is the terminal site for its own construction's branch).
- Async-reaction-final, `codex-github-reviewer.sh:2081` — same negated-form mutation shape. Caught by
  `codex_footer_near_miss_async_reaction_final_safe_fails`. Also already properly isolated for the same
  structural reason (terminal site for the reaction-detected branch).

**Whole-body exact-match classifier (`codex_response_is_approved`, the array element cited at
`codex-github-reviewer.sh:759` in the finding, template literal at `codex-github-reviewer.sh:737`)** — mutation
removes the trailing `$` anchor from `CODEX_APPROVED_TEMPLATES`' one entry, reopening the "extra trailing
content" gap Decision 1 exists to close. Caught by `codex_e10_trailing_prose_not_approved`, which produces a
false `VERDICT: APPROVED` with the violation present.

**Bounded flavor placeholder (`codex-github-reviewer.sh:737`)** — mutation removes `*` from the placeholder's
excluded-character class (`[^*`[:cntrl:]]{1,40}` → `[^`[:cntrl:]]{1,40}`). Caught by
`codex_placeholder_asterisk_not_approved`, which also produces a false `VERDICT: APPROVED` with the violation
present.

**Not re-proven (exemption, `REVIEW.md:324`): the SHA field's `[0-9a-f]{7,40}` bound and the complete footer
literal.** Neither was modified by this PR's diff — the SHA bound is unchanged from the version this plan's
E5/E6/E7/E8 scenarios already proved (Decision 2's original implementation), and the footer literal is
byte-identical to the version E9–E11/E24 already proved. Carrying an already-proven check unmodified is a pure
refactor with no behavior change on that surface, so re-proof is exempt per `REVIEW.md:324`; this exemption is
stated explicitly rather than silently omitting the proof.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Real Codex clean root comment | Body captured from PR #1489: `Codex Review: Didn't find any major issues. Swish!`, a `**Reviewed commit:**` marker matching the fixture head SHA, and the full `<details>` "About Codex in GitHub" footer including its bulleted list | `scripts/development-workflow/tests/test-pr-review-loop.sh` (E1's scenario — see "New scenarios") |
| Real Codex review-wrapper body (no clean signal) | Any body captured from PR #1490's review history, verbatim | `scripts/development-workflow/tests/test-pr-review-loop.sh` (E2's scenario) |
| Footer-with-refusal variant | The real PR #1489 body with `This must not be merged.` inserted inside the `<details>` block | `scripts/development-workflow/tests/test-pr-review-loop.sh` (E22's scenario) |
| Footer-opening-line-only-plus-trailer variant (regression for finding `3803545669`) | The real approved template, followed by only the footer's opening line (not its complete text), followed by `Rename the unsafe function.` | `scripts/development-workflow/tests/test-pr-review-loop.sh` (E23's scenario) |

Capture the real bodies with:

<!-- workflow-shell-contract: bash -->

```bash
gh api repos/lhpaul/ai-dev-framework-template/issues/1489/comments \
  --jq '.[] | select(.user.login | test("codex"; "i")) | .body'
gh api repos/lhpaul/ai-dev-framework-template/pulls/1490/reviews \
  --jq '.[] | select(.user.login | test("codex"; "i")) | .body'
```

Escape for the existing `jq -nc` / `printf` mock convention already used by the neighbouring scenarios; do not
add a fixture file, as the harness is deliberately self-contained. **If either capture no longer matches the
shape recorded in the Cross-Cutting Operational Assumption Check, stop and report it before writing any code**
— Implementation Order step 1 requires this re-check, and a drifted capture changes what
`CODEX_APPROVED_TEMPLATES` must contain.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/codex-github.md` — **replace** any existing "Verdict
      classification" section with one stating that `APPROVED` requires the response — the **entire,
      untruncated** body, whitespace-normalized — to be an **exact** match against one of a small set of
      literal templates captured from real Codex clean responses, each template including the complete vendor
      `<details>` footer text — currently exactly one template, covering the `Codex Review: Didn't find any
      major issues. Swish!` / `**Reviewed commit:**` shape plus the complete "About Codex in GitHub" footer,
      with a bounded placeholder only for the commit SHA. State plainly that there is no vocabulary list, no
      grammar, no truncation step, and no case-insensitive or punctuation-tolerant matching, and that adding a
      template is the only way to widen the approval surface and needs a live capture plus the same review a
      `CODEX_CLEAN_SIGNAL_PATTERN` change once required. Note the deliberate, disclosed trade: a genuinely
      clean response using different wording anywhere in the body — including the vendor footer — safe-fails
      to `NEEDS_REVISION` today.
- [ ] **(Decision 2 Second Addendum, PR #1494 follow-up — supersedes the item above)** Update the same
      section to state that the flavor slot between the verdict sentence and the `Reviewed commit:` marker is
      a **single bounded placeholder** (``[^*`[:cntrl:]]{1,40}``), not an enumeration and not a single literal —
      state the length cap's derivation (31-character longest evidenced token, rounded to 40 with headroom)
      and the excluded-character set's rationale (`*` and backtick protect adjacent template structure;
      control characters are defense in depth given normalization). State the residual risk plainly: a false
      `APPROVED` requires self-contradictory vendor output (a clean verdict immediately followed by a directive
      inside the 40-character slot).
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` — in the
      "Codex GitHub terminal evidence" block, state: the response must reproduce, whitespace aside, one of a
      small set of exact captured clean-response templates covering the entire body, footer included, with no
      truncation step; anything else is treated as `NEEDS_REVISION` regardless of how close it reads to a
      genuine approval.
- [ ] `CHANGELOG.md` — `[Unreleased]` → `### Changed` (see Implementation Order for the literal entry).
- [ ] `AGENTS.md` — no change. The classifier is not named there and no command, convention, or branching rule
      is affected.
- [ ] `REVIEW.md` — no change. This plan adds no cross-cutting review checklist category.
- [ ] Agent and Codex skill files — no change. No agent, skill, or protocol file references the affected
      symbols, and no workflow stage behavior changes (confirm at implementation time with a repository-wide
      search for the symbols this plan deletes or adds).

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A genuinely clean Codex response uses wording that does not reproduce any evidenced template, and safe-fails to `NEEDS_REVISION` | **Confirmed, not hypothetical — materialized on PR #1494, this plan's own first real-traffic exercise** | Low–Medium | **This is the central, accepted trade of this design, stated explicitly rather than discovered later — and now observed directly, not merely anticipated.** The failure direction is always safe (never a false `APPROVED`): PR #1494's Codex review used `:rocket:` instead of the sole evidenced `Swish!` literal and safe-failed, exactly as this row predicted. Recovery for the SHA field or the footer is a one-line addition to `CODEX_APPROVED_TEMPLATES`, backed by a live capture. **For the flavor slot specifically, recovery is no longer adding a token** — a 14-token enumeration was tried and replaced before merge (Decision 2 Addendum, superseded by Decision 2 Second Addendum) because 14 distinct tokens from under 50 samples proved the vocabulary would not converge by enumeration, the same non-convergence failure mode issue #1491 was originally filed against. The flavor slot is now a bounded placeholder (``[^*`[:cntrl:]]{1,40}``), so a genuinely clean response safe-fails on this axis now only if its flavor phrasing exceeds 40 characters or contains `*`/backtick/a control character — narrower and rarer than the enumeration's gap, and recovery for THAT (if a genuine flavor phrase is ever found to exceed the bound) is widening the placeholder's length cap or excluded-character set with live evidence, held to the same review discipline (Decision 2 Second Addendum). This risk directly subsumes and replaces every "vendor wording change" risk row every prior revision of this plan carried separately for the clean-signal vocabulary, the flavor-token list, and the footer literal — under this design there is exactly one surface (the template array, including its one bounded-placeholder slot) where this class of risk lives, not three |
| **The flavor placeholder (``[^*`[:cntrl:]]{1,40}``) is a genuine bounded placeholder, not a literal — unlike every other part of this template, a false `APPROVED` through this one slot is possible in principle** | Low | Medium | **Stated plainly, not claimed away (Decision 2 Second Addendum).** A false `APPROVED` requires Codex to emit a response reading "Didn't find any major issues." and then place an actual directive inside this 40-character slot, while still reproducing the complete, exact vendor footer verbatim afterward — self-contradictory vendor output (a clean verdict immediately followed by an instruction, inside one otherwise-genuine response). No evidence of this construction has ever been observed from the vendor; the SHA-pinning requirement (terminal evidence only) and the requirement to reproduce the complete real footer verbatim both remain fully load-bearing and unchanged, so this is not an open surface — it is one narrow, bounded, and disclosed slot. Mitigation if evidence of this construction is ever found: narrow the excluded-character set or the length cap further (always safe), never widen either without new live evidence |
| **The template now binds to vendor-controlled help text (the `<details>` footer), not just the verdict sentence — a purely cosmetic rewording of OpenAI's footer now also produces a false `NEEDS_REVISION`, which it did not under the prior (truncate-then-match) revision.** | **High, by design — an explicit, accepted trade** | Low–Medium | **Recorded explicitly (Decision 5).** The failure direction remains safe (more `NEEDS_REVISION`, never a false `APPROVED`) — this trade is accepted specifically because it closes Codex GitHub finding `3803545669`, which was the opposite (unsafe) failure direction. Recovery is the same as the row above: re-capture the footer live and update the one template entry. This risk did not exist under the prior revision (the footer was discarded before comparison, so its wording was irrelevant to the match) and is a direct, disclosed consequence of removing truncation |
| Only one template is evidenced today, so the approval surface is intentionally very narrow at ship time | High (by design) | Medium | Accepted, not a defect: the two live sources this plan had access to yield exactly one clean-response shape. Widening it requires a genuinely new live capture, per Decision 2's extension rule — inventing a plausible-looking second template with no current live evidence was explicitly out of scope and must not be done without one |
| The commit-SHA placeholder's bound (`{7,40}`) is wider than the length every current real capture shows, and could in principle match a SHA-shaped string that is not really a commit reference | Low | Low | The bound is git's own documented abbreviated-to-full SHA-1 range, not an arbitrary guess (Decision 2) — narrowing it to today's observed length would be *safer* in the false-`APPROVED` direction but would fail on the very next legitimate response once this repository's object count crosses git's next auto-lengthening threshold, for a reason unrelated to anything Codex changed. This trade was made deliberately; revisit only with fresh evidence that git's behavior differs from its documented specification |
| **A future PR reintroduces truncation (or any partial-body matching) before comparison** | Low, if the standing rule in Decision 5 is applied; this exact class of finding has recurred before, so the historical base rate for "the truncation boundary needs one more fix" is not low | High | **Standing rule (Decision 5): no future PR may reintroduce a truncation step, a partial-body match, or any mechanism that compares less than the entire normalized body against the template.** `CODEX_FOOTER_OPENING_LITERAL` and `codex_strip_codex_footer` are deleted, not narrowed — there is no helper left to accidentally widen. Any PR proposing to "just match the visible part" or "strip X before comparing" must be rejected and pointed at this row and Decision 5 |
| **This revision removes the approval path's last dependency on `codex_response_is_blocking` for safety (not merely for verdict specificity) — a future refactor that assumes `is_blocking` is still load-bearing there, and relaxes it on that mistaken assumption, would reintroduce risk `is_approved` no longer independently guards against** | Low | Medium | Recorded explicitly (Decision 4, new bullet; Decision 5, closing paragraph): `is_approved`'s whole-body exact match is now self-contained — no input can reach `APPROVED` without being byte-identical (whitespace aside) to the one evidenced literal, regardless of what `is_blocking` does. `is_blocking` remains independently necessary for its own reason (Decision 4: false negatives there are unsafe on their own terms) — this row exists so a future contributor does not mistake "is_blocking is no longer needed to prevent this specific false APPROVED" for "is_blocking is no longer needed" |
| BSD versus GNU tooling divergence (`tr`'s whitespace-class handling, `grep -E`'s escaping of `.`/`*`/backtick/parentheses in the template) | Medium | Medium | This revision uses **fewer** BSD/GNU divergence points than the prior one: no `awk` truncation pass at all, no `\b` word boundaries anywhere, and the one remaining regex per template is a fully-anchored literal with a single bounded character-class placeholder — the simplest, least divergence-prone construct this plan has ever shipped. Verify on both BSD and GNU tooling at implementation time; CI covers GNU |
| `CODEX_APPROVED_TEMPLATES` regresses to a flexible pattern (an optional clause, a case-insensitive flag, a wildcard placeholder) — the same class of finding that recurred repeatedly against this classifier's prior designs, now aimed at the one array that replaced all of them | Low, **if the mechanical rule below is applied**; historically high without one | High | **Standing rule (Decision 2): every entry in `CODEX_APPROVED_TEMPLATES` must be backed by a live capture, every non-literal character must be a placeholder bound to that field's own external specification (never a general wildcard), and no case-insensitive, optional, alternation, or truncation-based matching may be introduced.** Any PR proposing otherwise — however narrowly scoped it looks — must be rejected and pointed at this row and Decision 2 |
| The scenarios in Group RETARGETED, plus the new scenarios this plan adds, mask a real regression in something other than `is_approved` | Medium | Medium | The "Test disposition" section gives an exhaustive derivation method, not a bare count; the PR description must name the full delta by scenario name, derived fresh against the real file, not a number alone — a stable-looking total has previously concealed a real composition change when reported as a bare number |
| **This document's own claims about which test scenarios already exist, or about test-suite counts, have been wrong multiple times across this plan's review history** | Medium, absent the standing rule below; historically has recurred, so treat as a real, not hypothetical, risk | High — a false "exists" claim leaves a genuine coverage gap that reads as covered; an inflated or deflated count misdirects the implementer | **Standing rule: before relying on any claim in this document that a named test scenario "exists," "is kept," or "is unchanged," or on any count derived from the test file, re-derive it by direct execution against the real file** — never trust this document's prose for either, no matter how recent the revision. This is why this document states derivation methods and reconciliation rules rather than frozen numbers wherever the underlying file can change |
| **A symbol scheduled for deletion is silently load-bearing for `codex_response_is_blocking` — deleting it (or one of its call sites) reintroduces a false-blocking regression the production script's own history already fixed once** | Medium, absent the standing rule below; has occurred once in this plan's history (`codex_strip_not_only_idiom`) | High — a silently reintroduced false-blocking match can override concurrent availability evidence and produce an incorrect `NEEDS_REVISION` (blocking branch) for a genuinely clean response | **Standing rule: before scheduling ANY symbol for deletion, check whether it has a real call site inside `codex_response_is_blocking` specifically** (not just inside the function being replaced) — `codex_response_is_blocking`'s failure direction is unsafe (Decision 4), so an incorrect deletion there is never merely a disclosed trade the way an `is_approved`-side deletion can be. No other scheduled-for-deletion symbol has this coupling today (confirmed by inspecting the function's real body directly), but any future addition to the deletion list must repeat this check, not assume it |
| **A verification command added to close one finding introduces a new, unexecuted defect of its own** — a `grep -c` count vulnerable to comment-line inflation, a `grep`-over-`git diff` check that cannot prove a function region is unmodified, a `diff` including line numbers on both sides that produces false positives when unrelated code shifts line numbers around it, or a `diff` comparing against a moving branch-tip ref (`origin/develop`) instead of the stable commit this branch actually started from | Medium, absent the standing rules below; has recurred multiple times in this plan's history | Medium–High — a mandatory smoke step that fails a correct implementation blocks shipping; a check that cannot detect a real regression gives false confidence | **Standing rules: (1) every verification command added to this document or the smoke-test runbook must be executed against the real tree before being written down, not reasoned about; (2) any `grep -c`/exact-count check must either anchor to executable syntax or explicitly filter comment lines before counting, if the searched symbol could plausibly appear in a comment; (3) any check whose purpose is "prove this function/region is unmodified" must extract the complete region and diff the extraction directly — `grep` over a diff can only prove a specific line exists or changed, never that an unrelated line inside the same region did not change; (4) a byte/content comparison must never include line numbers in the compared text, since unrelated deletions elsewhere in the file shift line numbers and produce false-positive diffs on byte-identical content; (5) any comparison whose purpose is "prove this is unchanged from what the branch started with" must resolve `git merge-base HEAD origin/develop` (after `git fetch origin`) once and compare against that commit, never against `origin/develop` directly — the branch tip is a moving target that can advance after branching, producing a false-positive diff on genuinely untouched code, and a stale or missing remote-tracking ref must fail loudly rather than silently falling back to a tip comparison** |
| **A test-suite count is derived by arithmetic (subtracting one heterogeneous count from another) instead of direct enumeration, concealing a heterogeneous total** | Medium, absent the standing rule below; has recurred multiple times in this plan's history | High — an inflated or deflated group size misdirects the implementer, and a correct implementation then fails a mandatory smoke step | **Standing rule: every test-suite count is produced by a stated command run directly against the real file at the time it is needed, and no count is ever derived by subtracting one heterogeneous count from another.** A heterogeneous total (e.g. "every `codex_*` assertion of every kind") is never a valid basis for computing a subgroup's size by subtraction, because the total may contain categories the subtraction does not account for. A same-superset subtraction (a precisely-identified subset from its own precisely-identified superset) is safe; a cross-group subtraction is not. Where a reconciliation across groups is useful, it must be presented as a direct-enumeration sum that is *checked against* the total, never as the sole method used to *derive* a group's membership |
| **An edge-case or scenario expectation is modeled against a single classifier function in isolation instead of the composed verdict chain at a real verdict site** | Medium, absent the standing rule below; has recurred more than once in this plan's history | High — a false safe-fail claim looks like a documentation defect but is a real production gap, since a branch downstream of the function under test can override its result | **Standing rule (Decision 6): every edge-case expectation in this document is stated for the composed verdict chain at a real verdict site, never for `codex_response_is_approved` (or any other classifier function) in isolation.** Verification of a classifier change must patch a copy of the real production script with only the changed function replaced — everything else, including all four real verdict sites, left untouched — and run the actual edge case through the real, composed chain via a mocked `gh`, not through the function called directly |
| **A scenario's non-verdict paired assertion (exit code, reason string) is left asserting its old expected value after the scenario's verdict-string assertion is retargeted, because it was counted inside a "must pass unchanged, non-verdict" bucket instead of being recognized as paired with the retargeting scenario** | Medium, absent the standing rule below; has occurred once in this plan's history | High — a retargeted scenario whose paired exit-code assertion is left unedited fails the harness after a correct implementation, and the failure looks like a regression in `is_approved` rather than an incomplete test-file edit | **Standing rule: when any scenario's primary (verdict) assertion changes disposition, every other assertion paired with the same scenario — exit code, reason string, count — must be re-derived from the new disposition and checked for its own expected-value change, not assumed unchanged because it does not itself contain a `VERDICT:` string.** A "non-verdict" bucket is not the same claim as "unaffected by this plan"; membership in one does not imply the other |

---

## Operational cost and escape hatch

**What a maintainer should expect.** `VERDICT: APPROVED` will now be **at least as rare** as under the
immediately prior revision, and **rarer in one specific respect**: a cosmetic change to the vendor footer alone
— wording the prior revision never compared, because it discarded the footer before matching — now also
produces a false `NEEDS_REVISION`. This is the direct, intended consequence of the human decision behind this
round's redesign (see Decisions 1, 2, and 5, and "Background"): every softer alternative this plan tried — a
vocabulary list, then a disqualifier list, then a closed grammar, then exact matching with a truncation
boundary — was found to have a false-`APPROVED` gap within one to two review rounds, repeatedly, and the
truncation boundary's gap was found in exactly the same shape as the others (an unreviewed region where prose
could hide). Removing the boundary — rather than tightening it a fourth time — is the one change in this
plan's history that eliminates the *category* of gap, not just its latest instance, and the cost of that
guarantee is a wider surface bound to vendor wording. Each false `NEEDS_REVISION` produces one extra
reviewer-loop cycle: `pr-review-loop.sh` reports the platform as not clean, the item agent inspects the
response, finds nothing actionable, and re-triggers.

**Escape hatch: none, deliberately.** No environment variable, config flag, or CLI option is added to relax
the classifier. The supported response to a persistent false `NEEDS_REVISION` is:

1. Confirm, by re-fetching live, that the response really is a Codex clean response using wording not
   currently in `CODEX_APPROVED_TEMPLATES` — including wording inside the footer, not just the verdict sentence
   (do not assume — verify).
2. Capture the exact body live, complete footer included, and add it as a new template entry, bounding any
   genuinely variable field to that field's own known specification (as the SHA is bound to git's documented
   hex-length range) — never to an open-ended wildcard, and never by reintroducing a truncation step to avoid
   having to capture the footer. This is the **only** lever that can widen the approval surface, and it needs
   the same review a `CODEX_CLEAN_SIGNAL_PATTERN` change once required.
3. If Codex begins submitting reviews with `state == "APPROVED"`, file the deferred structural-approval
   follow-up from Decision 3 instead of loosening the template rules — that remains the one case where a
   structured GitHub signal is more trustworthy than any prose comparison this function could ever perform.

---

## Implementation Order

1. **Re-verify the vendor wire format** (Protocol 02 implementation-start source check). Re-run the
   `gh api …/issues/1489/comments` and `gh api …/pulls/1490/reviews` queries and confirm the clean-response
   shape and the **complete footer text** (not just its opening line) still match. Record `Still valid` or
   stop and return evidence to the parent orchestrator — a drifted capture changes what
   `CODEX_APPROVED_TEMPLATES` must contain, not just what this plan documents.
2. **Delete every obsoleted symbol** in `codex-github-reviewer.sh`: `CODEX_APPROVAL_PATTERN`,
   `CODEX_NEGATED_APPROVAL_TARGET_WORDS`, `CODEX_NEGATED_APPROVAL_PATTERN`, `CODEX_CLEAN_SIGNAL_PATTERN`,
   `CODEX_CLEAN_SIGNAL_EXCISION`, `CODEX_APPROVAL_NEGATION_PATTERN`, `CODEX_APPROVAL_HEDGE_PATTERN`,
   `CODEX_APPROVAL_ACTIONABLE_PATTERN`, `CODEX_APPROVAL_DISQUALIFIER_PATTERN`,
   `CODEX_RESIDUE_FILLER_WORD_PATTERN`, `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN`, `codex_excise_clean_signals`,
   `codex_residue_is_closed_grammar`, `codex_response_first_paragraph`, `codex_strip_vendor_metadata_lines`,
   and `CODEX_FOOTER_OPENING_LITERAL`/`codex_strip_codex_footer` (see Decision 5). **`codex_strip_not_only_idiom`
   is NOT on this list** — the function definition and its call inside `codex_response_is_blocking` are both
   kept; only its call inside the old `codex_response_is_approved` disappears, as a consequence of that
   function being fully replaced (Decision 1), not as a separate deletion step.
   *Verify*:
   1. `bash -n scripts/development-workflow/codex-github-reviewer.sh` succeeds.
   2. **The deletion-list absence check must be comment-filtered.** Several functions this plan keeps unchanged
      have rationale comments that name symbols on the deletion list — an unfiltered search over-counts. Filter
      comment lines before checking for absence (`grep -v '^[[:space:]]*#' scripts/development-workflow/codex-github-reviewer.sh
      | grep -nE "<deletion-list pattern>"`); this filtered form must return nothing after a correct
      implementation. Do not use the unfiltered form as a pass/fail gate — it will still show surviving comment
      lines in functions this plan does not touch.
   3. `codex_strip_not_only_idiom`'s occurrence count has the identical comment-inflation risk — see the
      Layer-by-Layer verify note for the comment-filtered method.
3. **Add** `CODEX_APPROVED_TEMPLATES` (Decision 2, now covering the entire body including the complete footer)
   and `codex_normalize_whitespace` (Decision 1, unchanged).
4. **Rewrite `codex_response_is_approved`** per Decision 1 and the Code Samples section: normalize whitespace
   on the raw body directly (no footer-strip call), test against every `CODEX_APPROVED_TEMPLATES` entry, return
   on first match.
5. **Gate the acknowledgement branch on non-terminal evidence, at all four verdict sites** (Decision 6) — this
   is a chain-level fix, not part of `codex_response_is_approved` itself, and must not be skipped: without it,
   a genuine Codex response that carries the real footer but does not exactly match the evidenced template is
   misrouted to `continue`/`sleep` (wait for more evidence) instead of the documented `NEEDS_REVISION`
   safe-fail, and eventually times out. Change the acknowledgement `elif` at the main-loop, async-arrival,
   async-final, and async-reaction-final verdict sites from an unconditional footer-text match to one gated on
   `source != "review"`.
   *Verify*: run every footer-bearing edge case in the Parser-risk addendum through the real, patched script
   via a mocked `gh` and confirm each produces the documented composed verdict, never `VERDICT: TIMED_OUT`.
   **This alone does not confirm all four duplicated copies of this gate are correct** — a single scenario per
   edge case resolves at whichever site its default mock sequencing reaches. Additionally run the four
   verdict-site near-miss scenarios from "New scenarios" (one routed to each of main-loop, async-arrival,
   async-final, and async-reaction-final) and confirm all four produce `NEEDS_REVISION`, never
   `VERDICT: TIMED_OUT`. Finally, apply only this gate to an otherwise-unmodified copy of the real script and
   confirm the full existing test suite still passes with no failures.
6. **Update every stale approval-path comment.** Keeping `codex_response_has_fence_marker` and
   `codex_strip_quoted_spans` unchanged (Decision 1) preserves their source comments, which describe an
   approval-path relationship this plan removes. Sweep the file for every comment mentioning
   `codex_response_is_approved`, `is_approved`, or describing fence/quote/vocabulary/excision/truncation
   behavior, and rewrite each to state the current contract, including (at minimum) the file-header "Verdict
   parsing" block, any duplicate copy of it inline in the polling loop, and the docstrings of
   `codex_response_has_fence_marker`, `codex_strip_quoted_spans`, and `codex_strip_not_only_idiom`.
   *Verify*: after this step, a search for `codex_response_is_approved` across the file must show only the
   function's own definition, its real call sites — **five, not four** (Codex GitHub finding `3805786163`, P2:
   the four verdict sites — main-loop, async-arrival, async-final, async-reaction-final — plus one more inside
   `codex_response_priority`, which calls `codex_response_is_approved` to decide whether a body ranks at the
   approved priority tier when selecting between competing evidence sources; confirmed by direct inspection of
   the real file, not assumed) — unchanged in count or location by this step (Decision 1 changes
   `is_approved`'s internals, not its name or any of its five call sites), and any comment that correctly
   describes current or historical behavior — no comment may still claim `codex_response_has_fence_marker`,
   `codex_strip_quoted_spans`, or `codex_strip_not_only_idiom` is "used by" `codex_response_is_approved`. Derive
   the expected post-implementation occurrence count directly from the edits this step itself makes (each
   comment rewrite that removes the phrase from a line reduces the count by one; each comment that is deleted
   entirely reduces it by one; all five call sites and the definition are unaffected) — do not carry forward a
   number from an earlier revision of this document without re-deriving it against the edits actually being
   made, and do not assume "call sites" means only the four verdict sites.
7. **Before touching the test file, re-derive which scenarios exist by name against the real, current
   `test-pr-review-loop.sh`** — this document's scenario-existence claims have been wrong before; do not
   proceed on any scenario list in this document without re-confirming it against the file as it stands at
   implementation time.
8. **Update the tests, in three explicitly sequenced stages — do not interleave them (Codex GitHub findings
   `3805277339` and `3805404998`, both P2: the reconciliation equations only balance against the file exactly
   as it stands before any scenario in this step is edited).**
   1. **Before editing anything, derive the group split and verify the reconciliation equations against the
      file as it currently stands** (see "Test disposition" for the enumeration commands and both equations).
      Confirm every scenario currently asserting `VERDICT: APPROVED` is classified into either Group APPROVED
      or Group RETARGETED, that both reconciliation equations balance against this pre-edit file, and that no
      scenario body has been touched yet. If either equation does not balance here, the classification is
      wrong — re-derive it before proceeding; do not adjust either equation's numbers to force agreement, and
      do not proceed to edit any scenario until it balances.
   2. **Then, and only then, apply the edits.** Update every Group APPROVED scenario body per the split in
      "Test disposition" — **a full body replacement for all eight members**, not a footer append for any of
      them (Codex GitHub finding `3805497682`, P2: the two template-anchored members' current bodies are
      missing the `Swish!` sentence and the footer entirely, not just the footer), with mock sequencing
      preserved for the routing-testing members kept in that group; apply every Group RETARGETED disposition
      to the remaining, vocabulary-testing scenarios only — **each retargeted scenario
      requires two edits, not one**: its `VERDICT: APPROVED` assertion retargets to `VERDICT: NEEDS_REVISION
      (unrecognized response format — safe-fail)`, **and** its paired `*_exit_clean` assertion retargets from
      `"0"` to `"1"` in the same commit; **`codex_usage_limit_topic_mention_not_quota` additionally requires
      its competing root-comment fixture updated to the new exact template, not merely the retargeting edits
      above** (Codex GitHub finding `3805611400`, P2 — see "Test disposition" for why the tie-break otherwise
      silently absorbs the exact regression this scenario exists to catch); confirm
      `codex_disqualifier_diagnostic_emitted` is genuinely absent (no deletion needed — it was never
      implemented); refresh the comment on each real scenario in Group
      UNCHANGED-NEEDS_REVISION (do not touch Group UNTOUCHED, per "Test disposition"). **Do not add any new
      scenario in this stage, and do not re-run the equations from stage 1 against the now-edited file** — the
      "different, simpler check" in "Test disposition" applies instead.
      *Verify*: run `bash scripts/development-workflow/tests/test-pr-review-loop.sh` and confirm it exits 0,
      and confirm by name (per the post-edit check in "Test disposition") that every Group RETARGETED scenario
      now reads `NEEDS_REVISION`/`"1"`, every Group APPROVED scenario still reads `APPROVED`, and no assertion
      changed anywhere among Group UNTOUCHED's members.
   3. **Then add the new scenarios** from "New scenarios" — including the four verdict-site near-miss routing
      scenarios described there (Codex GitHub finding `3805277351`, P2).
      *Verify*: per the "Post-addition check" in "Test disposition" — confirm the `codex_*` total grows by
      exactly the count of `run_test` lines the newly-added scenarios introduce, with every new assertion
      belonging to a scenario named in "New scenarios." Re-run the full suite and confirm it still exits 0.
9. **Update the documentation** listed in "Documentation Updates," then add the CHANGELOG entry under
   `[Unreleased]` → `### Changed`, copied literally:

   ```text
   - **Conservative Codex verdict classifier** (#1491): `codex-github-reviewer.sh` now requires the response —
     whitespace-normalized, with no truncation step of any kind — to be an exact match, from its first
     character to its last, against one of a small set of clean-response templates captured verbatim from real
     Codex responses (each template including the complete vendor `<details>` footer text), and safe-fails to
     `NEEDS_REVISION` for anything else, including responses that are plausibly clean but use different
     wording anywhere in the body. This replaces both the open-ended negated-approval vocabulary enumeration
     this plan originally targeted and the allow-list/closed-grammar/truncate-then-match designs this plan
     shipped and then found further false-`APPROVED` gaps in across subsequent review rounds — no vocabulary,
     grammar, or partial-body match converged, so this revision applies exact literal comparison to the entire
     response, leaving no discarded byte range for a novel construction to hide in. GitHub's structured
     `CHANGES_REQUESTED` review-state short-circuit and the blocking classifier are unchanged.
   ```

10. **Run the markdown and shell lint gates**: `npx markdownlint-cli2` on the changed docs and this plan,
    `python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`,
    `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`, and
    `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`.
11. **Walk the smoke test runbook** and record the results in the PR description.

---

## Document Quality Gate

- Spec/brief coverage: Checked — every objective in issue #1491's Option 2 maps to a decision, an
  implementation step, and test coverage; Options 1 and 3 are addressed explicitly under Decision 3 (unchanged
  across every revision). The human decision behind this revision (whole-body exact-template matching,
  replacing the truncate-then-match design) is itself still squarely within Option 2 — it is a different
  technique for implementing "an allow-list of recognized clean responses," not a change of approach to
  Option 1 or 3.
- Implementation-order consistency: Checked — helper names, constant names, decision labels, and file paths
  agree across the Summary, Decisions, Layer-by-Layer, Code Samples, Parser-risk addendum, Testing Strategy,
  and Implementation Order sections. **Scenario-name and test-count claims are deliberately not frozen in this
  document** — every section that references them states the derivation method and reconciliation rule
  instead, specifically because this plan's history includes multiple rounds where a frozen claim of this kind
  was later found wrong (fabricated "exists" scenarios, miscounted groups, a stale baseline). This document was
  re-read start to finish this round to confirm no passage still describes a superseded mechanism (footer
  truncation, the vocabulary/grammar designs, an isolated-function verdict model) as current, and no
  cross-reference points at a section that no longer exists.
- Verification support: Checked — every claim about existing behavior or the vendor wire format cites a
  Cross-Cutting Operational Assumption Check entry or a named source file; every claim about the test file's
  current contents states the command to derive it rather than a number, per the standing rule in Risks &
  Mitigations.
- Behavioral guarantees: Checked — the "cannot weaken the `CHANGES_REQUESTED` short-circuit" guarantee names
  its mechanism (unchanged, Decision 3); the "whole-body match leaves no discarded byte range" guarantee names
  its actual mechanism (no truncation step exists in `codex_response_is_approved`, Decision 1/5) rather than
  merely asserting it, and is the guarantee that directly answers Codex GitHub finding `3803545669`; the
  "`is_blocking` is no longer load-bearing for this specific composition" guarantee is stated as a consequence
  of the whole-body match, not as a new mechanism added to `is_blocking` (Decision 4); the "`is_blocking` is
  unchanged" guarantee is explicitly conditional on retaining `codex_strip_not_only_idiom`'s call site
  (Decision 4); the "exact matching converges" guarantee names its actual mechanism (a finite language defined
  by one literal template plus one bounded placeholder, Decision 2) rather than merely asserting it, and
  explicitly discloses both trades this design makes; the "the composed chain, not the classifier alone,
  determines the verdict" guarantee (Decision 6) names its mechanism and is verified against the real,
  composed chain, not the classifier in isolation.
- Complex workflow decision-gate matrix: Checked — see the matrix below.
- Parser/API/concurrency checklist: Checked (parser-risk addendum present with a full-replacement edge-case
  enumeration and a unit-test-mapping method); concurrent-event-source recorded as not applicable with
  rationale.
- CHANGELOG literal format: Checked — Implementation Order step 9 gives the entry in the project's
  `**Bold Title** (#N):` format under `### Changed`, describing the whole-body, no-truncation contract that
  will actually ship.
- Not-applicable rationale: Checked — suppression semantics and concurrency each carry a rationale.

### Decision-gate matrix

**Every row below is verified against the emitting code path in `codex-github-reviewer.sh` directly, not
against the row's own prior description** (Codex GitHub finding `3805405005`, P2 — an earlier revision of this
matrix conflated two rows with genuinely different verdict strings and exit codes; every other row was
re-checked the same way this round and confirmed to already match its real emitter).

| Gate input | Allowed outcome | Exit code | Required next action | Mirror surface |
| --- | --- | --- | --- | --- |
| Review-sourced evidence with `state == CHANGES_REQUESTED`, or `codex_response_is_blocking` matches | `NEEDS_REVISION` | 1 | Loop counts unresolved threads; item agent fixes findings | Unchanged in all four verdict sites and in `codex_response_priority` — both conditions share one branch and one emission in the real code, confirmed by inspection, so they are correctly one row |
| Usage-limit notice (`codex_response_is_usage_limit`) | `UNAVAILABLE — Codex GitHub review usage limit reached` | 3 | Platform reported unavailable; loop applies the configured unavailable policy | Unchanged. Emitted by `codex_return_usage_limit` — verified against its real body this round |
| Environment-setup notice (`codex_response_is_environment_error`) | `TIMED_OUT — Codex GitHub review environment missing (treated as unavailable)` | 2 | Same policy as above, but as a timeout, not a usage-limit notice — **corrected this round from a conflated row that stated `UNAVAILABLE`/exit 3 for this outcome too; the real verdict string and exit code differ from the usage-limit row above** | Unchanged. Emitted by `codex_return_environment_error` — verified against its real body this round, distinct from `codex_return_usage_limit` |
| The **entire, untruncated** body, whitespace-normalized, exactly matches an entry in `CODEX_APPROVED_TEMPLATES` (footer included, no truncation step) | `APPROVED` | 0 | Platform reported clean | No footer-truncation step precedes the match any more (Decision 1/5); the required literal now includes the complete vendor footer |
| The entire, untruncated, whitespace-normalized body does not exactly match any template, and evidence is terminal | `NEEDS_REVISION (unrecognized response format — safe-fail)` | 1 | Item agent inspects the response, confirms whether it is a genuinely clean response using new wording — including footer wording — and either re-triggers or (rarely) proposes a new template with a live capture | This is the only false-`NEEDS_REVISION` surface, now also covering a footer wording mismatch; reached even when the acknowledgement phrase is present, because Decision 6 gates that branch on non-terminal evidence |
| Acknowledgement text present, evidence not yet terminal | wait / re-poll | n/a | Loop continues polling within its budget | Decision 6 — this branch fires only for non-terminal evidence now, not for any body that happens to carry the footer's acknowledgement sentence |
| No terminal evidence within the poll window | `TIMED_OUT — no response from '<bot>' after …` | 2 | Treated as unavailable | Unchanged. Every other non-usage-limit unavailable/timeout emitter in the script (auth failure, malformed payloads, API fetch failures, reaction-without-review, head-changed, this final timeout) also uses `VERDICT: TIMED_OUT` at exit 2 — `codex_return_usage_limit`'s `UNAVAILABLE`/exit 3 above is the one exception, not the rule, confirmed by reading every `VERDICT: TIMED_OUT`/`VERDICT: UNAVAILABLE` emission in the file this round |

Example bodies for each changed row are enumerated in the Parser-risk addendum and mapped to named test
scenarios per "Unit test mapping," so the matrix, the examples, and the tests are the same set.

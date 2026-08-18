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

**Approach**: `codex_response_is_approved` returns `APPROVED` only when the body, after two narrow structural
strips (the vendor `<details>` footer, matched by an exact byte-literal line; nothing else), reduces —
whitespace-normalized, nothing else changed — to an **exact match against one of a small set of literal
templates captured verbatim from real Codex clean responses**. There is no prose parsing, no vocabulary list,
no grammar, and no position/complexity heuristic: either the remaining text is byte-for-byte (modulo
whitespace runs) one of the evidenced clean-response shapes, or it safe-fails to `NEEDS_REVISION`.
`codex_response_is_blocking` is unchanged — still a block-list, unchanged priority ordering, PR #1490's
`CHANGES_REQUESTED` short-circuit untouched — because its failure direction is the opposite one and a false
negative there is unsafe, so applying this same "exact evidence only" discipline to it would be unsafe in the
other direction (see Decision 4).

**This is the third design this plan has shipped**, each time in response to a new false-`APPROVED`
construction a review round found (see Decision 2 for the specifics). The technique that survived every round
unbroken was the one already reduced to exact literal comparison — the footer check. This revision applies
that same technique everywhere in the classifier, rather than tightening the previous prose grammar a sixth
time.

**Estimated complexity**: **M**

**Rationale**: The shipped code is now smaller than any earlier revision of this plan: one function rewritten
(`codex_response_is_approved`), two helpers (`codex_strip_codex_footer`, unchanged from the prior revision;
`codex_normalize_whitespace`, new), and one data structure (`CODEX_APPROVED_TEMPLATES`, an array of one
element today). Every prose-matching symbol this plan previously introduced — the clean-signal pattern and
its excision wrapper, the three disqualifier-vocabulary groups and their composite, the closed-residue-grammar
constants and helper, the vendor-metadata-label stripper, the first-paragraph helper — is deleted outright,
not deprecated in place (Decision 2). The work is still medium, not small, because the test corpus this
contract change affects is large (247 `codex_*` assertions) and the disposition delta is severe: only 5
scenarios can assert `VERDICT: APPROVED` under the new contract (down from 27 in the pre-plan baseline and 21
after the fourth revision), since only 5 fixture bodies are byte-for-byte reproductions of an evidenced real
clean-response template (3 existing scenarios, 2 of them retargeted with an updated body, plus 2 new
boundary-condition scenarios) — see "Test disposition" for the full, named delta.

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
| Assertion inventory (pre-plan baseline) | `python3 -c "…count run_test lines…"` on `test-pr-review-loop.sh` | 628 total `run_test` assertions; 247 `codex_*` assertions; 27 assert `VERDICT: APPROVED` |
| Loop coupling | `grep -n "codex-github-reviewer\|codex_response" scripts/development-workflow/pr-review-loop.sh` | single hit at line 790 (script path resolution). `pr-review-loop.sh` consumes only the verdict line and exit code, so no loop change is required |
| Real clean Codex root comment — re-fetched live this round | `gh api repos/lhpaul/ai-dev-framework-template/issues/1489/comments --jq '.[] \| select(.user.login\|test("codex";"i")) \| .body'` | `Codex Review: Didn't find any major issues. Swish!` + `**Reviewed commit:** \`87aaefceff\`` (10 lowercase hex chars) + the `<details>` "About Codex in GitHub" footer. Apostrophe confirmed straight ASCII (`0x27`) via `od -c`, not a curly quote |
| Real findings Codex reviews — ALL 12 re-fetched live this round | `gh api repos/lhpaul/ai-dev-framework-template/pulls/1490/reviews --jq '.[] \| select(.user.login\|test("codex";"i")) \| .body'` | All 12 review bodies on PR #1490 (its full review history) are structurally identical: `\n### 💡 Codex Review\n\nHere are some automated review suggestions for this pull request.\n\n**Reviewed commit:** \`<10-hex-char SHA, one per review>\`\n    \n\n<details>…</details>`. **None contains a clean-signal phrase in its visible text** — the body is Codex's generic "a review was submitted" wrapper; the actual verdict for this evidence type is carried by the review's `state` field (`COMMENTED` in every one of these 12), which Decision 3's precedence table already routes around prose parsing entirely. This means **none of the 12 #1490 captures is eligible to become an `is_approved` template** — they are not evidence of a clean-response shape, they are evidence of the review-submission wrapper shape, which is out of scope for this function |
| Footer opening line — byte-identical across all 13 real sources | `diff`/`od -c` comparing the `<details>` opening line from the #1489 capture against all 12 #1490 captures | Byte-identical: `<details> <summary>ℹ️ About Codex in GitHub</summary>`, including the same U+2139/U+FE0F emoji byte sequence (`342 204 271 357 270 217`) in every source. No divergence — `CODEX_FOOTER_OPENING_LITERAL` (unchanged from the prior revision) is confirmed current |
| Commit-SHA field observed across all 13 real sources | `grep -oE "Reviewed commit:\*\* \`[0-9a-f]+\`"` on all 13 captured bodies | All 13 show exactly 10 lowercase hex characters. The placeholder bound (`{7,40}`) is nonetheless drawn from git's own documented abbreviated-SHA range, not from this single observed length — see Decision 2 for why a narrower, observation-only bound was rejected |
| Tooling identity confirmed for this review round | `sed 2>&1`, `grep --version`, `awk --version` (via `/usr/bin/{sed,grep,awk}` explicitly) | BSD `sed` (rejects GNU long-option syntax), `grep (BSD grep, GNU compatible) 2.6.0-FreeBSD`, one-true-awk `20200816` — confirms the same macOS BSD toolchain this plan has targeted throughout |
| Open PRs on the same surface | `gh pr list --state open --limit 50` | zero open pull requests in the repository at check time |
| Repository mode | `grep -nE "^mode:\|^workflow_hub:\|^product_repo:" .ai-dev-workflow.yaml` | no key present → `single_repo`; this repository owns the plan |

### Predicate validation (reproducible)

The decision rule below — the exact mechanism this plan ships, not an illustrative approximation — was
executed against all 13 real captured Codex bodies (the #1489 root comment and all 12 #1490 reviews) and
against every synthetic fixture body this plan's test corpus has ever used, on macOS (BSD `sed`, BSD `grep`,
BSD `awk`, via their `/usr/bin/` paths). The implementer must re-run the same checks on GNU tooling in CI.

<!-- workflow-shell-contract: bash -->

```bash
CODEX_FOOTER_OPENING_LITERAL='<details> <summary>ℹ️ About Codex in GitHub</summary>'
codex_strip_codex_footer() {
  awk -v literal="$CODEX_FOOTER_OPENING_LITERAL" '$0 == literal { exit } { print }' <<< "$1"
}
codex_normalize_whitespace() {
  local text
  text=$(tr '\n\t\r' '   ' <<< "$1" | tr -s ' ')
  sed -E 's/^ //; s/ $//' <<< "$text"
}
CODEX_APPROVED_TEMPLATES=(
  '^Codex Review: Didn'"'"'t find any major issues\. Swish! \*\*Reviewed commit:\*\* `[0-9a-f]{7,40}`$'
)
visible=$(codex_strip_codex_footer "$body")
normalized=$(codex_normalize_whitespace "$visible")
grep -qE "${CODEX_APPROVED_TEMPLATES[0]}" <<< "$normalized"
```

**Result**: the real #1489 root comment matches (exit 0, `APPROVED`); all 12 real #1490 review bodies do not
match (exit 1, `NEEDS_REVISION` — as expected, since none carries a clean-signal phrase at all, see the
Verification Log row above); every construction found across all five review rounds of this plan's history
(`unapproved`, `un_approved`, `Approved. Revert.`, `Looks good. Remove the authentication check.`,
`Looks good. Commit this.`, the round-3 footer-paragraph exploit, the round-4 markup lookalike, the round-4
one-byte footer mutation, and the round-5 `Looks good, or is it?`) does not match. Full per-construction output
is in "Testing Strategy".

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved artifact base branch | `develop` | Parent orchestrator handoff for issue #1491 plus the branching section of `AGENTS.md` | 2026-08-17, repo `55b2df5d` | This invocation (issue #1491) plus same-surface open PRs touching `scripts/development-workflow/codex-github-reviewer.sh`; `gh pr list --state open` returned zero open PRs | `Verified` |
| Artifact owner / repository mode | `single_repo` — this repository owns the plan | `.ai-dev-workflow.yaml` (no `mode`, `workflow_hub`, or `product_repo` key) | 2026-08-17, repo `55b2df5d` | Current invocation only | `Verified` |
| Ready-phase reviewer that consumes this classifier | `review.on_ready.github: [codex-github]` | `.ai-dev-workflow.yaml` | 2026-08-17, repo `55b2df5d` | Current invocation; no open PR modifies `.ai-dev-workflow.yaml` | `Verified` |
| Codex clean-response wire format `codex_response_is_approved` must accept | **Revised this round.** Exactly one evidenced clean-response template: the literal `Codex Review: Didn't find any major issues. Swish!` sentence, followed (whitespace-normalized) by the literal `**Reviewed commit:**` marker and a backtick-quoted, lowercase-hex commit SHA of 7–40 characters (git's documented abbreviated-to-full SHA-1 range; only 10-character SHAs are directly observed so far). The generic `### 💡 Codex Review` review-submission wrapper (all 12 #1490 captures) is explicitly **not** a clean-response template — it carries no clean-signal text and is routed by the review `state` field instead (Decision 3, unchanged) | Live GitHub API responses on PR #1489 (root comment) and all 12 reviews on PR #1490, all re-fetched live this round | 2026-08-18, repo `1fe72e43` | Current invocation; vendor-controlled surface, re-verified at implementation start per Protocol 02 | `Verified` |
| Number of templates evidenced | **New this round.** Exactly 1. This is intentionally narrow — see Decision 2 for why inventing additional templates (e.g. a `No blocking issues found.` shape that appears nowhere in the two currently-accessible live sources) is explicitly out of scope for this plan, and Risks & Mitigations for the resulting operational trade-off | The two live sources listed above; no other source was consulted, per this round's explicit "never invented, never generalized" instruction | 2026-08-18, repo `1fe72e43` | Current invocation | `Verified` |

No conflict was found. The wire-format row is the one assumption a third party (OpenAI) can change without
notice; the implementation-start re-check for it is Step 1 of the Implementation Order, and Decision 2
explains exactly what changes when it does (a template stops matching; the fix is to capture the new format
live and add a template, never to relax the matching technique).

---

## Background: why block-list, allow-list, and closed-grammar approaches all failed to converge, and exact matching does not have the same failure mode

`codex_response_is_approved` originally (before this plan) did three things in sequence: bail out if a fence
marker is present, strip quoted spans and the "not only" idiom, reject if `CODEX_NEGATED_APPROVAL_PATTERN`
matches, then accept if `CODEX_APPROVAL_PATTERN` matches. `CODEX_NEGATED_APPROVAL_PATTERN` was
`CODEX_NEGATION_WORDS` plus a same-clause span plus `CODEX_NEGATED_APPROVAL_TARGET_WORDS` — both vocabularies
are finite enumerations of an infinite natural-language space, so every review cycle that found one more
synonym (`wouldn't`, `mustn't`, `unable to`, the noun "approval") was a genuine bug in the *unsafe* direction:
a missing entry produced a false `APPROVED`. Issue #1491 was filed against exactly this non-convergence.

This plan's **first** design (Decisions 1–2 as originally shipped, commit `6e41e260`) replaced the block-list
with an allow-list: require a recognized clean-signal phrase, then disqualify on any negation/hedge/actionable
token found elsewhere. That converged the *known* vocabulary gap but reopened the same class of problem one
level up — the **disqualifier** list was now the open-ended enumeration, and a construction using no listed
disqualifier word still slipped through (`Looks good. Remove the authentication check.`, Codex GitHub finding
`3800167486`).

The **second** design (a human-directed revision, commit `20f8d267`, then hardened twice more) replaced the
disqualifier scan with a zero-tolerance closed residue grammar: after excising the recognized signal, every
remaining clause had to reduce to nothing but a small closed-class filler/vendor-flavor vocabulary. This
converged the *specific* gap that motivated it, but the filler vocabulary — the thing doing the converging —
was itself an enumeration, and it kept admitting the wrong words: vendor-identity tokens that doubled as
imperative verbs (`commit`, `review`; Codex GitHub finding `3803050745`), and eventually a **hedge expressed
entirely in words the grammar already treated as inert** (`Looks good, or is it?` — `or`, `is`, and `it` are
all closed-class function words with no plausible directive reading, and the grammar had no way to recognize
that their *combination*, as a question, negates the clean signal; Codex GitHub finding `3803306915`). The
footer check, meanwhile — the one component of this classifier converted to **exact byte-literal comparison**
instead of a pattern (Decision 2 of the second design, then corrected once more after a still-too-flexible
tag-name regex, Codex GitHub finding `3803189273`) — **stayed closed across every subsequent round**. No
review round found a new bypass for it, because there was no vocabulary or grammar left to have a gap in: it
either matched the one exact string that was ever captured, or it didn't.

That is the decisive evidence behind this plan's **third and final** design: apply the footer check's
technique — exact comparison against literal, live-captured evidence, with no interpretive layer in between —
to the whole classifier, not just the footer. A response either reproduces one of a small set of real captured
clean-response shapes, whitespace differences aside, or it safe-fails. There is no vocabulary to be
incomplete, no grammar to have an unconsidered shape, and no position heuristic to be gamed, because there is
no parsing step left for a novel construction to exploit.

---

## Decisions

### Decision 1 — `APPROVED` requires an exact, whitespace-normalized match against a captured clean-response template

A response is `APPROVED` if and only if, after the footer strip below, the whitespace-normalized remaining
text is identical to one of the strings matched by `CODEX_APPROVED_TEMPLATES` (an array of fully-anchored
`^...$` patterns, each representing one evidenced clean-response shape with, at most, a tightly-bounded
placeholder for a field the evidence itself shows varies — see Decision 2). Concretely:

1. **Footer strip.** `codex_strip_codex_footer` truncates the body at the first line that is byte-identical to
   `CODEX_FOOTER_OPENING_LITERAL`. Unchanged from the prior revision of this plan (Decision 5).
2. **Whitespace normalization.** `codex_normalize_whitespace` replaces every run of whitespace (spaces, tabs,
   newlines, carriage returns — including blank lines between paragraphs) with a single space, then trims
   leading/trailing whitespace. This is the **only** permitted flexibility in the match, per the human
   decision that produced this design: no case folding, no optional clauses, no punctuation tolerance, no
   synonym alternation.
3. **Exact template match.** The normalized text must satisfy `^...$` for at least one entry in
   `CODEX_APPROVED_TEMPLATES`. Anything else — including a superset (extra trailing or leading text around an
   otherwise-matching template) or a subset (a truncated or reworded template) — fails.

There is **no separate fence-marker check, no quoted-span stripping, no first-paragraph restriction, and no
disqualifier scan** in this function. All four were mechanisms that existed to compensate for a parsing layer
that no longer exists: a stray fence marker, a quoted span, or off-position content is now just "extra text
that breaks the exact match," and the match already rejects it without a dedicated check. Verified: a
fenced-code-block wrapper around the real template body fails to match (the fence characters are literal text
the template does not contain) — see "Testing Strategy."

If the match fails, `codex_response_is_approved` returns non-zero and the caller falls through to the existing
safe-fail branch (`VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)`), or to the blocking
branch when `codex_response_is_blocking` already matched earlier in the chain (unchanged, Decision 4).

### Decision 2 — Why exact-template matching converges where every prior design did not, and the rules for extending it safely

**This is a design replacement, not an incremental fix.** The previous two designs of this plan (summarized in
"Background" above) are deleted in full: `CODEX_CLEAN_SIGNAL_PATTERN`, `CODEX_CLEAN_SIGNAL_EXCISION`,
`CODEX_APPROVAL_NEGATION_PATTERN`, `CODEX_APPROVAL_HEDGE_PATTERN`, `CODEX_APPROVAL_ACTIONABLE_PATTERN`,
`CODEX_APPROVAL_DISQUALIFIER_PATTERN`, `CODEX_RESIDUE_FILLER_WORD_PATTERN`, `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN`,
`codex_excise_clean_signals`, `codex_residue_is_closed_grammar`, and `codex_response_first_paragraph` are all
removed outright — not deprecated, not left dormant. There is nothing in the final design that reads like a
vocabulary list, a grammar, or a token-class test, because every one of those was itself the recurring root
cause across five review rounds (see "Background"): each was an open-ended enumeration over natural language,
and open-ended enumerations over natural language do not converge — that is the literal thesis issue #1491
was filed against, and it held regardless of which layer (block-list, allow-list, or closed grammar) the
enumeration lived in.

**Why exact matching against live evidence does not have this failure mode.** A regex over vocabulary or
grammar defines an *infinite* language (every sentence some combination of its tokens/rules can produce) and
asks "is this input inside that language" — the review rounds kept finding new sentences inside the language
that shouldn't have been. `CODEX_APPROVED_TEMPLATES` defines a *finite* language (exactly the strings its
anchored patterns can produce, which — because every non-placeholder character is a literal — is either one
exact evidenced string or, for the one bounded field, one of a small enumerable set of exact strings). There
is no "in between" a novel sentence can occupy: it either reproduces a template exactly (whitespace aside) or
it does not, and template membership is decided by direct comparison, not by evaluating whether some
open-ended rule happens to accept it.

**`CODEX_APPROVED_TEMPLATES` — the templates, and exactly what evidence each is drawn from.**

```bash
CODEX_APPROVED_TEMPLATES=(
  '^Codex Review: Didn'"'"'t find any major issues\. Swish! \*\*Reviewed commit:\*\* `[0-9a-f]{7,40}`$'
)
```

- **Template 1** is drawn from the PR #1489 root-comment capture, re-fetched live this round:
  `Codex Review: Didn't find any major issues. Swish!` followed by `**Reviewed commit:** \`87aaefceff\``.
  Every character is a literal from that capture **except** the commit SHA, which is the one field the
  evidence shows varies (all 13 real captures this round — the #1489 comment and all 12 #1490 reviews —
  contain a different SHA on their `Reviewed commit:` line, all 10 lowercase hex characters).
- **The SHA placeholder's bound is `[0-9a-f]{7,40}`, and it is not invented.** It is git's own documented
  abbreviated-to-full SHA-1 commit-id range (`git rev-parse --short` defaults to 7 characters and lengthens
  automatically as a repository grows to avoid collisions; a full SHA-1 is 40 hex characters). This bound is
  wider than the 10-character length every one of today's 13 real captures happens to show, deliberately: the
  SHA's length is a property of *this repository's object count*, not of Codex's wording, so a narrower bound
  tied only to today's observation would fail on tomorrow's legitimate response for a reason that has nothing
  to do with the vendor changing anything. This is the **one and only** placeholder in this plan's templates.
  It cannot absorb prose — it accepts hex digits and nothing else, within a length range fixed by git's own
  specification, not by this plan's judgment call about what "looks like" a SHA.
- **No other field is a placeholder.** "Swish!" is not generalized into "some flavor word" and the
  `**Reviewed commit:**` label is not stripped or made optional — both are literal characters in the
  template, exactly as captured. A response reading `Codex Review: Didn't find any major issues.` (no
  "Swish!") or omitting the `Reviewed commit:` line does **not** match, and returns `NEEDS_REVISION` — see
  Risks & Mitigations for why this is an accepted, disclosed trade rather than an oversight.
- **The generic `### 💡 Codex Review` review-submission wrapper (all 12 #1490 captures) is deliberately not a
  template.** It carries no clean-signal text at all — it is evidence of what a review submission's body looks
  like, not of what a clean verdict in prose looks like — so it is out of scope for this array by definition,
  not by omission. Decision 3's `state`-based routing (unchanged) is the correct mechanism for that evidence
  type, exactly as it already was.

**The governing rule for extending `CODEX_APPROVED_TEMPLATES` — unchanged in spirit from every prior
revision's "reviewers must not…" list, restated for the final design.** Adding a template is the **only**
change that can widen the approval surface, so it needs the same review discipline `CODEX_CLEAN_SIGNAL_PATTERN`
required in every prior revision:

- A new template must come from a **live capture** of a real Codex response — never invented, never a
  plausible-sounding guess, never a generalization from an existing template ("this probably also happens
  with different wording").
- Any variable field within a new template must be bound as narrowly as the evidence and the field's own
  known specification allow (as the SHA is bound to git's hex-length range, not to an arbitrary wildcard).
  A placeholder that can absorb arbitrary prose is not a bounded field — it is the grammar hole this design
  exists to close, reintroduced in a new shape.
- **Narrowing** — removing a template, or tightening a placeholder's bound — is always safe: it can only
  increase the false-`NEEDS_REVISION` rate. **Widening** — adding a template, or loosening a placeholder's
  bound — is never safe without the review above, because it can only increase the false-`APPROVED` rate. This
  is the same asymmetry every earlier revision of this plan already stated for its own token lists; it applies
  identically here, at the template level, because a template is exactly as much an enumerable admission list
  as a token was.

**The residual gap this design accepts, disclosed explicitly.** With one template evidenced, the classifier
will safe-fail on any genuinely clean response that does not reproduce that template's exact wording — a
vendor phrasing change, a different flavor sentence than "Swish!", a missing `Reviewed commit:` line, or the
generic review-wrapper format ever gaining clean-signal text of its own. This is the accepted trade the human
decision made explicitly (see "Why exact matching…" above and Risks & Mitigations): the failure direction is
always safe (more `NEEDS_REVISION`, never a false `APPROVED`), and the fix — capture the new wording live, add
a template with a stated, evidence-derived bound for any variable field — is the same fix this plan has
always prescribed for its riskiest lever, just now applied to one array instead of several.

### Decision 3 — Composition with the GitHub review `state` short-circuit from PR #1490

PR #1490 threaded GitHub's structured review `state` through evidence selection. That behavior is **preserved
verbatim, unchanged by this or any prior revision of this plan**; template matching is layered underneath it,
not in place of it. The resulting precedence, in the order each verdict site already evaluates it:

1. `state == "CHANGES_REQUESTED"` on review-sourced evidence → blocking, short-circuit, no prose parsing.
   Unchanged (`codex_response_priority`, `codex_combine_terminal_evidence`, and all four verdict sites).
2. `codex_response_is_blocking(body)` → blocking. Unchanged block-list (see Decision 4).
3. `codex_response_is_usage_limit` / `codex_response_is_environment_error` → unavailable. Unchanged.
4. `codex_response_is_approved(body)` → `APPROVED`. **This is the only function this plan's contract changes.**
5. Anything else → safe-fail `NEEDS_REVISION`. Unchanged.

Because the classifier only ever moves responses **out of** tier 4 and into tier 5, it cannot weaken the
`CHANGES_REQUESTED` short-circuit, cannot change `codex_response_priority`'s tier ordering (3 > 2 > 1 > 0),
and cannot let blocking evidence be hidden behind an availability notice. Since exact template matching can
only ever be **more** restrictive than every prior design (a strict subset of what the closed grammar
accepted, which was itself a strict subset of what the disqualifier scan accepted), this precedence
composition needs no re-verification beyond what prior revisions already established — nothing about tiers 1–3
or 5 changed in this round.

**Explicitly considered and deferred**: adding `state == "APPROVED"` as an independent sufficient condition
(the symmetric complement of PR #1490's `CHANGES_REQUESTED` short-circuit). It is deferred because the
observed Codex wire format submits clean results as `COMMENTED` reviews or root comments, never as an
`APPROVED` review, so the path would be dead code today while widening the approval surface. If the vendor
ever starts submitting `APPROVED` reviews, that is the right follow-up and should be filed as its own item —
and, notably, would be the one case where a structured signal is *more* trustworthy than prose matching, since
it comes from GitHub's own API rather than from parsing vendor-authored text.

### Decision 4 — `codex_response_is_blocking` stays a block-list

`codex_response_is_blocking` is **kept**, and `CODEX_BLOCKING_PATTERN`, `CODEX_MERGE_REFUSAL_PATTERN`, and
`CODEX_NEGATION_WORDS` are **kept unchanged** — this redesign does not touch them. Its only edit, unchanged
from every prior revision of this plan, is dropping the now-deleted `codex_strip_not_only_idiom` call
(see below). Reasons, restated because they are exactly as true under exact-template matching as they were
under every earlier design:

- **The failure directions are not symmetric.** A false negative from `is_approved` is safe (extra
  `NEEDS_REVISION`); a false negative from `is_blocking` is unsafe. Protocol 93 and
  `codex_combine_terminal_evidence` both depend on "blocking always wins outright" so that an actionable
  finding is never hidden behind a usage-limit or environment-error `UNAVAILABLE` verdict. Converting
  `is_blocking` to exact-template matching would mean a genuine refusal in ANY wording other than a captured
  template would be **missed entirely** — the opposite of this plan's goal. Exact matching is only safe to
  apply to the direction where a miss is safe; `is_blocking`'s miss direction is unsafe, so it keeps its
  block-list, unchanged.
- **Its vocabulary gaps stop being correctness bugs**, for the same reason every earlier revision of this plan
  already gave: under exact-template `is_approved`, a missing `is_blocking` synonym costs, at worst, a
  tier-4-vs-tier-5 nuance (an unrecognized refusal falls through to the already-conservative
  `NEEDS_REVISION` safe-fail instead of the more specific blocking verdict) — never a false `APPROVED`, since
  `is_approved` independently requires exact template reproduction regardless of what `is_blocking` decided.

`codex_strip_not_only_idiom` is deleted **entirely — the function definition, not just its call sites** (a
change from how earlier revisions of this plan described this step, which removed the calls but left the
function defined and unused; per this round's explicit "delete what the redesign obsoletes, do not leave it
dormant" instruction, an unreferenced function is exactly that). It existed only to avoid a false
`NEEDS_REVISION` on the rhetorical "not only X, but Y" construction, in both `is_approved` (now moot — the
function's own removal means there is no prose-normalization step left to need it) and `is_blocking` (kept,
per the standing decision recorded here since round 1: keeping a bespoke idiom stripper while the file
accepts a much higher false-`NEEDS_REVISION` rate everywhere else is incoherent, and "not only X, but Y" is
one of the enumerated constructs issue #1491 names as evidence that enumeration does not converge).

### Decision 5 — The vendor `<details>` footer is truncated via exact byte-literal comparison before classification

Every real Codex response ends with a static "About Codex in GitHub" `<details>` footer containing a bulleted
list, straight-quoted phrases, and marketing prose that is never part of the clean-verdict content. Truncating
it before template matching keeps the templates in Decision 2 short and readable; it is not load-bearing for
correctness the way it was under the disqualifier-scan and closed-grammar designs (a vendor wording change
inside the footer can no longer disqualify anything, because there is no disqualifier scan left to trigger —
template matching would simply fail to match an untruncated body just as readily as it fails on any other
extra text). It is kept because it is proven, cheap, and keeps the templates focused on content a human
actually reviews.

`codex_strip_codex_footer` truncates the body at the first line that is **byte-identical** to
`CODEX_FOOTER_OPENING_LITERAL` — `<details> <summary>ℹ️ About Codex in GitHub</summary>`, captured verbatim
from a live Codex response and re-verified byte-identical (via `diff`/`od -c`) against all 13 real captures
available this round. It is applied **only inside `codex_response_is_approved`**. It must not be applied
anywhere else, because:

- `codex_response_reviews_current_head` must see the original body for SHA extraction.
- The acknowledgement branch (`grep -qi "If Codex has suggestions, it will comment; otherwise it will react with"`)
  matches text that lives **inside** the footer; truncating before that check would break acknowledgement
  detection.
- `codex_response_is_blocking` must keep scanning the full body, which is also the mitigation for the only
  risk truncation introduces (a refusal placed after the footer): blocking is evaluated before approval at
  every verdict site (Decision 3).

**Why exact byte-literal comparison, not a regex — this is settled, not an open design question.** Three
consecutive review rounds tightened a regex-based version of this check, and each tightening closed one
lookalike while admitting another: a generic `<details` match (round 1, Codex GitHub finding `3800167489`)
truncated any `<details>` block anywhere in the body, including a non-vendor one hiding a real instruction; a
bare-phrase match (round 3, finding `3803050750`) truncated any paragraph merely mentioning "About Codex in
GitHub," markup or not; a markup-structure regex requiring *some* `<details…><summary…>…</summary` shape
(round 4, finding `3803189273`) still matched a lookalike using different tag names
(`<details-not-footer><summary-note>…</summary-note>`). Each of these was a flexible pattern accepting an
input shape it should not have. Exact byte equality against one fixed line has no such surface: the only way
to make it match something other than the captured literal is to reproduce that literal exactly, which is
definitionally the real footer, not a lookalike. **No future PR may reintroduce a regex, a tag-name pattern,
or any form of matching flexibility for this helper** — see the standing rule in Risks & Mitigations.

---

## Layer-by-Layer Changes

Only the tooling layer of this repository is affected. There is no database, API, frontend, or infrastructure
surface in scope.

### Shell tooling — `scripts/development-workflow/codex-github-reviewer.sh`

**Shell contract**: `bash` (the script declares `#!/usr/bin/env bash` and uses `<<<` here-strings, `local`,
and `[[ ]]`-free POSIX tests). No portable `bash-zsh` snippet is introduced.

- [ ] **Rename nothing, delete outright**: `CODEX_APPROVAL_PATTERN` (the original pre-plan symbol) is
      **deleted**, not renamed. Every prior revision of this plan proposed renaming it to
      `CODEX_CLEAN_SIGNAL_PATTERN`; the final design has no equivalent symbol at all, since there is no
      clean-signal vocabulary to match against — matching is against whole-body templates instead.
- [ ] **Delete** `CODEX_NEGATED_APPROVAL_TARGET_WORDS` and `CODEX_NEGATED_APPROVAL_PATTERN` (unchanged from
      every prior revision).
- [ ] **Delete** every symbol this plan itself introduced in an earlier revision and no longer ships:
      `CODEX_CLEAN_SIGNAL_PATTERN`, `CODEX_CLEAN_SIGNAL_EXCISION`, `CODEX_APPROVAL_NEGATION_PATTERN`,
      `CODEX_APPROVAL_HEDGE_PATTERN`, `CODEX_APPROVAL_ACTIONABLE_PATTERN`, `CODEX_APPROVAL_DISQUALIFIER_PATTERN`,
      `CODEX_RESIDUE_FILLER_WORD_PATTERN`, `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN`, `CODEX_RESIDUE_STARTER_PATTERN`
      (already dead from an earlier round), `codex_excise_clean_signals`, `codex_residue_is_closed_grammar`,
      `codex_response_first_paragraph`, and `codex_strip_vendor_metadata_lines`. None of these has a role in
      the final design — see Decision 2 for why each category (vocabulary, grammar, position) was replaced,
      not narrowed.
- [ ] **Delete** `codex_strip_not_only_idiom` — the function definition itself, not just its call sites (see
      Decision 4). Remove its call from `codex_response_is_blocking`.
      *Verify*: `grep -n "not_only" scripts/development-workflow/codex-github-reviewer.sh` returns nothing.
- [ ] **Keep unchanged**: `codex_response_has_fence_marker`, `codex_strip_quoted_spans`,
      `codex_response_is_usage_limit`, `codex_response_is_environment_error`,
      `codex_response_reviews_current_head`, `codex_response_priority`, `codex_select_terminal_evidence`,
      `codex_select_review_evidence`, `codex_combine_terminal_evidence`, `codex_response_is_blocking`,
      `CODEX_BLOCKING_PATTERN`, `CODEX_NEGATION_WORDS`, `CODEX_MERGE_REFUSAL_PATTERN`, and all four
      verdict-emission sites. Note that `codex_response_has_fence_marker` and `codex_strip_quoted_spans` are
      kept **because other functions still call them** (`is_usage_limit`, `is_environment_error`,
      `is_blocking`) — `is_approved` itself no longer calls either (see Decision 1).
- [ ] **Keep unchanged**: `CODEX_FOOTER_OPENING_LITERAL` and `codex_strip_codex_footer` — both carried forward
      byte-for-byte from the prior revision (Decision 5).
- [ ] **Add** `CODEX_APPROVED_TEMPLATES` — a bash array of fully-anchored `^...$` ERE patterns, one entry per
      evidenced clean-response shape (exactly one today). See Decision 2 for the template, its provenance, the
      one bounded placeholder it contains, and the extension rule. **Any future PR that adds an entry must be
      backed by a live capture and hold any variable field to the narrowest bound the evidence and the field's
      own specification allow** — this is the sole lever that can widen the approval surface, and is held to
      the same review discipline `CODEX_CLEAN_SIGNAL_PATTERN` required in every prior revision.
- [ ] **Add** `codex_normalize_whitespace` — collapses whitespace runs to a single space and trims. The only
      permitted flexibility in the match (Decision 1).
- [ ] **Rewrite** `codex_response_is_approved` per Decision 1: strip the footer, normalize whitespace, test
      against every entry in `CODEX_APPROVED_TEMPLATES`, return 0 on the first match or 1 if none match. No
      diagnostic line is emitted (see the Code Samples note on why the previous stderr diagnostics are
      removed).
- [ ] **Update** the file-header "Verdict parsing" comment block (currently describing path 2 in terms of the
      allow-list/grammar contract from the prior revision) to state the exact-template contract: `APPROVED`
      requires exact reproduction (whitespace aside) of a captured clean-response shape; anything else,
      including a superset or subset of a template, safe-fails.

### Tests — `scripts/development-workflow/tests/test-pr-review-loop.sh`

- [ ] Retarget every scenario whose fixture body is not byte-for-byte (whitespace aside) one of the
      `CODEX_APPROVED_TEMPLATES` entries from `VERDICT: APPROVED` to `VERDICT: NEEDS_REVISION`. This is nearly
      every scenario that previously asserted `APPROVED` — see "Test disposition" for the exhaustive,
      named delta. Update each retargeted scenario's fixture-body comment to state the new reason (the body is
      not an exact template reproduction), not the superseded grammar-based reason.
- [ ] Update the two scenarios whose bodies need only the addition of the evidenced `Swish!` sentence to remain
      exact template reproductions (`codex_clean_root_review_comment`, `codex_full_root_review_comment`) — see
      Group APPROVED in "Test disposition."
- [ ] Add the new regression scenarios listed in "Testing Strategy" (the round-5 exploit, the whitespace-
      normalization boundary cases, and the SHA-placeholder-bound cases) — see "New scenarios."
- [ ] Consolidate, rather than individually re-litigate, the round 1–4 regression scenarios whose underlying
      mechanism no longer exists (e.g. the underscore-boundary, adjacent-signal-excision, and closed-grammar
      scenarios) — every one of these constructions is now trivially rejected because it does not reproduce a
      template, and the assertion itself does not change (all were already, or are now, `NEEDS_REVISION`), but
      their comments must be rewritten to say so rather than describing removed machinery. Do **not** delete
      them: they remain valid regression coverage proving the new design does not reopen any exploit a prior
      round found.
      *Verify*: run `bash scripts/development-workflow/tests/test-pr-review-loop.sh` and confirm it exits 0,
      that the total assertion count matches the "Reconciled test-disposition counts" table (report any
      discrepancy), and that only the scenarios named in "Test disposition" changed expectation.

### Documentation

- [ ] `docs/workflow/development-workflow/integrations/codex-github.md`
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
- [ ] `CHANGELOG.md`

See "Documentation Updates" for exactly what changes in each.

---

## Code Samples

<!-- Illustrative — adapt during implementation. -->

**This is the third design this plan has shipped**, replacing (not extending) the residue-grammar design of
the prior revision after five review rounds each surfaced a new false-`APPROVED` construction (see
"Background" and Decision 2 for the full history). Every regex and helper below was re-executed against the
same macOS BSD toolchain this plan has targeted throughout (`sed`, `grep`, `awk`, `tr`, invoked via their
`/usr/bin/` paths to avoid any interactive-shell aliasing — confirmed BSD this round: `sed` rejects GNU's
long-option `--` syntax, `grep --version` reports `BSD grep, GNU compatible`, `awk --version` reports the
one-true-awk `20200816` build) against all 13 real captured Codex bodies, every construction found across all
five review rounds, and the full existing test corpus. See "Testing Strategy" for the complete, reproduced
verification output.

```bash
# Illustrative — adapt during implementation.
#
# Anchored on the ACTUAL vendor footer opening line, captured verbatim from
# a live Codex response, compared by EXACT byte equality — not a regex of
# any kind. Unchanged from the prior revision of this plan. Three
# consecutive review rounds each tightened a regex-based version of this
# check and each tightening admitted a fresh lookalike (see Decision 5).
# Re-verified this round: byte-identical (diff/od -c) across all 13 real
# captures currently available (the PR #1489 root comment and all 12
# PR #1490 reviews).
CODEX_FOOTER_OPENING_LITERAL='<details> <summary>ℹ️ About Codex in GitHub</summary>'

codex_strip_codex_footer() {
  awk -v literal="$CODEX_FOOTER_OPENING_LITERAL" '$0 == literal { exit } { print }' <<< "$1"
}

# Collapses every run of whitespace (spaces, tabs, newlines, carriage
# returns — including blank lines between paragraphs) to a single space,
# then trims leading/trailing whitespace. This is the ONLY permitted
# flexibility in template matching (Decision 1) — no case folding, no
# optional clauses, no punctuation tolerance, no synonym alternation.
# `tr` first converts every whitespace class this function cares about to
# a literal space (BSD tr does not support `\s`, hence the explicit
# newline/tab/carriage-return class), then `tr -s ' '` squeezes runs of
# spaces to one; `sed` trims the two remaining edges.
codex_normalize_whitespace() {
  local text
  text=$(tr '\n\t\r' '   ' <<< "$1" | tr -s ' ')
  sed -E 's/^ //; s/ $//' <<< "$text"
}

# Exact captured clean-response templates. See Decision 2 for the full
# provenance of each entry, the ONE bounded placeholder this plan permits
# (a commit SHA, bound to git's own documented abbreviated-to-full SHA-1
# hex-length range — NOT to the single length this round's captures happen
# to show), and the extension rule (a new entry requires a live capture and
# the same review CODEX_CLEAN_SIGNAL_PATTERN required in every prior
# revision — it is the ONLY lever that can widen the approval surface).
#
# Template 1 is drawn verbatim from the PR #1489 root-comment capture:
# "Codex Review: Didn't find any major issues. Swish!" followed by
# "**Reviewed commit:** `<sha>`". Every character is a literal from that
# capture except the SHA. The apostrophe in "Didn't" is a literal straight
# ASCII apostrophe (confirmed via `od -c` this round, not a curly quote),
# NOT a regex wildcard — do not replace it with `.` if this pattern is
# edited; a wildcard there would silently widen the match to any character,
# which is exactly the kind of unreviewed widening this design forbids.
CODEX_APPROVED_TEMPLATES=(
  '^Codex Review: Didn'"'"'t find any major issues\. Swish! \*\*Reviewed commit:\*\* `[0-9a-f]{7,40}`$'
)

codex_response_is_approved() {
  local body="$1" visible normalized template
  visible=$(codex_strip_codex_footer "$body")
  normalized=$(codex_normalize_whitespace "$visible")
  for template in "${CODEX_APPROVED_TEMPLATES[@]}"; do
    if grep -qE "$template" <<< "$normalized"; then
      return 0
    fi
  done
  return 1
}
```

Notes for the implementer:

- **No stderr diagnostic is emitted on a non-match.** Every prior revision of this plan emitted an
  `INFO: Codex clean signal present but disqualified (…)` line naming which rule fired, because there were
  multiple rules (a disqualifier match vs. an unclosed grammar clause) worth distinguishing operationally.
  Under exact-template matching there is exactly one reason a response fails to approve: it does not
  reproduce an evidenced template. A diagnostic distinguishing "no reason" is not useful, and adding one that
  tried to explain *why* a template didn't match (e.g. "closest template was N characters different") would
  reintroduce a fuzzy-matching concept this design deliberately does not have. If operational visibility into
  false-`NEEDS_REVISION` cases is wanted later, the correct mechanism is the operational-cost logging already
  described in "Operational cost and escape hatch," not a per-call diagnostic.
- **No fence-marker check, no quote-stripping, and no first-paragraph restriction are performed inside this
  function**, unlike every prior revision. Each was a defense against a specific way a parsing layer could be
  fooled; there is no parsing layer left to fool. Verified this round (see "Testing Strategy") that a fenced,
  quoted, or off-position wrapper around the real template body all fail to match, with no dedicated check
  needed — the exact-match requirement already rejects any extra or reordered text.
- `codex_response_has_fence_marker` and `codex_strip_quoted_spans` remain defined and used elsewhere in the
  file (by `is_usage_limit`, `is_environment_error`, and `is_blocking`); this function simply no longer calls
  either.
- Performance: this implementation is a fixed number of `awk`/`tr`/`sed`/`grep` passes over the body
  regardless of its structure (no per-sentence or per-clause loop, unlike the prior revision's residue
  grammar). Verified against a 200 000-character SIGPIPE-safety fixture (the real template's opening sentence
  followed by 200 000 non-matching characters): ≈0.04s, no hang, no crash, correctly `NEEDS_REVISION` — an
  order of magnitude faster than the prior revision's ≈0.4s on the same input, because there is no longer a
  sentence/clause tokenization pass to run.
- Every real captured body (all 13), every construction found across all five review rounds of this plan's
  history, and every scenario in the pre-this-round test corpus (previously organized as Groups A/A2/A3/B/C,
  now reorganized into Group APPROVED/RETARGETED/UNCHANGED-NEEDS_REVISION/UNTOUCHED — see "Testing Strategy")
  was re-verified against this exact implementation on BSD `sed`/`grep`/`awk`/`tr`. See "Testing Strategy" for
  the full, reproduced output and the exhaustive, named disposition delta.

---

## Parser-risk addendum

This plan is **parser-risk**: it materially changes how the response body is compared against expected
content, even though the final design has deliberately minimal "parsing" left (footer truncation and
whitespace normalization only — see Decision 1).

### Edge-case enumeration

The edge-case set below is a full replacement of every prior revision's set (E1–E26 across five rounds),
renumbered from 1, because most of those cases tested mechanisms (vocabulary excision, closed-grammar clause
splitting, filler-token admission) that no longer exist. Every construction that was ever found to cause a
false `APPROVED` across all five rounds is retained below as a regression case (E13–E21); the boundary/shape
cases for the final design are new (E3–E12).

| # | Input (verbatim) | Expected | Why it is an edge case |
| --- | --- | --- | --- |
| E1 | Real captured PR #1489 root comment, in full (with its real `<details>` footer) | approved | The anchor case: the one evidenced clean-response template, in its real, untruncated wire form |
| E2 | Any of the 12 real captured PR #1490 review bodies, in full | not approved | Confirms the generic review-submission wrapper — which carries no clean-signal text at all — correctly never matches; its verdict is (and remains) driven by the review `state` field, not this function (Decision 3) |
| E3 | `Codex Review: Didn't find any major issues.` (the real template's opening sentence, `Reviewed commit:` line included, but **without** `Swish!`) | not approved | The template has no optional clauses (Decision 1/2): a response missing the evidenced flavor sentence does not reproduce the template, however close it looks |
| E4 | The real template with a **different**, still-valid SHA (e.g. `deadf00d1234`, not the exact captured `87aaefceff`) | approved | Confirms the SHA placeholder generalizes across values, not just the one literal value captured — this is what makes it a placeholder rather than a second hardcoded literal |
| E5 | The real template with a 6-character SHA | not approved | Below the `{7,40}` bound — verifies the lower edge of git's abbreviated-SHA range is enforced, not just documented |
| E6 | The real template with a 41-character SHA | not approved | Above the `{7,40}` bound — verifies the upper edge (one past a full SHA-1) is enforced |
| E7 | The real template with a 40-character (full-length) SHA | approved | Confirms the upper bound is inclusive, not an off-by-one exclusion of legitimate full-length SHAs |
| E8 | The real template with a non-hex "SHA" (e.g. `not-a-sha!`) | not approved | The placeholder accepts hex digits only — confirms it cannot be satisfied by arbitrary text, which is what makes it a bounded field rather than a general wildcard |
| E9 | The real template with unrelated prose immediately **before** it (e.g. `FYI: Codex Review: …`) | not approved | Exact match is whole-body (via `^...$` after normalization), not a substring/prefix test — extra leading text breaks the match |
| E10 | The real template with unrelated prose immediately **after** it (e.g. `… \`87aaefceff\`\n\nAlso remove the auth check.`) | not approved | Same as E9, trailing direction — this is also the case that confirms no disqualifier-style trailing-clause exploit (the entire class of finding from rounds 2, 3, and 5) can reach `APPROVED`: any trailing content at all breaks the whole-body match, regardless of its wording |
| E11 | The real template wrapped in a fenced code block (`` ``` `` before and after) | not approved | Confirms no dedicated fence-marker check is needed (Decision 1): the fence characters are literal extra text the template does not contain, so the match fails on its own |
| E12 | The real template with extra/irregular whitespace (extra spaces, tabs, multiple blank lines between the two lines, trailing spaces) | approved | Confirms `codex_normalize_whitespace` provides exactly the permitted flexibility (Decision 1) and nothing more |
| E13 | The real template, case-altered (e.g. `codex review: didn't find any major issues. swish!`) | not approved | Confirms there is no case-insensitive matching beyond what the captures themselves show (Decision 1's explicit prohibition) |
| E14 | `This change remains unapproved.` | not approved | Round 1's boundary-lookalike construction — trivially rejected now: it is not a reproduction of any template |
| E15 | `This remains un_approved.` | not approved | Round 1's underscore variant — same reason as E14 |
| E16 | `Looks good. Remove the authentication check.` | not approved | Round 2's disqualifier-list gap (Codex GitHub finding `3800167486`) — same reason |
| E17 | `Approved. Revert.` | not approved | The residual gap the zero-tolerance grammar disclosed but could not close (Decision 2 of the prior revision) — now genuinely closed, not merely accepted, because it was never a reproduction of any template to begin with |
| E18 | `Looks good. Commit this.` | not approved | Round 3's vendor-metadata-token gap (Codex GitHub finding `3803050745`) — same reason |
| E19 | `Looks good.` followed by a **non-vendor** `<details>` block containing `Rename the unsafe function.` | not approved | Round 1's over-broad footer truncation (Codex GitHub finding `3800167489`) — the non-vendor block does not match `CODEX_FOOTER_OPENING_LITERAL`, so it is never truncated, and the whole body still does not reproduce any template |
| E20 | `Looks good.` followed by `<details-not-footer><summary-note>About Codex in GitHub</summary-note>` then `Rename the unsafe function.` | not approved | Round 4's tag-name-flexible footer regex (Codex GitHub finding `3803189273`) — same reason as E19, and additionally confirms exact byte-literal comparison has no tag-name surface to be flexible about |
| E21 | `Looks good, or is it?` | not approved | Round 5's filler-composed-hedge construction (Codex GitHub finding `3803306915`) — the construction that motivated this design replacement; trivially rejected because it is not a reproduction of any template |
| E22 | The real template with `This must not be merged.` inserted inside its `<details>` footer | not approved (blocking branch) | Confirms truncation still cannot hide a refusal from the **composed** verdict: `codex_response_is_approved` alone returns `APPROVED` for this body (the footer, refusal included, is stripped before matching), but `codex_response_is_blocking` (unchanged, Decision 4) scans the untruncated body first at every verdict site (Decision 3), so the composed result is `NEEDS_REVISION`, not `APPROVED` |

### Unit test mapping

There is one test file for this script: `scripts/development-workflow/tests/test-pr-review-loop.sh`. Each
edge case above gets at least one scenario there, driven through the real script with a mocked `gh` on `PATH`
(the harness convention already used by all 247 `codex_*` assertions).

| Edge case | Scenario name |
| --- | --- |
| E1 | `codex_real_vendor_footer_clean_root_comment` (exists — keep, verdict unchanged) |
| E2 | `codex_review_wrapper_no_clean_signal_not_approved_root_comment` (new) |
| E3 | `codex_template_missing_flavor_sentence_not_approved_root_comment` (new) |
| E4 | Covered by existing scenarios `codex_clean_root_review_comment`/`codex_full_root_review_comment` — both already use a different, non-captured SHA (`abcdefab12`, `abcabcabcabc1234567890`); no new scenario needed |
| E5 | `codex_sha_below_bound_not_approved_root_comment` (new) |
| E6 | `codex_sha_above_bound_not_approved_root_comment` (new) |
| E7 | `codex_sha_full_length_approved_root_comment` (new) |
| E8 | `codex_sha_non_hex_not_approved_root_comment` (new) |
| E9 | `codex_leading_prose_before_template_not_approved_root_comment` (new) |
| E10 | `codex_trailing_prose_after_template_not_approved_root_comment` (new) |
| E11 | `codex_fenced_template_not_approved_root_comment` (new) |
| E12 | `codex_irregular_whitespace_template_approved_root_comment` (new) |
| E13 | `codex_case_altered_template_not_approved_root_comment` (new) |
| E14 | `codex_unapproved_prefix_root_comment` (exists — keep, comment rewritten) |
| E15 | `codex_underscore_prefixed_lookalike_root_comment` (exists — keep, comment rewritten) |
| E16 | `codex_unenumerated_actionable_sentence_after_signal_root_comment` (exists — keep, comment rewritten) |
| E17 | `codex_approved_revert_not_approved_root_comment` (new — the residual gap is now a positive regression test rather than a disclosed accepted risk) |
| E18 | `codex_metadata_token_as_directive_root_comment` (exists — keep, comment rewritten) |
| E19 | `codex_nonfooter_details_block_not_truncated_root_comment` (exists — keep, comment rewritten) |
| E20 | `codex_footer_markup_lookalike_tag_names_not_truncated_root_comment` (exists — keep, comment rewritten) |
| E21 | `codex_or_is_it_hedge_question_not_approved_root_comment` (new) |
| E22 | `codex_footer_truncation_keeps_blocking_root_comment` (exists — keep, verdict unchanged) |

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

### Test disposition — the full, named delta

**This section is a full replacement, not an amendment.** Every prior revision's Group A/A2/A3/B/C/D/E
structure described dispositions under a design this plan no longer ships. The new contract (exact template
match) is dramatically more restrictive than any prior revision, so the delta is large: **only 5 scenarios
assert `VERDICT: APPROVED`**, down from 21 after the fourth revision (and from a 27-scenario, block-list-era
baseline). Every scenario below was re-executed against the exact implementation in the Code Samples section.

#### Group APPROVED — exactly 5 scenarios assert `VERDICT: APPROVED`

| Scenario | Body | Why it matches a template |
| --- | --- | --- |
| `codex_clean_root_review_comment` | **Body updated this round** to `Codex Review: Didn't find any major issues. Swish!` + `**Reviewed commit:** \`abcdefab12\`` (adds the evidenced `Swish!` sentence, which the previous body omitted and which is not optional under exact matching) | Exact reproduction of Template 1, SHA `abcdefab12` (10 hex chars, within bound) |
| `codex_full_root_review_comment` | **Body updated this round** the same way, with a different placeholder SHA (`abcabcabcabc1234567890`, 22 hex chars) | Exact reproduction of Template 1 with a different valid SHA — demonstrates the placeholder is not hardcoded to one value |
| `codex_real_vendor_footer_clean_root_comment` | The real captured PR #1489 body, in full, including its real `<details>` footer | The literal evidence Template 1 was drawn from — footer-stripped, whitespace-normalized, reproduces the template exactly |
| `codex_sha_full_length_approved_root_comment` (new) | Template 1 with a 40-character (full-length) SHA | Confirms the SHA bound's upper edge is inclusive (edge case E7) |
| `codex_irregular_whitespace_template_approved_root_comment` (new) | Template 1 with extra spaces, tabs, and multiple blank lines inserted between its two lines, plus trailing whitespace | Confirms `codex_normalize_whitespace` provides exactly the permitted flexibility and nothing more (edge case E12) |

#### Group RETARGETED — every previously-`APPROVED` scenario that does not reproduce a template

These 18 scenarios asserted `VERDICT: APPROVED` after the fourth revision of this plan. None of their fixture
bodies is a reproduction (whitespace aside) of `CODEX_APPROVED_TEMPLATES`' one entry, so all 18 retarget to
`VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)`. Keep each scenario and its body; rewrite
its comment to state the new reason (does not reproduce an evidenced template) rather than the superseded
grammar-based reason:

- `codex_reaction_with_current_review`, `codex_reaction_then_late_review`,
  `codex_async_reaction_then_late_review`, `codex_latest_current_review`,
  `codex_environment_with_current_review`, `codex_main_loop_env_then_newer_review_supersedes`,
  `codex_didnt_find_issues_and_looks_good_approved_root_comment` — all use `No blocking issues found.` or
  `Codex didn't find any major issues and looks good.`, neither of which is an evidenced template (see
  Decision 2: only the `Codex Review: … Swish! … Reviewed commit: …` shape is currently evidenced).
- `codex_quoted_rejection_in_clean_review_root_comment`, `codex_terminal_review_quotes_quota_message`,
  `codex_quoted_blocker_token_stays_approved_root_comment` — the three bodies this plan's third revision
  simplified specifically to survive the (now-deleted) zero-tolerance grammar; none reproduces the template.
- `codex_inline_backtick_pair_stays_approved_root_comment` — `` Looks good; `foo.py:42`. `` after three
  rounds of retargeting; does not reproduce the template.
- `codex_bare_approved_punctuation_root_comment`, `codex_two_clean_signals_one_line_root_comment`,
  `codex_adjacent_clean_signals_root_comment`, `codex_uppercase_clean_signal_root_comment`,
  `codex_emoji_clean_signal_root_comment`, `codex_adjacent_signal_second_contains_no_root_comment`,
  `codex_adjacent_signal_second_contains_didnt_root_comment` — added across rounds 1–2 to test
  clean-signal-vocabulary boundary conditions (`Approved.`, `lgtm approved`, `NO BLOCKING ISSUES FOUND.`,
  etc.) that no longer exist as a concept; none reproduces the template.

Also rename any scenario whose name now asserts the opposite of its expectation (the `…_stays_approved_…` and
`…_approved_root_comment` suffixes on several of the scenarios above) in the same commit that retargets it, so
the name and expectation never disagree on `develop`.

#### Group UNCHANGED-NEEDS_REVISION — every scenario that was already `NEEDS_REVISION` and stays that way

This is the large majority of the `codex_*` corpus: the 5 previously-Group-A2 scenarios
(`codex_long_review_body_no_sigpipe`, `codex_long_root_comment_no_sigpipe`,
`codex_usage_limit_topic_mention_not_quota`, `codex_usage_limit_code_reviews_phrase_mention`,
`codex_terminal_comment_quotes_env_error_not_ancillary`), the 9 previously-Group-C negation-precision
scenarios, and the roughly 26 previously-Group-D scenarios (negated-approval vocabulary, merge-refusal
blocking, quote/fence stripping). None of these bodies has ever reproduced, and still does not reproduce, any
template, so none changes verdict. **Every scenario's explanatory comment must still be rewritten** — under
every prior revision, most of these passed because a specific mechanism (a disqualifier match, a closed-
grammar clause, a fence-marker check) caught them; under this revision, they pass because the body is simply
not an exact template reproduction. That is a materially different — and, per Decision 2, structurally
simpler and more robust — reason, and the comment must say so, not describe removed machinery as current.
Scenarios that were already testing `codex_response_is_blocking` specifically (e.g. the merge-refusal-blocking
group) are wholly unaffected: that function did not change (Decision 4).

#### Group UNTOUCHED

All remaining `codex_*` scenarios (evidence selection and tie-breaks, usage-limit and environment-error
routing, `CHANGES_REQUESTED` state handling, trigger idempotency, thread audits, timeout and poll-interval
configuration) neither approve nor depend on approval-content parsing at all, and must pass unchanged. Any
failure among them is a genuine regression, not an intended contract change.

#### Deleted — `codex_disqualifier_diagnostic_emitted`

This scenario (added in an earlier revision) asserted that a stderr `INFO:` diagnostic line was emitted when a
clean signal was present but disqualified. The final design emits no diagnostic at all (Code Samples note: the
concept of "a clean signal was present but something else disqualified it" does not exist when there is no
clean-signal detection step, only exact-or-not template matching). Deleted outright, per the "delete what the
redesign obsoletes" instruction — there is no replacement, because there is nothing left to diagnose.

### New scenarios

**13 new scenarios**, one per edge case in the Parser-risk addendum that does not already have an existing
scenario, plus the 2 counted above in Group APPROVED (`codex_sha_full_length_approved_root_comment`,
`codex_irregular_whitespace_template_approved_root_comment`):

- `codex_review_wrapper_no_clean_signal_not_approved_root_comment` (E2) — `NEEDS_REVISION`. Uses a real
  captured PR #1490 review body verbatim.
- `codex_template_missing_flavor_sentence_not_approved_root_comment` (E3) — `NEEDS_REVISION`.
- `codex_sha_below_bound_not_approved_root_comment` (E5) — `NEEDS_REVISION`.
- `codex_sha_above_bound_not_approved_root_comment` (E6) — `NEEDS_REVISION`.
- `codex_sha_full_length_approved_root_comment` (E7) — `APPROVED`.
- `codex_sha_non_hex_not_approved_root_comment` (E8) — `NEEDS_REVISION`.
- `codex_leading_prose_before_template_not_approved_root_comment` (E9) — `NEEDS_REVISION`.
- `codex_trailing_prose_after_template_not_approved_root_comment` (E10) — `NEEDS_REVISION`.
- `codex_fenced_template_not_approved_root_comment` (E11) — `NEEDS_REVISION`.
- `codex_irregular_whitespace_template_approved_root_comment` (E12) — `APPROVED`.
- `codex_case_altered_template_not_approved_root_comment` (E13) — `NEEDS_REVISION`.
- `codex_approved_revert_not_approved_root_comment` (E17) — `NEEDS_REVISION`. The construction that defeated
  the prior revision's disclosed one-token tolerance; now a positive regression test, not an accepted risk.
- `codex_or_is_it_hedge_question_not_approved_root_comment` (E21) — `NEEDS_REVISION`. The round-5 exploit that
  triggered this design replacement.

Of the 13, **2** assert `VERDICT: APPROVED` (E7, E12) and **11** assert `VERDICT: NEEDS_REVISION`.

### Reconciled test-disposition counts

| Metric | Before this plan (baseline, `55b2df5d`) | After 4 prior revisions | After this revision (final) |
| --- | --- | --- | --- |
| Total `run_test` assertions | 628 | 674 | 674 − (`codex_disqualifier_diagnostic_emitted`'s assertions, estimated 2, exact count to reconcile at implementation time) + 13 × 2 = **~698** (confirm the exact figure when implementing — this table has carried the same "confirm at implementation time" caveat since round 2, because the harness's assertions-per-scenario convention is not perfectly uniform) |
| `codex_*` assertions | 247 | 293 | ~317, same caveat |
| Scenarios asserting `VERDICT: APPROVED` | 27 | 21 | **5** — the full, named delta is Group APPROVED above (3 existing scenarios retained, 2 of them with updated bodies, plus 2 new scenarios) versus the 18 named in Group RETARGETED that flip out. This is not a coincidentally-stable total like the last two revisions' reconciliations — it is a large, deliberate reduction, and the PR description must state it as such, by name, not as a bare count |

### Residual verification strategy

This is a full design replacement, so the evidence the implementation must produce before
`ready-for-human-review` is:

1. A full `bash scripts/development-workflow/tests/test-pr-review-loop.sh` run exiting 0, with the total
   assertion count reported before and after, reconciled against the table above (report and explain any
   discrepancy — the estimate above is explicitly not final).
2. A reconciliation statement in the PR description naming, individually: the 5 scenarios in Group APPROVED
   (and which 2 have updated bodies), the 18 scenarios in Group RETARGETED, the deletion of
   `codex_disqualifier_diagnostic_emitted`, and the 13 new scenarios. No scenario outside these four buckets
   may change disposition; any that does is a genuine regression, not an intended part of this contract
   change.
3. Confirmation that the real captured PR #1489 body approves end-to-end (not just via the illustrative
   snippet in the Verification Log) — this remains the single highest-impact check: a classifier that rejects
   the one thing it must accept is a total operational failure of the ready phase.
4. Confirmation that all 12 real captured PR #1490 review bodies still correctly return `NEEDS_REVISION` (or,
   for any with `state == "CHANGES_REQUESTED"`, are still routed to the blocking short-circuit unaffected by
   this function) — re-fetch live, do not rely on the bodies captured during this review round, since the
   whole point of exact-template matching is that it is sensitive to exactly this kind of drift.
5. Confirmation that every construction found across all five review rounds of this plan's history — E14
   through E21 in the Parser-risk addendum — still returns `NEEDS_REVISION` against the real script, not just
   the illustrative prototype in this plan.
6. Confirmation that `codex_response_is_blocking`'s own test coverage (unaffected by this revision, per
   Decision 4) still passes unchanged, and specifically that `codex_footer_truncation_keeps_blocking_root_comment`
   (edge case E22) still resolves to the blocking branch — this is the one remaining case where truncation
   inside `is_approved` and the composed verdict genuinely differ, and it is easy to regress silently if a
   future change ever moves the footer strip earlier in the precedence chain.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Real Codex clean root comment | Body captured from PR #1489: `Codex Review: Didn't find any major issues. Swish!`, a `**Reviewed commit:**` marker matching the fixture head SHA, and the full `<details>` "About Codex in GitHub" footer including its bulleted list | `scripts/development-workflow/tests/test-pr-review-loop.sh` (inline `gh` mock heredoc, scenario `codex_real_vendor_footer_clean_root_comment`) |
| Real Codex review-wrapper body (no clean signal) | Any one of the 12 bodies captured from PR #1490's review history, verbatim | `scripts/development-workflow/tests/test-pr-review-loop.sh` (scenario `codex_review_wrapper_no_clean_signal_not_approved_root_comment`) |
| Footer-with-refusal variant | The real PR #1489 body with `This must not be merged.` inserted inside the `<details>` block | `scripts/development-workflow/tests/test-pr-review-loop.sh` (scenario `codex_footer_truncation_keeps_blocking_root_comment`) |

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
shape recorded in the Verification Log, stop and report it before writing any code** — Implementation Order
step 1 requires this re-check, and a drifted capture changes what `CODEX_APPROVED_TEMPLATES` must contain.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/codex-github.md` — **replace** any existing "Verdict
      classification" section (added by an earlier revision of this plan) with one stating that `APPROVED`
      requires the response, after footer truncation and whitespace normalization, to be an **exact** match
      against one of a small set of literal templates captured from real Codex clean responses — currently
      exactly one, covering the `Codex Review: Didn't find any major issues. Swish!` / `**Reviewed commit:**`
      shape, with a bounded placeholder only for the commit SHA. State plainly that there is no vocabulary
      list, no grammar, and no case-insensitive or punctuation-tolerant matching, and that adding a template is
      the only way to widen the approval surface and needs a live capture plus the same review a
      `CODEX_CLEAN_SIGNAL_PATTERN` change once required. Note the deliberate, disclosed trade: a genuinely
      clean response using different wording than an evidenced template safe-fails to `NEEDS_REVISION` today.
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` — in the
      "Codex GitHub terminal evidence" block, update the sentence added by an earlier revision (about an
      "unhedged clean signal") to instead state: the response must reproduce, whitespace aside, one of a
      small set of exact captured clean-response templates; anything else is treated as `NEEDS_REVISION`
      regardless of how close it reads to a genuine approval.
- [ ] `CHANGELOG.md` — `[Unreleased]` → `### Changed` (see Implementation Order for the literal — this
      replaces, not appends to, the entry an earlier revision of this plan specified, since the shipped
      behavior described there is superseded).
- [ ] `AGENTS.md` — no change. The classifier is not named there and no command, convention, or branching rule
      is affected.
- [ ] `REVIEW.md` — no change. This plan adds no cross-cutting review checklist category.
- [ ] Agent and Codex skill files — no change. The Verification Log confirms no agent, skill, or protocol file
      references the affected symbols, and no workflow stage behavior changes.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A genuinely clean Codex response uses wording that does not reproduce any evidenced template, and safe-fails to `NEEDS_REVISION` | **High, by design** | Low–Medium | **This is the central, accepted trade of this design, stated explicitly rather than discovered later.** The failure direction is always safe (never a false `APPROVED`). Recovery is a one-line addition to `CODEX_APPROVED_TEMPLATES`, backed by a live capture of the new wording and held to the same review a `CODEX_CLEAN_SIGNAL_PATTERN` change once required (Decision 2). This risk directly subsumes and replaces every "vendor wording change" risk row every prior revision of this plan carried separately for the clean-signal vocabulary, the flavor-token list, and the footer literal — under this design there is exactly one surface (the template array) where this class of risk lives, not three |
| Only one template is evidenced today, so the approval surface is intentionally very narrow at ship time | High (by design) | Medium | Accepted, not a defect: the two live sources this round had access to (`#1489`, `#1490`) yield exactly one clean-response shape. Widening it requires a genuinely new live capture, per Decision 2's extension rule — inventing a plausible-looking second template (e.g. a `No blocking issues found.` shape with no current live evidence) was explicitly out of scope for this revision and must not be done without one |
| The commit-SHA placeholder's bound (`{7,40}`) is wider than the 10-character length every current real capture shows, and could in principle match a SHA-shaped string that is not really a commit reference | Low | Low | The bound is git's own documented abbreviated-to-full SHA-1 range, not an arbitrary guess (Decision 2) — narrowing it to today's observed 10 characters would be *safer* in the false-`APPROVED` direction but would fail on the very next legitimate response once this repository's object count crosses git's next auto-lengthening threshold, for a reason unrelated to anything Codex changed. This trade (a marginally wider hex-only, length-bounded field vs. a narrower one likely to need updating for reasons outside anyone's control) was made deliberately; revisit only with fresh evidence that git's behavior differs from its documented specification |
| Truncating the footer before matching could, in principle, hide a refusal from the composed verdict | Very low | High | Unchanged mitigation from every prior revision: `codex_response_is_blocking` runs before approval at every verdict site and scans the untruncated body (Decision 3/4); covered by scenario `codex_footer_truncation_keeps_blocking_root_comment` (edge case E22) |
| BSD versus GNU tooling divergence (`tr`'s whitespace-class handling, `awk`'s literal-string line comparison, `grep -E`'s escaping of `.`/`*`/backtick in the template) | Medium | Medium | The final design uses substantially fewer BSD/GNU divergence points than every prior revision: no `\b` word boundaries anywhere (there is no boundary-anchored token matching left at all), and the one remaining regex per template is a fully-anchored literal with a single bounded character-class placeholder — the simplest, least divergence-prone construct this plan has ever shipped. Verified on BSD tooling this round; CI covers GNU |
| `CODEX_APPROVED_TEMPLATES` regresses to a flexible pattern (an optional clause, a case-insensitive flag, a wildcard placeholder) — this is the same class of finding that recurred five times against this classifier's prior designs, now aimed at the one array that replaced all of them | Low, **if the mechanical rule below is applied**; historically High — it recurred five times across the classifier's history without one | High | **Standing rule (Decision 2): every entry in `CODEX_APPROVED_TEMPLATES` must be backed by a live capture, every non-literal character must be a placeholder bound to that field's own external specification (never a general wildcard), and no case-insensitive, optional, or alternation syntax may be introduced.** Any PR proposing otherwise — however narrowly scoped it looks — must be rejected and pointed at this row and Decision 2 |
| Regressing `codex_strip_codex_footer` back to a regex (unchanged risk from the prior revision, restated because it is unaffected by this round's redesign) | Low, if the standing rule from the prior revision is followed | High | Unchanged: `codex_strip_codex_footer` must remain an exact byte-literal match against `CODEX_FOOTER_OPENING_LITERAL` (Decision 5). Any PR that reintroduces a regex for this helper must be rejected |
| The 18 scenarios in Group RETARGETED, plus the deletion of `codex_disqualifier_diagnostic_emitted`, mask a real regression in something other than `is_approved` | Medium | Medium | The Test disposition section is exhaustive and named; the PR description must state the full delta by scenario name, not a bare count (this is now the third revision in this plan's history where a stable-looking total would have concealed a real composition change if reported as a bare number alone) |

---

## Operational cost and escape hatch

**What a maintainer should expect.** `VERDICT: APPROVED` will now be **rare** relative to every prior revision
of this plan — not merely "chattier responses safe-fail more often" as the earlier grammar-based design
predicted, but categorically: **any response that is not, character-for-character (whitespace aside), one of
the evidenced templates safe-fails**, including responses a human would immediately recognize as clean. This
is the direct, intended consequence of the human decision behind this design (see Decision 2 and "Background"):
every softer alternative this plan tried — a vocabulary list, then a disqualifier list, then a closed grammar —
was found to have a false-`APPROVED` gap within one to two review rounds, five times in a row. Exact matching
against live evidence is the one technique this plan's own five-round history shows does not have that failure
mode, and the cost of that guarantee is a categorically higher false-`NEEDS_REVISION` rate. Each false
`NEEDS_REVISION` produces one extra reviewer-loop cycle: `pr-review-loop.sh` reports the platform as not clean,
the item agent inspects the response, finds nothing actionable, and re-triggers.

**Escape hatch: none, deliberately — unchanged in spirit from every prior revision, restated because the lever
itself changed.** No environment variable, config flag, or CLI option is added to relax the classifier. The
supported response to a persistent false `NEEDS_REVISION` is:

1. Confirm, by re-fetching live, that the response really is a Codex clean response using wording not
   currently in `CODEX_APPROVED_TEMPLATES` (do not assume — verify).
2. Capture the exact body live and add it as a new template entry, bounding any genuinely variable field to
   that field's own known specification (as the SHA is bound to git's documented hex-length range) — never to
   an open-ended wildcard. This is the **only** lever that can widen the approval surface, and it needs the
   same review a `CODEX_CLEAN_SIGNAL_PATTERN` change once required.
3. If Codex begins submitting reviews with `state == "APPROVED"`, file the deferred structural-approval
   follow-up from Decision 3 instead of loosening the template rules — that remains the one case where a
   structured GitHub signal is more trustworthy than any prose comparison this function could ever perform.

---

## Implementation Order

1. **Re-verify the vendor wire format** (Protocol 02 implementation-start source check). Re-run the
   `gh api …/issues/1489/comments` and `gh api …/pulls/1490/reviews` queries from the Verification Log and
   confirm the clean-response shape and the footer opening line still match. Record `Still valid` or stop and
   return evidence to the parent orchestrator — a drifted capture changes what `CODEX_APPROVED_TEMPLATES` must
   contain, not just what this plan documents.
2. **Delete every obsoleted symbol** in `codex-github-reviewer.sh`: `CODEX_APPROVAL_PATTERN`,
   `CODEX_NEGATED_APPROVAL_TARGET_WORDS`, `CODEX_NEGATED_APPROVAL_PATTERN`, `CODEX_CLEAN_SIGNAL_PATTERN`,
   `CODEX_CLEAN_SIGNAL_EXCISION`, `CODEX_APPROVAL_NEGATION_PATTERN`, `CODEX_APPROVAL_HEDGE_PATTERN`,
   `CODEX_APPROVAL_ACTIONABLE_PATTERN`, `CODEX_APPROVAL_DISQUALIFIER_PATTERN`,
   `CODEX_RESIDUE_FILLER_WORD_PATTERN`, `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN`, `codex_excise_clean_signals`,
   `codex_residue_is_closed_grammar`, `codex_response_first_paragraph`, `codex_strip_vendor_metadata_lines`,
   and `codex_strip_not_only_idiom` (the function definition, plus its call in `codex_response_is_blocking`).
   *Verify*: `bash -n scripts/development-workflow/codex-github-reviewer.sh` succeeds and
   `grep -nE "CODEX_NEGATED_APPROVAL|CODEX_CLEAN_SIGNAL|CODEX_APPROVAL_(NEGATION|HEDGE|ACTIONABLE|DISQUALIFIER)|CODEX_RESIDUE_FILLER|CODEX_VENDOR_FLAVOR|codex_excise_clean_signals|codex_residue_is_closed_grammar|codex_response_first_paragraph|codex_strip_vendor_metadata_lines|not_only" scripts/development-workflow/codex-github-reviewer.sh`
   returns nothing.
3. **Add** `CODEX_APPROVED_TEMPLATES` (Decision 2) and `codex_normalize_whitespace` (Decision 1), placed next
   to `CODEX_FOOTER_OPENING_LITERAL`/`codex_strip_codex_footer` (both kept unchanged from the prior revision).
4. **Rewrite `codex_response_is_approved`** per Decision 1 and the Code Samples section: strip the footer,
   normalize whitespace, test against every `CODEX_APPROVED_TEMPLATES` entry, return on first match.
5. **Update the file-header "Verdict parsing" comment block** to describe the exact-template contract; remove
   every reference to the allow-list/grammar contract the comment block described after the prior revision.
6. **Update the tests**: apply the Group APPROVED and Group RETARGETED changes (Test disposition), delete
   `codex_disqualifier_diagnostic_emitted`, refresh every Group UNCHANGED-NEEDS_REVISION scenario's comment,
   then add the 13 new scenarios from "New scenarios."
   *Verify*: run `bash scripts/development-workflow/tests/test-pr-review-loop.sh` and confirm it exits 0, that
   the total assertion count is reconciled against the "Reconciled test-disposition counts" table (report the
   real figure — the table's estimate is explicitly provisional), and that only the scenarios named in Test
   disposition changed expectation.
7. **Update the documentation** listed in "Documentation Updates," then add the CHANGELOG entry under
   `[Unreleased]` → `### Changed`, copied literally:

   ```text
   - **Conservative Codex verdict classifier** (#1491): `codex-github-reviewer.sh` now requires the response —
     after vendor-footer truncation and whitespace normalization — to be an exact match against one of a small
     set of clean-response templates captured verbatim from real Codex responses, and safe-fails to
     `NEEDS_REVISION` for anything else, including responses that are plausibly clean but use different
     wording. This replaces both the open-ended negated-approval vocabulary enumeration this plan originally
     targeted and the allow-list/closed-grammar designs this plan shipped and then found further false-
     `APPROVED` gaps in across four subsequent review rounds — no vocabulary or grammar converged, so this
     revision applies the one technique in this classifier's history that did (exact literal comparison,
     already proven for the vendor footer check) to the whole verdict. GitHub's structured
     `CHANGES_REQUESTED` review-state short-circuit and the blocking classifier are unchanged.
   ```

8. **Run the markdown and shell lint gates**: `npx markdownlint-cli2` on the changed docs and this plan,
   `python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`,
   `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`, and
   `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`.
9. **Walk the smoke test runbook** and record the results in the PR description.

---

## Document Quality Gate

- Spec/brief coverage: Checked — every objective in issue #1491's Option 2 maps to a decision, an
  implementation step, and test coverage; Options 1 and 3 are addressed explicitly under Decision 3 (unchanged
  across every revision). The human decision behind this revision (exact-template matching, replacing the
  residue-grammar design) is itself still squarely within Option 2 — it is a different technique for
  implementing "an allow-list of recognized clean responses," not a change of approach to Option 1 or 3.
- Implementation-order consistency: Checked — helper names (`codex_strip_codex_footer`, unchanged;
  `codex_normalize_whitespace`, new), constant names (`CODEX_FOOTER_OPENING_LITERAL`, unchanged;
  `CODEX_APPROVED_TEMPLATES`, new — no `CODEX_CLEAN_SIGNAL_PATTERN`, `CODEX_APPROVAL_DISQUALIFIER_PATTERN`,
  `CODEX_RESIDUE_FILLER_WORD_PATTERN`, or `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN`, all deleted this round),
  decision labels (Decision 1–5, renumbered from the prior revision's 1–6 because the prior Decision 4 — a
  length-cap rationale specific to the deleted grammar design — has no equivalent in this design and is not
  carried forward as a dormant section), scenario names, and file paths agree across the Summary, Decisions,
  Layer-by-Layer, Code Samples, Parser-risk addendum, Testing Strategy, and Implementation Order sections. A
  full-document re-read confirmed no remaining passage describes the deleted grammar, disqualifier-list, or
  flexible-footer-regex mechanisms as current — every reference to them is explicitly framed as history (in
  "Background," Decision 2, or Decision 5's "why exact matching" note).
- Verification support: Checked — every claim about existing behavior, file coverage, counts, and the vendor
  wire format cites a Verification Log command or a named source file. The exact implementation shipped in
  Code Samples (not an illustrative approximation of it) was re-executed on BSD `sed`/`grep`/`awk`/`tr` against
  all 13 real captured Codex bodies, every construction found across all five review rounds, and every edge
  case in the Parser-risk addendum.
- Behavioral guarantees: Checked — the "cannot weaken the `CHANGES_REQUESTED` short-circuit" guarantee names
  its mechanism (unchanged, Decision 3); the "truncation cannot hide a refusal from the composed verdict"
  guarantee names `codex_response_is_blocking` running on the untruncated body (Decision 3/4); the "exact
  matching converges" guarantee names its actual mechanism (a finite language defined by literal templates
  plus one bounded placeholder, Decision 2) rather than merely asserting it, and explicitly discloses the one
  trade this design makes (a categorically higher false-`NEEDS_REVISION` rate) rather than presenting the
  design as risk-free.
- Complex workflow decision-gate matrix: Checked — see the matrix below.
- Parser/API/concurrency checklist: Checked (parser-risk addendum present with a full-replacement edge-case
  enumeration and per-case unit-test mapping); concurrent-event-source recorded as not applicable with
  rationale, unchanged.
- CHANGELOG literal format: Checked — Implementation Order step 7 gives the entry in the project's
  `**Bold Title** (#N):` format under `### Changed`.
- Not-applicable rationale: Checked — suppression semantics and concurrency each carry a rationale.

### Decision-gate matrix

| Gate input | Allowed outcome | Exit code | Required next action | Mirror surface |
| --- | --- | --- | --- | --- |
| Review-sourced evidence with `state == CHANGES_REQUESTED` | `NEEDS_REVISION` | 1 | Loop counts unresolved threads; item agent fixes findings | Unchanged in all four verdict sites and in `codex_response_priority` |
| `codex_response_is_blocking` matches | `NEEDS_REVISION` | 1 | Same as above | Unchanged |
| Usage-limit or environment-error notice | `UNAVAILABLE` | 3 | Platform reported unavailable; loop applies the configured unavailable policy | Unchanged |
| Footer-stripped, whitespace-normalized body exactly matches an entry in `CODEX_APPROVED_TEMPLATES` | `APPROVED` | 0 | Platform reported clean | **Changed — categorically stricter than every prior revision** |
| Footer-stripped, whitespace-normalized body does not exactly match any template | `NEEDS_REVISION (unrecognized response format — safe-fail)` | 1 | Item agent inspects the response, confirms whether it is a genuinely clean response using new wording, and either re-triggers or (rarely) proposes a new template with a live capture | **Changed — this is now the only false-`NEEDS_REVISION` surface; there is no longer a distinguishable "disqualifier matched" vs. "grammar clause unclosed" split, since there is only one comparison left** |
| No clean signal at all | `NEEDS_REVISION (unrecognized response format — safe-fail)` | 1 | Same as above | Subsumed into the row above — there is no longer a separate "signal present" concept to distinguish |
| No terminal evidence within the poll window | `TIMED_OUT` | 2 | Treated as unavailable | Unchanged |

Example bodies for each changed row are enumerated in the Parser-risk addendum (E1–E22) and mapped to named
test scenarios, so the matrix, the examples, and the tests are the same set.

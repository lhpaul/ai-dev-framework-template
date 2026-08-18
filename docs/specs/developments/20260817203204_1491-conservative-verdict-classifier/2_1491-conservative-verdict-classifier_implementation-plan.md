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

**Rationale**: The code change itself is small (one function rewritten, one helper added, three symbols deleted,
one renamed). The work is medium because it changes a contract that 27 existing assertions depend on: 9 test
scenarios change their expected verdict, 1 changes its fixture text, and new regression coverage must be added
for the allow-list contract and its parser edge cases. Every disposition must be justified individually so a
reviewer can tell an intended contract change from a regression.

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
  inside `unapproved` (edge case E1) and reintroduce a false `APPROVED`.
- **A2 — No fence marker anywhere.** `codex_response_has_fence_marker` on the **raw, untruncated** body must
  be false. Unchanged from today.
- **A3 — Disqualifier-free residue.** The **residue** — the whole footer-truncated, quote-stripped,
  lowercased body with every boundary-anchored `CODEX_CLEAN_SIGNAL_PATTERN` occurrence excised (via
  `CODEX_CLEAN_SIGNAL_EXCISION`) — must not match `CODEX_APPROVAL_DISQUALIFIER_PATTERN`.

If any condition fails, `codex_response_is_approved` returns non-zero and the caller falls through to the
existing safe-fail branch (`VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)`), or to the
blocking branch when `codex_response_is_blocking` already matched earlier in the chain.

**Excision before scanning is the mechanism that makes A3 sound.** The recognized clean phrases themselves
contain words that are otherwise disqualifiers (`no` in "no blocking issues", `didn't` in "didn't find any
major issues"). Removing them first lets the disqualifier list be aggressive without self-contradiction, and
removes the need for the existing `didn't`-is-deliberately-excluded special case in `CODEX_NEGATION_WORDS`.

### Decision 2 — Non-exhaustiveness of the disqualifier list is now safe, and that is the point

Under the old block-list, a missing negation synonym caused a false `APPROVED` — a correctness bug, because
`pr-review-loop.sh` would mark the platform clean on a rejecting review. Under the allow-list, a missing
disqualifier can only matter when a genuine clean signal is *also* present in the opening paragraph and no
listed disqualifier appears anywhere; the residual exposure is far narrower, and the *default* for anything
unrecognized is already `NEEDS_REVISION`.

**Reviewers must not read the non-exhaustive disqualifier list as a reintroduction of the old bug.** The
correctness argument no longer depends on the disqualifier list being complete. Concretely:

- Extending `CODEX_APPROVAL_DISQUALIFIER_PATTERN` is **always safe** and never required for correctness. It
  can be done at any time without re-analysis; it only moves the false-`NEEDS_REVISION` rate.
- Extending `CODEX_CLEAN_SIGNAL_PATTERN` is **the only change that can create new false-`APPROVED` surface**
  and must receive the same scrutiny the old negation list used to receive. This plan therefore adds **no**
  new clean-signal alternatives: the allow-list keeps exactly the alternatives that `CODEX_APPROVAL_PATTERN`
  has today.

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

`codex_strip_codex_footer` truncates the body at the first line containing `<details` (case-insensitive) and
is applied **only inside `codex_response_is_approved`**. It must not be applied anywhere else, because:

- `codex_response_reviews_current_head` must see the original body for SHA extraction.
- The acknowledgement branch (`grep -qi "If Codex has suggestions, it will comment; otherwise it will react with"`)
  matches text that lives **inside** the footer; truncating before that check would break acknowledgement
  detection.
- `codex_response_is_blocking` must keep scanning the full body, which is also the mitigation for the only
  risk truncation introduces (a refusal placed after the footer): blocking is evaluated before approval at
  every verdict site.

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
      wrapper — see the code sample and its inline comments.
- [ ] **Add** `CODEX_APPROVAL_NEGATION_PATTERN`, `CODEX_APPROVAL_HEDGE_PATTERN`,
      `CODEX_APPROVAL_ACTIONABLE_PATTERN`, and the composite `CODEX_APPROVAL_DISQUALIFIER_PATTERN`
      (the three groups plus `CODEX_BLOCKING_PATTERN`). These must be defined **after** the line that appends
      `CODEX_MERGE_REFUSAL_PATTERN` to `CODEX_BLOCKING_PATTERN`, since the composite reads it.
- [ ] **Add** `codex_strip_codex_footer`.
- [ ] **Add** `codex_response_first_paragraph`.
- [ ] **Rewrite** `codex_response_is_approved` per Decision 1.
- [ ] **Update** the file-header "Verdict parsing" comment block (currently describing path 2 as "Approval
      signals present → APPROVED") to state the allow-list contract, the three conditions, and the deliberate
      false-`NEEDS_REVISION` tradeoff.

### Tests — `scripts/development-workflow/tests/test-pr-review-loop.sh`

- [ ] Retarget the expected verdict of every scenario listed in Group C of "Test disposition" below.
- [ ] Retarget the fixture body of `codex_inline_backtick_pair_stays_approved_root_comment`.
- [ ] Add the new scenarios listed in "Testing Strategy".
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
# equivalent boundary-safety using only portable [^[:alnum:]] classes.
CODEX_CLEAN_SIGNAL_PATTERN='(approved|lgtm|looks[[:space:]]+good|didn.t find[[:space:]]+any major[[:space:]]+issues|no[[:space:]]+blocking[[:space:]]+issues?)'
# Portable word-boundary wrapper (no \b — unsupported by BSD sed). Used at
# BOTH classifier call sites below: A1's grep presence test AND A3's sed
# excision. Do not call grep or sed with the raw CODEX_CLEAN_SIGNAL_PATTERN
# directly at either site — see the A1 comment in codex_response_is_approved
# for the false-APPROVED gap that reintroduces.
CODEX_CLEAN_SIGNAL_EXCISION='(^|[^[:alnum:]])'"${CODEX_CLEAN_SIGNAL_PATTERN}"'([^[:alnum:]]|$)'

# Disqualifiers. Deliberately NON-EXHAUSTIVE: see Decision 2. Lowercase-only,
# because the residue is lowercased before scanning.
CODEX_APPROVAL_NEGATION_PATTERN='(\bnot\b|[[:alpha:]]n.t\b|\bnever\b|\bcannot\b|\bunable\b|\bwithout\b|\bno\b|\bnone\b|\bnor\b|\bneither\b|\blacks?\b|\blacking\b)'
CODEX_APPROVAL_HEDGE_PATTERN='(\bbut\b|\bhowever\b|\balthough\b|\bthough\b|\bunless\b|\buntil\b|\bpending\b|\bcaveats?\b|\bnits?\b|\bminor\b|\bnonetheless\b|\bnevertheless\b|\bexcept\b|\baside from\b|\bapart from\b|\bother than\b|\bassuming\b|\bat first glance\b)'
CODEX_APPROVAL_ACTIONABLE_PATTERN='(\bshould\b|\bmust\b|\bneeds?\b|\brequires?d?\b|\baddress\b|\bconsider\b|\brecommends?\b|\bsuggests?\b|\brevise\b|\bbefore merging\b)'
CODEX_APPROVAL_DISQUALIFIER_PATTERN="(${CODEX_APPROVAL_NEGATION_PATTERN}|${CODEX_APPROVAL_HEDGE_PATTERN}|${CODEX_APPROVAL_ACTIONABLE_PATTERN}|${CODEX_BLOCKING_PATTERN})"

# Truncates Codex's static "About Codex in GitHub" <details> footer. Applied
# ONLY inside codex_response_is_approved (see Decision 6).
codex_strip_codex_footer() {
  awk 'tolower($0) ~ /<details/ { exit } { print }' <<< "$1"
}

# First non-empty paragraph, leading blank lines skipped.
codex_response_first_paragraph() {
  awk 'NF == 0 { if (started) exit; next } { started = 1; print }' <<< "$1"
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
  # same boundary guarantee using only portable [^[:alnum:]] classes, so one
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

  # A3 — excise the clean signals, then reject on any disqualifier in what is left.
  residue=$(sed -E "s/${CODEX_CLEAN_SIGNAL_EXCISION}/\1 \3/g" <<< "$lowered")
  if grep -qE "$CODEX_APPROVAL_DISQUALIFIER_PATTERN" <<< "$residue"; then
    echo "INFO: Codex clean signal present but disqualified (negation/hedge/actionable token)" >&2
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

---

## Parser-risk addendum

This plan is **parser-risk**: it materially changes regex-based scanning of structured natural-language text.

### Edge-case enumeration

| # | Input (verbatim) | Expected | Why it is an edge case |
| --- | --- | --- | --- |
| E1 | `This change remains unapproved.` | not approved | Boundary variant: `\bapproved\b` must not match inside a concatenated prefix, so A1 fails outright |
| E2 | `Approved.` / `Approved!` / `(approved)` | approved | Boundary variant: terminal and bracketing punctuation must satisfy the excision's `([^[:alnum:]]\|$)` boundary group |
| E3 | `No blocking issues found. The content is consistent and the constant is important.` | approved | Negative lookalike: `content`, `consistent`, `constant`, `important` must not match `[[:alpha:]]n.t\b` |
| E4 | `This looks good; it oughtn't be merged yet.` | not approved | Unenumerated contraction. `oughtn't` is absent from `CODEX_NEGATION_WORDS`; the structural `[[:alpha:]]n.t\b` rule catches the whole contraction class at once |
| E5 | `Looks good and no blocking issues found.` | approved | Multiple occurrences on one line — both must be excised, leaving a disqualifier-free residue |
| E6 | `lgtm approved` | approved | Adjacent/overlapping occurrences. `sed`'s `g` flag resumes scanning after the replacement, so the second signal may be left un-excised. That is harmless: an un-excised clean signal is not a disqualifier. Assert the outcome, not the residue |
| E7 | `NO BLOCKING ISSUES FOUND.` | approved | Case normalization: the `tr` pass must make the lowercase-only patterns match |
| E8 | `No blocking issues found. 🎉` | approved | Multibyte safety: `LC_ALL=C tr` must not corrupt the emoji into something matching a pattern |
| E9 | Real clean root comment including the `<details>` footer with its bullet list | approved | The vendor footer must be truncated before the disqualifier scan; without truncation this is the single most likely source of a mass false-`NEEDS_REVISION` |
| E10 | `Didn't find any major issues.` + footer whose interior says `This must not be merged.` | not approved | Truncation must not hide a refusal: `codex_response_is_blocking` runs first, on the untruncated body |
| E11 | `Summary of the diff.` blank line `No blocking issues found.` | not approved | A1 position rule: a clean signal outside the opening paragraph does not approve |
| E12 | `` The documented output is: ```text / No blocking issues found / ``` `` | not approved | Fence marker present anywhere (A2), unchanged behavior; the closing fence is never located |
| E13 | `The documented bot response "No blocking issues found" is inaccurate.` | not approved | Quoted span is stripped before A1, so no clean signal survives |
| E14 | `No blocking issues found. The tests correctly cover the` `` `must fix` `` `marker.` | approved | Quoted span stripping must run **before** the disqualifier scan, or the quoted blocker token would disqualify a genuinely clean review |
| E15 | `No blocking issues found. Please address the naming.` | not approved | Actionable-verb group; the residue has no negation and no hedge, so this is the case only that group catches |

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

Every existing `codex_*` scenario is accounted for below. **No existing test is deleted.**

#### Group A — keep as-is, still `VERDICT: APPROVED`

These bodies contain a clean signal in the opening paragraph and a disqualifier-free residue, so the new
contract preserves them:

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
| `codex_inline_backtick_pair_stays_approved_root_comment` | Change the body from `` The fix looks good. See `foo.py:42` for a minor nit. `` to `` The fix looks good. See `foo.py:42` in the diff. ``; keep `VERDICT: APPROVED` | The scenario's purpose is to prove a **single** inline backtick pair does not trip the fence guard. `minor nit` is now a hedge disqualifier, which would flip the verdict for a reason unrelated to the regression being guarded. Retargeting the body preserves the original intent |

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

The eleven new scenarios in the "Unit test mapping" table above, plus:

- `codex_disqualifier_diagnostic_emitted` — assert that a body with a clean signal plus a disqualifier emits
  the `INFO: Codex clean signal present but disqualified` line, so the operational diagnostic is itself
  covered.

### Residual verification strategy

This is a contract-flip refactor with pattern-completeness characteristics, so the evidence the
implementation must produce before `ready-for-human-review` is:

1. A full `bash scripts/development-workflow/tests/test-pr-review-loop.sh` run exiting 0, with the total
   assertion count reported before and after.
2. A reconciliation statement in the PR description: every scenario whose expectation changed appears in
   Group B or Group C above, and no scenario outside those groups changed. Any additional flip discovered
   during implementation must be added to the table with its own justification rather than silently accepted.
3. Confirmation that the real captured Codex clean body (E9) approves — this is the check that guards against
   the highest-impact failure mode, a classifier that rejects every real clean review.

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
      and that the vendor `<details>` footer is ignored for this decision. Note the deliberate
      false-`NEEDS_REVISION` tradeoff and that extending the disqualifier list is always safe while extending
      the clean-signal allow-list is not.
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
| BSD versus GNU regex divergence (`\b` in `sed`, `tr` locale behavior) | Medium | Medium | `\b` is used only in `grep -E`, where the file already documents cross-implementation verification; `sed` uses explicit `[^[:alnum:]]` boundary groups; `tr` runs under `LC_ALL=C`. The prototype was executed on BSD tooling and CI covers GNU |
| Retargeting 9 expectations masks a real regression | Medium | Medium | The Group A–E disposition table is exhaustive; the PR must state that no scenario outside Groups B and C changed |

---

## Operational cost and escape hatch

**What a maintainer should expect.** Responses that are genuinely clean but *chatty* will now be reported
`NEEDS_REVISION` more often than before. Concretely, the constructions that used to approve and no longer
will are: an unrelated negation anywhere in the response ("tests were not run", "not a blocker"), any hedge
("but", "however", "minor nit", "at first glance"), any actionable verb ("please address", "should rename"),
and the "not only X" idiom. Each of these produces one extra reviewer-loop cycle: `pr-review-loop.sh` reports
the platform as not clean, the item agent inspects the response, finds nothing actionable, and re-triggers.

**Escape hatch: none, deliberately.** No environment variable, config flag, or CLI option is added to relax
the classifier. A bypass would be indistinguishable from the false-`APPROVED` bug this change exists to
eliminate, and it would be reached for precisely when the classifier is doing its job. The supported
responses to a persistent false `NEEDS_REVISION` are, in order:

1. Read the `INFO: Codex clean signal present but disqualified (…)` line to see which rule fired.
2. If a disqualifier is too broad, narrow `CODEX_APPROVAL_DISQUALIFIER_PATTERN` — always safe, no correctness
   analysis needed.
3. If the vendor's clean wording is unrecognized, extend `CODEX_CLEAN_SIGNAL_PATTERN` — the one change that
   widens the approval surface and therefore needs full review.
4. If Codex begins submitting reviews with `state == "APPROVED"`, file the deferred structural-approval
   follow-up from Decision 3 instead of loosening the prose rules.

---

## Implementation Order

1. **Re-verify the vendor wire format** (Protocol 02 implementation-start source check). Re-run the
   `gh api …/issues/1489/comments` and `…/pulls/1490/reviews` queries from the Verification Log and confirm
   the clean-response shape still matches. Record `Still valid` or stop and return evidence to the parent
   orchestrator.
2. **Add the new constants** in `codex-github-reviewer.sh`, immediately after the existing line that appends
   `CODEX_MERGE_REFUSAL_PATTERN` to `CODEX_BLOCKING_PATTERN`: `CODEX_CLEAN_SIGNAL_PATTERN` (renamed from
   `CODEX_APPROVAL_PATTERN`), `CODEX_CLEAN_SIGNAL_EXCISION`, the three disqualifier groups, and the composite
   `CODEX_APPROVAL_DISQUALIFIER_PATTERN`. Delete `CODEX_NEGATED_APPROVAL_TARGET_WORDS` and
   `CODEX_NEGATED_APPROVAL_PATTERN`.
   *Verify*: `bash -n scripts/development-workflow/codex-github-reviewer.sh` succeeds and
   `grep -n "CODEX_NEGATED_APPROVAL" scripts/development-workflow/codex-github-reviewer.sh` returns nothing.
3. **Add the two helpers** `codex_strip_codex_footer` and `codex_response_first_paragraph`, placed next to the
   other normalization helpers.
4. **Rewrite `codex_response_is_approved`** per Decision 1, including the two stderr diagnostics.
5. **Delete `codex_strip_not_only_idiom`** and remove its call from `codex_response_is_blocking`. Make no
   other change to `codex_response_is_blocking`.
   *Verify*: `grep -n "not_only" scripts/development-workflow/codex-github-reviewer.sh` returns nothing.
6. **Update the file-header "Verdict parsing" comment block** and the rationale comments around the changed
   and deleted symbols.
7. **Update the tests**: apply Group B and Group C changes, refresh Group D comments, then add the new
   scenarios from the unit-test mapping table plus `codex_disqualifier_diagnostic_emitted`.
   *Verify*: run `bash scripts/development-workflow/tests/test-pr-review-loop.sh` and confirm it exits 0 and
   that the failures you fixed are exactly the ones this plan predicted — read the output and confirm no
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
  implementation step, and test coverage; Options 1 and 3 are addressed explicitly under Decision 3.
- Implementation-order consistency: Checked — helper names (`codex_strip_codex_footer`,
  `codex_response_first_paragraph`), constant names (`CODEX_CLEAN_SIGNAL_PATTERN`,
  `CODEX_CLEAN_SIGNAL_EXCISION`, `CODEX_APPROVAL_NEGATION_PATTERN`, `CODEX_APPROVAL_HEDGE_PATTERN`,
  `CODEX_APPROVAL_ACTIONABLE_PATTERN`, `CODEX_APPROVAL_DISQUALIFIER_PATTERN`), decision labels
  (Decision 1–6), scenario names, and file paths agree across the Summary, Decisions, Layer-by-Layer, Code
  Samples, Parser-risk addendum, Testing Strategy, and Implementation Order sections.
- Verification support: Checked — every claim about existing behavior, file coverage, counts, and the vendor
  wire format cites a Verification Log command or a named source file.
- Behavioral guarantees: Checked — the "cannot weaken the `CHANGES_REQUESTED` short-circuit" guarantee names
  its mechanism (the classifier only moves responses from priority tier 0 to tier 2, and blocking is
  evaluated first at every verdict site); the "truncation cannot hide a refusal" guarantee names
  `codex_response_is_blocking` running on the untruncated body.
- Complex workflow decision-gate matrix: Checked — see the matrix below.
- Parser/API/concurrency checklist: Checked (parser-risk addendum present with edge-case enumeration and
  per-case unit-test mapping); concurrent-event-source recorded as not applicable with rationale.
- CHANGELOG literal format: Checked — Implementation Order step 8 gives the entry in the project's
  `**Bold Title** (#N):` format under `### Changed`.
- Not-applicable rationale: Checked — suppression semantics and concurrency each carry a rationale.

### Decision-gate matrix

| Gate input | Allowed outcome | Exit code | Required next action | Mirror surface |
| --- | --- | --- | --- | --- |
| Review-sourced evidence with `state == CHANGES_REQUESTED` | `NEEDS_REVISION` | 1 | Loop counts unresolved threads; item agent fixes findings | Unchanged in all four verdict sites and in `codex_response_priority` |
| `codex_response_is_blocking` matches | `NEEDS_REVISION` | 1 | Same as above | Unchanged |
| Usage-limit or environment-error notice | `UNAVAILABLE` | 3 | Platform reported unavailable; loop applies the configured unavailable policy | Unchanged |
| Clean signal in opening paragraph, no fence, disqualifier-free residue | `APPROVED` | 0 | Platform reported clean | **Changed** — stricter than today |
| Clean signal present but fence marker, negation, hedge, or actionable token found | `NEEDS_REVISION (unrecognized response format — safe-fail)` | 1 | Item agent inspects the stderr diagnostic and re-triggers or fixes | **Changed** — this is the new false-`NEEDS_REVISION` surface |
| No clean signal at all | `NEEDS_REVISION (unrecognized response format — safe-fail)` | 1 | Same as above | Unchanged |
| No terminal evidence within the poll window | `TIMED_OUT` | 2 | Treated as unavailable | Unchanged |

Example bodies for each changed row are enumerated in the Parser-risk addendum (E1–E15) and mapped to named
test scenarios, so the matrix, the examples, and the tests are the same set.

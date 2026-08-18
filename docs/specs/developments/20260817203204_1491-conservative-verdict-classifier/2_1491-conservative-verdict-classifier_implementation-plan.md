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
— as of this revision — **no truncation step of any kind**: either the entire body is byte-for-byte (modulo
whitespace runs) one of the evidenced clean-response shapes from its first character to its last, or it
safe-fails to `NEEDS_REVISION`. `codex_response_is_blocking` is unchanged — still a block-list, unchanged
priority ordering, PR #1490's `CHANGES_REQUESTED` short-circuit untouched — because its failure direction is
the opposite one and a false negative there is unsafe, so applying this same "exact evidence only" discipline
to it would be unsafe in the other direction (see Decision 4). **This "unchanged" claim holds only if
`codex_strip_not_only_idiom`'s call inside `codex_response_is_blocking` is retained — corrected this round
per Codex GitHub finding `3803959040`, which caught an earlier revision scheduling that call for deletion,
reproduced here as a real false-blocking regression (`CODEX_MERGE_REFUSAL_PATTERN` matches "not only … merge"
constructions without the strip).**

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

**Estimated complexity**: **M**

**Rationale**: The shipped code is smaller again than the design it replaces: one function rewritten
(`codex_response_is_approved`), one helper (`codex_normalize_whitespace`, unchanged), and one data structure
(`CODEX_APPROVED_TEMPLATES`, still an array of one element, now longer because it includes the footer text).
`CODEX_FOOTER_OPENING_LITERAL` and `codex_strip_codex_footer` — the helpers that performed the truncation this
revision removes — are **deleted outright**, not deprecated in place, because nothing in the redesigned
function calls them and Decision 5 already established (in the prior revision) that nothing else in the file
did either. The work is still medium, not small, because the test corpus this contract change affects is
large (**247** `codex_*` assertions, confirmed by direct count against the real file this round — see the
Verification Log) and the disposition delta is real: **5 scenarios assert `VERDICT: APPROVED`** — 2 real,
existing scenarios (`codex_clean_root_review_comment`, `codex_full_root_review_comment`) whose bodies must be
updated to append the complete, verbatim vendor footer (under the prior, truncate-then-match design a
footer-less fixture matched because the footer was discarded before comparison; under this no-truncation
design the same fixture no longer matches unless the footer text is actually present), plus **3 new
scenarios** authored with the footer built in from the start (`codex_real_vendor_footer_clean_root_comment`,
`codex_sha_full_length_approved_root_comment`, `codex_irregular_whitespace_template_approved_root_comment`).
**`codex_real_vendor_footer_clean_root_comment` is corrected this round from "already existing" to "new" — see
Codex GitHub finding `3803807958` and the round-7 audit in the Verification Log** — an earlier revision of
this document wrongly claimed it already existed; it did not, and this correction, together with a full
re-audit of every other existing-scenario claim, is this round's primary change. See "Test disposition" for the
full, named, ground-truth-verified delta.

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
| Assertion inventory (pre-plan baseline) — **re-derived directly from the file this round, not carried forward** | `grep -c '^run_test ' test-pr-review-loop.sh`; `grep -c 'run_test "codex_' test-pr-review-loop.sh`; `grep 'run_test "codex_' test-pr-review-loop.sh \| grep -c 'VERDICT: APPROVED'` | **620** total `run_test` assertions (corrects an earlier revision's "628," which this round's re-count does not reproduce); **247** `codex_*` assertions (confirmed, unchanged); **27** assert `VERDICT: APPROVED` (confirmed, unchanged) — see the round-7 audit row below for the full by-name reconciliation of which 27 |
| Loop coupling | `grep -n "codex-github-reviewer\|codex_response" scripts/development-workflow/pr-review-loop.sh` | single hit at line 790 (script path resolution). `pr-review-loop.sh` consumes only the verdict line and exit code, so no loop change is required |
| Real clean Codex root comment — re-fetched live this round | `gh api repos/lhpaul/ai-dev-framework-template/issues/1489/comments --jq '.[] \| select(.user.login\|test("codex";"i")) \| .body'` | `Codex Review: Didn't find any major issues. Swish!` + `**Reviewed commit:** \`87aaefceff\`` (10 lowercase hex chars) + the `<details>` "About Codex in GitHub" footer. Apostrophe confirmed straight ASCII (`0x27`) via `od -c`, not a curly quote |
| Real findings Codex reviews — ALL 12 re-fetched live this round | `gh api repos/lhpaul/ai-dev-framework-template/pulls/1490/reviews --jq '.[] \| select(.user.login\|test("codex";"i")) \| .body'` | All 12 review bodies on PR #1490 (its full review history) are structurally identical: `\n### 💡 Codex Review\n\nHere are some automated review suggestions for this pull request.\n\n**Reviewed commit:** \`<10-hex-char SHA, one per review>\`\n    \n\n<details>…</details>`. **None contains a clean-signal phrase in its visible text** — the body is Codex's generic "a review was submitted" wrapper; the actual verdict for this evidence type is carried by the review's `state` field (`COMMENTED` in every one of these 12), which Decision 3's precedence table already routes around prose parsing entirely. This means **none of the 12 #1490 captures is eligible to become an `is_approved` template** — they are not evidence of a clean-response shape, they are evidence of the review-submission wrapper shape, which is out of scope for this function |
| Footer — byte-identical across all 13 real sources, **whole footer, not just its opening line, re-verified this round** | Python `set()` comparison of the substring from `<details>` through end-of-body, extracted from the #1489 root-comment capture and all 12 #1490 review captures, re-fetched live this round | All 13 collapse to **exactly 1** unique footer string once a single trailing `\n` present only in the #1489 Issues-API capture (an API-transport artifact, not vendor content — the Issues and Pulls-reviews endpoints trail the body differently) is stripped; whitespace normalization already absorbs that difference regardless, so no special-case handling was added for it. No wording divergence found anywhere in the footer body (the bulleted list, the chatgpt.com settings link, and the trailing sentence are byte-identical, including the same U+2139/U+FE0F emoji byte sequence `342 204 271 357 270 217`, across all 13 sources) |
| Commit-SHA field observed across all 13 real sources | `grep -oE "Reviewed commit:\*\* \`[0-9a-f]+\`"` on all 13 captured bodies | All 13 show exactly 10 lowercase hex characters. The placeholder bound (`{7,40}`) is nonetheless drawn from git's own documented abbreviated-SHA range, not from this single observed length — see Decision 2 for why a narrower, observation-only bound was rejected |
| Tooling identity confirmed for this review round | `sed 2>&1`, `grep --version`, `awk --version` (via `/usr/bin/{sed,grep,awk}` explicitly) | BSD `sed` (rejects GNU long-option syntax), `grep (BSD grep, GNU compatible) 2.6.0-FreeBSD`, one-true-awk `20200816` — confirms the same macOS BSD toolchain this plan has targeted throughout |
| Open PRs on the same surface | `gh pr list --state open --limit 50` | zero open pull requests in the repository at check time |
| Repository mode | `grep -nE "^mode:\|^workflow_hub:\|^product_repo:" .ai-dev-workflow.yaml` | no key present → `single_repo`; this repository owns the plan |
| Codex GitHub finding `3803545669` (P1, round 6) closed by removing truncation | `codex_response_is_approved` re-executed, unmodified from Code Samples, against a body reading template + `CODEX_FOOTER_OPENING_LITERAL` (the footer's opening line only, not the complete footer) + `Rename the unsafe function.` | `NEEDS_REVISION` (exit 1) — the opening-line-only construction no longer reproduces the required complete-footer literal, so it fails the whole-body match on its own terms, independent of what follows it |
| **Codex GitHub finding `3803807958` (P1, round 7): `codex_real_vendor_footer_clean_root_comment` does not exist** | `grep -rl "codex_real_vendor_footer_clean_root_comment" scripts/`; `grep -rl "About Codex in GitHub" scripts/` | Confirmed correct — both return nothing. This round's document previously described this scenario as already implemented ("exists — keep, verdict unchanged"). It is not implemented anywhere in the repository. Corrected: reclassified as a new scenario to be added (see the round-7 audit row immediately below and the corrected Test disposition) |
| **Codex GitHub finding `3803807963` (P2, round 7): Step 6 of the smoke-test runbook truncated a multi-line review body with `head -1`** | `gh api .../pulls/1490/reviews --jq '[.[] \| select(...)][0].body' \| wc -l` vs. the same query piped through `\| head -1` | Confirmed correct — the real review body is 24 lines; `head -1` after the `--jq` pipe returned only the first physical line (a truncated `### 💡 Codex Review` header fragment), not one complete review body. Fixed by moving the array-index selection inside the jq expression (`[.[] \| select(...)][0].body`), which correctly emits exactly one complete, multi-line body. Grepped the whole document set for every other `head -1`/`head -n1`/`head -n 1` instance applied to potentially multi-line content: **one instance found, the one above; no others exist** |
| **Round-7 full re-audit of every "exists"/"kept"/"unchanged"/"retargeted" scenario-name claim against the real `test-pr-review-loop.sh`** — performed because the finding above was the second time this plan's completeness/verification claims were wrong (round 4's "no stale passage found" was also incomplete) | For every `codex_*_root_comment`-style name this document referenced as already implemented: `grep -c -- "<name>" test-pr-review-loop.sh`, cross-checked against `grep -oE 'run_test "codex_[a-zA-Z0-9_]+"' test-pr-review-loop.sh \| sort -u` (247 real names) and, for keyword-level near-miss checking, `grep -in "<keyword>" test-pr-review-loop.sh` | **Extensive additional fabrication found, well beyond the one Codex named.** Of the ~40 scenario names this document claimed already existed, **14 more do not exist anywhere in the repository** (not merely under this name — the underlying test mechanism itself was never implemented): `codex_bare_approved_punctuation_root_comment`, `codex_two_clean_signals_one_line_root_comment`, `codex_adjacent_clean_signals_root_comment`, `codex_uppercase_clean_signal_root_comment`, `codex_emoji_clean_signal_root_comment`, `codex_adjacent_signal_second_contains_no_root_comment`, `codex_adjacent_signal_second_contains_didnt_root_comment`, `codex_disqualifier_diagnostic_emitted`, `codex_footer_truncation_keeps_blocking_root_comment`, `codex_footer_markup_lookalike_tag_names_not_truncated_root_comment`, `codex_nonfooter_details_block_not_truncated_root_comment`, `codex_metadata_token_as_directive_root_comment`, `codex_underscore_prefixed_lookalike_root_comment`, `codex_unenumerated_actionable_sentence_after_signal_root_comment`. Additionally, **two real scenarios were misclassified by disposition, not just by existence**: `codex_long_review_body_no_sigpipe` and `codex_long_root_comment_no_sigpipe` are real and currently assert `VERDICT: APPROVED` (bodies use the pre-plan block-list phrase `No blocking issues found.` inside a 200 000-character SIGPIPE-safety fixture) — this document had placed them in "Group UNCHANGED-NEEDS_REVISION" ("already `NEEDS_REVISION`, stays that way"), which is the opposite of their real, current, verified disposition; they belong in Group RETARGETED. Full corrected inventory, and the complete list of every name checked, is in the rebuilt Test disposition section below |
| **Codex GitHub finding `3803959040` (P2, round 8): deleting `codex_strip_not_only_idiom`'s call inside `codex_response_is_blocking` reintroduces a false-blocking regression** | The real, unmodified `CODEX_BLOCKING_PATTERN`/`CODEX_MERGE_REFUSAL_PATTERN`/`CODEX_NEGATION_WORDS` and `codex_strip_not_only_idiom` extracted from `codex-github-reviewer.sh`, executed against `This is not only safe to merge but looks good.` with and without the strip | Confirmed correct. **Without** the strip: matches `CODEX_MERGE_REFUSAL_PATTERN` — `is_blocking` returns `TRUE` (false blocking). **With** the strip (the production script's actual, current behavior): no match — `is_blocking` returns `FALSE` (correct). An earlier revision of this document scheduled the function for outright deletion "plus its call in `codex_response_is_blocking`," which is exactly the regression reproduced here. Corrected: the function and its `is_blocking` call site are both kept; only the (already-replaced) `is_approved` call site is gone — see Decision 4 |
| **Round-8 sibling-coupling check: does any other symbol scheduled for deletion have a real call site inside `codex_response_is_blocking`?** | `awk 'NR==599,NR==641' codex-github-reviewer.sh \| grep -vE '^\s*#' \| grep -oE '\bcodex_[a-zA-Z_]+\b\|\bCODEX_[A-Z_]+\b' \| sort -u` (filters comment-only lines, so only real code references count) | `codex_response_is_blocking`'s real function body references exactly four symbols: `CODEX_BLOCKING_PATTERN`, `codex_strip_not_only_idiom`, `codex_strip_quoted_spans`, and itself. All four are already in this document's "Keep unchanged" list (after this round's correction). **No other symbol on the deletion list has any real call site inside `codex_response_is_blocking`** — the coupling this round found is isolated to the one symbol Codex named. Also checked `codex_combine_terminal_evidence` (the function whose comment references `is_blocking`'s "blocking always wins" invariant): its real body calls only `codex_response_is_blocking`, `codex_response_is_environment_error`, `codex_response_is_usage_limit`, and `codex_select_terminal_evidence` — all four already kept, none scheduled for deletion |
| **`codex_not_only_safe_to_merge_stays_approved_root_comment`'s real, current disposition re-verified with the strip retained** | The real `codex_response_is_blocking` (strip retained) composed with this plan's whole-body `codex_response_is_approved`, against the scenario's real body: `"This is not only safe to merge but looks good.\n\n**Reviewed commit:** \`face7777\`"` | `is_blocking`: `FALSE`. `is_approved`: `FALSE` (does not reproduce the template). Composed verdict: **`NEEDS_REVISION (unrecognized response format — safe-fail)`** — unchanged from what this document's round-7 Group RETARGETED entry already stated; the round-8 fix does not change this scenario's expected string, because the bug was in the deletion-list instruction, not in the disposition table. Also re-verified the two sibling "not only" scenarios (`codex_not_only_idiom_stays_approved_root_comment`, `codex_not_only_idiom_uppercase_stays_approved_root_comment`) — neither contains "merge," so neither is affected by the strip either way; both still resolve to the same safe-fail |
| **Codex GitHub finding `3804088454` (P2, round 9): the round-8 `grep -c "codex_strip_not_only_idiom"` verify command counts comment lines as code** | `grep -c "codex_strip_not_only_idiom" codex-github-reviewer.sh` (raw) vs. `grep -v '^[[:space:]]*#' codex-github-reviewer.sh \| grep -c "codex_strip_not_only_idiom"` (comment-filtered), both run against the real file today | Confirmed correct. Raw: **5** today (2 comments in `is_blocking`'s own rationale text + 1 definition + 2 calls); comment-filtered: **3** today (1 definition + 2 calls). After a correct implementation (only the `is_approved` call site removed): raw would read **4**, not 2 as the round-8 verify command claimed; comment-filtered correctly reads **2**. **Every `grep -c`/`grep -n` count-based verify command in this document and the smoke-test runbook was re-audited for the same defect class — see the round-9 audit row below for the full table** |
| **Codex GitHub finding `3804088461` (P2, round 9): the round-8 `git diff origin/develop -- ... \| grep -n "codex_response_is_blocking\|codex_strip_not_only_idiom"` check cannot prove the function is unchanged** | Mutated a copy of the production script by removing `-i` from `codex_response_is_blocking`'s internal `grep -qiE "$CODEX_BLOCKING_PATTERN"` call, then ran the round-8 check against it | Confirmed correct. The mutation produced **zero output** from the round-8 check — invisible, because the diff line for that mutation contains neither `codex_response_is_blocking` nor `codex_strip_not_only_idiom` as a substring. Replaced with `diff <(git show origin/develop:… \| awk '/^codex_response_is_blocking\(\)/,/^}/') <(awk '/^codex_response_is_blocking\(\)/,/^}/' codex-github-reviewer.sh)` — run against the real tree: **exit 0, no output** (unchanged); run against the same mutated copy: **exit 1**, output shows exactly the mutated line. This form has no blind spot because it compares every line in the function's range, not only lines containing a searched substring |
| **Round-9 full audit of every verification command in this document and the smoke-test runbook against both defect classes** (`grep -c` counting non-executable matches; `grep` over a diff used to prove a region is unmodified) — performed because rounds 8 and 9 both introduced defects in verification commands added the round before, and the coordinator required an exhaustive audit, not a two-instance patch | Every `*Verify*:`/`grep`/`diff`/`bash -n` command in both documents, individually executed against the real tree and classified | **Two additional instances of Class 1 found and fixed beyond the two Codex named**: (a) the Implementation Order step 2 deletion-list absence check (`grep -nE "CODEX_NEGATED_APPROVAL\|CODEX_CLEAN_SIGNAL\|…"`) is comment-vulnerable — `codex_response_is_blocking`'s, `codex_strip_quoted_spans`'s, and `CODEX_BLOCKING_PATTERN`'s own unchanged rationale comments mention `CODEX_NEGATED_APPROVAL_PATTERN`/`CODEX_APPROVAL_PATTERN` a combined 8 times; raw **13** matches today, comment-filtered **5** (all real code); fixed by comment-filtering and by adding the missing `CODEX_APPROVAL_PATTERN` term (present on the deletion list, absent from this specific check); (b) the identical smoke-test-runbook copy of the same check, same fix. **No other command needed a fix**: file-listing (`grep -l`/`-rl`) and pure-absence (`grep -rl <literal>` returning nothing) checks are sound because they test whether a string appears anywhere at all, not an exact count with semantic meaning or a region's invariance; the `run_test`-count checks (`^run_test `, `run_test "codex_`) are structurally low-risk (executable-invocation syntax unlikely to appear in prose comments) and were confirmed empirically to have zero comment-line matches in the real file; the round-7 scenario-existence audit methodology (`grep -c -- "<name>"`, cross-checked against the real `run_test "codex_…"` name list) remains sound as a boolean existence check, not an exact-count claim. Full per-command disposition table is in the round-9 report to the parent orchestrator |

### Predicate validation (reproducible)

The decision rule below — the exact mechanism this plan ships, not an illustrative approximation — was
executed against all 13 real captured Codex bodies (the #1489 root comment and all 12 #1490 reviews) and
against every synthetic fixture body this plan's test corpus has ever used, on macOS (BSD `sed`, BSD `grep`,
BSD `awk`, via their `/usr/bin/` paths). The implementer must re-run the same checks on GNU tooling in CI.

<!-- workflow-shell-contract: bash -->

```bash
codex_normalize_whitespace() {
  local text
  text=$(tr '\n\t\r' '   ' <<< "$1" | tr -s ' ')
  sed -E 's/^ //; s/ $//' <<< "$text"
}
CODEX_APPROVED_TEMPLATES=(
  '^Codex Review: Didn'"'"'t find any major issues\. Swish! \*\*Reviewed commit:\*\* `[0-9a-f]{7,40}` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> \[Your team has set up Codex to review pull requests in this repo\]\(https://chatgpt\.com/codex/cloud/settings/general\)\. Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment "@codex review"\. If Codex has suggestions, it will comment; otherwise it will react with 👍\. Codex can also answer questions or update the PR\. Try commenting "@codex address that feedback"\. </details>$'
)
normalized=$(codex_normalize_whitespace "$body")
grep -qE "${CODEX_APPROVED_TEMPLATES[0]}" <<< "$normalized"
```

**Result**: the real #1489 root comment (raw, untruncated, footer included) matches (exit 0, `APPROVED`); all
12 real #1490 review bodies do not match (exit 1, `NEEDS_REVISION` — as expected, since none carries a
clean-signal phrase at all, see the Verification Log row above); every construction found across all five
prior review rounds of this plan's history (`unapproved`, `un_approved`, `Approved. Revert.`,
`Looks good. Remove the authentication check.`, `Looks good. Commit this.`, the round-3 footer-paragraph
exploit, the round-4 markup lookalike, the round-4 one-byte footer mutation, and the round-5
`Looks good, or is it?`) does not match; **this round's construction — template + the footer's opening line
only (not the complete footer) + `Rename the unsafe function.` (Codex GitHub finding `3803545669`) — does not
match**, because the required literal is now the complete footer text, and an opening-line-only body is not a
reproduction of it; a body reading template + the **complete** footer + any trailing content after
`</details>` does not match, for the same whole-body reason; and a one-byte mutation anywhere inside the
footer (not only its opening line — verified at three separate points: mid-body, near `</details>`, and inside
the settings URL) does not match. Full per-construction output is in "Testing Strategy".

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved artifact base branch | `develop` | Parent orchestrator handoff for issue #1491 plus the branching section of `AGENTS.md` | 2026-08-17, repo `55b2df5d` | This invocation (issue #1491) plus same-surface open PRs touching `scripts/development-workflow/codex-github-reviewer.sh`; `gh pr list --state open` returned zero open PRs | `Verified` |
| Artifact owner / repository mode | `single_repo` — this repository owns the plan | `.ai-dev-workflow.yaml` (no `mode`, `workflow_hub`, or `product_repo` key) | 2026-08-17, repo `55b2df5d` | Current invocation only | `Verified` |
| Ready-phase reviewer that consumes this classifier | `review.on_ready.github: [codex-github]` | `.ai-dev-workflow.yaml` | 2026-08-17, repo `55b2df5d` | Current invocation; no open PR modifies `.ai-dev-workflow.yaml` | `Verified` |
| Codex clean-response wire format `codex_response_is_approved` must accept | **Revised this round.** Exactly one evidenced clean-response template, now defined over the **entire** body: the literal `Codex Review: Didn't find any major issues. Swish!` sentence, the literal `**Reviewed commit:**` marker and a backtick-quoted, lowercase-hex commit SHA of 7–40 characters (git's documented abbreviated-to-full SHA-1 range; only 10-character SHAs are directly observed so far), followed by the **complete, verbatim vendor `<details>` footer** (the "About Codex in GitHub" block through its closing `</details>`, including the bulleted list and the `chatgpt.com` settings link) — whitespace-normalized, with no truncation step of any kind. The generic `### 💡 Codex Review` review-submission wrapper (all 12 #1490 captures) is explicitly **not** a clean-response template — it carries no clean-signal text and is routed by the review `state` field instead (Decision 3, unchanged) | Live GitHub API responses on PR #1489 (root comment) and all 12 reviews on PR #1490, all re-fetched live this round | 2026-08-18, repo `26b5dada` | Current invocation; vendor-controlled surface, re-verified at implementation start per Protocol 02 | `Verified` |
| Number of templates evidenced | Exactly 1, unchanged from the prior revision. This is intentionally narrow — see Decision 2 for why inventing additional templates (e.g. a `No blocking issues found.` shape that appears nowhere in the two currently-accessible live sources) is explicitly out of scope for this plan, and Risks & Mitigations for the resulting operational trade-off | The two live sources listed above; no other source was consulted, per this round's explicit "never invented, never generalized" instruction | 2026-08-18, repo `26b5dada` | Current invocation | `Verified` |
| Footer text is byte-identical (not merely its opening line) across all 13 real sources | **New this round, required before binding the footer into the exact-match template (see Decision 5).** Confirmed: exactly 1 unique footer string across all 13 captures, once one API-transport-only trailing newline is stripped from the #1489 Issues-API capture; whitespace normalization absorbs that difference regardless | Python `set()` comparison of the `<details>`-through-end-of-body substring extracted from all 13 live captures, re-fetched this round | 2026-08-18, repo `26b5dada` | Current invocation; vendor-controlled surface, re-verified at implementation start per Protocol 02 | `Verified` |

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

That evidence motivated this plan's **third** design: apply the footer check's technique — exact comparison
against literal, live-captured evidence, with no interpretive layer in between — to the whole classifier, not
just the footer. But that design still had one interpretive step left: it truncated the body at the footer's
opening line before comparing, and trusted every byte after that line, unseen, as inert footer content. Codex
GitHub finding `3803545669` showed that trust was exactly the same class of gap as every prior round's, just
moved to a new location: a body reading the approved template, followed by the footer's opening line only (not
the rest of the footer), followed by `Rename the unsafe function.`, reproduced the *visible* (pre-truncation)
template exactly, and the discarded suffix — where the actual instruction was hiding — was never inspected by
anything. The finding was made materially more likely by this plan's own history: the footer's opening literal
is now documented verbatim inside this repository (Decision 2's code sample, the Code Samples section, and the
prior revision's Verification Log all quote it), so a future Codex review response quoting a diff that contains
that string would itself trigger truncation at the wrong point.

That is the decisive evidence behind this plan's **fourth and final** design: remove the truncation step
entirely. The footer is not a separately-trusted region any more — it is captured verbatim as part of the one
evidenced template, so the whole body, first character to last, is either an exact (whitespace-normalized)
reproduction of a real captured clean-response shape or it safe-fails. There is no vocabulary to be
incomplete, no grammar to have an unconsidered shape, no position heuristic to be gamed, and — the property the
third design still lacked — no discarded byte range for a novel construction to hide inside.

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
   clauses, no punctuation tolerance, no synonym alternation, and — as of this revision — no truncation.
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
match already rejects it without a dedicated check. Verified: a fenced-code-block wrapper around the real
template-plus-footer body fails to match (the fence characters are literal text the template does not contain)
— see "Testing Strategy."

**This closes the specific gap Codex GitHub finding `3803545669` identified in the prior revision.** Because
there is no longer a discarded byte range, there is no location left in the body where content can go
uninspected: every byte from the first character of the verdict sentence through the closing `</details>` of
the footer must be part of the one evidenced literal, or the match fails. A body reading the approved template
followed only by the footer's opening line (not its complete text) followed by arbitrary content — the exact
construction the finding raised — does not reproduce the template (the template's literal requires the
complete footer text, not just its first line) and is rejected on that basis alone, independent of what
follows it.

If the match fails, `codex_response_is_approved` returns non-zero and the caller falls through to the existing
safe-fail branch (`VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)`), or to the blocking
branch when `codex_response_is_blocking` already matched earlier in the chain (unchanged, Decision 4).

### Decision 2 — Why whole-body exact-template matching converges where every prior design did not, and the rules for extending it safely

**This is a design replacement, not an incremental fix.** The previous designs of this plan (summarized in
"Background" above) are deleted in full: `CODEX_CLEAN_SIGNAL_PATTERN`, `CODEX_CLEAN_SIGNAL_EXCISION`,
`CODEX_APPROVAL_NEGATION_PATTERN`, `CODEX_APPROVAL_HEDGE_PATTERN`, `CODEX_APPROVAL_ACTIONABLE_PATTERN`,
`CODEX_APPROVAL_DISQUALIFIER_PATTERN`, `CODEX_RESIDUE_FILLER_WORD_PATTERN`, `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN`,
`codex_excise_clean_signals`, `codex_residue_is_closed_grammar`, and `codex_response_first_paragraph` are all
removed outright — not deprecated, not left dormant. So are `CODEX_FOOTER_OPENING_LITERAL` and
`codex_strip_codex_footer` (kept by the immediately prior revision; deleted by this one — see Decision 5).
There is nothing in the final design that reads like a vocabulary list, a grammar, a token-class test, or a
truncation boundary, because every one of those was itself the recurring root cause across six review rounds
(see "Background"): each was either an open-ended enumeration over natural language, or — in the truncation
case — a boundary past which bytes were trusted without being read. Neither converges: enumeration is the
literal thesis issue #1491 was filed against, and an unread trust boundary is exactly the same failure
one level removed (see finding `3803545669`, closed in Decision 1).

**Why exact matching against live evidence does not have this failure mode.** A regex over vocabulary or
grammar defines an *infinite* language (every sentence some combination of its tokens/rules can produce) and
asks "is this input inside that language" — the review rounds kept finding new sentences inside the language
that shouldn't have been. `CODEX_APPROVED_TEMPLATES` defines a *finite* language (exactly the strings its
anchored patterns can produce, which — because every non-placeholder character is a literal — is either one
exact evidenced string or, for the one bounded field, one of a small enumerable set of exact strings). There
is no "in between" a novel sentence can occupy: it either reproduces a template exactly (whitespace aside) or
it does not, and template membership is decided by direct comparison, not by evaluating whether some
open-ended rule happens to accept it.

**`CODEX_APPROVED_TEMPLATES` — the template, and exactly what evidence it is drawn from.** The single entry
now covers the entire body, footer included:

```bash
CODEX_APPROVED_TEMPLATES=(
  '^Codex Review: Didn'"'"'t find any major issues\. Swish! \*\*Reviewed commit:\*\* `[0-9a-f]{7,40}` <details> <summary>ℹ️ About Codex in GitHub</summary> <br/> \[Your team has set up Codex to review pull requests in this repo\]\(https://chatgpt\.com/codex/cloud/settings/general\)\. Reviews are triggered when you - Open a pull request for review - Mark a draft as ready - Comment "@codex review"\. If Codex has suggestions, it will comment; otherwise it will react with 👍\. Codex can also answer questions or update the PR\. Try commenting "@codex address that feedback"\. </details>$'
)
```

- **Template 1** is drawn from the PR #1489 root-comment capture, re-fetched live this round:
  `Codex Review: Didn't find any major issues. Swish!` followed by `**Reviewed commit:** \`87aaefceff\``,
  followed by the **complete** `<details>` "About Codex in GitHub" footer, through its closing `</details>`.
  Every character is a literal from that capture **except** the commit SHA, which is the one field the
  evidence shows varies (all 13 real captures this round — the #1489 comment and all 12 #1490 reviews —
  contain a different SHA on their `Reviewed commit:` line, all 10 lowercase hex characters).
- **The footer is not a separate, truncated-away region any more — it is part of the literal, evidenced
  the same way the verdict sentence is.** Before binding to it, the footer text (the substring from
  `<details>` through the end of the body) was extracted from all 13 live captures and compared for byte
  equality (see the Verification Log). It is identical across all 13 sources, modulo one trailing newline
  present only in the #1489 capture — an artifact of the Issues API's transport, not a difference in vendor
  content, and one whitespace normalization already absorbs regardless of its source. No field inside the
  footer varies across the evidence, so **no placeholder was introduced anywhere in the footer text** — it is
  bound exactly as tightly as the evidence allows (Decision 5 has the full account of why the footer moved
  from a truncation boundary to part of the literal).
- **The SHA placeholder's bound is `[0-9a-f]{7,40}`, and it is not invented.** It is git's own documented
  abbreviated-to-full SHA-1 commit-id range (`git rev-parse --short` defaults to 7 characters and lengthens
  automatically as a repository grows to avoid collisions; a full SHA-1 is 40 hex characters). This bound is
  wider than the 10-character length every one of today's 13 real captures happens to show, deliberately: the
  SHA's length is a property of *this repository's object count*, not of Codex's wording, so a narrower bound
  tied only to today's observation would fail on tomorrow's legitimate response for a reason that has nothing
  to do with the vendor changing anything. This is the **one and only** placeholder in this plan's template.
  It cannot absorb prose — it accepts hex digits and nothing else, within a length range fixed by git's own
  specification, not by this plan's judgment call about what "looks like" a SHA.
- **No other field is a placeholder — not in the verdict sentence, and not anywhere in the footer.** "Swish!"
  is not generalized into "some flavor word," the `**Reviewed commit:**` label is not stripped or made
  optional, and no word, phrase, or markup fragment inside the footer (the settings link, the bulleted list,
  the acknowledgement sentence) is generalized either — every one of those is a literal character in the
  template, exactly as captured. A response reading `Codex Review: Didn't find any major issues.` (no
  "Swish!"), omitting the `Reviewed commit:` line, carrying only the footer's opening line instead of its
  complete text, or carrying the complete footer with any trailing content after `</details>`, does **not**
  match, and returns `NEEDS_REVISION` — see Risks & Mitigations for why this is an accepted, disclosed trade
  rather than an oversight.
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
  bound, or reintroducing any form of truncation before matching — is never safe without the review above,
  because it can only increase the false-`APPROVED` rate. This is the same asymmetry every earlier revision of
  this plan already stated for its own token lists; it applies identically here, at the template level, because
  a template is exactly as much an enumerable admission list as a token was, and a truncation boundary is
  exactly as much an unreviewed trust surface as a vocabulary gap was (Decision 5).

**The residual gap this design accepts, disclosed explicitly.** With one template evidenced, the classifier
will safe-fail on any genuinely clean response that does not reproduce that template's exact wording — a
vendor phrasing change, a different flavor sentence than "Swish!", a missing `Reviewed commit:` line, or a
reworded vendor footer (the settings link text, the bulleted-list wording, or the acknowledgement sentence
changing in any way) — or the generic review-wrapper format ever gaining clean-signal text of its own. Binding
the footer into the template — rather than continuing to strip it — makes this trade strictly larger than the
prior revision's: a footer wording change now also produces a false `NEEDS_REVISION`, where under the
truncate-then-match design it would not have. This is the accepted trade the human decision made explicitly
this round (see "Why exact matching…" above and Risks & Mitigations): the failure direction is always safe
(more `NEEDS_REVISION`, never a false `APPROVED`), and the fix — capture the new wording live, add a template
with a stated, evidence-derived bound for any variable field — is the same fix this plan has always prescribed
for its riskiest lever, just now applied to one array instead of several.

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

`codex_response_is_blocking` is **kept, with zero edits — not even the drop of a call site.** `CODEX_BLOCKING_PATTERN`,
`CODEX_MERGE_REFUSAL_PATTERN`, `CODEX_NEGATION_WORDS`, `codex_strip_quoted_spans`, and **`codex_strip_not_only_idiom`
and its call inside `codex_response_is_blocking`** are all **kept unchanged** — this redesign does not touch
any of them. **This corrects Codex GitHub finding `3803959040` (P2, round 8): an earlier revision of this
document scheduled `codex_strip_not_only_idiom` for deletion "plus its call in `codex_response_is_blocking`,"
which is a real behavioral regression, re-executed and confirmed this round against the real, unmodified
production constants** — reasons below. The claim "`codex_response_is_blocking` is unchanged" is true **only
conditional on retaining this one call site**; every place that claim appears in this document (this Decision,
the Summary, the Verification Log, Risks & Mitigations) now states that condition explicitly.

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
- **This revision removes the last case where the approval path depended on `is_blocking` to prevent a false
  `APPROVED`.** Under the prior (truncate-then-match) revision, a refusal placed after the footer's opening
  line was invisible to `is_approved` on its own — `is_approved` alone would have returned `APPROVED` for that
  body, and only `is_blocking`'s independent, untruncated scan of the same raw body (evaluated first at every
  verdict site, Decision 3) kept the composed verdict correct. Under this revision, that case no longer exists:
  `is_approved` reads the entire body itself, so inserting a refusal anywhere — including inside the footer —
  already breaks the whole-body exact match on its own, with no help from `is_blocking` needed. `is_blocking`
  still runs first at every verdict site and still independently flags a recognized refusal (verified: edge
  case E22 below), but it is now redundant-but-harmless for this specific composition, not load-bearing for it:
  it upgrades an already-correct `NEEDS_REVISION` safe-fail to the more specific blocking verdict, it does not
  prevent a false `APPROVED` that `is_approved` would otherwise have produced. This is a direct consequence of
  Decision 1's whole-body match, not a new mechanism added to `is_blocking` itself.

**`codex_strip_not_only_idiom` is kept — the function definition, and its one remaining call site inside
`codex_response_is_blocking`.** This corrects a self-contradiction in an earlier revision of this document,
which claimed the function was "deleted entirely" in the same breath as describing it as "kept… in
`is_blocking`" — those two statements cannot both be true, and Codex GitHub finding `3803959040` caught the
one that mattered: deleting the real, currently-load-bearing call site.

**Why it is load-bearing for `is_blocking`, reproduced by execution this round (not asserted):**
`CODEX_MERGE_REFUSAL_PATTERN` is built from `CODEX_NEGATION_WORDS`' bare `not` alternative plus
`[^.!?;,]*(be[[:space:]]+)?merged?` — the exact same construction that motivated `codex_strip_not_only_idiom`
for `is_approved` in the first place, now inherited by `is_blocking` once `CODEX_BLOCKING_PATTERN` absorbed
`CODEX_MERGE_REFUSAL_PATTERN` (this is documented in the production script's own comment above
`codex_response_is_blocking`, citing PR #1490 finding `3799277922`). Running the real, unmodified constants
extracted from `codex-github-reviewer.sh` against `This is not only safe to merge but looks good.`:

```text
WITHOUT the codex_strip_not_only_idiom call: MATCHES CODEX_BLOCKING_PATTERN — is_blocking returns TRUE (false blocking)
WITH the codex_strip_not_only_idiom call:    no match — is_blocking returns FALSE (correct)
```

Deleting the call, as an earlier revision of this document scheduled, reintroduces exactly the false-positive
`CODEX_MERGE_REFUSAL_PATTERN` was already known to produce on this idiom — a genuinely clean response
containing "not only … merge" in the same clause, with no intervening `.!?;,`, would be misclassified as an
explicit merge refusal.

**What is actually removed, and why that removal is still correct.** The call site inside the *original*
`codex_response_is_approved` (the pre-plan function this revision fully replaces, not edits in place) is gone
— but that is a consequence of replacing the entire function body with the whole-body exact-template match
(Decision 1), which performs no prose normalization of any kind and therefore has no use for any stripping
helper. Nothing is deleted from `is_approved` by name; the function that called
`codex_strip_not_only_idiom` no longer exists in its old form at all. This is the same distinction Decision 2
already draws for every other now-unused prose-matching symbol — the difference for
`codex_strip_not_only_idiom` specifically is that, unlike those other symbols, it still has one real,
load-bearing caller left (`is_blocking`), so the function itself is not obsoleted, only one of its two call
sites is.

### Decision 5 — The vendor `<details>` footer is captured verbatim as part of the exact-match template; it is no longer truncated before classification

**This decision reverses the prior revision's Decision 5.** The prior revision truncated the body at the
footer's opening line via `codex_strip_codex_footer`/`CODEX_FOOTER_OPENING_LITERAL`, matched only the visible,
pre-truncation portion, and trusted everything from the opening line onward as inert footer content it never
inspected. Codex GitHub finding `3803545669` showed that trust was exactly the gap this plan's history keeps
finding in a new location: a body reading the approved template, then the footer's opening line only, then
`Rename the unsafe function.`, matched the visible portion exactly and was classified `APPROVED` — the
instruction hiding in the discarded suffix was never read by anything. The fresh evidence that made this more
likely, not less, is that the footer's opening literal is documented verbatim inside this very repository (the
prior revision's own plan text and Verification Log), so a future Codex review response quoting a diff
containing that literal could itself trigger truncation at the wrong point.

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
called them.** The prior revision's Decision 5 already established, and this round re-confirmed by inspecting
the production script, that `codex_strip_codex_footer` was applied **only** inside `codex_response_is_approved`
— never to `codex_response_reviews_current_head`'s SHA extraction, never to the acknowledgement branch that
matches text living inside the footer (`grep -qi "If Codex has suggestions, it will comment; otherwise it will
react with"`), and never to `codex_response_is_blocking`'s scan. All three of those already operated on the
raw, untruncated body before this round, and continue to after it, completely unaffected by this decision.

**Why the footer's text must be byte-identical across the evidence before being bound into the template — this
round's required check, not an assumption.** Binding a literal from a single capture, without checking whether
it is representative, would reintroduce exactly the risk Decision 2's governing rule forbids: a placeholder or
a lucky-guess literal standing in for content that actually varies. Before writing the template above, the
footer substring (`<details>` through end-of-body) was extracted from all 13 real captures — the #1489 root
comment and all 12 #1490 reviews, all re-fetched live this round — and compared for byte equality. They
collapse to exactly one unique string once a single trailing newline present only in the #1489 Issues-API
capture is stripped (a transport artifact of that endpoint, not a vendor-content difference; whitespace
normalization absorbs it regardless, so no special-casing was added). No field inside the footer was found to
vary, so the footer contributes zero placeholders to the template — every character of it is a literal,
exactly as tight a bound as the SHA field's `{7,40}` hex-only bound is for its one variable field (Decision 2).
If a future capture ever shows real variation inside the footer, the correct response is the same one Decision
2 already prescribes for any template field: bind the varying part as narrowly as that specific field's own
evidence and specification allow, backed by a live capture — never a wildcard, and never a return to
truncation.

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
- [ ] **Keep** `codex_strip_not_only_idiom` — **the function definition, and its call inside
      `codex_response_is_blocking` (line 639 of the current production script).** This is a correction to an
      earlier revision of this document (Codex GitHub finding `3803959040`, round 8), which scheduled the
      function and both its call sites for deletion; deleting the `is_blocking` call site is a real regression,
      reproduced this round against the real production constants: `CODEX_MERGE_REFUSAL_PATTERN` (built from
      `CODEX_NEGATION_WORDS`' bare `not` plus `merge`) matches `This is not only safe to merge but looks good.`
      without the strip, and does not match with it. **Only the call site inside `codex_response_is_approved`
      is gone** — not by an explicit deletion instruction, but because the entire function is being replaced by
      the whole-body exact-template match (Decision 1), which performs no prose normalization at all.
      *Verify*: **corrected this round (Codex GitHub finding `3804088454`, round 9) — a bare `grep -c` over this
      symbol counts comment lines as well as code**, and `codex_response_is_blocking`'s own unchanged rationale
      comment names `codex_strip_not_only_idiom` twice. Both commands below were run against the real file
      today (pre-implementation, both call sites — `is_blocking`'s and the old `is_approved`'s — still present):
      raw `grep -c "codex_strip_not_only_idiom" scripts/development-workflow/codex-github-reviewer.sh` →
      **5** (2 comments + 1 definition + 2 calls); comment-filtered `grep -v '^[[:space:]]*#'
      scripts/development-workflow/codex-github-reviewer.sh | grep -c "codex_strip_not_only_idiom"` → **3** (1
      definition + 2 calls). **Use the comment-filtered form.** After a correct implementation (the
      `is_approved` call site removed, everything else unchanged), the comment-filtered count must be **2** (1
      definition + 1 call, inside `codex_response_is_blocking`) — not 0 (function wrongly deleted entirely) and
      not 3 (the obsolete `is_approved` call site wrongly left in place). The raw (unfiltered) count would read
      **4** after a correct implementation, not 2 — do not use the raw count as the pass/fail gate.
- [ ] **Keep unchanged**: `codex_response_has_fence_marker`, `codex_strip_quoted_spans`,
      `codex_response_is_usage_limit`, `codex_response_is_environment_error`,
      `codex_response_reviews_current_head`, `codex_response_priority`, `codex_select_terminal_evidence`,
      `codex_select_review_evidence`, `codex_combine_terminal_evidence`, `codex_response_is_blocking`,
      `CODEX_BLOCKING_PATTERN`, `CODEX_NEGATION_WORDS`, `CODEX_MERGE_REFUSAL_PATTERN`, and all four
      verdict-emission sites. Note that `codex_response_has_fence_marker` and `codex_strip_quoted_spans` are
      kept **because other functions still call them** (`is_usage_limit`, `is_environment_error`,
      `is_blocking`) — `is_approved` itself no longer calls either (see Decision 1).
- [ ] **Delete** `CODEX_FOOTER_OPENING_LITERAL` and `codex_strip_codex_footer` — kept unchanged by the
      immediately prior revision, deleted outright by this one (Decision 5). Nothing in the redesigned
      `codex_response_is_approved` calls either, and nothing else in the file ever did (Decision 5 confirms
      no other caller exists).
      *Verify*: `grep -n "CODEX_FOOTER_OPENING_LITERAL\|codex_strip_codex_footer" scripts/development-workflow/codex-github-reviewer.sh`
      returns nothing.
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
- [ ] **Update** the file-header "Verdict parsing" comment block (currently describing path 2 in terms of the
      truncate-then-match contract from the prior revision) to state the whole-body exact-template contract:
      `APPROVED` requires exact reproduction (whitespace aside) of a captured clean-response shape — footer
      included, with no truncation step — from the first character of the response to the last; anything else,
      including a superset or subset of a template, safe-fails.

### Tests — `scripts/development-workflow/tests/test-pr-review-loop.sh`

- [ ] **Re-verify every scenario name in "Test disposition" against the real file before starting this work**
      (`grep -c -- "<name>" test-pr-review-loop.sh` per name) — this document was wrong twice about which
      scenarios already exist (rounds 6 and 7); do not trust the scenario lists below without re-running the
      check, since the file may have changed again between this plan's last edit and implementation start.
- [ ] Retarget the **25 real, confirmed-existing** scenarios in Group RETARGETED whose fixture bodies are not
      byte-for-byte (whitespace aside) `CODEX_APPROVED_TEMPLATES`' one entry, from `VERDICT: APPROVED` to
      `VERDICT: NEEDS_REVISION` — see "Test disposition" for the exhaustive, named, ground-truth-verified list
      (corrected this round from a false count of 18). Update each retargeted scenario's fixture-body comment
      to state the new reason (the body is not an exact template reproduction), not the superseded
      grammar-based reason.
- [ ] **Append the complete, verbatim vendor footer to the 2 real, existing scenario bodies that must continue
      to assert `VERDICT: APPROVED`** (`codex_clean_root_review_comment`, `codex_full_root_review_comment`) —
      see Group APPROVED in "Test disposition." This is a stricter requirement than the prior revision's: under
      truncate-then-match, a fixture body omitting the footer still matched (the footer was discarded before
      comparison either way); under whole-body exact matching, the same fixture no longer matches unless the
      footer text is genuinely present, because nothing is discarded any more.
- [ ] Add the **22** new scenarios listed in "New scenarios" — 15 carried forward correctly from the immediately
      prior revision (the round-6 exploit closing Codex GitHub finding `3803545669`, the
      one-byte-anywhere-in-the-footer mutation, the whitespace-normalization boundary cases, and the
      SHA-placeholder-bound cases), plus **7 corrected this round from false "exists" claims**:
      `codex_real_vendor_footer_clean_root_comment` (E1 — the classifier's primary real-response anchor; Codex
      GitHub finding `3803807958`), `codex_underscore_prefixed_lookalike_root_comment` (E15),
      `codex_unenumerated_actionable_sentence_after_signal_root_comment` (E16),
      `codex_metadata_token_as_directive_root_comment` (E18),
      `codex_nonfooter_details_block_not_truncated_root_comment` (E19),
      `codex_footer_markup_lookalike_tag_names_not_truncated_root_comment` (E20), and
      `codex_footer_refusal_rejected_by_whole_body_match_root_comment` (E22 — a new addition, not a rename; the
      pre-rename name `codex_footer_truncation_keeps_blocking_root_comment` was also confirmed absent).
- [ ] Consolidate, rather than individually re-litigate, the regression scenarios whose underlying mechanism no
      longer exists but whose scenario **is real** (confirmed via the round-7 audit — e.g.
      `codex_unapproved_prefix_root_comment`, E14) — these constructions are now trivially rejected because
      they do not reproduce a template, and the assertion itself does not change (already `NEEDS_REVISION`),
      but their comments must be rewritten to say so rather than describing removed machinery. Do **not**
      delete them: they remain valid regression coverage. **Do not assume any other "exists — keep" claim in
      this document is accurate without re-running the check above first** — this round found 14 such claims
      were false.
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

**This is the fourth design this plan has shipped**, replacing (not extending) the truncate-then-match design
of the immediately prior revision after Codex GitHub finding `3803545669` showed that design still trusted
every byte after the footer's opening line, unseen (see "Background" and Decisions 1, 2, and 5 for the full
history). Every regex and helper below was re-executed against the same macOS BSD toolchain this plan has
targeted throughout (`sed`, `grep`, `awk`, `tr`, invoked via their `/usr/bin/` paths to avoid any
interactive-shell aliasing — confirmed BSD this round: `sed` rejects GNU's long-option `--` syntax, `grep
--version` reports `BSD grep, GNU compatible`, `awk --version` reports the one-true-awk `20200816` build)
against all 13 real captured Codex bodies (re-fetched live this round), every construction found across all
six review rounds, and the full existing test corpus. See "Testing Strategy" for the complete, reproduced
verification output.

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
# The footer portion of this literal was verified byte-identical (via a
# Python set() comparison, this round) across all 13 real captures — the
# PR #1489 root comment and all 12 PR #1490 reviews — modulo one trailing
# newline present only in the Issues-API capture, which whitespace
# normalization already absorbs. No field inside the footer varies, so the
# footer contributes zero placeholders.
#
# The apostrophe in "Didn't" is a literal straight ASCII apostrophe
# (confirmed via `od -c`, not a curly quote), NOT a regex wildcard — do not
# replace it with `.` if this pattern is edited; a wildcard there would
# silently widen the match to any character, which is exactly the kind of
# unreviewed widening this design forbids.
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
  tried to explain *why* a template didn't match (e.g. "closest template was N characters different") would
  reintroduce a fuzzy-matching concept this design deliberately does not have. If operational visibility into
  false-`NEEDS_REVISION` cases is wanted later, the correct mechanism is the operational-cost logging already
  described in "Operational cost and escape hatch," not a per-call diagnostic.
- **No fence-marker check, no quote-stripping, and no first-paragraph restriction are performed inside this
  function**, unlike every prior revision. Each was a defense against a specific way a parsing layer could be
  fooled; there is no parsing layer left to fool. Verified this round (see "Testing Strategy") that a fenced,
  quoted, or off-position wrapper around the real template-plus-footer body all fail to match, with no
  dedicated check needed — the exact-match requirement already rejects any extra or reordered text.
- `codex_response_has_fence_marker` and `codex_strip_quoted_spans` remain defined and used elsewhere in the
  file (by `is_usage_limit`, `is_environment_error`, and `is_blocking`); this function simply no longer calls
  either — unchanged from the prior revision.
- Performance: this implementation is a fixed number of `tr`/`sed`/`grep` passes over the body regardless of
  its structure (no per-sentence or per-clause loop, and — as of this revision — no separate `awk` truncation
  pass either). Re-verified this round against a 200 000-character SIGPIPE-safety fixture (the real template's
  opening sentence followed by 200 000 non-matching characters): ≈0.05s, no hang, no crash, correctly
  `NEEDS_REVISION` — comparable to the prior revision's ≈0.04s (one fewer pass, one longer literal to compare;
  the two roughly offset).
- Every real captured body (all 13, re-fetched live this round), every construction found across all six
  review rounds of this plan's history, and every scenario in the pre-this-round test corpus (organized as
  Group APPROVED/RETARGETED/UNCHANGED-NEEDS_REVISION/UNTOUCHED — see "Testing Strategy") was re-verified
  against this exact implementation on BSD `sed`/`grep`/`awk`/`tr`. See "Testing Strategy" for the full,
  reproduced output and the exhaustive, named disposition delta.

---

## Parser-risk addendum

This plan is **parser-risk**: it materially changes how the response body is compared against expected
content, even though the final design has deliberately minimal "parsing" left — whitespace normalization only,
applied to the raw, untruncated body (see Decision 1). There is no footer-truncation step any more; the prior
revision's edge cases that specifically exercised truncation (footer-opening-line matching, the "does it get
discarded" question) are superseded by the whole-body edge cases below.

### Edge-case enumeration

The edge-case set below is a full replacement of every prior revision's set (E1–E26 across five rounds, then
E1–E22 after the fifth, then E1–E24 after the sixth), renumbered from 1, because most of those cases tested
mechanisms (vocabulary excision, closed-grammar clause splitting, filler-token admission, footer truncation)
that no longer exist. Every construction that was ever found to cause a false `APPROVED` across all six review
rounds is retained below as a regression case (E13–E21, plus the round-6 E23); the boundary/shape cases for the
final design are E3–E12 (each now updated to include the complete footer where the case asserts `approved`,
since the template requires it — see the "Test disposition" note on why); E22 is rewritten to describe the new
structural relationship between `is_approved` and `is_blocking`; E24 is from round 6.

**Round-7 correction — automated-test *status*, not the edge case itself, changed for seven of these rows.**
The edge cases themselves (E1, E15, E16, E18, E19, E20, E22) are unchanged and still valid; what changed is
that this document previously, incorrectly, described each of their automated `test-pr-review-loop.sh`
scenarios as already implemented. All seven are confirmed absent from the file (Codex GitHub finding
`3803807958` for E1; a full round-7 re-audit for the other six — see the Verification Log's round-7 audit row
and the corrected "Unit test mapping" table immediately below). They are now correctly scheduled as new
additions in "New scenarios," not as existing scenarios to keep or rename.

| # | Input (verbatim) | Expected | Why it is an edge case |
| --- | --- | --- | --- |
| E1 | Real captured PR #1489 root comment, in full (with its real `<details>` footer) | approved | The anchor case: the one evidenced clean-response template, in its real, untruncated wire form |
| E2 | Any of the 12 real captured PR #1490 review bodies, in full | not approved | Confirms the generic review-submission wrapper — which carries no clean-signal text at all — correctly never matches; its verdict is (and remains) driven by the review `state` field, not this function (Decision 3) |
| E3 | `Codex Review: Didn't find any major issues.` (the real template's opening sentence, `Reviewed commit:` line and the complete real footer included, but **without** `Swish!`) | not approved | The template has no optional clauses (Decision 1/2): a response missing the evidenced flavor sentence does not reproduce the template, however close it looks — including when the rest of the body, footer included, is otherwise exact |
| E4 | The real template with a **different**, still-valid SHA (e.g. `deadf00d1234`, not the exact captured `87aaefceff`) plus the complete real footer | approved | Confirms the SHA placeholder generalizes across values, not just the one literal value captured — this is what makes it a placeholder rather than a second hardcoded literal |
| E5 | The real template with a 6-character SHA plus the complete real footer | not approved | Below the `{7,40}` bound — verifies the lower edge of git's abbreviated-SHA range is enforced, not just documented |
| E6 | The real template with a 41-character SHA plus the complete real footer | not approved | Above the `{7,40}` bound — verifies the upper edge (one past a full SHA-1) is enforced |
| E7 | The real template with a 40-character (full-length) SHA plus the complete real footer | approved | Confirms the upper bound is inclusive, not an off-by-one exclusion of legitimate full-length SHAs |
| E8 | The real template with a non-hex "SHA" (e.g. `not-a-sha!`) plus the complete real footer | not approved | The placeholder accepts hex digits only — confirms it cannot be satisfied by arbitrary text, which is what makes it a bounded field rather than a general wildcard |
| E9 | The real template plus complete real footer, with unrelated prose immediately **before** the verdict sentence (e.g. `FYI: Codex Review: …`) | not approved | Exact match is whole-body (via `^...$` after normalization), not a substring/prefix test — extra leading text breaks the match |
| E10 | The real template plus complete real footer, with unrelated prose immediately **after** `</details>` (e.g. `…</details>\n\nAlso remove the auth check.`) | not approved | Same as E9, trailing direction, now evaluated **past the complete footer, not past a truncation point** — this is the case that confirms no trailing-clause exploit of any kind (the class of finding from rounds 2, 3, 5, and 6) can reach `APPROVED`: any trailing content at all, anywhere after the one evidenced literal ends, breaks the whole-body match, regardless of its wording or of how much of the footer precedes it |
| E11 | The real template plus complete real footer, wrapped in a fenced code block (`` ``` `` before and after) | not approved | Confirms no dedicated fence-marker check is needed (Decision 1): the fence characters are literal extra text the template does not contain, so the match fails on its own |
| E12 | The real template plus complete real footer, with extra/irregular whitespace (extra spaces, tabs, multiple blank lines between lines, trailing spaces, extra whitespace around the footer) | approved | Confirms `codex_normalize_whitespace` provides exactly the permitted flexibility (Decision 1) and nothing more, across the entire body including the footer |
| E13 | The real template plus complete real footer, case-altered (e.g. `codex review: didn't find any major issues. swish!` / lower-cased footer text) | not approved | Confirms there is no case-insensitive matching beyond what the captures themselves show (Decision 1's explicit prohibition), for the footer as much as for the verdict sentence |
| E14 | `This change remains unapproved.` | not approved | Round 1's boundary-lookalike construction — trivially rejected now: it is not a reproduction of any template |
| E15 | `This remains un_approved.` | not approved | Round 1's underscore variant — same reason as E14 |
| E16 | `Looks good. Remove the authentication check.` | not approved | Round 2's disqualifier-list gap (Codex GitHub finding `3800167486`) — same reason |
| E17 | `Approved. Revert.` | not approved | The residual gap the zero-tolerance grammar disclosed but could not close (Decision 2 of an earlier revision) — now genuinely closed, not merely accepted, because it was never a reproduction of any template to begin with |
| E18 | `Looks good. Commit this.` | not approved | Round 3's vendor-metadata-token gap (Codex GitHub finding `3803050745`) — same reason |
| E19 | `Looks good.` followed by a **non-vendor** `<details>` block containing `Rename the unsafe function.` | not approved | Round 1's over-broad footer-truncation regex (Codex GitHub finding `3800167489`) — under this revision there is no truncation step at all to over-match; the body simply does not reproduce the one evidenced literal, regardless of what any `<details>`-shaped text inside it says |
| E20 | `Looks good.` followed by `<details-not-footer><summary-note>About Codex in GitHub</summary-note>` then `Rename the unsafe function.` | not approved | Round 4's tag-name-flexible footer-truncation regex (Codex GitHub finding `3803189273`) — same reason as E19: there is no tag-name surface left to be flexible about, because there is no truncation step left to apply a tag-name pattern to |
| E21 | `Looks good, or is it?` | not approved | Round 5's filler-composed-hedge construction (Codex GitHub finding `3803306915`) — the construction that motivated the third design; trivially rejected because it is not a reproduction of any template |
| E22 | The real template plus complete real footer, with `This must not be merged.` inserted inside the footer (e.g. immediately after `</summary>`) | not approved (blocking branch) | **Rewritten this round to describe the new structural relationship.** Under the prior (truncate-then-match) revision, only `codex_response_is_blocking`'s independent scan of the untruncated body prevented this body from reaching `APPROVED` — `is_approved` alone returned `APPROVED` for it, because the inserted sentence fell after the truncation point. Under this revision, `is_approved` **alone** already returns `NEEDS_REVISION` for this body: inserting any text inside the footer breaks the whole-body exact match on its own, with no truncation point for the insertion to hide behind. `is_blocking` (unchanged, Decision 4) still runs first at every verdict site (Decision 3) and still independently recognizes `must not be merged` via `CODEX_MERGE_REFUSAL_PATTERN`, so the **composed** verdict is still the more specific blocking branch — but `is_blocking` is no longer load-bearing for preventing a false `APPROVED` here, only for verdict specificity (see the new bullet in Decision 4 and Decision 5's closing paragraph) |
| E23 | The real template, followed by the footer's **opening line only** (not its complete text), followed by `Rename the unsafe function.` | not approved | **New this round — the exact construction from Codex GitHub finding `3803545669`.** Under the prior revision this reproduced the *visible* (pre-truncation) template exactly and was classified `APPROVED`, because the footer's opening line satisfied the truncation trigger and everything after it — including the injected sentence — was discarded unread. Under this revision there is no truncation trigger to satisfy: the required literal is the **complete** footer text, and a body carrying only its opening line does not reproduce that literal, so the match fails regardless of what follows the opening line |
| E24 | The real template plus complete real footer, with a single byte changed at three separate points **inside the footer body** (not its opening line): mid-sentence (`react with` → `react With`), immediately before `</details>` (`feedback"` → `feedback"K` on the preceding word), and inside the `chatgpt.com` settings URL | not approved (all three) | **New this round.** Confirms the entire footer is load-bearing for the match, not merely its opening line — a property the prior revision never needed and never tested, since only the opening line was ever compared against anything |

### Unit test mapping

There is one test file for this script: `scripts/development-workflow/tests/test-pr-review-loop.sh`. Each
edge case above gets at least one scenario there, driven through the real script with a mocked `gh` on `PATH`
(the harness convention already used by all 247 `codex_*` assertions).

**Corrected this round**: E1, E15, E16, E18, E19, E20, and E22 are marked `new` below, not `exists`. An earlier
revision of this document marked all seven as "exists — keep"; every one of the seven is confirmed absent from
`test-pr-review-loop.sh` (Codex GitHub finding `3803807958` for E1; the round-7 full audit for the other six —
see the Verification Log's round-7 audit row for the exact `grep` commands and keyword searches run against
each).

| Edge case | Scenario name |
| --- | --- |
| E1 | `codex_real_vendor_footer_clean_root_comment` (**new — corrected this round from "exists"**; confirmed absent via `grep -rl "codex_real_vendor_footer_clean_root_comment" scripts/` and `grep -rl "About Codex in GitHub" scripts/`, both empty; Codex GitHub finding `3803807958`) |
| E2 | `codex_review_wrapper_no_clean_signal_not_approved_root_comment` (new) |
| E3 | `codex_template_missing_flavor_sentence_not_approved_root_comment` (new — body updated this round to include the complete real footer, so the scenario isolates the missing-flavor-sentence defect specifically) |
| E4 | Covered by existing scenarios `codex_clean_root_review_comment`/`codex_full_root_review_comment` — both confirmed present, both use a different, non-captured SHA (`abcdefab12`, `abcabcabcabc1234567890`); no new scenario needed, but **both bodies are updated this round to append the complete real footer** (Group APPROVED; see "Test disposition") |
| E5 | `codex_sha_below_bound_not_approved_root_comment` (new — body includes the complete real footer) |
| E6 | `codex_sha_above_bound_not_approved_root_comment` (new — body includes the complete real footer) |
| E7 | `codex_sha_full_length_approved_root_comment` (new — body includes the complete real footer, required for this scenario to assert `APPROVED`) |
| E8 | `codex_sha_non_hex_not_approved_root_comment` (new — body includes the complete real footer) |
| E9 | `codex_leading_prose_before_template_not_approved_root_comment` (new — body includes the complete real footer after the template) |
| E10 | `codex_trailing_prose_after_template_not_approved_root_comment` (new — body now includes the complete real footer, with the trailing prose placed after `</details>`, not after a truncation point) |
| E11 | `codex_fenced_template_not_approved_root_comment` (new — fenced body includes the complete real footer) |
| E12 | `codex_irregular_whitespace_template_approved_root_comment` (new — irregular whitespace applied around the complete real footer too, required for this scenario to assert `APPROVED`) |
| E13 | `codex_case_altered_template_not_approved_root_comment` (new — case alteration applied to the footer text too) |
| E14 | `codex_unapproved_prefix_root_comment` (**exists — confirmed present** via `grep -n "codex_unapproved_prefix_root_comment" scripts/development-workflow/tests/test-pr-review-loop.sh`, real body `"This change remains unapproved pending further work."`; keep, comment rewritten) |
| E15 | `codex_underscore_prefixed_lookalike_root_comment` (**new — corrected this round from "exists"**; confirmed absent — `grep -c "underscore" test-pr-review-loop.sh` is 0) |
| E16 | `codex_unenumerated_actionable_sentence_after_signal_root_comment` (**new — corrected this round from "exists"**; confirmed absent — no `Remove the authentication check` construction anywhere in the file) |
| E17 | `codex_approved_revert_not_approved_root_comment` (new — the residual gap is now a positive regression test rather than a disclosed accepted risk) |
| E18 | `codex_metadata_token_as_directive_root_comment` (**new — corrected this round from "exists"**; confirmed absent — `grep -c "metadata_token"` is 0) |
| E19 | `codex_nonfooter_details_block_not_truncated_root_comment` (**new — corrected this round from "exists"**; confirmed absent — `grep -c "footer" test-pr-review-loop.sh` is 0, no footer-related scenario of any kind currently exists) |
| E20 | `codex_footer_markup_lookalike_tag_names_not_truncated_root_comment` (**new — corrected this round from "exists"**; confirmed absent, same footer-keyword-zero-hits evidence as E19) |
| E21 | `codex_or_is_it_hedge_question_not_approved_root_comment` (new) |
| E22 | `codex_footer_refusal_rejected_by_whole_body_match_root_comment` (**new — corrected this round.** An earlier revision claimed this scenario existed under the name `codex_footer_truncation_keeps_blocking_root_comment` and scheduled a rename; that pre-rename name is also confirmed absent from the file (0 hits for "footer" anywhere in it), so there is nothing to rename — this is a new addition, not a rename. Verdict on addition: `NEEDS_REVISION`, blocking branch — see the Parser-risk addendum E22 row and Decision 4/5 for why `is_blocking` upgrades but is no longer load-bearing for safety) |
| E23 | `codex_footer_opening_line_only_then_trailer_not_approved_root_comment` (new — the exact regression test for Codex GitHub finding `3803545669`) |
| E24 | `codex_one_byte_mutation_inside_footer_not_approved_root_comment` (new — parameterized or triplicated across the three footer-body positions named in the Parser-risk addendum E24 row) |

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

**This section is a full replacement, ground-truth-audited against the real `test-pr-review-loop.sh` this
round, not carried forward from an earlier revision's description of itself.** Codex GitHub finding
`3803807958` (round 7) showed that an earlier revision's claim that `codex_real_vendor_footer_clean_root_comment`
already existed was false. Because that was the second time this plan's own completeness/verification claims
were wrong (round 4's "no stale passage found" was also incomplete, corrected in round 5), every scenario name
this document references as already implemented — "exists," "kept," "unchanged," or "retargeted" — was
re-checked this round directly against the file, by name and by keyword, not assumed from an earlier
revision's prose. The result: **14 additional scenario names besides the one Codex named were also fabricated
— they do not exist anywhere in the repository** — and **2 real scenarios were misclassified by disposition**
(claimed already-`NEEDS_REVISION`, actually currently `APPROVED`). See the Verification Log's round-7 audit row
for the full list of names checked and the full list found missing. The corrected groups below reflect only
what `grep`-verified execution against the real file actually shows.

#### Group APPROVED — exactly 5 scenarios assert `VERDICT: APPROVED`

**2 real, existing scenarios with updated bodies; 3 new scenarios (not 3 existing + 2 new, as an earlier
revision incorrectly stated) — `codex_real_vendor_footer_clean_root_comment` moves from "existing" to "new"
this round, per Codex GitHub finding `3803807958`.**

| Scenario | Real/New | Body | Why it matches a template |
| --- | --- | --- | --- |
| `codex_clean_root_review_comment` | **Real — confirmed in file** (`test-pr-review-loop.sh`, current body: `"Codex Review: Didn't find any major issues.\n\n**Reviewed commit:** \`abcdefab12\`"`, no `Swish!`, no footer) | **Body updated again this round** to add the evidenced `Swish!` sentence and the **complete, verbatim real footer** — the real current body has neither | Exact reproduction of Template 1 — verdict sentence, SHA `abcdefab12` (10 hex chars, within bound), and the complete footer, whitespace-normalized |
| `codex_full_root_review_comment` | **Real — confirmed in file** (current body: `"Codex Review: Didn't find any major issues.\n\n**Reviewed commit:** \`abcabcabcabc1234567890\`"`, no `Swish!`, no footer) | **Body updated the same way** | Exact reproduction of Template 1 with a different valid SHA and the complete footer |
| `codex_real_vendor_footer_clean_root_comment` | **New — confirmed NOT in file.** `grep -rl "codex_real_vendor_footer_clean_root_comment" scripts/` and `grep -rl "About Codex in GitHub" scripts/` both return nothing (Codex GitHub finding `3803807958`, round 7). An earlier revision of this document described this scenario as "exists — keep, verdict unchanged"; that was false | Must be added: the real captured PR #1489 body, in full, including its real `<details>` footer | The literal evidence Template 1 was drawn from — whitespace-normalized, reproduces the template exactly, footer included, with no truncation step applied |
| `codex_sha_full_length_approved_root_comment` | New | Template 1 with a 40-character (full-length) SHA, plus the complete real footer | Confirms the SHA bound's upper edge is inclusive (edge case E7) |
| `codex_irregular_whitespace_template_approved_root_comment` | New | Template 1 with extra spaces, tabs, and multiple blank lines inserted between lines (including around the footer), plus trailing whitespace, plus the complete real footer | Confirms `codex_normalize_whitespace` provides exactly the permitted flexibility and nothing more (edge case E12), across the entire body |

#### Group RETARGETED — 25 real, confirmed-existing scenarios that currently assert `VERDICT: APPROVED` and do not reproduce a template

**This is 25, not 18 — the number an earlier revision of this document stated.** These are the complete real
set: `grep 'run_test "codex_' test-pr-review-loop.sh | grep -c 'VERDICT: APPROVED'` returns 27, of which 2 are
`codex_clean_root_review_comment`/`codex_full_root_review_comment` (Group APPROVED above); the remaining 25 are
listed below with their real, current bodies (verified by reading the file directly, not carried forward).
None reproduces `CODEX_APPROVED_TEMPLATES`' one entry, so all 25 retarget to `VERDICT: NEEDS_REVISION
(unrecognized response format — safe-fail)`. Keep each scenario and its body; rewrite its comment to state the
new reason:

- `codex_reaction_with_current_review` — `"If Codex has suggestions, it will comment; otherwise it will react
  with thumbs up."`
- `codex_reaction_then_late_review`, `codex_async_reaction_then_late_review`,
  `codex_main_loop_env_then_newer_review_supersedes`, `codex_latest_current_review`,
  `codex_environment_with_current_review` — all driven by a review body reading `"No blocking issues found."`
- `codex_didnt_find_issues_and_looks_good_approved_root_comment` — `"Codex didn't find any major issues and
  looks good.\n\n**Reviewed commit:** \`face9999\`"`
- **`codex_long_review_body_no_sigpipe`, `codex_long_root_comment_no_sigpipe`** — **corrected this round from
  Group UNCHANGED-NEEDS_REVISION, where an earlier revision wrongly placed them.** Real bodies:
  `"No blocking issues found. " + ("x" * 200000)` (review) and `"Codex Review: Didn't find any major
  issues.\n\n" + ("x" * 200000) + "\n\n**Reviewed commit:** \`deadf00d1234\`"` (root comment) — SIGPIPE-safety
  fixtures that currently assert `VERDICT: APPROVED` under the pre-plan block-list classifier (the
  `"No blocking issues found."`/`"Didn't find any major issues."` substrings match `CODEX_APPROVAL_PATTERN`
  today). Neither reproduces the evidenced whole-body template, so both retarget
- `codex_usage_limit_topic_mention_not_quota` — `"No blocking issues found.\n\n**Reviewed commit:**
  \`facade008f\`"`
- `codex_usage_limit_code_reviews_phrase_mention` — `"No blocking issues found. The docs correctly explain
  Codex usage limits for code reviews.\n\n**Reviewed commit:** \`facade00aa\`"`
- `codex_negation_prior_sentence_does_not_leak_root_comment` — `"The variable name is not great. No blocking
  issues found.\n\n**Reviewed commit:** \`facade00cc\`"`
- `codex_terminal_comment_quotes_env_error_not_ancillary` — `"No blocking issues found. The docs accurately
  quote: To use Codex here, create an environment for this repo.\n\n**Reviewed commit:** \`facade00ee\`"`
- `codex_unrelated_later_negation_stays_approved_root_comment` — `"Looks good overall; tests were not
  run.\n\n**Reviewed commit:** \`facade00ff\`"`
- `codex_semicolon_scoped_negation_root_comment` — `"Tests are not required for this documentation-only
  change; looks good.\n\n**Reviewed commit:** \`facade01331\`"`
- `codex_quoted_rejection_in_clean_review_root_comment` — `"No blocking issues found. The tests cover \"This
  change is not approved\".\n\n**Reviewed commit:** \`facade01551\`"`
- `codex_comma_scoped_negation_root_comment` — `"Tests are not required, but looks good.\n\n**Reviewed
  commit:** \`facade01661\`"`
- `codex_terminal_review_quotes_quota_message` — `"No blocking issues found. The docs accurately quote: `You
  have reached your Codex usage limits.`\n\n**Reviewed commit:** \`facade01771\`"`
- `codex_not_only_idiom_stays_approved_root_comment` — `"Not only does this look good, it is
  approved.\n\n**Reviewed commit:** \`facade01881\`"`
- `codex_not_only_idiom_uppercase_stays_approved_root_comment` — `"NOT ONLY does this look good, it is
  approved.\n\n**Reviewed commit:** \`facade01991\`"`
- `codex_quoted_blocker_token_stays_approved_root_comment` — `"No blocking issues found. The tests correctly
  cover the `must fix` marker."`
- `codex_unrelated_negation_before_merge_stays_approved_root_comment` — `"This is not a blocker; looks good,
  please merge.\n\n**Reviewed commit:** \`face5555\`"`
- `codex_not_only_safe_to_merge_stays_approved_root_comment` — `"This is not only safe to merge but looks
  good.\n\n**Reviewed commit:** \`face7777\`"`. **Re-verified this round (round 8) with `codex_strip_not_only_idiom`'s
  `is_blocking` call site correctly retained (Decision 4 correction, Codex GitHub finding `3803959040`):** this
  scenario's expected disposition is unchanged — `is_blocking` returns `FALSE` (the strip removes "not only,"
  leaving no negation word adjacent to "merge"), `is_approved` returns `FALSE` (does not reproduce the
  template), composed verdict remains `NEEDS_REVISION (unrecognized response format — safe-fail)`. Also
  re-checked `codex_unrelated_negation_before_merge_stays_approved_root_comment` (below) for the same class of
  risk, since its body also contains "not" and "merge": its semicolon (`"This is not a blocker; looks good,
  please merge."`) already breaks `CODEX_MERGE_REFUSAL_PATTERN`'s same-clause requirement independent of the
  not-only strip, so it is unaffected either way — confirmed by execution, not assumed.
- `codex_contraction_apostrophes_not_mangled_root_comment` — `"It's fine, doesn't need changes. No blocking
  issues found.\n\n**Reviewed commit:** \`facade02441\`"`
- `codex_inline_backtick_pair_stays_approved_root_comment` — `` "The fix looks good. See `foo.py:42` for a
  minor nit.\n\n**Reviewed commit:** `facade02991`" ``

None of these 25 real bodies is a template-plus-footer construction, so this group is unaffected by this
round's footer change specifically — the disposition (retarget) was already correct for 23 of the 25 in the
immediately prior revision; the correction this round is (a) the count (18 → 25) and (b) moving the two
SIGPIPE scenarios in from Group UNCHANGED-NEEDS_REVISION. Also rename any scenario whose name now asserts the
opposite of its expectation (the `…_stays_approved_…` and `…_approved_root_comment` suffixes on several of the
scenarios above) in the same commit that retargets it, so the name and expectation never disagree on
`develop`.

**Removed this round — false "exists" claims with no real scenario or mechanism behind them at all.** An
earlier revision listed the following as an additional Group RETARGETED bullet, "added across rounds 1–2 to
test clean-signal-vocabulary boundary conditions": `codex_bare_approved_punctuation_root_comment`,
`codex_two_clean_signals_one_line_root_comment`, `codex_adjacent_clean_signals_root_comment`,
`codex_uppercase_clean_signal_root_comment`, `codex_emoji_clean_signal_root_comment`,
`codex_adjacent_signal_second_contains_no_root_comment`,
`codex_adjacent_signal_second_contains_didnt_root_comment`. **All 7 are confirmed absent from the repository**
— not merely under a different name; keyword search (`emoji`, `uppercase`, `adjacent`, `bare_approved`,
`two_clean_signals`) found no matching mechanism anywhere in the test file. There is nothing to retarget and
nothing to rename; the claim is removed outright rather than corrected to "new," because the vocabulary-
boundary mechanism these names describe (clean-signal-vocabulary boundary conditions of the original
block-list/allow-list design) is already fully covered, under the whole-body design, by the general "does not
reproduce the template" rejection every other retained scenario demonstrates — adding 7 more instances of the
same already-proven rejection would not increase coverage, so no replacement scenarios are added for them.

#### Group UNCHANGED-NEEDS_REVISION — every other real scenario that was already `NEEDS_REVISION` and stays that way

**247 total `codex_*` assertions − 27 currently-`VERDICT: APPROVED` assertions = 220 assertions already
`NEEDS_REVISION` today** (re-derived this round: `grep -c 'run_test "codex_'` minus the `VERDICT: APPROVED`
count, both directly against the file). This group is not individually enumerated by name — doing so for 220
assertions is neither feasible nor load-bearing, since none of their dispositions change — but two corrections
apply:

- **`codex_long_review_body_no_sigpipe` and `codex_long_root_comment_no_sigpipe` are removed from this group**
  (an earlier revision placed them here as "previously-Group-A2 scenarios"); they are real, but they currently
  assert `VERDICT: APPROVED`, not `NEEDS_REVISION` — see Group RETARGETED above, where they now correctly
  belong.
- Every remaining scenario's explanatory comment must still be rewritten if it currently describes a
  now-deleted mechanism (a disqualifier match, a closed-grammar clause, a fence-marker check) as the reason it
  passes; under this revision, it passes because the body is simply not an exact template reproduction.
  Scenarios that were already testing `codex_response_is_blocking` specifically (e.g. the merge-refusal-blocking
  group) are wholly unaffected: that function did not change (Decision 4).

#### Group UNTOUCHED

All remaining `codex_*` scenarios (evidence selection and tie-breaks, usage-limit and environment-error
routing, `CHANGES_REQUESTED` state handling, trigger idempotency, thread audits, timeout and poll-interval
configuration) neither approve nor depend on approval-content parsing at all, and must pass unchanged. Any
failure among them is a genuine regression, not an intended contract change.

#### Not applicable — `codex_disqualifier_diagnostic_emitted` was never implemented; there is nothing to delete

**Corrected this round.** An earlier revision of this document described this scenario as "added in an earlier
revision" and scheduled it for deletion. It is not in the repository: `grep -c "codex_disqualifier_diagnostic_emitted"
test-pr-review-loop.sh` returns 0. There is no stderr-diagnostic-emitted test to delete, because no revision of
this plan has ever been implemented — the production script still carries only the original pre-plan
classifier (`CODEX_APPROVAL_PATTERN`, `CODEX_NEGATED_APPROVAL_PATTERN`, `codex_strip_not_only_idiom`, all
confirmed present; `CODEX_APPROVED_TEMPLATES`, `codex_normalize_whitespace`, and every symbol this plan
proposes are confirmed absent). The "Deleted" work item is removed from the Implementation Order and the
Layer-by-Layer checklist accordingly — there is no deletion step for this scenario, only a note that it was
never real.

### New scenarios

**22 new scenarios** (15 carried forward correctly from the immediately prior revision's own audit, plus 7
more this round that an earlier revision incorrectly described as already existing — see the Verification
Log's round-7 audit row for the full list of names checked). Of the 22, **3** assert `VERDICT: APPROVED` (E1,
E7, E12) and **19** assert `VERDICT: NEEDS_REVISION`.

Carried forward, unaffected by this round's correction:

- `codex_review_wrapper_no_clean_signal_not_approved_root_comment` (E2) — `NEEDS_REVISION`. Uses a real
  captured PR #1490 review body verbatim.
- `codex_template_missing_flavor_sentence_not_approved_root_comment` (E3) — `NEEDS_REVISION`. Body includes the
  complete real footer.
- `codex_sha_below_bound_not_approved_root_comment` (E5) — `NEEDS_REVISION`. Body includes the complete real
  footer.
- `codex_sha_above_bound_not_approved_root_comment` (E6) — `NEEDS_REVISION`. Body includes the complete real
  footer.
- `codex_sha_full_length_approved_root_comment` (E7) — `APPROVED`. Body includes the complete real footer —
  **required** for this scenario to assert `APPROVED`.
- `codex_sha_non_hex_not_approved_root_comment` (E8) — `NEEDS_REVISION`. Body includes the complete real
  footer.
- `codex_leading_prose_before_template_not_approved_root_comment` (E9) — `NEEDS_REVISION`. Body includes the
  complete real footer.
- `codex_trailing_prose_after_template_not_approved_root_comment` (E10) — `NEEDS_REVISION`. Trailing prose sits
  after the complete footer's `</details>`, not after a truncation point.
- `codex_fenced_template_not_approved_root_comment` (E11) — `NEEDS_REVISION`. Body includes the complete real
  footer.
- `codex_irregular_whitespace_template_approved_root_comment` (E12) — `APPROVED`. Body includes irregular
  whitespace around the complete real footer — **required** for this scenario to assert `APPROVED`.
- `codex_case_altered_template_not_approved_root_comment` (E13) — `NEEDS_REVISION`. Body includes the complete
  real footer (also case-altered).
- `codex_approved_revert_not_approved_root_comment` (E17) — `NEEDS_REVISION`. The construction that defeated an
  earlier revision's disclosed one-token tolerance; a positive regression test.
- `codex_or_is_it_hedge_question_not_approved_root_comment` (E21) — `NEEDS_REVISION`. The round-5 exploit that
  triggered the third design.
- `codex_footer_opening_line_only_then_trailer_not_approved_root_comment` (E23) — `NEEDS_REVISION`. The exact
  regression test for Codex GitHub finding `3803545669`.
- `codex_one_byte_mutation_inside_footer_not_approved_root_comment` (E24) — `NEEDS_REVISION`. Verifies the
  entire footer is load-bearing, not just its opening line; may be implemented as one scenario with three
  assertions (one per mutation position) rather than three separate scenarios.

**New this round — corrected from false "exists" claims, per the round-7 audit:**

- `codex_real_vendor_footer_clean_root_comment` (E1) — `APPROVED`. Counted in Group APPROVED above. The
  regression test for Codex GitHub finding `3803807958` — an earlier revision claimed this scenario already
  existed; it did not, and this is now the highest-priority addition in this round's delta, since E1 is the
  classifier's primary real-response anchor and must have automated coverage.
- `codex_underscore_prefixed_lookalike_root_comment` (E15) — `NEEDS_REVISION`. Real body: `This remains
  un_approved.` An earlier revision claimed this scenario "exists — keep"; confirmed absent (`grep -c
  underscore` returns 0 hits anywhere in the file).
- `codex_unenumerated_actionable_sentence_after_signal_root_comment` (E16) — `NEEDS_REVISION`. Real construction:
  `Looks good. Remove the authentication check.` An earlier revision claimed this scenario "exists — keep";
  confirmed absent.
- `codex_metadata_token_as_directive_root_comment` (E18) — `NEEDS_REVISION`. Real construction: `Looks good.
  Commit this.` An earlier revision claimed this scenario "exists — keep"; confirmed absent (`grep -c
  metadata_token` returns 0 hits).
- `codex_nonfooter_details_block_not_truncated_root_comment` (E19) — `NEEDS_REVISION`. Real construction:
  `Looks good.` followed by a non-vendor `<details>` block containing `Rename the unsafe function.` An earlier
  revision claimed this scenario "exists — keep"; confirmed absent (`grep -c footer` returns 0 hits anywhere in
  the file — no footer-related scenario of any kind currently exists).
- `codex_footer_markup_lookalike_tag_names_not_truncated_root_comment` (E20) — `NEEDS_REVISION`. Real
  construction: `Looks good.` followed by `<details-not-footer><summary-note>About Codex in
  GitHub</summary-note>` then `Rename the unsafe function.` An earlier revision claimed this scenario "exists —
  keep"; confirmed absent.
- `codex_footer_refusal_rejected_by_whole_body_match_root_comment` (E22) — `NEEDS_REVISION` (blocking branch).
  Real construction: the real template plus complete footer with `This must not be merged.` inserted inside
  it. **An earlier revision claimed this scenario existed under the name `codex_footer_truncation_keeps_blocking_root_comment`
  and scheduled a rename; the pre-rename name is also confirmed absent from the file — there was nothing to
  rename, this is a new addition.**

### Reconciled test-disposition counts

| Metric | Before this plan (baseline, re-derived this round directly from the file) | After this revision (final) |
| --- | --- | --- |
| Total `run_test` assertions | **620** (corrects an earlier revision's "628," which this round's direct count — `grep -c '^run_test '` — does not reproduce) | 620 + 22 new scenarios' assertions (≈2 each, some scenarios use 3) ≈ **660–664** (confirm the exact figure when implementing — this table has carried the same "confirm at implementation time" caveat since round 2, because the harness's assertions-per-scenario convention is not perfectly uniform) |
| `codex_*` assertions | **247** (confirmed via `grep -c 'run_test "codex_'`, unchanged from every prior revision's claim) | ~247 + 22 × 2 ≈ 291, same caveat |
| Scenarios asserting `VERDICT: APPROVED` | **27** (confirmed via direct grep against the file, unchanged from every prior revision's claim — but see the corrected by-name breakdown below, which an earlier revision got wrong for 18 of the 25 non-Group-APPROVED members) | **5** — 2 real scenarios with updated bodies (`codex_clean_root_review_comment`, `codex_full_root_review_comment`) plus 3 new (`codex_real_vendor_footer_clean_root_comment`, `codex_sha_full_length_approved_root_comment`, `codex_irregular_whitespace_template_approved_root_comment`); the other 25 of the real 27 retarget to `NEEDS_REVISION` (Group RETARGETED, corrected this round from a false count of 18) |

### Residual verification strategy

This is a full design replacement, so the evidence the implementation must produce before
`ready-for-human-review` is:

1. A full `bash scripts/development-workflow/tests/test-pr-review-loop.sh` run exiting 0, with the total
   assertion count reported before and after, reconciled against the table above (report and explain any
   discrepancy — the estimate above is explicitly not final).
2. A reconciliation statement in the PR description naming, individually: the 5 scenarios in Group APPROVED
   (2 real with updated bodies, 3 new), the 25 scenarios in Group RETARGETED (corrected count — verify by
   re-running the same `grep` commands in the Verification Log's round-7 audit row, do not assume the count in
   this document is still current by the time of implementation), the confirmation that
   `codex_disqualifier_diagnostic_emitted` never existed (no deletion needed), and the 22 new scenarios (15
   carried forward, 7 corrected from false "exists" claims this round). No scenario outside these buckets may
   change disposition; any that does is a genuine regression, not an intended part of this contract change.
3. Confirmation that the real captured PR #1489 body approves end-to-end (not just via the illustrative
   snippet in the Verification Log) — this remains the single highest-impact check: a classifier that rejects
   the one thing it must accept is a total operational failure of the ready phase.
4. Confirmation that all 12 real captured PR #1490 review bodies still correctly return `NEEDS_REVISION` (or,
   for any with `state == "CHANGES_REQUESTED"`, are still routed to the blocking short-circuit unaffected by
   this function) — re-fetch live, do not rely on the bodies captured during this review round, since the
   whole point of exact-template matching is that it is sensitive to exactly this kind of drift.
5. Confirmation that every construction found across all seven review rounds of this plan's history — E14
   through E24 in the Parser-risk addendum — still returns `NEEDS_REVISION` against the real script, not just
   the illustrative prototype in this plan. E23 specifically re-verifies Codex GitHub finding `3803545669` is
   closed.
6. Confirmation that a one-byte mutation anywhere inside the footer (not only its opening line — E24) still
   returns `NEEDS_REVISION`, proving the entire footer text is load-bearing for the match.
7. Confirmation that `codex_response_is_blocking`'s own test coverage (unaffected by this revision, per
   Decision 4) still passes, and specifically that the new `codex_footer_refusal_rejected_by_whole_body_match_root_comment`
   scenario (edge case E22 — genuinely new this round, not a rename of a pre-existing scenario) resolves to the
   blocking branch — this is the one remaining case where `is_approved`'s own rejection and `is_blocking`'s
   independent recognition compose, and confirming both fire (even though `is_approved` alone is now sufficient
   for safety) prevents a silent loss of verdict specificity if a future change ever alters the precedence
   chain.
8. **Before marking this document's test-suite claims verified again, re-run the exact `grep` commands in the
   Verification Log's round-7 audit row against the file at implementation time**, not against this document's
   prose — this plan has now been wrong about test-suite existence twice (rounds 6 and 7), and the standing
   instruction going forward is that every "exists"/"kept"/"unchanged" claim in this document must be
   re-verified by execution immediately before it is relied upon, not assumed from a prior revision.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Real Codex clean root comment | Body captured from PR #1489: `Codex Review: Didn't find any major issues. Swish!`, a `**Reviewed commit:**` marker matching the fixture head SHA, and the full `<details>` "About Codex in GitHub" footer including its bulleted list | `scripts/development-workflow/tests/test-pr-review-loop.sh` (inline `gh` mock heredoc, scenario `codex_real_vendor_footer_clean_root_comment` — **new this round, corrected from "exists"; confirmed absent from the file, Codex GitHub finding `3803807958`**) |
| Real Codex review-wrapper body (no clean signal) | Any one of the 12 bodies captured from PR #1490's review history, verbatim | `scripts/development-workflow/tests/test-pr-review-loop.sh` (scenario `codex_review_wrapper_no_clean_signal_not_approved_root_comment`) |
| Footer-with-refusal variant | The real PR #1489 body with `This must not be merged.` inserted inside the `<details>` block | `scripts/development-workflow/tests/test-pr-review-loop.sh` (scenario `codex_footer_refusal_rejected_by_whole_body_match_root_comment` — **new this round; the pre-rename name `codex_footer_truncation_keeps_blocking_root_comment` this document previously scheduled for renaming is also confirmed absent from the file, so this is a new addition, not a rename**) |
| Footer-opening-line-only-plus-trailer variant (round-6 exploit) | The real approved template, followed by only the footer's opening line (not its complete text), followed by `Rename the unsafe function.` | `scripts/development-workflow/tests/test-pr-review-loop.sh` (scenario `codex_footer_opening_line_only_then_trailer_not_approved_root_comment`) |

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
      requires the response — the **entire, untruncated** body, whitespace-normalized — to be an **exact**
      match against one of a small set of literal templates captured from real Codex clean responses, each
      template including the complete vendor `<details>` footer text — currently exactly one template,
      covering the `Codex Review: Didn't find any major issues. Swish!` / `**Reviewed commit:**` shape plus the
      complete "About Codex in GitHub" footer, with a bounded placeholder only for the commit SHA. State
      plainly that there is no vocabulary list, no grammar, no truncation step, and no case-insensitive or
      punctuation-tolerant matching, and that adding a template is the only way to widen the approval surface
      and needs a live capture plus the same review a `CODEX_CLEAN_SIGNAL_PATTERN` change once required. Note
      the deliberate, disclosed trade: a genuinely clean response using different wording anywhere in the body
      — including the vendor footer — safe-fails to `NEEDS_REVISION` today.
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` — in the
      "Codex GitHub terminal evidence" block, update the sentence added by an earlier revision (about an
      "unhedged clean signal") to instead state: the response must reproduce, whitespace aside, one of a
      small set of exact captured clean-response templates covering the entire body, footer included, with no
      truncation step; anything else is treated as `NEEDS_REVISION` regardless of how close it reads to a
      genuine approval.
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
| **The template now binds to vendor-controlled help text (the `<details>` footer), not just the verdict sentence — a purely cosmetic rewording of OpenAI's footer (the settings-link text, the bulleted list, the acknowledgement sentence) now also produces a false `NEEDS_REVISION`, which it did not under the prior (truncate-then-match) revision.** | **High, by design — this round's explicit, accepted trade** | Low–Medium | **Recorded explicitly per this round's human decision (Decision 5).** The failure direction remains safe (more `NEEDS_REVISION`, never a false `APPROVED`) — this trade is accepted specifically because it closes Codex GitHub finding `3803545669`, which was the opposite (unsafe) failure direction. Recovery is the same as the row above: re-capture the footer live and update the one template entry. This risk did not exist under the prior revision (the footer was discarded before comparison, so its wording was irrelevant to the match) and is a direct, disclosed consequence of removing truncation |
| Only one template is evidenced today, so the approval surface is intentionally very narrow at ship time | High (by design) | Medium | Accepted, not a defect: the two live sources this round had access to (`#1489`, `#1490`) yield exactly one clean-response shape. Widening it requires a genuinely new live capture, per Decision 2's extension rule — inventing a plausible-looking second template (e.g. a `No blocking issues found.` shape with no current live evidence) was explicitly out of scope for this revision and must not be done without one |
| The commit-SHA placeholder's bound (`{7,40}`) is wider than the 10-character length every current real capture shows, and could in principle match a SHA-shaped string that is not really a commit reference | Low | Low | The bound is git's own documented abbreviated-to-full SHA-1 range, not an arbitrary guess (Decision 2) — narrowing it to today's observed 10 characters would be *safer* in the false-`APPROVED` direction but would fail on the very next legitimate response once this repository's object count crosses git's next auto-lengthening threshold, for a reason unrelated to anything Codex changed. This trade (a marginally wider hex-only, length-bounded field vs. a narrower one likely to need updating for reasons outside anyone's control) was made deliberately; revisit only with fresh evidence that git's behavior differs from its documented specification |
| **A future PR reintroduces truncation (or any partial-body matching) before comparison — this is now a structurally different risk than "the truncation boundary is wrong," and is why Codex GitHub finding `3803545669` closed the way it did** | Low, if the standing rule in Decision 5 is applied; **this exact class of finding has now recurred once (round 6) after the truncation approach was introduced in round 5**, so the historical base rate for "the truncation boundary needs one more fix" is not low | High | **Standing rule (Decision 5): no future PR may reintroduce a truncation step, a partial-body match, or any mechanism that compares less than the entire normalized body against the template.** `CODEX_FOOTER_OPENING_LITERAL` and `codex_strip_codex_footer` are deleted, not narrowed — there is no helper left to accidentally widen. Any PR proposing to "just match the visible part" or "strip X before comparing" must be rejected and pointed at this row and Decision 5 |
| **This revision removes the approval path's last dependency on `codex_response_is_blocking` for safety (not merely for verdict specificity) — a future refactor that assumes `is_blocking` is still load-bearing there, and relaxes it on that mistaken assumption, would reintroduce risk `is_approved` no longer independently guards against** | Low | Medium | Recorded explicitly (Decision 4, new bullet; Decision 5, closing paragraph): `is_approved`'s whole-body exact match is now self-contained — no input can reach `APPROVED` without being byte-identical (whitespace aside) to the one evidenced literal, regardless of what `is_blocking` does. `is_blocking` remains independently necessary for its own reason (Decision 4: false negatives there are unsafe on their own terms, for `CHANGES_REQUESTED`-adjacent and merge-refusal wording that never reaches `is_approved` at all) — this row exists so a future contributor does not mistake "is_blocking is no longer needed to prevent this specific false APPROVED" for "is_blocking is no longer needed" |
| BSD versus GNU tooling divergence (`tr`'s whitespace-class handling, `grep -E`'s escaping of `.`/`*`/backtick/parentheses in the template) | Medium | Medium | This revision uses **fewer** BSD/GNU divergence points than the prior one: no `awk` truncation pass at all (one fewer tool in the comparison path), no `\b` word boundaries anywhere, and the one remaining regex per template is a fully-anchored literal with a single bounded character-class placeholder — the simplest, least divergence-prone construct this plan has ever shipped, now applied to a longer literal. Verified on BSD tooling this round; CI covers GNU |
| `CODEX_APPROVED_TEMPLATES` regresses to a flexible pattern (an optional clause, a case-insensitive flag, a wildcard placeholder) — this is the same class of finding that recurred five times against this classifier's prior designs, now aimed at the one array that replaced all of them | Low, **if the mechanical rule below is applied**; historically High — it recurred five times across the classifier's history without one | High | **Standing rule (Decision 2): every entry in `CODEX_APPROVED_TEMPLATES` must be backed by a live capture, every non-literal character must be a placeholder bound to that field's own external specification (never a general wildcard), and no case-insensitive, optional, alternation, or truncation-based matching may be introduced.** Any PR proposing otherwise — however narrowly scoped it looks — must be rejected and pointed at this row and Decision 2 |
| The 25 scenarios in Group RETARGETED (corrected this round from a false count of 18 — see the round-7 audit), plus the 22 new scenarios (corrected from 15 — 7 were previously, incorrectly, described as already existing), mask a real regression in something other than `is_approved` | Medium | Medium | The Test disposition section is exhaustive, named, and ground-truth-verified against the real file this round; the PR description must state the full delta by scenario name, not a bare count (this is now the fourth revision in this plan's history where a stable-looking total would have concealed a real composition change if reported as a bare number alone) |
| **This document's own claims about which test scenarios already exist have now been wrong twice** (round 4's "no stale passage found," corrected in round 5; and round 7's `codex_real_vendor_footer_clean_root_comment` plus 14 further fabricated "exists" claims) | Medium, absent the standing rule below; **historically has recurred**, so treat as a real, not hypothetical, risk | High — a false "exists" claim leaves a genuine coverage gap that reads as covered | **Standing rule: before relying on any claim in this document that a named test scenario "exists," "is kept," or "is unchanged," re-run the exact `grep` command against the real file** (see the Verification Log's round-7 audit row for the commands used) rather than trusting this document's prose, no matter how recent the revision. This applies to every future round of this plan, not only this one |
| **A symbol scheduled for deletion is silently load-bearing for `codex_response_is_blocking` — deleting it (or one of its call sites) reintroduces a false-blocking regression the production script's own history already fixed once.** This is the third distinct class of "this document's own claim about the codebase was wrong" finding across rounds 7–8 (round 7: fabricated test-scenario existence; round 8: a real, load-bearing call site scheduled for deletion) | Medium, absent the standing rule below; **has now occurred once (round 8, `codex_strip_not_only_idiom`)** | High — a silently reintroduced false-blocking match can override concurrent availability evidence and produce an incorrect `NEEDS_REVISION` (blocking branch) for a genuinely clean response | **Standing rule (new this round, Codex GitHub finding `3803959040`): before scheduling ANY symbol for deletion, check whether it has a real call site inside `codex_response_is_blocking` specifically** (not just inside the function being replaced) — `codex_response_is_blocking`'s failure direction is unsafe (Decision 4), so an incorrect deletion there is never merely a disclosed trade the way an `is_approved`-side deletion can be. The round-8 sibling-coupling check (Verification Log) confirmed no other scheduled-for-deletion symbol has this coupling today, but any future addition to the deletion list must repeat this check, not assume it |
| **A verification command added to close one finding introduces a new, unexecuted defect of its own — this happened twice in round 8's own verify commands (a `grep -c` count vulnerable to comment-line inflation, and a `grep`-over-`git diff` check that cannot prove a function region is unmodified), caught in round 9** | Medium, absent the standing rule below; **has now occurred twice in one round (round 9, Codex GitHub findings `3804088454` and `3804088461`)**, confirming this is a recurring failure mode of writing verify commands without executing them, not a one-off | Medium — a mandatory smoke step that fails a correct implementation blocks shipping; a check that cannot detect a real regression (the diff-grep case) is worse, since it gives false confidence | **Standing rule (new this round): every verification command added to this document or the smoke-test runbook must be executed against the real tree before being written down, and its actual output recorded — not reasoned about.** Two structural sub-rules from the round-9 audit: (1) any `grep -c`/exact-count check must either anchor to executable syntax (e.g. `^run_test `) or explicitly filter comment lines (`grep -v '^[[:space:]]*#'`) before counting, if the searched symbol could plausibly appear in a comment; (2) any check whose purpose is "prove this function/region is unmodified" must extract the complete region (e.g. `awk '/^name\(\)/,/^}/'`) and diff the extraction directly — `grep` over a diff can only prove a specific line exists or changed, never that an unrelated line inside the same region did not change. The round-9 audit applied both sub-rules to every verification command in this document and the smoke-test runbook; see the Verification Log's round-9 audit row for the full disposition |

---

## Operational cost and escape hatch

**What a maintainer should expect.** `VERDICT: APPROVED` will now be **at least as rare** as under the
immediately prior revision, and **rarer in one specific respect**: a cosmetic change to the vendor footer alone
— wording the prior revision never compared, because it discarded the footer before matching — now also
produces a false `NEEDS_REVISION`. This is the direct, intended consequence of the human decision behind this
round's redesign (see Decisions 1, 2, and 5, and "Background"): every softer alternative this plan tried — a
vocabulary list, then a disqualifier list, then a closed grammar, then exact matching with a truncation
boundary — was found to have a false-`APPROVED` gap within one to two review rounds, six times in a row, and
the truncation boundary's gap was found in exactly the same shape as the others (an unreviewed region where
prose could hide). Removing the boundary — rather than tightening it a fourth time — is the one change in this
plan's history that eliminates the *category* of gap, not just its latest instance, and the cost of that
guarantee is a wider surface bound to vendor wording. Each false `NEEDS_REVISION` produces one extra
reviewer-loop cycle: `pr-review-loop.sh` reports the platform as not clean, the item agent inspects the
response, finds nothing actionable, and re-triggers.

**Escape hatch: none, deliberately — unchanged in spirit from every prior revision, restated because the lever
itself changed again.** No environment variable, config flag, or CLI option is added to relax the classifier.
The supported response to a persistent false `NEEDS_REVISION` is:

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
   `gh api …/issues/1489/comments` and `gh api …/pulls/1490/reviews` queries from the Verification Log and
   confirm the clean-response shape and the **complete footer text** (not just its opening line) still match.
   Record `Still valid` or stop and return evidence to the parent orchestrator — a drifted capture changes what
   `CODEX_APPROVED_TEMPLATES` must contain, not just what this plan documents.
2. **Delete every obsoleted symbol** in `codex-github-reviewer.sh`: `CODEX_APPROVAL_PATTERN`,
   `CODEX_NEGATED_APPROVAL_TARGET_WORDS`, `CODEX_NEGATED_APPROVAL_PATTERN`, `CODEX_CLEAN_SIGNAL_PATTERN`,
   `CODEX_CLEAN_SIGNAL_EXCISION`, `CODEX_APPROVAL_NEGATION_PATTERN`, `CODEX_APPROVAL_HEDGE_PATTERN`,
   `CODEX_APPROVAL_ACTIONABLE_PATTERN`, `CODEX_APPROVAL_DISQUALIFIER_PATTERN`,
   `CODEX_RESIDUE_FILLER_WORD_PATTERN`, `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN`, `codex_excise_clean_signals`,
   `codex_residue_is_closed_grammar`, `codex_response_first_paragraph`, `codex_strip_vendor_metadata_lines`,
   and `CODEX_FOOTER_OPENING_LITERAL`/`codex_strip_codex_footer` (**new to the deletion list in round 6** — see
   Decision 5). **`codex_strip_not_only_idiom` is corrected this round (Codex GitHub finding `3803959040`) to
   NOT be on this list** — the function definition and its call inside `codex_response_is_blocking` are both
   kept; only its call inside the old `codex_response_is_approved` disappears, as a consequence of that
   function being fully replaced (Decision 1), not as a separate deletion step.
   *Verify* — **corrected this round (Codex GitHub finding `3804088454`, round 9): two of these checks were
   `grep -c`/`grep -n` counts vulnerable to comment-line inflation. Both replacements below were run against the
   real file and their actual output is recorded, not asserted from reasoning.**
   1. `bash -n scripts/development-workflow/codex-github-reviewer.sh` succeeds (unaffected, sound as-is).
   2. **The deletion-list absence check must be comment-filtered.** The unfiltered form used in earlier
      revisions is unsound: `codex_response_is_blocking`'s own unchanged rationale comment names
      `CODEX_NEGATED_APPROVAL_PATTERN` three times, `codex_strip_quoted_spans`'s comment names both
      `CODEX_APPROVAL_PATTERN` and `CODEX_NEGATED_APPROVAL_PATTERN` once each, and `CODEX_BLOCKING_PATTERN`'s
      own unchanged rationale comment names `CODEX_NEGATED_APPROVAL_PATTERN` twice more — all in functions this
      plan explicitly keeps unchanged. Run today, before implementation (`CODEX_APPROVAL_PATTERN` added to the
      search set for parity with the deletion list two lines above, which this earlier check omitted):
      raw `grep -nE "CODEX_APPROVAL_PATTERN|CODEX_NEGATED_APPROVAL|CODEX_CLEAN_SIGNAL|CODEX_APPROVAL_(NEGATION|HEDGE|ACTIONABLE|DISQUALIFIER)|CODEX_RESIDUE_FILLER|CODEX_VENDOR_FLAVOR|codex_excise_clean_signals|codex_residue_is_closed_grammar|codex_response_first_paragraph|codex_strip_vendor_metadata_lines|CODEX_FOOTER_OPENING_LITERAL|codex_strip_codex_footer" scripts/development-workflow/codex-github-reviewer.sh`
      → **13** matches (8 of them comment mentions in functions this plan does not touch); comment-filtered
      `grep -v '^[[:space:]]*#' scripts/development-workflow/codex-github-reviewer.sh | grep -nE "<same pattern>"`
      → **5** matches, all of them the real code being deleted (the two `CODEX_APPROVAL_PATTERN`/
      `CODEX_NEGATED_APPROVAL_PATTERN` definitions, `CODEX_NEGATED_APPROVAL_TARGET_WORDS`'s definition, and
      their two real call sites inside the old `codex_response_is_approved`). **Use the comment-filtered form
      as the gate; it must return nothing after a correct implementation.** The raw (unfiltered) form will
      still show 8 surviving comment lines after a correct implementation and must not be used as a pass/fail
      check.
   3. **`codex_strip_not_only_idiom`'s count has the identical defect** — see the corrected verify command on
      the Layer-by-Layer bullet above: comment-filtered count is **3** today, must be **2** after a correct
      implementation (not 0, not 3) — do not use the raw count (**5** today, **4** after a correct
      implementation).
3. **Add** `CODEX_APPROVED_TEMPLATES` (Decision 2, now covering the entire body including the complete footer)
   and `codex_normalize_whitespace` (Decision 1, unchanged).
4. **Rewrite `codex_response_is_approved`** per Decision 1 and the Code Samples section: normalize whitespace
   on the raw body directly (no footer-strip call), test against every `CODEX_APPROVED_TEMPLATES` entry, return
   on first match.
5. **Update the file-header "Verdict parsing" comment block** to describe the exact-template contract; remove
   every reference to the allow-list/grammar contract the comment block described after the prior revision.
6. **Before touching the test file, re-run the round-7 audit's `grep` commands (Verification Log) against the
   real, current `test-pr-review-loop.sh`** — this document's "exists" claims have been wrong twice; do not
   proceed on this document's scenario lists without re-confirming them against the file as it stands at
   implementation time.
7. **Update the tests**: append the complete real footer to the 2 real scenario bodies in Group APPROVED
   (`codex_clean_root_review_comment`, `codex_full_root_review_comment`); apply the 25 Group RETARGETED
   dispositions (Test disposition, corrected this round from a false count of 18); confirm
   `codex_disqualifier_diagnostic_emitted` is genuinely absent (no deletion needed — it was never implemented);
   refresh every Group UNCHANGED-NEEDS_REVISION scenario's comment; then add the 22 new scenarios from "New
   scenarios" (15 carried forward correctly, plus 7 corrected this round from false "exists" claims:
   `codex_real_vendor_footer_clean_root_comment`, `codex_underscore_prefixed_lookalike_root_comment`,
   `codex_unenumerated_actionable_sentence_after_signal_root_comment`,
   `codex_metadata_token_as_directive_root_comment`, `codex_nonfooter_details_block_not_truncated_root_comment`,
   `codex_footer_markup_lookalike_tag_names_not_truncated_root_comment`, and
   `codex_footer_refusal_rejected_by_whole_body_match_root_comment`).
   *Verify*: run `bash scripts/development-workflow/tests/test-pr-review-loop.sh` and confirm it exits 0, that
   the total assertion count is reconciled against the "Reconciled test-disposition counts" table (report the
   real figure — the table's estimate is explicitly provisional), and that only the scenarios named in Test
   disposition changed expectation.
8. **Update the documentation** listed in "Documentation Updates," then add the CHANGELOG entry under
   `[Unreleased]` → `### Changed`, copied literally:

   ```text
   - **Conservative Codex verdict classifier** (#1491): `codex-github-reviewer.sh` now requires the response —
     whitespace-normalized, with no truncation step of any kind — to be an exact match, from its first
     character to its last, against one of a small set of clean-response templates captured verbatim from real
     Codex responses (each template including the complete vendor `<details>` footer text), and safe-fails to
     `NEEDS_REVISION` for anything else, including responses that are plausibly clean but use different
     wording anywhere in the body. This replaces both the open-ended negated-approval vocabulary enumeration
     this plan originally targeted and the allow-list/closed-grammar/truncate-then-match designs this plan
     shipped and then found further false-`APPROVED` gaps in across five subsequent review rounds — no
     vocabulary, grammar, or partial-body match converged, so this revision applies exact literal comparison to
     the entire response, leaving no discarded byte range for a novel construction to hide in. GitHub's
     structured `CHANGES_REQUESTED` review-state short-circuit and the blocking classifier are unchanged.
   ```

9. **Run the markdown and shell lint gates**: `npx markdownlint-cli2` on the changed docs and this plan,
   `python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`,
   `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`, and
   `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`.
10. **Walk the smoke test runbook** and record the results in the PR description.

---

## Document Quality Gate

- Spec/brief coverage: Checked — every objective in issue #1491's Option 2 maps to a decision, an
  implementation step, and test coverage; Options 1 and 3 are addressed explicitly under Decision 3 (unchanged
  across every revision). The human decision behind this revision (whole-body exact-template matching,
  replacing the truncate-then-match design) is itself still squarely within Option 2 — it is a different
  technique for implementing "an allow-list of recognized clean responses," not a change of approach to
  Option 1 or 3.
- Implementation-order consistency: Checked — helper names (`codex_normalize_whitespace`, unchanged from the
  prior revision), constant names (`CODEX_APPROVED_TEMPLATES`, updated in place to cover the whole body — no
  `CODEX_FOOTER_OPENING_LITERAL`, `CODEX_CLEAN_SIGNAL_PATTERN`, `CODEX_APPROVAL_DISQUALIFIER_PATTERN`,
  `CODEX_RESIDUE_FILLER_WORD_PATTERN`, or `CODEX_VENDOR_FLAVOR_TOKEN_PATTERN`, all deleted — `CODEX_FOOTER_OPENING_LITERAL`
  and `codex_strip_codex_footer` deleted in round 6; **`codex_strip_not_only_idiom` corrected in round 8 to be
  kept, not deleted — see below**), decision labels (Decision 1–5, same numbering as the immediately prior
  revision — Decisions 1, 2, 4, and 5 rewritten in place rather than renumbered, since each still addresses the
  same question its number always has: what counts as a match, why exact matching converges, why
  `is_blocking` stays a block-list, and how the footer is handled), and file paths agree across the Summary,
  Decisions, Layer-by-Layer, Code Samples, Parser-risk addendum, Testing Strategy, and Implementation Order
  sections. **Scenario-name claims specifically were re-verified in round 7 by direct execution against the
  real `test-pr-review-loop.sh` — not by document self-consistency alone** — after Codex GitHub finding
  `3803807958` and the round-7 audit it triggered found 14 additional fabricated "exists" claims beyond the one
  Codex named, plus 2 real scenarios misclassified by disposition (`codex_long_review_body_no_sigpipe`,
  `codex_long_root_comment_no_sigpipe`). Every scenario name this document currently marks "exists," "kept,"
  "real," or "confirmed present" was checked with `grep -c -- "<name>" test-pr-review-loop.sh` (or, for the two
  misclassified scenarios, by reading their real body and expected-verdict directly); every scenario name
  marked "new" was confirmed absent by the same method. **In round 8, the same execution-first discipline was
  applied to a behavioral (not existence) claim**: Codex GitHub finding `3803959040` showed the deletion list
  itself was wrong — `codex_strip_not_only_idiom`'s call inside `codex_response_is_blocking` is load-bearing,
  reproduced this round by running the real `CODEX_MERGE_REFUSAL_PATTERN`/`CODEX_NEGATION_WORDS` constants with
  and without the strip against `This is not only safe to merge but looks good.`, and a sibling-coupling check
  confirmed no other symbol on the deletion list has the same coupling. A full-document re-read this round
  confirmed no remaining passage describes footer truncation, `codex_strip_codex_footer`,
  `CODEX_FOOTER_OPENING_LITERAL`, the "visible portion only" match, any now-corrected false "exists" claim, or
  `codex_strip_not_only_idiom`'s full deletion as current — every reference to them is explicitly framed as
  history (in "Background," Decision 2, Decision 4, Decision 5, or the round-7/round-8 corrections).
- Verification support: Checked — every claim about existing behavior, file coverage, counts, and the vendor
  wire format cites a Verification Log command or a named source file. The exact implementation shipped in
  Code Samples (not an illustrative approximation of it) was re-executed on BSD `sed`/`grep`/`awk`/`tr` against
  all 13 real captured Codex bodies, every construction found across all eight review rounds, and every edge
  case in the Parser-risk addendum, including the two new to round 6 (E23, E24), the rewritten E22, and the
  seven scenario-existence corrections made in round 7. **The total `run_test` assertion baseline is corrected
  in round 7 from 628 to 620 — re-derived by direct count against the real file (`grep -c '^run_test '`), not
  carried forward from an earlier revision's claim** — the `codex_*` count (247) and the `VERDICT: APPROVED`
  count (27) were independently re-derived the same way and confirmed to match the earlier revision's figures,
  so those two specific numbers were correct even though several of the named scenarios behind the 27 were not.
  **Round 8 additionally re-verified, by execution against the real production constants (not the plan's prior
  description of them), that `codex_response_is_blocking` behaves identically before and after this plan only
  when `codex_strip_not_only_idiom`'s call site is retained** — this document's blanket "`is_blocking` is
  unchanged" claim is now stated everywhere as conditional on that retention, not as an unqualified fact.
- Behavioral guarantees: Checked — the "cannot weaken the `CHANGES_REQUESTED` short-circuit" guarantee names
  its mechanism (unchanged, Decision 3); the "whole-body match leaves no discarded byte range" guarantee names
  its actual mechanism (no truncation step exists in `codex_response_is_approved`, Decision 1/5) rather than
  merely asserting it, and is the guarantee that directly answers Codex GitHub finding `3803545669`; the
  "`is_blocking` is no longer load-bearing for this specific composition" guarantee is stated as a consequence
  of the whole-body match, not as a new mechanism added to `is_blocking` (Decision 4); **the "`is_blocking` is
  unchanged" guarantee is now explicitly conditional on retaining `codex_strip_not_only_idiom`'s call site
  (Decision 4, corrected round 8, Codex GitHub finding `3803959040`) — the claim previously read as
  unconditional while the same section scheduled the very call site it depends on for deletion**; the "exact
  matching converges" guarantee names its actual mechanism (a finite language defined by one literal template
  plus one bounded placeholder, Decision 2) rather than merely asserting it, and explicitly discloses both
  trades this design makes (a categorically higher false-`NEEDS_REVISION` rate, and a dependency on
  vendor-controlled footer wording) rather than presenting the design as risk-free.
- Complex workflow decision-gate matrix: Checked — see the matrix below, updated this round to remove the
  "footer-stripped" qualifier from the matched-body rows.
- Parser/API/concurrency checklist: Checked (parser-risk addendum present with a full-replacement edge-case
  enumeration and per-case unit-test mapping, updated this round for the whole-body match); concurrent-event-source
  recorded as not applicable with rationale, unchanged.
- CHANGELOG literal format: Checked — Implementation Order step 8 (renumbered this round to make room for the
  new step 6, re-running the round-7 audit before touching the test file) gives the entry in the project's
  `**Bold Title** (#N):` format under `### Changed`, rewritten this round to describe the whole-body,
  no-truncation contract that will actually ship.
- Not-applicable rationale: Checked — suppression semantics and concurrency each carry a rationale.

### Decision-gate matrix

| Gate input | Allowed outcome | Exit code | Required next action | Mirror surface |
| --- | --- | --- | --- | --- |
| Review-sourced evidence with `state == CHANGES_REQUESTED` | `NEEDS_REVISION` | 1 | Loop counts unresolved threads; item agent fixes findings | Unchanged in all four verdict sites and in `codex_response_priority` |
| `codex_response_is_blocking` matches | `NEEDS_REVISION` | 1 | Same as above | Unchanged |
| Usage-limit or environment-error notice | `UNAVAILABLE` | 3 | Platform reported unavailable; loop applies the configured unavailable policy | Unchanged |
| The **entire, untruncated** body, whitespace-normalized, exactly matches an entry in `CODEX_APPROVED_TEMPLATES` (footer included, no truncation step) | `APPROVED` | 0 | Platform reported clean | **Changed again this round — no footer-truncation step precedes the match any more (Decision 1/5); the required literal now includes the complete vendor footer** |
| The entire, untruncated, whitespace-normalized body does not exactly match any template | `NEEDS_REVISION (unrecognized response format — safe-fail)` | 1 | Item agent inspects the response, confirms whether it is a genuinely clean response using new wording — including footer wording — and either re-triggers or (rarely) proposes a new template with a live capture | **Changed again this round — this remains the only false-`NEEDS_REVISION` surface, now also covering a footer wording mismatch, which the prior revision's truncation step made irrelevant to this row** |
| No clean signal at all | `NEEDS_REVISION (unrecognized response format — safe-fail)` | 1 | Same as above | Subsumed into the row above — there is no longer a separate "signal present" concept to distinguish |
| No terminal evidence within the poll window | `TIMED_OUT` | 2 | Treated as unavailable | Unchanged |

Example bodies for each changed row are enumerated in the Parser-risk addendum (E1–E24) and mapped to named
test scenarios, so the matrix, the examples, and the tests are the same set.

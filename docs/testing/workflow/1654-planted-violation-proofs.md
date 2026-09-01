# Planted-violation proofs — #1654

Recorded for PR #1690 per REVIEW.md Workflow Policy checklist item 4 and the
implementation plan. Each proof: plant location (file:line), fail command/outcome,
restore, pass command/outcome.

## P1 — collapsed supply states

**Plant**: `scripts/development-workflow/local-ai-reviewer.sh:409-447` — merge
`absent`, `unreadable`, and `oversized` into one `not_supplied` state.

**Fail**: `bash scripts/development-workflow/tests/test-local-ai-reviewer.sh` →
FAIL `1654_s1_absent_state`, `1654_s1_unreadable_state`, or `1654_s2_oversized_state`.

**Pass (canonical)**: same command → PASS all four `1654_s1_*` / `1654_s2_*` state tests.

## P2 — truncated oversized doctrine text

**Plant**: `local-ai-reviewer.sh:426-430` — supply first `REVIEW_DOCTRINE_MAX_BYTES`
of snapshot instead of empty `text` in oversized row.

**Fail**: `test-local-ai-reviewer.sh` → FAIL `1654_s2_oversized_text_empty`.

**Pass**: PASS `1654_s2_oversized_text_empty` and `1654_s2_oversized_version_present`.

## P3 — duplicate bound in linter

**Plant**: `scripts/lint/review-doctrine-lint.sh:43` — compare with literal
`-gt 12000` instead of `-gt "$REVIEW_DOCTRINE_MAX_BYTES"`.

**Fail**:

```bash
grep -Eq -- '-gt[[:space:]]+[1-9][0-9]{2,}' scripts/lint/review-doctrine-lint.sh && echo PLANT_DETECTED
bash scripts/development-workflow/tests/test-review-doctrine-lint.sh  # FAIL s15_linter_no_literal_gt
```

**Pass (canonical line 43)**: `test-review-doctrine-lint.sh` → PASS `s15_*`.

## P4 — whole-file incident scan

**Plant**: `scripts/lint/review-doctrine-lint.sh:74-94` — apply AC-4 grep to the
full file instead of `$entry_text`.

**Fail**: lint rejects
`scripts/development-workflow/tests/fixtures/review-doctrine/preamble-dev-path-clean-entries.md`
(exit 1 on preamble `docs/specs/developments/`).

**Pass (canonical entry scope)**: `test-review-doctrine-lint.sh` → PASS
`s13_preamble_path_pass`.

## P5 — supplied with empty version when digest missing

**Plant**: `local-ai-reviewer.sh:391-405` (`reviewer_doctrine_version`) — return
empty string instead of failing when neither `sha256sum` nor `shasum` exists.

**Fail**: with `PATH` stripped of digest tools, supply returns `supplied` and empty
`version` instead of `unreadable`.

**Pass (canonical)**: `test-local-ai-reviewer.sh` → PASS `1654_s6_no_digest_state` and
`1654_s6_no_digest_version_empty`.

## P6 — doctrine text in key=value output

**Plant**: `local-ai-reviewer.sh:704-707` — add `print_kv` for full doctrine text.

**Fail**: `test-local-ai-reviewer.sh` → FAIL `1654_s8_no_text_kv` and fabricated
`PLATFORM_1_*` keys in `1654_s8_no_fabricated`.

**Pass**: PASS `1654_s8_no_text_kv` (count 0) and `1654_s8_platform_*`.

## P7 — stage-conditional doctrine supply

**Plant**: `local-ai-reviewer.sh:626-697` — wrap doctrine fields in
`if [ "$review_stage" != default ]`.

**Fail**: `test-local-ai-reviewer.sh` → FAIL `1654_s9_main_state` or
`1654_s9_develop_state` (not `supplied`).

**Pass**: PASS all `1654_s9_*` branches including `main` and `develop`.

## P8 — overridable bound constant

**Plant**: `scripts/development-workflow/workflow-lib.sh:7` — use
`"${REVIEW_DOCTRINE_MAX_BYTES:-12000}"` instead of `readonly …=12000`.

**Fail**: with env `REVIEW_DOCTRINE_MAX_BYTES=20000`, 12,001-byte catalogue passes
lint and is `supplied`.

**Pass (canonical readonly)**: `test-review-doctrine-lint.sh` → PASS `s14_at_12001_fail`.

## P9 — command-substitution text path

**Plant**: `local-ai-reviewer.sh:668-697` — pass doctrine via `--arg` from
`$(jq -r '.text' …)` instead of `--argjson doctrine_supply`.

**Fail**: `test-local-ai-reviewer.sh` → FAIL `1654_s7a_bytes_match` (3416 vs 3417
bytes when trailing newline mishandled).

**Pass (canonical `--argjson`)**: PASS `1654_s7a_bytes_match`.

## P10 — permission-bit probe only

**Plant**: `local-ai-reviewer.sh:409-447` — replace read handlers with single
`[ -r "$path" ]` before any operation.

**Fail**: file removed after `[ -r ]` aborts reviewer under `set -e` instead of
reporting `unreadable`.

**Pass (canonical per-operation handlers)**: PASS `1654_s1_unreadable_state`,
`1654_s1a_grep_error_unreadable`, and `1654_s1a_cp_fail_unreadable`.

## P11 — multi-read race (version ≠ text bytes)

**Plant**: `local-ai-reviewer.sh:409-447` — derive hash, count, and text from
separate reads of the live file instead of one snapshot.

**Fail**: rewrite catalogue after snapshot; returned `version` is hash of different
bytes than `text` (plan scenario 1b).

**Pass (canonical single snapshot)**: PASS `1654_s1b_version_matches_text`; all four
values from one `cp` in `reviewer_doctrine_supply`.

## P12 — `grep -c … || true` on pattern count

**Plant**: `local-ai-reviewer.sh:437-444` — use `grep -c … || true` flattening
exit 1 and exit >1.

**Fail**: unreadable grep error reports `supplied` with `pattern_count=0` instead
of `unreadable`.

**Pass (canonical status branch)**: PASS `1654_s1a_grep_error_unreadable`; grep exit 1
→ count 0 + `supplied`; exit >1 → `unreadable`.

## P13 — evidence file without review_doctrine object

**Plant**: `local-ai-reviewer.sh:1034-1040` (`write_evidence_file`) — omit
`review_doctrine` object from evidence JSON.

**Fail**: `test-local-ai-reviewer.sh` → FAIL `1654_s8a_evidence_state` while kv
output still passes.

**Pass**: PASS `1654_s8a_evidence_*` with `review_doctrine` object present.

## P14 — CI step without path filter entries

**Plant**: `.github/workflows/markdown-lint.yml:25-26` — remove
`review-doctrine.md` and `review-doctrine-lint.sh` from `paths`.

**Fail**: `test-review-doctrine-lint.sh` → FAIL `s17_markdown_paths_catalogue` /
`s17_markdown_paths_linter`; catalogue-only PR triggers no workflow.

**Pass (canonical lines 25-26 + step at line 98)**: PASS `s17_*`; explicit
`bash scripts/lint/review-doctrine-lint.sh` step runs on catalogue edits.

## Regression suite (canonical head)

```bash
bash scripts/lint/review-doctrine-lint.sh
bash scripts/development-workflow/tests/test-review-doctrine-lint.sh   # 25 passed
bash scripts/development-workflow/tests/test-local-ai-reviewer.sh      # 288 passed
shellcheck --severity=warning scripts/lint/review-doctrine-lint.sh
```

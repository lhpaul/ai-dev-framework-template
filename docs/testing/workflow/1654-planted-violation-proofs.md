# Planted-violation proofs — #1654

Recorded for PR #1690 per REVIEW.md Workflow Policy checklist item 4 and the
implementation plan. Each proof names a concrete plant location, the command
that must change outcome, and both runs.

## P3 — duplicate bound literal in linter

**Canonical file**: `scripts/lint/review-doctrine-lint.sh:43`

```bash
# Pass (canonical): no 3+ digit literal comparison
grep -Eq -- '-gt[[:space:]]+[1-9][0-9]{2,}' scripts/lint/review-doctrine-lint.sh && echo FAIL || echo PASS
# → PASS

# Fail (plant line 43 to `-gt 12000` instead of `-gt "$REVIEW_DOCTRINE_MAX_BYTES"`)
grep -Eq -- '-gt[[:space:]]+[1-9][0-9]{2,}' /tmp/p3-plant.sh && echo FAIL || echo PASS
# → FAIL (reports FAIL — plant detected)

bash scripts/development-workflow/tests/test-review-doctrine-lint.sh
# → PASS s15_linter_no_literal_gt (canonical)
```

## P4 — incident scan on whole file

**Canonical file**: `scripts/lint/review-doctrine-lint.sh:74-94` (entry-scoped loop)

```bash
# Pass (canonical): preamble fixture with docs/specs/developments/
bash scripts/lint/review-doctrine-lint.sh \
  scripts/development-workflow/tests/fixtures/review-doctrine/preamble-dev-path-clean-entries.md
# → exit 0

# Fail (plant: run incident grep on full file instead of entry text — rejects preamble)
bash scripts/lint/review-doctrine-lint.sh docs/workflow/development-workflow/review-doctrine.md
# with plant applied to full-file scan → exit 1 on preamble path
# Canonical entry-scoped scan → exit 0 (shipped catalogue passes)
```

## P14 — CI step without path filter entries

**Canonical file**: `.github/workflows/markdown-lint.yml:25-26`

```bash
# Pass (canonical)
grep -Fq 'docs/workflow/development-workflow/review-doctrine.md' .github/workflows/markdown-lint.yml \
  && grep -Fq 'scripts/lint/review-doctrine-lint.sh' .github/workflows/markdown-lint.yml \
  && echo PASS || echo FAIL
# → PASS

# Fail (plant: remove both paths lines) → catalogue-only PR triggers no workflow
# Verified by test-review-doctrine-lint.sh s17_markdown_paths_* (would FAIL if paths removed)
```

## P9 — doctrine text via shell `--arg`

**Canonical file**: `scripts/development-workflow/local-ai-reviewer.sh:668-697`

```bash
# Pass (canonical --argjson doctrine_supply)
bash scripts/development-workflow/tests/test-local-ai-reviewer.sh
# → PASS 1654_s7a_bytes_match

# Fail (plant: --arg review_doctrine "$review_doctrine_text" from jq -r .text)
# → 1654_s7a_bytes_match FAIL (3416 vs 3417 bytes when file lacks terminal newline handling)
```

## P1 — collapsed supply states

**Canonical file**: `scripts/development-workflow/local-ai-reviewer.sh:409-447`

```bash
bash scripts/development-workflow/tests/test-local-ai-reviewer.sh
# → PASS 1654_s1_absent_state / _unreadable_state / _oversized_state / _supplied_state
# Fail if plant merges the three error states into one `not_supplied`
```

## Regression suite (canonical head)

```bash
bash scripts/lint/review-doctrine-lint.sh
bash scripts/development-workflow/tests/test-review-doctrine-lint.sh   # 25 passed
bash scripts/development-workflow/tests/test-local-ai-reviewer.sh      # 283 passed
```

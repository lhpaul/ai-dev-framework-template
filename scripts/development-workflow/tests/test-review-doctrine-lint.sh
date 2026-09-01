#!/usr/bin/env bash
# Unit tests for review-doctrine-lint.sh and the shipped catalogue.
# covers: scripts/lint/review-doctrine-lint.sh
# covers: docs/workflow/development-workflow/review-doctrine.md

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
LINTER="$REPO_ROOT/scripts/lint/review-doctrine-lint.sh"
FIXTURES="$SCRIPT_DIR/fixtures/review-doctrine"
CATALOGUE="$REPO_ROOT/docs/workflow/development-workflow/review-doctrine.md"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

lint_exit() {
  local file="$1"
  set +e
  bash "$LINTER" "$file" >/dev/null 2>&1
  local status=$?
  set -e
  printf '%s' "$status"
}

# Scenario 11: well-formedness
run_test "s11_well_formed_pass" "0" "$(lint_exit "$FIXTURES/well-formed.md")"
run_test "s11_missing_detect_fail" "1" "$(lint_exit "$FIXTURES/malformed-missing-detect.md")"
run_test "s11_duplicate_shape_fail" "1" "$(lint_exit "$FIXTURES/malformed-duplicate-shape.md")"

# Scenario 12: incident references (one per AC-4 form)
run_test "s12_hash_number_fail" "1" "$(lint_exit "$FIXTURES/incident-hash-number.md")"
run_test "s12_forge_url_fail" "1" "$(lint_exit "$FIXTURES/incident-forge-url.md")"
run_test "s12_spelled_out_fail" "1" "$(lint_exit "$FIXTURES/incident-spelled-out.md")"
run_test "s12_dev_path_fail" "1" "$(lint_exit "$FIXTURES/incident-dev-path.md")"

# Scenario 12 near-miss controls (must pass on well-formed + shipped catalogue)
_near_miss_file="$(mktemp)"
cat > "$_near_miss_file" <<'EOF'
# Near misses

Guidance may mention docs/specs/ without developments.

### Clean controls

**Shape**: Hash-like headings must not match.

**Example**: Use # Title and PR review language safely.

**Detect**: Also example.com/pull/1 is not github.com.

EOF
run_test "s12_near_miss_pass" "0" "$(lint_exit "$_near_miss_file")"
rm -f "$_near_miss_file"

# Scenario 13: preamble path allowed
run_test "s13_preamble_path_pass" "0" "$(lint_exit "$FIXTURES/preamble-dev-path-clean-entries.md")"

# Scenario 14: boundary sizes
_boundary_dir="$(mktemp -d)"
_boundary_pass="$_boundary_dir/at-bound.md"
_boundary_fail="$_boundary_dir/over-bound.md"
python3 - <<'PY' "$FIXTURES/well-formed.md" "$_boundary_pass" "$_boundary_fail"
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_bytes()
base = pathlib.Path(sys.argv[2])
fail = pathlib.Path(sys.argv[3])
padding = b"x" * 8000
body = src + b"\n\n### Pad entry\n\n**Shape**: pad\n\n**Example**: " + padding + b"\n\n**Detect**: pad?\n"
while len(body) < 12000:
    body += b" "
body = body[:12000]
base.write_bytes(body)
fail.write_bytes(body + b"x")
PY
run_test "s14_at_12000_pass" "0" "$(lint_exit "$_boundary_pass")"
run_test "s14_at_12001_fail" "1" "$(lint_exit "$_boundary_fail")"

# Scenario 15b: behavioural boundary agreement (reuse over-bound fixture)
run_test "s15b_linter_rejects_oversized" "1" "$(lint_exit "$_boundary_fail")"
rm -rf "$_boundary_dir"

# Scenario 15: single bound definition
_assign_count="$(rg -l 'REVIEW_DOCTRINE_MAX_BYTES=' scripts --glob '*.sh' 2>/dev/null | rg -v '/tests/' | wc -l | tr -d ' ')"
run_test "s15_single_assignment" "1" "$_assign_count"
run_test "s15_linter_uses_constant" "yes" "$(grep -Fq '$REVIEW_DOCTRINE_MAX_BYTES' "$LINTER" && echo yes || echo no)"
run_test "s15_linter_no_literal_gt" "no" "$(grep -Eq -- '-gt[[:space:]]+[1-9][0-9]{2,}' "$LINTER" && echo yes || echo no)"
_reviewer_supply_fn="$(sed -n '/^reviewer_doctrine_supply(/,/^}/p' "$REPO_ROOT/scripts/development-workflow/local-ai-reviewer.sh")"
run_test "s15_reviewer_uses_constant" "yes" "$(printf '%s\n' "$_reviewer_supply_fn" | grep -Fq '$REVIEW_DOCTRINE_MAX_BYTES' && echo yes || echo no)"
run_test "s15_reviewer_no_literal_gt" "no" "$(printf '%s\n' "$_reviewer_supply_fn" | grep -Eq -- '-gt[[:space:]]+[1-9][0-9]{2,}' && echo yes || echo no)"

# Scenario 16: shipped catalogue
run_test "s16_shipped_passes_linter" "0" "$(lint_exit "$CATALOGUE")"
_pattern_count="$(grep -c '^### ' "$CATALOGUE" || true)"
run_test "s16_five_patterns" "5" "$_pattern_count"
run_test "s16_ac3_not_only_reporting" "yes" "$(grep -Fq 'set of things worth reporting' "$CATALOGUE" && echo yes || echo no)"
run_test "s16_ac3a_name_pattern" "yes" "$(grep -Fq 'name it' "$CATALOGUE" && echo yes || echo no)"

# Scenario 16a: generality obligation in catalogue guidance
run_test "s16a_catalogue_generality" "yes" "$(grep -Fq 'reads generally' "$CATALOGUE" && echo yes || echo no)"
run_test "s16a_review_generality" "yes" "$(grep -Fq 'read generally' "$REPO_ROOT/REVIEW.md" && echo yes || echo no)"

# Scenario 17: CI path filters
run_test "s17_markdown_paths_catalogue" "yes" "$(grep -Fq 'docs/workflow/development-workflow/review-doctrine.md' "$REPO_ROOT/.github/workflows/markdown-lint.yml" && echo yes || echo no)"
run_test "s17_markdown_paths_linter" "yes" "$(grep -Fq 'scripts/lint/review-doctrine-lint.sh' "$REPO_ROOT/.github/workflows/markdown-lint.yml" && echo yes || echo no)"
run_test "s17_shellcheck_paths_linter" "yes" "$(grep -Fq 'scripts/lint/review-doctrine-lint.sh' "$REPO_ROOT/.github/workflows/shellcheck.yml" && echo yes || echo no)"

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAIL: $FAIL_COUNT test(s) failed"
  exit 1
fi

echo "PASS: $PASS_COUNT test(s) passed"

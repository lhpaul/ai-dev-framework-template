#!/usr/bin/env bash
# test-security-advisory-classifier.sh - Unit tests for the BR1 two-part
# (content-category AND file-location) security-sensitive advisory
# classifier.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
CLASSIFIER="$REPO_ROOT/scripts/development-workflow/security-advisory-classifier.sh"

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
    echo "FAIL: $name - expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_fails_contains() {
  local name="$1" expected="$2"
  shift 2
  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  if [ "$status" -ne 0 ] && grep -Fq -- "$expected" <<< "$output"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected failure containing '${expected}'"
    printf 'Status: %s\nOutput:\n%s\n' "$status" "$output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# Each helper builds the classifier invocation as an explicit array (rather
# than relying on `${3:+--diff-hunk "$3"}`'s unquoted expansion, which is
# correct here only because $3 happens not to need word-splitting) so
# appending the optional --diff-hunk pair only when $3 is set is
# unambiguous regardless of what $3 contains.
classify_sensitive() {
  local -a args=(classify --finding-text "$1" --file-path "$2")
  if [ -n "${3:-}" ]; then args+=(--diff-hunk "$3"); fi
  "$CLASSIFIER" "${args[@]}" | jq -r '.securitySensitive'
}

classify_category() {
  local -a args=(classify --finding-text "$1" --file-path "$2")
  if [ -n "${3:-}" ]; then args+=(--diff-hunk "$3"); fi
  "$CLASSIFIER" "${args[@]}" | jq -r '.matchedCategory'
}

classify_file() {
  local -a args=(classify --finding-text "$1" --file-path "$2")
  if [ -n "${3:-}" ]; then args+=(--diff-hunk "$3"); fi
  "$CLASSIFIER" "${args[@]}" | jq -r '.matchedFile'
}

echo ""
echo "=== Security advisory classifier ==="

# --- CLI surface ---
run_fails_contains "requires_subcommand" "unknown subcommand" "$CLASSIFIER" bogus
run_fails_contains "requires_finding_text" "--finding-text or --finding-text-file is required" "$CLASSIFIER" classify --file-path "x"
run_fails_contains "requires_file_path" "--file-path is required" "$CLASSIFIER" classify --finding-text "x"
run_fails_contains "rejects_empty_finding_text" "--finding-text is required and must be non-empty" "$CLASSIFIER" classify --finding-text "" --file-path ""
run_fails_contains "rejects_both_finding_text_forms" "mutually exclusive" "$CLASSIFIER" classify --finding-text "x" --finding-text-file "/dev/null" --file-path ""
run_fails_contains "rejects_both_diff_hunk_forms" "mutually exclusive" "$CLASSIFIER" classify --finding-text "x" --file-path "" --diff-hunk "y" --diff-hunk-file "/dev/null"
run_fails_contains "finding_text_file_rejects_missing_file" "referenced file not found" "$CLASSIFIER" classify --finding-text-file "/nonexistent/path" --file-path ""

# --- AC1/BR1: match on only one part never classifies as security-sensitive ---
run_test "part_a_only_not_sensitive" "false" \
  "$(classify_sensitive "this endpoint bypasses the auth check for admin users" "src/app/admin-controller.ts")"
run_test "part_b_only_not_sensitive" "false" \
  "$(classify_sensitive "this jq filter could be written more concisely" "scripts/development-workflow/run-epic-delegated-gate.sh")"

# --- AC2: zero-of-three on this batch's real non-security findings ---
run_test "ac2_pr1459_not_sensitive" "false" \
  "$(classify_sensitive "this jq iteration could produce duplicate entries if the array contains repeated keys" "scripts/development-workflow/run-epic-audit-trail.sh")"
run_test "ac2_pr1460_not_sensitive" "false" \
  "$(classify_sensitive "this JSON key is typed as a string but consumed as a number downstream" "scripts/development-workflow/run-epic-risk-classifier.sh")"
run_test "ac2_pr1467_not_sensitive" "false" \
  "$(classify_sensitive "this quote is not escaped consistently with the rest of the string" "scripts/development-workflow/pr-review-loop.sh")"

# --- AC3: positive match on the motivating PR #1431 shape ---
run_test "ac3_force_without_lease_sensitive" "true" \
  "$(classify_sensitive "raw git push --force is used here without a safety lease" "scripts/development-workflow/workflow-branch-push-guard.sh")"
run_test "ac3_force_without_lease_category" "c" \
  "$(classify_category "raw git push --force is used here without a safety lease" "scripts/development-workflow/workflow-branch-push-guard.sh")"
run_test "ac3_permissive_remote_url_sensitive" "true" \
  "$(classify_sensitive "the remote URL parsing here is too permissive and could let a spoofed remote bypass the push guard's validation check" "scripts/development-workflow/workflow-branch-push-guard.sh")"
run_test "ac3_permissive_remote_url_category" "e" \
  "$(classify_category "the remote URL parsing here is too permissive and could let a spoofed remote bypass the push guard's validation check" "scripts/development-workflow/workflow-branch-push-guard.sh")"

# --- Parser-risk addendum edge cases ---

# Case variance
run_test "case_variance_force_upper" "c" \
  "$(classify_category "raw git push --FORCE without a lease" "scripts/development-workflow/workflow-branch-push-guard.sh")"

# Negative lookalike: not git/version-control context
run_test "negative_lookalike_rerender" "false" \
  "$(classify_sensitive "force a component re-render" "scripts/development-workflow/workflow-branch-push-guard.sh")"

# Negative lookalike: safety-lease exclusion, hyphenated
run_test "safety_lease_hyphenated_excluded" "false" \
  "$(classify_sensitive "the caller uses git push --force-with-lease, which is safe" "scripts/development-workflow/workflow-branch-push-guard.sh")"

# Negative lookalike: safety-lease exclusion, unhyphenated phrasing
run_test "safety_lease_unhyphenated_excluded" "false" \
  "$(classify_sensitive "force push with a safety lease" "scripts/development-workflow/workflow-branch-push-guard.sh")"

# Positive case still matches despite containing "with" inside "without"
run_test "without_safety_lease_still_matches" "true" \
  "$(classify_sensitive "raw git push --force is used here without a safety lease" "scripts/development-workflow/workflow-branch-push-guard.sh")"

# Negative lookalike: bare "secret" word, no exposure verb
run_test "bare_secret_word_not_sensitive" "false" \
  "$(classify_sensitive "the retry count is a secret constant we tune later" "scripts/development-workflow/workflow-branch-push-guard.sh")"

# Multiple category keywords on one line: fixed category-priority (b before c)
run_test "category_priority_b_over_c" "b" \
  "$(classify_category "this force push also leaks a secret token in the logs" "scripts/development-workflow/workflow-branch-push-guard.sh")"

# Overlapping categories (a) vs (e): auth bypass takes precedence, in either order
run_test "overlap_bypass_before_auth" "a" \
  "$(classify_category "this change bypasses the auth check" "scripts/development-workflow/workflow-branch-push-guard.sh")"
run_test "overlap_auth_before_bypass" "a" \
  "$(classify_category "this change has an auth check that can be bypassed" "scripts/development-workflow/workflow-branch-push-guard.sh")"

# File-location exact-match boundary: lookalike file is not on the allowlist
run_test "exact_path_boundary_lookalike_not_sensitive" "false" \
  "$(classify_sensitive "raw git push --force is used here without a safety lease" "scripts/development-workflow/run-epic-risk-classifier-notes.sh")"

# .github/workflows/*.yml special case: no permissions/secrets context
run_test "workflow_yaml_no_permissions_not_sensitive" "false" \
  "$(classify_sensitive "this bypasses the guard check on: push trigger" ".github/workflows/deploy.yml")"

# .github/workflows/*.yml special case: permissions context in finding text
run_test "workflow_yaml_with_permissions_sensitive" "true" \
  "$(classify_sensitive "this bypasses the guard check via permissions: contents: write" ".github/workflows/deploy.yml")"

# .github/workflows/*.yml special case: diff-hunk-only match
run_test "workflow_yaml_diff_hunk_only_sensitive" "true" \
  "$(classify_sensitive "this job grants broader access than it needs and bypasses the least-privilege check" ".github/workflows/deploy.yml" "permissions: contents: write")"
run_test "workflow_yaml_diff_hunk_only_no_prose_key_not_sensitive" "false" \
  "$(classify_sensitive "this job grants broader access than it needs" ".github/workflows/deploy.yml")"

# Empty/absent file path (PR-level issue comment): Part B always fails
run_test "empty_file_path_not_sensitive" "false" \
  "$(classify_sensitive "raw git push --force is used here without a safety lease" "")"

# Multiline finding text: newline-to-space normalization
run_test "multiline_finding_matches_category_a" "true" \
  "$(classify_sensitive "$(printf 'this finding describes an auth\nbypass on the enforcement surface')" "scripts/development-workflow/workflow-branch-push-guard.sh")"
run_test "multiline_finding_matches_category_a_value" "a" \
  "$(classify_category "$(printf 'this finding describes an auth\nbypass on the enforcement surface')" "scripts/development-workflow/workflow-branch-push-guard.sh")"

# matchedFile is populated only on a positive match
run_test "matched_file_populated_on_match" "scripts/development-workflow/workflow-branch-push-guard.sh" \
  "$(classify_file "raw git push --force is used here without a safety lease" "scripts/development-workflow/workflow-branch-push-guard.sh")"
run_test "matched_file_null_when_not_sensitive" "null" \
  "$(classify_file "this jq filter could be written more concisely" "scripts/development-workflow/run-epic-delegated-gate.sh")"

# --finding-text-file / --diff-hunk-file input form (distinct flags, not an
# "@file" convention on --finding-text/--diff-hunk -- see the CRITICAL
# planted-violation cases below for why that convention is unsafe).
tmp_file="$(mktemp)"
trap 'rm -f "$tmp_file"' EXIT
printf 'raw git push --force is used here without a safety lease' > "$tmp_file"
run_test "finding_text_file_input" "true" \
  "$("$CLASSIFIER" classify --finding-text-file "$tmp_file" --file-path "scripts/development-workflow/workflow-branch-push-guard.sh" | jq -r '.securitySensitive')"

tmp_diff_hunk_file="$(mktemp)"
trap 'rm -f "$tmp_file" "$tmp_diff_hunk_file"' EXIT
printf 'permissions: contents: write' > "$tmp_diff_hunk_file"
run_test "diff_hunk_file_input" "true" \
  "$("$CLASSIFIER" classify --finding-text "this job grants broader access than it needs and bypasses the least-privilege check" --file-path ".github/workflows/deploy.yml" --diff-hunk-file "$tmp_diff_hunk_file" | jq -r '.securitySensitive')"

# CRITICAL planted-violation proof: --finding-text/--diff-hunk must always
# be literal, never treated as a file reference. A real unified-diff hunk
# header starts with "@@" (before this fix, "@@" was misread as an "@file"
# reference and the classifier aborted with "referenced file not found").
run_test "diff_hunk_real_at_at_header_is_literal" "true" \
  "$("$CLASSIFIER" classify --finding-text "this job grants broader access than it needs and bypasses the least-privilege check" --file-path ".github/workflows/deploy.yml" --diff-hunk "@@ -12,7 +12,9 @@ permissions: contents: write" | jq -r '.securitySensitive')"
run_test "finding_text_at_mention_is_literal" "false" \
  "$("$CLASSIFIER" classify --finding-text "@octocat please review this jq filter" --file-path "scripts/development-workflow/run-epic-delegated-gate.sh" | jq -r '.securitySensitive')"

# Category (d): injection risk
run_test "category_d_injection" "d" \
  "$(classify_category "unsanitized input reaches an eval( call here" "scripts/development-workflow/workflow-branch-push-guard.sh")"

# Category (b): credential exposure
run_test "category_b_credential_exposure" "b" \
  "$(classify_category "this logs the credential in plaintext" "scripts/development-workflow/workflow-branch-push-guard.sh")"

# Planted-violation proof: a genuine internal `grep` failure (exit >=2) must
# abort loudly (classify exits non-zero), never silently fall through to
# `securitySensitive: false`. Shadows `grep` with a mock that always exits 2
# to force the failure path deterministically.
mock_bin_dir="$(mktemp -d)"
trap 'rm -f "$tmp_file" "$tmp_diff_hunk_file"; rm -rf "$mock_bin_dir"' EXIT
cat > "$mock_bin_dir/grep" <<'MOCK_GREP'
#!/usr/bin/env bash
exit 2
MOCK_GREP
chmod +x "$mock_bin_dir/grep"
grep_failure_status=0
grep_failure_output="$(PATH="$mock_bin_dir:$PATH" "$CLASSIFIER" classify --finding-text "raw git push --force is used here without a safety lease" --file-path "scripts/development-workflow/workflow-branch-push-guard.sh" 2>&1)" || grep_failure_status=$?
run_test "grep_internal_failure_aborts_loudly" "yes" \
  "$([ "$grep_failure_status" -ne 0 ] && grep -Fq 'internal error' <<< "$grep_failure_output" && echo yes || echo no)"
run_test "grep_internal_failure_never_returns_false" "yes" \
  "$(grep -Fq 'securitySensitive' <<< "$grep_failure_output" && echo no || echo yes)"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi

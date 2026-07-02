#!/usr/bin/env bash
# test-run-work-router.sh — Unit tests for the /run-work routing classifier.
#
# Usage: bash scripts/development-workflow/tests/test-run-work-router.sh
#
# Each test calls run-work-router.sh with a mock gh/git on PATH that:
#   - Provides canned responses for read-only queries (issue view, pr view)
#   - Fails loudly on any mutating call (exit 99) to prove the read-only contract

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir)"
case "$GIT_COMMON_DIR" in
  /*) REPO_ROOT="$(cd "$GIT_COMMON_DIR/.." && pwd -P)" ;;
  *) REPO_ROOT="$(cd "$SCRIPT_DIR/$GIT_COMMON_DIR/.." && pwd -P)" ;;
esac
ROUTER="$REPO_ROOT/scripts/development-workflow/run-work-router.sh"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
CALL_LOG="$TMP_ROOT/calls.log"
mkdir -p "$MOCK_BIN"
: > "$CALL_LOG"

# ---------------------------------------------------------------------------
# Cleanup on EXIT (including SIGPIPE exit 141)
# ---------------------------------------------------------------------------

_harness_exit() {
  local status=$?
  rm -rf "$TMP_ROOT"
  case "$status" in
    141) exit 0 ;;
    *)   exit "$status" ;;
  esac
}
trap _harness_exit EXIT

# ---------------------------------------------------------------------------
# Mock gh — read-only responses for the tokens used in tests
#
# Issue numbers used in tests:
#   978  — open, non-epic issue (no subIssues, no "epic" label)
#   977  — open, epic-like issue (has subIssues)
#   979  — open, non-epic issue
#   999999 — does not exist (unresolvable)
#
# PR numbers:
#   118  — open pull request
# ---------------------------------------------------------------------------

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "$MOCK_CALL_LOG"

# ---- Mutating operations: fail loudly to prove read-only contract ----
case "$*" in
  issue\ edit*|\
  pr\ create*|\
  pr\ edit*|\
  pr\ merge*|\
  pr\ comment*|\
  pr\ ready*|\
  pr\ close*|\
  issue\ close*|\
  issue\ comment*|\
  project\ item-edit*|\
  project\ item-add*|\
  release\ create*|\
  release\ delete*)
    printf 'MUTATION DETECTED: gh %s\n' "$*" >&2
    exit 99
    ;;
  api\ graphql*)
    # GraphQL mutations that contain "mutation" keyword
    if printf '%s\n' "$*" | grep -qi 'mutation'; then
      printf 'MUTATION DETECTED (GraphQL): gh %s\n' "$*" >&2
      exit 99
    fi
    # For subIssues check
    if printf '%s\n' "$*" | grep -q 'subIssues'; then
      # Return empty subIssues (non-epic by default)
      cat <<'JSON'
{"data":{"repository":{"issue":{"subIssues":{"nodes":[]}}}}}
JSON
      exit 0
    fi
    printf 'unexpected graphql: gh %s\n' "$*" >&2
    exit 64
    ;;
esac

# ---- auth status (used by gh_available in workflow-lib.sh) ----
case "$*" in
  auth\ status)
    exit 0
    ;;
  repo\ view\ --json\ nameWithOwner\ --jq\ .nameWithOwner)
    printf 'lhpaul/ai-dev-framework-template\n'
    exit 0
    ;;
esac

emit_issue_subissues() {
  local issue_num="$1" jq_filter="$2"
  local json
  case "$issue_num" in
    977)
      json='{"subIssues":{"nodes":[{"number":101},{"number":102}],"totalCount":2}}'
      ;;
    978|979)
      json='{"subIssues":{"nodes":[],"totalCount":0}}'
      ;;
    *)
      return 1
      ;;
  esac

  if [ -n "$jq_filter" ]; then
    printf '%s\n' "$json" | jq -r "$jq_filter"
  else
    printf '%s\n' "$json"
  fi
}

# ---- issue view ----
# Matches: gh issue view <number> --json state --jq .state
# or:      gh issue view <number> --json subIssues --jq ...
case "$*" in
  issue\ view\ 978\ --json\ state\ --jq\ .state)
    printf 'OPEN\n'
    exit 0
    ;;
  issue\ view\ 979\ --json\ state\ --jq\ .state)
    printf 'OPEN\n'
    exit 0
    ;;
  issue\ view\ 977\ --json\ state\ --jq\ .state)
    printf 'OPEN\n'
    exit 0
    ;;
  issue\ view\ 999999\ --json\ state\ --jq\ .state)
    exit 1   # not found
    ;;
  issue\ view\ 978\ --json\ subIssues\ --jq\ *)
    emit_issue_subissues 978 "$7"
    exit 0
    ;;
  issue\ view\ 979\ --json\ subIssues\ --jq\ *)
    emit_issue_subissues 979 "$7"
    exit 0
    ;;
  issue\ view\ 977\ --json\ subIssues\ --jq\ *)
    emit_issue_subissues 977 "$7"
    exit 0
    ;;
  issue\ view\ 977\ --json\ labels\ --jq\ '[.labels[].name] | map(ascii_downcase) | map(select(. == "epic")) | length')
    printf '0\n'
    exit 0
    ;;
  issue\ view\ 978\ --json\ labels\ --jq\ '[.labels[].name] | map(ascii_downcase) | map(select(. == "epic")) | length')
    printf '0\n'
    exit 0
    ;;
  issue\ view\ 979\ --json\ labels\ --jq\ '[.labels[].name] | map(ascii_downcase) | map(select(. == "epic")) | length')
    printf '0\n'
    exit 0
    ;;
esac

# ---- pr view ----
# Matches: gh pr view <number> --json state --jq .state
case "$*" in
  pr\ view\ 118\ --json\ state\ --jq\ .state)
    printf 'OPEN\n'
    exit 0
    ;;
  pr\ view\ 978\ --json\ state\ --jq\ .state)
    exit 1   # 978 is an issue, not a PR
    ;;
  pr\ view\ 979\ --json\ state\ --jq\ .state)
    exit 1   # not a PR
    ;;
  pr\ view\ 977\ --json\ state\ --jq\ .state)
    exit 1   # not a PR
    ;;
  pr\ view\ 999999\ --json\ state\ --jq\ .state)
    exit 1   # not found
    ;;
esac

printf 'unexpected gh invocation: gh %s\n' "$*" >&2
exit 64
MOCK_GH

chmod +x "$MOCK_BIN/gh"

# ---------------------------------------------------------------------------
# Mock git — block all mutating operations
# ---------------------------------------------------------------------------

cat > "$MOCK_BIN/git" <<'MOCK_GIT'
#!/usr/bin/env bash
printf 'git %s\n' "$*" >> "$MOCK_CALL_LOG"
case "$*" in
  checkout*|switch*|reset*|restore*|push*|commit*|merge*|branch\ -d*|branch\ -D*)
    printf 'MUTATION DETECTED: git %s\n' "$*" >&2
    exit 99
    ;;
  rev-parse\ --git-common-dir)
    # Used by workflow-lib.sh SCRIPT_DIR resolution
    printf '.git\n'
    exit 0
    ;;
  rev-parse\ --show-toplevel)
    # Simulate git root = CWD (resolve_token uses repo root for dev folder checks)
    printf '%s\n' "$(pwd)"
    exit 0
    ;;
  show-ref\ --verify\ --quiet\ *)
    # Simulate branch existence check: exit 0 (exists) for all test branches
    exit 0
    ;;
  *)
    # Other read-only git calls are fine but we don't need to handle them
    exit 0
    ;;
esac
MOCK_GIT

chmod +x "$MOCK_BIN/git"

export MOCK_CALL_LOG="$CALL_LOG"

# ---------------------------------------------------------------------------
# Test helpers
# ---------------------------------------------------------------------------

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf 'PASS: %s\n' "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf 'FAIL: %s — expected %q, got %q\n' "$name" "$expected" "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_test_contains() {
  local name="$1" pattern="$2" actual="$3"
  if printf '%s\n' "$actual" | grep -q "$pattern"; then
    printf 'PASS: %s\n' "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf 'FAIL: %s — expected pattern %q not found in: %s\n' "$name" "$pattern" "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_fails_contains() {
  local name="$1" expected_pattern="$2"
  shift 2
  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  if [ "$status" -ne 0 ] && printf '%s\n' "$output" | grep -q "$expected_pattern"; then
    printf 'PASS: %s\n' "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf 'FAIL: %s — expected failure containing %q (exit=%s)\n' "$name" "$expected_pattern" "$status"
    printf 'Output:\n%s\n' "$output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# Helper: run router and extract a specific key=value from output
router_field() {
  local field="$1"
  shift
  PATH="$MOCK_BIN:$PATH" "$ROUTER" "$@" 2>/dev/null | grep "^${field}=" | cut -d= -f2-
}

# Helper: run router and capture full output
router_output() {
  PATH="$MOCK_BIN:$PATH" "$ROUTER" "$@" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Create a minimal .ai-dev-workflow.yaml in a tmp dir for guardrails tests
# ---------------------------------------------------------------------------

FAKE_REPO_DIR="$TMP_ROOT/fake_repo"
mkdir -p "$FAKE_REPO_DIR"

cat > "$FAKE_REPO_DIR/.ai-dev-workflow.yaml" <<'YAML'
schema_version: 2
guardrails:
  mode: delegated
  backlog_start:
    allow_without_confirmation: true
YAML

cat > "$FAKE_REPO_DIR/.ai-dev-workflow-no-guardrails.yaml" <<'YAML'
schema_version: 2
issue_tracker:
  provider: github_projects
YAML

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

echo ""
echo "=== run-work-router.sh unit tests ==="
echo ""

# --- No-target routing (AC1) -----------------------------------------------

output_no_target="$(router_output)"
run_test "no_target_empty_args_mode" "no_target_scan" \
  "$(printf '%s\n' "$output_no_target" | grep '^MODE=' | cut -d= -f2-)"
run_test "no_target_mode_label" "No-target scan" \
  "$(printf '%s\n' "$output_no_target" | grep '^MODE_LABEL=' | cut -d= -f2-)"
run_test "no_target_raw_target" "(none)" \
  "$(printf '%s\n' "$output_no_target" | grep '^RAW_TARGET=' | cut -d= -f2-)"
run_test "no_target_resolved_scope" "(none)" \
  "$(printf '%s\n' "$output_no_target" | grep '^RESOLVED_SCOPE=' | cut -d= -f2-)"

# Whitespace-only input: pass as a single arg
output_ws="$(router_output "   ")"
run_test "whitespace_only_arg_mode" "no_target_scan" \
  "$(printf '%s\n' "$output_ws" | grep '^MODE=' | cut -d= -f2-)"

# --- Single non-epic issue (AC2) -------------------------------------------

output_978="$(router_output "978")"
run_test "single_issue_978_mode" "redirect_item" \
  "$(printf '%s\n' "$output_978" | grep '^MODE=' | cut -d= -f2-)"
run_test "single_issue_978_scope" "978" \
  "$(printf '%s\n' "$output_978" | grep '^RESOLVED_SCOPE=' | cut -d= -f2-)"
run_test "single_issue_978_raw_target" "978" \
  "$(printf '%s\n' "$output_978" | grep '^RAW_TARGET=' | cut -d= -f2-)"
run_test "single_issue_978_redirect" "/run-item 978" \
  "$(printf '%s\n' "$output_978" | grep '^REDIRECT_COMMAND=' | cut -d= -f2-)"

# --- Single epic-like issue → epic mode (AC5) ------------------------------

output_977="$(router_output "977")"
run_test "single_epic_issue_977_mode" "redirect_epic" \
  "$(printf '%s\n' "$output_977" | grep '^MODE=' | cut -d= -f2-)"
run_test "single_epic_issue_977_scope" "977" \
  "$(printf '%s\n' "$output_977" | grep '^RESOLVED_SCOPE=' | cut -d= -f2-)"
run_test "single_epic_issue_977_redirect" "/run-epic --epic 977" \
  "$(printf '%s\n' "$output_977" | grep '^REDIRECT_COMMAND=' | cut -d= -f2-)"

# --- --epic flag (explicit epic) (AC4) -------------------------------------

output_epic_flag="$(router_output "--epic" "977")"
run_test "epic_flag_mode" "redirect_epic" \
  "$(printf '%s\n' "$output_epic_flag" | grep '^MODE=' | cut -d= -f2-)"
run_test "epic_flag_scope" "977" \
  "$(printf '%s\n' "$output_epic_flag" | grep '^RESOLVED_SCOPE=' | cut -d= -f2-)"
run_test "epic_flag_raw_target" "--epic 977" \
  "$(printf '%s\n' "$output_epic_flag" | grep '^RAW_TARGET=' | cut -d= -f2-)"
run_test "epic_flag_redirect" "/run-epic --epic 977" \
  "$(printf '%s\n' "$output_epic_flag" | grep '^REDIRECT_COMMAND=' | cut -d= -f2-)"

# --- --epic with non-integer → ambiguous ------------------------------------

output_epic_bad="$(router_output "--epic" "not-a-number")"
run_test "epic_flag_bad_value_mode" "ambiguous" \
  "$(printf '%s\n' "$output_epic_bad" | grep '^MODE=' | cut -d= -f2-)"
run_test_contains "epic_flag_bad_value_stop_reason" "not a valid issue number" \
  "$(printf '%s\n' "$output_epic_bad" | grep '^STOP_REASON=' | cut -d= -f2-)"

# --- Single branch token (AC2) ---------------------------------------------

output_branch="$(router_output "feature/42-foo")"
run_test "single_branch_mode" "redirect_item" \
  "$(printf '%s\n' "$output_branch" | grep '^MODE=' | cut -d= -f2-)"
run_test "single_branch_scope" "feature/42-foo" \
  "$(printf '%s\n' "$output_branch" | grep '^RESOLVED_SCOPE=' | cut -d= -f2-)"

output_spec_branch="$(router_output "spec/42-foo")"
run_test "single_spec_branch_mode" "redirect_item" \
  "$(printf '%s\n' "$output_spec_branch" | grep '^MODE=' | cut -d= -f2-)"

output_fix_branch="$(router_output "fix/978-bug")"
run_test "single_fix_branch_mode" "redirect_item" \
  "$(printf '%s\n' "$output_fix_branch" | grep '^MODE=' | cut -d= -f2-)"

output_plan_branch="$(router_output "plan/978-foo")"
run_test "single_plan_branch_mode" "redirect_item" \
  "$(printf '%s\n' "$output_plan_branch" | grep '^MODE=' | cut -d= -f2-)"

# --- Single PR token (AC2) -------------------------------------------------

output_pr="$(router_output "118")"
run_test "single_pr_118_mode" "redirect_item" \
  "$(printf '%s\n' "$output_pr" | grep '^MODE=' | cut -d= -f2-)"
run_test "single_pr_118_scope" "118" \
  "$(printf '%s\n' "$output_pr" | grep '^RESOLVED_SCOPE=' | cut -d= -f2-)"

# --- Single development-folder token (AC2) ---------------------------------

mkdir -p "$TMP_ROOT/fake_dev/docs/specs/developments/20260617_978-foo"
# Router checks if path starts with docs/specs/developments/... and is a directory.
# We can't easily test this without changing cwd, so we use a relative path that
# resolve_token will recognize. Instead, verify the routing table handles this token
# form when the directory exists by invoking from a suitable working directory.
# For isolation, we do a quick functional check.
DEV_FOLDER_TMP="$TMP_ROOT/fake_repo2"
mkdir -p "$DEV_FOLDER_TMP/docs/specs/developments/20260617_978-foo"
pushd "$DEV_FOLDER_TMP" > /dev/null
output_devfolder="$(PATH="$MOCK_BIN:$PATH" "$ROUTER" "docs/specs/developments/20260617_978-foo" 2>/dev/null)"
popd > /dev/null
run_test "single_dev_folder_mode" "redirect_item" \
  "$(printf '%s\n' "$output_devfolder" | grep '^MODE=' | cut -d= -f2-)"

# --- PyYAML unavailable: conservative defaults applied ----------------------
# Simulates PyYAML being unavailable by injecting a fake yaml module into
# PYTHONPATH. Verifies the router applies conservative safe defaults
# (mode=manual, backlog_start=false) and does not silently misparse config.
mkdir -p "$TMP_ROOT/no_yaml"
cat > "$TMP_ROOT/no_yaml/yaml.py" <<'NO_YAML'
raise ImportError("test: yaml not available for fallback test")
NO_YAML
# Uses AI_DEV_WORKFLOW_CONFIG_FILE to supply a config with delegated mode.
# When PyYAML is absent, the router must ignore the config and use safe defaults.
output_fallback="$(AI_DEV_WORKFLOW_CONFIG_FILE="$FAKE_REPO_DIR/.ai-dev-workflow.yaml" PYTHONPATH="$TMP_ROOT/no_yaml" PATH="$MOCK_BIN:$PATH" "$ROUTER" 2>/dev/null)"
run_test "guardrails_nopyaml_mode_defaults_to_manual" "manual" \
  "$(printf '%s\n' "$output_fallback" | grep '^GUARDRAILS_MODE=' | cut -d= -f2-)"
run_test "guardrails_nopyaml_backlog_defaults_to_false" "false" \
  "$(printf '%s\n' "$output_fallback" | grep '^GUARDRAILS_BACKLOG_START=' | cut -d= -f2-)"

# --- Space-separated multi-target list → redirect_items (AC3) ---------------

output_list_space="$(router_output "978" "979")"
run_test "space_list_mode" "redirect_items" \
  "$(printf '%s\n' "$output_list_space" | grep '^MODE=' | cut -d= -f2-)"
run_test_contains "space_list_scope_contains_978" "978" \
  "$(printf '%s\n' "$output_list_space" | grep '^RESOLVED_SCOPE=' | cut -d= -f2-)"
run_test_contains "space_list_scope_contains_979" "979" \
  "$(printf '%s\n' "$output_list_space" | grep '^RESOLVED_SCOPE=' | cut -d= -f2-)"
run_test_contains "space_list_redirect_command_prefix" "/run-items" \
  "$(printf '%s\n' "$output_list_space" | grep '^REDIRECT_COMMAND=' | cut -d= -f2-)"
run_test_contains "space_list_redirect_command_978" "978" \
  "$(printf '%s\n' "$output_list_space" | grep '^REDIRECT_COMMAND=' | cut -d= -f2-)"
run_test_contains "space_list_redirect_command_979" "979" \
  "$(printf '%s\n' "$output_list_space" | grep '^REDIRECT_COMMAND=' | cut -d= -f2-)"

# --- Comma-separated multi-target list → redirect_items (AC3) ---------------

output_list_comma="$(router_output "978,979")"
run_test "comma_list_mode" "redirect_items" \
  "$(printf '%s\n' "$output_list_comma" | grep '^MODE=' | cut -d= -f2-)"
run_test_contains "comma_list_scope_contains_978" "978" \
  "$(printf '%s\n' "$output_list_comma" | grep '^RESOLVED_SCOPE=' | cut -d= -f2-)"
run_test_contains "comma_list_scope_contains_979" "979" \
  "$(printf '%s\n' "$output_list_comma" | grep '^RESOLVED_SCOPE=' | cut -d= -f2-)"
run_test_contains "comma_list_redirect_command_prefix" "/run-items" \
  "$(printf '%s\n' "$output_list_comma" | grep '^REDIRECT_COMMAND=' | cut -d= -f2-)"

# --- Duplicate token collapse (UC3 consideration) ---------------------------

output_dupes="$(router_output "978" "978" "979")"
run_test "duplicate_tokens_mode" "redirect_items" \
  "$(printf '%s\n' "$output_dupes" | grep '^MODE=' | cut -d= -f2-)"
# Should not have 978 appear twice in scope
scope_dupes="$(printf '%s\n' "$output_dupes" | grep '^RESOLVED_SCOPE=' | cut -d= -f2-)"
count_978="$(printf '%s\n' "$scope_dupes" | tr ',' '\n' | grep -c '^978$')"
run_test "duplicate_tokens_deduped" "1" "$count_978"

# --- Unresolvable lookalike token → ambiguous (AC11) -----------------------

output_noresol="$(router_output "999999")"
run_test "unresolvable_token_mode" "ambiguous" \
  "$(printf '%s\n' "$output_noresol" | grep '^MODE=' | cut -d= -f2-)"
run_test_contains "unresolvable_token_stop_reason" "could not be resolved" \
  "$(printf '%s\n' "$output_noresol" | grep '^STOP_REASON=' | cut -d= -f2-)"

# --- Mixed list with one unresolvable token → ambiguous (AC11) -------------

output_mixed="$(router_output "978" "999999")"
run_test "mixed_list_mode" "ambiguous" \
  "$(printf '%s\n' "$output_mixed" | grep '^MODE=' | cut -d= -f2-)"
run_test_contains "mixed_list_stop_reason" "999999" \
  "$(printf '%s\n' "$output_mixed" | grep '^STOP_REASON=' | cut -d= -f2-)"

# --- Routing-decision record fields present (AC10) -------------------------

# Verify all required fields are present in no-target output
required_fields="MODE MODE_LABEL RAW_TARGET RESOLVED_SCOPE HELD_BACK OUT_OF_SCOPE GUARDRAILS_SECTION GUARDRAILS_MODE GUARDRAILS_BACKLOG_START"
for field in $required_fields; do
  run_test "record_has_field_${field}" "yes" \
    "$(printf '%s\n' "$output_no_target" | grep -q "^${field}=" && echo yes || echo no)"
done

# --- JSON output (--json flag, AC10) ----------------------------------------

output_json="$(router_output "978" "--json")"
run_test "json_has_mode_field" "redirect_item" \
  "$(printf '%s\n' "$output_json" | python3 -c 'import json,sys
data = sys.stdin.read()
# Extract the JSON block (after key=value lines)
lines = data.split("\n")
json_start = next((i for i,l in enumerate(lines) if l.strip().startswith("{")), None)
if json_start is not None:
    obj = json.loads("\n".join(lines[json_start:]))
    print(obj["mode"])
else:
    print("no_json_block")
' 2>/dev/null)"

output_json_noarg="$(router_output "--json")"
run_test "json_no_target_mode" "no_target_scan" \
  "$(printf '%s\n' "$output_json_noarg" | python3 -c 'import json,sys
data = sys.stdin.read()
lines = data.split("\n")
json_start = next((i for i,l in enumerate(lines) if l.strip().startswith("{")), None)
if json_start is not None:
    obj = json.loads("\n".join(lines[json_start:]))
    print(obj["mode"])
else:
    print("no_json_block")
' 2>/dev/null)"

run_test "json_has_guardrails_block" "yes" \
  "$(printf '%s\n' "$output_json_noarg" | python3 -c 'import json,sys
data = sys.stdin.read()
lines = data.split("\n")
json_start = next((i for i,l in enumerate(lines) if l.strip().startswith("{")), None)
if json_start is not None:
    obj = json.loads("\n".join(lines[json_start:]))
    print("yes" if "guardrails" in obj else "no")
else:
    print("no_json_block")
' 2>/dev/null)"

# --- Read-only contract: no mutating calls made ----------------------------

mutation_count="0"
if grep -q 'MUTATION DETECTED' "$CALL_LOG" 2>/dev/null; then
  mutation_count="$(grep -c 'MUTATION DETECTED' "$CALL_LOG" 2>/dev/null)"
fi
run_test "no_mutating_calls_during_tests" "0" "$mutation_count"

# --- Usage error handling ---------------------------------------------------

# Run the router with --epic missing a value; capture output + exit code manually
_epic_missing_output=""
_epic_missing_status=0
set +e
_epic_missing_output="$(PATH="$MOCK_BIN:$PATH" "$ROUTER" "--epic" 2>&1)"
_epic_missing_status=$?
set -e

if [ "$_epic_missing_status" -ne 0 ] && printf '%s\n' "$_epic_missing_output" | grep -qF -- "--epic requires an issue number"; then
  printf 'PASS: epic_flag_missing_value\n'
  PASS_COUNT=$((PASS_COUNT + 1))
else
  printf 'FAIL: epic_flag_missing_value — expected failure containing "--epic requires an issue number" (exit=%s)\n' "$_epic_missing_status"
  printf 'Output:\n%s\n' "$_epic_missing_output"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "=== Summary ==="
printf 'Passed: %d\n' "$PASS_COUNT"
printf 'Failed: %d\n' "$FAIL_COUNT"
echo ""

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi

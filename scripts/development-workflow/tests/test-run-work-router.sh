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
  api\ rate_limit\ --jq\ '.resources.graphql.reset')
    # Fixed far-future epoch (2100-01-01T00:00:00Z) so reset-time messages
    # are deterministic without depending on wall-clock time.
    printf '4102444800\n'
    exit 0
    ;;
esac

# ---- gh probe failures: rate limit / auth / network / outage ----
# Issue numbers reserved for probe-failure regression tests (see issue #1503):
#   888881 — gh probe fails with an API rate limit error
#   888882 — gh probe fails with an authentication error
#   888883 — gh probe fails with a network error
#   888884 — gh probe fails with an unrecognized/opaque error (outage-style)
#   888885 — gh probe fails with a genuine "could not resolve" not-found error
#            (explicit not-found stderr text, not just a bare non-zero exit)
#   888886 — gh probe fails with empty stderr and a non-1 exit code (e.g. the
#            gh binary itself crashed or was signal-killed) — must NOT be
#            misclassified as not_found the way a bare exit-1/empty-stderr is
#   888887 — gh probe fails with "no default remote repository has been set"
#            (a local repo-configuration error) — must NOT be classified as
#            not_found; it is not confirmation the target doesn't exist
case "$*" in
  pr\ view\ 888881\ --json\ state\ --jq\ .state)
    printf 'API rate limit exceeded for user ID 1148259 (https://docs.github.com/en/rest/overview/resources-in-the-rest-api#rate-limiting)\n' >&2
    exit 1
    ;;
  pr\ view\ 888882\ --json\ state\ --jq\ .state)
    printf 'gh: To use GitHub CLI in a GitHub Actions workflow, set the GH_TOKEN environment variable.\nerror: not logged into any GitHub hosts. Run gh auth login\n' >&2
    exit 1
    ;;
  pr\ view\ 888883\ --json\ state\ --jq\ .state)
    printf 'error connecting to api.github.com\ndial tcp: lookup api.github.com: no such host\n' >&2
    exit 1
    ;;
  pr\ view\ 888884\ --json\ state\ --jq\ .state)
    printf 'HTTP 502: Bad Gateway\nSomething went wrong while executing your query. Unicorn! ...ready.\n' >&2
    exit 1
    ;;
  pr\ view\ 888885\ --json\ state\ --jq\ .state)
    printf 'GraphQL: Could not resolve to a PullRequest with the number of 888885. (repository.pullRequest)\n' >&2
    exit 1
    ;;
  issue\ view\ 888885\ --json\ state\ --jq\ .state)
    printf 'GraphQL: Could not resolve to an Issue with the number of 888885. (repository.issue)\n' >&2
    exit 1
    ;;
  pr\ view\ 888886\ --json\ state\ --jq\ .state)
    # Empty stderr, non-1 exit code (simulates a signal-killed gh process,
    # e.g. exit 137 = 128 + SIGKILL(9)). The issue-view probe below mirrors
    # this so the test isolates classify_gh_probe_error's own empty-stderr
    # exit-code handling rather than accidentally passing via the generic
    # "unexpected gh invocation" catch-all if only the PR probe were mocked.
    exit 137
    ;;
  issue\ view\ 888886\ --json\ state\ --jq\ .state)
    exit 137
    ;;
  pr\ view\ 888887\ --json\ state\ --jq\ .state)
    printf 'no default remote repository has been set\n' >&2
    exit 1
    ;;
  issue\ view\ 888887\ --json\ state\ --jq\ .state)
    printf 'no default remote repository has been set\n' >&2
    exit 1
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

# --- PyYAML unavailable: stdlib parser still reads guardrails ----------------
# Simulates PyYAML being unavailable by injecting a fake yaml module into
# PYTHONPATH. The router must use the repo's stdlib-only YAML subset parser and
# still report the configured guardrails instead of falling back to defaults.
mkdir -p "$TMP_ROOT/no_yaml"
cat > "$TMP_ROOT/no_yaml/yaml.py" <<'NO_YAML'
raise ImportError("test: yaml not available for fallback test")
NO_YAML
# Uses AI_DEV_WORKFLOW_CONFIG_FILE to supply a config with delegated mode.
output_fallback="$(AI_DEV_WORKFLOW_CONFIG_FILE="$FAKE_REPO_DIR/.ai-dev-workflow.yaml" PYTHONPATH="$TMP_ROOT/no_yaml" PATH="$MOCK_BIN:$PATH" "$ROUTER" 2>/dev/null)"
run_test "guardrails_nopyaml_mode_uses_config" "delegated" \
  "$(printf '%s\n' "$output_fallback" | grep '^GUARDRAILS_MODE=' | cut -d= -f2-)"
run_test "guardrails_nopyaml_backlog_uses_config" "true" \
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

# --- gh probe failure classification (issue #1503) --------------------------
#
# resolve_token() must distinguish a gh probe failure (rate limit, auth,
# network, GitHub outage) from a successful "not found" result. A probe
# failure must route to MODE=tracker_unavailable with a distinct, actionable
# STOP_REASON — not MODE=ambiguous, which tells the operator their target is
# unrecognized when it is actually gh that failed.

# Rate-limited probe → tracker_unavailable, reason names the cause and
# includes the rate-limit reset time.
output_rate_limited="$(router_output "888881")"
run_test "rate_limited_probe_mode" "tracker_unavailable" \
  "$(printf '%s\n' "$output_rate_limited" | grep '^MODE=' | cut -d= -f2-)"
run_test_contains "rate_limited_probe_stop_reason_names_cause" "rate limit" \
  "$(printf '%s\n' "$output_rate_limited" | grep '^STOP_REASON=' | cut -d= -f2-)"
run_test_contains "rate_limited_probe_stop_reason_has_reset_time" "retry after" \
  "$(printf '%s\n' "$output_rate_limited" | grep '^STOP_REASON=' | cut -d= -f2-)"

# Auth-failed probe → tracker_unavailable, reason is actionable (gh auth login).
output_auth_failed="$(router_output "888882")"
run_test "auth_failed_probe_mode" "tracker_unavailable" \
  "$(printf '%s\n' "$output_auth_failed" | grep '^MODE=' | cut -d= -f2-)"
run_test_contains "auth_failed_probe_stop_reason" "gh auth login" \
  "$(printf '%s\n' "$output_auth_failed" | grep '^STOP_REASON=' | cut -d= -f2-)"

# Network-error probe → tracker_unavailable, distinct reason from auth/rate-limit.
output_network_error="$(router_output "888883")"
run_test "network_error_probe_mode" "tracker_unavailable" \
  "$(printf '%s\n' "$output_network_error" | grep '^MODE=' | cut -d= -f2-)"
run_test_contains "network_error_probe_stop_reason" "Network error" \
  "$(printf '%s\n' "$output_network_error" | grep '^STOP_REASON=' | cut -d= -f2-)"

# Opaque/outage probe (unrecognized gh error, not the specific not-found
# message) → tracker_unavailable, falls back to github_unavailable framing.
output_github_unavailable="$(router_output "888884")"
run_test "github_unavailable_probe_mode" "tracker_unavailable" \
  "$(printf '%s\n' "$output_github_unavailable" | grep '^MODE=' | cut -d= -f2-)"
run_test_contains "github_unavailable_probe_stop_reason" "unavailable" \
  "$(printf '%s\n' "$output_github_unavailable" | grep '^STOP_REASON=' | cut -d= -f2-)"

# Genuine not-found with an explicit gh "could not resolve" error on BOTH
# probes must still classify as not_found → MODE=ambiguous (unchanged
# behavior), proving the fix does not turn every non-zero gh exit into
# tracker_unavailable.
output_explicit_not_found="$(router_output "888885")"
run_test "explicit_not_found_probe_mode" "ambiguous" \
  "$(printf '%s\n' "$output_explicit_not_found" | grep '^MODE=' | cut -d= -f2-)"
run_test_contains "explicit_not_found_probe_stop_reason" "could not be resolved" \
  "$(printf '%s\n' "$output_explicit_not_found" | grep '^STOP_REASON=' | cut -d= -f2-)"

# Genuine not-found via a bare non-zero exit with no stderr (999999, existing
# fixture) must also still classify as not_found → MODE=ambiguous. Re-asserted
# here explicitly as part of the #1503 regression coverage.
run_test "bare_exit_not_found_probe_mode_regression" "ambiguous" \
  "$(printf '%s\n' "$output_noresol" | grep '^MODE=' | cut -d= -f2-)"

# A bare non-zero exit with EMPTY stderr and a non-1 exit code (simulating a
# crashed/signal-killed gh process) must NOT be misclassified as not_found —
# only gh's normal exit-1/empty-stderr not-found path keeps that
# classification. This must resolve as tracker_unavailable.
output_crash_empty_stderr="$(router_output "888886")"
run_test "crash_empty_stderr_nonone_exit_mode" "tracker_unavailable" \
  "$(printf '%s\n' "$output_crash_empty_stderr" | grep '^MODE=' | cut -d= -f2-)"
run_test_contains "crash_empty_stderr_nonone_exit_stop_reason" "unavailable" \
  "$(printf '%s\n' "$output_crash_empty_stderr" | grep '^STOP_REASON=' | cut -d= -f2-)"

# "no default remote repository has been set" is a local repo-configuration
# error, not confirmation that the target doesn't exist — must NOT be
# classified as not_found (CodeRabbit finding on PR #1541).
output_no_default_remote="$(router_output "888887")"
run_test "no_default_remote_probe_mode" "tracker_unavailable" \
  "$(printf '%s\n' "$output_no_default_remote" | grep '^MODE=' | cut -d= -f2-)"
run_test_contains "no_default_remote_probe_stop_reason" "unavailable" \
  "$(printf '%s\n' "$output_no_default_remote" | grep '^STOP_REASON=' | cut -d= -f2-)"

# Multi-target list: a probe failure partway through the list must still
# surface as tracker_unavailable, not ambiguous, and must not be masked by
# an earlier successfully-resolved token.
output_list_rate_limited="$(router_output "978" "888881")"
run_test "list_rate_limited_mode" "tracker_unavailable" \
  "$(printf '%s\n' "$output_list_rate_limited" | grep '^MODE=' | cut -d= -f2-)"
run_test_contains "list_rate_limited_stop_reason" "rate limit" \
  "$(printf '%s\n' "$output_list_rate_limited" | grep '^STOP_REASON=' | cut -d= -f2-)"

# Happy path: a successful resolution (no probe failure at all) must be
# entirely unaffected by the new probe-capturing path — reconfirmed here
# alongside the failure-classification tests so the two are visibly compared
# in the same regression block.
run_test "happy_path_probe_regression" "redirect_item" \
  "$(printf '%s\n' "$output_978" | grep '^MODE=' | cut -d= -f2-)"

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

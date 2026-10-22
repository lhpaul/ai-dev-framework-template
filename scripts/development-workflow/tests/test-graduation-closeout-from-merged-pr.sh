#!/usr/bin/env bash
# test-graduation-closeout-from-merged-pr.sh - merge-time graduation closeout wrapper tests.
#
# covers: scripts/development-workflow/graduation-closeout-from-merged-pr.sh
# covers: scripts/development-workflow/graduation-closeout-lib.sh
#         (Linear tracker safety with graduation-closeout.sh)
#
# Usage: bash scripts/development-workflow/tests/test-graduation-closeout-from-merged-pr.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
FIXTURE_REPO="$TMP_ROOT/repo"
MOCK_STATE_DIR="$TMP_ROOT/state"
CHILD_ARGV_LOG="$TMP_ROOT/child-argv.log"
MOCK_GH_LOG="$TMP_ROOT/gh-invocations.log"
MOCK_GRAPHQL_LOG="$TMP_ROOT/graphql.log"
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  local status=$?
  rm -rf "$TMP_ROOT"
  case "$status" in
    141) exit 0 ;;
    *) exit "$status" ;;
  esac
}
trap cleanup EXIT

mkdir -p "$MOCK_BIN" "$FIXTURE_REPO/scripts/development-workflow" "$MOCK_STATE_DIR"

cp "$REPO_ROOT/scripts/development-workflow/graduation-closeout-from-merged-pr.sh" \
  "$FIXTURE_REPO/scripts/development-workflow/graduation-closeout-from-merged-pr.sh"
cp "$REPO_ROOT/scripts/development-workflow/closing-keyword-lib.sh" \
  "$FIXTURE_REPO/scripts/development-workflow/closing-keyword-lib.sh"
cp "$REPO_ROOT/scripts/development-workflow/graduation-closeout-lib.sh" \
  "$FIXTURE_REPO/scripts/development-workflow/graduation-closeout-lib.sh"
chmod +x "$FIXTURE_REPO/scripts/development-workflow/graduation-closeout-from-merged-pr.sh"

# Stub child reconciler — assert argv, do not re-test full closeout matrix.
cat > "$FIXTURE_REPO/scripts/development-workflow/graduation-closeout.sh" <<'CHILD'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "${CHILD_ARGV_LOG:?}"
if [ "${MOCK_CHILD_FAIL:-0}" = "1" ]; then
  echo "GRADUATION_CLOSEOUT_RESULT=failed"
  exit 1
fi
echo "GRADUATION_CLOSEOUT_RESULT=pass"
echo "EPIC_RESULT=closed"
exit 0
CHILD
chmod +x "$FIXTURE_REPO/scripts/development-workflow/graduation-closeout.sh"

# Real workflow-lib for shared + closeout-local provider resolution.
cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" \
  "$FIXTURE_REPO/scripts/development-workflow/workflow-lib.sh"
cat >> "$FIXTURE_REPO/scripts/development-workflow/workflow-lib.sh" <<'FIXTURE_OVERRIDES'

# --- fixture overrides ---
repo_slug() {
  printf 'lhpaul/ai-dev-framework-template\n'
}
FIXTURE_OVERRIDES

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >> "${MOCK_GH_LOG:?}"
case "$*" in
  "auth status")
    exit 0
    ;;
  pr\ view\ *\ --json\ number,state,mergedAt,baseRefName,headRefName,title,body,merged)
    pr="$3"
    file="$MOCK_STATE_DIR/pr-${pr}.json"
    if [ ! -f "$file" ]; then
      printf 'missing fixture for pr #%s\n' "$pr" >&2
      exit 44
    fi
    cat "$file"
    ;;
  issue\ list\ --label\ integration-branch:*\ --state\ all\ --limit\ 1000\ --json\ number)
    label_mode="${MOCK_LABEL_PARENT_MODE:-ok}"
    case "$label_mode" in
      fail)
        printf 'mock label list failure\n' >&2
        exit 47
        ;;
      empty)
        printf '[]\n'
        ;;
      diverge)
        printf '[{"number":101},{"number":102}]\n'
        ;;
      *)
        printf '[{"number":101},{"number":102}]\n'
        ;;
    esac
    ;;
  api\ graphql*)
    # Parent lookup for label-discovered children.
    child=""
    idx=1
    while [ "$idx" -le "$#" ]; do
      if [ "${!idx}" = "-F" ]; then
        next=$((idx + 1))
        val="${!next:-}"
        case "$val" in
          number=*)
            child="${val#number=}"
            printf '%s\n' "$child" >> "${MOCK_GRAPHQL_LOG:?}"
            ;;
        esac
      fi
      idx=$((idx + 1))
    done
    parent="${MOCK_PARENT_DEFAULT:-900}"
    if [ "${MOCK_LABEL_PARENT_MODE:-ok}" = "diverge" ]; then
      if [ "$child" = "101" ]; then
        parent=900
      else
        parent=901
      fi
    fi
    if [ "${MOCK_LABEL_PARENT_MODE:-ok}" = "missing_parents" ]; then
      printf '{"data":{"repository":{"issue":{"parent":null}}}}\n'
      exit 0
    fi
    printf '{"data":{"repository":{"issue":{"parent":{"number":%s}}}}}\n' "$parent"
    ;;
  issue\ view\ *\ --json\ labels\ --jq\ *)
    issue="$3"
    file="$MOCK_STATE_DIR/issue-${issue}-labels.txt"
    if [ -f "$file" ]; then
      # Emulate jq join(",", labels) — no trailing newline.
      tr -d '\n' < "$file"
    else
      printf ''
    fi
    printf '\n'
    ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"

export PATH="$MOCK_BIN:$PATH"
export WORKFLOW_FIXTURE_REPO="$FIXTURE_REPO"
export MOCK_STATE_DIR CHILD_ARGV_LOG MOCK_GH_LOG MOCK_GRAPHQL_LOG

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

run_contains() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if grep -Fq -- "$expected" <<< "$actual"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected output to contain '${expected}'"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_not_contains() {
  local name="$1"
  local unexpected="$2"
  local actual="$3"
  if grep -Fq -- "$unexpected" <<< "$actual"; then
    echo "FAIL: $name - output unexpectedly contained '${unexpected}'"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  fi
}

write_pr() {
  local number="$1"
  local head="$2"
  local base="$3"
  local merged="$4"
  local title="$5"
  local body="$6"
  python3 - "$MOCK_STATE_DIR/pr-${number}.json" "$number" "$head" "$base" "$merged" "$title" "$body" <<'PY'
import json, sys
path, number, head, base, merged, title, body = sys.argv[1:8]
payload = {
    "number": int(number),
    "state": "MERGED" if merged == "true" else "OPEN",
    "mergedAt": "2026-07-21T12:00:00Z" if merged == "true" else None,
    "merged": merged == "true",
    "baseRefName": base,
    "headRefName": head,
    "title": title,
    "body": body,
}
json.dump(payload, open(path, "w"))
PY
}

write_tracker_config() {
  local provider="$1"
  cat > "$FIXTURE_REPO/.ai-dev-workflow.yaml" <<EOF
issue_tracker:
  provider: ${provider}
EOF
}

reset_fixture() {
  rm -f "$MOCK_STATE_DIR"/* "$CHILD_ARGV_LOG" "$MOCK_GH_LOG" "$MOCK_GRAPHQL_LOG"
  rm -f "$FIXTURE_REPO/.ai-dev-workflow.yaml"
  : > "$MOCK_GH_LOG"
  : > "$MOCK_GRAPHQL_LOG"
  unset MOCK_LABEL_PARENT_MODE MOCK_PARENT_DEFAULT MOCK_CHILD_FAIL
  export MOCK_LABEL_PARENT_MODE=empty
}

run_wrapper() {
  local output status
  set +e
  output="$(cd "$FIXTURE_REPO" && ./scripts/development-workflow/graduation-closeout-from-merged-pr.sh "$@" 2>&1)"
  status=$?
  set -e
  printf '%s\n%s\n' "$status" "$output"
}

last_body() { tail -n +2 <<< "$1"; }
last_status() { head -n 1 <<< "$1"; }

echo ""
echo "=== wrapper: valid slug + Epic ref delegates to reconciler ==="
reset_fixture
write_pr 77 "develop-my.feature_1" "develop" "true" "Graduate my.feature_1" "Epic #900\nCloses nothing else."
export MOCK_LABEL_PARENT_MODE=empty
result="$(run_wrapper --graduation-pr 77)"
body="$(last_body "$result")"
run_test "valid_slug_exit_zero" "0" "$(last_status "$result")"
run_contains "valid_slug_extracted" "SLUG=my.feature_1" "$body"
run_contains "epic_from_pr" "EPIC_ISSUE=900" "$body"
run_contains "epic_source_pr" "EPIC_SOURCE=pr_reference" "$body"
run_contains "child_argv_slug" "--slug my.feature_1" "$(cat "$CHILD_ARGV_LOG")"
run_contains "child_argv_epic" "--epic 900" "$(cat "$CHILD_ARGV_LOG")"
run_contains "child_argv_pr" "--graduation-pr 77" "$(cat "$CHILD_ARGV_LOG")"
run_contains "pass_result" "GRADUATION_CLOSEOUT_FROM_MERGED_PR_RESULT=pass" "$body"

echo ""
echo "=== wrapper: invalid slug chars fail closed ==="
reset_fixture
write_pr 78 "develop-my feature" "develop" "true" "Bad slug" "Epic #900"
result="$(run_wrapper --graduation-pr 78)"
body="$(last_body "$result")"
run_test "invalid_slug_exit_one" "1" "$(last_status "$result")"
run_contains "invalid_slug_reason" "invalid_graduation_slug" "$body"
run_test "invalid_slug_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"

echo ""
echo "=== wrapper: non-graduation head fails closed ==="
reset_fixture
write_pr 79 "feature/develop-123-x" "develop" "true" "Not graduation" "Epic #900"
result="$(run_wrapper --graduation-pr 79)"
body="$(last_body "$result")"
run_test "non_grad_exit_one" "1" "$(last_status "$result")"
run_contains "non_grad_reason" "head_not_graduation_branch" "$body"
run_test "non_grad_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"

echo ""
echo "=== wrapper: multiple closing refs fail closed without convergent parent ==="
reset_fixture
export MOCK_LABEL_PARENT_MODE=empty
write_pr 80 "develop-test-1281" "develop" "true" "Closes #10 and Closes #11" "Closes #10\nCloses #11"
result="$(run_wrapper --graduation-pr 80)"
body="$(last_body "$result")"
run_test "multi_ref_exit_one" "1" "$(last_status "$result")"
run_contains "multi_ref_reason" "ambiguous_epic_candidates" "$body"

echo ""
echo "=== wrapper: nested/related refs ignored; Epic # wins ==="
reset_fixture
export MOCK_LABEL_PARENT_MODE=empty
write_pr 81 "develop-test-1281" "develop" "true" "Graduate" $'see #12\nCloses issue #12\nEpic #900\nowner/repo#395'
result="$(run_wrapper --graduation-pr 81)"
body="$(last_body "$result")"
# Closing keyword Closes issue #12 and Epic #900 → two candidates → ambiguous without parents
# Unless Epic # and closing keyword both present - that's ambiguous. Use only Epic line:
write_pr 81 "develop-test-1281" "develop" "true" "Graduate" $'see #12\nnot closing #397\nEpic #900\n```\nCloses #999\n```'
result="$(run_wrapper --graduation-pr 81)"
body="$(last_body "$result")"
run_test "fence_ignored_exit_zero" "0" "$(last_status "$result")"
run_contains "fence_ignored_epic" "EPIC_ISSUE=900" "$body"
run_contains "fence_example_not_used" "EPIC_SOURCE=pr_reference" "$body"

echo ""
echo "=== wrapper: Parent # accepted ==="
reset_fixture
export MOCK_LABEL_PARENT_MODE=empty
write_pr 82 "develop-test-1281" "develop" "true" "Graduate" "Parent #901"
result="$(run_wrapper --graduation-pr 82)"
body="$(last_body "$result")"
run_test "parent_ref_exit_zero" "0" "$(last_status "$result")"
run_contains "parent_ref_epic" "EPIC_ISSUE=901" "$body"

echo ""
echo "=== wrapper: converging label parents discover epic ==="
reset_fixture
export MOCK_LABEL_PARENT_MODE=ok
export MOCK_PARENT_DEFAULT=900
write_pr 83 "develop-test-1281" "develop" "true" "Graduate" "No epic line here"
result="$(run_wrapper --graduation-pr 83)"
body="$(last_body "$result")"
run_test "label_parent_exit_zero" "0" "$(last_status "$result")"
run_contains "label_parent_epic" "EPIC_ISSUE=900" "$body"
run_contains "label_parent_source" "EPIC_SOURCE=label_parent_converged" "$body"

echo ""
echo "=== wrapper: diverging label parents fail closed ==="
reset_fixture
export MOCK_LABEL_PARENT_MODE=diverge
write_pr 84 "develop-test-1281" "develop" "true" "Graduate" "No epic"
result="$(run_wrapper --graduation-pr 84)"
body="$(last_body "$result")"
run_test "diverge_exit_one" "1" "$(last_status "$result")"
run_contains "diverge_reason" "epic_discovery_failed" "$body"

echo ""
echo "=== wrapper: defer-epic-close label passes flag to child ==="
reset_fixture
export MOCK_LABEL_PARENT_MODE=empty
write_pr 85 "develop-test-1281" "develop" "true" "Graduate" "Epic #900"
printf '%s' 'defer-epic-close' > "$MOCK_STATE_DIR/issue-900-labels.txt"
result="$(run_wrapper --graduation-pr 85)"
body="$(last_body "$result")"
run_test "defer_label_exit_zero" "0" "$(last_status "$result")"
run_contains "defer_source_label" "DEFER_SOURCE=epic_label" "$body"
run_contains "defer_child_flag" "--defer-epic-close" "$(cat "$CHILD_ARGV_LOG")"

echo ""
echo "=== wrapper: CLI defer override ==="
reset_fixture
export MOCK_LABEL_PARENT_MODE=empty
write_pr 86 "develop-test-1281" "develop" "true" "Graduate" "Epic #900"
result="$(run_wrapper --graduation-pr 86 --defer-epic-close)"
body="$(last_body "$result")"
run_test "defer_cli_exit_zero" "0" "$(last_status "$result")"
run_contains "defer_source_cli" "DEFER_SOURCE=cli" "$body"
run_contains "defer_cli_child_flag" "--defer-epic-close" "$(cat "$CHILD_ARGV_LOG")"

echo ""
echo "=== wrapper: exclude-issue forwarded ==="
reset_fixture
export MOCK_LABEL_PARENT_MODE=empty
write_pr 87 "develop-test-1281" "develop" "true" "Graduate" "Epic #900"
result="$(run_wrapper --graduation-pr 87 --exclude-issue 501 --exclude-issue 502)"
run_test "exclude_exit_zero" "0" "$(last_status "$result")"
run_contains "exclude_forwarded" "--exclude-issue 501 --exclude-issue 502" "$(cat "$CHILD_ARGV_LOG")"

echo ""
echo "=== wrapper: unmerged PR fails closed ==="
reset_fixture
write_pr 88 "develop-test-1281" "develop" "false" "Open grad" "Epic #900"
result="$(run_wrapper --graduation-pr 88)"
body="$(last_body "$result")"
run_test "unmerged_exit_one" "1" "$(last_status "$result")"
run_contains "unmerged_reason" "graduation_pr_not_merged" "$body"

echo ""
echo "=== wrapper: Linear epic LEA-326 from PR body; no GH #326 mutations (#1984) ==="
reset_fixture
write_tracker_config linear
export MOCK_LABEL_PARENT_MODE=ok
export MOCK_PARENT_DEFAULT=326
write_pr 90 "develop-test-1984" "develop" "true" "Graduate" "Epic LEA-326"
result="$(run_wrapper --graduation-pr 90)"
body="$(last_body "$result")"
run_test "linear_wrapper_exit_zero" "0" "$(last_status "$result")"
run_contains "linear_wrapper_epic" "EPIC_ISSUE=LEA-326" "$body"
run_contains "linear_wrapper_provider" "TRACKER_PROVIDER=linear" "$body"
run_contains "linear_child_epic" "--epic LEA-326" "$(cat "$CHILD_ARGV_LOG")"
run_test "linear_wrapper_no_parent_graphql" "" "$(cat "$MOCK_GRAPHQL_LOG")"
run_not_contains "linear_wrapper_no_issue_view_326" "issue view 326" "$(cat "$MOCK_GH_LOG")"

echo ""
echo "=== wrapper: Linear bare --epic 326 fails closed (#1984) ==="
reset_fixture
write_tracker_config linear
write_pr 91 "develop-test-1984" "develop" "true" "Graduate" "Epic LEA-326"
result="$(run_wrapper --graduation-pr 91 --epic 326)"
body="$(last_body "$result")"
run_test "linear_wrapper_bare_exit_64" "64" "$(last_status "$result")"
run_contains "linear_wrapper_bare_error" "native Linear ID" "$body"
run_test "linear_wrapper_bare_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"

echo ""
echo "=== wrapper: Linear --dry-run forwarded to child (#1984) ==="
reset_fixture
write_tracker_config linear
write_pr 92 "develop-test-1984" "develop" "true" "Graduate" "Epic LEA-326"
result="$(run_wrapper --graduation-pr 92 --dry-run)"
body="$(last_body "$result")"
run_test "linear_wrapper_dry_exit_zero" "0" "$(last_status "$result")"
run_contains "linear_wrapper_dry_flag" "DRY_RUN=1" "$body"
run_contains "linear_wrapper_dry_child" "--dry-run" "$(cat "$CHILD_ARGV_LOG")"

echo ""
echo "=== wrapper: Linear ignores tilde-fenced example Epic LEA-999 (#1984 Pass 2) ==="
reset_fixture
write_tracker_config linear
export MOCK_LABEL_PARENT_MODE=empty
write_pr 94 "develop-test-1984" "develop" "true" "Graduate" $'Example only:\n~~~\nEpic LEA-999\n~~~\nNo live epic.'
result="$(run_wrapper --graduation-pr 94)"
body="$(last_body "$result")"
run_test "linear_tilde_fence_exit_one" "1" "$(last_status "$result")"
run_contains "linear_tilde_fence_reason" "epic_discovery_failed" "$body"
run_test "linear_tilde_fence_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"
run_not_contains "linear_tilde_fence_no_lea999" "LEA-999" "$( [ -f "$CHILD_ARGV_LOG" ] && cat "$CHILD_ARGV_LOG" || true )"

echo ""
echo "=== wrapper: Linear ignores unclosed-fence example Epic LEA-999 (#1984 Pass 2) ==="
reset_fixture
write_tracker_config linear
export MOCK_LABEL_PARENT_MODE=empty
write_pr 95 "develop-test-1984" "develop" "true" "Graduate" $'Example only:\n```text\nEpic LEA-999\n'
result="$(run_wrapper --graduation-pr 95)"
body="$(last_body "$result")"
run_test "linear_unclosed_fence_exit_one" "1" "$(last_status "$result")"
run_contains "linear_unclosed_fence_reason" "epic_discovery_failed" "$body"
run_test "linear_unclosed_fence_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"
run_not_contains "linear_unclosed_fence_no_lea999" "LEA-999" "$( [ -f "$CHILD_ARGV_LOG" ] && cat "$CHILD_ARGV_LOG" || true )"

echo ""
echo "=== wrapper: Linear ignores indented-code Epic LEA-999 (#1984 Pass 1) ==="
reset_fixture
write_tracker_config linear
export MOCK_LABEL_PARENT_MODE=empty
write_pr 96 "develop-test-1984" "develop" "true" "Graduate" $'Example only:\n    Epic LEA-999\nNo live epic.'
result="$(run_wrapper --graduation-pr 96)"
body="$(last_body "$result")"
run_test "linear_indented_epic_exit_one" "1" "$(last_status "$result")"
run_contains "linear_indented_epic_reason" "epic_discovery_failed" "$body"
run_test "linear_indented_epic_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"
run_not_contains "linear_indented_epic_no_lea999" "LEA-999" "$( [ -f "$CHILD_ARGV_LOG" ] && cat "$CHILD_ARGV_LOG" || true )"

echo ""
echo "=== wrapper: commented header + linear fails closed before child (#1984) ==="
reset_fixture
cat > "$FIXTURE_REPO/.ai-dev-workflow.yaml" <<'EOF'
issue_tracker: # native tracker
  provider: linear
EOF
write_pr 97 "develop-test-1984" "develop" "true" "Graduate" "Epic LEA-326"
result="$(run_wrapper --graduation-pr 97)"
body="$(last_body "$result")"
run_test "commented_linear_wrapper_exit_64" "64" "$(last_status "$result")"
run_contains "commented_linear_wrapper_remediation" "tracker bridge cannot read it" "$body"
run_test "commented_linear_wrapper_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"

echo ""
echo "=== wrapper: github_projects discovery unchanged with explicit config (#1984) ==="
reset_fixture
write_tracker_config github_projects
export MOCK_LABEL_PARENT_MODE=empty
write_pr 93 "develop-test-1984" "develop" "true" "Graduate" "Epic #900"
result="$(run_wrapper --graduation-pr 93)"
body="$(last_body "$result")"
run_test "gh_proj_wrapper_exit_zero" "0" "$(last_status "$result")"
run_contains "gh_proj_wrapper_epic" "EPIC_ISSUE=900" "$body"
run_contains "gh_proj_wrapper_provider" "TRACKER_PROVIDER=github_projects" "$body"
run_contains "gh_proj_child_epic" "--epic 900" "$(cat "$CHILD_ARGV_LOG")"

# ---------------------------------------------------------------------------
# #2016 — GitHub providers ignore example-only closing keywords in epic discovery
# ---------------------------------------------------------------------------

assert_wrapper_github_example_ignored() {
  local provider="$1"
  local body_text="$2"
  local label="$3"
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 110 "develop-test-2016" "develop" "true" "Graduate" "$body_text"
  local result body
  result="$(run_wrapper --graduation-pr 110)"
  body="$(last_body "$result")"
  run_test "${label}_exit_zero" "0" "$(last_status "$result")"
  run_contains "${label}_epic" "EPIC_ISSUE=900" "$body"
  run_contains "${label}_provider" "TRACKER_PROVIDER=${provider}" "$body"
  run_contains "${label}_child_epic" "--epic 900" "$(cat "$CHILD_ARGV_LOG")"
  run_not_contains "${label}_no_epic_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"
}

assert_wrapper_github_example_only_fails() {
  local provider="$1"
  local body_text="$2"
  local label="$3"
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 111 "develop-test-2016" "develop" "true" "Graduate" "$body_text"
  local result body
  result="$(run_wrapper --graduation-pr 111)"
  body="$(last_body "$result")"
  run_test "${label}_exit_one" "1" "$(last_status "$result")"
  run_contains "${label}_reason" "epic_discovery_failed" "$body"
  run_test "${label}_no_child" "missing" "$( [ -f "$CHILD_ARGV_LOG" ] && echo present || echo missing )"
}

for provider in github_projects github_issues; do
  echo ""
  echo "=== wrapper: ${provider} ignores fenced Closes #326 beside Epic #900 (#2016) ==="
  assert_wrapper_github_example_ignored "$provider" \
    $'Epic #900\n```\nCloses #326\n```' \
    "${provider}_wrap_fenced"

  echo ""
  echo "=== wrapper: ${provider} ignores tilde-fenced Closes #326 (#2016) ==="
  assert_wrapper_github_example_ignored "$provider" \
    $'Epic #900\n~~~\nCloses #326\n~~~' \
    "${provider}_wrap_tilde"

  echo ""
  echo "=== wrapper: ${provider} ignores unclosed-fence Closes #326 (#2016) ==="
  assert_wrapper_github_example_ignored "$provider" \
    $'Epic #900\n```text\nCloses #326\n' \
    "${provider}_wrap_unclosed"

  echo ""
  echo "=== wrapper: ${provider} ignores blank+indented Closes #326 (#2016) ==="
  assert_wrapper_github_example_ignored "$provider" \
    $'Epic #900\n\n    Closes #326\n' \
    "${provider}_wrap_indented"

  echo ""
  echo "=== wrapper: ${provider} ignores space+tab mixed-indent Closes #326 (#2016) ==="
  assert_wrapper_github_example_ignored "$provider" \
    "$(printf 'Epic #900\n\n \tCloses #326\n')" \
    "${provider}_wrap_mixed_indent"

  echo ""
  echo "=== wrapper: ${provider} ignores body-start 4-space Closes #326 with title (#2016) ==="
  # Title is set by write_pr; body alone starts with indented code.
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 117 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'    Closes #326\nEpic #900'
  result="$(run_wrapper --graduation-pr 117)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_body_start_spaces_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_body_start_spaces_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_body_start_spaces_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} ignores body-start tab Closes #326 with title (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 118 "develop-test-2016" "develop" "true" "Graduate wave" \
    "$(printf '\tCloses #326\nEpic #900')"
  result="$(run_wrapper --graduation-pr 118)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_body_start_tab_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_body_start_tab_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_body_start_tab_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} ignores body-start space+tab Closes #326 with title (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 119 "develop-test-2016" "develop" "true" "Graduate wave" \
    "$(printf ' \tCloses #326\nEpic #900')"
  result="$(run_wrapper --graduation-pr 119)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_body_start_mixed_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_body_start_mixed_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_body_start_mixed_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} selects title Closes #327; body-start indent #326 ignored (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 120 "develop-test-2016" "develop" "true" "Closes #327" \
    $'    Closes #326'
  result="$(run_wrapper --graduation-pr 120)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_title_327_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_title_327_epic" "EPIC_ISSUE=327" "$body"
  run_contains "${provider}_wrap_title_327_child" "--epic 327" "$(cat "$CHILD_ARGV_LOG")"
  run_not_contains "${provider}_wrap_title_327_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} ignores thematic-break then indented Closes #326 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 121 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'- - -\n\n    Closes #326\nEpic #900'
  result="$(run_wrapper --graduation-pr 121)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_thematic_spaced_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_thematic_spaced_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_thematic_spaced_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 122 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'---\n\n    Closes #326\nEpic #900'
  result="$(run_wrapper --graduation-pr 122)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_thematic_hr_dashes_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_thematic_hr_dashes_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_thematic_hr_dashes_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 123 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'* * *\n\n    Closes #326\nEpic #900'
  result="$(run_wrapper --graduation-pr 123)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_thematic_stars_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_thematic_stars_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_thematic_stars_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 124 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'***\n\n    Closes #326\nEpic #900'
  result="$(run_wrapper --graduation-pr 124)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_thematic_hr_stars_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_thematic_hr_stars_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_thematic_hr_stars_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 125 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'___\n\n    Closes #326\nEpic #900'
  result="$(run_wrapper --graduation-pr 125)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_thematic_underscores_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_thematic_underscores_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_thematic_underscores_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} keeps real list then indented Closes #123 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 126 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'- item\n    Closes #123'
  result="$(run_wrapper --graduation-pr 126)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_list_then_indent_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_list_then_indent_epic" "EPIC_ISSUE=123" "$body"
  run_contains "${provider}_wrap_list_then_indent_child" "--epic 123" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} keeps list two-space continuation then Closes #123 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 127 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'- Delivered work:\n  Additional details.\n\n    Closes #123'
  result="$(run_wrapper --graduation-pr 127)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_list_two_space_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_list_two_space_epic" "EPIC_ISSUE=123" "$body"
  run_contains "${provider}_wrap_list_two_space_child" "--epic 123" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} keeps list multi-continuation then Closes #124 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 128 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'- a\n  b\n\n  c\n\n    Closes #124'
  result="$(run_wrapper --graduation-pr 128)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_list_multi_cont_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_list_multi_cont_epic" "EPIC_ISSUE=124" "$body"

  echo ""
  echo "=== wrapper: ${provider} strips code after list ends with indent-0 paragraph (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 129 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'- item\n\nParagraph outside list.\n\n    Closes #326\nEpic #900'
  result="$(run_wrapper --graduation-pr 129)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_list_then_para_code_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_list_then_para_code_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_list_then_para_code_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} strips list-item six-space code Closes #326 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 130 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'- Example:\n\n      Closes #326\nEpic #900'
  result="$(run_wrapper --graduation-pr 130)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_list_item_code_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_list_item_code_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_list_item_code_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} strips ordered-list seven-space code Closes #327 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 131 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'1. Item\n\n       Closes #327\nEpic #900'
  result="$(run_wrapper --graduation-pr 131)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_ordered_list_code_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_ordered_list_code_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_ordered_list_code_no_327" "--epic 327" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} strips ATX-heading then indented Closes #326 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 132 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'## Example\n    Closes #326\nEpic #900'
  result="$(run_wrapper --graduation-pr 132)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_atx_indent_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_atx_indent_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_atx_indent_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} strips setext then indented Closes #326 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 133 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'Paragraph\n---\n    Closes #326\nEpic #900'
  result="$(run_wrapper --graduation-pr 133)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_setext_indent_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_setext_indent_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_setext_indent_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} keeps ATX-heading then blank prose Closes #328 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 134 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'## Example\n\nCloses #328'
  result="$(run_wrapper --graduation-pr 134)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_atx_blank_prose_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_atx_blank_prose_epic" "EPIC_ISSUE=328" "$body"

  echo ""
  echo "=== wrapper: ${provider} strips list-item tilde fence Closes #326 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 135 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'- Example:\n\n    ~~~text\n    Closes #326\n    ~~~\nEpic #900'
  result="$(run_wrapper --graduation-pr 135)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_list_tilde_fence_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_list_tilde_fence_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_list_tilde_fence_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} strips list-item unclosed tilde fence Closes #326 (#2016) ==="
  # Epic must precede the unclosed fence (fence extends to EOF).
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 136 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'Epic #900\n- Example:\n\n    ~~~text\n    Closes #326'
  result="$(run_wrapper --graduation-pr 136)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_list_tilde_unclosed_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_list_tilde_unclosed_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_list_tilde_unclosed_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} strips list-item backtick fence Closes #326 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 137 "develop-test-2016" "develop" "true" "Graduate wave" \
    "$(printf -- '- Example:\n\n    ```text\n    Closes #326\n    ```\nEpic #900')"
  result="$(run_wrapper --graduation-pr 137)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_list_tick_fence_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_list_tick_fence_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_list_tick_fence_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} strips list-item unclosed backtick fence Closes #326 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 138 "develop-test-2016" "develop" "true" "Graduate wave" \
    "$(printf -- 'Epic #900\n- Example:\n\n    ```text\n    Closes #326')"
  result="$(run_wrapper --graduation-pr 138)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_list_tick_unclosed_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_list_tick_unclosed_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_list_tick_unclosed_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} keeps prose after list-item fence Closes #123 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 139 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'- Example:\n\n    ~~~text\n    Closes #326\n    ~~~\n    Closes #123'
  result="$(run_wrapper --graduation-pr 139)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_list_fence_then_prose_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_list_fence_then_prose_epic" "EPIC_ISSUE=123" "$body"

  echo ""
  echo "=== wrapper: ${provider} strips marker-line tilde fence Closes #326 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 140 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'- ~~~text\n  Closes #326\n  ~~~\nEpic #900'
  result="$(run_wrapper --graduation-pr 140)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_marker_tilde_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_marker_tilde_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_marker_tilde_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} strips marker-line unclosed tilde fence Closes #326 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 141 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'Epic #900\n- ~~~text\n  Closes #326'
  result="$(run_wrapper --graduation-pr 141)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_marker_tilde_unclosed_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_marker_tilde_unclosed_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_marker_tilde_unclosed_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} strips marker-line backtick fence Closes #326 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 142 "develop-test-2016" "develop" "true" "Graduate wave" \
    "$(printf -- '- ```text\n  Closes #326\n  ```\nEpic #900')"
  result="$(run_wrapper --graduation-pr 142)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_marker_tick_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_marker_tick_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_marker_tick_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} strips marker-line unclosed backtick fence Closes #326 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 143 "develop-test-2016" "develop" "true" "Graduate wave" \
    "$(printf -- 'Epic #900\n- ```text\n  Closes #326')"
  result="$(run_wrapper --graduation-pr 143)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_marker_tick_unclosed_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_marker_tick_unclosed_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_marker_tick_unclosed_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} strips ordered marker-line tilde fence Closes #326 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 144 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'1. ~~~\n   Closes #326\n   ~~~\nEpic #900'
  result="$(run_wrapper --graduation-pr 144)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_ordered_marker_tilde_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_ordered_marker_tilde_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_ordered_marker_tilde_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} keeps prose after marker-line fence Closes #123 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 145 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'- ~~~text\n  Closes #326\n  ~~~\n  Closes #123'
  result="$(run_wrapper --graduation-pr 145)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_marker_fence_then_prose_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_marker_fence_then_prose_epic" "EPIC_ISSUE=123" "$body"

  echo ""
  echo "=== wrapper: ${provider} does not leak list state from top-level tilde fence (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 146 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'~~~text\n- example\n~~~\n\n    Closes #326\nEpic #900'
  result="$(run_wrapper --graduation-pr 146)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_fence_list_no_leak_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_fence_list_no_leak_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_fence_list_no_leak_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} does not leak list state from top-level backtick fence (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 147 "develop-test-2016" "develop" "true" "Graduate wave" \
    "$(printf -- '```text\n- example\n```\n\n    Closes #327\nEpic #900')"
  result="$(run_wrapper --graduation-pr 147)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_tick_fence_list_no_leak_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_tick_fence_list_no_leak_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_tick_fence_list_no_leak_no_327" "--epic 327" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} ignores heading inside fence then strips indent (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 148 "develop-test-2016" "develop" "true" "Graduate wave" \
    $'~~~\n## Example\n~~~\n\n    Closes #326\nEpic #900'
  result="$(run_wrapper --graduation-pr 148)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_heading_inside_fence_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_heading_inside_fence_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_heading_inside_fence_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} strips tab-after-marker tilde fence Closes #326 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 149 "develop-test-2016" "develop" "true" "Graduate wave" \
    "$(printf -- '-\t~~~text\n\tCloses #326\n\t~~~\nEpic #900')"
  result="$(run_wrapper --graduation-pr 149)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_tab_marker_tilde_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_tab_marker_tilde_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_tab_marker_tilde_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} strips tab-after-marker unclosed tilde fence Closes #326 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 150 "develop-test-2016" "develop" "true" "Graduate wave" \
    "$(printf -- 'Epic #900\n-\t~~~text\n\tCloses #326')"
  result="$(run_wrapper --graduation-pr 150)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_tab_marker_tilde_unclosed_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_tab_marker_tilde_unclosed_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_tab_marker_tilde_unclosed_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} strips ordered tab-after-marker tick fence Closes #326 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 151 "develop-test-2016" "develop" "true" "Graduate wave" \
    "$(printf -- '1.\t```text\n\tCloses #326\n\t```\nEpic #900')"
  result="$(run_wrapper --graduation-pr 151)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_tab_ordered_tick_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_tab_ordered_tick_epic" "EPIC_ISSUE=900" "$body"
  run_not_contains "${provider}_wrap_tab_ordered_tick_no_326" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} keeps tab-indented nested list prose Closes #331 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 152 "develop-test-2016" "develop" "true" "Graduate wave" \
    "$(printf -- '\t- item\n\t\tCloses #331')"
  result="$(run_wrapper --graduation-pr 152)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_tab_nested_prose_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_tab_nested_prose_epic" "EPIC_ISSUE=331" "$body"

  echo ""
  echo "=== wrapper: ${provider} keeps nested-list Closes #123 with Epic #900 (#2016) ==="
  # Nested list keyword is live but Epic #900 is the sole epic/parent ref style
  # candidate preferred when both exist — assert 123 is not chosen as epic and
  # discovery still succeeds via Epic #900 (keyword may add a second candidate).
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 113 "develop-test-2016" "develop" "true" "Graduate" \
    $'Epic #900\n- Delivered work:\n    - Closes #123'
  result="$(run_wrapper --graduation-pr 113)"
  body="$(last_body "$result")"
  # Epic #900 + Closes #123 → two candidates → ambiguous without parents
  run_test "${provider}_wrap_nested_list_exit_one" "1" "$(last_status "$result")"
  run_contains "${provider}_wrap_nested_list_ambiguous" "ambiguous_epic_candidates" "$body"

  echo ""
  echo "=== wrapper: ${provider} selects nested-list Closes #123 as sole epic (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 114 "develop-test-2016" "develop" "true" "Graduate" \
    $'- Delivered work:\n    - Closes #123'
  result="$(run_wrapper --graduation-pr 114)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_nested_sole_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_nested_sole_epic" "EPIC_ISSUE=123" "$body"
  run_contains "${provider}_wrap_nested_sole_child" "--epic 123" "$(cat "$CHILD_ARGV_LOG")"

  echo ""
  echo "=== wrapper: ${provider} selects list-continuation Closes #124 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 115 "develop-test-2016" "develop" "true" "Graduate" \
    $'- Delivered work:\n    Closes #124'
  result="$(run_wrapper --graduation-pr 115)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_list_cont_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_list_cont_epic" "EPIC_ISSUE=124" "$body"

  echo ""
  echo "=== wrapper: ${provider} selects paragraph-continuation Closes #125 (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 116 "develop-test-2016" "develop" "true" "Graduate" \
    $'Some prose about the change.\n    Closes #125'
  result="$(run_wrapper --graduation-pr 116)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_para_cont_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_para_cont_epic" "EPIC_ISSUE=125" "$body"

  echo ""
  echo "=== wrapper: ${provider} ignores Closes other/repo#326 (#2016) ==="
  assert_wrapper_github_example_only_fails "$provider" \
    'Closes other/repo#326' \
    "${provider}_wrap_foreign"

  echo ""
  echo "=== wrapper: ${provider} still selects plain-prose Closes #326 as epic (#2016) ==="
  reset_fixture
  write_tracker_config "$provider"
  export MOCK_LABEL_PARENT_MODE=empty
  write_pr 112 "develop-test-2016" "develop" "true" "Graduate" "Closes #326"
  result="$(run_wrapper --graduation-pr 112)"
  body="$(last_body "$result")"
  run_test "${provider}_wrap_plain_exit_zero" "0" "$(last_status "$result")"
  run_contains "${provider}_wrap_plain_epic" "EPIC_ISSUE=326" "$body"
  run_contains "${provider}_wrap_plain_child" "--epic 326" "$(cat "$CHILD_ARGV_LOG")"
done

echo ""
echo "Graduation closeout-from-merged-pr tests: $PASS_COUNT passed, $FAIL_COUNT failed."
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi

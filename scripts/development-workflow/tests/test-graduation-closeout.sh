#!/usr/bin/env bash
# test-graduation-closeout.sh - graduation closeout helper tests.
#
# Usage: bash scripts/development-workflow/tests/test-graduation-closeout.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
FIXTURE_REPO="$TMP_ROOT/repo"
MOCK_STATE_DIR="$TMP_ROOT/state"
MOCK_STATUS_DIR="$TMP_ROOT/status"
MOCK_CLOSE_LOG="$TMP_ROOT/close.log"
MOCK_LABEL_LOG="$TMP_ROOT/label.log"
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

mkdir -p "$MOCK_BIN" "$FIXTURE_REPO/scripts/development-workflow" "$MOCK_STATE_DIR" "$MOCK_STATUS_DIR"
cp "$REPO_ROOT/scripts/development-workflow/graduation-closeout.sh" "$FIXTURE_REPO/scripts/development-workflow/graduation-closeout.sh"
chmod +x "$FIXTURE_REPO/scripts/development-workflow/graduation-closeout.sh"

cat > "$FIXTURE_REPO/scripts/development-workflow/workflow-lib.sh" <<'STUB_LIB'
#!/usr/bin/env bash

cd_workflow_repo_root() {
  cd "$WORKFLOW_FIXTURE_REPO"
}

require_gh() {
  gh auth status >/dev/null
}

repo_slug() {
  printf 'lhpaul/ai-dev-framework-template\n'
}

is_terminal_tracker_status() {
  case "$1" in
    Done|Merged|Released|Cancelled) return 0 ;;
    *) return 1 ;;
  esac
}

get_tracker_status_for_issue() {
  local issue="$1"
  if [ -f "$MOCK_STATUS_DIR/$issue" ]; then
    cat "$MOCK_STATUS_DIR/$issue"
  fi
}

update_tracker_status_best_effort() {
  local issue="$1"
  local status="$2"
  if [ "${MOCK_STATUS_FAIL_ISSUE:-}" = "$issue" ]; then
    printf 'Warning: mocked status update failure for #%s\n' "$issue" >&2
    return 0
  fi
  printf '%s\n' "$status" > "$MOCK_STATUS_DIR/$issue"
}
STUB_LIB

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
  "auth status")
    exit 0
    ;;
  api\ graphql*)
    case "${MOCK_NATIVE_MODE:-children}" in
      fail)
        printf 'mock native failure\n' >&2
        exit 42
        ;;
      empty)
        cat <<'JSON'
{"data":{"repository":{"issue":{"subIssues":{"nodes":[],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
        ;;
      *)
        cat <<'JSON'
{"data":{"repository":{"issue":{"subIssues":{"nodes":[{"number":101,"title":"Open child","state":"OPEN","labels":{"nodes":[]}},{"number":102,"title":"Closed nonterminal","state":"CLOSED","labels":{"nodes":[]}},{"number":103,"title":"Closed terminal","state":"CLOSED","labels":{"nodes":[]}},{"number":104,"title":"Optional child","state":"OPEN","labels":{"nodes":[{"name":"optional"}]}}],"pageInfo":{"hasNextPage":false,"endCursor":null}}}}}}
JSON
        ;;
    esac
    ;;
  issue\ list\ --label\ integration-branch:test\ --state\ all\ --limit\ 1000\ --json\ number,title,state,labels\ --jq\ .[]\ \|\ .number)
    if [ "${MOCK_LABEL_MODE:-ok}" = "fail" ]; then
      printf 'mock label discovery failure\n' >&2
      exit 47
    fi
    if [ -n "${MOCK_LABEL_ISSUES:-}" ]; then
      printf '%s\n' "$MOCK_LABEL_ISSUES"
    fi
    ;;
  "pr view 77 --json number,state,mergedAt,baseRefName,headRefName")
    case "${MOCK_GRADUATION_PR_MODE:-merged}" in
      open)
        cat <<'JSON'
{"number":77,"state":"OPEN","mergedAt":null,"baseRefName":"develop","headRefName":"develop-test"}
JSON
        ;;
      wrong_head)
        cat <<'JSON'
{"number":77,"state":"MERGED","mergedAt":"2026-07-15T12:00:00Z","baseRefName":"develop","headRefName":"feature/not-graduation"}
JSON
        ;;
      wrong_base)
        cat <<'JSON'
{"number":77,"state":"MERGED","mergedAt":"2026-07-15T12:00:00Z","baseRefName":"main","headRefName":"develop-test"}
JSON
        ;;
      nested_base)
        cat <<'JSON'
{"number":77,"state":"MERGED","mergedAt":"2026-07-15T12:00:00Z","baseRefName":"develop-sales-module","headRefName":"develop-test"}
JSON
        ;;
      *)
        cat <<'JSON'
{"number":77,"state":"MERGED","mergedAt":"2026-07-15T12:00:00Z","baseRefName":"develop","headRefName":"develop-test"}
JSON
        ;;
    esac
    ;;
  "pr list --state merged --base develop-test --limit 1000 --json number,title,body")
    case "${MOCK_PR_MODE:-single_ref}" in
      fail)
        printf 'mock pr list failure\n' >&2
        exit 46
        ;;
      none)
        printf '[]\n'
        ;;
      parser)
        cat <<'JSON'
[{"number":21,"title":"Closes #301 and fixes #302","body":"(Resolves issue #303.)\n- closed #304\nDisclose #398\nhotfix #399\nnot closing #397\nowner/repo#396\nCloses owner/repo#395\nfixes #302"}]
JSON
        ;;
      *)
        cat <<'JSON'
[{"number":11,"title":"Deliver extra item","body":"Closes #105"}]
JSON
        ;;
    esac
    ;;
  issue\ view\ *\ --json\ labels\ --jq\ *)
    issue="$3"
    file="$MOCK_STATE_DIR/$issue.json"
    if [ ! -f "$file" ]; then
      printf 'missing fixture for issue #%s\n' "$issue" >&2
      exit 44
    fi
    python3 - "$file" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
print(",".join(label.get("name") or "" for label in (data.get("labels") or [])))
PY
    ;;
  issue\ view\ *\ --json\ number,title,state,labels)
    issue="$3"
    file="$MOCK_STATE_DIR/$issue.json"
    if [ ! -f "$file" ]; then
      printf 'missing fixture for issue #%s\n' "$issue" >&2
      exit 44
    fi
    cat "$file"
    ;;
  issue\ edit\ *\ --add-label\ defer-epic-close)
    issue="$3"
    file="$MOCK_STATE_DIR/$issue.json"
    if [ ! -f "$file" ]; then
      printf 'missing fixture for issue #%s\n' "$issue" >&2
      exit 44
    fi
    if [ "${MOCK_LABEL_ADD_FAIL:-0}" = "1" ]; then
      printf 'mock label add failure\n' >&2
      exit 48
    fi
    python3 - "$file" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))
labels = data.setdefault("labels", [])
if not any((label.get("name") or "") == "defer-epic-close" for label in labels):
    labels.append({"name": "defer-epic-close"})
json.dump(data, open(path, "w"))
PY
    printf 'add\t%s\tdefer-epic-close\n' "$issue" >> "$MOCK_LABEL_LOG"
    ;;
  label\ create\ defer-epic-close*)
    if [ "${MOCK_LABEL_CREATE_FAIL:-0}" = "1" ]; then
      printf 'mock label create failure\n' >&2
      exit 49
    fi
    printf 'create\tdefer-epic-close\n' >> "$MOCK_LABEL_LOG"
    ;;
  issue\ close\ *\ --comment\ *)
    issue="$3"
    if [ "${MOCK_CLOSE_FAIL_ISSUE:-}" = "$issue" ]; then
      printf 'mock close failure for #%s\n' "$issue" >&2
      exit 45
    fi
    python3 - "$MOCK_STATE_DIR/$issue.json" <<'PY'
import json
import sys
path = sys.argv[1]
data = json.load(open(path))
data["state"] = "CLOSED"
json.dump(data, open(path, "w"))
PY
    printf '%s\t%s\n' "$issue" "$*" >> "$MOCK_CLOSE_LOG"
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
export MOCK_STATE_DIR MOCK_STATUS_DIR MOCK_CLOSE_LOG MOCK_LABEL_LOG

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

write_issue() {
  local number="$1"
  local title="$2"
  local state="$3"
  local labels_csv="${4:-}"
  python3 - "$MOCK_STATE_DIR/$number.json" "$number" "$title" "$state" "$labels_csv" <<'PY'
import json
import sys
path, number, title, state, labels_csv = sys.argv[1:6]
labels = [{"name": label} for label in labels_csv.split(",") if label]
json.dump({"number": int(number), "title": title, "state": state, "labels": labels}, open(path, "w"))
PY
}

set_status() {
  printf '%s\n' "$2" > "$MOCK_STATUS_DIR/$1"
}

reset_fixture() {
  rm -f "$MOCK_STATE_DIR"/*.json "$MOCK_STATUS_DIR"/* "$MOCK_CLOSE_LOG" "$MOCK_LABEL_LOG"
  : > "$MOCK_CLOSE_LOG"
  : > "$MOCK_LABEL_LOG"
  unset MOCK_NATIVE_MODE MOCK_LABEL_MODE MOCK_LABEL_ISSUES MOCK_PR_MODE MOCK_GRADUATION_PR_MODE MOCK_CLOSE_FAIL_ISSUE MOCK_STATUS_FAIL_ISSUE MOCK_LABEL_ADD_FAIL MOCK_LABEL_CREATE_FAIL GITHUB_PROJECT_STATUS_GRADUATED GITHUB_PROJECT_STATUS_MERGED GRADUATION_BASE
}

run_closeout() {
  local output status
  set +e
  output="$(cd "$FIXTURE_REPO" && ./scripts/development-workflow/graduation-closeout.sh --slug test --graduation-pr 77 --epic 900 "$@" 2>&1)"
  status=$?
  set -e
  printf '%s\n%s\n' "$status" "$output"
}

last_output_body() {
  tail -n +2 <<< "$1"
}

last_output_status() {
  head -n 1 <<< "$1"
}

echo ""
echo "=== graduation closeout: discovery failures fail closed ==="
reset_fixture
export MOCK_NATIVE_MODE=fail
export MOCK_PR_MODE=none
write_issue 900 "Parent epic" OPEN
set_status 900 "In Development"
empty_discovery_result="$(run_closeout)"
empty_discovery_body="$(last_output_body "$empty_discovery_result")"
run_test "empty_discovery_exit_one" "1" "$(last_output_status "$empty_discovery_result")"
run_contains "empty_discovery_failed_result" "GRADUATION_CLOSEOUT_RESULT=failed" "$empty_discovery_body"
run_contains "empty_discovery_reason" "no_delivered_subitems_discovered" "$empty_discovery_body"
run_contains "empty_discovery_epic_held" "EPIC_RESULT=held" "$empty_discovery_body"
run_test "empty_discovery_no_epic_close" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/900.json"))["state"])')"

reset_fixture
export MOCK_PR_MODE=fail
write_issue 101 "Open child" OPEN
write_issue 102 "Closed nonterminal" CLOSED
write_issue 103 "Closed terminal" CLOSED
write_issue 104 "Optional child" OPEN optional
write_issue 900 "Parent epic" OPEN
set_status 101 "In Development"
set_status 102 "Development in Review"
set_status 103 "Merged"
set_status 104 "In Development"
set_status 900 "In Development"
pr_discovery_result="$(run_closeout)"
pr_discovery_body="$(last_output_body "$pr_discovery_result")"
run_test "pr_discovery_exit_one" "1" "$(last_output_status "$pr_discovery_result")"
run_contains "pr_discovery_reason" "merged_pr_discovery_failed" "$pr_discovery_body"
run_contains "pr_discovery_epic_held" "EPIC_RESULT=held" "$pr_discovery_body"
run_test "pr_discovery_child_still_processed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/101.json"))["state"])')"
run_test "pr_discovery_no_epic_close" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/900.json"))["state"])')"

reset_fixture
export MOCK_LABEL_MODE=fail
export MOCK_PR_MODE=none
write_issue 101 "Open child" OPEN
write_issue 102 "Closed nonterminal" CLOSED
write_issue 103 "Closed terminal" CLOSED
write_issue 104 "Optional child" OPEN optional
write_issue 900 "Parent epic" OPEN
set_status 101 "In Development"
set_status 102 "Development in Review"
set_status 103 "Merged"
set_status 104 "In Development"
set_status 900 "In Development"
label_discovery_result="$(run_closeout)"
label_discovery_body="$(last_output_body "$label_discovery_result")"
run_test "label_discovery_exit_one" "1" "$(last_output_status "$label_discovery_result")"
run_contains "label_discovery_reason" "label_fallback_failed" "$label_discovery_body"
run_contains "label_discovery_epic_held" "EPIC_RESULT=held" "$label_discovery_body"
run_test "label_discovery_child_still_processed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/101.json"))["state"])')"
run_test "label_discovery_no_epic_close" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/900.json"))["state"])')"

echo ""
echo "=== graduation closeout: graduation PR validation ==="
reset_fixture
export MOCK_GRADUATION_PR_MODE=open
export MOCK_NATIVE_MODE=empty
export MOCK_LABEL_ISSUES="701"
export MOCK_PR_MODE=none
write_issue 701 "Should not close" OPEN
write_issue 900 "Parent epic" OPEN
set_status 701 "In Development"
set_status 900 "In Development"
validation_result="$(run_closeout)"
validation_body="$(last_output_body "$validation_result")"
run_test "validation_exit_one" "1" "$(last_output_status "$validation_result")"
run_contains "validation_reports_unmerged_pr" "has not merged yet" "$validation_body"
run_test "validation_does_not_close_child" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/701.json"))["state"])')"
run_test "validation_no_close_calls" "" "$(cat "$MOCK_CLOSE_LOG")"

echo ""
echo "=== graduation closeout: --base graduation base override (issue #1513) ==="

# Regression: default base (no --base flag) must still require the graduation
# PR to target 'develop', and must still be rejected with a clear error when
# it does not — this must not regress when --base support is added.
reset_fixture
export MOCK_GRADUATION_PR_MODE=wrong_base
export MOCK_NATIVE_MODE=empty
export MOCK_LABEL_ISSUES="801"
export MOCK_PR_MODE=none
write_issue 801 "Default base child" OPEN
write_issue 900 "Parent epic" OPEN
set_status 801 "In Development"
set_status 900 "In Development"
default_base_reject_result="$(run_closeout)"
default_base_reject_body="$(last_output_body "$default_base_reject_result")"
run_test "default_base_reject_exit_one" "1" "$(last_output_status "$default_base_reject_result")"
run_contains "default_base_reject_error" "expected 'develop'" "$default_base_reject_body"
run_test "default_base_reject_no_close" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/801.json"))["state"])')"

# Non-default base: a nested graduation PR (develop-test -> develop-sales-module)
# whose --base matches the PR's actual base passes validation and completes
# closeout normally.
reset_fixture
export MOCK_GRADUATION_PR_MODE=nested_base
export MOCK_NATIVE_MODE=empty
export MOCK_LABEL_ISSUES="802"
export MOCK_PR_MODE=none
write_issue 802 "Nested base child" OPEN
write_issue 900 "Parent epic" OPEN
set_status 802 "In Development"
set_status 900 "In Development"
nested_base_result="$(run_closeout --base develop-sales-module)"
nested_base_body="$(last_output_body "$nested_base_result")"
run_test "nested_base_exit_zero" "0" "$(last_output_status "$nested_base_result")"
run_contains "nested_base_result_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$nested_base_body"
run_contains "nested_base_reported" "GRADUATION_BASE=develop-sales-module" "$nested_base_body"
run_test "nested_base_child_closed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/802.json"))["state"])')"
run_contains "nested_base_comment_target" "to \`develop-sales-module\`" "$(cat "$MOCK_CLOSE_LOG")"

# Non-default base with a mismatched actual PR base is still rejected with a
# clear error (the "real check" required by issue #1513 AC-2) — the expected
# branch named in the error is the custom --base, not a hardcoded 'develop'.
reset_fixture
export MOCK_GRADUATION_PR_MODE=merged
export MOCK_NATIVE_MODE=empty
export MOCK_LABEL_ISSUES="803"
export MOCK_PR_MODE=none
write_issue 803 "Mismatched base child" OPEN
write_issue 900 "Parent epic" OPEN
set_status 803 "In Development"
set_status 900 "In Development"
nested_base_mismatch_result="$(run_closeout --base develop-sales-module)"
nested_base_mismatch_body="$(last_output_body "$nested_base_mismatch_result")"
run_test "nested_base_mismatch_exit_one" "1" "$(last_output_status "$nested_base_mismatch_result")"
run_contains "nested_base_mismatch_error" "expected 'develop-sales-module'" "$nested_base_mismatch_body"
run_test "nested_base_mismatch_no_close" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/803.json"))["state"])')"

# An arbitrary feature/fix branch as --base is rejected up front (usage-level
# validation) before any gh call — the "real check" is not bypassable by
# simply passing a matching but non-integration-branch value.
reset_fixture
invalid_base_result="$(run_closeout --base feature/not-an-integration-branch)"
invalid_base_body="$(last_output_body "$invalid_base_result")"
run_test "invalid_base_exit_64" "64" "$(last_output_status "$invalid_base_result")"
run_contains "invalid_base_error" "must be 'develop' or a 'develop-*' integration branch" "$invalid_base_body"

echo ""
echo "=== graduation closeout: native sub-issues and PR refs ==="
reset_fixture
write_issue 101 "Open child" OPEN
write_issue 102 "Closed nonterminal" CLOSED
write_issue 103 "Closed terminal" CLOSED
write_issue 104 "Optional child" OPEN optional
write_issue 105 "PR referenced child" OPEN
write_issue 900 "Parent epic" OPEN
set_status 101 "In Development"
set_status 102 "Development in Review"
set_status 103 "Merged"
set_status 104 "In Development"
set_status 105 "Plan Ready"
set_status 900 "In Development"
native_result="$(run_closeout)"
native_body="$(last_output_body "$native_result")"
run_test "native_exit_zero" "0" "$(last_output_status "$native_result")"
run_contains "native_result_pass" "GRADUATION_CLOSEOUT_RESULT=pass" "$native_body"
run_contains "native_closed_count" "CLOSED_COUNT=3" "$native_body"
run_contains "native_already_count" "ALREADY_TERMINAL_COUNT=1" "$native_body"
run_contains "native_skipped_count" "SKIPPED_OPTIONAL_COUNT=1" "$native_body"
run_contains "native_failed_count" "FAILED_COUNT=0" "$native_body"
run_contains "native_epic_closed" "EPIC_RESULT=closed" "$native_body"
run_test "open_child_closed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/101.json"))["state"])')"
run_test "closed_nonterminal_status_updated" "Merged" "$(cat "$MOCK_STATUS_DIR/102")"
run_test "optional_stays_open" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/104.json"))["state"])')"
run_contains "pr_ref_source_reported" "#105" "$native_body"
run_contains "close_log_has_epic" "900" "$(cat "$MOCK_CLOSE_LOG")"

echo ""
echo "=== graduation closeout: label fallback ==="
reset_fixture
export MOCK_NATIVE_MODE=empty
export MOCK_LABEL_ISSUES=$'201\n202'
export MOCK_PR_MODE=none
write_issue 201 "Fallback child A" OPEN
write_issue 202 "Fallback child B" OPEN
write_issue 900 "Parent epic" OPEN
set_status 201 "In Development"
set_status 202 "In Development"
set_status 900 "In Development"
fallback_result="$(run_closeout)"
fallback_body="$(last_output_body "$fallback_result")"
run_test "fallback_exit_zero" "0" "$(last_output_status "$fallback_result")"
run_contains "fallback_closed_count" "CLOSED_COUNT=2" "$fallback_body"
run_contains "fallback_label_source" "label:integration-branch:test" "$fallback_body"

echo ""
echo "=== graduation closeout: closing keyword parser ==="
reset_fixture
export MOCK_NATIVE_MODE=empty
export MOCK_PR_MODE=parser
for issue in 301 302 303 304 395 396 397 398 399; do
  write_issue "$issue" "Parser $issue" OPEN
  set_status "$issue" "In Development"
done
write_issue 900 "Parent epic" OPEN
set_status 900 "In Development"
parser_result="$(run_closeout)"
parser_body="$(last_output_body "$parser_result")"
run_test "parser_exit_zero" "0" "$(last_output_status "$parser_result")"
run_contains "parser_variants_count" "CLOSED_COUNT=4" "$parser_body"
run_contains "parser_parentheses_match" "#303" "$parser_body"
run_contains "parser_markdown_match" "#304" "$parser_body"
run_not_contains "parser_disclose_ignored" "#398" "$parser_body"
run_not_contains "parser_hotfix_ignored" "#399" "$parser_body"
run_not_contains "parser_cross_repo_ignored" "#395" "$parser_body"
run_not_contains "parser_related_repo_ignored" "#396" "$parser_body"
run_not_contains "parser_non_closing_ignored" "#397" "$parser_body"

echo ""
echo "=== graduation closeout: partial failure and epic hold ==="
reset_fixture
export MOCK_NATIVE_MODE=empty
export MOCK_LABEL_ISSUES=$'401\n402'
export MOCK_PR_MODE=none
export MOCK_CLOSE_FAIL_ISSUE=401
write_issue 401 "Fails close" OPEN
write_issue 402 "Still closes" OPEN
write_issue 900 "Parent epic" OPEN
set_status 401 "In Development"
set_status 402 "In Development"
set_status 900 "In Development"
failure_result="$(run_closeout)"
failure_body="$(last_output_body "$failure_result")"
run_test "failure_exit_one" "1" "$(last_output_status "$failure_result")"
run_contains "failure_count" "FAILED_COUNT=1" "$failure_body"
run_contains "failure_other_item_closed" "#402" "$failure_body"
run_contains "failure_epic_held" "EPIC_RESULT=held" "$failure_body"
run_test "failed_issue_stays_open" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/401.json"))["state"])')"
run_test "other_issue_closed" "CLOSED" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/402.json"))["state"])')"

echo ""
echo "=== graduation closeout: defer epic and configured terminal status ==="
reset_fixture
export MOCK_NATIVE_MODE=empty
export MOCK_LABEL_ISSUES="501"
export MOCK_PR_MODE=none
export GITHUB_PROJECT_STATUS_GRADUATED=Done
write_issue 501 "Done child" OPEN
write_issue 900 "Parent epic" OPEN
set_status 501 "In Development"
set_status 900 "In Development"
defer_result="$(run_closeout --defer-epic-close)"
defer_body="$(last_output_body "$defer_result")"
run_test "defer_exit_zero" "0" "$(last_output_status "$defer_result")"
run_contains "defer_epic" "EPIC_RESULT=deferred" "$defer_body"
run_contains "defer_label_added" "DEFER_LABEL=added" "$defer_body"
run_contains "configured_terminal_status" "TERMINAL_STATUS=Done" "$defer_body"
run_test "done_status_written" "Done" "$(cat "$MOCK_STATUS_DIR/501")"
run_test "deferred_epic_stays_open" "OPEN" "$(python3 -c 'import json; print(json.load(open("'"$MOCK_STATE_DIR"'/900.json"))["state"])')"
run_contains "defer_label_on_epic" "defer-epic-close" "$(python3 -c 'import json; print(",".join(l["name"] for l in json.load(open("'"$MOCK_STATE_DIR"'/900.json"))["labels"]))')"

# Re-run with label already present — durable signal must stay idempotent.
defer_rerun_result="$(run_closeout --defer-epic-close)"
defer_rerun_body="$(last_output_body "$defer_rerun_result")"
run_test "defer_rerun_exit_zero" "0" "$(last_output_status "$defer_rerun_result")"
run_contains "defer_label_already" "DEFER_LABEL=already_present" "$defer_rerun_body"

echo ""
echo "=== graduation closeout: already-terminal rerun behavior ==="
reset_fixture
export MOCK_NATIVE_MODE=empty
export MOCK_LABEL_ISSUES="601"
export MOCK_PR_MODE=none
write_issue 601 "Already done" CLOSED
write_issue 900 "Parent epic" CLOSED
set_status 601 "Merged"
set_status 900 "Merged"
rerun_result="$(run_closeout)"
rerun_body="$(last_output_body "$rerun_result")"
run_test "rerun_exit_zero" "0" "$(last_output_status "$rerun_result")"
run_contains "rerun_already_count" "ALREADY_TERMINAL_COUNT=1" "$rerun_body"
run_contains "rerun_epic_already" "EPIC_RESULT=already_terminal" "$rerun_body"
run_test "rerun_no_close_calls" "" "$(cat "$MOCK_CLOSE_LOG")"

echo ""
echo "Graduation closeout tests: $PASS_COUNT passed, $FAIL_COUNT failed."
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi

#!/usr/bin/env bash
# test-graduation-closeout-from-merged-pr.sh - merge-time graduation closeout wrapper tests.
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
STUB_LIB

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
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
          number=*) child="${val#number=}" ;;
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
export MOCK_STATE_DIR CHILD_ARGV_LOG

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

reset_fixture() {
  rm -f "$MOCK_STATE_DIR"/* "$CHILD_ARGV_LOG"
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
echo "Graduation closeout-from-merged-pr tests: $PASS_COUNT passed, $FAIL_COUNT failed."
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi

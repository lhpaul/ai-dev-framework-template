#!/usr/bin/env bash
# test-post-merge-qa-scope.sh — unit tests for post-merge-qa-scope.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/scripts/development-workflow/post-merge-qa-scope.sh"

PASS_COUNT=0
FAIL_COUNT=0
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_fails_contains() {
  local name="$1" needle="$2"
  shift 2
  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  if [ "$status" -ne 0 ] && grep -Fq -- "$needle" <<<"$output"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected failure containing '$needle' (status $status)"
    printf '%s\n' "$output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

MOCK_BIN="$TMP_ROOT/bin"
mkdir -p "$MOCK_BIN"
cat >"$MOCK_BIN/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"pr list"*"--state merged"*)
    cat <<'JSON'
[{"number":101,"title":"Merged feature","url":"https://example.test/pr/101","mergedAt":"2026-07-01T00:00:00Z"}]
JSON
    ;;
  *"issue view"*"--json"*)
    # last numeric arg-ish — parse issue number from args
    issue=""
    for a in "$@"; do
      if [[ "$a" =~ ^[0-9]+$ ]]; then issue="$a"; fi
    done
    if [ "$issue" = "50" ]; then
      cat <<'JSON'
{"number":50,"title":"Epic","url":"https://example.test/issues/50","labels":[{"name":"integration-branch:demo"}],"body":"epic"}
JSON
    else
      cat <<JSON
{"number":${issue:-1},"title":"Issue ${issue:-1}","url":"https://example.test/issues/${issue:-1}","labels":[],"body":""}
JSON
    fi
    ;;
  *"issue list"*"integration-branch:demo"*)
    cat <<'JSON'
[{"number":50,"title":"Epic","url":"https://example.test/issues/50"},{"number":51,"title":"Child","url":"https://example.test/issues/51"}]
JSON
    ;;
  *)
    echo "unexpected gh: $*" >&2
    exit 99
    ;;
esac
STUB
chmod +x "$MOCK_BIN/gh"
export PATH="$MOCK_BIN:$PATH"

run_fails_contains "requires_base" "--base is required" "$HELPER" --json
run_fails_contains "rejects_feature_base" "Disallowed base" "$HELPER" --base feature/foo --json
run_fails_contains "rejects_bad_recent" "--recent-merged-prs must be" "$HELPER" --base develop --recent-merged-prs no --json

out="$("$HELPER" --base develop --recent-merged-prs 1 --json)"
run_test "recent_merged_count" "1" "$(printf '%s' "$out" | jq -r '.candidateCount')"
run_test "confirmation_required" "true" "$(printf '%s' "$out" | jq -r '.confirmationRequired')"
run_test "read_only_present" "yes" "$(printf '%s' "$out" | jq -r 'if .readOnlyGuarantee then "yes" else "no" end')"
run_test "base_echoed" "develop" "$(printf '%s' "$out" | jq -r '.base')"

out2="$("$HELPER" --base develop --issues 42 --json)"
run_test "explicit_issue" "42" "$(printf '%s' "$out2" | jq -r '.candidates[0].number')"

out3="$("$HELPER" --base develop-demo --epic 50 --json)"
run_test "epic_child_included" "yes" "$(printf '%s' "$out3" | jq -r 'any(.candidates[]; .number == 51) | if . then "yes" else "no" end')"
run_test "epic_self_excluded" "no" "$(printf '%s' "$out3" | jq -r 'any(.candidates[]; .number == 50) | if . then "yes" else "no" end')"

echo ""
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi

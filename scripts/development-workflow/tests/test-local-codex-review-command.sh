#!/usr/bin/env bash
# Unit tests for local-codex-review-command.sh.
# covers: scripts/development-workflow/local-codex-review-command.sh
# covers: scripts/development-workflow/local-codex-reviewer.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
COMMAND="$REPO_ROOT/scripts/development-workflow/local-codex-review-command.sh"
WRAPPER="$REPO_ROOT/scripts/development-workflow/local-codex-reviewer.sh"

MOCK_BIN="$(mktemp -d)"
PROMPT_LOG="$(mktemp)"
OUTPUT_FILE="$(mktemp)"
STDERR_FILE="$(mktemp)"

cleanup() {
  local status=$?
  rm -rf "$MOCK_BIN"
  rm -f "$PROMPT_LOG" "$OUTPUT_FILE" "$STDERR_FILE"
  exit "$status"
}
trap cleanup EXIT

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

cat > "$MOCK_BIN/codex" <<'MOCK_CODEX'
#!/usr/bin/env bash
output_file=""
previous=""
for arg in "$@"; do
  if [ "$previous" = "-o" ]; then
    output_file="$arg"
  fi
  previous="$arg"
done
[ -n "$output_file" ] || exit 2
printf '%s\n' "${*: -1}" > "${PROMPT_LOG:?}"
printf '{"result":"clean","reviewed_head":"%s","findings":[]}\n' "${REVIEWED_HEAD:?}" > "$output_file"
MOCK_CODEX
chmod +x "$MOCK_BIN/codex"

CONTEXT_BUNDLE_PATH="/tmp/context.json"
BASE_BRANCH="develop"
REVIEWED_HEAD="abc123"
export CONTEXT_BUNDLE_PATH BASE_BRANCH REVIEWED_HEAD PROMPT_LOG

PATH="$MOCK_BIN:$PATH" "$COMMAND" >"$OUTPUT_FILE" 2>"$STDERR_FILE"

run_test "codex_command_result" "clean" "$(jq -r '.result' "$OUTPUT_FILE")"
run_test "codex_command_reviewed_head" "abc123" "$(jq -r '.reviewed_head' "$OUTPUT_FILE")"
run_test "codex_prompt_mentions_context" "yes" "$(grep -q '/tmp/context.json' "$PROMPT_LOG" && echo yes || echo no)"
run_test "codex_prompt_mentions_base_diff" "yes" "$(grep -q 'origin/develop...HEAD' "$PROMPT_LOG" && echo yes || echo no)"
run_test "wrapper_help_mentions_evidence_file" "yes" "$("$WRAPPER" --help 2>&1 | grep -q -- '--evidence-file' && echo yes || echo no)"

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAIL: $FAIL_COUNT test(s) failed"
  exit 1
fi

echo "PASS: $PASS_COUNT test(s) passed"

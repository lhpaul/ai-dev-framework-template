#!/usr/bin/env bash
# Unit tests for local-openai-review-command.sh.
# covers: scripts/development-workflow/local-openai-review-command.sh
# covers: scripts/development-workflow/local-openai-reviewer.sh
# covers: scripts/development-workflow/local-ai-reviewer.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
COMMAND="$REPO_ROOT/scripts/development-workflow/local-openai-review-command.sh"
WRAPPER="$REPO_ROOT/scripts/development-workflow/local-openai-reviewer.sh"
REVIEWER="$REPO_ROOT/scripts/development-workflow/local-ai-reviewer.sh"

MOCK_BIN="$(mktemp -d)"
WORK_DIR="$(mktemp -d)"
REQUEST_FILE="$(mktemp)"
URL_FILE="$(mktemp)"
OUTPUT_FILE="$(mktemp)"
STDERR_FILE="$(mktemp)"
CONTEXT_BUNDLE_PATH="$WORK_DIR/context.json"

cleanup() {
  local status=$?
  rm -rf "$MOCK_BIN" "$WORK_DIR"
  rm -f "$REQUEST_FILE" "$URL_FILE" "$OUTPUT_FILE" "$STDERR_FILE"
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

cat > "$CONTEXT_BUNDLE_PATH" <<'EOF'
{"schema_version":"local_ai_reviewer_context.v1","reviewed_head":"abc123"}
EOF

cat > "$WORK_DIR/REVIEW.md" <<'EOF'
# Review Contract
EOF

cat > "$MOCK_BIN/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
output_file=""
write_fmt=""
previous=""
url=""
data_file=""
for arg in "$@"; do
  if [ "$previous" = "-o" ]; then
    output_file="$arg"
  elif [ "$previous" = "-w" ]; then
    write_fmt="$arg"
  elif [ "$previous" = "--data-binary" ]; then
    data_file="${arg#@}"
  fi
  previous="$arg"
  case "$arg" in
    http://*|https://*) url="$arg" ;;
  esac
done
[ -n "$output_file" ] || exit 2
printf '%s\n' "$url" > "${URL_FILE:?}"
if [ -n "$data_file" ] && [ -f "$data_file" ]; then
  cat "$data_file" > "${REQUEST_FILE:?}"
fi
content="${MOCK_MODEL_CONTENT:-{\"result\":\"clean\",\"reviewed_head\":\"abc123\",\"findings\":[]}}"
printf '{"choices":[{"message":{"content":%s}}]}\n' "$(printf '%s' "$content" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" > "$output_file"
if [ "$write_fmt" = '%{http_code}' ]; then
  printf '%s' "${MOCK_HTTP_CODE:-200}"
fi
MOCK_CURL
chmod +x "$MOCK_BIN/curl"

cat > "$MOCK_BIN/git" <<'MOCK_GIT'
#!/usr/bin/env bash
if [ "${MOCK_GIT_FAIL:-0}" = "1" ]; then
  echo "fatal: bad revision" >&2
  exit 128
fi
exit 0
MOCK_GIT
chmod +x "$MOCK_BIN/git"

export CONTEXT_BUNDLE_PATH BASE_BRANCH=develop REVIEWED_HEAD=abc123 REQUEST_FILE URL_FILE
export LOCAL_AI_REVIEWER_MODEL=deepseek-v4-pro
export LOCAL_AI_REVIEWER_API_BASE_URL=https://api.deepseek.com
export LOCAL_AI_REVIEWER_API_KEY=test-key
export LOCAL_AI_REVIEWER_CURL_BIN="$MOCK_BIN/curl"
export LOCAL_AI_REVIEWER_JSON_OBJECT=1

(
  cd "$WORK_DIR"
  PATH="$MOCK_BIN:$PATH" "$COMMAND"
) >"$OUTPUT_FILE" 2>"$STDERR_FILE"

run_test "openai_command_result" "clean" "$(jq -r '.result' "$OUTPUT_FILE")"
run_test "openai_command_reviewed_head" "abc123" "$(jq -r '.reviewed_head' "$OUTPUT_FILE")"
run_test "openai_posts_chat_completions" "yes" "$(grep -q 'https://api.deepseek.com/chat/completions' "$URL_FILE" && echo yes || echo no)"
run_test "openai_inlines_context_bundle" "yes" "$(grep -q 'local_ai_reviewer_context.v1' "$REQUEST_FILE" && echo yes || echo no)"
run_test "openai_inlines_review_md" "yes" "$(grep -q 'Review Contract' "$REQUEST_FILE" && echo yes || echo no)"
run_test "openai_requests_json_object" "yes" "$(jq -e '.response_format.type == "json_object"' "$REQUEST_FILE" >/dev/null && echo yes || echo no)"
run_test "openai_model_id" "deepseek-v4-pro" "$(jq -r '.model' "$REQUEST_FILE")"

REVIEW_STAGE=implementation
REVIEW_CHECKLISTS="Code Review Checklist,Workflow Policy Review Checklist"
export REVIEW_STAGE REVIEW_CHECKLISTS
(
  cd "$WORK_DIR"
  PATH="$MOCK_BIN:$PATH" "$COMMAND"
) >"$OUTPUT_FILE" 2>"$STDERR_FILE"
run_test "openai_stage_in_full" "yes" "$(grep -Fq 'in full' "$REQUEST_FILE" && echo yes || echo no)"
run_test "openai_stage_names_sections" "yes" "$(grep -Fq 'Code Review Checklist,Workflow Policy Review Checklist' "$REQUEST_FILE" && echo yes || echo no)"

unset REVIEW_STAGE REVIEW_CHECKLISTS
MOCK_MODEL_CONTENT=$'```json\n{"result":"needs_fixes","reviewed_head":"abc123","findings":[]}\n```'
export MOCK_MODEL_CONTENT
(
  cd "$WORK_DIR"
  PATH="$MOCK_BIN:$PATH" "$COMMAND"
) >"$OUTPUT_FILE" 2>"$STDERR_FILE"
run_test "openai_strips_markdown_fence" "needs_fixes" "$(jq -r '.result' "$OUTPUT_FILE")"
unset MOCK_MODEL_CONTENT

unset LOCAL_AI_REVIEWER_API_KEY DEEPSEEK_API_KEY OPENAI_API_KEY LOCAL_AI_REVIEWER_API_KEY_COMMAND
(
  cd "$WORK_DIR"
  PATH="$MOCK_BIN:$PATH" "$COMMAND"
) >"$OUTPUT_FILE" 2>"$STDERR_FILE" || true
run_test "openai_missing_credentials" "yes" "$(grep -Eiq 'missing credentials' "$STDERR_FILE" && echo yes || echo no)"
export LOCAL_AI_REVIEWER_API_KEY=test-key

run_test "wrapper_help_mentions_evidence_file" "yes" "$("$WRAPPER" --help 2>&1 | grep -q -- '--evidence-file' && echo yes || echo no)"
run_test "wrapper_help_mentions_model" "yes" "$("$WRAPPER" --help 2>&1 | grep -q 'LOCAL_AI_REVIEWER_MODEL' && echo yes || echo no)"

MOCK_GIT_FAIL=1
export MOCK_GIT_FAIL
(
  cd "$WORK_DIR"
  PATH="$MOCK_BIN:$PATH" "$COMMAND"
) >"$OUTPUT_FILE" 2>"$STDERR_FILE" || true
run_test "openai_git_diff_failure_exits" "yes" "$(grep -q 'git diff origin/develop...HEAD failed' "$STDERR_FILE" && echo yes || echo no)"
unset MOCK_GIT_FAIL

# Backend resolution through local-ai-reviewer.sh
unset LOCAL_AI_REVIEWER_COMMAND
LOCAL_AI_REVIEWER_BACKEND=openai_compat
export LOCAL_AI_REVIEWER_BACKEND
# shellcheck source=scripts/development-workflow/local-ai-reviewer.sh
HARNESS_MODE=1 source "$REVIEWER"
resolve_stderr="$(mktemp)"
resolve_local_ai_reviewer_command 2>"$resolve_stderr"
run_test "backend_defaults_to_openai_preset" "yes" "$(printf '%s' "$LOCAL_AI_REVIEWER_COMMAND" | grep -q 'local-openai-review-command.sh' && echo yes || echo no)"
run_test "backend_info_mentions_openai_preset" "yes" "$(grep -q 'bundled openai-compatible preset' "$resolve_stderr" && echo yes || echo no)"
rm -f "$resolve_stderr"
unset LOCAL_AI_REVIEWER_COMMAND
LOCAL_AI_REVIEWER_BACKEND=openai
export LOCAL_AI_REVIEWER_BACKEND
set +e
resolve_local_ai_reviewer_command 2>"$STDERR_FILE"
alias_rc=$?
set -e
run_test "backend_rejects_openai_alias" "1" "$alias_rc"
run_test "backend_alias_error_names_openai_compat" "yes" "$(grep -q 'expected codex or openai_compat' "$STDERR_FILE" && echo yes || echo no)"
unset LOCAL_AI_REVIEWER_BACKEND LOCAL_AI_REVIEWER_COMMAND

LOCAL_AI_REVIEWER_BACKEND=not-a-backend
export LOCAL_AI_REVIEWER_BACKEND
set +e
resolve_local_ai_reviewer_command 2>"$STDERR_FILE"
unknown_rc=$?
set -e
run_test "backend_unknown_nonzero" "1" "$unknown_rc"
unset LOCAL_AI_REVIEWER_BACKEND LOCAL_AI_REVIEWER_COMMAND

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAIL: $FAIL_COUNT test(s) failed"
  exit 1
fi

echo "PASS: $PASS_COUNT test(s) passed"

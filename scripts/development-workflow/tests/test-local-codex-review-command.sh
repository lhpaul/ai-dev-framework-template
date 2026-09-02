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

DEFAULT_PROMPT_WITHOUT_STAGE='Review this PR change using REVIEW.md and the JSON context at /tmp/context.json. Inspect the changed files against origin/develop...HEAD, using the context bundle diff metadata as a guide. Return only a compact JSON object with fields: result (clean or needs_fixes), reviewed_head, findings array. Each finding should include severity, path, line, message, and clear_in_scope. Use needs_fixes only for clear in-scope blocking issues; advisory or nit findings should not block.'

PATH="$MOCK_BIN:$PATH" "$COMMAND" >"$OUTPUT_FILE" 2>"$STDERR_FILE"

run_test "codex_command_result" "clean" "$(jq -r '.result' "$OUTPUT_FILE")"
run_test "codex_command_reviewed_head" "abc123" "$(jq -r '.reviewed_head' "$OUTPUT_FILE")"
run_test "codex_prompt_mentions_context" "yes" "$(grep -q '/tmp/context.json' "$PROMPT_LOG" && echo yes || echo no)"
run_test "codex_prompt_mentions_base_diff" "yes" "$(grep -q 'origin/develop...HEAD' "$PROMPT_LOG" && echo yes || echo no)"
run_test "wrapper_help_mentions_evidence_file" "yes" "$("$WRAPPER" --help 2>&1 | grep -q -- '--evidence-file' && echo yes || echo no)"

# Scenario 11: default stage (no REVIEW_CHECKLISTS) is byte-identical to fixture
run_test "1653_s11_default_prompt" "$DEFAULT_PROMPT_WITHOUT_STAGE" "$(cat "$PROMPT_LOG")"

# Scenario 10: stage sentence includes monotonicity wording
REVIEW_STAGE="implementation"
REVIEW_STAGE_SOURCE="branch+files"
REVIEW_CHECKLISTS="Code Review Checklist,Workflow Policy Review Checklist"
export REVIEW_STAGE REVIEW_STAGE_SOURCE REVIEW_CHECKLISTS
PATH="$MOCK_BIN:$PATH" "$COMMAND" >"$OUTPUT_FILE" 2>"$STDERR_FILE"
run_test "1653_s10_in_full" "yes" "$(grep -Fq 'in full' "$PROMPT_LOG" && echo yes || echo no)"
run_test "1653_s10_core_rules" "yes" "$(grep -Fq 'Core Rules' "$PROMPT_LOG" && echo yes || echo no)"
run_test "1653_s10_names_sections" "yes" "$(grep -Fq 'Code Review Checklist,Workflow Policy Review Checklist' "$PROMPT_LOG" && echo yes || echo no)"

# Scenario 15: override wins — no stage sentence appended
LOCAL_CODEX_REVIEWER_PROMPT="custom override prompt"
export LOCAL_CODEX_REVIEWER_PROMPT
PATH="$MOCK_BIN:$PATH" "$COMMAND" >"$OUTPUT_FILE" 2>"$STDERR_FILE"
run_test "1653_s15_override_exact" "custom override prompt" "$(cat "$PROMPT_LOG")"

# Scenario 15a: bundled command receives all three stage env vars
unset LOCAL_CODEX_REVIEWER_PROMPT
ENV_DUMP="$(mktemp)"
cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
  *"pr view 123"*"--json baseRefName,headRefName,headRefOid"*)
    printf '{"baseRefName":"develop","headRefName":"refactor/1653-test","headRefOid":"abc123"}\n'
    exit 0
    ;;
  *"pr diff 123"*"--name-only"*)
    printf 'REVIEW.md\nscripts/example.sh\n'
    exit 0
    ;;
  *)
    exit 1
    ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"
cat > "$MOCK_BIN/local-ai-reviewer-env-dump" <<'MOCK_DUMP'
#!/usr/bin/env bash
env | sort > "${ENV_DUMP:?}"
printf '%s\n' '{"result":"clean","reviewed_head":"abc123","findings":[]}'
MOCK_DUMP
chmod +x "$MOCK_BIN/local-ai-reviewer-env-dump"
LOCAL_AI_REVIEWER_COMMAND=local-ai-reviewer-env-dump
export LOCAL_AI_REVIEWER_COMMAND ENV_DUMP
PATH="$MOCK_BIN:$PATH" "$REPO_ROOT/scripts/development-workflow/local-ai-reviewer.sh" \
  123 owner repo >"$OUTPUT_FILE" 2>"$STDERR_FILE" || true
run_test "1653_s15a_env_stage" "yes" "$(grep -q '^REVIEW_STAGE=' "$ENV_DUMP" && echo yes || echo no)"
run_test "1653_s15a_env_source" "yes" "$(grep -q '^REVIEW_STAGE_SOURCE=' "$ENV_DUMP" && echo yes || echo no)"
run_test "1653_s15a_env_lists" "yes" "$(grep -q '^REVIEW_CHECKLISTS=' "$ENV_DUMP" && echo yes || echo no)"
rm -f "$ENV_DUMP"

# Scenario 8a: workflow-policy sentence identical across three Pass-restricted surfaces
_1653_policy_sentence='When the change under review touches workflow-policy surfaces'
run_test "1653_s8a_claude" "yes" "$(grep -Fq "$_1653_policy_sentence" "$REPO_ROOT/.claude/agents/code-reviewer.md" && echo yes || echo no)"
run_test "1653_s8a_cursor" "yes" "$(grep -Fq "$_1653_policy_sentence" "$REPO_ROOT/.cursor/agents/code-reviewer.md" && echo yes || echo no)"
run_test "1653_s8a_codex" "yes" "$(grep -Fq "$_1653_policy_sentence" "$REPO_ROOT/.codex/skills/workflow-code-reviewer/SKILL.md" && echo yes || echo no)"
_1653_claude_line="$(grep -F "$_1653_policy_sentence" "$REPO_ROOT/.claude/agents/code-reviewer.md")"
_1653_cursor_line="$(grep -F "$_1653_policy_sentence" "$REPO_ROOT/.cursor/agents/code-reviewer.md")"
_1653_codex_line="$(grep -F "$_1653_policy_sentence" "$REPO_ROOT/.codex/skills/workflow-code-reviewer/SKILL.md" | sed -E 's/^[0-9]+\. //')"
run_test "1653_s8a_claude_cursor_match" "yes" "$([ "$_1653_claude_line" = "$_1653_cursor_line" ] && echo yes || echo no)"
run_test "1653_s8a_claude_codex_match" "yes" "$([ "$_1653_claude_line" = "$_1653_codex_line" ] && echo yes || echo no)"

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAIL: $FAIL_COUNT test(s) failed"
  exit 1
fi

echo "PASS: $PASS_COUNT test(s) passed"

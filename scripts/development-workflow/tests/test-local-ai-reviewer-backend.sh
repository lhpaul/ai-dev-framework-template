#!/usr/bin/env bash
# Backend selection tests for local-ai-reviewer.sh (#1957): the shared-default
# resolver subcommand (T-R1 to T-R7) and end-to-end backend resolution, the
# direct-run budget, and preset outcome classification (T-B1 to T-B15).
# covers: scripts/development-workflow/local-ai-reviewer.sh
# covers: scripts/development-workflow/local-claude-review-command.sh
# covers: scripts/development-workflow/workflow-config-resolver.py
#
# Hermetic: every case pins AI_DEV_WORKFLOW_CONFIG_FILE to a fixture file, or
# runs a copied tooling tree when the case needs "no shared file" (plan D7).
# Stand-in claude/codex binaries replace the real CLIs; no login is used.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR" && git rev-parse --show-toplevel)"
TOOLS="$REPO_ROOT/scripts/development-workflow"
RESOLVER="$TOOLS/workflow-config-resolver.py"
REVIEWER="$TOOLS/local-ai-reviewer.sh"

TMP_ROOT="$(mktemp -d)"
TMP_ROOT="$(CDPATH='' cd -- "$TMP_ROOT" && pwd -P)"
cleanup() {
  local status=$?
  chmod -R u+rwx "$TMP_ROOT" 2>/dev/null || true
  rm -rf "$TMP_ROOT"
  exit "$status"
}
trap cleanup EXIT

PASS_COUNT=0
FAIL_COUNT=0

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

yes_no() { if "$@"; then echo yes; else echo no; fi; }

# ---------------------------------------------------------------------------
# T-R1 to T-R7: resolver subcommand review-local-ai-backend (plan D1)
# ---------------------------------------------------------------------------
CFG_DIR="$TMP_ROOT/cfg"
mkdir -p "$CFG_DIR"

# cfg <name> <body>: write a configuration fixture and print its path.
cfg() {
  printf '%s' "$2" > "$CFG_DIR/$1.yaml"
  printf '%s\n' "$CFG_DIR/$1.yaml"
}

# shared_backend_cfg <name> <backend line>: review.local_ai_reviewer.<line>.
shared_backend_cfg() {
  cfg "$1" "review:
  local_ai_reviewer:
    $2
"
}

RESOLVE_OUT=""
RESOLVE_RC=0
resolve_backend() {
  RESOLVE_RC=0
  RESOLVE_OUT="$(python3 "$RESOLVER" review-local-ai-backend --file "$1" 2>"$TMP_ROOT/resolver.err")" || RESOLVE_RC=$?
}

expect_row() {
  local name="$1" file="$2" want_out="$3" want_rc="$4"
  resolve_backend "$file"
  run_test "${name}_stdout" "$want_out" "$RESOLVE_OUT"
  run_test "${name}_exit" "$want_rc" "$RESOLVE_RC"
}

# T-R1: Y1 missing file, Y2 empty or comment-only, Y3 review without the key.
expect_row "T-R1_missing_file" "$CFG_DIR/does-not-exist.yaml" "" 0
expect_row "T-R1_directory" "$CFG_DIR" "" 0
expect_row "T-R1_empty_file" "$(cfg empty '')" "" 0
expect_row "T-R1_comment_only" "$(cfg comment '# nothing here
')" "" 0
expect_row "T-R1_review_without_key" "$(cfg review_only 'review:
  on_ready:
    github:
      - local-ai-reviewer
')" "" 0
expect_row "T-R1_section_null" "$(cfg section_null 'review:
  local_ai_reviewer:
')" "" 0

# T-R2: Y4 no value / null, Y5 empty string.
expect_row "T-R2_no_value" "$(shared_backend_cfg no_value 'backend:')" "" 0
expect_row "T-R2_null" "$(shared_backend_cfg null 'backend: null')" "" 0
expect_row "T-R2_empty_string" "$(shared_backend_cfg empty_string 'backend: ""')" "" 0

# T-R3: Y6 plain, quoted, and commented names.
expect_row "T-R3_plain" "$(shared_backend_cfg plain 'backend: claude')" "claude" 0
expect_row "T-R3_quoted" "$(shared_backend_cfg quoted 'backend: "claude"')" "claude" 0
expect_row "T-R3_comment" "$(shared_backend_cfg commented 'backend: claude # note')" "claude" 0
expect_row "T-R3_codex" "$(shared_backend_cfg codex 'backend: codex')" "codex" 0
expect_row "T-R3_openai_compat" "$(shared_backend_cfg openai_compat 'backend: openai_compat')" "openai_compat" 0

# T-R4: Y7 non-string values, Y8 scalar section.
expect_row "T-R4_list" "$(shared_backend_cfg list 'backend: [claude]')" "" 3
expect_row "T-R4_mapping" "$(shared_backend_cfg mapping 'backend:
      name: claude')" "" 3
expect_row "T-R4_number" "$(shared_backend_cfg number 'backend: 3')" "" 3
expect_row "T-R4_boolean" "$(shared_backend_cfg boolean 'backend: true')" "" 3
expect_row "T-R4_scalar_section" "$(cfg scalar_section 'review:
  local_ai_reviewer: claude
')" "" 3
expect_row "T-R4_scalar_review" "$(cfg scalar_review 'review: claude
')" "" 3

# T-R5: Y9 decoder rejections count as unreadable (exit 4).
expect_row "T-R5_invalid_yaml" "$(cfg invalid_yaml 'review:
  local_ai_reviewer:
    backend: [claude
')" "" 4
expect_row "T-R5_duplicate_key" "$(cfg duplicate 'review:
  local_ai_reviewer:
    backend: claude
    backend: codex
')" "" 4
expect_row "T-R5_flow_mapping" "$(cfg flow 'review:
  local_ai_reviewer: {backend: claude}
')" "" 4
printf 'review:\n  local_ai_reviewer:\n    backend: cl\377aude\n' > "$CFG_DIR/non_utf8.yaml"
expect_row "T-R5_non_utf8" "$CFG_DIR/non_utf8.yaml" "" 4
run_test "T-R5_no_traceback" "no" "$(yes_no grep -q 'Traceback' "$TMP_ROOT/resolver.err")"

# T-R6: Y10 raw case kept; Y12 grammar refusal (exit 3, empty stdout).
expect_row "T-R6_uppercase_raw" "$(shared_backend_cfg upper 'backend: CLAUDE')" "CLAUDE" 0
expect_row "T-R6_trailing_newline" "$(shared_backend_cfg trailing_nl 'backend: "claude\n"')" "" 3
expect_row "T-R6_only_newline" "$(shared_backend_cfg only_nl 'backend: "\n"')" "" 3
expect_row "T-R6_leading_space" "$(shared_backend_cfg leading_space 'backend: " claude"')" "" 3
expect_row "T-R6_tab" "$(shared_backend_cfg tab 'backend: "cl\taude"')" "" 3
expect_row "T-R6_trailing_space" "$(shared_backend_cfg trailing_space "backend: 'claude '")" "" 3
expect_row "T-R6_non_ascii_letter" "$(shared_backend_cfg non_ascii 'backend: "cláude"')" "" 3

# T-R7: Y11 the new block leaves the existing review readers unchanged.
y11_base='review:
  on_draft:
    runner:
      - claude
    github:
      - pr-agent
  on_ready:
    github:
      - local-ai-reviewer
  wait_budgets:
    local-ai-reviewer: 1500
'
y11_without="$(cfg y11_without "$y11_base")"
y11_with="$(cfg y11_with "$y11_base  local_ai_reviewer:
    backend: claude
")"
y11_between="$(cfg y11_between 'review:
  on_draft:
    github:
      - pr-agent
  local_ai_reviewer:
    backend: claude
  on_ready:
    github:
      - local-ai-reviewer
  wait_budgets:
    local-ai-reviewer: 1500
')"
y11_readers() {
  (
    # shellcheck source=scripts/development-workflow/workflow-lib.sh
    source "$TOOLS/workflow-lib.sh"
    printf 'draft_github=%s\n' "$(workflow_config_review_on_draft_github "$1" | tr '\n' ',')"
    printf 'ready_github=%s\n' "$(workflow_config_review_on_ready_github "$1" | tr '\n' ',')"
    printf 'wait=%s\n' "$(workflow_config_review_wait_budget local-ai-reviewer "$1")"
    printf 'list=%s\n' "$(python3 "$RESOLVER" review-list --shared-file "$1" --phase on_ready --key github | tr '\n' ',')"
  )
}
y11_reference="$(y11_readers "$y11_without")"
run_test "T-R7_reference_sane" "yes" "$(yes_no grep -q 'ready_github=local-ai-reviewer,' <<< "$y11_reference")"
run_test "T-R7_wait_reference" "yes" "$(yes_no grep -qx 'wait=1500' <<< "$y11_reference")"
run_test "T-R7_readers_unchanged_after_block" "$y11_reference" "$(y11_readers "$y11_with")"
run_test "T-R7_readers_unchanged_between_blocks" "$(y11_readers "$y11_without" | sed '/^draft_github=/d')" "$(y11_readers "$y11_between" | sed '/^draft_github=/d')"
expect_row "T-R7_backend_after_block" "$y11_with" "claude" 0
expect_row "T-R7_backend_between_blocks" "$y11_between" "claude" 0

# @@T-B-SECTION@@

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAIL: $FAIL_COUNT test(s) failed"
  exit 1
fi

echo "PASS: $PASS_COUNT test(s) passed"

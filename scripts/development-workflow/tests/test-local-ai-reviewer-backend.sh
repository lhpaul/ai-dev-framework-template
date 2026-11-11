#!/usr/bin/env bash
# Backend selection tests for local-ai-reviewer.sh (#1957): the shared-default
# resolver subcommand (T-R1 to T-R7) and end-to-end backend resolution, the
# direct-run budget, and preset outcome classification (T-B1 to T-B15).
# duration: 95
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

# ---------------------------------------------------------------------------
# T-B1 to T-B15: end-to-end backend resolution, budget, and outcomes
# ---------------------------------------------------------------------------
GLOBAL_GITCONFIG="$TMP_ROOT/global.gitconfig"
: > "$GLOBAL_GITCONFIG"
export GIT_CONFIG_GLOBAL="$GLOBAL_GITCONFIG"
export GIT_CONFIG_NOSYSTEM=1
export TMPDIR="$TMP_ROOT/tmp"
mkdir -p "$TMPDIR"
unset LOCAL_AI_REVIEWER_COMMAND LOCAL_AI_REVIEWER_BACKEND LOCAL_AI_REVIEWER_DISABLE_DEFAULT
unset LOCAL_AI_REVIEWER_DISABLED LOCAL_AI_REVIEWER_TIMEOUT LOCAL_AI_REVIEWER_EVIDENCE_FILE
unset LOCAL_CLAUDE_REVIEWER_BIN LOCAL_CLAUDE_REVIEWER_MODEL LOCAL_CLAUDE_REVIEWER_PROMPT LOCAL_CLAUDE_REVIEWER_STRICT_PROMPT
unset LOCAL_CODEX_REVIEWER_BIN LOCAL_CODEX_REVIEWER_MODEL LOCAL_CODEX_REVIEWER_PROMPT LOCAL_CODEX_REVIEWER_STRICT_PROMPT
export LOCAL_AI_REVIEWER_GRAPH_STRATEGY=none

MOCK_BIN="$TMP_ROOT/mock-bin"
mkdir -p "$MOCK_BIN"
export CLAUDE_REC="$TMP_ROOT/rec-claude"
export CODEX_REC="$TMP_ROOT/rec-codex"
export CURL_REC="$TMP_ROOT/rec-curl"
export CMD_REC="$TMP_ROOT/rec-command"

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
  *"pr view 123"*"--json baseRefName,headRefName,headRefOid"*)
    printf '{"baseRefName":"develop","headRefName":"feature/1957-fixture","headRefOid":"%s"}\n' "${MOCK_PR_HEAD_SHA:?}"
    ;;
  *"pr diff 123"*"--name-only"*)
    printf '%s\n' change.txt
    ;;
  *)
    exit 1
    ;;
esac
MOCK_GH

# Stand-in claude: records its budget and argv, then prints scripted output.
cat > "$MOCK_BIN/claude" <<'MOCK_CLAUDE'
#!/usr/bin/env bash
d="${CLAUDE_REC:?}"
mkdir -p "$d"
: > "$d/ran"
printf '%s\n' "${LOCAL_AI_REVIEWER_TIMEOUT:-}" > "$d/timeout"
printf '%s\n' "${LOCAL_AI_REVIEWER_TIMEOUT:-}" >> "$d/timeouts"
if [ -n "${STANDIN_ACTION:-}" ]; then eval "$STANDIN_ACTION"; fi
if [ -n "${STANDIN_SLEEP:-}" ]; then sleep "$STANDIN_SLEEP"; fi
if [ -n "${STANDIN_STDERR:-}" ]; then printf '%s\n' "$STANDIN_STDERR" >&2; fi
if [ -n "${STANDIN_STDOUT+x}" ]; then
  printf '%s\n' "$STANDIN_STDOUT"
else
  printf '{"result":"clean","findings":[]}\n'
fi
exit "${STANDIN_EXIT:-0}"
MOCK_CLAUDE

# Stand-in codex: records its budget and writes a clean verdict to -o.
cat > "$MOCK_BIN/codex" <<'MOCK_CODEX'
#!/usr/bin/env bash
mkdir -p "${CODEX_REC:?}"
: > "$CODEX_REC/ran"
printf '%s\n' "${LOCAL_AI_REVIEWER_TIMEOUT:-}" > "$CODEX_REC/timeout"
out=""
prev=""
for arg in "$@"; do
  [ "$prev" = "-o" ] && out="$arg"
  prev="$arg"
done
printf '{"result":"clean","reviewed_head":"%s","findings":[]}\n' "${REVIEWED_HEAD:?}" > "$out"
MOCK_CODEX

# Stand-in curl for the HTTP preset: records its budget, returns a verdict.
cat > "$MOCK_BIN/curl" <<'MOCK_CURL'
#!/usr/bin/env bash
mkdir -p "${CURL_REC:?}"
: > "$CURL_REC/ran"
printf '%s\n' "${LOCAL_AI_REVIEWER_TIMEOUT:-}" > "$CURL_REC/timeout"
out=""
while [ "$#" -gt 0 ]; do
  case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
printf '{"choices":[{"message":{"content":"{\\"result\\":\\"clean\\",\\"findings\\":[]}"}}]}' > "$out"
printf '200'
MOCK_CURL

# An explicit reviewer command.
cat > "$MOCK_BIN/explicit-review" <<'MOCK_CMD'
#!/usr/bin/env bash
mkdir -p "${CMD_REC:?}"
: > "$CMD_REC/ran"
printf '{"result":"clean","findings":[]}\n'
MOCK_CMD
chmod +x "$MOCK_BIN"/*

FX="$TMP_ROOT/fx"
git init -q -b main "$FX"
git -C "$FX" config user.email fixture@example.test
git -C "$FX" config user.name Fixture
printf '# Review contract\n' > "$FX/REVIEW.md"
git -C "$FX" add REVIEW.md
git -C "$FX" commit -qm base
git -C "$FX" update-ref refs/remotes/origin/develop HEAD
git -C "$FX" remote add origin git@github.com:owner/repo.git
printf 'change\n' > "$FX/change.txt"
git -C "$FX" add change.txt
git -C "$FX" commit -qm change
PR_HEAD="$(git -C "$FX" rev-parse HEAD)"
export MOCK_PR_HEAD_SHA="$PR_HEAD"

NEUTRAL_CFG="$(cfg neutral '')"
SHARED_CLAUDE="$(shared_backend_cfg sh_claude 'backend: claude')"
SHARED_CODEX="$(shared_backend_cfg sh_codex 'backend: codex')"
SHARED_HTTP="$(shared_backend_cfg sh_http 'backend: http')"
SHARED_COMPAT="$(shared_backend_cfg sh_compat 'backend: openai_compat')"
SHARED_EMPTY="$(shared_backend_cfg sh_empty 'backend: ""')"
SHARED_LIST="$(shared_backend_cfg sh_list 'backend: [claude]')"
SHARED_NEWLINE="$(shared_backend_cfg sh_newline 'backend: "claude\n"')"
SHARED_UNKNOWN="$(shared_backend_cfg sh_unknown 'backend: plantedSharedValue456')"
SHARED_UNREADABLE="$(cfg sh_unreadable 'review:
  local_ai_reviewer: {backend: claude}
')"

ROUT="$TMP_ROOT/reviewer.out"
RERR="$TMP_ROOT/reviewer.err"
RRC=0

# review [VAR=value...] -- [reviewer args...]: run local-ai-reviewer.sh for
# PR 123 against the fixture, with fresh stand-in records.
REVIEWER_UNDER_TEST="$REVIEWER"
review() {
  local -a envs=()
  while [ "$#" -gt 0 ] && [ "$1" != "--" ]; do envs+=("$1"); shift; done
  [ "$#" -gt 0 ] && shift
  rm -rf "$CLAUDE_REC" "$CODEX_REC" "$CURL_REC" "$CMD_REC"
  RRC=0
  env PATH="$MOCK_BIN:$PATH" LOCAL_AI_REVIEWER_MODEL=fixture-model \
    LOCAL_AI_REVIEWER_API_BASE_URL=https://fixture.invalid LOCAL_AI_REVIEWER_API_KEY=fixture-key \
    ${envs[@]+"${envs[@]}"} "$REVIEWER_UNDER_TEST" 123 owner repo --repo-root "$FX" "$@" >"$ROUT" 2>"$RERR" || RRC=$?
}

kv() { grep "^$1=" "$ROUT" | head -n 1 | cut -d= -f2- || true; }
rerr_has() { grep -Fq -- "$1" "$RERR"; }
ran() { [ -e "$1/ran" ]; }
claude_info='defaulted to bundled Claude preset'
codex_info='defaulted to bundled Codex preset'
http_info='defaulted to bundled HTTP preset'
budget_info='timeout defaulted to 900s for the bundled Claude preset'
shared_error='ERROR: configuration validation error; key=review.local_ai_reviewer.backend'
env_error='ERROR: configuration validation error; key=LOCAL_AI_REVIEWER_BACKEND'

# T-B1: environment selection runs Claude, and the verdict follows it.
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude --
run_test "T-B1_result_clean" "clean" "$(kv RESULT)"
run_test "T-B1_exit" "0" "$RRC"
run_test "T-B1_info_names_claude" "yes" "$(yes_no rerr_has "$claude_info")"
run_test "T-B1_claude_ran" "yes" "$(yes_no ran "$CLAUDE_REC")"
run_test "T-B1_codex_not_ran" "no" "$(yes_no ran "$CODEX_REC")"
run_test "T-B1_reviewed_head" "$PR_HEAD" "$(kv REVIEWED_HEAD)"
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude \
  STANDIN_STDOUT='{"result":"needs_fixes","findings":[{"severity":"blocking","path":"change.txt","line":1,"message":"broken","clear_in_scope":true}]}' --
run_test "T-B1_result_needs_fixes" "needs_fixes" "$(kv RESULT)"
run_test "T-B1_needs_fixes_blocking" "1" "$(kv BLOCKING_COUNT)"
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude \
  STANDIN_STDOUT='{"result":"clean","reviewed_head":"ffffffffffffffffffffffffffffffffffffffff","findings":[]}' --
run_test "T-B1_wrong_head_still_clean" "clean" "$(kv RESULT)"
run_test "T-B1_wrong_head_reviewed_head" "$PR_HEAD" "$(kv REVIEWED_HEAD)"
run_test "T-B1_wrong_head_not_mismatch" "no" "$(yes_no grep -q head_mismatch "$ROUT")"

# T-B2: no command, no selection, neutral configuration runs Codex.
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" --
run_test "T-B2_result" "clean" "$(kv RESULT)"
run_test "T-B2_info_names_codex" "yes" "$(yes_no rerr_has "$codex_info")"
run_test "T-B2_codex_ran" "yes" "$(yes_no ran "$CODEX_REC")"
run_test "T-B2_claude_not_ran" "no" "$(yes_no ran "$CLAUDE_REC")"
run_test "T-B2_no_budget_line" "no" "$(yes_no rerr_has "$budget_info")"

# T-B3: an explicit command wins; disabling the default ignores the shared value.
review AI_DEV_WORKFLOW_CONFIG_FILE="$SHARED_CLAUDE" LOCAL_AI_REVIEWER_BACKEND=claude \
  LOCAL_AI_REVIEWER_COMMAND=explicit-review --
run_test "T-B3_explicit_result" "clean" "$(kv RESULT)"
run_test "T-B3_explicit_ran" "yes" "$(yes_no ran "$CMD_REC")"
run_test "T-B3_explicit_claude_not_ran" "no" "$(yes_no ran "$CLAUDE_REC")"
run_test "T-B3_explicit_no_preset_info" "no" "$(yes_no rerr_has 'defaulted to bundled')"
review AI_DEV_WORKFLOW_CONFIG_FILE="$SHARED_CLAUDE" LOCAL_AI_REVIEWER_DISABLE_DEFAULT=1 --
run_test "T-B3_disable_default_reason" "missing_command" "$(kv REASON)"
run_test "T-B3_disable_default_result" "escalate" "$(kv RESULT)"
run_test "T-B3_disable_default_claude_not_ran" "no" "$(yes_no ran "$CLAUDE_REC")"

# T-B4: the shared default selects Claude; a non-empty selection overrides it.
review AI_DEV_WORKFLOW_CONFIG_FILE="$SHARED_CLAUDE" --
run_test "T-B4_shared_claude_info" "yes" "$(yes_no rerr_has "$claude_info")"
run_test "T-B4_shared_claude_ran" "yes" "$(yes_no ran "$CLAUDE_REC")"
run_test "T-B4_shared_claude_result" "clean" "$(kv RESULT)"
review AI_DEV_WORKFLOW_CONFIG_FILE="$SHARED_CLAUDE" LOCAL_AI_REVIEWER_BACKEND=http --
run_test "T-B4_env_http_info" "yes" "$(yes_no rerr_has "$http_info")"
run_test "T-B4_env_http_claude_not_ran" "no" "$(yes_no ran "$CLAUDE_REC")"
review AI_DEV_WORKFLOW_CONFIG_FILE="$SHARED_CLAUDE" LOCAL_AI_REVIEWER_BACKEND= --
run_test "T-B4_empty_env_uses_shared" "yes" "$(yes_no rerr_has "$claude_info")"

# T-B5: every shared value, every "not set" form, and the invalid forms.
for t5_case in "codex|$SHARED_CODEX|$codex_info" "http|$SHARED_HTTP|$http_info" \
    "openai_compat|$SHARED_COMPAT|$http_info" "claude|$SHARED_CLAUDE|$claude_info" \
    "absent|$NEUTRAL_CFG|$codex_info" "empty|$SHARED_EMPTY|$codex_info" \
    "unreadable|$SHARED_UNREADABLE|$codex_info"; do
  t5_id="${t5_case%%|*}"
  t5_rest="${t5_case#*|}"
  review AI_DEV_WORKFLOW_CONFIG_FILE="${t5_rest%%|*}" --
  run_test "T-B5_${t5_id}_selects_preset" "yes" "$(yes_no rerr_has "${t5_rest#*|}")"
done
review AI_DEV_WORKFLOW_CONFIG_FILE="$SHARED_UNREADABLE" --
run_test "T-B5_unreadable_warns" "yes" "$(yes_no grep -Fxq 'WARN: configuration unreadable; key=review.local_ai_reviewer.backend; using the built-in default backend' "$RERR")"
for t5_bad in "list|$SHARED_LIST" "newline|$SHARED_NEWLINE"; do
  review AI_DEV_WORKFLOW_CONFIG_FILE="${t5_bad#*|}" --
  run_test "T-B5_${t5_bad%%|*}_reason" "invalid_backend" "$(kv REASON)"
  run_test "T-B5_${t5_bad%%|*}_diagnostic" "yes" "$(yes_no grep -Fxq "$shared_error" "$RERR")"
  run_test "T-B5_${t5_bad%%|*}_no_preset_ran" "no/no" "$(yes_no ran "$CLAUDE_REC")/$(yes_no ran "$CODEX_REC")"
done
# The private local configuration is never a source for the backend.
LOCAL_DIR="$TMP_ROOT/local-cfg"
mkdir -p "$LOCAL_DIR"
cp "$NEUTRAL_CFG" "$LOCAL_DIR/.ai-dev-workflow.yaml"
printf 'review:\n  local_ai_reviewer:\n    backend: claude\n' > "$LOCAL_DIR/.ai-dev-workflow.local.yaml"
printf 'review:\n  local_ai_reviewer:\n    backend: claude\n' > "$FX/.ai-dev-workflow.local.yaml"
printf '.ai-dev-workflow.local.yaml\n' >> "$FX/.git/info/exclude"
review AI_DEV_WORKFLOW_CONFIG_FILE="$LOCAL_DIR/.ai-dev-workflow.yaml" WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="$LOCAL_DIR" --
run_test "T-B5_private_local_ignored" "yes" "$(yes_no rerr_has "$codex_info")"
run_test "T-B5_private_local_claude_not_ran" "no" "$(yes_no ran "$CLAUDE_REC")"
rm -f "$FX/.ai-dev-workflow.local.yaml"
# No shared file at all: a copied tooling tree whose root has no
# .ai-dev-workflow.yaml, so the fallback cannot reach a consumer's own file.
TOOLING="$TMP_ROOT/tooling"
mkdir -p "$TOOLING/scripts/development-workflow"
while IFS= read -r -d '' t5_path; do
  case "$t5_path" in
    scripts/development-workflow/*/*) ;;
    scripts/development-workflow/*.sh|scripts/development-workflow/*.py)
      cp -p "$REPO_ROOT/$t5_path" "$TOOLING/$t5_path" ;;
  esac
done < <(git -C "$REPO_ROOT" ls-files -z -- scripts/development-workflow)
run_test "T-B5_copied_tree_has_no_shared_file" "no" "$(yes_no test -e "$TOOLING/.ai-dev-workflow.yaml")"
REVIEWER_UNDER_TEST="$TOOLING/scripts/development-workflow/local-ai-reviewer.sh"
review --
run_test "T-B5_missing_shared_file_codex" "yes" "$(yes_no rerr_has "$codex_info")"
run_test "T-B5_missing_shared_file_result" "clean" "$(kv RESULT)"
review AI_DEV_WORKFLOW_CONFIG_FILE="$TMP_ROOT/no-such-config.yaml" --
run_test "T-B5_missing_pinned_file_codex" "yes" "$(yes_no rerr_has "$codex_info")"
REVIEWER_UNDER_TEST="$REVIEWER"

# T-B6 to T-B9: the direct-run budget.
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude --
run_test "T-B6_budget_info" "yes" "$(yes_no grep -Fxq "INFO: local AI reviewer $budget_info" "$RERR")"
run_test "T-B6_budget_900" "900" "$(cat "$CLAUDE_REC/timeout" 2>/dev/null || true)"
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude -- --timeout 120
run_test "T-B7_flag_budget" "120" "$(cat "$CLAUDE_REC/timeout" 2>/dev/null || true)"
run_test "T-B7_flag_no_budget_info" "no" "$(yes_no rerr_has "$budget_info")"
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude LOCAL_AI_REVIEWER_TIMEOUT=600 --
run_test "T-B7_env_budget" "600" "$(cat "$CLAUDE_REC/timeout" 2>/dev/null || true)"
run_test "T-B7_env_no_budget_info" "no" "$(yes_no rerr_has "$budget_info")"
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude -- --timeout abc
run_test "T-B8_invalid_flag_exit" "2" "$RRC"
run_test "T-B8_invalid_flag_key" "yes" "$(yes_no rerr_has 'configuration validation error; key=--timeout')"
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude LOCAL_AI_REVIEWER_TIMEOUT=0 --
run_test "T-B8_invalid_env_exit" "2" "$RRC"
run_test "T-B8_invalid_env_key" "yes" "$(yes_no rerr_has 'configuration validation error; key=--timeout')"
run_test "T-B8_invalid_env_claude_not_ran" "no" "$(yes_no ran "$CLAUDE_REC")"
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" --
run_test "T-B9_codex_budget_300" "300" "$(cat "$CODEX_REC/timeout" 2>/dev/null || true)"
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=http --
run_test "T-B9_http_budget_300" "300" "$(cat "$CURL_REC/timeout" 2>/dev/null || true)"
run_test "T-B9_http_result" "clean" "$(kv RESULT)"
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" \
  LOCAL_AI_REVIEWER_COMMAND="'$TOOLS/local-claude-review-command.sh'" --
run_test "T-B9_explicit_claude_budget_300" "300" "$(cat "$CLAUDE_REC/timeout" 2>/dev/null || true)"
run_test "T-B9_explicit_claude_no_budget_info" "no" "$(yes_no rerr_has "$budget_info")"
run_test "T-B9_explicit_claude_no_preset_info" "no" "$(yes_no rerr_has 'defaulted to bundled')"

# T-B10: CLI quota and model-access text on either stream is classified.
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude STANDIN_EXIT=1 \
  STANDIN_STDOUT="You've hit your usage limit. Try again at 5pm." --
run_test "T-B10_quota_stdout" "quota_exhausted" "$(kv REASON)"
run_test "T-B10_quota_stdout_result" "escalate" "$(kv RESULT)"
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude STANDIN_EXIT=1 \
  STANDIN_STDOUT="" STANDIN_STDERR="Claude usage limit reached" --
run_test "T-B10_quota_stderr" "quota_exhausted" "$(kv REASON)"
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude STANDIN_EXIT=1 \
  STANDIN_STDOUT="This account has no model access for the selected model." --
run_test "T-B10_model_access" "missing_model_access" "$(kv REASON)"
run_test "T-B10_model_access_result" "escalate" "$(kv RESULT)"

# T-B11: every preset refusal ends as malformed_output, never a probe reason.
t11_check() {
  run_test "T-B11_$1_result" "escalate" "$(kv RESULT)"
  run_test "T-B11_$1_reason" "malformed_output" "$(kv REASON)"
}
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude \
  LOCAL_CLAUDE_REVIEWER_BIN="$TMP_ROOT/no-such-claude" --
t11_check missing_cli
mkdir -p "$TMP_ROOT/not-a-repo"
printf '# Review contract\n' > "$TMP_ROOT/not-a-repo/REVIEW.md"
rm -rf "$CLAUDE_REC"
RRC=0
( cd "$TMP_ROOT/not-a-repo" && env PATH="$MOCK_BIN:$PATH" AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" \
    LOCAL_AI_REVIEWER_BACKEND=claude "$REVIEWER" 123 owner repo ) >"$ROUT" 2>"$RERR" || RRC=$?
t11_check copy_not_created
run_test "T-B11_copy_not_created_claude_not_ran" "no" "$(yes_no ran "$CLAUDE_REC")"
FX_EMPTY="$TMP_ROOT/fx-empty"
git clone -q "$FX" "$FX_EMPTY"
git -C "$FX_EMPTY" remote set-url origin git@github.com:owner/repo.git
git -C "$FX_EMPTY" update-ref refs/remotes/origin/develop HEAD
FX_SAVED="$FX"
FX="$FX_EMPTY"
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude --
t11_check empty_diff
FX="$FX_SAVED"
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude \
  STANDIN_ACTION='printf planted > planted.txt' --
t11_check modified_copy
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude \
  STANDIN_STDOUT='{"result":"needs_fixes","findings":[{"result":"clean"}]' --
t11_check malformed_e18
run_test "T-B11_malformed_not_clean" "no" "$(yes_no grep -qx 'RESULT=clean' "$ROUT")"

# T-B12: a capacity message is retried and ends as needs_rerun, never Clean.
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude STANDIN_EXIT=1 \
  STANDIN_STDOUT="API Error: overloaded" --
run_test "T-B12_result" "needs_rerun" "$(kv RESULT)"
run_test "T-B12_reason" "provider_overloaded" "$(kv REASON)"

# T-B12b (#2151, capacity_budget_*): capacity retries share one round budget.
# Each attempt gets only the time left, and a backoff that no longer fits ends
# the round as needs_rerun instead of starting another full-budget attempt.
# The stand-in logs every attempt's budget, so these checks read attempt counts
# and budgets instead of wall-clock time, which a loaded runner stretches.
# capacity_budget_fits: attempt k follows backoffs 1..k-1, so its budget plus
# those backoffs must fit in the round budget given as $1.
capacity_budget_fits() {
  awk -v budget="$1" '{ k++; waited += k - 1; if ($1 + waited > budget) bad = 1 }
    END { exit (k == 0 || bad) }' "$CLAUDE_REC/timeouts" 2>/dev/null
}
capacity_attempts() { awk 'END { print NR }' "$CLAUDE_REC/timeouts" 2>/dev/null || echo 0; }
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude STANDIN_EXIT=1 \
  STANDIN_STDOUT="API Error: overloaded" -- --timeout 5
t12_last="$(cat "$CLAUDE_REC/timeout" 2>/dev/null || echo 0)"
run_test "T-B12b_capacity_budget_result" "needs_rerun/provider_overloaded" "$(kv RESULT)/$(kv REASON)"
run_test "T-B12b_capacity_budget_retried" "yes" "$(yes_no test "$(capacity_attempts)" -ge 2)"
run_test "T-B12b_capacity_budget_last_attempt_shrunk" "yes" "$(yes_no test "$t12_last" -lt 5)"
run_test "T-B12b_capacity_budget_within_budget" "yes" "$(yes_no capacity_budget_fits 5)"
# A first attempt that uses half the budget leaves no room for backoff plus
# another attempt, so the round stops after exactly one attempt.
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude STANDIN_EXIT=1 \
  STANDIN_SLEEP=1 STANDIN_STDOUT="API Error: overloaded" -- --timeout 2
run_test "T-B12b_capacity_budget_no_room_result" "needs_rerun/provider_overloaded" "$(kv RESULT)/$(kv REASON)"
run_test "T-B12b_capacity_budget_no_room_stops" "1" "$(capacity_attempts)"
run_test "T-B12b_capacity_budget_no_room_diag" "yes" "$(yes_no rerr_has 'no budget left for another attempt')"

# T-B13: a run past the budget is No verdict yet and leaves no copy behind.
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude STANDIN_SLEEP=30 -- --timeout 3
run_test "T-B13_result" "waiting_on_reviewer" "$(kv RESULT)"
run_test "T-B13_exit" "4" "$RRC"
sleep 3
run_test "T-B13_no_leftover_dir" "0" "$(find "$TMPDIR" -maxdepth 1 -name 'local-claude-review.*' | grep -c . || true)"
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=claude --
run_test "T-B13_following_run_clean" "clean" "$(kv RESULT)"

# T-B14: unknown names give exactly the key diagnostic and never echo values.
review AI_DEV_WORKFLOW_CONFIG_FILE="$NEUTRAL_CFG" LOCAL_AI_REVIEWER_BACKEND=plantedEnvValue123 --
run_test "T-B14_env_reason" "invalid_backend" "$(kv REASON)"
run_test "T-B14_env_line" "yes" "$(yes_no grep -Fxq "$env_error" "$RERR")"
run_test "T-B14_env_value_not_echoed" "no" "$(yes_no grep -q plantedEnvValue123 "$ROUT" "$RERR")"
run_test "T-B14_env_no_preset_ran" "no/no" "$(yes_no ran "$CLAUDE_REC")/$(yes_no ran "$CODEX_REC")"
review AI_DEV_WORKFLOW_CONFIG_FILE="$SHARED_UNKNOWN" --
run_test "T-B14_shared_reason" "invalid_backend" "$(kv REASON)"
run_test "T-B14_shared_line" "yes" "$(yes_no grep -Fxq "$shared_error" "$RERR")"
run_test "T-B14_shared_value_not_echoed" "no" "$(yes_no grep -q plantedSharedValue456 "$ROUT" "$RERR")"
run_test "T-B14_shared_no_preset_ran" "no/no" "$(yes_no ran "$CLAUDE_REC")/$(yes_no ran "$CODEX_REC")"
review AI_DEV_WORKFLOW_CONFIG_FILE="$(shared_backend_cfg sh_upper 'backend: CLAUDE')" --
run_test "T-B14_shared_case_sensitive" "invalid_backend" "$(kv REASON)"

# T-B15: the help text names the backend, the shared key, and the settings.
help_text="$("$REVIEWER" --help 2>&1 || true)"
for t15_needle in claude review.local_ai_reviewer.backend LOCAL_CLAUDE_REVIEWER_BIN \
    LOCAL_CLAUDE_REVIEWER_MODEL LOCAL_CLAUDE_REVIEWER_PROMPT LOCAL_CLAUDE_REVIEWER_STRICT_PROMPT \
    "Backend selection (first match wins)" "then the bundled"; do
  run_test "T-B15_help_names_${t15_needle// /_}" "yes" "$(yes_no grep -Fq -- "$t15_needle" <<< "$help_text")"
done

if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "FAIL: $FAIL_COUNT test(s) failed"
  exit 1
fi

echo "PASS: $PASS_COUNT test(s) passed"

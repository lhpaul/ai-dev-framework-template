#!/usr/bin/env bash
# test-workflow-design-opt-in.sh — workflow_design_opt_in (#2211) returns
# exactly one opt-in outcome from the versioned .ai-dev-workflow.yaml and
# leaves the repository unchanged.
#
# Every case writes fabricated configuration into a fresh mktemp -d
# repository, sources workflow-lib.sh, calls the helper and compares the full
# stdout and exit status. Cases run under the invoking bash and /bin/bash (3.2
# on macOS). No real .ai-dev-workflow.local.* file is read or written.
#
# Usage: bash scripts/development-workflow/tests/test-workflow-design-opt-in.sh
# covers: scripts/development-workflow/workflow-lib.sh
# covers: scripts/development-workflow/workflow-config-resolver.py
# duration: 10

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
LIB="$REPO_ROOT/scripts/development-workflow/workflow-lib.sh"
SCRIPTS_DIR="$REPO_ROOT/scripts/development-workflow"

PASS=0
FAIL=0
SKIP=0
WORK_DIR="$(mktemp -d)"
cleanup() {
  # A mode-000 fixture would block rm -rf; restore permissions first.
  chmod -R u+rwx "$WORK_DIR" 2>/dev/null || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf 'FAIL: %s\n' "$1"; FAIL=$((FAIL + 1)); }
skip() { printf 'SKIP: %s\n' "$1"; SKIP=$((SKIP + 1)); }

SHELLS=()
add_shell() {
  local candidate="$1" existing
  [ -n "$candidate" ] && [ -x "$candidate" ] || return 0
  for existing in ${SHELLS[@]+"${SHELLS[@]}"}; do
    [ "$existing" = "$candidate" ] && return 0
  done
  SHELLS+=("$candidate")
}
add_shell "${BASH:-}"
add_shell /bin/bash

# ── Expected-output builders ────────────────────────────────────────────────

NOT_OPTED_IN=$'DESIGN_OPT_IN=not_opted_in\nDESIGN_OPT_IN_LABEL=Not opted in'
HOME_ACCEPTED='accepted values: knowledge (Knowledge repository), product (Product repository)'
KIND_ACCEPTED='accepted values: design-intent (Design intent), reproduction (Reproduction)'
ROOT_RULE='expected a non-empty relative path that stays inside the repository, or omit root to use the default design/'
CONFIG_RULE='it must be readable UTF-8 YAML whose top level is a mapping'
BLOCK_RULE='expected a mapping with the fields home, kind and optional root'
FALLBACK_PROBLEM='configuration: the opt-in check could not run (python3 or the configuration reader failed); the file may be valid'
VALID=$'design:\n  home: knowledge\n  kind: design-intent\n'

expect_invalid() {
  local out problem
  out=$'DESIGN_OPT_IN=invalid\nDESIGN_OPT_IN_LABEL=Invalid configuration\n'"DESIGN_PROBLEM_COUNT=$#"
  for problem in "$@"; do
    out+=$'\n'"DESIGN_PROBLEM=$problem"
  done
  printf '%s' "$out"
}

# expect_opted <escaped root> <source> <home> <kind>
expect_opted() {
  local home_label kind_label
  case "$3" in knowledge) home_label='Knowledge repository' ;; *) home_label='Product repository' ;; esac
  case "$4" in design-intent) kind_label='Design intent' ;; *) kind_label='Reproduction' ;; esac
  printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n%s' 'DESIGN_OPT_IN=opted_in' 'DESIGN_OPT_IN_LABEL=Opted in' \
    "DESIGN_ROOT=$1" "DESIGN_ROOT_SOURCE=$2" \
    "DESIGN_HOME=$3" "DESIGN_HOME_LABEL=$home_label" \
    "DESIGN_KIND=$4" "DESIGN_KIND_LABEL=$kind_label"
}

config_problem() {
  printf 'configuration: .ai-dev-workflow.yaml exists but could not be read or parsed (%s); %s' "$1" "$CONFIG_RULE"
}

root_problem() {
  printf 'design.root: %s; %s' "$1" "$ROOT_RULE"
}

# ── Fixtures and invocation ─────────────────────────────────────────────────

new_repo() {
  mktemp -d "$WORK_DIR/repo.XXXXXX"
}

# repo_with <content>: a fresh repository whose versioned config is <content>.
repo_with() {
  local repo
  repo="$(new_repo)"
  printf '%s' "$1" >"$repo/.ai-dev-workflow.yaml"
  printf '%s\n' "$repo"
}

OUT=""
RC=0
# call_helper [args...]: runs the helper in a fresh shell; sets OUT and RC.
call_helper() {
  local status=0
  OUT="$("$SHELL_UNDER_TEST" -c 'lib="$1"; shift; source "$lib"; workflow_design_opt_in "$@"' \
    _ "$LIB" "$@")" || status=$?
  RC=$status
}

assert_out() {
  local name="$1" expected="$2" expected_rc="${3:-0}"
  if [ "$RC" = "$expected_rc" ] && [ "$OUT" = "$expected" ]; then
    pass "$name [$SHELL_UNDER_TEST]"
  else
    fail "$name [$SHELL_UNDER_TEST]"
    printf '  expected (rc=%s):\n%s\n  actual (rc=%s):\n%s\n' "$expected_rc" "$expected" "$RC" "$OUT"
  fi
}

# case_config <name> <content> <expected>
case_config() {
  local repo
  repo="$(repo_with "$2")"
  call_helper "$repo"
  assert_out "$1" "$3"
}

with_root() {
  printf 'design:\n  home: knowledge\n  kind: design-intent\n  root: %s\n' "$1"
}

# ── Cases ───────────────────────────────────────────────────────────────────

run_binding_cases() {
  local repo
  # T1: no configuration file.
  repo="$(new_repo)"
  call_helper "$repo"
  assert_out "T1 no configuration file" "$NOT_OPTED_IN"

  # T2: unparseable; the problem never echoes file content.
  case_config "T2 unparseable configuration" $'design:\n  home: [unclosed-secret-text\n' \
    "$(expect_invalid "$(config_problem 'invalid YAML, line 2')")"
  case "$OUT" in
    *unclosed-secret-text*) fail "T2 echoes file content [$SHELL_UNDER_TEST]" ;;
    *) pass "T2 does not echo file content [$SHELL_UNDER_TEST]" ;;
  esac

  case_config "T3 no design key" $'schema_version: 2\ntemplate:\n  is_template: false\n' "$NOT_OPTED_IN"
  case_config "T4 design with no value" $'design:\n' \
    "$(expect_invalid "design: found null (no value); $BLOCK_RULE")"
  case_config "T5 missing home" $'design:\n  kind: design-intent\n' \
    "$(expect_invalid "design.home: absent; $HOME_ACCEPTED")"
  case_config "T6 unknown home" $'design:\n  home: studio\n  kind: design-intent\n' \
    "$(expect_invalid "design.home: found \"studio\"; $HOME_ACCEPTED")"
  case_config "T7 missing kind" $'design:\n  home: knowledge\n' \
    "$(expect_invalid "design.kind: absent; $KIND_ACCEPTED")"
  case_config "T8 unknown kind" $'design:\n  home: knowledge\n  kind: mock\n' \
    "$(expect_invalid "design.kind: found \"mock\"; $KIND_ACCEPTED")"
  case_config "T9 wrong-case value" $'design:\n  home: Knowledge\n  kind: design-intent\n' \
    "$(expect_invalid "design.home: found \"Knowledge\"; $HOME_ACCEPTED")"
  case_config "T10 absolute root" "$(with_root /srv/design)" \
    "$(expect_invalid "$(root_problem 'found "/srv/design", which is an absolute path')")"
  case_config "T11 root outside the repository" "$(with_root ../design)" \
    "$(expect_invalid "$(root_problem 'found "../design", which leaves the repository')")"
  case_config "T12 numeric root" "$(with_root 42)" \
    "$(expect_invalid "$(root_problem 'found a number (42), which is not a string')")"
  case_config "T13 list root" "$(with_root '[design-secret-text]')" \
    "$(expect_invalid "$(root_problem 'found a list, which is not a string')")"
  case "$OUT" in
    *design-secret-text*) fail "T13 echoes list content [$SHELL_UNDER_TEST]" ;;
    *) pass "T13 does not echo list content [$SHELL_UNDER_TEST]" ;;
  esac
  case_config "T14 valid, no root" "$VALID" "$(expect_opted design/ default knowledge design-intent)"
  case_config "T15 valid, custom root" $'design:\n  root: docs/design/\n  home: product\n  kind: reproduction\n' \
    "$(expect_opted docs/design/ configured product reproduction)"
  case_config "T16 valid plus unknown field" $'design:\n  home: knowledge\n  kind: design-intent\n  surfaces: [web]\n' \
    "$(expect_opted design/ default knowledge design-intent)"

  # T17: block only in machine-local configuration.
  repo="$(repo_with $'schema_version: 2\n')"
  printf '%s' "$VALID" >"$repo/.ai-dev-workflow.local.yaml"
  call_helper "$repo"
  assert_out "T17 block only in local configuration" "$NOT_OPTED_IN"
}

run_resolution_cases() {
  local repo form expected_root
  case_config "T-multi several problems" $'design:\n  home: studio\n  root: /srv/design\n' \
    "$(expect_invalid "design.home: found \"studio\"; $HOME_ACCEPTED" \
      "design.kind: absent; $KIND_ACCEPTED" \
      "$(root_problem 'found "/srv/design", which is an absolute path')")"

  case_config "T-null-forms null" $'design: null\n' "$(expect_invalid "design: found null (no value); $BLOCK_RULE")"
  case_config "T-null-forms {}" $'design: {}\n' "$(expect_invalid "design: found an empty mapping; $BLOCK_RULE")"
  case_config "T-null-forms []" $'design: []\n' "$(expect_invalid "design: found an empty list; $BLOCK_RULE")"
  case_config "T-null-forms scalar" $'design: yes\n' "$(expect_invalid "design: found \"yes\"; $BLOCK_RULE")"
  case_config "T-null-forms empty string" $'design: ""\n' "$(expect_invalid "design: found an empty string; $BLOCK_RULE")"

  case_config "T-key-case Home" $'design:\n  Home: knowledge\n  kind: design-intent\n' \
    "$(expect_invalid "design.home: absent; $HOME_ACCEPTED")"
  case_config "T-quoted quotes and comments" $'design:\n  home: "knowledge"\n  kind: \'design-intent\'  # note\n' \
    "$(expect_opted design/ default knowledge design-intent)"
  case_config "T-flow flow mapping" $'design: {home: product, kind: reproduction}\n' \
    "$(expect_opted design/ default product reproduction)"
  case_config "T-padded boundary whitespace" $'design:\n  home: "knowledge "\n  kind: design-intent\n' \
    "$(expect_invalid "design.home: found \"knowledge \"; $HOME_ACCEPTED")"
  case_config "T-numeric home" $'design:\n  home: 7\n  kind: design-intent\n' \
    "$(expect_invalid "design.home: found a number (7); $HOME_ACCEPTED")"

  case_config "T-root-forms null" "$(with_root null)" \
    "$(expect_invalid "$(root_problem 'found null (no value), which is not a string')")"
  case_config "T-root-forms empty string" "$(with_root "''")" \
    "$(expect_invalid "$(root_problem 'found an empty string')")"
  case_config "T-root-forms boolean" "$(with_root true)" \
    "$(expect_invalid "$(root_problem 'found a boolean (true), which is not a string')")"
  case_config "T-root-forms mapping" $'design:\n  home: knowledge\n  kind: design-intent\n  root:\n    path: design\n' \
    "$(expect_invalid "$(root_problem 'found a mapping, which is not a string')")"
  case_config "T-root-forms drive letter" "$(with_root C:/design)" \
    "$(expect_invalid "$(root_problem 'found "C:/design", which is an absolute path')")"
  case_config "T-root-forms backslash absolute" "$(with_root '\design')" \
    "$(expect_invalid "$(root_problem 'found "\\design", which is an absolute path')")"
  case_config "T-root-forms normalises outside" "$(with_root design/../..)" \
    "$(expect_invalid "$(root_problem 'found "design/../..", which leaves the repository')")"
  case_config "T-root-forms backslash outside" "$(with_root '..\design')" \
    "$(expect_invalid "$(root_problem 'found "..\\design", which leaves the repository')")"

  for form in ./design design/../mocks . "'  '" "..design" "design/.."; do
    case "$form" in
      "'  '") expected_root='  ' ;;
      *) expected_root="$form" ;;
    esac
    case_config "T-root-inside $form" "$(with_root "$form")" \
      "$(expect_opted "$expected_root" configured knowledge design-intent)"
  done
  case_config "T-quoted-42 numeric lookalike" "$(with_root '"42"')" \
    "$(expect_opted 42 configured knowledge design-intent)"

  case_config "T-dup duplicate key" $'design:\n  home: knowledge\n  home: product\n  kind: design-intent\n' \
    "$(expect_invalid "$(config_problem 'duplicate mapping key, line 3')")"
  case_config "T-toplevel list" $'- a\n' \
    "$(expect_invalid "$(config_problem 'selected source must be a mapping, line 1')")"
  case_config "T-empty file" '' "$NOT_OPTED_IN"
  case_config "T-empty comment-only" $'# x\n' "$NOT_OPTED_IN"
  case_config "T-nested design under template" $'template:\n  design:\n    home: knowledge\n    kind: design-intent\n' \
    "$NOT_OPTED_IN"
  case_config "T-commented block" $'# design:\n#   home: knowledge\n#   kind: design-intent\n' "$NOT_OPTED_IN"

  repo="$(new_repo)"
  mkdir "$repo/.ai-dev-workflow.yaml"
  call_helper "$repo"
  assert_out "T-dir directory at the path" "$(expect_invalid "$(config_problem 'not a readable regular file')")"

  repo="$(new_repo)"
  ln -s "$repo/missing.yaml" "$repo/.ai-dev-workflow.yaml"
  call_helper "$repo"
  assert_out "T-symlink dangling symlink" "$(expect_invalid "$(config_problem 'not a readable regular file')")"

  # A FIFO is never opened for reading, so the check cannot block on it.
  repo="$(new_repo)"
  mkfifo "$repo/.ai-dev-workflow.yaml"
  call_helper "$repo"
  assert_out "T-fifo FIFO at the path" "$(expect_invalid "$(config_problem 'not a readable regular file')")"

  repo="$(new_repo)"
  printf 'design:\n  home: \377\376\n' >"$repo/.ai-dev-workflow.yaml"
  call_helper "$repo"
  assert_out "T-bytes invalid UTF-8" "$(expect_invalid "$(config_problem 'not valid UTF-8')")"

  if [ "$(id -u)" = "0" ]; then
    skip "T-unreadable: running as root, where mode 000 does not deny reads [$SHELL_UNDER_TEST]"
  else
    repo="$(repo_with "$VALID")"
    chmod 000 "$repo/.ai-dev-workflow.yaml"
    call_helper "$repo"
    chmod 600 "$repo/.ai-dev-workflow.yaml"
    assert_out "T-unreadable permission denied" "$(expect_invalid "$(config_problem 'not a readable regular file')")"
  fi
}

run_output_cases() {
  local repo expected line_count long80 long81 long120
  # T-control: every control is escaped exactly as print_kv_escaped does.
  repo="$(repo_with "$(with_root '"a\tb\nc\rd\x7fe\x85f\\g"')")"
  call_helper "$repo"
  expected="$("$SHELL_UNDER_TEST" -c 'source "$1"; print_kv_escaped DESIGN_ROOT "$2"' \
    _ "$LIB" $'a\tb\nc\rd\x7fe\xc2\x85f\\g')"
  if [ "$expected" != 'DESIGN_ROOT=a\tb\nc\rd\x7fe\u0085f\\g' ]; then
    fail "T-control reference spelling from print_kv_escaped [$SHELL_UNDER_TEST]"
  fi
  assert_out "T-control escapes" "$(expect_opted 'a\tb\nc\rd\x7fe\u0085f\\g' configured knowledge design-intent)"
  line_count="$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')"
  if [ "$line_count" = "8" ]; then
    pass "T-control one physical line per value [$SHELL_UNDER_TEST]"
  else
    fail "T-control one physical line per value: $line_count lines [$SHELL_UNDER_TEST]"
  fi

  # T-truncate: 80 characters whole, 81 cut to 80 plus an ellipsis; the
  # opted-in root is never truncated.
  long80="$(printf 'h%.0s' $(seq 1 80))"
  long81="${long80}X"
  long120="$(printf 'r%.0s' $(seq 1 120))"
  case_config "T-truncate 80 characters" "design:"$'\n'"  home: $long80"$'\n'"  kind: design-intent"$'\n' \
    "$(expect_invalid "design.home: found \"$long80\"; $HOME_ACCEPTED")"
  case_config "T-truncate 81 characters" "design:"$'\n'"  home: $long81"$'\n'"  kind: design-intent"$'\n' \
    "$(expect_invalid "design.home: found \"$long80"$'\xe2\x80\xa6'"\"; $HOME_ACCEPTED")"
  case_config "T-truncate long root printed whole" "$(with_root "$long120")" \
    "$(expect_opted "$long120" configured knowledge design-intent)"

  # T-locale: a non-ASCII root is printed as UTF-8 under the C locale.
  repo="$(repo_with "$(with_root $'dise\xc3\xb1o/')")"
  OUT="$(LC_ALL=C LANG=C "$SHELL_UNDER_TEST" -c 'source "$1"; workflow_design_opt_in "$2"' _ "$LIB" "$repo")" \
    && RC=0 || RC=$?
  assert_out "T-locale non-ASCII root under LC_ALL=C" \
    "$(expect_opted $'dise\xc3\xb1o/' configured knowledge design-intent)"
}

run_source_cases() {
  local repo other
  # T-env: the override variables cannot opt a repository in.
  repo="$(repo_with $'schema_version: 2\n')"
  other="$(repo_with "$VALID")"
  printf '%s' "$VALID" >"$other/.ai-dev-workflow.local.yaml"
  OUT="$(AI_DEV_WORKFLOW_CONFIG_FILE="$other/.ai-dev-workflow.yaml" \
    WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="$other" \
    "$SHELL_UNDER_TEST" -c 'source "$1"; workflow_design_opt_in "$2"' _ "$LIB" "$repo")" && RC=0 || RC=$?
  assert_out "T-env override variables ignored" "$NOT_OPTED_IN"

  # T-local-override: local configuration cannot change the values.
  repo="$(repo_with "$VALID")"
  printf 'design:\n  home: product\n  kind: reproduction\n  root: elsewhere/\n' >"$repo/.ai-dev-workflow.local.yaml"
  call_helper "$repo"
  assert_out "T-local-override versioned values win" "$(expect_opted design/ default knowledge design-intent)"

  # T-path: a repository path with spaces and glob characters.
  repo="$(new_repo)/dir with space [*]"
  mkdir "$repo"
  printf '%s' "$VALID" >"$repo/.ai-dev-workflow.yaml"
  call_helper "$repo"
  assert_out "T-path spaces and glob characters" "$(expect_opted design/ default knowledge design-intent)"

  # T-fresh: every call reads the file again.
  repo="$(repo_with $'schema_version: 2\n')"
  call_helper "$repo"
  assert_out "T-fresh before edit" "$NOT_OPTED_IN"
  printf '%s' "$VALID" >"$repo/.ai-dev-workflow.yaml"
  call_helper "$repo"
  assert_out "T-fresh after edit" "$(expect_opted design/ default knowledge design-intent)"
}

run_fallback_cases() {
  local repo bin
  # T-fallback-absent / -present: no python3 on PATH.
  bin="$(mktemp -d "$WORK_DIR/bin.XXXXXX")"
  ln -s "$(command -v dirname)" "$bin/dirname"
  repo="$(new_repo)"
  OUT="$(PATH="$bin" "$SHELL_UNDER_TEST" -c 'source "$1"; workflow_design_opt_in "$2"' _ "$LIB" "$repo")" \
    && RC=0 || RC=$?
  assert_out "T-fallback-absent no python3, no file" "$NOT_OPTED_IN"
  repo="$(repo_with "$VALID")"
  OUT="$(PATH="$bin" "$SHELL_UNDER_TEST" -c 'source "$1"; workflow_design_opt_in "$2"' _ "$LIB" "$repo")" \
    && RC=0 || RC=$?
  assert_out "T-fallback-present no python3, valid file" "$(expect_invalid "$FALLBACK_PROBLEM")"

  # The program fails (python3 exits non-zero) or prints no outcome line.
  bin="$(mktemp -d "$WORK_DIR/bin.XXXXXX")"
  ln -s "$(command -v dirname)" "$bin/dirname"
  printf '#!/bin/sh\necho DESIGN_OPT_IN=opted_in\nexit 1\n' >"$bin/python3"
  chmod +x "$bin/python3"
  OUT="$(PATH="$bin" "$SHELL_UNDER_TEST" -c 'source "$1"; workflow_design_opt_in "$2"' _ "$LIB" "$repo")" \
    && RC=0 || RC=$?
  assert_out "T-fallback-present program exits non-zero, no partial output" "$(expect_invalid "$FALLBACK_PROBLEM")"
  printf '#!/bin/sh\necho unexpected\n' >"$bin/python3"
  OUT="$(PATH="$bin" "$SHELL_UNDER_TEST" -c 'source "$1"; workflow_design_opt_in "$2"' _ "$LIB" "$repo")" \
    && RC=0 || RC=$?
  assert_out "T-fallback-present program prints no outcome line" "$(expect_invalid "$FALLBACK_PROBLEM")"
  OUT="$(PATH="$bin" "$SHELL_UNDER_TEST" -c 'source "$1"; workflow_design_opt_in "$2"' _ "$LIB" "$(new_repo)")" \
    && RC=0 || RC=$?
  assert_out "T-fallback-absent program prints no outcome line, no file" "$NOT_OPTED_IN"
}

run_badarg_cases() {
  local file
  call_helper ""
  assert_out "T-badarg empty argument" "" 2
  file="$WORK_DIR/not-a-directory"
  : >"$file"
  call_helper "$file"
  assert_out "T-badarg non-directory argument" "" 2
  call_helper "$WORK_DIR/does-not-exist"
  assert_out "T-badarg missing directory" "" 2
  OUT="$("$SHELL_UNDER_TEST" -c 'source "$1"; workflow_repo_root() { return 1; }; workflow_design_opt_in' \
    _ "$LIB")" && RC=0 || RC=$?
  assert_out "T-badarg no argument, repo root unresolved" "" 2
}

# T-unchanged (AC14): every AC12 case leaves its repository unchanged, and no
# bytecode cache appears next to the resolver.
snapshot_tree() {
  local root="$1" entry
  (
    cd "$root"
    find . -print | LC_ALL=C sort | while IFS= read -r entry; do
      if [ -f "$entry" ] && [ ! -L "$entry" ]; then
        printf '%s %s\n' "$entry" "$(cksum <"$entry")"
      else
        printf '%s\n' "$entry"
      fi
    done
  )
}

snapshot_cache() {
  find "$SCRIPTS_DIR" -path '*__pycache__*' -name 'workflow*config*resolver*' -print 2>/dev/null \
    | LC_ALL=C sort | while IFS= read -r entry; do
      printf '%s %s\n' "$entry" "$(cksum <"$entry")"
    done
}

run_unchanged_case() {
  local root content before after cache_after index=0 repo
  root="$(mktemp -d "$WORK_DIR/unchanged.XXXXXX")"
  for content in \
    $'design:\n  home: [unclosed\n' $'schema_version: 2\n' $'design:\n' \
    $'design:\n  kind: design-intent\n' $'design:\n  home: studio\n  kind: design-intent\n' \
    $'design:\n  home: knowledge\n' $'design:\n  home: knowledge\n  kind: mock\n' \
    $'design:\n  home: Knowledge\n  kind: design-intent\n' "$(with_root /srv/design)" \
    "$(with_root ../design)" "$(with_root 42)" "$(with_root '[design]')" "$VALID" \
    $'design:\n  root: docs/design/\n  home: product\n  kind: reproduction\n' \
    $'design:\n  home: knowledge\n  kind: design-intent\n  surfaces: [web]\n'; do
    index=$((index + 1))
    mkdir "$root/case$index"
    printf '%s' "$content" >"$root/case$index/.ai-dev-workflow.yaml"
  done
  mkdir "$root/no-config" "$root/local-only"
  printf 'schema_version: 2\n' >"$root/local-only/.ai-dev-workflow.yaml"
  printf '%s' "$VALID" >"$root/local-only/.ai-dev-workflow.local.yaml"

  before="$(snapshot_tree "$root")"
  for repo in "$root"/*; do
    call_helper "$repo"
  done
  after="$(snapshot_tree "$root")"
  cache_after="$(snapshot_cache)"
  if [ "$before" = "$after" ] && [ -n "$before" ]; then
    pass "T-unchanged repositories unchanged [$SHELL_UNDER_TEST]"
  else
    fail "T-unchanged repositories unchanged [$SHELL_UNDER_TEST]"
    diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") || true
  fi
  if [ "$CACHE_BEFORE" = "$cache_after" ]; then
    pass "T-unchanged no resolver bytecode cache written [$SHELL_UNDER_TEST]"
  else
    fail "T-unchanged no resolver bytecode cache written [$SHELL_UNDER_TEST]"
  fi
}

# T-template (AC11): only meaningful in the template repository itself.
run_template_case() {
  local is_template
  is_template="$("$SHELL_UNDER_TEST" -c 'source "$1"; workflow_template_is_template "$2"' \
    _ "$LIB" "$REPO_ROOT/.ai-dev-workflow.yaml")"
  if [ "$is_template" != "true" ]; then
    skip "T-template: not the template repository (template.is_template is not true) [$SHELL_UNDER_TEST]"
    return
  fi
  OUT="$("$SHELL_UNDER_TEST" -c 'source "$1"; workflow_design_opt_in' _ "$LIB")" && RC=0 || RC=$?
  assert_out "T-template template repository is not opted in" "$NOT_OPTED_IN"
}

# Taken before the first helper call, so a cache written by any call shows.
CACHE_BEFORE="$(snapshot_cache)"

for SHELL_UNDER_TEST in ${SHELLS[@]+"${SHELLS[@]}"}; do
  printf '== shell: %s (%s)\n' "$SHELL_UNDER_TEST" "$("$SHELL_UNDER_TEST" -c 'printf %s "$BASH_VERSION"')"
  run_binding_cases
  run_resolution_cases
  run_output_cases
  run_source_cases
  run_fallback_cases
  run_badarg_cases
  run_unchanged_case
  run_template_case
done

printf '\nResults: %d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]

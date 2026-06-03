#!/usr/bin/env bash
# test-install-codex-skills.sh — Unit tests for install-codex-skills.sh.
#
# Exercises the highest-risk installer behavior:
#   1. Three-pass ordering: repo skills -> legacy canonical -> legacy aliases
#   2. Skip rules: existing non-symlink destinations are not overwritten
#   3. Source-directory validation: missing .agents/skills fails clearly
#
# Usage: bash scripts/development-workflow/tests/test-install-codex-skills.sh
#
# Exit code: 0 if all tests pass, 1 if any test fails.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir)"
case "$GIT_COMMON_DIR" in
  /*) REPO_ROOT="$(cd "$GIT_COMMON_DIR/.." && pwd -P)" ;;
  *)  REPO_ROOT="$(cd "$SCRIPT_DIR/$GIT_COMMON_DIR/.." && pwd -P)" ;;
esac
INSTALLER="$REPO_ROOT/scripts/development-workflow/install-codex-skills.sh"

TMP_ROOT="$(mktemp -d)"

_harness_exit() {
  local status=$?
  rm -rf "$TMP_ROOT"
  case "$status" in
    141) exit 0 ;;
    *)   exit "$status" ;;
  esac
}
trap _harness_exit EXIT

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
  else
    echo "FAIL: $name — expected '${expected}', got '${actual}'"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  fi
}

make_repo_fixture() {
  local fixture="$1"

  mkdir -p "$fixture/scripts/development-workflow" \
    "$fixture/.agents/skills/run-work" \
    "$fixture/.agents/skills/workflow-orchestrator" \
    "$fixture/.codex/skills/workflow-orchestrator"

  cp "$INSTALLER" "$fixture/scripts/development-workflow/install-codex-skills.sh"
  printf '%s\n' 'repo-run-work' > "$fixture/.agents/skills/run-work/SKILL.md"
  printf '%s\n' 'repo-workflow' > "$fixture/.agents/skills/workflow-orchestrator/SKILL.md"
  printf '%s\n' 'legacy-workflow' > "$fixture/.codex/skills/workflow-orchestrator/SKILL.md"
}

echo ""
echo "=== Area 1: three-pass ordering and destination coverage ==="

fixture="$TMP_ROOT/fixture-order"
agents_home="$TMP_ROOT/agents-home-order"
codex_home="$TMP_ROOT/codex-home-order"
output_file="$TMP_ROOT/order.out"
make_repo_fixture "$fixture"

AGENTS_HOME="$agents_home" CODEX_HOME="$codex_home" \
  bash "$fixture/scripts/development-workflow/install-codex-skills.sh" > "$output_file"

run_test "primary_run_work_symlink" "yes" "$(
  [ -L "$agents_home/skills/run-work" ] && echo yes || echo no
)"
run_test "primary_workflow_symlink" "yes" "$(
  [ -L "$agents_home/skills/workflow-orchestrator" ] && echo yes || echo no
)"
run_test "legacy_run_work_alias_symlink" "yes" "$(
  [ -L "$codex_home/skills/run-work" ] && echo yes || echo no
)"
run_test "legacy_workflow_canonical_symlink" "yes" "$(
  [ -L "$codex_home/skills/workflow-orchestrator" ] && echo yes || echo no
)"

order_actual="$(
  awk '
    /\(repo\)/ && repo == 0 { repo = NR }
    /\(legacy canonical\)/ && legacy == 0 { legacy = NR }
    /\(legacy aliases\)/ && alias == 0 { alias = NR }
    END {
      if (repo > 0 && legacy > repo && alias > legacy) print "ordered";
      else print "wrong";
    }
  ' "$output_file"
)"
run_test "three_pass_order" "ordered" "$order_actual"

echo ""
echo "=== Area 2: skip existing non-symlink destinations ==="

fixture="$TMP_ROOT/fixture-skip"
agents_home="$TMP_ROOT/agents-home-skip"
codex_home="$TMP_ROOT/codex-home-skip"
output_file="$TMP_ROOT/skip.out"
make_repo_fixture "$fixture"
mkdir -p "$agents_home/skills/run-work"
printf '%s\n' 'keep-me' > "$agents_home/skills/run-work/SKILL.md"

AGENTS_HOME="$agents_home" CODEX_HOME="$codex_home" \
  bash "$fixture/scripts/development-workflow/install-codex-skills.sh" > "$output_file"

run_test "non_symlink_destination_preserved" "keep-me" "$(
  cat "$agents_home/skills/run-work/SKILL.md"
)"
run_test "skip_message_emitted" "yes" "$(
  grep -q 'Skipping run-work:' "$output_file" && echo yes || echo no
)"

echo ""
echo "=== Area 3: missing repo skill source fails clearly ==="

fixture="$TMP_ROOT/fixture-missing-source"
agents_home="$TMP_ROOT/agents-home-missing"
codex_home="$TMP_ROOT/codex-home-missing"
stderr_file="$TMP_ROOT/missing.err"
mkdir -p "$fixture/scripts/development-workflow"
cp "$INSTALLER" "$fixture/scripts/development-workflow/install-codex-skills.sh"

set +e
AGENTS_HOME="$agents_home" CODEX_HOME="$codex_home" \
  bash "$fixture/scripts/development-workflow/install-codex-skills.sh" \
  > /dev/null 2> "$stderr_file"
missing_exit=$?
set -e

run_test "missing_source_exit_code" "1" "$missing_exit"
run_test "missing_source_error_message" "yes" "$(
  grep -q 'Skill source directory not found:' "$stderr_file" && echo yes || echo no
)"

echo ""
echo "=== Area 4: real repo command alias coverage ==="

agents_home="$TMP_ROOT/agents-home-real"
codex_home="$TMP_ROOT/codex-home-real"
output_file="$TMP_ROOT/real.out"

AGENTS_HOME="$agents_home" CODEX_HOME="$codex_home" \
  bash "$INSTALLER" > "$output_file"

while IFS= read -r alias_name; do
  [ -n "$alias_name" ] || continue

  run_test "primary_alias_${alias_name}" "yes" "$(
    [ -e "$agents_home/skills/$alias_name" ] && echo yes || echo no
  )"
  run_test "legacy_alias_${alias_name}" "yes" "$(
    [ -e "$codex_home/skills/$alias_name" ] && echo yes || echo no
  )"
done <<'ALIASES'
add-backlog-item
batch-merge
code-review
graduate-development
post-merge-cleanup
prepare-release
retrospective
run-item-work
run-reviewer-loop
run-work
sync-template
ALIASES

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi

#!/usr/bin/env bash
# test-protocol-02-portable-parser-guidance.sh - Protocol 02 portability regression coverage.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
PROTOCOL="$REPO_ROOT/docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md"
SYNC_COMMAND="$REPO_ROOT/.claude/commands/sync-template.md"
OBSOLETE_PATH="docs/specs/developments/20260420120000_201-tech-lead-parser-regex-plan-requirements/1_201-tech-lead-parser-regex-plan-requirements_specs.md"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [ "$expected" = "$actual" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

contains() {
  local needle="$1"
  local file="$2"

  if grep -Fq -- "$needle" "$file"; then
    printf 'yes\n'
  else
    printf 'no\n'
  fi
}

run_test "obsolete_historical_reference_removed" "no" "$(contains "$OBSOLETE_PATH" "$PROTOCOL")"
run_test "parser_risk_classification_retained" "yes" "$(contains 'Classification (parser-risk)' "$PROTOCOL")"
run_test "edge_case_enumeration_retained" "yes" "$(contains 'Edge-case enumeration' "$PROTOCOL")"
run_test "automated_unit_tests_retained" "yes" "$(contains 'Mandatory when parser-risk — Unit tests' "$PROTOCOL")"
run_test "recognized_directives_retained" "yes" "$(contains 'Which directives are recognized' "$PROTOCOL")"
run_test "directive_placement_retained" "yes" "$(contains 'Where directives can appear' "$PROTOCOL")"
run_test "multiple_suppressions_retained" "yes" "$(contains 'How multiple suppressions on one line are interpreted' "$PROTOCOL")"
run_test "optional_history_is_non_blocking" "yes" "$(contains 'must never block plan authoring or sync' "$PROTOCOL")"

RECEIVING_REPO="$TMP_ROOT/receiving-repository"
mkdir -p "$RECEIVING_REPO/docs/workflow/development-workflow/protocols"
cp "$PROTOCOL" "$RECEIVING_REPO/docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md"
RECEIVING_PROTOCOL="$RECEIVING_REPO/docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md"

run_test "receiving_repo_needs_no_obsolete_historical_fixture" "no" "$(contains "$OBSOLETE_PATH" "$RECEIVING_PROTOCOL")"
run_test "receiving_repo_parser_guidance_actionable" "yes" "$(contains 'Conditional — Suppression semantics' "$RECEIVING_PROTOCOL")"
run_test "sync_command_keeps_missing_path_guard" "yes" "$(contains 'path verification' "$SYNC_COMMAND")"

echo ""
echo "${PASS_COUNT} passed, ${FAIL_COUNT} failed"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi

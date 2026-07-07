#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/development-workflow/check-tracker-merge-mapping.sh"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

run_with_workflow() {
  local workflow_file="$1"
  WORKFLOW_FILE_OVERRIDE="$workflow_file" bash "$SCRIPT"
}

missing_output="$(run_with_workflow "$TMP_DIR/missing-update-tracker-on-merge.yml")" \
  || fail "missing workflow should be skipped successfully"
printf '%s\n' "$missing_output" | grep -q '^SKIP: workflow file not found:' \
  || fail "missing workflow output should explain the skip"
printf '%s\n' "$missing_output" | grep -q 'Non-GitHub tracker providers intentionally omit update-tracker-on-merge.yml' \
  || fail "missing workflow output should identify non-GitHub tracker providers"

valid_workflow="$TMP_DIR/update-tracker-on-merge.yml"
touch "$valid_workflow"
cat > "$valid_workflow" <<'YAML'
name: Update tracker on merge

on:
  pull_request:
    types: [closed]

jobs:
  update-tracker:
    runs-on: ubuntu-latest
    steps:
      - name: Detect branch type
        run: |
          if [[ "$BRANCH" == spec/* ]]; then
            TARGET_STATUS="Spec Ready"
          elif [[ "$BRANCH" == implementation-plan/* ]]; then
            TARGET_STATUS="Plan Ready"
          elif [[ "$BRANCH" == feature/* || "$BRANCH" == fix/* || "$BRANCH" == refactor/* || "$BRANCH" == hotfix/* ]]; then
            TARGET_STATUS="Merged"
          fi
YAML

valid_output="$(run_with_workflow "$valid_workflow")" \
  || fail "valid workflow mappings should pass"
printf '%s\n' "$valid_output" | grep -q 'All 6 mappings correct\.' \
  || fail "valid workflow output should confirm all mappings"

printf 'check tracker merge mapping tests passed\n'

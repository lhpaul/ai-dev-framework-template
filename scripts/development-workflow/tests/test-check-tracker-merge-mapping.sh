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
  local config_file="${2:-}"
  if [ -n "$config_file" ]; then
    WORKFLOW_FILE_OVERRIDE="$workflow_file" AI_DEV_WORKFLOW_CONFIG_FILE="$config_file" bash "$SCRIPT"
  else
    WORKFLOW_FILE_OVERRIDE="$workflow_file" bash "$SCRIPT"
  fi
}

linear_config="$TMP_DIR/linear.yaml"
cat > "$linear_config" <<'YAML'
schema_version: 2
issue_tracker:
  provider: linear
YAML

missing_output="$(run_with_workflow "$TMP_DIR/missing-update-tracker-on-merge.yml" "$linear_config")" \
  || fail "missing workflow should be skipped successfully for non-GitHub providers"
printf '%s\n' "$missing_output" | grep -q '^SKIP: workflow file not found:' \
  || fail "missing workflow output should explain the skip"
printf '%s\n' "$missing_output" | grep -q 'Non-GitHub tracker providers intentionally omit update-tracker-on-merge.yml' \
  || fail "missing workflow output should identify non-GitHub tracker providers"

github_config="$TMP_DIR/github-projects.yaml"
cat > "$github_config" <<'YAML'
schema_version: 2
issue_tracker:
  provider: github_projects
YAML

github_missing_exit=0
github_missing_output="$(run_with_workflow "$TMP_DIR/missing-update-tracker-on-merge.yml" "$github_config" 2>&1)" \
  || github_missing_exit=$?
[ "$github_missing_exit" -eq 1 ] \
  || fail "missing workflow should fail closed for GitHub-based tracker providers"
printf '%s\n' "$github_missing_output" | grep -q "GitHub-based tracker provider 'github_projects' requires update-tracker-on-merge.yml" \
  || fail "missing GitHub workflow output should explain the required workflow"

github_hyphen_config="$TMP_DIR/github-projects-hyphen.yaml"
cat > "$github_hyphen_config" <<'YAML'
schema_version: 2
issue_tracker:
  provider: github-projects
YAML

github_hyphen_missing_exit=0
github_hyphen_missing_output="$(run_with_workflow "$TMP_DIR/missing-update-tracker-on-merge.yml" "$github_hyphen_config" 2>&1)" \
  || github_hyphen_missing_exit=$?
[ "$github_hyphen_missing_exit" -eq 1 ] \
  || fail "missing workflow should fail closed for hyphenated GitHub tracker providers"
printf '%s\n' "$github_hyphen_missing_output" | grep -q "GitHub-based tracker provider 'github_projects' requires update-tracker-on-merge.yml" \
  || fail "hyphenated GitHub workflow output should identify the normalized provider"

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

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

permissions:
  contents: read
  pull-requests: read
  issues: write

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
          elif [[ "$BRANCH" == develop-* ]]; then
            BRANCH_TYPE="graduation"
          fi
      - name: Checkout repository for graduation closeout
        uses: actions/checkout@93cb6efe18208431cddfb8368fd83d5badbf9bfd  # v5
      - name: Run graduation closeout fallback
        run: ./scripts/development-workflow/graduation-closeout-from-merged-pr.sh --graduation-pr 1
YAML

valid_output="$(run_with_workflow "$valid_workflow")" \
  || fail "valid workflow mappings should pass"
printf '%s\n' "$valid_output" | grep -q 'All 6 mappings correct (+ graduation closeout fallback)\.' \
  || fail "valid workflow output should confirm all mappings and graduation fallback"
printf '%s\n' "$valid_output" | grep -q "OK: branch 'develop-\*' → graduation closeout fallback" \
  || fail "valid workflow output should acknowledge graduation closeout fallback"
printf '%s\n' "$valid_output" | grep -q 'OK: actions/checkout present with contents: read' \
  || fail "valid workflow output should confirm contents: read for checkout"

missing_contents_workflow="$TMP_DIR/update-tracker-missing-contents.yml"
cat > "$missing_contents_workflow" <<'YAML'
name: Update tracker on merge

on:
  pull_request:
    types: [closed]

permissions:
  pull-requests: read
  issues: write

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
          elif [[ "$BRANCH" == develop-* ]]; then
            BRANCH_TYPE="graduation"
          fi
      - name: Checkout repository for graduation closeout
        uses: actions/checkout@93cb6efe18208431cddfb8368fd83d5badbf9bfd  # v5
      - name: Run graduation closeout fallback
        run: ./scripts/development-workflow/graduation-closeout-from-merged-pr.sh --graduation-pr 1
YAML

missing_contents_exit=0
missing_contents_output="$(run_with_workflow "$missing_contents_workflow" 2>&1)" \
  || missing_contents_exit=$?
[ "$missing_contents_exit" -eq 1 ] \
  || fail "workflow with checkout but no contents: read should fail"
printf '%s\n' "$missing_contents_output" | grep -q 'permissions lack contents: read' \
  || fail "missing contents: read should explain the checkout permission requirement"

missing_graduation_workflow="$TMP_DIR/update-tracker-missing-graduation.yml"
cat > "$missing_graduation_workflow" <<'YAML'
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

missing_graduation_exit=0
missing_graduation_output="$(run_with_workflow "$missing_graduation_workflow" 2>&1)" \
  || missing_graduation_exit=$?
[ "$missing_graduation_exit" -eq 1 ] \
  || fail "workflow without graduation fallback should fail"
printf '%s\n' "$missing_graduation_output" | grep -q 'expected graduation closeout fallback wiring' \
  || fail "missing graduation fallback should explain the required wiring"

# ---------------------------------------------------------------------------
# Tracker-configuration gate (issue #1715)
#
# Planted-violation proof, both directions: the check must FAIL when a step
# consuming secrets.GH_PROJECT_TOKEN is not gated on the configuration step,
# and PASS once the gate is restored.
# ---------------------------------------------------------------------------
write_gate_workflow() {
  # $1 = destination, $2 = "gated" | "ungated" | "no-gate-step" | "no-token"
  local dest="$1" variant="$2"
  local gate_if="" gate_step="" token_env="          GH_TOKEN: \${{ secrets.GH_PROJECT_TOKEN }}"

  [ "$variant" = "ungated" ] || gate_if="          steps.config.outputs.configured == 'true' &&"
  [ "$variant" = "no-token" ] && token_env="          GH_TOKEN: \${{ secrets.GITHUB_TOKEN }}"

  if [ "$variant" != "no-gate-step" ]; then
    gate_step="      - name: Check tracker configuration
        id: config
        env:
          PROJECT_TOKEN: \${{ secrets.GH_PROJECT_TOKEN }}
        run: |
          if [ -n \"\${PROJECT_TOKEN:-}\" ]; then
            echo \"configured=true\" >> \"\$GITHUB_OUTPUT\"
          else
            echo \"configured=false\" >> \"\$GITHUB_OUTPUT\"
          fi"
    [ "$variant" = "no-token" ] && gate_step="${gate_step//secrets.GH_PROJECT_TOKEN/secrets.GITHUB_TOKEN}"
  fi

  cat > "$dest" <<YAML
name: Update tracker on merge

on:
  pull_request:
    types: [closed]

permissions:
  contents: read
  pull-requests: read
  issues: write

jobs:
  update-tracker:
    runs-on: ubuntu-latest
    steps:
      - name: Detect branch type
        run: |
          if [[ "\$BRANCH" == spec/* ]]; then
            TARGET_STATUS="Spec Ready"
          elif [[ "\$BRANCH" == implementation-plan/* ]]; then
            TARGET_STATUS="Plan Ready"
          elif [[ "\$BRANCH" == feature/* || "\$BRANCH" == fix/* || "\$BRANCH" == refactor/* || "\$BRANCH" == hotfix/* ]]; then
            TARGET_STATUS="Merged"
          elif [[ "\$BRANCH" == develop-* ]]; then
            BRANCH_TYPE="graduation"
          fi
${gate_step}
      - name: Checkout repository for graduation closeout
        uses: actions/checkout@93cb6efe18208431cddfb8368fd83d5badbf9bfd  # v5
      - name: Run graduation closeout fallback
        if: >
${gate_if}
          true
        env:
${token_env}
        run: ./scripts/development-workflow/graduation-closeout-from-merged-pr.sh --graduation-pr 1
YAML
}

# Direction 1 — gate present: the check passes.
gated_workflow="$TMP_DIR/update-tracker-gated.yml"
write_gate_workflow "$gated_workflow" gated
gated_output="$(run_with_workflow "$gated_workflow")" \
  || fail "workflow with the configuration gate wired should pass"
printf '%s\n' "$gated_output" | grep -q 'OK: tracker-configuration gate step is present' \
  || fail "gated workflow output should confirm the gate step"
printf '%s\n' "$gated_output" | grep -q 'OK: every step consuming GH_PROJECT_TOKEN is gated on the configuration check' \
  || fail "gated workflow output should confirm every token consumer is gated"

# Direction 2 — plant the violation by removing the gate from the consuming
# step: the check must fail, and must name the offending step.
ungated_workflow="$TMP_DIR/update-tracker-ungated.yml"
write_gate_workflow "$ungated_workflow" ungated
ungated_exit=0
ungated_output="$(run_with_workflow "$ungated_workflow" 2>&1)" || ungated_exit=$?
[ "$ungated_exit" -eq 1 ] \
  || fail "workflow with an ungated GH_PROJECT_TOKEN consumer should fail"
printf '%s\n' "$ungated_output" | grep -q "step 'Run graduation closeout fallback' consumes secrets.GH_PROJECT_TOKEN without gating" \
  || fail "ungated workflow output should name the offending step"

# Direction 2b — plant the violation by deleting the gate step entirely while
# leaving the `if:` conditions in place.
no_gate_workflow="$TMP_DIR/update-tracker-no-gate-step.yml"
write_gate_workflow "$no_gate_workflow" no-gate-step
no_gate_exit=0
no_gate_output="$(run_with_workflow "$no_gate_workflow" 2>&1)" || no_gate_exit=$?
[ "$no_gate_exit" -eq 1 ] \
  || fail "workflow using GH_PROJECT_TOKEN without a gate step should fail"
printf '%s\n' "$no_gate_output" | grep -q "no 'id: config' gate step emitting configured=true/false" \
  || fail "missing gate step should explain the required gate"

# Fail-closed check: a workflow that never references the secret reports the
# gate as not applicable EXPLICITLY, rather than passing silently.
no_token_workflow="$TMP_DIR/update-tracker-no-token.yml"
write_gate_workflow "$no_token_workflow" no-token
no_token_output="$(run_with_workflow "$no_token_workflow")" \
  || fail "workflow without GH_PROJECT_TOKEN should still pass"
printf '%s\n' "$no_token_output" | grep -q 'configuration gate not applicable' \
  || fail "workflow without GH_PROJECT_TOKEN should say the gate is not applicable"

printf 'check tracker merge mapping tests passed\n'

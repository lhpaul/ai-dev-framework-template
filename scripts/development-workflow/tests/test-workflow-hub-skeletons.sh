#!/usr/bin/env bash
# test-workflow-hub-skeletons.sh - workflow hub skeleton validation tests.
#
# Usage: bash scripts/development-workflow/tests/test-workflow-hub-skeletons.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir)"
case "$GIT_COMMON_DIR" in
  /*) REPO_ROOT="$(cd "$GIT_COMMON_DIR/.." && pwd -P)" ;;
  *)  REPO_ROOT="$(cd "$SCRIPT_DIR/$GIT_COMMON_DIR/.." && pwd -P)" ;;
esac

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
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_contains() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if grep -Fq -- "$expected" <<< "$actual"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected output to contain '${expected}'"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_fails_contains() {
  local name="$1"
  local expected="$2"
  shift 2
  local output=""
  local status=0

  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  if [ "$status" -ne 0 ] && grep -Fq -- "$expected" <<< "$output"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected failure containing '${expected}'"
    printf 'Status: %s\nOutput:\n%s\n' "$status" "$output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_passes() {
  local name="$1"
  shift
  local output=""
  local status=0

  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  if [ "$status" -eq 0 ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected success"
    printf 'Status: %s\nOutput:\n%s\n' "$status" "$output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

validate_skeleton_manifest() {
  local manifest_path="$1"
  local repo_root="$2"
  python3 "$REPO_ROOT/scripts/development-workflow/validate-workflow-hub-skeletons.py" \
    --repo-root "$repo_root" \
    --skeleton-manifest "$manifest_path" \
    --skip-sync-manifest
}

echo ""
echo "=== Area 1: real skeleton files ==="

run_test "workflow_hub_readme_exists" "yes" "$(
  [ -f "$REPO_ROOT/template/workflow-hub/README.md" ] && echo yes || echo no
)"
run_test "workflow_hub_manifest_exists" "yes" "$(
  [ -f "$REPO_ROOT/template/workflow-hub/skeleton-manifest.yaml" ] && echo yes || echo no
)"
run_test "product_repo_readme_exists" "yes" "$(
  [ -f "$REPO_ROOT/template/product-repo-injection/README.md" ] && echo yes || echo no
)"
run_test "product_repo_manifest_exists" "yes" "$(
  [ -f "$REPO_ROOT/template/product-repo-injection/skeleton-manifest.yaml" ] && echo yes || echo no
)"

run_passes \
  "real_skeleton_and_sync_manifests_valid" \
  python3 "$REPO_ROOT/scripts/development-workflow/validate-workflow-hub-skeletons.py" \
  --repo-root "$REPO_ROOT"

private_detail_hits=""
set +e
private_detail_hits="$(
  grep -RInE 'Leasity|RADAR|kids-safety|baumsystem|lhpaul/' \
    "$REPO_ROOT/template/workflow-hub" \
    "$REPO_ROOT/template/product-repo-injection"
)"
private_detail_status=$?
set -e
if [ "$private_detail_status" -ne 0 ] && [ "$private_detail_status" -ne 1 ]; then
  echo "FAIL: skeleton_private_detail_scan - grep failed with exit code $private_detail_status"
  FAIL_COUNT=$((FAIL_COUNT + 1))
fi
run_test "skeleton_private_detail_scan" "" "$private_detail_hits"

echo ""
echo "=== Area 2: sync manifest mode scopes ==="

run_passes \
  "sync_manifest_semantic_validation" \
  python3 "$REPO_ROOT/scripts/development-workflow/validate-workflow-hub-skeletons.py" \
  --repo-root "$REPO_ROOT" \
  --sync-manifest "$REPO_ROOT/sync-manifest.yaml"

echo ""
echo "=== Area 3: fixture validation edge cases ==="

fixture_root="$TMP_ROOT/fixture repo with spaces"
mkdir -p "$fixture_root"
printf '%s\n' '# Agent guidance' > "$fixture_root/AGENTS.md"

single_entry_manifest="$TMP_ROOT/single-entry.yaml"
cat > "$single_entry_manifest" <<'YAML'
schema_version: 1
skeleton_role: product_repo
mode_scope: product_repo_injection
entries:
  - path: AGENTS.md
    mode_scope: product_repo_injection
YAML
run_passes "single_entry_manifest_with_spaced_repo_path" validate_skeleton_manifest "$single_entry_manifest" "$fixture_root"

empty_manifest="$TMP_ROOT/empty.yaml"
: > "$empty_manifest"
run_fails_contains "empty_manifest_fails" "manifest is empty" validate_skeleton_manifest "$empty_manifest" "$fixture_root"

whitespace_manifest="$TMP_ROOT/whitespace.yaml"
printf ' \n  \n' > "$whitespace_manifest"
run_fails_contains "whitespace_manifest_fails" "manifest is empty" validate_skeleton_manifest "$whitespace_manifest" "$fixture_root"

missing_path_manifest="$TMP_ROOT/missing-path.yaml"
cat > "$missing_path_manifest" <<'YAML'
schema_version: 1
skeleton_role: workflow_hub
mode_scope: hub_only
entries:
  - path: missing/file.md
    mode_scope: hub_only
YAML
run_fails_contains "missing_source_path_fails" "missing source path" validate_skeleton_manifest "$missing_path_manifest" "$fixture_root"

generated_path_manifest="$TMP_ROOT/generated-path.yaml"
cat > "$generated_path_manifest" <<'YAML'
schema_version: 1
skeleton_role: workflow_hub
mode_scope: hub_only
entries:
  - path: generated/file.md
    mode_scope: hub_only
    generated_example: true
YAML
run_passes "generated_example_missing_path_passes" validate_skeleton_manifest "$generated_path_manifest" "$fixture_root"

forbidden_specs_manifest="$TMP_ROOT/forbidden-specs.yaml"
cat > "$forbidden_specs_manifest" <<'YAML'
schema_version: 1
skeleton_role: product_repo
mode_scope: product_repo_injection
entries:
  - path: docs/specs/developments/example/1_example_specs.md
    mode_scope: product_repo_injection
    generated_example: true
YAML
run_fails_contains "product_repo_specs_forbidden" "hub-owned artifact" validate_skeleton_manifest "$forbidden_specs_manifest" "$fixture_root"

forbidden_plan_manifest="$TMP_ROOT/forbidden-plan.yaml"
cat > "$forbidden_plan_manifest" <<'YAML'
schema_version: 1
skeleton_role: product_repo
mode_scope: product_repo_injection
entries:
  - path: docs/example/2_example_implementation-plan.md
    mode_scope: product_repo_injection
    generated_example: true
YAML
run_fails_contains "product_repo_plan_forbidden" "hub-owned artifact" validate_skeleton_manifest "$forbidden_plan_manifest" "$fixture_root"

required_product_artifact_manifest="$TMP_ROOT/required-product-artifact.yaml"
cat > "$required_product_artifact_manifest" <<'YAML'
schema_version: 1
skeleton_role: product_repo
mode_scope: product_repo_injection
entries:
  - path: docs/specs/developments/example/1_example_specs.md
    mode_scope: product_repo_injection
    generated_example: true
    required_for_product_repo: true
YAML
run_passes "required_product_repo_artifact_passes" validate_skeleton_manifest "$required_product_artifact_manifest" "$fixture_root"

required_non_product_artifact_manifest="$TMP_ROOT/required-non-product-artifact.yaml"
cat > "$required_non_product_artifact_manifest" <<'YAML'
schema_version: 1
skeleton_role: workflow_hub
mode_scope: hub_only
entries:
  - path: docs/specs/developments/example/1_example_specs.md
    mode_scope: hub_only
    generated_example: true
    required_for_product_repo: true
YAML
run_fails_contains "required_product_repo_flag_rejected_for_hub" "only valid for product_repo" validate_skeleton_manifest "$required_non_product_artifact_manifest" "$fixture_root"

unknown_scope_manifest="$TMP_ROOT/unknown-scope.yaml"
cat > "$unknown_scope_manifest" <<'YAML'
schema_version: 1
skeleton_role: product_repo
mode_scope: product_repo_injection
entries:
  - path: AGENTS.md
    mode_scope: unknown_scope
YAML
run_fails_contains "unknown_mode_scope_fails" "unknown mode_scope" validate_skeleton_manifest "$unknown_scope_manifest" "$fixture_root"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi

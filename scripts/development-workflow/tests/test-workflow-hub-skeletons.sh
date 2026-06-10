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
  python3 - "$REPO_ROOT" "$manifest_path" "$repo_root" <<'PY'
import importlib.util
import sys
from pathlib import Path

resolver_path = Path(sys.argv[1]) / "scripts/development-workflow/workflow-config-resolver.py"
manifest_path = Path(sys.argv[2])
repo_root = Path(sys.argv[3])

spec = importlib.util.spec_from_file_location("workflow_config_resolver", resolver_path)
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

allowed_scopes = {"shared", "hub_only", "product_repo_injection"}

if not manifest_path.read_text(encoding="utf-8").strip():
    raise SystemExit(f"{manifest_path}: manifest is empty")

data = module.parse_yaml_subset(manifest_path)
if not isinstance(data, dict):
    raise SystemExit(f"{manifest_path}: manifest root must be a mapping")

role = data.get("skeleton_role")
if role not in {"workflow_hub", "product_repo"}:
    raise SystemExit(f"{manifest_path}: unknown skeleton_role '{role}'")

entries = data.get("entries")
if not isinstance(entries, list) or not entries:
    raise SystemExit(f"{manifest_path}: entries must be a non-empty list")

for index, entry in enumerate(entries, start=1):
    if not isinstance(entry, dict):
        raise SystemExit(f"{manifest_path}: entry {index} must be a mapping")
    path = entry.get("path")
    if not isinstance(path, str) or not path.strip():
        raise SystemExit(f"{manifest_path}: entry {index} has no path")
    scope = entry.get("mode_scope")
    if scope not in allowed_scopes:
        raise SystemExit(f"{manifest_path}: entry {path} has unknown mode_scope '{scope}'")

    generated = entry.get("generated_example") is True or entry.get("example_only") is True
    if not generated and not (repo_root / path).exists():
        raise SystemExit(f"{manifest_path}: entry {path} points to a missing source path")

    if role == "product_repo":
        required = entry.get("required_for_product_repo") is True
        forbidden = (
            path.startswith("docs/specs/")
            or "implementation-plan" in path
            or path.startswith("docs/testing/workflow/")
        )
        if forbidden and not required:
            raise SystemExit(
                f"{manifest_path}: product repository injection includes hub-owned artifact {path}"
            )

print("VALID")
PY
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
  "workflow_hub_manifest_valid" \
  validate_skeleton_manifest \
  "$REPO_ROOT/template/workflow-hub/skeleton-manifest.yaml" \
  "$REPO_ROOT"
run_passes \
  "product_repo_manifest_valid" \
  validate_skeleton_manifest \
  "$REPO_ROOT/template/product-repo-injection/skeleton-manifest.yaml" \
  "$REPO_ROOT"

private_detail_hits="$(
  grep -RInE 'Leasity|RADAR|kids-safety|baumsystem|lhpaul/' \
    "$REPO_ROOT/template/workflow-hub" \
    "$REPO_ROOT/template/product-repo-injection" || true
)"
run_test "skeleton_private_detail_scan" "" "$private_detail_hits"

echo ""
echo "=== Area 2: sync manifest mode scopes ==="

sync_manifest="$REPO_ROOT/sync-manifest.yaml"
sync_content="$(cat "$sync_manifest")"
run_contains "sync_scope_shared_defined" "  shared:" "$sync_content"
run_contains "sync_scope_hub_only_defined" "  hub_only:" "$sync_content"
run_contains "sync_scope_product_injection_defined" "  product_repo_injection:" "$sync_content"
run_contains "sync_manifest_workflow_hub_skeleton" "template/workflow-hub/" "$sync_content"
run_contains "sync_manifest_product_repo_skeleton" "template/product-repo-injection/" "$sync_content"
run_contains "sync_manifest_existing_always_sync" "  always_sync:" "$sync_content"
run_contains "sync_manifest_existing_special_handling" "  special_handling:" "$sync_content"
run_contains "sync_manifest_existing_project_specific" "  project_specific:" "$sync_content"

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

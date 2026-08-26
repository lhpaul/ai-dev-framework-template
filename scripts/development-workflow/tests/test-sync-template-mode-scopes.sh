#!/usr/bin/env bash
# test-sync-template-mode-scopes.sh - role-aware sync-manifest selection tests.
# covers: sync-manifest.yaml
# covers: scripts/development-workflow/select-sync-manifest-entries.py
# covers: scripts/development-workflow/validate-workflow-config.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
SELECTOR="$REPO_ROOT/scripts/development-workflow/select-sync-manifest-entries.py"

TMP_ROOT="$(mktemp -d)" || {
  echo "Failed to create temporary directory." >&2
  exit 1
}

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

run_equals() {
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

run_not_contains() {
  local name="$1"
  local unexpected="$2"
  local actual="$3"
  if grep -Fq -- "$unexpected" <<< "$actual"; then
    echo "FAIL: $name - output unexpectedly contained '${unexpected}'"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
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

fixture_manifest="$TMP_ROOT/sync-manifest.yaml"
cat > "$fixture_manifest" <<'YAML'
schema_version: 1

mode_scopes:
  shared:
    label: Shared
  hub_only:
    label: Hub only
  product_repo_injection:
    label: Product repository injection

categories:
  always_sync:
    - path: REVIEW.md
      mode_scope: shared
    - path: "docs/hash#file.md"
      mode_scope: shared
    - path: docs/workflow/
      glob: "**/*"
      mode_scope: hub_only
    - path: template/product-repo-injection/
      glob: "**/*"
      mode_scope: product_repo_injection
    - path: scripts/development-workflow/validate-workflow-config.sh
      mode_scope: product_repo_injection
    - path: scripts/development-workflow/pr-ci-loop.sh
      mode_scope: product_repo_injection
  special_handling:
    - path: .github/workflows/e2e-regression.yml
      mode_scope: shared
    - path: .claude/settings.json
      mode_scope: hub_only
    - path: .ai-dev-workflow.local.example.yaml
      mode_scope: product_repo_injection
  project_specific:
    - path: README.md
      mode_scope: shared
      note: |
        This literal block also has colon-like text that must not be parsed as
        metadata: mode_scope: hub_only.
    - path: CLAUDE.md
      mode_scope: hub_only
    - path: AGENTS.md
      mixed_content: true
      annotation_scheme: html_comments
      mode_scope: product_repo_injection
      note: >
        This folded block has colon-like text that must not be parsed as entry
        metadata: mode_scope: hub_only.
YAML

single_output="$(python3 "$SELECTOR" --manifest "$fixture_manifest" --role single_repo)"
hub_output="$(python3 "$SELECTOR" --manifest "$fixture_manifest" --role workflow_hub)"
product_output="$(python3 "$SELECTOR" --manifest "$fixture_manifest" --role product_repo)"

echo ""
echo "=== sync_template_scopes: single_repo compatibility ==="

run_contains "single_role_reported" "ROLE=single_repo" "$single_output"
run_contains "single_selects_all_entries" "SELECTED_COUNT=12" "$single_output"
run_contains "single_skips_no_entries" "SKIPPED_COUNT=0" "$single_output"
run_contains "single_preserves_quoted_hash_path" "SELECTED category=always_sync mode_scope=shared path=docs/hash#file.md glob=" "$single_output"
run_contains "single_keeps_hub_scope" "SELECTED category=always_sync mode_scope=hub_only path=docs/workflow/ glob=**/*" "$single_output"
run_contains "single_keeps_product_scope" "SELECTED category=project_specific mode_scope=product_repo_injection path=AGENTS.md glob=" "$single_output"

echo ""
echo "=== sync_template_scopes: workflow_hub selection ==="

run_contains "hub_role_reported" "ROLE=workflow_hub" "$hub_output"
run_contains "hub_selected_count" "SELECTED_COUNT=7" "$hub_output"
run_contains "hub_skipped_count" "SKIPPED_COUNT=5" "$hub_output"
run_contains "hub_selects_shared" "SELECTED category=always_sync mode_scope=shared path=REVIEW.md glob=" "$hub_output"
run_contains "hub_selects_hub_only" "SELECTED category=always_sync mode_scope=hub_only path=docs/workflow/ glob=**/*" "$hub_output"
run_contains "hub_reports_product_scope_skipped" "SKIPPED category=always_sync mode_scope=product_repo_injection path=template/product-repo-injection/ glob=**/* mixed_content= annotation_scheme= reason=scope_not_applicable" "$hub_output"
run_contains "hub_skips_product_release_runtime" "SKIPPED category=always_sync mode_scope=product_repo_injection path=scripts/development-workflow/validate-workflow-config.sh glob=" "$hub_output"

echo ""
echo "=== sync_template_scopes: product_repo selection ==="

run_contains "product_role_reported" "ROLE=product_repo" "$product_output"
run_contains "product_selected_count" "SELECTED_COUNT=9" "$product_output"
run_contains "product_skipped_count" "SKIPPED_COUNT=3" "$product_output"
run_contains "product_selects_shared" "SELECTED category=always_sync mode_scope=shared path=REVIEW.md glob=" "$product_output"
run_contains "product_selects_injection" "SELECTED category=always_sync mode_scope=product_repo_injection path=template/product-repo-injection/ glob=**/*" "$product_output"
run_contains "product_selects_release_validation_runtime" "SELECTED category=always_sync mode_scope=product_repo_injection path=scripts/development-workflow/validate-workflow-config.sh glob=" "$product_output"
run_contains "product_selects_product_ci_runtime" "SELECTED category=always_sync mode_scope=product_repo_injection path=scripts/development-workflow/pr-ci-loop.sh glob=" "$product_output"
run_contains "product_reports_hub_scope_skipped" "SKIPPED category=always_sync mode_scope=hub_only path=docs/workflow/ glob=**/* mixed_content= annotation_scheme= reason=scope_not_applicable" "$product_output"
run_not_contains "product_does_not_select_hub_protocols" "SELECTED category=always_sync mode_scope=hub_only path=docs/workflow/" "$product_output"

echo ""
echo "=== sync_template_scopes: parser-risk edge cases ==="

stable_output="$(python3 "$SELECTOR" --manifest "$fixture_manifest" --role product_repo)"
run_equals "selection_helper_output_stable_for_dry_run_apply" "$product_output" "$stable_output"

unknown_scope_manifest="$TMP_ROOT/unknown-scope.yaml"
sed 's/mode_scope: shared/mode_scope: mystery/' "$fixture_manifest" > "$unknown_scope_manifest"
run_fails_contains \
  "unknown_mode_scope_fails_closed" \
  "unknown mode_scope 'mystery'" \
  python3 "$SELECTOR" --manifest "$unknown_scope_manifest" --role workflow_hub

missing_entry_scope_manifest="$TMP_ROOT/missing-entry-scope.yaml"
sed '/mode_scope: shared/d' "$fixture_manifest" > "$missing_entry_scope_manifest"
run_fails_contains \
  "missing_entry_mode_scope_fails_closed" \
  "is missing mode_scope" \
  python3 "$SELECTOR" --manifest "$missing_entry_scope_manifest" --role workflow_hub

missing_scopes_manifest="$TMP_ROOT/missing-mode-scopes.yaml"
sed '/mode_scopes:/,/categories:/d' "$fixture_manifest" > "$missing_scopes_manifest"
printf 'categories:\n' | cat - "$missing_scopes_manifest" > "$TMP_ROOT/missing-mode-scopes-fixed.yaml"
run_fails_contains \
  "missing_mode_scopes_fails_closed" \
  "manifest is missing mode_scopes" \
  python3 "$SELECTOR" --manifest "$TMP_ROOT/missing-mode-scopes-fixed.yaml" --role workflow_hub

partial_scopes_manifest="$TMP_ROOT/partial-mode-scopes.yaml"
cat > "$partial_scopes_manifest" <<'YAML'
schema_version: 1

mode_scopes:
  shared:
    label: Shared

categories:
  always_sync:
    - path: REVIEW.md
      mode_scope: shared
YAML
run_fails_contains \
  "partial_mode_scopes_fail_closed" \
  "manifest is missing required mode_scope declarations" \
  python3 "$SELECTOR" --manifest "$partial_scopes_manifest" --role workflow_hub

unknown_category_manifest="$TMP_ROOT/unknown-category.yaml"
cat > "$unknown_category_manifest" <<'YAML'
schema_version: 1

mode_scopes:
  shared:
    label: Shared
  hub_only:
    label: Hub only
  product_repo_injection:
    label: Product repository injection

categories:
  not_a_sync_category:
    - path: REVIEW.md
      mode_scope: shared
YAML
run_fails_contains \
  "unknown_category_fails_closed" \
  "unknown category 'not_a_sync_category'" \
  python3 "$SELECTOR" --manifest "$unknown_category_manifest" --role workflow_hub

entry_before_category_manifest="$TMP_ROOT/entry-before-category.yaml"
cat > "$entry_before_category_manifest" <<'YAML'
schema_version: 1

mode_scopes:
  shared:
    label: Shared
  hub_only:
    label: Hub only
  product_repo_injection:
    label: Product repository injection

categories:
    - path: REVIEW.md
      mode_scope: shared
YAML
run_fails_contains \
  "entry_before_category_fails_closed" \
  "category entry appears before category name" \
  python3 "$SELECTOR" --manifest "$entry_before_category_manifest" --role workflow_hub

run_fails_contains \
  "unknown_role_fails_closed" \
  "invalid choice" \
  python3 "$SELECTOR" --manifest "$fixture_manifest" --role unknown_role

tab_indent_manifest="$TMP_ROOT/tab-indent.yaml"
printf 'schema_version: 1\n\nmode_scopes:\n\tshared:\n' > "$tab_indent_manifest"
run_fails_contains \
  "tab_indentation_fails_closed" \
  "tabs are not supported for indentation" \
  python3 "$SELECTOR" --manifest "$tab_indent_manifest" --role workflow_hub

triple_quote_manifest="$TMP_ROOT/triple-quote.yaml"
cat > "$triple_quote_manifest" <<'YAML'
schema_version: 1

mode_scopes:
  shared:
    label: Shared
  hub_only:
    label: Hub only
  product_repo_injection:
    label: Product repository injection

categories:
  always_sync:
    - path: """docs/triple#hash.md"""
      mode_scope: shared
YAML
triple_quote_output="$(python3 "$SELECTOR" --manifest "$triple_quote_manifest" --role single_repo)"
run_contains \
  "triple_quoted_hash_path_preserved" \
  "SELECTED category=always_sync mode_scope=shared path=docs/triple#hash.md glob=" \
  "$triple_quote_output"

echo ""
echo "=== sync_template_scopes: retro-metrics precedence canary (real manifest) ==="
# Regression guard for issue #1438: docs/workflow/retro-metrics.md and
# docs/workflow/retro-metrics-platforms.md must remain declared as exact
# project_specific entries (never re-absorbed into the docs/workflow/
# always_sync glob), so downstream projects keep their own accumulated
# history across /sync-template runs.
real_manifest="$REPO_ROOT/sync-manifest.yaml"
real_single_output="$(python3 "$SELECTOR" --manifest "$real_manifest" --role single_repo)"
real_hub_output="$(python3 "$SELECTOR" --manifest "$real_manifest" --role workflow_hub)"

run_contains \
  "retro_metrics_selected_project_specific_single_repo" \
  "SELECTED category=project_specific mode_scope=shared path=docs/workflow/retro-metrics.md glob=" \
  "$real_single_output"
run_contains \
  "retro_metrics_platforms_selected_project_specific_single_repo" \
  "SELECTED category=project_specific mode_scope=shared path=docs/workflow/retro-metrics-platforms.md glob=" \
  "$real_single_output"
run_contains \
  "retro_metrics_selected_project_specific_workflow_hub" \
  "SELECTED category=project_specific mode_scope=shared path=docs/workflow/retro-metrics.md glob=" \
  "$real_hub_output"
run_not_contains \
  "retro_metrics_not_declared_always_sync" \
  "category=always_sync mode_scope=shared path=docs/workflow/retro-metrics.md" \
  "$real_single_output"
run_not_contains \
  "retro_metrics_platforms_not_declared_always_sync" \
  "category=always_sync mode_scope=shared path=docs/workflow/retro-metrics-platforms.md" \
  "$real_single_output"

echo ""
echo "sync-template mode-scope tests complete: $PASS_COUNT passed, $FAIL_COUNT failed."

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi

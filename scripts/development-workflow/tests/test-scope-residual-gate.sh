#!/usr/bin/env bash
# test-scope-residual-gate.sh - Unit tests for scope residual gate.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
HELPER="$REPO_ROOT/scripts/development-workflow/scope-residual-gate.sh"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

assert_field() {
  local name="$1" expected="$2" text="$3" field="$4"
  local actual
  actual="$(printf '%s\n' "$text" | sed -n "s/^${field}=//p" | tail -1)"
  if [ "$actual" = "$expected" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'PASS: %s\n' "$name"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf 'FAIL: %s - expected %s=%s, got %s\n' "$name" "$field" "$expected" "$actual"
  fi
}

assert_fails_contains() {
  local name="$1" expected="$2"
  shift 2
  local output status
  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e
  if [ "$status" -ne 0 ] && grep -Fq -- "$expected" <<<"$output"; then
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'PASS: %s\n' "$name"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf 'FAIL: %s - expected failure containing %s\n%s\n' "$name" "$expected" "$output"
  fi
}

write_json() {
  local path="$1" content="$2"
  printf '%s\n' "$content" >"$path"
}

clean="$TMP_DIR/clean.json"
write_json "$clean" '{"checked_scope":"console.log cleanup","residual_groups":[],"helper_outputs":[]}'

blocking="$TMP_DIR/blocking.json"
write_json "$blocking" '{"checked_scope":"console.log cleanup","residual_groups":[{"summary":"admin logs","remaining_count":3}],"helper_outputs":[]}'

follow_up="$TMP_DIR/follow-up.json"
write_json "$follow_up" '{"checked_scope":"console.log cleanup","residual_groups":[{"summary":"legacy logs","remaining_count":3,"disposition":"follow_up","follow_up":"#1234"}],"helper_outputs":[]}'

completed_zero="$TMP_DIR/completed-zero.json"
write_json "$completed_zero" '{"checked_scope":"console.log cleanup","residual_groups":[{"summary":"fixed logs","remaining_count":0,"disposition":"completed"}],"helper_outputs":[]}'

missing_count="$TMP_DIR/missing-count.json"
write_json "$missing_count" '{"checked_scope":"console.log cleanup","residual_groups":[{"summary":"admin logs"}],"helper_outputs":[]}'

completed_positive="$TMP_DIR/completed-positive.json"
write_json "$completed_positive" '{"checked_scope":"console.log cleanup","residual_groups":[{"summary":"admin logs","remaining_count":2,"disposition":"completed"}],"helper_outputs":[]}'

unused_helper="$TMP_DIR/unused-helper.json"
write_json "$unused_helper" '{"checked_scope":"helper extraction","residual_groups":[],"helper_outputs":[{"path":"scripts/shared.sh","apparent_callers":[]}]}'

used_helper="$TMP_DIR/used-helper.json"
write_json "$used_helper" '{"checked_scope":"helper extraction","residual_groups":[],"helper_outputs":[{"path":"scripts/shared.sh","apparent_callers":["scripts/caller.sh"]}]}'

malformed="$TMP_DIR/malformed.json"
write_json "$malformed" '[]'

bad_remaining="$TMP_DIR/bad-remaining.json"
write_json "$bad_remaining" '{"checked_scope":"console.log cleanup","residual_groups":[{"summary":"admin logs","remaining_count":"unknown"}],"helper_outputs":[]}'

out="$( "$HELPER" classify --issue-title "Clean 127 console.log occurrences across apps/admin" )"
assert_field "classify_requires_verification_not_pass" "requires_verification" "$out" "RESULT"
assert_field "classifies_boundary_variants" "numeric_sweep" "$out" "SCOPE_CLASSIFICATION"
assert_field "preserves_numeric_target_in_summary" "127" "$out" "TARGET_COUNT"

out="$( "$HELPER" classify --issue-title "Fix helper text copy on settings page" )"
assert_field "ignores_negative_helper_lookalike" "not_applicable" "$out" "SCOPE_CLASSIFICATION"

out="$( "$HELPER" classify --issue-title "All set on login page" )"
assert_field "ignores_all_set_phrase" "not_applicable" "$out" "SCOPE_CLASSIFICATION"

out="$( "$HELPER" classify --issue-title "Tune batch size config for worker queue" )"
assert_field "ignores_batch_size_config" "not_applicable" "$out" "SCOPE_CLASSIFICATION"

out="$( "$HELPER" classify --issue-title "Align spacing across from login sidebar" )"
assert_field "ignores_across_from_phrase" "not_applicable" "$out" "SCOPE_CLASSIFICATION"

out="$( "$HELPER" classify --issue-title "Remove debug() and console.log across apps/admin, apps/api" )"
assert_field "collapses_multi_target_line_to_single_gate" "sweep" "$out" "SCOPE_CLASSIFICATION"

out="$( "$HELPER" classify --issue-title "Extract 7 shared helpers across services and remove all old callers" )"
assert_field "combines_overlapping_helper_and_sweep_signals" "helper_extraction" "$out" "SCOPE_CLASSIFICATION"
assert_field "helper_numeric_target_preserved" "7" "$out" "TARGET_COUNT"

out="$( "$HELPER" verify --issue-title "Clean 127 console.log occurrences across apps/admin" --evidence "$clean" )"
assert_field "passes_clean_evidence" "pass" "$out" "RESULT"

assert_fails_contains "blocks_undisposed_residuals" "undisposed residual" \
  "$HELPER" verify --issue-title "Clean 127 console.log occurrences across apps/admin" --evidence "$blocking"

out="$( "$HELPER" verify --issue-title "Clean 127 console.log occurrences across apps/admin" --evidence "$follow_up" )"
assert_field "requires_linked_follow_up_for_deferred_residuals" "pass" "$out" "RESULT"
assert_field "follow_up_count_reported" "1" "$out" "FOLLOW_UPS"

out="$( "$HELPER" verify --issue-title "Clean 127 console.log occurrences across apps/admin" --evidence "$completed_zero" )"
assert_field "passes_completed_zero_residual" "pass" "$out" "RESULT"

assert_fails_contains "blocks_missing_residual_count" "residual missing remaining_count" \
  "$HELPER" verify --issue-title "Clean 127 console.log occurrences across apps/admin" --evidence "$missing_count"

assert_fails_contains "blocks_completed_positive_residual_count" "undisposed residual" \
  "$HELPER" verify --issue-title "Clean 127 console.log occurrences across apps/admin" --evidence "$completed_positive"

assert_fails_contains "blocks_unused_helper_outputs" "unused helper without disposition" \
  "$HELPER" verify --issue-title "Extract 7 shared helpers from workflow scripts" --evidence "$unused_helper"

out="$( "$HELPER" verify --issue-title "Extract 7 shared helpers from workflow scripts" --evidence "$used_helper" )"
assert_field "passes_helper_with_callers" "pass" "$out" "RESULT"

assert_fails_contains "escalates_missing_evidence_for_ambiguous_scope" "Residual evidence is required" \
  "$HELPER" verify --issue-title "Clean all unresolved workflow leftovers across the codebase"

assert_fails_contains "blocks_malformed_or_incomplete_evidence" "not a JSON object" \
  "$HELPER" verify --issue-title "Clean 127 console.log occurrences across apps/admin" --evidence "$malformed"

assert_fails_contains "blocks_unparseable_evidence_fields" "fields could not be parsed" \
  "$HELPER" verify --issue-title "Clean 127 console.log occurrences across apps/admin" --evidence "$bad_remaining"

printf '\nScope residual gate tests: %s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]

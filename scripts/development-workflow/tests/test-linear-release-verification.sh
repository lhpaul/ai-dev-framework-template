#!/usr/bin/env bash
# test-linear-release-verification.sh - evaluator for verified Linear release
# completion (#2009). Drives linear-release-verification.py directly with
# temporary state directories and synthetic read-back files; no network, no
# Linear access, no repository mutation.
#
# Cases U1-U15 follow the implementation plan:
# docs/specs/developments/20261113135530_2009-linear-release-verification/2_2009-linear-release-verification_implementation-plan.md
#
# Usage: bash scripts/development-workflow/tests/test-linear-release-verification.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
EVALUATOR="$REPO_ROOT/scripts/development-workflow/linear-release-verification.py"

TMP_ROOT="$(mktemp -d)"
cleanup() {
  chmod -R u+rwX "$TMP_ROOT" 2>/dev/null || true
  rm -rf -- "$TMP_ROOT"
}
trap cleanup EXIT

PASS_COUNT=0
FAIL_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); echo "PASS: $1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); echo "FAIL: $1" >&2; }

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then pass "$name"; else fail "$name (expected '$expected', got '$actual')"; fi
}

has_line() {
  # Exact whole-line match without a pipe (no SIGPIPE under pipefail).
  case $'\n'"$2"$'\n' in
    *$'\n'"$1"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

assert_line() {
  local name="$1" line="$2" output="$3"
  if has_line "$line" "$output"; then pass "$name"; else fail "$name (missing line: $line)"; printf '%s\n' "$output" >&2; fi
}

assert_contains() {
  local name="$1" needle="$2" output="$3"
  case "$output" in
    *"$needle"*) pass "$name" ;;
    *) fail "$name (missing: $needle)"; printf '%s\n' "$output" >&2 ;;
  esac
}

assert_not_contains() {
  local name="$1" needle="$2" output="$3"
  case "$output" in
    *"$needle"*) fail "$name (unexpected: $needle)"; printf '%s\n' "$output" >&2 ;;
    *) pass "$name" ;;
  esac
}

BRANCH="release/v1.29.1"
VERSION="v1.29.1"
LABEL="release/v1.29.1"
FIRST_RUN="2026-01-01T00:00:00Z"
RUN_STARTED="2026-06-01T00:00:00Z"
NOW="2026-07-01T00:00:00Z"
STATE_KEY="release__v1.29.1"

new_state() {
  # new_state [seed:true|false] -> prints a fresh, unique state directory
  local dir
  dir="$(mktemp -d "$TMP_ROOT/state.XXXXXX")"
  mkdir -p "$dir/$STATE_KEY"
  if [ "${1:-true}" = "true" ]; then
    printf '{"schemaVersion":"linear_release_first_run.v1","releaseBranch":"%s","releaseVersion":"%s","firstRunStartedAt":"%s"}\n' \
      "$BRANCH" "$VERSION" "$FIRST_RUN" > "$dir/$STATE_KEY/first-run.json"
  fi
  printf '%s\n' "$dir"
}

# read_json <issue> <status> <labels-json-array> [observedAt] [extra-json-object]
read_json() {
  local issue="$1" status="$2" labels="$3" observed="${4-2026-03-01T12:00:00Z}" extra="${5:-}"
  [ -n "$extra" ] || extra='{}'
  jq -cn --arg issue "$issue" --arg status "$status" --argjson labels "$labels" \
    --arg observed "$observed" --arg version "$VERSION" --argjson extra "$extra" \
    '{suppliedFor:$issue, provider:"linear", issue:$issue, team:($issue|split("-")[0]),
      releaseVersion:$version, labels:$labels, statusName:$status, observedAt:$observed,
      readRequestId:("read-" + $issue + "-" + $observed)} + $extra'
}

# readback <file> <read-json>... -> writes a v1 read-back document
readback() {
  local file="$1"
  shift
  local reads="[]" item
  for item in "$@"; do
    reads="$(jq -c --argjson read "$item" '. + [$read]' <<<"$reads")"
  done
  jq -n --argjson reads "$reads" '{schemaVersion:"linear_release_readback.v1", reads:$reads}' > "$file"
}

RC=0
OUT=""
# evaluate <state-dir> <readback-file|-> <scope...>
evaluate() {
  local state="$1" file="$2"
  shift 2
  local -a args=(evaluate --state-dir "$state" --release-branch "$BRANCH"
    --release-version "$VERSION" --release-label "$LABEL" --released-status Released
    --run-started-at "${EVAL_RUN_STARTED:-$RUN_STARTED}" --now "${EVAL_NOW:-$NOW}")
  if [ "$file" != "-" ]; then
    args+=(--readback "$file")
  fi
  local scope
  for scope in "$@"; do
    args+=(--scope "$scope")
  done
  RC=0
  OUT="$(python3 "$EVALUATOR" "${args[@]}" 2>"$TMP_ROOT/stderr")" || RC=$?
}

VERIFIED_10="$(read_json LEA-10 Released "[\"$LABEL\",\"bug\"]")"
VERIFIED_11="$(read_json LEA-11 Released "[\"$LABEL\"]")"

echo "=== U1: every item verified -> complete ==="
state="$(new_state)"
readback "$TMP_ROOT/u1.json" "$VERIFIED_10" "$VERIFIED_11"
evaluate "$state" "$TMP_ROOT/u1.json" LEA-10 LEA-11
assert_eq "u1_exit_complete" 0 "$RC"
assert_line "u1_outcome" "LINEAR_RELEASE_OUTCOME=complete" "$OUT"
assert_line "u1_counts" "LINEAR_RELEASE_COUNTS verified=2 missing_label=0 not_released=0 missing_label_and_not_released=0 not_verified=0" "$OUT"
assert_contains "u1_item_10" "LINEAR_RELEASE_ITEM issue=LEA-10 result=verified label=present status=\"Released\"" "$OUT"
assert_contains "u1_read_at" "read_at=2026-03-01T12:00:00Z" "$OUT"
assert_not_contains "u1_no_label_action" "LINEAR_RELEASE_LABEL_ACTION" "$OUT"
assert_not_contains "u1_no_unverified" "TRACKER_ISSUES_UNVERIFIED" "$OUT"
record_count="$(find "$state/$STATE_KEY/runs" -name '*.json' -type f | wc -l | tr -d ' ')"
assert_eq "u1_one_record" 1 "$record_count"
record="$(find "$state/$STATE_KEY/runs" -name '*.json' -type f)"
assert_eq "u1_record_outcome" complete "$(jq -r .outcome "$record")"
assert_eq "u1_record_keeps_readback" "$(cat "$TMP_ROOT/u1.json")" "$(jq -r .readback.text "$record")"
assert_contains "u1_record_line" "LINEAR_RELEASE_VERIFICATION_RECORD path=\"$record\"" "$OUT"

echo "=== U2: one item in Merged with the label -> not_released ==="
state="$(new_state)"
readback "$TMP_ROOT/u2.json" "$(read_json LEA-10 Merged "[\"$LABEL\"]")" "$VERIFIED_11"
evaluate "$state" "$TMP_ROOT/u2.json" LEA-10 LEA-11
assert_eq "u2_exit_incomplete" 1 "$RC"
assert_contains "u2_item_10" "LINEAR_RELEASE_ITEM issue=LEA-10 result=not_released label=present status=\"Merged\"" "$OUT"
assert_contains "u2_item_11" "LINEAR_RELEASE_ITEM issue=LEA-11 result=verified" "$OUT"
assert_line "u2_outcome" "LINEAR_RELEASE_OUTCOME=incomplete" "$OUT"
assert_line "u2_unverified" "TRACKER_ISSUES_UNVERIFIED=LEA-10" "$OUT"

echo "=== U3: missing label, and neither requirement ==="
state="$(new_state)"
readback "$TMP_ROOT/u3.json" "$(read_json LEA-10 Released '["bug"]')" "$(read_json LEA-11 Merged '[]')"
evaluate "$state" "$TMP_ROOT/u3.json" LEA-10 LEA-11
assert_eq "u3_exit" 1 "$RC"
assert_contains "u3_missing_label" "LINEAR_RELEASE_ITEM issue=LEA-10 result=missing_label label=absent" "$OUT"
assert_contains "u3_labels_read" 'labels_read=["bug"]' "$OUT"
assert_contains "u3_both" "LINEAR_RELEASE_ITEM issue=LEA-11 result=missing_label_and_not_released" "$OUT"
assert_line "u3_label_action" "LINEAR_RELEASE_LABEL_ACTION label=$LABEL teams=LEA action=create_label_in_owning_team_if_missing_then_apply" "$OUT"

echo "=== U4: hotfix version, no read-back -> no_read and label action ==="
state="$(new_state false)"
evaluate "$state" - LEA-10 OPS-3
assert_eq "u4_exit" 1 "$RC"
assert_line "u4_no_read_10" "LINEAR_RELEASE_ITEM issue=LEA-10 result=not_verified reasons=no_read" "$OUT"
assert_line "u4_no_read_ops" "LINEAR_RELEASE_ITEM issue=OPS-3 result=not_verified reasons=no_read" "$OUT"
assert_line "u4_label_action" "LINEAR_RELEASE_LABEL_ACTION label=release/v1.29.1 teams=LEA,OPS action=create_label_in_owning_team_if_missing_then_apply" "$OUT"
assert_contains "u4_header_none" "readback=none" "$OUT"
assert_line "u4_unverified" "TRACKER_ISSUES_UNVERIFIED=LEA-10,OPS-3" "$OUT"

echo "=== U5: reads that do not count ==="
u5_case() {
  local name="$1" reason="$2" detail="$3" read="$4"
  local state
  state="$(new_state)"
  readback "$TMP_ROOT/u5-$name.json" "$read"
  evaluate "$state" "$TMP_ROOT/u5-$name.json" LEA-10
  assert_eq "u5_${name}_exit" 1 "$RC"
  assert_contains "u5_${name}_reason" "LINEAR_RELEASE_ITEM issue=LEA-10 result=not_verified reasons=$reason reads=" "$OUT"
  assert_contains "u5_${name}_detail" "\"detail\":\"$detail\"" "$OUT"
}
OK_LABELS="[\"$LABEL\"]"
u5_case other_version mismatch other_release_version "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01T12:00:00Z '{"releaseVersion":"v1.29.0"}')"
u5_case bare_version mismatch other_release_version "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01T12:00:00Z '{"releaseVersion":"1.29.1"}')"
u5_case other_item mismatch other_item "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01T12:00:00Z '{"issue":"LEA-12"}')"
u5_case other_team mismatch other_team "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01T12:00:00Z '{"team":"OPS"}')"
u5_case team_prefix mismatch other_team "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01T12:00:00Z '{"team":"LE"}')"
u5_case stale stale before_first_run "$(read_json LEA-10 Released "$OK_LABELS" 2025-12-31T23:59:59Z)"
u5_case at_start stale before_first_run "$(read_json LEA-10 Released "$OK_LABELS" "$FIRST_RUN")"
u5_case no_observed unreadable invalid_observedAt "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01T12:00:00Z '{"observedAt":null}')"
u5_case empty_observed unreadable invalid_observedAt "$(read_json LEA-10 Released "$OK_LABELS" "")"
u5_case no_offset unreadable invalid_observedAt "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01T12:00:00)"
u5_case not_a_date unreadable invalid_observedAt "$(read_json LEA-10 Released "$OK_LABELS" yesterday)"
u5_case date_only unreadable invalid_observedAt "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01)"
u5_case future unreadable future_observedAt "$(read_json LEA-10 Released "$OK_LABELS" 2026-07-01T00:00:01Z)"
u5_case provider unreadable provider_not_linear "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01T12:00:00Z '{"provider":"github"}')"
u5_case echoed_write unreadable echoed_write "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01T12:00:00Z '{"readRequestId":"same","mutationRequestId":"same"}')"
u5_case labels_string unreadable invalid_labels "$(read_json LEA-10 Released '"release/v1.29.1"')"
u5_case labels_non_string unreadable invalid_labels "$(read_json LEA-10 Released '[1]')"
u5_case no_status unreadable invalid_statusName "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01T12:00:00Z '{"statusName":""}')"
u5_case no_read_id unreadable invalid_readRequestId "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01T12:00:00Z '{"readRequestId":7}')"

# Accepted timestamp forms: +00:00, non-UTC offset, and a fraction inside the
# evaluation second (whole-second future check).
for form in "2026-03-01T12:00:00+00:00" "2026-03-01T14:00:00+02:00" "2026-07-01T00:00:00.500000Z"; do
  state="$(new_state)"
  readback "$TMP_ROOT/u5-form.json" "$(read_json LEA-10 Released "$OK_LABELS" "$form")"
  evaluate "$state" "$TMP_ROOT/u5-form.json" LEA-10
  assert_eq "u5_form_accepted_${form}" 0 "$RC"
done

echo "=== U6: several unusable reads -> every reason in order ==="
state="$(new_state)"
readback "$TMP_ROOT/u6.json" \
  "$(read_json LEA-10 Released "$OK_LABELS" 2025-06-01T00:00:00Z)" \
  "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01T12:00:00Z '{"team":"OPS"}')" \
  "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01T12:00:00Z '{"provider":"x"}')"
evaluate "$state" "$TMP_ROOT/u6.json" LEA-10
assert_contains "u6_ordered_reasons" "result=not_verified reasons=unreadable,mismatch,stale reads=" "$OUT"

echo "=== U7: read-back shape errors -> every item unreadable ==="
u7_case() {
  local name="$1" detail="$2" body="$3"
  local state
  state="$(new_state)"
  printf '%s\n' "$body" > "$TMP_ROOT/u7-$name.json"
  evaluate "$state" "$TMP_ROOT/u7-$name.json" LEA-10 LEA-11
  assert_eq "u7_${name}_exit" 1 "$RC"
  assert_line "u7_${name}_10" "LINEAR_RELEASE_ITEM issue=LEA-10 result=not_verified reasons=unreadable detail=$detail" "$OUT"
  assert_line "u7_${name}_11" "LINEAR_RELEASE_ITEM issue=LEA-11 result=not_verified reasons=unreadable detail=$detail" "$OUT"
}
u7_case not_json readback_not_json 'not json {'
u7_case array readback_not_object '[]'
u7_case schema readback_schema_version '{"schemaVersion":"v0","reads":[]}'
u7_case no_reads readback_reads_not_array '{"schemaVersion":"linear_release_readback.v1"}'
u7_case reads_object readback_reads_not_array '{"schemaVersion":"linear_release_readback.v1","reads":{}}'

echo "=== U8: ignored reads never change the outcome ==="
state="$(new_state)"
printf '%s\n' "$(jq -n --argjson a "$VERIFIED_10" --argjson b "$(read_json LEA-99 Merged '[]')" \
  '{schemaVersion:"linear_release_readback.v1", reads:[$a, $b, "text", {suppliedFor:"LEA_1"}, {suppliedFor:"-1"}, {issue:"LEA-"}]}')" \
  > "$TMP_ROOT/u8.json"
evaluate "$state" "$TMP_ROOT/u8.json" LEA-10
assert_eq "u8_exit_complete" 0 "$RC"
assert_line "u8_out_of_scope" 'LINEAR_RELEASE_READ_IGNORED issue="LEA-99" reason=out_of_scope' "$OUT"
assert_line "u8_non_object" 'LINEAR_RELEASE_READ_IGNORED issue=null reason=unattributable' "$OUT"
assert_line "u8_bad_id_underscore" 'LINEAR_RELEASE_READ_IGNORED issue="LEA_1" reason=unattributable' "$OUT"
assert_line "u8_bad_id_dash" 'LINEAR_RELEASE_READ_IGNORED issue="-1" reason=unattributable' "$OUT"
assert_line "u8_bad_id_trailing" 'LINEAR_RELEASE_READ_IGNORED issue="LEA-" reason=unattributable' "$OUT"

echo "=== U9: latest usable read decides; equal-time disagreement ==="
state="$(new_state)"
readback "$TMP_ROOT/u9a.json" \
  "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01T12:00:00Z)" \
  "$(read_json LEA-10 Merged "$OK_LABELS" 2026-03-02T12:00:00Z)"
evaluate "$state" "$TMP_ROOT/u9a.json" LEA-10
assert_contains "u9_newer_decides" "LINEAR_RELEASE_ITEM issue=LEA-10 result=not_released" "$OUT"
state="$(new_state)"
readback "$TMP_ROOT/u9b.json" \
  "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01T12:00:00Z '{"readRequestId":"a"}')" \
  "$(read_json LEA-10 Merged "$OK_LABELS" 2026-03-01T12:00:00Z '{"readRequestId":"b"}')"
evaluate "$state" "$TMP_ROOT/u9b.json" LEA-10
assert_contains "u9_conflicting" "LINEAR_RELEASE_ITEM issue=LEA-10 result=not_verified reasons=conflicting reads=" "$OUT"
state="$(new_state)"
readback "$TMP_ROOT/u9c.json" "$VERIFIED_10" "$VERIFIED_10"
evaluate "$state" "$TMP_ROOT/u9c.json" LEA-10
assert_eq "u9_identical_duplicates_verify" 0 "$RC"
state="$(new_state)"
readback "$TMP_ROOT/u9d.json" \
  "$(read_json LEA-10 Released "$OK_LABELS" 2026-03-01T12:00:00Z)" \
  "$(read_json LEA-10 Merged "$OK_LABELS" 2026-03-05T12:00:00Z '{"team":"OPS"}')"
evaluate "$state" "$TMP_ROOT/u9d.json" LEA-10
assert_eq "u9_unusable_newer_ignored_for_decision" 0 "$RC"

echo "=== U10: first-run record is created once and never moves ==="
state="$(new_state false)"
EVAL_RUN_STARTED="2026-02-01T00:00:00Z" evaluate "$state" - LEA-10
assert_eq "u10_first_created" "2026-02-01T00:00:00Z" "$(jq -r .firstRunStartedAt "$state/$STATE_KEY/first-run.json")"
assert_contains "u10_header_first" "first_run_started_at=2026-02-01T00:00:00Z run_started_at=2026-02-01T00:00:00Z" "$OUT"
readback "$TMP_ROOT/u10.json" "$(read_json LEA-10 Released "$OK_LABELS" 2026-02-15T00:00:00Z)"
EVAL_RUN_STARTED="2026-03-01T00:00:00Z" evaluate "$state" "$TMP_ROOT/u10.json" LEA-10
assert_eq "u10_rerun_keeps_start" "2026-02-01T00:00:00Z" "$(jq -r .firstRunStartedAt "$state/$STATE_KEY/first-run.json")"
assert_eq "u10_read_after_first_start_counts" 0 "$RC"
leftover="$(find "$state/$STATE_KEY" -maxdepth 1 -name '.first-run-*' | wc -l | tr -d ' ')"
assert_eq "u10_no_temporary_left" 0 "$leftover"

echo "=== U11: unavailable state -> exit 3 with one line ==="
state="$(new_state false)"
printf 'not json\n' > "$state/$STATE_KEY/first-run.json"
evaluate "$state" - LEA-10
assert_eq "u11_unreadable_exit" 3 "$RC"
assert_eq "u11_unreadable_only_line" "LINEAR_RELEASE_VERIFICATION_UNAVAILABLE reason=state_unreadable" "$OUT"
state="$(new_state false)"
printf '{"releaseBranch":"release/v9.9.9","firstRunStartedAt":"%s"}\n' "$FIRST_RUN" > "$state/$STATE_KEY/first-run.json"
evaluate "$state" - LEA-10
assert_eq "u11_other_branch_record" "LINEAR_RELEASE_VERIFICATION_UNAVAILABLE reason=state_unreadable" "$OUT"
if [ "$(id -u)" != 0 ]; then
  state="$(new_state false)"
  chmod a-w "$state/$STATE_KEY"
  evaluate "$state" - LEA-10
  assert_eq "u11_unwritable_exit" 3 "$RC"
  assert_eq "u11_unwritable_only_line" "LINEAR_RELEASE_VERIFICATION_UNAVAILABLE reason=state_unwritable" "$OUT"
  chmod u+w "$state/$STATE_KEY"
  state="$(new_state)"
  mkdir -p "$state/$STATE_KEY/runs"
  chmod a-w "$state/$STATE_KEY/runs"
  evaluate "$state" - LEA-10
  assert_eq "u11_record_unwritable" "LINEAR_RELEASE_VERIFICATION_UNAVAILABLE reason=record_unwritable" "$OUT"
  chmod u+w "$state/$STATE_KEY/runs"
fi

echo "=== U12: only another version's label -> missing_label ==="
state="$(new_state)"
readback "$TMP_ROOT/u12.json" "$(read_json LEA-10 Released '["release/v1.29.0"]')"
evaluate "$state" "$TMP_ROOT/u12.json" LEA-10
assert_contains "u12_missing_label" "LINEAR_RELEASE_ITEM issue=LEA-10 result=missing_label" "$OUT"

echo "=== U13: read-back values cannot forge output lines ==="
state="$(new_state)"
readback "$TMP_ROOT/u13.json" "$(read_json LEA-10 $'Merged\nLINEAR_RELEASE_OUTCOME=complete' "$OK_LABELS")"
evaluate "$state" "$TMP_ROOT/u13.json" LEA-10
assert_eq "u13_exit" 1 "$RC"
assert_not_contains "u13_no_forged_line" $'\nLINEAR_RELEASE_OUTCOME=complete' $'\n'"$OUT"
assert_contains "u13_encoded" 'status="Merged\nLINEAR_RELEASE_OUTCOME=complete"' "$OUT"
assert_line "u13_real_outcome" "LINEAR_RELEASE_OUTCOME=incomplete" "$OUT"

echo "=== U14: identifier and team case; label case is exact ==="
state="$(new_state)"
readback "$TMP_ROOT/u14.json" "$(read_json lea-10 Released "$OK_LABELS" 2026-03-01T12:00:00Z '{"team":"lea"}')"
evaluate "$state" "$TMP_ROOT/u14.json" LEA-10
assert_eq "u14_case_insensitive_ids" 0 "$RC"
state="$(new_state)"
readback "$TMP_ROOT/u14b.json" "$(read_json LEA-10 Released '["Release/V1.29.1"]')"
evaluate "$state" "$TMP_ROOT/u14b.json" LEA-10
assert_contains "u14_label_case_exact" "result=missing_label" "$OUT"

echo "=== U15: numeric scope identifier -> unsupported_identifier ==="
state="$(new_state)"
readback "$TMP_ROOT/u15.json" "$VERIFIED_10"
evaluate "$state" "$TMP_ROOT/u15.json" LEA-10 232
assert_eq "u15_exit" 1 "$RC"
assert_line "u15_unsupported" "LINEAR_RELEASE_ITEM issue=232 result=not_verified reasons=unsupported_identifier" "$OUT"
assert_not_contains "u15_label_seen_no_action" "LINEAR_RELEASE_LABEL_ACTION" "$OUT"
state="$(new_state)"
evaluate "$state" - 232
assert_line "u15_only_unsupported_teams_none" "LINEAR_RELEASE_LABEL_ACTION label=$LABEL teams=none action=create_label_in_owning_team_if_missing_then_apply" "$OUT"

echo "=== Usage errors ==="
state="$(new_state)"
evaluate "$state" - 'LEA-10 x'
assert_eq "usage_bad_scope" 2 "$RC"
evaluate "$state" -
assert_eq "usage_no_scope" 2 "$RC"
EVAL_NOW="soon" evaluate "$state" - LEA-10
assert_eq "usage_bad_now" 2 "$RC"

echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
[ "$FAIL_COUNT" -eq 0 ]

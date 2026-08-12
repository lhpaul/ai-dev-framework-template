#!/usr/bin/env bash
# test-security-advisory-tracker.sh - Unit tests for BR7 cross-push
# reconciliation and marker-comment persistence.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
TRACKER="$REPO_ROOT/scripts/development-workflow/security-advisory-tracker.sh"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
CALL_LOG="$TMP_ROOT/gh-calls.log"
mkdir -p "$MOCK_BIN"
: > "$CALL_LOG"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_GH_CALL_LOG"
case "$*" in
  auth\ status)
    exit 0
    ;;
  api\ --paginate\ --slurp\ repos/example/mobile-app/issues/42/comments\?per_page=100)
    if [ "${MOCK_COMMENT_MODE:-missing}" = "existing" ]; then
      cat <<'JSON'
[[{"id":321,"body":"<!-- security-sensitive-advisory-findings -->\nold"}]]
JSON
    else
      printf '[]\n'
    fi
    ;;
  api\ -X\ PATCH\ repos/example/mobile-app/issues/comments/321\ --input\ -)
    cat >/dev/null || true
    printf '{"id":321}\n'
    ;;
  api\ -X\ POST\ repos/example/mobile-app/issues/42/comments\ --input\ -)
    cat >/dev/null || true
    printf '{"id":555}\n'
    ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"
export PATH="$MOCK_BIN:$PATH"
export MOCK_GH_CALL_LOG="$CALL_LOG"
export WORKFLOW_TARGET_GITHUB_REPO="example/mobile-app"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '${expected}', got '${actual}'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_fails_contains() {
  local name="$1" expected="$2"
  shift 2
  local output status
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

write_json() {
  local name="$1" content="$2"
  local path="$TMP_ROOT/${name}.json"
  printf '%s' "$content" > "$path"
  printf '%s\n' "$path"
}

HEAD_A="1111111111111111111111111111111111111a"
HEAD_B="2222222222222222222222222222222222222b"
NOW="2026-08-12T02:00:00Z"

echo ""
echo "=== Security advisory tracker ==="

# --- CLI surface ---
run_fails_contains "requires_subcommand" "unknown subcommand" "$TRACKER" bogus
run_fails_contains "reconcile_requires_prior" "--prior is required" "$TRACKER" reconcile --current /dev/null --head-sha "$HEAD_A"
run_fails_contains "reconcile_requires_current" "--current is required" "$TRACKER" reconcile --prior none --head-sha "$HEAD_A"
run_fails_contains "reconcile_requires_head_sha" "--head-sha is required" "$TRACKER" reconcile --prior none --current /dev/null
run_fails_contains "render_requires_input" "--input is required" "$TRACKER" render
run_fails_contains "apply_requires_pr" "--pr must be a positive integer" "$TRACKER" apply --input /dev/null

# --- New entry: prior=none, one fresh finding -> pending entry with firstTrackedAt ---
current_new="$(write_json current-new '[{"id":"sec-aaa111","category":"c","matchedFile":"scripts/x.sh"}]')"
new_entry_result="$("$TRACKER" reconcile --prior none --current "$current_new" --head-sha "$HEAD_A" --now "$NOW")"
run_test "new_entry_status_pending" "pending" "$(printf '%s' "$new_entry_result" | jq -r '.[0].status')"
run_test "new_entry_head_sha" "$HEAD_A" "$(printf '%s' "$new_entry_result" | jq -r '.[0].headSha')"
run_test "new_entry_first_tracked_at" "$NOW" "$(printf '%s' "$new_entry_result" | jq -r '.[0].firstTrackedAt')"
run_test "new_entry_no_audit_reason" "null" "$(printf '%s' "$new_entry_result" | jq -r '.[0].auditReason // null')"
run_test "new_entry_count" "1" "$(printf '%s' "$new_entry_result" | jq 'length')"

# --- Same-push collision: two fresh findings sharing (category, matchedFile) ---
current_collision="$(write_json current-collision '[
  {"id":"sec-one","category":"c","matchedFile":"scripts/x.sh"},
  {"id":"sec-two","category":"c","matchedFile":"scripts/x.sh"}
]')"
collision_result="$("$TRACKER" reconcile --prior none --current "$current_collision" --head-sha "$HEAD_A" --now "$NOW")"
run_test "collision_two_distinct_entries" "2" "$(printf '%s' "$collision_result" | jq 'length')"
run_test "collision_ids_distinct" "sec-one sec-two" "$(printf '%s' "$collision_result" | jq -r '[.[].id] | join(" ")')"

# Shared prior-entry fixture builder for the three same-head/new-head/exit
# loops below: only the write_json label and assertions differ per loop, so
# the status-based extra_fields case logic and jq program live in one
# place, and $HEAD_A is passed via --arg rather than embedded interpolation.
make_prior_entry() {
  local status="$1" extra_fields="{}"
  case "$status" in
    fixed) extra_fields='{"fixCommit":"deadbeef"}' ;;
    human-accepted|human-rejected) extra_fields='{"decider":"lhpaul","decidedAt":"2026-08-01T00:00:00Z","rationale":"reviewed"}' ;;
  esac
  jq -c -n --arg status "$status" --arg headSha "$HEAD_A" --argjson extra "$extra_fields" \
    '{id:"sec-aaa111",category:"c",matchedFile:"scripts/x.sh",status:$status,headSha:$headSha,firstTrackedAt:"2026-08-01T00:00:00Z"} + $extra'
}

# --- Same-head reconciliation: idempotent for all four prior statuses ---
for status in pending fixed human-accepted human-rejected; do
  prior_entry="$(make_prior_entry "$status")"
  prior_file="$(write_json "prior-same-head-$status" "[$prior_entry]")"
  same_head_result="$("$TRACKER" reconcile --prior "$prior_file" --current "$current_new" --head-sha "$HEAD_A" --now "$NOW")"
  run_test "same_head_${status}_unchanged" "$prior_entry" "$(printf '%s' "$same_head_result" | jq -c '.[0]')"
done

# --- New-head reconciliation, still matches: reset to pending, cleared fields ---
for status in pending fixed human-accepted human-rejected; do
  prior_entry="$(make_prior_entry "$status")"
  prior_file="$(write_json "prior-new-head-$status" "[$prior_entry]")"
  new_head_result="$("$TRACKER" reconcile --prior "$prior_file" --current "$current_new" --head-sha "$HEAD_B" --now "$NOW")"
  run_test "new_head_${status}_resets_status" "pending" "$(printf '%s' "$new_head_result" | jq -r '.[0].status')"
  run_test "new_head_${status}_resets_head_sha" "$HEAD_B" "$(printf '%s' "$new_head_result" | jq -r '.[0].headSha')"
  run_test "new_head_${status}_audit_reason" "superseded_by_new_commit" "$(printf '%s' "$new_head_result" | jq -r '.[0].auditReason')"
  run_test "new_head_${status}_first_tracked_unchanged" "2026-08-01T00:00:00Z" "$(printf '%s' "$new_head_result" | jq -r '.[0].firstTrackedAt')"
  run_test "new_head_${status}_no_fix_commit" "null" "$(printf '%s' "$new_head_result" | jq -r '.[0].fixCommit // null')"
  run_test "new_head_${status}_no_decider" "null" "$(printf '%s' "$new_head_result" | jq -r '.[0].decider // null')"
  run_test "new_head_${status}_no_decided_at" "null" "$(printf '%s' "$new_head_result" | jq -r '.[0].decidedAt // null')"
  run_test "new_head_${status}_no_rationale" "null" "$(printf '%s' "$new_head_result" | jq -r '.[0].rationale // null')"
done

# --- New-head reconciliation, no longer matches: exits tracking entirely ---
current_empty="$(write_json current-empty '[]')"
for status in pending fixed human-accepted human-rejected; do
  prior_entry="$(make_prior_entry "$status")"
  prior_file="$(write_json "prior-exit-$status" "[$prior_entry]")"
  exit_result="$("$TRACKER" reconcile --prior "$prior_file" --current "$current_empty" --head-sha "$HEAD_B" --now "$NOW")"
  run_test "no_longer_matching_${status}_exits_tracking" "0" "$(printf '%s' "$exit_result" | jq 'length')"
done

# --- File-rename scenario: old path exits, new path is a fresh pending entry ---
prior_rename="$(write_json prior-rename '[{"id":"sec-aaa111","category":"c","matchedFile":"scripts/old-name.sh","status":"pending","headSha":"'"$HEAD_A"'","firstTrackedAt":"2026-08-01T00:00:00Z"}]')"
current_rename="$(write_json current-rename '[{"id":"sec-bbb222","category":"c","matchedFile":"scripts/new-name.sh"}]')"
rename_result="$("$TRACKER" reconcile --prior "$prior_rename" --current "$current_rename" --head-sha "$HEAD_B" --now "$NOW")"
run_test "rename_produces_exactly_one_fresh_entry" "1" "$(printf '%s' "$rename_result" | jq 'length')"
run_test "rename_fresh_entry_is_new_path" "scripts/new-name.sh" "$(printf '%s' "$rename_result" | jq -r '.[0].matchedFile')"
run_test "rename_fresh_entry_is_pending" "pending" "$(printf '%s' "$rename_result" | jq -r '.[0].status')"

# --- Interop: --current accepts raw security-advisory-classifier.sh
# `classify` output unchanged (matchedCategory, not category) without
# breaking cross-push matching by key -- planted-violation proof: before
# this fix, a --current entry with only matchedCategory keyed on an empty
# category and rendered category:null in the reconciled output.
current_classifier_shape="$(write_json current-classifier-shape '[{"id":"sec-aaa111","matchedCategory":"c","matchedFile":"scripts/x.sh"}]')"
classifier_shape_result="$("$TRACKER" reconcile --prior none --current "$current_classifier_shape" --head-sha "$HEAD_A" --now "$NOW")"
run_test "classifier_shape_current_normalizes_category" "c" "$(printf '%s' "$classifier_shape_result" | jq -r '.[0].category')"
run_test "classifier_shape_current_keys_by_normalized_category" "1" "$(printf '%s' "$classifier_shape_result" | jq 'length')"

# --- Decision events: resolve a matching pending entry ---
prior_pending="$(write_json prior-pending '[{"id":"sec-one","category":"c","matchedFile":"scripts/x.sh","status":"pending","headSha":"'"$HEAD_A"'","firstTrackedAt":"2026-08-01T00:00:00Z"}]')"
current_one="$(write_json current-one '[{"id":"sec-one","category":"c","matchedFile":"scripts/x.sh"}]')"
events_one="$(write_json events-one '[{"findingId":"sec-one","decision":"human-accepted","decider":"lhpaul","decidedAt":"2026-08-12T01:00:00Z","rationale":"acceptable risk","sourceEventId":"12345","sourceEventType":"issue_comment"}]')"
decision_result="$("$TRACKER" reconcile --prior "$prior_pending" --current "$current_one" --head-sha "$HEAD_A" --decision-events "$events_one" --now "$NOW")"
run_test "decision_event_resolves_status" "human-accepted" "$(printf '%s' "$decision_result" | jq -r '.[0].status')"
run_test "decision_event_resolves_decider" "lhpaul" "$(printf '%s' "$decision_result" | jq -r '.[0].decider')"
run_test "decision_event_resolves_decided_at" "2026-08-12T01:00:00Z" "$(printf '%s' "$decision_result" | jq -r '.[0].decidedAt')"
run_test "decision_event_resolves_rationale" "acceptable risk" "$(printf '%s' "$decision_result" | jq -r '.[0].rationale')"

# --- Decision events: non-pending entries and non-matching events unaffected ---
prior_fixed_only="$(write_json prior-fixed-only '[{"id":"sec-one","category":"c","matchedFile":"scripts/x.sh","status":"fixed","headSha":"'"$HEAD_A"'","firstTrackedAt":"2026-08-01T00:00:00Z","fixCommit":"deadbeef"}]')"
non_matching_events="$(write_json events-non-matching '[{"findingId":"sec-does-not-exist","decision":"human-accepted","decider":"lhpaul","decidedAt":"2026-08-12T01:00:00Z","rationale":"n/a","sourceEventId":"1","sourceEventType":"issue_comment"}]')"
unaffected_result="$("$TRACKER" reconcile --prior "$prior_fixed_only" --current "$current_one" --head-sha "$HEAD_A" --decision-events "$non_matching_events" --now "$NOW")"
run_test "non_pending_entry_unaffected_by_decision_events" "fixed" "$(printf '%s' "$unaffected_result" | jq -r '.[0].status')"

# --- Decision events: conflicting duplicate findingId fails closed ---
events_conflict="$(write_json events-conflict '[
  {"findingId":"sec-one","decision":"human-accepted","decider":"lhpaul","decidedAt":"2026-08-12T01:00:00Z","rationale":"acceptable risk","sourceEventId":"12345","sourceEventType":"issue_comment"},
  {"findingId":"sec-one","decision":"human-rejected","decider":"otheruser","decidedAt":"2026-08-12T01:05:00Z","rationale":"false positive","sourceEventId":"67890","sourceEventType":"issue_comment"}
]')"
conflict_stderr="$("$TRACKER" reconcile --prior "$prior_pending" --current "$current_one" --head-sha "$HEAD_A" --decision-events "$events_conflict" --now "$NOW" 2>&1 >/dev/null)"
conflict_stdout="$("$TRACKER" reconcile --prior "$prior_pending" --current "$current_one" --head-sha "$HEAD_A" --decision-events "$events_conflict" --now "$NOW" 2>/dev/null)"
run_test "conflicting_events_leave_entry_pending" "pending" "$(printf '%s' "$conflict_stdout" | jq -r '.[0].status')"
run_test "conflicting_events_warns_with_finding_id" "yes" "$(grep -q 'sec-one' <<< "$conflict_stderr" && echo yes || echo no)"
run_test "conflicting_events_warns_with_source_event_ids" "yes" "$(grep -q '12345' <<< "$conflict_stderr" && grep -q '67890' <<< "$conflict_stderr" && echo yes || echo no)"
run_test "conflicting_events_agreeing_still_fails_closed" "yes" "$(
  events_agree="$(write_json events-agree '[
    {"findingId":"sec-one","decision":"human-accepted","decider":"lhpaul","decidedAt":"2026-08-12T01:00:00Z","rationale":"a","sourceEventId":"1","sourceEventType":"issue_comment"},
    {"findingId":"sec-one","decision":"human-accepted","decider":"lhpaul","decidedAt":"2026-08-12T01:00:00Z","rationale":"a","sourceEventId":"2","sourceEventType":"issue_comment"}
  ]')"
  agree_status="$("$TRACKER" reconcile --prior "$prior_pending" --current "$current_one" --head-sha "$HEAD_A" --decision-events "$events_agree" --now "$NOW" 2>/dev/null | jq -r '.[0].status')"
  [ "$agree_status" = "pending" ] && echo yes || echo no
)"

# --- render: distinct entries render with real content ---
render_input="$(write_json render-input '[
  {"id":"sec-one","category":"c","matchedFile":"scripts/x.sh","status":"pending","headSha":"'"$HEAD_A"'","firstTrackedAt":"2026-08-01T00:00:00Z"},
  {"id":"sec-two","category":"a","matchedFile":"scripts/y.sh","status":"human-accepted","headSha":"'"$HEAD_A"'","firstTrackedAt":"2026-08-01T00:00:00Z","decider":"lhpaul","decidedAt":"2026-08-12T01:00:00Z","rationale":"low risk, isolated fallback path"},
  {"id":"sec-three","category":"b","matchedFile":"scripts/z.sh","status":"fixed","headSha":"'"$HEAD_A"'","firstTrackedAt":"2026-08-01T00:00:00Z","fixCommit":"deadbeefcafe"}
]')"
rendered="$("$TRACKER" render --input "$render_input")"
run_test "render_contains_marker" "yes" "$(grep -qF '<!-- security-sensitive-advisory-findings -->' <<< "$rendered" && echo yes || echo no)"
run_test "render_contains_heading" "yes" "$(grep -qF '## Security-Sensitive Advisory Findings' <<< "$rendered" && echo yes || echo no)"
run_test "render_contains_decider" "yes" "$(grep -qF 'lhpaul' <<< "$rendered" && echo yes || echo no)"
run_test "render_contains_rationale" "yes" "$(grep -qF 'low risk, isolated fallback path' <<< "$rendered" && echo yes || echo no)"
run_test "render_contains_fix_commit" "yes" "$(grep -qF 'deadbeefcafe' <<< "$rendered" && echo yes || echo no)"

empty_render_input="$(write_json render-empty '[]')"
empty_rendered="$("$TRACKER" render --input "$empty_render_input")"
run_test "render_empty_none_currently_tracked" "yes" "$(grep -qF 'None currently tracked.' <<< "$empty_rendered" && echo yes || echo no)"

# --- apply: creates when no marker exists, updates when marker exists ---
apply_input="$(write_json apply-input '[{"id":"sec-one","category":"c","matchedFile":"scripts/x.sh","status":"pending","headSha":"'"$HEAD_A"'","firstTrackedAt":"2026-08-01T00:00:00Z"}]')"
apply_created_output="$(MOCK_COMMENT_MODE=missing "$TRACKER" apply --input "$apply_input" --pr 42)"
run_test "apply_creates_when_no_marker" "CREATED_COMMENT=1" "$apply_created_output"

apply_updated_output="$(MOCK_COMMENT_MODE=existing "$TRACKER" apply --input "$apply_input" --pr 42)"
run_test "apply_updates_when_marker_exists" "UPDATED_COMMENT_ID=321" "$apply_updated_output"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi

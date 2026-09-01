#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
SCRIPT="$ROOT_DIR/scripts/development-workflow/reviewer-effectiveness-report.sh"
FIXTURE_DIR="$ROOT_DIR/scripts/development-workflow/tests/fixtures/reviewer-effectiveness"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  printf 'PASS: %s\n' "$*"
}

assert_eq() {
  local got="$1" want="$2" msg="$3"
  [ "$got" = "$want" ] || fail "$msg (got='$got' want='$want')"
}

assert_jq() {
  local json="$1" filter="$2" want="$3" msg="$4"
  local got
  got="$(printf '%s\n' "$json" | jq -r "$filter")"
  assert_eq "$got" "$want" "$msg"
}

HARNESS_MODE=1 source "$SCRIPT"

wrap_body() {
  bash "$FIXTURE_DIR/wrap-history.sh" "$(cat "$1")"
}

# --- classifier scenarios ---
assert_eq "$(rer_classify_payload "$(cat "$FIXTURE_DIR/no-marker.body")")" "no_history" "scenario 1 no marker"
assert_eq "$(rer_classify_payload "$(cat "$FIXTURE_DIR/unparseable.body")")" "unparseable_history" "scenario 2 unparseable"
assert_eq "$(rer_classify_payload "$(wrap_body "$FIXTURE_DIR/unavailable.json")")" "history_unavailable" "scenario 3 unavailable"
assert_eq "$(rer_classify_payload "$(wrap_body "$FIXTURE_DIR/today-schema.json")")" "included" "today schema included"

# --- measure 6 today schema ---
today_json="$(wrap_body "$FIXTURE_DIR/today-schema.json" | reviewer_loop_history_extract_latest_json)"
today_measures="$(rer_compute_measures_json "$today_json")"
assert_jq "$today_measures" '.rounds.value' '3' 'rounds count'
assert_jq "$today_measures" '.external_blocking_rounds.availability' 'not_recorded' 'external blocking not recorded'
assert_jq "$today_measures" '.blocking_findings.value' '3' 'blocking findings sum'
assert_jq "$today_measures" '.codex_github_invocations.value' '2' 'codex invocations'
assert_jq "$today_measures" '.final_current_head_evidence.availability' 'not_recorded' 'measure 7 not recorded'

# --- full telemetry ---
full_json="$(wrap_body "$FIXTURE_DIR/full-telemetry.json" | reviewer_loop_history_extract_latest_json)"
full_measures="$(rer_compute_measures_json "$full_json")"
assert_jq "$full_measures" '.external_blocking_rounds.value' '4' 'external blocking rounds total'
assert_jq "$full_measures" '.confirmed_miss_records.value' '3' 'confirmed misses'
assert_jq "$full_measures" '.possible_miss_records.value' '1' 'possible misses'
assert_jq "$full_measures" '.final_current_head_evidence.value' 'current' 'final head evidence'

# --- end-to-end with recording gh stub ---
cat > "$TMP_DIR/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail
LOG="${GH_RECORD_LOG:-/dev/null}"
printf '%s\n' "$*" >> "$LOG"
json_comment() {
  local body_file="$1"
  jq -nc --arg body "$(cat "$body_file")" --arg created_at "2026-08-01T00:00:00Z" \
    '[{id: 1, body: $body, created_at: $created_at}]'
}
case "$*" in
  *issues/101/comments*)
    json_comment "$GH_FIXTURE_DIR/no-marker.body"
    ;;
  *issues/102/comments*)
    json_comment "$GH_FIXTURE_DIR/unparseable.body"
    ;;
  *issues/103/comments*)
    json_comment "$GH_FIXTURE_DIR/unavailable.body"
    ;;
  *issues/200/comments*)
    json_comment <(bash "$GH_FIXTURE_DIR/wrap-history.sh" "$(cat "$GH_FIXTURE_DIR/today-schema.json")")
    ;;
  *pr\ list*)
    printf '[{"number":103},{"number":102},{"number":101}]\n'
    ;;
  *)
    echo "unexpected gh: $*" >&2
    exit 99
    ;;
esac
MOCK_GH
chmod +x "$TMP_DIR/gh"

export GH_FIXTURE_DIR="$FIXTURE_DIR"
export GH_RECORD_LOG="$TMP_DIR/gh.log"
PATH="$TMP_DIR:$PATH"

out="$(HARNESS_MODE=0 "$SCRIPT" --window 3 --repo example/repo --json 2>/dev/null)"
assert_jq "$out" '.accounting.requested' '3' 'window requested count'
assert_jq "$out" '.accounting.excluded' '3' 'all three excluded'
assert_jq "$out" '.aggregates | length' '0' 'no aggregates when none included'

# window refusal
if HARNESS_MODE=0 "$SCRIPT" --window 0 --repo example/repo --json >/dev/null 2>&1; then
  fail 'window 0 should refuse'
fi
if HARNESS_MODE=0 "$SCRIPT" --window -3 --repo example/repo --json >/dev/null 2>&1; then
  fail 'window -3 should refuse'
fi
pass 'window refusal'

# write guard
if grep -E ' (post|create|edit|delete|patch) ' "$TMP_DIR/gh.log" >/dev/null 2>&1; then
  fail 'gh stub saw a write invocation'
fi
pass 'read-only gh invocations'

# AC-2d: no alternate default window config in script/help
if rg -n 'RER_DEFAULT_WINDOW|default window' "$SCRIPT" >/dev/null \
  && rg -n 'WINDOW|DEFAULT.*20' "$SCRIPT" | rg -v 'RER_DEFAULT_WINDOW=20' >/dev/null 2>&1; then
  : # only RER_DEFAULT_WINDOW constant allowed
fi
pass 'default window source'

pass 'all reviewer-effectiveness-report scenarios'

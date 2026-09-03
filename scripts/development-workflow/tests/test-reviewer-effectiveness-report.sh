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

assert_contains() {
  local text="$1" pattern="$2" msg="$3"
  printf '%s\n' "$text" | grep -Fq "$pattern" || fail "$msg"
}

assert_not_contains() {
  local text="$1" pattern="$2" msg="$3"
  if printf '%s\n' "$text" | grep -Fq "$pattern"; then
    fail "$msg"
  fi
}

# shellcheck source=scripts/development-workflow/reviewer-effectiveness-report.sh
HARNESS_MODE=1 source "$SCRIPT"

wrap_body() {
  bash "$FIXTURE_DIR/wrap-history.sh" "$(cat "$1")"
}

# --- classifier scenarios ---
assert_eq "$(rer_classify_payload "$(cat "$FIXTURE_DIR/no-marker.body")")" "no_history" "scenario 1 no marker"
assert_eq "$(rer_classify_payload "$(cat "$FIXTURE_DIR/unparseable.body")")" "unparseable_history" "scenario 2 unparseable"
assert_eq "$(rer_classify_payload "$(cat "$FIXTURE_DIR/malformed-json.body")")" "unparseable_history" "malformed json is unparseable not unavailable"
assert_eq "$(rer_classify_payload "$(wrap_body "$FIXTURE_DIR/unavailable.json")")" "history_unavailable" "scenario 3 unavailable"
assert_eq "$(rer_classify_payload "$(wrap_body "$FIXTURE_DIR/today-schema.json")")" "included" "today schema included"
large_marked_body="$(wrap_body "$FIXTURE_DIR/today-schema.json")"
printf -v large_marked_padding '%70000s' ''
large_marked_body="${large_marked_body}${large_marked_padding}"
assert_eq "$(rer_classify_payload "$large_marked_body")" "included" "large marked body included"

# --- measure 6 today schema ---
today_json="$(wrap_body "$FIXTURE_DIR/today-schema.json" | reviewer_loop_history_extract_latest_json)"
today_measures="$(rer_compute_measures_json "$today_json")"
assert_jq "$today_measures" '.rounds.value' '3' 'rounds count'
assert_jq "$today_measures" '.external_blocking_rounds.availability' 'not_recorded' 'external blocking not recorded'
assert_jq "$today_measures" '.blocking_findings.value' '3' 'blocking findings sum'
assert_jq "$today_measures" '.codex_github_invocations.value' '2' 'codex invocations'
assert_jq "$today_measures" '.final_current_head_evidence.availability' 'not_recorded' 'measure 7 not recorded'

deferred_codex_json="$(jq -nc '
  {
    schema: "reviewer_loop_history.v1",
    pr_number: 101,
    history_status: "available",
    entries: [
      {
        iteration: 1,
        platforms: ["local-ai-reviewer (clean)", "codex-github (deferred (baseline_checks_pending))"],
        platform_results: [{platform: "local-ai-reviewer", result: "clean"}],
        blocking_count: 0
      },
      {
        iteration: 2,
        platforms: ["local-ai-reviewer (clean)", "codex-github (needs_fixes)"],
        platform_results: [
          {platform: "local-ai-reviewer", result: "clean"},
          {platform: "codex-github", result: "needs_fixes"}
        ],
        blocking_count: 1
      }
    ]
  }
')"
deferred_measures="$(rer_compute_measures_json "$deferred_codex_json")"
assert_jq "$deferred_measures" '.codex_github_invocations.value' '1' 'deferred codex gate is not an invocation'
assert_jq "$deferred_measures" '.external_blocking_rounds.value' '1' 'external blocking rounds count platform needs_fixes'

external_without_attribution_json="$(jq -nc '
  {
    schema: "reviewer_loop_history.v1",
    pr_number: 102,
    history_status: "available",
    entries: [
      {
        iteration: 1,
        platforms: ["local-ai-reviewer (clean)", "codex-github (needs_fixes)"],
        platform_results: [
          {platform: "local-ai-reviewer", result: "clean"},
          {platform: "codex-github", result: "needs_fixes"}
        ],
        missed_findings: [],
        blocking_count: 2
      }
    ]
  }
')"
external_without_attribution_measures="$(rer_compute_measures_json "$external_without_attribution_json")"
assert_jq "$external_without_attribution_measures" '.external_blocking_rounds.value' '1' 'external blockers do not require attribution records'

mixed_history_json="$(jq -nc '
  {
    schema: "reviewer_loop_history.v1",
    pr_number: 103,
    history_status: "available",
    entries: [
      {
        iteration: 1,
        platforms: ["local-ai-reviewer", "codex-github"],
        missed_findings: [{reviewer: "codex-github"}],
        blocking_count: 1
      },
      {
        iteration: 2,
        platforms: ["local-ai-reviewer (clean)", "codex-github (clean)"],
        platform_results: [
          {platform: "local-ai-reviewer", result: "clean"},
          {platform: "codex-github", result: "clean"}
        ],
        blocking_count: 0
      }
    ]
  }
')"
mixed_history_measures="$(rer_compute_measures_json "$mixed_history_json")"
assert_jq "$mixed_history_measures" '.external_blocking_rounds.value' '1' 'mixed legacy and platform-result history preserves legacy external blockers'

# --- full telemetry ---
full_json="$(wrap_body "$FIXTURE_DIR/full-telemetry.json" | reviewer_loop_history_extract_latest_json)"
full_measures="$(rer_compute_measures_json "$full_json")"
assert_jq "$full_measures" '.external_blocking_rounds.value' '4' 'external blocking rounds count rounds with findings'
assert_jq "$full_measures" '.confirmed_miss_records.value' '3' 'confirmed misses'
assert_jq "$full_measures" '.possible_miss_records.value' '1' 'possible misses'
assert_jq "$full_measures" '.final_current_head_evidence.value' 'current' 'final head evidence'

# --- strict checks incidence ---
full_row="$(jq -nc --argjson pr 200 --arg state included --argjson measures "$full_measures" --argjson payload "$full_json" \
  '{pr:$pr, state:$state, measures:$measures, _payload:$payload}')"
full_rows_json="$(printf '%s\n' "$full_row" | jq -s '.')"
strict="$(rer_strict_checks_json "$full_rows_json")"
assert_jq "$strict" '.checks[] | select(.check=="spec-ac-1") | .fired' '1' 'spec check fired once per PR'
assert_jq "$strict" '.checks[] | select(.check=="plan-ac-1") | .fired' '1' 'plan check fired once per PR'
assert_jq "$strict" '.checks[] | select(.check=="plan-ac-1") | .applied' '1' 'plan check applied denominator'

spec_zero_json="$(jq -nc '
  {
    schema: "reviewer_loop_history.v1",
    pr_number: 201,
    history_status: "available",
    entries: [
      {
        iteration: 1,
        platforms: ["local-ai-reviewer"],
        blocking_count: 0,
        strict_spec: {state: "applied", count: 0, checks: [], applied: ["ac_consistency"]}
      }
    ]
  }
')"
spec_zero_measures="$(rer_compute_measures_json "$spec_zero_json")"
spec_zero_row="$(jq -nc --argjson pr 201 --arg state included --argjson measures "$spec_zero_measures" --argjson payload "$spec_zero_json" \
  '{pr:$pr, state:$state, measures:$measures, _payload:$payload}')"
spec_zero_rows_json="$(printf '%s\n' "$spec_zero_row" | jq -s '.')"
spec_zero_strict="$(rer_strict_checks_json "$spec_zero_rows_json")"
assert_jq "$spec_zero_strict" '.checks[] | select(.check=="ac_consistency") | .kind' 'spec' 'zero-firing spec check is listed'
assert_jq "$spec_zero_strict" '.checks[] | select(.check=="ac_consistency") | .fired' '0' 'zero-firing spec check reports zero fired'
assert_jq "$spec_zero_strict" '.checks[] | select(.check=="ac_consistency") | .applied' '1' 'zero-firing spec check keeps applied denominator'
assert_jq "$spec_zero_strict" '[.checks[] | select(.kind=="spec")] | length' '1' 'recorded spec applied set avoids live-catalogue backfill'

# --- partial telemetry: mixed field availability and measure 7 last entry ---
partial_json="$(wrap_body "$FIXTURE_DIR/partial-telemetry.json" | reviewer_loop_history_extract_latest_json)"
partial_measures="$(rer_compute_measures_json "$partial_json")"
assert_jq "$partial_measures" '.rounds.value' '5' 'partial rounds counts all entries'
assert_jq "$partial_measures" '.external_blocking_rounds.value' '2' 'partial external rounds count rounds with findings'
assert_jq "$partial_measures" '.confirmed_miss_records.value' '1' 'partial confirmed from later rounds'
assert_jq "$partial_measures" '.possible_miss_records.value' '1' 'partial possible from later rounds'
assert_jq "$partial_measures" '.final_current_head_evidence.availability' 'computed' 'measure7 available from last entry field'
assert_jq "$partial_measures" '.final_current_head_evidence.value' 'not-reported' 'measure7 reads last entry only'

partial_row="$(jq -nc --argjson pr 300 --arg state included --argjson measures "$partial_measures" --argjson payload "$partial_json" \
  '{pr:$pr, state:$state, measures:$measures, _payload:$payload}')"
partial_rows_json="$(printf '%s\n' "$partial_row" | jq -s '.')"
assert_jq "$(rer_aggregate_measure "$partial_rows_json" "external_blocking_rounds")" '.included' '1' 'partial aggregate denominator for telemetry measure'
assert_jq "$(rer_aggregate_measure "$partial_rows_json" "rounds")" '.included' '1' 'partial aggregate denominator for rounds'

# --- AC-2: --pr and window row equivalence (mock gh for PR 200) ---
cat > "$TMP_DIR/gh" <<'MOCK_EQUIV'
#!/usr/bin/env bash
set -euo pipefail
json_comment() {
  jq -nc --arg body "$(cat "$1")" --arg created_at "2026-08-01T00:00:00Z" \
    '[{id: 1, body: $body, created_at: $created_at}]'
}
case "$*" in
  *issues/200/comments*)
    json_comment <(bash "$GH_FIXTURE_DIR/wrap-history.sh" "$(cat "$GH_FIXTURE_DIR/full-telemetry.json")")
    ;;
  *pr\ list*)
    printf '[{"number":200}]\n'
    ;;
  *) echo "unexpected gh equiv: $*" >&2; exit 99 ;;
esac
MOCK_EQUIV
chmod +x "$TMP_DIR/gh"
export GH_FIXTURE_DIR="$FIXTURE_DIR"
single_out="$(PATH="$TMP_DIR:$PATH" HARNESS_MODE=0 "$SCRIPT" --pr 200 --repo example/repo --json 2>/dev/null)"
window_out="$(PATH="$TMP_DIR:$PATH" HARNESS_MODE=0 "$SCRIPT" --window 1 --repo example/repo --json 2>/dev/null)"
single_measures="$(printf '%s\n' "$single_out" | jq -c '.rows[0].measures')"
window_measures="$(printf '%s\n' "$window_out" | jq -c '.rows[0].measures')"
assert_eq "$single_measures" "$window_measures" 'single PR and window measures match'

# --- selector agreement with loop (scenario 22) ---
body_file="$FIXTURE_DIR/full-telemetry.body"
[ -f "$body_file" ] || bash "$FIXTURE_DIR/wrap-history.sh" "$(cat "$FIXTURE_DIR/full-telemetry.json")" > "$body_file"
comments_json="$(jq -nc --arg body "$(cat "$body_file")" --arg created_at "2026-08-01T12:00:00Z" \
  '[{id:1, body:$body, created_at:$created_at}]')"
loop_record="$(printf '%s\n' "$comments_json" | reviewer_loop_history_select_latest_summary_record)"
report_record="$(printf '%s\n' "$comments_json" | reviewer_loop_history_select_latest_summary_record)"
assert_eq "$(printf '%s\n' "$loop_record" | jq -c .)" "$(printf '%s\n' "$report_record" | jq -c .)" 'selector agrees between callers'

# --- not_recorded never renders as 0 in text ---
cat > "$TMP_DIR/gh" <<'MOCK_TEXT'
#!/usr/bin/env bash
set -euo pipefail
json_comment() {
  jq -nc --arg body "$(bash "$GH_FIXTURE_DIR/wrap-history.sh" "$(cat "$GH_FIXTURE_DIR/today-schema.json")")" \
    --arg created_at "2026-08-01T00:00:00Z" '[{id:1, body:$body, created_at:$created_at}]'
}
case "$*" in
  *issues/201/comments*) json_comment ;;
  *pr\ list*) printf '[{"number":201}]\n' ;;
  *) exit 99 ;;
esac
MOCK_TEXT
chmod +x "$TMP_DIR/gh"
today_text="$(PATH="$TMP_DIR:$PATH" HARNESS_MODE=0 "$SCRIPT" --pr 201 --repo example/repo 2>/dev/null)"
assert_not_contains "$today_text" 'External blocking rounds: 0' 'not_recorded not rendered as zero'
assert_contains "$today_text" 'External blocking rounds: Not recorded' 'not_recorded rendered as word'

today_json_out="$(PATH="$TMP_DIR:$PATH" HARNESS_MODE=0 "$SCRIPT" --pr 201 --repo example/repo --json 2>/dev/null)"
assert_jq "$today_json_out" '[.aggregates[] | select(.measure == "external_blocking_rounds")] | length' '0' 'omit aggregate for not_recorded measure'
assert_jq "$today_json_out" '[.aggregates[] | select(.measure == "rounds")] | length' '1' 'include aggregate for computed measure'
assert_jq "$today_json_out" '.rows[0] | has("_payload")' 'false' 'JSON output omits internal payload'

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

# AC-2d: no alternate default window configuration in script/help
forbidden_window_sources="$(rg -n '\b(WINDOW_SIZE|REPORT_WINDOW|DEFAULT_PR_WINDOW|RER_.*WINDOW)\b' "$SCRIPT" 2>/dev/null \
  | rg -v 'RER_DEFAULT_WINDOW' || true)"
if [ -n "$forbidden_window_sources" ]; then
  fail "found alternate default-window sources:${forbidden_window_sources}"
fi
pass 'default window source'

pass 'all reviewer-effectiveness-report scenarios'

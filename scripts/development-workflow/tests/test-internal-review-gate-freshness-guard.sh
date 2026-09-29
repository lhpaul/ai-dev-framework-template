#!/usr/bin/env bash
# test-internal-review-gate-freshness-guard.sh - disposable Git coverage for
# the internal-review-gate-freshness-guard.sh planted-violation proof.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
GUARD="$REPO_ROOT/scripts/development-workflow/internal-review-gate-freshness-guard.sh"
TMP_ROOT="$(mktemp -d)"
REAL_GIT="$(command -v git)"
PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  local status=$?
  rm -rf "$TMP_ROOT"
  case "$status" in
    141) exit 0 ;;
    *) exit "$status" ;;
  esac
}
trap cleanup EXIT

run_test() {
  local name="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    printf 'PASS: %s\n' "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf "FAIL: %s - expected '%s', got '%s'\n" "$name" "$expected" "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_contains() {
  local name="$1" expected="$2" actual="$3"
  if grep -Fq -- "$expected" <<< "$actual"; then
    printf 'PASS: %s\n' "$name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    printf "FAIL: %s - expected output to contain '%s'\n" "$name" "$expected"
    printf 'Actual output:\n%s\n' "$actual"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

guard_output() {
  local status output
  set +e
  output="$("$GUARD" "$@" 2>&1)"
  status=$?
  set -e
  printf '%s\n%s\n' "$status" "$output"
}

status_code() {
  head -n 1 <<< "$1"
}

body() {
  tail -n +2 <<< "$1"
}

field() {
  local key="$1" output="$2"
  sed -n "s/^${key}=//p" <<< "$output" | head -n 1
}

repo="$TMP_ROOT/repo"
"$REAL_GIT" init -q -b develop "$repo"
"$REAL_GIT" -C "$repo" config user.email test@example.com
"$REAL_GIT" -C "$repo" config user.name Test

printf 'line one\nline two\n' > "$repo/notes.md"
"$REAL_GIT" -C "$repo" add notes.md
"$REAL_GIT" -C "$repo" commit -q -m "initial"
gate_sha="$("$REAL_GIT" -C "$repo" rev-parse HEAD)"

# --- Case 1: gate SHA equals HEAD (gate just ran) -> pass/fresh ---
out="$(guard_output --gate-sha "$gate_sha" --head-sha "$gate_sha" --repo-root "$repo")"
run_test "fresh_head_matches_gate_exit" "0" "$(status_code "$out")"
run_test "fresh_head_matches_gate_result" "pass" "$(field RESULT "$(body "$out")")"
run_test "fresh_head_matches_gate_reason" "fresh" "$(field REASON "$(body "$out")")"

# --- Case 2 (planted violation): a substantial post-gate content commit with
# no MECHANICAL_DELTA marker and >10 changed lines -> readiness refused,
# naming the stale gate SHA. This is the "plant a post-gate content commit"
# half of the guard test the issue requires. ---
{
  i=1
  while [ "$i" -le 20 ]; do
    printf 'new substantive line %s\n' "$i"
    i=$((i + 1))
  done
} >> "$repo/notes.md"
"$REAL_GIT" -C "$repo" add notes.md
"$REAL_GIT" -C "$repo" commit -q -m "rewrite design section with new concurrency addendum"
head_sha="$("$REAL_GIT" -C "$repo" rev-parse HEAD)"

out="$(guard_output --gate-sha "$gate_sha" --head-sha "$head_sha" --repo-root "$repo")"
run_test "stale_gate_evidence_exit" "1" "$(status_code "$out")"
run_test "stale_gate_evidence_result" "refused" "$(field RESULT "$(body "$out")")"
run_test "stale_gate_evidence_reason" "stale_gate_evidence" "$(field REASON "$(body "$out")")"
run_contains "stale_gate_evidence_names_stale_sha" "$gate_sha" "$(body "$out")"

# --- Case 3 (proof the check clears once fixed): "re-run the gate at HEAD"
# -> assert readiness passes with an empty diff on the guard. ---
out="$(guard_output --gate-sha "$head_sha" --head-sha "$head_sha" --repo-root "$repo")"
run_test "gate_rerun_at_head_exit" "0" "$(status_code "$out")"
run_test "gate_rerun_at_head_result" "pass" "$(field RESULT "$(body "$out")")"
run_test "gate_rerun_at_head_reason" "fresh" "$(field REASON "$(body "$out")")"
run_test "gate_rerun_at_head_lines" "0" "$(field LINES_CHANGED "$(body "$out")")"

# --- Case 4: an explicitly mechanical delta (marked + <=10 lines) is allowed
# without a fresh gate re-run. ---
printf 'typo fx\n' >> "$repo/notes.md"
"$REAL_GIT" -C "$repo" add notes.md
"$REAL_GIT" -C "$repo" commit -q -m "fix typo in notes

MECHANICAL_DELTA: single-word spelling correction, no structural change"
mechanical_head_sha="$("$REAL_GIT" -C "$repo" rev-parse HEAD)"

out="$(guard_output --gate-sha "$head_sha" --head-sha "$mechanical_head_sha" --repo-root "$repo")"
run_test "mechanical_delta_exit" "0" "$(status_code "$out")"
run_test "mechanical_delta_result" "pass" "$(field RESULT "$(body "$out")")"
run_test "mechanical_delta_reason" "mechanical_delta_verified" "$(field REASON "$(body "$out")")"

# --- Case 5: marker present but the delta exceeds the mechanical line bound
# -> still refused. Independent verification, not bare self-certification. ---
{
  i=1
  while [ "$i" -le 20 ]; do
    printf 'another substantive line %s\n' "$i"
    i=$((i + 1))
  done
} >> "$repo/notes.md"
"$REAL_GIT" -C "$repo" add notes.md
"$REAL_GIT" -C "$repo" commit -q -m "large rewrite claiming mechanical

MECHANICAL_DELTA: false claim, this is actually a large rewrite"
oversized_head_sha="$("$REAL_GIT" -C "$repo" rev-parse HEAD)"

out="$(guard_output --gate-sha "$mechanical_head_sha" --head-sha "$oversized_head_sha" --repo-root "$repo")"
run_test "oversized_marked_delta_exit" "1" "$(status_code "$out")"
run_test "oversized_marked_delta_result" "refused" "$(field RESULT "$(body "$out")")"
run_test "oversized_marked_delta_reason" "stale_gate_evidence" "$(field REASON "$(body "$out")")"

# --- Case 6: invalid gate SHA -> invalid_input, exit 64 ---
out="$(guard_output --gate-sha "0000000000000000000000000000000000dead" --head-sha "$head_sha" --repo-root "$repo")"
run_test "invalid_gate_sha_exit" "64" "$(status_code "$out")"
run_test "invalid_gate_sha_reason" "invalid_input" "$(field REASON "$(body "$out")")"

# --- Case 7: gate SHA not an ancestor of HEAD (diverged history) ---
"$REAL_GIT" -C "$repo" checkout -q -b diverged "$gate_sha"
printf 'diverged content\n' >> "$repo/other.md"
"$REAL_GIT" -C "$repo" add other.md
"$REAL_GIT" -C "$repo" commit -q -m "diverged branch commit"
diverged_sha="$("$REAL_GIT" -C "$repo" rev-parse HEAD)"

out="$(guard_output --gate-sha "$diverged_sha" --head-sha "$mechanical_head_sha" --repo-root "$repo")"
run_test "not_ancestor_exit" "1" "$(status_code "$out")"
run_test "not_ancestor_reason" "gate_sha_not_ancestor" "$(field REASON "$(body "$out")")"

printf '\n%s passed, %s failed\n' "$PASS_COUNT" "$FAIL_COUNT"
if [ "$FAIL_COUNT" -gt 0 ]; then
  exit 1
fi
exit 0

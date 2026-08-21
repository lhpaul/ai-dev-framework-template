#!/usr/bin/env bash
# test-batch-merge-changelog-race.sh - Regression tests for issue #1516:
# PR_HAS_CHANGELOG (and sibling label checks) were flaky under
# `set -o pipefail` because `producer | grep -q needle` closes the pipe as
# soon as grep finds its match, which can SIGPIPE a producer that still has
# buffered output left to write. Bash's pipefail exit-status rule then
# reports the pipeline as failed even though grep itself found (and would
# have reported) a match — a false negative that only reproduces when the
# producer still has output queued at the moment grep exits, which is why it
# was originally observed as an intermittent failure (see PR #1507).
#
# This suite has two parts:
#   Part 1 reproduces the underlying shell mechanism in isolation (no
#   dependency on batch-merge.sh) to establish that the race is real and
#   that "capture full output first, then match in pure bash" removes it.
#   The producer intentionally floods the pipe with far more data than any
#   common kernel pipe buffer holds (macOS: 16-64 KB; Linux default: 64 KB)
#   so the race reproduces on effectively every run rather than "sometimes"
#   — this is what makes the assertion below deterministic rather than a
#   flaky coin flip.
#
#   Part 2/3/4 exercise the actual shipped batch-merge.sh (as a real
#   subprocess, via a mocked `gh`) with the same kind of adversarial,
#   oversized payload, and assert PR_HAS_CHANGELOG / PR_READY_LABEL /
#   PR_HAS_NEEDS_FIXES / PR_HAS_HUMAN_CHECKPOINT are correct on every one of
#   several repeated runs. A "control" pattern that mirrors the original
#   buggy `jq | grep -q` / `gh pr diff | grep -q` shape is run against the
#   exact same mock to prove the payload really is adversarial (i.e. that a
#   naive re-introduction of the old pattern would be caught by this test).
#
# Honesty note on confidence: this is a race condition, and POSIX makes no
# absolute scheduling guarantee. What is deterministic here is the *setup*
# (the producer is forced to have megabytes of unread output queued the
# instant grep -q exits after matching line 1), which was 100% reproducible
# (10/10, repeated across many manual runs during development, both directly
# and via this suite) on this environment. If this suite ever starts
# reporting spurious buggy-pattern successes on some CI runner, the most
# likely explanation is a pipe buffer configured far larger than any
# platform this repo targets, not that the underlying race stopped existing.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
HELPER="$REPO_ROOT/scripts/development-workflow/batch-merge.sh"

TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
FIXTURE_DIR="$TMP_ROOT/fixtures"
mkdir -p "$MOCK_BIN" "$FIXTURE_DIR"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

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

# ---------------------------------------------------------------------------
# Part 1: SIGPIPE-under-pipefail race mechanism proof (self-contained; does
# not touch batch-merge.sh).
# ---------------------------------------------------------------------------

echo ""
echo "=== Part 1: race mechanism proof (buggy shape vs. fixed shape) ==="

# Writes the match on line 1, then floods the pipe with ~1.1 MB of filler so
# grep -q's early exit (right after matching line 1) reliably happens while
# the producer still has output queued.
#
# Deliberately does NOT guard the inner `yes | head` pipeline with `|| true`:
# doing so was measured (during development of this test) to change bash's
# process-exec strategy for the tail command of this function body enough to
# eliminate the very race this function exists to reproduce. This function
# is only ever invoked from inside an explicit `( fn )` subshell guarded by
# `if !`, both below, so its own `set -e` exposure is already contained —
# see _buggy_pattern_matches / _fixed_pattern_matches.
_race_mechanism_producer() {
  printf 'CHANGELOG.md\n'
  yes 'scripts/filler-padding-line-to-exceed-the-kernel-pipe-buffer.sh' | head -n 20000
}

# Mirrors the *original* buggy shape from batch-merge.sh (pre-#1516):
#   if gh pr diff --name-only "$pr_num" 2>/dev/null | grep -q '^CHANGELOG\.md$'; then
_buggy_pattern_matches() {
  set -o pipefail
  _race_mechanism_producer | grep -q '^CHANGELOG\.md$'
}

# Mirrors the shipped fix's helper (duplicated here, deliberately, so this
# part of the suite stays independent of the file under test and proves the
# *mechanism*, not just "the file parses").
_test_list_has_exact_line() {
  local needle="$1" haystack="$2"
  case $'\n'"$haystack"$'\n' in
    *$'\n'"$needle"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

_fixed_pattern_matches() {
  set -o pipefail
  local files
  files="$(_race_mechanism_producer)"
  _test_list_has_exact_line 'CHANGELOG.md' "$files"
}

buggy_false_negatives=0
fixed_false_negatives=0
mechanism_iterations=10
for _ in $(seq 1 "$mechanism_iterations"); do
  if ! (_buggy_pattern_matches); then
    buggy_false_negatives=$((buggy_false_negatives + 1))
  fi
  if ! (_fixed_pattern_matches); then
    fixed_false_negatives=$((fixed_false_negatives + 1))
  fi
done

echo "  buggy pattern:  ${buggy_false_negatives}/${mechanism_iterations} runs produced a false negative"
echo "  fixed pattern:  ${fixed_false_negatives}/${mechanism_iterations} runs produced a false negative"

run_test "buggy_pattern_reproduces_false_negative" "yes" "$([ "$buggy_false_negatives" -gt 0 ] && echo yes || echo no)"
run_test "fixed_pattern_never_produces_false_negative" "0" "$fixed_false_negatives"

# ---------------------------------------------------------------------------
# Fixtures for Parts 2-4: mocked `gh` driving the real batch-merge.sh.
# ---------------------------------------------------------------------------

# PR 9001: CHANGELOG.md race payload for `gh pr diff --name-only`.
{
  printf 'CHANGELOG.md\n'
  yes 'scripts/filler-padding-line-to-exceed-the-kernel-pipe-buffer.sh' | head -n 20000 || true
} > "$FIXTURE_DIR/pr9001-diff.txt"

cat > "$FIXTURE_DIR/pr9001-view.json" <<'JSON'
{"number":9001,"title":"changelog race PR","headRefName":"fix/9001-race","headRefOid":"1111111111111111111111111111111111111a","baseRefName":"develop","labels":[{"name":"ready-for-human-review"}],"createdAt":"2026-08-20T00:00:00Z","isDraft":false}
JSON

# PR 9002: genuine `gh pr diff` failure (must not be reported the same as
# "CHANGELOG.md not in diff").
cat > "$FIXTURE_DIR/pr9002-view.json" <<'JSON'
{"number":9002,"title":"gh pr diff failure PR","headRefName":"fix/9002-diff-fail","headRefOid":"2222222222222222222222222222222222222b","baseRefName":"develop","labels":[{"name":"ready-for-human-review"}],"createdAt":"2026-08-20T00:01:00Z","isDraft":false}
JSON

# PR 9003: label-list race payload for `gh pr view` (jq streams one label
# name per line; ~550 KB of filler labels after the real one).
jq -n '
  (["ready-for-human-review"] + ([range(0;30000)] | map("filler-label-" + (. | tostring)))) as $names
  | {
      number: 9003,
      title: "labels race PR",
      headRefName: "fix/9003-race",
      headRefOid: "3333333333333333333333333333333333333c",
      baseRefName: "develop",
      labels: ($names | map({name: .})),
      createdAt: "2026-08-20T00:02:00Z",
      isDraft: false
    }
' > "$FIXTURE_DIR/pr9003-view.json"

cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
case "$*" in
  auth\ status)
    exit 0
    ;;
  pr\ view\ 9001\ --json\ number,title,headRefName,headRefOid,baseRefName,labels,createdAt,isDraft)
    cat "$FIXTURE_DIR/pr9001-view.json"
    ;;
  pr\ diff\ --name-only\ 9001)
    cat "$FIXTURE_DIR/pr9001-diff.txt"
    ;;
  pr\ view\ 9002\ --json\ number,title,headRefName,headRefOid,baseRefName,labels,createdAt,isDraft)
    cat "$FIXTURE_DIR/pr9002-view.json"
    ;;
  pr\ diff\ --name-only\ 9002)
    printf 'simulated network failure fetching diff\n' >&2
    exit 1
    ;;
  pr\ view\ 9003\ --json\ number,title,headRefName,headRefOid,baseRefName,labels,createdAt,isDraft)
    cat "$FIXTURE_DIR/pr9003-view.json"
    ;;
  pr\ diff\ --name-only\ 9003)
    printf 'scripts/harmless-file.sh\n'
    ;;
  pr\ view\ 9010\ --json\ headRefName,state,isCrossRepository,headRepository,headRepositoryOwner)
    printf '{"headRefName":"fix/9010-already-gone","state":"MERGED","isCrossRepository":false}\n'
    ;;
  pr\ view\ 9011\ --json\ headRefName,state,isCrossRepository,headRepository,headRepositoryOwner)
    printf '{"headRefName":"fix/9011-genuine-failure","state":"MERGED","isCrossRepository":false}\n'
    ;;
  *)
    printf 'unexpected gh invocation: gh %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GH
chmod +x "$MOCK_BIN/gh"
export PATH="$MOCK_BIN:$PATH"
export FIXTURE_DIR

# ---------------------------------------------------------------------------
# Part 2: PR_HAS_CHANGELOG — control (buggy shape fails against this exact
# mock) + shipped script (must never fail against the same mock).
# ---------------------------------------------------------------------------

echo ""
echo "=== Part 2: PR_HAS_CHANGELOG via the real gh mock (PR #9001) ==="

# Control: this mirrors the exact pre-#1516 line
# (`gh pr diff --name-only "$pr_num" 2>/dev/null | grep -q '^CHANGELOG\.md$'`)
# run against the *same* mock and payload used to exercise the shipped
# script below. If this control ever stops failing, the payload has stopped
# being adversarial for this platform and the test needs a bigger payload —
# it is not evidence that the original bug pattern is safe.
_control_buggy_diff_check() {
  local pr_num="9001"
  set -o pipefail
  gh pr diff --name-only "$pr_num" 2>/dev/null | grep -q '^CHANGELOG\.md$'
}

control_false_negatives=0
control_iterations=10
for _ in $(seq 1 "$control_iterations"); do
  if ! (_control_buggy_diff_check); then
    control_false_negatives=$((control_false_negatives + 1))
  fi
done
echo "  control (pre-#1516 shape): ${control_false_negatives}/${control_iterations} false negatives against PR #9001's mock diff"
run_test "control_buggy_diff_check_reproduces_false_negative" "yes" "$([ "$control_false_negatives" -gt 0 ] && echo yes || echo no)"

changelog_true_count=0
changelog_iterations=10
for _ in $(seq 1 "$changelog_iterations"); do
  out="$("$HELPER" discover --prs 9001 2>/dev/null)"
  val="$(awk -F= '$1=="PR_HAS_CHANGELOG"{print $2; exit}' <<< "$out")"
  [ "$val" = "true" ] && changelog_true_count=$((changelog_true_count + 1))
done
echo "  shipped batch-merge.sh: ${changelog_true_count}/${changelog_iterations} runs correctly reported PR_HAS_CHANGELOG=true"
run_test "shipped_script_never_false_negatives_on_changelog" "$changelog_iterations" "$changelog_true_count"

# ---------------------------------------------------------------------------
# Part 3: PR_READY_LABEL / PR_HAS_NEEDS_FIXES / PR_HAS_HUMAN_CHECKPOINT — same
# treatment for the sibling `jq -r '.labels[].name' | grep -q` call sites.
# ---------------------------------------------------------------------------

echo ""
echo "=== Part 3: label checks via the real gh mock (PR #9003, ~30k labels) ==="

_control_buggy_label_check() {
  set -o pipefail
  gh pr view 9003 --json number,title,headRefName,headRefOid,baseRefName,labels,createdAt,isDraft 2>/dev/null \
    | jq -r '.labels[].name' \
    | grep -q '^ready-for-human-review$'
}

control_label_false_negatives=0
for _ in $(seq 1 "$control_iterations"); do
  if ! (_control_buggy_label_check); then
    control_label_false_negatives=$((control_label_false_negatives + 1))
  fi
done
echo "  control (pre-#1516 shape): ${control_label_false_negatives}/${control_iterations} false negatives against PR #9003's mock labels"
run_test "control_buggy_label_check_reproduces_false_negative" "yes" "$([ "$control_label_false_negatives" -gt 0 ] && echo yes || echo no)"

label_true_count=0
needs_fixes_false_count=0
checkpoint_false_count=0
label_iterations=10
for _ in $(seq 1 "$label_iterations"); do
  out="$("$HELPER" discover --prs 9003 2>/dev/null)"
  ready_val="$(awk -F= '$1=="PR_READY_LABEL"{print $2; exit}' <<< "$out")"
  needs_fixes_val="$(awk -F= '$1=="PR_HAS_NEEDS_FIXES"{print $2; exit}' <<< "$out")"
  checkpoint_val="$(awk -F= '$1=="PR_HAS_HUMAN_CHECKPOINT"{print $2; exit}' <<< "$out")"
  [ "$ready_val" = "true" ] && label_true_count=$((label_true_count + 1))
  [ "$needs_fixes_val" = "false" ] && needs_fixes_false_count=$((needs_fixes_false_count + 1))
  [ "$checkpoint_val" = "false" ] && checkpoint_false_count=$((checkpoint_false_count + 1))
done
echo "  shipped batch-merge.sh: ${label_true_count}/${label_iterations} runs correctly reported PR_READY_LABEL=true"
run_test "shipped_script_never_false_negatives_on_ready_label" "$label_iterations" "$label_true_count"
run_test "shipped_script_correctly_reports_no_needs_fixes_label" "$label_iterations" "$needs_fixes_false_count"
run_test "shipped_script_correctly_reports_no_checkpoint_label" "$label_iterations" "$checkpoint_false_count"

# ---------------------------------------------------------------------------
# Part 4: a genuine `gh pr diff` failure must not be reported identically to
# "CHANGELOG.md legitimately absent from the diff" (acceptance criterion:
# do not simply swallow the error).
# ---------------------------------------------------------------------------

echo ""
echo "=== Part 4: genuine gh pr diff failure is surfaced, not swallowed (PR #9002) ==="

diff_failure_output="$("$HELPER" discover --prs 9002 2>&1)"
diff_failure_changelog_val="$(awk -F= '$1=="PR_HAS_CHANGELOG"{print $2; exit}' <<< "$diff_failure_output")"
run_test "diff_failure_still_reports_has_changelog_false" "false" "$diff_failure_changelog_val"
run_test "diff_failure_is_surfaced_not_silently_swallowed" "yes" "$(grep -q 'gh pr diff failed for PR #9002' <<< "$diff_failure_output" && echo yes || echo no)"

# ---------------------------------------------------------------------------
# Part 5: cmd_delete_branch's push_err match (also touched by this fix, via
# `tr` instead of `grep -qi`) still classifies "already gone" vs. "genuine
# failure" correctly, including with a multi-line, mixed-case stderr
# payload. `tr` does not early-exit, so this is a correctness check rather
# than a race repro, but it confirms the refactor did not change behavior.
# NOTE: the filler payload here is intentionally small (~15 lines). A large
# multi-thousand-line value hits an unrelated, pre-existing quadratic-time
# issue in workflow-lib.sh's print_kv_escaped (repeated `${value//$'\n'/...}`
# global substitution on a string with many newlines) that is out of scope
# for #1516 — see this PR's description.
# ---------------------------------------------------------------------------

echo ""
echo "=== Part 5: cmd_delete_branch push_err classification (git mock) ==="

cat > "$MOCK_BIN/git" <<'MOCK_GIT'
#!/usr/bin/env bash
case "$*" in
  push\ origin\ --delete\ fix/9010-already-gone)
    {
      yes 'remote: filler padding line for the delete-branch push error test' | head -n 15
      printf 'error: unable to delete '"'"'fix/9010-already-gone'"'"': remote ref does NOT Exist\n'
    } >&2
    exit 1
    ;;
  push\ origin\ --delete\ fix/9011-genuine-failure)
    {
      yes 'remote: filler padding line for the delete-branch push error test' | head -n 15
      printf 'error: permission denied to push to origin\n'
    } >&2
    exit 1
    ;;
  *)
    printf 'unexpected git invocation: git %s\n' "$*" >&2
    exit 64
    ;;
esac
MOCK_GIT
chmod +x "$MOCK_BIN/git"

not_found_output="$("$HELPER" delete-branch --pr 9010 2>&1)"
run_test "delete_branch_classifies_already_gone_as_not_found" "not_found" "$(awk -F= '$1=="DELETE_RESULT"{print $2; exit}' <<< "$not_found_output")"

set +e
genuine_failure_output="$("$HELPER" delete-branch --pr 9011 2>&1)"
genuine_failure_status=$?
set -e
run_test "delete_branch_classifies_genuine_failure_as_skipped_exit" "2" "$genuine_failure_status"
run_test "delete_branch_genuine_failure_message_present" "yes" "$(grep -q 'permission denied' <<< "$genuine_failure_output" && echo yes || echo no)"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi

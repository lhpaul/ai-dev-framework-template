#!/usr/bin/env bash
# test-item-completion-followups.sh - follow-up disposition rows of the
# completion self-check (#1331): deferred follow-ups must stay open and must
# not be closed by the PR; fixed ones are enumerated as eligible to close.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/scripts/development-workflow/item-completion-self-check.sh"
TMP_ROOT="$(mktemp -d)"
MOCK_BIN="$TMP_ROOT/bin"
PASS_COUNT=0
FAIL_COUNT=0
trap 'rm -rf "$TMP_ROOT"' EXIT

mkdir -p "$MOCK_BIN"
cat > "$MOCK_BIN/gh" <<'MOCK_GH'
#!/usr/bin/env bash
# Minimal gh double. Issue states come from MOCK_ISSUE_<N>; the PR body from
# MOCK_PR_BODY; MOCK_FAIL_ISSUES / MOCK_FAIL_PR_BODY simulate read failures.
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  n="$3"
  if [ "${MOCK_FAIL_ISSUES:-}" = "1" ]; then echo "issue read failed" >&2; exit 1; fi
  var="MOCK_ISSUE_$n"
  printf '%s\n' "${!var:-OPEN}"
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  if [ "${MOCK_FAIL_PR_BODY:-}" = "1" ]; then echo "pr read failed" >&2; exit 1; fi
  case "$*" in
    *--jq*) printf '%s\n' "${MOCK_PR_BODY:-}" ;;
    *) printf '%s\n' '{"number":7,"baseRefName":"develop","headRefName":"fix/1331-followups","isDraft":false,"labels":[],"files":[],"statusCheckRollup":[],"comments":[]}' ;;
  esac
  exit 0
fi
echo "unexpected gh invocation: gh $*" >&2
exit 64
MOCK_GH
chmod +x "$MOCK_BIN/gh"
export PATH="$MOCK_BIN:$PATH"
export WORKFLOW_TARGET_GITHUB_REPO="example/repo"
export WORKFLOW_SELF_CHECK_TRACKER_STATUS="In Development"

repo="$TMP_ROOT/repo"
mkdir -p "$repo"
git init -q -b develop "$repo"
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name Test
printf 'base\n' > "$repo/README.md"
git -C "$repo" add README.md
git -C "$repo" commit -q -m init
git -C "$repo" switch -q -c fix/1331-followups
repo="$(CDPATH='' cd -- "$repo" && pwd -P)"

check() {
  local status output
  set +e
  output="$("$HELPER" --repo-root "$repo" --issue 1331 --branch fix/1331-followups \
    --stage implementation --worktree-path "$repo" --require-ci-green false "$@" 2>&1)"
  status=$?
  set -e
  printf '%s\n%s\n' "$status" "$output"
}

expect_status() {
  local name="$1" want="$2" out="$3" got
  got="$(head -n 1 <<< "$out")"
  if [ "$got" = "$want" ]; then echo "PASS: $name"; PASS_COUNT=$((PASS_COUNT + 1))
  else echo "FAIL: $name - expected exit $want, got $got"; tail -n +2 <<< "$out"; FAIL_COUNT=$((FAIL_COUNT + 1)); fi
}

expect_row() {
  local name="$1" row="$2" out="$3"
  if grep -Fq -- "$row" <<< "$out"; then echo "PASS: $name"; PASS_COUNT=$((PASS_COUNT + 1))
  else echo "FAIL: $name - missing '$row'"; tail -n +2 <<< "$out"; FAIL_COUNT=$((FAIL_COUNT + 1)); fi
}

echo ""
echo "=== item completion self-check: follow-up disposition ==="

# Happy path: one fixed (closed by PR), one deferred (open, not closed).
export MOCK_PR_BODY=$'Fixes the thing.\n\nCloses #1331\nSee also #1895 (deferred).'
out="$(check --pr 7 --followup 1894=fixed --followup 1895=deferred)"
expect_status "mixed_dispositions_pass" 0 "$out"
expect_row "fixed_enumerated" "| followup.#1894 | verified | fixed in this PR; eligible to close on merge; closing keyword absent |" "$out"
expect_row "deferred_enumerated" "| followup.#1895 | verified | deferred to future PR; open; not closed by PR (closing keyword absent) |" "$out"

# Planted violation: PR body closes a deferred follow-up.
export MOCK_PR_BODY=$'Closes #1331\nCloses #1895'
out="$(check --pr 7 --followup 1895=deferred)"
expect_status "deferred_closed_by_pr_body_blocks" 1 "$out"
expect_row "deferred_closed_by_pr_body_row" "| followup.#1895 | discrepancy | deferred but PR body closes it with a closing keyword |" "$out"

# Closing keyword variants and cross-repo form are all caught.
for body in 'fixes #1895' 'Resolved: #1895' 'closed example/repo#1895'; do
  export MOCK_PR_BODY="$body"
  out="$(check --pr 7 --followup 1895=deferred)"
  expect_status "keyword_variant_blocks: $body" 1 "$out"
done

# A longer issue number sharing the prefix is not a match.
export MOCK_PR_BODY='Closes #18950'
out="$(check --pr 7 --followup 1895=deferred)"
expect_status "prefix_number_not_matched" 0 "$out"

# Planted violation: deferred issue is already closed.
export MOCK_PR_BODY='Closes #1331'
export MOCK_ISSUE_1895=CLOSED
out="$(check --pr 7 --followup 1895=deferred)"
expect_status "deferred_closed_issue_blocks" 1 "$out"
expect_row "deferred_closed_issue_row" "| followup.#1895 | discrepancy | deferred but state=CLOSED; must remain open |" "$out"
unset MOCK_ISSUE_1895

# Unreadable evidence is not treated as a pass.
export MOCK_FAIL_ISSUES=1
out="$(check --pr 7 --followup 1895=deferred)"
expect_status "unreadable_issue_state_blocks" 1 "$out"
expect_row "unreadable_issue_state_row" "| followup.#1895 | unavailable_required |" "$out"
unset MOCK_FAIL_ISSUES
export MOCK_FAIL_PR_BODY=1
out="$(check --pr 7 --followup 1895=deferred)"
expect_status "unreadable_pr_body_blocks" 1 "$out"
unset MOCK_FAIL_PR_BODY

# Without a PR the deferred issue is still checked for open state.
out="$(check --followup 1895=deferred)"
expect_status "no_pr_deferred_open_passes" 0 "$out"
expect_row "no_pr_keyword_unknown" "closing keyword unknown" "$out"

# Without --followup nothing is added.
out="$(check --pr 7)"
expect_status "no_followup_flag_passes" 0 "$out"
if grep -Fq "followup." <<< "$out"; then echo "FAIL: no_followup_rows_absent"; FAIL_COUNT=$((FAIL_COUNT + 1))
else echo "PASS: no_followup_rows_absent"; PASS_COUNT=$((PASS_COUNT + 1)); fi

# Malformed values are rejected up front.
for bad in 1895 abc=deferred 1895=maybe 1895= =deferred "1a=fixed"; do
  out="$(check --followup "$bad")"
  expect_status "malformed_rejected: $bad" 64 "$out"
done

echo ""
echo "=== Results ==="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ]

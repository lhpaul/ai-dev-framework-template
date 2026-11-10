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
if [ "$1" = "repo" ] && [ "$2" = "view" ]; then
  if [ "${MOCK_FAIL_HUB:-}" = "1" ]; then echo "repo view failed" >&2; exit 1; fi
  # Distinct checkout identities: the product checkout reports the product
  # repository, every other directory (the hub/tooling checkout) the tracker.
  if [ -n "${MOCK_PRODUCT_CHECKOUT:-}" ] && [ "$(pwd -P)" = "$MOCK_PRODUCT_CHECKOUT" ]; then
    printf 'example/product\n'
  else
    printf 'example/repo\n'
  fi
  exit 0
fi
if [ "$1" = "issue" ] && [ "$2" = "view" ]; then
  n="$3"
  if [ "${MOCK_FAIL_ISSUES:-}" = "1" ]; then echo "issue read failed" >&2; exit 1; fi
  var="MOCK_ISSUE_$n"
  case "$*" in *"--repo example/product"*) var="MOCK_PRODUCT_ISSUE_$n" ;; esac
  printf '%s\n' "${!var:-OPEN}"
  exit 0
fi
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  if [ "${MOCK_FAIL_PR_BODY:-}" = "1" ]; then echo "pr read failed" >&2; exit 1; fi
  case "$*" in
    *commits*--jq*)
      if [ "${MOCK_PR_COMMITS_LARGE:-}" = "1" ]; then
        # Generated here, not exported: a ~500 KB environment string would
        # exceed the per-string exec limit on Linux CI.
        seq 20000 60000 | sed 's/^/Closes #/'
        printf 'Closes #1895\n'
      else
        printf '%s\n' "${MOCK_PR_COMMITS:-}"
      fi
      ;;
    *--jq*) printf '%s\n' "${MOCK_PR_BODY:-}" ;;
    *) printf '%s\n' '{"number":7,"baseRefName":"develop","headRefName":"fix/1331-followups","isDraft":false,"labels":[],"files":[],"statusCheckRollup":[],"comments":[]}' ;;
  esac
  exit 0
fi
echo "unexpected gh invocation: gh $*" >&2
exit 64
MOCK_GH
chmod +x "$MOCK_BIN/gh"
# python3 shim so a closing-keyword scan failure can be simulated.
export REAL_PY
REAL_PY="$(command -v python3)"
cat > "$MOCK_BIN/python3" <<'SHIM'
#!/usr/bin/env bash
case "$*" in
  *strip_inline_code_spans*)
    if [ "${MOCK_FAIL_PY:-}" = "1" ]; then echo "python failed" >&2; exit 1; fi
    ;;
esac
exec "$REAL_PY" "$@"
SHIM
chmod +x "$MOCK_BIN/python3"
export PATH="$MOCK_BIN:$PATH"
unset WORKFLOW_TARGET_GITHUB_REPO
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
  output="$(cd "${CHECK_CWD:-.}" && "$HELPER" --repo-root "$repo" --issue 1331 --branch fix/1331-followups \
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
expect_row "deferred_closed_by_pr_body_row" "| followup.#1895 | discrepancy | deferred but PR title, body or commit messages close it with a closing keyword |" "$out"

# Closing keyword variants and the qualified same-repo form are all caught.
for body in 'fixes #1895' '(Resolves issue #1895)' 'closed example/repo#1895'; do
  export MOCK_PR_BODY="$body"
  out="$(check --pr 7 --followup 1895=deferred)"
  expect_status "keyword_variant_blocks: $body" 1 "$out"
done

# Commit messages count (post-merge-cleanup reads them too).
export MOCK_PR_BODY='Closes #1331'
export MOCK_PR_COMMITS=$'fix: thing\n\nCloses #1895'
out="$(check --pr 7 --followup 1895=deferred)"
expect_status "deferred_closed_by_commit_blocks" 1 "$out"
unset MOCK_PR_COMMITS

# Not closing references: word-embedded keywords and fenced examples.
for body in 'hotfix #1895' 'disclose #1895' $'```\nCloses #1895\n```'; do
  export MOCK_PR_BODY="$body"
  out="$(check --pr 7 --followup 1895=deferred)"
  expect_status "not_a_closing_reference: ${body%%$'\n'*}" 0 "$out"
done

# Large closing-reference output must not turn a match into "absent" (grep -q
# under pipefail would SIGPIPE its writer).
export MOCK_PR_BODY='Closes #1331'
export MOCK_PR_COMMITS_LARGE=1
out="$(check --pr 7 --followup 1895=deferred)"
expect_status "large_reference_output_still_detects_match" 1 "$out"
expect_row "large_reference_output_row" "| followup.#1895 | discrepancy |" "$out"
unset MOCK_PR_COMMITS_LARGE

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

# A failed closing-keyword scan is not read as "no closing keyword".
export MOCK_PR_BODY='Closes #1331'
export MOCK_FAIL_PY=1
out="$(check --pr 7 --followup 1895=deferred)"
unset MOCK_FAIL_PY
expect_status "scan_failure_blocks" 1 "$out"
expect_row "scan_failure_row" "| followup.#1895 | unavailable_required |" "$out"

# Without a PR the closing-keyword proof is impossible: fail closed.
out="$(check --followup 1895=deferred)"
expect_status "no_pr_deferred_unproven_blocks" 1 "$out"
expect_row "no_pr_deferred_row" "| followup.#1895 | unavailable_required | deferred; open; closing keywords not checked because --pr was omitted |" "$out"
out="$(check --followup 1894=fixed)"
expect_status "no_pr_fixed_still_lists" 0 "$out"

# workflow_hub: follow-up numbers belong to the tracker (hub) repository,
# example/repo here; the PR lives in the product repository, example/product.
# The product repo's own issue #1895 (a trap) is OPEN throughout: reading it
# instead of the tracker's would hide a closed hub issue.
export WORKFLOW_TARGET_GITHUB_REPO="example/product"
# Run from the product checkout so a tracker lookup keyed on cwd would be wrong.
export MOCK_PRODUCT_CHECKOUT="$repo" CHECK_CWD="$repo"
export MOCK_PRODUCT_ISSUE_1895=OPEN
export MOCK_ISSUE_1895=CLOSED
export MOCK_PR_BODY='Closes #1331'
out="$(check --pr 7 --followup 1895=deferred)"
expect_status "hub_closed_tracker_issue_blocks" 1 "$out"
expect_row "hub_closed_row" "deferred but state=CLOSED" "$out"
unset MOCK_ISSUE_1895
export MOCK_PR_BODY=$'Closes #1331\nCloses example/repo#1895'
out="$(check --pr 7 --followup 1895=deferred)"
expect_status "hub_qualified_reference_blocks" 1 "$out"
export MOCK_PR_BODY='Closes #1895'
out="$(check --pr 7 --followup 1895=deferred)"
expect_status "hub_bare_reference_names_product_issue_passes" 0 "$out"
export MOCK_FAIL_HUB=1
out="$(check --pr 7 --followup 1895=deferred)"
expect_status "hub_unresolvable_blocks" 1 "$out"
expect_row "hub_unresolvable_row" "| followup.#1895 | unavailable_required | cannot resolve tracker repository" "$out"
unset MOCK_FAIL_HUB MOCK_PRODUCT_ISSUE_1895 MOCK_PRODUCT_CHECKOUT CHECK_CWD

# Same repository spelled with different case is still the same repository:
# a bare closing keyword must still count.
export WORKFLOW_TARGET_GITHUB_REPO="Example/Repo"
export MOCK_PR_BODY='Closes #1895'
out="$(check --pr 7 --followup 1895=deferred)"
expect_status "slug_case_difference_still_same_repo_blocks" 1 "$out"
unset WORKFLOW_TARGET_GITHUB_REPO

# Cleanup claim: run from the base checkout, naming the merged item branch.
git -C "$repo" switch -q develop
export MOCK_PR_BODY='Closes #1331'
out="$("$HELPER" --repo-root "$repo" --issue 1331 --branch fix/1331-followups --stage cleanup --worktree-path "$repo" --pr 7 --expected-base develop --require-ci-green false --followup 1895=deferred 2>&1; echo "rc=$?")"
if grep -Fq "| followup.#1895 | verified | deferred to future PR" <<< "$out" && ! grep -Fq "pull_request.head | discrepancy" <<< "$out"; then
  echo "PASS: cleanup_claim_shape_verifies_deferred_without_head_discrepancy"; PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "FAIL: cleanup_claim_shape_verifies_deferred_without_head_discrepancy"; echo "$out"; FAIL_COUNT=$((FAIL_COUNT + 1))
fi
git -C "$repo" switch -q fix/1331-followups

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

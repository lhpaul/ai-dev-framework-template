#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
HELPER="$REPO_ROOT/scripts/development-workflow/post-merge-cleanup.sh"
REAL_GIT="$(command -v git)"

PASS_COUNT=0
FAIL_COUNT=0
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '$expected', got '$actual'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_contains() {
  local name="$1"
  local needle="$2"
  local haystack="$3"

  if grep -Fq "$needle" <<<"$haystack"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected output to contain '$needle'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_fails_contains() {
  local name="$1"
  local needle="$2"
  shift 2
  local output status

  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  if [ "$status" -ne 0 ] && grep -Fq "$needle" <<<"$output"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected failure output to contain '$needle' (status $status)"
    printf '%s\n' "$output"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

write_gh_stub() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

args=" $* "

case "$1 $2" in
  "pr list")
    head=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --head)
          head="${2:-}"
          shift 2
          ;;
        *)
          shift
          ;;
      esac
    done
    if [ -n "${GH_PR_LIST_FAIL:-}" ]; then
      echo "mock pr list failure" >&2
      exit 1
    fi
    if [ "$head" = "${GH_MERGED_HEAD:-}" ] && [ -n "${GH_MERGED_PR:-}" ]; then
      if [[ "$args" == *"--jq"* ]]; then
        if [[ "$args" == *"isCrossRepository"* ]]; then
          printf '{"number":%s,"isCrossRepository":%s,"headRepository":{"name":"repo","owner":{"login":"owner"}},"headRepositoryOwner":{"login":"owner"}}\n' "$GH_MERGED_PR" "${GH_IS_CROSS_REPOSITORY:-false}"
        else
          printf '%s\n' "$GH_MERGED_PR"
        fi
      else
        printf '[{"number":%s,"isCrossRepository":%s}]\n' "$GH_MERGED_PR" "${GH_IS_CROSS_REPOSITORY:-false}"
      fi
    else
      if [[ "$args" == *"--jq"* ]]; then
        printf '\n'
      else
        printf '[]\n'
      fi
    fi
    ;;
  "pr view")
    pr_number="${3:-}"
    if [[ "$args" == *"--json number,state,headRefName,isCrossRepository"* ]]; then
      if [ "$pr_number" = "${GH_MERGED_PR:-}" ] && [ "${GH_PR_STATE:-MERGED}" = "MERGED" ] && [ "${GH_PR_HEAD_REF_NAME:-${GH_MERGED_HEAD:-}}" = "${GH_MERGED_HEAD:-}" ]; then
        printf '{"number":%s,"state":"%s","headRefName":"%s","isCrossRepository":%s,"headRepository":{"name":"repo","owner":{"login":"owner"}},"headRepositoryOwner":{"login":"owner"}}\n' \
          "$GH_MERGED_PR" \
          "${GH_PR_STATE:-MERGED}" \
          "${GH_PR_HEAD_REF_NAME:-${GH_MERGED_HEAD:-}}" \
          "${GH_IS_CROSS_REPOSITORY:-false}"
      else
        printf '\n'
      fi
    elif [[ "$args" == *"--json number,state,headRefName"* ]]; then
      if [ "$pr_number" = "${GH_MERGED_PR:-}" ]; then
        printf '{"number":%s,"state":"%s","headRefName":"%s"}\n' \
          "$GH_MERGED_PR" \
          "${GH_PR_STATE:-MERGED}" \
          "${GH_PR_HEAD_REF_NAME:-${GH_MERGED_HEAD:-}}"
      else
        printf '\n'
      fi
    elif [[ "$args" == *"--json state,baseRefName,headRefName"* ]]; then
      if [ "$pr_number" = "${GH_MERGED_PR:-}" ]; then
        printf 'develop\n'
      else
        printf '\n'
      fi
    elif [[ "$args" == *"--json commits"* ]]; then
      # Emulates '[.commits[] | ...] | join("\n")' — tests control it via
      # GH_PR_COMMITS_TEXT (already-joined text, may be empty).
      printf '%s\n' "${GH_PR_COMMITS_TEXT:-}"
    elif [[ "$args" == *"--json title "* || "$args" == *'--json title'* ]]; then
      if [ -n "${GH_PR_TITLE_FETCH_FAIL:-}" ]; then
        echo "mock pr view --json title failure" >&2
        exit 1
      fi
      printf '%s\n' "${GH_PR_TITLE:-}"
    elif [[ "$args" == *"--json body,title"* ]]; then
      # Emulates the real command's jq filter
      # '(.title // "") + "\n" + (.body // "")' without invoking jq, so tests
      # can control the PR title/body via GH_PR_TITLE / GH_PR_BODY.
      printf '%s\n%s' "${GH_PR_TITLE:-}" "${GH_PR_BODY:-}"
    elif [[ "$args" == *"--jq"* ]]; then
      printf '\n'
    else
      printf '{"body":"","title":""}\n'
    fi
    ;;
  "issue view")
    if [[ "$args" == *"--jq"* ]]; then
      printf '%s\n' "${GH_ISSUE_STATE:-CLOSED}"
    else
      printf '{"state":"%s"}\n' "${GH_ISSUE_STATE:-CLOSED}"
    fi
    ;;
  "issue close")
    printf 'closed\n'
    ;;
  *)
    echo "unexpected gh invocation: $*" >&2
    exit 1
    ;;
esac
STUB
  chmod +x "$dir/gh"
}

write_git_failure_stub() {
  local dir="$1"
  mkdir -p "$dir"
  cat >"$dir/git" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" = "push" ] && [ "${2:-}" = "origin" ] && [ "${3:-}" = "--delete" ] && [ "${4:-}" = "${GIT_FAIL_DELETE_BRANCH:-}" ]; then
  echo "permission denied deleting ${4}" >&2
  exit 1
fi

exec "$REAL_GIT" "$@"
STUB
  chmod +x "$dir/git"
}

make_repo() {
  local name="$1"
  local branch="$2"
  local push_branch="${3:-yes}"
  local bare="$TMP_ROOT/${name}.git"
  local repo="$TMP_ROOT/$name"

  "$REAL_GIT" init --bare -q -b develop "$bare"
  "$REAL_GIT" init -q -b develop "$repo"
  "$REAL_GIT" -C "$repo" config user.email "fixture@example.com"
  "$REAL_GIT" -C "$repo" config user.name "Fixture User"
  printf 'base\n' >"$repo/README.md"
  "$REAL_GIT" -C "$repo" add README.md
  "$REAL_GIT" -C "$repo" commit -q -m "initial base"
  "$REAL_GIT" -C "$repo" remote add origin "$bare"
  "$REAL_GIT" -C "$repo" push -q -u origin develop
  "$REAL_GIT" -C "$repo" checkout -q -b "$branch"
  printf 'branch\n' >"$repo/branch.txt"
  "$REAL_GIT" -C "$repo" add branch.txt
  "$REAL_GIT" -C "$repo" commit -q -m "branch fixture"
  if [ "$push_branch" = "yes" ]; then
    "$REAL_GIT" -C "$repo" push -q -u origin "$branch"
  fi
  "$REAL_GIT" -C "$repo" checkout -q develop
  printf '%s\n' "$repo"
}

stub_bin="$TMP_ROOT/bin"
write_gh_stub "$stub_bin"

merged_branch="feature/noissue-cleanup"
merged_repo="$(make_repo merged "$merged_branch" yes)"
merged_output="$(
  GH_MERGED_HEAD="$merged_branch" \
  GH_MERGED_PR=77 \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$merged_repo" --base develop --pr 77 "$merged_branch"
)"
run_contains "merged_implementation_remote_deleted" "REMOTE_DELETE_RESULT=deleted" "$merged_output"
run_contains "merged_implementation_records_pr" "REMOTE_DELETE_PR_NUMBER=77" "$merged_output"
run_test "merged_implementation_remote_ref_absent" "" "$("$REAL_GIT" -C "$merged_repo" ls-remote --heads origin "$merged_branch")"

absent_branch="feature/noissue-already-absent"
absent_repo="$(make_repo absent "$absent_branch" no)"
absent_output="$(
  GH_MERGED_HEAD="$absent_branch" \
  GH_MERGED_PR=78 \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$absent_repo" --base develop --pr 78 "$absent_branch"
)"
run_contains "already_absent_remote_is_successful" "REMOTE_DELETE_RESULT=not_found" "$absent_output"
run_contains "already_absent_remote_status" "REMOTE_DELETE_STATUS=already_absent" "$absent_output"

unmerged_branch="feature/noissue-unmerged"
unmerged_repo="$(make_repo unmerged "$unmerged_branch" yes)"
run_fails_contains \
  "unmerged_implementation_skips_remote_delete" \
  "REMOTE_DELETE_REASON=pr_number_required" \
  env WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$HELPER" --repo-root "$unmerged_repo" --base develop "$unmerged_branch"
run_test "unmerged_remote_ref_still_exists" "yes" "$(
  if "$REAL_GIT" -C "$unmerged_repo" ls-remote --heads origin "$unmerged_branch" | grep -q .; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

unmerged_before_local_head="$("$REAL_GIT" -C "$unmerged_repo" rev-parse HEAD)"
unmerged_before_branch_sha="$("$REAL_GIT" -C "$unmerged_repo" rev-parse "refs/heads/$unmerged_branch")"
set +e
unmerged_no_mutation_output="$(
  env WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$HELPER" --repo-root "$unmerged_repo" --base develop "$unmerged_branch" 2>&1
)"
set -e
unmerged_after_local_head="$("$REAL_GIT" -C "$unmerged_repo" rev-parse HEAD)"
unmerged_after_branch_sha="$("$REAL_GIT" -C "$unmerged_repo" rev-parse "refs/heads/$unmerged_branch")"

# Regression coverage for the no-mutation property: the pr_number_required
# guard must fire before any fetch/checkout/pull/local-delete runs. Asserts
# both that the "Fetching origin..." banner (printed immediately before the
# first mutating git command) never appears, and that the local develop HEAD
# and the target branch's local ref are byte-identical before and after the
# failing invocation. A future refactor that moved the guard back below the
# mutating work would make this fail.
run_test "unmerged_guard_fires_before_fetch" "no" "$(
  if grep -Fq "Fetching origin..." <<<"$unmerged_no_mutation_output"; then
    printf 'yes'
  else
    printf 'no'
  fi
)"
run_test "unmerged_guard_local_develop_head_unchanged" "$unmerged_before_local_head" "$unmerged_after_local_head"
run_test "unmerged_guard_local_branch_ref_unchanged" "$unmerged_before_branch_sha" "$unmerged_after_branch_sha"

fork_branch="feature/noissue-fork-pr"
fork_repo="$(make_repo fork "$fork_branch" yes)"
fork_output="$(
  GH_MERGED_HEAD="$fork_branch" \
  GH_MERGED_PR=81 \
  GH_IS_CROSS_REPOSITORY=true \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$fork_repo" --base develop --pr 81 "$fork_branch"
)"
run_contains "fork_remote_delete_skipped" "REMOTE_DELETE_RESULT=skipped" "$fork_output"
run_contains "fork_remote_delete_reason" "REMOTE_DELETE_REASON=cross_repository_pr" "$fork_output"
run_contains "fork_remote_delete_records_pr" "REMOTE_DELETE_PR_NUMBER=81" "$fork_output"
run_test "fork_remote_ref_remains" "yes" "$(
  if "$REAL_GIT" -C "$fork_repo" ls-remote --heads origin "$fork_branch" | grep -q .; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

spec_branch="spec/noissue-persistent"
spec_repo="$(make_repo spec "$spec_branch" yes)"
spec_output="$(
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$spec_repo" --base develop "$spec_branch"
)"
run_contains "spec_branch_expected_persistent" "BRANCH_LIFECYCLE=expected_persistent" "$spec_output"
run_test "spec_remote_ref_remains" "yes" "$(
  if "$REAL_GIT" -C "$spec_repo" ls-remote --heads origin "$spec_branch" | grep -q .; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

persistent_mismatch_branch="spec/123-persistent"
persistent_mismatch_repo="$(make_repo persistent-mismatch "$persistent_mismatch_branch" yes)"
run_fails_contains \
  "persistent_branch_pr_mismatch_blocks_tracker" \
  "refusing cleanup and tracker updates" \
  env GH_MERGED_HEAD="$persistent_mismatch_branch" \
    GH_MERGED_PR=84 \
    GH_PR_HEAD_REF_NAME="spec/different-branch" \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$HELPER" --repo-root "$persistent_mismatch_repo" --base develop --pr 84 "$persistent_mismatch_branch"

hub_sync_branch="feature/sync-template-v0.37.0"
hub_sync_repo="$(make_repo hub-sync "$hub_sync_branch" yes)"
printf 'mode: workflow_hub\n' >"$hub_sync_repo/.ai-dev-workflow.yaml"
hub_sync_output="$(
  GH_MERGED_HEAD="$hub_sync_branch" \
  GH_MERGED_PR=80 \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$hub_sync_repo" --base develop "$hub_sync_branch"
)"
run_contains "hub_sync_branch_is_hub_owned" "ACTION_REPOSITORY_KIND=hub_owned" "$hub_sync_output"
run_contains "hub_sync_branch_skips_product_repo_requirement" "BRANCH_LIFECYCLE=unclassified" "$hub_sync_output"

fail_branch="feature/noissue-delete-fails"
fail_repo="$(make_repo delete-fails "$fail_branch" yes)"
fail_bin="$TMP_ROOT/fail-bin"
write_gh_stub "$fail_bin"
write_git_failure_stub "$fail_bin"
run_fails_contains \
  "exact_pr_head_mismatch_blocks_delete" \
  "REMOTE_DELETE_REASON=pr_not_merged_or_branch_mismatch" \
  env GH_MERGED_HEAD="$merged_branch" \
    GH_MERGED_PR=82 \
    GH_PR_HEAD_REF_NAME="feature/different-branch" \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$HELPER" --repo-root "$(make_repo exact-mismatch "$merged_branch" yes)" --base develop --pr 82 "$merged_branch"

quoted_branch='feature/x"),true#'
quoted_repo="$(make_repo quoted "$quoted_branch" yes)"
run_fails_contains \
  "quoted_branch_does_not_bypass_exact_pr_filter" \
  "REMOTE_DELETE_REASON=pr_not_merged_or_branch_mismatch" \
  env GH_MERGED_HEAD="$quoted_branch" \
    GH_MERGED_PR=83 \
    GH_PR_HEAD_REF_NAME="feature/different-branch" \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$stub_bin:$PATH" \
    "$HELPER" --repo-root "$quoted_repo" --base develop --pr 83 "$quoted_branch"
run_test "quoted_branch_remote_ref_remains" "yes" "$(
  if "$REAL_GIT" -C "$quoted_repo" ls-remote --heads origin "$quoted_branch" | grep -q .; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

run_fails_contains \
  "remote_delete_failure_blocks_cleanup" \
  "REMOTE_DELETE_RESULT=failed" \
  env GH_MERGED_HEAD="$fail_branch" \
    GH_MERGED_PR=79 \
    GIT_FAIL_DELETE_BRANCH="$fail_branch" \
    REAL_GIT="$REAL_GIT" \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$fail_bin:$PATH" \
    "$HELPER" --repo-root "$fail_repo" --base develop --pr 79 "$fail_branch"
run_test "failed_delete_local_branch_remains" "yes" "$(
  if "$REAL_GIT" -C "$fail_repo" show-ref --quiet "refs/heads/$fail_branch"; then
    printf 'yes'
  else
    printf 'no'
  fi
)"

# --- Team-prefixed issue identifier vs. PR-body-derived issue (issue #1511) ---
#
# Team-prefixed branch slugs (2-6 letters, dash, digits) are ambiguous with
# ordinary descriptive slug fragments that happen to contain a number
# (retro-517, http-500, sha-256). These tests cover the three scenarios from
# the fix: a false-positive slug overridden by the PR body, a team-prefixed
# slug whose PR body confirms the same issue, and a team-prefixed slug with
# no PR-body closing reference falling back to the slug-derived issue.

# #1391: a numeric branch names one issue; the PR may resolve more. Closing
# refs from body/commits are processed as extras, and bare title refs warn.
multi_branch="fix/1520-retro-followups"
multi_repo="$(make_repo multi-close "$multi_branch" yes)"
multi_output="$(
  GH_MERGED_HEAD="$multi_branch" \
  GH_MERGED_PR=1521 \
  GH_PR_TITLE="fix(#1520): retro followups" \
  GH_PR_BODY="Also resolves the report tracked separately. Closes #1517" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$multi_repo" --base develop --pr 1521 "$multi_branch"
)"
run_contains "branch_issue_still_closed" "Closing issue #1520..." "$multi_output"
run_contains "body_extra_ref_processed" "Processing issue #1517 from PR #1521" "$multi_output"
run_contains "extras_announced" "PR #1521 also closes: 1517" "$multi_output"

commitmsg_branch="fix/1600-commit-ref"
commitmsg_repo="$(make_repo commitmsg-close "$commitmsg_branch" yes)"
commitmsg_output="$(
  GH_MERGED_HEAD="$commitmsg_branch" \
  GH_MERGED_PR=1601 \
  GH_PR_TITLE="fix(#1600): thing" \
  GH_PR_BODY="No closing keyword in the body." \
  GH_PR_COMMITS_TEXT=$'fix: the thing\nCloses #1602' \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$commitmsg_repo" --base develop --pr 1601 "$commitmsg_branch"
)"
run_contains "commit_message_ref_processed" "Processing issue #1602 from PR #1601" "$commitmsg_output"

# #1391: title/body and commit text must be fence-stripped SEPARATELY. An
# unclosed fence in the PR body extends "to end of input" by design (see the
# unclosed_fence_extends_to_end_of_input test above); if body and commit text
# were combined before stripping, that same unclosed-fence rule would treat
# every commit message as inside the fence too and silently drop a live
# commit-message closing reference as collateral damage.
unclosed_body_fence_branch="fix/1610-unclosed-body-fence"
unclosed_body_fence_repo="$(make_repo unclosed-body-fence "$unclosed_body_fence_branch" yes)"
unclosed_body_fence_output="$(
  GH_MERGED_HEAD="$unclosed_body_fence_branch" \
  GH_MERGED_PR=1611 \
  GH_PR_TITLE="fix(#1610): thing" \
  GH_PR_BODY=$'Accidentally unclosed fence below.\n\n```\nsome example text' \
  GH_PR_COMMITS_TEXT="fix: the thing
Closes #1612" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$unclosed_body_fence_repo" --base develop --pr 1611 "$unclosed_body_fence_branch"
)"
run_contains "unclosed_body_fence_does_not_swallow_commit_ref" \
  "Processing issue #1612 from PR #1611" \
  "$unclosed_body_fence_output"

bare_branch="fix/2053-first-of-two"
bare_repo="$(make_repo bare-title "$bare_branch" yes)"
bare_output="$(
  GH_MERGED_HEAD="$bare_branch" \
  GH_MERGED_PR=2060 \
  GH_PR_TITLE="fix(#2053,#2055): shared component edits" \
  GH_PR_BODY="No closing keywords." \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$bare_repo" --base develop --pr 2060 "$bare_branch" 2>&1
)"
run_contains "bare_title_ref_warns_loudly" "title references issue(s) #2055 without a closing keyword" "$bare_output"
run_test "bare_title_ref_branch_issue_not_warned" "no" \
  "$(if grep -Fq "#2053 without" <<<"$bare_output"; then printf yes; else printf no; fi)"

# #1391: the branch-derived issue may already be closed (e.g. a re-run, or an
# issue closed by hand before cleanup ran) — extras from the PR body/commits
# must still be processed rather than being skipped along with the branch
# issue's own (redundant) close step.
already_closed_branch="fix/1800-already-closed-with-extra"
already_closed_repo="$(make_repo already-closed-extra "$already_closed_branch" yes)"
already_closed_output="$(
  GH_MERGED_HEAD="$already_closed_branch" \
  GH_MERGED_PR=1801 \
  GH_PR_TITLE="fix(#1800): thing" \
  GH_PR_BODY="Also closes #1802" \
  GH_ISSUE_STATE=CLOSED \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$already_closed_repo" --base develop --pr 1801 "$already_closed_branch"
)"
run_contains "already_closed_branch_issue_skips_close" "Issue #1800 is already CLOSED, skipping close." "$already_closed_output"
run_contains "already_closed_branch_extra_still_processed" "Processing issue #1802 from PR #1801" "$already_closed_output"

# #1391: a transient failure fetching the PR title for the bare-ref check
# must not go completely silent — it is the one helper whose purpose is
# avoiding exactly that kind of silent gap.
title_fetch_fail_branch="fix/1900-title-fetch-fails"
title_fetch_fail_repo="$(make_repo title-fetch-fail "$title_fetch_fail_branch" yes)"
title_fetch_fail_output="$(
  GH_MERGED_HEAD="$title_fetch_fail_branch" \
  GH_MERGED_PR=1901 \
  GH_PR_TITLE="fix(#1900): thing" \
  GH_PR_BODY="No closing keywords." \
  GH_ISSUE_STATE=OPEN \
  GH_PR_TITLE_FETCH_FAIL=1 \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$title_fetch_fail_repo" --base develop --pr 1901 "$title_fetch_fail_branch" 2>&1
)"
run_contains "title_fetch_failure_warns_instead_of_silent" \
  "could not fetch PR #1901 title to check for unprocessed bare issue references" \
  "$title_fetch_fail_output"

false_positive_branch="fix/retro-517-doc-gaps"
false_positive_repo="$(make_repo false-positive "$false_positive_branch" yes)"
false_positive_output="$(
  GH_MERGED_HEAD="$false_positive_branch" \
  GH_MERGED_PR=632 \
  GH_PR_BODY="Fixes #601" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$false_positive_repo" --base develop --pr 632 "$false_positive_branch"
)"
run_contains \
  "false_positive_slug_uses_pr_body_issue" \
  "Closing issue #601..." \
  "$false_positive_output"
run_test \
  "false_positive_slug_does_not_close_slug_derived_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #517" <<<"$false_positive_output" || grep -Fq "Processing issue #517" <<<"$false_positive_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"
run_contains \
  "false_positive_slug_notes_ambiguity" \
  "Team-prefixed identifier 'retro-517'" \
  "$false_positive_output"

matching_override_branch="fix/lh-97-fix-thing"
matching_override_repo="$(make_repo matching-override "$matching_override_branch" yes)"
matching_override_output="$(
  GH_MERGED_HEAD="$matching_override_branch" \
  GH_MERGED_PR=645 \
  GH_PR_BODY="Closes #97" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$matching_override_repo" --base develop --pr 645 "$matching_override_branch"
)"
run_contains \
  "pr_body_derived_happy_path_closes_issue" \
  "Closing issue #97..." \
  "$matching_override_output"
run_contains \
  "pr_body_derived_happy_path_used_override_path" \
  "using closing keyword refs from PR #645" \
  "$matching_override_output"

no_reference_branch="fix/lh-97-real-issue"
no_reference_repo="$(make_repo no-reference "$no_reference_branch" yes)"
no_reference_output="$(
  GH_MERGED_HEAD="$no_reference_branch" \
  GH_MERGED_PR=650 \
  GH_PR_BODY="No closing keyword here." \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$no_reference_repo" --base develop --pr 650 "$no_reference_branch"
)"
run_contains \
  "no_closing_reference_falls_back_to_slug_issue" \
  "Closing issue #97..." \
  "$no_reference_output"
run_test \
  "no_closing_reference_does_not_use_override_path" \
  "no" \
  "$(
    if grep -Fq "using closing keyword refs from PR" <<<"$no_reference_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# Punctuation-delimited closing keyword (e.g. "(Fixes #601)") must still be
# recognized — the word-boundary regex requires a non-alnum/underscore
# character immediately before the keyword, not specifically whitespace, so
# a parenthesis directly abutting the keyword still matches.
punctuation_branch="fix/retro-518-doc-gaps"
punctuation_repo="$(make_repo punctuation "$punctuation_branch" yes)"
punctuation_output="$(
  GH_MERGED_HEAD="$punctuation_branch" \
  GH_MERGED_PR=651 \
  GH_PR_BODY="Cleans up doc gaps. (Fixes #602)" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$punctuation_repo" --base develop --pr 651 "$punctuation_branch"
)"
run_contains \
  "punctuation_delimited_keyword_uses_pr_body_issue" \
  "Closing issue #602..." \
  "$punctuation_output"
run_test \
  "punctuation_delimited_keyword_does_not_close_slug_derived_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #518" <<<"$punctuation_output" || grep -Fq "Processing issue #518" <<<"$punctuation_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# An example closing keyword inside a fenced code block in the PR body must
# not be treated as a live reference — only the real footer reference should
# be used.
fenced_branch="fix/retro-519-doc-gaps"
fenced_repo="$(make_repo fenced "$fenced_branch" yes)"
fenced_pr_body='Cleans up doc gaps.

```
Example commit message: Closes #999
```

Closes #603'
fenced_output="$(
  GH_MERGED_HEAD="$fenced_branch" \
  GH_MERGED_PR=652 \
  GH_PR_BODY="$fenced_pr_body" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$fenced_repo" --base develop --pr 652 "$fenced_branch"
)"
run_contains \
  "fenced_example_excludes_code_block_reference_closes_real_issue" \
  "Closing issue #603..." \
  "$fenced_output"
run_test \
  "fenced_example_does_not_close_code_block_example_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #999" <<<"$fenced_output" || grep -Fq "Processing issue #999" <<<"$fenced_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# Tilde-fenced (~~~) code blocks must be excluded the same way as
# backtick-fenced blocks.
tilde_fenced_branch="fix/retro-520-doc-gaps"
tilde_fenced_repo="$(make_repo tilde-fenced "$tilde_fenced_branch" yes)"
tilde_fenced_pr_body='Cleans up doc gaps.

~~~
Example commit message: Closes #998
~~~

Closes #604'
tilde_fenced_output="$(
  GH_MERGED_HEAD="$tilde_fenced_branch" \
  GH_MERGED_PR=653 \
  GH_PR_BODY="$tilde_fenced_pr_body" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$tilde_fenced_repo" --base develop --pr 653 "$tilde_fenced_branch"
)"
run_contains \
  "tilde_fenced_example_closes_real_issue" \
  "Closing issue #604..." \
  "$tilde_fenced_output"
run_test \
  "tilde_fenced_example_does_not_close_code_block_example_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #998" <<<"$tilde_fenced_output" || grep -Fq "Processing issue #998" <<<"$tilde_fenced_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# An unclosed opening fence must extend to end of input, so a real closing
# reference placed after an accidentally-unclosed fence is NOT treated as
# live (rather than leaking past the unclosed fence and being extracted).
unclosed_fence_branch="fix/retro-521-doc-gaps"
unclosed_fence_repo="$(make_repo unclosed-fence "$unclosed_fence_branch" yes)"
unclosed_fence_pr_body='Cleans up doc gaps.

~~~
Example commit message: Closes #997
Closes #605'
unclosed_fence_output="$(
  GH_MERGED_HEAD="$unclosed_fence_branch" \
  GH_MERGED_PR=654 \
  GH_PR_BODY="$unclosed_fence_pr_body" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$unclosed_fence_repo" --base develop --pr 654 "$unclosed_fence_branch"
)"
run_test \
  "unclosed_fence_extends_to_end_of_input" \
  "no" \
  "$(
    if grep -Fq "Closing issue #997" <<<"$unclosed_fence_output" || grep -Fq "Processing issue #997" <<<"$unclosed_fence_output" || grep -Fq "Closing issue #605" <<<"$unclosed_fence_output" || grep -Fq "Processing issue #605" <<<"$unclosed_fence_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"
run_contains \
  "unclosed_fence_falls_back_to_slug_issue" \
  "Closing issue #521..." \
  "$unclosed_fence_output"

# A closing fence marker shorter than the opening one must NOT be treated as
# a closer (GFM requires the closer to be at least as long as the opener).
# Using tildes here (not backticks) keeps this test out of reach of
# workflow-shell-snippet-lint.py's backtick-only WS001 fence scan.
mismatched_fence_branch="fix/retro-522-doc-gaps"
mismatched_fence_repo="$(make_repo mismatched-fence "$mismatched_fence_branch" yes)"
mismatched_fence_pr_body='Cleans up doc gaps.

~~~~
Example commit message: Closes #996
~~~
still fenced content after a too-short closer
~~~~

Closes #606'
mismatched_fence_output="$(
  GH_MERGED_HEAD="$mismatched_fence_branch" \
  GH_MERGED_PR=655 \
  GH_PR_BODY="$mismatched_fence_pr_body" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$mismatched_fence_repo" --base develop --pr 655 "$mismatched_fence_branch"
)"
run_contains \
  "mismatched_fence_length_closes_real_issue" \
  "Closing issue #606..." \
  "$mismatched_fence_output"
run_test \
  "mismatched_fence_length_does_not_close_example_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #996" <<<"$mismatched_fence_output" || grep -Fq "Processing issue #996" <<<"$mismatched_fence_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# A closing fence line with trailing content after the fence marker (not
# pure whitespace) must NOT be treated as a closer either (GFM requires the
# closing fence to be followed only by whitespace).
trailing_content_fence_branch="fix/retro-523-doc-gaps"
trailing_content_fence_repo="$(make_repo trailing-content-fence "$trailing_content_fence_branch" yes)"
trailing_content_fence_pr_body='Cleans up doc gaps.

~~~
Example commit message: Closes #994
~~~ not a real closer
still fenced
~~~

Closes #607'
trailing_content_fence_output="$(
  GH_MERGED_HEAD="$trailing_content_fence_branch" \
  GH_MERGED_PR=656 \
  GH_PR_BODY="$trailing_content_fence_pr_body" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$trailing_content_fence_repo" --base develop --pr 656 "$trailing_content_fence_branch"
)"
run_contains \
  "trailing_content_fence_closes_real_issue" \
  "Closing issue #607..." \
  "$trailing_content_fence_output"
run_test \
  "trailing_content_fence_does_not_close_example_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #994" <<<"$trailing_content_fence_output" || grep -Fq "Processing issue #994" <<<"$trailing_content_fence_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# A genuine sort failure while extracting closing-keyword issue numbers must
# propagate as a fatal error, not be silently swallowed and fall through to
# the ambiguous slug-derived issue.
sort_failure_bin="$TMP_ROOT/sort-failure-bin"
write_gh_stub "$sort_failure_bin"
cat >"$sort_failure_bin/sort" <<'STUB'
#!/usr/bin/env bash
echo "mock sort failure" >&2
exit 2
STUB
chmod +x "$sort_failure_bin/sort"

sort_failure_branch="fix/retro-524-doc-gaps"
sort_failure_repo="$(make_repo sort-failure "$sort_failure_branch" yes)"
set +e
sort_failure_output="$(
  env GH_MERGED_HEAD="$sort_failure_branch" \
    GH_MERGED_PR=657 \
    GH_PR_BODY="Closes #608" \
    GH_ISSUE_STATE=OPEN \
    WORKFLOW_TARGET_GITHUB_REPO=example/repo \
    PATH="$sort_failure_bin:$PATH" \
    "$HELPER" --repo-root "$sort_failure_repo" --base develop --pr 657 "$sort_failure_branch" 2>&1
)"
sort_failure_status=$?
set -e
run_test \
  "extraction_sort_failure_propagates_as_fatal" \
  "nonzero" \
  "$([ "$sort_failure_status" -ne 0 ] && printf 'nonzero' || printf 'zero')"
run_contains \
  "extraction_sort_failure_error_message" \
  "ERROR: failed to sort extracted closing-keyword issue numbers" \
  "$sort_failure_output"
run_test \
  "extraction_sort_failure_does_not_fall_back_to_slug_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #524" <<<"$sort_failure_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

# A 4-space-indented fence marker is GFM indented code, not a real fence, and
# must not be treated as one — otherwise it can spuriously open an unclosed
# fence that swallows a later, real closing reference.
indented_fence_branch="fix/retro-525-doc-gaps"
indented_fence_repo="$(make_repo indented-fence "$indented_fence_branch" yes)"
indented_fence_pr_body='Cleans up doc gaps.

Example indented code (not a fence):
    ~~~
    some literal example content

Closes #609'
indented_fence_output="$(
  GH_MERGED_HEAD="$indented_fence_branch" \
  GH_MERGED_PR=658 \
  GH_PR_BODY="$indented_fence_pr_body" \
  GH_ISSUE_STATE=OPEN \
  WORKFLOW_TARGET_GITHUB_REPO=example/repo \
  PATH="$stub_bin:$PATH" \
  "$HELPER" --repo-root "$indented_fence_repo" --base develop --pr 658 "$indented_fence_branch"
)"
run_contains \
  "indented_fence_marker_is_not_a_fence_closes_real_issue" \
  "Closing issue #609..." \
  "$indented_fence_output"
run_test \
  "indented_fence_marker_does_not_fall_back_to_slug_issue" \
  "no" \
  "$(
    if grep -Fq "Closing issue #525" <<<"$indented_fence_output"; then
      printf 'yes'
    else
      printf 'no'
    fi
  )"

echo ""
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

[ "$FAIL_COUNT" -eq 0 ]

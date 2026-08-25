#!/usr/bin/env bash
#
# Post-merge cleanup: fetch origin, checkout the merge base, pull, delete the
# local branch that was just merged, and verify or delete merged implementation
# branches on the remote.
# Keeps the local repo clean after merging developments.
#
# Usage:
#   ./scripts/development-workflow/post-merge-cleanup.sh [--repo <name>] [--repo-root <path>] [--base <branch>] [--pr <number>] [BRANCH]
#
# - No BRANCH: use current branch (run while still on the merged branch).
# - BRANCH: name of the local branch to delete (e.g. feature/my-feature).
#
# Uses `git branch -D` (force delete) because squash/rebase merges (e.g. GitHub
# default) do not have the branch tip in develop's history, so -d would fail.
#
# Issue close: if a plain numeric issue number is embedded in the branch name
# (e.g. fix/42-slug) it is closed directly. Team-prefixed identifiers (e.g.
# fix/lh-97-slug) are ambiguous with descriptive slug fragments that happen to
# contain a number (fix/retro-517-doc-gaps, fix/http-500-retry) — for those,
# the merged PR body/title is checked first for GitHub closing keywords
# (Closes #N, Fixes #N, Resolves #N, etc.) and, when present, that reference
# is authoritative; the slug-derived identifier is only used as a fallback
# when the PR body carries no closing reference. When the branch slug
# contains no issue number at all (e.g. epic-slug branches like
# feature/model-cost-resilience), the merged PR body/title is parsed the same
# way, and each referenced issue is closed and its tracker status updated to
# Merged.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
. "$SCRIPT_DIR/workflow-lib.sh"

cd_workflow_repo_root

HUB_REPO_ROOT="$(workflow_repo_root)"
DEVELOP_BRANCH="develop"
TO_DELETE=""
target_repo=""
repo_root="$HUB_REPO_ROOT"
base_branch_override=""
merged_pr_number=""

require_option_value() {
  local option="$1"
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
    echo "$option requires a value." >&2
    sed -n '2,16p' "$0" >&2
    exit 64
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      require_option_value "$@"
      target_repo="$2"
      shift 2
      ;;
    --repo-root)
      require_option_value "$@"
      repo_root="$2"
      shift 2
      ;;
    --base)
      require_option_value "$@"
      base_branch_override="$2"
      shift 2
      ;;
    --pr)
      require_option_value "$@"
      merged_pr_number="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      if [ -n "$TO_DELETE" ]; then
        echo "Only one branch name may be provided." >&2
        exit 64
      fi
      TO_DELETE="$1"
      shift
      ;;
  esac
done

case "$merged_pr_number" in
  ''|*[!0-9]*) [ -z "$merged_pr_number" ] || { echo "Invalid --pr '${merged_pr_number}' — must be a positive integer." >&2; exit 64; } ;;
esac

HUB_REPO_ROOT="$repo_root"
cd "$HUB_REPO_ROOT" || exit 1

if [ -z "$TO_DELETE" ]; then
  TO_DELETE="$(git branch --show-current)"
  if [ -z "$TO_DELETE" ]; then
    echo "Could not determine current branch (detached HEAD?). Pass the branch name to delete." >&2
    exit 2
  fi
fi

CLEANUP_REPO_ROOT="$repo_root"
ACTION_REPOSITORY_KIND="hub_owned"
ACTION_REPOSITORY="$(basename "$repo_root")"
TARGET_GITHUB_REPO=""
mode_context="$(workflow_repository_mode "$repo_root")"
workflow_mode="$(workflow_context_value WORKFLOW_MODE "$mode_context")"
branch_owner_kind="hub"
selected_product_default_branch=""

case "$(branch_prefix "$TO_DELETE")" in
  feature)
    # Template sync branches are created and merged on the workflow hub itself.
    # They are not product-repository implementation artifacts.
    if [ "$workflow_mode" != "workflow_hub" ] || [[ "$TO_DELETE" != feature/sync-template-* ]]; then
      branch_owner_kind="implementation"
    fi
    ;;
  fix|refactor|hotfix)
    branch_owner_kind="implementation"
    ;;
  spec|implementation-plan)
    branch_owner_kind="expected_persistent"
    ;;
esac

# Shared with cleanup_remote_implementation_branch() below, which emits the
# identical REMOTE_DELETE_* contract for the same condition when reached via
# a different call path, so the two checks can't drift apart in wording.
emit_pr_number_required_skip() {
  local branch="$1"
  print_kv REMOTE_DELETE_RESULT "skipped"
  print_kv REMOTE_DELETE_REASON "pr_number_required"
  print_kv_escaped ERROR_MESSAGE "Remote implementation branch '${branch}' was not deleted because --pr <merged-pr-number> is required to bind cleanup to the exact merged PR."
  echo "ERROR: remote implementation branch '$branch' was not deleted because --pr <merged-pr-number> is required." >&2
}

if [ "$workflow_mode" = "workflow_hub" ] && [ "$branch_owner_kind" = "implementation" ] && [ -z "$target_repo" ]; then
  echo "ERROR: product repository selection is required for implementation branch cleanup in workflow_hub mode; pass --repo <name>." >&2
  exit 64
fi

# Fail fast: --pr is required to clean up the remote copy of an implementation
# branch (see cleanup_remote_implementation_branch() below). Check this before
# any fetch/checkout/pull/delete work runs, so the error surfaces immediately
# instead of after the rest of cleanup has already mutated local state. Kept
# after the workflow_hub product-repo-selection check above so the original
# relative check priority (and therefore which error a caller sees first when
# both --repo and --pr are missing in workflow_hub mode) is preserved exactly.
# Uses exit 64 (this script's usage-error convention, matching every other
# argument-validation check above) rather than the incidental exit 1 that
# resulted from cleanup_remote_implementation_branch()'s `return 1` plus
# `set -e` when this condition was only checked there.
#
# Planted-violation proof (both directions, plus no-mutation evidence:
# git rev-parse HEAD / git branch --show-current / git for-each-ref /
# git ls-remote identical before and after the failing invocation) is
# recorded at https://github.com/lhpaul/ai-dev-framework-template/pull/1500#issuecomment-5335650280
# Regression coverage lives in
# scripts/development-workflow/tests/test-post-merge-cleanup.sh
# (unmerged_guard_fires_before_fetch and friends).
if [ "$branch_owner_kind" = "implementation" ] && [ -z "$merged_pr_number" ]; then
  emit_pr_number_required_skip "$TO_DELETE"
  exit 64
fi

if [ "$workflow_mode" = "workflow_hub" ] && [ -n "$target_repo" ]; then
  selected_repo_context="$(workflow_validate_repository_context "$target_repo" "$repo_root" --require-local)"
  selected_product_default_branch="$(workflow_context_value TARGET_DEFAULT_BRANCH "$selected_repo_context")"
  if [ -z "$selected_product_default_branch" ]; then
    echo "ERROR: product repository default branch is required for workflow_hub cleanup." >&2
    exit 64
  fi
else
  selected_repo_context=""
fi

if [ "$workflow_mode" = "workflow_hub" ] && [ "$branch_owner_kind" = "implementation" ]; then
  if [ -n "$selected_repo_context" ]; then
    repo_context="$selected_repo_context"
  else
    repo_context="$(workflow_validate_repository_context "$target_repo" "$repo_root" --require-local)"
  fi
  CLEANUP_REPO_ROOT="$(workflow_context_value TARGET_LOCAL_PATH "$repo_context")"
  DEVELOP_BRANCH="$(workflow_context_value TARGET_DEFAULT_BRANCH "$repo_context")"
  if [ -z "$DEVELOP_BRANCH" ]; then
    echo "ERROR: product repository default branch is required for workflow_hub cleanup." >&2
    exit 64
  fi
  ACTION_REPOSITORY_KIND="product_repo_owned"
  ACTION_REPOSITORY="$(workflow_context_value TARGET_REPO_NAME "$repo_context")"
  TARGET_GITHUB_REPO="$(workflow_github_repo_from_context "$repo_context")"
  if [ -z "$CLEANUP_REPO_ROOT" ]; then
    echo "ERROR: product repository local path is required for product repository cleanup in workflow_hub mode." >&2
    exit 64
  fi
fi

case "$TO_DELETE" in
  "$DEVELOP_BRANCH"|"$selected_product_default_branch"|main|master)
    echo "Refusing to delete protected branch '$TO_DELETE'." >&2
    exit 2
    ;;
esac

if [ -n "$base_branch_override" ]; then
  DEVELOP_BRANCH="$base_branch_override"
elif [ "$ACTION_REPOSITORY_KIND" = "hub_owned" ]; then
  cleanup_repo_slug=""
  if ! cleanup_repo_slug="$(repo_slug 2>/dev/null)"; then
    echo "ERROR: could not resolve GitHub repository for merged PR base lookup; pass --base <branch> to override." >&2
    exit 1
  fi
  if [ -n "$merged_pr_number" ]; then
    if ! merged_pr_base_json="$(
      gh pr view "$merged_pr_number" \
        --repo "$cleanup_repo_slug" \
        --json state,baseRefName,headRefName
    )"; then
      echo "ERROR: could not query merged PR #${merged_pr_number} base; pass --base <branch> to override." >&2
      exit 1
    fi
    merged_base="$(printf '%s\n' "$merged_pr_base_json" | jq -r --arg branch "$TO_DELETE" 'select(type == "object" and .state == "MERGED" and .headRefName == $branch) | .baseRefName // empty')"
  else
    if ! merged_base="$(
      gh pr list \
        --repo "$cleanup_repo_slug" \
        --state merged \
        --head "$TO_DELETE" \
        --limit 1 \
        --json baseRefName \
        --jq '.[0].baseRefName // empty'
    )"; then
      echo "ERROR: could not query merged PR base for branch '$TO_DELETE'; pass --base <branch> to override." >&2
      exit 1
    fi
  fi
  if [ -z "$merged_base" ]; then
    echo "ERROR: could not determine merged PR base for branch '$TO_DELETE'; pass --base <branch> to override." >&2
    exit 1
  fi
  DEVELOP_BRANCH="$merged_base"
fi

case "$TO_DELETE" in
  "$DEVELOP_BRANCH")
    echo "Refusing to delete protected branch '$TO_DELETE'." >&2
    exit 2
    ;;
esac

print_kv ACTION_REPOSITORY_KIND "$ACTION_REPOSITORY_KIND"
print_kv ACTION_REPOSITORY "$ACTION_REPOSITORY"
[ -n "$TARGET_GITHUB_REPO" ] && print_kv TARGET_GITHUB_REPO "$TARGET_GITHUB_REPO"
print_kv CLEANUP_REPO_ROOT "$CLEANUP_REPO_ROOT"
print_kv TRACKER_REPO_ROOT "$HUB_REPO_ROOT"
case "$branch_owner_kind" in
  implementation)
    print_kv BRANCH_LIFECYCLE "expected_deleted"
    ;;
  expected_persistent)
    print_kv BRANCH_LIFECYCLE "expected_persistent"
    ;;
  *)
    print_kv BRANCH_LIFECYCLE "unclassified"
    ;;
esac

cd "$CLEANUP_REPO_ROOT" || exit 1

remote_cleanup_repo_slug() {
  if [ -n "$TARGET_GITHUB_REPO" ]; then
    printf '%s\n' "$TARGET_GITHUB_REPO"
    return 0
  fi
  repo_slug
}

verify_merged_pr_for_branch() {
  local branch="$1"
  local lookup_repo="$2"

  if [ -n "$merged_pr_number" ]; then
    gh pr view "$merged_pr_number" \
      --repo "$lookup_repo" \
      --json number,state,headRefName,isCrossRepository,headRepository,headRepositoryOwner |
      jq -c --arg branch "$branch" 'select(type == "object" and (.number | type == "number") and .state == "MERGED" and .headRefName == $branch)'
    return
  fi

  gh pr list \
    --repo "$lookup_repo" \
    --state merged \
    --head "$branch" \
    --limit 1 \
    --json number,isCrossRepository,headRepository,headRepositoryOwner \
    --jq '.[0] // empty'
}

cleanup_remote_implementation_branch() {
  local branch="$1"
  local lookup_repo merged_pr_json merged_pr is_cross_repository push_err push_exit

  if [ "$branch_owner_kind" != "implementation" ]; then
    return 0
  fi

  if [ -z "$merged_pr_number" ]; then
    # Unreachable via the main script flow above (the early guard near the
    # top exits first), kept as a defensive check in case this function is
    # ever called from another path in the future.
    emit_pr_number_required_skip "$branch"
    return 1
  fi

  if ! lookup_repo="$(remote_cleanup_repo_slug)"; then
    print_kv REMOTE_DELETE_RESULT "skipped"
    print_kv_escaped ERROR_MESSAGE "Could not resolve GitHub repository for remote implementation branch cleanup."
    echo "ERROR: could not resolve GitHub repository for remote implementation branch cleanup." >&2
    return 1
  fi

  if ! merged_pr_json="$(verify_merged_pr_for_branch "$branch" "$lookup_repo")"; then
    print_kv REMOTE_DELETE_RESULT "skipped"
    print_kv_escaped ERROR_MESSAGE "Could not query merged PRs for branch '${branch}' in '${lookup_repo}'."
    echo "ERROR: could not query merged PRs for branch '$branch' in '$lookup_repo'." >&2
    return 1
  fi

  if [ -z "$merged_pr_json" ]; then
    print_kv REMOTE_DELETE_RESULT "skipped"
    print_kv REMOTE_DELETE_REASON "pr_not_merged_or_branch_mismatch"
    print_kv_escaped ERROR_MESSAGE "Remote implementation branch '${branch}' was not deleted because PR #${merged_pr_number} is not MERGED or does not use that head branch."
    echo "ERROR: remote implementation branch '$branch' was not deleted because PR #${merged_pr_number} is not MERGED or does not use that head branch." >&2
    return 1
  fi

  merged_pr="$(printf '%s\n' "$merged_pr_json" | jq -r '.number // empty')"
  is_cross_repository="$(printf '%s\n' "$merged_pr_json" | jq -r '.isCrossRepository // false')"
  if [ "$is_cross_repository" = "true" ]; then
    print_kv REMOTE_DELETE_RESULT "skipped"
    print_kv REMOTE_DELETE_REASON "cross_repository_pr"
    print_kv REMOTE_DELETE_PR_NUMBER "$merged_pr"
    print_kv_escaped ERROR_MESSAGE "Remote implementation branch '${branch}' was not deleted because merged PR #${merged_pr} is cross-repository; refusing to delete an unqualified branch from origin."
    echo "Remote implementation branch '$branch' not deleted because merged PR #${merged_pr} is cross-repository." >&2
    return 0
  fi

  print_kv REMOTE_DELETE_PR_NUMBER "$merged_pr"
  push_err="$(git push origin --delete "$branch" 2>&1)" && push_exit=0 || push_exit=$?
  if [ "$push_exit" -eq 0 ]; then
    print_kv REMOTE_DELETE_RESULT "deleted"
    echo "Remote implementation branch '$branch' deleted after merged PR #${merged_pr}."
    return 0
  fi

  if printf '%s\n' "$push_err" | grep -Eiq "remote ref does not exist|unable to delete .* remote ref does not exist"; then
    print_kv REMOTE_DELETE_RESULT "not_found"
    print_kv REMOTE_DELETE_STATUS "already_absent"
    echo "Remote implementation branch '$branch' already absent after merged PR #${merged_pr}."
    return 0
  fi

  print_kv REMOTE_DELETE_RESULT "failed"
  print_kv_escaped ERROR_MESSAGE "Failed to delete remote implementation branch '${branch}' (exit ${push_exit}): ${push_err}"
  echo "ERROR: failed to delete remote implementation branch '$branch': $push_err" >&2
  return 1
}

LOCAL_BRANCH_MISSING=0
VERIFIED_MERGED_PR=""
if ! git show-ref --quiet "refs/heads/$TO_DELETE"; then
  merged_pr_lookup_repo="$TARGET_GITHUB_REPO"
  if [ -z "$merged_pr_lookup_repo" ]; then
    if ! merged_pr_lookup_repo="$(repo_slug)"; then
      echo "Local branch '$TO_DELETE' does not exist and merged PR lookup repo could not be resolved." >&2
      exit 2
    fi
  fi
  if [ -n "$merged_pr_number" ]; then
    if ! verified_merged_pr_json="$(gh pr view "$merged_pr_number" \
      --repo "$merged_pr_lookup_repo" \
      --json number,state,headRefName)"; then
      echo "Local branch '$TO_DELETE' does not exist and merged PR #${merged_pr_number} lookup failed (gh command failed)." >&2
      exit 2
    fi
    VERIFIED_MERGED_PR="$(printf '%s\n' "$verified_merged_pr_json" | jq -r --arg branch "$TO_DELETE" 'select(type == "object" and (.number | type == "number") and .state == "MERGED" and .headRefName == $branch) | .number // empty')"
  elif ! VERIFIED_MERGED_PR="$(gh pr list \
      --repo "$merged_pr_lookup_repo" \
      --state merged \
      --head "$TO_DELETE" \
      --limit 1 \
      --json number \
      --jq '.[0].number // empty')"; then
    echo "Local branch '$TO_DELETE' does not exist and merged PR lookup failed (gh command failed)." >&2
    exit 2
  fi
  if [ -z "$VERIFIED_MERGED_PR" ]; then
    echo "Local branch '$TO_DELETE' does not exist and no merged PR was found for that branch head." >&2
    exit 2
  fi
  LOCAL_BRANCH_MISSING=1
  echo "Local branch '$TO_DELETE' is already gone; verified merged PR #${VERIFIED_MERGED_PR} — continuing with fetch, base update, and tracker cleanup."
fi

if [ -n "$merged_pr_number" ] && [ -z "$VERIFIED_MERGED_PR" ]; then
  if ! merged_pr_lookup_repo="$(remote_cleanup_repo_slug)"; then
    echo "ERROR: could not resolve GitHub repository for merged PR #${merged_pr_number} validation." >&2
    exit 1
  fi
  if ! verified_merged_pr_json="$(verify_merged_pr_for_branch "$TO_DELETE" "$merged_pr_lookup_repo")"; then
    echo "ERROR: could not query merged PR #${merged_pr_number} for branch '$TO_DELETE' in '$merged_pr_lookup_repo'." >&2
    exit 1
  fi
  VERIFIED_MERGED_PR="$(printf '%s\n' "$verified_merged_pr_json" | jq -r '.number // empty')"
  if [ -z "$VERIFIED_MERGED_PR" ]; then
    print_kv REMOTE_DELETE_REASON "pr_not_merged_or_branch_mismatch"
    print_kv_escaped ERROR_MESSAGE "PR #${merged_pr_number} is not MERGED or does not use branch '${TO_DELETE}'; refusing cleanup and tracker updates."
    echo "ERROR: PR #${merged_pr_number} is not MERGED or does not use branch '$TO_DELETE'; refusing cleanup and tracker updates." >&2
    exit 2
  fi
fi

if [ "$LOCAL_BRANCH_MISSING" -eq 1 ]; then
  echo "Post-merge cleanup: will switch to $DEVELOP_BRANCH in $CLEANUP_REPO_ROOT (local branch '$TO_DELETE' already removed)."
else
  echo "Post-merge cleanup: will switch to $DEVELOP_BRANCH in $CLEANUP_REPO_ROOT, update it, and delete local branch '$TO_DELETE'."
fi
echo ""

echo "Fetching origin..."
# --prune: remove stale remote-tracking refs (e.g. origin/<merged-branch>)
git fetch origin --prune

echo "Checking out $DEVELOP_BRANCH..."
git checkout "$DEVELOP_BRANCH"

echo "Pulling $DEVELOP_BRANCH..."
# Use explicit 'origin <branch>' so this works even when the local branch has no upstream
# tracking set (e.g. integration branches created/pushed without --set-upstream).
# --ff-only: fail cleanly if the branch diverged (e.g. local commits) instead of creating a merge.
git pull --ff-only origin "$DEVELOP_BRANCH"

cleanup_remote_implementation_branch "$TO_DELETE"

if [ "$LOCAL_BRANCH_MISSING" -eq 1 ]; then
  echo "Skipping local branch delete for '$TO_DELETE' (already absent)."
else
echo "Deleting local branch '$TO_DELETE'..."
# Check whether a worktree is still using this branch; if so, remove it first.
# git branch -D fails with "error: cannot delete branch 'X' used by worktree" in that case.
# awk is used instead of grep to parse the structured porcelain output with an exact
# string match — grep -F would match branch names that are prefixes of other branches,
# and grep with a regex anchor would misinterpret metacharacters in branch names.
WORKTREE_PATH=$(git worktree list --porcelain | awk -v branch="branch refs/heads/$TO_DELETE" '
  /^worktree / { wt = substr($0, 10) }
  $0 == branch  { print wt }
' || true)
if [ -n "$WORKTREE_PATH" ]; then
  echo "Worktree '$WORKTREE_PATH' is still using branch '$TO_DELETE'. Removing worktree first..."
  # Proactive unlock: agent processes often leave worktrees locked; unlock is idempotent when not locked.
  git worktree unlock "$WORKTREE_PATH" 2>/dev/null || true
  # Capture stderr so we can detect the locked-worktree condition.
  REMOVE_ERR=$(git worktree remove "$WORKTREE_PATH" --force 2>&1) && REMOVE_RC=0 || REMOVE_RC=$?
  if [ "$REMOVE_RC" -ne 0 ] && echo "$REMOVE_ERR" | grep -q "locked working tree"; then
    # Detect lock reason from git worktree list --porcelain (the "locked" field).
    LOCK_REASON=$(git worktree list --porcelain | grep -A5 "^worktree $WORKTREE_PATH$" | grep "^locked" | sed 's/^locked //' || echo "unknown")
    echo "WARNING: Worktree '$WORKTREE_PATH' is locked (reason: $LOCK_REASON). Force-overriding — if this worktree belongs to an active agent, data may be lost."
    # Primary remediation: unlock then remove.
    RETRY_ERR=""
    RETRY_RC=1
    if git worktree unlock "$WORKTREE_PATH" 2>/dev/null; then
      RETRY_ERR=$(git worktree remove "$WORKTREE_PATH" --force 2>&1) && RETRY_RC=0 || RETRY_RC=$?
    else
      RETRY_ERR="'git worktree unlock' unavailable or failed"
    fi
    if [ "$RETRY_RC" -ne 0 ]; then
      # Fallback: double-force (bypasses lock without requiring unlock subcommand).
      echo "WARNING: ${RETRY_ERR}; using double-force fallback."
      FORCE_ERR=$(git worktree remove "$WORKTREE_PATH" --force --force 2>&1) && FORCE_RC=0 || FORCE_RC=$?
      if [ "$FORCE_RC" -ne 0 ]; then
        echo "Error removing locked worktree '$WORKTREE_PATH': $FORCE_ERR" >&2
        exit 1
      fi
    fi
  elif [ "$REMOVE_RC" -ne 0 ]; then
    echo "Error removing worktree '$WORKTREE_PATH': $REMOVE_ERR" >&2
    exit 1
  fi
  echo "Worktree removed."
fi
# -D: branch is already merged on remote (squash/rebase merges don't leave tip in develop)
git branch -D "$TO_DELETE"
fi

# --- Update tracker status and close associated GitHub issue (if any) ---

# strip_fenced_pr_body_blocks
# Removes quoted/example PR body text from stdin before it is scanned for
# closing keywords, so an example like "Closes #999" inside a code sample,
# inline code span, or blockquote is not treated as a live closing reference.
# Handles both backtick (```) and tilde (~~~) fence styles, and treats an
# unclosed opening fence as extending to end of input (rather than leaving the
# rest of the body unfiltered). Matches GitHub-Flavored Markdown's
# fence-matching rule: a closing fence must use the same character as the
# opening fence, be at least as long, and have nothing but trailing whitespace
# after the fence marker — a shorter, differently-charactered, or
# content-suffixed line (e.g. a nested example fence, or "``` end of block") is
# treated as still being inside the fence rather than closing it. A fence
# delimiter may be indented up to 3 spaces per GFM; 4+ spaces of leading
# whitespace makes it indented code instead, so the raw line (not a fully
# whitespace-stripped line) is matched to preserve that boundary — otherwise a
# 4-space-indented "```" could be mistaken for a real fence and hide a live
# closing reference.
strip_fenced_pr_body_blocks() {
  python3 -c '
import re, sys

def strip_inline_code_spans(line):
    out = []
    i = 0
    while i < len(line):
        if line[i] != "`":
            out.append(line[i])
            i += 1
            continue
        j = i
        while j < len(line) and line[j] == "`":
            j += 1
        ticks = line[i:j]
        closing = line.find(ticks, j)
        if closing == -1:
            out.append(line[i])
            i += 1
            continue
        i = closing + len(ticks)
    return "".join(out)

lines = sys.stdin.read().split("\n")
out = []
fence_char = None
fence_len = 0
fence_re = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
for line in lines:
    match = fence_re.match(line)
    if fence_char is None:
        if match:
            fence_char = match.group(1)[0]
            fence_len = len(match.group(1))
            continue
        if re.match(r"^\s*>", line):
            continue
        out.append(strip_inline_code_spans(line))
    else:
        if (match and match.group(1)[0] == fence_char
                and len(match.group(1)) >= fence_len
                and match.group(2).strip() == ""):
            fence_char = None
            fence_len = 0
        continue
sys.stdout.write("\n".join(out))
'
}

# fetch_pr_closing_issues <pr_repo> <pr_number>
# Fetches PR title+body, strips fenced code blocks (so example closing
# keywords in a code sample are not treated as live references — see
# strip_fenced_pr_body_blocks above), and extracts GitHub closing-keyword
# issue references (Close/Closes/Closed, Fix/Fixes/Fixed,
# Resolve/Resolves/Resolved — optionally followed by "issue" — then #NNN).
# Requires a non-word-boundary immediately before the keyword (start of
# string, or any character that is not alphanumeric/underscore) so substrings
# like "disclose" or "hotfix" are not treated as closing keywords, while
# still matching punctuation-delimited forms like "(Fixes #601)". Mirrors
# graduation-closeout-from-merged-pr.sh's extract_closing_issue_numbers().
# Echoes sorted, deduped issue numbers (one per line, possibly empty).
# Returns 2 if the arguments are missing/invalid, or 1 (without echoing
# anything) if the PR body could not be fetched, fence-stripping failed (e.g.
# python3 missing/erroring), or the keyword-extraction stages themselves
# failed — the caller decides whether either failure is fatal. Every failure
# mode is deliberately distinguished from "no closing keywords found" (which
# returns 0 with empty output) so a failure can never be silently treated as
# "nothing to close". Each `grep` stage is run separately (not piped
# together) and its own exit status captured directly: under `pipefail`, a
# 2-stage `grep1 | grep2` pipeline reports only the *rightmost* non-zero
# exit, so a real error in the first grep (exit 2+) can be masked by the
# second grep's ordinary "no match" (exit 1) on its now-empty input, and
# would otherwise be misread as "nothing to close" rather than propagated.
# A `grep` exit status of 1 means "no match" for that stage specifically
# (not a failure, per grep's own exit-code contract) and is not an error;
# anything else (grep exit >1, or `sort` failing) is.
fetch_pr_closing_issues() {
  local pr_repo="$1"
  local pr_number="$2"
  local pr_body stripped_pr_body keyword_lines matched_refs stage_status
  if [ "$#" -ne 2 ] || [ -z "$pr_repo" ] || [[ ! "$pr_number" =~ ^[0-9]+$ ]]; then
    echo "ERROR: fetch_pr_closing_issues requires <pr_repo> <pr_number>." >&2
    return 2
  fi
  pr_body="$(gh pr view "$pr_number" --repo "$pr_repo" --json body,title --jq '(.title // "") + "\n" + (.body // "")' 2>/dev/null)" || return 1
  # Commit messages carry closing keywords too, and GitHub only honours them
  # natively on default-branch merges — this repo merges to develop, so the
  # script must read them itself (#1391, second confirmation: a `Closes #N`
  # in a commit body was silently ignored).
  local pr_commit_text stripped_pr_commit_text
  pr_commit_text="$(gh pr view "$pr_number" --repo "$pr_repo" --json commits --jq '[.commits[] | ((.messageHeadline // "") + "\n" + (.messageBody // ""))] | join("\n")' 2>/dev/null)" || return 1
  # Strip the title/body and the commit text SEPARATELY, then combine the
  # already-stripped results. strip_fenced_pr_body_blocks deliberately treats
  # an unclosed opening fence as extending to end of input; if the raw body
  # and commit text were concatenated *before* stripping, an unclosed (e.g.
  # accidentally malformed) fence in the PR body would swallow every commit
  # message that follows it — including a live `Closes #N` reference — as
  # collateral damage. Each source's fence state must not leak into the
  # other's.
  if ! stripped_pr_body="$(printf '%s' "$pr_body" | strip_fenced_pr_body_blocks)"; then
    echo "ERROR: could not strip fenced code blocks from PR #${pr_number} body." >&2
    return 1
  fi
  if ! stripped_pr_commit_text="$(printf '%s' "$pr_commit_text" | strip_fenced_pr_body_blocks)"; then
    echo "ERROR: could not strip fenced code blocks from PR #${pr_number} commit messages." >&2
    return 1
  fi
  stripped_pr_body="${stripped_pr_body}
${stripped_pr_commit_text}"
  set +e
  keyword_lines="$(printf '%s' "$stripped_pr_body" | grep -ioE '(^|[^[:alnum:]_])(close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]+(issue[[:space:]]+)?#[0-9]+')"
  stage_status=$?
  set -e
  if [ "$stage_status" -gt 1 ]; then
    echo "ERROR: failed to scan PR #${pr_number} body for closing keywords (grep exit ${stage_status})." >&2
    return 1
  fi
  if [ "$stage_status" -eq 1 ] || [ -z "$keyword_lines" ]; then
    return 0
  fi
  set +e
  matched_refs="$(printf '%s' "$keyword_lines" | grep -oE '[0-9]+$')"
  stage_status=$?
  set -e
  if [ "$stage_status" -gt 1 ]; then
    echo "ERROR: failed to extract issue numbers from PR #${pr_number} closing-keyword matches (grep exit ${stage_status})." >&2
    return 1
  fi
  if [ "$stage_status" -eq 1 ] || [ -z "$matched_refs" ]; then
    return 0
  fi
  if ! printf '%s\n' "$matched_refs" | sort -un; then
    echo "ERROR: failed to sort extracted closing-keyword issue numbers from PR #${pr_number}." >&2
    return 1
  fi
  return 0
}

# close_issues_from_pr <pr_number> <issue_numbers_newline_list>
# For each issue number in the list, updates the tracker status to Merged,
# closes the issue if it is still open (commenting with the closing PR
# number), and reasserts Merged status after close. A `gh issue view` failure
# for a given issue is counted and reported but does not stop processing of
# the remaining issues in the list; once all issues have been processed, a
# nonzero view-failure count makes this function return 1, and the caller
# must treat that as fatal (`close_issues_from_pr ... || exit 1`), matching
# the aggregate fatal-on-view-failure behavior this replaces at both call
# sites. This is distinct from a `gh issue close` failure, which remains a
# warning-only, non-fatal condition (cleanup continues for the remaining
# issues in the list either way). The issue-numbers list may be empty (a
# no-op loop), but <pr_number> must be a non-empty numeric PR number so an
# invalid caller cannot produce a close comment like "Closed by PR #.".
close_issues_from_pr() {
  local pr_number="$1"
  local issue_list="$2"
  local issue_num issue_state view_failures=0
  if [ "$#" -ne 2 ] || [[ ! "$pr_number" =~ ^[0-9]+$ ]]; then
    echo "ERROR: close_issues_from_pr requires <pr_number> (numeric) <issue_numbers_newline_list>." >&2
    return 2
  fi
  while IFS= read -r issue_num; do
    [ -z "$issue_num" ] && continue
    echo "Processing issue #${issue_num} from PR #${pr_number} closing keywords..."
    if ! issue_state="$(gh issue view "$issue_num" --json state --jq '.state' 2>/dev/null)"; then
      echo "Warning: could not query issue #${issue_num}; skipping close and tracker update for this ref." >&2
      view_failures=$((view_failures + 1))
      continue
    fi
    update_tracker_status_best_effort "$issue_num" "Merged"
    if [ "$issue_state" = "OPEN" ]; then
      echo "Closing issue #${issue_num}..."
      if gh issue close "$issue_num" --comment "Closed by PR #${pr_number}."; then
        echo "Reasserting issue #${issue_num} tracker status as Merged after close..."
        update_tracker_status_best_effort "$issue_num" "Merged" "" "allow-backward"
      else
        echo "Warning: could not close issue #${issue_num}; continuing cleanup." >&2
      fi
    else
      echo "Issue #${issue_num} is already ${issue_state}, skipping close."
    fi
  done <<< "$issue_list"
  if [ "$view_failures" -gt 0 ]; then
    echo "ERROR: could not query ${view_failures} issue(s) from PR #${pr_number} closing refs (gh command failed)." >&2
    return 1
  fi
  return 0
}

# warn_unprocessed_title_refs <pr_repo> <pr_number> <processed_newline_list>
# A PR title like "fix(#2053,#2055): ..." references issues without a closing
# keyword; neither GitHub nor this script closes them. Say so loudly instead
# of silently processing a subset (#1391): list every #N in the title that is
# not in the processed list. Best-effort by design (a failure here must never
# fail the overall cleanup), but a failure to fetch the title is itself
# announced on stderr rather than returning silently — otherwise the one
# helper whose whole purpose is avoiding a silent gap could itself go silent
# on a transient `gh` failure, indistinguishable from "no bare refs found".
warn_unprocessed_title_refs() {
  if [ "$#" -ne 3 ] || [ -z "${1:-}" ] || [[ ! "${2:-}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: warn_unprocessed_title_refs requires <pr_repo> (non-empty) <pr_number> (numeric) <processed_newline_list>." >&2
    return 2
  fi
  local pr_repo="$1" pr_number="$2" processed="$3"
  local title refs ref unprocessed=""
  title="$(gh pr view "$pr_number" --repo "$pr_repo" --json title --jq '.title // ""' 2>/dev/null)" || {
    echo "Warning: could not fetch PR #${pr_number} title to check for unprocessed bare issue references; skipping this check." >&2
    return 0
  }
  refs="$(printf '%s' "$title" | grep -oE '#[0-9]+' | tr -d '#' | sort -un)" || return 0
  [ -n "$refs" ] || return 0
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    if ! printf '%s
' "$processed" | grep -qx "$ref"; then
      unprocessed="${unprocessed} #${ref}"
    fi
  done <<< "$refs"
  if [ -n "$unprocessed" ]; then
    echo "WARNING: PR #${pr_number} title references issue(s)${unprocessed} without a closing keyword; they were NOT closed or status-updated. If this PR resolved them, update them manually or add closing keywords next time." >&2
  fi
  return 0
}

# Unified issue-number extraction: covers all branch prefixes in a single pass.
# Sets ISSUE_NUMBER, ISSUE_IDENTIFIER, ISSUE_ID_TYPE, and BRANCH_TYPE.
# ISSUE_IDENTIFIER holds the full extracted identifier (e.g. "42", "lh-97").
# ISSUE_NUMBER holds the numeric part only (used for `gh issue` commands on GitHub).
# ISSUE_ID_TYPE is "numeric" or "team-prefixed".
# All four remain empty if the branch name does not match any known prefix/pattern.
#
# Supported identifier formats:
#   Numeric:      fix/42-slug, feature/123-slug, spec/7-slug, implementation-plan/99-slug
#   Team-prefixed: fix/lh-97-slug, feature/rad-42-slug, implementation-plan/PROJ-101-slug
#                  (pattern: 2–6 alpha chars, dash, digits; case-insensitive)
ISSUE_NUMBER=""
ISSUE_IDENTIFIER=""
ISSUE_ID_TYPE=""
BRANCH_TYPE=""

if [[ "$TO_DELETE" =~ ^(fix|feature|hotfix|refactor)/([0-9]+)($|-) ]]; then
  ISSUE_NUMBER="${BASH_REMATCH[2]}"
  ISSUE_IDENTIFIER="$ISSUE_NUMBER"
  ISSUE_ID_TYPE="numeric"
  BRANCH_TYPE="implementation"
elif [[ "$TO_DELETE" =~ ^(fix|feature|hotfix|refactor)/([a-zA-Z]{2,6}-([0-9]+))($|-) ]]; then
  ISSUE_IDENTIFIER="${BASH_REMATCH[2]}"
  ISSUE_NUMBER="${BASH_REMATCH[3]}"
  ISSUE_ID_TYPE="team-prefixed"
  BRANCH_TYPE="implementation"
elif [[ "$TO_DELETE" =~ ^(spec)/([0-9]+)($|-) ]]; then
  ISSUE_NUMBER="${BASH_REMATCH[2]}"
  ISSUE_IDENTIFIER="$ISSUE_NUMBER"
  ISSUE_ID_TYPE="numeric"
  BRANCH_TYPE="spec"
elif [[ "$TO_DELETE" =~ ^(spec)/([a-zA-Z]{2,6}-([0-9]+))($|-) ]]; then
  ISSUE_IDENTIFIER="${BASH_REMATCH[2]}"
  ISSUE_NUMBER="${BASH_REMATCH[3]}"
  ISSUE_ID_TYPE="team-prefixed"
  BRANCH_TYPE="spec"
elif [[ "$TO_DELETE" =~ ^(implementation-plan)/([0-9]+)($|-) ]]; then
  ISSUE_NUMBER="${BASH_REMATCH[2]}"
  ISSUE_IDENTIFIER="$ISSUE_NUMBER"
  ISSUE_ID_TYPE="numeric"
  BRANCH_TYPE="plan"
elif [[ "$TO_DELETE" =~ ^(implementation-plan)/([a-zA-Z]{2,6}-([0-9]+))($|-) ]]; then
  ISSUE_IDENTIFIER="${BASH_REMATCH[2]}"
  ISSUE_NUMBER="${BASH_REMATCH[3]}"
  ISSUE_ID_TYPE="team-prefixed"
  BRANCH_TYPE="plan"
fi

if [ -n "$ISSUE_IDENTIFIER" ]; then
  cd "$HUB_REPO_ROOT"
  # For team-prefixed identifiers, log the extraction result.
  # All `gh issue` and `update_tracker_status_best_effort` calls use ISSUE_NUMBER
  # (the numeric part) because:
  #   - `gh issue view/close` require a numeric GitHub issue number.
  #   - `update_tracker_status_best_effort` uses `--argjson` to match
  #     `.content.number` (an integer) in the GitHub Projects item list.
  # The full team-prefixed identifier is captured in ISSUE_IDENTIFIER for
  # informational logging; future tracker helpers with native team-prefix support
  # should use ISSUE_IDENTIFIER rather than ISSUE_NUMBER.
  if [ "$ISSUE_ID_TYPE" = "team-prefixed" ]; then
    echo "Detected team-prefixed issue identifier '$ISSUE_IDENTIFIER' in branch '$TO_DELETE' (numeric part: #$ISSUE_NUMBER)."
  fi

  if [ "$BRANCH_TYPE" = "implementation" ]; then
    # Team-prefixed identifiers are ambiguous by construction: a 2-6 letter
    # prefix followed by "-<digits>" matches both real team-prefixed issue
    # IDs (lh-97) and ordinary descriptive slug fragments that happen to
    # contain a number (retro-517, http-500, sha-256, utf-8, base-64). The
    # merged PR body is authoritative when it carries GitHub closing
    # keywords; only fall back to the slug-derived identifier below when the
    # PR body has no closing reference at all (e.g. no PR could be resolved,
    # or the PR genuinely does not close an issue).
    PR_OVERRIDE_ISSUES=""
    PR_FOR_OVERRIDE=""
    if [ "$ISSUE_ID_TYPE" = "team-prefixed" ]; then
      pr_override_repo="$TARGET_GITHUB_REPO"
      if [ -z "$pr_override_repo" ]; then
        if ! pr_override_repo="$(repo_slug 2>/dev/null)"; then
          echo "ERROR: could not resolve GitHub repository for PR-body issue verification." >&2
          exit 1
        fi
      fi
      PR_FOR_OVERRIDE="${VERIFIED_MERGED_PR:-}"
      [ -n "$PR_FOR_OVERRIDE" ] || PR_FOR_OVERRIDE="$merged_pr_number"
      if [ -z "$PR_FOR_OVERRIDE" ]; then
        PR_FOR_OVERRIDE="$(gh pr list --repo "$pr_override_repo" --state merged --head "$TO_DELETE" --limit 1 --json number --jq '.[0].number // empty')" || {
          echo "ERROR: could not query merged PRs for branch '$TO_DELETE' in '$pr_override_repo' (gh command failed)." >&2
          exit 1
        }
      fi
      if [ -n "$PR_FOR_OVERRIDE" ]; then
        PR_OVERRIDE_ISSUES="$(fetch_pr_closing_issues "$pr_override_repo" "$PR_FOR_OVERRIDE")" || {
          echo "ERROR: could not fetch PR #${PR_FOR_OVERRIDE} body from '$pr_override_repo' (gh command failed)." >&2
          exit 1
        }
      fi
    fi

    if [ -n "$PR_OVERRIDE_ISSUES" ]; then
      echo "Team-prefixed identifier '$ISSUE_IDENTIFIER' in branch '$TO_DELETE' is ambiguous; using closing keyword refs from PR #${PR_FOR_OVERRIDE} instead: $(printf '%s' "$PR_OVERRIDE_ISSUES" | tr '\n' ' ')"
      close_issues_from_pr "$PR_FOR_OVERRIDE" "$PR_OVERRIDE_ISSUES" || exit 1
      warn_unprocessed_title_refs "$pr_override_repo" "$PR_FOR_OVERRIDE" "$PR_OVERRIDE_ISSUES"
    else
      # Update the tracker status BEFORE closing the issue so that
      # gh project item-list can still find the item (it only returns items
      # whose linked issue is open; once closed the lookup silently fails).
      update_tracker_status_best_effort "$ISSUE_NUMBER" "Merged"
      # Close the issue when an implementation branch (feature/fix/hotfix/refactor) is merged.
      if ! ISSUE_STATE=$(gh issue view "$ISSUE_NUMBER" --json state --jq '.state'); then
        echo "ERROR: could not query issue #$ISSUE_NUMBER (gh command failed)." >&2
        exit 1
      fi
      # Resolve the merged PR up front: the branch-derived issue needs it for
      # the close comment, and the PR's own closing refs (#1391) need it even
      # when the branch issue is already closed.
      merged_pr_repo="$TARGET_GITHUB_REPO"
      if [ -z "$merged_pr_repo" ]; then
        if ! merged_pr_repo="$(repo_slug)"; then
          echo "ERROR: could not resolve GitHub repository for merged PR lookup." >&2
          exit 1
        fi
      fi
      if [ -n "$merged_pr_number" ]; then
        MERGED_PR="$merged_pr_number"
      else
        MERGED_PR="$(gh pr list --repo "$merged_pr_repo" --state merged --head "$TO_DELETE" --limit 1 --json number --jq '.[0].number // empty')" || {
          echo "ERROR: could not query merged PRs for branch '$TO_DELETE' in '$merged_pr_repo' (gh command failed)." >&2
          exit 1
        }
      fi
      if [ "$ISSUE_STATE" = "OPEN" ]; then
        if [ -n "$MERGED_PR" ]; then
          CLOSE_COMMENT="Closed by PR #${MERGED_PR}."
        elif [ -n "$VERIFIED_MERGED_PR" ]; then
          MERGED_PR="$VERIFIED_MERGED_PR"
          CLOSE_COMMENT="Closed by PR #${MERGED_PR}."
        fi
        if [ -n "$MERGED_PR" ]; then
          echo "Closing issue #$ISSUE_NUMBER..."
          if gh issue close "$ISSUE_NUMBER" --comment "$CLOSE_COMMENT"; then
            echo "Reasserting issue #$ISSUE_NUMBER tracker status as Merged after close..."
            update_tracker_status_best_effort "$ISSUE_NUMBER" "Merged" "" "allow-backward"
          else
            echo "Warning: could not close issue #$ISSUE_NUMBER; continuing cleanup." >&2
          fi
        else
          echo "No merged PR found for branch '$TO_DELETE'; leaving issue #$ISSUE_NUMBER open."
        fi
      else
        echo "Issue #$ISSUE_NUMBER is already $ISSUE_STATE, skipping close."
      fi
      # The branch names one issue; the PR may resolve more (#1391). Process
      # every closing reference from the PR title, body, and commit messages
      # that is not the branch-derived issue, and warn about bare title refs.
      if [ -n "${MERGED_PR:-}" ]; then
        if ! EXTRA_CLOSES="$(fetch_pr_closing_issues "$merged_pr_repo" "$MERGED_PR")"; then
          echo "ERROR: could not fetch PR #${MERGED_PR} closing refs from '$merged_pr_repo' (gh command failed)." >&2
          exit 1
        fi
        EXTRA_CLOSES="$(printf '%s\n' "$EXTRA_CLOSES" | grep -vx "$ISSUE_NUMBER" || true)"
        if [ -n "$EXTRA_CLOSES" ]; then
          echo "PR #${MERGED_PR} also closes: $(printf '%s' "$EXTRA_CLOSES" | tr '\n' ' ')"
          close_issues_from_pr "$MERGED_PR" "$EXTRA_CLOSES" || exit 1
        fi
        warn_unprocessed_title_refs "$merged_pr_repo" "$MERGED_PR" "$(printf '%s\n%s' "$ISSUE_NUMBER" "$EXTRA_CLOSES")"
      fi
    fi
  elif [ "$BRANCH_TYPE" = "spec" ]; then
    # spec/* branches reference the issue but must not close it — the issue stays
    # open for the next workflow stage (writing the implementation plan).
    echo "Spec branch for issue #$ISSUE_NUMBER merged; issue stays open for the next workflow stage. Updating tracker status to Spec Ready..."
    update_tracker_status_best_effort "$ISSUE_NUMBER" "Spec Ready"
  elif [ "$BRANCH_TYPE" = "plan" ]; then
    # implementation-plan/* branches reference the issue but must not close it —
    # the issue stays open for the next workflow stage (implementation).
    echo "Implementation plan branch for issue #$ISSUE_NUMBER merged; issue stays open for the next workflow stage. Updating tracker status to Plan Ready..."
    update_tracker_status_best_effort "$ISSUE_NUMBER" "Plan Ready"
  fi
else
  # No issue number in branch name — for implementation branches, fall back to
  # parsing the merged PR body/title for GitHub closing keywords
  # (Closes #NNN, Fixes #NNN, Resolves #NNN, etc.) so that epic-slug branches
  # like feature/model-cost-resilience still close their linked issues.
  if [ "$branch_owner_kind" = "implementation" ]; then
    pr_closes_repo="$TARGET_GITHUB_REPO"
    if [ -z "$pr_closes_repo" ]; then
      if ! pr_closes_repo="$(repo_slug 2>/dev/null)"; then
        echo "ERROR: could not resolve GitHub repository for PR-body issue closeout." >&2
        exit 1
      fi
    fi
    if [ -n "$pr_closes_repo" ]; then
      CLOSING_PR="${VERIFIED_MERGED_PR:-}"
      [ -n "$CLOSING_PR" ] || CLOSING_PR="$merged_pr_number"
      if [ -z "$CLOSING_PR" ]; then
        if ! CLOSING_PR="$(gh pr list --repo "$pr_closes_repo" --state merged --head "$TO_DELETE" --limit 1 --json number --jq '.[0].number // empty' 2>/dev/null)"; then
          echo "ERROR: could not query merged PRs for branch '$TO_DELETE' in '$pr_closes_repo' (gh command failed)." >&2
          exit 1
        fi
      fi
      if [ -n "$CLOSING_PR" ]; then
        if ! CLOSES_ISSUES="$(fetch_pr_closing_issues "$pr_closes_repo" "$CLOSING_PR")"; then
          echo "ERROR: could not fetch PR #${CLOSING_PR} body from '$pr_closes_repo' (gh command failed)." >&2
          exit 1
        fi
        if [ -n "$CLOSES_ISSUES" ]; then
          echo "Found closing keyword refs in PR #${CLOSING_PR}: issues $(printf '%s' "$CLOSES_ISSUES" | tr '\n' ' ')"
          cd "$HUB_REPO_ROOT"
          close_issues_from_pr "$CLOSING_PR" "$CLOSES_ISSUES" || exit 1
          warn_unprocessed_title_refs "$pr_closes_repo" "$CLOSING_PR" "$CLOSES_ISSUES"
        else
          echo "No issue number in branch name '$TO_DELETE' or PR #${CLOSING_PR} body; skipping issue close and tracker update."
        fi
      else
        echo "No issue number in branch name '$TO_DELETE' and no merged PR found; skipping issue close and tracker update."
      fi
    fi
  else
    echo "No issue number detected in branch name '$TO_DELETE', skipping issue close and tracker update."
  fi
fi

echo ""
if [ "$LOCAL_BRANCH_MISSING" -eq 1 ]; then
  echo "Done. You are on $DEVELOP_BRANCH; local branch '$TO_DELETE' was already removed."
else
  echo "Done. You are on $DEVELOP_BRANCH and '$TO_DELETE' has been removed locally."
fi

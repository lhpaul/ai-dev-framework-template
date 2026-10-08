#!/usr/bin/env bash
#
# Post-merge cleanup: fetch origin, checkout the merge base, pull, delete the
# local branch that was just merged, and verify or delete merged implementation
# branches on the remote. The caller's own worktree is never removed: if the
# merged branch is checked out there, it is detached onto the base instead.
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
# shellcheck source=scripts/development-workflow/closing-keyword-lib.sh
. "$SCRIPT_DIR/closing-keyword-lib.sh"

# Capture the caller's working directory before this script moves anywhere.
# A worktree-isolated runner that invokes cleanup is standing inside a linked
# worktree; that worktree must survive cleanup (#1386).
CALLER_PWD="$(pwd -P 2>/dev/null || true)"

cd_workflow_repo_root

HUB_REPO_ROOT="$(workflow_repo_root)"
DEVELOP_BRANCH="develop"
TO_DELETE=""
target_repo=""
repo_root="$HUB_REPO_ROOT"
base_branch_override=""
merged_pr_number=""
cleanup_repo_root_override=""
repo_root_explicit=0
inspect_targets=0
merge_session="${WORKFLOW_MERGE_BUDGET_SESSION:-}"

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
    --inspect-targets) inspect_targets=1; shift ;;
    --merge-session) require_option_value "$@"; merge_session="$2"; shift 2 ;;
    --repo)
      require_option_value "$@"
      target_repo="$2"
      shift 2
      ;;
    --repo-root)
      require_option_value "$@"
      repo_root="$2"
      repo_root_explicit=1
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
    --cleanup-repo-root)
      require_option_value "$@"
      cleanup_repo_root_override="$2"
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

# physical_worktree_root <path>
# Prints the physical (symlink-resolved) top-level directory of the git
# working tree containing <path>, or returns 1 when <path> is not inside one.
physical_worktree_root() {
  local top
  [ -n "${1:-}" ] && [ -d "$1" ] || return 1
  top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [ -n "$top" ] || return 1
  (CDPATH='' cd -- "$top" && pwd -P)
}

# physical_git_common_dir <path>
# Prints the physical path of the shared git directory for <path>, so a linked
# worktree and its main clone resolve to the same value.
physical_git_common_dir() {
  local dir
  dir="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" || return 1
  [ -n "$dir" ] || return 1
  case "$dir" in
    /*) ;;
    *) dir="$1/$dir" ;;
  esac
  (CDPATH='' cd -- "$dir" && pwd -P)
}

CALLER_WORKTREE_ROOT=""
# On the base-worktree re-entry below, this process's directory is wherever the
# first pass had moved to, not the caller's. The first pass hands the caller's
# worktrees over in POST_MERGE_CLEANUP_CALLER_WORKTREES instead.
# Read-only inspection inherits the first cleanup pass's capture, including an
# intentionally empty list from a caller outside Git. Direct begin has no list.
if { [ "$inspect_targets" -eq 0 ] || [ -z "${POST_MERGE_CLEANUP_CALLER_WORKTREES+x}" ]; } && [ -n "$CALLER_PWD" ] && [ "${POST_MERGE_CLEANUP_REENTERED:-}" != "1" ] && [ "${POST_MERGE_CLEANUP_BUDGET_ENTERED:-}" != 1 ]; then
  CALLER_WORKTREE_ROOT="$(physical_worktree_root "$CALLER_PWD" || true)"
fi

# Never operate on a repo root the caller did not pass (#1386). Without
# --repo-root the default used to be the checkout this script file lives in,
# which is the shared main clone whenever a worktree runner invokes the
# main-clone copy of the helper. When the caller is standing in another working
# tree of the same repository, that working tree is the root it meant.
if [ "$repo_root_explicit" -eq 0 ] && [ -n "$CALLER_WORKTREE_ROOT" ]; then
  default_repo_root_real="$(CDPATH='' cd -- "$repo_root" 2>/dev/null && pwd -P || true)"
  if [ -n "$default_repo_root_real" ] && [ "$CALLER_WORKTREE_ROOT" != "$default_repo_root_real" ]; then
    caller_common_dir="$(physical_git_common_dir "$CALLER_WORKTREE_ROOT" || true)"
    default_common_dir="$(physical_git_common_dir "$default_repo_root_real" || true)"
    if [ -n "$caller_common_dir" ] && [ "$caller_common_dir" = "$default_common_dir" ]; then
      echo "Using the calling working tree '$CALLER_WORKTREE_ROOT' as --repo-root (no --repo-root was passed)."
      repo_root="$CALLER_WORKTREE_ROOT"
    fi
  fi
fi

# Working trees that belong to the caller. Cleanup must never remove one of
# these; when the merged branch is checked out in one, that working tree is
# detached onto the updated base instead (#1386). The list is inherited across
# the base-worktree re-entry below, which changes this process's directory.
CALLER_WORKTREES="${POST_MERGE_CLEANUP_CALLER_WORKTREES:-}"
add_caller_worktree() {
  local root
  root="$(physical_worktree_root "${1:-}" || true)"
  [ -n "$root" ] || return 0
  if ! grep -Fqx -- "$root" <<<"$CALLER_WORKTREES"; then
    CALLER_WORKTREES="${CALLER_WORKTREES:+$CALLER_WORKTREES
}$root"
  fi
  return 0
}
add_caller_worktree "$CALLER_WORKTREE_ROOT"
if { [ "$inspect_targets" -eq 0 ] || [ -z "${POST_MERGE_CLEANUP_CALLER_WORKTREES+x}" ]; } && [ "$repo_root_explicit" -eq 1 ] && [ "${POST_MERGE_CLEANUP_REENTERED:-}" != "1" ] && [ "${POST_MERGE_CLEANUP_BUDGET_ENTERED:-}" != 1 ]; then
  add_caller_worktree "$repo_root"
fi
export POST_MERGE_CLEANUP_CALLER_WORKTREES="$CALLER_WORKTREES"

# is_linked_worktree <path>
# True when <path> is a linked worktree rather than the repository's main
# working tree (their git dir and common git dir differ).
is_linked_worktree() {
  local git_dir common_dir
  git_dir="$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  git_dir="$(CDPATH='' cd -- "$git_dir" 2>/dev/null && pwd -P)" || return 1
  common_dir="$(physical_git_common_dir "$1")" || return 1
  [ "$git_dir" != "$common_dir" ]
}

is_caller_worktree() {
  local candidate
  [ -n "${1:-}" ] && [ -n "$CALLER_WORKTREES" ] || return 1
  candidate="$(CDPATH='' cd -- "$1" 2>/dev/null && pwd -P)" || return 1
  grep -Fqx -- "$candidate" <<<"$CALLER_WORKTREES"
}

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

if [ -n "$cleanup_repo_root_override" ]; then
  CLEANUP_REPO_ROOT="$cleanup_repo_root_override"
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

cleanup_skip_local=0
cleanup_skip_remote=0
if [ "$inspect_targets" -eq 0 ]; then
  cleanup_budget_repo="$TARGET_GITHUB_REPO"
  [ -n "$cleanup_budget_repo" ] || cleanup_budget_repo="$(repo_slug)"
  [ -n "$merged_pr_number" ] || merged_pr_number="$(gh pr list --repo "$cleanup_budget_repo" --state merged --head "$TO_DELETE" --limit 1 --json number --jq '.[0].number // empty')"
  [ -n "$merged_pr_number" ] || { echo "Cleanup requires an owned merged PR" >&2; exit 2; }
  cleanup_budget_head="$(gh pr view "$merged_pr_number" --repo "$cleanup_budget_repo" --json headRefOid --jq '.headRefOid')"
  if [ -z "$merge_session" ]; then
    cleanup_admission="$(workflow_merge_budget_helper begin --followup-only --repo-root "$HUB_REPO_ROOT" --target-root "$CLEANUP_REPO_ROOT" \
      --repo "$cleanup_budget_repo" --pr "$merged_pr_number" --head "$cleanup_budget_head" --base "$DEVELOP_BRANCH" --branch "$TO_DELETE")" || {
        printf '%s\n' "$cleanup_admission" >&2; exit 2;
      }
    merge_session="$(printf '%s' "$cleanup_admission" | jq -er '.session')"
  fi
  export WORKFLOW_MERGE_BUDGET_SESSION="$merge_session"
  export WORKFLOW_MERGE_BUDGET_REPO="$cleanup_budget_repo"
  export WORKFLOW_MERGE_BUDGET_PR="$merged_pr_number"
  cleanup_binding="$(workflow_merge_budget_helper check --session "$merge_session" --repo "$cleanup_budget_repo" --pr "$merged_pr_number" --head "$cleanup_budget_head" --base "$DEVELOP_BRANCH" --branch "$TO_DELETE")" || exit 2
  cleanup_budget_repo="$(printf '%s' "$cleanup_binding" | jq -er --arg repo "$cleanup_budget_repo" --argjson pr "$merged_pr_number" '.prs[] | select(.repo==($repo|ascii_downcase) and .pr==$pr) | .repo')" || exit 2
  export WORKFLOW_MERGE_BUDGET_REPO="$cleanup_budget_repo"
  # Recovery may run from another declared checkout. Preserve caller ownership
  # frozen by begin, rather than rediscovering it from this process's cwd.
  while IFS= read -r cleanup_frozen_caller; do
    add_caller_worktree "$cleanup_frozen_caller"
  done < <(printf '%s' "$cleanup_binding" | jq -r --arg repo "$cleanup_budget_repo" --argjson pr "$merged_pr_number" '.prs[] | select(.repo==$repo and .pr==$pr) | .worktrees[]? | select(.caller==true) | .root')
  export POST_MERGE_CLEANUP_CALLER_WORKTREES="$CALLER_WORKTREES"
  cleanup_skip_local="$(printf '%s' "$cleanup_binding" | jq -r --arg repo "$cleanup_budget_repo" --argjson pr "$merged_pr_number" '[.prs[] | select(.repo==$repo and .pr==$pr) | .policySkipped[]? | select(.=="local_cleanup")] | length')"
  cleanup_skip_remote="$(printf '%s' "$cleanup_binding" | jq -r --arg repo "$cleanup_budget_repo" --argjson pr "$merged_pr_number" '[.prs[] | select(.repo==$repo and .pr==$pr) | .policySkipped[]? | select(.=="remote_delete")] | length')"
  cleanup_execution="$(workflow_merge_budget_helper check --session "$merge_session" --repo "$cleanup_budget_repo" \
    --pr "$merged_pr_number" --phase cleanup --executor-pid "$$")" || exit 2
  if [ "$(printf '%s' "$cleanup_execution" | jq -r '.nestedExecutionAuthorized')" != true ]; then
    cleanup_target_args=()
    [ -z "$target_repo" ] || cleanup_target_args+=(--repo "$target_repo")
    exec python3 "$SCRIPT_DIR/workflow-merge-budget.py" run-step --session "$merge_session" \
      --repo "$cleanup_budget_repo" --pr "$merged_pr_number" --phase cleanup --step cleanup -- \
      env POST_MERGE_CLEANUP_BUDGET_ENTERED=1 bash "$SCRIPT_DIR/post-merge-cleanup.sh" --merge-session "$merge_session" --repo-root "$HUB_REPO_ROOT" \
      --cleanup-repo-root "$CLEANUP_REPO_ROOT" ${cleanup_target_args[@]+"${cleanup_target_args[@]}"} --base "$DEVELOP_BRANCH" --pr "$merged_pr_number" "$TO_DELETE"
  fi
  cleanup_local_complete="$(printf '%s' "$cleanup_binding" | jq -r --arg repo "$cleanup_budget_repo" --argjson pr "$merged_pr_number" '.prs[] | select(.repo==$repo and .pr==$pr) | .steps.local_cleanup.status // "pending"')"
  cleanup_reentry_args=()
  [ "${POST_MERGE_CLEANUP_REENTERED:-}" != 1 ] || cleanup_reentry_args+=(--continue-intent)
  if [ "$cleanup_skip_local" -eq 1 ]; then
    cleanup_remote_declared="$(printf '%s' "$cleanup_binding" | jq -r --arg repo "$cleanup_budget_repo" --argjson pr "$merged_pr_number" '.prs[] | select(.repo==$repo and .pr==$pr) | .steps | has("remote_delete")')"
    cleanup_remote_state="$(printf '%s' "$cleanup_binding" | jq -r --arg repo "$cleanup_budget_repo" --argjson pr "$merged_pr_number" '.prs[] | select(.repo==$repo and .pr==$pr) | .steps.remote_delete.status // "absent"')"
    [ "$cleanup_remote_declared" = false ] || [ "$cleanup_skip_remote" -eq 1 ] || [ "$cleanup_remote_state" = completed ] || [ "$cleanup_remote_state" = skipped_by_policy ] || { echo "Local cleanup skipped while remote cleanup pending; explicit separate remote step required" >&2; exit 2; }
    for cleanup_skipped in remote_delete local_cleanup; do
      # A spec/plan/fork has no frozen remote-deletion duty to discharge.
      [ "$cleanup_skipped" != remote_delete ] || [ "$cleanup_remote_declared" = true ] || continue
      cleanup_skipped_state="$(printf '%s' "$cleanup_binding" | jq -r --arg repo "$cleanup_budget_repo" --argjson pr "$merged_pr_number" --arg step "$cleanup_skipped" '.prs[] | select(.repo==$repo and .pr==$pr) | .steps[$step].status // "pending"')"
      [ "$cleanup_skipped_state" = completed ] || [ "$cleanup_skipped_state" = skipped_by_policy ] || {
      workflow_merge_budget_before policy_skip "$cleanup_skipped" || exit 2
      workflow_merge_budget_after policy_skip "$cleanup_skipped" 0 >/dev/null || exit 2
      }
    done
    echo "Branch cleanup skipped by declared policy; retained resources independently verified."
  elif [ "$cleanup_local_complete" = completed ] || [ "$cleanup_local_complete" = skipped_by_policy ]; then
    cleanup_skip_local=2
  else
    workflow_merge_budget_before local_cleanup local_cleanup ${cleanup_reentry_args[@]+"${cleanup_reentry_args[@]}"} || exit 2
  fi
fi

if [ "$inspect_targets" -eq 0 ] && [ "$cleanup_skip_local" -eq 0 ]; then
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

# Remember where this repository was pointing before we move it.
#
# This script has to check out the base branch to fast-forward it, but the caller
# is frequently a worktree-isolated agent — and in that case CLEANUP_REPO_ROOT is
# the shared main clone, not the agent's worktree. Leaving it parked on the base
# branch is a side effect the caller never asked for, and it has two real costs:
# a hand-run deploy from a clone parked on an integration branch ships unreleased
# code, and a branch left checked out here cannot be checked out by any other
# worktree. Capture the ref now and restore it on exit; the base branch still
# gets fetched and fast-forwarded either way.
ORIGINAL_REF=""
ORIGINAL_REF_KIND=""
if ORIGINAL_REF="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)"; then
  ORIGINAL_REF_KIND="branch"
elif ORIGINAL_REF="$(git rev-parse --quiet --verify HEAD 2>/dev/null)"; then
  ORIGINAL_REF_KIND="detached"
else
  ORIGINAL_REF=""
fi
BASE_CHECKED_OUT=0

# Best effort by contract: this must never change the script's exit status, so
# every branch returns 0 and every git call is guarded.
restore_original_ref() {
  [ "$BASE_CHECKED_OUT" -eq 1 ] || return 0
  [ -n "$ORIGINAL_REF" ] || return 0

  # The branch we started on may be the very one we just deleted.
  if [ "$ORIGINAL_REF_KIND" = "branch" ] && [ "$ORIGINAL_REF" = "$TO_DELETE" ]; then
    echo "Leaving $CLEANUP_REPO_ROOT on $DEVELOP_BRANCH (its previous branch '$TO_DELETE' was deleted)."
    return 0
  fi

  if ! CURRENT_REF="$(git -C "$CLEANUP_REPO_ROOT" symbolic-ref --quiet --short HEAD 2>/dev/null)"; then
    if ! CURRENT_REF="$(git -C "$CLEANUP_REPO_ROOT" rev-parse --quiet --verify HEAD 2>/dev/null)"; then
      CURRENT_REF=""
    fi
  fi
  [ "$CURRENT_REF" = "$ORIGINAL_REF" ] && return 0

  if [ "$ORIGINAL_REF_KIND" = "branch" ] \
    && ! git -C "$CLEANUP_REPO_ROOT" show-ref --verify --quiet "refs/heads/$ORIGINAL_REF"; then
    echo "WARNING: cannot restore $CLEANUP_REPO_ROOT to '$ORIGINAL_REF' (branch no longer exists); it stays on $DEVELOP_BRANCH." >&2
    return 0
  fi

  if git -C "$CLEANUP_REPO_ROOT" checkout --quiet "$ORIGINAL_REF" 2>/dev/null; then
    echo "Restored $CLEANUP_REPO_ROOT to '$ORIGINAL_REF' (it was moved to $DEVELOP_BRANCH only to fast-forward it)."
  else
    echo "WARNING: could not restore $CLEANUP_REPO_ROOT to '$ORIGINAL_REF' (uncommitted changes?); it stays on $DEVELOP_BRANCH." >&2
  fi
  return 0
}
trap restore_original_ref EXIT

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

reenter_base_worktree_if_needed() {
  local current_root base_worktree script_path script_dir_real tracker_repo_root tracker_repo_root_real
  local reenter_args=()

  # Git refuses to check out a branch that is already checked out in another
  # linked worktree. When cleanup is invoked from a merged PR worktree, continue
  # from the existing base-branch worktree instead of failing on checkout.
  current_root="$(CDPATH='' cd -- "$CLEANUP_REPO_ROOT" && pwd -P)" || return 1
  base_worktree="$(git -C "$CLEANUP_REPO_ROOT" worktree list --porcelain | awk -v branch="branch refs/heads/$DEVELOP_BRANCH" '
    /^worktree / { wt = substr($0, 10) }
    $0 == branch  { print wt; exit }
  ' || true)"

  [ -n "$base_worktree" ] || return 0
  base_worktree="$(CDPATH='' cd -- "$base_worktree" && pwd -P)" || return 1
  [ "$base_worktree" != "$current_root" ] || return 0

  if [ "${POST_MERGE_CLEANUP_REENTERED:-}" = "1" ]; then
    echo "ERROR: base branch '$DEVELOP_BRANCH' is checked out at '$base_worktree', but cleanup already re-entered once from '$current_root'." >&2
    return 1
  fi

  script_path=""
  script_dir_real=""
  if [ -f "$SCRIPT_DIR/post-merge-cleanup.sh" ]; then
    script_dir_real="$(CDPATH='' cd -- "$SCRIPT_DIR" && pwd -P)" || return 1
    case "$script_dir_real" in
      "$current_root"|"$current_root"/*)
        ;;
      *)
        script_path="$SCRIPT_DIR/post-merge-cleanup.sh"
        ;;
    esac
  fi
  if [ -z "$script_path" ]; then
    script_path="$base_worktree/scripts/development-workflow/post-merge-cleanup.sh"
  fi
  if [ ! -f "$script_path" ]; then
    echo "ERROR: cleanup helper is missing from the surviving checkout: $script_path" >&2
    return 1
  fi

  echo "Base branch '$DEVELOP_BRANCH' is already checked out at '$base_worktree'. Re-entering cleanup through the workflow hub helper..."
  if [ -n "$target_repo" ]; then
    reenter_args+=(--repo "$target_repo")
  fi
  tracker_repo_root="$HUB_REPO_ROOT"
  tracker_repo_root_real="$(CDPATH='' cd -- "$tracker_repo_root" && pwd -P)" || return 1
  if [ "$tracker_repo_root_real" = "$current_root" ]; then
    tracker_repo_root="$base_worktree"
  fi
  reenter_args+=(--repo-root "$tracker_repo_root" --cleanup-repo-root "$base_worktree" --base "$DEVELOP_BRANCH")
  if [ -n "$merged_pr_number" ]; then
    reenter_args+=(--pr "$merged_pr_number")
  fi
  reenter_args+=("$TO_DELETE")

  exec env POST_MERGE_CLEANUP_REENTERED=1 "$script_path" "${reenter_args[@]}"
}

reenter_base_worktree_if_needed

echo "Fetching origin..."
# --prune: remove stale remote-tracking refs (e.g. origin/<merged-branch>)
git fetch origin --prune

# When cleanup runs inside the caller's own linked worktree, still on the merged
# branch, do not check the base branch out there (#1386): a linked worktree left
# on the base holds it against every other checkout, and uncommitted changes in
# the caller's worktree would make that checkout fail before the tracker work.
# Reaching this point means no other worktree has the base checked out (the
# re-entry above would have moved there), so fast-forward the base ref directly;
# the caller's worktree is detached onto it below, before the branch delete.
CALLER_ON_MERGED_BRANCH=0
if [ "$ORIGINAL_REF_KIND" = "branch" ] && [ "$ORIGINAL_REF" = "$TO_DELETE" ] \
  && is_caller_worktree "$CLEANUP_REPO_ROOT" && is_linked_worktree "$CLEANUP_REPO_ROOT"; then
  CALLER_ON_MERGED_BRANCH=1
fi

if [ "$CALLER_ON_MERGED_BRANCH" -eq 1 ]; then
  echo "Fast-forwarding $DEVELOP_BRANCH without checking it out in the calling worktree..."
  # Same outcomes as the --ff-only pull on the other path: create the branch
  # when it is missing, do nothing when it already contains origin's tip
  # (including when it is ahead), fast-forward otherwise, and fail when the two
  # have diverged. The '<src>:<dst>' fetch refuses non-fast-forward updates.
  if ! git show-ref --verify --quiet "refs/heads/$DEVELOP_BRANCH"; then
    git branch --quiet --track "$DEVELOP_BRANCH" "refs/remotes/origin/$DEVELOP_BRANCH"
  elif git merge-base --is-ancestor "refs/remotes/origin/$DEVELOP_BRANCH" "refs/heads/$DEVELOP_BRANCH"; then
    echo "$DEVELOP_BRANCH already contains origin/$DEVELOP_BRANCH."
  else
    git fetch origin "refs/heads/$DEVELOP_BRANCH:refs/heads/$DEVELOP_BRANCH"
  fi
else
echo "Checking out $DEVELOP_BRANCH..."
git checkout "$DEVELOP_BRANCH"
BASE_CHECKED_OUT=1

echo "Pulling $DEVELOP_BRANCH..."
# Use explicit 'origin <branch>' so this works even when the local branch has no upstream
# tracking set (e.g. integration branches created/pushed without --set-upstream).
# --ff-only: fail cleanly if the branch diverged (e.g. local commits) instead of creating a merge.
git pull --ff-only origin "$DEVELOP_BRANCH"
fi

if [ "$branch_owner_kind" != implementation ] || [ "$(printf '%s' "$cleanup_binding" | jq -r --arg repo "$cleanup_budget_repo" --argjson pr "$merged_pr_number" '.prs[] | select(.repo==$repo and .pr==$pr) | .remoteCleanup')" = false ]; then
  cleanup_remote_implementation_branch "$TO_DELETE"
elif [ "$cleanup_skip_remote" -eq 1 ]; then
  workflow_merge_budget_before policy_skip remote_delete || exit 2
  workflow_merge_budget_after policy_skip remote_delete 0 >/dev/null || exit 2
elif [ "$(workflow_merge_budget_helper check --session "$merge_session" --repo "$cleanup_budget_repo" --pr "$merged_pr_number" --phase remote_delete | jq -r '.stepStatus')" = completed ]; then
  print_kv REMOTE_DELETE_RESULT already_verified
else
  workflow_merge_budget_before remote_delete remote_delete || exit 2
  cleanup_remote_status=0
  cleanup_remote_implementation_branch "$TO_DELETE" || cleanup_remote_status=$?
  workflow_merge_budget_after remote_delete remote_delete "$cleanup_remote_status" >/dev/null || exit 2
fi

SKIP_LOCAL_DELETE=0
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
if [ -n "$WORKTREE_PATH" ] && is_caller_worktree "$WORKTREE_PATH"; then
  # The merged branch is checked out in the caller's own working tree. Removing
  # that worktree deletes the directory the caller is running in and kills the
  # run before it can update the tracker (#1386). Detach it onto the updated
  # base instead, then delete the branch.
  print_kv CALLER_WORKTREE_PATH "$WORKTREE_PATH"
  detach_target=""
  detach_err=""
  if detach_target="$(git rev-parse --verify --quiet "refs/heads/${DEVELOP_BRANCH}^{commit}")" \
    && detach_err="$(git -C "$WORKTREE_PATH" checkout --quiet --detach "$detach_target" 2>&1)"; then
    print_kv CALLER_WORKTREE_ACTION "detached"
    echo "Worktree '$WORKTREE_PATH' is the calling worktree; detached it onto $DEVELOP_BRANCH ($detach_target) instead of removing it."
  else
    SKIP_LOCAL_DELETE=1
    print_kv CALLER_WORKTREE_ACTION "detach_failed"
    print_kv LOCAL_DELETE_RESULT "skipped"
    print_kv LOCAL_DELETE_REASON "caller_worktree_detach_failed"
    echo "WARNING: worktree '$WORKTREE_PATH' is the calling worktree and could not be detached from '$TO_DELETE' (${detach_err:-base branch '$DEVELOP_BRANCH' not found}); leaving the worktree and local branch in place. Detach it and delete the branch by hand." >&2
  fi
elif [ -n "$WORKTREE_PATH" ]; then
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
if [ "$SKIP_LOCAL_DELETE" -eq 0 ]; then
  # -D: branch is already merged on remote (squash/rebase merges don't leave tip in develop)
  git branch -D "$TO_DELETE"
  print_kv LOCAL_DELETE_RESULT "deleted"
fi
fi

fi

if [ "$inspect_targets" -eq 0 ] && [ "$cleanup_skip_local" -eq 0 ]; then
  cleanup_local_proof=()
  [ "${SKIP_LOCAL_DELETE:-0}" -eq 0 ] || cleanup_local_proof+=(--policy-skip caller_worktree_detach_failed)
  workflow_merge_budget_after local_cleanup local_cleanup 0 ${cleanup_local_proof[@]+"${cleanup_local_proof[@]}"} >/dev/null || exit 2
fi

# --- Update tracker status and close associated GitHub issue (if any) ---


# fetch_pr_closing_issues <pr_repo> <pr_number> [<qualified_repo>]
# By default matches bare "#NNN" references. When <qualified_repo> (an
# owner/repo slug) is given, matches only "<qualified_repo>#NNN" references
# instead — used to honour explicit hub-tracker references in a product-repo
# PR (#1538); bare "#NNN" there names a product-repo issue.
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
  local pr_repo="${1:-}"
  local pr_number="${2:-}"
  local qualified_repo="${3:-}"
  # Function-local copy: the shared constant stays the single source of the
  # keyword grammar; the qualified form below only rewrites its trailing ref.
  local CLOSING_KEYWORD_REGEX="$CLOSING_KEYWORD_REGEX"
  local pr_body stripped_pr_body keyword_lines matched_refs stage_status
  if { [ "$#" -ne 2 ] && [ "$#" -ne 3 ]; } || [ -z "$pr_repo" ] || [[ ! "$pr_number" =~ ^[0-9]+$ ]]; then
    echo "ERROR: fetch_pr_closing_issues requires <pr_repo> <pr_number> [<qualified_repo>]." >&2
    return 2
  fi
  if [ "$#" -eq 3 ]; then
    if ! workflow_is_valid_github_repo_slug "$qualified_repo"; then
      echo "ERROR: fetch_pr_closing_issues <qualified_repo> must be an owner/repo GitHub repository slug." >&2
      return 2
    fi
    # Swap the shared regex's trailing bare "#[0-9]+" for "<slug>#[0-9]+".
    # A slug's only regex metacharacter is '.'.
    CLOSING_KEYWORD_REGEX="${CLOSING_KEYWORD_REGEX%'#[0-9]+'}${qualified_repo//./\\.}#[0-9]+"
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
  keyword_lines="$(printf '%s' "$stripped_pr_body" | grep -ioE "$CLOSING_KEYWORD_REGEX")"
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

# hub_github_repo_slug
# Echoes the owner/repo slug of the workflow hub's own repository (the one
# that owns the issue tracker this script mutates), resolved from
# $HUB_REPO_ROOT. Deliberately does NOT go through repo_slug(): that honours
# WORKFLOW_TARGET_GITHUB_REPO, which names the *product* repo in hub mode.
# Returns 1 when the slug cannot be resolved.
hub_github_repo_slug() {
  local slug
  slug="$(cd "$HUB_REPO_ROOT" && gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null)" || return 1
  [ -n "$slug" ] || return 1
  printf '%s\n' "$slug"
}

# pr_repo_is_hub_tracker_repo <pr_repo>
# Returns 0 when <pr_repo> is the repository whose issue numbers this script's
# tracker mutations (`gh issue view/close`, project status) address, 1 when it
# is a different repository (a workflow_hub product repo), and 2 when that
# cannot be determined. Outside a product-repo cleanup (TARGET_GITHUB_REPO
# empty) the PR always lives in the current repository.
pr_repo_is_hub_tracker_repo() {
  local pr_repo="$1" hub_slug
  [ -n "$TARGET_GITHUB_REPO" ] || return 0
  hub_slug="$(hub_github_repo_slug)" || return 2
  if [ "$(printf '%s' "$pr_repo" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$hub_slug" | tr '[:upper:]' '[:lower:]')" ]; then
    return 0
  fi
  return 1
}

# pr_close_label <pr_repo> <pr_number>
# Echoes how a close comment names the merged PR: "PR #N" when it lives in the
# hub tracker's own repository, else "<pr_repo>#N" so a product-repo PR number
# is not read as a hub PR number (#1538). An undeterminable hub is treated as
# "not the hub" (the qualified form is never wrong; the bare one can be).
pr_close_label() {
  local pr_repo="$1" pr_number="$2" status=0
  if [ -n "$pr_repo" ]; then
    pr_repo_is_hub_tracker_repo "$pr_repo" || status=$?
    if [ "$status" -ne 0 ]; then
      printf '%s#%s\n' "$pr_repo" "$pr_number"
      return 0
    fi
  fi
  printf 'PR #%s\n' "$pr_number"
}

# fetch_hub_tracker_closing_issues <pr_repo> <pr_number>
# Like fetch_pr_closing_issues, but only returns issue numbers that belong to
# the hub tracker (#1538). A bare "Fixes #NNN" in a PR is numbered in the
# repository the PR lives in; when that is a workflow_hub product repo, the
# same number in the hub is an unrelated issue, so bare refs are NOT applied
# (announced on stderr) and only explicit "Fixes <hub owner/repo>#NNN" refs
# are honoured. When the PR lives in the hub's own repo this is identical to
# fetch_pr_closing_issues. Same return contract as fetch_pr_closing_issues;
# an undeterminable hub slug is warned about and yields no refs rather than
# guessing (never mutating a tracker on a guess).
fetch_hub_tracker_closing_issues() {
  local pr_repo="${1:-}" pr_number="${2:-}" hub_slug status=0
  if [ "$#" -ne 2 ] || [ -z "$pr_repo" ] || [[ ! "$pr_number" =~ ^[0-9]+$ ]]; then
    echo "ERROR: fetch_hub_tracker_closing_issues requires <pr_repo> <pr_number>." >&2
    return 2
  fi
  pr_repo_is_hub_tracker_repo "$pr_repo" || status=$?
  case "$status" in
    0) fetch_pr_closing_issues "$pr_repo" "$pr_number" ;;
    1)
      hub_slug="$(hub_github_repo_slug)" || return 1
      echo "NOTE: PR #${pr_number} lives in product repository '${pr_repo}', not the workflow hub ('${hub_slug}'); bare closing-keyword refs (e.g. 'Fixes #NNN') name product-repo issues and are NOT applied to the hub tracker. Only 'Fixes ${hub_slug}#NNN' references are honoured." >&2
      fetch_pr_closing_issues "$pr_repo" "$pr_number" "$hub_slug"
      ;;
    *)
      echo "WARNING: could not resolve the workflow hub GitHub repository; closing-keyword refs from PR #${pr_number} in '${pr_repo}' were NOT applied to the hub tracker." >&2
      return 0
      ;;
  esac
}

cleanup_close_issue() {
  local issue="$1" comment="$2" status=0 binding closure_effect comment_effect
  workflow_merge_budget_before issue_close "issue_close:$issue" --issue "$issue" --status Merged || return 1
  binding="$(workflow_merge_budget_helper check --session "$WORKFLOW_MERGE_BUDGET_SESSION" --repo "$WORKFLOW_MERGE_BUDGET_REPO" --pr "$WORKFLOW_MERGE_BUDGET_PR" --step "issue_close:$issue" --phase issue_close --issue "$issue")" || return 1
  printf '%s' "$binding" | jq -e --arg repo "$WORKFLOW_MERGE_BUDGET_REPO" --argjson pr "$WORKFLOW_MERGE_BUDGET_PR" --arg key "issue_close:$issue" --arg comment "$comment" '.prs[] | select(.repo==$repo and .pr==$pr) | .steps[$key].expectedComment == $comment' >/dev/null || return 1
  closure_effect="$(printf '%s' "$binding" | jq -r --arg repo "$WORKFLOW_MERGE_BUDGET_REPO" --argjson pr "$WORKFLOW_MERGE_BUDGET_PR" --arg key "issue_close:$issue" '.prs[] | select(.repo==$repo and .pr==$pr) | .steps[$key].effects.closure')"
  comment_effect="$(printf '%s' "$binding" | jq -r --arg repo "$WORKFLOW_MERGE_BUDGET_REPO" --argjson pr "$WORKFLOW_MERGE_BUDGET_PR" --arg key "issue_close:$issue" '.prs[] | select(.repo==$repo and .pr==$pr) | .steps[$key].effects.comment')"
  if [ "$closure_effect" = pending ] && [ "$comment_effect" = pending ]; then
    gh issue close "$issue" --comment "$comment" || status=$?
  elif [ "$closure_effect" = pending ]; then
    gh issue close "$issue" || status=$?
  elif [ "$comment_effect" = pending ]; then
    gh issue comment "$issue" --body "$comment" || status=$?
  fi
  workflow_merge_budget_after issue_close "issue_close:$issue" "$status" --issue "$issue" --status Merged >/dev/null || return 1
  return "$status"
}

# close_issues_from_pr <pr_number> <issue_numbers_newline_list> [<pr_repo>]
# For each issue number in the list, updates the tracker status to Merged,
# closes the issue if it is still open (commenting with the closing PR
# number), and reasserts Merged status after close. A `gh issue view` failure
# for a given issue is counted and reported but does not stop processing of
# the remaining issues in the list; once all issues have been processed, a
# nonzero view-failure count makes this function return 1, and the caller
# must treat that as fatal (`close_issues_from_pr ... || exit 1`), matching
# the aggregate fatal-on-view-failure behavior this replaces at both call
# sites. This is distinct from a `gh issue close` failure, which remains a
# legacy warning-only condition; an admitted session records Interrupted and
# stops dispatching further mutations until explicit verified recovery. The issue-numbers list may be empty (a
# no-op loop), but <pr_number> must be a non-empty numeric PR number so an
# invalid caller cannot produce a close comment like "Closed by PR #.".
# When the optional <pr_repo> is a different repository than the hub tracker's
# (a workflow_hub product repo), the close comment names the PR as
# "<pr_repo>#N" so it does not read as a hub PR number (#1538).
close_issues_from_pr() {
  local pr_number="${1:-}"
  local issue_list="${2:-}"
  local pr_repo="${3:-}"
  local issue_num issue_state view_failures=0 close_pr_label
  if { [ "$#" -ne 2 ] && [ "$#" -ne 3 ]; } || [[ ! "$pr_number" =~ ^[0-9]+$ ]]; then
    echo "ERROR: close_issues_from_pr requires <pr_number> (numeric) <issue_numbers_newline_list> [<pr_repo>]." >&2
    return 2
  fi
  close_pr_label="$(pr_close_label "$pr_repo" "$pr_number")"
  while IFS= read -r issue_num; do
    [ -z "$issue_num" ] && continue
    echo "Processing issue #${issue_num} from PR #${pr_number} closing keywords..."
    if ! issue_state="$(gh issue view "$issue_num" --json state --jq '.state' 2>/dev/null)"; then
      echo "Warning: could not query issue #${issue_num}; skipping close and tracker update for this ref." >&2
      view_failures=$((view_failures + 1))
      continue
    fi
    update_tracker_status_best_effort "$issue_num" "Merged"
    workflow_merge_budget_helper check --session "$WORKFLOW_MERGE_BUDGET_SESSION" --repo "$WORKFLOW_MERGE_BUDGET_REPO" --pr "$WORKFLOW_MERGE_BUDGET_PR" >/dev/null || return 2
    if [ "$issue_state" = "OPEN" ]; then
      echo "Closing issue #${issue_num}..."
      if cleanup_close_issue "$issue_num" "Closed by ${close_pr_label}."; then
        echo "Reasserting issue #${issue_num} tracker status as Merged after close..."
        update_tracker_status_best_effort "$issue_num" "Merged" "" "allow-backward"
      else
        echo "Warning: could not close issue #${issue_num}; session interrupted." >&2
        return 2
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

# The same closing-keyword parser and branch precedence used below supplies
# the budget projection. This path never fetches/checks out/deletes or writes.
if [ "$inspect_targets" -eq 1 ]; then
  inspection_repo="$TARGET_GITHUB_REPO"
  [ -n "$inspection_repo" ] || inspection_repo="$(repo_slug)"
  inspection_owner="$(hub_github_repo_slug)" || exit 1
  inspection_cross="$(gh pr view "$merged_pr_number" --repo "$inspection_repo" --json isCrossRepository --jq ' .isCrossRepository')" || exit 1
  case "$inspection_cross" in true|false) ;; *) echo "Unknown PR branch ownership" >&2; exit 1 ;; esac
  inspection_provider="$(workflow_normalize_issue_tracker_provider "$(workflow_config_provider issue_tracker "$HUB_REPO_ROOT/.ai-dev-workflow.yaml")")"
  case "$inspection_provider" in '') inspection_provider=none ;; github_projects|github_issues|linear|none) ;; *) echo "Unknown tracker provider" >&2; exit 1 ;; esac
  inspection_status="Merged"
  inspection_refs=""
  case "$BRANCH_TYPE" in
    spec) inspection_status="Spec Ready"; inspection_refs="$ISSUE_NUMBER" ;;
    plan) inspection_status="Plan Ready"; inspection_refs="$ISSUE_NUMBER" ;;
    *)
      if [ "$branch_owner_kind" = implementation ]; then
      inspection_refs="$(fetch_hub_tracker_closing_issues "$inspection_repo" "$merged_pr_number")" || exit 1
      if [ -n "$ISSUE_NUMBER" ] && { [ "$ISSUE_ID_TYPE" = numeric ] || [ -z "$inspection_refs" ]; }; then
        inspection_refs="$(printf '%s\n%s\n' "$ISSUE_NUMBER" "$inspection_refs" | sed '/^$/d' | sort -un)"
      fi
      fi ;;
  esac
  if [ "$inspection_provider" = linear ] && [ -n "$inspection_refs" ]; then
    # Existing Linear ownership needs a native identifier; a numeric GitHub
    # reference cannot authorize an unrelated Linear mutation.
    [ "$ISSUE_ID_TYPE" = team-prefixed ] || { echo "Unknown native Linear issue ownership" >&2; exit 1; }
    inspection_refs="$ISSUE_IDENTIFIER"
  fi
  inspection_worktrees="$(git -C "$CLEANUP_REPO_ROOT" worktree list --porcelain | awk -v branch="branch refs/heads/$TO_DELETE" '
    /^worktree / { path=substr($0,10) }
    $0==branch { print path }
  ' | jq -Rsc --arg callers "$CALLER_WORKTREES" 'split("\n") | map(select(length>0) | . as $root | {root:$root,caller:($callers|split("\n")|index($root)!=null)})')"
  inspection_participants="$(git -C "$CLEANUP_REPO_ROOT" worktree list --porcelain | awk -v base="branch refs/heads/$DEVELOP_BRANCH" -v branch="branch refs/heads/$TO_DELETE" '
    /^worktree / { path=substr($0,10) }
    $0==base || $0==branch { print path }
  ' | jq -Rsc 'split("\n") | map(select(length>0))')"
  inspection_close_comment="Closed by $(pr_close_label "$inspection_repo" "$merged_pr_number")."
  printf '%s\n' "$inspection_refs" | jq -Rsc --argjson cross "$inspection_cross" --argjson worktrees "$inspection_worktrees" --arg remote "$branch_owner_kind" --argjson participants "$inspection_participants" --arg comment "$inspection_close_comment" --arg provider "$inspection_provider" --arg repo "$inspection_owner" --arg status "$inspection_status"     '{worktrees:$worktrees,remoteCleanup:($remote=="implementation" and ($cross|not)),participants:$participants,issues:(split("\n") | map(select(length>0) | {id:.,provider:$provider,repo:$repo,status:$status,statusPolicy:(if $provider=="github_projects" then "at_least" else "exact" end),close:($status=="Merged" and $provider!="linear"),tracker:($provider=="github_projects" or $provider=="linear"),closeComment:$comment}))}'
  exit 0
fi

cleanup_tracker_provider="$(workflow_normalize_issue_tracker_provider "$(workflow_config_provider issue_tracker "$HUB_REPO_ROOT/.ai-dev-workflow.yaml")")"
if [ "$cleanup_tracker_provider" = linear ]; then
  cd "$HUB_REPO_ROOT"
  # Native Linear duties belong to the frozen owning tracker, not a same-number
  # GitHub issue. The existing bridge emits work while the journal stays pending.
  while IFS=$'\t' read -r cleanup_linear_step cleanup_linear_issue cleanup_linear_status; do
    [ -n "$cleanup_linear_step" ] || continue
    cleanup_linear_binding="$(workflow_merge_budget_helper check --session "$merge_session" --repo "$cleanup_budget_repo" \
      --pr "$merged_pr_number" --phase tracker --step "$cleanup_linear_step" --issue "$cleanup_linear_issue")" || exit 2
    [ "$(printf '%s' "$cleanup_linear_binding" | jq -r '.stepStatus')" != completed ] || continue
    update_tracker_status_best_effort "$cleanup_linear_issue" "$cleanup_linear_status"
    cleanup_linear_binding="$(workflow_merge_budget_helper check --session "$merge_session" --repo "$cleanup_budget_repo" \
      --pr "$merged_pr_number" --phase tracker --step "$cleanup_linear_step" --issue "$cleanup_linear_issue")" || exit 2
    [ "$(printf '%s' "$cleanup_linear_binding" | jq -r '.stepStatus')" = completed ] || {
      echo "Linear reconciliation pending; apply the emitted native action through the owning bridge, then record fresh proof and resume." >&2
      exit 2
    }
  done < <(printf '%s' "$cleanup_binding" | jq -r --arg repo "$cleanup_budget_repo" --argjson pr "$merged_pr_number" '.prs[] | select(.repo==$repo and .pr==$pr) | . as $target | .steps | to_entries[] | select(.value.phase=="tracker") | .value.issue as $issue | [.key,$issue,($target.issues[] | select(.id==$issue and .provider=="linear") | .status)] | @tsv')
elif [ -n "$ISSUE_IDENTIFIER" ]; then
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
        PR_OVERRIDE_ISSUES="$(fetch_hub_tracker_closing_issues "$pr_override_repo" "$PR_FOR_OVERRIDE")" || {
          echo "ERROR: could not fetch PR #${PR_FOR_OVERRIDE} body from '$pr_override_repo' (gh command failed)." >&2
          exit 1
        }
      fi
    fi

    if [ -n "$PR_OVERRIDE_ISSUES" ]; then
      echo "Team-prefixed identifier '$ISSUE_IDENTIFIER' in branch '$TO_DELETE' is ambiguous; using closing keyword refs from PR #${PR_FOR_OVERRIDE} instead: $(printf '%s' "$PR_OVERRIDE_ISSUES" | tr '\n' ' ')"
      close_issues_from_pr "$PR_FOR_OVERRIDE" "$PR_OVERRIDE_ISSUES" "$pr_override_repo" || exit 1
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
          CLOSE_COMMENT="Closed by $(pr_close_label "$merged_pr_repo" "$MERGED_PR")."
        elif [ -n "$VERIFIED_MERGED_PR" ]; then
          MERGED_PR="$VERIFIED_MERGED_PR"
          CLOSE_COMMENT="Closed by $(pr_close_label "$merged_pr_repo" "$MERGED_PR")."
        fi
        if [ -n "$MERGED_PR" ]; then
          echo "Closing issue #$ISSUE_NUMBER..."
          if cleanup_close_issue "$ISSUE_NUMBER" "$CLOSE_COMMENT"; then
            echo "Reasserting issue #$ISSUE_NUMBER tracker status as Merged after close..."
            update_tracker_status_best_effort "$ISSUE_NUMBER" "Merged" "" "allow-backward"
          else
            echo "Warning: could not close issue #$ISSUE_NUMBER; session interrupted." >&2
            exit 2
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
        if ! EXTRA_CLOSES="$(fetch_hub_tracker_closing_issues "$merged_pr_repo" "$MERGED_PR")"; then
          echo "ERROR: could not fetch PR #${MERGED_PR} closing refs from '$merged_pr_repo' (gh command failed)." >&2
          exit 1
        fi
        EXTRA_CLOSES="$(printf '%s\n' "$EXTRA_CLOSES" | grep -vx "$ISSUE_NUMBER" || true)"
        if [ -n "$EXTRA_CLOSES" ]; then
          echo "PR #${MERGED_PR} also closes: $(printf '%s' "$EXTRA_CLOSES" | tr '\n' ' ')"
          close_issues_from_pr "$MERGED_PR" "$EXTRA_CLOSES" "$merged_pr_repo" || exit 1
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
        if ! CLOSES_ISSUES="$(fetch_hub_tracker_closing_issues "$pr_closes_repo" "$CLOSING_PR")"; then
          echo "ERROR: could not fetch PR #${CLOSING_PR} body from '$pr_closes_repo' (gh command failed)." >&2
          exit 1
        fi
        if [ -n "$CLOSES_ISSUES" ]; then
          echo "Found closing keyword refs in PR #${CLOSING_PR}: issues $(printf '%s' "$CLOSES_ISSUES" | tr '\n' ' ')"
          cd "$HUB_REPO_ROOT"
          close_issues_from_pr "$CLOSING_PR" "$CLOSES_ISSUES" "$pr_closes_repo" || exit 1
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
# Already satisfied duties use their own durable intent and independent proof.
# This never masks an uncertain adapter mutation or supplies caller success.
cleanup_pending="$(workflow_merge_budget_helper report --session "$merge_session" | jq -r --arg repo "$cleanup_budget_repo" --argjson pr "$merged_pr_number" '
  .prs[] | select(.repo==$repo and .pr==$pr) | .steps | to_entries[]
  | select(.value.status=="pending" and (.value.phase=="tracker" or .value.phase=="issue_close"))
  | [.key,.value.phase,.value.issue] | @tsv')"
while IFS=$'\t' read -r cleanup_step cleanup_phase cleanup_issue; do
  [ -n "$cleanup_step" ] || continue
  cleanup_expected="$(workflow_merge_budget_helper report --session "$merge_session" | jq -r --arg repo "$cleanup_budget_repo" --argjson pr "$merged_pr_number" --arg issue "$cleanup_issue" '.prs[] | select(.repo==$repo and .pr==$pr) | .issues[] | select((.id|tostring)==$issue) | .status')"
  if [ "$cleanup_phase" = issue_close ]; then
    cleanup_comment="$(workflow_merge_budget_helper report --session "$merge_session" | jq -r --arg repo "$cleanup_budget_repo" --argjson pr "$merged_pr_number" --arg step "$cleanup_step" '.prs[] | select(.repo==$repo and .pr==$pr) | .steps[$step].expectedComment')"
    cleanup_close_issue "$cleanup_issue" "$cleanup_comment" || exit 2
    continue
  fi
  workflow_merge_budget_before "$cleanup_phase" "$cleanup_step" --issue "$cleanup_issue" --status "$cleanup_expected" || exit 2
  workflow_merge_budget_after "$cleanup_phase" "$cleanup_step" 0 --issue "$cleanup_issue" --status "$cleanup_expected" --no-op >/dev/null || exit 2
done <<< "$cleanup_pending"

if [ "$cleanup_skip_local" -eq 1 ]; then
  echo "Done. Owned follow-up verified; branch resources retained by policy."
  exit 0
fi
if [ "$cleanup_skip_local" -eq 2 ]; then
  echo "Done. Owned follow-up verified; previous local cleanup outcome independently verified."
  exit 0
fi

FINAL_REF_AFTER_CLEANUP="$DEVELOP_BRANCH"
if [ "$BASE_CHECKED_OUT" -eq 1 ] && [ -n "$ORIGINAL_REF" ]; then
  if [ "$ORIGINAL_REF_KIND" = "branch" ] && [ "$ORIGINAL_REF" != "$TO_DELETE" ] \
    && git -C "$CLEANUP_REPO_ROOT" show-ref --verify --quiet "refs/heads/$ORIGINAL_REF"; then
    FINAL_REF_AFTER_CLEANUP="$ORIGINAL_REF"
  elif [ "$ORIGINAL_REF_KIND" = "detached" ]; then
    FINAL_REF_AFTER_CLEANUP="$ORIGINAL_REF"
  fi
fi
if [ "$LOCAL_BRANCH_MISSING" -eq 1 ]; then
  echo "Done. $DEVELOP_BRANCH is updated; exit cleanup will restore '$FINAL_REF_AFTER_CLEANUP'; local branch '$TO_DELETE' was already removed."
elif [ "$CALLER_ON_MERGED_BRANCH" -eq 1 ] && [ "$SKIP_LOCAL_DELETE" -eq 0 ]; then
  echo "Done. $DEVELOP_BRANCH is updated; the calling worktree $CLEANUP_REPO_ROOT is detached at it; local branch '$TO_DELETE' has been removed locally."
elif [ "$CALLER_ON_MERGED_BRANCH" -eq 1 ]; then
  echo "Done. $DEVELOP_BRANCH is updated; local branch '$TO_DELETE' was KEPT and the calling worktree $CLEANUP_REPO_ROOT stays on it because it could not be detached (see LOCAL_DELETE_REASON)."
elif [ "$SKIP_LOCAL_DELETE" -eq 1 ]; then
  echo "Done. $DEVELOP_BRANCH is updated; exit cleanup will restore '$FINAL_REF_AFTER_CLEANUP'; local branch '$TO_DELETE' was KEPT because its calling worktree could not be detached (see LOCAL_DELETE_REASON)."
else
  echo "Done. $DEVELOP_BRANCH is updated; exit cleanup will restore '$FINAL_REF_AFTER_CLEANUP'; local branch '$TO_DELETE' has been removed locally."
fi

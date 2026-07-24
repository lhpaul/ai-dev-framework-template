#!/usr/bin/env bash
# validate-branch-reuse.sh
#
# Read-only validation for reusing an existing workflow branch. Compatibility
# requires positive ancestry evidence from the explicitly approved base.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: validate-branch-reuse.sh --issue <number> --branch <branch> --approved-base <branch> --repo-root <path> [options]

Options:
  --remote <name>  Remote used for ref resolution (default: origin)
  --json           Append a JSON record after the stable key=value output
  --help           Show this help
USAGE
}

require_value() {
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
    printf 'ERROR: missing value for %s\n' "${1:-<unknown>}" >&2
    usage >&2
    exit 2
  fi
}

issue=""
branch=""
approved_base=""
repo_root=""
remote="origin"
json_output="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --issue)
      require_value "$@"
      issue="${2:-}"
      shift 2
      ;;
    --branch)
      require_value "$@"
      branch="${2:-}"
      shift 2
      ;;
    --approved-base)
      require_value "$@"
      approved_base="${2:-}"
      shift 2
      ;;
    --repo-root)
      require_value "$@"
      repo_root="${2:-}"
      shift 2
      ;;
    --remote)
      require_value "$@"
      remote="${2:-}"
      shift 2
      ;;
    --json)
      json_output="true"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'ERROR: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$issue" ] || [ -z "$branch" ] || [ -z "$approved_base" ] || [ -z "$repo_root" ]; then
  usage >&2
  exit 2
fi

case "$issue" in
  *[!0-9]*|"")
    printf 'ERROR: --issue must be a positive numeric identifier\n' >&2
    exit 2
    ;;
esac

if [ "$issue" -le 0 ]; then
  printf 'ERROR: --issue must be a positive numeric identifier\n' >&2
  exit 2
fi

if ! git check-ref-format --branch "$branch" >/dev/null 2>&1; then
  printf 'ERROR: invalid workflow branch name: %s\n' "$branch" >&2
  exit 2
fi

if ! git check-ref-format --branch "$approved_base" >/dev/null 2>&1; then
  printf 'ERROR: invalid approved base branch name: %s\n' "$approved_base" >&2
  exit 2
fi

if ! git check-ref-format --branch "$remote" >/dev/null 2>&1; then
  printf 'ERROR: invalid remote name: %s\n' "$remote" >&2
  exit 2
fi

if [ ! -d "$repo_root" ]; then
  printf 'ERROR: repository root does not exist: %s\n' "$repo_root" >&2
  exit 2
fi

repo_root="$(CDPATH='' cd -- "$repo_root" && pwd -P)"
if ! git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
  printf 'ERROR: repository root is not a Git repository: %s\n' "$repo_root" >&2
  exit 2
fi

if [ "$json_output" = "true" ] && ! command -v jq >/dev/null 2>&1; then
  printf 'ERROR: jq is required for --json output\n' >&2
  exit 2
fi

local_candidate_ref="refs/heads/$branch"
remote_candidate_ref="refs/remotes/$remote/$branch"
local_base_ref="refs/heads/$approved_base"
remote_base_ref="refs/remotes/$remote/$approved_base"

result=""
reason=""
human_action=""
candidate_source=""
candidate_ref=""
candidate_tip=""
base_source=""
base_ref=""
base_tip=""
worktree_path=""
remote_ref=""
remote_tip=""
tracking_state="not_applicable"
ahead=""
behind=""
exit_code=0

ref_state() {
  local ref="$1"
  local status
  git -C "$repo_root" show-ref --verify --quiet "$ref"
  status=$?
  case "$status" in
    0) return 0 ;;
    1) return 1 ;;
    *) return 2 ;;
  esac
}

resolve_commit() {
  local ref="$1"
  git -C "$repo_root" rev-parse --verify "${ref}^{commit}" 2>/dev/null
}

emit_output() {
  printf 'ITEM=%s\n' "$issue"
  printf 'BRANCH=%s\n' "$branch"
  printf 'APPROVED_BASE=%s\n' "$approved_base"
  printf 'REMOTE=%s\n' "$remote"
  printf 'REPO_ROOT=%s\n' "$repo_root"
  printf 'RESULT=%s\n' "$result"
  printf 'REASON=%s\n' "$reason"
  printf 'CANDIDATE_SOURCE=%s\n' "$candidate_source"
  printf 'CANDIDATE_REF=%s\n' "$candidate_ref"
  printf 'CANDIDATE_TIP=%s\n' "$candidate_tip"
  printf 'BASE_SOURCE=%s\n' "$base_source"
  printf 'BASE_REF=%s\n' "$base_ref"
  printf 'BASE_TIP=%s\n' "$base_tip"
  printf 'WORKTREE_PATH=%s\n' "$worktree_path"
  printf 'REMOTE_REF=%s\n' "$remote_ref"
  printf 'REMOTE_TIP=%s\n' "$remote_tip"
  printf 'TRACKING_STATE=%s\n' "$tracking_state"
  printf 'AHEAD=%s\n' "$ahead"
  printf 'BEHIND=%s\n' "$behind"
  printf 'HUMAN_ACTION=%s\n' "$human_action"

  if [ "$json_output" = "true" ]; then
    jq -n \
      --arg item "$issue" \
      --arg branch "$branch" \
      --arg approvedBase "$approved_base" \
      --arg remote "$remote" \
      --arg repoRoot "$repo_root" \
      --arg result "$result" \
      --arg reason "$reason" \
      --arg candidateSource "$candidate_source" \
      --arg candidateRef "$candidate_ref" \
      --arg candidateTip "$candidate_tip" \
      --arg baseSource "$base_source" \
      --arg baseRef "$base_ref" \
      --arg baseTip "$base_tip" \
      --arg worktreePath "$worktree_path" \
      --arg remoteRef "$remote_ref" \
      --arg remoteTip "$remote_tip" \
      --arg trackingState "$tracking_state" \
      --arg ahead "$ahead" \
      --arg behind "$behind" \
      --arg humanAction "$human_action" \
      '{
        item: $item,
        branch: $branch,
        approvedBase: $approvedBase,
        remote: $remote,
        repoRoot: $repoRoot,
        result: $result,
        reason: $reason,
        candidate: {
          source: $candidateSource,
          ref: $candidateRef,
          tip: $candidateTip,
          worktreePath: $worktreePath
        },
        base: {
          source: $baseSource,
          ref: $baseRef,
          tip: $baseTip
        },
        tracking: {
          remoteRef: $remoteRef,
          remoteTip: $remoteTip,
          state: $trackingState,
          ahead: $ahead,
          behind: $behind
        },
        humanAction: $humanAction
      }'
  fi
}

set +e
ref_state "$remote_base_ref"
remote_base_status=$?
ref_state "$local_base_ref"
local_base_status=$?
ref_state "$local_candidate_ref"
local_candidate_status=$?
ref_state "$remote_candidate_ref"
remote_candidate_status=$?
set -e

for ref_status in \
  "$remote_base_status" \
  "$local_base_status" \
  "$local_candidate_status" \
  "$remote_candidate_status"; do
  if [ "$ref_status" -eq 2 ]; then
    result="verification_blocked"
    reason="Git ref discovery failed while validating branch reuse"
    human_action="Restore readable repository ref state for item #$issue and retry the branch-reuse validation."
    exit_code=3
    emit_output
    exit "$exit_code"
  fi
done

if [ "$remote_base_status" -eq 0 ]; then
  base_source="remote"
  base_ref="$remote_base_ref"
elif [ "$local_base_status" -eq 0 ]; then
  base_source="local"
  base_ref="$local_base_ref"
else
  result="verification_blocked"
  reason="Approved base '$approved_base' could not be resolved from '$remote_base_ref' or '$local_base_ref'"
  human_action="Restore or fetch the approved base '$approved_base' for item #$issue, then retry without substituting another base."
  exit_code=3
  emit_output
  exit "$exit_code"
fi

if ! base_tip="$(resolve_commit "$base_ref")" || [ -z "$base_tip" ]; then
  result="verification_blocked"
  reason="Approved base ref '$base_ref' did not resolve to a commit"
  human_action="Repair the approved base '$approved_base' for item #$issue and retry branch-reuse validation."
  exit_code=3
  emit_output
  exit "$exit_code"
fi

if [ "$local_candidate_status" -eq 0 ]; then
  candidate_source="local"
  candidate_ref="$local_candidate_ref"
elif [ "$remote_candidate_status" -eq 0 ]; then
  candidate_source="remote_only"
  candidate_ref="$remote_candidate_ref"
else
  result="no_existing_branch"
  reason="No exact local, remote-tracking, or worktree-owned ref exists for '$branch'"
  human_action="Continue the canonical fresh-branch path for item #$issue from approved base '$approved_base'."
  emit_output
  exit 0
fi

if ! candidate_tip="$(resolve_commit "$candidate_ref")" || [ -z "$candidate_tip" ]; then
  result="verification_blocked"
  reason="Candidate ref '$candidate_ref' did not resolve to a commit"
  human_action="Restore unambiguous commit evidence for branch '$branch' on item #$issue and retry."
  exit_code=3
  emit_output
  exit "$exit_code"
fi

if [ "$local_candidate_status" -eq 0 ]; then
  worktree_output=""
  if ! worktree_output="$(git -C "$repo_root" worktree list --porcelain 2>/dev/null)"; then
    result="verification_blocked"
    reason="Registered worktree state could not be read for local branch '$branch'"
    human_action="Restore readable worktree metadata for item #$issue and retry branch-reuse validation."
    exit_code=3
    emit_output
    exit "$exit_code"
  fi

  worktree_paths="$(
    awk -v expected_ref="$local_candidate_ref" '
      function flush_entry() {
        if (path != "" && ref == expected_ref) {
          print path
        }
      }
      /^worktree / {
        flush_entry()
        path = substr($0, 10)
        ref = ""
        next
      }
      /^branch / {
        ref = substr($0, 8)
        next
      }
      END {
        flush_entry()
      }
    ' <<EOF
$worktree_output
EOF
  )"
  worktree_count="$(awk 'NF { count++ } END { print count + 0 }' <<< "$worktree_paths")"
  if [ "$worktree_count" -gt 1 ]; then
    result="verification_blocked"
    reason="Candidate branch '$branch' is ambiguously registered to multiple worktrees"
    human_action="Correct ambiguous worktree ownership for item #$issue and retry without deleting or rewriting the branch automatically."
    exit_code=3
    emit_output
    exit "$exit_code"
  fi
  if [ "$worktree_count" -eq 1 ]; then
    worktree_path="$worktree_paths"
    candidate_source="worktree"
  fi
fi

if [ "$remote_candidate_status" -eq 0 ]; then
  remote_ref="$remote_candidate_ref"
  if ! remote_tip="$(resolve_commit "$remote_ref")" || [ -z "$remote_tip" ]; then
    result="verification_blocked"
    reason="Remote-tracking ref '$remote_ref' did not resolve to a commit"
    human_action="Restore readable remote-tracking evidence for item #$issue and retry."
    exit_code=3
    emit_output
    exit "$exit_code"
  fi
fi

if [ "$local_candidate_status" -eq 0 ] && [ "$remote_candidate_status" -eq 0 ]; then
  divergence=""
  if ! divergence="$(git -C "$repo_root" rev-list --left-right --count "$remote_tip...$candidate_tip" 2>/dev/null)"; then
    result="verification_blocked"
    reason="Local-versus-remote divergence could not be calculated for '$branch'"
    human_action="Restore readable branch history for item #$issue and retry; do not infer base compatibility from tracking state."
    exit_code=3
    emit_output
    exit "$exit_code"
  fi
  behind="$(awk '{ print $1 }' <<< "$divergence")"
  ahead="$(awk '{ print $2 }' <<< "$divergence")"
  if [ "$ahead" -eq 0 ] && [ "$behind" -eq 0 ]; then
    tracking_state="equal"
  elif [ "$ahead" -gt 0 ] && [ "$behind" -eq 0 ]; then
    tracking_state="local_ahead"
  elif [ "$ahead" -eq 0 ] && [ "$behind" -gt 0 ]; then
    tracking_state="local_behind"
  else
    tracking_state="diverged"
  fi
elif [ "$local_candidate_status" -eq 0 ]; then
  tracking_state="remote_missing"
else
  tracking_state="remote_only"
  ahead="0"
  behind="0"
fi

set +e
git -C "$repo_root" merge-base --is-ancestor "$base_tip" "$candidate_tip" >/dev/null 2>&1
ancestry_status=$?
set -e

case "$ancestry_status" in
  0)
    result="compatible"
    reason="Approved base tip '$base_tip' is an ancestor of candidate tip '$candidate_tip'"
    human_action="Resume the canonical workflow for item #$issue on branch '$branch'; treat tracking divergence only as diagnostic evidence."
    exit_code=0
    ;;
  1)
    result="incompatible"
    reason="Approved base tip '$base_tip' is not an ancestor of candidate tip '$candidate_tip'"
    human_action="Inspect and preserve or manually remove branch '$branch' for item #$issue, then retry from approved base '$approved_base'; do not delete, reset, rebase, or force-push automatically."
    exit_code=1
    ;;
  *)
    result="verification_blocked"
    reason="Ancestry query failed for approved base '$base_ref' and candidate '$candidate_ref'"
    human_action="Restore readable Git history for item #$issue and retry, or request an explicit human recovery decision."
    exit_code=3
    ;;
esac

emit_output
exit "$exit_code"

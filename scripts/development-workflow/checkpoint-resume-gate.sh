#!/usr/bin/env bash
# Fail-closed entry gate for checkpointed worktree resumes.
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: checkpoint-resume-gate.sh --item <id> --expected-worktree <path> \
  --expected-branch <branch> --main-repo-root <path> \
  --checkpoint-state <pending|satisfied|waived> [--json]
USAGE
}

require_value() {
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
    printf 'ERROR: missing value for %s\n' "${1:-<unknown>}" >&2
    exit 2
  fi
}

item=""; expected_worktree=""; expected_branch=""; main_repo_root=""; checkpoint_state=""; json_output="false"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --item) [ -z "$item" ] || { printf 'ERROR: repeated option: --item\n' >&2; exit 2; }; require_value "$@"; item="$2"; shift 2 ;;
    --expected-worktree) [ -z "$expected_worktree" ] || { printf 'ERROR: repeated option: --expected-worktree\n' >&2; exit 2; }; require_value "$@"; expected_worktree="$2"; shift 2 ;;
    --expected-branch) [ -z "$expected_branch" ] || { printf 'ERROR: repeated option: --expected-branch\n' >&2; exit 2; }; require_value "$@"; expected_branch="$2"; shift 2 ;;
    --main-repo-root) [ -z "$main_repo_root" ] || { printf 'ERROR: repeated option: --main-repo-root\n' >&2; exit 2; }; require_value "$@"; main_repo_root="$2"; shift 2 ;;
    --checkpoint-state) [ -z "$checkpoint_state" ] || { printf 'ERROR: repeated option: --checkpoint-state\n' >&2; exit 2; }; require_value "$@"; checkpoint_state="$2"; shift 2 ;;
    --json) json_output="true"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$item" ] || [ -z "$expected_worktree" ] || [ -z "$expected_branch" ] || [ -z "$main_repo_root" ] || [ -z "$checkpoint_state" ]; then
  usage >&2; exit 2
fi
case "$checkpoint_state" in pending|satisfied|waived) ;; *) printf 'ERROR: invalid checkpoint state: %s\n' "$checkpoint_state" >&2; exit 2 ;; esac

script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
set +e
preflight_output="$(bash "$script_dir/worktree-resume-preflight.sh" --item "$item" --expected-worktree "$expected_worktree" --expected-branch "$expected_branch" --main-repo-root "$main_repo_root")"
preflight_status=$?
set -e

field() {
  printf '%s\n' "$preflight_output" | sed -n "s/^$1=//p" | tail -1
}

preflight_result="$(field RESULT)"
target_worktree="$(field TARGET_WORKTREE)"
observed_directory="$(field OBSERVED_DIRECTORY)"
observed_branch="$(field OBSERVED_BRANCH)"
preflight_reason="$(field REASON)"
human_action="$(field HUMAN_ACTION)"

if [ "$preflight_status" -ne 0 ] || [ "$preflight_result" != "continue" ]; then
  result="stop"
  isolation_result="stop"
  stop_condition="unclear_requirements"
  reason="worktree isolation verification failed: ${preflight_reason:-unknown reason}"
elif [ "$checkpoint_state" = "pending" ]; then
  result="checkpoint_pending"
  isolation_result="pass"
  stop_condition="checkpoint_pending"
  reason="human checkpoint remains pending"
  human_action="satisfy or waive the checkpoint before starting a fresh isolated resume"
else
  result="continue"
  isolation_result="pass"
  stop_condition=""
  reason="isolation and checkpoint state allow continuation"
  human_action="continue from current directory"
fi

printf 'RESULT=%s\n' "$result"
printf 'ISOLATION_RESULT=%s\n' "$isolation_result"
printf 'CHECKPOINT_STATE=%s\n' "$checkpoint_state"
printf 'STOP_CONDITION=%s\n' "$stop_condition"
printf 'ITEM=%s\n' "$item"
printf 'EXPECTED_BRANCH=%s\n' "$expected_branch"
printf 'EXPECTED_WORKTREE=%s\n' "$expected_worktree"
printf 'TARGET_WORKTREE=%s\n' "${target_worktree:-}"
printf 'MAIN_REPO_ROOT=%s\n' "$main_repo_root"
printf 'OBSERVED_DIRECTORY=%s\n' "${observed_directory:-}"
printf 'OBSERVED_BRANCH=%s\n' "${observed_branch:-}"
printf 'REASON=%s\n' "$reason"
printf 'HUMAN_ACTION=%s\n' "${human_action:-start a fresh runner with the complete isolation assignment before mutation}"
if [ "$json_output" = "true" ]; then
  python3 -c 'import json,sys; print(json.dumps(dict(result=sys.argv[1], isolationResult=sys.argv[2], checkpointState=sys.argv[3], stopCondition=sys.argv[4], item=sys.argv[5], expectedBranch=sys.argv[6], expectedWorktree=sys.argv[7], targetWorktree=sys.argv[8], mainRepoRoot=sys.argv[9], observedDirectory=sys.argv[10], observedBranch=sys.argv[11], reason=sys.argv[12], humanAction=sys.argv[13])))' "$result" "$isolation_result" "$checkpoint_state" "$stop_condition" "$item" "$expected_branch" "$expected_worktree" "${target_worktree:-}" "$main_repo_root" "${observed_directory:-}" "${observed_branch:-}" "$reason" "${human_action:-start a fresh runner with the complete isolation assignment before mutation}"
fi
[ "$result" = "continue" ]

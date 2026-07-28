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
isolation_result="$(printf '%s\n' "$preflight_output" | sed -n 's/^RESULT=//p' | tail -1)"
if [ "$preflight_status" -ne 0 ] || [ "$isolation_result" != "continue" ]; then
  result="stop"; stop_condition="unclear_requirements"; reason="worktree isolation verification failed"
elif [ "$checkpoint_state" = "pending" ]; then
  result="checkpoint_pending"; stop_condition="checkpoint_pending"; reason="human checkpoint remains pending"
else
  result="continue"; stop_condition=""; reason="isolation and checkpoint state allow continuation"
fi
printf '%s\n' "$preflight_output"
printf 'RESULT=%s\nISOLATION_RESULT=%s\nCHECKPOINT_STATE=%s\nSTOP_CONDITION=%s\nREASON=%s\n' "$result" "${isolation_result:-stop}" "$checkpoint_state" "$stop_condition" "$reason"
if [ "$json_output" = "true" ]; then
  python3 -c 'import json,sys; print(json.dumps(dict(result=sys.argv[1], isolationResult=sys.argv[2], checkpointState=sys.argv[3], stopCondition=sys.argv[4], reason=sys.argv[5])))' "$result" "${isolation_result:-stop}" "$checkpoint_state" "$stop_condition" "$reason"
fi
[ "$result" = "continue" ]

#!/usr/bin/env bash
# worktree-resume-preflight.sh
#
# Read-only preflight for checkpoint resumes. It proves that a resumed
# item-orchestrator is already inside the expected worktree. Resume context is
# fail-closed: the helper never re-enters a worktree from the main clone.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: worktree-resume-preflight.sh --item <id> --expected-branch <branch> \
  --expected-worktree <path> --main-repo-root <path> [options]

Options:
  --expected-worktree <path>  Expected worktree path
  --main-repo-root <path>     Main repository root
  --json                     Emit a JSON record after key=value lines
  --help                     Show this help
USAGE
}

require_value() {
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
    printf 'ERROR: missing value for %s\n' "${1:-<unknown>}" >&2
    usage >&2
    exit 2
  fi
}

item=""
expected_branch=""
expected_worktree=""
main_repo_root=""
json_output="false"
script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
cwd_guard="$script_dir/worktree-cwd-guard.sh"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --item)
      [ "$item" = "" ] || { printf 'ERROR: repeated option: --item\n' >&2; exit 2; }
      require_value "$@"
      item="${2:-}"
      shift 2
      ;;
    --expected-branch)
      [ "$expected_branch" = "" ] || { printf 'ERROR: repeated option: --expected-branch\n' >&2; exit 2; }
      require_value "$@"
      expected_branch="${2:-}"
      shift 2
      ;;
    --expected-worktree)
      [ "$expected_worktree" = "" ] || { printf 'ERROR: repeated option: --expected-worktree\n' >&2; exit 2; }
      require_value "$@"
      expected_worktree="${2:-}"
      shift 2
      ;;
    --main-repo-root)
      [ "$main_repo_root" = "" ] || { printf 'ERROR: repeated option: --main-repo-root\n' >&2; exit 2; }
      require_value "$@"
      main_repo_root="${2:-}"
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

if [ -z "$item" ] || [ -z "$expected_branch" ] || [ -z "$expected_worktree" ] || [ -z "$main_repo_root" ]; then
  usage >&2
  exit 2
fi

json_quote() {
  python3 -c 'import json, sys; print(json.dumps(sys.argv[1]))' "$1"
}

canon_path() {
  local path="$1"
  if [ -d "$path" ]; then
    (cd "$path" && pwd -P)
  else
    printf '%s\n' "$path"
  fi
}

path_contains() {
  local parent="$1" child="$2"
  case "$child" in
    "$parent"|"$parent"/*) return 0 ;;
    *) return 1 ;;
  esac
}

git_output_or_empty() {
  local output status
  set +e
  output="$(git "$@" 2>/dev/null)"
  status=$?
  set -e
  if [ "$status" -eq 0 ]; then
    printf '%s\n' "$output"
  fi
}

current_cwd="$(pwd -P 2>/dev/null || pwd)"
observed_branch="$(git_output_or_empty rev-parse --abbrev-ref HEAD)"

main_repo_root="$(canon_path "$main_repo_root")"

  worktree_output=""
  if ! worktree_output="$(git -C "$main_repo_root" worktree list --porcelain 2>/dev/null)"; then
    result="stop"
    action="none"
    target_worktree=""
    reason="git worktree list failed"
  else
    matches_file="$(mktemp)"
    trap 'rm -f "$matches_file"' EXIT

    awk -v expected_branch="$expected_branch" -v expected_worktree="$expected_worktree" '
      function flush_entry() {
        if (path == "") {
          return
        }
        branch_name = ""
        if (branch ~ /^refs\/heads\//) {
          branch_name = substr(branch, 12)
        }
        path_matches = (expected_worktree != "")
        branch_matches = (branch_name == expected_branch)
        if (path_matches || branch_matches) {
          printf "%s\034%s\034%s\n", path, branch_name, detached
        }
      }
      /^worktree / {
        flush_entry()
        path = substr($0, 10)
        branch = ""
        detached = "false"
        next
      }
      /^branch / {
        branch = substr($0, 8)
        next
      }
      /^detached/ {
        detached = "true"
        next
      }
      END {
        flush_entry()
      }
    ' <<EOF >"$matches_file"
$worktree_output
EOF

    expected_worktree_canon=""
    if [ -n "$expected_worktree" ]; then
      expected_worktree_canon="$(canon_path "$expected_worktree")"
      raw_matches_file="$(mktemp)"
      trap 'rm -f "$matches_file" "$raw_matches_file"' EXIT
      while IFS="$(printf '\034')" read -r path branch detached; do
        canon="$(canon_path "$path")"
        if [ "$canon" = "$expected_worktree_canon" ]; then
          printf '%s\034%s\034%s\n' "$canon" "$branch" "$detached" >>"$raw_matches_file"
        fi
      done <"$matches_file"
      mv "$raw_matches_file" "$matches_file"
    fi

    match_count="$(wc -l <"$matches_file" | tr -d ' ')"

    if [ "$match_count" -eq 0 ]; then
      result="stop"
      action="none"
      target_worktree="${expected_worktree_canon:-}"
      reason="no registered worktree matches expected branch or path"
    elif [ "$match_count" -gt 1 ]; then
      result="stop"
      action="none"
      target_worktree=""
      reason="multiple registered worktrees match expected branch or path"
    else
      IFS="$(printf '\034')" read -r target_worktree target_branch target_detached <"$matches_file"
      target_worktree="$(canon_path "$target_worktree")"

      if [ "$target_detached" = "true" ] || [ -z "$target_branch" ]; then
        result="stop"
        action="none"
        reason="matching worktree is detached or missing branch metadata"
      elif [ "$target_branch" != "$expected_branch" ]; then
        result="stop"
        action="none"
        reason="matching worktree is on a different branch"
      elif path_contains "$target_worktree" "$current_cwd"; then
        if (cd "$current_cwd" && bash "$cwd_guard" --check-cwd "$target_worktree" "$main_repo_root" >/dev/null 2>&1); then
          result="continue"
          action="none"
          reason="current directory is already inside expected worktree"
        else
          result="stop"
          action="none"
          reason="worktree CWD guard rejected current directory"
        fi
      elif path_contains "$main_repo_root" "$current_cwd"; then
        result="stop"
        action="none"
        reason="current directory is the main clone; start a fresh runner in the expected worktree"
      else
        result="stop"
        action="none"
        reason="current directory is neither expected worktree nor main clone"
      fi
    fi
  fi

human_action=""
case "${result:-stop}" in
  continue)
    human_action="continue from current directory"
    ;;
  *)
    human_action="start a fresh runner with the complete isolation assignment before mutation"
    ;;
esac

printf 'RESULT=%s\n' "${result:-stop}"
printf 'ACTION=%s\n' "${action:-none}"
printf 'ITEM=%s\n' "$item"
printf 'EXPECTED_BRANCH=%s\n' "$expected_branch"
printf 'EXPECTED_WORKTREE=%s\n' "${expected_worktree:-}"
printf 'TARGET_WORKTREE=%s\n' "${target_worktree:-}"
printf 'MAIN_REPO_ROOT=%s\n' "${main_repo_root:-}"
printf 'OBSERVED_DIRECTORY=%s\n' "$current_cwd"
printf 'OBSERVED_BRANCH=%s\n' "$observed_branch"
printf 'REASON=%s\n' "${reason:-}"
if [ "${result:-stop}" = "stop" ]; then
  printf 'STOP_CONDITION=unclear_requirements\n'
else
  printf 'STOP_CONDITION=\n'
fi
printf 'HUMAN_ACTION=%s\n' "$human_action"

if [ "$json_output" = "true" ]; then
  printf '{'
  printf '"result":%s,' "$(json_quote "${result:-stop}")"
  printf '"action":%s,' "$(json_quote "${action:-none}")"
  printf '"item":%s,' "$(json_quote "$item")"
  printf '"expectedBranch":%s,' "$(json_quote "$expected_branch")"
  printf '"expectedWorktree":%s,' "$(json_quote "${expected_worktree:-}")"
  printf '"targetWorktree":%s,' "$(json_quote "${target_worktree:-}")"
  printf '"mainRepoRoot":%s,' "$(json_quote "${main_repo_root:-}")"
  printf '"observedDirectory":%s,' "$(json_quote "$current_cwd")"
  printf '"observedBranch":%s,' "$(json_quote "$observed_branch")"
  printf '"reason":%s,' "$(json_quote "${reason:-}")"
  printf '"stopCondition":%s,' "$(json_quote "$([ "${result:-stop}" = "stop" ] && printf 'unclear_requirements')")"
  printf '"humanAction":%s' "$(json_quote "$human_action")"
  printf '}\n'
fi

case "${result:-stop}" in
  continue) exit 0 ;;
  *) exit 1 ;;
esac

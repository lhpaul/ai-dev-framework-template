#!/usr/bin/env bash
# worktree-cwd-guard.sh
#
# Runtime CWD guard for worktree isolation.
#
# PURPOSE
# -------
# Prevents agents running inside an isolated worktree from accidentally issuing
# git state-changing commands (switch, checkout, reset, restore) against the
# main repository root.  Protocol 91 (Step 3) defines this as a critical safety
# rule; violating it leaves the main repo on a feature branch and breaks all
# concurrent agents and the human operator.
#
# USAGE
# -----
# Source this file inside any worktree session before issuing git operations:
#
#   source scripts/development-workflow/worktree-cwd-guard.sh
#   worktree_cwd_guard_init "$WORKTREE_PATH" "$MAIN_REPO_ROOT"
#
# After init, the functions git_switch, git_checkout, git_reset, and git_restore
# wrap the underlying git commands with a CWD assertion.  Any attempt to run a
# state-changing git command from the main repo root while a worktree is active
# will print a GUARDRAIL warning and abort the command.
#
# NON-BLOCKING FALLTHROUGH
# ------------------------
# The guard emits a warning but does NOT abort the outer shell script by default.
# Each wrapper function returns exit code 1 on a CWD violation so the caller can
# detect and handle it, but the outer script continues unless it explicitly checks
# the return value.  This mirrors the advisory behavior documented in Protocol 91
# ("The hook is non-blocking — it warns but does not abort the command.")
#
# STANDALONE USAGE
# ----------------
# This script can also be executed directly (not sourced) for a one-shot CWD check:
#
#   bash scripts/development-workflow/worktree-cwd-guard.sh \
#        --check-cwd "$WORKTREE_PATH" "$MAIN_REPO_ROOT"
#
# Exit codes when run directly:
#   0  — CWD is inside the worktree (safe)
#   1  — CWD matches the main repo root (violation)
#   2  — Bad usage / missing arguments

# --- internal helpers -------------------------------------------------------

__wcg_worktree_path=""
__wcg_main_repo_root=""

# _wcg_assert_cwd_is_worktree: prints a GUARDRAIL warning and returns 1 if the
# current working directory is the main repo root; otherwise returns 0.
_wcg_assert_cwd_is_worktree() {
  local label="${1:-git command}"
  local real_cwd
  real_cwd="$(pwd -P 2>/dev/null || pwd)"

  if [ -z "$__wcg_worktree_path" ] || [ -z "$__wcg_main_repo_root" ]; then
    # Guard not initialised — skip check transparently.
    return 0
  fi

  # Resolve canonical paths for reliable comparison.
  local real_worktree real_main
  real_worktree="$(cd "$__wcg_worktree_path" 2>/dev/null && pwd -P || printf '%s' "$__wcg_worktree_path")"
  real_main="$(cd "$__wcg_main_repo_root" 2>/dev/null && pwd -P || printf '%s' "$__wcg_main_repo_root")"

  # If CWD is inside the worktree subtree, it is always safe — return early.
  # Must be checked before the main-repo check to handle the case where the
  # worktree lives under the main repo tree (e.g. .claude/worktrees/<id>/).
  case "$real_cwd" in
    "$real_worktree"/*|"$real_worktree")
      return 0
      ;;
  esac

  # If CWD is inside the main repo tree (root or any subdirectory), it is a
  # violation: git commands would operate on the main working tree rather than
  # the isolated worktree.
  case "$real_cwd" in
    "$real_main"/*|"$real_main")
      printf 'GUARDRAIL WARNING: %s was called from inside the main repository tree (%s).\n' "$label" "$real_cwd" >&2
      printf 'This is a protocol-91 worktree isolation violation. Use one of:\n' >&2
      printf '  cd %s && git %s ...\n' "$real_worktree" "${label#git }" >&2
      printf '  git -C %s %s ...\n' "$real_worktree" "${label#git }" >&2
      printf 'Command aborted to protect the main working tree.\n' >&2
      return 1
      ;;
  esac

  return 0
}

# --- public API -------------------------------------------------------------

# worktree_cwd_guard_init <worktree_path> <main_repo_root>
#
# Initialise the guard with the paths for the current batch item.  Must be
# called before any of the wrapper functions are used.
worktree_cwd_guard_init() {
  if [ $# -lt 2 ]; then
    printf 'Usage: worktree_cwd_guard_init <worktree_path> <main_repo_root>\n' >&2
    return 2
  fi
  __wcg_worktree_path="$1"
  __wcg_main_repo_root="$2"
}

# worktree_cwd_guard_status
#
# Print the current guard configuration to stdout.  Useful for debugging.
worktree_cwd_guard_status() {
  printf 'worktree-cwd-guard status:\n'
  printf '  worktree_path : %s\n' "${__wcg_worktree_path:-<not set>}"
  printf '  main_repo_root: %s\n' "${__wcg_main_repo_root:-<not set>}"
  local real_cwd
  real_cwd="$(pwd -P 2>/dev/null || pwd)"
  printf '  current_cwd   : %s\n' "$real_cwd"
  if _wcg_assert_cwd_is_worktree "status-check" 2>/dev/null; then
    printf '  verdict       : SAFE (CWD is not the main repo root)\n'
  else
    printf '  verdict       : VIOLATION (CWD is the main repo root)\n'
  fi
}

# git_switch <args>
#
# Guarded wrapper for `git switch`.  Aborts with a GUARDRAIL warning if CWD
# is the main repo root.
git_switch() {
  _wcg_assert_cwd_is_worktree "git switch" || return 1
  git switch "$@"
}

# git_checkout <args>
#
# Guarded wrapper for `git checkout` and `git checkout -b`.  Aborts with a
# GUARDRAIL warning if CWD is the main repo root.
git_checkout() {
  _wcg_assert_cwd_is_worktree "git checkout" || return 1
  git checkout "$@"
}

# git_reset <args>
#
# Guarded wrapper for `git reset`.  Aborts with a GUARDRAIL warning if CWD
# is the main repo root.
git_reset() {
  _wcg_assert_cwd_is_worktree "git reset" || return 1
  git reset "$@"
}

# git_restore <args>
#
# Guarded wrapper for `git restore`.  Aborts with a GUARDRAIL warning if CWD
# is the main repo root.
git_restore() {
  _wcg_assert_cwd_is_worktree "git restore" || return 1
  git restore "$@"
}

# --- standalone (non-sourced) entry point -----------------------------------

# When executed directly (not sourced), support a --check-cwd sub-command for
# one-shot CWD validation from shell scripts or CI steps.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    --check-cwd)
      if [ $# -lt 3 ]; then
        printf 'Usage: %s --check-cwd <worktree_path> <main_repo_root>\n' "$0" >&2
        exit 2
      fi
      worktree_cwd_guard_init "$2" "$3"
      if _wcg_assert_cwd_is_worktree "check-cwd"; then
        printf 'OK: CWD is not the main repo root.\n'
        exit 0
      else
        exit 1
      fi
      ;;
    --help|-h)
      printf 'worktree-cwd-guard.sh — runtime CWD guard for worktree isolation\n\n'
      printf 'Source usage (inside a worktree session):\n'
      printf '  source scripts/development-workflow/worktree-cwd-guard.sh\n'
      printf '  worktree_cwd_guard_init <worktree_path> <main_repo_root>\n\n'
      printf 'Standalone usage (one-shot check):\n'
      printf '  %s --check-cwd <worktree_path> <main_repo_root>\n' "$0"
      exit 0
      ;;
    *)
      printf 'worktree-cwd-guard.sh: unknown argument: %s\n' "${1:-}" >&2
      printf 'Run with --help for usage.\n' >&2
      exit 2
      ;;
  esac
fi

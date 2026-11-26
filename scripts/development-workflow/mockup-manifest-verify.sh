#!/usr/bin/env bash
# mockup-manifest-verify.sh — verify HTML Mockup Framework manifests (#2206).
#
# Spec: docs/specs/developments/20261126075749_2206-mockup-manifest-contract/
# Contract: "Manifest" in docs/workflow/development-workflow/mockup-framework.md
#
# Usage:
#   mockup-manifest-verify.sh manifest  <manifest-path> [--repo-root <dir>]
#   mockup-manifest-verify.sh tree      [--repo-root <dir>]
#   mockup-manifest-verify.sh inventory <manifest-path> [--repo-root <dir>]
#   mockup-manifest-verify.sh resolve   <manifest-path> --screen <id> [--state <id>] [--repo-root <dir>]
#
# Output is KEY=value lines on stdout. Exit codes:
#   0  a non-failing outcome (Conforms, Not opted in, No mockups found,
#      an inventory listed, Resolves)
#   1  a failing outcome (Does not conform, Invalid configuration,
#      Cannot check, Does not resolve)
#   2  a caller or environment error: usage, a --repo-root that is not a
#      directory, a missing python3, `tree` outside a Git repository without
#      --repo-root, or a failed design opt-in read. stderr only, empty stdout.
#
# The manifest is read as data and never executed. The script writes no file
# and uses no network; `tree` gates on workflow_design_opt_in (#2211) and runs
# Git only to find the default repository root. Bash 3.2 compatible.

set -euo pipefail

usage() {
  cat <<'EOF'
usage: mockup-manifest-verify.sh <subcommand> ...
  manifest  <manifest-path> [--repo-root <dir>]
  tree      [--repo-root <dir>]
  inventory <manifest-path> [--repo-root <dir>]
  resolve   <manifest-path> --screen <id> [--state <id>] [--repo-root <dir>]
EOF
}

die_usage() {
  printf 'mockup-manifest-verify: %s\n' "$1" >&2
  usage >&2
  exit 2
}

case "${BASH_SOURCE[0]}" in
  */*) script_dir="${BASH_SOURCE[0]%/*}" ;;
  *) script_dir="." ;;
esac
if ! script_dir="$(CDPATH='' cd -- "$script_dir" && pwd)"; then
  printf 'mockup-manifest-verify: cannot resolve the script folder\n' >&2
  exit 2
fi
py="$script_dir/mockup-manifest-verify.py"

[ "$#" -ge 1 ] || die_usage "missing subcommand"
sub="$1"
shift
case "$sub" in
  manifest | tree | inventory | resolve) ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die_usage "unknown subcommand: $sub" ;;
esac

# Validate --repo-root before anything runs; the module re-checks the rest.
repo_root=""
have_root=0
pending=""
for arg in "$@"; do
  if [ -n "$pending" ]; then
    if [ "$pending" = "--repo-root" ]; then
      repo_root="$arg"
      have_root=1
    fi
    pending=""
    continue
  fi
  case "$arg" in
    --repo-root | --screen | --state) pending="$arg" ;;
  esac
done
[ -z "$pending" ] || die_usage "$pending needs a value"
if [ "$have_root" = 1 ] && { [ -z "$repo_root" ] || [ ! -d "$repo_root" ]; }; then
  die_usage "--repo-root is not a directory"
fi

if ! command -v python3 >/dev/null 2>&1; then
  printf 'mockup-manifest-verify: python3 (3.9 or later) is required\n' >&2
  exit 2
fi

if [ "$sub" != "tree" ]; then
  exec python3 -I -B "$py" "$sub" "$@"
fi

# tree: only --repo-root is accepted.
if [ "$#" -ne 0 ] && { [ "$#" -ne 2 ] || [ "$1" != "--repo-root" ]; }; then
  die_usage "tree accepts only --repo-root <dir>"
fi
if [ "$have_root" = 0 ]; then
  if ! repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || [ -z "$repo_root" ]; then
    printf 'mockup-manifest-verify: tree needs --repo-root outside a Git repository\n' >&2
    exit 2
  fi
fi

# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$script_dir/workflow-lib.sh"
# Capture the whole opt-in outcome first: a helper that fails, even after
# printing valid-looking lines, stops here and the module never starts (P8).
if ! optin="$(workflow_design_opt_in "$repo_root")"; then
  printf 'mockup-manifest-verify: the design opt-in check failed\n' >&2
  exit 2
fi
status=0
printf '%s\n' "$optin" | python3 -I -B "$py" tree --repo-root "$repo_root" || status=$?
exit "$status"

#!/usr/bin/env bash
#
# Validate shared/local workflow repository-context configuration.
#
# Usage:
#   scripts/development-workflow/validate-workflow-config.sh [--repo <name>] [--require-local] [--repo-root <path>]

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

ARGS=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo|--repo-root)
      [ "$#" -ge 2 ] || { echo "ERROR: $1 requires a value" >&2; exit 2; }
      ARGS+=("$1" "$2")
      shift 2
      ;;
    --require-local)
      ARGS+=("$1")
      shift
      ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument '$1'" >&2
      exit 2
      ;;
  esac
done

if [ "${#ARGS[@]}" -gt 0 ]; then
  python3 "$SCRIPT_DIR/workflow-config-resolver.py" validate "${ARGS[@]}"
else
  python3 "$SCRIPT_DIR/workflow-config-resolver.py" validate
fi

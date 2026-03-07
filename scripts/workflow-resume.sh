#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
NEXT_ACTION_SCRIPT="$SCRIPT_DIR/workflow-next-action.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/workflow-resume.sh --branch <branch>
  ./scripts/workflow-resume.sh --pr <number>
  ./scripts/workflow-resume.sh --development <path>

Reports the next deterministic workflow action so an orchestrator can resume a partially completed run.
EOF
}

if [ "$#" -eq 0 ]; then
  usage >&2
  exit 64
fi

"$NEXT_ACTION_SCRIPT" "$@"

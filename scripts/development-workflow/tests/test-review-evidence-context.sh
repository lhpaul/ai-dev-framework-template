#!/usr/bin/env bash
# covers: scripts/development-workflow/review-evidence-context.py
# covers: scripts/development-workflow/workflow-lib.sh
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
python3 "$SCRIPT_DIR/test-review-evidence-context.py"

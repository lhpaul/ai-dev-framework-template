#!/usr/bin/env bash
# duration: 5
# covers: scripts/development-workflow/reviewer-loop-history.py
# covers: scripts/development-workflow/workflow-lib.sh
# covers: scripts/development-workflow/pr-review-loop.sh
# covers: scripts/development-workflow/tests/test-reviewer-loop-history.py
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
python3 "$SCRIPT_DIR/test-reviewer-loop-history.py"

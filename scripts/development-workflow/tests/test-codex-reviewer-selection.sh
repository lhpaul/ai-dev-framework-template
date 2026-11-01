#!/usr/bin/env bash
# covers: scripts/development-workflow/resolve-reviewer-availability.sh
# covers: scripts/development-workflow/workflow-config-resolver.py
# covers: scripts/development-workflow/reviewer_preflight_build_input.py
# covers: scripts/development-workflow/tests/test-codex-reviewer-selection.py
set -euo pipefail
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
exec python3 "$SCRIPT_DIR/test-codex-reviewer-selection.py"

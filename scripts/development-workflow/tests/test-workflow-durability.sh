#!/usr/bin/env bash
# covers: scripts/development-workflow/workflow-merge-budget.py
# covers: scripts/development-workflow/workflow-config-resolver.py
# covers: scripts/development-workflow/workflow-project-reader.py
# covers: scripts/development-workflow/tests/test_workflow_durability.py
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
python3 "$SCRIPT_DIR/test_workflow_durability.py"

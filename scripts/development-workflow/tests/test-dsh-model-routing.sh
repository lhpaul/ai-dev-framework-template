#!/usr/bin/env bash
# covers: scripts/development-workflow/workflow-config-resolver.py
# covers: scripts/development-workflow/tests/test_workflow_dsh_model_routing.py
# covers: scripts/development-workflow/validate-workflow-config.sh
# covers: docs/workflow/development-workflow/agent-model-config.md
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
python3 -B "$SCRIPT_DIR/test_workflow_dsh_model_routing.py"

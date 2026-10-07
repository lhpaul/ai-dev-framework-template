#!/usr/bin/env bash
# duration: 100
# covers: scripts/development-workflow/workflow-portfolio-scan.sh
# covers: scripts/development-workflow/workflow-portfolio-scan.py
# covers: scripts/development-workflow/workflow-project-reader.py
# covers: scripts/development-workflow/workflow-batch-plan.sh
# covers: scripts/development-workflow/workflow-next-action.sh
# covers: scripts/development-workflow/work-item-repository-routing.py
# covers: scripts/development-workflow/tests/test-workflow-portfolio-scan.py
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
exec python3 "$SCRIPT_DIR/test-workflow-portfolio-scan.py"

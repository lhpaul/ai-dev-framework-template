#!/usr/bin/env bash
# AC1/2 selected-private authority route inventory (#1993).
# covers: scripts/development-workflow/workflow-lib.sh
# covers: scripts/development-workflow/workflow-config-resolver.py
# covers: scripts/development-workflow/run-epic-risk-classifier.sh
# covers: scripts/development-workflow/run-epic-delegated-gate.sh
# covers: scripts/development-workflow/tests/test_private_source_authority.py
# covers: scripts/development-workflow/tests/test_private_source_consumers.py
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/test_private_source_authority.py"

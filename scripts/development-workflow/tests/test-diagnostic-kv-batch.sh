#!/usr/bin/env bash
# covers: scripts/development-workflow/workflow-config-resolver.py
# covers: scripts/development-workflow/workflow-lib.sh
# covers: scripts/development-workflow/apply-readiness-labels.sh
# covers: scripts/development-workflow/pr-ownership-guard.sh
# covers: scripts/development-workflow/tests/test_diagnostic_kv_batch.py
# covers: scripts/development-workflow/tests/test_runner_diagnostic_emitters.py
# covers: scripts/development-workflow/tests/test_private_source_consumers.py
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/test_diagnostic_kv_batch.py"

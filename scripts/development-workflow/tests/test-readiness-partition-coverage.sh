#!/usr/bin/env bash
# covers: scripts/development-workflow/tests/lib/readiness-*
# covers: scripts/development-workflow/tests/lib/consumer-readiness-*
# covers: scripts/development-workflow/tests/test-readiness-label-matrix-part-*.sh
# covers: scripts/development-workflow/tests/test-consumer-readiness-matrix-part-*.sh
# covers: scripts/development-workflow/tests/test_readiness_partition_coverage.py
# duration: 90
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
python3 "$SCRIPT_DIR/test_readiness_partition_coverage.py"

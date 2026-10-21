#!/usr/bin/env bash
# shellcheck shell=bash
# Independent consumer readiness matrix part 2/4; each suite retains 600s.
# covers: scripts/development-workflow/workflow-config-resolver.py
# covers: scripts/development-workflow/apply-readiness-labels.sh
# covers: scripts/development-workflow/workflow-lib.sh
# covers: scripts/development-workflow/tests/lib/readiness-*
# covers: scripts/development-workflow/tests/lib/readiness-matrix-record.py
# covers: scripts/development-workflow/tests/lib/consumer-readiness-*.sh
# covers: scripts/development-workflow/tests/test-apply-readiness-labels.sh
# duration: 150
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
READINESS_MATRIX_PART=2
# shellcheck source=scripts/development-workflow/tests/lib/consumer-readiness-matrix-driver.sh
source "$SCRIPT_DIR/lib/consumer-readiness-matrix-driver.sh"

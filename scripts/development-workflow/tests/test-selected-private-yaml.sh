#!/usr/bin/env bash
# covers: scripts/development-workflow/workflow-config-resolver.py
# covers: scripts/development-workflow/workflow-lib.sh
# covers: scripts/development-workflow/coderabbit-cli-reviewer.sh
# covers: scripts/development-workflow/tests/test_selected_private_yaml.py
# covers: scripts/development-workflow/tests/test_private_source_consumers.py
# covers: scripts/development-workflow/tests/fixtures/1993-selected-yaml-parity.json
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/test_selected_private_yaml.py"

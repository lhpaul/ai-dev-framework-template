#!/usr/bin/env bash
# covers: scripts/development-workflow/hub-worker-preflight.py
# covers: scripts/development-workflow/tests/test_hub_worker_preflight.py
# covers: .cursor/commands/run-item.md
# covers: .cursor/commands/run-items.md
# covers: .cursor/commands/run-epic.md
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
PYTHONDONTWRITEBYTECODE=1 python3 "$SCRIPT_DIR/test_hub_worker_preflight.py"

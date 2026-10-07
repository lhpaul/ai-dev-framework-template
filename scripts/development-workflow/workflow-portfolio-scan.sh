#!/usr/bin/env bash
# Canonical read-only scan coordinator. No live board enumeration or mutation.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
exec python3 "$SCRIPT_DIR/workflow-portfolio-scan.py" "$@"

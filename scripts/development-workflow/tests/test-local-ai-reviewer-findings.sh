#!/usr/bin/env bash
# Wrapper suite for local-ai-reviewer-findings.py.
# covers: scripts/development-workflow/local-ai-reviewer-findings.py
# covers: scripts/development-workflow/tests/test-local-ai-reviewer-findings.py

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
python3 "$SCRIPT_DIR/test-local-ai-reviewer-findings.py"

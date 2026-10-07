#!/usr/bin/env bash
# covers: scripts/development-workflow/sync-template-merge.py
# covers: scripts/development-workflow/tests/test_sync_template_merge.py
# covers: scripts/development-workflow/select-sync-manifest-entries.py
# covers: scripts/development-workflow/check-sync-manifest-coverage.py
# covers: .claude/commands/sync-template.md .cursor/commands/sync-template.md
# covers: .claude/skills/sync-template.md .codex/skills/workflow-sync-template/**
# covers: sync-manifest.yaml
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
python3 "$SCRIPT_DIR/test_sync_template_merge.py"

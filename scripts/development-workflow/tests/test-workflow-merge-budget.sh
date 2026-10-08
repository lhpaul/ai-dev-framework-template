#!/usr/bin/env bash
# covers: scripts/development-workflow/workflow-merge-budget.py
# covers: scripts/development-workflow/workflow-lib.sh
# covers: scripts/development-workflow/run-epic-risk-classifier.sh
# covers: scripts/development-workflow/run-epic-delegated-gate.sh
# covers: scripts/development-workflow/run-epic-audit-trail.sh
# covers: scripts/development-workflow/batch-merge.sh
# covers: scripts/development-workflow/post-merge-cleanup.sh
# covers: scripts/development-workflow/tests/test_workflow_merge_budget.py
# covers: scripts/development-workflow/tests/fixtures/workflow-merge-budget/**
# covers: .ai-dev-workflow.yaml
# covers: sync-manifest.yaml
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
python3 "$SCRIPT_DIR/test_workflow_merge_budget.py"

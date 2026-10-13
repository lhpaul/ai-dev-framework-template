#!/usr/bin/env bash
# covers: scripts/development-workflow/workflow-merge-budget.py
# covers: scripts/development-workflow/workflow-lib.sh
# covers: scripts/development-workflow/run-epic-risk-classifier.sh
# covers: scripts/development-workflow/run-epic-delegated-gate.sh
# covers: scripts/development-workflow/run-epic-audit-trail.sh
# covers: scripts/development-workflow/batch-merge.sh
# covers: scripts/development-workflow/post-merge-cleanup.sh
# covers: scripts/development-workflow/prepare-release-post-merge-cleanup.sh
# covers: scripts/development-workflow/tests/test_workflow_merge_budget.py
# covers: scripts/development-workflow/tests/test-workflow-merge-budget*.sh
# covers: scripts/development-workflow/tests/lib/merge-budget-runner.py
# covers: scripts/development-workflow/tests/fixtures/workflow-merge-budget/**
# covers: .ai-dev-workflow.yaml
# covers: sync-manifest.yaml
# duration: 250
# Eight independently selected CI suites share one exhaustive, disjoint enumeration.
# For a serial full run/shared evidence: python3 scripts/development-workflow/tests/lib/merge-budget-runner.py --all
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/lib/merge-budget-runner.py" --partition 3

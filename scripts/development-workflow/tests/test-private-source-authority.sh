#!/usr/bin/env bash
# AC1/2 selected-private authority route inventory (#1993).
# covers: scripts/development-workflow/workflow-lib.sh
# covers: scripts/development-workflow/workflow-config-resolver.py
# covers: scripts/development-workflow/run-epic-risk-classifier.sh
# covers: scripts/development-workflow/run-epic-delegated-gate.sh
# covers: scripts/development-workflow/coderabbit-cli-reviewer.sh
# covers: scripts/development-workflow/pr-ci-loop.sh
# covers: scripts/development-workflow/pr-review-loop.sh
# covers: scripts/development-workflow/item-completion-self-check.sh
# covers: scripts/development-workflow/apply-readiness-labels.sh
# covers: scripts/development-workflow/reviewer-preflight.sh
# covers: scripts/development-workflow/resolve-reviewer-availability.sh
# covers: scripts/development-workflow/github-app-token.sh
# covers: scripts/development-workflow/open-product-pr.sh
# covers: scripts/development-workflow/post-merge-cleanup.sh
# covers: scripts/development-workflow/discover-workflow-state.sh
# covers: scripts/development-workflow/workflow-next-action.sh
# covers: scripts/development-workflow/workflow-batch-plan.sh
# covers: scripts/development-workflow/workflow-batch-lanes.sh
# covers: scripts/development-workflow/tests/test_private_source_authority.py
# covers: scripts/development-workflow/tests/test_private_source_consumers.py
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/test_private_source_authority.py"

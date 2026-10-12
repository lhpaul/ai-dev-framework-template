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
# covers: scripts/development-workflow/tests/test-workflow-merge-budget.sh
# covers: scripts/development-workflow/tests/fixtures/workflow-merge-budget/**
# covers: .ai-dev-workflow.yaml
# covers: sync-manifest.yaml
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "${WORKFLOW_MERGE_BUDGET_TEST_EVIDENCE_DIR:-}" ]; then
  # Preserve the optional caller-owned aggregate evidence writer's serial contract.
  python3 "$SCRIPT_DIR/test_workflow_merge_budget.py"
else
  # Every case owns its temporary Git/provider resources. Run the complete
  # enumeration in two isolated processes within the unchanged CI suite deadline.
  python3 - "$SCRIPT_DIR/test_workflow_merge_budget.py" <<'PY'
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
path = Path(sys.argv[1])
spec = importlib.util.spec_from_file_location('budget_tests', path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def names(suite):
    for test in suite:
        if isinstance(test, unittest.TestSuite):
            yield from names(test)
        else:
            yield test.id().split('.', 1)[1]

tests = list(names(unittest.defaultTestLoader.loadTestsFromModule(module)))
groups = [tests[::2], tests[1::2]]
assert tests and len(tests) == len(set(tests))
assert sorted(test for group in groups for test in group) == sorted(tests)
failed = False
with tempfile.TemporaryDirectory(prefix='merge-budget-workers-') as directory:
    workers = []
    try:
        for index, group in enumerate(groups):
            if not group:
                continue
            log = Path(directory) / str(index)
            with log.open('wb') as stream:
                child = subprocess.Popen([sys.executable, str(path), *group], stdout=stream, stderr=subprocess.STDOUT)
            workers.append((child, log))
    finally:
        # Join every started worker even if a later launch or one test fails.
        for child, log in workers:
            failed = child.wait() != 0 or failed
            sys.stdout.buffer.write(log.read_bytes())
            sys.stdout.flush()
print('TEST_COUNT=' + str(len(tests)))
print('WORKER_COUNT=' + str(len(workers)))
print('RESULT=' + ('failed' if failed else 'pass'))
sys.exit(1 if failed else 0)
PY
fi

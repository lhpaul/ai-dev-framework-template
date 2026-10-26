#!/usr/bin/env bash
# covers: .github/workflows/update-tracker-on-merge.yml

set -euo pipefail

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"

python3 - "$ROOT_DIR" <<'PY'
import pathlib
import re
import sys
import tempfile

root = pathlib.Path(sys.argv[1])
checker = "scripts/development-workflow/check-tracker-merge-mapping.sh"


def verify_reference(workflow, repo):
    messages = re.findall(
        r'^\s*echo "These mappings are verified by ([^"]+)"\s*$',
        workflow,
        re.MULTILINE,
    )
    if len(messages) != 1:
        raise AssertionError("expected exactly one mapping verification reference")
    if not (repo / messages[0]).is_file():
        raise AssertionError("mapping verification reference does not name a file")


def verify_workflow(repo):
    workflow = repo / ".github/workflows/update-tracker-on-merge.yml"
    # Downstream repositories may use another tracker and omit this workflow.
    if not workflow.exists():
        return False
    verify_reference(workflow.read_text(), repo)
    return True


# Synthetic repository only: no workflow execution, credentials or tracker APIs.
# Spaces and glob characters in the root also exercise path handling.
with tempfile.TemporaryDirectory(prefix="tracker reference [synthetic] ") as tmp:
    synthetic = pathlib.Path(tmp)
    target = synthetic / checker
    target.parent.mkdir(parents=True)
    target.touch()
    correct = f'echo "These mappings are verified by {checker}"\n'
    verify_reference(correct, synthetic)
    assert verify_workflow(synthetic) is False
    workflow = synthetic / ".github/workflows/update-tracker-on-merge.yml"
    workflow.parent.mkdir(parents=True)
    workflow.write_text(correct)
    assert verify_workflow(synthetic) is True
    for broken in (
        f'echo "These mappings are verified by {checker}."\n',
        'echo "These mappings are verified by missing.sh"\n',
        "",
        " \t\n",
        correct + correct,
    ):
        try:
            workflow.write_text(broken)
            verify_workflow(synthetic)
        except AssertionError:
            pass
        else:
            raise AssertionError("invalid synthetic reference was accepted")

if not verify_workflow(root):
    print("tracker mapping workflow absent; repository reference check skipped")
print("tracker mapping reference tests passed (including planted trailing period)")
PY

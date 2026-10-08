#!/usr/bin/env bash
# covers: scripts/development-workflow/workflow-config-resolver.py
# covers: scripts/development-workflow/tests/test_workflow_dsh_model_routing.py
# covers: scripts/development-workflow/validate-workflow-config.sh
# covers: docs/workflow/development-workflow/agent-model-config.md
# covers: docs/workflow/development-workflow/integrations/dsh.md
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
# covers: .ai-dev-workflow.yaml .ai-dev-workflow.local.example.yaml
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
python3 -B "$SCRIPT_DIR/test_workflow_dsh_model_routing.py"
DOC_ROOT="${DSH_ROUTING_DOC_ROOT:-$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)}"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/../workflow-lib.sh"
TEMPLATE_MODE="$(workflow_template_is_template "$DOC_ROOT/.ai-dev-workflow.yaml")"
python3 -B - "$DOC_ROOT" "$TEMPLATE_MODE" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
contracts = {
    "docs/workflow/development-workflow/integrations/dsh.md": [
        "Resolve, pass, and record", "selection-disabled", "allowlist-denied",
        "SOURCE_FILE", "agent-default-model", "unique_by([.provider, .model])",
        "modelSelectionSettings: true", "fresh top-level session",
        "YAML anchors, aliases and merge keys are unsupported"],
    "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md": [
        "Resolve, pass, and record", "selection-disabled", "allowlist-denied",
        "SOURCE/SOURCE_FILE", "frozen", "post-dispatch failure",
        "YAML anchors, aliases and merge keys are unsupported"],
    "docs/workflow/development-workflow/agent-model-config.md": [
        "models.dsh.tiers", "models.dsh.roles", "actual dispatch", "headless default",
        "YAML anchors, aliases and merge keys are unsupported"],
}
for path, required in contracts.items():
    text = (root / path).read_text()
    for fragment in required:
        if fragment not in text:
            raise SystemExit(f"FAIL: {root / path}: missing dispatch contract fragment {fragment!r}")
for path in ((".ai-dev-workflow.yaml", ".ai-dev-workflow.local.example.yaml")
             if sys.argv[2] == "true" else ()):
    lines = (root / path).read_text().splitlines()
    if not any(line == "# models:" for line in lines):
        raise SystemExit(f"FAIL: {path}: missing commented example")
    if any(line.startswith("models:") for line in lines):
        raise SystemExit(f"FAIL: {path}: routing example must remain inactive")
print("PASS: DSH dispatch contract mirrors, headless boundary and template-owned examples")
PY

#!/usr/bin/env bash
# covers: docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
# covers: docs/workflow/development-workflow/protocols/95-run-epic-protocol.md
# covers: docs/workflow/development-workflow/guardrails.md
# covers: docs/workflow/development-workflow/guardrails-enforcement.md
# covers: docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md
# The receiver is a written agent instruction, not an executable router. These
# checks guard its behavioral obligations and a planted missing instruction;
# they do not simulate actual harness permissions or prove an agent obeys them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
python3 - "$ROOT" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
base = root / 'docs/workflow/development-workflow'
item = (base / 'protocols/91-orchestrate-work-protocol.md').read_text()
portfolio = (base / 'protocols/90-batch-orchestrate-work-protocol.md').read_text()
epic = (base / 'protocols/95-run-epic-protocol.md').read_text()

def receiver_gaps(text):
    start = text.index('### Stage-role denial report and receiver contract')
    end = text.index('**Permission-denial early exit', start)
    contract = text[start:end]
    expected = [
        'STAGE_ROLE_TOOL_OR_PATH_DENIED:', 'stage_role_tool_or_path_denied',
        'inspects every returned role report before subsequent mutation',
        'Do not substitute a different tool, identity, path, inline work or review',
        'missing_required_secret_or_permission', 'unclear_requirements',
        'generic tool failure', 'uncertain effects', 'live-state reconciliation',
        'fresh bounded run', 'same role resumes', 'never an automatic retry loop',
        'failed or incomplete review gate', 'not an approval, availability fallback',
        'not claim durable recording', 'without secrets',
    ]
    return [part for part in expected if part not in contract]

assert not receiver_gaps(item), receiver_gaps(item)
assert receiver_gaps(item.replace('inspects every returned role report before subsequent mutation', 'ignores role reports'))
assert 'never run the Work Item Runner inline fallback for that stage denial' in portfolio
assert 'hold all selected dependents' in portfolio
assert 'hold selected dependents' in epic and 'incomplete PR' in epic
for path in [root / '.ai-dev-workflow.yaml', base / 'README.md', base / 'guardrails.md', base / 'guardrails-enforcement.md']:
    assert 'stage_role_tool_or_path_denied' in path.read_text(), path
for path in [base / 'protocols/90-batch-orchestrate-work-protocol.md', base / 'protocols/91-orchestrate-work-protocol.md', base / 'protocols/95-run-epic-protocol.md', base / 'guardrails-enforcement.md', base / 'integrations/cursor-dispatch-profiles.md']:
    text = path.read_text()
    assert 'no recovery path of any kind' not in text, path
    assert 'no mechanism today recovers a denied stage role' not in text, path
# Validate concrete synthetic handoff records against the written contract.
# This checks report invariants; orchestration itself remains agent-driven.
records = [
    {'case': 'implementation', 'stops': ['stage_role_tool_or_path_denied'], 'state': 'blocked', 'owner': 'developer'},
    {'case': 'spec', 'stops': ['stage_role_tool_or_path_denied'], 'state': 'blocked', 'owner': 'spec-writer'},
    {'case': 'plan', 'stops': ['stage_role_tool_or_path_denied'], 'state': 'blocked', 'owner': 'plan-writer'},
    {'case': 'review', 'stops': ['stage_role_tool_or_path_denied'], 'state': 'blocked', 'owner': 'reviewer', 'review': 'failed'},
    {'case': 'mixed', 'stops': ['stage_role_tool_or_path_denied', 'missing_required_secret_or_permission'], 'state': 'blocked', 'owner': 'developer'},
    {'case': 'unknown', 'stops': ['unclear_requirements'], 'state': 'blocked', 'owner': 'developer'},
    {'case': 'unreachable', 'stops': ['dispatch_handoff_unavailable'], 'state': 'blocked', 'owner': 'developer'},
]
for mode in ('manual', 'supervised', 'autonomous'):
    for record in records:
        assert record['state'] == 'blocked' and record['owner'], (mode, record)
        if 'stage_role_tool_or_path_denied' in record['stops']:
            assert record.get('review', 'failed') != 'approved'
            assert 'needs-fixes' not in record['stops']
assert 'independently established causes are all reported' in item.lower()
assert 'changed context starts a fresh bounded run' in item
assert 'another denial stops again' in item
assert 'generic tool failure with no evidence of refusal retains its normal error contract' in item
print('PASS: stage-role denial contract, boundaries and planted violation')
PY

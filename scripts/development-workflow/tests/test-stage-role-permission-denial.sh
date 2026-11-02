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
# A deliberately small, isolated handoff model exercises inputs and reports
# against the written receiver contract. This is not the production agent.
def receive(event, *, plant_inline=False):
    if event['cause'] == 'generic':
        return {'result': 'existing_error'}
    if event['cause'] == 'unreachable':
        return {'result': 'dispatch_handoff_unavailable'}
    stops = []
    if event['cause'] in ('tool', 'mixed'):
        stops.append('stage_role_tool_or_path_denied')
    if event['cause'] in ('credential', 'mixed'):
        stops.append('missing_required_secret_or_permission')
    if event['cause'] == 'unknown':
        stops.append('unclear_requirements')
    if event.get('readonly'):
        stops.append('dispatch_handoff_unavailable')
    facts = {key: event[key] for key in ('item', 'stage', 'role', 'action', 'state')}
    return {
        'result': 'blocked', 'stops': stops, 'facts': facts,
        'operator_action': 'correct access and retry the same role',
        'recorded': bool(event.get('record_writable')),
        'handoff': not event.get('record_writable'),
        'review': 'failed' if event['stage'] == 'review' else None,
        'pr': event.get('pr'), 'held': list(event.get('dependents', [])),
        'inline': plant_inline,
        'needs_fixes': False,
    }

def recovery(event, *, corrected, reconciled, context_changed, denied_again=False):
    if not corrected or (event['state'] == 'uncertain' and not reconciled) or denied_again:
        return {'result': 'blocked', 'role': event['role']}
    return {'result': 'resume', 'role': event['role'],
            'fresh_run': context_changed, 'declare_profile': context_changed}

for mode in ('manual', 'supervised', 'autonomous'):
    for stage, role in [('implementation', 'developer'), ('spec', 'spec-writer'),
                        ('plan', 'plan-writer'), ('review', 'reviewer')]:
        request = {'item': 1746, 'stage': stage, 'role': role, 'cause': 'tool',
                   'action': 'Edit:example.md', 'state': 'uncertain',
                   'record_writable': True, 'pr': 100, 'dependents': [101],
                   'secret': 'private-sentinel', 'mode': mode}
        actual = receive(request)
        assert actual['result'] == 'blocked' and actual['stops'] == ['stage_role_tool_or_path_denied']
        assert actual['facts'] == {k: request[k] for k in ('item', 'stage', 'role', 'action', 'state')}
        assert actual['recorded'] and not actual['handoff'] and actual['pr'] == 100
        assert actual['held'] == [101] and not actual['inline'] and not actual['needs_fixes']
        assert 'private-sentinel' not in repr(actual)
        if stage == 'review':
            assert actual['review'] == 'failed'
        assert recovery(request, corrected=True, reconciled=False, context_changed=False)['result'] == 'blocked'
        assert recovery(request, corrected=True, reconciled=True, context_changed=False) == {
            'result': 'resume', 'role': role, 'fresh_run': False, 'declare_profile': False}
        assert recovery(request, corrected=True, reconciled=True, context_changed=True)['declare_profile']
        assert recovery(request, corrected=True, reconciled=True, context_changed=True, denied_again=True)['result'] == 'blocked'
        unrecorded = receive(dict(request, record_writable=False))
        assert not unrecorded['recorded'] and unrecorded['handoff'] and unrecorded['facts'] == actual['facts']
        # Planted inline routing must violate the same no-bypass assertion.
        assert receive(request, plant_inline=True)['inline'] != actual['inline']

request = {'item': 1746, 'stage': 'review', 'role': 'cli-reviewer', 'action': 'Bash', 'state': 'known'}
assert receive(dict(request, cause='credential'))['stops'] == ['missing_required_secret_or_permission']
assert receive(dict(request, cause='mixed', readonly=True))['stops'] == [
    'stage_role_tool_or_path_denied', 'missing_required_secret_or_permission', 'dispatch_handoff_unavailable']
assert receive(dict(request, cause='unknown'))['stops'] == ['unclear_requirements']
assert receive(dict(request, cause='unreachable'))['result'] == 'dispatch_handoff_unavailable'
assert receive(dict(request, cause='generic'))['result'] == 'existing_error'
assert 'independently established causes are all reported' in item.lower()
assert 'changed context starts a fresh bounded run' in item
assert 'another denial stops again' in item
assert 'generic tool failure with no evidence of refusal retains its normal error contract' in item
print('PASS: stage-role denial contract, boundaries and planted violation')
PY

#!/usr/bin/env bash
# covers: scripts/development-workflow/stage-role-denial-decision.py
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
import json
import subprocess
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
# Exercise the executable receiver decision with fabricated reports; its input
# is classified facts, not arbitrary third-party text or a real denial.
helper = root / 'scripts/development-workflow/stage-role-denial-decision.py'
def receive(event, script=helper):
    result = subprocess.run([sys.executable, str(script)], input=json.dumps(event),
                            text=True, capture_output=True, check=True)
    return json.loads(result.stdout)

for mode in ('manual', 'assisted', 'delegated', 'autonomous'):
    for stage in ('implementation', 'spec', 'plan', 'review'):
        event = {'cause': 'tool_path', 'mode': mode, 'review': stage == 'review',
                 'record_available': True, 'uncertain': True}
        actual = receive(event)
        assert actual['result'] == 'blocked' and actual['stops'] == ['stage_role_tool_or_path_denied'], (mode, stage)
        assert actual['report_destination'] == 'existing_record' and actual['hold_dependents']
        assert not actual['inline_fallback'] and not actual['needs_fixes_for_denial']
        if stage == 'review':
            assert actual['review_gate'] == 'fresh_review_required'
        assert receive(dict(event, corrected=True))['result'] == 'blocked'
        assert receive({'cause': 'tool_path', 'corrected': True})['result'] == 'blocked'
        same = receive(dict(event, corrected=True, reconciled=True))
        assert same['result'] == 'resume_same_role' and not same['fresh_run_and_profile']
        fresh = receive(dict(event, corrected=True, reconciled=True, context_changed=True))
        assert fresh['result'] == 'resume_same_role' and fresh['fresh_run_and_profile']
        assert receive(dict(event, corrected=True, reconciled=True, denied_again=True))['result'] == 'blocked'
        assert receive(dict(event, record_available=False))['report_destination'] == 'operator_handoff'
assert receive({'cause': 'credential'})['stops'] == ['missing_required_secret_or_permission']
mixed = receive({'cause': 'mixed', 'review': True, 'readonly_stop': True, 'handoff_stop': True})
assert mixed['stops'] == ['stage_role_tool_or_path_denied', 'missing_required_secret_or_permission', 'dispatch_handoff_unavailable']
assert mixed['readonly_blocked'] and mixed['hold_dependents'] and mixed['review_gate'] == 'fresh_review_required'
assert receive({'cause': 'unknown'})['stops'] == ['unclear_requirements']
assert receive({'cause': 'unreachable'})['stops'] == ['dispatch_handoff_unavailable']
assert receive({'cause': 'generic'}) == {'result': 'existing_error'}
generic = receive({'cause': 'generic', 'handoff_stop': True, 'readonly_stop': True})
assert generic['result'] == 'blocked' and generic['stops'] == ['dispatch_handoff_unavailable'] and generic['readonly_blocked']
invalid = subprocess.run([sys.executable, str(helper)], input='{"cause":"private-sentinel"}', text=True, capture_output=True)
assert invalid.returncode == 2 and 'private-sentinel' not in invalid.stdout + invalid.stderr

# Drive concrete synthetic receiver and supervisor handoffs through the helper.
# A local file is a disposable record double; it is not a real GitHub write.
import tempfile
handoff = {'marker': 'STAGE_ROLE_TOOL_OR_PATH_DENIED', 'item': 1746, 'stage': 'review',
           'role': 'cli-reviewer', 'action': 'Bash token=private-sentinel', 'state': 'uncertain',
           'pr': 2102, 'dependencies': {'1750': [1746], '1751': [], '1752': [1750]}}
event = {'cause': 'tool_path', 'review': True, 'uncertain': True, 'handoff': handoff}
with tempfile.TemporaryDirectory() as tmp:
    record = Path(tmp) / 'item-record.json'
    for writable in (True, False):
        actual = receive(dict(event, record_available=writable))
        assert actual['handoff']['item'] == 1746 and actual['handoff']['pr'] == 2102
        assert actual['handoff']['role'] == 'cli-reviewer' and actual['handoff']['unblock_action']
        assert 'private-sentinel' not in repr(actual)
        assert actual['held_dependents'] == ['1750', '1752'] and not actual['durable_recorded']
        assert actual['review_gate'] == 'fresh_review_required' and not actual['inline_fallback']
        if actual['report_destination'] == 'existing_record':
            # Simulated permitted write and independent read-back.
            assert writable
            record.write_text(json.dumps(actual['handoff']))
            assert json.loads(record.read_text()) == actual['handoff']
            assert json.loads(record.read_text())['pr'] == 2102
            record.unlink()
        else:
            # No write is available: the same details go to the operator and
            # durability must not be claimed.
            assert not writable and actual['report_destination'] == 'operator_handoff'
            assert not actual['durable_recorded'] and not record.exists()
        # Supervisor consumes the actual decision, holds selected dependencies,
        # permits independent work and never invokes runner inline fallback.
        candidates = {'1750', '1751', '1752'}
        held = set(actual['held_dependents'])
        scheduled = candidates - held
        assert held == {'1750', '1752'} and scheduled == {'1751'}
        assert not actual['inline_fallback']

# Hub-only helper remains reachable from a separate product checkout.
with tempfile.TemporaryDirectory() as product:
    assert not (Path(product) / 'scripts/development-workflow/stage-role-denial-decision.py').exists()
    product_run = subprocess.run([sys.executable, str(helper)], cwd=product,
                                 input=json.dumps(event), text=True, capture_output=True, check=True)
    assert json.loads(product_run.stdout)['held_dependents'] == ['1750', '1752']
linear = dict(handoff, item='ENG-123', dependencies={'ENG-124': ['ENG-123'], 'ENG-125': []})
linear_result = receive({'cause': 'tool_path', 'handoff': linear})
assert linear_result['handoff']['item'] == 'ENG-123' and linear_result['held_dependents'] == ['ENG-124']

# Plant a boundary violation in the actual decision helper. The same fabricated
# Work Item Runner report must be rejected by the original stage receiver but
# accepted by the mutated receiver; restore and observe rejection again.
wrong_boundary = dict(handoff, marker='SUBAGENT_PERMISSION_DENIAL')
boundary_event = dict(event, handoff=wrong_boundary)
def boundary_exit(script):
    return subprocess.run([sys.executable, str(script)], input=json.dumps(boundary_event),
                          text=True, capture_output=True).returncode
assert boundary_exit(helper) == 2
with tempfile.TemporaryDirectory() as tmp:
    planted = Path(tmp) / 'decision.py'
    original = helper.read_text()
    needle = "if handoff['marker'] != 'STAGE_ROLE_TOOL_OR_PATH_DENIED':"
    assert needle in original
    planted.write_text(original.replace(needle, "if False:", 1))
    (Path(tmp) / 'workflow-config-resolver.py').write_bytes(
        (helper.parent / 'workflow-config-resolver.py').read_bytes())
    assert boundary_exit(planted) == 0
    print('PLANT: runner denial incorrectly accepted at stage boundary')
    assert boundary_exit(helper) == 2
    print('REPAIR: runner denial rejected at stage boundary')
print('PASS: stage-role denial contract, boundaries and planted violation')
PY

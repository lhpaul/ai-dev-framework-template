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

for mode in ('manual', 'supervised', 'autonomous'):
    for stage in ('implementation', 'spec', 'plan', 'review'):
        event = {'cause': 'tool_path', 'review': stage == 'review',
                 'record_available': True, 'uncertain': True}
        actual = receive(event)
        assert actual['result'] == 'blocked' and actual['stops'] == ['stage_role_tool_or_path_denied'], (mode, stage)
        assert actual['report_destination'] == 'existing_record' and actual['hold_dependents']
        assert not actual['inline_fallback'] and not actual['needs_fixes_for_denial']
        if stage == 'review':
            assert actual['review_gate'] == 'fresh_review_required'
        assert receive(dict(event, corrected=True))['result'] == 'blocked'
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
assert receive({'cause': 'generic'})['result'] == 'existing_error'
invalid = subprocess.run([sys.executable, str(helper)], input='{"cause":"private-sentinel"}', text=True, capture_output=True)
assert invalid.returncode == 2 and 'private-sentinel' not in invalid.stdout + invalid.stderr

# Plant a real routing violation in an isolated copy of the decision helper;
# the same no-inline check must fail for the plant and pass for the original.
import tempfile
with tempfile.TemporaryDirectory() as tmp:
    planted = Path(tmp) / 'decision.py'
    original = helper.read_text()
    needle = "'inline_fallback': False"
    assert needle in original
    planted.write_text(original.replace(needle, "'inline_fallback': True", 1))
    def assert_no_inline(script):
        return not receive({'cause': 'tool_path'}, script)['inline_fallback']
    assert not assert_no_inline(planted)
    assert assert_no_inline(helper)
    print('PLANT: inline_fallback=True rejected; original accepted')
print('PASS: stage-role denial contract, boundaries and planted violation')
PY

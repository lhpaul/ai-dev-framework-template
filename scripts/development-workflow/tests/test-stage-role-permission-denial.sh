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
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$ROOT/scripts/development-workflow/workflow-lib.sh"
IS_TEMPLATE="$(workflow_template_is_template "$ROOT/.ai-dev-workflow.yaml")"
python3 - "$ROOT" "$IS_TEMPLATE" <<'PY'
from pathlib import Path
import sys
import json
import subprocess
import os
import shutil
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
        'receiver must write and independently verify an existing work-item or PR record before claiming durability',
    ]
    return [part for part in expected if part not in contract]

assert not receiver_gaps(item), receiver_gaps(item)
assert receiver_gaps(item.replace('inspects every returned role report before subsequent mutation', 'ignores role reports'))
assert receiver_gaps(item.replace('receiver must write and independently verify an existing work-item or PR record before claiming durability', 'receiver assumes durability'))
assert 'never run the Work Item Runner inline fallback for that stage denial' in portfolio
assert 'hold all selected dependents' in portfolio
assert 'hold selected dependents' in epic and 'incomplete PR' in epic
for path in [base / 'README.md', base / 'guardrails.md', base / 'guardrails-enforcement.md']:
    assert 'stage_role_tool_or_path_denied' in path.read_text(), path
# The configuration is project-owned. Consumers without a declared list are
# valid; the baseline list assertion belongs only to the template itself.
def template_config_ok(text, is_template):
    return not is_template or 'stage_role_tool_or_path_denied' in text
assert template_config_ok((root / '.ai-dev-workflow.yaml').read_text(), sys.argv[2] == 'true')
assert template_config_ok('template:\n  is_template: false\n', False)
assert not template_config_ok('template:\n  is_template: true\n', True)
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
        assert actual['handoff']['stage'] == handoff['stage']
        assert actual['handoff']['state'] == handoff['state']
        assert actual['handoff']['action'] == 'Bash token=[REDACTED]'
        assert actual['handoff']['stops'] == ['stage_role_tool_or_path_denied'] and actual['handoff']['remedies']
        assert 'private-sentinel' not in repr(actual)
        assert actual['held_dependents'] == ['1750', '1752'] and not actual['durable_recorded']
        assert actual['review_gate'] == 'fresh_review_required' and not actual['inline_fallback']
        if actual['report_destination'] == 'existing_record':
            # Simulated permitted write and independent read-back.
            assert writable
            record.write_text(json.dumps(actual['handoff']))
            assert json.loads(record.read_text()) == actual['handoff']
            assert json.loads(record.read_text())['pr'] == 2102
            assert json.loads(record.read_text())['stage'] == handoff['stage']
            assert json.loads(record.read_text())['state'] == handoff['state']
            assert json.loads(record.read_text())['action'] == 'Bash token=[REDACTED]'
            assert json.loads(record.read_text())['stops'] == ['stage_role_tool_or_path_denied']
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

# Corrected access permits a resume attempt but does not satisfy the item
# prerequisite or release its direct and transitive dependents.
resumed = receive(dict(event, corrected=True, reconciled=True))
assert resumed['result'] == 'resume_same_role' and resumed['hold_dependents']
assert resumed['held_dependents'] == ['1750', '1752']
mixed_report = receive(dict(event, cause='mixed', readonly_stop=True))['handoff']
assert mixed_report['stops'] == ['stage_role_tool_or_path_denied', 'missing_required_secret_or_permission']
assert len(mixed_report['remedies']) == 3
mixed_recovery = dict(event, cause='mixed', corrected=True, reconciled=True)
assert receive(mixed_recovery)['result'] == 'blocked'
assert receive(dict(mixed_recovery, corrected=False, credential_corrected=True))['result'] == 'blocked'
assert receive(dict(mixed_recovery, credential_corrected=True))['result'] == 'resume_same_role'

# Portfolio receiver fixture is explicitly tied to Protocol 90's ordering and
# no-fallback rule; the reports are fabricated and no agent is executed.
def portfolio_route(text, report, decision=None, runner_report=None):
    start = text.index('## Step 4.1: Subagent Permission-Denial Detection and Inline Fallback')
    end = text.index('### No-redispatch rule', start)
    rules = text[start:end]
    stage_first = rules.find('First classify `STAGE_ROLE_TOOL_OR_PATH_DENIED:`')
    runner_detection = rules.find("Check whether a separately attributable Work Item Runner's own report")
    separate_rule = 'A quoted or nested occurrence inside a stage-role report is not a separate Work Item Runner denial' in rules
    blocks_inline = 'never run the Work Item Runner inline fallback for that stage denial' in rules
    if ('STAGE_ROLE_TOOL_OR_PATH_DENIED:' in report or 'stage_role_tool_or_path_denied' in report):
        return {'fallback': not (stage_first >= 0 and stage_first < runner_detection and blocks_inline and separate_rule),
                'held': decision['held_dependents'],
                'runner_fallback': bool(runner_report and 'SUBAGENT_PERMISSION_DENIAL:' in runner_report and 'If a separately established Work Item Runner denial is also reported' in rules)}
    if 'SUBAGENT_PERMISSION_DENIAL:' in report and runner_detection >= 0:
        return {'fallback': True, 'held': []}
    return {'fallback': False, 'held': []}

stage_result = receive(dict(event, record_available=False))
stage_report = 'STAGE_ROLE_TOOL_OR_PATH_DENIED: stage_role_tool_or_path_denied; SUBAGENT_PERMISSION_DENIAL: quoted context'
runner_report = 'SUBAGENT_PERMISSION_DENIAL: Bash tool denied on target'
def assert_portfolio_routes(text):
    assert portfolio_route(text, stage_report, stage_result) == {'fallback': False, 'held': ['1750', '1752'], 'runner_fallback': False}
    assert portfolio_route(text, runner_report) == {'fallback': True, 'held': []}
    assert portfolio_route(text, stage_report, stage_result, runner_report) == {'fallback': False, 'held': ['1750', '1752'], 'runner_fallback': True}
assert_portfolio_routes(portfolio)
plant = portfolio.replace('never run the Work Item Runner inline fallback for that stage denial',
                          'always run the Work Item Runner inline fallback for that stage denial', 1)
try:
    assert_portfolio_routes(plant)
except AssertionError:
    print('PLANT: portfolio stage-denial fallback was detected')
else:
    raise AssertionError('portfolio boundary violation was not detected')
assert_portfolio_routes(portfolio)
print('REPAIR: portfolio stage and runner routes verified')

# A missing sanitizer fails closed with a bounded diagnostic, never a traceback.
with tempfile.TemporaryDirectory() as tmp:
    isolated = Path(tmp) / 'decision.py'
    isolated.write_bytes(helper.read_bytes())
    failed = subprocess.run([sys.executable, str(isolated)], input=json.dumps(event),
                            text=True, capture_output=True)
    assert failed.returncode == 2 and 'Traceback' not in failed.stderr
    assert 'private-sentinel' not in failed.stdout + failed.stderr
    (Path(tmp) / 'workflow-config-resolver.py').write_text(
        "def redact_diagnostic_json(value):\n    raise RuntimeError('private-sentinel')\n")
    failed = subprocess.run([sys.executable, str(isolated)], input=json.dumps(event),
                            text=True, capture_output=True)
    assert failed.returncode == 2 and 'Traceback' not in failed.stderr
    assert 'private-sentinel' not in failed.stdout + failed.stderr

# A CLI reviewer may return both an ordinary verdict and an explicit denial.
# The Step 7a receiver must prioritize the denial over both approval and fixes.
def review_route(protocol, response):
    precedence = ('The receiver checks the report and established access evidence before applying any ordinary verdict' in protocol
                  and 'never enters the fixer loop solely as `NEEDS REVISION`' in protocol)
    if 'STAGE_ROLE_TOOL_OR_PATH_DENIED:' in response and precedence:
        return 'access_stop'
    return 'approval' if 'VERDICT: APPROVED' in response else 'fixer'
def assert_review_precedence(protocol):
    for verdict in ('VERDICT: APPROVED', 'VERDICT: NEEDS REVISION'):
        assert review_route(protocol, 'STAGE_ROLE_TOOL_OR_PATH_DENIED: Bash denied; ' + verdict) == 'access_stop'
    assert review_route(protocol, 'VERDICT: NEEDS REVISION') == 'fixer'
assert_review_precedence(item)
plant_review = item.replace('The receiver checks the report and established access evidence before applying any ordinary verdict',
                            'The receiver applies the ordinary verdict first', 1)
try:
    assert_review_precedence(plant_review)
except AssertionError:
    print('PLANT: reviewer denial precedence violation detected')
else:
    raise AssertionError('reviewer denial precedence violation was not detected')
assert_review_precedence(item)
print('REPAIR: reviewer denial precedence verified')

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
def assert_boundary(script):
    assert boundary_exit(script) == 2
assert_boundary(helper)
with tempfile.TemporaryDirectory() as tmp:
    planted = Path(tmp) / 'decision.py'
    original = helper.read_text()
    needle = "if handoff['marker'] != 'STAGE_ROLE_TOOL_OR_PATH_DENIED':"
    assert needle in original
    planted.write_text(original.replace(needle, "if False:", 1))
    (Path(tmp) / 'workflow-config-resolver.py').write_bytes(
        (helper.parent / 'workflow-config-resolver.py').read_bytes())
    try:
        assert_boundary(planted)
    except AssertionError:
        print('PLANT: stage-boundary assertion failed for runner denial')
    else:
        raise AssertionError('stage-boundary violation was not detected')
    assert_boundary(helper)
    print('REPAIR: stage-boundary assertion passed after restoration')
# Re-run this actual synced suite in a disposable consumer checkout whose
# project-owned configuration deliberately has no stop_conditions list.
if sys.argv[2] == 'true' and os.environ.get('STAGE_ROLE_CONSUMER_FIXTURE') != '1':
    with tempfile.TemporaryDirectory(prefix='stage-role-consumer-') as tmp:
        consumer = Path(tmp)
        (consumer / 'scripts').mkdir()
        (consumer / 'docs/workflow').mkdir(parents=True)
        shutil.copytree(root / 'scripts/development-workflow', consumer / 'scripts/development-workflow')
        shutil.copytree(base, consumer / 'docs/workflow/development-workflow')
        (consumer / '.ai-dev-workflow.yaml').write_text('template:\n  is_template: false\n')
        env = dict(os.environ, STAGE_ROLE_CONSUMER_FIXTURE='1')
        run = subprocess.run(['bash', str(consumer / 'scripts/development-workflow/tests/test-stage-role-permission-denial.sh')],
                             env=env, text=True, capture_output=True)
        assert run.returncode == 0, run.stdout + run.stderr
        assert 'PASS: stage-role denial contract' in run.stdout
    print('PASS: consumer configuration with no stop list')
print('PASS: stage-role denial contract, boundaries and planted violation')
PY

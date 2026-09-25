#!/usr/bin/env bash
# covers: scripts/development-workflow/reviewer_preflight.py
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
# covers: .claude/agents/item-orchestrator.md .cursor/agents/item-orchestrator.md
# covers: docs/workflow/development-workflow/integrations/coderabbit.md
#
# Reads reviewer_preflight.py's OUTCOME_LABELS / exit_code_for_outcome as the
# ground truth (per the review-code checklist item on citing script-emitted
# signal values from source, not memory) and asserts Protocol 91's "Reviewer
# preflight before child dispatch" section and both item-orchestrator agent
# mirrors state the same outcome codes, display labels, and exit codes — and
# that both agent mirrors require stopping on blocked / prerequisite-failed.
set -euo pipefail
ROOT=${SURFACE_ROOT:-"$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"}
python3 - "$ROOT" <<'PY'
import pathlib, re, sys

root = pathlib.Path(sys.argv[1]).resolve()
engine = root / 'scripts/development-workflow/reviewer_preflight.py'
protocol = root / 'docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md'
agents = [
    root / '.claude/agents/item-orchestrator.md',
    root / '.cursor/agents/item-orchestrator.md',
]
coderabbit_doc = root / 'docs/workflow/development-workflow/integrations/coderabbit.md'
guardrails_doc = root / 'docs/workflow/development-workflow/guardrails-enforcement.md'

passed = 0
failed = []


def check(name, condition, detail=''):
    global passed
    if condition:
        passed += 1
        print(f'PASS: {name}', flush=True)
    else:
        failed.append(name)
        print(f'FAIL: {name}: {detail}', flush=True)


engine_src = engine.read_text()

# Ground truth: the OUTCOME_LABELS dict literal in reviewer_preflight.py.
labels_match = re.search(r'OUTCOME_LABELS = \{(.*?)\}', engine_src, re.S)
check('engine defines OUTCOME_LABELS', labels_match is not None, 'OUTCOME_LABELS dict not found')
outcome_labels = dict(re.findall(r'"([a-z-]+)":\s*"([^"]+)"', labels_match.group(1))) if labels_match else {}
check(
    'OUTCOME_LABELS has all five outcomes',
    set(outcome_labels) == {'passed', 'passed-unverified', 'blocked', 'prerequisite-failed', 'no-review-remaining'},
    outcome_labels,
)

exit_match = re.search(r'def exit_code_for_outcome.*?return \{(.*?)\}\[outcome\]', engine_src, re.S)
check('engine defines exit_code_for_outcome mapping', exit_match is not None, 'mapping not found')
exit_codes = dict(re.findall(r'"([a-z-]+)":\s*(\d+)', exit_match.group(1))) if exit_match else {}

protocol_text = protocol.read_text()
gate_section_match = re.search(
    r'### Reviewer preflight before child dispatch(.*?)\n### Existing-branch reuse validation',
    protocol_text,
    re.S,
)
check('Protocol 91 has the Reviewer preflight section', gate_section_match is not None)
gate_section = gate_section_match.group(1) if gate_section_match else ''

for outcome, label in outcome_labels.items():
    check(
        f'Protocol 91 states {outcome} -> {label!r}',
        f'`{outcome}`' in gate_section and label in gate_section,
        gate_section,
    )

for outcome, code in exit_codes.items():
    if outcome == 'no-review-remaining':
        # Documented as its own row with the same exit code as passed; a
        # single combined mention is acceptable as long as the code appears.
        pass
    check(
        f'Protocol 91 states {outcome} exit code {code}',
        f'`{code}`' in gate_section,
        gate_section,
    )

for mode in ('pre-dispatch', 'branch-resume', 'pr-resume'):
    check(f'Protocol 91 names --mode {mode}', mode in gate_section)

# Named-stop contract (guardrails-enforcement.md § 5 Stop-Message Contract):
# a Blocked/Prerequisite-not-met preflight stop must use one of the exact
# stop-condition strings recognized by § 4 Named Stop Conditions, not a
# generic "stop" description.
guardrails_text = guardrails_doc.read_text()
for stop_condition in (
    'reviewer_preflight_blocked',
    'reviewer_preflight_prerequisite_failed',
    'reviewer_preflight_tooling_failed',
):
    check(
        f'guardrails-enforcement.md defines {stop_condition}',
        f'`{stop_condition}`' in guardrails_text,
        guardrails_text,
    )
    check(
        f'Protocol 91 names the {stop_condition} stop condition',
        f'`{stop_condition}`' in gate_section,
        gate_section,
    )

# #1561 round-22 finding: the tooling-failure (exit 3) row must use its own
# distinct stop-condition name, not reuse reviewer_preflight_prerequisite_failed
# (reserved for OUTCOME=prerequisite-failed) — assert the exit-3 row's own
# text names the tooling-specific string and not the prerequisite-failed one.
exit3_row_match = re.search(r'\(tooling failure, exit `3`\).*', gate_section)
check('Protocol 91 has a tooling-failure (exit 3) row', exit3_row_match is not None, gate_section)
if exit3_row_match:
    exit3_row = exit3_row_match.group(0)
    check(
        'the exit-3 row names reviewer_preflight_tooling_failed',
        '`reviewer_preflight_tooling_failed`' in exit3_row,
        exit3_row,
    )
    check(
        'the exit-3 row does not reuse reviewer_preflight_prerequisite_failed as its own stop condition',
        # A clarifying cross-reference to the other name is fine (and
        # present, deliberately, to explain the distinction); what must not
        # recur is the exact "naming the exact stop condition
        # `reviewer_preflight_prerequisite_failed`" phrase this row used
        # pre-fix.
        'naming the exact stop condition `reviewer_preflight_prerequisite_failed`' not in exit3_row,
        exit3_row,
    )

for agent_path in agents:
    text = agent_path.read_text()
    section = text[text.find('reviewer-preflight.sh'):]
    check(f'{agent_path.name} references reviewer-preflight.sh', 'reviewer-preflight.sh' in text)
    check(
        f'{agent_path.name} requires stop on blocked',
        'blocked' in section and 'exit `1`' in section,
        section[:400],
    )
    check(
        f'{agent_path.name} requires stop on prerequisite-failed',
        'prerequisite-failed' in section and 'exit `2`' in section,
        section[:400],
    )
    check(
        f'{agent_path.name} requires stop on tooling failure (exit 3)',
        'exit `3`' in section,
        section[:600],
    )
    check(
        f'{agent_path.name} requires the report before item output',
        'before this item' in section,
        section[:400],
    )
    for mode in ('pre-dispatch', 'branch-resume', 'pr-resume'):
        check(f'{agent_path.name} names --mode {mode}', mode in section)

cr_text = coderabbit_doc.read_text()
check(
    'coderabbit.md states the branch-in-force resolution rule',
    ("pull request's own branch" in cr_text or "PR's own branch" in cr_text)
    and 'target' in cr_text,
)

print(f'\nPassed: {passed}')
print(f'Failed: {len(failed)}')
if failed:
    for name in failed:
        print(f'  - {name}')
    raise SystemExit(1)
PY

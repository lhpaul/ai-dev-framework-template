#!/usr/bin/env python3
"""Compute bounded stage-role denial decisions from already-established facts.

Read one JSON object from stdin. This does not parse third-party error text,
perform mutations, persist reports, or grant authority. The caller independently
establishes and redacts facts and owns the report and all workflow gates.
"""
import json
import runpy
import sys
from pathlib import Path


def decide(event):
    if not isinstance(event, dict):
        raise ValueError('invalid event')
    allowed = {'cause', 'review', 'readonly_stop', 'handoff_stop', 'record_available',
               'uncertain', 'corrected', 'credential_corrected', 'reconciled', 'context_changed', 'denied_again', 'handoff', 'mode'}
    if set(event) - allowed:
        raise ValueError('invalid field')
    cause = event.get('cause')
    if cause not in ('tool_path', 'credential', 'mixed', 'unknown', 'unreachable', 'generic'):
        raise ValueError('invalid cause')
    if event.get('mode', 'manual') not in ('manual', 'assisted', 'delegated', 'autonomous'):
        raise ValueError('invalid mode')
    for key in allowed - {'cause', 'handoff', 'mode'}:
        if key in event and not isinstance(event[key], bool):
            raise ValueError('invalid flag')
    stops = []
    if cause in ('tool_path', 'mixed'):
        stops.append('stage_role_tool_or_path_denied')
    if cause in ('credential', 'mixed'):
        stops.append('missing_required_secret_or_permission')
    if cause == 'unknown':
        stops.append('unclear_requirements')
    if cause == 'unreachable' or event.get('handoff_stop'):
        stops.append('dispatch_handoff_unavailable')
    # Recovery here is only a candidate for re-dispatch. Other workflow gates
    # and independently applicable stops remain the caller's responsibility.
    recoverable = (cause in ('tool_path', 'mixed')
                   and (cause != 'mixed' or event.get('credential_corrected', False))
                   and not event.get('readonly_stop') and not event.get('handoff_stop'))
    ready = (recoverable and event.get('corrected', False)
             and 'uncertain' in event
             and (not event['uncertain'] or event.get('reconciled', False))
             and not event.get('denied_again', False))
    if cause == 'generic' and not stops and not event.get('readonly_stop'):
        return {'result': 'existing_error'}
    result = {
        'result': ('existing_error' if cause == 'generic' and not stops and not event.get('readonly_stop')
                   else 'resume_same_role' if ready else 'blocked'),
        'stops': [] if ready else stops,
        'review_gate': 'fresh_review_required' if event.get('review') else 'unchanged',
        'report_destination': 'existing_record' if event.get('record_available') else 'operator_handoff',
        'readonly_blocked': bool(event.get('readonly_stop')),
        # Recovery permits redispatch, not completion of the prerequisite.
        'hold_dependents': True,
        'fresh_run_and_profile': bool(ready and event.get('context_changed')),
        'inline_fallback': False,
        'needs_fixes_for_denial': False,
    }
    if 'handoff' in event:
        handoff = event['handoff']
        keys = {'marker', 'item', 'stage', 'role', 'action', 'state', 'pr', 'dependencies'}
        if not isinstance(handoff, dict) or set(handoff) != keys:
            raise ValueError('invalid handoff')
        if handoff['marker'] != 'STAGE_ROLE_TOOL_OR_PATH_DENIED':
            raise ValueError('invalid role boundary')
        def item_id(value):
            if type(value) is int and value > 0:
                return str(value)
            if isinstance(value, str) and value.strip() and len(value) <= 300 and not any(ord(c) < 32 for c in value):
                return value
            raise ValueError('invalid item identifier')
        item_id(handoff['item'])
        if handoff['pr'] is not None and (type(handoff['pr']) is not int or handoff['pr'] < 1):
            raise ValueError('invalid pr')
        for key in ('stage', 'role', 'action', 'state'):
            if not isinstance(handoff[key], str) or not handoff[key].strip() or len(handoff[key]) > 300:
                raise ValueError('invalid report field')
        deps = handoff['dependencies']
        if not isinstance(deps, dict):
            raise ValueError('invalid dependencies')
        for child, prerequisites in deps.items():
            item_id(child)
            if not isinstance(prerequisites, list):
                raise ValueError('invalid prerequisites')
            for parent in prerequisites:
                item_id(parent)
        held = set()
        blocked = {item_id(handoff['item'])}
        if result['hold_dependents']:
            while True:
                found = {item_id(child) for child, parents in deps.items()
                         if blocked.intersection(item_id(parent) for parent in parents)} - blocked
                if not found:
                    break
                held.update(found)
                blocked.update(found)
        try:
            sanitizer = runpy.run_path(str(Path(__file__).with_name('workflow-config-resolver.py')))
            redact = sanitizer['redact_diagnostic_json']
        except Exception as exc:
            # Do not expose local paths or input details when tooling is missing.
            raise ValueError('redactor unavailable') from exc
        report = {k: handoff[k] for k in ('item', 'stage', 'role', 'action', 'state', 'pr')}
        report['stops'] = list(result['stops'])
        remedies = {
            'stage_role_tool_or_path_denied': 'Correct access, reconcile uncertain effects, and retry the same role.',
            'missing_required_secret_or_permission': 'Correct the identified credential or GitHub permission.',
            'unclear_requirements': 'Resolve the missing facts with the operator.',
            'dispatch_handoff_unavailable': 'Restore the applicable handoff or follow the profile remedy.',
        }
        report['remedies'] = [remedies[stop] for stop in result['stops']]
        if result['readonly_blocked']:
            report['remedies'].append('Resolve the independently established read-only restriction.')
        report['unblock_action'] = ' '.join(report['remedies']) if report['remedies'] else 'Continue under the existing gates.'
        try:
            result['handoff'] = redact(report)
        except Exception as exc:
            raise ValueError('redaction failed') from exc
        if handoff['stage'] == 'review':
            result['review_gate'] = 'fresh_review_required'
        result['held_dependents'] = sorted(held)
        # The helper plans a write but cannot assert that any remote record was written.
        result['durable_recorded'] = False
    return result


def main():
    try:
        event = json.load(sys.stdin)
        print(json.dumps(decide(event), sort_keys=True))
        return 0
    except (ValueError, TypeError, json.JSONDecodeError):
        print('stage-role decision: invalid input', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())

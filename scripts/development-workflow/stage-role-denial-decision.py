#!/usr/bin/env python3
"""Compute bounded stage-role denial decisions from already-established facts.

Read one JSON object from stdin. This does not parse third-party error text,
perform mutations, persist reports, or grant authority. The caller independently
establishes and redacts facts and owns the report and all workflow gates.
"""
import json
import sys


def decide(event):
    if not isinstance(event, dict):
        raise ValueError('invalid event')
    allowed = {'cause', 'review', 'readonly_stop', 'handoff_stop', 'record_available',
               'uncertain', 'corrected', 'reconciled', 'context_changed', 'denied_again'}
    if set(event) - allowed:
        raise ValueError('invalid field')
    cause = event.get('cause')
    if cause not in ('tool_path', 'credential', 'mixed', 'unknown', 'unreachable', 'generic'):
        raise ValueError('invalid cause')
    for key in allowed - {'cause'}:
        if key in event and not isinstance(event[key], bool):
            raise ValueError('invalid flag')
    if cause == 'generic':
        return {'result': 'existing_error'}
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
    recoverable = cause == 'tool_path' and not event.get('readonly_stop') and not event.get('handoff_stop')
    ready = (recoverable and event.get('corrected', False)
             and (not event.get('uncertain', False) or event.get('reconciled', False))
             and not event.get('denied_again', False))
    return {
        'result': 'resume_same_role' if ready else 'blocked',
        'stops': [] if ready else stops,
        'review_gate': 'fresh_review_required' if event.get('review') else 'unchanged',
        'report_destination': 'existing_record' if event.get('record_available') else 'operator_handoff',
        'readonly_blocked': bool(event.get('readonly_stop')),
        'hold_dependents': not ready,
        'fresh_run_and_profile': bool(ready and event.get('context_changed')),
        'inline_fallback': False,
        'needs_fixes_for_denial': False,
    }


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

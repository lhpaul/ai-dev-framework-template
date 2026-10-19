#!/usr/bin/env python3
"""Binding D01-D47: synthetic paired-channel runtime/publication diagnostics."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import shlex
import subprocess
import unittest

SPEC = importlib.util.spec_from_file_location('diagnostic_fixtures', Path(__file__).with_name('test_private_source_consumers.py'))
fixtures = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fixtures)


class RunnerDiagnosticEmitters(unittest.TestCase):
    def setUp(self):
        self.f = fixtures.PrivateSourceConsumers(methodName='runTest')
        self.f.setUp()
        self.addCleanup(self.f.doCleanups)
        home = self.f.root / 'home'; home.mkdir()
        import yaml
        self.f.env.update(HOME=str(home), PYTHONPATH=str(Path(yaml.__file__).resolve().parent.parent))
        self.f.private.write_text('review:\n  on_draft:\n    runner: [codex]\n')
        self.secret = 'fabricatedDiagnosticValue'

    def run_command(self, command, *, input=None):
        return subprocess.run(command, env=self.f.env, cwd=self.f.checkout, input=input,
                              capture_output=True, text=True, timeout=30)

    def entry(self, name, *args):
        return self.run_command(['bash', str(self.f.runtime / name), *args])

    def bash(self, body, *, loop=False):
        source = self.f.runtime / ('pr-review-loop.sh' if loop else 'workflow-lib.sh')
        prefix = ('HARNESS_MODE=1 source ' if loop else 'source ') + shlex.quote(str(source)) + '\n'
        return self.run_command(['bash', '-c', prefix + body])

    def safe(self, result, status):
        self.assertEqual(result.returncode, status, result.stdout + result.stderr)
        for stream in (result.stdout, result.stderr):
            self.assertNotIn(self.secret, stream)
            self.assertNotIn('fabricatedChildError', stream)
        return result

    def ronda(self, *, conclusion='failure', blocking=0, prefix=False):
        payload = self.f.root / 'checks.json'
        payload.write_text(json.dumps({'check_runs': [{
            'name': 'Ronda review', 'id': 1, 'head_sha': 'a' * 40,
            'status': 'completed', 'conclusion': conclusion,
            'output': {'title': 'token=' + self.secret + ' opaque suffix',
                       'summary': f'Blocking: {blocking}, Important: 0, Nit: 0\npassword: {self.secret}'},
        }]}))
        body = '''require_gh() { :; }
cd_workflow_repo_root() { :; }
repo_slug() { printf 'fixture/repo\\n'; }
gh() {
  printf 'token=fabricatedChildError\\n' >&2
  case "$*" in
    "pr view "*) printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\n' ;;
    *"check-runs"*) cat PAYLOAD ;;
    *) return 99 ;;
  esac
}
'''.replace('PAYLOAD', shlex.quote(str(payload)))
        call = 'run_ronda_review 1993 feature/1993-fixture 1 1'
        if prefix:
            body += 'status=0\noutput="$(' + call + ')" || status=$?\nemit_prefixed_platform_output 1 "$output"\nexit "$status"\n'
        else:
            body += call
        return self.bash(body, loop=True)

    def audit_fixture(self):
        path = self.f.root / 'audit.json'
        path.write_text(json.dumps({
            'scope_source': 'synthetic #1993', 'item': {'number': 1993, 'title': 'Synthetic'},
            'pr': {'number': 1993, 'head_sha': 'a' * 40}, 'risk': {'level': 'low'},
            'merge_authority': 'none', 'final_decision': 'hold', 'reviewer': {'result': 'clean'},
            'advisories': [{'source': 'fixture', 'decision': 'fixed',
                            'rationale': 'Authorization: dummy Bearer ' + self.secret}],
            'unknown token=' + self.secret: True,
        }))
        return path

    def test_D01_sanitizer_failure_in_real_local_entry(self):
        python = self.f.bin / 'python3'
        python.write_text('#!/bin/sh\nprintf "token=' + self.secret + '\\n" >&2\nexit 7\n')
        python.chmod(0o755)
        self.f.env['LOCAL_AI_REVIEWER_BACKEND'] = 'token=' + self.secret
        result = self.safe(self.entry('local-ai-reviewer.sh', '1993', 'fixture', 'repo'), 2)
        self.assertIn('diagnostic sanitization failed', result.stderr)

    def test_D03_structured_diagnostic_keys_and_failure(self):
        raw = {'token': self.secret, 'nested': {'api_key': [self.secret], 'reason': 'password: ' + self.secret},
               'authorization': {'authorized_by': 'fixture'}, 'Authorization': 'Bearer ' + self.secret,
               'blocking_count': 3, 'result': 'needs_fixes'}
        result = self.safe(self.run_command(['python3', str(self.f.runtime / 'workflow-config-resolver.py'),
                                             'redact-text', '--json'], input=json.dumps(raw)), 0)
        data = json.loads(result.stdout)
        self.assertEqual(data['token'], '[REDACTED]')
        self.assertEqual(data['nested']['api_key'], '[REDACTED]')
        self.assertEqual(data['authorization'], {'authorized_by': 'fixture'})
        self.assertEqual(data['blocking_count'], 3)
        self.assertEqual(data['result'], 'needs_fixes')
        malformed = self.safe(self.run_command(['python3', str(self.f.runtime / 'workflow-config-resolver.py'),
                                                'redact-text', '--json'], input='token=' + self.secret), 2)
        self.assertEqual(malformed.stdout, '')
        self.assertIn('diagnostic sanitization failed', malformed.stderr)

    def test_D02_functional_context_then_diagnostic_publication(self):
        target = self.f.root / ('token=' + self.secret); target.mkdir()
        self.f.private.write_text('product_repos:\n  - name: mobile\n    local_path: ../' + target.name + '\n')
        transport = self.f.root / 'functional.json'
        raw_kv = self.f.root / 'functional.kv'
        result = self.safe(self.bash(
            'context="$(workflow_repository_context mobile ' + shlex.quote(str(self.f.checkout)) + ')"\n' +
            'printf "%s" "$context" >' + shlex.quote(str(transport)) + '\n' +
            'print_kv FUNCTIONAL_CONFIG ' + shlex.quote('token=' + self.secret) + ' >' + shlex.quote(str(raw_kv)) + '\n' +
            'python3 ' + shlex.quote(str(self.f.runtime / 'workflow-config-resolver.py')) +
            ' resolve --repo-root ' + shlex.quote(str(self.f.checkout)) + ' --repo mobile --json | workflow_redact_json\n' +
            'workflow_diagnostic "$context" >&2'), 0)
        self.assertIn(self.secret, transport.read_text())
        self.assertIn(self.secret, raw_kv.read_text())
        self.assertEqual(json.loads(result.stdout)['WORKFLOW_MODE'], 'workflow_hub')
        self.assertIn('[REDACTED]', result.stdout)
        self.assertIn('[REDACTED]', result.stderr)

    def test_D08_result_fields_in_real_provider_paths(self):
        for conclusion, blocking, status, verdict in [('success', 0, 0, 'clean'),
                                                      ('success', 1, 1, 'needs_fixes'),
                                                      ('failure', 0, 2, 'escalate')]:
            with self.subTest(conclusion=conclusion, blocking=blocking):
                result = self.safe(self.ronda(conclusion=conclusion, blocking=blocking), status)
                self.assertIn('RESULT=' + verdict, result.stdout)

    def test_D09_prefixed_real_provider_output(self):
        result = self.safe(self.ronda(prefix=True), 2)
        self.assertIn('PLATFORM_1_RONDA_CHECK_TITLE=token=[REDACTED]', result.stdout)

    def test_D10_ronda_title_both_channels(self):
        result = self.safe(self.ronda(), 2)
        self.assertIn('RONDA_CHECK_TITLE=token=[REDACTED]', result.stdout)
        self.assertIn('Ronda pass failed', result.stderr)
        self.assertIn('[REDACTED]', result.stderr)

    def test_D22_audit_error_channel(self):
        missing = self.f.root / ('token=' + self.secret)
        result = self.safe(self.entry('run-epic-audit-trail.sh', 'render-pr-disposition', '--input', str(missing)), 1)
        self.assertIn('input file not found', result.stderr)
        self.assertEqual(result.stdout, '')

    def test_D23_audit_warning_and_report_together(self):
        result = self.safe(self.entry('run-epic-audit-trail.sh', 'render-pr-disposition', '--input', str(self.audit_fixture())), 0)
        self.assertIn('unrecognized top-level', result.stderr)
        self.assertIn('[REDACTED]', result.stderr)
        self.assertIn('<!-- run-epic:pr-disposition -->', result.stdout)

    def test_D24_audit_context_markers_and_layout(self):
        result = self.safe(self.entry('run-epic-audit-trail.sh', 'render-pr-disposition', '--input', str(self.audit_fixture())), 0)
        self.assertIn('Authorization: [REDACTED]', result.stdout)
        self.assertIn('Bearer [REDACTED]', result.stdout)
        row = next(line for line in result.stdout.splitlines() if line.startswith('| fixture |'))
        self.assertTrue(row.endswith('|'), row)
        ledger = self.f.root / 'ledger.json'
        ledger.write_text(json.dumps({'epic': {'number': 1993, 'title': 'token=' + self.secret},
                                     'items': [{'issue_number': 1993, 'notes': 'api_key=' + self.secret}]}))
        self.assertIn('<!-- run-epic:epic-ledger -->', self.safe(self.entry(
            'run-epic-audit-trail.sh', 'render-epic-ledger', '--input', str(ledger)), 0).stdout)
        bypass = self.f.root / 'bypass.json'
        bypass.write_text(json.dumps({'authorization': {'authorized_by': 'fixture', 'authorized_at': 'synthetic-time',
                                                       'authorization_text': 'token=' + self.secret},
                                     'pr': {'number': 1993, 'head_sha': 'a' * 40}, 'evidence_fingerprint': 'synthetic-fingerprint',
                                     'ci': {'result': 'green'}, 'reviewer': {'result': 'clean'},
                                     'blocked_check': {'name': 'synthetic-check'},
                                     'access': {'evidence': 'password: ' + self.secret, 'remediation_status': 'done', 'bypass_reason': 'synthetic'},
                                     'proposed_action': 'merge', 'state': 'synthetic'}))
        self.assertIn('Reviewer Access Bypass Audit', self.safe(self.entry(
            'run-epic-audit-trail.sh', 'render-reviewer-access-bypass', '--input', str(bypass)), 0).stdout)

    def test_D25_audit_publication_failure(self):
        gh = self.f.bin / 'gh'
        gh.write_text('''#!/bin/sh
case "$*" in
 "auth status"*) exit 0 ;;
 "repo view"*) echo fixture/repo ;;
 *"comments"*"--input"*) printf 'token=SECRET\\n'; printf 'api_key=SECRET\\n' >&2; exit 7 ;;
 *"comments"*) echo '[]' ;;
 *) exit 99 ;;
esac
'''.replace('SECRET', self.secret))
        result = self.safe(self.entry('run-epic-audit-trail.sh', 'apply-pr-disposition', '--input', str(self.audit_fixture()), '--pr', '1993'), 1)
        self.assertIn('failed to create marker comment', result.stderr)


if __name__ == '__main__':
    unittest.main(verbosity=2)

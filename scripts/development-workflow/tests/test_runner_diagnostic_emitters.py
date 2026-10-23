#!/usr/bin/env python3
"""Binding D01-D83: synthetic paired-channel runtime/publication diagnostics."""
from __future__ import annotations

import importlib.util
import json
import os
import signal
from pathlib import Path
import shlex
import subprocess
import unittest

SPEC = importlib.util.spec_from_file_location('diagnostic_fixtures', Path(__file__).with_name('test_private_source_consumers.py'))
fixtures = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fixtures)


# Frozen finite continuation inventory; diagnostic syntax acceptance is separate.
MULTILINE_REDACTION_CASES = [
    ('H01', 'token:\n  $OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('H02', 'token:\n  "$OPAQUE"\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('H03', "token:\n  '$OPAQUE'\npublic: KEEP_PUBLIC", ('public: KEEP_PUBLIC',), False),
    ('H04', 'token:\n  $OPAQUE', (), False),
    ('H05', 'token:\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), True),
    ('H06', 'token:', (), True),
    ('Q01', "token:\n  'first''$OPAQUE'\npublic: KEEP_PUBLIC", ('public: KEEP_PUBLIC',), False),
    ('Q02', "token:\n  'first\\$OPAQUE'\npublic: KEEP_PUBLIC", ('public: KEEP_PUBLIC',), False),
    ('Q03', 'token:\n  "first\\"$OPAQUE"\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('Q04', 'token:\n  "first\\\\\\/$OPAQUE"\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('Q05', 'token:\n  "first\n    $OPAQUE"\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('Q06', 'token:\n  "first\\n$OPAQUE"\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('Q07', 'token:\n  "first\n  $OPAQUE\npublic: ambiguous', (), False),
    ('Q08', "token: 'first\n  $OPAQUE\npublic: ambiguous", (), False),
    ('I01', 'token: first\n  $OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('I02', 'token: first\n      one\n    $OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('I03', 'token: "first\n  $OPAQUE"\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('I04', 'token: [REDACTED]\n  $OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('N01', 'outer:\n  token:\n    $OPAQUE\n  public: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('N02', '- token:\n    $OPAQUE\n  public: KEEP_PUBLIC\n- next: KEEP_NEXT', ('public: KEEP_PUBLIC', 'next: KEEP_NEXT'), False),
    ('N03', 'token:\n  child: $OPAQUE\n  other: second\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('N04', 'token:\n  - child: $OPAQUE\n    other: data\n  - second\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('N05', 'token:\n- $OPAQUE\n- second\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('N06', 'outer:\n  token:\n  - $OPAQUE\n  - second\n  public: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('N07', '- token:\n- public: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), True),
    ('B01', 'token:\n\n  # comment\n  $OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('B02', 'token: first\n  # comment\n\n  $OPAQUE\n\n# outside comment\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('B03', 'token: # comment\n  $OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('B04', 'token:\n  first#$OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('B05', "token:\n  '#$OPAQUE'\npublic: KEEP_PUBLIC", ('public: KEEP_PUBLIC',), False),
    ('B06', 'token:\n # comment\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), True),
    ('L01', 'token:\n  $OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('L02', 'token:\r\n  $OPAQUE\r\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('L03', 'token:\r  $OPAQUE\rpublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('L04', 'token:\x85  $OPAQUE\x85public: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('L05', 'token:\u2028  $OPAQUE\u2028public: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('L06', 'token:\u2029  $OPAQUE\u2029public: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('L07', 'token:\n\t$OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('K01', 'token: |\n  #$OPAQUE\n  tail\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('K02', 'token: >\n  #$OPAQUE\n  tail\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('K03', 'token: |-\n  #$OPAQUE\n  tail\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('K04', 'token: |+2\n  #$OPAQUE\n  tail\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('K05', 'token: >2-\n  #$OPAQUE\n  tail\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('K06', 'token: |\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('K07', 'outer:\n  token: >+\n    $OPAQUE\n  public: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('F01', '{token:\n "$OPAQUE", public: KEEP_PUBLIC}', ('public: KEEP_PUBLIC',), False),
    ('F02', "{token:\n '$OPAQUE', public: KEEP_PUBLIC}", ('public: KEEP_PUBLIC',), False),
    ('F03', '{token:\n $OPAQUE, public: KEEP_PUBLIC}', ('public: KEEP_PUBLIC',), False),
    ('F04', '{token:\n [$OPAQUE, {nested: second}], public: KEEP_PUBLIC}', ('public: KEEP_PUBLIC',), False),
    ('F05', '{token:\n {nested: [$OPAQUE, second], other: third}, public: KEEP_PUBLIC}', ('public: KEEP_PUBLIC',), False),
    ('F06', '{token:\n "first,}]$OPAQUE", public: KEEP_PUBLIC}', ('public: KEEP_PUBLIC',), False),
    ('F07', '{token:\n $OPAQUE, password:\n $OPAQUE, public: KEEP_PUBLIC}', ('public: KEEP_PUBLIC',), False),
    ('F08', '{token:\n [$OPAQUE, second, public: ambiguous}', (), False),
    ('F09', '{"token":\n ["$OPAQUE", {"nested": "tail"}], "public": "KEEP_PUBLIC"}', ('"public": "KEEP_PUBLIC"',), False),
    ('F10', '{token: "first\n$OPAQUE, public: ambiguous}', (), False),
    ('A01', 'Access_Token:\n  $OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('A02', 'Authorization:\n  Bearer $OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('A03', 'TOKEN=first\\\n$OPAQUE; public=KEEP_PUBLIC', ('public=KEEP_PUBLIC',), False),
    ('A04', 'TOKEN=$OPAQUE PUBLIC=KEEP_PUBLIC', ('PUBLIC=KEEP_PUBLIC',), False),
    ('A05', 'password: first $OPAQUE third\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('P01', 'WARN context password:\n  $OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('P02', '[stage] password:\n[stage]   $OPAQUE\n[stage] public: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('P03', '[stage] - password:\n[stage]     $OPAQUE\n[stage]   public: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('P04', 'notice password: "first\n  $OPAQUE"\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('I05', 'token: [REDACTED]$OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('F11', "can't retry\n{token:\n$OPAQUE, public: KEEP_PUBLIC}", ('public: KEEP_PUBLIC',), False),
    ('F12', 'token: [public]$OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('Q09', 'token: "public"$OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('P05', '  [stage] password:\n  [stage]   $OPAQUE\n  [stage] public: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('P06', '  [stage] - password:\n  [stage]     $OPAQUE\n  [stage]   public: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('F13', 'unclosed prose "stage\n{token:\n$OPAQUE, public: KEEP_PUBLIC}', ('public: KEEP_PUBLIC',), False),
    ('A06', '| fixture | Authorization: [REDACTED] Bearer [REDACTED] |', ('|',), False),
    ('A07', 'token: first|$OPAQUE, suffix ; tail\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('A08', 'token: [REDACTED] |\n  $OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
    ('A09', 'token: "public"|$OPAQUE\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',), False),
]

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
        process = subprocess.Popen(command, env=self.f.env, cwd=self.f.checkout,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
        try:
            stdout, stderr = process.communicate(input, timeout=30)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.communicate()
            raise
        return subprocess.CompletedProcess(command, process.returncode, stdout, stderr)

    def entry(self, name, *args):
        return self.run_command([getattr(self, '_entry_shell', 'bash'), str(self.f.runtime / name), *args])

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

    def ronda(self, *, conclusion='failure', blocking=0, prefix=False, title=None):
        payload = self.f.root / 'checks.json'
        payload.write_text(json.dumps({'check_runs': [{
            'name': 'Ronda review', 'id': 1, 'head_sha': 'a' * 40,
            'status': 'completed', 'conclusion': conclusion,
            'output': {'title': title or 'token=' + self.secret + ' opaque suffix',
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

    def preflight(self, *extra):
        return self.entry('reviewer-preflight.sh', '--repo-root', str(self.f.checkout),
                          '--owner', 'fixture', '--repo', 'repo', '--mode', 'pre-dispatch',
                          '--target-base', 'develop', '--remaining-stages', 'on_draft.runner',
                          '--pr-state', 'on_draft.runner=draft', *extra)

    def test_D04_preflight_real_git_failure_handoff(self):
        import shutil
        real_git = shutil.which('git', path=self.f.env['PATH'])
        git = self.f.bin / 'git'
        git.write_text('#!/bin/sh\ncase "$*" in *"ls-remote"*) printf "token=' + self.secret +
                       '\\n" >&2; exit 7;; esac\nexec ' + shlex.quote(real_git) + ' "$@"\n')
        git.chmod(0o755)
        result = self.safe(self.preflight(), 3)
        self.assertIn('cannot resolve', result.stderr)
        self.assertIn('token=[REDACTED]', result.stderr)

    def test_D05_preflight_actual_classifier_reports_json_and_kv(self):
        self.f.private.write_text('review:\n  on_draft:\n    runner: ["token=' + self.secret + '"]\n')
        for flags in ((), ('--json',)):
            with self.subTest(flags=flags):
                result = self.safe(self.preflight(*flags), 1)
                if flags:
                    data = json.loads(result.stdout)
                    self.assertEqual(data['outcome'], 'blocked')
                else:
                    self.assertIn('OUTCOME=blocked', result.stdout)
                    self.assertIn('value-not-supported', result.stdout)
                self.assertIn('unknown', result.stdout)
                self.assertIn('configuration validation error', result.stdout)

    def test_D06_availability_real_source_failure_and_fail(self):
        self.f.private.write_text('review: [invalid,, token=' + self.secret + ']\n')
        result = self.safe(self.entry('resolve-reviewer-availability.sh', '--repo-root', str(self.f.checkout),
                                      '--owner', 'fixture', '--repo', 'repo', '--runner-kind', 'codex'), 1)
        self.assertIn('invalid YAML', result.stdout)
        self.assertIn('BLOCK_CAUSE=policy-unreadable', result.stdout)
        bad = self.safe(self.entry('resolve-reviewer-availability.sh', '--bad token=' + self.secret), 2)
        self.assertIn('unknown argument', bad.stderr)

    def test_D07_availability_actual_report_values(self):
        self.f.private.write_text('review:\n  on_draft:\n    runner: ["token=' + self.secret + '"]\n')
        result = self.safe(self.entry('resolve-reviewer-availability.sh', '--repo-root', str(self.f.checkout),
                                      '--owner', 'fixture', '--repo', 'repo', '--runner-kind', 'codex'), 1)
        self.assertIn('REVIEWER_2_NAME=unknown', result.stdout)
        self.assertIn('value-not-supported', result.stdout)
        self.assertIn('value-not-supported', result.stdout)
        self.assertIn('OUTCOME=', result.stdout)

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


    def gh_script(self, text):
        path = self.f.bin / 'gh'
        path.write_text('#!/bin/sh\n' + text.replace('SECRET', self.secret))
        path.chmod(0o755)

    def local_entry(self, payload, stderr=None, status=0, context_capture=None, **env):
        (self.f.checkout / 'REVIEW.md').write_text('# Synthetic reviewer contract\n')
        self.gh_script('case "$*" in "pr diff"*) echo README.md;; "repo view"*) echo fixture/repo;; "pr view"*) cat "$SYNTHETIC_PR";; "auth status"*) exit 0;; *) exit 99;; esac\n')
        command = self.f.bin / 'synthetic-review'
        command.write_text('#!/bin/sh\n' + (('cp "$CONTEXT_BUNDLE_PATH" ' + shlex.quote(str(context_capture)) + '\n') if context_capture else '') + 'printf "%s\\n" ' + shlex.quote(json.dumps(payload) if isinstance(payload, dict) else payload) + '\n' +
                           'printf "%s\\n" ' + shlex.quote(stderr or 'token=' + self.secret) + ' >&2\nexit ' + str(status) + '\n')
        command.chmod(0o755)
        self.f.env.update(LOCAL_AI_REVIEWER_COMMAND=str(command), LOCAL_AI_REVIEWER_GRAPH_STRATEGY='none', **env)
        return self.entry('local-ai-reviewer.sh', '1993', 'fixture', 'repo')

    def test_D11_hosted_producer_reports_and_native_errors(self):
        for function in ('run_greptile_review', 'run_copilot_review', 'run_bugbot_review',
                         'run_devin_review', 'run_pr_agent_review', 'run_coderabbit_review'):
            with self.subTest(producer=function):
                result = self.safe(self.bash('require_gh() { :; }; cd_workflow_repo_root() { :; }; repo_slug() { echo fixture/repo; };\n' +
                    'gh() { printf "token=' + self.secret + '\\n" >&2; return 0; };\n' +
                    function + ' 1993 "feature/token=' + self.secret + '" 1 1', loop=True), 2)
                self.assertIn('REASON=head-sha-unavailable', result.stdout)
                self.assertIn('BRANCH=feature/token=[REDACTED]', result.stdout)
        # A real finding path reaches the shared escaped-KV sink too.
        comments = json.dumps([{'id': 42, 'user': {'login': 'greptile-apps[bot]'},
                                'created_at': '2026-10-19T00:00:00Z', 'original_commit_id': 'a' * 40,
                                'body': '[P1] password: ' + self.secret, 'path': 'token=' + self.secret, 'line': 4}])
        result = self.safe(self.bash('require_gh() { :; }; cd_workflow_repo_root() { :; }; repo_slug() { echo fixture/repo; };\n' +
            'loop_head_sha=' + 'a' * 40 + '; PR_REVIEW_TRIGGER_AUTHOR_LOGIN=fixture;\n' +
            'gh() { printf "token=' + self.secret + '\\n" >&2; case "$*" in *"commits/"*) echo 2020-01-01T00:00:00Z;; ' +
            '*"pulls/1993/comments"*) printf "%s\\n" ' + shlex.quote(comments) + ';; *) echo "[]";; esac; }\n' +
            'run_greptile_review 1993 feature/1993-fixture 1 1', loop=True), 1)
        self.assertIn('RESULT=needs_fixes', result.stdout)
        self.assertIn('BLOCKING_1_BODY=', result.stdout)

    def test_D12_real_child_adapter_handoff(self):
        import shutil
        real_git = shutil.which('git', path=self.f.env['PATH'])
        git = self.f.bin / 'git'
        git.write_text('#!/bin/sh\ncase "$*" in *"remote get-url origin"*) echo https://github.com/fixture/repo.git; exit 0;; esac\nexec ' +
                       shlex.quote(real_git) + ' "$@"\n')
        git.chmod(0o755)
        self.local_entry({'result': 'needs_rerun', 'reason': 'password: ' + self.secret})
        result = self.safe(self.bash('repo_root=' + shlex.quote(str(self.f.checkout)) + ';\n' +
            'run_local_ai_reviewer_review 1993 feature/1993-fixture 1 3', loop=True), 1)
        self.assertIn('PLATFORM=local-ai-reviewer', result.stdout)
        self.assertIn('REASON=password: [REDACTED]', result.stdout)

    def test_D13_read_denial_classifies_original_before_redaction(self):
        path = self.f.root / 'read.err'
        for error, status in [('token=' + self.secret + ' HTTP 403 forbidden', 0),
                              ('retry token=' + self.secret, 1)]:
            with self.subTest(status=status):
                path.write_text(error)
                result = self.safe(self.bash('reviewer_loop_gh_read_denied ' + shlex.quote(str(path)), loop=True), status)
                self.assertEqual(path.read_text(), '')
                self.assertIn('[REDACTED]', result.stdout + result.stderr)

    def test_D14_loop_startup_and_ownership_diagnostic_handoffs(self):
        result = self.safe(self.entry('pr-review-loop.sh', '1993', '--bad token=' + self.secret), 64)
        self.assertIn('Unknown option', result.stderr)
        result = self.safe(self.bash('print_reviewer_read_denied fixture 1993 "feature/token=' + self.secret + '" "password: ' + self.secret + '"', loop=True), 0)
        self.assertIn('RESULT=escalate', result.stdout)
        self.assertIn('[REDACTED]', result.stderr)

    def test_D15_history_and_preserved_sections_publication(self):
        payload = {'schema': 'reviewer_loop_history.v1', 'history_status': 'available',
                   'entries': [{'result': 'clean', 'blocking_count': 0, 'detail': 'token=' + self.secret}]}
        body = 'reviewer_loop_history_payload_from_existing() { printf "%s" ' + shlex.quote(json.dumps(payload)) + '; }\n'
        body += 'reviewer_loop_history_append_to_summary "summary password: ' + self.secret + '" ""\n'
        body += 'workflow_diagnostic "token=' + self.secret + '" >&2\n'
        result = self.safe(self.bash(body, loop=True), 0)
        parsed = json.loads(result.stdout.split('```json\n')[1].split('```')[0])
        self.assertEqual(parsed['entries'][0]['result'], 'clean')
        self.assertIn('[REDACTED]', parsed['entries'][0]['detail'])
        published = self.f.root / 'published-summary.md'
        self.f.env['SYNTHETIC_PUBLISHED'] = str(published)
        self.gh_script('case "$*" in "repo view"*) echo fixture/repo;; "pr comment"*) while [ "$#" -gt 0 ]; do ' +
                       'case "$1" in --body-file) cp "$2" "$SYNTHETIC_PUBLISHED"; break;; *) shift;; esac; done;; *) echo "[]";; esac\n')
        # Definition only from after the harness-return point; no main loop runs.
        post = fixtures.function_text('pr-review-loop.sh', '_post_review_summary')
        result = self.safe(self.bash(post + '\npr_number=1993; branch_name=feature/1993-fixture; compare_mode=0; compare_verdicts=();\n' +
                                    '_post_review_summary escalate "token=' + self.secret + '" fixture 0 0', loop=True), 0)
        self.assertIn('Automated Reviewer Loop Summary', published.read_text())
        self.assertIn('[REDACTED]', published.read_text())
        self.assertNotIn(self.secret, published.read_text())

    def test_D16_metrics_timing_and_missed_finding_renderers(self):
        folder = self.f.checkout / 'docs/workflow'; folder.mkdir(parents=True)
        timing = json.dumps({'platform': 'token=' + self.secret, 'result': 'clean', 'outcome_class': 'verdict_received',
                             'wait_budget_seconds': 1, 'wait_budget_source': 'default', 'elapsed_seconds': 1})
        missed = json.dumps({'reviewer': 'token=' + self.secret, 'reviewed_head': 'a' * 40, 'blocking_count': 1,
                             'path_total': 1, 'paths': ['password: ' + self.secret], 'local_evidence_state': 'unknown'})
        result = self.safe(self.bash('append_compare_metrics_row 1993 feature/1993-fixture clean "token=' + self.secret + '" "password: ' + self.secret + '"\n' +
            'platform_timing_records=(' + shlex.quote(timing) + ')\nreviewer_loop_timing_summary_section\n' +
            'reviewer_loop_missed_finding_summary_line ' + shlex.quote(missed) + '\nworkflow_diagnostic "token=' + self.secret + '" >&2', loop=True), 0)
        metrics = (folder / 'retro-metrics-platforms.md').read_text()
        self.assertNotIn(self.secret, metrics)
        self.assertIn('| #1993 | feature |', metrics)
        self.assertIn('[REDACTED]', result.stdout)

    def test_D17_local_result_reason_and_counts(self):
        result = self.safe(self.local_entry({'result': 'needs_rerun', 'comments': 0, 'reason': 'password: ' + self.secret}), 1)
        self.assertIn('RESULT=needs_rerun', result.stdout)
        self.assertIn('COMMENT_COUNT=0', result.stdout)
        self.assertIn('REASON=password: [REDACTED]', result.stdout)

    def test_D18_real_local_strict_and_ordinary_finding_outputs(self):
        # Actual emission functions: structured functional findings retain their
        # bytes until the runner promotes PATH/CHECK/BODY into public reports.
        text = fixtures.function_text('local-ai-reviewer.sh', 'emit_strict_entry_output')
        payload = json.dumps([{'check': 'token=' + self.secret, 'path': 'token=' + self.secret,
                               'line': 4, 'body': 'password: ' + self.secret}])
        result = self.safe(self.bash('print_kv() { workflow_diagnostic_kv "$@"; }\n' + text +
                                    '\nemit_strict_entry_output STRICT applied 1 checks 0 reason applied ' + shlex.quote(payload) + '\n' +
                                    'workflow_diagnostic "token=' + self.secret + '" >&2'), 0)
        self.assertIn('STRICT_1_PATH=token=[REDACTED]', result.stdout)
        self.assertIn('STRICT_1_LINE=4', result.stdout)
        finding = self.safe(self.local_entry({'result': 'needs_fixes', 'findings': [
            {'path': 'token=' + self.secret, 'line': 4, 'message': 'password: ' + self.secret,
             'severity': 'blocking', 'clear_in_scope': True}]}), 1)
        self.assertIn('BLOCKING_1_PATH=token=[REDACTED]', finding.stdout)

    def test_D19_local_quota_empty_and_invalid(self):
        for payload, error, status, reason in [('', 'token=' + self.secret, 7, 'malformed_output'),
                                               ('invalid', 'token=' + self.secret, 7, 'malformed_output'),
                                               ('', 'quota exceeded; try again at token=' + self.secret, 7, 'quota_exhausted')]:
            with self.subTest(reason=reason, payload=payload):
                result = self.safe(self.local_entry(payload, error, status), 2)
                self.assertIn('REASON=' + reason, result.stdout)
                self.assertIn('[REDACTED]', result.stderr)
                if reason == 'quota_exhausted':
                    self.assertIn('QUOTA_RESET_AT=token=[REDACTED]', result.stdout)

    def test_D20_local_persistent_evidence_and_write_failure(self):
        evidence = self.f.root / 'evidence.json'
        pr = json.loads(self.f.pr.read_text()); pr['body'] = 'token=' + self.secret
        self.f.pr.write_text(json.dumps(pr))
        result = self.safe(self.local_entry({'result': 'clean', 'comments': 0, 'reason': 'password: ' + self.secret},
                                           LOCAL_AI_REVIEWER_EVIDENCE_FILE=str(evidence)), 0)
        data = json.loads(evidence.read_text())
        self.assertEqual(data['result'], 'clean')
        self.assertNotIn(self.secret, evidence.read_text())
        missing = self.f.root / ('token=' + self.secret) / 'missing' / 'evidence.json'
        result = self.safe(self.local_entry({'result': 'clean', 'comments': 0},
                                           LOCAL_AI_REVIEWER_EVIDENCE_FILE=str(missing)), 0)
        self.assertIn('could not write', result.stderr)

    def test_D21_local_startup_invalid_argument(self):
        result = self.safe(self.entry('local-ai-reviewer.sh', 'token=' + self.secret, 'fixture', 'repo'), 2)
        self.assertIn('ERROR: PR number', result.stderr)

    def test_D26_coderabbit_startup_and_opaque_policy(self):
        result = self.safe(self.entry('coderabbit-cli-reviewer.sh', 'token=' + self.secret, 'fixture', 'repo'), 3)
        self.assertIn('ERROR: PR number', result.stderr)
        self.f.env['CODERABBIT_CLI_RATE_LIMIT_POLICY'] = 'opaque-fabricated-policy'
        self.gh_script('case "$*" in "auth status"*) exit 0;; "pr view"*) echo \'{"baseRefName":"develop"}\';; *) exit 99;; esac\n')
        result = self.safe(self.entry('coderabbit-cli-reviewer.sh', '1993', 'fixture', 'repo'), 3)
        self.assertIn('invalid-value category', result.stderr)
        self.assertNotIn('opaque-fabricated-policy', result.stdout + result.stderr)

    def test_D27_coderabbit_real_cli_findings(self):
        self.gh_script('case "$*" in "auth status"*) exit 0;; "pr view"*) echo \'{"baseRefName":"develop"}\';; *) exit 99;; esac\n')
        command = self.f.bin / 'cr'
        payload = {'findings': [{'path': 'token=' + self.secret, 'line': 4, 'body': 'password: ' + self.secret, 'severity': 'critical'}]}
        command.write_text('#!/bin/sh\nprintf "%s\\n" ' + shlex.quote(json.dumps(payload)) + '\nprintf "token=' + self.secret + '\\n" >&2\n')
        command.chmod(0o755)
        result = self.safe(self.entry('coderabbit-cli-reviewer.sh', '1993', 'fixture', 'repo'), 1)
        self.assertIn('RESULT=needs_fixes', result.stdout)
        self.assertIn('BLOCKING_1_PATH=token=[REDACTED]', result.stdout)

    def test_D28_ci_real_check_names_and_json(self):
        payload = json.dumps({'statusCheckRollup': [{'name': 'token=' + self.secret, 'status': 'COMPLETED', 'conclusion': 'FAILURE'}]})
        self.gh_script('case "$*" in "auth status"*) exit 0;; *"headRefOid"*) echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa;; *"statusCheckRollup"*) printf "%s\\n" ' + shlex.quote(payload) + ';; *) exit 99;; esac\n')
        result = self.safe(self.entry('pr-ci-loop.sh', '1993', '--repo', 'fixture/repo', '--repo-root', str(self.f.checkout),
                                      '--poll-interval', '1', '--max-wait', '1'), 1)
        self.assertIn('RESULT=red', result.stdout)
        self.assertIn('FAILING_CHECKS=token=[REDACTED]', result.stdout)

    def test_D29_ci_real_argument_stderr(self):
        for argument in ('--bad token=' + self.secret, '--token=' + self.secret):
            with self.subTest(argument=argument):
                result = self.safe(self.entry('pr-ci-loop.sh', '1993', argument), 64)
                self.assertIn('Unknown option:', result.stderr)
                self.assertIn('[REDACTED]', result.stderr)
        # The same literal assignment reaches both channels through Ronda.
        result = self.safe(self.ronda(title='--token=' + self.secret), 2)
        self.assertIn('RONDA_CHECK_TITLE=--token=[REDACTED]', result.stdout)
        self.assertIn('--token=[REDACTED]', result.stderr)
        # Adjacent assignments retain harmless context on both channels.
        result = self.safe(self.bash('workflow_diagnostic "context --token=' + self.secret + ' --password=syntheticSecond keep=visible"\n' +
                                    'workflow_diagnostic "context --token=' + self.secret + ' --password=syntheticSecond keep=visible" >&2'), 0)
        self.assertNotIn('syntheticSecond', result.stdout + result.stderr)
        self.assertIn('--token=[REDACTED] --password=[REDACTED] keep=visible', result.stdout)
        self.assertEqual(result.stdout, result.stderr)

    def test_D30_completion_real_observation_and_header(self):
        pr = json.loads(self.f.pr.read_text()); pr['headRefName'] = 'token=' + self.secret
        self.f.pr.write_text(json.dumps(pr))
        result = self.safe(self.entry('item-completion-self-check.sh', '--issue', '1993', '--branch', 'feature/1993-fixture',
                                      '--stage', 'token=' + self.secret, '--worktree-path', str(self.f.checkout), '--repo-root', str(self.f.checkout), '--pr', '1993',
                                      '--expected-base', 'develop', '--require-clean', 'false', '--require-ci-green', 'false'), 1)
        self.assertIn('Ground-Truth Completion Verification', result.stdout)
        self.assertIn('observed=token=[REDACTED]', result.stdout)
        bad = self.safe(self.entry('item-completion-self-check.sh', '--bad token=' + self.secret), 64)
        self.assertIn('Unknown option:', bad.stderr)

    def test_D40_library_captured_github_and_bootstrap(self):
        result = self.safe(self.bash('__workflow_last_gh_stderr="token=' + self.secret + '"\nworkflow_print_captured_gh_stderr\n' +
                                    'workflow_diagnostic "password: ' + self.secret + '"'), 0)
        self.assertIn('gh: token=[REDACTED]', result.stderr)
        result = self.safe(self.run_command(['bash', '-c', 'readonly REVIEW_DOCTRINE_MAX_BYTES=' + shlex.quote('token=' + self.secret) +
                                             '; source ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh'))]), 1)
        self.assertIn('invalid readonly value', result.stderr)

    def test_D41_readiness_actual_verdict_json(self):
        # Real emit_verdict with its actual entry-local sink; no label mutation.
        text = (self.f.runtime / 'apply-readiness-labels.sh').read_text()
        sink = next(line for line in text.splitlines() if line.startswith('print_kv() {'))
        report = fixtures.function_text('apply-readiness-labels.sh', 'emit_verdict')
        result = self.safe(self.bash(sink + '\n' + report + '\n' +
            'result=refused; reason="token=' + self.secret + '"; pr_number=1993; repo=fixture/repo; label=ready-for-human-review; head_sha=' + 'a' * 40 + '; reviewer_report="password: ' + self.secret + '"; blocking_count=1; pending_count=0; failing_count=0; dry_run=true; json_output=true\nemit_verdict\nworkflow_diagnostic "token=' + self.secret + '" >&2'), 0)
        self.assertIn('RESULT=refused', result.stdout)
        data = json.loads(result.stdout.splitlines()[-1])
        self.assertEqual(data['blockingFindingCount'], 1)
        self.assertTrue(data['dryRun'])

    def test_D42_readiness_ownership_child_failure_and_args(self):
        self.gh_script('case "$*" in "auth status"*) exit 0;; esac\nprintf "token=SECRET\\n" >&2\nexit 7\n')
        result = self.safe(self.entry('apply-readiness-labels.sh', '--pr', '1993', '--repo', 'fixture/repo',
                                      '--label', 'ready-for-human-review', '--dry-run'), 2)
        self.assertIn('ownership-unverified', result.stdout)
        bad = self.safe(self.entry('apply-readiness-labels.sh', '--bad token=' + self.secret), 2)
        self.assertIn('unknown argument:', bad.stderr)


    def test_D31_haystack_real_cli_and_check_run_diagnostics(self):
        command = self.f.bin / 'haystack'
        command.write_text('#!/bin/sh\nprintf "%s\\n" ' + shlex.quote(json.dumps({'findings': [
            {'category': 'Critical', 'summary': 'password: ' + self.secret}]})) + '\nprintf "token=' + self.secret + '\\n" >&2\n')
        command.chmod(0o755)
        self.f.env['HAYSTACK_PR_STATUS_CHECK'] = '0'
        result = self.safe(self.entry('haystack-reviewer.sh', '1993', 'fixture', 'repo', '--timeout', '3'), 1)
        self.assertIn('RESULT=needs_fixes', result.stdout)
        self.assertIn('[REDACTED]', result.stderr)
        names = ['emit_haystack_check_run_result', 'emit_reviewed_head_if_known', 'capture_reviewed_head_from_check_json']
        text = '\n'.join(fixtures.function_text('haystack-reviewer.sh', n) for n in names)
        payload = json.dumps({'status': 'completed', 'conclusion': 'success', 'head_sha': 'a' * 40,
                              'details_url': 'https://example.test/?token=' + self.secret,
                              'output': {'title': 'password: ' + self.secret, 'summary': '**Findings:** 0'}})
        result = self.safe(self.bash(text + '\nfetch_haystack_check_run_json() { printf "%s\\n" ' + shlex.quote(payload) + '; }\n' +
            'emit_haystack_analysis_file_limit_skip_from_json() { return 1; }\nemit_haystack_check_run_result\nworkflow_diagnostic "token=' + self.secret + '" >&2'), 0)
        self.assertIn('CHECK_RUN_TITLE=password: [REDACTED]', result.stdout)
        self.assertIn('REVIEWED_HEAD=' + 'a' * 40, result.stdout)

    def test_D32_codex_github_real_evidence_emission_and_startup(self):
        text = '\n'.join(fixtures.function_text('codex-github-reviewer.sh', n) for n in (
            'emit_reviewed_head_if_known', 'emit_review_requested_at_if_known'))
        result = self.safe(self.bash(text + '\nCURRENT_SHA_FULL=' + 'a' * 40 + '; TRIGGER_TIME="token=' + self.secret + '"\n' +
                                    'emit_reviewed_head_if_known\nworkflow_diagnostic "password: ' + self.secret + '" >&2'), 0)
        self.assertIn('REVIEW_REQUESTED_AT=token=[REDACTED]', result.stdout)
        self.assertIn('REVIEWED_HEAD=' + 'a' * 40, result.stdout)
        bad = self.safe(self.entry('codex-github-reviewer.sh', 'token=' + self.secret, 'fixture', 'repo'), 2)
        self.assertIn('ERROR: PR number', bad.stderr)
        self.gh_script('case "$*" in "auth status"*) exit 0;; esac\nprintf "token=SECRET\\n" >&2\nexit 7\n')
        failed_read = self.safe(self.entry('codex-github-reviewer.sh', '1993', 'fixture', 'repo'), 2)
        self.assertIn('could not resolve PR', failed_read.stderr)
        self.assertIn('[REDACTED]', failed_read.stderr)

    def test_D33_actions_evidence_helper_no_reviewer_execution(self):
        text = '\n'.join(fixtures.function_text('claude-code-action-reviewer.sh', n) for n in (
            'verify_claude_code_action_run_log', 'classify_claude_code_action_log'))
        # GH fixture only; this helper never dispatches Actions or a reviewer.
        result = self.safe(self.bash(text + '\ngh() { printf "token=' + self.secret + '\\n" >&2; return 7; }\n' +
                                    'verify_claude_code_action_run_log 1 fixture repo'), 3)
        self.assertIn('VERDICT: UNAVAILABLE', result.stdout)
        self.assertIn('token=[REDACTED]', result.stderr)

    def companion_environment(self):
        context = self.f.root / 'context.json'; context.write_text('{}')
        (self.f.checkout / 'REVIEW.md').write_text('# Synthetic contract\n')
        subprocess.run(['git', 'update-ref', 'refs/remotes/origin/develop', 'HEAD'], cwd=self.f.checkout,
                       env=self.f.env, check=True, capture_output=True)
        self.f.env.update(CONTEXT_BUNDLE_PATH=str(context), BASE_BRANCH='develop', LOCAL_AI_REVIEWER_MODEL='synthetic',
                          LOCAL_AI_REVIEWER_API_BASE_URL='https://synthetic.invalid', LOCAL_AI_REVIEWER_API_KEY='fabricated-api-only')

    def test_D34_http_companion_functional_stdout_and_safe_failure(self):
        self.companion_environment()
        command = self.f.bin / 'curl'
        prefix = '#!/bin/sh\nwhile [ "$#" -gt 0 ]; do case "$1" in -o) destination=$2; shift 2;; *) shift;; esac; done\n'
        command.write_text(prefix + 'printf "%s" ' + shlex.quote(json.dumps({'error': 'password: ' + self.secret})) +
                           ' > "$destination"\nprintf "token=' + self.secret + '\\n" >&2\nprintf 500\n')
        command.chmod(0o755)
        result = self.safe(self.entry('local-http-review-command.sh'), 1)
        self.assertIn('HTTP 500', result.stderr)
        self.assertIn('[REDACTED]', result.stderr)
        raw = json.dumps({'choices': [{'message': {'content': json.dumps({'result': 'needs_fixes', 'reason': 'token=' + self.secret})}}]})
        command.write_text(prefix + 'printf "%s" ' + shlex.quote(raw) +
                           ' > "$destination"\nprintf "token=' + self.secret + '\\n" >&2\nprintf 200\n')
        result = self.entry('local-http-review-command.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(self.secret, result.stdout)  # Functional response, retained.
        self.assertNotIn(self.secret, result.stderr)
        self.assertEqual(json.loads(result.stdout)['result'], 'needs_fixes')

    def test_D35_codex_companion_preserves_response_and_status(self):
        self.companion_environment()
        command = self.f.bin / 'codex'
        payload = json.dumps({'result': 'needs_fixes', 'reason': 'token=' + self.secret})
        command.write_text('#!/bin/sh\nwhile [ "$#" -gt 0 ]; do case "$1" in -o) destination=$2; shift 2;; *) shift;; esac; done\n' +
                           'printf "%s" ' + shlex.quote(payload) + ' > "$destination"\nprintf "token=' + self.secret + '\\n" >&2\nexit 0\n')
        result = self.entry('local-codex-review-command.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), json.loads(payload))
        self.assertNotIn(self.secret, result.stderr)
        command.write_text('#!/bin/sh\nprintf "password: ' + self.secret + '\\n" >&2\nexit 7\n')
        result = self.safe(self.entry('local-codex-review-command.sh'), 7)
        self.assertEqual(result.stdout, '')
        self.assertIn('[REDACTED]', result.stderr)

    def test_D36_compatibility_aliases_delegate_to_safe_local_entry(self):
        for name in ('local-codex-reviewer.sh', 'local-http-reviewer.sh'):
            with self.subTest(entry=name):
                result = self.safe(self.entry(name, 'token=' + self.secret, 'fixture', 'repo'), 2)
                self.assertIn('ERROR: PR number', result.stderr)

    def test_D37_classifier_cli_report_and_read_error(self):
        payload = self.f.root / 'classifier.json'
        payload.write_text(json.dumps({'target_base': 'develop', 'remaining_stages': [],
                                       'checked_shared_config_ref': 'token=' + self.secret}))
        result = self.safe(self.run_command(['python3', str(self.f.runtime / 'reviewer_preflight.py'),
                                             '--input-json', str(payload)]), 0)
        self.assertEqual(json.loads(result.stdout)['outcome'], 'no-review-remaining')
        self.assertIn('[REDACTED]', result.stdout)
        missing = self.f.root / ('token=' + self.secret)
        result = self.safe(self.run_command(['python3', str(self.f.runtime / 'reviewer_preflight.py'),
                                             '--input-json', str(missing)]), 3)
        self.assertIn('configuration: configuration unreadable', result.stderr)

    def test_D38_input_builder_preserves_functional_bundle_and_safe_error(self):
        target = self.f.root / 'assembled.json'
        result = self.safe(self.run_command(['python3', str(self.f.runtime / 'reviewer_preflight_build_input.py'),
                                             '--target-base', 'develop', '--checked-shared-config-ref', 'token=' + self.secret,
                                             '--output', str(target)]), 0)
        self.assertEqual(result.stdout, '')
        self.assertIn(self.secret, target.read_text())  # Internal functional bundle.
        bad = self.f.root / ('token=' + self.secret)
        bad.write_text('malformed-json')
        result = self.safe(self.run_command(['python3', str(self.f.runtime / 'reviewer_preflight_build_input.py'),
                                             '--runner-json', str(bad), '--output', str(target)]), 1)
        self.assertIn('configuration: invalid JSON; line=1; column=1', result.stderr)

    def test_D39_config_probe_functional_payload_and_parse_diagnostics(self):
        config = self.f.root / 'synthetic-coderabbit.yaml'
        config.write_text('reviews:\n  auto_review:\n    enabled: true\n    base_branches: ["token=' + self.secret + '"]\n')
        result = self.run_command(['python3', str(self.f.runtime / 'reviewer_preflight_coderabbit.py'),
                                   '--mode', 'full-json', str(config)])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['base_branches'], ['token=' + self.secret])
        self.assertEqual(result.stderr, '')
        config.write_text('reviews:\n  auto_review: [token=' + self.secret + '\n')
        result = self.safe(self.run_command(['python3', str(self.f.runtime / 'reviewer_preflight_coderabbit.py'),
                                             '--mode', 'full-json', str(config)]), 3)
        self.assertEqual(result.stdout, '')
        self.assertIn('configuration: invalid YAML; line=3; column=1', result.stderr)
        for name in ('reviewer_preflight.py', 'reviewer_preflight_build_input.py', 'reviewer_preflight_coderabbit.py',
                     'workflow-config-resolver.py'):
            with self.subTest(parser=name):
                arguments = {
                    'reviewer_preflight.py': ['--input-json', str(config), '--bad', 'token=' + self.secret],
                    'reviewer_preflight_build_input.py': ['--output', str(config), '--bad', 'token=' + self.secret],
                    'reviewer_preflight_coderabbit.py': ['--mode', 'token=' + self.secret, str(config)],
                    'workflow-config-resolver.py': ['token=' + self.secret],
                }[name]
                result = self.safe(self.run_command(['python3', str(self.f.runtime / name), *arguments]), 2)
                self.assertIn('error:', result.stderr)

    def test_D43_effectiveness_real_report_final_renderers(self):
        source = shlex.quote(str(self.f.runtime / 'reviewer-effectiveness-report.sh'))
        for output in ('--json', ''):
            with self.subTest(output=output):
                payload = {'requested': 1, 'included': 0, 'excluded': 1, 'records': [], 'rows': [],
                           'repo': 'fixture/repo', 'reason': 'token=' + self.secret,
                           'accounting': {'requested': 1, 'included': 0, 'excluded': 1},
                           'exclusions': [{'pr': 1993, 'reason': 'password: ' + self.secret}]}
                body = 'HARNESS_MODE=1 source ' + source + '\nrer_build_report() { printf "%s\\n" ' + shlex.quote(json.dumps(payload)) + '; }\n'
                result = self.safe(self.bash(body + '\nrer_main --pr 1993 --repo fixture/repo ' + output + '\n' +
                                            'workflow_diagnostic "password: ' + self.secret + '" >&2'), 0)
                self.assertIn('[REDACTED]', result.stdout)
                if output:
                    self.assertEqual(json.loads(result.stdout)['requested'], 1)
        result = self.safe(self.entry('reviewer-effectiveness-report.sh', '--bad token=' + self.secret), 1)
        self.assertIn('unknown argument', result.stderr)

    def test_D44_ownership_compares_raw_then_sanitizes_reports(self):
        payload = {'headRefName': 'token=' + self.secret, 'headRepositoryOwner': {'login': 'fixture'},
                   'headRepository': {'name': 'repo'}, 'isCrossRepository': False}
        self.gh_script('printf "%s\\n" ' + shlex.quote(json.dumps(payload)) + '\n')
        for expected, status, verdict in [('token=' + self.secret, 0, 'owned'), ('other', 1, 'not_owned')]:
            with self.subTest(status=status):
                result = self.safe(self.entry('pr-ownership-guard.sh', '--pr', '1993', '--expected-branch', expected,
                                              '--expected-head-repo', 'fixture/repo', '--repo', 'fixture/repo'), status)
                self.assertIn('RESULT=' + verdict, result.stdout)
                self.assertIn('PR_HEAD_BRANCH=token=[REDACTED]', result.stdout)

    def test_D45_functional_parser_outputs_then_diagnostic_promotion(self):
        import runpy
        data = self.f.root / 'ready-findings.json'
        empty = self.f.root / 'local-findings.json'; empty.write_text('[]')
        data.write_text(json.dumps([{'path': 'token=' + self.secret, 'line': 4, 'message': 'password: ' + self.secret}]))
        result = self.run_command(['python3', str(self.f.runtime / 'local-ai-reviewer-findings.py'),
                                   '--local', str(empty), '--ready', str(data)])
        self.assertEqual(result.returncode, 0, result.stderr)
        normalized = json.loads(result.stdout)
        self.assertEqual(normalized['net_new_count'], 1)
        self.assertEqual(normalized['net_new'][0]['path'], 'token=' + self.secret)
        # PR-Agent code/metadata parsing is functional; never mutate review
        # content or hooks here, and never import a provider or run its entry.
        runtime = runpy.run_path(str(self.f.runtime / 'pr-agent-runtime.py'))
        functional = runtime['mask_review_code']('plain token=' + self.secret)
        self.assertIn(self.secret, functional)
        # Real Codex marker extraction likewise retains the raw token for
        # validation; only its promotion to a runner report is redacted.
        marker = fixtures.function_text('codex-github-evidence-lib.sh', 'codex_extract_reviewed_commit_field')
        result = self.safe(self.bash(marker + '\ncodex_extract_reviewed_commit_field ' +
            shlex.quote('Reviewed commit: `token=' + self.secret + '`') + '\n' +
            'printf "%s" "$MARKER_FIELD_TOKEN" >' + shlex.quote(str(self.f.root / 'marker.raw')) + '\n' +
            'workflow_diagnostic_kv MARKER_TOKEN "$MARKER_FIELD_TOKEN"\nworkflow_diagnostic "password: ' + self.secret + '" >&2'), 0)
        self.assertIn(self.secret, (self.f.root / 'marker.raw').read_text())
        self.assertIn('MARKER_TOKEN=[REDACTED]', result.stdout)

    def test_D46_optional_advisory_both_channels_and_fail_open(self):
        extension = self.f.root / 'synthetic-advisory.sh'
        extension.write_text('#!/bin/sh\nprintf "password: ' + self.secret + '\\n"\nprintf "token=' + self.secret + '\\n" >&2\nexit 7\n')
        result = self.safe(self.bash('run_project_advisory_checks 1993 ' + shlex.quote(str(extension)), loop=True), 0)
        self.assertEqual(result.stderr, '')  # Existing suppression stays intact.
        self.assertIn('password: [REDACTED]', result.stdout)

    def test_D47_audit_fake_admission_child_failure_only(self):
        budget = self.f.runtime / 'workflow-merge-budget.py'
        spy = self.f.root / 'budget-called'
        budget.write_text('import pathlib, sys\npathlib.Path(' + repr(str(spy)) + ').write_text("called")\n' +
                          'print("token=' + self.secret + '", file=sys.stderr)\nraise SystemExit(9)\n')
        result = self.safe(self.entry('run-epic-audit-trail.sh', 'apply-pr-disposition', '--input', str(self.audit_fixture()),
                                      '--pr', '1993', '--operation', 'merge', '--merge-session', 'synthetic-not-a-session'), 1)
        self.assertTrue(spy.exists())
        self.assertIn('outside admitted session', result.stderr)
        self.assertIn('token=[REDACTED]', result.stderr)
        self.assertFalse(self.f.log.exists())  # No mutation/provider was reached.

    def test_D48_reviewer_failed_label_creation_child_channels(self):
        calls = self.f.root / 'label-calls'
        source = shlex.quote(str(self.f.runtime / 'pr-review-loop.sh'))
        for shell in ('/bin/bash', '/opt/homebrew/bin/bash'):
            if not Path(shell).exists():
                continue
            for view_status, create_status in ((0, 0), (1, 0), (1, 17)):
                with self.subTest(shell=shell, view_status=view_status, create_status=create_status):
                    calls.write_text('')
                    body = '''gh() {
  case "$1:$2:$3" in
    label:view:reviewer-failed)
      printf 'view\\n' >>CALLS
      printf 'token=fabricatedChildError\\n'
      printf 'Authorization: Bearer SECRET\\n' >&2
      return VIEW_STATUS ;;
    label:create:reviewer-failed)
      printf 'create\\n' >>CALLS
      printf 'token=fabricatedChildError\\n'
      printf 'Authorization: Bearer SECRET\\nlabel-create synthetic context\\n' >&2
      return CREATE_STATUS ;;
    *) printf 'unexpected\\n' >>CALLS; return 99 ;;
  esac
}
ensure_reviewer_failed_label_exists
'''.replace('CALLS', shlex.quote(str(calls))).replace('SECRET', self.secret)
                    body = body.replace('VIEW_STATUS', str(view_status)).replace('CREATE_STATUS', str(create_status))
                    result = self.safe(self.run_command([shell, '-c', 'HARNESS_MODE=1 source ' + source + '\n' + body]), 0)
                    self.assertEqual(result.stdout, '')
                    self.assertEqual(calls.read_text().splitlines(), ['view'] if view_status == 0 else ['view', 'create'])
                    if view_status == 0:
                        self.assertEqual(result.stderr, '')
                    else:
                        self.assertIn('[REDACTED]', result.stderr)
                        self.assertIn('label-create synthetic context', result.stderr)
                        self.assertEqual('WARN: failed to create reviewer-failed label' in result.stderr,
                                         create_status != 0)

    def test_D49_pr_agent_active_check_child_stderr(self):
        """Actual PR-Agent pending-count path keeps requests/counts and masks GH stderr."""
        source = shlex.quote(str(self.f.runtime / 'pr-review-loop.sh'))
        for shell in ['/bin/bash', '/opt/homebrew/bin/bash']:
            if not Path(shell).exists():
                continue
            for state, read_status, post_status in [
                ('active', 0, 0), ('empty', 0, 0),
                ('read_failure', 17, 0), ('post_failure', 0, 17),
            ]:
                with self.subTest(shell=shell, state=state):
                    calls = self.f.root / 'pr-agent-gh-calls'
                    calls.write_text('')
                    payload = self.f.root / 'pr-agent-checks.json'
                    payload.write_text(json.dumps({'check_runs': [
                        {'id': 1, 'name': 'PR-Agent review', 'status': 'completed',
                         'conclusion': 'success', 'started_at': '2020-01-01T00:00:00Z'},
                        {'id': 2, 'name': 'PR-Agent review', 'status': 'queued',
                         'started_at': '2020-01-01T00:00:01Z'},
                        {'id': 3, 'name': 'Unrelated check', 'status': 'queued'},
                    ] if state == 'active' else []}))
                    body = r'''require_gh() { :; }
cd_workflow_repo_root() { :; }
repo_slug() { printf 'fixture/repo\n'; }
reviewer_for_branch() { printf 'codex\n'; }
loop_head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
gh() {
  printf 'Authorization: Bearer SECRET\ntoken=fabricatedChildError\nPR-Agent synthetic read context\n' >&2
  case "$*" in
    *'--jq .commit.committer.date'*) printf '2020-01-01T00:00:00Z\n' ;;
    *'commits/'*'/check-runs --paginate')
      printf 'check-runs\n' >>CALLS
      cat PAYLOAD
      return READ_STATUS ;;
    *'-X POST '*'/issues/1993/comments'*)
      printf 'post\n' >>CALLS
      printf '{"created_at":"2020-01-01T00:00:01Z","id":42}\n'
      return POST_STATUS ;;
    *'/issues/1993/comments --paginate') printf '[]\n' ;;
    *) printf 'unexpected\n' >>CALLS; return 99 ;;
  esac
}
status=0
output="$(run_pr_agent_review 1993 feature/1993-fixture 1 0)" || status=$?
printf '%s\n' "$output"
emit_prefixed_platform_output 1 "$output"
exit "$status"
'''.replace('SECRET', self.secret).replace('CALLS', shlex.quote(str(calls)))
                    body = body.replace('PAYLOAD', shlex.quote(str(payload)))
                    body = body.replace('READ_STATUS', str(read_status)).replace('POST_STATUS', str(post_status))
                    result = self.safe(self.run_command([shell, '-c', 'HARNESS_MODE=1 source ' + source + '\n' + body]),
                                       2 if post_status else 0)
                    self.assertIn('[REDACTED]', result.stderr)
                    self.assertIn('PR-Agent synthetic read context', result.stderr)
                    self.assertNotIn('unexpected', calls.read_text())
                    self.assertEqual(calls.read_text().splitlines().count('post'), 0 if state == 'active' else 1)
                    self.assertEqual(calls.read_text().splitlines().count('check-runs'), 1 if post_status else 2)
                    if state == 'active':
                        self.assertIn('PLATFORM_1_PR_AGENT_TRIGGER_SKIPPED=active_review_in_progress', result.stdout)
                        self.assertIn('PLATFORM_1_PR_AGENT_ACTIVE_CHECK_COUNT=1', result.stdout)
                        self.assertNotIn('PR_AGENT_TRIGGER_COMMENT=/review', result.stdout)
                    elif post_status:
                        self.assertIn('PLATFORM_1_REASON=pr_agent_trigger_failed', result.stdout)
                    else:
                        self.assertIn('PLATFORM_1_PR_AGENT_TRIGGER_COMMENT=/review', result.stdout)
                        self.assertNotIn('PR_AGENT_ACTIVE_CHECK_COUNT=', result.stdout)
                    self.assertIn('RESULT=' + ('escalate' if post_status else 'skipped'), result.stdout)
                    if not post_status:
                        self.assertIn('PLATFORM_1_REASON=no_review', result.stdout)


    def test_D50_pr_policy_dispatch_captured_child_channels(self):
        '''Real best-effort dispatch redacts captured errors before flattening.'''
        source = shlex.quote(str(self.f.runtime / 'pr-review-loop.sh'))
        calls = self.f.root / 'policy-dispatch-calls'
        for shell in ('/bin/bash', '/opt/homebrew/bin/bash'):
            if not Path(shell).exists():
                continue
            for state in ('stdout', 'stderr', 'mixed', 'private_key', 'empty',
                          'success', 'default_failure', 'absent', 'opt_out',
                          'missing_pr', 'sanitizer_failure'):
                with self.subTest(shell=shell, state=state):
                    calls.write_text('')
                    body = r'''repo_slug() { printf 'fixture/repo\n'; }
eval "$(declare -f workflow_command_with_safe_stderr | sed '1s/workflow_command_with_safe_stderr/original_safe_stderr/')"
workflow_command_with_safe_stderr() {
  printf 'safe-stderr\n' >>CALLS
  original_safe_stderr "$@"
}
STATE=STATE_VALUE
gh() {
  if [ "$1" = api ] && [ "$2" = repos/fixture/repo ]; then
    printf 'default\n' >>CALLS
    printf 'Authorization: Bearer SECRET\n' >&2
    if [ "$STATE" = default_failure ]; then
      printf 'token=SECRET\n'
      return 17
    fi
    printf 'main\n'
  elif [ "$1" = api ] && [ "$2" = 'repos/fixture/repo/contents/.github/workflows/pr-policy.yml?ref=main' ]; then
    printf 'contents\n' >>CALLS
    printf 'password: SECRET\n' >&2
    if [ "$STATE" = absent ]; then
      printf 'token=SECRET\n'
      return 17
    fi
    printf '.github/workflows/pr-policy.yml\n'
  elif [ "$1:$2:$3" = workflow:run:pr-policy.yml ]; then
    [ "$#" -eq 9 ] && [ "$4:$5:$6:$7:$8:$9" = '--repo:fixture/repo:--ref:main:-f:pr_number=1993' ] || return 99
    printf 'dispatch\n' >>CALLS
    case "$STATE" in
      stdout) printf 'policy synthetic context\ntoken=SECRET\n' ;;
      stderr) printf 'policy synthetic context\nAuthorization: Bearer SECRET\n' >&2 ;;
      mixed|sanitizer_failure|success)
        printf 'policy synthetic context\npassword: SECRET\n'
        printf 'Authorization: Bearer SECRET\n' >&2 ;;
      private_key)
        printf 'policy synthetic context\n-----BEGIN PRIVATE KEY-----\nSECRET\n'
        printf 'SECRET\n-----END PRIVATE KEY-----\n' >&2 ;;
      empty) : ;;
      *) return 99 ;;
    esac
    [ "$STATE" = success ] && return 0
    return 17
  else
    printf 'unexpected\n' >>CALLS
    return 99
  fi
}
if [ "$STATE" = sanitizer_failure ]; then
  workflow_redact_text() { return 2; }
fi
if [ "$STATE" = opt_out ]; then
  PR_REVIEW_LOOP_POLICY_DISPATCH=0
fi
pr=1993
[ "$STATE" != missing_pr ] || pr=''
reviewer_loop_dispatch_pr_policy "$pr" fixture/repo
status=$?
printf 'RESULT=clean\nREASON=none\nDISPATCH_RETURN=%s\n' "$status"
exit "$status"
'''.replace('STATE_VALUE', shlex.quote(state)).replace('CALLS', shlex.quote(str(calls)))
                    body = body.replace('SECRET', self.secret)
                    result = self.safe(self.run_command([shell, '-c', 'HARNESS_MODE=1 source ' + source + '\n' + body]), 0)
                    self.assertEqual(result.stderr, '')
                    self.assertIn('RESULT=clean\nREASON=none\nDISPATCH_RETURN=0\n', result.stdout)
                    events = calls.read_text().splitlines()
                    if state in ('missing_pr', 'opt_out'):
                        self.assertEqual(events, [])
                        self.assertIn('PR_POLICY_DISPATCH=skipped reason=' +
                                      ('missing_pr_number' if state == 'missing_pr' else 'opt_out'), result.stdout)
                    elif state == 'default_failure':
                        self.assertEqual(events, ['default'])
                        self.assertIn('PR_POLICY_DISPATCH=failed reason=default_branch_unresolved', result.stdout)
                    elif state == 'absent':
                        self.assertEqual(events, ['default', 'contents'])
                        self.assertIn('PR_POLICY_DISPATCH=skipped reason=pr_policy_workflow_absent', result.stdout)
                    else:
                        self.assertEqual(events, ['default', 'contents', 'safe-stderr', 'dispatch'])
                        if state == 'success':
                            self.assertEqual(result.stdout.splitlines()[0], 'PR_POLICY_DISPATCH=requested')
                            self.assertNotIn('policy synthetic context', result.stdout)
                        elif state in ('empty', 'sanitizer_failure'):
                            self.assertEqual(result.stdout.splitlines()[0],
                                             'PR_POLICY_DISPATCH=failed reason=workflow_dispatch_failed')
                        else:
                            diagnostic = result.stdout.splitlines()[0]
                            self.assertTrue(diagnostic.startswith('PR_POLICY_DISPATCH=failed reason='))
                            self.assertIn('policy synthetic context', diagnostic)
                            self.assertIn('[REDACTED]', diagnostic)


    def test_D51_settle_review_probe_actual_callsite_bash32_cardinality(self):
        '''Execute the actual production argument expansion under nounset.'''
        source = (self.f.runtime / 'pr-review-loop.sh').read_text()
        lines = [line.strip() for line in source.splitlines()
                 if line.strip().startswith('settle_review_probe="$(_bot_review_submitted_since ')]
        self.assertEqual(len(lines), 1)
        args_file = self.f.root / 'settle-probe-args'
        for shell in ('/bin/bash', '/opt/homebrew/bin/bash'):
            if not Path(shell).exists():
                continue
            for reviewers in ([], ['one reviewer'], ['one reviewer', 'second-reviewer']):
                for probe in ('0', '1', '-1'):
                    with self.subTest(shell=shell, reviewers=len(reviewers), probe=probe):
                        body = '''set -euo pipefail
settle_repo=fixture/repo
pr_number=1993
settle_head_iso=2026-10-21T00:00:00Z
settle_head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
declare -a unresolved_bot_logins=(REVIEWERS)
_bot_review_submitted_since() {
  printf '%s\\0' "$@" >ARGS_FILE
  printf '%s' PROBE
}
CALLSITE
printf 'PROBE=%s\\n' "$settle_review_probe"
'''.replace('REVIEWERS', ' '.join(shlex.quote(value) for value in reviewers))
                        body = body.replace('ARGS_FILE', shlex.quote(str(args_file)))
                        body = body.replace('PROBE\n', shlex.quote(probe) + '\n')
                        body = body.replace('CALLSITE', lines[0])
                        result = self.safe(self.run_command([shell, '-c', body]), 0)
                        self.assertEqual(result.stdout, 'PROBE=' + probe + '\n')
                        self.assertEqual(result.stderr, '')
                        actual = args_file.read_bytes().split(b'\0')
                        self.assertEqual(actual[-1], b'')
                        self.assertEqual([value.decode() for value in actual[:-1]],
                                         ['fixture/repo', '1993', '2026-10-21T00:00:00Z', 'a' * 40, *reviewers])


    def test_D52_local_evidence_redacts_complete_value_before_cap(self):
        '''Real CLI evidence never persists the credential prefix cut before @.'''
        prefix = 'EvidenceQX'
        password = prefix + 'r' * 22
        padding = 'x' * 19979 + ' '
        crossing = padding + 'https://u:' + password + '@fixture.invalid ' + 'z' * 500
        self.assertEqual(len(prefix), 10)
        self.assertEqual(len(password), 32)
        self.assertEqual(crossing.index('@'), 20022)
        self.assertIn(prefix, crossing[:20000])
        self.assertNotIn('@', crossing[:20000])
        for kind, body in [('crossing', crossing), ('plain_long', 'q' * 20123),
                           ('unicode_long', '界' * 20123), ('short', 'synthetic short context')]:
            with self.subTest(kind=kind):
                evidence = self.f.root / ('evidence-' + kind + '.json')
                pr = json.loads(self.f.pr.read_text()); pr['body'] = body
                self.f.pr.write_text(json.dumps(pr))
                result = self.safe(self.local_entry({'result': 'clean', 'comments': 0},
                                   LOCAL_AI_REVIEWER_EVIDENCE_FILE=str(evidence)), 0)
                self.assertIn('RESULT=clean', result.stdout)
                raw = evidence.read_text()
                combined = result.stdout + result.stderr + raw
                self.assertNotIn(prefix, combined)
                self.assertNotIn(password, combined)
                data = json.loads(raw)
                self.assertEqual(data['schema_version'], 'local_ai_reviewer_evidence.v1')
                self.assertEqual(data['result'], 'clean')
                self.assertEqual(data['counts'], {'comments': 0, 'blocking': 0, 'suggestions': 0})
                self.assertEqual(data['pr_number'], 1993)
                self.assertEqual(data['reviewed_head'], pr['headRefOid'])
                self.assertEqual(set(data['context_summary']),
                                 {'changed_files', 'pr_body', 'diff_name_status', 'diff_stat'})
                self.assertEqual(data['context_summary']['changed_files'], ['README.md'])
                captured = data['context_summary']['pr_body']
                self.assertEqual(len(captured), min(len(body), 20000))
                if kind == 'crossing':
                    self.assertTrue(captured.startswith(padding))
                    self.assertIn('https://[REDACTED]@', captured)
                else:
                    self.assertEqual(captured, body[:20000])
                self.assertIn('strict_spec', data)
                self.assertIn('strict_plan', data)

    def cutoff_url(self, cap):
        prefix = 'CutoffQXYZ'
        password = prefix + 'r' * 22
        body = 'x' * (cap - 21) + ' https://u:' + password + '@fixture.invalid tail'
        self.assertIn(prefix, body[:cap])
        self.assertNotIn('@', body[:cap])
        return prefix, body

    def compatible_shells(self):
        return [p for p in ('/bin/bash', '/opt/homebrew/bin/bash') if Path(p).is_file()]

    def test_D53_five_codex_display_branches_redact_before_character_cap(self):
        import re
        source = (self.f.runtime / 'codex-github-reviewer.sh').read_text()
        for display, raw in [('response_display', 'EXISTING_BOT_RESPONSE'),
                             ('BOT_RESPONSE', 'BOT_RESPONSE'),
                             ('ASYNC_BOT_RESPONSE', 'ASYNC_BOT_RESPONSE'),
                             ('ASYNC_FINAL_BOT_RESPONSE', 'ASYNC_FINAL_BOT_RESPONSE'),
                             ('ASYNC_REACTION_FINAL_BOT_RESPONSE', 'ASYNC_REACTION_FINAL_BOT_RESPONSE')]:
            # Execute the production assignment AND its actual failed-verdict
            # publisher. Fake evidence/classifier isolates each of five callers;
            # the raw classifier input is checked independently of the display.
            cap = next(line.strip() for line in source.splitlines()
                       if line.strip().startswith(display + '=$(') and '10000' in line)
            offset = source.index(cap)
            start = source.index('if ! codex_finalize_verdict ', offset)
            end = source.index('elif codex_response_is_usage_limit ', start)
            publisher = source[start:end] + 'fi\n'
            variables = sorted(set(re.findall(r'\$([A-Z][A-Z0-9_]*)', cap + publisher)))
            prefix, crossing = self.cutoff_url(10000)
            for shell in self.compatible_shells():
                for kind, body in [('url', crossing), ('pem', '-----BEGIN PRIVATE KEY-----\n' + self.secret + '\n-----END PRIVATE KEY-----'),
                                   ('long', 'h' * 100000)]:
                    with self.subTest(display=display, shell=shell, kind=kind):
                        captured = self.f.root / 'raw-classifier.txt'
                        prelude = 'set -euo pipefail\nsource ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n'
                        prelude += ''.join(name + '=\'\'\n' for name in variables)
                        prelude += raw + '=' + shlex.quote(body) + '\n' + raw + '_FULL="$' + raw + '"\n'
                        prelude += 'codex_finalize_verdict() { printf "%s" "$2" >' + shlex.quote(str(captured)) + '; return 1; }\n'
                        prelude += 'emit_reviewed_head_if_known() { printf "REVIEWED_HEAD=%s\\n" ' + 'a' * 40 + '; }\n'
                        result = self.safe(self.run_command([shell, '-c', prelude + cap + '\n' + publisher]), 1)
                        self.assertNotIn(prefix, result.stdout + result.stderr)
                        self.assertEqual(captured.read_text(), body)
                        self.assertIn('VERDICT: NEEDS_REVISION', result.stdout)
                        self.assertIn('REVIEWED_HEAD=' + 'a' * 40, result.stdout)
                        displayed = result.stdout.split('---BEGIN BOT RESPONSE---\n')[1].split('\n---END BOT RESPONSE---')[0]
                        decoded = displayed  # jq -Rrs keeps a raw string display.
                        self.assertLessEqual(len(decoded), 10000)
                        if kind == 'long':
                            self.assertEqual(decoded, body[:10000])
                        else:
                            self.assertIn('[REDACTED]', decoded)

    def test_D54_claude_dispatch_byte_preview_preserves_status_and_drains(self):
        prefix, crossing = self.cutoff_url(300)
        response = self.f.root / 'dispatch-response.txt'
        self.f.env['SYNTHETIC_DISPATCH_RESPONSE'] = str(response)
        self.gh_script('case "$*" in "auth status"*) exit 0;; *"pr view"*"baseRefName"*) echo develop;; '
                       '*"repo view"*"defaultBranchRef"*) echo main;; *"/dispatches"*) cat "$SYNTHETIC_DISPATCH_RESPONSE";; *) exit 99;; esac\n')
        for kind, body in [('url', crossing), ('pem', '-----BEGIN PRIVATE KEY-----\n' + self.secret + '\n-----END PRIVATE KEY-----'),
                           ('long', 'h' * 100000), ('unicode', '界' * 1000)]:
            with self.subTest(kind=kind):
                response.write_text(body)
                result = self.safe(self.entry('claude-code-action-reviewer.sh', '1993', 'fixture', 'repo',
                                              '--max-wait', '1', '--poll-interval', '1'), 3)
                self.assertNotIn(prefix, result.stdout + result.stderr)
                self.assertIn('DISPATCH_RESULT=no_workflow_run_id', result.stdout)
                marker = 'WARNING: dispatch response body had no integer workflow_run_id: '
                preview = result.stderr.split(marker)[1].split('\n')[0]
                if kind == 'long':
                    self.assertEqual(preview, 'h' * 300)
                elif kind == 'unicode':
                    self.assertEqual(preview, '界' * 100)
                    self.assertEqual(len(preview.encode()), 300)
                else:
                    self.assertIn('[REDACTED]', preview)

    def test_D55_three_blocking_title_consumers_redact_complete_body(self):
        names = ['reviewer_loop_print_blocking_from_unreplied_rest_comments',
                 'reviewer_loop_print_blocking_from_unresolved_bot_threads',
                 'reviewer_loop_append_late_thread_missed_findings']
        prefix, crossing = self.cutoff_url(120)
        for shell in self.compatible_shells():
            for name in names:
                for kind, body in [('fallback', crossing), ('heading', '### -----BEGIN PRIVATE KEY----- ' + self.secret + '\ncontinued\n-----END PRIVATE KEY-----'),
                                   ('long', 'h' * 100000)]:
                    with self.subTest(shell=shell, consumer=name, kind=kind):
                        row = {'body': body, 'path': 'fixture.py', 'line': 4, 'commit': 'a' * 40}
                        lines = self.f.root / 'blocking.jsonl'; lines.write_text(json.dumps(row) + '\n')
                        array = self.f.root / 'blocking.json'; array.write_text(json.dumps([row]))
                        text = fixtures.function_text('pr-review-loop.sh', name)
                        setup = 'set -euo pipefail\nHARNESS_MODE=1 source ' + shlex.quote(str(self.f.runtime / 'pr-review-loop.sh')) + '\n' + text + '\n'
                        setup += '_unreplied_rest_blocking_comment_json_lines() { cat ' + shlex.quote(str(lines)) + '; }\n'
                        setup += '_reviewer_loop_blocking_unresolved_bot_threads_json() { cat ' + shlex.quote(str(array)) + '; }\n'
                        setup += 'reviewer_loop_print_reviewed_head_from_json_lines() { printf "REVIEWED_HEAD=%s\\n" ' + 'a' * 40 + '; }\n'
                        setup += 'bot_login_for_platform() { echo fixture-bot; }; check_unresolved_threads() { echo 1; };\n'
                        setup += 'reviewer_loop_platform_result_record_json() { echo \'{"result":"needs_fixes"}\'; }; platforms=(codex);\n'
                        setup += 'platform_blocking_outputs=(); platform_result_records=(); platform_reviewed_heads=();\n'
                        setup += name + ' 1993 fixture/repo fixture-bot\n'
                        if name == names[2]:
                            setup += 'printf "%s\\n" "${platform_blocking_outputs[0]}"\n'
                        result = self.safe(self.run_command([shell, '-c', setup]), 0)
                        self.assertNotIn(prefix, result.stdout + result.stderr)
                        self.assertIn('BLOCKING_1_PATH=fixture.py', result.stdout)
                        self.assertIn('BLOCKING_1_LINE=4', result.stdout)
                        title = next(line.split('BODY=', 1)[1] for line in result.stdout.splitlines() if 'BLOCKING_1_BODY=' in line)
                        if kind == 'long':
                            self.assertEqual(title, 'h' * 120)
                        else:
                            self.assertIn('[REDACTED]', title)

    def test_D56_evidence_diff_caps_are_separate_from_functional_context(self):
        import shutil
        import sys
        prefix, crossing = self.cutoff_url(12000)
        real_git = shutil.which('git', path=self.f.env['PATH'])
        real_jq = shutil.which('jq', path=self.f.env['PATH'])
        # Reproduce Linux's per-argument ceiling on other hosts too. The real
        # jq still produces the evidence; only argv is bounded.
        fake_jq = self.f.bin / 'jq'
        fake_jq.write_text('#!' + sys.executable + '\nimport os, sys\n'
                           'if any(len(os.fsencode(arg)) >= 131072 for arg in sys.argv[1:]):\n'
                           '    sys.stderr.write("Argument list too long (synthetic Linux limit)\\n")\n'
                           '    sys.exit(126)\n'
                           'os.execv(' + repr(real_jq) + ', [' + repr(real_jq) + ', *sys.argv[1:]])\n')
        fake_jq.chmod(0o755)
        fake_git = self.f.bin / 'git'
        value = self.f.root / 'diff-output.txt'
        self.f.env['SYNTHETIC_DIFF_OUTPUT'] = str(value)
        fake_git.write_text('#!/bin/sh\ncase "$*" in "diff --name-status"*|"diff --stat"*) cat "$SYNTHETIC_DIFF_OUTPUT"; exit "${SYNTHETIC_DIFF_STATUS:-0}";; esac\nexec ' + shlex.quote(real_git) + ' "$@"\n')
        fake_git.chmod(0o755)
        subprocess.run(['git', 'update-ref', 'refs/remotes/origin/develop', 'HEAD'], cwd=self.f.checkout,
                       env=self.f.env, check=True, capture_output=True)
        for kind, body in [('crossing', crossing), ('long', 'h' * 14000), ('unicode', '界' * 14000),
                           ('large', 'h' * 220000), ('large_unicode', '界' * 75000),
                           ('large_crossing', crossing + 'z' * 220000),
                           ('short', 'M\tfixture.py'), ('failed', crossing)]:
            with self.subTest(kind=kind):
                if kind.startswith('large'):
                    self.assertGreaterEqual(len(body.encode()), 200000)
                value.write_text(body)
                self.f.env['SYNTHETIC_DIFF_STATUS'] = '7' if kind == 'failed' else '0'
                evidence = self.f.root / 'diff-evidence.json'
                context = self.f.root / 'functional-context.json'
                result = self.safe(self.local_entry({'result': 'clean', 'comments': 0}, context_capture=context,
                                                   LOCAL_AI_REVIEWER_EVIDENCE_FILE=str(evidence)), 0)
                self.assertNotIn('Argument list too long', result.stderr)
                self.assertNotIn('could not write local AI reviewer evidence', result.stderr)
                raw = evidence.read_text()
                self.assertNotIn(prefix, raw + result.stdout + result.stderr)
                data = json.loads(raw)
                functional = json.loads(context.read_text())
                self.assertEqual(data['counts'], {'comments': 0, 'blocking': 0, 'suggestions': 0})
                for field in ('diff_name_status', 'diff_stat'):
                    if kind == 'failed':
                        self.assertEqual(functional[field], '')
                        self.assertEqual(data['context_summary'][field], '')
                        continue
                    self.assertEqual(functional[field], body[:12000])
                    self.assertEqual(len(data['context_summary'][field]), min(len(body), 12000))
                    if kind in ('crossing', 'large_crossing'):
                        self.assertIn('https://[REDACTED]@', data['context_summary'][field])
                    else:
                        self.assertEqual(data['context_summary'][field], body[:12000])

    def test_D57_quota_reset_selection_uses_complete_redacted_diagnostic(self):
        for body, expected in [('quota exceeded\n-----BEGIN PRIVATE KEY-----\ntry again at ' + self.secret + '\n-----END PRIVATE KEY-----', None),
                               ('quota exceeded; try again at 2030-01-01T00:00:00Z', '2030-01-01T00:00:00Z')]:
            with self.subTest(reset=expected):
                result = self.safe(self.local_entry('', body, 7), 2)
                self.assertIn('REASON=quota_exhausted', result.stdout)
                if expected is None:
                    self.assertNotIn('QUOTA_RESET_AT=', result.stdout)
                else:
                    self.assertIn('QUOTA_RESET_AT=' + expected, result.stdout)

    def sanitizer_input_spy(self):
        import shutil
        real_python = shutil.which('python3', path=self.f.env['PATH'])
        spy = self.f.root / 'sanitizer-inputs.jsonl'
        self.f.env['SYNTHETIC_SPY'] = str(spy)
        wrapper = self.f.bin / 'python3'
        wrapper.write_text('#!' + real_python + '\nimport os,sys,subprocess,json,hashlib\n'
                           'if len(sys.argv)>2 and sys.argv[1].endswith("workflow-config-resolver.py") and sys.argv[2:] == ["redact-text"]:\n'
                           ' raw=sys.stdin.buffer.read()\n'
                           ' with open(os.environ["SYNTHETIC_SPY"],"a") as f:f.write(json.dumps({"length":len(raw),"sha256":hashlib.sha256(raw).hexdigest()})+"\\n")\n'
                           ' p=subprocess.run([' + repr(real_python) + ']+sys.argv[1:],input=raw);sys.exit(p.returncode)\n'
                           'os.execv(' + repr(real_python) + ',[' + repr(real_python) + ']+sys.argv[1:])\n')
        wrapper.chmod(0o755)
        return spy

    def assert_first_sanitizer_input(self, spy, source):
        import hashlib
        rows = spy.read_text().splitlines() if spy.exists() else []
        self.assertTrue(rows, 'complete diagnostic sanitizer was not reached')
        self.assertEqual(json.loads(rows[0]), {'length': len(source.encode()),
                                              'sha256': hashlib.sha256(source.encode()).hexdigest()})

    def test_D58_ownership_first_line_redacts_full_error_before_selection(self):
        # The complete-input spy is intentional: legacy EOF-PEM redaction could
        # already protect a retained first line, but selection must not precede
        # sanitization. The public entrypoint and real formatter still execute.
        error = self.f.root / 'ownership.err'
        source = 'first harmless line\n-----BEGIN PRIVATE KEY-----\n' + self.secret + '\n-----END PRIVATE KEY-----'
        error.write_text(source)
        self.f.env['SYNTHETIC_ERROR'] = str(error)
        self.gh_script('cat "$SYNTHETIC_ERROR" >&2\nexit 7\n')
        spy = self.sanitizer_input_spy()
        result = self.safe(self.entry('pr-ownership-guard.sh', '--pr', '1993', '--repo-root', str(self.f.checkout),
                                      '--expected-branch', 'feature/1993-fixture', '--repo', 'fixture/repo'), 3)
        self.assertIn('RESULT=pr_unresolved', result.stdout)
        self.assertIn('first harmless line', result.stderr)
        self.assert_first_sanitizer_input(spy, source)

    def test_D59_router_both_error_preview_classes_and_long_input(self):
        spy = self.sanitizer_input_spy()
        for category, first in [('local_config_error', 'no default remote repository has been set'),
                                ('github_unavailable', 'HTTP 500 internal server error')]:
            for kind, error in [('url', first + ' https://u:' + self.secret + '@fixture.invalid\nsecond line'),
                                ('pem', first + ' -----BEGIN PRIVATE KEY----- ' + self.secret + '\ncontinued\n-----END PRIVATE KEY-----'),
                                ('long', first + ' ' + 'h' * 100000)]:
                with self.subTest(category=category, kind=kind):
                    spy.write_text('')
                    self.gh_script('case "$*" in "auth status"*) exit 0;; *) printf "%s\\n" ' + shlex.quote(error) + ' >&2; exit 1;; esac\n')
                    result = self.safe(self.entry('run-work-router.sh', '1993', '--json'), 0)
                    self.assert_first_sanitizer_input(spy, error)
                    self.assertIn('MODE=tracker_unavailable', result.stdout)
                    self.assertIn('gh reported:', result.stdout)
                    self.assertIn('default repository is configured' if category == 'local_config_error'
                                  else 'retry shortly', result.stdout)
                    if kind == 'long':
                        self.assertIn('h' * 100000, result.stdout)
                    else:
                        self.assertIn('[REDACTED]', result.stdout)

    def test_D60_batch_merge_error_and_conflict_previews_are_diagnostic_only(self):
        # Real cmd_merge, fixed valid metadata and explicitly fake budget/git:
        # no remote merge/session or real checkout mutation is performed.
        spy = self.sanitizer_input_spy()
        command = fixtures.function_text('batch-merge.sh', 'cmd_merge')
        pr = json.loads(self.f.pr.read_text()); pr.update(headRefOid='a' * 40, labels=[])
        for stage in ('failed_merge', 'prior_conflict'):
            for kind, error in [('url', 'operation https://u:' + self.secret + '@fixture.invalid failed\n' + 'h\n' * 10),
                                ('pem', '-----BEGIN PRIVATE KEY-----\n' + self.secret + '\n' + 'h\n' * 8 + '-----END PRIVATE KEY-----'),
                                ('long', 'h' * 100000 + '\nsecond\nthird\nfourth\nfifth\nsixth')]:
                with self.subTest(stage=stage, kind=kind):
                    spy.write_text('')
                    content = self.f.root / 'merge-error.txt'; content.write_text(error)
                    if stage == 'prior_conflict':
                        # A recognized assignment in the filename is diagnostic
                        # source text, while the structured path API is untouched.
                        content.write_text('UU ' + ('h' * 100000 if kind == 'long' else
                                           'https://u:' + self.secret + '@fixture.invalid' if kind == 'url' else
                                           '-----BEGIN PRIVATE KEY----- ' + self.secret + '\ncontinued\n-----END PRIVATE KEY-----') + '\n')
                    setup = 'set -euo pipefail\n' + command + '\nTARGET_BASE=develop; merge_session=synthetic;\n'
                    setup += 'require_gh() { :; }; repo_slug() { echo fixture/repo; }; gh() { printf "%s" ' + shlex.quote(json.dumps(pr)) + '; };\n'
                    setup += 'workflow_merge_budget_helper() { echo \'{"stepId":"synthetic","nestedExecutionAuthorized":true}\'; };\n'
                    setup += 'git() { case "$*" in "status --porcelain") '
                    setup += ('cat ' + shlex.quote(str(content)) if stage == 'prior_conflict' else ':') + ';; '
                    setup += '"rev-parse "*) printf "%s\\n" ' + 'a' * 40 + ';; "merge --no-ff"*) cat ' + shlex.quote(str(content)) + '; return 7;; '
                    setup += '"checkout "*|"pull "*|"fetch "*|"merge --abort"|"diff "*) return 0;; *) return 99;; esac; };\n'
                    setup += 'cmd_merge --merge-session synthetic --pr 1993 --expected-head-sha ' + 'a' * 40
                    result = self.safe(self.bash(setup), 2)
                    expected_input = content.read_text().rstrip('\n')
                    if stage == 'prior_conflict':
                        expected_input = '\n'.join(line for line in expected_input.splitlines() if line.startswith(('UU', 'AA', 'DD', 'AU', 'UA', 'DU', 'UD')))
                    self.assert_first_sanitizer_input(spy, expected_input)
                    self.assertIn('MERGE_RESULT=failed', result.stdout)
                    self.assertIn('[REDACTED]' if kind != 'long' else 'h' * 100000, result.stdout)
                    if stage == 'failed_merge' and kind == 'long':
                        self.assertNotIn('sixth', result.stdout)


    def test_D61_capture_utility_boundaries_exact_status_and_argv(self):
        # U16-U19: run the actual common command boundary in both errexit
        # contexts; the child stdout/argv stay functional and stderr is opaque.
        for shell in self.compatible_shells():
            for case, expected in [('U16_mktemp', 2), ('U17_open', 1),
                                   ('U18_read', 2), ('U19_cleanup_conditional', 17),
                                   ('U19_cleanup_bare', 23), ('success', 0)]:
                with self.subTest(route=case, shell=shell):
                    capture = self.f.root / 'capture.err'; capture.write_text('')
                    invoked = self.f.root / 'capture-child.argv'
                    if invoked.exists(): invoked.unlink()
                    setup = 'set -euo pipefail\nsource ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n'
                    setup += 'child() { printf "%s\\0" "$@" >' + shlex.quote(str(invoked)) + '; printf "FUNCTIONAL=ok\\n"; printf "token=' + self.secret + '\\n" >&2; return ' + ('0' if case == 'success' else '17') + '; };\n'
                    if case == 'U16_mktemp':
                        setup += 'mktemp() { printf "token=' + self.secret + '\\n" >&2; return 29; };\n'
                    elif case == 'U17_open':
                        setup += 'mktemp() { printf "%s\\n" ' + shlex.quote(str(self.f.root / ('token=' + self.secret) / 'missing' / 'capture')) + '; };\n'
                    else:
                        setup += 'mktemp() { printf "%s\\n" ' + shlex.quote(str(capture)) + '; };\n'
                    if case == 'U18_read':
                        setup += 'eval "$(declare -f workflow_redact_file | sed \'1s/workflow_redact_file/actual_redact_file/\')"\n'
                        setup += 'workflow_redact_file() { command rm -f "$1"; actual_redact_file "$@"; };\n'
                    if case.startswith('U19_'):
                        setup += 'rm() { printf "token=' + self.secret + '\\n" >&2; return 23; };\n'
                    if case == 'U19_cleanup_bare':
                        setup += 'workflow_command_with_safe_stderr child first "two words"\n'
                    else:
                        setup += 'status=0; workflow_command_with_safe_stderr child first "two words" || status=$?; exit "$status"\n'
                    result = self.safe(self.run_command([shell, '-c', setup]), expected)
                    if case in ('U16_mktemp', 'U17_open'):
                        self.assertFalse(invoked.exists())
                        self.assertEqual(result.stdout, '')
                        self.assertIn('diagnostic capture failed', result.stderr)
                    else:
                        self.assertEqual(invoked.read_bytes().split(b'\0'), [b'first', b'two words', b''])
                        self.assertEqual(result.stdout, 'FUNCTIONAL=ok\n')
                    if case.startswith('U19_'):
                        self.assertIn('diagnostic cleanup failed', result.stderr)

    def test_D62_actual_diagnostic_file_callsite_matrix(self):
        import re
        # U25/U28-U41: execute each ORIGINAL production statement (including
        # its original failure guard), not a reimplementation of its pipeline.
        # The surrounding dispatch/classification is independently retained in
        # D20/D54/D58 and the full provider/loop suites; this isolates file-open.
        rows = [('U25', 'pr-review-loop.sh', '_payload_tmp', 0, 2),
                ('U28', 'claude-code-action-reviewer.sh', 'DISPATCH_RESPONSE', 0, 0),
                ('U29', 'haystack-reviewer.sh', 'TRIAGE_STDERR', 0, 1),
                ('U30', 'haystack-reviewer.sh', 'PR_STATUS_STDERR', 0, 1),
                ('U31', 'local-http-review-command.sh', 'diff_err', 0, 1),
                ('U32', 'local-http-review-command.sh', 'body_file', 0, 1),
                ('U33', 'local-http-review-command.sh', 'body_file', 1, 1),
                ('U34', 'pr-ownership-guard.sh', 'SCRATCH_DIR/stderr', 0, 0),
                ('U35', 'pr-review-loop.sh', 'haystack_stderr_file', 0, 1),
                ('U36', 'pr-review-loop.sh', 'coderabbit_cli_stderr_file', 0, 1),
                ('U37', 'pr-review-loop.sh', 'local_ai_stderr_file', 0, 1),
                ('U38', 'resolve-reviewer-availability.sh', 'work_dir/config.err', 0, 1),
                ('U39', 'reviewer-preflight.sh', 'work_dir/early-classify.err', 0, 1),
                ('U40', 'reviewer-preflight.sh', 'work_dir/preflight.err', 0, 1),
                ('U41', 'reviewer-preflight.sh', 'work_dir/json-report.out', 0, 1)]
        for route, name, token, ordinal, failure in rows:
            source = (self.f.runtime / name).read_text().splitlines()
            matches = [line.strip() for line in source if re.search(r'workflow_redact_(?:text|json|file)\s+<?\"\$' + re.escape(token) + r'\"', line)]
            statement = matches[ordinal]
            for missing in (False, True):
                with self.subTest(route=route, missing=missing):
                    folder = self.f.root / ('token=' + self.secret); folder.mkdir(exist_ok=True)
                    variable, _, tail = token.partition('/')
                    target = folder / (tail or 'diagnostic.txt')
                    if target.exists(): target.unlink()
                    if not missing:
                        target.write_text(json.dumps({'reason': 'token=' + self.secret, 'count': 4}) if route in ('U25', 'U41') else 'token=' + self.secret + '\nsecond\n\n')
                    setup = 'set -euo pipefail\nsource ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n'
                    setup += variable + '=' + shlex.quote(str(folder if tail else target)) + '\n'
                    setup += 'config_rc=2; fail() { workflow_diagnostic "ERROR: $*" >&2; exit 2; };\n'
                    # return in U25 belongs to its actual containing function.
                    setup += 'actual_boundary() {\n' + statement + '\n'
                    if route in ('U28', 'U34'):
                        field = 'dispatch_diagnostic' if route == 'U28' else 'GH_ERROR'
                        setup += 'workflow_diagnostic "$' + field + '" >&2\n'
                    if route in ('U32', 'U33'):
                        setup += next(line.strip() for line in source if "printf '%.2000s" in line) + '\n'
                    if route == 'U25': setup += 'printf "%s\\n" "$payload"\n'
                    setup += '}\nactual_boundary\n'
                    result = self.safe(self.run_command(['bash', '-c', setup]), failure if missing else (2 if route == 'U38' else 0))
                    if missing and route not in ('U28', 'U34'):
                        self.assertEqual(result.stdout, '')
                    if not missing:
                        self.assertIn('[REDACTED]', result.stdout + result.stderr)
                        if route == 'U41': self.assertEqual(json.loads(result.stdout)['count'], 4)

    def test_D63_file_boundary_stream_and_errexit_contract(self):
        for shell in self.compatible_shells():
            for mode, expected in [('text', 0), ('json', 0), ('missing', 1), ('sanitizer', 2)]:
                with self.subTest(shell=shell, mode=mode):
                    path = self.f.root / ('token=' + self.secret)
                    if path.exists(): path.unlink()
                    raw = 'first\n\nsecond\n\n' if mode != 'json' else '{"count":4,"reason":"token=' + self.secret + '"}'
                    if mode != 'missing': path.write_text(raw)
                    setup = 'set -euo pipefail\nsource ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n'
                    if mode == 'sanitizer': setup += '_workflow_redact_stdin() { printf "token=' + self.secret + '\\n" >&2; return 2; };\n'
                    setup += 'workflow_redact_file ' + shlex.quote(str(path)) + (' --json' if mode == 'json' else '') + '\n'
                    result = self.safe(self.run_command([shell, '-c', setup]), expected)
                    if mode == 'text': self.assertEqual(result.stdout, 'first\n\nsecond\n')
                    if mode == 'json': self.assertEqual(json.loads(result.stdout)['count'], 4)
                    if expected: self.assertEqual(result.stdout, '')


    def test_D64_writer_staging_and_raw_capture_actual_routes(self):
        # U20-U23: actual local-AI CLI, not a mirrored evidence writer.
        for writer_shell in self.compatible_shells():
            self._entry_shell = writer_shell
            for route, expected in [('U20', 0), ('U21', 0), ('U22', 1), ('writer_sanitizer', 2), ('U23', 23), ('writer_success', 0)]:
                with self.subTest(route=route, shell=writer_shell):
                    record = self.f.root / 'writer-capture-path'
                    evidence = self.f.root / 'class-evidence.json'
                    if evidence.exists(): evidence.unlink()
                    bash_env = self.f.root / 'class-utility-functions.sh'
                    body = 'mktemp() { case " ${FUNCNAME[*]} " in *write_evidence_file*) '
                    if route == 'U20':
                        body += 'printf "token=' + self.secret + '\\n" >&2; return 17; '
                    elif route == 'U21':
                        body += 'printf "%s\\n" ' + shlex.quote(str(self.f.root / ('token=' + self.secret) / 'absent-parent' / 'capture')) + '; '
                    else:
                        body += 'local path; path="$(command mktemp "$@")"; printf "%s" "$path" >' + shlex.quote(str(record)) + '; printf "%s\\n" "$path"; '
                    body += ';; *) command mktemp "$@";; esac; }\n'
                    if route == 'U23':
                        body += 'rm() { if [ "$#" = 2 ] && [ "$1" = -f ] && [ "$2" = "$(command cat ' + shlex.quote(str(record)) + ' 2>/dev/null)" ]; then printf "token=' + self.secret + '\\n" >&2; return 23; fi; command rm "$@"; }\n'
                    if route in ('U22', 'writer_sanitizer'):
                        body += 'jq() { case " ${FUNCNAME[*]} " in *write_evidence_file*) if [ "${1:-}" = -n ] && [ -n "${evidence_error:-}" ]; then '
                        if route == 'U22': body += 'command rm -f "$evidence_error"; '
                        body += 'printf "token=' + self.secret + '\n" >&2; return 7; fi;; esac; command jq "$@"; };\n'
                    if route == 'writer_sanitizer':
                        body += 'python3() { case " ${FUNCNAME[*]}:$* " in *write_evidence_file*redact-text*) case " $* " in *" --json "*) command python3 "$@"; return $?;; esac; printf "token=' + self.secret + '\n" >&2; return 17;; esac; command python3 "$@"; };\n'
                    bash_env.write_text(body)
                    self.f.env['BASH_ENV'] = str(bash_env)
                    result = self.safe(self.local_entry({'result': 'clean', 'comments': 0}, LOCAL_AI_REVIEWER_EVIDENCE_FILE=str(evidence)), expected)
                    self.f.env.pop('BASH_ENV', None)
                    if route == 'U20':
                        self.assertIn('could not capture evidence diagnostics', result.stderr)
                        self.assertIn('RESULT=clean', result.stdout)
                        self.assertFalse(evidence.exists())
                    elif route in ('U21', 'U22', 'writer_sanitizer'):
                        # Preserve the actual writer's original open-failure best-effort
                        # contract, independently of sanitizer and cleanup failures.
                        self.assertIn('REVIEWED_HEAD=' + json.loads(self.f.pr.read_text())['headRefOid'], result.stdout)
                        self.assertIn('BASE_BRANCH=develop', result.stdout)
                        if route in ('U22', 'writer_sanitizer'): self.assertNotIn('RESULT=clean', result.stdout)
                        else: self.assertIn('RESULT=clean', result.stdout)
                        if route == 'U21': self.assertFalse(evidence.exists())
                        if route == 'U22':
                            self.assertIn('diagnostic sanitization failed', result.stderr)
                            self.assertNotIn(record.read_text(), result.stderr)
                        if route == 'U21': self.assertIn('could not write local AI reviewer evidence', result.stderr)
                    else:
                        data = json.loads(evidence.read_text())
                        self.assertEqual(data['counts'], {'comments': 0, 'blocking': 0, 'suggestions': 0})
                        self.assertEqual(data['schema_version'], 'local_ai_reviewer_evidence.v1')
                        if route == 'U23': self.assertIn('diagnostic cleanup failed', result.stderr)
                        else: self.assertIn('RESULT=clean', result.stdout)
        del self._entry_shell
        # U24: actual changed staging command, exact mode/path argv, plus success.
        line = next(line.strip() for line in (self.f.runtime / 'reviewer-preflight.sh').read_text().splitlines() if 'mkdir -m 700 "$shared_dir"' in line)
        for fail in (False, True):
            with self.subTest(route='U24', fail=fail):
                path = self.f.root / ('token=' + self.secret) / ('staging-fail' if fail else 'staging-ok')
                path.parent.mkdir(exist_ok=True)
                args = self.f.root / 'mkdir-args'
                body = 'shared_dir=' + shlex.quote(str(path)) + '\nmkdir() { printf "%s\\n" "$@" >' + shlex.quote(str(args)) + '; '
                body += ('printf "token=' + self.secret + '\\n" >&2; return 19;' if fail else 'command mkdir "$@";') + ' };\n' + line
                result = self.safe(self.bash(body), 19 if fail else 0)
                self.assertEqual(result.stdout, '')
                self.assertEqual(args.read_text().splitlines(), ['-m', '700', str(path)])
                if not fail: self.assertEqual(path.stat().st_mode & 0o777, 0o700)
        # U26: retain raw CodeRabbit classifier detail before report promotion.
        source = (self.f.runtime / 'resolve-reviewer-availability.sh').read_text().splitlines()
        line = next(line.strip() for line in source if line.strip().startswith('detail="$(') and '"$work_dir/probe.err"' in line)
        for fail in (False, True):
            with self.subTest(route='U26', fail=fail):
                args = self.f.root / 'cat-args'
                body = 'work_dir=' + shlex.quote(str(self.f.root)) + '\ncat() { printf "%s\\n" "$@" >' + shlex.quote(str(args)) + '; '
                body += ('printf "token=' + self.secret + '\\n" >&2; return 21;' if fail else 'printf "configuration: invalid YAML; key=review\\n";') + ' };\n'
                body += line + '\nprintf "%s" "$detail"\n'
                result = self.safe(self.bash(body), 21 if fail else 0)
                self.assertEqual(args.read_text().splitlines(), [str(self.f.root / 'probe.err')])
                self.assertEqual(result.stdout, '' if fail else 'configuration: invalid YAML; key=review')
        # U27: full actual loop classifier+publisher, raw class before redaction.
        for fail in (False, True):
            with self.subTest(route='U27', fail=fail):
                error = self.f.root / 'polling-error'; error.write_text('HTTP 403 forbidden token=' + self.secret)
                body = 'cat() { ' + ('printf "token=' + self.secret + '\\n" >&2; return 21;' if fail else 'command cat "$@";') + ' };\n'
                body += 'reviewer_loop_gh_read_denied ' + shlex.quote(str(error))
                result = self.safe(self.bash(body, loop=True), 21 if fail else 0)
                if fail: self.assertEqual(result.stdout, '')
                else: self.assertIn('HTTP 403 forbidden token=[REDACTED]', result.stdout)


    def test_D65_redactor_argument_expansion_is_inside_stderr_boundary(self):
        # U42: actual newly-added redactor calls a legacy path helper; its
        # command substitution runs before Python's own redirection is applied.
        for shell in self.compatible_shells():
            for fail in (False, True):
                with self.subTest(route='U42', shell=shell, fail=fail):
                    resolver = self.f.runtime / 'workflow-config-resolver.py'
                    body = 'source ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n'
                    body += 'workflow_config_resolver_script() { printf "token=' + self.secret + '\\n" >&2; '
                    body += ('printf "%s\\n" /synthetic/missing-resolver; return 17;' if fail else 'printf "%s\\n" ' + shlex.quote(str(resolver)) + ';') + ' };\n'
                    body += 'printf "FUNCTIONAL=ok\\n" | workflow_redact_text\n'
                    result = self.safe(self.run_command([shell, '-c', body]), 2 if fail else 0)
                    self.assertEqual(result.stdout, '' if fail else 'FUNCTIONAL=ok\n')
                    self.assertEqual(result.stderr, 'ERROR: diagnostic sanitization failed\n' if fail else '')

    def test_D66_root_utility_boundaries_preserve_cwd_status_and_argv(self):
        rows = [('U02', 'apply-readiness-labels.sh', 'repo_root', 19),
                ('U03', 'discover-workflow-state.sh', 'repo_root', 2),
                ('U04', 'post-merge-cleanup.sh', 'repo_root', 2),
                ('U05', 'workflow-batch-lanes.sh', 'repo_root', 1),
                ('U06', 'workflow-batch-plan.sh', 'repo_root', 1),
                ('U07', 'workflow-next-action.sh', 'repo_root', 2),
                ('U08', 'post-merge-cleanup.sh', 'dir', 19),
                ('U09', 'post-merge-cleanup.sh', 'source_caller_worktree_root', 0)]
        for route, name, variable, failed_status in rows:
            lines = (self.f.runtime / name).read_text().splitlines()
            if route == 'U02': statement = next(x.strip() for x in lines if x.startswith('cd -- "$repo_root"'))
            elif route == 'U08': statement = next(x.strip() for x in fixtures.function_text(name, 'private_source_common_dir').splitlines() if '(CDPATH=' in x and 'cd -- "$dir"' in x)
            else: statement = next(x.strip() for x in lines if x.strip().startswith(variable + '=') and 'cd -- "$' + variable + '"' in x)
            for shell in self.compatible_shells():
                for failure in ('success', 'cd', 'pwd'):
                    if route == 'U02' and failure == 'pwd': continue
                    fail = failure != 'success'
                    with self.subTest(route=route, shell=shell, failure=failure):
                        args = self.f.root / 'cd-argv'
                        path = self.f.root / (('token=' + self.secret) if fail else 'safe-checkout')
                        path.mkdir(exist_ok=True)
                        body = 'set -euo pipefail\n' + variable + '=' + shlex.quote(str(path)) + '\n'
                        body += 'cd() { printf "%s\\0" "$@" >' + shlex.quote(str(args)) + '; '
                        body += ('printf "token=' + self.secret + '\\n" >&2; return 19;' if failure == 'cd' else 'builtin cd "$@";') + ' };\n'
                        if failure == 'pwd': body += 'pwd() { printf "token=' + self.secret + '\\n" >&2; return 29; };\n'
                        body += 'actual_boundary() {\n' + statement + '\n};\nactual_boundary\n'
                        body += 'printf "ROOT=%s\\nCWD=%s\\n" "$' + variable + '" "$PWD"\n'
                        result = self.safe(self.run_command([shell, '-c', body]), (29 if route == 'U08' and failure == 'pwd' else failed_status) if fail else 0)
                        self.assertEqual(args.read_bytes().split(b'\0'), [b'--', str(path).encode(), b''])
                        if fail:
                            if route == 'U09': self.assertEqual(result.stdout, 'ROOT=\nCWD=' + str(self.f.checkout) + '\n')
                            else: self.assertEqual(result.stdout, '')
                            self.assertEqual(result.stderr, 'configuration: checkout access error\n')
                        else:
                            self.assertIn('ROOT=' + str(path), result.stdout)
                            # Only the original bare cd changes the caller CWD.
                            self.assertIn('CWD=' + str(path if route == 'U02' else self.f.checkout), result.stdout)
                            self.assertEqual(result.stderr, '')
        # U01 informational diagnostic promotion uses the exact production line.
        line = next(x.strip() for x in (self.f.runtime / 'post-merge-cleanup.sh').read_text().splitlines() if 'Using the calling working tree' in x)
        result = self.safe(self.bash('source_caller_worktree_root="token=' + self.secret + '"\n' + line), 0)
        self.assertIn('Using the calling working tree', result.stdout)
        self.assertIn('token=[REDACTED]', result.stdout)
        valid = self.safe(self.bash('source_caller_worktree_root=/synthetic/checkout\n' + line), 0)
        self.assertEqual(valid.stdout, "Using the calling working tree '/synthetic/checkout' as --repo-root (no --repo-root was passed).\n")

    def test_D67_bootstrap_plain_source_preserves_initializer_errexit(self):
        # U10-U15: execute each actual script prefix up through its real source
        # statement in an isolated tooling directory; no provider body runs.
        names = ['claude-code-action-reviewer.sh', 'codex-github-reviewer.sh',
                 'local-codex-review-command.sh', 'local-http-review-command.sh',
                 'pr-ownership-guard.sh', 'resolve-reviewer-availability.sh']
        for index, name in enumerate(names, 10):
            lines = (self.f.runtime / name).read_text().splitlines()
            end = next(i for i, line in enumerate(lines) if line.startswith('source ') and '/workflow-lib.sh"' in line)
            prefix = '\n'.join(lines[:end + 1]) + '\nprintf "IMPORTED=%s\\n" "$BOOTSTRAP_IMPORTED"\n'
            for shell in self.compatible_shells():
                for mode, expected in [('success', 0), ('canonical', 19), ('missing', 1), ('initializer', 17), ('errexit', 1)]:
                    with self.subTest(route='U' + str(index), shell=shell, mode=mode):
                        folder = self.f.root / ('bootstrap-' + str(index)); folder.mkdir(exist_ok=True)
                        script = folder / name; script.write_text(prefix)
                        library = folder / 'workflow-lib.sh'
                        if library.exists(): library.unlink()
                        if mode != 'missing':
                            library.write_text('BOOTSTRAP_IMPORTED=present\n' if mode == 'success' else 'printf "token=' + self.secret + '\\n" >&2\n' + ('return 17\n' if mode == 'initializer' else 'false\nprintf "SHOULD_NOT_RUN\\n"\n'))
                        init = self.f.root / 'bootstrap-env'
                        init.write_text('cd() { printf "token=' + self.secret + '\\n" >&2; return 19; }\n' if mode == 'canonical' else ':\n')
                        self.f.env['BASH_ENV'] = str(init)
                        try: result = self.safe(self.run_command([shell, str(script)]), expected)
                        finally: self.f.env.pop('BASH_ENV', None)
                        self.assertEqual(result.stdout, 'IMPORTED=present\n' if mode == 'success' else '')
                        self.assertEqual(result.stderr, 'configuration: tooling initialization error\n' if mode == 'canonical' else '')

    def test_D68_resolver_argument_helper_matrix_and_real_policy_diagnostics(self):
        # U43-U53: exact eleven new/modified resolver invocations, including
        # their original command continuations and return/exit guards.
        counts = {'coderabbit-cli-reviewer.sh': 2, 'discover-workflow-state.sh': 1,
                  'pr-review-loop.sh': 1, 'workflow-lib.sh': 7}
        route = 43
        for name, expected_count in counts.items():
            functions = {'coderabbit-cli-reviewer.sh': ['rate_limit_policy_from_file', 'rate_limit_policy_from_config'],
                         'pr-review-loop.sh': ['resolve_local_review_override_root'],
                         'workflow-lib.sh': ['workflow_local_config_file', 'workflow_product_repo_name_for_github_slug',
                                             'workflow_hub_root_for_ci_policy', 'workflow_merge_ci_policy_into_json',
                                             'workflow_config_review_local_list_if_declared', 'workflow_config_review_list']}
            source = ('\n'.join(fixtures.function_text(name, function) for function in functions[name]).splitlines()
                      if name in functions else (self.f.runtime / name).read_text().splitlines())
            starts = [i for i, line in enumerate(source) if '$(workflow_config_resolver_script' in line]
            self.assertEqual(len(starts), expected_count)
            for start in starts:
                end = start
                while source[end].rstrip().endswith('\\'): end += 1
                if '|| status=$?' in source[end]: end += 1
                statement = '\n'.join(source[start:end + 1]).strip()
                for shell in self.compatible_shells():
                    for fail in (False, True):
                        with self.subTest(route='U' + str(route), shell=shell, fail=fail):
                            args = self.f.root / 'resolver-argv'
                            resolver = self.f.runtime / 'workflow-config-resolver.py'
                            body = 'set -euo pipefail\nsource ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n'
                            body += 'root=' + shlex.quote(str(self.f.checkout)) + '; repo_root="$root"; initiating_root="$root"; config_file="$root/.ai-dev-workflow.yaml"; policy_root="$root"; review_root="$root"; phase=on_draft; key=runner; status=0; args=(review-list --repo-root "$root" --phase on_draft --key runner)\n'
                            body += 'workflow_effective_config_file() { printf "%s\\n" "$config_file"; }; workflow_local_config_root() { printf "%s\\n" "$root"; };\n'
                            body += 'workflow_config_resolver_script() { printf "token=' + self.secret + '\\n" >&2; printf "%s\\n" ' + shlex.quote(str(resolver)) + '; };\n'
                            body += 'python3() { if [ "${2:-}" = redact-text ]; then command python3 "$@"; return $?; fi; printf "%s\\0" "$@" >' + shlex.quote(str(args)) + '; '
                            body += ('printf "configuration: invalid YAML; line=1; column=1\\n" >&2; return 17;' if fail else 'printf "FUNCTIONAL=ok\\n";') + ' };\n'
                            body += 'actual_boundary() {\n' + statement + '\n'
                            if statement.startswith('configured_repos='): body += 'printf "%s\\n" "$configured_repos"\n'
                            elif statement.startswith('selected_file='): body += 'printf "%s\\n" "$selected_file"\n'
                            elif statement.startswith('mode_json='): body += 'printf "%s\\n" "$mode_json"\n'
                            elif statement.startswith('names='): body += 'printf "%s\\n" "$names"\n'
                            body += '}\nactual_boundary ' + shlex.quote(str(self.f.private)) + '\n'
                            guarded = '|| return 2' in statement or '|| exit 2' in statement
                            result = self.safe(self.run_command([shell, '-c', body]), (2 if guarded else 17) if fail else 0)
                            captured = args.read_bytes().split(b'\0')
                            self.assertEqual(captured[0], str(resolver).encode())
                            self.assertEqual(captured[-1], b'')
                            expected_tail = {
                                43: ['coderabbit-policy', '--file', str(self.f.private)],
                                44: ['coderabbit-policy', '--repo-root', str(self.f.checkout), '--shared-file', str(self.f.checkout / '.ai-dev-workflow.yaml')],
                                45: ['list-product-repos', '--repo-root', str(self.f.checkout)],
                                46: ['local-source', '--repo-root', str(self.f.checkout)],
                                47: ['local-source', '--repo-root', str(self.f.checkout)],
                                48: ['mode', '--repo-root', str(self.f.checkout), '--json'],
                                49: ['list-product-repos', '--repo-root', str(self.f.checkout)],
                                50: ['mode', '--repo-root', str(self.f.checkout), '--json'],
                                51: ['mode', '--repo-root', str(self.f.checkout), '--json'],
                                52: ['review-local-list', '--repo-root', str(self.f.checkout), '--phase', 'on_draft', '--key', 'runner'],
                                53: ['review-list', '--repo-root', str(self.f.checkout), '--phase', 'on_draft', '--key', 'runner'],
                            }[route]
                            self.assertEqual(captured[:-1], [str(resolver).encode(), *[arg.encode() for arg in expected_tail]])
                            self.assertEqual(captured.count(str(self.f.checkout).encode()), 0 if '--file' in statement else 1)
                            self.assertEqual(result.stdout, '' if fail else 'FUNCTIONAL=ok\n')
                            self.assertEqual(result.stderr, 'configuration: invalid YAML; line=1; column=1\n' if fail else '')
                route += 1
        self.assertEqual(route, 54)
        # Real Python diagnostics are not swallowed by the nested helper's
        # stderr suppression: the existing strict reader and policy argv run.
        function = fixtures.function_text('coderabbit-cli-reviewer.sh', 'rate_limit_policy_from_file')
        for shell in self.compatible_shells():
            for invalid in (False, True):
                with self.subTest(route='real-policy', shell=shell, invalid=invalid):
                    self.f.private.write_text('review:\n  coderabbit_cli:\n    rate_limit_policy: strict\n' + ('other: [bad?token=' + self.secret + ']\n' if invalid else ''))
                    body = 'source ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n'
                    body += 'workflow_config_resolver_script() { printf "token=' + self.secret + '\\n" >&2; printf "%s\\n" ' + shlex.quote(str(self.f.runtime / 'workflow-config-resolver.py')) + '; };\n'
                    body += function + '\nrate_limit_policy_from_file ' + shlex.quote(str(self.f.private))
                    result = self.safe(self.run_command([shell, '-c', body]), 2 if invalid else 0)
                    self.assertEqual(result.stdout, '' if invalid else 'strict')
                    if invalid: self.assertRegex(result.stderr, r'^ERROR: configuration: [A-Za-z ]+(?:; (?:line|column)=[0-9]+)*(?:; key=[A-Za-z_.]+)?\n$')
                    else: self.assertEqual(result.stderr, '')

    def test_D69_supported_unbound_root_apis_fail_before_reader(self):
        # U56/U59-U65: real supported APIs, without an entry binding, and the
        # same APIs with an actual binding. Poison ONLY the legacy fallback
        # reached from the real getter; unrelated inherited root calls remain.
        rows = [('U56', 'rate_limit_policy_from_config', ''),
                ('U59', 'workflow_local_config_file', ''),
                ('U60', 'workflow_config_review_local_list_if_declared', 'SHARED on_draft runner'),
                ('U61', 'workflow_config_review_list', 'SHARED on_draft runner'),
                ('U62', 'workflow_repository_mode', ''),
                ('U63', 'workflow_repository_context', 'mobile'),
                ('U64', 'workflow_validate_repository_context', 'mobile'),
                ('U65', 'workflow_review_override_context', '')]
        for route, function, arguments in rows:
            for shell in self.compatible_shells():
                baseline = None
                for mode in ('unbound', 'bound', 'fault'):
                    with self.subTest(route=route, shell=shell, mode=mode):
                        reads = self.f.root / 'root-api-reader-argv'
                        fallback = self.f.root / 'root-api-fallback'
                        for path in (reads, fallback): path.unlink(missing_ok=True)
                        body = 'set -euo pipefail\nsource ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n'
                        if function == 'rate_limit_policy_from_config': body += fixtures.function_text('coderabbit-cli-reviewer.sh', function) + '\n'
                        if mode == 'bound': body += 'workflow_bind_local_config_root ' + shlex.quote(str(self.f.checkout)) + '\n'
                        if mode != 'unbound':
                            body += 'eval "$(declare -f workflow_repo_root | sed \'1s/workflow_repo_root/actual_workflow_repo_root/\')"\n'
                            body += 'workflow_repo_root() { case " ${FUNCNAME[*]} " in *workflow_local_config_root*) printf x >' + shlex.quote(str(fallback)) + '; printf "token=' + self.secret + '\\n" >&2; return 17;; esac; actual_workflow_repo_root "$@"; };\n'
                        body += 'python3() { if [ "${1##*/}" = workflow-config-resolver.py ]; then printf "%s\\0" "$@" >' + shlex.quote(str(reads)) + '; fi; command python3 "$@"; };\n'
                        call = function + ' ' + arguments.replace('SHARED', shlex.quote(str(self.f.shared)))
                        # Conditional callers disable errexit in their producer:
                        # the new guard must prevent a later reader/default0.
                        body += 'status=0; ' + call + ' || status=$?; exit "$status"\n'
                        result = self.safe(self.run_command([shell, '-c', body]), 2 if mode == 'fault' else 0)
                        self.assertEqual(result.stderr, '')
                        if mode == 'fault':
                            self.assertEqual(result.stdout, '')
                            self.assertTrue(fallback.exists())
                            self.assertFalse(reads.exists())
                        else:
                            self.assertFalse(fallback.exists())
                            argv = reads.read_bytes().split(b'\0')
                            self.assertEqual(argv[-1], b'')
                            root_index = argv.index(b'--repo-root')
                            self.assertEqual(argv[root_index + 1], str(self.f.checkout).encode())
                            self.assertTrue(result.stdout)
                            current = (result.stdout, argv)
                            if baseline is None: baseline = current
                            else: self.assertEqual(current, baseline)

    def test_D70_entry_defaults_and_real_readiness_fallback_subprocess(self):
        # U54/U55: actual module setup statements; failed default lookup never
        # reaches a binder/reader, and REPO_ROOT's original empty value survives.
        apply = (self.f.runtime / 'apply-readiness-labels.sh').read_text().splitlines()
        readiness_line = next(line for line in apply if line.startswith('[ -n "$repo_root" ] || repo_root='))
        source = (self.f.runtime / 'coderabbit-cli-reviewer.sh').read_text()
        start = source.index('# Bind only after argument parsing')
        end = source.index('\nif [ -n "$REPO_ROOT" ]; then', start)
        binding = source[start:end]
        for shell in self.compatible_shells():
            for route, statement, failure_status in [('U54', readiness_line, 17), ('U55', binding, 2)]:
                for mode in ('default', 'explicit', 'fault'):
                    with self.subTest(route=route, shell=shell, mode=mode):
                        trace = self.f.root / 'entry-default-binder'; trace.unlink(missing_ok=True)
                        body = 'set -euo pipefail\nsource ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n'
                        initial = str(self.f.checkout) if mode == 'explicit' else ''
                        body += 'repo_root=' + shlex.quote(initial) + '; REPO_ROOT="$repo_root"\n'
                        body += 'workflow_repo_root() { printf "token=' + self.secret + '\\n" >&2; ' + ('return 17;' if mode == 'fault' else 'printf "%s\\n" ' + shlex.quote(str(self.f.checkout)) + ';') + ' };\n'
                        body += 'eval "$(declare -f workflow_bind_local_config_root | sed \'1s/workflow_bind_local_config_root/actual_bind/\')"\n'
                        body += 'workflow_bind_local_config_root() { printf "%s\\0" "$@" >' + shlex.quote(str(trace)) + '; actual_bind "$@"; };\n'
                        body += statement + '\n'
                        if route == 'U54': body += 'workflow_bind_local_config_root "$repo_root"\n'
                        body += 'printf "BOUND=%s\\nREPO_ROOT=%s\\n" "$(workflow_local_config_root)" "$REPO_ROOT"\n'
                        result = self.safe(self.run_command([shell, '-c', body]), failure_status if mode == 'fault' else 0)
                        if mode == 'fault':
                            self.assertEqual(result.stdout, '')
                            self.assertFalse(trace.exists())
                            self.assertEqual(result.stderr, 'configuration: checkout access error\n' if route == 'U55' else '')
                        else:
                            self.assertEqual(trace.read_bytes().split(b'\0'), [str(self.f.checkout).encode(), b''])
                            self.assertEqual(result.stdout, 'BOUND=' + str(self.f.checkout) + '\nREPO_ROOT=' + initial + '\n')
                            self.assertEqual(result.stderr, '')
        # U57/U58: reuse only the established fake GH/child observer. The actual
        # restore/revalidate function and actual readiness subprocess both run.
        spec = importlib.util.spec_from_file_location('root_handoff_fixtures', Path(__file__).with_name('test_private_source_authority.py'))
        authority = importlib.util.module_from_spec(spec); spec.loader.exec_module(authority)
        holder = type('SyntheticFixtureState', (), {})(); holder.f = self.f
        authority.PrivateSourceAuthority.readiness_handoff_fixture(holder)
        for shell in self.compatible_shells():
            self.f.env['SYNTHETIC_BASH'] = shell
            for route in ('restore', 'revalidate'):
                self.f.env['SYNTHETIC_LABEL_PRESENT'] = '1' if route == 'revalidate' else '0'
                for mode in ('unbound', 'bound', 'fault'):
                    with self.subTest(route=route, shell=shell, mode=mode):
                        holder.child_events.unlink(missing_ok=True)
                        body = 'SCRIPT_DIR=' + shlex.quote(str(self.f.runtime)) + '\nrepo_root=""\n'
                        if mode == 'bound': body += 'workflow_bind_local_config_root ' + shlex.quote(str(self.f.checkout)) + '\n'
                        body += 'eval "$(declare -f workflow_local_config_root | sed \'1s/workflow_local_config_root/actual_local_root/\')"\n'
                        body += 'workflow_local_config_root() { printf "token=' + self.secret + '\\n" >&2; ' + ('return 17;' if mode == 'fault' else 'actual_local_root "$@";') + ' };\n'
                        body += 'restore_regression_label_if_missing 1993 feature/1993-fixture\n'
                        prefix = 'HARNESS_MODE=1 source ' + shlex.quote(str(self.f.runtime / 'pr-review-loop.sh')) + '\n'
                        result = self.safe(self.run_command([shell, '-c', prefix + body]), 0)
                        events = [json.loads(line) for line in holder.child_events.read_text().splitlines()]
                        self.assertEqual(len(events), 1)
                        self.assertEqual(events[0]['repo_root'], '' if mode == 'fault' else str(self.f.checkout))
                        self.assertEqual(events[0]['status'], 2 if mode == 'fault' else 1)
                        self.assertIn('WARN: apply-readiness-labels.sh refused or failed', result.stderr)
                        if mode == 'fault': self.assertIn('missing value for --repo-root', result.stderr)
                        else: self.assertIn('REASON=ownership-mismatch', result.stdout)
        self.assertFalse(self.f.log.exists())

    def test_D71_new_default_classifier_and_complete_binder_boundary(self):
        # U66: boolean classifier0/1 still chooses exact private/shared names.
        for shell in self.compatible_shells():
            for default in (True, False):
                with self.subTest(route='U66', shell=shell, default=default):
                    body = 'source ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n'
                    body += 'workflow_bind_local_config_root ' + shlex.quote(str(self.f.checkout)) + '\n'
                    body += 'workflow_is_default_config_file() { printf "token=' + self.secret + '\\n" >&2; return ' + ('0' if default else '1') + '; };\n'
                    body += 'workflow_config_review_list ' + shlex.quote(str(self.f.shared)) + ' on_draft runner\n'
                    result = self.safe(self.run_command([shell, '-c', body]), 0)
                    self.assertEqual(result.stdout, 'codex\n' if default else 'shared-policy-sentinel\n')
                    self.assertEqual(result.stderr, '')
            # U67: real binder, both canonicalization producers, before reading.
            for failure in ('success', 'cd', 'pwd'):
                with self.subTest(route='U67', shell=shell, failure=failure):
                    trace = self.f.root / 'binder-reader'; trace.unlink(missing_ok=True)
                    body = 'source ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n'
                    body += 'eval "$(declare -f workflow_local_config_file | sed \'1s/workflow_local_config_file/actual_local_file/\')"\n'
                    body += 'workflow_local_config_file() { printf x >' + shlex.quote(str(trace)) + '; actual_local_file "$@"; };\n'
                    if failure != 'success': body += failure + '() { printf "token=' + self.secret + '\\n" >&2; return 29; };\n'
                    body += 'workflow_bind_local_config_root ' + shlex.quote(str(self.f.checkout)) + '\nworkflow_local_config_root\n'
                    result = self.safe(self.run_command([shell, '-c', body]), 0 if failure == 'success' else 2)
                    self.assertEqual(trace.exists(), failure == 'success')
                    self.assertEqual(result.stdout, str(self.f.checkout) + '\n' if failure == 'success' else '')
                    self.assertEqual(result.stderr, '' if failure == 'success' else 'ERROR: local-source unreadable directory\n')

    def test_D72_real_python_launcher_boundaries_missing_unreadable_and_success(self):
        # The real interpreter may fail BEFORE the resolver can sanitize stderr.
        # These are the actual eleven U43-U53 statements, with original guards.
        groups = {'coderabbit-cli-reviewer.sh': ['rate_limit_policy_from_file', 'rate_limit_policy_from_config'],
                  'discover-workflow-state.sh': None,
                  'pr-review-loop.sh': ['resolve_local_review_override_root'],
                  'workflow-lib.sh': ['workflow_local_config_file', 'workflow_product_repo_name_for_github_slug',
                                      'workflow_hub_root_for_ci_policy', 'workflow_merge_ci_policy_into_json',
                                      'workflow_config_review_local_list_if_declared', 'workflow_config_review_list']}
        locator_dir = self.f.root / ('token=' + self.secret); locator_dir.mkdir()
        missing = locator_dir / 'missing-resolver.py'
        unreadable = locator_dir / 'unreadable-resolver.py'
        unreadable.write_text('print("UNEXPECTED_READ")\n'); unreadable.chmod(0)
        self.addCleanup(unreadable.chmod, 0o600)
        self.assertFalse(os.access(unreadable, os.R_OK), 'synthetic unreadable fixture must genuinely deny reads')
        initialize = 'root=' + shlex.quote(str(self.f.checkout)) + '; repo_root="$root"; initiating_root="$root"; config_file="$root/.ai-dev-workflow.yaml"; policy_root="$root"; review_root="$root"; phase=on_draft; key=runner; status=0; args=(review-list --repo-root "$root" --shared-file "$config_file" --phase on_draft --key runner)\n'
        route = 43
        for name, functions in groups.items():
            lines = ('\n'.join(fixtures.function_text(name, f) for f in functions).splitlines()
                     if functions else (self.f.runtime / name).read_text().splitlines())
            for start in [i for i, line in enumerate(lines) if '$(workflow_config_resolver_script' in line]:
                end = start
                while lines[end].rstrip().endswith('\\'): end += 1
                if '|| status=$?' in lines[end]: end += 1
                statement = '\n'.join(lines[start:end + 1]).strip()
                for shell in self.compatible_shells():
                    for mode, locator in [('missing', missing), ('unreadable', unreadable), ('success', Path('/dev/stdin'))]:
                        with self.subTest(route='U' + str(route), shell=shell, mode=mode):
                            body = 'set -euo pipefail\nsource ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n' + initialize
                            body += 'workflow_config_resolver_script() { printf "%s\\n" ' + shlex.quote(str(locator)) + '; };\n'
                            body += 'actual_boundary() {\n' + statement + '\n'
                            for variable in ['configured_repos', 'selected_file', 'mode_json', 'names']:
                                if statement.startswith(variable + '='): body += 'printf "%s\\n" "$' + variable + '"\n'
                            body += '}\nactual_boundary ' + shlex.quote(str(self.f.private)) + '\n'
                            result = self.safe(self.run_command([shell, '-c', body], input='print("SYNTHETIC_OK")\n'), 0 if mode == 'success' else 2)
                            self.assertEqual(result.stdout, 'SYNTHETIC_OK\n' if mode == 'success' else '')
                            self.assertEqual(result.stderr, '' if mode == 'success' else 'ERROR: diagnostic sanitization failed\n')
                            self.assertNotIn(str(locator_dir), result.stdout + result.stderr)
                route += 1
        self.assertEqual(route, 54)
        # Complete public APIs, not only extracted launch statements; no real
        # config is reached when the interpreter cannot open the fake resolver.
        for shell in self.compatible_shells():
            for function, args in [('workflow_local_config_file', shlex.quote(str(self.f.checkout))),
                                   ('workflow_config_review_local_list_if_declared', shlex.quote(str(self.f.shared)) + ' on_draft runner'),
                                   ('workflow_config_review_list', shlex.quote(str(self.f.shared)) + ' on_draft runner')]:
                for mode, locator in [('missing', missing), ('unreadable', unreadable), ('success', Path('/dev/stdin'))]:
                    with self.subTest(public_api=function, shell=shell, mode=mode):
                        body = 'set -euo pipefail\nsource ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n'
                        body += 'workflow_local_config_root() { printf "%s\\n" ' + shlex.quote(str(self.f.checkout)) + '; };\nworkflow_is_default_config_file() { return 0; };\n'
                        body += 'workflow_config_resolver_script() { printf "%s\\n" ' + shlex.quote(str(locator)) + '; };\n' + function + ' ' + args + '\n'
                        result = self.safe(self.run_command([shell, '-c', body], input='print("SYNTHETIC_OK")\n'), 0 if mode == 'success' else 2)
                        self.assertEqual(result.stdout, 'SYNTHETIC_OK\n' if mode == 'success' else '')
                        self.assertEqual(result.stderr, '' if mode == 'success' else 'ERROR: diagnostic sanitization failed\n')
                        self.assertNotIn(str(locator_dir), result.stdout + result.stderr)

    def test_D73_parallelism_error_formatter_failure_is_metadata_only(self):
        function = fixtures.function_text('workflow-batch-lanes.sh', 'read_parallelism_caps')
        target = self.f.root / ('token=' + self.secret); target.mkdir()
        missing_config = target / 'missing-selected.yaml'
        malformed = target / 'malformed-selected.yaml'; malformed.write_text('other: [' + self.secret + '\n')
        valid = self.f.root / 'caps.yaml'
        valid.write_text('guardrails:\n  parallelism:\n    max_concurrent_by_stage:\n      spec: 2\n      plan: 3\n      review: 4\n      implementation: 5\n')
        raising = self.f.root / 'raising-formatter'; raising.mkdir()
        (raising / 'workflow-config-resolver.py').write_text('def format_config_error(*args, **kwargs):\n    raise RuntimeError("' + self.secret + '")\n')
        availability = self.f.root / 'yaml-available'; availability.mkdir()
        (availability / 'yaml.py').write_text('def safe_load(text):\n    raise AssertionError("real Path.read_text must fail before parsing")\n')
        absent = self.f.root / 'yaml-absent'; absent.mkdir()
        (absent / 'yaml.py').write_text('raise ImportError("synthetic dependency absence")\n')
        original_path = self.f.env['PYTHONPATH']
        defaults = {'spec': 0, 'plan': 0, 'review': 0, 'implementation': 1}
        cases = [('missing-formatter', missing_config, target, availability, 2,
                  'configuration: configuration validation error; key=guardrails.parallelism\n'),
                 ('raising-formatter', missing_config, raising, availability, 2,
                  'configuration: configuration validation error; key=guardrails.parallelism\n'),
                 ('normal-formatter', missing_config, self.f.runtime, availability, 2,
                  'configuration: configuration unreadable; key=guardrails.parallelism\n'),
                 ('malformed-source-missing-formatter', malformed, target, None, 2,
                  'configuration: configuration validation error; key=guardrails.parallelism\n'),
                 ('valid-caps', valid, self.f.runtime, None, 0, ''),
                 ('legacy-no-yaml-default', missing_config, target, absent, 0, '')]
        for shell in self.compatible_shells():
            for name, config, formatter_dir, stub, status, stderr in cases:
                with self.subTest(case=name, shell=shell):
                    self.f.env['PYTHONPATH'] = str(stub) + os.pathsep + original_path if stub else original_path
                    body = 'set -euo pipefail\nSCRIPT_DIR=' + shlex.quote(str(formatter_dir)) + '\n'
                    body += 'parallelism_config_file() { printf "%s\\n" ' + shlex.quote(str(config)) + '; };\n'
                    body += function + '\nread_parallelism_caps ' + shlex.quote(str(self.f.checkout)) + '\n'
                    try: result = self.safe(self.run_command([shell, '-c', body]), status)
                    finally: self.f.env['PYTHONPATH'] = original_path
                    self.assertEqual(result.stderr, stderr)
                    self.assertNotIn('Traceback', result.stdout + result.stderr)
                    self.assertNotIn(str(target), result.stdout + result.stderr)
                    if status: self.assertEqual(result.stdout, '')
                    else: self.assertEqual(json.loads(result.stdout), defaults if stub else {'spec': 2, 'plan': 3, 'review': 4, 'implementation': 5})

    def test_D74_risk_error_formatter_failure_is_metadata_only(self):
        # Actual CLI rejects [] evidence before config reads; only its renderer
        # then attempts the sibling loader. No actual PR risk is classified.
        source = (self.f.runtime / 'workflow-risk-paths.py').read_bytes()
        target = self.f.root / ('token=' + self.secret); target.mkdir()
        missing_script = target / 'workflow-risk-paths.py'; missing_script.write_bytes(source)
        raising = self.f.root / 'raising-risk-formatter'; raising.mkdir()
        raising_script = raising / 'workflow-risk-paths.py'; raising_script.write_bytes(source)
        (raising / 'workflow-config-resolver.py').write_text('def format_config_error(*args, **kwargs):\n    raise RuntimeError("' + self.secret + '")\n')
        self.f.shared.write_text('mode: single_repo\n')
        cases = [('missing-formatter', missing_script, '[]', 2,
                  'ERROR: configuration: configuration validation error; key=guardrails.risk_paths\n'),
                 ('raising-formatter', raising_script, '[]', 2,
                  'ERROR: configuration: configuration validation error; key=guardrails.risk_paths\n'),
                 ('normal-formatter', self.f.runtime / 'workflow-risk-paths.py', '[]', 2,
                  'ERROR: configuration: configuration validation error; key=guardrails.risk_paths\n'),
                 ('normal-json-error', missing_script, self.secret, 2,
                  'ERROR: unreadable project configuration or classifier evidence\n'),
                 ('valid-no-map', self.f.runtime / 'workflow-risk-paths.py', '{}', 0, '')]
        for name, script, evidence, status, stderr in cases:
            with self.subTest(case=name):
                result = self.safe(self.run_command(['python3', str(script), '--repo-root', str(self.f.checkout)], input=evidence), status)
                self.assertEqual(result.stderr, stderr)
                self.assertNotIn('Traceback', result.stdout + result.stderr)
                self.assertNotIn(str(target), result.stdout + result.stderr)
                if status: self.assertEqual(result.stdout, '')
                else: self.assertEqual(json.loads(result.stdout), {'matches': {}})

    def test_D75_changed_context_callers_close_inherited_native_stderr(self):
        # Isolate the later exact boundary: earlier successful resolver probes
        # must not mask a subsequent tooling-locator IO failure.
        routes = [
            ('C01', 'workflow-lib.sh', 'workflow_product_repo_name_for_github_slug', 'context'),
            ('C02', 'workflow-lib.sh', 'workflow_merge_ci_policy_into_json', 'context'),
            ('C03', 'discover-workflow-state.sh', None, 'repo_context'),
        ]
        target = 'synthetic product name'
        root = self.f.root / 'selected checkout'; root.mkdir()
        locators = self.f.root / ('token=' + self.secret); locators.mkdir()
        missing = locators / 'missing-resolver.py'
        unreadable = locators / 'unreadable-resolver.py'
        unreadable.write_text('print("UNEXPECTED_READ")\n'); unreadable.chmod(0)
        self.addCleanup(unreadable.chmod, 0o600)
        self.assertFalse(os.access(unreadable, os.R_OK), 'synthetic unreadable fixture must genuinely deny reads')
        for route, name, function, variable in routes:
            text = fixtures.function_text(name, function) if function else (self.f.runtime / name).read_text()
            matches = [line.strip() for line in text.splitlines()
                       if variable + '="$(' in line and 'workflow_repository_context ' in line
                       and (function is not None or '"$selected_for_context"' in line)]
            self.assertEqual(len(matches), 1)
            statement = matches[0]
            initialize = 'root=' + shlex.quote(str(root)) + '; repo_root="$root"; name=' + shlex.quote(target) + '; repo_name="$name"; selected_for_context="$name";\n'
            for shell in self.compatible_shells():
                for mode, locator in [('missing', missing), ('unreadable', unreadable), ('success', Path('/dev/stdin'))]:
                    with self.subTest(route=route, shell=shell, mode=mode):
                        argv = self.f.root / 'native-context-argv'
                        if argv.exists(): argv.unlink()
                        body = 'set -euo pipefail\nsource ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n' + initialize
                        body += 'workflow_config_resolver_script() { printf "%s\\n" ' + shlex.quote(str(locator)) + '; };\n'
                        body += 'actual_boundary() {\n' + statement + '\nprintf "%s\\n" "$' + variable + '"\n}\nactual_boundary\n'
                        program = 'import pathlib,sys; pathlib.Path(' + repr(str(argv)) + ').write_bytes(b"\\0".join(arg.encode() for arg in sys.argv[1:])+b"\\0"); print("SYNTHETIC_OK")\n'
                        result = self.safe(self.run_command([shell, '-c', body], input=program), 0 if mode == 'success' else 2)
                        self.assertEqual(result.stdout, 'SYNTHETIC_OK\n' if mode == 'success' else '')
                        self.assertEqual(result.stderr, '' if mode == 'success' else 'ERROR: diagnostic sanitization failed\n')
                        self.assertNotIn(str(locators), result.stdout + result.stderr)
                        if mode == 'success':
                            self.assertEqual(argv.read_bytes().split(b'\0'), [b'resolve', b'--repo-root', str(root).encode(), b'--repo', target.encode(), b''])
                        else: self.assertFalse(argv.exists())
                for failure in [False, True]:
                    with self.subTest(route=route, shell=shell, mode='helper-argv', failure=failure):
                        argv = self.f.root / 'helper-context-argv'
                        body = 'set -euo pipefail\nsource ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n' + initialize
                        body += 'workflow_repository_context() { printf "%s\\0" "$@" >' + shlex.quote(str(argv)) + '; '
                        body += ('printf "configuration: invalid YAML; line=1; column=1\\n" >&2; return 17;' if failure else 'printf "FUNCTIONAL=ok\\n";') + ' };\n'
                        body += 'actual_boundary() {\n' + statement + '\nprintf "%s\\n" "$' + variable + '"\n}\nactual_boundary\n'
                        result = self.safe(self.run_command([shell, '-c', body]), 2 if failure else 0)
                        self.assertEqual(argv.read_bytes().split(b'\0'), [target.encode(), str(root).encode(), b''])
                        self.assertEqual(result.stdout, '' if failure else 'FUNCTIONAL=ok\n')
                        self.assertEqual(result.stderr, 'configuration: invalid YAML; line=1; column=1\n' if failure else '')

    def multiline_redactor(self):
        spec = importlib.util.spec_from_file_location('synthetic_continuation_redactor', self.f.runtime / 'workflow-config-resolver.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def assert_multiline_diagnostic(self, output, public, empty=False):
        self.assertNotIn(self.secret, output)
        self.assertNotIn('ContinuationOpaqueSuffix', output)
        for item in public:
            self.assertIn(item, output)
        if not empty:
            self.assertIn('[REDACTED]', output)

    def test_D76_complete_multiline_scalar_inventory_and_actual_cli(self):
        module = self.multiline_redactor()
        for case, template, public, empty in MULTILINE_REDACTION_CASES:
            with self.subTest(case=case):
                source = template.replace('$OPAQUE', self.secret + 'ContinuationOpaqueSuffix')
                output = module.redact_text(source)
                self.assert_multiline_diagnostic(output, public, empty)
                self.assertEqual(module.redact_text(output), output)
                result = self.safe(self.run_command(['python3', str(self.f.runtime / 'workflow-config-resolver.py'),
                                                     'redact-text'], input=source), 0)
                self.assert_multiline_diagnostic(result.stdout + result.stderr, public, empty)
                self.assertEqual(result.stderr, '')
        # These source-valid forms remain configuration-reader controls; the
        # diagnostic-only malformed/block/prose cases above do not add syntax.
        for spelling in (self.secret, '"' + self.secret + '"', "'" + self.secret + "'"):
            module.parse_review_yaml(self.f.private, raw='token:\n  ' + spelling + '\npublic: value\n', review_fields=False)

    def test_D77_multiline_actual_bash_text_file_and_json_boundaries(self):
        source_file = self.f.root / 'synthetic-diagnostic.txt'
        for shell in self.compatible_shells():
            for case, template, public, empty in MULTILINE_REDACTION_CASES:
                with self.subTest(shell=shell, case=case):
                    source = template.replace('$OPAQUE', self.secret + 'ContinuationOpaqueSuffix')
                    source_file.write_text(source)
                    script = 'source "$1"\nworkflow_redact_text < "$2"\nworkflow_redact_file "$2" >&2\n'
                    result = self.safe(self.run_command([shell, '-c', script, 'synthetic',
                                                        str(self.f.runtime / 'workflow-lib.sh'), str(source_file)]), 0)
                    self.assertEqual(result.stdout, result.stderr)
                    self.assert_multiline_diagnostic(result.stdout + result.stderr, public, empty)
            value = {'reason': 'token:\n  ' + self.secret + '\npublic: KEEP_PUBLIC',
                     'token': self.secret + '\nunindented tail', 'nested': [3, True, None], 'result': 'clean'}
            source_file.write_text(json.dumps(value))
            result = self.safe(self.run_command([shell, '-c', 'source "$1"; workflow_redact_json < "$2"; workflow_redact_json < "$2" >&2',
                                                'synthetic', str(self.f.runtime / 'workflow-lib.sh'), str(source_file)]), 0)
            self.assertEqual(result.stdout, result.stderr)
            data = json.loads(result.stdout)
            self.assertEqual(data['nested'], [3, True, None])
            self.assertEqual(data['result'], 'clean')
            self.assertEqual(data['token'], '[REDACTED]')
            self.assertIn('public: KEEP_PUBLIC', data['reason'])

    def diagnostic_binary(self, shell, body, *args, input=None):
        return subprocess.run([shell, '-c', 'source "$1"; shift;\n' + body,
                               'synthetic', str(self.f.runtime / 'workflow-lib.sh'), *args],
                              input=input, capture_output=True, env=self.f.env,
                              cwd=self.f.checkout, timeout=30)

    def test_D78_sensitive_original_kv_frame_ownership_and_independent_records(self):
        cases = [('DETAIL', 'token:\n  ' + self.secret + '\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',)),
                 ('TOKEN', self.secret + '\nunindented ContinuationOpaqueSuffix', ()),
                 *[('TOKEN', prefix + self.secret + '\nContinuationOpaqueSuffix', ()) for prefix in ('\n', '\r\n', '\n\n')],
                 *[(key, '\n' + self.secret + '\nContinuationOpaqueSuffix', ()) for key in ('TOKEN ', ' "TOKEN" ', "'TOKEN'", 'notice TOKEN', 'Authorization ')],
                 ('DETAIL', 'token: "unclosed\n' + self.secret + '\nContinuationOpaqueSuffix', ()),
                 ('password=' + self.secret, self.secret + '\nContinuationOpaqueSuffix', ()),
                 ('password="open ' + self.secret, self.secret + '\nContinuationOpaqueSuffix', ()),
                 ('-----BEGIN PRIVATE KEY-----' + self.secret, 'ContinuationOpaqueSuffix', ()),
                 ('https://u:' + self.secret, 'ContinuationOpaqueSuffix@fixture.invalid', ()),
                 ('detail with spaces', 'token:\n  ' + self.secret + '\npublic: KEEP_PUBLIC', ('public: KEEP_PUBLIC',)),
                 ('password="' + self.secret + '"', 'KEEP_VALUE', ('KEEP_VALUE',))]
        for shell in self.compatible_shells():
            for helper in ('workflow_diagnostic_kv', 'workflow_diagnostic_kv_escaped'):
                for key, value, public in cases:
                    with self.subTest(shell=shell, helper=helper, key_kind=cases.index((key, value, public))):
                        script = helper + ' "$1" "$2"; ' + helper + ' "$1" "$2" >&2; workflow_diagnostic_kv RESULT clean; workflow_diagnostic_kv BLOCKING_COUNT 17; workflow_diagnostic_kv HEAD_SHA ' + 'a' * 40
                        result = self.diagnostic_binary(shell, script, key, value)
                        self.assertEqual(result.returncode, 0)
                        combined = result.stdout + result.stderr
                        self.assertNotIn(self.secret.encode(), combined)
                        self.assertNotIn(b'ContinuationOpaqueSuffix', combined)
                        for item in public:
                            self.assertIn(item.encode(), result.stdout)
                        self.assertTrue(result.stdout.endswith(('RESULT=clean\nBLOCKING_COUNT=17\nHEAD_SHA=' + 'a' * 40 + '\n').encode()))
                        self.assertEqual(result.stdout[:-len(('RESULT=clean\nBLOCKING_COUNT=17\nHEAD_SHA=' + 'a' * 40 + '\n').encode())], result.stderr)
            for key, value in [('TOKEN', self.secret + '\nunindented ContinuationOpaqueSuffix'),
                               *[('TOKEN', prefix + self.secret + '\nContinuationOpaqueSuffix') for prefix in ('\n', '\r\n', '\n\n')],
                               ('DETAIL', 'token: "unclosed\n' + self.secret)]:
                result = self.diagnostic_binary(shell, 'workflow_diagnostic_kvs "$1" "$2" RESULT clean BLOCKING_COUNT 17 HEAD_SHA ' + 'a' * 40 + '; workflow_diagnostic_kvs "$1" "$2" RESULT clean BLOCKING_COUNT 17 HEAD_SHA ' + 'a' * 40 + ' >&2', key, value)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stdout, result.stderr)
                self.assertNotIn(self.secret.encode(), result.stdout + result.stderr)
                self.assertNotIn(b'ContinuationOpaqueSuffix', result.stdout + result.stderr)
                self.assertIn(b'RESULT=clean\nBLOCKING_COUNT=17\nHEAD_SHA=', result.stdout)

    def test_D79_kv_layout_escape_and_authorization_positive_parity(self):
        controls = ''.join(chr(code) for code in list(range(1, 32)) + [127] + list(range(128, 160)))
        cases = [('', ''), ('public', ''), ('arbitrary detail=key', 'two words'),
                 ('multi\nline key\n', 'public\\literal\n\n'), ('key\r', 'public\r\n\n'),
                 ('key', controls + '\\literal\\n界\n\n'), ('key', 'public\r'), ('key', 'public\n\r\n')]
        for shell in self.compatible_shells():
            for helper in ('workflow_diagnostic_kv', 'workflow_diagnostic_kv_escaped'):
                for key, value in cases:
                    with self.subTest(shell=shell, helper=helper, control=cases.index((key, value))):
                        result = self.diagnostic_binary(shell, helper + ' "$1" "$2"; ' + helper + ' "$1" "$2" >&2', key, value)
                        self.assertEqual(result.returncode, 0)
                        expected_body = ('value="$(printf %s "$2")"; print_kv_escaped "$1" "$value"' if helper.endswith('_escaped') else 'value="$(printf "%s=%s\\n" "$1" "$2")"; printf "%s\\n" "$value"')
                        expected = self.diagnostic_binary(shell, expected_body, key, value)
                        self.assertEqual(expected.returncode, 0)
                        self.assertEqual(result.stdout, expected.stdout)
                        self.assertEqual(result.stderr, expected.stdout)
            for helper, expected in [('workflow_diagnostic_kv', 'Authorization=[REDACTED] Bearer [REDACTED] Basic [REDACTED]\n'),
                                     ('workflow_diagnostic_kv_escaped', 'Authorization=Bearer [REDACTED] Basic [REDACTED]\n')]:
                result = self.diagnostic_binary(shell, helper + ' Authorization "$1"; ' + helper + ' Authorization "$1" >&2',
                                                'Bearer ' + self.secret + ' Basic ' + self.secret + '\nContinuationOpaqueSuffix')
                self.assertEqual(result.returncode, 0)
                self.assertEqual(result.stdout, expected.encode())
                self.assertEqual(result.stderr, expected.encode())
            for key, raw_value in [('Authorization ', '[REDACTED] Bearer [REDACTED] Basic [REDACTED]'),
                                   ('notice Authorization', '[REDACTED] Bearer [REDACTED] Basic [REDACTED]'),
                                   ('"Authorization"', '"[REDACTED]"'), ("'Authorization'", '[REDACTED]')]:
                for helper in ('workflow_diagnostic_kv', 'workflow_diagnostic_kv_escaped'):
                    result = self.diagnostic_binary(shell, helper + ' "$1" "$2"; ' + helper + ' "$1" "$2" >&2',
                                                    key, 'Bearer ' + self.secret + ' Basic ' + self.secret)
                    expected_value = 'Bearer [REDACTED] Basic [REDACTED]' if helper.endswith('_escaped') else raw_value
                    expected = (key + '=' + expected_value + '\n').encode()
                    self.assertEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, expected)
                    self.assertEqual(result.stderr, expected)
            for quote in ('"', "'"):
                for helper in ('workflow_diagnostic_kv', 'workflow_diagnostic_kv_escaped'):
                    result = self.diagnostic_binary(shell, helper + ' Authorization "$1"; ' + helper + ' Authorization "$1" >&2',
                                                    quote + 'Bearer ' + self.secret + quote)
                    expected_value = 'Bearer [REDACTED]' if helper.endswith('_escaped') else '[REDACTED]'
                    expected = ('Authorization=' + quote + expected_value + quote + '\n').encode()
                    self.assertEqual(result.returncode, 0)
                    self.assertEqual(result.stdout, expected)
                    self.assertEqual(result.stderr, expected)

    def test_D80_multiline_before_cap_actual_pipeline(self):
        source = 'p' * 19970 + '\ntoken:\n  ' + self.secret + 'ContinuationOpaqueSuffix' + 'x' * 100 + '\npublic: KEEP_PUBLIC'
        # Actual pipeline: full stdin is sanitized before the byte selector.
        result = self.safe(self.bash('printf %s ' + shlex.quote(source) + ' | workflow_redact_text | head -c 20000'), 0)
        self.assertNotIn('fabricatedDi', result.stdout + result.stderr)
        self.assertLessEqual(len(result.stdout.encode()), 20000)

    def test_D81_single_pair_framing_and_scanner_failure_are_atomic(self):
        resolver = str(self.f.runtime / 'workflow-config-resolver.py')
        for flag in ('--kv-pair', '--kv-escaped'):
            for raw in (b'', b'KEY\0value', b'KEY\0value\0EXTRA\0value\0', b'KEY\0\xfffabricatedDiagnosticValue\0'):
                with self.subTest(flag=flag, length=len(raw)):
                    result = subprocess.run(['python3', resolver, 'redact-text', flag], input=raw,
                                            capture_output=True, env=self.f.env, cwd=self.f.checkout, timeout=30)
                    self.assertEqual(result.returncode, 2)
                    self.assertEqual(result.stdout, b'')
                    self.assertEqual(result.stderr, b'ERROR: diagnostic sanitization failed\n')
        module = self.multiline_redactor()
        import io
        from unittest.mock import patch
        for flags in ({'kv': False, 'json': False, 'kv_pair': False, 'kv_escaped': False},
                      {'kv': True, 'json': False, 'kv_pair': False, 'kv_escaped': False}):
            with self.subTest(mode=flags):
                stdin = io.TextIOWrapper(io.BytesIO(b'KEY\0token: fabricatedDiagnosticValue\0'), encoding='utf-8')
                output, error = io.StringIO(), io.StringIO()
                with patch.object(module.sys, 'stdin', stdin), patch.object(module.sys, 'stdout', output), patch.object(module.sys, 'stderr', error), patch.object(module, '_diagnostic_assignment_spans', side_effect=RuntimeError('fabricatedDiagnosticValue')):
                    status = module.cmd_redact_text(type('Arguments', (), flags)())
                self.assertEqual(status, 2)
                self.assertEqual(output.getvalue(), '')
                self.assertEqual(error.getvalue(), 'ERROR: diagnostic sanitization failed\n')

    def test_D82_actual_persisted_multiline_evidence_and_functional_body(self):
        source = 'p' * 19970 + '\ntoken:\n  ' + self.secret + 'ContinuationOpaqueSuffix' + 'x' * 100 + '\npublic: KEEP_PUBLIC'
        pr = json.loads(self.f.pr.read_text())
        pr['body'] = source
        self.f.pr.write_text(json.dumps(pr))
        evidence = self.f.root / 'multiline-evidence.json'
        context = self.f.root / 'multiline-functional.json'
        result = self.safe(self.local_entry({'result': 'clean', 'comments': 0}, context_capture=context,
                                           LOCAL_AI_REVIEWER_EVIDENCE_FILE=str(evidence)), 0)
        raw = evidence.read_text()
        self.assertNotIn('fabricatedDi', raw + result.stdout + result.stderr)
        self.assertNotIn('ContinuationOpaqueSuffix', raw + result.stdout + result.stderr)
        data = json.loads(raw)
        self.assertEqual(data['counts'], {'comments': 0, 'blocking': 0, 'suggestions': 0})
        self.assertEqual(data['result'], 'clean')
        self.assertLessEqual(len(data['context_summary']['pr_body']), 20000)
        self.assertEqual(json.loads(context.read_text())['pr_body'], source[:20000])


    def test_D83_shared_header_grammar_with_empty_first_line_frames(self):
        module = self.multiline_redactor()
        names = ('token', 'ToKeN', 'Access_Token', 'workflow.api-key', 'private_key_value',
                 'passphrase', 'api key', 'Authorization', 'password', 'secret')
        breaks = ('\n', '\r\n', '\r', '\x85', '\u2028', '\u2029')
        profiles = []
        for index in range(90):
            left = ('', "'", '"')[(index % 9) // 3]
            right = ('', "'", '"')[index % 3]
            prefix = ('', 'notice ', '[stage] ', '--', '  ')[index % 5]
            spaces = ('', ' ', '\t')[index % 3]
            separator = ('', ':', '=')[(index // 3) % 3]
            profiles.append(prefix + left + names[index % 10] + right + spaces + separator)
        for index, key in enumerate(profiles):
            for boundary, newline in enumerate(breaks):
                value = newline + self.secret + newline + 'ContinuationOpaqueSuffix'
                for escaped in (False, True):
                    with self.subTest(profile=index, boundary=boundary, escaped=escaped):
                        output = module.redact_diagnostic_kv_frames(key + '\0' + value + '\0', single=True, escaped=escaped)
                        self.assertNotIn(self.secret, output)
                        self.assertNotIn('ContinuationOpaqueSuffix', output)
                        self.assertIn('[REDACTED]', output)
        tail = 'RESULT=clean\nBLOCKING_COUNT=17\nHEAD_SHA=' + 'a' * 40 + '\n'
        for shell in self.compatible_shells():
            # All grammar dimensions and all linebreaks reach actual supported
            # Bash helpers, not an emulated serialization/regex implementation.
            for index, key in enumerate(profiles[:18]):
                for boundary, newline in enumerate(breaks):
                    for helper in ('workflow_diagnostic_kv', 'workflow_diagnostic_kv_escaped'):
                        with self.subTest(shell=shell, profile=index, boundary=boundary, helper=helper):
                            script = helper + ' "$1" "$2"; workflow_diagnostic_kv RESULT clean; workflow_diagnostic_kv BLOCKING_COUNT 17; workflow_diagnostic_kv HEAD_SHA ' + 'a' * 40
                            result = self.diagnostic_binary(shell, script, key, newline + self.secret + newline + 'ContinuationOpaqueSuffix')
                            self.assertEqual(result.returncode, 0)
                            self.assertNotIn(self.secret.encode(), result.stdout + result.stderr)
                            self.assertNotIn(b'ContinuationOpaqueSuffix', result.stdout + result.stderr)
                            self.assertTrue(result.stdout.endswith(tail.encode()))
                            self.assertEqual(result.stderr, b'')
            for key in ('TOKEN', 'API_KEY', 'AUTHORIZATION'):
                for boundary, newline in enumerate(breaks):
                    with self.subTest(shell=shell, helper='workflow_diagnostic_kvs', boundary=boundary):
                        result = self.diagnostic_binary(shell, 'workflow_diagnostic_kvs "$1" "$2" RESULT clean BLOCKING_COUNT 17 HEAD_SHA ' + 'a' * 40,
                                                        key, newline + self.secret + newline + 'ContinuationOpaqueSuffix')
                        self.assertEqual(result.returncode, 0)
                        self.assertNotIn(self.secret.encode(), result.stdout + result.stderr)
                        self.assertNotIn(b'ContinuationOpaqueSuffix', result.stdout + result.stderr)
                        self.assertTrue(result.stdout.endswith(tail.encode()))
                        self.assertEqual(result.stderr, b'')


    def comment_redaction_cases(self):
        # Frozen diagnostic fixtures; source validity is a separate contract.
        return (('C01', 'other: { # }\n  token:\n  $OPAQUE$TAIL, public: PUBLIC_KEEP\n}\n', ('PUBLIC_KEEP',), False),
         ('C02', 'other: [ # ]\n  {token:\n  $OPAQUE$TAIL, public: PUBLIC_KEEP}\n]\n', ('PUBLIC_KEEP',), False),
         ('C03',
          'other: [{ # }]]}\n  token:\n  $OPAQUE$TAIL, public: PUBLIC_KEEP\n}]\n',
          ('PUBLIC_KEEP',),
          False),
         ('C04', '# {\ntoken: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C05', '# [\ntoken: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C06', '# [ { \' " } ]\ntoken: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C07', 'other: { # " }\n  token:\n  $OPAQUE$TAIL, public: PUBLIC_KEEP\n}\n', ('PUBLIC_KEEP',), False),
         ('C08', "other: { # ' }\n  token:\n  $OPAQUE$TAIL, public: PUBLIC_KEEP\n}\n", ('PUBLIC_KEEP',), False),
         ('C09', "# can't [\nother: {token:\n$OPAQUE$TAIL, public: PUBLIC_KEEP}\n", ('PUBLIC_KEEP',), False),
         ('C10', 'other: public # [\ntoken: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C11', 'other: {token: # }\n$OPAQUE$TAIL, public: PUBLIC_KEEP}\n', ('PUBLIC_KEEP',), False),
         ('C12', 'other: {token: $OPAQUE\n# ] }\n$TAIL, public: PUBLIC_KEEP}\n', ('PUBLIC_KEEP',), False),
         ('C13', 'other: {token: "$OPAQUE$TAIL", # ] }\npublic: PUBLIC_KEEP}\n', ('PUBLIC_KEEP',), False),
         ('C14', '# token: $OPAQUE$TAIL [\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C15', 'other: { # token: $OPAQUE$TAIL }\npublic: PUBLIC_KEEP}\n', ('PUBLIC_KEEP',), False),
         ('C16', 'other: "# [ {"\ntoken: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C17', "other: '# [ {'\ntoken: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n", ('PUBLIC_KEEP',), False),
         ('C18', 'other: "quoted\\" # ["\ntoken: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C19', "other: 'can''t # ['\ntoken: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n", ('PUBLIC_KEEP',), False),
         ('C20', 'other: public#value[\ntoken: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C21', 'other: {token: "$OPAQUE# } [ $TAIL", public: PUBLIC_KEEP}\n', ('PUBLIC_KEEP',), False),
         ('C22', "other: {token: '$OPAQUE# } [ $TAIL', public: PUBLIC_KEEP}\n", ('PUBLIC_KEEP',), False),
         ('C23', 'other: {token:\n$OPAQUE$TAIL, public: PUBLIC_KEEP}\n', ('PUBLIC_KEEP',), False),
         ('C24', 'other: [{token: [$OPAQUE, {$TAIL: value}], public: PUBLIC_KEEP}]\n', ('PUBLIC_KEEP',), False),
         ('C25', 'other: {note: "[}]", token:\n$OPAQUE$TAIL, public: PUBLIC_KEEP}\n', ('PUBLIC_KEEP',), False),
         ('C26',
          'other: {note: [public, # ] }\nvalue], token:\n$OPAQUE$TAIL, public: PUBLIC_KEEP}\n',
          ('PUBLIC_KEEP',),
          False),
         ('C27', '{token:\n$OPAQUE$TAIL, public: PUBLIC_KEEP}\n', ('PUBLIC_KEEP',), False),
         ('C28', 'other:\n  - {token:\n    $OPAQUE$TAIL, public: PUBLIC_KEEP}\n', ('PUBLIC_KEEP',), False),
         ('C29', 'other: public [ literal\ntoken: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C30', 'other: public { literal\ntoken: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C31',
          "other: public can't [ literal\ntoken: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n",
          ('PUBLIC_KEEP',),
          False),
         ('C32', 'notice [stage] token: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C33',
          'other: |\n  [ public literal\ntoken: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n',
          ('PUBLIC_KEEP',),
          False),
         ('C34',
          'other: >\n  # [ public literal\ntoken: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n',
          ('PUBLIC_KEEP',),
          False),
         ('C35', '# [ { } ]\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), True),
         ('C36', 'other: "# [ { } ]"\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), True),
         ('C37', 'token: # [\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), True),
         ('C38', 'other: {token: "$OPAQUE\n# }\n$TAIL\n', (), False),
         ('C39', 'other: {token: [$OPAQUE, # ] }\n$TAIL\n', (), False),
         ('C40', 'token: $OPAQUE\n  # }\n  $TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C41',
          'other:\n  - token: # [\n      $OPAQUE$TAIL\n    public: PUBLIC_KEEP\n',
          ('PUBLIC_KEEP',),
          False),
         ('C42', 'notice token: # [\n  $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C43', '{\n# }\npassword:\n$OPAQUE$TAIL,\npublic: PUBLIC_KEEP\n}', ('public: PUBLIC_KEEP',), False),
         ('C44', '{\n# ]\npassword:\n$OPAQUE$TAIL,\npublic: PUBLIC_KEEP\n}', ('public: PUBLIC_KEEP',), False),
         ('C45', '[{\n# ]}\npassword:\n$OPAQUE$TAIL,\npublic: PUBLIC_KEEP\n}]', ('public: PUBLIC_KEEP',), False),
         ('C46', 'password: [\n# ]\n$OPAQUE$TAIL\n]\npublic: PUBLIC_KEEP', ('public: PUBLIC_KEEP',), False),
         ('C47',
          'password: {\n# }\nchild: $OPAQUE$TAIL\n}\npublic: PUBLIC_KEEP',
          ('public: PUBLIC_KEEP',),
          False),
         ('C48', '# [\npassword:\n  $OPAQUE$TAIL\npublic: PUBLIC_KEEP', ('public: PUBLIC_KEEP',), False),
         ('C49', '# {\npassword:\n  $OPAQUE$TAIL\npublic: PUBLIC_KEEP', ('public: PUBLIC_KEEP',), False),
         ('C50',
          'label: ordinary[\npassword:\n  $OPAQUE$TAIL\npublic: PUBLIC_KEEP',
          ('public: PUBLIC_KEEP',),
          False),
         ('C51',
          'label: ordinary{\npassword:\n  $OPAQUE$TAIL\npublic: PUBLIC_KEEP',
          ('public: PUBLIC_KEEP',),
          False),
         ('C52',
          'label: ordinary#[\npassword:\n  $OPAQUE$TAIL\npublic: PUBLIC_KEEP',
          ('public: PUBLIC_KEEP',),
          False),
         ('C53', 'password: [\n  # ]\n  $OPAQUE$TAIL\n]\npublic: PUBLIC_KEEP', ('public: PUBLIC_KEEP',), False),
         ('C54', '{\n# "}\npassword:\n$OPAQUE$TAIL,\npublic: PUBLIC_KEEP\n}', ('public: PUBLIC_KEEP',), False),
         ('C55',
          'label: "#[{"\npassword:\n  $OPAQUE$TAIL\npublic: PUBLIC_KEEP',
          ('public: PUBLIC_KEEP',),
          False),
         ('C56', 'password: "$OPAQUE$TAIL#]}"\npublic: PUBLIC_KEEP', ('public: PUBLIC_KEEP',), False),
         ('C57', '# token: "$OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C58', '# token: [$OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C59', 'other: { # token: "$OPAQUE$TAIL\npublic: PUBLIC_KEEP}\n', ('PUBLIC_KEEP',), False),
         ('C60', 'other: { # token: [$OPAQUE$TAIL\npublic: PUBLIC_KEEP}\n', ('PUBLIC_KEEP',), False),
         ('C61',
          "label: 'public\n  [ { PUBLIC_SCALAR\n  end'\ntoken: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n",
          ('PUBLIC_KEEP', 'PUBLIC_SCALAR'),
          False),
         ('C62',
          'label: "public\n  { [ PUBLIC_SCALAR\n  end"\ntoken: $OPAQUE$TAIL\npublic: PUBLIC_KEEP\n',
          ('PUBLIC_KEEP', 'PUBLIC_SCALAR'),
          False),
         ('C63', 'other: {token: $OPAQUE#attached$TAIL, public: PUBLIC_KEEP}\n', ('PUBLIC_KEEP',), False),
         ('C64', 'other: |\n  token: "$OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C65', 'other: |\n  token: [$OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C66', 'other: >\n  token: "$OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C67', 'other: >\n  token: [$OPAQUE$TAIL\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C68',
          '{"reason":"password: $OPAQUE, $TAIL","public":"PUBLIC_KEEP","count":17,"nested":[3,true,null]}',
          ('PUBLIC_KEEP',),
          False),
         ('C69',
          '{"reason":"notice password: $OPAQUE, [$TAIL] # '
          'data","public":"PUBLIC_KEEP","count":17,"nested":[3,true,null]}',
          ('PUBLIC_KEEP',),
          False),
         ('C70',
          '{"reason":"password: \\"$OPAQUE, $TAIL\\" '
          'suffix","public":"PUBLIC_KEEP","count":17,"nested":[3,true,null]}',
          ('PUBLIC_KEEP',),
          False),
         ('C71',
          '{"reason":"notice password: $OPAQUE\\n$TAIL\\" '
          'suffix","public":"PUBLIC_KEEP","count":17,"nested":[3,true,null]}',
          ('PUBLIC_KEEP',),
          False),
         ('C72', 'reason: "password: $OPAQUE, [$TAIL] # data"\npublic: PUBLIC_KEEP\n', ('PUBLIC_KEEP',), False),
         ('C73',
          'reason: "notice password: $OPAQUE, [$TAIL] # data"\npublic: PUBLIC_KEEP\n',
          ('PUBLIC_KEEP',),
          False),
         ('C74', "reason: 'password: $OPAQUE, [$TAIL] # data'\npublic: PUBLIC_KEEP\n", ('PUBLIC_KEEP',), False),
         ('C75',
          "reason: 'notice password: $OPAQUE, [$TAIL] # data'\npublic: PUBLIC_KEEP\n",
          ('PUBLIC_KEEP',),
          False),
         ('C76',
          'reason:\n  - "notice password: $OPAQUE, [$TAIL] # data"\npublic: PUBLIC_KEEP\n',
          ('PUBLIC_KEEP',),
          False),
         ('C77',
          "reason:\n  - 'notice password: $OPAQUE, [$TAIL] # data'\npublic: PUBLIC_KEEP\n",
          ('PUBLIC_KEEP',),
          False),
         ('C78', '"PUBLIC_PREFIX password: $OPAQUE, [$TAIL] # data"', ('PUBLIC_PREFIX',), False),
         ('C79', "'PUBLIC_PREFIX password: $OPAQUE, [$TAIL] # data'", ('PUBLIC_PREFIX',), False),
         ('C80',
          '{"reason":"notice \\"password: $OPAQUE, $TAIL\\" '
          'suffix","public":"PUBLIC_KEEP","count":17,"nested":[3,true,null]}',
          ('PUBLIC_KEEP',),
          False),
         ('C81',
          "reason: 'notice ''password: $OPAQUE, $TAIL'' suffix'\npublic: PUBLIC_KEEP\n",
          ('PUBLIC_KEEP',),
          False),
         ('C82',
          '- other: |\n    token: "$OPAQUE$TAIL\n  public: PUBLIC_KEEP\n- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C83',
          '-\n  other: |\n    token: "$OPAQUE$TAIL\n  public: PUBLIC_KEEP\n- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C84',
          '  - other: |\n      token: "$OPAQUE$TAIL\n    public: PUBLIC_KEEP\n  - next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C85',
          '  -\n    other: |\n      token: "$OPAQUE$TAIL\n    public: PUBLIC_KEEP\n  - next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C86',
          '- other: |\n    token: [$OPAQUE$TAIL\n  public: PUBLIC_KEEP\n- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C87',
          '-\n  other: |\n    token: [$OPAQUE$TAIL\n  public: PUBLIC_KEEP\n- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C88',
          '  - other: |\n      token: [$OPAQUE$TAIL\n    public: PUBLIC_KEEP\n  - next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C89',
          '  -\n    other: |\n      token: [$OPAQUE$TAIL\n    public: PUBLIC_KEEP\n  - next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C90',
          '- other: >\n    token: "$OPAQUE$TAIL\n  public: PUBLIC_KEEP\n- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C91',
          '-\n  other: >\n    token: "$OPAQUE$TAIL\n  public: PUBLIC_KEEP\n- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C92',
          '  - other: >\n      token: "$OPAQUE$TAIL\n    public: PUBLIC_KEEP\n  - next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C93',
          '  -\n    other: >\n      token: "$OPAQUE$TAIL\n    public: PUBLIC_KEEP\n  - next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C94',
          '- other: >\n    token: [$OPAQUE$TAIL\n  public: PUBLIC_KEEP\n- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C95',
          '-\n  other: >\n    token: [$OPAQUE$TAIL\n  public: PUBLIC_KEEP\n- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C96',
          '  - other: >\n      token: [$OPAQUE$TAIL\n    public: PUBLIC_KEEP\n  - next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C97',
          '  -\n    other: >\n      token: [$OPAQUE$TAIL\n    public: PUBLIC_KEEP\n  - next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C98',
          '- |\n  token: "$OPAQUE$TAIL\n- public: PUBLIC_KEEP\n- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C99',
          '- - |\n    token: "$OPAQUE$TAIL\n  - public: PUBLIC_KEEP\n- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C100',
          '- >\n  token: "$OPAQUE$TAIL\n- public: PUBLIC_KEEP\n- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C101',
          '- - >\n    token: "$OPAQUE$TAIL\n  - public: PUBLIC_KEEP\n- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'),
          False),
         ('C102',
          '- - other: |\n'
          '      token: "$OPAQUE$TAIL\n'
          '    public: PUBLIC_KEEP\n'
          '  - inner: PUBLIC_INNER\n'
          '- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'inner: PUBLIC_INNER', 'next: PUBLIC_NEXT'),
          False),
         ('C103',
          '- - other: |\n'
          '      token: [$OPAQUE$TAIL\n'
          '    public: PUBLIC_KEEP\n'
          '  - inner: PUBLIC_INNER\n'
          '- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'inner: PUBLIC_INNER', 'next: PUBLIC_NEXT'),
          False),
         ('C104',
          '- - other: >\n'
          '      token: "$OPAQUE$TAIL\n'
          '    public: PUBLIC_KEEP\n'
          '  - inner: PUBLIC_INNER\n'
          '- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'inner: PUBLIC_INNER', 'next: PUBLIC_NEXT'),
          False),
         ('C105',
          '- - other: >\n'
          '      token: [$OPAQUE$TAIL\n'
          '    public: PUBLIC_KEEP\n'
          '  - inner: PUBLIC_INNER\n'
          '- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'inner: PUBLIC_INNER', 'next: PUBLIC_NEXT'),
          False),
         ('C106',
          '- - token: |\n'
          '      $OPAQUE$TAIL\n'
          '    public: PUBLIC_KEEP\n'
          '  - inner: PUBLIC_INNER\n'
          '- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'inner: PUBLIC_INNER', 'next: PUBLIC_NEXT'),
          False),
         ('C107',
          '- -\n'
          '    token: |\n'
          '      $OPAQUE$TAIL\n'
          '    public: PUBLIC_KEEP\n'
          '  - inner: PUBLIC_INNER\n'
          '- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'inner: PUBLIC_INNER', 'next: PUBLIC_NEXT'),
          False),
         ('C108',
          '  - - token: |\n'
          '        $OPAQUE$TAIL\n'
          '      public: PUBLIC_KEEP\n'
          '    - inner: PUBLIC_INNER\n'
          '  - next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'inner: PUBLIC_INNER', 'next: PUBLIC_NEXT'),
          False),
         ('C109',
          '  - -\n'
          '      token: |\n'
          '        $OPAQUE$TAIL\n'
          '      public: PUBLIC_KEEP\n'
          '    - inner: PUBLIC_INNER\n'
          '  - next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'inner: PUBLIC_INNER', 'next: PUBLIC_NEXT'),
          False),
         ('C110',
          '- - token: >\n'
          '      $OPAQUE$TAIL\n'
          '    public: PUBLIC_KEEP\n'
          '  - inner: PUBLIC_INNER\n'
          '- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'inner: PUBLIC_INNER', 'next: PUBLIC_NEXT'),
          False),
         ('C111',
          '- -\n'
          '    token: >\n'
          '      $OPAQUE$TAIL\n'
          '    public: PUBLIC_KEEP\n'
          '  - inner: PUBLIC_INNER\n'
          '- next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'inner: PUBLIC_INNER', 'next: PUBLIC_NEXT'),
          False),
         ('C112',
          '  - - token: >\n'
          '        $OPAQUE$TAIL\n'
          '      public: PUBLIC_KEEP\n'
          '    - inner: PUBLIC_INNER\n'
          '  - next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'inner: PUBLIC_INNER', 'next: PUBLIC_NEXT'),
          False),
         ('C113',
          '  - -\n'
          '      token: >\n'
          '        $OPAQUE$TAIL\n'
          '      public: PUBLIC_KEEP\n'
          '    - inner: PUBLIC_INNER\n'
          '  - next: PUBLIC_NEXT\n',
          ('public: PUBLIC_KEEP', 'inner: PUBLIC_INNER', 'next: PUBLIC_NEXT'),
          False))

    def test_D84_comment_and_literal_context_inventory_and_actual_cli(self):
        module = self.multiline_redactor()
        for case, template, public, empty in self.comment_redaction_cases():
            for boundary in ('\n', '\r\n', '\r', '\x85', '\u2028', '\u2029'):
                with self.subTest(case=case, boundary=repr(boundary)):
                    source = template.replace('$OPAQUE', self.secret).replace('$TAIL', 'CommentOpaqueTail').replace('\n', boundary)
                    output = module.redact_text(source)
                    self.assert_multiline_diagnostic(output, public, empty)
                    self.assertNotIn('CommentOpaqueTail', output)
                    self.assertEqual(module.redact_text(output), output)
                    if empty and 'token:' not in source:
                        self.assertEqual(output, source)
            source = template.replace('$OPAQUE', self.secret).replace('$TAIL', 'CommentOpaqueTail')
            with self.subTest(case=case, boundary='actual-cli'):
                result = self.safe(self.run_command(['python3', str(self.f.runtime / 'workflow-config-resolver.py'),
                                                     'redact-text'], input=source), 0)
                self.assert_multiline_diagnostic(result.stdout + result.stderr, public, empty)
                self.assertNotIn('CommentOpaqueTail', result.stdout + result.stderr)
                self.assertEqual(result.stderr, '')

    def test_D85_comment_context_actual_bash_text_file_and_json(self):
        source_file = self.f.root / 'synthetic-comment-diagnostic.txt'
        for shell in self.compatible_shells():
            for index, (case, template, public, empty) in enumerate(self.comment_redaction_cases()):
                with self.subTest(case=case, shell=shell):
                    boundary = ('\n', '\r\n', '\r', '\x85', '\u2028', '\u2029')[index % 6]
                    source = template.replace('$OPAQUE', self.secret).replace('$TAIL', 'CommentOpaqueTail').replace('\n', boundary)
                    source_file.write_bytes(source.encode())
                    result = self.safe(self.run_command([shell, '-c', 'source "$1"; workflow_redact_text < "$2"; workflow_redact_file "$2" >&2',
                                                        'synthetic', str(self.f.runtime / 'workflow-lib.sh'), str(source_file)]), 0)
                    self.assertEqual(result.stdout, result.stderr)
                    self.assert_multiline_diagnostic(result.stdout + result.stderr, public, empty)
                    self.assertNotIn('CommentOpaqueTail', result.stdout + result.stderr)
            for case, template, public, empty in self.comment_redaction_cases():
                with self.subTest(case=case, shell=shell, mode='json-string'):
                    source = template.replace('$OPAQUE', self.secret).replace('$TAIL', 'CommentOpaqueTail')
                    payload = {'reason': source, 'result': 'clean', 'count': 17, 'nested': [3, True, None]}
                    source_file.write_text(json.dumps(payload))
                    result = self.safe(self.run_command([shell, '-c', 'source "$1"; workflow_redact_json < "$2"; workflow_redact_json < "$2" >&2',
                                                        'synthetic', str(self.f.runtime / 'workflow-lib.sh'), str(source_file)]), 0)
                    self.assertEqual(result.stdout, result.stderr)
                    self.assertNotIn('CommentOpaqueTail', result.stdout + result.stderr)
                    data = json.loads(result.stdout)
                    self.assert_multiline_diagnostic(data['reason'], public, empty)
                    self.assertEqual((data['result'], data['count'], data['nested']), ('clean', 17, [3, True, None]))

    def test_D86_comment_context_all_existing_kv_boundaries(self):
        tail = 'RESULT=clean\nBLOCKING_COUNT=17\nHEAD_SHA=' + 'a' * 40 + '\n'
        for shell in self.compatible_shells():
            for case, template, public, empty in self.comment_redaction_cases():
                source = template.replace('$OPAQUE', self.secret).replace('$TAIL', 'CommentOpaqueTail')
                for helper in ('workflow_diagnostic_kv', 'workflow_diagnostic_kv_escaped', 'workflow_diagnostic_kvs'):
                    with self.subTest(case=case, shell=shell, helper=helper):
                        body = helper + ' DETAIL "$1"; ' + helper + ' DETAIL "$1" >&2; workflow_diagnostic_kv RESULT clean; workflow_diagnostic_kv BLOCKING_COUNT 17; workflow_diagnostic_kv HEAD_SHA ' + 'a' * 40
                        result = self.diagnostic_binary(shell, body, source)
                        self.assertEqual(result.returncode, 0)
                        self.assertNotIn(self.secret.encode(), result.stdout + result.stderr)
                        self.assertNotIn(b'CommentOpaqueTail', result.stdout + result.stderr)
                        for item in public: self.assertIn(item.encode(), result.stdout + result.stderr)
                        self.assertTrue(result.stdout.endswith(tail.encode()))
                        self.assertEqual(result.stdout[:-len(tail)], result.stderr)

    def test_D87_comment_context_before_cap_and_actual_evidence_writer(self):
        source = 'p' * 19940 + '\nother: {\n# }\ntoken:\n' + self.secret + 'CommentOpaqueTail' + 'x' * 100 + ',\npublic: PUBLIC_KEEP\n}\n'
        result = self.safe(self.bash('printf %s ' + shlex.quote(source) + ' | workflow_redact_text | head -c 20000'), 0)
        self.assertNotIn(self.secret[:12], result.stdout + result.stderr)
        self.assertNotIn('CommentOpaqueTail', result.stdout + result.stderr)
        self.assertLessEqual(len(result.stdout.encode()), 20000)
        pr = json.loads(self.f.pr.read_text()); pr['body'] = source; self.f.pr.write_text(json.dumps(pr))
        evidence = self.f.root / 'comment-evidence.json'
        context = self.f.root / 'comment-functional.json'
        result = self.safe(self.local_entry({'result': 'clean', 'comments': 0}, context_capture=context,
                                           LOCAL_AI_REVIEWER_EVIDENCE_FILE=str(evidence)), 0)
        raw = evidence.read_text()
        self.assertNotIn(self.secret[:12], raw + result.stdout + result.stderr)
        self.assertNotIn('CommentOpaqueTail', raw + result.stdout + result.stderr)
        data = json.loads(raw)
        self.assertEqual(data['counts'], {'comments': 0, 'blocking': 0, 'suggestions': 0})
        self.assertEqual(data['result'], 'clean')
        self.assertLessEqual(len(data['context_summary']['pr_body']), 20000)
        self.assertEqual(json.loads(context.read_text())['pr_body'], source[:20000])

    def test_D88_sensitive_assignment_inside_public_raw_json_string(self):
        resolver = str(self.f.runtime / 'workflow-config-resolver.py')
        for case, template, public, empty in self.comment_redaction_cases():
            if case not in ('C68', 'C69', 'C70', 'C71', 'C80'):
                continue
            source = template.replace('$OPAQUE', self.secret).replace('$TAIL', 'CommentOpaqueTail')
            original = json.loads(source)
            for shell in self.compatible_shells():
                with self.subTest(case=case, shell=shell):
                    result = self.safe(self.run_command([shell, '-c', 'source "$1"; workflow_redact_text; workflow_redact_text >&2 <<< "$2"',
                                                        'synthetic', str(self.f.runtime / 'workflow-lib.sh'), source], input=source), 0)
                    self.assertNotIn('CommentOpaqueTail', result.stdout + result.stderr)
                    for channel in (result.stdout, result.stderr):
                        data = json.loads(channel)
                        self.assertEqual((data['public'], data['count'], data['nested']),
                                         (original['public'], original['count'], original['nested']))
                        self.assertIn('[REDACTED]', data['reason'])
            with self.subTest(case=case, mode='raw-json-cli'):
                result = self.safe(self.run_command(['python3', resolver, 'redact-text'], input=source), 0)
                data = json.loads(result.stdout)
                self.assertEqual((data['public'], data['count'], data['nested']),
                                 (original['public'], original['count'], original['nested']))
                self.assertNotIn('CommentOpaqueTail', result.stdout + result.stderr)
                self.assertEqual(result.stderr, '')

    def test_D89_comment_and_block_actual_writer_independent_of_cap(self):
        # A failed cap assertion must not prevent the actual artifact boundary
        # from being exercised independently with its own opacity controls.
        cases = [('flow-comment', 'p' * 19940 + '\nother: {\n# }\ntoken:\n' + self.secret + 'CommentOpaqueTail' + 'x' * 100 + ',\npublic: PUBLIC_KEEP\n}\n', ()),
                 ('compact-block', '- other: |\n    token: "' + self.secret + 'CommentOpaqueTail\n  public: PUBLIC_KEEP\n- next: PUBLIC_NEXT\n',
                  ('public: PUBLIC_KEEP', 'next: PUBLIC_NEXT'))]
        for case, source, public in cases:
            with self.subTest(case=case):
                pr = json.loads(self.f.pr.read_text()); pr['body'] = source; self.f.pr.write_text(json.dumps(pr))
                evidence = self.f.root / ('independent-' + case + '-evidence.json')
                context = self.f.root / ('independent-' + case + '-functional.json')
                result = self.safe(self.local_entry({'result': 'clean', 'comments': 0}, context_capture=context,
                                                   LOCAL_AI_REVIEWER_EVIDENCE_FILE=str(evidence)), 0)
                raw = evidence.read_text()
                self.assertNotIn(self.secret[:12], raw + result.stdout + result.stderr)
                self.assertNotIn('CommentOpaqueTail', raw + result.stdout + result.stderr)
                data = json.loads(raw)
                for marker in public: self.assertIn(marker, data['context_summary']['pr_body'])
                self.assertEqual(data['counts'], {'comments': 0, 'blocking': 0, 'suggestions': 0})
                self.assertEqual(data['result'], 'clean')
                self.assertLessEqual(len(data['context_summary']['pr_body']), 20000)
                # Existing Bash PR_BODY capture strips terminal LF before the functional cap.
                self.assertEqual(json.loads(context.read_text())['pr_body'], source.rstrip('\n')[:20000])

    def configured_source_case(self, state):
        self.f.shared.write_text('review:\n  on_draft:\n    github: [local-ai-reviewer]\n  on_ready:\n    github: []\n')
        self.f.env['WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT'] = str(self.f.external)
        if state == 'malformed':
            self.f.private.write_text('other: [' + self.secret + '\n')
        elif state == 'missing':
            self.f.env['WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT'] = str(self.f.root / 'missing-selected')
            self.f.private.write_text('review:\n  on_draft:\n    github: []\n')
        elif state == 'configured':
            self.f.private.write_text('review:\n  on_draft:\n    github: [local-ai-reviewer]\n  on_ready:\n    github: []\n')
        elif state == 'nonempty':
            self.f.private.write_text('review:\n  on_draft:\n    github: [pr-agent]\n  on_ready:\n    github: [haystack]\n')
        elif state == 'absent':
            self.f.private.write_text('other: true\n')
            self.f.shared.write_text('review:\n  on_draft:\n    github: []\n  on_ready:\n    github: []\n')
        else:
            self.assertEqual(state, 'empty')
            self.f.private.write_text('review:\n  on_draft:\n    github: []\n  on_ready:\n    github: []\n')
        return ('HARNESS_MODE=1 source ' + shlex.quote(str(self.f.runtime / 'pr-review-loop.sh')) + '\n'
                'unset repo_review_platforms platforms\nconfig_file=' + shlex.quote(str(self.f.shared)) + '\n'
                'loop_head_sha=' + 'a' * 40 + '\n')

    def test_D90_configured_platform_success_and_real_source_failures(self):
        for shell in self.compatible_shells():
            for state in ('absent', 'empty', 'nonempty', 'malformed', 'missing'):
                with self.subTest(shell=shell, state=state):
                    body = self.configured_source_case(state)
                    result = self.run_command([shell, '-c', body + 'reviewer_loop_repo_configured_platforms'])
                    self.safe(result, 2 if state in ('malformed', 'missing') else 0)
                    self.assertEqual(result.stdout, 'pr-agent\nhaystack\n' if state == 'nonempty' else '')
                    if state not in ('malformed', 'missing'): self.assertEqual(result.stderr, '')
                    else: self.assertIn('configuration:', result.stderr)
            with self.subTest(shell=shell, state='cached-list'):
                body = self.configured_source_case('empty')
                result = self.safe(self.run_command([shell, '-c', body + 'repo_review_platforms=(local-ai-reviewer pr-agent); reviewer_loop_repo_configured_platforms']), 0)
                self.assertEqual(result.stdout, 'local-ai-reviewer\npr-agent\n')

    def test_D91_expensive_gate_source_failure_precedes_force_policy(self):
        controls = r'''
expensive_gate_local_ai_head_current() { printf '1\n'; }
expensive_gate_local_ai_result_clean() { printf '1\n'; }
expensive_gate_check_peers() { :; }
expensive_gate_unresolved_threads_status() { printf 'ok 0 %s\n' "$loop_head_sha"; }
expensive_gate_baseline_checks_status() { printf 'green %s\n' "$loop_head_sha"; }
expensive_gate_deferral_count() { printf '0\n'; }
expensive_gate_max_deferrals=3
'''
        for shell in self.compatible_shells():
            for state in ('empty', 'configured', 'malformed', 'missing'):
                for force in (0, 1):
                    with self.subTest(shell=shell, state=state, force=force):
                        body = self.configured_source_case(state) + controls
                        body += 'PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS=' + str(force) + '\ngate_status=0\nexpensive_reviewer_gate 1993 codex-github "$loop_head_sha" || gate_status=$?\nexit "$gate_status"'
                        result = self.run_command([shell, '-c', body])
                        expected = 2 if state in ('malformed', 'missing') else (1 if state == 'empty' and not force else 0)
                        self.safe(result, expected)
                        if expected == 2:
                            self.assertEqual(result.stdout, '')
                            self.assertIn('configuration:', result.stderr)
                        else:
                            values = dict(line.split('=', 1) for line in result.stdout.splitlines())
                            self.assertEqual(values['EXPENSIVE_GATE_RESULT'], 'forced' if state == 'empty' and force else ('deferred' if state == 'empty' else 'dispatched'))
                            self.assertEqual(values['EXPENSIVE_GATE_REASON'], 'local_reviewer_not_configured' if state == 'empty' else '')

    def test_D92_actual_platform_loop_empty_ready_and_failed_selected_source(self):
        source = (self.f.runtime / 'pr-review-loop.sh').read_text()
        begin = source.index('for index in "${!platforms[@]}"; do')
        end = source.index('\n# --- Automated Reviewer Loop Summary comment ---', begin)
        actual_loop = source[begin:end]
        executable = self.f.bin / 'synthetic-ready-reviewer'
        executable.write_text('#!/bin/sh\nprintf "%s\\0" "$@" >> "$SYNTHETIC_DISPATCH_ARGS"\n'
                              'if [ "$1" = pr-agent ]; then case "$SYNTHETIC_SOURCE_STATE" in\n'
                              'malformed) printf "other: [%s\\n" "$SYNTHETIC_OPAQUE" > "$SYNTHETIC_SELECTED";;\n'
                              'missing) rm "$SYNTHETIC_SELECTED";; esac; fi\n'
                              'printf "RESULT=clean\\nCOMMENT_COUNT=0\\nBLOCKING_COUNT=0\\nSUGGESTION_COUNT=0\\n"\n')
        executable.chmod(0o755)
        for shell in self.compatible_shells():
            for state in ('absent', 'empty', 'malformed', 'missing'):
                with self.subTest(shell=shell, state=state):
                    body = self.configured_source_case('absent' if state == 'absent' else 'empty')
                    log = self.f.root / 'ready-dispatch-argv.bin'; log.unlink(missing_ok=True)
                    ready = self.f.root / 'ready-transition'; ready.unlink(missing_ok=True)
                    self.f.env.update(SYNTHETIC_DISPATCH_ARGS=str(log), SYNTHETIC_SOURCE_STATE=state,
                                      SYNTHETIC_SELECTED=str(self.f.private), SYNTHETIC_OPAQUE=self.secret)
                    body += r'''
repo_review_platforms=()
platforms=(pr-agent haystack)
phase_after_clean_platforms=(haystack)
phase_after_clean_enabled=1; phase_after_clean_started=0
compare_mode=0; compare_first_blocking_result=
pr_number=1993; branch_name=feature/1993-fixture
aggregate_result=clean; aggregate_status=0; aggregate_reason=; aggregate_output=
platform_result_records=(); platform_reviewed_heads=(); platform_result_tokens=()
reviewer_loop_prior_history_payload_from_pr() { printf '{"entries":[]}\n'; }
reviewer_loop_second_local_pass_confirm_live_head() { return 0; }
reviewer_loop_platform_pre_dispatch() { reviewer_loop_pre_dispatch_action=dispatch; }
reviewer_wait_budget_for_platform() { printf '1 synthetic unchanged\n'; }
reviewer_poll_interval_resolve() { printf '1\n'; }
reviewer_loop_rewait_prepare_platform() { :; }
reviewer_loop_head_refs_prepare_platform() { :; }
reviewer_loop_timing_begin() { :; }
reviewer_loop_timing_end() { :; }
reviewer_loop_process_platform_output() { aggregate_result=clean; aggregate_status=0; last_platform="$1"; }
run_platform_review() { synthetic-ready-reviewer "$@"; }
'''
                    body += 'ensure_pr_ready_for_ready_phase() { touch ' + shlex.quote(str(ready)) + '; }\n'
                    body += actual_loop + '\nprintf "RESULT=%s\\nSTATUS=%s\\n" "$aggregate_result" "$aggregate_status"\nexit "$aggregate_status"\n'
                    result = self.run_command([shell, '-c', body])
                    self.safe(result, 2 if state in ('malformed', 'missing') else 0)
                    items = log.read_bytes().split(b'\0')[:-1]
                    expected = [b'pr-agent', b'1993', b'feature/1993-fixture', b'1', b'1']
                    if state not in ('malformed', 'missing'):
                        expected += [b'haystack', b'1993', b'feature/1993-fixture', b'1', b'1']
                    self.assertEqual(items, expected)
                    self.assertEqual(ready.exists(), state not in ('malformed', 'missing'))
                    self.assertIn('RESULT=escalate\n' if state in ('malformed', 'missing') else 'RESULT=clean\n', result.stdout)
                    if state in ('malformed', 'missing'): self.assertNotIn('RESULT=clean\n', result.stdout)

    def test_D93_head_evidence_and_terminal_publication_fail_closed(self):
        source = (self.f.runtime / 'pr-review-loop.sh').read_text()
        skipped_start = source.index('if [ -z "$last_platform" ]; then\n')
        skipped = source[skipped_start:source.index('\n# --- Compare mode:', skipped_start)]
        normal_start = source.index("# Persist this cycle's reviewer_loop_history.v1 ledger entry BEFORE")
        normal = source[normal_start:source.index('\n# Append compare-mode metrics row', normal_start)]
        tail_start = source.index('print_kv LOCAL_SECOND_PASS "${local_second_pass:-0}"', normal_start)
        final = normal + '\n' + source[tail_start:]
        for shell in self.compatible_shells():
            for state in ('empty', 'configured', 'malformed', 'missing'):
                for boundary, actual in (('renderer', 'render_status=0\nreviewer_loop_emit_local_ai_head_evidence_keys || render_status=$?\nexit "$render_status"'), ('skipped', skipped), ('final', final)):
                    with self.subTest(shell=shell, state=state, boundary=boundary):
                        body = self.configured_source_case(state)
                        summary = self.f.root / 'owned-summary-argv.bin'; summary.unlink(missing_ok=True)
                        body += 'platform_reviewed_heads=("local-ai-reviewer:$loop_head_sha")\n'
                        body += '_post_review_summary() { printf "%s\\0" "$@" >> ' + shlex.quote(str(summary)) + '; }\n'
                        body += r'''
sync_reviewer_failed_label() { :; }
reviewer_loop_persist_failure_should_escalate() { return 1; }
pr_number=1993; last_platform=pr-agent
aggregate_result=clean; aggregate_reason=; aggregate_output=
total_comment_count=0; total_blocking_count=0; total_suggestion_count=0
_summary_platform_list=pr-agent; aggregate_advisory_labels=; aggregate_possible_issue_eval_outcome=
phase_after_clean_enabled=1; phase_after_clean_platform_list=haystack
phase_after_clean_started=1; phase_after_clean_net_new_blocker=0; phase_after_clean_blocking_platform=
pre_after_clean_only=0; advisory_checks_section=
'''
                        if boundary == 'skipped': body += 'last_platform=\n'
                        result = self.run_command([shell, '-c', body + actual])
                        for stream in (result.stdout, result.stderr): self.assertNotIn(self.secret, stream)
                        if state in ('malformed', 'missing'):
                            self.assertFalse(summary.exists(), 'configuration failure must precede owned summary publication')
                            self.assertNotIn('LOCAL_AI_CONFIGURED=0', result.stdout)
                            self.assertNotIn('RESULT=clean', result.stdout)
                            self.assertNotIn('RESULT=skipped', result.stdout)
                            self.assertEqual(result.returncode, 2)
                            self.assertEqual(result.stdout, '')
                            self.assertIn('configuration:', result.stderr)
                        else:
                            self.safe(result, 0)
                            self.assertEqual(summary.exists(), boundary != 'renderer')
                            self.assertIn('LOCAL_AI_CONFIGURED=' + ('1' if state == 'configured' else '0') + '\n', result.stdout)
                            self.assertIn('LOCAL_AI_HEAD_CURRENT=' + ('1' if state == 'configured' else '') + '\n', result.stdout)
                            if boundary == 'renderer': self.assertEqual(len(result.stdout.splitlines()), 3)
                            else: self.assertIn('RESULT=' + ('skipped' if boundary == 'skipped' else 'clean') + '\n', result.stdout)

    def test_D94_cached_expensive_gate_preserves_baseline_source_errors(self):
        source = (self.f.runtime / 'pr-review-loop.sh').read_text()
        begin = source.index('for index in "${!platforms[@]}"; do')
        end = source.index('\n# --- Automated Reviewer Loop Summary comment ---', begin)
        actual_loop = source[begin:end]
        head = 'a' * 40
        payload = self.f.root / 'baseline-checks.json'
        payload.write_text(json.dumps({'headRefOid': head, 'statusCheckRollup': [
            {'__typename': 'CheckRun', 'name': 'Haystack / Review', 'status': 'COMPLETED',
             'conclusion': 'FAILURE', 'workflowName': 'review'},
            {'__typename': 'CheckRun', 'name': 'unit-tests', 'status': 'COMPLETED',
             'conclusion': 'SUCCESS', 'workflowName': 'tests'},
        ]}))
        for shell in self.compatible_shells():
            for state in ('configured', 'empty', 'malformed', 'missing', 'unavailable'):
                for force in (0, 1):
                    for boundary in ('gate', 'predispatch', 'ready-loop'):
                        with self.subTest(shell=shell, state=state, force=force, boundary=boundary):
                            body = self.configured_source_case(state if state != 'unavailable' else 'configured')
                            self.f.shared.write_text('review:\n  on_draft:\n    github: [bugbot]\n  on_ready:\n    github: []\n')
                            if state in ('configured', 'unavailable'):
                                self.f.private.write_text('review:\n  on_draft:\n    github: [haystack]\n  on_ready:\n    github: []\n')
                            calls = self.f.root / 'baseline-argv.bin'; calls.unlink(missing_ok=True)
                            dispatch = self.f.root / 'cached-dispatch-argv.bin'; dispatch.unlink(missing_ok=True)
                            ready = self.f.root / 'cached-ready-argv.bin'; ready.unlink(missing_ok=True)
                            body += 'gh() { printf "%s\\0" "$@" >> ' + shlex.quote(str(calls)) + '; '
                            body += ('return 1; }\n' if state == 'unavailable' else 'cat ' + shlex.quote(str(payload)) + '; }\n')
                            body += r'''
repo_review_platforms=(local-ai-reviewer pr-agent)
platforms=(codex-github)
EXPENSIVE_REVIEWER_PLATFORMS=(codex-github)
platform_reviewed_heads=("local-ai-reviewer:$loop_head_sha")
platform_peer_evidence=("local-ai-reviewer|clean|")
expensive_gate_check_peers() { :; }
expensive_gate_unresolved_threads_status() { printf 'ok 0 %s\n' "$loop_head_sha"; }
expensive_gate_deferral_count() { printf '0\n'; }
expensive_gate_max_deferrals=3
pr_number=1993; branch_name=feature/1993-fixture
stage_skip_enabled=0
aggregate_result=clean; aggregate_status=0; aggregate_reason=; aggregate_output=
platform_result_records=(); platform_result_tokens=()
phase_after_clean_enabled=1; phase_after_clean_started=0
phase_after_clean_platforms=(codex-github)
compare_mode=0; compare_first_blocking_result=
reviewer_loop_second_local_pass_before_ready_gate() { return 0; }
reviewer_wait_budget_for_platform() { printf '1 synthetic unchanged\n'; }
reviewer_poll_interval_resolve() { printf '1\n'; }
reviewer_loop_rewait_prepare_platform() { :; }
reviewer_loop_head_refs_prepare_platform() { :; }
reviewer_loop_timing_begin() { :; }
reviewer_loop_timing_end() { :; }
reviewer_loop_process_platform_output() { aggregate_result=clean; aggregate_status=0; last_platform="$1"; }
'''
                            body += 'PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS=' + str(force) + '\n'
                            body += 'run_platform_review() { printf "%s\\0" "$@" >> ' + shlex.quote(str(dispatch)) + '; printf "RESULT=clean\\nCOMMENT_COUNT=0\\nBLOCKING_COUNT=0\\nSUGGESTION_COUNT=0\\n"; }\n'
                            body += 'ensure_pr_ready_for_ready_phase() { printf "%s\\0" "$@" >> ' + shlex.quote(str(ready)) + '; }\n'
                            if boundary == 'gate':
                                body += 'gate_status=0\nexpensive_reviewer_gate 1993 codex-github "$loop_head_sha" || gate_status=$?\nexit "$gate_status"\n'
                            elif boundary == 'predispatch':
                                body += 'reviewer_loop_platform_pre_dispatch codex-github 1\nprintf "ACTION=%s\\nAGGREGATE=%s\\n" "$reviewer_loop_pre_dispatch_action" "$aggregate_result"\nexit "$aggregate_status"\n'
                            else:
                                body += actual_loop + '\nprintf "AGGREGATE=%s\\n" "$aggregate_result"\nexit "$aggregate_status"\n'
                            result = self.run_command([shell, '-c', body])
                            source_error = state in ('malformed', 'missing')
                            permitted = state == 'configured' or (not source_error and force == 1)
                            expected = 2 if source_error and boundary == 'gate' else (0 if permitted else 1)
                            self.safe(result, expected)
                            self.assertEqual(self.f.log.exists(), False)
                            args = calls.read_bytes().split(b'\0')[:-1]
                            one_call = [b'pr', b'view', b'1993', b'--json', b'statusCheckRollup,headRefOid']
                            self.assertEqual(args, one_call * (2 if boundary == 'ready-loop' and permitted else 1))
                            if source_error:
                                self.assertIn('configuration:', result.stderr)
                                self.assertNotIn('EXPENSIVE_GATE_RESULT=forced', result.stdout)
                                self.assertNotIn('EXPENSIVE_GATE_RESULT=dispatched', result.stdout)
                                if boundary == 'gate': self.assertEqual(result.stdout, '')
                                else: self.assertIn('AGGREGATE=needs_fixes\n', result.stdout)
                            else:
                                self.assertEqual(result.stderr, '' if boundary != 'ready-loop' or not permitted else 'INFO: expensive-gate ready preflight passed for codex-github (earlier_buckets); full gate still runs before dispatch\n')
                                values = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
                                self.assertEqual(values['EXPENSIVE_GATE_RESULT'], 'dispatched' if state == 'configured' else ('forced' if force else 'deferred'))
                                self.assertEqual(values['EXPENSIVE_GATE_REASON'], '' if state == 'configured' else ('baseline_checks_not_green' if state == 'empty' else 'evidence_unavailable_checks'))
                            self.assertEqual(ready.exists(), boundary == 'ready-loop' and permitted)
                            self.assertEqual(dispatch.exists(), boundary == 'ready-loop' and permitted)
                            if dispatch.exists():
                                self.assertEqual(dispatch.read_bytes().split(b'\0')[:-1], [b'codex-github', b'1993', b'feature/1993-fixture', b'1', b'1'])
                                self.assertEqual(ready.read_bytes(), b'1993\0')

    def test_D95_completion_report_retains_late_selected_source_failure(self):
        source = (self.f.runtime / 'item-completion-self-check.sh').read_text()
        def actual_function(name):
            start = source.index(name + '() {')
            return source[start:source.index('\n}', start) + 2]
        start = source.index('      if ! is_true "$require_review_summary"; then')
        branch = source[start:source.index('\n      if is_true "$require_review_threads"; then', start)]
        terminal = source[source.index('if [ "$unavailable_required_count" -gt 0 ]; then'):]
        definitions = '\n'.join(actual_function(n) for n in ('is_true', 'md_escape', 'add_row'))
        definitions += '\n' + actual_function('local_ai_reviewer_configured').replace('local_ai_reviewer_configured()', 'original_local_ai_reviewer_configured()', 1)
        original = actual_function('configured_review_platforms').replace('configured_review_platforms()', 'original_configured_review_platforms()', 1)
        for shell in self.compatible_shells():
            for state in ('configured', 'empty', 'late-malformed', 'late-missing', 'not-claimed'):
                with self.subTest(shell=shell, state=state):
                    self.configured_source_case('empty' if state == 'empty' else 'configured')
                    self.f.shared.write_text('review:\n  on_draft:\n    github: [pr-agent]\n  on_ready:\n    github: []\n')
                    statuses = self.f.root / 'completion-reader-statuses'; statuses.write_text('')
                    argv = self.f.root / 'completion-reader-argv.bin'; argv.write_bytes(b'')
                    helper = self.f.root / 'completion-helper-status'; helper.unlink(missing_ok=True)
                    self.f.env.update(SYNTHETIC_SELECTED=str(self.f.private), SYNTHETIC_OPAQUE=self.secret,
                                      SYNTHETIC_COMPLETION_STATE=state, SYNTHETIC_COMPLETION_STATUSES=str(statuses),
                                      SYNTHETIC_COMPLETION_ARGV=str(argv), SYNTHETIC_COMPLETION_HELPER=str(helper))
                    body = 'source ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n' + definitions + '\n' + original + '\n'
                    body += r'''
local_ai_reviewer_configured() {
  local helper_status=0
  original_local_ai_reviewer_configured || helper_status=$?
  printf '%s' "$helper_status" > "$SYNTHETIC_COMPLETION_HELPER"
  return "$helper_status"
}
configured_review_platforms() {
  local reader_status=0 count
  printf '%s\0' "$@" >> "$SYNTHETIC_COMPLETION_ARGV"
  original_configured_review_platforms "$@" || reader_status=$?
  printf '%s\n' "$reader_status" >> "$SYNTHETIC_COMPLETION_STATUSES"
  count="$(wc -l < "$SYNTHETIC_COMPLETION_STATUSES")"
  if [ "$count" -eq 1 ]; then
    case "$SYNTHETIC_COMPLETION_STATE" in
      late-missing) rm "$SYNTHETIC_SELECTED" ;;
      late-malformed) printf 'other: [%s\n' "$SYNTHETIC_OPAQUE" > "$SYNTHETIC_SELECTED" ;;
    esac
  fi
  return "$reader_status"
}
fetch_latest_review_summary() { printf 'synthetic-evidence\n'; }
extract_reviewer_loop_history_json() { printf '{"entries":[{"platform_results":[{"platform":"local-ai-reviewer","result":"clean"}],"reviewed_heads":[{"platform":"local-ai-reviewer","reviewed_head":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]}]}\n'; }
rows=(); failure_count=0; discrepancy_count=0; unavailable_required_count=0
require_review_summary=true; require_review_threads=false
pr_repo=fixture/public; pr_number=1993; pr_head_oid=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
issue=1993; stage=fixture; expected_branch=feature/1993-fake; resolved_worktree_path=fake
'''
                    if state == 'not-claimed': body += 'require_review_summary=false\n'
                    body += branch + '\n' + terminal
                    result = self.run_command([shell, '-c', body])
                    error = state.startswith('late-')
                    self.safe(result, 1 if error else 0)
                    self.assertEqual([int(v) for v in statuses.read_text().splitlines()], [0, 2] if error else ([] if state == 'not-claimed' else [0, 0]))
                    self.assertEqual(argv.read_bytes().split(b'\0')[:-1], [] if state == 'not-claimed' else [str(self.f.shared).encode()] * 2)
                    self.assertEqual(helper.read_text() if helper.exists() else 'not_called', '2' if error else ('1' if state == 'empty' else ('not_called' if state == 'not-claimed' else '0')))
                    self.assertFalse(self.f.log.exists())
                    if error:
                        self.assertIn('- Result: unavailable_required\n', result.stdout)
                        self.assertIn('| pull_request.local_reviewer_head | unavailable_required | source resolution failed |', result.stdout)
                        self.assertNotIn('- Result: verified', result.stdout)
                        self.assertNotIn('unavailable_optional', result.stdout)
                        self.assertIn('configuration:', result.stderr)
                    else:
                        self.assertIn('- Result: verified\n', result.stdout)
                        self.assertEqual(result.stderr, '')
                        self.assertIn('| pull_request.local_reviewer_head | ' + ('verified | ledger head matches live headRefOid' if state == 'configured' else ('unavailable_optional | not claimed' if state == 'not-claimed' else 'unavailable_optional | local-ai-reviewer not configured')), result.stdout)


    def diagnostic_actual_function(self, file, name):
        source = (self.f.runtime / file).read_text()
        start = source.index(name + '() {')
        return source[start:source.index('\n}', start) + 2]

    def test_D96_actual_local_root_native_failure_and_success(self):
        import shutil
        (self.f.checkout / 'REVIEW.md').write_text('# Synthetic contract\n')
        self.gh_script('case "$*" in "pr diff"*) echo REVIEW.md;; "repo view"*) echo fixture/repo;; "pr view"*) cat "$SYNTHETIC_PR";; "auth status"*) exit 0;; *) exit 99;; esac\n')
        capture = self.f.root / 'root-review-capture.json'
        command = self.f.bin / 'root-review-command'
        command.write_text('#!/usr/bin/env python3\nimport json,os,sys\nopen(os.environ["ROOT_CAPTURE"],"w").write(json.dumps({"cwd":os.getcwd(),"args":sys.argv[1:]}))\nprint(json.dumps({"result":"clean","comments":[]}))\n')
        command.chmod(0o755)
        real_git = shutil.which('git', path=self.f.env['PATH'])
        git = self.f.bin / 'git'
        git.write_text('#!/bin/sh\ncase "$*" in *"remote get-url origin"*) echo https://github.com/fixture/repo.git; exit 0;; esac\nexec ' + shlex.quote(real_git) + ' "$@"\n'); git.chmod(0o755)
        self.f.env.update(LOCAL_AI_REVIEWER_COMMAND=shlex.quote(str(command)) + ' first ' + shlex.quote('two words'),
                          LOCAL_AI_REVIEWER_GRAPH_STRATEGY='none', ROOT_CAPTURE=str(capture))
        for shell in self.compatible_shells():
            for state in ('missing', 'valid'):
                with self.subTest(shell=shell, state=state):
                    capture.unlink(missing_ok=True)
                    root = self.f.root / ('password=' + self.secret) / 'missing' if state == 'missing' else self.f.checkout
                    result = self.safe(self.run_command([shell, str(self.f.runtime / 'local-ai-reviewer.sh'), '1993', 'fixture', 'repo', '--repo-root', str(root)]), 2 if state == 'missing' else 0)
                    self.assertFalse(self.f.log.exists())
                    if state == 'missing':
                        self.assertFalse(capture.exists())
                        self.assertIn('invalid_repo_root', result.stdout)
                        self.assertIn('configuration validation error', result.stderr)
                    else:
                        self.assertIn('RESULT=clean\n', result.stdout)
                        payload = json.loads(capture.read_text())
                        self.assertEqual(payload, {'cwd': str(self.f.checkout.resolve()), 'args': ['first', 'two words']})

    def test_D97_all_changed_native_root_statements(self):
        import re
        cases = [('N02', 'coderabbit-cli-reviewer.sh', 'REPO_ROOT', 0, 'cwd'), ('N03', 'item-completion-self-check.sh', 'repo_root', 0, 'cwd'), ('N04', 'pr-ci-loop.sh', 'repo_root', 0, 'cwd'), ('N05', 'pr-review-loop.sh', 'repo_root', 0, 'cwd'), ('N06', 'pr-review-loop.sh', 'review_repo_root', 0, 'cwd'), ('N07', 'pr-review-loop.sh', 'review_repo_root', 1, 'cwd'), ('N08', 'discover-workflow-state.sh', 'repo_root', 1, 'cwd'), ('N09', 'workflow-next-action.sh', 'repo_root', 1, 'cwd'), ('N10', 'workflow-batch-plan.sh', 'repo_root', 1, 'cwd'), ('N11', 'workflow-batch-lanes.sh', 'repo_root', 1, 'cwd'), ('N12', 'reviewer-preflight.sh', 'repo_root', 0, 'preflight'), ('N13', 'reviewer-preflight.sh', 'work_dir', 0, 'preflight'), ('N14', 'post-merge-cleanup.sh', 'top', 0, 'physical'), ('N15', 'post-merge-cleanup.sh', 'dir', 0, 'physical'), ('N16', 'post-merge-cleanup.sh', 'HUB_REPO_ROOT', 0, 'cwd'), ('N17', 'post-merge-cleanup.sh', 'CLEANUP_REPO_ROOT', 0, 'cwd'), ('N18', 'post-merge-cleanup.sh', 'CLEANUP_REPO_ROOT', 1, 'physical'), ('N19', 'post-merge-cleanup.sh', 'base_worktree', 0, 'physical'), ('N20', 'post-merge-cleanup.sh', 'tracker_repo_root', 0, 'physical'), ('N21', 'post-merge-cleanup.sh', 'HUB_REPO_ROOT', 1, 'slug'), ('N22', 'post-merge-cleanup.sh', 'HUB_REPO_ROOT', 2, 'cwd'), ('N23', 'post-merge-cleanup.sh', 'HUB_REPO_ROOT', 3, 'cwd'), ('N24', 'post-merge-cleanup.sh', 'HUB_REPO_ROOT', 4, 'cwd')]
        for shell in self.compatible_shells():
            for name, file, variable, ordinal, transport in cases:
                source = (self.f.runtime / file).read_text().splitlines()
                statements = [s for s in source if re.search(r'\bcd\s+(?:--\s+)?"\$' + re.escape(variable) + '"', s)]
                statement = statements[ordinal]
                for state in ('missing', 'valid'):
                    for context in ('errexit', 'conditional'):
                        with self.subTest(shell=shell, site=name, state=state, context=context):
                            root = self.f.root / ('password=' + self.secret) / 'missing' if state == 'missing' else self.f.root / 'valid directory with spaces'
                            if state == 'valid': root.mkdir(exist_ok=True)
                            argv = self.f.root / 'native-root-argv.bin'; argv.write_bytes(b'')
                            cwd = self.f.root / 'native-root-cwd'; cwd.unlink(missing_ok=True)
                            self.f.env.update(NATIVE_TARGET=str(root), NATIVE_ARGV=str(argv), NATIVE_CWD=str(cwd))
                            body = 'set -euo pipefail\nsource ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n'
                            body += r'''
trap 'exit_status=$?; builtin pwd -P > "$NATIVE_CWD"; exit "$exit_status"' EXIT
cd() {
  local arg matched=0
  for arg in "$@"; do [ "$arg" != "$NATIVE_TARGET" ] || matched=1; done
  if [ "$matched" -eq 1 ]; then printf '%s\0' "$@" >> "$NATIVE_ARGV"; fi
  builtin cd "$@"
}
fail() { printf 'configuration: checkout access error\n' >&2; return 3; }
gh() { printf 'fixture/repo\n'; }
'''
                            body += variable + '=' + shlex.quote(str(root)) + '\n'
                            body += 'actual_boundary() {\n' + statement + '\n}\n'
                            if context == 'conditional':
                                body += 'status=0\nactual_boundary || status=$?\n[ "$status" -eq 0 ] || exit "$status"\n'
                            else: body += 'actual_boundary\n'
                            if transport == 'preflight' or (transport == 'physical' and not statement.lstrip().startswith('(')):
                                output_variable = statement.strip().split('=', 1)[0]
                                body += 'printf "%s\\n" "$' + output_variable + '"\n'
                            elif transport == 'slug': body += 'printf "%s\\n" "$slug"\n'
                            elif transport == 'cwd': body += 'builtin pwd -P\n'
                            expected = 0 if state == 'valid' else (3 if transport == 'preflight' else 1)
                            result = self.safe(self.run_command([shell, '-c', body]), expected)
                            expected_args = ([b'--'] if re.search(r'\bcd\s+--\s+', statement) else []) + [str(root).encode()]
                            self.assertEqual(argv.read_bytes().split(b'\0')[:-1], expected_args)
                            self.assertEqual(cwd.read_text().strip(), str(root.resolve()) if state == 'valid' and transport == 'cwd' else str(self.f.checkout))
                            self.assertEqual(result.stdout, '' if state == 'missing' else ('fixture/repo\n' if transport == 'slug' else str(root.resolve()) + '\n'))
                            if state == 'valid': self.assertEqual(result.stderr, '')
                            self.assertFalse(self.f.log.exists())

    def test_D98_loop_rejected_settings_preserve_numeric_payloads(self):
        prefix = 'HARNESS_MODE=1 source ' + shlex.quote(str(self.f.runtime / 'pr-review-loop.sh')) + '\n'
        for shell in self.compatible_shells():
            for function, envkey, default in (
                    ('reviewer_loop_resolve_max_cycles', 'PR_REVIEW_LOOP_MAX_CYCLES', '10'),
                    ('reviewer_loop_resolve_max_total_cycles', 'PR_REVIEW_LOOP_MAX_TOTAL_CYCLES', '25'),
                    ('expensive_gate_resolve_max_deferrals', 'PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS', '3')):
                for state in ('invalid-config', 'invalid-env', 'valid', 'empty'):
                    with self.subTest(shell=shell, function=function, state=state):
                        value = self.secret if state.startswith('invalid') else ('7' if state == 'valid' else '')
                        body = prefix + envkey + '=' + shlex.quote(value if state == 'invalid-env' or function == 'expensive_gate_resolve_max_deferrals' else '') + '\n'
                        body += function + (' ' + shlex.quote(value) if function != 'expensive_gate_resolve_max_deferrals' else '')
                        result = self.safe(self.run_command([shell, '-c', body]), 0)
                        self.assertEqual(result.stdout, ('7' if state == 'valid' else default) + '\n')
                        self.assertEqual(bool(result.stderr), state.startswith('invalid'))
                        if result.stderr: self.assertRegex(result.stderr, r'^WARN: configuration validation error; key=[A-Za-z0-9_.-]+\n$')
            for state, settings, stdout in (
                    ('retries-bound', 'CODERABBIT_RATE_LIMIT_MAX_RETRIES=12345678901234567', 'BUDGET_INVARIANT=violated\nRESULT=escalate\nREASON=execution_budget_misconfigured\n'),
                    ('wait-bound', 'CODERABBIT_RATE_LIMIT_WAIT=23456789012345678', 'BUDGET_INVARIANT=violated\nRESULT=escalate\nREASON=execution_budget_misconfigured\n'),
                    ('budget-bound', 'PR_REVIEW_LOOP_EXECUTION_BUDGET=34567890123456789', 'BUDGET_INVARIANT=violated\nRESULT=escalate\nREASON=execution_budget_misconfigured\n'),
                    ('combination', 'CODERABBIT_RATE_LIMIT_MAX_RETRIES=0000000004\nCODERABBIT_RATE_LIMIT_WAIT=0000000900\nPR_REVIEW_LOOP_EXECUTION_BUDGET=0000001800', 'BUDGET_EXECUTION_SECONDS=1800\nBUDGET_WORST_CASE_RATE_LIMIT_WAIT_SECONDS=3600\nBUDGET_INVARIANT=violated\nRESULT=escalate\nREASON=execution_budget_misconfigured\n'),
                    ('valid', 'CODERABBIT_RATE_LIMIT_MAX_RETRIES=4\nCODERABBIT_RATE_LIMIT_WAIT=900\nPR_REVIEW_LOOP_EXECUTION_BUDGET=5400', 'BUDGET_EXECUTION_SECONDS=5400\nBUDGET_WORST_CASE_RATE_LIMIT_WAIT_SECONDS=3600\nBUDGET_INVARIANT=ok\n')):
                with self.subTest(shell=shell, budget=state):
                    result = self.safe(self.run_command([shell, '-c', prefix + settings + '\n_check_execution_budget']), 0 if state == 'valid' else 1)
                    self.assertEqual(result.stdout, stdout)
                    if state != 'valid':
                        self.assertRegex(result.stderr, r'^ERROR: configuration validation error; key=[A-Z_]+\.?\n$')
                        for line in settings.splitlines(): self.assertNotIn(line.split('=', 1)[1], result.stdout + result.stderr)
                    else: self.assertEqual(result.stderr, '')
            for state, text, call, expected, warns in (
                    ('invalid-value', 'review:\n  wait_budgets:\n    bugbot: OPAQUE\n', 'reviewer_wait_budget_resolve bugbot', '2400 default none\n', True),
                    ('unknown-key', 'review:\n  wait_budgets:\n    OPAQUE: 77\n    bugbot: 77\n', 'reviewer_wait_budget_config_warnings', '', True),
                    ('empty', 'review:\n  wait_budgets:\n    bugbot:\n', 'reviewer_wait_budget_resolve bugbot', '2400 default none\n', True),
                    ('flow', 'review:\n  wait_budgets: {bugbot: 77}\n', 'reviewer_wait_budget_config_warnings', '', True),
                    ('claude-cap', 'review:\n  wait_budgets:\n    claude-code-action: 54321\n', 'reviewer_wait_budget_resolve claude-code-action', '1200 default none\n', True),
                    ('valid', 'review:\n  wait_budgets:\n    bugbot: 77\n', 'reviewer_wait_budget_resolve bugbot', '77 configured none\n', False),
                    ('missing', 'review:\n  wait_budgets:\n    bugbot: 77\n', 'reviewer_wait_budget_configured devin', '', False)):
                with self.subTest(shell=shell, wait=state):
                    self.f.shared.write_text(text.replace('OPAQUE', self.secret))
                    result = self.safe(self.run_command([shell, '-c', prefix + 'config_file=' + shlex.quote(str(self.f.shared)) + '\n' + call]), 0)
                    self.assertEqual(result.stdout, expected)
                    self.assertEqual(bool(result.stderr), warns)
                    self.assertNotIn('54321', result.stdout + result.stderr)
                    if warns and state != 'flow': self.assertRegex(result.stderr, r'^WARN: configuration validation error; key=[A-Za-z0-9_.-]+\n$')
            result = self.safe(self.run_command([shell, '-c', prefix + 'config_file=/dev/null\nCODEX_GITHUB_MAX_WAIT=456789012345\nreviewer_wait_budget_configured codex-github']), 0)
            self.assertEqual(result.stdout, ''); self.assertNotIn('456789012345', result.stderr)
            self.assertIn('configuration validation error; key=CODEX_GITHUB_MAX_WAIT', result.stderr)
            result = self.safe(self.run_command([shell, str(self.f.runtime / 'pr-review-loop.sh'), '1993', '--max-wait', self.secret]), 64)
            self.assertIn('configuration validation error; key=--max-wait', result.stderr)

    def test_D99_companion_rejected_setting_emitters(self):
        cases = [
            ('local-ai-reviewer.sh', '--timeout', self.secret, 2),
            ('coderabbit-cli-reviewer.sh', '--timeout', self.secret, 3),
            ('haystack-reviewer.sh', '--timeout', self.secret, 3),
            ('codex-github-reviewer.sh', '--poll-interval', self.secret, 2),
            ('codex-github-reviewer.sh', '--max-wait', self.secret, 2),
            ('codex-github-reviewer.sh', '--pre-trigger-wait', self.secret, 2),
            ('codex-github-reviewer.sh', '--max-retriggers', self.secret, 2),
            ('claude-code-action-reviewer.sh', '--poll-interval', self.secret, 2),
            ('claude-code-action-reviewer.sh', '--poll-interval', '54321', 2),
            ('claude-code-action-reviewer.sh', '--max-wait', self.secret, 2),
            ('claude-code-action-reviewer.sh', '--max-wait', '65432', 2)]
        for shell in self.compatible_shells():
            for file, option, value, status in cases:
                with self.subTest(shell=shell, file=file, option=option, value_kind='opaque' if value == self.secret else 'numeric-bound'):
                    result = self.safe(self.run_command([shell, str(self.f.runtime / file), '1993', 'fixture', 'repo', option, value]), status)
                    self.assertNotIn(value, result.stdout + result.stderr)
                    self.assertIn('configuration validation error; key=' + option, result.stderr)
                    self.assertFalse(self.f.log.exists())
            for file, variable, key, status in (
                    ('local-ai-reviewer.sh', 'LOCAL_AI_REVIEWER_TIMEOUT', '--timeout', 2),
                    ('coderabbit-cli-reviewer.sh', 'CODERABBIT_CLI_REVIEW_TIMEOUT', '--timeout', 3),
                    ('haystack-reviewer.sh', 'HAYSTACK_REVIEWER_TIMEOUT', '--timeout', 3),
                    ('haystack-reviewer.sh', 'HAYSTACK_POLL_INTERVAL', 'HAYSTACK_POLL_INTERVAL', 3),
                    ('codex-github-reviewer.sh', 'CODEX_GITHUB_PRE_TRIGGER_WAIT', '--pre-trigger-wait', 2)):
                with self.subTest(shell=shell, setting=variable):
                    previous = self.f.env.get(variable); self.f.env[variable] = self.secret
                    try: result = self.safe(self.run_command([shell, str(self.f.runtime / file), '1993', 'fixture', 'repo']), status)
                    finally:
                        if previous is None: self.f.env.pop(variable, None)
                        else: self.f.env[variable] = previous
                    self.assertIn('configuration validation error; key=' + key, result.stderr)
            prefix = 'HARNESS_MODE=1 source ' + shlex.quote(str(self.f.runtime / 'local-ai-reviewer.sh')) + '\n'
            result = self.safe(self.run_command([shell, '-c', prefix + 'LOCAL_AI_REVIEWER_COMMAND=\nLOCAL_AI_REVIEWER_DISABLE_DEFAULT=0\nLOCAL_AI_REVIEWER_BACKEND=' + shlex.quote(self.secret) + '\nresolve_local_ai_reviewer_command']), 1)
            self.assertIn('configuration validation error; key=LOCAL_AI_REVIEWER_BACKEND', result.stderr)
            for backend in ('codex', 'http'):
                with self.subTest(shell=shell, backend=backend):
                    body = prefix + 'LOCAL_AI_REVIEWER_COMMAND=\nLOCAL_AI_REVIEWER_DISABLE_DEFAULT=0\nLOCAL_AI_REVIEWER_BACKEND=' + backend + '\nresolve_local_ai_reviewer_command\n'
                    body += 'test -n "$LOCAL_AI_REVIEWER_COMMAND"\nprintf "BACKEND_RESOLVED\\n"\n'
                    result = self.safe(self.run_command([shell, '-c', body]), 0)
                    self.assertEqual(result.stdout, 'BACKEND_RESOLVED\n')
                    self.assertIn('defaulted to bundled', result.stderr)
            self.gh_script('case "$*" in "pr diff"*) echo REVIEW.md;; "repo view"*) echo fixture/repo;; "pr view"*) cat "$SYNTHETIC_PR";; "auth status"*) exit 0;; *) exit 99;; esac\n')
            (self.f.checkout / 'REVIEW.md').write_text('# Synthetic contract\n')
            command = self.f.bin / 'never-review'
            command.write_text('#!/bin/sh\nexit 99\n'); command.chmod(0o755)
            self.f.env.update(LOCAL_AI_REVIEWER_COMMAND=str(command), LOCAL_AI_REVIEWER_GRAPH_STRATEGY=self.secret)
            try: result = self.safe(self.run_command([shell, str(self.f.runtime / 'local-ai-reviewer.sh'), '1993', 'fixture', 'repo']), 2)
            finally: self.f.env.pop('LOCAL_AI_REVIEWER_GRAPH_STRATEGY', None)
            self.assertIn('configuration validation error; key=LOCAL_AI_REVIEWER_GRAPH_STRATEGY', result.stderr)
            self.assertFalse(self.f.log.exists())
            # Success controls use the actual validation regions, without invoking a real reviewer.
            for file, begin, end, setup in (
                    ('codex-github-reviewer.sh', 'case "$POLL_INTERVAL" in', '# ── Pre-flight', 'POLL_INTERVAL=1; MAX_WAIT=1; PRE_TRIGGER_WAIT=0; MAX_RETRIGGERS=0'),
                    ('claude-code-action-reviewer.sh', 'case "$POLL_INTERVAL" in', '# ── Pre-flight', 'POLL_INTERVAL=300; MAX_WAIT=3600'),
                    ('haystack-reviewer.sh', 'case "$TIMEOUT" in', '# ── GitHub App', 'TIMEOUT=1; POLL_INTERVAL=1'),
                    ('coderabbit-cli-reviewer.sh', 'case "$TIMEOUT" in', 'rate_limit_policy_from_file()', 'TIMEOUT=1')):
                with self.subTest(shell=shell, valid_region=file):
                    source = (self.f.runtime / file).read_text(); start = source.index(begin); region = source[start:source.index(end, start)]
                    result = self.safe(self.run_command([shell, '-c', 'source ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n' + setup + '\n' + region + '\nprintf "VALID_UNCHANGED\\n"']), 0)
                    self.assertEqual(result.stdout, 'VALID_UNCHANGED\n'); self.assertEqual(result.stderr, '')

    def test_D100_boolean_and_lifecycle_metadata_preserve_policy(self):
        self.f.private.unlink(missing_ok=True)  # This shared-policy control starts with no private override.
        self.f.env.pop("WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT", None)
        prefix = 'source ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n'
        boolean_defs = self.diagnostic_actual_function('item-completion-self-check.sh', 'is_true') + '\n' + self.diagnostic_actual_function('item-completion-self-check.sh', 'validate_bool_option')
        for shell in self.compatible_shells():
            result = self.safe(self.run_command([shell, str(self.f.runtime / 'item-completion-self-check.sh'),
                '--issue', '1993', '--branch', 'feature/1993-fixture', '--stage', 'synthetic',
                '--worktree-path', str(self.f.checkout), '--repo-root', str(self.f.checkout), '--require-clean', self.secret]), 64)
            self.assertIn('configuration validation error; key=--require-clean', result.stderr)
            for function in ('is_true', 'validate_bool_option'):
                for value in (self.secret, 'true', 'false', ''):
                    with self.subTest(shell=shell, function=function, value_kind='opaque' if value == self.secret else value):
                        call = function + (' --require-clean ' if function == 'validate_bool_option' else ' ') + shlex.quote(value)
                        expected = 64 if value == self.secret else (1 if function == 'is_true' and value in ('false', '') else 0)
                        result = self.safe(self.run_command([shell, '-c', prefix + boolean_defs + '\n' + call]), expected)
                        self.assertEqual(result.stdout, '')
                        if value == self.secret: self.assertRegex(result.stderr, r'^ERROR: configuration validation error(?:; key=--require-clean)?\n$')
                        else: self.assertEqual(result.stderr, '')
            for duplicate in (False, True):
                with self.subTest(shell=shell, duplicate=duplicate):
                    self.f.shared.write_text('review:\n  on_draft:\n    runner: [' + self.secret + ']\n    github: [' + (self.secret if duplicate else 'pr-agent') + ']\n  on_ready:\n    github: []\n')
                    loop = 'HARNESS_MODE=1 source ' + shlex.quote(str(self.f.runtime / 'pr-review-loop.sh')) + '\n'
                    result = self.safe(self.run_command([shell, '-c', loop + 'emit_review_lifecycle_duplicate_warnings ' + shlex.quote(str(self.f.shared))]), 0)
                    self.assertEqual(result.stdout, '')
                    self.assertEqual(result.stderr, 'WARN: configuration validation error; key=review\n' if duplicate else '')
                    # Configuration payload remains functional and unmasked when explicitly requested.
                    result = self.run_command([shell, '-c', prefix + 'workflow_config_review_on_draft_runner ' + shlex.quote(str(self.f.shared))])
                    self.assertEqual(result.returncode, 0); self.assertEqual(result.stdout, self.secret + '\n'); self.assertEqual(result.stderr, '')


if __name__ == '__main__':
    unittest.main(verbosity=2)

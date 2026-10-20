#!/usr/bin/env python3
"""Binding D01-D47: synthetic paired-channel runtime/publication diagnostics."""
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

    def local_entry(self, payload, stderr=None, status=0, **env):
        (self.f.checkout / 'REVIEW.md').write_text('# Synthetic reviewer contract\n')
        self.gh_script('case "$*" in "pr diff"*) echo README.md;; "repo view"*) echo fixture/repo;; "pr view"*) cat "$SYNTHETIC_PR";; "auth status"*) exit 0;; *) exit 99;; esac\n')
        command = self.f.bin / 'synthetic-review'
        command.write_text('#!/bin/sh\nprintf "%s\\n" ' + shlex.quote(json.dumps(payload) if isinstance(payload, dict) else payload) + '\n' +
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


if __name__ == '__main__':
    unittest.main(verbosity=2)

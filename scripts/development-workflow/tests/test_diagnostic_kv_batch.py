#!/usr/bin/env python3
"""Synthetic per-value batching controls; no reviewer, config or network access."""
from pathlib import Path
import importlib.util
import json
import shlex
import sys
import unittest

SPEC = importlib.util.spec_from_file_location('batch_fixtures', Path(__file__).with_name('test_runner_diagnostic_emitters.py'))
fixtures = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fixtures)


class DiagnosticBatch(unittest.TestCase):
    def setUp(self):
        self.harness = fixtures.RunnerDiagnosticEmitters(methodName='runTest')
        self.harness.setUp()
        self.addCleanup(self.harness.doCleanups)
        self.f = self.harness.f
        self.secret = self.harness.secret

    def native(self, body, *values):
        return self.harness.run_command(['/bin/bash', '-c', 'source "$1"; shift;\n' + body,
                                        'synthetic', str(self.f.runtime / 'workflow-lib.sh'), *values])

    def framed(self, raw):
        # Binary subprocess input is needed to exercise invalid UTF-8, rather
        # than failing in the test's own string encoder before the real CLI.
        import subprocess
        return subprocess.run([sys.executable, '-S', str(self.f.runtime / 'workflow-config-resolver.py'),
                               'redact-text', '--kv'], input=raw, env=self.f.env,
                              cwd=self.f.checkout, capture_output=True, timeout=10)

    def rejected(self, raw):
        result = self.framed(raw)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, b'')
        self.assertEqual(result.stderr, b'ERROR: diagnostic sanitization failed\n')

    def test_B01_native_value_isolation_order_stripping_and_both_channels(self):
        pairs = ['DETAIL', 'first\nsecond\n\n', 'EMPTY', '', 'PEM',
                 '-----BEGIN PRIVATE KEY-----\n' + self.secret,
                 'RESULT', 'refused', 'BLOCKING_FINDING_COUNT', '17', 'HEAD_SHA', 'a' * 40,
                 'TAIL', ' spaces  ', 'DETAIL', 'token=' + self.secret]
        legacy = self.native('while [ "$#" -gt 0 ]; do workflow_diagnostic_kv "$1" "$2"; shift 2; done', *pairs)
        self.assertEqual(legacy.returncode, 0, legacy.stderr)
        result = self.native('workflow_diagnostic_kvs "$@"; workflow_diagnostic_kvs "$@" >&2', *pairs)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, legacy.stdout)
        self.assertEqual(result.stderr, legacy.stdout)
        self.assertNotIn(self.secret, result.stdout + result.stderr)
        self.assertIn('DETAIL=first\nsecond\nEMPTY=\nPEM=[REDACTED]\nRESULT=refused\n', result.stdout)
        self.assertIn('BLOCKING_FINDING_COUNT=17\nHEAD_SHA=' + 'a' * 40 + '\nTAIL= spaces  \n', result.stdout)

    def test_B02_missing_terminal_frame_fails_closed(self):
        self.rejected(b'DETAIL\0token=fabricatedDiagnosticValue')

    def test_B03_odd_pairs_fail_closed_after_valid_prefix(self):
        self.rejected(b'RESULT\0owned\0DETAIL\0')

    def test_B04_invalid_utf8_fails_closed(self):
        self.rejected(b'RESULT\0owned\0DETAIL\0\xfffabricatedDiagnosticValue\0')

    def test_B05_invalid_late_key_publishes_no_prefix(self):
        self.rejected(b'RESULT\0owned\0bad=token\0fabricatedDiagnosticValue\0')

    def test_B06_empty_frame_and_helper_odd_arguments_fail_closed(self):
        self.rejected(b'')
        result = self.native('workflow_diagnostic_kvs RESULT owned DETAIL')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, '')
        self.assertEqual(result.stderr, 'ERROR: diagnostic sanitization failed\n')

    def fail_filter(self):
        python = self.f.bin / 'python3'
        python.write_text('#!/bin/sh\ncase "$2 $3" in "redact-text --kv")\n'
                          'echo token=fabricatedDiagnosticValue; echo fabricatedDiagnosticValue >&2; exit 7;;\nesac\n'
                          'exec ' + shlex.quote(sys.executable) + ' "$@"\n')
        python.chmod(0o755)

    def test_B07_filter_failure_drops_untrusted_stdout_and_stderr(self):
        self.fail_filter()
        result = self.native('workflow_diagnostic_kvs RESULT owned DETAIL safe')
        self.assertEqual(result.returncode, 2)
        self.assertEqual(result.stdout, '')
        self.assertEqual(result.stderr, 'ERROR: diagnostic sanitization failed\n')

    def test_B08_real_readiness_verdict_preserves_fields_and_json(self):
        report = fixtures.fixtures.function_text('apply-readiness-labels.sh', 'emit_verdict')
        pem = '-----BEGIN PRIVATE KEY-----\n' + self.secret
        body = report + '\n' + '; '.join(k + '=' + shlex.quote(v) for k, v in {
            'result': 'refused', 'reason': pem, 'pr_number': '1993', 'repo': 'fixture/repo',
            'label': 'ready-for-human-review', 'head_sha': 'a' * 40, 'reviewer_report': pem,
            'blocking_count': '17', 'pending_count': '2', 'failing_count': '3',
            'dry_run': 'true', 'json_output': 'true',
        }.items()) + '\nemit_verdict\nemit_verdict >&2\n'
        result = self.native(body)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, result.stderr)
        self.assertNotIn(self.secret, result.stdout + result.stderr)
        self.assertIn('REASON=[REDACTED]\nPR_NUMBER=1993\n', result.stdout)
        self.assertIn('REVIEWER_REPORT=[REDACTED]\nBLOCKING_FINDING_COUNT=17\n', result.stdout)
        data = json.loads(result.stdout.splitlines()[-1])
        self.assertEqual(data['headSha'], 'a' * 40)
        self.assertEqual(data['blockingFindingCount'], 17)
        self.assertEqual(data['pendingCheckCount'], 2)
        self.assertEqual(data['reason'], '[REDACTED]')
        self.assertEqual(data['reviewerReport'], '[REDACTED]')

    def ownership(self, expected):
        return self.harness.run_command(['/bin/bash', str(self.f.runtime / 'pr-ownership-guard.sh'), '--pr', '1993',
                                         '--expected-branch', expected, '--expected-head-repo', 'fixture/repo',
                                         '--repo', 'fixture/repo'])

    def test_B09_real_ownership_filter_failure_never_publishes_owned(self):
        payload = {'headRefName': 'synthetic', 'headRepositoryOwner': {'login': 'fixture'},
                   'headRepository': {'name': 'repo'}, 'isCrossRepository': False}
        self.harness.gh_script('printf "%s\\n" ' + shlex.quote(json.dumps(payload)) + '\n')
        good = self.ownership('synthetic')
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertIn('RESULT=owned\n', good.stdout)
        self.fail_filter()
        failed = self.ownership('synthetic')
        self.assertEqual(failed.returncode, 2)
        self.assertEqual(failed.stdout, '')
        self.assertEqual(failed.stderr, 'ERROR: diagnostic sanitization failed\n')

    def test_B10_real_ownership_pem_field_preserves_following_controls(self):
        payload = {'headRefName': 'feature/-----BEGIN PRIVATE KEY-----' + self.secret, 'headRepositoryOwner': {'login': 'fixture'},
                   'headRepository': {'name': 'repo'}, 'isCrossRepository': False}
        self.harness.gh_script('printf "%s\\n" ' + shlex.quote(json.dumps(payload)) + '\n')
        result = self.ownership('synthetic')
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertNotIn(self.secret, result.stdout + result.stderr)
        self.assertIn('EXPECTED_BRANCH=synthetic\nEXPECTED_BRANCH_SOURCE=argument\n', result.stdout)
        self.assertIn('PR_HEAD_BRANCH=feature/[REDACTED]\nPR_HEAD_REPO=fixture/repo\n', result.stdout)
        self.assertIn('MISMATCH=branch\nREQUIRED_ACTION=', result.stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)

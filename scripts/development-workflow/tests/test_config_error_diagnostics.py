#!/usr/bin/env python3
"""AC4 binding K01-K26 plus55 real consumers; fabricated opaque content only."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import sys
import unittest

SPEC = importlib.util.spec_from_file_location('config_fixtures', Path(__file__).with_name('test_private_source_consumers.py'))
fixtures = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fixtures)
ROOT = Path(__file__).resolve().parents[3]


def function(file, name):
    lines = file.read_text().splitlines(keepends=True)
    start = next(i for i, line in enumerate(lines) if re.match(re.escape(name) + r'\(\)\s*\{', line))
    delimiter = None
    for i in range(start + 1, len(lines)):
        if delimiter:
            if lines[i].strip() == delimiter:
                delimiter = None
            continue
        match = re.search(r'<<-?\s*[\'\"]?([A-Za-z_][A-Za-z0-9_]*)', lines[i])
        if match:
            delimiter = match[1]
        elif lines[i].rstrip() == '}':
            return ''.join(lines[start:i + 1])
    raise AssertionError('public function boundary missing: ' + name)


class ConfigErrorDiagnostics(unittest.TestCase):
    def setUp(self):
        self.f = fixtures.PrivateSourceConsumers(methodName='runTest')
        self.f.setUp()
        self.addCleanup(self.f.doCleanups)
        home = self.f.root / 'fake-home'; home.mkdir()
        import yaml
        self.f.env.update(HOME=str(home), PYTHONPATH=str(Path(yaml.__file__).resolve().parent.parent))
        self.opaque = 'opaqueConfigurationMaterial'
        self.bad = 'unknownOpaqueKey: [opaqueConfigurationMaterial\n'
        self.f.private.write_text('review:\n  on_draft:\n    runner: [codex]\n')
        self.valid_manifest = 'mode_scopes:\n  shared:\n  hub_only:\n  product_repo_injection:\ncategories:\n  always_sync:\n    - path: README.md\n      mode_scope: shared\n'

    def run_command(self, args, *, input=None):
        child = subprocess.Popen(args, cwd=self.f.checkout, env=self.f.env, text=True,
                                 stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 start_new_session=True)
        try:
            stdout, stderr = child.communicate(input, timeout=40)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL); child.communicate(); raise
        return subprocess.CompletedProcess(args, child.returncode, stdout, stderr)

    def cli(self, file, *args, input=None):
        return self.run_command([sys.executable, str(self.f.runtime / file), *args], input=input)

    def safe(self, result, status, *, locator=True):
        self.assertEqual(result.returncode, status, result.stdout + result.stderr)
        combined = result.stdout + result.stderr
        for value in (self.opaque, 'unknownOpaqueKey', 'opaqueUnknownPath', str(self.f.external)):
            self.assertNotIn(value, combined)
        self.assertNotIn(str(self.f.checkout), result.stderr)
        self.assertNotIn('Traceback', combined)
        self.assertNotIn('usage:', combined)
        if locator:
            self.assertRegex(combined, r'configuration:|local-source|invalid YAML|configuration unreadable')
        self.assertFalse(self.f.log.exists(), 'unexpected mutation/provider call')
        return result

    def test_K01_metadata_api_and_selected_syntax(self):
        body = '''import runpy,sys
api=runpy.run_path(sys.argv[1])
class OpaqueError(ValueError):
 def __str__(self): raise AssertionError("must not stringify opaque exception")
for error in (OpaqueError(), api['ConfigError']('opaqueConfigurationMaterial', key='unknownOpaqueKey', line=7)):
 text=api['format_config_error'](error)
 print(text);print(text,file=sys.stderr)
'''
        self.safe(self.run_command([sys.executable, '-c', body, str(self.f.runtime / 'workflow-config-resolver.py')]), 0)
        self.f.private.write_text(self.bad)
        result = self.safe(self.cli('workflow-config-resolver.py', 'yaml-source-check', '--file', str(self.f.private)), 2)
        self.assertIn('line=1', result.stderr)
        self.assertNotIn(str(self.f.private), result.stderr)

    def test_K02_legacy_source_error(self):
        self.f.shared.write_text('unknownOpaqueKey: [opaqueConfigurationMaterial\n')
        result = self.safe(self.cli('workflow-config-resolver.py', 'mode', '--repo-root', str(self.f.checkout)), 0, locator=False)
        # Legacy shared reader remains permissive; selected private syntax is strict.
        self.f.private.write_text(self.bad)
        self.safe(self.cli('workflow-config-resolver.py', 'review-overrides', '--repo-root', str(self.f.checkout)), 2)

    def test_K03_modern_error_reports_and_snapshot(self):
        self.f.private.write_text(self.bad)
        for command in ('review-effective', 'review-github-effective'):
            result = self.cli('workflow-config-resolver.py', command, '--repo-root', str(self.f.checkout))
            self.assertEqual(result.returncode, 0, result.stderr)
            payload = json.loads(result.stdout)
            self.assertEqual(payload['unreadable_file'], '')
            self.assertNotIn(self.opaque, payload['unreadable_detail'])
            self.assertNotIn(str(self.f.private), payload['unreadable_detail'])
            self.assertIn('invalid YAML', payload['unreadable_detail'])
            self.assertEqual(payload['local_override_file'], str(self.f.private))
            self.assertNotIn('shared-policy-sentinel', json.dumps(payload))
            if command == 'review-effective':
                self.assertEqual(payload['effective_runner'], [])
                self.assertEqual(payload['effective_runner_state'], 'malformed')
        destination = self.f.root / 'staged'; destination.mkdir()
        self.safe(self.cli('workflow-config-resolver.py', 'review-snapshot', '--repo-root', str(self.f.checkout),
                           '--destination', str(destination)), 2)

    def test_K04_repository_schema(self):
        self.f.shared.write_text('mode: opaqueConfigurationMaterial\n')
        self.safe(self.cli('workflow-config-resolver.py', 'mode', '--repo-root', str(self.f.checkout)), 2)
        self.f.shared.write_text('mode: [opaqueConfigurationMaterial]\n')
        self.safe(self.cli('workflow-config-resolver.py', 'mode', '--repo-root', str(self.f.checkout)), 1)

    def test_K05_model_error_FILE_empty_functional_SOURCE_FILE_retained(self):
        valid = '# adf-models-dsh: v1\nmodels:\n  dsh:\n    tiers:\n      balanced:\n        provider: synthetic\n        model: synthetic\n# adf-models-dsh: end\n'
        self.f.shared.write_text(valid)
        good = self.cli('workflow-config-resolver.py', 'model-route', '--runner', 'dsh', '--role', 'developer', '--repo-root', str(self.f.checkout), '--json')
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertEqual(json.loads(good.stdout)['SOURCE_FILE'], str(self.f.shared))
        self.f.shared.write_text(valid.replace('provider: synthetic', 'unknownOpaqueKey: opaqueConfigurationMaterial'))
        for command in ('validate', 'model-route', 'model-routes'):
            args = [] if command == 'validate' else ['--runner', 'dsh']
            if command == 'model-route': args += ['--role', 'developer']
            result = self.safe(self.cli('workflow-config-resolver.py', command, *args, '--repo-root', str(self.f.checkout), '--json'), 2)
            diagnostic = json.loads(result.stderr)
            self.assertEqual(set(diagnostic), {'CODE', 'FILE', 'FIELD', 'MESSAGE'})
            self.assertEqual(diagnostic['FILE'], '')
            self.assertEqual(diagnostic['CODE'], 'unknown_field')

    def coderabbit(self, mode):
        source = self.f.checkout / '.coderabbit.yaml'
        source.write_text('reviews:\n  auto_review:\n    enabled: true\nopaqueUnknownPath: [opaqueConfigurationMaterial\n')
        result = self.safe(self.cli('reviewer_preflight_coderabbit.py', '--mode', mode, str(source)), 3)
        self.assertIn('line=5', result.stderr)
        source.write_bytes(b'opaqueConfigurationMaterial: \xff\n')
        self.safe(self.cli('reviewer_preflight_coderabbit.py', '--mode', mode, str(source)), 3)
        source.write_text('reviews:\n  auto_review:\n    enabled: opaqueConfigurationMaterial\n')
        self.safe(self.cli('reviewer_preflight_coderabbit.py', '--mode', mode, str(source)), 3)
        source.write_text('reviews:\n  auto_review:\n    enabled: true\n')
        good = self.cli('reviewer_preflight_coderabbit.py', '--mode', mode, str(source))
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertIn('true', good.stdout)

    def test_K06_coderabbit_enabled_bool(self): self.coderabbit('enabled-bool')
    def test_K07_coderabbit_full_json(self): self.coderabbit('full-json')

    def test_K08_input_builder(self):
        source = self.f.root / 'opaqueUnknownPath.json'; source.write_text('{"unknownOpaqueKey": opaqueConfigurationMaterial')
        self.safe(self.cli('reviewer_preflight_build_input.py', '--runner-json', str(source), '--output', str(self.f.root / 'bundle.json')), 1)

    def test_K09_classifier_json(self):
        source = self.f.root / 'opaqueUnknownPath.json'; source.write_bytes(b'{"opaqueConfigurationMaterial": "\xff"}')
        self.safe(self.cli('reviewer_preflight.py', '--input-json', str(source)), 1)

    def shell_function(self, file, names, body):
        definitions = '\n'.join(function(self.f.runtime / file, name) for name in names)
        prefix = 'source ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\nSCRIPT_DIR=' + shlex.quote(str(self.f.runtime)) + '\n'
        return self.run_command(['/bin/bash', '-c', prefix + definitions + '\n' + body])

    def test_K10_prelude_embedded_parser(self):
        self.f.shared.write_text('opaqueConfigurationMaterial\n')
        body = 'workflow_effective_config_file() { printf "%s\\n" ' + shlex.quote(str(self.f.shared)) + '; }; read_guardrails_json'
        self.safe(self.shell_function('run-bounded-prelude.sh', ['sanitize_guardrails_parse_detail', 'read_guardrails_json'], body), 2)
        self.f.shared.write_text('guardrails:\n  mode: manual\n')
        good = self.shell_function('run-bounded-prelude.sh', ['sanitize_guardrails_parse_detail', 'read_guardrails_json'], body)
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertEqual(json.loads(good.stdout)['section'], 'present')

    def test_K11_router_embedded_parser(self):
        self.f.shared.write_text('broken opaqueConfigurationMaterial\n')
        self.f.env['AI_DEV_WORKFLOW_CONFIG_FILE'] = str(self.f.shared)
        self.safe(self.shell_function('run-work-router.sh', ['read_guardrails_config'], 'read_guardrails_config'), 0)
        self.f.shared.write_text('guardrails:\n  mode: delegated\n')
        good = self.shell_function('run-work-router.sh', ['read_guardrails_config'], 'read_guardrails_config; printf "%s" "$GUARDRAILS_MODE"')
        self.assertEqual(good.stdout, 'delegated')

    def test_K12_risk_paths(self):
        self.f.shared.write_text(self.bad)
        result = self.safe(self.cli('workflow-risk-paths.py', '--repo-root', str(self.f.checkout), input='{}'), 2)
        self.assertIn('key=guardrails.risk_paths', result.stderr)

    def test_K13_portfolio_config_before_any_scan(self):
        self.f.shared.write_text(self.bad)
        snapshot = self.f.root / 'snapshot.json'; snapshot.write_text('{}')
        self.safe(self.cli('workflow-portfolio-scan.py', '--repo-root', str(self.f.checkout), '--scan-snapshot', str(snapshot)), 1)
        self.assertFalse(self.f.log.exists())

    def test_K14_routing_config_json(self):
        source = self.f.root / 'opaqueUnknownPath.json'; source.write_text('{"opaqueConfigurationMaterial":')
        self.safe(self.cli('work-item-repository-routing.py', '--config', str(source), '--json'), 2)
        source.write_text('{"mode":"single_repo"}')
        good = self.cli('work-item-repository-routing.py', '--config', str(source), '--json')
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertEqual(json.loads(good.stdout)['outcome_code'], 'single_repo')
        for mode, selected, outcome, key in ((self.opaque, [], 'unsupported_mode', 'mode'), ('workflow_hub', [self.opaque], 'ambiguous_target', 'workflow_hub.product_repos[].name')):
            source.write_text(json.dumps({'mode': mode, 'configured_product_repo_keys': ['known']}))
            args = ['--config', str(source), '--json']
            for value in selected: args += ['--selected-product-repo-key', value]
            result = self.cli('work-item-repository-routing.py', *args)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stderr, '')
            payload = json.loads(result.stdout)
            self.assertNotIn(self.opaque, payload['stop_reason'])
            self.assertIn('key=' + key, payload['stop_reason'])
            self.assertEqual(payload['outcome_code'], outcome)
            self.assertFalse(payload['continue_allowed'])
            self.assertEqual(payload['configured_product_repo_keys'], ['known'])
            self.assertEqual(payload['selected_product_repo_keys'], selected)
            self.assertRegex(payload['fingerprint'], '^sha256:[0-9a-f]{64}$')


    def test_K15_skeleton_manifest(self):
        source = self.f.root / 'opaqueUnknownPath.yaml'; source.write_text('skeleton_role: opaqueConfigurationMaterial\n')
        args = ('--repo-root', str(self.f.checkout), '--parser-root', str(self.f.checkout), '--skeleton-manifest', str(source), '--skip-sync-manifest')
        self.safe(self.cli('validate-workflow-hub-skeletons.py', *args), 1)
        source.write_text('skeleton_role: workflow_hub\nentries:\n  - path: fake.md\n    mode_scope: shared\n    generated_example: true\n')
        good = self.cli('validate-workflow-hub-skeletons.py', *args)
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertEqual(good.stdout.strip(), 'VALID')

    def test_K16_manifest_selector(self):
        source = self.f.root / 'opaqueUnknownPath.yaml'; source.write_text(self.valid_manifest.replace('mode_scope: shared', 'mode_scope: opaqueConfigurationMaterial'))
        args = ('--manifest', str(source), '--role', 'single_repo')
        self.safe(self.cli('select-sync-manifest-entries.py', *args), 1)
        source.write_text(self.valid_manifest)
        good = self.cli('select-sync-manifest-entries.py', *args)
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertIn('SELECTED_COUNT=1', good.stdout)

    def test_K17_manifest_coverage_forward(self):
        source = self.f.root / 'opaqueUnknownPath.yaml'; source.write_text(self.valid_manifest.replace('mode_scope: shared', 'mode_scope: opaqueConfigurationMaterial'))
        self.safe(self.cli('check-sync-manifest-coverage.py', '--repo-root', str(self.f.checkout), '--manifest', str(source), '--role', 'single_repo'), 2)

    def test_K18_sync_manifest_forward_without_apply(self):
        selector = self.f.runtime / 'select-sync-manifest-entries.py'
        trace = self.f.root / 'manifest-reader-reached'
        text = selector.read_text()
        marker = 'def parse_manifest(path: Path) -> tuple[set[str], list[ManifestEntry]]:\n'
        self.assertIn(marker, text)
        selector.write_text(text.replace(marker, marker + '    Path(' + repr(str(trace)) + ').write_text("reached")\n'))
        source = self.f.checkout / 'sync-manifest.yaml'; source.write_text(self.valid_manifest.replace('mode_scope: shared', 'mode_scope: opaqueConfigurationMaterial'))
        for args in (['git', 'add', 'sync-manifest.yaml'], ['git', 'commit', '-qm', 'Synthetic malformed manifest']):
            result = self.run_command(args); self.assertEqual(result.returncode, 0, result.stderr)
        consumer = self.f.root / 'consumer'
        cloned = self.run_command(['git', 'clone', '-q', str(self.f.checkout), str(consumer)])
        self.assertEqual(cloned.returncode, 0, cloned.stderr)
        sha = self.run_command(['git', 'rev-parse', 'HEAD']).stdout.strip()
        args = ('preview', '--template-root', str(self.f.checkout), '--consumer-root', str(consumer), '--template-ref', sha, '--template-id', 'fixture/repo', '--role', 'single_repo', '--plan', str(self.f.root / 'plan.json'))
        self.safe(self.cli('sync-template-merge.py', *args), 2)
        self.assertFalse((self.f.root / 'plan.json').exists())
        self.assertTrue(trace.is_file(), 'actual CLI never reached manifest parser')
        trace.unlink()
        source.write_text(self.valid_manifest)
        for command in (['git', 'add', 'sync-manifest.yaml'], ['git', 'commit', '-qm', 'Restore synthetic valid manifest']):
            self.assertEqual(self.run_command(command).returncode, 0)
        new_sha = self.run_command(['git', 'rev-parse', 'HEAD']).stdout.strip()
        args = tuple(new_sha if value == sha else value for value in args)
        valid = self.cli('sync-template-merge.py', *args)
        self.assertIn(valid.returncode, (0, 1), valid.stdout + valid.stderr)
        self.assertTrue(trace.is_file(), 'restored source never reached manifest parser')

    def test_K19_batch_caps_suppressed_error_and_valid_control(self):
        self.f.shared.write_text(self.bad)
        body = 'parallelism_config_file() { printf "%s\\n" ' + shlex.quote(str(self.f.shared)) + '; }; read_parallelism_caps ' + shlex.quote(str(self.f.checkout))
        bad = self.safe(self.shell_function('workflow-batch-lanes.sh', ['read_parallelism_caps'], body), 0, locator=False)
        self.assertEqual(json.loads(bad.stdout)['implementation'], 1)
        self.f.shared.write_text('guardrails:\n  parallelism:\n    max_concurrent_by_stage:\n      implementation: 9\n')
        good = self.shell_function('workflow-batch-lanes.sh', ['read_parallelism_caps'], body)
        self.assertEqual(json.loads(good.stdout)['implementation'], 9)

    def test_K20_functional_config_transport(self):
        self.f.shared.write_text('vcs:\n  provider: opaqueConfigurationMaterial\n')
        body = 'source ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '; workflow_config_provider vcs ' + shlex.quote(str(self.f.shared))
        result = self.run_command(['/bin/bash', '-c', body])
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), self.opaque)
        self.assertEqual(result.stderr, '')

    def test_K21_budget_config_constant_error_only(self):
        self.f.private.write_text(self.bad)
        body = '''import runpy,sys
api=runpy.run_path(sys.argv[1])
try:api['config'](sys.argv[2])
except api['Stop'] as error:
 print(str(error),file=sys.stderr);sys.exit(2)
sys.exit(99)
'''
        result = self.cli_wrapper(body, 'workflow-merge-budget.py', str(self.f.checkout))
        self.safe(result, 2, locator=False)
        self.assertEqual(result.stderr.strip(), 'owning configuration unreadable')

    def cli_wrapper(self, body, file, *args):
        return self.run_command([sys.executable, '-c', body, str(self.f.runtime / file), *args])

    def test_K22_tracker_reader_not_config_transport(self):
        # Pure functional API/data counterpoint: no workflow config loaded here.
        body = '''import runpy,sys
import json
api=runpy.run_path(sys.argv[1]); print(json.dumps(api['dependency_fields'](sys.argv[2])))
'''
        result = self.cli_wrapper(body, 'workflow-project-reader.py', self.opaque)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, '')
        self.assertEqual(json.loads(result.stdout), [self.opaque])

    def test_K23_guidance_parser_and_linter_channels(self):
        import shutil
        import textwrap
        shells = list(dict.fromkeys(filter(None, ('/bin/bash', shutil.which('bash')))))
        for name in ('.claude/commands/sync-template.md', '.claude/skills/sync-template.md', '.cursor/commands/sync-template.md'):
            text = (ROOT / name).read_text()
            snippets = [x for x in re.findall(r'```bash\n(.*?)```', text, re.S) if 'yaml.safe_load' in x]
            self.assertEqual(len(snippets), 3)
            source = self.f.checkout / '.ai-dev-workflow.yaml'; source.write_text(self.bad)
            workflows = self.f.checkout / '.github/workflows'; workflows.mkdir(parents=True, exist_ok=True)
            (workflows / 'synthetic.yml').write_text(self.bad)
            for linter in (False, True):
                fake = self.f.bin / 'yamllint'
                if linter:
                    fake.write_text('#!/bin/sh\necho opaqueConfigurationMaterial; echo opaqueConfigurationMaterial >&2; exit 7\n'); fake.chmod(0o755)
                elif fake.exists():fake.unlink()
                for index, snippet in enumerate(snippets):
                    # Markdown removes the list indentation from fenced code.
                    # Retaining it makes Bash treat the heredoc terminator as a command.
                    snippet = textwrap.dedent(snippet).replace('<template_workflow_file>', str(source))
                    for shell in shells:
                        result = self.safe(self.run_command([shell, '-c', snippet]), 1 if index == 2 else 0, locator=False)
                        self.assertIn('YAML', result.stdout)
                        self.assertEqual(result.stderr, '')
            # Check the remaining command spellings after the real executions;
            # an old-head failure must first expose the fabricated excerpt.
            for snippet in snippets:
                relevant = [line for line in snippet.splitlines() if 'yaml.safe_load' in line or 'yamllint -d' in line]
                self.assertTrue(relevant)
                self.assertTrue(all('>/dev/null 2>&1' in line for line in relevant), relevant)

    def test_K24_unsupported_platform_error_view(self):
        source = self.f.root / 'bundle.json'; source.write_text(json.dumps({'target_base':'develop', 'remaining_stages':['on_draft_runner'], 'pr_state':{'on_draft_runner':'draft'}, 'shared':{'on_draft_runner':[self.opaque]}, 'resolved':{'on_draft_runner':[self.opaque]}}))
        result = self.safe(self.cli('reviewer_preflight.py', '--input-json', str(source)), 1)
        report = json.loads(result.stdout)
        self.assertEqual(report['platforms'][0]['name'], 'unknown')
        self.assertIn('value-not-supported', report['platforms'][0]['reasons'])

    def test_K25_availability_unsupported_value(self):
        self.f.private.write_text('review:\n  on_draft:\n    runner: [opaqueConfigurationMaterial]\n')
        result = self.safe(self.run_command(['/bin/bash', str(self.f.runtime / 'resolve-reviewer-availability.sh'), '--repo-root', str(self.f.checkout), '--runner-kind', 'codex', '--owner', 'fixture', '--repo', 'repo']), 1)
        self.assertIn('value-not-supported', result.stdout)
        self.assertRegex(result.stdout, r'REVIEWER_[0-9]+_NAME=unknown')
        self.f.private.write_text('review:\n  on_draft:\n    runner: [coderabbit]\n')
        (self.f.checkout / '.coderabbit.yaml').write_text(self.bad)
        result = self.safe(self.run_command(['/bin/bash', str(self.f.runtime / 'resolve-reviewer-availability.sh'), '--repo-root', str(self.f.checkout), '--runner-kind', 'codex', '--owner', 'fixture', '--repo', 'repo']), 1)
        self.assertIn('check-inconclusive', result.stdout)
        self.assertNotIn('.coderabbit.yaml', result.stdout + result.stderr)


    def test_K26_preflight_coderabbit_error_handoff(self):
        # Real pre-dispatch entry, local fake Git refs and fake platform config.
        # The preflight cross-check reads evidence; it never launches a reviewer.
        self.f.shared.write_text('review:\n  on_draft:\n    github: [coderabbit]\n  on_ready:\n    github: []\n')
        source = self.f.checkout / '.coderabbit.yaml'; source.write_text(self.bad)
        for command in (['git', 'switch', 'develop'], ['git', 'add', '.ai-dev-workflow.yaml', '.coderabbit.yaml'],
                        ['git', 'commit', '-qm', 'Synthetic platform config'],
                        ['git', 'remote', 'set-url', 'origin', str(self.f.checkout)],
                        ['git', 'fetch', '-q', 'origin', 'develop']):
            result = self.run_command(command); self.assertEqual(result.returncode, 0, result.stderr)
        self.f.env.update(WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE='1',
                          WORKFLOW_REVIEWER_PREFLIGHT_BUDGET_SECONDS='45',
                          WORKFLOW_REVIEWER_PREFLIGHT_PER_PLATFORM_CAP_SECONDS='20')
        args = ['/bin/bash', str(self.f.runtime / 'reviewer-preflight.sh'), '--repo-root', str(self.f.checkout),
                '--mode', 'pre-dispatch', '--target-base', 'develop', '--remaining-stages', 'on_draft.github',
                '--pr-state', 'on_draft.github=draft']
        result = self.safe(self.run_command(args), 0, locator=False)
        self.assertIn('check-inconclusive', result.stdout)
        source.write_text('reviews:\n  auto_review:\n    enabled: true\n    drafts: true\n')
        for command in (['git', 'add', '.coderabbit.yaml'], ['git', 'commit', '-qm', 'Restore synthetic valid platform'],
                        ['git', 'fetch', '-q', 'origin', 'develop']):
            self.assertEqual(self.run_command(command).returncode, 0)
        good = self.run_command(args)
        self.assertEqual(good.returncode, 0, good.stdout + good.stderr)
        self.assertIn('OUTCOME=passed', good.stdout)


def consumer_test(row):
    def test(self):
        self.f.private.write_text(self.bad)
        expected = {'C18': 1, 'C19': 1, 'C20': 3, 'D03': 1, 'D04': 1, 'D05': 1, 'D06': 1, 'D07': 1, 'D08': 1, 'E01': 1, 'E02': 1, 'E03': 1, 'E10': 1}.get(row[0], 2)
        result = self.safe(self.f.execute(row), expected)
        self.assertNotIn(str(self.f.checkout), result.stdout + result.stderr)
        self.assertRegex(result.stdout + result.stderr, 'invalid YAML|configuration')
        # Reuse the established arrival-control spy on a restored valid source.
        self.f.private.write_text('review:\n  on_draft:\n    runner: [codex]\n')
        self.f.check_consumer(row)
    return test


for row in fixtures.CASES:
    setattr(ConfigErrorDiagnostics, 'test_C_' + row[0] + '_metadata_only', consumer_test(row))


if __name__ == '__main__':
    unittest.main(verbosity=2)

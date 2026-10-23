#!/usr/bin/env python3
"""AC4 binding K01-K28 plus55 real consumers; fabricated opaque content only."""
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
TEST_BASH = os.environ.get('CONFIG_DIAGNOSTIC_BASH', '/bin/bash')


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
        return self.run_command([TEST_BASH, '-c', prefix + definitions + '\n' + body])

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
        self.safe(self.shell_function('run-work-router.sh', ['read_guardrails_config'], 'read_guardrails_config'), 2)
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
        bad = self.safe(self.shell_function('workflow-batch-lanes.sh', ['read_parallelism_caps'], body), 2)
        self.assertEqual(bad.stdout, '')
        self.f.shared.write_text('guardrails:\n  parallelism:\n    max_concurrent_by_stage:\n      implementation: 9\n')
        good = self.shell_function('workflow-batch-lanes.sh', ['read_parallelism_caps'], body)
        self.assertEqual(json.loads(good.stdout)['implementation'], 9)

    def test_K20_functional_config_transport(self):
        self.f.shared.write_text('vcs:\n  provider: opaqueConfigurationMaterial\n')
        body = 'source ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '; workflow_config_provider vcs ' + shlex.quote(str(self.f.shared))
        result = self.run_command([TEST_BASH, '-c', body])
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


    def late_setup(self, *, single=False, plan=True):
        self.selected = 'opaqueSelectedRoutingMaterial'
        self.f.private.write_text('review: {}\n')
        self.f.shared.write_text(('mode: single_repo\n' if single else
            'mode: workflow_hub\nissue_tracker:\n  provider: linear\nworkflow_hub:\n  product_repos:\n    - name: ' + self.selected + '\n      github_repo: fixture/mobile\n'))
        self.f.env.update(WORKFLOW_SKIP_FETCH='1', AI_DEV_WORKFLOW_CONFIG_FILE=str(self.f.shared))
        d = self.f.checkout / 'docs/specs/developments/20261020101010_1993-fixture'
        d.mkdir(parents=True)
        (d / '1_1993-fixture_specs.md').write_text('**Issue**: #1993\n')
        if plan:
            (d / '2_1993-fixture_implementation-plan.md').write_text('**Issue**: #1993\n')
        return d

    def late_schema(self):
        self.f.private.write_text('product_repos: ' + self.opaque + '\n')

    def late_gh(self, *, mutate=False):
        # Synthetic read transport: mutation models a source changing between
        # the validated argument handoff and the later context validation.
        change = ('printf "%s\\n" ' + shlex.quote('product_repos: ' + self.opaque) +
                  ' > ' + shlex.quote(str(self.f.private)) + '\n') if mutate else ''
        (self.f.bin / 'gh').write_text('#!/bin/sh\ncase "$*" in\n'
            ' "auth status"*) exit 0;;\n "pr view"*)\n' + change +
            'cat "$SYNTHETIC_PR";;\n "pr list"*)\n' + change +
            'case "$*" in *"--jq length"*) echo 0;; *) echo "[]";; esac;;\n *) exit 99;;\nesac\n')

    def late_cli(self, file, *args):
        return self.run_command([TEST_BASH, str(self.f.runtime / file), *args,
                                 '--repo-root', str(self.f.checkout)])

    def late_safe(self, result, status=2):
        self.safe(result, status)
        self.assertEqual(result.stdout, '', 'fatal validation published a functional payload')
        self.assertNotIn(self.selected, result.stdout + result.stderr)
        self.assertNotIn('ROUTING_', result.stdout + result.stderr)
        self.assertNotIn('ACTION_', result.stdout + result.stderr)
        for line in result.stderr.splitlines():
            self.assertRegex(line, r'^(ERROR: )?configuration: [a-zA-Z -]+(?:; (?:line|column)=\d+|; key=[a-zA-Z_.\[\]]+)*$')
        return result

    def test_T01_context_atomic(self):
        self.late_setup(); self.late_schema()
        setup = ('repo_root=' + shlex.quote(str(self.f.checkout)) + '\nworkflow_mode=workflow_hub\n'
                 'target_repo=' + shlex.quote(self.selected) + '\nbranch_name=feature/1993-fixture\n'
                 'implementation_item_is_hub_only_cached() { return 1; }\n')
        def run(tail=''):
            return self.shell_function('workflow-next-action.sh', ['repository_context_for_action'],
                                       setup + tail + '\nrepository_context_for_action implementation')
        self.late_safe(run(), 3)
        self.f.private.write_text('review: {}\n')
        valid = run(); self.assertEqual(valid.returncode, 0, valid.stderr)
        self.assertIn('ROUTING_OUTCOME_CODE=product_owned\n', valid.stdout)
        self.assertIn('ROUTING_SELECTED_PRODUCT_REPO_KEY=' + self.selected + '\n', valid.stdout)
        self.assertIn('ACTION_GITHUB_REPO=fixture/mobile\n', valid.stdout)
        negative = run('target_repo=unknown-product')
        self.assertEqual(negative.returncode, 2, negative.stderr)
        self.assertIn('ROUTING_CONTINUE_ALLOWED=false\n', negative.stdout)
        self.assertIn('ROUTING_OUTCOME_CODE=ambiguous_target\n', negative.stdout)
        self.assertEqual(negative.stderr, '')

    def test_T02_pr_probe(self):
        self.late_setup(); self.late_gh()
        valid_shared = self.f.shared.read_text()
        self.f.shared.write_text('mode: workflow_hub\nissue_tracker:\n  provider: linear\nworkflow_hub:\n  product_repos: ' + self.opaque + '\n')
        self.late_safe(self.late_cli('workflow-next-action.sh', '--pr', '1993'))
        self.f.shared.write_text(valid_shared)
        rejected = self.late_cli('workflow-next-action.sh', '--pr', '1993')
        self.assertEqual(rejected.returncode, 0, rejected.stderr)
        self.assertIn('NEXT_ACTION=resolve-repository-selection\n', rejected.stdout)
        self.assertIn('ROUTING_CONTINUE_ALLOWED=false', rejected.stdout)
        self.assertEqual(rejected.stderr, '')

    def test_T03_pr_context(self):
        self.late_setup(); self.late_gh(mutate=True)
        self.late_safe(self.late_cli('workflow-next-action.sh', '--pr', '1993', '--repo', self.selected))
        self.f.private.write_text('review: {}\n'); self.late_gh()
        good = self.late_cli('workflow-next-action.sh', '--pr', '1993', '--repo', self.selected)
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertIn('NEXT_ACTION=resolve-pr-readiness\n', good.stdout)
        self.assertIn('ROUTING_CONTINUE_ALLOWED=true\n', good.stdout)

    def test_T04_branch_context(self):
        self.late_setup(); self.late_schema()
        self.late_safe(self.late_cli('workflow-next-action.sh', '--branch', 'feature/1993-fixture', '--repo', self.selected))
        self.f.private.write_text('review: {}\n')
        negative = self.late_cli('workflow-next-action.sh', '--branch', 'feature/1993-fixture')
        self.assertEqual(negative.returncode, 0, negative.stderr)
        self.assertIn('NEXT_ACTION=resolve-repository-selection\n', negative.stdout)
        self.assertIn('ROUTING_CONTINUE_ALLOWED=false', negative.stdout)
        self.assertEqual(negative.stderr, '')

    def test_T05_development_context(self):
        development = self.late_setup(); self.late_gh(mutate=True)
        self.late_safe(self.late_cli('workflow-next-action.sh', '--development', str(development), '--repo', self.selected))
        self.f.private.write_text('review: {}\n'); self.late_gh()
        good = self.late_cli('workflow-next-action.sh', '--development', str(development), '--repo', self.selected)
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertIn('NEXT_ACTION=implement\n', good.stdout)
        self.assertIn('ROUTING_OUTCOME_CODE=product_owned\n', good.stdout)

    def test_T06_development_hub(self):
        development = self.late_setup(single=True, plan=False)
        self.f.shared.write_text('mode: single_repo\nrelease: ' + self.opaque + '\n')
        self.late_safe(self.late_cli('workflow-next-action.sh', '--development', str(development)))
        self.f.shared.write_text('mode: single_repo\n')
        good = self.late_cli('workflow-next-action.sh', '--development', str(development))
        self.assertEqual(good.returncode, 0, good.stderr)
        self.assertIn('NEXT_ACTION=write-plan\n', good.stdout)
        self.assertIn('ACTION_REPOSITORY_KIND=single_repo_context\n', good.stdout)

    def test_T10_tracker_provider(self):
        self.late_setup()
        body = ('repo_root=' + shlex.quote(str(self.f.checkout)) + '\n'
                'workflow_config_provider() { printf "%s\\n" "opaqueConfigurationMaterial"; printf "%s\\n" "opaqueConfigurationMaterial" >&2; return 2; }\n'
                'repo_root_tracker_provider')
        self.late_safe(self.shell_function('workflow-next-action.sh', ['repo_root_tracker_provider'], body))
        body = body.replace('printf "%s\\n" "opaqueConfigurationMaterial"; printf "%s\\n" "opaqueConfigurationMaterial" >&2; return 2;', 'printf "linear\\n";')
        good = self.shell_function('workflow-next-action.sh', ['repo_root_tracker_provider'], body)
        self.assertEqual((good.returncode, good.stdout, good.stderr), (0, 'linear', ''))


    def classifier_fixture(self):
        development = self.late_setup()
        valid = self.f.shared.read_text() + 'template:\n  is_template: true\n'
        bad = ('mode: workflow_hub\nissue_tracker:\n  provider: linear\n'
               'template:\n  is_template: true\nworkflow_hub:\n  product_repos: ' + self.opaque + '\n')
        (self.f.bin / 'gh').write_text('#!/bin/sh\nexit 99\n')
        self.f.shared.write_text(bad)
        # Syntax and mode succeed before the real classifier rejects the shape.
        mode = self.cli('workflow-config-resolver.py', 'mode', '--repo-root', str(self.f.checkout))
        self.assertEqual(mode.returncode, 0, mode.stderr)
        self.assertIn('workflow_hub', mode.stdout)
        return development, valid, bad

    def test_A01_classifier(self):
        _, valid, _ = self.classifier_fixture()
        args = ('--repo-root', str(self.f.checkout), '--repository-mode', 'workflow_hub', '--stage', 'implementation', '--json')
        self.late_safe(self.cli('work-item-repository-routing.py', *args))
        self.f.shared.write_text(valid)
        good = self.cli('work-item-repository-routing.py', *args)
        self.assertEqual(good.returncode, 0, good.stderr)
        payload = json.loads(good.stdout)
        self.assertEqual((payload['outcome_code'], payload['continue_allowed']), ('missing_target', False))
        self.assertEqual(payload['configured_product_repo_keys'], [self.selected])
        self.assertEqual(good.stderr, '')

    def classifier_entry(self, script, scan=False):
        development, valid, _ = self.classifier_fixture()
        args = [str(development)] if script != 'workflow-next-action.sh' else ['--development', str(development)]
        if scan: args.insert(0, '--scan')
        self.late_safe(self.late_cli(script, *args))
        self.f.shared.write_text(valid)
        negative = self.late_cli(script, *args)
        self.assertEqual(negative.returncode, 0, negative.stdout + negative.stderr)
        self.assertIn('NEXT_ACTION=resolve-repository-selection\n', negative.stdout)
        self.assertNotIn(self.opaque, negative.stdout + negative.stderr)
        # Documented absent stage input66 is not a validation failure.
        absent = development / 'no-stage'; absent.mkdir()
        (absent / 'README.md').write_text('**Issue**: #1993\n')
        no_stage = self.late_cli('workflow-next-action.sh', '--development', str(absent))
        self.assertEqual(no_stage.returncode, 66, no_stage.stdout + no_stage.stderr)
        self.assertIn('No spec or plan file found', no_stage.stderr)
        if script != 'workflow-next-action.sh':
            skipped = self.late_cli(script, *(['--scan'] if scan else []), str(absent))
            self.assertEqual(skipped.returncode, 0, skipped.stdout + skipped.stderr)
            self.assertIn('Skipping ', skipped.stderr)
            self.assertNotIn('configuration:', skipped.stderr)
            self.assertNotIn(self.opaque, skipped.stdout + skipped.stderr)

    def test_A02_next_classifier(self): self.classifier_entry('workflow-next-action.sh')
    def test_A03_batch_classifier(self): self.classifier_entry('workflow-batch-plan.sh')
    def test_A04_scan_classifier(self): self.classifier_entry('workflow-batch-lanes.sh', True)

    def prelude_scope(self):
        scope = {'scopeSource': 'item', 'resolvedIssueNumber': 1993, 'trackerReadDeferred': False,
                 'baseBranch': 'develop', 'baseAmbiguous': False, 'baseReason': 'synthetic',
                 'policy': {'delegateReview': False, 'mayMerge': False, 'mayStartBacklog': False, 'maxRisk': 'low'},
                 'groups': {'eligible': [], 'blocked': [], 'already_merged': [], 'in_review': [], 'ambiguous': [], 'out_of_scope': []},
                 'items': [{'number': 1993, 'title': 'Synthetic', 'status': 'In Development', 'type': 'Feature', 'labels': [], 'body': 'synthetic', 'pullRequests': {'open': [], 'merged': []}}]}
        scope['groups']['eligible'] = scope['items']
        self.f.scope.write_text(json.dumps(scope))
        stub = self.f.runtime / 'run-item-scope-resolver.sh'
        stub.write_text('#!/bin/sh\ncat ' + shlex.quote(str(self.f.scope)) + '\n'); stub.chmod(0o755)

    def test_A05_prelude_classifier(self):
        _, valid, _ = self.classifier_fixture(); self.prelude_scope()
        args = ('--original-command', '/run-item 1993', '--issue', '1993', '--json')
        self.late_safe(self.run_command([TEST_BASH, str(self.f.runtime / 'run-bounded-prelude.sh'), *args]))
        self.f.shared.write_text(valid)
        good = self.run_command([TEST_BASH, str(self.f.runtime / 'run-bounded-prelude.sh'), *args])
        self.assertEqual(good.returncode, 0, good.stdout + good.stderr)
        self.assertEqual(json.loads(good.stdout)['scope']['resolvedIssueNumber'], 1993)


    def mixed_fatal_child(self):
        """Plant functional stdout at a real late-failing CLI boundary.

        Keep the actual validator and failure2; this challenges downstream
        consumers even though the corrected child normally publishes atomically.
        """
        path = self.f.runtime / 'workflow-next-action.sh'; original = path.read_text()
        anchor = ('action_context_output="$(repository_context_for_action hub 2>&1)" || action_context_status=$?\n'
                  '    if [ "$action_context_status" -ne 0 ]; then\n')
        self.assertEqual(original.count(anchor), 1)
        path.write_text(original.replace(anchor, anchor + '      printf "ROUTING_SELECTED_PRODUCT_REPO_KEY=%s\\n" ' + shlex.quote(self.opaque) + '\n'))
        return path, original

    def test_T07_batch_forward(self):
        development = self.late_setup(single=True, plan=False)
        self.f.shared.write_text('mode: single_repo\nrelease: ' + self.opaque + '\n')
        path, original = self.mixed_fatal_child()
        producer = self.late_cli('workflow-next-action.sh', '--development', str(development))
        self.assertEqual(producer.returncode, 2, producer.stdout + producer.stderr)
        self.assertIn(self.opaque, producer.stdout, 'plant did not reach real child error boundary')
        self.assertIn('configuration:', producer.stderr)
        try:
            self.late_safe(self.late_cli('workflow-batch-plan.sh', str(development)))
        finally:
            path.write_text(original)
        self.f.shared.write_text('mode: single_repo\n')
        good = self.late_cli('workflow-batch-plan.sh', str(development))
        self.assertEqual(good.returncode, 0, good.stdout + good.stderr)
        self.assertIn('NEXT_ACTION=write-plan\n', good.stdout)
        self.assertEqual(good.stderr, '')

    def test_T08_prelude_forward(self):
        development = self.late_setup(single=True, plan=False); self.prelude_scope()
        valid = 'mode: single_repo\ntemplate:\n  is_template: true\n'
        self.f.shared.write_text(valid + 'release: ' + self.opaque + '\n')
        path, original = self.mixed_fatal_child()
        producer = self.late_cli('workflow-next-action.sh', '--development', str(development))
        self.assertEqual(producer.returncode, 2, producer.stdout + producer.stderr)
        self.assertIn(self.opaque, producer.stdout, 'plant did not reach real child error boundary')
        self.assertIn('configuration:', producer.stderr)
        args = [TEST_BASH, str(self.f.runtime / 'run-bounded-prelude.sh'), '--original-command', '/run-item 1993', '--issue', '1993', '--json']
        try:
            self.late_safe(self.run_command(args))
        finally:
            path.write_text(original)
        self.f.shared.write_text(valid)
        good = self.run_command(args)
        self.assertEqual(good.returncode, 0, good.stdout + good.stderr)
        self.assertEqual(json.loads(good.stdout)['scope']['resolvedIssueNumber'], 1993)

    def test_T09_scan_forward(self):
        self.late_setup(); self.late_schema()
        # Transport a real selected branch context through the scan consumer.
        # A04 separately covers the unmodified full development/batch/scan chain.
        batch = self.f.runtime / 'workflow-batch-plan.sh'; original = batch.read_text()
        batch.write_text('#!/bin/sh\nexec ' + shlex.join([TEST_BASH, str(self.f.runtime / 'workflow-next-action.sh'), '--branch', 'feature/1993-fixture', '--repo', self.selected, '--repo-root', str(self.f.checkout)]) + '\n')
        (self.f.bin / 'gh').write_text('#!/bin/sh\nexit 99\n')
        try:
            producer = self.late_cli('workflow-next-action.sh', '--branch', 'feature/1993-fixture', '--repo', self.selected)
            self.late_safe(producer)
            self.late_safe(self.late_cli('workflow-batch-lanes.sh', '--scan'))
            self.f.private.write_text('review: {}\n')
            good = self.late_cli('workflow-batch-lanes.sh', '--scan')
            self.assertEqual(good.returncode, 0, good.stdout + good.stderr)
            self.assertTrue(good.stdout.startswith('MAX_CONCURRENT_SPEC=0\nMAX_CONCURRENT_PLAN=0\nMAX_CONCURRENT_REVIEW=0\nMAX_CONCURRENT_IMPLEMENTATION=1\n\n'))
            self.assertIn('ACTION_REPOSITORY=' + self.selected + '\n', good.stdout)
            self.assertEqual(good.stderr, '')
        finally:
            batch.write_text(original)


    def classifier_execution(self, status):
        development, valid, _ = self.classifier_fixture(); self.prelude_scope()
        self.f.shared.write_text(valid)
        classifier = self.f.runtime / 'work-item-repository-routing.py'; original = classifier.read_text()
        classifier.write_text('import sys\nprint(' + repr('{"opaqueUnknownKey":"' + self.opaque + '"}') + ')\nprint(' + repr(self.opaque) + ',file=sys.stderr)\nsys.exit(' + str(status) + ')\n')
        direct = self.cli('work-item-repository-routing.py')
        self.assertEqual(direct.returncode, status)
        self.assertIn(self.opaque, direct.stdout)
        self.assertIn(self.opaque, direct.stderr)
        entries = [
            ('next-development', 'workflow-next-action.sh', ['--development', str(development)]),
            ('next-branch', 'workflow-next-action.sh', ['--branch', 'feature/1993-fixture', '--repo', self.selected]),
            ('next-pr', 'workflow-next-action.sh', ['--pr', '1993']),
            ('batch', 'workflow-batch-plan.sh', [str(development)]),
            ('scan', 'workflow-batch-lanes.sh', ['--scan', str(development)]),
            ('prelude', 'run-bounded-prelude.sh', ['--original-command', '/run-item 1993', '--issue', '1993', '--json']),
        ]
        self.late_gh()  # PR probe is a fake read; no actual provider.
        try:
            for name, script, args in entries:
                with self.subTest(entry=name, child_status=status):
                    if name != 'next-pr':
                        (self.f.bin / 'gh').write_text('#!/bin/sh\nexit 99\n')
                    else:
                        self.late_gh()
                    result = (self.run_command([TEST_BASH, str(self.f.runtime / script), *args])
                              if script == 'run-bounded-prelude.sh' else self.late_cli(script, *args))
                    self.late_safe(result)
        finally:
            classifier.write_text(original)
        negative = self.late_cli('workflow-next-action.sh', '--development', str(development))
        self.assertEqual(negative.returncode, 0, negative.stdout + negative.stderr)
        self.assertIn('NEXT_ACTION=resolve-repository-selection\n', negative.stdout)
        self.assertIn('ROUTING_CONTINUE_ALLOWED=false\n', negative.stdout)
        self.assertEqual(negative.stderr, '')

    def test_A06_classifier_execution(self): self.classifier_execution(17)
    def test_A07_classifier_response(self): self.classifier_execution(0)


    def rejected_graduation_provider(self, script):
        '''Reach the real shared-provider rejection before any remote operation.'''
        self.opaque = 'opaqueconfigurationmaterial'
        self.f.shared.write_text('issue_tracker:\n  provider: ' + self.opaque + '\n')
        syntax = self.cli('workflow-config-resolver.py', 'yaml-source-check', '--file', str(self.f.shared))
        self.assertEqual(syntax.returncode, 0, syntax.stdout + syntax.stderr)
        self.f.env['WORKFLOW_TARGET_GITHUB_REPO'] = 'fixture/repo'
        auth_calls = self.f.root / 'graduation-auth-calls'
        provider_calls = self.f.root / 'graduation-provider-calls'
        gh = self.f.bin / 'gh'
        gh.write_text('#!/bin/sh\nif [ "$1:$2" = auth:status ]; then\n' +
                      '  printf "auth\\n" >>' + shlex.quote(str(auth_calls)) + '\n  exit 0\nfi\n' +
                      'printf "unexpected-provider\\n" >>' + shlex.quote(str(provider_calls)) + '\nexit 99\n')
        gh.chmod(0o755)
        args = ['--graduation-pr', '1993', '--epic', '1993']
        if script == 'graduation-closeout.sh':
            args += ['--slug', 'synthetic']
        for shell in ('/bin/bash', '/opt/homebrew/bin/bash'):
            if not Path(shell).exists():
                continue
            with self.subTest(shell=shell, entry=script):
                auth_calls.write_text('')
                result = self.safe(self.run_command([shell, str(self.f.runtime / script), *args]), 64)
                self.assertEqual(result.stdout, '')
                self.assertEqual(result.stderr,
                                 'configuration: configuration validation error; key=issue_tracker.provider\n')
                self.assertEqual(auth_calls.read_text().splitlines(), ['auth'])
                self.assertFalse(provider_calls.exists(), 'remote provider operation reached')
                self.assertFalse(self.f.log.exists(), 'unexpected mutation')

    def test_K27_graduation_rejected_provider_metadata(self):
        self.rejected_graduation_provider('graduation-closeout.sh')

    def test_K28_graduation_merged_pr_rejected_provider_metadata(self):
        self.rejected_graduation_provider('graduation-closeout-from-merged-pr.sh')


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

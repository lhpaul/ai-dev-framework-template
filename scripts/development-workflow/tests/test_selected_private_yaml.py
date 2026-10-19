#!/usr/bin/env python3
"""Cycle6 strict framework syntax: fabricated selected sources, no PyYAML."""
from __future__ import annotations

import importlib.util
import itertools
import json
from pathlib import Path
import subprocess
import sys
import unittest

SPEC = importlib.util.spec_from_file_location('private_fixtures', Path(__file__).with_name('test_private_source_consumers.py'))
fixtures = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fixtures)
RESOLVER_SPEC = importlib.util.spec_from_file_location('private_parser', fixtures.SCRIPTS / 'workflow-config-resolver.py')
resolver = importlib.util.module_from_spec(RESOLVER_SPEC)
RESOLVER_SPEC.loader.exec_module(resolver)


class SelectedPrivateYaml(unittest.TestCase):
    def setUp(self):
        self.f = fixtures.PrivateSourceConsumers(methodName='runTest')
        self.f.setUp()
        self.addCleanup(self.f.doCleanups)
        missing = self.f.root / 'blocked-yaml'; missing.mkdir()
        (missing / 'yaml.py').write_text('raise ImportError("synthetic unavailable parser")\n')
        self.f.env['PYTHONPATH'] = str(missing)
        self.valid = ('review:\n  on_draft:\n    runner: [codex]\n    github: [bugbot]\n'
                      '  on_ready:\n    github: []\n  coderabbit_cli:\n    rate_limit_policy: strict\n')
        self.f.private.write_text(self.valid)
        self.path = self.f.root / 'fabricated-private.yaml'

    def cli(self, *arguments):
        return subprocess.run([sys.executable, str(self.f.runtime / 'workflow-config-resolver.py'),
                               *arguments], env=self.f.env, cwd=self.f.checkout,
                              text=True, capture_output=True, timeout=15)

    def parse(self, raw):
        return resolver.validate_selected_yaml(raw, self.path)

    def test_P01_valid_selected_legacy_commands_without_pyyaml(self):
        commands = [
            ('local-source', []), ('mode', []),
            ('resolve', ['--repo', 'mobile', '--json']),
            ('auth', ['--repo', 'mobile']),
            ('review-overrides', []),
            ('model-route', ['--runner', 'dsh', '--role', 'developer']),
            ('review-local-list', ['--phase', 'on_draft', '--key', 'runner']),
        ]
        for command, arguments in commands:
            with self.subTest(command=command):
                result = self.cli(command, '--repo-root', str(self.f.checkout), *arguments)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertNotIn('shared-policy-sentinel', result.stdout)
                if command == 'review-overrides':
                    self.assertIn('REVIEW_ON_DRAFT_RUNNER=codex', result.stdout)
                if command == 'review-local-list':
                    self.assertEqual(result.stdout.strip(), 'codex')
        checked = self.cli('yaml-source-check', '--file', str(self.f.private))
        self.assertEqual(checked.returncode, 0, checked.stderr)

    def test_P02_missing_empty_and_shared_only_without_pyyaml(self):
        self.f.env.pop('WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT')
        local = self.f.checkout / '.ai-dev-workflow.local.yaml'
        for source in (None, '', '# synthetic comment\n', 'other: ordinary context\n'):
            with self.subTest(source=source):
                if source is None:
                    local.unlink(missing_ok=True)
                else:
                    local.write_text(source)
                for command in ('local-source', 'mode', 'review-overrides'):
                    result = self.cli(command, '--repo-root', str(self.f.checkout))
                    self.assertEqual(result.returncode, 0, (command, result.stderr))

    def test_P03_real_bash_consumers_without_pyyaml(self):
        rows = [row for row in fixtures.CASES if row[0] in ('L01', 'L03', 'L04', 'L05', 'L06', 'L10', 'C01', 'C02')]
        for row in rows:
            with self.subTest(consumer=row[0]):
                result = self.f.execute(row)
                self.assertEqual(result.returncode, 0, (row, result.stderr))
                self.assertNotIn('shared-policy-sentinel', result.stdout)
        # A source error must still propagate inside conditional composition.
        self.f.private.write_text(self.valid + 'unrelated: [syntheticOpaque,,tail]\n')
        for row in rows:
            with self.subTest(invalid_consumer=row[0]):
                result = self.f.execute(row)
                self.assertEqual(result.returncode, 2, (row, result.stderr))
                self.assertIn('invalid YAML', result.stderr)
                self.assertNotIn('syntheticOpaque', result.stdout + result.stderr)
                self.assertNotIn('shared-policy-sentinel', result.stdout)

    def test_P04_invalid_whole_selected_document_without_pyyaml(self):
        invalid = ['other: [syntheticOpaque,,tail]', 'other: "syntheticOpaque',
                   "other: 'syntheticOpaque", 'other: [syntheticOpaque',
                   'other: a: syntheticOpaque', 'other: value\nother: syntheticOpaque',
                   'other:\n  key: value\n  key: syntheticOpaque',
                   'other: ["syntheticOpaque" "suffix"]', 'other: [:syntheticOpaque]',
                   'other: [syntheticOpaque,:bad]', 'other: %syntheticOpaque',
                   'other: &syntheticOpaque value', 'other: *syntheticOpaque',
                   'other: "syntheticOpaque"suffix', 'other: "syntheticOpaque\\q"',
                   '# syntheticOpaque\x00', 'other: syntheticOpaque\x07',
                   'other:\n   key: syntheticOpaque', '\tother: syntheticOpaque',
                   'other: !!str syntheticOpaque', 'other: |\n  syntheticOpaque',
                   'other: >\n  syntheticOpaque', 'other: "syntheticOpaque\n  tail"',
                   'other: [syntheticOpaque,\n  tail]',
                   'other: {key: first, key: syntheticOpaque}']
        for text in invalid:
            for position in ('before', 'after'):
                with self.subTest(text=text, position=position):
                    self.f.private.write_text(text + '\n' + self.valid if position == 'before' else self.valid + text + '\n')
                    for command in ('local-source', 'review-overrides'):
                        result = self.cli(command, '--repo-root', str(self.f.checkout))
                        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                        self.assertRegex(result.stderr, 'invalid YAML|duplicate mapping')
                        self.assertEqual(result.stdout, '')
                        self.assertNotIn('syntheticOpaque', result.stderr)

    def test_P05_mapping_sequence_and_flow_compatibility(self):
        data = self.parse('''items:
  - name: first
    nested:
      flag: true
  - name:
      key: value
    siblings: [a, [b, c], {}]
empty: {}
flow: {name: value, nested: [x, y]}
''')
        self.assertEqual(data['items'][0], {'name': 'first', 'nested': {'flag': True}})
        self.assertEqual(data['items'][1]['name'], {'key': 'value'})
        self.assertEqual(data['flow'], {'name': 'value', 'nested': ['x', 'y']})
        self.assertEqual(data['empty'], {})

    def test_P06_single_double_and_plain_scalar_compatibility(self):
        for raw, expected in [
            ("'synthetic it''s secret'", "synthetic it's secret"),
            ('"synthetic \\"quoted\\" \\\\ tail"', 'synthetic "quoted" \\ tail'),
            ('synthetic multi, word # comment', 'synthetic multi, word'),
            ('synthetic#literal multi word', 'synthetic#literal multi word'),
            ('foo "', 'foo "'), ('a:b', 'a:b'),
            ('synthetic [brackets] {braces}, tail', 'synthetic [brackets] {braces}, tail'), ('"\\u2028"', '\u2028'),
        ]:
            with self.subTest(raw=raw):
                self.assertEqual(self.parse('other: ' + raw + '\n')['other'], expected)
                self.f.private.write_text(self.valid + 'other: ' + raw + '\n')
                actual = self.cli('local-source', '--repo-root', str(self.f.checkout))
                self.assertEqual(actual.returncode, 0, actual.stderr)
        for raw, expected in [('"\\e[2J"', '\x1b[2J'), ('"#literal"', '#literal'),
                              ("':bad'", ':bad'), ('a#b', 'a#b'), ('a:b', 'a:b')]:
            with self.subTest(flow=raw):
                self.assertEqual(self.parse('other: [codex, ' + raw + '] # context\n')['other'], ['codex', expected])
                self.f.private.write_text('review:\n  on_draft:\n    runner: [codex, ' + raw + ']\n')
                actual = self.cli('review-local-list', '--repo-root', str(self.f.checkout),
                                  '--phase', 'on_draft', '--key', 'runner')
                self.assertEqual(actual.returncode, 0, actual.stderr)
                self.assertEqual(actual.stdout.splitlines(), ['codex', expected])

    def test_P07_schema_remains_after_precedence_and_syntax(self):
        self.f.private.write_text(self.valid + 'review_alias: opaque\n')
        result = self.cli('review-local-list', '--repo-root', str(self.f.checkout), '--phase', 'on_ready', '--key', 'github')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, '')
        self.f.private.write_text('review:\n  internal_reviewers: opaque\n  on_draft:\n    runner: [codex]\n')
        result = self.cli('review-local-list', '--repo-root', str(self.f.checkout), '--phase', 'on_draft', '--key', 'runner')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), 'codex')
        self.f.private.write_text('review:\n  on_draft:\n    runner: [3]\n')
        result = self.cli('review-local-list', '--repo-root', str(self.f.checkout), '--phase', 'on_draft', '--key', 'runner')
        self.assertEqual(result.returncode, 2)
        self.assertIn('schema', result.stderr)

    def test_P09_flow_structure_is_not_misread_as_a_string(self):
        for token in ('a:', '?foo', '? foo', 'a:[]', 'a:{}', '"\\0"'):
            with self.subTest(token=token):
                self.f.private.write_text('review:\n  on_draft:\n    runner: [' + token + ']\n')
                result = self.cli('review-local-list', '--repo-root', str(self.f.checkout),
                                  '--phase', 'on_draft', '--key', 'runner')
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertEqual(result.stdout, '')
        self.assertEqual(self.parse('   # arbitrary comment indentation\nother: [a:b, a#b]\n')['other'], ['a:b', 'a#b'])
        self.f.private.write_text(self.valid + 'unrelated: {key: value}\n')
        result = self.cli('review-local-list', '--repo-root', str(self.f.checkout),
                          '--phase', 'on_draft', '--key', 'runner')
        self.assertEqual(result.returncode, 2)
        self.assertIn('unsupported YAML', result.stderr)

    def test_P08_modern_review_dependency_is_separate(self):
        result = self.cli('review-effective', '--repo-root', str(self.f.checkout))
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report['effective_policy_state'], 'unreadable')
        self.assertIn('PyYAML', report['unreadable_detail'])

    def test_P10_generated_invalid_flow_syntax_cannot_be_accepted(self):
        # The existing test dependency is an oracle, never the implementation.
        # Child CLI tests above still run with yaml imports explicitly blocked.
        import yaml
        rejected = 0
        for left, right in itertools.product(('a', ':', ',', '[', ']', '"', "'", '#', '{', '}'), repeat=2):
            for token in (left + right, 'synthetic' + left + right, left + right + 'tail'):
                text = 'other: [' + token + ']\n'
                try:
                    yaml.compose(text, Loader=yaml.BaseLoader)
                except yaml.YAMLError:
                    with self.subTest(token=token):
                        with self.assertRaises(resolver.ConfigError):
                            self.parse(text)
                    rejected += 1
        self.assertGreater(rejected, 100)


if __name__ == '__main__':
    unittest.main(verbosity=2)

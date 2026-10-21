#!/usr/bin/env python3
"""Cycle6 strict framework syntax: fabricated selected sources, no PyYAML."""
from __future__ import annotations

import importlib.util
import hashlib
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


INDICATORS = '-?:,[]{}#&*!|>\'"%@`'


def indicator_context_cases():
    """Finite syntax-oracle matrix, independent of the framework parser."""
    contexts = {
        'block_value': 'other: TOKEN\n',
        'block_sequence': 'other:\n  - TOKEN\n',
        'block_mapping_key': 'TOKEN: tail\n',
        'block_sequence_mapping_key': 'other:\n  - TOKEN: tail\n',
        'flow_sequence': 'other: [TOKEN]\n',
        'flow_mapping_key': 'other: {TOKEN: tail}\n',
        'flow_mapping_value': 'other: {a: TOKEN}\n',
        'nested_flow_sequence': 'other: [{a: [TOKEN]}]\n',
        'nested_flow_mapping': 'other: {a: {b: TOKEN}}\n',
        'implicit_pair_sequence_value': 'other: [a: TOKEN]\n',
        'explicit_pair_sequence_value': 'other: [? a: TOKEN]\n',
        'explicit_mapping_key': 'other: {? TOKEN: tail}\n',
    }
    positions = {
        'start': lambda c: c + 'fabricatedOpaqueIndicator',
        'internal': lambda c: 'fabricatedOpaqueIndicator' + c + 'tail',
        'end': lambda c: 'fabricatedOpaqueIndicator' + c,
        'alone': lambda c: c,
        'start_space': lambda c: c + ' fabricatedOpaqueIndicator',
        'space_before': lambda c: 'fabricatedOpaqueIndicator ' + c + 'tail',
        'space_after': lambda c: 'fabricatedOpaqueIndicator' + c + ' tail',
        'single_quoted': lambda c: "'fabricatedOpaqueIndicator" + c.replace("'", "''") + "tail'",
        'double_quoted': lambda c: json.dumps('fabricatedOpaqueIndicator' + c + 'tail'),
        'double_escaped': lambda c: '"fabricatedOpaqueIndicator\\' + c + 'tail"',
    }
    for context, wrapper in contexts.items():
        for position, token in positions.items():
            for indicator in INDICATORS:
                yield context, position + ':' + indicator, wrapper.replace('TOKEN', token(indicator))
    # Adjacent indicators exercise dispatch, separators and plain-scalar scanning
    # at collection keys, values and nested entry/value boundaries.
    for context in ('block_value', 'flow_sequence', 'flow_mapping_key',
                    'flow_mapping_value', 'nested_flow_mapping', 'explicit_pair_sequence_value'):
        for left, right in itertools.product(INDICATORS, repeat=2):
            pair = left + right
            for position, token in (('pair_start', pair + 'fabricatedOpaqueIndicator'),
                                    ('pair_internal', 'fabricatedOpaqueIndicator' + pair + 'tail'),
                                    ('pair_end', 'fabricatedOpaqueIndicator' + pair)):
                yield context, position + ':' + pair, contexts[context].replace('TOKEN', token)
    for raw in ('other: {a: ?b}\n', 'other: {a: ? b}\n',
                'other: [a: ?b]\n', 'other: [? a: ?b]\n',
                'other: [? a: [? b: c]]\n', 'other: [? a: b]\n',
                'other: [?a]\n', 'other: {a: [?b]}\n',
                'other: {a: {?b: c}}\n', 'other: {a: [key: ?b]}\n'):
        yield 'explicit_key_position', 'nested_entry_or_value', raw


def modern_reader_cases():
    """Pinned public fixtures plus pre-change strict-reader scalar/Unicode controls."""
    corpus = json.loads((Path(__file__).parent / 'fixtures/1993-selected-yaml-parity.json').read_text())
    for index, case in enumerate(corpus['cases'], 1):
        yield f'F{index:04}', case['raw']
    raws=[
     'other: "literal \\"quotes\\" \\\\ tail"\n', "other: 'literal it''s tail'\n", 'other: [a:b, a#b, "a,b", [true, null, 0x10]]\n',
     'other:\n  - name: first\n    value: [1, -2, 3.5]\n', 'other: {a: value}\n',
     'other: .inf\n','other: '+('1'*4400)+'\n', 'other: ["\\uFFFE", "\\uFFFF", "\\U0001FFFF"]\n',
    ]
    for c in ['\x7f','\x85','\u2028','\u2029','\ufffe','\uffff','\ufeff','\U0001fffe','\U0001ffff','\U0010ffff']:
     for template in ['other: fabricatedOpaque'+c+'tail\n','other: "fabricatedOpaque'+c+'tail"\n','# fabricatedOpaque'+c+'tail\nother: valid\n','other: first'+c+'next: second\n']:
      raws.append(template)
    for index, raw in enumerate(raws, 1):
        if index != 7:  # Runtime integer digit limits are covered by the existing modern harness.
            yield f'U{index:03}', raw


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
        for raw, expected in [('"fabricatedOpaqueControlName\\e[2J"', 'fabricatedOpaqueControlName\x1b[2J'), ('"#literal"', '#literal'),
                              ("':bad'", ':bad'), ('a#b', 'a#b'), ('a:b', 'a:b')]:
            with self.subTest(flow=raw):
                self.assertEqual(self.parse('other: [codex, ' + raw + '] # context\n')['other'], ['codex', expected])
                self.f.private.write_text('review:\n  on_draft:\n    runner: [codex, ' + raw + ']\n')
                actual = self.cli('review-local-list', '--repo-root', str(self.f.checkout),
                                  '--phase', 'on_draft', '--key', 'runner')
                if '\x1b' in expected:
                    # The scalar is valid YAML above, but not a reviewer name.
                    self.assertEqual(actual.returncode, 2, actual.stdout + actual.stderr)
                    self.assertEqual(actual.stdout, '')
                    self.assertIn('schema', actual.stderr)
                    self.assertNotIn('fabricatedOpaqueControlName', actual.stdout + actual.stderr)
                else:
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

    def test_P08_modern_review_uses_same_dependency_free_reader(self):
        result = self.cli('review-effective', '--repo-root', str(self.f.checkout))
        self.assertEqual(result.returncode, 0, result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report['effective_runner'], ['codex'])
        self.assertEqual(report['effective_runner_state'], 'defined')
        self.assertEqual(report['unreadable_detail'], '')
        self.assertEqual(result.stderr, '')

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

    def test_P11_pinned_develop_fixture_syntax_parity_without_pyyaml(self):
        corpus = json.loads((Path(__file__).parent / 'fixtures/1993-selected-yaml-parity.json').read_text())
        self.assertEqual(corpus['base'], '25e702d2cf8ea5c7d97c9080a44fec84a3607a63')
        self.assertEqual(len(corpus['cases']), 1020)
        self.assertEqual(sum(len(case['origins']) for case in corpus['cases']), 2117)
        for case in corpus['cases']:
            with self.subTest(origins=case['origins']):
                self.parse(case['raw'])
                self.f.private.write_text(case['raw'])
                actual = self.cli('yaml-source-check', '--file', str(self.f.private))
                self.assertEqual(actual.returncode, 0, actual.stdout + actual.stderr)
                self.assertEqual(actual.stdout, '')

    def test_P12_spaced_mapping_syntax_keeps_schema_independent(self):
        for raw in ('review : {}\n', 'review\t: {}\n',
                    'items:\n  - name : first\n    value : second\n'):
            with self.subTest(raw=raw):
                self.parse(raw)
                self.f.private.write_text(raw)
                actual = self.cli('review-overrides', '--repo-root', str(self.f.checkout))
                self.assertEqual(actual.returncode, 0, actual.stdout + actual.stderr)
        for raw in ('review:\n  broken mapping\n', 'review:\n  on_draft:\n    runner:[]\n',
                    'review:\n  on_draft:\n    runner:null\n', 'review:\n  on_draft:{}\n',
                    'review:\n  internal_reviewers_unavailable_policy:warn\n'):
            with self.subTest(schema=raw):
                self.parse(raw)
                self.f.private.write_text(raw)
                actual = self.cli('review-local-list', '--repo-root', str(self.f.checkout),
                                  '--phase', 'on_draft', '--key', 'runner')
                self.assertEqual(actual.returncode, 2)
                self.assertEqual(actual.stdout, '')
                self.assertIn('schema', actual.stderr)

    def test_P13_baseline_quote_comment_and_flow_mapping_contracts(self):
        self.assertEqual(self.parse('policy: "warn"#comment\n')['policy'], 'warn')
        self.f.private.write_text('review:\n  on_draft:\n    runner: [codex, extra:]\n')
        legacy = self.cli('review-overrides', '--repo-root', str(self.f.checkout))
        self.assertEqual(legacy.returncode, 0, legacy.stderr)
        self.assertIn('REVIEW_ON_DRAFT_RUNNER=codex,extra:', legacy.stdout)
        strict = self.cli('review-local-list', '--repo-root', str(self.f.checkout),
                          '--phase', 'on_draft', '--key', 'runner')
        self.assertEqual(strict.returncode, 2)
        self.assertEqual(strict.stdout, '')
        self.assertIn('flow mapping', strict.stderr)

    def test_P14_internal_flow_indicators_cannot_fall_back_to_shared(self):
        buckets = (('on_draft', 'runner'), ('on_draft', 'github'), ('on_ready', 'github'))
        # No local reviewer declaration: accepting the unrelated malformed
        # scalar would otherwise emit the different shared policy successfully.
        for token in ('fabricatedOpaqueFlow?value', 'fabricatedOpaqueFlow??value',
                      'fabricatedOpaqueFlow? tail'):
            raw = 'other: [' + token + ']\n'
            with self.assertRaises(resolver.ConfigError):
                resolver.parse_review_yaml(self.path, raw=raw)
            self.f.private.write_text(raw)
            for phase, key in buckets:
                with self.subTest(invalid=token, phase=phase, key=key):
                    result = self.cli('review-list', '--repo-root', str(self.f.checkout),
                                      '--shared-file', str(self.f.shared), '--apply-local',
                                      '--phase', phase, '--key', key)
                    self.assertEqual(result.returncode, 2)
                    self.assertEqual(result.stdout, '')
                    self.assertEqual(result.stderr, 'ERROR: configuration: invalid YAML; line=1\n')
                    self.assertNotIn('fabricatedOpaqueFlow', result.stdout + result.stderr)
                    self.assertNotIn('shared-policy-sentinel', result.stdout + result.stderr)
        # Quoted punctuation, nonflow plain punctuation and valid flow
        # separators retain their syntax and legitimate shared fallback.
        for raw in ("other: ['fabricatedOpaqueFlow?value']\n",
                    'other: ["fabricatedOpaqueFlow?,[]{}:value"]\n',
                    'other: fabricatedOpaqueFlow?,[]{}:value\n',
                    'other: [first, second, a:b]\n'):
            resolver.parse_review_yaml(self.path, raw=raw)
            self.f.private.write_text(raw)
            for phase, key in buckets:
                with self.subTest(valid=raw, phase=phase, key=key):
                    result = self.cli('review-list', '--repo-root', str(self.f.checkout),
                                      '--shared-file', str(self.f.shared), '--apply-local',
                                      '--phase', phase, '--key', key)
                    self.assertEqual((result.returncode, result.stdout, result.stderr),
                                     (0, 'shared-policy-sentinel\n', ''))
                    self.assertNotIn('fabricatedOpaqueFlow', result.stdout + result.stderr)
        for declaration, expected in (('[codex]', 'codex\n'), ('[]', '')):
            self.f.private.write_text('review:\n  on_draft:\n    runner: ' + declaration + '\n')
            result = self.cli('review-list', '--repo-root', str(self.f.checkout),
                              '--shared-file', str(self.f.shared), '--apply-local',
                              '--phase', 'on_draft', '--key', 'runner')
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, expected, ''))

    def test_P15_all_indicator_positions_and_adjacencies_match_strict_syntax(self):
        # Existing test-only PyYAML is the syntax oracle, not a runtime dependency.
        import yaml
        rejected = 0
        supported_valid_ids = []
        for index, (context, position, raw) in enumerate(indicator_context_cases(), 1):
            try:
                yaml.compose(raw, Loader=yaml.BaseLoader)
                syntax_valid = True
            except yaml.YAMLError:
                syntax_valid = False
            with self.subTest(case=index, context=context, position=position):
                if not syntax_valid:
                    rejected += 1
                    with self.assertRaises(resolver.ConfigError):
                        self.parse(raw)
                else:
                    try:
                        self.parse(raw)
                    except resolver.ConfigError:
                        pass  # Existing unsupported-valid grammar remains outside this subset.
                    else:
                        supported_valid_ids.append(index)
        self.assertEqual(index, 8788)
        self.assertEqual(rejected, 4775)
        # Baseline5d94 accepted IDs among syntax-valid cases, frozen independently
        # of the corrected parser. Bind every supported valid form, not only quotes.
        # The common reader also preserves four old-modern-supported compact
        # block collections that the former selected-only grammar rejected.
        additions = {248, 267, 268, 647}
        self.assertEqual(len(supported_valid_ids), 3461)
        self.assertTrue(additions.issubset(supported_valid_ids))
        baseline_ids = [index for index in supported_valid_ids if index not in additions]
        self.assertEqual(len(baseline_ids), 3457)
        self.assertEqual(hashlib.sha256(json.dumps(baseline_ids, separators=(',', ':')).encode()).hexdigest(),
                         'd165665d3e57457d99e44b4302101efdbf02456f6f794ee9c8df913b38ba9a7b')
        # A leading '?' can introduce an entry, not a mapping's value. Valid
        # explicit sequence entries and nested entries keep their existing shape.
        for raw, expected in [('other: [?a]\n', [{'a': None}]),
                              ('other: [? a: b]\n', [{'a': 'b'}]),
                              ('other: {a: [?b]}\n', {'a': [{'b': None}]})]:
            self.assertEqual(self.parse(raw)['other'], expected)

    def test_P16_invalid_entry_indicators_fail_before_legacy_and_shared_policy(self):
        # Frozen pre-correction syntax mismatches from the complete P15 matrix.
        # These are invalid YAML, independently of review-field shape/schema.
        regression_ids = {1142, 1218, 1522, 1598, 1712, 1788, 1902, 1978,
                          4565, 5587, 6670, 7753, 8779, 8780, 8781, 8782, 8788}
        regressions = [(index, raw) for index, (_, _, raw) in
                       enumerate(indicator_context_cases(), 1) if index in regression_ids]
        self.assertEqual(len(regressions), 17)
        shared = self.f.shared.read_text()  # This file is exclusively synthetic.
        buckets = (('on_draft', 'runner'), ('on_draft', 'github'), ('on_ready', 'github'))
        for shared_present in (True, False):
            if shared_present:
                self.f.shared.write_text(shared)
            else:
                self.f.shared.unlink()
            for index, raw in regressions:
                with self.assertRaises(resolver.ConfigError):
                    resolver.parse_review_yaml(self.path, raw=raw)
                self.f.private.write_text(raw + 'sentinel: fabricatedOpaqueIndicator\n')
                commands = [('mode', '--repo-root', str(self.f.checkout)),
                            ('review-overrides', '--repo-root', str(self.f.checkout))]
                commands += [('review-list', '--repo-root', str(self.f.checkout),
                              '--shared-file', str(self.f.shared), '--apply-local',
                              '--phase', phase, '--key', key) for phase, key in buckets]
                for arguments in commands:
                    with self.subTest(case=index, shared=shared_present, command=arguments[0],
                                      bucket=arguments[-1]):
                        result = self.cli(*arguments)
                        self.assertEqual(result.returncode, 2)
                        self.assertEqual(result.stdout, '')
                        self.assertRegex(result.stderr, r'^ERROR: configuration: (invalid YAML|unsupported YAML flow mapping); line=1\n$')
                        self.assertNotIn('fabricatedOpaqueIndicator', result.stdout + result.stderr)
                        self.assertNotIn('shared-policy-sentinel', result.stdout + result.stderr)
            # Valid unrelated syntax preserves existing shared/default behavior.
            for raw in ('other: ?valid\n', 'other: ["?quoted", "a:b", "a#b"]\n'):
                self.f.private.write_text(raw)
                mode = self.cli('mode', '--repo-root', str(self.f.checkout))
                self.assertEqual((mode.returncode, mode.stdout, mode.stderr),
                                 (0, 'WORKFLOW_MODE=workflow_hub\n' if shared_present else 'WORKFLOW_MODE=single_repo\n', ''))
                for phase, key in buckets:
                    result = self.cli('review-list', '--repo-root', str(self.f.checkout),
                                      '--shared-file', str(self.f.shared), '--apply-local',
                                      '--phase', phase, '--key', key)
                    self.assertEqual((result.returncode, result.stdout, result.stderr),
                                     (0, 'shared-policy-sentinel\n' if shared_present else '', ''))
        self.f.shared.write_text(shared)

    def test_P17_complete_forbidden_character_matrix_and_escaped_controls(self):
        import yaml
        forbidden = ([code for code in range(32) if code not in (9, 10, 13)] +
                     [code for code in range(127, 160) if code != 133] +
                     list(range(0xD800, 0xE000)) + [0xFFFE, 0xFFFF])
        self.assertEqual(len(forbidden), 2111)
        templates = ('other: fabricatedOpaque{}tail\n', 'other: "fabricatedOpaque{}tail"\n',
                     "other: 'fabricatedOpaque{}tail'\n", '# fabricatedOpaque{}tail\nother: valid\n')
        for code in forbidden:
            for context, template in enumerate(templates):
                raw = template.format(chr(code))
                with self.subTest(code=code, context=context):
                    with self.assertRaises(yaml.YAMLError):
                        yaml.compose(raw, Loader=yaml.BaseLoader)
                    with self.assertRaises(resolver.ConfigError):
                        resolver.parse_review_yaml(self.path, raw=raw)
                    with self.assertRaises(resolver.ConfigError):
                        self.parse(raw)
            escaped = 'other: "\\u' + f'{code:04X}' + '"\n'
            with self.subTest(escaped_code=code):
                yaml.compose(escaped, Loader=yaml.BaseLoader)
                if code == 0 or 0xD800 <= code <= 0xDFFF:
                    for reader in (self.parse, lambda raw: resolver.parse_review_yaml(self.path, raw=raw)):
                        with self.assertRaises(resolver.ConfigError):
                            reader(escaped)
                else:
                    self.assertEqual(self.parse(escaped)['other'], chr(code))
                    self.assertEqual(resolver.parse_review_yaml(self.path, raw=escaped)['other'], chr(code))
        for code in (0x1FFFE, 0x1FFFF, 0x10FFFE, 0x10FFFF):
            raw = 'other: "' + chr(code) + '"\n'
            yaml.compose(raw, Loader=yaml.BaseLoader)
            self.assertEqual(self.parse(raw)['other'], chr(code))
            self.assertEqual(resolver.parse_review_yaml(self.path, raw=raw)['other'], chr(code))

    def test_P18_frozen_modern_reader_support_and_single_authority(self):
        from unittest import mock
        accepted = []
        for case, raw in modern_reader_cases():
            with self.subTest(case=case):
                try:
                    value = resolver.parse_review_yaml(self.path, raw=raw)
                except resolver.ConfigError:
                    continue
                accepted.append((case, value))
        # Frozen a447 strict-reader accepted values, independent of the replacement.
        self.assertEqual(len(accepted), 1025)
        self.assertEqual(hashlib.sha256(json.dumps(accepted, ensure_ascii=True, sort_keys=True,
                                                   separators=(',', ':')).encode()).hexdigest(),
                         '53aaa7b9285e9be3bd25a865628cb40cb56b69df35625c6701f22e24f5e8aba7')
        # Frozen old strict-reader support beyond the former selected-only cap.
        # Malformed counterparts still fail; Python recursion exhaustion is safe.
        for depth in (101, 110, 150):
            raw = 'other: ' + '[' * depth + 'tail' + ']' * depth + '\n'
            expected = 'tail'
            for _ in range(depth):
                expected = [expected]
            self.assertEqual(resolver.parse_review_yaml(self.path, raw=raw), {'other': expected})
            self.assertEqual(self.parse(raw), {'other': expected})
            for malformed in (raw.replace(']', '', 1), raw.rstrip() + ']\n'):
                with self.assertRaises(resolver.ConfigError):
                    resolver.parse_review_yaml(self.path, raw=malformed)
                with self.assertRaises(resolver.ConfigError):
                    self.parse(malformed)
        with self.assertRaises(resolver.ConfigError):
            self.parse('other: ' + '[' * 2000 + 'tail' + ']' * 2000 + '\n')
        # These exact AST shapes are frozen from the old modern strict reader.
        for raw, expected in [('other:\n  - -\n', {'other': [[None]]}),
                              ('other:\n  - - key: tail\n', {'other': [[{'key': 'tail'}]]}),
                              ('other:\n  - ? codex\n', {'other': [{'codex': None}]}),
                              ('other:\n  - - codex\n', {'other': [['codex']]})]:
            self.assertEqual(resolver.parse_review_yaml(self.path, raw=raw), expected)
            self.assertEqual(self.parse(raw), expected)
        for raw, expected in [
                ('other:\n  - - first\n    - second\n', {'other': [['first', 'second']]}),
                ('? key\n: value\n', {'key': 'value'}),
                ('other:\n  ? key\n  : value\n', {'other': {'key': 'value'}}),
                ('other:\n  - ? key\n    : value\n', {'other': [{'key': 'value'}]}),
                ('other:\n  - ? key\n    : value\n    extra: tail\n', {'other': [{'key': 'value', 'extra': 'tail'}]})]:
            self.assertEqual(resolver.parse_review_yaml(self.path, raw=raw), expected)
            self.assertEqual(self.parse(raw), expected)
        for raw in ('? "key"\n: value\n', 'other:\n  - ? key\n    :\n      - first\n      - second\n'):
            with self.assertRaises(resolver.ConfigError):
                resolver.parse_review_yaml(self.path, raw=raw)
        raw = 'review:\n  on_draft:\n    runner:\n      - name: codex\n        name: cursor\n'
        with self.assertRaises(resolver.ConfigError) as duplicate:
            resolver.parse_review_yaml(self.path, raw=raw)
        self.assertEqual((duplicate.exception.error_type, duplicate.exception.line), ('duplicate mapping key', 5))
        raw = 'other: ["quoted", 0x10, true, null]\n'
        with mock.patch.object(resolver, 'parse_review_yaml', wraps=resolver.parse_review_yaml) as reader:
            self.assertEqual(self.parse(raw)['other'], ['quoted', 16, True, None])
            reader.assert_called_once_with(self.path, raw=raw, review_fields=False)
        for linebreak in ('\r', '\r\n', '\x85', '\u2028', '\u2029'):
            raw = 'first: value' + linebreak + 'second: tail\n'
            self.assertEqual(resolver.parse_review_yaml(self.path, raw=raw), {'first': 'value', 'second': 'tail'})
        self.assertEqual(resolver.parse_review_yaml(self.path, raw='items:\n  -\tvalue\n'), {'items': ['value']})
        for space in ('\u00a0', '\u2000', '\u3000'):
            with self.assertRaises(resolver.ConfigError):
                resolver.parse_review_yaml(self.path, raw=space + '\n')

    def test_P19_literal_noncharacters_cannot_reach_legacy_or_shared_fallback(self):
        shared = self.f.shared.read_text()  # Synthetic fixture only.
        buckets = (('on_draft', 'runner'), ('on_draft', 'github'), ('on_ready', 'github'))
        templates = ('other: fabricatedOpaque{}tail\n', 'other: "fabricatedOpaque{}tail"\n',
                     "other: 'fabricatedOpaque{}tail'\n", '# fabricatedOpaque{}tail\n')
        for shared_present in (True, False):
            if shared_present:
                self.f.shared.write_text(shared)
            else:
                self.f.shared.unlink()
            for code in (0xFFFE, 0xFFFF):
                for context, template in enumerate(templates):
                    self.f.private.write_text(template.format(chr(code)) + self.valid)
                    commands = [('mode', '--repo-root', str(self.f.checkout)),
                                ('review-overrides', '--repo-root', str(self.f.checkout))]
                    commands += [('review-list', '--repo-root', str(self.f.checkout),
                                  '--shared-file', str(self.f.shared), '--apply-local',
                                  '--phase', phase, '--key', key) for phase, key in buckets]
                    for arguments in commands:
                        with self.subTest(code=code, context=context, shared=shared_present, command=arguments[0], bucket=arguments[-1]):
                            result = self.cli(*arguments)
                            self.assertEqual((result.returncode, result.stdout), (2, ''))
                            self.assertRegex(result.stderr, r'^ERROR: configuration: invalid YAML; line=1; column=[0-9]+\n$')
                            self.assertNotIn('fabricatedOpaque', result.stdout + result.stderr)
                            self.assertNotIn(chr(code), result.stdout + result.stderr)
                            self.assertNotIn('shared-policy-sentinel', result.stdout + result.stderr)
                    # Ordinary malformed config keeps the modern structured report/status0.
                    with self.subTest(code=code, context=context, shared=shared_present, modern=True):
                        modern = self.cli('review-effective', '--repo-root', str(self.f.checkout))
                        self.assertEqual(modern.returncode, 0)
                        data = json.loads(modern.stdout)
                        self.assertEqual(data['effective_policy_state'], 'unreadable')
                        self.assertEqual(data['effective_runner'], [])
                        self.assertRegex(data['unreadable_detail'], r'^configuration: invalid YAML; line=1; column=[0-9]+$')
                        self.assertEqual(modern.stderr, '')
                        self.assertNotIn(chr(code), modern.stdout + modern.stderr)
                        self.assertNotIn('fabricatedOpaque', modern.stdout + modern.stderr)
            with self.subTest(shared=shared_present, valid_escaped_control=True):
                self.f.private.write_text(self.valid + 'other: ["\\uFFFE", "\\uFFFF"]\n')
                result = self.cli('review-effective', '--repo-root', str(self.f.checkout))
                self.assertEqual(result.returncode, 0)
                data = json.loads(result.stdout)
                self.assertEqual(data['effective_runner'], ['codex'])
                self.assertEqual(data['unreadable_detail'], '')
        self.f.shared.write_text(shared)


if __name__ == '__main__':
    unittest.main(verbosity=2)

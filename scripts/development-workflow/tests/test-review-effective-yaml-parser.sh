#!/usr/bin/env bash
# covers: scripts/development-workflow/workflow-config-resolver.py
# Whole-document syntax and dependency contract for the strict YAML reader.
set -euo pipefail
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
python3 - "$SCRIPT_DIR/../workflow-config-resolver.py" <<'PY'
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile

import yaml

spec = importlib.util.spec_from_file_location('resolver', sys.argv[1])
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)
passed = 0

with tempfile.TemporaryDirectory(prefix='review-yaml-parser-') as tmp:
    root = pathlib.Path(tmp).resolve()
    shared = root / '.ai-dev-workflow.yaml'
    local = root / '.ai-dev-workflow.local.yaml'
    missing = root / 'missing-dependency'
    missing.mkdir()
    (missing / 'yaml.py').write_text('raise ImportError("planted missing dependency")\n')
    valid = 'review:\n  on_draft:\n    runner: [codex]\n'

    def effective(source, text, env=None):
        local.unlink(missing_ok=True)
        shared.write_text(valid)
        source.write_text(text)
        return json.loads(subprocess.check_output([
            sys.executable, sys.argv[1], 'review-effective', '--repo-root', tmp,
        ], env=env))

    for source in (shared, local):
        for flow in ('[codex,:bad]', '[:bad]', '[[codex,:bad]]', '[codex,#]',
                     '[a[b]', '[a]b]', '[a,,b]', '["a" "b"]'):
            result = effective(source, 'review:\n  on_draft:\n    runner: '+flow+'\n')
            assert result['effective_runner_state'] == 'malformed', result
            assert result['effective_policy_state'] == 'unreadable', result
            assert result['unreadable_file'] == str(source), result
            passed += 1
        for token, value in (('":bad"', ':bad'), ("':bad'", ':bad'),
                             ('"#literal"', '#literal'), ('a:b', 'a:b'),
                             ('a#b', 'a#b'), ('foo "', 'foo "'),
                             ('"a\\e[2J"', 'a\x1b[2J')):
            result = effective(source, 'review:\n  on_draft:\n    runner: [codex,'+token+'] # comment\n')
            assert result['effective_runner'] == ['codex', value], result
            assert result['effective_runner_state'] == 'defined', result
            passed += 1
        for invalid in ('broken: "unterminated', 'broken: a: b', 'broken: %reserved',
                        'broken: [a[b]', 'broken: \x07', '# comment \x00'):
            for text in (invalid+'\n'+valid, valid+invalid+'\n'):
                result = effective(source, text)
                assert result['effective_policy_state'] == 'unreadable', result
                passed += 1
        for unsupported in ('other: !!python/object/apply:os.system ["false"]',
                            'other: &anchor value', 'other: *anchor',
                            'other: {key: value}', 'other: value\nother: duplicate',
                            'other:\n  key: value\n  key: duplicate'):
            result = effective(source, unsupported+'\n'+valid)
            assert result['effective_policy_state'] == 'unreadable', result
            passed += 1
        if hasattr(sys, 'get_int_max_str_digits') and sys.get_int_max_str_digits():
            result = effective(source, 'other: '+('1'*(sys.get_int_max_str_digits()+1))+'\n'+valid)
            assert result['effective_policy_state'] == 'unreadable', result
            assert 'scalar conversion' in result['unreadable_detail'], result
            passed += 1
        result = effective(source, valid, {**os.environ, 'PYTHONPATH': str(missing)})
        assert result['effective_policy_state'] == 'unreadable', result
        assert 'install PyYAML==6.0.2' in result['unreadable_detail'], result
        legacy = subprocess.check_output([
            sys.executable, sys.argv[1], 'review-overrides', '--repo-root', tmp,
        ], env={**os.environ, 'PYTHONPATH': str(missing)}, text=True)
        assert 'REVIEW_ON_DRAFT_RUNNER=' in legacy, legacy
        if source == local:
            assert 'REVIEW_ON_DRAFT_RUNNER=codex' in legacy, legacy
        passed += 1

    # Document the parser's line-break boundary without emulating its scanner.
    for linebreak in ('\u0085', '\u2028', '\u2029'):
        shared.write_text('other: "a'+linebreak+'b"\n')
        try:
            resolver.parse_yaml_subset(shared, preserve_empty_values=True)
        except resolver.ConfigError as exc:
            assert 'multiline' in str(exc), exc
            passed += 1
        else:
            raise AssertionError('raw YAML linebreak became ordinary whitespace')
    shared.write_text('other: "a\\u2028b"\n')
    assert resolver.parse_yaml_subset(shared, preserve_empty_values=True)['other'] == 'a\u2028b'
    passed += 1

    # Generated punctuation combinations must never turn parser-rejected YAML
    # into an accepted strict config; this guards beyond the reported token.
    rejected = 0
    tokens = [':bad', '#', 'a[b', 'a]b', '? x', '- x', 'a:b', 'a#b', '"x"', 'x']
    for first in tokens:
        for second in tokens:
            text = 'other: ['+first+','+second+']\n'+valid
            try:
                yaml.compose(text, Loader=yaml.BaseLoader)
            except yaml.YAMLError:
                rejected += 1
                shared.write_text(text)
                try:
                    resolver.parse_yaml_subset(shared, preserve_empty_values=True)
                except resolver.ConfigError:
                    passed += 1
                else:
                    raise AssertionError(text)
    assert rejected > 30, rejected

print(f'{passed} strict YAML parser assertions passed')
PY

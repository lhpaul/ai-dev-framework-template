#!/usr/bin/env python3
"""Synthetic-only runner security regressions. Never load workstation settings."""
from __future__ import annotations

import ast
import base64
import importlib.util
import json
import os
import re
import shlex
import signal
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / 'scripts/development-workflow'
RESOLVER = SCRIPTS / 'workflow-config-resolver.py'
# Import safety: configuration reads occur only in function bodies, never at import.
TREE = ast.parse(RESOLVER.read_text())
for node in TREE.body:
    if isinstance(node, ast.Expr) and not isinstance(node.value, ast.Constant):
        raise AssertionError('unexpected import-time execution')
SPEC = importlib.util.spec_from_file_location('synthetic_runner_resolver', RESOLVER)
MODULE = importlib.util.module_from_spec(SPEC)
with patch.object(Path, 'read_text', side_effect=AssertionError('import read configuration')), \
        patch.object(Path, 'read_bytes', side_effect=AssertionError('import read configuration')), \
        patch.object(Path, 'open', side_effect=AssertionError('import opened configuration')):
    SPEC.loader.exec_module(MODULE)

# Only public shared configuration is consulted for template-owned artifact checks.
IS_TEMPLATE = MODULE.parse_yaml_subset(ROOT / '.ai-dev-workflow.yaml').get('template', {}).get('is_template') is True


def function_text(file: str, name: str) -> str:
    """Extract an existing Bash function, retaining real composed implementation."""
    source = (SCRIPTS / file).read_text()
    start = source.index(name + '() {')
    end = source.index('\n}', start) + 2
    return source[start:end]


class RunnerSecurityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='runner-security-1993-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.checkout = self.root / 'checkout'
        self.checkout.mkdir()
        self.external = self.root / 'external'
        self.external.mkdir()
        self.env = dict(os.environ)
        for key in list(self.env):
            if key.startswith(('WORKFLOW_', 'AI_DEV_WORKFLOW_', 'LOCAL_AI_REVIEWER_', 'CODERABBIT_CLI_')) or re.search(
                    r'token|secret|password|passphrase|api.?key|access.?key|credential', key, re.IGNORECASE):
                self.env.pop(key, None)
        self.env.update(GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_SYSTEM='/dev/null',
                        GIT_CONFIG_NOSYSTEM='1', GIT_TERMINAL_PROMPT='0')
        self.env['PYTHONDONTWRITEBYTECODE'] = '1'
        runtimes = self.root / 'runtime-stubs'; runtimes.mkdir()
        for binary in ('codex', 'claude', 'cursor', 'dsh', 'coderabbit', 'cr', 'gh'):
            stub = runtimes / binary
            stub.write_text('#!/bin/sh\nexit 99\n'); stub.chmod(0o755)
        self.env['PATH'] = str(runtimes) + os.pathsep + self.env['PATH']

    def write(self, text: str, root: Path | None = None, local=True):
        path = (root or self.checkout) / (MODULE.LOCAL_CONFIG_NAME if local else '.ai-dev-workflow.yaml')
        path.write_text(text)
        return path

    def cli(self, command, *args, env=None):
        return subprocess.run([sys.executable, str(RESOLVER), command,
                               '--repo-root', str(self.checkout), *args],
                              env=env or self.env, text=True, capture_output=True)

    def bash(self, expression, *, extra='', env=None):
        # The library only defines functions. Override its root before any config use.
        script = f'source {str(SCRIPTS / "workflow-lib.sh")!r}\nworkflow_repo_root() {{ printf "%s\\n" {str(self.checkout)!r}; }}\n'
        return subprocess.run(['bash', '-c', script + extra + '\n' + expression],
                              env=env or self.env, text=True, capture_output=True)

    def selected_race_fixture(self):
        # Each action starts with a fresh disposable regular fixture, even if
        # the preceding action deliberately left a FIFO at that fake path.
        (self.external / MODULE.LOCAL_CONFIG_NAME).unlink(missing_ok=True)
        source = self.write('review:\n  on_draft:\n    runner: [codex]\n    github: [pr-agent]\n  on_ready:\n    github: [coderabbit]\n  coderabbit_cli:\n    rate_limit_policy: strict\nignored: fabricated-original-opaque\n', self.external)
        self.write('review:\n  on_draft:\n    runner: [claude]\n    github: [ronda]\n  on_ready:\n    github: [bugbot]\n  coderabbit_cli:\n    rate_limit_policy: warn\n', local=False)
        bindir = self.root / 'race-bin'
        bindir.mkdir(exist_ok=True)
        wrapper = bindir / 'python3'
        wrapper.write_text(f'#!{sys.executable}\n' + r"""
import importlib.util, os, pathlib, sys
args = sys.argv[1:]
if not args or not args[0].endswith('workflow-config-resolver.py'):
    os.execv(os.environ['RACE_PYTHON'], [os.environ['RACE_PYTHON'], *args])
spec = importlib.util.spec_from_file_location('race_resolver', args[0])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
source = pathlib.Path(os.environ['RACE_SOURCE'])
original = m.validate_local_source
changed = False
def selection(*a, **kw):
    global changed
    path = original(*a, **kw)
    if path == source and not changed:
        changed = True
        action = os.environ['RACE_ACTION']
        if action == 'remove': source.unlink()
        elif action == 'fifo':
            source.unlink(); os.mkfifo(source)
        elif action in ('valid', 'invalid'):
            replacement = source.parent / 'fabricated-replacement'
            replacement.write_text('review: [fabricated-invalid-opaque' if action == 'invalid' else
                'review:\n  on_draft:\n    runner: [fabricated-replaced-opaque]\n    github: [fabricated-replaced-opaque]\n  on_ready:\n    github: [fabricated-replaced-opaque]\n  coderabbit_cli:\n    rate_limit_policy: warn\n')
            replacement.replace(source)
        pathlib.Path(os.environ['RACE_MARKER']).write_text('selected')
    return path
m.validate_local_source = selection
identity = m.source_identity
replaced = False
def checked_identity(path):
    global replaced
    result = identity(path)
    if path == source and not replaced and os.environ['RACE_ACTION'] == 'fifo-open' and (changed or os.environ.get('RACE_DIRECT') == '1'):
        replaced = True
        source.unlink(); os.mkfifo(source)
        pathlib.Path(os.environ['RACE_MARKER']).write_text('identity-checked')
    return result
m.source_identity = checked_identity
sys.exit(m.main(args[1:]))
""")
        wrapper.chmod(0o755)
        env = dict(self.env, WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT=str(self.external),
                   RACE_SOURCE=str(source), RACE_PYTHON=sys.executable,
                   RACE_MARKER=str(self.root / 'selected-marker'),
                   PATH=str(bindir) + os.pathsep + self.env['PATH'])
        return source, wrapper, env

    def bounded_source(self, argv, env):
        # Kill and reap our entire synthetic process group if the old blocking
        # opener waits for a FIFO writer; no writer or external service exists.
        child = subprocess.Popen(argv, env=env, text=True, stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, start_new_session=True)
        try:
            out, err = child.communicate(timeout=3)
            return subprocess.CompletedProcess(argv, child.returncode, out, err)
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            out, err = child.communicate()
            return subprocess.CompletedProcess(argv, 124, out, err)

    def selected_race_route(self, route, actions=('stable', 'remove', 'valid', 'invalid')):
        for action in actions:
            with self.subTest(route=route, action=action):
                source, wrapper, env = self.selected_race_fixture()
                env['RACE_ACTION'] = action
                stage = self.root / ('stage-' + action); stage.mkdir(exist_ok=True)
                shared = self.checkout / '.ai-dev-workflow.yaml'
                commands = {
                    'R01': ['mode'], 'R02': ['review-effective'], 'R03': ['review-github-effective'],
                    'R04': ['review-overrides', '--json'], 'R05': ['model-routes', '--runner', 'dsh', '--json'],
                    'R07': ['review-snapshot', '--destination', str(stage)], 'R08': ['local-source'],
                    'R09': ['review-list', '--apply-local', '--shared-file', str(shared), '--phase', 'on_draft', '--key', 'runner'],
                    'R10': ['review-local-list', '--phase', 'on_draft', '--key', 'runner']}
                if route == 'R06':
                    # The writer's direct validate->initial capture route uses
                    # checkout-local authority even with an external model/review
                    # selection: this forces the writer's own initial capture.
                    local = self.checkout / MODULE.LOCAL_CONFIG_NAME
                    local.write_text(source.read_text())
                    env['RACE_SOURCE'] = str(local)
                    commands[route] = ['set-local-path', '--repo', 'synthetic', '--local-path', '.']
                    # It requires an existing repo declaration to reach a valid write.
                    local.write_text('product_repos:\n  - name: synthetic\n    local_path: .\n')
                    self.write('mode: workflow_hub\nworkflow_hub:\n  product_repos:\n    - name: synthetic\n      github_repo: fabricated/synthetic\n', local=False)
                if route in ('R12', 'R13'): env['RACE_DIRECT'] = '1'
                if route in ('R11', 'R12'):
                    extra = function_text('coderabbit-cli-reviewer.sh', 'rate_limit_policy_from_file') + '\n' + function_text('coderabbit-cli-reviewer.sh', 'rate_limit_policy_from_config')
                    expression = 'rate_limit_policy_from_config' if route == 'R11' else 'rate_limit_policy_from_file "$RACE_SOURCE"'
                    script = f'source {shlex.quote(str(SCRIPTS / "workflow-lib.sh"))}\nworkflow_repo_root() {{ printf "%s\\n" {shlex.quote(str(self.checkout))}; }}\n' + extra + '\n' + expression
                    result = self.bounded_source(['/bin/bash', '-c', script], env)
                else:
                    args = (['yaml-source-check', '--file', str(source)] if route == 'R13' else
                            [*commands[route], '--repo-root', str(self.checkout)])
                    result = self.bounded_source([str(wrapper), str(RESOLVER), *args], env)
                self.assertTrue((self.root / 'selected-marker').exists(), 'actual selected-source boundary not reached')
                if action == 'stable':
                    self.assertEqual(result.returncode, 0, result.stderr)
                    if route in ('R09', 'R10'): self.assertEqual(result.stdout, 'codex\n')
                    if route in ('R11', 'R12'): self.assertEqual(result.stdout, 'strict')
                else:
                    self.assertEqual(result.returncode, 2, result.stderr)
                    self.assertEqual(result.stdout, '', 'partial output or shared fallback')
                    self.assertEqual(result.stderr, 'ERROR: configuration: selected source changed during capture\n')
                    self.assertNotRegex(result.stdout + result.stderr, r'fabricated-|claude|ronda|bugbot|' + re.escape(str(self.root)))
                    self.assertFalse((stage / MODULE.LOCAL_CONFIG_NAME).exists())
                (self.root / 'selected-marker').unlink()

    def test_nonregular_checked_open_all_thirteen_routes(self):
        # Replace the regular source AFTER source_identity returned its regular
        # stamp, BEFORE the open. A pre-open is_file check alone cannot pass.
        for number in range(1, 14):
            self.selected_race_route(f'R{number:02d}', actions=('fifo-open',))

    def test_nonregular_initial_and_post_validation(self):
        source = self.external / 'fabricated-fifo-opaque'
        os.mkfifo(source)
        for path in (source, self.external):
            result = self.bounded_source([sys.executable, str(RESOLVER), 'yaml-source-check', '--file', str(path)], self.env)
            self.assertEqual((result.returncode, result.stdout), (2, ''))
            self.assertNotRegex(result.stdout + result.stderr, 'fabricated-|'+re.escape(str(self.root)))
        source.unlink()
        self.selected_race_route('R09', actions=('fifo',))

    def test_nonregular_three_bash_buckets(self):
        for shell in ('/bin/bash', '/opt/homebrew/bin/bash'):
            if not Path(shell).exists(): continue
            for getter in ('workflow_config_review_on_draft_runner', 'workflow_config_review_on_draft_github', 'workflow_config_review_on_ready_github'):
                with self.subTest(shell=shell, getter=getter):
                    source, wrapper, env = self.selected_race_fixture()
                    env['RACE_ACTION'] = 'fifo-open'
                    script = f'source {shlex.quote(str(SCRIPTS / "workflow-lib.sh"))}\nworkflow_repo_root() {{ printf "%s\\n" {shlex.quote(str(self.checkout))}; }}\n{getter}'
                    result = self.bounded_source([shell, '-c', script], env)
                    self.assertEqual((result.returncode, result.stdout, result.stderr),
                                     (2, '', 'ERROR: configuration: selected source changed during capture\n'))
                    self.assertEqual((self.root / 'selected-marker').read_text(), 'identity-checked')
                    (self.root / 'selected-marker').unlink()

    def test_selected_capture_R01_legacy(self): self.selected_race_route('R01')
    def test_selected_capture_R02_runner_effective(self): self.selected_race_route('R02')
    def test_selected_capture_R03_github_effective(self): self.selected_race_route('R03')
    def test_selected_capture_R04_overrides(self): self.selected_race_route('R04')
    def test_selected_capture_R05_model(self): self.selected_race_route('R05')
    def test_selected_capture_R06_writer_initial(self): self.selected_race_route('R06')
    def test_selected_capture_R07_projection(self): self.selected_race_route('R07')
    def test_selected_capture_R08_source(self): self.selected_race_route('R08')
    def test_selected_capture_R09_effective_list(self): self.selected_race_route('R09')
    def test_selected_capture_R10_local_list(self): self.selected_race_route('R10')
    def test_selected_capture_R11_coderabbit_config(self): self.selected_race_route('R11')

    def test_selected_capture_R12_coderabbit_file(self):
        # Actual direct-file helper: mutate after validation of the captured
        # bytes; extraction must still use that capture instead of reopening.
        source, wrapper, env = self.selected_race_fixture()
        text = wrapper.read_text()
        text = text.replace('m.validate_local_source = selection', """m.validate_local_source = selection
validate = m.validate_selected_yaml
def validated(raw, path, **kw):
    result = validate(raw, path, **kw)
    if path == source:
        source.write_text('review:\\n  coderabbit_cli:\\n    rate_limit_policy: warn\\n')
        pathlib.Path(os.environ['RACE_MARKER']).write_text('validated')
    return result
m.validate_selected_yaml = validated""")
        wrapper.write_text(text)
        env['RACE_ACTION'] = 'stable'
        result = self.bash('rate_limit_policy_from_file "$RACE_SOURCE"',
                           extra=function_text('coderabbit-cli-reviewer.sh', 'rate_limit_policy_from_file'), env=env)
        self.assertEqual((self.root / 'selected-marker').read_text(), 'validated')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, 'strict')
        self.assertEqual(result.stderr, '')

    def test_selected_capture_absence_empty_and_initial_malformed(self):
        self.write('review:\n  on_draft:\n    runner: [codex]\n', local=False)
        shared = str(self.checkout / '.ai-dev-workflow.yaml')
        for local, expected in ((None, 'codex\n'), ('ignored: synthetic\n', 'codex\n'), ('review:\n  on_draft:\n    runner: []\n', '')):
            if local is not None: self.write(local)
            result = self.cli('review-list', '--shared-file', shared, '--apply-local', '--phase', 'on_draft', '--key', 'runner')
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, expected, ''))
        self.write('review: [fabricated-broken')
        result = self.cli('review-effective')
        self.assertEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data['effective_runner_state'], 'malformed')
        self.assertNotIn('fabricated-broken', result.stdout + result.stderr)

    def test_selected_capture_during_read(self, command="review-list"):
        for action in ('remove', 'valid', 'invalid'):
            for timing in ('open', 'read'):
                with self.subTest(action=action, timing=timing):
                    source, wrapper, env = self.selected_race_fixture()
                    text = wrapper.read_text()
                    hook = r"""
original_open = pathlib.Path.open
import builtins
original_builtin_open = builtins.open
def mutate():
    if os.environ['DURING_ACTION'] == 'remove': source.unlink()
    else:
        with original_open(source, 'w') as out:
            out.write('review: [fabricated-invalid-opaque' if os.environ['DURING_ACTION'] == 'invalid' else 'review: {}\n')
class Reading:
    def __init__(self, stream): self.stream = stream
    def __enter__(self): self.stream.__enter__(); return self
    def __exit__(self, *args): return self.stream.__exit__(*args)
    def fileno(self): return self.stream.fileno()
    def read(self):
        with original_open(source.parent / 'captured-read-marker', 'w') as marker: marker.write('read')
        raw = self.stream.read()
        if os.environ['DURING_TIMING'] == 'read': mutate()
        return raw
def opened(path, *args, **kw):
    mode = kw.get('mode', args[0] if args else 'r')
    if path == source and mode in ('r', 'rb'):
        if os.environ['DURING_TIMING'] == 'open': mutate()
        return Reading(original_builtin_open(path, *args, **kw))
    return original_builtin_open(path, *args, **kw)
pathlib.Path.open = opened
builtins.open = opened
"""
                    wrapper.write_text(text.replace('sys.exit(m.main(args[1:]))', hook + '\nsys.exit(m.main(args[1:]))'))
                    read_marker = source.parent / 'captured-read-marker'
                    read_marker.unlink(missing_ok=True)
                    env.update(RACE_ACTION='stable', DURING_ACTION=action, DURING_TIMING=timing)
                    args = (['yaml-source-check', '--file', str(source)] if command == 'yaml-source-check' else
                            ['review-list', '--repo-root', str(self.checkout), '--apply-local', '--shared-file',
                             str(self.checkout / '.ai-dev-workflow.yaml'), '--phase', 'on_draft', '--key', 'runner'])
                    result = subprocess.run([str(wrapper), str(RESOLVER), *args], env=env, text=True, capture_output=True)
                    self.assertEqual((result.returncode, result.stdout, result.stderr),
                                     (2, '', 'ERROR: configuration: selected source changed during capture\n'))
                    self.assertNotIn('fabricated-', result.stdout + result.stderr)
                    if timing == 'open': self.assertFalse(read_marker.exists(), 'changed FD was read before identity rejection')
                    else: self.assertTrue(read_marker.exists(), 'during-read mutation not reached')

    def test_selected_capture_R13_syntax_check(self):
        source = self.write('review: {}\n', self.external)
        result = subprocess.run([sys.executable, str(RESOLVER), 'yaml-source-check', '--file', str(source)],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, '', ''))
        source.write_text('review: [fabricated-opaque')
        for invalid in (source, self.external / 'fabricated-missing', self.external):
            result = subprocess.run([sys.executable, str(RESOLVER), 'yaml-source-check', '--file', str(invalid)],
                                    env=self.env, text=True, capture_output=True)
            self.assertEqual((result.returncode, result.stdout), (2, ''))
            self.assertNotRegex(result.stdout + result.stderr, 'fabricated-|'+re.escape(str(self.root)))
        self.test_selected_capture_during_read('yaml-source-check')

    def test_selected_capture_three_bash_buckets(self):
        for shell in ('/bin/bash', '/opt/homebrew/bin/bash'):
            if not Path(shell).exists(): continue
            for getter in ('workflow_config_review_on_draft_runner', 'workflow_config_review_on_draft_github', 'workflow_config_review_on_ready_github'):
                for action in ('stable', 'remove', 'valid', 'invalid'):
                    with self.subTest(shell=shell, getter=getter, action=action):
                        source, wrapper, env = self.selected_race_fixture()
                        env['RACE_ACTION'] = action
                        script = f'source {shlex.quote(str(SCRIPTS / "workflow-lib.sh"))}\nworkflow_repo_root() {{ printf "%s\\n" {shlex.quote(str(self.checkout))}; }}\n{getter}'
                        result = subprocess.run([shell, '-c', script], env=env, text=True, capture_output=True)
                        expected = {'workflow_config_review_on_draft_runner': 'codex\n', 'workflow_config_review_on_draft_github': 'pr-agent\n', 'workflow_config_review_on_ready_github': 'coderabbit\n'}
                        if action == 'stable': self.assertEqual((result.returncode, result.stdout, result.stderr), (0, expected[getter], ''))
                        else:
                            self.assertEqual((result.returncode, result.stdout), (2, ''))
                            self.assertIn('selected source changed during capture', result.stderr)
                            self.assertNotRegex(result.stdout + result.stderr, 'fabricated-|claude|ronda|bugbot')

    def test_selected_capture_coderabbit_optional_and_lexical(self):
        extra = function_text('coderabbit-cli-reviewer.sh', 'rate_limit_policy_from_file') + '\n' + function_text('coderabbit-cli-reviewer.sh', 'rate_limit_policy_from_config')
        for value in ('', str(self.root / 'missing'), str(self.root)):
            result = self.bash('rate_limit_policy_from_file "$OPTIONAL_FILE"', extra=extra, env=dict(self.env, OPTIONAL_FILE=value))
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, '', ''))
        result = self.bash('rate_limit_policy_from_config', extra=extra)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, '', ''))
        for separator, expected in ((b'\n', 'strict'), (b'\r\n', 'strict'), (b'\r', '')):
            source = self.external / MODULE.LOCAL_CONFIG_NAME
            source.write_bytes(b'review:\n  coderabbit_cli:\n    rate_limit_policy: strict\n'.replace(b'\n', separator))
            result = self.bash('rate_limit_policy_from_file "$OPTIONAL_FILE"', extra=extra, env=dict(self.env, OPTIONAL_FILE=str(source)))
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, expected, ''))
        # The retained legacy extractor uses AWK's POSIX space class, whose
        # Unicode membership depends on the AWK implementation and locale.
        # Probe the class independently; do not impose Python/BSD trimming on
        # the same valid YAML when CI's AWK classifies U+2003 as whitespace.
        space = subprocess.run(['awk', '{ print ($0 ~ /^[[:space:]]+$/) ? "yes" : "no" }'],
                               input='\u2003\n', env=self.env, text=True, capture_output=True)
        self.assertEqual((space.returncode, space.stderr), (0, ''))
        self.assertIn(space.stdout, ('yes\n', 'no\n'))
        unicode_expected = 'strict' if space.stdout == 'yes\n' else 'strict\u2003'
        for raw, expected in [('strict', 'strict'), ('"strict" # synthetic', 'strict'), ("'warn'", 'warn'), ('"str\\u0069ct"', 'str\\u0069ct'), ('fabricated-unknown', 'fabricated-unknown'), ('strict\u2003', unicode_expected)]:
            source = self.write('review:\n  coderabbit_cli:\n    rate_limit_policy: ' + raw + '\n', self.external)
            result = self.bash('rate_limit_policy_from_file "$OPTIONAL_FILE"', extra=extra, env=dict(self.env, OPTIONAL_FILE=str(source)))
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, expected, ''))

    def test_selected_capture_coderabbit_extractor_failure(self):
        source = self.write('review:\n  coderabbit_cli:\n    rate_limit_policy: strict\n', self.external)
        bindir = self.root / 'extractor-bin'; bindir.mkdir()
        awk = bindir / 'awk'
        awk.write_text('#!/bin/sh\nprintf "%s\\n" fabricated-child-opaque\nprintf "%s\\n" fabricated-child-opaque >&2\nexit 17\n')
        awk.chmod(0o755)
        env = dict(self.env, PATH=str(bindir) + os.pathsep + self.env['PATH'], OPTIONAL_FILE=str(source))
        result = self.bash('rate_limit_policy_from_file "$OPTIONAL_FILE"',
                           extra=function_text('coderabbit-cli-reviewer.sh', 'rate_limit_policy_from_file'), env=env)
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (2, '', 'ERROR: configuration: configuration validation error\n'))
        self.assertNotIn('fabricated-', result.stdout + result.stderr)
        # Original Bash command substitution strips LF only. Keep CR bytes in
        # functional output, while containing opaque child stderr on success.
        awk.write_text('#!/bin/sh\nprintf "strict\\r\\n"\nprintf "%s\\n" fabricated-child-opaque >&2\n')
        script = 'source ' + shlex.quote(str(SCRIPTS / 'workflow-lib.sh')) + '\n' + function_text('coderabbit-cli-reviewer.sh', 'rate_limit_policy_from_file') + '\nrate_limit_policy_from_file "$OPTIONAL_FILE"'
        result = subprocess.run(['/bin/bash', '-c', script], env=env, capture_output=True)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, b'strict\r', b''))

    def test_source_isolation(self):
        main = self.root / 'main'
        (main / '.git/worktrees/linked').mkdir(parents=True)
        (self.checkout / '.git').write_text(f'gitdir: {main}/.git/worktrees/linked\n')
        self.write('review:\n  on_draft:\n    runner: [fabricated-primary]\n', main)
        for local in (None, '', 'product_repos: []\n', 'review: {}\n'):
            if local is not None:
                self.write(local)
            with patch.dict(os.environ, self.env, clear=True):
                with patch.object(MODULE, 'linked_worktree_main_root', create=True,
                                  side_effect=AssertionError('ancestry discovery')):
                    path, origin, metadata = MODULE.resolve_local_config(self.checkout)
            self.assertEqual(path, self.checkout / MODULE.LOCAL_CONFIG_NAME)
            self.assertIsNone(metadata)
            result = self.bash('workflow_local_config_file')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn(str(main), result.stdout + result.stderr)
        # Source selection is independent of Git layout, including a submodule,
        # a primary checkout and a directory outside Git.
        dot_git = self.checkout / '.git'
        for layout in ('submodule', 'primary', 'outside'):
            if dot_git.is_file(): dot_git.unlink()
            elif dot_git.is_dir(): dot_git.rmdir()
            if layout == 'submodule': dot_git.write_text('gitdir: ../main/.git/modules/fake\n')
            elif layout == 'primary': dot_git.mkdir()
            result = self.bash('workflow_local_config_file')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), str(self.checkout / MODULE.LOCAL_CONFIG_NAME))
        (self.checkout / MODULE.LOCAL_CONFIG_NAME).unlink()
        (self.checkout / MODULE.LOCAL_CONFIG_NAME).symlink_to(main / MODULE.LOCAL_CONFIG_NAME)
        self.assertEqual(self.cli('local-source').returncode, 2)
        env = dict(self.env, WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT=str(main))
        self.assertEqual(self.cli('local-source', env=env).returncode, 0)
        for external in (str(self.root / 'missing'), str(self.external)):
            env['WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT'] = external
            self.assertEqual(self.cli('local-source', env=env).returncode, 2)
            self.assertEqual(self.bash('workflow_local_config_file', env=env).returncode, 2)
        self.write('review: {}\n', self.external)
        env['WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT'] = str(self.external)
        self.assertEqual(self.cli('local-source', env=env).returncode, 0)
        with patch.dict(os.environ, env, clear=True), patch.object(MODULE.os, 'access', return_value=False):
            with self.assertRaises(MODULE.ConfigError):
                MODULE.resolve_local_config(self.checkout)
        # Relative explicit roots follow normal process CWD resolution.
        env['WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT'] = os.path.relpath(self.external)
        self.assertEqual(self.cli('local-source', env=env).returncode, 0)

    def test_bash_source_failure_propagation(self):
        env = dict(self.env, WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT=str(self.root / 'invalid'))
        calls = ['workflow_config_review_on_draft_runner', 'workflow_config_review_on_draft_github',
                 'workflow_config_review_on_ready_github', 'workflow_config_review_platforms',
                 'workflow_config_review_phase_after_clean_platforms',
                 'configured_reviewer_check_names_json',
                 'workflow_config_review_github_reviewer_configured bugbot']
        for shared in (False, True):
            if shared:
                self.write('review:\n  on_draft:\n    runner: [codex]\n    github: [pr-agent]\n  on_ready:\n    github: [bugbot]\n', local=False)
            for call in calls:
                with self.subTest(shared=shared, call=call):
                    result = self.bash(f'if out="$({call})"; then exit 90; else status=$?; fi\n[ "$status" -eq 2 ] && [ -z "$out" ]', env=env)
                    self.assertEqual(result.returncode, 0, result.stderr)
            # Extract real caller functions: both branch choices and conditional invocation.
            consumers = [('apply-readiness-labels.sh', 'configured_ready_reviewer_platforms'),
                         ('item-completion-self-check.sh', 'configured_review_platforms'),
                         ('item-completion-self-check.sh', 'configured_thread_bot_logins_json'),
                         ('item-completion-self-check.sh', 'reviewer_check_names_json'),
                         ('item-completion-self-check.sh', 'configured_platforms_all_no_thread'),
                         ('item-completion-self-check.sh', 'local_ai_reviewer_configured'),
                         ('pr-review-loop.sh', 'emit_review_lifecycle_duplicate_warnings'),
                         ('pr-review-loop.sh', 'reviewer_loop_repo_configured_platforms'),
                         ('coderabbit-cli-reviewer.sh', 'rate_limit_policy_from_config')]
            for file, name in consumers:
                extra = function_text(file, name)
                if file == 'item-completion-self-check.sh' and name != 'configured_review_platforms':
                    extra = function_text(file, 'configured_review_platforms') + '\n' + extra
                args = f' "{self.checkout}/.ai-dev-workflow.yaml"' if name in ('configured_review_platforms', 'emit_review_lifecycle_duplicate_warnings') else ''
                result = self.bash(f'if out="$({name}{args})"; then exit 90; else status=$?; fi\n[ "$status" -eq 2 ] && [ -z "$out" ]', extra=extra, env=env)
                self.assertEqual(result.returncode, 0, (shared, name, result.stderr))
            # PR/base snapshot helper retains source failure across temporary-file
            # cleanup even when called conditionally.
            encoded = base64.b64encode(b'review:\n  on_ready:\n    github: [bugbot]\n').decode()
            extra = function_text('apply-readiness-labels.sh', 'pr_head_config_ready_platforms')
            extra += f"\ngh() {{ printf '%s\\n' {encoded!r}; }}\nloop_dispatched_base=1\n"
            result = self.bash('if out="$(pr_head_config_ready_platforms fixture/repo synthetic-sha)"; then exit 90; else status=$?; fi; [ "$status" -eq 2 ] && [ -z "$out" ]', extra=extra, env=env)
            self.assertEqual(result.returncode, 0, result.stderr)
            # Actual public startup must stop before any stubbed service mutation.
            scripts = self.checkout / 'scripts/development-workflow'
            scripts.mkdir(parents=True, exist_ok=True)
            for file in ('workflow-lib.sh', 'workflow-config-resolver.py', 'pr-ci-loop.sh',
                         'pr-review-loop.sh', 'codex-github-evidence-lib.sh', 'apply-readiness-labels.sh', 'coderabbit-cli-reviewer.sh', 'run-epic-policy-recommender.sh'):
                shutil.copyfile(SCRIPTS / file, scripts / file)
            bindir = self.root / 'bin'; bindir.mkdir(exist_ok=True)
            for service in ('gh', 'codex', 'claude', 'coderabbit', 'cr'):
                stub = bindir / service
                stub.write_text('#!/bin/sh\necho unexpected-service >> "$MUTATION_LOG"\nexit 99\n'); stub.chmod(0o755)
            script_env = dict(env, PATH=str(bindir) + os.pathsep + self.env['PATH'], MUTATION_LOG=str(self.root / 'mutations'))
            for file in ('pr-ci-loop.sh', 'pr-review-loop.sh', 'apply-readiness-labels.sh', 'coderabbit-cli-reviewer.sh'):
                arguments = ['1993', 'fixture', 'repo'] if file == 'coderabbit-cli-reviewer.sh' else ['1993']
                if file == 'apply-readiness-labels.sh':
                    arguments = ['--pr', '1993', '--label', 'ready-for-human-review']
                result = subprocess.run(['bash', str(scripts / file), *arguments], env=script_env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 2, (file, result.stderr))
                self.assertRegex(result.stderr, 'local-source|source resolution failed', (file, result.stderr))
            scope = self.root / 'scope.json'
            scope.write_text('{"groups":{},"items":[],"policy":{}}')
            result = subprocess.run(['bash', str(scripts / 'run-epic-policy-recommender.sh'), '--scope', str(scope), '--original-command', '/run-item 1993', '--json'], env=script_env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('reviewer-list read error; key=review.on_draft.runner', result.stderr)
            self.assertFalse((self.root / 'mutations').exists())
        # Earlier bucket failure cannot be hidden by a later successful bucket.
        result = self.bash('if out="$(workflow_config_review_platforms)"; then exit 90; else [ "$?" -eq 2 ] && [ -z "$out" ]; fi',
                           extra='workflow_config_review_on_draft_github() { return 2; }\nworkflow_config_review_on_ready_github() { echo fabricated-later; }')
        self.assertEqual(result.returncode, 0, result.stderr)
        # Valid absence permits shared fallback; explicit empty disables it.
        self.write('product_repos: []\n')
        self.assertEqual(self.bash('workflow_config_review_on_draft_runner').stdout.strip(), 'codex')
        self.write('review:\n  on_draft:\n    runner: []\n')
        self.assertEqual(self.bash('workflow_config_review_on_draft_runner').stdout, '')

    def test_review_projection_semantics(self):
        opaque = 'inventedOpaqueValueForShadowedAlias'
        for runner in ('[codex]', '[]'):
            data = MODULE.parse_review_yaml(self.checkout / 'synthetic.yaml', raw=(
                f'review:\n  internal_reviewers: {opaque}\n  platforms: {opaque}\n  phase_after_clean: {opaque}\n  on_draft:\n    runner: {runner}\n    github: []\n  on_ready:\n    github: [pr-agent]\n  ignored_secret: fabricated-unrelated\nproduct_repos: []\n'))
            projection = MODULE.project_review_settings(data, self.checkout / 'synthetic.yaml')
            self.assertEqual(projection['review']['on_draft']['runner'], json.loads(runner.replace('codex', '"codex"')))
            self.assertNotIn(opaque, json.dumps(projection))
            self.assertNotIn('ignored_secret', json.dumps(projection))
            self.write('\n'.join(MODULE.dump_review_projection(data)) + '\n')
            expected = json.loads(runner.replace('codex', '"codex"'))
            result = self.bash('workflow_config_review_on_draft_runner')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), expected)
            effective = self.cli('review-effective')
            self.assertEqual(effective.returncode, 0, effective.stderr)
            self.assertEqual(json.loads(effective.stdout)['effective_runner'], expected)
            github = self.cli('review-github-effective')
            self.assertEqual(github.returncode, 0, github.stderr)
            self.assertEqual(json.loads(github.stdout)['effective_on_draft_github'], [])
            self.assertEqual(json.loads(github.stdout)['effective_on_ready_github'], ['pr-agent'])
            overrides = self.cli('review-overrides', '--json')
            self.assertEqual(overrides.returncode, 0, overrides.stderr)
            self.assertNotIn(opaque, overrides.stdout)
            stage = self.root / ('empty-stage' if runner == '[]' else 'defined-stage'); stage.mkdir()
            snapshot = self.cli('review-snapshot', '--destination', str(stage))
            self.assertEqual(snapshot.returncode, 0, snapshot.stderr)
            effective = subprocess.run([sys.executable, str(RESOLVER), 'review-effective', '--repo-root', str(stage)], env=self.env, text=True, capture_output=True)
            self.assertEqual(effective.returncode, 0, effective.stderr)
            self.assertEqual(json.loads(effective.stdout)['effective_runner'], expected)
            self.assertEqual(json.loads(effective.stdout)['effective_runner_state'], 'empty' if runner == '[]' else 'defined')
            self.assertNotIn(opaque, (stage / MODULE.LOCAL_CONFIG_NAME).read_text())


        for raw in ('', 'product_repos: []\n', 'review: {}\n'):
            self.assertEqual(MODULE.project_review_settings(MODULE.parse_review_yaml(Path('fake'), raw=raw), Path('fake')), {})
        legacy = MODULE.project_review_settings({'review': {'internal_reviewers': ['codex'], 'platforms': ['pr-agent', 'bugbot'], 'phase_after_clean': ['bugbot']}}, Path('fake'))
        self.assertEqual(legacy['review'], {'on_draft': {'runner': ['codex'], 'github': ['pr-agent']}, 'on_ready': {'github': ['bugbot']}})
        self.write('review:\n  internal_reviewers: [codex]\n  platforms: [pr-agent, bugbot]\n  phase_after_clean: [bugbot]\n')
        for command, expected in (('workflow_config_review_on_draft_runner', 'codex'),
                                  ('workflow_config_review_on_draft_github', 'pr-agent'),
                                  ('workflow_config_review_on_ready_github', 'bugbot')):
            result = self.bash(command)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), expected)

        self.write('review:\n  on_draft:\n    runner: [codex]\n  secret: fabricated-unrelated\n')
        staged = self.root / 'staged'; staged.mkdir()
        result = self.cli('review-snapshot', '--destination', str(staged))
        self.assertEqual(result.returncode, 0, result.stderr)
        content = (staged / MODULE.LOCAL_CONFIG_NAME).read_text()
        self.assertNotIn('fabricated-unrelated', content)
        self.assertEqual((staged / MODULE.LOCAL_CONFIG_NAME).stat().st_mode & 0o777, 0o600)

    def test_invalid_review_projection(self):
        for raw in ('review:\n  on_draft:\n    runner: [unfinished\n',
                    'review:\n  on_draft:\n    runner: [codex]\n    runner: []\n',
                    'review: []\n', 'review:\n  on_ready: opaque\n',
                    'review:\n  on_draft:\n    runner: opaque\n',
                    'review:\n  on_draft:\n    runner: [false]\n',
                    'review:\n  internal_reviewers_unavailable_policy: opaque\n'):
            self.write(raw)
            staged = self.root / 'stage-invalid'; staged.mkdir(exist_ok=True)
            result = self.cli('review-snapshot', '--destination', str(staged))
            self.assertEqual(result.returncode, 2, (raw, result.stdout, result.stderr))
            self.assertEqual(list(staged.iterdir()), [])
        self.write('review:\n  on_draft:\n    runner: [codex]\n')
        with patch.dict(os.environ, self.env, clear=True), patch.object(MODULE.os, 'replace', side_effect=OSError('fabricated-error')):
            with self.assertRaises(MODULE.ConfigError):
                MODULE.cmd_review_snapshot(type('Args', (), {'repo_root': str(self.checkout), 'destination': str(staged)})())
        self.assertEqual(list(staged.iterdir()), [])

    def test_staged_projection_pinning(self):
        scripts = self.root / 'tools/scripts/development-workflow'; scripts.mkdir(parents=True)
        for path in SCRIPTS.iterdir():
            if path.is_file() and (path.name in ('workflow-lib.sh', 'workflow-config-resolver.py', 'reviewer-preflight.sh') or path.name.startswith('reviewer_preflight')):
                shutil.copyfile(path, scripts / path.name)
        shared = 'review:\n  on_draft:\n    runner: [cursor]\n    github: [bugbot]\n  on_ready:\n    github: []\n'
        self.write(shared, local=False)
        def git(*args):
            subprocess.run(['git', '-C', str(self.checkout), *args], check=True, capture_output=True)
        git('init', '-q'); git('checkout', '-q', '-b', 'develop'); git('add', '.ai-dev-workflow.yaml')
        git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.test', 'commit', '-qm', 'init')
        git('remote', 'add', 'origin', str(self.checkout))
        original = 'review:\n  on_draft:\n    runner: [codex]\n    github: [pr-agent]\n  on_ready:\n    github: [coderabbit]\n  ignored_secret: fabricated-do-not-stage\n'
        bindir = self.root / 'bin'; bindir.mkdir()
        wrapper = bindir / 'python3'
        # Execute the actual resolver in-process to spy on its single source read;
        # mutate only the synthetic external source after atomic projection.
        wrapper.write_text(f"#!{sys.executable}\n" + r'''
import contextlib, importlib.util, io, json, os, pathlib, sys
args = sys.argv[1:]
if not args or not args[0].endswith('workflow-config-resolver.py') or (len(args) > 1 and args[1] == 'redact-text'):
    os.execv(os.environ['REAL_PYTHON'], [os.environ['REAL_PYTHON'], *args])
spec = importlib.util.spec_from_file_location('isolated_resolver', args[0])
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
reads = []
source_open = os.open
source = pathlib.Path(os.environ['SYNTHETIC_SOURCE'])
def spy(path, flags, *a, **kw):
    if pathlib.Path(path) == source and (flags & os.O_ACCMODE) == os.O_RDONLY: reads.append(str(path))
    return source_open(path, flags, *a, **kw)
os.open = spy
capture = io.StringIO()
with contextlib.redirect_stdout(capture):
    rc = module.main(args[1:])
text = capture.getvalue()
entry = {'command': args[1], 'reads': reads, 'override': os.environ.get('WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT'), 'payload': json.loads(text) if text else None}
with open(os.environ['SPY_LOG'], 'a') as log: log.write(json.dumps(entry) + '\n')
if args[1] == 'review-snapshot':
    action = os.environ['SOURCE_MUTATION']
    if action == 'remove': source.unlink()
    elif action == 'malformed': source.write_text('review: [broken')
    elif action == 'change': source.write_text('review:\n  on_draft:\n    runner: [claude]\n    github: [bugbot]\n  on_ready:\n    github: [ronda]\n')
sys.stdout.write(text)
sys.exit(rc)
''')
        wrapper.chmod(0o755)
        for action in ('change', 'malformed', 'remove', 'no-projection'):
            source = self.write('product_repos: []\n' if action == 'no-projection' else original, self.external)
            log = self.root / ('spy-' + action)
            env = dict(self.env, WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT=str(self.external),
                       REAL_PYTHON=sys.executable, SYNTHETIC_SOURCE=str(source), SOURCE_MUTATION=action,
                       SPY_LOG=str(log), PATH=str(bindir) + os.pathsep + self.env['PATH'],
                       WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE='1', WORKFLOW_REVIEWER_PREFLIGHT_BUDGET_SECONDS='60',
                       WORKFLOW_REVIEWER_PREFLIGHT_PER_PLATFORM_CAP_SECONDS='20')
            result = subprocess.run(['bash', str(scripts / 'reviewer-preflight.sh'), '--repo-root', str(self.checkout),
                                     '--mode', 'pre-dispatch', '--target-base', 'develop', '--remaining-stages',
                                     'on_draft.runner,on_draft.github,on_ready.github', '--pr-state',
                                     'on_draft.runner=draft,on_draft.github=draft,on_ready.github=ready'],
                                    env=env, text=True, capture_output=True)
            self.assertIn(result.returncode, (0, 1), result.stderr)
            self.assertNotIn('fabricated-do-not-stage', result.stdout + result.stderr)
            entries = [json.loads(line) for line in log.read_text().splitlines()]
            snapshot = next(e for e in entries if e['command'] == 'review-snapshot')
            self.assertEqual(snapshot['reads'], [str(source)])
            self.assertEqual(snapshot['payload']['LOCAL_OVERRIDE_FILE'], str(source))
            self.assertEqual(snapshot['payload']['LOCAL_OVERRIDE_ORIGIN'], 'override_root')
            runner = next(e for e in entries if e['command'] == 'review-effective')
            github = next(e for e in entries if e['command'] == 'review-github-effective')
            for entry in (runner, github):
                self.assertIsNone(entry['override']); self.assertEqual(entry['reads'], [])
            self.assertEqual(runner['payload']['effective_runner'], ['cursor'] if action == 'no-projection' else ['codex'])
            self.assertEqual(github['payload']['effective_on_draft_github'], ['bugbot'] if action == 'no-projection' else ['pr-agent'])
            self.assertEqual(github['payload']['effective_on_ready_github'], [] if action == 'no-projection' else ['coderabbit'])
            self.assertEqual(env['WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT'], str(self.external))

        # Actual preflight failure diagnostics must remain metadata-only, even
        # when the malformed source includes an unrecognizable opaque value.
        self.write('review:\n  on_draft:\n    runner: [opaquePrivateFixture\n', self.external)
        result = subprocess.run(['bash', str(scripts / 'reviewer-preflight.sh'), '--repo-root', str(self.checkout),
                                 '--mode', 'pre-dispatch', '--target-base', 'develop', '--remaining-stages',
                                 'on_draft.runner', '--pr-state', 'on_draft.runner=draft'], env=env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 3, result.stdout + result.stderr)
        self.assertNotIn('opaquePrivateFixture', result.stdout + result.stderr)
        self.assertIn('review-snapshot failed', result.stderr)
        # A successful JSON render of a blocked reviewer result keeps its
        # machine envelope while sanitizing diagnostic strings.
        self.write('review:\n  on_draft:\n    runner: ["token=fakePreflightDiagnostic"]\n', self.external)
        result = subprocess.run(['bash', str(scripts / 'reviewer-preflight.sh'), '--repo-root', str(self.checkout),
                                 '--mode', 'pre-dispatch', '--target-base', 'develop', '--remaining-stages',
                                 'on_draft.runner', '--pr-state', 'on_draft.runner=draft', '--json'], env=env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        report = json.loads(result.stdout)
        self.assertEqual(report['outcome'], 'blocked')
        self.assertNotIn('fakePreflightDiagnostic', result.stdout + result.stderr)

    def assert_redacts(self, text, forbidden):
        with patch.object(MODULE, 'resolve_local_config', side_effect=AssertionError('redactor read configuration')):
            output = MODULE.redact_text(text)
        for value in forbidden:
            self.assertNotIn(value, output)
        result = subprocess.run([sys.executable, str(RESOLVER), 'redact-text'], input=text,
                                env=dict(self.env, WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT='invalid-must-not-read'), text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, output)
        self.assertEqual(MODULE.redact_text(output), output)
        shell = self.bash('workflow_redact_text', extra='') if not text else subprocess.run(
            ['bash', '-c', f'source {str(SCRIPTS / "workflow-lib.sh")!r}; workflow_redact_text'],
            input=text, env=self.env, text=True, capture_output=True)
        self.assertEqual(shell.returncode, 0, shell.stderr)
        for value in forbidden:
            self.assertNotIn(value, shell.stdout + shell.stderr)
        return output

    def test_sensitive_assignments(self):
        for key in ('token', 'PASSWORD', 'Passphrase', 'client_secret', 'API_KEY', 'api-key', 'access.key', 'private key'):
            for value in ('fabricatedOpaqueValue', '"fabricated \\"quoted-tail"', "'fabricated \\'quoted-tail'", '"fabricated\\\\tail"'):
                with self.subTest(key=key, value=value):
                    self.assert_redacts(f'{key} = {value}; operation=review', ['fabricated', 'quoted-tail'])
        output = self.assert_redacts('{"api_key":"fabricatedOpaqueValue", "result":"clean", "count":0}', ['fabricatedOpaqueValue'])
        self.assertEqual(json.loads(output)['result'], 'clean')

    def test_multiple_values(self):
        self.assert_redacts('token=firstFake password="secondFake"; Authorization: Bearer thirdFake token=fourthFake',
                            ['firstFake', 'secondFake', 'thirdFake', 'fourthFake'])

    def test_sensitive_assignment_multiword_values(self):
        for text in ('password: fabricated first tail\nresult: clean\n',
                     'token=fabricated first tail; operation=review',
                     r'token=fabricated\ first\ tail operation=review',
                     r'password=fabricated\;first\ tail; operation=review',
                     'password: fabricated#first tail # public note\nresult: clean\n',
                     'password: fabricated multi, first; word tail\nresult: clean\n',
                     'password: fabricated\'s "first", word tail\nresult: clean\n',
                     'token=fabricated\\\nfirst tail; operation=review',
                     'token=fabricated first password=second fake tail; operation=review'):
            output = self.assert_redacts(text, ['fabricated', 'first', 'tail', 'second fake'])
            self.assertIn('result: clean' if '\nresult:' in text else 'operation=review', output)
            if '# public note' in text:
                self.assertIn('# public note', output)
        output = self.assert_redacts('{"token":"fabricated first tail","result":"clean","count":1}',
                                     ['fabricated', 'first', 'tail'])
        self.assertEqual(json.loads(output), {'token': '[REDACTED]', 'result': 'clean', 'count': 1})
        output = self.assert_redacts('{"token":123,"nested":{},"password":false,"result":"clean"}', ['123', 'false'])
        self.assertEqual(json.loads(output), {'token': '[REDACTED]', 'nested': {}, 'password': '[REDACTED]', 'result': 'clean'})

    def assert_yaml_scalar_redacted(self, scalar):
        text = 'password: ' + scalar + ' # public note\nresult: clean\n'
        parsed = MODULE.parse_review_yaml(Path('synthetic-scalar.yaml'), raw=text)
        self.assertIsInstance(parsed['password'], str)
        output = self.assert_redacts(text, ['fabricated', 'hiddenSuffix', 'secretTail'])
        self.assertEqual(MODULE.parse_review_yaml(Path('synthetic-scalar.yaml'), raw=output)['result'], 'clean')
        self.assertIn('[REDACTED]', output)
        self.assertIn('# public note', output)
        if scalar.startswith(("'", '"')):
            import yaml  # Existing strict-reader dependency; synthetic syntax oracle.
            # The preceding public field combines a literal backslash and
            # YAML's doubled apostrophe inside a flow mapping.
            flow = r"{public: 'ordinary\''note', password: " + scalar + ', result: clean}\n'
            yaml.safe_load(flow)
            safe_flow = self.assert_redacts(flow, ['fabricated', 'hiddenSuffix', 'secretTail'])
            self.assertEqual(yaml.safe_load(safe_flow)['result'], 'clean')

    def test_yaml_single_quoted_doubled_apostrophe(self):
        self.assert_yaml_scalar_redacted("'fabricated''hiddenSuffix multi, secretTail'")

    def test_yaml_single_quoted_literal_backslash(self):
        self.assert_yaml_scalar_redacted(r"'fabricated\''hiddenSuffix secretTail'")

    def test_yaml_double_quoted_escaped_quote(self):
        self.assert_yaml_scalar_redacted(r'"fabricated\"hiddenSuffix secretTail"')

    def test_yaml_double_quoted_escaped_backslash(self):
        self.assert_yaml_scalar_redacted(r'"fabricated\\hiddenSuffix \\\"secretTail"')

    def test_yaml_plain_spaces(self):
        self.assert_yaml_scalar_redacted('fabricated hiddenSuffix secretTail')

    def test_yaml_plain_internal_hash(self):
        self.assert_yaml_scalar_redacted('fabricated#hiddenSuffix secretTail')

    def test_yaml_plain_special_characters(self):
        self.assert_yaml_scalar_redacted(r'''fabricated, hiddenSuffix; \\literal 'double" !@$%^&*() []{} secretTail''')

    def test_header_and_url_values(self):
        output = self.assert_redacts('Authorization: Bearer fabricatedBearer\nAuthorization: Basic fabricatedBasic==\nhttps://user:fakePassword@example.test/path\n',
                                     ['fabricatedBearer', 'fabricatedBasic', 'fakePassword', 'user:'])
        self.assertIn('example.test/path', output)
        output = self.assert_redacts('{"Authorization":"opaqueFakeAuthorization"}', ['opaqueFakeAuthorization'])
        self.assertEqual(json.loads(output)['Authorization'], '[REDACTED]')
        output = self.assert_redacts(json.dumps({'Authorization': 'Bearer opaque\\"FakeAuthorization'}), ['opaque', 'FakeAuthorization'])
        self.assertEqual(json.loads(output)['Authorization'], '[REDACTED]')

    def test_token_boundaries(self):
        for token in ('ghp_fabricatedToken', 'github_pat_fabricatedToken', 'sk-proj-fabricatedToken', 'xoxb-fabricatedToken'):
            self.assert_redacts(f'({token}), "{token}"; end={token}', [token])

    def test_private_key_blocks(self):
        for text in ('-----BEGIN PRIVATE KEY-----\nfabricatedLine1\nfabricatedLine2\n-----END PRIVATE KEY-----',
                     '-----BEGIN RSA PRIVATE KEY-----\nfabricatedLine1\nfabricatedLine2',
                     '-----BEGIN PRIVATE KEY-----\n-----BEGIN PUBLIC KEY-----\nfabricatedLine1\n-----END PRIVATE KEY-----',
                     '-----BEGIN PRIVATE KEY-----\n-----BEGIN RSA PRIVATE KEY-----\nfabricatedLine1\n-----END RSA PRIVATE KEY-----\nfabricatedLine2\n-----END PRIVATE KEY-----'):
            self.assert_redacts(text, ['fabricatedLine1', 'fabricatedLine2', 'BEGIN PRIVATE KEY'])

    def test_negative_lookalikes(self):
        text = 'token count 3; public_key: identity.pub; https://example.test/path\n<strong>No security concerns identified</strong>\n**[Persistent review]** [link](https://example.test/review)\n**Verdict**: APPROVED'
        self.assertEqual(self.assert_redacts(text, []), text)

    def test_config_error_metadata_only(self):
        opaque = 'fabricatedOpaqueNoKnownPrefix'
        for raw in (f'review:\n  {opaque} invalid\n', f'review:\n  on_draft:\n    runner: ["{opaque}\n',
                    f'review:\n  internal_reviewers_unavailable_policy: {opaque}\n'):
            self.write(raw)
            for command in ('review-effective', 'review-github-effective', 'review-overrides', 'mode', 'validate'):
                result = self.cli(command)
                if command == 'review-overrides' and 'internal_reviewers_unavailable_policy:' in raw:
                    # Functional override transport is deliberately not a diagnostic.
                    continue
                self.assertNotIn(opaque, result.stdout + result.stderr, (command, result.stdout, result.stderr))
                self.assertNotIn('Traceback', result.stderr)
        (self.checkout / MODULE.LOCAL_CONFIG_NAME).write_bytes(b'\xff')
        for command in ('review-effective', 'review-github-effective', 'review-overrides', 'mode', 'validate'):
            result = self.cli(command)
            self.assertNotIn('Traceback', result.stderr)
            self.assertNotIn('0xff', result.stderr)

    def test_coderabbit_policy_metadata_only(self):
        scripts = self.checkout / 'scripts/development-workflow'; scripts.mkdir(parents=True)
        for name in ('coderabbit-cli-reviewer.sh', 'workflow-lib.sh', 'workflow-config-resolver.py'):
            shutil.copyfile(SCRIPTS / name, scripts / name)
        bindir = self.root / 'bin'; bindir.mkdir()
        (bindir / 'gh').write_text('#!/bin/sh\nexit 1\n'); (bindir / 'gh').chmod(0o755)
        opaque = 'fabricatedOpaquePolicyNoPrefix'
        for from_env in (False, True):
            self.write('review:\n  coderabbit_cli:\n    rate_limit_policy: ' + ('warn' if from_env else opaque) + '\n')
            env = dict(self.env, PATH=str(bindir) + os.pathsep + self.env['PATH'])
            if from_env: env['CODERABBIT_CLI_RATE_LIMIT_POLICY'] = opaque
            result = subprocess.run(['bash', str(scripts / 'coderabbit-cli-reviewer.sh'), '1', 'fixture', 'repo'], env=env, text=True, capture_output=True)
            self.assertNotIn(opaque, result.stdout + result.stderr)
            self.assertIn('defaulting to warn', result.stderr)
            self.assertIn('rate_limit_policy', result.stderr)
            env['WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT'] = str(self.root / 'missing')
            result = subprocess.run(['bash', str(scripts / 'coderabbit-cli-reviewer.sh'), '1', 'fixture', 'repo'], env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 2)
            self.assertNotIn('defaulting to warn', result.stderr)

    def test_failure_boundaries(self):
        # Filter failure emits no unsafe input and cannot change command status.
        text = 'token=fabricatedNeverEcho'

        source = self.write('review:\n  on_draft:\n    runner: [codex]\n')
        stage = self.root / 'removed-source-stage'; stage.mkdir()
        def remove_after_selection(root):
            source.unlink()
            return source, 'checkout', None
        with patch.object(MODULE, 'resolve_local_config', side_effect=remove_after_selection):
            with self.assertRaises(MODULE.ConfigError):
                MODULE.cmd_review_snapshot(type('Args', (), {'repo_root': str(self.checkout), 'destination': str(stage)})())
        self.assertEqual(list(stage.iterdir()), [])
        with patch.object(MODULE, 'redact_text', side_effect=ValueError(text)), patch.object(MODULE.sys, 'stdin') as stdin, patch.object(MODULE.sys, 'stderr') as stderr, patch.object(MODULE.sys, 'stdout') as stdout:
            stdin.read.return_value = text
            self.assertEqual(MODULE.cmd_redact_text(type('Args', (), {'json': False})()), 2)
            stdout.write.assert_not_called()
            self.assertNotIn('fabricatedNeverEcho', str(stderr.write.call_args_list))
        for status in (0, 7):
            result = self.bash(f"""set +e; output="$(printf 'token=fabricatedNeverEcho\\n'; exit {status})"; status=$?; set -e; printf '%s' "$output" | workflow_redact_text; exit "$status"; """)
            self.assertEqual(result.returncode, status)
            self.assertNotIn('fabricatedNeverEcho', result.stdout + result.stderr)
        result = self.bash('workflow_redact_text', extra='workflow_config_resolver_script() { echo /synthetic/missing-filter; }')
        self.assertEqual(result.returncode, 2)
        self.assertNotIn(text, result.stdout + result.stderr)

    def test_composed_diagnostic_boundaries(self):
        scripts = self.checkout / 'scripts/development-workflow'; scripts.mkdir(parents=True)
        for name in ('workflow-lib.sh', 'workflow-config-resolver.py', 'resolve-reviewer-availability.sh',
                     'local-ai-reviewer.sh', 'pr-review-loop.sh', 'run-epic-audit-trail.sh', 'reviewer_preflight_coderabbit.py', 'codex-github-evidence-lib.sh'):
            shutil.copyfile(SCRIPTS / name, scripts / name)
        bindir = self.root / 'bin'; bindir.mkdir()
        gh = bindir / 'gh'
        gh.write_text('''#!/bin/sh\ncase "$*" in\n*"pr view"*) printf '%s\\n' '{"baseRefName":"develop","headRefName":"feature/1993-fixture","headRefOid":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","body":"token=fakePersistentContext"}' ;;\n*"pr diff"*) echo README.md ;;\n*) echo "token=fakeCapturedError" >&2; exit 1 ;;\nesac\n''')
        gh.chmod(0o755)
        (bindir / 'codex').write_text('#!/bin/sh\nexit 1\n'); (bindir / 'codex').chmod(0o755)
        env = dict(self.env, PATH=str(bindir) + os.pathsep + self.env['PATH'])
        self.write('review:\n  on_draft:\n    runner: [codex, coderabbit]\n')
        # Native codex is just an availability declaration; no runtime is launched.
        for runner, expected in (('codex', 0), ('unknown', 1)):
            result = subprocess.run(['bash', str(scripts / 'resolve-reviewer-availability.sh'), '--repo-root', str(self.checkout),
                                     '--owner', 'fixture', '--repo', 'repo', '--runner-kind', runner], env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, expected, result.stderr + result.stdout)
            self.assertNotIn('fakeCapturedError', result.stdout + result.stderr)
        subprocess.run(['git', 'init', '-q', str(self.checkout)], check=True, capture_output=True)
        (self.checkout / 'REVIEW.md').write_text('# Synthetic review contract\n')
        command = bindir / 'synthetic-review'
        evidence = self.root / 'evidence.json'
        yaml_diagnostic = ('password: \'fabricated\'\'hiddenSingleSuffix secretTail\'\n'
                           'password: "fabricated\\\\\\"hiddenDoubleSuffix secretTail"\n'
                           'password: fabricated#hiddenPlainSuffix, secretTail')
        for line in yaml_diagnostic.splitlines():
            MODULE.parse_review_yaml(Path('synthetic-diagnostic.yaml'), raw=line)
        for valid, expected in ((True, 0), (False, 2)):
            payload = json.dumps({'result': 'clean', 'reason': 'token=fakeVerdictReason hiddenVerdictSuffix\n' + yaml_diagnostic, 'comments': 0}) if valid else 'invalid-verdict'
            stderr = 'token=fakeCapturedError hiddenCapturedSuffix\n' + yaml_diagnostic
            command.write_text("#!/bin/sh\nprintf '%s\\n' " + shlex.quote(stderr) + " >&2\nprintf '%s\\n' " + shlex.quote(payload) + '\nexit ' + ('0' if valid else '7') + '\n')
            command.chmod(0o755)
            call_env = dict(env, LOCAL_AI_REVIEWER_COMMAND=str(command), LOCAL_AI_REVIEWER_EVIDENCE_FILE=str(evidence),
                            LOCAL_AI_REVIEWER_GRAPH_STRATEGY='none')
            result = subprocess.run(['bash', str(scripts / 'local-ai-reviewer.sh'), '1993', 'fixture', 'repo'], env=call_env,
                                    cwd=self.checkout, capture_output=True, text=True)
            self.assertEqual(result.returncode, expected, result.stderr + result.stdout)
            self.assertNotIn('fakeCapturedError', result.stdout + result.stderr)
            self.assertNotIn('fakeVerdictReason', result.stdout + result.stderr)
            self.assertNotIn('hiddenVerdictSuffix', result.stdout + result.stderr)
            self.assertNotIn('hiddenCapturedSuffix', result.stdout + result.stderr)
            for suffix in ('hiddenSingleSuffix', 'hiddenDoubleSuffix', 'hiddenPlainSuffix', 'secretTail'):
                self.assertNotIn(suffix, result.stdout + result.stderr)
            if valid:
                data = json.loads(evidence.read_text())
                self.assertEqual(data['result'], 'clean')
                self.assertEqual(data['counts']['blocking'], 0)
                self.assertNotIn('fakePersistentContext', evidence.read_text())
                self.assertNotIn('hiddenVerdictSuffix', evidence.read_text())
                for suffix in ('hiddenSingleSuffix', 'hiddenDoubleSuffix', 'hiddenPlainSuffix', 'secretTail'):
                    self.assertNotIn(suffix, evidence.read_text())
        command.write_text("#!/bin/sh\necho 'quota exceeded; try again at token=fakeQuotaDiagnostic' >&2\nexit 7\n")
        result = subprocess.run(['bash', str(scripts / 'local-ai-reviewer.sh'), '1993', 'fixture', 'repo'], env=call_env,
                                cwd=self.checkout, capture_output=True, text=True)
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn('REASON=quota_exhausted', result.stdout)
        self.assertIn('QUOTA_RESET_AT=token=[REDACTED]', result.stdout)
        self.assertNotIn('fakeQuotaDiagnostic', result.stdout + result.stderr)
        # Load the real reviewer loop in its explicit harness mode: no main loop,
        # reviewer service, label, tracker, or merge mutation can execute.
        errfile = self.root / 'operation.err'
        for error, expected in (('HTTP 403 token=fakeCapturedError', 0), ('temporary retry token=fakeCapturedError', 1)):
            errfile.write_text(error)
            result = subprocess.run(['bash', '-c', f'HARNESS_MODE=1 source {str(scripts / "pr-review-loop.sh")!r}; reviewer_loop_gh_read_denied {str(errfile)!r}'],
                                    env=env, cwd=self.checkout, capture_output=True, text=True)
            self.assertEqual(result.returncode, expected, result.stderr + result.stdout)
            self.assertNotIn('fakeCapturedError', result.stdout + result.stderr)
        # Exercise the persistent summary composition with a synthetic history
        # producer; the actual append and JSON renderer remain under test.
        history = function_text('pr-review-loop.sh', 'reviewer_loop_history_append_to_summary')
        history += '\n' + function_text('pr-review-loop.sh', 'reviewer_loop_history_render_section')
        history += "\nreviewer_loop_history_payload_from_existing() { printf '%s' '{\"history_status\":\"available\",\"entries\":[{\"result\":\"clean\",\"blocking_count\":0,\"detail\":\"token=fakeHistoryDiagnostic hiddenHistorySuffix\"}]}'; }\nREVIEWER_LOOP_HISTORY_MARKER='<!-- reviewer-loop-history:v1 -->'\n"
        result = self.bash("reviewer_loop_history_append_to_summary 'detail token=fakePublishedDiagnostic' ''", extra=history)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('fakePublishedDiagnostic', result.stdout)
        self.assertNotIn('fakeHistoryDiagnostic', result.stdout)
        self.assertNotIn('hiddenHistorySuffix', result.stdout)
        payload = json.loads(result.stdout.split('```json\n')[1].split('```')[0])
        self.assertEqual(payload['entries'][0]['result'], 'clean')
        self.assertEqual(payload['entries'][0]['blocking_count'], 0)
        audit = self.root / 'audit.json'
        audit.write_text(json.dumps({'scope_source': 'synthetic #1993', 'item': {'number': 1993, 'title': 'Synthetic'}, 'pr': {'number': 1, 'head_sha': 'a' * 40}, 'risk': {'level': 'low'}, 'merge_authority': 'none', 'final_decision': 'hold', 'reviewer': {'result': 'clean'},
                                     'advisories': [{'source': 'fixture', 'decision': 'fixed', 'rationale': 'token=fakeAuditDiagnostic /tmp/fake-private-path'}]}))
        result = subprocess.run(['bash', str(scripts / 'run-epic-audit-trail.sh'), 'render-pr-disposition', '--input', str(audit)], env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('<!-- run-epic:pr-disposition -->', result.stdout)
        self.assertNotIn('fakeAuditDiagnostic', result.stdout)
        self.assertNotIn('/tmp/fake-private-path', result.stdout)

    @unittest.skipUnless(IS_TEMPLATE, "project-owned controls vary in consumer repositories")
    def test_prevention_controls(self):
        import fnmatch
        subprocess.run(['git', 'init', '-q', str(self.checkout)], check=True, capture_output=True)
        shutil.copyfile(ROOT / '.gitignore', self.checkout / '.gitignore')
        private = ('.ai-dev-workflow.local.yaml', '.ai-dev-workflow.local.yaml.retired',
                   '.ai-dev-workflow.local.private.yaml', '.ai-dev-workflow.local.env',
                   '.ai-dev-workflow.local.env.bak', '.env', '.env.production', '.env.local',
                   'private.key', 'service-key.pem', 'service.private.pem', 'private_key.pem',
                   'id_rsa', 'id_ed25519', '.netrc', '.aws/credentials', 'credentials.json')
        public = ('.ai-dev-workflow.local.example.yaml', '.ai-dev-workflow.local.env.example',
                  '.env.example', 'certificate.pem', 'certificate.crt', 'id_ed25519.pub')
        for name, ignored in [(n, True) for n in private] + [(n, False) for n in public]:
            result = subprocess.run(['git', '-C', str(self.checkout), 'check-ignore', '-q', '--', name])
            self.assertEqual(result.returncode, 0 if ignored else 1, name)
        policy = json.loads((ROOT / '.claude/settings.json').read_text())['permissions']
        self.assertIn('Bash(git status:*)', policy['allow'])
        for operation in ('Read', 'Edit'):
            patterns = [rule[len(operation)+1:-1] for rule in policy['deny'] if rule.startswith(operation + '(')]
            for name in ('.ai-dev-workflow.local.yaml', '.ai-dev-workflow.local.env', 'private.key',
                         'service-key.pem', 'id_ed25519', 'credentials.json'):
                self.assertTrue(any(fnmatch.fnmatch('fixture/' + name, pattern) for pattern in patterns), (operation, name))
            for name in public:
                self.assertFalse(any(fnmatch.fnmatch('fixture/' + name, pattern) for pattern in patterns), (operation, name))
        guidance = (ROOT / 'AGENTS.md').read_text()
        self.assertIn('not agent inspection or editing targets', guidance)
        self.assertIn('Authorized protocol scripts deliberately read', guidance)
        self.assertIn('disposable synthetic repositories', guidance)

    @unittest.skipUnless(IS_TEMPLATE, "release fragments belong to the template repository")
    def test_upgrade_artifacts_presence_and_content(self):
        # AC-9 / smoke journey 8: require the guide and release note, either
        # pending in its fragment or published in a versioned changelog section.
        guide = ROOT / 'docs/workflow/development-workflow/integrations/runner-secret-prevention.md'
        fragment = ROOT / 'changelog.d/1993.security.runner-secret-prevention.md'
        self.assertTrue(guide.is_file(), str(guide))
        text = guide.read_text()
        for phrase in ('WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT', 'minimal local review configuration',
                       'no automatic copying', 'Do not restore fallback during downstream template sync',
                       'conflated public Bash', 'not supported', 'reviewed forward fix',
                       'distinct failure status', 'checkout-local'):
            self.assertIn(phrase, text.replace('\n', ' '))
        if fragment.is_file():
            note = fragment.read_text()
            required_phrases = ('(#1993)', 'explicit selection',
                                'minimal checkout-local review settings', 'never copied automatically')
        else:
            changelog = ROOT / 'CHANGELOG.md'
            self.assertTrue(changelog.is_file(), str(changelog))
            released_sections = re.findall(
                r'^## \[\d+\.\d+\.\d+\] - \d{4}-\d{2}-\d{2}\n(.*?)(?=^## |\Z)',
                changelog.read_text(), re.MULTILINE | re.DOTALL)
            published_notes = [section for section in released_sections if '(#1993)' in section]
            self.assertEqual(len(published_notes), 1, 'Expected one published release note for #1993')
            note = published_notes[0]
            required_phrases = ('Private runner configuration', 'explicit validated selection',
                                'minimal reviewer settings', 'never copied automatically')
        for phrase in required_phrases:
            self.assertIn(phrase, note)



    NAME_BUCKETS = (
        ('on_draft', 'runner', 'review-effective', 'effective_runner', 'workflow_config_review_on_draft_runner'),
        ('on_draft', 'github', 'review-github-effective', 'effective_on_draft_github', 'workflow_config_review_on_draft_github'),
        ('on_ready', 'github', 'review-github-effective', 'effective_on_ready_github', 'workflow_config_review_on_ready_github'),
    )

    def name_document(self, bucket, names, legacy=False):
        phase, key = bucket[:2]
        if legacy:
            review = ({'internal_reviewers': names} if key == 'runner' else
                      {'platforms': names, 'phase_after_clean': ['separate-ready']} if phase == 'on_draft' else
                      {'platforms': ['separate-draft'], 'phase_after_clean': names})
        else:
            review = {phase: {key: names}}
        return '\n'.join(MODULE.dump_review_projection({'review': review})) + '\n'

    def names_from_bash(self, bucket, shell='/bin/bash', env=None, root=None):
        root = root or self.checkout
        script = 'source ' + shlex.quote(str(SCRIPTS / 'workflow-lib.sh')) + '\n'
        script += 'workflow_repo_root() { printf "%s\\n" ' + shlex.quote(str(root)) + '; }\n'
        script += bucket[4] + ' ' + shlex.quote(str(root / '.ai-dev-workflow.yaml'))
        return subprocess.run([shell, '-c', script], env=env or self.env, text=True, capture_output=True, timeout=20)

    def name_case(self, bucket, names, *, local=True, valid=False, legacy=False, shells=('/bin/bash',)):
        self.write('review:\n  on_draft:\n    runner: [codex]\n    github: [bugbot]\n  on_ready:\n    github: [pr-agent]\n', local=False)
        local_path = self.checkout / MODULE.LOCAL_CONFIG_NAME
        local_path.unlink(missing_ok=True)
        self.write(self.name_document(bucket, names, legacy), local=local)
        result = self.cli(bucket[2]); self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload[bucket[3] + '_state'], 'defined' if valid else 'malformed')
        expected = names if valid else []
        self.assertEqual(payload[bucket[3]], expected)
        if not valid:
            self.assertNotIn('fabricatedOpaqueReviewer', result.stdout + result.stderr)
        for shell in dict.fromkeys(shells):
            bash = self.names_from_bash(bucket, shell)
            self.assertEqual(bash.returncode, 0 if valid else 2, bash.stdout + bash.stderr)
            if valid:
                self.assertEqual(bash.stdout.splitlines(), names)
                self.assertEqual(len(bash.stdout.splitlines()), len(payload[bucket[3]]))
                self.assertEqual(bash.stderr, '')
            else:
                self.assertEqual(bash.stdout, '')
                self.assertRegex(bash.stderr, 'configuration:')
                self.assertNotIn('fabricatedOpaqueReviewer', bash.stdout + bash.stderr)

    def test_reviewer_name_newline_rejected_before_bash(self):
        shells = ('/bin/bash', shutil.which('bash'))
        for bucket in self.NAME_BUCKETS:
            for local in (False, True):
                with self.subTest(bucket=bucket[:2], local=local):
                    self.name_case(bucket, ['codex', 'fabricatedOpaqueReviewer\nclaude'], local=local, shells=shells)

    def test_reviewer_name_controls_rejected(self):
        for control in ('\r', '\t', '\x1b', '\x7f', '\x85', '\u2028', '\u2029', '\u200b'):
            for bucket in self.NAME_BUCKETS:
                with self.subTest(control=repr(control), bucket=bucket[:2]):
                    self.name_case(bucket, ['codex', 'fabricatedOpaqueReviewer' + control + 'codex'])

    def test_reviewer_name_blank_or_trimmed_rejected(self):
        for bad in ('', ' ', ' codex', 'codex '):
            for bucket in self.NAME_BUCKETS:
                with self.subTest(value=repr(bad), bucket=bucket[:2]):
                    self.name_case(bucket, ['codex', bad])

    def test_reviewer_name_printable_cardinality(self):
        names = ['codex', 'unknown reviewer, with "quotes" and \\ slash', 'opaque-ñ-工']
        for bucket in self.NAME_BUCKETS:
            for local in (False, True):
                with self.subTest(bucket=bucket[:2], local=local):
                    self.name_case(bucket, names, local=local, valid=True, shells=('/bin/bash', shutil.which('bash')))

    def test_reviewer_name_legacy_precedence_and_empty(self):
        valid_names = ['codex', 'printable-unknown-reviewer']
        for bucket in self.NAME_BUCKETS:
            for local in (False, True):
                with self.subTest(bucket=bucket[:2], local=local):
                    self.name_case(bucket, ['codex', 'fabricatedOpaqueReviewer\nclaude'], local=local, legacy=True)
                    self.name_case(bucket, valid_names, local=local, valid=True, legacy=True)
        # A selected modern declaration is validated; shadowed legacy values
        # do not add an independent provider-name policy or reject the source.
        self.write('review:\n  on_draft:\n    runner: [codex]\n    github: [bugbot]\n  on_ready:\n    github: [pr-agent]\n', local=False)
        for empty in (False, True):
            values = [] if empty else valid_names
            review = {'internal_reviewers': ['fabricatedOpaqueReviewer\nclaude'],
                      'platforms': ['fabricatedOpaqueReviewer\nclaude'],
                      'phase_after_clean': ['fabricatedOpaqueReviewer\nclaude'],
                      'on_draft': {'runner': values, 'github': values}, 'on_ready': {'github': values}}
            self.write('\n'.join(MODULE.dump_review_projection({'review': review})) + '\n')
            for bucket in self.NAME_BUCKETS:
                json_result = self.cli(bucket[2]); data = json.loads(json_result.stdout)
                bash = self.names_from_bash(bucket)
                self.assertEqual(bash.returncode, 0, bash.stderr)
                self.assertEqual(bash.stdout.splitlines(), values)
                self.assertEqual(data[bucket[3]], values)

    def test_reviewer_name_dependency_free_and_shared_fallback(self):
        blocked = self.root / 'blocked-name-yaml'; blocked.mkdir()
        (blocked / 'yaml.py').write_text('raise ImportError("synthetic parser unavailable")\n')
        env = dict(self.env, PYTHONPATH=str(blocked))
        for bucket in self.NAME_BUCKETS:
            names = ['codex', 'unknown reviewer, punctuation']
            self.write(self.name_document(bucket, names), local=False)
            for local in (None, 'review: {}\n', self.name_document(bucket, [])):
                path = self.checkout / MODULE.LOCAL_CONFIG_NAME
                if local is None: path.unlink(missing_ok=True)
                else: path.write_text(local)
                bash = self.names_from_bash(bucket, env=env)
                self.assertEqual(bash.returncode, 0, bash.stderr)
                self.assertEqual(bash.stdout.splitlines(), [] if local and '[]' in local else names)
        # Existing shared-empty->legacy and local-declared-empty->disabled
        # behavior remains distinct under the common selected-list validator.
        for bucket in self.NAME_BUCKETS:
            modern = {'on_draft': {'runner': [], 'github': []}, 'on_ready': {'github': []}}
            modern.update({'internal_reviewers': ['codex'], 'platforms': ['codex'], 'phase_after_clean': ['codex']})
            self.write('\n'.join(MODULE.dump_review_projection({'review': modern})) + '\n', local=False)
            (self.checkout / MODULE.LOCAL_CONFIG_NAME).unlink(missing_ok=True)
            bash = self.names_from_bash(bucket, env=env)
            self.assertEqual(bash.returncode, 0, bash.stderr)
            expected = [] if bucket[:2] == ('on_draft', 'github') else ['codex']
            self.assertEqual(bash.stdout.splitlines(), expected)

    def test_reviewer_name_three_bucket_projection(self):
        valid = ['codex', 'unknown reviewer, quoted "value"']
        for bucket in self.NAME_BUCKETS:
            self.write(self.name_document(bucket, ['codex', 'fabricatedOpaqueReviewer\nclaude']))
            stage = self.root / ('reject-' + '-'.join(bucket[:2])); stage.mkdir()
            result = self.cli('review-snapshot', '--destination', str(stage))
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertEqual(result.stdout, '')
            self.assertNotIn('fabricatedOpaqueReviewer', result.stderr)
            self.assertFalse((stage / MODULE.LOCAL_CONFIG_NAME).exists())
        self.write('\n'.join(MODULE.dump_review_projection({'review': {
            'on_draft': {'runner': valid, 'github': valid}, 'on_ready': {'github': valid}}})) + '\n')
        stage = self.root / 'accepted-stage'; stage.mkdir()
        result = self.cli('review-snapshot', '--destination', str(stage))
        self.assertEqual(result.returncode, 0, result.stderr)
        for bucket in self.NAME_BUCKETS:
            effective = subprocess.run([sys.executable, str(RESOLVER), bucket[2], '--repo-root', str(stage)], env=self.env, text=True, capture_output=True)
            self.assertEqual(effective.returncode, 0, effective.stderr)
            names = json.loads(effective.stdout)[bucket[3]]
            bash = self.names_from_bash(bucket, root=stage)
            self.assertEqual((bash.returncode, bash.stdout.splitlines()), (0, names), bash.stderr)
            self.assertEqual(names, valid)


if __name__ == '__main__':
    unittest.main()

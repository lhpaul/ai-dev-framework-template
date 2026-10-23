#!/usr/bin/env python3
"""AC1/2 route inventory: private source authority survives composed callers."""
from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import shlex
import subprocess
import unittest

SPEC = importlib.util.spec_from_file_location('consumer_fixtures', Path(__file__).with_name('test_private_source_consumers.py'))
fixtures = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fixtures)


class PrivateSourceAuthority(unittest.TestCase):
    def setUp(self):
        self.f = fixtures.PrivateSourceConsumers(methodName='runTest')
        self.f.setUp()
        self.addCleanup(self.f.doCleanups)
        self.f.env.pop('WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT', None)
        # Only sibling-hub is a discovery candidate; an earlier matching tool
        # manifest must not mask the candidate whose private file we mutate.
        self.f.shared.write_text(self.f.shared.read_text().replace('mode: workflow_hub', 'mode: single_repo', 1))
        self.product = self.f.root / 'product'; self.product.mkdir()
        (self.product / '.ai-dev-workflow.yaml').write_text('''mode: product_repo
product_repo:
  ci_policy: required
  workflow_hub:
    github_repo: fixture/hub
''')
        self.hub = self.f.root / 'sibling-hub'; self.hub.mkdir()
        (self.hub / '.ai-dev-workflow.yaml').write_text('''mode: workflow_hub
workflow_hub:
  product_repos:
    - name: mobile
      github_repo: fixture/mobile
      ci_policy: none
''')
        self.foreign = self.hub / '.ai-dev-workflow.local.yaml'
        self.reads = self.f.root / 'private-reads.jsonl'
        self.calls = self.f.root / 'resolver-calls.jsonl'
        self.allowed = ()
        self.spy = self.f.root / 'spy'; self.spy.mkdir()
        # Python field readers, validators and snapshots all use these open APIs.
        # Only fake private path metadata is recorded; no file contents are logged.
        (self.spy / 'sitecustomize.py').write_text('''import builtins, io, os, json, sys
_builtin, _io, _os = builtins.open, io.open, os.open
if sys.argv[0].endswith('/workflow-config-resolver.py'):
    root = sys.argv[sys.argv.index('--repo-root') + 1] if '--repo-root' in sys.argv else ''
    with _io(CALLS, 'a') as stream:
        stream.write(json.dumps({'command': sys.argv[1], 'repo_root': root}) + '\\n')
def record(file):
    if isinstance(file, (str, bytes, os.PathLike)):
        path = os.fsdecode(file)
        if os.path.basename(path) == '.ai-dev-workflow.local.yaml':
            with _io(TRACE, 'a') as stream:
                stream.write(os.path.realpath(path) + '\\n')
def builtin(file, *args, **kwargs):
    record(file); return _builtin(file, *args, **kwargs)
def io_open(file, *args, **kwargs):
    record(file); return _io(file, *args, **kwargs)
def os_open(file, *args, **kwargs):
    record(file); return _os(file, *args, **kwargs)
builtins.open, io.open, os.open = builtin, io_open, os_open
'''.replace('TRACE', repr(str(self.reads))).replace('CALLS', repr(str(self.calls))))
        import yaml
        self.f.env['PYTHONPATH'] = str(self.spy) + ':' + str(Path(yaml.__file__).resolve().parent.parent)
        for arguments in (['git', 'init', '-q', '-b', 'develop'],
                          ['git', 'config', 'user.name', 'Synthetic fixture'],
                          ['git', 'config', 'user.email', 'fixture@example.test'],
                          ['git', 'add', '.ai-dev-workflow.yaml'],
                          ['git', 'commit', '-qm', 'Selected product policy'],
                          ['git', 'switch', '-qc', 'feature/1993-fixture']):
            subprocess.run(arguments, cwd=self.product, env=self.f.env, check=True, capture_output=True)
        origin = self.f.root / 'product-origin.git'
        subprocess.run(['git', 'clone', '--bare', str(self.product), str(origin)], env=self.f.env, check=True, capture_output=True)
        subprocess.run(['git', 'remote', 'add', 'origin', str(origin)], cwd=self.product, env=self.f.env, check=True, capture_output=True)
        pr = json.loads(self.f.pr.read_text())
        pr['headRefOid'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=self.product, env=self.f.env, text=True).strip()
        self.f.pr.write_text(json.dumps(pr))

    def run_command(self, command, cwd=None):
        return subprocess.run(command, cwd=cwd or self.product, env=self.f.env,
                              capture_output=True, text=True, timeout=30)

    def bash(self, text, cwd=None):
        return self.run_command(['bash', '-c', 'source ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n' + text], cwd=cwd)

    def no_foreign_reads(self, allowed=()):
        paths = set(self.reads.read_text().splitlines()) if self.reads.exists() else set()
        self.assertLessEqual(paths, {str(path.resolve()) for path in allowed}, paths)

    def invariant(self, invoke, check=None, normalize=None):
        baseline = None
        for state, text in (('absent', None), ('created', 'review:\n  on_draft:\n    runner: [cursor]\n'),
                            ('modified', 'product_repos:\n  - name: mobile\n    local_path: ../fabricated-target\n'),
                            ('malformed', 'broken: [synthetic-opaque\n')):
            with self.subTest(state=state):
                for foreign in getattr(self, 'foreign_paths', (self.foreign,)):
                    if text is None:
                        foreign.unlink(missing_ok=True)
                    else:
                        foreign.write_text(text)
                result = invoke()
                self.assertNotIn('synthetic-opaque', result.stdout + result.stderr)
                stdout = normalize(result.stdout) if normalize else result.stdout
                current = (result.returncode, stdout, result.stderr)
                if baseline is None:
                    baseline = current
                    if check:
                        check(result)
                else:
                    self.assertEqual(current, baseline)
                self.no_foreign_reads(self.allowed)
        return baseline

    def parser_reached(self, root=None, command=None):
        events = [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []
        self.assertTrue(any((root is None or event['repo_root'] == str(root)) and
                            (command is None or event['command'] == command) for event in events), events)

    def python(self, *arguments):
        return self.run_command(['python3', str(self.f.runtime / 'workflow-config-resolver.py'), *arguments])

    def relative_override_invariant(self, invoke, command=None, root=None, check=None):
        # The recognized relative source belongs to invocation CWD, never the
        # selected checkout after cd. Only fabricated paths and metadata logged.
        first = self.f.root / 'selected'; first.mkdir(exist_ok=True)
        second = self.product / 'selected'; second.mkdir(exist_ok=True)
        # Git status is public output; hide the synthetic forbidden directory
        # itself so creating its private file does not change unrelated status.
        exclude = self.product / '.git/info/exclude'
        with exclude.open('a') as stream:
            stream.write('\n/selected/\n')
        private = first / '.ai-dev-workflow.local.yaml'
        private.write_text('review:\n  on_draft:\n    runner: [codex]\n    github: [bugbot]\n  on_ready:\n    github: [bugbot]\nproduct_repos:\n  - name: mobile\n    local_path: ../product\n')
        self.f.env['WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT'] = 'selected'
        previous_paths = getattr(self, 'foreign_paths', None)
        self.foreign_paths = [second / '.ai-dev-workflow.local.yaml']
        self.allowed = (private,)
        self.reads.unlink(missing_ok=True)
        self.calls.unlink(missing_ok=True)
        self.invariant(invoke, check)
        self.assertTrue(self.reads.is_file(), 'real entry must read selected synthetic source')
        self.parser_reached(root or self.product, command)
        if previous_paths is None:
            del self.foreign_paths
        else:
            self.foreign_paths = previous_paths

    def test_R01_python_checkout_authority(self):
        self.invariant(lambda: self.python('resolve', '--repo-root', str(self.product), '--json'),
                       lambda result: self.assertEqual(result.returncode, 0, result.stderr))
        self.parser_reached(self.product, 'resolve')

    def test_R02_python_explicit_override(self):
        self.f.private.write_text('review:\n  on_draft:\n    runner: []\n')
        self.f.env['WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT'] = str(self.f.external)
        result = self.python('local-source', '--repo-root', str(self.product))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(Path(result.stdout.strip()), self.f.private)
        self.no_foreign_reads((self.f.private,))
        self.f.private.write_text('broken: [synthetic-opaque\n')
        bad = self.python('local-source', '--repo-root', str(self.product))
        self.assertEqual(bad.returncode, 2)
        self.assertIn('invalid YAML', bad.stderr)
        self.assertNotIn('synthetic-opaque', bad.stderr)
        self.assertEqual(bad.stdout, '')
        command = ('workflow_bind_local_config_root product\ncd product\nsource ' +
                   shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) +
                   '\nworkflow_config_review_on_draft_runner "$(workflow_effective_config_file)"')
        self.relative_override_invariant(lambda: self.bash(command, cwd=self.f.root), 'review-list',
                                         check=lambda result: self.assertEqual(result.stdout.strip(), 'codex'))
        # A pure output redactor must not parse/read selected private bytes on
        # import, even when the explicitly named synthetic source is malformed.
        (self.f.root / 'selected/.ai-dev-workflow.local.yaml').write_text('broken: [synthetic-opaque\n')
        self.reads.unlink(missing_ok=True)
        pure = self.bash("printf 'token=syntheticvalue\\n' | workflow_redact_text", cwd=self.f.root)
        self.assertEqual(pure.returncode, 0, pure.stderr)
        self.assertNotIn('syntheticvalue', pure.stdout)
        self.assertFalse(self.reads.exists(), 'pure library import read private configuration')

    def test_R03_python_model_and_projection_roots(self):
        private = self.product / '.ai-dev-workflow.local.yaml'
        private.write_text('review:\n  on_draft:\n    runner: []\n')
        self.allowed = (private,)
        stage = self.f.root / 'staged'; stage.mkdir()
        def snapshot():
            (stage / '.ai-dev-workflow.local.yaml').unlink(missing_ok=True)
            return self.python('review-snapshot', '--repo-root', str(self.product), '--destination', str(stage))
        self.invariant(snapshot,
                       lambda result: self.assertEqual(result.returncode, 0, result.stderr))
        self.parser_reached(self.product, 'review-snapshot')
        result = self.python('validate', '--repo-root', str(self.product), '--json')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.no_foreign_reads(self.allowed)

    def test_R04_bash_local_selector_root(self):
        # Tool checkout is foreign to this entry, even when an inherited scalar
        # tries to impersonate the process-local binding. Re-source must retain
        # a legitimate in-process binding and command substitutions must see it.
        self.foreign = self.f.checkout / '.ai-dev-workflow.local.yaml'
        self.f.env['_WORKFLOW_LOCAL_CONFIG_ROOT'] = str(self.f.checkout)
        root = shlex.quote('product'); lib = shlex.quote(str(self.f.runtime / 'workflow-lib.sh'))
        command = ('workflow_bind_local_config_root ' + root + '\ncd ' + shlex.quote(str(self.f.checkout)) + '\nsource ' + lib +
                   '\nvalue="$(workflow_local_config_file)" || exit $?\nprintf "%s\\n" "$value"\n'
                   'workflow_merge_ci_policy_into_json \'{}\' ""\n')
        empty_calls = [('workflow_local_config_file ""', 2), ('workflow_bind_local_config_root', 2),
                       ('workflow_hub_root_for_ci_policy ""', 1),
                       ('workflow_product_repo_name_for_github_slug "" fixture/mobile', 1),
                       ('workflow_repository_mode ""', 2), ('workflow_repository_context mobile ""', 2),
                       ('workflow_validate_repository_context mobile ""', 2), ('workflow_review_override_context ""', 2)]
        for call, expected in empty_calls:
            # Conditional invocation must preserve exact failure/absence status.
            command += f'if {call}; then exit 94; else empty_status=$?; test "$empty_status" -eq {expected}; fi\n'
        def check(result):
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), [str(self.product / '.ai-dev-workflow.local.yaml'), '{}'])
        self.invariant(lambda: self.bash(command, cwd=self.f.root), check)

    def test_R05_ci_hub_sibling_probe(self):
        self.invariant(lambda: self.bash('workflow_hub_root_for_ci_policy ' + shlex.quote(str(self.product)) + ' fixture/mobile'),
                       lambda result: self.assertEqual(result.returncode, 1))

    def test_R06_ci_inherited_hub_env(self):
        self.f.env['WORKFLOW_HUB_REPO_ROOT'] = str(self.hub)
        self.invariant(lambda: self.bash('workflow_hub_root_for_ci_policy ' + shlex.quote(str(self.product)) + ' fixture/mobile'),
                       lambda result: self.assertEqual(result.returncode, 1))

    def test_R07_ci_candidate_product_mapping(self):
        # Deliberately selected public hub is allowed; its neighboring private
        # source is not followed when resolving another selected product root.
        self.invariant(lambda: self.bash('workflow_product_repo_name_for_github_slug ' + shlex.quote(str(self.product)) + ' fixture/mobile'),
                       lambda result: self.assertEqual(result.returncode, 1))

    def test_R08_ci_merge_root_rebinding(self):
        command = "workflow_merge_ci_policy_into_json '{\"github_repo\":\"fixture/mobile\"}' " + shlex.quote(str(self.product))
        def check(result):
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout)['ciPolicy'], 'required')
        self.invariant(lambda: self.bash(command), check)

    def actual_ci_entry(self, filename):
        path = self.f.root / 'input.json'
        path.write_text(json.dumps({'pr_number': 1993, 'github_repo': 'fixture/mobile',
                                    'files': [], 'base': 'develop', 'head': 'docs/1993-fixture',
                                    'pr': {'number': 1993, 'headRefName': 'docs/1993-fixture', 'baseRefName': 'develop'}}))
        return self.run_command(['bash', str(self.f.runtime / filename), '--repo-root', str(self.product), '--input', str(path), '--json'])

    def test_R09_risk_entry_no_discovery(self):
        self.invariant(lambda: self.actual_ci_entry('run-epic-risk-classifier.sh'),
                       lambda result: self.assertEqual(result.returncode, 0, result.stderr))
        self.parser_reached(self.product, 'resolve')

    def test_R10_gate_entry_no_discovery(self):
        self.invariant(lambda: self.actual_ci_entry('run-epic-delegated-gate.sh'),
                       lambda result: self.assertEqual(result.returncode, 0, result.stderr))
        self.parser_reached(self.product, 'resolve')

    def entry_with_selected_root(self, script):
        previous = self.f.checkout
        self.f.checkout = self.product
        try:
            return self.f.execute(('', '', 'entry', script))
        finally:
            self.f.checkout = previous

    def selected_entry_invariance(self, script):
        self.foreign = self.f.checkout / '.ai-dev-workflow.local.yaml'
        self.invariant(lambda: self.entry_with_selected_root(script),
                       lambda result: self.assertNotIn('invalid YAML', result.stderr))
        self.parser_reached(self.product, 'local-source')
        events = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertFalse(any(event['repo_root'] == str(self.f.checkout) for event in events), events)

    def test_R11_coderabbit_selected_root(self):
        self.selected_entry_invariance('coderabbit-cli-reviewer.sh')

    def test_R12_ci_loop_selected_root(self):
        self.nested_checkouts()
        command = ['bash', str(self.f.runtime / 'pr-ci-loop.sh'), '1993', '--repo-root', 'product',
                   '--product-repo', 'mobile', '--poll-interval', '1', '--max-wait', '1']
        self.invariant(lambda: self.run_command(command, cwd=self.f.root))
        self.parser_reached(self.product, 'resolve')
        command = ['bash', str(self.f.runtime / 'pr-ci-loop.sh'), '1993', '--repo-root', 'product',
                   '--repo', 'fixture/repo', '--poll-interval', '1', '--max-wait', '1']
        self.relative_override_invariant(lambda: self.run_command(command, cwd=self.f.root), 'review-list')

    def test_R13_review_loop_root_and_handoff(self):
        self.selected_entry_invariance('pr-review-loop.sh')

    def review_function(self, script, name, command):
        dependencies = fixtures.function_text(script, 'trim') + '\n' if name == 'reviewer_loop_repo_configured_platforms' else ''
        return self.bash('workflow_bind_local_config_root ' + shlex.quote(str(self.product)) + '\n' +
                         dependencies + fixtures.function_text(script, name) + '\n' + command)

    def test_R14_review_base_shared_snapshot(self):
        self.foreign = self.f.checkout / '.ai-dev-workflow.local.yaml'
        base = self.f.root / 'base.yaml'; base.write_text(self.f.shared.read_text())
        command = ('config_file=' + shlex.quote(str(base)) + '\nWORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 '
                   'reviewer_loop_repo_configured_platforms')
        self.invariant(lambda: self.review_function('pr-review-loop.sh', 'reviewer_loop_repo_configured_platforms', command),
                       lambda result: self.assertEqual(result.returncode, 0, result.stderr))
        self.parser_reached(self.product, 'review-list')

    def test_R15_readiness_base_snapshot(self):
        import base64
        encoded = base64.b64encode(self.f.shared.read_bytes()).decode()
        command = "gh() { printf '%s\\n' " + shlex.quote(encoded) + "; }\nloop_dispatched_base=1\npr_head_config_ready_platforms fixture/repo synthetic-sha"
        self.foreign = self.f.checkout / '.ai-dev-workflow.local.yaml'
        self.invariant(lambda: self.review_function('apply-readiness-labels.sh', 'pr_head_config_ready_platforms', command),
                       lambda result: self.assertEqual(result.returncode, 0, result.stderr))
        self.parser_reached(self.product, 'review-list')
        relative = ('workflow_bind_local_config_root product\ncd product\n' +
                    fixtures.function_text('apply-readiness-labels.sh', 'pr_head_config_ready_platforms') +
                    '\n' + command)
        self.relative_override_invariant(lambda: self.bash(relative, cwd=self.f.root), 'review-list')

    def test_R16_preflight_projection_handoff(self):
        # Existing pinning suite exercises both staged readers, source mutation,
        # and no-projection. This real entry adds neighbor no-override isolation.
        result = self.invariant(lambda: self.entry_with_selected_root('reviewer-preflight.sh'),
                                normalize=lambda output: '\n'.join(line for line in output.splitlines()
                                                                    if not line.startswith('ELAPSED_SECONDS=')))
        self.assertNotIn('invalid YAML', result[2])
        self.parser_reached(self.product, 'review-snapshot')

    def test_R17_availability_selected_root(self):
        self.invariant(lambda: self.entry_with_selected_root('resolve-reviewer-availability.sh'),
                       normalize=lambda output: '\n'.join(line for line in output.splitlines()
                                                           if not line.startswith('ELAPSED_SECONDS=')))
        self.parser_reached(self.product, 'review-effective')

    def test_R18_context_target_path_not_source(self):
        self.f.shared.write_text(self.f.shared.read_text().replace('mode: single_repo', 'mode: workflow_hub', 1))
        private = self.f.checkout / '.ai-dev-workflow.local.yaml'
        private.write_text('product_repos:\n  - name: mobile\n    local_path: ../sibling-hub\n')
        self.allowed = (private,)
        self.invariant(lambda: self.python('resolve', '--repo-root', str(self.f.checkout), '--repo', 'mobile', '--json'),
                       lambda result: self.assertEqual(json.loads(result.stdout)['TARGET_LOCAL_PATH'], str(self.hub)))
        # These entries retain their original CWD (script-dir cd is a subshell),
        # including open-product-pr's token-helper handoff. Real dry-run/status
        # entry controls need no credential or provider invocation.
        for script, arguments, command in (
            ('github-app-token.sh', ['--status'], 'auth'),
            ('open-product-pr.sh', ['--base', 'develop', '--approved-base', 'develop',
                                    '--head', 'feature/1993-fixture', '--title', 'Synthetic',
                                    '--body-file', str(self.f.body), '--dry-run'], 'resolve')):
            with self.subTest(entry=script):
                self.relative_override_invariant(lambda: self.run_command(
                    ['bash', str(self.f.runtime / script), '--repo-root', str(self.f.checkout),
                     '--repo', 'mobile', *arguments], cwd=self.f.root), command, self.f.checkout)

    def test_R19_cleanup_caller_worktree_authority(self):
        # Real linked-worktree identity, read-only inspection only. Main-clone
        # private changes cannot become the initiating worktree's source.
        subprocess.run(['git', 'switch', '-q', 'develop'], cwd=self.f.checkout, env=self.f.env, check=True, capture_output=True)
        linked = self.f.root / 'linked'
        subprocess.run(['git', 'worktree', 'add', '-q', str(linked), 'feature/1993-fixture'],
                       cwd=self.f.checkout, env=self.f.env, check=True, capture_output=True)
        self.foreign = self.f.checkout / '.ai-dev-workflow.local.yaml'
        self.invariant(lambda: self.run_command(['bash', str(self.f.runtime / 'post-merge-cleanup.sh'),
                                                '--inspect-targets', 'feature/1993-fixture'], cwd=linked))
        self.parser_reached(linked, 'mode')
        inherited_cases = [
            {'POST_MERGE_CLEANUP_REENTERED': '1'},
            {'POST_MERGE_CLEANUP_BUDGET_ENTERED': '1', 'POST_MERGE_CLEANUP_CALLER_WORKTREES': str(self.f.checkout)},
            {'GIT_DIR': str(self.f.checkout / '.git'), 'GIT_WORK_TREE': str(self.f.checkout),
             'GIT_COMMON_DIR': str(self.f.checkout / '.git'), 'GIT_CONFIG_COUNT': '1',
             'GIT_CONFIG_KEY_0': 'core.worktree', 'GIT_CONFIG_VALUE_0': str(self.f.checkout)},
        ]
        original_env = dict(self.f.env)
        for inherited in inherited_cases:
            with self.subTest(inherited=','.join(sorted(inherited))):
                self.f.env = dict(original_env, **inherited)
                self.calls.unlink(missing_ok=True)
                self.invariant(lambda: self.run_command(['bash', str(self.f.runtime / 'post-merge-cleanup.sh'),
                                                        '--inspect-targets', 'feature/1993-fixture'], cwd=linked))
                self.parser_reached(linked, 'mode')
        self.f.env = original_env
        # Relative explicit root is anchored at invocation CWD, before the
        # helper enters the selected checkout or considers caller worktrees.
        self.nested_checkouts(base=self.f.checkout)
        self.invariant(lambda: self.run_command(['bash', str(self.f.runtime / 'post-merge-cleanup.sh'),
                                                '--repo-root', 'product', '--inspect-targets', 'feature/1993-fixture'],
                                               cwd=self.f.root))
        self.parser_reached(self.product, 'mode')
        self.relative_override_invariant(lambda: self.run_command(
            ['bash', str(self.f.runtime / 'post-merge-cleanup.sh'), '--repo-root', 'product',
             '--inspect-targets', 'feature/1993-fixture'], cwd=self.f.root), 'mode')

    def test_R20_home_and_unrecognized_env_no_authority(self):
        self.f.env.update(HOME=str(self.hub), GIT_COMMON_DIR=str(self.hub),
                          WORKFLOW_HUB_REPO_ROOT=str(self.hub), WORKFLOW_REPO_ROOT=str(self.hub))
        self.invariant(lambda: self.python('local-source', '--repo-root', str(self.product)),
                       lambda result: self.assertEqual(result.stdout.strip(), str(self.product / '.ai-dev-workflow.local.yaml')))

    def test_R21_selected_local_writer_containment(self):
        # set-local-path is an explicit fixture-only operation. Its target path
        # is data and cannot cause reading that target's private configuration.
        self.allowed = (self.f.checkout / '.ai-dev-workflow.local.yaml',)
        self.f.shared.write_text(self.f.shared.read_text().replace('mode: single_repo', 'mode: workflow_hub', 1))
        self.invariant(lambda: self.python('set-local-path', '--repo-root', str(self.f.checkout), '--repo', 'mobile', '--local-path', str(self.hub)),
                       lambda result: self.assertEqual(result.returncode, 0, result.stderr))

    def test_R22_shared_override_not_private_authority(self):
        self.f.env['AI_DEV_WORKFLOW_CONFIG_FILE'] = str(self.hub / '.ai-dev-workflow.yaml')
        command = ('workflow_bind_local_config_root ' + shlex.quote(str(self.product)) +
                   '\nWORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 workflow_config_review_on_draft_runner "$(workflow_effective_config_file)"')
        self.invariant(lambda: self.bash(command), lambda result: self.assertEqual(result.returncode, 0, result.stderr))
        self.parser_reached(self.product, 'review-list')

    def test_R23_completion_selected_root(self):
        # Relative entry roots must be bound before cd changes their meaning.
        self.foreign = self.f.checkout / '.ai-dev-workflow.local.yaml'
        command = ['bash', str(self.f.runtime / 'item-completion-self-check.sh'),
                   '--issue', '1993', '--branch', 'feature/1993-fixture', '--stage', 'synthetic',
                   '--worktree-path', str(self.product), '--repo-root', 'product', '--pr', '1993',
                   '--expected-base', 'develop', '--require-clean', 'false', '--require-ci-green', 'false',
                   '--require-review-summary', 'true', '--require-review-threads', 'true']
        self.invariant(lambda: self.run_command(command, cwd=self.f.root), lambda result: self.assertNotIn('unreadable directory', result.stderr))
        self.parser_reached(self.product, 'local-source')
        self.parser_reached(self.product, 'review-list')
        self.relative_override_invariant(lambda: self.run_command(command, cwd=self.f.root), 'review-list')

    def nested_checkouts(self, base=None):
        # Reinterpreting "product" after one or more cd/child boundaries would
        # land in a distinguishable nested fake checkout, never a missing path.
        root = base or self.product
        self.foreign_paths = []
        for _ in range(3):
            root = root / 'product'; root.mkdir()
            (root / '.ai-dev-workflow.yaml').write_text((self.product / '.ai-dev-workflow.yaml').read_text())
            (root / '.git').mkdir()
            (root / '.git/config').write_text('[remote "origin"]\n url = https://github.com/fixture/foreign\n')
            self.foreign_paths.append(root / '.ai-dev-workflow.local.yaml')
        self.f.env['WORKFLOW_SKIP_FETCH'] = '1'

    def relative_entry(self, script, arguments):
        self.nested_checkouts()
        self.invariant(lambda: self.run_command(['bash', str(self.f.runtime / script), '--repo-root', 'product', *arguments],
                                               cwd=self.f.root))
        self.parser_reached(self.product, 'mode')
        self.relative_override_invariant(lambda: self.run_command(
            ['bash', str(self.f.runtime / script), '--repo-root', 'product', *arguments], cwd=self.f.root), 'mode')

    def test_R24_discovery_relative_root(self):
        self.relative_entry('discover-workflow-state.sh', [])

    def test_R25_next_action_relative_root(self):
        self.relative_entry('workflow-next-action.sh', ['--branch', 'feature/1993-fixture'])

    def test_R26_batch_plan_relative_handoff(self):
        development = self.f.root / 'development'; development.mkdir()
        # A real development has a document; empty arrays in the unrelated
        # pre-existing Bash 3.2 issue-number helper must not mask this route.
        (development / '1_specs.md').write_text('**Issue**: #1993\n')
        self.relative_entry('workflow-batch-plan.sh', [str(development)])

    def test_R27_batch_lanes_relative_handoff(self):
        development = self.f.root / 'development'; development.mkdir()
        # A real development has a document; empty arrays in the unrelated
        # pre-existing Bash 3.2 issue-number helper must not mask this route.
        (development / '1_specs.md').write_text('**Issue**: #1993\n')
        self.relative_entry('workflow-batch-lanes.sh', ['--scan', str(development)])

    def readiness_handoff_fixture(self):
        """Only GH transport is fake; reader, ownership and child entry are real."""
        import sys
        home = self.f.root / 'readiness-home'; home.mkdir()
        self.f.env['HOME'] = str(home)
        self.child_events = self.f.root / 'readiness-children.jsonl'
        self.f.env.update(GH_REPO='fixture/repo', SYNTHETIC_CHILD_EVENTS=str(self.child_events))
        pr = json.loads(self.f.pr.read_text())
        # Intentional ownership rejection is a valid gate outcome after source
        # selection, distinct from selected-source failure2 or argument errors.
        pr.update(headRefName='feature/1993-other', isCrossRepository=False,
                  headRepositoryOwner={'login': 'fixture'}, headRepository={'name': 'repo'})
        self.f.pr.write_text(json.dumps(pr))
        (self.f.bin / 'gh').write_text('''#!PYTHON
import json, os, subprocess, sys
args = sys.argv[1:]
if args[:2] == ['auth', 'status']:
    raise SystemExit(0)
if args[:2] == ['repo', 'view']:
    print('fixture/repo'); raise SystemExit(0)
if args[:2] == ['pr', 'view']:
    data = json.load(open(os.environ['SYNTHETIC_PR']))
    if '--json' in args and args[args.index('--json') + 1] == 'labels':
        data = {'labels': [{'name': 'ready-for-regression'}] if os.environ.get('SYNTHETIC_LABEL_PRESENT') == '1' else []}
    raw = json.dumps(data)
    if '--jq' in args:
        result = subprocess.run(['jq', '-r', args[args.index('--jq') + 1]], input=raw, text=True, capture_output=True)
        sys.stdout.write(result.stdout); raise SystemExit(result.returncode)
    print(raw); raise SystemExit(0)
if args[:2] == ['pr', 'edit']:
    with open(os.environ['SYNTHETIC_MUTATIONS'], 'a') as out: out.write('unexpected-label-write\\n')
raise SystemExit(99)
'''.replace('PYTHON', sys.executable))
        (self.f.bin / 'bash').write_text('''#!PYTHON
import json, os, subprocess, sys
args = sys.argv[1:]
result = subprocess.run([os.environ['SYNTHETIC_BASH'], *args])
if args and args[0].endswith('/apply-readiness-labels.sh'):
    root = args[args.index('--repo-root') + 1] if '--repo-root' in args else None
    with open(os.environ['SYNTHETIC_CHILD_EVENTS'], 'a') as out:
        out.write(json.dumps({'status': result.returncode, 'repo_root': root, 'cwd': os.getcwd()}) + '\\n')
raise SystemExit(result.returncode)
'''.replace('PYTHON', sys.executable))
        (self.f.bin / 'bash').chmod(0o755)

    def readiness_handoff_case(self, route):
        self.readiness_handoff_fixture()
        selected = self.product / '.ai-dev-workflow.local.yaml'
        tool_private = self.f.checkout / '.ai-dev-workflow.local.yaml'
        shells = [path for path in ('/bin/bash', '/opt/homebrew/bin/bash') if Path(path).is_file()]
        for shell in shells:
            self.f.env['SYNTHETIC_BASH'] = shell
            for declaration in (None, 'product_repos: []\n'):
                if declaration is None:
                    selected.unlink(missing_ok=True)
                else:
                    selected.write_text(declaration)
                baseline = None
                for state, text in [('absent', None),
                                    ('created', 'review:\n  on_ready:\n    github: [synthetic-opaque-created]\n'),
                                    ('changed', 'product_repos:\n  - name: synthetic-opaque-changed\n'),
                                    ('invalid', 'broken: [synthetic-opaque-invalid\n')]:
                    with self.subTest(route=route, shell=shell, selected=declaration is not None, tooling=state):
                        if text is None:
                            tool_private.unlink(missing_ok=True)
                        else:
                            tool_private.write_text(text)
                        self.reads.unlink(missing_ok=True)
                        self.child_events.unlink(missing_ok=True)
                        if route == 'direct':
                            result = self.run_command([shell, str(self.f.runtime / 'apply-readiness-labels.sh'),
                                                       '--pr', '1993', '--repo', 'fixture/repo',
                                                       '--branch', 'feature/1993-fixture', '--repo-root', str(self.product),
                                                       '--label', 'ready-for-regression', '--dry-run'], cwd=self.f.runtime)
                            self.assertEqual(result.returncode, 1)
                        else:
                            self.f.env['SYNTHETIC_LABEL_PRESENT'] = '1' if route == 'revalidate' else '0'
                            command = ('SCRIPT_DIR=' + shlex.quote(str(self.f.runtime)) + '\n' +
                                       fixtures.function_text('pr-review-loop.sh', 'restore_regression_label_if_missing') + '\n' +
                                       'repo_root=' + shlex.quote(str(self.product)) + '\n' +
                                       'workflow_bind_local_config_root "$repo_root" || exit 2\n' +
                                       'restore_regression_label_if_missing 1993 feature/1993-fixture\n')
                            result = self.bash(command, cwd=self.f.runtime)
                            self.assertEqual(result.returncode, 0)  # Existing best-effort contract.
                            events = [json.loads(line) for line in self.child_events.read_text().splitlines()]
                            self.assertEqual(len(events), 1)
                            self.assertEqual(events[0]['status'], 1)
                            self.assertEqual(events[0]['repo_root'], str(self.product))
                            self.assertIn('WARN: apply-readiness-labels.sh refused or failed', result.stderr)
                        self.assertIn('REASON=ownership-mismatch', result.stdout)
                        self.assertIn('OWNERSHIP_EXPECTED_BRANCH=feature/1993-fixture', result.stdout)
                        self.assertNotIn('synthetic-opaque', result.stdout + result.stderr)
                        current = (result.returncode, result.stdout, result.stderr)
                        if baseline is None:
                            baseline = current
                        else:
                            self.assertEqual(current, baseline)
                        self.no_foreign_reads((selected,))
                        if selected.exists():
                            self.assertIn(str(selected.resolve()), self.reads.read_text().splitlines())
                        self.assertFalse(self.f.log.exists(), 'readiness rejection must not mutate or run a reviewer')

    def test_R28_readiness_explicit_root_real_subprocess(self):
        self.readiness_handoff_case('direct')

    def test_R29_readiness_restore_root_real_subprocess(self):
        self.readiness_handoff_case('restore')

    def test_R30_readiness_revalidate_root_real_subprocess(self):
        self.readiness_handoff_case('revalidate')

    def test_R31_readiness_source_failure_and_explicit_tool_checkout(self):
        self.readiness_handoff_fixture()
        self.f.env['SYNTHETIC_BASH'] = '/bin/bash'
        selected = self.product / '.ai-dev-workflow.local.yaml'
        selected.write_text('broken: [synthetic-opaque-selected\n')
        arguments = ['--pr', '1993', '--repo', 'fixture/repo', '--branch', 'feature/1993-fixture',
                     '--label', 'ready-for-regression', '--dry-run']
        result = self.run_command(['/bin/bash', str(self.f.runtime / 'apply-readiness-labels.sh'),
                                   *arguments, '--repo-root', str(self.product)], cwd=self.f.runtime)
        self.assertEqual((result.returncode, result.stdout), (2, ''))
        self.assertRegex(result.stderr, r'^ERROR: configuration: invalid YAML; line=1\n$')
        self.assertNotIn('synthetic-opaque', result.stdout + result.stderr)
        self.no_foreign_reads((selected,))
        # Explicit selection of the tooling checkout remains legitimate.
        tool_private = self.f.checkout / '.ai-dev-workflow.local.yaml'
        tool_private.write_text('product_repos: []\n')
        self.reads.unlink(missing_ok=True)
        result = self.run_command(['/bin/bash', str(self.f.runtime / 'apply-readiness-labels.sh'),
                                   *arguments, '--repo-root', str(self.f.checkout)], cwd=self.product)
        self.assertEqual(result.returncode, 1)
        self.assertIn('REASON=ownership-mismatch', result.stdout)
        self.no_foreign_reads((tool_private,))
        self.assertIn(str(tool_private.resolve()), self.reads.read_text().splitlines())
        # The existing no-flag default still deliberately selects that tool root.
        result = self.run_command(['/bin/bash', str(self.f.runtime / 'apply-readiness-labels.sh'),
                                   *arguments], cwd=self.product)
        self.assertEqual(result.returncode, 1)
        self.no_foreign_reads((tool_private,))
        for flag in ('--classify-pr-agent', '--pr-agent-focus-labels'):
            self.reads.unlink(missing_ok=True)
            result = subprocess.run(['/bin/bash', str(self.f.runtime / 'apply-readiness-labels.sh'), flag],
                                    env=self.f.env, cwd=self.f.runtime, input='No major issues detected\n',
                                    text=True, capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0)
            self.assertFalse(self.reads.exists(), 'stdin-only classifier must not read configuration')


if __name__ == '__main__':
    unittest.main(verbosity=2)

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

    def bash(self, text):
        return self.run_command(['bash', '-c', 'source ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n' + text])

    def no_foreign_reads(self, allowed=()):
        paths = set(self.reads.read_text().splitlines()) if self.reads.exists() else set()
        self.assertLessEqual(paths, {str(path.resolve()) for path in allowed}, paths)

    def invariant(self, invoke, check=None, normalize=None):
        baseline = None
        for state, text in (('absent', None), ('created', 'review:\n  on_draft:\n    runner: [cursor]\n'),
                            ('modified', 'product_repos:\n  - name: mobile\n    local_path: ../fabricated-target\n'),
                            ('malformed', 'broken: [synthetic-opaque\n')):
            with self.subTest(state=state):
                if text is not None:
                    self.foreign.write_text(text)
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
        root = shlex.quote('../product'); lib = shlex.quote(str(self.f.runtime / 'workflow-lib.sh'))
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
        self.invariant(lambda: self.bash(command), check)

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
        # Stop before GitHub polling, after the real selected-source parser.
        (self.f.bin / 'gh').write_text('#!/bin/sh\nexit 99\n')
        self.selected_entry_invariance('pr-ci-loop.sh')

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
        self.parser_reached(self.product, 'review-local-list')

    def test_R15_readiness_base_snapshot(self):
        import base64
        encoded = base64.b64encode(self.f.shared.read_bytes()).decode()
        command = "gh() { printf '%s\\n' " + shlex.quote(encoded) + "; }\nloop_dispatched_base=1\npr_head_config_ready_platforms fixture/repo synthetic-sha"
        self.foreign = self.f.checkout / '.ai-dev-workflow.local.yaml'
        self.invariant(lambda: self.review_function('apply-readiness-labels.sh', 'pr_head_config_ready_platforms', command),
                       lambda result: self.assertEqual(result.returncode, 0, result.stderr))
        self.parser_reached(self.product, 'review-local-list')

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
        self.parser_reached(self.product, 'review-local-list')

    def test_R23_completion_selected_root(self):
        # Real synthetic completion entry, with all remote/runtime calls stubbed.
        self.selected_entry_invariance('item-completion-self-check.sh')


if __name__ == '__main__':
    unittest.main(verbosity=2)

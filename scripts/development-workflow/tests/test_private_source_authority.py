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
        self.spy = self.f.root / 'spy'; self.spy.mkdir()
        # Python field readers, validators and snapshots all use these open APIs.
        # Only fake private path metadata is recorded; no file contents are logged.
        (self.spy / 'sitecustomize.py').write_text('''import builtins, io, os
_builtin, _io, _os = builtins.open, io.open, os.open
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
'''.replace('TRACE', repr(str(self.reads))))
        import yaml
        self.f.env['PYTHONPATH'] = str(self.spy) + ':' + str(Path(yaml.__file__).resolve().parent.parent)

    def run_command(self, command, cwd=None):
        return subprocess.run(command, cwd=cwd or self.product, env=self.f.env,
                              capture_output=True, text=True, timeout=30)

    def bash(self, text):
        return self.run_command(['bash', '-c', 'source ' + shlex.quote(str(self.f.runtime / 'workflow-lib.sh')) + '\n' + text])

    def no_foreign_reads(self, allowed=()):
        paths = set(self.reads.read_text().splitlines()) if self.reads.exists() else set()
        self.assertLessEqual(paths, {str(path.resolve()) for path in allowed}, paths)

    def invariant(self, invoke, check=None):
        baseline = None
        for state, text in (('absent', None), ('created', 'review:\n  on_draft:\n    runner: [cursor]\n'),
                            ('modified', 'product_repos:\n  - name: mobile\n    local_path: ../fabricated-target\n'),
                            ('malformed', 'broken: [synthetic-opaque\n')):
            with self.subTest(state=state):
                if text is not None:
                    self.foreign.write_text(text)
                result = invoke()
                self.assertNotIn('synthetic-opaque', result.stdout + result.stderr)
                current = (result.returncode, result.stdout, result.stderr)
                if baseline is None:
                    baseline = current
                    if check:
                        check(result)
                else:
                    self.assertEqual(current, baseline)
                self.no_foreign_reads()
        return baseline

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

    def test_R10_gate_entry_no_discovery(self):
        self.invariant(lambda: self.actual_ci_entry('run-epic-delegated-gate.sh'),
                       lambda result: self.assertEqual(result.returncode, 0, result.stderr))


if __name__ == '__main__':
    unittest.main(verbosity=2)

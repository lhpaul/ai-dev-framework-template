#!/usr/bin/env python3
"""Synthetic-only runner security regressions. Never load workstation settings."""
from __future__ import annotations

import ast
import importlib.util
import json
import os
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
with patch.object(Path, 'read_text', side_effect=AssertionError('import read configuration')):
    SPEC.loader.exec_module(MODULE)


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
        for key in ('WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT', 'AI_DEV_WORKFLOW_CONFIG_FILE',
                    'WORKFLOW_MERGE_BUDGET_SESSION', 'WORKFLOW_MERGE_BUDGET_OWNER_ROOT'):
            self.env.pop(key, None)
        self.env['PYTHONDONTWRITEBYTECODE'] = '1'

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
            # Actual public startup must stop before any stubbed service mutation.
            scripts = self.checkout / 'scripts/development-workflow'
            scripts.mkdir(parents=True, exist_ok=True)
            for file in ('workflow-lib.sh', 'workflow-config-resolver.py', 'pr-ci-loop.sh',
                         'pr-review-loop.sh', 'apply-readiness-labels.sh', 'coderabbit-cli-reviewer.sh'):
                shutil.copyfile(SCRIPTS / file, scripts / file)
            bindir = self.root / 'bin'; bindir.mkdir(exist_ok=True)
            for service in ('gh', 'codex', 'claude', 'coderabbit', 'cr'):
                stub = bindir / service
                stub.write_text('#!/bin/sh\necho unexpected-service >> "$MUTATION_LOG"\nexit 99\n'); stub.chmod(0o755)
            script_env = dict(env, PATH=str(bindir) + os.pathsep + self.env['PATH'], MUTATION_LOG=str(self.root / 'mutations'))
            for file in ('pr-ci-loop.sh', 'pr-review-loop.sh', 'apply-readiness-labels.sh', 'coderabbit-cli-reviewer.sh'):
                result = subprocess.run(['bash', str(scripts / file)], env=script_env, capture_output=True, text=True)
                self.assertEqual(result.returncode, 2, (file, result.stderr))
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


if __name__ == '__main__':
    unittest.main()

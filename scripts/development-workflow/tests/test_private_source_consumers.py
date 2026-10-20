#!/usr/bin/env python3
"""Binding AC3 inventory: each real Bash consumer rejects a broken private source."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / 'scripts/development-workflow'
# IDs are the pre-edit cycle3 inventory, including the additive E10 crosscheck.
# Each tuple selects a real public function or executable entry, not a mock reader.
CASES = [
    ('L01', 'workflow_local_config_file', 'lib', ''),
    ('L02', 'workflow_local_review_override_root', 'lib', ''),
    ('L03', 'workflow_config_review_local_list_if_declared', 'lib', 'SHARED on_draft runner'),
    ('L04', 'workflow_config_review_on_draft_runner', 'lib', 'SHARED'),
    ('L05', 'workflow_config_review_on_draft_github', 'lib', 'SHARED'),
    ('L06', 'workflow_config_review_on_ready_github', 'lib', 'SHARED'),
    ('L07', 'workflow_config_review_platforms', 'lib', 'SHARED'),
    ('L08', 'workflow_config_review_phase_after_clean_platforms', 'lib', 'SHARED'),
    ('L09', 'workflow_config_review_github_reviewer_configured', 'lib', 'shared-policy-sentinel SHARED'),
    ('L10', 'configured_reviewer_check_names_json', 'lib', ''),
    ('L11', 'workflow_repository_mode', 'lib', 'CHECKOUT'),
    ('L12', 'workflow_repository_context', 'lib', 'mobile CHECKOUT'),
    ('L13', 'workflow_validate_repository_context', 'lib', 'mobile CHECKOUT'),
    ('L14', 'workflow_review_override_context', 'lib', 'CHECKOUT'),
    ('L15', 'workflow_product_repo_name_for_github_slug', 'lib', 'CHECKOUT fixture/mobile'),
    ('L16', 'workflow_hub_root_for_ci_policy', 'lib', 'CHECKOUT fixture/mobile'),
    ('L17', 'workflow_merge_ci_policy_into_json', 'lib', "'{}' CHECKOUT mobile"),
    ('C01', 'rate_limit_policy_from_file', 'coderabbit-cli-reviewer.sh', 'PRIVATE'),
    ('C02', 'rate_limit_policy_from_config', 'coderabbit-cli-reviewer.sh', ''),
    ('C03', 'coderabbit_startup', 'entry', 'coderabbit-cli-reviewer.sh'),
    ('C04', 'resolve_local_review_override_root', 'pr-review-loop.sh', 'CHECKOUT'),
    ('C05', 'review_loop_startup', 'entry', 'pr-review-loop.sh'),
    ('C06', 'reviewer_loop_repo_configured_platforms', 'pr-review-loop.sh', ''),
    ('C07', 'emit_review_lifecycle_duplicate_warnings', 'pr-review-loop.sh', 'SHARED'),
    ('C08', 'configured_ready_reviewer_platforms', 'apply-readiness-labels.sh', ''),
    ('C09', 'pr_head_config_ready_platforms', 'apply-readiness-labels.sh', 'fixture/repo fake-sha'),
    ('C10', 'readiness_startup', 'entry', 'apply-readiness-labels.sh'),
    ('C11', 'configured_review_platforms', 'item-completion-self-check.sh', 'SHARED'),
    ('C12', 'configured_platforms_all_no_thread', 'item-completion-self-check.sh', ''),
    ('C13', 'configured_thread_bot_logins_json', 'item-completion-self-check.sh', ''),
    ('C14', 'local_ai_reviewer_configured', 'item-completion-self-check.sh', ''),
    ('C15', 'reviewer_check_names_json', 'item-completion-self-check.sh', ''),
    ('C16', 'completion_pr_evidence', 'entry', 'item-completion-self-check.sh'),
    ('C17', 'ci_loop_startup', 'entry', 'pr-ci-loop.sh'),
    ('C18', 'policy_recommender_count', 'entry', 'run-epic-policy-recommender.sh'),
    ('C19', 'reviewer_availability', 'entry', 'resolve-reviewer-availability.sh'),
    ('C20', 'reviewer_preflight', 'entry', 'reviewer-preflight.sh'),
    ('D01', 'validate_context', 'entry', 'validate-workflow-config.sh'),
    ('D02', 'component_target', 'entry', 'component-release-target.sh'),
    ('D03', 'github_app_auth', 'entry', 'github-app-token.sh'),
    ('D04', 'open_product_pr', 'entry', 'open-product-pr.sh'),
    ('D05', 'hub_require_workflow_hub_mode', 'hub', 'CHECKOUT'),
    ('D06', 'hub_list_product_repos', 'hub', 'CHECKOUT'),
    ('D07', 'hub_selected_repos', 'hub', "CHECKOUT '' true"),
    ('D08', 'hub_resolve_context_json', 'hub', 'CHECKOUT mobile'),
    ('E01', 'hub_status', 'entry', 'hub-status.sh'),
    ('E02', 'hub_list_prs', 'entry', 'hub-list-prs.sh'),
    ('E03', 'hub_sync', 'entry', 'hub-sync-product-repos.sh'),
    ('E04', 'discover_state', 'entry', 'discover-workflow-state.sh'),
    ('E05', 'next_action', 'entry', 'workflow-next-action.sh'),
    ('E06', 'epic_scope', 'entry', 'run-epic-scope-resolver.sh'),
    ('E07', 'cleanup_inspection', 'entry', 'post-merge-cleanup.sh'),
    ('E08', 'risk_ci_policy', 'entry', 'run-epic-risk-classifier.sh'),
    ('E09', 'delegated_ci_policy', 'entry', 'run-epic-delegated-gate.sh'),
    ('E10', 'hub_preflight', 'entry', 'hub-preflight-product-repos.sh'),
]
assert len(CASES) == 55 and len({row[0] for row in CASES}) == 55


def function_text(file: str, name: str) -> str:
    text = (SCRIPTS / file).read_text()
    start = text.index(name + '() {')
    return text[start:text.index('\n}', start) + 2]


class PrivateSourceConsumers(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='private-consumer-1993-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.checkout = self.root / 'checkout'; self.checkout.mkdir()
        self.external = self.root / 'explicit'; self.external.mkdir()
        self.shared = self.checkout / '.ai-dev-workflow.yaml'
        self.private = self.external / '.ai-dev-workflow.local.yaml'
        self.shared.write_text('''mode: workflow_hub
workflow_hub:
  product_repos:
    - name: mobile
      github_repo: fixture/mobile
review:
  on_draft:
    runner: [shared-policy-sentinel]
    github: [shared-policy-sentinel]
  on_ready:
    github: [shared-policy-sentinel]
  coderabbit_cli:
    rate_limit_policy: warn
''')
        self.runtime = self.checkout / 'scripts/development-workflow'
        self.runtime.mkdir(parents=True)
        # Read tracked public runtime files only; no workstation local file copy.
        tracked = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z', 'scripts/development-workflow']).split(b'\0')
        for raw in tracked:
            if not raw:
                continue
            path = ROOT / os.fsdecode(raw)
            if path.parent == SCRIPTS and path.suffix in ('.sh', '.py'):
                shutil.copy2(path, self.runtime / path.name)
        self.env = {k: v for k, v in os.environ.items()
                    if k in ('PATH', 'TMPDIR', 'LANG', 'LC_ALL', 'LC_CTYPE', 'TERM')}
        self.env.update(GIT_CONFIG_GLOBAL='/dev/null', GIT_CONFIG_SYSTEM='/dev/null',
                        GIT_CONFIG_NOSYSTEM='1', GIT_TERMINAL_PROMPT='0', GIT_ALLOW_PROTOCOL='file', PYTHONDONTWRITEBYTECODE='1')
        self.bin = self.root / 'bin'; self.bin.mkdir()
        self.log = self.root / 'mutations.log'
        self.pr = self.root / 'pr.json'
        self.env.update(PATH=str(self.bin) + os.pathsep + self.env['PATH'],
                        WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT=str(self.external),
                        SYNTHETIC_PR=str(self.pr), SYNTHETIC_MUTATIONS=str(self.log))
        gh = self.bin / 'gh'
        gh.write_text('''#!/bin/sh
case "$*" in
  *"--method POST"*|*"pr create"*|*"pr merge"*|*"label create"*|*"issue edit"*) echo mutation >> "$SYNTHETIC_MUTATIONS"; exit 99 ;;
  "repo view"*) echo fixture/repo ;;
  "auth status"*) exit 0 ;;
  "pr view"*) cat "$SYNTHETIC_PR" ;;
  "api"*) echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[],"pageInfo":{"hasNextPage":false}}}}}}' ;;
  *) echo synthetic-read-unavailable >&2; exit 99 ;;
esac
'''); gh.chmod(0o755)
        for name in ('codex', 'claude', 'cursor', 'cursor-agent', 'dsh', 'coderabbit', 'cr', 'curl'):
            path = self.bin / name
            path.write_text('#!/bin/sh\necho unexpected-runtime >> "$SYNTHETIC_MUTATIONS"\nexit 99\n')
            path.chmod(0o755)
        for args in (['git', 'init', '-q', '-b', 'develop'],
                     ['git', 'config', 'user.name', 'Synthetic fixture'],
                     ['git', 'config', 'user.email', 'fixture@example.test'],
                     ['git', 'add', '.ai-dev-workflow.yaml'],
                     ['git', 'commit', '-qm', 'Synthetic shared policy'],
                     ['git', 'switch', '-qc', 'feature/1993-fixture']):
            subprocess.run(args, cwd=self.checkout, env=self.env, check=True, capture_output=True)
        sha = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=self.checkout, env=self.env, text=True).strip()
        origin = self.root / 'synthetic-origin.git'
        subprocess.run(['git', 'clone', '--bare', str(self.checkout), str(origin)], env=self.env, check=True, capture_output=True)
        subprocess.run(['git', 'remote', 'add', 'origin', str(origin)], cwd=self.checkout, env=self.env, check=True, capture_output=True)
        self.pr.write_text(json.dumps({'number': 1993, 'state': 'OPEN', 'baseRefName': 'develop',
                                      'headRefName': 'feature/1993-fixture', 'headRefOid': sha,
                                      'isDraft': False, 'labels': [], 'files': [], 'comments': [], 'statusCheckRollup': []}))
        self.scope = self.root / 'scope.json'; self.scope.write_text('{"groups":{},"items":[],"policy":{}}')
        self.risk = self.root / 'risk.json'; self.risk.write_text('{"pr_number":1993}')
        self.gate = self.root / 'gate.json'; self.gate.write_text('{"pr":{"number":1993,"headRefName":"feature/1993-fixture","baseRefName":"develop"},"policy":{}}')
        self.body = self.root / 'body.md'; self.body.write_text('Synthetic PR body\n')

    def execute(self, row):
        _, name, kind, args = row
        substitutions = {'CHECKOUT': str(self.checkout), 'SHARED': str(self.shared), 'PRIVATE': str(self.private)}
        for key, path in substitutions.items():
            args = args.replace(key, shlex.quote(path))
        if kind == 'entry':
            file = row[3]
            common = ['--repo-root', str(self.checkout)]
            entries = {
                'coderabbit-cli-reviewer.sh': ['1993', 'fixture', 'repo', *common],
                'pr-review-loop.sh': ['1993', '--repo', 'fixture/repo', *common],
                'apply-readiness-labels.sh': ['1993', '--repo', 'fixture/repo'],
                'pr-ci-loop.sh': ['1993', '--repo', 'fixture/repo', *common],
                'item-completion-self-check.sh': ['--issue', '1993', '--branch', 'feature/1993-fixture', '--stage', 'synthetic', '--worktree-path', str(self.checkout), *common, '--pr', '1993', '--expected-base', 'develop', '--require-clean', 'false', '--require-ci-green', 'false', '--require-review-summary', 'true', '--require-review-threads', 'true'],
                'run-epic-policy-recommender.sh': ['--scope', str(self.scope), '--original-command', '/run-item 1993', '--json'],
                'resolve-reviewer-availability.sh': [*common, '--owner', 'fixture', '--repo', 'repo', '--runner-kind', 'codex'],
                'reviewer-preflight.sh': [*common, '--owner', 'fixture', '--repo', 'repo', '--mode', 'pre-dispatch', '--target-base', 'develop', '--remaining-stages', 'on_draft.runner', '--pr-state', 'on_draft.runner=draft'],
                'validate-workflow-config.sh': [*common, '--repo', 'mobile'],
                'component-release-target.sh': [*common, '--repo', 'mobile', '--json'],
                'github-app-token.sh': [*common, '--repo', 'mobile', '--status'],
                'open-product-pr.sh': [*common, '--repo', 'mobile', '--base', 'develop', '--approved-base', 'develop', '--head', 'feature/1993-fixture', '--title', 'Synthetic', '--body-file', str(self.body), '--dry-run'],
                'hub-status.sh': [*common, '--repo', 'mobile'],
                'hub-list-prs.sh': [*common, '--repo', 'mobile'],
                'hub-sync-product-repos.sh': [*common, '--repo', 'mobile'],
                'hub-preflight-product-repos.sh': [*common, '--repo', 'mobile'],
                'discover-workflow-state.sh': [*common, '--repo', 'mobile'],
                'workflow-next-action.sh': [*common, '--branch', 'feature/1993-fixture'],
                'run-epic-scope-resolver.sh': ['--items', '1993', '--json'],
                'post-merge-cleanup.sh': [*common, '--inspect-targets', 'feature/1993-fixture'],
                'run-epic-risk-classifier.sh': [*common, '--input', str(self.risk), '--json'],
                'run-epic-delegated-gate.sh': [*common, '--input', str(self.gate), '--json'],
            }
            command = ['bash', str(self.runtime / file), *entries[file]]
        else:
            source = self.runtime / ('hub-product-repo-lib.sh' if kind == 'hub' else 'workflow-lib.sh')
            script = 'source ' + shlex.quote(str(source)) + '\n'
            if kind not in ('lib', 'hub'):
                dependencies = []
                if kind == 'coderabbit-cli-reviewer.sh' and name == 'rate_limit_policy_from_config':
                    dependencies.append('rate_limit_policy_from_file')
                if kind == 'item-completion-self-check.sh' and name != 'configured_review_platforms':
                    dependencies.append('configured_review_platforms')
                script += '\n'.join(function_text(kind, item) for item in [*dependencies, name]) + '\n'
            script += 'loop_dispatched_base=1\nconfig_file=' + shlex.quote(str(self.shared)) + '\n'
            if name == 'pr_head_config_ready_platforms':
                import base64
                encoded = base64.b64encode(self.shared.read_bytes()).decode()
                script += 'gh() { printf "%s\\n" ' + shlex.quote(encoded) + '; }\n'
            # Conditional invocation deliberately disables implicit errexit safety.
            script += 'if value="$('+name+' '+args+')"; then printf "%s\\n" "$value"; exit 0; else rc=$?; printf "%s\\n" "$value"; exit "$rc"; fi\n'
            command = ['bash', '-c', script]
        return subprocess.run(command, cwd=self.checkout, env=self.env, capture_output=True, text=True, timeout=25)

    def test_L17_schema_validation_failure_preserves_safe_error(self):
        """Valid YAML with an invalid selected-source schema must not mean absence."""
        opaque = 'opaqueSelectedSchemaMaterial1993'
        self.shared.write_text('''mode: workflow_hub
workflow_hub:
  product_repos:
    - name: mobile
      github_repo: fixture/mobile
      ci_policy: none
''')
        self.private.write_text('product_repos: ' + opaque + '\n')
        expected_error = 'ERROR: configuration: field must be a list; key=product_repos\n'
        direct = subprocess.run(
            ['python3', str(self.runtime / 'workflow-config-resolver.py'), 'resolve',
             '--repo-root', str(self.checkout), '--repo', 'mobile', '--json'],
            cwd=self.checkout, env=self.env, capture_output=True, text=True, timeout=25)
        self.assertEqual(direct.returncode, 2)
        self.assertEqual(direct.stdout, '')
        self.assertEqual(direct.stderr, expected_error)
        script = 'source ' + shlex.quote(str(self.runtime / 'workflow-lib.sh')) + '\n'
        # The conditional also proves propagation without relying on errexit.
        script += 'if workflow_merge_ci_policy_into_json \'{"risk":"low"}\' '
        script += shlex.quote(str(self.checkout)) + ' mobile; then exit 0; else exit "$?"; fi\n'
        for shell in dict.fromkeys(('/bin/bash', shutil.which('bash'))):
            with self.subTest(shell=shell):
                failed = subprocess.run([shell, '-c', script], cwd=self.checkout,
                                        env=self.env, capture_output=True, text=True, timeout=25)
                self.assertEqual(failed.returncode, 2)
                self.assertEqual(failed.stdout, '')
                self.assertEqual(failed.stderr, expected_error)
                output = failed.stdout + failed.stderr
                for forbidden in (opaque, str(self.private), str(self.external), str(self.checkout)):
                    self.assertNotIn(forbidden, output)
                self.private.write_text('review:\n  on_draft:\n    runner: []\n')
                restored = subprocess.run([shell, '-c', script], cwd=self.checkout,
                                          env=self.env, capture_output=True, text=True, timeout=25)
                self.assertEqual(restored.returncode, 0)
                self.assertEqual(json.loads(restored.stdout), {'risk': 'low', 'ciPolicy': 'none'})
                self.assertEqual(restored.stderr, '')
                self.assertNotIn(opaque, restored.stdout + restored.stderr)
                self.private.write_text('product_repos: ' + opaque + '\n')
        self.assertFalse(self.log.exists(), 'unexpected external runtime or mutation')

    def suppression_shell(self, command, shell='/bin/bash', extra=''):
        script = 'source ' + shlex.quote(str(self.runtime / 'workflow-lib.sh')) + '\n' + extra
        script += '\nif ' + command + '; then exit 0; else exit "$?"; fi\n'
        return subprocess.run([shell, '-c', script], cwd=self.checkout, env=self.env,
                              capture_output=True, text=True, timeout=30)

    def suppression_assert_metadata(self, failed, expected, opaque):
        self.assertEqual(failed.returncode, 2, failed.stdout + failed.stderr)
        self.assertEqual(failed.stdout, '')
        self.assertEqual(failed.stderr, expected)
        self.assertIn('configuration:', expected)
        for forbidden in (opaque, str(self.private), str(self.external), str(self.checkout), 'Traceback'):
            self.assertNotIn(forbidden, failed.stdout + failed.stderr)
        self.assertFalse(self.log.exists(), 'unexpected provider/transport/mutation')

    def suppression_lookup_case(self, route):
        opaque = 'fabricatedOpaqueSuppression' + route
        shared = self.shared.read_text().replace('github_repo: fixture/mobile', 'github_repo: fixture/mobile\n      ci_policy: none')
        self.shared.write_text(shared)
        invalid = 'product_repos: ' + opaque + '\n'
        if route == 'S02':
            self.shared.write_text(shared.replace('- name: mobile\n      github_repo: fixture/mobile\n      ci_policy: none', '- ' + opaque))
            invalid = 'review:\n  on_draft:\n    runner: []\n'
        self.private.write_text(invalid)
        command = 'list-product-repos' if route == 'S02' else 'resolve'
        args = ['python3', str(self.runtime / 'workflow-config-resolver.py'), command, '--repo-root', str(self.checkout)]
        if command == 'resolve': args += ['--repo', 'mobile']
        direct = subprocess.run(args, env=self.env, capture_output=True, text=True, timeout=20)
        self.assertEqual(direct.returncode, 2)
        expected = direct.stderr
        root = shlex.quote(str(self.checkout))
        call = ('workflow_merge_ci_policy_into_json \'{"github_repo":"fixture/mobile","risk":"low"}\' ' + root
                if route == 'S03' else 'workflow_product_repo_name_for_github_slug ' + root + ' fixture/mobile')
        for shell in dict.fromkeys(('/bin/bash', shutil.which('bash'))):
            with self.subTest(route=route, shell=shell):
                self.private.write_text(invalid)
                if route == 'S02': self.shared.write_text(shared.replace('- name: mobile\n      github_repo: fixture/mobile\n      ci_policy: none', '- ' + opaque))
                failed = self.suppression_shell(call, shell)
                self.suppression_assert_metadata(failed, expected, opaque)
                self.shared.write_text(shared)
                self.private.write_text('review:\n  on_draft:\n    runner: []\n')
                restored = self.suppression_shell(call, shell)
                self.assertEqual(restored.returncode, 0, restored.stderr)
                self.assertEqual(restored.stderr, '')
                if route == 'S03':
                    self.assertEqual(json.loads(restored.stdout), {'github_repo': 'fixture/mobile', 'risk': 'low', 'ciPolicy': 'none'})
                else:
                    self.assertEqual(restored.stdout, 'mobile\n')
                    absent = self.suppression_shell('workflow_product_repo_name_for_github_slug ' + root + ' fixture/not-configured', shell)
                    self.assertEqual((absent.returncode, absent.stdout, absent.stderr), (1, '', ''))

    def test_S01_lookup_context(self):
        self.suppression_lookup_case('S01')

    def test_S02_lookup_list(self):
        self.suppression_lookup_case('S02')

    def test_S03_inferred_merge(self):
        self.suppression_lookup_case('S03')

    def check_consumer(self, row):
        valid_source = '''review:
  on_draft:
    runner: [cursor]
    github: [bugbot]
  on_ready:
    github: [bugbot]
  coderabbit_cli:
    rate_limit_policy: strict
'''
        for variant in ('trailing-error', 'absent-field-error'):
            with self.subTest(id=row[0], variant=variant):
                prefix = valid_source if variant == 'trailing-error' else ''
                self.private.write_text(prefix + 'broken: [fabricatedOpaqueParseValue\n')
                result = self.execute(row)
                output = result.stdout + result.stderr
                self.assertNotEqual(result.returncode, 0, (row, output))
                self.assertRegex(output, r'invalid YAML|source resolution failed|policy-unreadable', (row, output))
                self.assertNotIn('fabricatedOpaqueParseValue', output)
                self.assertNotIn('shared-policy-sentinel', output)
                self.assertFalse(self.log.exists(), (row, self.log.read_text() if self.log.exists() else ''))
        # Restore valid selected bytes, then instrument only the resolver boundary.
        # Every real entry/API must reach a successful real parser invocation;
        # stop immediately afterwards so no external or mutating stage can run.
        self.private.write_text(valid_source + 'valid: true\n')
        resolver = self.runtime / 'workflow-config-resolver.py'
        original = self.runtime / 'synthetic-real-resolver.py'
        shutil.copy2(resolver, original)
        trace = self.root / 'validated.jsonl'
        resolver.write_text('''import importlib.util, json, subprocess, sys
from pathlib import Path
real = Path(__file__).with_name('synthetic-real-resolver.py')
if __name__ == '__main__':
    result = subprocess.run([sys.executable, str(real), *sys.argv[1:]], capture_output=True, text=True)
    with Path('TRACE').open('a') as stream:
        stream.write(json.dumps({'command': sys.argv[1], 'status': result.returncode}) + '\\n')
    print('synthetic validated-source stop' if result.returncode == 0 else result.stderr, file=sys.stderr)
    sys.exit(2)
else:
    spec = importlib.util.spec_from_file_location('synthetic_real_resolver', real)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    globals().update({k: v for k, v in vars(module).items() if not k.startswith('__')})
'''.replace('TRACE', str(trace)))
        self.execute(row)
        self.assertTrue(trace.is_file(), (row, 'valid control did not reach resolver'))
        events = [json.loads(line) for line in trace.read_text().splitlines()]
        self.assertTrue(any(event['status'] == 0 for event in events), (row, events))
        self.assertFalse(self.log.exists(), (row, 'valid control ran a mutation/runtime'))


def named_case(row):
    def test(self):
        self.check_consumer(row)
    test.__doc__ = row[0] + ': ' + row[1]
    return test


for consumer in CASES:
    setattr(PrivateSourceConsumers, 'test_' + consumer[0] + '_' + consumer[1], named_case(consumer))


if __name__ == '__main__':
    unittest.main(verbosity=2)

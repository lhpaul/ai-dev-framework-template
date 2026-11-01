#!/usr/bin/env python3
"""Synthetic regression tests for #2089; no real config, repository or API reads."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / 'scripts/development-workflow'


def function(name, source):
    text = source.read_text()
    start = text.index(name + '() {')
    return text[start:text.index('\n}', start) + 2] + '\n'


class PreludeRegression(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name)
        self.env = dict(os.environ)
        for key in list(self.env):
            if key.startswith(('AI_DEV_WORKFLOW', '_BOUNDED_PRELUDE')):
                del self.env[key]
        self.env['BOUNDED_PRELUDE_TIMEOUT_SECONDS'] = '15'

    def shell(self, text, *args):
        return subprocess.run(['bash', '-c', 'set -euo pipefail\n' + text, '--', *map(str, args)],
                              cwd=self.path, env=self.env, capture_output=True, text=True, timeout=20)

    def test_extractor_rules_and_large_documents(self):
        extract = function('extract_github_issue_number', SCRIPTS / 'workflow-lib.sh')
        cases = [
            ('20260101010101_77-slug', [('a.md', '**Issue**: #00042\n')], '00042'),
            ('77-slug', [('a.md', '**Issue**:\t[#123](url) #999\n')], '123'),
            ('77-slug', [('b.md', '**Issue**: #2\n'), ('a.md', '**Issue**: #1\n')], '1'),
            ('77-slug', [('a.md', ' **Issue**: #1\n**Issue**: #8\n**Issue**: #9\n')], '8'),
            ('20260101010101_77-slug', [('a.md', '**Issue**: 123\n**issue**: #4\n')], '77'),
            ('88-slug', [('a.txt', '**Issue**: #1\n'), ('nested/a.md', '**Issue**: #2\n')], '88'),
            ('no-id', [('a.md', '**Issue**: #3')], ''),  # preserve incomplete-line rule
            ('2026010101010_77-slug', [], ''),
            ('no-id', [('a.md', 'x' * 1000 + '\n')], ''),
            ('no-id', [('a.md', ('ordinary line\n' * 10000) + '**Issue**: [#95](url)\n')], '95'),
        ]
        for i, (slug, docs, expected) in enumerate(cases):
            folder = self.path / str(i) / slug
            folder.mkdir(parents=True)
            for name, contents in docs:
                target = folder / name
                target.parent.mkdir(exist_ok=True)
                target.write_text(contents)
            result = self.shell(extract + 'extract_github_issue_number "$1"', folder)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, expected, slug)

    def test_head_search_argv_cache_and_filtering(self):
        source = SCRIPTS / 'run-epic-scope-resolver.sh'
        code = '\n'.join(function(name, source) for name in (
            'discover_prs_via_head_search', 'discover_prs_via_head_search_uncached',
            'discover_integration_bases_for_issue'))
        mock = self.path / 'gh'
        mock.write_text('''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ['CALL_LOG'], 'a') as log:
    log.write(json.dumps(args) + '\\n')
if args[:2] == ['pr', 'list']:
    print('[]')
elif args[:2] == ['search', 'prs']:
    assert args[2] == '321 in:head'
    assert args[args.index('--repo') + 1] == 'synthetic/repo'
    assert args[args.index('--head') + 1] in [p + '/' for p in ['spec','implementation-plan','feature','fix','refactor','hotfix']]
    if args[args.index('--head') + 1] == 'fix/' and os.environ['HAS_PR'] == '1':
        print('7\\n8')
elif args[:2] == ['pr', 'view']:
    head = 'fix/321-correct' if args[2] == '7' else 'fix/3210-unrelated'
    print(json.dumps(dict(number=int(args[2]), title='Synthetic', state='OPEN', headRefName=head,
                         baseRefName='develop-synthetic', isDraft=True, labels=[], mergedAt=None)))
else:
    sys.exit(99)
''')
        mock.chmod(0o755)
        self.env.update(PATH=str(self.path) + os.pathsep + self.env['PATH'], CALL_LOG=str(self.path / 'calls'))
        for has_pr in ('0', '1'):
            with self.subTest(has_pr=has_pr):
                cache = self.path / ('cache' + has_pr)
                cache.mkdir()
                self.env['HAS_PR'] = has_pr
                (self.path / 'calls').write_text('')
                result = self.shell('tmp_dir="$1"\nrepo=synthetic/repo\nHEAD_REF_TEAM_PREFIX_RE=""\n' + code + '''
first="$(discover_prs_via_head_search 321)"
second="$(discover_prs_via_head_search 321)"
[ "$first" = "$second" ]
discover_integration_bases_for_issue 321 >/dev/null
printf '%s' "$second"
''', cache)
                self.assertEqual(result.returncode, 0, result.stderr)
                data = json.loads(result.stdout)
                self.assertEqual([p['number'] for p in data['open']], [7] if has_pr == '1' else [])
                calls = [json.loads(line) for line in (self.path / 'calls').read_text().splitlines()]
                self.assertEqual(sum(c[:2] == ['search', 'prs'] for c in calls), 6)
                self.assertEqual(sum(c[:2] == ['pr', 'list'] for c in calls), 1)

    def fixture(self, stall=''):
        shutil.copy(SCRIPTS / 'run-bounded-prelude.sh', self.path)
        extract = function('extract_github_issue_number', SCRIPTS / 'workflow-lib.sh')
        (self.path / 'workflow-lib.sh').write_text('''
workflow_effective_config_file() { return 1; }
workflow_template_is_template() { printf true; }
workflow_repo_root() { printf '%s' "$FIXTURE_ROOT"; }
workflow_branch_pr_evidence_single_item() { printf none; }
''' + extract + ('sleep 40\n' if stall == 'configuration' else ''))
        scope = dict(scopeSource='item', resolvedIssueNumber=999, baseBranch='develop',
                     items=[dict(number=999, title='Synthetic', status='In Development', type='Bug')])
        self.env['FIXTURE_ROOT'] = str(self.path)
        self.env['SCOPE_JSON'] = json.dumps(scope)
        resolver = self.path / 'run-item-scope-resolver.sh'
        resolver.write_text('#!/usr/bin/env bash\n' + (
            # Descendant ignores TERM; the supervisor must also send KILL.
            'bash -c \'trap "" TERM; sleep 3; touch "$FIXTURE_ROOT/escaped"\' &\nwait\n'
            if stall == 'scope' else 'printf "%s" "$SCOPE_JSON"\n'))
        resolver.chmod(0o755)
        gate = self.path / 'framework-mode-backlog-type-gate.sh'
        gate.write_text('#!/usr/bin/env bash\nprintf "RESULT=continue\\n"\n')
        gate.chmod(0o755)
        policy = self.path / 'run-epic-policy-recommender.sh'
        policy.write_text('#!/usr/bin/env bash\nprintf \'%s\' \'{"effectivePolicy":{"base":"develop","mayMerge":false,"maxRisk":"medium","delegateReview":true,"mayStartBacklog":true},"fieldSources":{},"requiresConfirmation":true}\'\n')
        policy.chmod(0o755)

    def prelude(self, budget='15'):
        self.env['BOUNDED_PRELUDE_TIMEOUT_SECONDS'] = budget
        return subprocess.run(['bash', str(self.path / 'run-bounded-prelude.sh'), '--original-command',
                               '/run-item 999 fabricated-sensitive-marker', '--issue', '999', '--json'],
                              cwd=self.path, env=self.env, capture_output=True, text=True, timeout=20)

    def test_global_timeout_during_configuration_and_scope(self):
        for stage in ('configuration', 'scope', 'artifacts'):
            with self.subTest(stage=stage):
                self.fixture(stage)
                if stage == 'artifacts':
                    folder = self.path / 'docs/specs/developments/1-synthetic'
                    folder.mkdir(parents=True)
                    with (self.path / 'workflow-lib.sh').open('a') as lib:
                        lib.write('extract_github_issue_number() { while :; do :; done; }\n')
                started = time.monotonic()
                result = self.prelude('1')
                self.assertEqual(result.returncode, 124, result.stderr)
                self.assertLess(time.monotonic() - started, 3)
                self.assertEqual(json.loads(result.stdout)['stage'], stage)
                self.assertNotIn('fabricated-sensitive-marker', result.stdout + result.stderr)
                self.assertNotIn(str(self.path), result.stdout + result.stderr)
                if stage == 'scope':
                    time.sleep(3)
                    self.assertFalse((self.path / 'escaped').exists(), 'descendant survived global timeout')

    def test_many_folders_finish_and_stdout_stays_json(self):
        self.fixture()
        for i in range(40):
            folder = self.path / 'docs/specs/developments' / ('20260101010101_%s-synthetic' % (i + 1))
            folder.mkdir(parents=True)
            (folder / 'a.md').write_text('ordinary synthetic line\n' * 500)
        result = self.prelude()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)['scope']['resolvedIssueNumber'], 999)
        for stage in ('configuration', 'guardrails', 'scope', 'artifacts', 'policy', 'output'):
            self.assertIn('stage=' + stage, result.stderr)
        self.assertNotIn('fabricated-sensitive-marker', result.stderr)

    def test_invalid_budget_is_safe(self):
        self.fixture()
        result = self.prelude('fabricated-sensitive-marker')
        self.assertEqual(result.returncode, 64)
        self.assertNotIn('fabricated-sensitive-marker', result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()

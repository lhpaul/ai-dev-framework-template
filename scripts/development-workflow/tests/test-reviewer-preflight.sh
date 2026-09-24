#!/usr/bin/env bash
# covers: scripts/development-workflow/reviewer-preflight.sh
# covers: scripts/development-workflow/reviewer_preflight_build_input.py scripts/development-workflow/reviewer_preflight_coderabbit.py
# Hermetic git fixtures; gh is faked for the pr-resume mode.
set -euo pipefail
python3 -c 'import yaml' >/dev/null 2>&1 || {
  printf 'ERROR: install PyYAML==6.0.2 in the test python3 environment.\n' >&2
  exit 2
}
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
python3 - "$SCRIPT_DIR/.." <<'PY'
import json, os, pathlib, shutil, subprocess, sys, tempfile

scripts = pathlib.Path(sys.argv[1]).resolve()
helper = scripts / 'reviewer-preflight.sh'
bash = '/bin/bash'
passed = 0


def check(name, condition, detail=''):
    global passed
    if not condition:
        raise AssertionError(f'{name}: {detail}')
    passed += 1
    print(f'PASS: {name}', flush=True)


def run(root, *args, env=None, expected=None):
    # Default to a generous, explicit test-mode budget/cap so a briefly loaded
    # CI/sandbox host does not flake a test that is not itself exercising the
    # timeout path (T-7 supplies its own, deliberately tight, override).
    base_env = {
        'WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE': '1',
        'WORKFLOW_REVIEWER_PREFLIGHT_BUDGET_SECONDS': '45',
        'WORKFLOW_REVIEWER_PREFLIGHT_PER_PLATFORM_CAP_SECONDS': '20',
    }
    full_env = {**os.environ, **base_env, **(env or {})}
    result = subprocess.run(
        [bash, str(helper), '--repo-root', str(root), *args],
        env=full_env, text=True, capture_output=True, timeout=90,
    )
    if expected is not None and result.returncode != expected:
        raise AssertionError(
            f'exit {result.returncode} != {expected}\nargs={args}\nstdout={result.stdout}\nstderr={result.stderr}'
        )
    data = {}
    for line in result.stdout.splitlines():
        if '=' in line:
            key, _, value = line.partition('=')
            data[key] = value
    return result.returncode, data, result.stdout, result.stderr


def git(root, *args, check_call=True):
    return subprocess.run(['git', '-C', str(root), *args], check=check_call, text=True, capture_output=True)


def write_repo(root, shared_yaml, coderabbit_yaml=None):
    root.mkdir(parents=True, exist_ok=True)
    git(root, 'init', '-q')
    git(root, 'checkout', '-q', '-b', 'develop')
    (root / '.ai-dev-workflow.yaml').write_text(shared_yaml)
    if coderabbit_yaml is not None:
        (root / '.coderabbit.yaml').write_text(coderabbit_yaml)
    git(root, 'add', '-A')
    git(root, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'init')
    git(root, 'remote', 'add', 'origin', str(root))
    git(root, 'fetch', '-q', 'origin', 'develop')


coherent_shared = (
    'review:\n'
    '  on_draft:\n'
    '    github:\n'
    '      - coderabbit\n'
    '  on_ready:\n'
    '    github: []\n'
)
coherent_coderabbit = (
    'reviews:\n'
    '  auto_review:\n'
    '    enabled: true\n'
    '    drafts: true\n'
)
disabled_coderabbit = (
    'reviews:\n'
    '  auto_review:\n'
    '    enabled: false\n'
    '    drafts: true\n'
)

with tempfile.TemporaryDirectory(prefix='reviewer-preflight-tests-') as tmp:
    root = pathlib.Path(tmp).resolve()

    # T-1: coherent config passes, exit 0.
    repo1 = root / 'repo1'
    write_repo(repo1, coherent_shared, coherent_coderabbit)
    before = subprocess.check_output(['git', '-C', str(repo1), 'status', '--porcelain'])
    rc, data, out, err = run(
        repo1, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=0,
    )
    after = subprocess.check_output(['git', '-C', str(repo1), 'status', '--porcelain'])
    check('T-1 coherent config passes', data.get('OUTCOME') == 'passed', data)
    check('T-1 side-effect freedom', before == after == b'', (before, after))

    # T-2: automatic review off blocks, exit 1, correct reason.
    repo2 = root / 'repo2'
    write_repo(repo2, coherent_shared, disabled_coderabbit)
    rc, data, out, err = run(
        repo2, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=1,
    )
    check('T-2 review-disabled blocks', data.get('OUTCOME') == 'blocked', data)
    check('T-2 review-disabled reason', data.get('PLATFORM_1_REASONS') == 'review-disabled', data)
    check('T-2 review-disabled surface', data.get('PLATFORM_1_SURFACE') == '.coderabbit.yaml', data)

    # T-3: missing --remaining-stages is prerequisite-failed, exit 2.
    rc, data, out, err = run(repo1, '--mode', 'pre-dispatch', '--target-base', 'develop', expected=2)
    check('T-3 missing remaining-stages is prerequisite-failed', data.get('OUTCOME') == 'prerequisite-failed', data)
    # Protocol 91's named-stop contract needs the specific failed input in
    # the default (non-JSON) report, not only in --json output, to name a
    # concrete unblock action.
    check(
        'T-3 prerequisite-failed report names the specific failed input',
        bool(data.get('PREREQUISITE_DETAIL')),
        data,
    )

    # T-4: explicit empty --remaining-stages is no-review-remaining, exit 0.
    rc, data, out, err = run(
        repo1, '--mode', 'pre-dispatch', '--target-base', 'develop', '--remaining-stages', '', expected=0,
    )
    check('T-4 empty remaining-stages is no-review-remaining', data.get('OUTCOME') == 'no-review-remaining', data)
    check('T-4 no platforms computed', data.get('PLATFORM_COUNT') == '0', data)

    # T-5: branch-resume reads the platform's own config from the branch, not the base.
    repo5 = root / 'repo5'
    write_repo(repo5, coherent_shared, coherent_coderabbit)
    git(repo5, 'checkout', '-q', '-b', 'feature/branch-resume-test')
    (repo5 / '.coderabbit.yaml').write_text(disabled_coderabbit)
    git(repo5, 'add', '-A')
    git(repo5, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'disable on branch')
    rc, data, out, err = run(
        repo5, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', 'feature/branch-resume-test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=1,
    )
    check('T-5 branch-resume reads branch-local config', data.get('OUTCOME') == 'blocked', data)
    check(
        'T-5 branch-resume platform ref names the branch',
        'feature/branch-resume-test' in data.get('CHECKED_PLATFORM_CONFIG_REF', ''),
        data,
    )
    check(
        'T-5 branch-resume shared ref names the base, not the branch',
        'origin/develop' in data.get('CHECKED_SHARED_CONFIG_REF', ''),
        data,
    )

    # T-6: pr-resume distinguishes shared (target base) vs platform (PR head) refs.
    repo6 = root / 'repo6'
    write_repo(repo6, coherent_shared, coherent_coderabbit)
    git(repo6, 'checkout', '-q', '-b', 'feature/pr-resume-test')
    (repo6 / '.coderabbit.yaml').write_text(disabled_coderabbit)
    git(repo6, 'add', '-A')
    git(repo6, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'disable on pr head')
    bins = root / 'bin'
    bins.mkdir(exist_ok=True)
    fake_gh = bins / 'gh'
    fake_gh.write_text(
        '#!/bin/bash\n'
        'if [ "$1" = pr ] && [ "$2" = view ]; then\n'
        '  printf \'{"baseRefName":"develop","headRefName":"feature/pr-resume-test"}\\n\'\n'
        '  exit 0\n'
        'fi\n'
        'exit 1\n'
    )
    fake_gh.chmod(0o755)
    env = {'PATH': f'{bins}:{os.environ.get("PATH", "")}'}
    # gh cannot fetch the PR head from a bare "pull/<n>/head" ref against a
    # plain file:// remote with no PR object; simulate it as an ordinary
    # branch ref instead, which the fetch_ref call still exercises for the
    # base and the shell's read-only ref resolution still exercises for the
    # (faked) PR head branch name reported back by fake gh.
    git(repo6, 'update-ref', 'refs/pull/7/head', 'refs/heads/feature/pr-resume-test')
    rc, data, out, err = run(
        repo6, '--mode', 'pr-resume', '--target-base', 'develop', '--pr', '7',
        '--owner', 'example', '--repo', 'test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env=env, expected=1,
    )
    check('T-6 pr-resume blocks on PR-head config', data.get('OUTCOME') == 'blocked', data)
    check(
        'T-6 pr-resume shared ref names the target base',
        'origin/develop' in data.get('CHECKED_SHARED_CONFIG_REF', ''),
        data,
    )
    check(
        'T-6 pr-resume platform ref names the PR head, not the base',
        'PR #7' in data.get('CHECKED_PLATFORM_CONFIG_REF', '') and 'develop' not in data.get(
            'CHECKED_PLATFORM_CONFIG_REF', ''
        ).split('(')[0],
        data,
    )
    # AC-2: the pr-resume path fetches the PR head into a temporary,
    # invocation-unique ref (never a fixed name — two concurrent invocations
    # on the same PR must not race on the same ref) to read it the same way
    # every other ref is read; that ref must not survive the run — a
    # porcelain diff cannot see it, since refs live outside the working tree
    # the porcelain check covers. Match by prefix, since the invocation-unique
    # suffix is not known in advance.
    ref_listing = git(repo6, 'for-each-ref', 'refs/reviewer-preflight/')
    check(
        'T-6 pr-resume does not leave a temporary PR-head ref behind',
        ref_listing.stdout.strip() == '',
        ref_listing.stdout,
    )

    # T-7: budget timeout degrades to undetermined, not blocked, when nothing
    # else already proved a disagreement — never hangs past the test budget.
    repo7 = root / 'repo7'
    write_repo(repo7, coherent_shared, coherent_coderabbit)
    slow_git = bins / 'git'
    real_git = shutil.which('git')
    slow_git.write_text(
        '#!/bin/bash\n'
        'for arg in "$@"; do case "$arg" in *:.coderabbit.yaml) sleep 5; break;; esac; done\n'
        f'exec {real_git!r} "$@"\n'
    )
    slow_git.chmod(0o755)
    env2 = {
        'PATH': f'{bins}:{os.environ.get("PATH", "")}',
        'WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE': '1',
        'WORKFLOW_REVIEWER_PREFLIGHT_BUDGET_SECONDS': '2',
        'WORKFLOW_REVIEWER_PREFLIGHT_PER_PLATFORM_CAP_SECONDS': '1',
    }
    rc, data, out, err = run(
        repo7, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env=env2, expected=0,
    )
    check('T-7 budget timeout is undetermined not blocked', data.get('OUTCOME') == 'passed-unverified', data)
    check('T-7 budget timeout reason', data.get('PLATFORM_1_REASONS') == 'check-inconclusive', data)

    # T-8: json output mode.
    rc, data, out, err = run(
        repo1, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        '--json', expected=0,
    )
    parsed = json.loads(out)
    check('T-8 json output mode', parsed.get('outcome') == 'passed', parsed)

    # T-9: a shared-config ref that does not resolve at all (never pushed,
    # bad branch name) is not the same as ".ai-dev-workflow.yaml is absent at
    # a ref that does resolve" — treating both alike would let the preflight
    # report a coherent verdict on a shared configuration it never read.
    # fetch_ref's own remote-add-to-self loopback means `origin/<name>` never
    # existing is reachable simply by never having pushed that branch name.
    rc, data, out, err = run(
        repo1, '--mode', 'pre-dispatch', '--target-base', 'nonexistent-target-branch',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=3,
    )
    check('T-9 unresolved shared ref fails closed, not empty-config', 'OUTCOME' not in data, data)
    check(
        'T-9 unresolved shared ref names the ref, not "absent"',
        'nonexistent-target-branch' in err and 'did not resolve' in err,
        err,
    )

    # T-10: branch-resume resolves a branch that exists only as a
    # remote-tracking ref (a resume on another machine or checkout) instead
    # of degrading to check-inconclusive.
    repo10 = root / 'repo10'
    write_repo(repo10, coherent_shared, coherent_coderabbit)
    git(repo10, 'checkout', '-q', '-b', 'feature/remote-only-test')
    (repo10 / '.coderabbit.yaml').write_text(disabled_coderabbit)
    git(repo10, 'add', '-A')
    git(repo10, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'disable on remote-only branch')
    git(repo10, 'fetch', '-q', 'origin', 'feature/remote-only-test')
    git(repo10, 'checkout', '-q', 'develop')
    git(repo10, 'branch', '-D', 'feature/remote-only-test')
    rc, data, out, err = run(
        repo10, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', 'feature/remote-only-test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=1,
    )
    check('T-10 branch-resume resolves a remote-only branch', data.get('OUTCOME') == 'blocked', data)
    check(
        'T-10 branch-resume remote-only platform ref names origin/',
        'origin/feature/remote-only-test' in data.get('CHECKED_PLATFORM_CONFIG_REF', ''),
        data,
    )

    # T-11: branch-resume reads the remote tip, not a stale local checkout,
    # when the two diverge — the local copy still has the coherent config
    # (review enabled) an operator ran the preflight from days ago, but the
    # remote branch has since been pushed with review disabled. Every other
    # fixture in this suite aliases "origin" to its own working directory,
    # which cannot represent genuine divergence (fetching it always syncs to
    # whatever the local branch currently points to); this one needs an
    # actually separate bare remote so the local branch can be reset back to
    # the older commit while the remote-tracking ref still reflects the
    # remote's own, independently newer, history.
    repo11 = root / 'repo11'
    write_repo(repo11, coherent_shared, coherent_coderabbit)
    remote11 = root / 'remote11.git'
    subprocess.run(['git', 'clone', '-q', '--bare', str(repo11), str(remote11)], check=True)
    git(repo11, 'remote', 'set-url', 'origin', str(remote11))
    git(repo11, 'checkout', '-q', '-b', 'feature/stale-local-test')
    stale_sha = git(repo11, 'rev-parse', 'HEAD').stdout.strip()
    git(repo11, 'push', '-q', 'origin', 'feature/stale-local-test')
    (repo11 / '.coderabbit.yaml').write_text(disabled_coderabbit)
    git(repo11, 'add', '-A')
    git(repo11, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'disable on remote push')
    fresh_sha = git(repo11, 'rev-parse', 'HEAD').stdout.strip()
    git(repo11, 'push', '-q', 'origin', 'feature/stale-local-test')
    git(repo11, 'reset', '-q', '--hard', stale_sha)
    git(repo11, 'fetch', '-q', 'origin', 'feature/stale-local-test')
    check(
        'T-11 fixture: local is behind the remote-tracking ref',
        git(repo11, 'rev-parse', 'HEAD').stdout.strip() == stale_sha
        and git(repo11, 'rev-parse', 'refs/remotes/origin/feature/stale-local-test').stdout.strip() == fresh_sha,
        (stale_sha, fresh_sha),
    )
    rc, data, out, err = run(
        repo11, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', 'feature/stale-local-test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=1,
    )
    check(
        'T-11 branch-resume reads the remote tip over a stale local checkout',
        data.get('OUTCOME') == 'blocked',
        data,
    )
    check(
        'T-11 branch-resume stale-local platform ref names origin/',
        'origin/feature/stale-local-test' in data.get('CHECKED_PLATFORM_CONFIG_REF', ''),
        data,
    )

    # T-12: a malformed bucket from an already-completed lifecycle stage
    # must not block a resume that stage no longer reaches — Decision 5's
    # malformed-shared-list stop is scoped to remaining stages, and must not
    # outrun the engine's own fixed prerequisite order (stage-set
    # resolvability and the empty-remaining-stages short-circuit both need
    # to be able to win first).
    malformed_runner_shared = (
        'review:\n'
        '  on_draft:\n'
        '    runner: not-a-list\n'
    )
    repo12 = root / 'repo12'
    write_repo(repo12, malformed_runner_shared, coherent_coderabbit)
    rc, data, out, err = run(
        repo12, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', '', expected=0,
    )
    check(
        'T-12 malformed historical bucket does not block empty remaining-stages',
        data.get('OUTCOME') == 'no-review-remaining',
        data,
    )
    rc, data, out, err = run(
        repo12, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_ready.github', '--pr-state', 'on_ready.github=ready',
        expected=0,
    )
    check(
        'T-12 malformed historical bucket ignored when excluded from remaining stages',
        data.get('OUTCOME') == 'passed',
        data,
    )

print(f'\nPassed: {passed}')
PY

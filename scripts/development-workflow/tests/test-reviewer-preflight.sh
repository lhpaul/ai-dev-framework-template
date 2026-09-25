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
    # The base-branch refresh (fetch_ref) now fails closed before ever
    # reaching read_ref_file for a target-base that does not exist on the
    # remote at all — an earlier, equally valid "fails closed, names the
    # ref" failure than read_ref_file's own "did not resolve" message.
    check(
        'T-9 unresolved shared ref names the ref, not "absent"',
        'nonexistent-target-branch' in err and 'cannot refresh' in err,
        err,
    )

    # T-10: branch-resume resolves a branch that exists only as a
    # remote-tracking ref (a resume on another machine or checkout) instead
    # of degrading to check-inconclusive. Needs an actually separate bare
    # remote (like T-11/T-13/T-14 below): a self-referencing "origin" would
    # have the branch-resume path's own re-fetch of "$branch" (added later
    # in this suite) observe the branch as absent from the "remote" too,
    # once the local-only copy is deleted — the same self-reference
    # limitation those later tests' comments describe.
    repo10 = root / 'repo10'
    write_repo(repo10, coherent_shared, coherent_coderabbit)
    remote10 = root / 'remote10.git'
    subprocess.run(['git', 'clone', '-q', '--bare', str(repo10), str(remote10)], check=True)
    git(repo10, 'remote', 'set-url', 'origin', str(remote10))
    git(repo10, 'checkout', '-q', '-b', 'feature/remote-only-test')
    (repo10 / '.coderabbit.yaml').write_text(disabled_coderabbit)
    git(repo10, 'add', '-A')
    git(repo10, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'disable on remote-only branch')
    git(repo10, 'push', '-q', 'origin', 'feature/remote-only-test')
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
    # An unrecognized --remaining-stages token must let the engine's own
    # stage-set validation win (prerequisite-failed, exit 2), not have this
    # module's malformed-bucket screen retain a same-repo malformed bucket
    # and preempt that with a tooling failure (exit 3) instead.
    rc, data, out, err = run(
        repo12, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.runner,not-a-real-bucket', '--pr-state', 'on_draft.runner=draft,not-a-real-bucket=draft',
        expected=2,
    )
    check(
        'T-12 invalid remaining-stages token yields prerequisite-failed, not tooling failure',
        data.get('OUTCOME') == 'prerequisite-failed',
        data,
    )

    # T-13: branch-resume reads a genuinely local-ahead branch (unpushed
    # work), the mirror case of T-11 — the earlier stale-local fix must not
    # overcorrect into unconditionally preferring the remote when the local
    # checkout is what will actually become the PR once pushed.
    repo13 = root / 'repo13'
    write_repo(repo13, coherent_shared, coherent_coderabbit)
    remote13 = root / 'remote13.git'
    subprocess.run(['git', 'clone', '-q', '--bare', str(repo13), str(remote13)], check=True)
    git(repo13, 'remote', 'set-url', 'origin', str(remote13))
    git(repo13, 'checkout', '-q', '-b', 'feature/local-ahead-test')
    git(repo13, 'push', '-q', 'origin', 'feature/local-ahead-test')
    git(repo13, 'fetch', '-q', 'origin', 'feature/local-ahead-test')
    (repo13 / '.coderabbit.yaml').write_text(disabled_coderabbit)
    git(repo13, 'add', '-A')
    git(repo13, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'disable, not yet pushed')
    check(
        'T-13 fixture: local is ahead of the remote-tracking ref',
        git(repo13, 'rev-parse', 'HEAD').stdout.strip()
        != git(repo13, 'rev-parse', 'refs/remotes/origin/feature/local-ahead-test').stdout.strip(),
        None,
    )
    rc, data, out, err = run(
        repo13, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', 'feature/local-ahead-test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=1,
    )
    check(
        'T-13 branch-resume reads the local-ahead branch over a stale remote',
        data.get('OUTCOME') == 'blocked',
        data,
    )
    check(
        'T-13 branch-resume local-ahead platform ref does not name origin/',
        data.get('CHECKED_PLATFORM_CONFIG_REF', '').startswith('feature/local-ahead-test:'),
        data,
    )

    # T-14: branch-resume fails closed on genuine divergence — neither copy
    # is an ancestor of the other, so there is no safe "ahead" answer.
    repo14 = root / 'repo14'
    write_repo(repo14, coherent_shared, coherent_coderabbit)
    remote14 = root / 'remote14.git'
    subprocess.run(['git', 'clone', '-q', '--bare', str(repo14), str(remote14)], check=True)
    git(repo14, 'remote', 'set-url', 'origin', str(remote14))
    git(repo14, 'checkout', '-q', '-b', 'feature/diverged-test')
    base_sha = git(repo14, 'rev-parse', 'HEAD').stdout.strip()
    (repo14 / '.coderabbit.yaml').write_text(disabled_coderabbit)
    git(repo14, 'add', '-A')
    git(repo14, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'remote-side change')
    git(repo14, 'push', '-q', 'origin', 'feature/diverged-test')
    git(repo14, 'reset', '-q', '--hard', base_sha)
    (repo14 / 'other-file.txt').write_text('local-side change\n')
    git(repo14, 'add', '-A')
    git(repo14, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'local-side change')
    git(repo14, 'fetch', '-q', 'origin', 'feature/diverged-test')
    rc, data, out, err = run(
        repo14, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', 'feature/diverged-test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=3,
    )
    check('T-14 branch-resume fails closed on true divergence', 'OUTCOME' not in data, data)
    check('T-14 branch-resume divergence message names the branch', 'diverged' in err, err)

    # T-15: a base-branch refresh that fails while a stale origin/<base>
    # already exists (from an earlier successful fetch) must not silently
    # read that stale copy as current — the base-branch refresh itself must
    # fail closed, the same as pr-resume's own equivalent refresh already
    # does. A `git` wrapper fails only the `fetch` subcommand so the
    # earlier `write_repo` setup (which already fetched origin/develop once
    # successfully) leaves a real, pre-existing stale ref behind.
    repo15_bins = root / 'repo15-bin'
    repo15_bins.mkdir(exist_ok=True)
    real_git15 = shutil.which('git')
    failing_git = repo15_bins / 'git'
    failing_git.write_text(
        '#!/bin/bash\n'
        # reviewer-preflight.sh invokes fetch as `git -C <root> fetch ...`,
        # so "fetch" is not necessarily $1 — scan every argument.
        'for arg in "$@"; do if [ "$arg" = fetch ]; then echo "fatal: simulated fetch failure" >&2; exit 1; fi; done\n'
        f'exec {real_git15!r} "$@"\n'
    )
    failing_git.chmod(0o755)
    rc, data, out, err = run(
        repo1, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={'PATH': f'{repo15_bins}:{os.environ.get("PATH", "")}'},
        expected=3,
    )
    check('T-15 fetch failure with a pre-existing stale ref fails closed', 'OUTCOME' not in data, data)
    check(
        'T-15 fetch failure message names the base branch',
        'develop' in err and 'cannot refresh' in err,
        err,
    )

    # T-16: --target-base / --branch reach `git fetch origin "<value>"` as a
    # bare refspec argument, not merely a branch name — reject refspec
    # syntax (a "<src>:<dst>" separator, or a leading '+' force prefix)
    # before it ever reaches git, so this nominally read-only gate cannot be
    # made to create or overwrite an arbitrary local ref.
    # --target-base routes through the documented prerequisite-failed
    # outcome (exit 2, PREREQUISITE_DETAIL) like every other malformed-
    # target-base case the engine itself raises, not a bare tooling failure
    # — validation still happens before git ever sees the value.
    injected_ref = 'refs/heads/injected-by-preflight'
    rc, data, out, err = run(
        repo1, '--mode', 'pre-dispatch', '--target-base', f'develop:{injected_ref}',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=2,
    )
    check('T-16 refspec-syntax --target-base is rejected', data.get('OUTCOME') == 'prerequisite-failed', data)
    check(
        'T-16 rejection message names --target-base',
        '--target-base' in data.get('PREREQUISITE_DETAIL', ''),
        data,
    )
    injected_check = git(repo1, 'show-ref', '--verify', '--quiet', injected_ref, check_call=False)
    check('T-16 refspec-syntax --target-base never creates the injected ref', injected_check.returncode != 0, injected_check)
    rc, data, out, err = run(
        repo1, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', '+develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=3,
    )
    check('T-16 force-prefixed --branch is rejected', 'OUTCOME' not in data, data)
    check('T-16 rejection message names --branch', '--branch' in err, err)

    # T-17: branch-resume distinguishes a branch that genuinely does not
    # exist on the remote (T-10's case — safe to degrade to the local-only
    # copy) from an operational fetch failure (network/auth/timeout) with a
    # branch that *does* exist remotely — the latter must fail closed, not
    # silently read a stale cached origin/<branch> as current.
    repo17 = root / 'repo17'
    write_repo(repo17, coherent_shared, coherent_coderabbit)
    git(repo17, 'checkout', '-q', '-b', 'feature/fetch-failure-test')
    git(repo17, 'fetch', '-q', 'origin', 'feature/fetch-failure-test')
    repo17_bins = root / 'repo17-bin'
    repo17_bins.mkdir(exist_ok=True)
    real_git17 = shutil.which('git')
    failing_git17 = repo17_bins / 'git'
    failing_git17.write_text(
        '#!/bin/bash\n'
        # Only fail the branch fetch (not the base-branch fetch, which runs
        # first in branch-resume and must still succeed for this case to
        # isolate the branch-fetch failure specifically).
        'has_fetch=0; has_branch=0\n'
        'for arg in "$@"; do\n'
        '  [ "$arg" = fetch ] && has_fetch=1\n'
        '  [ "$arg" = feature/fetch-failure-test ] && has_branch=1\n'
        'done\n'
        'if [ "$has_fetch" = 1 ] && [ "$has_branch" = 1 ]; then echo "fatal: simulated network failure" >&2; exit 1; fi\n'
        f'exec {real_git17!r} "$@"\n'
    )
    failing_git17.chmod(0o755)
    rc, data, out, err = run(
        repo17, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', 'feature/fetch-failure-test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={'PATH': f'{repo17_bins}:{os.environ.get("PATH", "")}'},
        expected=3,
    )
    check('T-17 operational branch-fetch failure fails closed', 'OUTCOME' not in data, data)
    check(
        'T-17 operational branch-fetch failure message names the branch',
        'feature/fetch-failure-test' in err and 'cannot refresh' in err,
        err,
    )

    # T-18: the final subprocess steps' bound floor keeps the worst-case
    # total wall clock close to PREFLIGHT_BUDGET_SECONDS, not the much
    # larger fixed-cap-per-step overrun a naive fixed bound would allow.
    rc, data, out, err = run(
        repo1, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={
            'WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE': '1',
            'WORKFLOW_REVIEWER_PREFLIGHT_BUDGET_SECONDS': '1',
            'WORKFLOW_REVIEWER_PREFLIGHT_PER_PLATFORM_CAP_SECONDS': '4',
        },
        expected=0,
    )
    elapsed = float(data.get('ELAPSED_SECONDS', '999'))
    check(
        'T-18 bound floor keeps total elapsed close to the budget, not 2x the per-step cap',
        elapsed <= 4.0,
        data,
    )

    # T-19: --json mode also routes a malformed --target-base through the
    # structured prerequisite-failed JSON shape, not bare stderr text.
    rc, data, out, err = run(
        repo1, '--mode', 'pre-dispatch', '--target-base', 'develop:refs/heads/injected-json',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        '--json', expected=2,
    )
    parsed = json.loads(out)
    check('T-19 json prerequisite-failed for malformed target-base', parsed.get('outcome') == 'prerequisite-failed', parsed)
    check('T-19 json prerequisite_detail names --target-base', '--target-base' in parsed.get('prerequisite_detail', ''), parsed)

    # T-20: a leading-dash --target-base is not merely an invalid ref name —
    # git parses it as an option to `git fetch` regardless of its position
    # after "origin". Prove the confirmed exploit ("--upload-pack=<path>"
    # runs an arbitrary repo-root program during fetch) never executes: a
    # marker file the "evil" program would create must not appear.
    marker = root / 'evil-ran.marker'
    evil = repo1 / 'evil'
    evil.write_text(f'#!/bin/bash\ntouch {str(marker)!r}\n')
    evil.chmod(0o755)
    rc, data, out, err = run(
        repo1, '--mode', 'pre-dispatch', '--target-base', '--upload-pack=./evil',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=2,
    )
    evil.unlink()
    check('T-20 leading-dash --target-base is rejected as prerequisite-failed', data.get('OUTCOME') == 'prerequisite-failed', data)
    check('T-20 leading-dash --target-base never executes the option payload', not marker.exists(), marker)

    # T-21: an empty --target-base (Protocol 91 invoking with an unresolved
    # BASE_BRANCH) routes through the same documented prerequisite-failed
    # shape, not a bare tooling failure.
    rc, data, out, err = run(
        repo1, '--mode', 'pre-dispatch', '--target-base', '',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=2,
    )
    check('T-21 empty --target-base is prerequisite-failed', data.get('OUTCOME') == 'prerequisite-failed', data)
    check('T-21 empty --target-base detail names --target-base', '--target-base' in data.get('PREREQUISITE_DETAIL', ''), data)

    # T-22: pr-resume's baseRefName (gh-reported, not CLI input) gets the
    # same option/refspec-injection validation as --target-base — a PR
    # whose base is a leading-dash value must not reach `fetch_ref`
    # unvalidated. Reuses T-6's fake-gh pattern with a malicious base.
    repo22 = root / 'repo22'
    write_repo(repo22, coherent_shared, coherent_coderabbit)
    marker22 = root / 'evil22-ran.marker'
    evil22 = repo22 / 'evil'
    evil22.write_text(f'#!/bin/bash\ntouch {str(marker22)!r}\n')
    evil22.chmod(0o755)
    bins22 = root / 'bin22'
    bins22.mkdir(exist_ok=True)
    fake_gh22 = bins22 / 'gh'
    fake_gh22.write_text(
        '#!/bin/bash\n'
        'if [ "$1" = pr ] && [ "$2" = view ]; then\n'
        '  printf \'{"baseRefName":"--upload-pack=./evil","headRefName":"feature/x"}\\n\'\n'
        '  exit 0\n'
        'fi\n'
        'exit 1\n'
    )
    fake_gh22.chmod(0o755)
    rc, data, out, err = run(
        repo22, '--mode', 'pr-resume', '--target-base', 'develop', '--pr', '99', '--owner', 'example', '--repo', 'test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={'PATH': f'{bins22}:{os.environ.get("PATH", "")}'},
        expected=2,
    )
    evil22.unlink()
    check('T-22 malicious PR base is rejected as prerequisite-failed', data.get('OUTCOME') == 'prerequisite-failed', data)
    check('T-22 malicious PR base never executes the option payload', not marker22.exists(), marker22)

    # T-23: a duplicate --remaining-stages token must let the engine's own
    # duplicate-stage prerequisite-failed win, not a same-repo malformed
    # bucket screened as still "in scope" by this predicate.
    rc, data, out, err = run(
        repo12, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.runner,on_draft.runner', '--pr-state', 'on_draft.runner=draft',
        expected=2,
    )
    check(
        'T-23 duplicate remaining-stages token yields prerequisite-failed, not tooling failure',
        data.get('OUTCOME') == 'prerequisite-failed',
        data,
    )

    # T-24: a `timeout` binary that is not GNU coreutils (e.g. BusyBox,
    # which has no --kill-after / --version does not print "GNU coreutils")
    # must not break every bounded call — the script must detect this and
    # fall back to its manual owned-process launcher, still reaching a
    # normal outcome instead of failing every read.
    bins24 = root / 'bin24'
    bins24.mkdir(exist_ok=True)
    fake_timeout = bins24 / 'timeout'
    fake_timeout.write_text(
        '#!/bin/bash\n'
        'if [ "$1" = --version ]; then printf "busybox timeout 1.0\\n"; exit 0; fi\n'
        'echo "timeout: unrecognized option" >&2\n'
        'exit 125\n'
    )
    fake_timeout.chmod(0o755)
    rc, data, out, err = run(
        repo1, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={'PATH': f'{bins24}:{os.environ.get("PATH", "")}'},
        expected=0,
    )
    check('T-24 non-GNU timeout falls back to the manual launcher', data.get('OUTCOME') == 'passed', data)

    # T-25: a branch deleted *on the remote by someone/something else* (not
    # via this checkout's own `git push --delete`, which git itself
    # proactively removes the matching local tracking ref for — that would
    # not reproduce the bug) must not be read from the now-stale cached
    # refs/remotes/origin/<branch> this suite's own re-fetch (added for
    # T-11/T-13) would otherwise leave untouched — `git fetch` does not
    # prune on its own. Delete the ref directly inside the bare remote to
    # simulate that. The stale cache holds a coherent (enabled) config; if
    # it were read, this would wrongly pass instead of degrading.
    repo25 = root / 'repo25'
    write_repo(repo25, coherent_shared, coherent_coderabbit)
    remote25 = root / 'remote25.git'
    subprocess.run(['git', 'clone', '-q', '--bare', str(repo25), str(remote25)], check=True)
    git(repo25, 'remote', 'set-url', 'origin', str(remote25))
    git(repo25, 'checkout', '-q', '-b', 'feature/deleted-remote-test')
    git(repo25, 'push', '-q', 'origin', 'feature/deleted-remote-test')
    git(repo25, 'fetch', '-q', 'origin', 'feature/deleted-remote-test')
    check(
        'T-25 fixture: stale cache holds the coherent (enabled) config before deletion',
        git(repo25, 'show', 'refs/remotes/origin/feature/deleted-remote-test:.coderabbit.yaml').stdout == coherent_coderabbit,
        None,
    )
    subprocess.run(['git', 'update-ref', '-d', 'refs/heads/feature/deleted-remote-test'], cwd=remote25, check=True)
    git(repo25, 'checkout', '-q', 'develop')
    git(repo25, 'branch', '-D', 'feature/deleted-remote-test')
    check(
        'T-25 fixture: local tracking ref is still stale (not auto-pruned)',
        git(repo25, 'rev-parse', '--verify', '--quiet', 'refs/remotes/origin/feature/deleted-remote-test', check_call=False).returncode == 0,
        None,
    )
    rc, data, out, err = run(
        repo25, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', 'feature/deleted-remote-test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=0,
    )
    check(
        'T-25 deleted-remote branch does not read the stale cached config as current',
        data.get('OUTCOME') != 'passed' or data.get('PLATFORM_1_VERDICT') != 'operable',
        data,
    )
    check(
        'T-25 stale cache ref is discarded, not named as the checked ref',
        'origin/feature/deleted-remote-test' not in data.get('CHECKED_PLATFORM_CONFIG_REF', ''),
        data,
    )

print(f'\nPassed: {passed}')
PY

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
import json, os, pathlib, shutil, subprocess, sys, tempfile, time

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
    pr6_head_sha = git(repo6, 'rev-parse', 'HEAD').stdout.strip()
    git(repo6, 'checkout', '-q', 'develop')
    bins = root / 'bin'
    bins.mkdir(exist_ok=True)
    fake_gh = bins / 'gh'
    # #1561 round-26: pr-resume reads the PR head directly by gh's own
    # reported headRefOid (no fetch, no temporary ref) — report the real
    # local commit SHA here so the read_ref_file call this exercises finds
    # the object already present, the same way GitHub's own headRefOid
    # would be present locally in the common case (an already-checked-out
    # or already-fetched PR branch).
    fake_gh.write_text(
        '#!/bin/bash\n'
        'if [ "$1" = pr ] && [ "$2" = view ]; then\n'
        f'  printf \'{{"baseRefName":"develop","headRefName":"feature/pr-resume-test","headRefOid":"{pr6_head_sha}"}}\\n\'\n'
        '  exit 0\n'
        'fi\n'
        'exit 1\n'
    )
    fake_gh.chmod(0o755)
    env = {'PATH': f'{bins}:{os.environ.get("PATH", "")}'}
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
    # #1561 round-26: pr-resume no longer fetches the PR head into any
    # temporary ref at all (it reads gh's own reported headRefOid directly)
    # — confirm no such ref, or any other ref under refs/reviewer-preflight/,
    # was ever created.
    ref_listing = git(repo6, 'for-each-ref', 'refs/reviewer-preflight/')
    check(
        'T-6 pr-resume creates no temporary ref (round-26 read-only redesign)',
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

    # T-9 (#1561 round-26 finding): a --target-base that is syntactically
    # valid but confirmed absent on the remote (never pushed, bad branch
    # name) is a run-INPUT problem — the base this run needs to read does
    # not currently exist — not a tooling outage, so it must classify as
    # OUTCOME=prerequisite-failed (exit 2) like every other malformed/
    # unresolved --target-base case, not an unstructured tooling failure
    # (exit 3). resolve_remote_sha's own `git ls-remote --exit-code`
    # distinguishes "confirmed absent" (rc=2, mapped to prerequisite-failed)
    # from any other operational query failure (mapped to a tooling
    # failure, T-15 below).
    rc, data, out, err = run(
        repo1, '--mode', 'pre-dispatch', '--target-base', 'nonexistent-target-branch',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=2,
    )
    check('T-9 confirmed-absent target base is prerequisite-failed, not a tooling failure', data.get('OUTCOME') == 'prerequisite-failed', data)
    check(
        'T-9 prerequisite_detail names --target-base and the branch',
        '--target-base' in data.get('PREREQUISITE_DETAIL', '') and 'nonexistent-target-branch' in data.get('PREREQUISITE_DETAIL', ''),
        data,
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

    # T-15 (#1561 round-26): an operational `git ls-remote` failure (network,
    # auth — anything other than the documented --exit-code=2 "no such ref"
    # signal resolve_remote_sha treats as prerequisite-failed, T-9 above)
    # must fail closed as a tooling failure, not be silently swallowed or
    # misreported as a run-input problem.
    repo15_bins = root / 'repo15-bin'
    repo15_bins.mkdir(exist_ok=True)
    real_git15 = shutil.which('git')
    failing_git = repo15_bins / 'git'
    failing_git.write_text(
        '#!/bin/bash\n'
        # reviewer-preflight.sh invokes ls-remote as `git -C <root>
        # ls-remote ...`, so "ls-remote" is not necessarily $1 — scan every
        # argument. Exit 128 (git's own generic fatal-error code), not the
        # --exit-code=2 "no matching refs" signal this must stay distinct
        # from.
        'for arg in "$@"; do if [ "$arg" = ls-remote ]; then echo "fatal: simulated ls-remote failure" >&2; exit 128; fi; done\n'
        f'exec {real_git15!r} "$@"\n'
    )
    failing_git.chmod(0o755)
    rc, data, out, err = run(
        repo1, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={'PATH': f'{repo15_bins}:{os.environ.get("PATH", "")}'},
        expected=3,
    )
    check('T-15 operational ls-remote failure fails closed as a tooling failure', 'OUTCOME' not in data, data)
    check(
        'T-15 ls-remote failure message names the base branch',
        'develop' in err and 'cannot resolve' in err,
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

    # T-17 (#1561 round-26): branch-resume distinguishes a branch that
    # genuinely does not exist on the remote (T-10's case — safe to degrade
    # to the local-only copy, resolve_remote_sha's rc=1 via --exit-code=2)
    # from an operational `git ls-remote` failure (network/auth/timeout,
    # any other exit code) with that branch — the latter must fail closed,
    # not be silently misread as "branch absent."
    repo17 = root / 'repo17'
    write_repo(repo17, coherent_shared, coherent_coderabbit)
    git(repo17, 'checkout', '-q', '-b', 'feature/fetch-failure-test')
    repo17_bins = root / 'repo17-bin'
    repo17_bins.mkdir(exist_ok=True)
    real_git17 = shutil.which('git')
    failing_git17 = repo17_bins / 'git'
    failing_git17.write_text(
        '#!/bin/bash\n'
        # Only fail the branch's own ls-remote query (not the base-branch
        # one, which runs first in branch-resume and must still succeed for
        # this case to isolate the branch query failure specifically).
        'has_lsremote=0; has_branch=0\n'
        'for arg in "$@"; do\n'
        '  [ "$arg" = ls-remote ] && has_lsremote=1\n'
        '  case "$arg" in *feature/fetch-failure-test*) has_branch=1;; esac\n'
        'done\n'
        'if [ "$has_lsremote" = 1 ] && [ "$has_branch" = 1 ]; then echo "fatal: simulated network failure" >&2; exit 128; fi\n'
        f'exec {real_git17!r} "$@"\n'
    )
    failing_git17.chmod(0o755)
    rc, data, out, err = run(
        repo17, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', 'feature/fetch-failure-test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={'PATH': f'{repo17_bins}:{os.environ.get("PATH", "")}'},
        expected=3,
    )
    check('T-17 operational branch ls-remote failure fails closed', 'OUTCOME' not in data, data)
    check(
        'T-17 operational branch ls-remote failure message names the branch',
        'feature/fetch-failure-test' in err and 'cannot query the remote' in err,
        err,
    )

    # T-18: the final subprocess steps' bound floor keeps the worst-case
    # total wall clock close to PREFLIGHT_BUDGET_SECONDS, not the much
    # larger fixed-cap-per-step overrun a naive fixed bound would allow.
    # A tiny *total* budget (constraining all setup work, not just the
    # phase under test) previously made this flake on a loaded host: the
    # base fetch and config resolvers are real (if normally fast) bounded
    # work too, and could legitimately time out before ever reaching the
    # final steps this case exists to test. Reuse T-7's slow-git-on-
    # .coderabbit.yaml trick (a real, isolated, deliberate late delay) to
    # consume the budget instead, giving normal setup a comfortable total.
    repo18 = root / 'repo18'
    write_repo(repo18, coherent_shared, coherent_coderabbit)
    bins18 = root / 'bin18'
    bins18.mkdir(exist_ok=True)
    real_git18 = shutil.which('git')
    slow_git18 = bins18 / 'git'
    slow_git18.write_text(
        '#!/bin/bash\n'
        'for arg in "$@"; do case "$arg" in *:.coderabbit.yaml) sleep 5; break;; esac; done\n'
        f'exec {real_git18!r} "$@"\n'
    )
    slow_git18.chmod(0o755)
    rc, data, out, err = run(
        repo18, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={
            'PATH': f'{bins18}:{os.environ.get("PATH", "")}',
            'WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE': '1',
            'WORKFLOW_REVIEWER_PREFLIGHT_BUDGET_SECONDS': '3',
            'WORKFLOW_REVIEWER_PREFLIGHT_PER_PLATFORM_CAP_SECONDS': '1',
        },
        expected=0,
    )
    elapsed = float(data.get('ELAPSED_SECONDS', '999'))
    check(
        'T-18 bound floor keeps total elapsed close to the budget, not 2x the per-step cap',
        elapsed <= 6.0,
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
        '  printf \'{"baseRefName":"--upload-pack=./evil","headRefName":"feature/x","headRefOid":"0000000000000000000000000000000000000000"}\\n\'\n'
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
    # This fixture deletes the branch both on the live remote AND locally
    # (a genuine "neither copy exists anywhere" state, not merely a stale
    # local cache — the round-26 redesign already eliminated the
    # refs/remotes/origin/* caching concern this test originally targeted;
    # see T-26 below). The bounded-Codex-pass "reject branch-resume when
    # neither branch copy exists" fix now correctly fails closed here
    # rather than silently degrading to Undetermined/check-inconclusive
    # and potentially still exiting 0 — never re-reads the stale cached
    # (coherent/enabled) config as current either way.
    rc, data, out, err = run(
        repo25, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', 'feature/deleted-remote-test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=3,
    )
    check(
        'T-25 deleted-remote-and-local branch fails closed, not OUTCOME=passed on the stale cached config',
        'OUTCOME' not in data,
        data,
    )
    check(
        'T-25 failure message names the branch and that it resolves neither locally nor on the remote',
        'feature/deleted-remote-test' in err and 'neither locally nor on the remote' in err,
        err,
    )

    # T-26 (#1561 round-26 redesign): the whole "undeletable stale ref"
    # vulnerability class T-26 used to guard against no longer exists — the
    # round-26 read-only redesign never writes refs/remotes/origin/<branch>
    # at all (git ls-remote resolves the live remote tip directly, git
    # show reads it by SHA), so there is nothing for this script to
    # discard or fail to discard. In its place, prove the stronger
    # guarantee that redesign provides directly: a stale local
    # refs/remotes/origin/<branch> left over from some unrelated, earlier,
    # real `git fetch` (a human, CI, or another tool — not this script) is
    # never consulted and never modified, even though it exists and even
    # though its content actively disagrees with the live remote.
    repo26 = root / 'repo26'
    write_repo(repo26, coherent_shared, coherent_coderabbit)
    remote26 = root / 'remote26.git'
    subprocess.run(['git', 'clone', '-q', '--bare', str(repo26), str(remote26)], check=True)
    git(repo26, 'remote', 'set-url', 'origin', str(remote26))
    git(repo26, 'checkout', '-q', '-b', 'feature/stale-cache-untouched-test')
    (repo26 / '.coderabbit.yaml').write_text(disabled_coderabbit)
    git(repo26, 'add', '-A')
    git(repo26, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'disabled at first push')
    git(repo26, 'push', '-q', 'origin', 'feature/stale-cache-untouched-test')
    git(repo26, 'fetch', '-q', 'origin', 'feature/stale-cache-untouched-test')
    stale_ref_sha_before = git(repo26, 'rev-parse', 'refs/remotes/origin/feature/stale-cache-untouched-test').stdout.strip()
    # Now push a genuinely different (enabled) commit to the remote without
    # ever re-fetching locally — refs/remotes/origin/... stays exactly as
    # stale as it would after any real, unrelated earlier fetch.
    (repo26 / '.coderabbit.yaml').write_text(coherent_coderabbit)
    git(repo26, 'add', '-A')
    git(repo26, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'enabled on the remote tip')
    git(repo26, 'push', '-q', 'origin', 'feature/stale-cache-untouched-test')
    git(repo26, 'checkout', '-q', 'develop')
    git(repo26, 'branch', '-D', 'feature/stale-cache-untouched-test')
    # `git push` above updates its own local remote-tracking ref as a
    # normal side effect (unrelated to this script) — force it back to the
    # stale sha so the fixture actually represents "a stale local cache
    # from some earlier, unrelated fetch," independent of that side effect.
    git(repo26, 'update-ref', 'refs/remotes/origin/feature/stale-cache-untouched-test', stale_ref_sha_before)
    rc, data, out, err = run(
        repo26, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', 'feature/stale-cache-untouched-test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=0,
    )
    check(
        'T-26 reads the live remote tip (enabled), not the stale local cache (disabled)',
        data.get('OUTCOME') == 'passed',
        data,
    )
    stale_ref_sha_after = git(repo26, 'rev-parse', 'refs/remotes/origin/feature/stale-cache-untouched-test').stdout.strip()
    check(
        'T-26 the stale local cache ref itself is never modified',
        stale_ref_sha_after == stale_ref_sha_before,
        f'before={stale_ref_sha_before} after={stale_ref_sha_after}',
    )

    # T-27: the report-rendering rewrite (one bounded jq pass instead of
    # ~9 per platform) must still render every platform row correctly,
    # including an unsupported value (which still gets its own row) mixed
    # with an operable one — proving field-to-row alignment survives the
    # single-pass NUL-delimited parse.
    repo27 = root / 'repo27'
    write_repo(
        repo27,
        (
            'review:\n'
            '  on_draft:\n'
            '    github:\n'
            '      - coderabbit\n'
            '      - not-a-real-reviewer\n'
        ),
        coherent_coderabbit,
    )
    rc, data, out, err = run(
        repo27, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=1,
    )
    check('T-27 multi-platform report renders both rows', data.get('PLATFORM_COUNT') == '2', data)
    names = {data.get('PLATFORM_1_NAME'), data.get('PLATFORM_2_NAME')}
    check('T-27 both platform names appear', names == {'coderabbit', 'not-a-real-reviewer'}, data)
    for n in ('1', '2'):
        name = data.get(f'PLATFORM_{n}_NAME')
        verdict = data.get(f'PLATFORM_{n}_VERDICT')
        expected_verdict = 'operable' if name == 'coderabbit' else 'not-operable'
        check(f'T-27 platform {n} ({name}) verdict aligns with its own row', verdict == expected_verdict, data)

    # T-28: --pr reaches `gh pr view "$pr" ...` as a bare argument gh
    # itself parses — a leading-dash value must be rejected before it
    # could be interpreted as a gh CLI flag instead of a PR number.
    rc, data, out, err = run(
        repo1, '--mode', 'pr-resume', '--target-base', 'develop', '--pr', '--help',
        '--owner', 'example', '--repo', 'test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=3,
    )
    check('T-28 non-numeric --pr is rejected', 'OUTCOME' not in data, data)
    check('T-28 rejection message names --pr', '--pr' in err, err)

    # T-29 (#1561 round-26 redesign): pr-resume no longer fetches the PR
    # head into a temporary ref (the "undeletable temp ref" and "partial
    # fetch leaves a temp ref behind" vulnerability classes the earlier
    # versions of T-29/T-30 covered no longer exist, since there is no temp
    # ref for anything to go wrong with). In their place: a PR head whose
    # object this local checkout does not have (a fork PR, or any commit
    # this repo genuinely never saw — this script does not fetch to fix
    # that) must degrade gracefully to Undetermined/check-inconclusive for
    # the coderabbit platform read, not hang, not fetch, and not fail
    # closed the whole run.
    repo29 = root / 'repo29'
    write_repo(repo29, coherent_shared, coherent_coderabbit)
    bins29 = root / 'bin29'
    bins29.mkdir(exist_ok=True)
    fake_gh29 = bins29 / 'gh'
    unknown_sha29 = 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef'
    fake_gh29.write_text(
        '#!/bin/bash\n'
        'if [ "$1" = pr ] && [ "$2" = view ]; then\n'
        f'  printf \'{{"baseRefName":"develop","headRefName":"feature/pr29-fork-test","headRefOid":"{unknown_sha29}"}}\\n\'\n'
        '  exit 0\n'
        'fi\n'
        'exit 1\n'
    )
    fake_gh29.chmod(0o755)
    rc, data, out, err = run(
        repo29, '--mode', 'pr-resume', '--target-base', 'develop', '--pr', '29', '--owner', 'example', '--repo', 'test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={'PATH': f'{bins29}:{os.environ.get("PATH", "")}'},
        expected=0,
    )
    check('T-29 an unfetched PR-head object degrades to passed-unverified, not a hang or fetch', data.get('OUTCOME') == 'passed-unverified', data)
    check('T-29 the affected platform is Undetermined/check-inconclusive', data.get('PLATFORM_1_VERDICT') == 'undetermined' and data.get('PLATFORM_1_REASONS') == 'check-inconclusive', data)
    ref_listing29 = git(repo29, 'for-each-ref', 'refs/reviewer-preflight/')
    check('T-29 creates no temporary ref', ref_listing29.stdout.strip() == '', ref_listing29.stdout)
    unknown29_present = git(repo29, 'cat-file', '-e', f'{unknown_sha29}^{{commit}}', check_call=False)
    check('T-29 never fetches the unknown PR-head object into the local object DB', unknown29_present.returncode != 0, unknown29_present)

    # T-30 (#1561 round-26): pr-resume's own base-branch resolution goes
    # through the same resolve_target_base_or_fail path pre-dispatch/
    # branch-resume already exercise (T-9) — a confirmed-absent PR base
    # must classify as prerequisite-failed here too, not a tooling failure,
    # for consistency across all three modes.
    repo30 = root / 'repo30'
    write_repo(repo30, coherent_shared, coherent_coderabbit)
    bins30 = root / 'bin30'
    bins30.mkdir(exist_ok=True)
    fake_gh30 = bins30 / 'gh'
    fake_gh30.write_text(
        '#!/bin/bash\n'
        'if [ "$1" = pr ] && [ "$2" = view ]; then\n'
        '  printf \'{"baseRefName":"nonexistent-pr-base","headRefName":"feature/pr30-test","headRefOid":"0000000000000000000000000000000000000000"}\\n\'\n'
        '  exit 0\n'
        'fi\n'
        'exit 1\n'
    )
    fake_gh30.chmod(0o755)
    rc, data, out, err = run(
        repo30, '--mode', 'pr-resume', '--target-base', 'develop', '--pr', '30', '--owner', 'example', '--repo', 'test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={'PATH': f'{bins30}:{os.environ.get("PATH", "")}'},
        expected=2,
    )
    check('T-30 confirmed-absent PR base is prerequisite-failed', data.get('OUTCOME') == 'prerequisite-failed', data)
    check(
        'T-30 prerequisite_detail names the PR base',
        'nonexistent-pr-base' in data.get('PREREQUISITE_DETAIL', ''),
        data,
    )

    # T-31: LOCAL_OVERRIDE_STATE must match the documented contract's
    # present-unpropagated <details> shape (naming the file), not the bare
    # undocumented literal "present", when an override file exists but
    # contains no review keys any resolved bucket used.
    repo31 = root / 'repo31'
    write_repo(repo31, coherent_shared, coherent_coderabbit)
    local31 = repo31 / '.ai-dev-workflow.local.yaml'
    local31.write_text('unrelated:\n  key: value\n')
    rc, data, out, err = run(
        repo31, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=0,
    )
    check(
        'T-31 unpropagated local override reports present-unpropagated with the file path',
        data.get('LOCAL_OVERRIDE_STATE', '').startswith('present-unpropagated')
        and str(local31) in data.get('LOCAL_OVERRIDE_STATE', ''),
        data,
    )

    # T-32 (#1561 round-20 finding): a local-only resumed branch that shares
    # its short name with a tag must resolve through refs/heads/<name>, not
    # let git's own refname disambiguation (which tries refs/tags/<name>
    # before refs/heads/<name>) silently substitute the tag's
    # .coderabbit.yaml. Build a same-named tag pointing at a commit with
    # review DISABLED, then a same-named local branch (no remote copy) with
    # review ENABLED; branch-resume must report the branch's own (enabled)
    # config, not fall through to the tag's disabled one.
    repo32 = root / 'repo32'
    write_repo(repo32, coherent_shared, coherent_coderabbit)
    git(repo32, 'checkout', '-q', '-b', 'shared-name-test')
    (repo32 / '.coderabbit.yaml').write_text(disabled_coderabbit)
    git(repo32, 'add', '-A')
    git(repo32, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'tag target: review disabled')
    git(repo32, 'tag', 'shared-name-test')
    git(repo32, 'checkout', '-q', 'develop')
    git(repo32, 'branch', '-D', 'shared-name-test')
    git(repo32, 'checkout', '-q', '-b', 'shared-name-test-branch-only')
    git(repo32, 'branch', '-m', 'shared-name-test-branch-only', 'shared-name-test')
    # shared-name-test is now: a tag (review disabled) AND a local-only
    # branch of the same short name (review enabled, coherent_coderabbit,
    # inherited from develop) with no remote copy — the exact ambiguous
    # shape git's own refname disambiguation resolves against refs/tags/
    # first for a bare revision.
    check(
        'T-32 fixture sanity: bare name resolves the TAG (disabled), confirming the ambiguity exists',
        git(repo32, 'show', 'shared-name-test:.coderabbit.yaml').stdout == disabled_coderabbit,
    )
    rc, data, out, err = run(
        repo32, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', 'shared-name-test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=0,
    )
    check(
        'T-32 branch-resume resolves the fully-qualified local BRANCH, not the same-named tag',
        data.get('OUTCOME') == 'passed',
        data,
    )
    # The OUTCOME=passed check above is the primary assertion (a
    # disabled-tag misread would report OUTCOME=blocked instead, since
    # coherent_shared lists coderabbit and review-disabled is a not-operable
    # reason). Cross-check directly against the git ref resolution the fix
    # targets, independent of the report's rendering shape.
    check(
        'T-32 refs/heads/<name> (the branch) is what actually has review enabled',
        git(repo32, 'show', 'refs/heads/shared-name-test:.coderabbit.yaml').stdout == coherent_coderabbit,
    )

    # T-33 (#1561 round-21 finding): the AC-2 before/after `git status
    # --porcelain` snapshots must be bounded the same way every other read in
    # this script is — a stalled filesystem must not let this run past its
    # advertised whole-invocation budget. Fake `git status --porcelain` as an
    # unbounded sleep; the run must still finish within a small multiple of
    # the (deliberately tight) test budget, not hang for the fake's full
    # sleep duration.
    repo33 = root / 'repo33'
    write_repo(repo33, coherent_shared, coherent_coderabbit)
    bins33 = root / 'bin33'
    bins33.mkdir(exist_ok=True)
    real_git33 = shutil.which('git')
    slow_git33 = bins33 / 'git'
    slow_git33.write_text(
        '#!/bin/bash\n'
        # "git -C <root> status --porcelain": `status` is not a fixed
        # positional argument once -C <root> precedes it, so match by
        # scanning args rather than assuming $1/$2.
        'is_status=0\n'
        'for arg in "$@"; do case "$arg" in status) is_status=1;; esac; done\n'
        'if [ "$is_status" = 1 ]; then sleep 30; fi\n'
        f'exec {real_git33!r} "$@"\n'
    )
    slow_git33.chmod(0o755)
    import time as _time33

    start33 = _time33.monotonic()
    rc, data, out, err = run(
        repo33, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={
            'PATH': f'{bins33}:{os.environ.get("PATH", "")}',
            'WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE': '1',
            'WORKFLOW_REVIEWER_PREFLIGHT_BUDGET_SECONDS': '3',
            'WORKFLOW_REVIEWER_PREFLIGHT_PER_PLATFORM_CAP_SECONDS': '1',
        },
    )
    wall33 = _time33.monotonic() - start33
    check(
        'T-33 a stalled git status --porcelain does not let the run exceed a small multiple of its budget',
        wall33 <= 15.0,
        f'wall={wall33}s rc={rc} data={data} err={err}',
    )
    check(
        'T-33 a bounded status-check timeout fails closed (exit 3), not OUTCOME=passed built on an unverified working tree',
        rc == 3 and 'OUTCOME' not in data,
        f'rc={rc} data={data} err={err}',
    )
    check(
        'T-33 the failure message names AC-2 and the time budget',
        'AC-2' in err and 'time budget' in err,
        err,
    )

    # T-34 (#1561 round-22 finding): the branch-resume ancestry-selection
    # `merge-base --is-ancestor` calls must be bounded too — same class of
    # unbounded-wall-clock risk as T-33's porcelain checks, on a fixture
    # where both a local and remote copy resolve so the ancestry-selection
    # code path is actually reached (T-13's local-ahead fixture shape).
    repo34 = root / 'repo34'
    write_repo(repo34, coherent_shared, coherent_coderabbit)
    remote34 = root / 'remote34.git'
    subprocess.run(['git', 'clone', '-q', '--bare', str(repo34), str(remote34)], check=True)
    git(repo34, 'remote', 'set-url', 'origin', str(remote34))
    git(repo34, 'checkout', '-q', '-b', 'feature/ancestry-timeout-test')
    git(repo34, 'push', '-q', 'origin', 'feature/ancestry-timeout-test')
    git(repo34, 'fetch', '-q', 'origin', 'feature/ancestry-timeout-test')
    bins34 = root / 'bin34'
    bins34.mkdir(exist_ok=True)
    real_git34 = shutil.which('git')
    slow_git34 = bins34 / 'git'
    slow_git34.write_text(
        '#!/bin/bash\n'
        'is_merge_base=0\n'
        'for arg in "$@"; do case "$arg" in merge-base) is_merge_base=1;; esac; done\n'
        'if [ "$is_merge_base" = 1 ]; then sleep 30; fi\n'
        f'exec {real_git34!r} "$@"\n'
    )
    slow_git34.chmod(0o755)
    start34 = _time33.monotonic()
    rc, data, out, err = run(
        repo34, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', 'feature/ancestry-timeout-test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={
            'PATH': f'{bins34}:{os.environ.get("PATH", "")}',
            'WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE': '1',
            'WORKFLOW_REVIEWER_PREFLIGHT_BUDGET_SECONDS': '3',
            'WORKFLOW_REVIEWER_PREFLIGHT_PER_PLATFORM_CAP_SECONDS': '1',
        },
    )
    wall34 = _time33.monotonic() - start34
    check(
        'T-34 a stalled merge-base --is-ancestor does not let the run exceed a small multiple of its budget',
        wall34 <= 15.0,
        f'wall={wall34}s rc={rc} data={data} err={err}',
    )
    check(
        'T-34 a bounded ancestry-check timeout fails closed (exit 3), not a divergence or wrong-branch outcome',
        rc == 3 and 'OUTCOME' not in data,
        f'rc={rc} data={data} err={err}',
    )
    check(
        'T-34 the failure message names the ancestry check and the time budget',
        'ancestry check' in err and 'time budget' in err,
        err,
    )

    # T-35 (#1561 round-23 finding): the two ancestry checks must clamp to
    # the remaining invocation deadline (clamp_bound), not reset a fresh
    # per-check floor (clamp_bound_floor) — the latter lets branch-resume
    # repeatedly re-extend past the whole invocation's nominal budget by up
    # to one floor-second per check (up to two checks) once the budget is
    # already exhausted, eroding Decision 3's total-wall-clock guarantee.
    # A live timing reproduction of this specific regression is impractical
    # to construct hermetically without also perturbing the (separately
    # bounded via clamp_bound, not clamp_bound_floor, as of the round-24
    # fix, and out of this round's scope either way) rev-parse resolution
    # probes that precede the ancestry checks in the same block; assert the
    # source directly instead, scoped to exactly the two merge-base call
    # sites this fix touches (the ancestry-selection branch, not the
    # ref-resolution probes above it).
    ancestry_block = helper.read_text().split(
        'if [ "$local_resolves" = 1 ] && [ "$origin_resolves" = 1 ]; then', 1
    )[1]
    ancestry_block = ancestry_block[: ancestry_block.find("elif [ \"$origin_resolves\" = 1 ]")]
    check(
        # 3, not 2, as of the round-26 read-only redesign: the object-
        # presence `cat-file -e` check that now precedes the two
        # merge-base calls (guarding against this script never having
        # fetched the remote's resolved SHA) added its own clamp_bound
        # call in the same block.
        'T-35 every ancestry-selection clamp call (presence check + both merge-base calls) uses clamp_bound, not clamp_bound_floor',
        ancestry_block.count('clamp_bound "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"') == 3
        # Substring match alone would false-positive on this fix's own
        # explanatory comment, which names clamp_bound_floor to contrast
        # against it; require the actual call form instead.
        and 'clamp_bound_floor "$PREFLIGHT_PER_PLATFORM_CAP_SECONDS"' not in ancestry_block,
        ancestry_block,
    )

    # T-36 (#1561 round-24 finding): "HEAD" must be rejected as a
    # --target-base / --branch value. `git check-ref-format refs/heads/HEAD`
    # reports it as a syntactically fine refname (confirmed: it is not
    # rejected the way a leading-dash or refspec-syntax value is), but HEAD
    # is git's own reserved symbolic-ref name — passing it through would
    # fetch/read the remote's symbolic default-branch pointer under the
    # literal name "HEAD" rather than that branch's own name.
    check(
        'T-36 fixture sanity: check-ref-format refs/heads/HEAD alone does not reject it (confirming the gap existed)',
        subprocess.run(['git', 'check-ref-format', 'refs/heads/HEAD'], capture_output=True).returncode == 0,
    )
    rc, data, out, err = run(
        repo1, '--mode', 'pre-dispatch', '--target-base', 'HEAD',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=2,
    )
    check('T-36 --target-base HEAD is rejected as prerequisite-failed', data.get('OUTCOME') == 'prerequisite-failed', data)
    check(
        'T-36 rejection message names --target-base and HEAD',
        '--target-base' in data.get('PREREQUISITE_DETAIL', '') and 'HEAD' in data.get('PREREQUISITE_DETAIL', ''),
        data,
    )
    rc, data, out, err = run(
        repo1, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', 'HEAD',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=3,
    )
    check('T-36 --branch HEAD is rejected (not OUTCOME=passed against the wrong ref)', 'OUTCOME' not in data, data)
    check('T-36 --branch HEAD rejection message names --branch and HEAD', '--branch' in err and 'HEAD' in err, err)

    # T-37 (#1561 round-24 finding): the two `rev-parse --verify --quiet`
    # branch-existence probes immediately preceding the ancestry checks
    # must be bounded too — same class of unbounded-wall-clock risk as the
    # porcelain and ancestry checks.
    repo37 = root / 'repo37'
    write_repo(repo37, coherent_shared, coherent_coderabbit)
    remote37 = root / 'remote37.git'
    subprocess.run(['git', 'clone', '-q', '--bare', str(repo37), str(remote37)], check=True)
    git(repo37, 'remote', 'set-url', 'origin', str(remote37))
    git(repo37, 'checkout', '-q', '-b', 'feature/resolve-timeout-test')
    git(repo37, 'push', '-q', 'origin', 'feature/resolve-timeout-test')
    git(repo37, 'fetch', '-q', 'origin', 'feature/resolve-timeout-test')
    bins37 = root / 'bin37'
    bins37.mkdir(exist_ok=True)
    real_git37 = shutil.which('git')
    slow_git37 = bins37 / 'git'
    slow_git37.write_text(
        '#!/bin/bash\n'
        'is_revparse=0\n'
        'for arg in "$@"; do case "$arg" in --verify) is_revparse=1;; esac; done\n'
        'if [ "$is_revparse" = 1 ]; then sleep 30; fi\n'
        f'exec {real_git37!r} "$@"\n'
    )
    slow_git37.chmod(0o755)
    start37 = _time33.monotonic()
    rc, data, out, err = run(
        repo37, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', 'feature/resolve-timeout-test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={
            'PATH': f'{bins37}:{os.environ.get("PATH", "")}',
            'WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE': '1',
            'WORKFLOW_REVIEWER_PREFLIGHT_BUDGET_SECONDS': '3',
            'WORKFLOW_REVIEWER_PREFLIGHT_PER_PLATFORM_CAP_SECONDS': '1',
        },
    )
    wall37 = _time33.monotonic() - start37
    check(
        'T-37 a stalled rev-parse --verify branch-resolution probe does not let the run exceed a small multiple of its budget',
        wall37 <= 15.0,
        f'wall={wall37}s rc={rc} data={data} err={err}',
    )
    check(
        'T-37 a bounded resolution-probe timeout fails closed (exit 3), not a wrong-branch outcome',
        rc == 3 and 'OUTCOME' not in data,
        f'rc={rc} data={data} err={err}',
    )
    check(
        'T-37 the failure message names the resolution probe and the time budget',
        'resolution probe' in err and 'time budget' in err,
        err,
    )

    # T-38 (#1561 round-25 finding): read_ref_file's own failure-path
    # `rev-parse --verify` (run after a `git show` failure, to distinguish
    # "file absent at a ref that resolves" from "ref itself does not
    # resolve") must be bounded too — same class of unbounded-wall-clock
    # risk. Use a repo with no .coderabbit.yaml at all, so `git show
    # <ref>:.coderabbit.yaml` fails for the ordinary (non-timeout) reason
    # this verification probe exists to disambiguate.
    repo38 = root / 'repo38'
    write_repo(repo38, coherent_shared, coderabbit_yaml=None)
    bins38 = root / 'bin38'
    bins38.mkdir(exist_ok=True)
    real_git38 = shutil.which('git')
    slow_git38 = bins38 / 'git'
    slow_git38.write_text(
        '#!/bin/bash\n'
        'is_verify=0\n'
        'for arg in "$@"; do case "$arg" in --verify) is_verify=1;; esac; done\n'
        'if [ "$is_verify" = 1 ]; then sleep 30; fi\n'
        f'exec {real_git38!r} "$@"\n'
    )
    slow_git38.chmod(0o755)
    start38 = _time33.monotonic()
    rc, data, out, err = run(
        repo38, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={
            'PATH': f'{bins38}:{os.environ.get("PATH", "")}',
            'WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE': '1',
            'WORKFLOW_REVIEWER_PREFLIGHT_BUDGET_SECONDS': '3',
            'WORKFLOW_REVIEWER_PREFLIGHT_PER_PLATFORM_CAP_SECONDS': '1',
        },
    )
    wall38 = _time33.monotonic() - start38
    check(
        'T-38 a stalled read_ref_file verify-probe does not let the run exceed a small multiple of its budget',
        wall38 <= 15.0,
        f'wall={wall38}s rc={rc} data={data} err={err}',
    )
    # The shared config file (.ai-dev-workflow.yaml) exists in this
    # fixture, so its own read_ref_file call succeeds immediately (rc=0)
    # without ever reaching this verify sub-probe; only the coderabbit
    # read (.coderabbit.yaml is absent from this fixture on purpose, so
    # `git show` genuinely fails and falls through to the now-slowed
    # verify probe) exercises the bound. Its caller already degrades a
    # 124 there to Undetermined/check-inconclusive for that one platform
    # (this test's own load-bearing assertion is the wall-clock bound
    # above, which proves that degrade happened quickly rather than after
    # hanging for the fake's full 30s sleep).
    check(
        'T-38 a bounded verify-probe timeout degrades to Undetermined/check-inconclusive, not a hang',
        data.get('OUTCOME') == 'passed-unverified'
        and data.get('PLATFORM_1_VERDICT') == 'undetermined'
        and data.get('PLATFORM_1_REASONS') == 'check-inconclusive',
        f'rc={rc} data={data} err={err}',
    )

    # T-39 (human decision on #1561's round-26 P1 finding): comprehensive
    # proof that this script makes no repository-state change whatsoever —
    # not merely "the working tree is unchanged" (AC-2's own porcelain
    # diff, exercised throughout this suite already) but specifically that
    # refs/remotes/*, FETCH_HEAD, and the object database are byte-for-byte
    # identical before and after, across all three modes. `git ls-remote`
    # (this script's own replacement for the `git fetch` it used to run)
    # only queries the remote; it must never create or update a local ref,
    # never write FETCH_HEAD, and never download any object.
    def repo_fingerprint(repo):
        refs = git(repo, 'for-each-ref').stdout
        fetch_head_path = repo / '.git' / 'FETCH_HEAD'
        fetch_head = fetch_head_path.read_bytes() if fetch_head_path.exists() else None
        objects = git(repo, 'count-objects', '-v').stdout
        return (refs, fetch_head, objects)

    repo39 = root / 'repo39'
    write_repo(repo39, coherent_shared, coherent_coderabbit)
    remote39 = root / 'remote39.git'
    subprocess.run(['git', 'clone', '-q', '--bare', str(repo39), str(remote39)], check=True)
    git(repo39, 'remote', 'set-url', 'origin', str(remote39))
    git(repo39, 'checkout', '-q', '-b', 'feature/fingerprint-test')
    git(repo39, 'push', '-q', 'origin', 'feature/fingerprint-test')
    git(repo39, 'fetch', '-q', 'origin', 'feature/fingerprint-test')

    # pre-dispatch: fingerprint immediately before/after.
    before39a = repo_fingerprint(repo39)
    run(
        repo39, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=0,
    )
    after39a = repo_fingerprint(repo39)
    check('T-39 pre-dispatch: refs/for-each-ref unchanged', before39a[0] == after39a[0], (before39a[0], after39a[0]))
    check('T-39 pre-dispatch: FETCH_HEAD unchanged', before39a[1] == after39a[1], (before39a[1], after39a[1]))
    check('T-39 pre-dispatch: object database unchanged', before39a[2] == after39a[2], (before39a[2], after39a[2]))

    # branch-resume: exercises both the target-base AND the branch-name
    # ls-remote resolution paths (local and remote both resolve here, so
    # the ancestry-selection object-presence check and merge-base calls run
    # too).
    before39b = repo_fingerprint(repo39)
    run(
        repo39, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', 'feature/fingerprint-test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=0,
    )
    after39b = repo_fingerprint(repo39)
    check('T-39 branch-resume: refs/for-each-ref unchanged', before39b[0] == after39b[0], (before39b[0], after39b[0]))
    check('T-39 branch-resume: FETCH_HEAD unchanged', before39b[1] == after39b[1], (before39b[1], after39b[1]))
    check('T-39 branch-resume: object database unchanged', before39b[2] == after39b[2], (before39b[2], after39b[2]))

    # pr-resume: exercises the gh-reported headRefOid direct-SHA read path.
    bins39 = root / 'bin39'
    bins39.mkdir(exist_ok=True)
    fake_gh39 = bins39 / 'gh'
    pr39_head_sha = git(repo39, 'rev-parse', 'feature/fingerprint-test').stdout.strip()
    fake_gh39.write_text(
        '#!/bin/bash\n'
        'if [ "$1" = pr ] && [ "$2" = view ]; then\n'
        f'  printf \'{{"baseRefName":"develop","headRefName":"feature/fingerprint-test","headRefOid":"{pr39_head_sha}"}}\\n\'\n'
        '  exit 0\n'
        'fi\n'
        'exit 1\n'
    )
    fake_gh39.chmod(0o755)
    before39c = repo_fingerprint(repo39)
    run(
        repo39, '--mode', 'pr-resume', '--target-base', 'develop', '--pr', '39', '--owner', 'example', '--repo', 'test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={'PATH': f'{bins39}:{os.environ.get("PATH", "")}'},
        expected=0,
    )
    after39c = repo_fingerprint(repo39)
    check('T-39 pr-resume: refs/for-each-ref unchanged', before39c[0] == after39c[0], (before39c[0], after39c[0]))
    check('T-39 pr-resume: FETCH_HEAD unchanged', before39c[1] == after39c[1], (before39c[1], after39c[1]))
    check('T-39 pr-resume: object database unchanged', before39c[2] == after39c[2], (before39c[2], after39c[2]))

    # T-40 (#1561 round-26 finding): "0" cannot identify a pull request;
    # the digits-only --pr check alone still accepted it, reaching
    # `gh pr view 0` as an unstructured tooling failure instead of
    # rejecting the invalid input locally.
    rc, data, out, err = run(
        repo1, '--mode', 'pr-resume', '--target-base', 'develop', '--pr', '0',
        '--owner', 'example', '--repo', 'test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=3,
    )
    check('T-40 --pr 0 is rejected', 'OUTCOME' not in data, data)
    check('T-40 --pr 0 rejection message names --pr and zero', '--pr' in err and 'zero' in err, err)
    # An all-zero value of any length ("00", "000", ...) is the same gap.
    rc, data, out, err = run(
        repo1, '--mode', 'pr-resume', '--target-base', 'develop', '--pr', '000',
        '--owner', 'example', '--repo', 'test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=3,
    )
    check('T-40 --pr 000 is rejected', 'OUTCOME' not in data, data)

    # T-41 (#1561 round-26 finding): a repeated --pr-state bucket key is
    # ambiguously composed input, not "last value wins" — reject it as
    # prerequisite-failed rather than silently keeping the last-parsed
    # value (which could bypass a disagreement the first, discarded value
    # would have produced, e.g. stage-excluded/blocked).
    rc, data, out, err = run(
        repo1, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github',
        '--pr-state', 'on_draft.github=draft,on_draft.github=ready',
        expected=2,
    )
    check('T-41 duplicate --pr-state bucket is prerequisite-failed', data.get('OUTCOME') == 'prerequisite-failed', data)
    check(
        'T-41 prerequisite_detail names the duplicated stage',
        'on_draft_github' in data.get('PREREQUISITE_DETAIL', ''),
        data,
    )

    # T-42 (bounded-Codex-pass finding, contract violation): `git status
    # --porcelain` must not itself write .git/index (an optional stat-cache
    # refresh) — AC-2's own before/after diff cannot detect that, since
    # porcelain output stays empty either way. Force a stale-mtime,
    # unchanged-content scenario (the documented trigger for this optional
    # write) and compare the raw index file's bytes, not just the porcelain
    # diff this suite already exercises everywhere else.
    repo42 = root / 'repo42'
    write_repo(repo42, coherent_shared, coherent_coderabbit)
    os.utime(repo42 / '.coderabbit.yaml', (1735689600, 1735689600))  # 2025-01-01, well in the past
    index_before = (repo42 / '.git' / 'index').read_bytes()
    run(
        repo42, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=0,
    )
    index_after = (repo42 / '.git' / 'index').read_bytes()
    check(
        'T-42 git status --porcelain does not rewrite .git/index (--no-optional-locks)',
        index_before == index_after,
        f'index changed: {len(index_before)} -> {len(index_after)} bytes',
    )

    # T-43 (bounded-Codex-pass finding, security/ReDoS): base_branches
    # patterns that each individually survive the per-pattern alarm (a
    # "near miss," not a per-pattern timeout) must still be bounded in
    # aggregate — many near-miss patterns together must not exhaust the
    # classifier's own outer per-platform deadline. This exercises
    # reviewer_preflight_coderabbit.py directly (round-24's T-33/T-34-style
    # shell fixtures cover the *shell* launcher's own bounds; this is the
    # python-internal aggregate bound those shell bounds sit on top of).
    coderabbit_helper = scripts / 'reviewer_preflight_coderabbit.py'
    near_miss_yaml = (
        'reviews:\n  auto_review:\n    enabled: true\n    base_branches:\n'
        + ''.join('      - "(a+)+$"\n' for _ in range(30))
    )
    coderabbit_file42 = root / 'near-miss-coderabbit.yaml'
    coderabbit_file42.write_text(near_miss_yaml)
    start43 = _time33.monotonic()
    result43 = subprocess.run(
        [sys.executable, str(coderabbit_helper), '--mode', 'full-json', str(coderabbit_file42)],
        capture_output=True, text=True, timeout=15,
    )
    wall43 = _time33.monotonic() - start43
    check(
        'T-43 parsing many near-miss base_branches patterns completes (no per-pattern timeout expected here; base_branch_covered is exercised separately)',
        result43.returncode == 0,
        (result43.returncode, result43.stdout, result43.stderr),
    )
    # The aggregate bound lives in base_branch_covered, called from
    # reviewer_preflight.py's classify(), not from this file's own
    # full-json parse — invoke it directly against the wall-clock claim.
    sys.path.insert(0, str(scripts))
    import importlib
    rpc = importlib.import_module('reviewer_preflight_coderabbit')
    importlib.reload(rpc)
    start43b = _time33.monotonic()
    try:
        rpc.base_branch_covered(['(a+)+$'] * 30, 'a' * 23 + '!', per_pattern_timeout_seconds=0.5, aggregate_timeout_seconds=3.0)
        check('T-43 aggregate bound raised PatternTimeoutError', False, 'expected PatternTimeoutError, none raised')
    except rpc.PatternTimeoutError:
        wall43b = _time33.monotonic() - start43b
        check(
            'T-43 30 near-miss patterns are bounded in aggregate (~3s), not left to run to ~10.5s unbounded',
            wall43b <= 5.0,
            f'wall={wall43b}s',
        )

    # T-44 (bounded-Codex-pass finding, contract violation): on the manual
    # (non-GNU-timeout) fallback launcher, a timed-out command's own
    # descendant process must be terminated too, not merely its direct
    # PID. Force the fallback path (T-24's fake, non-GNU `timeout`) and
    # fake `git` so its `ls-remote` invocation spawns a background
    # grandchild that writes a marker file after a delay — if only the
    # direct PID is signaled, the grandchild survives the cleanup (already
    # detached into the background before the parent is killed) and
    # writes the marker after this test has already moved on; if the whole
    # process group is signaled, the grandchild dies with it and the
    # marker is never written.
    repo44 = root / 'repo44'
    write_repo(repo44, coherent_shared, coherent_coderabbit)
    bins44 = root / 'bin44'
    bins44.mkdir(exist_ok=True)
    fake_timeout44 = bins44 / 'timeout'
    fake_timeout44.write_text(
        '#!/bin/bash\n'
        'if [ "$1" = --version ]; then printf "busybox timeout 1.0\\n"; exit 0; fi\n'
        'echo "timeout: unrecognized option" >&2\n'
        'exit 125\n'
    )
    fake_timeout44.chmod(0o755)
    real_git44 = shutil.which('git')
    marker44 = root / 'grandchild-survived.marker'
    slow_git44 = bins44 / 'git'
    slow_git44.write_text(
        '#!/bin/bash\n'
        'is_lsremote=0\n'
        'for arg in "$@"; do [ "$arg" = ls-remote ] && is_lsremote=1; done\n'
        'if [ "$is_lsremote" = 1 ]; then\n'
        f'  (sleep 2.5; touch {str(marker44)!r}) &\n'
        '  disown\n'
        '  sleep 30\n'
        '  exit 0\n'
        'fi\n'
        f'exec {real_git44!r} "$@"\n'
    )
    slow_git44.chmod(0o755)
    start44 = _time33.monotonic()
    rc, data, out, err = run(
        repo44, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={
            'PATH': f'{bins44}:{os.environ.get("PATH", "")}',
            'WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE': '1',
            'WORKFLOW_REVIEWER_PREFLIGHT_BUDGET_SECONDS': '2',
            'WORKFLOW_REVIEWER_PREFLIGHT_PER_PLATFORM_CAP_SECONDS': '1',
        },
    )
    wall44 = _time33.monotonic() - start44
    check(
        'T-44 a stalled fallback-launcher command does not let the run hang for the grandchild\'s full sleep',
        wall44 <= 10.0,
        f'wall={wall44}s rc={rc} data={data} err={err}',
    )
    # Wait past when the marker would appear if the grandchild survived
    # (2.5s from its own spawn, well before this check), then confirm it
    # never did.
    _time33.sleep(max(0.0, 3.5 - wall44))
    check(
        'T-44 the ls-remote grandchild is killed with its parent (process-group kill), not left running',
        not marker44.exists(),
        f'marker exists: {marker44.exists()}',
    )

    # T-45 (bounded-Codex-pass round 2, contract violation): in a genuine
    # partial clone (a supported Git checkout mode, not a hypothetical),
    # reading an object this checkout does not have locally must fail
    # closed (the existing read_ref_file rc=2 / undetermined contract),
    # not transparently lazy-fetch it from the promisor remote and write
    # new objects under .git — reproduced live with GIT_TRACE=1 showing an
    # internal `git fetch --filter=blob:none` triggered by a plain `git
    # show`. Build a real promisor-remote partial clone: commit1 has no
    # workflow config, commit2 (pushed to the bare remote *after* the
    # partial clone below, so its blobs are never fetched) adds a coherent
    # .ai-dev-workflow.yaml + .coderabbit.yaml.
    origin45 = root / 'origin45'
    origin45.mkdir()
    git(origin45, 'init', '-q')
    git(origin45, 'checkout', '-q', '-b', 'develop')
    (origin45 / 'placeholder.txt').write_text('no workflow config yet\n')
    git(origin45, 'add', '-A')
    git(origin45, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'commit1: no workflow config')
    remote45 = root / 'remote45.git'
    subprocess.run(['git', 'clone', '-q', '--bare', str(origin45), str(remote45)], check=True)
    git(remote45, 'config', 'uploadpack.allowFilter', 'true')
    git(remote45, 'config', 'uploadpack.allowAnySHA1InWant', 'true')
    repo45 = root / 'repo45'
    subprocess.run(
        ['git', 'clone', '-q', '--filter=blob:none', f'file://{remote45}', str(repo45)],
        check=True,
    )
    # `develop` is already the checked-out branch (the remote's only/default
    # branch), so no separate checkout is needed here.
    objects_before45 = sorted(p for p in (repo45 / '.git' / 'objects').rglob('*') if p.is_file())
    # Now advance the *origin* checkout (not the partial clone) past what
    # the partial clone has and push it — the partial clone's own local
    # object store never sees these new blobs.
    (origin45 / '.ai-dev-workflow.yaml').write_text(coherent_shared)
    (origin45 / '.coderabbit.yaml').write_text(coherent_coderabbit)
    git(origin45, 'add', '-A')
    git(origin45, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'commit2: add workflow config')
    git(origin45, 'push', '-q', str(remote45), 'develop:develop')
    rc, data, out, err = run(
        repo45, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
    )
    objects_after45 = sorted(p for p in (repo45 / '.git' / 'objects').rglob('*') if p.is_file())
    check(
        'T-45 reading a not-locally-present object in a partial clone does not trigger a lazy fetch (object store unchanged)',
        objects_before45 == objects_after45,
        f'before={len(objects_before45)} after={len(objects_after45)} rc={rc} data={data} err={err}',
    )
    check(
        'T-45 the run still reaches a bounded, non-hanging outcome (fails closed rather than fetching)',
        'OUTCOME' not in data or data.get('OUTCOME') in ('passed', 'passed-unverified', 'blocked'),
        f'rc={rc} data={data} err={err}',
    )

    # T-46 (bounded-Codex-pass, P1): read_ref_file must distinguish "path
    # genuinely absent from the tree" from "path present in the tree but
    # its blob is not locally available" — a partial clone that never
    # checked out a file (here: --no-checkout, so no blob is eagerly
    # fetched at all, not even the tip's own) reproduces the latter case
    # even for the ref this preflight actually reads (round-27's own T-45
    # fixture could only reproduce it for a historical, non-tip commit).
    # `git show` fails ("bad object") but a bare commit-only rev-parse
    # succeeds; the fix (ls-tree, which needs only the tree object) must
    # tell these apart and fail closed rather than report "absent."
    origin46 = root / 'origin46'
    origin46.mkdir()
    git(origin46, 'init', '-q')
    git(origin46, 'checkout', '-q', '-b', 'develop')
    (origin46 / '.ai-dev-workflow.yaml').write_text(coherent_shared)
    git(origin46, 'add', '-A')
    git(origin46, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'commit1: coherent shared config requiring coderabbit')
    remote46 = root / 'remote46.git'
    subprocess.run(['git', 'clone', '-q', '--bare', str(origin46), str(remote46)], check=True)
    git(remote46, 'config', 'uploadpack.allowFilter', 'true')
    git(remote46, 'config', 'uploadpack.allowAnySHA1InWant', 'true')
    repo46 = root / 'repo46'
    subprocess.run(
        ['git', 'clone', '-q', '--filter=blob:none', '--no-checkout', f'file://{remote46}', str(repo46)],
        check=True,
    )
    objects_before46 = sorted(p for p in (repo46 / '.git' / 'objects').rglob('*') if p.is_file())
    rc, data, out, err = run(
        repo46, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=3,
    )
    objects_after46 = sorted(p for p in (repo46 / '.git' / 'objects').rglob('*') if p.is_file())
    check(
        'T-46 an unfetched-blob tip (path present in tree, blob missing) fails closed, not OUTCOME=passed',
        'OUTCOME' not in data,
        f'rc={rc} data={data} err={err}',
    )
    check(
        'T-46 the failure message distinguishes this from "file absent" (names read_ref_file exit 2, not exit 1)',
        'read_ref_file exit 2' in err,
        err,
    )
    check(
        'T-46 no lazy fetch occurred while distinguishing the two cases (object store unchanged)',
        objects_before46 == objects_after46,
        f'before={len(objects_before46)} after={len(objects_after46)}',
    )

    # T-47 (bounded-Codex-pass, P2): a branch that never existed anywhere
    # (never pushed, never locally created — distinct from T-25's
    # "existed then was deleted" case) must fail closed the same way.
    repo47 = root / 'repo47'
    write_repo(repo47, coherent_shared, coherent_coderabbit)
    rc, data, out, err = run(
        repo47, '--mode', 'branch-resume', '--target-base', 'develop', '--branch', 'feature/never-existed-test',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        expected=3,
    )
    check('T-47 a branch that never existed anywhere fails closed, not a degraded-but-successful outcome', 'OUTCOME' not in data, data)
    check(
        'T-47 failure message names the branch and that it resolves neither locally nor on the remote',
        'feature/never-existed-test' in err and 'neither locally nor on the remote' in err,
        err,
    )

    # T-48 (bounded-Codex-pass, P2): if copying the local override file
    # fails for any reason (it disappears, becomes unreadable, or the copy
    # itself fails between review-overrides resolving it and this script's
    # own read — review-overrides must itself still succeed first, or the
    # existing "review-overrides failed" tooling failure fires instead,
    # never reaching the cp this test targets), that must be a tooling
    # failure (exit 3, named), not an unguarded `cp` exiting 1 under
    # `set -e` with no OUTCOME report — exit 1 is reserved for the
    # structured `blocked` verdict, so a caller distinguishing outcomes by
    # exit code alone could misclassify this staging failure as a
    # reviewer-configuration disagreement. Fake `cp` itself to fail
    # deterministically for exactly this one target, isolating the guard
    # from needing to reproduce a genuine, inherently racy TOCTOU window.
    repo48 = root / 'repo48'
    write_repo(repo48, coherent_shared, coherent_coderabbit)
    local48 = repo48 / '.ai-dev-workflow.local.yaml'
    local48.write_text('review:\n  on_draft:\n    runner: [claude]\n')
    bins48 = root / 'bin48'
    bins48.mkdir(exist_ok=True)
    real_cp48 = shutil.which('cp')
    failing_cp48 = bins48 / 'cp'
    failing_cp48.write_text(
        '#!/bin/bash\n'
        'for arg in "$@"; do case "$arg" in *.ai-dev-workflow.local.yaml) echo "cp: simulated I/O error" >&2; exit 1;; esac; done\n'
        f'exec {real_cp48!r} "$@"\n'
    )
    failing_cp48.chmod(0o755)
    rc, data, out, err = run(
        repo48, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={'PATH': f'{bins48}:{os.environ.get("PATH", "")}'},
        expected=3,
    )
    check('T-48 a failed copy of the local override file fails closed as a tooling failure, not a bare cp exit 1', 'OUTCOME' not in data, data)
    check(
        'T-48 failure message names the local override file and the copy failure',
        str(local48) in err and 'cannot copy the local override file' in err,
        err,
    )

    # T-49 (#1561 round-6 finding, P2): an explicit empty --remaining-stages
    # short-circuits straight to no-review-remaining WITHOUT reading either
    # reviewer configuration — but it must still resolve (and validate the
    # existence of) the run's own base first, the same prerequisite-failed
    # gate every other mode applies: the base is a run-input precondition,
    # not merely a value only the skipped reviewer-configuration reads would
    # have consulted. A --target-base that does not exist on the remote at
    # all must report prerequisite-failed (exit 2), not silently succeed
    # with an unvalidated base.
    repo49 = root / 'repo49'
    write_repo(repo49, coherent_shared, coherent_coderabbit)
    rc, data, out, err = run(
        repo49, '--mode', 'pre-dispatch', '--target-base', 'nonexistent-base-that-would-fail',
        '--remaining-stages', '',
        expected=2,
    )
    check('T-49 empty remaining-stages still resolves (and validates) target-base before short-circuiting', data.get('OUTCOME') == 'prerequisite-failed', data)
    check(
        'T-49 prerequisite_detail names --target-base and the branch',
        '--target-base' in data.get('PREREQUISITE_DETAIL', '') and 'nonexistent-base-that-would-fail' in data.get('PREREQUISITE_DETAIL', ''),
        data,
    )

    # T-49b: with a base that DOES exist on the remote, the empty
    # --remaining-stages short-circuit must still report no-review-remaining
    # and never compute any platform — confirming the base-resolution fix
    # above did not reintroduce the reviewer-configuration reads the
    # original round-5 fix removed.
    repo49b = root / 'repo49b'
    write_repo(repo49b, coherent_shared, coherent_coderabbit)
    rc, data, out, err = run(
        repo49b, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', '',
        expected=0,
    )
    check('T-49b empty remaining-stages against a valid base still short-circuits to no-review-remaining', data.get('OUTCOME') == 'no-review-remaining', data)
    check('T-49b no platforms computed', data.get('PLATFORM_COUNT') == '0', data)

    # T-50 (bounded-Codex-pass, P2): when review-overrides resolves a
    # local override path but that path is no longer a readable regular
    # file by the time this script's own presence check runs (deleted or
    # replaced in between), this must fail closed as a tooling failure —
    # not silently fall through to LOCAL_OVERRIDE_STATE=none and resolve
    # reviewer lists as if no override existed. Fake python3 to replace
    # the override file with a directory immediately after the real
    # review-overrides call resolves it (a stable, deterministic
    # reproduction of this TOCTOU window).
    repo50 = root / 'repo50'
    write_repo(repo50, coherent_shared, coherent_coderabbit)
    local50 = repo50 / '.ai-dev-workflow.local.yaml'
    local50.write_text('review:\n  on_draft:\n    runner: [claude]\n')
    bins50 = root / 'bin50'
    bins50.mkdir(exist_ok=True)
    real_python50 = shutil.which('python3')
    racy_python50 = bins50 / 'python3'
    racy_python50.write_text(
        '#!/bin/bash\n'
        'is_review_overrides=0\n'
        'for arg in "$@"; do [ "$arg" = review-overrides ] && is_review_overrides=1; done\n'
        f'{real_python50!r} "$@"\n'
        'rc=$?\n'
        'if [ "$is_review_overrides" = 1 ] && [ "$rc" = 0 ]; then\n'
        f'  rm -f {str(local50)!r}\n'
        'fi\n'
        'exit "$rc"\n'
    )
    racy_python50.chmod(0o755)
    rc, data, out, err = run(
        repo50, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={'PATH': f'{bins50}:{os.environ.get("PATH", "")}'},
        expected=3,
    )
    check('T-50 a local override removed between resolution and the presence check fails closed, not LOCAL_OVERRIDE_STATE=none', 'OUTCOME' not in data, data)
    check(
        'T-50 failure message names the local override file and that it no longer exists',
        str(local50) in err and 'no longer exists' in err,
        err,
    )

    # T-51 (#1561 round-7 finding, P2): clamp_bound_floor's 1-second floor
    # must extend the effective deadline exactly ONCE per invocation, not
    # grant a fresh 1-second budget to every post-deadline call site — an
    # earlier version of this function reset `remaining` to a fresh 1 on
    # every call after the deadline, which could let a slow run overrun
    # PREFLIGHT_BUDGET_SECONDS by several seconds in aggregate across the
    # up to six clamp_bound_floor call sites in a single invocation (the
    # before-porcelain snapshot, either input-build path, the classifier,
    # the after-porcelain snapshot, and the report renderer). Reuse T-7's
    # own reliable, non-race-prone timing fixture (a real git subprocess
    # bounded well under its artificial 5-second delay, not a tight
    # sub-second race against another fake) and assert the reported
    # BUDGET_SECONDS stays exactly the nominal value passed in (not
    # inflated by however many post-deadline call sites happened to run)
    # and ELAPSED_SECONDS stays within budget plus the platform cap plus a
    # single one-second floor extension — not budget plus the cap plus one
    # second per post-deadline call site.
    rc, data, out, err = run(
        repo7, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env=env2, expected=0,
    )
    check('T-51 reported BUDGET_SECONDS is the nominal input, not inflated by the floor extension', data.get('BUDGET_SECONDS') == '2', data)
    check(
        'T-51 elapsed stays within budget + per-platform cap + a single one-second floor extension, not one extension per post-deadline call site',
        float(data.get('ELAPSED_SECONDS', '999')) <= 5.0,
        data,
    )

    # T-52 (#1561 round-8 finding, P2): an omitted --remaining-stages must
    # be classified prerequisite-failed (exit 2) even when the resolved
    # base's own config blob cannot be read locally — the config-read
    # failure must not mask the earlier malformed/omitted stage-set input
    # behind an unstructured tooling failure (exit 3). Reuse T-46's own
    # partial-clone fixture (--filter=blob:none --no-checkout: the tip's
    # own .ai-dev-workflow.yaml blob is never fetched, so a config read
    # would fail with read_ref_file exit 2) — T-46 itself proves that same
    # fixture DOES route through `fail()` (exit 3) when --remaining-stages
    # is otherwise valid; this proves the earlier, prerequisite-failed
    # stage-set check now wins first when it is not.
    origin52 = root / 'origin52'
    origin52.mkdir()
    git(origin52, 'init', '-q')
    git(origin52, 'checkout', '-q', '-b', 'develop')
    (origin52 / '.ai-dev-workflow.yaml').write_text(coherent_shared)
    git(origin52, 'add', '-A')
    git(origin52, '-c', 'user.name=Test', '-c', 'user.email=test@example.test', 'commit', '-qm', 'commit1: coherent shared config requiring coderabbit')
    remote52 = root / 'remote52.git'
    subprocess.run(['git', 'clone', '-q', '--bare', str(origin52), str(remote52)], check=True)
    git(remote52, 'config', 'uploadpack.allowFilter', 'true')
    git(remote52, 'config', 'uploadpack.allowAnySHA1InWant', 'true')
    repo52 = root / 'repo52'
    subprocess.run(
        ['git', 'clone', '-q', '--filter=blob:none', '--no-checkout', f'file://{remote52}', str(repo52)],
        check=True,
    )
    rc, data, out, err = run(
        repo52, '--mode', 'pre-dispatch', '--target-base', 'develop',
        expected=2,
    )
    check(
        'T-52 an omitted --remaining-stages is prerequisite-failed even when the base config blob is unreadable, not a tooling failure',
        data.get('OUTCOME') == 'prerequisite-failed',
        f'rc={rc} data={data} err={err}',
    )
    check(
        'T-52 prerequisite_detail names the unresolved stage set, not a config-read failure',
        'lifecycle stages' in data.get('PREREQUISITE_DETAIL', ''),
        data,
    )

    # T-53 (#1561 round-10 finding, P2): the --json report renderer must be
    # bounded the same way the text-report renderer already is, not run
    # jq unboundedly after classification has completed. Fake jq to stall
    # specifically on the `--argjson elapsed` invocation this renderer
    # uses (identifiable by its own distinct flag, so every OTHER jq call
    # this script makes still delegates to the real binary), with a tight
    # budget: the run must still reach a bounded, fail-closed outcome
    # (exit 3) well within the test's own subprocess timeout, not hang for
    # the fake's full stall duration.
    repo53 = root / 'repo53'
    write_repo(repo53, coherent_shared, coherent_coderabbit)
    bins53 = root / 'bin53'
    bins53.mkdir(exist_ok=True)
    real_jq53 = shutil.which('jq')
    stalled_jq53 = bins53 / 'jq'
    stalled_jq53.write_text(
        '#!/bin/bash\n'
        'for arg in "$@"; do [ "$arg" = --argjson ] && is_argjson=1; done\n'
        'if [ "${is_argjson:-0}" = 1 ]; then\n'
        '  for arg in "$@"; do [ "$arg" = elapsed ] && sleep 10; done\n'
        'fi\n'
        f'exec {real_jq53!r} "$@"\n'
    )
    stalled_jq53.chmod(0o755)
    started53 = time.monotonic()
    rc, data, out, err = run(
        repo53, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        '--json',
        env={
            'PATH': f'{bins53}:{os.environ.get("PATH", "")}',
            'WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE': '1',
            'WORKFLOW_REVIEWER_PREFLIGHT_BUDGET_SECONDS': '2',
            'WORKFLOW_REVIEWER_PREFLIGHT_PER_PLATFORM_CAP_SECONDS': '1',
        },
        expected=3,
    )
    elapsed53 = time.monotonic() - started53
    check('T-53 a stalled JSON-report jq is bounded, not left to run its full stall duration', elapsed53 <= 8.0, elapsed53)
    check('T-53 failure message names the JSON report render failure', 'cannot render the JSON report' in err, err)

    # T-54 (#1561 round-11 finding, P2): required dependencies must be
    # checked BEFORE any validation or reporting path can reach them.
    # is_option_or_refspec_like's own `git check-ref-format` call used to
    # run ahead of the dependency loop: with git genuinely unresolvable, a
    # perfectly valid --target-base like "develop" was misclassified as
    # prerequisite-failed (exit 2, a run-input verdict) instead of the
    # documented tooling failure (exit 3) a missing dependency actually
    # is. Use a minimal, curated PATH (not merely a shadowing prepend) so
    # git is genuinely unresolvable via `command -v git`, not just a
    # faked binary that would still satisfy have_cmd.
    bins54 = root / 'bin54'
    bins54.mkdir(exist_ok=True)
    stub_python54 = bins54 / 'python3'
    stub_python54.write_text('#!/bin/bash\nexit 0\n')
    stub_python54.chmod(0o755)
    (bins54 / 'dirname').symlink_to(shutil.which('dirname'))
    repo54 = root / 'repo54'
    repo54.mkdir(exist_ok=True)
    rc, data, out, err = run(
        repo54, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={'PATH': str(bins54)},
        expected=3,
    )
    check(
        'T-54 a genuinely-missing git is reported as a tooling failure, not prerequisite-failed on a valid branch name',
        'OUTCOME' not in data,
        f'rc={rc} data={data} err={err}',
    )
    check('T-54 failure message names the missing dependency', 'missing dependency: git' in err, err)

    # T-55 (#1561 round-11 finding, P2): the resolver-output field reads
    # (LOCAL_OVERRIDE_FILE/LOCAL_OVERRIDE_ORIGIN) and the subsequent
    # local_review_override_applied probe used to run unbounded — a
    # stalled filesystem or malfunctioning jq wrapper could hang an
    # already-bounded preflight indefinitely before classification. Fake
    # jq to stall specifically on a `.LOCAL_OVERRIDE_FILE` filter
    # (identifiable by its own distinct string, so every other jq call
    # this script makes still delegates to the real binary); the run must
    # still reach a bounded, fail-closed outcome well within the test's
    # own subprocess timeout.
    repo55 = root / 'repo55'
    write_repo(repo55, coherent_shared, coherent_coderabbit)
    bins55 = root / 'bin55'
    bins55.mkdir(exist_ok=True)
    real_jq55 = shutil.which('jq')
    stalled_jq55 = bins55 / 'jq'
    stalled_jq55.write_text(
        '#!/bin/bash\n'
        'for arg in "$@"; do case "$arg" in *LOCAL_OVERRIDE_FILE*) sleep 10;; esac; done\n'
        f'exec {real_jq55!r} "$@"\n'
    )
    stalled_jq55.chmod(0o755)
    started55 = time.monotonic()
    rc, data, out, err = run(
        repo55, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={
            'PATH': f'{bins55}:{os.environ.get("PATH", "")}',
            'WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE': '1',
            'WORKFLOW_REVIEWER_PREFLIGHT_BUDGET_SECONDS': '2',
            'WORKFLOW_REVIEWER_PREFLIGHT_PER_PLATFORM_CAP_SECONDS': '1',
        },
        expected=3,
    )
    elapsed55 = time.monotonic() - started55
    check('T-55 a stalled resolver-output jq is bounded, not left to run its full stall duration', elapsed55 <= 8.0, elapsed55)
    check('T-55 failure message names the LOCAL_OVERRIDE_FILE/LOCAL_OVERRIDE_ORIGIN parse failure', 'cannot read LOCAL_OVERRIDE_FILE' in err, err)

    # T-56 (#1561 round-12 finding, P1): a non-empty but malformed
    # --remaining-stages CSV (only whitespace/separators, e.g. ",,") does
    # not match the CLI's own explicit-empty-stages short-circuit (that
    # requires the raw value to be exactly ""), so it reaches the early
    # stage-set validation added in round-8 — which must reject it as
    # prerequisite-failed, not silently normalize it to no-review-remaining
    # (exit 0, no reviewer checks at all despite malformed input).
    repo56 = root / 'repo56'
    write_repo(repo56, coherent_shared, coherent_coderabbit)
    rc, data, out, err = run(
        repo56, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', ',,',
        expected=2,
    )
    check(
        'T-56 a malformed non-empty --remaining-stages CSV is prerequisite-failed, not no-review-remaining',
        data.get('OUTCOME') == 'prerequisite-failed',
        f'rc={rc} data={data} err={err}',
    )
    check(
        'T-56 prerequisite_detail names the unresolved/malformed stage set',
        'lifecycle stages' in data.get('PREREQUISITE_DETAIL', ''),
        data,
    )

    # T-57 (#1561 round-13 finding, P2): is_option_or_refspec_like's own
    # `git check-ref-format` call — the very first git subprocess this
    # script runs, ahead of clamp_bound_floor and the mktemp-created
    # work_dir — must be bounded like every other read. Fake git to stall
    # specifically on check-ref-format (identifiable by its own distinct
    # subcommand argv, so ls-remote and every other git call this script
    # makes still delegates to the real binary), with a tight budget: the
    # run must reach a bounded, fail-closed outcome well within the test's
    # own subprocess timeout, not hang for the fake's full stall duration.
    repo57 = root / 'repo57'
    write_repo(repo57, coherent_shared, coherent_coderabbit)
    bins57 = root / 'bin57'
    bins57.mkdir(exist_ok=True)
    real_git57 = shutil.which('git')
    stalled_git57 = bins57 / 'git'
    stalled_git57.write_text(
        '#!/bin/bash\n'
        'for arg in "$@"; do [ "$arg" = check-ref-format ] && sleep 10; done\n'
        f'exec {real_git57!r} "$@"\n'
    )
    stalled_git57.chmod(0o755)
    started57 = time.monotonic()
    rc, data, out, err = run(
        repo57, '--mode', 'pre-dispatch', '--target-base', 'develop',
        '--remaining-stages', 'on_draft.github', '--pr-state', 'on_draft.github=draft',
        env={
            'PATH': f'{bins57}:{os.environ.get("PATH", "")}',
            'WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE': '1',
            'WORKFLOW_REVIEWER_PREFLIGHT_BUDGET_SECONDS': '2',
            'WORKFLOW_REVIEWER_PREFLIGHT_PER_PLATFORM_CAP_SECONDS': '1',
        },
        expected=3,
    )
    elapsed57 = time.monotonic() - started57
    check('T-57 a stalled check-ref-format probe is bounded, not left to run its full stall duration', elapsed57 <= 8.0, elapsed57)
    check('T-57 failure message names the check-ref-format probe timeout', 'check-ref-format probe did not complete' in err, err)

print(f'\nPassed: {passed}')
PY

#!/usr/bin/env bash
# covers: scripts/development-workflow/resolve-reviewer-availability.sh
# covers: scripts/development-workflow/workflow-config-resolver.py scripts/development-workflow/workflow-lib.sh
# Hermetic PATHs; all reviewer commands and GitHub calls are fake.
set -euo pipefail
SCRIPT_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
python3 - "$SCRIPT_DIR/.." <<'PY'
import json, os, pathlib, shlex, shutil, signal, subprocess, sys, tempfile, time

scripts = pathlib.Path(sys.argv[1]).resolve()
helper = scripts / 'resolve-reviewer-availability.sh'
real_python = sys.executable
bash = '/bin/bash'
passed = 0
outputs = []

def check(name, condition, detail=''):
    global passed
    if not condition:
        raise AssertionError(f'{name}: {detail}')
    passed += 1
    print(f'PASS: {name}', flush=True)

with tempfile.TemporaryDirectory(prefix='availability-tests-') as tmp:
    root = pathlib.Path(tmp).resolve()
    repo = root / 'repository with spaces'
    repo.mkdir()
    bins = root / 'bin'
    bins.mkdir()
    for command in ('bash','sh','cat','chmod','date','dirname','jq','mktemp','perl','rm','sleep','touch'):
        executable = shutil.which(command)
        if executable:
            (bins / command).symlink_to(executable)
    def restore_python():
        # Execute the original interpreter path so virtualenv packages remain
        # visible; relocating its symlink makes Python lose pyvenv.cfg.
        launcher = bins / 'python3'
        launcher.write_text('#!/bin/bash\nexec '+shlex.quote(real_python)+' "$@"\n')
        launcher.chmod(0o755)
    restore_python()
    env = {**os.environ, 'PATH':str(bins), 'TMPDIR':str(root)}
    for key in list(env):
        if key.startswith(('WORKFLOW_REVIEWER_AVAILABILITY_', 'CODEX_GITHUB_')) or key == 'WORKFLOW_RUNNER_KIND':
            del env[key]
    cfg = repo / '.ai-dev-workflow.yaml'
    local = repo / '.ai-dev-workflow.local.yaml'
    log = root / 'gh.log'
    activity = root / 'activity.json'

    def fake(command, body):
        path = bins / command
        path.unlink(missing_ok=True)  # Never follow a dependency symlink when writing a fake.
        if command == 'python3':
            # Fake the requested config parser, not the Linux process supervisor
            # that bounds and reaps that parser. A hanging target stays bounded.
            body = (f'if [ "$1" = -B ] && [ "$2" = -c ] && [[ "$3" == "# Step 7a Linux probe supervisor"* ]]; then exec {real_python!r} "$@"; fi\n' + body)
        path.write_text('#!/bin/bash\n'+body+'\n')
        path.chmod(0o755)

    def reset(runners='[codex]', policy=None):
        for command in ('claude','cursor-agent','codex','gh','python3'):
            (bins / command).unlink(missing_ok=True)
        restore_python()
        local.unlink(missing_ok=True)
        (repo / '.git').unlink(missing_ok=True) if (repo / '.git').is_file() else None
        (repo / '.coderabbit.yaml').write_text('reviews:\n  auto_review:\n    enabled: true\n')
        cfg.write_text('review:\n' + (f'  on_draft:\n    runner: {runners}\n' if runners is not None else '') + (f'  internal_reviewers_unavailable_policy: {policy}\n' if policy is not None else ''))
        log.write_text('')
        activity.write_text('[]')

    def gh(comments=None, body=None):
        if comments is not None:
            activity.write_text(json.dumps(comments))
        fake('gh', f'printf "%s\\n" "$*" >> {str(log)!r}\n'+ (body or f'cat {str(activity)!r}'))

    def run(driver='claude', expected=0, extra_env=None, arguments=None, closed_stdin=False):
        started = time.monotonic()
        result = subprocess.run(
            [bash,str(helper), '--repo-root',str(repo), '--owner','example','--repo','test', '--runner-kind',driver] if arguments is None else [bash,str(helper),*arguments],
            env={**env,**(extra_env or {})}, text=True, capture_output=True, timeout=12,
            stdin=subprocess.DEVNULL if closed_stdin else None,
        )
        elapsed = time.monotonic()-started
        assert elapsed <= 10.0, (elapsed,result.stdout,result.stderr)
        assert result.returncode == expected, (result.returncode,expected,result.stdout,result.stderr)
        rows = result.stdout.splitlines()
        assert all('=' in row for row in rows), result.stdout
        data = dict(row.split('=',1) for row in rows)
        assert len(data)==len(rows), result.stdout
        if 'OUTCOME' in data:
            assert float(data['ELAPSED_SECONDS']) <= 10.0
            outputs.append(data)
        return data

    def value(data, key, expected):
        assert data.get(key)==expected, (key,data.get(key),expected,data)

    reset(); fake('codex','exit 0'); d=run()
    check('T-1 cross-runtime callable', d['REVIEWER_1_STATUS']=='reachable' and d['REVIEWER_1_REASON']==d['REVIEWER_1_REMEDY']=='' and d['REVIEWER_COUNT']=='1')
    (bins/'codex').unlink();d=run(expected=1)
    check('T-2 runtime absent / guard plant', d['REVIEWER_1_REASON']=='runtime-absent' and d['BLOCK_CAUSE']=='zero-reachable')
    fake('codex','exit 0');check('T-2 repaired guard', run()['OUTCOME']=='proceeded')
    reset('[claude]');check('T-3 native without CLI', run()['REVIEWER_1_STATUS']=='reachable')
    check('T-4 other runner absent',run('cursor',1)['REVIEWER_1_REASON']=='runtime-absent')
    reset();fake('codex','exit 1');check('T-5 error is inconclusive',run(expected=1)['REVIEWER_1_REASON']=='check-inconclusive')
    fake('codex','sleep 30');d=run(expected=1,extra_env={'WORKFLOW_REVIEWER_AVAILABILITY_TEST_MODE':'1','WORKFLOW_REVIEWER_AVAILABILITY_BUDGET_SECONDS':'2'})
    check('T-6 probe bound', 'bound' in d['REVIEWER_1_DETAIL'])
    reset('[claude, cursor, codex, coderabbit, codex-github]')
    for binary in ('claude','cursor-agent','codex'): fake(binary,'sleep 30')
    gh(body='sleep 30');d=run('unknown',1)
    check('T-7 exact ten-second ceiling',d['REVIEWER_COUNT']=='5' and d['BUDGET_SECONDS']=='8')
    reset('[not-a-reviewer]');d=run(expected=1)
    check('T-8 unsupported',d['REVIEWER_1_NAME']=='not-a-reviewer' and d['REVIEWER_1_REASON']=='value-not-supported')
    reset('[not-a-reviewer, codex]');fake('codex','exit 0');d=run();check('T-9 reduced',d['OUTCOME']=='proceeded-reduced')
    reset(None);check('T-10 absent fallback',run()['FALLBACK_APPLIED']=='true')
    reset('[]');check('T-11 empty fallback',run()['CONFIG_LIST_STATE']=='empty')
    check('T-12 unknown fallback blocked',run('unknown',1)['BLOCK_CAUSE']=='no-driving-runner')
    reset('codex');check('T-13 malformed plant',run('codex',1)['BLOCK_CAUSE']=='list-malformed')
    reset('[codex]');check('T-13 repaired guard',run('codex')['OUTCOME']=='proceeded')
    # A genuinely clean git fixture, with outputs/temporary artifacts outside it.
    subprocess.run(['git','init','-q',str(repo)],check=True)
    subprocess.run(['git','-C',str(repo),'add','.'],check=True)
    subprocess.run(['git','-C',str(repo),'-c','user.name=Test','-c','user.email=test@example.test','commit','-qm','fixture'],check=True)
    run('codex')
    check('T-14 tracked checkout purity',subprocess.check_output(['git','-C',str(repo),'status','--porcelain'])==b'')
    shutil.rmtree(repo/'.git')
    reset('[codex-github]');gh([{'user':{'login':'chatgpt-codex-connector[bot]'}}]);run()
    check('T-15 GET-only purity', log.read_text().splitlines()==['api repos/example/test/issues/comments?per_page=100&sort=created&direction=desc'])
    reset('[not-a-reviewer, codex]','fail-if-any-unavailable');fake('codex','exit 0');d=run(expected=1)
    check('T-16 strict plant',d['BLOCK_CAUSE']=='policy-forbids-reduced-coverage' and d['REVIEWER_2_STATUS']=='reachable')
    cfg.write_text(cfg.read_text().replace('fail-if-any-unavailable','warn'));check('T-16 repaired policy',run()['OUTCOME']=='proceeded-reduced')
    reset(None,'maybe');d=run('codex',1);check('T-17 policy before fallback',d['CONFIG_LIST_STATE']=='not-evaluated' and d['POLICY']=='')
    reset(None);d=run('codex');check('T-18 default repair',d['POLICY_SOURCE']=='default' and d['OUTCOME']=='proceeded')
    reset('[codex, cursor]');d=run('codex');check('T-18 mixed default',d['POLICY_SOURCE']=='default' and d['OUTCOME']=='proceeded-reduced')
    reset('[claude, cursor, codex]');local.write_text('review:\n  on_draft:\n    runner: [codex]\n');d=run('codex')
    check('T-19 override exclusions',d['OVERRIDE_EXCLUDED']=='claude,cursor' and d['UNREACHABLE']=='')
    d=run('unknown',1);check('T-20 resolved override origin',str(local) in d['LOCAL_OVERRIDE_STATE'] and 'applied' in d['LOCAL_OVERRIDE_STATE'])
    reset('[coderabbit]');gh([{'user':{'login':'coderabbitai[bot]'}}]);check('T-21 hosted enabled with closed stdin via fallback',run(closed_stdin=True)['REVIEWER_1_STATUS']=='reachable')
    gh([]);check('T-22 hosted disabled with closed stdin via fallback',run(expected=1,closed_stdin=True)['REVIEWER_1_REASON']=='prerequisite-missing')
    # A GNU timeout path backgrounds the bounded command too. The enablement
    # program must not rely on the caller's stdin in either launch strategy.
    fake('timeout', '''if [ "$1" = --version ]; then echo 'timeout (GNU coreutils) fixture'; exit 0; fi
case "$1" in --kill-after=*) shift ;; esac
shift
exec "$@"''')
    gh([{'user':{'login':'coderabbitai[bot]'}}]);check('T-22 hosted enabled with closed stdin via GNU timeout',run(closed_stdin=True)['REVIEWER_1_STATUS']=='reachable')
    gh([]);check('T-22 hosted disabled with closed stdin via GNU timeout',run(expected=1,closed_stdin=True)['REVIEWER_1_REASON']=='prerequisite-missing')
    (bins/'timeout').unlink()
    # The enablement reader follows only the target mapping path. Valid
    # CodeRabbit block scalars elsewhere must not make that path unreadable.
    (repo/'.coderabbit.yaml').write_text('''reviews:
  path_instructions:
    - path: src/**
      instructions: |
        Explain the module.
        \tKeep this literal tab after required spaces.
  auto_review:
    enabled: true
''')
    gh([{'user':{'login':'coderabbitai[bot]'}}]);check('T-22 multiline path instructions before target',run(closed_stdin=True)['REVIEWER_1_STATUS']=='reachable')
    (repo/'.coderabbit.yaml').write_text('''reviews:
  auto_review:
    enabled: true
  path_instructions:
    - path: src/**
      instructions: |
        Explain the module.
        Keep this indentation intact.
''')
    check('T-22 multiline path instructions after target',run(closed_stdin=True)['REVIEWER_1_STATUS']=='reachable')
    (repo/'.coderabbit.yaml').write_text('''reviews:
  auto_review:
    enabled: true
  path_instructions:
    - path: src/**
      instructions: >
        \tThis literal block can contain enabled: false.
''')
    check('T-22 folded path instructions after target with tab',run(closed_stdin=True)['REVIEWER_1_STATUS']=='reachable')
    (repo/'.coderabbit.yaml').write_text('''reviews:
  auto_review:
    enabled: false
  path_instructions:
    - path: src/**
      instructions: |
        \tenabled: true
''')
    check('T-22 literal fake enabled cannot override false target',run(expected=1,closed_stdin=True)['REVIEWER_1_REASON']=='prerequisite-missing')
    (repo/'.coderabbit.yaml').write_text('''reviews:
  auto_review:
  path_instructions:
    - path: src/**
      instructions: |
        enabled: true
''')
    check('T-22 literal fake enabled cannot create missing target',run(expected=1,closed_stdin=True)['REVIEWER_1_REASON']=='prerequisite-missing')
    (repo/'.coderabbit.yaml').write_text('''instructions: |
  reviews:
    auto_review:
      enabled: true
reviews:
  auto_review:
    enabled: false
''')
    check('T-22 nested fake reviews cannot override root false target',run(expected=1,closed_stdin=True)['REVIEWER_1_REASON']=='prerequisite-missing')
    (repo/'.coderabbit.yaml').write_text('''instructions: |
  reviews:
    auto_review:
      enabled: true
reviews:
  auto_review:
''')
    check('T-22 nested fake reviews cannot create root target',run(expected=1,closed_stdin=True)['REVIEWER_1_REASON']=='prerequisite-missing')
    (repo/'.coderabbit.yaml').write_text('reviews:\n  auto_review:\n\tenabled: true\n')
    check('T-22 target tab indentation fails closed',run(expected=1,closed_stdin=True)['REVIEWER_1_REASON']=='check-inconclusive')
    (repo/'.coderabbit.yaml').write_text('reviews:\n  auto_review:\n    enabled: "true"\n')
    check('T-22 text enabled fails closed',run(expected=1,closed_stdin=True)['REVIEWER_1_REASON']=='check-inconclusive')
    (repo/'.coderabbit.yaml').write_text('reviews:\n  auto_review: [\n')
    check('T-22 malformed target fails closed',run(expected=1,closed_stdin=True)['REVIEWER_1_REASON']=='check-inconclusive')
    for separator in ('', 'language: en-US\n', 'other:\n  auto_review:\n    enabled: true\n'):
        (repo/'.coderabbit.yaml').write_text('reviews:\n  auto_review:\n    enabled: true\n' + separator + 'reviews:\n  auto_review:\n    enabled: false\n')
        check(f'T-22 duplicate root reviews after {separator!r} fails closed',run(expected=1)['REVIEWER_1_REASON']=='check-inconclusive')
    cfg.write_text(cfg.read_text() + '  internal_reviewers_unavailable_policy: fail-if-any-unavailable\n')
    d=run(expected=1)
    check('T-22 duplicate root reviews blocks strict policy',d['OUTCOME']=='blocked' and d['POLICY']=='fail-if-any-unavailable' and d['REVIEWER_1_REASON']=='check-inconclusive')
    for enabled,expected,reason in (('true',0,''),('false',1,'prerequisite-missing')):
        (repo/'.coderabbit.yaml').write_text(f'reviews:\n  auto_review:\n    enabled: {enabled}\nother:\n  reviews:\n    auto_review:\n      enabled: true\n')
        check(f'T-22 unrelated nested reviews preserves {enabled}',run(expected=expected)['REVIEWER_1_REASON']==reason)
    for malformed in (
        'reviews:\n  - invalid\n  auto_review:\n    enabled: true\n',
        'reviews:\n- invalid\n  auto_review:\n    enabled: true\n',
        'reviews:\n  auto_review:\n    enabled: true\n  - invalid\n',
        'reviews:\n  auto_review:\n    - invalid\n    enabled: true\n',
        'reviews:\n  auto_review:\n  - invalid\n    enabled: true\n',
        'reviews:\n  auto_review:\n    enabled: true\n    - invalid\n',
        'reviews:\n  broken mapping\n  auto_review:\n    enabled: true\n',
    ):
        (repo/'.coderabbit.yaml').write_text(malformed)
        log.write_text('')
        d=run(expected=1)
        check(f'T-22 malformed mapping blocks strict policy {malformed!r}',d['OUTCOME']=='blocked' and d['POLICY']=='fail-if-any-unavailable' and d['REVIEWER_1_REASON']=='check-inconclusive' and not log.read_text(),d)
    for indentation in ('', '  '):
        for enabled,expected,reason in (('true',0,''),('false',1,'prerequisite-missing')):
            (repo/'.coderabbit.yaml').write_text(f'reviews:\n  path_filters:\n  {indentation}- "src/**"\n  auto_review:\n    enabled: {enabled}\n    labels:\n    {indentation}- ready\n  path_instructions:\n  {indentation}- path: src/**\n    {indentation}instructions: |\n      {indentation}\tenabled: false\n')
            check(f'T-22 valid sibling lists {indentation!r} preserve {enabled}',run(expected=expected)['REVIEWER_1_REASON']==reason)
    for extra in (
        '  path_filters: [\n    "src/**"\n  ]\n',
        '  "path_filters": ["src/**"]\n',
        '  custom.key: true\n',
        '  path_filters: ["src # text", "a]b"]\n',
        '  custom key: true\n',
        '  settings: {\n    text: "[quoted] # text",\n    nested: [one, two]\n  }\n',
    ):
        for placement in ('reviews', 'auto_review'):
            nested = extra if placement == 'reviews' else ''.join('  '+line+'\n' for line in extra.splitlines())
            content = 'reviews:\n'+nested+'  auto_review:\n    enabled: true\n' if placement == 'reviews' else 'reviews:\n  auto_review:\n'+nested+'    enabled: true\n'
            (repo/'.coderabbit.yaml').write_text(content)
            check(f'T-22 valid unrelated YAML {placement} {extra!r}',run()['REVIEWER_1_STATUS']=='reachable')
    for malformed_flow in ('[\n', '[one}\n'):
        (repo/'.coderabbit.yaml').write_text('reviews:\n  auto_review:\n    enabled: true\n  path_filters: '+malformed_flow)
        d=run(expected=1)
        check(f'T-22 malformed flow value fails closed {malformed_flow!r}',d['REVIEWER_1_REASON']=='check-inconclusive' and 'Repair' in d['REVIEWER_1_REMEDY'],d)
    (repo/'.coderabbit.yaml').write_text('reviews:\n  - invalid\n  auto_review:\n    enabled: true\n')
    d=run(expected=1)
    check('T-22 parse error identifies config and actionable repair', '.coderabbit.yaml' in d['REVIEWER_1_DETAIL'] and 'line ' in d['REVIEWER_1_DETAIL'] and 'Repair' in d['REVIEWER_1_REMEDY'],d)
    for invalid_nesting in (
        'reviews:\n  auto_review:\n    enabled: true\n      invalid: value\n',
        'reviews:\n  auto_review:\n    enabled: true\n      - invalid\n',
        'reviews:\n  auto_review:\n    enabled: true\n      continuation\n',
        'reviews:\n  auto_review:\n    enabled: true\n   invalid: value\n',
        'reviews:\n  auto_review:\n    enabled: true\n invalid: value\n',
        'reviews:\n  profile: chill\n    invalid: value\n  auto_review:\n    enabled: true\n',
        'reviews:\n  auto_review:\n    enabled: true\n    drafts: false\n      invalid: value\n',
        'reviews:\n  auto_review:\n    enabled: true\n    labels: [ready]\n      invalid: value\n',
    ):
        for activity_rows in ([], [{'user':{'login':'coderabbitai[bot]'}}]):
            gh(activity_rows);log.write_text('')
            (repo/'.coderabbit.yaml').write_text(invalid_nesting)
            d=run(expected=1)
            check(f'T-22 invalid scalar nesting blocks before activity {invalid_nesting!r} {bool(activity_rows)}', d['REVIEWER_1_REASON']=='check-inconclusive' and d['OUTCOME']=='blocked' and not log.read_text(),d)
    gh([{'user':{'login':'coderabbitai[bot]'}}])
    for valid_nesting in (
        'reviews:\n  profile: a plain\n    multiline scalar\n  auto_review:\n    enabled: true\n    drafts: false\n',
        'reviews:\n  profile: "a quoted\n    multiline scalar"\n  auto_review:\n    enabled: true\n',
        'reviews:\n  auto_review:\n    enabled: true\n    nested:\n      key: value\n  other:\n    nested: true\n',
        'reviews:\n    auto_review:\n        enabled: true\n        drafts: false\n    other: value\n',
    ):
        (repo/'.coderabbit.yaml').write_text(valid_nesting)
        check(f'T-22 valid target nesting preserved {valid_nesting!r}',run()['REVIEWER_1_STATUS']=='reachable')
    for spelling,expected in (('True',0),('TRUE',0),('true',0),('False',1),('FALSE',1),('false',1)):
        (repo/'.coderabbit.yaml').write_text(f'reviews:\n  auto_review:\n    enabled: {spelling}\n')
        d=run(expected=expected)
        check(f'T-22 typed YAML boolean {spelling}',d['REVIEWER_1_STATUS']==('reachable' if expected==0 else 'unreachable') and d['REVIEWER_1_REASON']==('' if expected==0 else 'prerequisite-missing'),d)
    for token in ('"True"', "'TRUE'", '1', '0', 'null', 'yes', 'on', 'tRuE', '!!bool yes', '!!bool nonsense'):
        (repo/'.coderabbit.yaml').write_text(f'reviews:\n  auto_review:\n    enabled: {token}\n')
        log.write_text('');d=run(expected=1)
        check(f'T-22 nonboolean YAML remains invalid {token}',d['REVIEWER_1_REASON']=='check-inconclusive' and not log.read_text(),d)
    for broken in ('broken: "unterminated\n', "broken: 'unterminated\n", 'broken: [one, two\n', 'broken: true\n  invalid: value\n', 'broken: !unsafe value\n', 'broken: *unknown\n', 'broken: one\nbroken: two\n', 'other:\n  duplicate: one\n  duplicate: two\n'):
        for placement in ('before','after'):
            target='reviews:\n  auto_review:\n    enabled: true\n'
            (repo/'.coderabbit.yaml').write_text(broken+target if placement=='before' else target+broken)
            log.write_text('');d=run(expected=1)
            check(f'T-22 invalid whole document {placement} {broken!r}',d['REVIEWER_1_REASON']=='check-inconclusive' and '.coderabbit.yaml' in d['REVIEWER_1_DETAIL'] and not log.read_text(),d)
    for document,expected in (
        ('defaults: &defaults {enabled: false, drafts: true}\nreviews:\n  auto_review:\n    <<: *defaults\n    enabled: TRUE\n',0),
        ('defaults: &defaults {enabled: TRUE}\nreviews:\n  auto_review: *defaults\n',0),
        ('defaults: &defaults {enabled: true}\nreviews:\n  auto_review:\n    <<: *defaults\n    enabled: FALSE\n',1),
        ('description: "quoted multiline\n  with: colon and [brackets]"\nreviews:\n  auto_review: {enabled: True}\n',0),
    ):
        (repo/'.coderabbit.yaml').write_text(document);d=run(expected=expected)
        check(f'T-22 valid whole YAML document {document!r}', d['REVIEWER_1_REASON']==('' if expected==0 else 'prerequisite-missing'),d)
    missing_parser=root/'missing-parser';missing_parser.mkdir()
    (missing_parser/'yaml.py').write_text('raise ImportError("planted unavailable parser")\n')
    (repo/'.coderabbit.yaml').write_text('reviews:\n  auto_review:\n    enabled: true\n')
    log.write_text('');d=run(expected=1,extra_env={'PYTHONPATH':str(missing_parser)})
    check('T-22 missing YAML parser gives setup remedy',d['REVIEWER_1_REASON']=='check-inconclusive' and 'requires PyYAML' in d['REVIEWER_1_DETAIL'] and 'Install PyYAML' in d['REVIEWER_1_REMEDY'] and not log.read_text(),d)
    reset('[codex]');d=run('codex',extra_env={'PYTHONPATH':str(missing_parser)})
    check('T-22 other reviewers do not need YAML parser',d['REVIEWER_1_STATUS']=='reachable',d)
    reset('[coderabbit]');gh([{'user':{'login':'coderabbitai[bot]'}}])
    reset('[codex]');fake('codex','exit 1');d=run(expected=1)
    check('T-22 local failure remedy targets runtime', '--version' in d['REVIEWER_1_REMEDY'] and all(x not in d['REVIEWER_1_REMEDY'] for x in ('gh','PyYAML','.coderabbit')),d)
    fake('codex','sleep 30');d=run(expected=1,extra_env={'WORKFLOW_REVIEWER_AVAILABILITY_TEST_MODE':'1','WORKFLOW_REVIEWER_AVAILABILITY_BUDGET_SECONDS':'2'})
    check('T-22 local timeout remedy targets runtime','codex --version' in d['REVIEWER_1_DETAIL'] and '--version' in d['REVIEWER_1_REMEDY'] and 'gh' not in d['REVIEWER_1_REMEDY'],d)
    for reviewer in ('coderabbit','codex-github'):
        reset('['+reviewer+']');gh(body='exit 1');d=run(expected=1)
        check(f'T-22 hosted activity remedy {reviewer}','gh authentication' in d['REVIEWER_1_REMEDY'] and all(x not in d['REVIEWER_1_REMEDY'] for x in ('PyYAML','.coderabbit','--version')),d)
    reset('[coderabbit]');gh([{'user':{'login':'coderabbitai[bot]'}}])
    (repo/'.coderabbit.yaml').write_text('broken: "unterminated\n')
    d=run(expected=1)
    check('T-22 config remedy targets file','Repair .coderabbit.yaml' in d['REVIEWER_1_REMEDY'] and all(x not in d['REVIEWER_1_REMEDY'] for x in ('gh','PyYAML','--version')),d)
    (repo/'.coderabbit.yaml').write_text('reviews:\n  auto_review:\n    enabled: true\n')
    d=run(expected=1,extra_env={'PYTHONPATH':str(missing_parser)})
    check('T-22 dependency remedy targets install','Install PyYAML' in d['REVIEWER_1_REMEDY'] and all(x not in d['REVIEWER_1_REMEDY'] for x in ('gh','Repair','--version')),d)
    fake('python3', 'if [ "$1" = -B ] && [ "$2" = -c ]; then exit 1; fi\nexec '+shlex.quote(real_python)+' "$@"')
    d=run(expected=1)
    check('T-22 parser execution remedy targets python','configuration check with the gate python3' in d['REVIEWER_1_REMEDY'] and all(x not in d['REVIEWER_1_REMEDY'] for x in ('gh','Repair','Install')),d)
    # Exhaust the budget before dispatch, independently of timeout/SECONDS
    # rounding. Delay only the final list decode, after bounded config parsing.
    reset('[codex, cursor]')
    runtime_started=root/'budget-runtime-started'
    for binary in ('codex','cursor-agent'):
        fake(binary,'touch '+shlex.quote(str(runtime_started)))
    real_jq=str((bins/'jq').resolve())
    fake('jq', 'if [ "$1" = -j ] && [[ "$2" == ".effective_runner[]"* ]]; then sleep 4; fi\nexec '+shlex.quote(real_jq)+' "$@"')
    try:
        d=run(expected=1,extra_env={'WORKFLOW_REVIEWER_AVAILABILITY_TEST_MODE':'1','WORKFLOW_REVIEWER_AVAILABILITY_BUDGET_SECONDS':'3'})
    finally:
        (bins/'jq').unlink()
        (bins/'jq').symlink_to(real_jq)
    check('T-22 unstarted probe remedy targets budget',not runtime_started.exists() and d['REVIEWER_2_DETAIL']=='availability budget exhausted before this check started' and 'budget' in d['REVIEWER_2_REMEDY'] and all(x not in d['REVIEWER_2_REMEDY'] for x in ('gh','PyYAML','.coderabbit')),d)
    reset('[coderabbit]');gh([{'user':{'login':'coderabbitai[bot]'}}])
    (bins/'gh').unlink();check('T-23 missing gh',run(expected=1)['REVIEWER_1_REASON']=='check-inconclusive')
    reset('[codex-github]');gh([{'user':{'login':'special'}}]);check('T-24 hosted login suffix',run('cursor',extra_env={'CODEX_GITHUB_BOT_LOGIN':'special[bot]'})['REVIEWER_1_STATUS']=='reachable')
    d=run(expected=2,arguments=['--repo-root',str(repo)])
    check('T-26 invocation failure has no verdict','OUTCOME' not in d)
    for source in (cfg,local):
        for scalar in ('a: b','a:', 'https://example.test: invalid'):
            reset();source.write_text('broken: '+scalar+'\nreview:\n  on_draft:\n    runner: [codex]\n')
            d=run('codex',1)
            check(f'T-31 plain mapping delimiter blocks {source.name} {scalar}',d['BLOCK_CAUSE']=='policy-unreadable' and d['REVIEWER_COUNT']=='0',d)
        for scalar in ('"a: b"', "'a: b'", 'https://example.test/path#part', 'value#fragment', 'value # ignored: comment', '["a: b", https://example.test]'):
            reset();source.write_text('other: '+scalar+'\nreview:\n  on_draft:\n    runner: [codex]\n')
            check(f'T-31 valid scalar controls {source.name} {scalar}',run('codex')['REVIEWER_1_STATUS']=='reachable')
    for source in (cfg, local):
        for flow in ['[a[b]', '[a]b]', '[a[b]]', '[a{b}]', '[a}b]', '[[a,b]', '[[a], b]]', '[[] []]', '[{}x]', '["a"b]', '["a[b]"', '[a "b[c"]', ']', '}', ',bad']:
            reset();source.write_text('other: '+flow+'\nreview:\n  on_draft:\n    runner: [codex]\n')
            d=run('codex',1)
            check(f'T-31 malformed flow blocks {source.name} {flow}',d['BLOCK_CAUSE']=='policy-unreadable' and d['REVIEWER_COUNT']=='0',d)
        for flow in ['["a[b]", "a]b"]', "['a{b}', 'a}b']", '[[a, b], [c, d]]', '[[], {}, [a, [b, c]]]', '[["a: b", https://example.test], ["x,y"]]', '["escaped\\"[", \'doubled\'\'[\']', 'a[b', 'a]b', 'a[b]', 'a{b}', 'a,b']:
            reset();source.write_text('other: '+flow+'\nreview:\n  on_draft:\n    runner: [codex]\n')
            check(f'T-31 valid flow and block control {source.name} {flow}',run('codex')['REVIEWER_1_STATUS']=='reachable')
    for source in (cfg, local):
        for token in ('nUlL','NuLl','tRuE','fAlSe'):
            reset();source.write_text('review:\n  internal_reviewers_unavailable_policy: '+token+'\n')
            d=run('codex',1)
            check(f'T-31 mixed-case policy stays unsupported {source.name} {token}',d['BLOCK_CAUSE']=='policy-unsupported' and d['POLICY_INPUT']==token,d)
            reset();source.write_text('review:\n  on_draft:\n    runner: '+token+'\n')
            d=run('codex',1)
            check(f'T-31 mixed-case runner never falls back {source.name} {token}',d['BLOCK_CAUSE']=='list-malformed' and d['FALLBACK_APPLIED']=='false',d)
            reset();source.write_text('review:\n  on_draft:\n    runner: ['+token+', codex]\n')
            d=run('codex')
            check(f'T-31 mixed-case list member stays string {source.name} {token}',d['OUTCOME']=='proceeded-reduced' and d['REVIEWER_1_NAME']==token and d['REVIEWER_1_REASON']=='value-not-supported',d)
        for token in ('null','Null','NULL','~'):
            reset();source.write_text('review:\n  internal_reviewers_unavailable_policy: '+token+'\n')
            d=run('codex')
            check(f'T-31 canonical null policy defaults {source.name} {token}',d['POLICY_STATE']=='empty' and d['POLICY']=='warn',d)
            reset();source.write_text('review:\n  on_draft:\n    runner: '+token+'\n')
            d=run('codex')
            check(f'T-31 canonical null runner falls back {source.name} {token}',d['CONFIG_LIST_STATE']=='empty' and d['FALLBACK_APPLIED']=='true',d)
        for token in ('True','FALSE'):
            reset();source.write_text('review:\n  internal_reviewers_unavailable_policy: '+token+'\n')
            d=run('codex',1)
            check(f'T-31 canonical boolean policy stays nonstring {source.name} {token}',d['BLOCK_CAUSE']=='policy-unreadable',d)
            reset();source.write_text('review:\n  on_draft:\n    runner: ['+token+', codex]\n')
            d=run('codex',1)
            check(f'T-31 canonical boolean member stays nonstring {source.name} {token}',d['BLOCK_CAUSE']=='list-malformed',d)
    for source in (cfg, local):
        for flow in ('[codex,#]', '[#]', '[codex,#name]', '[[#name],codex]', '[codex, #name]', '[codex,\t#name]'):
            reset();source.write_text('review:\n  on_draft:\n    runner: '+flow+'\n')
            d=run('codex',1)
            check(f'T-31 hash flow node blocks {source.name} {flow!r}',d['BLOCK_CAUSE']=='policy-unreadable' and d['REVIEWER_COUNT']=='0',d)
        for token in ("'#'", '"#name"', 'a#name', 'https://example.test/#part'):
            reset();source.write_text('review:\n  on_draft:\n    runner: [codex,'+token+'] # comment\n')
            d=run('codex')
            check(f'T-31 literal hash remains reportable {source.name} {token}',d['OUTCOME']=='proceeded-reduced' and d['REVIEWER_1_STATUS']=='reachable' and d['REVIEWER_2_NAME']==token.strip("\"'"),d)
    for source in (cfg, local):
        for token in ('foo "', "foo '", 'foo "#literal', "foo '#literal"):
            for suffix in ('', ' # comment', '\t# comment'):
                reset();source.write_text('review:\n  on_draft:\n    runner: ['+token+', codex]'+suffix+'\n')
                d=run('codex')
                check(f'T-31 plain quote preserves comment {source.name} {token!r} {suffix!r}',d['OUTCOME']=='proceeded-reduced' and d['REVIEWER_1_NAME']==token and d['REVIEWER_2_NAME']=='codex' and d['REVIEWER_2_STATUS']=='reachable',d)
        for node, expected in ((r'"escaped\" #literal"', 'escaped" #literal'), ("'doubled'' #literal'", "doubled' #literal")):
            reset();source.write_text('review:\n  on_draft:\n    runner: ['+node+', codex] # comment\n')
            d=run('codex')
            check(f'T-31 quoted literal hash preserves comment {source.name} {node}',d['OUTCOME']=='proceeded-reduced' and d['REVIEWER_1_NAME']==expected,d)
    for source in (cfg, local):
        for char in ('\x00', '\x07', '\x0b', '\x7f', '\x9f', '\ufffe', '\uffff'):
            for extra in ('# comment '+char, 'other: x'+char, 'other: "x'+char+'"'):
                reset();source.write_text(extra+'\nreview:\n  on_draft:\n    runner: [codex]\n')
                d=run('codex',1)
                check(f'T-31 raw control blocks {source.name} {extra!r}',d['BLOCK_CAUSE']=='policy-unreadable' and d['REVIEWER_COUNT']=='0',d)
        for escaped in (r'\a', r'\x07', r'\u0007', r'\t'):
            reset();source.write_text('other: "'+escaped+'" # valid escape\nreview:\n  on_draft:\n    runner: [codex]\n')
            d=run('codex')
            check(f'T-31 valid escaped control proceeds {source.name} {escaped}',d['OUTCOME']=='proceeded',d)
    for source in (cfg, local):
        for token in ('?\tfoo', '-\tfoo', ':\tfoo'):
            reset();source.write_text('review:\n  on_draft:\n    runner: [codex, '+token+']\n')
            d=run('codex',1)
            check(f'T-31 tab node indicator blocks {source.name} {token!r}',d['BLOCK_CAUSE']=='policy-unreadable' and d['REVIEWER_COUNT']=='0',d)
            for quote in ("'", '"'):
                reset();source.write_text('review:\n  on_draft:\n    runner: [codex, '+quote+token+quote+']\n')
                d=run('codex')
                check(f'T-31 quoted tab node stays reportable {source.name} {quote} {token!r}',d['OUTCOME']=='proceeded-reduced' and d['REVIEWER_2_NAME']==token.replace('\t',r'\t') and d['REVIEWER_2_REASON']=='value-not-supported',d)
    for source in (cfg, local):
        for space in ('\u00a0', '\u2003', '\u3000'):
            for token in (space, 'warn'+space+'#literal', space+'warn', 'warn'+space):
                reset();source.write_text('review:\n  internal_reviewers_unavailable_policy: '+token+'\n')
                d=run('codex',1)
                check(f'T-31 Unicode policy stays unsupported {source.name} {token!r}',d['BLOCK_CAUSE']=='policy-unsupported' and d['POLICY_INPUT']==token,d)
            for token in (space, 'codex'+space+'#literal'):
                reset();source.write_text('review:\n  on_draft:\n    runner: ['+token+']\n')
                d=run('codex',1)
                check(f'T-31 Unicode runner stays unsupported {source.name} {token!r}',any(d[f'REVIEWER_{n}_NAME']==token and d[f'REVIEWER_{n}_REASON']=='value-not-supported' for n in range(1,int(d['REVIEWER_COUNT'])+1)) and d['FALLBACK_APPLIED']=='false',d)
        for token in ('warn #comment', 'warn\t#comment', '"warn" #comment'):
            reset();source.write_text('review:\n  internal_reviewers_unavailable_policy: '+token+'\n')
            d=run('codex')
            check(f'T-31 ASCII policy comment {source.name} {token!r}',d['POLICY']=='warn' and d['POLICY_STATE']=='defined',d)
    for source in (cfg, local):
        for scalar in ('%reserved', '%', '[%reserved]', '[[%reserved]]'):
            reset();source.write_text('other: '+scalar+'\nreview:\n  on_draft:\n    runner: [codex]\n  internal_reviewers_unavailable_policy: fail-if-any-unavailable\n')
            d=run('codex',1)
            check(f'T-31 reserved percent blocks {source.name} {scalar}',d['BLOCK_CAUSE']=='policy-unreadable' and d['REVIEWER_COUNT']=='0',d)
        for scalar in ('"%reserved"', "'%reserved'", '["%reserved"]', 'value%part', 'https://example.test/%20'):
            reset();source.write_text('other: '+scalar+'\nreview:\n  on_draft:\n    runner: [codex]\n  internal_reviewers_unavailable_policy: fail-if-any-unavailable\n')
            d=run('codex')
            check(f'T-31 valid percent proceeds {source.name} {scalar}',d['OUTCOME']=='proceeded' and d['REVIEWER_1_STATUS']=='reachable',d)
    reset();cfg.write_text('review:\n  broken mapping\n');d=run('codex',1)
    check('T-31 broken file plant',d['BLOCK_CAUSE']=='policy-unreadable' and d['CONFIG_LIST_STATE']=='not-evaluated')
    reset();check('T-31 repaired availability guard',run('codex')['OUTCOME']=='proceeded')
    reset();a=run(expected=1);fake('codex','exit 0');b=run();(bins/'codex').unlink();c=run(expected=1)
    check('T-32 fresh absent/present/absent',[x['REVIEWER_1_STATUS'] for x in (a,b,c)]==['unreachable','reachable','unreachable'])
    shipped=(scripts.parent.parent/'.ai-dev-workflow.yaml').read_text()
    for driver in ('claude','cursor','codex'):
        reset();cfg.write_text(shipped);d=run(driver)
        check(f'T-33 / T-44 shipped native {driver}',d['OUTCOME']!='blocked' and driver in d['REACHABLE'].split(','))
    reset('[claude,cursor,codex]');main=root/'main';wtgit=main/'.git/worktrees/linked';wtgit.mkdir(parents=True)
    (wtgit/'commondir').write_text('../..\n');(repo/'.git').write_text(f'gitdir: {wtgit}\n')
    (main/'.ai-dev-workflow.local.yaml').write_text('review:\n  on_draft:\n    runner: [codex]\n')
    d=run('codex');check('T-34 main-clone override', 'main_clone' in d['LOCAL_OVERRIDE_STATE'])
    (repo/'.ai-dev-workflow.local.yaml').write_text('product_repos:\n  checkout_root: ../linked-product\n')
    (main/'.ai-dev-workflow.local.yaml').write_text('product_repos:\n  checkout_root: ../main-product\n')
    d=run('codex');check('T-34 linked product-only local files are not review overrides',d['LOCAL_OVERRIDE_STATE']=='none' and d['OUTCOME']=='proceeded-reduced',d)
    (repo/'.ai-dev-workflow.local.yaml').unlink()
    reset('[codex]','[warn]');d=run('codex',1);check('T-35 non-scalar policy',d['POLICY_STATE']=='unreadable' and d['POLICY']=='')
    reset('[codex-github]');gh([{'user':{'login':'chatgpt-codex-connector[bot]'},'created_at':'2000-01-01T00:00:00Z'}]);check('T-38 historical proxy',run()['REVIEWER_1_STATUS']=='reachable')
    for name in ('codex, claude','my reviewer','a, b c',"it's",''):
        reset(json.dumps([name]));d=run(expected=1)
        check(f'T-39 / T-44 lossless {name!r}',d['REVIEWER_COUNT']=='1' and d['REVIEWER_1_NAME']==name and d['CONFIGURED']=='<entry 1>')
    reset();fake('python3','sleep 30');d=run(expected=1)
    check('T-40 config timeout ceiling',d['BLOCK_CAUSE']=='config-resolution-inconclusive' and d['REVIEWER_COUNT']=='0' and d['POLICY_STATE']==d['CONFIG_LIST_STATE']=='not-evaluated')
    fake('python3','echo deliberate-parser-error >&2; exit 2');check('T-41 config invocation error','OUTCOME' not in run(expected=2))
    reset();payload=json.loads(subprocess.check_output([real_python,str(scripts/'workflow-config-resolver.py'),'review-effective','--repo-root',str(repo)]))
    name='bad\tname\nOUTCOME=forged\\tail';payload['effective_runner']=[name]
    payload_file=root/'payload.json';payload_file.write_text(json.dumps(payload));fake('python3',f'cat {str(payload_file)!r}')
    d=run(expected=1);check('T-42 escaped JSON transport',d['REVIEWER_1_NAME']=='bad\\tname\\nOUTCOME=forged\\\\tail' and d['OUTCOME']=='blocked')
    for driver in ('claude','cursor','codex'):
        earlier=[x for x in ('claude','cursor','codex') if x!=driver]
        reset(json.dumps(earlier+[driver,'not-a-reviewer']))
        for binary in ('claude','cursor-agent','codex'):fake(binary,'sleep 30')
        d=run(driver,extra_env={'WORKFLOW_REVIEWER_AVAILABILITY_TEST_MODE':'1','WORKFLOW_REVIEWER_AVAILABILITY_BUDGET_SECONDS':'2'})
        check(f'T-43 native survives budget {driver}',d['REVIEWER_3_STATUS']=='reachable' and d['REVIEWER_4_REASON']=='value-not-supported' and d['OUTCOME']=='proceeded-reduced')
    reset('[claude,cursor,codex]');local.write_text('review:\n  on_draft:\n    runner: []\n');d=run('codex')
    check('T-45 empty override fallback',d['REVIEWER_COUNT']=='3' and d['OVERRIDE_EXCLUDED']=='claude,cursor,codex' and d['FALLBACK_APPLIED']=='true' and not d['UNREACHABLE'])
    for engine in ('fallback', 'timeout-leader-exit'):
        if engine == 'timeout-leader-exit':
            # Mimic GNU timeout's owned group and immediate return when the
            # monitored leader exits on TERM, leaving its descendant alive.
            fake('timeout', """if [ \"$1\" = --version ]; then echo 'timeout (GNU coreutils) fixture'; exit 0; fi
shift
bound=$1
shift
exec perl -e 'setpgrp(0,0) or die; my $bound=shift; $SIG{TERM}="IGNORE"; my $pid=fork(); die unless defined $pid; if (!$pid) {$SIG{TERM}="DEFAULT"; exec @ARGV; die;} my $timed=0; $SIG{ALRM}=sub {$timed=1; kill "TERM", -$$;}; alarm $bound; while (waitpid($pid,0) < 0) {} exit($timed ? 124 : ($? >> 8));' -- "$bound" "$@""" + '"')
        for command,reviewer in (('codex','codex'),('gh','codex-github')):
            reset(f'[{reviewer}]');pidfile=root/'descendant.pid'
            fake(command, f'trap "exit 0" TERM\n( trap "" TERM; sleep 30 ) &\nprintf "%s\\n" "$!" > {str(pidfile)!r}\nwait')
            d=run(expected=1)
            pid=int(pidfile.read_text());gone=False
            for _ in range(30):
                try:os.kill(pid,0)
                except ProcessLookupError:gone=True;break
                time.sleep(.05)
            check(f'T-46 {engine} descendant cleanup {command}',gone and d['REVIEWER_1_REASON']=='check-inconclusive')
    (bins/'timeout').unlink(missing_ok=True)
    if sys.platform.startswith('linux'):
        for discovery,command,reviewer in ((mode,cmd,reviewer) for mode in ('task-children','status-scan') for cmd,reviewer in (('codex','codex'),('gh','codex-github'))):
            reset(f'[{reviewer}]');pidfile=root/'detached.pid'
            pidfile.unlink(missing_ok=True)
            detached = f"import os,pathlib,time; os.setsid(); pathlib.Path({str(pidfile)!r}).write_text(str(os.getpid())); time.sleep(30)"
            # Wait until the child has actually left the original group, then
            # exit the leader successfully. Cleanup must still reap that child.
            fake(command, f'{shlex.quote(real_python)} -c {shlex.quote(detached)} &\nwhile [ ! -s {str(pidfile)!r} ]; do sleep .01; done\nprintf \'%s\\n\' \'[{{"user":{{"login":"chatgpt-codex-connector[bot]"}}}}]\'\nexit 0')
            extra={'WORKFLOW_REVIEWER_AVAILABILITY_TEST_MODE':'1','WORKFLOW_REVIEWER_AVAILABILITY_TEST_NO_PROC_CHILDREN':'1'} if discovery == 'status-scan' else {}
            d=run(extra_env=extra);pid=int(pidfile.read_text());gone=False
            try:os.kill(pid,0)
            except ProcessLookupError:gone=True
            check(f'T-46 {discovery} detached-session descendant cleanup {command}',gone and d['REVIEWER_1_STATUS']=='reachable')
    if sys.platform.startswith('linux'):
        for engine in ('fallback', 'GNU-timeout'):
            (bins/'timeout').unlink(missing_ok=True)
            if engine == 'GNU-timeout':
                (bins/'timeout').symlink_to(shutil.which('timeout'))
            for cancellation in (signal.SIGTERM, signal.SIGINT):
                reset('[codex]');pidfile=root/'cancel-probe.pid';childfile=root/'cancel-child.pid'
                pidfile.unlink(missing_ok=True);childfile.unlink(missing_ok=True)
                descendant=f"import os,pathlib,time; pathlib.Path({str(childfile)!r}).write_text(str(os.getpid())); time.sleep(30)"
                probe=f"import os,pathlib,subprocess,sys,time; subprocess.Popen([sys.executable, '-c', {descendant!r}], start_new_session=True); pathlib.Path({str(pidfile)!r}).write_text(str(os.getpid())); time.sleep(30)"
                fake('codex',f'exec {shlex.quote(real_python)} -c {shlex.quote(probe)}')
                process=subprocess.Popen([bash,str(helper),'--repo-root',str(repo),'--owner','example','--repo','test','--runner-kind','unknown'],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
                owned=[]
                try:
                    deadline=time.monotonic()+5
                    while not (pidfile.exists() and childfile.exists()) and process.poll() is None and time.monotonic()<deadline:
                        time.sleep(.01)
                    assert pidfile.exists() and childfile.exists(), 'probe must start before cancellation'
                    owned=[int(pidfile.read_text()),int(childfile.read_text())]
                    started=time.monotonic();process.send_signal(cancellation)
                    time.sleep(.01)
                    if process.poll() is None:
                        process.send_signal(cancellation)  # Repeated cancellation must not interrupt cleanup.
                    output,error=process.communicate(timeout=3)
                    gone=[]
                    for pid in owned:
                        try:os.kill(pid,0);gone.append(False)
                        except ProcessLookupError:gone.append(True)
                    check(f'T-46 external cancellation reaps {engine} {cancellation.name}',process.returncode==2 and time.monotonic()-started<2.5 and all(gone),(process.returncode,owned,gone,output,error))
                finally:
                    if process.poll() is None:process.kill();process.wait()
                    for pid in owned:
                        try:os.kill(pid,signal.SIGKILL)
                        except ProcessLookupError:pass
        # An unresponsive supervisor still has a bounded owned-group fallback.
        (bins/'timeout').unlink(missing_ok=True)
        reset('[codex]');pidfile=root/'hung-supervisor.pid'
        (bins/'python3').write_text('#!/bin/bash\ntrap "" TERM INT\nprintf "%s" "$$" > '+shlex.quote(str(pidfile))+'\nwhile :; do :; done\n')
        process=subprocess.Popen([bash,str(helper),'--repo-root',str(repo),'--owner','example','--repo','test'],env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
        try:
            deadline=time.monotonic()+3
            while not pidfile.exists() and process.poll() is None and time.monotonic()<deadline:time.sleep(.01)
            assert pidfile.exists(), 'hung supervisor fixture must start'
            started=time.monotonic();process.terminate();output,error=process.communicate(timeout=3)
            gone=False
            try:os.kill(int(pidfile.read_text()),0)
            except ProcessLookupError:gone=True
            check('T-46 external cancellation bounds unresponsive supervisor',process.returncode==2 and gone and time.monotonic()-started<2.5,(output,error))
        finally:
            if process.poll() is None:process.kill();process.wait()
        (bins/'timeout').unlink(missing_ok=True)
    reset();fake('codex','exit 0');fake('timeout','echo "BusyBox timeout"; exit 1')
    check('T-46 non-GNU timeout uses owned-group fallback',run()['REVIEWER_1_STATUS']=='reachable')
    (bins/'timeout').unlink()
    reset('[codex-github]');gh([{'user':{'login':'chatgpt-codex-connector[bot]'}}],body=f'if [ "$1" = auth ]; then sleep 30; else cat {str(activity)!r}; fi')
    run();gh(body='if [ "$1" = auth ]; then sleep 30; else sleep 30; fi');run(expected=1)
    check('T-47 no auth preflight','auth' not in log.read_text())
    reset('[codex]','"bad policy"');d=run(expected=1)
    check('T-48 unsupported raw policy',d['POLICY_INPUT']=='bad policy' and d['POLICY']=='')
    for malformed in ('review:\n  on_draft:\n    runner:[]\n', 'review:\n  on_draft:\n    runner:null\n', 'review:\n  on_draft:{}\n', 'review:{}\n', 'review:\n  internal_reviewers_unavailable_policy:warn\n'):
        reset();cfg.write_text(malformed);d=run('codex',1)
        check(f'T-48 mapping separation blocks fallback {malformed!r}',d['BLOCK_CAUSE']=='policy-unreadable' and d['REVIEWER_COUNT']=='0' and bool(d['UNREADABLE_DETAIL']),d)
    for duplicate in (
        'review:\n  on_draft:\n    runner: [codex-github]\n    runner: []\n',
        'review:\n  on_draft:\n    runner: [codex]\n  internal_reviewers_unavailable_policy: fail-if-any-unavailable\n  internal_reviewers_unavailable_policy: warn\n',
        'review:\n  on_draft:\n    runner: [codex-github]\nreview:\n  on_draft:\n    runner: []\n',
    ):
        for source in (cfg,local):
            reset();source.write_text(duplicate);d=run('codex',1)
            check(f'T-48 duplicate config blocks {source.name} {duplicate!r}',d['BLOCK_CAUSE']=='policy-unreadable' and d['REVIEWER_COUNT']=='0' and d['UNREADABLE_FILE']==str(source) and 'duplicate mapping key' in d['UNREADABLE_DETAIL'],d)
    reset('[codex]','warn#typo');d=run('codex',1)
    check('T-48 hash without separation remains unsupported policy',d['BLOCK_CAUSE']=='policy-unsupported' and d['POLICY_INPUT']=='warn#typo' and d['REVIEWER_COUNT']=='0',d)
    reset('[codex#typo]');d=run('codex',1)
    check('T-48 hash without separation remains reviewer value',d['REVIEWER_1_NAME']=='codex#typo' and d['REVIEWER_1_REASON']=='value-not-supported',d)
    reset('[codex]','warn # ordinary comment');d=run('codex')
    check('T-48 separated comment remains valid policy',d['OUTCOME']=='proceeded' and d['POLICY']=='warn',d)
    reset();cfg.write_text('review:\n  internal_reviewers: [codex-github]\n  internal_reviewers_unavailable_policy: fail-if-any-unavailable\n');gh([]);d=run('codex',1)
    check('T-48 legacy reviewer alias preserves required hosted coverage',d['REVIEWER_1_NAME']=='codex-github' and d['REVIEWER_1_STATUS']=='unreachable' and d['FALLBACK_APPLIED']=='false',d)
    reset();cfg.write_text('review:\n  internal_reviewers: [codex-github]\n  on_draft:\n    runner: []\n');d=run('codex')
    check('T-48 explicit modern empty overrides legacy alias',d['FALLBACK_APPLIED']=='true' and d['CONFIG_LIST_STATE']=='empty',d)
    reset();local.write_text('review:\n  internal_reviewers: [cursor]\n');d=run('codex',1)
    check('T-48 local legacy alias overrides shipped reviewer',d['OVERRIDE_EXCLUDED']=='codex' and d['REVIEWER_2_NAME']=='cursor' and d['REVIEWER_2_REASON']=='runtime-absent',d)
    reset();local.write_text('product_repos:\n  checkout_root: ../product-checkout\n');d=run('codex')
    check('T-48 unrelated local config is not an applied review override',d['LOCAL_OVERRIDE_STATE']=='none' and d['OUTCOME']=='proceeded',d)
    reset();local.write_text('review: {}\n');d=run('codex')
    check('T-48 empty local review is not an applied override',d['LOCAL_OVERRIDE_STATE']=='none' and d['OUTCOME']=='proceeded',d)
    reset();local.write_text('review: []\n');d=run('codex',1)
    check('T-48 malformed local review remains an applied diagnostic',str(local) in d['LOCAL_OVERRIDE_STATE'] and 'applied' in d['LOCAL_OVERRIDE_STATE'] and d['BLOCK_CAUSE']=='policy-unreadable',d)
    reset();cfg.write_text('review:\n  internal_reviewers: codex\n');d=run('codex',1)
    check('T-48 malformed legacy alias blocks fallback',d['BLOCK_CAUSE']=='list-malformed' and d['REVIEWER_COUNT']=='0',d)
    reset('[codex]','{}');d=run(expected=1)
    check('T-48 collection diagnostics',d['POLICY_INPUT']=='{}' and str(cfg)==d['UNREADABLE_FILE'] and bool(d['UNREADABLE_DETAIL']), d)
    for malformed in ('review: []\n',):
        reset();local.write_text(malformed);d=run('codex',1)
        check(f'T-31 malformed ancestor {malformed!r}',d['BLOCK_CAUSE']=='policy-unreadable' and str(local)==d['UNREADABLE_FILE'] and bool(d['UNREADABLE_DETAIL']),d)
    for source in (cfg,local):
        reset();source.write_text('review:\n  on_draft: []\n  internal_reviewers_unavailable_policy: warn\n');d=run('codex',1)
        check(f'T-31 malformed runner keeps readable sibling policy {source.name}',d['BLOCK_CAUSE']=='list-malformed' and d['POLICY_STATE']=='defined' and d['POLICY']=='warn' and d['CONFIG_LIST_SOURCE']==str(source) and d['REVIEWER_COUNT']=='0',d)
    for source in (cfg,local):
        reset();source.write_text('review:\n  on_draft: []\n  internal_reviewers_unavailable_policy: maybe\n');d=run('codex',1)
        check(f'T-31 unsupported sibling policy takes priority {source.name}',d['BLOCK_CAUSE']=='policy-unsupported' and d['POLICY_STATE']=='unsupported' and d['CONFIG_LIST_STATE']=='not-evaluated' and d['REVIEWER_COUNT']=='0',d)
    for malformed in ('[,]', '[codex,,cursor]', '[,codex]'):
        reset(malformed);d=run('codex',1)
        check(f'T-31 missing flow element {malformed}',d['BLOCK_CAUSE']=='policy-unreadable' and str(cfg)==d['UNREADABLE_FILE'],d)
    for numeric in ('123','-4','1.5','1e3','0xFF','0o77'):
        reset('[codex, '+numeric+']');d=run('codex',1)
        check(f'T-13 numeric member {numeric}',d['BLOCK_CAUSE']=='list-malformed' and d['REVIEWER_COUNT']=='0',d)
    reset('[codex,]');check('T-31 valid trailing comma remains defined',run('codex')['CONFIG_LIST_STATE']=='defined')
    reset('["123"]');d=run('codex',1)
    check('T-13 quoted numeric remains unsupported string',d['REVIEWER_1_NAME']=='123' and d['REVIEWER_1_REASON']=='value-not-supported',d)
    for badfile in (cfg,local):
        reset();badfile.write_bytes(b'review: \xff\n');d=run('codex',1)
        check(f'T-31 invalid UTF-8 {badfile.name}',d['BLOCK_CAUSE']=='policy-unreadable' and str(badfile)==d['UNREADABLE_FILE'] and bool(d['UNREADABLE_DETAIL']),d)
    reset('[codex]','{foo: bar}');d=run(expected=1)
    check('T-48 nonempty flow-map diagnostics',d['BLOCK_CAUSE']=='policy-unreadable' and str(cfg)==d['UNREADABLE_FILE'] and bool(d['UNREADABLE_DETAIL']),d)
    for malformed in ('["codex]', '[codex'):
        reset(malformed);d=run(expected=1)
        check(f'T-31 malformed YAML {malformed}',d['BLOCK_CAUSE']=='policy-unreadable' and str(cfg)==d['UNREADABLE_FILE'] and d['CONFIG_LIST_STATE']=='not-evaluated',d)
    for malformed in ('[codex, "claude" "cursor"]', "[codex, 'claude' 'cursor']", '[codex, "claude"cursor]'):
        reset(malformed);d=run('codex',1)
        check(f'T-31 missing delimiter after quoted entry {malformed}',d['BLOCK_CAUSE']=='policy-unreadable' and d['REVIEWER_COUNT']=='0' and bool(d['UNREADABLE_DETAIL']),d)
    reset(r'["co\u0064ex"]');d=run('codex')
    check('T-31 escaped supported reviewer decodes before probing',d['OUTCOME']=='proceeded' and d['REVIEWER_1_NAME']=='codex' and d['REVIEWER_1_STATUS']=='reachable',d)
    for malformed in (r'[codex, "bad\q"]', r'[codex, "bad\x1"]', r'[codex, "bad\u12"]', r'[codex, "bad\uD800"]', r'[codex, "bad\U00110000"]', r'[codex, "bad\0"]'):
        reset(malformed);d=run('codex',1)
        check(f'T-31 invalid YAML escape {malformed}',d['BLOCK_CAUSE']=='policy-unreadable' and d['REVIEWER_COUNT']=='0' and bool(d['UNREADABLE_DETAIL']),d)
    reset(r'[codex, "bad\nname"]');d=run('codex')
    check('T-31 escaped newline stays one verdict field',d['OUTCOME']=='proceeded-reduced' and d['REVIEWER_2_NAME']=='bad\\nname' and d['REVIEWER_COUNT']=='2',d)
    for scalar in ('"foo: bar"',"'foo: bar'",'https://example.test'):
        reset();cfg.write_text('review:\n  on_draft:\n    runner:\n      - '+scalar+'\n');d=run(expected=1)
        check(f'T-49 colon scalar {scalar}',d['REVIEWER_1_NAME']==scalar.strip("\"'") and d['REVIEWER_1_REASON']=='value-not-supported')
    cfg.write_text('review:\n  on_draft:\n    runner:\n      - key: value\n');check('T-49 mapping',run(expected=1)['BLOCK_CAUSE']=='list-malformed')
    reset();cfg.write_text('review:\n  on_draft:\n    runner:\n      - codex\n      - a:b: c\n');d=run('codex',1)
    check('T-49 later colon mapping blocks',d['BLOCK_CAUSE']=='policy-unreadable' and d['REVIEWER_COUNT']=='0',d)
    for token in ('!local codex', '&local codex', '*local', '? codex', '- codex', '|', '>', '@bad', '`bad'):
        reset('['+token+', codex]');d=run('codex',1)
        check(f'T-49 unsupported YAML node blocks {token}',d['BLOCK_CAUSE']=='policy-unreadable' and d['REVIEWER_COUNT']=='0',d)
    for token in ('!local codex', '&local codex', '*local', '? codex', '- codex', '|', '>', '@bad', '`bad', '-foo', '?foo'):
        reset('['+json.dumps(token)+', codex]');d=run('codex')
        check(f'T-49 quoted node-like scalar stays reportable {token}',d['OUTCOME']=='proceeded-reduced' and d['REVIEWER_1_NAME']==token and d['REVIEWER_2_STATUS']=='reachable',d)
    for mapping in ('extra: value', 'extra:', '"extra": value', '? extra', ': value'):
        reset('[codex, '+mapping+']');d=run('codex',1)
        check(f'T-49 flow mapping blocks {mapping}',d['OUTCOME']=='blocked' and d['BLOCK_CAUSE'] in ('list-malformed','policy-unreadable') and d['REVIEWER_COUNT']=='0',d)
    for scalar in ('"foo: bar"', "'foo: bar'", 'https://example.test'):
        reset('[codex, '+scalar+']');d=run('codex')
        check(f'T-49 flow scalar preserved {scalar}',d['OUTCOME']=='proceeded-reduced' and d['REVIEWER_2_NAME']==scalar.strip("\"'") and d['REVIEWER_2_REASON']=='value-not-supported',d)
    for scalar in ("it's", 'a"b', "'quoted, name'", '"quoted, name"'):
        reset('['+scalar+', codex]');d=run('codex')
        check(f'T-49 flow entry boundaries preserved {scalar}',d['OUTCOME']=='proceeded-reduced' and d['REVIEWER_COUNT']=='2' and d['REVIEWER_1_NAME']==scalar.strip("\"'") and d['REVIEWER_2_NAME']=='codex' and d['REVIEWER_2_STATUS']=='reachable',d)
    for reviewer,login in (('codex-github','chatgpt-codex-connector[bot]'),('coderabbit','coderabbitai[bot]')):
        reset(f'[{reviewer}]')
        new=[{'user':{'login':login}}]+[{'user':{'login':'other'}}]*99
        activity.write_text(json.dumps(new));gh(body=f'case "$*" in *"sort=created&direction=desc"*) cat {str(activity)!r} ;; *) printf "[]" ;; esac')
        check(f'T-50 newest activity {reviewer}',run()['REVIEWER_1_STATUS']=='reachable')
        gh([{'user':{'login':'other'}}]*100);d=run(expected=1);check(f'T-50 incomplete {reviewer}',d['REVIEWER_1_REASON']=='check-inconclusive' and d['REVIEWER_1_DETAIL']=='activity coverage incomplete')
        gh([]);d=run(expected=1);check(f'T-50 review-only absent {reviewer}',d['REVIEWER_1_REASON']=='prerequisite-missing' and all('/issues/comments?' in line for line in log.read_text().splitlines()))
    # Cross-case invariant checks include successes, policy blocks, and exclusions.
    for d in outputs:
        for n in range(1,int(d['REVIEWER_COUNT'])+1):
            name=d[f'REVIEWER_{n}_NAME'];status=d[f'REVIEWER_{n}_STATUS'];reason=d[f'REVIEWER_{n}_REASON'];remedy=d[f'REVIEWER_{n}_REMEDY']
            assert not(name in ('coderabbit','codex-github') and reason=='runtime-absent')
            assert not(name in ('claude','cursor','codex') and reason=='prerequisite-missing')
            if status=='unreachable':assert reason in ('runtime-absent','prerequisite-missing','check-inconclusive','value-not-supported') and remedy
            else:assert reason==remedy==''
            assert d['RUNNER_KIND'] not in d[f'REVIEWER_{n}_DETAIL'], d
    check('T-25 / T-36 / T-37 reason and remedy invariants',True)
print(f'{passed} availability assertions passed')
PY

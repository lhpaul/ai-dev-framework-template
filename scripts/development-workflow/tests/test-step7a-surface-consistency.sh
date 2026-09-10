#!/usr/bin/env bash
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
# covers: .ai-dev-workflow.yaml .ai-dev-workflow.local.example.yaml .claude/agents/item-orchestrator.md .cursor/agents/item-orchestrator.md
# covers: docs/workflow/development-workflow/integrations/coderabbit.md docs/workflow/development-workflow/integrations/codex-github.md docs/workflow/development-workflow/README.md
# covers: scripts/development-workflow/resolve-reviewer-availability.sh
# covers: **.md **.sh **.yaml **.yml **.mdc
# The selector's ** matches root and nested files; D-3 deliberately scans all live surfaces.
set -euo pipefail
ROOT=${SURFACE_ROOT:-"$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"}
python3 - "$ROOT" "${1:-}" <<'PY'
import pathlib, re, shutil, subprocess, sys, tempfile
root = pathlib.Path(sys.argv[1]).resolve()
protocol = 'docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md'
shared = '.ai-dev-workflow.yaml'
local = '.ai-dev-workflow.local.example.yaml'
agents = ['.claude/agents/item-orchestrator.md', '.cursor/agents/item-orchestrator.md']
cr = 'docs/workflow/development-workflow/integrations/coderabbit.md'
cg = 'docs/workflow/development-workflow/integrations/codex-github.md'
readme = 'docs/workflow/development-workflow/README.md'
helper = 'scripts/development-workflow/resolve-reviewer-availability.sh'
header = 'scripts/development-workflow/codex-github-reviewer.sh'
supported = {'claude','cursor','codex','coderabbit','codex-github'}
start = '<!-- step7a-codex-github-availability:start -->'
end = '<!-- step7a-codex-github-availability:end -->'

def normalized(s): return ' '.join(s.split())
def contains(s, *parts):
    s = normalized(s)
    return all(normalized(p) in s for p in parts)
def section(s, first, last):
    return s.split(first,1)[1].split(last,1)[0] if first in s and last in s.split(first,1)[1] else ''
def availability(s):
    if s.count(start)!=1 or s.count(end)!=1: return None
    return start + section(s,start,end) + end

def runner_lists(s):
    # Read every block-list runner field in the two shipped config examples.
    result=[]; lines=s.splitlines()
    for i,line in enumerate(lines):
        if re.match(r'^\s*runner:\s*(?:#.*)?$',line):
            depth=len(line)-len(line.lstrip()); entries=[]
            for child in lines[i+1:]:
                if not child.strip() or child.lstrip().startswith('#'): continue
                if len(child)-len(child.lstrip())<=depth: break
                match=re.fullmatch(r'\s*-\s+([a-z][a-z0-9-]*)\s*(?:#.*)?',child)
                if not match: return None
                entries.append(match[1])
            result.append(entries)
    return result

def checks(base):
    def read(path): return (base/path).read_text()
    p=read(protocol); gate=section(p,'### Determining which reviewers to run','### Step 7a loop parameters')
    entry=section(gate,'The only configuration resolution','### Runtime-availability check')
    runtime=section(gate,'### Runtime-availability check','#### Policy resolution')
    policy=section(gate,'#### Policy resolution','#### Warning comment format')
    warning=section(gate,'#### Warning comment format','#### Hard-fail comment format')
    hard=section(gate,'#### Hard-fail comment format','### Reviewer dispatch map')
    dispatch=section(gate,'### Reviewer dispatch map','### Branch-type detection')
    summary=gate.split('#### Step 7a summary comment (mandatory)',1)[-1]
    out={}
    declared=section(entry,'Supported reviewer values are ','. If no list')
    out['D-1']=set(re.findall(r'`([^`]+)`',declared))==supported and contains(entry,'Supported reviewer values are `claude`, `cursor`, `codex` (local-runtime), and','`coderabbit`, `codex-github` (hosted-service)')
    out['D-2']=not any(x in gate.lower() for x in ('runner identity is a sufficient proxy','reachability classification table'))
    grep=subprocess.run(['git','-C',str(base),'grep','-n','-i','-F','universally reachable','--','*.md','*.sh','*.yaml','*.yml','*.mdc',':(exclude)CHANGELOG.md',':(exclude)docs/specs/developments/**',':(exclude)docs/testing/**',':(exclude)scripts/**/tests/**'],capture_output=True)
    out['D-3']=grep.returncode==1 # search errors must never count as an empty result
    lists=[runner_lists(read(path)) for path in (shared,local)]
    out['D-4']=all(groups is not None and groups and all(set(group)<=supported for group in groups) for groups in lists)
    reasons={'runtime-absent','prerequisite-missing','check-inconclusive','value-not-supported'}
    doc=dict(re.findall(r'^\| `([^`]+)` \| (.+) \|$',runtime,re.M))
    code={}
    for line in read(helper).splitlines():
        m=re.match(r'\s*([a-z-]+)\) remedies\[\$count\]=([\'"])(.*)\2 ;;',line)
        if m: code[m[1]]=m[3]
    out['D-5']=set(doc)==set(code)==reasons and doc==code
    out['D-6']=contains(dispatch,'Every dispatched failure is a review failure under either policy.','claude -p --output-format text','cursor-agent --print --output-format text','codex exec --sandbox read-only','exactly one `VERDICT: APPROVED` or `VERDICT: NEEDS REVISION`','non-zero CLI exit, timeout, permission denial, or missing/ambiguous verdict')
    out['D-7']=all("driving runner's own stage reviewer" in normalized(x) for x in (entry,read(readme))) and 'stage-appropriate `claude` reviewer' not in entry
    out['D-8']=contains(runtime,'is read-only: do not review, post a comment, alter the PR, install software, or substitute a reviewer','Do not provision services or write tracked files.')
    out['D-9']=lists[0]==[['claude','cursor','codex']] and not re.search(r'expected behavio[u]?r.*hard.fail',read(shared),re.I)
    c=read(cr)
    out['D-10']=contains(section(c,'### Draft conversion','### Invocation'),'reviews.auto_review.enabled: true','after availability and policy') and 'coderabbitai[bot]' in c and contains(hard,'CodeRabbit draft-eligibility precondition','before its dispatch') and 'Switch to Claude' not in c
    def dispatch_block(s):
        return re.findall(r'^\*\*`codex-github` runner reviewer dispatch\*\*:.*$',s,re.M)
    da,db=[dispatch_block(read(a)) for a in agents]
    out['D-11']=len(da)==len(db)==1 and da==db
    out['D-12']=contains(entry,'On exit `0`, dispatch each indexed reachable reviewer','Never dispatch unreachable or override-excluded records.','When `FALLBACK_APPLIED=true`, dispatch the driving runner\'s own stage reviewer exactly once.')
    out['D-13']=contains(entry,'Run it on every cycle','a verdict from an earlier cycle is never reused.')
    out['D-14']=contains(runtime,'This interval starts at helper entry and ends at helper return; reporting and draft-state recovery are allowed only after determination.','is read-only: do not review, post a comment, alter the PR','Do not provision services or write tracked files.')
    invocation=section(entry,'```bash','```')
    out['D-15']=contains(entry,'No reviewer is dispatched until the resolver returns and the policy has been applied') and contains(invocation,'resolve-reviewer-availability.sh','--repo-root <artifact-repo-root> --owner <target-owner> --repo <target-repo>','--runner-kind <actual-driving-session-kind>') and contains(entry,'never a value inferred from PATH, the reviewer list, or `WORKFLOW_RUNNER_KIND`')
    out['D-16']=contains(summary,'per-reviewer verdict for every configured reviewer','display labels Reachable, Unreachable, or Excluded by override','Override-excluded entries appear in the summary and never in the warning.','Record `FALLBACK_APPLIED` and the own-stage dispatch')
    out['D-17']=contains(warning,'only when `OUTCOME=proceeded-reduced`','before dispatching any reviewer','indexed names, reasons, and remedies','reachable subset','never name runner context') and '(<runner-context>)' not in warning
    out['D-18']=contains(hard,'Every configured reviewer with its verdict','including Reachable and Excluded by override','reason and remedy','`BLOCK_CAUSE`','`LOCAL_OVERRIDE_STATE`','`POLICY_INPUT`','`UNREADABLE_FILE` / `UNREADABLE_DETAIL`','Case B names `fail-if-any-unavailable`','do not attribute a block to runner identity') and '(<runner-context>)' not in hard
    recovery=section(hard,'Treat helper','After a proceed verdict')
    out['D-19']=contains(recovery,'exit `1` and exit `2` (`availability-resolver-failed`)','dispatch nobody, never convert to ready','After determination','gh pr ready <pr_number> --undo','verify `isDraft: true`','missing_required_secret_or_permission','do not claim the PR is draft')
    out['D-20']=contains(entry,'no independent `review-effective` or `review-overrides` call','stalled parser is verified by smoke Step 16') and contains(hard,'After a proceed verdict, if a Reachable `coderabbit` is selected','only if needed','after availability and policy but before dispatch') and contains(policy,'Neither reviewer is classified unavailable because the PR is draft.')
    out['D-21']=contains(runtime,'historical activity can be a false Reachable after removal','new or review-only installation can be false Unreachable','review failure under either policy, never an unreachability reclassification')
    unsafe_aggregate_lines=[line for line in gate.splitlines() if re.search(r'\b(?:CONFIGURED|REACHABLE|UNREACHABLE|OVERRIDE_EXCLUDED)\b',line) and re.search(r'\b(?:split|splitting|tokenize|eval)\b',line,re.I) and not re.search(r'never|must not|do not',line,re.I)]
    out['D-22']=not unsafe_aggregate_lines and contains(entry,'names only from its indexed `REVIEWER_N_*` fields','display-only and must never be split or `eval`ed') and contains(summary,'names, reasons, remedies, and details from indexed `REVIEWER_N_*` fields')
    blocks=[availability(read(x)) for x in [protocol,*agents,cg]]
    out['D-23']=all(blocks) and len(set(blocks))==1 and contains(blocks[0],'repository-activity proxy','`prerequisite-missing`','complete short page','`check-inconclusive`','full unmatched page','Post-dispatch errors remain review failures')
    outside=runtime.replace(availability(p) or '', '')
    out['D-24']=contains(outside,'availability is decided at runtime from whether the service is installed and reachable.','Where the service is not installed and reachable it is unavailable with a named reason.','Decision 8 waives literal verification of both directions')
    return out

def report(result):
    for name,passed in result.items(): print(('PASS' if passed else 'FAIL')+': '+name,flush=True)
    print(f'{sum(result.values())} passed; {len(result)-sum(result.values())} failed',flush=True)

baseline=checks(root);report(baseline)
if not all(baseline.values()): raise SystemExit(1)
if sys.argv[2] not in ('','--prove-plants'): raise SystemExit('unknown argument: '+sys.argv[2])
if sys.argv[2]=='--prove-plants':
    # Copy only versioned input files; never copy .git, credentials, local
    # overrides, dependencies, or unrelated ignored state into a fixture.
    with tempfile.TemporaryDirectory(prefix='step7a-surfaces-') as tmp:
        fixture=pathlib.Path(tmp)
        paths=subprocess.check_output(['git','-C',str(root),'ls-files','-z']).decode().split('\0')
        for name in paths:
            if not name or not (root/name).is_file(): continue
            dest=fixture/name;dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(root/name,dest)
        subprocess.run(['git','init','-q',str(fixture)],check=True)
        subprocess.run(['git','-C',str(fixture),'add','.'],check=True)
        assert all(checks(fixture).values()), 'clean copied fixture must pass'
        plants=[
            ('D-1',protocol,'`coderabbit`, `codex-github` (hosted-service). If no list','`coderabbit`, `codex-github` (hosted-service), `greptile`. If no list'),
            ('D-2',protocol,'### Runtime-availability check','### Runtime-availability check\n\nRunner identity is a sufficient proxy.'),
            ('D-3',header,'# This is a hosted-service reviewer.','# This is universally reachable.'),
            ('D-4',local,'      - cursor','      - greptile'),
            ('D-5',protocol,"| `runtime-absent` | Install the reviewer's runtime","| `runtime-absent` | Acquire the reviewer's runtime"),
            ('D-6',protocol,'Every dispatched failure is a review failure under either policy.','Every dispatched failure is skipped under warn.'),
            ('D-7',readme,"driving runner's own stage reviewer",'fixed Claude reviewer'),
            ('D-8',protocol,'install software, or\nsubstitute a reviewer','install software, or\nreplace a reviewer'),
            ('D-9',shared,'      - claude\n      - cursor\n      - codex','      - codex'),
            ('D-10',cr,'`reviews.auto_review.enabled: true` must be set','`reviews.auto_review.enabled: false` must be set'),
            ('D-11',agents[1],'Exit `0` approves','Exit `0` accepts'),
            ('D-12',protocol,"`FALLBACK_APPLIED=true`, dispatch the driving runner's own stage reviewer\nexactly once.","`FALLBACK_APPLIED=true`, dispatch the driving runner's own stage reviewer\nzero times."),
            ('D-13',protocol,'a verdict from an earlier cycle is never reused.','a verdict from an earlier cycle is reused.'),
            ('D-14',protocol,'This interval starts at helper entry and ends at helper return; reporting and draft-state recovery are allowed only after determination.','Reporting may run during determination.'),
            ('D-15',protocol,'No reviewer is dispatched until the resolver returns and the\npolicy has been applied','Dispatch all reviewers before determination'),
            ('D-15',protocol,'  --runner-kind <actual-driving-session-kind>\n```','  --runner-kind omitted\n```'),
            ('D-16',protocol,'per-reviewer verdict for every configured reviewer','verdict for dispatched reviewers only'),
            ('D-17',protocol,'only when `OUTCOME=proceeded-reduced`','for every outcome'),
            ('D-18',protocol,'Every configured reviewer with its verdict is included in each hard-fail report.','Only unreachable reviewers are included in each hard-fail report.'),
            ('D-19',protocol,'verify `isDraft: true` before completing the block report','assume the PR is draft'),
            ('D-20',protocol,'After a proceed verdict, if a Reachable `coderabbit` is selected','After a proceed verdict, regardless of whether `coderabbit` is Reachable'),
            ('D-21',protocol,'historical activity can be a false Reachable after removal','historical activity proves the service remains installed'),
            ('D-22',protocol,'### Branch-type detection','Split `CONFIGURED` on commas to recover reviewer names.\n\n### Branch-type detection'),
            ('D-23',agents,'complete short page','incomplete short page'),
            ('D-24',protocol,'Where the service is not installed and reachable it is\nunavailable with a named reason.','No source condition applies when the service is absent.'),
        ]
        for number,(case,files,needle,replacement) in enumerate(plants,1):
            files=[files] if isinstance(files,str) else files
            originals={};evidence=[]
            try:
                for file in files:
                    target=fixture/file;s=target.read_text(); originals[file]=s
                    assert s.count(needle)==1,(case,file,'plant must identify one unique location',s.count(needle))
                    line=s[:s.index(needle)].count('\n')+1;evidence.append(f'{file}:{line}')
                    target.write_text(s.replace(needle,replacement,1))
                result=checks(fixture)
                assert [k for k,v in result.items() if not v]==[case],(case,'plant must change only its check',result)
                print(f'PROOF {number:02d} {case}: FAIL at '+', '.join(evidence),flush=True)
            finally:
                for file,s in originals.items(): (fixture/file).write_text(s)
            assert checks(fixture)==baseline,(case,'repaired fixture must pass every check')
            print(f'PROOF {number:02d} {case}: PASS after repair',flush=True)
        print('25 isolated planted violations failed and repaired; source checkout untouched.',flush=True)
PY

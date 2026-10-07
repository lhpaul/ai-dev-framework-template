#!/usr/bin/env python3
"""Composed fixture proofs; fake gh never forwards a request to GitHub."""
import importlib.util
import json
import os
from pathlib import Path
from datetime import datetime, timedelta, timezone
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
SCRIPTS = ROOT / 'scripts/development-workflow'
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location('scan', SCRIPTS / 'workflow-portfolio-scan.py')
scan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scan)
FAKE_GH = r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
p=Path(os.environ['SCAN_FIXTURE_STATE']); state=json.loads(p.read_text()); args=sys.argv[1:]
state['calls'].append(args)
def finish(data=None,error=None,exit_json=False):
 p.write_text(json.dumps(state))
 if exit_json: print(json.dumps(data));print(error or 'GraphQL errors',file=sys.stderr);sys.exit(1)
 if error: print(error,file=sys.stderr);sys.exit(1)
 print(json.dumps(data));sys.exit(0)
def raw(value):
 state['graphql']+=1;state['remaining']-=1;p.write_text(json.dumps(state));print(value);sys.exit(0)
if args[:2]==['auth','status']:
 p.write_text(json.dumps(state));sys.exit(0)
if args[:2]==['repo','view']:
 field=args[args.index('--json')+1]
 raw({'owner':'fixture','name':'repo','nameWithOwner':'fixture/repo'}[field])
if args[:2]==['pr','list']:
 raw('' if '--jq' in args and '.[0].number' in args[args.index('--jq')+1] else '[]')
if args[:2]==['pr','view']:finish(error='Could not resolve to a PullRequest')
if args[:2]==['issue','view']:
 n=int(args[2]);fields=args[args.index('--json')+1]
 if '--jq' in args:
  if fields=='state':raw('OPEN')
  if fields in ('labels','subIssues'):raw('0')
 value={'number':n,'title':'Fixture '+str(n),'state':'OPEN','stateReason':None,'body':'','labels':[], 'projectItems':[]}
 raw(json.dumps(value))
if not args or args[0]!='api': finish(error='Forbidden gh operation/mutation')
if args[1]=='graphql':
 values={args[i+1].split('=',1)[0]:args[i+1].split('=',1)[1] for i in range(2,len(args),2)}
 query=values['query']; state['graphql']+=1
 if state.get('reject')==state['graphql']: finish(error='API rate limit exceeded')
 if state.get('partialRate')==state['graphql']:
  state['remaining']-=state.get('partialCost',0)
  finish({'data':{'rateLimit':{'cost':state.get('partialCost',0)}},'errors':[{'type':'RATE_LIMITED','message':'API rate limit exceeded'}]},exit_json=state.get('partialRateExit',False))
 if state.get('nonrate')==state['graphql']: finish(error='Bad credentials')
 if state['remaining']<=0: finish(error='API rate limit exceeded')
 state['remaining']-=state.get('cost',1)
 rate={'rateLimit':{'cost':state.get('cost',1)}}
 if 'projectV2(number:' in query:
  kind='organization' if 'organization(login:' in query else 'user'
  if kind=='user' and state.get('userNotFound'):
   rate['rateLimit']['cost']=state.get('partialCost',1)
   state['remaining']-=state.get('partialCost',1)-state.get('cost',1)
   finish({'data':{'user':None,**rate},'errors':[{'type':'NOT_FOUND','path':['user'],'message':'Organization is not a user'}]},exit_json=state.get('userNotFoundExit',False))
  value=None if kind=='user' and state.get('org') else {'projectV2':{'id':'P1'}}
  finish({'data':{kind:value,**rate}})
 n=int(values.get('issueNumber',state.get('target',1)))
 card={'id':'I'+str(n),'project':{'id':'P1'},'content':{'number':n,'repository':{'nameWithOwner':state['repo']},'issueType':{'name':state.get('nativeType','Bug')}},'status':{'name':state.get('statuses',{}).get(str(n),'Backlog')},'type':{'name':'Feature'},'customType':{'name':state.get('customType','Refactor')},'configuredType':{'name':state.get('configuredType','Feature')}}
 for alias in ('dependsOn','dependencies'):
  if alias in state:card[alias]={'text':state[alias]}
  if alias in state.get('dependencyRaw',{}):card[alias]=state['dependencyRaw'][alias]
 card['priority']={'name':state.get('priorities',{}).get(str(n),'Normal')}
 card['dueDate']={'date':state.get('dueDates',{}).get(str(n))}
 if state.get('missingType'): card.pop('type');card.pop('customType');card.pop('configuredType');card['content'].pop('issueType')
 if state.get('missingStatus'):card.pop('status')
 if 'subIssues(first:' in query:
  finish({'data':{'repository':{'issue':{'number':10,'subIssues':{'nodes':[{'number':1,'title':'one','state':'OPEN'},{'number':2,'title':'two','state':'OPEN'}],'pageInfo':{'hasNextPage':False,'endCursor':None}}}}}})
 if 'parent { number title }' in query:finish({'data':{'repository':{'issue':{'parent':{'number':10,'title':'epic'}}}}})
 if 'projectItems(first:' in query:
  page=int(values.get('after','0'));cap=state.get('pages',1)
  if cap>1: nodes=[] if page<cap-1 else [card]
  else:nodes=[] if state.get('fallback') else [card]
  info={'hasNextPage':page<cap-1,'endCursor':str(page+1) if page<cap-1 else None}
  if state.get('forceEmptyPrimary'):nodes=[]
  if state.get('repeatCursor'):info={'hasNextPage':True,'endCursor':'0'};nodes=[]
  if state.get('malformed')=='primary':nodes='bad'
  finish({'data':{'repository':{'issue':{'projectItems':{'nodes':nodes,'pageInfo':info}}},**rate}})
 if 'items(first:100,query:' in query:
  # Server candidate search is title based; foreign number must never match.
  foreign=dict(card, id='FOREIGN',content={'number':state.get('target',1),'repository':{'nameWithOwner':'foreign/repo'}})
  card['content']['number']=state.get('target',1)
  nodes=[foreign,card]
  if state.get('unsupported'):finish({'errors':[{'type':'GRAPHQL_VALIDATION_FAILED','message':'Unknown argument archivedStates'}]})
  if state.get('missingIdentity'):nodes=[dict(card,content={})]
  if state.get('atCap'):nodes=[foreign]*99+[card]
  if state.get('foreignOnly'):nodes=[foreign]
  if state.get('duplicate'):nodes=[card,dict(card,id='CONFLICT')]
  if state.get('malformed')=='fallback':nodes=[dict(card,content='bad')]
  finish({'data':{'node':{'items':{'nodes':nodes,'pageInfo':{'hasNextPage':state.get('truncated',False),'endCursor':'more' if state.get('truncated') else None}}},**rate}})
 finish(error='Unexpected GraphQL query')
endpoint=args[-1]
if endpoint=='rate_limit':
 state['samples']+=1
 if state.get('sampleFailures','') in ('both',str(state['samples'])):finish(error='Budget sample failed')
 if state['samples']==2:
  state['remaining']-=state.get('otherSpend',0)
  state['remaining']=state.get('afterRemaining',state['remaining'])
  state['reset']=state.get('afterReset',state['reset'])
 finish({'resources':{'graphql':{'remaining':state['remaining'],'reset':state['reset']},'core':{'remaining':4999}}})
if endpoint.endswith('issues?state=open&per_page=100'):
 if state.get('restFail'):finish(error='Incomplete REST page')
 issues=[{'number':i,'title':'Fixture '+str(i),'body':state.get('bodies',{}).get(str(i),state.get('body','')),'state':'open','created_at':state.get('created',{}).get(str(i),'2026-01-01T00:00:00Z')} for i in range(1,state.get('active',41)+1)]
 finish([issues[:20],issues[20:]])
if 'pulls?state=all&base=' in endpoint:finish([[]])
if endpoint.endswith('pulls?state=open&per_page=100'):
 prs=[{'number':70,'head':{'ref':state.get('prBranch','fix/1-fixture')}}] if state.get('pr') else []
 finish([prs])
if endpoint.endswith('/pulls/70'):finish({'number':70,'head':{'ref':state.get('prBranch','fix/1-fixture'),'sha':'H1'},'draft':True,'labels':state.get('labels',[])})
if endpoint.endswith('/issues/70/comments?per_page=100'):
 if state.get('prFail'):finish(error='PR evidence unavailable')
 finish([state.get('prComments',[])])
if endpoint.endswith('/commits/H1/status'):finish(state.get('prStatus',{'state':'success','sha':'H1','statuses':[]}))
if endpoint.endswith('/commits/H1/check-runs?per_page=100'):finish([{'check_runs':state.get('prChecks',[])},{'check_runs':[]}])
if '/pulls?state=closed&head=' in endpoint:
 head=endpoint.split('&head=',1)[1].split('&',1)[0].split(':',1)[1]
 finish([[{'number':80,'head':{'ref':head},'merged_at':'2026-10-01T00:00:00Z'}]] if head in state.get('mergedHeads',[]) else [[]])
if '/issues/' in endpoint:
 n=int(endpoint.rsplit('/',1)[-1]);finish({'number':n,'title':state.get('title','Fixture '+str(n)),'state':state.get('state','open')})
finish(error='Unexpected REST request: '+endpoint)
'''


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='portfolio-fixture-')
        self.folder = Path(self.tmp.name)
        self.root = self.folder / 'repo'
        self.root.mkdir()
        self.bin = self.folder / 'bin'
        self.bin.mkdir()
        self.state = self.folder / 'state.json'
        self.env = os.environ.copy()
        for key in ('GITHUB_PROJECT_NUMBER','GITHUB_PROJECT_OWNER','GITHUB_REPO','WORKFLOW_SCAN_INVOCATION_ID','WORKFLOW_SCAN_LOCAL_METADATA_FILE'):
            self.env.pop(key,None)
        self.env.update(PATH=str(self.bin)+os.pathsep+self.env['PATH'], SCAN_FIXTURE_STATE=str(self.state))
        # Local git operations use real git. Remote reads are fixture-only.
        self.git = subprocess.check_output(['which','git'],text=True).strip()
        (self.bin/'git').write_text('#!/bin/sh\ncase "$*" in *ls-remote*)\n  [ -n "$SCAN_FIXTURE_BRANCH" ] && printf "fixture\\trefs/heads/%s\\n" "$SCAN_FIXTURE_BRANCH"\n  exit 0\n  ;;\n*fetch*) exit 0 ;;\nesac\nexec '+self.git+' "$@"\n')
        (self.bin/'gh').write_text(FAKE_GH)
        for p in self.bin.iterdir():p.chmod(0o755)
        subprocess.run([self.git,'init','-q',str(self.root)],check=True)
        subprocess.run([self.git,'-C',str(self.root),'remote','add','origin','https://github.com/fixture/repo.git'],check=True)
        self.config = self.root/'.ai-dev-workflow.yaml'
        self.config.write_text('issue_tracker:\n  provider: github_projects\n  project_number: 1\ntemplate:\n  is_template: true\n')
        self.env['AI_DEV_WORKFLOW_CONFIG_FILE']=str(self.config)
        self.reset()

    def tearDown(self):self.tmp.cleanup()

    def reset(self, **overrides):
        state=dict(repo='fixture/repo',remaining=4500,reset=2000000000,calls=[],graphql=0,samples=0,active=41,history=600)
        state.update(overrides)
        state['terminalCards']=[{'number':10000+i,'state':'closed','status':'Released'} for i in range(state['history'])]
        self.state.write_text(json.dumps(state))

    def execute(self,*args,ok=True):
        result=subprocess.run(args,env=self.env,text=True,capture_output=True,cwd=self.root)
        if ok:self.assertEqual(result.returncode,0,result.stderr)
        else:self.assertNotEqual(result.returncode,0,result.stdout)
        return result

    def scan(self,ok=True):
        result=self.execute('bash',str(SCRIPTS/'workflow-portfolio-scan.sh'),'--repo-root',str(self.root),'--json',ok=ok)
        report=json.loads(result.stdout)
        if os.environ.get('WORKFLOW_PORTFOLIO_EVIDENCE_DIR'):
            directory=Path(os.environ['WORKFLOW_PORTFOLIO_EVIDENCE_DIR']);directory.mkdir(parents=True,exist_ok=True)
            index=len(list(directory.glob('*.json')))
            (directory/f'{index:03d}-{self._testMethodName}.json').write_text(json.dumps({'report':report,'requests':self.ledger()},indent=2))
        return report

    def ledger(self):return json.loads(self.state.read_text())

    def artifact(self,number=1,plan=True):
        p=self.root/'docs/specs/developments'/f'20261007120000_{number}-fixture'
        p.mkdir(parents=True,exist_ok=True)
        (p/f'1_{number}_fixture_specs.md').write_text('fixture\n')
        if plan:(p/f'2_{number}_fixture_implementation-plan.md').write_text('fixture\n')
        return str(p.relative_to(self.root))

    def brief_artifact(self,number):
        p=self.root/'docs/specs/developments'/f'{number}-fixture'
        p.mkdir(parents=True,exist_ok=True)
        (p/'brief.md').write_text(f'**Issue**: #{number}\nSimple application change.\n')
        return p

    def plan_files(self,number,files):
        p=self.root/self.artifact(number)
        (p/f'2_{number}_fixture_implementation-plan.md').write_text('### Files modified\n\n```text\n'+'\n'.join(files)+'\n```\n')
        return p

    def target(self,**overrides):
        self.reset(**overrides)
        return self.execute('python3',str(SCRIPTS/'workflow-project-reader.py'),'--fallback','--repo','fixture/repo','--project-id','P1','--number','1',ok=not overrides.get('fails',False))

    def test_large_history_and_growth(self):
        router=self.execute('bash',str(SCRIPTS/'run-work-router.sh'))
        self.assertIn('MODE=no_target_scan',router.stdout)
        self.assertEqual(self.ledger()['graphql'],0)
        self.artifact();self.reset(statuses={'1':'Plan Ready'},nativeType='Feature')
        report=self.scan();self.assertEqual(report['coverage'],scan.FULL)
        self.assertEqual(len(report['fullyRead']),41)
        self.assertLessEqual(report['scanOwnedSpend'],1000)
        self.assertGreaterEqual(report['spend']['GraphQL points remaining'],1000)
        self.assertIn(report['recommendedCommand'].split()[0],('/run-item','/run-items'))
        ledger=self.ledger();self.assertEqual(ledger['graphql'],42)
        self.assertTrue(all(call[0]=='api' for call in ledger['calls']))
        self.assertFalse(any('project item-list' in ' '.join(call) for call in ledger['calls']))
        counts=[]
        for history in (50,1000):
            self.reset(history=history,statuses={'1':'Plan Ready'})
            counts.append((len(self.scan()['fullyRead']),self.ledger()['graphql']))
        self.assertEqual(counts,[(41,42),(41,42)])
        # Retained closed folder and branch do not cause any target reads.
        self.artifact(500);self.env['SCAN_FIXTURE_BRANCH']='fix/500-closed'
        self.reset();self.scan();self.assertEqual(self.ledger()['graphql'],42)

    def test_budget_matrix_and_reserve(self):
        self.artifact(1)
        for initial,coverage in ((900,scan.DEFERRED),(1001,scan.DEFERRED),(1002,scan.DEFERRED),(1021,scan.DEFERRED),(1022,scan.PARTIAL),(1861,scan.PARTIAL),(1862,scan.FULL)):
            self.reset(remaining=initial,statuses={'1':'Plan Ready'})
            report=self.scan();self.assertEqual(report['coverage'],coverage,(initial,report))
            self.assertGreaterEqual(self.ledger()['remaining'],min(initial,1000))
            self.assertLessEqual(report.get('projectionSpend',0),2)
            if initial<1002:self.assertEqual(self.ledger()['graphql'],0)
            if coverage==scan.DEFERRED:self.assertFalse(report['classification'])
            if coverage==scan.PARTIAL:
                self.assertEqual(len(report['fullyRead']),1)
                self.assertFalse(any(row['action']=='start-backlog' for row in report['classification']))
        for initial in range(1000,1920,19):
            self.reset(remaining=initial);self.scan();self.assertGreaterEqual(self.ledger()['remaining'],1000)

    def test_config_validation(self):
        warnings=[]
        self.assertEqual(scan.reserve_from_config({},warnings),1000);self.assertFalse(warnings)
        for value in ('0','5000',0,5000):
            self.assertEqual(scan.reserve_from_config({'portfolio_scan':{'graphql_reserve':value}},[]),int(value))
        for value in (None,'',' ',True,False,'1.5',-1,'-1','+2',[],{},'5001'):
            warnings=[];self.assertEqual(scan.reserve_from_config({'portfolio_scan':{'graphql_reserve':value}},warnings),1000);self.assertTrue(warnings)
        self.config.write_text(self.config.read_text()+'portfolio_scan:\n  graphql_reserve: null\n')
        self.assertTrue(any('Invalid' in warning for warning in self.scan()['warnings']))

    def test_effective_project_scope_and_empty_owner(self):
        self.env['GITHUB_PROJECT_OWNER']=''
        for override,expected in (('2','2'),('','1')):
            self.env['GITHUB_PROJECT_NUMBER']=override
            self.reset(active=1)
            report=self.scan();self.assertEqual(report['projectNumber'],expected)
            self.assertEqual(report['projectOwner'],'fixture')
            self.assertEqual(report['ledger'][0]['variables'],{'owner':'fixture','number':int(expected)})
            snapshot=self.folder/'scope.json';snapshot.write_text(json.dumps(report))
            self.env['WORKFLOW_SCAN_INVOCATION_ID']=report['invocation']
            before=len(self.ledger()['calls'])
            self.execute('bash',str(SCRIPTS/'workflow-batch-plan.sh'),'--repo-root',str(self.root),'--scan-snapshot',str(snapshot))
            self.assertEqual(len(self.ledger()['calls']),before)
            self.env['GITHUB_PROJECT_NUMBER']='3'
            self.execute('bash',str(SCRIPTS/'workflow-batch-plan.sh'),'--repo-root',str(self.root),'--scan-snapshot',str(snapshot),ok=False)
            self.assertEqual(len(self.ledger()['calls']),before)
            self.env['GITHUB_PROJECT_NUMBER']=override
            self.env['GITHUB_PROJECT_OWNER']='different-owner'
            self.execute('bash',str(SCRIPTS/'workflow-batch-plan.sh'),'--repo-root',str(self.root),'--scan-snapshot',str(snapshot),ok=False)
            self.env['GITHUB_PROJECT_OWNER']=''
            self.assertEqual(len(self.ledger()['calls']),before)
            status=self.execute('bash','-c','source "$1"; get_tracker_status_for_issue 1','fixture',str(SCRIPTS/'workflow-lib.sh'))
            self.assertEqual(status.stdout.strip(),'Backlog')
            queries=[call for call in self.ledger()['calls'][before:] if call[:2]==['api','graphql'] and 'projectV2(number:' in ' '.join(call)]
            self.assertTrue(queries);self.assertIn('projectNumber='+expected,queries[0])

    def test_local_only_workflow_branch_full_and_partial(self):
        subprocess.run([self.git,'-C',str(self.root),'-c','user.name=Fixture','-c','user.email=fixture@example.test','commit','--allow-empty','-qm','fixture'],check=True)
        subprocess.run([self.git,'-C',str(self.root),'branch','fix/1-local-work'],check=True)
        for remaining,coverage in ((4500,scan.FULL),(1022,scan.PARTIAL)):
            self.reset(remaining=remaining,nativeType='Workflow')
            report=self.scan();self.assertEqual(report['coverage'],coverage)
            row=next(row for row in report['classification'] if row['number']==1)
            self.assertEqual(row['category'],'ACTIONABLE RESUME')
            self.assertEqual(row['action'],'run-code-review-and-open-pr')
            record=next(record for record in report['fullyRead'] if record['number']==1)
            self.assertTrue(record['inFlight']);self.assertIn('fix/1-local-work',record['branches'])
            self.assertEqual(report['partialCost'],22)

    def test_priority_due_date_creation_and_ordering_guards(self):
        self.brief_artifact(1);self.brief_artifact(2)
        today=datetime.now(timezone.utc).date()
        scenarios=[({'priorities':{'1':'Low','2':'Urgent'}},2,False),
                   ({'priorities':{'1':'Low','2':'Urgent'},'dueDates':{'1':str(today+timedelta(days=5))}},1,True),
                   ({'priorities':{'1':'Low','2':'Urgent'},'dueDates':{'1':str(today+timedelta(days=14))}},1,True),
                   ({'priorities':{'1':'Low','2':'Urgent'},'dueDates':{'1':str(today+timedelta(days=15))}},2,False),
                   ({'dueDates':{'1':str(today+timedelta(days=10)),'2':str(today+timedelta(days=3))}},2,False),
                   ({'priorities':{'1':'Low','2':'High'},'dueDates':{'1':str(today+timedelta(days=20))}},2,False),
                   ({'priorities':{'1':'Normal','2':'Medium'},'created':{'1':'2026-02-01T00:00:00Z','2':'2026-01-01T00:00:00Z'}},2,False)]
        for overrides,winner,warned in scenarios:
            self.reset(active=2,**overrides);report=self.scan()
            self.assertEqual(report['recommendedCommand'],'/run-item '+str(winner))
            self.assertEqual(report['classification'][0]['number'],winner)
            self.assertEqual(self.ledger()['graphql'],3)
            self.assertEqual(any('conflicts with abstract Priority' in warning for warning in report['warnings']),warned)
            self.assertIn('fieldValueByName(name:"Due date")',report['ledger'][1]['query'])
        self.reset(active=1,created={'1':None});self.assertFalse(self.scan()['fullyRead'])
        self.reset(active=1,dueDates={'1':'bad-date'});self.assertFalse(self.scan(ok=False)['fullyRead'])
        self.reset(active=1);report=self.scan();snapshot=self.folder/'ordering.json'
        self.env['WORKFLOW_SCAN_INVOCATION_ID']=report['invocation'];before=len(self.ledger()['calls'])
        for bad in ({'created_at':None},{'created_at':'bad'},{'due_date':[]},{'due_date':'bad'}):
            invalid=dict(report,fullyRead=[dict(report['fullyRead'][0],**bad)])
            snapshot.write_text(json.dumps(invalid))
            self.execute('bash',str(SCRIPTS/'workflow-batch-plan.sh'),'--repo-root',str(self.root),'--scan-snapshot',str(snapshot),ok=False)
            self.assertEqual(len(self.ledger()['calls']),before)

    def test_tool_fix_and_overlap_gates_before_lane_caps(self):
        self.config.write_text(self.config.read_text()+'guardrails:\n  parallelism:\n    max_concurrent_by_stage:\n      implementation: 2\n')
        self.plan_files(1,['src/shared.py']);self.plan_files(2,['src/shared.py'])
        self.reset(active=2,statuses={'1':'Plan Ready','2':'Plan Ready'},priorities={'1':'Low','2':'Urgent'})
        report=self.scan();rows={row['number']:row for row in report['classification']}
        self.assertEqual(rows[2]['category'],'ACTIONABLE RESUME');self.assertEqual(rows[2]['dispatch'],'proposed')
        self.assertEqual(rows[1]['category'],'HELD');self.assertIn('Overlap serialization',rows[1]['reason'])
        self.assertEqual(rows[1]['overlapEvidence'][0]['signals']['sharedFiles'],['src/shared.py'])
        self.assertEqual(self.ledger()['graphql'],3)
        self.config.write_text(self.config.read_text().replace('implementation: 2','implementation: 1'))
        self.reset(active=2,statuses={'1':'Plan Ready','2':'Plan Ready'},priorities={'1':'Low','2':'Urgent'})
        rows={row['number']:row for row in self.scan()['classification']}
        self.assertEqual(rows[2]['dispatch'],'proposed');self.assertEqual(rows[1]['category'],'HELD')
        # Actual implementation-branch resumes pass the same concrete file gate.
        self.env['SCAN_FIXTURE_BRANCH']='fix/1-fixture'
        self.reset(active=2,statuses={'1':'In Development','2':'Plan Ready'},priorities={'1':'Low','2':'Urgent'})
        rows={row['number']:row for row in self.scan()['classification']}
        self.assertEqual(rows[1]['action'],'run-code-review-and-open-pr');self.assertEqual(rows[1]['category'],'HELD')
        self.env.pop('SCAN_FIXTURE_BRANCH')
        self.plan_files(1,['scripts/development-workflow/pr-review-loop.sh']);self.plan_files(2,['src/consumer.py'])
        self.reset(active=2,statuses={'1':'Plan Ready','2':'Plan Ready'},priorities={'1':'Low','2':'Urgent'})
        rows={row['number']:row for row in self.scan()['classification']}
        self.assertEqual(rows[1]['dispatch'],'proposed');self.assertEqual(rows[1]['toolFix'],'yes')
        self.assertEqual(rows[2]['category'],'HELD');self.assertIn('tool-fix merge for #1',rows[2]['reason'])
        # A waiting tool fix blocks consumers without redispatching itself.
        self.reset(active=2,pr=True,labels=[{'name':'ready-for-human-review'}],statuses={'1':'Development in Review','2':'Plan Ready'})
        rows={row['number']:row for row in self.scan()['classification']}
        self.assertEqual(rows[1]['category'],'INFORMATIONAL');self.assertEqual(rows[2]['category'],'HELD')
        self.assertIn('tool-fix merge for #1',rows[2]['reason'])
        # Tracker canonical references strengthen a local no classification.
        self.plan_files(1,['src/app.py'])
        self.reset(active=2,statuses={'1':'Plan Ready','2':'Plan Ready'},bodies={'1':'Change scripts/development-workflow/pr-ci-loop.sh'})
        rows={row['number']:row for row in self.scan()['classification']}
        self.assertEqual(rows[1]['toolFix'],'yes');self.assertEqual(rows[2]['category'],'HELD')
        # Keep the original unclassified planless pair as a conservative negative.
        import shutil
        shutil.rmtree(self.root/'docs/specs/developments')
        self.reset(active=2);report=self.scan();rows={row['number']:row for row in report['classification']}
        self.assertEqual(rows[1]['toolFix'],'unknown');self.assertEqual(rows[2]['category'],'HELD')
        self.assertIn('TOOL_FIX=unknown',rows[2]['reason']);self.assertEqual(report['recommendedCommand'],'/run-item 1')

    def test_unreadable_reset_other_consumers(self):
        for failures in ('1','2','both'):
            self.reset(sampleFailures=failures);report=self.scan()
            self.assertEqual(report['coverage'],scan.FULL)
            self.assertEqual(report['spend']['GraphQL points spent by this scan'],'Unavailable')
            self.assertIn('GraphQL budget could not be read',report['warnings'])
            if failures in ('2','both'):self.assertEqual(report['spend']['GraphQL points remaining'],'Unavailable')
        for override in ({'afterReset':2000003600},{'afterRemaining':4999}):
            self.reset(**override);self.assertEqual(self.scan()['spend']['GraphQL points spent by this scan'],'Unavailable (budget reset during scan)')
        self.reset(otherSpend=3500);report=self.scan();self.assertEqual(report['coverage'],scan.FULL)
        self.assertTrue(any('below reserve' in w for w in report['warnings']))
        self.reset(remaining=900,afterRemaining=800);self.assertFalse(any('below reserve' in w for w in self.scan()['warnings']))
        self.artifact()
        for initial,coverage in ((900,scan.DEFERRED),(1022,scan.PARTIAL),(4500,scan.FULL)):
            self.reset(remaining=initial,sampleFailures='2');report=self.scan();self.assertEqual(report['coverage'],coverage)

    def test_midscan_atomic_and_errors(self):
        for reject,coverage,size in ((1,scan.DEFERRED,0),(2,scan.DEFERRED,0),(3,scan.PARTIAL,1)):
            self.reset(reject=reject);report=self.scan();self.assertEqual(report['coverage'],coverage)
            self.assertEqual(len(report['fullyRead']),size)
            self.assertEqual(self.ledger()['graphql'],reject)
            self.assertFalse(any(row['action']=='start-backlog' for row in report['classification']))
            self.assertEqual(report['reason'],'GraphQL budget ran out during the scan')
        self.reset(nonrate=2);report=self.scan(ok=False);self.assertIn('Bad credentials',report['error']);self.assertFalse(report['classification'])
        self.reset(restFail=True);self.assertIn('Incomplete REST',self.scan(ok=False)['error'])
        self.reset(missingType=True);self.assertFalse(self.scan()['fullyRead'])
        self.reset(pr=True,prFail=True);self.assertFalse(self.scan(ok=False)['fullyRead'])
        self.reset(cost=2);self.assertIn('cost contract',self.scan(ok=False)['error'])
        for cli_exit in (False,True):
            self.reset(active=1,userNotFound=True,userNotFoundExit=cli_exit,partialCost=2)
            bad=self.scan(ok=False)
            self.assertIn('cost contract',bad['error']);self.assertEqual(self.ledger()['graphql'],1)
            self.assertEqual(bad['ledger'][0]['charged'],2)
            self.reset(active=1,userNotFound=True,userNotFoundExit=cli_exit,partialCost=1)
            self.assertEqual(self.scan()['projectionSpend'],2);self.assertEqual(self.ledger()['graphql'],3)
        for cost in (0,2):
            for rejected,size,coverage in ((1,0,scan.DEFERRED),(3,1,scan.PARTIAL)):
                self.reset(partialRate=rejected,partialCost=cost,partialRateExit=True)
                report=self.scan();self.assertEqual(report['coverage'],coverage)
                self.assertEqual(len(report['fullyRead']),size);self.assertEqual(self.ledger()['graphql'],rejected)
                self.assertEqual(report['ledger'][-1]['charged'],cost)
                self.assertEqual(report['reason'],'GraphQL budget ran out during the scan')

    def test_cache_types_and_malformed_cursor(self):
        cache=self.folder/'cache';cache.mkdir(mode=0o700)
        args=('python3',str(SCRIPTS/'workflow-project-reader.py'),'--fallback','--repo','fixture/repo','--project-id','P1','--number','1','--cache-dir',str(cache),'--cache-pid','fixture')
        self.reset(active=1)
        valid=json.loads(self.execute(*args).stdout)
        cached=next(cache.glob('fixture-*.json'))
        self.execute(*args);self.assertEqual(self.ledger()['graphql'],1)
        for invalid in (dict(valid,item_id=True),dict(valid,status=[]),dict(valid,type=None),dict(valid,depends_on={}),dict(valid,due_date=[]),dict(valid,due_date='bad-date'),{'membership':'absent','project_id':'P1','item_id':[]},'bad'):
            cached.write_text(json.dumps(invalid));before=self.ledger()['graphql']
            self.assertEqual(json.loads(self.execute(*args).stdout),valid)
            self.assertEqual(self.ledger()['graphql'],before+1)
        for cursor in (None,[],{},7):
            with self.assertRaises(scan.ReadError):
                scan.reader.connection({'nodes':[],'pageInfo':{'hasNextPage':True,'endCursor':cursor}})

    def test_fallback_identity_escape_archived_cap(self):
        result=self.target(org=True,title='quote " \\ repo:evil is:closed ☃',atCap=True,dueDates={'1':'2026-10-15'})
        item=json.loads(result.stdout);self.assertEqual(item['item_id'],'I1')
        self.assertEqual(item['due_date'],'2026-10-15')
        args=self.ledger()['calls'][-1];query=' '.join(args)
        self.assertIn('archivedStates:[ARCHIVED,NOT_ARCHIVED]',query)
        self.assertIn('repo:fixture/repo is:issue is:open "quote \\"',query)
        self.assertEqual(self.ledger()['graphql'],1)
        for overrides in ({'foreignOnly':True,'truncated':True},{'duplicate':True},{'malformed':'fallback'},{'missingIdentity':True},{'unsupported':True}):
            result=self.target(fails=True,**overrides);self.assertFalse(result.stdout.strip());self.assertEqual(self.ledger()['graphql'],1)
        result=self.target(foreignOnly=True);self.assertEqual(json.loads(result.stdout)['membership'],'absent')
        for override in ({'fallback':True},{'pages':20},{'repeatCursor':True},{'malformed':'primary'}):
            self.reset(active=1,**override)
            report=self.scan(ok=not bool(override.get('repeatCursor') or override.get('malformed')))
            self.assertLessEqual(self.ledger()['graphql'],22)
            if not report.get('error'):self.assertEqual(len(report['fullyRead']),1)
        self.reset(active=1,pages=20,forceEmptyPrimary=True);self.assertEqual(self.scan()['scanOwnedSpend'],22)
        self.reset(active=1,org=True);self.assertEqual(self.scan()['projectionSpend'],2)
        self.reset(active=1,pages=21);self.assertIn('pagination cap',self.scan(ok=False)['error'])

    def test_type_precedence_framework_and_pr(self):
        self.reset(active=1,nativeType='Feature');self.assertEqual(self.scan()['fullyRead'][0]['type'],'Feature')
        self.config.write_text('issue_tracker:\n  provider: github_projects\n  project_number: 1\n  custom_fields:\n    type_field: Classification\ntemplate:\n  is_template: true\n')
        self.reset(active=1,configuredType='Bug');self.assertEqual(self.scan()['fullyRead'][0]['type'],'Bug')
        # Fresh root configuration for framework hold/stale artifact bypass.
        self.config.write_text('issue_tracker:\n  provider: github_projects\n  project_number: 1\ntemplate:\n  is_template: true\n')
        self.reset(active=1,nativeType='Workflow');self.assertEqual(self.scan()['classification'][0]['category'],'HELD')
        self.artifact();self.reset(active=1,nativeType='Workflow');self.assertEqual(self.scan()['classification'][0]['category'],'ACTIONABLE RESUME')
        self.reset(active=1,pr=True,labels=[{'name':'ready-for-human-review'}]);report=self.scan();self.assertEqual(report['classification'][0]['category'],'INFORMATIONAL')
        self.reset(active=1,pr=True,labels=[{'name':'needs-fixes'}]);self.assertEqual(self.scan()['classification'][0]['category'],'ACTIONABLE RESUME')

    def test_snapshot_artifact_scope_before_reads(self):
        development=str(self.plan_files(1,['src/app.py']).relative_to(self.root))
        self.reset(active=1,statuses={'1':'Plan Ready'});report=self.scan()
        path=self.folder/'artifact-snapshot.json';self.env['WORKFLOW_SCAN_INVOCATION_ID']=report['invocation']
        foreign=self.folder/'foreign-artifacts';foreign.mkdir()
        (foreign/'2_1_foreign_implementation-plan.md').write_text('### Files modified\n```text\nforeign/sentinel.py\n```\n')
        foreign=foreign.resolve()
        marker=self.folder/'foreign-read-attempts'
        # Audit Python document opens and native grep reads of synthetic foreign
        # artifacts. Rejection must occur before either classifier can read.
        runtime_site=getattr(sys.modules.get('sitecustomize'),'__file__',None)
        bootstrap='import runpy;runpy.run_path('+repr(runtime_site)+')\n' if runtime_site else ''
        (self.bin/'sitecustomize.py').write_text(bootstrap+"import os,sys\ndef audit(event,args):\n if event=='open' and isinstance(args[0],(str,bytes)):\n  path=os.path.realpath(os.fsdecode(args[0]))\n  if path=="+repr(str(foreign))+" or path.startswith("+repr(str(foreign)+os.sep)+"):\n   with open("+repr(str(marker))+",'a') as out:out.write(path+'\\n')\n   raise RuntimeError('forbidden synthetic artifact read')\nsys.addaudithook(audit)\n")
        self.env['PYTHONPATH']=str(self.bin)+os.pathsep+self.env.get('PYTHONPATH','')
        realgrep=subprocess.check_output(['which','grep'],text=True).strip()
        (self.bin/'grep').write_text("#!/usr/bin/env python3\nimport os,sys\nfor arg in sys.argv[1:]:\n try:path=os.path.realpath(arg)\n except OSError:continue\n if path=="+repr(str(foreign))+" or path.startswith("+repr(str(foreign)+os.sep)+"):\n  with open("+repr(str(marker))+",'a') as out:out.write(path+'\\n')\n  sys.exit(91)\nos.execv("+repr(realgrep)+",["+repr(realgrep)+",*sys.argv[1:]])\n")
        (self.bin/'grep').chmod(0o755)
        self.execute('python3','-c','import yaml')
        self.execute('python3','-c','open('+repr(str(foreign/'2_1_foreign_implementation-plan.md'))+')',ok=False)
        self.assertTrue(marker.exists(),'Synthetic foreign-read monitor did not activate')
        marker.unlink()
        link=self.root/'docs/specs/developments/escaped-artifact';link.symlink_to(foreign,target_is_directory=True)
        before=len(self.ledger()['calls'])
        for invalid in (str(foreign),'../foreign-artifacts',str(link.relative_to(self.root)),None,[],7,'src/foreign',str(self.root/development)):
            bad=json.loads(json.dumps(report));bad['fullyRead'][0]['development_path']=invalid;path.write_text(json.dumps(bad))
            for script,target in (('workflow-batch-plan.sh',[]),('workflow-next-action.sh',['--development',development])):
                result=self.execute('bash',str(SCRIPTS/script),'--repo-root',str(self.root),'--scan-snapshot',str(path),*target,ok=False)
                self.assertEqual(result.stdout,'');self.assertIn('artifact',result.stderr.lower())
                self.assertNotIn('Error in sitecustomize',result.stderr)
                self.assertFalse(marker.exists(),'Consumer attempted a foreign artifact read')
                self.assertEqual(len(self.ledger()['calls']),before)
        # Even a valid directory must not admit a foreign Markdown symlink.
        document=self.root/development/'foreign.md';document.symlink_to(foreign/'2_1_foreign_implementation-plan.md')
        path.write_text(json.dumps(report))
        self.execute('bash',str(SCRIPTS/'workflow-batch-plan.sh'),'--repo-root',str(self.root),'--scan-snapshot',str(path),ok=False)
        self.assertFalse(marker.exists());self.assertEqual(len(self.ledger()['calls']),before)
        document.unlink()
        rows=json.loads(self.execute('bash',str(SCRIPTS/'workflow-batch-plan.sh'),'--repo-root',str(self.root),'--scan-snapshot',str(path)).stdout)
        self.assertEqual(rows[0]['action'],'implement');self.assertEqual(rows[0]['fileSet'],'src/app.py')
        self.assertIn('NEXT_ACTION=implement',self.execute('bash',str(SCRIPTS/'workflow-next-action.sh'),'--repo-root',str(self.root),'--scan-snapshot',str(path),'--development',development).stdout)
        self.assertFalse(marker.exists());self.assertEqual(len(self.ledger()['calls']),before)
        # Producer discovery shares admission, before opening any foreign doc.
        original=Path.read_text
        def tracked(document,*args,**kwargs):
            self.assertFalse(document.resolve().is_relative_to(foreign),'Producer attempted a foreign artifact read')
            return original(document,*args,**kwargs)
        with patch.object(Path,'read_text',tracked),patch.object(scan,'run',return_value=''):
            with self.assertRaisesRegex(scan.ReadError,'approved scope'):scan.current_local_evidence(self.root)
            link.unlink()
            document.symlink_to(foreign/'2_1_foreign_implementation-plan.md')
            with self.assertRaisesRegex(scan.ReadError,'approved scope'):scan.current_local_evidence(self.root)
            document.unlink()
            folders,_=scan.current_local_evidence(self.root);self.assertEqual(folders[1]['development_path'],development)

    def test_snapshot_repository_ownership(self):
        development=self.artifact(1)
        self.config.write_text(self.config.read_text()+'mode: workflow_hub\nworkflow_hub:\n  product_repos:\n    - name: mobile-app\n      github_repo: fixture/mobile-app\n')
        self.reset(active=1,statuses={'1':'Plan Ready'})
        report=self.scan();self.assertEqual(report['classification'][0]['action'],'resolve-repository-selection')
        self.assertEqual(report['classification'][0]['category'],'HELD');self.assertEqual(report['recommendedCommand'],'')
        path=self.folder/'ownership.json';path.write_text(json.dumps(report));self.env['WORKFLOW_SCAN_INVOCATION_ID']=report['invocation']
        before=len(self.ledger()['calls'])
        def next_action(target, selected=None):
            args=['bash',str(SCRIPTS/'workflow-next-action.sh'),'--repo-root',str(self.root),*target,'--scan-snapshot',str(path)]
            if selected:args+=['--repo',selected]
            result=self.execute(*args)
            self.assertEqual(len(self.ledger()['calls']),before)
            return result.stdout
        for selected, outcome in ((None,'missing_target'),('mobile-app','product_owned'),('foreign/slug','ambiguous_target'),('foreign-key','ambiguous_target')):
            result=next_action(['--development',development],selected)
            self.assertIn('CATEGORY=HELD',result);self.assertIn('NEXT_ACTION='+('hold-unreadable' if outcome=='product_owned' else 'resolve-repository-selection'),result)
            self.assertIn('ROUTING_OUTCOME_CODE='+outcome,result);self.assertNotIn('NEXT_ACTION=implement',result)
        # Hub PR and branch evidence cannot authorize the selected product.
        self.reset(active=1,pr=True,labels=[{'name':'needs-fixes'}],statuses={'1':'Development in Review'})
        report=self.scan();path.write_text(json.dumps(report));self.env['WORKFLOW_SCAN_INVOCATION_ID']=report['invocation'];before=len(self.ledger()['calls'])
        result=next_action(['--pr','70'],'mobile-app');self.assertIn('CATEGORY=HELD',result);self.assertNotIn('NEXT_ACTION=resume-fix-loop',result)
        report['fullyRead'][0]['branches']=['spec/1-fixture','fix/1-fixture'];path.write_text(json.dumps(report))
        self.assertIn('CATEGORY=HELD',next_action(['--branch','fix/1-fixture'],'mobile-app'))
        # Fresh, complete Type Workflow evidence admits hub-only implementation.
        self.reset(active=1,nativeType='Workflow',statuses={'1':'Plan Ready'})
        report=self.scan();path.write_text(json.dumps(report));self.env['WORKFLOW_SCAN_INVOCATION_ID']=report['invocation'];before=len(self.ledger()['calls'])
        result=next_action(['--development',development]);self.assertIn('NEXT_ACTION=implement',result);self.assertIn('ROUTING_OUTCOME_CODE=hub_only',result)
        result=next_action(['--development',development],'mobile-app');self.assertIn('CATEGORY=HELD',result);self.assertIn('ROUTING_OUTCOME_CODE=ambiguous_target',result)
        # Terminal records stay informational even with retained implementation evidence.
        self.reset(active=1,pr=True,statuses={'1':'Merged'})
        terminal=self.scan();self.assertEqual(terminal['classification'][0]['category'],'INFORMATIONAL')
        self.assertEqual(terminal['classification'][0]['action'],'skip')
        # Planning stays hub-owned; a documentation PR also stays hub-owned.
        self.reset(active=1,statuses={'1':'Spec Ready'})
        report=self.scan();path.write_text(json.dumps(report));self.env['WORKFLOW_SCAN_INVOCATION_ID']=report['invocation'];before=len(self.ledger()['calls'])
        self.assertIn('NEXT_ACTION=write-plan',next_action(['--development',development]))
        self.reset(active=1,pr=True,labels=[{'name':'needs-fixes'}],statuses={'1':'Spec in Review'})
        report=self.scan();report['fullyRead'][0]['prs'][0]['branch']='spec/1-fixture'
        path.write_text(json.dumps(report));self.env['WORKFLOW_SCAN_INVOCATION_ID']=report['invocation'];before=len(self.ledger()['calls'])
        self.assertIn('NEXT_ACTION=resume-fix-loop',next_action(['--pr','70']))

    def test_snapshot_planted_scope_violation(self):
        development=self.artifact();self.reset(active=1,statuses={'1':'Plan Ready'})
        report=self.scan();path=self.folder/'snapshot.json';path.write_text(json.dumps(report))
        self.env['WORKFLOW_SCAN_INVOCATION_ID']=report['invocation']
        before=len(self.ledger()['calls'])
        # Planted guard violation: wrong repository must refuse before fallthrough.
        bad=dict(report,repo='foreign/repo');path.write_text(json.dumps(bad))
        result=self.execute('bash',str(SCRIPTS/'workflow-batch-plan.sh'),'--repo-root',str(self.root),'--scan-snapshot',str(path),ok=False)
        self.assertIn('scope mismatch',result.stderr);self.assertEqual(len(self.ledger()['calls']),before)
        path.write_text(json.dumps(report))
        result=self.execute('bash',str(SCRIPTS/'workflow-next-action.sh'),'--repo-root',str(self.root),'--development',development,'--scan-snapshot',str(path))
        self.assertIn('NEXT_ACTION=implement',result.stdout);self.assertEqual(len(self.ledger()['calls']),before)
        for replacement in ({'invocation':'stale'},{'projectNumber':'2'},{'fullyRead':[dict(report['fullyRead'][0],fullyRead=False)]}):
            path.write_text(json.dumps(dict(report,**replacement)))
            self.execute('bash',str(SCRIPTS/'workflow-batch-plan.sh'),'--repo-root',str(self.root),'--scan-snapshot',str(path),ok=False)
        path.write_text('not json');self.execute('bash',str(SCRIPTS/'workflow-batch-plan.sh'),'--repo-root',str(self.root),'--scan-snapshot',str(path),ok=False)

    def test_snapshot_membership_and_pr_completeness(self):
        development=self.artifact();self.reset(active=1,statuses={'1':'Plan Ready'})
        report=self.scan();path=self.folder/'complete-snapshot.json'
        self.env['WORKFLOW_SCAN_INVOCATION_ID']=report['invocation']
        before=len(self.ledger()['calls'])

        def check_snapshot(snapshot, ok, target):
            path.write_text(json.dumps(snapshot))
            batch=self.execute('bash',str(SCRIPTS/'workflow-batch-plan.sh'),'--repo-root',str(self.root),'--scan-snapshot',str(path),ok=ok)
            next_action=self.execute('bash',str(SCRIPTS/'workflow-next-action.sh'),'--repo-root',str(self.root),*target,'--scan-snapshot',str(path),ok=ok)
            self.assertEqual(len(self.ledger()['calls']),before)
            if not ok:
                self.assertFalse(batch.stdout.strip());self.assertFalse(next_action.stdout.strip())
            return next_action

        def altered(snapshot, target, key, value, remove=False):
            copy=json.loads(json.dumps(snapshot));entry=copy['fullyRead'][0]
            if target=='pr':entry=entry['prs'][0]
            if remove:entry.pop(key,None)
            else:entry[key]=value
            return copy

        target=('--development',development)
        for key in ('item_id','project_id','implementationMerged'):
            check_snapshot(altered(report,'record',key,None,remove=True),False,target)
        for key,value in (('item_id',''),('item_id',True),('project_id',[]),('project_id','foreign-project'),('status',[]),('type',True),('membership','absent'),('implementationMerged','false'),('branches',['fix/2-other'])):
            check_snapshot(altered(report,'record',key,value),False,target)
        check_snapshot(dict(report,projectId=''),False,target)
        corrected=check_snapshot(report,True,target);self.assertIn('NEXT_ACTION=implement',corrected.stdout)
        # Empty Deferred reports legitimately never acquired a project identity.
        self.reset(active=1,remaining=900);deferred=self.scan()
        self.env['WORKFLOW_SCAN_INVOCATION_ID']=deferred['invocation'];before=len(self.ledger()['calls'])
        path.write_text(json.dumps(deferred))
        self.execute('bash',str(SCRIPTS/'workflow-batch-plan.sh'),'--repo-root',str(self.root),'--scan-snapshot',str(path))
        self.assertNotIn('projectId',deferred);self.assertEqual(len(self.ledger()['calls']),before)

        for ci_state,conclusion in (('pending',None),('failure','failure')):
            self.reset(active=1,pr=True,prComments=[{'body':'review evidence'}],
                       prStatus={'state':ci_state,'sha':'H1','statuses':[{'state':ci_state}]},
                       prChecks=[{'status':'in_progress' if conclusion is None else 'completed','conclusion':conclusion,'head_sha':'H1'}])
            report=self.scan();self.assertEqual(len(report['fullyRead']),1)
            self.env['WORKFLOW_SCAN_INVOCATION_ID']=report['invocation'];before=len(self.ledger()['calls'])
            target=('--pr','70')
            for key in ('number','branch','sha','draft','labels','comments','status','checks'):
                check_snapshot(altered(report,'pr',key,None,remove=True),False,target)
            for key,value in (('number',True),('number',0),('branch','fix/2-other'),('sha',''),('sha',[]),('draft','false'),('labels',{}),('comments',None),('comments',[{}]),('status',[]),('status',{'state':ci_state}),('status',{'state':ci_state,'sha':'foreign-sha','statuses':[]}),('checks',{}),('checks',{'check_runs':'bad'}),('checks',{'check_runs':[{}]}),('checks',{'check_runs':[{'status':'completed','conclusion':'failure','head_sha':'foreign-sha'}]})):
                check_snapshot(altered(report,'pr',key,value),False,target)
            corrected=check_snapshot(report,True,target)
            self.assertIn('NEXT_ACTION=resolve-pr-readiness',corrected.stdout)
        # The same validation runs before REST evidence becomes atomic fullyRead.
        for bad in ({'prComments':[{}]},{'prStatus':{'state':'pending'}},{'prChecks':[{'status':'completed'}]}):
            self.reset(active=1,pr=True,**bad);self.assertFalse(self.scan(ok=False)['fullyRead'])

    def test_same_window_bounded_start_and_epic(self):
        # Real resolvers/prelude/guards use the same fake gh ledger; only dispatch is mocked.
        runtime=self.root/'scripts/development-workflow';runtime.mkdir(parents=True)
        for source in SCRIPTS.iterdir():
            if source.is_file() and source.suffix in ('.sh','.py'):
                (runtime/source.name).symlink_to(source)
        statuses={str(n):'Released' for n in range(3,42)}
        statuses.update({'1':'Backlog','2':'Backlog'})
        # Explicit local brief evidence makes this a known non-tool-fix pair.
        self.brief_artifact(1);self.brief_artifact(2)
        self.config.write_text(self.config.read_text()+'guardrails:\n  parallelism:\n    max_concurrent_by_stage:\n      implementation: 2\n')
        self.reset(statuses=statuses)
        report=self.scan();self.assertEqual(report['recommendedCommand'],'/run-items 1 2')
        after_scan=self.ledger()['remaining'];self.assertGreaterEqual(after_scan,1000)
        self.env['AI_DEV_WORKFLOW_CONFIG_FILE']=str(self.config)
        self.env['GITHUB_PROJECT_OWNER']='fixture'
        self.env['GITHUB_REPO']='fixture/repo'
        routed=self.execute('bash',str(runtime/'run-work-router.sh'),'1','2')
        self.assertIn('MODE=redirect_items',routed.stdout)
        prelude=self.execute('bash',str(runtime/'run-bounded-prelude.sh'),'--original-command',report['recommendedCommand'],'--items','1,2','--base','develop','--delegate-review','--may-merge','--may-start-backlog','true','--max-risk','high','--json')
        scope=json.loads(prelude.stdout)
        self.assertFalse(scope.get('stopCondition'))
        items=scope.get('scope',scope.get('scopePayload',{})).get('items',[])
        if not items:items=scope.get('items',[])
        self.assertTrue(items,scope)
        self.assertTrue(all(item['status']=='Backlog' and item['type']=='Bug' for item in items))
        self.execute('bash',str(runtime/'validate-workflow-branch-name.sh'),'fix/1-fixture')
        self.execute('bash',str(runtime/'run-nested-artifact-guard.sh'),'--mode','pre-create','--issue','1','--expected-branch','fix/1-fixture','--approved-base','develop','--repo-root',str(self.root))
        # Authorized fixture dispatch records first-stage start after real gates.
        dispatch=self.folder/'dispatch.json';dispatch.write_text(json.dumps({'issue':1,'stage':'implementation','freshScope':True,'started':True}))
        self.assertTrue(json.loads(dispatch.read_text())['started'])
        self.assertEqual(self.ledger()['reset'],2000000000)
        self.assertLess(self.ledger()['remaining'],after_scan)
        self.assertGreater(self.ledger()['remaining'],0)
        epic=self.execute('bash',str(runtime/'run-epic-scope-resolver.sh'),'--epic','10','--base','develop','--may-start-backlog','true','--json')
        self.assertEqual([item['number'] for item in json.loads(epic.stdout)['items']],[1,2])
        single=self.execute('bash',str(runtime/'run-item-scope-resolver.sh'),'--issue','1','--base','develop','--may-start-backlog','true','--json')
        self.assertEqual(json.loads(single.stdout)['items'][0]['type'],'Bug')
        if os.environ.get('WORKFLOW_PORTFOLIO_EVIDENCE_DIR'):
            (Path(os.environ['WORKFLOW_PORTFOLIO_EVIDENCE_DIR'])/'same-window-bounded-start.json').write_text(json.dumps({'afterScanRemaining':after_scan,'freshPrelude':scope,'dispatch':json.loads(dispatch.read_text()),'epic':json.loads(epic.stdout),'single':json.loads(single.stdout),'ledger':self.ledger()},indent=2))
        growth=[]
        for history in (50,1000):
            self.reset(history=history)
            results=[self.execute('bash',str(runtime/'run-item-scope-resolver.sh'),'--issue','1','--base','develop','--may-start-backlog','true','--json'),
                     self.execute('bash',str(runtime/'run-bounded-prelude.sh'),'--original-command','/run-items 1 2','--items','1,2','--base','develop','--delegate-review','--may-merge','--may-start-backlog','true','--max-risk','high','--json'),
                     self.execute('bash',str(runtime/'run-epic-scope-resolver.sh'),'--epic','10','--base','develop','--may-start-backlog','true','--json')]
            for result in results:
                value=json.loads(result.stdout)
                items=value.get('items') or value.get('scope',value.get('scopePayload',{})).get('items',[])
                self.assertTrue(items);self.assertTrue(all(item['status']=='Backlog' and item['type']=='Bug' for item in items))
            growth.append(self.ledger()['graphql'])
        self.assertEqual(growth[0],growth[1])
        if os.environ.get('WORKFLOW_PORTFOLIO_EVIDENCE_DIR'):
            (Path(os.environ['WORKFLOW_PORTFOLIO_EVIDENCE_DIR'])/'bounded-history-growth.json').write_text(json.dumps({'terminalCounts':[50,1000],'chargedRequests':growth},indent=2))

    def test_local_and_tracker_dependency_contract(self):
        development=self.root/self.artifact();self.artifact(2)
        spec=next(development.glob('1_*_specs.md'));plan=next(development.glob('2_*_implementation-plan.md'))
        for document,label in ((spec,'**Depends on**'),(plan,'**Dependencies**')):
            for declaration in ('#2','2-fixture'):
                document.write_text(label+': '+declaration+'\n')
                for status,action in (('Backlog','hold-dependency'),('Cancelled','hold-dependency'),('Merged','implement'),('Released','implement')):
                    self.reset(active=2,statuses={'1':'Plan Ready','2':status});report=self.scan()
                    row=next(row for row in report['classification'] if row['number']==1)
                    self.assertEqual(row['action'],action)
                    record=next(record for record in report['fullyRead'] if record['number']==1)
                    self.assertEqual(record['dependencies'],[2]);self.assertEqual(self.ledger()['graphql'],3)
            document.write_text(label+': unknown-prerequisite\n')
            self.reset(active=2,statuses={'1':'Plan Ready'})
            report=self.scan();self.assertNotIn(1,[record['number'] for record in report['fullyRead']])
            self.assertTrue(any(entry['number']==1 and 'Unresolved dependency' in entry['reason'] for entry in report['omissions']))
            for absence in ('None','none.','None. No prerequisites.'):
                document.write_text(label+': '+absence+'\n')
                self.reset(active=1,statuses={'1':'Plan Ready'},body='DependsOn: none')
                report=self.scan();self.assertEqual(report['classification'][0]['action'],'implement')
                self.assertEqual(report['fullyRead'][0]['dependencies'],[])
            document.write_text('fixture\n')
        plan.write_text('## Dependencies\n\n- #2\n\n## Implementation\nNo other dependency.\n')
        self.reset(active=1,statuses={'1':'Plan Ready'});report=self.scan()
        self.assertFalse(report['fullyRead']);self.assertIn('Dependency tracker state unreadable',report['omissions'][0]['reason'])
        plan.write_text('**Dependencies**: None\n')
        for body in ('Dependencies: None','**Depends on**: none','| Dependencies | None |','Dependencies: unknown','DependsOn: #2'):
            self.reset(active=2,statuses={'1':'Plan Ready','2':'Backlog'},bodies={'1':body})
            report=self.scan()
            if 'unknown' in body:self.assertNotIn(1,[record['number'] for record in report['fullyRead']])
            else:
                row=next(row for row in report['classification'] if row['number']==1)
                self.assertEqual(row['action'],'hold-dependency' if '#2' in body else 'implement')

    def test_mixed_dependency_members_preserved(self):
        development=self.root/self.artifact();self.artifact(2);self.artifact(3)
        for pattern,label in (('1_*_specs.md','**Depends on**'),('2_*_implementation-plan.md','**Dependencies**')):
            document=next(development.glob(pattern))
            for declaration in ('#2, 3-fixture','2-fixture, #3','[#2, 3-fixture]'):
                document.write_text(label+': '+declaration+'\n')
                for state,action in (('Backlog','hold-dependency'),('Cancelled','hold-dependency'),('Released','implement')):
                    self.reset(active=3,statuses={'1':'Plan Ready','2':'Merged','3':state})
                    report=self.scan();row=next(row for row in report['classification'] if row['number']==1)
                    self.assertEqual(row['action'],action,declaration)
                    record=next(record for record in report['fullyRead'] if record['number']==1)
                    self.assertEqual(record['dependencies'],[2,3]);self.assertEqual(self.ledger()['graphql'],4)
            for declaration in ('#2, unknown-prerequisite','unknown-prerequisite, #2'):
                document.write_text(label+': '+declaration+'\n')
                self.reset(active=3,statuses={'1':'Plan Ready','2':'Merged','3':'Released'})
                report=self.scan();self.assertNotIn(1,[record['number'] for record in report['fullyRead']])
                self.assertNotIn(1,[row['number'] for row in report['classification']])
                self.assertTrue(any(entry['number']==1 and 'Unresolved dependency' in entry['reason'] for entry in report['omissions']))
                self.assertEqual(self.ledger()['graphql'],4)
            document.write_text('fixture\n')
        # Real tracker fields have the same complete-member contract.
        for declaration in ('#2, 3-fixture','#2, unknown-prerequisite'):
            self.reset(active=3,statuses={'1':'Plan Ready','2':'Merged','3':'Backlog'},dependsOn=declaration)
            report=self.scan()
            if 'unknown' in declaration:self.assertNotIn(1,[record['number'] for record in report['fullyRead']])
            else:
                row=next(row for row in report['classification'] if row['number']==1)
                self.assertEqual(row['action'],'hold-dependency')
                self.assertEqual(next(record for record in report['fullyRead'] if record['number']==1)['dependencies'],[2,3])
            self.assertEqual(self.ledger()['graphql'],4)

    def test_dependency_producer_boundaries(self):
        development=self.root/self.artifact();self.artifact(2);self.artifact(3)
        plan=next(development.glob('2_*_implementation-plan.md'))
        sources=[({'dependsOn':'#2','dependencies':'3-fixture'},None,[2,3]),
                 ({'dependsOn':'#2','dependencies':'unknown-prerequisite'},None,None),
                 ({'dependsOn':'None.','dependencies':'#3'},None,[3]),
                 ({'dependsOn':'None. No prerequisites.','dependencies':'#3'},None,[3]),
                 ({},'- None. No prerequisites.\n- #3',[3]),
                 ({},'- #2\n- 3-fixture',[2,3]),
                 ({},'- #2\n- unknown-prerequisite',None)]
        for fields,section,expected in sources:
            plan.write_text('## Dependencies\n'+section+'\n## Implementation\nfixture\n' if section else 'fixture\n')
            for state in ('Backlog','Released'):
                self.reset(active=3,statuses={'1':'Plan Ready','2':'Merged','3':state},**fields)
                report=self.scan();self.assertEqual(self.ledger()['graphql'],4)
                if expected is None:
                    self.assertNotIn(1,[record['number'] for record in report['fullyRead']])
                    self.assertNotIn(1,[row['number'] for row in report['classification']])
                    self.assertTrue(any(entry['number']==1 and 'Unresolved dependency' in entry['reason'] for entry in report['omissions']))
                else:
                    record=next(record for record in report['fullyRead'] if record['number']==1)
                    self.assertEqual(record['dependencies'],expected)
                    row=next(row for row in report['classification'] if row['number']==1)
                    self.assertEqual(row['action'],'hold-dependency' if state=='Backlog' else 'implement')
        # Ordinary descriptions and independent explicit None members survive.
        for fields,section,expected in (({'dependsOn':'#2 (foundation)','dependencies':'None.'},None,[2]),
                                        ({'dependsOn':'None.','dependencies':'None'},None,[]),
                                        ({},'- None.\n- #2 (foundation)',[2])):
            plan.write_text('## Dependencies\n'+section+'\n## Implementation\nfixture\n' if section else 'fixture\n')
            self.reset(active=3,statuses={'1':'Plan Ready','2':'Merged','3':'Released'},**fields)
            report=self.scan();record=next(record for record in report['fullyRead'] if record['number']==1)
            self.assertEqual(record['dependencies'],expected)
            self.assertEqual(next(row for row in report['classification'] if row['number']==1)['action'],'implement')
            self.assertEqual(self.ledger()['graphql'],4)

    def test_tracker_dependency_field_absence_and_unknown(self):
        self.artifact()
        for field in ('dependsOn','dependencies'):
            for value, action in (('None','implement'),('none.','implement'),('#2','hold-dependency'),('unknown prerequisite',None)):
                self.reset(active=2,statuses={'1':'Plan Ready','2':'Backlog'},**{field:value})
                report=self.scan();self.assertEqual(self.ledger()['graphql'],3)
                if action is None:
                    self.assertNotIn(1,[record['number'] for record in report['fullyRead']])
                    self.assertTrue(any('Unresolved dependency' in entry['reason'] for entry in report['omissions']))
                else:
                    row=next(row for row in report['classification'] if row['number']==1)
                    self.assertEqual(row['action'],action)

    def test_malformed_dependency_field_atomicity(self):
        self.artifact()
        for field in ('dependsOn','dependencies'):
            for value in ('unknown',[],7,{}, {'text':[]},{'text':7}):
                self.reset(active=1,statuses={'1':'Plan Ready'},dependencyRaw={field:value})
                report=self.scan(ok=False)
                self.assertEqual(report['fullyRead'],[]);self.assertEqual(report['classification'],[])
                self.assertEqual(report['recommendedCommand'],'');self.assertEqual(self.ledger()['graphql'],2)
                self.assertIn('Unknown dependency field type' if value=={} else 'Malformed dependency field evidence',report['error'])
            for value in (None,{'text':None},{'text':''},{'text':'None'}):
                self.reset(active=1,statuses={'1':'Plan Ready'},dependencyRaw={field:value})
                report=self.scan();self.assertEqual(report['fullyRead'][0]['dependencies'],[])
                self.assertEqual(report['classification'][0]['action'],'implement');self.assertEqual(self.ledger()['graphql'],2)

    def test_bounded_dependency_field_consumer_compatibility(self):
        with patch.dict(os.environ,self.env):
            for field in ('dependsOn','dependencies'):
                for value in ({},{'text':None}):
                    for fallback in (False,True):
                        client=scan.reader.Client()
                        self.reset(active=1,dependencyRaw={field:value})
                        card=(scan.reader.fallback if fallback else scan.reader.target)(client,1,'P1','fixture/repo')
                        self.assertEqual(card['item_id'],'I1');self.assertEqual(card['status'],'Backlog')
                        self.assertEqual(card['type'],'Bug');self.assertEqual(card['depends_on'],'')
                        self.assertEqual(self.ledger()['graphql'],1)
                    # Strict fallback must not borrow a permissive cached empty fragment.
                    cache=self.folder/('dependency-cache-'+field+('-unknown' if value=={} else '-nullable'));cache.mkdir(mode=0o700,exist_ok=True)
                    self.reset(active=1,dependencyRaw={field:value});client=scan.reader.Client()
                    args=(client,1,'P1','fixture/repo','',str(cache),'fixture',5)
                    scan.reader.fallback(*args)
                    if value=={}:
                        with self.assertRaisesRegex(scan.ReadError,'Unknown dependency field type'):
                            scan.reader.fallback(*args,strict_dependencies=True)
                    else:self.assertEqual(scan.reader.fallback(*args,strict_dependencies=True)['item_id'],'I1')
                    self.assertEqual(self.ledger()['graphql'],2)

    def test_review_fix_loop_lane_composition(self):
        self.artifact()
        for status in ('Spec in Review','Plan in Review','Development in Review'):
            for labels,expected in (([{'name':'needs-fixes'}],'ACTIONABLE RESUME'),([], 'INFORMATIONAL'),([{'name':'ready-for-human-review'}],'INFORMATIONAL'),([{'name':'needs-fixes'},{'name':'ready-for-human-review'}],'INFORMATIONAL')):
                self.reset(active=1,pr=True,statuses={'1':status},labels=labels,prBranch={'Spec in Review':'spec/1-fixture','Plan in Review':'implementation-plan/1-fixture','Development in Review':'fix/1-fixture'}[status])
                report=self.scan();row=report['classification'][0]
                self.assertEqual(row['category'],expected)
                if expected=='ACTIONABLE RESUME':
                    self.assertEqual(row['action'],'resume-fix-loop');self.assertEqual(row['dispatch'],'proposed')
                else:self.assertFalse(report['recommendedCommand'])
                self.assertEqual(self.ledger()['graphql'],2)

    def test_merged_implementation_reconciles_stale_backlog(self):
        development=self.artifact();slug=Path(development).name.split('_',1)[1]
        for status in ('Backlog','Plan Ready'):
            for prefix in ('feature','fix','hotfix'):
                self.reset(active=1,statuses={'1':status},mergedHeads=[prefix+'/'+slug])
                report=self.scan();row=report['classification'][0]
                self.assertTrue(report['fullyRead'][0]['implementationMerged'])
                self.assertEqual(row['category'],'HELD');self.assertEqual(row['action'],'reconcile-tracker')
                self.assertFalse(report['recommendedCommand']);self.assertEqual(self.ledger()['graphql'],2)
                closed=[call[-1] for call in self.ledger()['calls'] if 'pulls?state=closed' in call[-1]]
                self.assertTrue(all('&head=fixture:' in endpoint for endpoint in closed));self.assertLessEqual(len(closed),3)
        # Active branch/current PR evidence still takes precedence over retained merges.
        self.env['SCAN_FIXTURE_BRANCH']='fix/1-fixture'
        self.reset(active=1,mergedHeads=['fix/'+slug]);report=self.scan()
        self.assertEqual(report['classification'][0]['action'],'run-code-review-and-open-pr')
        self.assertFalse(any('pulls?state=closed' in call[-1] for call in self.ledger()['calls']))
        self.env.pop('SCAN_FIXTURE_BRANCH')
        self.reset(active=1,pr=True,mergedHeads=['fix/'+slug]);report=self.scan()
        self.assertEqual(report['classification'][0]['action'],'resolve-pr-readiness')
        self.assertFalse(any('pulls?state=closed' in call[-1] for call in self.ledger()['calls']))

    def test_retained_document_branches_and_stale_backlog(self):
        self.env['AI_DEV_WORKFLOW_CONFIG_FILE']=str(self.config)
        self.env['WORKFLOW_SKIP_FETCH']='1'
        self.env['GITHUB_PROJECT_OWNER']='fixture'
        for plan,action in ((False,'write-plan'),(True,'implement')):
            development=self.artifact(plan=plan)
            self.env['SCAN_FIXTURE_BRANCH']='spec/1-fixture' if not plan else 'implementation-plan/1-fixture'
            self.reset(active=1,statuses={'1':'Backlog'},nativeType='Workflow')
            report=self.scan();self.assertEqual(report['classification'][0]['action'],action)
            current=self.execute('bash',str(SCRIPTS/'workflow-next-action.sh'),'--repo-root',str(self.root),'--development',development)
            self.assertIn('NEXT_ACTION='+action,current.stdout)
        self.reset(active=1,statuses={'1':'Plan Ready'});self.assertEqual(self.scan()['classification'][0]['action'],'implement')
        self.env['SCAN_FIXTURE_BRANCH']='fix/1-fixture'
        self.reset(active=1,statuses={'1':'Backlog'},nativeType='Workflow')
        row=self.scan()['classification'][0]
        self.assertEqual(row['action'],'run-code-review-and-open-pr');self.assertEqual(row['category'],'ACTIONABLE RESUME')
        current=self.execute('bash',str(SCRIPTS/'workflow-next-action.sh'),'--repo-root',str(self.root),'--branch','fix/1-fixture')
        self.assertIn('NEXT_ACTION=run-code-review-and-open-pr',current.stdout)
        # Branch-only stale Backlog also resumes its actual stage.
        import shutil
        shutil.rmtree(self.root/'docs/specs/developments')
        for prefix,action in (('spec','run-spec-review-and-open-pr'),('implementation-plan','run-plan-review-and-open-pr'),('fix','run-code-review-and-open-pr')):
            self.env['SCAN_FIXTURE_BRANCH']=prefix+'/1-fixture'
            self.reset(active=1,nativeType='Workflow')
            row=self.scan()['classification'][0]
            self.assertEqual(row['action'],action);self.assertEqual(row['category'],'ACTIONABLE RESUME')
            current=self.execute('bash',str(SCRIPTS/'workflow-next-action.sh'),'--repo-root',str(self.root),'--branch',prefix+'/1-fixture')
            self.assertIn('NEXT_ACTION='+action,current.stdout)
        self.artifact()
        self.env.pop('SCAN_FIXTURE_BRANCH')
        # Closed issue alone does not prove Merged/Released dependency readiness.
        self.reset(active=1,statuses={'1':'Plan Ready'},body='Depends on #2',state='closed')
        report=self.scan();self.assertFalse(report['classification']);self.assertTrue(report['omissions'])
        for status,expected in (('Released','implement'),('Merged','implement'),('Cancelled','hold-dependency'),('Backlog','hold-dependency')):
            self.reset(active=2,statuses={'1':'Plan Ready','2':status})
            # Only issue 1 declares the dependency; fixture issue 2 must not self-depend.
            state=self.ledger();state['bodies']={'1':'**DependsOn**: #2'};self.state.write_text(json.dumps(state))
            report=self.scan();row=next(row for row in report['classification'] if row['number']==1)
            self.assertEqual(row['action'],expected)
        self.reset(active=1,statuses={'1':'Plan Ready'},body='Dependencies: external unknown')
        self.assertFalse(self.scan()['fullyRead'])


if __name__=='__main__':unittest.main(verbosity=2)

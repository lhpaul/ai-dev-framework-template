#!/usr/bin/env python3
"""Composed fixture proofs; fake gh never forwards a request to GitHub."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

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
if args[:2]==['pr','list']:raw('[]')
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
 issues=[{'number':i,'title':'Fixture '+str(i),'body':state.get('bodies',{}).get(str(i),state.get('body','')),'state':'open'} for i in range(1,state.get('active',41)+1)]
 finish([issues[:20],issues[20:]])
if 'pulls?state=all&base=' in endpoint:finish([[]])
if endpoint.endswith('pulls?state=open&per_page=100'):
 prs=[{'number':70,'head':{'ref':'fix/1-fixture'}}] if state.get('pr') else []
 finish([prs])
if endpoint.endswith('/pulls/70'):finish({'number':70,'head':{'ref':'fix/1-fixture','sha':'H1'},'draft':True,'labels':state.get('labels',[])})
if endpoint.endswith('/issues/70/comments?per_page=100'):
 if state.get('prFail'):finish(error='PR evidence unavailable')
 finish([[]])
if endpoint.endswith('/commits/H1/status'):finish({'state':'success','statuses':[]})
if endpoint.endswith('/commits/H1/check-runs?per_page=100'):finish([{'check_runs':[]},{'check_runs':[]}])
if '/pulls?state=closed&head=' in endpoint:finish([[]])
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
        self.assertEqual(report['recommendedCommand'].split()[0],'/run-items')
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
        for invalid in (dict(valid,item_id=True),dict(valid,status=[]),dict(valid,type=None),dict(valid,depends_on={}),{'membership':'absent','project_id':'P1','item_id':[]},'bad'):
            cached.write_text(json.dumps(invalid));before=self.ledger()['graphql']
            self.assertEqual(json.loads(self.execute(*args).stdout),valid)
            self.assertEqual(self.ledger()['graphql'],before+1)
        for cursor in (None,[],{},7):
            with self.assertRaises(scan.ReadError):
                scan.reader.connection({'nodes':[],'pageInfo':{'hasNextPage':True,'endCursor':cursor}})

    def test_fallback_identity_escape_archived_cap(self):
        result=self.target(org=True,title='quote " \\ repo:evil is:closed ☃',atCap=True)
        item=json.loads(result.stdout);self.assertEqual(item['item_id'],'I1')
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

    def test_same_window_bounded_start_and_epic(self):
        # Real resolvers/prelude/guards use the same fake gh ledger; only dispatch is mocked.
        runtime=self.root/'scripts/development-workflow';runtime.mkdir(parents=True)
        for source in SCRIPTS.iterdir():
            if source.is_file() and source.suffix in ('.sh','.py'):
                (runtime/source.name).symlink_to(source)
        statuses={str(n):'Released' for n in range(3,42)}
        statuses.update({'1':'Backlog','2':'Backlog'})
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

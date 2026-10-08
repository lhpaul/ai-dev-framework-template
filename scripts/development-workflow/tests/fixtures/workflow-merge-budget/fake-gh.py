#!/usr/bin/env python3
"""Synthetic #1890 provider; every unknown command fails, never forwards."""
import json
import os
from pathlib import Path
import subprocess
import sys

args = sys.argv[1:]
path = Path(os.environ['MERGE_BUDGET_FIXTURE'])
state = json.loads(path.read_text())
state.setdefault('events', []).append(args[:2])
path.write_text(json.dumps(state))

def save():
    path.write_text(json.dumps(state))

def emit(value):
    if '--jq' in args:
        result = subprocess.run(['jq', '-r', args[args.index('--jq')+1]], input=json.dumps(value), text=True, capture_output=True)
        print(result.stdout, end='')
        sys.exit(result.returncode)
    print(json.dumps(value))
    sys.exit(0)

if args[:2] == ['api', 'rate_limit']:
    if state.get('quotaOutage'):
        sys.exit(1)
    emit({'resources': {'graphql': state['quota']}})
if args[:2] == ['repo', 'view']:
    checkout = subprocess.run(['git','rev-parse','--show-toplevel'],text=True,capture_output=True).stdout.strip()
    repository = os.environ.get('GH_REPO',state.get('checkoutRepos',{}).get(checkout,state['repo']))
    emit({'nameWithOwner': repository, 'owner': {'login': state['repo'].split('/')[0]}, 'name': state['repo'].split('/')[1]})
if args[:2] == ['api', 'graphql']:
    query = next((a[6:] for a in args if a.startswith('query=')), '')
    if 'MergeBudgetPR' in query:
        if state.get('prOutage'):
            sys.exit(1)
        number = int(next(a[7:] for a in args if a.startswith('number=')))
        emit({'data': {'repository': {'pullRequest': state['prs'][str(number)]}}})
    if 'updateProjectV2ItemFieldValue' in query:
        if state.get('trackerFailure'):
            sys.exit(1)
        state.setdefault('trackerMutationRepos',[]).append(os.environ.get('GH_REPO',state['repo']))
        state['trackerMutationCount'] = state.get('trackerMutationCount',0)+1
        state['trackerStatus'] = 'Merged'
        save()
        emit({'data': {'updateProjectV2ItemFieldValue': {'projectV2Item': {'id': 'item'}}}})
    if 'projectItems(' in query:
        number = int(next(a.split('=', 1)[1] for a in args if a.startswith('issueNumber=')))
        emit({'data': {'repository': {'issue': {'projectItems': {
            'nodes': [{'id': 'item', 'project': {'id': 'project', 'number': 1},
                       'content': {'number': number, 'url': 'https://github.com/'+state['repo']+'/issues/'+str(number), 'repository': {'nameWithOwner': state['repo']}},
                       'status': {'name': state.get('trackerStatus', 'Plan Ready')}}],
            'pageInfo': {'hasNextPage': False, 'endCursor': None}}}}, 'rateLimit': {'cost': 1}}})
    if 'fields(' in query:
        emit({'data': {'node': {'fields': {'nodes': [{'id': 'field', 'name': 'Status', 'options': [{'id': 'merged', 'name': 'Merged'}, {'id': 'plan', 'name': 'Plan Ready'}]}], 'pageInfo': {'hasNextPage': False, 'endCursor': None}}}}})
    if 'projectV2(' in query:
        emit({'data': {'user': {'projectV2': {'id': 'project'}}, 'organization': {'projectV2': {'id': 'project'}}}})
    sys.exit(1)
if args[:2] == ['pr', 'view']:
    value = dict(state['prs'][str(args[2])])
    value.update(body=state.get('body', ''), title=state.get('title', ''), commits=[],
                 isCrossRepository=state.get('fork', False), labels=[], isDraft=False)
    emit(value)
if args[:2] == ['pr', 'merge']:
    state.setdefault('mergeArgv',[]).append(args)
    checkout = subprocess.run(['git','rev-parse','--show-toplevel'],text=True,capture_output=True).stdout.strip()
    repository = args[args.index('--repo')+1] if '--repo' in args else os.environ.get('GH_REPO',state.get('checkoutRepos',{}).get(checkout,state['repo']))
    state.setdefault('mergeContexts',[]).append({'repo':repository,'cwd':checkout})
    if repository.lower() != state['repo'].lower():
        state['foreignMergeCount'] = state.get('foreignMergeCount',0)+1
        save()
        sys.exit(0)
    value = state['prs'][str(args[2])]
    if state.get('queue'):
        value['isInMergeQueue'] = True
    else:
        value['state'] = 'MERGED'
    if state.get('mergePause'):
        import signal
        import time
        if state['mergePause'] == 'ignore':
            signal.signal(signal.SIGTERM,signal.SIG_IGN)
            signal.signal(signal.SIGINT,signal.SIG_IGN)
        state['mergeReady'] = True
        save()
        while not json.loads(path.read_text()).get('mergeRelease'):
            time.sleep(0.02)
    save()
    sys.exit(0)
if args[:2] == ['issue', 'view']:
    emit({'number': int(args[2]), 'state': state.get('issueState', 'CLOSED')})
if args[:2] == ['issue', 'close']:
    state.setdefault('issueMutationRepos',[]).append(os.environ.get('GH_REPO',state['repo']))
    if '--comment' in args and not state.get('omitCloseComment'):
        state.setdefault('comments', []).append({'id': len(state.get('comments',[]))+1, 'body': args[args.index('--comment')+1]})
    if state.get('closeFailure'):
        save()
        sys.exit(1)
    state['issueState'] = 'CLOSED'
    save()
    sys.exit(0)
if args[:2] == ['issue','comment']:
    state.setdefault('comments',[]).append({'id':len(state.get('comments',[]))+1,'body':args[args.index('--body')+1]})
    save()
    sys.exit(0)
if args[:1] == ['api'] and any('/comments' in a for a in args):
    comments = state.get('comments', [])
    if '-X' in args and args[args.index('-X')+1] in {'POST','PATCH'}:
        if state.get('auditFailure'):
            sys.exit(1)
        body = next(a[5:] for a in args if a.startswith('body='))
        if args[args.index('-X')+1] == 'PATCH':
            endpoint = next(a for a in args if '/comments/' in a)
            comment_id = int(endpoint.rsplit('/',1)[1])
            found = next((c for c in comments if c['id']==comment_id),None)
            if found is None:
                sys.exit(1)
            found['body'] = body
            if state.get('auditPatchReadOutage'):
                state['commentReadOutage'] = True
        else:
            found = {'id':len(comments)+1,'body':body}
            comments.append(found)
        state['commentMutationCount'] = state.get('commentMutationCount',0)+1
        state['comments'] = comments
        save()
        emit(found)
    if state.get('commentReadOutage'):
        sys.exit(1)
    emit([comments] if '--slurp' in args else comments)
if args[:2] == ['auth', 'status']:
    sys.exit(0)
sys.exit(1)

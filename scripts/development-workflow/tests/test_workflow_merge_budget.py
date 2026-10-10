#!/usr/bin/env python3
"""#1890 durable admission proofs; no remote requests or user-resource cleanup."""
import argparse
import importlib.util
import json
import os
import shutil
import subprocess
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location('merge_budget', Path(__file__).resolve().parents[1] / 'workflow-merge-budget.py')
budget = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(budget)
RAW_GH = budget.gh
RAW_RESERVE = budget.reserve
RAW_PR_READ = budget.pr_read


class Admission(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='1890-merge-budget-')
        self.addCleanup(self.temp.cleanup)
        self.owner = Path(self.temp.name).resolve()
        self.common = self.owner / '.git'
        self.common.mkdir()
        self.live = {'number': 12, 'state': 'OPEN', 'headRefName': 'feature/12-item',
                     'headRefOid': 'a' * 40, 'baseRefName': 'develop',
                     'isInMergeQueue': False, 'autoMergeRequest': None}
        self.sample = {'remaining': 5000, 'reset': int(time.time()) + 3600, 'limit': 5000}
        self.manifest = self.owner / '1890-manifest.json'
        self.manifest.write_text(json.dumps({'ownerRoot': str(self.owner), 'prs': [{
            'repo': 'org/repo', 'pr': 12, 'head': 'a'*40, 'base': 'develop',
            'root': str(self.owner), 'phases': ['merge_api', 'cleanup']}]}))
        for name, replacement in [('root', lambda p: self.owner), ('common', lambda p: self.common),
                                  ('checkout_repo', lambda p: 'org/repo'), ('reserve', lambda p, v: 1000), ('pr_read', lambda p: dict(self.live)),
                                  ('inspect', lambda p, o: {'issues': []}),
                                  ('gh', lambda *a, **k: {'resources': {'graphql': dict(self.sample)}})]:
            mock = patch.object(budget, name, replacement)
            mock.start()
            self.addCleanup(mock.stop)
        self.args = argparse.Namespace(input=str(self.manifest), repo_root=str(self.owner), reserve=None,
            session=None, repo='org/repo', pr=12, phase='merge_api', step='merge_api', issue=None,
            status=None, executor_pid=os.getpid(), expected_file=None, exit_code=0)

    def begin(self):
        value = budget.begin(self.args)
        self.args.session = value['session']
        return value

    def test_newly_issued_retry_drops_historical_supersession_reference(self):
        manifest = json.loads(self.manifest.read_text())
        manifest['prs'][0].pop('phases')
        manifest['prs'][0]['steps'] = [dict(id='audit',phase='audit',auditRepo='org/repo',
            auditTarget=900,marker='<!-- ledger -->')]
        self.manifest.write_text(json.dumps(manifest));self.begin()
        with budget.journal(self.args.session) as state:
            state['prs'][0]['steps']['audit'].update(supersededBy='historical',retryVerifiedAt=budget.now(),
                expectedBody='<!-- ledger --> retry')
        body = self.owner/'1890-retry-body';body.write_text('<!-- ledger --> retry')
        self.args.phase='audit';self.args.step='audit';self.args.expected_file=str(body)
        budget.before(self.args)
        entry = budget.snapshot(self.args.session)['prs'][0]['steps']['audit']
        self.assertEqual(entry['status'],'in_flight')
        self.assertNotIn('supersededBy',entry)
        self.assertIs(type(entry['intentRevision']),int)

    def test_comment_supersession_owns_exact_scope_and_issued_intent(self):
        for phase in ('audit','hold'):
            with self.subTest(phase=phase):
                old = dict(phase=phase,status='completed',auditRepo='Org/Repo',auditTarget=900,
                    marker='<!-- ledger -->',intentAt='2026-10-07T10:00:00+00:00',intentRevision=1,
                    verifiedAt='2026-10-07T10:00:01+00:00',expectedBody='old')
                latest = dict(old,intentRevision=2,intentAt='2026-10-07T10:00:02+00:00',expectedBody='final')
                pending = dict(phase=phase,status='pending',auditRepo='org/repo',auditTarget=900,marker='<!-- ledger -->')
                target = dict(repo='org/repo',pr=12,root=str(self.owner),steps={'old':old,'pending':pending})
                later_target = dict(target,pr=13,steps={'final':latest})
                unrelated = []
                for field,value in [('phase','hold' if phase=='audit' else 'audit'),('auditRepo','org/other'),
                                    ('auditTarget',901),('marker','<!-- other -->')]:
                    entry = dict(old);entry[field]=value
                    unrelated.append(entry)
                target['steps'].update({str(i):entry for i,entry in enumerate(unrelated)})
                state = {'prs':[target,later_target]}
                budget.supersede_verified_comment(state,later_target,'final')
                self.assertEqual(old['supersededBy'],{'repo':'org/repo','pr':13,'step':'final'})
                self.assertNotIn('supersededBy',pending)
                for entry in unrelated:
                    self.assertNotIn('supersededBy',entry)
                    entry['supersededBy'] = dict(old['supersededBy'])
                    with self.assertRaises(budget.Stop):
                        budget.verify(state,target,entry)
                endpoints = []
                def read(endpoint):
                    endpoints.append(endpoint)
                    return [{'id':1,'body':'final'}]
                with patch.object(budget,'comments_read',side_effect=read):
                    self.assertTrue(budget.verify(state,target,old))
                self.assertEqual(endpoints,['repos/Org/Repo/issues/900/comments?per_page=100'])

    def test_comment_supersession_legacy_reference_and_cycles_fail_closed(self):
        old = dict(phase='audit',status='completed',auditTarget=900,marker='<!-- ledger -->',
            intentAt='2026-10-07T10:00:00+00:00',verifiedAt='2026-10-07T10:00:01+00:00',expectedBody='old')
        latest = dict(old,intentAt='2026-10-07T10:00:02+00:00',expectedBody='final')
        target = dict(repo='org/repo',pr=12,root=str(self.owner),steps={'old':old,'final':latest})
        state = {'prs':[target]};old['supersededBy']='final'
        with patch.object(budget,'comments_read',return_value=[{'id':1,'body':'final'}]):
            self.assertTrue(budget.verify(state,target,old))
        latest['supersededBy']='old'
        with self.assertRaises(budget.Stop):
            budget.verify(state,target,old)
        latest.pop('supersededBy');latest.pop('intentAt')
        with self.assertRaises(budget.Stop):
            budget.verify(state,target,old)

    def test_comment_intent_chronology_rejects_invalid_ties_and_mixed_cycles(self):
        base = dict(intentAt='2026-10-07T10:00:01+00:00')
        for value in (True,0,'2'):
            with self.subTest(revision=value),self.assertRaises(budget.Stop):
                budget.comment_order(dict(base,intentRevision=value),base)
        for value in ('invalid',None):
            with self.subTest(timestamp=value),self.assertRaises(budget.Stop):
                budget.comment_order(dict(intentAt=value),base)
        with self.assertRaises(budget.Stop):
            budget.ordered_comment_group([(None,'a',dict(base)),(None,'b',dict(base))])
        # Revision says A > C, while legacy wall time says C > B > A: no safe total order.
        entries = [dict(intentAt='2026-10-07T10:00:00+00:00',intentRevision=3),
                   dict(intentAt='2026-10-07T10:00:01+00:00'),
                   dict(intentAt='2026-10-07T10:00:02+00:00',intentRevision=1)]
        with self.assertRaises(budget.Stop):
            budget.ordered_comment_group([(None,str(i),e) for i,e in enumerate(entries)])

    def test_dispatch_identity_drift_interrupts_before_child_launch(self):
        from contextlib import redirect_stderr, redirect_stdout
        import io
        self.begin()
        original_before = budget.before
        with patch.object(budget,'checkout_repo',return_value='org/repo') as identity:
            def drift_after_intent(args):
                result = original_before(args)
                identity.return_value = 'org/foreign'
                return result
            with patch.object(budget,'before',side_effect=drift_after_intent), \
                 patch.object(budget,'proof_root',return_value=str(self.owner)), \
                 patch.object(budget.subprocess,'Popen') as launch, \
                 patch.object(sys,'argv',['workflow-merge-budget.py','run-step','--session',self.args.session,
                    '--repo','org/repo','--pr','12','--phase','merge_api','--step','merge_api','--',
                    'gh','pr','merge','12']), redirect_stderr(io.StringIO()), redirect_stdout(io.StringIO()):
                self.assertEqual(budget.main(),2)
                launch.assert_not_called()
        state = budget.snapshot(self.args.session)
        self.assertEqual(state['outcome'],'Interrupted')
        self.assertEqual(state['prs'][0]['steps']['merge_api']['status'],'uncertain')
        self.assertIn('checkout differs',state['reason'])

    def test_audit_lookup_normalizes_older_frozen_repository_case(self):
        from contextlib import redirect_stdout
        import io
        manifest = json.loads(self.manifest.read_text())
        manifest['prs'][0].pop('phases')
        manifest['prs'][0]['steps'] = [{'id':'audit','phase':'audit','auditRepo':'Org/Repo',
            'auditTarget':12,'marker':'<!-- fixture -->'}]
        self.manifest.write_text(json.dumps(manifest))
        self.begin()
        with budget.journal(self.args.session) as state:
            state['prs'][0]['steps']['audit']['auditRepo'] = 'Org/Repo'
        output = io.StringIO()
        with patch.object(sys,'argv',['workflow-merge-budget.py','check','--session',self.args.session,
            '--repo','ORG/REPO','--pr','12','--phase','audit','--step','audit','--audit-repo','oRG/rEPO']), redirect_stdout(output):
            self.assertEqual(budget.main(),0)
        self.assertEqual(json.loads(output.getvalue())['stepId'],'audit')

    def _signal_main_case(self, queued=False, terminal=False):
        from contextlib import redirect_stderr, redirect_stdout
        import io
        import signal
        from types import SimpleNamespace
        expected = self.owner/'1890-cancelled-body.txt'
        expected.write_text('<!-- fixture -->')
        phase = 'audit' if terminal else 'merge_api'
        if terminal:
            manifest = json.loads(self.manifest.read_text())
            manifest['prs'][0].pop('phases')
            manifest['prs'][0]['steps'] = [{'id':'audit','phase':'audit','auditRepo':'org/repo',
                'auditTarget':12,'marker':'<!-- fixture -->'}]
            self.manifest.write_text(json.dumps(manifest))
        self.begin()
        original_verify, original_publish = budget.verify, budget.publish
        injected = False
        def wait():
            self.live.update(state='OPEN' if queued else 'MERGED',isInMergeQueue=queued)
            return 0
        def verify(state,target,entry):
            completed = True if terminal else original_verify(state,target,entry)
            if not terminal:
                os.kill(os.getpid(),signal.SIGTERM)
                os.kill(os.getpid(),signal.SIGINT)
            return completed
        def publish(path,state):
            nonlocal injected
            original_publish(path,state)
            if terminal and state['outcome']=='Completed' and not injected:
                injected = True
                os.kill(os.getpid(),signal.SIGINT)
        argv = ['workflow-merge-budget.py','run-step','--session',self.args.session,'--repo','org/repo',
            '--pr','12','--phase',phase,'--step',phase]
        if terminal:
            argv += ['--expected-file',str(expected)]
        argv += ['--','true']
        with patch.object(sys,'argv',argv), patch.object(budget,'proof_root',return_value=str(self.owner)), \
             patch.object(budget,'verify',side_effect=verify), patch.object(budget,'publish',side_effect=publish), \
             patch.object(budget.os,'write',return_value=1), patch.object(budget,'group_alive',return_value=False), \
             patch.object(budget.subprocess,'Popen',return_value=SimpleNamespace(pid=99999999,wait=wait)), \
             redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            self.assertEqual(budget.main(),2)
        state = budget.snapshot(self.args.session)
        self.assertEqual(state['outcome'],'Interrupted')
        self.assertIsNotNone(state.get('cancellation'))
        self.assertEqual(state['prs'][0]['steps'][phase]['status'],'pending' if queued else 'completed')
        if queued:
            self.assertTrue(state['prs'][0]['steps'][phase]['submission'])
        if terminal:
            self.assertTrue(injected)

    def test_signal_during_merge_readback_is_sticky_with_verified_effect(self):
        self._signal_main_case()

    def test_signal_during_queue_readback_remains_interrupted(self):
        self._signal_main_case(queued=True)

    def test_signal_during_terminal_journal_publication_does_not_deadlock(self):
        self._signal_main_case(terminal=True)

    def test_projection_derivation_and_equality(self):
        self.sample['remaining'] = 1125  # raw 25+50, margin50, reserve1000
        result = self.begin()
        self.assertEqual(result['estimate']['projectedCost'], 125)
        self.assertEqual(result['outcome'], 'Admitted')
        budget.before(self.args)
        self.assertTrue(budget.snapshot(self.args.session)['started'])

    def test_one_below_defers_before_intent(self):
        self.sample['remaining'] = 1124
        result = self.begin()
        self.assertEqual(result['outcome'], 'Deferred')
        with self.assertRaises(budget.Stop):
            budget.before(self.args)
        state = budget.snapshot(self.args.session)
        self.assertFalse(state['started'])
        self.assertEqual(state['prs'][0]['steps']['merge_api']['status'], 'pending')

    def test_provisional_balance_is_refreshed(self):
        self.begin()
        self.sample['remaining'] = 1124
        with self.assertRaises(budget.Stop):
            budget.before(self.args)
        self.assertEqual(budget.snapshot(self.args.session)['outcome'], 'Deferred')

    def test_malformed_quota_no_core_substitution(self):
        for value in [True, '5000', None, -1, 5001]:
            with self.subTest(value=value):
                self.sample['remaining'] = value
                with self.assertRaises(budget.Stop):
                    budget.budget()

    def test_quota_field_types_and_window_fail_closed(self):
        original = dict(self.sample)
        for field,value in [('remaining',False),('remaining','5000'),('reset',True),('reset','1'),
                            ('reset',int(time.time())-1),('limit',0),('limit',True),('limit','5000')]:
            with self.subTest(field=field,value=value):
                self.sample.clear(); self.sample.update(original); self.sample[field] = value
                with self.assertRaises(budget.Stop):
                    budget.budget()
        self.sample.clear(); self.sample.update(original)
        for absent in ('remaining','reset','limit'):
            self.sample.clear(); self.sample.update(original); del self.sample[absent]
            with self.assertRaises(budget.Stop):
                budget.budget()

    def test_unknown_step_rejected_without_admission(self):
        self.begin()
        self.args.step = 'invented'
        with self.assertRaises(budget.Stop):
            budget.before(self.args)
        self.assertFalse(budget.snapshot(self.args.session)['started'])

    def test_waiting_stops_next_action(self):
        self.begin()
        budget.before(self.args)
        self.live['isInMergeQueue'] = True
        with self.assertRaises(budget.Stop):
            budget.after(self.args)
        state = budget.snapshot(self.args.session)
        self.assertEqual(state['outcome'], 'Waiting')
        with self.assertRaises(budget.Stop):
            budget.before(self.args)
        self.live['isInMergeQueue'] = False
        self.live['state'] = 'MERGED'
        result = budget.resume(self.args)
        self.assertEqual(result['prs'][0]['verifiedState'], 'merged')
        self.assertEqual(result['prs'][0]['steps']['merge_api']['status'], 'completed')

    def test_outage_preserves_intent_and_offline_report(self):
        self.begin()
        budget.before(self.args)
        with patch.object(budget, 'pr_read', side_effect=budget.Stop('offline')):
            with self.assertRaises(budget.Stop):
                budget.after(self.args)
        state = budget.snapshot(self.args.session)
        self.assertEqual(state['outcome'], 'Interrupted')
        self.assertEqual(state['prs'][0]['steps']['merge_api']['status'], 'uncertain')
        with patch.object(budget, 'budget', side_effect=budget.Stop('offline')):
            self.assertEqual(budget.summary(state, True)['outcome'], 'Interrupted')
            self.assertIsNone(budget.summary(state, True)['observedSpend'])
        self.live['state'] = 'MERGED'
        result = budget.resume(self.args)
        self.assertEqual(result['prs'][0]['steps']['merge_api']['status'], 'completed')
        with self.assertRaises(budget.Stop):
            budget.before(self.args)

    def test_surviving_child_blocks_recovery(self):
        self.begin()
        with budget.journal(self.args.session) as state:
            state['active'] = {'pid': 99999999, 'childPid': os.getpid(), 'token': 'claim'}
        with self.assertRaises(budget.Stop):
            budget.resume(self.args)

    def test_remote_reads_do_not_hold_journal_lock(self):
        self.begin()
        def read(p):
            # A second exclusive lock can be acquired while this live read runs.
            with budget.journal(self.args.session, write=False):
                pass
            return dict(self.live)
        with patch.object(budget, 'pr_read', read):
            budget.before(self.args)
            self.live['state'] = 'MERGED'
            budget.after(self.args)

    def test_partial_response_and_duplicate_keys(self):
        with self.assertRaises(budget.Stop):
            budget.decode('{"remaining":1,"remaining":2}')
        with patch.object(budget.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '{"errors":[{"message":"quota"}],"data":{}}', '')):
            with self.assertRaises(budget.Stop):
                # bypass setUp gh mock to exercise raw evidence parser
                RAW_GH('api', 'graphql')

    def test_final_window_comparability(self):
        state = self.begin()
        self.sample['remaining'] -= 30
        self.assertEqual(budget.summary(state, True)['observedSpend'], 30)
        self.sample['reset'] += 1
        self.assertIsNone(budget.summary(state, True)['observedSpend'])
        self.assertEqual(budget.summary(state, True)['spendReason'], 'quota window reset')

    def test_reserve_resolution(self):
        self.assertEqual(RAW_RESERVE(self.owner, None), 1000)
        shared = self.owner / '.ai-dev-workflow.yaml'
        local = self.owner / '.ai-dev-workflow.local.yaml'
        shared.write_text('merge_budget:\n  graphql_reserve: 123\n')
        local.write_text('merge_budget:\n  graphql_reserve: 456\n')
        self.assertEqual(RAW_RESERVE(self.owner, None), 456)
        self.assertEqual(RAW_RESERVE(self.owner, '789'), 789)
        for literal in ['null', '""', '-1', '+1', '1.5', 'true', '[]', '{}']:
            with self.subTest(literal=literal):
                local.write_text('merge_budget:\n  graphql_reserve: ' + literal + '\n')
                with self.assertRaises(budget.Stop):
                    RAW_RESERVE(self.owner, None)
        local.write_text('merge_budget:\n  graphql_reserve: null\n')
        self.assertEqual(RAW_RESERVE(self.owner, '0'), 0)

    def test_repeated_issue_executions_and_full_batch_boundary(self):
        declaration = json.loads(self.manifest.read_text())
        declaration['prs'].append(dict(declaration['prs'][0], pr=13))
        self.manifest.write_text(json.dumps(declaration))
        issue = {'id': '99', 'provider': 'github_projects', 'repo': 'org/repo',
                 'status': 'Merged', 'tracker': True, 'close': True, 'closeComment': 'Closed by PR #12.'}
        with patch.object(budget, 'inspect', return_value={'issues': [issue]}):
            self.sample['remaining'] = 2695
            value = self.begin()
            self.assertEqual(value['estimate']['rawCost'], 1130)
            self.assertEqual(value['estimate']['projectedCost'], 1695)
            self.assertEqual(value['outcome'], 'Admitted')
            self.args.pr = 13
            with self.assertRaisesRegex(budget.Stop, 'preceding selected'):
                budget.before(self.args)
            self.args.pr = 12
            self.sample['remaining'] = 2694
            with self.assertRaises(budget.Stop):
                budget.before(self.args)
            self.assertFalse(budget.snapshot(self.args.session)['started'])

    def test_partial_projection_retains_full_selected_set(self):
        declaration = json.loads(self.manifest.read_text())
        declaration['prs'][0]['head'] = 'bad'
        declaration['prs'].append(dict(declaration['prs'][0], pr=13, head='b'*40))
        self.manifest.write_text(json.dumps(declaration))
        value = self.begin()
        self.assertEqual(value['outcome'], 'Deferred')
        self.assertEqual(len(value['selectedSet']), 2)
        self.assertFalse(value['projectionComplete'])

    def test_manifest_identity(self):
        original = json.loads(self.manifest.read_text())
        for identity in ['#12', '12x', 0, True]:
            declaration = json.loads(json.dumps(original))
            declaration['prs'][0]['pr'] = identity
            self.manifest.write_text(json.dumps(declaration))
            self.assertEqual(self.begin()['outcome'], 'Deferred')
        declaration = json.loads(json.dumps(original))
        declaration['prs'].append(declaration['prs'][0])
        self.manifest.write_text(json.dumps(declaration))
        self.assertEqual(self.begin()['outcome'], 'Deferred')
        self.manifest.write_text(json.dumps(original))
        with patch.object(budget, 'checkout_repo', return_value='foreign/repo'):
            self.assertEqual(self.begin()['outcome'], 'Deferred')

    def test_live_pr_structured_contract(self):
        target = {'repo': 'org/repo', 'pr': 12, 'base': 'develop', 'head': 'a'*40}
        response = {'data': {'repository': {'pullRequest': dict(self.live)}}}
        with patch.object(budget, 'gh', return_value=response):
            self.assertEqual(RAW_PR_READ(target)['state'], 'OPEN')
            response['data']['repository']['pullRequest']['headRefOid'] = 'b'*40
            with self.assertRaises(budget.Stop):
                RAW_PR_READ(target)
            response['data']['repository']['pullRequest']['state'] = 'MERGED'
            self.assertEqual(RAW_PR_READ(target)['state'], 'MERGED')
        with patch.object(budget, 'gh', return_value={'data': {'repository': None}}):
            with self.assertRaises(budget.Stop):
                RAW_PR_READ(target)

    def test_completion_identity_and_redacted_report(self):
        self.begin()
        budget.before(self.args)
        self.live['state'] = 'MERGED'
        self.args.phase = 'cleanup'
        with self.assertRaises(budget.Stop):
            budget.after(self.args)
        self.args.phase = 'merge_api'
        self.args.execution_token = 'foreign-executor'
        with self.assertRaises(budget.Stop):
            budget.after(self.args)
        report = budget.summary(budget.snapshot(self.args.session))
        self.assertNotIn('token', report['prs'][0]['steps']['merge_api'])

    def test_live_verification_oserror_is_durably_interrupted(self):
        self.begin()
        budget.before(self.args)
        with patch.object(budget,'pr_read',side_effect=FileNotFoundError('fixture executable missing')):
            with self.assertRaises(budget.Stop):
                budget.after(self.args)
        state = budget.snapshot(self.args.session)
        self.assertEqual(state['outcome'],'Interrupted')
        self.assertEqual(state['prs'][0]['steps']['merge_api']['status'],'uncertain')
        self.assertEqual(state['prs'][0]['steps']['merge_api']['exitCode'],0)

    def test_unavailable_final_sample_and_admission_preserve_known_facts(self):
        self.begin()
        state = budget.snapshot(self.args.session)
        state['outcome'] = 'Completed'; state['prs'][0]['verifiedState'] = 'merged'
        with patch.object(budget,'budget',side_effect=FileNotFoundError('fixture gh unavailable')):
            report = budget.summary(state,True)
            self.assertEqual(report['outcome'],'Completed')
            self.assertEqual(report['prs'][0]['verifiedState'],'merged')
            self.assertIsNone(report['observedSpend'])
            self.assertFalse(budget.admission(state))
            self.assertEqual(state['outcome'],'Deferred')
            self.assertEqual(state['prs'][0]['verifiedState'],'merged')
            result = budget.resume(self.args)
            self.assertEqual(result['outcome'],'Deferred')

    def test_malformed_issue_and_comment_pages_are_unknown(self):
        issue = {'repo':'org/repo','id':'1'}
        for value in [{'number':True,'state':'CLOSED'}, {'number':1,'state':'UNKNOWN'}, {'number':1}]:
            with patch.object(budget,'gh',return_value=value):
                with self.assertRaises(budget.Stop) as raised:
                    budget.issue_read(issue)
                self.assertFalse((raised.exception.evidence or {}).get('knownOutstanding'))
        for value in [{}, [None], [[{}]], [[{'body':None}]], [[{'body':True}]]]:
            with patch.object(budget,'gh',return_value=value):
                with self.assertRaises(budget.Stop) as raised:
                    budget.comments_read('fixture/comments')
                self.assertFalse((raised.exception.evidence or {}).get('knownOutstanding'))
        with patch.object(budget,'gh',return_value=[]):
            self.assertEqual(budget.comments_read('fixture/comments'),[])

    def test_empty_best_effort_tracker_read_is_unknown(self):
        self.begin()
        state = budget.snapshot(self.args.session)
        issue = {'id':'99','repo':'org/repo','provider':'github_projects','status':'Merged'}
        for result in ['\n-1\n9', 'Unrecognized\n-1\n9', 'Plan Ready\n6\n-1']:
            with patch.object(budget,'proof_root',return_value=str(self.owner)), patch.object(budget,'call',return_value=result):
                with self.assertRaises(budget.Stop):
                    budget.tracker_read(state,issue)
        with patch.object(budget,'proof_root',return_value=str(self.owner)), patch.object(budget,'call',return_value='Plan Ready\n6\n9'):
            self.assertFalse(budget.tracker_read(state,issue))

    def test_closed_queue_is_unknown_and_merged_queue_remains_merged(self):
        self.begin()
        budget.before(self.args)
        self.live.update(state='CLOSED',isInMergeQueue=True)
        with self.assertRaises(budget.Stop):
            budget.after(self.args)
        self.assertEqual(budget.snapshot(self.args.session)['outcome'],'Interrupted')
        result = budget.resume(self.args)
        self.assertEqual(result['outcome'],'Deferred')
        self.live['state'] = 'MERGED'
        result = budget.resume(self.args)
        self.assertEqual(result['outcome'],'Admitted')
        self.assertEqual(result['prs'][0]['verifiedState'],'merged')

    def test_noop_closure_requires_independent_closed_state_before_intent(self):
        issue = {'id':'99','provider':'none','repo':'org/repo','status':'Merged','tracker':False,
                 'close':True,'closeComment':'Closed by PR #12.'}
        patcher = patch.object(budget,'inspect',return_value={'issues':[issue]})
        patcher.start(); self.addCleanup(patcher.stop)
        self.begin(); self.live['state'] = 'MERGED'
        self.args.phase,self.args.step,self.args.issue,self.args.status = 'issue_close','issue_close:99','99','Merged'
        with patch.object(budget,'issue_read',return_value={'number':99,'state':'OPEN'}), patch.object(budget,'comments_read',return_value=[]):
            budget.before(self.args)
        self.args.no_op = True
        with patch.object(budget,'issue_read',return_value={'number':99,'state':'CLOSED'}), patch.object(budget,'comments_read',return_value=[]):
            with self.assertRaises(budget.Stop):
                budget.after(self.args)
        state = budget.snapshot(self.args.session)
        self.assertEqual(state['outcome'],'Interrupted')
        self.assertFalse(state['prs'][0]['steps']['issue_close:99']['verifiedNoOp'])
        self.assertEqual(state['prs'][0]['steps']['issue_close:99']['issueStateBefore'],'OPEN')

    def test_timestamp_contract(self):
        from datetime import timedelta, timezone, datetime
        earlier = datetime.now(timezone.utc) - timedelta(seconds=2)
        observed = earlier + timedelta(seconds=1)
        self.assertTrue(budget.newer(observed.isoformat(), earlier.isoformat()))
        for value in ['zzz', '2026-01-01', '2030-01-01T00:00:00+00:00', True, None]:
            with self.subTest(value=value):
                self.assertFalse(budget.newer(value, earlier.isoformat()))

    def test_nested_completion_retains_outer_claim_and_competitor_refused(self):
        issue = {'id':'99','provider':'github_projects','repo':'org/repo','status':'Merged','tracker':True,'close':False}
        patcher = patch.object(budget,'inspect',return_value={'issues':[issue]})
        patcher.start(); self.addCleanup(patcher.stop)
        self.begin()
        intent = budget.before(self.args)
        self.live['state'] = 'MERGED'
        self.args.phase,self.args.step,self.args.issue,self.args.status = 'tracker','tracker:99:pre','99','Merged'
        with patch.dict(os.environ,{'WORKFLOW_MERGE_BUDGET_TOKEN':intent['token']}):
            budget.before(self.args)
            with patch.object(budget,'tracker_read',return_value=True):
                budget.after(self.args)
        self.assertIsNotNone(budget.snapshot(self.args.session)['active'])
        self.args.phase,self.args.step,self.args.issue,self.args.status = 'merge_verify','merge_verify',None,None
        with patch.dict(os.environ,{'WORKFLOW_MERGE_BUDGET_TOKEN':'1890-foreign'}):
            with self.assertRaises(budget.Stop):
                budget.before(self.args)
        self.args.phase,self.args.step = 'merge_api','merge_api'
        self.args.execution_token = intent['token']
        budget.after(self.args)
        with self.assertRaises(budget.Stop):
            budget.after(self.args)  # duplicate completion has no in-flight intent

    def test_atomic_failure_and_storage_refusal(self):
        self.begin()
        path = Path(self.args.session)
        original = path.read_bytes()
        with patch.object(budget.os,'replace',side_effect=OSError('fixture publish failed')):
            with self.assertRaises(OSError):
                budget.publish(path,{'torn':True})
        self.assertEqual(path.read_bytes(),original)
        with patch.object(budget.os,'fsync',side_effect=OSError('fixture fsync failed')):
            with self.assertRaises(OSError):
                budget.publish(path,{'torn':True})
        self.assertEqual(path.read_bytes(),original)
        for bad in [path.parent/'..'/'state.json', self.owner/'foreign.json']:
            with self.assertRaises(budget.Stop):
                budget.snapshot(bad)
        link = self.owner/'1890-link'
        link.symlink_to(path.parent)
        with self.assertRaises(budget.Stop):
            budget.snapshot(link/'state.json')
        with budget.journal(path) as state:
            state['ownerCommonDir'] = str(self.owner/'foreign-common')
        with self.assertRaises(budget.Stop):
            budget.snapshot(path)

    def test_linear_recovery_generation_and_single_continuation(self):
        issue = {'id':'ENG-12','provider':'linear','repo':'org/repo','status':'Merged','tracker':True,'close':False}
        with patch.object(budget,'inspect',return_value={'issues':[issue]}):
            self.begin()
        patcher = patch.object(budget,'inspect',return_value={'issues':[issue]})
        patcher.start(); self.addCleanup(patcher.stop)
        self.live['state'] = 'MERGED'
        self.args.phase,self.args.step,self.args.issue,self.args.status = 'tracker','tracker:ENG-12:pre','ENG-12','Merged'
        budget.before(self.args)
        with self.assertRaises(budget.Stop):
            budget.after(self.args)
        result = budget.resume(self.args)
        self.assertEqual(result['outcome'],'Deferred')
        first = budget.snapshot(self.args.session)
        self.args.evidence = str(self.owner/'1890-provider-proof.json')
        proof = {'provider':'linear','repo':'org/repo','issue':'ENG-12','statusName':'Merged',
                 'statusId':'merged','mutationRequestId':'1890-mutation','readRequestId':'1890-read','observedAt':budget.now()}
        Path(self.args.evidence).write_text(json.dumps(proof))
        budget.provider(self.args)
        result = budget.resume(self.args)
        self.assertEqual(result['outcome'],'Admitted')
        continued = budget.snapshot(self.args.session)
        self.assertEqual(continued['recoveryGeneration'],first['recoveryGeneration'])
        self.assertFalse(continued['recoveryAwaitingProvider'])
        result = budget.resume(self.args)
        self.assertEqual(result['outcome'],'Deferred')
        self.assertGreater(budget.snapshot(self.args.session)['recoveryGeneration'],continued['recoveryGeneration'])
        with self.assertRaises(budget.Stop):
            budget.provider(self.args)  # prior read timestamp cannot authorize a later recovery

    def test_provider_proof_cannot_release_surviving_mutating_child(self):
        issue = {'id':'ENG-12','provider':'linear','repo':'org/repo','status':'Merged','tracker':True,'close':False}
        patcher = patch.object(budget,'inspect',return_value={'issues':[issue]})
        patcher.start(); self.addCleanup(patcher.stop)
        self.begin(); self.live['state'] = 'MERGED'
        self.args.phase,self.args.step,self.args.issue,self.args.status = 'tracker','tracker:ENG-12:pre','ENG-12','Merged'
        intent = budget.before(self.args)
        with budget.journal(self.args.session) as state:
            state['active']['children'] = [{'pid':os.getpid(),'group':os.getpgrp(),'step':self.args.step,'repo':'org/repo','pr':12}]
        self.args.evidence = str(self.owner/'1890-provider-live-proof.json')
        Path(self.args.evidence).write_text(json.dumps({'provider':'linear','repo':'org/repo','issue':'ENG-12',
            'statusName':'Merged','statusId':'merged','mutationRequestId':'1890-mutation','readRequestId':'1890-read','observedAt':budget.now()}))
        with self.assertRaises(budget.Stop):
            budget.provider(self.args)
        state = budget.snapshot(self.args.session)
        self.assertEqual(state['active']['token'],intent['token'])
        self.assertEqual(state['prs'][0]['steps'][self.args.step]['status'],'in_flight')

    def test_python_query_literal_uses_existing_linter(self):
        source = Path(__file__).resolve().parents[1]/'workflow-merge-budget.py'
        import ast
        module = ast.parse(source.read_text())
        literal = next(node.value.value for node in module.body if isinstance(node,ast.Assign)
                       and any(isinstance(target,ast.Name) and target.id == 'PR_QUERY' for target in node.targets))
        query = self.owner/'1890-query-literal.sh'
        query.write_text("gh api graphql -f query='"+literal+"'\n")
        linter = source.parents[1]/'lint'/'lint-graphql-query-literals.py'
        result = subprocess.run([sys.executable,str(linter),str(query)],text=True,capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_schema_and_private_storage(self):
        self.begin()
        path = Path(self.args.session)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        original = json.loads(path.read_text())
        for version in [999, True, '1']:
            altered = dict(original,schemaVersion=version); path.write_text(json.dumps(altered))
            with self.assertRaises(budget.Stop):
                budget.snapshot(path)
        path.write_text('[]')
        with self.assertRaises(budget.Stop):
            budget.snapshot(path)


class Composed(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='1890-composed-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.source = Path(__file__).resolve().parents[1]
        self.scripts = self.repo / 'scripts/development-workflow'
        self.scripts.mkdir(parents=True)
        for name in ['workflow-merge-budget.py', 'workflow-lib.sh', 'workflow-config-resolver.py',
                     'workflow-project-reader.py', 'post-merge-cleanup.sh', 'batch-merge.sh', 'closing-keyword-lib.sh']:
            shutil.copyfile(self.source / name, self.scripts / name)
        self.command(['git', 'init', '-q', '-b', 'develop'])
        self.command(['git', 'config', 'user.name', 'Fixture'])
        self.command(['git', 'config', 'user.email', 'fixture@example.invalid'])
        (self.repo / '.ai-dev-workflow.yaml').write_text('issue_tracker:\n  provider: none\n')
        (self.repo / 'base.txt').write_text('base\n')
        self.command(['git', 'add', 'base.txt', '.ai-dev-workflow.yaml'])
        self.command(['git', 'commit', '-qm', 'fixture base'])
        self.origin = self.root / 'origin.git'
        subprocess.run(['git', 'init', '-q', '--bare', '-b', 'develop', str(self.origin)], check=True)
        self.command(['git', 'remote', 'add', 'origin', str(self.origin)])
        self.command(['git', 'push', '-q', 'origin', 'develop'])
        self.command(['git', 'checkout', '-qb', 'feature/12-item'])
        (self.repo / 'feature.txt').write_text('feature\n')
        self.command(['git', 'add', 'feature.txt'])
        self.command(['git', 'commit', '-qm', 'fixture feature'])
        self.head = self.command(['git', 'rev-parse', 'HEAD']).stdout.strip()
        self.command(['git', 'push', '-q', 'origin', 'feature/12-item'])
        self.command(['git', 'push', '-q', 'origin', 'feature/12-item:refs/pull/12/head'])
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        shutil.copyfile(self.source / 'tests/fixtures/workflow-merge-budget/fake-gh.py', self.bin/'gh')
        (self.bin/'gh').chmod(0o700)
        self.fixture = self.root / '1890-provider.json'
        self.data = {'repo': 'org/repo', 'prs': {'12': {'number': 12, 'state': 'OPEN',
            'headRefName': 'feature/12-item', 'headRefOid': self.head, 'baseRefName': 'develop',
            'isInMergeQueue': False, 'autoMergeRequest': None}},
            'quota': {'remaining': 5000, 'limit': 5000, 'reset': int(time.time())+3600}}
        self.fixture.write_text(json.dumps(self.data))
        self.env = dict(os.environ, PATH=str(self.bin)+os.pathsep+os.environ['PATH'], MERGE_BUDGET_FIXTURE=str(self.fixture),
                        WORKFLOW_GH_ITEM_LIST_CACHE_DIR=str(self.root/'1890-cache'))
        for name in ['WORKFLOW_MERGE_BUDGET_SESSION', 'WORKFLOW_MERGE_BUDGET_TOKEN', 'WORKFLOW_MERGE_BUDGET_PR',
                     'WORKFLOW_MERGE_BUDGET_REPO', 'GH_REPO', 'POST_MERGE_CLEANUP_CALLER_WORKTREES']:
            self.env.pop(name, None)

    def tearDown(self):
        directory = Path(os.environ.get('WORKFLOW_MERGE_BUDGET_TEST_EVIDENCE_DIR',str(self.root)))
        if not directory.is_dir():
            raise AssertionError('caller-owned evidence directory must exist')
        destination = directory/'1890-composed-evidence.json'
        records = json.loads(destination.read_text()) if destination.exists() else {}
        record_id = self.id()+('.'+self.evidence_case if hasattr(self,'evidence_case') else '')
        records[record_id] = {'events':json.loads(self.fixture.read_text()).get('events',[]),
                             'sessions':[]}
        if hasattr(self,'cancellation_evidence'):
            records[record_id]['cancellationEvidence'] = self.cancellation_evidence
        for journal in self.repo.glob('.git/workflow-merge-budget/*/state.json'):
            state = json.loads(journal.read_text())
            records[record_id]['sessions'].append({'outcome':state['outcome'],'reason':state['reason'],
                'projectionComplete':state['projectionComplete'],'estimate':state.get('estimate'),
                'prs':[{'repo':target['repo'],'pr':target['pr'],'verifiedState':target['verifiedState'],
                        'steps':{key:{field:entry.get(field) for field in ('phase','status','exitCode','commit','verifiedRemoteCommit')}
                                 for key,entry in target['steps'].items()}} for target in state['prs']]})
        destination.write_text(json.dumps(records,indent=2)+'\n')

    def command(self, argv, env=None):
        result = subprocess.run(argv, cwd=self.repo, env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def helper(self, *argv, success=True):
        result = subprocess.run([sys.executable, str(self.scripts/'workflow-merge-budget.py'), *map(str,argv)],
                                cwd=self.repo, env=self.env, text=True, capture_output=True)
        if success:
            self.assertEqual(result.returncode, 0, result.stderr)
        return result

    def begin(self, skipped=True):
        path = self.root / '1890-manifest.json'
        path.write_text(json.dumps({'ownerRoot': str(self.repo), 'prs': [{'repo': 'org/repo', 'pr': 12,
            'head': self.head, 'base': 'develop', 'root': str(self.repo),
            'phases': ['local_merge','base_push','merge_api','cleanup'],
            'policySkipped': ['remote_delete','local_cleanup'] if skipped else []}]}))
        result = self.helper('begin','--input',path)
        return json.loads(result.stdout)['session']

    def test_actual_linear_cleanup_emits_native_bridge_without_github_issue(self):
        for index,(branch,status) in enumerate([('feature/ENG-12-item','Merged'),
                ('spec/ENG-12-item','Spec Ready'),('implementation-plan/ENG-12-item','Plan Ready')]):
            with self.subTest(branch=branch,status=status):
                if index:
                    self.tearDown();self.doCleanups();self.setUp()
                self.command(['git','branch','-m',branch]);self.command(['git','push','-q','origin',branch])
                (self.repo/'.ai-dev-workflow.yaml').write_text('issue_tracker:\n  provider: linear\n')
                self.data['prs']['12'].update(state='MERGED',headRefName=branch)
                self.data['missingGithubIssue']=True;self.fixture.write_text(json.dumps(self.data))
                manifest=self.root/'1890-linear-cleanup.json'
                manifest.write_text(json.dumps({'ownerRoot':str(self.repo),'prs':[dict(repo='org/repo',pr=12,
                    head=self.head,base='develop',root=str(self.repo),phases=['cleanup'],
                    policySkipped=['remote_delete','local_cleanup'])]}))
                session=json.loads(self.helper('begin','--input',manifest).stdout)['session']
                result=subprocess.run(['bash',str(self.scripts/'post-merge-cleanup.sh'),'--merge-session',session,
                    '--repo-root',str(self.repo),'--base','develop','--pr','12',branch],cwd=self.repo,
                    env=self.env,text=True,capture_output=True)
                self.assertNotEqual(result.returncode,0)
                self.assertIn('TRACKER_ACTION_REQUIRED=set_status issue=ENG-12 target_status='+ ("'"+status+"'" if ' ' in status else status),result.stdout)
                state=json.loads(Path(session).read_text())
                self.assertEqual(state['outcome'],'Interrupted')
                self.assertEqual(state['prs'][0]['issues'][0]['id'],'ENG-12')
                step=state['prs'][0]['steps']['tracker:ENG-12:pre']
                self.assertIn('intentAt',step);self.assertEqual(step['status'],'uncertain')
                events=json.loads(self.fixture.read_text())['events']
                self.assertNotIn(['issue','view'],events);self.assertNotIn(['issue','close'],events)
                self.helper('resume','--session',session,success=False)
                proof=self.root/'1890-native-linear-proof.json'
                proof.write_text(json.dumps(dict(provider='linear',repo='org/repo',issue='ENG-12',statusName=status,
                    statusId='linear-merged',mutationRequestId='1890-bridge-mutation',readRequestId='1890-bridge-read',
                    observedAt=step['intentAt'])))
                rejected=self.helper('record-provider-result','--session',session,'--repo','org/repo','--pr','12',
                    '--phase','tracker','--step','tracker:ENG-12:pre','--issue','ENG-12','--status',status,'--evidence',proof,success=False)
                self.assertNotEqual(rejected.returncode,0)
                self.assertNotEqual(json.loads(Path(session).read_text())['outcome'],'Completed')
                evidence=json.loads(proof.read_text());evidence['observedAt']=budget.now()
                proof.write_text(json.dumps(evidence))
                self.helper('record-provider-result','--session',session,'--repo','org/repo','--pr','12',
                    '--phase','tracker','--step','tracker:ENG-12:pre','--issue','ENG-12','--status',status,'--evidence',proof)
                recovered=json.loads(self.helper('resume','--session',session).stdout)
                self.assertEqual(recovered['outcome'],'Admitted')
                finished=self.command(['bash',str(self.scripts/'post-merge-cleanup.sh'),'--merge-session',session,
                    '--repo-root',str(self.repo),'--base','develop','--pr','12',branch],self.env)
                self.assertNotIn('TRACKER_ACTION_REQUIRED=',finished.stdout)
                self.assertEqual(json.loads(self.helper('report','--session',session).stdout)['outcome'],'Completed')
                events=json.loads(self.fixture.read_text())['events']
                self.assertNotIn(['issue','view'],events);self.assertNotIn(['issue','close'],events)
                self.assertEqual(self.command(['git','branch','--show-current']).stdout.strip(),branch)

    def test_actual_merge_cleanup_no_deletion_composition(self):
        session = self.begin()
        result = self.command(['bash',str(self.scripts/'batch-merge.sh'),'--merge-session',session,
                               'merge','--pr','12','--expected-head-sha',self.head], self.env)
        self.assertIn('MERGE_RESULT=clean', result.stdout)
        state = json.loads(self.helper('report','--session',session).stdout)
        self.assertEqual(state['prs'][0]['verifiedState'], 'merged')
        self.assertEqual(state['outcome'], 'Admitted')
        result = self.command(['bash',str(self.scripts/'post-merge-cleanup.sh'),'--merge-session',session,
                               '--repo-root',str(self.repo),'--base','develop','--pr','12','feature/12-item'], self.env)
        self.assertIn('retained by policy', result.stdout)
        state = json.loads(self.helper('report','--session',session,'--final').stdout)
        self.assertEqual(state['outcome'], 'Completed')
        self.assertTrue(self.command(['git','branch','--list','feature/12-item']).stdout.strip())
        self.assertTrue(self.command(['git','ls-remote','--heads','origin','feature/12-item']).stdout.strip())
        events = json.loads(self.fixture.read_text())['events']
        self.assertEqual(events.count(['pr','merge']), 1)

    def test_direct_begin_preserves_linked_cleanup_caller(self):
        (self.scripts/'post-merge-cleanup.sh').chmod(0o700)
        self.command(['git','checkout','-q','develop'])
        self.command(['git','merge','-q','--no-edit','feature/12-item'])
        self.command(['git','push','-q','origin','develop'])
        linked = self.root/'1890-caller-worktree'
        self.command(['git','worktree','add','-q',str(linked),'feature/12-item'])
        self.data['prs']['12']['state'] = 'MERGED'
        self.fixture.write_text(json.dumps(self.data))
        manifest = self.root/'1890-linked-manifest.json'
        manifest.write_text(json.dumps({'ownerRoot':str(self.repo),'prs':[{
            'repo':'org/repo','pr':12,'head':self.head,'base':'develop',
            'root':str(linked),'phases':['cleanup']}]}))
        admitted = subprocess.run([sys.executable,str(self.scripts/'workflow-merge-budget.py'),
            'begin','--input',str(manifest)],cwd=linked,env=self.env,text=True,capture_output=True)
        self.assertEqual(admitted.returncode,0,admitted.stderr)
        session = json.loads(admitted.stdout)['session']
        target = json.loads(Path(session).read_text())['prs'][0]
        self.assertEqual(target['worktrees'],[{'root':str(linked),'caller':True}])
        cleanup = subprocess.run(['bash',str(self.scripts/'post-merge-cleanup.sh'),
            '--merge-session',session,'--repo-root',str(self.repo),'--cleanup-repo-root',str(linked),
            '--base','develop','--pr','12','feature/12-item'],cwd=self.repo,env=self.env,text=True,capture_output=True)
        self.assertEqual(cleanup.returncode,0,cleanup.stdout+cleanup.stderr)
        self.assertEqual(json.loads(self.helper('report','--session',session).stdout)['outcome'],'Completed')
        self.assertTrue(linked.is_dir())
        self.assertEqual(subprocess.run(['git','-C',str(linked),'branch','--show-current'],
            text=True,capture_output=True,check=True).stdout.strip(),'')

    def test_retained_local_cleanup_without_remote_deletion_duty(self):
        for branch_kind,fork in [('spec',False),('implementation-plan',False),('feature',True)]:
            for skipped in [['local_cleanup'],['remote_delete','local_cleanup']]:
                with self.subTest(branch_kind=branch_kind,skipped=skipped):
                    branch = branch_kind+'/12-item'
                    current = self.command(['git','branch','--show-current']).stdout.strip()
                    if current != branch:
                        self.command(['git','branch','-m',branch])
                    self.command(['git','push','-q','origin',branch])
                    self.data['prs']['12'].update(state='MERGED',headRefName=branch)
                    self.data['fork'] = fork
                    self.fixture.write_text(json.dumps(self.data))
                    manifest = self.root/'1890-retained-manifest.json'
                    manifest.write_text(json.dumps({'ownerRoot':str(self.repo),'prs':[{
                        'repo':'org/repo','pr':12,'head':self.head,'base':'develop',
                        'root':str(self.repo),'phases':['cleanup'],'policySkipped':skipped}]}))
                    session = json.loads(self.helper('begin','--input',manifest).stdout)['session']
                    target = json.loads(Path(session).read_text())['prs'][0]
                    self.assertFalse(target['remoteCleanup'])
                    self.assertNotIn('remote_delete',target['steps'])
                    cleanup = subprocess.run(['bash',str(self.scripts/'post-merge-cleanup.sh'),
                        '--merge-session',session,'--repo-root',str(self.repo),'--base','develop',
                        '--pr','12',branch],cwd=self.repo,env=self.env,text=True,capture_output=True)
                    self.assertEqual(cleanup.returncode,0,cleanup.stdout+cleanup.stderr)
                    self.assertEqual(json.loads(self.helper('report','--session',session).stdout)['outcome'],'Completed')
                    self.assertTrue(self.command(['git','branch','--list',branch]).stdout.strip())
                    self.assertTrue(self.command(['git','ls-remote','--heads','origin',branch]).stdout.strip())

    def test_retained_local_cleanup_after_verified_remote_deletion(self):
        self.data['prs']['12']['state'] = 'MERGED'
        self.fixture.write_text(json.dumps(self.data))
        manifest = self.root/'1890-completed-remote-manifest.json'
        manifest.write_text(json.dumps({'ownerRoot':str(self.repo),'prs':[{
            'repo':'org/repo','pr':12,'head':self.head,'base':'develop',
            'root':str(self.repo),'phases':['cleanup'],'policySkipped':['local_cleanup']}]}))
        session = json.loads(self.helper('begin','--input',manifest).stdout)['session']
        self.helper('run-step','--session',session,'--repo','org/repo','--pr','12',
                    '--phase','remote_delete','--step','remote_delete','--',
                    'git','push','origin','--delete','feature/12-item')
        cleanup = subprocess.run(['bash',str(self.scripts/'post-merge-cleanup.sh'),
            '--merge-session',session,'--repo-root',str(self.repo),'--base','develop',
            '--pr','12','feature/12-item'],cwd=self.repo,env=self.env,text=True,capture_output=True)
        self.assertEqual(cleanup.returncode,0,cleanup.stdout+cleanup.stderr)
        self.assertEqual(json.loads(self.helper('report','--session',session).stdout)['outcome'],'Completed')
        self.assertTrue(self.command(['git','branch','--list','feature/12-item']).stdout.strip())
        self.assertFalse(self.command(['git','ls-remote','--heads','origin','feature/12-item']).stdout.strip())

    def test_local_retention_refuses_unhandled_applicable_remote_duty(self):
        self.data['prs']['12']['state'] = 'MERGED'
        self.fixture.write_text(json.dumps(self.data))
        manifest = self.root/'1890-applicable-remote-manifest.json'
        manifest.write_text(json.dumps({'ownerRoot':str(self.repo),'prs':[{
            'repo':'org/repo','pr':12,'head':self.head,'base':'develop',
            'root':str(self.repo),'phases':['cleanup'],'policySkipped':['local_cleanup']}]}))
        session = json.loads(self.helper('begin','--input',manifest).stdout)['session']
        cleanup = subprocess.run(['bash',str(self.scripts/'post-merge-cleanup.sh'),
            '--merge-session',session,'--repo-root',str(self.repo),'--base','develop',
            '--pr','12','feature/12-item'],cwd=self.repo,env=self.env,text=True,capture_output=True)
        self.assertNotEqual(cleanup.returncode,0)
        self.assertIn('explicit separate remote step required',cleanup.stderr)
        target = json.loads(Path(session).read_text())['prs'][0]
        self.assertEqual(target['steps']['remote_delete']['status'],'pending')
        self.assertTrue(self.command(['git','branch','--list','feature/12-item']).stdout.strip())
        self.assertTrue(self.command(['git','ls-remote','--heads','origin','feature/12-item']).stdout.strip())

    def test_hub_dispatch_binds_implicit_merge_to_selected_product(self):
        hub = self.root/'1890-hub'
        hub.mkdir()
        subprocess.run(['git','init','-q','-b','develop',str(hub)],check=True)
        (hub/'.ai-dev-workflow.yaml').write_text('schema_version: 2\nmode: workflow_hub\nissue_tracker:\n  provider: none\nworkflow_hub:\n  product_repos:\n    - name: product\n      github_repo: org/repo\n      default_branch: develop\n')
        (hub/'.ai-dev-workflow.local.yaml').write_text('product_repos:\n  - name: product\n    local_path: "'+str(self.repo)+'"\n')
        self.data['checkoutRepos'] = {str(hub):'org/hub',str(self.repo):'org/repo'}
        self.fixture.write_text(json.dumps(self.data))
        manifest = self.root/'1890-product-dispatch.json'
        manifest.write_text(json.dumps({'ownerRoot':str(hub),'prs':[{
            'repo':'org/repo','pr':12,'head':self.head,'base':'develop','root':str(self.repo),
            'phases':['base_push','merge_api','cleanup'],'policySkipped':['remote_delete','local_cleanup']}]}))
        admitted = subprocess.run([sys.executable,str(self.scripts/'workflow-merge-budget.py'),
            'begin','--input',str(manifest)],cwd=hub,env=self.env,text=True,capture_output=True)
        self.assertEqual(admitted.returncode,0,admitted.stderr)
        session = json.loads(admitted.stdout)['session']
        pushed = subprocess.run([sys.executable,str(self.scripts/'workflow-merge-budget.py'),
            'run-step','--session',session,'--repo','org/repo','--pr','12','--phase','base_push',
            '--step','base_push','--','git','push','origin','HEAD:refs/heads/develop'],
            cwd=hub,env=self.env,text=True,capture_output=True)
        self.assertEqual(pushed.returncode,0,pushed.stderr)
        self.assertIn(self.head,self.command(['git','ls-remote','--heads','origin','develop']).stdout)
        merged = subprocess.run([sys.executable,str(self.scripts/'workflow-merge-budget.py'),
            'run-step','--session',session,'--repo','org/repo','--pr','12','--phase','merge_api',
            '--step','merge_api','--','gh','pr','merge','12','--admin','--match-head-commit',self.head],
            cwd=hub,env=self.env,text=True,capture_output=True)
        self.assertEqual(merged.returncode,0,merged.stderr)
        evidence = json.loads(self.fixture.read_text())
        self.assertEqual(evidence.get('foreignMergeCount',0),0)
        self.assertEqual(evidence['mergeContexts'],[{'repo':'org/repo','cwd':str(self.repo)}])
        self.assertEqual(evidence['mergeArgv'][0],['pr','merge','12','--admin','--match-head-commit',self.head])

    def test_mixed_case_cleanup_uses_canonical_nested_repository(self):
        self.data.update(repo='Org/Repo',issueState='OPEN')
        self.data['prs']['12']['state'] = 'MERGED'
        self.fixture.write_text(json.dumps(self.data))
        session = self.begin()
        cleanup = subprocess.run(['bash',str(self.scripts/'post-merge-cleanup.sh'),
            '--merge-session',session,'--repo-root',str(self.repo),'--base','develop',
            '--pr','12','feature/12-item'],cwd=self.repo,env=self.env,text=True,capture_output=True)
        self.assertEqual(cleanup.returncode,0,cleanup.stdout+cleanup.stderr)
        checked = self.helper('check','--session',session,'--repo','ORG/REPO','--pr','12')
        self.assertEqual(json.loads(checked.stdout)['outcome'],'Completed')
        state = json.loads(Path(session).read_text())
        self.assertEqual(state['prs'][0]['repo'],'org/repo')
        self.assertEqual(state['prs'][0]['steps']['issue_close:12']['status'],'completed')
        evidence = json.loads(self.fixture.read_text())
        self.assertEqual([value.lower() for value in evidence['issueMutationRepos']],['org/repo'])
        self.assertEqual(evidence['issueState'],'CLOSED')

    def test_cancelled_merge_retains_effect_and_requires_explicit_resume(self):
        import signal
        # Scope atomic publication to this test's private provider copy.
        provider = self.bin/'gh'
        provider_source = provider.read_text()
        write = 'path.write_text(json.dumps(state))'
        self.assertEqual(provider_source.count(write),2)
        publisher = """def publish_fixture():
    import tempfile
    with tempfile.NamedTemporaryFile(mode='w',dir=path.parent,delete=False) as temporary:
        json.dump(state,temporary)
    os.replace(temporary.name,path)

"""
        provider_source = provider_source.replace("state.setdefault('events', []).append(args[:2])",
            publisher + "state.setdefault('events', []).append(args[:2])")
        provider_source = provider_source.replace(write,'publish_fixture()')
        pause = "while not json.loads(path.read_text()).get('mergeRelease'):"
        self.assertEqual(provider_source.count(pause),1)
        provider_source = provider_source.replace(pause,
            "while not Path(os.environ['MERGE_BUDGET_RELEASE']).exists():")
        provider.write_text(provider_source)

        def publish_fixture(data):
            with tempfile.NamedTemporaryFile(mode='w',dir=self.root,delete=False) as temporary:
                json.dump(data,temporary)
            os.replace(temporary.name,self.fixture)

        def wait_until(read,predicate,process,message):
            deadline = time.monotonic()+15
            while True:
                value = read()
                if predicate(value):
                    return value
                self.assertIsNone(process.poll(),message)
                self.assertLess(time.monotonic(),deadline,message)
                time.sleep(0.02)

        self.cancellation_evidence = []
        for signum,mode in [(signal.SIGTERM,'exit'),(signal.SIGINT,'ignore')]:
            with self.subTest(signal=signum,mode=mode):
                self.data['prs']['12'].update(state='OPEN',isInMergeQueue=False)
                self.data.update(mergePause=mode,mergeReady=False,mergeRelease=False,events=[])
                publish_fixture(self.data)
                release = self.root/('1890-release-'+mode)
                child_env = dict(self.env,MERGE_BUDGET_RELEASE=str(release))
                manifest = self.root/'1890-cancelled-merge.json'
                manifest.write_text(json.dumps({'ownerRoot':str(self.repo),'prs':[{
                    'repo':'org/repo','pr':12,'head':self.head,'base':'develop','root':str(self.repo),
                    'phases':['merge_api','cleanup'],'policySkipped':['remote_delete','local_cleanup']}]}))
                session = json.loads(self.helper('begin','--input',manifest).stdout)['session']
                process = subprocess.Popen([sys.executable,str(self.scripts/'workflow-merge-budget.py'),
                    'run-step','--session',session,'--repo','org/repo','--pr','12','--phase','merge_api',
                    '--step','merge_api','--','gh','pr','merge','12','--match-head-commit',self.head],
                    cwd=self.repo,env=child_env,text=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
                try:
                    wait_until(lambda: json.loads(self.fixture.read_text()),
                        lambda data: data.get('mergeReady'),process,'merge child did not become ready')
                    os.kill(process.pid,signum)
                    if mode == 'ignore':
                        wait_until(lambda: json.loads(Path(session).read_text()),
                            lambda data: data['outcome']=='Interrupted',process,
                            'cancellation not durably recorded while child lives')
                        self.assertIsNone(process.poll())
                        self.assertNotEqual(self.helper('resume','--session',session,success=False).returncode,0)
                        stopped = self.helper('before-step','--session',session,'--repo','org/repo','--pr','12',
                            '--phase','cleanup','--step','cleanup',success=False)
                        self.assertNotEqual(stopped.returncode,0)
                finally:
                    # Releasing does not race the provider's JSON/event publication.
                    try:
                        release.touch()
                    finally:
                        try:
                            output,error = process.communicate(timeout=15)
                        except subprocess.TimeoutExpired:
                            # Kill only this fixture's recorded group, then always reap its executor.
                            try:
                                child_group = (json.loads(Path(session).read_text()).get('active') or {}).get('childGroup')
                                if child_group:
                                    try:
                                        os.killpg(child_group,signal.SIGKILL)
                                    except ProcessLookupError:
                                        pass
                            finally:
                                process.kill()
                                output,error = process.communicate()
                            self.fail('merge child did not join after release: '+output+error)
                self.assertNotEqual(process.returncode,0,output+error)
                state = json.loads(Path(session).read_text())
                self.assertEqual(state['outcome'],'Interrupted')
                self.assertEqual(state['prs'][0]['verifiedState'],'merged')
                self.assertEqual(state['prs'][0]['steps']['merge_api']['status'],'completed')
                self.assertNotEqual(self.helper('before-step','--session',session,'--repo','org/repo','--pr','12',
                    '--phase','cleanup','--step','cleanup',success=False).returncode,0)
                count = json.loads(self.fixture.read_text())['events'].count(['pr','merge'])
                self.helper('resume','--session',session)
                resumed = json.loads(Path(session).read_text())
                self.assertNotIn('cancellation',resumed)
                self.assertTrue(any(item.get('cancellation') for item in resumed['history']))
                self.helper('run-step','--session',session,'--repo','org/repo','--pr','12',
                    '--phase','merge_verify','--step','merge_verify','--','true')
                self.command(['bash',str(self.scripts/'post-merge-cleanup.sh'),'--merge-session',session,
                    '--repo-root',str(self.repo),'--base','develop','--pr','12','feature/12-item'],self.env)
                self.assertEqual(json.loads(self.helper('report','--session',session).stdout)['outcome'],'Completed')
                self.assertEqual(json.loads(self.fixture.read_text())['events'].count(['pr','merge']),count)
                self.cancellation_evidence.append({'signal':signum.name,'childMode':mode,
                    'cancelledOutcome':state['outcome'],'verifiedState':state['prs'][0]['verifiedState'],
                    'mergeStep':state['prs'][0]['steps']['merge_api']['status'],
                    'childExitCode':state['prs'][0]['steps']['merge_api']['exitCode'],
                    'liveChildRecoveryRefused':mode=='ignore','currentStoppingCleared':True,
                    'historyRetainsCancellation':True,'finalOutcome':'Completed','duplicateMergeCount':0})

    def test_actual_queue_waiting_no_cleanup_or_resubmission(self):
        self.data['queue'] = True
        self.fixture.write_text(json.dumps(self.data))
        session = self.begin()
        result = subprocess.run(['bash',str(self.scripts/'batch-merge.sh'),'--merge-session',session,
                                'merge','--pr','12','--expected-head-sha',self.head], cwd=self.repo,
                                env=self.env,text=True,capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('MERGE_RESULT=waiting',result.stdout)
        state = json.loads(self.helper('report','--session',session,success=False).stdout)
        self.assertEqual(state['outcome'],'Waiting')
        self.helper('resume','--session',session,success=False)
        events = json.loads(self.fixture.read_text())['events']
        self.assertEqual(events.count(['pr','merge']), 1)
        self.assertNotIn(['issue','close'], events)

    def two_pr_manifest(self):
        value = dict(self.data['prs']['12'], number=13, headRefName='feature/13-item')
        self.data['prs']['13'] = value
        self.fixture.write_text(json.dumps(self.data))
        self.command(['git','branch','feature/13-item',self.head])
        self.command(['git','push','-q','origin','feature/13-item'])
        path = self.root/'1890-batch.json'
        path.write_text(json.dumps({'ownerRoot':str(self.repo), 'prs': [
            {'repo':'org/repo','pr':n,'head':self.head,'base':'develop','root':str(self.repo),
             'phases':['local_merge','base_push','merge_api','cleanup'],
             'policySkipped':['remote_delete','local_cleanup']} for n in (12,13)]}))
        return path

    def test_actual_full_batch_refuses_affordable_prefix_and_no_fallback(self):
        self.data['quota']['remaining'] = 1150  # single125+reserve fits; whole195+reserve does not
        path = self.two_pr_manifest()
        result = self.helper('begin','--input',path,success=False)
        self.assertNotEqual(result.returncode,0)
        response = json.loads(result.stdout)
        self.assertEqual(response['outcome'],'Deferred')
        session = response['session']
        result = subprocess.run(['bash',str(self.scripts/'batch-merge.sh'),'--merge-session',session,
                                'merge','--pr','12','--expected-head-sha',self.head],cwd=self.repo,env=self.env,
                                text=True,capture_output=True)
        self.assertNotEqual(result.returncode,0)
        self.assertNotIn(['pr','merge'],json.loads(self.fixture.read_text())['events'])
        self.assertEqual(self.command(['git','rev-parse','HEAD']).stdout.strip(),self.head)

    def test_actual_outage_after_verified_merge_offline_resume_no_duplicate(self):
        path = self.two_pr_manifest()
        session = json.loads(self.helper('begin','--input',path).stdout)['session']
        self.command(['bash',str(self.scripts/'batch-merge.sh'),'--merge-session',session,
                      'merge','--pr','12','--expected-head-sha',self.head],self.env)
        data = json.loads(self.fixture.read_text())
        data.update(prOutage=True,quotaOutage=True)
        self.fixture.write_text(json.dumps(data))
        result = subprocess.run(['bash',str(self.scripts/'post-merge-cleanup.sh'),'--merge-session',session,
                     '--repo-root',str(self.repo),'--base','develop','--pr','12','feature/12-item'],
                     cwd=self.repo,env=self.env,text=True,capture_output=True)
        self.assertNotEqual(result.returncode,0)
        report = json.loads(self.helper('report','--session',session,'--final').stdout)
        self.assertEqual(report['outcome'],'Interrupted')
        self.assertEqual(report['prs'][0]['verifiedState'],'merged')
        self.assertIsNone(report['observedSpend'])
        resumed = self.helper('resume','--session',session,success=False)
        self.assertEqual(json.loads(resumed.stdout)['outcome'],'Deferred')
        # Even with historical started=true, Deferred never grants pending dispatch.
        direct = self.helper('run-step','--session',session,'--repo','org/repo','--pr','13',
                             '--step','merge_api','--phase','merge_api','--','gh','pr','merge','13',
                             '--merge','--match-head-commit',self.head,success=False)
        self.assertNotEqual(direct.returncode,0)
        result = subprocess.run(['bash',str(self.scripts/'batch-merge.sh'),'--merge-session',session,
                                'merge','--pr','13','--expected-head-sha',self.head],cwd=self.repo,env=self.env,
                                text=True,capture_output=True)
        self.assertNotEqual(result.returncode,0)
        data = json.loads(self.fixture.read_text())
        self.assertEqual(data['events'].count(['pr','merge']),1)
        data.update(prOutage=False,quotaOutage=False)
        self.fixture.write_text(json.dumps(data))
        report = json.loads(self.helper('resume','--session',session).stdout)
        self.assertEqual(report['prs'][0]['verifiedState'],'merged')
        self.command(['bash',str(self.scripts/'post-merge-cleanup.sh'),'--merge-session',session,
                      '--repo-root',str(self.repo),'--base','develop','--pr','12','feature/12-item'],self.env)
        self.assertEqual(json.loads(self.fixture.read_text())['events'].count(['pr','merge']),1)
        report = json.loads(self.helper('report','--session',session).stdout)
        self.assertTrue(all(s['status'] in {'completed','skipped_by_policy'} for s in report['prs'][0]['steps'].values()))

    def test_actual_partial_close_effects_recover_without_replaying_success(self):
        for failure in ('closeFailure','omitCloseComment'):
            with self.subTest(failure=failure):
                if failure == 'omitCloseComment':
                    # A separate fixture resets all Git, quota and journal identities.
                    self.tearDown(); self.doCleanups(); self.setUp()
                self.evidence_case = failure
                self.data.update(issueState='OPEN',**{failure:True})
                self.fixture.write_text(json.dumps(self.data))
                session = self.begin()
                self.command(['bash',str(self.scripts/'batch-merge.sh'),'--merge-session',session,
                              'merge','--pr','12','--expected-head-sha',self.head],self.env)
                argv = ['bash',str(self.scripts/'post-merge-cleanup.sh'),'--merge-session',session,
                        '--repo-root',str(self.repo),'--base','develop','--pr','12','feature/12-item']
                result = subprocess.run(argv,cwd=self.repo,env=self.env,text=True,capture_output=True)
                self.assertNotEqual(result.returncode,0)
                report = json.loads(self.helper('report','--session',session).stdout)
                step = report['prs'][0]['steps']['issue_close:12']
                self.assertEqual(step['issueStateBefore'],'OPEN')
                self.assertTrue(step['commentRequired'])
                expected = {'closure':'pending','comment':'completed'} if failure == 'closeFailure' else {'closure':'completed','comment':'pending'}
                self.assertEqual(step['effects'],expected)
                data = json.loads(self.fixture.read_text()); data[failure] = False
                self.fixture.write_text(json.dumps(data))
                self.helper('resume','--session',session)
                self.command(argv,self.env)
                data = json.loads(self.fixture.read_text())
                self.assertEqual(len(data['comments']),1)
                self.assertEqual(data['issueState'],'CLOSED')
                self.assertEqual(data['events'].count(['issue','comment']),0 if failure == 'closeFailure' else 1)
                self.assertEqual(data['events'].count(['issue','close']),2 if failure == 'closeFailure' else 1)
                self.assertEqual(json.loads(self.helper('report','--session',session).stdout)['outcome'],'Completed')

    def test_actual_closed_released_tracker_preserves_forward_progress(self):
        (self.repo/'.ai-dev-workflow.yaml').write_text('issue_tracker:\n  provider: github_projects\n  project_number: 1\n')
        self.data.update(trackerStatus='Released',issueState='CLOSED')
        self.fixture.write_text(json.dumps(self.data))
        session = self.begin()
        self.command(['bash',str(self.scripts/'batch-merge.sh'),'--merge-session',session,
                      'merge','--pr','12','--expected-head-sha',self.head],self.env)
        self.command(['bash',str(self.scripts/'post-merge-cleanup.sh'),'--merge-session',session,
                      '--repo-root',str(self.repo),'--base','develop','--pr','12','feature/12-item'],self.env)
        report = json.loads(self.helper('report','--session',session).stdout)
        self.assertEqual(report['outcome'],'Completed')
        data = json.loads(self.fixture.read_text())
        self.assertEqual(data['trackerStatus'],'Released')
        self.assertEqual(data.get('trackerMutationCount',0),0)
        self.assertNotIn(['issue','close'],data['events'])

    def test_actual_failed_tracker_zero_exit_requires_recovery(self):
        (self.repo/'.ai-dev-workflow.yaml').write_text('issue_tracker:\n  provider: github_projects\n  project_number: 1\n')
        self.data.update(trackerFailure=True,trackerStatus='Plan Ready')
        self.fixture.write_text(json.dumps(self.data))
        session = self.begin()
        self.command(['bash',str(self.scripts/'batch-merge.sh'),'--merge-session',session,
                      'merge','--pr','12','--expected-head-sha',self.head],self.env)
        result = subprocess.run(['bash',str(self.scripts/'post-merge-cleanup.sh'),'--merge-session',session,
                      '--repo-root',str(self.repo),'--base','develop','--pr','12','feature/12-item'],
                      cwd=self.repo,env=self.env,text=True,capture_output=True)
        self.assertNotEqual(result.returncode,0)
        report = json.loads(self.helper('report','--session',session).stdout)
        self.assertEqual(report['outcome'],'Interrupted')
        self.assertEqual(report['prs'][0]['verifiedState'],'merged')
        data = json.loads(self.fixture.read_text())
        data['trackerFailure'] = False
        self.fixture.write_text(json.dumps(data))
        self.helper('resume','--session',session)
        result = self.command(['bash',str(self.scripts/'post-merge-cleanup.sh'),'--merge-session',session,
                      '--repo-root',str(self.repo),'--base','develop','--pr','12','feature/12-item'],self.env)
        self.assertEqual(json.loads(self.helper('report','--session',session).stdout)['outcome'],'Completed')
        self.assertEqual(json.loads(self.fixture.read_text())['events'].count(['pr','merge']),1)

    def test_recovery_after_local_cleanup_finishes_only_pending_reconciliation(self):
        (self.repo/'.ai-dev-workflow.yaml').write_text('issue_tracker:\n  provider: github_projects\n  project_number: 1\n')
        self.data.update(trackerFailure=True,trackerStatus='Plan Ready',issueState='OPEN')
        self.fixture.write_text(json.dumps(self.data))
        session = self.begin(skipped=False)
        self.command(['bash',str(self.scripts/'batch-merge.sh'),'--merge-session',session,
                      'merge','--pr','12','--expected-head-sha',self.head],self.env)
        argv = ['bash',str(self.scripts/'post-merge-cleanup.sh'),'--merge-session',session,
                '--repo-root',str(self.repo),'--base','develop','--pr','12','feature/12-item']
        failed = subprocess.run(argv,cwd=self.repo,env=self.env,text=True,capture_output=True)
        self.assertNotEqual(failed.returncode,0)
        state = json.loads(Path(session).read_text())
        self.assertEqual(state['outcome'],'Interrupted')
        self.assertEqual(state['prs'][0]['steps']['local_cleanup']['status'],'completed')
        self.assertFalse(self.command(['git','branch','--list','feature/12-item']).stdout.strip())
        self.assertFalse(self.command(['git','ls-remote','--heads','origin','feature/12-item']).stdout.strip())
        data = json.loads(self.fixture.read_text()); data['trackerFailure'] = False
        self.fixture.write_text(json.dumps(data))
        self.helper('resume','--session',session)
        recovered = subprocess.run(argv,cwd=self.repo,env=self.env,text=True,capture_output=True)
        self.assertEqual(recovered.returncode,0,recovered.stdout+recovered.stderr)
        self.assertIn('previous local cleanup outcome independently verified',recovered.stdout)
        self.assertNotIn('develop is updated',recovered.stdout)
        self.assertNotIn('Fetching origin',recovered.stdout)
        self.assertNotIn('Deleting local branch',recovered.stdout)
        self.assertEqual(json.loads(self.helper('report','--session',session).stdout)['outcome'],'Completed')
        data = json.loads(self.fixture.read_text())
        self.assertEqual(data['events'].count(['pr','merge']),1)
        self.assertEqual(data['events'].count(['issue','close']),1)
        self.assertEqual(data['issueState'],'CLOSED')
        self.assertEqual(len(data['comments']),1)
        self.assertEqual(data['trackerStatus'],'Merged')

    def test_actual_conflict_resolution_requires_explicit_resume_before_push(self):
        (self.repo/'base.txt').write_text('feature change\n')
        self.command(['git','add','base.txt']);self.command(['git','commit','-qm','fixture feature conflict'])
        self.head=self.command(['git','rev-parse','HEAD']).stdout.strip()
        self.command(['git','push','-q','origin','feature/12-item'])
        self.data['prs']['12']['headRefOid']=self.head;self.fixture.write_text(json.dumps(self.data))
        self.command(['git','checkout','develop'])
        (self.repo/'base.txt').write_text('base change\n')
        self.command(['git','add','base.txt']);self.command(['git','commit','-qm','fixture base conflict'])
        self.command(['git','push','-q','origin','develop'])
        before_remote=self.command(['git','rev-parse','HEAD']).stdout.strip()
        session=self.begin()
        conflicted=self.helper('run-step','--session',session,'--repo','org/repo','--pr','12',
            '--step','local_merge','--phase','local_merge','--','git','merge','--no-ff','--no-edit',self.head,success=False)
        self.assertNotEqual(conflicted.returncode,0)
        state=json.loads(Path(session).read_text())
        self.assertEqual(state['outcome'],'Interrupted')
        self.assertEqual(state['prs'][0]['steps']['local_merge']['status'],'uncertain')
        self.assertTrue((self.repo/'.git/MERGE_HEAD').exists())
        (self.repo/'base.txt').write_text('resolved feature and base changes\n')
        self.command(['git','add','base.txt']);self.command(['git','commit','-qm','fixture resolve merge conflict'])
        resolved=self.command(['git','rev-parse','HEAD']).stdout.strip()
        push=['run-step','--session',session,'--repo','org/repo','--pr','12','--step','base_push',
              '--phase','base_push','--','git','push','origin','HEAD:refs/heads/develop']
        denied=self.helper(*push,success=False)
        self.assertNotEqual(denied.returncode,0)
        self.assertTrue(self.command(['git','ls-remote','origin','refs/heads/develop']).stdout.startswith(before_remote))
        self.assertNotIn(['pr','merge'],json.loads(self.fixture.read_text())['events'])
        recovered=json.loads(self.helper('resume','--session',session).stdout)
        self.assertEqual(recovered['outcome'],'Admitted')
        self.assertEqual(recovered['prs'][0]['steps']['local_merge']['status'],'completed')
        self.assertEqual(recovered['prs'][0]['steps']['local_merge']['commit'],resolved)
        self.helper(*push)
        self.helper('run-step','--session',session,'--repo','org/repo','--pr','12','--step','merge_api',
            '--phase','merge_api','--','gh','pr','merge','12','--merge','--match-head-commit',self.head)
        self.helper('run-step','--session',session,'--repo','org/repo','--pr','12','--step','merge_verify',
            '--phase','merge_verify','--','true')
        self.command(['bash',str(self.scripts/'post-merge-cleanup.sh'),'--merge-session',session,
            '--repo-root',str(self.repo),'--base','develop','--pr','12','feature/12-item'],self.env)
        self.assertEqual(json.loads(self.helper('report','--session',session).stdout)['outcome'],'Completed')
        self.assertEqual(json.loads(self.fixture.read_text())['events'].count(['pr','merge']),1)
        self.assertTrue(self.command(['git','ls-remote','origin','refs/heads/develop']).stdout.startswith(resolved))

    def test_actual_failed_push_retries_frozen_commit_after_checkout_change(self):
        session = self.begin()
        self.command(['git','checkout','develop'])
        self.helper('run-step','--session',session,'--repo','org/repo','--pr','12',
                    '--step','local_merge','--phase','local_merge','--',
                    'git','merge','--no-ff','--no-edit',self.head)
        result = self.helper('run-step','--session',session,'--repo','org/repo','--pr','12',
                             '--step','base_push','--phase','base_push','--','false',success=False)
        self.assertNotEqual(result.returncode,0)
        intended = json.loads(self.helper('report','--session',session).stdout)['prs'][0]['steps']['base_push']['expectedCommit']
        self.command(['git','checkout','-b','1890-other-checkout',self.head])
        self.helper('resume','--session',session)
        self.helper('run-step','--session',session,'--repo','org/repo','--pr','12',
                    '--step','base_push','--phase','base_push','--',
                    'git','push','origin',intended+':refs/heads/develop')
        report = json.loads(self.helper('report','--session',session).stdout)
        self.assertEqual(report['prs'][0]['steps']['base_push']['commit'],intended)
        self.assertTrue(self.command(['git','ls-remote','origin','refs/heads/develop']).stdout.startswith(intended))
        self.assertNotEqual(self.command(['git','rev-parse','HEAD']).stdout.strip(),intended)
        self.assertNotIn(['pr','merge'],json.loads(self.fixture.read_text())['events'])

    def test_actual_advanced_base_recovery_preserves_pushed_commit(self):
        session = self.begin()
        self.command(['bash',str(self.scripts/'batch-merge.sh'),'--merge-session',session,
                      'merge','--pr','12','--expected-head-sha',self.head],self.env)
        old = json.loads(self.helper('report','--session',session).stdout)['prs'][0]['steps']['base_push']['commit']
        (self.repo/'1890-advance').write_text('later base commit')
        self.command(['git','add','1890-advance'])
        self.command(['git','commit','-m','test: advance fixture base'])
        advanced = self.command(['git','rev-parse','HEAD']).stdout.strip()
        self.command(['git','push','origin','develop'])
        self.command(['git','checkout','-b','1890-operator-context',self.head])
        self.helper('resume','--session',session)
        step = json.loads(self.helper('report','--session',session).stdout)['prs'][0]['steps']['base_push']
        self.assertEqual(step['commit'],old)
        self.assertEqual(step['verifiedRemoteCommit'],advanced)
        self.assertEqual(json.loads(self.fixture.read_text())['events'].count(['pr','merge']),1)

    def test_actual_first_audit_refresh_and_malformed_manifests(self):
        path = self.root/'1890-audit-manifest.json'
        selected = {'repo':'org/repo','pr':12,'head':self.head,'base':'develop','root':str(self.repo),
                    'steps':[{'id':'audit:pre','phase':'audit','auditRepo':'org/repo',
                              'auditTarget':12,'marker':'<!-- 1890-fixture -->'}]}
        path.write_text(json.dumps({'ownerRoot':str(self.repo),'prs':[selected]}))
        session = json.loads(self.helper('begin','--input',path).stdout)['session']
        data = json.loads(self.fixture.read_text()); data['quota']['remaining'] = 1
        self.fixture.write_text(json.dumps(data))
        body = self.root/'1890-audit-body'; body.write_text('<!-- 1890-fixture --> fixture')
        result = self.helper('run-step','--session',session,'--repo','org/repo','--pr','12',
                             '--step','audit:pre','--phase','audit','--expected-file',body,
                             '--','gh','api','repos/org/repo/issues/12/comments','-X','POST',
                             '-f','body='+body.read_text(),success=False)
        self.assertNotEqual(result.returncode,0)
        events = json.loads(self.fixture.read_text())['events']
        self.assertNotIn(['api','repos/org/repo/issues/12/comments'],events)
        for declaration in [[], {'prs':None}, {'prs':[None]},
                            {'prs':[dict(selected,phases=None)]},
                            {'prs':[dict(selected,steps=[None])]}, {'prs':[dict(selected,steps=None)]}, {'prs':[dict(selected,steps=[{'id':'bad','phase':[]}])]}, {'prs':[dict(selected,policySkipped=None)]}, {'prs':[dict(selected,root=[])]}, {'ownerRoot':[], 'prs':[selected]}]:
            path.write_text(json.dumps(declaration))
            result = self.helper('begin','--input',path,success=False)
            self.assertEqual(result.returncode,2)
            self.assertEqual(json.loads(result.stdout)['outcome'],'Deferred')
            self.assertNotIn('Traceback',result.stderr)

    def test_actual_invalid_json_retains_durable_deferred_report(self):
        path = self.root/'1890-invalid-manifest.json'
        for raw in ['{"prs":[],"prs":[]}', '{"prs":NaN}', '{not-json', '{"prs":Infinity}']:
            path.write_text(raw)
            result = self.helper('begin','--input',path,success=False)
            self.assertEqual(result.returncode,2)
            report = json.loads(result.stdout)
            self.assertEqual(report['outcome'],'Deferred')
            self.assertFalse(report['projectionComplete'])
            self.assertTrue(Path(report['session']).is_file())
            self.assertEqual(json.loads(self.helper('report','--session',report['session']).stdout)['outcome'],'Deferred')
            self.assertNotIn('Traceback',result.stderr)

    def test_applied_final_audit_patch_recovers_in_execution_order(self):
        for phase,reverse,cross_pr,outage in [('audit',False,False,True),('audit',True,False,True),
                                            ('audit',False,True,True),('hold',False,False,True),
                                            ('audit',False,True,False)]:
            with self.subTest(phase=phase,reverse=reverse,cross_pr=cross_pr,outage=outage):
                self.data.update(comments=[],commentReadOutage=False,auditPatchReadOutage=False,
                                 commentMutationCount=0,events=[])
                self.data['prs']['13'] = dict(self.data['prs']['12'],number=13)
                self.fixture.write_text(json.dumps(self.data))
                scope = dict(phase=phase,auditRepo='org/repo',auditTarget=900,marker='<!-- fixture-ledger -->')
                pre,final = dict(scope,id='audit:pre'),dict(scope,id='audit:final')
                selected = dict(repo='org/repo',pr=12,head=self.head,base='develop',root=str(self.repo))
                targets = [dict(selected,steps=[final,pre] if reverse else [pre,final])]
                if cross_pr:
                    targets = [dict(selected,steps=[pre]),dict(selected,pr=13,steps=[final])]
                manifest = self.root/'1890-audit-supersession.json'
                manifest.write_text(json.dumps({'ownerRoot':str(self.repo),'prs':targets}))
                session = json.loads(self.helper('begin','--input',manifest).stdout)['session']
                body = self.root/'1890-ledger-body';body.write_text('<!-- fixture-ledger --> pre')
                self.helper('run-step','--session',session,'--repo','org/repo','--pr','12',
                    '--phase',phase,'--step','audit:pre','--expected-file',body,'--','gh','api',
                    'repos/org/repo/issues/900/comments','-X','POST','-f','body='+body.read_text())
                body.write_text('<!-- fixture-ledger --> final')
                data = json.loads(self.fixture.read_text());data['auditPatchReadOutage'] = outage
                self.fixture.write_text(json.dumps(data))
                failed = self.helper('run-step','--session',session,'--repo','org/repo','--pr',13 if cross_pr else 12,
                    '--phase',phase,'--step','audit:final','--expected-file',body,'--','gh','api',
                    'repos/org/repo/issues/comments/1','-X','PATCH','-f','body='+body.read_text(),success=False)
                self.assertEqual(failed.returncode != 0,outage)
                self.assertEqual(json.loads(Path(session).read_text())['outcome'],'Interrupted' if outage else 'Completed')
                data = json.loads(self.fixture.read_text());data['commentReadOutage'] = False
                self.fixture.write_text(json.dumps(data))
                recovered = self.helper('resume','--session',session)
                self.assertEqual(json.loads(recovered.stdout)['outcome'],'Completed')
                state = json.loads(Path(session).read_text())
                self.assertEqual(state['prs'][0]['steps']['audit:pre']['status'],'completed')
                self.assertIsNotNone(state['prs'][0]['steps']['audit:pre'].get('supersededBy'))
                data = json.loads(self.fixture.read_text())
                self.assertEqual(data['comments'],[{'id':1,'body':body.read_text()}])
                self.assertEqual(data['commentMutationCount'],2)

    def test_unissued_final_declaration_cannot_discharge_overwritten_pre_audit(self):
        scope = dict(phase='audit',auditRepo='org/repo',auditTarget=900,marker='<!-- fixture-ledger -->')
        manifest = self.root/'1890-unissued-audit.json'
        manifest.write_text(json.dumps({'ownerRoot':str(self.repo),'prs':[dict(repo='org/repo',pr=12,
            head=self.head,base='develop',root=str(self.repo),steps=[dict(scope,id='pre'),dict(scope,id='final')])]}))
        session = json.loads(self.helper('begin','--input',manifest).stdout)['session']
        body = self.root/'1890-issued-pre-body';body.write_text('<!-- fixture-ledger --> pre')
        self.helper('run-step','--session',session,'--repo','org/repo','--pr','12','--phase','audit',
            '--step','pre','--expected-file',body,'--','gh','api','repos/org/repo/issues/900/comments',
            '-X','POST','-f','body='+body.read_text())
        data = json.loads(self.fixture.read_text());data['comments'][0]['body']='<!-- fixture-ledger --> final'
        self.fixture.write_text(json.dumps(data))
        self.assertNotEqual(self.helper('resume','--session',session,success=False).returncode,0)
        state = json.loads(Path(session).read_text())
        self.assertEqual(state['outcome'],'Deferred')
        self.assertEqual(state['prs'][0]['steps']['pre']['status'],'completed')
        self.assertNotIn('supersededBy',state['prs'][0]['steps']['pre'])
        self.assertEqual(state['prs'][0]['steps']['final']['status'],'pending')
        self.assertNotIn('intentAt',state['prs'][0]['steps']['final'])
        self.assertEqual(json.loads(self.fixture.read_text())['commentMutationCount'],1)

    def test_actual_failed_audit_readable_absence_retries_exact_intent(self):
        path = self.root/'1890-audit-retry-manifest.json'
        path.write_text(json.dumps({'ownerRoot':str(self.repo),'prs':[{'repo':'org/repo','pr':12,
            'head':self.head,'base':'develop','root':str(self.repo),'steps':[{'id':'audit:pre','phase':'audit',
            'auditRepo':'org/repo','auditTarget':12,'marker':'<!-- 1890-fixture -->'}]}]}))
        session = json.loads(self.helper('begin','--input',path).stdout)['session']
        body = self.root/'1890-audit-body'; body.write_text('<!-- 1890-fixture --> exact fixture')
        args = ['run-step','--session',session,'--repo','org/repo','--pr','12','--step','audit:pre',
                '--phase','audit','--expected-file',body,'--','gh','api',
                'repos/org/repo/issues/12/comments','-X','POST','-f','body='+body.read_text()]
        data = json.loads(self.fixture.read_text()); data['auditFailure'] = True
        self.fixture.write_text(json.dumps(data))
        self.assertNotEqual(self.helper(*args,success=False).returncode,0)
        data = json.loads(self.fixture.read_text()); data['auditFailure'] = False
        self.fixture.write_text(json.dumps(data))
        self.helper('resume','--session',session)
        self.helper(*args)
        self.assertEqual(json.loads(self.helper('report','--session',session).stdout)['outcome'],'Completed')
        self.assertEqual(json.loads(self.fixture.read_text())['comments'][0]['body'],body.read_text())

    def test_session_dispatch_clears_foreign_github_repo_override(self):
        (self.repo/'.ai-dev-workflow.yaml').write_text('issue_tracker:\n  provider: github_projects\n  project_number: 1\n')
        self.data['trackerStatus'] = 'Plan Ready'
        self.data['issueState'] = 'OPEN'; self.fixture.write_text(json.dumps(self.data))
        self.env['GH_REPO'] = 'foreign/same-number'
        self.env['WORKFLOW_TARGET_GITHUB_REPO'] = 'foreign/same-number'
        session = self.begin()
        # Initial explicit helper inspection and gated actual child use physical ownership.
        self.helper('run-step','--session',session,'--repo','org/repo','--pr','12',
                    '--step','merge_api','--phase','merge_api','--',
                    'gh','pr','merge','12','--merge','--match-head-commit',self.head)
        self.helper('run-step','--session',session,'--repo','org/repo','--pr','12',
                    '--step','tracker:12:pre','--phase','tracker','--issue','12','--status','Merged',
                    '--','bash','-c','source "$1/workflow-lib.sh"; update_tracker_status_best_effort 12 Merged',
                    '1890-owned-tracker',self.scripts)
        self.helper('run-step','--session',session,'--repo','org/repo','--pr','12',
                    '--step','issue_close:12','--phase','issue_close','--issue','12','--status','Merged',
                    '--','gh','issue','close','12','--comment','Closed by PR #12.')
        data = json.loads(self.fixture.read_text())
        self.assertEqual(data['issueMutationRepos'],['org/repo'])
        self.assertEqual(data['trackerMutationRepos'],['org/repo'])
        self.assertEqual(data['issueState'],'CLOSED')
        self.assertEqual(json.loads(self.helper('report','--session',session).stdout)['prs'][0]['issues'][0]['repo'],'org/repo')

    def test_actual_authorized_admin_argv_is_preserved(self):
        session = self.begin()
        argv = ['gh','pr','merge','12','--merge','--admin','--match-head-commit',self.head]
        self.helper('run-step','--session',session,'--repo','org/repo','--pr','12',
                    '--step','merge_api','--phase','merge_api','--',*argv)
        data = json.loads(self.fixture.read_text())
        self.assertEqual(data['mergeArgv'],[argv[1:]])
        report = json.loads(self.helper('report','--session',session).stdout)
        self.assertEqual(report['outcome'],'Admitted')
        self.assertEqual(report['prs'][0]['steps']['cleanup']['status'],'pending')
        self.assertEqual(report['prs'][0]['steps']['merge_verify']['status'],'pending')

    def test_actual_already_merged_never_replays_api(self):
        self.data['prs']['12']['state'] = 'MERGED'
        self.fixture.write_text(json.dumps(self.data))
        result = self.command(['bash',str(self.scripts/'batch-merge.sh'),'merge','--pr','12',
                               '--expected-head-sha',self.head],self.env)
        self.assertIn('MERGE_API_RESULT=already_merged',result.stdout)
        self.assertNotIn(['pr','merge'],json.loads(self.fixture.read_text())['events'])

    def test_planted_admission_violation_is_detected_and_restored(self):
        helper = self.scripts/'workflow-merge-budget.py'
        original = helper.read_text()
        predicate = 'if sample["remaining"] < state["estimate"]["projectedCost"] + state["reserve"]:'
        self.assertEqual(original.count(predicate),1)
        line = original[:original.index(predicate)].count('\n')+1
        self.data['quota']['remaining'] = 1
        self.fixture.write_text(json.dumps(self.data))
        argv = ['bash',str(self.scripts/'batch-merge.sh'),'merge','--pr','12','--expected-head-sha',self.head]
        green = subprocess.run(argv,cwd=self.repo,env=self.env,text=True,capture_output=True)
        self.assertNotEqual(green.returncode,0)
        self.assertNotIn(['pr','merge'],json.loads(self.fixture.read_text())['events'])
        try:
            helper.write_text(original.replace(predicate,'if False and sample["remaining"] < state["estimate"]["projectedCost"] + state["reserve"]:'))
            red = subprocess.run(argv,cwd=self.repo,env=self.env,text=True,capture_output=True)
            red_events = json.loads(self.fixture.read_text())['events']
            with self.assertRaises(AssertionError):
                self.assertNotIn(['pr','merge'],red_events)
            self.assertIn(['pr','merge'],red_events)
        finally:
            helper.write_text(original)
        self.assertEqual(helper.read_text(),original)
        data = json.loads(self.fixture.read_text()); data['prs']['12']['state'] = 'OPEN'; data['events'] = []
        self.fixture.write_text(json.dumps(data))
        restored = subprocess.run(argv,cwd=self.repo,env=self.env,text=True,capture_output=True)
        self.assertNotEqual(restored.returncode,0)
        self.assertNotIn(['pr','merge'],json.loads(self.fixture.read_text())['events'])
        evidence = Path(os.environ.get('WORKFLOW_MERGE_BUDGET_TEST_EVIDENCE_DIR',str(self.root)))/'1890-planted-admission-proof.json'
        if evidence.parent.is_dir():
            revision = subprocess.run(['git','rev-parse','HEAD'],cwd=self.source,text=True,capture_output=True,check=True).stdout.strip()
            evidence.write_text(json.dumps({'source':'scripts/development-workflow/workflow-merge-budget.py',
                'line':line,'revision':revision,'fixtureOnly':True,'predicate':predicate,
                'sourceDigest':__import__('hashlib').sha256(original.encode()).hexdigest(),
                'baseline':'green, zero merge dispatch','planted':'red, forbidden fixture merge detected',
                'restored':'green, zero merge dispatch'},indent=2)+'\n')

    def test_actual_insufficient_session_has_zero_mutations(self):
        self.data['quota']['remaining'] = 1
        self.fixture.write_text(json.dumps(self.data))
        result = subprocess.run(['bash',str(self.scripts/'batch-merge.sh'),'merge','--pr','12',
                                 '--expected-head-sha',self.head], cwd=self.repo,env=self.env,text=True,capture_output=True)
        self.assertNotEqual(result.returncode,0)
        self.assertIn('MERGE_RESULT=deferred',result.stdout)
        self.assertNotIn(['pr','merge'],json.loads(self.fixture.read_text())['events'])
        self.assertEqual(self.command(['git','rev-parse','HEAD']).stdout.strip(),self.head)



class ReleaseScope(unittest.TestCase):
    command = Composed.command
    helper = Composed.helper

    def setUp(self):
        dates=patch.dict(os.environ,{'GIT_AUTHOR_DATE':'2026-10-10T12:00:00Z','GIT_COMMITTER_DATE':'2026-10-10T12:00:00Z'})
        dates.start();self.addCleanup(dates.stop)
        Composed.setUp(self)
        shutil.copyfile(self.source/'prepare-release-post-merge-cleanup.sh', self.scripts/'prepare-release-post-merge-cleanup.sh')
        (self.repo/'.ai-dev-workflow.yaml').write_text('issue_tracker:\n  provider: github_projects\n  project_number: 1\n')
        self.env.update(GITHUB_PROJECT_OWNER='org', GITHUB_PROJECT_NUMBER='1')

    def scope(self, section='- Shipped (#12).\n', *, success=True, version='v1.2.3'):
        (self.repo/'CHANGELOG.md').write_text('# Changes\n\n## [1.2.3] - 2026-10-10\n'+section)
        self.command(['git','add','CHANGELOG.md','.ai-dev-workflow.yaml'])
        self.command(['git','commit','-qm','fixture release scope'])
        self.release_head = self.command(['git','rev-parse','HEAD']).stdout.strip()
        self.fixture.write_text(json.dumps(self.data))
        result = subprocess.run(['bash',str(self.scripts/'prepare-release-post-merge-cleanup.sh'),version,
            '--inspect-targets','--release-head',self.release_head],cwd=self.repo,env=self.env,text=True,capture_output=True)
        if success:
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            return json.loads(result.stdout)
        self.assertNotEqual(result.returncode,0,result.stdout+result.stderr)
        return result

    def candidate(self, number, commit, *, repository='org/repo'):
        self.data.setdefault('releaseProjectItems',[]).append({'content': {'__typename':'Issue','number':number,
            'repository': {'nameWithOwner':repository}}, 'status': {'name':'Merged'}})
        self.data.setdefault('releaseClosers',{})[str(number)] = [{'__typename':'ClosedEvent','closer': {'__typename':'PullRequest',
            'number':number+100,'merged':True,'repository': {'nameWithOwner':repository},'mergeCommit': {'oid':commit}}}]

    def test_release_scope_boundary_references(self):
        self.assertEqual([i['id'] for i in self.scope('(#12), #13.\n')['issues']],['12','13'])

    def test_release_scope_negative_references(self):
        self.assertEqual([i['id'] for i in self.scope('thing#12 and #0; ship #13\n')['issues']],['13'])
        result=self.scope('no issue references\n',success=False)
        self.assertIn('CHANGELOG_NO_ISSUES_FOUND',result.stderr)

    def test_release_scope_multiple_references_deduplicated(self):
        self.assertEqual([i['id'] for i in self.scope('#12 #13 #12\n')['issues']],['12','13'])

    def test_release_scope_exact_version_section(self):
        projection=self.scope('#12\n\n## [1.2.30] - 2026-10-11\n#13\n')
        self.assertEqual([i['id'] for i in projection['issues']],['12'])
        self.scope('#12\n',version='v1.2.4',success=False)

    def test_release_scope_omitted_unshipped_item_excluded(self):
        self.command(['git','checkout','-qb','develop-other'])
        (self.repo/'other.txt').write_text('other\n')
        self.command(['git','add','other.txt']);self.command(['git','commit','-qm','unshipped'])
        unshipped=self.command(['git','rev-parse','HEAD']).stdout.strip()
        self.command(['git','checkout','-q','feature/12-item'])
        self.candidate(13,unshipped)
        self.assertEqual([i['id'] for i in self.scope()['issues']],['12'])

    def test_release_scope_prepublication_includes_omitted_shipped(self):
        self.candidate(13,self.head)
        self.candidate(99,self.head,repository='org/other')
        projection=self.scope()
        self.assertEqual([i['id'] for i in projection['issues']],['12','13'])
        events=json.loads(self.fixture.read_text())['events']
        self.assertFalse(any(len(e)>1 and '/releases/' in e[1] for e in events))
        self.assertEqual(self.command(['git','tag','--list']).stdout,'')
        self.assertTrue(self.command(['git','branch','--list','feature/12-item']).stdout.strip())
        self.assertFalse((self.repo/'.git/component-release-cleanup-locks').exists())
        self.assertTrue(all(i['releaseStamp'] and i['tracker'] and i['status']=='Released' for i in projection['issues']))

    def test_release_scope_manual_close_uses_merged_cross_reference(self):
        self.candidate(13,self.head)
        pr=self.data['releaseClosers']['13'][0]['closer']
        self.data['releaseClosers']['13']=[{'__typename':'ClosedEvent','closer':None},
            {'__typename':'CrossReferencedEvent','source':pr}]
        self.assertEqual([i['id'] for i in self.scope()['issues']],['12','13'])

    def test_release_scope_cross_reference_missing_merge_refuses_then_restores(self):
        self.candidate(13,self.head)
        pr=self.data['releaseClosers']['13'][0]['closer']
        self.data['releaseClosers']['13']=[{'__typename':'CrossReferencedEvent','source':pr}]
        pr['mergeCommit']=None
        self.scope(success=False)
        pr['mergeCommit']={'oid':self.head}
        self.assertEqual([i['id'] for i in self.scope('- Shipped #12 again.\n')['issues']],['12','13'])

    def test_release_scope_sibling_product_excluded_unknown_owner_refused(self):
        self.candidate(13,'f'*40)
        closer=self.data['releaseClosers']['13'][0]['closer']
        closer['repository']['nameWithOwner']='org/other-product'
        self.assertEqual([i['id'] for i in self.scope()['issues']],['12'])
        closer['repository']=None
        self.scope('- Unknown owning PR for #12.\n',success=False)
        closer['repository']={'nameWithOwner':'org/other-product'}
        self.data['releaseClosers']['13'].append({'__typename':'CrossReferencedEvent','source':dict(
            __typename='PullRequest',merged=True,repository={'nameWithOwner':'org/repo'},
            mergeCommit={'oid':self.head})})
        self.assertEqual([i['id'] for i in self.scope('- Known selected-product reference #12.\n')['issues']],['12','13'])
        tree=self.command(['git','rev-parse','HEAD^{tree}']).stdout.strip()
        outside=subprocess.run(['git','commit-tree',tree],cwd=self.repo,input='unshipped reference\n',
            text=True,capture_output=True,check=True).stdout.strip()
        selected=self.data['releaseClosers']['13'][-1]['source']
        self.data['releaseClosers']['13'].append({'__typename':'CrossReferencedEvent',
            'source':dict(selected,mergeCommit={'oid':outside})})
        refused=self.scope('- Ambiguous selected-product membership #12.\n',success=False)
        self.assertIn('release candidate membership ambiguous',refused.stderr)
        self.data['releaseClosers']['13'].pop()
        self.assertEqual([i['id'] for i in self.scope('- Restored known membership #12.\n')['issues']],['12','13'])

    def test_release_scope_exhausts_project_pages_before_freezing_scope(self):
        self.candidate(13,self.head)
        self.data['releaseProjectPages']={
            'first':{'nodes':[],'pageInfo':{'hasNextPage':True,'endCursor':'second'}},
            'second':{'nodes':self.data['releaseProjectItems'],'pageInfo':{'hasNextPage':False,'endCursor':None}}}
        projection=self.scope()
        self.assertEqual([i['id'] for i in projection['issues']],['12','13'])

    def test_release_scope_unknown_response_defers(self):
        self.data['scopeOutage']=True
        self.scope(success=False)
        self.data.pop('scopeOutage');self.data['releaseProjectPage']={'nodes':[],'pageInfo':{}}
        result=self.scope('- Second attempt #12\n',success=False)
        self.assertIn('malformed release scope page',result.stderr)
        events=json.loads(self.fixture.read_text())['events']
        self.assertNotIn(['pr','merge'],events)

    def test_release_scope_missing_closer_and_cursor_cycle_refuse(self):
        self.candidate(13,self.head);self.data['releaseClosers']['13']=[]
        self.scope(success=False)
        self.data['releaseProjectPage']={'nodes':[],'pageInfo':{'hasNextPage':True,'endCursor':'same'}}
        result=self.scope('- Changed #12\n',success=False)
        self.assertIn('cursor unavailable or repeated',result.stderr)

    def test_release_scope_uses_reviewed_commit_with_dirty_changelog(self):
        projection=self.scope()
        (self.repo/'CHANGELOG.md').write_text('## [1.2.3]\n#99\n')
        result=self.command(['bash',str(self.scripts/'prepare-release-post-merge-cleanup.sh'),'v1.2.3',
            '--inspect-targets','--release-head',self.release_head],self.env)
        self.assertEqual(json.loads(result.stdout),projection)


class ReleasePair(unittest.TestCase):
    command = Composed.command
    helper = Composed.helper
    candidate = ReleaseScope.candidate

    def setUp(self):
        ReleaseScope.setUp(self)
        self.command(['git','branch','-m','release/v1.2.3'])
        (self.repo/'CHANGELOG.md').write_text('# Changes\n\n## [1.2.3] - 2026-10-10\n- Shipped #12, #13 (ENG-12, ENG-13).\n')
        self.command(['git','add','CHANGELOG.md','.ai-dev-workflow.yaml'])
        self.command(['git','commit','-qm','reviewed release'])
        self.head = self.command(['git','rev-parse','HEAD']).stdout.strip()
        self.command(['git','push','-q','origin','release/v1.2.3'])
        base = self.command(['git','rev-parse','develop']).stdout.strip()
        tree = self.command(['git','rev-parse','HEAD^{tree}']).stdout.strip()
        self.commits = {}
        self.data.update(releaseMode=True, gitCommits={})
        for number, target_base in ((12,'main'),(13,'develop')):
            merged = subprocess.run(['git','commit-tree',tree,'-p',base,'-p',self.head],cwd=self.repo,
                input='release merge '+str(number)+'\n',text=True,capture_output=True,check=True).stdout.strip()
            self.commits[number] = merged
            self.data['gitCommits'][merged] = {'sha':merged,'parents':[{'sha':base},{'sha':self.head}]}
            self.data['prs'][str(number)] = dict(number=number,state='OPEN',headRefName='release/v1.2.3',
                headRefOid=self.head,baseRefName=target_base,isInMergeQueue=False,autoMergeRequest=None,
                fixtureMergeCommit=merged)
        self.save()

    def save(self):
        self.fixture.write_text(json.dumps(self.data))

    def reload(self):
        self.data = json.loads(self.fixture.read_text())

    def begin(self, **changes):
        declaration = dict(ownerRoot=str(self.repo),releasePair=dict(version='v1.2.3',productionPr=12,backportPr=13),
            prs=[dict(repo='org/repo',pr=n,head=self.head,base=b,root=str(self.repo),
                phases=['merge_api','cleanup'],policySkipped=['remote_delete','local_cleanup'])
                for n,b in ((12,'main'),(13,'develop'))])
        declaration.update(changes)
        path = self.root/'1941-pair.json';path.write_text(json.dumps(declaration))
        result = self.helper('begin','--input',path,success=False)
        value = json.loads(result.stdout)
        self.session = value['session']
        return value

    def step(self, number, phase, *, key=None, issue=None, status=None, argv=('true',), success=True):
        args = ['run-step','--session',self.session,'--repo','org/repo','--pr',number,
                '--phase',phase,'--step',key or phase]
        if issue is not None:
            args += ['--issue',issue]
        if status is not None:
            args += ['--status',status]
        return self.helper(*args,'--',*argv,success=success)

    def merge(self, number, success=True, method='--merge'):
        return self.step(number,'merge_api',argv=('gh','pr','merge',str(number),'--repo','org/repo',method,
            '--match-head-commit',self.head),success=success)

    def published(self):
        self.reload()
        self.data.update(releaseTag={'ref':'refs/tags/v1.2.3','object':{'type':'commit','sha':self.commits[12]}},
            releasePublication={'id':1941,'tag_name':'v1.2.3','draft':False,'published_at':'2020-01-01T00:00:00Z'})
        self.save()

    def both(self):
        self.assertEqual(self.begin()['outcome'],'Admitted')
        self.merge(12);self.step(12,'merge_verify');self.published();self.step(12,'publication')
        self.merge(13);self.step(13,'merge_verify')

    def cleanup(self, success=True, extra=(), release_input='v1.2.3'):
        result=subprocess.run(['bash',str(self.scripts/'prepare-release-post-merge-cleanup.sh'),release_input,
            '--merge-session',self.session,'--json',*extra],cwd=self.repo,env=self.env,text=True,capture_output=True)
        if success:
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        else:
            self.assertNotEqual(result.returncode,0,result.stdout+result.stderr)
        return result

    def test_release_pair_freezes_complete_duties_before_publication(self):
        self.candidate(14,self.head);self.save()
        value=self.begin();self.assertEqual(value['outcome'],'Admitted')
        state=json.loads(Path(self.session).read_text())
        self.assertEqual(state['prs'][0]['issues'],[])
        self.assertEqual([i['id'] for i in state['prs'][1]['issues']],['12','13','14'])
        self.assertFalse(any(s['phase']=='policy_skip' for s in state['prs'][0]['steps'].values()))
        self.assertEqual(sum(s['phase']=='release_stamp' for s in state['prs'][1]['steps'].values()),3)
        events=json.loads(self.fixture.read_text())['events']
        self.assertNotIn(['pr','merge'],events)
        self.assertFalse(any('/releases/' in e[1] for e in events if len(e)>1))

    def test_release_pair_deferred_final_audit_requires_cleanup_and_readback(self):
        prs=[dict(repo='org/repo',pr=n,head=self.head,base=b,root=str(self.repo),
            steps=[dict(id=phase,phase=phase) for phase in ('merge_api','merge_verify','cleanup')],
            policySkipped=['remote_delete','local_cleanup']) for n,b in ((12,'main'),(13,'develop'))]
        prs[0]['steps'].append(dict(id='audit:final',phase='audit',auditRepo='org/repo',
            auditTarget=900,marker='<!-- release-final -->',deferUntilPairCleanup=True))
        self.assertEqual(self.begin(prs=prs)['outcome'],'Admitted')
        body=self.root/'release-final-audit.md';body.write_text('<!-- release-final --> verified paired release')
        argv=['run-step','--session',self.session,'--repo','org/repo','--pr',12,
            '--phase','audit','--step','audit:final','--expected-file',body,'--',
            'gh','api','repos/org/repo/issues/900/comments','-X','POST','-f','body='+body.read_text()]
        refused=self.helper(*argv,success=False)
        self.assertNotEqual(refused.returncode,0)
        self.assertIn('final release audit requires shared cleanup',refused.stderr)
        self.reload();self.assertEqual(self.data.get('commentMutationCount',0),0)
        self.assertEqual(json.loads(Path(self.session).read_text())['prs'][0]['steps']['audit:final']['status'],'pending')
        self.helper('resume','--session',self.session)
        self.merge(12);self.step(12,'merge_verify');self.published();self.step(12,'publication')
        self.merge(13);self.step(13,'merge_verify')
        self.reload();self.data['trackerStatuses']={'12':'Merged','13':'Merged'};self.save()
        self.cleanup()
        self.assertNotEqual(json.loads(self.helper('report','--session',self.session,'--final',success=False).stdout)['outcome'],'Completed')
        self.reload();self.data['commentReadOutage']=True;self.save()
        failed=self.helper(*argv,success=False)
        self.assertNotEqual(failed.returncode,0)
        self.reload();self.assertEqual(self.data['commentMutationCount'],1)
        self.assertEqual(self.data['comments'],[{'id':1,'body':body.read_text()}])
        state=json.loads(Path(self.session).read_text())
        self.assertEqual(state['prs'][0]['steps']['audit:final']['status'],'uncertain')
        self.assertNotEqual(state['outcome'],'Completed')
        self.data['commentReadOutage']=False;self.save()
        self.helper('resume','--session',self.session)
        self.assertEqual(json.loads(self.helper('report','--session',self.session,'--final').stdout)['outcome'],'Completed')
        self.reload();self.assertEqual(self.data['commentMutationCount'],1)
        self.assertEqual(len(self.data['mergeArgv']),2)
        self.assertEqual(self.data['trackerMutationCount'],2)

    def test_release_pair_unaffordable_admits_no_prefix(self):
        self.data['quota']['remaining']=30;self.save()
        self.assertEqual(self.begin()['outcome'],'Deferred')
        self.merge(12,success=False)
        self.assertNotIn(['pr','merge'],json.loads(self.fixture.read_text())['events'])

    def test_release_pair_extra_shipped_issue_increases_complete_projection(self):
        first=self.begin()['estimate']['projectedCost']
        self.reload();self.candidate(14,self.head);self.save()
        self.assertGreater(self.begin()['estimate']['projectedCost'],first)

    def test_release_pair_projection_accounts_for_excluded_candidates_rechecks(self):
        self.begin()
        state=json.loads(Path(self.session).read_text())
        small=budget.estimate(state)['projectedCost']
        # Non-shipped Merged candidates still require membership reads on all
        # four projection boundaries, without adding an owning tracker duty.
        state['releasePair']['projection']['scopeReadCost']=400
        larger=budget.estimate(state)
        component=next(p for p in larger['components'] if p['kind']=='release_projection')
        self.assertEqual(component['weight'],1600)
        self.assertGreater(larger['projectedCost'],small)
        old_raw=larger['rawCost']-800
        old_cost=old_raw+max(50,(old_raw+1)//2)
        quota=dict(remaining=old_cost+1000+1,limit=5000,reset=int(time.time())+3600)
        with patch.object(budget,'budget',return_value=quota):
            self.assertFalse(budget.admission(state))
        self.assertEqual(state['outcome'],'Deferred')
        self.reload();self.assertNotIn(['pr','merge'],self.data['events'])

    def test_release_like_branch_without_pair_retains_ordinary_barrier(self):
        declaration=dict(ownerRoot=str(self.repo),prs=[dict(repo='org/repo',pr=n,head=self.head,
            base=b,root=str(self.repo),phases=['merge_api','cleanup'],policySkipped=['remote_delete','local_cleanup'])
            for n,b in ((12,'main'),(13,'develop'))])
        path=self.root/'1941-ordinary.json';path.write_text(json.dumps(declaration))
        self.session=json.loads(self.helper('begin','--input',path).stdout)['session']
        self.merge(12);self.step(12,'merge_verify');self.merge(13,success=False)
        self.reload();self.assertEqual(len(self.data['mergeArgv']),1)

    def test_release_pair_scope_drift_refuses_then_restored_scope_advances(self):
        self.begin();self.candidate(14,self.head);self.save()
        self.merge(12,success=False)
        self.reload();self.assertNotIn(['pr','merge'],self.data['events'])
        self.data['releaseProjectItems']=[];self.save()
        self.helper('resume','--session',self.session)
        self.merge(12)
        self.reload();self.assertEqual(len(self.data['mergeArgv']),1)

    def test_release_pair_project_binding_drift_refuses_then_restored_owner_advances(self):
        self.begin();self.reload();self.data['projectId']='different-owning-project';self.save()
        self.merge(12,success=False)
        self.reload();self.assertNotIn(['pr','merge'],self.data['events'])
        self.data['projectId']='project';self.save()
        self.helper('resume','--session',self.session);self.merge(12)

    def test_release_pair_annotated_tag_dereferences_to_production_commit(self):
        self.begin();self.merge(12);self.step(12,'merge_verify');self.published()
        annotation='a'*40
        self.data['releaseTag']={'ref':'refs/tags/v1.2.3','object':{'type':'tag','sha':annotation}}
        self.data['tagObjects']={annotation:{'sha':annotation,'object':{'type':'commit','sha':self.commits[12]}}};self.save()
        self.step(12,'publication');self.merge(13)

    def test_release_pair_rejects_mismatched_head_and_version(self):
        self.data['prs']['13']['headRefOid']='f'*40;self.save()
        self.assertEqual(self.begin()['outcome'],'Deferred')
        self.data['prs']['13']['headRefOid']=self.head;self.save()
        self.assertEqual(self.begin(releasePair=dict(version='v9.9.9',productionPr=12,backportPr=13))['outcome'],'Deferred')
        self.data['prs']['13']['state']='CLOSED';self.save()
        self.assertEqual(self.begin()['outcome'],'Deferred')
        self.data['prs']['13']['state']='OPEN';self.save()
        self.assertEqual(self.begin()['outcome'],'Admitted')

    def test_release_pair_requires_regular_executor_and_preserves_branch(self):
        self.begin();result=self.merge(12,success=False,method='--squash')
        self.assertIn('requires unchanged regular-merge argv',result.stderr)
        self.assertNotIn(['pr','merge'],json.loads(self.fixture.read_text())['events'])
        self.assertTrue(self.command(['git','ls-remote','origin','refs/heads/release/v1.2.3']).stdout)
        self.helper('resume','--session',self.session)
        result=self.step(12,'merge_api',argv=('gh','pr','merge','12','--repo','org/foreign','--merge',
            '--match-head-commit',self.head),success=False)
        self.assertIn('exact frozen repository',result.stderr)
        self.helper('resume','--session',self.session);self.merge(12)

    def test_release_pair_boolean_and_alias_guards_refuse_before_mutation(self):
        self.begin()
        prefix=('gh','pr','merge','12','--repo','org/repo','--match-head-commit',self.head)
        for flags in (('--merge','--delete-branch=true'),
                      ('--merge','--merge=false','--squash=true'),
                      ('--merge','-d=true'), ('--merge','-rs'),
                      ('--merge','--squash=false')):
            with self.subTest(flags=flags):
                result=self.step(12,'merge_api',argv=prefix+flags,success=False)
                self.assertIn('requires unchanged regular-merge argv',result.stderr)
                self.reload();self.assertNotIn(['pr','merge'],self.data['events'])
                self.assertEqual(self.data['prs']['12']['state'],'OPEN')
                self.assertTrue(self.command(['git','ls-remote','origin','refs/heads/release/v1.2.3']).stdout)
                self.helper('resume','--session',self.session)
        permitted=prefix+('--merge=true','--admin=false','--auto=false','--subject','literal --delete-branch=true')
        self.step(12,'merge_api',argv=permitted)
        self.reload();self.assertEqual(self.data['mergeArgv'],[list(permitted[1:])])
        self.assertTrue(self.command(['git','ls-remote','origin','refs/heads/release/v1.2.3']).stdout)

    def test_release_pair_publication_precedes_backport_and_shared_cleanup(self):
        self.begin();self.merge(12);self.step(12,'merge_verify')
        self.merge(13,success=False)
        self.reload();self.assertEqual(len(self.data.get('mergeArgv',[])),1)
        self.assertEqual(self.data['prs']['13']['state'],'OPEN')
        self.published();self.helper('resume','--session',self.session)
        self.step(12,'publication');self.merge(13);self.step(13,'merge_verify')
        self.step(13,'cleanup',success=False)
        self.reload();self.assertNotIn(['issue','close'],self.data['events'])

    def test_release_pair_tag_and_draft_proofs_refuse_backport(self):
        self.begin();self.merge(12);self.step(12,'merge_verify');self.published()
        self.data['releaseTag']['object']['sha']=self.head;self.save()
        self.step(12,'publication',success=False)
        self.published();self.data['releasePublication']['draft']=True;self.save()
        self.helper('resume','--session',self.session)
        self.step(12,'publication',success=False)
        self.reload();self.assertEqual(len(self.data['mergeArgv']),1)
        self.published();self.helper('resume','--session',self.session)
        self.merge(13)
        self.reload();self.assertEqual(len(self.data['mergeArgv']),2)

    def test_release_pair_regular_merge_parent_is_independent_proof(self):
        self.begin();self.merge(12)
        self.reload();self.data['gitCommits'][self.commits[12]]['parents']=[{'sha':self.head}];self.save()
        self.helper('resume','--session',self.session,success=False)
        self.reload();self.assertEqual(len(self.data['mergeArgv']),1)

    def test_release_pair_known_queue_waits_without_duplicate_submission(self):
        self.data['prs']['12']['isInMergeQueue']=True;self.save()
        self.assertEqual(self.begin()['outcome'],'Waiting')
        self.merge(12,success=False)
        self.assertNotIn(['pr','merge'],json.loads(self.fixture.read_text())['events'])

    def test_release_pair_completed_requires_live_stamps_tracker_marker_and_both_cleanup(self):
        self.both();self.reload()
        self.data['issueMilestones']={n:{'number':1,'title':'v1.2.3'} for n in ('12','13')}
        self.data['trackerStatuses']={n:'Released' for n in ('12','13')}
        self.data['milestones']=[{'number':1,'title':'v1.2.3','state':'closed'}];self.save()
        for issue in ('12','13'):
            self.step(13,'release_stamp',key='release_stamp:'+issue,issue=issue,status='v1.2.3')
            self.step(13,'tracker',key='tracker:'+issue+':pre',issue=issue,status='Released')
        self.step(13,'release_finalize')
        for phase in ('remote_delete','local_cleanup'):
            self.step(13,'policy_skip',key=phase)
        self.step(13,'cleanup');self.step(12,'cleanup')
        report=json.loads(self.helper('report','--session',self.session,'--final').stdout)
        self.assertEqual(report['outcome'],'Completed')
        self.reload();self.data['issueMilestones']['13']=None;self.save()
        result=self.helper('resume','--session',self.session,success=False)
        self.assertNotEqual(json.loads(result.stdout)['outcome'],'Completed')

    def test_release_pair_actual_cleanup_runs_owned_helpers_and_emits_single_json(self):
        # On macOS this exercises the declared Bash 3.2 runtime, including an
        # empty issue-argument array at the session cleanup entrypoint.
        (self.bin/'bash').symlink_to('/bin/bash')
        self.both();self.reload();self.data['trackerStatuses']={'12':'Merged','13':'Merged'};self.save()
        result=self.cleanup()
        self.assertEqual(json.loads(result.stdout)['outcome'],'Completed')
        self.reload()
        self.assertEqual(self.data['stampMutationCount'],{'12':1,'13':1})
        self.assertEqual(self.data['trackerMutationCount'],2)
        self.assertEqual(self.data['finalizeMutationCount'],1)
        self.assertEqual(self.data['trackerStatuses'],{'12':'Released','13':'Released'})
        self.assertTrue(self.command(['git','branch','--list','release/v1.2.3']).stdout)
        self.assertTrue(self.command(['git','ls-remote','origin','refs/heads/release/v1.2.3']).stdout)

    def test_release_pair_recovery_reads_frozen_project_despite_config_drift(self):
        self.both();self.reload();self.data['trackerStatuses']={'12':'Merged','13':'Merged'};self.save()
        self.cleanup()
        self.reload();self.data['projectId']='different-project'
        self.data['projectCards']={n:[{'project':{'id':'different-project'},'status':{'name':'Released'}},
            {'project':{'id':'project'},'status':{'name':'Merged'}}] for n in ('12','13')}
        self.save();self.env['GITHUB_PROJECT_NUMBER']='2'
        refused=json.loads(self.helper('resume','--session',self.session,success=False).stdout)
        self.assertEqual(refused['outcome'],'Deferred')
        self.reload();self.assertEqual(self.data['trackerMutationCount'],2)
        self.assertEqual(len(self.data['mergeArgv']),2)
        for cards in self.data['projectCards'].values():
            cards[1]['status']['name']='Released'
        self.save()
        restored=json.loads(self.helper('resume','--session',self.session).stdout)
        self.assertEqual(restored['outcome'],'Completed')
        self.reload();self.assertEqual(self.data['trackerMutationCount'],2)
        self.assertEqual(len(self.data['mergeArgv']),2)

    def test_release_pair_cross_repository_veto_preserves_unrelated_origin_branch(self):
        self.data['fork']=None;self.save()
        # A same-named origin branch has unrelated work beyond the fork PR head.
        tree=self.command(['git','rev-parse','HEAD^{tree}']).stdout.strip()
        unrelated=subprocess.run(['git','commit-tree',tree,'-p',self.head],cwd=self.repo,
            input='unrelated origin work\n',text=True,capture_output=True,check=True).stdout.strip()
        self.command(['git','push','-q','origin',unrelated+':refs/heads/release/v1.2.3'])
        prs=[dict(repo='org/repo',pr=n,head=self.head,base=b,root=str(self.repo),
            phases=['merge_api','cleanup'],policySkipped=['local_cleanup']) for n,b in ((12,'main'),(13,'develop'))]
        self.assertEqual(self.begin(prs=prs)['outcome'],'Deferred')
        self.reload();self.assertNotIn(['pr','merge'],self.data['events'])
        self.data['fork']=True;self.save()
        self.assertEqual(self.begin(prs=prs)['outcome'],'Admitted')
        state=json.loads(Path(self.session).read_text())
        self.assertTrue(all(p['remoteCleanup'] is False for p in state['prs']))
        self.assertTrue(all(p['releaseRemoteOwned'] is False for p in state['prs']))
        self.assertFalse(any(s['phase']=='remote_delete' for p in state['prs'] for s in p['steps'].values()))
        self.merge(12);self.step(12,'merge_verify');self.published();self.step(12,'publication')
        self.merge(13);self.step(13,'merge_verify')
        self.reload();self.data['trackerStatuses']={'12':'Merged','13':'Merged'};self.save()
        self.assertEqual(json.loads(self.cleanup().stdout)['outcome'],'Completed')
        remote=self.command(['git','ls-remote','origin','refs/heads/release/v1.2.3']).stdout
        self.assertEqual(remote.split()[0],unrelated)
        self.helper('resume','--session',self.session)
        self.assertEqual(self.command(['git','ls-remote','origin','refs/heads/release/v1.2.3']).stdout,remote)
        self.reload();self.assertEqual(len(self.data['mergeArgv']),2)
        self.assertEqual(self.data['trackerMutationCount'],2)

    def test_release_pair_authorized_fixture_branch_cleanup_after_both_merges(self):
        prs=[dict(repo='org/repo',pr=n,head=self.head,base=b,root=str(self.repo),
            phases=['merge_api','cleanup']) for n,b in ((12,'main'),(13,'develop'))]
        self.assertEqual(self.begin(prs=prs)['outcome'],'Admitted')
        self.merge(12);self.step(12,'merge_verify');self.published();self.step(12,'publication')
        self.merge(13);self.step(13,'merge_verify')
        self.command(['git','push','-q','origin',self.commits[12]+':refs/heads/main',self.commits[13]+':refs/heads/develop'])
        self.reload();self.data['trackerStatuses']={'12':'Merged','13':'Merged'};self.save()
        self.cleanup()
        self.assertEqual(self.command(['git','branch','--list','release/v1.2.3']).stdout,'')
        self.assertEqual(self.command(['git','ls-remote','origin','refs/heads/release/v1.2.3']).stdout,'')
        self.reload();self.assertEqual(len(self.data['mergeArgv']),2)

    def test_release_pair_authorized_linked_cleanup_reuses_occupied_base(self):
        main=self.repo
        self.command(['git','switch','-q','develop'])
        linked=self.root/'release-linked'
        self.command(['git','worktree','add','-q',str(linked),'release/v1.2.3'])
        shutil.copytree(self.scripts,linked/'scripts/development-workflow')
        # Fixture helpers are deliberately untracked in both checkouts.
        (main/'.git/info/exclude').write_text('/scripts/\n')
        self.repo=linked;self.scripts=linked/'scripts/development-workflow'
        prs=[dict(repo='org/repo',pr=n,head=self.head,base=b,root=str(linked),
            phases=['merge_api','cleanup']) for n,b in ((12,'main'),(13,'develop'))]
        self.assertEqual(self.begin(prs=prs)['outcome'],'Admitted')
        self.merge(12);self.step(12,'merge_verify');self.published();self.step(12,'publication')
        self.merge(13);self.step(13,'merge_verify')
        self.command(['git','push','-q','origin',self.commits[12]+':refs/heads/main',self.commits[13]+':refs/heads/develop'])
        self.command(['git','switch','-q','--detach',self.head])
        self.reload();self.data['trackerStatuses']={'12':'Merged','13':'Merged'};self.save()
        (main/'base.txt').write_text('retained caller changes\n')
        self.cleanup(success=False)
        self.reload();self.assertEqual(self.data.get('trackerMutationCount',0),0)
        self.assertEqual(self.data.get('stampMutationCount',{}),{})
        self.assertEqual(self.data.get('milestones',[]),[])
        self.assertEqual((main/'base.txt').read_text(),'retained caller changes\n')
        self.assertTrue(self.command(['git','branch','--list','release/v1.2.3']).stdout)
        (main/'base.txt').write_text('base\n')
        self.helper('resume','--session',self.session)
        self.cleanup()
        self.assertTrue(main.is_dir() and linked.is_dir())
        self.assertEqual(self.command(['git','branch','--show-current']).stdout,'')
        self.assertEqual(subprocess.check_output(['git','-C',str(main),'branch','--show-current'],text=True).strip(),'develop')
        self.assertEqual(self.command(['git','branch','--list','release/v1.2.3']).stdout,'')
        self.assertEqual(self.command(['git','ls-remote','origin','refs/heads/release/v1.2.3']).stdout,'')
        self.assertEqual(self.command(['git','rev-parse','HEAD']).stdout.strip(),self.commits[13])
        self.reload();self.assertEqual(self.data['trackerMutationCount'],2)
        self.assertEqual(len(self.data['mergeArgv']),2)

    def test_release_pair_provider_duties_require_verified_branch_cleanup(self):
        self.both()
        self.reload();self.data['trackerStatuses']={'12':'Merged','13':'Merged'};self.save()
        for phase,key,issue,status,function,values in [
            ('release_stamp','release_stamp:12','12','v1.2.3','record_release_for_issue_best_effort',['12','v1.2.3']),
            ('tracker','tracker:12:pre','12','Released','update_tracker_status_best_effort',['12','Released','Merged']),
            ('release_finalize','release_finalize',None,None,'finalize_release_marker_best_effort',['v1.2.3'])]:
            argv=['bash','-c','set -e; source "$1/workflow-lib.sh"; cd "$2"; shift 2; '+function+' "$@"',
                'plant-provider',str(self.scripts),str(self.repo),*values]
            refused=self.step(13,phase,key=key,issue=issue,status=status,argv=argv,success=False)
            self.assertNotEqual(refused.returncode,0)
            self.assertIn('verified product branch cleanup/retention required before release reconciliation',refused.stderr)
            self.reload();self.assertEqual(self.data.get('trackerMutationCount',0),0)
            self.assertEqual(self.data.get('stampMutationCount',{}),{})
            self.assertEqual(self.data.get('milestones',[]),[])
            self.helper('resume','--session',self.session)
        self.cleanup()
        self.assertEqual(json.loads(self.helper('report','--session',self.session,'--final').stdout)['outcome'],'Completed')
        self.reload();self.assertEqual(self.data['trackerMutationCount'],2)
        self.assertEqual(self.data['stampMutationCount'],{'12':1,'13':1})
        self.assertTrue(any(m['title']=='v1.2.3' and m['state']=='closed' for m in self.data['milestones']))

    def test_release_pair_main_owner_projects_selected_linked_checkout(self):
        main=self.repo
        self.command(['git','switch','-q','develop'])
        linked=self.root/'release-selected-linked'
        self.command(['git','worktree','add','-q',str(linked),'release/v1.2.3'])
        shutil.copyfile(linked/'.ai-dev-workflow.yaml',main/'.ai-dev-workflow.yaml')
        refused=subprocess.run(['bash',str(self.scripts/'prepare-release-post-merge-cleanup.sh'),
            'v1.2.3','--target-root',str(linked)],cwd=main,env=self.env,text=True,capture_output=True)
        self.assertNotEqual(refused.returncode,0)
        self.assertIn('only supported for read-only --inspect-targets',refused.stderr)
        self.reload();self.assertNotIn(['pr','merge'],self.data['events'])
        prs=[dict(repo='org/repo',pr=n,head=self.head,base=b,root=str(linked),
            phases=['merge_api','cleanup'],policySkipped=['remote_delete','local_cleanup'])
            for n,b in ((12,'main'),(13,'develop'))]
        self.assertEqual(self.begin(prs=prs)['outcome'],'Admitted')
        state=json.loads(Path(self.session).read_text())
        self.assertEqual(state['ownerRoot'],str(main))
        self.assertEqual(state['releasePair']['projection']['root'],str(linked))
        self.assertEqual(state['releasePair']['projection']['markerProvider'],'github_projects')
        self.assertEqual([i['id'] for i in state['prs'][1]['issues']],['12','13'])
        self.merge(12);self.step(12,'merge_verify');self.published();self.step(12,'publication')
        self.merge(13);self.step(13,'merge_verify')
        self.reload();self.data['trackerStatuses']={'12':'Merged','13':'Merged'};self.save()
        self.cleanup()
        self.assertEqual(json.loads(self.helper('report','--session',self.session,'--final').stdout)['outcome'],'Completed')
        self.helper('resume','--session',self.session)
        self.reload();self.assertEqual(len(self.data['mergeArgv']),2)
        self.assertEqual(self.data['trackerMutationCount'],2)
        self.assertEqual(self.command(['git','branch','--show-current']).stdout.strip(),'develop')
        self.assertEqual(subprocess.check_output(['git','-C',str(linked),'branch','--show-current'],text=True).strip(),'release/v1.2.3')
        self.assertTrue(self.command(['git','ls-remote','origin','refs/heads/release/v1.2.3']).stdout)

    def test_release_pair_linear_stamp_bridge_preserves_deferred_work(self):
        (self.repo/'.ai-dev-workflow.yaml').write_text('issue_tracker:\n  provider: linear\n  custom_fields:\n    release_field: Release\n')
        self.both()
        self.cleanup(success=False)
        state=json.loads(Path(self.session).read_text())
        stamp=state['prs'][1]['steps']['release_stamp:ENG-12']
        self.assertEqual(stamp['status'],'uncertain')
        self.assertEqual(state['releasePair']['projection']['linearMarker'],{'kind':'field','name':'Release','value':'v1.2.3'})
        proof=self.root/'1941-linear-stamp-proof.json'
        evidence=dict(provider='linear',repo='org/repo',issue='ENG-12',releaseVersion='v1.2.3',
            releaseMarker={'kind':'field','name':'Release','value':'v1.2.3'},markerId='field-id',
            mutationRequestId='stamp-mutation',readRequestId='stamp-read',observedAt=stamp['intentAt'])
        proof.write_text(json.dumps(evidence))
        self.helper('record-provider-result','--session',self.session,'--repo','org/repo','--pr',13,
            '--phase','release_stamp','--step','release_stamp:ENG-12','--issue','ENG-12','--evidence',proof,success=False)
        evidence['observedAt']=budget.now();proof.write_text(json.dumps(evidence))
        self.helper('record-provider-result','--session',self.session,'--repo','org/repo','--pr',13,
            '--phase','release_stamp','--step','release_stamp:ENG-12','--issue','ENG-12','--evidence',proof)
        state=json.loads(Path(self.session).read_text())
        self.assertEqual(state['prs'][1]['steps']['release_stamp:ENG-12']['status'],'completed')
        self.assertNotEqual(state['outcome'],'Completed')
        self.reload();self.assertNotIn(['issue','close'],self.data['events'])

    def test_release_pair_component_linked_checkout_keeps_hub_tracker_ownership(self):
        self.component_linked_checkout_keeps_hub_tracker_ownership('v1.2.3')

    def test_release_pair_component_unprefixed_version_preserves_contract_and_cleanup(self):
        self.component_linked_checkout_keeps_hub_tracker_ownership('1.2.3')

    def component_linked_checkout_keeps_hub_tracker_ownership(self, version):
        hub=self.root/'hub';hub.mkdir()
        subprocess.run(['git','init','-q','-b','develop',str(hub)],check=True)
        scripts=hub/'scripts/development-workflow';shutil.copytree(self.scripts,scripts)
        shutil.copyfile(self.source/'component-release-target.sh',scripts/'component-release-target.sh')
        (scripts/'component-release-target.sh').chmod(0o700)
        branch='product/release/'+version
        self.command(['git','branch','-m',branch]);self.command(['git','push','-q','origin',branch])
        for pr in self.data['prs'].values():
            pr['headRefName']=branch
        self.command(['git','switch','-q','develop'])
        linked=self.root/'product-linked'
        self.command(['git','worktree','add','-q',str(linked),branch])
        (hub/'.ai-dev-workflow.yaml').write_text('schema_version: 2\nmode: workflow_hub\nissue_tracker:\n  provider: github_projects\n  project_number: 1\nworkflow_hub:\n  product_repos:\n    - name: product\n      github_repo: org/repo\n      default_branch: develop\n      release:\n        base: develop\n        branch_pattern: "{product_repo}/release/v{version}"\n        changelog_owner: product_repo\n        tag_owner: product_repo\n        github_release_owner: product_repo\n        deployment_evidence_owner: product_repo\n        cleanup_evidence_owner: product_repo\n        tracker_reconciliation_owner: hub\n')
        if not version.startswith('v'):
            config=hub/'.ai-dev-workflow.yaml'
            config.write_text(config.read_text().replace('/release/v{version}', '/release/{version}'))
        (hub/'.ai-dev-workflow.local.yaml').write_text('product_repos:\n  - name: product\n    local_path: "'+str(linked)+'"\n')
        # Preserve the configured component prefix and the existing opaque tag.
        self.data['checkoutRepos']={str(hub):'org/hub',str(linked):'org/repo',str(self.repo):'org/repo'}
        self.candidate(14,self.head,repository='org/hub')
        pr=self.data['releaseClosers']['14'][0]['closer'];pr['repository']['nameWithOwner']='org/repo'
        self.data['releaseClosers']['14']=[{'__typename':'CrossReferencedEvent','source':pr}]
        self.candidate(15,'f'*40,repository='org/hub')
        self.data['releaseClosers']['15'][0]['closer']['repository']['nameWithOwner']='org/other-product'
        self.save()
        target=subprocess.run(['bash',str(scripts/'component-release-target.sh'),'--repo-root',str(hub),
            '--repo','product','--release-branch',branch,'--json'],cwd=hub,env=self.env,
            text=True,capture_output=True,check=True)
        evidence=hub/'component.json'
        evidence.write_text(json.dumps(dict(schema_version='component_release_evidence.v1',target_binding=json.loads(target.stdout),
            release_branch=branch,release_outcome='completed',ci_outcome='passed',deployment_outcome='recorded',
            cleanup_outcome='not_started',component_tag='product-v1.2.3')))
        refused=subprocess.run(['bash',str(scripts/'prepare-release-post-merge-cleanup.sh'),branch,
            '--repo-root',str(hub),'--repo','product','--evidence-file',str(evidence),
            '--inspect-targets','--release-head',self.head,'--target-root',str(self.repo)],
            cwd=hub,env=self.env,text=True,capture_output=True)
        self.assertEqual(refused.returncode,2,refused.stdout+refused.stderr)
        self.assertIn('--target-root differs from the resolved component checkout.',refused.stderr)
        self.reload();self.assertNotIn(['pr','merge'],self.data['events'])
        self.assertNotIn('trackerMutationCount',self.data)
        self.assertNotIn('stampMutationCount',self.data)
        manifest=hub/'pair.json';manifest.write_text(json.dumps(dict(ownerRoot=str(hub),
            releasePair=dict(version='v1.2.3',productionPr=12,backportPr=13,productRepo='product',evidenceFile=str(evidence)),
            prs=[dict(repo='org/repo',pr=n,head=self.head,base=b,root=str(linked),phases=['merge_api','cleanup'],
                policySkipped=['remote_delete','local_cleanup']) for n,b in ((12,'main'),(13,'develop'))])))
        self.repo=hub;self.scripts=scripts
        if not version.startswith('v'):
            declaration=json.loads(manifest.read_text())
            declaration['releasePair']['version']='v9.9.9';manifest.write_text(json.dumps(declaration))
            refused=json.loads(self.helper('begin','--input',manifest,success=False).stdout)
            self.assertEqual(refused['outcome'],'Deferred')
            self.reload();self.assertNotIn(['pr','merge'],self.data['events'])
            declaration['releasePair']['version']='v1.2.3';manifest.write_text(json.dumps(declaration))
        self.session=json.loads(self.helper('begin','--input',manifest).stdout)['session']
        state=json.loads(Path(self.session).read_text())
        self.assertEqual(state['outcome'],'Admitted')
        self.assertEqual(state['releasePair']['version'],version)
        self.assertEqual(state['releasePair']['projection']['version'],version)
        self.assertEqual(state['releasePair']['projection']['markerRepo'],'org/hub')
        self.assertEqual([i['id'] for i in state['prs'][1]['issues']],['12','13','14'])
        self.assertEqual(state['releasePair']['projection']['publicationTag'],'product-v1.2.3')
        self.merge(12);self.step(12,'merge_verify');self.published()
        self.data['releasePublication']['tag_name']='product-v1.2.3';self.data['releaseTag']['ref']='refs/tags/product-v1.2.3'
        self.data['trackerStatuses']={n:'Merged' for n in ('12','13','14','15')};self.save()
        self.step(12,'publication');self.merge(13);self.step(13,'merge_verify')
        self.cleanup(extra=('--repo','product','--repo-root',str(hub),'--evidence-file',str(evidence)),release_input=branch)
        self.reload();self.assertEqual(self.data['stampMutationRepos'],['org/hub']*3)
        self.assertEqual(self.data['trackerMutationRepos'],['org/hub']*3)
        self.assertEqual(self.data['trackerStatuses']['15'],'Merged')
        self.assertNotIn('15',self.data['issueMilestones'])
        self.assertTrue(all(m['title']==version for m in self.data['issueMilestones'].values()))
        self.assertTrue(any(m['title']==version and m['state']=='closed' for m in self.data['milestones']))
        self.assertTrue(linked.is_dir())

    def test_release_pair_partial_stamp_read_outage_reconciles_without_replay(self):
        self.both();self.reload();self.data.update(trackerStatuses={'12':'Merged','13':'Merged'},stampPostReadOutage='13');self.save()
        self.cleanup(success=False)
        state=json.loads(Path(self.session).read_text())
        self.assertEqual(state['outcome'],'Interrupted')
        self.assertEqual(state['prs'][1]['steps']['release_stamp:12']['status'],'completed')
        self.assertEqual(state['prs'][1]['steps']['release_stamp:13']['status'],'uncertain')
        self.reload();self.assertEqual(self.data['stampMutationCount'],{'12':1,'13':1})
        self.helper('resume','--session',self.session,success=False)
        self.reload();self.data.pop('stampReadOutage');self.data.pop('stampPostReadOutage');self.save()
        self.helper('resume','--session',self.session)
        self.cleanup()
        self.reload();self.assertEqual(self.data['stampMutationCount'],{'12':1,'13':1})
        self.assertEqual(len(self.data['mergeArgv']),2)

    def test_release_pair_recovery_at_four_boundaries_preserves_completed_merges(self):
        for boundary in ('production','publication','backport','partial_cleanup'):
            with self.subTest(boundary=boundary):
                if boundary != 'production':
                    self.doCleanups();self.setUp()
                self.begin();self.merge(12)
                if boundary != 'production':
                    self.step(12,'merge_verify');self.published();self.step(12,'publication')
                if boundary in ('backport','partial_cleanup'):
                    self.merge(13)
                if boundary == 'partial_cleanup':
                    self.reload();self.data['stampFailureOnIssue']='13';self.data['trackerStatuses']={'12':'Merged','13':'Merged'};self.save()
                    self.cleanup(success=False)
                self.reload();self.data.update(prOutage=True,quotaOutage=True);self.save()
                self.helper('resume','--session',self.session,success=False)
                state=json.loads(Path(self.session).read_text())
                self.assertEqual(state['prs'][0]['verifiedState'],'merged')
                self.reload();self.data.pop('prOutage');self.data.pop('quotaOutage');self.data.pop('stampFailureOnIssue',None);self.save()
                self.helper('resume','--session',self.session)
                if boundary == 'production':
                    self.published();self.step(12,'publication')
                if boundary in ('production','publication'):
                    self.merge(13)
                self.reload();self.data.setdefault('trackerStatuses',{'12':'Merged','13':'Merged'});self.save()
                self.cleanup()
                self.reload();self.assertEqual(len(self.data['mergeArgv']),2)
                self.assertEqual(self.data['stampMutationCount'],{'12':1,'13':1})


if __name__ == '__main__':
    unittest.main()

#!/usr/bin/env python3
"""Synthetic durability proofs; no user configuration or remote calls.

covers: scripts/development-workflow/workflow-merge-budget.py
covers: scripts/development-workflow/workflow-config-resolver.py
covers: scripts/development-workflow/workflow-project-reader.py
"""
import argparse
import ast
from contextlib import contextmanager
from concurrent.futures import ThreadPoolExecutor
import importlib.util
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import Mock, patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace('-', '_'), ROOT / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


budget = load('workflow-merge-budget')
config = load('workflow-config-resolver')
reader = load('workflow-project-reader')


class Durability(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix='workflow-durability-2005-')
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name).resolve()

    def test_required_fsync_omission_proofs(self):
        """Run failing mutants and restored passing tests only in copied fixtures."""
        cases = (
            ('workflow-merge-budget.py', 'def begin(args):', '        os.fsync(fd)\n',
             'test_workflow_durability.py', 'Durability.test_session_ancestors_are_synced_before_journal_publication'),
            ('workflow-config-resolver.py', 'def set_local_product_repo_path(', '            os.fsync(stream.fileno())\n',
             'test_workflow_durability.py', 'Durability.test_config_atomic_durable_and_private'),
            ('workflow-project-reader.py', 'def fallback(', '                os.fsync(stream.fileno())\n',
             'test_workflow_durability.py', 'Durability.test_project_cache_durable_and_readable'),
            ('sync-template-merge.py', 'def write_snapshot(',
             '            os.fsync(parent_fd)  # Persist replacement before recovery can be removed.\n',
             'test_sync_template_merge.py', 'SyncTests.test_directory_entries_are_durable_before_writes_and_recovery_cleanup'),
        )
        sources = [case[0] for case in cases] + [
            'select-sync-manifest-entries.py', 'check-sync-manifest-coverage.py']
        for index, (filename, anchor, barrier, test_file, test_name) in enumerate(cases):
            with self.subTest(script=filename):
                copied = self.root / str(index) / 'scripts/development-workflow'
                (copied / 'tests').mkdir(parents=True)
                for source in sources:
                    shutil.copyfile(ROOT / source, copied / source)
                for source in ('test_workflow_durability.py', 'test_sync_template_merge.py'):
                    shutil.copyfile(ROOT / 'tests' / source, copied / 'tests' / source)
                original = (ROOT / filename).read_bytes()
                text = original.decode()
                offset = text.index(barrier, text.index(anchor))
                line = text[:offset].count('\n') + 1
                test_source = ROOT / 'tests' / test_file
                test_line = next(node.lineno for node in ast.walk(ast.parse(test_source.read_text()))
                                 if isinstance(node, ast.FunctionDef) and node.name == test_name.split('.')[-1])
                command = [sys.executable, str(copied / 'tests' / test_file), '-v', test_name]
                indentation = barrier[:len(barrier) - len(barrier.lstrip())]
                mutant = text[:offset] + indentation + 'pass  # planted fsync omission\n' + text[offset + len(barrier):]
                target = copied / filename
                try:
                    target.write_text(mutant)
                    failed = subprocess.run(command, capture_output=True, text=True, timeout=60)
                finally:
                    target.write_bytes(original)
                self.assertEqual(target.read_bytes(), original)
                print(f'PLANTED_PROOF {filename}:{line} TEST=tests/{test_file}:{test_line}', flush=True)
                print('COMMAND=' + ' '.join(command), flush=True)
                print(f'OMITTED_FSYNC_EXPECTED_FAILURE EXIT={failed.returncode}\n' + failed.stdout + failed.stderr, flush=True)
                self.assertEqual(failed.returncode, 1, failed.stdout + failed.stderr)
                self.assertIn('FAIL: ' + test_name.split('.')[-1], failed.stderr)
                restored = subprocess.run(command, capture_output=True, text=True, timeout=60)
                print(f'RESTORED_FSYNC_EXPECTED_PASS EXIT={restored.returncode}\n' + restored.stdout + restored.stderr, flush=True)
                self.assertEqual(restored.returncode, 0, restored.stdout + restored.stderr)
                self.assertEqual((ROOT / filename).read_bytes(), original)

    @contextmanager
    def observed(self, destination, fail=None):
        events = []
        fsync, replace = os.fsync, os.replace
        parent = destination.parent.stat()

        def synced(fd):
            info = os.fstat(fd)
            kind = 'directory' if stat.S_ISDIR(info.st_mode) else 'file'
            if kind == 'directory':
                self.assertEqual((info.st_dev, info.st_ino), (parent.st_dev, parent.st_ino))
            events.append(kind)
            if fail == kind:
                raise OSError('synthetic fsync failure')
            fsync(fd)

        def replaced(src, dst, **kwargs):
            self.assertEqual(Path(dst), destination)
            self.assertEqual(Path(src).parent, destination.parent)
            self.assertEqual(events, ['file'])
            # Original remains complete until atomic publication.
            if destination.exists():
                self.assertEqual(destination.read_bytes(), b'original\n')
            self.assertEqual(stat.S_IMODE(Path(src).stat().st_mode), 0o600)
            replace(src, dst, **kwargs)
            events.append('replace')

        with patch.object(os, 'fsync', synced), patch.object(os, 'replace', replaced):
            yield events

    def test_session_ancestors_are_synced_before_journal_publication(self):
        common = self.root / '.git'
        common.mkdir()
        declaration = self.root / 'declaration.json'
        declaration.write_text(json.dumps({'ownerRoot': str(self.root), 'prs': []}))
        args = argparse.Namespace(input=str(declaration), repo_root=str(self.root), reserve=None)
        fsync, publish = os.fsync, budget.publish
        synced = []

        def observed(fd):
            fsync(fd)
            info = os.fstat(fd)
            synced.append((info.st_dev, info.st_ino))

        def published(path, state):
            expected = [common.stat(), path.parent.parent.stat()]
            self.assertEqual(synced, [(s.st_dev, s.st_ino) for s in expected])
            publish(path, state)

        with patch.object(budget, 'root', return_value=self.root), \
             patch.object(budget, 'common', return_value=common), \
             patch.object(budget, 'reserve', return_value=1000), \
             patch.object(budget, 'gh', side_effect=AssertionError('no remote calls')), \
             patch.object(os, 'fsync', observed), patch.object(budget, 'publish', published):
            for _ in range(2):  # Fresh store and existing store both persist ancestors.
                synced.clear()
                result = budget.begin(args)
                self.assertEqual(result['outcome'], 'Deferred')
                self.assertTrue(Path(result['session']).is_file())

    def test_session_state_publication_is_private(self):
        destination = self.root / 'state.json'
        for existing in (False, True):
            with self.subTest(existing=existing):
                if existing:
                    destination.write_bytes(b'original\n')
                    destination.chmod(0o640)
                with self.observed(destination) as events:
                    budget.publish(destination, {'synthetic': True})
                self.assertEqual(events, ['file', 'replace', 'directory'])
                self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o600)

    def test_session_directory_sync_failure_prevents_admission(self):
        common = self.root / '.git'
        common.mkdir()
        declaration = self.root / 'declaration.json'
        declaration.write_text('{"prs": []}')
        args = argparse.Namespace(input=str(declaration), repo_root=str(self.root), reserve=None)
        with patch.object(budget, 'root', return_value=self.root), \
             patch.object(budget, 'common', return_value=common), \
             patch.object(os, 'fsync', side_effect=OSError('synthetic sync failure')), \
             patch.object(budget, 'publish') as publish:
            with self.assertRaises(OSError):
                budget.begin(args)
            publish.assert_not_called()

    def write_config(self):
        # The supplied snapshot is fabricated; no real private config is read.
        snapshot = Mock(envelope=b'', legacy={})
        return config.set_local_product_repo_path(self.root, 'fixture', '/fixture/product', snapshot=snapshot)

    def test_config_atomic_durable_and_private(self):
        destination = self.root / config.LOCAL_CONFIG_NAME
        for existing in (False, True):
            with self.subTest(existing=existing):
                if existing:
                    destination.write_bytes(b'original\n')
                    destination.chmod(0o640)
                with self.observed(destination) as events:
                    self.assertEqual(self.write_config(), destination)
                self.assertEqual(events, ['file', 'replace', 'directory'])
                self.assertIn(b'/fixture/product', destination.read_bytes())
                self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o600)
                self.assertEqual(list(self.root.glob('.workflow-config-*')), [])

    def test_config_failure_preserves_original_or_reports_uncertain_durability(self):
        destination = self.root / config.LOCAL_CONFIG_NAME
        for failure in ('file', 'replace', 'directory'):
            with self.subTest(failure=failure):
                destination.write_bytes(b'original\n')
                with self.observed(destination, fail=failure):
                    if failure == 'replace':
                        with patch.object(os, 'replace', side_effect=OSError('synthetic replace failure')):
                            with self.assertRaises(OSError):
                                self.write_config()
                    else:
                        with self.assertRaises(OSError):
                            self.write_config()
                if failure != 'directory':
                    self.assertEqual(destination.read_bytes(), b'original\n')
                else:
                    self.assertIn(b'/fixture/product', destination.read_bytes())
                self.assertEqual(list(self.root.glob('.workflow-config-*')), [])

    def test_concurrent_config_readers_observe_only_complete_publications(self):
        destination = self.root / config.LOCAL_CONFIG_NAME
        snapshot = Mock(envelope=b'', legacy={})
        paths = ('/fixture/product one', '/fixture/product two')
        expected = set()
        for path in paths:
            config.set_local_product_repo_path(self.root, 'fixture', path, snapshot=snapshot)
            expected.add(destination.read_bytes())
        started, done = threading.Event(), threading.Event()

        def read_publications():
            observed = set()
            while not done.is_set():
                observed.add(destination.read_bytes())
                started.set()
            return observed

        with ThreadPoolExecutor(max_workers=1) as pool:
            reader = pool.submit(read_publications)
            try:
                self.assertTrue(started.wait(timeout=5))
                for _ in range(5):
                    for path in paths:
                        config.set_local_product_repo_path(self.root, 'fixture', path, snapshot=snapshot)
            finally:
                done.set()
            observed = reader.result(timeout=5)
        self.assertTrue(observed)
        self.assertLessEqual(observed, expected)
        self.assertEqual(list(self.root.glob('.workflow-config-*')), [])

    def test_review_projection_durable(self):
        destination = self.root / config.LOCAL_CONFIG_NAME
        args = argparse.Namespace(repo_root=str(self.root), destination=str(self.root))
        from contextlib import redirect_stdout
        import io
        with patch.object(config, 'resolve_local_config', return_value=(destination, 'fixture', None)), \
             patch.object(config, 'capture_config_text', return_value='review:\n  on_draft:\n    runner: [codex]\n'), \
             self.observed(destination) as events, redirect_stdout(io.StringIO()):
            self.assertEqual(config.cmd_review_snapshot(args), 0)
        self.assertEqual(events, ['file', 'replace', 'directory'])

    def cache_client(self):
        client = Mock()
        client.rest.return_value = {'number': 7, 'title': 'Fixture'}
        client.graphql.return_value = {'node': {'items': {'nodes': [], 'pageInfo': {'hasNextPage': False}}}}
        return client

    def test_project_cache_durable_and_readable(self):
        cache = self.root / 'cache'
        cache.mkdir(mode=0o700)
        client = self.cache_client()
        # Derive the public cache name using a first synthetic request.
        reader.fallback(client, 7, 'fixture-project', 'org/repo', cache_dir=str(cache), cache_pid='123')
        destination, = cache.glob('*.json')
        destination.unlink()
        with self.observed(destination) as events:
            result = reader.fallback(client, 7, 'fixture-project', 'org/repo', cache_dir=str(cache), cache_pid='123')
        self.assertEqual(events, ['file', 'replace', 'directory'])
        self.assertEqual(json.loads(destination.read_text()), result)
        calls = client.graphql.call_count
        self.assertEqual(reader.fallback(client, 7, 'fixture-project', 'org/repo', cache_dir=str(cache), cache_pid='123'), result)
        self.assertEqual(client.graphql.call_count, calls)

    def test_existing_cache_publication_is_private(self):
        cache = self.root / 'cache'
        cache.mkdir(mode=0o700)
        client = self.cache_client()
        reader.fallback(client, 7, 'fixture-project', 'org/repo', cache_dir=str(cache), cache_pid='123')
        destination, = cache.glob('*.json')
        self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o600)
        destination.write_bytes(b'original\n')  # Invalid fabricated cache forces publication.
        destination.chmod(0o640)
        with self.observed(destination) as events:
            reader.fallback(client, 7, 'fixture-project', 'org/repo', cache_dir=str(cache), cache_pid='123')
        self.assertEqual(events, ['file', 'replace', 'directory'])
        self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o600)

    def test_cache_fsync_failures_are_reported_and_temporary_is_removed(self):
        cache = self.root / 'cache'
        cache.mkdir(mode=0o700)
        client = self.cache_client()
        reader.fallback(client, 7, 'fixture-project', 'org/repo', cache_dir=str(cache), cache_pid='123')
        destination, = cache.glob('*.json')
        destination.unlink()
        for failure in ('file', 'directory'):
            with self.subTest(failure=failure):
                destination.unlink(missing_ok=True)
                with self.observed(destination, fail=failure):
                    with self.assertRaises(OSError):
                        reader.fallback(client, 7, 'fixture-project', 'org/repo', cache_dir=str(cache), cache_pid='123')
                self.assertEqual(list(cache.glob('.item-list.*')), [])
                self.assertEqual(destination.exists(), failure == 'directory')


if __name__ == '__main__':
    unittest.main()

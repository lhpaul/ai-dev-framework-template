#!/usr/bin/env python3
"""Synthetic forks, cumulative accounting, and real append/readback transport."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("history", ROOT / "reviewer-loop-history.py")
HISTORY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HISTORY)


def comment(number, entries, **extra):
    payload = dict(schema=HISTORY.SCHEMA, entries=entries, **extra)
    return {"id": number, "created_at": f"2026-01-01T00:00:{number:02d}Z",
            "body": HISTORY.HEADER + "\n\n" + HISTORY.MARKER + "\n```json\n"
            + json.dumps(payload) + "\n```\n" + HISTORY.FOOTER}


def payload(record):
    return json.loads(list(HISTORY.BLOCK.finditer(record["body"]))[-1].group(1))


class HistoryTests(unittest.TestCase):
    def test_forks_and_copied_snapshots_preserve_objects_and_multiplicity(self):
        a = {"head_sha": "a" * 40, "result": "needs_fixes", "run_id": "run-A"}
        b = {"head_sha": "b" * 40, "result": "needs_rerun", "run_id": "run-A"}
        comments = [comment(1, [a, a]), comment(2, [b]), comment(3, [a, a, b])]
        original = copy.deepcopy(comments)
        merged = HISTORY.reconcile([comments[:1], comments[1:]])
        self.assertEqual(payload(merged)["entries"], [a, a, b])
        self.assertEqual(payload(merged)["reconciled_comment_ids"], [1, 2, 3])
        self.assertEqual(comments, original)
        cumulative = dict(merged, id=4, created_at="2026-01-02")
        self.assertEqual(payload(HISTORY.reconcile([comments + [cumulative]]))["entries"], [a, a, b])

    def test_production_counter_reconciles_historical_and_distinct_retry_uuids(self):
        legacy = {"head_sha": "a" * 40, "classification_head": "a" * 40,
                  "result": "needs_fixes", "run_id": "run-A"}
        attempts = []
        for number in (1, 2):
            entry = dict(legacy, local_review_retry_attempt={
                "id": f"00000000-0000-4000-8000-{number:012d}",
                "head_sha": "a" * 40, "run_id": "run-A"})
            attempts.append(entry)
        comments = [comment(1, [legacy]), comment(2, [attempts[0]]),
                    comment(3, [dict(attempts[0], result="clean"), attempts[1]])]
        merged = HISTORY.reconcile([comments])
        env = dict(os.environ, BODY=merged["body"])
        result = subprocess.run(["bash", "-c", 'HARNESS_MODE=1 source "$1/pr-review-loop.sh"; '
                                 'reviewer_loop_history_entries_count "$BODY" run-A; '
                                 'reviewer_loop_history_entries_count "$BODY" run-B', "test", str(ROOT)],
                                env=env, text=True, capture_output=True, check=True)
        self.assertEqual(result.stdout, "3 3 available\n3 0 available\n")

    def test_unavailable_or_malformed_anywhere_never_resets_counters(self):
        valid = comment(2, [{"head_sha": "a", "result": "needs_fixes"}])
        for invalid in (comment(1, [], history_status="unavailable"),
                        dict(comment(1, []), body=HISTORY.HEADER + "\n" + HISTORY.MARKER + HISTORY.FOOTER)):
            for records in ([invalid, valid], [valid, dict(invalid, id=3, created_at="2026-01-02")]):
                data = payload(HISTORY.reconcile([records]))
                self.assertEqual(data["history_status"], "unavailable")
                self.assertEqual(data["entries"], [{"head_sha": "a", "result": "needs_fixes"}])

    def test_quoted_markers_never_become_summary_or_hide_a_cycle(self):
        records = [comment(1, [{"result": "needs_fixes"}]),
                   dict(comment(2, []), body="Untrusted guide quoting:\n" + comment(2, [])["body"])]
        result = HISTORY.reconcile([records])
        self.assertEqual(result["id"], 1)
        self.assertEqual(len(payload(result)["entries"]), 1)

    def test_invalid_api_pages_are_unavailable(self):
        for pages in ([{}], [[None]], [[{}]]):
            with self.assertRaises(ValueError):
                HISTORY.reconcile(pages)

    def test_invalid_or_conflicting_uuid_bindings_preserve_entries_but_stop(self):
        first = {"head_sha": "a" * 40, "result": "needs_fixes", "run_id": "run-A",
                 "local_review_retry_attempt": {"id": "00000000-0000-4000-8000-000000000001",
                                                "head_sha": "a" * 40, "run_id": "run-A"}}
        conflicting = copy.deepcopy(first)
        conflicting["head_sha"] = conflicting["local_review_retry_attempt"]["head_sha"] = "b" * 40
        for second in (conflicting, dict(first, local_review_retry_attempt=None)):
            result = payload(HISTORY.reconcile([[comment(1, [first]), comment(2, [second])]]))
            self.assertEqual(result["history_status"], "unavailable")
            self.assertEqual(result["entries"], [first, second])

    def test_real_publisher_post_then_independent_get_no_uncertain_write_replay(self):
        for mode, expected, operations in (("ok", 0, ["POST", "GET"]),
                                            ("mismatch", 1, ["POST", "GET"]),
                                            ("wrong_id", 1, ["POST", "GET"]),
                                            ("get_fail", 1, ["POST", "GET"]),
                                            ("uncertain", 1, ["POST"]),
                                            ("reject", 1, ["POST"]),
                                            ("bad_response", 1, ["POST"])):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                (root / "body").write_text("Synthetic cumulative record\nUnicode: ñ\n")
                mock = root / "gh"
                mock.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
root = Path(os.environ['FIXTURE'])
mode = os.environ['MODE']
args = sys.argv[1:]
operation = args[args.index('--method') + 1] if '--method' in args else 'GET'
with (root / 'calls').open('a') as log: log.write(operation + '\\n')
if operation == 'POST':
    if mode == 'reject': sys.exit(1)
    record = dict(json.loads(Path(args[args.index('--input') + 1]).read_text()), id=99)
    (root / 'saved').write_text(json.dumps(record))
    if mode == 'uncertain': sys.exit(1)
    print('{}' if mode == 'bad_response' else json.dumps(record))
elif operation == 'GET':
    if mode == 'get_fail': sys.exit(1)
    record = json.loads((root / 'saved').read_text())
    if mode == 'mismatch': record['body'] += 'changed'
    if mode == 'wrong_id': record['id'] = 100
    print(json.dumps(record))
else: sys.exit(99)
''')
                mock.chmod(0o755)
                env = dict(os.environ, FIXTURE=temp, MODE=mode, TMPDIR=temp, PATH=temp + os.pathsep + os.environ["PATH"])
                result = subprocess.run(["bash", "-c", 'source "$1/workflow-lib.sh"; '
                                         'reviewer_loop_history_publish synthetic/repo 42 "$2/body"',
                                         "test", str(ROOT), temp], env=env, capture_output=True, text=True)
                self.assertEqual(result.returncode, expected, result.stderr)
                self.assertEqual((root / "calls").read_text().splitlines(), operations)
                self.assertEqual([p.name for p in root.iterdir() if p.is_dir()], [])
                if mode not in ("reject",):
                    self.assertEqual(json.loads((root / "saved").read_text())["body"], (root / "body").read_text())

    def test_actual_summary_writers_preserve_originals_and_withhold_clean_on_bad_readback(self):
        source = (ROOT / "pr-review-loop.sh").read_text()
        definitions = []
        for name in ("_post_review_summary", "post_release_guard_summary"):
            start = source.index(name + "() {\n")
            definitions.append(source[start:source.index("\n}\n", start) + 3])
        for writer in ("normal", "release"):
            for mismatch in (False, True):
                with self.subTest(writer=writer, mismatch=mismatch), tempfile.TemporaryDirectory() as temp:
                    root = Path(temp)
                    original = json.dumps(comment(1, [{"head_sha": "a" * 40, "result": "needs_fixes"}]))
                    (root / "record-1").write_text(original)
                    mock = root / "gh"
                    mock.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
root = Path(os.environ['FIXTURE'])
args = sys.argv[1:]
method = args[args.index('--method') + 1] if '--method' in args else 'GET'
with (root / 'calls').open('a') as log: log.write(method + '\\n')
if '--paginate' in args:
    print(json.dumps([json.loads(p.read_text()) for p in sorted(root.glob('record-*'))]))
elif method == 'POST':
    record = json.loads(Path(args[args.index('--input') + 1]).read_text())
    record.update(id=1 + len(list(root.glob('record-*'))), created_at='2026-01-02')
    (root / ('record-' + str(record['id']))).write_text(json.dumps(record))
    print(json.dumps(record))
elif method == 'GET':
    record = json.loads((root / ('record-' + args[1].split('/')[-1])).read_text())
    if os.environ['MISMATCH'] == '1': record['body'] += 'changed'
    print(json.dumps(record))
else: sys.exit(99)
''')
                    mock.chmod(0o755)
                    env = dict(os.environ, FIXTURE=temp, MISMATCH=str(int(mismatch)),
                               PATH=temp + os.pathsep + os.environ["PATH"])
                    setup = '''HARNESS_MODE=1 source "$1/pr-review-loop.sh"
repo_slug() { printf 'synthetic/repo\\n'; }
reviewer_loop_dispatch_pr_policy() { :; }
reviewer_loop_history_current_head_sha() { printf 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\\n'; }
reviewer_loop_history_recorded_at() { printf '2026-01-02T00:00:00Z\\n'; }
compare_mode=0; compare_verdicts=(); platform_policy_status_notes=()
pr_number=42; branch_name=feature/42-synthetic; current_run_id=run-A
'''
                    call = ('_post_review_summary clean "" local-ai-reviewer 0 0' if writer == "normal"
                            else 'post_release_guard_summary 42 release/v0.0.0')
                    program = setup + "\n".join(definitions) + '\nstatus=0\n' + call + ' || status=$?\n'
                    program += 'printf "WRITE_STATUS=%s\\n" "$status"\n'
                    program += 'if reviewer_loop_persist_failure_should_escalate "$status" clean; then printf "STOP=escalate\\n"; fi\n'
                    program += 'exit 0\n'
                    result = subprocess.run(["bash", "-s", "--", str(ROOT)], input=program,
                                            env=env, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertIn(f"WRITE_STATUS={int(mismatch)}\n", result.stdout)
                    self.assertEqual("STOP=escalate" in result.stdout, mismatch)
                    self.assertEqual((root / "record-1").read_text(), original)
                    new = json.loads((root / "record-2").read_text())
                    self.assertEqual(len(payload(new)["entries"]), 2)
                    calls = (root / "calls").read_text().splitlines()
                    self.assertEqual(calls[-2:], ["POST", "GET"])
                    self.assertEqual(calls.count("POST"), 1)
                    self.assertTrue(all(operation in ("GET", "POST") for operation in calls))


if __name__ == "__main__":
    unittest.main(verbosity=2)

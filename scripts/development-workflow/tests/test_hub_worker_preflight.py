"""Synthetic tests for read-only hub worker preflight."""
import datetime as dt
import json
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "hub-worker-preflight.py"


class WorkerPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.hub = self.base / "hub"
        self.products = [self.base / "one", self.base / "two"]
        for path, slug in [(self.hub, "example/hub"), (self.products[0], "example/one"), (self.products[1], "example/two")]:
            path.mkdir()
            self.git(path, "init", "-q")
            self.git(path, "config", "user.email", "test@example.invalid")
            self.git(path, "config", "user.name", "Fixture")
            (path / "fixture.txt").write_text("fixture\n")
            self.git(path, "add", "fixture.txt")
            self.git(path, "-c", "core.hooksPath=/dev/null", "commit", "-qm", "fixture")
            self.git(path, "remote", "add", "origin", "https://github.com/" + slug + ".git")
        self.names = ["first", "-second"]
        self.write_config()
        bindir = self.base / "bin"
        bindir.mkdir()
        gh = bindir / "gh"
        gh.write_text('''#!/usr/bin/env python3
import json,os,sys
args=sys.argv[1:]
if os.environ.get("GH_HOST") != "github.com": sys.exit(12)
if os.environ.get("FAKE_GH_FAIL") == "auth" and args[:2] == ["auth", "status"]: sys.exit(1)
if args == ["auth", "status", "--hostname", "github.com"]: sys.exit(0)
if len(args) == 5 and args[:2] == ["repo", "view"] and args[3:] == ["--json", "nameWithOwner"]:
    if os.environ.get("FAKE_GH_FAIL") == args[2]: sys.exit(1)
    if os.environ.get("FAKE_GH_MALFORMED"): print("{"); sys.exit(0)
    print(json.dumps({"nameWithOwner":args[2].removeprefix("github.com/")})); sys.exit(0)
sys.exit(2)
''')
        gh.chmod(0o755)
        self.env = os.environ.copy()
        self.env.update({"PATH": str(bindir) + os.pathsep + self.env["PATH"], "GH_HOST": "other.example", "PYTHONDONTWRITEBYTECODE": "1"})
        self.rid = str(uuid.uuid4())
        self.start = self.now(-10)
        self.selected = self.now(-5)

    def git(self, path, *args):
        return subprocess.run(["git", "-C", str(path), *args], check=True, capture_output=True, text=True)

    def now(self, seconds=0):
        return (dt.datetime.now(dt.timezone.utc) + dt.timedelta(seconds=seconds)).isoformat(timespec="microseconds").replace("+00:00", "Z")

    def write_config(self):
        self.hub.joinpath(".ai-dev-workflow.yaml").write_text("schema_version: 2\nmode: workflow_hub\nworkflow_hub:\n  product_repos:\n" + "".join(f"    - name: {name}\n      github_repo: example/{slug}\n" for name, slug in zip(self.names, ("one", "two"))))
        self.hub.joinpath(".ai-dev-workflow.local.yaml").write_text("product_repos:\n" + "".join(f"  - name: {name}\n    local_path: ../{path.name}\n" for name, path in zip(self.names, self.products)))

    def invoke(self, *args, env=None, cwd=None):
        result = subprocess.run(["python3", str(SCRIPT), *map(str, args)], cwd=cwd or self.base,
                                env=env or self.env, capture_output=True, text=True, timeout=30)
        return result, json.loads(result.stdout)

    def check(self, worker=None, env=None):
        return self.invoke("check", "--hub-dir", self.hub, "--worker-dir", worker or self.hub,
                           "--run-id", self.rid, env=env)

    def verify(self, data, start=None, selected=None, hub=None):
        file = self.base / "result.json"
        file.write_text(json.dumps(data))
        return self.invoke("verify", "--hub-dir", hub or self.hub, "--run-id", self.rid,
                           "--result-file", file, "--run-start", start or self.start,
                           "--hub-selected-at", selected or self.selected)

    def test_success_and_current_result(self):
        before = [self.git(path, "status", "--porcelain").stdout for path in [self.hub, *self.products]]
        result, data = self.check()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, [self.git(path, "status", "--porcelain").stdout for path in [self.hub, *self.products]])
        self.assertEqual(len(data["products"]), 2)
        self.assertNotIn("first", result.stdout)
        self.assertEqual(self.verify(data)[0].returncode, 0)
        data["products"].reverse()
        self.assertEqual(self.verify(data)[0].returncode, 0)

    def test_wrong_directory_and_missing_product(self):
        self.assertEqual(self.check(worker=self.base)[1]["result"], "fail")
        subdir = self.hub / "nested"
        subdir.mkdir()
        self.assertEqual(self.check(worker=subdir)[1]["check"], "worker_directory")
        self.git(self.products[1], "remote", "set-url", "origin", "https://github.com/example/wrong.git")
        result, data = self.check()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(data["product_ordinal"], 2)
        self.assertEqual(data["check"], "product_origin")

    def test_failures_never_print_private_values(self):
        secret = "sensitive-token-sentinel"
        self.names[1] = secret
        self.write_config()
        self.git(self.products[1], "remote", "set-url", "origin", "https://user:secret@github.com/example/two.git")
        result, data = self.check()
        self.assertEqual(data["result"], "fail")
        self.assertNotIn(secret, result.stdout + result.stderr)
        self.assertNotIn("user:secret", result.stdout + result.stderr)

    def test_success_hides_sensitive_configured_name(self):
        secret = "sensitive token sentinel"
        self.names[1] = secret
        self.write_config()
        result, data = self.check()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(data["result"], "pass")
        self.assertNotIn(secret, result.stdout + result.stderr)

    def test_empty_products_and_non_checkout(self):
        config = self.hub / ".ai-dev-workflow.yaml"
        config.write_text("schema_version: 2\nmode: workflow_hub\nworkflow_hub:\n  product_repos: []\n")
        self.assertEqual(self.check()[1]["result"], "fail")
        self.write_config()
        nongit = self.base / "not-a-checkout"
        nongit.mkdir()
        local = self.hub / ".ai-dev-workflow.local.yaml"
        local.write_text(local.read_text().replace("local_path: ../two", "local_path: ../not-a-checkout"))
        self.assertEqual(self.check()[1]["check"], "product_checkout")
        self.write_config()
        self.git(self.products[1], "remote", "remove", "origin")
        self.assertEqual(self.check()[1]["check"], "product_origin")

    def test_auth_and_repository_failure(self):
        env = self.env.copy()
        for failure in ("auth", "github.com/example/two"):
            env["FAKE_GH_FAIL"] = failure
            result, data = self.check(env=env)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(data["result"], "fail")
        env.pop("FAKE_GH_FAIL")
        env["FAKE_GH_MALFORMED"] = "1"
        self.assertEqual(self.check(env=env)[1]["result"], "fail")

    def test_result_completeness_freshness_and_origin(self):
        _, valid = self.check()
        for transform in (lambda d: d["products"].pop(),
                          lambda d: d["products"].append(d["products"][0]),
                          lambda d: d["products"].append({"product_id": "1" * 64, "repo_id": "2" * 64, "checkout": "pass", "github": "pass"}),
                          lambda d: d["products"][0].update(repo_id="3" * 64),
                          lambda d: d.update(run_id=str(uuid.uuid4())),
                          lambda d: d.update(hub_repo_id="0" * 64)):
            data = json.loads(json.dumps(valid))
            transform(data)
            self.assertEqual(self.verify(data)[0].returncode, 1)
        self.assertEqual(self.verify(valid, start=self.now(-1), selected=self.now(-5))[0].returncode, 1)
        self.git(self.hub, "remote", "set-url", "origin", "https://github.com/example/other.git")
        self.assertEqual(self.verify(valid)[0].returncode, 1)

    def test_missing_mapping_then_recovery_without_mutation(self):
        config = self.hub / ".ai-dev-workflow.local.yaml"
        original = config.read_text()
        config.write_text(original.replace("local_path: ../two", "local_path: ../missing"))
        before = [self.git(path, "status", "--porcelain").stdout for path in [self.hub, *self.products]]
        result, data = self.check()
        self.assertEqual((result.returncode, data["check"], data["product_ordinal"]), (1, "product_checkout", 2))
        self.assertEqual(before, [self.git(path, "status", "--porcelain").stdout for path in [self.hub, *self.products]])
        config.write_text(original)
        self.assertEqual(self.check()[0].returncode, 0)

    def test_verifier_rejects_invalid_fields_and_timestamps(self):
        _, valid = self.check()
        for change in (lambda d: d.update(extra=True),
                       lambda d: d.update(checked_at="not-a-time"),
                       lambda d: d.update(worker="unknown"),
                       lambda d: d["products"][0].update(github="fail")):
            data = json.loads(json.dumps(valid))
            change(data)
            self.assertEqual(self.verify(data)[0].returncode, 1)
        self.assertEqual(self.verify(valid, selected=self.now(60))[0].returncode, 1)
        spanning = dict(valid, started_at=self.start)
        result, data = self.verify(spanning)
        self.assertEqual((result.returncode, data["check"]), (1, "timestamp"))
        invoked = dt.datetime.fromisoformat(valid["started_at"].replace("Z", "+00:00"))
        same_second = (invoked + dt.timedelta(microseconds=1)).isoformat(timespec="microseconds").replace("+00:00", "Z")
        self.assertEqual(self.verify(valid, selected=same_second)[1]["check"], "timestamp")
        self.assertEqual(self.verify(valid, selected=self.selected.split(".")[0] + "Z")[1]["check"], "timestamp")
        file = self.base / "duplicate.json"
        file.write_text('{"result":"pass","result":"fail"}')
        result, data = self.invoke("verify", "--hub-dir", self.hub, "--run-id", self.rid,
                                   "--result-file", file, "--run-start", self.start,
                                   "--hub-selected-at", self.selected)
        self.assertEqual((result.returncode, data["result"]), (1, "fail"))

    def test_malformed_structured_input_and_control_name(self):
        spec = importlib.util.spec_from_file_location("worker_preflight_decode", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        for raw in ("", "{", "[]", "null", '{"key":1,"key":2}'):
            with self.assertRaises(module.Failure):
                module.decode(raw, dict, "result", "Retry.")
        self.names[1] = "control\x01sentinel"
        self.write_config()
        result, data = self.check()
        self.assertNotIn("control\x01sentinel", result.stdout + result.stderr)
        self.assertIn(data["result"], ("pass", "fail"))

    def test_timeout_is_safe(self):
        spec = importlib.util.spec_from_file_location("worker_preflight", SCRIPT)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with mock.patch.object(module.subprocess, "run", side_effect=subprocess.TimeoutExpired("secret", 1)):
            with self.assertRaises(module.Failure) as raised:
                module.command(["ignored"], "github_access", "Retry.")
        self.assertEqual(raised.exception.check, "github_access")
        with mock.patch.object(module.subprocess, "run", side_effect=FileNotFoundError()):
            with self.assertRaises(module.Failure) as missing:
                module.command(["gh"], "github_auth", "Retry.")
        self.assertEqual(missing.exception.check, "github_auth")
        self.assertNotIn("secret", str(raised.exception))

    def test_entrypoint_gate_pointers(self):
        root = SCRIPT.parents[2]
        for name in ("run-item.md", "run-items.md", "run-epic.md"):
            text = (root / ".cursor" / "commands" / name).read_text()
            self.assertIn("before the first workflow write", text)
            self.assertIn("current-run preflight", text)
            self.assertIn("cursor-my-machines.md", text)

    def test_empty_and_whitespace_arguments_are_rejected_safely(self):
        for value in ("", "   "):
            result = subprocess.run(["python3", str(SCRIPT), "check", "--hub-dir", str(self.hub),
                                     "--worker-dir", str(self.hub), "--run-id", value],
                                    env=self.env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(json.loads(result.stdout)["check"], "run_id")
        for flag, check in (("--hub-dir", "hub_directory"), ("--worker-dir", "worker_directory")):
            for value in ("", "   "):
                hub = value if flag == "--hub-dir" else str(self.hub)
                worker = value if flag == "--worker-dir" else str(self.hub)
                result, data = self.invoke("check", "--hub-dir", hub, "--worker-dir", worker,
                                           "--run-id", self.rid, cwd=self.hub)
                self.assertEqual((result.returncode, data["check"]), (1, check))
        missing = subprocess.run(["python3", str(SCRIPT), "check"], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(missing.returncode, 0)
        self.assertNotIn("--hub-dir", missing.stderr)

    def test_single_product_in_path_with_spaces(self):
        other = self.base / "hub with spaces"
        self.git(self.hub, "worktree", "add", "--detach", str(other))
        other.joinpath(".ai-dev-workflow.yaml").write_text(
            "schema_version: 2\nmode: workflow_hub\nworkflow_hub:\n  product_repos:\n"
            "    - name: first\n      github_repo: example/one\n")
        other.joinpath(".ai-dev-workflow.local.yaml").write_text(
            "product_repos:\n  - name: first\n    local_path: ../one\n")
        result, data = self.invoke("check", "--hub-dir", other, "--worker-dir", other, "--run-id", self.rid)
        self.assertEqual((result.returncode, len(data["products"])), (0, 1))

    def test_linked_worktree_is_valid_hub(self):
        other = self.base / "linked-hub"
        self.git(self.hub, "worktree", "add", "--detach", str(other))
        other.joinpath(".ai-dev-workflow.yaml").write_text(self.hub.joinpath(".ai-dev-workflow.yaml").read_text())
        other.joinpath(".ai-dev-workflow.local.yaml").write_text(self.hub.joinpath(".ai-dev-workflow.local.yaml").read_text())
        result, data = self.invoke("check", "--hub-dir", other, "--worker-dir", other, "--run-id", self.rid)
        self.assertEqual((result.returncode, data["result"]), (0, "pass"))

    def test_same_origin_different_hub(self):
        _, data = self.check()
        other = self.base / "other-hub"
        self.git(self.hub, "worktree", "add", "--detach", str(other))
        other.joinpath(".ai-dev-workflow.yaml").write_text(self.hub.joinpath(".ai-dev-workflow.yaml").read_text())
        other.joinpath(".ai-dev-workflow.local.yaml").write_text(self.hub.joinpath(".ai-dev-workflow.local.yaml").read_text())
        self.assertEqual(self.verify(data, hub=other)[0].returncode, 1)


if __name__ == "__main__":
    unittest.main()

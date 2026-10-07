#!/usr/bin/env python3
"""Behavioral proofs for committed three-way template synchronization."""
from __future__ import annotations

import base64
from contextlib import redirect_stdout
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
HELPER = ROOT / "scripts/development-workflow/sync-template-merge.py"
spec = importlib.util.spec_from_file_location("sync_template_merge", HELPER)
merge = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = merge
spec.loader.exec_module(merge)

MANIFEST = '''mode_scopes:
  shared:
    description: common
  hub_only:
    description: hub
  product_repo_injection:
    description: product
categories:
  always_sync:
    - path: shared/
      glob: "**/*"
      mode_scope: shared
    - path: hub/
      glob: "**/*"
      mode_scope: hub_only
    - path: product/
      glob: "**/*"
      mode_scope: product_repo_injection
  project_specific:
    - path: shared/metrics.md
      mode_scope: hub_only
'''
TEXT = "".join(f"line {i}\n" for i in range(16))


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args], stderr=subprocess.DEVNULL).decode().strip()


class SyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="sync-1875-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.template, self.consumer = self.root / "template", self.root / "consumer"
        for path in (self.template, self.consumer):
            path.mkdir()
            git(path, "init", "-q")
            git(path, "config", "user.name", "Fixture")
            git(path, "config", "user.email", "fixture@example.test")
        (self.template / "sync-manifest.yaml").write_text(MANIFEST)
        self.write(self.template, "shared/a.md", TEXT)
        self.write(self.template, "shared/b.md", TEXT)
        self.base = self.save(self.template)
        shutil.copytree(self.template / "shared", self.consumer / "shared")
        self.bootstrap = self.save(self.consumer)
        self.plan = self.root / "plan.json"
        self.incoming = self.base

    def write(self, root, path, content):
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content.encode() if isinstance(content, str) else content)
        return target

    def save(self, root):
        git(root, "add", ".")
        git(root, "commit", "-qm", "fixture", "--allow-empty")
        return git(root, "rev-parse", "HEAD")

    def preview(self, known=True, role="single_repo", declines=(), source="template", **kwargs):
        inputs = dict(template_root=str(self.template), consumer_root=str(self.consumer),
                      template_ref=self.incoming, template_id="fixture/template", role=role,
                      base_ref=(self.base if source == "template" else self.bootstrap) if known else None,
                      base_source=source if known else None, selection_file=None, decline=sorted(declines))
        inputs.update(kwargs)
        result = merge.build_preview(inputs)
        self.plan.write_bytes(merge.json_bytes(result))
        return result

    def apply(self, expected=0):
        approval = hashlib.sha256(self.plan.read_bytes()).hexdigest()
        output = io.StringIO()
        with redirect_stdout(output):
            result = merge.main(["apply", "--plan", str(self.plan), "--approved-digest", approval])
        self.assertEqual(result, expected)
        return output.getvalue()

    def state(self):
        return json.loads((self.consumer / merge.STATE_PATH).read_text())

    def fingerprint(self):
        return {str(p.relative_to(self.consumer)): ("link", os.readlink(p)) if p.is_symlink() else ("file", p.read_bytes(), p.stat().st_mode) for p in self.consumer.rglob("*") if ".git" not in p.relative_to(self.consumer).parts and (p.is_symlink() or p.is_file())}

    def test_independent_edits_repeat_sync_and_completed_summary(self):
        self.write(self.consumer, "shared/a.md", TEXT.replace("line 1\n", "local 1\n"))
        self.write(self.template, "shared/a.md", TEXT.replace("line 13\n", "upstream 13\n"))
        self.incoming = self.save(self.template)
        before = self.fingerprint()
        plan = self.preview()
        self.assertEqual(plan["counts"], {"clean_merge": 1, "no_change": 1})
        self.assertEqual(before, self.fingerprint(), "successful dry-run changed consumer bytes/metadata")
        output = self.apply()
        self.assertIn("clean_merge\tshared/a.md", output)
        self.assertIn("local 1", (self.consumer / "shared/a.md").read_text())
        self.assertIn("upstream 13", (self.consumer / "shared/a.md").read_text())
        self.assertEqual(self.state()["files"]["shared/a.md"]["commit"], self.incoming)
        self.write(self.template, "shared/a.md", (self.template / "shared/a.md").read_text().replace("line 8\n", "next 8\n"))
        self.incoming = self.save(self.template)
        self.preview(known=False)
        self.apply()
        self.assertIn("local 1", (self.consumer / "shared/a.md").read_text())
        self.assertIn("next 8", (self.consumer / "shared/a.md").read_text())

    def test_conflict_whole_batch_and_stopped_counts(self):
        self.write(self.consumer, "shared/a.md", TEXT.replace("line 1\n", "local\n"))
        self.write(self.template, "shared/a.md", TEXT.replace("line 1\n", "upstream\n"))
        self.write(self.template, "shared/b.md", TEXT + "new\n")
        self.incoming = self.save(self.template)
        before = self.fingerprint()
        plan = self.preview()
        self.assertEqual(plan["result"], "blocked")
        self.assertEqual(plan["counts"], {"conflict": 1, "direct_update": 1})
        self.assertEqual(sum(plan["counts"].values()), plan["selected_count"])
        self.apply(expected=2)
        self.assertEqual(before, self.fingerprint())
        self.assertNotIn("<<<<<<<", (self.consumer / "shared/a.md").read_text())
        print("PROOF conflict: shared/a.md:2 fails; independent-line repair in merge test passes")

    def test_unknown_base_missing_and_differing_then_verified_bootstrap(self):
        self.write(self.consumer, "shared/a.md", TEXT.replace("line 1\n", "local\n"))
        (self.consumer / "shared/b.md").unlink()
        before = self.fingerprint()
        plan = self.preview(known=False)
        self.assertEqual(plan["counts"], {"baseline_unavailable": 2})
        self.apply(expected=2)
        self.assertEqual(before, self.fingerprint())
        repaired = self.preview(source="consumer")
        self.assertEqual(repaired["counts"], {"local_deletion": 1, "local_retained": 1})
        self.apply()
        self.assertFalse((self.consumer / "shared/b.md").exists())
        print("PROOF unknown base: shared/a.md:2 and deleted shared/b.md block; verified bootstrap passes")

    def test_declined_path_keeps_base_and_missing_entries_stay_unknown(self):
        self.preview(); self.apply()
        old = self.state()["files"]["shared/b.md"]
        self.write(self.template, "shared/b.md", TEXT + "incoming\n")
        self.incoming = self.save(self.template)
        self.preview(known=False, declines=["shared/b.md"]); self.apply()
        self.assertEqual(old, self.state()["files"]["shared/b.md"])
        self.write(self.template, "shared/new.md", "new\n")
        self.incoming = self.save(self.template)
        self.preview(known=False)
        self.assertEqual(json.loads(self.plan.read_text())["counts"]["baseline_unavailable"], 1)
        self.preview(); self.apply()
        self.assertTrue((self.consumer / "shared/new.md").exists())

    def test_local_only_deletion_upstream_modification_and_consumer_only(self):
        self.write(self.consumer, "shared/a.md", TEXT + "local\n")
        (self.consumer / "shared/b.md").unlink()
        self.write(self.consumer, "shared/consumer-only.md", "mine\n")
        self.assertEqual(self.preview()["counts"], {"local_retained": 1, "local_deletion": 1})
        self.apply()
        self.assertEqual((self.consumer / "shared/consumer-only.md").read_text(), "mine\n")
        self.write(self.template, "shared/b.md", TEXT + "upstream\n"); self.incoming = self.save(self.template)
        self.assertEqual(self.preview(known=False)["counts"]["conflict"], 1)

    def test_upstream_removal_requires_resolution_or_decline(self):
        (self.template / "shared/a.md").unlink(); self.incoming = self.save(self.template)
        # Seed ledger so removed incoming paths are still selected.
        self.incoming = self.base; self.preview(); self.apply()
        self.incoming = git(self.template, "rev-parse", "HEAD")
        self.assertEqual(self.preview(known=False)["counts"]["conflict"], 1)
        self.preview(known=False, declines=["shared/a.md"]); self.apply()
        self.assertTrue((self.consumer / "shared/a.md").exists())
        (self.consumer / "shared/a.md").unlink()
        self.preview(known=False); self.apply()
        self.assertIsNone(self.state()["files"]["shared/a.md"]["blob"])

    def test_stale_consumer_mode_config_source_state_and_two_applies(self):
        self.preview()
        self.write(self.consumer, "shared/a.md", "late edit\n")
        before = self.fingerprint(); self.apply(expected=2); self.assertEqual(before, self.fingerprint())
        self.preview(); (self.consumer / "shared/a.md").chmod(0o700)
        before = self.fingerprint(); self.apply(expected=2); self.assertEqual(before, self.fingerprint())
        self.preview(); self.write(self.consumer, ".ai-dev-workflow.yaml", "mode: product_repo\n")
        self.apply(expected=2)
        self.preview(); self.save(self.template)
        self.apply(expected=2)
        self.incoming = git(self.template, "rev-parse", "HEAD"); self.preview(); self.apply()
        self.preview(); old = self.plan.read_bytes(); self.apply()
        self.plan.write_bytes(old)
        # Already-synchronized no-op replay is harmless; a state-changing first apply rejects the second.
        self.write(self.template, "shared/b.md", TEXT + "update\n"); self.incoming = self.save(self.template)
        self.preview(known=False); duplicate = self.plan.read_bytes(); self.apply()
        self.plan.write_bytes(duplicate); before = self.fingerprint(); self.apply(expected=2)
        self.assertEqual(before, self.fingerprint())
        print("PROOF stale: shared/a.md:1 edit and permission change fail; fresh preview passes; duplicate apply rejects")

    def test_tampered_selection_requires_independent_approval_digest(self):
        plan = self.preview(); approved = hashlib.sha256(self.plan.read_bytes()).hexdigest()
        plan["inputs"]["decline"] = ["shared/a.md"]
        self.plan.write_bytes(merge.json_bytes(plan))
        before = self.fingerprint()
        self.assertEqual(merge.main(["apply", "--plan", str(self.plan), "--approved-digest", approved]), 2)
        self.assertEqual(before, self.fingerprint())
        self.preview(); self.apply()
        print("PROOF approval binding: plan.json inputs.decline tamper fails; original approved plan passes")

    def test_roles_and_cross_scope_project_owned_exclusion(self):
        for path in ("hub/x.md", "product/x.md", "shared/metrics.md"):
            self.write(self.template, path, "template\n")
        self.incoming = self.save(self.template)
        self.write(self.consumer, "shared/metrics.md", "consumer rows\n")
        hub = self.preview(role="workflow_hub")
        self.assertIn("hub/x.md", [r["path"] for r in hub["rows"]])
        self.assertNotIn("product/x.md", [r["path"] for r in hub["rows"]])
        product = self.preview(role="product_repo")
        self.assertIn("product/x.md", [r["path"] for r in product["rows"]])
        self.assertNotIn("hub/x.md", [r["path"] for r in product["rows"]])
        self.assertNotIn("shared/metrics.md", [r["path"] for r in product["rows"]])
        self.apply(); self.assertEqual((self.consumer / "shared/metrics.md").read_text(), "consumer rows\n")

    def test_source_untracked_and_staged_data_never_selected(self):
        self.write(self.template, "shared/untracked-secret.md", "do not copy\n")
        self.write(self.template, "shared/staged.md", "do not copy\n"); git(self.template, "add", "shared/staged.md")
        self.write(self.template, "shared/a.md", "uncommitted change\n")
        plan = self.preview()
        self.assertEqual(plan["counts"], {"no_change": 2}); self.apply()
        self.assertFalse((self.consumer / "shared/staged.md").exists())
        self.assertEqual((self.consumer / "shared/a.md").read_text(), TEXT)

    def test_modes_binary_and_independent_exec_change(self):
        (self.consumer / "shared/a.md").chmod(0o700)
        self.write(self.template, "shared/a.md", TEXT + "upstream\n"); self.incoming = self.save(self.template)
        self.assertEqual(self.preview()["counts"]["clean_merge"], 1); self.apply()
        self.assertEqual((self.consumer / "shared/a.md").stat().st_mode & 0o777, 0o700)
        self.write(self.template, "shared/b.md", b"base\0\xff"); self.base = self.save(self.template)
        self.write(self.consumer, "shared/b.md", b"local\0\xff")
        self.write(self.template, "shared/b.md", b"upstream\0\xff"); self.incoming = self.save(self.template)
        # Use a fresh consumer without ledger for the verified binary baseline.
        (self.consumer / merge.STATE_PATH).unlink()
        self.assertEqual(self.preview()["counts"]["conflict"], 1)

    def test_symlink_alias_new_directories_cycles_escape_and_ancestor(self):
        self.write(self.template, "shared/skills/workflow/SKILL.md", "skill\n")
        os.symlink("skills/workflow", self.template / "shared/alias")
        self.incoming = self.save(self.template)
        self.preview(); self.apply()
        self.assertTrue((self.consumer / "shared/alias").is_symlink())
        self.assertEqual((self.consumer / "shared/alias/SKILL.md").read_text(), "skill\n")
        (self.template / "shared/alias").unlink(); os.symlink("../../escape", self.template / "shared/alias")
        self.incoming = self.save(self.template)
        self.assertEqual(self.preview(known=False)["counts"]["blocked"], 1)
        (self.template / "shared/alias").unlink(); os.symlink("alias", self.template / "shared/alias")
        self.incoming = self.save(self.template)
        self.assertEqual(self.preview(known=False)["counts"]["blocked"], 1)
        (self.consumer / "shared/a.md").unlink(); os.symlink(self.root, self.consumer / "shared/a.md")
        self.assertEqual(self.preview(known=False)["result"], "blocked")

    def test_symlink_target_conflict_directory_collision_and_dangling(self):
        os.symlink("a.md", self.template / "shared/alias"); self.base = self.save(self.template)
        os.symlink("b.md", self.consumer / "shared/alias")
        (self.template / "shared/alias").unlink(); os.symlink("missing.md", self.template / "shared/alias")
        self.incoming = self.save(self.template)
        self.assertEqual(self.preview()["counts"]["conflict"], 1)
        (self.consumer / "shared/alias").unlink(); (self.consumer / "shared/alias").mkdir()
        self.assertEqual(self.preview()["counts"]["blocked"], 1)

    def test_ledger_corruption_duplicate_schema_missing_commit_and_identity(self):
        self.preview(); self.apply()
        state = self.state(); path = self.consumer / merge.STATE_PATH
        state["files"]["shared/a.md"]["commit"] = "0" * 40; path.write_text(json.dumps(state))
        self.assertEqual(self.preview(known=False)["counts"]["blocked"], 1)
        for raw in ('{"schema_version":1,"schema_version":1}', '{"schema_version":99}', '{bad json'):
            path.write_text(raw); before = self.fingerprint(); result = self.preview(known=False)
            self.assertEqual(result["result"], "blocked"); self.assertEqual(before, self.fingerprint())
        state["template_id"] = "other/template"; path.write_text(json.dumps(state))
        self.assertEqual(self.preview(known=False)["result"], "blocked")

    def test_fallback_selection_and_nonascii_space_paths(self):
        (self.template / "sync-manifest.yaml").unlink()
        self.write(self.template, "shared/á file.md", "new\n"); self.incoming = self.save(self.template)
        selection = self.root / "selection.json"
        selection.write_text(json.dumps({"role":"single_repo", "paths":["shared/á file.md"], "project_specific":[]}))
        result = self.preview(selection_file=str(selection))
        self.assertEqual(result["counts"], {"add": 1}); self.apply()
        self.assertEqual((self.consumer / "shared/á file.md").read_text(), "new\n")
        self.preview(selection_file=str(selection)); selection.write_text('{}'); self.apply(expected=2)

    def test_rollback_write_and_metadata_failure_restore_batch(self):
        self.preview(); self.apply()
        before = self.fingerprint()
        self.write(self.template, "shared/a.md", TEXT + "new a\n")
        self.write(self.template, "shared/new.md", "new path\n"); self.incoming = self.save(self.template)
        self.preview()
        original = merge.write_snapshot
        def fail_ledger(root, path, snapshot, created):
            if path == merge.STATE_PATH and snapshot != merge.local_snapshot(root, path):
                raise OSError("planted metadata write failure")
            return original(root, path, snapshot, created)
        with patch.object(merge, "write_snapshot", side_effect=fail_ledger):
            self.apply(expected=2)
        self.assertEqual(before, self.fingerprint())
        self.assertFalse((self.consumer / merge.LOCK_PATH).exists())
        self.preview(); self.apply()
        print("PROOF rollback: metadata persistence failure restores shared/a.md and created shared/new.md; corrected writer passes")

    def test_composed_entrypoints_share_preservation_and_approval_contract(self):
        bodies = [ROOT / path for path in (".claude/commands/sync-template.md", ".cursor/commands/sync-template.md", ".claude/skills/sync-template.md")]
        sections = []
        for body in bodies:
            text = body.read_text()
            for token in ("sync-template-merge.py", "--approved-digest", "Locally modified template files", "baseline_unavailable", ".ai-dev-workflow.sync-state.json", "Decide with me", "Accept recommendations"):
                self.assertIn(token, text, str(body))
            self.assertNotIn("Copy/overwrite all", text)
            self.assertNotIn("template is a clean superset", text)
            sections.append(text[text.index("### Exact source and per-path"):text.index("**Migration notes check**")])
        self.assertTrue(all(section == sections[0] for section in sections))

    def test_real_committed_template_aliases_and_role_selection(self):
        source = ROOT.resolve(); sha = git(source, "rev-parse", "HEAD")
        inputs = dict(template_root=str(source), consumer_root=str(self.consumer),
                      template_ref=sha, template_id="fixture/real-template", role="single_repo",
                      base_ref=None, base_source=None, selection_file=None, decline=[])
        objects = merge.Objects(); matches, owned, _ = merge.selection(inputs, objects)
        selected = [path for path in objects.tree(source, sha) if path not in owned and matches(path)]
        self.assertTrue(selected)
        link_count = 0
        for path in selected:
            snapshot = objects.snapshot(source, sha, path)
            target = self.consumer / path; target.parent.mkdir(parents=True, exist_ok=True)
            if snapshot["mode"] == "120000":
                os.symlink(os.fsdecode(merge.decoded(snapshot["data"])), target); link_count += 1
            else:
                target.write_bytes(merge.decoded(snapshot["data"]))
                target.chmod(0o755 if snapshot["mode"] == "100755" else 0o644)
        self.assertGreater(link_count, 0, "real shipped alias coverage missing")
        plan = merge.build_preview(inputs)
        self.assertEqual(plan["result"], "ready")
        self.assertEqual(plan["counts"], {"no_change": len(selected)})
        self.plan.write_bytes(merge.json_bytes(plan)); self.apply()
        self.assertNotIn("docs/workflow/retro-metrics.md", self.state()["files"])
        print(f"REAL_TEMPLATE revision={sha} selected={len(selected)} symlinks={link_count} all ready")

    def test_leftover_lock_blocks_and_preview_cannot_write_consumer(self):
        lock = self.consumer / merge.LOCK_PATH
        self.preview(); lock.mkdir()
        self.apply(expected=2)
        self.assertEqual(self.preview()["result"], "blocked")
        lock.rmdir(); self.preview(); self.apply()
        print("PROOF lock: .ai-dev-workflow.sync-lock blocks a ready apply; cleared fixture lock and fresh preview pass")
        args = ["preview", "--template-root", str(self.template), "--consumer-root", str(self.consumer), "--template-ref", self.incoming, "--template-id", "fixture/template", "--role", "single_repo", "--plan", str(self.consumer / "shared/a.md")]
        before = self.fingerprint(); self.assertEqual(merge.main(args), 2); self.assertEqual(before, self.fingerprint())
        for path in ("../outside", "/absolute", "a/../b", ".git/config"):
            with self.assertRaises(merge.SyncError): merge.valid_path(path)


if __name__ == "__main__":
    unittest.main(verbosity=2)

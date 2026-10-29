#!/usr/bin/env python3
"""Synthetic behavioral tests for evidence identity and proof binding."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location(
    "review_evidence", Path(__file__).resolve().parents[1] / "review-evidence-context.py")
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.raw = {"repository": "example/project", "pr_number": 42,
                    "head_sha": "a" * 40, "body": "Synthetic pass/fail proof",
                    "available": True, "comments": [
                        {"id": 10, "body": "Verification request", "updated_at": "2026-01-01T00:00:00Z"},
                        {"id": 20, "body": "Synthetic planted violation fails; removal passes",
                         "updated_at": "2026-01-01T00:00:00Z"}]}
        self.context = evidence.snapshot(self.raw)
        self.result = {"result": "clean", "reviewed_head": "a" * 40,
                       "evidence_verification": {"schema": evidence.PROOF_SCHEMA,
                           "snapshot_sha256": self.context["snapshot_sha256"],
                           "request_id": 10, "status": "verified", "sources": ["comment:20"]}}

    def test_explicit_current_proof_can_verify_comment_or_body(self):
        for sources in (["body"], ["comment:20"], ["body", "comment:20"]):
            with self.subTest(sources=sources):
                self.result["evidence_verification"]["sources"] = sources
                self.assertTrue(evidence.verify(self.context, self.result, 10)["verified"])

    def test_verification_inspection_never_relaxes_other_blockers(self):
        classifier = Path(__file__).resolve().parents[1] / "apply-readiness-labels.sh"
        request = ("<table><tr><td>\n**Ticket compliance analysis**\n"
                   "**[42](url) - PR Code Verified**\nCompliant requirements:\n- Code checked.\n"
                   "Requires further human verification:\n- Verify synthetic test evidence.\n"
                   "</td></tr></table>\n### Recommended focus areas for review\n**No major issues detected**\n")
        for name, body, expected in (
                ("known", request, "clean"),
                ("code", request.replace("No major issues detected", "Must Fix"), "needs_fixes"),
                ("partial", request.replace("PR Code Verified", "Partially compliant"), "clean"),
                ("unknown", request.replace("PR Code Verified", "Unknown status"), "escalate"),
                ("malformed", request.replace("</td>", ""), "escalate"),
                ("unvalidated_prefix", request.replace("**[42]", "Verification: pending\n**[42]"), "escalate"),
                ("checkpoint", request + "<h3>Requires further human verification</h3>\n", "escalate"),
                ("status", request + "## Verification status: pending\n", "escalate"),
                ("security", request + "## Security concerns\nYes\n", "needs_fixes"),
                ("unknown_focus", request.replace("No major issues detected", "Unknown label"), "escalate")):
            with self.subTest(name=name):
                output = subprocess.run(["bash", str(classifier), "--inspect-pr-agent"],
                    input=body, capture_output=True, text=True, check=True)
                inspection = json.loads(output.stdout)
                self.assertFalse(inspection["verification_only"])
                self.assertEqual(inspection["verdict"], expected)

    def test_ticket_only_shared_predicate_does_not_require_proof(self):
        raw = copy.deepcopy(self.raw)
        request = ("**Ticket compliance analysis**\n**[42](url) - PR Code Verified**\n"
                   "Compliant requirements:\n- Code checked.\n"
                   "Requires further human verification:\n- Verify synthetic test evidence.\n"
                   "### Recommended focus areas for review\n**No major issues detected**\n")
        raw["comments"][0]["body"] = request
        proof = copy.deepcopy(self.result["evidence_verification"])
        proof["snapshot_sha256"] = evidence.snapshot(raw)["snapshot_sha256"]
        ledger = {"schema": "reviewer_loop_history.v1", "entries": [{
            "reviewed_heads": [{"platform": "pr-agent", "reviewed_head": "a" * 40}],
            "platform_results": [{"platform": "pr-agent", "result": "clean",
                "evidence_verifier": "local-ai-reviewer", "evidence_verification": proof}]}]}
        library = Path(__file__).resolve().parents[1] / "workflow-lib.sh"
        with tempfile.TemporaryDirectory() as root:
            root = Path(root)
            mock = root / "gh"
            mock.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
data=json.loads(Path(os.environ["MOCK_SHARED_DATA"]).read_text())
args=sys.argv[1:]
if args[:2] == ["api", "user"]: print("reviewer")
elif args[:2] == ["pr", "view"]: print(json.dumps(data["pr"]))
elif "permission" in " ".join(args): print(data["permission"])
elif args[:1] == ["api"]: print(json.dumps([data["comments"]]))
else: sys.exit(1)
''')
            mock.chmod(0o755)
            datafile = root / "data.json"
            bodyfile = root / "body.txt"
            bodyfile.write_text(request)
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"],
                       MOCK_SHARED_DATA=str(datafile))
            for variant, expected in (("verified", "clean"), ("missing", "clean"),
                    ("edited", "clean"), ("deleted", "clean"),
                    ("forged", "clean"), ("writer", "clean"),
                    ("unverified", "clean"), ("wrong_head", "clean"),
                    ("wrong_request", "clean"), ("bookkeeping", "clean"), ("inherited_claim", "clean"), ("outside", "escalate"),
                    ("malformed", "escalate")):
                with self.subTest(variant=variant):
                    bodyfile.write_text(request + "### Verification: pending\n" if variant == "outside"
                                        else request.replace("PR Code Verified", "Unknown status") if variant == "malformed"
                                        else request)
                    current = copy.deepcopy(raw)
                    payload = copy.deepcopy(ledger)
                    record = payload["entries"][0]["platform_results"][0]
                    if variant == "missing": record.pop("evidence_verification")
                    if variant == "edited": current["comments"][1]["body"] += " amended"
                    if variant == "deleted": current["comments"].pop()
                    if variant == "unverified": record["evidence_verification"]["status"] = "unverified"
                    if variant == "wrong_head": payload["entries"][0]["reviewed_heads"][0]["reviewed_head"] = "b" * 40
                    if variant == "wrong_request": record["evidence_verification"]["request_id"] = 11
                    if variant == "bookkeeping": record["evidence_verification"]["sources"] = ["comment:30"]
                    if variant == "inherited_claim": payload["entries"].append({"platform_results": [], "result": "clean"})
                    summary = ("### Automated Reviewer Loop Summary\n"
                               "*Posted automatically by `pr-review-loop.sh`.*\n"
                               "<!-- reviewer-loop-history:v1 -->\n```json\n" + json.dumps(payload) + "\n```\n")
                    current["comments"].append({"id": 30, "body": summary,
                        "updated_at": "2026-01-01", "created_at": "2026-01-01",
                        "user": {"login": "attacker" if variant in ("forged", "writer") else "reviewer"}})
                    datafile.write_text(json.dumps({"comments": current["comments"],
                        "pr": {"headRefOid": "a" * 40, "body": raw["body"]},
                        "permission": "write" if variant == "writer" else "read"}))
                    result = subprocess.run(["bash", "-c", 'source "$1"; workflow_pr_agent_evidence_verdict example/project 42 "$2" 10 "$(cat "$3")"',
                        "synthetic-shared-predicate", str(library), "a" * 40, str(bodyfile)],
                        env=env, text=True, capture_output=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(result.stdout, expected, result.stderr)

    def test_publication_and_unrelated_clean_are_not_verification(self):
        for result in ({"result": "clean", "reviewed_head": "a" * 40}, {}, None):
            self.assertFalse(evidence.verify(self.context, result, 10)["verified"])

    def test_code_finding_or_wrong_head_cannot_be_overridden_by_proof(self):
        for key, value in (("result", "needs_fixes"), ("reviewed_head", "b" * 40)):
            result = copy.deepcopy(self.result)
            result[key] = value
            self.assertFalse(evidence.verify(self.context, result, 10)["verified"])

    def test_evidence_edit_delete_and_identity_change_invalidate_proof(self):
        for kind in ("body", "edit", "delete", "request", "head", "repo", "pr"):
            raw = copy.deepcopy(self.raw)
            if kind == "body": raw["body"] += " amended"
            elif kind == "edit": raw["comments"][1]["body"] += " amended"
            elif kind == "delete": raw["comments"].pop()
            elif kind == "request": raw["comments"][0]["body"] += " amended"
            elif kind == "head": raw["head_sha"] = "b" * 40
            elif kind == "repo": raw["repository"] = "example/other"
            else: raw["pr_number"] = 43
            self.assertFalse(evidence.verify(evidence.snapshot(raw), self.result, 10)["verified"], kind)

    def test_comment_order_is_irrelevant_and_complete_unicode_is_preserved(self):
        self.raw["body"] = "Prueba íntegra 🧪" * 10000
        original = evidence.snapshot(self.raw)
        self.raw["comments"].reverse()
        reordered = evidence.snapshot(self.raw)
        self.assertEqual(original, reordered)
        self.assertEqual(reordered["body"], self.raw["body"])
        self.raw["body"] += "final-character-change"
        self.assertNotEqual(original["snapshot_sha256"], evidence.snapshot(self.raw)["snapshot_sha256"])

    def test_bookkeeping_is_excluded_but_marker_prose_is_not(self):
        raw = copy.deepcopy(self.raw)
        raw["comments"].append({"id": 30, "body": "### Automated Reviewer Loop Summary\nnew history",
                                "updated_at": "2026-01-01T00:01:00Z"})
        self.assertEqual(self.context["snapshot_sha256"], evidence.snapshot(raw)["snapshot_sha256"])
        raw["comments"][-1]["body"] = "Mention ### Automated Reviewer Loop Summary in proof"
        self.assertNotEqual(self.context["snapshot_sha256"], evidence.snapshot(raw)["snapshot_sha256"])

    def test_unknown_self_empty_duplicate_or_malformed_proof_is_rejected(self):
        for sources in ([], ["comment:10"], ["comment:999"], ["comment:020"],
                        ["comment:20", "comment:20"], [True], None):
            result = copy.deepcopy(self.result)
            result["evidence_verification"]["sources"] = sources
            self.assertFalse(evidence.verify(self.context, result, 10)["verified"], sources)
        for key, value in (("status", "unknown"), ("request_id", True),
                           ("request_id", 20), ("schema", "unknown")):
            result = copy.deepcopy(self.result)
            result["evidence_verification"][key] = value
            self.assertFalse(evidence.verify(self.context, result, 10)["verified"])

    def test_unavailable_partial_tampered_or_duplicate_context_cannot_verify(self):
        raw = copy.deepcopy(self.raw)
        raw["available"] = False
        context = evidence.snapshot(raw)
        self.assertEqual(context["snapshot_sha256"], "")
        self.assertFalse(evidence.verify(context, self.result, 10)["verified"])
        context = copy.deepcopy(self.context)
        context["body"] += " tamper"
        self.assertFalse(evidence.verify(context, self.result, 10)["verified"])
        raw = copy.deepcopy(self.raw)
        raw["comments"].append(raw["comments"][0])
        with self.assertRaises(ValueError): evidence.snapshot(raw)

    def test_collection_reads_every_page_and_failure_never_becomes_empty_success(self):
        library = Path(__file__).resolve().parents[1] / "workflow-lib.sh"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            pr_file, pages_file, output = (root / n for n in ("pr.json", "pages.json", "context.json"))
            pr_file.write_text(json.dumps({"headRefOid": "a" * 40, "body": "Complete synthetic body"}))
            comments = [{"id": i, "body": f"Proof {i} 🧪", "updated_at": "2026-01-01T00:00:00Z"}
                        for i in range(100, 205)]
            pages_file.write_text(json.dumps([comments[:100], comments[100:]]))
            gh = root / "gh"
            gh.write_text('''#!/usr/bin/env bash
case "$1" in
  pr) cat "$MOCK_EVIDENCE_PR_FILE" ;;
  api)
    [ "${MOCK_EVIDENCE_API_FAIL:-0}" = 0 ] || exit 1
    cat "$MOCK_EVIDENCE_PAGES_FILE" ;;
  *) exit 99 ;;
esac
''')
            gh.chmod(0o755)
            env = {**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"],
                   "MOCK_EVIDENCE_PR_FILE": str(pr_file), "MOCK_EVIDENCE_PAGES_FILE": str(pages_file)}
            command = ["bash", "-c", 'source "$1"; workflow_collect_review_evidence example/project 42 "$3" "$2"',
                       "synthetic-collector", str(library), str(output), "a" * 40]
            collected = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(collected.returncode, 0, collected.stderr)
            context = json.loads(output.read_text())
            self.assertEqual(context["comments"], comments)
            env["MOCK_EVIDENCE_API_FAIL"] = "1"
            unavailable = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(unavailable.returncode, 1)
            self.assertFalse(json.loads(output.read_text())["available"])
            self.assertIn("context unavailable", unavailable.stderr)


if __name__ == "__main__":
    unittest.main()

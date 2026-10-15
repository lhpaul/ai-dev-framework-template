#!/usr/bin/env bash
# covers: scripts/development-workflow/workflow-risk-paths.py
# covers: scripts/development-workflow/run-epic-risk-classifier.sh
# covers: scripts/development-workflow/workflow-config-resolver.py
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
python3 - "$SCRIPT_DIR/../workflow-risk-paths.py" <<'PY'
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

helper = Path(sys.argv.pop())
spec = importlib.util.spec_from_file_location("risk_paths", helper)
module = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = module
spec.loader.exec_module(module)


class RiskPathsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.config = self.root / ".ai-dev-workflow.yaml"

    def evaluate(self, config=None, paths=None, **identity):
        if config is not None:
            self.config.write_text(config)
        return module.evaluate(self.root, identity.pop("product", ""),
                               dict(changed_files=paths if paths is not None else ["docs/a.md"], **identity))

    def rule_config(self, rules):
        return "guardrails:\n  risk_paths:\n" + "".join(
            f"    - glob: {json.dumps(glob)}\n      risk: {risk}\n      reason: {json.dumps(reason)}\n"
            for glob, risk, reason in rules)

    def test_absent_and_empty_maps(self):
        self.assertEqual(self.evaluate(), {"matches": {}})
        for config in ("", "guardrails: {}\n", "guardrails:\n  risk_paths: []\n"):
            with self.subTest(config=config):
                self.assertEqual(self.evaluate(config), {"matches": {}})

    def test_overlap_order_and_tie_reasons(self):
        rules = [("docs/**", "low", "Docs"), ("docs/store/**", "high", "Store"),
                 ("docs/store/*", "high", "Second reason")]
        for ordered in (rules, list(reversed(rules))):
            result = self.evaluate(self.rule_config(ordered), ["docs/store/x.md"])["matches"]["docs/store/x.md"]
            self.assertEqual(result["risk"], "high")
            self.assertEqual(len(result["reasons"]), 3)
            self.assertTrue(all(any(reason in text for text in result["reasons"])
                                for reason in ("Docs", "Store", "Second reason")))

    def test_glob_boundaries_and_literal_strings(self):
        cases = [("docs/*", "docs/a.md", True), ("docs/*", "docs/sub/a.md", False),
                 ("docs/**", "docs/sub/a.md", True), ("docs/a?b.md", "docs/acb.md", True),
                 ("docs/a?b.md", "docs/a/b.md", False), ("docs/*", "docs/.hidden", True),
                 ("docs/**", "Docs/a.md", False), ("**/file", "file", False),
                 ("**/file", "dir/file", True), ("file", "file", True),
                 ("docs/a+b.md", "docs/ab.md", False), ("docs/a+b.md", "docs/a+b.md", True),
                 ("docs/a b.md", "docs/a b.md", True)]
        for glob, path, expected in cases:
            with self.subTest(glob=glob, path=path):
                result = self.evaluate(self.rule_config([(glob, "low", "Literal reason with spaces")]), [path])
                self.assertEqual(path in result["matches"], expected)

    def test_invalid_map_shapes(self):
        for value in ("null", "", "{}", "low", "true", "1"):
            with self.subTest(value=value), self.assertRaises(module.RiskPathError):
                self.evaluate(f"guardrails:\n  risk_paths: {value}\n")

    def test_invalid_rule_shapes(self):
        invalid = [None, {}, {"glob": "**", "risk": "low"},
                   {"glob": "**", "risk": "low", "reason": "x", "extra": "x"}]
        good = {"glob": "docs/**", "risk": "low", "reason": "Docs"}
        for key in good:
            for value in (None, True, 1, "", "   ", "line\nbreak", "line\u2028break"):
                invalid.append(dict(good, **{key: value}))
        invalid.append(dict(good, risk="critical"))
        for rule in invalid:
            with self.subTest(rule=rule), self.assertRaises(module.RiskPathError):
                module.rules_from_node([rule], "guardrails.risk_paths")

    def test_invalid_unmatched_rule_still_fails(self):
        with self.assertRaises(module.RiskPathError):
            self.evaluate(self.rule_config([("docs/**", "low", "Docs"),
                                            ("apps/**", "unknown", "Unmatched")]))

    def test_invalid_patterns_and_changed_paths(self):
        invalid = ["/docs/**", "./docs/**", "docs/../x", "docs//x", "docs/", "docs\\x", "docs/\nx"]
        for value in invalid:
            with self.subTest(value=value), self.assertRaises(module.RiskPathError):
                self.evaluate(self.rule_config([(value, "low", "Docs")]))
            with self.subTest(path=value), self.assertRaises(module.RiskPathError):
                self.evaluate("", [value])
        for value in ("docs/[ab]", "docs/{a,b}"):
            with self.subTest(value=value), self.assertRaises(module.RiskPathError):
                self.evaluate(self.rule_config([(value, "low", "Docs")]))
        for value in (None, 1, False, "", " "):
            with self.subTest(value=value), self.assertRaises(module.RiskPathError):
                self.evaluate("", [value])

    def test_strict_yaml_diagnostic_redaction(self):
        documents = ["guardrails:\n  risk_paths: []\n  risk_paths: []\n",
                     "guardrails:\n  risk_paths: &rules []\n",
                     "guardrails:\n  risk_paths: *missing\n",
                     "guardrails:\n  risk_paths: !!str hidden-sensitive-value\n",
                     "guardrails:\n  risk_paths: |\n    hidden-sensitive-value\n",
                     "guardrails: [hidden-sensitive-value\n"]
        for config in documents:
            with self.subTest(config=config):
                self.config.write_text(config)
                proc = subprocess.run([sys.executable, str(helper), "--repo-root", str(self.root)],
                                      input='{"changed_files":["docs/a.md"]}', text=True, capture_output=True)
                self.assertEqual(proc.returncode, 2)
                self.assertEqual(proc.stdout, "")
                self.assertNotIn("hidden-sensitive-value", proc.stderr)
                self.assertIn("ERROR:", proc.stderr)

    def hub_config(self, maps=True):
        root_map = "guardrails:\n  risk_paths:\n    - glob: docs/**\n      risk: high\n      reason: Hub\n" if maps else ""
        product_map = "      guardrails:\n        risk_paths:\n          - glob: docs/**\n            risk: low\n            reason: Product\n" if maps else ""
        return ("mode: workflow_hub\n" + root_map + "workflow_hub:\n  product_repos:\n"
                "    - name: one\n      github_repo: example/one\n" + product_map +
                "    - name: two\n      github_repo: example/two\n")

    def test_project_isolation_and_explicit_priority(self):
        config = self.hub_config()
        result = self.evaluate(config, product="one", productRepo={"name": "two"}, github_repo="example/one")
        self.assertEqual(result["matches"]["docs/a.md"]["risk"], "low")
        self.assertEqual(self.evaluate(config, product="two")["matches"], {})
        self.assertEqual(self.evaluate(config, github_repo="example/one")["matches"]["docs/a.md"]["risk"], "low")
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        subprocess.run(["git", "-C", str(self.root), "remote", "add", "origin", "https://github.com/example/hub.git"], check=True)
        self.assertEqual(self.evaluate(config, github_repo="example/hub")["matches"]["docs/a.md"]["risk"], "high")

    def test_hub_identity_in_linked_worktree(self):
        self.config.write_text(self.hub_config())
        def git(*args):
            return subprocess.run(["git", "-C", str(self.root), *args],
                                  check=True, capture_output=True, text=True)
        git("init", "-q")
        git("remote", "add", "origin", "https://github.com/example/hub.git")
        git("add", ".ai-dev-workflow.yaml")
        git("-c", "user.name=Test", "-c", "user.email=test@example.invalid",
            "-c", "commit.gpgsign=false", "commit", "-qm", "Fixture")
        linked = self.root / "linked"
        git("worktree", "add", "--detach", str(linked))
        self.assertTrue((linked / ".git").is_file())
        evidence = {"changed_files": ["docs/a.md"], "github_repo": "example/hub"}
        expected = module.evaluate(self.root, "", evidence)
        self.assertEqual(module.evaluate(linked, "", evidence), expected)
        self.assertEqual(expected["matches"]["docs/a.md"]["risk"], "high")
        with self.assertRaises(module.RiskPathError):
            module.evaluate(linked, "", dict(evidence, github_repo="example/unknown"))

    def test_project_selection_errors_and_no_map_compatibility(self):
        for identity in ({}, {"product": "missing"}, {"github_repo": "example/missing"},
                         {"product": "one", "github_repo": "example/two"}):
            with self.subTest(identity=identity), self.assertRaises(module.RiskPathError):
                self.evaluate(self.hub_config(), **identity)
        self.assertEqual(self.evaluate(self.hub_config(False))["matches"], {})

    def test_invalid_project_metadata_cli_has_no_traceback(self):
        for config in ("mode: {}\n", "mode: []\n", "guardrails: false\n",
                       "mode: workflow_hub\nworkflow_hub: []\n"):
            with self.subTest(config=config):
                self.config.write_text(config)
                proc = subprocess.run([sys.executable, str(helper), "--repo-root", str(self.root)],
                                      input='{"changed_files":[]}', text=True, capture_output=True)
                self.assertEqual(proc.returncode, 2)
                self.assertEqual(proc.stdout, "")
                self.assertNotIn("Traceback", proc.stderr)
                self.assertIn("ERROR:", proc.stderr)

    def test_product_mode_and_no_local_override(self):
        self.config.write_text("mode: product_repo\n" + self.rule_config([("docs/**", "medium", "Project")]))
        (self.root / ".ai-dev-workflow.local.yaml").write_text(self.rule_config([("docs/**", "low", "Machine")]))
        self.assertEqual(self.evaluate()["matches"]["docs/a.md"]["risk"], "medium")

    def test_evidence_boundary_and_untrusted_matches(self):
        for evidence in ([], None, "", {"changed_files": "docs/a.md"}):
            with self.subTest(evidence=evidence), self.assertRaises(module.RiskPathError):
                module.evaluate(self.root, "", evidence)
        for evidence in ({}, {"changed_files": []}, {"changed_files": None}):
            self.assertEqual(module.evaluate(self.root, "", evidence), {"matches": {}})
        self.assertEqual(module.evaluate(self.root, "", {"changed_files": ["docs/a.md"],
                          "risk_path_matches": {"docs/a.md": {"risk": "low"}}}), {"matches": {}})


unittest.main()
PY

"""Behavioral DSH routing tests; no provider calls or real local config reads."""

import importlib.util
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / "scripts/development-workflow/workflow-config-resolver.py"
spec = importlib.util.spec_from_file_location("workflow_resolver", SCRIPT)
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)


class ModelRoutingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.shared = self.root / ".ai-dev-workflow.yaml"
        self.local = self.root / ".ai-dev-workflow.local.yaml"
        self.env = patch.dict(os.environ, {"WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT": ""})
        self.env.start()
        self.addCleanup(self.env.stop)

    def write(self, shared="", local=""):
        self.shared.write_text(shared)
        self.local.write_text(local)

    def policy(self, tiers="", roles=""):
        text = "models:\n  dsh:\n"
        if tiers:
            text += "    tiers:\n" + tiers
        if roles:
            text += "    roles:\n" + roles
        return text

    def tier(self, tier="balanced", provider="base", model="shared", effort=""):
        return (f"      {tier}:\n        provider: {provider}\n        model: {model}\n"
                + (f"        reasoning_effort: {effort}\n" if effort else ""))

    def route(self, role="developer", tier=""):
        return resolver.model_resolution(resolver.load_model_policy(self.root), role, tier)

    def error(self, text, code=None, local=""):
        self.write(text, local)
        with self.assertRaises(resolver.ModelConfigError) as ctx:
            self.route()
        if code:
            self.assertEqual(ctx.exception.diagnostic["CODE"], code)
        return ctx.exception.diagnostic

    def cli(self, *args, **kwargs):
        env = dict(os.environ, WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="")
        return subprocess.run([sys.executable, "-B", str(SCRIPT), *args, "--repo-root", str(self.root)],
                              text=True, capture_output=True, env=env, **kwargs)

    def test_absent_files_and_blocks_are_read_only(self):
        before = list(self.root.iterdir())
        self.assertEqual(self.route()["SOURCE"], "inherited")
        self.assertEqual(before, list(self.root.iterdir()))
        for text in ("mode: single_repo\n", "# models:\n#   dsh:\n", "models:\n  other: value\n"):
            with self.subTest(text=text):
                self.write(text)
                self.assertEqual(self.route()["MODEL"], "")
                self.assertEqual(self.route()["SOURCE_FILE"], "")
                self.assertEqual(self.shared.read_text(), text)

    def test_precedence_and_tier_reference_provenance(self):
        shared = self.policy(self.tier() + self.tier("premium", "base", "premium"))
        self.write(shared)
        self.assertEqual(self.route()["SOURCE"], "committed-tier")
        self.write(shared, self.policy(self.tier(model="private")))
        self.assertEqual(self.route()["SOURCE"], "local-tier")
        shared_role = self.policy(self.tier(), "      developer:\n        provider: role\n        model: direct\n")
        self.write(shared_role, self.policy(self.tier(model="private")))
        self.assertEqual(self.route()["MODEL"], "direct")
        self.assertEqual(self.route()["SOURCE"], "committed-role")
        self.assertEqual(self.route()["TIER"], "")
        self.write(shared_role, self.policy(roles="      developer:\n        provider: local\n        model: private-role\n"))
        self.assertEqual(self.route()["SOURCE"], "local-role")
        self.write(shared, self.policy(roles="      developer: premium\n"))
        self.assertEqual(self.route()["SOURCE"], "committed-tier")
        self.assertEqual(self.route()["SOURCE_FILE"], str(self.shared))
        self.assertEqual(self.route()["TIER"], "premium")
        self.write(shared, self.policy(self.tier("premium", "new", "private"), "      developer: premium\n"))
        self.assertEqual(self.route()["SOURCE"], "local-tier")

    def test_partial_merge_empty_override_and_unrelated_entries(self):
        shared = self.policy(self.tier(effort="high") + self.tier("premium", "p", "premium"))
        local = self.policy("      balanced:\n        provider: private\n")
        self.write(shared, local)
        route = self.route()
        self.assertEqual((route["PROVIDER"], route["MODEL"], route["REASONING_EFFORT"]), ("private", "shared", "high"))
        self.assertEqual(self.route("product-manager")["MODEL"], "premium")
        self.write(shared, self.policy("      balanced: {}\n"))
        self.assertEqual(self.route()["SOURCE"], "committed-tier")
        self.assertEqual(self.route()["SOURCE_FILE"], str(self.shared))
        self.error(self.policy("      balanced: {}\n"), "incomplete_route")

    def test_role_partial_override_and_whole_entry_replacement(self):
        shared = self.policy(self.tier("premium", "p", "premium"), "      developer:\n        provider: role\n        model: direct\n")
        self.write(shared, self.policy(roles="      developer:\n        model: private\n"))
        self.assertEqual((self.route()["PROVIDER"], self.route()["MODEL"], self.route()["SOURCE"]), ("role", "private", "local-role"))
        self.write(shared, self.policy(roles="      developer: premium\n"))
        self.assertEqual(self.route()["MODEL"], "premium")
        self.write(self.policy(roles="      developer: premium\n"), self.policy(roles="      developer:\n        provider: local\n        model: direct\n"))
        self.assertEqual(self.route()["MODEL"], "direct")
        for shared in (self.policy(self.tier(), "      developer: balanced\n"), ""):
            self.write(shared, self.policy(roles="      developer: {}\n"))
            with self.assertRaises(resolver.ModelConfigError) as caught:
                resolver.load_model_policy(self.root)
            self.assertEqual(caught.exception.diagnostic["CODE"], "incomplete_route")
            self.assertEqual(caught.exception.diagnostic["FILE"], str(self.local))

    def test_explicit_tier_is_only_default_and_missing_tier_inherits(self):
        self.write(self.policy(self.tier("premium", "p", "premium")))
        self.assertEqual(self.route(tier="premium")["MODEL"], "premium")
        self.assertEqual(self.route(tier="economy")["SOURCE"], "inherited")
        self.assertEqual(resolver.model_resolution(resolver.load_model_policy(self.root), tier="premium")["ROLE"], "")
        self.write(self.policy(self.tier("premium", "p", "premium"), "      developer:\n        provider: r\n        model: role\n"))
        self.assertEqual(self.route(tier="premium")["MODEL"], "role")

    def test_query_errors_are_structured(self):
        for args, code in ((["--role", "Unknown"], "unknown_role"), (["--tier", "ultra"], "unknown_tier"), ([], "missing_query")):
            with self.subTest(args=args):
                result = self.cli("model-route", "--runner", "dsh", *args, "--json")
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")
                self.assertEqual(json.loads(result.stderr)["CODE"], code)
        result = self.cli("model-route", "--runner", "other", "--role", "developer")
        self.assertEqual(json.loads(result.stderr)["CODE"], "unsupported_runner")

    def test_wrong_types_and_names_in_both_layers_are_not_masked(self):
        valid = self.policy(self.tier(), "      developer:\n        provider: p\n        model: m\n")
        cases = ["models: null\n", "models: []\n", "models:\n  dsh: true\n", "models:\n  dsh: []\n",
                 self.policy("      ultra: {}\n"), self.policy(roles="      Developer: balanced\n"),
                 self.policy(roles="      developer: ultra\n"), self.policy("      balanced: null\n"),
                 self.policy("      balanced: 1\n"), self.policy("      balanced: []\n"),
                 self.policy("      balanced:\n        provider: true\n        model: good\n"),
                 self.policy("      balanced:\n        provider: 12\n        model: good\n"),
                 self.policy("      balanced:\n        provider: good\n        model: good\n        extra: bad\n"),
                 "models:\n  dsh:\n    other: {}\n", "models:\n  dsh:\n    roles: []\n"]
        for invalid in cases:
            with self.subTest(invalid=invalid):
                self.error(invalid, local=valid)
                self.error(valid, local=invalid)

    def test_incomplete_and_empty_ids(self):
        for fields in ("provider: p", "model: m", "provider: ''\n        model: m", "provider: p\n        model: '   '", "provider: p\n        model: m\n        reasoning_effort: ''"):
            self.error(self.policy("      balanced:\n        " + fields + "\n"))
        self.write(self.policy("      balanced:\n        provider: p\n"), self.policy("      balanced:\n        model: m\n"))
        self.assertEqual(self.route()["MODEL"], "m")

    def test_dangling_reference_scope(self):
        self.error(self.policy(roles="      developer: premium\n"), "dangling_reference")
        self.write(self.policy(roles="      developer: premium\n"), self.policy(roles="      developer:\n        provider: p\n        model: m\n"))
        self.assertEqual(self.route()["MODEL"], "m")

    def test_scalar_boundaries_and_control_characters(self):
        self.write(self.policy("      balanced:\n        provider: p # comment\n        model: 'id#literal'\n"))
        self.assertEqual(self.route()["MODEL"], "id#literal")
        for escaped in ("\\n", "\\r", "\\t", "\\u0085", "\\u2028"):
            self.error(self.policy(f'      balanced:\n        provider: p\n        model: "m{escaped}x"\n'), "invalid_value")

    def test_strict_yaml_and_safe_parser_diagnostics(self):
        cases = [self.policy(self.tier() + self.tier()),
                 "models:\n  dsh: {tiers: {balanced: {provider: p, model: m}}}\n",
                 "models:\n  dsh: &anchor {}\n", "models:\n  dsh: *alias\n",
                 "models:\n  dsh: !tag {}\n", "'models':\n  dsh: {}\n",
                 "models:\n   dsh: {}\n", 'models:\n  dsh:\n    tiers:\n      balanced:\n        model: [PRIVATE_TEST_SENTINEL\n']
        for invalid in cases:
            with self.subTest(invalid=invalid):
                diagnostic = self.error(invalid, "invalid_yaml")
                self.assertNotIn("PRIVATE_TEST_SENTINEL", json.dumps(diagnostic))
                result = self.cli("model-route", "--runner", "dsh", "--role", "developer", "--json")
                self.assertEqual(result.returncode, 2)
                self.assertNotIn("PRIVATE_TEST_SENTINEL", result.stdout + result.stderr)

    def test_reader_consistent_line_breaks(self):
        for newline in ("\r\n", "\u0085", "\u2028", "\u2029"):
            self.write(self.policy(self.tier()).replace("\n", newline))
            self.assertEqual(self.route()["MODEL"], "shared")

    def test_local_discovery_checkout_main_clone_and_override_root(self):
        main = self.root / "main"
        checkout = self.root / "linked"
        override = self.root / "override"
        for directory in (main / ".git/worktrees/w", checkout, override):
            directory.mkdir(parents=True)
        (checkout / ".git").write_text(f"gitdir: {main}/.git/worktrees/w\n")
        (main / resolver.LOCAL_CONFIG_NAME).write_text(self.policy(self.tier(model="main")))
        self.assertEqual(resolver.model_resolution(resolver.load_model_policy(checkout), "developer")["MODEL"], "main")
        (checkout / resolver.LOCAL_CONFIG_NAME).write_text(self.policy(self.tier(model="checkout")))
        self.assertEqual(resolver.model_resolution(resolver.load_model_policy(checkout), "developer")["MODEL"], "checkout")
        (override / resolver.LOCAL_CONFIG_NAME).write_text(self.policy(self.tier(model="override")))
        with patch.dict(os.environ, WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT=str(override)):
            self.assertEqual(resolver.model_resolution(resolver.load_model_policy(checkout), "developer")["MODEL"], "override")

    def test_listing_deduplicates_routes_but_preserves_records_and_unused_tiers(self):
        roles = "".join(f"      {role}: balanced\n" for role in resolver.DSH_ROLE_TIERS)
        self.write(self.policy(self.tier() + self.tier("premium", "p", "unused"), roles))
        result = self.cli("model-routes", "--runner", "dsh", "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(len(payload["RESOLUTIONS"]), 15)
        self.assertEqual(len(payload["ROUTES"]), 2)
        self.assertIn("unused", [route["MODEL"] for route in payload["ROUTES"]])
        shared = self.shared.read_text()
        self.local.write_text(self.policy(roles="      developer:\n        provider: base\n        model: shared\n        reasoning_effort: high\n"))
        payload = json.loads(self.cli("model-routes", "--runner", "dsh", "--json").stdout)
        self.assertEqual(len(payload["ROUTES"]), 3)  # distinct effort tuples remain
        self.assertEqual(self.shared.read_text(), shared)

    def test_shell_output_equivalent_to_json_and_safe_quoting(self):
        self.write(self.policy(self.tier(model="'id with spaces#hash'")))
        raw = self.cli("model-route", "--runner", "dsh", "--role", "developer").stdout
        shell = dict(line.split("=", 1) for line in raw.splitlines())
        shell = {key: (shlex.split(value)[0] if value else "") for key, value in shell.items()}
        payload = json.loads(self.cli("model-route", "--runner", "dsh", "--role", "developer", "--json").stdout)
        self.assertEqual(shell, payload)

    def test_validate_parity_and_malformed_opt_in_boundary(self):
        for text in (self.policy("      balanced:\n        provider: p\n"),
                     "'models':\n  dsh: {}\n", '"models":\n  "dsh": {}\n',
                     '"\\u006dodels":\n  dsh: {}\n',
                     '"\\x6dodels":\n  dsh: {}\n', '"\\U0000006dodels":\n  dsh: {}\n',
                     'models: {"\\x64sh": {}}\n',
                     "models:\n   dsh: {}\n", " models:\n   dsh: {}\n",
                     "models\n  dsh: {}\n", "models:\n  dsh [broken\n",
                     "models: {dsh: {tiers: {}}}\n",
                     "models: !!map {dsh: {tiers: {balanced: {provider: p}}}}\n",
                     "models: &policy {dsh: {}}\n",
                     "policy: &policy {dsh: {}}\nmodels: *policy\n",
                     "policy: unrelated\nactual: &policy {dsh: {}}\nmodels: *policy\n",
                     'decoy: "some &policy text"\nactual: &policy {dsh: {}}\nmodels: *policy\n',
                     'decoy: some &policy text\nactual: {inner: &policy {dsh: {}}}\nmodels: *policy\n',
                     "policy: &policy\n  dsh: {}\nmodels: *policy\n",
                     "policy:\n  dsh: {}\nmodels: *policy\n",
                     self.policy(self.tier()).replace("\n", "\u2028")):
            with self.subTest(text=text):
                self.write(text)
                route = self.cli("model-route", "--runner", "dsh", "--role", "developer", "--json")
                validate = self.cli("validate", "--json")
                self.assertEqual(validate.returncode, route.returncode, validate.stderr)
                if route.returncode:
                    self.assertEqual(json.loads(validate.stderr), json.loads(route.stderr))
                else:
                    self.assertEqual(json.loads(validate.stdout)["WORKFLOW_MODE"], "single_repo")
        self.write('models:\n  dsh:\n    tiers:\n      balanced:\n        model: [PRIVATE_TEST_SENTINEL\n')
        result = self.cli("validate")
        self.assertNotIn("PRIVATE_TEST_SENTINEL", result.stderr + result.stdout)
        self.assertEqual(json.loads(result.stderr)["CODE"], "invalid_yaml")

    def test_absent_validate_has_no_new_dependency_or_grammar(self):
        for text in ("mode: single_repo\n", "# models:\n#   dsh: {}\n", "models:\n  other:\n    dsh: unused\n",
                     'models: {other: {dsh: unused}}\n', 'models: {other: "dsh: unused"}\n',
                     'custom:\n  models:\n    dsh: unused\n',
                     'custom:\n  models: {dsh: unused}\n',
                     'models: !!map {other: unused}\n',
                     'policy: &policy {other: {dsh: unused}}\nmodels: *policy\n',
                     'actual: {inner: &policy {other: unused}, sibling: {dsh: unused}}\nmodels: *policy\n'):
            self.write(text)
            absent = subprocess.run([sys.executable, "-S", str(SCRIPT), "validate", "--repo-root", str(self.root), "--json"],
                                    capture_output=True, text=True, env=dict(os.environ, WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT=""))
            self.assertEqual(absent.returncode, 0, absent.stderr)
            self.assertEqual(absent.stdout, self.cli("resolve", "--json").stdout)
        self.write(self.policy(self.tier()))
        opted_in = subprocess.run([sys.executable, "-S", str(SCRIPT), "validate", "--repo-root", str(self.root)],
                                 capture_output=True, text=True, env=dict(os.environ, WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT=""))
        self.assertEqual(opted_in.returncode, 2)
        self.assertEqual(json.loads(opted_in.stderr)["CODE"], "dependency_missing")

    def test_role_catalogue_matches_canonical_table(self):
        text = (ROOT / "docs/workflow/development-workflow/agent-model-config.md").read_text()
        table = text.split("## Agent Assignments (Tier-Based)", 1)[1].split("### Runner Notes", 1)[0]
        entries = dict(re.findall(r"\| `([^`]+)`\s*\| `(economy|balanced|premium)`", table))
        self.assertEqual(entries, resolver.DSH_ROLE_TIERS)
        self.assertEqual(len(entries), 12)


if __name__ == "__main__":
    unittest.main()

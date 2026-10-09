"""Behavioral DSH routing tests; no provider calls or real local config reads."""

import importlib.util
import json
import os
import re
import random
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
        self.root = Path(self.temp.name).resolve()
        self.shared = self.root / ".ai-dev-workflow.yaml"
        self.local = self.root / ".ai-dev-workflow.local.yaml"
        self.env = patch.dict(os.environ, {"WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT": ""})
        self.env.start()
        self.addCleanup(self.env.stop)

    def write(self, shared="", local=""):
        self.shared.write_text(shared)
        self.local.write_text(local)

    def envelope(self, text):
        if text.startswith(resolver.MODEL_ENVELOPE_PREFIX):
            return text
        return resolver.MODEL_ENVELOPE_OPEN + "\n" + text + resolver.MODEL_ENVELOPE_END + "\n"

    def policy(self, tiers="", roles=""):
        text = "models:\n  dsh:\n"
        if tiers:
            text += "    tiers:\n" + tiers
        if roles:
            text += "    roles:\n" + roles
        return self.envelope(text)

    def tier(self, tier="balanced", provider="base", model="shared", effort=""):
        return (f"      {tier}:\n        provider: {provider}\n        model: {model}\n"
                + (f"        reasoning_effort: {effort}\n" if effort else ""))

    def route(self, role="developer", tier=""):
        return resolver.model_resolution(resolver.load_model_policy(self.root), role, tier)

    def error(self, text, code=None, local=""):
        self.write(self.envelope(text), self.envelope(local) if local else "")
        with self.assertRaises(resolver.ModelConfigError) as ctx:
            self.route()
        if code:
            self.assertEqual(ctx.exception.diagnostic["CODE"], code)
        return ctx.exception.diagnostic

    def cli(self, *args, **kwargs):
        env = kwargs.pop("env", dict(os.environ, WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT=""))
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
        self.write(self.policy("      balanced:\n        provider: p\n        model: 'literal &anchor *alias <<: text'\n"))
        self.assertEqual(self.route()["MODEL"], "literal &anchor *alias <<: text")
        for escaped in ("\\n", "\\r", "\\t", "\\u0085", "\\u2028"):
            self.error(self.policy(f'      balanced:\n        provider: p\n        model: "m{escaped}x"\n'), "invalid_yaml")

    def test_strict_yaml_and_safe_parser_diagnostics(self):
        cases = [self.policy(self.tier() + self.tier()),
                 "models:\n  dsh: {tiers: {balanced: {provider: p, model: m}}}\n",
                 "models:\n  dsh: &anchor {}\n", "models:\n  dsh: *alias\n",
                 "models:\n  dsh:\n    <<: {}\n",
                 "models:\n  dsh:\n    tiers:\n      balanced: &route\n        provider: p\n        model: m\n",
                 "models:\n  dsh:\n    roles:\n      developer: *route\n",
                 "models:\n  dsh: !tag {}\n", "'models':\n  dsh: {}\n",
                 "models:\n   dsh: {}\n", 'models:\n  dsh:\n    tiers:\n      balanced:\n        model: [PRIVATE_TEST_SENTINEL\n']
        for invalid in cases:
            with self.subTest(invalid=invalid):
                diagnostic = self.error(invalid, "invalid_yaml")
                self.assertNotIn("PRIVATE_TEST_SENTINEL", json.dumps(diagnostic))
                result = self.cli("model-route", "--runner", "dsh", "--role", "developer", "--json")
                self.assertEqual(result.returncode, 2)
                self.assertNotIn("PRIVATE_TEST_SENTINEL", result.stdout + result.stderr)
                self.assertIn("BR9 block mappings", diagnostic["MESSAGE"])
                for command in (("model-routes", "--runner", "dsh", "--json"), ("validate", "--json")):
                    parity = self.cli(*command)
                    self.assertEqual(parity.returncode, 2)
                    self.assertEqual(json.loads(parity.stderr), json.loads(result.stderr))
                    self.assertEqual(parity.stdout, "")

    def test_reader_consistent_line_breaks(self):
        for newline in ("\n", "\r\n"):
            self.write(self.policy(self.tier()).replace("\n", newline))
            self.assertEqual(self.route()["MODEL"], "shared")
        for char in ("\u0085", "\u2028", "\u2029", "\t", "\x00"):
            self.error(self.policy(self.tier(model="'id" + char + "x'")), "invalid_yaml")

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

    def assert_parity_error(self, text, code, local=""):
        self.write(text, local)
        commands = (("validate", "--json"),
                    ("model-route", "--runner", "dsh", "--role", "developer", "--json"),
                    ("model-routes", "--runner", "dsh", "--json"))
        results = [self.cli(*command) for command in commands]
        results.append(subprocess.run(["bash", str(ROOT / "scripts/development-workflow/validate-workflow-config.sh"),
                                       "--repo-root", str(self.root)],
                                      capture_output=True, text=True, env=dict(os.environ)))
        expected = None
        for result in results:
            self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
            self.assertEqual(result.stdout, "")
            diagnostic = json.loads(result.stderr)
            self.assertEqual(set(diagnostic), {"CODE", "FILE", "FIELD", "MESSAGE"})
            self.assertEqual(diagnostic["CODE"], code)
            self.assertEqual(diagnostic["FILE"], str((self.shared if text else self.local).resolve()))
            self.assertNotIn("PRIVATE_TEST_SENTINEL", result.stderr)
            if expected is None:
                expected = diagnostic
            self.assertEqual(diagnostic, expected)
        return expected

    def test_declared_malformed_corpus_rejects_with_identical_diagnostics(self):
        syntax = [
            "models:\n- dsh: {}\n", "models:\n  - dsh: {}\n",
            "models:\n  - other: {}\n    dsh: null\n", "models:\n  - dsh: {}\n  -\n",
            "models: [{dsh: {}}\n", "models: {dsh: {}\n",
            "models: [{dsh: {}},\n", "models: {dsh: {},\n",
            "models: [{dsh: {}},]\n", "models: {dsh: {},}\n",
            "models: dsh: {}\n", "models: &x{}\n", "models: [ ]\n",
            "models:\n  dsh: &policy {}\n", "models:\n  dsh: *policy\n",
            "models:\n  dsh:\n    <<: {}\n", "models:\n  dsh: !tag {}\n",
            "---\nmodels: {}\n", "%YAML 1.2\nmodels: {}\n",
            "models:\n  dsh: |\n    PRIVATE_TEST_SENTINEL\n",
            "models:\n  dsh: >\n    text\n", "models:\n   dsh: {}\n",
            "models:\n    dsh: {}\n", "models:\n\tdsh: {}\n",
            "models:\n  dsh: {}\n  dsh: {}\n", "'models': {}\n",
            self.policy(self.tier(model='"unterminated')),
            self.policy(self.tier(model='"bad\\n"')),
            self.policy(self.tier(model="'ok'junk")),
            self.policy(self.tier(model="id#no-space")),
            self.policy(self.tier(model="'one\ntwo'")),
            self.policy(self.tier(model='"PRIVATE_TEST_SENTINEL\\u0000"')),
        ]
        typed = ["models: null\n", "models:\n  dsh: null\n", "models:\n  dsh: true\n",
                 "models:\n  dsh: plain\n", "models:\n  dsh:\n    tiers: 1\n",
                 "models:\n  dsh:\n    roles: false\n", "models:\n  dsh:\n",
                 self.policy("      balanced: null\n"),
                 *[self.policy(self.tier(model=x)) for x in ("NULL", "~", "TRUE", "False", "12", "-1", ".5", "1.", "1e3", "+.5e-2")]]
        schema = [(self.policy("      ultra: {}\n"), "unknown_name"),
                  (self.policy(roles="      Developer: balanced\n"), "unknown_name"),
                  (self.policy(roles="      developer: ultra\n"), "unknown_name"),
                  (self.policy(self.tier() + "        extra: value\n"), "unknown_field"),
                  ("models:\n  other: {}\n", "unknown_field"),
                  (self.policy(self.tier(model="''")), "invalid_value"),
                  (self.policy("      balanced: {}\n"), "incomplete_route"),
                  (self.policy(roles="      developer: premium\n"), "dangling_reference")]
        for raw, code in [(x, "invalid_yaml") for x in syntax] + [(x, "invalid_type") for x in typed] + schema:
            active = self.envelope(raw)
            with self.subTest(raw=raw, layer="shared"):
                self.assert_parity_error(active, code)
            with self.subTest(raw=raw, layer="local"):
                self.assert_parity_error("", code, active)
        # Retain the historical shapes without guessing activation from their text.
        for raw in syntax[:16] + typed[:6]:
            with self.subTest(inactive=raw):
                self.write(raw)
                legacy = self.cli("resolve", "--json")
                validation = self.cli("validate", "--json")
                self.assertEqual((validation.returncode, validation.stdout, validation.stderr),
                                 (legacy.returncode, legacy.stdout, legacy.stderr))

    def test_envelope_errors_have_three_command_and_wrapper_parity(self):
        valid = self.policy(self.tier())
        cases = [valid.replace(": v1", ": v2", 1), valid.replace(": v1", ":v1", 1),
                 "\ufeff" + valid, valid.replace(resolver.MODEL_ENVELOPE_END, ""),
                 valid + resolver.MODEL_ENVELOPE_END + "\n", valid + valid,
                 valid + "models: {}\n", resolver.MODEL_ENVELOPE_END + "\nmodels: {}\n"]
        for text in cases:
            with self.subTest(text=text):
                self.assert_parity_error(text, "invalid_envelope")
        self.assert_parity_error(valid + " PRIVATE_TEST_SENTINEL\n", "invalid_yaml")
        self.shared.write_bytes((resolver.MODEL_ENVELOPE_OPEN + "\nmodels: {}\n").encode() + b"\xff")
        for command in (("validate",), ("model-route", "--runner", "dsh", "--role", "developer"),
                        ("model-routes", "--runner", "dsh")):
            result = self.cli(*command)
            self.assertEqual(json.loads(result.stderr)["CODE"], "invalid_yaml")

    def test_commands_share_one_policy_loader_snapshot_and_parse_per_layer(self):
        commands = (("validate", "--json"),
                    ("model-route", "--runner", "dsh", "--role", "developer", "--json"),
                    ("model-routes", "--runner", "dsh", "--json"))
        for active in (False, True):
            self.write(self.policy(self.tier()) if active else "mode: single_repo\n",
                       self.policy(self.tier(model="local")) if active else "")
            for command in commands:
                args = resolver.build_parser().parse_args([*command, "--repo-root", str(self.root)])
                original_read = Path.read_bytes
                reads = []
                def observed(path):
                    reads.append(path)
                    return original_read(path)
                with self.subTest(active=active, command=command), \
                        patch.object(resolver, "load_model_policy", wraps=resolver.load_model_policy) as loader, \
                        patch.object(resolver, "parse_model_mapping", wraps=resolver.parse_model_mapping) as parser, \
                        patch.object(resolver, "parse_review_yaml", side_effect=AssertionError("YAML dependency used")), \
                        patch.object(Path, "read_bytes", observed), patch("builtins.print"):
                    self.assertEqual(args.func(args), 0)
                    loader.assert_called_once_with(self.root.resolve())
                    self.assertEqual(parser.call_count, 2 if active else 0)
                    self.assertEqual(reads, [self.shared.resolve(), self.local.resolve()])
        self.write(self.policy(self.tier()))
        policy = resolver.load_model_policy(self.root)
        self.assertEqual(policy.positions[0]["models.dsh.tiers.balanced.model"], 7)
        with self.assertRaises(TypeError):
            policy.configs[0]["mode"] = "changed"
        with self.assertRaises(TypeError):
            policy.effective["tiers"]["balanced"]["model"] = "changed"

    def test_deep_legacy_snapshots_preserve_depth_and_active_error_boundary(self):
        value = {"leaf": "kept"}
        for _ in range(1500):
            value = {"child": [value]}
        frozen = resolver.freeze_model_mapping(value)
        thawed = resolver.thaw_model_snapshot(frozen)
        for _ in range(1500):
            with self.assertRaises(TypeError):
                frozen["child"] = "changed"
            self.assertIsInstance(frozen["child"], tuple)
            self.assertIsInstance(thawed["child"], list)
            frozen, thawed = frozen["child"][0], thawed["child"][0]
        self.assertEqual(dict(frozen), {"leaf": "kept"})
        self.assertEqual(thawed, {"leaf": "kept"})

        def legacy(depth):
            return ("mode: single_repo\n" + "".join("  " * i + "nested:\n" for i in range(depth))
                    + "  " * depth + "leaf: kept\n")
        commands = (("validate", "--json"),
                    ("model-route", "--runner", "dsh", "--role", "developer", "--json"),
                    ("model-routes", "--runner", "dsh", "--json"))
        for active in (False, True):
            self.write((self.envelope("models: {}\n") if active else "") + legacy(600))
            reference = self.cli("resolve", "--json")
            self.assertEqual(reference.returncode, 0, reference.stderr)
            for command in commands:
                result = self.cli(*command)
                self.assertEqual(result.returncode, 0, result.stderr)
                if command[0] == "validate":
                    self.assertEqual((result.stdout, result.stderr), (reference.stdout, reference.stderr))
        for layer in ("shared", "local"):
            self.write("", "")
            (self.shared if layer == "shared" else self.local).write_text(
                self.envelope("models: {}\n") + legacy(1500))
            diagnostics = []
            for command in commands:
                result = self.cli(*command)
                self.assertEqual((result.returncode, result.stdout), (2, ""))
                diagnostics.append(json.loads(result.stderr))
            self.assertEqual(diagnostics, [diagnostics[0]] * len(commands))
            self.assertEqual(diagnostics[0]["CODE"], "invalid_yaml")
            self.assertNotIn("Traceback", diagnostics[0]["MESSAGE"])
            wrapper = subprocess.run(["bash", str(ROOT / "scripts/development-workflow/validate-workflow-config.sh"),
                                      "--repo-root", str(self.root)], capture_output=True, text=True,
                                     env=dict(os.environ, WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT=""))
            self.assertEqual((wrapper.returncode, wrapper.stdout), (2, ""))
            self.assertEqual(json.loads(wrapper.stderr), diagnostics[0])

    def test_defined_quotes_types_comments_and_bounded_generative_lexer(self):
        cases = [("'it''s'", "it's"), (r'"a\\b\"c"', 'a\\b"c'),
                 ("'literal\\n'", "literal\\n"), ("'&x *x << # literal'", "&x *x << # literal"),
                 ("'雪'", "雪"), ('"null"', "null"), ("'12'", "12"),
                 *[(x, x) for x in ("yes", "no", "on", "off", "p/m:v@tag+id-1")]]
        for value, expected in cases:
            with self.subTest(value=value):
                self.write(self.policy(self.tier(model=value + " # comment")))
                self.assertEqual(self.route()["MODEL"], expected)
        for empty in ("models: {}\n", "models:\n  dsh: {}\n",
                      "models:\n  dsh:\n    tiers: {}\n    roles: {}\n"):
            self.write(self.envelope(empty))
            self.assertEqual(self.route()["SOURCE"], "inherited")
        rng = random.Random(1927)
        for index in range(40):
            value = "".join(rng.choice("ab #&*<>雪'\\") for _ in range(12))
            encoded = "'" + value.replace("'", "''") + "'"
            with self.subTest(index=index):
                self.write(self.policy(self.tier(model=encoded)))
                self.assertEqual(self.route()["MODEL"], value)
                self.error(self.policy(self.tier(model=encoded + rng.choice((",", "]", "}", "x")))), "invalid_yaml")
        # Invalid query cannot mask malformed selected policy.
        self.write(self.envelope("models:\n- dsh: {}\n"))
        self.assertEqual(json.loads(self.cli("model-route", "--runner", "dsh", "--role", "Unknown").stderr)["CODE"], "invalid_yaml")

    def test_set_local_path_preserves_active_bytes_and_rejects_before_write(self):
        policy = self.policy(self.tier(model="local")).replace("\n", "\r\n")
        tail = "product_repos:\n  - name: app\n    local_path: before\n"
        self.write("mode: workflow_hub\nworkflow_hub:\n  product_repos:\n    - name: app\n      github_repo: example/app\n", policy + tail)
        before = self.route()
        result = self.cli("set-local-path", "--repo", "app", "--local-path", str(self.root / "after"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(self.local.read_bytes().startswith(policy.encode()))
        self.assertEqual(self.route(), before)
        self.assertIn("local_path: after", self.local.read_text())
        for raw in ("models:\n- dsh: {}\n", "models:\n  dsh: null\n"):
            self.local.write_text(self.envelope(raw) + tail)
            before_bytes = self.local.read_bytes()
            result = self.cli("set-local-path", "--repo", "app", "--local-path", "after")
            self.assertEqual(result.returncode, 2)
            self.assertEqual(self.local.read_bytes(), before_bytes)

    def test_opted_in_discovery_error_parity_preserves_absent_legacy(self):
        missing = self.root / "PRIVATE_TEST_SENTINEL_missing"
        with patch.dict(os.environ, WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT=str(missing)):
            self.write(self.policy(self.tier()))
            route = self.cli("model-route", "--runner", "dsh", "--role", "developer", "--json",
                             env=dict(os.environ))
            validate = self.cli("validate", "--json", env=dict(os.environ))
            self.assertEqual(route.returncode, 2)
            self.assertEqual(validate.returncode, 2)
            self.assertEqual(json.loads(validate.stderr), json.loads(route.stderr))
            self.assertEqual(json.loads(validate.stderr)["CODE"], "config_discovery")
            self.assertNotIn("PRIVATE_TEST_SENTINEL", validate.stderr)
            missing.mkdir()
            self.assertEqual(self.cli("validate", "--json", env=dict(os.environ)).returncode, 0)
            self.assertEqual(self.cli("model-route", "--runner", "dsh", "--role", "developer", "--json",
                                      env=dict(os.environ)).returncode, 0)
            self.write("mode: single_repo\n")
            absent_env = dict(os.environ, WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT=str(self.root / "another-missing"))
            validate = self.cli("validate", "--json", env=absent_env)
            resolve = self.cli("resolve", "--json", env=absent_env)
            self.assertEqual(validate.returncode, resolve.returncode)
            self.assertEqual(validate.stderr, resolve.stderr)

    def test_unactivated_discovery_error_preserves_legacy_precedence(self):
        env = dict(os.environ, WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT=str(self.root / "missing"))
        for raw in (b"BROKEN_LEGACY_TOKEN\n", b"\xff", b"models:\n- dsh: {}\n", b"mode: single_repo\n"):
            self.shared.write_bytes(raw)
            with self.subTest(raw=raw):
                legacy = self.cli("resolve", "--json", env=env)
                self.assertEqual(legacy.returncode, 2)
                for command in (("validate", "--json"),
                                ("model-route", "--runner", "dsh", "--role", "developer", "--json"),
                                ("model-routes", "--runner", "dsh", "--json")):
                    result = self.cli(*command, env=env)
                    self.assertEqual((result.returncode, result.stdout, result.stderr),
                                     (legacy.returncode, legacy.stdout, legacy.stderr))
        self.shared.write_text(self.envelope("models:\n  dsh: null\n"))
        for command in (("validate",), ("model-route", "--runner", "dsh", "--role", "developer"),
                        ("model-routes", "--runner", "dsh")):
            result = self.cli(*command, env=env)
            self.assertEqual(json.loads(result.stderr)["CODE"], "invalid_type")

    def test_absent_validate_has_no_new_dependency_or_grammar(self):
        for text in ("mode: single_repo\n", "# models:\n#   dsh: {}\n", "models:\n  other:\n    dsh: unused\n",
                     'models: {other: {dsh: unused}}\n',
                     'models:\n  - other:\n      dsh: unused\n',
                     'models: [{other: {dsh: unused}}]\n',
                     'models: [{other: {dsh: unused}}\n',
                     'policy: &policy [{other: {dsh: unused}}]\nmodels: *policy\n',
                     'policy: &policy [*policy]\nmodels: *policy\n',
                     'models: ["dsh: unused", {other: unused}]\n', 'models: {other: "dsh: unused"}\n',
                     'custom:\n  models:\n    dsh: unused\n',
                     'custom:\n  models: {dsh: unused}\n',
                     'models: !!map {other: unused}\n',
                     'models: !<tag:example.org,2002:map> {other: unused}\n',
                     'policy: &policy {other: {dsh: unused}}\nmodels: *policy\n',
                     'actual: {inner: &policy {other: unused}, sibling: {dsh: unused}}\nmodels: *policy\n',
                     'holder: {first: &route {codex: {}}, second: &route {other: {}}}\nmodels: *route\n',
                     'route: &route {other: {dsh: unused}}\nmodels: {<<: *route}\n',
                     'first: &a *b\nsecond: &b *a\nmodels: *a\n',
                     '{mode: single_repo, models: {other: {dsh: unused}}}\n',
                     '{mode: single_repo, custom: {models: {dsh: unused}}}\n'):
            self.write(text)
            absent = subprocess.run([sys.executable, "-S", str(SCRIPT), "validate", "--repo-root", str(self.root), "--json"],
                                    capture_output=True, text=True, env=dict(os.environ, WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT=""))
            legacy = self.cli("resolve", "--json")
            self.assertEqual(absent.returncode, legacy.returncode, absent.stderr)
            self.assertEqual(absent.stdout, legacy.stdout)
            self.assertEqual(absent.stderr, legacy.stderr)
        self.write(self.policy(self.tier()))
        opted_in = subprocess.run([sys.executable, "-S", str(SCRIPT), "validate", "--repo-root", str(self.root)],
                                 capture_output=True, text=True, env=dict(os.environ, WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT=""))
        self.assertEqual(opted_in.returncode, 0, opted_in.stderr)

    def test_role_catalogue_matches_canonical_table(self):
        text = (ROOT / "docs/workflow/development-workflow/agent-model-config.md").read_text()
        table = text.split("## Agent Assignments (Tier-Based)", 1)[1].split("### Runner Notes", 1)[0]
        entries = dict(re.findall(r"\| `([^`]+)`\s*\| `(economy|balanced|premium)`", table))
        self.assertEqual(entries, resolver.DSH_ROLE_TIERS)
        self.assertEqual(len(entries), 12)


if __name__ == "__main__":
    unittest.main()

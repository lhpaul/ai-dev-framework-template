#!/usr/bin/env python3
# covers: scripts/development-workflow/resolve-reviewer-availability.sh
# covers: scripts/development-workflow/workflow-config-resolver.py
# covers: scripts/development-workflow/reviewer_preflight_build_input.py
"""Synthetic Step 7a selection: no provider or GitHub requests are possible."""
import importlib.util
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("resolver", SCRIPTS / "workflow-config-resolver.py")
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)


class ReviewerSelection(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="codex-reviewer-selection-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.repo = self.root / "synthetic repository"
        self.repo.mkdir()
        self.config = self.repo / ".ai-dev-workflow.yaml"
        self.local = self.repo / ".ai-dev-workflow.local.yaml"
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.log = self.root / "probes.log"
        for command in ("bash", "sh", "cat", "chmod", "date", "dirname", "jq", "mktemp", "perl", "rm", "sleep"):
            executable = shutil.which(command)
            if executable:
                (self.bin / command).symlink_to(executable)
        self.fake("python3", "exec " + shlex.quote(sys.executable) + ' "$@"')
        self.env = {key: value for key, value in os.environ.items()
                    if not key.startswith(("WORKFLOW_", "AI_DEV_", "CODEX_GITHUB_"))}
        self.env.update(PATH=str(self.bin), TMPDIR=str(self.root), PYTHONDONTWRITEBYTECODE="1")
        self.config.write_text("review: {}\n")

    def fake(self, name, body):
        path = self.bin / name
        path.write_text("#!/bin/bash\nprintf '%s %s\\n' " + shlex.quote(name)
                        + ' "$*" >> ' + shlex.quote(str(self.log)) + "\n" + body + "\n")
        path.chmod(0o755)

    def configure(self, primary="[claude]", fallback="codex", policy="warn"):
        self.config.write_text(f"review:\n  on_draft:\n    runner: {primary}\n"
                               f"    fallback_runner: {fallback}\n"
                               f"  internal_reviewers_unavailable_policy: {policy}\n")

    def run_gate(self, driver="codex", expected=0):
        result = subprocess.run(["/bin/bash", str(SCRIPTS / "resolve-reviewer-availability.sh"),
                                 "--repo-root", str(self.repo), "--owner", "synthetic", "--repo", "fixture",
                                 "--runner-kind", driver], env=self.env, capture_output=True,
                                text=True, timeout=12)
        self.assertEqual(result.returncode, expected, result.stdout + result.stderr)
        return dict(line.split("=", 1) for line in result.stdout.splitlines())

    def test_default_codex_independent_of_driving_runner(self):
        self.fake("codex", 'test "$1" = --version')
        for driver in ("claude", "cursor", "dsh", "codex", "unknown"):
            with self.subTest(driver=driver):
                gate = self.run_gate(driver)
                self.assertEqual(gate["REACHABLE"], "codex")
                self.assertEqual(gate["FALLBACK_REASON"], "default-codex")
                self.assertEqual(gate["REVIEWER_COUNT"], "1")

    def test_configured_primary_keeps_precedence(self):
        self.configure(primary="[claude]")
        gate = self.run_gate("claude")
        self.assertEqual(gate["REACHABLE"], "claude")
        self.assertEqual(gate["FALLBACK_APPLIED"], "false")
        self.assertEqual(gate["REVIEWER_COUNT"], "1")

    def test_missing_primary_requires_explicit_fallback(self):
        self.configure(fallback="null")
        gate = self.run_gate(expected=1)
        self.assertEqual(gate["BLOCK_CAUSE"], "zero-reachable")
        self.configure()
        gate = self.run_gate()
        self.assertEqual(gate["OUTCOME"], "proceeded-reduced")
        self.assertEqual(gate["REVIEWER_1_REASON"], "runtime-absent")
        self.assertEqual(gate["REVIEWER_2_NAME"], "codex")
        self.assertEqual(gate["REACHABLE"], "codex")
        self.assertEqual(gate["FALLBACK_REASON"], "primary-unavailable")

    def test_missing_codex_can_use_explicit_claude_fallback(self):
        self.configure(primary="[]", fallback="claude")
        gate = self.run_gate("claude")
        self.assertEqual(gate["REVIEWER_1_NAME"], "codex")
        self.assertEqual(gate["REACHABLE"], "claude")
        self.assertEqual(gate["FALLBACK_REASON"], "primary-unavailable")

    def test_strict_policy_does_not_allow_substitution(self):
        self.configure(policy="fail-if-any-unavailable")
        gate = self.run_gate(expected=1)
        self.assertEqual(gate["OUTCOME"], "blocked")
        self.assertEqual(gate["REVIEWER_COUNT"], "1")
        self.assertEqual(gate["FALLBACK_APPLIED"], "false")

    def test_no_fallback_for_partial_coverage_or_inconclusive_probe(self):
        self.configure(primary="[claude,codex]", fallback="cursor")
        gate = self.run_gate()
        self.assertEqual(gate["REACHABLE"], "codex")
        self.assertEqual(gate["REVIEWER_COUNT"], "2")
        self.assertEqual(gate["FALLBACK_APPLIED"], "false")
        self.configure()
        self.fake("claude", "exit 1")
        gate = self.run_gate(expected=1)
        self.assertEqual(gate["REVIEWER_1_REASON"], "check-inconclusive")
        self.assertEqual(gate["REVIEWER_COUNT"], "1")

    def test_no_retry_of_primary_and_unavailable_fallback_blocks(self):
        self.configure(fallback="claude")
        gate = self.run_gate(expected=1)
        self.assertEqual(gate["REVIEWER_COUNT"], "1")
        self.configure(fallback="cursor")
        gate = self.run_gate(expected=1)
        self.assertEqual(gate["BLOCK_CAUSE"], "zero-reachable")
        self.assertEqual(gate["REVIEWER_2_REASON"], "runtime-absent")

    def test_malformed_fallback_fails_before_probing_and_hides_value(self):
        for invalid in ("[]", "[codex]", "false", "coderabbit", "fabricated-opaque-value"):
            with self.subTest(invalid=invalid):
                self.configure(fallback=invalid)
                gate = self.run_gate(expected=1)
                self.assertEqual(gate["BLOCK_CAUSE"], "fallback-malformed")
                self.assertEqual(gate["REVIEWER_COUNT"], "0")
                self.assertNotIn("fabricated-opaque-value", json.dumps(gate))
        self.configure(primary="[unsupported]")
        gate = self.run_gate(expected=1)
        self.assertEqual(gate["REVIEWER_1_REASON"], "value-not-supported")
        self.assertEqual(gate["REVIEWER_COUNT"], "1")

    def test_local_fallback_override_disable_and_review_projection(self):
        self.configure(fallback="cursor")
        self.local.write_text("review:\n  on_draft:\n    fallback_runner: codex\n")
        self.assertEqual(self.run_gate()["REACHABLE"], "codex")
        settings = resolver.project_review_settings(
            {"review": {"on_draft": {"fallback_runner": "codex"}}, "private": "synthetic-only"}, self.local)
        self.assertEqual(settings, {"review": {"on_draft": {"fallback_runner": "codex"}}})
        self.local.write_text("review:\n  on_draft:\n    fallback_runner: null\n")
        self.assertEqual(self.run_gate(expected=1)["FALLBACK_CONFIG_STATE"], "empty")
        for invalid in ([], True, "fabricated-opaque-value"):
            with self.assertRaises(resolver.ConfigError):
                resolver.project_review_settings({"review": {"on_draft": {"fallback_runner": invalid}}}, self.local)

    def test_review_failure_is_not_an_availability_probe(self):
        self.configure(primary="[codex]", fallback="claude")
        # This fake would fail any actual review, while --version is available.
        self.fake("codex", 'if [ "$1" = --version ]; then exit 0; fi; exit 9')
        self.fake("claude", "exit 0")
        gate = self.run_gate("unknown")
        self.assertEqual(gate["REACHABLE"], "codex")
        self.assertEqual(gate["FALLBACK_APPLIED"], "false")
        probes = self.log.read_text().splitlines()
        self.assertIn("codex --version", probes)
        self.assertFalse(any(line.startswith("claude ") for line in probes))
        self.assertFalse(any(" exec" in line or " -p" in line for line in probes))

    def test_synthetic_snapshot_carries_only_validated_fallback(self):
        self.local.write_text("review:\n  on_draft:\n    fallback_runner: codex\nprivate: synthetic-only\n")
        destination = self.root / "staged"
        destination.mkdir()
        subprocess.run([sys.executable, str(SCRIPTS / "workflow-config-resolver.py"),
                        "review-snapshot", "--repo-root", str(self.repo), "--destination", str(destination)],
                       env=self.env, check=True, capture_output=True)
        staged = resolver.parse_yaml_subset(destination / ".ai-dev-workflow.local.yaml")
        self.assertEqual(staged, {"review": {"on_draft": {"fallback_runner": "codex"}}})

    def test_preflight_includes_fallback_and_rejects_its_malformed_config(self):
        self.configure()
        for fallback, expected in (("codex", ["claude", "codex"]), ("[]", [])):
            self.configure(fallback=fallback)
            data = json.loads(subprocess.check_output(
                [sys.executable, str(SCRIPTS / "workflow-config-resolver.py"),
                 "review-effective", "--repo-root", str(self.repo)], env=self.env))
            runner_json = self.root / "runner.json"
            runner_json.write_text(json.dumps(data))
            output = self.root / "preflight.json"
            subprocess.run([sys.executable, str(SCRIPTS / "reviewer_preflight_build_input.py"),
                            "--runner-json", str(runner_json), "--remaining-stages", "on_draft.runner",
                            "--remaining-stages-provided", "1", "--output", str(output)],
                           env=self.env, check=True, capture_output=True)
            payload = json.loads(output.read_text())
            if fallback == "[]":
                self.assertIn("on_draft_runner", payload["malformed_buckets"])
            else:
                self.assertEqual(payload["resolved"]["on_draft_runner"], expected)


if __name__ == "__main__":
    unittest.main()

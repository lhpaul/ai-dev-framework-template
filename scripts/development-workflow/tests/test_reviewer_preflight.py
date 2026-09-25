#!/usr/bin/env python3
"""Unit tests for reviewer_preflight.py's cross-check engine (issue #1561).

Exercises ``classify()`` directly against JSON-serializable input, per
Decision 2 of the implementation plan: the Python module performs no I/O, so
every outcome-matrix and reason-code case in this suite is expressed as a
payload dict rather than a git fixture or a real .coderabbit.yaml on disk.
"""

from __future__ import annotations

import pathlib
import sys
import unittest
import unittest.mock

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPT_DIR))

import reviewer_preflight as rp  # noqa: E402
import reviewer_preflight_coderabbit as rpc  # noqa: E402


def base_payload(**overrides):
    payload = {
        "target_base": "develop",
        "remaining_stages": ["on_draft_github"],
        "pr_state": {"on_draft_github": "draft"},
        "shared": {"on_draft_github": ["coderabbit"]},
        "resolved": {"on_draft_github": ["coderabbit"]},
        "checked_shared_config_ref": "origin/develop:.ai-dev-workflow.yaml",
        "checked_platform_config_ref": "origin/develop:.coderabbit.yaml",
        "local_override_state": "none",
        "platform_configs": {
            "coderabbit": {
                "read": True,
                "auto_review_enabled": True,
                "drafts": True,
                "base_branches": None,
            }
        },
    }
    payload.update(overrides)
    return payload


def platform(result, name):
    for entry in result["platforms"]:
        if entry["name"] == name:
            return entry
    raise AssertionError(f"platform {name} not in report: {result}")


class OutcomeMatrixTests(unittest.TestCase):
    def test_passed_on_coherent_config(self):
        result = rp.classify(base_payload())
        self.assertEqual(result["outcome"], "passed")
        self.assertEqual(platform(result, "coderabbit")["verdict"], "operable")

    def test_review_disabled(self):
        payload = base_payload()
        payload["platform_configs"]["coderabbit"]["auto_review_enabled"] = False
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "blocked")
        entry = platform(result, "coderabbit")
        self.assertEqual(entry["verdict"], "not-operable")
        self.assertEqual(entry["reasons"], ["review-disabled"])
        self.assertIn("reviews.auto_review.enabled", entry["setting"])

    def test_stage_excluded_no_adjustment(self):
        payload = base_payload()
        payload["platform_configs"]["coderabbit"]["drafts"] = False
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "blocked")
        entry = platform(result, "coderabbit")
        self.assertEqual(entry["reasons"], ["stage-excluded"])

    def test_stage_excluded_on_absent_drafts_setting(self):
        # coderabbit.md's documented default: CodeRabbit declines drafts both
        # when `drafts: false` is explicit and when the key is absent
        # (`drafts: None` — "no repository commitment either way" at the
        # config-reader layer, but Step 7a's own documented interpretation
        # of that absence is still "cannot review drafts").
        payload = base_payload()
        payload["platform_configs"]["coderabbit"]["drafts"] = None
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "blocked")
        entry = platform(result, "coderabbit")
        self.assertEqual(entry["reasons"], ["stage-excluded"])

    def test_stage_excluded_resolved_by_draft_to_ready_adjustment(self):
        # Decision 7: the shell-supplied pr_state already reflects the
        # post-adjustment state, so a drafts:false platform dispatched
        # against a converted-to-ready PR sees no stage mismatch.
        payload = base_payload()
        payload["platform_configs"]["coderabbit"]["drafts"] = False
        payload["pr_state"]["on_draft_github"] = "ready"
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "passed")
        self.assertEqual(platform(result, "coderabbit")["verdict"], "operable")

    def test_base_branch_not_covered(self):
        payload = base_payload()
        payload["platform_configs"]["coderabbit"]["base_branches"] = ["main"]
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "blocked")
        entry = platform(result, "coderabbit")
        self.assertEqual(entry["reasons"], ["base-branch-unmatched"])
        self.assertIn("develop", entry["detail"])

    def test_base_branch_covered_by_regex(self):
        payload = base_payload(target_base="develop-guardrails")
        payload["platform_configs"]["coderabbit"]["base_branches"] = ["develop", "develop-.*"]
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "passed")

    def test_value_not_supported_stands_alone(self):
        payload = base_payload(
            shared={"on_draft_github": ["not-a-reviewer"]},
            resolved={"on_draft_github": ["not-a-reviewer"]},
        )
        payload["platform_configs"] = {}
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "blocked")
        entry = platform(result, "not-a-reviewer")
        self.assertEqual(entry["reasons"], ["value-not-supported"])

    def test_value_not_supported_override_added_points_at_local_override(self):
        # A shared config with a coherent list, plus a machine-local
        # override that added an unsupported value not present in the
        # shared list at all — the remedy must name the local override
        # file, not the shared config the bad value was never in.
        payload = base_payload(
            shared={"on_draft_github": []},
            resolved={"on_draft_github": ["not-a-reviewer"]},
            local_override_state="applied",
        )
        payload["platform_configs"] = {}
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "blocked")
        entry = platform(result, "not-a-reviewer")
        self.assertEqual(entry["reasons"], ["value-not-supported"])
        self.assertEqual(entry["surface"], ".ai-dev-workflow.local.yaml")
        self.assertIn(".ai-dev-workflow.local.yaml", entry["remedy"])

    def test_value_not_supported_bucket_scoped(self):
        # claude is supported for on_draft.runner but not on_ready.github.
        payload = base_payload(
            remaining_stages=["on_ready_github"],
            pr_state={"on_ready_github": "ready"},
            shared={"on_ready_github": ["claude"]},
            resolved={"on_ready_github": ["claude"]},
        )
        payload["platform_configs"] = {}
        result = rp.classify(payload)
        entry = platform(result, "claude")
        self.assertEqual(entry["reasons"], ["value-not-supported"])
        self.assertIn("on_ready.github", entry["setting"])

    def test_hosted_reviewers_supported_in_runner_bucket(self):
        # resolve-reviewer-availability.sh (Step 7a) accepts coderabbit and
        # codex-github in review.on_draft.runner (probe_hosted, entry case
        # coderabbit|codex-github) alongside the three local-runtime driving-
        # session values; the preflight must not reject an existing valid
        # configuration as value-not-supported.
        payload = base_payload(
            remaining_stages=["on_draft_runner"],
            pr_state={"on_draft_runner": "draft"},
            shared={"on_draft_runner": ["coderabbit", "codex-github"]},
            resolved={"on_draft_runner": ["coderabbit", "codex-github"]},
        )
        result = rp.classify(payload)
        coderabbit_entry = platform(result, "coderabbit")
        codex_github_entry = platform(result, "codex-github")
        self.assertNotIn("value-not-supported", coderabbit_entry["reasons"])
        self.assertNotIn("value-not-supported", codex_github_entry["reasons"])
        # coderabbit still reads its own repo-hosted config regardless of
        # which bucket it is configured in.
        self.assertEqual(coderabbit_entry["verdict"], "operable")
        # codex-github has no repo-local config in any bucket (Decision 8).
        self.assertEqual(codex_github_entry["verdict"], "undetermined")
        self.assertIn("no-readable-surface", codex_github_entry["reasons"])

    def test_multi_reason_aggregation_on_one_verdict(self):
        payload = base_payload()
        payload["platform_configs"]["coderabbit"].update(
            {"auto_review_enabled": False, "base_branches": ["main"]}
        )
        result = rp.classify(payload)
        entry = platform(result, "coderabbit")
        self.assertEqual(entry["verdict"], "not-operable")
        self.assertEqual(set(entry["reasons"]), {"review-disabled", "base-branch-unmatched"})

    def test_undetermined_no_readable_surface(self):
        payload = base_payload(
            shared={"on_draft_github": ["pr-agent"]},
            resolved={"on_draft_github": ["pr-agent"]},
        )
        payload["platform_configs"] = {"pr-agent": {"read": False, "reason": "no-readable-surface"}}
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "passed-unverified")
        entry = platform(result, "pr-agent")
        self.assertEqual(entry["verdict"], "undetermined")
        self.assertEqual(entry["reasons"], ["no-readable-surface"])

    def test_undetermined_check_inconclusive(self):
        payload = base_payload()
        payload["platform_configs"]["coderabbit"] = {"read": False, "reason": "check-inconclusive"}
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "passed-unverified")
        self.assertEqual(platform(result, "coderabbit")["reasons"], ["check-inconclusive"])

    def test_timeout_after_disagreement_stays_not_operable(self):
        # Decision 3: a read that times out after already proving a
        # disagreement is not thereby weaker evidence than one that finished.
        payload = base_payload()
        payload["platform_configs"]["coderabbit"] = {
            "read": False,
            "reason": "check-inconclusive",
            "prior_reasons": ["review-disabled"],
        }
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "blocked")
        entry = platform(result, "coderabbit")
        self.assertEqual(entry["verdict"], "not-operable")
        self.assertEqual(entry["reasons"], ["review-disabled"])

    def test_base_branch_pattern_timeout_is_undetermined_check_inconclusive(self):
        # #1561 round-20 finding: a catastrophic-backtracking base_branches
        # pattern (e.g. "(a+)+$") must degrade this one platform's verdict
        # to Undetermined/check-inconclusive rather than hanging classify()
        # itself or propagating an uncaught exception.
        payload = base_payload(target_base="a" * 30 + "!")
        payload["platform_configs"]["coderabbit"]["base_branches"] = ["(a+)+$"]
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "passed-unverified")
        entry = platform(result, "coderabbit")
        self.assertEqual(entry["verdict"], "undetermined")
        self.assertEqual(entry["reasons"], ["check-inconclusive"])

    def test_base_branch_pattern_timeout_after_disagreement_stays_not_operable(self):
        # Same Decision 3 precedent as the file-read timeout case above,
        # applied to a base_branches pattern timeout: a proven disagreement
        # (review-disabled) found before the timeout is not weakened by the
        # inconclusive base-branch check that follows it.
        payload = base_payload(target_base="a" * 30 + "!")
        payload["platform_configs"]["coderabbit"]["auto_review_enabled"] = False
        payload["platform_configs"]["coderabbit"]["base_branches"] = ["(a+)+$"]
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "blocked")
        entry = platform(result, "coderabbit")
        self.assertEqual(entry["verdict"], "not-operable")
        self.assertEqual(entry["reasons"], ["review-disabled"])

    def test_undetermined_never_blocks_alone(self):
        payload = base_payload(
            shared={"on_draft_github": ["pr-agent", "coderabbit"]},
            resolved={"on_draft_github": ["pr-agent", "coderabbit"]},
        )
        payload["platform_configs"]["pr-agent"] = {"read": False, "reason": "no-readable-surface"}
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "passed-unverified")
        self.assertEqual(platform(result, "pr-agent")["verdict"], "undetermined")
        self.assertEqual(platform(result, "coderabbit")["verdict"], "operable")

    def test_blocked_wins_over_undetermined(self):
        payload = base_payload(
            shared={"on_draft_github": ["pr-agent", "coderabbit"]},
            resolved={"on_draft_github": ["pr-agent", "coderabbit"]},
        )
        payload["platform_configs"]["pr-agent"] = {"read": False, "reason": "no-readable-surface"}
        payload["platform_configs"]["coderabbit"]["auto_review_enabled"] = False
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "blocked")
        self.assertEqual(platform(result, "pr-agent")["verdict"], "undetermined")
        self.assertEqual(platform(result, "coderabbit")["verdict"], "not-operable")


class PrerequisiteOrderTests(unittest.TestCase):
    def test_bad_base_beats_empty_stages(self):
        payload = base_payload(target_base="", remaining_stages=[])
        with self.assertRaises(rp.PrerequisiteFailed) as ctx:
            rp.classify(payload)
        self.assertIn("base branch", ctx.exception.detail)

    def test_unresolved_base_prerequisite_failed(self):
        payload = base_payload(target_base=None)
        with self.assertRaises(rp.PrerequisiteFailed):
            rp.classify(payload)

    def test_malformed_stage_set_prerequisite_failed(self):
        payload = base_payload(remaining_stages=["not-a-real-bucket"])
        with self.assertRaises(rp.PrerequisiteFailed):
            rp.classify(payload)

    def test_duplicate_stage_set_prerequisite_failed(self):
        payload = base_payload(remaining_stages=["on_draft_github", "on_draft_github"])
        with self.assertRaises(rp.PrerequisiteFailed):
            rp.classify(payload)

    def test_unresolved_pr_state_prerequisite_failed(self):
        payload = base_payload(pr_state={})
        with self.assertRaises(rp.PrerequisiteFailed):
            rp.classify(payload)

    def test_malformed_pr_state_value_prerequisite_failed(self):
        payload = base_payload(pr_state={"on_draft_github": "unknown"})
        with self.assertRaises(rp.PrerequisiteFailed):
            rp.classify(payload)

    def test_empty_remaining_stages_is_no_review_remaining_not_prerequisite_failed(self):
        payload = base_payload(remaining_stages=[], pr_state={})
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "no-review-remaining")
        self.assertEqual(result["platforms"], [])

    def test_empty_resolved_list_is_passed(self):
        payload = base_payload(shared={"on_draft_github": []}, resolved={"on_draft_github": []})
        payload["platform_configs"] = {}
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "passed")
        self.assertEqual(result["platforms"], [])


class OverrideTests(unittest.TestCase):
    def test_override_excluded_reported_not_blocking(self):
        payload = base_payload(
            shared={"on_draft_github": ["coderabbit", "pr-agent"]},
            resolved={"on_draft_github": ["coderabbit"]},
            local_override_state="applied",
        )
        result = rp.classify(payload)
        self.assertEqual(result["outcome"], "passed")
        excluded = platform(result, "pr-agent")
        self.assertEqual(excluded["verdict"], "override-excluded")

    def test_override_added_platform_is_cross_checked(self):
        payload = base_payload(
            shared={"on_draft_github": ["pr-agent"]},
            resolved={"on_draft_github": ["coderabbit"]},
            local_override_state="applied",
        )
        result = rp.classify(payload)
        added = platform(result, "coderabbit")
        self.assertEqual(added["verdict"], "operable")
        # pr-agent named by shared but removed by override.
        excluded = platform(result, "pr-agent")
        self.assertEqual(excluded["verdict"], "override-excluded")

    def test_override_added_platform_review_disabled_remedy_points_at_local_override(self):
        # #1561 round-21 finding: when the machine-local override is what
        # added a *supported* platform (not merely an unsupported value, the
        # case test_value_not_supported_override_added_points_at_local_override
        # already covers) and that platform's own config disagrees for an
        # ordinary reason (review-disabled here), the remedy must still name
        # .ai-dev-workflow.local.yaml, not .ai-dev-workflow.yaml — the
        # shared file never listed this platform, so a remedy pointing
        # there cannot actually unblock the run.
        payload = base_payload(
            shared={"on_draft_github": ["pr-agent"]},
            resolved={"on_draft_github": ["coderabbit"]},
            local_override_state="applied",
        )
        payload["platform_configs"]["coderabbit"]["auto_review_enabled"] = False
        result = rp.classify(payload)
        entry = platform(result, "coderabbit")
        self.assertTrue(entry["override_added"])
        self.assertEqual(entry["reasons"], ["review-disabled"])
        self.assertIn(".ai-dev-workflow.local.yaml", entry["remedy"])
        self.assertNotIn(
            "review.on_draft.github in .ai-dev-workflow.yaml", entry["remedy"]
        )

    def test_override_added_platform_has_provenance(self):
        # LOCAL_OVERRIDE_STATE=applied is a global flag; an operator also
        # needs to know *which* platform the override added, not only that
        # some override was applied somewhere.
        payload = base_payload(
            shared={"on_draft_github": ["pr-agent"]},
            resolved={"on_draft_github": ["coderabbit"]},
            local_override_state="applied",
        )
        result = rp.classify(payload)
        added = platform(result, "coderabbit")
        self.assertTrue(added["override_added"])
        excluded = platform(result, "pr-agent")
        self.assertFalse(excluded["override_added"])

    def test_shared_platform_not_reported_as_override_added(self):
        # A platform present in both the shared and resolved lists was not
        # added by the override, even when the override changed something
        # else in the same bucket.
        payload = base_payload(
            shared={"on_draft_github": ["coderabbit", "pr-agent"]},
            resolved={"on_draft_github": ["coderabbit"]},
            local_override_state="applied",
        )
        result = rp.classify(payload)
        coderabbit_entry = platform(result, "coderabbit")
        self.assertFalse(coderabbit_entry["override_added"])

    def test_partial_removal_preserved_in_still_covered_platform_row(self):
        # coderabbit is shared in both draft and ready, but the local
        # override narrows it to ready-only. The platform is NOT fully
        # override-excluded (it still has resolved coverage in on_ready), so
        # the "override-excluded" platform-row branch does not apply here —
        # the removed draft bucket must still be visible in this platform's
        # own bucket_results, not silently dropped.
        payload = base_payload(
            remaining_stages=["on_draft_github", "on_ready_github"],
            pr_state={"on_draft_github": "draft", "on_ready_github": "ready"},
            shared={"on_draft_github": ["coderabbit"], "on_ready_github": ["coderabbit"]},
            resolved={"on_draft_github": [], "on_ready_github": ["coderabbit"]},
            local_override_state="applied",
        )
        result = rp.classify(payload)
        entry = platform(result, "coderabbit")
        # The still-resolved ready bucket keeps its own operable verdict —
        # the partial removal must not change the platform's overall verdict.
        self.assertEqual(entry["verdict"], "operable")
        bucket_names = {b["bucket"] for b in entry["bucket_results"]}
        self.assertIn("on_ready_github", bucket_names)
        self.assertIn("on_draft_github", bucket_names)
        removed = next(b for b in entry["bucket_results"] if b["bucket"] == "on_draft_github")
        self.assertEqual(removed["verdict"], "override-excluded")


class MultiBucketAggregationTests(unittest.TestCase):
    def test_oq4_bucket_results_and_severity(self):
        # coderabbit named in both remaining buckets: passes on_ready.github,
        # fails on_draft.github (review-disabled) — overall must be
        # not-operable (most severe), with both bucket outcomes preserved.
        payload = base_payload(
            remaining_stages=["on_draft_github", "on_ready_github"],
            pr_state={"on_draft_github": "draft", "on_ready_github": "ready"},
            shared={"on_draft_github": ["coderabbit"], "on_ready_github": ["coderabbit"]},
            resolved={"on_draft_github": ["coderabbit"], "on_ready_github": ["coderabbit"]},
        )
        payload["platform_configs"]["coderabbit"]["auto_review_enabled"] = False
        result = rp.classify(payload)
        entry = platform(result, "coderabbit")
        self.assertEqual(entry["verdict"], "not-operable")
        self.assertEqual(len(entry["bucket_results"]), 2)
        buckets = {b["bucket"]: b["verdict"] for b in entry["bucket_results"]}
        self.assertEqual(buckets["on_draft_github"], "not-operable")
        self.assertEqual(buckets["on_ready_github"], "not-operable")

    def test_platform_reported_exactly_once_across_buckets(self):
        payload = base_payload(
            remaining_stages=["on_draft_github", "on_ready_github"],
            pr_state={"on_draft_github": "draft", "on_ready_github": "ready"},
            shared={"on_draft_github": ["coderabbit"], "on_ready_github": ["coderabbit"]},
            resolved={"on_draft_github": ["coderabbit"], "on_ready_github": ["coderabbit"]},
        )
        result = rp.classify(payload)
        names = [p["name"] for p in result["platforms"]]
        self.assertEqual(names.count("coderabbit"), 1)


class ExitCodeTests(unittest.TestCase):
    def test_exit_codes(self):
        self.assertEqual(rp.exit_code_for_outcome("passed"), 0)
        self.assertEqual(rp.exit_code_for_outcome("passed-unverified"), 0)
        self.assertEqual(rp.exit_code_for_outcome("no-review-remaining"), 0)
        self.assertEqual(rp.exit_code_for_outcome("blocked"), 1)
        self.assertEqual(rp.exit_code_for_outcome("prerequisite-failed"), 2)


import reviewer_preflight_coderabbit as rpc  # noqa: E402


class BaseBranchCoveredTests(unittest.TestCase):
    """#1561 round-20 finding: base_branch_covered must bound each pattern
    match against catastrophic backtracking rather than hanging."""

    def test_normal_patterns_unaffected(self):
        self.assertTrue(rpc.base_branch_covered(["develop", "main"], "develop"))
        self.assertFalse(rpc.base_branch_covered(["develop"], "feature/x"))
        self.assertTrue(rpc.base_branch_covered(None, "anything"))

    def test_invalid_regex_pattern_skipped_not_fatal(self):
        # An unbalanced group is a re.error, not a timeout; existing
        # behavior (skip and keep checking) is unchanged by this fix.
        self.assertFalse(rpc.base_branch_covered(["(unbalanced", "develop"], "main"))
        self.assertTrue(rpc.base_branch_covered(["(unbalanced", "develop"], "develop"))

    def test_pathological_pattern_raises_timeout_quickly(self):
        import time

        start = time.time()
        with self.assertRaises(rpc.PatternTimeoutError):
            rpc.base_branch_covered(
                ["(a+)+$"], "a" * 30 + "!", per_pattern_timeout_seconds=0.3
            )
        elapsed = time.time() - start
        # Bounded: must not run anywhere near the ~10s+ this pattern would
        # otherwise take against this target unbounded.
        self.assertLess(elapsed, 2.0)


import reviewer_preflight_build_input as rpbi  # noqa: E402


class ParsePrStateTests(unittest.TestCase):
    """#1561 round-26 finding: a repeated --pr-state bucket key must be
    rejected, not resolved by "last value wins"."""

    def test_single_entries_parse_normally(self):
        self.assertEqual(
            rpbi._parse_pr_state("on_draft.runner=draft,on_draft.github=ready"),
            {"on_draft_runner": "draft", "on_draft_github": "ready"},
        )

    def test_duplicate_bucket_is_cleared_to_none(self):
        self.assertEqual(
            rpbi._parse_pr_state("on_draft.runner=draft,on_draft.runner=ready"),
            {"on_draft_runner": None},
        )

    def test_duplicate_bucket_with_identical_values_is_still_rejected(self):
        # Not only conflicting duplicates: any repeated bucket key is an
        # ambiguously composed input regardless of whether the repeated
        # values happen to agree.
        self.assertEqual(
            rpbi._parse_pr_state("on_draft.runner=draft,on_draft.runner=draft"),
            {"on_draft_runner": None},
        )

    def test_triple_duplicate_stays_cleared(self):
        self.assertEqual(
            rpbi._parse_pr_state("on_draft.runner=draft,on_draft.runner=ready,on_draft.runner=draft"),
            {"on_draft_runner": None},
        )

    def test_duplicate_bucket_fails_classify_as_prerequisite_failed(self):
        # End-to-end through classify(): a None pr_state value for a
        # remaining stage must route through the same prerequisite-failed
        # check as any other malformed value, not silently pass.
        payload = base_payload(remaining_stages=["on_draft_github"])
        payload["pr_state"] = rpbi._parse_pr_state("on_draft.github=draft,on_draft.github=ready")
        with self.assertRaises(rp.PrerequisiteFailed):
            rp.classify(payload)


class SharedBaseBranchBudgetTests(unittest.TestCase):
    """Bounded-Codex-pass round 2: base_branch_covered() must be called once
    per platform, not once per resolved bucket — otherwise a platform
    present in N remaining buckets gets N independent fresh aggregate
    deadlines instead of sharing one."""

    def test_base_branch_covered_called_once_across_three_buckets(self):
        payload = base_payload(
            remaining_stages=["on_draft_runner", "on_draft_github", "on_ready_github"],
            pr_state={"on_draft_runner": "draft", "on_draft_github": "draft", "on_ready_github": "ready"},
            shared={
                "on_draft_runner": ["coderabbit"],
                "on_draft_github": ["coderabbit"],
                "on_ready_github": ["coderabbit"],
            },
            resolved={
                "on_draft_runner": ["coderabbit"],
                "on_draft_github": ["coderabbit"],
                "on_ready_github": ["coderabbit"],
            },
        )
        payload["platform_configs"]["coderabbit"]["base_branches"] = ["develop"]
        calls = []
        real = rp.base_branch_covered

        def spy(base_branches, target_base, **kwargs):
            calls.append((tuple(base_branches), target_base))
            return real(base_branches, target_base, **kwargs)

        with unittest.mock.patch.object(rp, "base_branch_covered", spy):
            result = rp.classify(payload)
        self.assertEqual(len(calls), 1, calls)
        entry = platform(result, "coderabbit")
        self.assertEqual(len(entry["bucket_results"]), 3)

    def test_shared_result_still_applies_per_bucket_correctly(self):
        # The shared result must still be evaluated correctly against each
        # bucket's own other reasons (e.g. stage-excluded) — sharing the
        # base-branch computation must not also silently share unrelated
        # per-bucket verdicts.
        payload = base_payload(
            remaining_stages=["on_draft_runner", "on_draft_github"],
            pr_state={"on_draft_runner": "draft", "on_draft_github": "ready"},
            shared={"on_draft_runner": ["coderabbit"], "on_draft_github": ["coderabbit"]},
            resolved={"on_draft_runner": ["coderabbit"], "on_draft_github": ["coderabbit"]},
        )
        payload["platform_configs"]["coderabbit"]["base_branches"] = ["not-develop"]
        payload["platform_configs"]["coderabbit"]["drafts"] = False
        result = rp.classify(payload)
        entry = platform(result, "coderabbit")
        by_bucket = {r["bucket"]: r for r in entry["bucket_results"]}
        # on_draft_runner is a draft stage with drafts=False: stage-excluded
        # AND base-branch-unmatched (both reasons apply there).
        self.assertIn("stage-excluded", by_bucket["on_draft_runner"]["reasons"])
        self.assertIn("base-branch-unmatched", by_bucket["on_draft_runner"]["reasons"])
        # on_ready.github's own bucket (mapped from on_draft_github's ready
        # state here) is not a draft stage: only base-branch-unmatched.
        self.assertNotIn("stage-excluded", by_bucket["on_draft_github"]["reasons"])
        self.assertIn("base-branch-unmatched", by_bucket["on_draft_github"]["reasons"])


class CoderabbitMissingFileWithoutYamlTests(unittest.TestCase):
    # #1561 round-9 finding (P1): reviewer_preflight_coderabbit.py's
    # --mode full-json is what reviewer-preflight.sh calls with a
    # deliberately nonexistent placeholder path when CodeRabbit is not in
    # the resolved reviewer list at all — the missing-file case is meant
    # to resolve to a default disabled config without ever needing PyYAML
    # (load_coderabbit_config's own missing-file branch does no parsing).
    # _cmd_full_json previously imported yaml unconditionally before ever
    # checking whether the file existed, so a missing file plus a missing
    # PyYAML install returned dependency error 4 (which reviewer-preflight
    # .sh's caller degrades to check-inconclusive/passed-unverified)
    # instead of the documented disabled/prerequisite-missing outcome —
    # exactly the class of silent disagreement this preflight exists to
    # catch, not a graceful degrade.
    def test_missing_file_succeeds_even_when_pyyaml_is_unavailable(self):
        missing_path = pathlib.Path("/this/path/does/not/exist/.coderabbit.yaml")
        self.assertFalse(missing_path.exists())
        with unittest.mock.patch.dict(sys.modules, {"yaml": None}):
            rc = rpc._cmd_full_json(missing_path)
        self.assertEqual(rc, 0)

    def test_existing_file_still_requires_pyyaml(self):
        # The fix must not weaken the existing, intentional dependency
        # requirement for a file that genuinely needs parsing.
        with unittest.mock.patch.object(rpc.Path, "exists", return_value=True), \
             unittest.mock.patch.dict(sys.modules, {"yaml": None}):
            rc = rpc._cmd_full_json(pathlib.Path("/this/path/does/not/matter/.coderabbit.yaml"))
        self.assertEqual(rc, 4)


if __name__ == "__main__":
    unittest.main()

#!/usr/bin/env python3
"""Reviewer preflight cross-check engine (issue #1561).

Cross-checks three configuration surfaces — the shared workflow reviewer
configuration, the machine-local override, and each reviewer platform's own
configuration — before Protocol 91 dispatches an item, and reports a
disagreement rather than proceeding on an assumption. See
``docs/specs/developments/20260911230501_1561-reviewer-preflight/`` for the
spec and implementation plan this module implements.

Decision 2 of the implementation plan: this module owns deterministic
cross-check logic only. It performs no I/O, no git operations, and no
network calls — ``reviewer-preflight.sh`` resolves git refs, reads files
under a time budget, and prints the ``KEY=value`` report; this module reads
a JSON payload describing the already-resolved inputs and returns a JSON
verdict. That split is what makes the outcome matrix unit-testable without a
git fixture or a real .coderabbit.yaml on disk.
"""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any

from reviewer_preflight_coderabbit import base_branch_covered

# Per-bucket supported reviewer platform lists (spec: "value-not-supported").
# A value supported in one bucket is not automatically supported in another —
# review.on_draft.runner, review.on_draft.github, and review.on_ready.github
# each have their own list, matching .ai-dev-workflow.yaml's own comments and
# pr-review-loop.sh's shipped GitHub reviewer roster. review.on_draft.runner
# also accepts the two hosted Step 7a reviewers resolve-reviewer-availability.sh
# probes there (probe_hosted, entry case coderabbit|codex-github) alongside the
# three local-runtime driving-session values — the same platforms classify
# generically below (coderabbit reads .coderabbit.yaml regardless of bucket;
# codex-github is Undetermined/no-readable-surface in every bucket, Decision 8).
SUPPORTED_RUNNER = frozenset({"claude", "cursor", "codex", "coderabbit", "codex-github"})
SUPPORTED_GITHUB = frozenset(
    {
        "greptile",
        "devin",
        "coderabbit",
        "coderabbit-cli",
        "local-ai-reviewer",
        "pr-agent",
        "codex-github",
        "claude-code-action",
        "haystack",
        "copilot",
        "bugbot",
        "ronda",
    }
)

BUCKET_SUPPORTED: dict[str, frozenset[str]] = {
    "on_draft_runner": SUPPORTED_RUNNER,
    "on_draft_github": SUPPORTED_GITHUB,
    "on_ready_github": SUPPORTED_GITHUB,
}

# review.<bucket dotted path>, used in setting names and remedies.
BUCKET_DOTTED = {
    "on_draft_runner": "on_draft.runner",
    "on_draft_github": "on_draft.github",
    "on_ready_github": "on_ready.github",
}

# Platforms with a readable, repository-hosted own-configuration file this
# preflight cross-checks. Every other supported platform — including the
# local-runtime runner reviewers and hosted platforms configured only through
# their own dashboard/App settings (codex-github, pr-agent, and the rest of
# SUPPORTED_GITHUB) — classifies Undetermined / no-readable-surface (spec Use
# Case 4; plan Decision 8), because this preflight cross-checks configuration
# it can read, not live installation or service state (Out of Scope entry
# 11).
PLATFORM_CONFIG_FILE = {
    "coderabbit": ".coderabbit.yaml",
}

VERDICT_SEVERITY = {"operable": 0, "undetermined": 1, "not-operable": 2}

OUTCOME_LABELS = {
    "passed": "Passed",
    "passed-unverified": "Passed, some unverified",
    "blocked": "Blocked",
    "prerequisite-failed": "Prerequisite not met",
    "no-review-remaining": "No review remaining",
}

VERDICT_LABELS = {
    "operable": "Can review",
    "not-operable": "Cannot review",
    "undetermined": "Undetermined",
    "override-excluded": "Excluded by override",
}


class PrerequisiteFailed(Exception):
    def __init__(self, detail: str):
        super().__init__(detail)
        self.detail = detail


def _reason_setting(reason: str) -> str:
    return {
        "review-disabled": "reviews.auto_review.enabled",
        "stage-excluded": "reviews.auto_review.drafts",
        "base-branch-unmatched": "reviews.auto_review.base_branches",
    }.get(reason, "")


def _reason_remedy(reason: str, name: str, file_name: str, bucket: str, target_base: str) -> str:
    dotted = BUCKET_DOTTED[bucket]
    if reason == "review-disabled":
        return (
            f"Set reviews.auto_review.enabled: true in {file_name}, or remove "
            f"{name} from review.{dotted} in .ai-dev-workflow.yaml, and re-run."
        )
    if reason == "stage-excluded":
        return (
            f"Set reviews.auto_review.drafts: true in {file_name}, or move "
            f"{name} to a stage its own configuration covers in "
            f"review.{dotted}, and re-run."
        )
    if reason == "base-branch-unmatched":
        return (
            f"Add '{target_base}' to reviews.auto_review.base_branches in "
            f"{file_name}, or narrow this machine's reviewer list through "
            f".ai-dev-workflow.local.yaml to exclude {name} for this item, "
            "and re-run."
        )
    return ""


def classify_platform_in_bucket(
    name: str,
    bucket: str,
    *,
    target_base: str,
    pr_state: dict[str, str],
    platform_configs: dict[str, Any],
    shared_config_ref: str,
) -> dict[str, Any]:
    """Classify one platform's ability to review, scoped to one lifecycle bucket."""
    supported = BUCKET_SUPPORTED[bucket]
    dotted = BUCKET_DOTTED[bucket]
    if name not in supported:
        return {
            "bucket": bucket,
            "verdict": "not-operable",
            "reasons": ["value-not-supported"],
            "surface": shared_config_ref or ".ai-dev-workflow.yaml",
            "setting": f"review.{dotted}",
            "detail": f"'{name}' is not a supported reviewer platform for review.{dotted}.",
            "remedy": (
                f"Correct '{name}' to a supported platform's name for "
                f"review.{dotted}, or remove it from the shared reviewer "
                "list, and re-run."
            ),
        }

    cfg = platform_configs.get(name)
    if not cfg or not cfg.get("read"):
        reason = (cfg or {}).get("reason", "no-readable-surface")
        prior_reasons = (cfg or {}).get("prior_reasons") or []
        if reason == "check-inconclusive" and prior_reasons:
            # Decision 3: a read that times out after already proving a
            # disagreement is not thereby weaker evidence than one that
            # finished — it stays Cannot review with the proven reasons.
            file_name = PLATFORM_CONFIG_FILE.get(name, f"{name}'s own configuration")
            details = []
            settings = []
            remedies = []
            for prior in prior_reasons:
                details.append(_reason_detail_text(prior, name, target_base))
                setting = _reason_setting(prior)
                if setting:
                    settings.append(setting)
                remedy = _reason_remedy(prior, name, file_name, bucket, target_base)
                if remedy:
                    remedies.append(remedy)
            return {
                "bucket": bucket,
                "verdict": "not-operable",
                "reasons": list(prior_reasons),
                "surface": file_name,
                "setting": ", ".join(dict.fromkeys(settings)),
                "detail": "; ".join(details),
                "remedy": " ".join(dict.fromkeys(remedies)),
            }
        detail = (
            f"{name} exposes no configuration this preflight can read."
            if reason == "no-readable-surface"
            else (
                f"{name}'s own configuration could not be read within the "
                "preflight's time budget."
            )
        )
        return {
            "bucket": bucket,
            "verdict": "undetermined",
            "reasons": [reason],
            "surface": "",
            "setting": "",
            "detail": detail,
            "remedy": "",
        }

    reasons: list[str] = []
    if cfg.get("auto_review_enabled") is False:
        reasons.append("review-disabled")
    stage_pr_state = pr_state.get(bucket)
    # coderabbit.md's documented default: CodeRabbit cannot review drafts
    # both when `drafts: false` is explicit *and* when the key is absent
    # (`cfg["drafts"] is None`) — only an explicit `drafts: true` preserves
    # draft reachability. Only `is not True` matches that "false or absent"
    # rule; checking `is False` alone would miss the absent case.
    if stage_pr_state == "draft" and cfg.get("drafts") is not True:
        reasons.append("stage-excluded")
    base_branches = cfg.get("base_branches")
    if base_branches is not None and not base_branch_covered(base_branches, target_base):
        reasons.append("base-branch-unmatched")

    if not reasons:
        return {
            "bucket": bucket,
            "verdict": "operable",
            "reasons": [],
            "surface": "",
            "setting": "",
            "detail": "",
            "remedy": "",
        }

    file_name = PLATFORM_CONFIG_FILE.get(name, f"{name}'s own configuration")
    details = [_reason_detail_text(reason, name, target_base, cfg) for reason in reasons]
    settings = [s for s in (_reason_setting(reason) for reason in reasons) if s]
    remedies = [
        r for r in (_reason_remedy(reason, name, file_name, bucket, target_base) for reason in reasons) if r
    ]
    return {
        "bucket": bucket,
        "verdict": "not-operable",
        "reasons": reasons,
        "surface": file_name,
        "setting": ", ".join(dict.fromkeys(settings)),
        "detail": "; ".join(details),
        "remedy": " ".join(dict.fromkeys(remedies)),
    }


def _reason_detail_text(
    reason: str, name: str, target_base: str, cfg: dict[str, Any] | None = None
) -> str:
    cfg = cfg or {}
    if reason == "review-disabled":
        return "reviews.auto_review.enabled is false; automatic review is off for this repository"
    if reason == "stage-excluded":
        return "listed for the draft stage; reviews.auto_review.drafts is false, so drafts are declined"
    if reason == "base-branch-unmatched":
        covered = cfg.get("base_branches")
        return (
            f"this item targets '{target_base}'; reviews.auto_review.base_branches "
            f"covers {covered!r}"
        )
    return ""


def classify(payload: dict[str, Any]) -> dict[str, Any]:
    """Pure classification: JSON-serializable input, JSON-serializable output.

    Raises ``PrerequisiteFailed`` when a required input is empty, unresolved,
    or malformed, per the spec's fixed prerequisite order: base branch, then
    stage-set resolvability, then (for a non-empty stage set) per-stage
    pull-request state.
    """
    target_base = payload.get("target_base")
    if not isinstance(target_base, str) or not target_base.strip():
        raise PrerequisiteFailed("the base branch this item targets is empty, unresolved, or malformed")

    remaining_stages = payload.get("remaining_stages")
    if not isinstance(remaining_stages, list) or any(
        not isinstance(stage, str) or stage not in BUCKET_SUPPORTED for stage in remaining_stages
    ):
        raise PrerequisiteFailed(
            "the set of lifecycle stages this run will exercise is unresolved or malformed"
        )
    # Duplicate stage names are malformed input, not a legitimate empty/non-empty set.
    if len(remaining_stages) != len(set(remaining_stages)):
        raise PrerequisiteFailed(
            "the set of lifecycle stages this run will exercise is unresolved or malformed"
        )

    checked_shared_config_ref = payload.get("checked_shared_config_ref", "")
    checked_platform_config_ref = payload.get("checked_platform_config_ref", "")
    local_override_state = payload.get("local_override_state", "none")

    if not remaining_stages:
        return {
            "outcome": "no-review-remaining",
            "outcome_label": OUTCOME_LABELS["no-review-remaining"],
            "checked_shared_config_ref": checked_shared_config_ref,
            "checked_platform_config_ref": checked_platform_config_ref,
            "local_override_state": local_override_state,
            "platforms": [],
        }

    pr_state = payload.get("pr_state")
    if not isinstance(pr_state, dict):
        raise PrerequisiteFailed(
            "the pull-request state for a remaining lifecycle stage is empty, unresolved, or malformed"
        )
    for stage in remaining_stages:
        if pr_state.get(stage) not in ("draft", "ready"):
            raise PrerequisiteFailed(
                f"the pull-request state for stage '{stage}' is empty, unresolved, or malformed"
            )

    shared = payload.get("shared") or {}
    resolved = payload.get("resolved") or {}
    platform_configs = payload.get("platform_configs") or {}

    names_in_play: list[str] = []
    for stage in remaining_stages:
        for name in shared.get(stage, []) or []:
            if name not in names_in_play:
                names_in_play.append(name)
        for name in resolved.get(stage, []) or []:
            if name not in names_in_play:
                names_in_play.append(name)

    platforms: list[dict[str, Any]] = []
    for name in names_in_play:
        resolved_buckets = [
            stage for stage in remaining_stages if name in (resolved.get(stage, []) or [])
        ]
        if not resolved_buckets:
            platforms.append(
                {
                    "name": name,
                    "verdict": "override-excluded",
                    "reasons": [],
                    "surface": "",
                    "setting": "",
                    "detail": "removed from the resolved reviewer list by the machine-local override",
                    "remedy": "",
                    "bucket_results": [],
                }
            )
            continue

        bucket_results = [
            classify_platform_in_bucket(
                name,
                bucket,
                target_base=target_base,
                pr_state=pr_state,
                platform_configs=platform_configs,
                shared_config_ref=checked_shared_config_ref,
            )
            for bucket in resolved_buckets
        ]
        overall_verdict = max(
            (result["verdict"] for result in bucket_results), key=lambda v: VERDICT_SEVERITY[v]
        )
        merged_reasons: list[str] = []
        merged_surfaces: list[str] = []
        merged_settings: list[str] = []
        merged_details: list[str] = []
        merged_remedies: list[str] = []
        for result in bucket_results:
            if result["verdict"] != overall_verdict:
                continue
            for reason in result["reasons"]:
                if reason not in merged_reasons:
                    merged_reasons.append(reason)
            if result["surface"] and result["surface"] not in merged_surfaces:
                merged_surfaces.append(result["surface"])
            if result["setting"] and result["setting"] not in merged_settings:
                merged_settings.append(result["setting"])
            if result["detail"] and result["detail"] not in merged_details:
                merged_details.append(result["detail"])
            if result["remedy"] and result["remedy"] not in merged_remedies:
                merged_remedies.append(result["remedy"])
        platforms.append(
            {
                "name": name,
                "verdict": overall_verdict,
                "reasons": merged_reasons,
                "surface": ", ".join(merged_surfaces),
                "setting": ", ".join(merged_settings),
                "detail": "; ".join(merged_details),
                "remedy": " ".join(merged_remedies),
                "bucket_results": bucket_results,
            }
        )

    resolved_platforms = [p for p in platforms if p["verdict"] != "override-excluded"]
    if any(p["verdict"] == "not-operable" for p in resolved_platforms):
        outcome = "blocked"
    elif any(p["verdict"] == "undetermined" for p in resolved_platforms):
        outcome = "passed-unverified"
    else:
        outcome = "passed"

    return {
        "outcome": outcome,
        "outcome_label": OUTCOME_LABELS[outcome],
        "checked_shared_config_ref": checked_shared_config_ref,
        "checked_platform_config_ref": checked_platform_config_ref,
        "local_override_state": local_override_state,
        "platforms": platforms,
    }


def exit_code_for_outcome(outcome: str) -> int:
    return {
        "passed": 0,
        "passed-unverified": 0,
        "no-review-remaining": 0,
        "blocked": 1,
        "prerequisite-failed": 2,
    }[outcome]


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Reviewer preflight cross-check engine")
    parser.add_argument("--input-json", required=True, help="path to the input JSON payload")
    args = parser.parse_args(argv)
    try:
        with open(args.input_json, encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        print(f"ERROR: cannot read input JSON: {error}", file=sys.stderr)
        return 3
    try:
        result = classify(payload)
    except PrerequisiteFailed as failure:
        result = {
            "outcome": "prerequisite-failed",
            "outcome_label": OUTCOME_LABELS["prerequisite-failed"],
            "checked_shared_config_ref": payload.get("checked_shared_config_ref", ""),
            "checked_platform_config_ref": payload.get("checked_platform_config_ref", ""),
            "local_override_state": payload.get("local_override_state", "none"),
            "platforms": [],
            "prerequisite_detail": failure.detail,
        }
    print(json.dumps(result, sort_keys=True))
    return exit_code_for_outcome(result["outcome"])


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

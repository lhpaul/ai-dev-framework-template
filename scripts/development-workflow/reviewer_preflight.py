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

from reviewer_preflight_coderabbit import PatternTimeoutError, base_branch_covered

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


def _reason_remedy(
    reason: str,
    name: str,
    file_name: str,
    bucket: str,
    target_base: str,
    *,
    override_added: bool = False,
) -> str:
    dotted = BUCKET_DOTTED[bucket]
    if reason == "review-disabled":
        # When the machine-local override is what added this platform to
        # this bucket, the shared config (.ai-dev-workflow.yaml) never
        # listed it — telling the operator to remove it from there sends
        # them to a file that has nothing to remove, so the remedy cannot
        # actually unblock the run. Name the local override instead, same
        # provenance rule the value-not-supported branch above already
        # applies.
        list_surface = ".ai-dev-workflow.local.yaml" if override_added else ".ai-dev-workflow.yaml"
        return (
            f"Set reviews.auto_review.enabled: true in {file_name}, or remove "
            f"{name} from review.{dotted} in {list_surface}, and re-run."
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
    override_added: bool = False,
    base_branch_check: tuple[bool, bool] | None = None,
) -> dict[str, Any]:
    """Classify one platform's ability to review, scoped to one lifecycle bucket.

    ``base_branch_check``, when given, is ``(timed_out, covered)`` —
    ``base_branch_covered()``'s already-computed result for this platform's
    ``base_branches`` against ``target_base``, reused across every bucket
    this platform appears in rather than recomputed here. A platform can
    appear in up to three remaining buckets (on_draft.runner, on_draft.github,
    on_ready.github); without sharing this result, each bucket call
    recreated its own fresh aggregate regex-matching deadline (round-1 of
    this bounded pass's own fix), so a platform present in all three buckets
    could spend up to 3x that aggregate budget in total — exceeding the
    shell's own outer per-platform deadline and surfacing as an
    undifferentiated tooling failure instead of the documented
    Undetermined/check-inconclusive degrade. When ``None`` (direct callers,
    e.g. unit tests, that classify a single bucket in isolation), this
    function computes it itself exactly as before.
    """
    supported = BUCKET_SUPPORTED[bucket]
    dotted = BUCKET_DOTTED[bucket]
    if name not in supported:
        # When the machine-local override is what added this unsupported
        # value to this bucket, the shared config never contained it —
        # pointing the operator at the shared file/list (and telling them
        # to remove it from there) sends them to a file that does not have
        # the bad value, so the documented remedy cannot actually unblock
        # dispatch. Name the local override instead.
        if override_added:
            surface = ".ai-dev-workflow.local.yaml"
            remedy = (
                f"Correct '{name}' to a supported platform's name for "
                f"review.{dotted} in .ai-dev-workflow.local.yaml, or remove "
                "it from the local override list, and re-run."
            )
        else:
            surface = shared_config_ref or ".ai-dev-workflow.yaml"
            remedy = (
                f"Correct '{name}' to a supported platform's name for "
                f"review.{dotted}, or remove it from the shared reviewer "
                "list, and re-run."
            )
        return {
            "bucket": bucket,
            "verdict": "not-operable",
            "reasons": ["value-not-supported"],
            "surface": surface,
            "setting": f"review.{dotted}",
            "detail": f"'{name}' is not a supported reviewer platform for review.{dotted}.",
            "remedy": remedy,
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
                remedy = _reason_remedy(
                    prior, name, file_name, bucket, target_base, override_added=override_added
                )
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
    base_branch_timed_out = False
    if base_branch_check is not None:
        base_branch_timed_out, base_branch_matched = base_branch_check
        if base_branches is not None and not base_branch_timed_out and not base_branch_matched:
            reasons.append("base-branch-unmatched")
    elif base_branches is not None:
        try:
            if not base_branch_covered(base_branches, target_base):
                reasons.append("base-branch-unmatched")
        except PatternTimeoutError:
            base_branch_timed_out = True

    if base_branch_timed_out and not reasons:
        # Same precedent as the config-read timeout handled above (Decision
        # 3): a bounded check that could not complete in time reports
        # Undetermined/check-inconclusive for this one platform, rather than
        # this function raising and letting reviewer-preflight.sh's outer
        # subprocess bound kill the whole classifier — which would turn one
        # platform's pathological base_branches pattern into a hard tooling
        # failure for every remaining platform's verdict, not just this
        # one's. When another reason already proved a disagreement (e.g.
        # review-disabled) before the timeout, that proof stands on its own
        # and is not weakened by an inconclusive base-branch check, so it
        # falls through to the not-operable return below unchanged.
        return {
            "bucket": bucket,
            "verdict": "undetermined",
            "reasons": ["check-inconclusive"],
            "surface": "",
            "setting": "",
            "detail": (
                f"{name}'s base_branches pattern could not be evaluated "
                "within the preflight's bounded time budget."
            ),
            "remedy": "",
        }

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
        r
        for r in (
            _reason_remedy(reason, name, file_name, bucket, target_base, override_added=override_added)
            for reason in reasons
        )
        if r
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
                    "override_added": False,
                }
            )
            continue

        # Provenance: a bucket where this platform is in the resolved
        # (post-override) list but not in the shared (pre-override) list
        # means the machine-local override added it there — coverage the
        # shared configuration alone would not have produced. Without this,
        # LOCAL_OVERRIDE_STATE=applied is a global flag an operator cannot
        # attribute to any specific platform.
        override_added_buckets = [
            stage for stage in resolved_buckets if name not in (shared.get(stage, []) or [])
        ]
        # The mirror case: a bucket where this platform is in the *shared*
        # list but the override removed it there specifically, while the
        # platform still has resolved coverage in another remaining bucket
        # (so the "override-excluded" platform row above does not apply —
        # this platform is not excluded overall, only from this one bucket).
        # Without recording this, a partial per-bucket removal is invisible:
        # the row shows only the still-covered bucket's operable verdict
        # plus the global LOCAL_OVERRIDE_STATE flag, with no sign the
        # override reduced this platform's coverage at all.
        override_removed_buckets = [
            stage
            for stage in remaining_stages
            if stage not in resolved_buckets and name in (shared.get(stage, []) or [])
        ]
        # Compute base_branch_covered() once per platform, not once per
        # resolved bucket: a platform can appear in up to three remaining
        # buckets, and each classify_platform_in_bucket call used to
        # recreate its own fresh aggregate regex-matching deadline —
        # reproduced live, a platform present in all three buckets could
        # exhaust up to 3x that aggregate budget in total. base_branches
        # and target_base are identical across every bucket this platform
        # appears in, so the match result is too.
        platform_cfg = platform_configs.get(name) or {}
        platform_base_branches = platform_cfg.get("base_branches") if platform_cfg.get("read") else None
        base_branch_check: tuple[bool, bool] | None = None
        if platform_base_branches is not None:
            try:
                base_branch_check = (False, base_branch_covered(platform_base_branches, target_base))
            except PatternTimeoutError:
                base_branch_check = (True, False)
        bucket_results = [
            classify_platform_in_bucket(
                name,
                bucket,
                target_base=target_base,
                pr_state=pr_state,
                platform_configs=platform_configs,
                shared_config_ref=checked_shared_config_ref,
                override_added=bucket in override_added_buckets,
                base_branch_check=base_branch_check,
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
        # Appended after aggregation so a partial per-bucket removal never
        # changes this platform's overall verdict or merged reason/detail
        # text — it only adds visible provenance to bucket_results.
        for stage in override_removed_buckets:
            bucket_results.append(
                {
                    "bucket": stage,
                    "verdict": "override-excluded",
                    "reasons": [],
                    "surface": "",
                    "setting": "",
                    "detail": "removed from the resolved reviewer list by the machine-local override for this bucket",
                    "remedy": "",
                }
            )
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
                "override_added": bool(override_added_buckets),
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

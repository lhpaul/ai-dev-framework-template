#!/usr/bin/env python3
"""Assemble reviewer_preflight.py's input JSON from resolver/probe fragments.

Kept as a small standalone module (rather than an embedded shell heredoc) so
it stays testable and readable. Decision 2 of the implementation plan: this
module still performs no git/gh I/O of its own — reviewer-preflight.sh has
already resolved every fragment path this script reads.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

BUCKET_MAP = {
    "on_draft.runner": "on_draft_runner",
    "on_draft.github": "on_draft_github",
    "on_ready.github": "on_ready_github",
}

ALL_BUCKETS = ("on_draft_runner", "on_draft_github", "on_ready_github")


def _load_json(path: str) -> dict[str, Any] | None:
    if not path:
        return None
    candidate = Path(path)
    if not candidate.is_file():
        return None
    with candidate.open(encoding="utf-8") as handle:
        return json.load(handle)


def _parse_stage_list(csv: str) -> list[str]:
    """Parse ``--remaining-stages``'s comma-separated bucket-token value.

    #1561 round-12 finding: a genuinely empty ``csv`` (the CLI's own
    explicit-empty-stages short-circuit in reviewer-preflight.sh, which
    always calls this with ``--remaining-stages ""``) is the legitimate
    "no stages remaining" signal and must still parse to ``[]``. But a
    NON-empty csv containing only whitespace/separators (e.g. ``",,"``, a
    lone ``","``, or a leading/trailing comma) previously stripped every
    resulting empty token and silently normalized to that same ``[]`` —
    conflating deliberately-empty input with malformed input. That let a
    malformed ``--remaining-stages`` value reach classify()'s own
    ``if not remaining_stages: return {"outcome": "no-review-remaining"}``
    branch (exit 0, no reviewer checks at all) instead of its
    ``PrerequisiteFailed`` branch (exit 2), which the decision matrix
    requires for malformed stage input. Only the whole-string-empty case
    returns ``[]``; any OTHER split producing an empty segment preserves
    that empty string as an entry, so classify()'s own bucket-membership
    check (an empty string is never a member of ``BUCKET_SUPPORTED``)
    rejects it as malformed, the same as any other unsupported token.
    """
    if not csv:
        return []
    stages = []
    for token in csv.split(","):
        token = token.strip()
        stages.append(BUCKET_MAP.get(token, token) if token else token)
    return stages


def _parse_pr_state(csv: str) -> dict[str, str | None]:
    """Parse ``--pr-state``'s ``bucket=state,...`` value.

    A repeated bucket key (e.g. ``on_draft.runner=draft,on_draft.runner=
    ready``) is rejected rather than "last value wins": which pull-request
    state Step 7's own dispatch actually used for that bucket is unknowable
    from an ambiguously composed string alone, and silently keeping the
    last-parsed value let an earlier, differently-classified state (e.g.
    stage-excluded/blocked) be silently overridden by a later one that
    happens to pass. classify()'s own existing prerequisite-failed check
    (``pr_state.get(stage) not in ("draft", "ready")``) already rejects
    any value that is not exactly ``"draft"`` or ``"ready"`` — clearing a
    repeated bucket's value to ``None`` routes it through that same,
    already-established check rather than inventing a new outcome.
    """
    state: dict[str, str | None] = {}
    for pair in csv.split(","):
        pair = pair.strip()
        if not pair or "=" not in pair:
            continue
        key, value = pair.split("=", 1)
        bucket = BUCKET_MAP.get(key.strip(), key.strip())
        if bucket in state:
            state[bucket] = None
            continue
        state[bucket] = value.strip()
    return state


def build(args: argparse.Namespace) -> dict[str, Any]:
    shared: dict[str, list[str]] = {bucket: [] for bucket in ALL_BUCKETS}
    resolved: dict[str, list[str]] = {bucket: [] for bucket in ALL_BUCKETS}
    malformed_buckets: list[str] = []

    runner_data = _load_json(args.runner_json)
    if runner_data is not None:
        shared["on_draft_runner"] = runner_data.get("shipped_runner", [])
        if runner_data.get("effective_runner_state") == "malformed":
            malformed_buckets.append("on_draft_runner")
        else:
            resolved["on_draft_runner"] = runner_data.get("effective_runner", [])

    github_data = _load_json(args.github_json)
    if github_data is not None:
        shared["on_draft_github"] = github_data.get("shipped_on_draft_github", [])
        shared["on_ready_github"] = github_data.get("shipped_on_ready_github", [])
        if github_data.get("effective_on_draft_github_state") == "malformed":
            malformed_buckets.append("on_draft_github")
        else:
            resolved["on_draft_github"] = github_data.get("effective_on_draft_github", [])
        if github_data.get("effective_on_ready_github_state") == "malformed":
            malformed_buckets.append("on_ready_github")
        else:
            resolved["on_ready_github"] = github_data.get("effective_on_ready_github", [])

    platform_configs: dict[str, Any] = {}
    if args.coderabbit_read == "ok":
        cr = _load_json(args.coderabbit_json) or {}
        platform_configs["coderabbit"] = {"read": True, **cr}
    elif args.coderabbit_read in ("no-readable-surface", "check-inconclusive"):
        entry: dict[str, Any] = {"read": False, "reason": args.coderabbit_read}
        if args.coderabbit_prior_reasons:
            entry["prior_reasons"] = [
                reason for reason in args.coderabbit_prior_reasons.split(",") if reason
            ]
        platform_configs["coderabbit"] = entry

    remaining_stages: list[str] | None
    if args.remaining_stages_provided != "1":
        remaining_stages = None
    else:
        remaining_stages = _parse_stage_list(args.remaining_stages)

    # Decision 5's malformed-shared-list stop applies only to buckets a
    # lifecycle stage still ahead of this item will actually use. Checking
    # every bucket unconditionally — including one from an already-completed
    # stage nothing remaining reads — would fail closed on history that
    # cannot affect this run, and would run ahead of the engine's own fixed
    # prerequisite order (stage-set resolvability, then the empty-remaining-
    # stages short-circuit, both of which must be able to win first). An
    # unresolved remaining-stage set (missing --remaining-stages), or one
    # containing a token classify()'s own validation would reject, must defer
    # entirely to the engine's own prerequisite-failed handling for that —
    # screening malformed_buckets against an invalid stage set here would let
    # this module's shell-level malformed-list stop preempt the engine's
    # prerequisite-failed verdict for the stage set itself, which the fixed
    # order requires to win first.
    # A duplicate stage name is malformed input to classify() too (its own
    # `len(remaining_stages) != len(set(remaining_stages))` check) — this
    # predicate must reject it the same way, or a duplicate-containing
    # stage set that also happens to include a genuinely malformed bucket
    # would still let this module's shell-level malformed-list stop win
    # over the engine's own prerequisite-failed verdict for the duplicate.
    stage_set_valid = (
        remaining_stages is not None
        and all(isinstance(stage, str) and stage in ALL_BUCKETS for stage in remaining_stages)
        and len(remaining_stages) == len(set(remaining_stages))
    )
    if not stage_set_valid:
        malformed_buckets = []
    else:
        malformed_buckets = [bucket for bucket in malformed_buckets if bucket in remaining_stages]

    payload: dict[str, Any] = {
        "target_base": args.target_base or None,
        "remaining_stages": remaining_stages,
        "pr_state": _parse_pr_state(args.pr_state),
        "shared": shared,
        "resolved": resolved,
        "checked_shared_config_ref": args.checked_shared_config_ref,
        "checked_platform_config_ref": args.checked_platform_config_ref,
        "local_override_state": args.local_override_state,
        "platform_configs": platform_configs,
        "malformed_buckets": malformed_buckets,
    }
    return payload


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Build reviewer_preflight.py input JSON")
    parser.add_argument("--runner-json", default="")
    parser.add_argument("--github-json", default="")
    parser.add_argument("--coderabbit-json", default="")
    parser.add_argument("--coderabbit-read", default="", choices=["", "ok", "no-readable-surface", "check-inconclusive"])
    parser.add_argument("--coderabbit-prior-reasons", default="")
    parser.add_argument("--target-base", default="")
    parser.add_argument("--remaining-stages", default="")
    parser.add_argument("--remaining-stages-provided", default="0")
    parser.add_argument("--pr-state", default="")
    parser.add_argument("--checked-shared-config-ref", default="")
    parser.add_argument("--checked-platform-config-ref", default="")
    parser.add_argument("--local-override-state", default="none")
    parser.add_argument("--output", required=True)
    args = parser.parse_args(argv)

    payload = build(args)
    with open(args.output, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, sort_keys=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

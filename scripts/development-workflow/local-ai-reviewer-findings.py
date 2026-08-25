#!/usr/bin/env python3
"""Normalize and compare local reviewer findings.

The helper is intentionally conservative: ambiguous ready-phase matches are
reported as net-new instead of being collapsed away.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


def norm(value: Any) -> str:
    text = "" if value is None else str(value).lower()
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    return text or "unclassified"


def title_norm(value: Any) -> str:
    text = "" if value is None else str(value).lower()
    text = re.sub(r"\s+", " ", text).strip()
    return text


def line_range(item: dict[str, Any]) -> tuple[int | None, int | None]:
    start = item.get("start_line", item.get("line"))
    end = item.get("end_line", start)
    try:
        start_i = int(start) if start not in (None, "") else None
        end_i = int(end) if end not in (None, "") else start_i
    except (TypeError, ValueError):
        return None, None
    return start_i, end_i


def ranges_overlap(left: dict[str, Any], right: dict[str, Any]) -> bool:
    left_start, left_end = line_range(left)
    right_start, right_end = line_range(right)
    if left_start is None or right_start is None:
        return False
    assert left_end is not None
    assert right_end is not None
    return left_start <= right_end and right_start <= left_end


def normalize_item(item: dict[str, Any], index: int) -> dict[str, Any]:
    title = item.get("title") or item.get("summary") or item.get("message") or item.get("body") or ""
    return {
        "id": str(item.get("id") or f"finding-{index}"),
        "head": str(item.get("head") or item.get("head_sha") or item.get("reviewed_head") or ""),
        "severity": norm(item.get("severity") or item.get("level")),
        "path": str(item.get("path") or item.get("file") or ""),
        "start_line": line_range(item)[0],
        "end_line": line_range(item)[1],
        "affected_scope": norm(item.get("affected_scope") or item.get("scope") or item.get("path") or "repo"),
        "title": str(title),
        "title_key": title_norm(title),
        "category_key": norm(item.get("category_key") or item.get("category")),
        "requirement_key": norm(item.get("requirement_key") or item.get("requirement")),
        "failure_mode_key": norm(item.get("failure_mode_key") or item.get("failure_mode")),
        "summary": str(item.get("summary") or item.get("message") or item.get("body") or title),
    }


def load_findings(path: str) -> list[dict[str, Any]]:
    raw = json.loads(Path(path).read_text())
    if isinstance(raw, dict):
        raw_items = raw.get("findings", [])
    else:
        raw_items = raw
    if not isinstance(raw_items, list):
        raise ValueError(f"{path} does not contain a findings array")
    return [normalize_item(item, idx + 1) for idx, item in enumerate(raw_items) if isinstance(item, dict)]


def dedupe(items: list[dict[str, Any]], include_title: bool) -> list[dict[str, Any]]:
    seen: set[tuple[str, ...]] = set()
    result: list[dict[str, Any]] = []
    for item in items:
        key = (
            item["head"],
            item["affected_scope"],
            item["category_key"],
            item["requirement_key"],
            item["failure_mode_key"],
        )
        if include_title:
            key = (*key, item["title_key"])
        if key in seen:
            continue
        seen.add(key)
        result.append(item)
    return result


def same_class(left: dict[str, Any], right: dict[str, Any]) -> bool:
    return (
        left["category_key"] == right["category_key"]
        and left["requirement_key"] == right["requirement_key"]
        and left["failure_mode_key"] == right["failure_mode_key"]
    )


def matches(local: dict[str, Any], ready: dict[str, Any]) -> bool:
    if local["head"] and ready["head"] and local["head"] != ready["head"]:
        return False
    if "unclassified" in {local["category_key"], local["requirement_key"], local["failure_mode_key"],
                          ready["category_key"], ready["requirement_key"], ready["failure_mode_key"]}:
        return local["affected_scope"] == ready["affected_scope"] and local["title_key"] == ready["title_key"]
    if local["affected_scope"] == ready["affected_scope"] and same_class(local, ready):
        return True
    if local["path"] and local["path"] == ready["path"] and ranges_overlap(local, ready):
        return local["requirement_key"] == ready["requirement_key"]
    return False


def compare(local_items: list[dict[str, Any]], ready_items: list[dict[str, Any]]) -> dict[str, Any]:
    local_deduped = dedupe(local_items, include_title=False)
    ready_deduped = dedupe(ready_items, include_title=True)
    consumed: set[str] = set()
    net_new: list[dict[str, Any]] = []
    matched: list[dict[str, str]] = []

    for ready in ready_deduped:
        candidates = [item for item in local_deduped if item["id"] not in consumed and matches(item, ready)]
        if len(candidates) == 1:
            consumed.add(candidates[0]["id"])
            matched.append({"ready_id": ready["id"], "local_id": candidates[0]["id"]})
        else:
            copy = dict(ready)
            if len(candidates) > 1:
                copy["ambiguous_candidate_ids"] = [item["id"] for item in candidates]
            net_new.append(copy)

    return {
        "local_count": len(local_deduped),
        "ready_count": len(ready_deduped),
        "matched_count": len(matched),
        "net_new_count": len(net_new),
        "matched": matched,
        "net_new": net_new,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--local", required=True)
    parser.add_argument("--ready", required=True)
    args = parser.parse_args()
    print(json.dumps(compare(load_findings(args.local), load_findings(args.ready)), indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

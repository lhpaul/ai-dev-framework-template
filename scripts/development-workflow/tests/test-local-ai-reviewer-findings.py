#!/usr/bin/env python3
"""Tests for local-ai-reviewer-findings.py."""

from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
HELPER_PATH = REPO_ROOT / "scripts" / "development-workflow" / "local-ai-reviewer-findings.py"
spec = importlib.util.spec_from_file_location("local_ai_reviewer_findings", HELPER_PATH)
assert spec and spec.loader
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)

PASS_COUNT = 0
FAIL_COUNT = 0


def check(name: str, expected, actual) -> None:
    global PASS_COUNT, FAIL_COUNT
    if expected == actual:
        print(f"PASS: {name}")
        PASS_COUNT += 1
    else:
        print(f"FAIL: {name} - expected {expected!r}, got {actual!r}")
        FAIL_COUNT += 1


def norm(items):
    return [helper.normalize_item(item, index + 1) for index, item in enumerate(items)]


same_local = norm([
    {
        "id": "l1",
        "head": "abc",
        "path": "scripts/a.sh",
        "line": 10,
        "affected_scope": "scripts/a.sh",
        "category_key": "validation",
        "requirement_key": "tests",
        "failure_mode_key": "missing",
        "title": "Add test",
    }
])

same_ready = norm([
    {
        "id": "r1",
        "head": "abc",
        "path": "scripts/a.sh",
        "line": 10,
        "affected_scope": "scripts/a.sh",
        "category_key": "validation",
        "requirement_key": "tests",
        "failure_mode_key": "missing",
        "title": "Test is missing",
    }
])
check("same_class_matches", 0, helper.compare(same_local, same_ready)["net_new_count"])

different_key_ready = norm([
    {
        "id": "r2",
        "head": "abc",
        "path": "scripts/a.sh",
        "line": 10,
        "affected_scope": "scripts/a.sh",
        "category_key": "validation",
        "requirement_key": "review-contract",
        "failure_mode_key": "missing",
        "title": "Review contract missing",
    }
])
check("same_path_different_key_net_new", 1, helper.compare(same_local, different_key_ready)["net_new_count"])

ambiguous_local = norm([
    {
        "id": "l1",
        "head": "abc",
        "path": "scripts/a.sh",
        "line": 10,
        "affected_scope": "scripts/a.sh",
        "category_key": "validation",
        "requirement_key": "tests",
        "failure_mode_key": "missing",
        "title": "First",
    },
    {
        "id": "l2",
        "head": "abc",
        "path": "scripts/a.sh",
        "line": 10,
        "affected_scope": "scripts/a.sh",
        "category_key": "documentation",
        "requirement_key": "tests",
        "failure_mode_key": "missing",
        "title": "Second",
    },
])
ambiguous_ready = norm([
    {
        "id": "r1",
        "head": "abc",
        "path": "scripts/a.sh",
        "line": 10,
        "affected_scope": "scripts/a.sh",
        "category_key": "review",
        "requirement_key": "tests",
        "failure_mode_key": "missing",
        "title": "Missing test",
    }
])
ambiguous = helper.compare(ambiguous_local, ambiguous_ready)
check("ambiguous_counts_net_new", 1, ambiguous["net_new_count"])
check("ambiguous_candidate_ids", ["l1", "l2"], ambiguous["net_new"][0]["ambiguous_candidate_ids"])

two_ready = norm([
    {
        "id": "r1",
        "head": "abc",
        "affected_scope": "scripts/a.sh",
        "category_key": "validation",
        "requirement_key": "tests",
        "failure_mode_key": "missing",
        "title": "A",
    },
    {
        "id": "r2",
        "head": "abc",
        "affected_scope": "scripts/a.sh",
        "category_key": "validation",
        "requirement_key": "tests",
        "failure_mode_key": "missing",
        "title": "B",
    },
])
one_to_one = helper.compare(same_local, two_ready)
check("one_local_not_consumed_twice", 1, one_to_one["matched_count"])
check("second_ready_net_new", 1, one_to_one["net_new_count"])

unclassified_local = norm([
    {"id": "l1", "head": "abc", "affected_scope": "repo", "title": "Same words"},
])
unclassified_ready_same = norm([
    {"id": "r1", "head": "abc", "affected_scope": "repo", "title": "Same words"},
])
unclassified_ready_diff = norm([
    {"id": "r2", "head": "abc", "affected_scope": "repo", "title": "Different words"},
])
check("unclassified_exact_title_matches", 0, helper.compare(unclassified_local, unclassified_ready_same)["net_new_count"])
check("unclassified_different_title_net_new", 1, helper.compare(unclassified_local, unclassified_ready_diff)["net_new_count"])

with tempfile.TemporaryDirectory() as tmp:
    local_path = Path(tmp) / "local.json"
    ready_path = Path(tmp) / "ready.json"
    local_path.write_text(json.dumps({"findings": [{"id": "l1", "head": "abc", "affected_scope": "repo", "title": "Same"}]}))
    ready_path.write_text(json.dumps([{"id": "r1", "head": "abc", "affected_scope": "repo", "title": "Same"}]))
    check("load_findings_dict", "l1", helper.load_findings(str(local_path))[0]["id"])
    check("load_findings_list", "r1", helper.load_findings(str(ready_path))[0]["id"])

if FAIL_COUNT:
    raise SystemExit(f"FAIL: {FAIL_COUNT} test(s) failed")

print(f"PASS: {PASS_COUNT} test(s) passed")

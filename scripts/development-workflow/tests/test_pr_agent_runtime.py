"""Publication regressions; synthetic state, no GitHub or model calls."""

import importlib.util
import json
import logging
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("pr_agent_runtime", ROOT / "scripts/development-workflow/pr-agent-runtime.py")
runtime = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = runtime
SPEC.loader.exec_module(runtime)
HEADERS = ("## PR Reviewer Guide", "## Incremental PR Reviewer Guide")
IMAGE_SMOKE = os.environ.get("PR_AGENT_IMAGE_SMOKE") == "1"


class SyntheticState:
    """Unit-test boundary double; image mode uses the actual producer helpers."""

    @staticmethod
    def serialize_review_state(state):
        payload = json.dumps(state, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        payload = payload.replace("-->", "--\\u003e").replace("--!>", "--!\\u003e")
        return "<!-- pr-agent-review-state:v1\n" + payload + "\n-->"

    @staticmethod
    def parse_review_state(body):
        count = body.count("<!-- pr-agent-review-state:")
        if not count:
            return SimpleNamespace(state=None, present=False, valid=True)
        match = re.search(r"<!-- pr-agent-review-state:v1\n(.*?)\n-->", body, re.S)
        try:
            state = json.loads(match.group(1)) if match and count == 1 else None
        except ValueError:
            state = None
        valid = isinstance(state, dict) and state.get("schema_version") == 1
        return SimpleNamespace(state=state if valid else None, present=True, valid=valid)

    @staticmethod
    def split_review_state_marker(body):
        match = re.search(r"<!-- pr-agent-review-state:v1\n.*?\n-->", body, re.S)
        return ((body[:match.start()] + body[match.end():]).rstrip(), match.group(0)) if match else (body, "")

    @staticmethod
    def _render_resolved_section(state):
        findings = [f for f in state["findings"] if f["state"] == "RESOLVED"]
        findings.sort(key=lambda f: (str(f.get("resolved_at") or ""), f["finding_id"]), reverse=True)
        if not findings:
            return ""
        return "<details>\n<summary>✅ Resolved findings</summary>\n\n" + "\n\n".join(
            "### " + f["path"] + "\n\n" + f["body"] for f in findings
        ) + "\n\n</details>"


if IMAGE_SMOKE:
    import pr_agent.algo.review_finding_state as STATE
else:
    STATE = SyntheticState


def state(size=70000, resolved=False):
    return {"schema_version": 1, "last_run": {"head_sha": "a" * 40, "complete": True, "kind": "full"},
            "findings": [{"finding_id": "synthetic-1", "path": "src/example.py", "body": "é雪-->--!>" + "x" * size,
                          "state": "RESOLVED" if resolved else "ACTIVE"}]}


def review(blocking=False, excerpt="", suffix=""):
    if blocking:
        focus = ('<strong>Recommended focus areas for review</strong><br><br>\n'
                 '<details><summary><a href="https://example.invalid/source"><strong>Must fix</strong></a>\n\n'
                 'The original blocker must remain visible.\n</summary>\n' + excerpt + '\n</details>')
    else:
        focus = '<strong>No major issues detected</strong>'
    return ('## PR Reviewer Guide 🔍\n\n<!-- pr-agent:review:full -->\n\n'
            'Here are some key observations to aid the review process:\n\n<table>\n'
            '<tr><td>🔒&nbsp;<strong>No security concerns identified</strong></td></tr>\n'
            '<tr><td>⚡&nbsp;' + focus + '</td></tr>\n</table>\n' + suffix)


def compose(visible, snapshot):
    sections = [visible.rstrip(), STATE._render_resolved_section(snapshot), STATE.serialize_review_state(snapshot)]
    return "\n\n".join(s for s in sections if s) + "\n"


def classify(body):
    return subprocess.run(
        ["bash", str(ROOT / "scripts/development-workflow/apply-readiness-labels.sh"), "--classify-pr-agent"],
        input=body, text=True, capture_output=True, check=True,
    ).stdout.strip()


# Complete producer comments from #1967; issuecomment ids 6180457309 / 6192010352.
HTML_INLINE_REVIEWS = {
    '1966': (
        '## PR Reviewer Guide 🔍\n'
        '\n'
        '<!-- pr-agent:review:full -->\n'
        '\n'
        'Here are some key observations to aid the review process:\n'
        '\n'
        '<table>\n'
        '<tr><td>⏱️&nbsp;<strong>Estimated effort to review</strong>: 3 🔵🔵🔵⚪⚪</td></tr>\n'
        '<tr><td>🧪&nbsp;<strong>PR contains tests</strong></td></tr>\n'
        '<tr><td>🔒&nbsp;<strong>No security concerns identified</strong></td></tr>\n'
        '<tr><td>⚡&nbsp;<strong>Recommended focus areas for review</strong><br><br>\n'
        '\n'
        "<details><summary><a href='https://github.com/lhpaul/ai-dev-framework-template/pull/1966/files#diff-5fa4b162a9e57de4f6e9dfcb5398951dacfdc660caae3d8f8daf42962921dc46R1236-R1242'><strong>Possible Issue</strong></a>\n"
        '\n'
        'The new `--release-head` authorization check reads `$child_binding` and `$SESSION_CHILD`, but these are only assigned inside the `if [ -n "$MERGE_SESSION" ] && [ -n "${WORKFLOW_MERGE_BUDGET_TOKEN:-}" ]` block. When a caller passes `--release-head` without a merge session (or without the budget token), `child_binding` is unset. Under `set -u` (nounset, used by these scripts) the `printf \'%s\' "$child_binding"` in the rejection branch would abort with an unbound-variable error rather than the intended exit 2 message. The guard should default `child_binding` (e.g. `child_binding=""`) before the check, or test `$SESSION_CHILD` first. Note: the added test `test_release_head_rejected_before_ordinary_cleanup` passes `--release-head` without a session, so if that test passes it may indicate the variable is initialized elsewhere in the file — verify the initialization before treating this as confirmed.\n'
        '</summary>\n'
        '\n'
        '```shell\n'
        'if [ "$RELEASE_HEAD_SET" = "true" ] && [ "$INSPECT_TARGETS" != "true" ]; then\n'
        '  if [ "$SESSION_CHILD" != "true" ] || ! printf \'%s\' "$child_binding" | jq -e --arg head "$RELEASE_HEAD" \\\n'
        "    '.releasePair != null and .releasePair.head == $head and .selectedPR == .releasePair.backportPr' >/dev/null; then\n"
        '    echo "--release-head is only supported for read-only --inspect-targets or the authenticated owning release cleanup child." >&2\n'
        '    exit 2\n'
        '  fi\n'
        'fi\n'
        '```\n'
        '\n'
        '</details>\n'
        '\n'
        '</td></tr>\n'
        '</table>\n'
        '\n'
        '<!-- pr-agent-review-state:v1\n'
        '{"findings":[{"body":"**Possible Issue**\\n\\nThe new `--release-head` authorization check reads `$child_binding` and `$SESSION_CHILD`, but these are only assigned inside the `if [ -n \\"$MERGE_SESSION\\" ] && [ -n \\"${WORKFLOW_MERGE_BUDGET_TOKEN:-}\\" ]` block. When a caller passes `--release-head` without a merge session (or without the budget token), `child_binding` is unset. Under `set -u` (nounset, used by these scripts) the `printf \'%s\' \\"$child_binding\\"` in the rejection branch would abort with an unbound-variable error rather than the intended exit 2 message. The guard should default `child_binding` (e.g. `child_binding=\\"\\"`) before the check, or test `$SESSION_CHILD` first. Note: the added test `test_release_head_rejected_before_ordinary_cleanup` passes `--release-head` without a session, so if that test passes it may indicate the variable is initialized elsewhere in the file — verify the initialization before treating this as confirmed.","finding_id":"a31a4f1947d3","first_seen":"2026-10-14T23:06:44.710516Z","last_seen":"2026-10-14T23:06:44.710516Z","last_seen_head_sha":"73d1bd159b1b1bd1f52459ecc33939ee78b826a6","line_end":1242,"line_start":1236,"path":"scripts/development-workflow/prepare-release-post-merge-cleanup.sh","state":"ACTIVE"}],"last_run":{"complete":true,"excluded_files":[],"head_sha":"73d1bd159b1b1bd1f52459ecc33939ee78b826a6","kind":"full","run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/73d1bd159b1b1bd1f52459ecc33939ee78b826a6"},"schema_version":1}\n'
        '-->\n'
        '\n'
    ),
    '1974': (
        '## PR Reviewer Guide 🔍\n'
        '\n'
        '<!-- pr-agent:review:full -->\n'
        '\n'
        '#### (Review updated until commit https://github.com/lhpaul/ai-dev-framework-template/commit/76a0820f0f899398040511c40c16182a8aaab127)\n'
        '\n'
        '\n'
        'Here are some key observations to aid the review process:\n'
        '\n'
        '<table>\n'
        '<tr><td>⏱️&nbsp;<strong>Estimated effort to review</strong>: 4 🔵🔵🔵🔵⚪</td></tr>\n'
        '<tr><td>🧪&nbsp;<strong>PR contains tests</strong></td></tr>\n'
        '<tr><td>🔒&nbsp;<strong>No security concerns identified</strong></td></tr>\n'
        '<tr><td>⚡&nbsp;<strong>Recommended focus areas for review</strong><br><br>\n'
        '\n'
        "<details><summary><a href='https://github.com/lhpaul/ai-dev-framework-template/pull/1974/files#diff-69990674c60490161235d30d9b51b9c6d186bdee2ab0fa8e1029dca6abb9858fR365-R378'><strong>Possible Issue</strong></a>\n"
        '\n'
        'The `protected_risk_path` function matches release tooling with patterns like `scripts/*release*.sh`, `.github/workflows/*release*`, and `.agents/skills/*release*/*`. These use `*` which in shell `case` matches across `/` boundaries, so a path such as `scripts/development-workflow/prepare-release-post-merge-cleanup.sh` matches `scripts/*release*.sh` (intended), but also a nested path like `scripts/foo/bar/release-helper.sh` would match. More importantly, the pattern `.github/workflows/*release*` will match any workflow whose name contains `release` anywhere, including `deploy-release-notes.yml`, which is the intended conservative behavior. This is likely intentional, but verify that the broad `*release*` matching does not re-introduce the false-positive class the PR aims to fix for paths under `scripts/` that merely mention release in a subdirectory name (e.g. `scripts/docs/release-notes.md` would not match since it requires `.sh`/`.py`). Confirm the tooling-root scoping is as narrow as the plan intends.\n'
        '</summary>\n'
        '\n'
        '```shell\n'
        'protected_risk_path() {\n'
        '  case "$1" in\n'
        '    scripts/*release*.sh|scripts/*release*.py|.github/workflows/*release*|\\\n'
        '    .claude/commands/*release*.md|.cursor/commands/*release*.md|\\\n'
        '    .agents/skills/*release*/*|.codex/skills/*release*/*|\\\n'
        '    *branch-deletion*|*delete-branch*|\\\n'
        '    auth/*|*/auth/*|*/auth|authentication/*|*/authentication/*|*/authentication|\\\n'
        '    secret/*|*/secret/*|*/secret|secrets/*|*/secrets/*|*/secrets|\\\n'
        '    credential/*|*/credential/*|*/credential|credentials/*|*/credentials/*|*/credentials|\\\n'
        '    permission/*|*/permission/*|*/permission|permissions/*|*/permissions/*|*/permissions)\n'
        '      return 0 ;;\n'
        '  esac\n'
        '  return 1\n'
        '}\n'
        '```\n'
        '\n'
        '</details>\n'
        '\n'
        "<details><summary><a href='https://github.com/lhpaul/ai-dev-framework-template/pull/1974/files#diff-c6cd4825f13ea12046fe63020bbb4ae7cda1684a24d681b71e8e54b06b72acafR82-R98'><strong>Possible Issue</strong></a>\n"
        '\n'
        'In `select_map`, when `mode == "workflow_hub"` and `own_map` is present but no product maps exist, and no product identity is supplied, the code falls through to `raise RiskPathError("project risk map requires an unambiguous project identity")` only when `product_maps` is non-empty. When `all(node is MISSING for node in product_maps)` is true and `own_map` is not MISSING, the `elif all(...)` branch returns `own_map`. This means a hub with a top-level map but no product maps and no selector silently uses the hub map for any product, which may be intended. However, if `product_maps` is non-empty but the selected product has no map, `map_node` returns MISSING and `rules_from_node` yields no rules, so the product silently gets built-ins rather than the hub map — verify this matches the documented "absent product rules use built-ins and never inherit sibling or hub categories" behavior. The concern is whether a product entry that omits `guardrails` is distinguishable from one that intends to inherit; the docs say it should not inherit, so this appears correct, but the fall-through ordering deserves a test for the mixed case (some products mapped, some not).\n'
        '</summary>\n'
        '\n'
        '```python\n'
        'if selected:\n'
        '    candidates = [repo for repo in repos if repo["name"] == selected]\n'
        'elif slug:\n'
        '    if slug == reader.parse_remote_slug(root):\n'
        '        return own_map, location\n'
        '    candidates = [repo for repo in repos if repo_slug(repo) == slug]\n'
        'elif all(node is MISSING for node in product_maps):\n'
        '    return own_map, location\n'
        'else:\n'
        '    raise RiskPathError("project risk map requires an unambiguous project identity")\n'
        'if len(candidates) != 1:\n'
        '    raise RiskPathError("project risk map target is unknown or ambiguous")\n'
        'selected_repo = candidates[0]\n'
        'if slug and repo_slug(selected_repo) != slug:\n'
        '    raise RiskPathError("project risk map selector and evidence repository disagree")\n'
        'location = "workflow_hub.product_repos[].guardrails.risk_paths"\n'
        'return map_node(selected_repo, "selected product"), location\n'
        '```\n'
        '\n'
        '</details>\n'
        '\n'
        '</td></tr>\n'
        '</table>\n'
        '\n'
        '<!-- pr-agent-review-state:v1\n'
        '{"findings":[{"body":"**Possible Issue**\\n\\nThe `changed_file_risk` function now rebuilds `file_reasons` for each file and appends to the global `reasons` array. For files that match the `scripts/development-workflow/tests/*|test/*|tests/*` case, `file_risk` remains `low` and a reason is appended. However, if a project map matches the same file with a higher risk, the project risk overrides `file_risk` but the built-in reason is still appended. This means the reasons array may contain both the built-in \\"low-risk docs or tests change\\" reason and the project reason, even though the final risk is higher. This is likely intentional for visibility, but could be confusing. The test `mapped_reason_is_visible` checks for project reason presence, not absence of built-in reasons.","finding_id":"3443f7ae914b","first_seen":"2026-10-15T12:26:28.618644Z","last_seen":"2026-10-15T12:26:28.618644Z","last_seen_head_sha":"76a0820f0f899398040511c40c16182a8aaab127","line_end":418,"line_start":407,"path":"scripts/development-workflow/run-epic-risk-classifier.sh","state":"ACTIVE"},{"body":"**Possible Issue**\\n\\nThe `protected_risk_path` function matches release tooling with patterns like `scripts/*release*.sh`, `.github/workflows/*release*`, and `.agents/skills/*release*/*`. These use `*` which in shell `case` matches across `/` boundaries, so a path such as `scripts/development-workflow/prepare-release-post-merge-cleanup.sh` matches `scripts/*release*.sh` (intended), but also a nested path like `scripts/foo/bar/release-helper.sh` would match. More importantly, the pattern `.github/workflows/*release*` will match any workflow whose name contains `release` anywhere, including `deploy-release-notes.yml`, which is the intended conservative behavior. This is likely intentional, but verify that the broad `*release*` matching does not re-introduce the false-positive class the PR aims to fix for paths under `scripts/` that merely mention release in a subdirectory name (e.g. `scripts/docs/release-notes.md` would not match since it requires `.sh`/`.py`). Confirm the tooling-root scoping is as narrow as the plan intends.","finding_id":"3960ab9411ef","first_seen":"2026-10-15T12:28:02.850774Z","last_seen":"2026-10-15T12:28:02.850774Z","last_seen_head_sha":"76a0820f0f899398040511c40c16182a8aaab127","line_end":378,"line_start":365,"path":"scripts/development-workflow/run-epic-risk-classifier.sh","state":"ACTIVE"},{"body":"**Possible Issue**\\n\\nIn `select_map`, when `mode == \\"workflow_hub\\"` and `own_map` is present but no product maps exist, and no product identity is supplied, the code falls through to `raise RiskPathError(\\"project risk map requires an unambiguous project identity\\")` only when `product_maps` is non-empty. When `all(node is MISSING for node in product_maps)` is true and `own_map` is not MISSING, the `elif all(...)` branch returns `own_map`. This means a hub with a top-level map but no product maps and no selector silently uses the hub map for any product, which may be intended. However, if `product_maps` is non-empty but the selected product has no map, `map_node` returns MISSING and `rules_from_node` yields no rules, so the product silently gets built-ins rather than the hub map — verify this matches the documented \\"absent product rules use built-ins and never inherit sibling or hub categories\\" behavior. The concern is whether a product entry that omits `guardrails` is distinguishable from one that intends to inherit; the docs say it should not inherit, so this appears correct, but the fall-through ordering deserves a test for the mixed case (some products mapped, some not).","finding_id":"55f491a5f239","first_seen":"2026-10-15T12:28:02.850774Z","last_seen":"2026-10-15T12:28:02.850774Z","last_seen_head_sha":"76a0820f0f899398040511c40c16182a8aaab127","line_end":98,"line_start":82,"path":"scripts/development-workflow/workflow-risk-paths.py","state":"ACTIVE"},{"body":"**Possible Issue**\\n\\nThe `protected_risk_path` function is invoked before the built-in `case` categories, and it returns `high` for any path matching `scripts/*release*.sh`. However, the previous `*release*` pattern was intentionally broad and also covered release-named docs. The new function narrows release detection to tooling roots, which is the stated intent. The concern is that `protected_risk_path` is checked first and sets `floor_reason`, but the subsequent `case` block for `.github/workflows/*` can also set `floor_reason` for non-test/lint workflows. If a file matches both `protected_risk_path` (e.g., `.github/workflows/*release*`) and the `.github/workflows/*` case, the `floor_reason` from `protected_risk_path` is set, then the `case` block runs and may overwrite `floor_reason` with the same or a different message. Since both set `file_risk=\\"high\\"`, the final risk is correct, but the reason text may be duplicated or replaced. This is a minor cosmetic issue, not a correctness bug, but worth confirming the reason aggregation is as intended.","finding_id":"6e81189b04dc","first_seen":"2026-10-15T12:26:28.618644Z","last_seen":"2026-10-15T12:26:28.618644Z","last_seen_head_sha":"76a0820f0f899398040511c40c16182a8aaab127","line_end":405,"line_start":391,"path":"scripts/development-workflow/run-epic-risk-classifier.sh","state":"ACTIVE"},{"body":"**Possible Issue**\\n\\nIn `select_map`, when `mode == \\"workflow_hub\\"` and `own_map` is not MISSING but `product_maps` are all MISSING, the function proceeds to select a product. If `selected` is empty and `slug` is empty, it falls through to `elif all(node is MISSING for node in product_maps): return own_map, location`. This is correct. However, if `selected` is provided but no product matches, `candidates` is empty and `len(candidates) != 1` raises an error. This is intended. The concern is the case where `slug` matches the hub remote (`slug == reader.parse_remote_slug(root)`) and `own_map` is MISSING but product maps exist. The function returns `own_map` (MISSING) and location, which means no rules are applied. This is correct for hub-owned files, but if the hub remote slug is provided as evidence for a product file, it would incorrectly use hub policy. The test `test_project_isolation_and_explicit_priority` covers this, so it appears intentional.","finding_id":"a6236f8c966e","first_seen":"2026-10-15T12:26:28.618644Z","last_seen":"2026-10-15T12:26:28.618644Z","last_seen_head_sha":"76a0820f0f899398040511c40c16182a8aaab127","line_end":89,"line_start":82,"path":"scripts/development-workflow/workflow-risk-paths.py","state":"ACTIVE"}],"last_run":{"complete":true,"excluded_files":[],"head_sha":"76a0820f0f899398040511c40c16182a8aaab127","kind":"full","run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/76a0820f0f899398040511c40c16182a8aaab127"},"schema_version":1}\n'
        '-->\n'
        '\n'
    ),
    '1978': (
        '## PR Reviewer Guide 🔍\n'
        '\n'
        '<!-- pr-agent:review:full -->\n'
        '\n'
        '#### (Review updated until commit https://github.com/lhpaul/ai-dev-framework-template/commit/bd05503e5ce7243f948dc13f8203fad18b927105)\n'
        '\n'
        '\n'
        'Here are some key observations to aid the review process:\n'
        '\n'
        '<table>\n'
        '<tr><td>⏱️&nbsp;<strong>Estimated effort to review</strong>: 3 🔵🔵🔵⚪⚪</td></tr>\n'
        '<tr><td>🧪&nbsp;<strong>PR contains tests</strong></td></tr>\n'
        '<tr><td>🔒&nbsp;<strong>No security concerns identified</strong></td></tr>\n'
        '<tr><td>⚡&nbsp;<strong>Recommended focus areas for review</strong><br><br>\n'
        '\n'
        "<details><summary><a href='https://github.com/lhpaul/ai-dev-framework-template/pull/1978/files#diff-dba3e72840843ae37245e2f7afa96e5826cda270ac9fc17c31ea59c73bfbd184R126-R133'><strong>Possible Issue</strong></a>\n"
        '\n'
        'The new inline-HTML gate computes `in_html = bool(html_depth or html_block)` and then rejects when `(in_html and "table" not in html_depth)`. Because `html_block` is a separate variable from `html_depth`, a case where `html_block` is set (e.g. a supported block tag like `details`/`summary`/`strong` opened outside a table) while `html_depth` is empty will satisfy `in_html` and then always raise, even though `html_block` is in `inline_tags`. Conversely, when `html_depth` is non-empty but contains only supported tags and no `table` (e.g. a `<details>` opened via the depth stack rather than the block variable), the `"table" not in html_depth` check rejects it. The intent stated in the comment is "supported only while the producer review table is open", but the condition mixes the two tracking structures inconsistently, so whether a given supported container is accepted depends on which of `html_depth`/`html_block` the parser happened to use for that tag. Verify that the depth-vs-block bookkeeping for `table`/`details`/`summary`/`strong` actually places `table` in `html_depth` for the real producer comments; if any supported wrapper is tracked in `html_block` instead, the span will be rejected despite being listed in `inline_tags`.\n'
        '</summary>\n'
        '\n'
        '```python\n'
        'if source[index] == "`":\n'
        '    in_html = bool(html_depth or html_block)\n'
        '    # Inline HTML is supported only while the producer review table\n'
        '    # is open; an isolated span/details is still ambiguous raw HTML.\n'
        '    if (any(tag not in inline_tags for tag in html_depth)\n'
        '            or html_block not in inline_tags | {None}\n'
        '            or (in_html and "table" not in html_depth)):\n'
        '        raise ValueError("ambiguous backticks in HTML")\n'
        '```\n'
        '\n'
        '</details>\n'
        '\n'
        '</td></tr>\n'
        '</table>\n'
        '\n'
        '<details>\n'
        '<summary>✅ Resolved findings</summary>\n'
        '\n'
        '### scripts/development-workflow/pr-agent-runtime.py:145-148\n'
        '\n'
        '**Possible Issue**\n'
        '\n'
        'The cross-container guard `if in_html and re.search(r"<\\s*/|<!|<\\?", content)` rejects any inline span whose content contains a closing-tag-like sequence or comment opener. This is intended to prevent swallowing container boundaries, but it also rejects legitimate inline code that contains a literal `</` or `<?` sequence, such as documenting `</summary>` or `<?php`. The PR description states the goal is to accept "complete single-backtick inline code" while rejecting "cross-container spans"; a span containing `</summary>` as literal text (not an actual tag boundary) is indistinguishable from a real boundary under this regex. If such content appears in a real producer finding, it will escalate. This may be an acceptable conservative tradeoff, but it is worth confirming the producer never emits inline code containing `</` or `<?` as literal content.\n'
        '\n'
        '### scripts/development-workflow/pr-agent-runtime.py:126-133\n'
        '\n'
        '**Possible Issue**\n'
        '\n'
        'The new inline-HTML gate checks `html_block not in inline_tags | {None}` and `(in_html and "table" not in html_depth)`, but `html_depth` is a list of open tags and `html_block` is a separate variable. The condition `any(tag not in inline_tags for tag in html_depth)` rejects any open tag outside the allowlist, yet the allowlist includes `span`, `a`, `b`, `em`, `strong`, `details`, `summary`, etc. A finding summary like `<details><summary><a href=\'...\'><strong>Possible Issue</strong></a> ...` opens `details`, `summary`, `a`, `strong` — all allowed — so the gate passes. However, the check `(in_html and "table" not in html_depth)` requires `table` to be present in `html_depth` whenever any HTML is open. If the producer table is opened and then closed before the inline span (e.g. a `<details>` block that appears after `</table>` but still within the review body), `html_depth` would no longer contain `table` and the span would be rejected even though it is inside the producer review. This is a narrow trigger, but it means the acceptance is tied to the table being currently open rather than the review being a producer review. Confirm whether the producer format always keeps the table open across all finding spans; if not, valid inline code after the table close would still escalate.\n'
        '\n'
        '</details>\n'
        '\n'
        '<!-- pr-agent-review-state:v1\n'
        '{"findings":[{"body":"**Possible Issue**\\n\\nThe new inline-HTML gate computes `in_html = bool(html_depth or html_block)` and then rejects when `(in_html and \\"table\\" not in html_depth)`. Because `html_block` is a separate variable from `html_depth`, a case where `html_block` is set (e.g. a supported block tag like `details`/`summary`/`strong` opened outside a table) while `html_depth` is empty will satisfy `in_html` and then always raise, even though `html_block` is in `inline_tags`. Conversely, when `html_depth` is non-empty but contains only supported tags and no `table` (e.g. a `<details>` opened via the depth stack rather than the block variable), the `\\"table\\" not in html_depth` check rejects it. The intent stated in the comment is \\"supported only while the producer review table is open\\", but the condition mixes the two tracking structures inconsistently, so whether a given supported container is accepted depends on which of `html_depth`/`html_block` the parser happened to use for that tag. Verify that the depth-vs-block bookkeeping for `table`/`details`/`summary`/`strong` actually places `table` in `html_depth` for the real producer comments; if any supported wrapper is tracked in `html_block` instead, the span will be rejected despite being listed in `inline_tags`.","finding_id":"24521fb8d005","first_seen":"2026-10-15T13:34:17.994063Z","last_seen":"2026-10-15T13:34:17.994063Z","last_seen_head_sha":"bd05503e5ce7243f948dc13f8203fad18b927105","line_end":133,"line_start":126,"path":"scripts/development-workflow/pr-agent-runtime.py","state":"ACTIVE"},{"body":"**Possible Issue**\\n\\nThe new inline-HTML gate checks `html_block not in inline_tags | {None}` and `(in_html and \\"table\\" not in html_depth)`, but `html_depth` is a list of open tags and `html_block` is a separate variable. The condition `any(tag not in inline_tags for tag in html_depth)` rejects any open tag outside the allowlist, yet the allowlist includes `span`, `a`, `b`, `em`, `strong`, `details`, `summary`, etc. A finding summary like `<details><summary><a href=\'...\'><strong>Possible Issue</strong></a> ...` opens `details`, `summary`, `a`, `strong` — all allowed — so the gate passes. However, the check `(in_html and \\"table\\" not in html_depth)` requires `table` to be present in `html_depth` whenever any HTML is open. If the producer table is opened and then closed before the inline span (e.g. a `<details>` block that appears after `</table>` but still within the review body), `html_depth` would no longer contain `table` and the span would be rejected even though it is inside the producer review. This is a narrow trigger, but it means the acceptance is tied to the table being currently open rather than the review being a producer review. Confirm whether the producer format always keeps the table open across all finding spans; if not, valid inline code after the table close would still escalate.","finding_id":"28886a027301","first_seen":"2026-10-15T13:32:23.844031Z","last_seen":"2026-10-15T13:32:23.844031Z","last_seen_head_sha":"283777e2ff0b6f6124e40edaebd294d0956ede2a","line_end":133,"line_start":126,"path":"scripts/development-workflow/pr-agent-runtime.py","resolution_run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/bd05503e5ce7243f948dc13f8203fad18b927105","resolved_at":"2026-10-15T13:34:17.994063Z","resolved_head_sha":"bd05503e5ce7243f948dc13f8203fad18b927105","state":"RESOLVED"},{"body":"**Possible Issue**\\n\\nThe cross-container guard `if in_html and re.search(r\\"<\\\\s*/|<!|<\\\\?\\", content)` rejects any inline span whose content contains a closing-tag-like sequence or comment opener. This is intended to prevent swallowing container boundaries, but it also rejects legitimate inline code that contains a literal `</` or `<?` sequence, such as documenting `</summary>` or `<?php`. The PR description states the goal is to accept \\"complete single-backtick inline code\\" while rejecting \\"cross-container spans\\"; a span containing `</summary>` as literal text (not an actual tag boundary) is indistinguishable from a real boundary under this regex. If such content appears in a real producer finding, it will escalate. This may be an acceptable conservative tradeoff, but it is worth confirming the producer never emits inline code containing `</` or `<?` as literal content.","finding_id":"3a8ca8a08881","first_seen":"2026-10-15T13:32:23.844031Z","last_seen":"2026-10-15T13:32:23.844031Z","last_seen_head_sha":"283777e2ff0b6f6124e40edaebd294d0956ede2a","line_end":148,"line_start":145,"path":"scripts/development-workflow/pr-agent-runtime.py","resolution_run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/bd05503e5ce7243f948dc13f8203fad18b927105","resolved_at":"2026-10-15T13:34:17.994063Z","resolved_head_sha":"bd05503e5ce7243f948dc13f8203fad18b927105","state":"RESOLVED"}],"last_run":{"complete":true,"excluded_files":[],"head_sha":"bd05503e5ce7243f948dc13f8203fad18b927105","kind":"full","run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/bd05503e5ce7243f948dc13f8203fad18b927105"},"schema_version":1}\n'
        '-->\n'
        '\n'
    ),
}


# Complete current PR-Agent report 6193308267, preserved verbatim.
CURRENT_REVIEW_1978 = (
    '## PR Reviewer Guide 🔍\n'
    '\n'
    '<!-- pr-agent:review:full -->\n'
    '\n'
    '#### (Review updated until commit https://github.com/lhpaul/ai-dev-framework-template/commit/a73ffb344cc70aad71018c9e6440c0a2005844f6)\n'
    '\n'
    '\n'
    'Here are some key observations to aid the review process:\n'
    '\n'
    '<table>\n'
    '<tr><td>⏱️&nbsp;<strong>Estimated effort to review</strong>: 4 🔵🔵🔵🔵⚪</td></tr>\n'
    '<tr><td>🧪&nbsp;<strong>PR contains tests</strong></td></tr>\n'
    '<tr><td>🔒&nbsp;<strong>No security concerns identified</strong></td></tr>\n'
    '<tr><td>⚡&nbsp;<strong>Recommended focus areas for review</strong><br><br>\n'
    '\n'
    "<details><summary><a href='https://github.com/lhpaul/ai-dev-framework-template/pull/1978/files#diff-dba3e72840843ae37245e2f7afa96e5826cda270ac9fc17c31ea59c73bfbd184R179-R193'><strong>Possible Issue</strong></a>\n"
    '\n'
    'The `resolved_history` flag is set when a `<details>` block matching the canonical resolved-history pattern opens after the producer table closes, and it is only reset when a matching `</details>` is popped from `html_depth`. However, `resolved_history` is not reset when the parser encounters a new top-level raw HTML block or when the details block is closed via a path that does not pop `html_depth` (e.g. mismatched nesting). If a later, unrelated `<details>` block appears after the history block without an intervening `</details>` that pops the stack, `history_markdown` could remain true and permit inline spans containing `</` or `<?` in a context the PR intends to reject. The tests cover a later `<span>` block but not a later `<details>` block; verify the flag cannot leak past the intended history container.\n'
    '</summary>\n'
    '\n'
    '```python\n'
    'if (not closing and tag_name == "details" and not html_depth\n'
    '        and producer_table_closed\n'
    '        and re.match(r"<details>\\s*<summary>✅ Resolved findings</summary>"\n'
    '                     r"[ \\t]*\\r?\\n[ \\t]*\\r?\\n", source[index:])):\n'
    '    resolved_history = True\n'
    'if not source[line_start:index].strip():\n'
    '    html_block = tag_name\n'
    'if closing:\n'
    '    if html_depth and html_depth[-1] == tag_name:\n'
    '        html_depth.pop()\n'
    '        if not html_depth:\n'
    '            if tag_name == "table":\n'
    '                producer_table_closed = True\n'
    '            if tag_name == "details":\n'
    '                resolved_history = False\n'
    '```\n'
    '\n'
    '</details>\n'
    '\n'
    "<details><summary><a href='https://github.com/lhpaul/ai-dev-framework-template/pull/1978/files#diff-dba3e72840843ae37245e2f7afa96e5826cda270ac9fc17c31ea59c73bfbd184R189-R193'><strong>Possible Issue</strong></a>\n"
    '\n'
    "The `producer_table_closed` flag is set to true whenever any `</table>` pops the last element of `html_depth`, regardless of whether that table was the producer review table. A standalone `<table></table>` earlier in the body (e.g. in unrelated prose) would set `producer_table_closed = True`, and a subsequent canonical-looking `<details><summary>✅ Resolved findings</summary>` block would then be treated as resolved history even though it did not follow the producer review table. This widens the acceptance surface beyond the stated intent of recognizing only the producer's canonical resolved-history details after its review table.\n"
    '</summary>\n'
    '\n'
    '```python\n'
    'if not html_depth:\n'
    '    if tag_name == "table":\n'
    '        producer_table_closed = True\n'
    '    if tag_name == "details":\n'
    '        resolved_history = False\n'
    '```\n'
    '\n'
    '</details>\n'
    '\n'
    '</td></tr>\n'
    '</table>\n'
    '\n'
    '<details>\n'
    '<summary>✅ Resolved findings</summary>\n'
    '\n'
    '### scripts/development-workflow/pr-agent-runtime.py:133-136\n'
    '\n'
    '**Possible Issue**\n'
    '\n'
    'The inline-HTML acceptance gate requires `"table" in html_depth` whenever any HTML is open (`in_html and "table" not in html_depth and not resolved_history`). Because `html_block` is tracked separately from `html_depth`, a supported block tag opened at line start (which sets `html_block` rather than pushing onto `html_depth`) combined with an empty `html_depth` yields `in_html == True` but `"table" not in html_depth`, so the span is rejected even though the tag is in `inline_tags`. Conversely, a `<details>` opened via the depth stack outside a table is also rejected. This makes acceptance depend on which tracking structure the parser used for a given tag rather than on the documented "producer review table is open" condition. The added tests exercise the real producer comments, but a supported wrapper tracked via `html_block` (e.g. a line-leading `<strong>`/`<summary>`) would still escalate.\n'
    '\n'
    '### scripts/development-workflow/pr-agent-runtime.py:177-191\n'
    '\n'
    '**Possible Issue**\n'
    '\n'
    'The resolved-history detection sets `resolved_history = True` when a `<details>` with the exact canonical summary is opened after a closed producer table, but the flag is only reset when a `</details>` closing tag is popped from `html_depth`. If the history `<details>` is opened while `html_depth` is non-empty (e.g. nested inside another open element) or if the matching `</details>` is never pushed/popped in the same way, `resolved_history` can remain `True` past the intended history block. In that state the cross-container guard (`in_html and not resolved_history and re.search(...)`) is disabled, so a later standalone raw `<span>`/`<details>` containing backticks would be accepted instead of escalating. The test `test_resolved_history_retains_producer_context_only` covers the simple case but not a history block whose closing tag is unbalanced or nested, so this relaxation path is under-verified.\n'
    '\n'
    '### scripts/development-workflow/pr-agent-runtime.py:126-133\n'
    '\n'
    '**Possible Issue**\n'
    '\n'
    'The new inline-HTML gate computes `in_html = bool(html_depth or html_block)` and then rejects when `(in_html and "table" not in html_depth)`. Because `html_block` is a separate variable from `html_depth`, a case where `html_block` is set (e.g. a supported block tag like `details`/`summary`/`strong` opened outside a table) while `html_depth` is empty will satisfy `in_html` and then always raise, even though `html_block` is in `inline_tags`. Conversely, when `html_depth` is non-empty but contains only supported tags and no `table` (e.g. a `<details>` opened via the depth stack rather than the block variable), the `"table" not in html_depth` check rejects it. The intent stated in the comment is "supported only while the producer review table is open", but the condition mixes the two tracking structures inconsistently, so whether a given supported container is accepted depends on which of `html_depth`/`html_block` the parser happened to use for that tag. Verify that the depth-vs-block bookkeeping for `table`/`details`/`summary`/`strong` actually places `table` in `html_depth` for the real producer comments; if any supported wrapper is tracked in `html_block` instead, the span will be rejected despite being listed in `inline_tags`.\n'
    '\n'
    '### scripts/development-workflow/pr-agent-runtime.py:145-148\n'
    '\n'
    '**Possible Issue**\n'
    '\n'
    'The cross-container guard `if in_html and re.search(r"<\\s*/|<!|<\\?", content)` rejects any inline span whose content contains a closing-tag-like sequence or comment opener. This is intended to prevent swallowing container boundaries, but it also rejects legitimate inline code that contains a literal `</` or `<?` sequence, such as documenting `</summary>` or `<?php`. The PR description states the goal is to accept "complete single-backtick inline code" while rejecting "cross-container spans"; a span containing `</summary>` as literal text (not an actual tag boundary) is indistinguishable from a real boundary under this regex. If such content appears in a real producer finding, it will escalate. This may be an acceptable conservative tradeoff, but it is worth confirming the producer never emits inline code containing `</` or `<?` as literal content.\n'
    '\n'
    '### scripts/development-workflow/pr-agent-runtime.py:126-133\n'
    '\n'
    '**Possible Issue**\n'
    '\n'
    'The new inline-HTML gate checks `html_block not in inline_tags | {None}` and `(in_html and "table" not in html_depth)`, but `html_depth` is a list of open tags and `html_block` is a separate variable. The condition `any(tag not in inline_tags for tag in html_depth)` rejects any open tag outside the allowlist, yet the allowlist includes `span`, `a`, `b`, `em`, `strong`, `details`, `summary`, etc. A finding summary like `<details><summary><a href=\'...\'><strong>Possible Issue</strong></a> ...` opens `details`, `summary`, `a`, `strong` — all allowed — so the gate passes. However, the check `(in_html and "table" not in html_depth)` requires `table` to be present in `html_depth` whenever any HTML is open. If the producer table is opened and then closed before the inline span (e.g. a `<details>` block that appears after `</table>` but still within the review body), `html_depth` would no longer contain `table` and the span would be rejected even though it is inside the producer review. This is a narrow trigger, but it means the acceptance is tied to the table being currently open rather than the review being a producer review. Confirm whether the producer format always keeps the table open across all finding spans; if not, valid inline code after the table close would still escalate.\n'
    '\n'
    '</details>\n'
    '\n'
    '<!-- pr-agent-review-state:v1\n'
    '{"findings":[{"body":"**Possible Issue**\\n\\nThe `producer_table_closed` flag is set to true whenever any `</table>` pops the last element of `html_depth`, regardless of whether that table was the producer review table. A standalone `<table></table>` earlier in the body (e.g. in unrelated prose) would set `producer_table_closed = True`, and a subsequent canonical-looking `<details><summary>✅ Resolved findings</summary>` block would then be treated as resolved history even though it did not follow the producer review table. This widens the acceptance surface beyond the stated intent of recognizing only the producer\'s canonical resolved-history details after its review table.","finding_id":"17d0394221fd","first_seen":"2026-10-15T14:37:48.518356Z","last_seen":"2026-10-15T14:37:48.518356Z","last_seen_head_sha":"a73ffb344cc70aad71018c9e6440c0a2005844f6","line_end":193,"line_start":189,"path":"scripts/development-workflow/pr-agent-runtime.py","state":"ACTIVE"},{"body":"**Possible Issue**\\n\\nThe new inline-HTML gate computes `in_html = bool(html_depth or html_block)` and then rejects when `(in_html and \\"table\\" not in html_depth)`. Because `html_block` is a separate variable from `html_depth`, a case where `html_block` is set (e.g. a supported block tag like `details`/`summary`/`strong` opened outside a table) while `html_depth` is empty will satisfy `in_html` and then always raise, even though `html_block` is in `inline_tags`. Conversely, when `html_depth` is non-empty but contains only supported tags and no `table` (e.g. a `<details>` opened via the depth stack rather than the block variable), the `\\"table\\" not in html_depth` check rejects it. The intent stated in the comment is \\"supported only while the producer review table is open\\", but the condition mixes the two tracking structures inconsistently, so whether a given supported container is accepted depends on which of `html_depth`/`html_block` the parser happened to use for that tag. Verify that the depth-vs-block bookkeeping for `table`/`details`/`summary`/`strong` actually places `table` in `html_depth` for the real producer comments; if any supported wrapper is tracked in `html_block` instead, the span will be rejected despite being listed in `inline_tags`.","finding_id":"24521fb8d005","first_seen":"2026-10-15T13:34:17.994063Z","last_seen":"2026-10-15T13:34:17.994063Z","last_seen_head_sha":"bd05503e5ce7243f948dc13f8203fad18b927105","line_end":133,"line_start":126,"path":"scripts/development-workflow/pr-agent-runtime.py","resolution_run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/925b3463a2fa829f93ba35371bc873bac187fdaa","resolved_at":"2026-10-15T13:58:34.511516Z","resolved_head_sha":"925b3463a2fa829f93ba35371bc873bac187fdaa","state":"RESOLVED"},{"body":"**Possible Issue**\\n\\nThe new inline-HTML gate checks `html_block not in inline_tags | {None}` and `(in_html and \\"table\\" not in html_depth)`, but `html_depth` is a list of open tags and `html_block` is a separate variable. The condition `any(tag not in inline_tags for tag in html_depth)` rejects any open tag outside the allowlist, yet the allowlist includes `span`, `a`, `b`, `em`, `strong`, `details`, `summary`, etc. A finding summary like `<details><summary><a href=\'...\'><strong>Possible Issue</strong></a> ...` opens `details`, `summary`, `a`, `strong` — all allowed — so the gate passes. However, the check `(in_html and \\"table\\" not in html_depth)` requires `table` to be present in `html_depth` whenever any HTML is open. If the producer table is opened and then closed before the inline span (e.g. a `<details>` block that appears after `</table>` but still within the review body), `html_depth` would no longer contain `table` and the span would be rejected even though it is inside the producer review. This is a narrow trigger, but it means the acceptance is tied to the table being currently open rather than the review being a producer review. Confirm whether the producer format always keeps the table open across all finding spans; if not, valid inline code after the table close would still escalate.","finding_id":"28886a027301","first_seen":"2026-10-15T13:32:23.844031Z","last_seen":"2026-10-15T13:32:23.844031Z","last_seen_head_sha":"283777e2ff0b6f6124e40edaebd294d0956ede2a","line_end":133,"line_start":126,"path":"scripts/development-workflow/pr-agent-runtime.py","resolution_run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/bd05503e5ce7243f948dc13f8203fad18b927105","resolved_at":"2026-10-15T13:34:17.994063Z","resolved_head_sha":"bd05503e5ce7243f948dc13f8203fad18b927105","state":"RESOLVED"},{"body":"**Possible Issue**\\n\\nThe cross-container guard `if in_html and re.search(r\\"<\\\\s*/|<!|<\\\\?\\", content)` rejects any inline span whose content contains a closing-tag-like sequence or comment opener. This is intended to prevent swallowing container boundaries, but it also rejects legitimate inline code that contains a literal `</` or `<?` sequence, such as documenting `</summary>` or `<?php`. The PR description states the goal is to accept \\"complete single-backtick inline code\\" while rejecting \\"cross-container spans\\"; a span containing `</summary>` as literal text (not an actual tag boundary) is indistinguishable from a real boundary under this regex. If such content appears in a real producer finding, it will escalate. This may be an acceptable conservative tradeoff, but it is worth confirming the producer never emits inline code containing `</` or `<?` as literal content.","finding_id":"3a8ca8a08881","first_seen":"2026-10-15T13:32:23.844031Z","last_seen":"2026-10-15T13:32:23.844031Z","last_seen_head_sha":"283777e2ff0b6f6124e40edaebd294d0956ede2a","line_end":148,"line_start":145,"path":"scripts/development-workflow/pr-agent-runtime.py","resolution_run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/bd05503e5ce7243f948dc13f8203fad18b927105","resolved_at":"2026-10-15T13:34:17.994063Z","resolved_head_sha":"bd05503e5ce7243f948dc13f8203fad18b927105","state":"RESOLVED"},{"body":"**Possible Issue**\\n\\nThe resolved-history detection sets `resolved_history = True` when a `<details>` with the exact canonical summary is opened after a closed producer table, but the flag is only reset when a `</details>` closing tag is popped from `html_depth`. If the history `<details>` is opened while `html_depth` is non-empty (e.g. nested inside another open element) or if the matching `</details>` is never pushed/popped in the same way, `resolved_history` can remain `True` past the intended history block. In that state the cross-container guard (`in_html and not resolved_history and re.search(...)`) is disabled, so a later standalone raw `<span>`/`<details>` containing backticks would be accepted instead of escalating. The test `test_resolved_history_retains_producer_context_only` covers the simple case but not a history block whose closing tag is unbalanced or nested, so this relaxation path is under-verified.","finding_id":"6feeab06a5eb","first_seen":"2026-10-15T13:58:34.511516Z","last_seen":"2026-10-15T13:58:34.511516Z","last_seen_head_sha":"925b3463a2fa829f93ba35371bc873bac187fdaa","line_end":191,"line_start":177,"path":"scripts/development-workflow/pr-agent-runtime.py","resolution_run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/a73ffb344cc70aad71018c9e6440c0a2005844f6","resolved_at":"2026-10-15T14:37:48.518356Z","resolved_head_sha":"a73ffb344cc70aad71018c9e6440c0a2005844f6","state":"RESOLVED"},{"body":"**Possible Issue**\\n\\nThe `resolved_history` flag is set when a `<details>` block matching the canonical resolved-history pattern opens after the producer table closes, and it is only reset when a matching `</details>` is popped from `html_depth`. However, `resolved_history` is not reset when the parser encounters a new top-level raw HTML block or when the details block is closed via a path that does not pop `html_depth` (e.g. mismatched nesting). If a later, unrelated `<details>` block appears after the history block without an intervening `</details>` that pops the stack, `history_markdown` could remain true and permit inline spans containing `</` or `<?` in a context the PR intends to reject. The tests cover a later `<span>` block but not a later `<details>` block; verify the flag cannot leak past the intended history container.","finding_id":"d43c9acb524a","first_seen":"2026-10-15T14:37:48.518356Z","last_seen":"2026-10-15T14:37:48.518356Z","last_seen_head_sha":"a73ffb344cc70aad71018c9e6440c0a2005844f6","line_end":193,"line_start":179,"path":"scripts/development-workflow/pr-agent-runtime.py","state":"ACTIVE"},{"body":"**Possible Issue**\\n\\nThe inline-HTML acceptance gate requires `\\"table\\" in html_depth` whenever any HTML is open (`in_html and \\"table\\" not in html_depth and not resolved_history`). Because `html_block` is tracked separately from `html_depth`, a supported block tag opened at line start (which sets `html_block` rather than pushing onto `html_depth`) combined with an empty `html_depth` yields `in_html == True` but `\\"table\\" not in html_depth`, so the span is rejected even though the tag is in `inline_tags`. Conversely, a `<details>` opened via the depth stack outside a table is also rejected. This makes acceptance depend on which tracking structure the parser used for a given tag rather than on the documented \\"producer review table is open\\" condition. The added tests exercise the real producer comments, but a supported wrapper tracked via `html_block` (e.g. a line-leading `<strong>`/`<summary>`) would still escalate.","finding_id":"f1314959da68","first_seen":"2026-10-15T13:58:34.511516Z","last_seen":"2026-10-15T13:58:34.511516Z","last_seen_head_sha":"925b3463a2fa829f93ba35371bc873bac187fdaa","line_end":136,"line_start":133,"path":"scripts/development-workflow/pr-agent-runtime.py","resolution_run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/a73ffb344cc70aad71018c9e6440c0a2005844f6","resolved_at":"2026-10-15T14:37:48.518356Z","resolved_head_sha":"a73ffb344cc70aad71018c9e6440c0a2005844f6","state":"RESOLVED"}],"last_run":{"complete":true,"excluded_files":[],"head_sha":"a73ffb344cc70aad71018c9e6440c0a2005844f6","kind":"full","run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/a73ffb344cc70aad71018c9e6440c0a2005844f6"},"schema_version":1}\n'
    '-->\n'
    '\n'
)


class InlineProducerHTMLTests(unittest.TestCase):
    def labels(self, body):
        return subprocess.run(
            ["bash", str(ROOT / "scripts/development-workflow/apply-readiness-labels.sh"),
             "--pr-agent-focus-labels"], input=body, text=True, capture_output=True, check=True,
        ).stdout.strip().splitlines()

    def finding(self, content, label="Possible Issue"):
        return review(True).replace("Must fix", label).replace(
            "The original blocker must remain visible.", content)

    def test_complete_real_reviews(self):
        for name, body in HTML_INLINE_REVIEWS.items():
            with self.subTest(pr=name):
                self.assertEqual("clean", classify(body))
                self.assertTrue(self.labels(body))
                self.assertEqual({"Possible Issue"}, set(self.labels(body)))
                parsed = runtime.ReviewSpans(body)
                self.assertEqual(body, parsed.source)

    def test_leasity_minimal_and_supported_containers(self):
        for content in ("Read `git show <head>:CHANGELOG.md`.",
                        "Read `known_helper()` and `--release-head`."):
            for wrapper in ("{}", "<a href='url'>{}</a>",
                            "<b>{}</b>", "<em>{}</em>", "<span>{}</span>"):
                with self.subTest(content=content, wrapper=wrapper):
                    body = self.finding(wrapper.format(content))
                    self.assertEqual("clean", classify(body))
                    self.assertEqual(["Possible Issue"], self.labels(body))
        for tag in ("table", "tbody", "thead", "tfoot", "tr", "td", "th",
                    "details", "summary", "strong"):
            sample = "Use `helper()`."
            if tag != "table":
                sample = "<" + tag + ">" + sample + "</" + tag + ">"
            body = "<table>" + sample + "</table>"
            masked = runtime.mask_review_code(body)
            self.assertEqual(len(body), len(masked), tag)
            self.assertNotIn("helper()", masked, tag)

    def test_inline_html_requires_open_producer_table(self):
        for source in ("<span>`Critical`</span>",
                       "<details><summary>Read `git show <head>:CHANGELOG.md`</summary></details>",
                       "<table></table><span>`Critical`</span>"):
            for preserve in (True, False):
                with self.subTest(source=source, preserve=preserve):
                    with self.assertRaises(ValueError):
                        runtime.mask_review_code(source, preserve_offsets=preserve)
            self.assertEqual("escalate", classify(review() + "\n" + source))

    def test_real_blockers_survive_inline_examples(self):
        for label in ("Must fix", "Critical", "Security concern", "Breaking change"):
            body = self.finding("Read `helper()`.", label)
            self.assertEqual("needs_fixes", classify(body))
            self.assertEqual([label], self.labels(body))
        body = self.finding("Example: `<strong>Must fix</strong>`.")
        self.assertEqual("clean", classify(body))
        self.assertEqual(["Possible Issue"], self.labels(body))

    def test_quoted_code_and_comments_cannot_supply_clean_evidence(self):
        for sample in ("`No major issues detected`", "<!-- No major issues detected -->",
                       '<span title="No major issues detected">example</span>'):
            body = "<details><summary>" + sample + "</summary></details>"
            self.assertEqual("escalate", classify(body))
        body = self.finding("`Possible Issue`").replace("<strong>Possible Issue</strong>", "")
        self.assertNotEqual("clean", classify(body))

    def test_unsupported_and_ambiguous_inputs_still_escalate(self):
        for content in ("`unclosed", "``double``", "`two\nlines`", "`trailing\\`",
                        "\\`escaped`", "`prose </summary>`",
                        "`</summary> live prose <strong>Must fix</strong>`", "<div>`helper()`</div>",
                        '<a title="`helper()`">text</a>',
                        "<a title=bad`attribute`>text</a>"):
            with self.subTest(content=content):
                self.assertEqual("escalate", classify(self.finding(content)))
        body = self.finding("`helper()`").replace("</summary>", "</details>", 1)
        self.assertEqual("escalate", classify(body))

    def test_resolved_history_retains_producer_context_only(self):
        history = ("<details>\n<summary>✅ Resolved findings</summary>\n\n"
                   "Example `</summary>` and `<?php` and `<!-- literal -->`.\n\n</details>")
        body = review() + "\n" + history
        self.assertEqual("clean", classify(body))
        self.assertEqual(len(body), len(runtime.mask_review_code(body)))
        for unsupported in (history, history.replace("✅ Resolved findings", "Other history"),
                            history.replace("</summary>\n\n", "</summary>\n", 1)):
            source = unsupported if unsupported == history else review() + "\n" + unsupported
            self.assertEqual("escalate", classify(source))
        for bad in ("`unclosed", "``double``", "`two\nlines`", '<span title="`bad`">text</span>'):
            self.assertEqual("escalate", classify(review() + "\n" + history.replace(
                "Example `</summary>` and `<?php` and `<!-- literal -->`.", bad)))
        # History recognition never extends to a later, unrelated raw block.
        self.assertEqual("escalate", classify(body + "\n<span>`Critical`</span>"))
        for label in ("Must fix", "Critical"):
            live = self.finding("Read `helper()`.", label) + "\n" + history
            self.assertEqual("needs_fixes", classify(live))
            self.assertEqual([label], self.labels(live))

    def test_resolved_history_does_not_mask_nested_raw_html_boundaries(self):
        prefix = "<details>\n<summary>✅ Resolved findings</summary>\n\n"
        # Pass-2 counterexample: the first closing summary is real HTML; the
        # backticks must not hide it and make the surplus closer look valid.
        invalid = (prefix + "<details><summary>Example `</summary>`</summary></details>"
                   "\n\n</details>")
        for sample in (invalid,
                       prefix + "<span>Example `</span>`</span>\n\n</details>",
                       prefix + "<strong>Example `<!-- sample -->`</strong>\n\n</details>"):
            body = review() + "\n" + sample
            self.assertEqual("escalate", classify(body))
            for preserve in (True, False):
                with self.subTest(sample=sample, preserve=preserve):
                    with self.assertRaises(ValueError):
                        runtime.mask_review_code(body, preserve_offsets=preserve)
        # After nested HTML closes and a blank line ends its block, ordinary
        # root Markdown inline code is supported again, with offsets intact.
        history = prefix + "<details><summary>Notes</summary></details>\n\nRead `</summary>`.\n\n</details>"
        body = review() + "\n" + history
        self.assertEqual("clean", classify(body))
        self.assertEqual(len(body), len(runtime.mask_review_code(body)))

    def test_isolated_html_tag_inline_is_literal_but_real_closers_fail(self):
        for tag in ("<details>", "</details>", "<summary>", "</summary>", "<span>", "</span>"):
            with self.subTest(tag=tag):
                body = self.finding("Example `" + tag + "`.")
                self.assertEqual("clean", classify(body))
                self.assertEqual(["Possible Issue"], self.labels(body))
                for preserve in (True, False):
                    runtime.mask_review_code(body, preserve_offsets=preserve)
                self.assertEqual("escalate", classify(self.finding("Example " + tag + ".")))
    def test_html_only_inline_fragments_and_sequences_are_literal(self):
        for content in ("</", "<?", "<table></table>",
                        "<details><summary>✅ Resolved findings</summary>",
                        "</summary><strong>Must fix</strong>", "<!-- hidden -->"):
            with self.subTest(content=content):
                body = self.finding("Example `" + content + "`.")
                self.assertEqual("clean", classify(body))
                self.assertEqual(["Possible Issue"], self.labels(body))
                for preserve in (True, False):
                    runtime.mask_review_code(body, preserve_offsets=preserve)
                # Real closing tags, incomplete markup and nested review tables
                # outside code remain unsafe even beside an advisory finding.
                if content != "<!-- hidden -->":
                    self.assertEqual("escalate", classify(self.finding(content)))
                else:
                    # A complete real comment is valid and opaque; it must
                    # never suppress a blocker outside the quoted example.
                    self.assertEqual("needs_fixes", classify(self.finding(content, "Critical")))
                blocker = self.finding("Example `" + content + "`.", "Critical")
                self.assertEqual("needs_fixes", classify(blocker))
                self.assertEqual(["Critical"], self.labels(blocker))

    def test_comment_delimiters_in_complete_inline_expressions(self):
        for content in ('source.startswith("<!--", index)',
                        're.match(r"<!--\\s*pr-agent-review-state", source[index:])',
                        'marker = "<!-- literal -->"',
                        'text.replace("<!--", "-->")'):
            for label, expected in (("Possible Issue", "clean"), ("Must fix", "needs_fixes")):
                with self.subTest(content=content, label=label):
                    body = self.finding("Read `" + content + "` then act.", label)
                    self.assertEqual(expected, classify(body))
                    self.assertEqual([label], self.labels(body))
                    masked = runtime.mask_review_code(body)
                    self.assertEqual(len(body), len(masked))
                    self.assertEqual(body.count("\n"), masked.count("\n"))
                    self.assertIn(" then act.", masked)
                    self.assertNotIn(content, masked)

    def test_comment_expressions_do_not_relax_other_inline_boundaries(self):
        for content in ('`source.startswith("<!--", index)',
                        '`source.startswith("<!--",\n index)`',
                        '`<!-- example </summary>`',
                        '`<!-- </summary><strong>Must fix</strong>`',
                        '`prose <!DOCTYPE html>`', '`prose <?php`'):
            with self.subTest(content=content):
                body = self.finding(content)
                self.assertEqual("escalate", classify(body))
                for preserve in (True, False):
                    with self.assertRaises(ValueError):
                        runtime.mask_review_code(body, preserve_offsets=preserve)
        body = review() + '\n<span>`source.startswith("<!--", index)`</span>'
        self.assertEqual("escalate", classify(body))

    def test_real_1986_comment_with_inline_comment_expression(self):
        original = PR_1986_INLINE_REVIEW
        self.assertEqual("clean", classify(original))
        self.assertEqual(["Possible Issue", "Possible Issue"], self.labels(original))
        parsed = runtime.ReviewSpans(original)
        self.assertEqual(original, parsed.source)
        self.assertEqual(len(original), len(runtime.mask_review_code(original)))
        blocker = original.replace("<strong>Possible Issue</strong>",
                                   "<strong>Must fix</strong>", 1)
        self.assertEqual("needs_fixes", classify(blocker))

    def test_current_complete_review_with_html_code(self):
        self.assertEqual("clean", classify(CURRENT_REVIEW_1978))
        self.assertEqual({"Possible Issue"}, set(self.labels(CURRENT_REVIEW_1978)))
        parsed = runtime.ReviewSpans(CURRENT_REVIEW_1978)
        self.assertEqual(CURRENT_REVIEW_1978, parsed.source)

    def test_mask_offsets_and_original_prose(self):
        body = self.finding("Read `helper()` then act.")
        masked = runtime.mask_review_code(body)
        self.assertEqual(len(body), len(masked))
        self.assertEqual(body.count("\n"), masked.count("\n"))
        self.assertIn(" then act.", masked)
        self.assertIn("<strong>Possible Issue</strong>", masked)
        self.assertNotIn("helper()", masked)


class FittingTests(unittest.TestCase):
    def fit(self, body, limit=65000):
        result = runtime.fit_review(body, limit, STATE, HEADERS)
        self.assertLessEqual(len(result), limit)
        return result

    def test_unchanged_comments(self):
        for body in ("", " \t\n", review(), review(True), "unknown review -- invalid marker"):
            for limit in (max(1, len(body)), len(body) + 10):
                with self.subTest(body=body[:20], limit=limit):
                    self.assertEqual(body, self.fit(body, limit))

    def test_visible_verdict_survives(self):
        for blocking in (False, True):
            visible = review(blocking)
            original = compose(visible, state())
            self.assertGreater(len(original), 65000)
            result = self.fit(original)
            self.assertIn(visible.rstrip(), result)
            self.assertEqual(classify(visible), classify(result))
            self.assertEqual("needs_fixes" if blocking else "clean", classify(result))
            self.assertIsNone(STATE.parse_review_state(result).state)

    def test_notice_capacity(self):
        visible = review().rstrip()
        original = compose(visible, state())
        self.assertEqual(visible, self.fit(original, len(visible)))
        self.assertTrue(self.fit(original, len(visible) + 21).endswith("> History omitted."))
        self.assertIn("preserve the current summary and verdict", self.fit(original, len(visible) + 120))

    def test_history_suffix_only(self):
        visible = review(True, '<details><summary>nested current evidence</summary>keep</details>')
        snapshot = state(10000, resolved=True)
        original = compose(visible, snapshot)
        result = self.fit(original, len(visible) + len(STATE.serialize_review_state(snapshot)) + 200)
        self.assertIn(visible.rstrip(), result)
        self.assertNotIn("✅ Resolved findings", result)
        self.assertEqual(snapshot, STATE.parse_review_state(result).state)
        self.assertEqual("needs_fixes", classify(result))

    def test_state_round_trip(self):
        visible = review()
        snapshot = state(200, resolved=True)
        original = compose(visible, snapshot)
        marker = STATE.serialize_review_state(snapshot)
        result = self.fit(original, len(visible.rstrip()) + len(marker) + 4)
        self.assertEqual(snapshot, STATE.parse_review_state(result).state)
        self.assertIn("--\\u003e", result)
        omitted = self.fit(original, len(visible.rstrip()))
        self.assertIsNone(STATE.parse_review_state(omitted).state)
        self.assertFalse(STATE.parse_review_state(omitted).present)

    def test_unsafe_history(self):
        marker = STATE.serialize_review_state(state(20))
        for unsafe in (marker + marker, marker.replace(":v1", ":v2"), marker[:-4],
                       "<!-- pr-agent-review-state:v1\nnot-json\n-->",
                       "<!-- pr-agent-review-state:v1 invalid -->"):
            original = review() + unsafe + "x" * 70000
            result = self.fit(original, 1000)
            self.assertEqual("escalate", classify(result))
            self.assertNotIn("No major issues", result)
            self.assertEqual(original, self.fit(original, len(original)))

    def test_non_history_content(self):
        visible = review(True, '<!-- other-comment -->\ncurrent source')
        result = self.fit(compose(visible, state()))
        self.assertIn('<!-- other-comment -->', result)
        self.assertIn('current source', result)
        self.assertIn('<summary>', result)

    def test_visible_oversize_preserves_summary(self):
        guide = '<details><summary><strong>💡 Tool usage guide:</strong></summary><hr>' + 'help ' * 14000 + '</details>'
        for blocking in (False, True):
            visible = review(blocking, '```python\n' + 'source ' * 10000 + '\n```' if blocking else '', guide)
            result = self.fit(compose(visible, state()))
            self.assertEqual(classify(visible), classify(result))
            self.assertIn('Here are some key observations', result)
            self.assertIn('No security concerns identified', result)
            if blocking:
                self.assertIn('The original blocker must remain visible.', result)
                self.assertNotIn('source source', result)
            self.assertNotIn('help help', result)
            self.assertEqual("needs_fixes" if blocking else "clean", classify(result))

    def test_metadata_reduction(self):
        metadata = '<tr><td>📂&nbsp;<strong>Priority files</strong><br><br><ul><li>' + 'file.py ' * 12000 + '</li></ul></td></tr>'
        visible = review().replace('</table>', metadata + '</table>')
        result = self.fit(visible)
        self.assertNotIn('Priority files', result)
        self.assertEqual(classify(visible), classify(result))
        status = metadata.replace('<li>', '<li><strong>Verification</strong>: required ')
        unsafe = review().replace('</table>', status + '</table>')
        result = self.fit(unsafe)
        self.assertEqual('escalate', classify(result))

    def test_summary_span_boundaries(self):
        excerpt = '```html\n<summary>fake</summary>\n<details>fake</details>\n' + 'code ' * 16000 + '\n```\n'
        visible = review(True, excerpt)
        result = self.fit(visible)
        self.assertIn('The original blocker must remain visible.\n</summary>', result)
        self.assertNotIn('fake', result)
        self.assertEqual(classify(visible), classify(result))
        runtime.ReviewSpans(result)
        unsafe = visible.replace('```html\n', '').replace('\n```', '')
        self.assertEqual('escalate', classify(self.fit(unsafe)))

    def test_late_blocker_and_protected_excerpt_status(self):
        visible = review(True, '```python\n' + 'code ' * 16000 + '\n```')
        visible = visible.replace('Must fix', 'Possible Issue').replace(
            '</td></tr>\n</table>',
            '<details><summary><strong title="x > y">Must fix</strong>Late original blocker</summary>'
            '\n```python\nx\n```\n</details></td></tr>\n</table>',
        )
        result = self.fit(visible)
        self.assertIn('Late original blocker', result)
        self.assertIn('<strong title="x > y">Must fix</strong>', result)
        self.assertEqual('needs_fixes', classify(result))
        self.assertEqual(classify(visible), classify(result))
        protected = review(True, '<strong>Must fix</strong>\n' + 'payload ' * 10000).replace(
            '<strong>Must fix</strong></a>', '<strong>Possible Issue</strong></a>')
        self.assertEqual('needs_fixes', classify(protected))
        self.assertEqual('escalate', classify(self.fit(protected)))

    def test_markdown_blocker_counterexample(self):
        # The exact reported input formerly changed needs_fixes to clean.
        visible = review(True, '**Must fix**\n' + 'source ' * 12000).replace(
            '<strong>Must fix</strong></a>', '<strong>Possible Issue</strong></a>')
        self.assertEqual('needs_fixes', classify(visible))
        self.assertEqual('escalate', classify(self.fit(visible)))
        self.assertEqual(visible, self.fit(visible, len(visible)))

    def test_all_unfenced_blocker_labels_survive(self):
        labels = ('Must fix', 'Critical', 'Breaking Change', 'Security Concern',
                  'API Change', 'Backward Compatibility')
        code = '```python\n' + 'source ' * 12000 + '\n```\n'
        for label in labels:
            for evidence in ('**' + label + '**', '<strong>' + label + '</strong>'):
                with self.subTest(evidence=evidence):
                    for excerpt in (evidence + '\n' + code, code + evidence + '\n'):
                        visible = review(True, excerpt).replace(
                            '<strong>Must fix</strong></a>', '<strong>Possible Issue</strong></a>')
                        result = self.fit(visible)
                        self.assertIn(evidence, result)
                        self.assertNotIn('source source', result)
                        self.assertEqual('needs_fixes', classify(visible))
                        self.assertEqual('needs_fixes', classify(result))

    def test_unknown_unfenced_status_is_protected(self):
        code = '~~~~python\n' + 'source ' * 12000 + '\n~~~~\n'
        for evidence in ('**Unknown finding status**', 'Verification: pending'):
            visible = review(True, code + evidence + '\n').replace(
                '<strong>Must fix</strong></a>', '<strong>Possible Issue</strong></a>')
            result = self.fit(visible)
            self.assertIn(evidence, result)
            self.assertEqual('escalate', classify(visible))
            self.assertEqual('escalate', classify(result))

    def test_fence_boundaries_do_not_hide_status(self):
        for fence in ('```', '~~~~', '``````'):
            excerpt = fence + 'python\n' + 'source ' * 12000 + '\n' + fence + ' not-a-close\n'
            visible = review(True, excerpt)
            self.assertEqual('escalate', classify(visible))
            self.assertEqual('escalate', classify(self.fit(visible)))
        excerpt = '````python\n``` nested marker\n' + 'source ' * 12000 + '\n`````\n**Must fix**\n'
        visible = review(True, excerpt).replace(
            '<strong>Must fix</strong></a>', '<strong>Possible Issue</strong></a>')
        result = self.fit(visible)
        self.assertIn('**Must fix**', result)
        self.assertEqual('needs_fixes', classify(visible))
        self.assertEqual('needs_fixes', classify(result))

    def test_auxiliary_status_evidence_is_not_removed(self):
        for evidence in ('Verification: pending\n', '**Verification**: pending\n'):
            guide = '<details><summary><strong>💡 Tool usage guide:</strong></summary><hr>\n'
            guide += evidence + 'help ' * 14000 + '</details>'
            visible = review(False, suffix=guide)
            self.assertNotEqual('clean', classify(visible))
            self.assertEqual('escalate', classify(self.fit(visible)))

    def test_comment_split_human_verification_is_not_ancillary(self):
        for comment in ('<!-- note -->', '<!-- note > detail -->',
                        '<!-- multi\nline note -->', '<!-- first --><!-- second -->'):
            payload = '\nRequires further human verifi' + comment + 'cation\n'
            payload += 'file.py ' * 10000
            metadata = '<tr><td><strong>Priority files</strong><br><br>' + payload + '</td></tr>'
            guide = '<details><summary><strong>💡 Tool usage guide:</strong></summary><hr>'
            for surface, original in (
                ('metadata', review().replace('</table>', metadata + '</table>')),
                ('tool-guide', review(suffix=guide + payload + '</details>')),
            ):
                with self.subTest(comment=comment, surface=surface):
                    self.assertGreater(len(original), 65000)
                    self.assertEqual('escalate', classify(original))
                    self.assertEqual('escalate', classify(self.fit(original)))
                    for limit in (len(original), len(original) + 1):
                        self.assertEqual(original, self.fit(original, limit))

    def test_hidden_comment_status_does_not_protect_ancillary_content(self):
        payload = '\n<!-- Requires further human verification -->\n' + 'file.py ' * 10000
        metadata = '<tr><td><strong>Priority files</strong><br><br>' + payload + '</td></tr>'
        guide = '<details><summary><strong>💡 Tool usage guide:</strong></summary><hr>'
        for original in (review().replace('</table>', metadata + '</table>'),
                         review(suffix=guide + payload + '</details>')):
            with self.subTest(metadata='Priority files' in original):
                self.assertEqual('clean', classify(original))
                published = self.fit(original)
                self.assertEqual('clean', classify(published))
                self.assertIn('No security concerns identified', published)
                self.assertIn('No major issues detected', published)
                self.assertNotIn('file.py', published)

    def test_comment_contained_fences_cannot_remove_live_blocker(self):
        for fence in ('```', '~~~~'):
            for excerpt in (
                '<!--\n' + fence + '\n-->\n**Must fix**\n' + 'source ' * 12000
                + '\n<!--\n' + fence + '\n-->\n',
                '<!--\n' + fence + '\n-->\n<strong>Must fix</strong>\n'
                + 'source ' * 12000 + '\n<!--\n' + fence + '\n-->\n',
            ):
                with self.subTest(fence=fence, excerpt=excerpt[:60]):
                    visible = review(True, excerpt).replace(
                        '<strong>Must fix</strong></a>', '<strong>Possible Issue</strong></a>')
                    self.assertEqual('needs_fixes', classify(visible))
                    self.assertEqual('escalate', classify(self.fit(visible)))
                    self.assertEqual(visible, self.fit(visible, len(visible)))

    def test_empty_classifier_headings_are_not_ancillary(self):
        for heading in ('Recommended focus areas for review', 'Key issues to review',
                        'Security concerns', 'Verification', 'Ticket compliance analysis'):
            styles = ('### ' + heading,) if heading == 'Ticket compliance analysis' else (
                heading, '### ' + heading, '<span>' + heading + '</span>')
            for styled in styles:
                payload = '\n' + styled + '\n' + 'help ' * 19000
                metadata = '<tr><td><strong>Priority files</strong><br><br>' + payload + '</td></tr>'
                guide = '<details><summary><strong>💡 Tool usage guide:</strong></summary><hr>'
                for visible in (review().replace('</table>', metadata + '</table>'),
                                review(suffix=guide + payload + '</details>')):
                    with self.subTest(heading=styled, metadata='Priority files' in visible):
                        self.assertEqual('escalate', classify(visible))
                        self.assertEqual('escalate', classify(self.fit(visible)))
                        self.assertEqual(visible, self.fit(visible, len(visible)))

    def test_visible_oversize_diagnostic(self):
        protected = review(True).replace('The original blocker', 'x' * 70000 + 'The original blocker')
        for original in (protected, review().replace('</table>', '') + 'x' * 70000,
                         '## PR Reviewer Guide\nUnknown layout\n' + 'x' * 70000):
            for limit in (1, 21, 1000, 65000):
                self.assertEqual('escalate', classify(self.fit(original, limit)))

    def test_invalid_limit(self):
        for limit in (0, -1, True, 1.5, '65000', None):
            with self.assertRaises(ValueError):
                runtime.fit_review(review(), limit, STATE, HEADERS)

    def test_count_only_logs(self):
        with self.assertLogs(runtime.LOGGER, level='WARNING') as logs:
            self.fit(compose(review(True), state()))
        self.assertIn('original_chars=', ''.join(logs.output))
        self.assertNotIn('original blocker', ''.join(logs.output))

    def test_runtime_compatibility(self):
        def unsupported(output):
            return output
        with self.assertRaisesRegex(RuntimeError, 'incompatible'):
            runtime.require_signature(unsupported, ['self', 'output', 'max_chars'])
        def supported(self, output, max_chars):
            return output
        runtime.require_signature(supported, ['self', 'output', 'max_chars'])
        with patch.object(runtime, 'install_hooks', side_effect=RuntimeError('planted unsupported hook')):
            with patch.object(runtime.runpy, 'run_path') as runner:
                with patch.object(sys, 'argv', ['runtime']):
                    with self.assertRaises(RuntimeError):
                        runtime.main()
                runner.assert_not_called()
        with patch.object(runtime, 'install_hooks') as hooks:
            with patch.object(runtime.runpy, 'run_path') as runner:
                with patch.object(sys, 'argv', ['runtime', '--image']):
                    with patch('builtins.print') as output:
                        runtime.main()
                output.assert_called_once_with(runtime.IMAGE)
                hooks.assert_not_called()
                runner.assert_not_called()


class ConsumerDeliveryTests(unittest.TestCase):
    def assert_trusted_workflow(self, source):
        checkouts = re.findall(r'      - name: .*\n(?:        .*\n)*?        uses: actions/checkout@[^\n]+\n'
                               r'        with:\n((?:          .*\n)+)', source)
        self.assertEqual(1, len(checkouts))
        self.assertIn('ref: ${{ steps.trusted-base.outputs.sha }}', checkouts[0])
        self.assertIn('persist-credentials: false', checkouts[0])
        self.assertIn('id: trusted-base', source)
        self.assertRegex(source, r'uses: actions/github-script@[0-9a-f]{40}  # v7')
        self.assertLess(source.index('id: trusted-base'), source.index('uses: actions/checkout@'))
        self.assertLess(source.index('uses: actions/checkout@'), source.index('      - name: PR-Agent\n'))

    def test_workflow_trusted_revision_contract(self):
        source = (ROOT / '.github/workflows/pr-agent.yml').read_text()
        self.assert_trusted_workflow(source)
        for revision in ('github.event.pull_request.head.sha', 'github.sha',
                         "github.event_name == 'pull_request' && github.event.pull_request.head.sha || github.sha"):
            with self.subTest(revision=revision):
                changed = source.replace('steps.trusted-base.outputs.sha', revision)
                with self.assertRaises(AssertionError):
                    self.assert_trusted_workflow(changed)

    @unittest.skipIf(IMAGE_SMOKE, 'workflow resolver runs on the GitHub host')
    def test_workflow_resolves_actual_pr_base_for_every_trigger(self):
        source = (ROOT / '.github/workflows/pr-agent.yml').read_text()
        match = re.search(r'          script: \|\n((?:            [^\n]*\n)+)', source)
        self.assertIsNotNone(match)
        script = '\n'.join(line[12:] for line in match[1].splitlines())
        harness = r'''
const fs = require('fs');
const input = JSON.parse(fs.readFileSync(0, 'utf8'));
const calls = [], outputs = {};
const github = {rest: {pulls: {get: async args => {
  calls.push(args);
  if (input.apiError) throw new Error('API unavailable');
  return {data: input.pullRequest};
}}}};
const core = {setOutput: (key, value) => {outputs[key] = value;}};
const AsyncFunction = Object.getPrototypeOf(async function() {}).constructor;
(async () => {
  let error = null;
  try { await new AsyncFunction('github', 'context', 'core', input.script)(github, input.context, core); }
  catch (failure) { error = failure.message; }
  process.stdout.write(JSON.stringify({calls, outputs, error}));
})();
'''
        base_sha = 'a' * 40
        pull_request = {'base': {'sha': base_sha, 'ref': 'develop-product'},
                        'head': {'sha': 'b' * 40, 'repo': {'full_name': 'example/product'}}}
        context = {'repo': {'owner': 'example', 'repo': 'product'}, 'issue': {'number': 42},
                   'sha': 'c' * 40, 'payload': {'repository': {'default_branch': 'main'}}}

        def resolve(event_name, action, response=None, api_error=False):
            event_context = {**context, 'eventName': event_name,
                             'payload': {**context['payload'], 'action': action}}
            if event_name == 'pull_request':
                event_context['payload']['pull_request'] = {
                    'base': {'sha': 'd' * 40}, 'head': {'sha': 'b' * 40}}
            else:
                event_context['payload'].update(issue={'number': 42, 'pull_request': {}},
                                                comment={'body': '/review'})
            result = subprocess.run(['node', '-e', harness], input=json.dumps({
                'script': script, 'context': event_context, 'pullRequest': response or pull_request,
                'apiError': api_error}), text=True, capture_output=True, check=True)
            return json.loads(result.stdout)

        for event, action in [('pull_request', action) for action in
                              ('opened', 'reopened', 'ready_for_review', 'synchronize')] + [('issue_comment', 'created')]:
            with self.subTest(event=event, action=action):
                result = resolve(event, action)
                self.assertEqual([{'owner': 'example', 'repo': 'product', 'pull_number': 42}], result['calls'])
                self.assertEqual({'sha': base_sha}, result['outputs'])
                self.assertIsNone(result['error'])
        for sha in ('', ' ', 'a' * 39, 'a' * 41, 'g' * 40):
            with self.subTest(invalid_base=sha):
                result = resolve('issue_comment', 'created', {**pull_request, 'base': {'sha': sha}})
                self.assertEqual({}, result['outputs'])
                self.assertIsNotNone(result['error'])
        for response, api_error in [({**pull_request, 'head': {'repo': {'full_name': 'other/product'}}}, False),
                                    (pull_request, True)]:
            result = resolve('issue_comment', 'created', response, api_error)
            self.assertEqual({}, result['outputs'])
            self.assertIsNotNone(result['error'])

    def test_product_sync_dependency(self):
        manifest = ROOT / 'sync-manifest.yaml'
        selector = ROOT / 'scripts/development-workflow/select-sync-manifest-entries.py'
        def selected(path):
            output = subprocess.run([sys.executable, str(selector), '--manifest', str(path),
                                     '--role', 'product_repo'], capture_output=True, text=True, check=True).stdout
            return {line.split(' path=', 1)[1].split(' glob=', 1)[0]
                    for line in output.splitlines() if line.startswith('SELECTED ')}
        workflow = '.github/workflows/pr-agent.yml'
        helper = 'scripts/development-workflow/pr-agent-runtime.py'
        self.assertTrue({workflow, helper} <= selected(manifest))
        with tempfile.TemporaryDirectory(prefix='pr agent context ') as directory:
            planted = Path(directory) / 'manifest.yaml'
            text = manifest.read_text()
            text = re.sub(r'    - path: scripts/development-workflow/pr-agent-runtime.py\n'
                          r'      mode_scope: shared\n      note: [^\n]+\n', '', text)
            planted.write_text(text)
            self.assertIn(workflow, selected(planted))
            with self.assertRaises(AssertionError):
                self.assertTrue({workflow, helper} <= selected(planted), 'shared runtime missing')
        self.assertTrue({workflow, helper} <= selected(manifest))

    def test_suite_selection(self):
        selector = ROOT / 'scripts/development-workflow/select-test-suites.sh'
        for path in ('scripts/development-workflow/pr-agent-runtime.py',
                     'scripts/development-workflow/tests/test_pr_agent_runtime.py',
                     '.github/workflows/pr-agent.yml'):
            result = subprocess.run(['bash', str(selector), '--changed-files', '-'], input=path + '\n',
                                    text=True, capture_output=True, check=True)
            self.assertIn('scripts/development-workflow/tests/test-pr-agent-runtime.sh', result.stdout.splitlines())

    def test_workflow_context_and_secret_forwarding(self):
        source = (ROOT / '.github/workflows/pr-agent.yml').read_text()
        self.assertIn('types: [opened, reopened, ready_for_review, synchronize]', source)
        self.assertIn("github.event.comment.body == '/review'", source)
        self.assertIn('github.event.pull_request.head.repo.full_name == github.repository', source)
        self.assert_trusted_workflow(source)
        self.assertIn('persist-credentials: false', source)
        self.assertNotIn('pull_request_target:', source)
        for permission in ('issues: write', 'pull-requests: write', 'contents: read'):
            self.assertIn(permission, source)
        commands = source.split('        run: |\n', 1)[1]
        commands = '\n'.join(line[10:] for line in commands.splitlines())
        with tempfile.TemporaryDirectory() as directory:
            temp = Path(directory)
            bin_path = temp / 'bin'
            bin_path.mkdir()
            capture = temp / 'docker.json'
            python = bin_path / 'python3'
            python.write_text('#!' + sys.executable + '\nimport sys\nprint(' + repr(runtime.IMAGE) + ')\n')
            docker = bin_path / 'docker'
            docker.write_text('#!' + sys.executable + '\nimport json,os,sys\n'
                              'from pathlib import Path\nPath(os.environ["CAPTURE"]).write_text(json.dumps(sys.argv[1:]))\n')
            python.chmod(0o755)
            docker.chmod(0o755)
            environment = {'PATH': str(bin_path) + ':' + os.environ['PATH'], 'CAPTURE': str(capture),
                           'GITHUB_WORKSPACE': str(temp), 'GITHUB_EVENT_PATH': str(temp / 'event.json'),
                           'GITHUB_OUTPUT': str(temp / 'output'),
                           'GITHUB_TOKEN': 'synthetic-secret-not-a-real-token',
                           'DEEPSEEK_API_KEY': 'synthetic-key-not-a-real-key'}
            subprocess.run(['bash', '-c', commands], env=environment, check=True, capture_output=True)
            argv = json.loads(capture.read_text())
            for key in ('GITHUB_TOKEN', 'DEEPSEEK_API_KEY', 'config.model', 'config.fallback_models',
                        'config.model_weak', 'github_action_config.pr_actions', 'github_action_config.auto_review',
                        'github_action_config.auto_describe', 'github_action_config.auto_improve'):
                self.assertIn(key, argv)
            self.assertNotIn(environment['GITHUB_TOKEN'], argv)
            self.assertNotIn(environment['DEEPSEEK_API_KEY'], argv)
            self.assertIn('GITHUB_WORKSPACE=/github/workspace', argv)
            self.assertIn('GITHUB_EVENT_PATH=/github/event.json', argv)
            self.assertIn('GITHUB_OUTPUT=/github/output', argv)
            self.assertEqual(runtime.IMAGE, argv[-2])
            self.assertEqual('/github/workspace/scripts/development-workflow/pr-agent-runtime.py', argv[-1])
            environment.pop('GITHUB_EVENT_PATH')
            missing = subprocess.run(['bash', '-c', commands], env=environment, capture_output=True, text=True)
            self.assertNotEqual(0, missing.returncode)
            self.assertIn('GITHUB_EVENT_PATH', missing.stderr)


@unittest.skipUnless(IMAGE_SMOKE, 'actual producer publication requires --image-smoke')
class ImagePublicationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from pr_agent.git_providers.github_provider import GithubProvider
        import pr_agent.tools.pr_reviewer as reviewer
        cls.provider_class = GithubProvider
        cls.original_composer = STATE.append_review_state
        cls.original_limiter = GithubProvider.limit_output_characters
        cls.original_alias = reviewer.append_review_state
        cls.original_publisher = GithubProvider.publish_comment
        cls.original_editor = GithubProvider.edit_comment
        cls.original_persistent = GithubProvider.publish_persistent_comment_full
        runtime.install_hooks()

    @classmethod
    def tearDownClass(cls):
        import pr_agent.tools.pr_reviewer as reviewer
        STATE.append_review_state = cls.original_composer
        reviewer.append_review_state = cls.original_alias
        cls.provider_class.limit_output_characters = cls.original_limiter
        cls.provider_class.publish_comment = cls.original_publisher
        cls.provider_class.edit_comment = cls.original_editor
        cls.provider_class.publish_persistent_comment_full = cls.original_persistent
        del cls.provider_class._workflow_immutable_review_hook

    def provider(self, limit=65000):
        provider = self.provider_class.__new__(self.provider_class)
        provider.pr = Mock()
        provider.issue_main = None
        provider.max_comment_chars = limit
        provider.pr.comments_list = []
        provider.repo = 'synthetic/repo'
        provider.last_commit_id = SimpleNamespace(
            sha='a' * 40, html_url='https://example.invalid/synthetic/repo/commit/' + 'a' * 40)
        provider.pr.head.sha = 'a' * 40
        records = {}

        def create(body):
            number = len(records) + 1
            records[number] = body
            return SimpleNamespace(id=number, body=body)

        provider.pr.create_issue_comment.side_effect = create
        provider.pr.get_issue_comment.side_effect = lambda number: SimpleNamespace(id=number, body=records[number])
        return provider

    def test_publication_consumers(self):
        from pr_agent.git_providers.git_provider import GitProvider
        import pr_agent.tools.pr_reviewer as reviewer
        for blocking in (False, True):
            visible = review(blocking)
            generated = reviewer.append_review_state(visible, state(), max_chars=65000)
            self.assertGreater(len(generated), 65000)
            provider = self.provider()
            provider.publish_comment(generated)
            outbound = provider.pr.create_issue_comment.call_args.args[0]
            self.assertLessEqual(len(outbound), 65000)
            self.assertIn(visible.split('\n', 1)[1].rstrip(), outbound)
            self.assertEqual(classify(visible), classify(outbound))
            comment = Mock()
            body = generated.replace('<!-- pr-agent:review:full -->',
                                     '<!-- pr-agent:review:full -->\n\n#### (Review updated until commit https://example.invalid/commit/' + 'a' * 40 + ')')
            provider.edit_comment(comment, body)
            comment.edit.assert_not_called()
            outbound = provider.pr.create_issue_comment.call_args.args[0]
            self.assertLessEqual(len(outbound), 65000)
            self.assertIn('a' * 40, outbound)
            self.assertEqual(classify(visible), classify(outbound))
            self.assertIsNone(STATE.parse_review_state(outbound).state)
            provider.get_latest_commit_url = Mock(return_value='https://example.invalid/synthetic/repo/commit/' + 'a' * 40)
            provider.get_comment_url = Mock(return_value='https://example.invalid/comment/1')
            comment.reset_mock()
            with patch.object(GitProvider, '_iter_persistent_comments', return_value=iter([(comment, visible)])):
                provider.publish_persistent_comment_full(
                    generated, initial_header='## PR Reviewer Guide 🔍', final_update_message=False,
                    fallback_on_error=False,
                )
            comment.edit.assert_not_called()
            outbound = provider.pr.create_issue_comment.call_args.args[0]
            self.assertIn('Review updated until commit https://example.invalid/synthetic/repo/commit/' + 'a' * 40, outbound)
            self.assertLessEqual(len(outbound), 65000)
            self.assertEqual(classify(visible), classify(outbound))

    def test_new_d15_record_with_prior_summary_and_review_trigger(self):
        from pr_agent.git_providers.git_provider import GitProvider
        provider = self.provider()
        old = Mock(body=review(False))
        before = old.body
        generated = STATE.append_review_state(review(False), state())
        # A persistent summary already exists and /review may have been used.
        # The producer must not inspect/edit it or rely on D15 rule (b).
        with patch.object(GitProvider, '_iter_persistent_comments', return_value=iter([(old, before)])) as iterator:
            response = provider.publish_persistent_comment_full(generated, initial_header=HEADERS[0])
        iterator.assert_not_called()
        old.edit.assert_not_called()
        self.assertEqual(before, old.body)
        provider.pr.create_issue_comment.assert_called_once()
        provider.pr.get_issue_comment.assert_called_once_with(response.id)
        published = provider.pr.create_issue_comment.call_args.args[0]
        self.assertIn('#### (Review updated until commit https://example.invalid/synthetic/repo/commit/' + 'a' * 40 + ')', published)
        # The actual D15 consumer runs on the host in --image-smoke, where jq
        # already exists. Do not install tools into the producer image.
        self.assertEqual('clean', classify(published))
        provider.pr.head.sha = 'b' * 40
        with self.assertRaisesRegex(RuntimeError, 'head moved'):
            provider.publish_comment(generated)
        self.assertEqual(1, provider.pr.create_issue_comment.call_count)

    def test_producer_rejects_missing_wrong_or_unverifiable_identity_before_create(self):
        generated = STATE.append_review_state(review(False), state())
        for variant in ('missing_head', 'wrong_head', 'wrong_repo', 'wrong_state', 'too_small'):
            with self.subTest(variant=variant):
                provider = self.provider()
                if variant == 'missing_head': provider.last_commit_id.sha = None
                if variant == 'wrong_head': provider.last_commit_id.sha = 'b' * 40
                if variant == 'wrong_repo': provider.repo = 'other/repo'
                if variant == 'wrong_state': generated_input = generated.replace('"head_sha":"' + 'a' * 40, '"head_sha":"' + 'b' * 40)
                else: generated_input = generated
                if variant == 'too_small': provider.max_comment_chars = 20
                with self.assertRaises(RuntimeError):
                    provider.publish_comment(generated_input)
                provider.pr.create_issue_comment.assert_not_called()

    def test_producer_uncertain_create_or_readback_never_replays_or_edits(self):
        generated = STATE.append_review_state(review(False), state())
        for variant in ('uncertain', 'missing_id', 'readback_error', 'wrong_id', 'boolean_id', 'wrong_body'):
            with self.subTest(variant=variant):
                provider = self.provider()
                old = Mock(body=review(False))
                if variant == 'uncertain': provider.pr.create_issue_comment.side_effect = RuntimeError('synthetic transport uncertainty')
                if variant == 'missing_id': provider.pr.create_issue_comment.side_effect = lambda body: SimpleNamespace(body=body)
                if variant == 'readback_error': provider.pr.get_issue_comment.side_effect = RuntimeError('synthetic readback failure')
                if variant in ('wrong_id', 'boolean_id', 'wrong_body'):
                    original_readback = provider.pr.get_issue_comment.side_effect

                    def altered_readback(number):
                        record = original_readback(number)
                        return SimpleNamespace(
                            id=(True if variant == 'boolean_id' else number + (variant == 'wrong_id')),
                            body=('mismatch' if variant == 'wrong_body' else record.body))

                    provider.pr.get_issue_comment.side_effect = altered_readback
                with self.assertRaises(RuntimeError):
                    provider.edit_comment(old, generated)
                provider.pr.create_issue_comment.assert_called_once()
                old.edit.assert_not_called()

    def test_repeated_hook_installation_does_not_duplicate_publication(self):
        runtime.install_hooks()
        provider = self.provider()
        provider.publish_comment(STATE.append_review_state(review(False), state()))
        provider.pr.create_issue_comment.assert_called_once()
        provider.pr.get_issue_comment.assert_called_once()

    def test_non_review_delegation(self):
        provider = self.provider(10)
        for body in ('ordinary comment ' * 100, '**[Persistent review](https://example.invalid)** updated'):
            self.assertEqual(type(self).original_limiter(provider, body, 10), provider.limit_output_characters(body, 10))

    def test_real_renderer_reduction(self):
        from pr_agent.algo.utils import convert_to_markdown_v2
        from pr_agent.config_loader import get_settings
        get_settings().set('PR_REVIEWER.ENABLE_INTRO_TEXT', True)
        original = convert_to_markdown_v2({'review': {
            'estimated_effort_to_review_[1-5]': 3, 'relevant_tests': 'no',
            'contribution_time_cost_estimate': {'best_case': '10m', 'average_case': '20m', 'worst_case': '30m'},
            'security_concerns': 'no', 'key_issues_to_review': [],
            'review_priority_files': ['src/example.py ' * 10000],
            'risk_level': 'low', 'merge_recommendation': 'approve',
        }})
        self.assertGreater(len(original), 65000)
        result = self.provider().limit_output_characters(original, 65000)
        self.assertLessEqual(len(result), 65000)
        for protected in ('Here are some key observations', 'No security concerns identified',
                          'No major issues detected', '<strong>Risk level</strong>: Low',
                          '<strong>Merge recommendation</strong>: Approve'):
            self.assertIn(protected, result)
        self.assertEqual(classify(original), classify(result))

    def test_incompatible_hook_before_install(self):
        def unsupported(output):
            return output
        current = self.provider_class.limit_output_characters
        with patch.object(self.provider_class, 'limit_output_characters', unsupported):
            with self.assertRaisesRegex(RuntimeError, 'incompatible'):
                runtime.install_hooks()
        self.assertIs(current, self.provider_class.limit_output_characters)


# Captured read-only from PR #1983, issuecomment 6207732003, head 950f94e9.
PR_1983_REVIEW = (
    '## PR Reviewer Guide 🔍\n'
    '\n'
    '<!-- pr-agent:review:full -->\n'
    '\n'
    '#### (Review updated until commit https://github.com/lhpaul/ai-dev-framework-template/commit/950f94e9df62ce51c33a44733513bbdaff3f1d67)\n'
    '\n'
    '\n'
    'Here are some key observations to aid the review process:\n'
    '\n'
    '<table>\n'
    '<tr><td>⏱️&nbsp;<strong>Estimated effort to review</strong>: 3 🔵🔵🔵⚪⚪</td></tr>\n'
    '<tr><td>🧪&nbsp;<strong>PR contains tests</strong></td></tr>\n'
    '<tr><td>🔒&nbsp;<strong>No security concerns identified</strong></td></tr>\n'
    '<tr><td>⚡&nbsp;<strong>Recommended focus areas for review</strong><br><br>\n'
    '\n'
    "<details><summary><a href='https://github.com/lhpaul/ai-dev-framework-template/pull/1983/files#diff-d5b14e171d2f73383716d358c73452f57cc03a70974714ccd36e06090ab775dfR938-R942'><strong>Possible Issue</strong></a>\n"
    '\n'
    'The leading-metadata consumption loop strips the closing `-->` and then removes at most one following space (`normalized=${normalized# }`). If a receipt is followed by a newline (or multiple spaces) before the verdict, the loop exits with `normalized` still starting with whitespace, so the `^`-anchored template match fails and a clean review is rejected as `codex_current_verdict_unrecognized`. This works in the tests only because `codex_normalize_whitespace` collapses all whitespace to single spaces first, so the residual is exactly one space. The logic is correct given normalization runs first, but it is fragile: it silently depends on the caller having normalized. Confirm normalization always precedes this loop in both classifiers (it does in the shown code), otherwise the single-space strip is insufficient.\n'
    '</summary>\n'
    '\n'
    '```shell\n'
    'while [[ "$normalized" == \'<!--\'* ]]; do\n'
    '  [[ "$normalized" == *\'-->\'* ]] || return 1\n'
    '  normalized=${normalized#*-->}\n'
    '  normalized=${normalized# }\n'
    'done\n'
    '```\n'
    '\n'
    '</details>\n'
    '\n'
    "<details><summary><a href='https://github.com/lhpaul/ai-dev-framework-template/pull/1983/files#diff-5b4fab22790748d685f0bd2f84b270ce6a8adbe191389dd844deb2b7cca99ca8R123-R123'><strong>Test Isolation</strong></a>\n"
    '\n'
    "The fixture extraction uses `sed -n '/^codex_normalize_whitespace() {$/,/^}$/p; ...'` to source pure definitions from the target script. This relies on the function bodies containing no line that is exactly `}` at column 0 before the real closing brace. If any of these functions later contains a nested block whose closing brace is at column 0, the extracted snippet will be truncated mid-function and the test will fail confusingly rather than testing the classifier. This is a maintenance hazard rather than a current defect, since the current bodies satisfy the pattern.\n"
    '</summary>\n'
    '\n'
    '```shell\n'
    'source <(sed -n \'/^codex_normalize_whitespace() {$/,/^}$/p; /^CODEX_APPROVED_TEMPLATES=($/,/^)/p; /^codex_response_is_approved() {$/,/^}$/p\' "$1")\n'
    '```\n'
    '\n'
    '</details>\n'
    '\n'
    '</td></tr>\n'
    '</table>\n'
    '\n'
    '<details>\n'
    '<summary>✅ Resolved findings</summary>\n'
    '\n'
    '### scripts/development-workflow/apply-readiness-labels.sh:938-942\n'
    '\n'
    '**Possible Issue**\n'
    '\n'
    'The leading-metadata consumption loop strips only a single space after each `-->` (`normalized=${normalized# }`). Since `codex_normalize_whitespace` collapses all whitespace runs to a single space, this is normally fine, but the loop condition `[[ "$normalized" == \'<!--\'* ]]` requires the next comment to start immediately. If a body has two adjacent metadata comments separated by whitespace that normalizes to exactly one space, the single-space strip handles it; however, if the normalization ever leaves the body starting with a space before `<!--` (e.g. leading whitespace before the first comment), the loop won\'t enter and the template match fails closed. This is a fail-closed behavior, so impact is limited to false negatives, not false approvals. Verify the normalization guarantees no leading space remains before the first `<!--`.\n'
    '\n'
    '### scripts/development-workflow/tests/test-pr-review-loop-failure-paths-4.sh:120-127\n'
    '\n'
    '**Test Extraction Fragility**\n'
    '\n'
    "The `_codex_receipt_approval_status` helper extracts function definitions via `sed -n '/^codex_normalize_whitespace() {$/,/^}$/p; ...'`. This relies on the closing brace being exactly `^}$` on its own line. If the classifier functions are ever reformatted (e.g. closing brace indented, or a nested block ending with `}` at column 0), the extraction silently produces a truncated or empty definition, and the test would pass or fail for the wrong reason rather than erroring clearly. This is a test-maintenance concern, not a runtime defect.\n"
    '\n'
    '</details>\n'
    '\n'
    '<!-- pr-agent-review-state:v1\n'
    '{"findings":[{"body":"**Possible Issue**\\n\\nThe leading-metadata consumption loop strips the closing `--\\u003e` and then strips a single following space via `normalized=${normalized# }`. After `codex_normalize_whitespace`, all whitespace runs are already collapsed to a single space, so this is generally fine. However, consider the case where the metadata comment is the entire body (e.g. `<!-- codex-review-receipt:v1 --\\u003e`). The loop consumes the comment, leaving an empty string, and then falls through to the template match which fails — this is the intended fail-closed behavior. The concern is more subtle: if the body is `<!-- a --\\u003e<!-- b --\\u003e` (two adjacent comments with no whitespace), after consuming the first comment the remainder is `<!-- b --\\u003e` which still starts with `<!--`, so the loop continues correctly. This appears handled. No concrete defect identified.","finding_id":"154e2f148c34","first_seen":"2026-10-16T04:09:58.828595Z","last_seen":"2026-10-16T04:09:58.828595Z","last_seen_head_sha":"950f94e9df62ce51c33a44733513bbdaff3f1d67","line_end":942,"line_start":938,"path":"scripts/development-workflow/apply-readiness-labels.sh","state":"ACTIVE"},{"body":"**Possible Issue**\\n\\nThe leading-metadata consumption loop strips the closing `--\\u003e` and then removes at most one following space (`normalized=${normalized# }`). If a receipt is followed by a newline (or multiple spaces) before the verdict, the loop exits with `normalized` still starting with whitespace, so the `^`-anchored template match fails and a clean review is rejected as `codex_current_verdict_unrecognized`. This works in the tests only because `codex_normalize_whitespace` collapses all whitespace to single spaces first, so the residual is exactly one space. The logic is correct given normalization runs first, but it is fragile: it silently depends on the caller having normalized. Confirm normalization always precedes this loop in both classifiers (it does in the shown code), otherwise the single-space strip is insufficient.","finding_id":"1d092640b813","first_seen":"2026-10-16T11:47:16.601922Z","last_seen":"2026-10-16T11:47:16.601922Z","last_seen_head_sha":"950f94e9df62ce51c33a44733513bbdaff3f1d67","line_end":942,"line_start":938,"path":"scripts/development-workflow/apply-readiness-labels.sh","state":"ACTIVE"},{"body":"**Test Isolation**\\n\\nThe fixture extraction uses `sed -n \'/^codex_normalize_whitespace() {$/,/^}$/p; ...\'` to source pure definitions from the target script. This relies on the function bodies containing no line that is exactly `}` at column 0 before the real closing brace. If any of these functions later contains a nested block whose closing brace is at column 0, the extracted snippet will be truncated mid-function and the test will fail confusingly rather than testing the classifier. This is a maintenance hazard rather than a current defect, since the current bodies satisfy the pattern.","finding_id":"ae538e9769b3","first_seen":"2026-10-16T11:47:16.601922Z","last_seen":"2026-10-16T11:47:16.601922Z","last_seen_head_sha":"950f94e9df62ce51c33a44733513bbdaff3f1d67","line_end":123,"line_start":123,"path":"scripts/development-workflow/tests/test-pr-review-loop-failure-paths-4.sh","state":"ACTIVE"},{"body":"**Test Extraction Fragility**\\n\\nThe `_codex_receipt_approval_status` helper extracts function definitions via `sed -n \'/^codex_normalize_whitespace() {$/,/^}$/p; ...\'`. This relies on the closing brace being exactly `^}$` on its own line. If the classifier functions are ever reformatted (e.g. closing brace indented, or a nested block ending with `}` at column 0), the extraction silently produces a truncated or empty definition, and the test would pass or fail for the wrong reason rather than erroring clearly. This is a test-maintenance concern, not a runtime defect.","finding_id":"e64a1db73aa4","first_seen":"2026-10-16T03:56:43.795201Z","last_seen":"2026-10-16T03:56:43.795201Z","last_seen_head_sha":"12dfd02f66ee980edd37b554e6660a0a95908d65","line_end":127,"line_start":120,"path":"scripts/development-workflow/tests/test-pr-review-loop-failure-paths-4.sh","resolution_run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/950f94e9df62ce51c33a44733513bbdaff3f1d67","resolved_at":"2026-10-16T04:09:58.828595Z","resolved_head_sha":"950f94e9df62ce51c33a44733513bbdaff3f1d67","state":"RESOLVED"},{"body":"**Possible Issue**\\n\\nThe leading-metadata consumption loop strips only a single space after each `--\\u003e` (`normalized=${normalized# }`). Since `codex_normalize_whitespace` collapses all whitespace runs to a single space, this is normally fine, but the loop condition `[[ \\"$normalized\\" == \'<!--\'* ]]` requires the next comment to start immediately. If a body has two adjacent metadata comments separated by whitespace that normalizes to exactly one space, the single-space strip handles it; however, if the normalization ever leaves the body starting with a space before `<!--` (e.g. leading whitespace before the first comment), the loop won\'t enter and the template match fails closed. This is a fail-closed behavior, so impact is limited to false negatives, not false approvals. Verify the normalization guarantees no leading space remains before the first `<!--`.","finding_id":"f4066716eaeb","first_seen":"2026-10-16T03:56:43.795201Z","last_seen":"2026-10-16T03:56:43.795201Z","last_seen_head_sha":"12dfd02f66ee980edd37b554e6660a0a95908d65","line_end":942,"line_start":938,"path":"scripts/development-workflow/apply-readiness-labels.sh","resolution_run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/950f94e9df62ce51c33a44733513bbdaff3f1d67","resolved_at":"2026-10-16T04:09:58.828595Z","resolved_head_sha":"950f94e9df62ce51c33a44733513bbdaff3f1d67","state":"RESOLVED"}],"last_run":{"complete":true,"excluded_files":[],"head_sha":"950f94e9df62ce51c33a44733513bbdaff3f1d67","kind":"full","run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/950f94e9df62ce51c33a44733513bbdaff3f1d67"},"schema_version":1}\n'
    '-->\n'
)


# Captured read-only from PR #1986, issuecomment 6217136440, head 8d51852b.
PR_1986_INLINE_REVIEW = (
    '## PR Reviewer Guide 🔍\n'
    '\n'
    '<!-- pr-agent:review:full -->\n'
    '\n'
    '#### (Review updated until commit https://github.com/lhpaul/ai-dev-framework-template/commit/8d51852b44188908a24fa7851b26e1108199331e)\n'
    '\n'
    '\n'
    'Here are some key observations to aid the review process:\n'
    '\n'
    '<table>\n'
    '<tr><td>⏱️&nbsp;<strong>Estimated effort to review</strong>: 3 🔵🔵🔵⚪⚪</td></tr>\n'
    '<tr><td>🧪&nbsp;<strong>PR contains tests</strong></td></tr>\n'
    '<tr><td>🔒&nbsp;<strong>No security concerns identified</strong></td></tr>\n'
    '<tr><td>⚡&nbsp;<strong>Recommended focus areas for review</strong><br><br>\n'
    '\n'
    "<details><summary><a href='https://github.com/lhpaul/ai-dev-framework-template/pull/1986/files#diff-dba3e72840843ae37245e2f7afa96e5826cda270ac9fc17c31ea59c73bfbd184R141-R151'><strong>Possible Issue</strong></a>\n"
    '\n'
    'In `mask_review_code`, the review-state branch is only entered when `source.startswith("<!--", index)` and the regex `<!--\\s*pr-agent-review-state` matches. The new `review_state_seen` flag raises `ValueError("duplicate review-state marker")` on a second marker. However, the duplicate detection relies on the marker being reached via this exact path. If a second `pr-agent-review-state` marker appears inside a fenced code block or is otherwise masked before reaching this branch, the duplicate is not detected. This is likely intentional (masked content is opaque), but worth confirming the fail-closed guarantee holds for the intended threat model. Low confidence; the test `test_malformed_and_unknown_state_fail_closed` covers the adjacent-marker case.\n'
    '</summary>\n'
    '\n'
    '```python\n'
    'if source.startswith("<!--", index):\n'
    '    if re.match(r"<!--\\s*pr-agent-review-state", source[index:]):\n'
    '        if review_state_seen:\n'
    '            raise ValueError("duplicate review-state marker")\n'
    '        end = review_state_comment_end(source, index)\n'
    '        review_state_seen = True\n'
    '        # Only the in-memory parser view changes. Preserve offsets for\n'
    '        # publication spans; JSON strings are opaque to HTML scanning.\n'
    '        parts.append("<!--" + masked(index + 4, end - 3) + "-->")\n'
    '        index = end\n'
    '        continue\n'
    '```\n'
    '\n'
    '</details>\n'
    '\n'
    "<details><summary><a href='https://github.com/lhpaul/ai-dev-framework-template/pull/1986/files#diff-dba3e72840843ae37245e2f7afa96e5826cda270ac9fc17c31ea59c73bfbd184R265-R268'><strong>Possible Issue</strong></a>\n"
    '\n'
    '`review_state_comment_end` uses `decoder.raw_decode(source, start + header.end())` and then matches `\\s*-->` after the decoded JSON. If the JSON object is followed by trailing content other than whitespace before `-->` (e.g. a stray token), `raw_decode` stops at the object end and the `\\s*-->` match fails, raising `unclosed review-state marker`. This is fail-closed and acceptable. No concrete defect; noting only that the error message may be misleading for trailing-garbage cases. Not flagging as a bug.\n'
    '</summary>\n'
    '\n'
    '```python\n'
    'closing = re.match(r"\\s*-->", source[end:])\n'
    'if closing is None:\n'
    '    raise ValueError("unclosed review-state marker")\n'
    'return end + closing.end()\n'
    '```\n'
    '\n'
    '</details>\n'
    '\n'
    '</td></tr>\n'
    '</table>\n'
    '\n'
    '<!-- pr-agent-review-state:v1\n'
    '{"findings":[{"body":"**Possible Issue**\\n\\n`review_state_comment_end` uses `decoder.raw_decode(source, start + header.end())` and then matches `\\\\s*--\\u003e` after the decoded JSON. If the JSON object is followed by trailing content other than whitespace before `--\\u003e` (e.g. a stray token), `raw_decode` stops at the object end and the `\\\\s*--\\u003e` match fails, raising `unclosed review-state marker`. This is fail-closed and acceptable. No concrete defect; noting only that the error message may be misleading for trailing-garbage cases. Not flagging as a bug.","finding_id":"7097fba26714","first_seen":"2026-10-16T14:05:06.280922Z","last_seen":"2026-10-16T14:05:06.280922Z","last_seen_head_sha":"8d51852b44188908a24fa7851b26e1108199331e","line_end":268,"line_start":265,"path":"scripts/development-workflow/pr-agent-runtime.py","state":"ACTIVE"},{"body":"**Possible Issue**\\n\\nIn `mask_review_code`, the review-state branch is only entered when `source.startswith(\\"<!--\\", index)` and the regex `<!--\\\\s*pr-agent-review-state` matches. The new `review_state_seen` flag raises `ValueError(\\"duplicate review-state marker\\")` on a second marker. However, the duplicate detection relies on the marker being reached via this exact path. If a second `pr-agent-review-state` marker appears inside a fenced code block or is otherwise masked before reaching this branch, the duplicate is not detected. This is likely intentional (masked content is opaque), but worth confirming the fail-closed guarantee holds for the intended threat model. Low confidence; the test `test_malformed_and_unknown_state_fail_closed` covers the adjacent-marker case.","finding_id":"f5d49efd62e3","first_seen":"2026-10-16T14:05:06.280922Z","last_seen":"2026-10-16T14:05:06.280922Z","last_seen_head_sha":"8d51852b44188908a24fa7851b26e1108199331e","line_end":151,"line_start":141,"path":"scripts/development-workflow/pr-agent-runtime.py","state":"ACTIVE"}],"last_run":{"complete":false,"excluded_files":[],"head_sha":"8d51852b44188908a24fa7851b26e1108199331e","kind":"partial","run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/8d51852b44188908a24fa7851b26e1108199331e"},"schema_version":1}\n'
    '-->\n'
)


class HiddenReviewStateTests(unittest.TestCase):
    def labels(self, body):
        return subprocess.run(
            ["bash", str(ROOT / "scripts/development-workflow/apply-readiness-labels.sh"),
             "--pr-agent-focus-labels"], input=body, text=True,
            capture_output=True, check=True,
        ).stdout

    def test_real_1983_comment_reaches_visible_findings(self):
        original = PR_1983_REVIEW
        self.assertIn("950f94e9df62ce51c33a44733513bbdaff3f1d67", original)
        self.assertGreater(original.count("<!--"), original.count("-->"))
        self.assertEqual("Possible Issue\nTest Isolation", self.labels(original))
        # Unknown visible labels remain closed (#1972 is a separate item).
        self.assertEqual("escalate", classify(original))
        # A test-only copy isolates the delimiter bug from that unknown label.
        known_advisories = original.replace("<strong>Test Isolation</strong>",
                                            "<strong>Possible Issue</strong>")
        self.assertEqual("clean", classify(known_advisories))
        blocker = known_advisories.replace("<strong>Possible Issue</strong>",
                                           "<strong>Must fix</strong>", 1)
        self.assertEqual("needs_fixes", classify(blocker))
        self.assertEqual(original, PR_1983_REVIEW)

    def test_json_delimiters_are_data_with_and_without_producer_escaping(self):
        snapshot = state(size=0)
        snapshot["findings"][0]["body"] = (
            '<!-- nested <!-- "quoted" \\ --> --!> `unclosed <table> 雪'
        )
        snapshot["findings"][0]["extra"] = {"items": ["<!--", "-->", {"a": "<!--"}]}
        for payload in (json.dumps(snapshot),
                        json.dumps(snapshot).replace("-->", "--\\u003e")):
            hidden = "<!-- pr-agent-review-state:v1\n" + payload + "\n-->"
            self.assertEqual(snapshot, json.loads(payload))
            for blocking in (False, True):
                with self.subTest(escaped="\\u003e" in payload, blocking=blocking):
                    body = review(blocking=blocking, suffix=hidden)
                    self.assertEqual("needs_fixes" if blocking else "clean", classify(body))
                    self.assertEqual("Must fix" if blocking else "", self.labels(body))

    def test_malformed_and_unknown_state_fail_closed(self):
        invalid = (
            "<!-- pr-agent-review-state:v2 {} -->",
            "<!-- pr-agent-review-state:v10 {} -->",
            "<!-- pr-agent-review-state {} -->",
            "<!-- pr-agent-review-state:v1 -->",
            "<!-- pr-agent-review-state:v1 {broken} -->",
            "<!-- pr-agent-review-state:v1 [] -->",
            "<!-- pr-agent-review-state:v1 null -->",
            "<!-- pr-agent-review-state:v1 {} trailing -->",
            "<!-- pr-agent-review-state:v1 {}",
            '<!-- pr-agent-review-state:v1 {"schema_version":2} -->',
            '<!-- pr-agent-review-state:v1 {"schema_version":true} -->',
            '<!-- pr-agent-review-state:v1 {"a":1,"a":2} -->',
            '<!-- pr-agent-review-state:v1 {"nested":{"a":1,"a":2}} -->',
            '<!-- pr-agent-review-state:v1 {"a":NaN} -->',
            '<!-- pr-agent-review-state:v1 {"a":Infinity} -->',
            '<!-- pr-agent-review-state:v1 {"body":"unterminated -->',
            "<!-- pr-agent-review-state:v1 {} --!>",
            "<!-- pr-agent-review-state:v1 {} -->" * 2,
        )
        for hidden in invalid:
            with self.subTest(hidden=hidden):
                body = review(suffix=hidden)
                self.assertEqual("escalate", classify(body))
                self.assertEqual("", self.labels(body))

    def test_invalid_html_outside_state_and_later_blockers_remain_visible(self):
        hidden = SyntheticState.serialize_review_state(state(size=0))
        for tail in ("<!-- unclosed", "<!-- nested <!-- -->", "-->"):
            with self.subTest(tail=tail):
                self.assertEqual("escalate", classify(review(suffix=hidden + tail)))
        self.assertEqual("needs_fixes", classify(hidden + "\n" + review(blocking=True)))
        self.assertEqual("needs_fixes", classify(review(suffix=hidden + "\n### Security concerns: Critical\n")))


if __name__ == '__main__':
    runtime.LOGGER.addHandler(logging.NullHandler())
    if IMAGE_SMOKE and sys.argv[1:] == ['--emit-synthetic-d15-record']:
        ImagePublicationTests.setUpClass()
        try:
            fixture = ImagePublicationTests('test_new_d15_record_with_prior_summary_and_review_trigger')
            provider = fixture.provider()
            compact_state = state()
            compact_state['findings'] = []
            body = STATE.append_review_state(review(False), compact_state)
            response = provider.publish_persistent_comment_full(body, initial_header=HEADERS[0])
            print(json.dumps({'body': response.body, 'head': 'a' * 40,
                              'creates': provider.pr.create_issue_comment.call_count,
                              'readbacks': provider.pr.get_issue_comment.call_count}))
        finally:
            ImagePublicationTests.tearDownClass()
    else:
        unittest.main(verbosity=2)

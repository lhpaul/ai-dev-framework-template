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
    '1966': r'''## PR Reviewer Guide 🔍

<!-- pr-agent:review:full -->

Here are some key observations to aid the review process:

<table>
<tr><td>⏱️&nbsp;<strong>Estimated effort to review</strong>: 3 🔵🔵🔵⚪⚪</td></tr>
<tr><td>🧪&nbsp;<strong>PR contains tests</strong></td></tr>
<tr><td>🔒&nbsp;<strong>No security concerns identified</strong></td></tr>
<tr><td>⚡&nbsp;<strong>Recommended focus areas for review</strong><br><br>

<details><summary><a href='https://github.com/lhpaul/ai-dev-framework-template/pull/1966/files#diff-5fa4b162a9e57de4f6e9dfcb5398951dacfdc660caae3d8f8daf42962921dc46R1236-R1242'><strong>Possible Issue</strong></a>

The new `--release-head` authorization check reads `$child_binding` and `$SESSION_CHILD`, but these are only assigned inside the `if [ -n "$MERGE_SESSION" ] && [ -n "${WORKFLOW_MERGE_BUDGET_TOKEN:-}" ]` block. When a caller passes `--release-head` without a merge session (or without the budget token), `child_binding` is unset. Under `set -u` (nounset, used by these scripts) the `printf '%s' "$child_binding"` in the rejection branch would abort with an unbound-variable error rather than the intended exit 2 message. The guard should default `child_binding` (e.g. `child_binding=""`) before the check, or test `$SESSION_CHILD` first. Note: the added test `test_release_head_rejected_before_ordinary_cleanup` passes `--release-head` without a session, so if that test passes it may indicate the variable is initialized elsewhere in the file — verify the initialization before treating this as confirmed.
</summary>

```shell
if [ "$RELEASE_HEAD_SET" = "true" ] && [ "$INSPECT_TARGETS" != "true" ]; then
  if [ "$SESSION_CHILD" != "true" ] || ! printf '%s' "$child_binding" | jq -e --arg head "$RELEASE_HEAD" \
    '.releasePair != null and .releasePair.head == $head and .selectedPR == .releasePair.backportPr' >/dev/null; then
    echo "--release-head is only supported for read-only --inspect-targets or the authenticated owning release cleanup child." >&2
    exit 2
  fi
fi
```

</details>

</td></tr>
</table>

<!-- pr-agent-review-state:v1
{"findings":[{"body":"**Possible Issue**\n\nThe new `--release-head` authorization check reads `$child_binding` and `$SESSION_CHILD`, but these are only assigned inside the `if [ -n \"$MERGE_SESSION\" ] && [ -n \"${WORKFLOW_MERGE_BUDGET_TOKEN:-}\" ]` block. When a caller passes `--release-head` without a merge session (or without the budget token), `child_binding` is unset. Under `set -u` (nounset, used by these scripts) the `printf '%s' \"$child_binding\"` in the rejection branch would abort with an unbound-variable error rather than the intended exit 2 message. The guard should default `child_binding` (e.g. `child_binding=\"\"`) before the check, or test `$SESSION_CHILD` first. Note: the added test `test_release_head_rejected_before_ordinary_cleanup` passes `--release-head` without a session, so if that test passes it may indicate the variable is initialized elsewhere in the file — verify the initialization before treating this as confirmed.","finding_id":"a31a4f1947d3","first_seen":"2026-10-14T23:06:44.710516Z","last_seen":"2026-10-14T23:06:44.710516Z","last_seen_head_sha":"73d1bd159b1b1bd1f52459ecc33939ee78b826a6","line_end":1242,"line_start":1236,"path":"scripts/development-workflow/prepare-release-post-merge-cleanup.sh","state":"ACTIVE"}],"last_run":{"complete":true,"excluded_files":[],"head_sha":"73d1bd159b1b1bd1f52459ecc33939ee78b826a6","kind":"full","run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/73d1bd159b1b1bd1f52459ecc33939ee78b826a6"},"schema_version":1}
-->

''',
    '1974': r'''## PR Reviewer Guide 🔍

<!-- pr-agent:review:full -->

#### (Review updated until commit https://github.com/lhpaul/ai-dev-framework-template/commit/76a0820f0f899398040511c40c16182a8aaab127)


Here are some key observations to aid the review process:

<table>
<tr><td>⏱️&nbsp;<strong>Estimated effort to review</strong>: 4 🔵🔵🔵🔵⚪</td></tr>
<tr><td>🧪&nbsp;<strong>PR contains tests</strong></td></tr>
<tr><td>🔒&nbsp;<strong>No security concerns identified</strong></td></tr>
<tr><td>⚡&nbsp;<strong>Recommended focus areas for review</strong><br><br>

<details><summary><a href='https://github.com/lhpaul/ai-dev-framework-template/pull/1974/files#diff-69990674c60490161235d30d9b51b9c6d186bdee2ab0fa8e1029dca6abb9858fR365-R378'><strong>Possible Issue</strong></a>

The `protected_risk_path` function matches release tooling with patterns like `scripts/*release*.sh`, `.github/workflows/*release*`, and `.agents/skills/*release*/*`. These use `*` which in shell `case` matches across `/` boundaries, so a path such as `scripts/development-workflow/prepare-release-post-merge-cleanup.sh` matches `scripts/*release*.sh` (intended), but also a nested path like `scripts/foo/bar/release-helper.sh` would match. More importantly, the pattern `.github/workflows/*release*` will match any workflow whose name contains `release` anywhere, including `deploy-release-notes.yml`, which is the intended conservative behavior. This is likely intentional, but verify that the broad `*release*` matching does not re-introduce the false-positive class the PR aims to fix for paths under `scripts/` that merely mention release in a subdirectory name (e.g. `scripts/docs/release-notes.md` would not match since it requires `.sh`/`.py`). Confirm the tooling-root scoping is as narrow as the plan intends.
</summary>

```shell
protected_risk_path() {
  case "$1" in
    scripts/*release*.sh|scripts/*release*.py|.github/workflows/*release*|\
    .claude/commands/*release*.md|.cursor/commands/*release*.md|\
    .agents/skills/*release*/*|.codex/skills/*release*/*|\
    *branch-deletion*|*delete-branch*|\
    auth/*|*/auth/*|*/auth|authentication/*|*/authentication/*|*/authentication|\
    secret/*|*/secret/*|*/secret|secrets/*|*/secrets/*|*/secrets|\
    credential/*|*/credential/*|*/credential|credentials/*|*/credentials/*|*/credentials|\
    permission/*|*/permission/*|*/permission|permissions/*|*/permissions/*|*/permissions)
      return 0 ;;
  esac
  return 1
}
```

</details>

<details><summary><a href='https://github.com/lhpaul/ai-dev-framework-template/pull/1974/files#diff-c6cd4825f13ea12046fe63020bbb4ae7cda1684a24d681b71e8e54b06b72acafR82-R98'><strong>Possible Issue</strong></a>

In `select_map`, when `mode == "workflow_hub"` and `own_map` is present but no product maps exist, and no product identity is supplied, the code falls through to `raise RiskPathError("project risk map requires an unambiguous project identity")` only when `product_maps` is non-empty. When `all(node is MISSING for node in product_maps)` is true and `own_map` is not MISSING, the `elif all(...)` branch returns `own_map`. This means a hub with a top-level map but no product maps and no selector silently uses the hub map for any product, which may be intended. However, if `product_maps` is non-empty but the selected product has no map, `map_node` returns MISSING and `rules_from_node` yields no rules, so the product silently gets built-ins rather than the hub map — verify this matches the documented "absent product rules use built-ins and never inherit sibling or hub categories" behavior. The concern is whether a product entry that omits `guardrails` is distinguishable from one that intends to inherit; the docs say it should not inherit, so this appears correct, but the fall-through ordering deserves a test for the mixed case (some products mapped, some not).
</summary>

```python
if selected:
    candidates = [repo for repo in repos if repo["name"] == selected]
elif slug:
    if slug == reader.parse_remote_slug(root):
        return own_map, location
    candidates = [repo for repo in repos if repo_slug(repo) == slug]
elif all(node is MISSING for node in product_maps):
    return own_map, location
else:
    raise RiskPathError("project risk map requires an unambiguous project identity")
if len(candidates) != 1:
    raise RiskPathError("project risk map target is unknown or ambiguous")
selected_repo = candidates[0]
if slug and repo_slug(selected_repo) != slug:
    raise RiskPathError("project risk map selector and evidence repository disagree")
location = "workflow_hub.product_repos[].guardrails.risk_paths"
return map_node(selected_repo, "selected product"), location
```

</details>

</td></tr>
</table>

<!-- pr-agent-review-state:v1
{"findings":[{"body":"**Possible Issue**\n\nThe `changed_file_risk` function now rebuilds `file_reasons` for each file and appends to the global `reasons` array. For files that match the `scripts/development-workflow/tests/*|test/*|tests/*` case, `file_risk` remains `low` and a reason is appended. However, if a project map matches the same file with a higher risk, the project risk overrides `file_risk` but the built-in reason is still appended. This means the reasons array may contain both the built-in \"low-risk docs or tests change\" reason and the project reason, even though the final risk is higher. This is likely intentional for visibility, but could be confusing. The test `mapped_reason_is_visible` checks for project reason presence, not absence of built-in reasons.","finding_id":"3443f7ae914b","first_seen":"2026-10-15T12:26:28.618644Z","last_seen":"2026-10-15T12:26:28.618644Z","last_seen_head_sha":"76a0820f0f899398040511c40c16182a8aaab127","line_end":418,"line_start":407,"path":"scripts/development-workflow/run-epic-risk-classifier.sh","state":"ACTIVE"},{"body":"**Possible Issue**\n\nThe `protected_risk_path` function matches release tooling with patterns like `scripts/*release*.sh`, `.github/workflows/*release*`, and `.agents/skills/*release*/*`. These use `*` which in shell `case` matches across `/` boundaries, so a path such as `scripts/development-workflow/prepare-release-post-merge-cleanup.sh` matches `scripts/*release*.sh` (intended), but also a nested path like `scripts/foo/bar/release-helper.sh` would match. More importantly, the pattern `.github/workflows/*release*` will match any workflow whose name contains `release` anywhere, including `deploy-release-notes.yml`, which is the intended conservative behavior. This is likely intentional, but verify that the broad `*release*` matching does not re-introduce the false-positive class the PR aims to fix for paths under `scripts/` that merely mention release in a subdirectory name (e.g. `scripts/docs/release-notes.md` would not match since it requires `.sh`/`.py`). Confirm the tooling-root scoping is as narrow as the plan intends.","finding_id":"3960ab9411ef","first_seen":"2026-10-15T12:28:02.850774Z","last_seen":"2026-10-15T12:28:02.850774Z","last_seen_head_sha":"76a0820f0f899398040511c40c16182a8aaab127","line_end":378,"line_start":365,"path":"scripts/development-workflow/run-epic-risk-classifier.sh","state":"ACTIVE"},{"body":"**Possible Issue**\n\nIn `select_map`, when `mode == \"workflow_hub\"` and `own_map` is present but no product maps exist, and no product identity is supplied, the code falls through to `raise RiskPathError(\"project risk map requires an unambiguous project identity\")` only when `product_maps` is non-empty. When `all(node is MISSING for node in product_maps)` is true and `own_map` is not MISSING, the `elif all(...)` branch returns `own_map`. This means a hub with a top-level map but no product maps and no selector silently uses the hub map for any product, which may be intended. However, if `product_maps` is non-empty but the selected product has no map, `map_node` returns MISSING and `rules_from_node` yields no rules, so the product silently gets built-ins rather than the hub map — verify this matches the documented \"absent product rules use built-ins and never inherit sibling or hub categories\" behavior. The concern is whether a product entry that omits `guardrails` is distinguishable from one that intends to inherit; the docs say it should not inherit, so this appears correct, but the fall-through ordering deserves a test for the mixed case (some products mapped, some not).","finding_id":"55f491a5f239","first_seen":"2026-10-15T12:28:02.850774Z","last_seen":"2026-10-15T12:28:02.850774Z","last_seen_head_sha":"76a0820f0f899398040511c40c16182a8aaab127","line_end":98,"line_start":82,"path":"scripts/development-workflow/workflow-risk-paths.py","state":"ACTIVE"},{"body":"**Possible Issue**\n\nThe `protected_risk_path` function is invoked before the built-in `case` categories, and it returns `high` for any path matching `scripts/*release*.sh`. However, the previous `*release*` pattern was intentionally broad and also covered release-named docs. The new function narrows release detection to tooling roots, which is the stated intent. The concern is that `protected_risk_path` is checked first and sets `floor_reason`, but the subsequent `case` block for `.github/workflows/*` can also set `floor_reason` for non-test/lint workflows. If a file matches both `protected_risk_path` (e.g., `.github/workflows/*release*`) and the `.github/workflows/*` case, the `floor_reason` from `protected_risk_path` is set, then the `case` block runs and may overwrite `floor_reason` with the same or a different message. Since both set `file_risk=\"high\"`, the final risk is correct, but the reason text may be duplicated or replaced. This is a minor cosmetic issue, not a correctness bug, but worth confirming the reason aggregation is as intended.","finding_id":"6e81189b04dc","first_seen":"2026-10-15T12:26:28.618644Z","last_seen":"2026-10-15T12:26:28.618644Z","last_seen_head_sha":"76a0820f0f899398040511c40c16182a8aaab127","line_end":405,"line_start":391,"path":"scripts/development-workflow/run-epic-risk-classifier.sh","state":"ACTIVE"},{"body":"**Possible Issue**\n\nIn `select_map`, when `mode == \"workflow_hub\"` and `own_map` is not MISSING but `product_maps` are all MISSING, the function proceeds to select a product. If `selected` is empty and `slug` is empty, it falls through to `elif all(node is MISSING for node in product_maps): return own_map, location`. This is correct. However, if `selected` is provided but no product matches, `candidates` is empty and `len(candidates) != 1` raises an error. This is intended. The concern is the case where `slug` matches the hub remote (`slug == reader.parse_remote_slug(root)`) and `own_map` is MISSING but product maps exist. The function returns `own_map` (MISSING) and location, which means no rules are applied. This is correct for hub-owned files, but if the hub remote slug is provided as evidence for a product file, it would incorrectly use hub policy. The test `test_project_isolation_and_explicit_priority` covers this, so it appears intentional.","finding_id":"a6236f8c966e","first_seen":"2026-10-15T12:26:28.618644Z","last_seen":"2026-10-15T12:26:28.618644Z","last_seen_head_sha":"76a0820f0f899398040511c40c16182a8aaab127","line_end":89,"line_start":82,"path":"scripts/development-workflow/workflow-risk-paths.py","state":"ACTIVE"}],"last_run":{"complete":true,"excluded_files":[],"head_sha":"76a0820f0f899398040511c40c16182a8aaab127","kind":"full","run_id":"https://github.com/lhpaul/ai-dev-framework-template/commit/76a0820f0f899398040511c40c16182a8aaab127"},"schema_version":1}
-->

''',
}


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
                    "details", "summary"):
            body = review() + "\n<" + tag + ">Use `helper()`.</" + tag + ">\n"
            self.assertEqual("clean", classify(body), tag)

    def test_real_blockers_survive_inline_examples(self):
        for label in ("Must fix", "Critical", "Security concern", "Breaking change"):
            body = self.finding("Read `helper()`.", label)
            self.assertEqual("needs_fixes", classify(body))
            self.assertEqual([label], self.labels(body))
        body = self.finding("Example: `<strong>Must fix</strong>`.")
        self.assertEqual("escalate", classify(body))

    def test_quoted_code_and_comments_cannot_supply_clean_evidence(self):
        for sample in ("`No major issues detected`", "<!-- No major issues detected -->",
                       '<span title="No major issues detected">example</span>'):
            body = "<details><summary>" + sample + "</summary></details>"
            self.assertEqual("escalate", classify(body))
        body = self.finding("`Possible Issue`").replace("<strong>Possible Issue</strong>", "")
        self.assertNotEqual("clean", classify(body))

    def test_unsupported_and_ambiguous_inputs_still_escalate(self):
        for content in ("`unclosed", "``double``", "`two\nlines`", "`trailing\\`",
                        "\\`escaped`", "`</summary><strong>Must fix</strong>`",
                        "`<!-- hidden -->`", "<div>`helper()`</div>",
                        '<a title="`helper()`">text</a>',
                        "<a title=bad`attribute`>text</a>"):
            with self.subTest(content=content):
                self.assertEqual("escalate", classify(self.finding(content)))
        body = self.finding("`helper()`").replace("</summary>", "</details>", 1)
        self.assertEqual("escalate", classify(body))

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
        self.assertIn('ref: ${{ github.event_name == \'pull_request\' && github.event.pull_request.head.sha || github.sha }}', source)
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
        runtime.install_hooks()

    @classmethod
    def tearDownClass(cls):
        import pr_agent.tools.pr_reviewer as reviewer
        STATE.append_review_state = cls.original_composer
        reviewer.append_review_state = cls.original_alias
        cls.provider_class.limit_output_characters = cls.original_limiter

    def provider(self, limit=65000):
        provider = self.provider_class.__new__(self.provider_class)
        provider.pr = Mock()
        provider.issue_main = None
        provider.max_comment_chars = limit
        provider.pr.comments_list = []
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
            self.assertIn(visible.rstrip(), outbound)
            self.assertEqual(classify(visible), classify(outbound))
            comment = Mock()
            body = generated.replace('<!-- pr-agent:review:full -->',
                                     '<!-- pr-agent:review:full -->\n\n#### (Review updated until commit https://example.invalid/commit/' + 'a' * 40 + ')')
            provider.edit_comment(comment, body)
            outbound = comment.edit.call_args.kwargs['body']
            self.assertLessEqual(len(outbound), 65000)
            self.assertIn('a' * 40, outbound)
            self.assertEqual(classify(visible), classify(outbound))
            self.assertIsNone(STATE.parse_review_state(outbound).state)
            provider.get_latest_commit_url = Mock(return_value='https://example.invalid/commit/' + 'a' * 40)
            provider.get_comment_url = Mock(return_value='https://example.invalid/comment/1')
            comment.reset_mock()
            with patch.object(GitProvider, '_iter_persistent_comments', return_value=iter([(comment, visible)])):
                provider.publish_persistent_comment_full(
                    generated, initial_header='## PR Reviewer Guide 🔍', final_update_message=False,
                    fallback_on_error=False,
                )
            outbound = comment.edit.call_args.kwargs['body']
            self.assertIn('Review updated until commit https://example.invalid/commit/' + 'a' * 40, outbound)
            self.assertLessEqual(len(outbound), 65000)
            self.assertEqual(classify(visible), classify(outbound))

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


if __name__ == '__main__':
    runtime.LOGGER.addHandler(logging.NullHandler())
    unittest.main(verbosity=2)

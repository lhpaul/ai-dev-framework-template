"""Publication regressions; synthetic state, no GitHub or model calls."""

import importlib.util
import json
import logging
import os
from pathlib import Path
import re
import subprocess
import sys
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


class FittingTests(unittest.TestCase):
    def fit(self, body, limit=65000):
        result = runtime.fit_review(body, limit, STATE, HEADERS)
        self.assertLessEqual(len(result), limit)
        return result

    def test_unchanged_comments(self):
        for body in ("", review(), review(True), "unknown review -- invalid marker"):
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
            visible = review(blocking, 'source ' * 10000 if blocking else '', guide)
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
        excerpt = '```html\n<summary>fake</summary>\n<details>fake</details>\n```\n' + 'code ' * 16000
        visible = review(True, excerpt)
        result = self.fit(visible)
        self.assertIn('The original blocker must remain visible.\n</summary>', result)
        self.assertNotIn('fake', result)
        self.assertEqual(classify(visible), classify(result))
        runtime.ReviewSpans(result)
        unsafe = visible.replace('```html\n', '').replace('\n```', '')
        self.assertEqual('escalate', classify(self.fit(unsafe)))

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

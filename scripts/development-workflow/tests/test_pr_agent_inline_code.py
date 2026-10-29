#!/usr/bin/env python3
"""Synthetic source-formatting and pinned producer publication regressions."""
import copy
import importlib.util
import os
import json
from html import unescape
from types import SimpleNamespace
from unittest.mock import Mock
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('inline_runtime', ROOT / 'scripts/development-workflow/pr-agent-runtime.py')
runtime = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = runtime
spec.loader.exec_module(runtime)
EXPRESSION = 're.split(r"</td>|^### ", section)'
TEXT = 'Consider `' + EXPRESSION + '` here.'


def data(text=TEXT, header='Possible Issue', security='No'):
    return {'review': {'security_concerns': security, 'key_issues_to_review': [
        {'relevant_file': 'src/example.py', 'issue_header': header, 'issue_content': text}]}}


class SourceTests(unittest.TestCase):
    def test_mixed_closing_tag(self):
        result = runtime.normalize_finding_inline_code(TEXT)
        self.assertEqual('Consider <code>re.split(r&quot;&lt;/td&gt;|^### &quot;, section)</code> here.', result)
        self.assertEqual(TEXT, 'Consider `' + EXPRESSION + '` here.')
        self.assertEqual(result, runtime.normalize_finding_inline_code(result))

    def test_ordinary_unchanged(self):
        for text in ('Use `helper()` here.', '`&lt;/td&gt;`', 'ordinary prose'):
            self.assertEqual(text, runtime.normalize_finding_inline_code(text))

    def test_structural_boundaries(self):
        for markup in ('<details><summary>Example `</summary>`</details>',
                       TEXT + '<div>later</div>', '<!-- comment -->' + TEXT,
                       '<!DOCTYPE html>' + TEXT, '<?synthetic?>' + TEXT):
            self.assertEqual(markup, runtime.normalize_finding_inline_code(markup))


def provider():
    from pr_agent.git_providers.github_provider import GithubProvider
    instance = GithubProvider.__new__(GithubProvider)
    instance.pr = Mock()
    instance.issue_main = None
    instance.max_comment_chars = 65000
    instance.repo = 'synthetic/repo'
    instance.last_commit_id = SimpleNamespace(sha='a' * 40)
    instance.pr.head.sha = 'a' * 40
    instance.get_latest_commit_url = Mock(return_value='https://example.invalid/synthetic/repo/commit/' + 'a' * 40)
    records = {}
    def create(body):
        number = len(records) + 1
        records[number] = body
        return SimpleNamespace(id=number, body=body)
    instance.pr.create_issue_comment.side_effect = create
    instance.pr.get_issue_comment.side_effect = lambda number: SimpleNamespace(id=number, body=records[number])
    return instance


def snapshot():
    return {'schema_version': 1, 'last_run': {'head_sha': 'a' * 40, 'complete': True, 'kind': 'full'},
            'findings': [{'finding_id': 'fabricated-1', 'path': 'src/example.py', 'body': TEXT, 'state': 'ACTIVE'}]}


def publication(text=TEXT):
    import pr_agent.tools.pr_reviewer as reviewer
    runtime.install_hooks()
    source = data(text)
    before = copy.deepcopy(source)
    state = snapshot()
    rendered = reviewer.convert_to_markdown_v2(source)
    generated = reviewer.append_review_state(rendered, state)
    instance = provider()
    response = instance.publish_comment(generated)
    readback = instance.pr.get_issue_comment(response.id).body
    assert source == before
    assert instance.pr.create_issue_comment.call_count == 1
    # One runtime readback plus this independently requested test readback.
    assert instance.pr.get_issue_comment.call_count == 2
    return {'body': readback, 'head': 'a' * 40}


@unittest.skipUnless(os.environ.get('PR_AGENT_IMAGE_SMOKE') == '1', 'requires pinned image')
class ProducerTests(unittest.TestCase):
    def test_mixed_closing_tag(self):
        import pr_agent.tools.pr_reviewer as reviewer
        runtime.install_hooks()
        source = data()
        before = copy.deepcopy(source)
        rendered = reviewer.convert_to_markdown_v2(source)
        runtime.mask_review_code(rendered)
        self.assertIn('<code>', rendered)
        self.assertEqual(before, source)


if __name__ == '__main__':
    if sys.argv[1:] == ['--emit-record']:
        print(json.dumps(publication()))
    else:
        unittest.main()

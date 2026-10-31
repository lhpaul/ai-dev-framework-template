#!/usr/bin/env python3
"""Synthetic source-formatting and pinned producer publication regressions."""
import copy
import importlib.util
import os
import json
import re
import subprocess
from html.parser import HTMLParser
from types import ModuleType, SimpleNamespace
from unittest.mock import Mock, patch
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
        {'relevant_file': 'src/example.py', 'issue_header': header, 'issue_content': text,
         'category': 'blocking' if header.lower() == 'must fix' else 'advisory',
         'severity': 'high' if header.lower() == 'must fix' else 'medium'}]}}


FINDING_HEAD = '0' * 39 + '1'


def titled_review():
    """Fabricated two-finding shape; no copied consumer data."""
    findings = []
    details = []
    for index, title in enumerate(('Retry Loop', 'Unbounded Read')):
        line = 10 + index * 30
        findings.append({'issue_header': title, 'issue_content': 'A fabricated review finding.',
                         'category': 'advisory', 'severity': 'medium'})
        details.append(
            f"<details><summary><a href='https://example.invalid/repo/pull/42/files#diff-abcR{line}-R{line+10}'>"
            f'<strong>{title}</strong></a>\n\nA fabricated review finding.\n</summary>\n\n'
            '```typescript\nconst example = 1;\n```\n\n</details>')
    state = {'schema_version': 1, 'last_run': {}, 'findings': [
        {'body': '**' + f['issue_header'] + '**\n\nFabricated prose.',
         'finding_id': character * 12, 'path': 'src/' + character + '.ts',
         'line_start': 10 + index * 30, 'line_end': 20 + index * 30,
         'last_seen_head_sha': FINDING_HEAD, 'state': 'ACTIVE'}
        for index, (f, character) in enumerate(zip(findings, ('a', 'b')))]}
    body = ('## PR Reviewer Guide 🔍\n\n<!-- pr-agent:review:full -->\n\n'
            f'#### (Review updated until commit https://example.invalid/repo/commit/{FINDING_HEAD})\n\n'
            '<table>\n<tr><td>⏱️&nbsp;<strong>Estimated effort to review</strong>: 3</td></tr>\n'
            '<tr><td>🧪&nbsp;<strong>PR contains tests</strong></td></tr>\n'
            '<tr><td>🔒&nbsp;<strong>No security concerns identified</strong></td></tr>\n'
            '<tr><td>⚡&nbsp;<strong>Recommended focus areas for review</strong><br><br>\n\n'
            + '\n\n'.join(details) + '\n\n</td></tr>\n</table>\n\n'
            '<!-- pr-agent-review-state:v1\n' + json.dumps(state) + '\n-->')
    return body, {'review': {'key_issues_to_review': findings}}


class FindingMetadataTests(unittest.TestCase):
    def consumer(self, body, flag='--classify-pr-agent'):
        return subprocess.run(
            ['bash', str(ROOT / 'scripts/development-workflow/apply-readiness-labels.sh'), flag],
            input=body, text=True, capture_output=True, check=True).stdout.strip()

    def annotated(self):
        body, source = titled_review()
        before = copy.deepcopy(source)
        result = runtime.annotate_finding_metadata(body, source)
        self.assertEqual(before, source)
        self.assertIn('<strong data-pr-agent-finding="v1"', result)
        return result

    def test_legacy_free_titles_remain_ambiguous(self):
        body, _ = titled_review()
        self.assertEqual('escalate', self.consumer(body))

    def test_explicit_advisories_keep_visible_titles_and_excerpts(self):
        body = self.annotated()
        self.assertEqual('clean', self.consumer(body))
        self.assertEqual('Possible Issue\nPossible Issue', self.consumer(body, '--pr-agent-focus-labels'))
        self.assertEqual({'verdict': 'clean', 'verification_only': False},
                         json.loads(self.consumer(body, '--inspect-pr-agent')))
        self.assertIn('>Retry Loop</strong>', body)
        self.assertIn('>Unbounded Read</strong>', body)
        self.assertEqual(2, body.count('const example = 1;'))

    def test_markdown_boundaries_cannot_hide_extra_findings_inside_focus_cell(self):
        body = self.annotated()
        for boundary in ('### Additional finding', '---'):
            for closing in ('</summary>', '</details>', '</td>'):
                with self.subTest(boundary=boundary, closing=closing):
                    extra = '\n' + boundary + '\n**Must fix**\n'
                    if closing == '</td>':
                        # Add evidence to the focus cell, not an ancillary row.
                        candidate = body.replace('\n\n</td></tr>\n</table>', extra + '\n</td></tr>\n</table>')
                    else:
                        candidate = body.replace(closing, extra + closing, 1)
                    self.assertNotEqual(body, candidate)
                    self.assertEqual('escalate', self.consumer(candidate))
                    self.assertEqual('', self.consumer(candidate, '--pr-agent-focus-labels'))
                    self.assertEqual('escalate', json.loads(self.consumer(candidate, '--inspect-pr-agent'))['verdict'])
            with self.subTest(boundary=boundary, attribute='quoted cell terminator'):
                extra = '<span title="</td>">Descriptive prose.</span>\n' + boundary + '\n**Must fix**\n'
                self.assertEqual('escalate', self.consumer(body.replace('</details>', extra + '</details>', 1)))

    def test_markdown_boundaries_in_prose_or_code_do_not_invent_findings(self):
        body = self.annotated()
        for boundary in ('### Additional finding', '---'):
            prose = body.replace('</details>', '\n' + boundary + '\nDescriptive prose.\n</details>', 1)
            code = body.replace('const example = 1;', 'const example = 1;\n' + boundary + '\n**Must fix**', 1)
            for candidate in (prose, code):
                with self.subTest(boundary=boundary, candidate=candidate):
                    self.assertEqual('clean', self.consumer(candidate))

    def test_unmarked_html_emphasis_cannot_hide_extra_findings(self):
        body = self.annotated()
        for tag in ('b', 'em'):
            for closing in ('</summary>', '</details>', '</td>'):
                with self.subTest(tag=tag, closing=closing):
                    extra = f'<{tag}>Must fix</{tag}>'
                    if closing == '</td>':
                        candidate = body.replace('\n\n</td></tr>\n</table>', extra + '\n</td></tr>\n</table>')
                    else:
                        candidate = body.replace(closing, extra + closing, 1)
                    self.assertNotEqual(body, candidate)
                    self.assertEqual('escalate', self.consumer(candidate))
                    self.assertEqual('', self.consumer(candidate, '--pr-agent-focus-labels'))
                    self.assertEqual('escalate', json.loads(self.consumer(candidate, '--inspect-pr-agent'))['verdict'])

    def test_html_emphasis_in_code_or_comments_is_not_a_finding(self):
        body = self.annotated()
        for tag in ('b', 'em'):
            extra = f'<{tag}>Must fix</{tag}>'
            candidates = (
                body.replace('const example = 1;', 'const example = 1;\n' + extra, 1),
                body.replace('</details>', '<!-- ' + extra + ' --></details>', 1))
            for candidate in candidates:
                with self.subTest(tag=tag, candidate=candidate):
                    self.assertEqual('clean', self.consumer(candidate))

    def test_blocking_and_security_escalate(self):
        body = self.annotated()
        for candidate in (
                body.replace('data-category="advisory" data-severity="medium"',
                             'data-category="blocking" data-severity="high"', 1),
                body.replace('<strong>No security concerns identified</strong>',
                             '<strong>Security concerns</strong><br>Yes')):
            with self.subTest(candidate=candidate):
                self.assertEqual('escalate', self.consumer(candidate))

    def test_incomplete_invalid_and_contradictory_markers(self):
        body = self.annotated()
        for candidate in (
                body.replace('<table>', '').replace('</table>', ''),
                re.sub(r'^#### .*\n', '', body, flags=re.M),
                body.replace('data-category="advisory"', 'data-category="unknown"', 1),
                body.replace('data-severity="medium"', 'data-severity="high"', 1),
                body.replace('data-severity="medium"', '', 1),
                body.replace('data-pr-agent-finding="v1"', '', 1),
                body.replace('data-pr-agent-finding="v1"', 'data-pr-agent-finding="v2"', 1),
                body.replace(FINDING_HEAD + ')', FINDING_HEAD[:-1] + ')', 1),
                body.replace('</table>', '</table>\n<table></table>'),
                body.replace('data-category="advisory" data-severity="medium"', '', 1),
                body.replace('data-category="advisory"', 'data-category="advisory" data-category="blocking"', 1),
                body.replace('</details>', '', 1),
                body.replace('data-category="advisory"', 'data-category=""', 1),
                body.replace('data-severity="medium"', 'data-severity="   "', 1),
                body + '\n### Key issues to review\n**Must fix**\n',
                body.replace('</details>', '\n**Must fix**\n</details>', 1)):
            with self.subTest(candidate=candidate):
                self.assertEqual('escalate', self.consumer(candidate))
                self.assertEqual('', self.consumer(candidate, '--pr-agent-focus-labels'))

    def test_producer_never_guesses_metadata_from_title(self):
        body, source = titled_review()
        for field in ('category', 'severity'):
            for value in (None, '', ' ', 'unknown', [], {}, 1):
                candidate = copy.deepcopy(source)
                candidate['review']['key_issues_to_review'][0][field] = value
                self.assertEqual('escalate', self.consumer(runtime.annotate_finding_metadata(body, candidate)))
            candidate = copy.deepcopy(source)
            del candidate['review']['key_issues_to_review'][0][field]
            self.assertEqual('escalate', self.consumer(runtime.annotate_finding_metadata(body, candidate)))

    def test_prompt_schema_is_explicit_and_idempotent(self):
        source = 'class KeyIssuesComponentLink(BaseModel):\n    issue_header: str\n      issue_header: |\n'
        extended = runtime.finding_prompt_schema(source)
        self.assertIn('category: Literal["advisory", "blocking"]', extended)
        self.assertIn('severity: Literal["low", "medium", "high", "critical"]', extended)
        self.assertEqual(extended, runtime.finding_prompt_schema(extended))
        for invalid in ('', ' ', source + source):
            with self.assertRaises(RuntimeError):
                runtime.finding_prompt_schema(invalid)


class SourceTests(unittest.TestCase):
    def test_mixed_closing_tag(self):
        result = runtime.normalize_finding_inline_code(TEXT)
        self.assertEqual('Consider <code>re.split(r&quot;&lt;/td&gt;|^### &quot;, section)</code> here.', result)
        self.assertEqual(TEXT, 'Consider `' + EXPRESSION + '` here.')
        self.assertEqual(result, runtime.normalize_finding_inline_code(result))

    def test_ordinary_unchanged(self):
        for text in ('', ' \t\n', 'Use `helper()` here.', '`&lt;/td&gt;`', 'ordinary prose'):
            self.assertEqual(text, runtime.normalize_finding_inline_code(text))

    def test_structural_boundaries(self):
        for markup in ('<details><summary>Example `cross </summary> boundary`</details>',
                       TEXT + '<div>later</div>', '<!-- comment -->' + TEXT,
                       '<!DOCTYPE html>' + TEXT, '<?synthetic?>' + TEXT, TEXT + '<broken', TEXT + '<!'):
            self.assertEqual(markup, runtime.normalize_finding_inline_code(markup))

    def test_boundary_variants(self):
        class CodeText(HTMLParser):
            def __init__(self):
                super().__init__(convert_charrefs=True)
                self.text = []
            def handle_data(self, value):
                self.text.append(value)
        for payload in (EXPRESSION, 'f("</ CuStOm>", a & b)', "g('</x attr=\"v\">', '&lt;/td&gt;')"):
            with self.subTest(payload=payload):
                result = runtime.normalize_finding_inline_code('`' + payload + '`')
                parser = CodeText()
                parser.feed(result)
                self.assertEqual(payload, ''.join(parser.text))
                self.assertTrue(result.startswith('<code>'))
                self.assertEqual(result, runtime.normalize_finding_inline_code(result))

    def test_multiple_spans(self):
        text = '雪 `' + EXPRESSION + '` then `helper()` and `x("</Z>")`.'
        result = runtime.normalize_finding_inline_code(text)
        self.assertEqual(2, result.count('<code>'))
        self.assertIn(' then `helper()` and ', result)
        self.assertTrue(result.startswith('雪 '))

    def test_unsupported_delimiters(self):
        for text in ('\\`' + EXPRESSION + '`', '``' + EXPRESSION + '`',
                     '`' + EXPRESSION, '`first\n</td>`', '`</td>\\`',
                     '`ok` ``unsupported` `' + EXPRESSION + '`', '`</td>\u2028x`'):
            with self.subTest(text=text):
                self.assertEqual(text, runtime.normalize_finding_inline_code(text))

    def test_fence_boundaries(self):
        for opener, closer in (('```python', '````'), ('~~~', '~~~~')):
            fenced = opener + '\n`helper()`\n' + closer + '\n'
            result = runtime.normalize_finding_inline_code(fenced + TEXT)
            self.assertTrue(result.startswith(fenced))
            self.assertIn('<code>', result)
            raw_fenced = opener + '\n`</td>`\n' + closer + '\n' + TEXT
            self.assertEqual(raw_fenced, runtime.normalize_finding_inline_code(raw_fenced))
        self.assertEqual('```\n' + TEXT, runtime.normalize_finding_inline_code('```\n' + TEXT))
        double_fence = '````python\n``literal``\n`````\n'
        self.assertTrue(runtime.normalize_finding_inline_code(double_fence + TEXT).startswith(double_fence))

    def test_input_shapes(self):
        for source in (None, [], {}, {'review': None}, {'review': []},
                       {'review': {'key_issues_to_review': None}},
                       {'review': {'key_issues_to_review': [None, {}, {'issue_content': 1}]}}):
            before = copy.deepcopy(source)
            self.assertEqual(before, runtime.normalize_review_render_data(source))
            self.assertEqual(before, source)
        source = data()
        source['review']['security_concerns'] = TEXT
        source['review']['key_issues_to_review'][0]['issue_header'] = TEXT
        source['other'] = TEXT
        before = copy.deepcopy(source)
        result = runtime.normalize_review_render_data(source)
        self.assertEqual(before, source)
        self.assertEqual(TEXT, result['other'])
        self.assertEqual(TEXT, result['review']['security_concerns'])
        self.assertEqual(TEXT, result['review']['key_issues_to_review'][0]['issue_header'])
        self.assertIn('<code>', result['review']['key_issues_to_review'][0]['issue_content'])


    def test_double_backticks(self):
        for source, decoded in (
                ('``f("</node>")``', 'f("</node>")'),
                ('``  x("</node>")  ``', ' x("</node>") ')):
            with self.subTest(source=source):
                result = runtime.normalize_finding_inline_code(source)
                self.assertTrue(result.startswith('<code>'), result)
                from html import unescape
                self.assertEqual(decoded, unescape(result.removeprefix('<code>').removesuffix('</code>')))
        mixed = TEXT + ' beside `` `value` ``.'
        self.assertEqual(mixed, runtime.normalize_finding_inline_code(mixed))
        for source in ('``helper()``', '``complex``', '``   ``', '``a <node> b``'):
            self.assertEqual(source, runtime.normalize_finding_inline_code(source))
            body = '<table><tr><td><details><summary>Inspect ' + source + '</summary></details></td></tr></table>'
            masked = runtime.mask_review_code(body)
            self.assertEqual(len(body), len(masked))
            self.assertNotIn('`', masked)

    def test_mixed_width_runs_are_deferred_without_relaxing_simple_doubles(self):
        deferred = ('``git `<head>`:CHANGELOG.md``', '`` `value` ``',
                    '`` `f("</node>")` ``', '``before ` after``')
        for source in deferred:
            with self.subTest(source=source):
                self.assertEqual(source, runtime.normalize_finding_inline_code(source))
                for preserve in (True, False):
                    with self.assertRaises(ValueError):
                        runtime.mask_review_code(source, preserve_offsets=preserve)
        source = '``complex``'
        suffix = '\n\n<table><tr><td>Visible</td></tr></table>'
        self.assertEqual(' ' * len(source) + suffix, runtime.mask_review_code(source + suffix))
        self.assertEqual(' ' + suffix, runtime.mask_review_code(source + suffix, preserve_offsets=False))

    def test_double_negative_boundaries(self):
        for source in ('``unclosed', '``x`', '`x``', '``x```', '``two\nlines``',
                       '\\``escaped``', '``trailing\\``', '``first\u2028last``'):
            with self.subTest(source=source):
                self.assertEqual(source, runtime.normalize_finding_inline_code(source))
                with self.assertRaises(ValueError):
                    runtime.mask_review_code('<table><tr><td>' + source + '</td></tr></table>')
        for source in ('<details><summary>Example ``cross </summary> boundary``</details>',
                       '``f("</node>")`` <div>later</div>'):
            self.assertEqual(source, runtime.normalize_finding_inline_code(source))
            with self.assertRaises(ValueError):
                runtime.mask_review_code('<table><tr><td>' + source + '</td></tr></table>')
        for source in ('<div>``helper()``</div>', '<span title="``bad``">text</span>'):
            with self.assertRaises(ValueError):
                runtime.mask_review_code(source)


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


def snapshot(text=TEXT):
    return {'schema_version': 1, 'last_run': {'head_sha': 'a' * 40, 'complete': True, 'kind': 'full'},
            'findings': [{'finding_id': 'fabricated-1', 'path': 'src/example.py', 'body': text, 'state': 'ACTIVE'}]}


def publication(text=TEXT, header="Possible Issue", security="No", mode="fresh", extra_review=None):
    import pr_agent.tools.pr_reviewer as reviewer
    runtime.install_hooks()
    source = data(text, header, security)
    source["review"].update(extra_review or {})
    before = copy.deepcopy(source)
    state = snapshot(text)
    rendered = reviewer.convert_to_markdown_v2(source)
    generated = reviewer.append_review_state(rendered, state)
    instance = provider()
    old = Mock(body='a previous immutable review')
    if mode == 'edit':
        response = instance.edit_comment(old, generated)
    elif mode == 'persistent':
        response = instance.publish_persistent_comment_full(generated, initial_header='## PR Reviewer Guide')
    else:
        response = instance.publish_comment(generated)
    old.edit.assert_not_called()
    readback = instance.pr.get_issue_comment(response.id).body
    assert source == before
    assert instance.pr.create_issue_comment.call_count == 1
    # One runtime readback plus this independently requested test readback.
    assert instance.pr.get_issue_comment.call_count == 2
    import pr_agent.algo.review_finding_state as state_api
    assert state_api.parse_review_state(readback).state == state
    assert state == snapshot(text)
    return {'body': readback, 'head': 'a' * 40, 'creates': 1, 'readbacks': 2}


@unittest.skipUnless(os.environ.get('PR_AGENT_IMAGE_SMOKE') == '1', 'requires pinned image')
class ProducerTests(unittest.TestCase):
    def setUp(self):
        import pr_agent.algo.review_finding_state as state_api
        import pr_agent.algo.utils as utils
        import pr_agent.tools.pr_reviewer as reviewer
        from pr_agent.git_providers.github_provider import GithubProvider
        self.state_api, self.utils, self.reviewer = state_api, utils, reviewer
        self.provider_class = GithubProvider
        self.targets = [(state_api, 'append_review_state'), (reviewer, 'append_review_state'),
                        (utils, 'convert_to_markdown_v2'), (reviewer, 'convert_to_markdown_v2'),
                        (reviewer, 'PRReview')]
        self.targets += [(GithubProvider, name) for name in ('limit_output_characters', 'publish_comment',
                         'edit_comment', 'publish_persistent_comment_full')]
        self.originals = [(obj, name, getattr(obj, name)) for obj, name in self.targets]
        self.addCleanup(self.restore_hooks)

    def restore_hooks(self):
        for obj, name, original in self.originals:
            setattr(obj, name, original)
        if hasattr(self.provider_class, '_workflow_immutable_review_hook'):
            del self.provider_class._workflow_immutable_review_hook

    def generated(self, text=TEXT, header='Possible Issue', security='No', with_state=True):
        runtime.install_hooks()
        source = data(text, header, security)
        before = copy.deepcopy(source)
        state = snapshot(text)
        state_before = copy.deepcopy(state)
        body = self.reviewer.convert_to_markdown_v2(source)
        if with_state:
            body = self.reviewer.append_review_state(body, state)
            parsed = self.state_api.parse_review_state(body)
            self.assertTrue(parsed.valid)
            self.assertEqual(state, parsed.state)
        self.assertEqual(before, source)
        self.assertEqual(state_before, state)
        return body

    def test_publication_consumers(self):
        for text in (TEXT, 'Consider `helper()` here.', 'Inspect ``f("</node>")`` and ``helper()``.'):
            generated = self.generated(text)
            for mode in ('fresh', 'edit', 'persistent'):
                with self.subTest(text=text, mode=mode):
                    instance = provider()
                    old = Mock(body='a previous immutable review')
                    if mode == 'fresh':
                        response = instance.publish_comment(generated)
                    elif mode == 'edit':
                        response = instance.edit_comment(old, generated)
                    else:
                        response = instance.publish_persistent_comment_full(generated, initial_header='## PR Reviewer Guide')
                    instance.pr.create_issue_comment.assert_called_once()
                    instance.pr.get_issue_comment.assert_called_once_with(response.id)
                    old.edit.assert_not_called()
                    outbound = instance.pr.create_issue_comment.call_args.args[0]
                    self.assertEqual(outbound, instance.pr.get_issue_comment(response.id).body)
                    self.assertEqual(snapshot(text), self.state_api.parse_review_state(outbound).state)
                    self.assertIn('Possible Issue', outbound)
                    runtime.mask_review_code(outbound)
                    self.assertIn('`helper()`' if text == 'Consider `helper()` here.' else '<code>', outbound)

    def test_free_title_metadata_reaches_published_record(self):
        record = publication('A fabricated finding with `helper()`.', header='Retry Loop')
        body = record['body']
        self.assertIn('data-category="advisory" data-severity="medium">Retry Loop</strong>', body)
        self.assertEqual('clean', FindingMetadataTests().consumer(body))
        from pr_agent.config_loader import get_settings
        self.assertIn('category: Literal["advisory", "blocking"]', get_settings().pr_review_prompt.system)

    def test_schema_reaches_reviewer_after_synthetic_repo_settings(self):
        from pr_agent.config_loader import get_settings
        import pr_agent.git_providers.utils as provider_utils
        runtime.install_hooks()
        settings = get_settings()
        previous = settings.pr_reviewer.extra_instructions
        self.addCleanup(settings.set, 'pr_reviewer.extra_instructions', previous)
        instance = Mock()
        instance.get_repo_settings.return_value = b'[pr_reviewer]\nextra_instructions = "Fabricated repository guidance"\n'
        with patch.object(provider_utils, 'get_git_provider_with_context', return_value=instance), \
                patch.object(provider_utils, '_get_per_directory_settings', return_value=[]):
            provider_utils.apply_repo_settings('https://example.invalid/repo/pull/42')
        self.assertEqual('Fabricated repository guidance', settings.pr_reviewer.extra_instructions)
        instance.get_pr_description.return_value = ('Synthetic description', [])
        with patch.object(self.reviewer, 'get_git_provider_with_context', return_value=instance), \
                patch.object(self.reviewer, 'get_main_pr_language', return_value='Python'), \
                patch.object(self.reviewer, 'get_skills_context', return_value=''), \
                patch.object(self.reviewer, 'build_repo_context', return_value=''), \
                patch.object(self.reviewer.PRReviewer, '_get_user_answers', return_value=('', '')), \
                patch.object(self.reviewer, 'TokenHandler') as tokens:
            self.reviewer.PRReviewer('https://example.invalid/repo/pull/42', ai_handler=Mock)
        prompt = tokens.call_args.args[2]
        self.assertIn('category: Literal["advisory", "blocking"]', prompt)
        self.assertIn('severity: Literal["low", "medium", "high", "critical"]', prompt)

    def test_actual_output_schema_accepts_explicit_fields_and_rejects_bad_data(self):
        source = data('Synthetic finding.', 'Retry Loop')
        source['review']['key_issues_to_review'][0].update(start_line=10, end_line=20)
        instance = self.reviewer.PRReviewer.__new__(self.reviewer.PRReviewer)
        instance.vars = {}
        # Planted producer failure: upstream extra="forbid" rejects these fields.
        self.assertFalse(instance._validate_review_schema(source))
        runtime.install_hooks()
        self.assertTrue(instance._validate_review_schema(source))
        for field in ('category', 'severity', 'relevant_file', 'start_line'):
            invalid = copy.deepcopy(source)
            del invalid['review']['key_issues_to_review'][0][field]
            self.assertFalse(instance._validate_review_schema(invalid))
        for field, value in (('category', 'unknown'), ('severity', 'unknown'),
                             ('unexpected_field', 'fabricated')):
            invalid = copy.deepcopy(source)
            invalid['review']['key_issues_to_review'][0][field] = value
            self.assertFalse(instance._validate_review_schema(invalid))

    def test_mixed_width_publication_remains_blocking(self):
        for mode in ('fresh', 'edit', 'persistent'):
            with self.subTest(mode=mode):
                record = publication('Inspect `` `f("</node>")` ``.', mode=mode)
                with self.assertRaises(ValueError):
                    runtime.mask_review_code(record['body'])

    def test_structural_boundaries(self):
        negatives = ('<details><summary>Example `cross </summary> boundary`</details>',
                     TEXT + '<details><summary>Example `cross </summary> boundary`</details>')
        for text in negatives:
            source = data(text)
            copied = runtime.normalize_review_render_data(source)
            self.assertEqual(text, copied['review']['key_issues_to_review'][0]['issue_content'])
            rendered = self.generated(text)
            self.assertIn(text, rendered)
            with self.assertRaises(ValueError):
                runtime.mask_review_code(rendered)
        composed = '<table><tr><td><details><summary>Example `cross </summary> boundary`</details></td></tr></table>'
        with self.assertRaises(ValueError):
            runtime.mask_review_code(composed)
        runtime.mask_review_code(self.generated())

    def test_input_shapes_and_non_gfm(self):
        original = self.utils.convert_to_markdown_v2
        source = data()
        expected = original(source, False, 'synthetic incremental', None, [])
        runtime.install_hooks()
        self.assertEqual(expected, self.reviewer.convert_to_markdown_v2(source, False, 'synthetic incremental', None, []))
        for malformed in ({}, {'review': {}}, {'review': {'key_issues_to_review': [None, {'issue_content': 1}]}}):
            observed = self.reviewer.convert_to_markdown_v2(malformed)
            if observed != original(malformed):
                self.assertIn('Verification: required', observed)
                self.assertEqual('escalate', FindingMetadataTests().consumer(observed))
            else:
                self.assertEqual(original(malformed), observed)

    def test_identity_failures_before_create(self):
        body = self.generated()
        for mode in ('missing', 'wrong_sha', 'wrong_url', 'stale_state', 'live_drift', 'malformed', 'duplicate', 'unknown'):
            with self.subTest(mode=mode):
                instance = provider()
                candidate = body
                if mode == 'missing':
                    instance.last_commit_id.sha = None
                elif mode == 'wrong_sha':
                    instance.last_commit_id.sha = 'invalid-sha'
                elif mode == 'wrong_url':
                    instance.get_latest_commit_url.return_value = 'https://example.invalid/synthetic/repo/commit/' + 'b' * 40
                elif mode == 'stale_state':
                    candidate = body.replace('"head_sha":"' + 'a' * 40, '"head_sha":"' + 'b' * 40)
                    self.assertNotEqual(candidate, body)
                elif mode == 'live_drift':
                    instance.pr.head.sha = 'b' * 40
                elif mode == 'malformed':
                    candidate += '\n<!-- pr-agent-review-state:v1 broken -->'
                elif mode == 'duplicate':
                    candidate += self.state_api.serialize_review_state(snapshot())
                else:
                    candidate = body.replace('pr-agent-review-state:v1', 'pr-agent-review-state:v99')
                with self.assertRaises(RuntimeError):
                    instance.publish_comment(candidate)
                instance.pr.create_issue_comment.assert_not_called()
        # Missing state is currently accepted; formatting must not invent a new requirement.
        missing_state = self.generated(with_state=False)
        instance = provider()
        instance.publish_comment(missing_state)
        instance.pr.create_issue_comment.assert_called_once()

    def test_readback_and_uncertain_write(self):
        body = self.generated()
        for mode in ('body', 'id', 'write_exception'):
            instance = provider()
            if mode == 'body':
                instance.pr.get_issue_comment.side_effect = lambda number: SimpleNamespace(id=number, body='different')
            elif mode == 'id':
                instance.pr.get_issue_comment.side_effect = lambda number: SimpleNamespace(id=number + 1, body=body)
            else:
                instance.pr.create_issue_comment.side_effect = RuntimeError('fabricated uncertain write')
            with self.assertRaises(RuntimeError):
                instance.publish_comment(body)
            instance.pr.create_issue_comment.assert_called_once()
            instance.pr.edit_issue_comment.assert_not_called()

    def test_limits(self):
        body = self.generated()
        instance = provider()
        bound = runtime.bind_review_record(instance, body, self.state_api, ('## PR Reviewer Guide',))
        instance.max_comment_chars = len(bound)
        instance.publish_comment(body)
        self.assertEqual(bound, instance.pr.create_issue_comment.call_args.args[0])
        # The formatted visible payload, not the shorter source, counts toward fitting.
        raw = self.originals[2][2](data())
        normalized = self.reviewer.convert_to_markdown_v2(data())
        self.assertGreater(len(normalized), len(raw))
        expansion_limit = len(bound) - (len(normalized) - len(raw))
        instance = provider()
        instance.max_comment_chars = expansion_limit
        instance.publish_comment(body)
        expanded_outbound = instance.pr.create_issue_comment.call_args.args[0]
        self.assertLessEqual(len(expanded_outbound), expansion_limit)
        self.assertIn('<code>', expanded_outbound)
        self.assertIsNone(self.state_api.parse_review_state(expanded_outbound).state)
        large = self.generated(' '.join([TEXT] * 100))
        instance = provider()
        instance.max_comment_chars = 1500
        instance.publish_comment(large)
        outbound = instance.pr.create_issue_comment.call_args.args[0]
        self.assertLessEqual(len(outbound), 1500)
        self.assertNotIn('<code>', outbound)
        self.assertIn('verification', outbound.lower())

    def test_incompatible_renderer_before_partial_install(self):
        # Planted signature violation: the renderer is no longer compatible.
        def incompatible(output_data):
            return ''
        for obj in (self.utils, self.reviewer):
            obj.convert_to_markdown_v2 = incompatible
        with self.assertRaisesRegex(RuntimeError, 'incompatible'):
            runtime.install_hooks()
        self.assert_unpatched()
        self.restore_hooks()
        runtime.install_hooks()
        self.assertIs(self.utils.convert_to_markdown_v2, self.reviewer.convert_to_markdown_v2)

    def test_mismatched_renderer_alias_before_partial_install(self):
        # Planted alias violation: same signature but a distinct callable.
        def other(output_data, gfm_supported=True, incremental_review=None, git_provider=None, files=None):
            return ''
        self.reviewer.convert_to_markdown_v2 = other
        with self.assertRaisesRegex(RuntimeError, 'renderer alias'):
            runtime.install_hooks()
        self.assert_unpatched()
        self.restore_hooks()
        runtime.install_hooks()
        self.assertIs(self.utils.convert_to_markdown_v2, self.reviewer.convert_to_markdown_v2)

    def assert_unpatched(self):
        self.assertFalse(hasattr(self.provider_class, '_workflow_immutable_review_hook'))
        for obj, name, original in self.originals:
            if name != 'convert_to_markdown_v2':
                self.assertIs(original, getattr(obj, name))

    def test_idempotence_and_non_review_delegation(self):
        # Install over explicit non-review delegates to prove argument preservation.
        calls = []
        def publish(self, pr_comment, is_temporary=False):
            calls.append((pr_comment, is_temporary))
            return 'delegated'
        with patch.object(self.provider_class, 'publish_comment', publish):
            runtime.install_hooks()
            renderer = self.utils.convert_to_markdown_v2
            runtime.install_hooks()
            self.assertIs(renderer, self.utils.convert_to_markdown_v2)
            instance = provider()
            self.assertEqual('delegated', instance.publish_comment('ordinary bot comment', True))
            self.assertEqual([('ordinary bot comment', True)], calls)


def emit_records():
    import pr_agent.tools.pr_reviewer as reviewer
    records = []
    for text in (TEXT, 'Consider `helper()` here.', 'Inspect ``f("</node>")`` and ``helper()``.'):
        for mode in ('fresh', 'edit', 'persistent'):
            records.append(dict(publication(text, mode=mode), name=mode + text, verdict='clean', verification_only=False,
                                focus='Possible Issue', d15=True))
    for name, header, security, verdict, verification in (
            ('security', 'Possible Issue', 'Yes', 'escalate', False),
            ('verification', 'Possible Issue', 'No', 'clean', False),
            ('hard-focus', 'Must fix', 'No', 'escalate', False)):
        extra = {}
        if name == 'verification':
            extra['ticket_compliance_check'] = [{
                'ticket_url': 'https://example.invalid/issues/fabricated',
                'requires_further_human_verification': '- Confirm the fabricated acceptance scenario.'}]
        record = publication(header=header, security=security, extra_review=extra)
        records.append(dict(record, name=name, verdict=verdict, verification_only=verification,
                            focus='' if name == 'hard-focus' else header, d15=True))
        if name == 'verification':
            for suffix in ('\n### Verification status: pending\n',
                           '\n### Requires further human verification\n- Confirm code evidence.\n'):
                records.append({'name': 'independent-verification-' + suffix,
                                'body': record['body'] + suffix, 'verdict': 'escalate',
                                'verification_only': False, 'd15': False})
    for text in ('<details><summary>Example `cross </summary> boundary`</details>',
                 TEXT + '<details><summary>Example `cross </summary> boundary`</details>'):
        records.append({'name': 'renderer-source-negative', 'body': reviewer.convert_to_markdown_v2(data(text)),
                        'verdict': 'escalate', 'verification_only': False, 'd15': False})
    records.append({'name': 'composed-negative', 'body': '## PR Reviewer Guide 🔍\n<table><tr><td><details><summary>Example `cross </summary> boundary`</details></td></tr></table>',
                    'verdict': 'escalate', 'verification_only': False, 'd15': False})
    for text in ('<details><summary>Example ``cross </summary> boundary``</details>',
                 '``f("</node>")`` <div>later</div>', '``unclosed', '``x`', '`x``',
                 '``x```', '``two\nlines``', '\\``escaped``', '``trailing\\``',
                 '``git `<head>`:CHANGELOG.md``', '`` `f("</node>")` ``'):
        copied = runtime.normalize_review_render_data(data(text))
        assert copied['review']['key_issues_to_review'][0]['issue_content'] == text
        records.append({'name': 'double-renderer-negative', 'body': reviewer.convert_to_markdown_v2(data(text)),
                        'verdict': 'escalate', 'verification_only': False, 'd15': False})
    records.append({'name': 'double-quoted-verdict-negative',
                    'body': '## PR Reviewer Guide 🔍\n\n``No major issues detected``',
                    'verdict': 'escalate', 'verification_only': False, 'd15': False})
    print(json.dumps(records))


def emit_bootstrap_records():
    # Separate process: only this untouched public predecessor installs hooks.
    global runtime
    predecessor = ModuleType('bootstrap_predecessor')
    sys.modules[predecessor.__name__] = predecessor
    source = sys.stdin.read()
    assert source.startswith('#!/usr/bin/env python3')
    exec(compile(source, 'public-bootstrap-predecessor.py', 'exec'), predecessor.__dict__)
    runtime = predecessor
    text = 'Inspect ``widget`` and ``a <node> b`` and ``   ``.'
    records = []
    for mode in ('fresh', 'edit', 'persistent'):
        record = publication(text, mode=mode)
        assert text in record['body']  # The old producer did not normalize it.
        try:
            predecessor.mask_review_code(record['body'])
        except ValueError as error:
            assert str(error) == 'unsupported inline delimiter'
        else:
            raise AssertionError('predecessor unexpectedly accepts the bootstrap fixture')
        records.append(dict(record, name='bootstrap-' + mode, verdict='clean', verification_only=False,
                            focus='Possible Issue', d15=True))
    for name, header, security, verdict, verification in (
            ('security', 'Possible Issue', 'Yes', 'needs_fixes', False),
            ('verification', 'Possible Issue', 'No', 'clean', False),
            ('hard-focus', 'Must fix', 'No', 'needs_fixes', False)):
        extra = {}
        if name == 'verification':
            extra['ticket_compliance_check'] = [{
                'ticket_url': 'https://example.invalid/issues/fabricated',
                'requires_further_human_verification': '- Confirm the fabricated acceptance scenario.'}]
        record = publication(text, header=header, security=security, extra_review=extra)
        records.append(dict(record, name='bootstrap-' + name, verdict=verdict, verification_only=verification,
                            focus=header, d15=True))
        if name == 'verification':
            for suffix in ('\n### Verification status: pending\n',
                           '\n### Requires further human verification\n- Confirm code evidence.\n'):
                records.append({'name': 'bootstrap-independent-verification-' + suffix,
                                'body': record['body'] + suffix, 'verdict': 'escalate',
                                'verification_only': False, 'd15': False})
    import pr_agent.tools.pr_reviewer as reviewer
    import pr_agent.algo.review_finding_state as state_api
    history = snapshot(text)
    history['findings'].append({'finding_id': 'fabricated-resolved', 'path': 'src/example.py',
                                'body': 'Read ``archived``.', 'state': 'RESOLVED'})
    generated = reviewer.append_review_state(reviewer.convert_to_markdown_v2(data(text)), history)
    instance = provider()
    response = instance.publish_comment(generated)
    history_readback = instance.pr.get_issue_comment(response.id).body
    assert state_api.parse_review_state(history_readback).state == history
    records.append({'name': 'bootstrap-resolved-history', 'body': history_readback, 'head': 'a' * 40,
                    'creates': 1, 'readbacks': 2, 'verdict': 'clean', 'verification_only': False,
                    'focus': 'Possible Issue', 'd15': True})
    # Existing publication identity failures stay pre-create failures in the old runtime.
    instance = provider()
    instance.last_commit_id.sha = None
    try:
        instance.publish_comment(generated)
    except RuntimeError:
        assert instance.pr.create_issue_comment.call_count == 0
    else:
        raise AssertionError('predecessor published without reviewed identity')
    # The predecessor body stays immutable; mixed-width code remains unsupported.
    mixed = publication('Inspect `` `widget` `` and ``a <node> b``.')
    records.append(dict(mixed, name='bootstrap-mixed-width-negative', verdict='escalate',
                        verification_only=False, d15=True))
    # Do not allow an old-producer cross-boundary span merely because doubles are recognized.
    negative = '<details><summary>Example ``cross </summary> boundary``</details>'
    records.append({'name': 'bootstrap-structural-negative', 'body': reviewer.convert_to_markdown_v2(data(negative)),
                    'verdict': 'escalate', 'verification_only': False, 'd15': False})
    # Old publication fitting diagnostics are not a successful bootstrap result.
    generated = reviewer.append_review_state(reviewer.convert_to_markdown_v2(data(text * 100)), snapshot(text * 100))
    instance = provider()
    instance.max_comment_chars = 1500
    response = instance.publish_comment(generated)
    diagnostic = instance.pr.get_issue_comment(response.id).body
    assert len(diagnostic) <= 1500 and 'verification' in diagnostic.lower()
    records.append({'name': 'bootstrap-limit-diagnostic', 'body': diagnostic,
                    'verdict': 'escalate', 'verification_only': False, 'd15': False})
    print(json.dumps(records))


def probe_compatibility(mode):
    """Disposable-process proof: planted violations must exit nonzero."""
    import pr_agent.algo.utils as utils
    import pr_agent.tools.pr_reviewer as reviewer
    if mode == 'signature':
        def incompatible(output_data):
            return ''
        utils.convert_to_markdown_v2 = reviewer.convert_to_markdown_v2 = incompatible
    elif mode == 'alias':
        def other(output_data, gfm_supported=True, incremental_review=None, git_provider=None, files=None):
            return ''
        reviewer.convert_to_markdown_v2 = other
    elif mode != 'compatible':
        raise ValueError('unknown compatibility probe')
    runtime.install_hooks()
    print('PASS: compatible renderer installed')


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--probe-compatibility':
        probe_compatibility(sys.argv[2])
    elif sys.argv[1:] == ['--emit-bootstrap-records']:
        emit_bootstrap_records()
    elif sys.argv[1:] == ['--emit-records']:
        emit_records()
    else:
        unittest.main()

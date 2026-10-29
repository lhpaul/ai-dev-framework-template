#!/usr/bin/env python3
"""Synthetic source-formatting and pinned producer publication regressions."""
import copy
import importlib.util
import os
import json
from html import unescape
from html.parser import HTMLParser
from types import SimpleNamespace
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
        for markup in ('<details><summary>Example `cross </summary> boundary`</details>',
                       TEXT + '<div>later</div>', '<!-- comment -->' + TEXT,
                       '<!DOCTYPE html>' + TEXT, '<?synthetic?>' + TEXT):
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
        for text in ('\\`' + EXPRESSION + '`', '``' + EXPRESSION + '``',
                     '`' + EXPRESSION, '`first\n</td>`', '`</td>\\`',
                     '`ok` ``unsupported`` `' + EXPRESSION + '`', '`</td>\u2028x`'):
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


def publication(text=TEXT, header="Possible Issue", security="No", mode="fresh", extra_review=None):
    import pr_agent.tools.pr_reviewer as reviewer
    runtime.install_hooks()
    source = data(text, header, security)
    source["review"].update(extra_review or {})
    before = copy.deepcopy(source)
    state = snapshot()
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
    assert state == snapshot()
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
                        (utils, 'convert_to_markdown_v2'), (reviewer, 'convert_to_markdown_v2')]
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
        state = snapshot()
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
        for text in (TEXT, 'Consider `helper()` here.'):
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
                    self.assertEqual(snapshot(), self.state_api.parse_review_state(outbound).state)
                    self.assertIn('Possible Issue', outbound)
                    runtime.mask_review_code(outbound)
                    self.assertIn('<code>' if text == TEXT else '`helper()`', outbound)

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
            self.assertEqual(original(malformed), self.reviewer.convert_to_markdown_v2(malformed))

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
    for text in (TEXT, 'Consider `helper()` here.'):
        for mode in ('fresh', 'edit', 'persistent'):
            records.append(dict(publication(text, mode=mode), name=mode + text, verdict='clean', verification_only=False,
                                focus='Possible Issue', d15=True))
    for name, header, security, verdict, verification in (
            ('security', 'Possible Issue', 'Yes', 'needs_fixes', False),
            ('verification', 'Possible Issue', 'No', 'escalate', True),
            ('hard-focus', 'Must fix', 'No', 'needs_fixes', False)):
        extra = {}
        if name == 'verification':
            extra['ticket_compliance_check'] = [{
                'ticket_url': 'https://example.invalid/issues/fabricated',
                'requires_further_human_verification': '- Confirm the fabricated acceptance scenario.'}]
        record = publication(header=header, security=security, extra_review=extra)
        records.append(dict(record, name=name, verdict=verdict, verification_only=verification, focus=header, d15=True))
    for text in ('<details><summary>Example `cross </summary> boundary`</details>',
                 TEXT + '<details><summary>Example `cross </summary> boundary`</details>'):
        records.append({'name': 'renderer-source-negative', 'body': reviewer.convert_to_markdown_v2(data(text)),
                        'verdict': 'escalate', 'verification_only': False, 'd15': False})
    records.append({'name': 'composed-negative', 'body': '## PR Reviewer Guide 🔍\n<table><tr><td><details><summary>Example `cross </summary> boundary`</details></td></tr></table>',
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
    elif sys.argv[1:] == ['--emit-records']:
        emit_records()
    else:
        unittest.main()

#!/usr/bin/env python3
"""Fit final PR-Agent reviews before GitHub publication; no live work on import."""

import argparse
from dataclasses import dataclass, field
from html import unescape
from html.parser import HTMLParser
import inspect
import logging
from pathlib import Path
import re
import runpy
import sys


IMAGE = "pragent/pr-agent@sha256:31b9aac6ab067bada9a0c1b001d30ebc500ea4487e00a93c18c59b9ef5fa66db"
RUNNER = "/app/pr_agent/servers/github_action_runner.py"
LOGGER = logging.getLogger("pr_agent_publication")
VOID_TAGS = {"br", "hr", "img", "wbr", "input", "meta", "link"}
STATUS_WORDS = re.compile(
    r"summary|verdict|security|compliance|verification|risk|merge|approval|"
    r"block(?:ing|er|ed)?|requires?\s+(?:fix|human)|needs?\s+fix|unknown|pending|"
    r"must\s+fix|critical|breaking\s+change|api\s+change|backward\s+compatibility",
    re.I,
)


@dataclass
class Span:
    tag: str
    start: int
    open_end: int
    close_start: int = 0
    end: int = 0
    parent: object = None
    children: list = field(default_factory=list)
    attrs: tuple = ()


def fence_spans(source):
    """Locate complete producer code fences; all surrounding prose is protected."""
    fence = None
    offset = 0
    start = 0
    spans = []
    for line in source.splitlines(keepends=True):
        match = re.match(r"^[ \t]*(`{3,}|~{3,})", line)
        if fence is None and match:
            fence = match.group(1)
            start = offset
        elif fence is not None:
            if (match and match.group(1)[0] == fence[0]
                    and len(match.group(1)) >= len(fence)
                    and not line[match.end():].rstrip("\r\n").strip(" \t")):
                spans.append((start, offset + len(line)))
                fence = None
        offset += len(line)
    if fence is not None:
        raise ValueError("unclosed source fence")
    return spans


def mask_fences(source):
    """Ignore source-example tags while retaining exact source offsets."""
    for start, end in reversed(fence_spans(source)):
        source = source[:start] + re.sub(r"[^\r\n]", " ", source[start:end]) + source[end:]
    return source


def has_status_evidence(source):
    # Unknown emphasis may carry a classifier heading or label. Protect it too.
    return (STATUS_WORDS.search(plain_text(source))
            or re.search(r"\*\*|__|<(?:strong|b|em)\b", source, re.I))


class ReviewSpans(HTMLParser):
    """Collect balanced producer HTML spans; never regenerate review text."""

    def __init__(self, source):
        super().__init__(convert_charrefs=False)
        self.source = source
        self.offsets = [0]
        for match in re.finditer("\n", source):
            self.offsets.append(match.end())
        self.stack = []
        self.nodes = []
        self.feed(mask_fences(source))
        self.close()
        if self.stack:
            raise ValueError("unbalanced review markup")

    def position(self):
        line, column = self.getpos()
        return self.offsets[line - 1] + column

    def handle_starttag(self, tag, attrs):
        start = self.position()
        node = Span(tag, start, start + len(self.get_starttag_text()))
        node.attrs = tuple(attrs)
        if self.stack:
            node.parent = self.stack[-1]
            node.parent.children.append(node)
        self.nodes.append(node)
        if tag in VOID_TAGS:
            node.close_start = node.end = node.open_end
        else:
            self.stack.append(node)

    def handle_startendtag(self, tag, attrs):
        if tag not in VOID_TAGS:
            raise ValueError("unexpected self-closing review tag")
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        if not self.stack or self.stack[-1].tag != tag:
            raise ValueError("mismatched review tag")
        node = self.stack.pop()
        node.close_start = self.position()
        end = self.source.find(">", node.close_start)
        if end < 0:
            raise ValueError("unclosed review tag")
        node.end = end + 1


def plain_text(source):
    return " ".join(unescape(re.sub(r"<[^>]*>", " ", source)).split())


def remove_spans(source, spans):
    for start, end in sorted(spans, reverse=True):
        source = source[:start] + source[end:]
    return source


def ancillary_candidates(source):
    """Ordered, conservative removals for the pinned renderer's GFM layout."""
    parsed = ReviewSpans(source)
    tables = [n for n in parsed.nodes if n.tag == "table" and n.parent is None]
    if len(tables) != 1:
        raise ValueError("unsupported review table layout")
    table = tables[0]
    if any(n.tag == "table" and n is not table for n in parsed.nodes):
        raise ValueError("nested review table")
    rows = [n for n in table.children if n.tag == "tr"]
    if not rows or len(rows) != len(table.children):
        raise ValueError("unsupported review rows")
    trailers, excerpts, metadata = [], [], []
    for node in parsed.nodes:
        if node.tag == "details" and node.parent is None and node.start > table.end:
            summaries = [n for n in node.children if n.tag == "summary"]
            if (len(summaries) == 1 and node.children[0] is summaries[0]
                    and plain_text(source[summaries[0].open_end:summaries[0].close_start])
                    == "💡 Tool usage guide:"
                    and not has_status_evidence(source[summaries[0].end:node.close_start])):
                trailers.append((node.start, node.end))
    for row in rows:
        if len(row.children) != 1 or row.children[0].tag != "td":
            raise ValueError("unsupported review cell")
        cell = row.children[0]
        labels = [n for n in cell.children if n.tag == "strong"]
        if not labels:
            continue  # Unknown rows are protected, never inferred as ancillary.
        label = plain_text(source[labels[0].open_end:labels[0].close_start])
        descendants = [n for n in parsed.nodes if row.start < n.start < row.end]
        if label == "Recommended focus areas for review":
            for detail in [n for n in cell.children if n.tag == "details"]:
                summaries = [n for n in detail.children if n.tag == "summary"]
                if len(summaries) != 1 or detail.children[0] is not summaries[0]:
                    raise ValueError("unsupported finding summary layout")
                summary = summaries[0]
                # Other detail/summary nodes after the issue summary are ambiguous.
                if any(n.tag in {"summary", "details"} and summary.end <= n.start < detail.close_start
                       for n in descendants):
                    raise ValueError("ambiguous source excerpt")
                # Only the producer's fenced source is ancillary. Never remove
                # unfenced text, irrespective of its HTML/Markdown status syntax.
                excerpt = source[summary.end:detail.close_start]
                excerpts.extend((summary.end + start, summary.end + end)
                                for start, end in fence_spans(excerpt))
        safe_labels = {"Estimated effort to review", "No relevant tests", "PR contains tests",
                       "Contribution time estimate", "Priority files"}
        if (label not in safe_labels or sum(n.tag == "strong" for n in descendants) != 1
                or has_status_evidence(source[labels[0].end:cell.close_start])):
            continue
        tags = {n.tag for n in descendants}
        if (not tags <= {"td", "strong", "br", "ul", "li"}
                or row.attrs or any(n.attrs for n in descendants)):
            continue
        tail = plain_text(source[labels[0].end:cell.close_start])
        if label == "Estimated effort to review" and not re.fullmatch(r":\s*[1-5]\s*[🔵⚪]{5}", tail):
            continue
        if label in {"No relevant tests", "PR contains tests"} and tail:
            continue
        if label == "Contribution time estimate" and not re.fullmatch(
                r"\(best, average, worst case\):\s*[\d.]+\s*(?:minutes?|hours?)\s*\|\s*"
                r"[\d.]+\s*(?:minutes?|hours?)\s*\|\s*[\d.]+\s*(?:minutes?|hours?)", tail):
            continue
        metadata.append((row.start, row.end))
    return trailers, excerpts, metadata


def notice(body, limit, visible_reduced):
    messages = (
        "\n\n> Review history/ancillary content omitted to preserve the current summary and verdict."
        if visible_reduced else "\n\n> Review history omitted to preserve the current summary and verdict.",
        "\n\n> Content omitted." if visible_reduced else "\n\n> History omitted.",
    )
    for message in messages:
        if len(body) + len(message) <= limit:
            return body + message
    return body


def diagnostic(body, limit, headers):
    message = "\n\nVerification: required\nReview content exceeded the publication limit or was unsafe. Manual review required."
    metadata = []
    for line in body.splitlines():
        if (any(line.startswith(header) for header in headers)
                or re.fullmatch(r"<!-- pr-agent:review:(?:full|incremental) -->", line)
                or re.fullmatch(r"#### \(Review updated until commit https://[^\s)]+\)", line)):
            metadata.append(line)
    prefix = "\n\n".join(metadata)
    if len(prefix + message) <= limit:
        return prefix + message
    if len(message) <= limit:
        return message
    short = "Verification: required"
    return short if len(short) <= limit else "?"


def fit_review(body, limit, state_api, headers):
    if isinstance(limit, bool) or not isinstance(limit, int) or limit <= 0:
        raise ValueError("publication limit must be a positive integer")
    if len(body) <= limit:
        return body
    reason = "history"
    parsed = state_api.parse_review_state(body)
    if not parsed.valid:
        result = diagnostic(body, limit, headers)
        reason = "unsafe_state"
    else:
        visible, marker = state_api.split_review_state_marker(body)
        current = visible
        if parsed.state is not None:
            resolved = state_api._render_resolved_section(parsed.state)
            if resolved and current.endswith("\n\n" + resolved):
                current = current[:-(len(resolved) + 2)]
        with_marker = current + ("\n\n" + marker + "\n" if marker else "")
        if len(with_marker) <= limit:
            result = notice(with_marker, limit, False)
        elif len(current) <= limit:
            result = notice(current, limit, False)
        else:
            try:
                groups = ancillary_candidates(current)
                spans = []
                reduced = current
                for group in groups:
                    spans.extend(group)
                    reduced = remove_spans(current, spans)
                    if len(reduced) <= limit:
                        break
                if len(reduced) <= limit:
                    result = notice(reduced, limit, True)
                    reason = "history_and_ancillary"
                else:
                    result = diagnostic(body, limit, headers)
                    reason = "protected_content_exceeds_limit"
            except ValueError:
                result = diagnostic(body, limit, headers)
                reason = "unsafe_visible_layout"
    LOGGER.warning("PR-Agent publication omission: reason=%s original_chars=%d published_chars=%d limit=%d",
                   reason, len(body), len(result), limit)
    return result


def require_signature(function, names):
    parameters = list(inspect.signature(function).parameters.values())
    if ([p.name for p in parameters] != names
            or any(p.kind not in {p.POSITIONAL_ONLY, p.POSITIONAL_OR_KEYWORD} for p in parameters)):
        raise RuntimeError("incompatible PR-Agent runtime hook: " + function.__qualname__)


def install_hooks():
    import pr_agent.algo.review_finding_state as state_api
    from pr_agent.algo.comment_identity import PRReviewHeader
    from pr_agent.git_providers.github_provider import GithubProvider
    import pr_agent.tools.pr_reviewer as reviewer

    composer = state_api.append_review_state
    limiter = GithubProvider.limit_output_characters
    require_signature(composer, ["review_body", "state", "max_chars"])
    require_signature(limiter, ["self", "output", "max_chars"])
    require_signature(state_api.parse_review_state, ["comment_body"])
    require_signature(state_api.split_review_state_marker, ["comment_body"])
    require_signature(state_api._render_resolved_section, ["state"])
    require_signature(GithubProvider.publish_comment, ["self", "pr_comment", "is_temporary"])
    require_signature(GithubProvider.edit_comment, ["self", "comment", "body"])
    if reviewer.append_review_state is not composer or not Path(RUNNER).is_file():
        raise RuntimeError("incompatible PR-Agent composer alias or action runner")
    headers = tuple(header.value for header in PRReviewHeader)
    if len(headers) != 2 or not all(isinstance(h, str) and h.startswith("## ") for h in headers):
        raise RuntimeError("incompatible PR-Agent review identities")

    def deferred_composer(review_body, state, max_chars=None):
        return composer(review_body, state, max_chars=None)

    def publication_limiter(self, output, max_chars):
        first_line = output.split("\n", 1)[0]
        if any(first_line == header or first_line.startswith(header + " ") for header in headers):
            return fit_review(output, max_chars, state_api, headers)
        return limiter(self, output, max_chars)

    state_api.append_review_state = deferred_composer
    reviewer.append_review_state = deferred_composer
    GithubProvider.limit_output_characters = publication_limiter


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--image", action="store_true", help="print immutable image without importing PR-Agent")
    args = parser.parse_args()
    if args.image:
        print(IMAGE)
        return
    sys.path.insert(0, "/app")
    install_hooks()
    runpy.run_path(RUNNER, run_name="__main__")


if __name__ == "__main__":
    main()

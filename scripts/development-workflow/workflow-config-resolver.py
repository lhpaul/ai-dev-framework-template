#!/usr/bin/env python3
"""Resolve shared and local workflow repository context.

Selected validation and modern review share one dependency-free strict reader.
Review schema profiles remain separate from complete-source syntax. Field readers
support the small YAML subset in `.ai-dev-workflow.yaml` and
`.ai-dev-workflow.local.yaml`: nested mappings, lists, and scalar values.
Unsupported or malformed structures fail closed with metadata-only diagnostics.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import shlex
import stat
import subprocess
import sys
import tempfile
import unicodedata
from collections import namedtuple
from collections.abc import Mapping
from types import MappingProxyType
from pathlib import Path
from typing import Any


VALID_MODES = {"single_repo", "workflow_hub", "product_repo"}
VALID_CI_POLICIES = {"required", "none"}
VALID_RELEASE_OWNER_VALUES = {"current_repo", "product_repo", "hub", "hub_reference", "not_applicable"}
RELEASE_OWNER_FIELDS = (
    "changelog_owner",
    "tag_owner",
    "github_release_owner",
    "deployment_evidence_owner",
    "cleanup_evidence_owner",
    "tracker_reconciliation_owner",
)
LOCAL_ONLY_KEYS = {
    "local_path",
    "checkout_path",
    "checkout_root",
    "private_key_path",
    "private_key",
    "api_key",
    "access_key",
    "password",
    "passphrase",
    "secret_name",
    "secret_value",
    "secret",
    "secrets",
    "secret_ref",
    "token",
    "tokens",
    "tool_overrides",
    "local_overrides",
}


# Closed metadata vocabulary: never accept parser text, source paths or unknown
# key/value strings as an error description. Functional payloads bypass this API.
CONFIG_ERROR_TYPES = frozenset({
    'NUL or surrogate is not supported in review configuration',
    'YAML nesting exceeds the supported depth',
    'configuration unreadable',
    'configuration validation error',
    'contains forbidden local or secret fields',
    'contains unknown placeholder(s)',
    'contains unresolved placeholder text',
    'could not parse remaining YAML',
    'could not read config',
    'duplicate mapping key',
    'duplicate or invalid mapping continuation',
    'duplicate product_repos entries cannot be updated safely',
    'duplicate workflow_hub.product_repos name',
    "expected '<key>: <value>'",
    'expected child indentation of',
    "field 'mode' must be a string",
    "field 'mode' must be one of",
    'field must be a list',
    'field must be a mapping',
    'indentation must use multiples of two spaces',
    'invalid JSON',
    'invalid UTF-8 encoding',
    'invalid YAML',
    'invalid review.. schema',
    'invalid reviewer-field schema',
    'invalid reviewer-field schema: review.',
    'is not a portable branch name',
    'list item is not valid in this mapping',
    'local path for selected product repo is required; set product_repos[].local_path or checkout_root',
    'local-source external indirection requires explicit selection',
    'local-source missing file',
    'local-source unreadable regular file',
    'local-source: filesystem validation failed',
    'local-source: unreadable directory',
    'multiline flow collections are not supported',
    'multiline scalars are not supported',
    'must be a non-empty branch name',
    'must be a string',
    'must be one of',
    'must include the {version} placeholder',
    'non-empty flow mappings are not supported',
    'non-finite numeric scalar is not supported',
    'product repository selection is ambiguous; pass --repo',
    'product_repo.workflow_hub must define github_repo or git_url in product_repo mode',
    'product_repos[] must be a mapping',
    'repository root is not a readable directory',
    'review-effective requires PyYAML; install PyYAML==6.0.2 for the python3 used by the gate and re-run',
    'review-snapshot source unreadable',
    'review-snapshot: atomic staging failed',
    'review-snapshot: destination already contains a local projection',
    'selected source must be a mapping',
    'selected source unreadable',
    'selected source changed during capture',
    'selected workflow_hub.product_repos entry is missing',
    'tabs are not supported for indentation',
    'top-level keys must not be indented',
    'unexpected indentation',
    'unsupported YAML flow mapping',
    'unsupported YAML flow mappings',
    'unsupported YAML mapping key',
    'unsupported YAML metadata',
    'unsupported YAML nesting',
    'unsupported YAML node',
    'unsupported YAML scalar',
    'unsupported YAML scalar conversion',
    'unsupported mapping key',
    'workflow config must be a top-level mapping',
    'workflow_hub mode is required to list product repositories',
    'workflow_hub mode is required to write product repository local paths',
    'workflow_hub.product_repos is required for workflow_hub mode',
    'workflow_hub.product_repos[] contains local-only fields',
    'workflow_hub.product_repos[] must be a mapping',
    'workflow_hub.product_repos[] must define github_repo or git_url',
    'workflow_hub.product_repos[].name is required',
})
CONFIG_ERROR_KEYS = frozenset("""schema_version mode review on_draft on_ready runner github
internal_reviewers platforms phase_after_clean internal_reviewers_unavailable_policy
coderabbit_cli rate_limit_policy workflow_hub product_repo product_repos name github_repo
git_url default_branch default_branch_strategy local_path checkout_path checkout_root
release base branch_pattern changelog_owner tag_owner github_release_owner
deployment_evidence_owner cleanup_evidence_owner tracker_reconciliation_owner
ci ci_policy policy required_checks github_app app_id installation_id private_key_path
models dsh tiers roles provider model reasoning_effort role tier guardrails parallelism
max_concurrent_by_stage spec plan implementation risk_paths category glob when_pattern
path scope mode_scope mode_scopes categories always_sync special_handling project_specific
required_additions must_contain sync_coverage_exemptions reason skeleton_role entries
required_for_product_repo generated_example example_only enforce_release_runtime
reviews auto_review enabled drafts base_branches issue_tracker project_number vcs
repository_mode configured_product_repo_keys""".split())


def safe_config_key(value: Any) -> str:
    if not isinstance(value, str) or not value:
        return ""
    normalized = re.sub(r"\[\d+\]", "[]", value)
    parts = re.split(r"[./]", normalized.replace("[]", ""))
    allowed = CONFIG_ERROR_KEYS | set(globals().get("DSH_ROLE_TIERS", {})) | set(globals().get("DSH_TIERS", ()))
    return normalized if all(part in allowed for part in parts) else "unknown"


def _config_locator(value: Any) -> int | None:
    return value if type(value) is int and 0 < value <= 1000000000 else None


def format_config_error(error: BaseException | None = None, *, error_type: str = "configuration validation error",
                        key: str = "", line: int | None = None, column: int | None = None) -> str:
    """Only closed error type, numeric locators and a known schema key; no str(error)."""
    if isinstance(error, ConfigError) or (error is not None and
            type(error).__name__ == "ConfigError" and hasattr(error, "error_type")):
        error_type, key, line, column = error.error_type, error.key or key, error.line, error.column
    elif error is not None:
        name = type(error).__name__
        if name in {"ScannerError", "ParserError", "ComposerError", "ConstructorError", "ReaderError", "YAMLError"}:
            error_type = "invalid YAML"
            mark = getattr(error, "problem_mark", None)
            if mark is not None:
                line, column = mark.line + 1, mark.column + 1
        elif isinstance(error, UnicodeError):
            error_type = "invalid UTF-8 encoding"
        elif isinstance(error, OSError):
            error_type = "configuration unreadable"
        elif isinstance(error, json.JSONDecodeError):
            error_type, line, column = "invalid JSON", error.lineno, error.colno
    if not isinstance(error_type, str) or error_type not in CONFIG_ERROR_TYPES:
        error_type = "configuration validation error"
    fields = ["configuration: " + error_type]
    if _config_locator(line) is not None:
        fields.append("line=" + str(line))
    if _config_locator(column) is not None:
        fields.append("column=" + str(column))
    if key:
        fields.append("key=" + safe_config_key(key))
    return "; ".join(fields)


class ConfigError(Exception):
    """Configuration failure retaining safe structured metadata only."""

    def __init__(self, error_type: str, *, key: str = "", line: int | None = None, column: int | None = None):
        self.error_type = error_type if error_type in CONFIG_ERROR_TYPES else "configuration validation error"
        self.key, self.line, self.column = safe_config_key(key), _config_locator(line), _config_locator(column)
        super().__init__(self.error_type)

    def __str__(self) -> str:
        return format_config_error(self)


class SourceIntegrityError(ConfigError):
    """A selected source changed before its immutable capture completed."""

    def __init__(self):
        super().__init__('selected source changed during capture')


# Preserve the public Path/origin/None tuple. Retain the Path itself so object IDs
# cannot be reused; only filesystem identity metadata lives in this process map.
# No private bytes or fingerprints are cached or persisted here.
_SELECTED_SOURCES: dict[int, tuple[Path, Any]] = {}


def source_identity(path: Path) -> Any:
    try:
        link = path.lstat()
    except FileNotFoundError:
        return None
    target = path.stat()
    def identity(info: os.stat_result) -> tuple[int, ...]:
        return (info.st_dev, info.st_ino, info.st_mode, info.st_size,
                info.st_mtime_ns, info.st_ctime_ns)
    return (identity(link), identity(target), str(path.resolve()))


def retain_selected_source(path: Path, expected: Any) -> Path:
    if source_identity(path) != expected:
        raise SourceIntegrityError()
    _SELECTED_SOURCES[id(path)] = (path, expected)
    return path


def selected_source_present(path: Path) -> bool:
    selected = _SELECTED_SOURCES.get(id(path))
    return selected[1] is not None if selected and selected[0] is path else path.is_file()


def open_config_nonblocking(path: str, flags: int) -> int:
    """Never wait for a FIFO writer if a selected path changes before open."""
    return os.open(path, flags | os.O_NONBLOCK)


def capture_config_bytes(path: Path, *, required: bool = False) -> bytes | None:
    """Read once from the selected identity, checking path and FD around capture.

    Subsequent use consumes this immutable value; mutations after capture do not
    invalidate a completed model snapshot or staged review projection.
    """
    selected = _SELECTED_SOURCES.get(id(path))
    bound = selected is not None and selected[0] is path
    try:
        before = source_identity(path)
        expected = selected[1] if bound else before
        if before != expected or (required and before is None):
            raise SourceIntegrityError()
        if before is None:
            return None
        if not stat.S_ISREG(before[1][2]):
            raise SourceIntegrityError()
        with open(path, 'rb', opener=open_config_nonblocking) as stream:
            opened = os.fstat(stream.fileno())
            identity = (opened.st_dev, opened.st_ino, opened.st_mode, opened.st_size,
                        opened.st_mtime_ns, opened.st_ctime_ns)
            if identity != expected[1] or not stat.S_ISREG(opened.st_mode):
                raise SourceIntegrityError()
            raw = stream.read()
            final = os.fstat(stream.fileno())
            final_identity = (final.st_dev, final.st_ino, final.st_mode, final.st_size,
                              final.st_mtime_ns, final.st_ctime_ns)
            if final_identity != identity or source_identity(path) != expected:
                raise SourceIntegrityError()
        return raw
    except (OSError, RuntimeError) as exc:
        if bound or required:
            raise SourceIntegrityError() from exc
        raise ConfigError('could not read config') from exc


def capture_config_text(path: Path, *, required: bool = False) -> str | None:
    raw = capture_config_bytes(path, required=required)
    # Match Path.read_text's universal-newline handling for legacy text readers.
    return None if raw is None else raw.decode('utf-8').replace('\r\n', '\n').replace('\r', '\n')


SENSITIVE_DIAGNOSTIC_KEY = r"(?:[A-Za-z0-9]+[_.-])*(?:token|password|passphrase|secret|api[ _.-]?key|access[ _.-]?key|private[ _.-]?key)(?:[_.-](?:value|key))?"


def _diagnostic_assignment_spans(text: str, *, frame_separator: int | None = None, include_empty: bool = False):
    """Yield complete lexical values, without reading or parsing configuration."""
    key = SENSITIVE_DIAGNOSTIC_KEY
    next_field = re.compile(r'''[ \t]+(?:--?)?["']?(?:[A-Za-z_][\w.-]*|''' + key + r''')["']?[ \t]*[:=]''', re.IGNORECASE)
    assignment = re.compile(r'''(?<![\w.])(["']?(?:''' + key + r'''|authorization)["']?[ \t]*[:=][ \t]*)''', re.IGNORECASE)
    breaks = re.compile(r"\r\n|[\n\r\x85\u2028\u2029]")
    lines = []
    previous = 0
    for boundary in breaks.finditer(text):
        lines.append((previous, boundary.start(), boundary.end()))
        previous = boundary.end()
    lines.append((previous, len(text), len(text)))

    def sequence_indent(prefix, *, scalar=False):
        leading = len(prefix) - len(prefix.lstrip(" \t"))
        sequence = re.match(r"(?:-[ \t]+)+", prefix[leading:])
        if not sequence:
            return None
        end = leading + sequence.end()
        if scalar and not prefix[end:].strip(" \t"):
            # A bare block scalar belongs to the final dash, while a compact
            # mapping key belongs after the complete sequence prefix.
            return leading + re.search(r"-[ \t]+$", sequence[0]).start()
        return end

    def flow_at(position):
        stack, quote, plain, block_indent = [], "", False, None
        for line_number, (begin, finish, _) in enumerate(lines):
            if begin > position:
                break
            raw = text[begin:finish]
            indent = len(raw) - len(raw.lstrip(" \t"))
            if block_indent is not None and not quote:
                if not raw.strip(" \t") or indent > block_indent:
                    if position <= finish:
                        block_end = len(text)
                        for following in range(line_number + 1, len(lines)):
                            left, right, _ = lines[following]
                            body = text[left:right]
                            spaces = len(body) - len(body.lstrip(" \t"))
                            if body.strip(" \t") and spaces <= block_indent:
                                block_end = lines[following - 1][1]
                                break
                        return False, block_end, ""
                    continue
                block_indent = None
            if not stack and not quote:
                plain = False
            index = begin
            while index < min(position, finish):
                char = text[index]
                if quote:
                    if quote == '"' and char == "\\":
                        index += 2
                        continue
                    if char == quote:
                        if quote == "'" and text[index + 1:index + 2] == "'":
                            index += 2
                            continue
                        quote, plain = "", True
                elif char == "#" and (not plain or index == begin or text[index - 1] in " \t"):
                    # A sensitive assignment inside a comment still needs
                    # redaction, but its quote/brackets cannot own a real field.
                    if position <= finish:
                        return False, finish, ""
                    break
                elif char in ('"', "'") and not plain:
                    quote = char
                elif char in "[{" and not plain:
                    stack.append(char)
                    plain = False
                elif char in "]}" and stack:
                    if (stack[-1], char) in (("[", "]"), ("{", "}")):
                        stack.pop()
                    plain = True
                elif char == "," and stack:
                    plain = False
                elif char == ":" and (stack or text[index + 1:index + 2] in ("", " ", "\t")):
                    plain = False
                elif not stack and not plain and char in "|>":
                    logical = sequence_indent(raw[:index - begin], scalar=True)
                    block_indent = indent if logical is None else logical
                    break
                elif not stack and not plain and char == "-" and text[index + 1:index + 2] in (" ", "\t"):
                    pass
                elif char not in " \t":
                    plain = True
                index += 1
        if quote:
            # An assignment inside a public quoted scalar is literal payload.
            # Its enclosing quote, rather than an inner comma, owns the end.
            index = position
            while index < len(text):
                if quote == '"' and text[index] == "\\":
                    index += 2
                    continue
                if text[index] == quote:
                    if quote == "'" and text[index + 1:index + 2] == "'":
                        index += 2
                        continue
                    return False, index, quote
                index += 1
            return False, len(text), quote
        return bool(stack), None, ""

    offset = 0
    for match in assignment.finditer(text):
        if match.start() < offset:
            continue
        header = start = end = match.end()
        colon = match[1].rstrip().endswith(":")
        context_position = match.start()
        header_key = match[1].rstrip(" \t")[:-1].rstrip(" \t")
        if header_key[:1] in ('"', "'") and not header_key.endswith(header_key[0]):
            # The optional header quote can be the PUBLIC scalar's opener,
            # rather than one of the balanced quotes around a mapping key.
            context_position += 1
        flow, context_end, literal_quote = flow_at(context_position)
        flow = colon and flow
        scan_limit = len(text) if context_end is None else context_end
        if literal_quote:
            if scan_limit > start or include_empty:
                yield match, header, start, scan_limit, False, literal_quote
                offset = scan_limit
            continue
        line_index = next(i for i, row in enumerate(lines) if row[0] <= match.start() <= row[1])
        line_start = lines[line_index][0]
        prefix = text[line_start:match.start()]
        indent = len(prefix) - len(prefix.lstrip(" \t"))
        decoration = ""
        # List mapping fields are siblings at the node after the dash. A prose
        # prefix is decoration, not the scalar's structural indentation.
        node_indent = sequence_indent(prefix)
        logical = re.search(r"(?:^|[ \t])((?:-[ \t]+)+)$", prefix)
        if node_indent is not None:
            indent = node_indent
        elif logical:
            before = prefix[:logical.start(1)]
            decoration = before if before.strip(" \t") else ""
            indent = (len(before) - len(before.lstrip(" \t"))) + len(logical[1])
        elif prefix.strip(" \t"):
            decoration = prefix

        def content(index):
            begin, finish, after = lines[index]
            decorated_indent = 0
            if decoration and text.startswith(decoration, begin):
                begin += len(decoration)
                decorated_indent = len(decoration) - len(decoration.lstrip(" \t"))
            raw = text[begin:finish]
            spaces = len(raw) - len(raw.lstrip(" \t"))
            return begin + spaces, finish, after, spaces + decorated_indent, raw[spaces:]

        def owns(index):
            _, _, _, spaces, body = content(index)
            return spaces > indent or (spaces == indent and re.match(r"-[ \t]", body))

        if colon and flow:
            while start < len(text) and text[start] in " \t\r\n\x85\u2028\u2029":
                start += 1
        elif colon and (start == lines[line_index][1] or text[start:start + 1] == "#"):
            for index in range(line_index + 1, len(lines)):
                begin, _, _, _, body = content(index)
                if not body or body.startswith("#"):
                    continue
                if owns(index):
                    start = begin
                break
            # A missing value has no owned span; leave public siblings intact.
            if start == header:
                continue
        end = start
        quote = ""
        stack = []
        quoted_scalar = text[start:start + 1] in ('"', "'")

        def closed_value(position):
            following = position
            while following < scan_limit and text[following] in " \t":
                following += 1
            line_end = breaks.search(text, following)
            terminal_pipe = (text[following:following + 1] == "|" and
                             not text[following + 1:line_end.start() if line_end else len(text)].strip(" \t"))
            return (following == frame_separator or following == scan_limit or text[following] in "\r\n\x85\u2028\u2029#"
                    or terminal_pipe or (flow and text[following] in ",}]"))

        while end < scan_limit:
            char = text[end]
            if char == "\\" and end + 1 < len(text) and (not colon or quote == '"'):
                end += 2
                continue
            if quote:
                if char == quote:
                    if colon and quote == "'" and text[end + 1:end + 2] == "'":
                        end += 2
                        continue
                    quote = ""
                    if quoted_scalar and not stack and (colon or end + 1 == frame_separator):
                        end += 1
                        if closed_value(end):
                            break
                        quoted_scalar = False
                        continue
            elif char in ('"', "'") and (not colon or end == start or stack):
                quote = char
            elif colon and (flow or stack) and char == "#" and (end == start or text[end - 1] in " \t\r\n\x85\u2028\u2029"):
                # Comment punctuation is never collection structure. Consume
                # the physical comment while retaining the actual open value.
                boundary = breaks.search(text, end)
                end = min(scan_limit, boundary.end() if boundary else len(text))
                continue
            elif colon and (flow or text[start:start + 1] in "[{") and char in "[{":
                stack.append(char)
            elif colon and (flow or stack) and char in "]}":
                if not stack:
                    break
                if (stack[-1], char) not in (("[", "]"), ("{", "}")):
                    end = len(text)
                    break
                stack.pop()
                if not stack and text[start:start + 1] in "[{":
                    end += 1
                    if closed_value(end):
                        break
                    continue
            elif flow and char == "," and not stack:
                break
            elif char in "\r\n\x85\u2028\u2029" and not flow and not stack:
                break
            elif not colon and char in ";|&":
                break
            elif char in " \t" and ((not flow and not stack and text[end:].lstrip(" \t").startswith("#")) or (not colon and next_field.match(text, end))):
                break
            end += 1
        if quote or stack:
            end = scan_limit
        # After a block/plain/quoted header, consume only owned subsequent
        # physical lines. Lookahead over blanks/comments never eats a sibling.
        if colon and not flow and context_end is None and end < len(text):
            last_line = next(i for i, row in enumerate(lines) if row[0] <= max(start, end - 1) <= row[1])
            remainder = text[end:lines[last_line][1]].strip(" \t")
            if not remainder or remainder.startswith("#") or remainder == "|":
                block = text[start:start + 1] in "|>"
                for index in range(last_line + 1, len(lines)):
                    _, finish, _, _, body = content(index)
                    if not body or (body.startswith("#") and not block):
                        continue
                    if not owns(index):
                        break
                    end = finish
        if end > start or include_empty:
            yield match, header, start, end, flow, ""
            offset = end


def redact_text(text: str) -> str:
    """Bounded structural diagnostic sanitizer; never reads configuration."""
    marker = "[REDACTED]"
    # Track nesting so a misleading nested delimiter cannot expose a suffix.
    key_boundary = re.compile(r"-----((?:BEGIN|END)) (?:[A-Z0-9]+ )*PRIVATE KEY-----", re.IGNORECASE)
    pieces: list[str] = []
    offset = depth = 0
    for boundary in key_boundary.finditer(text):
        if boundary[1].upper() == "BEGIN":
            if depth == 0:
                pieces.append(text[offset:boundary.start()])
            depth += 1
        elif depth:
            depth -= 1
            if depth == 0:
                pieces.append(marker)
                offset = boundary.end()
    if depth:
        pieces.append(marker)
    else:
        pieces.append(text[offset:])
    text = "".join(pieces)
    pieces, offset = [], 0
    for match, header, start, end, flow, literal_quote in _diagnostic_assignment_spans(text):
        raw = text[start:end]
        quote = raw[:1] if not literal_quote and raw[:1] in ("\"", "'") else ""
        if not literal_quote and not quote and match[1].startswith('"'):
            quote = '"'
        trailing_space = raw[len(raw.rstrip(" \t")):]
        context = ""
        if not flow and not quote and re.fullmatch(r"authorization[ \t]*[:=][ \t]*", match[1], re.IGNORECASE):
            schemes = dict.fromkeys(item.title() for item in re.findall(r"\b(Bearer|Basic)[ \t]+\S+", raw, re.IGNORECASE))
            context = "".join(" " + scheme + " " + marker for scheme in schemes)
        pieces.extend((text[offset:match.start()], match[1], quote + marker + quote, context, trailing_space))
        offset = end
    pieces.append(text[offset:])
    text = "".join(pieces)
    text = re.sub(r"(?i)\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+", lambda match: match[1] + " " + marker, text)
    text = re.sub(r"(?i)(\b[a-z][a-z0-9+.-]*://)[^\s/@]+(?::[^\s/@]*)?@", lambda match: match[1] + marker + "@", text)
    text = re.sub(r"(?<![A-Za-z0-9_])(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|sk-(?:proj-)?[A-Za-z0-9_-]+|xox[baprs]-[A-Za-z0-9-]+)(?![A-Za-z0-9_])", marker, text)
    return text


def redact_diagnostic_json(value: Any) -> Any:
    if isinstance(value, str):
        return redact_text(value)
    if isinstance(value, list):
        return [redact_diagnostic_json(item) for item in value]
    if isinstance(value, dict):
        output = {}
        for key, item in value.items():
            sensitive = re.fullmatch(SENSITIVE_DIAGNOSTIC_KEY, key, re.IGNORECASE)
            header = key.lower() == "authorization" and isinstance(item, str)
            # An authorization metadata object is not a header;
            # recurse so its own sensitive fields still disappear.
            output[redact_text(key)] = "[REDACTED]" if sensitive or header else redact_diagnostic_json(item)
        return output
    return value


class DiagnosticArgumentParser(argparse.ArgumentParser):
    """CLI parse/help errors are diagnostic text; never read config here."""
    def _print_message(self, message, file=None):
        if message:
            super()._print_message(redact_text(message), file)


def _redact_diagnostic_pair(key: str, value: str, *, escaped: bool = False) -> str:
    """Classify an original frame before markers can hide separator ownership."""
    original = key + "=" + value
    separator = len(key)
    assignments = list(_diagnostic_assignment_spans(original, frame_separator=separator, include_empty=True))
    spans = [(match.start(), start, end) for match, _, start, end, _, _ in assignments]
    headers = [match for match, _, _, end, _, _ in assignments if match.start() < separator and end > separator]
    authorization = any(re.fullmatch(r'''["']?authorization["']?[ \t]*[:=][ \t]*''', match[1], re.IGNORECASE) for match in headers)
    raw_authorization = any(re.fullmatch(r"authorization[ \t]*[:=][ \t]*", match[1], re.IGNORECASE) for match in headers)
    # These are the existing non-assignment lexical classes. Keep their original
    # positions too: a credential/PEM opened in the key may cross the separator.
    boundaries = re.compile(r"-----((?:BEGIN|END)) (?:[A-Z0-9]+ )*PRIVATE KEY-----", re.IGNORECASE)
    depth = 0
    begin = 0
    for boundary in boundaries.finditer(original):
        if boundary[1].upper() == "BEGIN":
            if not depth:
                begin = boundary.start()
            depth += 1
        elif depth:
            depth -= 1
            if not depth:
                spans.append((begin, begin, boundary.end()))
    if depth:
        spans.append((begin, begin, len(original)))
    for pattern in (r"(?i)\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+",
                    r"(?i)(\b[a-z][a-z0-9+.-]*://)[^\s/@]+(?::[^\s/@]*)?@",
                    r"(?<![A-Za-z0-9_])(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|sk-(?:proj-)?[A-Za-z0-9_-]+|xox[baprs]-[A-Za-z0-9-]+)(?![A-Za-z0-9_])"):
        for match in re.finditer(pattern, original):
            spans.append((match.start(), match.end(1) if match.lastindex else match.start(), match.end()))
    crossing = [(start, end) for begin, start, end in spans if begin < separator and end > separator]
    # Protect the key's part of an open span, then apply the ordinary scanner to
    # its remaining complete content. A closed key span leaves a public value.
    safe_key = key
    for start, end in sorted(crossing, reverse=True):
        if start < separator:
            safe_key = safe_key[:start] + "[REDACTED]"
    safe_key = redact_text(safe_key)
    whole_key = re.fullmatch(SENSITIVE_DIAGNOSTIC_KEY, key, re.IGNORECASE) or key.lower() == "authorization"
    if (crossing or whole_key) and value:
        leading = value[:len(value) - len(value.lstrip(" \t"))]
        trailing = value[len(value.rstrip(" \t")):]
        quote = value.lstrip(" \t")[:1]
        quote = quote if quote in ('"', "'") else ""
        if not escaped and not quote and any(match[1].startswith('"') for match in headers):
            quote = '"'
        safe_value = leading + quote + "[REDACTED]" + quote
        if authorization:
            schemes = dict.fromkeys(item.title() for item in re.findall(r"\b(Bearer|Basic)[ \t]+\S+", value, re.IGNORECASE))
            display = " ".join(scheme + " [REDACTED]" for scheme in schemes)
            if escaped and display:
                safe_value = leading + quote + display + quote
            elif not quote and raw_authorization and display:
                safe_value += " " + display
        safe_value += trailing
    else:
        safe_value = redact_text(value)
    if escaped:
        safe_value = safe_value.rstrip("\n")
        safe_value = safe_value.replace("\\", "\\\\").replace("\r", "\\r").replace("\n", "\\n").replace("\t", "\\t")
        safe_value = "".join(("\\x%02x" % ord(char)) if ord(char) < 32 or ord(char) == 127 else
                             ("\\u%04x" % ord(char)) if 128 <= ord(char) <= 159 else char for char in safe_value)
        return safe_key + "=" + safe_value + "\n"
    return (safe_key + "=" + safe_value).rstrip("\n") + "\n"


def redact_diagnostic_kv_frames(raw: str, *, single: bool = False, escaped: bool = False) -> str:
    """Sanitize complete NUL-framed records before atomic report publication."""
    if not raw.endswith("\0"):
        raise ValueError("invalid diagnostic framing")
    fields = raw[:-1].split("\0")
    if not fields or len(fields) % 2 or (single and len(fields) != 2):
        raise ValueError("invalid diagnostic pair count")
    records = []
    for index in range(0, len(fields), 2):
        key, value = fields[index:index + 2]
        if not single and not re.fullmatch(r"[A-Z][A-Z0-9_]*", key):
            raise ValueError("invalid diagnostic key")
        records.append(_redact_diagnostic_pair(key, value, escaped=escaped))
    return "".join(records)


def cmd_redact_text(args: argparse.Namespace) -> int:
    try:
        framed = args.kv or args.kv_pair or args.kv_escaped
        raw = sys.stdin.buffer.read().decode("utf-8") if framed else sys.stdin.read()
        if args.json:
            output = json.dumps(redact_diagnostic_json(json.loads(raw)), sort_keys=True) + "\n"
        elif framed:
            output = redact_diagnostic_kv_frames(raw, single=not args.kv, escaped=args.kv_escaped)
        else:
            output = redact_text(raw)
    except Exception:
        print("ERROR: diagnostic sanitization failed", file=sys.stderr)
        return 2
    sys.stdout.write(output)
    return 0


def strip_inline_comment(line: str) -> str:
    in_single = False
    in_double = False
    escaped = False
    result: list[str] = []
    for char in line:
        if escaped:
            result.append(char)
            escaped = False
            continue
        if char == "\\" and in_double:
            result.append(char)
            escaped = True
            continue
        if char == "'" and not in_double:
            in_single = not in_single
            result.append(char)
            continue
        if char == '"' and not in_single:
            in_double = not in_double
            result.append(char)
            continue
        if char == "#" and not in_single and not in_double:
            break
        result.append(char)
    return "".join(result).rstrip()


def preprocess_yaml(path: Path) -> list[tuple[int, str, int]]:
    try:
        raw_lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise ConfigError('could not read config') from exc

    return preprocess_yaml_snapshot("\n".join(raw_lines), path)


def preprocess_yaml_snapshot(raw: str, path: Path) -> list[tuple[int, str, int]]:
    """Default legacy preprocessing on an already selected snapshot."""
    lines: list[tuple[int, str, int]] = []
    for line_no, raw in enumerate(raw.splitlines(), start=1):
        if "\t" in raw[: len(raw) - len(raw.lstrip(" \t"))]:
            raise ConfigError('tabs are not supported for indentation', line=line_no)
        stripped_comment = strip_inline_comment(raw)
        if not stripped_comment.strip():
            continue
        indent = len(stripped_comment) - len(stripped_comment.lstrip(" "))
        if indent % 2 != 0:
            raise ConfigError('indentation must use multiples of two spaces', line=line_no)
        lines.append((indent, stripped_comment.strip(), line_no))
    return lines


def split_key_value(content: str, path: Path, line_no: int) -> tuple[str, str | None]:
    if ":" not in content:
        raise ConfigError("expected '<key>: <value>'", line=line_no)
    key, value = content.split(":", 1)
    key = key.strip()
    if not re.match(r"^[A-Za-z0-9_.-]+$", key):
        raise ConfigError('unsupported mapping key', line=line_no)
    value = value.strip()
    return key, value if value != "" else None


def parse_scalar(
    value: str, *, review_effective: bool = False, path: Path | None = None, line_no: int | None = None
) -> Any:
    if review_effective:
        assert path is not None and line_no is not None
        return parse_review_yaml(path, raw="value: " + value)["value"]
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [parse_scalar(item.strip()) for item in split_inline_list(inner) if item.strip()]
    if value in {"''", '""'}:
        return ""
    if (value.startswith("'") and value.endswith("'")) or (
        value.startswith('"') and value.endswith('"')
    ):
        return value[1:-1]
    if value == "[]":
        return []
    if value == "{}":
        return {}
    if value.lower() == "true":
        return True
    if value.lower() == "false":
        return False
    if value.lower() in {"null", "~"}:
        return None
    return value


def parse_review_numeric_scalar(value: str, path: Path, line_no: int) -> Any:
    """Preserve numeric YAML scalars as non-strings for review-effective only."""
    normalized = value.replace("_", "")
    decimal = r"(?:0|[1-9](?:_?[0-9])*)"
    if re.fullmatch(r"[+-]?\.(?:inf|nan)", value, re.IGNORECASE):
        raise ConfigError('non-finite numeric scalar is not supported', line=line_no)
    if re.fullmatch(r"[+-]?0[xX][0-9a-fA-F](?:_?[0-9a-fA-F])*", value):
        return int(normalized, 0)
    if re.fullmatch(r"[+-]?0[oO][0-7](?:_?[0-7])*", value):
        return int(normalized, 0)
    if re.fullmatch(r"[+-]?0[bB][01](?:_?[01])*", value):
        return int(normalized, 0)
    if re.fullmatch(r"[+-]?0[0-7](?:_?[0-7])*", value):
        sign = -1 if normalized.startswith("-") else 1
        return sign * int(normalized.lstrip("+-"), 8)
    if re.fullmatch(rf"[+-]?{decimal}", value):
        return int(normalized)
    if re.fullmatch(
        rf"[+-]?(?:(?:{decimal}\.(?:[0-9](?:_?[0-9])*)?|\.[0-9](?:_?[0-9])*)(?:[eE][+-]?{decimal})?|{decimal}[eE][+-]?{decimal})",
        value,
    ):
        numeric = float(normalized)
        if not math.isfinite(numeric):
            raise ConfigError('non-finite numeric scalar is not supported', line=line_no)
        return numeric
    return value


def split_inline_list(value: str) -> list[str]:
    items: list[str] = []
    current: list[str] = []
    in_single = False
    in_double = False
    escaped = False

    for char in value:
        if escaped:
            current.append(char)
            escaped = False
            continue
        if char == "\\" and in_double:
            current.append(char)
            escaped = True
            continue
        if char == "'" and not in_double:
            in_single = not in_single
            current.append(char)
            continue
        if char == '"' and not in_single:
            in_double = not in_double
            current.append(char)
            continue
        if char == "," and not in_single and not in_double:
            items.append("".join(current))
            current = []
            continue
        current.append(char)

    items.append("".join(current))
    return items


def parse_mapping(
    lines: list[tuple[int, str, int]], index: int, indent: int, path: Path
) -> tuple[dict[str, Any], int]:
    result: dict[str, Any] = {}
    while index < len(lines):
        line_indent, content, line_no = lines[index]
        if line_indent < indent:
            break
        if line_indent > indent:
            raise ConfigError('unexpected indentation', line=line_no)
        if content.startswith("- "):
            raise ConfigError('list item is not valid in this mapping', line=line_no)
        key, value = split_key_value(content, path, line_no)
        index += 1
        if value is not None:
            result[key] = parse_scalar(value)
            continue
        if index >= len(lines) or lines[index][0] <= indent:
            result[key] = {}
            continue
        child_indent, child_content, _ = lines[index]
        if child_indent != indent + 2:
            raise ConfigError('expected child indentation of', line=lines[index][2])
        if child_content.startswith("- "):
            child, index = parse_list(lines, index, child_indent, path)
        else:
            child, index = parse_mapping(lines, index, child_indent, path)
        result[key] = child
    return result, index


def parse_list(
    lines: list[tuple[int, str, int]], index: int, indent: int, path: Path
) -> tuple[list[Any], int]:
    result: list[Any] = []
    while index < len(lines):
        line_indent, content, line_no = lines[index]
        if line_indent < indent:
            break
        if line_indent > indent:
            raise ConfigError('unexpected indentation', line=line_no)
        if not content.startswith("- "):
            break
        item = content[2:].strip()
        index += 1
        if not item:
            if index >= len(lines) or lines[index][0] <= indent:
                result.append({})
                continue
            child_indent, child_content, _ = lines[index]
            if child_indent != indent + 2:
                raise ConfigError('expected child indentation of', line=lines[index][2])
            if child_content.startswith("- "):
                child, index = parse_list(lines, index, child_indent, path)
            else:
                child, index = parse_mapping(lines, index, child_indent, path)
            result.append(child)
            continue
        if ":" in item:
            key, value = split_key_value(item, path, line_no)
            if value is None and index < len(lines) and lines[index][0] > indent:
                # For `- key:` items, the following indented block is the value
                # of `key`; it must not be merged into the list-item root.
                child_indent = lines[index][0]
                child_content = lines[index][1]
                if child_content.startswith("- "):
                    child, index = parse_list(lines, index, child_indent, path)
                else:
                    child, index = parse_mapping(lines, index, child_indent, path)
                item_map = {key: child}
            else:
                item_map = {key: parse_scalar(value) if value is not None else {}}
            if value is not None and index < len(lines) and lines[index][0] == indent + 2:
                continuation, index = parse_mapping(lines, index, indent + 2, path)
                for continuation_key, continuation_value in continuation.items():
                    item_map[continuation_key] = continuation_value
            result.append(item_map)
        else:
            result.append(parse_scalar(item))
    return result, index


def parse_review_yaml(path: Path, *, raw: str | None = None, review_fields: bool = True) -> dict[str, Any]:
    """Read the complete framework grammar once, then apply its data profile.

    This is the sole strict syntax authority for validation, modern review and
    captured projections. Review-specific collection/numeric restrictions are
    conversion rules, never a second grammar or a third-party parser.
    """
    try:
        if raw is None:
            raw = path.read_text(encoding="utf-8")
        tree = StrictYamlReader(raw, path).parse()
        return convert_strict_yaml(tree, path, review_fields=review_fields)
    except (OSError, RecursionError, ValueError, OverflowError) as exc:
        raise ConfigError('invalid YAML') from exc


class YamlScalar(str):
    """A syntactically complete scalar before profile-specific conversion."""
    def __new__(cls, value: str, line: int, quoted: bool = False):
        result = super().__new__(cls, value)
        result.line = line
        result.quoted = quoted
        return result


class YamlBlockMapping(dict):
    """Retain key locations until duplicate continuation checks finish."""
    def __init__(self):
        super().__init__()
        self.key_lines: dict[str, int] = {}


class YamlFlowMapping(dict):
    """Keep flow identity until the review profile can reject nonempty maps."""
    def __init__(self, *args, line: int):
        super().__init__(*args)
        self.line = line


def convert_strict_yaml(value: Any, path: Path, *, review_fields: bool) -> Any:
    if isinstance(value, YamlScalar):
        text = str(value)
        if value.quoted:
            return text
        if text in ("null", "Null", "NULL", "~"):
            return None
        if text in ("true", "True", "TRUE", "false", "False", "FALSE"):
            return text.lower() == "true"
        try:
            return parse_review_numeric_scalar(text, path, value.line)
        except ConfigError:
            if review_fields:
                raise
            return 0  # Syntax-only legacy validation retains its numeric marker.
        except (ValueError, OverflowError) as exc:
            if review_fields:
                raise ConfigError('unsupported YAML scalar conversion', line=value.line) from exc
            return 0
    if isinstance(value, dict):
        if review_fields and isinstance(value, YamlFlowMapping) and value:
            raise ConfigError('unsupported YAML flow mappings', line=value.line)
        return {str(key): convert_strict_yaml(item, path, review_fields=review_fields)
                for key, item in value.items()}
    if isinstance(value, list):
        return [convert_strict_yaml(item, path, review_fields=review_fields) for item in value]
    return value


def parse_yaml_subset(path: Path, *, preserve_empty_values: bool = False) -> dict[str, Any]:
    raw = capture_config_text(path)
    if raw is None:
        return {}
    if preserve_empty_values:
        return parse_review_yaml(path, raw=raw)
    return parse_yaml_snapshot(raw, path)


def parse_yaml_snapshot(raw: str, path: Path) -> dict[str, Any]:
    """Keep legacy fields; validate selected private bytes before extracting them."""
    if path.name == LOCAL_CONFIG_NAME:
        validate_selected_yaml(raw, path)
    lines = preprocess_yaml_snapshot(raw, path)
    if not lines:
        return {}
    if lines[0][0] != 0:
        raise ConfigError('top-level keys must not be indented', line=lines[0][2])
    data, index = parse_mapping(lines, 0, lines[0][0], path)
    if index != len(lines):
        _, _, line_no = lines[index]
        raise ConfigError('could not parse remaining YAML', line=line_no)
    return data


def repo_root_from_args(value: str | None) -> Path:
    if value:
        return Path(value).resolve()
    return Path.cwd().resolve()


def as_mapping(value: Any, path: Path, field: str) -> dict[str, Any]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ConfigError('field must be a mapping', key=field)
    return value


def as_list(value: Any, path: Path, field: str) -> list[Any]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise ConfigError('field must be a list', key=field)
    return value


LOCAL_CONFIG_NAME = ".ai-dev-workflow.local.yaml"


class StrictYamlReader:
    """Strict, finite framework grammar; no YAML object construction or recovery.

    Block mappings/sequences and one-line flow collections/scalars are supported.
    Metadata, references and multiline scalars are deliberately unsupported, as
    in the framework readers. Legacy field conversion remains a separate step.
    """

    def __init__(self, raw: str, path: Path):
        self.path = path
        self.unicode_breaks = set()
        self.lines: list[tuple[int, str, int]] = []
        physical_lines = re.split(r"(\r\n|[\r\n\x85\u2028\u2029])", raw)
        for number, physical in enumerate(physical_lines[::2], 1):
            separator = physical_lines[number * 2 - 1] if number * 2 - 1 < len(physical_lines) else ""
            if separator in ("\x85", "\u2028", "\u2029"):
                self.unicode_breaks.add(number)
            line = physical
            if number == 1:
                line = line.removeprefix("\ufeff")
            for column, char in enumerate(line, 1):
                code = ord(char)
                if not (code == 9 or 0x20 <= code <= 0x7E or
                        0xA0 <= code <= 0xD7FF or 0xE000 <= code <= 0xFFFD or
                        0x10000 <= code <= 0x10FFFF):
                    raise ConfigError('invalid YAML', line=number, column=column)
            indent = len(line) - len(line.lstrip(" \t"))
            if "\t" in line[:indent]:
                self.fail(number)
            content = line[indent:]
            if content.strip(" \t") and not content.startswith("#"):
                if indent % 2:
                    self.fail(number)
                self.lines.append((indent, content, number))

    def fail(self, line: int, category: str = "invalid YAML") -> None:
        raise ConfigError(category, line=line)

    def scalar(self, text: str, line: int, *, depth: int = 0) -> Any:
        """Consume the complete scalar/flow value, including its comment suffix."""
        index = 0

        def spaces() -> None:
            nonlocal index
            while index < len(text) and text[index] in " \t":
                index += 1

        def quoted() -> str:
            nonlocal index
            quote = text[index]
            index += 1
            output = []
            escapes = {"0": "\0", "a": "\a", "b": "\b", "t": "\t", "n": "\n",
                       "v": "\v", "f": "\f", "r": "\r", "e": "\x1b", " ": " ",
                       '"': '"', "/": "/", "\\": "\\", "N": "\x85", "_": "\xa0",
                       "L": "\u2028", "P": "\u2029"}
            while index < len(text):
                char = text[index]
                index += 1
                if char == quote:
                    if quote == "'" and index < len(text) and text[index] == "'":
                        output.append("'")
                        index += 1
                        continue
                    result = "".join(output)
                    if "\0" in result:
                        self.fail(line, "unsupported YAML scalar")
                    return YamlScalar(result, line, quoted=True)
                if char == "\\" and quote == '"':
                    if index >= len(text):
                        self.fail(line)
                    escape = text[index]
                    index += 1
                    if escape in ("x", "u", "U"):
                        size = {"x": 2, "u": 4, "U": 8}[escape]
                        digits = text[index:index + size]
                        if len(digits) != size or not re.fullmatch(r"[0-9a-fA-F]+", digits):
                            self.fail(line)
                        code = int(digits, 16)
                        if code > 0x10FFFF or 0xD800 <= code <= 0xDFFF:
                            self.fail(line)
                        char = chr(code)
                        index += size
                    elif escape in escapes:
                        char = escapes[escape]
                    else:
                        self.fail(line)
                output.append(char)
            self.fail(line, "multiline scalars are not supported" if line in self.unicode_breaks else "invalid YAML")

        def value(level: int, flow: bool = False, key: bool = False, *, entry: bool = False) -> Any:
            nonlocal index
            spaces()
            if index >= len(text):
                self.fail(line)
            char = text[index]
            if flow and entry and char == "?":
                index += 1
                spaces()
                explicit_key = value(level + 1, True, True)
                spaces()
                explicit_value = None
                if index < len(text) and text[index] == ":":
                    index += 1
                    spaces()
                    if index < len(text) and text[index] not in ",]}":
                        explicit_value = value(level + 1, True)
                if not isinstance(explicit_key, str):
                    self.fail(line, "unsupported YAML mapping key")
                return YamlFlowMapping({explicit_key: explicit_value}, line=line)
            if char in "\"'":
                return quoted()
            if char in "[{":
                opening = char
                closing = "]" if char == "[" else "}"
                index += 1
                items: Any = [] if opening == "[" else YamlFlowMapping(line=line)
                spaces()
                if index < len(text) and text[index] == closing:
                    index += 1
                    return items
                while True:
                    item = value(level + 1, True, opening == "{", entry=True)
                    spaces()
                    if opening == "[":
                        if index < len(text) and text[index] == ":":
                            if not isinstance(item, str):
                                self.fail(line, "unsupported YAML flow mapping")
                            index += 1
                            spaces()
                            mapped = (None if index == len(text) or text[index] in ",]"
                                      else value(level + 1, True))
                            item = YamlFlowMapping({item: mapped}, line=line)
                            spaces()
                        items.append(item)
                    else:
                        if not isinstance(item, str) or index >= len(text) or text[index] != ":":
                            self.fail(line)
                        index += 1
                        spaces()
                        if item in items:
                            self.fail(line, "duplicate mapping key")
                        items[item] = value(level + 1, True)
                        spaces()
                    if index >= len(text):
                        self.fail(line)
                    separator = text[index]
                    index += 1
                    if separator == closing:
                        return items
                    if separator != ",":
                        self.fail(line)
                    spaces()
                    if index < len(text) and text[index] == closing:
                        index += 1  # Existing YAML flow trailing-comma syntax.
                        return items
            start = index
            if char in ",]}#&*!|>%@`" or (flow and char in ":?") or (char in "-?:" and
                    (index + 1 == len(text) or text[index + 1] in " \t")):
                self.fail(line)
            while index < len(text):
                char = text[index]
                if flow and char in ",]}":
                    break
                if char == "#" and (index == start or text[index - 1] in " \t"):
                    break
                if key and char == ":":
                    break
                if flow and char == ":" and (index + 1 == len(text) or
                        text[index + 1] in " \t,[]{}"):
                    break
                if (flow and char in "[{?") or (char == ":" and
                        (index + 1 == len(text) or text[index + 1] in " \t")):
                    self.fail(line)
                index += 1
            token = text[start:index].rstrip(" \t")
            if not token:
                self.fail(line)
            if key:
                return token
            return YamlScalar(token, line)

        spaces()
        if index == len(text) or text[index] == "#":
            return None
        result = value(depth)
        end = index
        spaces()
        if index < len(text) and not (text[index] == "#" and
                (index > end or text.lstrip()[0] in "\"'[{" or
                 (index > 0 and text[index - 1] in " \t"))):
            self.fail(line)
        return result

    @staticmethod
    def sequence(content: str) -> bool:
        return content == "-" or content.startswith(("- ", "-\t"))

    def mapping_entry(self, content: str, number: int) -> tuple[str, str]:
        match = re.fullmatch(r"([A-Za-z0-9_.-]+)[ \t]*:(?:[ \t]+(.*))?", content)
        if not match:
            self.fail(number)
        return match[1], match[2] or ""

    def block(self, index: int, indent: int, depth: int = 0) -> tuple[Any, int]:
        sequence = self.sequence(self.lines[index][1])
        if not sequence and not (self.lines[index][1].startswith(("? ", "?\t")) or
                                 re.match(r"[A-Za-z0-9_.-]+[ \t]*:(?:[ \t]|$)", self.lines[index][1])):
            # A nested plain scalar is valid YAML even when its eventual
            # reviewer-field schema is invalid (e.g. ``runner:[]``). Syntax
            # validation must leave that independent decision to the caller.
            return self.scalar(self.lines[index][1], self.lines[index][2], depth=depth), index + 1
        result: Any = [] if sequence else YamlBlockMapping()
        while index < len(self.lines) and self.lines[index][0] == indent:
            _, content, number = self.lines[index]
            if self.sequence(content) != sequence:
                self.fail(number)
            index += 1
            mapping_item = False
            if sequence:
                content = content[1:].lstrip(" \t")
                if self.sequence(content):
                    # A compact nested sequence is the same block grammar at
                    # the next indentation, retaining its physical source line.
                    original_index = index - 1
                    original = self.lines[original_index]
                    self.lines[original_index] = (indent + 2, content, number)
                    try:
                        item, index = self.block(index - 1, indent + 2, depth + 1)
                    finally:
                        self.lines[original_index] = original
                    result.append(item)
                    continue
                mapping_item = bool(content.startswith(("? ", "?\t")) or
                                    re.match(r"[A-Za-z0-9_.-]+[ \t]*:(?:[ \t]|$)", content))
                target: Any = YamlBlockMapping() if mapping_item else result
            else:
                target = result
            explicit = content.startswith(("? ", "?\t"))
            if not sequence or mapping_item:
                if explicit:
                    key = content[1:].strip(" \t")
                    if not re.fullmatch(r"[A-Za-z0-9_.-]+", key):
                        self.fail(number, "unsupported mapping key")
                    text = ""
                    pair_indent = indent + (2 if mapping_item else 0)
                    if index < len(self.lines) and self.lines[index][0] == pair_indent:
                        pair = self.lines[index][1]
                        if pair == ":" or pair.startswith((": ", ":\t")):
                            text = pair[1:].lstrip(" \t")
                            index += 1
                else:
                    key, text = self.mapping_entry(content, number)
                if key in target:
                    self.fail(number, "duplicate mapping key")
            else:
                key, text = "", content
            item = self.scalar(text, number, depth=depth)
            header = not text.strip(" \t") or text.lstrip(" \t").startswith("#")
            value_indent = indent + (4 if mapping_item else 2) + (2 if explicit else 0)
            if header and index < len(self.lines) and self.lines[index][0] > indent:
                if self.lines[index][0] != value_indent:
                    # List mapping continuation belongs to the item, not key.
                    if not mapping_item or self.lines[index][0] != indent + 2:
                        self.fail(self.lines[index][2])
                else:
                    item, index = self.block(index, value_indent, depth + 1)
            if not sequence or mapping_item:
                target[key] = item
                target.key_lines[key] = number
            else:
                result.append(item)
            if mapping_item:
                if index < len(self.lines) and self.lines[index][0] == indent + 2:
                    continuation, index = self.block(index, indent + 2, depth + 1)
                    if not isinstance(continuation, YamlBlockMapping):
                        self.fail(number, "duplicate or invalid mapping continuation")
                    duplicates = target.keys() & continuation.keys()
                    if duplicates:
                        self.fail(min(continuation.key_lines[key] for key in duplicates), "duplicate mapping key")
                    target.update(continuation)
                    target.key_lines.update(continuation.key_lines)
                result.append(target)
            if index < len(self.lines) and self.lines[index][0] > indent:
                self.fail(self.lines[index][2])
        return result, index

    def parse(self) -> dict[str, Any]:
        if not self.lines:
            return {}
        if self.lines[0][0] != 0 or self.sequence(self.lines[0][1]):
            self.fail(self.lines[0][2], "selected source must be a mapping")
        data, index = self.block(0, 0)
        if not isinstance(data, dict):
            self.fail(self.lines[0][2], "selected source must be a mapping")
        if index != len(self.lines):
            self.fail(self.lines[index][2])
        return data


def validate_selected_yaml(raw: str, path: Path, *, review_fields: bool = False) -> dict[str, Any]:
    """Validate all selected private bytes without a third-party parser."""
    return parse_review_yaml(path, raw=raw, review_fields=review_fields)


def validate_local_source(repo_root: Path, *, explicit: bool = False) -> Path:
    """Validate a selected source without discovering another checkout."""
    try:
        root = repo_root.resolve()
        if not root.is_dir() or not os.access(root, os.R_OK | os.X_OK):
            raise ConfigError("local-source: unreadable directory")
        path = root / LOCAL_CONFIG_NAME
        before = source_identity(path)
        if not path.exists() and not path.is_symlink():
            if explicit:
                raise ConfigError('local-source missing file')
            return retain_selected_source(path, before)
        if not path.is_file() or not os.access(path, os.R_OK):
            raise ConfigError('local-source unreadable regular file')
        if not explicit and not path.resolve().is_relative_to(root):
            raise ConfigError('local-source external indirection requires explicit selection')
        return retain_selected_source(path, before)
    except (OSError, RuntimeError) as exc:
        raise ConfigError("local-source: filesystem validation failed") from exc

def resolve_local_config(repo_root: Path) -> tuple[Path, str, Path | None]:
    """Checkout-local selection, or a validated explicit external source.

    Compatibility main-clone metadata is always empty; no Git ancestry is read.
    """
    override_root = os.environ.get("WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT", "")
    if override_root:
        path = validate_local_source(Path(override_root), explicit=True)
        return path, "override_root", None
    path = validate_local_source(repo_root)
    return path, "checkout" if selected_source_present(path) else "", None


def load_configs(repo_root: Path, *, policy: ModelPolicy | None = None) -> tuple[dict[str, Any], dict[str, Any], Path, Path]:
    if policy is not None:
        return (thaw_model_snapshot(policy.configs[0]), thaw_model_snapshot(policy.configs[1]),
                policy.shared_path, policy.local_path)
    shared_path = repo_root / ".ai-dev-workflow.yaml"
    local_path, _, _ = resolve_local_config(repo_root)
    shared = parse_yaml_subset(shared_path)
    local = parse_yaml_subset(local_path)
    return shared, local, shared_path, local_path


def mode_from_shared(shared: dict[str, Any], shared_path: Path) -> str:
    raw_mode = shared.get("mode", "single_repo")
    if raw_mode in {None, ""}:
        raw_mode = "single_repo"
    if not isinstance(raw_mode, str):
        raise ConfigError("field 'mode' must be a string")
    if raw_mode not in VALID_MODES:
        raise ConfigError("field 'mode' must be one of")
    return raw_mode


def normalize_ci_policy(raw: Any, shared_path: Path, field_path: str) -> str:
    if raw is None or raw == "":
        return "required"
    if not isinstance(raw, str):
        raise ConfigError('must be a string', key=field_path)
    value = raw.strip()
    if value not in VALID_CI_POLICIES:
        raise ConfigError('must be one of', key=field_path)
    return value


def validate_branch_name(value: str, shared_path: Path, field_path: str) -> str:
    if not isinstance(value, str) or not value:
        raise ConfigError('must be a non-empty branch name', key=field_path)
    forbidden_tokens = ["..", "@{", "//", "?", "^", "~", ":", "\\", "#"]
    if (
        value.startswith("/")
        or value.endswith("/")
        or re.search(r"\s", value)
        or any(token in value for token in forbidden_tokens)
    ):
        raise ConfigError('is not a portable branch name', key=field_path)
    for segment in value.split("/"):
        # Mirror git's ref-format component rules (see git-check-ref-format(1))
        # beyond the plain character allowlist: a component cannot start with
        # a dot, cannot end with the sequence ".lock", and cannot end with a
        # dot. Names such as "release/v1.2.3.lock", "release/v1.2.3.", or a
        # segment beginning with "." pass the character class but are
        # rejected by git as branch names.
        if (
            not segment
            or not re.match(r"^[A-Za-z0-9._-]+$", segment)
            or segment.startswith(".")
            or segment.endswith(".lock")
            or segment.endswith(".")
        ):
            raise ConfigError('is not a portable branch name', key=field_path)
    return value


def validate_release_branch_pattern(
    raw: Any,
    shared_path: Path,
    field_path: str,
    product_repo_name: str,
) -> str:
    if raw is None or raw == "":
        return "release/v{version}"
    if not isinstance(raw, str):
        raise ConfigError('must be a string', key=field_path)
    placeholders = set(re.findall(r"\{[^{}]+\}", raw))
    unknown = sorted(placeholders - {"{version}", "{product_repo}"})
    if unknown:
        raise ConfigError('contains unknown placeholder(s)', key=field_path)
    if "{version}" not in raw:
        raise ConfigError('must include the {version} placeholder', key=field_path)
    resolved = raw.replace("{version}", "1.2.3").replace("{product_repo}", product_repo_name)
    if "{" in resolved or "}" in resolved:
        raise ConfigError('contains unresolved placeholder text', key=field_path)
    validate_branch_name(resolved, shared_path, field_path)
    return raw


def normalize_release_owner(
    raw: Any,
    default: str,
    shared_path: Path,
    field_path: str,
) -> tuple[str, str]:
    if raw is None or raw == "":
        return default, "default"
    if not isinstance(raw, str):
        raise ConfigError('must be a string', key=field_path)
    value = raw.strip()
    if value not in VALID_RELEASE_OWNER_VALUES:
        raise ConfigError('must be one of', key=field_path)
    return value, "explicit"


def forbidden_release_value_paths(value: Any, prefix: str = "") -> set[str]:
    found: set[str] = set()
    if isinstance(value, dict):
        for key, child in value.items():
            key_path = f"{prefix}.{key}" if prefix else str(key)
            if key in LOCAL_ONLY_KEYS or re.search(
                r"(secret|token|credential|password|passphrase|api[_-]?key|access[_-]?key)",
                str(key),
                re.I,
            ):
                found.add(key_path)
            found.update(forbidden_release_value_paths(child, key_path))
        return found
    if isinstance(value, list):
        for index, child in enumerate(value, start=1):
            item_path = f"{prefix}[{index}]" if prefix else f"[{index}]"
            found.update(forbidden_release_value_paths(child, item_path))
        return found
    if isinstance(value, str):
        text = value.strip()
        if re.search(r"(gh[pousr]_|github_pat_|BEGIN .*PRIVATE KEY|Bearer\s+|op://)", text, re.I):
            found.add(prefix)
        elif re.match(r"^(?:/Users/|/home/|/var/|/tmp/|~/|\./|\.\./|[A-Za-z]:\\)", text):
            found.add(prefix)
    return found


def default_release_owner(mode: str, field: str) -> str:
    if mode == "single_repo":
        return "current_repo"
    if field == "tracker_reconciliation_owner":
        return "hub"
    return "product_repo"


def normalize_release_contract(
    raw: Any,
    shared_path: Path,
    field_path: str,
    mode: str,
    product_repo_name: str,
    default_branch: str,
) -> dict[str, str]:
    release = as_mapping(raw, shared_path, field_path)
    forbidden_values = sorted(forbidden_release_value_paths(release))
    if forbidden_values:
        raise ConfigError('contains forbidden local or secret fields', key=field_path)

    base_source = "explicit" if release.get("base") not in {None, ""} else "default"
    base = str(release.get("base") or default_branch)
    validate_branch_name(base, shared_path, f"{field_path}.base")

    pattern_source = "explicit" if release.get("branch_pattern") not in {None, ""} else "default"
    branch_pattern = validate_release_branch_pattern(
        release.get("branch_pattern"),
        shared_path,
        f"{field_path}.branch_pattern",
        product_repo_name,
    )

    normalized = {
        "base": base,
        "base_source": base_source,
        "branch_pattern": branch_pattern,
        "branch_pattern_source": pattern_source,
    }
    for field in RELEASE_OWNER_FIELDS:
        value, source = normalize_release_owner(
            release.get(field),
            default_release_owner(mode, field),
            shared_path,
            f"{field_path}.{field}",
        )
        normalized[field] = value
        normalized[f"{field}_source"] = source
    return normalized


def product_repos(shared: dict[str, Any], shared_path: Path) -> list[dict[str, Any]]:
    workflow_hub = as_mapping(shared.get("workflow_hub"), shared_path, "workflow_hub")
    repos = as_list(workflow_hub.get("product_repos"), shared_path, "workflow_hub.product_repos")
    normalized: list[dict[str, Any]] = []
    seen: set[str] = set()
    for index, raw in enumerate(repos, start=1):
        if not isinstance(raw, dict):
            raise ConfigError('workflow_hub.product_repos[] must be a mapping')
        forbidden = sorted(find_local_only_keys(raw))
        if forbidden:
            raise ConfigError('workflow_hub.product_repos[] contains local-only fields')
        name = raw.get("name")
        if not isinstance(name, str) or not name:
            raise ConfigError('workflow_hub.product_repos[].name is required')
        if name in seen:
            raise ConfigError('duplicate workflow_hub.product_repos name')
        seen.add(name)
        github_repo = raw.get("github_repo") or ""
        git_url = raw.get("git_url") or ""
        if not github_repo and not git_url:
            raise ConfigError('workflow_hub.product_repos[] must define github_repo or git_url')
        repo = dict(raw)
        repo["default_branch"] = repo.get("default_branch") or "main"
        validate_branch_name(
            str(repo["default_branch"]),
            shared_path,
            f"workflow_hub.product_repos[{index}].default_branch",
        )
        repo["ci_policy"] = normalize_ci_policy(
            repo.get("ci_policy"),
            shared_path,
            f"workflow_hub.product_repos[{index}].ci_policy",
        )
        repo["release_contract"] = normalize_release_contract(
            repo.get("release"),
            shared_path,
            f"workflow_hub.product_repos[{index}].release",
            "workflow_hub",
            str(repo["name"]),
            str(repo["default_branch"]),
        )
        normalized.append(repo)
    return normalized


def find_local_only_keys(value: Any, prefix: str = "") -> set[str]:
    if isinstance(value, dict):
        found: set[str] = set()
        for key, child in value.items():
            key_path = f"{prefix}.{key}" if prefix else str(key)
            if key in LOCAL_ONLY_KEYS:
                found.add(key_path)
            found.update(find_local_only_keys(child, key_path))
        return found
    if isinstance(value, list):
        found = set()
        for index, child in enumerate(value, start=1):
            item_path = f"{prefix}[{index}]" if prefix else f"[{index}]"
            found.update(find_local_only_keys(child, item_path))
        return found
    return set()


def select_product_repo(repos: list[dict[str, Any]], target: str | None, shared_path: Path) -> dict[str, Any]:
    if target:
        for repo in repos:
            if repo.get("name") == target:
                return repo
        raise ConfigError('selected workflow_hub.product_repos entry is missing')
    if not repos:
        raise ConfigError('workflow_hub.product_repos is required for workflow_hub mode')
    if len(repos) > 1:
        raise ConfigError('product repository selection is ambiguous; pass --repo')
    return repos[0]


def local_product_repo(local: dict[str, Any], local_path: Path, name: str) -> dict[str, Any]:
    repos = as_list(local.get("product_repos"), local_path, "product_repos")
    for index, raw in enumerate(repos, start=1):
        if not isinstance(raw, dict):
            raise ConfigError('product_repos[] must be a mapping')
        if raw.get("name") == name:
            return raw
    return {}


def resolve_local_path(
    local: dict[str, Any],
    local_path: Path,
    name: str,
    require_local: bool,
) -> tuple[str, str]:
    # Relative paths are anchored to the deliberately selected source directory.
    local_entry = local_product_repo(local, local_path, name)
    explicit = local_entry.get("local_path") or local_entry.get("checkout_path")
    if explicit:
        return str((local_path.parent / str(explicit)).resolve()) if not os.path.isabs(str(explicit)) else str(explicit), "local_override"
    checkout_root = local.get("checkout_root")
    if checkout_root:
        base = Path(str(checkout_root))
        if not base.is_absolute():
            base = (local_path.parent / base).resolve()
        return str(base / name), "checkout_root"
    if require_local:
        raise ConfigError('local path for selected product repo is required; set product_repos[].local_path or checkout_root')
    return "", ""


def relative_or_absolute_path(repo_root: Path, value: str) -> str:
    path = Path(value)
    if path.is_absolute():
        try:
            return os.path.relpath(path, repo_root)
        except ValueError:
            return str(path)
    return value


def quote_yaml_scalar(value: Any) -> str:
    text = str(value)
    if text == "":
        return '""'
    yaml_token = text.lower()
    if (
        yaml_token in {"true", "false", "yes", "no", "on", "off", "null", "~"}
        or re.match(r"^[+-]?[0-9]+(?:\.[0-9]+)?$", text)
    ):
        must_quote = True
    else:
        must_quote = not re.match(r"^[A-Za-z0-9_./:@~+-]+$", text)
    if not must_quote:
        return text
    escaped = text.replace("\\", "\\\\").replace("\n", "\\n").replace('"', '\\"')
    return '"' + escaped + '"'


def dump_yaml_subset(value: Any, indent: int = 0) -> list[str]:
    prefix = " " * indent
    lines: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            if isinstance(child, (dict, list)):
                lines.append(f"{prefix}{key}:")
                lines.extend(dump_yaml_subset(child, indent + 2))
            else:
                lines.append(f"{prefix}{key}: {quote_yaml_scalar(child)}")
        return lines
    if isinstance(value, list):
        for item in value:
            if isinstance(item, dict):
                if not item:
                    lines.append(f"{prefix}- {{}}")
                    continue
                first = True
                for key, child in item.items():
                    if first:
                        if isinstance(child, (dict, list)):
                            lines.append(f"{prefix}- {key}:")
                            lines.extend(dump_yaml_subset(child, indent + 4))
                        else:
                            lines.append(f"{prefix}- {key}: {quote_yaml_scalar(child)}")
                        first = False
                    else:
                        if isinstance(child, (dict, list)):
                            lines.append(f"{prefix}  {key}:")
                            lines.extend(dump_yaml_subset(child, indent + 4))
                        else:
                            lines.append(f"{prefix}  {key}: {quote_yaml_scalar(child)}")
            else:
                lines.append(f"{prefix}- {quote_yaml_scalar(item)}")
        return lines
    lines.append(f"{prefix}{quote_yaml_scalar(value)}")
    return lines


def set_local_product_repo_path(repo_root: Path, repo_name: str, local_path_value: str,
                               *, snapshot: ModelSnapshot | None = None) -> Path:
    # Writes always belong to this checkout; validate physical containment first.
    local_path = validate_local_source(repo_root)
    if snapshot is None:
        snapshot = read_model_snapshot(local_path)
    local = thaw_model_snapshot(snapshot.legacy)
    repos = as_list(local.get("product_repos"), local_path, "product_repos")
    updated = False
    match_count = 0
    normalized_path = relative_or_absolute_path(repo_root, local_path_value)

    new_repos: list[dict[str, Any]] = []
    for index, raw in enumerate(repos, start=1):
        if not isinstance(raw, dict):
            raise ConfigError('product_repos[] must be a mapping')
        repo = dict(raw)
        if repo.get("name") == repo_name:
            match_count += 1
            repo["local_path"] = normalized_path
            updated = True
        new_repos.append(repo)

    if match_count > 1:
        raise ConfigError('duplicate product_repos entries cannot be updated safely')

    if not updated:
        new_repos.append({"name": repo_name, "local_path": normalized_path})
    local["product_repos"] = new_repos

    tail = ("\n".join(dump_yaml_subset(local)) + "\n").encode("utf-8")
    envelope = snapshot.envelope
    if envelope and not envelope.endswith(b"\n"):
        envelope += b"\n"
    local_path.write_bytes(envelope + tail)
    return local_path


def flatten_tracker_hints(repo: dict[str, Any]) -> str:
    tracker = repo.get("tracker")
    if not isinstance(tracker, dict):
        return ""
    parts = []
    for key in sorted(tracker):
        value = tracker[key]
        if value not in {None, ""}:
            parts.append(f"{key}:{value}")
    return ",".join(parts)


def release_contract_context(prefix: str, release_contract: dict[str, str]) -> dict[str, str]:
    context = {
        f"{prefix}_RELEASE_BASE": release_contract.get("base", ""),
        f"{prefix}_RELEASE_BASE_SOURCE": release_contract.get("base_source", ""),
        f"{prefix}_RELEASE_BRANCH_PATTERN": release_contract.get("branch_pattern", ""),
        f"{prefix}_RELEASE_BRANCH_PATTERN_SOURCE": release_contract.get("branch_pattern_source", ""),
        f"{prefix}_RELEASE_CONTRACT_REVISION": release_contract_revision(release_contract),
    }
    for field in RELEASE_OWNER_FIELDS:
        key = f"{prefix}_RELEASE_{field.upper()}"
        context[key] = release_contract.get(field, "")
        context[f"{key}_SOURCE"] = release_contract.get(f"{field}_source", "")
    return context


def release_contract_revision(release_contract: dict[str, str]) -> str:
    revision_input = {
        "schema_version": "workflow_release_contract.v1",
        "base": release_contract.get("base", ""),
        "branch_pattern": release_contract.get("branch_pattern", ""),
    }
    for field in RELEASE_OWNER_FIELDS:
        revision_input[field] = release_contract.get(field, "")
    canonical = json.dumps(revision_input, sort_keys=True, separators=(",", ":"))
    return "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def github_repo_from_url(value: str) -> str:
    match = re.match(
        r"^(?:git@github\.com:|https://github\.com/|ssh://git@github\.com/)([^/\s]+/[^/\s]+?)(?:\.git)?/?$",
        value,
    )
    if not match:
        return ""
    return match.group(1)


def parse_remote_slug(repo_root: Path) -> str:
    git_config = repo_root / ".git" / "config"
    if not git_config.exists():
        return ""
    try:
        text = git_config.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return ""
    match = re.search(
        r"^\s*url = (?:git@github\.com:|https://github\.com/|ssh://git@github\.com/)([^/\s]+/[^/\s]+)\s*$",
        text,
        re.M,
    )
    if not match:
        return ""
    slug = match.group(1)
    return slug[:-4] if slug.endswith(".git") else slug


def nested_mapping(value: dict[str, Any], key: str) -> dict[str, Any]:
    raw = value.get(key)
    return raw if isinstance(raw, dict) else {}


def first_present(*values: Any) -> str:
    for value in values:
        if value is not None and value != "":
            return str(value)
    return ""


def resolve_auth_context(args: argparse.Namespace) -> dict[str, str]:
    repo_root = repo_root_from_args(args.repo_root)
    shared, local, shared_path, local_path = load_configs(repo_root)
    mode = mode_from_shared(shared, shared_path)
    if mode != "workflow_hub":
        return {
            "WORKFLOW_MODE": mode,
            "AUTH_STATUS": "not_required",
            "AUTH_REQUIRES_PRODUCT_REPO": "false",
            "AUTH_MESSAGE": "GitHub App product-repo auth is only required in workflow_hub mode",
        }

    repo = select_product_repo(product_repos(shared, shared_path), args.repo, shared_path)
    local_repo = local_product_repo(local, local_path, str(repo["name"]))
    shared_app = nested_mapping(repo, "github_app")
    local_app = nested_mapping(local_repo, "github_app")

    github_repo = str(repo.get("github_repo") or "")
    if not github_repo and repo.get("git_url"):
        github_repo = github_repo_from_url(str(repo.get("git_url")))

    app_id = first_present(local_app.get("app_id"), local_repo.get("app_id"), shared_app.get("app_id"))
    installation_id = first_present(
        local_app.get("installation_id"),
        local_repo.get("installation_id"),
        shared_app.get("installation_id"),
    )
    private_key_path = first_present(
        local_app.get("private_key_path"), local_repo.get("private_key_path")
    )
    secret_ref = first_present(local_app.get("secret_ref"), local_repo.get("secret_ref"))

    status = "auth_configured"
    if not app_id:
        status = "missing_app_id"
    elif not private_key_path and not secret_ref:
        status = "missing_private_key"
    elif not installation_id:
        status = "missing_installation"

    context = {
        "WORKFLOW_MODE": mode,
        "TARGET_REPO_NAME": str(repo.get("name") or ""),
        "TARGET_GITHUB_REPO": github_repo,
        "TARGET_GIT_URL": str(repo.get("git_url") or ""),
        "AUTH_STATUS": status,
        "AUTH_REQUIRES_PRODUCT_REPO": "true",
        "AUTH_APP_ID_PRESENT": "true" if app_id else "false",
        "AUTH_INSTALLATION_ID_PRESENT": "true" if installation_id else "false",
        "AUTH_PRIVATE_KEY_REF_PRESENT": "true" if (private_key_path or secret_ref) else "false",
        "AUTH_SECRET_SOURCE": (
            "private_key_path" if private_key_path else ("secret_ref" if secret_ref else "")
        ),
    }
    if args.include_local_secrets:
        context.update(
            {
                "AUTH_APP_ID": app_id,
                "AUTH_INSTALLATION_ID": installation_id,
                "AUTH_PRIVATE_KEY_PATH": private_key_path,
                "AUTH_SECRET_REF": secret_ref,
            }
        )
    return context


def resolve_context(args: argparse.Namespace, configs: tuple[Any, ...] | None = None) -> dict[str, str]:
    repo_root = repo_root_from_args(args.repo_root)
    shared, local, shared_path, local_path = configs if configs is not None else load_configs(repo_root)
    mode = mode_from_shared(shared, shared_path)
    context: dict[str, str] = {
        "WORKFLOW_MODE": mode,
        "TARGET_REPO_NAME": "",
        "TARGET_GITHUB_REPO": "",
        "TARGET_GIT_URL": "",
        "TARGET_DEFAULT_BRANCH": "",
        "TARGET_LOCAL_PATH": "",
        "TARGET_LOCAL_PATH_SOURCE": "",
        "TARGET_TRACKER_HINTS": "",
        "WORKFLOW_HUB_GITHUB_REPO": "",
        "WORKFLOW_HUB_GIT_URL": "",
    }

    if mode == "single_repo":
        default_branch = str(shared.get("default_branch") or "main")
        validate_branch_name(default_branch, shared_path, "default_branch")
        release_contract = normalize_release_contract(
            shared.get("release"),
            shared_path,
            "release",
            "single_repo",
            repo_root.name,
            default_branch,
        )
        context["TARGET_REPO_NAME"] = repo_root.name
        context["TARGET_GITHUB_REPO"] = parse_remote_slug(repo_root)
        context["TARGET_DEFAULT_BRANCH"] = default_branch
        context["TARGET_LOCAL_PATH"] = str(repo_root)
        context["TARGET_LOCAL_PATH_SOURCE"] = "current_repo"
        context.update(release_contract_context("TARGET", release_contract))
        return context

    if mode == "workflow_hub":
        repo = select_product_repo(product_repos(shared, shared_path), args.repo, shared_path)
        local_value, local_source = resolve_local_path(
            local, local_path, str(repo["name"]), bool(args.require_local)
        )
        github_repo = str(repo.get("github_repo") or "")
        if not github_repo and repo.get("git_url"):
            github_repo = github_repo_from_url(str(repo.get("git_url")))
        context.update(
            {
                "TARGET_REPO_NAME": str(repo.get("name") or ""),
                "TARGET_GITHUB_REPO": github_repo,
                "TARGET_GIT_URL": str(repo.get("git_url") or ""),
                "TARGET_DEFAULT_BRANCH": str(repo.get("default_branch") or "main"),
                "TARGET_CI_POLICY": str(repo.get("ci_policy") or "required"),
                "TARGET_LOCAL_PATH": local_value,
                "TARGET_LOCAL_PATH_SOURCE": local_source,
                "TARGET_TRACKER_HINTS": flatten_tracker_hints(repo),
            }
        )
        context.update(release_contract_context("TARGET", repo["release_contract"]))
        return context

    product_repo = as_mapping(shared.get("product_repo"), shared_path, "product_repo")
    hub = as_mapping(product_repo.get("workflow_hub"), shared_path, "product_repo.workflow_hub")
    default_branch = str(product_repo.get("default_branch") or "main")
    validate_branch_name(default_branch, shared_path, "product_repo.default_branch")
    release_contract = normalize_release_contract(
        product_repo.get("release"),
        shared_path,
        "product_repo.release",
        "product_repo",
        repo_root.name,
        default_branch,
    )
    context.update(
        {
            "TARGET_REPO_NAME": repo_root.name,
            "TARGET_GITHUB_REPO": parse_remote_slug(repo_root),
            "TARGET_DEFAULT_BRANCH": default_branch,
            "TARGET_CI_POLICY": normalize_ci_policy(
                product_repo.get("ci_policy"),
                shared_path,
                "product_repo.ci_policy",
            ),
            "TARGET_LOCAL_PATH": str(repo_root),
            "TARGET_LOCAL_PATH_SOURCE": "current_repo",
            "WORKFLOW_HUB_GITHUB_REPO": str(hub.get("github_repo") or ""),
            "WORKFLOW_HUB_GIT_URL": str(hub.get("git_url") or ""),
        }
    )
    context.update(release_contract_context("TARGET", release_contract))
    if not context["WORKFLOW_HUB_GITHUB_REPO"] and not context["WORKFLOW_HUB_GIT_URL"]:
        raise ConfigError('product_repo.workflow_hub must define github_repo or git_url in product_repo mode')
    return context


def list_override_from_path(data: dict[str, Any], path: list[str]) -> tuple[list[str], bool]:
    value: Any = data
    for key in path:
        if not isinstance(value, dict) or key not in value:
            return [], False
        value = value.get(key)
    if isinstance(value, list):
        return [str(item) for item in value], True
    return [], False


def typed_value_from_path(data: dict[str, Any], path: list[str]) -> tuple[Any, bool]:
    """Return a raw nested value and whether its final key was present."""
    value: Any = data
    for key in path:
        if not isinstance(value, dict) or key not in value:
            return None, False
        value = value[key]
    return value, True


def review_effective_value_from_path(
    data: dict[str, Any], path: list[str]
) -> tuple[Any, bool, bool]:
    """Read a review-effective field without hiding a non-mapping ancestor.

    The legacy review-overrides reader intentionally treats this shape as
    absent.  The new gate cannot: a present ``review: []`` or
    ``review.on_draft: []`` is malformed configuration and policy resolution
    must block before a shipped value can be used as a fallback.
    """
    value: Any = data
    for index, key in enumerate(path):
        if not isinstance(value, dict):
            # Empty optional review/on_draft/on_ready sections (including
            # sections that contain only comments, which the YAML subset
            # parser represents as a null value at that key) retain the
            # historic absent-field meaning. A list, scalar, or mapping in
            # the wrong position remains a structural error and cannot fall
            # through to another file.
            #
            # #1561 round-9 finding: on_ready was missing from this
            # null-parent exemption even though on_draft already had it — a
            # comment-only or null `review.on_ready:` section (a shape
            # workflow_config_review_local_list_if_declared, workflow-lib.sh,
            # does not treat as a declared override either) was misclassified
            # as a structural error, marking on_ready.github malformed and
            # exiting this preflight as a tooling failure, while Step 7
            # correctly falls back to the shared ready-stage list for that
            # exact shape.
            if value is None and (
                (index == 1 and path[:1] == ["review"])
                or (index == 2 and path[:2] == ["review", "on_draft"])
                or (index == 2 and path[:2] == ["review", "on_ready"])
            ):
                return None, False, False
            return None, False, True
        if key not in value:
            return None, False, False
        value = value[key]
    return value, True, False


def valid_reviewer_name(value: Any) -> bool:
    """Keep one decoded name equal to one trimmed Bash record, without a provider allowlist."""
    return (
        isinstance(value, str)
        and bool(value)
        and value == value.strip()
        and all(unicodedata.category(char) not in {"Cc", "Cf", "Cs", "Zl", "Zp"} for char in value)
    )


def review_runner_state(value: Any, present: bool) -> tuple[list[str], str]:
    if not present:
        return [], "absent"
    if value is None or value == []:
        return [], "empty"
    if not isinstance(value, list):
        return [], "malformed"
    if not all(valid_reviewer_name(item) for item in value):
        return [], "malformed"
    return value, "defined"


def review_runner_value(data: dict[str, Any]) -> tuple[Any, bool, bool]:
    """Resolve modern runner config before the supported legacy alias.

    A present modern key wins even when empty or malformed. Its malformed
    ancestors must also block rather than letting the alias change coverage.

    Shared/shipped runner fallback retains its separate historic rules in
    review_runner_shared_value; local lists use declared-modern precedence.
    """
    modern_raw, modern_present, modern_structure_error = review_effective_value_from_path(
        data, ["review", "on_draft", "runner"]
    )
    legacy_raw, legacy_present, legacy_structure_error = review_effective_value_from_path(
        data, ["review", "internal_reviewers"]
    )
    if modern_present or modern_structure_error:
        return modern_raw, modern_present, modern_structure_error
    return legacy_raw, legacy_present, legacy_structure_error


def review_runner_shared_value(data: dict[str, Any]) -> tuple[Any, bool, bool]:
    """Resolve the shared config's on_draft.runner list, falling back to the
    legacy ``internal_reviewers`` alias whenever the modern list emits no
    entries — absent, null, *or* an explicit empty list ``[]`` alike.

    This intentionally does NOT special-case an explicit ``on_draft.runner:
    []`` the way review_runner_value (above) treats a locally *declared*
    empty list: that "declared empty wins outright" contract is specific to
    workflow_config_review_local_list_if_declared's own local-override
    check in workflow-lib.sh, which never falls back to that same local
    file's internal_reviewers at all. The SHARED file has no such carve-out:
    workflow_config_review_on_draft_runner (workflow-lib.sh, what Step 7 /
    pr-review-loop.sh actually consults for the shared file) only ever
    inspects whether `workflow_config_review_nested_list ... on_draft
    runner | grep -q .` produced any output — true for a nonempty modern
    list, false for absent, null, AND an explicit `[]` alike — falling back
    to internal_reviewers in every one of those false cases. An earlier
    version of this function special-cased explicit `[]` to win outright
    over the legacy alias for the shared config too; that diverged from
    Step 7's real dispatch (an operator writing an explicit `on_draft.
    runner: []` alongside a still-populated `internal_reviewers` would see
    this preflight report "no reviewers configured" while Step 7 goes on to
    dispatch the legacy list anyway) — precisely the class of silent
    disagreement between the preflight and Step 7 this module exists to
    catch (#1561).
    """
    modern_raw, modern_present, modern_structure_error = review_effective_value_from_path(
        data, ["review", "on_draft", "runner"]
    )
    if modern_structure_error:
        return modern_raw, modern_present, modern_structure_error
    modern_list, modern_state = review_runner_state(modern_raw, modern_present)
    if modern_state == "malformed" or modern_list:
        return modern_raw, modern_present, modern_structure_error
    legacy_raw, legacy_present, legacy_structure_error = review_effective_value_from_path(
        data, ["review", "internal_reviewers"]
    )
    if legacy_present or legacy_structure_error:
        return legacy_raw, legacy_present, legacy_structure_error
    return modern_raw, modern_present, modern_structure_error


def review_github_legacy_derived_value(data: dict[str, Any], bucket: str) -> tuple[Any, bool, bool]:
    """Derive the legacy ``on_draft.github`` / ``on_ready.github`` list.

    Mirrors ``workflow_config_review_on_draft_github`` /
    ``workflow_config_review_on_ready_github`` in ``workflow-lib.sh``: the
    legacy top-level ``review.platforms`` / ``review.phase_after_clean``
    keys remain accepted for one transition release (AGENTS.md), and
    ``pr-review-loop.sh`` (Step 7) still dispatches reviewers resolved that
    way. Without this fallback, a downstream repository still on the legacy
    keys would see the preflight report ``passed`` while never having
    cross-checked a reviewer Step 7 goes on to run — exactly the gap this
    module exists to close (#1561).
    """
    platforms_raw, platforms_present, platforms_error = review_effective_value_from_path(
        data, ["review", "platforms"]
    )
    phase_raw, phase_present, phase_error = review_effective_value_from_path(
        data, ["review", "phase_after_clean"]
    )
    platforms_list, platforms_state = review_runner_state(platforms_raw, platforms_present)
    phase_list, phase_state = review_runner_state(phase_raw, phase_present)
    present = platforms_present or phase_present
    # A malformed leaf value (e.g. `review.platforms: coderabbit`, a scalar)
    # must propagate the same as a structurally malformed ancestor — both
    # are Decision 5's "the shared reviewer list is malformed" tooling
    # failure, not a silently-empty derived list.
    structure_error = (
        platforms_error or phase_error or platforms_state == "malformed" or phase_state == "malformed"
    )
    if structure_error:
        # An invalid selected alias is not an empty declaration. Do not derive
        # additional identities from another list while reporting malformed.
        return [], present, True
    if bucket == "on_draft_github":
        # workflow_config_review_on_draft_github only emits anything when
        # `phase_after_clean` itself has entries; an empty/absent
        # `phase_after_clean` means the legacy config never split draft from
        # ready, and the full `platforms` list belongs to on_ready.github
        # only (the `else` branch below), not to both buckets.
        derived = [entry for entry in platforms_list if entry not in phase_list] if phase_list else []
    else:
        derived = phase_list if phase_list else platforms_list
    return derived, present, structure_error


def review_github_value(data: dict[str, Any], bucket: str, path: list[str]) -> tuple[Any, bool, bool]:
    """Resolve modern ``on_draft.github`` / ``on_ready.github`` before the
    supported legacy alias.

    Unlike ``review_runner_value`` (whose present-even-if-empty precedence
    is deliberate, but only for resolve_review_effective's *local override*
    call site — see that function's own docstring; the analogous shared-
    config precedence for the runner bucket lives in
    ``review_runner_shared_value``, not here), this mirrors
    ``workflow_config_review_on_draft_github`` / ``_on_ready_github`` in
    workflow-lib.sh exactly, because *this* resolver's whole purpose is to
    report the same reviewer list Step 7 (``pr-review-loop.sh``) actually
    dispatches: those shell functions fall through to the legacy alias
    whenever the modern list emits no entries (absent **or** explicitly
    empty), not only when it is absent. A malformed modern value (wrong
    type) still wins outright — a malformed ancestor must not silently
    regain legacy coverage.
    """
    modern_raw, modern_present, modern_structure_error = review_effective_value_from_path(data, path)
    if modern_structure_error:
        return modern_raw, modern_present, modern_structure_error
    modern_list, modern_state = review_runner_state(modern_raw, modern_present)
    if modern_state == "malformed" or modern_list:
        # A malformed leaf value (e.g. a scalar instead of a list) must not
        # silently regain legacy coverage, same as a structurally malformed
        # ancestor above. A present, well-formed, non-empty list also wins
        # outright — only "nothing here" falls through.
        return modern_raw, modern_present, modern_structure_error
    legacy_raw, legacy_present, legacy_structure_error = review_github_legacy_derived_value(data, bucket)
    if legacy_present or legacy_structure_error:
        return legacy_raw, legacy_present, legacy_structure_error
    # Neither the modern key nor the legacy alias has anything to offer;
    # report the modern key's own state (absent vs. explicitly empty) rather
    # than the legacy derivation's, which is always "absent" once both of
    # its own source keys are also absent.
    return modern_raw, modern_present, modern_structure_error


def local_review_list_value(data: dict[str, Any], phase: str, key: str) -> tuple[Any, bool, bool]:
    """Local modern declarations shadow aliases, including explicit []."""
    if key == "runner":
        return review_runner_value(data)
    raw, present, invalid = review_effective_value_from_path(data, ["review", phase, key])
    if not present and not invalid:
        return review_github_legacy_derived_value(data, phase + "_github")
    return raw, present, invalid


def review_policy_state(value: Any, present: bool) -> tuple[str, Any, str]:
    if not present:
        return "", None, "absent"
    if value is None or value == "":
        return "", value, "empty"
    if not isinstance(value, str):
        return "", None, "unreadable"
    if value in {"warn", "fail-if-any-unavailable"}:
        return value, value, "defined"
    return "", None, "unsupported"


def resolve_review_effective(args: argparse.Namespace) -> dict[str, Any]:
    """Resolve the Step 7a config without collapsing parse-state distinctions."""
    repo_root = repo_root_from_args(args.repo_root)
    if not repo_root.is_dir() or not os.access(repo_root, os.R_OK | os.X_OK):
        raise ConfigError('repository root is not a readable directory')

    shared_path = repo_root / ".ai-dev-workflow.yaml"
    local_path, local_origin, main_clone_file = resolve_local_config(repo_root)
    local_file = str(local_path) if local_origin else ""
    if not local_file:
        local_origin = ""

    base = {
        "effective_runner": [],
        "effective_runner_state": "malformed",
        "effective_runner_source": "",
        "shipped_runner": [],
        "override_excluded": [],
        "effective_policy": "",
        "policy_input": None,
        "effective_policy_state": "unreadable",
        "effective_policy_source": "",
        "unreadable_file": "",
        "unreadable_detail": "",
        "local_override_file": local_file,
        "local_override_origin": local_origin,
        "local_review_override_applied": False,
        "main_clone_local_override_file": str(main_clone_file) if main_clone_file else "",
    }

    try:
        shared = parse_yaml_subset(shared_path, preserve_empty_values=True)
    except (ConfigError, UnicodeDecodeError) as exc:
        base.update({
            "effective_policy_state": "unreadable",
            "unreadable_file": "",
            "unreadable_detail": format_config_error(exc),
        })
        return base

    parse_path = local_path
    try:
        local = parse_yaml_subset(local_path, preserve_empty_values=True)
    except SourceIntegrityError:
        raise
    except (ConfigError, UnicodeDecodeError) as exc:
        base.update({
            "effective_policy_state": "unreadable",
            "unreadable_file": "",
            "unreadable_detail": format_config_error(exc),
        })
        return base

    shipped_raw, shipped_present, shipped_runner_structure_error = review_runner_shared_value(shared)
    shipped_runner, _ = review_runner_state(shipped_raw, shipped_present)
    local_runner_raw, local_runner_present, local_runner_structure_error = review_runner_value(local)
    # A bare `runner:` with nothing after it (YAML null) is not the same as
    # a declared, possibly-empty, override: workflow_config_review_
    # local_list_if_declared (workflow-lib.sh, what Step 7a actually
    # consults) only treats an inline `[...]` or an actual `- item` line as
    # declared, so a null local runner key falls through to the shared
    # list there — mirrors the same fix already applied to the GitHub
    # buckets in review-github-effective.
    local_runner_declared = local_runner_present and local_runner_raw is not None
    # A local malformed ancestor is still the source of the effective runner
    # failure. Do not report the shipped list merely because that malformed
    # local tree has no final ``runner`` key.
    runner_raw, runner_present, runner_source = (
        (local_runner_raw, local_runner_present, str(local_path))
        if local_runner_declared or local_runner_structure_error
        else (
            shipped_raw,
            shipped_present,
            str(shared_path) if shipped_present or shipped_runner_structure_error else "",
        )
    )
    effective_runner, effective_runner_state = review_runner_state(runner_raw, runner_present)

    shipped_policy_raw, shipped_policy_present, shipped_policy_structure_error = review_effective_value_from_path(
        shared, ["review", "internal_reviewers_unavailable_policy"]
    )
    local_policy_raw, local_policy_present, local_policy_structure_error = review_effective_value_from_path(
        local, ["review", "internal_reviewers_unavailable_policy"]
    )
    local_review_override_applied = (
        local_runner_declared
        or local_runner_structure_error
        or local_policy_present
        or local_policy_structure_error
    )
    policy_raw, policy_present, policy_source = (
        (local_policy_raw, True, str(local_path)) if local_policy_present else (shipped_policy_raw, shipped_policy_present, str(shared_path) if shipped_policy_present else "")
    )
    effective_policy, policy_input, effective_policy_state = review_policy_state(policy_raw, policy_present)

    runner_structure_error = local_runner_structure_error or (
        not local_runner_declared and shipped_runner_structure_error
    )
    # Policy is evaluated first, but its sibling runner tree is independent.
    # A malformed ``review.on_draft`` affects the reviewer list only; a
    # readable ``review.internal_reviewers_unavailable_policy`` still decides
    # how that malformed list is reported. A malformed shared ``review``
    # ancestor is reported by both field paths and remains policy-unreadable
    # when the local file did not replace the runner tree.
    local_structure_error = local_policy_structure_error
    policy_structure_error = (
        local_structure_error
        or (not local_policy_present and shipped_policy_structure_error)
        or (
            not local_runner_declared
            and shipped_runner_structure_error
            and shipped_policy_structure_error
        )
    )
    if runner_structure_error:
        effective_runner_state = "malformed"
    if policy_structure_error:
        effective_policy_state = "unreadable"
        policy_input = None
        effective_policy = ""
        unreadable_path = str(local_path) if local_structure_error else str(shared_path)
        base["unreadable_file"] = ""
        base["unreadable_detail"] = format_config_error(key="review")
    if effective_policy_state == "unreadable" and not policy_structure_error:
        base["unreadable_file"] = ""
        base["unreadable_detail"] = (
            "review.internal_reviewers_unavailable_policy must be a scalar string; "
            f"received {type(policy_raw).__name__}"
        )

    base.update({
        "effective_runner": effective_runner,
        "effective_runner_state": effective_runner_state,
        "effective_runner_source": runner_source,
        "shipped_runner": shipped_runner,
        "override_excluded": [entry for entry in shipped_runner if local_runner_declared and entry not in effective_runner],
        "effective_policy": effective_policy,
        "policy_input": policy_input,
        "effective_policy_state": effective_policy_state,
        "effective_policy_source": policy_source,
        "local_review_override_applied": local_review_override_applied,
    })
    return base


def resolve_review_github_effective(args: argparse.Namespace) -> dict[str, Any]:
    """Resolve per-bucket effective GitHub reviewer lists for the preflight (#1561).

    Mirrors ``resolve_review_effective``'s parse-state handling
    (absent/empty/malformed/defined) for ``review.on_draft.github`` and
    ``review.on_ready.github``, generalizing ``review_runner_value`` /
    ``review_runner_state`` (previously runner-only) to both GitHub buckets.
    Also mirrors ``workflow_config_review_on_draft_github`` /
    ``workflow_config_review_on_ready_github`` in workflow-lib.sh: when the
    **shared** config's modern nested key is absent or resolves to an empty
    list, the shared-config legacy ``review.platforms`` /
    ``review.phase_after_clean`` fallback is applied
    (``review_github_value``/``review_github_legacy_derived_value``) so a
    downstream repository still on the legacy keys (AGENTS.md: "remain
    accepted for one transition release") gets the same reviewer list here
    that Step 7 (``pr-review-loop.sh``) actually dispatches. As with
    ``workflow_config_review_local_list_if_declared``, local modern declarations
    shadow legacy aliases even when explicitly empty.
    """
    repo_root = repo_root_from_args(args.repo_root)
    if not repo_root.is_dir() or not os.access(repo_root, os.R_OK | os.X_OK):
        raise ConfigError('repository root is not a readable directory')

    shared_path = repo_root / ".ai-dev-workflow.yaml"
    local_path, local_origin, main_clone_file = resolve_local_config(repo_root)
    local_file = str(local_path) if local_origin else ""
    if not local_file:
        local_origin = ""

    buckets = {
        "on_draft_github": ["review", "on_draft", "github"],
        "on_ready_github": ["review", "on_ready", "github"],
    }
    base: dict[str, Any] = {
        "unreadable_file": "",
        "unreadable_detail": "",
        "local_override_file": local_file,
        "local_override_origin": local_origin,
        "local_review_override_applied": False,
        "main_clone_local_override_file": str(main_clone_file) if main_clone_file else "",
    }
    for bucket_key in buckets:
        base[f"effective_{bucket_key}"] = []
        base[f"effective_{bucket_key}_state"] = "malformed"
        base[f"effective_{bucket_key}_source"] = ""
        base[f"shipped_{bucket_key}"] = []
        base[f"override_excluded_{bucket_key}"] = []

    try:
        shared = parse_yaml_subset(shared_path, preserve_empty_values=True)
    except (ConfigError, UnicodeDecodeError) as exc:
        base.update({"unreadable_file": "", "unreadable_detail": format_config_error(exc)})
        return base

    parse_path = local_path
    try:
        local = parse_yaml_subset(local_path, preserve_empty_values=True)
    except SourceIntegrityError:
        raise
    except (ConfigError, UnicodeDecodeError) as exc:
        base.update({"unreadable_file": "", "unreadable_detail": format_config_error(exc)})
        return base

    local_review_override_applied = False
    for bucket_key, path in buckets.items():
        shipped_raw, shipped_present, shipped_structure_error = review_github_value(
            shared, bucket_key, path
        )
        shipped_list, _ = review_runner_state(shipped_raw, shipped_present)
        local_raw, local_present, local_structure_error = local_review_list_value(local, path[1], path[2])
        # A bare `key:` with nothing after it (YAML null) is not the same as
        # a declared, possibly-empty, override: workflow_config_review_
        # local_list_if_declared (workflow-lib.sh, what Step 7 actually
        # consults) only treats an inline `[...]` or an actual `- item` line
        # as declared, so a null local key falls through to the shared list
        # there. Treating `None` as "present" here would instead let a null
        # local key silently narrow the effective list to empty, diverging
        # from what Step 7 dispatches.
        local_declared = local_present and local_raw is not None
        raw, present, source = (
            (local_raw, local_present, str(local_path))
            if local_declared or local_structure_error
            else (
                shipped_raw,
                shipped_present,
                str(shared_path) if shipped_present or shipped_structure_error else "",
            )
        )
        effective_list, effective_state = review_runner_state(raw, present)
        structure_error = local_structure_error or (not local_declared and shipped_structure_error)
        if structure_error:
            effective_state = "malformed"
        if local_declared or local_structure_error:
            local_review_override_applied = True
        base[f"effective_{bucket_key}"] = effective_list
        base[f"effective_{bucket_key}_state"] = effective_state
        base[f"effective_{bucket_key}_source"] = source
        base[f"shipped_{bucket_key}"] = shipped_list
        base[f"override_excluded_{bucket_key}"] = [
            entry for entry in shipped_list if local_declared and entry not in effective_list
        ]

    base["local_review_override_applied"] = local_review_override_applied
    return base


def scalar_from_path(data: dict[str, Any], path: list[str]) -> str:
    value: Any = data
    for key in path:
        if not isinstance(value, dict):
            return ""
        value = value.get(key)
    return str(value) if value not in {None, ""} else ""


def resolve_local_review_config(repo_root: Path) -> tuple[Path, str, Path | None, dict[str, Any]]:
    """Return only the selected checkout-local or explicit review source."""
    local_path, origin, main_clone_file = resolve_local_config(repo_root)
    return local_path, origin, main_clone_file, parse_yaml_subset(local_path)


def resolve_review_overrides(args: argparse.Namespace) -> dict[str, str]:
    repo_root = repo_root_from_args(args.repo_root)
    local_path, local_origin, main_clone_file, local = resolve_local_review_config(repo_root)
    local = project_review_settings(local, local_path)
    local_file = str(local_path) if local_origin else ""
    if not local_file:
        local_origin = ""

    local_runner, has_local_runner = list_override_from_path(local, ["review", "on_draft", "runner"])
    runner = local_runner
    runner_source = ".ai-dev-workflow.local.yaml" if has_local_runner else ""

    local_draft_github, has_local_draft_github = list_override_from_path(
        local, ["review", "on_draft", "github"]
    )
    draft_github = local_draft_github
    draft_github_source = ".ai-dev-workflow.local.yaml" if has_local_draft_github else ""

    local_ready_github, has_local_ready_github = list_override_from_path(
        local, ["review", "on_ready", "github"]
    )
    ready_github = local_ready_github
    ready_github_source = ".ai-dev-workflow.local.yaml" if has_local_ready_github else ""

    local_policy = scalar_from_path(local, ["review", "internal_reviewers_unavailable_policy"])
    policy = local_policy
    policy_source = ".ai-dev-workflow.local.yaml" if local_policy else ""

    sources = []
    if runner_source:
        sources.append(f"runner:{runner_source}")
    if draft_github_source:
        sources.append(f"draft-github:{draft_github_source}")
    if ready_github_source:
        sources.append(f"ready-github:{ready_github_source}")
    if policy_source:
        sources.append(f"policy:{policy_source}")

    return {
        "REVIEW_ON_DRAFT_RUNNER": ",".join(runner),
        "REVIEW_ON_DRAFT_RUNNER_SOURCE": runner_source,
        "REVIEW_ON_DRAFT_GITHUB": ",".join(draft_github),
        "REVIEW_ON_DRAFT_GITHUB_SOURCE": draft_github_source,
        "REVIEW_ON_READY_GITHUB": ",".join(ready_github),
        "REVIEW_ON_READY_GITHUB_SOURCE": ready_github_source,
        "INTERNAL_REVIEWERS_UNAVAILABLE_POLICY": policy,
        "INTERNAL_REVIEWERS_UNAVAILABLE_POLICY_SOURCE": policy_source,
        "LOCAL_OVERRIDE_SOURCE": ",".join(sources),
        # Selected source identity only; compatibility ancestry metadata is empty.
        "LOCAL_OVERRIDE_FILE": local_file,
        "LOCAL_OVERRIDE_ORIGIN": local_origin,
        "MAIN_CLONE_LOCAL_OVERRIDE_FILE": str(main_clone_file) if main_clone_file else "",
    }


def print_shell_context(values: dict[str, str]) -> None:
    for key in sorted(values):
        value = values[key]
        if value == "":
            print(f"{key}=")
        else:
            print(f"{key}={shlex.quote(str(value))}")


def print_context(args: argparse.Namespace, values: dict[str, str]) -> None:
    if getattr(args, "json", False):
        print(json.dumps(values, sort_keys=True))
    else:
        print_shell_context(values)


def cmd_mode(args: argparse.Namespace) -> int:
    repo_root = repo_root_from_args(args.repo_root)
    shared, _, shared_path, _ = load_configs(repo_root)
    print_context(args, {"WORKFLOW_MODE": mode_from_shared(shared, shared_path)})
    return 0


def cmd_resolve(args: argparse.Namespace) -> int:
    print_context(args, resolve_context(args))
    return 0


def cmd_list_product_repos(args: argparse.Namespace) -> int:
    repo_root = repo_root_from_args(args.repo_root)
    shared, _, shared_path, _ = load_configs(repo_root)
    mode = mode_from_shared(shared, shared_path)
    if mode != "workflow_hub":
        raise ConfigError('workflow_hub mode is required to list product repositories')
    names = [str(repo.get("name")) for repo in product_repos(shared, shared_path)]
    if args.json:
        print(json.dumps(names))
    else:
        for name in names:
            print(name)
    return 0


def cmd_set_local_path(args: argparse.Namespace) -> int:
    repo_root = repo_root_from_args(args.repo_root)
    policy = load_model_policy(repo_root)
    shared, _, shared_path, _ = load_configs(repo_root, policy=policy)
    mode = mode_from_shared(shared, shared_path)
    if mode != "workflow_hub":
        raise ConfigError('workflow_hub mode is required to write product repository local paths')
    select_product_repo(product_repos(shared, shared_path), args.repo, shared_path)
    # Reuse selected checkout bytes, while keeping any external fallback read-only.
    snapshot = policy.snapshots[1] if policy.local_path == repo_root / LOCAL_CONFIG_NAME else None
    written = set_local_product_repo_path(repo_root, args.repo, args.local_path, snapshot=snapshot)
    print_context(args, {"LOCAL_CONFIG_PATH": str(written)})
    return 0


def cmd_auth(args: argparse.Namespace) -> int:
    print_context(args, resolve_auth_context(args))
    return 0


def cmd_review_overrides(args: argparse.Namespace) -> int:
    print_context(args, resolve_review_overrides(args))
    return 0


def cmd_review_effective(args: argparse.Namespace) -> int:
    # JSON is the sole form: a shell key/value list would lose delimiter-bearing
    # reviewer names before the availability gate can classify them.
    print(json.dumps(resolve_review_effective(args), sort_keys=True))
    return 0


def cmd_review_github_effective(args: argparse.Namespace) -> int:
    # JSON is the sole form, for the same reason as review-effective above.
    print(json.dumps(resolve_review_github_effective(args), sort_keys=True))
    return 0


# Canonical core Agent Assignments; runner-specific aliases are intentionally absent.
DSH_ROLE_TIERS = {
    "orchestrator": "economy", "item-orchestrator": "balanced",
    "automated-reviewer-loop": "economy", "product-manager": "premium",
    "spec-reviewer": "balanced", "tech-lead": "premium",
    "implementation-plan-reviewer": "balanced", "developer": "balanced",
    "code-reviewer": "balanced", "project-setup": "balanced",
    "smoke-tester": "balanced", "retrospective": "balanced",
}
DSH_TIERS = ("economy", "balanced", "premium")
DSH_ROUTE_FIELDS = ("provider", "model", "reasoning_effort")


class ModelConfigError(ConfigError):
    """Safe model diagnostic; never retain raw configuration or parser output."""

    def __init__(self, code: str, path: Path | str, field: str, message: str):
        # Error provenance is metadata-only under the current human contract.
        # Successful model resolution still returns its functional SOURCE_FILE.
        kind = "invalid YAML" if code == "invalid_yaml" else "configuration validation error"
        self.diagnostic = {"CODE": code, "FILE": "", "FIELD": safe_config_key(field),
                           "MESSAGE": format_config_error(error_type=kind, key=field)}
        super().__init__(kind, key=field)


def model_error(code: str, path: Path | str, field: str, message: str) -> None:
    raise ModelConfigError(code, path, field, message)


def model_layer(data: dict[str, Any], path: Path) -> dict[str, Any]:
    if "models" not in data:
        return {}
    models = data["models"]
    if not isinstance(models, dict):
        model_error("invalid_type", path, "models", "Expected a mapping")
    if set(models) - {"dsh"}:
        model_error("unknown_field", path, "models", "Unknown model policy field")
    if "dsh" not in models:
        return {}
    policy = models["dsh"]
    if not isinstance(policy, dict):
        model_error("invalid_type", path, "models.dsh", "Expected a mapping")
    if set(policy) - {"tiers", "roles"}:
        model_error("unknown_field", path, "models.dsh", "Unknown routing field")
    for kind, names in (("tiers", DSH_TIERS), ("roles", DSH_ROLE_TIERS)):
        entries = policy.get(kind, {})
        if not isinstance(entries, dict):
            model_error("invalid_type", path, f"models.dsh.{kind}", "Expected a mapping")
        for name, value in entries.items():
            field = f"models.dsh.{kind}"
            if name not in names:
                model_error("unknown_name", path, f"models.dsh.{kind}", "Unknown role or tier name")
            field += f".{name}"
            if kind == "roles" and isinstance(value, str):
                if value not in DSH_TIERS:
                    model_error("unknown_name", path, field, "Expected a supported tier reference")
                continue
            if not isinstance(value, dict):
                model_error("invalid_type", path, field, "Expected a route mapping")
            if set(value) - set(DSH_ROUTE_FIELDS):
                model_error("unknown_field", path, field, "Unknown route field")
            for key, scalar in value.items():
                if not isinstance(scalar, str):
                    model_error("invalid_type", path, f"{field}.{key}", "Expected a string")
                if not scalar.strip():
                    model_error("invalid_value", path, f"{field}.{key}", "Expected a nonblank string")
                if any(ord(char) < 32 or 127 <= ord(char) <= 159 or char in "\u2028\u2029" for char in scalar):
                    model_error("invalid_value", path, f"{field}.{key}", "Control characters are not permitted")
    return policy


def compose_model_maps(shared: dict[str, Any], local: dict[str, Any]) -> dict[str, Any]:
    """Pure recursive composition; strings and mappings replace one another."""
    result = {}
    for key in sorted(shared.keys() | local.keys()):
        if key in local:
            value = local[key]
            if isinstance(value, Mapping):
                base = shared.get(key, {})
                result[key] = compose_model_maps(base if isinstance(base, Mapping) else {}, value)
            else:
                result[key] = value
        else:
            value = shared[key]
            result[key] = compose_model_maps(value, {}) if isinstance(value, Mapping) else value
    return result


def model_entry_source(kind: str, name: str, shared: dict[str, Any], local: dict[str, Any],
                       shared_path: Path, local_path: Path) -> tuple[str, Path]:
    local_entries = local.get(kind, {})
    local_entry = local_entries.get(name)
    shared_entry = shared.get(kind, {}).get(name)
    # Empty map-over-map overrides contribute no fields. A declared empty
    # map replacing a reference (or creating an entry) still owns its error.
    contributes = name in local_entries and (
        bool(local_entry) or not isinstance(shared_entry, Mapping)
    )
    suffix = "role" if kind == "roles" else "tier"
    return (f"local-{suffix}", local_path) if contributes else (f"committed-{suffix}", shared_path)


MODEL_ENVELOPE_PREFIX = "# adf-models-dsh:"
MODEL_ENVELOPE_OPEN = "# adf-models-dsh: v1"
MODEL_ENVELOPE_END = "# adf-models-dsh: end"
ModelSnapshot = namedtuple("ModelSnapshot", "policy legacy envelope positions")
ModelPolicy = namedtuple("ModelPolicy", "effective shared local shared_path local_path configs positions snapshots")


def copy_model_snapshot(value: Any, *, frozen: bool) -> Any:
    """Copy containers iteratively; snapshotting must not narrow legacy depth."""
    result = [None]
    pending = [(False, value, result, 0)]
    while pending:
        finish_tuple, node, parent, key = pending.pop()
        if finish_tuple:
            parent[key] = tuple(node)
        elif isinstance(node, Mapping):
            target = {}
            parent[key] = MappingProxyType(target) if frozen else target
            pending.extend((False, item, target, child_key)
                           for child_key, item in reversed(list(node.items())))
        elif isinstance(node, (list, tuple)):
            target = [None] * len(node)
            parent[key] = target
            if frozen:
                pending.append((True, target, parent, key))
            pending.extend((False, item, target, index)
                           for index, item in reversed(list(enumerate(node))))
        else:
            parent[key] = node
    return result[0]


def freeze_model_mapping(value: Any) -> Any:
    return copy_model_snapshot(value, frozen=True)


def thaw_model_snapshot(value: Any) -> Any:
    """Give legacy consumers their original mutable container types, without IO."""
    return copy_model_snapshot(value, frozen=False)


def model_syntax_error(path: Path, line: int) -> None:
    model_error("invalid_yaml", path, "models.dsh",
                f"Unsupported strict mapping syntax at line {line}; use BR9 block mappings")


def model_scalar(text: str, path: Path, line: int) -> Any:
    """Consume one BR9 scalar, including its entire suffix/comment."""
    text = text.lstrip(" ")
    if not text or text.startswith("#"):
        return None  # a block header; children must establish its mapping
    if text[0] in "\"'":
        quote, index, result = text[0], 1, []
        while index < len(text):
            char = text[index]
            if char == quote:
                if quote == "'" and index + 1 < len(text) and text[index + 1] == "'":
                    result.append("'")
                    index += 2
                    continue
                index += 1
                break
            if char == "\\" and quote == '"':
                index += 1
                if index >= len(text) or text[index] not in ('"', "\\"):
                    model_syntax_error(path, line)
                char = text[index]
            result.append(char)
            index += 1
        else:
            model_syntax_error(path, line)
        suffix = text[index:]
        if suffix and not (suffix.startswith(" ") and
                           (not suffix.strip(" ") or suffix.lstrip(" ").startswith("#"))):
            model_syntax_error(path, line)
        return "".join(result)
    token, separator, suffix = text.partition(" ")
    if separator and suffix.strip(" ") and not suffix.lstrip(" ").startswith("#"):
        model_syntax_error(path, line)
    if token == "{}":
        return {}
    if token.lower() == "null" or token == "~":
        return None
    if token.lower() in ("true", "false"):
        return token.lower() == "true"
    if re.fullmatch(r"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?", token):
        return 0  # recognized source type; never coerce numeric route ids
    if not re.fullmatch(r"[A-Za-z0-9_./:@+\-]+", token):
        model_syntax_error(path, line)
    return token


def parse_model_mapping(lines: list[str], path: Path) -> tuple[dict[str, Any], Mapping]:
    """Finite mapping stack: no sequence/flow/reference grammar or recovery."""
    root: dict[str, Any] = {}
    stack = [(0, root, "")]
    positions: dict[str, int] = {}
    pending = None
    for line, raw in enumerate(lines, start=2):
        if any(ord(c) < 32 or 127 <= ord(c) <= 159 or c in "\u2028\u2029" for c in raw):
            model_syntax_error(path, line)
        if not raw.strip(" ") or raw.lstrip(" ").startswith("#"):
            continue
        indent = len(raw) - len(raw.lstrip(" "))
        if indent % 2:
            model_syntax_error(path, line)
        if indent > stack[-1][0]:
            if indent != stack[-1][0] + 2 or pending is None:
                model_syntax_error(path, line)
            parent, key, field = pending
            child: dict[str, Any] = {}
            parent[key] = child
            stack.append((indent, child, field))
        else:
            while indent < stack[-1][0]:
                stack.pop()
            if indent != stack[-1][0]:
                model_syntax_error(path, line)
        match = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_-]*):(?: (.*))?", raw[indent:])
        if not match:
            model_syntax_error(path, line)
        key, text = match[1], match[2] or ""
        mapping = stack[-1][1]
        if key in mapping:
            model_syntax_error(path, line)
        mapping[key] = model_scalar(text, path, line)
        field = ".".join(part for part in (stack[-1][2], key) if part)
        positions[field] = line
        # Only an absent value opens a block, never an explicit null or {}.
        pending = (mapping, key, field) if not text.strip(" ") or text.lstrip(" ").startswith("#") else None
    return root, MappingProxyType(positions)


def read_model_snapshot(path: Path, *, legacy_error: ConfigError | None = None) -> ModelSnapshot:
    """One byte read; activation is exclusively a reserved first physical line."""
    try:
        raw_bytes = capture_config_bytes(path)
    except SourceIntegrityError:
        raise
    except ConfigError:
        if legacy_error is not None:
            raise legacy_error
        raise
    if raw_bytes is None:
        if legacy_error is not None:
            raise legacy_error
        return ModelSnapshot(MappingProxyType({}), MappingProxyType({}), b"", MappingProxyType({}))
    first_bytes = raw_bytes.split(b"\n", 1)[0].rstrip(b"\r")
    active = first_bytes.startswith(MODEL_ENVELOPE_PREFIX.encode())
    bom_active = first_bytes.startswith(b"\xef\xbb\xbf" + MODEL_ENVELOPE_PREFIX.encode())
    if bom_active:
        model_error("invalid_envelope", path, "models", "Opening marker must be UTF-8 without BOM")
    # Legacy load_configs discovers the selected local source before parsing.
    # Preserve that error priority once the first-line protocol is inactive.
    if not active and legacy_error is not None:
        raise legacy_error
    try:
        raw = raw_bytes.decode("utf-8")
    except UnicodeError:
        if active:
            model_error("invalid_yaml", path, "models.dsh", "Active configuration must be UTF-8")
        raise
    if not active:
        return ModelSnapshot(MappingProxyType({}), freeze_model_mapping(parse_yaml_snapshot(raw, path)), b"", MappingProxyType({}))
    # Physical lines, not str.splitlines: Unicode separators are grammar errors.
    physical = raw.split("\n")
    lines = [line[:-1] if line.endswith("\r") else line for line in physical]
    if lines[0] != MODEL_ENVELOPE_OPEN:
        model_error("invalid_envelope", path, "models", "Expected exact v1 opening marker on first line")
    ends = [index for index, line in enumerate(lines) if line == MODEL_ENVELOPE_END]
    if len(ends) != 1:
        model_error("invalid_envelope", path, "models", "Expected exactly one closing marker")
    end = ends[0]
    if any(line.startswith(MODEL_ENVELOPE_PREFIX) for line in lines[1:end] + lines[end + 1:]):
        model_error("invalid_envelope", path, "models", "Additional reserved markers are not permitted")
    data, positions = parse_model_mapping(lines[1:end], path)
    if "models" not in data:
        model_error("invalid_envelope", path, "models", "Envelope requires one root models mapping")
    projection = "\n" * (end + 1) + "\n".join(physical[end + 1:])
    try:
        legacy = parse_yaml_snapshot(projection, path)
    except (ConfigError, RecursionError):
        model_error("invalid_yaml", path, "models.dsh", "Invalid legacy region after policy envelope")
    if "models" in legacy:
        model_error("invalid_envelope", path, "models", "Legacy region must not supply root models")
    if set(data) != {"models"}:
        model_error("unknown_field", path, "models", "Unknown root policy field")
    policy = model_layer(data, path)
    # split with keepends retains the original opener, policy and end bytes.
    envelope = b"".join(raw_bytes.splitlines(keepends=True)[:end + 1])
    return ModelSnapshot(freeze_model_mapping(policy), freeze_model_mapping(legacy), envelope, positions)


def load_model_policy(repo_root: Path) -> ModelPolicy:
    """The sole reader/validator for validate, model-route and model-routes."""
    shared_path = repo_root / ".ai-dev-workflow.yaml"
    discovery_error = None
    try:
        local_path, _, _ = resolve_local_config(repo_root)
    except ConfigError as exc:
        discovery_error = exc
        local_path = repo_root / LOCAL_CONFIG_NAME
    shared_snapshot = read_model_snapshot(shared_path, legacy_error=discovery_error)
    if discovery_error is not None:
        model_error("config_discovery", repo_root / LOCAL_CONFIG_NAME, "models.dsh", "Local override source is unavailable")
    local_snapshot = read_model_snapshot(local_path)
    shared, local = shared_snapshot.policy, local_snapshot.policy
    effective = compose_model_maps(shared, local)
    for kind in ("tiers", "roles"):
        for name, value in effective.get(kind, {}).items():
            _, path = model_entry_source(kind, name, shared, local, shared_path, local_path)
            field = f"models.dsh.{kind}.{name}"
            if isinstance(value, str):
                if value not in effective.get("tiers", {}):
                    model_error("dangling_reference", path, field, "Referenced tier has no configured route")
            elif not all(key in value for key in ("provider", "model")):
                model_error("incomplete_route", path, field, "Effective route requires provider and model")
    return ModelPolicy(freeze_model_mapping(effective), shared, local, shared_path, local_path,
                       (shared_snapshot.legacy, local_snapshot.legacy, shared_path, local_path),
                       (shared_snapshot.positions, local_snapshot.positions),
                       (shared_snapshot, local_snapshot))


def model_resolution(policy: tuple[Any, ...], role: str = "", tier: str = "") -> dict[str, str]:
    if role and role not in DSH_ROLE_TIERS:
        model_error("unknown_role", "", "role", "Unknown workflow role")
    if tier and tier not in DSH_TIERS:
        model_error("unknown_tier", "", "tier", "Unknown model tier")
    if not role and not tier:
        model_error("missing_query", "", "role/tier", "Specify a role or tier")
    effective, shared, local, shared_path, local_path = policy[:5]
    selected_tier = tier or DSH_ROLE_TIERS[role]
    entry = effective.get("roles", {}).get(role)
    kind, name = "roles", role
    if entry is None or isinstance(entry, str):
        selected_tier = entry if isinstance(entry, str) else selected_tier
        kind, name = "tiers", selected_tier
        entry = effective.get("tiers", {}).get(selected_tier)
    else:
        selected_tier = ""
    result = {"ROLE": role, "TIER": selected_tier, "PROVIDER": "", "MODEL": "",
              "REASONING_EFFORT": "", "SOURCE": "inherited", "SOURCE_FILE": ""}
    if entry is not None:
        source, path = model_entry_source(kind, name, shared, local, shared_path, local_path)
        result.update({"PROVIDER": entry["provider"], "MODEL": entry["model"],
                       "REASONING_EFFORT": entry.get("reasoning_effort", ""),
                       "SOURCE": source, "SOURCE_FILE": str(path)})
    return result


def cmd_model_route(args: argparse.Namespace) -> int:
    if args.runner != "dsh":
        model_error("unsupported_runner", "", "runner", "Only dsh routing is supported")
    result = model_resolution(load_model_policy(repo_root_from_args(args.repo_root)),
                              args.role or "", args.tier or "")
    print_context(args, result)
    return 0


def cmd_model_routes(args: argparse.Namespace) -> int:
    if args.runner != "dsh":
        model_error("unsupported_runner", "", "runner", "Only dsh routing is supported")
    policy = load_model_policy(repo_root_from_args(args.repo_root))
    records = [model_resolution(policy, role=role) for role in DSH_ROLE_TIERS]
    records += [model_resolution(policy, tier=tier) for tier in DSH_TIERS]
    tuples = sorted({(r["PROVIDER"], r["MODEL"], r["REASONING_EFFORT"])
                     for r in records if r["SOURCE"] != "inherited"})
    routes = [dict(zip(("PROVIDER", "MODEL", "REASONING_EFFORT"), values)) for values in tuples]
    if args.json:
        print(json.dumps({"ROUTES": routes, "RESOLUTIONS": records}, sort_keys=True))
    else:
        output = {"ROUTE_COUNT": str(len(routes)), "RESOLUTION_COUNT": str(len(records))}
        for group, items in (("ROUTE", routes), ("RESOLUTION", records)):
            for index, item in enumerate(items):
                output.update({f"{group}_{index}_{key}": value for key, value in item.items()})
        print_shell_context(output)
    return 0


def cmd_validate(args: argparse.Namespace) -> int:
    policy = load_model_policy(repo_root_from_args(args.repo_root))
    configs = (thaw_model_snapshot(policy.configs[0]), thaw_model_snapshot(policy.configs[1]),
               policy.shared_path, policy.local_path)
    print_context(args, resolve_context(args, configs))
    return 0


def project_review_settings(data: dict[str, Any], path: Path) -> dict[str, Any]:
    """Select precedence first, then validate only fields crossing the handoff."""
    review: dict[str, Any] = {}

    def selected_list(raw: Any, present: bool, invalid: bool, field: str) -> list[str] | None:
        values, state = review_runner_state(raw, present)
        if invalid or state == "malformed":
            raise ConfigError('invalid reviewer-field schema', key=field)
        return values if present and raw is not None else None

    raw, present, invalid = review_runner_value(data)
    runner = selected_list(raw, present, invalid, "review.on_draft.runner")
    if runner is not None:
        review.setdefault("on_draft", {})["runner"] = runner
    for phase in ("on_draft", "on_ready"):
        raw, present, invalid = local_review_list_value(data, phase, "github")
        values = selected_list(raw, present, invalid, f"review.{phase}.github")
        if values is not None:
            review.setdefault(phase, {})["github"] = values
    field = "internal_reviewers_unavailable_policy"
    raw, present, invalid = review_effective_value_from_path(data, ["review", field])
    _, _, state = review_policy_state(raw, present)
    if invalid or state in ("unreadable", "unsupported"):
        raise ConfigError('invalid reviewer-field schema: review.', key=field)
    if present:
        review[field] = raw
    return {"review": review} if review else {}


def dump_review_projection(data: dict[str, Any], indent: int = 0) -> list[str]:
    """Serialize the validated allowlist without collapsing explicit empty lists."""
    lines: list[str] = []
    prefix = " " * indent
    for key, value in data.items():
        if isinstance(value, dict):
            lines.append(f"{prefix}{key}:")
            lines.extend(dump_review_projection(value, indent + 2))
        elif isinstance(value, list):
            if not value:
                lines.append(f"{prefix}{key}: []")
            else:
                lines.append(f"{prefix}{key}:")
                lines.extend(f"{prefix}  - {json.dumps(item)}" for item in value)
        else:
            lines.append(f"{prefix}{key}: {json.dumps(value)}")
    return lines


def cmd_review_snapshot(args: argparse.Namespace) -> int:
    root = repo_root_from_args(args.repo_root)
    path, origin, _ = resolve_local_config(root)
    projection: dict[str, Any] = {}
    if origin:
        # One source read; parser and schema projection share these exact bytes.
        try:
            raw = capture_config_text(path, required=True)
        except UnicodeError as exc:
            raise ConfigError('review-snapshot source unreadable') from exc
        projection = project_review_settings(validate_selected_yaml(raw, path, review_fields=True), path)
    destination = Path(args.destination)
    staged = destination / LOCAL_CONFIG_NAME
    temporary: str | None = None
    if staged.exists() or staged.is_symlink():
        raise ConfigError("review-snapshot: destination already contains a local projection")
    if projection:
        try:
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=destination,
                                             prefix=".review-projection-", delete=False) as stream:
                temporary = stream.name
                os.chmod(temporary, 0o600)
                stream.write("\n".join(dump_review_projection(projection)) + "\n")
            os.replace(temporary, staged)
            temporary = None
        except OSError as exc:
            raise ConfigError("review-snapshot: atomic staging failed") from exc
        finally:
            if temporary is not None:
                Path(temporary).unlink(missing_ok=True)
    print(json.dumps({"LOCAL_OVERRIDE_FILE": str(path) if origin else "",
                      "LOCAL_OVERRIDE_ORIGIN": origin,
                      "MAIN_CLONE_LOCAL_OVERRIDE_FILE": "",
                      "STAGED_OVERRIDE_FILE": str(staged) if projection else ""}, sort_keys=True))
    return 0


def cmd_local_source(args: argparse.Namespace) -> int:
    path, _, _ = resolve_local_config(repo_root_from_args(args.repo_root))
    parse_yaml_subset(path)
    print(path)
    return 0


def coderabbit_policy_from_snapshot(raw: bytes) -> str:
    """Run the existing lexical extractor on captured stdin, never a pathname.

    Retain POSIX AWK's locale/whitespace/quote behavior exactly; Python scalar
    decoding or Unicode trimming would change the existing policy contract.
    """
    program = r"""
        function trim(v) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
          gsub(/^["']|["']$/, "", v)
          return v
        }
        /^review:[[:space:]]*$/ { in_review=1; next }
        in_review && /^[^[:space:]#].*:[[:space:]]*/ { in_review=0 }
        in_review && /^[[:space:]][[:space:]]coderabbit_cli:[[:space:]]*$/ { in_cli=1; next }
        in_cli && /^[[:space:]][[:space:]][^[:space:]#].*:[[:space:]]*/ { in_cli=0 }
        in_cli && /^[[:space:]][[:space:]][[:space:]][[:space:]]rate_limit_policy:[[:space:]]*/ {
          line = $0
          sub(/^[[:space:]]*rate_limit_policy:[[:space:]]*/, "", line)
          sub(/[[:space:]]+#.*$/, "", line)
          print trim(line)
          exit
        }
"""
    try:
        result = subprocess.run(['awk', program], input=raw, capture_output=True)
    except OSError as exc:
        raise ConfigError('configuration validation error') from exc
    if result.returncode:
        raise ConfigError('configuration validation error')
    # Match Bash command substitution, which removes trailing newlines only.
    return result.stdout.rstrip(b'\n').decode('utf-8')


def read_coderabbit_policy(path: Path) -> str:
    selected = _SELECTED_SOURCES.get(id(path))
    if not (selected and selected[0] is path) and not path.is_file():
        return ''
    raw = capture_config_bytes(path)
    if raw is None:
        return ''
    validate_selected_yaml(raw.decode('utf-8').replace('\r\n', '\n').replace('\r', '\n'), path)
    return coderabbit_policy_from_snapshot(raw)


def cmd_coderabbit_policy(args: argparse.Namespace) -> int:
    # The selected source is captured and consumed here; no pathname is handed
    # back to Bash for an unprotected second private-source read.
    if args.file is not None:
        value = read_coderabbit_policy(Path(args.file))
    else:
        path, _, _ = resolve_local_config(repo_root_from_args(args.repo_root))
        value = read_coderabbit_policy(path)
        if not value:
            value = read_coderabbit_policy(Path(args.shared_file))
    print(value, end='')
    return 0


def cmd_yaml_source_check(args: argparse.Namespace) -> int:
    path = Path(args.file)
    try:
        raw = capture_config_text(path, required=True)
    except UnicodeError as exc:
        raise ConfigError('selected source unreadable') from exc
    validate_selected_yaml(raw, path)
    return 0


def read_review_list_source(path: Path) -> dict[str, Any]:
    """Decode reviewer scalars with the existing framework parser; no PyYAML dependency."""
    try:
        raw = capture_config_text(path)
    except UnicodeError as exc:
        raise ConfigError('selected source unreadable') from exc
    if raw is None:
        return {}
    return validate_selected_yaml(raw, path, review_fields=True)


def selected_review_list(data: dict[str, Any], phase: str, key: str, *, shared: bool = False) -> tuple[list[str], bool]:
    if shared:
        raw, present, invalid = (
            review_runner_shared_value(data) if key == "runner" else
            review_github_value(data, phase + "_github", ["review", phase, key])
        )
    else:
        raw, present, invalid = local_review_list_value(data, phase, key)
    values, state = review_runner_state(raw, present)
    if invalid or state == "malformed":
        raise ConfigError('invalid reviewer-field schema', key=f"review.{phase}.{key}")
    return values, present and raw is not None


def cmd_review_list(args: argparse.Namespace) -> int:
    """Resolve local precedence before decoding/emitting a complete shared list."""
    if args.apply_local:
        path, _, _ = resolve_local_config(repo_root_from_args(args.repo_root))
        values, declared = selected_review_list(read_review_list_source(path), args.phase, args.key)
        if declared:
            for item in values:
                print(item)
            return 0
    values, _ = selected_review_list(read_review_list_source(Path(args.shared_file)), args.phase, args.key, shared=True)
    for item in values:
        print(item)
    return 0


def cmd_review_local_list(args: argparse.Namespace) -> int:
    path, _, _ = resolve_local_config(repo_root_from_args(args.repo_root))
    values, declared = selected_review_list(read_review_list_source(path), args.phase, args.key)
    if not declared:
        return 1
    for item in values:
        print(item)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = DiagnosticArgumentParser(description="Resolve AI workflow repository context")
    subcommands = parser.add_subparsers(dest="command", required=True)

    policy = subcommands.add_parser("coderabbit-policy", help="read policy from one validated source capture")
    policy.add_argument("--repo-root")
    policy.add_argument("--shared-file", default="")
    policy.add_argument("--file")
    policy.set_defaults(func=cmd_coderabbit_policy)

    yaml_check = subcommands.add_parser("yaml-source-check", help="validate selected YAML before legacy field extraction")
    yaml_check.add_argument("--file", required=True)
    yaml_check.set_defaults(func=cmd_yaml_source_check)

    snapshot = subcommands.add_parser("review-snapshot", help="stage validated review-only local settings")
    snapshot.add_argument("--repo-root")
    snapshot.add_argument("--destination", required=True)
    snapshot.set_defaults(func=cmd_review_snapshot)

    redactor = subcommands.add_parser("redact-text", help="sanitize diagnostic stdin without reading configuration")
    redactor_format = redactor.add_mutually_exclusive_group()
    redactor_format.add_argument("--json", action="store_true", help="sanitize JSON string values, preserving structure")
    redactor_format.add_argument("--kv", action="store_true", help="sanitize NUL-framed diagnostic key/value pairs independently")
    redactor_format.add_argument("--kv-pair", action="store_true", help="sanitize one arbitrary NUL-framed diagnostic pair")
    redactor_format.add_argument("--kv-escaped", action="store_true", help="sanitize and escape one arbitrary NUL-framed diagnostic pair")
    redactor.set_defaults(func=cmd_redact_text)

    source = subcommands.add_parser("local-source", help="validate and print selected local source")
    source.add_argument("--repo-root")
    source.set_defaults(func=cmd_local_source)
    local_list = subcommands.add_parser("review-local-list", help="read a declared local review list")
    local_list.add_argument("--repo-root")
    local_list.add_argument("--phase", choices=("on_draft", "on_ready"), required=True)
    local_list.add_argument("--key", choices=("runner", "github"), required=True)
    local_list.set_defaults(func=cmd_review_local_list)

    review_list = subcommands.add_parser("review-list", help="emit decoded validated effective reviewer names")
    review_list.add_argument("--repo-root")
    review_list.add_argument("--shared-file", required=True)
    review_list.add_argument("--apply-local", action="store_true")
    review_list.add_argument("--phase", choices=("on_draft", "on_ready"), required=True)
    review_list.add_argument("--key", choices=("runner", "github"), required=True)
    review_list.set_defaults(func=cmd_review_list)

    mode = subcommands.add_parser("mode", help="print the effective workflow mode")
    mode.add_argument("--repo-root")
    mode.add_argument("--json", action="store_true", help="print JSON instead of shell KEY=value")
    mode.set_defaults(func=cmd_mode)

    for name in ("resolve", "validate"):
        command = subcommands.add_parser(name, help=f"{name} repository context")
        command.add_argument("--repo-root")
        command.add_argument("--repo", help="stable product repository name")
        command.add_argument(
            "--require-local",
            action="store_true",
            help="require a resolved local product checkout path",
        )
        command.add_argument("--json", action="store_true", help="print JSON instead of shell KEY=value")
        command.set_defaults(func=cmd_validate if name == "validate" else cmd_resolve)

    list_product_repos = subcommands.add_parser(
        "list-product-repos", help="list configured workflow_hub product repository names"
    )
    list_product_repos.add_argument("--repo-root")
    list_product_repos.add_argument("--json", action="store_true", help="print JSON instead of one name per line")
    list_product_repos.set_defaults(func=cmd_list_product_repos)

    set_local_path = subcommands.add_parser(
        "set-local-path", help="write one product repository local path to local config"
    )
    set_local_path.add_argument("--repo-root")
    set_local_path.add_argument("--repo", required=True, help="stable product repository name")
    set_local_path.add_argument("--local-path", required=True, help="local checkout path to write")
    set_local_path.add_argument("--json", action="store_true", help="print JSON instead of shell KEY=value")
    set_local_path.set_defaults(func=cmd_set_local_path)

    auth = subcommands.add_parser("auth", help="print product repository auth metadata")
    auth.add_argument("--repo-root")
    auth.add_argument("--repo", help="stable product repository name")
    auth.add_argument(
        "--include-local-secrets",
        action="store_true",
        help="include local secret references for machine callers; do not use for normal logs",
    )
    auth.add_argument("--json", action="store_true", help="print JSON instead of shell KEY=value")
    auth.set_defaults(func=cmd_auth)

    overrides = subcommands.add_parser("review-overrides", help="print local review override values")
    overrides.add_argument("--repo-root")
    overrides.add_argument("--json", action="store_true", help="print JSON instead of shell KEY=value")
    overrides.set_defaults(func=cmd_review_overrides)

    effective = subcommands.add_parser(
        "review-effective", help="print effective Step 7a reviewer configuration as JSON"
    )
    effective.add_argument("--repo-root")
    effective.set_defaults(func=cmd_review_effective)

    github_effective = subcommands.add_parser(
        "review-github-effective",
        help="print effective on_draft.github / on_ready.github reviewer configuration as JSON",
    )
    github_effective.add_argument("--repo-root")
    github_effective.set_defaults(func=cmd_review_github_effective)
    for name, func in (("model-route", cmd_model_route), ("model-routes", cmd_model_routes)):
        command = subcommands.add_parser(name, help="inspect read-only DSH model routing")
        command.add_argument("--runner", required=True)
        command.add_argument("--repo-root")
        command.add_argument("--json", action="store_true")
        if name == "model-route":
            command.add_argument("--role")
            command.add_argument("--tier")
        command.set_defaults(func=func)
    return parser


def main(argv: list[str]) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.func(args))
    except ModelConfigError as exc:
        print(json.dumps(exc.diagnostic, sort_keys=True), file=sys.stderr)
        return 2
    except (ConfigError, UnicodeError) as exc:
        detail = format_config_error(exc)
        print(f"ERROR: {detail}", file=sys.stderr)
        return 2
    except (OSError, ValueError, TypeError, KeyError, AttributeError, RecursionError) as exc:
        # Unexpected malformed shapes previously exited 1 via a traceback.
        # Retain that status while containing their diagnostic representation.
        print("ERROR: " + format_config_error(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

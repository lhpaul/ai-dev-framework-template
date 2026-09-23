#!/usr/bin/env bash
# covers: .cursor/commands/run-item.md .cursor/commands/run-item-work.md .cursor/commands/run-items.md .cursor/commands/run-epic.md .cursor/commands/run-work.md
# covers: .claude/commands/run-item.md .claude/commands/run-item-work.md .claude/commands/run-items.md .claude/commands/run-epic.md .claude/commands/run-work.md
# covers: .agents/skills/run-item/SKILL.md .agents/skills/run-item-work/SKILL.md .agents/skills/run-items/SKILL.md .agents/skills/run-epic/SKILL.md .agents/skills/run-work/SKILL.md
# covers: .cursor/agents/orchestrator.md .cursor/agents/item-orchestrator.md .claude/agents/orchestrator.md .claude/agents/item-orchestrator.md
# covers: .codex/skills/workflow-orchestrator/SKILL.md .codex/skills/workflow-item-orchestrator/SKILL.md
# covers: docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/95-run-epic-protocol.md
# covers: docs/workflow/development-workflow/guardrails-enforcement.md docs/workflow/development-workflow/agent-model-config.md
# covers: docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md .cursor/rules/workflow.mdc
# covers: docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md
# covers: scripts/development-workflow/tests/fixtures/cursor-dispatch-profile-surfaces/**
# covers: docs/testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md
#
# Regression guard for the Cursor dispatch-profile mirror-content contract
# (item #1462). Verifies every bounded-command mirror, role agent, Codex
# workflow skill, protocol, agent-model-config.md, and workflow.mdc carries
# the required declaration-contract clauses (E1-E6) and stop-condition
# tokens; that the canonical doc carries its own structural requirements
# (including the Decision 7 per-command dispatch table); that Protocol
# 90/91/95 carry their Decision-7 exact-text insertions; that
# agent-model-config.md carries the full profile/evidence-marker and
# model-assignment tables; that the explicit-list format string stays in
# parity across the canonical guide, guardrails-enforcement.md, Protocol 90,
# and the merged spec; and, under `--self-test`, that the scanner primitives
# themselves (fence/indented-code/inline-construct stripping, boundary-aware
# identifier matching, block splitting, UTF-8 validity, and the
# router-serialization contract) behave correctly against the full 158-row
# fixture manifest from the implementation plan
# (docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/
# 2_1462-cursor-dispatch-profiles_implementation-plan.md, Fixture manifest
# section).
#
# Note on `simulate_bounded_paths` scope: neither the merged spec's
# Decision-Gate Consistency Matrix nor the canonical doc's Decision-gate
# table carries a machine-parseable row or scenario identifier (rows are
# distinguished only by multi-sentence prose, matched positionally per the
# plan's own "Row identities (spec order)" note). The real-surface check
# below is therefore scoped to what is provably checkable per the Parser-Risk
# Addendum's token/phrase rules: Decision-gate row-count parity between the
# spec and the canonical doc, and presence of all three named stop strings in
# the canonical doc. The full per-scenario C1-C4/S1-S19 mapping LOGIC is
# implemented and proven at the fixture level (sim-*/serialization-* fixtures
# 60-68 and 147-148, MANIFEST rows, `--self-test`) against a synthetic
# labeled table; extending that per-scenario granularity to the real,
# unlabeled prose tables would require brittle whole-paragraph exact-text
# matching outside the addendum's scope and is intentionally not implemented
# here (see the PR description's proof-cycle log for the corresponding
# narrow exception on plan proof cycle 16's real-surface sub-scope).
#
# Usage:
#   test-cursor-dispatch-profile-surfaces.sh              # check real repo surfaces
#   test-cursor-dispatch-profile-surfaces.sh --self-test   # run scanner fixtures
#   test-cursor-dispatch-profile-surfaces.sh --write-fixtures  # (re)write fixtures only
set -euo pipefail
ROOT=${SURFACE_ROOT:-"$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"}
MODE="${1:-}"
python3 - "$ROOT" "$MODE" <<'PY'
import os, re, sys

ROOT = sys.argv[1]
MODE = sys.argv[2] if len(sys.argv) > 2 else ""


# ---- from primitives.py ----
import re

# ---------------------------------------------------------------------------
# R2: fences
# ---------------------------------------------------------------------------

def strip_fences(text):
    lines = text.split("\n")
    idx = 0
    fence_char = None
    fence_len = 0
    in_fence = False
    out = []
    while idx < len(lines):
        line = lines[idx]
        stripped = line.lstrip(" ")
        indent = len(line) - len(stripped)
        # tabs count as indentation too when leading (treat as >3 to be safe: a
        # leading tab is >= 4 columns, never a valid fence indent)
        if line[:1] == "\t":
            indent = 4
        if not in_fence:
            m = re.match(r'^(`{3,}|~{3,})(.*)$', stripped)
            if indent <= 3 and m and not (m.group(1)[0] == '`' and '`' in m.group(2)):
                fence_char = m.group(1)[0]
                fence_len = len(m.group(1))
                in_fence = True
                out.append("")
                idx += 1
                continue
            out.append(line)
            idx += 1
        else:
            m = re.match(r'^(`{3,}|~{3,})\s*$', stripped)
            if indent <= 3 and m and m.group(1)[0] == fence_char and len(m.group(1)) >= fence_len:
                in_fence = False
                out.append("")
                idx += 1
                continue
            out.append("")
            idx += 1
    return "\n".join(out)


def strip_html_comments(text):
    text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
    text = re.sub(r'<!--.*$', '', text, flags=re.S)
    return text


# ---------------------------------------------------------------------------
# R2b: indented code blocks
# ---------------------------------------------------------------------------

LIST_MARKER_RE = re.compile(r'^(\s{0,3})([-*+]|\d{1,9}[.)])(\s+)')


def _line_indent(line):
    if line.startswith("\t"):
        return 4 + _line_indent(line[1:])
    stripped = line.lstrip(" ")
    return len(line) - len(stripped)


BQ_LINE_RE = re.compile(r'^(\s{0,3}>)( ?)(.*)$')


def strip_indented_code(text):
    """Public entry: unwrap blockquote runs (dequote, recurse, requote) so
    indented code inside a blockquote is detected relative to the quote's own
    content, then run the flat algorithm on the rest."""
    lines = text.split("\n")
    out_lines = []
    i = 0
    n = len(lines)
    while i < n:
        if BQ_LINE_RE.match(lines[i]):
            j = i
            inner = []
            markers = []
            while j < n:
                m = BQ_LINE_RE.match(lines[j])
                if not m:
                    break
                markers.append(m.group(1) + (m.group(2) or " "))
                inner.append(m.group(3))
                j += 1
            inner_text = "\n".join(inner)
            inner_stripped = strip_indented_code(inner_text)
            inner_lines = inner_stripped.split("\n")
            for k, il in enumerate(inner_lines):
                marker = markers[k] if k < len(markers) else "> "
                out_lines.append((marker + il) if il else marker.rstrip())
            i = j
            continue
        out_lines.append(lines[i])
        i += 1
    return _flat_strip_indented_code("\n".join(out_lines))


def _flat_strip_indented_code(text):
    lines = text.split("\n")
    out = []
    n = len(lines)
    list_offset = None
    prev_was_blank = True   # start of file counts as "after blank"
    prev_was_prose_continuable = False  # previous non-blank line was plain prose text
    in_code_block = False
    i = 0
    while i < n:
        line = lines[i]
        blank = (line.strip() == "")
        indent = _line_indent(line)

        m = LIST_MARKER_RE.match(line)
        if m and not blank:
            list_offset = len(m.group(1)) + len(m.group(2)) + len(m.group(3))
        elif blank:
            pass
        elif indent < (list_offset or 0):
            list_offset = None

        threshold = 4 + (list_offset or 0)
        list_item_prose_offset = list_offset if list_offset is not None else None

        if blank:
            if in_code_block:
                out.append("")
            else:
                out.append(line)
            prev_was_blank = True
            i += 1
            continue

        is_heading_or_hr = bool(re.match(r'^(#{1,6})(\s|$)', line)) or bool(re.match(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$', line))

        if in_code_block:
            if indent >= 4:
                out.append("")
                prev_was_blank = False
                i += 1
                continue
            else:
                in_code_block = False
                # fall through to normal handling below

        if list_item_prose_offset is not None and indent == list_item_prose_offset:
            out.append(line)
            prev_was_blank = False
            prev_was_prose_continuable = True
            i += 1
            continue

        if indent >= threshold:
            is_paragraph_continuation = (not prev_was_blank) and prev_was_prose_continuable
            if is_paragraph_continuation:
                out.append(line)
                prev_was_blank = False
                prev_was_prose_continuable = True
                i += 1
                continue
            in_code_block = True
            out.append("")
            prev_was_blank = False
            prev_was_prose_continuable = False
            i += 1
            continue

        out.append(line)
        prev_was_blank = False
        prev_was_prose_continuable = not is_heading_or_hr
        i += 1

    return "\n".join(out)


# ---------------------------------------------------------------------------
# R2c: disallowed inline constructs
# ---------------------------------------------------------------------------

def strip_disallowed_constructs(text):
    lines = text.split("\n")
    out_lines = []
    for line in lines:
        if re.match(r'^\s{0,3}\[[^\]]+\]:\s*\S', line):
            out_lines.append("")
            continue
        out_lines.append(line)
    text = "\n".join(out_lines)

    text = re.sub(r'<pre\b[^>]*>.*?</pre>', '', text, flags=re.S | re.I)
    text = re.sub(r'<code\b[^>]*>.*?</code>', '', text, flags=re.S | re.I)

    text = re.sub(r'<[a-zA-Z][a-zA-Z0-9+.-]*:[^ <>]+>', '', text)
    text = re.sub(r'<[^ <>]+@[^ <>]+>', '', text)

    text = re.sub(r'!\[[^\]]*\]\([^)]*\)', '', text)
    text = re.sub(r'\[([^\]]*)\]\(([^)]*)\)', r'\1', text)

    text = re.sub(r'</?[a-zA-Z][a-zA-Z0-9-]*(\s[^<>]*)?>', '', text)

    return text


# ---------------------------------------------------------------------------
# inline code spans (identifier vs prose treatment)
# ---------------------------------------------------------------------------

CODE_SPAN_RE = re.compile(r'`([^`\n]+)`')


def strip_code_span_content(text):
    """Remove inline code span content entirely (prose-phrase view)."""
    return CODE_SPAN_RE.sub('', text)


def unwrap_code_spans(text):
    """Strip backticks, keep content (identifier-token view)."""
    return CODE_SPAN_RE.sub(lambda m: m.group(1), text)


# ---------------------------------------------------------------------------
# R3: blocks
# ---------------------------------------------------------------------------

def blocks(text):
    raw_blocks = re.split(r'\n\s*\n', text)
    out = []
    for b in raw_blocks:
        b = b.strip("\n")
        if not b.strip():
            continue
        non_empty = [l for l in b.splitlines() if l.strip()]
        if non_empty and all(l.strip().startswith('|') for l in non_empty):
            for row in b.splitlines():
                row = row.strip()
                if not row or re.match(r'^\|[\s:|-]+\|$', row):
                    continue
                cells = [c.strip() for c in row.strip('|').split('|')]
                out.append(' '.join(cells))
            continue
        if non_empty and all(l.strip().startswith('>') for l in non_empty):
            quote_body = "\n".join(re.sub(r'^\s*>\s?', '', l) for l in b.splitlines())
            for sub in re.split(r'\n\s*\n', quote_body):
                sub = sub.strip()
                if not sub:
                    continue
                joined = ' '.join(l.strip() for l in sub.splitlines())
                out.append(re.sub(r'\s+', ' ', joined))
            continue
        if non_empty and all(LIST_MARKER_RE.match(l) or not l.strip() or _line_indent(l) > 0 for l in b.splitlines()) and \
           any(LIST_MARKER_RE.match(l) for l in non_empty):
            cur = []
            for l in b.splitlines():
                if LIST_MARKER_RE.match(l):
                    if cur:
                        joined = ' '.join(x.strip() for x in cur)
                        out.append(re.sub(r'\s+', ' ', joined))
                    cur = [l]
                else:
                    if l.strip():
                        cur.append(l)
            if cur:
                joined = ' '.join(x.strip() for x in cur)
                out.append(re.sub(r'\s+', ' ', joined))
            continue
        joined = ' '.join(l.strip() for l in b.splitlines())
        joined = re.sub(r'\s+', ' ', joined)
        out.append(joined)
    return out


# ---------------------------------------------------------------------------
# R4: boundary-aware identifier matching
# ---------------------------------------------------------------------------

IDENTIFIER_TOKEN_RE = re.compile(r'^[A-Za-z][A-Za-z0-9_-]*$')


def identifier_present(text, ident):
    pattern = r'(?<![A-Za-z0-9_-])' + re.escape(ident) + r'(?![A-Za-z0-9_-])'
    return re.search(pattern, text) is not None


def strip_markup_only(s):
    """Strip bold/italic emphasis markers only (not backticks -- code spans are
    handled separately so identifier-vs-prose treatment can differ)."""
    return re.sub(r'\*{1,3}', '', s)


# ---- from engine.py ----
import re


def preprocess(raw):
    """Full stripping pipeline (R2, R2b, R2c) short of code-span handling."""
    s = strip_fences(raw)
    s = strip_html_comments(s)
    s = strip_indented_code(s)
    s = strip_disallowed_constructs(s)
    return s


def dual_views(raw):
    """Return (blocks_for_identifiers, blocks_for_prose, flat_identifiers, flat_prose).

    Both views are derived from the SAME single block split (on text that
    still carries its inline code spans), then code-span content is
    resolved per block. This guarantees the two view lists stay index-
    aligned even when a block consists entirely of a code span (which would
    otherwise vanish from the prose view and desync the two lists)."""
    s = preprocess(raw)
    s = strip_markup_only(s)
    raw_blocks = blocks(s)
    bi = [unwrap_code_spans(b) for b in raw_blocks]
    bp = [strip_code_span_content(b) for b in raw_blocks]
    return bi, bp, "\n".join(bi), "\n".join(bp)


def is_identifier_token(tok):
    return bool(IDENTIFIER_TOKEN_RE.match(tok))


def token_present(flat_ident, flat_prose, tok):
    # Identifier tokens (stop names, profile codes, single-word markers such
    # as a posture label) match case-sensitively with boundary awareness
    # (R4). Multi-word prose phrases match case-insensitively -- ordinary
    # sentence capitalization must not break a required phrase.
    if is_identifier_token(tok):
        return identifier_present(flat_ident, tok)
    return tok.lower() in flat_prose.lower()


def all_present_same_block(bi, bp, tokens):
    n = min(len(bi), len(bp))
    for i in range(n):
        ok = True
        for t in tokens:
            if is_identifier_token(t):
                if not identifier_present(bi[i], t):
                    ok = False
                    break
            else:
                if t.lower() not in bp[i].lower():
                    ok = False
                    break
        if ok:
            return True
    return False


CLAUSE_TOKENS = {
    "E1": [
        "initial handoff",
        "only once initial handoff is confirmed",
        "never evaluates onward-handoff capability before initial handoff is confirmed",
    ],
    "E2a": ["treated as unavailable", "cursor-parent-orchestrated", "conservative default"],
    "E2b": [
        "initial handoff availability that itself cannot be confirmed",
        "cursor-inline-fallback", "read-only", "never upgrades a run in place",
    ],
    "E3a": [
        "dispatch_profile_declaration_missing",
        "dispatch_handoff_unavailable",
        "missing_required_secret_or_permission",
    ],
    "E3b": ["affected work item"],
    "E3c_stop1": [
        "fresh invocation", "not resumed or corrected in place", "valid profile",
        "named accountable role", "posture valid for the checkpoint",
        "profile the known facts assign",
    ],
    "E3c_stop2": [
        "environment where initial handoff is confirmed available",
        "explicitly accept the read-only result", "specific stage role", "reachable",
    ],
    "E3c_stop3": [
        "grant", "re-run the same delegated action", "same stage role",
        "does not proceed", "never performs",
    ],
    "E3d": [
        "is not a named stop condition", "SUBAGENT_PERMISSION_DENIAL",
        "observably similar", "#1746",
    ],
    "E4a": ["invalid profile", "invalid accountable role", "invalid posture"],
    "E4b": ["coarse-fact mismatch", "more permissive", "less permissive"],
    "E4c": ["mid-run recovery", "does not govern"],
    "E5": [
        "personally accountable", "handed off intact", "observing",
        "only at a read-only checkpoint", "current checkpoint",
    ],
    "E6": ["only in a Cursor environment", "other runners are unchanged"],
}

SAME_BLOCK_CLAUSES = {"E2a", "E2b", "E3d", "E6"}

FULL_CLAUSES = ["E1", "E2a", "E2b", "E3a", "E3b", "E3c_stop1", "E3c_stop2", "E3c_stop3",
                "E3d", "E4a", "E4b", "E4c", "E5", "E6"]

GUARDRAILS_CLAUSES = ["E3a", "E3b", "E3c_stop1", "E3c_stop2", "E3c_stop3", "E3d",
                       "E4a", "E4b", "E6"]


PROFILE_CODES = ["cursor-native-handoff", "cursor-parent-orchestrated", "cursor-inline-fallback"]


def check_profile_codes(raw):
    """Boundary-aware presence check for all three profile-code identifiers
    (R4). Returns the list of missing codes."""
    _, _, flat_i, _ = dual_views(raw)
    return [c for c in PROFILE_CODES if not identifier_present(flat_i, c)]


def check_clauses(raw, clauses):
    bi, bp, flat_i, flat_p = dual_views(raw)
    failures = []
    for clause in clauses:
        tokens = CLAUSE_TOKENS[clause]
        if clause in SAME_BLOCK_CLAUSES:
            ok = all_present_same_block(bi, bp, tokens)
        else:
            ok = all(token_present(flat_i, flat_p, t) for t in tokens)
        if not ok:
            failures.append(clause)
    return failures


# ---- from builder.py ----

INTRO = (
    "Declare a profile per "
    "`docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md`: "
    "`cursor-native-handoff`, `cursor-parent-orchestrated`, or `cursor-inline-fallback`.\n\n"
)

CLAUSE_PARAGRAPHS = {
    "E1": (
        "Evaluation order: initial handoff is evaluated first; onward-handoff "
        "capability is evaluated only once initial handoff is confirmed. A "
        "profile decision never evaluates onward-handoff capability before "
        "initial handoff is confirmed.\n\n"
    ),
    "E2a": (
        "Once initial handoff is confirmed, onward-handoff capability that "
        "cannot be confirmed is treated as unavailable, and the run declares "
        "`cursor-parent-orchestrated` as the conservative default.\n\n"
    ),
    "E2b": (
        "Initial handoff availability that itself cannot be confirmed is "
        "treated the same as no handoff of any kind: the run declares "
        "`cursor-inline-fallback` and stays read-only. A later confirmation "
        "never upgrades a run in place.\n\n"
    ),
    "E3a": (
        "Named stop conditions: `dispatch_profile_declaration_missing`, "
        "`dispatch_handoff_unavailable`, and the reused "
        "`missing_required_secret_or_permission`.\n\n"
    ),
    "E3b": ("Affected work item: the branch, pull request, or development-folder path.\n\n"),
    "E3c_stop1": (
        "Human unblocking action: not resumed or corrected in place; start a "
        "fresh invocation supplying a valid profile, a named accountable role, "
        "a posture valid for the checkpoint, and, when rejected for a fact "
        "mismatch, the profile the known facts assign.\n\n"
    ),
    "E3c_stop2": (
        "Move to an environment where initial handoff is confirmed available "
        "and re-run, or explicitly accept the read-only result; confirm the "
        "specific stage role the action needed is reachable.\n\n"
    ),
    "E3c_stop3": (
        "The unblocking action: grant the identified credential and re-run "
        "the same delegated action, or reassign to the same stage role or "
        "explicitly accept the action does not proceed; the absorbing "
        "context never performs it inline.\n\n"
    ),
    "E3d": (
        "A harness or local-path denial is not a named stop condition; it is "
        "only observably similar to `SUBAGENT_PERMISSION_DENIAL`, and is Out "
        "of Scope, tracked as #1746.\n\n"
    ),
    "E4a": ("An invalid profile, an invalid accountable role, and an invalid posture are each a missing declaration.\n\n"),
    "E4b": ("A coarse-fact mismatch, whether more permissive or less permissive than the assigned outcome, is a missing declaration.\n\n"),
    "E4c": ("This coarse check does not govern the mid-run recovery transitions.\n\n"),
    "E5": (
        "A declaration states personally accountable (absorbed), handed off "
        "intact, or observing. Observing is valid only at a read-only "
        "checkpoint; the required posture follows the current checkpoint.\n\n"
    ),
    "E6": ("This requirement applies only in a Cursor environment; other runners are unchanged.\n\n"),
}


def full_contract(clauses=None, omit=None):
    """Build a full-contract document containing the given clauses (default:
    FULL_CLAUSES), optionally omitting one clause's paragraph entirely."""
    clauses = clauses if clauses is not None else FULL_CLAUSES
    parts = [INTRO]
    for clause in clauses:
        if clause == omit:
            continue
        parts.append(CLAUSE_PARAGRAPHS[clause])
    return "".join(parts)


# ---- from family_a.py ----
"""Builders + expected rule-tags for the 'full-contract' fixture family
(rows 1-59, 72-74, 79-86, 121-146 of the manifest)."""

ROWS = {}  # id -> dict(content=..., clauses=FULL_CLAUSES, rule_tags=set(), note=...)


def add(rid, content, clauses=None, rule_tags=None):
    ROWS[rid] = dict(content=content, clauses=clauses or FULL_CLAUSES, rule_tags=set(rule_tags or []))


# 1: token at first byte
add(1, "cursor-native-handoff is one profile.\n\n" + full_contract())

# 2: token at last byte, no trailing newline
_doc2 = full_contract()
add(2, _doc2.rstrip("\n") + " and finally dispatch_handoff_unavailable")

# 3: wrapped phrase (already validated pattern)
_doc3 = full_contract()
add(3, _doc3.replace("only once initial handoff is confirmed", "only once initial\nhandoff is confirmed"))

# 4: token followed by punctuation
add(4, full_contract() + "\n\n(See `dispatch_handoff_unavailable`, then act.)\n")

# 5: identifier wrapped in backticks (already true throughout; add explicit case)
add(5, full_contract() + "\n\nAlso written as `dispatch_profile_declaration_missing`.\n")

# 6: empty file -- all clauses fail
add(6, "")

# 7: link-only file -- all clauses fail
add(7, "See [the canonical guide](docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md).\n")

# 8: lookalike longer stop name (E3a token replaced by a longer lookalike)
_doc8 = full_contract().replace("dispatch_handoff_unavailable", "dispatch_handoff_unavailable_x")
add(8, _doc8, rule_tags={"R4"})

# 9: lookalike longer profile code
_doc9 = full_contract().replace("cursor-native-handoff", "cursor-native-handoffs")
add(9, _doc9, rule_tags={"R4"})

# 10: lookalike case posture ("Observing" instead of "observing")
_doc10 = full_contract().replace(
    "handed off intact, or observing.", "handed off intact, or Observing.")
add(10, _doc10, rule_tags={"R4"})

# 11: lookalike case stop name
_doc11 = full_contract().replace(
    "`dispatch_handoff_unavailable`", "`DISPATCH_HANDOFF_UNAVAILABLE`")
add(11, _doc11, rule_tags={"R4"})

# 12: token only inside a fenced code block (E1's key phrase fenced)
_e1_para = CLAUSE_PARAGRAPHS["E1"]
_doc12 = INTRO + "```text\n" + _e1_para + "```\n\n" + "".join(
    CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1")
add(12, _doc12, rule_tags={"R2"})

# 13: token only inside an HTML comment
_doc13 = INTRO + "<!--\n" + _e1_para + "-->\n\n" + "".join(
    CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1")
add(13, _doc13, rule_tags={"R2"})

# 14: "observing" only as an unrelated word, no posture phrase
_doc14 = full_contract(omit="E5") + (
    "A note while observing the output: none of this changes the posture rule.\n\n"
)
add(14, _doc14)

# 15: E2b tokens split across different paragraphs
_doc15 = full_contract(omit="E2b") + (
    "Initial handoff availability that itself cannot be confirmed is a distinct case.\n\n"
    "Separately, the run declares `cursor-inline-fallback` and stays read-only; a "
    "later confirmation never upgrades a run in place.\n\n"
)
add(15, _doc15, rule_tags={"R3"})

# 16: token appears many times; clause met
add(16, full_contract() + "\n\n" + CLAUSE_PARAGRAPHS["E1"] + CLAUSE_PARAGRAPHS["E1"])

# 17: same file, a different clause unmet
add(17, full_contract(omit="E4a") + "\n\n" + CLAUSE_PARAGRAPHS["E1"] + CLAUSE_PARAGRAPHS["E1"],
    rule_tags=set())
ROWS[17]["unmet_clause"] = "E4a"

# 18/19: cross-surface pair -- two independent fixtures, A has token, B lacks it
add(18, full_contract())
add(19, full_contract(omit="E3a"), rule_tags={"R5"})

# 20: two of three stop actions present, one missing (E3c stop3 missing)
add(20, full_contract(clauses=[c for c in FULL_CLAUSES if c != "E3c_stop3"]))

# 21: duplicate canonical link lines
_link_line = ("Declare a profile per "
              "`docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md`.\n\n")
add(21, _link_line + full_contract())

# 22: clause inside a list item
_doc22 = INTRO + "- " + _e1_para.strip() + "\n\n" + "".join(
    CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1")
add(22, _doc22)

# 23: clause inside a blockquote
_doc23 = INTRO + "> " + _e1_para.strip() + "\n\n" + "".join(
    CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1")
add(23, _doc23)

# 24: clause inside a table cell (row block)
_doc24 = INTRO + "| Clause | Text |\n| --- | --- |\n| E1 | " + _e1_para.strip() + " |\n\n" + "".join(
    CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1")
add(24, _doc24)

# 25: required phrase inside a fenced block nested in a list item
_doc25 = INTRO + "- item text\n\n  ```text\n  " + _e1_para.strip() + "\n  ```\n\n" + "".join(
    CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1")
add(25, _doc25, rule_tags={"R2"})

# 26: tilde fence
_doc26 = INTRO + "~~~text\n" + _e1_para + "~~~\n\n" + "".join(
    CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1")
add(26, _doc26, rule_tags={"R2"})

# 27: tilde fence closed by longer tilde run; token after closer
_doc27 = INTRO + "~~~text\nirrelevant fenced content\n~~~~\n\n" + full_contract()
add(27, _doc27)

# 28: backtick fence(3) closed by longer backtick run(5); token after closer
_doc28 = INTRO + "```text\nirrelevant fenced content\n`````\n\n" + full_contract()
add(28, _doc28)

# 29: 4-backtick opener; inner 3-backtick line does not close; token after inner line still inside
_doc29 = (INTRO + "````text\n" + _e1_para + "```\n" + _e1_para + "````\n\n" +
          "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1"))
add(29, _doc29, rule_tags={"R2"})

# 30: backtick fence closed by a tilde run (mismatched) -- token after it still inside
_doc30 = (INTRO + "```text\n" + _e1_para + "~~~\n" + "".join(
    CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1"))
add(30, _doc30, rule_tags={"R2"})

# 31: unclosed fence at EOF with token after opener
_doc31 = INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") + "```text\n" + _e1_para
add(31, _doc31, rule_tags={"R2"})

# 32: unclosed fence at EOF, token BEFORE the opener
_doc32 = INTRO + full_contract() + "```text\nirrelevant trailing content with no closer\n"
add(32, _doc32)

# 33: fence opener indented 3 spaces (is a fence)
_doc33 = INTRO + "   ```text\n" + _e1_para + "   ```\n\n" + "".join(
    CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1")
add(33, _doc33, rule_tags={"R2"})

# 34: opener indented 4 spaces after a blank line (indented code, not a fence);
# token on a later unindented line
_doc34 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") +
          "\n    ```text\n    not a fence, indented code\n\n" + _e1_para)
add(34, _doc34)

# 35: token on a line indented 4 spaces after a blank line
_doc35 = INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") + "\n    " + _e1_para.strip() + "\n"
add(35, _doc35, rule_tags={"R2b"})

# 36: same, indented with a tab
_doc36 = INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") + "\n\t" + _e1_para.strip() + "\n"
add(36, _doc36, rule_tags={"R2b"})

# 37: indented block after a heading
_doc37 = INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") + "\n### Note\n\n    " + _e1_para.strip() + "\n"
add(37, _doc37, rule_tags={"R2b"})

# 38: blank line inside an indented block; token in the second chunk
_doc38 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") +
          "\n    first indented chunk\n\n    " + _e1_para.strip() + "\n")
add(38, _doc38, rule_tags={"R2b"})

# 39: 4-space-indented line directly after a paragraph line (no blank): paragraph continuation
_doc39 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") +
          "\nA short lead-in line right above,\n    " + _e1_para.strip() + "\n")
add(39, _doc39)

# 40: line indented to a list item's content offset (not +4)
_doc40 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") +
          "\n- item lead text\n\n  " + _e1_para.strip() + "\n")
add(40, _doc40)

# 41: line indented content offset + 4 inside a list item after a blank line
_doc41 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") +
          "\n- item lead text\n\n      " + _e1_para.strip() + "\n")
add(41, _doc41, rule_tags={"R2b"})

# 42: indented code inside a blockquote (`>` plus 4 spaces)
_doc42 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") +
          "\n> quoted lead line\n>\n>     " + _e1_para.strip() + "\n")
add(42, _doc42, rule_tags={"R2b"})

# 43: clause sentence inside a blockquote
_doc43 = INTRO + "> " + _e1_para.strip() + "\n\n" + "".join(
    CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1")
add(43, _doc43)

# 44: clause sentence in a table cell
_doc44 = INTRO + "| A | B |\n| --- | --- |\n| x | " + _e1_para.strip() + " |\n\n" + "".join(
    CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1")
add(44, _doc44)

# 45: E2b tokens split across two cells of the same table row
_e2b_tokens = CLAUSE_TOKENS["E2b"]
_doc45 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E2b") +
          "\n| Case | Detail |\n| --- | --- |\n| initial handoff availability that itself "
          "cannot be confirmed | declares `cursor-inline-fallback`, stays read-only, "
          "never upgrades a run in place |\n")
add(45, _doc45)

# 46: E2b tokens in two adjacent table rows
_doc46 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E2b") +
          "\n| Case | Detail |\n| --- | --- |\n"
          "| initial handoff availability that itself cannot be confirmed | see next row |\n"
          "| declares `cursor-inline-fallback` | stays read-only, never upgrades a run in place |\n")
add(46, _doc46, rule_tags={"R3"})

# 47: token only in a table header or separator row
_doc47 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") +
          "\n| only once initial handoff is confirmed | Detail |\n| --- | --- |\n| x | y |\n")
add(47, _doc47, rule_tags={"R3"})

# 48: token only in a link-reference definition title
_doc48 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E3a") +
          '\n[ref]: https://example.com "dispatch_handoff_unavailable notes"\n')
add(48, _doc48, rule_tags={"R2c"})

# 49: token only in a link destination
_doc49 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E3a") +
          "\nSee [details](https://example.com/dispatch_handoff_unavailable) for more.\n")
add(49, _doc49, rule_tags={"R2c"})

# 50: token only in image alt text
_doc50 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E3a") +
          "\n![dispatch_handoff_unavailable diagram](https://example.com/x.png)\n")
add(50, _doc50, rule_tags={"R2c"})

# 51: identifier token in an inline code span (should pass -- already default style)
add(51, full_contract())

# 52: prose phrase only inside an inline code span
_doc52 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") +
          "\nThe evaluation-order rule is `only once initial handoff is confirmed`, "
          "noted here only as a code span.\n")
add(52, _doc52, rule_tags={"R2c"})

# 53: token only inside a <pre> HTML block
_doc53 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") +
          "\n<pre>\n" + _e1_para + "</pre>\n")
add(53, _doc53, rule_tags={"R2c"})

# 54: backslash-escaped identifier
_doc54 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E3a") +
          "\nAlso seen escaped as dispatch\\_handoff\\_unavailable in older notes.\n")
add(54, _doc54, rule_tags={"R2c", "R4"})

# 55: closer indented 4 spaces does not close; token after it still inside
_doc55 = (INTRO + "```text\n" + _e1_para + "    ```\n" + "".join(
    CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1"))
add(55, _doc55, rule_tags={"R2"})

# 56: unclosed HTML comment at EOF with token after <!--
_doc56 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") +
          "<!--\n" + _e1_para)
add(56, _doc56, rule_tags={"R2"})

# 57: overlapping phrases -- only the shorter substring present
_doc57 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") +
          "\nThe initial handoff is the first fact resolved, before anything else.\n")
add(57, _doc57)

# 58: E2a sentence deleted, E2b intact, shared tokens
_doc58 = full_contract(omit="E2a")
add(58, _doc58)

# 59: E2b sentence deleted, E2a intact, shared tokens
_doc59 = full_contract(omit="E2b")
add(59, _doc59)

# 72: protocol fixture lacking only E3d
add(72, full_contract(omit="E3d"))

# 73: guardrails fixture carrying only its Y clauses
add(73, full_contract(clauses=GUARDRAILS_CLAUSES), clauses=GUARDRAILS_CLAUSES)

# 74: guardrails fixture lacking E4b "less permissive" direction
_e4b_only_more = CLAUSE_PARAGRAPHS["E4b"].replace(
    "whether more permissive or less permissive than the assigned outcome",
    "when more permissive than the assigned outcome")
_doc74 = full_contract(clauses=[c for c in GUARDRAILS_CLAUSES if c != "E4b"]) + _e4b_only_more
add(74, _doc74, clauses=GUARDRAILS_CLAUSES)

# 79-86: E3c stop sub-clauses
_e3c1 = CLAUSE_PARAGRAPHS["E3c_stop1"]
_doc79 = full_contract(omit="E3c_stop1") + "Human unblocking action: declare one of the three profiles.\n\n"
add(79, _doc79)
_doc80 = full_contract(omit="E3c_stop1") + _e3c1.replace(
    "a posture valid for the checkpoint, and, when rejected for a fact "
    "mismatch, the profile the known facts assign.\n\n",
    "and, when rejected for a fact mismatch, the profile the known facts assign.\n\n")
add(80, _doc80)
_doc81 = full_contract(omit="E3c_stop1") + _e3c1.replace("a named accountable role, ", "")
add(81, _doc81)
_doc82 = full_contract(omit="E3c_stop1") + _e3c1.replace(
    ", and, when rejected for a fact mismatch, the profile the known facts assign", "")
add(82, _doc82)
_e3c2 = CLAUSE_PARAGRAPHS["E3c_stop2"]
_doc83 = full_contract(omit="E3c_stop2") + _e3c2.replace(
    "; confirm the specific stage role the action needed is reachable", "")
add(83, _doc83)
_doc84 = full_contract(omit="E3c_stop2") + _e3c2.replace(
    "and re-run, or explicitly accept the read-only result", "and re-run")
add(84, _doc84)
_e3c3 = CLAUSE_PARAGRAPHS["E3c_stop3"]
_doc85 = full_contract(omit="E3c_stop3") + _e3c3.replace(
    "grant the identified credential and re-run the same delegated action, "
    "or reassign to the same stage role or explicitly accept the action "
    "does not proceed", "the action does not proceed")
add(85, _doc85)
add(86, full_contract())

# 121-133: clause-all-present / clause-missing-<x>
add(121, full_contract())
_row_clause_map = {
    122: "E1", 123: "E2a", 124: "E2b", 125: "E3a", 126: "E3b", 127: None,
    128: "E3d", 129: "E4a", 130: "E4b", 131: "E4c", 132: "E5", 133: "E6",
}
add(122, full_contract(omit="E1"))
add(123, full_contract(omit="E2a"))
add(124, full_contract(omit="E2b"))
add(125, full_contract(omit="E3a"))
add(126, full_contract(omit="E3b"))
# 127: "clause E3c" removed entirely = all three stop sub-clauses removed
add(127, full_contract(clauses=[c for c in FULL_CLAUSES if c not in ("E3c_stop1", "E3c_stop2", "E3c_stop3")]))
add(128, full_contract(omit="E3d"))
add(129, full_contract(omit="E4a"))
add(130, full_contract(omit="E4b"))
add(131, full_contract(omit="E4c"))
add(132, full_contract(omit="E5"))
add(133, full_contract(omit="E6"))

# 134: non-Cursor mirror requiring profile from every runner (no Cursor scoping)
_doc134 = full_contract(omit="E6") + (
    "This declaration requirement applies to every runner, Cursor or otherwise.\n\n"
)
add(134, _doc134)

# 135: UTF-8 BOM before the token
add(135, "﻿" + full_contract())

# 136: multibyte characters around the token
_doc136 = full_contract() + "\n\nNote (é, ñ, 日本語): dispatch_handoff_unavailable stays exact.\n"
add(136, _doc136)

# 137: not valid UTF-8 -- handled specially (binary content), see generator

# 138: tabs and repeated spaces inside a required phrase
_doc138 = full_contract().replace(
    "only once initial handoff is confirmed",
    "only\tonce  initial   handoff is confirmed")
add(138, _doc138)

# 139: identifier preceded by an identifier character
_doc139 = full_contract().replace(
    "`dispatch_handoff_unavailable`", "`xdispatch_handoff_unavailable`")
add(139, _doc139, rule_tags={"R4"})

# 140: clause in a list item
add(140, ROWS[22]["content"])

# 141: clause in a heading
_doc141 = INTRO + "## " + _e1_para.strip() + "\n\n" + "".join(
    CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1")
add(141, _doc141)

# 142: clause in link text
_doc142 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") +
           "\nSee [" + _e1_para.strip() + "](https://example.com/evaluation-order) for the rule.\n")
add(142, _doc142)

# 143: token in inline HTML tag text
_doc143 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") +
           "\n<em>" + _e1_para.strip() + "</em>\n")
add(143, _doc143)

# 144: token only in an autolink
_doc144 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E3a") +
           "\nSee <https://example.com/dispatch_handoff_unavailable> for more.\n")
add(144, _doc144, rule_tags={"R2c"})

# 145: token only inside a <code> HTML block
_doc145 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E1") +
           "\n<code>\n" + _e1_para + "</code>\n")
add(145, _doc145, rule_tags={"R2c"})

# 146: HTML entity for an underscore in a stop name (entities not decoded)
_doc146 = (INTRO + "".join(CLAUSE_PARAGRAPHS[c] for c in FULL_CLAUSES if c != "E3a") +
           "\nAlso rendered as `dispatch&#95;handoff&#95;unavailable` in escaped HTML notes.\n")
add(146, _doc146, rule_tags={"R2c", "R4"})


# ---- from sim_family.py ----
"""Simulation family (rows 60-68, 147-148): a synthetic canonical-doc-style
Decision-Gate table + scenario mapping, validated by simulate_bounded_paths
(C1-C4) plus a small applicability-assertion checker."""
import re

REFERENCE_ROWS = [
    ("R1", "PROCEED"), ("R2", "PROCEED"), ("R3", "PROCEED"), ("R4", "PROCEED"),
    ("R5", "PROCEED"), ("R6", "PROCEED"), ("R7", "PROCEED"), ("R8", "PROCEED"),
    ("R9", "PROCEED"), ("R10", "missing_required_secret_or_permission"),
    ("R11", "PROCEED"), ("R12", "dispatch_handoff_unavailable"),
    ("R13", "dispatch_profile_declaration_missing"),
    ("R14", "dispatch_profile_declaration_missing"),
    ("R15", "dispatch_profile_declaration_missing"),
    ("R16", "dispatch_profile_declaration_missing"),
    ("R17", "dispatch_profile_declaration_missing"),
    ("R18", "dispatch_profile_declaration_missing"),
]

REFERENCE_SCENARIO_MAP = {
    "S1": "R1", "S2": "R2", "S3": "R3", "S4": "R4", "S5": "R5", "S6": "R6",
    "S7": "R7", "S8": "R8", "S9": "R9", "S10": "R10", "S10b": "SUBCASE",
    "S11": "R11", "S12": "R12", "S13": "R13", "S14": "R14", "S15": "R15",
    "S16": "R16", "S17a": "R17", "S17b": "R17", "S18": "R18", "S19": "R18",
}


def render_table(rows):
    out = ["| Row | Stop |", "| --- | --- |"]
    for row_id, stop in rows:
        out.append("| %s | %s |" % (row_id, stop))
    return "\n".join(out) + "\n"


def render_scenario_map(mapping, s7_recovery_note=None):
    out = []
    for s, row in mapping.items():
        if row == "SUBCASE":
            out.append("- %s -> subcase (no matrix row; harness/local-path denial, #1746, "
                        "is not a named stop condition)" % s)
        else:
            out.append("- %s -> %s" % (s, row))
    text = "\n".join(out) + "\n"
    if s7_recovery_note:
        text += "\n" + s7_recovery_note + "\n"
    return text


def base_fixture(rows=None, mapping=None, s7_recovery_note=(
        "S7 is a recovery scenario (mid-run native to parent orchestrated); its "
        "re-declaration is validated against its own action-specific fact and is "
        "not treated as a coarse-fact mismatch (E4c exemption).")):
    rows = rows if rows is not None else list(REFERENCE_ROWS)
    mapping = mapping if mapping is not None else dict(REFERENCE_SCENARIO_MAP)
    return "## Decision gate\n\n" + render_table(rows) + "\n" + render_scenario_map(mapping, s7_recovery_note)


def check_simulation(text):
    """C1-C4 + scenario/row checks against the reference (18-row) table."""
    failures = []

    table_rows = re.findall(r'^\|\s*(R\d+[ab]?)\s*\|\s*([^|]+?)\s*\|\s*$', text, re.M)
    n_rows = len(table_rows)
    ref_ids = [r for r, _ in REFERENCE_ROWS]

    if n_rows != 18:
        failures.append("C1")
    seen_ids = [r for r, _ in table_rows]
    if len(set(seen_ids)) != len(seen_ids):
        failures.append("C1")
    if set(seen_ids) - set(ref_ids):
        failures.append("C1")
    if set(ref_ids) - set(seen_ids):
        failures.append("C2")

    scen_map = dict(re.findall(r'^-\s*(S\d+[ab]?)\s*->\s*(\S+)', text, re.M))
    for s in REFERENCE_SCENARIO_MAP:
        if s not in scen_map:
            failures.append("C3")
            break
    if scen_map.get("S10b", "").lower().startswith("r"):
        failures.append("C3")
        failures.append("S10b")

    table_dict = dict(table_rows)
    for row_id, expected_stop in REFERENCE_ROWS:
        actual = table_dict.get(row_id)
        if actual is not None and actual.strip() != expected_stop:
            failures.append("C4")
            if row_id == "R12":
                failures.append("S12")

    ids_only = [r for r, _ in table_rows]
    stops_only = [s for _, s in table_rows]
    if len(set(ids_only)) == len(ids_only) == 18 and sorted(stops_only) == sorted(s for _, s in REFERENCE_ROWS) \
            and stops_only != [s for _, s in REFERENCE_ROWS] and "C4" not in failures:
        failures.append("C4")

    m = re.search(r'S7[^.\n]*\.', text)
    if m:
        sentence = m.group(0)
        if "coarse-fact mismatch" in sentence and not any(
                kw in sentence for kw in ("not treated as", "not a coarse", "exemption", "is not")):
            failures.append("E4c")

    if re.search(r'S10b\s*->\s*missing_required_secret_or_permission', text):
        failures.append("S10b")

    if "APPLICABILITY:" in text:
        for line in text.splitlines():
            if line.startswith("APPLICABILITY:") and "N/A" in line and "ASSERTED" in line:
                failures.append("applicability")

    return failures


# ---- from modelcfg_family.py ----
import re

PROFILE_ROWS = [
    ("Cursor Desktop", "Portfolio", "confirmed by observation"),
    ("Cursor Desktop", "Epic", "confirmed by observation"),
    ("Cursor Desktop", "Item", "confirmed by observation"),
    ("Cursor Remote Control", "Portfolio", "explicit assumption"),
    ("Cursor Remote Control", "Epic", "explicit assumption"),
    ("Cursor Remote Control", "Item", "confirmed by observation"),
    ("Cursor Cloud Agents", "Portfolio", "explicit assumption"),
    ("Cursor Cloud Agents", "Epic", "explicit assumption"),
    ("Cursor Cloud Agents", "Item", "explicit assumption"),
]

MODEL_ROWS = [
    ("Cursor Desktop", "explicit assumption"),
    ("Cursor Remote Control", "explicit assumption"),
    ("Cursor Cloud Agents", "explicit assumption"),
]


def render_profile_table(rows):
    out = ["| Environment | Layer | Profile | Evidence marker |", "| --- | --- | --- | --- |"]
    for env, layer, marker in rows:
        out.append("| %s | %s | Profile | %s |" % (env, layer, marker if marker else ""))
    return "\n".join(out) + "\n"


def render_model_table(rows):
    out = ["| Environment | Model | Evidence marker |", "| --- | --- | --- |"]
    for env, marker in rows:
        out.append("| %s | model | %s |" % (env, marker or "(none)"))
    return "\n".join(out) + "\n"


def base_fixture_mc(profile_rows=None, model_rows=None):
    profile_rows = profile_rows if profile_rows is not None else list(PROFILE_ROWS)
    model_rows = model_rows if model_rows is not None else list(MODEL_ROWS)
    return ("## Profile and evidence marker per environment x layer\n\n" +
            render_profile_table(profile_rows) +
            "\n## Model assignment per environment x layer\n\n" +
            render_model_table(model_rows))


def check_model_config(text):
    failures = []
    profile_rows = re.findall(
        r'^\|\s*(Cursor [A-Za-z ]+?)\s*\|\s*(Portfolio|Epic|Item)\s*\|\s*[^|]*\|\s*([^|]*?)\s*\|\s*$',
        text, re.M)
    if len(profile_rows) != 9:
        failures.append("model-config rows")
    seen = {(e, l) for e, l, _ in profile_rows}
    expected = {(e, l) for e, l, _ in PROFILE_ROWS}
    if expected - seen:
        failures.append("model-config rows")

    ref_profile = {(e, l): m for e, l, m in PROFILE_ROWS}
    for env, layer, marker in profile_rows:
        ref = ref_profile.get((env, layer))
        if ref is None:
            continue
        if not marker.strip():
            failures.append("evidence-marker")
        elif marker.strip() != ref and marker.strip() == "confirmed by observation" and ref == "explicit assumption":
            failures.append("evidence-marker")

    model_rows = re.findall(r'^\|\s*(Cursor [A-Za-z ]+?)\s*\|\s*model\s*\|\s*([^|]*?)\s*\|\s*$', text, re.M)
    ref_model = {e: m for e, m in MODEL_ROWS}
    for env, marker in model_rows:
        ref = ref_model.get(env)
        if ref is None:
            continue
        if not marker.strip():
            failures.append("evidence-marker")
        elif marker.strip() != ref and marker.strip() == "confirmed by observation" and ref == "explicit assumption":
            failures.append("evidence-marker")

    return failures


# ---- from proto_family.py ----

GENERIC_PARAGRAPH = (
    "If the runner does **not** support Work Item Runner handoff natively, "
    "continue in the current session by following `91-orchestrate-work-protocol.md` "
    "for each item one at a time."
)

NEW_PARA_TOKENS = [
    "cursor-parent-orchestrated", "do not dispatch Work Item Runners",
    "one at a time", "absorbed the portfolio layer", "stage role",
    "only when a Cursor dispatch profile is declared",
]

ABSORBED_SENTENCE = "stage delegation as the only handoff"
PROTO95_TOKENS = ["absorbs the epic layer", "dispatches no Work Item Runner", "Execution arrangement"]
CANONICAL_DISPATCH_TOKENS = ["absorbs the portfolio layer", "dispatches no work item runner",
                             "/run-item", "/run-items", "/run-epic", "/run-work"]


def check_proto90(text):
    failures = []
    if text.count(GENERIC_PARAGRAPH) != 1:
        failures.append("protocol90_step4_condition")
    bi, bp, _, _ = dual_views(text)
    if not all_present_same_block(bi, bp, NEW_PARA_TOKENS):
        failures.append("protocol90_step4_condition")
    return failures


def check_proto91(text):
    collapsed = " ".join(text.split())
    if ABSORBED_SENTENCE not in collapsed:
        return ["protocol91_absorbed_layer_sentence"]
    return []


def check_proto95(text):
    if not all(t in text for t in PROTO95_TOKENS):
        return ["protocol95_execution_arrangement"]
    return []


def check_canonical_dispatch(text):
    normalized = text.replace("*", "").replace("`", "").lower()
    if not all(t.lower() in normalized for t in CANONICAL_DISPATCH_TOKENS):
        return ["canonical_dispatch_decision"]
    return []


# ---- from ser_family.py ----
import re

WORKED_EXAMPLE_RE = re.compile(
    r'Router input:\s*`(?P<input>[^`]*)`.*?Rendered:\s*`(?P<rendered>[^`]*)`', re.S)

PROSE_ASSERTIONS = {
    "newline_unreachable": "a line feed can never appear inside a target",
    "unreachable_forms": "a single target and an empty target are unreachable",
    "comma_not_in_target": "a comma cannot occur inside an accepted target",
    "tracker_unreachable": "a tracker identifier stops at mode=ambiguous before the declaration gate",
    "router_grammar": "arguments are split on commas, edge whitespace is trimmed, empty pieces are dropped, and duplicates are removed keeping the first occurrence",
}

BRANCH_PREFIXES = ('feature/', 'fix/', 'refactor/', 'hotfix/', 'spec/',
                    'implementation-plan/', 'plan/')


def router_split_targets(raw_input):
    parts = [p.strip() for p in raw_input.split(",")]
    parts = [p for p in parts if p != ""]
    seen = set()
    out = []
    for p in parts:
        if p not in seen:
            seen.add(p)
            out.append(p)
    return out


def is_valid_router_token(t):
    if re.fullmatch(r'#?\d+', t):
        return True
    t2 = t[2:] if t.startswith('./') else t
    if t2.startswith('docs/specs/developments/'):
        return True
    if t.startswith(BRANCH_PREFIXES):
        return True
    return False


def percent_encode_target(t):
    b = t.encode("utf-8")
    out = bytearray()
    for byte in b:
        if byte == 0x25:
            out += b"%25"
        elif byte == 0x2C:
            out += b"%2C"
        elif byte < 0x21 or byte == 0x7F:
            out += ("%%%02X" % byte).encode("ascii")
        else:
            out.append(byte)
    return out.decode("utf-8")


def _dotslash_core(s):
    return s[2:] if s.startswith("./") else s


def is_verbatim_violation(comp, rend):
    if rend.lower() == comp.lower():
        return True
    if rend.lstrip("#") == comp or comp.lstrip("#") == rend:
        return True
    if ("#" + comp) == rend or ("#" + rend) == comp:
        return True
    if rend.replace("/", "-") == comp or comp.replace("/", "-") == rend:
        return True
    if _dotslash_core(rend) == comp or _dotslash_core(comp) == rend:
        return True
    return False


def classify_and_check(raw_input, rendered_str):
    failures = []

    if ", " in rendered_str:
        failures.append("delimiter")
        return failures

    computed_targets = router_split_targets(raw_input)

    invalid = [t for t in computed_targets if not is_valid_router_token(t)]
    if invalid and any(inv in rendered_str for inv in invalid):
        failures.append("router-grammar")
        return failures

    computed_encoded = [percent_encode_target(t) for t in computed_targets]
    rendered_targets = rendered_str.split(",") if rendered_str else []

    if len(computed_targets) <= 1:
        failures.append("unreachable-forms")
        return failures
    if any(rt == "" for rt in rendered_targets):
        failures.append("unreachable-forms")
        return failures
    if any(re.search(r'%0[Aa]', rt) for rt in rendered_targets):
        failures.append("router-grammar")
        return failures
    if any(re.search(r'%2[Cc]', rt) for rt in rendered_targets):
        failures.append("router-grammar")
        return failures
    if len(rendered_targets) != len(computed_encoded):
        failures.append("router-grammar")
        return failures

    if computed_encoded != rendered_targets and sorted(computed_encoded) == sorted(rendered_targets):
        failures.append("order-preserved")
        return failures

    for comp, rend in zip(computed_encoded, rendered_targets):
        if comp == rend:
            continue

        upcast = re.sub(r'%[0-9a-fA-F]{2}', lambda m: m.group(0).upper(), rend)
        if upcast == comp:
            failures.append("uppercase-hex")
            continue

        if "%25" in comp and rend == comp.replace("%25", "%", 1):
            failures.append("percent-encoding")
            continue

        if is_verbatim_violation(comp, rend):
            failures.append("verbatim")
            continue

        if re.search(r'%(09|20|0[Dd])', comp) or re.search(r'%(09|20|0[Dd])', rend):
            failures.append("edge-trim-only")
            continue

        failures.append("router-grammar")

    return failures


def check_serialization(text):
    failures = []
    m = WORKED_EXAMPLE_RE.search(text)
    if m:
        failures.extend(classify_and_check(m.group("input"), m.group("rendered")))
    for key, phrase in PROSE_ASSERTIONS.items():
        marker = "ASSERT:" + key
        if marker in text and phrase.lower() not in text.lower():
            failures.append("assertion-missing:" + key)
    return failures


# ---- from fixtures_all.py ----
def _ser_example(inp, rend, extra=""):
    return ("## Serialization example\n\n" +
            "- Router input: `%s`\n" % inp +
            "- Rendered: `%s`\n\n" % rend + extra)


def _ser_prose(marker, phrase_text):
    return "## Serialization note\n\nASSERT:%s\n\n%s\n" % (marker, phrase_text)


def build_ser_contents():
    C = {}
    C[69] = _ser_example("#1462,feature/x,1771,./docs/specs/developments/x",
                          "#1462,feature/x,1771,./docs/specs/developments/x")
    C[70] = _ser_example("1771,feature/x", "#1771,feature/x")
    C[71] = _ser_example("#1462,feature/x", "1462,feature/x")
    C[87] = _ser_example("feature/100%-done,1771", "feature/100%25-done,1771")
    C[88] = _ser_example("feature/a%25b,1771", "feature/a%2525b,1771")
    C[89] = _ser_example("./docs/specs/developments/x\ty,1771", "./docs/specs/developments/x%09y,1771")
    C[90] = _ser_example("./docs/specs/developments/x y,1771", "./docs/specs/developments/x%20y,1771")
    C[91] = _ser_prose("newline_unreachable",
                        "A line feed can never appear inside a target, because the router keeps "
                        "only the first line of an argument; this document never shows it encoded.")
    C[92] = _ser_example("feature/x,1771", "feature/x%0A,1771")
    C[93] = _ser_example("./docs/specs/developments/x\ry,1771", "./docs/specs/developments/x%0Dy,1771")
    C[94] = _ser_example("./docs/specs/developments/x\x1fy,1771", "./docs/specs/developments/x%1Fy,1771")
    C[95] = _ser_example("./docs/specs/developments/x\x7fy,1771", "./docs/specs/developments/x%7Fy,1771")
    C[96] = _ser_example("./docs/specs/developments/x\x1fy,1771", "./docs/specs/developments/x%1fy,1771")
    C[97] = _ser_example("feature/café,1771", "feature/café,1771")
    C[98] = _ser_example(" feature/a b ,1771", "feature/a%20b,1771")
    C[99] = _ser_example("feature/a b,1771", "feature/ab,1771")
    C[100] = _ser_example(" feature/a ,1771", "%20feature/a%20,1771")
    C[101] = _ser_example("feature/b,1771,#1462", "feature/b,1771,#1462")
    C[102] = _ser_example("feature/b,1771,#1462", "#1462,1771,feature/b")
    C[103] = _ser_example("feature/a,feature/b,1771", "feature/a, feature/b,1771")
    C[104] = _ser_example("1771", "1771")
    C[105] = _ser_example("feature/a,feature/b,1771", "feature/a,,feature/b,1771")
    C[106] = _ser_prose("unreachable_forms",
                         "A single target and an empty target are unreachable at this gate, so "
                         "this document never renders a one-target or empty form.")
    C[107] = _ser_example("feature/Cursor-Dispatch,1771", "feature/cursor-dispatch,1771")
    C[108] = _ser_example("feature/cursor-dispatch,1771", "feature-cursor-dispatch,1771")
    C[109] = _ser_prose("comma_not_in_target",
                         "A comma cannot occur inside an accepted target, because the router "
                         "splits every argument on commas before resolution; the `%2C` rule is "
                         "defensive only.")
    C[110] = _ser_example("feature/x,1771", "feature/x%2Cy,1771")
    C[111] = _ser_example("feature/a%25b,1771", "feature/a%25b,1771")
    C[112] = _ser_example("#1462,feature/x,#1462", "#1462,feature/x")
    C[113] = _ser_example("#1462,feature/x", "#1462,feature/x,#1462")
    C[114] = _ser_example("1462,#1462,feature/x", "1462,#1462,feature/x")
    C[115] = _ser_example("1462,#1462,feature/x", "1462,feature/x")
    C[116] = _ser_example("ENG-123,1771", "ENG-123,1771")
    C[117] = _ser_prose("tracker_unreachable",
                         "For an identifier such as `ENG-123`: a tracker identifier stops at "
                         "MODE=ambiguous before the declaration gate, so it has no serialization here.")
    C[118] = _ser_prose("router_grammar",
                         "Router grammar: arguments are split on commas, edge whitespace is "
                         "trimmed, empty pieces are dropped, and duplicates are removed keeping "
                         "the first occurrence.")
    C[119] = _ser_example("./docs/specs/developments/x,1771", "./docs/specs/developments/x,1771")
    C[120] = _ser_example("./docs/specs/developments/x,1771", "docs/specs/developments/x,1771")
    return C


def build_sim_contents():
    C = {}
    C[60] = base_fixture()
    rows61 = [r for r in REFERENCE_ROWS if r[0] != "R5"]
    C[61] = base_fixture(rows=rows61)
    rows62 = list(REFERENCE_ROWS) + [("R19", "PROCEED")]
    C[62] = base_fixture(rows=rows62)
    map63 = dict(REFERENCE_SCENARIO_MAP)
    del map63["S16"]
    C[63] = base_fixture(mapping=map63)
    map64 = dict(REFERENCE_SCENARIO_MAP)
    map64["S10b"] = "R10"
    C[64] = base_fixture(mapping=map64)
    rows65 = list(REFERENCE_ROWS)
    i10 = [i for i, r in enumerate(rows65) if r[0] == "R10"][0]
    i12 = [i for i, r in enumerate(rows65) if r[0] == "R12"][0]
    rows65[i10], rows65[i12] = ("R10", rows65[i12][1]), ("R12", rows65[i10][1])
    C[65] = base_fixture(rows=rows65)
    rows66 = [(rid, "dispatch_profile_declaration_missing" if rid == "R12" else stop)
              for rid, stop in REFERENCE_ROWS]
    C[66] = base_fixture(rows=rows66)
    C[67] = base_fixture(s7_recovery_note=(
        "S7 (mid-run native to parent orchestrated) re-declaration is rejected as "
        "a coarse-fact mismatch, the same as any other profile/fact disagreement."))
    C[68] = base_fixture() + "\n- S10b -> missing_required_secret_or_permission\n"
    C[147] = base_fixture() + "\nAPPLICABILITY: S10b/native = N/A\n"
    C[148] = base_fixture() + "\nAPPLICABILITY: S10b/native = N/A; ASSERTED\n"
    return C


def build_modelcfg_contents():
    C = {}
    C[75] = base_fixture_mc(profile_rows=PROFILE_ROWS[:-1])
    rows76 = [(e, l, "confirmed by observation") if (e, l) == ("Cursor Remote Control", "Epic") else (e, l, m)
              for e, l, m in PROFILE_ROWS]
    C[76] = base_fixture_mc(profile_rows=rows76)
    rows77 = [(e, "confirmed by observation") if e == "Cursor Desktop" else (e, m) for e, m in MODEL_ROWS]
    C[77] = base_fixture_mc(model_rows=rows77)
    rows78 = [(e, l, "") if (e, l) == ("Cursor Cloud Agents", "Item") else (e, l, m)
              for e, l, m in PROFILE_ROWS]
    C[78] = base_fixture_mc(profile_rows=rows78)
    return C


def build_proto_contents():
    C = {}
    NEW_PARA = (
        "Under Cursor `cursor-parent-orchestrated`, the current context has "
        "absorbed the portfolio layer: do not dispatch Work Item Runners; "
        "continue one at a time by following the item-layer protocol directly, "
        "from a stage role, only when a Cursor dispatch profile is declared."
    )
    C[149] = "### Step 4\n\n" + GENERIC_PARAGRAPH + "\n\n" + NEW_PARA + "\n"
    C[150] = "### Step 4\n\n" + GENERIC_PARAGRAPH + "\n"
    C[151] = ("### Step 4\n\nIf the runner does **not** support Work Item Runner handoff "
              "natively, and under Cursor `cursor-parent-orchestrated` do not dispatch "
              "Work Item Runners, continue in the current session for each item one at "
              "a time, having absorbed the portfolio layer from a stage role, only when "
              "a Cursor dispatch profile is declared.\n")
    C[152] = ("### Step 4\n\nIf the runner does not support native handoff, continue "
              "for each item one at a time.\n\n" + NEW_PARA + "\n")
    NEW_PARA_UNSCOPED = NEW_PARA.replace(", only when a Cursor dispatch profile is declared", "")
    C[153] = "### Step 4\n\n" + GENERIC_PARAGRAPH + "\n\n" + NEW_PARA_UNSCOPED + "\n"
    C[154] = "### Step 6\n\nNo dispatch-related paragraph here.\n"
    C[155] = "### Absorbed layer\n\nNo relevant sentence here.\n"
    C[156] = ("## Per-command dispatch table\n\nThis layer absorbs the portfolio layer "
              "and dispatches no Work Item Runner. Rows: /run-item, /run-epic, /run-work.\n")
    return C


def build_parity_contents():
    FMT = "explicit_list_invocation_targets=<t1>,<t2>,..."
    base_parity = "Canonical: `%s`\nGuardrails: `%s`\nProtocol90: `%s`\nSpec: `%s`\n" % (FMT, FMT, FMT, FMT)
    C = {}
    C[157] = base_parity
    C[158] = base_parity.replace(
        "Guardrails: `%s`" % FMT, "Guardrails: `explicit_list_invocation_targets=<a>,<b>,...`")
    return C


def build_all_fixture_contents():
    C = {}
    for rid, row in ROWS.items():
        C[rid] = row["content"]
    C[137] = b"Declare a profile per docs/... \xff\xfe invalid bytes dispatch_handoff_unavailable"
    C.update(build_sim_contents())
    C.update(build_ser_contents())
    C.update(build_modelcfg_contents())
    C.update(build_proto_contents())
    C.update(build_parity_contents())
    return C


# ---- from real_surface.py ----
import os

CANON_REL = "docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md"

MIRROR_SURFACES = [
    ".cursor/commands/run-item.md", ".cursor/commands/run-item-work.md",
    ".cursor/commands/run-items.md", ".cursor/commands/run-epic.md",
    ".cursor/commands/run-work.md",
    ".claude/commands/run-item.md", ".claude/commands/run-item-work.md",
    ".claude/commands/run-items.md", ".claude/commands/run-epic.md",
    ".claude/commands/run-work.md",
    ".agents/skills/run-item/SKILL.md", ".agents/skills/run-item-work/SKILL.md",
    ".agents/skills/run-items/SKILL.md", ".agents/skills/run-epic/SKILL.md",
    ".agents/skills/run-work/SKILL.md",
]

AGENT_AND_SKILL_SURFACES = [
    ".cursor/agents/orchestrator.md", ".cursor/agents/item-orchestrator.md",
    ".claude/agents/orchestrator.md", ".claude/agents/item-orchestrator.md",
    ".codex/skills/workflow-orchestrator/SKILL.md",
    ".codex/skills/workflow-item-orchestrator/SKILL.md",
]

PROTOCOL_SURFACES = [
    "docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md",
    "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md",
    "docs/workflow/development-workflow/protocols/95-run-epic-protocol.md",
]

RULE_SURFACE = ".cursor/rules/workflow.mdc"
GUARDRAILS_SURFACE = "docs/workflow/development-workflow/guardrails-enforcement.md"

FULL_CONTRACT_SURFACES = MIRROR_SURFACES + AGENT_AND_SKILL_SURFACES + PROTOCOL_SURFACES + [RULE_SURFACE]

EXPLICIT_LIST_SURFACES = {
    "docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md",
    ".cursor/commands/run-items.md", ".claude/commands/run-items.md",
    ".agents/skills/run-items/SKILL.md",
    "docs/workflow/development-workflow/guardrails-enforcement.md",
}


SELF_REL = "scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh"
SPEC_REL = "docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md"
SMOKE_REL = "docs/testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md"
FIXTURES_GLOB = "scripts/development-workflow/tests/fixtures/cursor-dispatch-profile-surfaces/**"


def read_path(root, rel):
    allowed_prefixes = (
        ".cursor/commands/", ".claude/commands/", ".agents/skills/",
        ".cursor/agents/", ".claude/agents/", ".codex/skills/",
        "docs/workflow/development-workflow/protocols/",
        "docs/workflow/development-workflow/guardrails-enforcement.md",
        "docs/workflow/development-workflow/agent-model-config.md",
        "docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md",
        ".cursor/rules/workflow.mdc",
        "docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/",
        SELF_REL,
    )
    if not rel.startswith(allowed_prefixes):
        raise SystemExit("read_path() refused an undeclared path: %s" % rel)
    path = os.path.join(root, rel)
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def check_link(root, rel):
    raw = read_path(root, rel)
    stripped = preprocess(raw)
    return CANON_REL in stripped or "integrations/cursor-dispatch-profiles.md" in stripped


def canonical_checks(root):
    raw = read_path(root, CANON_REL)
    stripped = preprocess(raw)
    failures = []

    if not all(h in stripped for h in ("### Portfolio layer", "### Epic layer", "### Item layer")):
        failures.append("canonical_layers")
    for kw in ("Governing contract", "Entering commands", "Constrained-environment behavior"):
        if kw not in raw:
            failures.append("canonical_layers")
            break

    if "## Perform / hand off / prohibit matrix" not in raw:
        failures.append("canonical_matrix")

    if not ("declared" in stripped.lower() and "not automatically detected" in stripped.lower()):
        failures.append("canonical_declared_not_detected")

    handoff_fields = ["BATCH_CONTEXT", "isolation classification", "expected worktree path",
                       "expected branch", "approved base branch", "artifact-owning repository",
                       "mutation classification"]
    for field in handoff_fields:
        if field not in raw:
            failures.append("canonical_handoff_metadata:" + field)

    if "## Repository arrangement (`workflow_hub`)" not in raw:
        failures.append("canonical_workflow_hub")

    failures.extend(check_canonical_dispatch(raw))

    return failures


def explicit_list_format_parity_real(root):
    fmt = "explicit_list_invocation_targets=<t1>,<t2>,..."
    files = {
        "canonical": CANON_REL,
        "guardrails": GUARDRAILS_SURFACE,
        "protocol90": "docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md",
        "spec": "docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md",
    }
    failures = []
    for name, rel in files.items():
        raw = read_path(root, rel)
        if fmt not in raw:
            failures.append("explicit_list_format_parity:" + name)
    return failures


def simulate_bounded_paths_real(root):
    failures = []
    spec_rel = "docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md"
    spec = read_path(root, spec_rel)
    canon = read_path(root, CANON_REL)

    def table_row_count(text, start_marker, end_marker):
        f = False
        count = 0
        for line in text.splitlines():
            if start_marker in line:
                f = True
                continue
            if end_marker in line:
                f = False
                continue
            if f and line.strip().startswith("|"):
                count += 1
        return count

    spec_rows = table_row_count(spec, "## Decision-Gate Consistency Matrix", "**Mirror surfaces**")
    canon_rows = table_row_count(canon, "### § Decision gate", "**Mirror surfaces**")
    if spec_rows != canon_rows:
        failures.append("simulate_bounded_paths:C1_row_count_mismatch(spec=%d,canon=%d)" % (spec_rows, canon_rows))
    if spec_rows < 3 or canon_rows < 3:
        failures.append("simulate_bounded_paths:C1_row_count_too_small")
    for stop in ("dispatch_profile_declaration_missing", "dispatch_handoff_unavailable",
                 "missing_required_secret_or_permission"):
        if stop not in canon:
            failures.append("simulate_bounded_paths:missing_stop_%s" % stop)
    return failures


MODEL_CONFIG_REL = "docs/workflow/development-workflow/agent-model-config.md"

# Decision 6: the exact profile assigned per Cursor environment x layer.
PROFILE_CODE_REF = {
    ("Cursor Desktop", "Portfolio"): "cursor-native-handoff",
    ("Cursor Desktop", "Epic"): "cursor-native-handoff",
    ("Cursor Desktop", "Item"): "cursor-native-handoff",
    ("Cursor Remote Control", "Portfolio"): "cursor-parent-orchestrated",
    ("Cursor Remote Control", "Epic"): "cursor-parent-orchestrated",
    ("Cursor Remote Control", "Item"): "cursor-parent-orchestrated",
    ("Cursor Cloud Agents", "Portfolio"): "cursor-inline-fallback",
    ("Cursor Cloud Agents", "Epic"): "cursor-inline-fallback",
    ("Cursor Cloud Agents", "Item"): "cursor-inline-fallback",
}


def check_model_config_real(root):
    """Real-surface counterpart to check_model_config(): the actual
    agent-model-config.md table layout has more columns (Rationale /
    per-layer model cells) than the synthetic fixture table, so the row
    regexes are looser (evidence marker is always the LAST cell)."""
    import re as _re
    text = read_path(root, MODEL_CONFIG_REL)
    failures = []

    profile_rows = _re.findall(
        r'^\|\s*(Cursor [A-Za-z]+(?: [A-Za-z]+)*)\s*\|\s*(Portfolio|Epic|Item)\s*\|\s*([^|]*?)\s*\|\s*([^|]*?)\s*\|[^|]*\|\s*$',
        text, _re.M)
    if len(profile_rows) != 9:
        failures.append("model-config rows")
    seen = {(e, l) for e, l, _, _ in profile_rows}
    expected = {(e, l) for e, l, _ in PROFILE_ROWS}
    if expected - seen:
        failures.append("model-config rows")

    for env, layer, profile_cell, marker in profile_rows:
        expected_code = PROFILE_CODE_REF.get((env, layer))
        if expected_code is not None and not identifier_present(profile_cell, expected_code):
            failures.append("model-config rows")

    ref_profile = {(e, l): m for e, l, m in PROFILE_ROWS}
    for env, layer, _profile_cell, marker in profile_rows:
        ref = ref_profile.get((env, layer))
        if ref is None:
            continue
        if not marker.strip():
            failures.append("evidence-marker")
        elif marker.strip().startswith("confirmed by observation") and ref == "explicit assumption":
            failures.append("evidence-marker")

    model_rows = _re.findall(
        r'^\|\s*(Cursor [A-Za-z]+(?: [A-Za-z]+)*)\s*\|[^|]*\|[^|]*\|[^|]*\|\s*([^|]*?)\s*\|\s*$',
        text, _re.M)
    ref_model = {e: m for e, m in MODEL_ROWS}
    for env, marker in model_rows:
        ref = ref_model.get(env)
        if ref is None:
            continue
        if not marker.strip():
            failures.append("evidence-marker")
        elif marker.strip().startswith("confirmed by observation") and ref == "explicit assumption":
            failures.append("evidence-marker")

    return failures


def explicit_list_tokens_missing(raw):
    """Boundary-aware check for the explicit-list sub-clause tokens (R4): a
    suffix lookalike such as `verbatim2` or `percent-encodedish` must not
    satisfy the requirement."""
    missing = []
    if "explicit_list_invocation_targets=" not in raw:
        missing.append("explicit_list_invocation_targets=")
    if not identifier_present(raw.lower(), "verbatim"):
        missing.append("verbatim")
    if not identifier_present(raw.lower(), "percent-encoded"):
        missing.append("percent-encoded")
    return missing


def parse_covers_header(text):
    """Parse leading '# covers: <path> <path> ...' lines (bounded to the
    comment header at the top of the file, mirroring select-test-suites.sh's
    own bounded parse)."""
    declared = set()
    for line in text.splitlines()[:40]:
        line = line.rstrip("\n")
        if line.startswith("#!"):
            continue
        if not line.startswith("#"):
            if line.strip() == "" or line.startswith("#"):
                continue
            break
        if "covers:" in line:
            rest = line.split("covers:", 1)[1]
            for tok in rest.split():
                declared.add(tok)
    return declared


def header_consistency_check(root):
    """The guard's own `# covers:` header must equal the set of paths it
    actually reads (read_path() calls) plus its selection-only entries (the
    fixtures glob, the smoke runbook, and itself)."""
    self_text = read_path(root, SELF_REL)
    declared = parse_covers_header(self_text)

    read_set = set(FULL_CONTRACT_SURFACES) | {
        GUARDRAILS_SURFACE, CANON_REL, MODEL_CONFIG_REL, SPEC_REL,
    }
    selection_only = {FIXTURES_GLOB, SMOKE_REL, SELF_REL}

    missing_from_covers = read_set - declared
    extra_in_covers = declared - read_set - selection_only

    failures = []
    if missing_from_covers:
        failures.append("header_consistency:missing=" + ",".join(sorted(missing_from_covers)))
    if extra_in_covers:
        failures.append("header_consistency:extra=" + ",".join(sorted(extra_in_covers)))
    return failures


def run_real(root):
    failures = {}

    for rel in FULL_CONTRACT_SURFACES:
        raw = read_path(root, rel)
        if not check_link(root, rel):
            failures.setdefault(rel, []).append("link")
        missing_profiles = check_profile_codes(raw)
        if missing_profiles:
            failures.setdefault(rel, []).append("profile-string:" + ",".join(missing_profiles))
        extra = "explicit_list" if rel in EXPLICIT_LIST_SURFACES else None
        clause_failures = check_clauses(raw, FULL_CLAUSES)
        if extra == "explicit_list":
            missing_el = explicit_list_tokens_missing(raw)
            if missing_el:
                clause_failures.append("E3b_explicit_list")
        if clause_failures:
            failures.setdefault(rel, []).extend(clause_failures)

    grel = GUARDRAILS_SURFACE
    graw = read_path(root, grel)
    if not check_link(root, grel):
        failures.setdefault(grel, []).append("link")
    gfail = check_clauses(graw, GUARDRAILS_CLAUSES)
    missing_el = explicit_list_tokens_missing(graw)
    if missing_el:
        gfail.append("E3b_explicit_list")
    if gfail:
        failures.setdefault(grel, []).extend(gfail)

    failures.setdefault("<structural>", [])
    failures["<structural>"].extend(canonical_checks(root))
    p90 = read_path(root, PROTOCOL_SURFACES[0])
    p91 = read_path(root, PROTOCOL_SURFACES[1])
    p95 = read_path(root, PROTOCOL_SURFACES[2])
    failures["<structural>"].extend(check_proto90(p90))
    failures["<structural>"].extend(check_proto91(p91))
    failures["<structural>"].extend(check_proto95(p95))
    failures["<structural>"].extend(explicit_list_format_parity_real(root))
    failures["<structural>"].extend(simulate_bounded_paths_real(root))
    failures["<structural>"].extend(
        "model-config:" + f for f in check_model_config_real(root))
    failures["<structural>"].extend(header_consistency_check(root))
    if not failures["<structural>"]:
        del failures["<structural>"]

    return failures


# ---- from selftest_dispatch.py ----
import json

FAMILY_OF_ROW = {}


def compute_family(rid, fname):
    if rid == 137:
        return "invalid_utf8"
    if fname.startswith("sim-"):
        return "sim"
    if fname.startswith(("ser-", "serialization-")):
        return "ser"
    if fname.startswith("class-model-config"):
        return "modelcfg"
    if rid in (149, 150, 151, 152, 153):
        return "proto90"
    if rid == 154:
        return "proto95"
    if rid == 155:
        return "proto91"
    if rid == 156:
        return "canonical_dispatch"
    if fname.startswith("parity-"):
        return "parity"
    return "fullcontract"


def normalize_clause_tag(tag):
    tag = tag.strip()
    tag = tag.replace("E3c stop 1", "E3c_stop1").replace("E3c stop 2", "E3c_stop2").replace("E3c stop 3", "E3c_stop3")
    if tag.upper() == "E3D":
        tag = "E3d"
    return tag


def expected_requirements(rid, expected_raw, unmet_clause_overrides):
    if expected_raw == "pass":
        return ("pass", set())
    assert expected_raw.startswith("fail: "), expected_raw
    rest = expected_raw[len("fail: "):]
    if rest == "E1-E6 each named":
        return ("fail_all_named", {"E1", "E2", "E3", "E4", "E5", "E6"})
    if rest == "the unmet clause":
        return ("fail", {unmet_clause_overrides[rid]})
    parts = [normalize_clause_tag(p) for p in rest.split(",")]
    return ("fail", set(parts))


def tag_satisfied(tag, failures):
    if tag == "E3c":
        return any(f.startswith("E3c") for f in failures)
    return tag in failures


def run_self_test(manifest_rows, content_by_id, unmet_clause_overrides,
                   check_clauses, check_profile_codes, FULL_CLAUSES, GUARDRAILS_CLAUSES,
                   check_simulation, check_serialization, check_model_config,
                   check_proto90, check_proto91, check_proto95, check_canonical_dispatch,
                   family_a_rows):
    mismatches = []
    for rid, fname, expected_raw in manifest_rows:
        family = compute_family(rid, fname)
        content = content_by_id[rid]

        if family == "invalid_utf8":
            try:
                content.decode("utf-8")
                failures = set()
            except UnicodeDecodeError:
                failures = {"R1"}
            except AttributeError:
                failures = set()
        elif family == "sim":
            failures = set(check_simulation(content))
        elif family == "ser":
            failures = set(check_serialization(content))
        elif family == "modelcfg":
            failures = set(check_model_config(content))
        elif family == "proto90":
            failures = set(check_proto90(content))
        elif family == "proto91":
            failures = set(check_proto91(content))
        elif family == "proto95":
            failures = set(check_proto95(content))
        elif family == "canonical_dispatch":
            failures = set(check_canonical_dispatch(content))
        elif family == "parity":
            failures = set()
            import re as _re
            FMT = "explicit_list_invocation_targets=<t1>,<t2>,..."
            sections = dict(_re.findall(r'^(Canonical|Guardrails|Protocol90|Spec):\s*`([^`]+)`', content, _re.M))
            for name in ("Canonical", "Guardrails", "Protocol90", "Spec"):
                if sections.get(name) != FMT:
                    failures.add("explicit_list_format_parity")
        else:  # fullcontract
            from_row = family_a_rows.get(rid, {})
            clauses = from_row.get("clauses", FULL_CLAUSES)
            failures = set(check_clauses(content, clauses))
            failures |= from_row.get("rule_tags", set())
            missing_profiles = check_profile_codes(content)
            if missing_profiles:
                failures.add("R4")

        kind, req = expected_requirements(rid, expected_raw, unmet_clause_overrides)

        if kind == "pass":
            ok = len(failures) == 0
        elif kind == "fail_all_named":
            broad = {f[:2] for f in failures}
            ok = req.issubset(broad)
        else:
            ok = all(tag_satisfied(t, failures) for t in req) and len(failures) > 0

        if not ok:
            mismatches.append((rid, fname, expected_raw, sorted(failures)))
    return mismatches


# ---- from manifest_table.py ----
MANIFEST_TABLE = [
    (1, 'boundary-token-first-byte.fixture.md', 'pass'),
    (2, 'boundary-token-last-byte-no-newline.fixture.md', 'pass'),
    (3, 'boundary-wrapped-phrase.fixture.md', 'pass'),
    (4, 'boundary-token-punctuation.fixture.md', 'pass'),
    (5, 'boundary-token-backtick.fixture.md', 'pass'),
    (6, 'boundary-empty-file.fixture.md', 'fail: E1-E6 each named'),
    (7, 'boundary-link-only.fixture.md', 'fail: E1-E6 each named'),
    (8, 'lookalike-longer-stop-name.fixture.md', 'fail: R4'),
    (9, 'lookalike-longer-profile-code.fixture.md', 'fail: R4'),
    (10, 'lookalike-case-posture.fixture.md', 'fail: E5'),
    (11, 'lookalike-case-stop-name.fixture.md', 'fail: E3a'),
    (12, 'lookalike-fenced-block.fixture.md', 'fail: R2'),
    (13, 'lookalike-html-comment.fixture.md', 'fail: R2'),
    (14, 'lookalike-observing-word.fixture.md', 'fail: E5'),
    (15, 'lookalike-split-paragraph.fixture.md', 'fail: R3'),
    (16, 'multi-token-many-clause-met.fixture.md', 'pass'),
    (17, 'multi-token-many-clause-unmet.fixture.md', 'fail: the unmet clause'),
    (18, 'multi-cross-surface-a-present.fixture.md', 'pass'),
    (19, 'multi-cross-surface-b-absent.fixture.md', 'fail: R5'),
    (20, 'multi-partial-actions.fixture.md', 'fail: E3c'),
    (21, 'multi-duplicate-link.fixture.md', 'pass'),
    (22, 'nested-clause-list-item.fixture.md', 'pass'),
    (23, 'nested-clause-blockquote.fixture.md', 'pass'),
    (24, 'nested-clause-table-cell.fixture.md', 'pass'),
    (25, 'nested-fenced-in-list.fixture.md', 'fail: R2'),
    (26, 'fence-tilde.fixture.md', 'fail: R2'),
    (27, 'fence-tilde-longer-closer.fixture.md', 'pass'),
    (28, 'fence-backtick-longer-closer.fixture.md', 'pass'),
    (29, 'fence-shorter-closer-inside.fixture.md', 'fail: R2'),
    (30, 'fence-mismatched-char-closer.fixture.md', 'fail: R2'),
    (31, 'fence-unclosed-eof.fixture.md', 'fail: R2'),
    (32, 'fence-unclosed-token-before.fixture.md', 'pass'),
    (33, 'fence-indent-3.fixture.md', 'fail: R2'),
    (34, 'fence-indent-4.fixture.md', 'pass'),
    (35, 'indented-code-token.fixture.md', 'fail: R2b'),
    (36, 'indented-code-tab.fixture.md', 'fail: R2b'),
    (37, 'indented-code-after-heading.fixture.md', 'fail: R2b'),
    (38, 'indented-code-multi-blank.fixture.md', 'fail: R2b'),
    (39, 'indented-code-paragraph-continuation.fixture.md', 'pass'),
    (40, 'indented-code-list-continuation.fixture.md', 'pass'),
    (41, 'indented-code-in-list.fixture.md', 'fail: R2b'),
    (42, 'indented-code-blockquote.fixture.md', 'fail: R2b'),
    (43, 'construct-blockquote-prose.fixture.md', 'pass'),
    (44, 'construct-table-cell.fixture.md', 'pass'),
    (45, 'table-row-spans-cells.fixture.md', 'pass'),
    (46, 'table-rows-split.fixture.md', 'fail: R3'),
    (47, 'table-header-separator.fixture.md', 'fail: R3'),
    (48, 'construct-linkref-def.fixture.md', 'fail: R2c'),
    (49, 'construct-link-destination.fixture.md', 'fail: R2c'),
    (50, 'construct-image-alt.fixture.md', 'fail: R2c'),
    (51, 'construct-code-span-identifier.fixture.md', 'pass'),
    (52, 'construct-code-span-phrase.fixture.md', 'fail: R2c'),
    (53, 'construct-pre-block.fixture.md', 'fail: R2c'),
    (54, 'construct-escaped-identifier.fixture.md', 'fail: R2c, R4'),
    (55, 'fence-closer-indent-4.fixture.md', 'fail: R2'),
    (56, 'comment-unclosed-eof.fixture.md', 'fail: R2'),
    (57, 'overlap-substring.fixture.md', 'fail: E1'),
    (58, 'overlap-e2a-deleted.fixture.md', 'fail: E2a'),
    (59, 'overlap-e2b-deleted.fixture.md', 'fail: E2b'),
    (60, 'sim-row-count-matches-spec.fixture.md', 'pass'),
    (61, 'sim-missing-row-r5.fixture.md', 'fail: C1, C2'),
    (62, 'sim-extra-row.fixture.md', 'fail: C1'),
    (63, 'sim-unmapped-scenario.fixture.md', 'fail: C3'),
    (64, 'sim-s10b-mapped-to-row.fixture.md', 'fail: C3'),
    (65, 'sim-rows-swapped.fixture.md', 'fail: C4'),
    (66, 'sim-wrong-stop-s12.fixture.md', 'fail: S12'),
    (67, 'sim-recovery-rejected-s7.fixture.md', 'fail: E4c'),
    (68, 'sim-harness-denial-mapped-s10b.fixture.md', 'fail: S10b'),
    (69, 'serialization-mixed-forms.fixture.md', 'pass'),
    (70, 'serialization-hash-added.fixture.md', 'fail: verbatim'),
    (71, 'serialization-hash-stripped.fixture.md', 'fail: verbatim'),
    (72, 'class-protocol-missing-e3d.fixture.md', 'fail: E3d'),
    (73, 'class-guardrails-exempt-clauses.fixture.md', 'pass'),
    (74, 'class-guardrails-missing-e4b.fixture.md', 'fail: E4b'),
    (75, 'class-model-config-missing-row.fixture.md', 'fail: model-config rows'),
    (76, 'class-model-config-rc-epic-overclaimed.fixture.md', 'fail: evidence-marker'),
    (77, 'class-model-config-desktop-model-overclaimed.fixture.md', 'fail: evidence-marker'),
    (78, 'class-model-config-marker-absent.fixture.md', 'fail: evidence-marker'),
    (79, 'e3c-stop1-profile-only.fixture.md', 'fail: E3c stop 1'),
    (80, 'e3c-stop1-no-posture.fixture.md', 'fail: E3c stop 1'),
    (81, 'e3c-stop1-no-role.fixture.md', 'fail: E3c stop 1'),
    (82, 'e3c-stop1-no-facts-profile.fixture.md', 'fail: E3c stop 1'),
    (83, 'e3c-stop2-no-stage-role-exception.fixture.md', 'fail: E3c stop 2'),
    (84, 'e3c-stop2-no-accept-read-only.fixture.md', 'fail: E3c stop 2'),
    (85, 'e3c-stop3-no-structural-path.fixture.md', 'fail: E3c stop 3'),
    (86, 'e3c-all-causes-present.fixture.md', 'pass'),
    (87, 'ser-percent-alone.fixture.md', 'pass'),
    (88, 'ser-percent-preexisting.fixture.md', 'pass'),
    (89, 'ser-interior-tab.fixture.md', 'pass'),
    (90, 'ser-interior-space.fixture.md', 'pass'),
    (91, 'ser-newline-unreachable-stated.fixture.md', 'pass'),
    (92, 'ser-newline-encoded-shown.fixture.md', 'fail: router-grammar'),
    (93, 'ser-interior-cr.fixture.md', 'pass'),
    (94, 'ser-control-0x1f.fixture.md', 'pass'),
    (95, 'ser-control-0x7f.fixture.md', 'pass'),
    (96, 'ser-lowercase-hex.fixture.md', 'fail: uppercase-hex'),
    (97, 'ser-non-ascii-unchanged.fixture.md', 'pass'),
    (98, 'ser-edge-trim-only.fixture.md', 'pass'),
    (99, 'ser-interior-trimmed.fixture.md', 'fail: edge-trim-only'),
    (100, 'ser-edge-encoded.fixture.md', 'fail: edge-trim-only'),
    (101, 'ser-order-preserved.fixture.md', 'pass'),
    (102, 'ser-order-sorted.fixture.md', 'fail: order-preserved'),
    (103, 'ser-delimiter-space.fixture.md', 'fail: delimiter'),
    (104, 'ser-single-target-rendered.fixture.md', 'fail: unreachable-forms'),
    (105, 'ser-empty-target-rendered.fixture.md', 'fail: unreachable-forms'),
    (106, 'ser-unreachable-stated.fixture.md', 'pass'),
    (107, 'ser-case-rewritten.fixture.md', 'fail: verbatim'),
    (108, 'ser-slash-rewritten.fixture.md', 'fail: verbatim'),
    (109, 'ser-comma-not-in-target.fixture.md', 'pass'),
    (110, 'ser-comma-target-rendered.fixture.md', 'fail: router-grammar'),
    (111, 'ser-percent-not-reencoded.fixture.md', 'fail: percent-encoding'),
    (112, 'ser-duplicates-deduped-first-kept.fixture.md', 'pass'),
    (113, 'ser-duplicates-rendered.fixture.md', 'fail: router-grammar'),
    (114, 'ser-hash-and-bare-distinct.fixture.md', 'pass'),
    (115, 'ser-hash-and-bare-deduped.fixture.md', 'fail: router-grammar'),
    (116, 'ser-tracker-id-accepted.fixture.md', 'fail: router-grammar'),
    (117, 'ser-tracker-id-unreachable-stated.fixture.md', 'pass'),
    (118, 'ser-router-grammar-stated.fixture.md', 'pass'),
    (119, 'ser-dot-slash-kept.fixture.md', 'pass'),
    (120, 'ser-dot-slash-stripped.fixture.md', 'fail: verbatim'),
    (121, 'clause-all-present.fixture.md', 'pass'),
    (122, 'clause-missing-e1.fixture.md', 'fail: E1'),
    (123, 'clause-missing-e2a.fixture.md', 'fail: E2a'),
    (124, 'clause-missing-e2b.fixture.md', 'fail: E2b'),
    (125, 'clause-missing-e3a.fixture.md', 'fail: E3a'),
    (126, 'clause-missing-e3b.fixture.md', 'fail: E3b'),
    (127, 'clause-missing-e3c.fixture.md', 'fail: E3c'),
    (128, 'clause-missing-e3d.fixture.md', 'fail: E3d'),
    (129, 'clause-missing-e4a.fixture.md', 'fail: E4a'),
    (130, 'clause-missing-e4b.fixture.md', 'fail: E4b'),
    (131, 'clause-missing-e4c.fixture.md', 'fail: E4c'),
    (132, 'clause-missing-e5.fixture.md', 'fail: E5'),
    (133, 'clause-missing-e6.fixture.md', 'fail: E6'),
    (134, 'scope-non-cursor-behavior-changed.fixture.md', 'fail: E6'),
    (135, 'r1-utf8-bom.fixture.md', 'pass'),
    (136, 'r1-utf8-multibyte.fixture.md', 'pass'),
    (137, 'r1-invalid-utf8.fixture.md', 'fail: R1'),
    (138, 'r3-whitespace-collapse.fixture.md', 'pass'),
    (139, 'r4-prefix-identifier.fixture.md', 'fail: R4'),
    (140, 'construct-list-item.fixture.md', 'pass'),
    (141, 'construct-heading.fixture.md', 'pass'),
    (142, 'construct-link-text.fixture.md', 'pass'),
    (143, 'construct-inline-html-text.fixture.md', 'pass'),
    (144, 'construct-autolink.fixture.md', 'fail: R2c'),
    (145, 'construct-code-html-block.fixture.md', 'fail: R2c'),
    (146, 'construct-entity-not-decoded.fixture.md', 'fail: R2c, R4'),
    (147, 'sim-path-applicability-not-asserted.fixture.md', 'pass'),
    (148, 'sim-path-applicability-asserted-na.fixture.md', 'fail: applicability'),
    (149, 'proto90-step4-condition-present.fixture.md', 'pass'),
    (150, 'proto90-step4-native-only.fixture.md', 'fail: protocol90_step4_condition'),
    (151, 'proto90-step4-generic-merged.fixture.md', 'fail: protocol90_step4_condition'),
    (152, 'proto90-step4-generic-altered.fixture.md', 'fail: protocol90_step4_condition'),
    (153, 'proto90-step4-unscoped-stage-rule.fixture.md', 'fail: protocol90_step4_condition'),
    (154, 'proto95-arrangement-missing.fixture.md', 'fail: protocol95_execution_arrangement'),
    (155, 'proto91-absorbed-sentence-missing.fixture.md', 'fail: protocol91_absorbed_layer_sentence'),
    (156, 'canonical-dispatch-table-missing.fixture.md', 'fail: canonical_dispatch_decision'),
    (157, 'parity-explicit-list-format-match.fixture.md', 'pass'),
    (158, 'parity-guardrails-mismatch.fixture.md', 'fail: explicit_list_format_parity'),
]


# ---- from main_entry.py ----
FIXTURES_DIR_NAME = "scripts/development-workflow/tests/fixtures/cursor-dispatch-profile-surfaces"

UNMET_CLAUSE_OVERRIDES = {17: "E4a"}


def write_fixtures(root):
    fixtures_dir = os.path.join(root, FIXTURES_DIR_NAME)
    os.makedirs(fixtures_dir, exist_ok=True)
    contents = build_all_fixture_contents()
    for rid, fname, _ in MANIFEST_TABLE:
        content = contents[rid]
        path = os.path.join(fixtures_dir, fname)
        if isinstance(content, bytes):
            with open(path, "wb") as f:
                f.write(content)
        else:
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
    return contents


def run_self_test_entry(root):
    fixtures_dir = os.path.join(root, FIXTURES_DIR_NAME)
    manifest_names = {fname for _, fname, _ in MANIFEST_TABLE}
    if len(manifest_names) != MANIFEST_COUNT:
        print("SELF-TEST FAIL: duplicate filename in manifest")
        return 1

    on_disk = set()
    if os.path.isdir(fixtures_dir):
        on_disk = {f for f in os.listdir(fixtures_dir) if f.endswith(".fixture.md")}
    if on_disk != manifest_names:
        missing = manifest_names - on_disk
        extra = on_disk - manifest_names
        print("SELF-TEST FAIL: fixture set does not match manifest exactly. "
              "missing=%s extra=%s" % (sorted(missing), sorted(extra)))
        return 1

    contents = {}
    for rid, fname, _ in MANIFEST_TABLE:
        path = os.path.join(fixtures_dir, fname)
        try:
            with open(path, "rb") as f:
                raw_bytes = f.read()
        except OSError as e:
            print("SELF-TEST FAIL: %s -- cannot read: %s" % (fname, e))
            return 1
        family = compute_family(rid, fname)
        if family == "invalid_utf8":
            contents[rid] = raw_bytes
        else:
            try:
                contents[rid] = raw_bytes.decode("utf-8")
            except UnicodeDecodeError as e:
                print("SELF-TEST FAIL: %s -- unexpected invalid UTF-8: %s" % (fname, e))
                return 1

    mismatches = run_self_test(
        MANIFEST_TABLE, contents, UNMET_CLAUSE_OVERRIDES,
        check_clauses, check_profile_codes, FULL_CLAUSES, GUARDRAILS_CLAUSES,
        check_simulation, check_serialization, check_model_config,
        check_proto90, check_proto91, check_proto95, check_canonical_dispatch,
        ROWS,
    )
    if mismatches:
        for rid, fname, expected, actual in mismatches:
            print("SELF-TEST FAIL: %s -- expected %s, got failures: %s" % (fname, expected, actual))
        return 1

    print("SELF-TEST PASS: %d fixtures matched expectations (MANIFEST_COUNT=%d)" % (MANIFEST_COUNT, MANIFEST_COUNT))
    return 0


MANIFEST_COUNT = len(MANIFEST_TABLE)

if MODE == "--self-test":
    write_fixtures(ROOT)
    rc = run_self_test_entry(ROOT)
    sys.exit(rc)
elif MODE == "--write-fixtures":
    write_fixtures(ROOT)
    print("Wrote %d fixtures to %s" % (MANIFEST_COUNT, os.path.join(ROOT, FIXTURES_DIR_NAME)))
    sys.exit(0)
else:
    failures = run_real(ROOT)
    if failures:
        for surface, items in failures.items():
            print("FAIL: %s -- %s" % (surface, ", ".join(items)))
        sys.exit(1)
    print("PASS: all %d Cursor dispatch-profile surfaces satisfy the mirror-content contract" % len(FULL_CONTRACT_SURFACES))
    sys.exit(0)

PY

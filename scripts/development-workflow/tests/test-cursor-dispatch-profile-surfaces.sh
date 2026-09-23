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
# tokens, that the canonical doc carries its own structural requirements,
# and that the Protocol 90/91/95 Decision-7 exact-text insertions and the
# explicit-list format string stay in parity across the canonical guide,
# guardrails-enforcement.md, Protocol 90, and the merged spec.
#
# Usage:
#   test-cursor-dispatch-profile-surfaces.sh            # check real repo surfaces
#   test-cursor-dispatch-profile-surfaces.sh --self-test # run scanner fixtures
set -euo pipefail
ROOT=${SURFACE_ROOT:-"$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"}
MODE="${1:-}"
python3 - "$ROOT" "$MODE" <<'PY'
import os, re, sys

ROOT = sys.argv[1]
MODE = sys.argv[2] if len(sys.argv) > 2 else ""

CANON_REL = "docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md"

# ---------------------------------------------------------------------------
# Structured-Markdown scanning primitives (Parser-Risk Addendum, scoped subset)
# ---------------------------------------------------------------------------

def strip_fences_and_comments(text):
    """Remove fenced code blocks (backtick/tilde, CommonMark-subset semantics)
    and HTML comments before token matching (scanner rule R2)."""
    out = []
    i = 0
    n = len(text)
    lines = text.split("\n")
    idx = 0
    fence_char = None
    fence_len = 0
    in_fence = False
    result_lines = []
    while idx < len(lines):
        line = lines[idx]
        if not in_fence:
            stripped = line.lstrip(" ")
            indent = len(line) - len(stripped)
            m = re.match(r'^(`{3,}|~{3,})(.*)$', stripped)
            if indent <= 3 and m and not (m.group(1)[0] == '`' and '`' in m.group(2)):
                fence_char = m.group(1)[0]
                fence_len = len(m.group(1))
                in_fence = True
                result_lines.append("")  # fence marker line itself carries no prose
                idx += 1
                continue
            result_lines.append(line)
            idx += 1
        else:
            stripped = line.lstrip(" ")
            indent = len(line) - len(stripped)
            m = re.match(r'^(`{3,}|~{3,})\s*$', stripped)
            if indent <= 3 and m and m.group(1)[0] == fence_char and len(m.group(1)) >= fence_len:
                in_fence = False
                result_lines.append("")
                idx += 1
                continue
            result_lines.append("")  # inside fence: stripped
            idx += 1
    text = "\n".join(result_lines)
    # HTML comments (greedy-safe, non-nesting): strip <!-- ... --> including unclosed-to-EOF
    text = re.sub(r'<!--.*?-->', '', text, flags=re.S)
    text = re.sub(r'<!--.*$', '', text, flags=re.S)
    return text


def blocks(text):
    """Split into blank-line-delimited blocks; join soft-wrapped lines within
    a block and collapse whitespace (scanner rule R3, table-row block treated
    as its own block by joining pipe-delimited cells with a single space)."""
    raw_blocks = re.split(r'\n\s*\n', text)
    out = []
    for b in raw_blocks:
        b = b.strip()
        if not b:
            continue
        if '\n' in b and all(l.strip().startswith('|') for l in b.splitlines() if l.strip()):
            # Table: treat every row as its own block (skip header separator rows)
            for row in b.splitlines():
                row = row.strip()
                if not row or re.match(r'^\|[\s:|-]+\|$', row):
                    continue
                cells = [c.strip() for c in row.strip('|').split('|')]
                out.append(' '.join(cells))
            continue
        joined = ' '.join(l.strip() for l in b.splitlines())
        joined = re.sub(r'\s+', ' ', joined)
        out.append(joined)
    return out


def read_path(rel):
    allowed_prefixes = (
        ".cursor/commands/", ".claude/commands/", ".agents/skills/",
        ".cursor/agents/", ".claude/agents/", ".codex/skills/",
        "docs/workflow/development-workflow/protocols/",
        "docs/workflow/development-workflow/guardrails-enforcement.md",
        "docs/workflow/development-workflow/agent-model-config.md",
        "docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md",
        ".cursor/rules/workflow.mdc",
        "docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/",
    )
    if not rel.startswith(allowed_prefixes):
        raise SystemExit("read_path() refused an undeclared path: %s" % rel)
    path = os.path.join(ROOT, rel)
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


# ---------------------------------------------------------------------------
# Token list (single shared source; canonical wording changes touch only here)
# ---------------------------------------------------------------------------

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
    "E3b_explicit_list": ["explicit_list_invocation_targets=", "verbatim", "percent-encoded"],
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

PROFILE_CODES = ["cursor-native-handoff", "cursor-parent-orchestrated", "cursor-inline-fallback"]

FULL_CLAUSES = ["E1", "E2a", "E2b", "E3a", "E3b", "E3c_stop1", "E3c_stop2", "E3c_stop3",
                "E3d", "E4a", "E4b", "E4c", "E5", "E6"]

# Surfaces requiring the E3b explicit-list serialization tokens in addition
EXPLICIT_LIST_SURFACES = {
    "docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md",
    ".cursor/commands/run-items.md", ".claude/commands/run-items.md",
    ".agents/skills/run-items/SKILL.md",
    "docs/workflow/development-workflow/guardrails-enforcement.md",
}

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

GUARDRAILS_CLAUSES = ["E3a", "E3b", "E3c_stop1", "E3c_stop2", "E3c_stop3", "E3d", "E4a", "E4b", "E6"]


def norm(s):
    """Case- and emphasis-marker-insensitive normalization for prose-phrase
    matching. Bold/italic asterisks and inline-code backticks are stripped so
    a required phrase split by markdown emphasis, or wrapped in a code span,
    still matches; matching is case-insensitive throughout this scanner
    (a deliberate, documented implementation choice -- see PR description)."""
    return s.replace("*", "").replace("`", "").lower()


def contains_all_same_block(block_list, tokens):
    norm_tokens = [norm(t) for t in tokens]
    for b in block_list:
        nb = norm(b)
        if all(t in nb for t in norm_tokens):
            return True
    return False


IDENTIFIER_TOKEN_RE = re.compile(r'^[a-z][a-z0-9_-]*$')


def contains_token_anywhere(full_text, token):
    normalized_text = norm(full_text)
    normalized_token = norm(token)
    if IDENTIFIER_TOKEN_RE.match(normalized_token):
        return identifier_present(normalized_text, normalized_token)
    return normalized_token in normalized_text


def check_clauses(rel, clauses, extra=None):
    """Return list of failing clause IDs for the given surface."""
    raw = read_path(rel)
    stripped = strip_fences_and_comments(raw)
    block_list = blocks(stripped)
    full_flat = "\n".join(block_list)
    failures = []
    for clause in clauses:
        tokens = CLAUSE_TOKENS[clause]
        if clause in ("E2a", "E2b", "E3d", "E6"):
            # same-paragraph requirement
            if not contains_all_same_block(block_list, tokens):
                failures.append(clause)
        else:
            if not all(contains_token_anywhere(full_flat, t) for t in tokens):
                failures.append(clause)
    if extra == "explicit_list":
        for t in CLAUSE_TOKENS["E3b_explicit_list"]:
            if not contains_token_anywhere(full_flat, t):
                failures.append("E3b_explicit_list")
                break
    return failures


def identifier_present(text, ident):
    """Boundary-aware identifier match (scanner rule R4): a lookalike such as
    `cursor-native-handoffs` or `dispatch_handoff_unavailable_x` must not
    satisfy a match for the shorter identifier."""
    pattern = r'(?<![A-Za-z0-9_-])' + re.escape(ident) + r'(?![A-Za-z0-9_-])'
    return re.search(pattern, text) is not None


def check_profile_strings(rel):
    raw = read_path(rel)
    stripped = strip_fences_and_comments(raw)
    missing = [c for c in PROFILE_CODES if not identifier_present(stripped, c)]
    return missing


def check_link(rel):
    raw = read_path(rel)
    stripped = strip_fences_and_comments(raw)
    return CANON_REL in stripped or "integrations/cursor-dispatch-profiles.md" in stripped


# ---------------------------------------------------------------------------
# Canonical-doc structural checks
# ---------------------------------------------------------------------------

def canonical_checks():
    raw = read_path(CANON_REL)
    stripped = strip_fences_and_comments(raw)
    failures = []

    if not all(h in stripped for h in ("### Portfolio layer", "### Epic layer", "### Item layer")):
        failures.append("canonical_layers")
    for kw in ("Governing contract", "Entering commands", "Constrained-environment behavior"):
        if kw not in raw:
            failures.append("canonical_layers")
            break

    if "## Perform / hand off / prohibit matrix" not in raw:
        failures.append("canonical_matrix")

    if not ("declared" in stripped and "not automatically detected" in stripped):
        failures.append("canonical_declared_not_detected")

    handoff_fields = ["BATCH_CONTEXT", "isolation classification", "expected worktree path",
                       "expected branch", "approved base branch", "artifact-owning repository",
                       "mutation classification"]
    for field in handoff_fields:
        if field not in raw:
            failures.append("canonical_handoff_metadata:" + field)

    if "## Repository arrangement (`workflow_hub`)" not in raw:
        failures.append("canonical_workflow_hub")

    normalized = raw.replace("*", "").replace("`", "").lower()
    dispatch_tokens = ["absorbs the portfolio layer", "dispatches no work item runner",
                        "/run-item", "/run-items", "/run-epic", "/run-work"]
    if not all(t in normalized for t in dispatch_tokens):
        failures.append("canonical_dispatch_decision")

    return failures


def protocol_condition_checks():
    failures = []
    p90 = read_path("docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md")
    generic = ("If the runner does **not** support Work Item Runner handoff natively, "
               "continue in the current session by following `91-orchestrate-work-protocol.md` "
               "for each item one at a time.")
    if p90.count(generic) != 1:
        failures.append("protocol90_step4_condition:generic_paragraph")
    new_para_tokens = ["cursor-parent-orchestrated", "do not dispatch Work Item Runners",
                        "one at a time", "absorbed the portfolio layer", "stage role",
                        "only when a Cursor dispatch profile is declared"]
    stripped90 = strip_fences_and_comments(p90)
    if not contains_all_same_block(blocks(stripped90), new_para_tokens):
        failures.append("protocol90_step4_condition:new_paragraph")

    p95 = read_path("docs/workflow/development-workflow/protocols/95-run-epic-protocol.md")
    if not ("absorbs the epic layer" in p95 and "dispatches no Work Item Runner" in p95
            and "Execution arrangement" in p95):
        failures.append("protocol95_execution_arrangement")

    p91 = read_path("docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md")
    if "stage delegation as\nthe only handoff" not in p91 and "stage delegation as the only handoff" not in p91.replace("\n", " "):
        failures.append("protocol91_absorbed_layer_sentence")

    return failures


def explicit_list_format_parity():
    fmt = "explicit_list_invocation_targets=<t1>,<t2>,..."
    files = {
        "canonical": CANON_REL,
        "guardrails": GUARDRAILS_SURFACE,
        "protocol90": "docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md",
        "spec": "docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md",
    }
    failures = []
    for name, rel in files.items():
        raw = read_path(rel)
        if fmt not in raw:
            failures.append("explicit_list_format_parity:" + name)
    return failures


def simulate_bounded_paths():
    """Simplified decision-matrix validation (C1): the canonical doc's
    Decision-gate table row count matches the merged spec's Decision-Gate
    Consistency Matrix row count."""
    failures = []
    spec_rel = "docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md"
    spec = read_path(spec_rel)
    canon = read_path(CANON_REL)

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
    # Named stop conditions each appear at least once in the canonical decision gate
    for stop in ("dispatch_profile_declaration_missing", "dispatch_handoff_unavailable",
                 "missing_required_secret_or_permission"):
        if stop not in canon:
            failures.append("simulate_bounded_paths:missing_stop_%s" % stop)
    return failures


# ---------------------------------------------------------------------------
# Real-surface run
# ---------------------------------------------------------------------------

def run_real():
    failures = {}

    for rel in FULL_CONTRACT_SURFACES:
        if not check_link(rel):
            failures.setdefault(rel, []).append("link")
        missing_profiles = check_profile_strings(rel)
        if missing_profiles:
            failures.setdefault(rel, []).append("profile-string:" + ",".join(missing_profiles))
        extra = "explicit_list" if rel in EXPLICIT_LIST_SURFACES else None
        clause_failures = check_clauses(rel, FULL_CLAUSES, extra=extra)
        if clause_failures:
            failures.setdefault(rel, []).extend(clause_failures)

    # Guardrails: reduced clause set (see surface-class table)
    grel = GUARDRAILS_SURFACE
    if not check_link(grel):
        failures.setdefault(grel, []).append("link")
    gfail = check_clauses(grel, GUARDRAILS_CLAUSES, extra="explicit_list")
    if gfail:
        failures.setdefault(grel, []).extend(gfail)

    for chk in (canonical_checks, protocol_condition_checks, explicit_list_format_parity,
                simulate_bounded_paths):
        result = chk()
        if result:
            failures.setdefault("<structural>", []).extend(result)

    return failures


# ---------------------------------------------------------------------------
# Fixture self-test (scoped subset; see PR description for scope note)
# ---------------------------------------------------------------------------

FIXTURES_DIR = os.path.join(
    ROOT, "scripts/development-workflow/tests/fixtures/cursor-dispatch-profile-surfaces")

# Manifest: (fixture filename, expected: "pass" or a substring that must be
# named in the failure output on non-zero exit)
MANIFEST = [
    ("clause-all-present.fixture.md", "pass"),
    ("clause-missing-e1.fixture.md", "E1"),
    ("clause-missing-e2a.fixture.md", "E2a"),
    ("clause-missing-e2b.fixture.md", "E2b"),
    ("clause-missing-e3a.fixture.md", "E3a"),
    ("clause-missing-e3b.fixture.md", "E3b"),
    ("clause-missing-e3c-stop1.fixture.md", "E3c_stop1"),
    ("clause-missing-e3c-stop2.fixture.md", "E3c_stop2"),
    ("clause-missing-e3c-stop3.fixture.md", "E3c_stop3"),
    ("clause-missing-e3d.fixture.md", "E3d"),
    ("clause-missing-e4a.fixture.md", "E4a"),
    ("clause-missing-e4b.fixture.md", "E4b"),
    ("clause-missing-e4c.fixture.md", "E4c"),
    ("clause-missing-e5.fixture.md", "E5"),
    ("clause-missing-e6.fixture.md", "E6"),
    ("lookalike-fenced-block.fixture.md", "E1"),
    ("lookalike-html-comment.fixture.md", "E1"),
    ("lookalike-split-paragraph-e2a.fixture.md", "E2a"),
    ("boundary-token-punctuation.fixture.md", "pass"),
    ("boundary-wrapped-phrase.fixture.md", "pass"),
    ("boundary-empty-file.fixture.md", "E1"),
    ("multi-cross-surface-present.fixture.md", "pass"),
]

MANIFEST_COUNT = len(MANIFEST)


def build_full_contract_fixture(missing_clause=None, split_paragraph_clause=None,
                                 wrap_in_fence=False, wrap_in_comment=False, empty=False):
    if empty:
        return ""
    parts = []
    parts.append(
        "Declare a profile per "
        "`docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md`: "
        "`cursor-native-handoff`, `cursor-parent-orchestrated`, or `cursor-inline-fallback`.\n\n"
    )
    clause_paragraphs = {
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
            "Grant the identified credential and re-run the same delegated action, "
            "or reassign to the same stage role or explicitly accept the action "
            "does not proceed; the absorbing context never performs it inline.\n\n"
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
    for clause, para in clause_paragraphs.items():
        if clause == missing_clause:
            continue
        if clause == split_paragraph_clause:
            half = len(para) // 2
            parts.append(para[:half] + "\n\n" + para[half:])
            continue
        parts.append(para)
    body = "".join(parts)
    if wrap_in_fence:
        body = "```text\n" + body + "\n```\n"
    if wrap_in_comment:
        body = "<!--\n" + body + "\n-->\n"
    return body


def write_fixtures():
    os.makedirs(FIXTURES_DIR, exist_ok=True)
    fixtures = {}
    fixtures["clause-all-present.fixture.md"] = build_full_contract_fixture()
    for clause in FULL_CLAUSES:
        slug = clause.lower().replace("_", "-")
        fixtures["clause-missing-%s.fixture.md" % slug] = build_full_contract_fixture(missing_clause=clause)
    fixtures["lookalike-fenced-block.fixture.md"] = build_full_contract_fixture(wrap_in_fence=True)
    fixtures["lookalike-html-comment.fixture.md"] = build_full_contract_fixture(wrap_in_comment=True)
    fixtures["lookalike-split-paragraph-e2a.fixture.md"] = build_full_contract_fixture(split_paragraph_clause="E2a")
    fixtures["boundary-token-punctuation.fixture.md"] = build_full_contract_fixture() + "\n\n(`dispatch_handoff_unavailable`, and other tokens.)\n"
    wrapped = build_full_contract_fixture()
    fixtures["boundary-wrapped-phrase.fixture.md"] = wrapped.replace(
        "only once initial handoff is confirmed",
        "only once initial\nhandoff is confirmed")
    fixtures["boundary-empty-file.fixture.md"] = build_full_contract_fixture(empty=True)
    fixtures["multi-cross-surface-present.fixture.md"] = build_full_contract_fixture() + build_full_contract_fixture()
    for name, content in fixtures.items():
        with open(os.path.join(FIXTURES_DIR, name), "w", encoding="utf-8") as f:
            f.write(content)
    return fixtures


def run_self_test():
    on_disk = set()
    if os.path.isdir(FIXTURES_DIR):
        on_disk = {f for f in os.listdir(FIXTURES_DIR) if f.endswith(".fixture.md")}
    manifest_names = {name for name, _ in MANIFEST}
    if len(manifest_names) != MANIFEST_COUNT:
        print("SELF-TEST FAIL: duplicate filename in manifest")
        return 1
    if on_disk and on_disk != manifest_names:
        missing = manifest_names - on_disk
        extra = on_disk - manifest_names
        print("SELF-TEST FAIL: fixture set does not match manifest exactly. "
              "missing=%s extra=%s" % (sorted(missing), sorted(extra)))
        return 1

    failed = []
    for name, expected in MANIFEST:
        path = os.path.join(FIXTURES_DIR, name)
        try:
            with open(path, "r", encoding="utf-8") as f:
                raw = f.read()
        except OSError as e:
            failed.append((name, "cannot read: %s" % e))
            continue
        stripped = strip_fences_and_comments(raw)
        block_list = blocks(stripped)
        full_flat = "\n".join(block_list)
        clause_failures = []
        for clause in FULL_CLAUSES:
            tokens = CLAUSE_TOKENS[clause]
            if clause in ("E2a", "E2b", "E3d", "E6"):
                if not contains_all_same_block(block_list, tokens):
                    clause_failures.append(clause)
            else:
                if not all(contains_token_anywhere(full_flat, t) for t in tokens):
                    clause_failures.append(clause)
        if expected == "pass":
            if clause_failures:
                failed.append((name, "expected pass, got failures: %s" % clause_failures))
        else:
            if expected not in clause_failures:
                failed.append((name, "expected failure naming %s, got: %s" % (expected, clause_failures)))

    if failed:
        for name, reason in failed:
            print("SELF-TEST FAIL: %s -- %s" % (name, reason))
        return 1
    print("SELF-TEST PASS: %d fixtures matched expectations (MANIFEST_COUNT=%d)" % (len(MANIFEST), MANIFEST_COUNT))
    return 0


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if MODE == "--self-test":
    write_fixtures()
    rc = run_self_test()
    sys.exit(rc)
elif MODE == "--write-fixtures":
    write_fixtures()
    print("Wrote %d fixtures to %s" % (MANIFEST_COUNT, FIXTURES_DIR))
    sys.exit(0)
else:
    failures = run_real()
    if failures:
        for surface, items in failures.items():
            print("FAIL: %s -- %s" % (surface, ", ".join(items)))
        sys.exit(1)
    print("PASS: all %d Cursor dispatch-profile surfaces satisfy the mirror-content contract" % len(FULL_CONTRACT_SURFACES))
    sys.exit(0)
PY

#!/usr/bin/env bash
# covers: docs/workflow/development-workflow/protocols/09-review-backlog-protocol.md
# covers: .claude/commands/review-backlog.md
# covers: .cursor/commands/review-backlog.md
# covers: .agents/skills/review-backlog/SKILL.md
# covers: .agents/skills/review-backlog/agents/openai.yaml
# covers: docs/testing/workflow/review-backlog-protocol.smoke-test.md
# covers: docs/workflow/development-workflow/README.md
# covers: AGENTS.md
#
# Documentation-contract suite for the backlog review protocol (#2155).
# Fixed substring checks plus one bounded regex (provider names only inside
# the capability-resolution block). Planted-violation proofs run against
# temporary copies, never the working files.
set -euo pipefail
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
DOC_ROOT="${REVIEW_BACKLOG_DOC_ROOT:-$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)}"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/../workflow-lib.sh"
TEMPLATE_MODE="$(workflow_template_is_template "$DOC_ROOT/.ai-dev-workflow.yaml")"
python3 -B - "$DOC_ROOT" "$TEMPLATE_MODE" <<'PY'
import re
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1])
template_mode = sys.argv[2] == "true"

PROTOCOL = "docs/workflow/development-workflow/protocols/09-review-backlog-protocol.md"
README = "docs/workflow/development-workflow/README.md"
RUNBOOK = "docs/testing/workflow/review-backlog-protocol.smoke-test.md"
ALIASES = [
    ".claude/commands/review-backlog.md",
    ".cursor/commands/review-backlog.md",
    ".agents/skills/review-backlog/SKILL.md",
]
START = "<!-- capability-resolution:start -->"
END = "<!-- capability-resolution:end -->"
PROVIDER_RE = re.compile(
    r"\b(?:Linear|Jira|GitHub Issues|GitHub Projects|github_projects|github_issues)\b"
    r"|`(?:linear|jira|none)`"
)
CAPABILITIES = [
    "project scope", "milestone scope", "parent/child hierarchy",
    "priority field", "priority that can be left unset",
    "classification carrier", "free-form labels", "item closure",
    "duplicate relation", "readable rate-limit surface",
]
MULTI_WORD_STATUSES = [
    "Writing Spec", "Spec in Review", "Spec Ready", "Writing Plan",
    "Plan in Review", "Plan Ready", "In Development", "Development in Review",
]
PROTOCOL_FRAGMENTS = {
    "AC6 three gates in order": [
        "Gate 1 — structural ledger", "Gate 2 — order", "Gate 3 — closeout",
        "Each gate waits for the maintainer's confirmation",
        "grouping by class never removes a confirmation",
    ],
    "AC7 authority and readback": [
        "Confirmation **in the conversation** is the write authority",
        "There is no flag", "the exact set",
        "print the **observed value** per row", "is `drift` and counts as\n  unapplied",
        "A readback that fails or cannot be read is a rejection",
        "A confirmation naming that item, or a group the run presented by name",
        "explicit per-item or per-group form",
        "delivered as proposed text",
        "status regressions; dependency edits; tracker rank fields",
    ],
    "AC13 scope stop-and-ask": [
        "no project configured | **Stop before reading.**",
        "Two configured identifiers name different projects (or different milestones) | **Stop before reading**",
        "A configured scope the tracker rejects or cannot find",
        "Scope is never widened silently",
        "The whole repository's items",
    ],
    "AC15 sweeps and evidence": [
        "### 1i. Landed-work sweep (mandatory)", "### 1j. Epic sweep (mandatory)",
        "on every full\nrun", "**seed, not\n   exhaustive**", "`no claim`",
        "is held, never guessed",
    ],
    "AC16 recommendations": [
        "exactly one\nrecommendation", "**Recomiendo:**", "**Por qué:**",
        "**Si no:**", "**Confianza:**",
    ],
    "AC17 admission and transitions": [
        "Writes are admitted **once per gate, before its first write**",
        "Either the whole confirmed set fits and is applied, or\n  nothing is applied",
        "The set is applied in order and the first rejection\n  stops it",
        "**A `partial` read ends at the Gate 1 close.**",
        "only marks Gate 3's final backlog state `partial`",
        "**Early-end delivery.**",
    ],
    "AC8 relationship": [
        "complements `/run-work`", "before batch selection", "never dispatches",
    ],
    "BR3/BR15 detection and precedents": [
        "marked `unverified`", "Detection failure never yields `no aplica`",
        "docs/project/backlog-review-precedents.md",
        "The run **never writes repository files**",
    ],
}
REFERENCES = ["tracker-status-mapping.md", "00-add-backlog-item-protocol.md"]
RUNBOOK_FRAGMENTS = ["**Maps to**: AC3", "**Maps to**: AC4", "**Maps to**: AC5",
                     "Early end delivers pending items"]
AGENTS_ROW = ("| Review backlog | `/review-backlog` | `/review-backlog` | "
              "`/review-backlog` alias | `/review-backlog` alias | Follow "
              "`docs/workflow/development-workflow/protocols/09-review-backlog-protocol.md`")

failures = []


def line_of(text, index):
    return text.count("\n", 0, index) + 1


def check_provider_neutral(name, text):
    """AC1: provider names only inside one capability-resolution block."""
    errs = []
    starts = text.count(START)
    ends = text.count(END)
    if starts != 1 or ends != 1:
        errs.append(f"{name}: capability-resolution block must appear exactly once "
                    f"(start={starts}, end={ends})")
        return errs
    s, e = text.index(START), text.index(END)
    if e < s:
        errs.append(f"{name}: capability-resolution end marker precedes start")
        return errs
    seen = set()
    for m in PROVIDER_RE.finditer(text):
        if s < m.start() < e:
            continue
        ln = line_of(text, m.start())
        if ln not in seen:
            seen.add(ln)
            errs.append(f"{name}:{ln}: provider name '{m.group(0)}' outside the "
                        "capability-resolution block")
    return errs


def check_capability_table(name, text):
    errs = []
    if text.count(START) != 1 or text.count(END) != 1:
        return [f"{name}: capability-resolution block missing or duplicated"]
    block = text[text.index(START):text.index(END)]
    for cap in CAPABILITIES:
        if f"| {cap} |" not in block:
            errs.append(f"{name}: capability row '{cap}' missing from the block")
    if "no aplica" not in block:
        errs.append(f"{name}: capability block lacks the 'no aplica' outcome")
    return errs


def check_no_status_copies(name, text):
    """AC14: no multi-word canonical Status name is restated."""
    errs = []
    for status in MULTI_WORD_STATUSES:
        idx = text.find(status)
        if idx >= 0:
            errs.append(f"{name}:{line_of(text, idx)}: restates canonical Status "
                        f"'{status}'")
    for ref in REFERENCES:
        if ref not in text:
            errs.append(f"{name}: missing reference to {ref}")
    return errs


def check_alias(name, text):
    """AC9: alias points at the protocol and accepts no apply flag."""
    errs = []
    if PROTOCOL not in text:
        errs.append(f"{name}:1: alias does not point at {PROTOCOL}")
    idx = text.find("--apply")
    if idx >= 0:
        errs.append(f"{name}:{line_of(text, idx)}: alias mentions --apply")
    return errs


def check_fragments(name, text, groups):
    errs = []
    for label, fragments in groups.items():
        for fragment in fragments:
            if fragment not in text:
                errs.append(f"{name}: [{label}] missing fragment {fragment!r}")
    return errs


def read(rel):
    path = root / rel
    if not path.is_file():
        failures.append(f"{rel}: file missing")
        return ""
    return path.read_text()


protocol = read(PROTOCOL)
failures += check_provider_neutral(PROTOCOL, protocol)
failures += check_capability_table(PROTOCOL, protocol)
failures += check_no_status_copies(PROTOCOL, protocol)
failures += check_fragments(PROTOCOL, protocol, PROTOCOL_FRAGMENTS)

readme = read(README)
failures += check_fragments(README, readme, {
    "AC8/AC9 workflow guide": ["complements `/run-work`", "`/review-backlog`",
                               "protocols/09-review-backlog-protocol.md"]})

for alias in ALIASES:
    failures += check_alias(alias, read(alias))
openai = read(".agents/skills/review-backlog/agents/openai.yaml")
if "allow_implicit_invocation: false" not in openai:
    failures.append(".agents/skills/review-backlog/agents/openai.yaml: implicit "
                    "invocation must be disabled")

runbook = read(RUNBOOK)
failures += check_fragments(RUNBOOK, runbook, {"AC3-AC5, AC11 runbook": RUNBOOK_FRAGMENTS})

# T2: AGENTS.md is project-owned in consumers (#1873); assert only in the template.
if template_mode:
    agents = read("AGENTS.md")
    if AGENTS_ROW not in agents:
        failures.append("AGENTS.md: Workflow Commands table lacks the Review backlog row")
    if "`/add-backlog-item`, `/review-backlog`" not in agents:
        failures.append("AGENTS.md: Codex alias list lacks /review-backlog")
else:
    print("SKIP AGENTS.md row check: not the template repository")

# Regex edge cases (parser-risk note in the plan).
def block(body_in, body_out=""):
    return f"intro\n{START}\n{body_in}\n{END}\n{body_out}\n"

edge_cases = [
    ("name inside block allowed", block("GitHub Projects and `linear`"), 0),
    ("name after end marker fails", block("ok", "Jira"), 1),
    ("non-linear prose not matched", block("ok", "a non-linear path"), 0),
    ("two names one line, one failure", block("ok", "Linear or Jira"), 1),
    ("second marker pair fails", block("ok") + block("ok"), 1),
]
for label, text, expected in edge_cases:
    got = len(check_provider_neutral("edge", text))
    if got != expected:
        failures.append(f"regex edge case '{label}': expected {expected} failure(s), got {got}")


# T3: planted-violation proofs against temporary copies.
def proof(name, rel, original, mutate, check):
    with tempfile.TemporaryDirectory() as tmp:
        copy = Path(tmp) / Path(rel).name
        copy.write_text(mutate(original))
        errs = check(rel, copy.read_text())
        if not errs:
            failures.append(f"PROOF {name}: planted violation was not detected")
            return
        loc = errs[0].split(": ", 1)[0]
        print(f"PROOF {name}: FAIL at {loc}")
        copy.write_text(original)
        errs = check(rel, copy.read_text())
        if errs:
            failures.append(f"PROOF {name}: repaired copy still fails: {errs[0]}")
            return
        print(f"PROOF {name}: PASS after repair")


if protocol and not failures:
    proof("provider-outside-block", PROTOCOL, protocol,
          lambda t: t + "\nConfigure GitHub Projects first.\n", check_provider_neutral)
    alias_text = read(ALIASES[0])
    proof("alias-without-protocol-path", ALIASES[0], alias_text,
          lambda t: t.replace(PROTOCOL, "docs/workflow/elsewhere.md"), check_alias)
    proof("restated-status-name", PROTOCOL, protocol,
          lambda t: t.replace("the initial backlog status |", "Plan in Review |", 1),
          check_no_status_copies)

if failures:
    for f in failures:
        print(f"FAIL {f}")
    sys.exit(1)
print("PASS test-review-backlog-protocol: all contract cases and proofs")
PY

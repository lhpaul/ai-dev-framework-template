#!/usr/bin/env bash
# test-cursor-model-pin-guidance.sh — Cursor stage-agent model selection keeps
# pointing at the local .cursor/agents/<agent>.md pins, not at the template
# model tables (#1378).
#
# Why this exists: a downstream /run-item run planned stage-agent models from
# the template "Cursor model defaults" table in agent-model-config.md instead
# of the repository's own .cursor/agents/*.md pins (Grok / Composer there). The
# fix states the rule once in agent-model-config.md, repeats it in the Cursor
# dispatch-profile contract, and points every item-level handoff surface at it.
# This suite fails when any of those statements is dropped.
#
# covers: docs/workflow/development-workflow/agent-model-config.md
# covers: docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md
# covers: .cursor/commands/run-item.md .cursor/agents/item-orchestrator.md
# covers: .claude/commands/run-item.md .claude/agents/item-orchestrator.md
# covers: .agents/skills/run-item/SKILL.md .codex/skills/workflow-item-orchestrator/SKILL.md

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# The checkout this suite belongs to (a worktree stays a worktree), so the
# assertions read the files this change set actually edits.
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd -P)"

MODEL_CONFIG_REL="docs/workflow/development-workflow/agent-model-config.md"
PROFILES_REL="docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md"

MODEL_CONFIG_HEADING="### Cursor model source of truth"
# The backticks below are literal Markdown, not command substitution.
# shellcheck disable=SC2016
MODEL_CONFIG_RULE='the `model:` field in each checked-in `.cursor/agents/<agent>.md`'
PROFILES_HEADING="## Stage-agent model selection"
# shellcheck disable=SC2016
PROFILES_RULE='`model:` field from
`.cursor/agents/<agent>.md`'
SURFACE_RULE="Stage-agent models in Cursor: before dispatching a stage subagent, read that"
SURFACE_POINTER='"Cursor model source of
truth" section.'

# Literal list so a surface dropped from the set is a visible diff here.
SURFACES=(
  ".cursor/commands/run-item.md"
  ".cursor/agents/item-orchestrator.md"
  ".claude/commands/run-item.md"
  ".claude/agents/item-orchestrator.md"
  ".agents/skills/run-item/SKILL.md"
  ".codex/skills/workflow-item-orchestrator/SKILL.md"
)

PASS=0
FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "PASS: $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $name expected=$expected actual=$actual"
    FAIL=$((FAIL + 1))
  fi
}

# contains <file> <text>: fixed-string match that may span lines.
contains() {
  python3 - "$1" "$2" <<'PY'
import sys
with open(sys.argv[1], encoding="utf-8") as fh:
    sys.exit(0 if sys.argv[2] in fh.read() else 1)
PY
}

# validate_root <root>: prints one "FAIL: ..." line per missing statement and
# returns 0 only when every statement is present.
validate_root() {
  local root="$1" problems=0 surface
  local -a needed
  for pair in \
    "$MODEL_CONFIG_REL|$MODEL_CONFIG_HEADING" \
    "$MODEL_CONFIG_REL|$MODEL_CONFIG_RULE" \
    "$PROFILES_REL|$PROFILES_HEADING" \
    "$PROFILES_REL|$PROFILES_RULE"; do
    local rel="${pair%%|*}" text="${pair#*|}"
    if [ ! -f "$root/$rel" ] || ! contains "$root/$rel" "$text"; then
      echo "FAIL: $rel lost: $text"
      problems=1
    fi
  done
  for surface in "${SURFACES[@]}"; do
    needed=("$SURFACE_RULE" "$SURFACE_POINTER")
    local text
    for text in "${needed[@]}"; do
      if [ ! -f "$root/$surface" ] || ! contains "$root/$surface" "$text"; then
        echo "FAIL: $surface lost: $text"
        problems=1
      fi
    done
  done
  [ "$problems" -eq 0 ]
}

# --- Real repository ---
real_output="$(validate_root "$REPO_ROOT" 2>&1)" && real_rc=0 || real_rc=$?
if [ "$real_rc" -eq 0 ]; then
  check real_repo_model_pin_guidance_present pass pass
else
  check real_repo_model_pin_guidance_present pass "fail: $real_output"
fi

# --- Planted-violation proofs, in a sandbox copy ---
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cursor-model-pin.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT
sandbox="$TMP_DIR/sandbox"
for rel in "$MODEL_CONFIG_REL" "$PROFILES_REL" "${SURFACES[@]}"; do
  mkdir -p "$sandbox/$(dirname "$rel")"
  cp "$REPO_ROOT/$rel" "$sandbox/$rel"
done

if validate_root "$sandbox" >/dev/null 2>&1; then
  check sandbox_baseline_clean pass pass
else
  check sandbox_baseline_clean pass fail
fi

# plant <rel> <text>: strip every occurrence of <text> from the sandbox copy.
plant() {
  python3 - "$sandbox/$1" "$2" <<'PY'
import sys
path, text = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as fh:
    body = fh.read()
with open(path, "w", encoding="utf-8") as fh:
    fh.write(body.replace(text, ""))
PY
}

restore() {
  cp "$REPO_ROOT/$1" "$sandbox/$1"
}

# P1 — an item surface drops the read-the-local-pin instruction.
plant "${SURFACES[0]}" "$SURFACE_RULE"
if validate_root "$sandbox" >/dev/null 2>&1; then
  check p1_surface_rule_dropped_detected fail pass
else
  check p1_surface_rule_dropped_detected fail fail
fi
restore "${SURFACES[0]}"

# P2 — agent-model-config.md drops the source-of-truth section.
plant "$MODEL_CONFIG_REL" "$MODEL_CONFIG_HEADING"
if validate_root "$sandbox" >/dev/null 2>&1; then
  check p2_model_config_heading_dropped_detected fail pass
else
  check p2_model_config_heading_dropped_detected fail fail
fi
restore "$MODEL_CONFIG_REL"

# P3 — the dispatch-profile contract drops the model-selection rule.
plant "$PROFILES_REL" "$PROFILES_RULE"
if validate_root "$sandbox" >/dev/null 2>&1; then
  check p3_profiles_rule_dropped_detected fail pass
else
  check p3_profiles_rule_dropped_detected fail fail
fi
restore "$PROFILES_REL"

# Repair clears every plant.
if validate_root "$sandbox" >/dev/null 2>&1; then
  check repairs_clear_findings pass pass
else
  check repairs_clear_findings pass fail
fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

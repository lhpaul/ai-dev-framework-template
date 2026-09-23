#!/usr/bin/env bash
# test-cursor-dispatch-profile-pointers.sh — every Cursor dispatch-profile
# mirror surface still points at the canonical document, and the canonical
# document itself still exists.
#
# Why this exists (PR #1783): the Test-Scope Deviation Record in the #1462
# implementation plan drops the surface-drift guard because the 21 mirror
# surfaces no longer carry the declaration contract, only a pointer to
# integrations/cursor-dispatch-profiles.md. The record claims a broken
# pointer is "already covered by the repository's existing link and markdown
# lints". It is not: markdownlint-cli2's active config
# (.markdownlint-cli2.jsonc) disables the relative-links rule for every path
# this repository lints, and the CI markdown-lint job's globs do not even
# reach .claude/, .cursor/, .agents/, or .codex/ — where every mirror in the
# list below lives. This suite is the cheap, narrowly-scoped check that
# closes that real gap without reviving the deleted parser/fixture guard.
#
# covers: docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md
# covers: .agents/skills/run-epic/SKILL.md .agents/skills/run-item-work/SKILL.md .agents/skills/run-item/SKILL.md
# covers: .agents/skills/run-items/SKILL.md .agents/skills/run-work/SKILL.md
# covers: .claude/agents/item-orchestrator.md .claude/agents/orchestrator.md
# covers: .claude/commands/run-epic.md .claude/commands/run-item-work.md .claude/commands/run-item.md
# covers: .claude/commands/run-items.md .claude/commands/run-work.md
# covers: .codex/skills/workflow-item-orchestrator/SKILL.md .codex/skills/workflow-orchestrator/SKILL.md
# covers: .cursor/agents/item-orchestrator.md .cursor/agents/orchestrator.md
# covers: .cursor/commands/run-epic.md .cursor/commands/run-item-work.md .cursor/commands/run-item.md
# covers: .cursor/commands/run-items.md .cursor/commands/run-work.md .cursor/rules/workflow.mdc

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
GIT_COMMON_DIR="$(cd "$SCRIPT_DIR" && git rev-parse --git-common-dir)"
case "$GIT_COMMON_DIR" in
  /*) REPO_ROOT="$(cd "$GIT_COMMON_DIR/.." && pwd -P)" ;;
  *) REPO_ROOT="$(cd "$SCRIPT_DIR/$GIT_COMMON_DIR/.." && pwd -P)" ;;
esac

CANONICAL_REL="docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md"

# Kept as a literal list, not a glob, so a mirror silently dropped from this
# list (or from the real surface set) is a visible diff in this file, not a
# pattern that quietly stops matching.
MIRRORS=(
  ".agents/skills/run-epic/SKILL.md"
  ".agents/skills/run-item-work/SKILL.md"
  ".agents/skills/run-item/SKILL.md"
  ".agents/skills/run-items/SKILL.md"
  ".agents/skills/run-work/SKILL.md"
  ".claude/agents/item-orchestrator.md"
  ".claude/agents/orchestrator.md"
  ".claude/commands/run-epic.md"
  ".claude/commands/run-item-work.md"
  ".claude/commands/run-item.md"
  ".claude/commands/run-items.md"
  ".claude/commands/run-work.md"
  ".codex/skills/workflow-item-orchestrator/SKILL.md"
  ".codex/skills/workflow-orchestrator/SKILL.md"
  ".cursor/agents/item-orchestrator.md"
  ".cursor/agents/orchestrator.md"
  ".cursor/commands/run-epic.md"
  ".cursor/commands/run-item-work.md"
  ".cursor/commands/run-item.md"
  ".cursor/commands/run-items.md"
  ".cursor/commands/run-work.md"
  ".cursor/rules/workflow.mdc"
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

# validate_root <root>: prints one "FAIL: ..." line per problem found under
# <root> (a missing canonical document, a missing mirror, or a mirror that no
# longer references the canonical document's path) and exits 0 only when it
# found none. Used against both the real repository and, below, a synthetic
# sandbox that plants each violation this check exists to catch.
validate_root() {
  local root="$1" problems=0
  if [ ! -f "$root/$CANONICAL_REL" ]; then
    echo "FAIL: canonical document missing: $CANONICAL_REL"
    problems=1
  fi
  local mirror
  for mirror in "${MIRRORS[@]}"; do
    if [ ! -f "$root/$mirror" ]; then
      echo "FAIL: mirror missing: $mirror"
      problems=1
      continue
    fi
    if ! grep -qF "$CANONICAL_REL" "$root/$mirror"; then
      echo "FAIL: mirror lost its pointer to $CANONICAL_REL: $mirror"
      problems=1
    fi
  done
  [ "$problems" -eq 0 ]
}

# --- Real repository: every mirror wired, canonical document present ---
real_repo_output="$(validate_root "$REPO_ROOT" 2>&1)" && real_repo_rc=0 || real_repo_rc=$?
if [ "$real_repo_rc" -eq 0 ]; then
  check real_repo_all_pointers_wired pass pass
else
  check real_repo_all_pointers_wired pass "fail: $real_repo_output"
fi

# --- Planted-violation proofs (REVIEW.md) ---
#
# A synthetic sandbox, not the real repository, so the plant/repair cycle
# below cannot leave the working tree dirty and cannot depend on which
# mirror happens to be first in MIRRORS.

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

sandbox="$TMP_DIR/sandbox"
mkdir -p "$sandbox/$(dirname "$CANONICAL_REL")"
printf '# Cursor dispatch profiles\n\nCanonical contract.\n' > "$sandbox/$CANONICAL_REL"

sample_mirror="${MIRRORS[0]}"
mkdir -p "$sandbox/$(dirname "$sample_mirror")"
printf 'Declare the dispatch profile per `%s`.\n' "$CANONICAL_REL" > "$sandbox/$sample_mirror"

# Every other mirror just needs to exist with a working pointer so the
# sandbox is clean before each plant below.
for mirror in "${MIRRORS[@]}"; do
  [ "$mirror" = "$sample_mirror" ] && continue
  mkdir -p "$sandbox/$(dirname "$mirror")"
  printf 'Declare the dispatch profile per `%s`.\n' "$CANONICAL_REL" > "$sandbox/$mirror"
done

# Baseline: the clean sandbox passes.
if validate_root "$sandbox" >/dev/null 2>&1; then
  check sandbox_baseline_clean pass pass
else
  check sandbox_baseline_clean pass fail
fi

# P1 — a mirror loses its pointer (the exact defect class this check exists
# to catch: a mirror silently drifting away from the single normative
# source once it no longer restates the contract itself).
printf 'Declare the dispatch profile before any mutating action.\n' > "$sandbox/$sample_mirror"
if validate_root "$sandbox" >/dev/null 2>&1; then
  check p1_plant_lost_pointer_detected fail pass
else
  check p1_plant_lost_pointer_detected fail fail
fi
# ...and repairing it clears the finding.
printf 'Declare the dispatch profile per `%s`.\n' "$CANONICAL_REL" > "$sandbox/$sample_mirror"
if validate_root "$sandbox" >/dev/null 2>&1; then
  check p1_repair_clears_finding pass pass
else
  check p1_repair_clears_finding pass fail
fi

# P2 — the canonical document itself goes missing (a move or delete with no
# mirror updated to follow it).
rm "$sandbox/$CANONICAL_REL"
if validate_root "$sandbox" >/dev/null 2>&1; then
  check p2_plant_missing_canonical_detected fail pass
else
  check p2_plant_missing_canonical_detected fail fail
fi
mkdir -p "$sandbox/$(dirname "$CANONICAL_REL")"
printf '# Cursor dispatch profiles\n\nCanonical contract.\n' > "$sandbox/$CANONICAL_REL"
if validate_root "$sandbox" >/dev/null 2>&1; then
  check p2_repair_clears_finding pass pass
else
  check p2_repair_clears_finding pass fail
fi

echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]

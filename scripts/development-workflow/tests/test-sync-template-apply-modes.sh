#!/usr/bin/env bash
# test-sync-template-apply-modes.sh — assert sync-template primary modes wording.
#
# Usage: bash scripts/development-workflow/tests/test-sync-template-apply-modes.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  echo "PASS: $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
  echo "FAIL: $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  local name="$3"
  if grep -Eq -- "$pattern" "$file"; then
    pass "$name"
  else
    fail "$name (missing /$pattern/ in $file)"
  fi
}

assert_primary_modes() {
  local file="$1"
  local name="$2"
  local block
  block="$(awk '/Ready to apply\? Choose how to handle discretionary items:/,/Advanced \/ escape hatch:/' "$file" || true)"
  if [ -z "$block" ]; then
    fail "$name (missing Ready-to-apply confirmation block)"
    return
  fi
  if printf '%s\n' "$block" | grep -q 'Decide with me' \
    && printf '%s\n' "$block" | grep -q 'Accept recommendations'; then
    pass "$name primary modes Decide with me / Accept recommendations"
  else
    fail "$name missing Decide with me / Accept recommendations in confirmation block"
  fi
  # Old coverage options must not appear as quoted primary bullets in this block.
  if printf '%s\n' "$block" | grep -qE '^\s*>\s*-\s*\*\*"apply all"\*\*' \
    || printf '%s\n' "$block" | grep -qE '^\s*>\s*-\s*\*\*"apply always-sync only"\*\*'; then
    fail "$name still lists old options as primary peer bullets"
  else
    pass "$name does not list old options as primary peer bullets"
  fi
}

BODIES=(
  "$REPO_ROOT/.claude/commands/sync-template.md"
  "$REPO_ROOT/.cursor/commands/sync-template.md"
  "$REPO_ROOT/.claude/skills/sync-template.md"
)

WRAPPERS=(
  "$REPO_ROOT/.codex/skills/workflow-sync-template/SKILL.md"
  "$REPO_ROOT/.agents/skills/workflow-sync-template/SKILL.md"
)

for f in "${BODIES[@]}"; do
  base="${f#"$REPO_ROOT/"}"
  assert_file_contains "$f" 'Decide with me' "$base has Decide with me"
  assert_file_contains "$f" 'Accept recommendations' "$base has Accept recommendations"
  assert_file_contains "$f" 'Escalation / hard-stop' "$base has hard-stop taxonomy"
  assert_file_contains "$f" 'analysis_skipped_file_limit' "$base documents Haystack file-limit skip"
  assert_file_contains "$f" 'other configured reviewers, CI,' "$base preserves other review and CI gates"
  assert_file_contains "$f" 'unresolved-thread, regression, and readiness gates remain mandatory' "$base preserves terminal gates"
  assert_primary_modes "$f" "$base"
  if awk '/Requires manual review \(you decide\)/,/^### /' "$f" | grep -q '\.claude/settings\.json'; then
    fail "$base lists .claude/settings.json under Requires manual review (you decide)"
  else
    pass "$base does not list settings.json under discretionary you-decide heading"
  fi
  if grep -q '\.claude/settings\.json' "$f" && grep -q 'Escalation / hard-stop' "$f"; then
    pass "$base mentions settings.json with escalation taxonomy present"
  else
    fail "$base missing settings.json or escalation taxonomy"
  fi
done

for f in "${WRAPPERS[@]}"; do
  base="${f#"$REPO_ROOT/"}"
  assert_file_contains "$f" 'Decide with me' "$base has Decide with me"
  assert_file_contains "$f" 'Accept recommendations' "$base has Accept recommendations"
  assert_file_contains "$f" 'analysis_skipped_file_limit' "$base documents Haystack file-limit skip"
  assert_file_contains "$f" 'unresolved-thread, regression, and readiness gates remain mandatory' "$base preserves terminal gates"
  if grep -qE 'confirmation prompt offers two options — "apply all"' "$f"; then
    fail "$base still documents old primary peer pair"
  else
    pass "$base no longer documents old primary peer pair"
  fi
done

echo
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi

#!/usr/bin/env bash
# test-may-merge-terminal-contract.sh - Verify merge terminal wording stays aligned.
# covers: .claude/agents/*.md .claude/commands/*.md .cursor/agents/*.md
# covers: .cursor/commands/*.md .codex/skills/** .agents/skills/**
# covers: docs/workflow/development-workflow/README.md
# covers: docs/workflow/development-workflow/guardrails-enforcement.md
# covers: docs/workflow/development-workflow/protocols/*.md

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

FAILURES=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

pass() {
  printf 'PASS: %s\n' "$1"
}

require_file() {
  local file="$1"
  if [ -f "$file" ]; then
    pass "file exists: $file"
  else
    fail "missing file: $file"
  fi
}

require_pattern() {
  local file="$1"
  local pattern="$2"
  local label="$3"
  if grep -Eq -- "$pattern" "$file"; then
    pass "$label"
  else
    fail "$label ($file missing pattern: $pattern)"
  fi
}

canonical_files=(
  "docs/workflow/development-workflow/guardrails-enforcement.md"
  "docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md"
  "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"
  "docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md"
  "docs/workflow/development-workflow/protocols/95-run-epic-protocol.md"
  "docs/workflow/development-workflow/README.md"
)

item_surfaces=(
  ".claude/commands/run-item.md"
  ".cursor/commands/run-item.md"
  ".agents/skills/run-item/SKILL.md"
  ".agents/skills/run-item/agents/openai.yaml"
  ".codex/skills/workflow-item-orchestrator/SKILL.md"
  ".codex/skills/workflow-item-orchestrator/agents/openai.yaml"
  ".claude/agents/item-orchestrator.md"
  ".cursor/agents/item-orchestrator.md"
)

batch_surfaces=(
  ".claude/commands/run-items.md"
  ".cursor/commands/run-items.md"
  ".agents/skills/run-items/SKILL.md"
  ".agents/skills/run-items/agents/openai.yaml"
  ".codex/skills/workflow-orchestrator/SKILL.md"
  ".codex/skills/workflow-orchestrator/agents/openai.yaml"
  ".claude/agents/orchestrator.md"
  ".cursor/agents/orchestrator.md"
)

epic_surfaces=(
  ".claude/commands/run-epic.md"
  ".cursor/commands/run-epic.md"
  ".agents/skills/run-epic/SKILL.md"
  ".agents/skills/run-epic/agents/openai.yaml"
)

all_files=(
  "${canonical_files[@]}"
  "${item_surfaces[@]}"
  "${batch_surfaces[@]}"
  "${epic_surfaces[@]}"
)

for file in "${all_files[@]}"; do
  require_file "$file"
done

require_pattern \
  "docs/workflow/development-workflow/guardrails-enforcement.md" \
  "merge_granted.*readiness|readiness.*merge_granted" \
  "guardrails defines merge_granted readiness behavior"
require_pattern \
  "docs/workflow/development-workflow/guardrails-enforcement.md" \
  "merge_denied" \
  "guardrails names merge_denied"
require_pattern \
  "docs/workflow/development-workflow/guardrails-enforcement.md" \
  "ready_human_merge" \
  "guardrails defines merge_denied human handoff"
require_pattern \
  "docs/workflow/development-workflow/guardrails-enforcement.md" \
  "merge_blocked" \
  "guardrails names merge_blocked"
require_pattern \
  "docs/workflow/development-workflow/guardrails-enforcement.md" \
  "policy_inconsistent" \
  "guardrails names policy_inconsistent"
require_pattern \
  "docs/workflow/development-workflow/guardrails-enforcement.md" \
  "out_of_scope" \
  "guardrails names out_of_scope"

for file in "${item_surfaces[@]}"; do
  require_pattern "$file" "merge_granted" "$file mentions merge_granted"
  require_pattern "$file" "merge_denied" "$file mentions merge_denied"
  require_pattern "$file" "ready_human_merge" "$file mentions ready_human_merge"
  require_pattern "$file" "policy_inconsistent" "$file mentions policy_inconsistent"
done

for file in "${batch_surfaces[@]}"; do
  require_pattern "$file" "merge_granted" "$file mentions merge_granted"
  require_pattern "$file" "merge_denied" "$file mentions merge_denied"
  require_pattern "$file" "ready_human_merge" "$file mentions ready_human_merge"
  require_pattern "$file" "merge_blocked" "$file mentions merge_blocked"
  require_pattern "$file" "policy_inconsistent" "$file mentions policy_inconsistent"
  require_pattern "$file" "out_of_scope" "$file mentions out_of_scope"
done

for file in "${epic_surfaces[@]}"; do
  require_pattern "$file" "merge_granted" "$file mentions merge_granted"
  require_pattern "$file" "merge_denied" "$file mentions merge_denied"
  require_pattern "$file" "ready_human_merge" "$file mentions ready_human_merge"
  require_pattern "$file" "policy_inconsistent" "$file mentions policy_inconsistent"
  require_pattern "$file" "out_of_scope" "$file mentions out_of_scope"
done

require_pattern \
  "docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md" \
  "ready_human_merge" \
  "Protocol 90 names ready_human_merge"
require_pattern \
  "docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md" \
  "merge_blocked" \
  "Protocol 90 names merge_blocked"
require_pattern \
  "docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md" \
  "policy_inconsistent" \
  "Protocol 90 names policy_inconsistent"
require_pattern \
  "docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md" \
  "out_of_scope" \
  "Protocol 90 names out_of_scope"

require_pattern \
  "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" \
  "merge_granted" \
  "Protocol 91 names merge_granted"
require_pattern \
  "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" \
  "merge_denied" \
  "Protocol 91 names merge_denied"
require_pattern \
  "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" \
  "ready_human_merge" \
  "Protocol 91 names ready_human_merge"
require_pattern \
  "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" \
  "merge_blocked" \
  "Protocol 91 names merge_blocked"
require_pattern \
  "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" \
  "policy_inconsistent" \
  "Protocol 91 names policy_inconsistent"

require_pattern \
  "docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md" \
  "merge_granted" \
  "Protocol 92 names merge_granted"
require_pattern \
  "docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md" \
  "merge_denied" \
  "Protocol 92 names merge_denied"
require_pattern \
  "docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md" \
  "ready_human_merge" \
  "Protocol 92 names ready_human_merge"

require_pattern \
  "docs/workflow/development-workflow/protocols/95-run-epic-protocol.md" \
  "merge_granted" \
  "Protocol 95 names merge_granted"
require_pattern \
  "docs/workflow/development-workflow/protocols/95-run-epic-protocol.md" \
  "merge_denied" \
  "Protocol 95 names merge_denied"
require_pattern \
  "docs/workflow/development-workflow/protocols/95-run-epic-protocol.md" \
  "ready_human_merge" \
  "Protocol 95 names ready_human_merge"
require_pattern \
  "docs/workflow/development-workflow/protocols/95-run-epic-protocol.md" \
  "merge_blocked" \
  "Protocol 95 names merge_blocked"
require_pattern \
  "docs/workflow/development-workflow/protocols/95-run-epic-protocol.md" \
  "policy_inconsistent" \
  "Protocol 95 names policy_inconsistent"
require_pattern \
  "docs/workflow/development-workflow/protocols/95-run-epic-protocol.md" \
  "out_of_scope" \
  "Protocol 95 names out_of_scope"

if [ "$FAILURES" -ne 0 ]; then
  printf 'FAIL: %s merge terminal contract checks failed.\n' "$FAILURES" >&2
  exit 1
fi

echo "PASS: merge terminal contract surfaces are aligned."

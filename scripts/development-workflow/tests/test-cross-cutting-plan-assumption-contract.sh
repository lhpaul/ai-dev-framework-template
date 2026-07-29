#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_contains() {
  local label="$1"
  local file="$2"
  local needle="$3"

  if grep -Fq "$needle" "$REPO_ROOT/$file"; then
    pass "$label"
  else
    fail "$label missing '$needle' in $file"
  fi
}

require_not_contains() {
  local label="$1"
  local file="$2"
  local needle="$3"

  if grep -Fq "$needle" "$REPO_ROOT/$file"; then
    fail "$label unexpectedly found '$needle' in $file"
  else
    pass "$label"
  fi
}

canonical_protocol="docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md"
template_file="docs/workflow/development-workflow/templates/implementation-plan-template.md"
implementation_protocol="docs/workflow/development-workflow/protocols/03-implement-development-protocol.md"
portfolio_protocol="docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md"
item_protocol="docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"

require_contains "protocol 02 defines assumption section" "$canonical_protocol" "Cross-cutting operational assumption check"
require_contains "protocol 02 requires bounded scope" "$canonical_protocol" "bounded current invocation / same-surface open PR scope"
require_contains "protocol 02 forbids unbounded scan" "$canonical_protocol" "unbounded scan of every open"
require_contains "protocol 02 rejects keyword-only conflicts" "$canonical_protocol" "Shared keywords alone"

for outcome in "Verified" "Conflict" "Resolved" "Human decision required" "Not applicable" "Still valid" "Stale or conflicting"; do
  require_contains "protocol 02 outcome $outcome" "$canonical_protocol" "$outcome"
done

require_contains "template includes assumption check" "$template_file" "Cross-Cutting Operational Assumption Check"
require_contains "template includes applicable table" "$template_file" "Assumption surface"
require_contains "template includes not applicable path" "$template_file" "Not applicable"

require_contains "implementation protocol re-verifies" "$implementation_protocol" "Implementation-Start Operational Assumption Re-Verification"
require_contains "implementation protocol records still valid" "$implementation_protocol" "Still valid"
require_contains "implementation protocol stops stale conflict" "$implementation_protocol" "Stale or conflicting"

require_contains "portfolio protocol passes current batch context" "$portfolio_protocol" "current-batch item list"
require_contains "portfolio protocol owns conflict resolution" "$portfolio_protocol" 'Record `Resolved`'
require_contains "item protocol passes planner context" "$item_protocol" "current-batch item list"
require_contains "item protocol handles stale conflict" "$item_protocol" "Stale or conflicting"

for file in \
  ".claude/agents/tech-lead.md" \
  ".cursor/agents/tech-lead.md" \
  ".codex/skills/workflow-plan-writer/SKILL.md"; do
  require_contains "planner mirror $file" "$file" "Cross-Cutting Operational Assumption Check"
done

for file in \
  ".claude/agents/developer.md" \
  ".cursor/agents/developer.md" \
  ".codex/skills/workflow-implementer/SKILL.md"; do
  require_contains "developer mirror $file" "$file" "Stale or conflicting"
done

for file in \
  ".claude/agents/orchestrator.md" \
  ".cursor/agents/orchestrator.md" \
  ".codex/skills/workflow-orchestrator/SKILL.md" \
  ".claude/agents/item-orchestrator.md" \
  ".cursor/agents/item-orchestrator.md" \
  ".codex/skills/workflow-item-orchestrator/SKILL.md" \
  ".claude/commands/run-items.md" \
  ".cursor/commands/run-items.md" \
  ".agents/skills/run-items/SKILL.md" \
  ".agents/skills/run-items/agents/openai.yaml"; do
  require_contains "orchestration mirror $file" "$file" "current-batch"
done

require_contains "review plan checklist updated" "REVIEW.md" "Cross-cutting operational assumption check"
require_contains "review code checklist updated" "REVIEW.md" "implementation-start re-verification"
require_contains "readme summary updated" "docs/workflow/development-workflow/README.md" "Cross-Cutting Operational Assumption Check"

require_not_contains "template avoids mandatory repository-wide PR scan" "$template_file" "scan every open PR"

printf 'All cross-cutting operational assumption contract checks passed.\n'

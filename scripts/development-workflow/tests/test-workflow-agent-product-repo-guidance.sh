#!/usr/bin/env bash
# test-workflow-agent-product-repo-guidance.sh - prompt guidance coverage for workflow_hub ownership.
#
# Usage: bash scripts/development-workflow/tests/test-workflow-agent-product-repo-guidance.sh

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

run_contains() {
  local name="$1"
  local file="$2"
  local expected="$3"

  if grep -Fq -- "$expected" "$REPO_ROOT/$file"; then
    echo "PASS: $name"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: $name - expected '$file' to contain '$expected'"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

echo ""
echo "=== Workflow agent product repository guidance ==="

run_contains "repository_modes_single_repo_compatible" \
  "docs/workflow/development-workflow/repository-modes.md" \
  "Missing mode or explicit \`single_repo\` keeps current behavior"
run_contains "repository_modes_mutation_stop" \
  "docs/workflow/development-workflow/repository-modes.md" \
  "the agent must stop before modifying files"

run_contains "protocol_90_selected_product_handoff" \
  "docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md" \
  "selected product repository name, local path or remote identity"
run_contains "protocol_91_mutation_stop" \
  "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" \
  "implementation PR creation"
run_contains "protocol_01_spec_hub_owned" \
  "docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md" \
  "the hub owns specs and"
run_contains "protocol_02_plan_hub_owned" \
  "docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md" \
  "the hub owns"
run_contains "protocol_03_pre_mutation_context" \
  "docs/workflow/development-workflow/protocols/03-implement-development-protocol.md" \
  "repository is missing or ambiguous"
run_contains "protocol_04_smoke_owner" \
  "docs/workflow/development-workflow/protocols/04-smoke-test-protocol.md" \
  "product-repository-owned"
run_contains "protocol_93_thin_wrapper" \
  "docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md" \
  "do not duplicate product repository selection logic"

for runner in .claude .cursor; do
  run_contains "${runner}_orchestrator_handoff_context" \
    "$runner/agents/orchestrator.md" \
    "selected product repository, local path or remote identity"
  run_contains "${runner}_item_orchestrator_mutation_stop" \
    "$runner/agents/item-orchestrator.md" \
    "Stop before file edits, branch creation, commits, or implementation PR creation"
  run_contains "${runner}_product_manager_spec_owner" \
    "$runner/agents/product-manager.md" \
    "specs and spec PRs are hub-owned"
  run_contains "${runner}_tech_lead_plan_owner" \
    "$runner/agents/tech-lead.md" \
    "plans and plan PRs are hub-owned"
  run_contains "${runner}_developer_pre_mutation_context" \
    "$runner/agents/developer.md" \
    "Before file edits, branch creation, commits, or"
  run_contains "${runner}_spec_reviewer_owner" \
    "$runner/agents/spec-reviewer.md" \
    "Resolve and report the artifact repository owner"
  run_contains "${runner}_plan_reviewer_owner" \
    "$runner/agents/implementation-plan-reviewer.md" \
    "Resolve and report the artifact repository owner"
  run_contains "${runner}_code_reviewer_product_owner" \
    "$runner/agents/code-reviewer.md" \
    "product implementation PRs are reviewed in the selected product"
  run_contains "${runner}_reviewer_loop_thin" \
    "$runner/agents/automated-reviewer-loop.md" \
    "Do not duplicate product repository selection logic"
  run_contains "${runner}_smoke_tester_owner" \
    "$runner/agents/smoke-tester.md" \
    "hub-owned or product-repository-owned"
done

run_contains "claude_run_work_alias_context" \
  ".claude/commands/run-work.md" \
  "selected product repository context in implementation handoffs"
run_contains "claude_code_review_command_owner" \
  ".claude/commands/code-review.md" \
  "Resolve and report the implementation artifact owner"
run_contains "claude_post_merge_cleanup_context" \
  ".claude/commands/post-merge-cleanup.md" \
  "preserve selected product repository context"
run_contains "cursor_implement_command_context" \
  ".cursor/commands/implement-development.md" \
  "state selected product repository, local path or remote identity"
run_contains "cursor_post_merge_cleanup_context" \
  ".cursor/commands/post-merge-cleanup.md" \
  "preserve selected product repository context"

run_contains "codex_orchestrator_context" \
  ".codex/skills/workflow-orchestrator/SKILL.md" \
  "selected product repository, local path or remote identity"
run_contains "codex_item_context" \
  ".codex/skills/workflow-item-orchestrator/SKILL.md" \
  "Stop before file edits, branch creation, commits, or implementation PR creation"
run_contains "codex_implementer_context" \
  ".codex/skills/workflow-implementer/SKILL.md" \
  "product implementation work mutates the selected product repository"
run_contains "codex_reviewer_loop_context" \
  ".codex/skills/workflow-reviewer-loop/SKILL.md" \
  "pass selected product repository context through to shared reviewer and CI scripts"
run_contains "agents_run_work_context" \
  ".agents/skills/run-work/SKILL.md" \
  "preserve selected product repository"
run_contains "agents_prepare_release_component_target" \
  ".agents/skills/prepare-release/SKILL.md" \
  "component-release-target.sh"
run_contains "agents_prepare_release_evidence_file" \
  ".agents/skills/prepare-release/SKILL.md" \
  "--evidence-file"
run_contains "agents_openai_default_prompt_context" \
  ".agents/skills/run-work/agents/openai.yaml" \
  "selected product repository context"

echo ""
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"

if [ "$FAIL_COUNT" -ne 0 ]; then
  exit 1
fi

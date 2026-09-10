#!/usr/bin/env bash
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
# covers: .ai-dev-workflow.yaml
# covers: Step 7a availability and reviewer-surface alignment (#1495)
set -euo pipefail

ROOT="$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"
PASS=0; FAIL=0
check() { local id="$1" pattern="$2" file="$3"; if grep -Fq -- "$pattern" "$ROOT/$file"; then echo "PASS: $id"; PASS=$((PASS+1)); else echo "FAIL: $id ($file)"; FAIL=$((FAIL+1)); fi; }
absent() { local id="$1" pattern="$2" file="$3"; if ! grep -Fiq -- "$pattern" "$ROOT/$file"; then echo "PASS: $id"; PASS=$((PASS+1)); else echo "FAIL: $id ($file)"; FAIL=$((FAIL+1)); fi; }

P=docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
check D-1 'codex-github' "$P"
absent D-2 'runner identity is a sufficient proxy' "$P"
absent D-3 'universally reachable' scripts/development-workflow/codex-github-reviewer.sh
check D-4 'codex-github' .ai-dev-workflow.yaml
check D-5 'runtime-absent' "$P"
check D-6 'review failure' "$P"
check D-7 "driving runner's own stage reviewer" docs/workflow/development-workflow/README.md
check D-8 'install software, or' "$P"
absent D-9 'expected behaviour' .ai-dev-workflow.yaml
check D-10 'reviews.auto_review.enabled: true' docs/workflow/development-workflow/integrations/coderabbit.md
cmp -s <(sed -n '/codex-github runner reviewer dispatch/,/\/codex-github runner reviewer dispatch/p' "$ROOT/.claude/agents/item-orchestrator.md") <(sed -n '/codex-github runner reviewer dispatch/,/\/codex-github runner reviewer dispatch/p' "$ROOT/.cursor/agents/item-orchestrator.md") && { echo 'PASS: D-11'; PASS=$((PASS+1)); } || { echo 'FAIL: D-11'; FAIL=$((FAIL+1)); }
check D-12 'exactly one `VERDICT: APPROVED`' "$P"
check D-13 'Run it on every cycle' "$P"
check D-14 'is read-only: do not review' "$P"
check D-15 'resolve-reviewer-availability.sh' "$P"
check D-16 'per-reviewer verdict' "$P"
absent D-17 '(<runner-context>)' "$P"
check D-18 'Local override:' "$P"
check D-19 'gh pr ready <pr_number> --undo' "$P"
check D-20 'after availability, before dispatch' "$P"
check D-21 'accepted proxy, not proof' "$P"
check D-22 'must never be split or `eval`ed' "$P"
check D-23 'bounded repository-activity proxy' .claude/agents/item-orchestrator.md
check D-24 'installed and reachable' "$P"

echo "Passed: $PASS"; echo "Failed: $FAIL"
[ "$FAIL" -eq 0 ]

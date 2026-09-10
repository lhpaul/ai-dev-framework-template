#!/usr/bin/env bash
# covers: docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
# covers: .ai-dev-workflow.yaml .ai-dev-workflow.local.example.yaml .claude/agents/item-orchestrator.md .cursor/agents/item-orchestrator.md
# covers: docs/workflow/development-workflow/integrations/coderabbit.md docs/workflow/development-workflow/integrations/codex-github.md docs/workflow/development-workflow/README.md
set -euo pipefail
ROOT=${SURFACE_ROOT:-"$(CDPATH='' cd -- "$(dirname -- "$0")/../../.." && pwd)"}; P="$ROOT/docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"; PASS=0; FAIL=0
ok(){ echo "PASS: $1"; PASS=$((PASS+1)); }; no(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }
all(){ local id="$1"; shift; local x; for x in "$@"; do grep -Fq -- "$x" "$P" || { no "$id"; return; }; done; ok "$id"; }
none(){ ! grep -Fiq -- "$2" "$ROOT/$3" && ok "$1" || no "$1"; }
block(){ sed -n '/step7a-codex-github-availability:start/,/step7a-codex-github-availability:end/p' "$1"; }
all D-1 'Supported reviewer values are `claude`, `cursor`, `codex` (local-runtime), and' '`coderabbit`, `codex-github` (hosted-service)'
none D-2 'runner identity is a sufficient proxy' docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md; none D-2b 'Reachability classification table' docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
if ! git -C "$ROOT" grep -in 'universally reachable' -- ':!CHANGELOG.md' ':!docs/specs/developments/**' ':!docs/testing/**' ':!scripts/**/tests/**' >/dev/null; then ok D-3; else no D-3; fi
if ! awk '/runner:/{on=1;next} on&&/- /{if($2!~ /^(claude|cursor|codex|coderabbit|codex-github)$/)exit 1} on{exit}' "$ROOT/.ai-dev-workflow.yaml" "$ROOT/.ai-dev-workflow.local.example.yaml"; then no D-4; else ok D-4; fi
all D-5 '`runtime-absent` | Make the required runtime available.' '`prerequisite-missing` | Satisfy the named repository prerequisite.' '`check-inconclusive` | Retry after the bounded check can complete.' '`value-not-supported` | Correct the configured reviewer value.'
all D-6 'review failure under either policy' 'claude -p --output-format text' 'cursor-agent --print --output-format text' 'codex exec --sandbox read-only' 'exactly one `VERDICT: APPROVED`'
if grep -Fq "driving runner's own stage reviewer" "$P" && grep -Fq "driving runner's own stage reviewer" "$ROOT/docs/workflow/development-workflow/README.md"; then ok D-7; else no D-7; fi
all D-8 'install software, or' 'substitute a reviewer'
if [ "$(awk '/runner:/{on=1;next} on&&/- /{print $2;next} on{exit}' "$ROOT/.ai-dev-workflow.yaml"|tr '\n' ' ')" = 'claude cursor codex ' ] && ! grep -Fiq 'expected behaviour' "$ROOT/.ai-dev-workflow.yaml"; then ok D-9; else no D-9; fi
if grep -Fq 'coderabbitai[bot]' "$ROOT/docs/workflow/development-workflow/integrations/coderabbit.md" && grep -Fq 'reviews.auto_review.enabled: true' "$ROOT/docs/workflow/development-workflow/integrations/coderabbit.md" && grep -Fq 'after availability and policy' "$ROOT/docs/workflow/development-workflow/integrations/coderabbit.md"; then ok D-10; else no D-10; fi
cmp -s <(block "$ROOT/.claude/agents/item-orchestrator.md") <(block "$ROOT/.cursor/agents/item-orchestrator.md") && ok D-11 || no D-11
all D-12 'indexed `REVIEWER_N_*` fields' 'exactly once'; all D-13 'Run it on every cycle' 'verdict from an earlier cycle is never reused'; all D-14 'is read-only: do not review' 'after determination'; all D-15 'No reviewer is dispatched until the resolver returns' '--runner-kind <actual-driving-session-kind>' 'never a value inferred'; all D-16 'per-reviewer verdict' 'Override-excluded entries appear in the summary'; none D-17 '(<runner-context>)' docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md; all D-18 'BLOCK_CAUSE' 'Local override:' 'Every configured reviewer with its verdict'; all D-19 'availability-resolver-failed' 'gh pr ready <pr_number> --undo' 'dispatch nobody'; all D-20 'no independent `review-effective` or `review-overrides` call' 'After a proceed verdict'; all D-21 'accepted proxy, not proof' 'false Reachable' 'review failure under either policy'; all D-22 'display-only and must never be split or `eval`ed'
canon=$(block "$P"); if [ -n "$canon" ] && [ "$canon" = "$(block "$ROOT/.claude/agents/item-orchestrator.md")" ] && [ "$canon" = "$(block "$ROOT/.cursor/agents/item-orchestrator.md")" ] && [ "$canon" = "$(block "$ROOT/docs/workflow/development-workflow/integrations/codex-github.md")" ]; then ok D-23; else no D-23; fi
all D-24 'installed and reachable' 'not proof of that source' 'Decision 8 waives' 'unavailable with a named reason'
echo "Passed: $PASS"; echo "Failed: $FAIL"; [ "$FAIL" -eq 0 ]

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
if awk '/^[[:space:]]*runner:/{in_runner=1;next} in_runner&&/^[[:space:]]*-[[:space:]]/{if($2 !~ /^(claude|cursor|codex|coderabbit|codex-github)$/) exit 1; next} in_runner{in_runner=0}' "$ROOT/.ai-dev-workflow.yaml" "$ROOT/.ai-dev-workflow.local.example.yaml"; then ok D-4; else no D-4; fi
protocol_remedies=$(sed -n '/| `runtime-absent` |/,/| `value-not-supported` |/p' "$P" | sed -E 's/^\| `([^`]+)` \| (.*) \|$/\1=\2/')
helper_remedies=$(sed -n '/runtime-absent) remedies/,/value-not-supported) remedies/p' "$ROOT/scripts/development-workflow/resolve-reviewer-availability.sh" | awk '{name=$1; sub(/\).*/, "", name); value=$0; sub(/^.*=/, "", value); sub(/^['\''"]/, "", value); sub(/['\''"][[:space:]]*;;$/, "", value); print name "=" value}')
if [ "$protocol_remedies" = "$helper_remedies" ]; then ok D-5; else no D-5; fi
all D-6 'review failure under either policy' 'claude -p --output-format text' 'cursor-agent --print --output-format text' 'codex exec --sandbox read-only' 'exactly one `VERDICT: APPROVED`'
if grep -Fq "driving runner's own stage reviewer" "$P" && grep -Fq "driving runner's own stage reviewer" "$ROOT/docs/workflow/development-workflow/README.md"; then ok D-7; else no D-7; fi
all D-8 'install software, or' 'substitute a reviewer'
if [ "$(awk '/runner:/{on=1;next} on&&/- /{print $2;next} on{exit}' "$ROOT/.ai-dev-workflow.yaml"|tr '\n' ' ')" = 'claude cursor codex ' ] && ! grep -Fiq 'expected behaviour' "$ROOT/.ai-dev-workflow.yaml"; then ok D-9; else no D-9; fi
if grep -Fq 'coderabbitai[bot]' "$ROOT/docs/workflow/development-workflow/integrations/coderabbit.md" && grep -Fq 'reviews.auto_review.enabled: true' "$ROOT/docs/workflow/development-workflow/integrations/coderabbit.md" && grep -Fq 'after availability and policy' "$ROOT/docs/workflow/development-workflow/integrations/coderabbit.md"; then ok D-10; else no D-10; fi
cmp -s <(block "$ROOT/.claude/agents/item-orchestrator.md") <(block "$ROOT/.cursor/agents/item-orchestrator.md") && ok D-11 || no D-11
all D-12 'indexed `REVIEWER_N_*` fields' 'exactly once'; all D-13 'Run it on every cycle' 'verdict from an earlier cycle is never reused'; all D-14 'is read-only: do not review' 'after determination'; all D-15 'No reviewer is dispatched until the resolver returns' '--runner-kind <actual-driving-session-kind>' 'never a value inferred'; all D-16 'per-reviewer verdict' 'Override-excluded entries appear in the summary'; none D-17 '(<runner-context>)' docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md; all D-18 'BLOCK_CAUSE' 'Local override:' 'Every configured reviewer with its verdict'; all D-19 'availability-resolver-failed' 'gh pr ready <pr_number> --undo' 'dispatch nobody'; all D-20 'no independent `review-effective` or `review-overrides` call' 'After a proceed verdict'; all D-21 'accepted proxy, not proof' 'false Reachable' 'review failure under either policy'; all D-22 'display-only and must never be split or `eval`ed'
canon=$(block "$P"); if [ -n "$canon" ] && [ "$canon" = "$(block "$ROOT/.claude/agents/item-orchestrator.md")" ] && [ "$canon" = "$(block "$ROOT/.cursor/agents/item-orchestrator.md")" ] && [ "$canon" = "$(block "$ROOT/docs/workflow/development-workflow/integrations/codex-github.md")" ]; then ok D-23; else no D-23; fi
all D-24 'installed and reachable' 'not proof of that source' 'Decision 8 waives' 'unavailable with a named reason'
echo "Passed: $PASS"; echo "Failed: $FAIL"; [ "$FAIL" -eq 0 ] || exit 1

if [ "${1:-}" = --prove-plants ]; then
  TMP=$(mktemp -d); trap 'rm -rf -- "$TMP"' EXIT
  cp -R "$ROOT/." "$TMP"
  prove() {
    local id="$1" file="$2" needle="$3" replacement="$4" output
    cp -R "$TMP" "$TMP-case" 2>/dev/null || { echo "FAIL: plant $id fixture"; exit 1; }
    perl -0pi -e "s/\Q$needle\E/$replacement/" "$TMP-case/$file"
    output=$(SURFACE_ROOT="$TMP-case" bash "$TMP-case/scripts/development-workflow/tests/test-step7a-surface-consistency.sh" 2>&1 || true)
    if grep -Fq "FAIL: $id" <<< "$output" && [ "$(grep -c '^FAIL:' <<< "$output")" -eq 1 ]; then
      echo "PASS: plant $id ($file)"
    else
      echo "FAIL: plant $id ($file)"; printf '%s\n' "$output"; exit 1
    fi
    rm -rf -- "$TMP-case"
  }
  prove D-1 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md 'codex-github` (hosted-service)' 'gone` (hosted-service)'
  prove D-2 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md 'Availability follows capability' 'runner identity is a sufficient proxy'
  prove D-3 scripts/development-workflow/codex-github-reviewer.sh 'This is a hosted-service reviewer.' 'This is universally reachable.'
  prove D-4 .ai-dev-workflow.local.example.yaml '      - cursor' '      - greptile'
  prove D-5 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md "Install the reviewer's runtime" 'Acquire the runtime'
  prove D-6 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md 'Every dispatched failure is a review failure under either policy.' 'Every dispatched failure is handled.'
  prove D-7 docs/workflow/development-workflow/README.md "driving runner's own stage reviewer" 'stage-appropriate `claude` reviewer'
  prove D-8 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md 'substitute a reviewer while it runs.' 'continue while it runs.'
  prove D-9 .ai-dev-workflow.yaml 'entries are probed against this machine' 'expected behaviour is to hard-fail on a supported runner'
  prove D-10 docs/workflow/development-workflow/integrations/coderabbit.md 'reviews.auto_review.enabled: true' 'reviews.auto_review.enabled: false'
  prove D-11 .cursor/agents/item-orchestrator.md 'Exit `0` approves' 'Exit `0` accepts'
  prove D-12 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md 'exactly once' 'repeatedly'
  prove D-13 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md 'verdict from an earlier cycle is never reused' 'verdict from an earlier cycle is reused'
  prove D-14 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md 'is read-only: do not review' 'may post gh pr comment while running'
  prove D-15 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md 'No reviewer is dispatched until the resolver returns' 'Dispatch reviewers before resolver returns'
  prove D-15 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md '--runner-kind <actual-driving-session-kind>' '--runner-kind omitted'
  prove D-16 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md 'per-reviewer verdict' 'aggregate verdict'
  prove D-17 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md '<reason-display-label>' '(<runner-context>)'
  prove D-18 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md 'Local override:' 'Override:'
  prove D-19 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md 'availability-resolver-failed' 'resolver-failed'
  prove D-20 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md 'After a proceed verdict' 'Before availability'
  prove D-21 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md 'accepted proxy, not proof' 'accepted implementation'
  prove D-22 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md 'must never be split or `eval`ed' 'split CONFIGURED on commas'
  prove D-23 .claude/agents/item-orchestrator.md 'complete short page' 'incomplete short page'
  prove D-24 docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md 'installed and reachable' 'available at runtime'
fi

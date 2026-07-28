# Epic Continuation Gate Smoke Test

**Spec**: [1_1372-epic-continuation-gate_specs.md](../../specs/developments/20260728110000_1372-epic-continuation-gate/1_1372-epic-continuation-gate_specs.md)
**Plan**: [2_1372-epic-continuation-gate_implementation-plan.md](../../specs/developments/20260728110000_1372-epic-continuation-gate/2_1372-epic-continuation-gate_implementation-plan.md)

## Preconditions

- The continuation-gate implementation for issue #1372 must be merged (or checked out on the implementation branch) before running this runbook. Running it against pre-implementation `develop` will fail and is not a regression signal.
- The epic scope resolver is available. Prefer the focused mock harness; use live GitHub only when explicitly noted below.
- GitHub authentication is configured only for the optional live-verification step.
- The runner has an accepted invocation policy when a remaining Backlog child needs to start (`mayStartBacklog` / `--may-start-backlog` as required by the scenario).
- For the optional live step, set a positive integer epic issue number first, for example: `EPIC_NUMBER=900`.

## Boundary: mock vs live

| Surface | Mode | Notes |
| --- | --- | --- |
| `scripts/development-workflow/tests/test-run-epic-scope-resolver.sh` | Mock | Primary verification. Case ids below are the planned harness selectors from the implementation plan; the harness must print or assert each case name so a missing fixture fails closed. |
| Protocol 95 / run-epic skill and command mirrors | Docs inspection | Read-only section checks; no GitHub calls. |
| Optional live child-state check before reporting `complete` | Live | Only after a non-empty all-merged mock result. |

## Scenarios

Run the focused harness once; it must execute every named case. Confirm each case name appears in harness output (or that the harness fails if a case is absent):

```bash
bash scripts/development-workflow/tests/test-run-epic-scope-resolver.sh
```

### 1. `continuation_merged_plus_eligible` → `continue` (mock)

**Expected JSON**: `outcome=continue`, `terminal=false`, `remainingItems` contains the eligible non-Backlog sibling, `affectedItems=[]`, `stopCondition=null`.

### 2. `continuation_authorized_backlog` → `continue` (mock)

**Expected JSON**: `outcome=continue`, `remainingItems` names the Backlog sibling, `stopCondition=null`.

### 3. `continuation_in_review` → `continue` (mock)

**Expected JSON**: `outcome=continue`, `remainingItems` names the in-review sibling, not `complete`.

### 4. `continuation_all_merged` → `complete` (mock + optional live)

**Expected JSON**: `outcome=complete`, `terminal=true`, `remainingItems=[]`, `affectedItems=[]`, `stopCondition=null`.

**Optional live follow-up** (skip if no suitable epic is available):

```bash
if ! [[ "${EPIC_NUMBER:-}" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: EPIC_NUMBER must be a positive integer" >&2
  exit 1
fi
scripts/development-workflow/run-epic-scope-resolver.sh --epic "$EPIC_NUMBER" --json
```

Confirm live child states still match all-merged before any epic closeout summary is reported.

### 5. `continuation_empty_scope` → `needs_resolution` (mock)

**Expected JSON**: `outcome=needs_resolution`, `stopCondition=missing_tracker_context` (exact), `affectedItems=[]`, non-empty `humanAction`.

### 6. `continuation_whitespace_items` → validation failure (mock)

**Focused invocation** (must match the harness case; non-zero exit expected):

```bash
scripts/development-workflow/run-epic-scope-resolver.sh --items "   " --json
echo "exit=$?"
```

**Expected**:
- Non-zero exit status.
- Stderr names the invalid item input.
- No `continuation` object with `outcome=complete` is emitted on stdout.

### 7. `continuation_eligible_plus_blocked` → `continue` (mock)

**Expected JSON**: `outcome=continue`, actionable sibling in `remainingItems`, blocked sibling not forcing `needs_resolution`.

### 8. `continuation_unauthorized_backlog` → `needs_resolution` (mock)

**Expected JSON**: `outcome=needs_resolution`, `stopCondition=human_required` (exact), unauthorized Backlog id in `affectedItems`, `humanAction` asks to grant backlog-start authority.

### 9. Additional named-stop cases (mock; same harness)

These may ship as dedicated harness cases or be folded into the empty/blocked/out-of-scope fixture set during implementation. Assert exact `stopCondition` values from the plan schema:

| Planned case id | Expected `stopCondition` | `affectedItems` |
| --- | --- | --- |
| `continuation_ambiguous_scope` | `missing_tracker_context` | `[]` |
| `continuation_blocked_only` | `unclear_requirements` | blocked child id |
| `continuation_out_of_scope` | `missing_tracker_context` | out-of-scope item id |

### 10. Protocol and command mirrors (docs)

For each file, open the epic continuation / Step 11 (or equivalent) section and confirm semantically — not via a file-wide token grep alone — that:

1. After every child terminal decision, scope is refreshed before an epic summary.
2. The only continuation outcomes are `continue`, `complete`, and `needs_resolution`.
3. No alternate guardrail or policy model is introduced.

```bash
files=(
  docs/workflow/development-workflow/protocols/95-run-epic-protocol.md
  .agents/skills/run-epic/SKILL.md
  .agents/skills/run-epic/agents/openai.yaml
  .claude/commands/run-epic.md
  .cursor/commands/run-epic.md
)
for f in "${files[@]}"; do
  echo "=== review section in $f ==="
  rg -n -i 'continuation|re-resolv|refresh.*scope|needs_resolution|complete|continue' "$f" || {
    echo "FAIL: no continuation guidance in $f" >&2
    exit 1
  }
done
# Then manually verify each matched section satisfies the three semantic checks above.
```

## Expected Result

The runner continues for remaining eligible, authorized Backlog, or in-review work; closes an epic only after a live-verified non-empty all-merged scope; and surfaces empty, ambiguous, blocked-without-actionable-sibling, unauthorized Backlog, and out-of-scope stops with the exact `stopCondition` values from the plan Continuation Schema.

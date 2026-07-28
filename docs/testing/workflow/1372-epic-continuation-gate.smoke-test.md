# Epic Continuation Gate Smoke Test

**Spec**: [1_1372-epic-continuation-gate_specs.md](../../specs/developments/20260728110000_1372-epic-continuation-gate/1_1372-epic-continuation-gate_specs.md)
**Plan**: [2_1372-epic-continuation-gate_implementation-plan.md](../../specs/developments/20260728110000_1372-epic-continuation-gate/2_1372-epic-continuation-gate_implementation-plan.md)

## Preconditions

- The epic scope resolver is available and GitHub authentication is configured for a live run, or its focused mock harness is available.
- The runner has an accepted invocation policy when a remaining Backlog child needs to start.

## Scenarios

1. Run the focused resolver harness. Confirm a merged child plus an eligible sibling returns `continue`, names the sibling, and does not report terminal completion.
2. Confirm a non-empty all-merged fixture returns `complete` only, then verify the live child states before an epic summary is reported.
3. Confirm the empty-scope fixture returns `needs_resolution` with a named stop and human action.
4. Confirm whitespace-only explicit item input fails validation rather than being treated as a completed empty scope.
5. Inspect Protocol 95, the Codex run-epic skill/metadata, and Claude/Cursor commands. Confirm each requires a scope refresh after every child terminal decision and uses the same three outcomes.

## Expected Result

The runner continues for remaining eligible or in-review work, closes an epic only after a live-verified non-empty all-merged scope, and surfaces unresolved scope as a named stop.

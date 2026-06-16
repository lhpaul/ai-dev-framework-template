# Linear Orchestration Support — Implementation Plan

**Spec**: [1\_966-linear-orchestration-support\_specs.md](1_966-linear-orchestration-support_specs.md)
**Smoke test runbook**: [docs/testing/workflow/966-linear-orchestration-support.smoke-test.md](../../../../docs/testing/workflow/966-linear-orchestration-support.smoke-test.md)

---

## Summary

**Approach**: The core bridge pattern is already sketched in the existing scripts
(`workflow-lib.sh` emits warnings for Linear, `add-backlog-item.sh` routes to
`linear_mcp_or_api`, and protocols 90/91 describe `TRACKER_UPDATE_REQUIRED:`
deferral). This plan closes the remaining gaps so that all six orchestration
commands (`run-work`, `run-item-work`, `run-epic`, status reads, status writes,
and backlog creation) behave consistently for Linear teams. Changes fall into
four buckets: (1) documentation updates that fully describe the bridge pattern
for orchestrators, (2) minor script enhancements to `workflow-lib.sh` and
`workflow-batch-plan.sh` that surface clear deferred-action signals instead of
silent empty returns, (3) a new `workflow-lib.sh` helper that encodes the Linear
deferred-action report format, and (4) integration guide additions that give
Linear teams the concrete setup steps and status-mapping table they need.

**Estimated complexity**: M

**Rationale**: No net-new script architecture is needed — the bridge pattern
already exists in embryonic form. The bulk of the work is consistent wiring (all
Linear provider paths emit the same structured `TRACKER_ACTION_REQUIRED=` /
`TRACKER_UPDATE_REQUIRED:` output) and documentation that explains the bridge
clearly enough that orchestrators handle it correctly without guessing. A handful
of unit tests close coverage gaps.

**Dependencies**: None — no other items must be merged first.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `6c84316` |
| Linear provider paths in `workflow-lib.sh` | `grep -n "linear" scripts/development-workflow/workflow-lib.sh` | 18 hits; `get_tracker_status_for_issue` returns `''`, `update_tracker_status_best_effort` emits a `Warning:` string, `record_release_for_issue_best_effort` emits `RELEASE_STAMP_SKIPPED` |
| Deferred-action output consistency | `grep -n "TRACKER_ACTION\|TRACKER_UPDATE_REQUIRED\|deferred" scripts/development-workflow/workflow-lib.sh` | 0 hits — no structured `TRACKER_ACTION_REQUIRED=` signal exists yet |
| `run-epic-scope-resolver.sh` Linear coverage | `grep -n "linear\|provider" scripts/development-workflow/run-epic-scope-resolver.sh` | 0 hits — no Linear-specific path |
| `add-backlog-item.sh` Linear path | `grep -n "linear" scripts/development-workflow/add-backlog-item.sh` | exits non-zero with guidance message; no `TRACKER_ACTION_REQUIRED=` output |
| Test files referencing Linear provider | `grep -rl "MOCK_TRACKER_PROVIDER=linear" scripts/development-workflow/tests/` | `test-workflow-lib-github-projects.sh` only; `get_tracker_status_for_issue` + `update_tracker_status_best_effort` + `record_release_for_issue` covered; deferred-action format not tested |
| Integration guide status-mapping table | `grep -n "Status Field" docs/workflow/development-workflow/integrations/linear.md` | table present at line 22; bridge pattern paragraph absent |
| Protocol 90 Linear discovery section | `grep -n "linear\|bridge" docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | tracker transition section at line 442 mentions MCP; no discovery walkthrough for Linear provider |
| Protocol 91 `TRACKER_UPDATE_REQUIRED` | `grep -n "TRACKER_UPDATE_REQUIRED" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | defined at line 1955; `run-epic` not mentioned |
| Smoke test folder | `ls docs/testing/workflow/ \| grep 966` | absent — to be created |

---

## Layer-by-Layer Changes

### Backend / API (shell scripts)

- [ ] **`scripts/development-workflow/workflow-lib.sh`**: add `emit_linear_deferred_action` helper that prints a structured `TRACKER_ACTION_REQUIRED=<action_type> issue=<id> target_status=<status>` line to stdout. Update `update_tracker_status_best_effort` to call this helper instead of emitting an unstructured `Warning:` string. Update `get_tracker_status_for_issue` to emit `TRACKER_ACTION_REQUIRED=read_status issue=<id>` so callers know a read was skipped (not silently empty).
- [ ] **`scripts/development-workflow/add-backlog-item.sh`**: update the `linear` branch of `create_cmd` to emit `TRACKER_ACTION_REQUIRED=create_item title=<title>` to stdout (in addition to the existing stderr guidance) and exit 0 (not exit 2), so the orchestrator can collect the deferred creation action from output rather than treating it as a fatal error.
- [ ] **`scripts/development-workflow/workflow-batch-plan.sh`**: in the discovery loop, when `get_tracker_status_for_issue` returns empty and provider is Linear, emit a `TRACKER_STATUS_DEFERRED=<issue>` key-value line in the item block so the batch orchestrator knows to query Linear separately rather than treating the status as unknown.
- [ ] **`scripts/development-workflow/run-epic-scope-resolver.sh`**: add a `--provider` / auto-detect path that, when `issue_tracker.provider` is `linear`, emits a `PROVIDER=linear` line in scope output and a `TRACKER_READ_DEFERRED=yes` line, signalling to the invoking orchestrator that item statuses were supplied by the caller rather than queried by the script.

### Shared Packages / Libraries

- [ ] **`scripts/development-workflow/workflow-lib.sh`** (continued): add `workflow_emit_deferred_tracker_action` as a public-facing alias of `emit_linear_deferred_action` for use by other scripts. No external library added.

### Infrastructure / Configuration

No infrastructure or configuration changes. The `.ai-dev-workflow.yaml` schema
already supports `issue_tracker.provider: linear` and
`issue_tracker.custom_fields.project`. No new fields are added.

### Documentation

- [ ] **`docs/workflow/development-workflow/integrations/linear.md`**: add a "Bridge Pattern" section after "Orchestrator Instructions" that explains (a) the orchestrator pre-resolves Linear data and passes it to scripts, (b) scripts emit `TRACKER_ACTION_REQUIRED=` lines for Linear mutations they cannot perform, and (c) the orchestrator applies those mutations via MCP. Add a `TRACKER_ACTION_REQUIRED=` output format reference table.
- [ ] **`docs/workflow/development-workflow/integrations/issue-tracker.md`**: add a "Deferred-action protocol" paragraph that describes the `TRACKER_ACTION_REQUIRED=` output contract and links to `linear.md` for provider-specific details.
- [ ] **`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`**: expand Step 1a to include a "Linear provider" sub-section that walks through how the orchestrator queries Linear items via MCP and passes `ITEM_STATUS=<status>` context to `workflow-batch-plan.sh` via environment variables (or item-list override). Expand Step 2.5 "Orchestrator ownership" section to include the concrete deferred-action collection loop (scan each Work Item Runner summary for `TRACKER_UPDATE_REQUIRED:` or `TRACKER_ACTION_REQUIRED=` lines, then apply via Linear MCP).
- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`**: add a "Linear provider — deferred status reads" paragraph in Step 2 ("Determine Next Action") that explains what to do when `workflow-next-action.sh` returns an empty status for a Linear item (pass the known status from the orchestrator's pre-resolved context). Verify the `TRACKER_UPDATE_REQUIRED:` contract in Step 8b already covers Linear — it does; add a cross-reference to `linear.md`.
- [ ] **`docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`**: add a "Linear provider" section that explains pre-resolving child items via MCP and passing them to the scope resolver, and how `TRACKER_READ_DEFERRED=yes` in scope output signals the orchestrator to apply statuses from its own pre-resolved set.
- [ ] **`docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md`**: update step 3 for the Linear path to note that `add-backlog-item.sh create` now emits a `TRACKER_ACTION_REQUIRED=create_item` line and exits 0, and that the orchestrator must use this output to drive the Linear MCP creation call.

---

## Testing Strategy

**Test types**: Unit (shell harness), Smoke (manual verification against workflow docs)

**Key scenarios to test** (all exercised in the shell unit test file):

1. `emit_linear_deferred_action` prints structured `TRACKER_ACTION_REQUIRED=` line — maps to AC-4
2. `update_tracker_status_best_effort` for Linear emits `TRACKER_ACTION_REQUIRED=set_status` (not unstructured Warning) — maps to AC-4
3. `get_tracker_status_for_issue` for Linear emits `TRACKER_ACTION_REQUIRED=read_status` line — maps to AC-1, AC-2, AC-3, AC-4
4. `add-backlog-item.sh create` for Linear emits `TRACKER_ACTION_REQUIRED=create_item` and exits 0 — maps to AC-5
5. `workflow-batch-plan.sh` emits `TRACKER_STATUS_DEFERRED=<issue>` when provider is Linear — maps to AC-1
6. `run-epic-scope-resolver.sh` emits `PROVIDER=linear` and `TRACKER_READ_DEFERRED=yes` — maps to AC-3
7. GitHub provider paths unchanged after all edits (regression) — maps to AC-8
8. `update_tracker_status_best_effort` backward-rollback guard still works for GitHub after the Linear changes — maps to AC-8

**Smoke test runbook**: `docs/testing/workflow/966-linear-orchestration-support.smoke-test.md`

**Regression suite**: No automated regression suite configured in this repository.

---

## Seed Data

Not applicable — no application database; all testing is via shell harness mocks.

---

## Documentation Updates

The plan itself includes documentation changes as deliverables (see Layer-by-Layer
above). No additional project docs outside `docs/workflow/development-workflow/`
are affected by this feature.

- `docs/workflow/development-workflow/integrations/linear.md` — updated inline (Bridge Pattern section)
- `docs/workflow/development-workflow/integrations/issue-tracker.md` — updated inline (Deferred-action protocol paragraph)
- `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — updated inline (Linear Step 1a and Step 2.5 additions)
- `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — updated inline (Linear Step 2 cross-reference)
- `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` — updated inline (Linear provider section)
- `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md` — updated inline (Linear path exit-0 note)

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Changing `add-backlog-item.sh` exit code from 2 to 0 for the Linear path breaks callers that detect failure via `$?` | Low | Med | Audit callers in `scripts/development-workflow/` and protocols before changing; add test asserting exit 0 + `TRACKER_ACTION_REQUIRED=` on stdout |
| `emit_linear_deferred_action` output added to `get_tracker_status_for_issue` stdout breaks callers that parse the empty return as "unknown status, skip" | Low | Med | The new output line uses a `TRACKER_ACTION_REQUIRED=` prefix that existing callers will not mistake for a status string; unit-test both old callers and new ones |
| Protocol 90 / 91 edits introduce ambiguity with existing GitHub-path text | Low | Low | Keep Linear sub-sections additive (new headings) rather than modifying existing paragraphs |
| `run-epic-scope-resolver.sh` change breaks existing single-provider usage | Low | Low | Add `--provider` detection as an auto-detect fallback behind the existing argument path; no flags removed |

---

## Code Samples

All samples below are illustrative — adapt during implementation.

### `emit_linear_deferred_action` helper (illustrative)

```bash
# In workflow-lib.sh — Illustrative: adapt during implementation
emit_linear_deferred_action() {
  local action_type="$1"   # e.g. set_status, read_status, create_item
  local issue_id="$2"
  local extra="${3:-}"     # e.g. target_status=Plan in Review
  printf 'TRACKER_ACTION_REQUIRED=%s issue=%s%s\n' \
    "$action_type" "$issue_id" "${extra:+ $extra}"
}
```

### `update_tracker_status_best_effort` Linear path (illustrative)

```bash
# Replace the existing Warning: string with a structured emit — Illustrative
if [ "$_utsbe_provider" = "linear" ]; then
  emit_linear_deferred_action "set_status" "$issue_number" \
    "target_status=${status_label}"
  return 0
fi
```

### `add-backlog-item.sh` Linear path (illustrative)

```bash
# Illustrative: adapt during implementation
if [ "$kind" = "linear" ]; then
  printf 'TRACKER_ACTION_REQUIRED=create_item title=%s\n' "$title"
  echo "add-backlog-item: Linear backlog creation requires the orchestrator. Use Linear MCP/API per docs/workflow/development-workflow/integrations/linear.md" >&2
  return 0   # exit 0 so the orchestrator can parse TRACKER_ACTION_REQUIRED from stdout
fi
```

---

## Implementation Order

1. **Add `emit_linear_deferred_action` to `workflow-lib.sh`**: implement the helper function as shown in Code Samples. Place it immediately after `workflow_normalize_issue_tracker_provider`. Confirm the function is reachable from sourced callers by running `source scripts/development-workflow/workflow-lib.sh && emit_linear_deferred_action set_status ENG-123 "target_status=Plan in Review"` and verifying the output is `TRACKER_ACTION_REQUIRED=set_status issue=ENG-123 target_status=Plan in Review`.

2. **Update `update_tracker_status_best_effort` in `workflow-lib.sh`**: replace the `Warning:` string in the Linear branch with a call to `emit_linear_deferred_action "set_status" "$issue_number" "target_status=${status_label}"`. Keep `return 0`. Confirm existing tests still pass: `bash scripts/development-workflow/tests/test-workflow-lib-github-projects.sh`.

3. **Update `get_tracker_status_for_issue` in `workflow-lib.sh`**: after the `_gts_provider = linear` check, emit `emit_linear_deferred_action "read_status" "$issue_number"` to stdout before the `printf ''` + `return 0`. **Important**: callers that parse the return value with command substitution will now receive `TRACKER_ACTION_REQUIRED=read_status issue=<N>` instead of an empty string. Audit all in-repo callers (`grep -rn "get_tracker_status_for_issue" scripts/ docs/`) and update any that test for empty return to instead filter out `TRACKER_ACTION_REQUIRED=` prefixed lines. Confirm the GitHub provider path still returns a clean status string.

4. **Add `TRACKER_STATUS_DEFERRED` emission to `workflow-batch-plan.sh`**: in the item classification loop, after `tracker_status="$(get_tracker_status_for_issue "$issue_number")"`, check whether the returned value is a `TRACKER_ACTION_REQUIRED=read_status` line; if so, set `tracker_status=""` (treat as unknown) and emit `print_kv TRACKER_STATUS_DEFERRED "$issue_number"` in the item block. This gives the portfolio orchestrator a stable signal without changing the skip-or-continue behavior for items whose status cannot be read.

5. **Update `add-backlog-item.sh` Linear branch**: change `exit 2` to `return 0` (inside `create_cmd`) and emit `printf 'TRACKER_ACTION_REQUIRED=create_item title=%s\n' "$title"` to stdout before the existing stderr guidance. Verify exit code is now 0: `./scripts/development-workflow/add-backlog-item.sh create --title "Test" 2>/dev/null; echo "exit=$?"`.

6. **Add `PROVIDER` / `TRACKER_READ_DEFERRED` output to `run-epic-scope-resolver.sh`**: at the top of the script output section (before the first item block is printed), auto-detect `issue_tracker.provider` via `workflow_issue_tracker_provider_raw` and emit `print_kv PROVIDER "$_provider"`. When `_provider = linear`, also emit `print_kv TRACKER_READ_DEFERRED yes`. No behavioral change to scope grouping logic.

7. **Add unit tests for the new Linear signals**: extend `scripts/development-workflow/tests/test-workflow-lib-github-projects.sh` with a new section at the bottom covering:
   - `emit_linear_deferred_action` output format (scenarios 1 above)
   - `update_tracker_status_best_effort` Linear emits `TRACKER_ACTION_REQUIRED=set_status` (scenario 2)
   - `get_tracker_status_for_issue` Linear emits `TRACKER_ACTION_REQUIRED=read_status` (scenario 3)
   - GitHub provider paths unchanged (scenario 7, scenario 8 backward-guard)

   Run all tests after adding: `bash scripts/development-workflow/tests/test-workflow-lib-github-projects.sh`. Confirm output ends with `All N tests passed.`

8. **Update `docs/workflow/development-workflow/integrations/linear.md`**: insert a new "Bridge Pattern" section between "Orchestrator Instructions" and "Branch Naming with Linear". The section must explain the three-phase flow: (a) orchestrator pre-resolves Linear data via MCP, (b) scripts emit `TRACKER_ACTION_REQUIRED=` lines for Linear mutations, (c) orchestrator applies mutations. Include a reference table of all `TRACKER_ACTION_REQUIRED=` action types:
   - `set_status` — emitted by `update_tracker_status_best_effort`
   - `read_status` — emitted by `get_tracker_status_for_issue`
   - `create_item` — emitted by `add-backlog-item.sh create`

9. **Update `docs/workflow/development-workflow/integrations/issue-tracker.md`**: add a "Deferred-action protocol" paragraph at the end of the "Stage-Specific Rules" section. The paragraph must note that for non-CLI providers (e.g., Linear), scripts cannot perform tracker mutations directly; instead they emit `TRACKER_ACTION_REQUIRED=<action_type> issue=<id> [target_status=<status>]` lines to stdout. Orchestrators must scan output for these lines and apply the actions via MCP. Link to `linear.md` for the full reference table.

10. **Update `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`**: in Step 1a, add a "Linear provider" sub-section after the existing "Rate-limit awareness" block. The sub-section must describe how the portfolio orchestrator: (a) queries the configured Linear team via MCP to get all open items, their status, type, priority, and dependencies; (b) formats the result as a list of `ITEM_STATUS=<status>` context lines; (c) passes that context to `workflow-batch-plan.sh` (or processes it inline). In Step 2.5, expand the "Orchestrator ownership" section to include the deferred-action collection loop pattern (pseudocode: `for each Work Item Runner summary: scan for TRACKER_UPDATE_REQUIRED: or TRACKER_ACTION_REQUIRED= lines; for each found: call Linear MCP set_status`).

11. **Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`**: in Step 2 ("Determine Next Action"), add a callout box: "Linear provider — deferred status reads: when `workflow-next-action.sh` returns a `TRACKER_ACTION_REQUIRED=read_status` line in place of an empty status, the orchestrator must supply the known Linear status from its pre-resolved context to determine the next action." Add a cross-reference to Step 8b's existing `TRACKER_UPDATE_REQUIRED:` contract.

12. **Update `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`**: add a "Linear provider" section under the scope resolution step that explains the pre-resolution flow: the orchestrator fetches child items (or the explicit list) from Linear via MCP, passes them as structured input, and interprets `TRACKER_READ_DEFERRED=yes` in scope output as confirmation that item statuses came from the orchestrator's pre-resolved set.

13. **Update `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md`**: in step 3 for the Linear path, add a note: "`add-backlog-item.sh create` now emits `TRACKER_ACTION_REQUIRED=create_item title=<title>` to stdout and exits 0 (not non-zero). The orchestrator must capture this output and use the Linear MCP `createIssue` tool to create the item."

14. **Write and commit smoke test runbook**: create `docs/testing/workflow/966-linear-orchestration-support.smoke-test.md` covering manual verification of each acceptance criterion (see Smoke Test Runbook file).

15. **Run pre-commit lint check** on both deliverable files:

    ```bash
    REPO_ROOT=$(git rev-parse --git-common-dir)/..
    "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
      "docs/specs/developments/20260616190141_966-linear-orchestration-support/2_966-linear-orchestration-support_implementation-plan.md" \
      "docs/testing/workflow/966-linear-orchestration-support.smoke-test.md"
    ```

    Fix any violations before staging.

16. **Update `CHANGELOG.md` under `[Unreleased]`**:

    ```
    - **Add Linear support to run-work / run-item-work / run-epic orchestration commands** (#966): Scripts emit structured TRACKER_ACTION_REQUIRED= deferred-action lines for the Linear provider; protocols 90, 91, 95, and 00 document the bridge pattern end-to-end; integration guide gains a Bridge Pattern reference table.
    ```

# Smoke Test Runbook: Linear Orchestration Support

**Feature**: Linear Orchestration Support (#966)
**Spec**: [docs/specs/developments/20260616190141\_966-linear-orchestration-support/1\_966-linear-orchestration-support\_specs.md](../../specs/developments/20260616190141_966-linear-orchestration-support/1_966-linear-orchestration-support_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Checkout the implementation branch (`feature/966-linear-orchestration-support`)
- [ ] Node.js is available (`node --version`)
- [ ] Bash is available (`bash --version`)
- [ ] `jq` is installed (`jq --version`)
- [ ] `python3` is available (`python3 --version`)

---

## Test Data

Not applicable — all tests exercise shell scripts with mock `gh` binaries
rather than live Linear or GitHub API calls.

---

## Smoke Test Steps

### Step 1: Verify `emit_linear_deferred_action` output format

**Maps to**: AC-4 (status transitions emitted as deferred actions)

1. Source `workflow-lib.sh` and call the new helper:

   ```bash
   source scripts/development-workflow/workflow-lib.sh
   emit_linear_deferred_action "set_status" "ENG-123" "target_status=Plan in Review"
   ```

2. Confirm output is exactly:

   ```
   TRACKER_ACTION_REQUIRED=set_status issue=ENG-123 target_status=Plan in Review
   ```

**Expected result**: The line is printed to stdout with no other text.

---

### Step 2: Verify `update_tracker_status_best_effort` for Linear emits structured output

**Maps to**: AC-4 (deferred status transition, not an unstructured Warning)

1. Create a minimal `.ai-dev-workflow.yaml` stub with `provider: linear`:

   ```bash
   tmp=$(mktemp -d)
   cat > "$tmp/.ai-dev-workflow.yaml" <<'EOF'
   schema_version: 2
   issue_tracker:
     provider: linear
   EOF
   ```

2. Run the function against the stub config:

   ```bash
   WORKFLOW_CONFIG_FILE="$tmp/.ai-dev-workflow.yaml" bash -c '
     source scripts/development-workflow/workflow-lib.sh
     update_tracker_status_best_effort ENG-123 "Plan in Review"
   '
   ```

3. Confirm output contains `TRACKER_ACTION_REQUIRED=set_status issue=ENG-123 target_status=Plan in Review`.
4. Confirm output does **not** contain `Warning: Linear tracker detected`.
5. Confirm exit code is 0.

**Expected result**: Structured deferred-action line on stdout, exit 0.

---

### Step 3: Verify `get_tracker_status_for_issue` for Linear emits `read_status` line

**Maps to**: AC-1, AC-4 (discovery does not silently return empty for Linear)

1. Using the same stub config from Step 2:

   ```bash
   WORKFLOW_CONFIG_FILE="$tmp/.ai-dev-workflow.yaml" bash -c '
     source scripts/development-workflow/workflow-lib.sh
     get_tracker_status_for_issue ENG-123
   '
   ```

2. Confirm output contains `TRACKER_ACTION_REQUIRED=read_status issue=ENG-123`.
3. Confirm exit code is 0.

**Expected result**: Deferred read-status line on stdout, exit 0 (not silent empty string).

---

### Step 4: Verify `add-backlog-item.sh create` for Linear exits 0 and emits deferred action

**Maps to**: AC-5 (backlog creation flow emits deferred action)

1. Using the stub config from Step 2:

   ```bash
   WORKFLOW_CONFIG_FILE="$tmp/.ai-dev-workflow.yaml" \
     scripts/development-workflow/add-backlog-item.sh create \
     --title "Test Linear Item" \
     --body "Test body"
   echo "exit=$?"
   ```

2. Confirm stdout contains `TRACKER_ACTION_REQUIRED=create_item title=Test Linear Item`.
3. Confirm exit code printed is `exit=0`.
4. Confirm stderr contains guidance referencing `linear.md`.

**Expected result**: Structured deferred-action on stdout, guidance on stderr, exit 0.

---

### Step 5: Verify `workflow-batch-plan.sh` emits `TRACKER_STATUS_DEFERRED` for Linear items

**Maps to**: AC-1 (portfolio discovery does not silently drop Linear items)

1. Run the unit tests that cover this path:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-lib-github-projects.sh
   ```

2. Confirm all tests pass (output ends with `All N tests passed.`).
3. Confirm the test output includes test cases for `TRACKER_STATUS_DEFERRED`.

**Expected result**: Test suite passes; `TRACKER_STATUS_DEFERRED` test case is listed.

---

### Step 6: Verify `run-epic-scope-resolver.sh` emits `PROVIDER` and `TRACKER_READ_DEFERRED`

**Maps to**: AC-3 (epic scope resolution signals Linear provider)

1. Using the stub config from Step 2, run the scope resolver with a placeholder item list and capture its output:

   ```bash
   resolver_output="$(WORKFLOW_CONFIG_FILE="$tmp/.ai-dev-workflow.yaml" \
     scripts/development-workflow/run-epic-scope-resolver.sh --items 1 2>/dev/null)"
   echo "$resolver_output"
   ```

2. Confirm output contains `PROVIDER=linear`.
3. Confirm output contains `TRACKER_READ_DEFERRED=yes`.

**Expected result**: Both `PROVIDER=linear` and `TRACKER_READ_DEFERRED=yes` appear in the output.

---

### Step 7: Verify type-based routing falls back for Linear (no type resolvable)

**Maps to**: AC-6 (type-based routing falls back to safe default)

1. Confirm that `get_tracker_type_for_issue` for Linear returns empty (not an error):

   ```bash
   WORKFLOW_CONFIG_FILE="$tmp/.ai-dev-workflow.yaml" bash -c '
     source scripts/development-workflow/workflow-lib.sh
     type="$(get_tracker_type_for_issue ENG-123)"
     printf "type=%s\n" "${type:-<empty>}"
   '
   ```

2. Confirm output is `type=<empty>` and exit code is 0.

**Expected result**: Empty type returned, exit 0 — caller can apply safe default route.

---

### Step 8: Verify GitHub provider paths are unchanged (regression)

**Maps to**: AC-8 (no change to GitHub-tracker behavior)

1. Run the full `test-workflow-lib-github-projects.sh` suite (already run in Step 5 above).
2. Specifically confirm that tests for GitHub Projects status reads, status updates,
   type reads, board membership, and milestone stamping still pass.

**Expected result**: All existing GitHub-path tests pass with no regressions.

---

### Step 9: Verify integration guide bridge pattern documentation

**Maps to**: AC-9 (Linear integration guide documents the bridge pattern)

1. Open `docs/workflow/development-workflow/integrations/linear.md`.
2. Confirm a "Bridge Pattern" section is present after "Orchestrator Instructions".
3. Confirm the section explains all three phases: pre-resolve, emit deferred action, orchestrator applies.
4. Confirm a `TRACKER_ACTION_REQUIRED=` reference table is present with at least `set_status`, `read_status`, and `create_item`.

**Expected result**: "Bridge Pattern" section present with complete reference table.

---

### Step 10: Verify protocol 90 Step 1a Linear sub-section

**Maps to**: AC-1, AC-9

1. Open `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`.
2. Confirm a "Linear provider" sub-section exists within Step 1a.
3. Confirm it describes querying Linear via MCP and passing item context to `workflow-batch-plan.sh`.
4. Confirm Step 2.5 "Orchestrator ownership" section includes the deferred-action collection loop.

**Expected result**: Both sections are present and describe the complete Linear portfolio discovery flow.

---

### Last Step: Clean Up and Validate

- Remove the stub config directory: `rm -rf "$tmp"`
- Confirm no test artifacts remain in the working tree: `git status --short`

---

## Assertions Checklist

- [ ] AC-1: `workflow-batch-plan.sh` emits `TRACKER_STATUS_DEFERRED` for Linear items; items are not silently dropped (Steps 5, 10).
- [ ] AC-2: `run-item-work` can resolve the next action for a Linear item; deferred-action mechanism (`TRACKER_ACTION_REQUIRED=read_status`, `set_status`) enables the orchestrator to supply and apply Linear status (Steps 2, 3).
- [ ] AC-3: `run-epic-scope-resolver.sh` emits `PROVIDER=linear` and `TRACKER_READ_DEFERRED=yes`; epic scope resolution signals the orchestrator to supply item statuses (Step 6).
- [ ] AC-4: `emit_linear_deferred_action` produces the canonical `TRACKER_ACTION_REQUIRED=` format; `update_tracker_status_best_effort` emits `TRACKER_ACTION_REQUIRED=set_status` (not unstructured Warning); status progression order is unchanged for GitHub (Steps 1, 2, 8).
- [ ] AC-5: `add-backlog-item.sh create` exits 0 and emits `TRACKER_ACTION_REQUIRED=create_item` for Linear (Step 4).
- [ ] AC-6: `get_tracker_type_for_issue` returns empty (not error) for Linear; caller can apply safe default route (Step 7).
- [ ] AC-7: Linear-dependent commands emit actionable `TRACKER_ACTION_REQUIRED=` lines rather than empty or misleading output, so the orchestrator receives an explicit signal when Linear access is needed (Steps 2, 3).
- [ ] AC-8: All `test-workflow-lib-github-projects.sh` GitHub-path tests pass with no regressions (Step 8).
- [ ] AC-9: `linear.md` Bridge Pattern section and reference table are present; protocols 90, 91, 95, and 00 are updated (Steps 9, 10).

---

## Seed Data Reference

Not applicable — shell script tests use inline mock `gh` binaries; no database seed data required.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `emit_linear_deferred_action: command not found` | Function not added to `workflow-lib.sh` | Ensure Step 1 of implementation order was completed |
| `update_tracker_status_best_effort` still prints `Warning: Linear tracker detected` | Linear branch not updated in Step 2 | Check the `_utsbe_provider = linear` branch in `workflow-lib.sh` |
| `add-backlog-item.sh` exits non-zero for Linear | `return 0` not substituted for `exit 2` | Check `create_cmd` linear branch in `add-backlog-item.sh` |
| `get_tracker_status_for_issue` returns empty for Linear | Deferred-action emit added but not before `printf ''` | Ensure `emit_linear_deferred_action` call precedes `printf ''` |
| Unit test suite fails on GitHub-path tests | Regression from Step 3 caller audit | Recheck callers of `get_tracker_status_for_issue` for empty-string assumptions |

---

## Known Limitations

- Live Linear MCP calls are not smoke-tested here; the runbook validates the deferred-action
  signal contract only. Full end-to-end Linear MCP validation requires a Linear workspace
  and is performed manually by the operator after deployment.

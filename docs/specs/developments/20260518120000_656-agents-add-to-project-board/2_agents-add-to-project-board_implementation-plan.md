# Agents Add to Project Board — Implementation Plan

**Spec**: [1_agents-add-to-project-board_specs.md](./1_agents-add-to-project-board_specs.md)
**Smoke test runbook**: [docs/testing/workflow/656-agents-add-to-project-board.smoke-test.md](../../../../docs/testing/workflow/656-agents-add-to-project-board.smoke-test.md)

---

## Summary

**Approach**: Add an `ensure_on_project_board` shell function to `workflow-lib.sh` that idempotently checks whether a GitHub issue is already registered on the configured project board and adds it if missing, then call this function inside the completion sequence of each stage protocol (`01-generate-spec-protocol.md`, `02-generate-implementation-plan-protocol.md`, `03-implement-development-protocol.md`) and confirm the Portfolio Orchestrator's Protocol 90 Step 2.5 already documents the equivalent step. The same board-add call is added as an instruction to each affected agent/skill guidance file so agents that run the protocols standalone also perform the check.

**Estimated complexity**: S

**Rationale**: The change is purely additive: one new function in `workflow-lib.sh` and instructions inserted at well-defined points in four protocol documents and their corresponding agent/skill guidance files. No schema changes, no new architectural layers, no coordination between services. All stages already have a "push branch and open draft PR" step; the board-add step inserts immediately before that step's tracker-status update in each protocol.

**Dependencies**: None

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `35875f0` |
| Protocol files that reference project board | `grep -rn "project board" docs/workflow/development-workflow/protocols/ --include="*.md" -l` | `90-batch-orchestrate-work-protocol.md`, `00-add-backlog-item-protocol.md` |
| Agent/skill files referencing affected protocols | `grep -rl "02-generate-implementation-plan-protocol\|03-implement-development-protocol\|01-generate-spec-protocol\|90-batch-orchestrate-work-protocol" .claude/agents/ .cursor/agents/ .codex/skills/` | `.claude/agents/developer.md`, `.claude/agents/orchestrator.md`, `.claude/agents/product-manager.md`, `.claude/agents/tech-lead.md`, `.codex/skills/workflow-implementer/SKILL.md`, `.codex/skills/workflow-orchestrator/SKILL.md`, `.codex/skills/workflow-plan-writer/SKILL.md`, `.codex/skills/workflow-spec-writer/SKILL.md`, `.cursor/agents/developer.md`, `.cursor/agents/orchestrator.md`, `.cursor/agents/product-manager.md`, `.cursor/agents/tech-lead.md` |
| Existing board-add function in workflow-lib.sh | `grep -n "ensure.*board\|board.*ensure\|item-add" scripts/development-workflow/workflow-lib.sh` | 0 matches — function does not exist yet |
| Existing update_tracker_status_best_effort line range | `grep -n "update_tracker_status_best_effort" scripts/development-workflow/workflow-lib.sh` | Lines 533–649 |
| workflow-lib.sh total lines | `wc -l scripts/development-workflow/workflow-lib.sh` | 649 lines |

---

## Layer-by-Layer Changes

### Shared Packages / Libraries

- [ ] Add `ensure_on_project_board <issue_number> <initial_status>` function to `scripts/development-workflow/workflow-lib.sh`.
  - Check whether the issue is already in the project using `gh project item-list`. If found, log `already present` and return 0. If not found, add it with `gh project item-add` and then set its status to `<initial_status>` using the same GraphQL mutation already used by `update_tracker_status_best_effort`. Log `added to board`. On any API failure, log a warning and return 0 (fail-open).

### Infrastructure / Configuration

- [ ] `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md` — insert a "Board Membership Check" paragraph in Step 5 (Git Execution), before the tracker status note. The step runs after the spec file is written and before `git push` / draft PR creation.
- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` — insert a "Board Membership Check" paragraph in Step 5 (Git Execution), in the same position relative to the push/draft-PR steps.
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` — insert a "Board Membership Check" paragraph in the "Open PR (Draft)" section of each path: Path 1 Step 8, Path 2 (Refactor) numbered step 9 "Open a draft PR targeting develop", Path 3 (Fast Track) Step 8, and Path 4 (Hotfix) "Open PR (Draft)" — immediately before the `gh pr create` command in each location.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — verify Step 2.5 sub-step 1 already documents the board-add check. If the prose lacks a concrete `ensure_on_project_board` call example, add a shell snippet showing how to invoke the new function.
- [ ] `.claude/agents/product-manager.md` — add one sentence after the protocol reference: call `ensure_on_project_board` on the issue before updating tracker status when running the spec completion sequence standalone.
- [ ] `.cursor/agents/product-manager.md` — same addition as the Claude agent.
- [ ] `.codex/skills/workflow-spec-writer/SKILL.md` — add a numbered step: before opening the draft spec PR, call `ensure_on_project_board` with initial status `Writing Spec`.
- [ ] `.claude/agents/tech-lead.md` — add one sentence: call `ensure_on_project_board` before updating tracker status when running the plan completion sequence standalone.
- [ ] `.cursor/agents/tech-lead.md` — same addition as the Claude agent.
- [ ] `.codex/skills/workflow-plan-writer/SKILL.md` — add a numbered step: before opening the draft plan PR, call `ensure_on_project_board` with initial status `Writing Plan`.
- [ ] `.claude/agents/developer.md` — add one sentence in the Key rules list: call `ensure_on_project_board` before updating tracker status when running the implementation completion sequence standalone.
- [ ] `.cursor/agents/developer.md` — same addition as the Claude agent.
- [ ] `.codex/skills/workflow-implementer/SKILL.md` — add one step: before opening the draft implementation PR, call `ensure_on_project_board` with initial status `In Development`.

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:

1. Spec-writer board-add path: run the spec completion sequence on an issue not yet on the board; verify the issue appears on the board with status "Writing Spec" before the draft PR is opened. (Maps to AC 1)
2. Plan-writer board-add path: run the plan completion sequence on an issue not yet on the board; verify status "Writing Plan". (Maps to AC 2)
3. Developer board-add path: run the implementation completion sequence on an issue not yet on the board; verify status "In Development". (Maps to AC 3)
4. Already-on-board idempotency: run any of the above on an issue already present on the board; verify the existing board status is not modified by the add step. (Maps to AC 4)
5. Portfolio orchestrator path: verify Step 2.5 of Protocol 90 includes the board-add and that the new `ensure_on_project_board` function is available for the orchestrator to call. (Maps to AC 5)
6. Fail-open: simulate an API error from `gh project item-add`; verify the agent logs a warning and continues to push and open the PR. (Maps to AC 6)
7. Idempotency of repeated calls: call `ensure_on_project_board` twice for the same issue; verify no duplicate board entries and exit code 0 both times. (Maps to AC 7)
8. Documentation coverage: verify all four protocol files and all agent/skill files contain the board-add step. (Maps to AC 8)

**Smoke test runbook**: `docs/testing/workflow/656-agents-add-to-project-board.smoke-test.md`

---

## Seed Data

No database seed data required. The smoke test requires:

| Entity | Values / Scenario | File |
| --- | --- | --- |
| GitHub issue not on project board | A test issue created with `gh issue create` and NOT added to the project board | Created ad hoc during test run |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/github-projects.md` — add a reference to the new `ensure_on_project_board` function under the "CLI Update Patterns for Agents and Subagents" section, explaining that agents call it before tracker status updates.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| `gh project item-add` returns non-zero when item already exists on some versions | Low | Low | Check for item presence first using `item-list`; only call `item-add` when item is absent. This is the same idempotency pattern used in Step 2.5 of Protocol 90. |
| Multiple protocol files updated inconsistently | Med | Med | Implementation Order prescribes a sequential update-and-verify pattern per file. Cross-section consistency self-check in protocol 02 Step 5 catches contradictions before commit. |
| Agent files have different wording that diverges from protocols | Low | Low | Keep agent file additions to one sentence each, pointing to the protocol function name rather than duplicating prose. |

---

## Code Samples

```bash
# Illustrative — adapt during implementation
ensure_on_project_board() {
  local issue_number="$1"
  local initial_status="$2"
  local owner project_number project_id item_json item_id repo_url

  project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
  if [ -z "$project_number" ]; then
    echo "Warning: GITHUB_PROJECT_NUMBER not set; skipping board-membership check."
    return 0
  fi
  owner="$(workflow_resolve_github_project_owner)"
  if [ -z "$owner" ]; then
    return 0
  fi

  # Check whether issue is already on the board
  item_json=$(gh project item-list "$project_number" --owner "$owner" --limit 10000 --format json 2>/dev/null \
    | python3 -c "
import json, sys
num = int(sys.argv[1])
data = json.loads(sys.stdin.read(), strict=False)
for item in data.get('items', []):
    if item.get('content', {}).get('number') == num:
        print(json.dumps(item))
        break
" "$issue_number" || true)

  if [ -n "$item_json" ]; then
    echo "Board membership check: issue #${issue_number} already on project board."
    return 0
  fi

  # Not on board — add it
  repo_url=$(gh repo view --json url --jq '.url' 2>/dev/null || true)
  if [ -z "$repo_url" ]; then
    echo "Warning: could not resolve repo URL; skipping board-add for issue #${issue_number}."
    return 0
  fi
  gh project item-add "$project_number" --owner "$owner" \
    --url "${repo_url}/issues/${issue_number}" 2>/dev/null \
    || { echo "Warning: gh project item-add failed for issue #${issue_number}; continuing."; return 0; }

  echo "Board membership check: issue #${issue_number} added to project board."
  # Set initial status
  update_tracker_status_best_effort "$issue_number" "$initial_status"
}
```

---

## Implementation Order

1. **Add `ensure_on_project_board` to `workflow-lib.sh`**

   Add the function immediately before `update_tracker_status_best_effort` (around line 533). The function must follow the same patterns used elsewhere in `workflow-lib.sh`: use `workflow_issue_tracker_project_number`, `workflow_resolve_github_project_owner`, Python3 for JSON parsing (for control-character robustness), and `|| true` / `return 0` on all failure paths.

   After adding, source the file and run a smoke check:
   ```bash
   bash -c 'source scripts/development-workflow/workflow-lib.sh && declare -f ensure_on_project_board'
   ```
   Confirm the function is declared (non-empty output).

2. **Update `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`**

   In Step 5 (Git Execution), add a sub-step after the "Create the spec file" step and before "Commit". The sub-step reads:

   > **Board membership check (mandatory — before tracker status update)**: Before committing, call `ensure_on_project_board <issue_number> "Writing Spec"` (sourcing `scripts/development-workflow/workflow-lib.sh`). If the issue is already on the project board, this is a no-op. If it is not, the function adds it and sets initial status to "Writing Spec". On any API failure, the function logs a warning and continues — this step must never block the commit or PR creation.

   Verify the paragraph appears in the correct location using:
   ```bash
   grep -n "ensure_on_project_board" docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md
   ```
   Confirm the line number is in the Step 5 block.

3. **Update `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`**

   In Step 5 (Git Execution), add the same board membership check sub-step with initial status `"Writing Plan"`. Apply the same placement rule as Step 2 above.

   Verify:
   ```bash
   grep -n "ensure_on_project_board" docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md
   ```

4. **Update `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`**

   In each of the four paths that contains a PR-open step, add the board membership check immediately before the `gh pr create` call, with initial status `"In Development"`:

   - Path 1 (Full Pipeline): `### Step 8: Open PR (Draft)` heading
   - Path 2 (Refactor): numbered step 9 — "Open a draft PR targeting `develop`" (this path uses in-text numbered steps rather than separate `### Step N` headings for most steps)
   - Path 3 (Fast Track): `### Step 8: Open PR (Draft)` heading
   - Path 4 (Hotfix): the "Open PR (Draft)" step in the hotfix path

   Because the board-add step text is identical for all implementation paths, use consistent wording in each location.

   Verify:
   ```bash
   grep -c "ensure_on_project_board" docs/workflow/development-workflow/protocols/03-implement-development-protocol.md
   ```
   Confirm count is 4 (one per path).

5. **Verify `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` Step 2.5**

   Read Step 2.5 sub-step 1. If it already has a shell snippet calling `ensure_on_project_board`, no change is needed. If the prose describes the board-add but does not show a concrete function call, add a shell snippet:

   ```bash
   # Illustrative — adapt during implementation
   ensure_on_project_board "$ISSUE_NUMBER" "$INITIAL_STATUS"
   ```

   Immediately after the existing prose for Step 2.5 sub-step 1. The snippet must reference the function by the exact name `ensure_on_project_board` so it matches the function added to `workflow-lib.sh`.

6. **Update `.claude/agents/product-manager.md`**

   Append one sentence to the existing instructions: "Before updating tracker status as part of a standalone spec completion sequence, call `ensure_on_project_board <issue_number> 'Writing Spec'` (from `scripts/development-workflow/workflow-lib.sh`) to register the issue on the project board if it is not already present."

7. **Update `.cursor/agents/product-manager.md`**

   Same addition as Step 6 (identical text).

8. **Update `.codex/skills/workflow-spec-writer/SKILL.md`**

   Add one numbered step: "Before opening the draft spec PR, call `ensure_on_project_board <issue_number> 'Writing Spec'` from `scripts/development-workflow/workflow-lib.sh`. This is a no-op when the issue is already on the board."

9. **Update `.claude/agents/tech-lead.md`**

   Append one sentence: "Before updating tracker status as part of a standalone plan completion sequence, call `ensure_on_project_board <issue_number> 'Writing Plan'` (from `scripts/development-workflow/workflow-lib.sh`) to register the issue on the project board if it is not already present."

10. **Update `.cursor/agents/tech-lead.md`**

    Same addition as Step 9.

11. **Update `.codex/skills/workflow-plan-writer/SKILL.md`**

    Add one numbered step: "Before opening the draft plan PR, call `ensure_on_project_board <issue_number> 'Writing Plan'` from `scripts/development-workflow/workflow-lib.sh`. This is a no-op when the issue is already on the board."

12. **Update `.claude/agents/developer.md`**

    Add one bullet to the "Key rules" list: "Before updating tracker status as part of a standalone implementation completion sequence, call `ensure_on_project_board <issue_number> 'In Development'` (from `scripts/development-workflow/workflow-lib.sh`) to register the issue on the project board if it is not already present."

13. **Update `.cursor/agents/developer.md`**

    Same addition as Step 12.

14. **Update `.codex/skills/workflow-implementer/SKILL.md`**

    Add one numbered step: "Before opening the draft implementation PR, call `ensure_on_project_board <issue_number> 'In Development'` from `scripts/development-workflow/workflow-lib.sh`. This is a no-op when the issue is already on the board."

15. **Update `docs/workflow/development-workflow/integrations/github-projects.md`**

    Under the "CLI Update Patterns for Agents and Subagents" section, add a short paragraph explaining that stage agents call `ensure_on_project_board` from `workflow-lib.sh` before updating tracker status. Include the function signature and its fail-open guarantee.

16. **Verify smoke test runbook**: follow the `docs/testing/workflow/656-agents-add-to-project-board.smoke-test.md` runbook manually on a test issue.

17. **Update `CHANGELOG.md` under `[Unreleased]`**:
    ```
    - **Ensure spec/plan/developer agents add issues to project board** (#656): adds `ensure_on_project_board` to `workflow-lib.sh` and calls it in the completion sequence of `01-generate-spec-protocol.md`, `02-generate-implementation-plan-protocol.md`, and `03-implement-development-protocol.md` so issues are guaranteed to appear on the GitHub Projects board before their tracker status is updated.
    ```

# Smoke Test Runbook: Agents Add to Project Board

**Feature**: Ensure spec/plan/developer agents add issues to the project board
**Spec**: [1_agents-add-to-project-board_specs.md](../../specs/developments/20260518120000_656-agents-add-to-project-board/1_agents-add-to-project-board_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] `gh` CLI is authenticated and has `project`, `repo`, and `issues` scopes
- [ ] `GITHUB_PROJECT_NUMBER` is set to the project number (e.g. `1`) or the value is in `.ai-dev-workflow.yaml`
- [ ] `scripts/development-workflow/workflow-lib.sh` is present and functional
- [ ] A test GitHub issue can be created and deleted without affecting active work

---

## Test Data

| Item | Value |
| --- | --- |
| Project number | `1` (or whichever is configured in `.ai-dev-workflow.yaml`) |
| Project owner | `lhpaul` (or the repo owner) |
| Test issue | Created ad hoc during Step 1 — delete after test |

---

## Smoke Test Steps

### Step 1: Create a test issue not on the project board

```bash
TEST_ISSUE=$(gh issue create --title "Smoke test: board-add (delete me)" --body "Temporary issue for smoke testing #656." --label workflow --json number --jq '.number')
echo "Created test issue #$TEST_ISSUE"
```

Verify: the issue number is printed and the issue is open (`gh issue view $TEST_ISSUE --json state`).

### Step 2: Confirm the issue is NOT on the project board

```bash
PROJECT_NUMBER="${GITHUB_PROJECT_NUMBER:-1}"
OWNER="$(gh repo view --json owner --jq '.owner.login')"
gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --limit 10000 --format json \
  | python3 -c "
import json, sys
num = int(sys.argv[1])
data = json.loads(sys.stdin.read(), strict=False)
found = any(item.get('content', {}).get('number') == num for item in data.get('items', []))
print('ON BOARD' if found else 'NOT ON BOARD')
" "$TEST_ISSUE"
```

**Expected result**: `NOT ON BOARD`

### Step 3: Call `ensure_on_project_board` with initial status "Writing Spec"

**Maps to**: Acceptance Criterion 1

```bash
bash -c "
source scripts/development-workflow/workflow-lib.sh
ensure_on_project_board $TEST_ISSUE 'Writing Spec'
"
```

**Expected result**: Log line `Board membership check: issue #${TEST_ISSUE} added to project board.` followed by `Updating tracker status for issue #${TEST_ISSUE} to 'Writing Spec'...` (or similar). No error output.

### Step 4: Confirm the issue is now on the board with status "Writing Spec"

**Maps to**: Acceptance Criterion 1

```bash
bash -c "
source scripts/development-workflow/workflow-lib.sh
get_tracker_status_for_issue $TEST_ISSUE
"
```

**Expected result**: `Writing Spec`

### Step 5: Call `ensure_on_project_board` a second time (idempotency check)

**Maps to**: Acceptance Criterion 7

```bash
bash -c "
source scripts/development-workflow/workflow-lib.sh
ensure_on_project_board $TEST_ISSUE 'Writing Spec'
"
```

**Expected result**: Log line `Board membership check: issue #${TEST_ISSUE} already on project board.` No duplicate board entry created. Exit code 0.

Verify no duplicate:
```bash
PROJECT_NUMBER="${GITHUB_PROJECT_NUMBER:-1}"
OWNER="$(gh repo view --json owner --jq '.owner.login')"
gh project item-list "$PROJECT_NUMBER" --owner "$OWNER" --limit 10000 --format json \
  | python3 -c "
import json, sys
num = int(sys.argv[1])
data = json.loads(sys.stdin.read(), strict=False)
count = sum(1 for item in data.get('items', []) if item.get('content', {}).get('number') == num)
print(f'Count: {count}')
" "$TEST_ISSUE"
```

**Expected result**: `Count: 1`

### Step 6: Verify existing board status is not overwritten by the add step

**Maps to**: Acceptance Criterion 4

The status is currently "Writing Spec". Calling `ensure_on_project_board` again must not change it.

```bash
bash -c "
source scripts/development-workflow/workflow-lib.sh
ensure_on_project_board $TEST_ISSUE 'Writing Plan'
get_tracker_status_for_issue $TEST_ISSUE
"
```

**Expected result**: Log line `already on project board`. Final status output is still `Writing Spec` — the existing status is NOT changed to "Writing Plan" by the board-add step (only the tracker-status update that follows in the normal flow changes the status; the board-add step does not overwrite an existing status).

Note: the `update_tracker_status_best_effort` call inside `ensure_on_project_board` only runs when the item was just added. If the item already exists, the function returns without calling `update_tracker_status_best_effort`.

### Step 7: Documentation coverage check

**Maps to**: Acceptance Criterion 8

```bash
grep -l "ensure_on_project_board" \
  docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md \
  docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md \
  docs/workflow/development-workflow/protocols/03-implement-development-protocol.md \
  .claude/agents/product-manager.md \
  .claude/agents/tech-lead.md \
  .claude/agents/developer.md \
  .cursor/agents/product-manager.md \
  .cursor/agents/tech-lead.md \
  .cursor/agents/developer.md \
  .codex/skills/workflow-spec-writer/SKILL.md \
  .codex/skills/workflow-plan-writer/SKILL.md \
  .codex/skills/workflow-implementer/SKILL.md
```

**Expected result**: All 12 listed files are printed (all contain `ensure_on_project_board`).

### Step 8: Cleanup — close and remove the test issue

```bash
gh issue close $TEST_ISSUE --comment "Smoke test complete — closing test issue."
```

**Expected result**: Issue is closed. (The project board entry can remain; it will be cleaned up manually or by the next orchestrator run.)

---

## Assertions Checklist

- [ ] AC 1: Issue appears on the board with status "Writing Spec" after calling `ensure_on_project_board $TEST_ISSUE 'Writing Spec'` on an issue not previously on the board.
- [ ] AC 4: Calling `ensure_on_project_board` on an already-present issue does not change the existing board status.
- [ ] AC 6: Any API failure logs a warning and returns 0; the caller (protocol or agent) continues unblocked.
- [ ] AC 7: Running `ensure_on_project_board` twice for the same issue results in exactly one board entry.
- [ ] AC 8: All 12 specified files contain a reference to `ensure_on_project_board`.

---

## Seed Data Reference

| Entity | Scenario | How to load |
| --- | --- | --- |
| Test GitHub issue | Issue not yet on the project board | `gh issue create --title "Smoke test: board-add (delete me)" ...` (see Step 1) |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `Warning: GITHUB_PROJECT_NUMBER not set` | Env var not set and not in `.ai-dev-workflow.yaml` | Set `export GITHUB_PROJECT_NUMBER=1` or update `.ai-dev-workflow.yaml` |
| `could not resolve project ID` | Wrong project number or owner | Run `gh project list --owner <OWNER>` to confirm number |
| `gh project item-add` returns non-zero | Issue URL format wrong or permissions | Confirm `gh auth status` shows `projects` scope |
| Status not updated after add | `update_tracker_status_best_effort` found a more advanced status | Expected if issue was already at a higher status |

---

## Known Limitations

- This runbook tests `ensure_on_project_board` directly. Full end-to-end testing of the spec/plan/developer agent paths requires running those agents on a test issue, which is out of scope for a unit-level smoke test.
- The "fail-open" scenario (AC 6) requires simulating an API error, which is not easily done without mocking `gh`. Reviewers may accept manual inspection of the function's error paths as sufficient.

# fix(post-merge-cleanup): Contradictory Log Output and Missing Tracker Status Update — Implementation Plan

**Spec**: [1_post-merge-cleanup-log-and-tracker_specs.md](1_post-merge-cleanup-log-and-tracker_specs.md)
**Smoke test runbook**: [../../testing/workflow/184-post-merge-cleanup-log-and-tracker.smoke-test.md](../../../testing/workflow/184-post-merge-cleanup-log-and-tracker.smoke-test.md)

---

## Summary

**Approach**: Unify the two separate issue-number extraction regexes in `post-merge-cleanup.sh` into a single code path that covers all branch prefixes (`fix`, `feature`, `hotfix`, `refactor`, `spec`, `implementation-plan`), then add a `update_tracker_status` helper that calls the `updateProjectV2ItemFieldValue` GraphQL mutation using the already-available `gh` CLI to set the project board Status after each merge.

**Estimated complexity**: S

**Rationale**: Both changes are confined to a single shell script with no dependencies on other files. The GraphQL pattern is already documented in `docs/ai/development-workflow/integrations/github-projects.md` and similar patterns exist elsewhere in the workflow. No schema changes, no frontend, no new packages.

**Dependencies**: None. (The #177 plan adds `git worktree unlock` + force-remove near the `git worktree remove` call — a disjoint line range from the issue-number detection block and the new tracker update block. The two changes will apply cleanly on top of each other.)

---

## Layer-by-Layer Changes

### Scripts / Shell (`scripts/development-workflow/post-merge-cleanup.sh`)

- [ ] **Unify issue-number extraction** (Bug Fix 1 — contradictory log output):
  Replace the two separate `if/elif` regex blocks for `(fix|feature|hotfix|refactor)` and `(spec|implementation-plan)` with a single block that captures the issue number from any matching prefix and sets a `BRANCH_TYPE` variable (`implementation`, `spec`, or `plan`). The `STAGE_ISSUE` variable and the separate `ISSUE_NUMBER` variable are merged into a single `ISSUE_NUMBER` extraction followed by a `BRANCH_TYPE` classification. This eliminates the code path that sets `STAGE_ISSUE` without setting `ISSUE_NUMBER`, which is the root cause of the spurious "No issue number detected" fallthrough for spec/plan branches.

- [ ] **Add `update_tracker_status` helper function**: Implement a bash function `update_tracker_status <issue_number> <status_label>` that:
  1. Reads `GITHUB_PROJECT_NUMBER` and `GITHUB_PROJECT_OWNER` from environment (with fallback to querying the repo owner via `gh repo view --json owner`).
  2. Fetches the project node ID: `gh project view <NUMBER> --owner <OWNER> --format json | jq -r '.id'`.
  3. Fetches the Status field ID and the option ID for `<status_label>` via `gh project field-list`.
  4. Fetches the project item ID for the issue via `gh project item-list`.
  5. Runs the `updateProjectV2ItemFieldValue` GraphQL mutation via `gh api graphql`.
  6. On any step failure, logs a `Warning:` line and returns 0 (best-effort, non-fatal).

- [ ] **Call `update_tracker_status` from the unified issue-number block**:
  - If `BRANCH_TYPE=spec`: call `update_tracker_status "$ISSUE_NUMBER" "Spec Ready"`.
  - If `BRANCH_TYPE=plan`: call `update_tracker_status "$ISSUE_NUMBER" "Plan Ready"`.
  - If `BRANCH_TYPE=implementation`: after the existing issue-close logic, call `update_tracker_status "$ISSUE_NUMBER" "Merged"`.

- [ ] **Emit exactly one log line per branch** for the issue-number outcome:
  - Issue detected + stays open (spec/plan): one line, e.g. `Plan/spec branch for issue #N merged; issue stays open for the next workflow stage. Updating tracker status to <Status>...`
  - Issue detected + closed (implementation): the existing close log lines are preserved; add one line for tracker update.
  - No issue number detected: one line (existing), no tracker update.

### Documentation (`docs/ai/development-workflow/integrations/github-projects.md`)

- [ ] **Align "Post-Merge Cleanup" section (Step 3)**: Update the step list under "Post-Merge Cleanup" (currently only mentions closing the issue and setting status to `Merged`) to reflect that all branch types now update tracker status:
  - `spec/*` → `Spec Ready`
  - `implementation-plan/*` → `Plan Ready`
  - `feature/*`, `fix/*`, `refactor/*`, `hotfix/*` → `Merged` (and closes issue)

---

## Testing Strategy

**Test types**: Manual smoke test (shell script — no automated unit test suite in this repo for scripts)

**Key scenarios to test**:
1. Run `post-merge-cleanup.sh spec/184-…` (simulated/dry-run path) — single log line, no "No issue number detected", tracker update attempted for `Spec Ready` — maps to AC 1 and AC 4
2. Run `post-merge-cleanup.sh implementation-plan/184-…` — single log line, tracker update attempted for `Plan Ready` — maps to AC 2 and AC 5
3. Run `post-merge-cleanup.sh feature/184-…` — issue close preserved, tracker update attempted for `Merged` — maps to AC 3
4. Run with a branch that has no numeric prefix — single "No issue number detected" line, no tracker update — maps to AC 6
5. Run with GitHub Projects env vars absent or pointing to non-existent project — script exits 0 with warning — maps to AC 7

**Smoke test runbook**: [`docs/testing/workflow/184-post-merge-cleanup-log-and-tracker.smoke-test.md`](../../../testing/workflow/184-post-merge-cleanup-log-and-tracker.smoke-test.md)

---

## Seed Data

Not applicable. This feature modifies a shell script with no database or seed data requirements. Smoke test scenarios are exercised against live GitHub API or simulated by patching environment variables (see runbook).

---

## Documentation Updates

- [ ] `docs/ai/development-workflow/integrations/github-projects.md` — update the "Post-Merge Cleanup" section to list all three status transitions (Spec Ready, Plan Ready, Merged) rather than only Merged. *(This update is planned in the Layer-by-Layer Changes above and executed during implementation.)*

No other project docs require changes. `AGENTS.md`/`CLAUDE.md` reference the `post-merge-cleanup` command but do not describe its internal tracker behavior. `docs/best-practices/2-version-control.md` and Protocol 91 Step 10 already list the correct status transitions without prescribing how the script implements them.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| GitHub Projects API fields not discoverable (project not configured) | Low | Low | Helper is best-effort: logs warning, exits 0. Git cleanup always runs first. |
| Regex unification accidentally breaks feature/fix/refactor/hotfix issue extraction | Low | Med | New unified regex covers the same patterns; add explicit test cases in smoke runbook for each prefix type |
| `gh project item-list` returns empty for issues not added to any project | Low | Low | Helper detects empty item ID and logs warning, exits 0 |
| Collision with #177 impl edits to `post-merge-cleanup.sh` | Low | Low | Edits are in non-overlapping line ranges (worktree unlock near `git worktree remove`; unified regex near `gh issue close`; new tracker block after close block). Batch-merge auto-resolution handles CHANGELOG conflicts. |

---

## Code Samples

```bash
# Illustrative — adapt during implementation

# Unified issue-number extraction (replaces the two separate if/elif blocks)
ISSUE_NUMBER=""
BRANCH_TYPE=""
if [[ "$TO_DELETE" =~ ^(fix|feature|hotfix|refactor)/([0-9]+)($|-) ]]; then
  ISSUE_NUMBER="${BASH_REMATCH[2]}"
  BRANCH_TYPE="implementation"
elif [[ "$TO_DELETE" =~ ^(spec)/([0-9]+)($|-) ]]; then
  ISSUE_NUMBER="${BASH_REMATCH[2]}"
  BRANCH_TYPE="spec"
elif [[ "$TO_DELETE" =~ ^(implementation-plan)/([0-9]+)($|-) ]]; then
  ISSUE_NUMBER="${BASH_REMATCH[2]}"
  BRANCH_TYPE="plan"
fi

# update_tracker_status helper (illustrative — adapt during implementation)
update_tracker_status() {
  local issue_number="$1"
  local status_label="$2"
  local owner project_number project_id field_id option_id item_id

  # Resolve owner and project number
  owner="${GITHUB_PROJECT_OWNER:-$(gh repo view --json owner --jq '.owner.login' 2>/dev/null)}"
  project_number="${GITHUB_PROJECT_NUMBER:-}"
  if [ -z "$owner" ] || [ -z "$project_number" ]; then
    echo "Warning: GITHUB_PROJECT_OWNER or GITHUB_PROJECT_NUMBER not set; skipping tracker status update."
    return 0
  fi

  project_id=$(gh project view "$project_number" --owner "$owner" --format json 2>/dev/null | jq -r '.id // empty')
  if [ -z "$project_id" ]; then
    echo "Warning: could not resolve project ID for project #${project_number}; skipping tracker status update."
    return 0
  fi

  # Resolve Status field ID and option ID for the requested label
  field_json=$(gh project field-list "$project_number" --owner "$owner" --format json 2>/dev/null)
  field_id=$(echo "$field_json" | jq -r '.fields[] | select(.name == "Status") | .id // empty')
  option_id=$(echo "$field_json" | jq -r --arg label "$status_label" '.fields[] | select(.name == "Status") | .options[] | select(.name == $label) | .id // empty')
  if [ -z "$field_id" ] || [ -z "$option_id" ]; then
    echo "Warning: could not resolve Status field or option '${status_label}'; skipping tracker status update."
    return 0
  fi

  # Resolve project item ID for the issue
  item_id=$(gh project item-list "$project_number" --owner "$owner" --format json 2>/dev/null \
    | jq -r --argjson num "$issue_number" '.items[] | select(.content.number == $num) | .id // empty')
  if [ -z "$item_id" ]; then
    echo "Warning: issue #${issue_number} not found in project #${project_number}; skipping tracker status update."
    return 0
  fi

  echo "Updating tracker status for issue #${issue_number} to '${status_label}'..."
  gh api graphql -f query="
    mutation {
      updateProjectV2ItemFieldValue(input: {
        projectId: \"${project_id}\"
        itemId: \"${item_id}\"
        fieldId: \"${field_id}\"
        value: { singleSelectOptionId: \"${option_id}\" }
      }) {
        projectV2Item { id }
      }
    }
  " 2>/dev/null || echo "Warning: GraphQL mutation failed for issue #${issue_number}; tracker status not updated."
}
```

---

## Implementation Order

1. Read the current `scripts/development-workflow/post-merge-cleanup.sh` in full.
2. Replace the two-block `if/elif` issue-number detection (lines 85–92 in current file) with the unified three-branch block (`implementation` / `spec` / `plan`) that sets both `ISSUE_NUMBER` and `BRANCH_TYPE`.
3. Implement the `update_tracker_status` function (placed before the issue-number extraction block, after the `cd_workflow_repo_root` call and local variable declarations).
4. Update the issue-number action block below the extraction:
   - For `BRANCH_TYPE=spec` and `BRANCH_TYPE=plan`: emit one log line (issue stays open) and call `update_tracker_status`.
   - For `BRANCH_TYPE=implementation`: preserve the existing issue-close logic; after the close block, call `update_tracker_status "$ISSUE_NUMBER" "Merged"`.
   - For no issue number: emit the existing single log line (unchanged).
5. Update `docs/ai/development-workflow/integrations/github-projects.md` — "Post-Merge Cleanup" section.
6. Write the smoke test runbook at `docs/testing/workflow/184-post-merge-cleanup-log-and-tracker.smoke-test.md`.
7. Run `shellcheck scripts/development-workflow/post-merge-cleanup.sh` and fix any warnings.
8. Run markdown lint on changed `.md` files: `npx markdownlint-cli2 "docs/specs/developments/20260417203259_post-merge-cleanup-log-and-tracker/*.md" "docs/testing/workflow/184-post-merge-cleanup-log-and-tracker.smoke-test.md" "docs/ai/development-workflow/integrations/github-projects.md"`.
9. Update `CHANGELOG.md` under `[Unreleased]` with an entry for this fix.
10. Verify the main working tree is clean and all changes are committed to the implementation branch.

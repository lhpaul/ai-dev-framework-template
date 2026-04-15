# Batch Merge — Implementation Plan

**Spec**: [`1_batch-merge_specs.md`](./1_batch-merge_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/batch-merge.smoke-test.md`](../../../testing/workflow/batch-merge.smoke-test.md)

---

## Summary

**Approach**: Split the batch-merge feature into a deterministic shell script (`batch-merge.sh`) that handles PR discovery, merge ordering, local merge attempts on `develop`, and structured status output, paired with an agent-side protocol (`94-batch-merge-protocol.md`) that drives the readiness gate, human prompts, conflict classification/resolution, push and remote-branch cleanup, `post-merge-cleanup`, and summary output. Use local `git merge --no-ff` as the only merge path so each PR remains individually identifiable in `develop` and GitHub can recognize the PR as merged when the resulting `develop` history is pushed. Agent entry points (Claude Code command, Cursor command, Codex skill) all point to the same protocol.

**Estimated complexity**: M
**Rationale**: Medium because the shell script has moderate complexity (PR discovery via `gh`, merge ordering logic, conflict detection, cleanup integration) and the protocol requires careful orchestration of human interaction points, but there are no database, API, or frontend layers involved — just shell scripting and markdown protocol authoring.

**Dependencies**: None

---

## Layer-by-Layer Changes

### Scripts / Shell

- [ ] **`scripts/development-workflow/batch-merge.sh`** — New shell script that implements the deterministic merge pipeline:
  - Sources `workflow-lib.sh` for shared helpers (`require_gh`, `repo_slug`, `cd_workflow_repo_root`)
  - **PR discovery mode**: accepts either `--prs <num1,num2,...>` (explicit list) or auto-discovers PRs labeled `ready-for-human-review` targeting `develop` via `gh pr list`; when auto-discovery returns no candidates, emits a dedicated `DISCOVERY_RESULT=none` record so the protocol can exit cleanly with no side effects
  - **PR metadata collection**: for each candidate PR, fetches: number, title, branch name, base branch, labels, creation timestamp, and whether the PR modifies `CHANGELOG.md` (via `gh pr diff --name-only`); filters out any PR not targeting `develop`
  - **Merge ordering**: sorts PRs into two groups — non-CHANGELOG PRs first (by ascending PR number), then CHANGELOG PRs (by ascending PR number) — and outputs the ordered list
  - **Per-PR merge-attempt mode**: for one PR at a time:
    1. Ensures local `develop` is up to date (`git checkout develop && git pull --ff-only`)
    2. Fetches the PR head branch and attempts `git merge --no-ff --no-edit origin/<branch>`
    3. On clean merge: leaves the merge commit in the local `develop` branch and emits `MERGE_RESULT=clean`; the agent protocol owns the subsequent push, GitHub verification, remote-branch deletion, and `post-merge-cleanup` steps
    4. On conflict: outputs the list of conflicted files (via `git diff --name-only --diff-filter=U`) plus merge-base/head metadata, then exits with a dedicated conflict status code so the agent protocol can classify trivial vs non-trivial conflicts
    5. On failure before conflict classification: aborts the merge (`git merge --abort`), reports the error, and exits with a failure status
  - **Output format**: structured key-value lines consumable by the agent (e.g., `PR_NUMBER=123`, `MERGE_RESULT=clean`, `CONFLICTED_FILES=CHANGELOG.md,docs/foo.md`, `PR_READY_LABEL=true`)
  - The script processes one PR per invocation (called in a loop by the agent protocol). This keeps git state transitions deterministic and lets the protocol own human-interaction steps.

  *Maps to: AC 4 (merge ordering), AC 5 (merge requirements), AC 11 (post-merge-cleanup)*

### Protocols / Agent Docs

- [ ] **`docs/ai/development-workflow/protocols/94-batch-merge-protocol.md`** — New agent protocol that orchestrates the full batch-merge flow:
  - **Step 1: Discovery & candidate list** — invoke `batch-merge.sh` in discovery mode (or accept explicit PR numbers from the human), display the candidate summary table (PR number, title, branch, labels, readiness status); if the script reports no auto-discovered candidates, exit immediately with an informational message and no side effects. *Maps to: AC 1, AC 13*
  - **Step 2: Readiness gate** — for each candidate PR, check for `ready-for-human-review` label. Any PR missing the label triggers a warning; the agent asks the human to confirm include or skip. Record each decision. *Maps to: AC 3, AC 14*
  - **Step 3: Human confirmation** — display the final merge plan (ordered list of PRs that will be merged, any skipped PRs) and require explicit human approval before proceeding. *Maps to: AC 2*
  - **Step 4: Sequential merge loop** — for each PR in the approved order:
    1. Report "Merging PR #N: <title>..."
    2. Invoke `batch-merge.sh` to attempt the merge
    3. If clean: report `merged_clean`, proceed to next PR
    4. If conflicts detected: classify each conflicted file:
       - **CHANGELOG.md `[Unreleased]` section**: auto-resolve by reading both sides of the conflict markers, combining all unique entries (entries from the already-merged side first, then entries from the incoming PR), writing the resolved content, staging, and completing the merge commit. Report `merged_auto` with details of what was combined. *Maps to: AC 6*
       - **Documentation/protocol files** (files under `docs/`, `.cursor/`, `.codex/`): if changes are in non-overlapping line ranges, auto-resolve by accepting both changes. If overlapping, treat as non-trivial. *Maps to: AC 7*
       - **Non-trivial conflicts**: display the conflicting file paths and a short excerpt of the conflict markers. Ask the human to resolve in their editor and signal when done. After human signals, verify resolution (`git diff --check`), complete the merge, and report `merged_human`. If the human chooses to abort, run `git merge --abort` to return `develop` to pre-merge state, report `skipped_conflict`, and continue with remaining PRs. *Maps to: AC 8, AC 9, AC 10*
    5. After each successful merge (`merged_clean`, `merged_auto`, or `merged_human`): push `develop`, verify via `gh pr view` that GitHub now reports the PR as merged, delete the remote branch if it still exists, run the `post-merge-cleanup` flow for the merged branch, and report the cleanup result. Do not use `gh pr close` because the PR must remain a merged PR, not a closed-unmerged PR. *Maps to: AC 5, AC 11*
    6. At any point, if the human requests abort: stop processing remaining PRs, mark them `not_attempted`. *Maps to: AC 15*
  - **Step 5: Final summary** — display a structured summary table listing every candidate PR with its outcome code (`merged_clean`, `merged_auto`, `merged_human`, `skipped_not_ready`, `skipped_conflict`, `failed`, `not_attempted`). Include details of any auto-resolved conflicts. *Maps to: AC 12*
  - **Orchestrator-invoked mode**: a note that when called from the orchestrator (protocol 90), the same flow applies — the orchestrator passes the PR list, and the protocol still requires human confirmation at Step 3 and human resolution at Step 4. *Maps to: AC 14*

- [ ] **`docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`** — Update the portfolio orchestrator protocol so that when a parallel-safe batch reaches the human-merge stage, it can hand the eligible PR list to `94-batch-merge-protocol.md` instead of stopping at "wait for human merge". Document that the orchestrator prepares the batch, presents the plan, and still requires explicit human approval before any merge starts. *Maps to: Use Case 2, AC 14*

### Agent Entry Points

- [ ] **`.claude/commands/batch-merge.md`** — Claude Code `/batch-merge` command. Points to `94-batch-merge-protocol.md`. Allowed tools: `Bash(./scripts/development-workflow/batch-merge.sh:*)`, `Bash(./scripts/development-workflow/post-merge-cleanup.sh:*)`, `Bash(git:*)`, `Bash(gh:*)`, plus issue tracker MCP tools (same pattern as `post-merge-cleanup.md`). Accepts optional arguments: explicit PR numbers or no arguments for auto-discovery. *Maps to: AC 1, AC 13*

- [ ] **`.cursor/commands/batch-merge.md`** — Cursor command equivalent. Same content as the Claude Code command but with Cursor frontmatter format (no `allowed-tools`). *Maps to: AC 13*

- [ ] **`.codex/skills/batch-merge/SKILL.md`** — Codex skill. Same instructions, Codex frontmatter format. *Maps to: AC 13*

### Documentation Updates

- [ ] **`AGENTS.md`** — Add `batch-merge` row to the **Workflow Commands** table (between "Run reviewer loop (PR)" and "Advance One Item" or at the end of the workflow commands section) and to the **Maintenance Commands** table if appropriate. The row should list: `/batch-merge` for Claude Code, `/batch-merge` for Cursor, `batch-merge` skill for Codex.

- [ ] **`docs/ai/development-workflow/README.md`** — Add `batch-merge` to the workflow command tables and add a reference to `94-batch-merge-protocol.md` in the protocol/command reference sections.

- [ ] **`scripts/development-workflow/README.md`** — Add `batch-merge.sh` to the script listing with a brief description.

---

## Testing Strategy

**Test types**: Smoke (manual runbook)

**Key scenarios to test**:
1. Auto-discovery mode with ready PRs (AC 1, AC 2)
2. Auto-discovery mode with no ready PRs — exits cleanly (AC 13)
3. Explicit PR list mode (AC 1, AC 13)
4. PR missing `ready-for-human-review` label — warning and human decision (AC 3)
5. Merge ordering — non-CHANGELOG PRs first, then CHANGELOG PRs, each group by ascending PR number (AC 4)
6. Clean merge — no conflicts (AC 5)
7. CHANGELOG conflict auto-resolution — entries combined, none dropped (AC 6)
8. Documentation file conflict auto-resolution — non-overlapping changes (AC 7)
9. Non-trivial conflict — pause, display conflict markers, human resolves (AC 8, AC 9)
10. Non-trivial conflict — human aborts, develop returned to pre-merge state (AC 10)
11. Post-merge cleanup runs after each successful merge (AC 11)
12. Final summary with all outcome codes (AC 12)
13. Abort entire batch mid-run — already-merged PRs stay, remaining marked `not_attempted` (AC 15)
14. Orchestrator-invoked mode — human confirmation still required (AC 14)
15. Post-push verification — after each successful local merge, GitHub shows the PR as merged (not closed-unmerged) before cleanup proceeds (AC 5)

**Smoke test runbook**: [`docs/testing/workflow/batch-merge.smoke-test.md`](../../../testing/workflow/batch-merge.smoke-test.md)

---

## Seed Data

No database seed data required. Testing requires:

| Entity | Values / Scenario | File |
|---|---|---|
| Test PRs | 2-3 open PRs targeting `develop` with `ready-for-human-review` label, at least one modifying `CHANGELOG.md` | Created manually in the test repository |
| Test PR (no label) | 1 open PR targeting `develop` without `ready-for-human-review` label | Created manually in the test repository |
| Orchestrator batch context | A batch of PRs identified by protocol 90 as ready for merge handoff | Created manually in the test repository / orchestration state |

---

## Documentation Updates

- [ ] `AGENTS.md` — Add `batch-merge` to the Workflow Commands table and Maintenance Commands table
- [ ] `docs/ai/development-workflow/README.md` — Add `batch-merge` to the workflow command tables and reference `94-batch-merge-protocol.md`
- [ ] `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` — Add the batch-merge handoff step for merge-ready batches
- [ ] `scripts/development-workflow/README.md` — Add `batch-merge.sh` to the script listing

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| GitHub may not mark a PR as merged immediately after pushing the local merge commit | Low | Med | Protocol verifies merged state with `gh pr view` before deleting the remote branch or starting cleanup; if GitHub has not recognized the merge yet, report `failed` and stop cleanup for that PR. |
| CHANGELOG auto-resolution produces incorrect merge (duplicate entries, wrong ordering) | Low | Med | Agent reads both sides of conflict markers carefully; combined entries are always reported to the human for verification in the summary. |
| `develop` left in conflicted state after unexpected failure | Low | High | Every conflict-detection path includes `git merge --abort` fallback. Protocol explicitly requires `develop` to never be left in conflicted state. |
| `post-merge-cleanup.sh` fails for a merged PR | Low | Low | Failure is reported but does not halt remaining merges (per spec). Human can re-run cleanup manually. |
| Race condition: another merge to `develop` between our merges | Low | Med | Each merge iteration does `git pull --ff-only` before attempting the next merge, ensuring the local `develop` is current. |

---

## Implementation Order

1. **Create `scripts/development-workflow/batch-merge.sh`** — implement PR discovery (auto + explicit), metadata collection, merge ordering logic, single-PR merge execution (with conflict detection), and structured output. Source `workflow-lib.sh`. Make executable.

2. **Create `docs/ai/development-workflow/protocols/94-batch-merge-protocol.md`** — write the full agent protocol covering: discovery/candidate list, readiness gate, human confirmation, sequential merge loop with conflict classification (CHANGELOG auto-resolution, doc file auto-resolution, non-trivial escalation), abort handling, post-merge cleanup invocation, and final summary output.

3. **Create `.claude/commands/batch-merge.md`** — Claude Code command pointing to the protocol with appropriate `allowed-tools` and description.

4. **Create `.cursor/commands/batch-merge.md`** — Cursor command equivalent.

5. **Create `.codex/skills/batch-merge/SKILL.md`** — Codex skill equivalent.

6. **Update `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`** — add the batch-merge handoff step for merge-ready parallel batches so Use Case 2 is implemented, not just mentioned.

7. **Update `AGENTS.md`** — add batch-merge row to the Workflow Commands table.

8. **Update `docs/ai/development-workflow/README.md`** — add the new command and reference to `94-batch-merge-protocol.md`.

9. **Update `scripts/development-workflow/README.md`** — add `batch-merge.sh` to the script listing.

10. **Verify smoke test runbook** — walk through the runbook to confirm all scenarios, including orchestrator handoff and GitHub merged-state verification, are testable with the implemented code.

11. **Update CHANGELOG** — add entry under `[Unreleased]` for the batch-merge feature.

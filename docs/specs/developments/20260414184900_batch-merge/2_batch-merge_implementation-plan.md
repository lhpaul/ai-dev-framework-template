# Batch Merge — Implementation Plan

**Spec**: [`1_batch-merge_specs.md`](./1_batch-merge_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/batch-merge.smoke-test.md`](../../../testing/workflow/batch-merge.smoke-test.md)

---

## Summary

**Approach**: Split the batch-merge feature into a deterministic shell script (`batch-merge.sh`) that handles PR discovery, merge ordering, invoking git merges, and calling `post-merge-cleanup`, paired with an agent-side protocol (`94-batch-merge-protocol.md`) that drives the readiness gate, human prompts, conflict classification/resolution, abort handling, and summary output. The shell script performs clean merges directly and delegates to the agent when conflicts are detected. Agent entry points (Claude Code command, Cursor command, Codex skill) all point to the same protocol.

**Estimated complexity**: M
**Rationale**: Medium because the shell script has moderate complexity (PR discovery via `gh`, merge ordering logic, conflict detection, cleanup integration) and the protocol requires careful orchestration of human interaction points, but there are no database, API, or frontend layers involved — just shell scripting and markdown protocol authoring.

**Dependencies**: None

---

## Layer-by-Layer Changes

### Scripts / Shell

- [ ] **`scripts/development-workflow/batch-merge.sh`** — New shell script that implements the deterministic merge pipeline:
  - Sources `workflow-lib.sh` for shared helpers (`require_gh`, `repo_slug`, `cd_workflow_repo_root`)
  - **PR discovery mode**: accepts either `--prs <num1,num2,...>` (explicit list) or auto-discovers PRs labeled `ready-for-human-review` targeting `develop` via `gh pr list`
  - **PR metadata collection**: for each candidate PR, fetches: number, title, branch name, labels, and whether the PR modifies `CHANGELOG.md` (via `gh pr diff --name-only`)
  - **Merge ordering**: sorts PRs into two groups — non-CHANGELOG PRs first (by ascending PR number), then CHANGELOG PRs (by ascending PR number) — and outputs the ordered list
  - **Per-PR merge execution**: for each PR in order:
    1. Ensures local `develop` is up to date (`git checkout develop && git pull --ff-only`)
    2. Attempts `git merge --no-ff --no-edit origin/<branch>` (fetching the branch first)
    3. On clean merge: pushes `develop` to origin, closes the PR via `gh pr close <number> --comment "Merged via batch-merge into develop"`, deletes the remote branch via `gh api -X DELETE repos/{owner}/{repo}/git/refs/heads/<branch>`, then invokes `post-merge-cleanup.sh <branch>`
    4. On conflict: outputs the list of conflicted files (via `git diff --name-only --diff-filter=U`) and exits with a special status code (e.g., exit 10) so the agent protocol can take over for conflict classification and resolution
    5. On failure: aborts the merge (`git merge --abort`), reports the error, and exits with a failure status
  - **Output format**: structured key-value lines consumable by the agent (e.g., `PR_NUMBER=123`, `MERGE_RESULT=clean`, `CONFLICTED_FILES=CHANGELOG.md,docs/foo.md`)
  - The script processes one PR per invocation (called in a loop by the agent protocol). This keeps the script simple and lets the agent control flow between PRs.
  - **Decision to finalize during implementation**: The plan calls for local `git merge` + push + `gh pr close` as the primary approach. During implementation, also test whether `gh pr merge --merge` can work for clean merges (it is simpler but may not allow conflict resolution). If `gh pr merge --merge` works reliably for clean merges, use it for those cases and fall back to local merge only when conflicts are detected. Document the final decision in the script comments.

  *Maps to: AC 4 (merge ordering), AC 5 (merge requirements), AC 11 (post-merge-cleanup)*

### Protocols / Agent Docs

- [ ] **`docs/ai/development-workflow/protocols/94-batch-merge-protocol.md`** — New agent protocol that orchestrates the full batch-merge flow:
  - **Step 1: Discovery & candidate list** — invoke `batch-merge.sh` in discovery mode (or accept explicit PR numbers from the human), display the candidate summary table (PR number, title, branch, labels, readiness status)
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
    5. After each successful merge: push `develop`, close the PR, delete the remote branch, run `post-merge-cleanup.sh <branch>`, and report the cleanup result. *Maps to: AC 11*
    6. At any point, if the human requests abort: stop processing remaining PRs, mark them `not_attempted`. *Maps to: AC 15*
  - **Step 5: Final summary** — display a structured summary table listing every candidate PR with its outcome code (`merged_clean`, `merged_auto`, `merged_human`, `skipped_not_ready`, `skipped_conflict`, `failed`, `not_attempted`). Include details of any auto-resolved conflicts. *Maps to: AC 12*
  - **Orchestrator-invoked mode**: a note that when called from the orchestrator (protocol 90), the same flow applies — the orchestrator passes the PR list, and the protocol still requires human confirmation at Step 3 and human resolution at Step 4. *Maps to: AC 14*

### Agent Entry Points

- [ ] **`.claude/commands/batch-merge.md`** — Claude Code `/batch-merge` command. Points to `94-batch-merge-protocol.md`. Allowed tools: `Bash(./scripts/development-workflow/batch-merge.sh:*)`, `Bash(./scripts/development-workflow/post-merge-cleanup.sh:*)`, `Bash(git:*)`, `Bash(gh:*)`, plus issue tracker MCP tools (same pattern as `post-merge-cleanup.md`). Accepts optional arguments: explicit PR numbers or no arguments for auto-discovery. *Maps to: AC 1, AC 13*

- [ ] **`.cursor/commands/batch-merge.md`** — Cursor command equivalent. Same content as the Claude Code command but with Cursor frontmatter format (no `allowed-tools`). *Maps to: AC 13*

- [ ] **`.codex/skills/batch-merge/SKILL.md`** — Codex skill. Same instructions, Codex frontmatter format. *Maps to: AC 13*

### Documentation Updates

- [ ] **`AGENTS.md`** — Add `batch-merge` row to the **Workflow Commands** table (between "Run reviewer loop (PR)" and "Advance One Item" or at the end of the workflow commands section) and to the **Maintenance Commands** table if appropriate. The row should list: `/batch-merge` for Claude Code, `/batch-merge` for Cursor, `batch-merge` skill for Codex.

- [ ] **`docs/ai/development-workflow/README.md`** — If the README has a protocol listing or table of contents, add a reference to `94-batch-merge-protocol.md`.

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

**Smoke test runbook**: [`docs/testing/workflow/batch-merge.smoke-test.md`](../../testing/workflow/batch-merge.smoke-test.md)

---

## Seed Data

No database seed data required. Testing requires:

| Entity | Values / Scenario | File |
|---|---|---|
| Test PRs | 2-3 open PRs targeting `develop` with `ready-for-human-review` label, at least one modifying `CHANGELOG.md` | Created manually in the test repository |
| Test PR (no label) | 1 open PR targeting `develop` without `ready-for-human-review` label | Created manually in the test repository |

---

## Documentation Updates

- [ ] `AGENTS.md` — Add `batch-merge` to the Workflow Commands table and Maintenance Commands table
- [ ] `docs/ai/development-workflow/README.md` — Add reference to `94-batch-merge-protocol.md` in the protocol listing (if one exists)
- [ ] `scripts/development-workflow/README.md` — Add `batch-merge.sh` to the script listing

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `gh pr merge --merge` may not support all needed scenarios (e.g., conflict detection) | Med | Low | Plan includes fallback to local `git merge` + push + `gh pr close`. Test both approaches during implementation. |
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

6. **Update `AGENTS.md`** — add batch-merge row to the Workflow Commands table.

7. **Update `docs/ai/development-workflow/README.md`** — add reference to `94-batch-merge-protocol.md`.

8. **Update `scripts/development-workflow/README.md`** — add `batch-merge.sh` to the script listing.

9. **Verify smoke test runbook** — walk through the runbook to confirm all scenarios are testable with the implemented code.

10. **Update CHANGELOG** — add entry under `[Unreleased]` for the batch-merge feature.

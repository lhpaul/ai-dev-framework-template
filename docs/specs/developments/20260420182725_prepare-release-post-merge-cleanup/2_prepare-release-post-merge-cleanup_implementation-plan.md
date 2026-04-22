# Prepare release post-merge cleanup — Implementation Plan

**Spec**: [`1_prepare-release-post-merge-cleanup_specs.md`](./1_prepare-release-post-merge-cleanup_specs.md)  
**Smoke test runbook**: [`docs/testing/workflow/232-prepare-release-post-merge-cleanup.smoke-test.md`](../../../testing/workflow/232-prepare-release-post-merge-cleanup.smoke-test.md)

---

## Summary

**Approach**: Extend `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md` with an explicit post-merge sequence (after both the `main` release PR and the `develop` backport PR are merged): verify merge state with `gh`, delete `release/vX.Y.Z` on `origin`, delete the local release branch when safe, then transition scoped tracker items from the integration-merged status to the shipped terminal status using the same GitHub Projects v2 GraphQL patterns as `scripts/development-workflow/post-merge-cleanup.sh` (`gh project field-list`, `gh project item-list`, `gh api graphql` mutation). Implement a dedicated helper script (e.g. `scripts/development-workflow/prepare-release-post-merge-cleanup.sh`) so operators and agents run one audited entry point instead of ad hoc commands; the script sources shared helpers from `workflow-lib.sh` where practical and logs skip reasons when project env vars are missing.

**Estimated complexity**: **M**  
**Rationale**: Touches protocol docs, a new script with git and GitHub edge cases, configuration surface for status labels, and must stay aligned with existing `update_tracker_status` ordering / rollback rules — more than a single-file tweak, but no application runtime.

**Dependencies**: None (spec **Depends on**: none).

---

## Layer-by-Layer Changes

### Database / Data Layer

- [ ] Not applicable.

### Backend / API

- [ ] Not applicable.

### Shared Packages / Libraries

- [ ] Not applicable.

### Frontend / UI

- [ ] Not applicable.

### Infrastructure / Configuration

- [ ] Optional: document advisory keys under `.ai-dev-workflow.yaml` (e.g. `issue_tracker.status_labels.released`) **or** environment variables only (`GITHUB_PROJECT_STATUS_MERGED`, `GITHUB_PROJECT_STATUS_RELEASED`) — pick one primary mechanism in implementation and reference the other as override; must not require secrets in repo files.
- [ ] Reuse existing `GITHUB_PROJECT_OWNER` / `GITHUB_PROJECT_NUMBER` contract from `post-merge-cleanup.sh` / `docs/workflow/development-workflow/integrations/github-projects.md`.

### Documentation / Workflow

- [ ] **`docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`**: Replace or extend current Step 8 (“Inform the Human”) so it clearly separates (a) pre-merge handoff from (b) post-merge cleanup. Add numbered substeps: confirm both PRs merged via `gh pr view` or `gh pr list` queries; **do not** delete the branch if either PR is open or only one merged (**AC**: one-PR-merged edge case). Document `git push origin --delete release/vX.Y.Z` and local `git branch -d` / `switch` away if branch checked out (**UC1**, **AC**).
- [ ] Same protocol: document tracker transition (**UC2**, **AC**): only items explicitly in scope for this release (default per spec open question: not a blind “all Merged in project” bulk unless human opts in); reference the new script’s flags (e.g. explicit issue numbers, or allowlisted query) in prose.
- [ ] **`docs/workflow/development-workflow/integrations/github-projects.md`**: Add configuration for shipped status display name / option resolution (parallel to how `Merged` is discovered today).
- [ ] **Command wrappers** (`.cursor/commands/prepare-release.md`, `.claude/commands/prepare-release.md`): One-line note that post-merge cleanup is defined in protocol Step 9 (or whatever final numbering is) so humans do not assume the command ends at PR merge.

### Scripts

- [ ] **`scripts/development-workflow/prepare-release-post-merge-cleanup.sh`** (name illustrative — adapt during implementation):  
  - Arguments: release version `X.Y.Z` or `vX.Y.Z` normalized to `release/vX.Y.Z`.  
  - Preconditions: both PRs from that head merged (`main` and `develop` targets) — exit non-zero with clear message if not (**BR**: branch deletion only after both merged).  
  - Remote delete: `git push origin --delete release/vX.Y.Z` with error handling if already absent (log and success exit 0 or distinct code — document choice).  
  - Local delete: `git branch -d release/vX.Y.Z` when ref exists; if “checked out” error, print remediation from spec (**UC1** considerations).  
  - Tracker: for each issue in scope, call shared logic equivalent to `update_tracker_status` in `post-merge-cleanup.sh` but targeting the **Released** option (or configured name). Respect rollback-prevention (do not move from a status more advanced than target).  
  - Logging: each major action emits one clear line (**Operational visibility**).
- [ ] **Refactor consideration**: extract `update_tracker_status` from `post-merge-cleanup.sh` into `workflow-lib.sh` if duplication would otherwise copy the GraphQL mutation; keep `post-merge-cleanup.sh` behavior unchanged for existing callers (**AC** same class of mechanism).

---

## Testing Strategy

**Test types**: ShellCheck on new/changed scripts, manual smoke per runbook, optional lightweight `bats` or script self-test only if the repo already uses them for workflow scripts (do not introduce a new framework unless already present).

**Key scenarios to test**:

1. Both PRs merged → remote branch deleted; script exits 0 (**AC** / **UC1**).
2. Only production PR merged → script refuses branch delete (**AC** edge case).
3. Tracker configured → in-scope issue moves `Merged` → `Released`; out-of-scope issue unchanged (**UC2**).
4. Missing `GITHUB_PROJECT_NUMBER` → script completes git cleanup and warns on tracker skip (**Operational visibility**).

**Smoke test runbook**: [`docs/testing/workflow/232-prepare-release-post-merge-cleanup.smoke-test.md`](../../../testing/workflow/232-prepare-release-post-merge-cleanup.smoke-test.md)

**Regression suite**: If a CI job runs ShellCheck on `scripts/development-workflow/`, ensure new script is included by existing glob; no separate e2e unless already standard for workflow scripts.

---

## Seed Data

| Entity | Values / Scenario | File |
|---|---|---|
| Not applicable | No database seed; use real or sandbox GitHub project for optional tracker steps | — |

---

## Documentation Updates

Post-implementation edits (not done in this plan PR):

- [ ] `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md` — add post-merge branch + tracker sequence; renumber steps if needed.
- [ ] `docs/workflow/development-workflow/integrations/github-projects.md` — document `Released` / configurable status and any new env vars.
- [ ] `.cursor/commands/prepare-release.md` and `.claude/commands/prepare-release.md` — pointer to post-merge section after merge.
- [ ] `docs/workflow/development-workflow/README.md` — only if the master workflow table needs a one-line note that release completes with post-merge cleanup (optional if protocol cross-link is enough).
- [ ] `CHANGELOG.md` — under `[Unreleased]` when the **implementation** PR merges (not this plan PR), per repo changelog rules.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Bulk transition moves wrong issues | Med | High | Default to explicit issue list or human-confirmed input; document dangerous vs safe modes; never auto-select “all Merged” without opt-in flag. |
| Branch delete while backport pending | Low | High | Hard gate in script + protocol: query both PR merge state before any `git push --delete`. |
| Divergence from `post-merge-cleanup.sh` mutation | Med | Med | Share one helper for GraphQL update; add ShellCheck and a short comment block pointing to protocol. |
| Local branch checked out | Med | Low | Document `git switch develop` then retry; script prints exact commands. |

---

## Code Samples

> No executable code samples in this plan — behavior is described at shell command level in protocol steps; any snippet in the implementation PR must be marked **Illustrative** per `REVIEW.md`.

---

## Implementation Order

1. Read `post-merge-cleanup.sh` and `workflow-lib.sh`; decide extract-vs-duplicate for `update_tracker_status`.
2. Implement `prepare-release-post-merge-cleanup.sh` with merge verification, branch deletion, and scoped tracker transitions.
3. Run ShellCheck locally / fix warnings.
4. Update `05-prepare-release-protocol.md` with post-merge section aligned to script capabilities.
5. Update `github-projects.md` and thin command wrappers.
6. Execute smoke test runbook (dry protocol review before script lands; full run after).
7. Add `[Unreleased]` CHANGELOG entry in the **implementation** PR.
8. Open implementation PR from `feature/232-…` or `fix/232-…` per repo conventions (follow implementation protocol when plan is merged).

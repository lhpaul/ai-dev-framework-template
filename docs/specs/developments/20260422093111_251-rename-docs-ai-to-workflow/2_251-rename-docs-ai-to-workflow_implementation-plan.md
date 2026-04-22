# Rename docs/ai/ to docs/workflow/ — Implementation Plan

**Issue**: #251
**Smoke test runbook**: `docs/testing/workflow/251-rename-docs-ai-to-workflow.smoke-test.md`

---

## Summary

**Approach**: Rename the `docs/ai/` directory tree to `docs/workflow/` and update every cross-reference in the repository — across agent definitions, Cursor/Codex wrappers, scripts, protocol files, AGENTS.md, README.md, REVIEW.md, CHANGELOG.md, and the sync-template command — to point to `docs/workflow/`. The rename itself is performed with `git mv`; all cross-reference updates are pure text substitutions with no content changes. The sync-template command and `workflow-batch-plan.sh` script contain hardcoded `docs/ai/` path literals that must be updated so the tooling continues to work correctly.

**Estimated complexity**: M
**Rationale**: Large surface area (388 cross-reference occurrences across ~100 tracked files) but changes are entirely mechanical text substitutions. No logic changes. Some care required to update the sync-template command's "always-sync" path list and to update spec/plan/smoke-test historical archive files that reference the old path.

**Dependencies**: None

---

## Verification Log

| Check | Command / query | Result |
|---|---|---|
| Repo revision | `git rev-parse --short HEAD` (in main repo) | `a3ea49c` |
| Files with `docs/ai/` refs (excl. `.claude/worktrees/` and `.git/`) | `find . -type f \( -name "*.md" -o -name "*.mdc" -o -name "*.yaml" -o -name "*.yml" -o -name "*.sh" -o -name "*.json" \) -not -path "./.git/*" -not -path "./.claude/worktrees/*" -print0 \| xargs -0 grep -l "docs/ai/" \| wc -l` | 131 files |
| Total `docs/ai/` occurrences (excl. `.claude/worktrees/` and `.git/`) | same `find` pipeline with `-c` and `awk` sum | 430 occurrences |
| Files with `docs/ai/` refs (non-docs/ai, non-specs, non-testing, non-codex, non-cursor) | filtered grep | 30 files (root + scripts) |
| Hardcoded `docs/ai/` literals in scripts | `grep -rn "docs/ai/" scripts/ --include="*.sh"` | 4 occurrences in 2 files: `workflow-batch-plan.sh` (line 45 + comment line 90), `add-backlog-item.sh` (lines 108 + 113) |
| `sync-template` command path list | grep in `.claude/commands/sync-template.md` and `.claude/skills/sync-template.md` | Both list `docs/ai/` in "always-sync" and in commit example |
| `docs/ai/` subtree structure | `ls docs/ai/` | `development-workflow/`, `setup/`, plus no top-level files in `docs/ai/` itself |

---

## Layer-by-Layer Changes

### Infrastructure / Configuration (directory rename)

- [ ] Rename `docs/ai/` → `docs/workflow/` using `git mv docs/ai docs/workflow`

### Cross-reference updates (text substitution: `docs/ai/` → `docs/workflow/`)

All substitutions replace the literal string `docs/ai/` with `docs/workflow/` (and `docs/ai` with `docs/workflow` where paths appear without a trailing slash). No content changes.

#### Agent definitions

- [ ] `.claude/agents/automated-reviewer-loop.md`
- [ ] `.claude/agents/code-reviewer.md`
- [ ] `.claude/agents/developer.md`
- [ ] `.claude/agents/implementation-plan-reviewer.md`
- [ ] `.claude/agents/item-orchestrator.md`
- [ ] `.claude/agents/orchestrator.md`
- [ ] `.claude/agents/product-manager.md`
- [ ] `.claude/agents/project-setup.md`
- [ ] `.claude/agents/retrospective.md`
- [ ] `.claude/agents/smoke-tester.md`
- [ ] `.claude/agents/spec-reviewer.md`
- [ ] `.claude/agents/tech-lead.md`

#### Claude Code commands and skills

- [ ] `.claude/commands/add-backlog-item.md`
- [ ] `.claude/commands/batch-merge.md`
- [ ] `.claude/commands/post-merge-cleanup.md`
- [ ] `.claude/commands/prepare-release.md`
- [ ] `.claude/commands/retrospective.md`
- [ ] `.claude/commands/run-item-work.md`
- [ ] `.claude/commands/run-reviewer-loop.md`
- [ ] `.claude/commands/run-work.md`
- [ ] `.claude/commands/sync-template.md` — also update the "always-sync" path list entry (`docs/ai/` → `docs/workflow/`) and the example commit/add commands
- [ ] `.claude/skills/post-merge-cleanup.md`
- [ ] `.claude/skills/sync-template.md` — same two-part update as the command equivalent

#### Codex skills

- [ ] `.codex/skills/batch-merge/SKILL.md`
- [ ] `.codex/skills/post-merge-cleanup/SKILL.md`
- [ ] `.codex/skills/workflow-code-reviewer/SKILL.md`
- [ ] `.codex/skills/workflow-implementer/SKILL.md`
- [ ] `.codex/skills/workflow-item-orchestrator/SKILL.md`
- [ ] `.codex/skills/workflow-orchestrator/SKILL.md`
- [ ] `.codex/skills/workflow-plan-reviewer/SKILL.md`
- [ ] `.codex/skills/workflow-plan-writer/SKILL.md`
- [ ] `.codex/skills/workflow-project-setup/SKILL.md`
- [ ] `.codex/skills/workflow-retrospective/SKILL.md`
- [ ] `.codex/skills/workflow-reviewer-loop/SKILL.md`
- [ ] `.codex/skills/workflow-spec-reviewer/SKILL.md`
- [ ] `.codex/skills/workflow-spec-writer/SKILL.md`

#### Cursor agents, commands, and rules

- [ ] `.cursor/agents/automated-reviewer-loop.md`
- [ ] `.cursor/agents/code-reviewer.md`
- [ ] `.cursor/agents/developer.md`
- [ ] `.cursor/agents/implementation-plan-reviewer.md`
- [ ] `.cursor/agents/item-orchestrator.md`
- [ ] `.cursor/agents/orchestrator.md`
- [ ] `.cursor/agents/product-manager.md`
- [ ] `.cursor/agents/project-setup.md`
- [ ] `.cursor/agents/retrospective.md`
- [ ] `.cursor/agents/smoke-tester.md`
- [ ] `.cursor/agents/spec-reviewer.md`
- [ ] `.cursor/agents/tech-lead.md`
- [ ] `.cursor/commands/add-backlog-item.md`
- [ ] `.cursor/commands/batch-merge.md`
- [ ] `.cursor/commands/generate-implementation-plan.md`
- [ ] `.cursor/commands/generate-new-feature.md`
- [ ] `.cursor/commands/implement-development.md`
- [ ] `.cursor/commands/post-merge-cleanup.md`
- [ ] `.cursor/commands/prepare-release.md`
- [ ] `.cursor/commands/retrospective.md`
- [ ] `.cursor/commands/review-code.md`
- [ ] `.cursor/commands/review-implementation-plan.md`
- [ ] `.cursor/commands/review-spec.md`
- [ ] `.cursor/commands/run-item-work.md`
- [ ] `.cursor/commands/run-reviewer-loop.md`
- [ ] `.cursor/commands/run-work.md`
- [ ] `.cursor/commands/setup-project.md`
- [ ] `.cursor/commands/sync-template.md`
- [ ] `.cursor/rules/workflow.mdc` — 7 `docs/ai/` references (workflow README + 5 protocol links + review-wrappers note)
- [ ] `.cursor/rules/documentation.mdc` — 1 `docs/ai/` reference (directory description table)

#### Root documentation

- [ ] `AGENTS.md` — update all `docs/ai/` path references and the `docs/ai/development-workflow/` directory description
- [ ] `README.md` — update all `docs/ai/` path references and the directory listing entry `docs/ai/`
- [ ] `REVIEW.md` — update `docs/ai/development-workflow/protocols/` references
- [ ] `CHANGELOG.md` — update historical `docs/ai/` path references (pure archive update; no version changes)
- [ ] `.ai-dev-workflow.yaml` — update any comment references to `docs/ai/`

#### docs/ subdirectories (cross-references only — not the renamed tree itself)

- [ ] `docs/README.md`
- [ ] `docs/best-practices/STACK-SPECIFIC.md`
- [ ] `docs/project/1-business-domain.md`
- [ ] `docs/project/2-repo-architecture.md`
- [ ] `docs/project/3-software-architecture.md`
- [ ] `docs/project/4-database-model.md`

#### Scripts

- [ ] `scripts/development-workflow/README.md`
- [ ] `scripts/development-workflow/add-backlog-item.sh` — update 2 path literals (lines 108 and 113)
- [ ] `scripts/development-workflow/workflow-batch-plan.sh` — update `PROTOCOLS_PREFIX` variable (line 45) and comment (line 90)

#### docs/specs and docs/testing historical archive

- [ ] All `*.md` files under `docs/specs/developments/` that contain `docs/ai/` references — **excluding** `docs/specs/developments/20260422093111_251-rename-docs-ai-to-workflow/` (this plan file itself uses `docs/ai/` as subject matter describing the rename)
- [ ] All `*.md` files under `docs/testing/workflow/` that contain `docs/ai/` references — **excluding** `docs/testing/workflow/251-rename-docs-ai-to-workflow.smoke-test.md` (uses `docs/ai/` as subject matter in verification steps)

#### docs/workflow/ internal self-references

After the rename, the protocol and README files that previously lived under `docs/ai/development-workflow/` and referenced each other via relative or absolute paths containing `docs/ai/` must also be updated. These are the files in the renamed tree itself:

- [ ] All `*.md` files under `docs/workflow/development-workflow/` that contain `docs/ai/` references
- [ ] `docs/workflow/setup/protocol.md` (if it contains `docs/ai/` self-references)

---

## Testing Strategy

**Test types**: Smoke (manual verification)

**Key scenarios to test**:

1. Directory exists at `docs/workflow/` with full subtree intact — maps to goal of rename
2. `docs/ai/` no longer exists at the repo root
3. Cross-references in agent definitions, commands, and scripts resolve to valid paths
4. `workflow-batch-plan.sh` can be invoked and correctly constructs protocol file paths using the new `docs/workflow/development-workflow/protocols/` prefix
5. `sync-template` command's "always-sync" list shows `docs/workflow/` not `docs/ai/`
6. `find . -type f \( -name "*.md" -o -name "*.mdc" -o -name "*.yaml" -o -name "*.yml" -o -name "*.sh" -o -name "*.json" \) -not -path "./.git/*" -not -path "./.claude/worktrees/*" -not -path "./docs/specs/developments/20260422093111_251-rename-docs-ai-to-workflow/*" -not -path "./docs/testing/workflow/251-rename-docs-ai-to-workflow.smoke-test.md" -print0 | xargs -0 grep -l "docs/ai/"` returns no matches (zero residual references outside of the self-referencing plan/smoke-test files for this issue)

**Smoke test runbook**: `docs/testing/workflow/251-rename-docs-ai-to-workflow.smoke-test.md`

---

## Seed Data

None — this is a pure structural refactor with no runtime data.

---

## Documentation Updates

- [ ] `AGENTS.md` — the directory description in the "Repository Structure" section refers to `docs/ai/`; update to `docs/workflow/`
- [ ] `README.md` — same directory listing and prose references
- [ ] `docs/workflow/development-workflow/README.md` — update any internal `docs/ai/` self-references after the rename

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Missed reference (residual `docs/ai/` after rename) | Medium | Medium | Run the `find` command from Implementation Order step 5 (includes self-referencing exclusions) after all substitutions and verify zero output |
| `workflow-batch-plan.sh` breaks at runtime | Low | High | PROTOCOLS_PREFIX variable is the single point to update; verify script can list protocol files from the new path |
| `sync-template` sync list out of date | Low | Medium | Both `.claude/commands/sync-template.md` and `.claude/skills/sync-template.md` have their always-sync path list updated as part of this work |
| Historical docs/specs files out of sync | Low | Low | Archive files are informational only; update them for consistency but no tooling depends on their paths |

---

## Code Samples

None — all changes are `git mv` and `sed`-style text substitutions.

---

## Implementation Order

1. **Fetch and verify baseline**: run `git fetch origin && git status` to confirm clean worktree on `refactor/251-rename-docs-ai-to-workflow` (from `develop`).
2. **Rename the directory**: `git mv docs/ai docs/workflow` — this moves the entire subtree and stages the rename for commit.
3. **Update cross-references in all non-docs/workflow files**: use a global search-and-replace of `docs/ai/` → `docs/workflow/` (and `docs/ai` → `docs/workflow` where the trailing slash is absent) across all tracked files listed in the Layer-by-Layer section above. Do not modify files under `.claude/worktrees/` or `.git/`. **Exception**: do NOT substitute inside `docs/specs/developments/20260422093111_251-rename-docs-ai-to-workflow/` or `docs/testing/workflow/251-rename-docs-ai-to-workflow.smoke-test.md` — these two files use `docs/ai/` as subject matter describing the rename and must keep those references unchanged.
4. **Update internal self-references inside the renamed tree**: run the same substitution for `*.md` files under `docs/workflow/` that still reference the old `docs/ai/` path.
5. **Verify zero residual references**: run `find . -type f \( -name "*.md" -o -name "*.mdc" -o -name "*.yaml" -o -name "*.yml" -o -name "*.sh" -o -name "*.json" \) -not -path "./.git/*" -not -path "./.claude/worktrees/*" -not -path "./docs/specs/developments/20260422093111_251-rename-docs-ai-to-workflow/*" -not -path "./docs/testing/workflow/251-rename-docs-ai-to-workflow.smoke-test.md" -print0 | xargs -0 grep -n "docs/ai/"` and confirm empty output. If any remain, fix them. (The two excluded paths are self-referencing subject-matter files for this issue.)
6. **Verify directory structure**: confirm `docs/workflow/development-workflow/`, `docs/workflow/setup/` exist and `docs/ai/` is gone.
7. **Verify scripts work**: `bash -n scripts/development-workflow/workflow-batch-plan.sh` (syntax check); confirm `PROTOCOLS_PREFIX` variable now reads `docs/workflow/development-workflow/protocols/`.
8. **Commit**: `refactor: rename docs/ai/ to docs/workflow/ (#251)`
9. **Push and open draft PR**: targeting `develop`.
10. **Update `CHANGELOG.md`** under `[Unreleased]`:
    ```
    - **Rename docs/ai/ to docs/workflow/** (#251): renamed the `docs/ai/` directory to `docs/workflow/` to clarify framework ownership. Updated all cross-references across agent definitions, Cursor/Codex wrappers, scripts, protocol files, and root documentation. No content changes — pure structural refactor.
    ```

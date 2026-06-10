# Workflow Hub and Product Repository Template Skeletons - Implementation Plan

**Spec**: [1_876-workflow-hub-template-skeletons_specs.md](1_876-workflow-hub-template-skeletons_specs.md)
**Smoke test runbook**: [876-workflow-hub-template-skeletons.smoke-test.md](../../../testing/workflow/876-workflow-hub-template-skeletons.smoke-test.md)

---

## Summary

**Approach**: Add role-specific, inspectable template skeleton directories under
`template/workflow-hub/` and `template/product-repo-injection/` using README
guidance plus skeleton manifests that reference canonical source paths. Extend
`sync-manifest.yaml` with non-breaking mode-scope metadata so files can be
classified as `shared`, `hub_only`, or `product_repo_injection` without changing
the current sync command behavior.

**Estimated complexity**: M

**Rationale**: The implementation creates new template artifacts, updates the
sync manifest model, and adds setup/sync guidance while preserving the current
root template as the `single_repo` path. The main risk is creating duplicate
framework file copies that drift, so the plan uses manifest-based skeletons
instead of copying whole framework trees.

**Dependencies**: #874 must be merged into `develop-workflow-hub-mode` before
the #876 implementation starts, because this item should link to and build on
the repository mode documentation introduced by #874.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `3144f30` |
| Issue brief and comments | `gh issue view 876 --json number,title,state,body,comments,labels` | Issue #876 is part of #873, has no scope-changing comments, and carries `integration-branch:workflow-hub-mode`. |
| Skeleton directory state | `find . -maxdepth 3 -type d \| sort \| rg '^./(template\|docs\|scripts\|\\.agents\|\\.codex\|\\.claude\|\\.cursor)'` | No existing `template/` skeleton directory is present. |
| Sync manifest state | `sed -n '1,260p' sync-manifest.yaml` | Manifest schema v1 has `always_sync`, `special_handling`, and `project_specific`; no mode-specific scopes. |
| Setup guidance state | `sed -n '1,320p' docs/workflow/setup/protocol.md` | Project setup assumes one root template path and does not ask for repository mode. |
| README setup guidance | `sed -n '1,380p' README.md` | README documents current single-repository setup and sync propagation paths, but no workflow-hub/product-repo skeleton choice. |
| Sync skill behavior | `sed -n '1,220p' .codex/skills/workflow-sync-template/SKILL.md` and `sed -n '260,520p' .claude/commands/sync-template.md` | Sync-template reads existing manifest categories and ignores additional metadata unless protocol text is changed. |

---

## Layer-by-Layer Changes

### Template Skeletons

- [ ] Add `template/workflow-hub/README.md` describing the workflow hub
      skeleton purpose, intended repository role, included file categories, and
      relationship to product repository injection.
- [ ] Add `template/workflow-hub/skeleton-manifest.yaml` listing canonical
      source paths that a workflow hub owns or receives, grouped by:
      - protocols and workflow documentation
      - workflow helper scripts
      - Claude, Cursor, and Codex agent/skill wrappers
      - project workflow configuration
      - workflow smoke runbooks and test harnesses
- [ ] Add `template/product-repo-injection/README.md` describing minimal product
      repository integration and explicit exclusions.
- [ ] Add `template/product-repo-injection/skeleton-manifest.yaml` listing only
      minimal product-repo integration candidates, such as local agent guidance,
      product-repo workflow config examples, and any helper wrappers explicitly
      needed for routed work.
- [ ] Do not duplicate full framework file contents into the skeleton
      directories. Use manifests that reference canonical source paths so the
      skeletons remain inspectable without creating a second copy that can drift.
- [ ] Add placeholder-free examples only; avoid private repository, team,
      product, or customer names.

### Sync Manifest Model

- [ ] Extend `sync-manifest.yaml` comments and schema metadata to define these
      mode scopes:
      - `shared`
      - `hub_only`
      - `product_repo_injection`
- [ ] Add optional mode-scope metadata to existing manifest entries while
      preserving the existing `categories.always_sync`,
      `categories.special_handling`, and `categories.project_specific`
      structure.
- [ ] Keep schema changes backward-compatible for current sync-template readers:
      extra scope metadata is informational in this item and must not alter file
      comparison or copy behavior.
- [ ] Add `template/workflow-hub/` and `template/product-repo-injection/` to the
      manifest as framework-owned files so downstream teams can inspect the new
      skeleton documentation.
- [ ] Ensure product repository injection scope excludes hub-owned tracker,
      spec, and plan artifacts unless a skeleton README explicitly marks a
      specific artifact as required.

### Documentation

- [ ] Update `README.md` with a repository-mode setup section explaining when a
      generated repository chooses:
      - `single_repo` using the current root template
      - `workflow_hub` using the workflow hub skeleton
      - `product_repo` using product repository injection
- [ ] Update `README.md` guidance for existing repositories that are adopting a
      workflow hub or connecting to one.
- [ ] Update `docs/workflow/setup/protocol.md` so setup asks which repository
      mode applies and points the user to the appropriate skeleton.
- [ ] Update `docs/workflow/development-workflow/README.md` or the #874
      repository modes note to link to the skeletons and describe the
      mode-specific setup choice.
- [ ] Update sync-template documentation enough to state that #876 adds
      mode-scope metadata for inspection, not mode-aware sync application.
- [ ] Add the implementation changelog entry under `[Unreleased]` / `### Added`:
      `- **Workflow hub template skeletons** (#876): adds inspectable workflow-hub and product-repo-injection skeletons with mode-specific sync-scope metadata.`

### Tests

- [ ] Add a lightweight manifest/skeleton validation script or test harness,
      for example
      `scripts/development-workflow/tests/test-workflow-hub-skeletons.sh`.
- [ ] Validate that both skeleton directories and both skeleton manifest files
      exist.
- [ ] Validate that each path referenced by a skeleton manifest either exists
      in the repository or is explicitly marked as generated/example-only.
- [ ] Validate that product-repo-injection skeleton entries do not include:
      - `docs/specs/`
      - implementation plan files
      - tracker-owned hub artifacts
      - hub-only smoke runbooks unless explicitly required
- [ ] Validate that `sync-manifest.yaml` contains all three mode-scope values.
- [ ] Validate that the current root template remains unchanged as the
      `single_repo` setup path.

### Database / Data Layer

- [ ] None. This feature has no database, migration, seed, or data model
      changes.

### Backend / API

- [ ] None. This feature does not implement mode-aware sync or skeleton
      application behavior.

### Frontend / UI

- [ ] None. This feature has no browser UI.

### Infrastructure / CI

- [ ] Update workflow test CI paths only if the new skeleton validation harness
      would otherwise be skipped.
- [ ] No CI, branch protection, or reviewer-loop behavior changes are required.

---

## Testing Strategy

**Test types**: Skeleton manifest validation, documentation smoke/manual
verification, markdown lint, shellcheck if a shell harness is added, and
existing sync-template behavior review.

**Key scenarios to test**:

1. `template/workflow-hub/` exists and describes hub-owned protocols, scripts,
   agents, project config, and runbooks (AC1).
2. `template/product-repo-injection/` exists and describes minimal product
   repository integration files (AC2).
3. Inspecting skeleton directories does not modify or replace the current root
   template setup (AC3, AC8).
4. Product repository injection excludes hub-owned tracker, spec, and plan
   artifacts unless explicitly required (AC4).
5. `sync-manifest.yaml` can distinguish `shared`, `hub_only`, and
   `product_repo_injection` scopes (AC5).
6. README guidance covers generated repositories choosing `single_repo`,
   `workflow_hub`, or `product_repo` setup (AC6).
7. README guidance covers existing repositories adopting or connecting to a
   workflow hub (AC7).
8. Skeleton and README examples are generic and private-detail-free (AC9).

**Smoke test runbook**:
`docs/testing/workflow/876-workflow-hub-template-skeletons.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-workflow-hub-skeletons.sh`
- `npx markdownlint-cli2 "README.md" "docs/workflow/**/*.md" "template/**/*.md" "docs/specs/developments/20260610140419_876-workflow-hub-template-skeletons/*.md" "docs/testing/workflow/876-workflow-hub-template-skeletons.smoke-test.md" "CHANGELOG.md"`
- `python3 scripts/lint/markdown-heuristic-lint.py docs/testing/workflow/876-workflow-hub-template-skeletons.smoke-test.md CHANGELOG.md`
- `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`
- `bash scripts/development-workflow/tests/test-install-codex-skills.sh`

### Parser-risk Addendum

- **Edge-case enumeration**:
  - missing skeleton directory
  - skeleton manifest path with a missing source path
  - skeleton manifest path explicitly marked as generated/example-only
  - product-repo-injection entry under `docs/specs/`
  - product-repo-injection entry pointing to a plan file
  - sync manifest entry missing mode-scope metadata where required
  - sync manifest containing an unknown mode scope
- **Unit test mapping**: Add one validation case per edge case in
  `scripts/development-workflow/tests/test-workflow-hub-skeletons.sh`.
- **Suppression semantics**: Not applicable. The validation script should not
  support suppressions in this item.

### Concurrent-Event-Source Addendum

Not applicable. This feature adds static template skeletons, documentation, and
validation. It does not add event listeners, timers, async queues, or shared
mutable runtime state.

---

## Seed Data

None.

---

## Documentation Updates

- [ ] `template/workflow-hub/README.md` - new hub skeleton guidance.
- [ ] `template/workflow-hub/skeleton-manifest.yaml` - new hub skeleton source
      path manifest.
- [ ] `template/product-repo-injection/README.md` - new product injection
      guidance.
- [ ] `template/product-repo-injection/skeleton-manifest.yaml` - new product
      injection source path manifest.
- [ ] `sync-manifest.yaml` - add mode-scope metadata and include skeleton
      directories.
- [ ] `README.md` - add generated/existing repository mode setup guidance.
- [ ] `docs/workflow/setup/protocol.md` - add repository mode selection prompt.
- [ ] `docs/workflow/development-workflow/README.md` or
      `docs/workflow/development-workflow/repository-modes.md` - link skeletons
      from the workflow-hub mode guidance after #874 merges.
- [ ] `CHANGELOG.md` - add the implementation entry listed above.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Skeleton directories duplicate real framework files and drift from canonical sources. | Medium | High | Use README plus manifest references instead of copying full framework trees. |
| Scope metadata changes current sync-template behavior before mode-aware sync is designed. | Medium | High | Keep current manifest categories intact and treat mode scopes as informational metadata in this item. |
| Product repo injection accidentally includes hub-owned specs/plans/tracker artifacts. | Medium | High | Add validation that blocks product injection entries under hub-owned paths unless explicitly marked required. |
| Existing single-repo setup guidance becomes ambiguous. | Medium | Medium | Keep the root template documented as the default `single_repo` path and state that skeleton inspection is passive. |
| Skeleton examples leak private topology. | Low | Medium | Use generic names only and include smoke assertions for private-detail-free examples. |

---

## Code Samples

Any manifest examples in documentation should be illustrative and use generic
paths only. Do not include private product names, repository names, teams, or
customer references.

---

## Implementation Order

1. Confirm #874 has merged into `develop-workflow-hub-mode`.
2. Add `template/workflow-hub/README.md` and
   `template/workflow-hub/skeleton-manifest.yaml`.
3. Add `template/product-repo-injection/README.md` and
   `template/product-repo-injection/skeleton-manifest.yaml`.
4. Extend `sync-manifest.yaml` with mode-scope definitions and skeleton
   directory entries while preserving existing categories.
5. Add the skeleton validation test harness.
6. Update README/setup/workflow documentation with repository mode selection
   guidance.
7. Add the `CHANGELOG.md` entry.
8. Run the smoke test runbook and automated validation commands listed in
   **Testing Strategy**.
9. Open a draft implementation PR targeting `develop-workflow-hub-mode`, run
   internal review, the automated reviewer loop, and CI, then mark the PR ready
   for human review.

# Artifact Ownership and Product Release Contract - Implementation Plan

**Spec**:
[`1_1353-artifact-ownership-product-release-contract_specs.md`](./1_1353-artifact-ownership-product-release-contract_specs.md)
**Smoke test runbook**:
[`docs/testing/workflow/1353-artifact-ownership-product-release-contract.smoke-test.md`](../../../testing/workflow/1353-artifact-ownership-product-release-contract.smoke-test.md)

---

## Summary

**Approach**: Extend the workflow-hub configuration model with a non-secret
product release contract, then make release-artifact ownership visible in the
repository-mode, setup, release, cleanup, and sync-selection surfaces. Keep
single-repository behavior unchanged by treating the current repository as the
default owner and only requiring product release metadata for product-owned
release mutations in `workflow_hub` or `product_repo` mode.

**Estimated complexity**: M

**Rationale**: The change spans configuration parsing, validation, sync
selection, skeleton manifests, workflow documentation, and focused shell/Python
tests. It does not require product app code, database changes, or new external
services.

**Dependencies**: #1353 spec PR #1399 is merged into
`develop-multi-repo-releases`. Issues #1354, #1356, #1357, #1358, and #1359
depend on this contract and should consume it after this implementation is
merged.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `12f5ad4` |
| Product role sync selection | `python3 scripts/development-workflow/select-sync-manifest-entries.py --manifest sync-manifest.yaml --role product_repo` | Selected 24 entries and skipped 14 hub-only entries. Product selection currently includes shared files plus `AGENTS.md`, `.ai-dev-workflow.yaml`, and `.ai-dev-workflow.local.example.yaml`; it skips `docs/workflow/`, `.claude/`, `.codex/skills/`, `.agents/skills/`, `.cursor/`, and `scripts/development-workflow/`. |
| Hub role sync selection | `python3 scripts/development-workflow/select-sync-manifest-entries.py --manifest sync-manifest.yaml --role workflow_hub` | Selected 35 entries and skipped 3 product-repo-injection entries. |
| Skeleton validation | `python3 scripts/development-workflow/validate-workflow-hub-skeletons.py` | `VALID` |
| Release and mode surface scan | `rg -l "release|Release|product_repo|workflow_hub|mode_scope|artifact ownership|GitHub Release|tag|changelog" docs/workflow/development-workflow scripts/development-workflow template sync-manifest.yaml .ai-dev-workflow.yaml \| sort` | Key surfaces include `.ai-dev-workflow.yaml`, `docs/workflow/development-workflow/repository-modes.md`, `workflow-hub-setup.md`, `product-repo-injection.md`, `cross-repo-pr-flow.md`, `protocols/05-prepare-release-protocol.md`, `prepare-release-post-merge-cleanup.sh`, `post-merge-cleanup.sh`, `workflow-config-resolver.py`, `select-sync-manifest-entries.py`, skeleton manifests, and sync tests. |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Plan base | `develop-multi-repo-releases` | `/run-epic 1352` invocation and PR #1399 base branch | 2026-07-30, repo `12f5ad4` | Epic #1352 child scope and current #1353 plan branch only | `Verified` |
| Repository mode default | Missing `mode` resolves to `single_repo` | `workflow-config-resolver.py` and `repository-modes.md` | 2026-07-30, repo `12f5ad4` | Config resolver tests and docs touched by this plan | `Verified` |
| Product release contract owner | Versioned non-secret metadata in `.ai-dev-workflow.yaml`; local paths and credentials stay in `.ai-dev-workflow.local.yaml` | #1353 spec and existing workflow-hub setup docs | 2026-07-30, repo `12f5ad4` | Workflow-hub/product-repo config, setup docs, and resolver validation | `Verified` |

---

## Layer-by-Layer Changes

### Database / Data Layer

- [ ] No database or seed-data changes. The repository is workflow tooling and
      documentation; #1353 stores no relational data.

### Backend / API

- [ ] No HTTP API changes.

### Shared Packages / Libraries

- [ ] `scripts/development-workflow/workflow-config-resolver.py`: add release
      contract normalization for `workflow_hub.product_repos[]` and
      `product_repo`, including branch-name validation, release-branch pattern
      validation, owner enum validation, explicit/default origin reporting, and
      forbidden-data scanning across the release contract. Map to AC3, AC4, AC5,
      and AC8.
- [ ] `scripts/development-workflow/validate-workflow-config.sh`: expose the
      resolver's product release contract validation in the existing validation
      entry point. Keep successful output non-secret and include whether fields
      were explicit or defaulted. Map to AC3-AC5.
- [ ] `scripts/development-workflow/select-sync-manifest-entries.py`: preserve
      existing role filtering, and include enough entry metadata for tests to
      assert release runtime surfaces by logical role. Do not introduce a second
      sync-selection path. Map to AC6-AC8.
- [ ] `scripts/development-workflow/validate-workflow-hub-skeletons.py`: extend
      skeleton validation so product repository manifests can mark required
      release runtime entries and hub manifests can reject product-only runtime
      ownership. Map to AC6-AC7.
- [ ] `sync-manifest.yaml`: classify the minimum product release runtime
      surfaces as `product_repo_injection` only when they are safe to inject
      into a product repository. Keep hub-only coordination docs, historical
      specs/plans, and hub runbooks excluded from product repository selection.
      Map to AC6-AC8.
- [ ] `template/workflow-hub/skeleton-manifest.yaml` and
      `template/product-repo-injection/skeleton-manifest.yaml`: add ownership
      notes and required product release runtime entries that match
      `sync-manifest.yaml`. Map to AC1, AC2, AC6, and AC7.

### Infrastructure / Configuration

- [ ] `.ai-dev-workflow.yaml`: document optional non-secret release contract
      fields for product repositories without enabling them for this template's
      own runtime. Keep the template repository's default behavior unchanged.
      Map to AC3, AC5, and AC8.
- [ ] `.ai-dev-workflow.local.example.yaml`: confirm local paths, private key
      paths, token values, and secret references remain local-only examples and
      are not part of the versioned product release contract. Map to AC5.

### Workflow Documentation

- [ ] `docs/workflow/development-workflow/repository-modes.md`: add the release
      artifact ownership table from the spec and cross-link it to existing PR
      and base-branch ownership guidance. Map to AC1, AC2, and AC8.
- [ ] `docs/workflow/development-workflow/workflow-hub-setup.md`: add product
      release contract setup examples, default semantics, and forbidden-data
      rules. Map to AC3-AC5.
- [ ] `docs/workflow/development-workflow/product-repo-injection.md`: describe
      which product release runtime files may be injected and which hub-only
      release coordination files must remain excluded. Map to AC6-AC7.
- [ ] `docs/workflow/development-workflow/cross-repo-pr-flow.md`: identify the
      owner for changelog, release branch, tag, GitHub Release, deployment
      evidence, product cleanup evidence, and tracker reconciliation evidence
      before product release mutation. Map to AC1-AC4.
- [ ] `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`:
      require release-contract validation before product-owned release branches,
      tags, GitHub Releases, or product changelog mutations. Preserve the
      existing single-repository release path. Map to AC3, AC4, and AC8.
- [ ] `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`
      and `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md`:
      reference the ownership contract where integration branch graduation or
      batch merging hands off to product release evidence. Map to AC1-AC2.
- [ ] `docs/workflow/development-workflow/integrations/github-projects.md`:
      clarify that tracker reconciliation evidence remains hub-owned for
      hub-managed product releases. Map to AC1-AC2.

---

## Testing Strategy

**Test types**: Unit, integration-style shell fixture tests, smoke/manual docs
review.

**Key scenarios to test**:

1. Product release contract validation accepts a minimal valid
   `workflow_hub.product_repos[]` entry, reports explicit/default values, and
   rejects missing product selection when multiple product repositories exist.
   Maps to AC3, AC4, and AC8.
2. Validation rejects local paths, credentials, tokens, secret names, secret
   values, and environment-specific account details inside the versioned release
   contract while still allowing those values in local-only config. Maps to AC5.
3. Branch names and release branch patterns accept portable valid values and
   reject whitespace, empty segments, `..`, `@{`, `//`, leading/trailing slash,
   `?`, `^`, `~`, `:`, backslash, `#`, unknown placeholders, and unresolved
   placeholders. Maps to AC3-AC4.
4. Role-aware sync selects product release runtime surfaces for `product_repo`,
   excludes hub-only coordination files, preserves `single_repo` selection, and
   selects hub surfaces for `workflow_hub`. Maps to AC6-AC8.
5. Skeleton validation proves workflow-hub and product-repo manifests match the
   ownership contract and fail closed for unknown or mis-scoped entries. Maps to
   AC1, AC2, AC6, and AC7.
6. Documentation review confirms each artifact in the spec's ownership table
   has exactly one owner for `single_repo`, `workflow_hub`, and `product_repo`.
   Maps to AC1-AC2.

**Smoke test runbook**:
`docs/testing/workflow/1353-artifact-ownership-product-release-contract.smoke-test.md`

**Regression suite**:

- [ ] Extend `scripts/development-workflow/tests/test-workflow-config-resolver.sh`.
- [ ] Extend `scripts/development-workflow/tests/test-sync-template-mode-scopes.sh`.
- [ ] Extend `scripts/development-workflow/tests/test-workflow-hub-skeletons.sh`.
- [ ] Extend or add a focused docs/smoke test under
      `scripts/development-workflow/tests/test-workflow-hub-docs.sh` for the
      release ownership map and setup guidance.

### Parser-Risk Addendum

This plan is parser-risk because it changes YAML subset parsing/validation and
adds branch-pattern validation over structured text.

- **Edge-case enumeration**:
  - Valid branches: `main`, `develop`, `release/v1.2.3`,
    `product_repo/release-v1.2.3`, and `team.alpha/release_1`.
  - Invalid branch boundary cases: empty string, leading slash, trailing slash,
    empty segment from `//`, whitespace, `..`, `@{`, `?`, `^`, `~`, `:`,
    backslash, and `#`.
  - Valid patterns: `release/v{version}` and
    `{product_repo}/release/v{version}` after substituting one version and one
    product repository key.
  - Invalid pattern cases: unknown placeholder, missing `{version}`,
    unresolved placeholder after substitution, and pattern resolving to an
    invalid branch.
  - Forbidden-data lookalikes: local-only keys nested inside the release
    contract, token-like values in allowed scalar fields, and local path-looking
    values that must remain out of versioned config.
- **Unit test mapping**:
  - `scripts/development-workflow/tests/test-workflow-config-resolver.sh`:
    valid/invalid branch and pattern cases, explicit/default release contract
    output, unknown owner enum, missing product selection, and forbidden-data
    rejection.
  - `scripts/development-workflow/tests/test-sync-template-mode-scopes.sh`:
    release runtime entries selected/skipped by role and unknown scope failures.
  - `scripts/development-workflow/tests/test-workflow-hub-skeletons.sh`:
    required product release runtime entries and hub-only exclusion failures.
- **Suppression semantics**: Not applicable. This feature does not introduce
  inline suppression directives.

### Concurrent-Event-Source Addendum

- **Shared mutable state guards**: Not applicable; the implementation is
  command-line validation and manifest selection with process-local state.
- **Re-entrancy / in-flight tracking**: Not applicable; each helper invocation
  reads files and exits.
- **Event deduplication**: Not applicable; no event listener or webhook source
  is introduced.
- **Listener and resource cleanup**: Not applicable; no long-lived listeners,
  timers, or handles are introduced.
- **Race conditions at initialization**: Not applicable; validation reads the
  current file state at command start.
- **Race conditions at teardown**: Not applicable; there is no teardown hook.
- **Error propagation across async boundaries**: Not applicable; scripts are
  synchronous Bash/Python commands.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Workflow hub fixture config | One valid hub with two product repositories; one product has explicit release fields and one relies on defaults | Temporary fixture inside `scripts/development-workflow/tests/test-workflow-config-resolver.sh` |
| Product repository fixture config | `mode: product_repo` with a hub reference and optional product release defaults | Temporary fixture inside `scripts/development-workflow/tests/test-workflow-config-resolver.sh` |
| Sync manifest fixture | Shared, hub-only, product-repo-injection, and release-runtime entries | Temporary fixture inside `scripts/development-workflow/tests/test-sync-template-mode-scopes.sh` |
| Skeleton fixture | Valid and invalid product release runtime entries | Temporary fixture inside `scripts/development-workflow/tests/test-workflow-hub-skeletons.sh` |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/repository-modes.md` - add release
      artifact ownership, default behavior, and links to product release
      contract validation.
- [ ] `docs/workflow/development-workflow/workflow-hub-setup.md` - add
      versioned product release contract examples and validation commands.
- [ ] `docs/workflow/development-workflow/product-repo-injection.md` - add the
      product release runtime inclusion/exclusion contract.
- [ ] `docs/workflow/development-workflow/cross-repo-pr-flow.md` - add release
      artifact owner checks before product-owned release mutation.
- [ ] `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`
      - require product release contract validation before product-owned release
      artifacts are created or mutated.
- [ ] `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`
      - reference release evidence ownership during integration branch
      graduation.
- [ ] `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md`
      - reference release cleanup/evidence ownership in batch handoff wording.
- [ ] `docs/workflow/development-workflow/integrations/github-projects.md` -
      clarify tracker reconciliation evidence ownership.
- [ ] `template/workflow-hub/README.md` and
      `template/product-repo-injection/README.md` - keep skeleton summaries
      aligned with the release ownership contract.
- [ ] `CHANGELOG.md` - add the #1353 Unreleased entry during implementation.
- [ ] `AGENTS.md` - no content update expected; workflow command guidance is
      unchanged.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Product repository injection accidentally includes hub-only coordination files | Med | High | Keep sync selection centralized in `select-sync-manifest-entries.py`; add role-count assertions and explicit selected/skipped path checks. |
| Release contract validation rejects existing single-repository adopters | Low | High | Gate required product release fields only for product-owned release work in `workflow_hub` or `product_repo`; add single-repo compatibility tests. |
| Forbidden-data checks become too broad and reject harmless values | Med | Med | Validate keys and high-signal token/path patterns, then cover allowed non-secret examples in tests. |
| Branch-pattern validation diverges from the spec | Med | Med | Implement one helper for branch names and pattern resolution; map each spec edge case to a unit test. |
| Documentation and skeleton manifests drift from sync-manifest behavior | Med | Med | Extend skeleton validation and smoke runbook checks to compare all three surfaces. |

---

## Code Samples

Illustrative configuration shape only; adapt during implementation:

```yaml
workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      default_branch: main
      release:
        base: main
        branch_pattern: release/v{version}
        changelog_owner: product_repo
        tag_owner: product_repo
        github_release_owner: product_repo
        deployment_evidence_owner: product_repo
        cleanup_evidence_owner: product_repo
        tracker_reconciliation_owner: hub
```

---

## Implementation Order

1. Update `workflow-config-resolver.py` with release contract normalization,
   owner enums, branch validation, pattern validation, default reporting, and
   forbidden-data checks. Run
   `bash scripts/development-workflow/tests/test-workflow-config-resolver.sh`
   and confirm the new release contract cases pass.
2. Update `validate-workflow-config.sh` only as needed to print the new
   resolver fields without exposing local paths or secrets. Re-run the config
   resolver tests.
3. Update `sync-manifest.yaml`, `select-sync-manifest-entries.py` only if extra
   metadata is needed, and `test-sync-template-mode-scopes.sh` so role-aware
   sync proves the product release runtime set. Confirm product role output
   selects product-runtime entries and skips hub-only coordination.
4. Update workflow and product skeleton manifests plus
   `validate-workflow-hub-skeletons.py`/tests so required product release
   runtime entries and hub-only exclusions are enforced.
5. Update repository-mode, setup, product-injection, cross-repo release flow,
   release, graduation, batch-merge, and GitHub Projects docs listed in
   **Documentation Updates**. Confirm the ownership table names exactly one
   owner per artifact and mode.
6. Update the smoke runbook if implementation details differ from this plan,
   then run the smoke commands in the runbook.
7. Update `CHANGELOG.md` under `[Unreleased]` using:
   `- **Artifact ownership and product release contract** (#1353): documents and validates multi-repository release artifact ownership and product release configuration for workflow hubs.`
8. Run the implementation-specific regression tests listed in **Regression
   suite**, then execute the linked smoke-test runbook as the source of truth
   for smoke and markdown verification commands.

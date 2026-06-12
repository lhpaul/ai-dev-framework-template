# Workflow Hub Setup And Operations Docs - Implementation Plan

**Spec**: [1_882-workflow-hub-docs_specs.md](1_882-workflow-hub-docs_specs.md)
**Smoke test runbook**: [882-workflow-hub-docs.smoke-test.md](../../../testing/workflow/882-workflow-hub-docs.smoke-test.md)

---

## Summary

**Approach**: Add adoption-oriented workflow-hub documentation under the
existing `docs/workflow/development-workflow/` tree, with one setup guide, one
product-repo injection guide, and one cross-repository PR operations guide.
Update the development-workflow README and repository-modes doc so the new
guides are discoverable. Validate the docs with link checks, secret-name scans,
unsafe-command scans, markdown lint, and a smoke runbook.

**Estimated complexity**: M

**Rationale**: The implementation is documentation-only, but it spans several
workflow-hub concepts and must align with recently merged commands, config
split, auth helpers, sync-template scopes, and cross-repository ownership rules.

**Dependencies**: #874, #875, #876, #877, #878, #879, #880, #881, and #883 are
merged.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `50c5293` |
| Approved spec | `sed -n '1,340p' docs/specs/developments/20260611204735_882-workflow-hub-docs/1_882-workflow-hub-docs_specs.md` | Spec requires setup, product-repo injection, cross-repo PR flow, troubleshooting, protocol links, and non-secret examples. |
| Existing workflow-hub operating model | `sed -n '1,460p' docs/workflow/development-workflow/repository-modes.md` | Source for mode names, artifact ownership, product-repo selection, sync-template scopes, and example topology. |
| Existing auth guide | `sed -n '1,220p' docs/workflow/development-workflow/integrations/workflow-hub-github-app.md` | Source for GitHub App setup, local credential split, dry-run PR helper, and auth failure states. |
| Existing script docs | `sed -n '1,320p' scripts/development-workflow/README.md` | Source for validation, product status/sync commands, smoke fixture, and sync-manifest selector invocation. |
| Existing docs tree | `find docs/workflow/development-workflow -maxdepth 2 -type f \| sort` | Workflow docs live directly under `docs/workflow/development-workflow/` and `integrations/`; use that structure instead of adding top-level `docs/setup` or `docs/operations`. |

---

## Layer-by-Layer Changes

### Documentation

- [ ] Add `docs/workflow/development-workflow/workflow-hub-setup.md`.
  - Cover when to choose `workflow_hub`.
  - Show versioned `.ai-dev-workflow.yaml` with placeholder
    `faind-workflow-hub`, `faind-mobile-app`, and `faind-admin-portal`
    repositories.
  - Show local-only `.ai-dev-workflow.local.yaml` with placeholder checkout
    paths and fake secret references only.
  - Include commands and run locations for:
    - `scripts/development-workflow/validate-workflow-config.sh`
    - `scripts/development-workflow/hub-status.sh --all`
    - `scripts/development-workflow/hub-sync-product-repos.sh`
    - `scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh`
  - Link to `repository-modes.md` and
    `integrations/workflow-hub-github-app.md`.
- [ ] Add `docs/workflow/development-workflow/product-repo-injection.md`.
  - Explain `product_repo` mode and the product repository config shape.
  - Explain role-aware sync-template selection after #881:
    `product_repo` selects `shared` plus `product_repo_injection` and skips
    `hub_only`.
  - Show a dry-run or preview command shape using
    `select-sync-manifest-entries.py` and `/sync-template --dry-run`.
  - State that product repos must not receive hub-owned tracker state, specs,
    implementation plans, workflow protocols, or hub orchestration scripts.
  - Link to `sync-manifest.yaml`, `template/product-repo-injection/`, and the
    sync-template command docs.
- [ ] Add `docs/workflow/development-workflow/cross-repo-pr-flow.md`.
  - Show a stage-by-stage flow from hub item selection through product branch,
    PR, reviewer loop, CI loop, readiness labels, merge, and cleanup.
  - Include a repository ownership table for tracker, spec, plan,
    implementation branch, PR, CI, reviewer loop, and cleanup.
  - Include concrete commands and run locations for:
    - `workflow-next-action.sh --repo faind-mobile-app --development docs/specs/developments/20260611204735_882-workflow-hub-docs`
    - `hub-status.sh --repo faind-mobile-app`
    - `hub-sync-product-repos.sh --repo faind-mobile-app`
    - `open-product-pr.sh --repo faind-mobile-app --dry-run`
    - `pr-review-loop.sh --repo example/faind-mobile-app`
    - `pr-ci-loop.sh --repo example/faind-mobile-app`
    - `post-merge-cleanup.sh --repo faind-mobile-app feature/faind-example`
  - Link to protocols 90, 91, 93, and 94 plus the GitHub App auth guide.
- [ ] Add troubleshooting sections to the new docs rather than a separate
      orphan file.
  - Missing product checkout.
  - Dirty product repo.
  - Missing GitHub App credentials.
  - Failed CI.
  - Reviewer-loop failures.
  - Each item must include symptom, confirm command, safe repair path, run
    location, and escalation condition.
- [ ] Update `docs/workflow/development-workflow/README.md`.
  - Add links to the setup, injection, and cross-repo PR flow guides near the
    repository-mode section.
- [ ] Update `docs/workflow/development-workflow/repository-modes.md`.
  - Add a short "Adoption guides" pointer to the new docs.
- [ ] Add a CHANGELOG entry under `[Unreleased]` / `### Added`:
  `- **Workflow hub setup and operations docs** (#882): documents workflow-hub setup, product-repo injection, cross-repo PR flow, and troubleshooting with non-secret example repositories.`

### Tests

- [ ] Add a focused documentation smoke test script:
      `scripts/development-workflow/tests/test-workflow-hub-docs.sh`.
  - Assert the three new docs exist.
  - Assert required commands appear in the expected docs.
  - Assert required protocol/integration links appear.
  - Assert required troubleshooting terms appear.
  - Assert unsafe command strings do not appear:
    `git reset --hard`, `push --force`, `--force-with-lease`, ambient token
    fallback phrases, or private key material.
  - Assert confidential project names and token patterns from the existing
    smoke fixture private scan are absent.
  - Assert the Faind-like placeholder names appear.
- [ ] Update `scripts/development-workflow/README.md` only if the new smoke
      test needs discoverability there; otherwise keep script docs unchanged.

### Database / Frontend / Infrastructure

- [ ] No database, frontend, or runtime infrastructure changes.
- [ ] No live product repositories, GitHub Apps, private keys, or secret
      manager access are required.

---

## Testing Strategy

**Test types**: Documentation smoke test, markdown lint, heuristic lint,
duplicate-header check, link/path inspection, and unsafe-content scan.

**Key scenarios to test**:

1. Setup guide includes concrete commands and run locations. Maps to AC1.
2. Setup and injection docs explain versioned versus local-only config. Maps to
   AC2.
3. Injection guide explains role-aware sync-template product-repo selection.
   Maps to AC3.
4. Cross-repo PR guide covers routing through reviewer loop, CI, readiness,
   merge, and cleanup. Maps to AC4 and AC5.
5. Troubleshooting covers missing checkout, dirty repo, missing credentials,
   failed CI, and reviewer-loop failures. Maps to AC6.
6. Docs link to relevant protocols and integration guides. Maps to AC7.
7. Examples use Faind-like placeholder names and no confidential details. Maps
   to AC8.
8. Docs avoid unsafe recovery instructions and secret material. Maps to AC9.
9. README or repository-modes links make docs discoverable. Maps to AC10.

**Smoke test runbook**:
`docs/testing/workflow/882-workflow-hub-docs.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-workflow-hub-docs.sh`
- `npx markdownlint-cli2 "docs/workflow/development-workflow/*.md" "docs/workflow/development-workflow/integrations/*.md" "docs/specs/developments/20260611204735_882-workflow-hub-docs/*.md" "docs/testing/workflow/882-workflow-hub-docs.smoke-test.md" "CHANGELOG.md"`
- `python3 scripts/lint/markdown-heuristic-lint.py docs/testing/workflow/882-workflow-hub-docs.smoke-test.md CHANGELOG.md`
- `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`
- `git diff --check`

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Placeholder hub | `faind-workflow-hub`, `example/faind-workflow-hub` | New setup and flow docs |
| Placeholder products | `faind-mobile-app`, `faind-admin-portal`, `example/faind-mobile-app`, `example/faind-admin-portal` | New setup, injection, and flow docs |
| Fake GitHub App IDs | `"12345"`, `"999999"`, `"888888"` | New setup docs |
| Fake local paths | `../repos/faind-mobile-app`, `../repos/faind-admin-portal` | New setup docs |
| Fake secret refs | `op://ExampleVault/faind-mobile-app-github-app/private-key` | New setup docs only as placeholder syntax |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/workflow-hub-setup.md` - new setup
      guide.
- [ ] `docs/workflow/development-workflow/product-repo-injection.md` - new
      injection guide.
- [ ] `docs/workflow/development-workflow/cross-repo-pr-flow.md` - new
      operations guide.
- [ ] `docs/workflow/development-workflow/README.md` - link new guides.
- [ ] `docs/workflow/development-workflow/repository-modes.md` - link new
      guides.
- [ ] `CHANGELOG.md` - add #882 docs entry.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Docs duplicate existing operating-model content and drift | Medium | Medium | Link to existing details and keep new docs adoption-focused. |
| Examples accidentally look like real private project data | Low | High | Use `example/*`, fake IDs, and smoke-test scans for known private/token patterns. |
| Troubleshooting suggests unsafe git or credential fallback | Low | High | Add smoke-test scans for unsafe command strings and fallback phrasing. |
| Docs point to commands from the wrong checkout | Medium | Medium | Require every command block to include run-location labels and smoke-test for key command names. |

---

## Implementation Order

1. Add the three new workflow-hub adoption docs.
2. Add the focused docs smoke test for required terms, links, safe examples,
   and unsafe-content absence.
3. Update README and repository-modes discoverability links.
4. Add the #882 CHANGELOG entry.
5. Run the documentation smoke test and markdown validation suite.
6. Review the final docs against AC1-AC10 before opening the implementation PR.

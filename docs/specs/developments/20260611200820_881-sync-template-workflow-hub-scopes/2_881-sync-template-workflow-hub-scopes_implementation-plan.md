# Sync-Template Workflow-Hub Scopes - Implementation Plan

**Spec**: [1_881-sync-template-workflow-hub-scopes_specs.md](1_881-sync-template-workflow-hub-scopes_specs.md)
**Smoke test runbook**: [881-sync-template-workflow-hub-scopes.smoke-test.md](../../../testing/workflow/881-sync-template-workflow-hub-scopes.smoke-test.md)

---

## Summary

**Approach**: Extend the manifest-driven sync-template protocol to resolve the
target repository role before file comparison, then filter manifest entries by
`mode_scope` for dry-run and apply summaries. Keep `single_repo` behavior as the
compatibility baseline, add tests around role-specific file selection, and
document the role-aware summary fields.

**Estimated complexity**: L

**Rationale**: The change touches the canonical sync-template command
instructions, the Codex skill wrapper, manifest interpretation, tests, docs, and
summary semantics. It is not a new runtime service, but it changes a high-risk
maintenance workflow that can overwrite files.

**Dependencies**: #875, #876, #877, and #883 are merged. No external service
dependency is required for default tests.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `178f9c0` |
| Template-fit check | `rg -n "template:" .ai-dev-workflow.yaml` and `.ai-dev-workflow.yaml` review | Repository is a template and #881 is generic workflow tooling, so the plan can proceed. |
| Approved spec | `sed -n '1,360p' docs/specs/developments/20260611200820_881-sync-template-workflow-hub-scopes/1_881-sync-template-workflow-hub-scopes_specs.md` | Spec defines role-aware sync-template behavior, divergent-change reporting, and selected/skipped file visibility. |
| Current sync manifest | `sed -n '1,260p' sync-manifest.yaml` | Manifest already defines `shared`, `hub_only`, and `product_repo_injection` scopes, but comments state they are currently informational. |
| Canonical sync-template protocol | `sed -n '1,520p' .claude/commands/sync-template.md` | Protocol loads `sync-manifest.yaml`, compares `always_sync`, `special_handling`, and `project_specific`, and has dry-run diagnostics but no role-based filtering. |
| Codex sync wrapper | `sed -n '1,220p' .codex/skills/workflow-sync-template/SKILL.md` | Wrapper delegates to the canonical protocol and needs a role-aware sync-template instruction update. |
| Existing workflow-hub tests | `find scripts/development-workflow/tests -maxdepth 1 -type f \| sort \| rg 'sync|hub|template'` | Existing tests cover hub skeletons, product repo commands, PR auth, smoke fixtures, and GitHub Projects helpers; add a focused sync-template scope test. |

---

## Layer-by-Layer Changes

### Backend / Scripts

- [ ] Add a small manifest selection helper under `scripts/development-workflow/`
      that can read `sync-manifest.yaml`, resolve a requested repository role,
      and print selected and skipped entries by sync category.
      - Inputs: manifest path and role (`single_repo`, `workflow_hub`, or
        `product_repo`).
      - Output: stable key/value or JSON records suitable for shell tests and
        future sync-template use.
      - Role rules:
        - `single_repo`: preserve current behavior by selecting the existing
          manifest categories without excluding entries by `mode_scope`.
        - `workflow_hub`: select `shared` and `hub_only`; skip
          `product_repo_injection`.
        - `product_repo`: select `shared` and `product_repo_injection`; skip
          `hub_only`.
      - Fail closed on unknown roles, missing `mode_scope`, or unknown
        `mode_scope` values.
- [ ] Update `.claude/commands/sync-template.md` so Step 0/Step 2 explicitly
      resolve repository role and apply role selection before comparing files.
- [ ] Update `.codex/skills/workflow-sync-template/SKILL.md` and
      `.agents/skills/sync-template/SKILL.md` to mention role-aware manifest
      selection while preserving delegation to the canonical protocol.
- [ ] Ensure dry-run output includes the resolved role, selected counts, and
      skipped counts by mode scope before any file mutation.
- [ ] Ensure the apply path uses the same selected entry set as dry-run, so
      preview and apply cannot disagree.
- [ ] Preserve existing divergent-local-change reporting by running it only for
      entries selected for the resolved role.

### Tests

- [ ] Add `scripts/development-workflow/tests/test-sync-template-mode-scopes.sh`.
- [ ] Cover one fixture manifest with representative entries in
      `always_sync`, `special_handling`, and `project_specific`.
- [ ] Assert `single_repo` selects the compatibility file set.
- [ ] Assert `workflow_hub` selects hub-only plus shared entries and reports
      product-repo-injection entries as skipped.
- [ ] Assert `product_repo` selects product-repo-injection plus shared entries
      and reports hub-only entries as skipped.
- [ ] Assert unknown role and unknown mode-scope values fail before selection.
- [ ] Assert dry-run/apply selection parity by comparing the helper output used
      by both protocol paths or by adding a protocol fixture check if the
      implementation keeps selection inside the command documentation.
- [ ] Extend `test-workflow-hub-smoke-fixtures.sh` only if the implementation
      exposes a real dry-run role-selection command; otherwise keep the focused
      sync-template test as the source of truth for #881.

### Documentation

- [ ] Update `sync-manifest.yaml` comments to remove the "informational only"
      language once role-aware selection is implemented.
- [ ] Update `docs/workflow/development-workflow/repository-modes.md` with the
      sync-template role behavior and product repository exclusion rule.
- [ ] Update `scripts/development-workflow/README.md` with the new helper or
      dry-run invocation.
- [ ] Update `docs/workflow/development-workflow/README.md` where it currently
      describes mode-scope metadata as informational.
- [ ] Add a CHANGELOG entry under `[Unreleased]` / `### Changed`:
      `- **Sync-template workflow-hub scopes** (#881): makes template sync role-aware so workflow hubs receive hub-owned files while product repositories receive only injection-safe files.`

### Database / Frontend / Infrastructure

- [ ] No database or frontend changes.
- [ ] No new CI secrets or live product repositories are required.
- [ ] If a new shell helper is added, ensure the existing ShellCheck workflow
      covers it through the `scripts/development-workflow/**/*.sh` path.

---

## Testing Strategy

**Test types**: Shell unit/fixture tests, smoke runbook verification,
ShellCheck, markdown lint, and existing workflow-hub regression tests.

**Key scenarios to test**:

1. `single_repo` role keeps the compatibility selection path. Maps to AC4.
2. `workflow_hub` role selects `shared` and `hub_only` entries. Maps to AC1.
3. `product_repo` role selects `shared` and `product_repo_injection` entries.
   Maps to AC2.
4. Product repository role excludes hub-owned tracker, spec, plan, workflow
   protocol, and orchestration paths when they are `hub_only`. Maps to AC3.
5. Skipped files are visible by mode scope in the summary. Maps to AC5.
6. Divergent local changes are reported for selected files before overwrite.
   Maps to AC6.
7. Unknown mode scopes fail closed. Maps to AC7.
8. Hub and product repository fixtures produce different selected file sets from
   the same manifest. Maps to AC8.
9. Product repository dry-run fixtures do not need private repositories or live
   GitHub App credentials. Maps to AC9.

**Smoke test runbook**:
`docs/testing/workflow/881-sync-template-workflow-hub-scopes.smoke-test.md`

**Regression suite**:

- `bash scripts/development-workflow/tests/test-sync-template-mode-scopes.sh`
- `bash scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh`
- `bash scripts/development-workflow/tests/test-workflow-hub-skeletons.sh`
- `bash scripts/development-workflow/tests/test-workflow-config-resolver.sh`
- `shellcheck --severity=warning scripts/development-workflow/*.sh scripts/development-workflow/tests/*.sh`
- `python3 -m py_compile scripts/development-workflow/workflow-config-resolver.py scripts/development-workflow/validate-workflow-hub-skeletons.py`
- `npx markdownlint-cli2 "docs/specs/developments/20260611200820_881-sync-template-workflow-hub-scopes/*.md" "docs/testing/workflow/881-sync-template-workflow-hub-scopes.smoke-test.md" "CHANGELOG.md"`
- `python3 scripts/lint/markdown-heuristic-lint.py docs/testing/workflow/881-sync-template-workflow-hub-scopes.smoke-test.md CHANGELOG.md`
- `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`

### Parser-Risk Addendum

This plan is parser-risk because it introduces manifest selection over structured
YAML-like sync metadata.

**Edge-case enumeration**:

- Manifest is missing `mode_scopes`.
- A category entry is missing `mode_scope`.
- A category entry has an unknown `mode_scope`.
- Role is unknown.
- `single_repo` preserves entries across all mode scopes.
- `workflow_hub` skips `product_repo_injection`.
- `product_repo` skips `hub_only`.
- Directory entries with `glob` retain their selection metadata.
- `special_handling` entries are selected but still require manual approval.
- `project_specific` entries remain additive/manual-review only.

**Unit test mapping**: `scripts/development-workflow/tests/test-sync-template-mode-scopes.sh`
must include one named assertion for each edge case above.

**Suppression semantics**: Not applicable. The feature does not introduce
suppression directives.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Fixture sync manifest | Entries covering `shared`, `hub_only`, `product_repo_injection`, directory `glob`, `always_sync`, `special_handling`, and `project_specific` | `scripts/development-workflow/tests/test-sync-template-mode-scopes.sh` |
| Fixture repository configs | Temporary `.ai-dev-workflow.yaml` files for `single_repo`, `workflow_hub`, and `product_repo` role resolution if the implementation tests role detection end to end | Temporary test directories |

---

## Documentation Updates

- [ ] `.claude/commands/sync-template.md` - canonical role-aware sync-template
      behavior and summary requirements.
- [ ] `.codex/skills/workflow-sync-template/SKILL.md` - wrapper guidance for
      role-aware manifest selection.
- [ ] `.agents/skills/sync-template/SKILL.md` - command alias guidance if needed
      for the updated wrapper behavior.
- [ ] `sync-manifest.yaml` - update comments from informational metadata to
      enforced role-selection metadata.
- [ ] `docs/workflow/development-workflow/repository-modes.md` - explain hub
      versus product repo sync behavior.
- [ ] `docs/workflow/development-workflow/README.md` - update current
      informational mode-scope language.
- [ ] `scripts/development-workflow/README.md` - document any helper or dry-run
      command added during implementation.
- [ ] `CHANGELOG.md` - add the #881 entry listed above.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Product repositories receive hub-owned workflow state | Medium | High | Add role-selection tests that assert `hub_only` paths are skipped for `product_repo`. |
| Single-repository adopters lose files after mode-scope filtering | Medium | High | Treat `single_repo` as compatibility mode and test that all manifest scopes remain selected. |
| Dry-run and apply paths disagree | Medium | High | Centralize selection in one helper or one documented selection function and test parity. |
| Unknown manifest scope is silently ignored | Low | Medium | Fail closed before file mutation and add explicit test coverage. |

---

## Implementation Order

1. Add the manifest role-selection helper or equivalent shared selection
   function, with stable output for selected and skipped entries.
2. Add `test-sync-template-mode-scopes.sh` with fixture manifests and edge-case
   assertions from the Parser-Risk Addendum.
3. Update the canonical sync-template protocol to resolve repository mode,
   invoke role selection before comparison, and show selected/skipped counts in
   dry-run summaries.
4. Update Codex and command-alias sync-template skill guidance so non-Claude
   surfaces follow the same role-aware behavior.
5. Update docs and manifest comments listed in Documentation Updates.
6. Add the #881 CHANGELOG entry under `[Unreleased]` / `### Changed`.
7. Run the regression suite listed in Testing Strategy.
8. Execute the smoke test runbook and record any implementation-time notes in
   the PR description.

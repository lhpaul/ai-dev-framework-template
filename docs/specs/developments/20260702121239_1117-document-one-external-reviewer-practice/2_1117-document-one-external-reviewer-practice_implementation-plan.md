# One External Reviewer Practice - Implementation Plan

**Spec**: [1_1117-document-one-external-reviewer-practice_specs.md](1_1117-document-one-external-reviewer-practice_specs.md)
**Smoke test runbook**: [1117-document-one-external-reviewer-practice.smoke-test.md](../../../testing/workflow/1117-document-one-external-reviewer-practice.smoke-test.md)

---

## Summary

**Approach**: Add canonical guidance in the generic automated review platform
documentation, cross-reference it from repository-mode/configuration guidance,
and make `.ai-dev-workflow.local.example.yaml` demonstrate the recommended
single external ready-phase reviewer pattern. Implement the optional validator
warning as a non-blocking stderr warning in `workflow-config-resolver.py` so
otherwise valid multi-reviewer configurations continue to pass validation.

**Estimated complexity**: S

**Rationale**: The change is limited to workflow documentation, one config
example, and one existing standard-library Python resolver with focused shell
tests.

**Dependencies**: #1113 is Merged, satisfying the epic dependency chain for
advisory-hardening work. No external service dependency is required.

## Verification Log

| Check | Command / query | Result |
| ----- | --------------- | ------ |
| Repo revision | `git rev-parse --short HEAD` | `141cc08` |
| External reviewer/config references | `rg -l "review.on_draft.github|review.on_ready.github|external reviewer|Automated PR Review Platforms|validate-workflow-config" docs/workflow/development-workflow .ai-dev-workflow.yaml .ai-dev-workflow.local.example.yaml scripts/development-workflow tests 2>/dev/null \| sort` | Key implementation targets include `docs/workflow/development-workflow/integrations/pr-review-platform.md`, `docs/workflow/development-workflow/README.md`, `docs/workflow/development-workflow/repository-modes.md`, `.ai-dev-workflow.local.example.yaml`, `scripts/development-workflow/workflow-config-resolver.py`, and `scripts/development-workflow/tests/test-workflow-config-resolver.sh`. |
| Resolver validation surface | `rg -n "review\\.on_draft|review\\.on_ready|normalize_haystack_config|validate_workflow_config|warnings" scripts/development-workflow/tests/test-workflow-config-resolver.sh scripts/development-workflow/workflow-config-resolver.py` | `validate_workflow_config` currently validates Haystack config only; resolver tests already cover validator wrapper behavior and config resolver output. |

## Layer-by-Layer Changes

### Documentation

- [ ] Update
      `docs/workflow/development-workflow/integrations/pr-review-platform.md`
      with a "Recommended Reviewer Count" section that states one external
      reviewer per repository/product is the default operating model, paired
      with internal runner review.
- [ ] Update `docs/workflow/development-workflow/README.md` so the central
      review configuration notes point to the same recommendation and do not
      imply that multi-bot external review is the default.
- [ ] Update `docs/workflow/development-workflow/repository-modes.md` so
      repository-mode guidance applies the same recommendation to
      `single_repo`, `workflow_hub`, and `product_repo` contexts.

### Infrastructure / Configuration

- [ ] Update `.ai-dev-workflow.local.example.yaml` so the Cursor pilot example
      uses one external reviewer in the ready phase and explains that additional
      external reviewers are advanced/local choices.

### Workflow Configuration Resolver

- [ ] Add a small warning helper in
      `scripts/development-workflow/workflow-config-resolver.py` that inspects
      `review.on_draft.github` and `review.on_ready.github` after YAML parsing.
- [ ] Emit a non-blocking warning when either effective list contains more than
      one external reviewer. The warning should name the config path and state
      that one external reviewer per phase is recommended.
- [ ] Call the warning helper from `validate_workflow_config` for both shared
      and local config. Do not raise `ConfigError`; valid multi-reviewer config
      must still exit successfully.

## Testing Strategy

**Test types**: Unit-style shell tests, config validation, markdown lint, and
smoke-test runbook.

**Key scenarios to test**:

1. Single external reviewer in each phase validates without warning. Maps to
   AC-1 and AC-3.
2. More than one external reviewer in `review.on_draft.github` validates
   successfully and emits a non-blocking warning. Maps to AC-4 and AC-5.
3. More than one external reviewer in `review.on_ready.github` validates
   successfully and emits a non-blocking warning. Maps to AC-4 and AC-5.
4. Documentation describes the recommended pattern and advanced multi-bot
   trade-offs. Maps to AC-1, AC-2, and AC-3.

**Smoke test runbook**:
`docs/testing/workflow/1117-document-one-external-reviewer-practice.smoke-test.md`

**Regression suite**: Update
`scripts/development-workflow/tests/test-workflow-config-resolver.sh` with
warning and no-warning fixtures.

## Seed Data

No seed data is required.

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/pr-review-platform.md`
      - add the canonical recommendation and advanced multi-bot trade-offs.
- [ ] `docs/workflow/development-workflow/README.md` - cross-reference the
      recommendation near review configuration notes.
- [ ] `docs/workflow/development-workflow/repository-modes.md` - clarify that
      the recommendation applies across repository modes.
- [ ] `.ai-dev-workflow.local.example.yaml` - adjust the local override example
      comments to model one external ready-phase reviewer by default.

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| Warning breaks scripts that expect quiet stdout | Medium | Medium | Emit warnings to stderr only and keep existing stdout key/value output unchanged. |
| Documentation duplicates provider-specific guidance | Low | Low | Put canonical reviewer-count guidance in `pr-review-platform.md` and cross-reference it from other docs. |
| Multi-reviewer users think support was removed | Low | Medium | Explicitly state multi-bot external review remains supported as advanced usage. |

## Implementation Order

1. Update `pr-review-platform.md` with the canonical one-external-reviewer
   recommendation, advanced multi-bot trade-offs, and support guarantee.
2. Update `README.md`, `repository-modes.md`, and
   `.ai-dev-workflow.local.example.yaml` to cross-reference or demonstrate the
   same recommendation without duplicating the full guidance.
3. Add the non-blocking multi-reviewer warning helper to
   `workflow-config-resolver.py`, called from `validate_workflow_config`.
4. Add `test-workflow-config-resolver.sh` coverage for no-warning,
   draft-phase warning, and ready-phase warning cases. Confirm the warning does
   not turn validation into a failure.
5. Update this runbook's "Updated in" line if implementation changes the final
   verification commands.
6. Update `CHANGELOG.md` under `[Unreleased]`:
   `- **External reviewer recommendation** (#1117): Documented the one-external-reviewer default pattern and added non-blocking workflow-config warnings for advanced multi-reviewer setups.`
7. Verify with:
   - `bash scripts/development-workflow/tests/test-workflow-config-resolver.sh`
   - `bash scripts/development-workflow/validate-workflow-config.sh`
   - `npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "CHANGELOG.md"`
   - `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`
   - `bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md`
   - `git diff --check`

# Portable Protocol 02 Parser Guidance - Implementation Plan

**Spec**:
[1_1310-protocol-02-product-repo-path_specs.md](1_1310-protocol-02-product-repo-path_specs.md)
**Smoke test runbook**:
[1310-protocol-02-product-repo-path.smoke-test.md](../../../testing/workflow/1310-protocol-02-product-repo-path.smoke-test.md)

---

## Summary

**Approach**: Make Protocol 02 self-contained by replacing its required
historical development-spec path with normative prose that states the existing
parser-risk and suppression acceptance intent directly. Add a focused workflow
regression test that rejects the obsolete live reference, confirms the required
topics remain present, and protects the general sync cross-reference contract
that still flags genuinely missing required paths.

**Estimated complexity**: S

**Rationale**: The production change is one bounded protocol correction plus a
regression test and release note. No parser implementation, sync-selection
logic, repository-mode routing, or new validation exception is required.

**Dependencies**: None.

**Template-fit check**: Passed. `.ai-dev-workflow.yaml` sets
`template.is_template: true`, and the change improves generic workflow
documentation distributed by the template without depending on any downstream
framework or runtime.

---

## Verification Log

Commands below were executed from the repository root. Recorded matches require
exit 0; the two intentional absence checks require exit 1 with no matches.

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse HEAD` | `21f23e3bbd3edc537381901bd08c9c4b11e28609` |
| Repository mode | `rg -n "^mode:|^template:|^[[:space:]]+is_template:[[:space:]]+true" .ai-dev-workflow.yaml` | `template.is_template: true`; mode is omitted, so this plan is owned by the current single repository |
| Tracker status | `gh issue view 1310 --json number,title,projectItems,state` | Issue #1310 is open and has status `Writing Plan` |
| Merged spec gate | `gh pr list --state merged --search 'head:spec/1310-protocol-02-product-repo-path base:develop' --limit 100 --json number,state,baseRefName,mergedAt` | The exact canonical head/base query returns spec PR #1318 merged to `develop` |
| Obsolete live reference | `rg -n -l "20260420120000_201-tech-lead-parser-regex-plan-requirements" . --hidden --glob '!.git/**'` | The only live occurrence is Protocol 02; the referenced historical file is absent from the current repository |
| Historical artifact availability | `find docs/specs/developments -maxdepth 2 -type f -name '1_201-tech-lead-parser-regex-plan-requirements_specs.md' -print` | No matching local historical artifact exists |
| Existing normative topics | `rg -n "Which directives are recognized|Where directives can appear|multiple suppressions|Edge-case enumeration|Unit tests" docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md` | Protocol 02 already states the required directive, placement, multiple-suppression, edge-case, and unit-test topics before the dead reference |
| Sync cross-reference gate | `rg -n "Post-apply path verification|If any path does not resolve|Collect all broken paths" .claude/commands/sync-template.md` | The canonical sync command already blocks or requires explicit acknowledgement for genuinely unresolved required paths |
| Repository-role selection | `python3 scripts/development-workflow/select-sync-manifest-entries.py --manifest sync-manifest.yaml --role <role>` for `single_repo`, `workflow_hub`, and `product_repo` | `single_repo` and `workflow_hub` select `docs/workflow/`; `product_repo` currently skips the hub-only tree. The spec's product-repository case is therefore conditional on Protocol 02 being present and does not require broadening distribution scope |
| Existing sync regression location | `rg -n "sync-template.*test|mode-scope tests" scripts/development-workflow/tests --glob '*.sh'` | Shell regressions under `scripts/development-workflow/tests/` are the established test surface |
| Design assets | Issue-body inspection plus `find docs/specs/developments/20260723112430_1310-protocol-02-product-repo-path -maxdepth 2 -type f -path '*/assets/*'` | No design assets or UI scope exist; no fidelity step applies |

---

## Layer-by-Layer Changes

### Distributed Planning Protocol

- [ ] Update
      `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
      to remove the required local reference to
      `docs/specs/developments/20260420120000_201-tech-lead-parser-regex-plan-requirements/1_201-tech-lead-parser-regex-plan-requirements_specs.md`.
- [ ] Replace that sentence with self-contained normative guidance stating
      that the existing parser-risk edge-case, automated-unit-test, and
      suppression-semantics requirements in Protocol 02 are the complete
      required acceptance intent (AC1, AC5).
- [ ] State that historical template or workflow-hub development artifacts are
      optional supplementary context only, may be absent in receiving
      repositories, and never block plan authoring or sync validation
      (AC1, AC2, AC7).
- [ ] Do not add a repository-mode allowlist or suppress missing references.
      Portability comes from eliminating the non-distributed required
      dependency, while the canonical sync command continues to report every
      genuinely missing required reference (AC3, AC4).

### Workflow Regression Coverage

- [ ] Add
      `scripts/development-workflow/tests/test-protocol-02-portable-parser-guidance.sh`
      using the repository's existing shell-test conventions.
- [ ] Assert the exact obsolete historical path is absent from live Protocol 02
      guidance, including a fixture copied into a temporary receiving
      repository with no `docs/specs/developments/` history (AC1, AC3).
- [ ] Assert Protocol 02 still contains normative requirements for parser-risk
      classification, concrete edge-case enumeration, automated unit tests,
      recognized suppression directives, allowed placement, and
      multiple-suppression interpretation (AC1, AC5).
- [ ] Assert the new portability wording identifies historical development
      artifacts as optional supplementary context whose absence is
      non-blocking (AC2, AC7).
- [ ] Assert `.claude/commands/sync-template.md` still contains its generic
      missing-required-path stop/acknowledgement behavior, so the fix cannot
      pass by weakening unrelated cross-reference validation (AC4).
- [ ] Run
      `scripts/development-workflow/tests/test-sync-template-mode-scopes.sh`
      unchanged to prove role-aware manifest selection remains intact. The
      implementation must not broaden `docs/workflow/` distribution as a side
      effect (AC3, AC4, AC7).

### Documentation and Release Notes

- [ ] Update `CHANGELOG.md` under `[Unreleased]` in the implementation PR with:
      `- **Make Protocol 02 parser guidance portable** (#1310): Inline the required parser-risk and suppression intent so synced repositories do not depend on an unavailable historical development fixture.`
- [ ] Do not update `.claude/commands/sync-template.md`,
      `sync-manifest.yaml`, the sync skills, or repository-mode docs unless
      implementation evidence contradicts the Verification Log. Their current
      selection and genuine-missing-reference behavior are intentionally
      preserved and covered by regression assertions.
- [ ] Do not change `REVIEW.md`. The feature preserves the existing parser-risk
      review contract and does not add or rename a checklist category.

### Database / Data Layer

- [ ] Not applicable. No schema, migration, seed, or persistent data changes.

### Backend / API

- [ ] Not applicable. No service endpoint or network API changes.

### Frontend / UI

- [ ] Not applicable. No user interface or design-asset changes.

### Infrastructure / Configuration

- [ ] Not applicable. No dependency, deployment, environment, secret, or CI
      configuration changes.

---

## Repository-Mode Verification Matrix

This matrix preserves every mode/availability row from the spec without
changing the sync selector itself. The final row records the current
`product_repo` selection boundary separately from the spec outcomes.

| Repository mode | Historical fixture available? | Protocol 02 present? | Required outcome | Next action | Evidence / mirror surfaces |
| --- | --- | --- | --- | --- | --- |
| Template or workflow hub | Yes | Yes | Parser-risk guidance is usable and every required reference validates | Continue plan authoring or sync validation | Protocol regression; Protocol 02; sync reference-validation contract |
| Template or workflow hub | No | Yes | Required intent remains available and optional historical material is non-blocking | Continue without reporting absent optional material as a defect | Receiving-repository fixture; Protocol 02; sync reference-validation contract |
| Product repository | No | Yes | Distributed guidance is fully usable and has no broken hub-fixture dependency | Continue plan authoring and accept the reference check | Receiving-repository fixture; Protocol 02; sync selection contract; reference-validation contract |
| Single repository | No | Yes | Guidance is usable without separate hub history; other missing required paths remain reportable | Continue plan authoring and report only genuinely missing required references | Receiving-repository fixture; Protocol 02; canonical sync-contract assertion |
| Product repository under the current selector | No | No | Existing `hub_only` selection remains unchanged; this feature does not distribute the full workflow tree | Preserve the current scoped sync | `test-sync-template-mode-scopes.sh`; `sync-manifest.yaml` |

**Complex workflow decision-gate classification**: Not applicable. The plan
does not add or modify sync routing or validation outcomes; it removes one
invalid required dependency and verifies that the existing gate remains
unchanged. The matrix is included to cover AC7's repository-mode combinations.

---

## Testing Strategy

**Test types**: Shell regression, temporary repository fixture, smoke,
ShellCheck, workflow shell guard, and Markdown lint.

**Key scenarios to test**:

1. Protocol 02 copied into a repository without historical development folders
   contains no obsolete fixture dependency and remains actionable (AC1, AC3).
2. Optional historical context is clearly non-normative and non-blocking
   (AC2, AC7).
3. Every existing parser-risk and suppression topic remains present and
   required (AC5).
4. The canonical sync command still documents its strict behavior for
   genuinely missing required references rather than applying a broad
   exception (AC4).
5. Single-repository, workflow-hub, and product-repository manifest selection
   behavior remains unchanged (AC3, AC4, AC7).
6. The implementation PR adds the exact downstream-facing changelog entry
   (AC6).

**Smoke test runbook**:
`docs/testing/workflow/1310-protocol-02-product-repo-path.smoke-test.md`

**Regression suite**:

- `scripts/development-workflow/tests/test-protocol-02-portable-parser-guidance.sh`
- `scripts/development-workflow/tests/test-sync-template-mode-scopes.sh`

**Parser-risk classification**: Not applicable. This implementation changes
documentation and uses fixed-string regression assertions; it does not add or
materially change a parser, scanner, tokenizer, regex engine, lint module, or
structured-text rule engine.

**Concurrent-event-source classification**: Not applicable. No event sources,
async queues, listeners, timers, or shared mutable runtime state are involved.

**Cross-cutting checklist classification**: Not applicable. The existing
parser-risk checklist and suppression topics remain behaviorally unchanged;
the plan removes only a non-portable historical reference.

**Residual verification strategy**: Before implementation readiness, run a
live fixed-string search across `docs/workflow/`, `.claude/commands/`,
`.agents/skills/`, and `.codex/skills/`. The obsolete historical path must have
zero live guidance occurrences. Occurrences retained only in the approved
spec, implementation plan, regression fixture, smoke runbook, or changelog
evidence are intentional test/history records and must be listed rather than
silently ignored.

---

## Seed Data

No persistent seed data is required.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Receiving repository fixture | Temporary repository containing corrected Protocol 02 but no historical `docs/specs/developments/` tree | `scripts/development-workflow/tests/test-protocol-02-portable-parser-guidance.sh` |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
      - make required parser/suppression intent self-contained and classify
      historical development material as optional.
- [ ] `CHANGELOG.md` - add the exact `[Unreleased]` correction listed above in
      the downstream implementation PR, never on this plan branch.
- [ ] `.claude/commands/sync-template.md` - no content change; preserve and test
      its existing post-apply missing-reference gate.
- [ ] `sync-manifest.yaml` and repository-mode docs - no content change; current
      role-aware selection is verified and intentionally unchanged.
- [ ] `AGENTS.md`, `docs/project/`, and `docs/best-practices/` - no update
      required because the change is confined to one canonical workflow
      protocol and its regression/release evidence.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Removing the dead link weakens parser/suppression intent | Low | High | Replace it with normative self-contained prose and assert every required topic in regression tests |
| Fix hides other genuinely broken docs paths | Low | High | Add no allowlist; assert the canonical sync missing-path gate remains present |
| Implementation accidentally broadens product-repo sync scope | Low | Medium | Leave manifest unchanged and run role-selection regressions |
| Static test becomes coupled to incidental prose | Medium | Low | Assert stable normative concepts and the exact forbidden path, not line numbers |
| Historical path remains on another live workflow surface | Low | Medium | Run the residual query across all live documentation/skill/command surfaces before readiness |

---

## Implementation Order

1. Update Protocol 02 to remove the obsolete historical development path,
   declare its existing parser-risk and suppression requirements normative and
   self-contained, and classify historical development material as optional
   supplementary context. Maps to AC1, AC2, AC5, and AC7.
2. Add
   `test-protocol-02-portable-parser-guidance.sh` with the temporary receiving
   repository, exact forbidden-path, normative-topic, optional-context, and
   canonical sync-contract assertions. Maps to AC1 through AC5 and AC7.
3. Run the new test and the existing sync-template mode-scope suite. Confirm
   the output shows portable guidance without any repository-mode selection
   change. Maps to AC3, AC4, and AC7.
4. Run the residual search and confirm no live workflow surface retains the
   obsolete local path. Review and explicitly classify any history/test
   occurrences outside the live surface. Maps to AC1, AC2, and AC3.
5. Run ShellCheck on the new shell test,
   `workflow-shell-guard-lint.py --base-ref origin/develop`, and Markdown lint
   on the changed protocol, plan artifacts, and `CHANGELOG.md`.
6. Execute the smoke runbook and record implementation evidence.
7. Update the project documentation listed under **Documentation Updates**.
8. In the downstream implementation PR, add under `CHANGELOG.md`
   `[Unreleased]` (do not edit the changelog on this plan branch):
   `- **Make Protocol 02 parser guidance portable** (#1310): Inline the required parser-risk and suppression intent so synced repositories do not depend on an unavailable historical development fixture.`

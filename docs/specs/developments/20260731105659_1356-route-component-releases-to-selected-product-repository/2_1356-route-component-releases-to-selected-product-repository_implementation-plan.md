# Route Component Releases To The Selected Product Repository - Implementation Plan

**Spec**:
[`1_1356-route-component-releases-to-selected-product-repository_specs.md`](./1_1356-route-component-releases-to-selected-product-repository_specs.md)
**Smoke test runbook**:
[`docs/testing/workflow/1356-route-component-releases-to-selected-product-repository.smoke-test.md`](../../../testing/workflow/1356-route-component-releases-to-selected-product-repository.smoke-test.md)

---

## Summary

**Approach**: Add one release-target resolution path for component releases,
then thread that resolved target through prepare-release guidance, release
post-merge cleanup, and component-release evidence. Reuse the #1353 product
release contract and #1354 one-target routing rules instead of creating a
parallel repository-selection model.

**Estimated complexity**: M

**Rationale**: The work is mostly Bash/Python workflow tooling and
documentation, but it touches release preparation, release cleanup, tracker
reconciliation, and evidence that later delivery-bundle work will consume. The
main risk is allowing release preparation and cleanup to derive product targets
from different sources.

**Dependencies**: #1353 and #1354 are merged through implementation on
`develop-multi-repo-releases`; #1356 spec PR #1409 is merged and sets #1356 to
`Spec Ready`.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `fbdcff7` |
| Template-fit check | `rg -n "template:|is_template" .ai-dev-workflow.yaml` | `template.is_template: true`; the feature is generic workflow tooling and release orchestration, not downstream framework-specific code. |
| Release and cleanup surface scan | `rg -l "prepare-release\\|prepare release\\|release branch\\|release contract\\|TARGET_RELEASE\\|deployment evidence\\|cleanup evidence\\|component release\\|Release outcome\\|Routing outcome" scripts/development-workflow docs/workflow/development-workflow .claude/agents .cursor/agents .codex/skills .agents/skills REVIEW.md \| sort` | Relevant implementation surfaces include `05-prepare-release-protocol.md`, `prepare-release-post-merge-cleanup.sh`, `post-merge-cleanup.sh`, `workflow-config-resolver.py`, `validate-workflow-config.sh`, `repository-modes.md`, `cross-repo-pr-flow.md`, `workflow-hub-setup.md`, `.agents/skills/prepare-release/SKILL.md`, and tests under `scripts/development-workflow/tests/`. |
| Existing resolver release contract support | `rg -n "normalize_release_contract\\|validate_release_branch_pattern\\|TARGET_LOCAL_PATH\\|release_contract" scripts/development-workflow/workflow-config-resolver.py scripts/development-workflow/validate-workflow-config.sh` | The resolver already normalizes product release contract fields and separates local checkout resolution behind `--require-local`; the implementation should extend this path rather than parse config independently. |
| Cleanup baseline | `rg -n "product repository selection is required\\|BRANCH_LIFECYCLE\\|Spec branch\\|Implementation plan branch" scripts/development-workflow/post-merge-cleanup.sh` | Implementation branch cleanup already requires product selection in `workflow_hub`; release cleanup remains current-repository oriented and needs product-target support. |
| Existing test surfaces | `find scripts/development-workflow/tests -maxdepth 1 -type f \| sort \| rg "release|cleanup|config|workflow-hub|product-repo|orchestration"` | Relevant tests include `test-workflow-config-resolver.sh`, `test-prepare-release-tracker-cleanup.sh`, `test-post-merge-cleanup.sh`, `test-workflow-hub-product-repo-commands.sh`, `test-workflow-hub-docs.sh`, and agent guidance tests. |
| Design assets | `gh issue view 1356 --json body --jq '.body' \| sed -n '/## Design assets/,+8p'` | No design assets section or tracker design references found; no fidelity step is required. |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Plan artifact base | `develop-multi-repo-releases` | `/run-epic 1352` effective policy and #1409 base branch | 2026-07-31, repo `fbdcff7` | Current #1356 plan branch only | `Verified` |
| Release contract authority | Product repository key and portable release fields come from #1353's product release contract; local checkout comes from local-only config | #1353 merged spec/implementation and `workflow-config-resolver.py` release contract support | 2026-07-31, repo `fbdcff7` | #1356 plan plus same-epic downstream #1357 evidence consumer | `Verified` |
| One-target routing authority | Component releases apply #1354's one-product-repository and pre-mutation blocking rules | #1354 merged spec/implementation and #1356 spec dependencies | 2026-07-31, repo `fbdcff7` | #1356 release-routing plan only | `Verified` |

---

## Complex Workflow Decision-Gate Matrix

This plan modifies release decision-gate behavior because release mutation
depends on repository mode, product selection, release contract validity, local
checkout availability, and persisted release evidence.

| Gate input | Routing outcome | Allowed outcome | Required next action | Mirror surfaces |
| --- | --- | --- | --- | --- |
| Single-repository mode | `single_repo_release` | Continue | Use current release and hotfix workflow unchanged | `05-prepare-release-protocol.md`, release cleanup helper, smoke runbook |
| Workflow hub release with no product selection | `missing_product_selection` | Stop | Request one product repository before branch, PR, tag, changelog, deployment, cleanup, or tracker mutation | Release target helper, prepare-release protocol, cleanup helper |
| Workflow hub release with multiple product targets | `multiple_product_targets` | Stop | Split or narrow to one component release per product repository | Release target helper and smoke runbook |
| Selected key absent from product release contract | `unknown_product_repository` | Stop | Correct the hub product release contract or selected key | Resolver output, release target helper |
| One selected value cannot resolve to one product repository | `ambiguous_product_selection` | Stop | Correct selection or contract before mutation | Resolver output and release target helper |
| Release contract would route product artifacts to the wrong owner or lacks required portable fields | `invalid_release_contract` | Stop | Correct versioned release contract before mutation | Resolver validation, prepare-release protocol, smoke runbook |
| Product checkout required but unavailable locally | `unavailable_product_repository_checkout` | Stop | Correct local-only checkout config before local mutation | Resolver `--require-local`, hub status/sync guidance |
| Exactly one valid product target and required local checkout available | `component_release_routed` | Continue | Mutate product-owned release artifacts in the selected product repository and hub-owned tracker reconciliation in the hub | Release summary, PR body, cleanup log, component release evidence |

Validation precedence is the table order above. Every mutating release or
cleanup command must produce exactly one canonical routing outcome code before
it mutates files, branches, pull requests, tags, deployment evidence, cleanup
evidence, or tracker state.

---

## Layer-by-Layer Changes

### Database / Data Layer

- [ ] No database, migration, or seed-data changes.

### Backend / API

- [ ] No HTTP API changes.

### Shared Workflow Tooling

- [ ] Add `scripts/development-workflow/component-release-target.sh` as the
      single release-target entry point. It should call
      `workflow-config-resolver.py validate --repo <name> --require-local` when
      workflow-hub product mutation needs a local checkout, accept
      single-repository mode without `--repo`, and emit a stable shell and JSON
      contract containing selected product key, canonical repository identity,
      local checkout path/source, release base, release branch pattern, artifact
      owners, routing outcome code, release correlation key, contract revision
      field named `contract_revision`, and human action when blocked. The same
      `contract_revision` field name and string format must appear in shell
      output, JSON output, evidence records, cleanup validation, smoke tests,
      and fixtures. Classified stop outcomes must emit structured output with
      `mutation_allowed=false`; malformed input and internal helper failures
      must exit nonzero. Map to AC1-AC4 and AC8.
- [ ] Extend `scripts/development-workflow/workflow-config-resolver.py` only as
      needed to expose contract revision or digest and any missing normalized
      release target fields. Keep local checkout fields sourced from local-only
      config and keep forbidden local/secret validation in the existing release
      contract path. Map to AC1-AC4.
- [ ] Extend `scripts/development-workflow/prepare-release-post-merge-cleanup.sh`
      with `--repo <name>`, `--repo-root <path>`, and `--evidence-file <path>`
      arguments. In workflow-hub mode, component release cleanup must require a
      persisted evidence file or an equivalent mandatory target-binding file
      before deleting branches, tags, cleanup evidence, or tracker state. The
      helper must resolve the current product release target first, reject any
      caller-supplied `--repo-root` that differs from the resolved hub checkout,
      validate canonical repository identity, release correlation key, and
      `contract_revision` against the current resolver output, then run product
      branch/tag cleanup in the selected product repository before returning to
      the hub for tracker release stamping and status transitions. Map to AC5
      and AC6.
- [ ] Add `scripts/development-workflow/component-release-evidence.sh` as a
      focused helper for rendering and validating the component release evidence
      record. The helper should accept explicit fields from release preparation
      and cleanup, derive target identity from the canonical resolver output or
      persisted target binding, validate required values, allowed outcome enums,
      and cross-field relationships, then write deterministic JSON that later
      #1357 delivery-bundle reconciliation can consume. It must reject
      mismatched product repository key, canonical repository identity, artifact
      owner, release correlation key, or `contract_revision` before writing
      evidence. Map to AC8.
- [ ] Add per-release cleanup concurrency control to the release cleanup path.
      Use a product-repository remote lock or lease keyed by release correlation
      key before deleting remote release branches, tags, cleanup evidence, or
      updating hub tracker state. Duplicate cleanup invocations for the same
      correlation key must either observe the existing completed evidence and
      exit idempotently or fail before mutation with a clear lock/lease owner
      message. Map to AC5 and AC6.
- [ ] Keep `scripts/development-workflow/post-merge-cleanup.sh` product-owned
      implementation cleanup behavior intact. Add documentation or a guard only
      if needed to distinguish implementation branch cleanup from release branch
      cleanup so operators use the correct helper. Map to AC5.

### Workflow Documentation

- [ ] `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`:
      replace any ambiguous current-checkout release steps with release target
      resolution, product checkout binding, evidence record creation, and
      fail-closed behavior for missing, multiple, unknown, ambiguous, invalid,
      or unavailable targets. Preserve current single-repository and hotfix
      behavior. Map to AC1-AC4, AC7, and AC8.
- [ ] `docs/workflow/development-workflow/cross-repo-pr-flow.md`: add the
      component-release release-target checkpoint and evidence handoff from the
      hub to selected product repository and back to hub tracker reconciliation.
      Map to AC1, AC4, and AC8.
- [ ] `docs/workflow/development-workflow/repository-modes.md`: add the
      canonical routing outcome codes, release evidence record pointer, and
      cleanup rerun contract for component releases. Map to AC1-AC8.
- [ ] `docs/workflow/development-workflow/workflow-hub-setup.md`: document the
      operator workflow for selecting one product repository for a component
      release and storing local checkout config outside versioned release
      contract fields. Map to AC2-AC4.
- [ ] `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md`
      and `05b-graduate-development-protocol.md`: add cross-links where release
      evidence or integration branch graduation hands off to component release
      preparation. Map to AC8.

### Agent And Skill Guidance

- [ ] `.agents/skills/prepare-release/SKILL.md`: require the agent to resolve
      the component release target and evidence record before product release
      mutation in workflow-hub mode. Map to AC1-AC8.
- [ ] `.agents/skills/prepare-release/agents/openai.yaml`: keep command
      metadata aligned if it contains behavior text for release ownership.
      Map to AC1-AC8.
- [ ] `docs/workflow/development-workflow/README.md` and
      `scripts/development-workflow/README.md`: add short references to
      component release routing only if the implementation adds new helper
      commands that operators must discover from command tables. Map to AC1.

---

## Testing Strategy

**Test types**: Unit-style shell/Python fixture tests, integration-style
workflow command tests, and smoke/manual release runbook verification.

**Key scenarios to test**:

1. Single-repository release target resolution returns `single_repo_release`
   and does not require a product repository selector. Maps to AC7.
2. Workflow-hub component release with exactly one selected product repository
   and valid release contract returns `component_release_routed`, product-owned
   artifact owners, local checkout source, release base, branch pattern,
   correlation key, and contract revision. Maps to AC1 and AC4.
3. Missing, multiple, unknown, ambiguous, invalid-contract, and unavailable
   checkout cases stop before branch, PR, tag, changelog, deployment, cleanup,
   or tracker mutation and produce the canonical routing outcome code. Maps to
   AC2 and AC3.
4. Release cleanup with a matching evidence file validates repository identity,
   release correlation key, and `contract_revision` before product cleanup
   mutation. Maps to AC5.
5. Release cleanup with mismatched persisted evidence stops before mutation and
   leaves hub tracker state unchanged. Maps to AC5 and AC6.
6. Component release evidence validation accepts complete `pending`,
   `completed`, `failed`, and `blocked` records, rejects invalid routing,
   release, CI, deployment, and cleanup outcomes, rejects repository-key,
   artifact-owner, correlation, and `contract_revision` cross-field
   mismatches, and requires the hub tracker reference. Maps to AC8.
7. Duplicate cleanup invocations for the same release correlation key acquire
   only one active lock/lease and keep completed reruns idempotent. Maps to AC5
   and AC6.
8. Prepare-release documentation preserves single-repository release and hotfix
   behavior while adding workflow-hub product release target resolution. Maps to
   AC7.

**Smoke test runbook**:
`docs/testing/workflow/1356-route-component-releases-to-selected-product-repository.smoke-test.md`

**Regression suite**:

- [ ] Extend `scripts/development-workflow/tests/test-workflow-config-resolver.sh`
      for release contract revision/digest and local checkout separation.
- [ ] Add `scripts/development-workflow/tests/test-component-release-target.sh`
      for release target routing outcomes and fail-closed mutation boundaries.
- [ ] Add `scripts/development-workflow/tests/test-component-release-evidence.sh`
      for evidence record validation, cross-field relationship checks, and
      deterministic JSON output.
- [ ] Extend `scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh`
      for workflow-hub product release cleanup with matching and mismatched
      evidence plus duplicate/concurrent cleanup lock behavior.
- [ ] Extend `scripts/development-workflow/tests/test-workflow-hub-product-repo-commands.sh`
      for product checkout resolution and local-only config errors.
- [ ] Extend `scripts/development-workflow/tests/test-workflow-agent-product-repo-guidance.sh`
      and `scripts/development-workflow/tests/test-workflow-hub-docs.sh` for
      mirrored prepare-release and documentation guidance.

### Parser-Risk Addendum

This plan is parser-risk because it introduces shell/JSON evidence validation,
release branch/correlation parsing, and structured release target output.

- **Edge-case enumeration**:
  - Routing outcomes: each canonical routing outcome from the spec table, plus
    invalid or missing outcome values.
  - Release outcomes: `pending`, `completed`, `failed`, `blocked`, empty value,
    and unknown value.
  - CI outcomes: `pending`, `passed`, `failed`, `not_applicable`, empty value,
    and unknown value.
  - Deployment outcomes: `pending`, `recorded`, `failed`, `not_applicable`,
    empty value, and unknown value.
  - Cleanup outcomes: `not_started`, `partial`, `complete`, `blocked`, empty
    value, and unknown value.
  - Correlation identity: matching repository/correlation/revision values,
    mismatched repository identity, mismatched artifact owner, mismatched
    correlation key, mismatched `contract_revision`, and missing persisted
    evidence.
  - Branch pattern carry-through: default `release/v{version}`, product pattern
    using `{product_repo}`, unknown placeholder, and unresolved placeholder.
- **Unit test mapping**:
  - `scripts/development-workflow/tests/test-component-release-target.sh`:
    routing outcomes, local checkout availability, branch pattern carry-through,
    and fail-closed mutation boundaries.
  - `scripts/development-workflow/tests/test-component-release-evidence.sh`:
    outcome enum validation, required field validation, deterministic JSON, and
    persisted-target mismatch cases.
  - `scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh`:
    cleanup evidence matching/mismatching and hub tracker mutation ordering.
- **Suppression semantics**: Not applicable. This feature does not introduce
  inline suppression directives.

### Cleanup Concurrency And Idempotency Addendum

This feature does not introduce event listeners, sockets, timers, or async
queues, but release cleanup can still be invoked concurrently by two operators
or CI jobs. The implementation must therefore add a per-release concurrency
control for cleanup and tracker reconciliation.

- **Shared mutable state guards**: Acquire a product-repository remote lock or
  lease keyed by the release correlation key before deleting remote branches,
  tags, cleanup evidence, or updating hub tracker state. The lock evidence must
  name the product repository, correlation key, `contract_revision`, caller, and
  expiry or completion state.
- **Re-entrancy / in-flight tracking**: A second cleanup invocation for the same
  correlation key must detect an active lock and stop before mutation unless it
  observes completed evidence for the same repository identity and
  `contract_revision`, in which case it exits idempotently.
- **Event deduplication**: Duplicate cleanup attempts for the same release
  correlation key are deduplicated by the lock/lease and persisted evidence.
- **Listener and resource cleanup**: Not applicable; no listeners, timers, or
  handles are introduced. Lock release or completion marking is part of the
  bounded cleanup command.
- **Race conditions at initialization**: The cleanup helper must acquire the
  lock before any mutable product or hub tracker operation. Validation without a
  lock is read-only.
- **Race conditions at teardown**: Cleanup must mark completed evidence before
  releasing the lock. If cleanup fails, the lock/lease remains visible with the
  failure reason or expires according to the documented lease policy.
- **Error propagation across async boundaries**: Not applicable; scripts are
  synchronous Bash/Python commands, but lock acquisition and release failures
  must return nonzero and stop later mutation.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Workflow hub release config | Valid hub with two product repositories, one explicit release pattern, one default release pattern, and matching local-only checkout entries | Temporary fixtures in `test-component-release-target.sh` and `test-workflow-config-resolver.sh` |
| Invalid release config | Missing selection, multiple selection, unknown product key, invalid artifact owner, forbidden local path in versioned contract | Temporary fixtures in `test-component-release-target.sh` |
| Evidence records | Complete pending/completed/failed/blocked component release records plus invalid enum and missing-field variants | Temporary fixtures in `test-component-release-evidence.sh` |
| Cleanup state | Matching and mismatched persisted repository identity, release correlation key, `contract_revision`, and lock/lease records | Temporary fixtures in `test-prepare-release-tracker-cleanup.sh` |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`
      - component release target resolution, evidence, and fail-closed release
      mutation behavior.
- [ ] `docs/workflow/development-workflow/cross-repo-pr-flow.md` - selected
      product release handoff and hub tracker reconciliation.
- [ ] `docs/workflow/development-workflow/repository-modes.md` - release
      routing outcomes, evidence record, and cleanup rerun contract.
- [ ] `docs/workflow/development-workflow/workflow-hub-setup.md` - operator
      setup and local checkout separation for component releases.
- [ ] `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md`
      and `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`
      - cross-links to component release evidence where release handoff applies.
- [ ] `.agents/skills/prepare-release/SKILL.md` and, if behavior text changes,
      `.agents/skills/prepare-release/agents/openai.yaml` - command guidance
      for workflow-hub component releases.
- [ ] `docs/workflow/development-workflow/README.md` and
      `scripts/development-workflow/README.md` only if new helper commands need
      command-table discoverability.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Release preparation and cleanup resolve different product targets | Med | High | Persist canonical repository identity, release correlation key, and `contract_revision` during preparation; cleanup must validate all three before mutation. |
| Concurrent cleanup invocations mutate the same release artifacts | Med | High | Use a per-release remote lock/lease keyed by release correlation and make completed reruns idempotent. |
| Product local checkout leaks into versioned release contract | Low | High | Reuse resolver forbidden-data checks and source local checkout only from local config. |
| Evidence record becomes too loose for #1357 delivery bundles | Med | Med | Validate required fields and allowed outcome enums in `component-release-evidence.sh`; include smoke and unit tests for every outcome. |
| Existing single-repository release flow regresses | Low | High | Keep `single_repo_release` as the first routing outcome and add tests that run without `--repo`. |
| Release cleanup mutates hub tracker before product cleanup is confirmed | Med | High | Cleanup implementation order must perform product validation/cleanup first and update hub tracker only after product evidence is complete. |

---

## Code Samples

No production code samples are included. Implementation should follow the
existing Bash/Python helper style in `scripts/development-workflow/`.

---

## Implementation Order

1. Extend resolver/release-target support:
   - Add or expose contract revision/digest and normalized release target fields
     through `workflow-config-resolver.py`.
   - Add `component-release-target.sh` using the resolver as the only authority
     for product keys, portable release fields, and local checkout source.
   - Verify with focused fixtures before touching release cleanup.
2. Add component release evidence:
   - Add `component-release-evidence.sh`.
   - Validate required fields, allowed enum values, and cross-field
     relationships against resolver output or persisted binding.
   - Ensure output is deterministic JSON and includes the release correlation
     key and hub tracker reference.
3. Update release cleanup:
   - Extend `prepare-release-post-merge-cleanup.sh` with product repository and
     evidence-file options.
   - Resolve product target before querying/deleting release branches.
   - Validate persisted release target before mutation.
   - Acquire the per-release lock/lease before product branch/tag cleanup or
     hub tracker reconciliation.
   - Keep tracker release stamping hub-owned and after product cleanup
     confirmation.
4. Update prepare-release protocol and command guidance:
   - Update `05-prepare-release-protocol.md` and `.agents/skills/prepare-release/SKILL.md`.
   - Add command-table references only where new helpers need discoverability.
5. Update workflow-hub documentation:
   - Update repository modes, cross-repo PR flow, workflow hub setup, and
     release handoff cross-links per **Documentation Updates**.
6. Add and extend tests:
   - Add target/evidence helper tests.
   - Extend release cleanup, config resolver, product repo commands, docs, and
     agent guidance tests.
7. Run verification:
   - `for script in scripts/development-workflow/component-release-target.sh scripts/development-workflow/component-release-evidence.sh scripts/development-workflow/prepare-release-post-merge-cleanup.sh; do bash -n "$script"; done`
   - `bash scripts/development-workflow/tests/test-component-release-target.sh`
   - `bash scripts/development-workflow/tests/test-component-release-evidence.sh`
   - `bash scripts/development-workflow/tests/test-workflow-config-resolver.sh`
   - `bash scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh`
   - `bash scripts/development-workflow/tests/test-workflow-hub-product-repo-commands.sh`
   - `bash scripts/development-workflow/tests/test-workflow-agent-product-repo-guidance.sh`
   - `bash scripts/development-workflow/tests/test-workflow-hub-docs.sh`
   - `npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "CHANGELOG.md"`
   - `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`
   - `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop-multi-repo-releases`
   - `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop-multi-repo-releases`
8. Update `CHANGELOG.md` under `[Unreleased]` during implementation with:
   `- **Route component releases to selected product repositories** (#1356): Add workflow-hub component release routing, cleanup, and evidence handling for selected product repositories.`

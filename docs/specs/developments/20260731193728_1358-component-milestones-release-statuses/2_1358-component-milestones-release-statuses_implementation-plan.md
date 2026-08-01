# Component Milestones And Release Statuses - Implementation Plan

**Spec**:
[`1_1358-component-milestones-release-statuses_specs.md`](./1_1358-component-milestones-release-statuses_specs.md)
**Smoke test runbook**:
[`docs/testing/workflow/1358-component-milestones-release-statuses.smoke-test.md`](../../../testing/workflow/1358-component-milestones-release-statuses.smoke-test.md)

---

## Summary

**Approach**: Add a hub-owned component milestone reconciliation helper that
consumes `component_release_evidence.v1` and `delivery_bundle_manifest.v1`
records, computes explicit child and parent release-state outcomes, and applies
namespaced GitHub milestones only to matching component child issues. Reuse the
existing component release evidence, delivery bundle manifest, and GitHub
milestone helper surfaces instead of creating a parallel release model.

**Estimated complexity**: M

**Rationale**: The feature is bounded to workflow shell/Python tooling, tests,
and documentation, but it is high consequence because it mutates tracker
milestones and release state from structured evidence. The main risks are
overlapping reconciliation outcomes and accidentally stamping parent or delivery
issues.

**Dependencies**: #1353, #1354, #1356, and #1357 are merged through
implementation on `develop-multi-repo-releases`. #1359 remains downstream
adoption and assurance work and must not be pulled into this implementation.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `ba02c8c` |
| Template-fit check | `rg -n "template:\|is_template" .ai-dev-workflow.yaml` | `.ai-dev-workflow.yaml` declares `template.is_template: true`; this item is generic workflow tooling for the template. |
| Same-surface PR check | `gh pr list --base develop-multi-repo-releases --state open --search "1358" --json number,title,headRefName,baseRefName,state,url` | No open #1358 PR existed before this plan branch mutation. |
| Design assets | `gh issue view 1358 --json body --jq '.body' \| sed -n '/## Design assets/,+8p'` | No design assets section or tracker design references found; no fidelity step is required. |
| Existing milestone and release-state surface | `rg -l "component_release_evidence\|delivery_bundle_manifest\|component_release_routed\|child_release_state\|hub_tracker_reconciliation\|milestone\|workflow_github_milestone" scripts/development-workflow docs/workflow/development-workflow docs/testing/workflow .agents/skills .codex/skills \| sort` | Relevant implementation surfaces include `delivery-bundle-manifest.sh`, `component-release-evidence.sh`, `workflow-lib.sh`, release stamping docs, repository mode docs, and workflow smoke tests. |
| Existing workflow tests | `find scripts/development-workflow/tests -maxdepth 1 -type f \| sort \| rg "delivery-bundle|component-release|prepare-release|workflow-hub|post-merge|config"` | Relevant test surfaces include component release evidence, delivery bundle manifests, prepare-release cleanup, workflow hub docs, config resolver, and GitHub Projects milestone helpers. |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Plan artifact base | `develop-multi-repo-releases` | `/run-epic 1352` effective policy, #1415 merged spec PR base, and branch guard | 2026-08-01T00:04:34Z, repo `ba02c8c` | Current #1358 plan branch and same-base open #1358 PR query only | `Verified` |
| Artifact owner | Hub owns tracker issues, specs/plans, delivery bundles, milestones, and parent release-state reconciliation; product repositories own component release artifacts | #1353 ownership contract, #1356 component evidence contract, #1357 delivery bundle manifest, and accepted #1358 spec | 2026-08-01T00:04:34Z, repo `ba02c8c` | Epic #1352 child #1358 plus merged dependency artifacts #1353, #1356, and #1357 | `Verified` |
| Downstream boundary | #1359 owns broad adoption, migration, and full assurance documentation; #1358 owns only the runtime/status semantics needed for milestone reconciliation | #1358 spec dispatch context and #1359 issue scope | 2026-08-01T00:04:34Z, repo `ba02c8c` | Current epic remaining children #1358 and #1359 | `Verified` |

---

## Complex Workflow Decision-Gate Matrix

This plan modifies workflow decision-gate behavior because reconciliation
depends on repository mode, product selection, evidence completeness, component
target matching, bundle finalization readiness, and target issue kind.

| Gate input | Reconciliation outcome | Allowed outcome | Required next action | Mirror surfaces |
| --- | --- | --- | --- | --- |
| No workflow-hub mode is active | `single_repo_milestone` | Continue | Use existing `vX.Y.Z` release milestone behavior unchanged | `workflow-lib.sh`, release stamping smoke test |
| Workflow-hub mode with no or ambiguous product repository | `missing_product_selection` | Stop | Select exactly one product repository before milestone or status mutation | New helper, smoke runbook |
| Component-target reconciliation has no evidence record | `component_release_pending` | Stop | Complete or attach `component_release_evidence.v1`; keep child pending and parent unreleased or partially released | New helper, bundle manifest output |
| Evidence product repository does not match the target child | `component_target_mismatch` | Stop | Correct the child target or evidence before mutation | New helper, tests |
| Evidence tag is missing or invalid | `component_tag_missing` | Stop | Provide the released component tag before milestone creation | New helper, tests |
| Evidence record exists but is incomplete, invalid, stale, conflicting, failed, blocked, or pending | `component_release_not_ready` | Stop | Repair or retry component release evidence; mark child blocked only when an invalid record exists | New helper, tests |
| Bundle-finalization reconciliation confirms every declared component is released and finalization passes | `parent_released` | Continue | Mark parent released without adding any milestone to parent or bundle issue | New helper, delivery bundle manifest |
| Component-target reconciliation has complete matching evidence | `component_released` | Continue | Create or reuse `<product-repo>@<tag>` milestone and assign it only to the component child | New helper, GitHub Projects tests |

Validation precedence follows the table order above. The implementation must
make `parent_released` and `component_released` disjoint by requiring an explicit
reconciliation scope: component-target reconciliation may stamp a child
milestone; bundle-finalization reconciliation may update parent release state
but must never stamp another component milestone.

---

## Layer-by-Layer Changes

### Database / Data Layer

- [ ] No database, migration, or persistent seed-data changes. All evidence is
      file-based workflow evidence or GitHub tracker state.

### Backend / API

- [ ] No HTTP API changes.

### Shared Workflow Tooling

- [ ] Add `scripts/development-workflow/component-milestone-reconciliation.sh`
      as the single hub-owned release-status reconciliation entry point. Use a
      Bash wrapper with embedded Python, matching the `delivery-bundle-manifest.sh`
      style. Map to AC1-AC13.
- [ ] Implement a read-only `inspect-component` path that consumes
      `component_release_evidence.v1`, `--issue`, `--product-repo`,
      `--component-tag`, `--target-kind component_child`, and optional
      `--delivery-manifest`. It must emit stable JSON and shell output with
      `schema_version=component_milestone_reconciliation.v1`, one
      `reconciliation_outcome`, one child release state, one parent release
      state, `milestone_title`, `mutation_allowed`, `required_next_action`, and
      `blockers`. Map to AC1-AC6 and AC13.
- [ ] Implement an apply path for component children that creates or reuses a
      GitHub milestone titled `<product-repo>@<tag>` in the hub repository and
      assigns it only to the selected component child issue after complete
      evidence matches repository identity, selected product key, component tag,
      release correlation key, contract revision, cleanup outcome, tracker
      reconciliation outcome, and hub tracker reference. Reuse or factor the
      existing GitHub milestone lookup/create/assign logic from `workflow-lib.sh`
      so current release-stamping behavior remains intact. Map to AC1, AC3-AC5,
      and AC13.
- [ ] Reject parent epic and delivery bundle targets before milestone mutation.
      Add explicit target-kind validation so `parent_epic` and
      `delivery_bundle` may be inspected for release state but cannot receive
      component or plain version milestones in workflow-hub mode. Map to AC7
      and AC8.
- [ ] Implement a bundle-finalization inspection path that consumes
      `delivery_bundle_manifest.v1` inspection output, calculates parent states
      `not_released`, `partially_released`, `released`, or `blocked`, and
      records recovery transitions from `blocked` after corrected evidence.
      This path must not modify historical component release evidence or create
      shared suite versions, branches, tags, or GitHub Releases. Map to AC9 and
      AC10.
- [ ] Add idempotency guards: reapplying the same complete component evidence to
      an already-stamped child should report `component_released` without
      creating a duplicate milestone or changing parent/bundle milestones.
      Reapplying parent finalization after a completed bundle should report the
      same `parent_released` state without extra component milestone writes. Map
      to AC1, AC5, AC7, AC8, AC10, and AC13.
- [ ] Preserve non-hub release behavior. When workflow-hub mode is inactive,
      delegate to the existing `record_release_for_issue_best_effort` /
      release-stamping path and do not require a namespaced milestone or
      delivery bundle. Map to AC11 and AC12.

### Workflow Documentation

- [ ] `docs/workflow/development-workflow/repository-modes.md`: document
      namespaced component milestones, hub-owned parent release states, the
      workflow-hub single-product case, and non-hub `vX.Y.Z` compatibility.
      Map to AC1, AC7-AC12.
- [ ] `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`:
      add the component milestone/status reconciliation handoff after component
      release evidence and cleanup complete. Map to AC1-AC6 and AC13.
- [ ] `docs/workflow/development-workflow/cross-repo-pr-flow.md`: add the
      selected product repository milestone handoff and parent bundle
      finalization boundary. Map to AC1-AC10.
- [ ] `scripts/development-workflow/README.md`: document the new helper,
      subcommands, inputs, output keys, blocked outcomes, and examples. Map to
      AC1-AC13.
- [ ] `docs/testing/workflow/release-stamping.smoke-test.md`: clarify that
      plain `vX.Y.Z` release stamping remains the non-hub path while
      workflow-hub component releases use namespaced milestones. Map to AC11
      and AC12.
- [ ] Update `CHANGELOG.md` under `[Unreleased]` during implementation:
      `- **Add component milestone release statuses** (#1358): Add workflow-hub component milestone and parent release-state reconciliation for multi-repository releases.`

### Agent And Skill Guidance

- [ ] `.agents/skills/prepare-release/SKILL.md`: mention the post-release
      workflow-hub handoff to component milestone reconciliation after component
      release evidence is complete. Map to AC1-AC6 and AC13.
- [ ] No changes expected for project setup, spec writing, or plan writing
      skills unless implementation finds they contain stale milestone wording.

---

## Testing Strategy

**Test types**: Unit-style shell/Python fixture tests, mocked GitHub API
integration tests, smoke/manual workflow runbook verification.

**Key scenarios to test**:

1. Non-hub mode returns `single_repo_milestone` and preserves current `vX.Y.Z`
   release stamping. Maps to AC11 and AC12.
2. Workflow-hub component evidence with matching product repository, tag,
   correlation key, contract revision, cleanup, tracker reconciliation, and hub
   reference returns `component_released` and stamps only the child. Maps to
   AC1, AC4, AC5, and AC13.
3. Missing product selection, no evidence record, missing tag, target mismatch,
   incomplete evidence, invalid evidence, stale evidence, failed evidence,
   blocked evidence, pending evidence, and conflicting evidence each produce
   exactly one stop outcome before tracker mutation. Maps to AC2, AC3, AC4,
   and AC6.
4. Parent epics and delivery bundle issues reject all milestone writes in
   workflow-hub mode, including plain version milestones. Maps to AC7 and AC8.
5. A single-product workflow-hub delivery uses `<product-repo>@<tag>` plus
   delivery bundle finalization, not the non-hub `vX.Y.Z` path. Maps to AC11.
6. Partial bundle state reports `partially_released` when at least one component
   is released and another current component remains unreleased. Maps to AC9.
7. Completed bundle finalization reports `parent_released` without creating
   another component milestone. Maps to AC10.
8. Parent `blocked` recovers to `not_released`, `partially_released`, or
   `released` after corrected bundle evidence. Maps to AC9 and AC10.

**Smoke test runbook**:
`docs/testing/workflow/1358-component-milestones-release-statuses.smoke-test.md`

**Regression suite**:

- [ ] Add
      `scripts/development-workflow/tests/test-component-milestone-reconciliation.sh`
      for component outcome classification, milestone title generation,
      parent/bundle no-milestone guards, single-product workflow-hub behavior,
      parent state transitions, and idempotent reapplication.
- [ ] Extend `scripts/development-workflow/tests/test-delivery-bundle-manifest.sh`
      only if the implementation adds release-state fields or helper output to
      `delivery-bundle-manifest.sh`.
- [ ] Extend `scripts/development-workflow/tests/test-workflow-lib-github-projects.sh`
      or add mock coverage beside it for namespaced milestone create/reuse and
      issue assignment.
- [ ] Extend `scripts/development-workflow/tests/test-workflow-hub-docs.sh` for
      new repository-mode, prepare-release, and helper README guidance.

### Parser-Risk Addendum

This plan is parser-risk because it introduces structured JSON evidence
validation, outcome classification, milestone-title validation, and mocked
GitHub API output parsing.

- **Edge-case enumeration**:
  - Repository mode: non-hub `single_repo`, workflow-hub component target,
    workflow-hub parent target, and workflow-hub delivery bundle target.
  - Product selection: missing, ambiguous, unknown, mismatched, and matching
    selected product repository key.
  - Evidence record: no file, malformed JSON, non-object JSON, wrong schema,
    missing identity fields, missing tag, missing cleanup outcome, missing hub
    tracker reference, mismatched release correlation key, mismatched contract
    revision, and complete evidence.
  - Evidence outcomes: `completed`, `pending`, `failed`, `blocked`, stale,
    conflicting, and unknown values for release, CI, deployment, cleanup, hub
    tracker reconciliation, and child release state.
  - Milestone title: valid `<product-repo>@<tag>`, missing separator, empty
    product repo, empty tag, whitespace, slash, and plain `vX.Y.Z` in
    workflow-hub mode.
  - Target issue kind: component child may receive a component milestone;
    parent epic and delivery bundle must reject component and plain version
    milestone writes.
  - Bundle parent state: no released components, one released plus one pending,
    all released but unfinalized, finalized, blocked, and blocked recovery.
  - Idempotency: existing namespaced milestone reused, already-stamped child
    reprocessed, and finalized parent reprocessed.
- **Unit test mapping**:
  `scripts/development-workflow/tests/test-component-milestone-reconciliation.sh`
  must include one named assertion group for each edge-case group above and
  positive coverage for inspect and apply paths. Mock `gh` responses must
  verify create/reuse/assign API calls without mutating the real repository.
- **Suppression semantics**: Not applicable. The helper validates structured
  JSON and milestone titles and must not support suppression directives.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Complete component evidence | `component_release_evidence.v1` with selected product key, canonical repository identity, release correlation key, contract revision, completed release, passing CI, recorded deployment, complete cleanup, hub tracker reference, complete hub tracker reconciliation, and released child state | Created under the test temp directory by `test-component-milestone-reconciliation.sh` |
| Negative component evidence | Missing, malformed, mismatched, pending, failed, blocked, stale, conflicting, and invalid outcome variants | Created under the test temp directory by `test-component-milestone-reconciliation.sh` |
| Delivery bundle manifests | Partial, blocked, ready, finalized, and corrected-after-blocked bundle states | Created under the test temp directory, reusing the #1357 fixture style |
| GitHub API fixtures | Mock milestone list/create responses and issue milestone assignment responses | Mock `gh` executable in the test temp directory |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/repository-modes.md` - component
      milestone namespacing, parent release states, single-product
      workflow-hub behavior, and non-hub compatibility.
- [ ] `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`
      - component milestone/status reconciliation handoff after evidence and
      cleanup.
- [ ] `docs/workflow/development-workflow/cross-repo-pr-flow.md` - component
      milestone handoff and final bundle release boundary.
- [ ] `scripts/development-workflow/README.md` - new helper usage and outputs.
- [ ] `docs/testing/workflow/release-stamping.smoke-test.md` - distinction
      between non-hub `vX.Y.Z` stamping and workflow-hub namespaced component
      milestones.
- [ ] `.agents/skills/prepare-release/SKILL.md` - post-release handoff to
      milestone reconciliation in workflow-hub mode.
- [ ] `CHANGELOG.md` - implementation entry under `[Unreleased]`.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Parent or delivery issue receives a milestone and appears shipped too early. | Med | High | Require explicit `--target-kind component_child` for milestone writes and test parent/delivery rejection. |
| Incomplete component evidence is treated the same as absent evidence, hiding a real blocker. | Med | High | Separate `component_release_pending` for no record from `component_release_not_ready` for incomplete or invalid records. |
| `component_released` and `parent_released` overlap during bundle finalization. | Med | Med | Require explicit reconciliation scope and test finalized bundles resolve to `parent_released` without milestone writes. |
| Existing single-repository release stamping regresses. | Low | High | Delegate non-hub mode to existing release stamping helpers and keep current milestone tests. |
| Namespaced milestone titles become inconsistent across scripts and docs. | Med | Med | Centralize title validation/generation in the new helper and cover valid/invalid titles in tests. |

---

## Code Samples

No production code samples are included. Implementation should follow the
existing Bash wrapper plus embedded Python style in
`scripts/development-workflow/delivery-bundle-manifest.sh`.

---

## Implementation Order

1. Add `component-milestone-reconciliation.sh` with schema constants, argument
   parsing, target-kind validation, milestone-title generation, and read-only
   `inspect-component` / `inspect-parent` output.
2. Add component evidence validation and outcome classification:
   - distinguish no evidence record from incomplete or invalid evidence,
   - validate stable identity fields and product/tag match,
   - emit exactly one child state and reconciliation outcome.
3. Add GitHub milestone apply behavior for component children:
   - create or reuse `<product-repo>@<tag>` milestones,
   - assign only the component child issue,
   - keep parent and delivery bundle issues milestone-free,
   - make repeated application idempotent.
4. Add parent release-state calculation from delivery bundle inspection:
   - partial shipment,
   - final bundle release,
   - blocked state,
   - recovery from blocked after corrected evidence.
5. Add `test-component-milestone-reconciliation.sh` with fixture writers,
   mocked `gh` API calls, and every parser-risk edge case above.
6. Update repository-mode, prepare-release, cross-repo flow, helper README,
   release-stamping smoke, and prepare-release skill guidance.
7. Update the #1358 smoke runbook if final command names or output keys differ
   from this plan.
8. Update `CHANGELOG.md` under `[Unreleased]` with:
   `- **Add component milestone release statuses** (#1358): Add workflow-hub component milestone and parent release-state reconciliation for multi-repository releases.`
9. Run verification before opening the implementation PR:

   ```bash
   set -euo pipefail

   bash -n scripts/development-workflow/component-milestone-reconciliation.sh
   bash -n scripts/development-workflow/tests/test-component-milestone-reconciliation.sh
   shellcheck \
     scripts/development-workflow/component-milestone-reconciliation.sh \
     scripts/development-workflow/tests/test-component-milestone-reconciliation.sh
   bash scripts/development-workflow/tests/test-component-milestone-reconciliation.sh
   bash scripts/development-workflow/tests/test-delivery-bundle-manifest.sh
   bash scripts/development-workflow/tests/test-component-release-evidence.sh
   bash scripts/development-workflow/tests/test-workflow-lib-github-projects.sh
   bash scripts/development-workflow/tests/test-workflow-hub-docs.sh
   npx markdownlint-cli2 \
     "docs/specs/developments/**/*.md" \
     "docs/testing/workflow/**/*.md" \
     "docs/workflow/development-workflow/**/*.md" \
     "scripts/development-workflow/README.md" \
     "CHANGELOG.md"
   find docs/specs/developments docs/testing/workflow -name "*.md" -print0 \
     | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md
   python3 scripts/lint/workflow-shell-snippet-lint.py \
     --base-ref origin/develop-multi-repo-releases
   python3 scripts/lint/workflow-shell-guard-lint.py \
     --base-ref origin/develop-multi-repo-releases
   git diff --check
   ```

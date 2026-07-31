# One Product Repository Per Implementation Item - Implementation Plan

**Spec**:
[`1_1354-one-product-repository-per-implementation-item_specs.md`](./1_1354-one-product-repository-per-implementation-item_specs.md)
**Smoke test runbook**:
[`docs/testing/workflow/1354-one-product-repository-per-implementation-item.smoke-test.md`](../../../testing/workflow/1354-one-product-repository-per-implementation-item.smoke-test.md)

---

## Summary

**Approach**: Add one shared routing contract that classifies a workflow-hub
work item as product-owned, hub-only, missing target, ambiguous target, multiple
targets, or single-repository. Wire that classification into item dispatch,
implementation handoffs, PR/reviewer routing, cleanup, and documentation so
product implementation mutation cannot proceed without exactly one selected
product repository key.

**Estimated complexity**: M

**Rationale**: The implementation is mostly workflow tooling and documentation,
but it crosses multiple command paths that currently pass product repository
context independently. The main risk is inconsistent enforcement between
run-item, run-items, run-epic, PR inspection, and cleanup.

**Dependencies**: #1353 is merged through implementation and provides the
canonical product repository key and artifact ownership contract. The #1354
spec PR #1404 is merged into `develop-multi-repo-releases`.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `ebaaab2` |
| Product-routing surface scan | `rg -l "selected product repository\|product repository selection\|workflow_hub" scripts/development-workflow docs/workflow/development-workflow .claude/agents .cursor/agents .codex/skills .agents/skills REVIEW.md \| sort \| wc -l` | 97 files mention the workflow-hub or selected-product-repository surface. The plan narrows implementation to shared scripts, protocol handoffs, tests, and agent/skill guidance that create or consume mutating item context. |
| Existing routing entry points | `rg -l "workflow-next-action\|repository_context_for_action\|github_repo_args_for_action\|selected product repository" scripts/development-workflow/tests docs/testing/workflow \| sort` | Relevant existing coverage lives in `test-workflow-orchestration-product-repo-aware.sh`, `test-workflow-hub-smoke-fixtures.sh`, `test-workflow-agent-product-repo-guidance.sh`, and workflow smoke runbooks 878, 879, 880, and 883. |
| Product repository key resolver | `sed -n '470,570p' scripts/development-workflow/workflow-config-resolver.py && sed -n '1010,1085p' scripts/development-workflow/workflow-config-resolver.py` | Existing resolver normalizes configured product repositories, rejects unknown keys, rejects ambiguous selection when more than one product repository exists, and exposes `list-product-repos`. |
| Current next-action behavior | `sed -n '130,230p' scripts/development-workflow/workflow-next-action.sh && sed -n '380,430p' scripts/development-workflow/workflow-next-action.sh` | PR and branch inspection already route implementation artifacts to a selected product repository in `workflow_hub`, but the decision is not backed by a shared tracker-level one-target contract. |
| Template-fit check | `rg -n "template:|is_template" .ai-dev-workflow.yaml` | `template.is_template: true`; the spec is generic workflow tooling and does not reference a downstream framework runtime, so planning can proceed. |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Plan base | `develop-multi-repo-releases` | `/run-epic 1352` effective policy and PR #1404 base branch | 2026-07-31, repo `ebaaab2` | Epic #1352 child scope and current #1354 plan branch only | `Verified` |
| Product repository key identity | Stable `workflow_hub.product_repos[].name` key from #1353 | `workflow-config-resolver.py` and #1353 merged contract | 2026-07-31, repo `ebaaab2` | #1354 plan plus same-epic remaining items #1356-#1359 that will consume the routing contract later | `Verified` |
| Planning artifact owner | Hub repository owns specs and plans; selected product repository owns product implementation artifacts | #1353 merged contract and #1354 spec | 2026-07-31, repo `ebaaab2` | Hub-owned #1354 plan PR only; product implementation routing is deferred to the implementation branch | `Verified` |

---

## Complex Workflow Decision-Gate Matrix

This plan modifies workflow decision-gate behavior because routing depends on
repository mode, work-item role, selected product repository keys, and stage.

| Gate input | Allowed outcome | Required next action | Mirror surfaces |
| --- | --- | --- | --- |
| `single_repo` mode | `Single-repository` | Continue current repository workflow unchanged | Protocol 91, `workflow-next-action.sh`, smoke runbook |
| `workflow_hub` product-owned item with exactly one valid selected product repository key on the item | `Product owned` | Continue product implementation routing with that selected key in handoffs | Run-item/run-items/run-epic handoffs, PR/reviewer routing, cleanup |
| `workflow_hub` product-owned item with no selected key | `Missing target` | Stop before product branch, PR, reviewer, CI, or cleanup mutation; hub may record stop evidence | Next-action output, orchestrator summaries, smoke runbook |
| `workflow_hub` product-owned item whose target cannot be resolved from confirmed tracker context | `Ambiguous target` | Stop before mutation and request routing clarification | Next-action output, orchestrator summaries, smoke runbook |
| `workflow_hub` product-owned item with more than one selected key | `Multiple targets` | Stop and split or narrow to one product repository child | Add-backlog guidance, run-item/run-epic handoffs, smoke runbook |
| `workflow_hub` hub-only item with no product repository key | `Hub only` | Continue hub-owned workflow artifacts in the hub repository | Spec/plan/review/cleanup guidance |
| `workflow_hub` hub-only item with a product repository key | `Ambiguous target` | Stop until the operator removes the key or reclassifies the item as product-owned | Add-backlog guidance, next-action output |

Precedence rule: a product-owned item with no selected key is always
`Missing target`, even when the hub config contains multiple product
repositories. `Ambiguous target` is reserved for conflicting, unknown, or
unresolved target evidence, including a hub-only item that also carries a
product key.

---

## Layer-by-Layer Changes

### Database / Data Layer

- [ ] No database, migration, or seed-data changes. The routing contract is
      workflow metadata and command behavior only.

### Backend / API

- [ ] No HTTP API changes.

### Shared Workflow Tooling

- [ ] Add `scripts/development-workflow/work-item-repository-routing.py` as the
      shared classifier for item-level routing. Inputs must include repository
      mode, action/stage, configured product repository keys, optional selected
      key values, and an explicit hub-only marker. Outputs must include a stable
      code, display label, selected key when valid, artifact owner, stop reason,
      and required human action. The canonical configuration input is either
      `--config <path>` for deterministic JSON fixtures or `--repo-root <path>`
      for production resolution from the repo workflow config; explicit
      `--config` wins over `--repo-root`, and `--repo-root` wins over the current
      working directory. `--fixture <path>` supplies only item identity, stage,
      selected keys, and hub-only markers; it must not override configured
      product repositories. The JSON fixture schema is one object with
      `repository_mode`, `stage`, `item_identifier`, `hub_only`, and
      `selected_product_repo_keys` item fields plus configuration from either
      the separate `--config` object or repo-root resolver output. The `--json`
      output contract is:
      `outcome_code` string enum (`product_owned`, `hub_only`,
      `missing_target`, `ambiguous_target`, `multiple_targets`,
      `single_repo`); `display_label` string; `continue_allowed` boolean;
      `selected_product_repo_key` string or `null`; `artifact_owner` string
      enum (`selected_product_repository`, `hub_repository`,
      `current_repository`, `none`); `stop_reason` string or `null`;
      `required_human_action` string or `null`; `configured_product_repo_keys`
      array of strings sorted lexicographically; `selected_product_repo_keys`
      array of strings sorted lexicographically; `fingerprint` string; and
      `schema_version` string. The `fingerprint` is
      `sha256(routing-fingerprint.v1 + "\n" + canonical_json)`, where
      `canonical_json` is UTF-8 JSON with sorted object keys and no insignificant
      whitespace over `schema_version`, `item_identifier`, `repository_mode`,
      `stage`, sorted configured keys, sorted selected keys, and `hub_only`.
      A mutating handoff that carries a fingerprint must reject the handoff when
      the current classifier fingerprint differs; handoffs that reclassify
      immediately before mutation treat the fingerprint as diagnostic evidence.
      The classifier exits `0` when it emits this contract for any classified
      outcome, `2` for malformed input or unreadable configuration, and nonzero
      for unexpected runtime errors. Because stop outcomes also exit `0`, every
      mutating consumer must parse `continue_allowed` and refuse branch, PR,
      reviewer, CI, or cleanup mutation when it is `false`; no wrapper may treat
      exit status alone as permission to continue. Classifier and orchestration
      tests must assert the same field names, nullability, enum values,
      exit-status semantics, fingerprint behavior, and `continue_allowed`
      gating. Map to AC1-AC8.
- [ ] Extend `scripts/development-workflow/workflow-config-resolver.py` or its
      tests only where needed to expose configured product repository keys in a
      reusable form. Do not duplicate key validation outside the resolver; the
      classifier consumes resolver output. Map to AC1, AC2, and AC4.
- [ ] Update `scripts/development-workflow/workflow-next-action.sh` so
      implementation-stage decisions in `workflow_hub` call the shared
      classifier before branch, PR, reviewer, CI, or cleanup routing. It should
      print the routing outcome, selected product repository key, artifact owner,
      and stop evidence, then gate mutation exclusively on `continue_allowed`.
      Map to AC1-AC4 and AC7.
- [ ] Update `scripts/development-workflow/discover-workflow-state.sh`,
      `run-item-scope-resolver.sh`, `run-epic-scope-resolver.sh`, and relevant
      run-item/run-items handoff code so summaries preserve the classifier
      result, fingerprint, and stop evidence instead of re-inferring repository
      ownership from branch names or the current checkout. Map to AC1-AC7.
- [ ] Update `scripts/development-workflow/post-merge-cleanup.sh` and
      reviewer/CI handoff glue only to consume the already-classified selected
      key. They must not implement a second product-repository-selection path.
      Map to AC6 and AC7.
- [ ] Add a stale-decision guard to every mutating handoff. Either reclassify
      immediately before mutation or carry the classifier `fingerprint` and
      reject the handoff when the item/configuration fingerprint has changed.
      Map to AC2-AC4 and AC7.

### Workflow Documentation

- [ ] `docs/workflow/development-workflow/repository-modes.md`: add the
      one-target routing model, display labels, stop outcomes, and statement
      that the selected key is `workflow_hub.product_repos[].name`. Map to all
      ACs.
- [ ] `docs/workflow/development-workflow/workflow-hub-setup.md`: document how
      operators decompose cross-repository work into a hub epic plus one
      repository-scoped child per product repository. Map to AC4-AC6.
- [ ] `docs/workflow/development-workflow/cross-repo-pr-flow.md`: add the
      pre-mutation routing checkpoint and handoff evidence expectations. Map to
      AC1-AC4 and AC7.
- [ ] `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md`:
      document the tracker authoring requirements for product-owned children,
      hub-only children, and split/narrow actions. Map to AC4-AC6.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`,
      `91-orchestrate-work-protocol.md`, and `95-run-epic-protocol.md`: require
      the classifier result in mutating handoffs and stop on missing, ambiguous,
      or multiple targets. Map to AC1-AC7.
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
      and `04-smoke-test-protocol.md`: clarify that product-owned validation
      consumes the selected key and hub-only work has no product key. Map to
      AC6 and AC7.

### Agent And Skill Guidance

- [ ] Update Claude, Cursor, Codex, and `.agents` guidance that currently says
      "selected product repository" so it names the classifier result and
      selected product repository key, while preserving thin wrappers around the
      shared scripts. Required targets include `.claude/agents/orchestrator.md`,
      `.claude/agents/item-orchestrator.md`, `.claude/agents/developer.md`,
      `.claude/agents/automated-reviewer-loop.md`, `.claude/agents/smoke-tester.md`,
      the corresponding `.cursor/agents/` files, `.codex/skills/workflow-item-orchestrator/SKILL.md`,
      `.codex/skills/workflow-implementer/SKILL.md`,
      `.codex/skills/workflow-reviewer-loop/SKILL.md`, and the matching
      `.agents/skills/` command wrappers. Map to AC6 and AC7.

---

## Testing Strategy

**Test types**: Unit-style shell/Python fixture tests, integration-style
workflow command tests, and smoke/manual review.

**Key scenarios to test**:

1. `single_repo` mode returns the current repository target without requiring a
   product repository key. Maps to AC8.
2. `workflow_hub` product-owned work with exactly one valid selected key
   returns `Product owned`, artifact owner `selected product repository`, and
   includes the same key in handoff output. Maps to AC1 and AC7.
3. Product-owned work with no key returns `Missing target`, stops before
   product artifact mutation, and allows hub-owned stop evidence. Maps to AC2.
4. Product-owned work with an ambiguous or unknown key returns
   `Ambiguous target` and stops before mutation. Maps to AC3.
5. Product-owned work with multiple selected keys returns `Multiple targets`
   and tells the operator to split or narrow the child item. Maps to AC4.
6. Hub-only work with no product key returns `Hub only` and routes hub-owned
   artifacts to the hub repository. Maps to AC6.
7. Cross-repository requests are represented in docs and smoke evidence as a
   hub epic with one product-owned child per product repository. Maps to AC5.
8. Release execution, delivery bundles, milestones, and adoption assurance are
   left to #1356-#1359. Maps to AC9.

**Smoke test runbook**:
`docs/testing/workflow/1354-one-product-repository-per-implementation-item.smoke-test.md`

**Regression suite**:

- [ ] Add `scripts/development-workflow/tests/test-work-item-repository-routing.sh`
      for classifier outcomes and edge cases.
- [ ] Extend `scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh`
      for run-item/run-epic handoff behavior and stop evidence.
- [ ] Extend `scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh`
      for dry-run product branch, PR, reviewer, and cleanup routing.
- [ ] Extend `scripts/development-workflow/tests/test-workflow-agent-product-repo-guidance.sh`
      for mirrored agent/skill wording.
- [ ] Extend `scripts/development-workflow/tests/test-workflow-hub-docs.sh` for
      decomposition and hub-only/product-owned documentation coverage.
- [ ] Run existing `scripts/development-workflow/tests/test-run-work-router.sh`
      coverage to guard no-target, single-target, and multi-target routing after
      shared classifier and next-action changes.

### Parser-Risk Addendum

This plan is parser-risk because it introduces a classifier over structured
workflow metadata and configured product repository keys.

- **Edge-case enumeration**:
  - Valid selected keys: one configured key such as `mobile-app`.
  - Missing target: empty selected key for product-owned work, including when
    multiple product repositories are configured.
  - Ambiguous target: unknown key, unresolved key, conflicting tracker text that
    cannot be normalized to one key, or hub-only marker plus a product key.
  - Multiple targets: two or more configured keys on one item.
  - Hub-only: explicit hub-only marker with no product key.
  - Hub-only conflict: hub-only marker plus product key.
  - Single-repository: missing workflow mode or `single_repo`.
  - Negative lookalikes: branch names, GitHub repo slugs, local paths, and PR
    titles that contain a product name but are not the selected key source.
- **Unit test mapping**:
  - `scripts/development-workflow/tests/test-work-item-repository-routing.sh`:
    one automated test for every edge case above plus one contract assertion for
    every JSON field and exit-status class.
  - `scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh`:
    one test each for product-owned continue, missing target stop, ambiguous
    target stop, multiple target stop, hub-only continue, and preservation of
    classifier result, fingerprint, and stop evidence through
    `run-item-scope-resolver.sh`.
- **Suppression semantics**: Not applicable. This feature does not introduce
  inline suppression directives.

### Concurrent-Event-Source Addendum

- **Shared mutable state guards**: Not applicable; the implementation is
  command-line routing with process-local state.
- **Re-entrancy / in-flight tracking**: Not applicable; each command invocation
  resolves one snapshot and exits.
- **Event deduplication**: Not applicable; no event listeners are introduced.
- **Listener and resource cleanup**: Not applicable; no long-lived listeners,
  timers, or handles are introduced.
- **Race conditions at initialization**: Not applicable; commands read the
  current tracker/config snapshot at invocation start. Mutating handoffs must
  still prevent stale decisions by reclassifying immediately before mutation or
  validating the classifier `fingerprint`.
- **Race conditions at teardown**: Not applicable; there is no teardown hook.
- **Error propagation across async boundaries**: Not applicable; failures are
  synchronous command exit statuses and stop evidence.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Workflow-hub fixture config | Two product repositories, `mobile-app` and `admin-portal`, with default branches and GitHub slugs | Persistent fixture `scripts/development-workflow/tests/fixtures/1354-routing/config-workflow-hub.json` used by classifier tests, orchestration tests, and the smoke runbook |
| Product-owned item fixture | One child item with selected key `mobile-app` | Persistent fixture `scripts/development-workflow/tests/fixtures/1354-routing/product-owned.json` |
| Product-owned peer fixture | One child item with selected key `admin-portal` | Persistent fixture `scripts/development-workflow/tests/fixtures/1354-routing/product-owned-admin-portal.json` |
| Missing-target fixture | Product-owned child with no selected key | Persistent fixture `scripts/development-workflow/tests/fixtures/1354-routing/missing-target.json` |
| Multiple-target fixture | Product-owned child naming both `mobile-app` and `admin-portal` | Persistent fixture `scripts/development-workflow/tests/fixtures/1354-routing/multiple-targets.json` |
| Hub-only fixture | Hub-owned workflow item with no product key | Persistent fixture `scripts/development-workflow/tests/fixtures/1354-routing/hub-only.json` |

---

## Documentation Updates

The canonical documentation inventory lives in
[Workflow Documentation](#workflow-documentation) and
[Agent And Skill Guidance](#agent-and-skill-guidance). Keep file additions and
scope updates there so implementation has one source of truth.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Different commands classify the same item differently | Medium | High | Centralize routing in one helper and make wrappers consume its output. |
| Tracker text parsing becomes brittle | Medium | Medium | Keep accepted metadata narrow, test negative lookalikes, and prefer configured product repository keys over free text. |
| Hub-only workflow work is accidentally forced into a product repository | Low | High | Require a distinct hub-only outcome with no product repository key and tests for hub-only conflict cases. |
| Later epic items need release, bundle, milestone, or adoption behavior not covered here | Medium | Medium | Keep those behaviors out of #1354 and reference #1356-#1359 in docs and smoke assertions. |

---

## Code Samples

No production code samples are included. Implementation should follow existing
Bash and Python helper patterns in `scripts/development-workflow/`.

---

## Implementation Order

1. Add the routing classifier and focused fixture tests for product-owned,
   hub-only, missing, ambiguous, multiple-target, and single-repository
   outcomes.
2. Wire the classifier into `workflow-next-action.sh` and workflow discovery so
   mutating implementation paths receive one normalized routing result.
3. Wire run-item/run-items/run-epic handoff paths to report the routing result
   and stop before mutation when the result is missing, ambiguous, or multiple.
4. Update reviewer, CI, smoke, and cleanup handoff glue to consume the selected
   product repository key from the classifier result.
5. Update workflow documentation and mirrored agent/skill guidance listed
   above.
6. Extend regression tests for orchestration, smoke fixtures, docs, and mirrored
   guidance.
7. Run validation:
   - `bash scripts/development-workflow/tests/test-work-item-repository-routing.sh`
   - `bash scripts/development-workflow/tests/test-workflow-orchestration-product-repo-aware.sh`
   - `bash scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh`
   - `bash scripts/development-workflow/tests/test-workflow-agent-product-repo-guidance.sh`
   - `bash scripts/development-workflow/tests/test-workflow-hub-docs.sh`
   - `bash scripts/development-workflow/tests/test-run-work-router.sh`
   - `npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "CHANGELOG.md"`
   - `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`
8. Update `CHANGELOG.md` under `[Unreleased]` with:
   `- **One product repository per implementation item** (#1354): enforce one-target workflow-hub routing before product implementation mutation.`
9. Complete the smoke test runbook and record any manual findings before PR
   readiness.

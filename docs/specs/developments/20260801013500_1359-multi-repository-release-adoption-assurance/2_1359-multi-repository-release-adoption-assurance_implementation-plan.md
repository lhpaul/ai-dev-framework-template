# Multi-Repository Release Adoption And Assurance - Implementation Plan

**Spec**:
[`1_1359-multi-repository-release-adoption-assurance_specs.md`](./1_1359-multi-repository-release-adoption-assurance_specs.md)
**Smoke test runbook**:
[`docs/testing/workflow/1359-multi-repository-release-adoption-assurance.smoke-test.md`](../../../testing/workflow/1359-multi-repository-release-adoption-assurance.smoke-test.md)

---

## Summary

**Approach**: Add one hub-owned adoption guide and one deterministic assurance
harness that composes the existing workflow-hub helpers for product routing,
component release evidence, delivery bundles, component milestones, and
configuration validation. The implementation should avoid redefining those
runtime contracts; it should orchestrate them into an adoption/self-review
evidence flow with non-secret fixtures and explicit outcome summaries.

**Estimated complexity**: M

**Rationale**: The work is mostly documentation and shell/Python fixture tests,
but it crosses several workflow-hub surfaces and must prove both hub-owned and
product-owned historical no-rewrite baselines. The main risk is creating a
parallel release model instead of an assurance layer over the existing helpers.

**Dependencies**: #1353, #1354, #1356, #1357, and #1358 are merged through
implementation on `develop-multi-repo-releases`.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `f6dc7a1` |
| Template-fit check | `rg -n "template:" .ai-dev-workflow.yaml && sed -n '171,177p' .ai-dev-workflow.yaml` | `.ai-dev-workflow.yaml` declares `template.is_template: true`; the spec is generic workflow-template adoption and assurance work, so it passes. |
| Workflow-hub test surfaces | `find scripts/development-workflow/tests -maxdepth 1 -type f \| sort \| rg 'workflow-hub\|component\|delivery\|release\|config\|post-merge\|prepare-release'` | Existing surfaces include component release evidence, component milestone reconciliation, delivery bundle manifest, config resolver, product-repo commands, skeletons, smoke fixtures, prepare-release cleanup, and workflow-hub docs tests. |
| Workflow-hub docs and helper surfaces | `rg -l "workflow_hub\|component release\|delivery bundle\|component-milestone\|release evidence\|single_repo\|repository mode" docs/workflow/development-workflow scripts/development-workflow .agents/skills .codex/skills \| sort` | Relevant docs and helpers include `workflow-hub-setup.md`, `product-repo-injection.md`, `repository-modes.md`, `cross-repo-pr-flow.md`, `05-prepare-release-protocol.md`, `component-release-target.sh`, `component-release-evidence.sh`, `delivery-bundle-manifest.sh`, and `component-milestone-reconciliation.sh`. |
| Same-surface PR check | `gh pr list --base develop-multi-repo-releases --state open --search "1359" --json number,title,headRefName,baseRefName,state,url` | No other open #1359 PR existed before this plan branch. |
| Design assets | `gh issue view 1359 --json body --jq '.body' \| sed -n '/## Design assets/,+8p'` | No design assets section or tracker design references found; no fidelity step is required. |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Plan artifact base | `develop-multi-repo-releases` | `/run-epic 1352` selected policy and merged #1418 spec PR base | 2026-08-01T02:03:00Z at repo `f6dc7a1` | Current #1359 plan branch plus same-base #1359 open PR check only | `Verified` |
| Artifact owner | Hub owns adoption docs, assurance harness, fixture evidence, and tracker comments; product repositories own product release artifacts and product-side evidence represented in fixtures | #1353, #1356, #1357, #1358 specs and accepted #1359 spec | 2026-08-01T02:03:00Z at repo `f6dc7a1` | Epic #1352 child #1359 and merged dependency specs only | `Verified` |
| Historical no-rewrite baseline | Adoption must compare hub-owned and product-owned historical baseline records before and after assurance, without mutating them | #1359 spec Use Case 3 and Use Case 4 | 2026-08-01T02:03:00Z at repo `f6dc7a1` | Current #1359 spec only | `Verified` |

---

## Assurance Contract

The implementation must create one canonical assurance contract in
`docs/workflow/development-workflow/multi-repo-release-adoption.md`. The harness
and runbook should point to that section instead of duplicating scenario
definitions elsewhere.

| Scenario | Required fixture inputs | Required output | Pass assertion |
| --- | --- | --- | --- |
| Component routing | Hub tracker fixture plus product release contract fixture | Scenario outcome and selected-product handoff summary | Matching product selection passes; missing, ambiguous, or mismatched selection stops before release mutation. |
| Configuration validation | Hub config fixture and product config fixture | Adoption status and owner-correction summary | Invalid hub or product configuration maps to `blocked` with the correcting owner named. |
| Namespaced component milestones | Component evidence fixture and component milestone fixture | Component milestone reconciliation result | Verified component evidence produces the expected component milestone and never stamps parent or delivery issues. |
| Bundle finalization | Delivery bundle fixture and accepted component evidence | Delivery bundle result and parent release-state result | Bundle finalizes only when every declared component has complete accepted evidence. |
| Partial failures | Failed, blocked, stale, missing, and conflicting evidence fixtures | `blocked` or `retryable` scenario outcome | Accepted evidence is preserved and the required recovery action is reported. |
| Reruns | Durable run id and step id fixtures for cleanup and handoff | Supersession and idempotency summary | Stale attempts are rejected; corrected reruns supersede older attempts; cleanup and handoff side effects are not repeated. |
| Migration no-rewrite | Hub-owned and product-owned historical baselines | Before/after comparison summary | Historical milestones, tags, changelogs, delivery records, and tracker records are byte-for-byte unchanged. |
| `single_repo` compatibility | Non-hub release fixture from the #1358 invariant | Compatibility outcome | The plain single-repository milestone path remains valid and does not require workflow-hub adoption fixtures. |

Outcome aggregation must be total: adoption is `validated` only when every
required scenario is `pass` or approved `skipped` with rationale; any `fail`,
`blocked`, or unresolved `retryable` scenario maps adoption to `blocked`.

---

## Layer-by-Layer Changes

### Database / Data Layer

- [ ] No database, migration, or persistent seed-data changes. Test data should
      be committed as non-secret shell/JSON fixtures under
      `scripts/development-workflow/tests/fixtures/1359-assurance/`.

### Backend / API

- [ ] No HTTP API changes.

### Shared Workflow Tooling

- [ ] Add `scripts/development-workflow/multi-repo-release-assurance.sh` as the
      canonical deterministic assurance harness. It should be a Bash wrapper
      with embedded Python or structured `jq` use, matching existing workflow
      helper style. Map to AC4, AC5, and AC7.
- [ ] The harness should consume explicit fixture paths and emit stable JSON
      with `schema_version=multi_repo_release_assurance.v1`, `adoption_status`,
      `scenario_results[]`, `historical_no_rewrite`, `owner_actions[]`, and
      `required_next_action`. Map to AC3-AC7.
- [ ] Compose existing helpers instead of re-implementing their contracts:
      `component-release-target.sh`, `component-release-evidence.sh`,
      `delivery-bundle-manifest.sh`, and
      `component-milestone-reconciliation.sh`. Map to AC4, AC5, and AC8.
- [ ] Add durable run and step identity handling for assurance reruns. The
      harness should reject stale attempts when a newer corrected run supersedes
      them and should record idempotency/completion guards for cleanup and
      handoff side effects in fixture state. Map to AC4 and AC5.
- [ ] Add hub-owned and product-owned historical baseline comparison. Compare
      fixture copies before and after assurance and fail if historical
      milestones, tags, changelogs, delivery records, or tracker records
      change. Map to AC5 and AC6.
- [ ] Add
      `scripts/development-workflow/tests/setup-multi-repo-release-assurance-fixture.sh`
      to create isolated non-secret fixtures for hub config, product config,
      selected-product evidence, bundle state, component milestone state,
      historical baselines, partial failures, reruns, and `single_repo`
      compatibility. Map to AC4 and AC5.
- [ ] Add
      `scripts/development-workflow/tests/test-multi-repo-release-assurance.sh`
      with automated assertions for every row in the Assurance Contract section.
      Map to AC4-AC7.
- [ ] Extend `scripts/development-workflow/tests/test-workflow-hub-docs.sh` so
      docs coverage includes the adoption guide, assurance harness, historical
      no-rewrite policy, and outcome vocabulary. Map to AC1-AC3 and AC8.
- [ ] Update `scripts/development-workflow/README.md` with the new harness,
      fixture setup, output fields, outcome vocabulary, and rerun behavior. Map
      to AC3-AC7.

### Workflow Documentation

- [ ] Add
      `docs/workflow/development-workflow/multi-repo-release-adoption.md` as the
      canonical adoption and assurance guide. Include hub adoption, product
      adoption, prospective migration, troubleshooting, release-runbook
      evidence, self-review evidence, outcome vocabulary, and the Assurance
      Contract table. Map to AC1-AC8.
- [ ] Update `docs/workflow/development-workflow/workflow-hub-setup.md` to link
      the adoption guide and require validation before release mutation. Map to
      AC1 and AC6.
- [ ] Update `docs/workflow/development-workflow/product-repo-injection.md` to
      link product repository adoption responsibilities and product-side
      self-review evidence. Map to AC2 and AC3.
- [ ] Update `docs/workflow/development-workflow/repository-modes.md` with the
      prospective migration boundary and historical no-rewrite policy. Map to
      AC1, AC2, and AC6.
- [ ] Update `docs/workflow/development-workflow/cross-repo-pr-flow.md` with
      the assurance evidence handoff and blocked/retryable adoption outcomes.
      Map to AC3-AC7.
- [ ] Update
      `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`
      to reference the adoption assurance runbook as a release self-review
      artifact, without making it mandatory for `single_repo` releases. Map to
      AC3, AC5, and AC8.
- [ ] Update `CHANGELOG.md` under `[Unreleased]` with:
      `- **Add multi-repository release adoption assurance** (#1359): Add workflow-hub adoption guidance and deterministic assurance coverage for multi-repository releases.`

### Agent And Skill Guidance

- [ ] Update `.agents/skills/prepare-release/SKILL.md` so release operators know
      where to find the adoption assurance guide and when to treat assurance as
      a self-review evidence artifact. Map to AC3 and AC8.

---

## Testing Strategy

**Test types**: shell fixture tests, mocked helper integration tests, docs smoke
tests, manual smoke runbook verification.

**Key scenarios to test**:

1. Hub adoption guidance validates ownership and migration boundary. Maps to
   AC1 and AC6.
2. Product adoption guidance validates product-owned artifact and evidence
   handoff requirements. Maps to AC2 and AC3.
3. Harness reports `pass`, `fail`, `blocked`, `skipped`, and `retryable`
   outcomes and aggregates adoption status correctly. Maps to AC5 and AC7.
4. Component routing, configuration validation, milestones, bundle
   finalization, partial failures, reruns, and `single_repo` compatibility are
   covered by deterministic fixtures. Maps to AC4 and AC5.
5. Hub-owned and product-owned historical baselines remain unchanged after the
   assurance run. Maps to AC5 and AC6.
6. Documentation links to the canonical assurance contract and does not
   duplicate scenario definitions. Maps to AC8.

**Smoke test runbook**:
`docs/testing/workflow/1359-multi-repository-release-adoption-assurance.smoke-test.md`

**Regression suite**:

- [ ] `bash scripts/development-workflow/tests/test-multi-repo-release-assurance.sh`
- [ ] `bash scripts/development-workflow/tests/test-workflow-hub-docs.sh`
- [ ] Existing dependency suites remain green:
      `test-component-release-target.sh`, `test-component-release-evidence.sh`,
      `test-delivery-bundle-manifest.sh`,
      `test-component-milestone-reconciliation.sh`,
      `test-workflow-config-resolver.sh`, and
      `test-workflow-hub-smoke-fixtures.sh`.

### Parser-Risk Classification

**Result**: `Not applicable` — the plan should use structured JSON via existing
helpers, `jq`, and Python JSON APIs. It must not introduce a custom
structured-text parser, regex scanner, or suppression syntax.

### Concurrent-Event-Source Classification

**Result**: `Not applicable` — the harness is a synchronous command-line
workflow with fixture state, not a listener, socket, timer, queue, or async
event source.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Hub adoption fixture | Valid workflow hub, invalid hub config, ambiguous product ownership, historical hub baseline | `scripts/development-workflow/tests/fixtures/1359-assurance/hub/` |
| Product adoption fixture | Valid product release contract, invalid product contract, product historical baseline | `scripts/development-workflow/tests/fixtures/1359-assurance/product/` |
| Assurance run fixture | Run id, step ids, stale attempt, corrected rerun, cleanup/handoff completion guards | `scripts/development-workflow/tests/fixtures/1359-assurance/reruns/` |
| Scenario evidence fixture | Component routing, component evidence, delivery bundle, component milestone, partial failure, `single_repo` compatibility | `scripts/development-workflow/tests/fixtures/1359-assurance/scenarios/` |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/multi-repo-release-adoption.md` - new
      canonical adoption and assurance guide.
- [ ] `docs/workflow/development-workflow/workflow-hub-setup.md` - link the
      guide and describe hub adoption validation.
- [ ] `docs/workflow/development-workflow/product-repo-injection.md` - link
      product adoption and self-review evidence responsibilities.
- [ ] `docs/workflow/development-workflow/repository-modes.md` - add
      prospective migration and historical no-rewrite boundaries.
- [ ] `docs/workflow/development-workflow/cross-repo-pr-flow.md` - add
      assurance evidence and outcome handoff.
- [ ] `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`
      - reference assurance as release self-review evidence.
- [ ] `scripts/development-workflow/README.md` - document harness usage,
      outputs, and reruns.
- [ ] `.agents/skills/prepare-release/SKILL.md` - point release operators to
      adoption assurance guidance.
- [ ] `CHANGELOG.md` - add #1359 `[Unreleased]` entry during implementation.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Assurance harness duplicates existing helper contracts and drifts. | Medium | High | Compose existing helpers and make the adoption guide the only scenario-definition source. |
| Historical no-rewrite checks cover hub records but miss product-owned records. | Medium | High | Require both hub-owned and product-owned baseline fixtures and before/after comparisons. |
| `skipped` or `retryable` outcomes make adoption status ambiguous. | Low | Medium | Implement the total precedence rule from the spec and test mixed-outcome aggregation. |
| Rerun tests accidentally repeat side effects. | Medium | Medium | Use fixture state with durable run and step ids plus explicit completion guards. |

---

## Implementation Order

1. Add the canonical adoption guide and update linked workflow documentation.
2. Add the smoke test runbook and update `test-workflow-hub-docs.sh` for doc
   coverage.
3. Add the assurance fixture setup script and committed non-secret fixture
   directories.
4. Add the assurance harness with stable JSON output and scenario aggregation.
5. Add the assurance test suite covering every Assurance Contract row and
   historical no-rewrite baselines.
6. Update `scripts/development-workflow/README.md` and
   `.agents/skills/prepare-release/SKILL.md`.
7. Update `CHANGELOG.md` under `[Unreleased]` with the literal entry from the
   Workflow Documentation section.
8. Run targeted validation:
   - `bash -n scripts/development-workflow/multi-repo-release-assurance.sh scripts/development-workflow/tests/setup-multi-repo-release-assurance-fixture.sh scripts/development-workflow/tests/test-multi-repo-release-assurance.sh`
   - `shellcheck scripts/development-workflow/multi-repo-release-assurance.sh scripts/development-workflow/tests/setup-multi-repo-release-assurance-fixture.sh scripts/development-workflow/tests/test-multi-repo-release-assurance.sh`
   - `bash scripts/development-workflow/tests/test-multi-repo-release-assurance.sh`
   - `bash scripts/development-workflow/tests/test-workflow-hub-docs.sh`
   - Dependency suites listed in the Testing Strategy section.
   - `npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "docs/workflow/development-workflow/**/*.md" "scripts/development-workflow/README.md" "CHANGELOG.md"`
   - `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`
   - `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop-multi-repo-releases`
   - `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop-multi-repo-releases`
   - `git diff --check`

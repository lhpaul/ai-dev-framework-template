# Cross-Check Cross-Cutting Plan Assumptions — Implementation Plan

**Spec**: [1_1201-cross-check-cross-cutting-plan-assumptions_specs.md](1_1201-cross-check-cross-cutting-plan-assumptions_specs.md)
**Smoke test runbook**: [1201-cross-check-cross-cutting-plan-assumptions.smoke-test.md](../../../testing/workflow/1201-cross-check-cross-cutting-plan-assumptions.smoke-test.md)

---

## Summary

**Approach**: Add one conditional cross-cutting operational-assumption gate to
the planning contract and plan template. Carry the bounded current-batch context
through portfolio and item orchestration, require parent-orchestrator resolution
for conflicting evidence, and re-run the recorded source checks before the
implementer edits files. Mirror the contract across supported runner guidance,
review rules, commands, and a fixed-string workflow regression test.

**Estimated complexity**: M

**Rationale**: The change is documentation-first and introduces no product code
or external integration, but it spans planning, batch dispatch, item
orchestration, implementation start, review, and multiple mirrored runner
surfaces. The gate also has seven distinct outcomes/next-action rows that must
remain consistent.

**Dependencies**: None. Coordinate implementation with the open plan PRs in the
current approved batch because several plan future changes to shared workflow
protocols. No other item must merge first.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD \|\| exit 1` | `21f23e3` |
| Template fit | Read `.ai-dev-workflow.yaml` | `template.is_template: true`; the feature changes framework-agnostic workflow guidance and passes the template-fit gate. |
| Approved spec | `git show HEAD:docs/specs/developments/20260723153924_1201-cross-check-cross-cutting-plan-assumptions/1_1201-cross-check-cross-cutting-plan-assumptions_specs.md \|\| exit 1` | The merged spec defines AC1-AC8 and the seven-row gate consistency matrix. |
| Direct planning/implementation guidance search | `grep -rl "02-generate-implementation-plan-protocol\|03-implement-development-protocol" .claude/agents/ .cursor/agents/ .codex/skills/ \|\| exit 1` | Six direct invocation files: both developer agents, both tech-lead agents, `workflow-implementer`, and `workflow-plan-writer`. |
| Batch context source | Read Protocol 90 handoff and dispatch sections plus Protocol 91's Batch Context Indicator | Protocol 90 already owns the exact in-scope item list and per-item handoff; Protocol 91 already consumes `BATCH_CONTEXT=true` and explicit-list metadata. |
| Implementation-start locations | `rg -n "^## Path|^### Step 1:|^### Step 1b:|^### Step 4: Implement" docs/workflow/development-workflow/protocols/03-implement-development-protocol.md \|\| exit 1` | Full Pipeline, Refactor, Fast Track, and Hotfix have distinct prep/scope sections; the assumption re-verification gate belongs in shared prep plus applicable plan-backed paths before edits. |
| Existing workflow test pattern | `set -o pipefail; find scripts/development-workflow/tests -maxdepth 1 -type f -name 'test-*.sh' \| wc -l \|\| exit 1` | 46 shell tests exist; `test-may-merge-terminal-contract.sh` demonstrates fixed-string contract checks across protocols, agents, skills, and commands. |
| Bounded in-flight cross-check | Inspect current approved batch PRs `#1334` through `#1343`; inspect related Protocol 02 plan PR `#1339` with `gh pr view 1339 --json title,body,files,headRefName,baseRefName \|\| exit 1` | `#1339` is the only current-batch plan directly touching Protocol 02. It changes reference portability, not the current repository's artifact ownership or approved `develop` base; no conflict with the operational assumption below. |
| Design assets | Inspect issue body, linked files, and the development folder's `assets/` path | No UI scope or design assets; fidelity steps are not applicable. |

---

## Cross-Cutting Operational Assumption Check

**Classification**: Applicable. This plan relies on one operational fact that
could be changed by concurrent workflow work: where #1201's workflow artifacts
are owned and which base branch the implementation PR must target.

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact owner and approved implementation base | The current repository owns the workflow implementation; the implementation PR targets `develop`. | Repository mode ownership rules in Protocols 02/03 (missing mode means current-repository ownership) plus the parent batch handoff's approved base | `2026-07-23T22:57:35Z` at `21f23e3` | Current approved batch plan PRs `#1334`-`#1343`; `#1339` inspected as the only Protocol 02 overlap | Consistent. No inspected item changes this repository's artifact owner or #1201's approved base. Re-verify before implementation. |

The implementation PR must not treat this result as timeless. Protocol 03 will
require the implementer to re-read the recorded source and current parent
handoff before the first implementation edit. A changed or conflicting result
returns to the parent orchestrator rather than being resolved locally.

---

## Layer-by-Layer Changes

### Planning Contract and Artifact Template

- [ ] Update
      `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
      with a conditional operational-assumption classifier. It must distinguish
      environment targets, linked external resources, approved base branches,
      canonical configuration, and similarly invalidatable facts from ordinary
      architecture decisions or shared terminology. Maps to AC1, AC2, AC7, and
      AC8.
- [ ] Require each applicable plan to record the assumption value,
      authoritative source, verification time, bounded current-batch/related-PR
      scope, result, and later re-verification requirement. An unverifiable
      source is unresolved evidence, not confirmation. Maps to AC1 and AC2.
- [ ] Require the planner to record a conflict row with competing evidence,
      affected plan statements, resolution status, and decision owner, then
      return control to the parent orchestrator. Planning may continue only
      after the recorded resolution is reflected in the plan. Implementation
      remains blocked meanwhile. Maps to AC3 and AC4.
- [ ] Define the not-applicable path as one concise rationale with no
      repository-wide PR scan. Explicitly state that shared keywords alone do
      not establish a related assumption surface. Maps to AC7 and AC8.
- [ ] Update
      `docs/workflow/development-workflow/templates/implementation-plan-template.md`
      with one `Cross-Cutting Operational Assumption Check` section containing
      an applicable evidence table and a documented not-applicable alternative.
      Do not make both alternatives mandatory in the final plan.

### Portfolio and Item Orchestration

- [ ] Update
      `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      so every plan-writing handoff receives the exact approved current-batch
      item set already owned by Protocol 90. The handoff must remain bounded and
      must not authorize mutations outside that set. Maps to AC2 and AC7.
- [ ] In Protocol 90, require the parent summary to keep an assumption conflict
      visible until it is resolved, record the selected interpretation and
      decision owner when evidence is sufficient, and request a human decision
      when it is not. Maps to AC3 and AC4.
- [ ] Update
      `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      so a planning handoff receives current-batch context when present and a
      conflict becomes a named `unclear_requirements` stop before implementation.
      The stop message must name #1201-style affected item identity, competing
      evidence, and the concrete parent/human action required. Maps to AC2-AC4.
- [ ] In Protocol 91's `Plan Ready` transition, require applicable plan
      assumption records to be handed to the implementer for fresh verification.
      A changed, conflicting, or unverifiable result returns to the parent
      orchestrator and prevents implementation mutation. Maps to AC5 and AC6.
- [ ] Preserve existing explicit-list scope, worktree isolation, artifact-base,
      review, CI, tracker, checkpoint, and merge-authority behavior. The new gate
      adds evidence and a stop; it does not replace another gate.

### Implementation Guidance

- [ ] Update
      `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
      so Full Pipeline and Refactor paths read the plan's assumption section and
      re-verify every applicable source before the first implementation file
      edit. Maps to AC5.
- [ ] Specify that `Not applicable` requires no PR scan at implementation start,
      while an applicable `Still valid` result is recorded in the implementation
      PR's pre-submission evidence. A changed/conflicting/unverifiable result
      stops and returns the evidence to the parent orchestrator. Maps to AC5-AC7.
- [ ] Clarify that Fast Track and Hotfix paths without a plan do not synthesize a
      plan-time assumption record; their existing operational checks remain
      authoritative.

### Review Contract

- [ ] Update `REVIEW.md` Plan Review Checklist to verify applicability,
      provenance, verification time, bounded scope, same-surface relevance,
      conflict resolution state, and the concise not-applicable path. Missing or
      unresolved applicable evidence is blocking. Maps to AC1-AC4, AC7, and AC8.
- [ ] Update the Code Review Checklist to verify implementation-start
      re-verification evidence for plan-backed work and treat changed/conflicting
      evidence followed by implementation mutation as blocking. Maps to AC5 and
      AC6.
- [ ] Add the decision-gate matrix consistency requirement described below so
      protocol, template, runner guidance, review text, tests, and examples use
      the same outcomes and next actions.

### Agent, Skill, and Command Mirrors

Update every file below in the same implementation PR. These are the complete
applicable planning, implementation, parent-orchestration, item-orchestration,
and bounded-batch surfaces identified by the live searches and canonical
protocol references:

- [ ] `.claude/agents/tech-lead.md`
- [ ] `.cursor/agents/tech-lead.md`
- [ ] `.codex/skills/workflow-plan-writer/SKILL.md`
- [ ] `.claude/agents/developer.md`
- [ ] `.cursor/agents/developer.md`
- [ ] `.codex/skills/workflow-implementer/SKILL.md`
- [ ] `.claude/agents/orchestrator.md`
- [ ] `.cursor/agents/orchestrator.md`
- [ ] `.codex/skills/workflow-orchestrator/SKILL.md`
- [ ] `.claude/agents/item-orchestrator.md`
- [ ] `.cursor/agents/item-orchestrator.md`
- [ ] `.codex/skills/workflow-item-orchestrator/SKILL.md`
- [ ] `.claude/commands/run-items.md`
- [ ] `.cursor/commands/run-items.md`
- [ ] `.agents/skills/run-items/SKILL.md`
- [ ] `.agents/skills/run-items/agents/openai.yaml`

The `.agents/skills/workflow-plan-writer`,
`.agents/skills/workflow-implementer`,
`.agents/skills/workflow-orchestrator`, and
`.agents/skills/workflow-item-orchestrator` paths are tracked symlink aliases to
the corresponding `.codex/skills/` directories. Verify that every alias still
resolves after the canonical Codex skill edit; do not replace or duplicate the
symlinks. Each runner surface should state only its role-specific responsibility
and point to the canonical protocol rather than copying the full matrix.

The implementation must also inspect the following reviewer wrappers and leave
them unchanged when their existing `REVIEW.md` delegation remains sufficient;
record that disposition in the implementation PR:

- `.claude/agents/implementation-plan-reviewer.md`
- `.cursor/agents/implementation-plan-reviewer.md`
- `.agents/skills/workflow-plan-reviewer/SKILL.md`
- `.codex/skills/workflow-plan-reviewer/SKILL.md`

### Documentation and Regression Coverage

- [ ] Update `docs/workflow/development-workflow/README.md` with a concise
      statement that applicable operational assumptions are recorded at plan
      time, resolved by the parent on conflict, and re-verified at
      implementation start.
- [ ] Add
      `scripts/development-workflow/tests/test-cross-cutting-plan-assumption-contract.sh`
      using the existing workflow contract-test pattern. Use fixed-string or
      narrowly anchored assertions for required headings, evidence fields,
      outcomes, bounded-scope language, parent/human resolution, and
      implementation-start re-verification across the canonical and mirrored
      surfaces.
- [ ] Include negative assertions proving the not-applicable contract forbids a
      repository-wide PR scan and shared-keyword-only conflict classification.
- [ ] Update the smoke runbook if implementation wording or exact surface names
      change, while preserving AC1-AC8 coverage.

---

## Cross-Cutting Checklist Classification

This is a cross-cutting checklist plan. It introduces a conditional workflow
safety category that applies to every plan and plan-backed implementation.
Therefore the plan explicitly enumerates the planning protocol, developer
protocol, tech-lead and developer agents, Codex plan/implementation skills,
review contract, parent/item orchestration, bounded batch commands, template,
README, and tests above. No required surface is delegated to future discovery.

`AGENTS.md`, the project architecture placeholders, database guidance,
post-merge protocols, spec-writing guidance, and release flows were reviewed and
do not need changes: they neither create plan assumptions nor govern the
plan-to-implementation gate.

---

## Complex Workflow Decision-Gate Consistency Matrix

| Gate input | Allowed outcome | Required next action | Evidence / owner | Mirror surfaces | Example |
| --- | --- | --- | --- | --- | --- |
| Plan relies on an applicable operational assumption and bounded evidence agrees | `Verified` | Record value, source, verification time, bounded scope, and result; continue planning | Planner owns plan evidence | Protocol 02, template, tech-lead/plan-writer guidance, `REVIEW.md` | Approved base agrees with batch handoff and related PR evidence |
| Applicable assumption has conflicting or unverifiable evidence | `Conflict` | Record competing evidence and affected statements; stop implementation pending resolution | Planner reports; parent orchestrator owns resolution | Protocols 02/90/91, plan guidance, review contract | A related PR changes the linked project named by the plan |
| Parent has sufficient authoritative evidence | `Resolved` | Record selected interpretation and decision owner; update plan; allow planning/readiness to resume | Parent-orchestrator decision record | Protocols 90/91 and orchestrator/item-orchestrator mirrors | Owning config identifies one canonical environment |
| Parent lacks sufficient evidence | `Human decision required` | Stop with `unclear_requirements` and request a human decision | Human supplies authoritative interpretation | Protocols 90/91 and orchestrator/item-orchestrator mirrors | Competing configs name different canonical values |
| Plan has no applicable operational assumption | `Not applicable` | Record concise rationale; do not scan every open PR | Planner owns rationale | Protocol 02, template, planning guidance, `REVIEW.md` | Prose-only change has no environment, base, linked resource, or canonical config dependency |
| Implementation-start source check matches plan record | `Still valid` | Record the current result and begin implementation | Implementer owns fresh evidence | Protocols 03/91, developer/implementer guidance, code review | Recorded base and owning config remain unchanged |
| Implementation-start source changed, conflicts, or cannot be verified | `Stale or conflicting` | Stop before file edits and return evidence to parent orchestrator | Implementer reports; parent/human resolves | Protocols 03/91, developer/implementer and item-orchestrator guidance, code review | Approved base changed after plan approval |

The implementation must preserve these exact seven logical rows. Wording may be
shortened for role-specific mirrors, but no mirror may add a different outcome,
skip the required next action, or convert a conflict into an automatic guess.

---

## Parser/API/Concurrency Classification

- **Parser-risk**: Not applicable. The implementation changes workflow
  documentation and uses fixed-string/anchored regression assertions; it does
  not introduce a parser, tokenizer, scanner, suppression syntax, or regex-heavy
  structured-text engine.
- **API surface**: Not applicable. No public or internal application API,
  command option, configuration schema, or external service contract is added.
  The handoff adds documented evidence fields to existing orchestration context.
- **Single-snapshot/consistency semantics**: Applicable. Plan-time evidence is a
  dated snapshot, and Protocol 03's mandatory source re-read is the mechanism
  that prevents treating it as current indefinitely. Parent resolution records
  are the mechanism that makes a known conflict non-silent.
- **Concurrent-event-source**: Not applicable. No listeners, timers, callbacks,
  queues, or shared mutable runtime state are introduced.
- **Database/data approval**: Not applicable. There are no schemas, migrations,
  seeds, production records, or data-model approvals.

---

## Testing Strategy

**Test types**: Workflow shell contract regression, markdown lint, shell guard,
and manual smoke review.

**Key scenarios to test**:

1. Applicable plan evidence contains value, source, time, bounded scope, and
   result. Maps to AC1 and AC2.
2. Same-surface conflicting evidence records both sides and blocks
   implementation until parent resolution. Maps to AC3 and AC8.
3. An unresolvable conflict requests a human decision through the named
   orchestration stop. Maps to AC4.
4. A plan-backed implementer re-reads every applicable source and records
   `Still valid` before editing. Maps to AC5.
5. Changed, conflicting, or unverifiable implementation-start evidence stops
   before edits and returns to the parent. Maps to AC6.
6. A plan without an applicable assumption records `Not applicable` and avoids
   an all-open-PR scan. Maps to AC7.
7. Shared terminology without evidence about the same operational surface does
   not become a conflict. Maps to AC8.
8. Canonical protocols, templates, mirrors, commands, review rules, README, and
   the seven-row matrix retain the same outcome/next-action contract.

**Smoke test runbook**:
`docs/testing/workflow/1201-cross-check-cross-cutting-plan-assumptions.smoke-test.md`

**Regression suite**: Add and run
`scripts/development-workflow/tests/test-cross-cutting-plan-assumption-contract.sh`.
Treat any non-zero exit as blocking and do not interpret partial output as
evidence. Also run the existing relevant workflow contract tests if the
implementation touches their asserted files.

---

## Seed Data

No application seed data or generated product artifact is required. The
contract test operates on repository files and may use temporary copies for
negative assertions, cleaned up with a shell `trap`.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
      — define classification, evidence, bounded cross-check, conflict, and
      not-applicable planning behavior.
- [ ] `docs/workflow/development-workflow/templates/implementation-plan-template.md`
      — expose the applicable evidence table and not-applicable alternative.
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
      — require implementation-start re-verification before edits.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      — pass bounded batch context and own resolvable conflicts.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      — enforce conflict stops, human escalation, and implementer handoff.
- [ ] `docs/workflow/development-workflow/README.md` — summarize the
      plan-to-implementation operational-assumption lifecycle.
- [ ] `REVIEW.md` — add plan and code review requirements.
- [ ] All agent, skill, and command files enumerated under **Agent, Skill, and
      Command Mirrors** — align their role-specific responsibilities.
- [ ] `CHANGELOG.md` — implementation PR only; this plan PR must not modify it.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The requirement causes every planner to scan all open PRs. | Medium | High | Make applicability conditional, use the exact current-batch list plus only plausibly related PRs, and regression-test the no-unbounded-scan language. |
| Shared words create false conflicts. | Medium | Medium | Require evidence that another item changes the same operational assumption surface; test a keyword-only negative case. |
| Parent, planner, and implementer use different outcome names or next actions. | Medium | High | Keep the seven-row matrix canonical, use role-specific pointers, and assert required outcomes across mirror surfaces. |
| A plan-time check is treated as current after approval. | Medium | High | Require a source re-read before implementation edits; code review blocks missing fresh evidence. |
| Concurrent implementation PRs touch the same protocol sections. | High | Medium | Re-run the surface and in-flight checks immediately before implementation, rebase through normal PR workflow when needed, and preserve issue-specific edits. |
| `.agents` symlink aliases stop resolving to the canonical Codex skills. | Low | Medium | Edit the tracked `.codex` skill files, preserve the `.agents` symlinks, and assert alias resolution in the contract test. |

---

## Code Samples

No production code sample is prescribed. The implementation should follow the
existing shell contract-test helpers and keep all workflow prose authoritative
in Protocols 02, 03, 90, and 91.

---

## Residual Verification Strategy

This is pattern-completeness work across workflow mirrors. Before the
implementation PR receives `ready-for-human-review`, re-run the direct
planning/implementation guidance search from the Verification Log plus searches
for `Cross-Cutting Operational Assumption`, `Not applicable`, `Still valid`,
and `unclear_requirements`. The implementation PR must provide:

- the resulting paths for every required outcome phrase;
- the contract-test result covering all enumerated required files;
- an explicit unchanged-with-rationale disposition for each reviewed reviewer
  wrapper;
- no unexplained residual file that invokes an affected stage while omitting its
  role-specific requirement.

Use `scope-residual-gate.sh` if its classifier marks the implementation as
pattern-completeness work. A remaining unexplained residual blocks readiness;
it must be completed, proved out of scope, or linked to an approved follow-up.

---

## Implementation Order

1. Re-verify the operational assumption table against its recorded sources and
   bounded current-batch context. Stop before edits and return to the parent
   orchestrator if ownership/base evidence changed, conflicts, or cannot be
   verified.
2. Add
   `scripts/development-workflow/tests/test-cross-cutting-plan-assumption-contract.sh`
   with positive and negative contract assertions for the canonical and
   mirrored surfaces.
3. Update Protocol 02 and the implementation-plan template with the classifier,
   applicable evidence fields, conflict record, bounded relevance check,
   not-applicable rationale, and no-unbounded-scan rule.
4. Update Protocols 90 and 91 with exact current-batch handoff context,
   parent-owned conflict resolution, `unclear_requirements` human escalation,
   and the Plan Ready implementation gate.
5. Update Protocol 03 with plan-backed implementation-start re-verification and
   record/stop behavior before the first file edit.
6. Update `REVIEW.md` with plan-review and code-review enforcement for the same
   seven matrix outcomes.
7. Update every agent, skill, and command file enumerated above. Inspect the four
   reviewer wrappers and record any unchanged disposition in the implementation
   PR description.
8. Update `docs/workflow/development-workflow/README.md` with the lifecycle
   summary.
9. Run the new contract test and relevant existing workflow contract tests.
   Confirm the output is readable and every intentional negative fixture fails
   when its required phrase is removed.
10. Run `shellcheck --severity=warning` on the new shell test and
    `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`.
11. Run markdown lint and heuristic lint on all changed workflow docs and the
    smoke runbook; run `git diff --check`.
12. Re-run the Residual Verification Strategy and include its path evidence,
    reviewed-wrapper dispositions, and decision-gate matrix pointer in the
    implementation PR description.
13. Update `CHANGELOG.md` under `[Unreleased]` in the implementation PR only
    with this literal entry:
    `- **Cross-check cross-cutting plan assumptions** (#1201): Require plans to record applicable operational assumptions, bounded in-flight conflict checks, parent resolution, and implementation-start re-verification.`

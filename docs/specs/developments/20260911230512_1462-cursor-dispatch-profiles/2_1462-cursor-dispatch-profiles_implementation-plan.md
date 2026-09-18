# Cursor Dispatch Profiles — Implementation Plan

**Spec**: [Cursor Dispatch Profiles](1_1462-cursor-dispatch-profiles_specs.md)
**Smoke test runbook**: [Cursor Dispatch Profiles](../../../testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md)

---

## Summary

**Approach**: Add a canonical integration guide (`cursor-dispatch-profiles.md`) that
defines the three profiles, orchestration layers, decision matrix, declaration
contract, handoff metadata, and worked examples. Mirror that contract onto every
bounded-command entrypoint, portfolio and item orchestration role documents,
Protocols 90/91/95, `agent-model-config.md`, and `.cursor/rules/workflow.mdc`.
Extend `guardrails-enforcement.md` section 4 with the two new named stop
conditions. Resolve the spec's pre-branch `/run-items` affected-item gap in this
plan and propagate it through the canonical doc and stop-message guidance.

**Estimated complexity**: L

**Rationale**: The change is documentation-heavy but must stay internally
consistent across many mirror surfaces, reproduce the full decision matrix
without restating role contracts, and give operators a self-service path under
Cursor Remote Control. Wrong or drifted wording drops gates in production runs.

**Dependencies**: Spec PR [#1732](https://github.com/lhpaul/ai-dev-framework-template/pull/1732)
is merged to `develop`. No other feature must merge first. Related gaps **#1745**
(batch-context marker enforcement) and **#1746** (stage-role harness permission
denial) remain out of scope and must be referenced, not solved, here.
Verified `2026-09-18` via `gh issue view 1745 --json state` / `gh issue view 1746
--json state`: both **OPEN**. Consequence if either closes before or during
implementation: re-check the issue resolution text, then either (a) keep the
canonical-doc / guardrails / role-agent "out of scope" callouts only if the
closed issue did not land a conflicting contract, or (b) update those surfaces
in the same implementation PR so they no longer assert an unresolved gap.

**Design assets**: None. Workflow documentation only.

---

## Verification Log

Re-run `2026-09-18` at plan-review fix (repo `6be6ad46`). `rg` patterns use
Rust-regex alternation (`a|b`), not grep-BRE `\|` (which matches a literal pipe).

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `6be6ad46` (plan-review fix baseline; earlier plan draft recorded `32605700`) |
| Canonical doc absent pre-impl | `test ! -f docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md && echo absent` | `absent` |
| Profile strings outside development folder | `rg -l 'cursor-native-handoff|cursor-parent-orchestrated|cursor-inline-fallback' --glob '!docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/*'` | `docs/testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md` only (Plan Ready smoke runbook; no production mirror surfaces yet) |
| Bounded command adapters | `rg -l 'run-item' .cursor/commands .claude/commands .agents/skills/run-item .agents/skills/run-item-work .agents/skills/run-items .agents/skills/run-epic .agents/skills/run-work` | **18** hits, re-run 2026-09-18: **14** command/`SKILL.md` (`5` `.cursor/commands` + `4` `.claude/commands` + `5` `SKILL.md`) + **4** `agents/openai.yaml` (`14+4=18`). Literal extras vs the **15** Files-to-modify mirrors: the four yaml files are not edited; `.claude/commands/run-epic.md` is in Files to modify but **not** in the 18 (no `run-item` substring). |
| Orchestration role agents | `ls .cursor/agents/orchestrator.md .cursor/agents/item-orchestrator.md .claude/agents/orchestrator.md .claude/agents/item-orchestrator.md` | All four present |
| Spec merge gate | `gh pr view 1732 --json state,baseRefName` | `MERGED`, base `develop` |
| Related gap #1745 | `gh issue view 1745 --json state,title` | `OPEN` — batch-context marker enforcement; out of scope here |
| Related gap #1746 | `gh issue view 1746 --json state,title` | `OPEN` — stage-role harness permission denial; out of scope here |
| Stop conditions pre-impl | `rg 'dispatch_profile_declaration_missing|dispatch_handoff_unavailable' docs/workflow/development-workflow/guardrails-enforcement.md` | No matches (expected until implementation) |

---

## Cross-Cutting Operational Assumption Check

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Integration / artifact base branch | `develop` | `.ai-dev-workflow.yaml` + batch handoff | `2026-09-17T11:15:00Z`; repo `32605700` | Current invocation `#1462`; batch peers `#1757,#1462,#1496,#1515,#1561,#1583,#1529`; same-surface open PRs none | `Verified` |
| Repository mode | `single_repo` | Batch handoff `WORKFLOW_MODE` | `2026-09-17T11:15:00Z`; repo `32605700` | Peers touch adjacent workflow docs but do not change base branch or mode for this item | `Verified` |

Peer item `#1529` references dispatch profiles in its plan narrative only; it
does not alter the integration branch or artifact ownership for `#1462`.

---

## Plan-Stage Gap Resolution (spec § Known gaps)

**Gap**: Pre-branch, explicit-list `/run-items` declaration stops lack an
affected-work-item representation when no branch, PR, or development folder
exists yet.

**Decision (recorded here, propagated in implementation)**:

- For a declaration stop on an explicit-list `/run-items` invocation **before
  any item-scoped artifact exists**, the affected work item is a **single**
  string: `explicit_list_invocation_targets=#N1,#N2,...` using the invocation's
  ordered tracker identifiers (bare numbers with `#` prefix, comma-separated, no
  spaces).
- Report **once** for the whole invocation; do not emit one stop per target.
- Mirror this rule in:
  - `integrations/cursor-dispatch-profiles.md` (Named stop reporting subsection),
  - `guardrails-enforcement.md` section 4 row text for
    `dispatch_profile_declaration_missing`,
  - Protocol 90 explicit-list preamble (declaration checkpoint before item
    resolution / first mutation),
  - The merged spec's Named Stop-Condition Mapping table (implementation PR
    updates the spec file to close the documented gap).

---

## Architecture and Decision Boundary

### Decision 1: Canonical guide owns the matrix; mirrors link back

All profile rules, evaluation order, transitions, and examples live in
`docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md`.
Every mirror surface states the requirement and links to that file rather than
restating the matrix (AC1–AC3, AC10, AC18–AC19).

### Decision 2: Declared, not detected

Implementation adds **documentation and runner instructions only**. No shell
helper auto-detects Cursor environment capabilities (spec Out of Scope item 3).
Commands and orchestration protocols require a visible declaration block before
the first mutating action (or before reporting for read-only checkpoints).

### Decision 3: Standard declaration block

The canonical doc defines one markdown-friendly block operators and agents
copy into run output:

```markdown
<!-- Illustrative — adapt during implementation -->
**Dispatch profile**: Native handoff (`cursor-native-handoff`)
**Accountable orchestration role**: Work Item Runner (item layer)
**Accountability posture**: handed off intact
**Canonical reference**: docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md
```

Re-declarations repeat the block with a **Reason** line when the profile
changes mid-run.

### Decision 4: Prelude vs declaration ordering

The shared bounded prelude (`bounded-run-prelude.md`) may complete read-only
scope and policy resolution first. The dispatch-profile declaration still must
appear **immediately before the first mutating action** (branch create, file
edit that changes tracked artifacts, tracker mutation, PR open). For
`/run-work`, declaration precedes reporting scan results.

### Decision 5: Parent-orchestrated absorbs full role contract

Under `cursor-parent-orchestrated`, the current context performs every
orchestration obligation from the absorbed role's agent + protocol surfaces and
**delegates** spec/plan/implement/review work to stage roles with full handoff
metadata (`BATCH_CONTEXT`, isolation, branch, base, artifact repo root,
mutation class). No inline product work (AC4, AC19).

### Decision 6: Cursor environment defaults in agent-model-config

Add a **Cursor dispatch profiles** subsection listing, per environment ×
orchestration layer:

| Environment | Portfolio layer | Epic layer | Item layer | Evidence |
| --- | --- | --- | --- | --- |
| Cursor Desktop (local app) | Native handoff | Native handoff | Native handoff | Confirmed by observation (template default) |
| Cursor Remote Control | Parent orchestrated | Parent orchestrated | Parent orchestrated | Confirmed by observation (recorded failure mode) |
| Cursor Cloud Agents | Parent orchestrated | Parent orchestrated | Parent orchestrated | Explicit assumption (conservative default per spec) |

Unobserved environments use the more restrictive applicable profile until an
operator confirms otherwise in run output.

### Decision 7: Portfolio batch scheduling unchanged

Parent-orchestrated portfolio runs use Protocol 90 Step 4's existing
one-item-at-a-time fallback when Work Item Runner handoff is unavailable. This
feature does not add concurrent scheduling behavior (AC17).

---

## Workflow Decision-Gate Consistency Matrix

This feature is a **complex workflow decision gate** (REVIEW.md). The **normative
matrix is the merged spec** — do not maintain a shortened copy in this plan.

**Authoritative sources** (implementation must match verbatim):

- Spec [Decision-Gate Consistency Matrix](1_1462-cursor-dispatch-profiles_specs.md#decision-gate-consistency-matrix) — all input rows, evaluation order, mirror-surfaces list, examples requirement, and out-of-scope note for #1746.
- Spec [Named Stop-Condition Mapping](1_1462-cursor-dispatch-profiles_specs.md#named-stop-condition-mapping) — including the plan-resolved pre-branch explicit-list affected-item format.

**Implementation mapping** (where each authoritative row lands):

| Spec matrix row (summary) | Canonical doc section | Guardrails / protocols |
| --- | --- | --- |
| Native handoff + mutating command | § Decision gate — full row text | Protocols 90/91/95 declaration + handoff |
| Native handoff + read-only portfolio scan | § Decision gate + § Scan exception | `/run-work` mirrors |
| Parent orchestrated + mutating command | § Decision gate + § Absorbed contract | Role agents + protocols |
| Parent orchestrated + read-only scan | § Decision gate + § Scan exception | `/run-work` mirrors |
| Unconfirmed onward-handoff capability (initial handoff confirmed) + mutating / scan | § Decision gate + § Conservative defaults | `agent-model-config.md` assumptions |
| Native → parent re-declaration (mid-run orchestration failure, initial handoff still available) | § Transitions | Protocol 91 run summary |
| Native → inline re-declaration (mid-run failure + initial handoff lost) | § Transitions | Stop `dispatch_handoff_unavailable` |
| Parent → inline re-declaration (stage handoff unavailable) | § Transitions | Stop `dispatch_handoff_unavailable` |
| Parent orchestrated + reachable stage credential/permission denial | § Delegation failures | Reuse `missing_required_secret_or_permission` |
| No handoff / unconfirmed initial handoff + read-only | § Decision gate | Inline fallback observing posture |
| No handoff / unconfirmed initial handoff + would mutate | § Decision gate | Stop `dispatch_handoff_unavailable` |
| Declaration missing at first mutating action | § Declaration contract | `dispatch_profile_declaration_missing` |
| Invalid profile value / missing accountable role | § Declaration contract | Same stop |
| Declaration invalid at read-only checkpoint (scan / inline-fallback) | § Declaration contract | Same stop |
| Posture mismatch (`observing` at mutation or absorbed/handoff at read-only checkpoint) | § Accountability postures | Same stop |
| Profile/fact mismatch (more or less permissive than assigned outcome) | § Declaration contract + § Evaluation order | Same stop; excludes mid-run recovery rows per spec |
| Pre-branch explicit-list `/run-items` declaration stop | § Named stop reporting | Plan gap `explicit_list_invocation_targets=#N1,#N2,...` |

**Examples (required in canonical doc)**: one worked example per profile for the
item layer; at minimum Native handoff `/run-item`, Parent orchestrated
`/run-item` under Remote Control, Inline fallback mutating `/run-item`, and
read-only `/run-work` under each profile label.

---

## Layer-by-Layer Changes

### Documentation — canonical

- [ ] `docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md`
      — new file: profiles (code + display labels), three layers (portfolio /
      epic / item), perform / hand off / prohibit matrix by layer, detection
      heuristics (declared not detected), absorbing context (contract + scope +
      handoff arrangement), parent-orchestrated stage handoff metadata,
      workflow_hub artifact/tracker/cleanup notes, inline-fix prohibition and
      delegation outcomes (#1746 out of scope), batch-context marker honesty
      (#1745 out of scope), worked examples, pointer precedence (role contract
      wins). Maps to AC1–AC8, AC10–AC11, AC17–AC20.

### Documentation — mirror surfaces

- [ ] `.cursor/commands/run-item.md`, `run-item-work.md`, `run-items.md`, `run-epic.md`, `run-work.md`
      — declaration requirement + link to canonical doc; `/run-work` states
      scanning is read-only under every profile and that acting on scan results
      requires a **new bounded run with its own declaration**. Maps to AC9, AC11,
      AC12, AC18.
- [ ] `.claude/commands/run-item.md`, `run-item-work.md`, `run-items.md`, `run-epic.md`, `run-work.md`
      — same parity as Cursor commands (including `/run-work` AC12 scan posture).
      Maps to AC12, AC18.
- [ ] `.agents/skills/run-item/SKILL.md`, `run-item-work/SKILL.md`, `run-items/SKILL.md`, `run-epic/SKILL.md`,
      `run-work/SKILL.md` — same parity for Codex discovery path (including deprecated
      `/run-item-work` alias and `/run-work` AC12 clause). Maps to AC12, AC18.
- [ ] `.cursor/agents/orchestrator.md` and `.claude/agents/orchestrator.md` —
      no-onward-handoff behavior: return to invoking context; no inline product
      work; profile declaration when absorbing portfolio layer. Maps to AC13.
- [ ] `.cursor/agents/item-orchestrator.md` and
      `.claude/agents/item-orchestrator.md` — same for item layer; clarify
      parent-orchestrated stage delegation vs `SUBAGENT_PERMISSION_DENIAL`
      (Work Item Runner only). Maps to AC13, AC19.
- [ ] `.codex/skills/workflow-item-orchestrator/SKILL.md` — pointer to canonical
      doc for Codex item-orchestrator alias. Maps to AC18.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      — reference canonical doc when establishing execution arrangement;
      explicit-list declaration checkpoint; pre-branch affected-item string;
      parent-orchestrated Step 4 fallback cross-reference. Maps to AC5, AC14,
      AC17, plan gap resolution.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      — reference at execution arrangement; declaration before first mutation;
      parent-orchestrated item-runner obligations; run summary fields (profile,
      transitions, absorbed layers, stage handoffs). Maps to AC5, AC9, AC14.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      — same reference for epic layer entry. Maps to AC5, AC14.
- [ ] `docs/workflow/development-workflow/agent-model-config.md` — Cursor
      environment × layer profile table with confirmed vs assumption labels.
      Maps to AC15.
- [ ] `.cursor/rules/workflow.mdc` — profile declaration requirement + canonical
      link. Maps to AC16.
- [ ] `docs/workflow/development-workflow/guardrails-enforcement.md` section 4 —
      add `dispatch_profile_declaration_missing` and
      `dispatch_handoff_unavailable`. Each stop message must name (a) the stop
      condition string, (b) the affected work item, and (c) the human action to
      unblock: for `dispatch_profile_declaration_missing`, declare one of
      `cursor-native-handoff`, `cursor-parent-orchestrated`, or
      `cursor-inline-fallback` in the run preamble and re-invoke the bounded
      command; for `dispatch_handoff_unavailable`, either switch to a profile
      whose next layer is available or restore the handoff target, then
      re-invoke. Extend `dispatch_profile_declaration_missing` affected-item
      text for `explicit_list_invocation_targets=...`; document reuse of
      `missing_required_secret_or_permission` for reachable stage credential
      denial. Maps to AC10–AC11, AC19.
- [ ] `docs/workflow/development-workflow/README.md` — add integration doc to
      integrations list. Maps to discoverability (AC17).
- [ ] `docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md`
      — update Named Stop-Condition Mapping affected-item row for pre-branch
      explicit-list stops per plan gap resolution (spec already merged; align
      text with implementation). Maps to plan gap + AC10.

### Documentation — optional clarity

- [ ] `docs/workflow/development-workflow/bounded-run-prelude.md` — one paragraph
      on ordering: prelude read-only work may precede declaration; declaration
      still required before first mutation. Maps to Decision 4.

### Workflow tooling / tests

- [ ] `scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh`
      (**plan-added**; not named in the merged spec) — lightweight regression
      guard that fails when bounded command adapters, orchestration role agents,
      protocols 90/91/95, `agent-model-config.md`, `workflow.mdc`, and deprecated
      `run-item-work` command/skill aliases omit a link to
      `integrations/cursor-dispatch-profiles.md` or required profile code strings.
      Rationale: AC18 mirror parity is easy to break across 15+ surfaces; a
      cheap shell guard catches drift without requiring live Cursor Remote
      Control. Maps to AC18 regression safety.
- [ ] **Planted-violation proof** (same implementation PR): temporarily remove the
      canonical link from `.cursor/commands/run-item.md`, run the surface guard
      and confirm non-zero exit; restore the link and confirm exit 0. Record the
      before/after command output in the PR test plan.

### Database / Backend / Frontend / Infrastructure

- [ ] Not applicable — documentation and a doc-surface test only.

---

## Files to modify (implementation checklist)

Adapter/skill documentation mirrors to edit: **15** paths (5 `.cursor/commands` +
5 `.claude/commands` + 5 `.agents/skills/*/SKILL.md`). The Verification Log `rg`
returns **18** hits = **14** of those mirrors (it misses `.claude/commands/run-epic.md`)
+ **4** `agents/openai.yaml` files that are **not** edited (`14+4=18`).

| Path | Change |
| --- | --- |
| `docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md` | **Create** canonical guide |
| `docs/workflow/development-workflow/guardrails-enforcement.md` | Add stop conditions + affected-item guidance |
| `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | Reference + declaration gate + explicit-list stop |
| `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Reference + declaration + summary fields |
| `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | Reference + declaration |
| `docs/workflow/development-workflow/agent-model-config.md` | Cursor profile table |
| `docs/workflow/development-workflow/bounded-run-prelude.md` | Optional ordering note |
| `docs/workflow/development-workflow/README.md` | Integrations list entry |
| `.cursor/commands/run-item.md` | Mirror |
| `.cursor/commands/run-item-work.md` | Mirror (deprecated alias) |
| `.cursor/commands/run-items.md` | Mirror |
| `.cursor/commands/run-epic.md` | Mirror |
| `.cursor/commands/run-work.md` | Mirror |
| `.claude/commands/run-item.md` | Mirror |
| `.claude/commands/run-item-work.md` | Mirror (deprecated alias) |
| `.claude/commands/run-items.md` | Mirror |
| `.claude/commands/run-epic.md` | Mirror |
| `.claude/commands/run-work.md` | Mirror |
| `.agents/skills/run-item/SKILL.md` | Mirror |
| `.agents/skills/run-item-work/SKILL.md` | Mirror (deprecated alias) |
| `.agents/skills/run-items/SKILL.md` | Mirror |
| `.agents/skills/run-epic/SKILL.md` | Mirror |
| `.agents/skills/run-work/SKILL.md` | Mirror |
| `.cursor/agents/orchestrator.md` | No-handoff + profile |
| `.cursor/agents/item-orchestrator.md` | No-handoff + profile |
| `.claude/agents/orchestrator.md` | Parity |
| `.claude/agents/item-orchestrator.md` | Parity |
| `.codex/skills/workflow-item-orchestrator/SKILL.md` | Pointer |
| `.cursor/rules/workflow.mdc` | Requirement + link |
| `docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md` | Named stop affected-item alignment |
| `scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh` | **Create** surface guard |
| `changelog.d/1462.feature.cursor-dispatch-profiles.md` | **Create** release-note fragment (implementation PR only) |
| `docs/testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md` | Already created in Plan Ready |

**Explicitly not in scope**: `REVIEW.md` checklist categories (no new review
gate category); `--dispatch-profile` CLI flag (BO-9); automated environment
detection; stage-role permission denial recovery (#1746); enforcing
`BATCH_CONTEXT` marker absence as a stage stop (#1745).

---

## Testing Strategy

**Test types**: Shell surface guard, markdown lint, manual smoke (documentation).

**Key scenarios**:

1. Every mirror surface links to `cursor-dispatch-profiles.md` and names the three
   profile code values consistently (AC18).
2. Guardrails section 4 lists both new stop conditions with definitions matching
   the spec matrix (AC10–AC12), including coarse-facts mismatch rejection in both
   directions (more and less permissive than assigned outcome).
3. Orchestration role agents instruct return-to-invoker when onward handoff is
   unavailable (AC13).
4. Agent-model-config states confirmed vs assumption for each Cursor environment
   (AC15).
5. Smoke runbook walks Native handoff desktop, Parent orchestrated Remote
   Control, Inline fallback, and read-only scan paths (AC6, AC17).
6. Smoke Step 10 (AC19): parent-orchestrated inline-product-work prohibition is
   not relaxed by any other document; #1746 remains Out of Scope; 
   `SUBAGENT_PERMISSION_DENIAL` is worded as observably similar only (Work Item
   Runner boundary).
7. Smoke Step 11 (AC20): three accountability postures are defined; `observing`
   is valid only at read-only checkpoints; posture mismatch is treated as a
   missing declaration.

**Smoke test runbook**:
`docs/testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md`

**Regression suite**: Add
`scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh`.
No extra registration step: `.github/workflows/workflow-tests.yml` runs suites
discovered by `list_suites` in `scripts/development-workflow/select-test-suites.sh`
(`find scripts/development-workflow/tests -maxdepth 1 -name 'test-*.sh'`).
Placing the file in that directory is the harness entrypoint.

---

## Seed Data

Not applicable — no runtime data.

---

## Documentation Updates (post-implementation, developer checklist)

- [ ] `changelog.d/1462.feature.cursor-dispatch-profiles.md` — implementation PR
      only; body:
      `- **Cursor dispatch profiles** (#1462): Document native-handoff, parent-orchestrated, and inline-fallback profiles for Cursor bounded commands with consistent declaration gates and named stop conditions.`
      Do **not** edit `CHANGELOG.md` directly in the implementation PR.
- [ ] `AGENTS.md` — optional one-line link under Key Documentation to
      `integrations/cursor-dispatch-profiles.md` if the workflow table is updated
      for discoverability (recommended, not strictly required by AC).

---

## Document Quality Gate (plan stage)

| Check | Result | Notes |
| --- | --- | --- |
| Spec coverage | Pass | Plan maps to AC1–AC20 via layer checklist; BO-9/BO-10 deferred per spec |
| Implementation-order consistency | Pass | Canonical doc before mirrors; guardrails before surface guard |
| Verification support | Pass | Verification Log + surface guard + planted-violation proof + smoke runbook |
| Decision-gate applicability | Pass | Complex gate — authoritative spec matrix + implementation mapping table |
| Parser-risk addendum | N/A | No new structured-text parser |
| Concurrent-event-source addendum | N/A | No concurrent event handlers |
| Cross-cutting checklist addendum | N/A | No new REVIEW.md checklist category |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Mirror surfaces drift from canonical doc | High | High | Surface guard test + smoke runbook cross-check |
| Operators confuse prelude with declaration | Medium | Medium | bounded-run-prelude ordering note + examples |
| Restating role contracts causes drift | Medium | High | Matrix links to protocols/agents only (spec Out of Scope 4) |
| Batch explicit-list stop wording inconsistent | Medium | Medium | Plan gap decision + spec row update in same PR |
| Conflicts with #1745 / #1746 scope creep | Medium | High | Explicit out-of-scope callouts in canonical doc |

---

## Implementation Order

1. **Canonical doc** — create `integrations/cursor-dispatch-profiles.md` with
   full matrix, examples, and gap references (#1745, #1746). Commit.
2. **Guardrails** — add named stop conditions and pre-branch affected-item text.
   Commit.
3. **Protocols 90, 91, 95** — reference canonical doc at execution
   arrangement; add declaration checkpoints and summary fields. Commit.
4. **Command + skill mirrors** — Cursor, Claude, Codex `.agents/skills` adapters.
   Commit.
5. **Role agents** — orchestrator + item-orchestrator (Cursor + Claude) + Codex
   workflow-item-orchestrator skill. Commit.
6. **agent-model-config + workflow rule + README + optional bounded-prelude** —
   Commit.
7. **Spec alignment** — update merged spec Named Stop-Condition Mapping row for
   explicit-list affected item. Commit. **Order note / reversal risk**: do not
   run this before step 2 (guardrails) or before the plan-gap wording is stable
   in the canonical doc (step 1). Reversing step 7 ahead of guardrails risks
   shipping a merged-spec row that disagrees with section 4 stop text, or
   rewriting the spec twice when guardrail wording settles. Spec alignment may
   land in the same commit as guardrails if both use the identical
   `explicit_list_invocation_targets=...` string; otherwise keep this after
   step 2.
8. **Surface guard test** — add and register shell test; run locally. Commit.
9. **Verify** — run markdown lint commands from `AGENTS.md`, surface guard, and
   execute smoke runbook steps that do not require live Remote Control (document
   manual Remote Control steps as PASS/NOT RUN).
10. **Changelog fragment** — create `changelog.d/1462.feature.cursor-dispatch-profiles.md`
      with the literal bullet from **Documentation Updates** (implementation PR only).
11. **Planted-violation proof** — run surface guard fail/pass cycle documented in
      **Layer-by-Layer Changes → Workflow tooling**.

---

## Cross-Cutting Operational Assumption Records (for implementer)

| ID | Assumption | Authoritative source | Implementation-start check |
| --- | --- | --- | --- |
| A1 | Artifact base branch remains `develop` | `.ai-dev-workflow.yaml` / handoff | `git merge-base --is-ancestor origin/develop HEAD` |
| A2 | `single_repo` — hub owns all artifacts | Batch handoff | No product-repo selector required |
| A3 | Pre-branch explicit-list affected item format | This plan § Plan-Stage Gap Resolution | Still valid if canonical + guardrails rows match |

Implementer must record `Still valid` or `Stale or conflicting` before file
edits per Protocol 03 assumption check.

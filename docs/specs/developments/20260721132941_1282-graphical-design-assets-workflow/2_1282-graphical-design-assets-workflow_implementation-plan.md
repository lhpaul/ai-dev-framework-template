# Graphical Design Assets in the Workflow — Implementation Plan

**Spec**: [`1_1282-graphical-design-assets-workflow_specs.md`](./1_1282-graphical-design-assets-workflow_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/1282-graphical-design-assets-workflow.smoke-test.md`](../../../testing/workflow/1282-graphical-design-assets-workflow.smoke-test.md)

---

## Summary

**Approach**: Add a canonical design-assets convention doc, then wire it into
`/add-backlog-item` (protocol + Claude/Cursor/Codex command surfaces), optional
GitHub attach helper behavior in `add-backlog-item.sh`, and lightweight discovery
plus expected-vs-actual fidelity hooks in plan/smoke protocols and the agents
that load them. Keep the MVP documentation- and convention-first: no visual
regression platform, no design-reviewer-as-primary fidelity gate, and no
`/merged-qa` (#1283).

**Estimated complexity**: M

**Rationale**: Touches several mirrored workflow surfaces (protocol, three
command entrypoints, helper/tests, plan/smoke guidance, and stage agents) but
avoids new subsystems or CI screenshot infrastructure.

**Dependencies**: None. Sibling items #1281 and #1284 are orthogonal and must
not be edited. #1283 is explicitly out of scope (enablement only).

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `160bb5e` |
| Add-backlog surfaces | `find .claude/commands .cursor/commands .agents/skills -name '*add-backlog*'` | `.claude/commands/add-backlog-item.md`, `.cursor/commands/add-backlog-item.md`, `.agents/skills/add-backlog-item` (+ `SKILL.md`) |
| Canonical protocol | `test -f docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md` | Present (225 lines); no design-asset steps today |
| Helper + tests | `ls scripts/development-workflow/add-backlog-item.sh scripts/development-workflow/tests/test-add-backlog-item.sh` | Present; helper creates issues / sets project fields; no attach path today |
| Plan/smoke protocols | `ls docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md docs/workflow/development-workflow/protocols/04-smoke-test-protocol.md` | Present; no design-asset discovery or fidelity hooks today |
| Stage agents referencing those protocols | `rg -l "00-add-backlog-item-protocol\|04-smoke-test-protocol\|02-generate-implementation-plan" .claude/agents .cursor/agents .codex/skills .agents/skills` | smoke-tester + tech-lead (Claude/Cursor), workflow-plan-writer, add-backlog skill |
| Existing "design asset" workflow guidance | `rg -n "Design assets\|design asset\|graphical" docs scripts .claude .cursor .agents` (excluding this item's spec) | No existing convention doc; only this item's spec |

---

## Technical Decisions

### Decision 1 — Canonical convention doc

Create
`docs/workflow/development-workflow/design-assets.md` as the single source of
truth for:

1. Candidate file recognition (likely vs ambiguous vs clearly non-design)
2. Storage layout
3. Agent discovery order
4. Issue-body recording template
5. Lightweight fidelity-check expectations

Protocols and command surfaces link here rather than redefining rules.

### Decision 2 — Storage layout

| When | Where | Notes |
| --- | --- | --- |
| Backlog creation | Tracker attachments (GitHub Issues / Linear / provider-native) | Primary store before a development folder exists |
| After development folder exists | `<dev-folder>/assets/` | Canonical on-disk location under the item's own `docs/specs/developments/<timestamp>_<slug>/` directory |
| Always | Issue / work-item body section `## Design assets` | Lists locations and states that plan/smoke should use them as fidelity references |

Exact folder name: **`assets/`** (not `design-assets/`) to stay short and stable.
Only design-reference files belong there; incidental attachments stay tracker-only
and are not copied into `assets/`.

Migration rule (spec stage and later): when a development folder is created or
first used and tracker design assets exist, copy or download confirmed design
assets into `<dev-folder>/assets/` and update the issue-body location note.
Do not invent assets when none exist.

### Decision 3 — Recognition heuristics (agent-facing, not a parser module)

Treat as **likely design assets** when the supplied file extension (case
insensitive) is one of:

- HTML mockups: `.html`, `.htm`
- Images: `.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.svg`
- PDF mockups: `.pdf`

Treat as **clearly non-design** (do not stage as design references): `.log`,
`.csv`, common source extensions (`.ts`, `.tsx`, `.js`, `.jsx`, `.py`, `.go`,
`.rs`, `.java`, `.rb`, `.sh`), and lock/config dumps unless the human explicitly
says they are design references.

Treat as **ambiguous** (ask one brief clarifying question): other files (for
example `.md`, `.txt`, `.docx`, `.zip`) or mixed batches where intent is unclear.
After clarification, still create **exactly one** backlog item.

This recognition lives in the convention doc and protocol text. Do **not** add a
new lint/parser scanner module for MVP (parser-risk classifier: not applicable).

### Decision 4 — Capture flow in `/add-backlog-item`

Extend protocol `00` with a step between clarify-intent and create:

1. Detect candidate files from the invocation (chat attachments, local paths).
2. Classify each file (likely / ambiguous / non-design).
3. Ask at most one brief clarifying question covering the ambiguous set.
4. Create the backlog item (unchanged destination / Type / Priority / Size rules).
5. Attach or upload confirmed design assets via provider-native means when
   available; on failure, record local paths in the body and ask the human to
   attach manually — do not fail item creation solely because upload failed.
6. Append the `## Design assets` body section (or include it in the initial body).

Command surfaces (Claude / Cursor / Codex) get short bullet reminders that point
at protocol `00` + `design-assets.md`; they do not fork the rules.

### Decision 5 — Optional helper enhancement

Extend `scripts/development-workflow/add-backlog-item.sh` only if a small,
testable GitHub path is practical (for example `--attach <path>` after create
that uploads or comments with a durable link). If provider APIs make reliable
attachment impractical in-shell, keep attachment agent-driven and document the
exact `gh`/MCP recipe in `design-assets.md`. Either outcome satisfies AC1 as long
as the protocol requires attach-or-stage and body recording.

Update `scripts/development-workflow/tests/test-add-backlog-item.sh` for any new
helper flags or no-op paths.

### Decision 6 — Discovery order (agents)

Before UI-facing plan or smoke work, agents check in order:

1. Issue / work-item body `## Design assets` section (canonical pointers)
2. Tracker attachments on the work item
3. Linked files referenced from the issue body
4. `<dev-folder>/assets/` when the development folder exists

If none found: continue normally; do not invent a baseline (AC5).
If locations conflict: ask the human once which reference is authoritative.

Orthogonal siblings (#1281, #1284, or unrelated issues) are never asset sources.

### Decision 7 — Plan and smoke fidelity hooks

- Protocol `02`: when writing/updating the smoke runbook, if discovery finds
  assets, include at least one expected-vs-actual fidelity step that names the
  reference asset(s). If none, omit fidelity steps.
- Protocol `04`: when a runbook includes fidelity steps, execute them as
  lightweight human/agent visual comparison (not pixel diff). Record PASS/FAIL
  with expected-vs-actual detail on failure.
- `smoke-tester` agents (Claude/Cursor): brief pointer to discovery + fidelity
  recording rules in protocol `04` / `design-assets.md`.
- `tech-lead` / `workflow-plan-writer`: brief pointer to discovery before runbook
  authoring.
- `product-manager` / `developer` (and matching Cursor agents / Codex
  spec/implement skills): brief discovery pointer so UI-facing stages notice
  assets; do **not** make design-reviewer the primary fidelity gate.

### Decision 8 — Out of scope (encode as non-goals in docs)

- `/merged-qa` / #1283 implementation
- design-reviewer as primary mockup-fidelity gate
- Automated visual-regression platform (pixel diffs, baseline vaults, CI
  screenshot suites)
- Edits to #1281 or #1284 artifacts

---

## Classifier results

| Classifier | Applies? | Rationale |
| --- | --- | --- |
| Parser-risk | No | Extension allowlists and protocol heuristics only; no new parse/lint scanner module |
| Concurrent-event-source | No | No concurrent listeners, shared mutable runtime state, or race-prone init/teardown |
| Cross-cutting checklist | No | Does not add a mandatory REVIEW.md / every-plan checklist category; fidelity steps apply only when assets exist |

---

## Layer-by-Layer Changes

### Shared Packages / Libraries

- [ ] Add `docs/workflow/development-workflow/design-assets.md` (canonical
  recognition, storage, discovery, body template, fidelity expectations).
- [ ] Optionally extend `scripts/development-workflow/add-backlog-item.sh` with
  attach support or documented no-op + agent recipe; update
  `scripts/development-workflow/tests/test-add-backlog-item.sh` accordingly.

### Infrastructure / Configuration

- [ ] No `.ai-dev-workflow.yaml` schema changes required for MVP.

### Workflow documentation & command surfaces

- [ ] Extend
  `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md`
  with candidate-file recognition, clarifying question, attach/stage, and body
  recording (AC1–AC3, AC8).
- [ ] Update `.claude/commands/add-backlog-item.md`,
  `.cursor/commands/add-backlog-item.md`, and
  `.agents/skills/add-backlog-item/SKILL.md` with short asset-handling bullets
  pointing at protocol `00` + `design-assets.md`.
- [ ] Extend
  `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
  so plan writers discover assets and add fidelity steps to smoke runbooks when
  present (AC5, AC6).
- [ ] Extend
  `docs/workflow/development-workflow/protocols/04-smoke-test-protocol.md` so
  smoke execution records PASS/FAIL expected-vs-actual for fidelity steps (AC7).
- [ ] Update
  `docs/workflow/development-workflow/templates/smoke-test-runbook-template.md`
  with an optional fidelity-step placeholder (include when design assets exist;
  omit when none).
- [ ] Optionally note discovery during development-folder creation in
  `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`
  (copy confirmed assets into `<dev-folder>/assets/` when creating the folder).
- [ ] Cross-link from `docs/workflow/development-workflow/README.md` (and
  `docs/testing/README.md` if smoke discovery belongs there) to
  `design-assets.md`.

### Agent / skill mirrors

- [ ] `.claude/agents/smoke-tester.md` and `.cursor/agents/smoke-tester.md` —
  discovery + fidelity recording pointer.
- [ ] `.claude/agents/tech-lead.md`, `.cursor/agents/tech-lead.md`, and
  `.codex/skills/workflow-plan-writer/SKILL.md` — discover assets before runbook
  authoring.
- [ ] `.claude/agents/product-manager.md`, `.cursor/agents/product-manager.md`,
  `.codex/skills/workflow-spec-writer/SKILL.md` — discovery / `assets/` migration
  pointer when creating the development folder.
- [ ] `.claude/agents/developer.md`, `.cursor/agents/developer.md`,
  `.codex/skills/workflow-implementer/SKILL.md` — discovery pointer for
  UI-facing implementation (use assets as reference; do not invent).
- [ ] Do **not** change `.claude/agents/design-reviewer.md` /
  `.cursor/agents/design-reviewer.md` to become the primary fidelity gate (AC9).

---

## Testing Strategy

**Test types**: Shell harness (if helper changes), documentation smoke, Markdown
lint.

**Key scenarios to test**:

1. Likely design files supplied at backlog creation are recognized and
   attached/staged; body records locations (AC1, AC3).
2. Ambiguous file triggers one clarifying question; still exactly one item (AC2).
3. Agent following discovery rules finds tracker attachments and/or
   `<dev-folder>/assets/` (AC4).
4. No assets → no invented baseline / no spurious fidelity failure (AC5).
5. Assets present → smoke runbook includes expected-vs-actual fidelity step
   (AC6); executing it records PASS/FAIL detail (AC7).
6. Docs cover capture, storage, discovery, and hooks without a visual-regression
   platform; #1283 and design-reviewer-primary remain out of scope (AC8, AC9).

**Smoke test runbook**:
`docs/testing/workflow/1282-graphical-design-assets-workflow.smoke-test.md`

**Regression suite**: None beyond the existing
`test-add-backlog-item.sh` harness if the helper gains attach flags.

---

## Seed Data

None for production. Smoke verification may use temporary fixture files (for
example a tiny `.png` and a `.log`) created under a disposable temp directory
during the runbook; delete them afterward. Do not commit binary fixtures unless
a tiny checked-in sample is clearly useful — prefer ephemeral fixtures.

---

## Documentation Updates

> Listed for the developer to execute during implementation (not in this plan PR).

- [ ] `docs/workflow/development-workflow/design-assets.md` — **create** canonical
  convention (new file).
- [ ] `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md`
  — capture / clarify / attach / body section.
- [ ] `docs/workflow/development-workflow/protocols/01-generate-spec-protocol.md`
  — optional `assets/` migration when the development folder is created.
- [ ] `docs/workflow/development-workflow/protocols/02-generate-implementation-plan-protocol.md`
  — discovery + fidelity steps in smoke runbooks.
- [ ] `docs/workflow/development-workflow/protocols/04-smoke-test-protocol.md` —
  fidelity execution and expected-vs-actual recording.
- [ ] `docs/workflow/development-workflow/templates/smoke-test-runbook-template.md`
  — optional fidelity-step placeholder when assets exist.
- [ ] `docs/workflow/development-workflow/README.md` — link the convention.
- [ ] `docs/testing/README.md` — short note that runbooks may include design
  fidelity steps when assets exist.
- [ ] `AGENTS.md` — only if the Key Documentation or Common Commands table needs
  a pointer to `design-assets.md`; otherwise leave unchanged.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| GitHub/Linear attachment APIs are awkward from CLI | Med | Med | Document provider recipes; allow body path notes + human attach fallback; keep item creation successful |
| Agents invent fidelity steps without assets | Low | Med | Explicit AC5 wording in protocol `02`/`04` and smoke assertions |
| Convention drifts across Claude/Cursor/Codex mirrors | Med | Med | Canonical `design-assets.md`; command files stay thin pointers; Verification Log lists all mirrors |
| Scope creeps into #1283 or design-reviewer primary gate | Low | High | Non-goals section + AC9 smoke assertion; do not edit design-reviewer primary role |
| Accidental edits to #1281 / #1284 | Low | Med | Implementation Order forbids those paths; PR self-check |

---

## Residual verification (implementation readiness)

Before implementation `ready-for-human-review`, confirm:

1. Live search still lists every add-backlog command mirror and every
   plan/smoke agent/skill that should mention discovery.
2. Smoke runbook assertions AC1–AC9 are still covered by concrete steps.
3. No implementation PR introduces visual-regression CI or `/merged-qa`.

Evidence source: occurrence/path lists from the Verification Log commands above
(re-run at implement time; do not trust this plan's frozen SHA alone).

---

## Implementation Order

1. **Create** `docs/workflow/development-workflow/design-assets.md` with
   recognition heuristics, `assets/` layout, discovery order, issue-body
   template, and lightweight fidelity rules (AC1, AC3, AC4, AC5, AC8).
2. **Extend** `00-add-backlog-item-protocol.md` to call that convention during
   backlog creation (AC1–AC3).
3. **Update** Claude/Cursor/Codex add-backlog command surfaces with short
   pointer bullets (AC8).
4. **Decide and implement** helper attach support or documented agent recipe;
   extend `test-add-backlog-item.sh` only if flags/behavior change.
5. **Extend** protocols `01` (optional migration), `02` (runbook fidelity when
   assets exist), and `04` (execute + record expected-vs-actual); update the
   smoke runbook template with an optional fidelity-step placeholder (AC5–AC7).
6. **Update** smoke-tester, tech-lead, product-manager, developer agent mirrors
   and matching Codex skills with brief discovery/fidelity pointers; do not
   promote design-reviewer to primary fidelity gate (AC4, AC9).
7. **Cross-link** workflow README / testing README (and `AGENTS.md` only if
   needed).
8. **Verify** with Markdown lint on touched docs, focused helper tests if any,
   and the smoke runbook for this feature.
9. **Update** `CHANGELOG.md` under `[Unreleased]` with:

   - **Graphical design assets in the workflow** (#1282): add capture, storage,
     discovery, and lightweight plan/smoke fidelity hooks for design references
     without a visual-regression platform.

---

## Document Quality Gate (plan-author log)

- Spec/brief coverage: Checked — AC1–AC9 map to Decisions, Layer-by-Layer steps,
  Testing Strategy, and smoke runbook assertions.
- Implementation-order consistency: Checked — storage path is always
  `<dev-folder>/assets/`; body section is always `## Design assets`; mirrors
  match Verification Log surfaces.
- Verification support: Checked — Verification Log records SHA `160bb5e` and
  live path queries for add-backlog / plan / smoke surfaces.
- Complex workflow decision-gate matrix: Not applicable — this plan does not
  add or modify orchestration decision-gate inputs/outcomes.
- Parser/API/concurrency checklist: Not applicable — classifiers above do not
  apply.
- CHANGELOG literal format: Checked — Implementation Order step 9 uses
  `**Bold Title** (#1282):` form.
- Not-applicable rationale: Checked — see Classifier results and gate bullets
  above.

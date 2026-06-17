# Align Cursor Workflow Surfaces for Client Rollout — Implementation Plan

**Spec**: [`1_align-cursor-workflow-surfaces_specs.md`](./1_align-cursor-workflow-surfaces_specs.md)
**Smoke test runbook**: [`../../../testing/workflow/989-align-cursor-workflow-surfaces.smoke-test.md`](../../../testing/workflow/989-align-cursor-workflow-surfaces.smoke-test.md)

---

## Summary

**Approach**: Close the Cursor workflow-surface parity gaps the spec audit identified
by adding the two missing thin Cursor slash-command wrappers (`smoke-tester` and
`graduate-development`), correcting the cross-tool guidance tables and prose in
`AGENTS.md`, `CLAUDE.md` (symlink target is `AGENTS.md`), `README.md`, and
`docs/testing/README.md` so advertised Cursor entrypoints and shipped surfaces
agree one-to-one, and recording the explicit decision that no Cursor-native skills
mirror is shipped (with rationale) in the project guidance. Every new or changed
Cursor file is a thin wrapper that points at its canonical protocol and adds no
restated behavior beyond a short orientation summary.

**Estimated complexity**: S

<!-- S: < 1 day | M: 1-3 days | L: 3+ days -->

**Rationale**: This is documentation and thin-wrapper work only. No code, no scripts,
no protocol behavior changes. The two new Cursor command files follow an existing,
established wrapper pattern (`.cursor/commands/retrospective.md`,
`.cursor/commands/run-reviewer-loop.md`). The remaining changes are guidance-table
and prose edits. The blast radius is confined to Cursor surfaces and the guidance
that describes them.

**Dependencies**: None. The spec is merged into `develop-cursor-bugbot-integration`;
this item is the first substantive child of epic #988 and depends on no other
in-flight work. All PRs for this item target `develop-cursor-bugbot-integration`,
not `develop`.

---

## Verification Log

> Reproducible plan-time verification commands that influenced scope, counts, and
> file lists. Run on the plan branch `implementation-plan/989-align-cursor-workflow-surfaces`,
> branched from `origin/develop-cursor-bugbot-integration`.

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `9a7de1e` |
| Cursor command surface | `ls .cursor/commands/` | 18 command files; **no** `smoke-tester.md`, **no** `graduate-development.md` |
| Cursor agent surface | `ls .cursor/agents/` | 13 agent files incl. `smoke-tester.md`; **no** `graduate-development.md` |
| Cursor rules surface | `ls .cursor/rules/` | `code.mdc`, `documentation.mdc`, `workflow.mdc` (3 files) |
| Cursor skills mirror | `ls .cursor/skills/ 2>/dev/null` | absent (no Cursor-native skills directory) |
| Shared skills tree | `git ls-tree -r --name-only HEAD .agents/skills/` | present; includes `graduate-development/SKILL.md` |
| Command/agent mapping | per-name `[ -f .cursor/commands/$n.md ]` / `[ -f .cursor/agents/$n.md ]` loop | `smoke-tester`: agent only (no command); `graduate-development`: neither; `retrospective`: both (the parity model) |
| Advertised-but-missing smoke command | `grep -n "smoke-tester" AGENTS.md` | AGENTS.md "Smoke Test" row advertises Cursor `/smoke-tester` but no command file ships |
| Advertised graduation gap | `grep -n "Graduate Integration Branch" AGENTS.md` | AGENTS.md row shows Cursor `—` while Claude has `/graduate-development` and Codex has the alias |
| Stale smoke command name | `grep -rn "run-smoke-test" docs/testing/README.md` | `docs/testing/README.md:7` references a non-existent "Cursor run-smoke-test command" |
| Existing thin-wrapper pattern | read `.cursor/commands/retrospective.md`, `.cursor/commands/run-reviewer-loop.md` | both reference canonical protocol/agent, no restated behavior — pattern to follow |

---

## Layer-by-Layer Changes

> Only the layers that apply to this documentation/wrapper feature are listed.
> Database, Backend/API, Shared Packages, and Frontend/UI layers do not apply.

### Cursor surfaces (`.cursor/`)

- [ ] **Add `.cursor/commands/smoke-tester.md`** — new thin Cursor slash command for
  the Smoke Test stage. References the canonical protocol
  `docs/workflow/development-workflow/protocols/04-smoke-test-protocol.md` and the
  existing `smoke-tester` Cursor subagent; no restated protocol behavior beyond a
  short orientation summary. (AC-1, AC-2, AC-3 / B2, B5, B6)
- [ ] **Add `.cursor/commands/graduate-development.md`** — new thin Cursor slash command
  for the Integration-Branch Graduation stage. Accepts `<slug>`, references the
  canonical protocol
  `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`,
  and surfaces the protocol's human-approval gates without restating them. (AC-1,
  AC-2, AC-3 / B2, B6)
- [ ] **No `.cursor/skills/` directory is created** — the recorded decision is to not
  ship a Cursor-native skills mirror. This is a deliberate non-change recorded in
  guidance (see Documentation Updates). (AC-5 / B3)

### Infrastructure / Configuration

- [ ] No `.ai-dev-workflow.yaml`, script, or CI changes. This item is explicitly
  scoped to Cursor wrappers and guidance and must not change canonical protocols,
  models, or tool restrictions (spec Out of Scope).

### Documentation / Guidance (cross-tool tables and Cursor prose)

These guidance edits keep the tables and the shipped surfaces in one-to-one
agreement and record the skills-mirror decision. They are listed in detail under
**Documentation Updates** below and are an integral part of the deliverable (not
just incidental doc edits), because the spec's acceptance criteria (AC-2, AC-4,
AC-5) are satisfied by these files.

---

## Testing Strategy

**Test types**: Manual / Smoke (documentation and thin-wrapper verification). No unit
or integration tests apply — there is no executable code in this change.

**Key scenarios to test**:

1. Every advertised Cursor entrypoint resolves to a real Cursor surface by its
   advertised name (maps to AC-1).
2. The previously advertised-but-missing smoke-test entrypoint and the
   integration-branch graduation entrypoint now exist as real Cursor command files,
   and the guidance tables and shipped surfaces agree in both directions (maps to
   AC-2).
3. Each new or changed Cursor file references an existing canonical protocol path and
   contains no restated protocol behavior beyond a short orientation summary (maps to
   AC-3).
4. README and AGENTS-format Cursor guidance for rules, subagents, commands, and
   skills match the actual shipped surfaces, including the corrected smoke-test
   command name in the testing README (maps to AC-4).
5. The skills-mirror decision and rationale are findable in the spec and the project
   guidance without inferring from a directory's presence/absence (maps to AC-5).
6. Issue #989 Project Type is Feature (maps to AC-6 — verified in the tracker, not in
   files).

**Smoke test runbook**:
`docs/testing/workflow/989-align-cursor-workflow-surfaces.smoke-test.md`

**Regression suite**: Not applicable. This repository has no automated regression
suite that exercises Markdown guidance or Cursor wrapper files; verification is by
the smoke runbook plus the standard Markdown lint gate.

<!-- Parser-risk addendum: not applicable. No lint/parser/scanner/tokenizer modules,
no regex-heavy structured-text scanning, and no files under scripts/lint or scripts/parse
are introduced or changed. -->

<!-- Concurrent-event-source addendum: not applicable. No event listeners, socket
callbacks, timers, async queues, or shared mutable state are introduced or changed. -->

<!-- Cross-cutting checklist: not applicable. This change does not add or modify a
safety/quality/compliance checklist category that applies across multiple feature
implementations; it aligns Cursor wrappers and the cross-tool guidance tables to the
existing protocols. No new conditional guidance block or universal acceptance
criterion is introduced. -->

---

## Seed Data

> Not applicable. This feature introduces no data model and requires no seed data.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| None | No seed data required (documentation/wrapper change only) | — |

---

## Documentation Updates

> These are listed for the developer to execute during implementation. For this
> item the guidance edits are load-bearing for the acceptance criteria (AC-2, AC-4,
> AC-5), so they are not optional polish.

- [ ] `AGENTS.md` — Update the **Workflow Commands** table inside the
  `<!-- TEMPLATE-OWNED-START -->` block:
  - **Graduate Integration Branch** row: replace the Cursor cell `—` with
    `/graduate-development <slug>` to reflect the new command.
  - Confirm the **Smoke Test** row's Cursor cell remains `/smoke-tester` (now backed
    by the new command file); no text change needed there, but verify it after adding
    the command.
  - In the Cursor-facing guidance prose (the "Note for Cursor users" and any
    surrounding Cursor description), add a one-line explicit statement of the
    skills-mirror decision: the framework intentionally does not ship a
    `.cursor/skills/` mirror because Cursor discovers the existing agent, command, and
    shared `.agents/skills/` surfaces, and review tooling treats an absent Cursor
    skills tree as intentional rather than a missing mirror. (AC-2, AC-4, AC-5)
  - Note: `CLAUDE.md` is a symlink to `AGENTS.md`, so editing `AGENTS.md` updates both;
    do not edit `CLAUDE.md` separately.
- [ ] `README.md` — In the **Cursor** usage section (the list beginning
  "Rules in `.cursor/rules/` provide automatic context"):
  - Ensure the description of Cursor rules, subagents, and commands matches the
    shipped surfaces (rules in `.cursor/rules/` as `*.mdc`, subagents in
    `.cursor/agents/` invoked as `/agent-name`, commands in `.cursor/commands/`
    invoked as `/command-name`).
  - Add an explicit one-line note that no Cursor-native skills mirror is shipped and
    why (same rationale as AGENTS.md). (AC-4, AC-5)
- [ ] `docs/testing/README.md` — Line 7 (`**Audience**:`) currently references a
  non-existent "Cursor run-smoke-test command". Correct it to the actual advertised
  Cursor entrypoint name `/smoke-tester` (matching the AGENTS.md table and the new
  command file). (AC-2, AC-4)
- [ ] `docs/project/` — None. No business-domain, architecture, database, or
  repo-architecture content changes (this item does not alter protocols, models, or
  structure).
- [ ] `docs/best-practices/` — None. No coding/version-control/testing standard
  changes.

No other project docs require updates for this item.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A new Cursor command duplicates protocol behavior instead of pointing at it (violates thin-wrapper rule / AC-3) | Low | Med | Model both new files on `.cursor/commands/retrospective.md` and `.cursor/commands/run-reviewer-loop.md`; keep them to a description front-matter line plus a canonical-path reference and a short orientation summary. Reviewer confirms no restated behavior. |
| Broken relative link to a canonical protocol path in a new wrapper or in the plan/runbook | Low | Med | Run `markdownlint-cli2` on the new/changed files before commit; verify each referenced `docs/workflow/.../*.md` path resolves with `ls`. |
| Guidance table edited in only one direction (advertised-but-missing or shipped-but-undocumented persists) | Low | Med | Re-run the command/agent mapping loop after edits and confirm the AGENTS.md table rows for Smoke Test and Graduate Integration Branch both resolve to real Cursor surfaces. |
| Editing `CLAUDE.md` separately from `AGENTS.md` and causing drift | Low | Low | `CLAUDE.md` is a symlink to `AGENTS.md`; edit only `AGENTS.md`. Verify with `ls -l CLAUDE.md`. |
| Scope creep into Claude/Codex surfaces or protocol behavior | Low | Med | Touch Claude/Codex surfaces only where a guidance table cell must stay internally consistent (none required beyond the Cursor cells here); do not modify canonical protocols, models, or tool restrictions (spec Out of Scope). |

---

## Code Samples

> The two new files are short thin wrappers. The snippet below is **illustrative —
> adapt during implementation** to match the exact front-matter style of the
> existing Cursor command wrappers.

`.cursor/commands/graduate-development.md` (illustrative skeleton):

```markdown
---
description: Graduate a completed integration branch (develop-<slug>) to develop. Usage: /graduate-development <slug>
---

# Cursor Command: Graduate Development

Follow the graduation protocol exactly as defined in:

`docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`

- Accept `<slug>` as the integration branch identifier.
- Honor every human-approval gate the protocol requires; do not merge without them.
```

`.cursor/commands/smoke-tester.md` (illustrative skeleton):

```markdown
---
description: Run the smoke test stage for an approved implementation. Usage: /smoke-tester
---

# Cursor Command: Smoke Tester

Invoke the `smoke-tester` agent, or follow the smoke test protocol directly:

`docs/workflow/development-workflow/protocols/04-smoke-test-protocol.md`

Read the smoke test runbook and `docs/testing/README.md` before beginning.
```

> **Consistency rule applied**: the canonical protocol paths
> (`04-smoke-test-protocol.md`, `05b-graduate-development-protocol.md`), the command
> names (`smoke-tester`, `graduate-development`), and the directory
> (`.cursor/commands/`) are referenced identically across the Summary, Layer-by-Layer,
> Documentation Updates, Implementation Order, and these samples.

---

## Implementation Order

> Ordered steps. Later steps may depend on earlier ones. No CHANGELOG step is
> included: `implementation-plan/*` and this item's `feature/*` documentation work
> land on the integration branch, but per protocol the implementation PR for a
> guidance/wrapper change still adds a CHANGELOG entry — see step 7.

1. Create `.cursor/commands/smoke-tester.md` as a thin wrapper that references
   `docs/workflow/development-workflow/protocols/04-smoke-test-protocol.md` and the
   `smoke-tester` Cursor subagent, modeled on `.cursor/commands/retrospective.md`.
   Verify: open the file and confirm it contains a canonical-path reference and no
   restated protocol steps.
2. Create `.cursor/commands/graduate-development.md` as a thin wrapper that accepts
   `<slug>`, references
   `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`,
   and notes the human-approval gates, modeled on
   `.claude/commands/graduate-development.md` (content) and
   `.cursor/commands/run-reviewer-loop.md` (thinness/style). Verify: open the file and
   confirm the referenced protocol path resolves with `ls`.
3. Update the `AGENTS.md` **Workflow Commands** table: set the **Graduate Integration
   Branch** row Cursor cell to `/graduate-development <slug>`. Confirm the **Smoke
   Test** row Cursor cell `/smoke-tester` is now backed by the new command. Verify: run
   the per-name command/agent mapping loop and confirm both rows resolve to a real
   Cursor surface.
4. Update the Cursor-facing prose in `AGENTS.md` and the **Cursor** section of
   `README.md` to (a) match the shipped rules/subagents/commands conventions and (b)
   state the explicit decision that no Cursor-native skills mirror is shipped, with the
   rationale. Verify: read both sections and confirm the decision is stated in prose,
   not implied.
5. Fix `docs/testing/README.md` line 7 to reference `/smoke-tester` instead of the
   non-existent "run-smoke-test command". Verify: `grep -n "smoke" docs/testing/README.md`
   shows the corrected name and no remaining "run-smoke-test".
6. Run the Markdown lint gate on all new/changed Markdown files (the two new command
   files, `AGENTS.md`, `README.md`, `docs/testing/README.md`, the plan, and the
   runbook) and fix any violations. Verify: lint exits clean.
7. Update `CHANGELOG.md` under `[Unreleased]` using the project's
   `**Bold Title** (#N):` format. Add exactly:
   `- **Align Cursor workflow surfaces for client rollout** (#989): add Cursor`
   `smoke-tester and graduate-development slash commands, align the cross-tool`
   `guidance tables, correct the testing README smoke command name, and record the`
   `decision not to ship a Cursor-native skills mirror.`
   (Place under the appropriate `### Added`/`### Changed` subsections — the new
   commands are `### Added`; the guidance corrections and recorded decision are
   `### Changed`.)
8. Execute the smoke test runbook
   `docs/testing/workflow/989-align-cursor-workflow-surfaces.smoke-test.md` and confirm
   every acceptance criterion passes.

> **CHANGELOG note for the implementation stage**: This *plan* PR
> (`implementation-plan/*`) does **not** add a CHANGELOG entry. The CHANGELOG literal
> in step 7 is for the later **implementation** PR (the `feature/*` branch that ships
> the wrappers and guidance edits), which targets `develop-cursor-bugbot-integration`.

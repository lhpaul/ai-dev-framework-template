# Post-Merge QA (`/post-merge-qa`) — Implementation Plan

**Spec**: [`1_1283-post-merge-qa_specs.md`](./1_1283-post-merge-qa_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/1283-post-merge-qa.smoke-test.md`](../../../testing/workflow/1283-post-merge-qa.smoke-test.md)

---

## Summary

**Approach**: Add a new workflow protocol (`08-post-merge-qa-protocol.md`) as the
single source of truth for `/post-merge-qa` (alias `/merged-qa-tester`), plus a
small read-only scope-proposal helper, thin Cursor/Claude/Codex command + agent
surfaces mirroring `smoke-tester` / `post-merge-cleanup`, and documentation
index updates. Runtime behavior is agent-executed against browser automation
(and/or docs-only validation when the human confirms a non-UI path). When
safely actionable defects are found, the same run opens one `fix/*` PR targeting
the QA branch — no new backlog item.

**Estimated complexity**: M

**Rationale**: New protocol + helper + multi-surface mirrors + tests, but no
new CI platform, visual-regression harness, or orchestration control-loop
changes. Reuses existing design-assets discovery and browser_automation config.

**Dependencies**: Spec merged (#1283 Spec Ready). #1282 is Orthogonal —
consume `design-assets.md` when assets happen to exist; do not require or edit
#1282 artifacts beyond linking.

**Template-fit**: Pass — workflow tooling for the template itself; stack-agnostic.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `20c99f8` |
| Spec present | `test -f docs/specs/developments/20260721204647_1283-post-merge-qa/1_1283-post-merge-qa_specs.md` | Present |
| Design assets convention | `test -f docs/workflow/development-workflow/design-assets.md` | Present (from #1282) |
| Smoke command surfaces | `ls .cursor/commands/smoke-tester.md .cursor/agents/smoke-tester.md .claude/agents/smoke-tester.md` | Present; no Claude slash command for smoke today |
| Post-merge cleanup mirrors | `find .cursor/commands .claude/commands .agents/skills .codex/skills -name '*post-merge-cleanup*'` | Cursor/Claude commands + agents skills + codex skill |
| Free protocol slot | `ls docs/workflow/development-workflow/protocols/0*.md` | `00`–`07` + `05b`/`06b`; use **`08-post-merge-qa-protocol.md`** |
| Existing merged-qa strings | `rg -n "post-merge-qa\|merged-qa" docs scripts .cursor .claude .agents` | Spec/plan only; design-assets.md mentions #1283 as out of scope for that item |

---

## Technical Decisions

### Decision 1 — Protocol as source of truth

Create
`docs/workflow/development-workflow/protocols/08-post-merge-qa-protocol.md`
covering:

1. Target resolution (`develop` / `develop-<slug>`; checkout default vs explicit)
2. Scope proposal + mandatory human confirmation (including empty-scope stop)
3. Environment preflight (ask/stop when missing)
4. Flow exercise + critical UX
5. Optional design-asset fidelity via `design-assets.md` (skip silently if none)
6. Findings handling: clean pass vs one fix PR vs deferred product decisions
7. Operator-facing report shape (chat + fix PR description when applicable)

Command surfaces and agents load this protocol; they do not fork behavior.

### Decision 2 — Scope helper (read-only)

Add `scripts/development-workflow/post-merge-qa-scope.sh` that:

- Accepts `--base <develop|develop-slug>`, optional `--epic <n>`, optional
  `--issues <csv>`, optional `--recent-merged-prs <n>`
- Proposes a JSON/list of candidate items/PRs for human confirmation
- Prefers merged-onto-base items; for epics, items associated with that epic’s
  integration branch
- Performs **no** tracker mutation, branch creation, or PR opens

Agents present the helper output and wait for confirmation before testing.

### Decision 3 — Command / agent / skill mirrors

| Surface | Artifact |
| --- | --- |
| Cursor command | `.cursor/commands/post-merge-qa.md` + thin alias `.cursor/commands/merged-qa-tester.md` |
| Cursor agent | `.cursor/agents/post-merge-qa.md` (loads protocol 08) |
| Claude command | `.claude/commands/post-merge-qa.md` + alias `.claude/commands/merged-qa-tester.md` |
| Claude agent | `.claude/agents/post-merge-qa.md` |
| Codex / agents skills | `.agents/skills/post-merge-qa/SKILL.md` (+ optional `agents/openai.yaml`); thin alias skill or documented alias name `/merged-qa-tester` |
| Codex legacy path | Mirror under `.codex/skills/post-merge-qa/` if install script expects it (match `post-merge-cleanup` pattern) |

Primary name: `/post-merge-qa`. Alias: `/merged-qa-tester` (identical behavior).

### Decision 4 — Fix PR path

When safely actionable defects exist after confirmed QA:

1. Create branch `fix/post-merge-qa-<short-slug>` (or include issue numbers when
   a single scoped issue dominates) from the **QA target branch**
2. Commit fixes; open **one** PR with base = QA target
3. PR body includes findings summary, what was fixed, asset checks run/skipped,
   and any deferred product questions
4. Do **not** call `/add-backlog-item` or create a tracker item for those fixes
5. Do **not** auto-merge the fix PR

If only product-decision defects remain: ask human; no ceremony-only PR.

### Decision 5 — Environment preflight

Before exercising flows, resolve runnable surfaces from (in order):

1. Explicit human-provided URLs / how-to-run
2. Project `docs/testing/README.md` / Common Commands in `AGENTS.md`
3. `.ai-dev-workflow.yaml` `browser_automation` provider availability

If nothing runnable and no human-confirmed docs-only path: stop (Use Case 2).

### Decision 6 — Documentation indexes

Update workflow command tables and Codex skill lists in:

- `AGENTS.md` / `CLAUDE.md` (symlink) TEMPLATE-OWNED workflow tables
- `docs/workflow/development-workflow/README.md`
- `design-assets.md` cross-link: post-merge QA may consume assets; still not a
  visual-regression platform
- `scripts/development-workflow/install-codex-skills.sh` if it enumerates skills

### Decision 7 — CHANGELOG

Implementation PR adds an `[Unreleased]` entry under Added for `/post-merge-qa`.

### Decision 8 — Out of scope (encode as non-goals)

- Replacing protocol `04` / `/smoke-tester`
- Visual-regression platform / pixel diffs / CI screenshot suites
- Auto-merge of the fix PR
- Editing #1282 implementation beyond cross-links
- Orchestrator auto-dispatch of post-merge QA after every merge (manual/operator
  invocation only for MVP)

---

## Classifier results

| Classifier | Applies? | Rationale |
| --- | --- | --- |
| Parser-risk | No | Scope helper uses `gh`/`jq` structured APIs; no new markdown/AST parser |
| Concurrent-event-source | No | No long-lived listeners or shared mutable runtime services |
| Cross-cutting checklist | No | Does not add a mandatory REVIEW.md category; optional fidelity only when assets exist |

---

## Layer-by-Layer Changes

### Workflow tooling / scripts

- [ ] Add `docs/workflow/development-workflow/protocols/08-post-merge-qa-protocol.md`
- [ ] Add `scripts/development-workflow/post-merge-qa-scope.sh` (read-only proposal)
- [ ] Add `scripts/development-workflow/tests/test-post-merge-qa-scope.sh`
- [ ] Wire skill install / discovery if `install-codex-skills.sh` lists skills

### Command & agent surfaces

- [ ] Cursor: `post-merge-qa` command + agent; `merged-qa-tester` alias command
- [ ] Claude: `post-merge-qa` command + agent; `merged-qa-tester` alias command
- [ ] Codex/agents: `post-merge-qa` skill (+ legacy `.codex/skills` mirror as needed)
- [ ] Ensure alias surfaces state identical behavior and point at protocol 08

### Documentation

- [ ] Update `AGENTS.md` workflow command + Codex skills lists
- [ ] Update `docs/workflow/development-workflow/README.md` stages/commands tables
- [ ] Cross-link from `design-assets.md` to protocol 08 (consumer, not owner)
- [ ] `CHANGELOG.md` `[Unreleased]` Added entry on the implementation PR

### Testing

- [ ] Unit/shell tests for scope helper (empty scope, epic path mock, disallowed base)
- [ ] Smoke runbook validating command surfaces + dry protocol walkthrough

### Database / product app layers

- Not applicable (template workflow tooling only)

---

## Implementation Steps

1. **Protocol 08** — Write full operator/agent procedure matching the spec ACs
2. **Scope helper + tests** — Deterministic proposal output; no mutations
3. **Agent/command mirrors** — Cursor, Claude, Codex; primary + alias
4. **Docs indexes + design-assets cross-link + CHANGELOG**
5. **Smoke runbook execution during implementation** — update runbook if needed
6. **Manual dry-run** on this template repo (docs-only path) to prove preflight +
   empty/clean path without opening a spurious fix PR

---

## Spec Coverage Matrix

| Spec AC / rule | Plan coverage |
| --- | --- |
| `/post-merge-qa` ≡ `/merged-qa-tester` | Decision 3 — primary + alias surfaces |
| Target `develop` / `develop-<slug>` only | Decision 1 + helper `--base` validation |
| Default target from checkout when allowed | Protocol 08 target resolution |
| Propose merged / epic-branch scope; confirm | Decision 2 + protocol confirmation gate |
| Empty confirmed scope stops cleanly | Protocol 08 + helper tests |
| Environment preflight before flows | Decision 5 |
| Optional design-asset fidelity | Decision 1 step 5 + design-assets.md link |
| One fix PR on QA base; no backlog item | Decision 4 |
| Clean pass → no fix PR | Decision 4 |
| Product-decision defects asked, not invented | Decision 4 + protocol 08 |
| Smoke unchanged | Decision 8 |
| Cursor / Claude / Codex surfaces | Decision 3 |

---

## Document updates after implementation

| Doc | Why |
| --- | --- |
| `AGENTS.md` | Command table + Codex skill list |
| `docs/workflow/development-workflow/README.md` | Stages / commands |
| `docs/workflow/development-workflow/design-assets.md` | Consumer cross-link |
| `CHANGELOG.md` | Unreleased Added |

---

## Smoke Test Plan (summary)

See
[`docs/testing/workflow/1283-post-merge-qa.smoke-test.md`](../../../testing/workflow/1283-post-merge-qa.smoke-test.md).

Validate: both command names resolve; disallowed base stops; scope proposal +
confirm gate; preflight asks when environment missing; clean docs-only path
opens no fix PR; alias parity.

---

## Risks & Open Design Notes (non-blocking)

- Scope discovery heuristics for “merged onto base” may vary by tracker provider;
  helper should document GitHub Projects assumptions and fail closed with a clear
  ask when provider data is insufficient.
- Fix PR branch naming when many items are in scope: prefer a descriptive
  aggregate slug + list scoped issues in the PR body.

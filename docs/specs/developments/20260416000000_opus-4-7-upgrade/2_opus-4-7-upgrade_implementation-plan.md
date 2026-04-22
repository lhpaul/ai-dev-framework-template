# Opus 4.7 Upgrade — Implementation Plan

**Spec**: N/A (Refactor — see GitHub issue #160)
**Smoke test runbook**: [`docs/testing/workflow/opus-4-7-upgrade.smoke-test.md`](../../../testing/workflow/opus-4-7-upgrade.smoke-test.md)

---

## Summary

**Approach**: Replace all `claude-opus-4-6` model ID references (and the stale `claude-opus-4-5-20251101` example) with `claude-opus-4-7` across agent configuration files and documentation. No logic changes — this is a purely mechanical find-and-replace across two files in the main repo: `.claude/agents/tech-lead.md` and `docs/workflow/development-workflow/agent-model-config.md`. Sonnet and Haiku references are intentionally left untouched.

**Estimated complexity**: S

**Rationale**: Two files, two to three line changes. No schema, no code, no test changes required.

**Dependencies**: None

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] `.claude/agents/tech-lead.md` — change `model: claude-opus-4-6` to `model: claude-opus-4-7` (front-matter field, line 3)
- [ ] `docs/workflow/development-workflow/agent-model-config.md` — update the in-session override example (currently `claude-opus-4-5-20251101`) to `claude-opus-4-7`
- [ ] `docs/workflow/development-workflow/agent-model-config.md` — update the permanent-change example (currently `claude-opus-4-6`) to `claude-opus-4-7`

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:
1. Confirm `grep -r "claude-opus-4-6" .claude/ .cursor/ .codex/ docs/workflow/` returns no matches — maps to success criterion 1
2. Confirm `grep -r "claude-opus-4-5" .claude/ .cursor/ .codex/ docs/workflow/` returns no matches — maps to success criterion 1
3. Confirm `.claude/agents/tech-lead.md` front-matter has `model: claude-opus-4-7` — maps to success criterion 1
4. Confirm `docs/workflow/development-workflow/agent-model-config.md` examples reference `claude-opus-4-7` — maps to success criterion 2
5. Confirm CHANGELOG has an entry under `[Unreleased]` — maps to success criterion 3

**Smoke test runbook**: [`docs/testing/workflow/opus-4-7-upgrade.smoke-test.md`](../../../testing/workflow/opus-4-7-upgrade.smoke-test.md)

**Regression suite**: No automated regression suite exists for agent config files.

---

## Seed Data

None — this change involves only documentation and configuration files, with no runtime data requirements.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/agent-model-config.md` — update the two Opus example model IDs (this is also a documentation file and is the primary change for this item)
- [ ] `CHANGELOG.md` — add a `Changed` entry under `[Unreleased]` for the Opus 4.6 → 4.7 model reference upgrade

No other project docs in `docs/project/`, `AGENTS.md`, or `docs/best-practices/` require updates. The tier names and rationale are unchanged.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Accidentally bumping Sonnet or Haiku references | Low | Low | Targeted search before and after for `claude-opus` only; verify Sonnet/Haiku lines are unchanged |
| Stale worktrees contain old references | Low | None | Worktrees are transient; only the tracked repo files matter |

---

## Implementation Order

1. In the worktree's `.claude/agents/tech-lead.md`, change `model: claude-opus-4-6` to `model: claude-opus-4-7`
2. In the worktree's `docs/workflow/development-workflow/agent-model-config.md`, update the in-session override example from `claude-opus-4-5-20251101` to `claude-opus-4-7`
3. In the worktree's `docs/workflow/development-workflow/agent-model-config.md`, update the permanent-change example from `claude-opus-4-6` to `claude-opus-4-7`
4. Run `grep -r "claude-opus-4-6\|claude-opus-4-5" .claude/ .cursor/ .codex/ docs/workflow/` to confirm zero remaining matches in tracked files (excluding worktree paths)
5. Add CHANGELOG entry under `[Unreleased]`
6. Commit: `refactor(agent-config): upgrade Opus model references from 4.6 to 4.7`

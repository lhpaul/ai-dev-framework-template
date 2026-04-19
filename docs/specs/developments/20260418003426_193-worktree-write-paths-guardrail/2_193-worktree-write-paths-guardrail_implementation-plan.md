# fix(item-orchestrator): Write/Edit path guardrail for isolated worktrees — Implementation Plan

**Spec**: [`1_193-worktree-write-paths-guardrail_specs.md`](./1_193-worktree-write-paths-guardrail_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/193-worktree-write-paths-guardrail.smoke-test.md`](../../../testing/workflow/193-worktree-write-paths-guardrail.smoke-test.md)

---

## Summary

**Approach**: Add an explicit `Write`/`Edit` path guardrail reminder to the worktree isolation section of Protocol 91 Step 3, instructing agents that all `Write` and `Edit` tool calls must target paths under the resolved `<worktree-path>` value — not the main repo root. Mirror identical reminder language into both `.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md` (dual-agent sync). Optionally document the pre-tool-use hook design for `WORKTREE_ROOT`-based path validation. No scripts are modified.

**Estimated complexity**: S

**Rationale**: All changes are documentation-only (one protocol file + two agent prompt files). No code, scripts, or infrastructure changes are required. The guardrail is a targeted prose addition to an existing section.

**Dependencies**: None — no other in-progress issues block this work. Note: issue #192 touches the same worktree-discipline section of Protocol 91 for the `git switch`/`git checkout` rule; at the plan stage there is no overlap. At implementation the two changes must be applied to separate lines or paragraphs; a merge conflict is expected and resolved by the developer.

---

## Layer-by-Layer Changes

### Protocol Documentation

- [ ] **`docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md`** — In the Step 3 worktree isolation block (after the existing `git switch`/`git reset` safety rule), add an explicit `Write`/`Edit` path guardrail subsection (see Implementation Order Step 1 for the exact prose placement and required content).

### Agent Prompt Files

- [ ] **`.claude/agents/item-orchestrator.md`** — Append a short worktree path reminder instruction after the existing key responsibilities list: when `BATCH_CONTEXT=true`, all `Write` and `Edit` calls must target paths under the resolved worktree path, and any main-repo-absolute path is a red flag to correct before calling the tool (see Implementation Order Step 2).
- [ ] **`.cursor/agents/item-orchestrator.md`** — Apply the identical change as `.claude/agents/item-orchestrator.md` in the same relative position (dual-agent consistency). The two files must remain in sync (see Implementation Order Step 3).

---

## Testing Strategy

**Test types**: Smoke (manual, doc-review walkthrough)

**Key scenarios to test**:

1. Protocol 91 Step 3 worktree section contains the Write/Edit path guardrail reminder with the `<worktree-path>` runtime-value requirement — maps to AC1
2. The reminder specifies that `<worktree-path>` must be resolved to its runtime value before injection into handoffs — maps to AC2
3. The reminder specifies it must appear in every stage-agent handoff (not just the first) — maps to AC3
4. The protocol language makes clear the guardrail applies only when `BATCH_CONTEXT=true` — maps to AC4
5. (Optional) A pre-tool-use hook design is described — maps to AC5
6. (Optional) The hook spec states `WORKTREE_ROOT` unset is a no-op — maps to AC6
7. Non-batch behavior is unchanged; no spurious changes to Protocol 90, `post-merge-cleanup.sh`, `pr-review-loop.sh`, or issue #192's scope — maps to AC7
8. `.claude/agents/item-orchestrator.md` and `.cursor/agents/item-orchestrator.md` have identical reminder language — confirms dual-agent sync

**Smoke test runbook**: [`docs/testing/workflow/193-worktree-write-paths-guardrail.smoke-test.md`](../../../testing/workflow/193-worktree-write-paths-guardrail.smoke-test.md)

**Regression suite**: No automated regression suite exists in this repository.

---

## Seed Data

No seed data required. All changes are documentation-only.

| Entity | Values / Scenario | File |
|---|---|---|
| N/A | — | — |

---

## Documentation Updates

- [ ] `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md` — Primary change target (Step 3 worktree isolation section). Already listed under Layer-by-Layer Changes.
- [ ] `.claude/agents/item-orchestrator.md` — Primary change target (agent prompt). Already listed under Layer-by-Layer Changes.
- [ ] `.cursor/agents/item-orchestrator.md` — Primary change target (agent prompt, dual-sync). Already listed under Layer-by-Layer Changes.

No additional `docs/project/` files or `AGENTS.md` need updating; this change does not alter the public-facing project overview, architecture docs, or best-practice guides.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Merge conflict with #192 in Protocol 91 Step 3 | Med | Low | Resolve at impl time: #192 adds `git switch` prose, this PR adds `Write`/`Edit` prose — apply to adjacent lines or paragraphs with clear labels |
| `.claude` and `.cursor` agent files diverge | Low | Med | Implementation Order enforces applying both files in the same commit before pushing |
| Guardrail reminder is too generic and agents ignore it | Low | Med | Include the literal resolved `<worktree-path>` value instruction (not a static placeholder) so agents can compare at runtime |

---

## Code Samples

> All samples below are **illustrative — adapt during implementation**.

### Protocol 91 Step 3 — Write/Edit Path Guardrail addition

The following prose block should be inserted in the Step 3 worktree isolation section, immediately after the existing critical safety rule for `git switch`/`git checkout`/`git reset`:

```markdown
**Critical safety rule — Write and Edit paths inside a worktree**: Every `Write` and
`Edit` tool call issued within an active worktree session **must** target a path under
`<worktree-path>/...`. Any path that does NOT begin with the resolved `<worktree-path>`
value is a main-repo path — treat it as a red flag and correct it before calling the tool.

- Before calling `Write` or `Edit`, mentally verify: "Does this absolute path start with
  `<worktree-path>/`?" If not, prepend `<worktree-path>/` to the relative portion of the
  path.
- The item-orchestrator must include the resolved literal value of `<worktree-path>` in
  every stage-agent handoff (not just the first), so each agent can validate paths against
  it independently.
- Paths under `<worktree-path>/.tmp/` are within the worktree boundary and are permitted.
- This rule applies only when `BATCH_CONTEXT=true` and a dedicated worktree exists; for
  non-batch runs, no reminder is injected.
```

### Optional pre-tool-use hook design (Use Case 2)

Add a short reference block to the same Step 3 section, after the Write/Edit path guardrail, to document the optional hook:

```markdown
**Optional: pre-tool-use hook for WORKTREE_ROOT validation**

A pre-tool-use hook can enforce the Write/Edit path rule automatically:

1. Set the `WORKTREE_ROOT` environment variable to the resolved worktree path when
   launching the agent session.
2. In the hook, intercept `Write` and `Edit` tool calls only.
3. If `WORKTREE_ROOT` is unset, skip the check (non-worktree session — no-op).
4. If the target path does not start with `$WORKTREE_ROOT`, emit:
   `"GUARDRAIL: Write/Edit target '<path>' is outside the designated worktree
   '<WORKTREE_ROOT>'. Correct the path before proceeding."`
5. The hook must NOT intercept read-only tools (`Read`, `Glob`, `Grep`).
```

### `.claude/agents/item-orchestrator.md` reminder addition

Append after the existing key responsibilities list (after the last bullet point, before the end of the file):

```markdown
- **Worktree Write/Edit path discipline (BATCH_CONTEXT=true only)**: When running inside
  an isolated worktree, all `Write` and `Edit` tool calls must target paths under the
  resolved `<worktree-path>/...`. Any absolute path that does NOT begin with
  `<worktree-path>/` is a main-repo path — correct it before calling the tool. Include
  the literal resolved `<worktree-path>` value in every stage-agent handoff so each
  dispatched agent can validate its own paths independently.
```

---

## Implementation Order

1. **Update Protocol 91 Step 3** — In `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md`, locate the "Critical safety rule — never modify the main working tree's branch" bullet block inside the Step 3 worktree isolation section. Immediately after that block (before the "4. Suggested worktree path" item), insert the "Write and Edit paths inside a worktree" critical safety rule prose and the optional pre-tool-use hook design block (see Code Samples above).

2. **Update `.claude/agents/item-orchestrator.md`** — Append the worktree Write/Edit path discipline bullet to the existing key responsibilities list (after the last existing bullet, before the end of the file). See Code Samples above for the exact bullet text. Keep the `---` frontmatter and `tools:` line unchanged.

3. **Update `.cursor/agents/item-orchestrator.md`** — Apply the identical worktree Write/Edit path discipline bullet in the same relative position as step 2. The two agent files must be updated in the same commit to ensure they stay in sync.

4. **Commit** — Single commit with all three files: `fix(item-orchestrator): add Write/Edit path guardrail for isolated worktrees`

5. **Update CHANGELOG** — Add an entry under `[Unreleased]`:
   - Under `Fixed`: `fix(item-orchestrator): item-orchestrator agents running in isolated git worktrees now receive an explicit reminder that all Write/Edit tool calls must target paths under the resolved worktree path, not the main repo root; same guardrail added to both Claude Code and Cursor agent prompts (#193)`

6. **Push and open draft PR** targeting `develop`

7. **Verify smoke test runbook** — Confirm all AC checkboxes map to testable steps in `docs/testing/workflow/193-worktree-write-paths-guardrail.smoke-test.md`

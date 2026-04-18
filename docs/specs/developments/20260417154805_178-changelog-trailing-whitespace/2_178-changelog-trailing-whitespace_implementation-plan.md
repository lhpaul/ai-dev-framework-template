# Developer Agent CHANGELOG Trailing-Whitespace Prevention — Implementation Plan

**Spec**: [`docs/specs/developments/20260417154805_178-changelog-trailing-whitespace/1_178-changelog-trailing-whitespace_specs.md`](1_178-changelog-trailing-whitespace_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/178-changelog-trailing-whitespace.smoke-test.md`](../../../testing/workflow/178-changelog-trailing-whitespace.smoke-test.md)

---

## Summary

**Approach**: Add an explicit, actionable CHANGELOG format verification instruction to every implementation path in `03-implement-development-protocol.md` (Full Pipeline Step 6, and equivalent CHANGELOG update steps in the Refactor, Fast Track, and Hotfix paths). Concurrently, add a matching rule to the developer agent's key rules section in `.claude/agents/developer.md` so the check is surfaced at agent initialization. Both changes are pure documentation and protocol text edits — no scripts, hooks, or CI changes are needed.

**Estimated complexity**: S

**Rationale**: Only two files need targeted text additions. No code, schema, or CI configuration changes are required. The change is well-bounded and each insertion point is clearly identified by the spec.

**Dependencies**: 173-markdown-lint-plan-spec-docs (merged — provides the durable CI enforcement gate that coexists with the agent-level check introduced here)

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] `docs/ai/development-workflow/protocols/03-implement-development-protocol.md` — Insert a CHANGELOG format verification sub-step into the CHANGELOG update step for every implementation path:
  - **Full Pipeline Path 1, Step 6** (`### Step 6: Update CHANGELOG`): add verification instruction after the entry-writing guidance.
  - **Refactor Path 2, Step 6** (the `Update CHANGELOG` bullet inside Refactor Steps): add the same verification instruction.
  - **Fast Track Path 3, Step 6** (`### Step 6: Update CHANGELOG`): add the same verification instruction.
  - **Hotfix Path 4, Step 6** (`### Step 6: Update CHANGELOG`): add the same verification instruction.
  - The instruction must cover both defect patterns (trailing whitespace on any line, two or more consecutive blank lines at the end of the entry), state that intentional two-space Markdown hard line breaks must not be treated as violations, and clarify that the check runs after writing the entry and before staging.

- [ ] `.claude/agents/developer.md` — Add a key rule that states the CHANGELOG entry must have no trailing whitespace or trailing blank lines before commit, alongside the existing CHANGELOG update reminder.

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:

1. Verify that `03-implement-development-protocol.md` contains the CHANGELOG verification instruction in all four implementation paths (Full Pipeline Step 6, Refactor Step 6, Fast Track Step 6, Hotfix Step 6) — maps to AC1, AC3, AC4.
2. Verify that `.claude/agents/developer.md` key rules section mentions no trailing whitespace or trailing blank lines — maps to AC2.
3. Verify the changes do not remove or conflict with any existing CHANGELOG update instructions — maps to AC5.

**Smoke test runbook**: [`docs/testing/workflow/178-changelog-trailing-whitespace.smoke-test.md`](../../../testing/workflow/178-changelog-trailing-whitespace.smoke-test.md)

---

## Seed Data

None — this feature is documentation/protocol-only. No runtime seed data is required.

---

## Documentation Updates

- [ ] `docs/ai/development-workflow/protocols/03-implement-development-protocol.md` — Updated as the primary deliverable (all four CHANGELOG update steps). No further documentation updates are needed beyond what is listed under Layer-by-Layer Changes.
- [ ] `.claude/agents/developer.md` — Updated as the secondary deliverable (key rules section).

No other project docs (`docs/project/`, `docs/best-practices/`, `AGENTS.md`, etc.) are affected by this change.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Instruction is too vague and an LLM agent skips it | Low | Med | Spec AC3 requires concrete, unambiguous language; use a shell-checkable example pattern in the instruction |
| Instruction inadvertently strips intentional two-space hard line breaks | Low | Low | Spec AC4 requires an explicit exclusion clause; include it verbatim in every insertion point |
| One of the four paths is missed | Low | Med | Pre-implementation scope checklist: grep for the CHANGELOG step heading in each path before opening PR |

---

## Implementation Order

1. Read the current text of `03-implement-development-protocol.md` in full, noting the exact location of Step 6 / the CHANGELOG update step in each of the four paths (Full Pipeline, Refactor, Fast Track, Hotfix).
2. Read the current text of `.claude/agents/developer.md` in full, noting the key rules section.
3. **Cross-reference consistency check**: grep for `CHANGELOG` and `trailing` across `docs/`, `.claude/`, `.cursor/`, `.codex/`, `AGENTS.md`, `REVIEW.md` to ensure no other location mentions a contradictory rule or would also need updating.
4. Edit `03-implement-development-protocol.md`:
   - In **Full Pipeline Path 1, Step 6**: append the verification sub-step immediately after the existing bullet list.
   - In **Refactor Path 2** Refactor Steps, the Update CHANGELOG bullet: append the same verification sub-step inline.
   - In **Fast Track Path 3, Step 6**: append the same verification sub-step.
   - In **Hotfix Path 4, Step 6**: append the same verification sub-step.

   The verification sub-step text (use consistently in all four paths):

   > **CHANGELOG format verification (before staging)**: After writing the CHANGELOG entry, verify the entry for the following defects and fix them in-place before staging:
   >
   > 1. **Trailing whitespace**: No line in the written entry should end with one or more whitespace characters. Note: intentional two-space Markdown hard line breaks (`<text>  ` with exactly two trailing spaces followed by a newline) are not trailing whitespace and must not be removed.
   > 2. **Trailing blank lines**: The entry must not end with two or more consecutive blank lines.
   >
   > A quick shell check for trailing whitespace on staged CHANGELOG lines:
   > ```bash
   > git diff --cached CHANGELOG.md | grep '^+' | grep -P '\s+$'
   > ```
   > If this returns output, fix the flagged lines before committing.

5. Edit `.claude/agents/developer.md`:
   - In the key rules section (the bullet list after `Key rules:`), add the following bullet:
     > - CHANGELOG entries must have no trailing whitespace and no trailing blank lines before commit; verify in-place after writing the entry and before staging (intentional two-space Markdown hard line breaks are exempt)

6. Run the markdown lint check on modified files to confirm no lint violations are introduced:
   ```bash
   npx markdownlint-cli2 "docs/specs/developments/20260417154805_178-changelog-trailing-whitespace/*.md" "docs/testing/workflow/178-changelog-trailing-whitespace.smoke-test.md"
   ```
7. Update CHANGELOG under `[Unreleased]` with a `Fixed` entry.
8. Commit with message: `fix(developer-agent): add CHANGELOG trailing-whitespace verification step`
9. Push branch and open a draft PR targeting `develop`.
10. Verify smoke test runbook assertions manually.

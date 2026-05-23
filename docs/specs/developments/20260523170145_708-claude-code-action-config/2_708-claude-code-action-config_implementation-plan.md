# Register Claude Code Action and Reslot phase_after_clean — Implementation Plan

**Spec**: [`docs/specs/developments/20260523170145_708-claude-code-action-config/1_708-claude-code-action-config_specs.md`](1_708-claude-code-action-config_specs.md)
**Smoke test runbook**: [`docs/testing/workflow/708-claude-code-action-config.smoke-test.md`](../../../../testing/workflow/708-claude-code-action-config.smoke-test.md)

---

## Summary

**Approach**: Update the inline YAML comments in `.ai-dev-workflow.yaml` to list `claude-code-action` as a supported platform and recommend it as the `phase_after_clean` value. Update `README.md` to mention `claude-code-action` in the Optional Integrations section. Add a CHANGELOG entry under `[Unreleased]`.

**Estimated complexity**: S

**Rationale**: All changes are comment/documentation edits in two files plus a CHANGELOG entry. No script logic, no binary changes, no schema changes. Dependencies #705, #706, and #707 must be merged before the *implementation* PR for this item; the plan stage has no such constraint.

**Dependencies**: Implementation depends on #705 (script), #706 (CI workflow), and #707 (integration docs) being merged into `develop-claude-review-platform` before the implementation PR is merged. Plan writing has no such dependency.

---

## Verification Log

> Reproducible plan-time verification commands used to confirm scope.

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` (worktree) | `0e984a7` |
| Current `phase_after_clean` value in `.ai-dev-workflow.yaml` | `grep -n "phase_after_clean\|coderabbit" .ai-dev-workflow.yaml` | `phase_after_clean: [coderabbit]`; `coderabbit` appears in `platforms` list and `phase_after_clean` list |
| `claude-code-action` already present in `.ai-dev-workflow.yaml` | `grep "claude-code-action" .ai-dev-workflow.yaml` | No matches (not yet added) |
| `review.platforms` comment line | `grep "Supported today" .ai-dev-workflow.yaml` | `# Supported today by pr-review-loop.sh: greptile, devin, coderabbit, pr-agent, codex-github` |
| README Optional Integrations section | `grep -n "Automated PR Review" README.md` | Line 261: `Automated PR Review (e.g., Greptile)` |
| README mentions of `claude-code-action` | `grep "claude-code-action" README.md` | No matches (not yet added) |

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] In `.ai-dev-workflow.yaml`, update the `# Supported today by pr-review-loop.sh:` comment to append `claude-code-action` to the platform list.
- [ ] In `.ai-dev-workflow.yaml`, add a comment block below the existing `phase_after_clean` comment that recommends `claude-code-action` as the value to use in place of `coderabbit` to remove the rate-limit bottleneck.
- [ ] Do **not** change the active `review.platforms` list values or the active `review.phase_after_clean` value — only comments are modified by this item (the active config change is out of scope per the spec's Business Rules and Out of Scope section).

### Frontend / UI

_Not applicable._

### Backend / API

_Not applicable._

### Shared Packages / Libraries

_Not applicable._

### Database / Data Layer

_Not applicable._

---

## Testing Strategy

**Test types**: Manual (smoke test)

**Key scenarios to test**:

1. Open `.ai-dev-workflow.yaml` and confirm `claude-code-action` appears in the `Supported today` comment line — maps to AC1.
2. Open `.ai-dev-workflow.yaml` and confirm the `phase_after_clean` comment block explicitly names `claude-code-action` as the recommended value — maps to AC2.
3. Open `README.md` and confirm `claude-code-action` is mentioned as the recommended `phase_after_clean` platform — maps to AC3.
4. Open `CHANGELOG.md` and confirm a new entry exists under `[Unreleased]` describing this update — maps to AC4.
5. Verify that the active `review.platforms` list and `review.phase_after_clean` value in `.ai-dev-workflow.yaml` are unchanged (still contain `coderabbit`) — maps to AC5.

**Smoke test runbook**: `docs/testing/workflow/708-claude-code-action-config.smoke-test.md`

---

## Seed Data

_Not applicable — no application runtime or database is involved._

---

## Documentation Updates

- [ ] `README.md` — update the "Optional Integrations" section: expand the "Automated PR Review" bullet to mention `claude-code-action` as the recommended `phase_after_clean` platform and link to the integration guide added by sibling item #707.

> Note: `AGENTS.md` (aliased as `CLAUDE.md`/`GEMINI.md`) does not currently describe review platform configuration in detail; the reference to `.ai-dev-workflow.yaml` as the source of truth is sufficient. No update to `AGENTS.md` is required.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Developer misreads the comment update as a change to the active config and enables `claude-code-action` prematurely (before sibling items are merged) | Low | Low | Comments are clearly worded as guidance ("recommended value"), not as active configuration. The active list values are not modified. |
| sibling item #707 integration guide path referenced in `README.md` does not exist yet at plan time | Medium | Low | Plan step references the integration guide path as established by #707; developer confirms the path exists before linking when implementing. If #707 is not yet merged, use a placeholder link or defer the README link until after #707 merges. |

---

## Implementation Order

1. **Update `.ai-dev-workflow.yaml` comment: `Supported today` line** — append `claude-code-action` to the platform list in the comment: change `# Supported today by pr-review-loop.sh: greptile, devin, coderabbit, pr-agent, codex-github` to `# Supported today by pr-review-loop.sh: greptile, devin, coderabbit, pr-agent, codex-github, claude-code-action`.

   Verification: open `.ai-dev-workflow.yaml` and confirm the comment line now includes `claude-code-action`.

2. **Update `.ai-dev-workflow.yaml` comment: `phase_after_clean` guidance** — add a comment below the existing `phase_after_clean` block that explicitly recommends `claude-code-action` as the value to swap in for `coderabbit` to remove the per-hour rate-limit constraint. The comment should mention that `claude-code-action` requires the `ANTHROPIC_API_KEY` secret and the CI workflow from sibling item #706, and that the integration guide (sibling item #707) covers setup. Example wording (illustrative — adapt during implementation):

   ```yaml
   # Recommended: swap coderabbit for claude-code-action in phase_after_clean to
   # remove the CodeRabbit per-hour rate-limit bottleneck. claude-code-action has
   # no review cap and uses your own Anthropic API key. Requires the
   # ANTHROPIC_API_KEY secret and the CI workflow from sibling item #706.
   # See docs/workflow/development-workflow/integrations/claude-code-action.md
   # for setup instructions.
   ```

   Verification: open `.ai-dev-workflow.yaml` and confirm the new comment is present near the `phase_after_clean` stanza and names `claude-code-action` explicitly.

3. **Update `README.md` Optional Integrations section** — expand the `Automated PR Review` bullet to mention `claude-code-action` as the recommended `phase_after_clean` option. Example (illustrative — adapt during implementation):

   ```markdown
   - **Automated PR Review (e.g., CodeRabbit, claude-code-action)**: See [`docs/workflow/development-workflow/integrations/coderabbit.md`](docs/workflow/development-workflow/integrations/coderabbit.md) or [`docs/workflow/development-workflow/integrations/claude-code-action.md`](docs/workflow/development-workflow/integrations/claude-code-action.md) (recommended `phase_after_clean` value; no rate-limit cap)
   ```

   Verify that sibling item #707's integration guide file (`docs/workflow/development-workflow/integrations/claude-code-action.md`) exists before adding the link. If it does not exist (i.e., #707 is not yet merged), link to the existing `greptile.md` as a placeholder or omit the direct link and add a note instead; do not create a dead link.

   Verification: open `README.md` and confirm `claude-code-action` is mentioned in the Optional Integrations section.

4. **Add CHANGELOG entry** — add a new bullet under `[Unreleased]` → `### Changed` (create the `### Changed` header if it does not yet exist under `[Unreleased]`):

   ```markdown
   - **Register claude-code-action as recommended phase_after_clean reviewer** (#708): Updated `.ai-dev-workflow.yaml` inline comments to list `claude-code-action` as a supported platform and recommend it as the `phase_after_clean` value in place of CodeRabbit for projects that want to avoid per-hour rate-limit stalls. Updated `README.md` Optional Integrations section to surface `claude-code-action` alongside existing options.
   ```

   Verification: open `CHANGELOG.md` and confirm the entry appears under `[Unreleased]`.

5. **Verify AC5 (no active config change)** — confirm that the `review.platforms` list and `review.phase_after_clean` value in `.ai-dev-workflow.yaml` remain unchanged (both still contain `coderabbit`; `claude-code-action` does not appear in the active YAML values, only in comments).

6. **Update project docs per Documentation Updates section** — already covered in steps 1–3 above. No additional `docs/project/` files require updating for this item.

7. **Run markdown lint** to confirm no trailing whitespace or link errors were introduced:

   ```bash
   npx markdownlint-cli2 "docs/specs/developments/20260523170145_708-claude-code-action-config/2_708-claude-code-action-config_implementation-plan.md" "CHANGELOG.md"
   ```

   Confirm no lint errors are reported.

8. **Verify smoke test runbook** — run through `docs/testing/workflow/708-claude-code-action-config.smoke-test.md` steps 1–5 to confirm all acceptance criteria are met before opening the PR.

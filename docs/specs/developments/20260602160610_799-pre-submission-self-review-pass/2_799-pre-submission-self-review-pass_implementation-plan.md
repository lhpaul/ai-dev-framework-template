# Pre-Submission Self-Review Pass Before Opening PR — Implementation Plan

**Spec**: [1_799-pre-submission-self-review-pass_specs.md](1_799-pre-submission-self-review-pass_specs.md)
**Smoke test runbook**: [799-pre-submission-self-review-pass.smoke-test.md](../../../../docs/testing/workflow/799-pre-submission-self-review-pass.smoke-test.md)

---

## Summary

**Approach**: Add a mandatory pre-PR diff self-review gate to Protocol 03 immediately before each implementation path opens a draft PR. Mirror the new requirement in developer-facing agent/skill guidance and reviewer-facing `REVIEW.md` so implementers know to run the pass and reviewers can flag stale markers, caller inconsistencies, or missing coverage that should have been caught before PR creation.

**Estimated complexity**: M

**Rationale**: The implementation is mostly documentation and workflow guidance, but it touches several duplicated protocol paths and agent surfaces. The main risk is inconsistent wording across paths, which would cause implementers to apply the new gate only to some branch types.

**Dependencies**: None. Closed issue #614 already shipped the Test Harness Coverage Checklist; this work references it but does not depend on further code changes.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `ea483b0` |
| Protocol 03 PR-open surfaces | `rg -n "gh pr create|Board membership check|Test Harness Coverage Checklist|Script-Accuracy Self-Check" docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` | Four implementation paths contain pre-PR verification and PR-create sections: Full Pipeline, Refactor, Fast Track Fix, and Hotfix. |
| Cross-cutting checklist target discovery | `grep -rl "02-generate-implementation-plan-protocol\\|03-implement-development-protocol" .claude/agents/ .cursor/agents/ .codex/skills/ .agents/skills/ 2>/dev/null \| sort` | Six direct targets: `.claude/agents/developer.md`, `.claude/agents/tech-lead.md`, `.codex/skills/workflow-implementer/SKILL.md`, `.codex/skills/workflow-plan-writer/SKILL.md`, `.cursor/agents/developer.md`, `.cursor/agents/tech-lead.md`. The developer files and `workflow-implementer` invoke Protocol 03 directly; tech-lead and plan-writer already carry the cross-cutting checklist enumeration requirement and should not need content changes for this implementation-stage gate. |
| Reviewer contract location | `rg -n "Pass 1: Spec Compliance|Pass 2: Code Quality|Cross-cutting checklist|documentation PRs" REVIEW.md` | `REVIEW.md` already has plan-review cross-cutting checklist checks and code-quality checks for documentation PRs; add the new implementation self-review verification under the code review checklist. |
| Existing test-harness checklist | `rg -n "Test Harness Coverage Checklist" docs/workflow/development-workflow/protocols/03-implement-development-protocol.md .claude/agents .cursor/agents .codex/skills` | Protocol 03 has the checklist and each implementation path references it; developer agents and `workflow-implementer` read Protocol 03, so the new gate can cross-reference the existing checklist rather than duplicating it. |

---

## Layer-by-Layer Changes

### Files To Modify

Implementation must modify:

- `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
- `.claude/agents/developer.md`
- `.cursor/agents/developer.md`
- `.codex/skills/workflow-implementer/SKILL.md`
- `REVIEW.md`
- `CHANGELOG.md`

Implementation must explicitly verify but is expected not to modify:

- `.claude/agents/tech-lead.md`
- `.cursor/agents/tech-lead.md`
- `.codex/skills/workflow-plan-writer/SKILL.md`

### Workflow Protocols And Review Contract

- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` — add a named "Pre-Submission Self-Review Pass" section before the path-specific implementation steps. The section must define the three-dot diff command, stale-marker scan, sibling/caller consistency check, and coverage check.
- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` — insert an explicit "run the Pre-Submission Self-Review Pass" step after verification/CHANGELOG work and before the board-membership and `gh pr create` steps in all four paths: Full Pipeline, Refactor, Fast Track Fix, and Hotfix.
- [ ] `REVIEW.md` — add a code-review checklist item requiring reviewers to flag stale debug/TODO/review markers, caller inconsistencies, and uncovered spec or issue-body requirements that should have been caught by the pre-submission pass.

### Agent And Skill Guidance

- [ ] `.claude/agents/developer.md` — add a concise reminder that implementation PRs must complete the Protocol 03 pre-submission self-review pass before opening the draft PR.
- [ ] `.cursor/agents/developer.md` — mirror the Claude developer reminder so Cursor agents apply the same pre-PR gate.
- [ ] `.codex/skills/workflow-implementer/SKILL.md` — add the same pre-PR self-review requirement before draft PR creation.
- [ ] `.claude/agents/tech-lead.md` — no content change expected; retain as reviewed because the file participates in cross-cutting checklist discovery but this feature changes implementation behavior, not plan-writing behavior.
- [ ] `.cursor/agents/tech-lead.md` — no content change expected for the same reason.
- [ ] `.codex/skills/workflow-plan-writer/SKILL.md` — no content change expected for the same reason.

### Tests And Validation

- [ ] No application code, database schema, or runtime configuration changes are required.
- [ ] Run markdown lint for the modified protocol, review contract, agent docs, plan, and smoke runbook.
- [ ] Run the heuristic markdown lint on `docs/specs/developments`, `docs/testing/workflow`, and `CHANGELOG.md`.
- [ ] Run a live grep after implementation to verify every `gh pr create` path in Protocol 03 has a preceding pre-submission self-review instruction.

---

## Testing Strategy

**Test types**: Documentation lint, repository grep validation, smoke/manual protocol validation.

**Key scenarios to test**:

1. Full Pipeline path contains the self-review gate before draft PR creation and maps to AC-1.
2. Refactor path contains the self-review gate and uses implementation-plan acceptance criteria, mapping to AC-2.
3. Fast Track Fix path contains stale-marker and sibling/caller checks plus issue-body coverage, mapping to AC-3.
4. Hotfix path uses the same gate with `main` as the base branch, mapping to AC-4.
5. The gate cites `git diff <base-branch>...HEAD`, references the Test Harness Coverage Checklist, and requires a PR description self-review log, mapping to AC-5 through AC-7.
6. `REVIEW.md` contains the reviewer verification item, mapping to AC-8.

**Smoke test runbook**: `docs/testing/workflow/799-pre-submission-self-review-pass.smoke-test.md`

**Regression suite**: No committed automated regression suite exists for protocol prose. Use markdown lint and grep-based validation as the regression guard.

### Cross-Cutting Checklist Completeness

This plan introduces a cross-cutting quality checklist that applies across implementation PRs. The implementation must explicitly cover:

- `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`
- `.claude/agents/developer.md`
- `.cursor/agents/developer.md`
- `.codex/skills/workflow-implementer/SKILL.md`
- `REVIEW.md`

Files reviewed but expected to remain unchanged:

- `.claude/agents/tech-lead.md`
- `.cursor/agents/tech-lead.md`
- `.codex/skills/workflow-plan-writer/SKILL.md`

---

## Seed Data

No seed data is required.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` — document the new gate and place it before PR creation in all implementation paths.
- [ ] `REVIEW.md` — add the reviewer check for stale markers, caller consistency, and coverage gaps that should have been caught before PR creation.
- [ ] `.claude/agents/developer.md` — add the developer reminder.
- [ ] `.cursor/agents/developer.md` — add the developer reminder.
- [ ] `.codex/skills/workflow-implementer/SKILL.md` — add the Codex implementer reminder.
- [ ] `CHANGELOG.md` — add `- **Pre-submission self-review pass** (#799): Adds a mandatory pre-PR diff self-review gate for implementation agents so stale markers, caller inconsistencies, and uncovered acceptance criteria are caught before draft PR creation.` under `[Unreleased]` in the implementation PR.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The new gate is inserted in one implementation path but omitted from another. | Medium | High | Use a grep validation over all `gh pr create` path sections and explicitly verify Full Pipeline, Refactor, Fast Track Fix, and Hotfix. |
| The self-review wording duplicates the existing Test Harness Coverage Checklist and creates contradictory guidance. | Medium | Medium | Define the new pass as broader diff review and explicitly state that it complements, not replaces, the harness checklist. |
| Reviewers cannot enforce the new gate because `REVIEW.md` lacks a matching checklist item. | Low | Medium | Add the reviewer check in the same implementation PR and include it in validation. |

---

## Code Samples

No production code samples are required. The implementation may include shell snippets for validation only; any new state-mutating shell snippets in protocol docs must follow the shell snippet safety rules in `REVIEW.md`.

---

## Implementation Order

1. Add a new Protocol 03 subsection named "Pre-Submission Self-Review Pass" near the existing pre-commit verification checklists. Define:
   - `git diff <base-branch>...HEAD` as the required diff form.
   - `<base-branch>` resolution: `develop` by default, `develop-<slug>` for integration-branch items, and `main` for hotfixes.
   - Stale-marker check for newly introduced debug comments, TODO/FIXME comments, temporary workarounds, and review-marker comments.
   - Sibling/caller consistency check scoped to changed files and changed call sites visible in the diff.
   - Coverage check against spec ACs for Full Pipeline, implementation-plan ACs for Refactor, and issue-body problem/proposed fix for Fast Track Fix and Hotfix.
   - Required PR-description self-review log.
   - Explicit relationship to the Test Harness Coverage Checklist from #614.
2. Insert a short required step in each Protocol 03 implementation path before board-membership check and `gh pr create`:
   - Full Pipeline Path 1: reference spec AC coverage.
   - Refactor Path 2: reference implementation-plan AC coverage.
   - Fast Track Fix Path 3: reference issue-body coverage.
   - Hotfix Path 4: reference `main` as the diff base.
3. Update `.claude/agents/developer.md`, `.cursor/agents/developer.md`, and `.codex/skills/workflow-implementer/SKILL.md` with a concise reminder to complete the Protocol 03 pre-submission self-review pass before opening implementation PRs.
4. Update `REVIEW.md` so implementation code reviews flag stale markers, caller inconsistencies, or uncovered acceptance criteria that should have been caught by the pre-submission pass.
5. Update `CHANGELOG.md` under `[Unreleased]` with:
   `- **Pre-submission self-review pass** (#799): Adds a mandatory pre-PR diff self-review gate for implementation agents so stale markers, caller inconsistencies, and uncovered acceptance criteria are caught before draft PR creation.`
6. Run validation:
   - `npx markdownlint-cli2 "docs/workflow/development-workflow/protocols/03-implement-development-protocol.md" "REVIEW.md" ".claude/agents/developer.md" ".cursor/agents/developer.md" ".codex/skills/workflow-implementer/SKILL.md" "docs/specs/developments/20260602160610_799-pre-submission-self-review-pass/2_799-pre-submission-self-review-pass_implementation-plan.md" "docs/testing/workflow/799-pre-submission-self-review-pass.smoke-test.md"`
   - `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`
   - `rg -n "Pre-Submission Self-Review Pass|gh pr create|Board membership check" docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` and confirm every implementation path has the self-review step before PR creation.

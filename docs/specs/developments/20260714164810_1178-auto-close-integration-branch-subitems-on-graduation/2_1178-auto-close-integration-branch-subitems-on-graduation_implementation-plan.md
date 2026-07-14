# Auto-Close Integration-Branch Sub-Items on Graduation - Implementation Plan

**Spec**: [1_1178-auto-close-integration-branch-subitems-on-graduation_specs.md](1_1178-auto-close-integration-branch-subitems-on-graduation_specs.md)
**Smoke test runbook**: [1178-auto-close-integration-branch-subitems-on-graduation.smoke-test.md](../../../testing/workflow/1178-auto-close-integration-branch-subitems-on-graduation.smoke-test.md)

---

## Summary

**Approach**: Add an explicit post-merge graduation closeout helper for
`/graduate-development` and make Protocol 05b call it after the graduation PR
has merged. The helper will reconcile planned delivered sub-items and the parent
epic by closing open GitHub issues, moving project items to a configured terminal
status, reporting already-terminal/skipped/failed outcomes, and leaving optional
or deferred work open for human disposition.

**Estimated complexity**: M

**Rationale**: The change is workflow-tooling only, but it touches GitHub API
queries, GitHub Projects status updates, issue closure, parser-risk closing
keyword extraction, repeatable partial-failure behavior, and mirrored command
guidance.

**Dependencies**: None. The implementation should reuse existing GitHub
Projects helper functions in `scripts/development-workflow/workflow-lib.sh`.

---

## Verification Log

| Check | Command / query | Result |
| ----- | --------------- | ------ |
| Repo revision | `git rev-parse --short HEAD` | `d26edf4` |
| Template-fit check | `rg -n "is_template: true" .ai-dev-workflow.yaml` | `.ai-dev-workflow.yaml:152` confirms this is a template repo; scope is workflow tooling and framework-generic. |
| Acceptance criteria inventory | `rg -n "^## Acceptance Criteria|^- \\[ \\] AC" docs/specs/developments/20260714164810_1178-auto-close-integration-branch-subitems-on-graduation/1_1178-auto-close-integration-branch-subitems-on-graduation_specs.md` | AC1 through AC10 are present, including AC3a as a distinct closed-but-non-terminal case. |
| Existing graduation cleanup gap | `rg -n "Step 5: Post-Merge Cleanup|Sub-items already marked Done|Close the epic issue|Optional sub-item disposition" docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md` | Step 5 closes the epic and surfaces optional open sub-items, but BR-9 currently says sub-items are already marked done and no tracker update is needed. |
| Existing closing keyword parser | `rg -n "GitHub closing keywords|CLOSES_ISSUES|close\\[sd\\]|resolve\\[sd\\]" scripts/development-workflow/post-merge-cleanup.sh` | `post-merge-cleanup.sh` already parses PR title/body closing keywords at lines 410-463; reuse or extract this behavior rather than inventing incompatible semantics. |
| Graduation command mirrors | `rg --files .agents .claude .cursor \| rg 'graduate-development' \| sort` | Four mirrors exist: `.agents/skills/graduate-development/SKILL.md`, `.agents/skills/graduate-development/agents/openai.yaml`, `.claude/commands/graduate-development.md`, `.cursor/commands/graduate-development.md`. |
| Cross-cutting checklist search | `grep -rl "02-generate-implementation-plan-protocol\\|03-implement-development-protocol" .claude/agents/ .cursor/agents/ .codex/skills/ \|\| true` | Planning/implementation guidance references exist, but this plan does not add or rename a cross-cutting checklist category, so the cross-cutting checklist block is not applicable. |

---

## Layer-by-Layer Changes

### Workflow Script / Tracker Automation

- [ ] Add `scripts/development-workflow/graduation-closeout.sh`.
- [ ] Source `scripts/development-workflow/workflow-lib.sh` and reuse
      `repo_slug`, `get_tracker_status_for_issue`, `update_tracker_status_best_effort`,
      and `is_terminal_tracker_status` where applicable.
- [ ] Support at least these inputs:
      `--slug <slug>`, `--graduation-pr <number>`, `--epic <issue-number>`,
      optional repeated `--exclude-issue <number>`, and optional
      `--defer-epic-close`.
- [ ] Resolve the integration branch as `develop-<slug>` and validate all issue
      and PR numbers before calling `gh`, `git`, or GraphQL.
- [ ] Resolve planned sub-items by preferring native GitHub sub-issues for the
      epic and falling back to `integration-branch:<slug>` labels when native
      sub-issues are unavailable.
- [ ] Include issue numbers referenced by merged sub-item PR title/body closing
      keywords when those PRs targeted `develop-<slug>`, then de-duplicate the
      planned delivered set.
- [ ] Classify optional/deferred/cancelled/excluded items before mutation.
      Deterministic skip signals should include explicit `--exclude-issue`
      values and lower-case labels such as `optional`, `deferred`, `cancelled`,
      `excluded-from-graduation`, or `exclude-from-graduation`.
- [ ] Resolve the terminal closeout status from configuration in this order:
      `GITHUB_PROJECT_STATUS_GRADUATED`, `GITHUB_PROJECT_STATUS_MERGED`, then
      `Merged`. Repos that use `Done` or `Released` can opt in with the
      environment override as long as the Project Status option exists.
- [ ] Treat a project status as terminal when it equals the configured closeout
      status or is already a more advanced terminal status. Do not rely only on
      `is_terminal_tracker_status` for configured values such as `Done` unless
      that helper is also updated in the implementation PR.
- [ ] For each delivered planned sub-item:
      - if the issue is open, close it with a comment naming the graduation PR
        and integration branch;
      - update or reassert the configured terminal project status after closure
        so GitHub Projects built-in close automation cannot leave stale status;
      - if the issue is already closed but project status is not terminal,
        update only the project status;
      - if both issue state and project status are terminal, report
        `already_terminal` without moving backward;
      - if closure or status update fails, keep processing other items and emit a
        `failed` result for retry.
- [ ] Close the parent epic and move it to the same terminal status only when all
      delivered planned sub-items reconcile, unless `--defer-epic-close` is set.
- [ ] Emit a stable, parseable summary with separate sections for
      `closed`, `already_terminal`, `skipped_optional`, and `failed`, including
      issue numbers, titles when available, source PR numbers when known, and
      the required human action for every skipped or failed item.
- [ ] Make the helper repeatable: reruns must skip already-terminal items, update
      only closed-but-non-terminal items, and avoid duplicating successful
      closeout comments where the issue already records the same graduation PR.

### Protocol and Command Guidance

- [ ] Update
      `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`
      Step 5 so post-merge cleanup runs `graduation-closeout.sh` before
      reporting the integration branch as fully closed.
- [ ] Replace the existing BR-9 assumption that sub-items are already done with a
      rule requiring the closeout sweep to reconcile delivered planned
      sub-items.
- [ ] Update `.agents/skills/graduate-development/SKILL.md`,
      `.claude/commands/graduate-development.md`, and
      `.cursor/commands/graduate-development.md` so the wrapper summaries mention
      sub-item reconciliation, terminal status updates, partial-failure
      reporting, and epic closure ordering.
- [ ] Review `.agents/skills/graduate-development/agents/openai.yaml`; update only
      if it contains operator-facing behavior that contradicts the new closeout
      contract.

### Documentation

- [ ] Update
      `docs/workflow/development-workflow/integrations/github-projects.md` to
      document integration-branch graduation closeout status behavior and the
      optional `GITHUB_PROJECT_STATUS_GRADUATED` override.
- [ ] Update `docs/workflow/development-workflow/README.md` only if its
      integration-branch summary would otherwise imply branch deletion and epic
      closure are sufficient without sub-item reconciliation.
- [ ] Do not update `AGENTS.md` unless the implementation changes command names,
      branch policy, or repository-wide rules.
- [ ] Do not update `CHANGELOG.md`; implementation-plan branches are exempt.

### Test / Validation Assets

- [ ] Add `scripts/development-workflow/tests/test-graduation-closeout.sh` with
      mocked `gh` responses and fixture Project statuses.
- [ ] Cover native sub-issue discovery, label fallback discovery, closing-keyword
      referenced issue discovery, open issue closure, closed-but-non-terminal
      status update, already-terminal skip, optional/deferred skip, partial
      failure continuation, rerun idempotency, and epic closure deferral.
- [ ] Update or add workflow smoke coverage in
      `docs/testing/workflow/1178-auto-close-integration-branch-subitems-on-graduation.smoke-test.md`.

---

## Testing Strategy

**Test types**: Unit, workflow script integration with mocked CLI fixtures,
markdown/documentation smoke, and manual live-repo smoke when a disposable
integration branch is available.

**Key scenarios to test**:

1. Native sub-issue discovery and label fallback both identify planned
   integration-branch sub-items. Maps to AC1.
2. Closing keyword references from merged sub-item PRs targeting
   `develop-<slug>` are included without overmatching non-closing references.
   Maps to AC1 and AC10.
3. Open delivered sub-items are closed and moved to configured terminal status.
   Maps to AC2.
4. Closed and terminal delivered sub-items are reported as already terminal and
   not moved backward. Maps to AC3.
5. Closed but non-terminal delivered sub-items receive the project status update.
   Maps to AC3a.
6. The parent epic closes only after delivered planned sub-items reconcile, or
   stays open when the operator defers closure. Maps to AC4.
7. Optional, deferred, cancelled, and explicitly excluded sub-items remain open
   and appear in the skipped/human-disposition summary. Maps to AC5 and AC6.
8. One closure or tracker update failure does not prevent other items from
   reconciling, and reruns process only still-non-terminal items. Maps to AC7
   and AC8.
9. A successful closeout leaves delivered sub-items closed and terminal so
   portfolio scans no longer classify them as open actionable work. Maps to AC9.

**Smoke test runbook**:
`docs/testing/workflow/1178-auto-close-integration-branch-subitems-on-graduation.smoke-test.md`

**Regression suite**: Add
`scripts/development-workflow/tests/test-graduation-closeout.sh`; no browser or
application regression suite applies to this workflow-only change.

---

## Parser-Risk Addendum

This plan is parser-risk because the helper will parse structured PR title/body
text for GitHub closing keyword references.

### Edge-Case Enumeration

1. Boundary keyword variants: `Closes #123`, `closed issue #123`,
   `FIXES #123`, and `resolved #123` should match case-insensitively.
2. Negative lookalikes: `disclose #123`, `hotfix #123`, `related #123`, and
   `not closing #123` must not match as closing refs.
3. Multiple occurrences on one line: `Closes #123, fixes #124` should discover
   both issue numbers once.
4. Duplicate refs across title/body and multiple PRs should de-duplicate to one
   closeout action per issue.
5. Optional `issue` word: `Resolves issue #123` should match the same as
   `Resolves #123`.
6. Cross-repository or owner-qualified references are out of scope for the MVP;
   the helper should ignore refs that are not plain `#<number>` in the current
   repository rather than attempting cross-repo mutation.
7. Markdown and punctuation boundaries: closing refs inside list items,
   parentheses, or trailing punctuation should still extract the numeric issue.

### Unit Test Mapping

Use `scripts/development-workflow/tests/test-graduation-closeout.sh`.

- Edge 1: `closing_keyword_variants_match`.
- Edge 2: `closing_keyword_negative_lookalikes_do_not_match`.
- Edge 3: `closing_keyword_multiple_refs_one_line`.
- Edge 4: `closing_keyword_duplicate_refs_deduplicate_actions`.
- Edge 5: `closing_keyword_optional_issue_word_matches`.
- Edge 6: `closing_keyword_cross_repo_refs_ignored`.
- Edge 7: `closing_keyword_markdown_punctuation_boundaries`.

### Suppression Semantics

Not applicable. The feature does not introduce inline suppression directives.

---

## Concurrency Safety

Not applicable. The implementation is a single command-line closeout sweep with
sequential `gh` and GraphQL operations. It does not introduce multiple listeners,
timers, socket callbacks, async queues, or shared mutable state across execution
contexts.

---

## Seed Data

No application seed data is required. Tests should use mocked GitHub CLI and
GraphQL fixtures inside `scripts/development-workflow/tests/test-graduation-closeout.sh`.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`
      - document the graduation closeout helper, terminal status resolution,
      sub-item reconciliation results, partial failure behavior, and updated
      business-rule mapping.
- [ ] `.agents/skills/graduate-development/SKILL.md` - keep Codex command
      guidance aligned with the new Step 5 closeout responsibilities.
- [ ] `.claude/commands/graduate-development.md` - keep Claude command guidance
      aligned with the new Step 5 closeout responsibilities.
- [ ] `.cursor/commands/graduate-development.md` - keep Cursor command guidance
      aligned with the new Step 5 closeout responsibilities.
- [ ] `docs/workflow/development-workflow/integrations/github-projects.md` -
      document the graduation closeout terminal status override and interaction
      with project item status updates.
- [ ] `docs/workflow/development-workflow/README.md` - update only if the
      existing integration-branch summary becomes incomplete after the protocol
      change.
- [ ] `docs/testing/workflow/1178-auto-close-integration-branch-subitems-on-graduation.smoke-test.md`
      - implement smoke coverage for AC1 through AC10.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| ---- | ---------- | ------ | ---------- |
| Closing optional or deferred work accidentally | Medium | High | Require explicit skip signals and report skipped open items separately; do not infer optional status from lack of merged PR alone. |
| Project status option differs across repositories | Medium | Medium | Resolve terminal status from `GITHUB_PROJECT_STATUS_GRADUATED`, `GITHUB_PROJECT_STATUS_MERGED`, then `Merged`, and treat unresolved status options as failed/manual repair. |
| GitHub API failure leaves partial cleanup | Medium | Medium | Keep processing independent items, emit failed results, and make reruns idempotent. |
| Closing keyword parser overmatches issue refs | Medium | Medium | Reuse existing keyword semantics where possible and add parser-risk unit tests for boundaries, negatives, duplicates, and punctuation. |
| Epic closes before child failures are repaired | Low | High | Gate epic closure on zero failed delivered planned sub-items unless `--defer-epic-close` records an explicit operator deferral. |

---

## Code Samples

No production code samples. The implementation PR should contain the actual
shell helper and tests.

---

## Implementation Order

1. Add `scripts/development-workflow/graduation-closeout.sh` with argument
   validation, repo resolution, terminal status resolution, and read-only
   discovery helpers for native sub-issues, label fallback, merged PRs targeting
   `develop-<slug>`, and closing keyword references.
2. Implement delivered/optional classification and closeout execution in the
   helper: sub-item status reconciliation first, then parent epic closure only
   after delivered sub-items are reconciled or explicitly deferred.
3. Add `scripts/development-workflow/tests/test-graduation-closeout.sh` covering
   all parser-risk cases and workflow outcomes listed in the Testing Strategy.
4. Run the new test directly and confirm it passes:
   `bash scripts/development-workflow/tests/test-graduation-closeout.sh`.
5. Run existing related tests and confirm they still pass:
   `bash scripts/development-workflow/tests/test-workflow-lib-github-projects.sh`
   and `bash scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh`.
6. Run shell quality checks for the changed workflow script:
   `shellcheck scripts/development-workflow/graduation-closeout.sh scripts/development-workflow/tests/test-graduation-closeout.sh`
   and `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`.
7. Update Protocol 05b Step 5 and the graduate-development command mirrors so
   operators are told to run the closeout sweep, interpret its summary, and stop
   for failed or skipped items that need human repair.
8. Update GitHub Projects integration documentation and README text only where
   needed by the Documentation Updates section.
9. Verify the smoke test runbook manually against the changed docs and helper
   behavior, then run markdown lint on the changed plan/runbook plus any updated
   workflow docs.
10. Add the implementation CHANGELOG entry under `[Unreleased]` using the
    project format:
    `- **Auto-close graduation sub-items** (#1178): Reconcile delivered integration-branch sub-items and parent epics during graduation closeout.`

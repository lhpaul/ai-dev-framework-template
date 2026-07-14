# Mandatory Ground-Truth Completion Verification — Implementation Plan

**Spec**: [1_1202-mandatory-ground-truth-completion-verification_specs.md](1_1202-mandatory-ground-truth-completion-verification_specs.md)
**Smoke test runbook**: [1202-mandatory-ground-truth-completion-verification.smoke-test.md](../../../testing/workflow/1202-mandatory-ground-truth-completion-verification.smoke-test.md)

---

## Summary

**Approach**: Add a reusable Work Item Runner completion self-check helper and
make Protocol 91 require its ground-truth evidence before any terminal item
report. Extend Protocol 90 batch summaries to consume that evidence, then update
the mirrored agent, Codex skill, review, and smoke-test surfaces so downstream
template consumers get the same requirement across runners.

**Estimated complexity**: M

**Rationale**: The behavioral change is workflow-wide and cross-cutting, but it
is bounded to protocol documentation, runner guidance, and shell tests. The new
helper should reuse existing `git`, `gh`, and tracker-read patterns rather than
changing merge authority, review gates, CI gates, or project data models.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `d26edf4` |
| Template-fit check | Read `.ai-dev-workflow.yaml` | `template.is_template: true`; spec is workflow/process tooling and framework-agnostic, so it passes. |
| Spec ordering gate | `git show origin/develop:docs/specs/developments/20260714164841_1202-mandatory-ground-truth-completion-verification/1_1202-mandatory-ground-truth-completion-verification_specs.md >/dev/null && echo spec-present-on-origin-develop` | Spec is present on `origin/develop`; plan PR can target `develop`. |
| Cross-cutting surface search | `grep -rl "02-generate-implementation-plan-protocol\\|03-implement-development-protocol\\|91-orchestrate-work-protocol\\|Work Item Runner Summary\\|completion report\\|ready-for-human-review" .agents/skills .claude/agents/ .cursor/agents/ .codex/skills/ docs/workflow/development-workflow/protocols REVIEW.md scripts/development-workflow 2>/dev/null \| sort \| wc -l` | `54` matching files; used to enumerate required and reviewed surfaces below. |
| Primary Work Item Runner evidence gate | `sed -n '2225,2355p' docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Step 8b already requires live-state completion confirmation; Step 8c independently verifies PR base, labels, review threads, reviewer summary, and CI before reporting ready. |
| Batch done-report evidence gate | `sed -n '1278,1360p' docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | Step 5.1 already requires artifact-state queries before batch done reports; implementation should require item-level self-check evidence to be included. |
| Workflow test location | `ls scripts/development-workflow/tests \| sort` | Existing shell tests live under `scripts/development-workflow/tests/`; add self-check tests there. |

---

## Layer-by-Layer Changes

### Workflow Helper Scripts

- [ ] Add `scripts/development-workflow/item-completion-self-check.sh`.
- [ ] The helper accepts at minimum `--issue`, `--branch`, `--worktree-path`,
      `--stage`, optional `--pr`, optional `--expected-base`, and optional
      `--claim` values.
- [ ] The helper prints a stable Markdown section headed
      `## Ground-Truth Completion Verification` that can be pasted into Work
      Item Runner and batch summaries.
- [ ] The helper records each surface as `verified`, `not_applicable`,
      `unavailable`, or `discrepancy`.
- [ ] Verified repository evidence includes current branch, current HEAD SHA,
      workspace path, `git status --short`, and `git worktree list` when a
      worktree path is supplied. This covers AC2, AC3, AC6, and AC7.
- [ ] Verified PR evidence, when `--pr` is supplied, comes from live `gh pr view`
      fields for PR number, base branch, draft state, labels, changed files,
      status checks, and comments. This covers AC2, AC4, AC5, and AC6.
- [ ] Verified review-thread evidence uses the existing GraphQL review-thread
      query pattern from Protocol 91 Step 8c, including configured bot authors
      where practical. This covers AC4, AC5, and AC10.
- [ ] Verified tracker evidence uses `get_tracker_status_for_issue` from
      `scripts/development-workflow/workflow-lib.sh` when the configured
      provider supports CLI reads. Tracker status is a required surface whenever
      the terminal report claims tracker synchronization, issue status, or
      post-merge reconciliation; unavailable required tracker reads emit
      `unavailable_required` and a non-zero exit. Tracker reads are optional only
      when the report explicitly says tracker state was not part of the terminal
      claim. This covers AC3, AC5, AC6, and AC8.
- [ ] External runtime, database, browser, deployment, and environment claims are
      accepted only through explicit `--claim` records whose evidence command or
      result is provided by the caller. A claim marked `required=true` emits
      `unavailable_required` and a non-zero exit when evidence is missing or
      unreadable; a claim marked `required=false` emits `unavailable_optional`
      and does not by itself block terminal success. This covers AC5 and AC8.
- [ ] Any mismatch between expected branch, expected PR base, expected labels,
      clean workspace, green CI, changed-file scope, review status, or tracker
      state produces a `discrepancy` result and a non-zero exit code. This covers
      AC5 and AC9.
- [ ] Define the required-surface table in the helper documentation and tests:
      branch, HEAD, workspace cleanliness, PR base, PR labels, CI status, review
      summary, review threads, changed-file scope, and tracker state are required
      when the terminal claim references them. External runtime/browser/database
      evidence is required only when the caller marks the claim required.

### Workflow Protocols

- [ ] Update
      `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      so Step 6 and Step 8c require the completion self-check section before
      any Work Item Runner terminal report.
- [ ] Update Protocol 91 to say that a self-check discrepancy sends the runner
      back to the appropriate existing gate: Step 7a for review findings, Step 8
      for CI, Step 8a for labels/readiness, Step 8b for tracker, or human
      escalation for unavailable required surfaces.
- [ ] Update Protocol 91 Step 10 so post-merge cleanup reports include the same
      self-check evidence when claiming cleanup or tracker reconciliation is
      complete.
- [ ] Update
      `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      so Step 5.1 and Step 6 require parent orchestrators to quote or link each
      item runner's `Ground-Truth Completion Verification` result before
      declaring a batch item terminal.
- [ ] Update
      `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`
      to clarify that `ready-for-human-review` remains the automation-clean
      label, while the self-check is the report evidence layer that proves the
      label and surrounding claims are current.
- [ ] Do not change review, CI, readiness-label, tracker, guardrails, or merge
      authority semantics. The self-check is an additional reporting requirement
      after existing gates pass. This covers AC10.

### Agent and Skill Guidance

- [ ] Update `.claude/agents/item-orchestrator.md`,
      `.cursor/agents/item-orchestrator.md`, and
      `.codex/skills/workflow-item-orchestrator/SKILL.md` to require the
      self-check output before the Work Item Runner Summary.
- [ ] Update `.claude/agents/orchestrator.md`,
      `.cursor/agents/orchestrator.md`, and
      `.codex/skills/workflow-orchestrator/SKILL.md` to require batch summaries
      to be based on item self-check evidence plus Protocol 90 Step 5.1 direct
      artifact queries.
- [ ] Update `.codex/skills/run-items` if present in the shipped skill tree, and
      any mirrored run-items command surface, so explicit-list batch execution
      requires per-item ground-truth completion evidence before final handoff.
- [ ] Update `.agents/skills/run-item/SKILL.md`,
      `.agents/skills/run-items/SKILL.md`, and
      `.agents/skills/run-items/agents/openai.yaml`, which are repo-scoped
      command aliases shipped by this template.
- [ ] Review `.claude/agents/automated-reviewer-loop.md`,
      `.cursor/agents/automated-reviewer-loop.md`, and
      `.codex/skills/workflow-sync-template/SKILL.md`. Update only if their final
      ready reports can bypass Protocol 91's Work Item Runner Summary.
- [ ] Review `.claude/agents/developer.md`, `.cursor/agents/developer.md`, and
      `.codex/skills/workflow-implementer/SKILL.md`. Update only to point
      standalone implementation completion handoffs back to Protocol 91's
      self-check requirement; do not make developer agents responsible for
      replacing the Work Item Runner gate.

### Review Contract

- [ ] Update `REVIEW.md` plan/code review guidance so reviewers verify the new
      completion self-check requirement appears in Protocol 91, batch Protocol
      90, the mirrored item-orchestrator guidance, and tests.
- [ ] Add a documentation-review check that final-report examples do not claim
      readiness, completion, blocked, escalated, or waiting-on-human states
      without a ground-truth evidence section or explicit not-applicable
      rationale.

### Tests and Smoke Coverage

- [ ] Add `scripts/development-workflow/tests/test-item-completion-self-check.sh`
      with stubbed `git` and `gh` commands so tests do not require a live PR.
- [ ] Cover the happy path for a PR-backed plan item: correct branch, expected
      base, non-draft PR, `ready-for-human-review`, no `needs-fixes`, green
      checks, expected changed files, and tracker read available. This covers
      AC1, AC2, AC4, AC6, and AC10.
- [ ] Cover the no-PR terminal path: branch, HEAD, workspace path, tracker
      status available, and PR fields marked `not_applicable`. This covers AC3.
- [ ] Cover a parallel-worktree path where the helper prints the assigned
      worktree path and `git worktree list` evidence. This covers AC7.
- [ ] Cover a discrepancy path where the helper observes the wrong PR base,
      missing readiness label, dirty workspace, or failing CI and exits non-zero
      without reporting success. This covers AC5 and AC9.
- [ ] Cover unavailable required tracker evidence so output marks the surface
      `unavailable_required`, prints the rationale, exits non-zero, and does not
      report terminal success. This covers AC5, AC6, and AC8.
- [ ] Cover unavailable optional tracker or external-runtime evidence so output
      marks the surface `unavailable_optional` with rationale while allowing the
      terminal report to proceed when no required surface failed. This covers AC8.
- [ ] Add the human-readable smoke runbook at
      `docs/testing/workflow/1202-mandatory-ground-truth-completion-verification.smoke-test.md`.

---

## Cross-Cutting Checklist Classification

This plan is a cross-cutting checklist plan because it adds a mandatory quality
and safety requirement that applies to every Work Item Runner terminal report.
The live search in the Verification Log found 54 potentially affected workflow
files. The implementation must update the required files above and explicitly
review these related surfaces before opening the implementation PR:

- `.agents/skills/run-item/SKILL.md`
- `.agents/skills/run-items/SKILL.md`
- `.agents/skills/run-items/agents/openai.yaml`
- `.claude/agents/automated-reviewer-loop.md`
- `.claude/agents/developer.md`
- `.claude/agents/item-orchestrator.md`
- `.claude/agents/orchestrator.md`
- `.claude/agents/tech-lead.md`
- `.cursor/agents/automated-reviewer-loop.md`
- `.cursor/agents/developer.md`
- `.cursor/agents/item-orchestrator.md`
- `.cursor/agents/orchestrator.md`
- `.cursor/agents/tech-lead.md`
- `.codex/skills/batch-merge/SKILL.md`
- `.codex/skills/post-merge-cleanup/SKILL.md`
- `.codex/skills/workflow-implementer/SKILL.md`
- `.codex/skills/workflow-item-orchestrator/SKILL.md`
- `.codex/skills/workflow-orchestrator/SKILL.md`
- `.codex/skills/workflow-plan-writer/SKILL.md`
- `.codex/skills/workflow-sync-template/SKILL.md`
- `REVIEW.md`
- `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
- `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
- `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`
- `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
- `docs/workflow/development-workflow/protocols/94-batch-merge-protocol.md`
- `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
- `scripts/development-workflow/README.md`

The implementation may leave a reviewed file unchanged only when the PR
description records why Protocol 91 or Protocol 90 already covers that runner
path.

---

## Parser/API/Concurrency Classification

- **Parser-risk**: Not applicable. The planned helper should consume structured
  `git`, `gh`, and GraphQL output and compare normalized fields; it does not add
  markdown/code parsing, a lint scanner, suppression directives, or regex-heavy
  structured-text parsing. If implementation adds regex parsing for report
  bodies or changed-file scope, the developer must add a parser-risk addendum
  and map unit tests to boundary, negative, multi-match, and overlapping cases.
- **API-surface changes**: Applicable only to the new local shell helper CLI.
  Required options, optional options, exit codes, output headings, and
  unavailable/discrepancy semantics must be documented in the helper usage text
  and tests.
- **Concurrent-event-source**: Not applicable. The feature does not add event
  listeners, sockets, timers, async queues, or shared mutable state across
  concurrent execution contexts.
- **Human/data-model approval**: Not applicable. This is workflow/process
  tooling and does not create or alter database schema, migrations, seed data,
  production data models, or human approval data structures.

---

## Testing Strategy

**Test types**: Shell unit tests, markdown lint, smoke/manual protocol review.

**Key scenarios to test**:

1. PR-backed item self-check produces verified branch, HEAD, worktree, PR, label,
   file, review, CI, and tracker evidence. Maps to AC1, AC2, AC4, AC6, and AC10.
2. No-PR item self-check marks PR fields not applicable while still verifying
   repository and tracker evidence. Maps to AC3 and AC6.
3. Worktree-backed parallel item report includes assigned worktree path and
   worktree-list evidence. Maps to AC7.
4. Mismatched base branch, missing readiness label, unexpected changed file,
   dirty workspace, failing CI, unresolved review state, or unavailable required
   surface produces a discrepancy/non-success report. Maps to AC5 and AC9.
5. External-runtime claims are either backed by explicit observed evidence or
   marked not verified/unavailable with a reason. Maps to AC8.

**Smoke test runbook**:
`docs/testing/workflow/1202-mandatory-ground-truth-completion-verification.smoke-test.md`

**Regression suite**: Add a shell test under
`scripts/development-workflow/tests/` and wire it into the existing workflow test
execution path if that path has a central runner. If no central runner exists,
document the direct command in the implementation PR test log.

---

## Seed Data

No application seed data is needed. Tests should create temporary stub command
fixtures for `git`, `gh`, and tracker output under a test temp directory and
remove them at test exit.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      — require ground-truth completion verification before item terminal
      reports.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      — require batch summaries to quote or link item self-check evidence.
- [ ] `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`
      — clarify the relationship between readiness labels and report evidence.
- [ ] `REVIEW.md` — add reviewer checks for the completion self-check
      requirement and final-report examples.
- [ ] `.claude/agents/item-orchestrator.md`,
      `.cursor/agents/item-orchestrator.md`, and
      `.codex/skills/workflow-item-orchestrator/SKILL.md` — mirror the item
      runner reporting requirement.
- [ ] `.claude/agents/orchestrator.md`,
      `.cursor/agents/orchestrator.md`, and
      `.codex/skills/workflow-orchestrator/SKILL.md` — mirror the batch summary
      evidence requirement.
- [ ] `.agents/skills/run-item/SKILL.md`,
      `.agents/skills/run-items/SKILL.md`, and
      `.agents/skills/run-items/agents/openai.yaml` — mirror the command alias
      requirements.
- [ ] `scripts/development-workflow/README.md` — document the new helper if the
      script is added.
- [ ] `CHANGELOG.md` — implementation PR only; plan PR must not modify it.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The helper duplicates existing Protocol 91 Step 8c logic and drifts over time. | Medium | Medium | Keep Step 8c as the readiness gate and make the helper a report-evidence wrapper that reuses the same queries and names Step 8c as authoritative for PR readiness. |
| The output becomes too verbose for batch summaries. | Medium | Medium | Print a compact Markdown table with raw/verbatim evidence snippets and allow the batch summary to quote the result plus key observed values. |
| A provider outage blocks harmless handoff states. | Medium | Medium | Distinguish `unavailable` from `discrepancy`; block only surfaces required for the claimed state and report the exact unavailable reason. |
| Mirrored agent/skill guidance becomes inconsistent. | Medium | High | Update Claude, Cursor, and Codex item-orchestrator and orchestrator files in the same PR, and add review checks in `REVIEW.md`. |
| Changed-file scope checking becomes parser-heavy. | Low | Medium | Start with structured `gh pr view --json files`; if implementation adds pattern parsing, add parser-risk tests before opening the PR. |

---

## Code Samples

No production code sample is prescribed. The helper interface below is
illustrative; the implementation may adjust option names if usage text, tests,
and protocol references stay consistent:

```bash
# Illustrative — adapt during implementation.
scripts/development-workflow/item-completion-self-check.sh \
  --issue 1202 \
  --stage plan \
  --branch implementation-plan/1202-mandatory-ground-truth-completion-verification \
  --worktree-path "$PWD" \
  --pr 1234 \
  --expected-base develop \
  --claim "external_runtime:not_applicable:documentation-only workflow item"
```

---

## Implementation Order

1. Create `scripts/development-workflow/item-completion-self-check.sh` with
   validated arguments, structured Markdown output, explicit status values, and
   non-zero exit behavior for discrepancies.
2. Add shell tests in
   `scripts/development-workflow/tests/test-item-completion-self-check.sh` with
   stubbed `git`, `gh`, GraphQL, and tracker reads for verified,
   not-applicable, unavailable, and discrepancy outcomes.
3. Update Protocol 91 so Work Item Runner terminal reports call for the
   self-check evidence after Step 8c and before Step 6 final notification, and
   so discrepancy results route back to the existing gate that owns the failed
   surface.
4. Update Protocol 90 so batch summaries require each item's self-check evidence
   and still run the existing Step 5.1 direct artifact queries before declaring
   items terminal.
5. Update Protocol 92 to clarify that readiness labels remain automation-clean
   signals and the self-check is the evidence required before reporting that
   signal as current ground truth.
6. Update `.claude/agents/item-orchestrator.md`,
   `.cursor/agents/item-orchestrator.md`, and
   `.codex/skills/workflow-item-orchestrator/SKILL.md` with the exact final
   report requirement.
7. Update `.claude/agents/orchestrator.md`,
   `.cursor/agents/orchestrator.md`, and
   `.codex/skills/workflow-orchestrator/SKILL.md` with the batch summary
   evidence requirement.
8. Review the remaining files listed in the cross-cutting section. Update only
   paths whose final-report behavior can bypass Protocol 90 or 91, and record
   unchanged reviewed paths in the implementation PR description.
9. Update `REVIEW.md` so plan/code/documentation reviewers check for the new
   self-check requirement across protocols, mirrored agents/skills, and tests.
10. Update `scripts/development-workflow/README.md` with the helper purpose and
    direct test command if the helper is added.
11. Add or update the smoke runbook at
    `docs/testing/workflow/1202-mandatory-ground-truth-completion-verification.smoke-test.md`
    so it covers all acceptance criteria, including the mismatch/discrepancy
    case.
12. Run `bash scripts/development-workflow/tests/test-item-completion-self-check.sh`
    and any central workflow shell test runner that includes
    `scripts/development-workflow/tests/`.
13. Run `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
    because the implementation adds or modifies workflow shell code.
14. Run markdown lint on the changed workflow docs and smoke runbook.
15. Update `CHANGELOG.md` under `[Unreleased]` in the implementation PR only,
    using this literal entry:
    `- **Mandatory ground-truth completion verification** (#1202): Require Work Item Runner completion reports to include live branch, worktree, PR, review, CI, tracker, and discrepancy evidence before claiming terminal status.`

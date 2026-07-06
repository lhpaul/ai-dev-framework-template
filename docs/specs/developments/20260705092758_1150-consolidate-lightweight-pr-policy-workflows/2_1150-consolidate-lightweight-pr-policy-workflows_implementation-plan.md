# Consolidate Lightweight PR Policy Workflows - Implementation Plan

**Spec**: [1_1150-consolidate-lightweight-pr-policy-workflows_specs.md](1_1150-consolidate-lightweight-pr-policy-workflows_specs.md)
**Smoke test runbook**: [1150-consolidate-lightweight-pr-policy-workflows.smoke-test.md](../../../testing/workflow/1150-consolidate-lightweight-pr-policy-workflows.smoke-test.md)

---

## Summary

**Approach**: Consolidate the three lightweight PR policy workflows into one
API-only PR policy workflow that handles PR events and reviewer-loop summary
comments from a single job. Preserve the current label lifecycle, reviewer-loop
summary readiness contract, PR-number-scoped status context, fork safety, and
minimal permissions, then update the static checks and docs to describe the new
single-workflow shape.

**Estimated complexity**: M

**Rationale**: The change touches GitHub Actions security boundaries, event
matrix behavior, label mutation, commit statuses, tests, and docs. The code is
small, but correctness depends on preserving several existing workflow
contracts while removing redundant short-job fan-out.

**Dependencies**: None. The approved spec from PR #1151 is merged into
`develop`; no other feature must merge first.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `04cec05` |
| Template repository mode | `sed -n '1,220p' .ai-dev-workflow.yaml` | `template.is_template: true`; this item is generic workflow tooling, so the template-fit check passes. |
| Target workflow inventory | `find .github/workflows -maxdepth 1 -type f \| sort \| rg 'apply-regression-label\|remove-regression-label-on-push\|reviewer-loop-guard'` | Three target workflows exist: `apply-regression-label.yml`, `remove-regression-label-on-push.yml`, and `reviewer-loop-guard.yml`. |
| Policy-surface references | `rg -n "apply-regression-label\|remove-regression-label-on-push\|reviewer-loop-guard\|ready-for-regression\|Reviewer-loop completion guard\|Automated Reviewer Loop Summary" .github/workflows scripts/development-workflow/tests docs/workflow/development-workflow/integrations docs/workflow/development-workflow/README.md` | References exist in the three workflows, `test-reviewer-loop-guard-workflow.sh`, `ci-enforcement.md`, `e2e-regression.md`, `README.md`, and related reviewer/risk tests. |
| Existing workflow static test | `sed -n '1,260p' scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh` | One focused static test currently validates reviewer-loop guard behavior only. |
| Workflow test inventory | `find scripts/development-workflow/tests -maxdepth 1 -type f \| sort \| rg 'reviewer-loop-guard\|regression\|workflow'` | Existing adjacent tests include `test-reviewer-loop-guard-workflow.sh`, `test-placeholder-workflows-opt-in.sh`, and reviewer/risk shell tests. |
| CI enforcement docs | `sed -n '1,220p' docs/workflow/development-workflow/integrations/ci-enforcement.md` | Documentation currently describes two enforcement workflows plus the existing remove-on-push workflow. |
| Regression docs | `sed -n '1,180p' docs/workflow/development-workflow/integrations/e2e-regression.md` | Documentation already explains the `ready-for-regression` lifecycle and should be updated only where workflow ownership changes. |

---

## Layer-by-Layer Changes

### Database / Data Layer

- [ ] No database, migration, or seed-data changes.

### Backend / API

- [ ] No application backend or API changes.

### Shared Packages / Libraries

- [ ] No shared package changes.

### Frontend / UI

- [ ] No frontend changes.

### Infrastructure / Configuration

- [ ] Replace the three lightweight PR policy workflow files with one
      consolidated workflow:
  - `.github/workflows/apply-regression-label.yml`
  - `.github/workflows/remove-regression-label-on-push.yml`
  - `.github/workflows/reviewer-loop-guard.yml`
  - new consolidated file, recommended name:
    `.github/workflows/pr-policy.yml`
- [ ] Configure the consolidated workflow with these triggers:
  - `pull_request_target` for `opened`, `reopened`, `ready_for_review`, and
    `synchronize`.
  - `issue_comment` for `created` and `edited`.
- [ ] Keep the workflow API-only. Do not add `actions/checkout`, do not execute
      PR head code, and do not read files from an untrusted fork head.
- [ ] Use one job that routes by event type:
  - Same-repository implementation PR on `opened`, `reopened`, or
    `ready_for_review`: ensure the `ready-for-regression` label exists and is
    applied, then evaluate reviewer-loop summary status.
  - Same-repository implementation PR on `synchronize`: evaluate whether
    `ready-for-regression` is stale. Remove it only when the label is present
    and no canonical reviewer-loop summary exists. Then evaluate reviewer-loop
    summary status.
  - Non-implementation PR: skip implementation label behavior and post the
    reviewer-loop guard success status with the existing "not an implementation
    branch" meaning.
  - Fork PR: skip privileged label/status mutation and report the safe skip.
  - Summary `issue_comment`: validate the canonical summary markers, fetch
    current PR metadata and comments, and post the PR-scoped success status for
    the current head SHA.
  - Non-summary `issue_comment`: exit successfully without changing status or
    labels.
- [ ] Preserve the existing per-PR workflow concurrency behavior in the
      consolidated workflow. The current split workflows use
      `cancel-in-progress: true` groups scoped to the PR number, with the
      reviewer-loop guard additionally separating summary-comment,
      non-summary-comment, and PR-event executions.
- [ ] Preserve the current branch-prefix configuration:
      `IN_SCOPE_PREFIXES: "feature/ fix/ refactor/ hotfix/"`.
- [ ] Preserve the current reviewer-loop summary marker contract:
  - `### Automated Reviewer Loop Summary`
  - `*Posted automatically by \`pr-review-loop.sh\`.*`
- [ ] Preserve the current status context string:
      `Reviewer-loop completion guard (#${PR_NUMBER})`.
- [ ] Preserve retry-oriented failure descriptions for metadata, head SHA,
      branch, head repository, and comments API failures.
- [ ] Keep workflow permissions minimal for the combined behavior:
  - `issues: read` to read PR comments.
  - `pull-requests: write` to read PR metadata and apply/remove PR labels.
  - `statuses: write` to post the reviewer-loop guard commit status.
- [ ] Document the consolidation recommendation in the implementation PR
      summary and `ci-enforcement.md`: consolidation is worthwhile because
      same-repository implementation PR events currently fan out into two short
      policy workflows on common PR events, while one API-only workflow can
      preserve the same guarantees with fewer one-minute jobs.

---

## Testing Strategy

**Test types**: Static workflow tests, shell test harness, markdown lint, smoke
runbook.

**Key scenarios to test**:

1. Consolidated workflow has the full trigger matrix: PR open, reopen,
   ready-for-review, synchronize, and reviewer-loop summary comments (AC11).
2. Same-repository implementation PRs still apply `ready-for-regression` on
   open/reopen/ready-for-review and preserve implementation-only scope (AC5,
   AC6).
3. Same-repository implementation PRs remove stale `ready-for-regression` on
   synchronize only when no canonical reviewer-loop summary exists (AC5, AC12).
4. Reviewer-loop readiness still requires both canonical summary markers (AC7).
5. The status context remains PR-number-scoped and prevents shared-SHA status
   collisions (AC8).
6. Fork PRs skip privileged label/status mutation and do not check out
   untrusted code (AC9, AC10, AC12).
7. The final docs mention the consolidated workflow name and no longer present
   the split workflow shape as current behavior (AC1, AC2, AC4, AC13).

**Smoke test runbook**:
`docs/testing/workflow/1150-consolidate-lightweight-pr-policy-workflows.smoke-test.md`

**Regression suite**: Update `scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh`
to validate the consolidated `pr-policy.yml` workflow. Keep the test name unless
renaming it is worth the extra churn; the test should cover both reviewer-loop
guard behavior and regression-label behavior after consolidation.

### Parser-risk addendum

Parser-risk classification: not applicable. The implementation modifies a
GitHub Actions workflow and static literal shell checks. It does not add a
custom parser, linter, scanner, regex engine, suppression syntax, or
free-form text parser.

### Concurrent-event-source addendum

Concurrent-event-source classification: not applicable. GitHub Actions events
start separate workflow jobs, and concurrency is handled by the workflow
`concurrency` group. The implementation does not introduce shared in-process
mutable state, listeners, timers, sockets, or async queues.

---

## Seed Data

No application seed data is required.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Static workflow fixture | Committed GitHub Actions workflow text and static shell assertions | `.github/workflows/pr-policy.yml`, `scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh` |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/ci-enforcement.md` -
      replace the split-workflow description with the consolidated PR policy
      workflow, including event routing, status context, permissions, fork
      behavior, and branch-protection guidance.
- [ ] `docs/workflow/development-workflow/integrations/e2e-regression.md` -
      update wording that describes how the `ready-for-regression` label is
      applied/maintained so it names the consolidated PR policy workflow where
      relevant.
- [ ] `docs/workflow/development-workflow/README.md` - update any high-level
      integration index or workflow-reference text if it names the old split
      workflows.
- [ ] `docs/workflow/development-workflow/integrations/actions-cost-audit.md` -
      add a short cross-reference from the cost-audit guidance to this
      consolidation as an example of replacing redundant short-job fan-out.
- [ ] `AGENTS.md` - no update expected; this does not change command usage,
      branching conventions, or standing agent instructions.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Fork PR safety regresses under `pull_request_target` | Med | High | Keep the workflow API-only, do not checkout PR code, and skip mutation when `HEAD_REPO != REPO`. Static tests must assert no checkout and fork skip behavior. |
| Combined event routing drops one current behavior | Med | High | Preserve a trigger/behavior matrix in the workflow comments, static tests, docs, and smoke runbook. |
| Label removal fights the reviewer loop after readiness is established | Med | Med | Preserve the existing summary-comment check before removing `ready-for-regression` on synchronize. |
| PR-scoped status context accidentally becomes shared-SHA-scoped | Low | High | Keep `Reviewer-loop completion guard (#${PR_NUMBER})` and test for the exact context string. |
| Permissions become broader than needed | Low | Med | Document each permission and add static tests for declared permissions. |
| Documentation still references removed workflow files | Med | Low | Include doc grep checks in the smoke runbook and implementation validation. |

---

## Code Samples

No production code samples are included in this plan.

---

## Implementation Order

1. Create `.github/workflows/pr-policy.yml`.
   - Start from the current behavior in the three split workflows.
   - Use `pull_request_target` and `issue_comment` triggers listed in this plan.
   - Add comments documenting the event routing matrix and fork safety contract.
   - Add a per-PR `concurrency` group that keeps the existing
     `cancel-in-progress: true` behavior and avoids canceling summary-comment
     evaluation with unrelated non-summary comments.
   - Keep the job API-only and avoid `actions/checkout`.
2. Port the reviewer-loop guard behavior into the consolidated workflow.
   - Preserve summary marker checks, PR metadata fetches, comment fetches,
     PR-number-scoped status context, retry-oriented failure statuses, and
     non-summary comment skips.
3. Port the regression-label apply/remove behavior into the consolidated
   workflow.
   - Preserve same-repository gating, branch-prefix scoping, label creation,
     label application on open/reopen/ready-for-review, and stale-label removal
     on synchronize only when no reviewer-loop summary exists.
4. Delete the three replaced workflows:
   - `.github/workflows/apply-regression-label.yml`
   - `.github/workflows/remove-regression-label-on-push.yml`
   - `.github/workflows/reviewer-loop-guard.yml`
5. Update `scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh`.
   - Point the test at `.github/workflows/pr-policy.yml`.
   - Keep existing reviewer-loop guard assertions.
   - Add assertions for label apply behavior, stale label removal behavior,
     trigger matrix, fork skip behavior, permissions, status context, and
     absence of checkout.
6. Update documentation listed in **Documentation Updates**.
   - Include the documented recommendation to consolidate.
   - Replace old workflow names with `pr-policy.yml` where they describe current
     behavior.
   - Keep references to removed workflow names only when explicitly describing
     historical replacement context.
7. Update the smoke runbook if final workflow file names or validation commands
   differ from this plan.
8. Update `CHANGELOG.md` under `[Unreleased]` / `Changed` with this literal
   entry:
   `- **Consolidate PR policy workflows** (#1150): Replace redundant lightweight PR policy workflow fan-out with one API-only PR policy workflow while preserving reviewer-loop and regression-readiness guarantees.`
9. Run focused validation:
   - `bash scripts/development-workflow/tests/test-reviewer-loop-guard-workflow.sh`
   - `npx markdownlint-cli2 "docs/specs/developments/20260705092758_1150-consolidate-lightweight-pr-policy-workflows/2_1150-consolidate-lightweight-pr-policy-workflows_implementation-plan.md" "docs/testing/workflow/1150-consolidate-lightweight-pr-policy-workflows.smoke-test.md"`
   - `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`
   - `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
10. Before opening the implementation PR, manually inspect the final diff and
    confirm no workflow checks out PR head code from `pull_request_target`.

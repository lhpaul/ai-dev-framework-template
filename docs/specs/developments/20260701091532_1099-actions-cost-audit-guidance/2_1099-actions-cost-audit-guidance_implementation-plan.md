# Actions Cost-Audit Guidance - Implementation Plan

**Spec**: [1_1099-actions-cost-audit-guidance_specs.md](1_1099-actions-cost-audit-guidance_specs.md)
**Smoke test runbook**: [1099-actions-cost-audit-guidance.smoke-test.md](../../../testing/workflow/1099-actions-cost-audit-guidance.smoke-test.md)

---

## Summary

**Approach**: Add a small repository-level GitHub Actions audit helper that reads
recent workflow runs with `gh run list`, aggregates run count and wall-time
signals by workflow, and prints a markdown summary suitable for retrospectives
and template-sync reviews. Pair it with integration documentation, focused
mocked shell tests, and a smoke runbook that validates the output structure and
cost-risk framing.

**Estimated complexity**: S

**Rationale**: The implementation is limited to one shell helper, one focused
test harness, and documentation. The main risk is robustly handling incomplete
GitHub CLI data and date fields without presenting approximate wall time as
billing-accurate cost.

**Dependencies**: None. Issue #1098 reduced placeholder workflow fan-out, but
this guidance can be implemented independently.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `be484a0` |
| Template repository mode | `sed -n '1,220p' .ai-dev-workflow.yaml` | `template.is_template: true`; item is generic workflow tooling, so the template-fit check passes. |
| Existing cost-audit files | `find scripts/development-workflow scripts/development-workflow/tests docs/workflow/development-workflow/integrations -maxdepth 1 -type f \| rg 'actions-cost\|cost-audit\|cost'` | No existing cost-audit helper, test, or integration doc found. |
| GitHub CLI run fields | `gh run list --help \| sed -n '/--json/,/Options inherited/p'` | `gh run list` supports `workflowName`, `databaseId`, `createdAt`, `startedAt`, `updatedAt`, `status`, `conclusion`, `event`, and `headBranch`. |
| Live run data shape | `gh run list --limit 3 --json databaseId,workflowName,status,conclusion,createdAt,updatedAt,event,headBranch` | Recent runs returned the required workflow names, IDs, timestamps, events, and statuses. |
| Workflow script inventory | `find scripts/development-workflow -maxdepth 1 -type f \| sort` | New helper belongs under `scripts/development-workflow/`; new focused test belongs under `scripts/development-workflow/tests/`. |
| Related cost guidance | `rg -n "runner minutes\|workflow runs\|billing\|gh run\|retrospective\|template-sync" docs/workflow docs/testing scripts CHANGELOG.md` | Existing docs mention placeholder regression minutes, PR-Agent Actions cost, and retrospective/template-sync contexts, but no reusable audit output format. |
| Shell test pattern | `sed -n '1,260p' scripts/development-workflow/tests/test-placeholder-workflows-opt-in.sh` | Existing focused workflow tests use portable Bash assertions over committed scripts/docs. |
| Integration docs inventory | `find docs/workflow/development-workflow/integrations -maxdepth 1 -type f \| sort` | New documentation should be added as `docs/workflow/development-workflow/integrations/actions-cost-audit.md`. |

---

## Layer-by-Layer Changes

### Database / Data Layer

- [ ] No database or seed-data changes.

### Backend / API

- [ ] Add `scripts/development-workflow/actions-cost-audit.sh`.
- [ ] The helper reads recent workflow runs through `gh run list --json` using
      normal repository workflow-run visibility.
- [ ] Support these options:
  - `--limit <n>`: number of recent runs to inspect, defaulting to a conservative
    value such as `100`.
  - `--repo <owner/repo>`: optional repository override passed through to `gh`.
  - `--since <iso-date>`: optional inclusive cutoff for `createdAt`; when
    omitted, the helper reports the most recent `--limit` runs.
  - `--format markdown`: initial and default output format.
- [ ] Aggregate by `workflowName`, using a stable fallback such as
      `workflow:<workflowDatabaseId>` or `unknown-workflow` when the name is
      absent.
- [ ] Compute wall time from `startedAt` when available, otherwise `createdAt`,
      through `updatedAt`. Mark runs with missing or unparseable timestamps as
      incomplete instead of including them in duration totals.
- [ ] Print a compact markdown report with:
  - audit scope and data-limit notes;
  - workflow summary table with run count, completed count, incomplete count,
    total wall time, average wall time, dominant events, and recent run IDs;
  - public/private cost-risk framing;
  - recommendation worksheet using the outcomes `keep`, `narrow`,
    `make opt-in`, `replace`, `disable`, and `investigate`;
  - high-signal keep guidance for CI checks, reviewer gates, release gates, real
    regression workflows, and real deploy workflows.
- [ ] Fail clearly when `gh` or `jq` is unavailable, or when `gh run list`
      returns a permission/authentication failure.
- [ ] Treat an empty run list as a successful audit with a visible "no data"
      limitation, not as a shell failure.

### Shared Packages / Libraries

- [ ] No shared package changes.

### Frontend / UI

- [ ] No frontend changes.

### Infrastructure / Configuration

- [ ] No GitHub workflow trigger or repository setting changes.
- [ ] Do not add billing API dependencies, organization-level permissions, or
      automatic workflow mutations.

---

## Testing Strategy

**Test types**: Unit-style shell tests, static documentation validation, smoke
runbook.

**Key scenarios to test**:

1. Successful markdown output groups run count and wall time by workflow (AC1,
   AC2, AC7).
2. Missing timestamps or incomplete runs are visible as data limitations and do
   not corrupt duration totals (AC3).
3. `gh` permission/authentication failure exits non-zero with an actionable
   error (AC3).
4. Empty run history prints a usable "no workflow run data" report (AC3, AC7).
5. Public/private cost-risk language appears in the generated report and
   explains that public-template results are not proof of private downstream
   cost safety (AC4, AC8).
6. The recommendation worksheet includes `keep`, `narrow`, `make opt-in`,
   `replace`, `disable`, and `investigate` (AC5, AC6, AC7, AC8).

**Smoke test runbook**:
`docs/testing/workflow/1099-actions-cost-audit-guidance.smoke-test.md`

**Regression suite**: Add `scripts/development-workflow/tests/test-actions-cost-audit.sh`
with a mocked `gh` command and deterministic JSON fixtures embedded in the test
or written to a temporary directory. The test should run without live GitHub
network access by default.

### Parser-risk addendum

Parser-risk classification: not applicable. The helper consumes structured JSON
from `gh run list` with `jq`; it does not add a custom parser, linter, scanner,
regex engine, suppression syntax, or free-form markdown/code/log scanner.

### Concurrent-event-source addendum

Concurrent-event-source classification: not applicable. The helper is a
single-process command with no event listeners, timers, sockets, or shared
mutable state across asynchronous contexts.

---

## Seed Data

No application seed data is required.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Mock workflow run JSON | Multiple workflows, incomplete timestamps, empty list, and permission failure | `scripts/development-workflow/tests/test-actions-cost-audit.sh` temporary fixtures |

---

## Documentation Updates

- [ ] `scripts/development-workflow/README.md` - add usage and purpose for
      `actions-cost-audit.sh`.
- [ ] `docs/workflow/development-workflow/integrations/actions-cost-audit.md` -
      add the cost-audit runbook, output interpretation guidance, public/private
      cost-risk framing, and recommendation vocabulary.
- [ ] `docs/workflow/development-workflow/integrations/e2e-regression.md` -
      link the cost-audit guidance where placeholder regression cost is
      discussed.
- [ ] `docs/workflow/development-workflow/integrations/pr-agent.md` - link the
      cost-audit guidance from the PR-Agent cost discussion.
- [ ] `docs/workflow/development-workflow/README.md` - add the new integration
      guide to the Protocol And Integration Index.
- [ ] `AGENTS.md` - no update expected; this does not change agent commands,
      project structure, or standing conventions.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Wall time is mistaken for exact billable minutes | Med | Med | Label the metric as wall time, document that exact billing requires GitHub billing or organization metrics, and avoid dollar estimates. |
| Missing timestamps or partial permissions create misleading totals | Med | Med | Track incomplete runs separately and print data-limit notes in the report. |
| Date parsing behaves differently across macOS and Linux | Med | Low | Use `jq` date parsing for ISO timestamps rather than platform-specific `date` flags. |
| Recommendation heuristics appear too authoritative | Low | Med | Present outcomes as a worksheet and decision guide; avoid automatic destructive recommendations. |
| Shell portability or quoting bugs | Low | Med | Use strict Bash, focused mocked tests, ShellCheck, and workflow shell guard. |

---

## Code Samples

No production code samples are included in this plan.

---

## Implementation Order

1. Create `scripts/development-workflow/actions-cost-audit.sh`.
   - Implement strict argument parsing for `--limit`, `--repo`, `--since`, and
     `--format markdown`.
   - Validate required local commands (`gh`, `jq`) before invoking GitHub.
   - Use `gh run list --json databaseId,workflowName,workflowDatabaseId,status,conclusion,createdAt,startedAt,updatedAt,event,headBranch,url`.
   - Ensure `gh` failures print a clear error and exit non-zero.
2. Implement aggregation and markdown rendering.
   - Group by workflow name/fallback ID.
   - Compute completed and incomplete run counts.
   - Compute total and average wall-time minutes only from runs with valid start
     and end timestamps.
   - Include recent run IDs/URLs and dominant events as context.
   - Include the public/private cost-risk note and recommendation worksheet.
3. Add `scripts/development-workflow/tests/test-actions-cost-audit.sh`.
   - Mock `gh` through `PATH` using temporary scripts.
   - Cover successful aggregation, incomplete timestamp handling, empty data,
     permission/auth failure, recommendation outcomes, and public/private
     framing.
4. Update documentation listed in **Documentation Updates**.
   - Keep the new integration guide focused on repository-level workflow-run
     visibility, not billing-admin dashboards.
   - Include example commands:
     `./scripts/development-workflow/actions-cost-audit.sh --limit 100` and
     `./scripts/development-workflow/actions-cost-audit.sh --repo owner/repo --since 2026-07-01T00:00:00Z`.
5. Update the smoke runbook during implementation if the final command options
   or output headings differ from this plan.
6. Update `CHANGELOG.md` under `[Unreleased]` / `Added` with this literal entry:
   `- **Actions cost-audit guidance** (#1099): Add lightweight workflow run-volume and wall-time audit guidance for retrospectives and downstream template-sync reviews.`
7. Run focused validation:
   - `bash scripts/development-workflow/tests/test-actions-cost-audit.sh`
   - `shellcheck --severity=warning scripts/development-workflow/actions-cost-audit.sh scripts/development-workflow/tests/test-actions-cost-audit.sh`
   - `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
   - `npx markdownlint-cli2 "scripts/development-workflow/README.md" "docs/workflow/development-workflow/README.md" "docs/workflow/development-workflow/integrations/actions-cost-audit.md" "docs/workflow/development-workflow/integrations/e2e-regression.md" "docs/workflow/development-workflow/integrations/pr-agent.md" "docs/testing/workflow/1099-actions-cost-audit-guidance.smoke-test.md" "CHANGELOG.md"`
   - `find docs/specs/developments docs/testing/workflow -name "*.md" -print0 | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md`
   - `git diff --check`
8. Run a live non-mutating smoke check when authenticated `gh` is available:
   `./scripts/development-workflow/actions-cost-audit.sh --limit 10`.
   Confirm the output groups workflows, includes cost-risk framing, and reports
   any data limitations without exposing secrets.

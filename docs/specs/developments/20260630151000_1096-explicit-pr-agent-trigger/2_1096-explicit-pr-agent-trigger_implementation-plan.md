# Implementation Plan: Explicit PR-Agent Trigger Model

**Spec**: `docs/specs/developments/20260630151000_1096-explicit-pr-agent-trigger/1_1096-explicit-pr-agent-trigger_specs.md`
**Smoke test runbook**: `docs/testing/workflow/1096-explicit-pr-agent-trigger.smoke-test.md`
**Issue**: #1096
**Complexity**: Medium
**Branch type**: `feature/1096-explicit-pr-agent-trigger`

---

## Step 0: Template-Fit Check

This repository has `template.is_template: true`. The feature changes workflow
tooling that the template ships (`.github/workflows/pr-agent.yml`,
`pr-review-loop.sh`, tests, and integration docs). It is framework-agnostic and
applies to downstream repositories regardless of application stack. Fit check
**passes**.

---

## Summary

Change PR-Agent from broad automatic fan-out to an explicit trigger model. The
workflow should no longer run on every pull request synchronize event and should
only react to issue comments that are exact PR-Agent commands. The reviewer loop
will explicitly request PR-Agent when `pr-agent` is configured, then keep the
existing deterministic polling and classification behavior.

**Estimated complexity**: M

**Rationale**: The observable behavior spans GitHub Actions triggers, shell
review-loop orchestration, tests with mocked GitHub calls, and integration docs.
No broad architecture change is required, but the trigger/polling contract must
be precise to avoid silently skipping a configured reviewer.

**Dependencies**: Spec PR #1100 is merged to `develop-actions-cost-reduction`.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `d414403` |
| Current PR-Agent workflow triggers | `sed -n '1,80p' .github/workflows/pr-agent.yml` | Workflow currently uses `pull_request` types `opened`, `reopened`, `ready_for_review`, `synchronize` and all created `issue_comment` events on PRs. |
| Reviewer-loop PR-Agent adapter | `sed -n '2560,2960p' scripts/development-workflow/pr-review-loop.sh` | `run_pr_agent_review` currently polls for PR-Agent comments but does not explicitly trigger PR-Agent. |
| Review config source | `sed -n '1,120p' .ai-dev-workflow.yaml` | `review.on_draft.github` includes `pr-agent`, so reviewer-loop semantics must be preserved. |
| Existing reviewer-loop tests | `find scripts/development-workflow/tests -maxdepth 1 -type f \| sort` | `test-pr-review-loop.sh` is the existing shell harness for reviewer-loop platform behavior. |
| PR-Agent docs references | `find docs/workflow/development-workflow/integrations -maxdepth 1 -type f \| sort \| xargs rg -n "pr-agent\|PR-Agent"` | `integrations/pr-agent.md` is the canonical PR-Agent integration doc; adjacent integration docs mention PR-Agent only as configuration examples. |

---

## Layer-by-Layer Changes

### GitHub Actions Workflow

- [ ] Update `.github/workflows/pr-agent.yml` so `pull_request` no longer
      includes `synchronize`.
- [ ] Keep only low-volume pull request lifecycle triggers that are useful by
      default, such as `opened`, `reopened`, and `ready_for_review`.
- [ ] Narrow `issue_comment` execution with a job-level condition requiring all
      of the following:
      - the comment is on a pull request;
      - the sender is not a bot;
      - the comment body is an exact supported PR-Agent command for review, with
        `/review` as the canonical command unless implementation-time PR-Agent
        compatibility requires a different exact command.
- [ ] Keep existing fork protection and token/model environment behavior.
- [ ] Add comments in the workflow explaining that review-loop-triggered
      PR-Agent runs happen through the explicit command path, not through
      synchronize fan-out.

### Reviewer Loop

- [ ] Update `scripts/development-workflow/pr-review-loop.sh` in
      `run_pr_agent_review` so the PR-Agent adapter explicitly triggers a run
      when no current-head PR-Agent comment exists.
- [ ] Implement the trigger as a PR issue comment using the supported command
      from the workflow condition. The command should be exact and stable,
      defaulting to `/review`.
- [ ] Add an override environment variable such as `PR_AGENT_TRIGGER_COMMENT`
      only if it is needed for downstream compatibility; if added, document the
      default and keep the workflow condition in sync.
- [ ] After posting the trigger, keep the existing polling behavior: scope to
      the current head SHA, classify clean/advisory/blocking comments, and return
      `skipped` or `escalate` states deterministically when no review appears.
- [ ] If the trigger comment cannot be posted, return `RESULT=skipped` or
      `RESULT=escalate` with a concrete reason rather than silently reporting
      clean. Use `skipped` only when absence is explicitly tolerable under the
      existing reviewer-loop policy; otherwise use `escalate`.
- [ ] Preserve the existing behavior that an already-present PR-Agent comment for
      the current head is reused instead of posting a duplicate trigger.

### Tests

- [ ] Extend `scripts/development-workflow/tests/test-pr-review-loop.sh` with
      mocked `gh` calls covering the PR-Agent trigger path:
      - no matching current-head comment exists, so the adapter posts the trigger
        comment before polling;
      - a matching current-head comment already exists, so the adapter does not
        post a duplicate trigger;
      - trigger comment post failure returns a deterministic non-clean state;
      - the workflow condition remains constrained to explicit commands and does
        not treat arbitrary human comments as triggers.
- [ ] Add simple assertions in the same harness, or a focused shell test if the
      harness becomes too coupled, that `.github/workflows/pr-agent.yml` no
      longer includes `synchronize` and still includes the explicit comment
      command path.
- [ ] Keep tests network-free by using the existing mock `gh` command style.

### Documentation

- [ ] Update `docs/workflow/development-workflow/integrations/pr-agent.md` to
      describe the new default: no synchronize trigger and no arbitrary comment
      trigger.
- [ ] Document the explicit PR-Agent command that maintainers and
      `pr-review-loop.sh` use.
- [ ] Document migration impact for downstream repositories that relied on every
      push or any human comment to trigger PR-Agent.
- [ ] Update `docs/workflow/development-workflow/integrations/pr-review-platform.md`
      if it describes PR-Agent as automatically available rather than explicitly
      requested by the reviewer loop.
- [ ] Update `docs/workflow/development-workflow/README.md` only if the
      high-level review-loop description would otherwise imply automatic
      PR-Agent fan-out.

### Database / Data Layer

- [ ] Not applicable. No database or seed data changes.

### Frontend / UI

- [ ] Not applicable. This template feature has no application UI.

---

## Testing Strategy

**Test types**: Shell unit tests, markdown lint, smoke/manual verification.

**Key scenarios to test**:

1. PR synchronize does not trigger PR-Agent by default. Maps to AC 1.
2. Arbitrary human PR comments do not trigger PR-Agent. Maps to AC 2.
3. The exact explicit command triggers PR-Agent. Maps to AC 2 and AC 3.
4. `pr-review-loop.sh --platform pr-agent` posts the explicit command when no
   current-head PR-Agent comment exists. Maps to AC 4 and AC 5.
5. The reviewer loop reuses an existing current-head PR-Agent comment without
   duplicate triggers. Maps to AC 6.
6. Trigger post failure has a deterministic non-clean outcome. Maps to AC 6.
7. Docs describe downstream migration impact. Maps to AC 8.

**Smoke test runbook**:
`docs/testing/workflow/1096-explicit-pr-agent-trigger.smoke-test.md`

**Regression suite**:
Run:

```bash
bash scripts/development-workflow/tests/test-pr-review-loop.sh
npx markdownlint-cli2 \
  docs/specs/developments/20260630151000_1096-explicit-pr-agent-trigger/2_1096-explicit-pr-agent-trigger_implementation-plan.md \
  docs/testing/workflow/1096-explicit-pr-agent-trigger.smoke-test.md \
  docs/workflow/development-workflow/integrations/pr-agent.md
```

---

## Seed Data

No seed data is required.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/pr-agent.md` — document
      explicit triggers, reviewer-loop triggering, skipped/unavailable states,
      and downstream migration.
- [ ] `docs/workflow/development-workflow/integrations/pr-review-platform.md` —
      update only if its platform overview implies PR-Agent auto-runs without an
      explicit request.
- [ ] `docs/workflow/development-workflow/README.md` — update only if the
      top-level review-loop overview would otherwise be misleading.
- [ ] `docs/testing/workflow/1096-explicit-pr-agent-trigger.smoke-test.md` —
      add the smoke runbook for this feature.
- [ ] `CHANGELOG.md` — add an `[Unreleased]` entry using the project format:
      `- **Make PR-Agent explicit** (#1096): Reduce default PR-Agent Actions fan-out while preserving configured reviewer-loop review.`

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| The chosen explicit command is not recognized by PR-Agent | Medium | High | Verify the command against current PR-Agent behavior during implementation; keep the workflow condition and reviewer-loop trigger using the same command. |
| Reviewer loop reports clean without actually triggering configured PR-Agent | Low | High | Test no-comment and trigger-failure paths; non-postable trigger must produce a deterministic non-clean result. |
| Downstream repos relied on automatic synchronize review | Medium | Medium | Document the migration and opt-in path clearly in the PR-Agent integration guide. |
| The trigger comment creates duplicate PR-Agent runs | Medium | Low | Reuse existing current-head comments and add a test proving no duplicate trigger is posted when one exists. |

---

## Implementation Order

1. Update `.github/workflows/pr-agent.yml`:
   - remove `synchronize` from `pull_request.types`;
   - constrain `issue_comment` to exact explicit review commands;
   - keep fork and bot protections.
2. Update `scripts/development-workflow/pr-review-loop.sh`:
   - add a small helper inside or near `run_pr_agent_review` to post the explicit
     PR-Agent trigger comment;
   - call it only when no matching current-head PR-Agent comment already exists;
   - return a deterministic non-clean state if the trigger cannot be posted.
3. Extend `scripts/development-workflow/tests/test-pr-review-loop.sh` with the
   trigger, no-duplicate, trigger-failure, and workflow-trigger assertions.
4. Update `docs/workflow/development-workflow/integrations/pr-agent.md` and any
   affected overview docs listed in **Documentation Updates**.
5. Add or update `docs/testing/workflow/1096-explicit-pr-agent-trigger.smoke-test.md`
   so it covers all acceptance criteria.
6. Add the `CHANGELOG.md` entry under `[Unreleased]`:
   `- **Make PR-Agent explicit** (#1096): Reduce default PR-Agent Actions fan-out while preserving configured reviewer-loop review.`
7. Run local verification:
   - `bash scripts/development-workflow/tests/test-pr-review-loop.sh`
   - markdownlint on the changed docs
   - `git diff --check`
8. Open the implementation PR as `feature/1096-explicit-pr-agent-trigger`
   targeting `develop-actions-cost-reduction`.

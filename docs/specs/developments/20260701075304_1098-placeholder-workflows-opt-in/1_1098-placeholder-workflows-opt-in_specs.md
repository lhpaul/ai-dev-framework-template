# Placeholder Workflows Opt-In - Spec

**Epic**: #1095 Actions cost reduction

---

## Overview

Template maintainers need the repository's placeholder deploy and regression
workflows to remain useful scaffolding without causing downstream private
repositories to spend runner minutes before they have real project-specific
value. This feature makes placeholder workflow execution opt-in or explicitly
configured while preserving clear guidance for teams that are ready to enable
real deployment and regression pipelines.

The product outcome is a safer default template: downstream projects can sync
the workflows without unintentionally running placeholder deploy jobs on every
push or installing browser dependencies merely because an implementation pull
request receives `ready-for-regression`.

## Brief Objective List

Derived from issue #1098:

1. Placeholder deploy workflows do not run on every push by default unless a
   downstream project opts in or replaces the placeholder.
2. Placeholder regression workflows do not install Playwright or browser
   dependencies unless regression is intentionally enabled.
3. `ready-for-regression` label automation is reviewed so it does not
   accidentally trigger expensive placeholder work.
4. Documentation explains the recommended downstream activation path for real
   deploy and regression workflows.
5. Existing release and reviewer-loop protocols still document how real
   regression should be label-gated when configured.

## Use Cases

### Use Case 1: Downstream repository syncs the template before configuring deploys

**Actor**: Downstream maintainer.
**Preconditions**: A downstream project has synced the template workflows but has
not replaced the placeholder deploy workflow with project-specific deployment
logic.

**Steps**:

1. The maintainer pushes to the repository's integration or production branch.
2. The placeholder deploy workflow evaluates its activation rules.
3. Because the downstream project has not opted in or replaced the placeholder,
   the workflow does not run a placeholder deploy job by default.
4. The maintainer can read the template guidance to understand how to activate a
   real deployment workflow later.

**Postconditions**: The downstream repository does not spend runner time on a
placeholder deploy job that cannot deploy the project.

**Information shown**:

- The workflow file or documentation identifies the placeholder as inactive by
  default.
- The activation path for a real deployment workflow is documented.

**Actions available**:

- Keep the placeholder inactive.
- Opt in to the placeholder for validation.
- Replace the placeholder with a real deployment workflow.

### Use Case 2: Implementation PR receives `ready-for-regression`

**Actor**: Workflow operator or automated readiness workflow.
**Preconditions**: An implementation pull request receives the
`ready-for-regression` label, but the downstream project has not enabled real
regression tests.

**Steps**:

1. The label automation applies or preserves `ready-for-regression` according to
   the workflow readiness rules.
2. The placeholder regression workflow evaluates whether regression is enabled.
3. If regression is not explicitly enabled, the placeholder workflow does not
   install Playwright or browser dependencies.
4. The pull request remains compatible with projects that have real label-gated
   regression checks configured.

**Postconditions**: The readiness label does not accidentally trigger expensive
placeholder browser setup in projects that have not opted in to regression.

**Information shown**:

- The placeholder regression workflow or documentation explains why no expensive
  browser setup ran.
- The real regression activation path remains visible to maintainers.

**Actions available**:

- Leave placeholder regression inactive.
- Enable regression intentionally for a project.
- Replace the placeholder with the project's real regression suite.

### Use Case 3: Maintainer enables real deploy or regression workflows

**Actor**: Downstream maintainer.
**Preconditions**: A downstream project has real deployment or regression value
to validate.

**Steps**:

1. The maintainer reads the template guidance for activating real workflows.
2. The maintainer chooses an activation model appropriate for the project.
3. The maintainer updates the placeholder or replaces it with project-specific
   logic.
4. Regression remains tied to the existing readiness label model when configured.

**Postconditions**: Real deploy or regression workflows can run intentionally
without losing the staged workflow's readiness semantics.

**Information shown**:

- The recommended activation path for deploy and regression.
- The expected relationship between `ready-for-regression` and real regression
  checks.
- Guidance that high-signal release and regression gates should remain enabled
  when they provide project value.

**Actions available**:

- Enable a placeholder only as a temporary validation step.
- Replace placeholder jobs with real jobs.
- Keep real regression label-gated.

### Use Case 4: Workflow operator audits the template defaults

**Actor**: Template maintainer or workflow operator.
**Preconditions**: The maintainer is reviewing template workflows for Actions
cost risk.

**Steps**:

1. The maintainer inspects placeholder deploy and regression workflow defaults.
2. The maintainer verifies that expensive placeholder work is opt-in or
   explicitly configured.
3. The maintainer verifies that documentation still describes how real
   regression and deploy workflows should be enabled.

**Postconditions**: The template's default workflow behavior is understandable
and does not hide cost risks in placeholder jobs.

**Information shown**:

- Which placeholder workflows are inactive by default.
- Which operator action enables them.
- Which real workflow gates should stay active after replacement.

**Actions available**:

- Keep defaults inactive.
- Document a downstream activation.
- Replace placeholders with real project workflows.

## Business Rules

- Placeholder deploy jobs must not run on every push by default.
- Placeholder regression jobs must not install Playwright or browser dependencies
  merely because the `ready-for-regression` label is present.
- Real regression workflows, when configured, should remain compatible with the
  existing `ready-for-regression` label-gated readiness model.
- The template must make the difference between placeholder scaffolding and real
  project-specific workflows visible to downstream maintainers.
- Opt-in behavior must be explicit enough that a maintainer can tell what action
  enables placeholder or real workflow execution.
- Public-repository zero-billing assumptions must not be used as justification
  for defaults that are costly in private downstream repositories.

## Operational Visibility

- **Inactive placeholder state**: Maintainers can see that placeholder deploy or
  regression work is inactive until explicitly enabled or replaced.
- **Activation guidance**: Documentation identifies how downstream projects
  should enable real deploy and regression workflows.
- **Readiness relationship**: Guidance explains that the
  `ready-for-regression` label remains the intended trigger for real regression
  checks when a project has configured them.
- **Cost-risk framing**: Documentation explains why placeholder browser install
  and deploy jobs are disabled by default for private downstream repositories.

## Acceptance Criteria

- [ ] Placeholder deploy jobs do not run on every push by default unless a
      downstream project opts in or replaces the placeholder.
- [ ] Placeholder regression jobs do not install Playwright or browser
      dependencies unless regression is intentionally enabled.
- [ ] `ready-for-regression` label automation does not accidentally trigger
      expensive placeholder regression work when regression is not enabled.
- [ ] Documentation explains the recommended downstream activation path for real
      deploy workflows.
- [ ] Documentation explains the recommended downstream activation path for real
      regression workflows.
- [ ] Existing release and reviewer-loop protocol guidance still describes how
      real regression should be label-gated when configured.
- [ ] Tests or static validation cover default-inactive deploy behavior,
      default-inactive regression behavior, and the label-trigger relationship.

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| Placeholder deploy does not run on every push by default | Use Case 1, Business Rules | AC1 |
| Placeholder regression does not install browser dependencies unless enabled | Use Case 2, Business Rules | AC2 |
| `ready-for-regression` does not accidentally trigger placeholder cost | Use Case 2, Business Rules | AC3, AC7 |
| Documentation explains deploy activation | Use Case 3, Operational Visibility | AC4 |
| Documentation explains regression activation | Use Case 3, Operational Visibility | AC5 |
| Existing release and reviewer-loop protocols preserve real regression guidance | Use Case 3, Business Rules | AC6 |
| Maintainability and cost-risk visibility | Use Case 4, Operational Visibility | AC1, AC2, AC4, AC5, AC7 |

## Out of Scope

- Designing a real deployment pipeline for any downstream project.
- Designing a real end-to-end regression suite for any downstream project.
- Removing the `ready-for-regression` label model for projects that have real
  regression checks configured.
- Changing reviewer-loop, release, or merge authority rules beyond the
  placeholder workflow activation behavior and related guidance.
- Optimizing unrelated GitHub Actions workflows outside the placeholder deploy
  and regression surfaces.

## PR-Visible Deferral Notes

- **Real deployment implementation**: Deferred because each downstream project
  has different hosting, authentication, build, and approval requirements. The
  plan should preserve template guidance but not invent project-specific deploy
  logic.
- **Real regression suite implementation**: Deferred because each downstream
  project owns its test framework, fixtures, and browser/runtime requirements.
  The plan should preserve label-gated guidance for projects that opt in.
- **Billing telemetry**: Deferred to the separate cost-audit guidance item in
  this epic. This feature focuses on making placeholder workflow execution
  opt-in rather than measuring historical Actions usage.

# Playwright-Based Design Review — Spec

---

## Overview

This feature adds a design reviewer to the AI development workflow that uses browser automation to validate the visual and behavioral quality of frontend changes beyond what static code review can detect. When a pull request includes frontend files (HTML, CSS, JavaScript, or frontend framework components), the design reviewer launches a real browser, renders the affected pages or components, and reports on rendering correctness, accessibility compliance, and runtime errors. This gives teams automated confidence that UI changes look and behave as intended before human review.

---

## Use Cases

### Use Case 1: Automated Design Review Triggered on a PR with Frontend Changes

**Actor**: Work Item Runner (automated orchestration agent, acting on behalf of the developer)
**Preconditions**:
- A pull request exists that includes one or more frontend files (HTML, CSS, JavaScript, or frontend framework component files such as React, Vue, Svelte, etc.)
- Browser automation is available in the current environment (the configured provider is reachable)
- The development server or preview environment for the changed pages/components can be started or is already running

**Steps**:
1. The Work Item Runner reaches Step 7a (Internal Review Gate) while processing an implementation PR.
2. The runner inspects the PR's changed files and detects that at least one file is a frontend file.
3. The runner invokes the design-reviewer agent, passing context about the PR: the list of changed frontend files and any available preview URL or instructions to start the development server.
4. The design-reviewer agent launches the browser via the configured browser automation provider.
5. The agent navigates to each affected page or component preview URL.
6. For each page or component, the agent:
   a. Captures a screenshot.
   b. Checks the browser console for errors or warnings.
   c. Runs an automated accessibility check (WCAG compliance check) on the rendered output.
7. The agent compiles the findings into a structured review comment and posts it to the PR.
8. The runner reads the findings:
   - If blocking issues are found (console errors, critical accessibility violations), the runner treats the result as "needs revision."
   - If no blocking issues are found (screenshots captured, no console errors, no critical accessibility violations), the runner treats the result as "approved" and continues.

**Postconditions**: A structured design review comment is present on the PR. If the review revealed blocking issues, those issues must be addressed before the PR can advance to human review.

**Information shown** (in the PR review comment):
- Whether frontend changes were detected
- List of pages/components reviewed with a screenshot attached (or link to screenshot artifact)
- Console errors and warnings found during rendering (if any)
- Accessibility findings (violation count by severity level, with a brief description of each violation)
- Overall verdict: approved or needs revision

**Actions available**:
- Developer addresses flagged issues and pushes fixes; the runner re-triggers the design review.
- Developer reviews the screenshots and accessibility report in the PR comment.

**Considerations**:
- If the development server cannot be started or the preview URL is unreachable, the agent reports this as a configuration error and skips the review without blocking the PR.
- If the browser automation provider is unavailable in the current runner environment, the agent gracefully no-ops and posts a notice on the PR indicating that design review was skipped.
- Pages or components that require authentication or special setup should be noted as out of scope for this first iteration (see Out of Scope section).

---

### Use Case 2: Design Review Skipped — No Frontend Changes Detected

**Actor**: Work Item Runner
**Preconditions**:
- A pull request exists that does NOT include any frontend files (e.g., it is a backend-only change, a documentation update, or a workflow tooling change).

**Steps**:
1. The Work Item Runner reaches Step 7a and inspects the PR's changed files.
2. No frontend files are found in the changed file list.
3. The design-reviewer agent is not invoked; the runner continues without it.

**Postconditions**: No design review comment is posted. The PR proceeds normally through the internal review gate.

**Information shown**: Nothing specific to design review.

**Actions available**: None — the runner continues the normal review flow.

**Considerations**:
- The detection logic must be documented so downstream teams can understand which file extensions and paths are treated as "frontend."

---

### Use Case 3: Design Review Skipped — Browser Automation Unavailable

**Actor**: Work Item Runner
**Preconditions**:
- A pull request includes frontend files.
- The browser automation provider is unavailable (e.g., the configured provider is not installed, not reachable, or explicitly set to `none`).

**Steps**:
1. The Work Item Runner reaches Step 7a and detects frontend changes.
2. The runner checks whether the configured browser automation provider is reachable.
3. The provider is not reachable.
4. The design-reviewer agent posts a notice on the PR explaining that design review was skipped due to provider unavailability.
5. The runner continues without blocking the PR on design review.

**Postconditions**: A notice is posted to the PR. The PR is not blocked; normal review flow continues.

**Information shown** (in the PR notice comment):
- The name of the configured provider.
- The reason for skipping (provider unavailable).
- Guidance on how to enable design review (e.g., install the provider or update configuration).

**Actions available**:
- Operator installs and configures the browser automation provider to enable design review in future runs.

---

## Business Rules

- BR-1: The design-reviewer agent MUST be invoked during the Step 7a internal review gate only for implementation PRs (`feature/*`, `fix/*`, `refactor/*`, `hotfix/*`) that contain frontend file changes. It MUST NOT be invoked for spec or plan PRs.
- BR-2: Frontend file detection is determined by file extension and path. At minimum, the following are considered frontend files: `.html`, `.css`, `.scss`, `.sass`, `.less`, `.js`, `.jsx`, `.ts`, `.tsx`, `.vue`, `.svelte`. The list must be documented and extensible.
- BR-3: The design-reviewer agent MUST NOT block the PR if browser automation is unavailable. Unavailability results in a graceful skip with a notice comment, not a hard failure.
- BR-4: The design-reviewer agent MUST NOT block the PR if the development server or preview URL cannot be reached. Unreachable preview results in a skip with an error notice, not a hard failure.
- BR-5: When the design review runs successfully and finds blocking issues (console errors or critical accessibility violations), the result is treated as "needs revision" and the PR must not advance to `ready-for-human-review` until the issues are resolved or explicitly accepted.
- BR-6: The accessibility check must cover WCAG 2.1 Level AA as the baseline. Violations at the "critical" and "serious" levels are treated as blocking; "moderate" and "minor" violations are reported but non-blocking.
- BR-7: Screenshots captured during a design review must be attached to or linked from the PR review comment. The comment must be human-readable and structured (not raw JSON).
- BR-8: The design-reviewer agent uses the repository's configured `browser_automation.provider` from `.ai-dev-workflow.yaml`. For this repository the provider is `playwright_cli`. The agent must not hard-code a provider.
- BR-9: The design-reviewer result (approved / needs-revision / skipped) must be explicitly stated in the PR comment so the Work Item Runner can parse the verdict programmatically.
- BR-10: If the design review was skipped (either no frontend changes or provider unavailable), the Work Item Runner MUST continue the normal Step 7a flow without treating the skip as a failure.

---

## UX Rules

This feature has no user-facing UI of its own. Its "UX" is the structured PR comment and notice posted to GitHub.

- The design review PR comment must begin with a recognizable header (e.g., "Design Review Summary") so it can be identified programmatically.
- Screenshot images should be embedded directly in the comment when the image format supports it, or linked as artifacts when embedding is not possible.
- Accessibility findings must be grouped by severity level ("Critical", "Serious", "Moderate", "Minor") and each group must include a count and a brief human-readable description of the violation type.
- Console errors must be listed with the error message and the URL at which they occurred.
- The overall verdict ("Approved" or "Needs Revision" or "Skipped") must appear prominently at the top of the comment.

---

## Operational Visibility

- **Logs**: The design-reviewer agent logs each step (browser launch, navigation, screenshot capture, accessibility check, console error collection) so that debugging is possible when a review fails or produces unexpected results.
- **Notifications**: No additional notifications beyond the structured PR comment.
- **Audit trail**: The PR comment itself serves as the audit trail. Each run's verdict, screenshot count, console error count, and accessibility finding count are recorded there.

---

## Acceptance Criteria

- [ ] AC-1: A `design-reviewer` agent file exists in the repository (in `.claude/agents/`, `.cursor/agents/`, or the equivalent location for applicable runners).
- [ ] AC-2: When a PR on a `feature/*`, `fix/*`, `refactor/*`, or `hotfix/*` branch includes at least one frontend file (per the documented extension list), the Work Item Runner invokes the design-reviewer agent during Step 7a.
- [ ] AC-3: The design-reviewer agent launches a browser using the configured `browser_automation.provider`, navigates to the affected page(s) or component preview(s), and captures at least one screenshot per reviewed page/component.
- [ ] AC-4: The design-reviewer agent checks the browser console for errors and reports any errors found in the PR comment.
- [ ] AC-5: The design-reviewer agent runs an automated accessibility check and reports findings grouped by severity level (Critical, Serious, Moderate, Minor) in the PR comment.
- [ ] AC-6: The design-reviewer agent posts a structured PR comment that includes the overall verdict, screenshots (embedded or linked), console errors (if any), and accessibility findings.
- [ ] AC-7: When the design review finds critical or serious accessibility violations, or any console errors, the verdict is "Needs Revision" and the PR does not advance to `ready-for-human-review` until the issues are resolved or explicitly accepted.
- [ ] AC-8: When no frontend files are detected in the PR's changed files, the design-reviewer agent is not invoked and the PR proceeds without a design review comment.
- [ ] AC-9: When the configured browser automation provider is unavailable, the design-reviewer agent posts a skip notice on the PR (not an error) and the PR is not blocked.
- [ ] AC-10: The design-reviewer agent works with the `playwright_cli` provider configured in this repository's `.ai-dev-workflow.yaml`.
- [ ] AC-11: Protocol 91 Step 7a documentation is updated to describe when the design-reviewer agent is invoked and how its verdict is interpreted.

---

## Out of Scope (MVP)

- **Pages requiring authentication**: Reviewing pages behind a login wall or requiring session tokens is not included in this iteration. Only publicly accessible or locally served pages/components without authentication gates are in scope.
- **Visual regression diffing against a baseline**: Comparing screenshots to a stored baseline image to detect visual regressions is not included. This iteration captures screenshots for human review but does not perform automated visual diff.
- **Multi-viewport / responsive design testing**: Running reviews across multiple screen sizes (mobile, tablet, desktop) in the same pass is not included. A single viewport (default desktop) is used per review run.
- **Cross-browser compatibility testing**: Running reviews in multiple browser engines (Chrome, Firefox, Safari) in the same pass is not included. A single browser instance via `playwright_cli` is used.
- **Integration with other browser automation providers**: Only `playwright_cli` is tested and supported. Other configured providers (e.g., `cursor_ide_browser_mcp`, `playwright_mcp`) are out of scope for this iteration.
- **Design token or style consistency validation**: Checking that CSS values match a design token system is not in scope.
- **Component-level isolation testing**: Rendering isolated component stories (e.g., Storybook) is not in scope; only full pages navigable via URL are reviewed.
- **Automatic fix suggestions for accessibility violations**: The agent reports violations but does not suggest or apply fixes.

---

## Brief Coverage Matrix

| Brief Objective | Mapped to |
|---|---|
| A new `design-reviewer` agent exists that uses Playwright | AC-1, AC-3 |
| Agent detects when a PR includes frontend changes | AC-2, AC-8 |
| Agent launches Playwright browser to render changed pages/components | AC-3 |
| Agent captures screenshots | AC-3 |
| Agent checks for console errors | AC-4 |
| Agent runs axe-core accessibility checks | AC-5 |
| Agent reports findings as a structured PR review comment | AC-6 |
| Protocol 91 Step 7a invokes design-reviewer for PRs with frontend changes | AC-2, AC-11 |
| Agent gracefully skips when no frontend changes detected | AC-8, AC-9 |
| Agent gracefully skips when Playwright is unavailable | AC-9 |
| This repo's `browser_automation.provider: playwright_cli` is used | AC-10 |

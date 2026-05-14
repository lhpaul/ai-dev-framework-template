# Smoke Test Runbook: Playwright-Based Design Review

**Feature**: Playwright-based design review for frontend changes
**Spec**: [`docs/specs/developments/20260504142557_playwright-design-review/1_playwright-design-review_specs.md`](../../specs/developments/20260504142557_playwright-design-review/1_playwright-design-review_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Implementation PR is merged and the repository is on the latest `develop` commit
- [ ] `playwright_cli` is installed and accessible in the test environment (required for browser-based checks: AC-3, AC-4, AC-5)
- [ ] A test implementation PR is available that includes at least one frontend file (e.g., a `.html` or `.css` change) targeting `develop`
- [ ] A test implementation PR is available that includes only non-frontend files (e.g., a Markdown-only change) targeting `develop`
- [ ] GitHub CLI (`gh`) is authenticated for the repository

---

## Test Data

| Item                                   | Value                                                                                                                                                |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Frontend-change PR                     | A PR on a `feature/*` or `fix/*` branch that changes at least one file with extension `.html`, `.css`, `.scss`, `.jsx`, `.tsx`, `.vue`, or `.svelte` |
| Non-frontend PR                        | A PR on a `feature/*` or `fix/*` branch that changes only `.md` or `.sh` files                                                                       |
| Repository browser automation provider | `playwright_cli` (set in `.ai-dev-workflow.yaml`)                                                                                                    |
| Design-reviewer agent (Claude)         | `.claude/agents/design-reviewer.md`                                                                                                                  |
| Design-reviewer agent (Cursor)         | `.cursor/agents/design-reviewer.md`                                                                                                                  |
| Protocol 91                            | `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`                                                                       |

---

## Smoke Test Steps

### Step 1: Verify design-reviewer agent files exist (AC-1)

**Maps to**: Acceptance Criterion 1

1. Run: `ls .claude/agents/design-reviewer.md`
2. Run: `ls .cursor/agents/design-reviewer.md`
3. Open each file and confirm it contains YAML front matter with `name: design-reviewer` and a body defining the design review protocol.

**Expected result**: Both files exist and contain readable protocol content with YAML front matter.

---

### Step 2: Verify Protocol 91 Step 7a documents the design review gate (AC-11)

**Maps to**: Acceptance Criterion 11

1. Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.
2. Navigate to `## Step 7a: Internal Review Gate (Draft PR)`.
3. Confirm a `### Design Review Gate (implementation PRs only)` sub-section exists before the `### Determining which reviewers to run` sub-section.
4. Confirm the sub-section states that the gate applies only to `feature/*`, `fix/*`, `refactor/*`, and `hotfix/*` branches.
5. Confirm the sub-section documents how the verdict (`Approved`, `Needs Revision`, `Skipped`) is interpreted.

**Expected result**: The sub-section exists, covers implementation-PR-only scope, and explains verdict interpretation.

---

### Step 3: Verify frontend-file detection — frontend changes present (AC-2)

**Maps to**: Acceptance Criterion 2

1. Open a test PR that includes at least one file with a frontend extension (`.html`, `.css`, `.scss`, `.jsx`, `.tsx`, `.vue`, `.svelte`, or `.js`/`.ts` under a frontend-specific path prefix).
2. Confirm Protocol 91 Step 7a states that for this PR, the design-reviewer agent is invoked.
3. Inspect the PR comments after a Work Item Runner processes this PR to confirm a comment beginning with `## Design Review Summary` is present.

**Expected result**: The design-reviewer agent is invoked and posts a `## Design Review Summary` comment on the PR.

---

### Step 4: Verify frontend-file detection — no frontend changes (AC-8)

**Maps to**: Acceptance Criterion 8

1. Open a test PR that includes only non-frontend files (`.md`, `.sh`, `.yaml`, `.json`).
2. Confirm Protocol 91 Step 7a states that for this PR, the design-reviewer agent is NOT invoked.
3. Inspect the PR comments after a Work Item Runner processes this PR to confirm no `## Design Review Summary` comment is present.

**Expected result**: The design-reviewer agent is not invoked and no design review comment appears on the PR. The PR proceeds normally.

---

### Step 5: Verify browser launch, navigation, and screenshot capture (AC-3)

**Maps to**: Acceptance Criterion 3

1. On a PR with frontend changes and a reachable preview URL (set via `PREVIEW_URL` environment variable or via local dev server), run the design-reviewer agent.
2. Inspect the resulting PR comment for: a list of reviewed pages, at least one screenshot per page (embedded or as a linked artifact).
3. Confirm no screenshot-failure error appears in the comment.

**Expected result**: At least one screenshot per reviewed page is captured and referenced in the PR comment.

---

### Step 6: Verify console error checking (AC-4)

**Maps to**: Acceptance Criterion 4

1. On a PR with frontend changes, simulate a page that generates a console error during rendering (or inspect a PR whose page has known console errors).
2. After the design-reviewer agent runs, inspect the PR comment.
3. Confirm console errors are listed with error message text and the URL at which they occurred.

**Expected result**: Console errors are reported in the PR comment. If no console errors exist, the comment confirms zero errors were found.

---

### Step 7: Verify accessibility check and severity grouping (AC-5)

**Maps to**: Acceptance Criterion 5

1. On a PR with frontend changes, run the design-reviewer agent.
2. Inspect the PR comment for an accessibility findings section.
3. Confirm findings are grouped by severity level: Critical, Serious, Moderate, Minor — each group includes a count and a brief human-readable description.

**Expected result**: Accessibility findings appear grouped by severity. Each group has a count and description. If no violations exist, the comment confirms zero findings.

---

### Step 8: Verify structured PR comment format (AC-6)

**Maps to**: Acceptance Criterion 6

1. Inspect the PR comment produced by the design-reviewer agent on a frontend-change PR.
2. Confirm the comment:
   - Begins with `## Design Review Summary`
   - Contains `**Verdict**: Approved`, `**Verdict**: Needs Revision`, or `**Verdict**: Skipped` prominently near the top
   - Includes reviewed pages and screenshots
   - Includes console errors section (may report zero errors)
   - Includes accessibility findings section (may report zero violations)

**Expected result**: All required sections are present in the PR comment and the verdict is clearly labeled.

---

### Step 9: Verify blocking verdict when issues found (AC-7)

**Maps to**: Acceptance Criterion 7

1. On a PR with frontend changes where the rendered page has critical or serious accessibility violations, or has console errors: confirm the PR comment shows `**Verdict**: Needs Revision`.
2. Confirm the PR is NOT labeled `ready-for-human-review` until the issues are resolved or explicitly accepted.

**Expected result**: The PR remains without `ready-for-human-review` when the verdict is `Needs Revision`.

---

### Step 10: Verify `playwright_cli` is the configured provider (AC-10)

**Maps to**: Acceptance Criterion 10

1. Open `.ai-dev-workflow.yaml`.
2. Confirm `browser_automation.provider: playwright_cli`.
3. Open `.claude/agents/design-reviewer.md`.
4. Confirm the agent protocol reads the provider from `.ai-dev-workflow.yaml` and does not hard-code a provider name.

**Expected result**: `.ai-dev-workflow.yaml` sets `playwright_cli`; the agent reads the provider from config.

---

### Step 11: Verify graceful skip when provider unavailable (AC-9)

**Maps to**: Acceptance Criterion 9

1. Simulate provider unavailability (e.g., temporarily change `browser_automation.provider` to `none` or ensure `playwright_cli` is not installed in a test environment).
2. Run the design-reviewer agent on a PR with frontend changes.
3. Inspect the PR comment.
4. Confirm the comment includes `**Verdict**: Skipped` and names the provider as unavailable.
5. Confirm the PR is not blocked — it continues through the normal review flow.

**Expected result**: A skip notice with `**Verdict**: Skipped` is posted. The PR is not blocked.

---

### Step 12: Verify graceful skip when preview URL unreachable (AC-12)

**Maps to**: Acceptance Criterion 12

1. On a PR with frontend changes, ensure neither `PREVIEW_URL` is set nor a local dev server is running.
2. Run the design-reviewer agent.
3. Inspect the PR comment.
4. Confirm a skip notice is posted indicating no live preview was accessible.
5. Confirm the PR is not blocked.

**Expected result**: A skip notice is posted. The PR is not blocked.

---

### Last Step: Validate & Shut Down

- Confirm all assertions in the checklist below are met.
- Restore `.ai-dev-workflow.yaml` if temporarily modified during Step 11.
- Close any test PRs opened during smoke testing.

---

## Assertions Checklist

- [ ] AC-1: `.claude/agents/design-reviewer.md` and `.cursor/agents/design-reviewer.md` exist and contain protocol content
- [ ] AC-2: Work Item Runner invokes design-reviewer for `feature/*`/`fix/*`/`refactor/*`/`hotfix/*` PRs with at least one frontend file
- [ ] AC-3: Design-reviewer captures at least one screenshot per reviewed page when preview is accessible
- [ ] AC-4: Design-reviewer reports browser console errors (message + URL) in the PR comment
- [ ] AC-5: Accessibility findings are grouped by severity level (Critical, Serious, Moderate, Minor) with count and description per group
- [ ] AC-6: PR comment begins with `## Design Review Summary`, shows the overall verdict prominently, and includes screenshots, console errors, and accessibility findings
- [ ] AC-7: When critical/serious accessibility violations or console errors are found, verdict is `Needs Revision` and PR is not labeled `ready-for-human-review`
- [ ] AC-8: PR with no frontend files: design-reviewer agent not invoked; no design review comment posted
- [ ] AC-9: When `playwright_cli` is unavailable, design-reviewer posts a skip notice with `**Verdict**: Skipped` and the PR is not blocked
- [ ] AC-10: `.ai-dev-workflow.yaml` has `browser_automation.provider: playwright_cli`; agent reads provider from config
- [ ] AC-11: Protocol 91 Step 7a contains a `### Design Review Gate (implementation PRs only)` sub-section that describes invocation conditions and verdict interpretation
- [ ] AC-12: When the dev server or preview URL is unreachable, design-reviewer posts a skip notice and the PR is not blocked

---

## Seed Data Reference

Not applicable — this feature adds workflow agent files and protocol documentation. No database or application seed data is required.

---

## Troubleshooting

| Symptom                                                                | Likely cause                                                                    | Fix                                                                                                 |
| ---------------------------------------------------------------------- | ------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Design-reviewer agent not found at `.claude/agents/design-reviewer.md` | Implementation step 1 was not completed                                         | Verify the implementation PR included both agent files                                              |
| `## Design Review Summary` comment not posted on a frontend-change PR  | Protocol 91 Step 7a sub-section missing or Work Item Runner is an older version | Verify Step 7a sub-section exists in the protocol; re-run with the updated runner                   |
| Verdict not found or malformed in PR comment                           | Agent body does not follow the `**Verdict**: ...` format                        | Check the agent file for the verdict line format                                                    |
| PR blocked despite `Skipped` verdict                                   | Runner incorrectly treating `Skipped` as a failure                              | Verify Protocol 91 Step 7a skip semantics state that `Skipped` is not a failure (BR-3, BR-4, BR-10) |
| axe-core not running                                                   | `axe-core` not installed in runner environment                                  | Check environment setup; agent must handle this as a skip sub-condition                             |

---

## Known Limitations

- Pages requiring authentication are out of scope for this iteration (see spec Out of Scope section).
- Visual regression diffing against a baseline is not included; screenshots are for human review only.
- Only a single viewport (default desktop) is reviewed per run.
- Only `playwright_cli` is tested and supported; other configured providers are out of scope.

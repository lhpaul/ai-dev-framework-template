# Playwright-Based Design Review — Implementation Plan

**Spec**: [`1_playwright-design-review_specs.md`](1_playwright-design-review_specs.md)
**Smoke test runbook**: [`../../../testing/workflow/450-playwright-design-review.smoke-test.md`](../../../testing/workflow/450-playwright-design-review.smoke-test.md)

---

## Summary

**Approach**: Add a `design-reviewer` agent file (`.claude/agents/design-reviewer.md` and `.cursor/agents/design-reviewer.md`) that encodes the Playwright-based design review protocol, then update Protocol 91 Step 7a to describe when and how the Work Item Runner invokes the design-reviewer agent for implementation PRs that include frontend file changes. The implementation has three layers: (1) the design-reviewer agent files that carry the browser-launch, screenshot, accessibility-check, and PR-comment posting instructions; (2) an update to Protocol 91 Step 7a that inserts the frontend-detection and agent-invocation logic before the existing internal-reviewer dispatch loop; and (3) a smoke test runbook covering all acceptance criteria. No database, backend API, or infrastructure changes are required — this is a pure workflow-tooling and documentation addition.

**Estimated complexity**: M

**Rationale**: The implementation touches several files across both Claude and Cursor agent directories and two workflow protocol documents. The logic is non-trivial: the frontend-file detection heuristic, the preview URL resolution order, the three skip conditions (no frontend changes, provider unavailable, preview unreachable), and the verdict-parsing requirement (BR-9) must all be expressed precisely in prose that an AI agent can follow reliably. There is no code to compile and no external service to configure, but the protocol prose must be accurate and complete to avoid ambiguity that would cause implementation PRs to be blocked or mis-reviewed.

**Dependencies**: None — spec PR #475 is merged.

---

## Verification Log

| Check | Command / query | Result |
|---|---|---|
| Repo revision | `git rev-parse --short HEAD` | `1ab1488` |
| `design-reviewer` agent in `.claude/agents/` | `ls .claude/agents/ \| grep -i design` | No match — agent does not exist yet |
| `design-reviewer` agent in `.cursor/agents/` | `ls .cursor/agents/ \| grep -i design` | No match — agent does not exist yet |
| `browser_automation` references in Protocol 91 | `grep -n "browser_automation\|playwright\|design.review" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | No matches — feature is entirely new |
| Smoke test runbooks count | `ls docs/testing/workflow/*.smoke-test.md \| wc -l` | 17 runbooks; no `450-playwright-design-review.smoke-test.md` yet |
| Spec PR merged | `gh pr view 475 --json state --jq '.state'` | `MERGED` |

---

## Layer-by-Layer Changes

### Agent Files

- [ ] **`.claude/agents/design-reviewer.md`** — Create new Claude Code design-reviewer agent file with YAML front matter (`name: design-reviewer`, `model: claude-sonnet-4-6`, `description`, `tools: Read, Grep, Glob, Bash`) and a body that defines the full design review protocol: frontend-file detection, browser launch via `browser_automation.provider`, preview URL resolution, screenshot capture, console error collection, axe-core accessibility check, PR comment posting, and verdict reporting. All three skip conditions (no frontend changes, provider unavailable, preview unreachable) must be handled.

- [ ] **`.cursor/agents/design-reviewer.md`** — Create parallel Cursor agent file with the same protocol as the Claude Code agent. Cursor agent format uses the same YAML front matter convention as other Cursor agents in this repository.

### Protocol / Documentation Layer

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 7a: Design Review sub-step** — Insert a new sub-section titled "Design Review Gate (implementation PRs only)" into Step 7a, placed **before** the "Determining which reviewers to run" sub-section. The sub-section must:
  1. State that this gate applies only to PRs on `feature/*`, `fix/*`, `refactor/*`, and `hotfix/*` branches; it is skipped for `spec/*` and `implementation-plan/*` branches (BR-1).
  2. Define the frontend-file detection logic: inspect the PR's changed files via `gh pr diff <pr_number> --name-only`; a file is frontend if its extension is `.html`, `.css`, `.scss`, `.sass`, `.less`, `.jsx`, `.tsx`, `.vue`, or `.svelte`; or if its extension is `.js` or `.ts` and its path starts with `src/`, `app/`, `pages/`, `components/`, `public/`, `static/`, or `assets/` (BR-2). These detection rules are extensible — downstream teams that need additional extensions or paths must update this list.
  3. Describe the three execution paths:
     - **No frontend changes detected** (Use Case 2): skip the agent; no comment is posted; proceed to the existing internal-reviewer loop. This skip is not a failure (BR-10).
     - **Frontend changes detected, provider available** (Use Case 1): invoke the `design-reviewer` agent, passing the PR number, the list of changed frontend files, and any `PREVIEW_URL` environment variable or instructions to start the development server. After the agent posts its PR comment, parse the verdict from the comment header. If verdict is `Approved`: proceed normally. If verdict is `Needs Revision`: treat as a review finding that must be addressed before `ready-for-human-review` (BR-5). If verdict is `Skipped` (dev server unreachable): log the skip and continue without blocking (BR-4).
     - **Frontend changes detected, provider unavailable** (Use Case 3): invoke the `design-reviewer` agent; it will post a skip notice. Parse the skip verdict and continue without blocking (BR-3).
  4. Note that the preview URL resolution order is: (1) `PREVIEW_URL` environment variable as base URL; (2) local development server started by the agent; (3) skip preview navigation if neither is available (BR-11).
  5. Note that `browser_automation.provider` is read from `.ai-dev-workflow.yaml`; the agent must not hard-code a provider value (BR-8).

### Smoke Test Runbook

- [ ] **`docs/testing/workflow/450-playwright-design-review.smoke-test.md`** — Create runbook covering all twelve acceptance criteria (AC-1 through AC-12).

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:

1. `design-reviewer` agent files exist in `.claude/agents/` and `.cursor/agents/` (maps to AC-1)
2. Orchestrator invokes design-reviewer for a `feature/*` PR with at least one frontend file (maps to AC-2)
3. Design-reviewer agent launches browser via configured provider, navigates to the preview URL, and captures screenshots (maps to AC-3)
4. Design-reviewer agent checks browser console for errors and includes any errors in the PR comment (maps to AC-4)
5. Design-reviewer agent runs accessibility check and reports findings grouped by severity level (maps to AC-5)
6. Design-reviewer agent posts a structured PR comment with verdict, screenshots, console errors, and accessibility findings (maps to AC-6)
7. PR with critical/serious accessibility violations or console errors gets verdict `Needs Revision` and is not labeled `ready-for-human-review` (maps to AC-7)
8. PR with no frontend files: design-reviewer agent is not invoked and the PR proceeds without a design review comment (maps to AC-8)
9. `playwright_cli` provider unavailable: design-reviewer posts a skip notice and the PR is not blocked (maps to AC-9)
10. `playwright_cli` provider is the configured provider in this repository (maps to AC-10)
11. Protocol 91 Step 7a documents when design-reviewer is invoked and how its verdict is interpreted (maps to AC-11)
12. Dev server or preview URL unreachable: design-reviewer posts a skip notice and the PR is not blocked (maps to AC-12)

**Smoke test runbook**: `docs/testing/workflow/450-playwright-design-review.smoke-test.md`

**Regression suite**: None in this repository.

---

## Seed Data

Not applicable — this feature adds workflow agent files and protocol documentation. No database, application seed data, or fixture files are required. The smoke test exercises the feature by inspecting PR comments and labels on a GitHub pull request and by verifying agent file contents and protocol text.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — updated as part of this implementation (Step 7a Design Review Gate sub-section). This is an in-scope change, not a follow-up doc update.

No other project docs in `docs/project/`, `docs/best-practices/`, or `AGENTS.md` require updates. This feature adds a new workflow agent and a protocol sub-step; it does not change domain entities, repo architecture, the database model, general coding standards, version control conventions, or testing standards.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Agent prose is ambiguous about the `Needs Revision` verdict format, causing the orchestrator to fail to parse it | Med | Med | Define the verdict line format explicitly in both the agent file and the Protocol 91 sub-section: the PR comment must begin with a `## Design Review Summary` header and the verdict must appear as `**Verdict**: Approved`, `**Verdict**: Needs Revision`, or `**Verdict**: Skipped` (BR-9) |
| `playwright_cli` is not installed in the runner environment | Med | Low | BR-3 and BR-4 require graceful skip; the agent must detect unavailability and post a `Skipped` notice rather than failing the review gate |
| Frontend-file detection produces false positives or negatives for unusual path layouts | Low | Low | Detection rules are documented and extensible (BR-2); the rules in Protocol 91 Step 7a are the canonical list; teams needing extensions update that list |
| Preview URL is not set and no dev server startup command is available | Med | Low | BR-11 defines the three-step resolution order; the agent falls back to skipping preview navigation and posts a note; the PR is not blocked |
| axe-core is not available in the runner environment | Low | Low | Agent handles tool unavailability as a skip condition at the accessibility-check sub-step; the overall design review may still report screenshot and console-error findings even if accessibility cannot run |

---

## Code Samples

The design-reviewer agent files are prose-driven workflow documents, not executable code. No illustrative code samples are required in this plan. The agent invokes `playwright_cli` and `axe-core` via shell commands documented in the agent file itself; those commands will be written during implementation.

---

## Implementation Order

1. **Create `.claude/agents/design-reviewer.md`** at the worktree path. The file must include:
   - YAML front matter: `name: design-reviewer`, `model: claude-sonnet-4-6`, `description: Design review stage. Use when an implementation PR includes frontend file changes. Launches a browser via the configured browser_automation.provider, renders affected pages or components, captures screenshots, checks for console errors, and runs an axe-core accessibility check. Posts a structured PR comment with the verdict (Approved / Needs Revision / Skipped).`, `tools: Read, Grep, Glob, Bash`
   - Agent body: the full protocol text defining: (a) the three invocation paths and their skip conditions; (b) frontend-file detection (same extension list as Protocol 91 Step 7a — keep in sync); (c) preview URL resolution order (BR-11); (d) step-by-step browser workflow: read `browser_automation.provider` from `.ai-dev-workflow.yaml`, launch browser, navigate to each frontend page, capture screenshot, collect console errors, run axe-core; (e) PR comment format: `## Design Review Summary` header, `**Verdict**: <Approved|Needs Revision|Skipped>` as the first field, followed by reviewed pages, screenshots, console errors, and grouped accessibility findings; (f) accessibility violation severity grouping: Critical, Serious, Moderate, Minor — Critical and Serious are blocking (BR-6); (g) skip notice format when provider is unavailable or preview is unreachable.

2. **Create `.cursor/agents/design-reviewer.md`** at the worktree path with the same protocol content as the Claude Code agent. Verify the YAML front matter matches the convention of existing Cursor agents in `.cursor/agents/` (same field names, no extra fields).

3. **Update `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 7a**: Locate the `## Step 7a: Internal Review Gate (Draft PR)` heading. Immediately after the heading and the introductory sentence ("Run this step immediately after opening a draft PR..."), insert a new `### Design Review Gate (implementation PRs only)` sub-section before the `### Determining which reviewers to run` sub-section. The inserted prose must cover all points from the Layer-by-Layer Changes section above: branch-type gate, frontend-file detection command and extension list, the three execution paths with their skip semantics, preview URL resolution order, and the `browser_automation.provider` read requirement.

4. **Write the smoke test runbook** at `docs/testing/workflow/450-playwright-design-review.smoke-test.md`. Cover all twelve acceptance criteria with at least one testable step each.

5. **Cross-section consistency self-check**: Verify that the extension list and directory-prefix list in the `.claude/agents/design-reviewer.md` body exactly match the list in the Protocol 91 Step 7a sub-section. Verify that the verdict strings (`Approved`, `Needs Revision`, `Skipped`) and the PR comment header format (`## Design Review Summary`, `**Verdict**: ...`) are identical in both places. Fix any discrepancies before committing.

6. **Run markdownlint-cli2** on the new and modified files before staging:

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     ".claude/agents/design-reviewer.md" \
     ".cursor/agents/design-reviewer.md" \
     "docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md" \
     "docs/testing/workflow/450-playwright-design-review.smoke-test.md"
   ```

   Fix any trailing-whitespace, broken-relative-link, or missing-trailing-newline violations before proceeding.

7. **Update `CHANGELOG.md`** under `[Unreleased]` with:

   ```
   - **Add Playwright-based design review for frontend changes** (#450): Adds a `design-reviewer` agent (`.claude/agents/design-reviewer.md` and `.cursor/agents/design-reviewer.md`) that uses `playwright_cli` to render affected pages, capture screenshots, check browser console errors, and run axe-core accessibility checks (WCAG 2.1 Level AA). Protocol 91 Step 7a is updated to invoke the design-reviewer agent during the internal review gate for implementation PRs that include frontend file changes. Gracefully skips when no frontend changes are detected, when the browser automation provider is unavailable, or when the preview URL cannot be reached.
   ```

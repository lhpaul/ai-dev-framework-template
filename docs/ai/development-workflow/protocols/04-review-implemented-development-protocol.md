# Protocol: Review Implemented Development (Code Review)

**Agent role**: Code Reviewer
**Stage**: Development Review (after In Development PR is opened)
**Output**: Fixes applied directly + review report

---

## Flow Overview

Execute the steps below in order. The review checklist is always run; when the code-review command is available, run it first so its findings inform the rest of the review.

1. **Prerequisites** — Read spec, plan, best practices, locate code
2. **Run code-review command** (when possible) — See [Step 2](#step-2-run-code-review-command-when-possible)
3. **Review checklist** — Always complete the full [Review Checklist](#step-3-review-checklist)
4. **Apply fixes** — Fix or report issues per [Apply Fixes](#apply-fixes)
5. **Output** — Produce the review report per [Output Format](#output-format)

---

## Step 1: Prerequisites

Before reviewing, read:
- The spec: `docs/specs/developments/[folder]/1_[slug]_specs.md`
- The plan: `docs/specs/developments/[folder]/2_[slug]_implementation-plan.md`
- All best practices: `docs/best-practices/`
- The actual code changes

### Locating the code to review

Priority order:
1. Explicit file paths provided by the human
2. Files edited in the current conversation
3. All files changed in the PR: `git diff develop...HEAD` (or `main...HEAD` for hotfix)
4. Ask the human

---

## Step 2: Run code-review command (when possible)

If you have access to the `Task` tool (e.g. you are running inside Claude Code and can spawn subagents), run this step **before** the review checklist:

Execute the pipeline defined in **`.claude/commands/code-review.md`**.

That pipeline runs multiple parallel review agents, scores issues for confidence, filters to high-confidence findings (≥ 80), and can post the result as a PR comment. Use its findings to inform the checklist and fix list below.

If the `Task` tool is not available (e.g. in Cursor, Codex, Gemini CLI), skip this step and proceed to the review checklist.

---

## Step 3: Review checklist

**Always** work through the full checklist below. If you ran the code-review command in Step 2, incorporate its findings into your checklist (e.g. treat its reported issues as candidates for the fix list and verify them against the checklist). Otherwise complete the checklist from scratch.

### 1. Plan Alignment

- [ ] All steps in the implementation plan are completed
- [ ] All acceptance criteria from the spec are implemented
- [ ] No changes made that aren't in the plan (unless a justified deviation is documented in the PR)
- [ ] Deviations from the plan are documented in the PR description with a rationale

### 2. Best Practices Compliance

- [ ] `docs/best-practices/1-general.md` — general conventions followed
- [ ] `docs/best-practices/2-version-control.md` — commit messages follow Conventional Commits
- [ ] `docs/best-practices/STACK-SPECIFIC.md` and `docs/best-practices/stack/` — stack-specific conventions followed (read the relevant technology files for the areas touched by this PR)
- [ ] CHANGELOG updated under `[Unreleased]` with appropriate entry

### 3. Code Quality & Correctness

- [ ] Logic is correct — matches the spec's business rules
- [ ] Edge cases from the spec are handled
- [ ] No dead code or commented-out code left in
- [ ] No unnecessary complexity introduced
- [ ] Functions are focused on one responsibility

### 4. Architecture & Design

- [ ] New code is consistent with existing patterns in the codebase
- [ ] No new patterns introduced without justification
- [ ] Abstractions are justified (not premature)
- [ ] No circular dependencies introduced

### 5. Security

- [ ] User input is validated at system boundaries
- [ ] No secrets, API keys, or credentials in code or commits
- [ ] Authorization is enforced at the right level (follows the project's security model)
- [ ] No injection vulnerabilities (SQL, shell, template, etc.)

### 6. Tests

- [ ] Tests exist for the new/changed business logic
- [ ] Tests are meaningful — they test behavior, not implementation details
- [ ] No tests deleted to make the build pass

### 7. Workflow-Specific

- [ ] CHANGELOG entry is present and correctly formatted
- [ ] Seed data updated if the plan required it
- [ ] Generated types updated if schema changed (if applicable)
- [ ] Spec/plan status updated if required

---

## Severity Levels

| Severity | Definition | Action |
|---|---|---|
| **Blocking** | Spec deviation, broken build, security issue, missing tests for critical logic | Must fix before merge |
| **Important** | Performance concern, missing edge case, confusing code | Fix by default; document if deferred |
| **Suggestion** | Style improvement, alternative approach | Fix at discretion |

---

## Apply Fixes

<a name="apply-fixes"></a>

**Fix directly** (without asking) for:
- Blocking and important issues
- Suggestions where the improvement is clear and low-risk
- Formatting, naming, and convention issues

**Report only** (do not fix) when:
- A product/design decision is needed
- The fix would change behavior in a way that requires spec input
- The issue is ambiguous and could be fixed in multiple valid ways

---

## Output Format

```
## Code Review: [feature-name]

### What's Good
[Acknowledge what was done well — specific and genuine]

### Summary
[One paragraph — is the PR ready to merge?]

### Plan Alignment
[Table mapping plan steps to implementation status]

### Issues Fixed
[List by severity: Blocking → Important → Suggestions]

### Issues Requiring Human Input
[List with context for each]

### Test Plan
[How to manually validate the key scenarios — reference smoke test runbook if available]

### Verdict
[ ] APPROVED — ready to merge
[ ] NEEDS REVISION — see blocking/important issues above
```

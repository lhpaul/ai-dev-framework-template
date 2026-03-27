# Protocol: Implement Development (In Development Stage)

**Agent role**: Developer
**Stage**: In Development
**Paths**: Full Pipeline | Fast Track | Hotfix

---

## Which Path to Use?

| Path | Branch | Use when |
|---|---|---|
| **Full Pipeline** | `feature/[slug]` from `develop` | Feature with approved spec + plan |
| **Fast Track** | `fix/[slug]` from `develop` | Bug or simple change — clear scope, ≤3 files, no schema changes, no new patterns |
| **Hotfix** | `hotfix/[slug]` from `main` | Critical production bug requiring immediate deployment |

---

## Path 1: Full Pipeline

### Step 1: Non-Negotiable Prep

Read **all** of the following before writing a single line of code. Do not skip.

1. `docs/specs/developments/[timestamp]_[slug]/1_[slug]_specs.md` — spec (acceptance criteria, use cases, business rules)
2. `docs/specs/developments/[timestamp]_[slug]/2_[slug]_implementation-plan.md` — plan (what to build, in what order)
3. `docs/testing/[section]/[slug].smoke-test.md` — smoke test runbook (what "done" looks like)
4. `docs/project/3-software-architecture.md` — architecture patterns
5. `docs/best-practices/` — all best practice docs
6. Relevant existing code — read actual files for the areas you will modify
7. If an issue tracker exists for this item, follow `docs/ai/development-workflow/integrations/issue-tracker.md` for `In Development (Full Pipeline)` expectations before coding.

Extract from your reading:
- The full list of acceptance criteria
- Every file or area you will touch
- The implementation order from the plan
- Seed data requirements

**Dependency check**: Read the `Depends on` field in the spec. If any dependency is not yet Merged or Released, stop and report to the human.

### Step 2: Human Review Shortcut (Optional)

Default behavior is **max autonomy**: once the approved spec and plan are understood and there is no unresolved product or architecture ambiguity, continue through implementation, the review gate, PR creation, and PR readiness without an extra pause.

Pause only if:

- The human explicitly asked to review the execution plan before coding
- The spec or plan is missing a decision you cannot safely invent
- The reviewer gate returns `NEEDS REVISION` because a human decision is required

### Step 3: Branch

Determine the branch slug:
- **With issue tracker**: `[issue-id]-[slug]` (e.g., `ENG-123-user-auth`)
- **Without issue tracker**: `[slug]` (e.g., `user-auth`)

```bash
git checkout develop
git pull origin develop
git checkout -b feature/[branch-slug]
```

### Step 4: Mark Status

- **When the issue tracker is the source of truth**: update the issue status to `In Development`; optionally update the spec file's status field for backwards compatibility.
- The spec file's **Status** field is optional and need not be set (workflow status is derived from the tracker or repo state).

If the spec file's status field was updated, commit: `docs: mark [feature-name] as In Development`

### Step 5: Implement

Execute each step from the implementation plan in order.

**Rules during implementation**:

- Follow `docs/best-practices/` for all code written
- Follow the implementation order in the plan
- If you hit a spec gap (something not covered by the spec), **stop and report** — do not make unilateral decisions
- If the scope is larger than the plan described, **stop and report**
- After each logical chunk of work, verify your changes are still building

**After schema/model changes** (if applicable):
- Run type generation if your project uses generated types from the schema
- Verify generated types are committed

**Seed data**: If the plan requires seed data changes, make them and verify they load correctly.

**End-to-end spec maintenance**: If a committed automated spec exists for the feature under test, keep it in sync with your changes. If the feature is new and a smoke test runbook exists, create the corresponding spec as part of the implementation. See `docs/project/3-software-architecture.md` → Testing Strategy for the two-tier approach.

### Step 6: Pre-Commit Verification

Before committing, verify:

```bash
# Build — must succeed
[your build command]

# Lint — must pass with zero errors
[your lint command]

# Unit / integration tests — must pass
[your test command]

# End-to-end suite — run if a spec exists for the affected feature
[your e2e command]
```

Fix any failures before committing. Do not push a broken build.

### Step 7: Update CHANGELOG

Add an entry under `[Unreleased]` in `CHANGELOG.md`:
- Use the appropriate category: `Added`, `Changed`, `Fixed`, `Security`, `Deprecated`, `Removed`
- Write from the user's perspective: what can they now do / what is now fixed?

### Step 8: Commit & Push

```bash
git add [files]
git commit -m "feat([scope]): [description]"
git push -u origin feature/[slug]
```

Use Conventional Commits (see `docs/best-practices/2-version-control.md`).

### Step 9: Open PR (Draft)

Open a **draft** PR targeting `develop` with:
- **Title**: `feat([scope]): [feature-name]`
- **Description**:
  - What was implemented
  - Link to spec and plan
  - Test plan (how to validate)
  - Any deviations from the plan (with justification)
  - CHANGELOG entry preview

```bash
gh pr create --draft --title "feat([scope]): [feature-name]" --body "..."
```

### Step 10: Internal Code Review

Run the code review gate on the draft PR using `REVIEW.md`:

- **Claude Code**: Use the `code-reviewer` agent (or `/code-review` command)
- **Other runners**: Use the compatibility wrapper `docs/ai/development-workflow/protocols/04-review-implemented-development-protocol.md`

Apply fixes directly on the branch, commit, and push if needed. Repeat until the review is clean.

If the verdict is **NEEDS REVISION** due to product/design decisions, stop and request human input before proceeding.

### Step 11: Automated Review Loop (if configured)

If an automated PR review tool is enabled (see `docs/ai/development-workflow/integrations/`):

1. Run `./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch feature/[slug]` (or the matching `fix/` / `hotfix/` branch)
2. If the result is `needs_fixes`, apply the fixes, push, and run the loop again
3. If the result is `clean`, continue immediately to Step 12
4. If the result is `escalate`, stop and report the latest blocking PR feedback to the human
5. Non-blocking suggestions: address at your discretion

### Step 12: PR Readiness Signal

Run `./scripts/development-workflow/pr-ci-loop.sh <pr_number>`. When CI is green and all reviews are clean:

```bash
gh pr ready <pr_number>
```

Then apply `agent:ready-for-review` only when:
- CI checks are green
- Claude code review has no blocking findings
- Automated review has no blocking PR feedback (or is not configured)

If CI fails, apply `agent:needs-fixes`, fix the branch, push, and return to Step 11.

See `docs/ai/development-workflow/protocols/91-pr-readiness-signal-protocol.md`.

---

## Path 2: Fast Track (Bug / Simple Change)

**Criteria check — all must be true**:
- [ ] The scope is clear and bounded from the start
- [ ] ≤ 3 files will be modified (estimate before starting)
- [ ] No new database schema migrations
- [ ] No new architectural patterns
- [ ] Human provided a clear, self-contained brief

**If any criterion fails**: Use the Full Pipeline instead.

**If scope expands during implementation**: Stop immediately. Report to the human. Do not silently expand scope.

### Steps

1. Read the brief. If the work item exists in an issue tracker, follow `docs/ai/development-workflow/integrations/issue-tracker.md` for `In Development (Fast Track)` expectations.
2. If no blocking ambiguity remains, proceed without an extra approval pause; otherwise stop and ask the human
3. Branch: `git checkout -b fix/[branch-slug]` from `develop` (slug: `[issue-id]-[slug]` with tracker, `[slug]` without)
4. Implement the fix
5. Verify: build, lint, tests pass; run e2e suite if a spec exists for the affected area
6. Update CHANGELOG under `[Unreleased]` with a `Fixed` entry
7. Commit: `fix([scope]): [description]`
8. Push branch to remote
9. Open draft PR targeting `develop` (Step 9 above)
10. Run Claude code review (Step 10 above)
11. Follow automated review loop (Step 11 above) if configured
12. Run CI loop to completion, then run `gh pr ready` and apply `agent:ready-for-review`

---

## Path 3: Hotfix (Critical Production Bug)

**Criteria**: Active production incident or critical security issue.

### Steps

1. Read the incident brief from the human
2. Confirm it's a production-only issue (not a dev/staging issue)
3. Branch: `git checkout -b hotfix/[branch-slug]` from `main` (slug: `[issue-id]-[slug]` with tracker, `[slug]` without)
4. Implement the minimal fix (do not bundle unrelated changes)
5. Verify: build, lint, tests pass
6. Update CHANGELOG under `[Unreleased]` with a `Fixed` entry
7. Commit: `fix([scope]): [description] (hotfix)`
8. Push branch to remote
9. Open draft PR targeting `main` (Step 9 above)
10. Run Claude code review (Step 10 above)
11. Run automated review + CI loops to completion, then run `gh pr ready` and apply `agent:ready-for-review`
12. **After merge**: notify the human that a backport PR (main → develop) must be opened to prevent branch drift

---

## Spec Gaps & Workflow Hardening

When you encounter something the spec or plan doesn't cover:

1. **Stop** — do not make a unilateral product decision
2. **Report**: "The spec doesn't address X. Here are my options: A (simpler), B (more complete). Which do you prefer?"
3. Human decides
4. **Update** the spec or plan with the clarification
5. **Resume** implementation
6. If the gap reveals a recurring weakness in the spec template or protocol, flag it so the template can be improved

---

## Quality Rules

- Follow all best practices in `docs/best-practices/`
- Never expose raw internal values (enum codes, IDs) directly in user-facing output — use display labels
- Extract duplication only when the same logic appears 3+ times and the abstraction is clear
- Do not refactor code outside the scope of the current change
- Do not add comments to code you didn't modify

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

### Step 2: Approval Gate

Before branching, present a brief execution plan to the human:

> "I've read the spec and plan. Here's what I'll do: [summary]. Shall I proceed?"

Wait for explicit confirmation.

### Step 3: Branch

Determine the branch slug:
- **With issue tracker**: `[issue-id]-[slug]` (e.g., `ENG-123-user-auth`)
- **Without issue tracker**: `[slug]` (e.g., `user-auth`)

```bash
git checkout develop
git pull
git checkout -b feature/[branch-slug]
```

### Step 4: Mark Status

Update the spec file's status field from `Plan Ready` to `In Development`.

Commit: `docs: mark [feature-name] as In Development`

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

### Step 6: Pre-Commit Verification

Before committing, verify:

```bash
# Build — must succeed
[your build command]

# Lint — must pass with zero errors
[your lint command]

# Tests — must pass
[your test command]
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

### Step 9: Open PR

Open a PR targeting `develop` with:
- **Title**: `feat([scope]): [feature-name]`
- **Description**:
  - What was implemented
  - Link to spec and plan
  - Test plan (how to validate)
  - Any deviations from the plan (with justification)
  - CHANGELOG entry preview

### Step 10: Automated Review Loop (if configured)

If an automated PR review tool is enabled (see `docs/ai/development-workflow/integrations/`):

1. Wait for the automated review to complete
2. For each **blocking** issue: fix it and push
3. Re-trigger the review if needed (see the integration doc for how)
4. Repeat until no blocking issues remain
5. Non-blocking suggestions: address at your discretion

### Step 11: PR Readiness Signal

Apply `agent:ready-for-review` label when:
- CI checks are green
- Automated review has no blocking issues (or is not configured)

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
2. Present a brief execution plan and get approval
3. Branch: `git checkout -b fix/[branch-slug]` from `develop` (slug: `[issue-id]-[slug]` with tracker, `[slug]` without)
4. Implement the fix
5. Verify: build, lint, tests pass
6. Update CHANGELOG under `[Unreleased]` with a `Fixed` entry
7. Commit: `fix([scope]): [description]`
8. Push and open PR targeting `develop`
9. Follow automated review loop (Step 10 above) if configured
10. Apply `agent:ready-for-review` label

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
8. Push and open PR targeting `main`
9. Apply `agent:ready-for-review` label
10. **After merge**: notify the human that a backport PR (main → develop) must be opened to prevent branch drift

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

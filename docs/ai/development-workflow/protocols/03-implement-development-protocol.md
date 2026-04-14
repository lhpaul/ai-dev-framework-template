# Protocol: Implement Development (In Development Stage)

**Agent role**: Developer
**Stage**: In Development
**Paths**: Full Pipeline | Refactor | Fast Track | Hotfix

---

## Which Path to Use?

| Path | Branch | Use when |
|---|---|---|
| **Full Pipeline** | `feature/[slug]` from `develop` | Feature with approved spec + plan |
| **Refactor** | `refactor/[slug]` from `develop` | Code restructuring with approved plan (no spec) |
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
git fetch origin
git checkout develop
git pull origin develop
git checkout -b feature/[branch-slug]
```

### Step 4: Implement

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

### Step 5: Pre-Commit Verification

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

### Step 6: Update CHANGELOG

> **Parallel batch exception**: If this implementation is part of a parallel batch and `SKIP_CHANGELOG=true` was signaled in the Work Item Runner handoff, skip this step entirely. See protocol 90 Step 3.6 for details.

Add an entry under `[Unreleased]` in `CHANGELOG.md`:

- Use the appropriate category: `Added`, `Changed`, `Fixed`, `Security`, `Deprecated`, `Removed`
- Write from the user's perspective: what can they now do / what is now fixed?
- If this PR fixes or adjusts an unreleased development that already has an `[Unreleased]` entry, update the existing entry instead of adding a new one; if the entry already describes the corrected behavior, no change is needed

### Step 7: Commit & Push

```bash
git add [files]
git commit -m "feat([scope]): [description]"
git push -u origin feature/[slug]
```

Use Conventional Commits (see `docs/best-practices/2-version-control.md`).

### Step 8: Open PR (Draft)

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

### Step 9: Handoff to Work Item Runner

After the draft PR exists, the **Work Item Runner** owns the rest of the lifecycle for this item:

- Run the internal code review gate (`code-reviewer` / `03-review-implementation-protocol.md`) on the draft PR
- Run the automated reviewer loop and CI loop to completion
- Apply `ready-for-human-review` and move the tracker to **Development in Review** when the PR is human-ready
- Stop only when the PR is waiting on human review / merge or the run has escalated

If this protocol is invoked **standalone** rather than through the Work Item Runner, hand off manually by following `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md` from the newly opened draft PR.

See `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md` and `docs/ai/development-workflow/protocols/92-pr-readiness-signal-protocol.md`.

---

## Path 2: Refactor (Code Restructuring / Tech Debt)

**Criteria**: Code restructuring, tech-debt cleanup, or internal reorganization that has an approved implementation plan but no product spec.

### Step 1: Non-Negotiable Prep

Read **all** of the following before writing a single line of code. Do not skip.

1. `docs/specs/developments/[timestamp]_[slug]/2_[slug]_implementation-plan.md` — plan (what to restructure, in what order)
2. `docs/testing/[section]/[slug].smoke-test.md` — smoke test runbook (what "done" looks like)
3. `docs/project/3-software-architecture.md` — architecture patterns
4. `docs/best-practices/` — all best practice docs
5. Relevant existing code — read actual files for the areas you will modify
6. If an issue tracker exists for this item, follow `docs/ai/development-workflow/integrations/issue-tracker.md` for `In Development (Refactor)` expectations before coding.

Extract from your reading:

- Every file or area you will touch
- The implementation order from the plan
- The acceptance criteria from the plan

**Dependency check**: Read the `Depends on` field in the plan. If any dependency is not yet Merged or Released, stop and report to the human.

### Refactor Steps

1. If no blocking ambiguity remains, proceed without an extra approval pause; otherwise stop and ask the human
2. Branch from `develop` (slug: `[issue-id]-[slug]` with tracker, `[slug]` without):

```bash
git fetch origin
git checkout develop
git pull origin develop
git checkout -b refactor/[branch-slug]
```

3. Implement following the plan order. Follow `docs/best-practices/` for all code written.
4. If scope is larger than the plan described, **stop and report**
5. Verify: build, lint, tests pass; run e2e suite if a spec exists for the affected area
6. Update CHANGELOG under `[Unreleased]` with a `Changed` entry (skip if this refactor adjusts unreleased work that already has an entry — update the existing entry instead, or leave it unchanged if it already describes the correct behavior). **Parallel batch exception**: if `SKIP_CHANGELOG=true` was signaled in the handoff, skip this step (see protocol 90 Step 3.6)
7. Commit: `refactor([scope]): [description]`
8. Push branch to remote
9. Open a **draft** PR targeting `develop` with refactor-appropriate metadata (do **not** reuse Path 1 Step 8 verbatim — that path uses `feat(...)` and a spec link):
   - **Title**: `refactor([scope]): [short description]`
   - **Description**:
     - What was refactored and why
     - Link to the **implementation plan** only (no spec)
     - Test plan (how to validate)
     - Any deviations from the plan (with justification)
     - CHANGELOG entry preview

```bash
gh pr create --draft --title "refactor([scope]): [short description]" --body "..."
```

10. Hand off to the Work Item Runner with the same lifecycle expectations as Path 1 Step 9 (internal review gate, automated reviewer loop, CI, labels). See `docs/ai/development-workflow/protocols/91-orchestrate-work-protocol.md` and `docs/ai/development-workflow/protocols/92-pr-readiness-signal-protocol.md`.

---

## Path 3: Fast Track (Bug / Simple Change)

**Criteria check — all must be true**:

- [ ] The scope is clear and bounded from the start
- [ ] ≤ 3 files will be modified (estimate before starting)
- [ ] No new database schema migrations
- [ ] No new architectural patterns
- [ ] Human provided a clear, self-contained brief

**If any criterion fails**: Use the Full Pipeline instead.

**If scope expands during implementation**: Stop immediately. Report to the human. Do not silently expand scope.

### Fast Track Steps

1. Read the brief. If the work item exists in an issue tracker, follow `docs/ai/development-workflow/integrations/issue-tracker.md` for `In Development (Fast Track)` expectations.
2. If no blocking ambiguity remains, proceed without an extra approval pause; otherwise stop and ask the human
3. Branch from `develop` (slug: `[issue-id]-[slug]` with tracker, `[slug]` without):

```bash
git fetch origin
git checkout develop
git pull origin develop
git checkout -b fix/[branch-slug]
```

4. Implement the fix
5. Verify: build, lint, tests pass; run e2e suite if a spec exists for the affected area
6. Update CHANGELOG under `[Unreleased]` with a `Fixed` entry (skip if this fixes unreleased work that already has an entry — update the existing entry instead, or leave it unchanged if it already describes the correct behavior). **Parallel batch exception**: if `SKIP_CHANGELOG=true` was signaled in the handoff, skip this step (see protocol 90 Step 3.6)
7. Commit: `fix([scope]): [description]`
8. Push branch to remote
9. Open a **draft** PR targeting `develop` using the same structure as Path 1 `### Step 8: Open PR (Draft)`, but with a **`fix(...)`** title and a fix-focused description (omit spec/plan links when none exist).
10. Hand off to the Work Item Runner per Path 1 `### Step 9: Handoff to Work Item Runner`.

---

## Path 4: Hotfix (Critical Production Bug)

**Criteria**: Active production incident or critical security issue.

### Hotfix Steps

1. Read the incident brief from the human
2. Confirm it's a production-only issue (not a dev/staging issue)
3. Branch from `main` (slug: `[issue-id]-[slug]` with tracker, `[slug]` without):

```bash
git fetch origin
git checkout main
git pull origin main
git checkout -b hotfix/[branch-slug]
```

4. Implement the minimal fix (do not bundle unrelated changes)
5. Verify: build, lint, tests pass
6. Update CHANGELOG under `[Unreleased]` with a `Fixed` entry (hotfixes always fix released code, so a new entry is always required). **Parallel batch exception**: if `SKIP_CHANGELOG=true` was signaled in the handoff, skip this step (see protocol 90 Step 3.6)
7. Commit: `fix([scope]): [description] (hotfix)`
8. Push branch to remote
9. Open a **draft** PR targeting `main` by adapting Path 1 `### Step 8: Open PR (Draft)` for hotfix (`fix(...)` title with `(hotfix)` as needed, incident-focused body, target branch `main`).
10. Hand off to the Work Item Runner per Path 1 `### Step 9: Handoff to Work Item Runner`.
11. **After merge**: notify the human that a backport PR (main → develop) must be opened to prevent branch drift

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

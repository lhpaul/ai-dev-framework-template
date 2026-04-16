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

### Step 1b: Pre-Implementation Scope Checklist

Complete this checklist **before writing any code**. It takes 5–10 minutes and prevents review round-trips caused by missed files, scope drift, or inconsistencies with related protocols.

1. **Enumerate all files** that need changes. List every file path explicitly.
2. **For each file**, describe the specific changes needed (e.g., "add section X", "update step Y to handle case Z").
3. **Verify scope**: confirm all listed changes are within the issue's stated scope. Remove anything that is not.
4. **Consider edge cases** before touching any file:
   - What if the branch already exists locally or remotely?
   - What if this runs inside a worktree?
   - What are the failure modes or missing inputs?
   - Are there related files that must stay consistent with the changed files?
5. **Cross-reference related protocols**: if any changed file references or is referenced by other protocol documents, read those documents and confirm your changes are consistent with them.

Do not proceed to Step 2 until this checklist is complete and all five points are answered.

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
gh pr create --draft --base develop --title "feat([scope]): [feature-name]" --body "..."
```

**Important**: Always use `--base develop` to explicitly target the `develop` branch. This prevents accidental PR creation to `main` or other branches.

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

### Step 1b: Pre-Implementation Scope Checklist

Complete this checklist **before writing any code**. It takes 5–10 minutes and prevents review round-trips caused by missed files, scope drift, or inconsistencies with related protocols.

1. **Enumerate all files** that need changes. List every file path explicitly.
2. **For each file**, describe the specific changes needed (e.g., "restructure section X", "rename Y to Z").
3. **Verify scope**: confirm all listed changes are within the refactor's stated scope. Remove anything that is not.
4. **Consider edge cases** before touching any file:
   - What if the branch already exists locally or remotely?
   - What if this runs inside a worktree?
   - Are there callers or dependents of the refactored code that must be updated in sync?
   - What behavior is preserved vs. changed?
5. **Cross-reference related protocols**: if any changed file references or is referenced by other protocol documents, read those documents and confirm your changes are consistent with them.

Do not proceed to the Refactor Steps until this checklist is complete and all five points are answered.

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
6. Update CHANGELOG under `[Unreleased]` with a `Changed` entry (skip if this refactor adjusts unreleased work that already has an entry — update the existing entry instead, or leave it unchanged if it already describes the correct behavior).
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
gh pr create --draft --base develop --title "refactor([scope]): [short description]" --body "..."
```

**Important**: Always use `--base develop` to explicitly target the `develop` branch.

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

### Step 1: Read Brief

Read the brief. If the work item exists in an issue tracker, follow `docs/ai/development-workflow/integrations/issue-tracker.md` for `In Development (Fast Track)` expectations.

### Step 1b: Pre-Implementation Scope Checklist

Complete this checklist **before writing any code**. It takes 5–10 minutes and prevents review round-trips caused by missed files, scope drift, or inconsistencies with related files.

1. **Enumerate all files** that need changes (list every file path explicitly).
2. **For each file**, describe the specific changes needed.
3. **Verify scope**: confirm all listed changes are within the issue's stated scope. Remove anything that is not.
4. **Consider edge cases**: what if the branch already exists locally or remotely? What if this runs in a worktree? What are the failure modes?
5. **Cross-reference related protocols**: if any changed file references or is referenced by other protocol documents, read those documents and confirm your changes are consistent with them.

Do not proceed to Step 2 until this checklist is complete and all five points are answered.

### Step 2: Ambiguity Check

If no blocking ambiguity remains, proceed without an extra approval pause; otherwise stop and ask the human.

### Step 3: Branch

Branch from `develop` (slug: `[issue-id]-[slug]` with tracker, `[slug]` without):

```bash
git fetch origin
git checkout develop
git pull origin develop
git checkout -b fix/[branch-slug]
```

### Step 4: Implement

Implement the fix.

### Step 5: Verify

Verify: build, lint, tests pass; run e2e suite if a spec exists for the affected area.

### Step 6: Update CHANGELOG

Update CHANGELOG under `[Unreleased]` with a `Fixed` entry (skip if this fixes unreleased work that already has an entry — update the existing entry instead, or leave it unchanged if it already describes the correct behavior).

### Step 7: Commit & Push

```bash
git add [files]
git commit -m "fix([scope]): [description]"
git push -u origin fix/[branch-slug]
```

### Step 8: Open PR (Draft)

Open a **draft** PR targeting `develop` using the same structure as Path 1 `### Step 8: Open PR (Draft)`, but with a **`fix(...)`** title and a fix-focused description (omit spec/plan links when none exist):

```bash
gh pr create --draft --base develop --title "fix([scope]): [description]" --body "..."
```

### Step 9: Handoff to Work Item Runner

Hand off to the Work Item Runner per Path 1 `### Step 9: Handoff to Work Item Runner`.

---

## Path 4: Hotfix (Critical Production Bug)

**Criteria**: Active production incident or critical security issue.

### Step 1: Read Brief

Read the incident brief from the human.

### Step 2: Confirm Production

Confirm it's a production-only issue (not a dev/staging issue).

### Step 2b: Pre-Implementation Scope Checklist

Complete this checklist **before writing any code**. It takes 5–10 minutes and prevents review round-trips caused by missed files or scope creep in a production-critical context.

1. **Enumerate all files** that need changes (list every file path explicitly).
2. **For each file**, describe the specific changes needed.
3. **Verify scope**: confirm all listed changes address the production incident directly. Remove anything that is not strictly necessary.
4. **Consider edge cases**: what if the branch already exists locally or remotely? What is the minimal safe change? Are there related files that must stay consistent?
5. **Cross-reference related protocols**: if the fix touches shared utilities or configuration files used by other flows, confirm consistency.

Do not proceed to Step 3 until this checklist is complete and all five points are answered.

### Step 3: Branch

Branch from `main` (slug: `[issue-id]-[slug]` with tracker, `[slug]` without):

```bash
git fetch origin
git checkout main
git pull origin main
git checkout -b hotfix/[branch-slug]
```

### Step 4: Implement

Implement the minimal fix (do not bundle unrelated changes).

### Step 5: Verify

Verify: build, lint, tests pass.

### Step 6: Update CHANGELOG

Update CHANGELOG under `[Unreleased]` with a `Fixed` entry (hotfixes fix released code, so a new entry is normally required).

### Step 7: Commit & Push

```bash
git add [files]
git commit -m "fix([scope]): [description] (hotfix)"
git push -u origin hotfix/[branch-slug]
```

### Step 8: Open PR (Draft)

Open a **draft** PR targeting `main` by adapting Path 1 `### Step 8: Open PR (Draft)` for hotfix (`fix(...)` title with `(hotfix)` as needed, incident-focused body, target branch `main`):

```bash
gh pr create --draft --base main --title "fix([scope]): [description] (hotfix)" --body "..."
```

**Important**: Use `--base main` for hotfixes (not `develop`). A hotfix merges to production first, then must be backported to `develop`.

### Step 9: Handoff to Work Item Runner

Hand off to the Work Item Runner per Path 1 `### Step 9: Handoff to Work Item Runner`.

**After merge**: notify the human that a backport PR (main → develop) must be opened to prevent branch drift.

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

- **Scope boundary**: Modify **only** files directly related to the assigned issue. If a code review or linter finding requires changes outside the issue's scope (e.g., fixing issues in adjacent modules, refactoring unrelated utilities, or addressing tech debt in other areas):
  1. **Do not fix it** in the current PR
  2. **Document it** as a separate issue or review finding
  3. **Move on** without implementing the out-of-scope fix

  This prevents merge conflicts, scope creep, and wasted review cycles. Scope boundaries are especially critical in parallel batch orchestration where multiple agents work simultaneously.
- Follow all best practices in `docs/best-practices/`
- Never expose raw internal values (enum codes, IDs) directly in user-facing output — use display labels
- Extract duplication only when the same logic appears 3+ times and the abstraction is clear
- Do not refactor code outside the scope of the current change
- Do not add comments to code you didn't modify

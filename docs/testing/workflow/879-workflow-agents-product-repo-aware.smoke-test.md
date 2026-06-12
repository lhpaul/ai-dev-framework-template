# Smoke Test Runbook: Workflow Agents Product Repository Awareness

**Feature**: Workflow agents and command wrappers product repository awareness
**Spec**: [1_879-workflow-agents-product-repo-aware_specs.md](../../specs/developments/20260610165352_879-workflow-agents-product-repo-aware/1_879-workflow-agents-product-repo-aware_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are reviewing the implementation PR for #879.
- [ ] #874 and #875 are already merged into `develop-workflow-hub-mode`.
- [ ] The PR targets `develop-workflow-hub-mode`.
- [ ] The implementation diff is available locally.

---

## Test Data

| Item | Value |
| --- | --- |
| Repository mode guide | `docs/workflow/development-workflow/repository-modes.md` |
| Claude agents | `.claude/agents/*.md` |
| Cursor agents | `.cursor/agents/*.md` |
| Codex skills | `.codex/skills/*/SKILL.md` |
| Command aliases | `.agents/skills/*/SKILL.md` |
| Prompt tests | `scripts/development-workflow/tests/test-workflow-agent-product-repo-guidance.sh` |

---

## Smoke Test Steps

### Step 1: Verify Single-Repo Prompt Compatibility

**Maps to**: AC1, AC10

1. Inspect orchestrator and command-wrapper guidance for Claude, Cursor, Codex,
   and `.agents`.
2. Confirm missing mode or `single_repo` still treats the current repository as
   the workflow owner.
3. Confirm no single-repo path requires a product repository selector.

**Expected result**: Existing single-repository workflow usage remains valid.

### Step 2: Verify Item-Orchestrator Context Declaration

**Maps to**: AC2, AC9

1. Inspect item-orchestrator guidance across runner surfaces.
2. Confirm workflow hub implementation handoffs include selected product
   repository name and local path or remote identity before mutation.
3. Confirm missing or ambiguous product repository context stops mutation.

**Expected result**: Item orchestration cannot silently mutate the hub for
product implementation work.

### Step 3: Verify Planning Agent Ownership

**Maps to**: AC3

1. Inspect product-manager and tech-lead prompts.
2. Confirm specs and plans are created in the documented owner repository for
   `single_repo`, `workflow_hub`, and `product_repo` modes.
3. Confirm workflow hub mode keeps spec and plan artifacts hub-owned unless
   future docs explicitly say otherwise.

**Expected result**: Planning artifacts are not duplicated into product repos.

### Step 4: Verify Developer Agent Product-Repo Routing

**Maps to**: AC4, AC9

1. Inspect developer prompts for Claude and Cursor plus Codex implementer
   skill guidance.
2. Confirm implementation branches, commits, file edits, and implementation PRs
   target the selected product repository in workflow hub mode.
3. Confirm the prompt requires stopping before mutation when context is missing
   or ambiguous.

**Expected result**: Developer work is routed to the selected product repo.

### Step 5: Verify Reviewer and Smoke-Tester Ownership Reporting

**Maps to**: AC5, AC6

1. Inspect spec, plan, code-reviewer, and smoke-tester prompts.
2. Confirm each prompt requires reporting the artifact repository owner.
3. Confirm spec/plan review stays hub-owned and code review can target product
   implementation PRs.

**Expected result**: Review and smoke-test summaries identify the repository
whose artifact was evaluated.

### Step 6: Verify Reviewer-Loop Wrapper Thinness

**Maps to**: AC7, AC8

1. Inspect reviewer-loop wrappers and skills.
2. Confirm they call canonical protocols/scripts and shared repository-context
   helpers.
3. Confirm they do not embed independent product repository selection rules.

**Expected result**: Wrappers remain thin and consistent across runner surfaces.

### Step 7: Run Automated Prompt Validation

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-agent-product-repo-guidance.sh
   bash scripts/development-workflow/tests/test-install-codex-skills.sh
   ```

2. Run markdown validation from the implementation plan.

**Expected result**: Prompt-fragment tests and skill-install regression pass.

---

## Assertions Checklist

- [ ] AC1: Portfolio orchestrator / run-work preserves current `single_repo`
      behavior.
- [ ] AC2: Item orchestrator states selected product repository before
      mutation in workflow hub mode.
- [ ] AC3: Product-manager and tech-lead agents create specs/plans in the
      documented owner repository.
- [ ] AC4: Developer agents create implementation branches, commits, and PRs in
      the selected product repository.
- [ ] AC5: Reviewers resolve and report repository owner.
- [ ] AC6: Smoke testers resolve and report repository owner.
- [ ] AC7: Reviewer-loop wrappers use shared repository-context behavior.
- [ ] AC8: Claude, Cursor, and Codex wrappers remain thin.
- [ ] AC9: Missing or ambiguous product repository context stops mutation.
- [ ] AC10: `single_repo` prompts remain valid without `--repo`.

---

## Seed Data Reference

No seed data is required. The test harness inspects committed prompt files.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Prompt test misses a runner surface | Inventory list was not updated | Re-run the file inventory query and add assertions for the missing surface. |
| Single-repo prompts mention mandatory `--repo` | Workflow hub language was added unconditionally | Qualify product selection language with `workflow_hub` mode. |
| Wrapper contains custom selection rules | Wrapper was made too thick | Replace custom rules with references to canonical scripts/helpers. |
| Developer prompt lacks pre-mutation context | Context statement was only added to summary text | Add an explicit before-mutation requirement. |

---

## Known Limitations

- This smoke test validates prompt and wrapper guidance. It does not execute
  real cross-repository implementation work.

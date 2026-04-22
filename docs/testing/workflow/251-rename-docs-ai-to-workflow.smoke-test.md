# Smoke Test Runbook: Rename docs/ai/ to docs/workflow/

**Feature**: #251 — Rename docs/ai/ to docs/workflow/
**Spec**: N/A (Refactor — no spec)
**Implementation plan**: `docs/specs/developments/20260422093111_251-rename-docs-ai-to-workflow/2_251-rename-docs-ai-to-workflow_implementation-plan.md`
**Created in**: Plan Ready stage

---

## Prerequisites

Before running this smoke test:

- [ ] Implementation branch `refactor/251-rename-docs-ai-to-workflow` is checked out (or the PR is merged to `develop`)
- [ ] Working directory is clean (`git status --porcelain` returns empty output)
- [ ] Run from the repository root

---

## Test Data

No test data required — this is a pure structural refactor verified via filesystem and grep.

---

## Smoke Test Steps

### Step 1: Verify `docs/ai/` is gone and `docs/workflow/` exists

```bash
# docs/ai/ must not exist
test ! -d docs/ai && echo "PASS: docs/ai/ does not exist" || echo "FAIL: docs/ai/ still exists"

# docs/workflow/ must exist with expected subtrees
test -d docs/workflow/development-workflow/protocols && echo "PASS: protocols dir present" || echo "FAIL: protocols dir missing"
test -d docs/workflow/development-workflow/integrations && echo "PASS: integrations dir present" || echo "FAIL: integrations dir missing"
test -d docs/workflow/development-workflow/templates && echo "PASS: templates dir present" || echo "FAIL: templates dir missing"
test -d docs/workflow/setup && echo "PASS: setup dir present" || echo "FAIL: setup dir missing"
```

**Expected result**: All five lines print PASS.

### Step 2: Verify zero residual `docs/ai` references (with and without trailing slash)

```bash
find . -type f \
  \( -name "*.md" -o -name "*.mdc" -o -name "*.yaml" -o -name "*.yml" \
     -o -name "*.sh" -o -name "*.json" \) \
  -not -path "./.git/*" \
  -not -path "./.claude/worktrees/*" \
  -not -path "./docs/specs/developments/20260422093111_251-rename-docs-ai-to-workflow/*" \
  -not -path "./docs/testing/workflow/251-rename-docs-ai-to-workflow.smoke-test.md" \
  -not -path "./CHANGELOG.md" \
  -print0 | xargs -0 grep -l "docs/ai" | wc -l
```

**Expected result**: Output is `0`. The excluded paths intentionally retain `docs/ai` as subject matter: the plan directory and this smoke test file (describing the rename), and `CHANGELOG.md` (whose new entry names the old path for historical reference). Any non-zero count for other files is a failure; inspect with:

```bash
find . -type f \
  \( -name "*.md" -o -name "*.mdc" -o -name "*.yaml" -o -name "*.yml" \
     -o -name "*.sh" -o -name "*.json" \) \
  -not -path "./.git/*" \
  -not -path "./.claude/worktrees/*" \
  -not -path "./docs/specs/developments/20260422093111_251-rename-docs-ai-to-workflow/*" \
  -not -path "./docs/testing/workflow/251-rename-docs-ai-to-workflow.smoke-test.md" \
  -not -path "./CHANGELOG.md" \
  -print0 | xargs -0 grep -n "docs/ai"
```

### Step 3: Verify key protocol files are accessible at new paths

```bash
test -f docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md && echo "PASS" || echo "FAIL: 91 protocol missing"
test -f docs/workflow/development-workflow/protocols/03-implement-development-protocol.md && echo "PASS" || echo "FAIL: 03 protocol missing"
test -f docs/workflow/development-workflow/README.md && echo "PASS" || echo "FAIL: workflow README missing"
test -f docs/workflow/setup/protocol.md && echo "PASS" || echo "FAIL: setup protocol missing"
test -f docs/workflow/development-workflow/agent-model-config.md && echo "PASS" || echo "FAIL: agent-model-config missing"
```

**Expected result**: All lines print PASS.

### Step 4: Verify `workflow-batch-plan.sh` references the new path

```bash
grep "PROTOCOLS_PREFIX" scripts/development-workflow/workflow-batch-plan.sh
```

**Expected result**: Output contains `docs/workflow/development-workflow/protocols/` (not `docs/ai/`).

### Step 5: Verify `sync-template` commands reference the new always-sync path

```bash
grep "docs/workflow" .claude/commands/sync-template.md | head -3
grep "docs/workflow" .claude/skills/sync-template.md | head -3
```

**Expected result**: Both grep commands return lines containing `docs/workflow/` (not `docs/ai/`).

### Step 6: Verify agent definitions point to new paths

```bash
grep "docs/ai" .claude/agents/*.md | wc -l
```

**Expected result**: Output is `0`.

### Step 7: Verify `AGENTS.md` and `README.md` reference new path

```bash
grep "docs/workflow/development-workflow" AGENTS.md | wc -l
grep "docs/ai" AGENTS.md | wc -l
grep "docs/workflow/development-workflow" README.md | wc -l
grep "docs/ai" README.md | wc -l
```

**Expected result**: First and third counts are greater than 0; second and fourth counts are 0.

---

## Assertions Checklist

- [ ] `docs/ai/` directory does not exist after implementation
- [ ] `docs/workflow/` contains the complete subtree (`development-workflow/`, `setup/`, with all child directories)
- [ ] Zero occurrences of `docs/ai` (with or without trailing slash) in any tracked file (excluding `.claude/worktrees/`, `.git/`, `CHANGELOG.md`, this smoke-test file itself, and the implementation plan under `docs/specs/developments/20260422093111_251-rename-docs-ai-to-workflow/` — those three paths intentionally retain `docs/ai` as subject matter)
- [ ] `workflow-batch-plan.sh` `PROTOCOLS_PREFIX` variable uses `docs/workflow/` prefix
- [ ] `sync-template` always-sync path list entries use `docs/workflow/`
- [ ] All `.claude/agents/*.md` files reference `docs/workflow/` only
- [ ] `AGENTS.md` references `docs/workflow/` for all workflow protocol links

---

## Seed Data Reference

None required.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `docs/ai/` still exists | `git mv` was not staged or commit was not made | Verify `git status` shows rename staged; re-run `git mv docs/ai docs/workflow` |
| Residual `docs/ai/` references found | One or more files missed in substitution pass | Run grep to find them; apply substitution and add to commit |
| `workflow-batch-plan.sh` fails at runtime | `PROTOCOLS_PREFIX` not updated | Edit line 45 of `workflow-batch-plan.sh` to use `docs/workflow/development-workflow/protocols/` |

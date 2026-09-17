# Framework-Mode Work-Item Classification — Smoke Test

**Plan**: [1583 implementation plan](../../specs/developments/20260911230727_1583-template-mode-type-routing/2_1583-template-mode-type-routing_implementation-plan.md)
**Spec**: [1583 spec](../../specs/developments/20260911230727_1583-template-mode-type-routing/1_1583-template-mode-type-routing_specs.md)

Manual smoke checks after the implementation PR merges (or on the feature branch before
readiness). Requires `gh` auth and a GitHub Projects board when exercising live tracker steps;
script-level checks use the regression harness first.

---

## Preconditions

- Repository declares framework mode: `template.is_template: true` in `.ai-dev-workflow.yaml`.
- On `develop` or the implementation branch with this feature applied.
- Regression harness green:

```bash
bash scripts/development-workflow/tests/test-add-backlog-item.sh
bash scripts/development-workflow/tests/test-framework-mode-type-routing.sh
```

(Use `test-workflow-lib-github-projects.sh` instead of the dedicated file if the plan collapses
suites.)

---

## Step 1: Creation refusal (framework mode)

1. Dry-run the creation helper against a test title (do **not** keep the issue if created by
   mistake — prefer the automated test fixture for CI):

```bash
./scripts/development-workflow/add-backlog-item.sh create \
  --title "SMOKE 1583 refuse workflow" \
  --body "Ephemeral smoke — delete if created" \
  --type Workflow
```

**Expected**: Non-zero exit, stderr names Workflow as invalid and lists Feature/Bug/Refactor, no
issue URL on stdout.

2. Repeat with `--type Bug`.

**Expected**: Success (issue URL printed) — delete the smoke issue from the tracker afterward.

---

## Step 2: Framework-item lookup semantics

1. With framework mode enabled, run the documented lookup wrapper:

```bash
./scripts/development-workflow/list_open_framework_items.sh
```

**Expected**: Lines include `FRAMEWORK_ITEMS_LOOKUP_STATUS` and `FRAMEWORK_ITEMS_JSON=…`.
Status is `ok` when open items exist (any Type), `empty` only for a completed read with no
open items, and `unavailable` with a reason when the tracker read fails.

2. Temporarily unset `GITHUB_PROJECT_NUMBER` and remove `project_number` from config in a local
   test checkout **or** use the harness fixture for unavailable mode.

**Expected (framework mode)**: Unavailable reporting with reason — not silent "no framework
items".

---

## Step 3: Backlog routing gate

1. Identify a Backlog issue classified `Workflow` (or create one in a consumer test repo — not
   in this template repo after Step 1).

2. Run the backlog type gate for a single-item caller:

```bash
./scripts/development-workflow/framework-mode-backlog-type-gate.sh \
  --issue <number> --status Backlog --caller single
```

**Expected**: `RESULT=stop`, `STOP_CONDITION=missing_tracker_context`, message names
re-classification.

3. Repeat with `--caller scan`.

**Expected**: `RESULT=hold` (not a global stop).

4. Pick an item past Backlog (e.g. Plan Ready) that still shows Type `Workflow`.

**Expected**: `RESULT=pass`.

---

## Step 4: Guidance spot-check

1. Open `AGENTS.md` Tracker Classification and
   `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md`.

**Expected**: Framework-mode rule visible; no instruction to file framework work as Workflow in
this repository.

---

## Pass criteria

All steps match expected behavior; regression harness from Preconditions remains green.

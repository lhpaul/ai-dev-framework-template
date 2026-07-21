# Smoke Test Runbook: Graphical Design Assets in the Workflow

**Feature**: Graphical Design Assets in the Workflow
**Spec**: `docs/specs/developments/20260721132941_1282-graphical-design-assets-workflow/1_1282-graphical-design-assets-workflow_specs.md`
**Created in**: Plan Ready stage

---

## Prerequisites

- [ ] Clean checkout of the implementation branch (or merged `develop` after merge).
- [ ] Ability to create a temporary directory with sample files (a tiny `.png` or
      `.html` mockup and a clearly non-design `.log`).
- [ ] Tracker access for a disposable test backlog item (GitHub Issues / Projects
      or the configured provider), or dry-run review of protocol text when live
      create is unavailable — note the limitation in the report.

---

## Test Data

| Item | Value |
| --- | --- |
| Likely design fixture | Temporary `.png` or `.html` file under a disposable temp directory |
| Non-design fixture | Temporary `.log` file in the same temp directory |
| Ambiguous fixture (optional) | Temporary `.md` or `.txt` file |
| Canonical convention | `docs/workflow/development-workflow/design-assets.md` |
| Add-backlog protocol | `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md` |

---

## Smoke Test Steps

### Step 1: Canonical convention exists

**Maps to**: AC4, AC8

1. Open `docs/workflow/development-workflow/design-assets.md`.
2. Confirm it defines recognition heuristics, storage (`tracker attachments` +
   `<dev-folder>/assets/`), discovery order, issue-body `## Design assets`
   template, and lightweight fidelity expectations.

**Expected result**: One canonical convention doc covers capture, storage,
discovery, and fidelity without describing a visual-regression platform.

### Step 2: Add-backlog capture path

**Maps to**: AC1, AC2, AC3, AC8

1. Read protocol `00` and the Claude/Cursor/Codex add-backlog command surfaces.
2. Confirm they instruct agents to recognize likely design files, ask one brief
   clarifying question for ambiguous intent, attach or stage confirmed assets,
   and record locations plus later-stage usage in the item body.
3. If live create is available: create one disposable backlog item while
   supplying the likely design fixture (and, optionally, the ambiguous fixture
   after answering the clarifying question). Confirm the body has `## Design
   assets` and that the design file was attached or path-noted. Confirm the
   `.log` was not staged as a design reference.
4. If live create is unavailable: mark this step as documentation-verified and
   record the limitation.

**Expected result**: Capture rules are present on all add-backlog surfaces; live
create (when available) yields exactly one item with design-asset recording and
no forced staging of clearly non-design files.

### Step 3: Agent discovery rules

**Maps to**: AC4, AC5

1. Read discovery order in `design-assets.md` and the brief pointers on
   product-manager / tech-lead / developer / smoke-tester agent (and matching
   Codex skill) surfaces.
2. Confirm agents are told to check issue-body notes, tracker attachments,
   linked files, and `<dev-folder>/assets/` before UI-facing plan/smoke work.
3. Confirm absence of assets means continue without inventing a baseline.

**Expected result**: Discovery is documented and mirrored; no-assets is not a
failure.

### Step 4: Plan and smoke fidelity hooks

**Maps to**: AC5, AC6, AC7

1. Read protocols `02` and `04`, plus the smoke runbook template if updated.
2. Confirm that when assets exist, plan/runbook authoring requires at least one
   expected-vs-actual fidelity step naming the reference asset(s).
3. Confirm smoke execution records PASS/FAIL with expected-vs-actual detail for
   those steps.
4. Confirm that when no assets exist, fidelity steps are omitted rather than
   invented.

**Expected result**: Lightweight fidelity hooks exist; no pixel-diff or CI
screenshot suite is required.

### Step 5: Out-of-scope boundaries

**Maps to**: AC8, AC9

1. Confirm docs explicitly leave `/merged-qa` (#1283) and design-reviewer-as-
   primary fidelity gate out of scope.
2. Confirm design-reviewer agent files were not changed to become the primary
   fidelity gate.
3. Confirm no new visual-regression CI workflow was introduced for this item.

**Expected result**: MVP stays convention + discovery + smoke hooks only.

### Last Step: Validate & Shut Down

- Verify all assertions below.
- Delete any temporary fixture files and close/delete the disposable backlog
  item if one was created.

---

## Assertions Checklist

- [ ] AC1: Likely design files are recognized and attached/staged per convention.
- [ ] AC2: Ambiguous intent asks one clarifying question; still exactly one item.
- [ ] AC3: Item body records asset locations and later-stage fidelity usage.
- [ ] AC4: Documented discovery surfaces locate tracker and/or `assets/` files.
- [ ] AC5: No assets → no invented baseline and no spurious fidelity failure.
- [ ] AC6: Assets present → smoke runbook includes expected-vs-actual fidelity step.
- [ ] AC7: Fidelity step results record PASS/FAIL with expected-vs-actual detail.
- [ ] AC8: Docs/commands cover capture, storage, discovery, and hooks without a
      visual-regression platform.
- [ ] AC9: `/merged-qa` (#1283) and design-reviewer-as-primary fidelity gate remain
      out of scope.

---

## Known Limitations

- Live tracker create/attach may be skipped when auth or provider APIs are
  unavailable; in that case Steps 2 live path is documentation-verified only.
- Fidelity checks are lightweight human/agent comparisons, not automated pixel
  diffs.

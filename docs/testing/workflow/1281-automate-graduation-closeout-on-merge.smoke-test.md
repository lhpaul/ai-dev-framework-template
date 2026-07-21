# Smoke Test Runbook: Automate Graduation Closeout on Merge

**Feature**: Automate epic/sub-item terminal status when a graduation PR merges (issue #1281)
**Spec**: [docs/specs/developments/20260721132930_1281-automate-graduation-closeout-on-merge/1_1281-automate-graduation-closeout-on-merge_specs.md](../../specs/developments/20260721132930_1281-automate-graduation-closeout-on-merge/1_1281-automate-graduation-closeout-on-merge_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Implementation includes
      `scripts/development-workflow/graduation-closeout-from-merged-pr.sh` and the
      graduation path in `.github/workflows/update-tracker-on-merge.yml`.
- [ ] Existing `scripts/development-workflow/graduation-closeout.sh` is present
      and unchanged in closeout policy.
- [ ] `gh` CLI is authenticated for optional live checks, or mocked unit tests
      are available.
- [ ] Project token/vars used by merge-time tracker updates are configured when
      exercising the live Actions path.

---

## Test Data

| Item | Value |
| ---- | ----- |
| Integration slug | `test-1281-closeout-automation` |
| Integration branch | `develop-test-1281-closeout-automation` |
| Graduation PR | Merged PR from that head into `develop` |
| Parent epic | Issue with discoverable sub-items (native or `integration-branch:<slug>`) |
| Delivered sub-item | Closed or open issue that should become terminal |
| Optional/excluded sub-item | Issue labeled `optional` / `deferred` / excluded |
| Deferred epic | Same epic with label `defer-epic-close` for AC4 |
| Non-graduation control PR | Merged `fix/*` or `feature/*` PR (mapping unchanged) |

---

## Smoke Test Steps

### Step 1: Primary path still documented (Step 5)

**Maps to**: AC1, BR-1

1. Open `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md`.
2. Confirm Step 5 still instructs operators to run `graduation-closeout.sh` with
   `--slug`, `--graduation-pr`, and `--epic`.
3. Confirm the protocol states merge-time automation is a fallback, not a
   replacement for Step 5.

**Expected result**: Primary path remains explicit; fallback is documented.

### Step 2: Merge-time automation invokes the same reconciler

**Maps to**: AC2

1. Inspect `.github/workflows/update-tracker-on-merge.yml` and
   `graduation-closeout-from-merged-pr.sh`.
2. Confirm a merged `develop-<slug>` head runs the wrapper, which execs
   `graduation-closeout.sh` (same policy, not a second reconciler).
3. Run unit tests:
   `bash scripts/development-workflow/tests/test-graduation-closeout-from-merged-pr.sh`
   (and existing `test-graduation-closeout.sh`).

**Expected result**: Graduation merges trigger closeout; tests pass; job logs
show run/success (or fail-closed with a clear error).

### Step 3: Idempotent double-run

**Maps to**: AC3

1. After a successful closeout (agent or automation), re-run the wrapper or
   Step 5 against the same graduation PR.
2. Confirm already-terminal delivered items are reported without backward moves
   and issues are not reopened.

**Expected result**: Second run is safe; board state stable.

### Step 4: Deferred epic close honored by automation

**Maps to**: AC4

1. Run primary closeout with `--defer-epic-close` and confirm the epic receives
   the durable `defer-epic-close` label (or apply the label explicitly).
2. Run automation/wrapper against the merged graduation PR afterward.
3. Confirm delivered non-excluded sub-items reconcile and the epic remains open.

**Expected result**: Automation honors the durable deferral signal and does not
force-close the epic.

### Step 5: Excluded / optional sub-items remain open

**Maps to**: AC5

1. Ensure at least one sub-item carries an optional/deferred/excluded label (or
   is passed via `--exclude-issue` on the primary path).
2. Run closeout (agent or automation).
3. Confirm those issues remain open and appear in skipped/disposition output.

**Expected result**: No silent close of disposition-required items.

### Step 6: Terminal status resolution order

**Maps to**: AC6

1. Inspect `graduation-closeout.sh` (or tests) for status resolution:
   `GITHUB_PROJECT_STATUS_GRADUATED` → `GITHUB_PROJECT_STATUS_MERGED` → `Merged`.
2. Confirm the automation path does not override that order.

**Expected result**: Resolution order unchanged.

### Step 7: Fail closed on incomplete discovery

**Maps to**: AC7

1. Exercise wrapper fixtures (or a live PR) with missing/ambiguous epic discovery
   or no delivered candidates.
2. Confirm non-zero exit / failed job and no invented terminal statuses.

**Expected result**: Fail closed; operator must repair before claiming cleanup
complete.

### Step 8: Non-graduation merge mapping unchanged

**Maps to**: AC8

1. Review `update-tracker-on-merge.yml` and
   `check-tracker-merge-mapping.sh` output.
2. Confirm `spec/*` → Spec Ready, `implementation-plan/*` → Plan Ready, and
   impl branches → Merged (+ close) remain the product mapping.
3. Optionally merge or dry-inspect a non-graduation control PR path.

**Expected result**: Non-graduation behavior unchanged.

### Step 9: Orthogonal to sibling items

**Maps to**: AC9

1. Confirm the implementation PR does not modify #1282/#1284 branches, specs, or
   plans.
2. Confirm docs do not introduce a hard dependency on those issues.

**Expected result**: No cross-item coupling.

---

## Edge Cases

| Case | Expected |
| ---- | -------- |
| Head `feature/…` merges to `develop` | Existing tracker path; no graduation closeout |
| Head `develop-bad slug` (invalid) | Not treated as valid graduation; fail/skip without closeout mutations |
| Two candidate epics after discovery | Fail closed |
| Actions project token missing on graduation path | Visible job failure (not silent success) |

---

## Sign-off

| Role | Name | Date | Result |
| ---- | ---- | ---- | ------ |
| Implementer | | | |
| Reviewer | | | |

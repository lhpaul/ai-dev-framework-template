# Smoke Test Runbook: Stale Tracker Status Transitions

**Feature**: Fix stale tracker status transitions in orchestrator pre-dispatch (#487)
**Spec**: [docs/specs/developments/20260506194337_487-stale-tracker-status-transitions/1_487-stale-tracker-status-transitions_specs.md](../../specs/developments/20260506194337_487-stale-tracker-status-transitions/1_487-stale-tracker-status-transitions_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation is merged to `develop`.
- [ ] You have `gh` CLI authenticated against the repository.
- [ ] `scripts/development-workflow/check-tracker-merge-mapping.sh` exists and is executable.
- [ ] `.github/workflows/update-tracker-on-merge.yml` is present and unchanged from the merged implementation.

---

## Test Data

| Item | Value |
|---|---|
| Workflow file | `.github/workflows/update-tracker-on-merge.yml` |
| New verification script | `scripts/development-workflow/check-tracker-merge-mapping.sh` |
| Protocol 90 | `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` |
| Protocol 91 | `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` |
| Simulated issue number (Case B) | Any non-existent issue number, e.g. `99999` |

---

## Smoke Test Steps

### Step 1: Verify `check-tracker-merge-mapping.sh` on correct mapping (AC-9)

**Maps to**: Acceptance Criterion AC-9

1. From the repository root, run:

   ```bash
   bash scripts/development-workflow/check-tracker-merge-mapping.sh
   ```

2. Observe the output.

**Expected result**: Script exits 0 and prints a line confirming all mappings are correct (e.g.,
`All mappings correct.`). There must be no `ERROR:` lines.

---

### Step 2: Verify `check-tracker-merge-mapping.sh` detects a wrong mapping (AC-9)

**Maps to**: Acceptance Criterion AC-9

1. Create a temporary copy of the workflow file:

   ```bash
   cp .github/workflows/update-tracker-on-merge.yml /tmp/update-tracker-on-merge.yml.bak
   ```

2. In the workflow file, manually change the `TARGET_STATUS` for `spec/*` from `"Spec Ready"` to
   `"Merged"` (simulate a regression).

3. Run the script:

   ```bash
   bash scripts/development-workflow/check-tracker-merge-mapping.sh
   ```

4. Restore the original file:

   ```bash
   cp /tmp/update-tracker-on-merge.yml.bak .github/workflows/update-tracker-on-merge.yml
   ```

**Expected result**: Script exits 1 and prints an `ERROR:` line describing the incorrect mapping
for `spec/*`. No other mappings should be reported as wrong.

---

### Step 3: Verify `update-tracker-on-merge.yml` mapping summary in Actions log (AC-1/AC-2/AC-3)

**Maps to**: Acceptance Criteria AC-1, AC-2, AC-3

1. Navigate to the repository's GitHub Actions page and open the most recent run of the
   "Update tracker status on PR merge" workflow (or trigger a test by merging a test PR).
2. Expand the `update-tracker` job.
3. Look for the mapping-summary log step.

**Expected result**: The log step output lists the branch prefix → target status mapping in
human-readable form (e.g., `spec/* → Spec Ready`, `implementation-plan/* → Plan Ready`,
`feature/* → Merged`, etc.).

---

### Step 4: Review `post-merge-cleanup.sh` mapping consistency (AC-4)

**Maps to**: Acceptance Criterion AC-4

1. Open `scripts/development-workflow/post-merge-cleanup.sh`.
2. Locate the section after the branch-type classification (`BRANCH_TYPE` variable).
3. Verify the three mapping outcomes:
   - `BRANCH_TYPE=spec` → `update_tracker_status_best_effort "..." "Spec Ready"`
   - `BRANCH_TYPE=plan` → `update_tracker_status_best_effort "..." "Plan Ready"`
   - `BRANCH_TYPE=implementation` → `update_tracker_status_best_effort "..." "Merged"`

**Expected result**: All three mappings match the expected values. No `BRANCH_TYPE` path sets
status to "Merged" for spec or plan branches.

---

### Step 5: Review Protocol 91 Step 10 mapping rule (AC-5)

**Maps to**: Acceptance Criterion AC-5

1. Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.
2. Navigate to Step 10 (Post-Merge Status Transitions).
3. Verify the rule table lists all three correct mappings and includes an explicit note
   prohibiting "Merged" for spec or plan merges.

**Expected result**: The table shows `spec/*` → `Spec Ready`, `implementation-plan/*` →
`Plan Ready`, implementation branches → `Merged`. A "Key rules" note explicitly states that
spec/plan PRs must not be set to "Merged".

---

### Step 6: Verify stale "In Development" detection rule in Protocol 90 (AC-6, AC-7, AC-8, AC-10)

**Maps to**: Acceptance Criteria AC-6, AC-7, AC-8, AC-10

1. Open `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`.
2. Locate Step 2 (Determine Eligibility and Priority) or the sub-step immediately following it.
3. Confirm a new sub-step exists that:
   - Applies when tracker status = "In Development".
   - Performs a branch and PR existence check.
   - Corrects to "Plan Ready" when no branch or PR is found.
   - Emits a log line prefixed `STALE_STATUS_CORRECTION:`.
   - Notes that the item is dispatched at most once in the run after correction.
   - Notes that a branch or PR being present invalidates the stale determination.

**Expected result**: All six requirements above are present in the protocol text.

---

### Step 7: Verify stale "In Development" detection rule in Protocol 91 (AC-6, AC-7, AC-8, AC-10)

**Maps to**: Acceptance Criteria AC-6, AC-7, AC-8, AC-10

1. Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.
2. Locate Step 2 (Determine the Next Deterministic Action).
3. Confirm a new rule exists (near the "Pre-dispatch branch check" sub-section) that:
   - Applies when tracker status = "In Development" AND the runner was dispatched from Protocol 90.
   - Performs the same branch and PR existence check as Protocol 90.
   - Corrects to "Plan Ready" and emits a `STALE_STATUS_CORRECTION:` log line.
   - States that direct human invocations outside Protocol 90/91 are out of scope for automatic
     correction (BR-7).

**Expected result**: All four requirements above are present in the protocol text.

---

### Last Step: Validate & Shut Down

- Verify all assertions in the checklist below are met.
- Restore any temporarily modified files if not already done.

---

## Assertions Checklist

- [ ] **AC-1**: `update-tracker-on-merge.yml` maps `spec/*` → `Spec Ready`. Confirmed by
  `check-tracker-merge-mapping.sh` exit 0 (Step 1) and manual review (Step 3).
- [ ] **AC-2**: `update-tracker-on-merge.yml` maps `implementation-plan/*` → `Plan Ready`.
  Confirmed by `check-tracker-merge-mapping.sh` exit 0 (Step 1) and manual review (Step 3).
- [ ] **AC-3**: `update-tracker-on-merge.yml` maps implementation branches → `Merged`. Confirmed
  by `check-tracker-merge-mapping.sh` exit 0 (Step 1).
- [ ] **AC-4**: `post-merge-cleanup.sh` uses Spec Ready / Plan Ready / Merged consistently with
  the workflow. Confirmed by manual review (Step 4).
- [ ] **AC-5**: Protocol 91 Step 10 explicitly states the branch-type → status table and
  prohibits "Merged" for spec/plan merges. Confirmed by manual review (Step 5).
- [ ] **AC-6**: Protocol 90 and Protocol 91 both contain stale "In Development" detection and
  correction rules. Confirmed by manual review (Steps 6–7).
- [ ] **AC-7**: The correction rule notes the item is dispatched at most once. Confirmed by
  manual review (Steps 6–7).
- [ ] **AC-8**: The correction rule invalidates when a branch or PR is present. Confirmed by
  manual review (Steps 6–7).
- [ ] **AC-9**: `check-tracker-merge-mapping.sh` exits 0 on correct mapping and exits 1 on
  incorrect mapping. Confirmed by Steps 1–2.
- [ ] **AC-10**: Both protocol rules emit a `STALE_STATUS_CORRECTION:` log line when a correction
  is made. Confirmed by manual review (Steps 6–7).

---

## Seed Data Reference

Not applicable — this feature operates on tracker state and VCS state, not application data.

| Entity | Scenario | How to load |
|---|---|---|
| (none) | — | — |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `check-tracker-merge-mapping.sh` exits 1 on an unmodified repo | The YAML structure of the detect step changed after the plan was written | Re-read the `detect` step in `update-tracker-on-merge.yml` and update the script's parsing pattern to match the current YAML layout |
| Step 6 or Step 7 sub-step not found in protocol | The plan edits were partially applied | Re-read the affected section header and apply the remaining text |
| The mapping-summary log step is absent from the Actions log | The workflow step was not committed or the test PR targeted the wrong branch | Confirm the implementation commit includes the new step in `.github/workflows/update-tracker-on-merge.yml` |

---

## Known Limitations

- The smoke test for Case B (stale "In Development") verifies the protocol text only; an
  end-to-end test of the actual correction (triggering the orchestrator against a real stale item)
  requires a live orchestrator run with a purpose-built test issue and cannot be performed as a
  simple runbook step.

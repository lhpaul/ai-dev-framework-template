# Smoke Test Runbook: Workflow Hub Product Repository Commands

**Feature**: Workflow hub product repository sync and status scripts
**Spec**: [1_877-workflow-hub-product-repo-sync-status-scripts_specs.md](../../specs/developments/20260610164114_877-workflow-hub-product-repo-sync-status-scripts/1_877-workflow-hub-product-repo-sync-status-scripts_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are reviewing the implementation PR for #877.
- [ ] #875 is already merged into `develop-workflow-hub-mode`.
- [ ] The PR targets `develop-workflow-hub-mode`.
- [ ] The implementation diff is available locally.

---

## Test Data

| Item | Value |
| --- | --- |
| Status command | `scripts/development-workflow/hub-status.sh` |
| Sync command | `scripts/development-workflow/hub-sync-product-repos.sh` |
| PR listing command | `scripts/development-workflow/hub-list-prs.sh` |
| Repository-context resolver | `scripts/development-workflow/workflow-config-resolver.py` |
| Workflow library | `scripts/development-workflow/workflow-lib.sh` |
| Command tests | `scripts/development-workflow/tests/test-workflow-hub-product-repo-commands.sh` |
| Local config | `.ai-dev-workflow.local.yaml` |

---

## Smoke Test Steps

### Step 1: Confirm Command Surfaces

**Maps to**: AC1

1. Run each command with `--help`.
2. Confirm help output explains purpose, required `workflow_hub` mode, target
   selection, and safe-failure behavior.
3. Confirm help output works even from a fixture without valid workflow hub
   configuration.

**Expected result**: Help output is available and complete for all commands.

### Step 2: Verify Wrong-Mode Failure

**Maps to**: AC2

1. Run each command from a missing-mode or explicit `single_repo` fixture.
2. Confirm each command fails before inspecting or mutating any product checkout.
3. Confirm the failure says `workflow_hub` mode is required.

**Expected result**: Commands do not act outside workflow hub mode.

### Step 3: Inspect One Product Repository

**Maps to**: AC3

1. Create or use a fixture workflow hub with one clean product repository.
2. Run:

   ```bash
   scripts/development-workflow/hub-status.sh --repo <name> --repo-root <fixture>
   ```

3. Confirm output includes local path, current branch, clean state, and remote
   inspection status.

**Expected result**: One-repository status output is readable and complete.

### Step 4: Inspect All Product Repositories

**Maps to**: AC4

1. Use a fixture with at least one clean checkout, one dirty checkout, one
   missing path, and one missing checkout.
2. Run:

   ```bash
   scripts/development-workflow/hub-status.sh --all --repo-root <fixture>
   ```

3. Confirm output reports each repository separately and ends with a final
   categorized summary.

**Expected result**: Multi-repository status does not hide mixed outcomes.

### Step 5: Verify Dirty-Checkout Refusal

**Maps to**: AC5

1. Add staged, unstaged, or untracked changes to a fixture product checkout.
2. Run sync for that repository.
3. Confirm the command refuses to overwrite the checkout and names the path.

**Expected result**: Dirty product checkouts remain untouched.

### Step 6: Verify Multi-Repository Sync Summary

**Maps to**: AC6

1. Use a fixture with one safe clean checkout and one blocked dirty checkout.
2. Run sync with `--all`.
3. Confirm the final summary separates synced repositories from blocked or
   failed repositories.

**Expected result**: Partial success and partial failure are both visible.

### Step 7: Verify Missing-Path Guidance

**Maps to**: AC7

1. Use a workflow hub fixture whose selected product repository has no local
   checkout path and no derivable default.
2. Run status or sync for that repository.
3. Confirm the output names `.ai-dev-workflow.local.yaml` and the exact entry
   the operator should add.

**Expected result**: Missing-path output gives an actionable local config fix.

### Step 8: Verify Bootstrap Confirmation

**Maps to**: AC8

1. Run the bootstrap path without confirmation and decline the prompt.
2. Confirm local config remains unchanged.
3. Run the bootstrap path with explicit confirmation.
4. Confirm only the selected repository local path entry is written.
5. Confirm no token, private key, or secret value is written.

**Expected result**: Local config writes require explicit confirmation and stay
limited to local path data.

### Step 9: Verify Pull-Request Listing

**Maps to**: AC9

1. Run PR listing for one fixture product repository.
2. Run PR listing with `--all`.
3. Confirm the command is read-only and reports PR number, title, branch, base,
   draft state, and readiness labels when remote inspection succeeds.
4. Confirm a repository declared with only a GitHub-form `git_url` is converted
   to the intended `owner/repo` slug.
5. Confirm a repository with a non-GitHub `git_url` fails clearly instead of
   targeting the workflow hub.
6. Confirm remote-inspection errors are reported per repository.

**Expected result**: PR visibility targets product repositories, not the hub.

### Step 10: Run Automated Validation

**Maps to**: AC10

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-hub-product-repo-commands.sh
   bash scripts/development-workflow/tests/test-workflow-config-resolver.sh
   ```

2. Run shell and markdown validation from the implementation plan.

**Expected result**: The command test harness passes and covers the required
success and failure paths.

---

## Assertions Checklist

- [ ] AC1: Command help explains purpose, required mode, target selection, and
      safe-failure behavior.
- [ ] AC2: Commands fail clearly outside `workflow_hub` mode before checkout
      inspection or mutation.
- [ ] AC3: One-repository status reports path, branch, cleanliness, and remote
      inspection availability.
- [ ] AC4: All-repository status reports per-repository outcomes and a final
      summary.
- [ ] AC5: One-repository sync refuses dirty checkouts.
- [ ] AC6: All-repository sync reports partial success and partial failure.
- [ ] AC7: Missing paths report the default or exact local config entry.
- [ ] AC8: Bootstrap writes require explicit confirmation.
- [ ] AC9: PR listing is read-only and supports one repository or all
      repositories.
- [ ] AC10: Shell validation covers help, wrong mode, clean status, dirty
      refusal, missing path guidance, and multi-repository summaries.

---

## Seed Data Reference

No persistent seed data is required. The automated command test should create
temporary workflow hub and product repository fixtures.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Commands inspect the hub instead of the product repo | Missing `--repo <owner/repo>` or missing `git -C <path>` use | Route every product command through resolved repository context. |
| Sync changes a dirty checkout | Dirty check happened after mutation or used the wrong path | Run `git -C <path> status --porcelain` before fetch or pull. |
| Missing-path output is generic | Resolver errors are not converted into operator guidance | Include `.ai-dev-workflow.local.yaml` and the product repo name in the message. |
| `--all` hides a blocked repo | Summary only reports final exit status | Accumulate and print per-repository outcome categories. |

---

## Known Limitations

- The default smoke path does not open, merge, or mutate product repository pull
  requests. It validates visibility and command routing only.

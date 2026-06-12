# Smoke Test Runbook: Workflow Hub Smoke Fixtures and Backwards-Compatibility Checks

**Feature**: Workflow hub smoke fixtures and backwards-compatibility checks
**Spec**: [1_883-workflow-hub-smoke-fixtures_specs.md](../../specs/developments/20260610170359_883-workflow-hub-smoke-fixtures/1_883-workflow-hub-smoke-fixtures_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are reviewing the implementation PR for #883.
- [ ] #875, #876, #877, #878, and #880 are merged into
      `develop-workflow-hub-mode`.
- [ ] The PR targets `develop-workflow-hub-mode`.
- [ ] The implementation diff is available locally.
- [ ] No live GitHub App credentials are required for the default smoke path.

---

## Test Data

| Item | Value |
| --- | --- |
| Fixture seed | `scripts/development-workflow/tests/fixtures/workflow-hub-smoke/` |
| Smoke harness | `scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh` |
| Config resolver | `scripts/development-workflow/workflow-config-resolver.py` |
| Skeleton validator | `scripts/development-workflow/validate-workflow-hub-skeletons.py` |
| Repository mode docs | `docs/workflow/development-workflow/repository-modes.md` |
| Sync manifest | `sync-manifest.yaml` |

---

## Smoke Test Steps

### Step 1: Verify Fixture Seed Safety

**Maps to**: AC1, AC2, AC9

1. Open the fixture seed directory.
2. Confirm it contains one workflow hub fixture and two dummy product repository
   definitions.
3. Confirm product names and identities are placeholders such as `mobile-app`,
   `admin-portal`, and `example/<repo>`.
4. Run the harness no-secret scan.
5. Confirm no tokens, private key paths, private repo names, customer names, or
   live secret-manager locations are committed.

**Expected result**: The fixture seed is deterministic and safe to commit.

### Step 2: Verify Config Parsing and Product Resolution

**Maps to**: AC3, AC7

1. Run the smoke harness.
2. Inspect the config parsing section.
3. Confirm both dummy product repos resolve with distinct names and identities.
4. Confirm local path override wins for one product repo.
5. Confirm `checkout_root` default resolves the second product repo.
6. Confirm ambiguous or unknown product selection fails clearly.
7. Confirm `.tmp/template-config.json` is not accepted as a checkout path
   source.

**Expected result**: The fixture proves product repository resolution without
using versioned secrets or legacy review override config as checkout data.

### Step 3: Verify Sync and Status Fixture Coverage

**Maps to**: AC4

1. Inspect the sync/status section of the harness output.
2. Confirm both product repositories are included.
3. Confirm output names the hub fixture and each product fixture.
4. Confirm missing local path or unknown product selection failures are
   actionable.
5. Confirm no default smoke check is skipped for a missing dependency.

**Expected result**: Sync/status behavior is covered for the dummy products with
no dependency skips in the final implementation PR.

### Step 4: Verify Branch and PR Dry-Run Routing

**Maps to**: AC5, AC9

1. Inspect the dry-run routing section of the harness output.
2. Confirm branch or next-action routing for product implementation work names
   the selected product repository.
3. Confirm product PR dry-run output includes the selected product repo slug,
   base branch, head branch, and title.
4. Confirm no dry-run command targets the workflow hub remote for product-owned
   work.
5. Confirm no token, private key, or secret-ref fixture value appears in
   stdout/stderr.

**Expected result**: Routing construction is validated without opening real
pull requests or exposing secrets.

### Step 5: Verify Mode-Specific Sync Scope

**Maps to**: AC6

1. Inspect the mode-scope section of the harness output.
2. Confirm `hub_only`, `product_repo_injection`, and `shared` entries are
   recognized from `sync-manifest.yaml`.
3. If runtime mode-aware sync filtering exists, confirm workflow hub and product
   repo dry-runs select the expected path groups.
4. If runtime filtering is not implemented yet, confirm the harness states that
   only classification validation is in scope for #883.

**Expected result**: Mode-scope metadata is validated without claiming runtime
filtering that does not exist.

### Step 6: Verify Single-Repository Regression

**Maps to**: AC8

1. Inspect the single-repository regression section.
2. Confirm missing mode resolves as `single_repo`.
3. Confirm explicit `single_repo` mode resolves as `single_repo`.
4. Confirm no product repository selector or workflow-hub local config is
   required for these paths.

**Expected result**: Existing adopters do not need workflow-hub product repo
configuration.

### Step 7: Verify Optional Live Validation Boundary

**Maps to**: AC10

1. Run the default harness without live flags.
2. Confirm live validation is skipped with a clear message.
3. Run the live flag without required safe-test environment variables.
4. Confirm it fails clearly before attempting auth.
5. Do not run live validation against production repositories as part of this
   smoke test.

**Expected result**: Live GitHub App validation is opt-in and separate from
default local and CI coverage.

### Step 8: Run Automated Validation

**Maps to**: AC1 through AC10

1. Run:

   ```bash
   bash scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh
   bash scripts/development-workflow/tests/test-workflow-config-resolver.sh
   bash scripts/development-workflow/tests/test-workflow-hub-skeletons.sh
   ```

2. Run shell, Python, markdown, and changelog validation from the implementation
   plan.

**Expected result**: Default non-secret workflow-hub fixture coverage and
single-repository regression coverage pass.

---

## Assertions Checklist

- [ ] AC1: Workflow hub smoke fixture exists and runs locally without secrets.
- [ ] AC2: Fixture models one hub and two dummy product repositories.
- [ ] AC3: Config parsing and product repository resolution are validated.
- [ ] AC4: Sync/status behavior is validated for dummy product repos.
- [ ] AC5: Branch and PR routing are validated in dry-run or fixture mode.
- [ ] AC6: Mode-specific sync-template behavior or classification is validated.
- [ ] AC7: Local checkout paths come from local config or documented defaults,
      not versioned secrets or `.tmp/template-config.json`.
- [ ] AC8: Single-repository regression remains green without product repo
      selection.
- [ ] AC9: CI can run non-secret coverage without private repos or live GitHub
      App credentials.
- [ ] AC10: Optional live GitHub App validation is explicit and separate from
      default coverage.

---

## Seed Data Reference

The fixture seed lives under
`scripts/development-workflow/tests/fixtures/workflow-hub-smoke/`. The harness
copies it into a temporary directory and creates local-only runtime files there.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Harness reports `SKIP_DEPENDENCY` | A required workflow-hub helper has not merged | Merge or rebase onto the dependency; the PR is not ready while default checks are skipped. |
| Fixture scan finds private details | A real repo, customer, token, or secret path was committed | Replace with `example/*` placeholders and rerun the scan. |
| Single-repo regression asks for `--repo` | Product selection leaked into default mode | Restore missing mode and `single_repo` behavior in resolver/helper logic. |
| PR dry-run targets the hub remote | Product repo routing failed | Use selected product repo context for implementation-owned PR operations. |
| Live validation runs in CI | Live flag or env gate is wired incorrectly | Remove live validation from default workflow and require explicit local opt-in. |

---

## Known Limitations

- The default fixture path validates command construction and dry-run behavior.
  It does not prove access to real private product repositories.
- Runtime mode-aware sync-template filtering may still be outside #883 if the
  sync-template implementation has not adopted `mode_scope` filtering yet.

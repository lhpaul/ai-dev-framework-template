# Smoke Test Runbook: ShellCheck Static Analysis for Workflow Scripts

**Feature**: ShellCheck static analysis CI check for `scripts/development-workflow/` shell scripts
**Spec**: [`docs/specs/developments/20260416120000_136-shellcheck-workflow-scripts/1_136-shellcheck-workflow-scripts_specs.md`](../../specs/developments/20260416120000_136-shellcheck-workflow-scripts/1_136-shellcheck-workflow-scripts_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] A GitHub repository with the ShellCheck workflow implemented and merged to `develop`
- [ ] You have write access to the repository to open test pull requests
- [ ] `gh` CLI is authenticated and working
- [ ] ShellCheck is installed locally (`shellcheck --version`) for pre-validation

---

## Test Data

| Item | Value |
|---|---|
| Target directory | `scripts/development-workflow/` |
| CI workflow file | `.github/workflows/shellcheck.yml` |
| ShellCheck severity threshold | `warning` (errors and warnings block; info and style do not) |
| Test branch prefix | `test/shellcheck-smoke-*` |

---

## Smoke Test Steps

### Step 1: Verify ShellCheck Workflow Exists

- Confirm `.github/workflows/shellcheck.yml` is present in the repository
- Confirm the workflow has a `paths` filter for `scripts/development-workflow/**/*.sh`
- Confirm the workflow uses `--severity=warning` (or equivalent)

**Expected result**: File exists, is syntactically valid YAML, and contains the correct path filter and severity flag.

---

### Step 2: Verify Baseline Is Green (Acceptance Criterion 6)

**Maps to**: Acceptance Criterion 6

1. Go to the GitHub Actions tab for the repository
2. Find the most recent run of the ShellCheck workflow (or trigger one by opening a PR that modifies a shell script)
3. Confirm the `shellcheck` job exits green

**Expected result**: The ShellCheck CI check passes (green) on the implementation PR. No `warning`- or `error`-level findings are unaddressed.

---

### Step 3: PR With a ShellCheck Warning — Check Fails (Use Case 1)

**Maps to**: Acceptance Criteria 1 and 2

1. Create a new branch: `git checkout -b test/shellcheck-smoke-fail develop`
2. Open any `.sh` file under `scripts/development-workflow/` and introduce a deliberate ShellCheck warning, for example an unquoted variable: change `echo "$VAR"` to `echo $VAR` on any line, or add a new line `VAR=hello; echo $VAR`
3. Commit and push the branch
4. Open a draft or regular PR targeting `develop`
5. Wait for the ShellCheck CI check to run (typically under 2 minutes)
6. Observe the check result

**Expected result**:
- The ShellCheck CI check is red (failed)
- The CI job log shows the specific file, line number, ShellCheck code (e.g., `SC2086`), and human-readable description of the finding
- The PR cannot be merged (the check is a required status check)

7. Clean up: close the PR and delete the branch

---

### Step 4: PR With No ShellCheck Findings — Check Passes (Use Case 1, green path)

**Maps to**: Acceptance Criterion 3

1. Create a new branch: `git checkout -b test/shellcheck-smoke-pass develop`
2. Make a trivial, correct change to any `.sh` file under `scripts/development-workflow/` (e.g., add a comment line: `# smoke test comment`)
3. Commit and push the branch
4. Open a PR targeting `develop`
5. Wait for the ShellCheck CI check to run

**Expected result**:
- The ShellCheck CI check is green (passed)
- No findings are reported

6. Clean up: close the PR and delete the branch

---

### Step 5: PR With No Shell Script Changes — Check Does Not Block (Use Case 2)

**Maps to**: Acceptance Criterion 4

1. Create a new branch: `git checkout -b test/shellcheck-smoke-noshell develop`
2. Make a change to any non-shell file (e.g., add a comment to `CHANGELOG.md` or any `.md` file)
3. Commit and push the branch
4. Open a PR targeting `develop`
5. Check the GitHub Actions tab for the PR

**Expected result**:
- Either the ShellCheck job does not appear in the PR's check list (path filter excluded it), or it appears as skipped/passed with a message indicating no shell files were changed
- The PR is not blocked by ShellCheck

6. Clean up: close the PR and delete the branch

---

### Step 6: Inline Suppression Allows False Positive to Pass (Use Case 3)

**Maps to**: Acceptance Criterion 5

1. Create a new branch: `git checkout -b test/shellcheck-smoke-suppress develop`
2. Open any `.sh` file under `scripts/development-workflow/`
3. Add a line that would normally trigger a ShellCheck warning, followed by an inline suppression directive on the preceding line:
   ```bash
   # shellcheck disable=SC2086
   echo $SOME_VAR
   ```
4. Commit and push the branch
5. Open a PR targeting `develop`
6. Wait for the ShellCheck CI check to run

**Expected result**:
- The ShellCheck CI check is green (passed)
- The suppression directive is visible in the diff and reviewable as a normal code change

7. Clean up: close the PR and delete the branch

---

### Step 7: Verify `.shellcheckrc` (If Present) (Acceptance Criterion 7)

**Maps to**: Acceptance Criterion 7

1. Check whether `.shellcheckrc` exists in the repository root: `ls .shellcheckrc`
2. If it exists, read the file and verify:
   - Each suppressed code is listed with a `disable=SCxxxx` directive
   - Each entry has a comment explaining the reason for suppression
   - No blanket file suppressions are present (only specific code suppressions)

**Expected result**:
- If `.shellcheckrc` is present: all entries are documented with reasons; no unexplained suppressions
- If `.shellcheckrc` is absent: this step passes trivially (no project-wide suppressions were needed)

---

### Last Step: Validate All Assertions

- Verify all checkboxes in the Assertions Checklist below are met
- Delete any test branches created during this smoke test

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] A CI check named (or clearly labeled) `shellcheck` runs automatically on every PR that modifies `.sh` files under `scripts/development-workflow/`
- [ ] The check exits red and displays specific findings (file, line, code, message) when any `error` or `warning`-level ShellCheck issue is present
- [ ] The check exits green when no `error` or `warning`-level findings are present
- [ ] A PR that modifies only non-shell files is not blocked by the ShellCheck check
- [ ] Suppressing a finding with an inline `# shellcheck disable=SCxxxx` directive causes the check to exit green for that finding
- [ ] The check is green from the moment the implementation PR is merged (baseline scripts are clean)
- [ ] `.shellcheckrc` (if present) is committed and lists only project-wide suppressed codes with a comment explaining the reason for each

---

## Seed Data Reference

Not applicable — this feature is CI-only and requires no application seed data.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| ShellCheck job does not appear on a PR that modifies a `.sh` file | The `paths` filter is misconfigured or the file is not under `scripts/development-workflow/` | Check `.github/workflows/shellcheck.yml` paths filter; ensure the modified file matches `scripts/development-workflow/**/*.sh` |
| ShellCheck job fails with "shellcheck: command not found" | ShellCheck is not pre-installed on the runner image | Add `sudo apt-get install -y shellcheck` as a workflow step before the ShellCheck run step |
| CI check stays pending indefinitely | GitHub Actions runner queue delay | Wait up to 5 minutes; if still pending, re-push a trivial commit to re-trigger |
| Inline suppression directive does not suppress the finding | Directive is on the wrong line or uses the wrong code | Place `# shellcheck disable=SCxxxx` on the line immediately before the flagged line; verify the correct SC code |

---

## Known Limitations

- Smoke test Steps 3–6 require opening and closing test PRs; clean up branches after each step to avoid cluttering the repository
- ShellCheck analysis covers only `scripts/development-workflow/*.sh`; scripts in other directories are out of scope for this feature (see spec Out of Scope section)
- The CI check reviews the PR branch state, not the local working tree — local fixes must be pushed before the check reflects them

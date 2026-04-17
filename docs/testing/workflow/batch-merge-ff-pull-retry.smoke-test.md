# Smoke Test Runbook: batch-merge ff-pull transient failure retry

**Feature**: Transient ff-pull failure retry in `batch-merge.sh`
**Spec**: [`docs/specs/developments/20260416120000_batch-merge-ff-pull-retry/1_batch-merge-ff-pull-retry_specs.md`](../../specs/developments/20260416120000_batch-merge-ff-pull-retry/1_batch-merge-ff-pull-retry_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Repository has a `develop` branch
- [ ] `gh` CLI is authenticated (`gh auth status` succeeds)
- [ ] You have push access to the repository
- [ ] `shellcheck` is installed (for static analysis step)
- [ ] The implementation has been applied to `scripts/development-workflow/batch-merge.sh`

---

## Test Data

| Item | Description |
|---|---|
| Test repo | The `ai-dev-framework-template` repository |
| Target branch | `develop` |
| Script under test | `scripts/development-workflow/batch-merge.sh` |

---

## Smoke Test Steps

### Step 1: Verify shellcheck passes

Run `shellcheck` against the modified script to confirm no static analysis errors were introduced.

```bash
shellcheck scripts/development-workflow/batch-merge.sh
```

**Expected result**: No errors or warnings are printed; shellcheck exits with code 0.

### Step 2: Structural verification of first-attempt ff-pull retry (AC 1 + AC 3)

This step performs structural verification of the retry path by inspecting script source and setting up a controlled environment (a temporary git repository) to confirm the logic is in place. Full automated simulation is not supported without a mock git layer (see Known Limitations).

```bash
# Create a temp repo for structural verification of the retry path
TMPDIR="$(mktemp -d)"
cd "$TMPDIR"

# Set up a local "remote" and a working clone
git init --bare remote.git
git clone remote.git local
cd local

# Create develop branch with an initial commit
git checkout -b develop
echo "init" > file.txt
git add file.txt
git commit -m "initial"
git push origin develop

# Now, in the working clone, confirm the retry path by temporarily
# wrapping git to fail once.
# (Manual verification: inspect the modified batch-merge.sh to confirm
#  the retry logic is present. Automated simulation below is illustrative.)

echo "Manual verification: open batch-merge.sh and confirm lines in cmd_merge"
echo "match the pattern: if ! git pull --ff-only ...; then sleep 2; git fetch ...; git pull --ff-only ... || merge_die; fi"
```

**Expected result**: The two-attempt block is present in `cmd_merge`. The first `git pull --ff-only` is in a conditional; a `sleep 2` + `git fetch origin "$TARGET_BASE"` precede the second attempt.

**Maps to**: Acceptance Criterion 1, Acceptance Criterion 3

### Step 3: Verify diagnostic message on stderr (AC 3)

Inspect the script source to confirm a stderr diagnostic is emitted on the retry path.

```bash
grep -n "retrying\|retry\|Retrying\|Retry" scripts/development-workflow/batch-merge.sh
```

**Expected result**: At least one line containing a retry-related message that is redirected to `>&2`, located within the `cmd_merge` function, between the first and second `git pull --ff-only` calls.

**Maps to**: Acceptance Criterion 3

### Step 4: Verify genuine divergence is still a hard failure (AC 2)

Read the script and confirm that when the retry `git pull --ff-only` fails, `merge_die` is called with the same structured output as before.

```bash
grep -A 5 "merge_die.*fast-forward" scripts/development-workflow/batch-merge.sh
```

**Expected result**: `merge_die "Could not fast-forward local '${TARGET_BASE}' from origin — resolve divergence manually"` (or equivalent wording) is called after the retry fails, ensuring `MERGE_RESULT=failed` and `ERROR_MESSAGE` are still emitted.

**Maps to**: Acceptance Criterion 2

### Step 5: Verify change isolation (AC 5)

Confirm the diff of `batch-merge.sh` is confined to the ff-pull block in `cmd_merge`.

```bash
BASE="$(git merge-base HEAD origin/develop)"
git diff "$BASE" -- scripts/development-workflow/batch-merge.sh | grep "^[+-]" | grep -v "^[+-][+-][+-]"
```

**Expected result**: Changed lines are only within the `cmd_merge` function, touching only the `git pull --ff-only` block and the adjacent retry logic. No changes to `cmd_discover`, conflict classification, `merge_die` definition, or post-merge logic.

**Maps to**: Acceptance Criterion 5

### Step 6: End-to-end batch-merge smoke test (AC 4 — no regression)

Run the existing `batch-merge.sh` discovery smoke test (or a subset of it) to confirm the clean-merge path is not broken.

```bash
# Confirm the existing batch-merge.smoke-test.md still passes for Step 1 (discovery)
# and a single-PR merge against a real ready PR (if available in the test environment).
./scripts/development-workflow/batch-merge.sh discover
```

**Expected result**: `DISCOVERY_RESULT=found` (if ready PRs exist) or `DISCOVERY_RESULT=none` (if none), with no script errors. The output contract is unchanged.

**Maps to**: Acceptance Criterion 4

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC 1: Retry path present in `cmd_merge` — when ff-pull fails, the script fetches and retries before calling `merge_die`.
- [ ] AC 2: Genuine-divergence path preserved — `merge_die` is still called (with `MERGE_RESULT=failed` + `ERROR_MESSAGE`) when both attempts fail.
- [ ] AC 3: Diagnostic stderr message present on the retry path.
- [ ] AC 4: No regression — `shellcheck` is clean; existing call paths (clean first attempt, conflict, non-ff failure) are unmodified.
- [ ] AC 5: Change scoped to the ff-pull block in `cmd_merge` only; discovery and conflict logic untouched.

---

## Seed Data Reference

N/A — no database or application seed data required. All test scenarios exercise the shell script directly.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `shellcheck` reports `SC2064` or similar on the retry block | Quoting or expansion issue in the retry conditional | Wrap variables with double quotes; use `"$TARGET_BASE"` not `$TARGET_BASE` |
| `grep` finds no retry message on stderr | Diagnostic was written to stdout instead | Confirm `>&2` redirect is present on the diagnostic `echo` |
| Discovery returns unexpected output | Unintended change leaked into `cmd_discover` | Re-check the diff; revert any changes outside `cmd_merge` |

---

## Known Limitations

- The "transient failure recovery" scenario (AC 1) cannot be fully automated without a mock git or wrapper script. The smoke test relies on code inspection to confirm the retry branch is structurally correct. A full integration test would require a controlled environment where `git pull --ff-only` can be made to fail exactly once.

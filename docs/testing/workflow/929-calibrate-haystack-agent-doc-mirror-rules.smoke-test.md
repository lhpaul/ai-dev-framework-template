# Smoke Test Runbook: Calibrate Haystack Agent-Doc Mirror Rules

**Feature**: Calibrate Haystack Agent-Doc Mirror Rules (#929)
**Spec**: [docs/specs/developments/20260615110334_929-calibrate-haystack-agent-doc-mirror-rules/1_929-calibrate-haystack-agent-doc-mirror-rules_specs.md](../../specs/developments/20260615110334_929-calibrate-haystack-agent-doc-mirror-rules/1_929-calibrate-haystack-agent-doc-mirror-rules_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The repository is checked out locally with the plan branch applied.
- [ ] `bash`, `jq`, and `git` are available in `PATH`.
- [ ] `scripts/development-workflow/tests/test-haystack-reviewer.sh` is executable.
- [ ] `scripts/development-workflow/tests/test-pr-review-loop.sh` is executable.
- [ ] The repository contains the current agent-doc surface map described in the plan verification log.

---

## Test Data

| Item | Value |
| ---- | ----- |
| Repo root | `/Users/lhpaul/Git/ai-dev-framework-template` |
| Current surface map | 13 Claude agent docs, 13 Cursor agent docs, 27 Codex skill files |
| Missing surface under test | `.cursor/skills` (absent on purpose) |
| Reviewer unit test | `scripts/development-workflow/tests/test-haystack-reviewer.sh` |
| PR loop unit test | `scripts/development-workflow/tests/test-pr-review-loop.sh` |

---

## Smoke Test Steps

### Step 1: Confirm the live surface map matches the plan

**Maps to**: Acceptance Criterion AC-1, AC-3

1. Run the surface-map query from the plan verification log:
   ```bash
   rg --files .claude/agents .cursor/agents .codex/skills | sort
   ```
2. Confirm the output contains the expected Claude agent docs, Cursor agent docs, and Codex skill files.
3. Confirm `.cursor/skills` does not exist:
   ```bash
   if [ -d .cursor/skills ]; then echo yes; else echo no; fi
   ```

**Expected result**:
- The repository surface map matches the plan verification log.
- `.cursor/skills` is absent and therefore not treated as a required mirror.

### Step 2: Verify command-doc semantic sync does not flag front matter only differences

**Maps to**: Acceptance Criterion AC-2

1. Run the Haystack reviewer unit tests:
   ```bash
   bash scripts/development-workflow/tests/test-haystack-reviewer.sh
   ```
2. Locate the test case that covers Claude/Cursor command mirrors with different front matter.
3. Confirm that the test passes and reports the case as advisory or clean rather than blocking.

**Expected result**:
- The semantic mirror test passes.
- Front matter differences alone do not produce a required fix.

### Step 3: Verify absent Cursor skills are not required

**Maps to**: Acceptance Criterion AC-3

1. Re-run the Haystack reviewer tests if needed after any local edits.
2. Confirm the case that exercises the missing `.cursor/skills` surface passes.

**Expected result**:
- Absent Cursor skills are treated as intentionally out of scope.
- The reviewer output does not invent a missing mirror requirement.

### Step 4: Verify coverage spans all mirrored surface classes

**Maps to**: Acceptance Criterion AC-4

1. Inspect the Haystack reviewer test cases for coverage of:
   - Claude commands to Cursor commands
   - Claude skills
   - Codex skills
   - absent Cursor skills
2. Confirm the test file includes fixtures or mocked payloads for each surface class.

**Expected result**:
- Every surface class named in the spec is represented in the regression coverage.

### Step 5: Verify actionable versus non-actionable reviewer output

**Maps to**: Acceptance Criteria AC-5, AC-6

1. Run the PR review loop tests:
   ```bash
   bash scripts/development-workflow/tests/test-pr-review-loop.sh
   ```
2. Confirm the summary-rendering case keeps actionable mirror drift distinct from stale or false advisories.
3. Confirm the output names the affected surfaces when the finding is actionable.
4. Confirm the output explains why a stale or false advisory is not required when the finding is non-actionable.

**Expected result**:
- Real mirror drift is labeled actionable.
- False or stale advisories are labeled non-actionable and include the reason.

### Step 6: Validate and shut down

- Verify all assertions in the checklist below are met.
- Leave the repository clean.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC-1: Mirror checks use the live repository surface map and do not require absent surfaces.
- [ ] AC-2: Claude/Cursor command mirrors are evaluated semantically, and tool-specific front matter differences do not count as drift.
- [ ] AC-3: Absent Cursor skills are not reported as a missing required mirror.
- [ ] AC-4: Regression coverage includes Claude commands to Cursor commands, Claude skills, Codex skills, and absent Cursor skills.
- [ ] AC-5: A real mismatch is labeled actionable mirror drift and names the affected surfaces.
- [ ] AC-6: A stale or false mirror finding is labeled non-actionable and explains why it is not required.
- [ ] AC-7: The output gives enough context to fix real drift without consulting implementation internals.

---

## Seed Data Reference

None. This smoke test exercises repository metadata, unit-test fixtures, and reviewer output only.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| ------- | ------------ | --- |
| `.cursor/skills` appears in the surface map | Local checkout includes an experimental directory not part of the repo | Confirm the path is not committed or adjust the test setup to use the clean repository state |
| A front-matter-only change is reported as drift | The Haystack rule still compares byte-for-byte content instead of semantic workflow behavior | Revisit `.haystack/pr-rules.yml` and the reviewer fixtures |
| A stale advisory blocks the reviewer loop | The review policy or wrapper still classifies the finding as blocking | Recheck the advisory mapping in `.haystack/review-policy.md` and `haystack-reviewer.sh` |

---

## Known Limitations

- The smoke test validates the repository boundary and the wrapper behavior, not Haystack's hosted model quality.
- The unit tests rely on mocked or local payloads, so they prove the contract at the script boundary rather than the external service implementation.

# Smoke Test Runbook: Register Claude Code Action and Reslot phase_after_clean

**Feature**: #708 — chore(config): register claude-code-action and reslot phase_after_clean
**Spec**: [`docs/specs/developments/20260523170145_708-claude-code-action-config/1_708-claude-code-action-config_specs.md`](../../specs/developments/20260523170145_708-claude-code-action-config/1_708-claude-code-action-config_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch has been merged or is checked out locally
- [ ] You have access to the repository's `.ai-dev-workflow.yaml`, `README.md`, and `CHANGELOG.md` files

---

## Test Data

| Item | Value |
| --- | --- |
| Target file 1 | `.ai-dev-workflow.yaml` |
| Target file 2 | `README.md` |
| Target file 3 | `CHANGELOG.md` |

---

## Smoke Test Steps

### Step 1: Verify `.ai-dev-workflow.yaml` — `claude-code-action` in supported-platforms comment

**Maps to**: Acceptance Criterion 1

1. Open `.ai-dev-workflow.yaml` in the repository root.
2. Find the comment line that lists supported platforms (look for the line starting with `# Supported today by pr-review-loop.sh:`).
3. Confirm that `claude-code-action` appears in that comment line alongside other platforms such as `coderabbit`, `pr-agent`, and `codex-github`.

**Expected result**: The comment line reads something like `# Supported today by pr-review-loop.sh: greptile, devin, coderabbit, pr-agent, codex-github, claude-code-action` (exact order may vary).

---

### Step 2: Verify `.ai-dev-workflow.yaml` — `phase_after_clean` recommendation comment

**Maps to**: Acceptance Criterion 2

1. In `.ai-dev-workflow.yaml`, locate the `phase_after_clean` key and its surrounding comment block.
2. Read the comment block near or below `phase_after_clean`.
3. Confirm that the comment explicitly states that `claude-code-action` is the recommended value to use in place of `coderabbit` to remove the CodeRabbit per-hour rate-limit bottleneck.

**Expected result**: A comment near the `phase_after_clean` stanza mentions `claude-code-action` as the recommended replacement for `coderabbit` and explains that it removes the rate-limit constraint.

---

### Step 3: Verify `README.md` — `claude-code-action` in Optional Integrations

**Maps to**: Acceptance Criterion 3

1. Open `README.md` in the repository root.
2. Navigate to the "Optional Integrations" section.
3. Find the bullet that describes automated PR review platforms.
4. Confirm that `claude-code-action` is mentioned as the recommended `phase_after_clean` option, or that the bullet links to the `claude-code-action` integration guide.

**Expected result**: The `README.md` Optional Integrations section mentions `claude-code-action` as an available and recommended automated review platform, with a reference or link to the integration guide.

---

### Step 4: Verify `CHANGELOG.md` — entry under `[Unreleased]`

**Maps to**: Acceptance Criterion 4

1. Open `CHANGELOG.md` in the repository root.
2. Navigate to the `## [Unreleased]` section.
3. Confirm that a new bullet entry describes this configuration and documentation update (e.g., registers `claude-code-action` as a supported platform and recommends it for `phase_after_clean`).
4. Confirm the entry uses the project's `**Bold Title** (#N):` format.

**Expected result**: `CHANGELOG.md` contains an entry referencing issue #708 under `[Unreleased]`.

---

### Step 5: Verify no active config change — `coderabbit` still in active YAML values

**Maps to**: Acceptance Criterion 5

1. In `.ai-dev-workflow.yaml`, inspect the `review.platforms` list (the YAML array, not the comment).
2. Confirm that `coderabbit` is still present in the list and `claude-code-action` is **not** present in the active list values.
3. Inspect the `review.phase_after_clean` list (the YAML array, not the comment).
4. Confirm that `coderabbit` is still listed as the active value and `claude-code-action` is **not** in the active array.

**Expected result**: The active YAML values for `review.platforms` and `review.phase_after_clean` are unchanged. `claude-code-action` appears only in YAML comments, not in the active configuration arrays.

---

## Pass / Fail Summary

| Step | Criterion | Result |
| --- | --- | --- |
| Step 1 | `claude-code-action` in `# Supported today` comment | Pass / Fail |
| Step 2 | `phase_after_clean` comment recommends `claude-code-action` | Pass / Fail |
| Step 3 | `README.md` mentions `claude-code-action` as recommended option | Pass / Fail |
| Step 4 | `CHANGELOG.md` entry present under `[Unreleased]` | Pass / Fail |
| Step 5 | Active YAML values unchanged (`coderabbit` still active) | Pass / Fail |

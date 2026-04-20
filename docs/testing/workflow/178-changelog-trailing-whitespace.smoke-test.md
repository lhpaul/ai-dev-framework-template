# Smoke Test Runbook: Developer Agent CHANGELOG Trailing-Whitespace Prevention

**Feature**: Developer Agent CHANGELOG Trailing-Whitespace Prevention (issue #178)
**Spec**: [`docs/specs/developments/20260417154805_178-changelog-trailing-whitespace/1_178-changelog-trailing-whitespace_specs.md`](../../specs/developments/20260417154805_178-changelog-trailing-whitespace/1_178-changelog-trailing-whitespace_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The feature branch has been merged to `develop`
- [ ] You have a local clone of the repository at the latest `develop` HEAD
- [ ] `grep`, `git`, and a text editor are available in your shell

---

## Test Data

| Item | Value |
|---|---|
| Protocol file | `docs/ai/development-workflow/protocols/03-implement-development-protocol.md` |
| Agent definition (Claude) | `.claude/agents/developer.md` |
| Agent definition (Cursor) | `.cursor/agents/developer.md` |

---

## Smoke Test Steps

### Step 1: Verify Full Pipeline Path (AC1, AC3, AC4)

1. Open `docs/ai/development-workflow/protocols/03-implement-development-protocol.md`.
2. Navigate to **Path 1: Full Pipeline**, **Step 6: Update CHANGELOG**.
3. Confirm that immediately after the existing entry-writing guidance there is a **CHANGELOG format verification** sub-step.
4. Confirm the sub-step names both defect patterns:
   - Trailing whitespace on any line of the entry
   - Two or more consecutive blank lines at the end of the entry
5. Confirm the sub-step explicitly states that intentional two-space Markdown hard line breaks are **not** trailing whitespace.
6. Confirm the sub-step instructs the agent to fix in-place **before staging**.

**Expected result**: All six confirmations pass.

---

### Step 2: Verify Refactor Path (AC1, AC3, AC4)

1. In the same file, navigate to **Path 2: Refactor**, **Refactor Steps**, step 6 (Update CHANGELOG bullet).
2. Confirm the same CHANGELOG format verification sub-step is present (same content as Step 1 above).

**Expected result**: Verification sub-step is present and covers both defect patterns with the hard-line-break exclusion.

---

### Step 3: Verify Fast Track Path (AC1, AC3, AC4)

1. In the same file, navigate to **Path 3: Fast Track**, **Step 6: Update CHANGELOG**.
2. Confirm the same CHANGELOG format verification sub-step is present.

**Expected result**: Verification sub-step is present and covers both defect patterns with the hard-line-break exclusion.

---

### Step 4: Verify Hotfix Path (AC1, AC3, AC4)

1. In the same file, navigate to **Path 4: Hotfix**, **Step 6: Update CHANGELOG**.
2. Confirm the same CHANGELOG format verification sub-step is present.

**Expected result**: Verification sub-step is present and covers both defect patterns with the hard-line-break exclusion.

---

### Step 5: Verify Developer Agent Key Rules (AC2)

1. Open `.claude/agents/developer.md`.
2. Navigate to the **Key rules** bullet list.
3. Confirm there is a bullet stating that CHANGELOG entries must have no trailing whitespace and no trailing blank lines before commit.
4. Confirm the bullet mentions that intentional two-space Markdown hard line breaks are exempt.
5. Open `.cursor/agents/developer.md`.
6. Navigate to its **Key rules** bullet list and confirm the same bullet is present with identical wording to the bullet in `.claude/agents/developer.md` (both agent files must stay in sync).

**Expected result**: All six confirmations pass — both files contain the new key rule with identical wording.

---

### Step 6: Verify No Existing Instructions Removed (AC5)

1. In `03-implement-development-protocol.md`, confirm that all pre-existing CHANGELOG update instructions (e.g., "Add an entry under `[Unreleased]`", category guidance, unreleased-entry update rule) are still present in each path.
2. In **both** `.claude/agents/developer.md` and `.cursor/agents/developer.md`, confirm that all pre-existing key rules (e.g., "Always update CHANGELOG before opening the PR") are still present and unchanged.

**Expected result**: No pre-existing instruction has been removed or overwritten.

---

### Step 7: Shell Grep Verification (AC1)

Run the following commands and verify the output:

```bash
# Confirm verification instruction appears in all four paths
grep -n "CHANGELOG format verification" \
  docs/ai/development-workflow/protocols/03-implement-development-protocol.md
```

**Expected result**: Exactly 4 matches (one per path).

```bash
# Confirm the hard-line-break exclusion is present in each occurrence
grep -n "two-space" \
  docs/ai/development-workflow/protocols/03-implement-development-protocol.md
```

**Expected result**: At least 4 matches (one per path).

```bash
# Confirm the developer agent key rule in the Claude agent definition
grep -n "trailing whitespace" .claude/agents/developer.md
```

**Expected result**: At least 1 match in the key rules section.

```bash
# Confirm the same key rule in the Cursor agent definition
grep -n "trailing whitespace" .cursor/agents/developer.md
```

**Expected result**: At least 1 match in the key rules section, with wording identical to the `.claude/agents/developer.md` bullet.

---

## Assertions Checklist

Each checkbox maps to an acceptance criterion from the spec.

- [ ] AC1: `03-implement-development-protocol.md` includes an explicit, actionable CHANGELOG format verification instruction in every implementation path (Full Pipeline Step 6, Refactor Step 6, Fast Track Step 6, Hotfix Step 6), directing the agent to verify for trailing whitespace and trailing blank lines before staging.
- [ ] AC2: **Both** `.claude/agents/developer.md` **and** `.cursor/agents/developer.md` key rules sections include a note (worded identically across the two files) that the CHANGELOG entry must have no trailing whitespace or trailing blank lines before commit.
- [ ] AC3: The instruction in the protocol specifies both defect patterns (trailing whitespace, trailing blank lines at end of entry) and the timing (after writing the CHANGELOG entry, before staging for commit).
- [ ] AC4: The instruction explicitly states that intentional two-space Markdown hard line breaks must not be treated as trailing whitespace violations.
- [ ] AC5: The changes do not remove or conflict with any existing CHANGELOG update instructions in the protocol or agent definition.

---

## Seed Data Reference

None — this feature is documentation and protocol text only. No runtime seed data is required.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `grep` returns fewer than 4 matches for "CHANGELOG format verification" | One or more paths were missed during implementation | Re-read each path's Step 6 and add the missing sub-step |
| Developer agent key rule is missing or mismatched between agent files | `.claude/agents/developer.md` and/or `.cursor/agents/developer.md` was not updated, or wording diverged between the two | Add/fix the trailing-whitespace key rule in both files and ensure the bullet text is identical |
| Existing CHANGELOG instructions are missing after the change | Incorrect edit replaced rather than appended | Restore from git history and re-apply the change as an append |

---

## Known Limitations

- This runbook verifies the presence and content of protocol text. It does not execute the developer agent end-to-end to confirm it follows the instruction — that requires a live agent run with a CHANGELOG-modifying PR. Manual spot-check of a future developer agent run is recommended as a follow-up validation.

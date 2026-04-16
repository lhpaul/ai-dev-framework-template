# Smoke Test Runbook: Opus 4.7 Upgrade

**Feature**: Upgrade workflow agents from Opus 4.6 to Opus 4.7 (GitHub issue #160)
**Spec**: N/A (Refactor)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Working tree is on the `refactor/160-opus-4-7-upgrade` branch (or reviewing the merged PR)
- [ ] No worktree-local files are being checked (worktrees are transient and irrelevant)

---

## Test Data

| Item | Value |
|---|---|
| Files to check | `.claude/agents/tech-lead.md`, `docs/ai/development-workflow/agent-model-config.md` |
| Old Opus model IDs | `claude-opus-4-6`, `claude-opus-4-5-20251101` |
| New Opus model ID | `claude-opus-4-7` |

---

## Smoke Test Steps

### Step 1: Verify no stale Opus 4.6 or 4.5 references in tracked agent files

Run from the repo root:

```bash
grep -r "claude-opus-4-6" .claude/agents/ .cursor/ .codex/ docs/ai/
grep -r "claude-opus-4-5" .claude/agents/ .cursor/ .codex/ docs/ai/
```

**Expected result**: Both commands return no output (zero matches).

### Step 2: Verify tech-lead agent front-matter

```bash
head -5 .claude/agents/tech-lead.md
```

**Expected result**: Line 3 reads `model: claude-opus-4-7`.

### Step 3: Verify agent-model-config examples

```bash
grep "claude-opus" docs/ai/development-workflow/agent-model-config.md
```

**Expected result**: All `claude-opus` references in the file use `claude-opus-4-7`. No `claude-opus-4-6` or `claude-opus-4-5` present.

### Step 4: Verify CHANGELOG entry

```bash
grep -A 3 "\[Unreleased\]" CHANGELOG.md | head -20
```

**Expected result**: The `[Unreleased]` section contains a `Changed` entry mentioning the Opus 4.6 → 4.7 bump.

### Step 5: Verify Sonnet and Haiku references are untouched

```bash
grep -r "claude-sonnet\|claude-haiku" .claude/agents/ docs/ai/development-workflow/agent-model-config.md
```

**Expected result**: Sonnet and Haiku lines are present and unchanged (no accidental version bumps).

---

## Assertions Checklist

- [ ] `grep -r "claude-opus-4-6" .claude/agents/ .cursor/ .codex/ docs/ai/` returns no matches
- [ ] `grep -r "claude-opus-4-5" .claude/agents/ .cursor/ .codex/ docs/ai/` returns no matches
- [ ] `.claude/agents/tech-lead.md` front-matter has `model: claude-opus-4-7`
- [ ] `docs/ai/development-workflow/agent-model-config.md` examples use `claude-opus-4-7`
- [ ] CHANGELOG `[Unreleased]` section has a `Changed` entry for this upgrade
- [ ] Sonnet and Haiku references are unchanged

---

## Seed Data Reference

None required.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| grep still returns hits in `.claude/agents/` | Edit was not saved or committed | Re-apply the change and verify with `git diff` |
| grep returns hits in `.claude/worktrees/` | Transient worktree directories | Exclude `.claude/worktrees/` from the search; worktrees are not tracked |

---

## Known Limitations

- Worktrees under `.claude/worktrees/` contain copies of the old config files for other open items. These are intentionally excluded from the success criteria — only tracked repository files matter.

# Smoke Test Runbook: Sync-Template Decide With Me vs Accept Recommendations

**Feature**: Sync-template apply modes (Decide with me vs Accept recommendations)
**Spec**: [1_1284-sync-template-decide-vs-accept_specs.md](../../specs/developments/20260721132934_1284-sync-template-decide-vs-accept/1_1284-sync-template-decide-vs-accept_specs.md)
**Created in**: Plan Ready stage

---

## Prerequisites

- [ ] You are reviewing the implementation PR for #1284 (or a local checkout of
      that branch).
- [ ] The PR targets `develop`.
- [ ] No live template sync apply is required for the default smoke path — this
      runbook verifies protocol text and mirror consistency.

---

## Test Data

| Item | Value |
| --- | --- |
| Canonical protocol | `.claude/commands/sync-template.md` |
| Cursor mirror | `.cursor/commands/sync-template.md` |
| Claude skill mirror | `.claude/skills/sync-template.md` |
| Codex wrapper | `.codex/skills/workflow-sync-template/SKILL.md` |
| Agents wrapper | `.agents/skills/workflow-sync-template/SKILL.md` |
| Hard-stop example path | `.claude/settings.json` (manifest `special_handling`) |

---

## Smoke Test Steps

### Step 1: Primary confirmation options

**Maps to**: AC1, AC6, UX1, UX5

1. Open `.claude/commands/sync-template.md` at the Step 3 confirmation prompt.
2. Confirm the primary options are **Decide with me** and **Accept
   recommendations** (or equally clear names).
3. Confirm `"apply all"` and `"apply always-sync only"` are not presented as the
   primary peer pair.
4. If always-sync-only remains, confirm it is labeled as advanced / escape hatch
   and is not a peer of the two primary modes.

**Expected result**: Autonomy modes are primary; coverage-only sync is demoted
or absent from the primary pair.

### Step 2: Decide with me walkthrough

**Maps to**: AC2, UX2, BR3

1. Locate the Decide with me apply path in Step 4.
2. Confirm always-sync Add/Update is applied as a batch after mode selection.
3. Confirm every discretionary item is walked with a recommendation and a
   yes/skip prompt.
4. Confirm hard-stop items are excluded from that walkthrough.

**Expected result**: Decide with me is interactive discretionary coverage, not a
partial sync, and not a hard-stop auto-yes path.

### Step 3: Accept recommendations plan + log

**Maps to**: AC3, BR7, UX3

1. Locate the Accept recommendations apply path in Step 4.
2. Confirm a planned disposition table is required before discretionary mutation.
3. Confirm one plan confirmation (or decline / switch mode) is required.
4. Confirm recommended discretionary dispositions apply without per-item prompts
   after confirmation.
5. Confirm a post-apply disposition log (applied / skipped / escalated) is
   required.

**Expected result**: Accept recommendations is plan-then-apply with a reviewable
disposition log.

### Step 4: Hard stops and contradiction resolution

**Maps to**: AC4, AC5, BR4, BR5, BR6

1. Confirm special-handling paths, rename cleanup actions, and placeholder-guard
   cases escalate and require explicit naming (second confirm for placeholder
   guard).
2. Confirm `.claude/settings.json` (or equivalent special-handling example) is
   **not** listed under a discretionary “you decide” walkthrough heading.
3. Confirm bulk phrases such as “apply everything” / “yes to all” never authorize
   hard-stop paths.

**Expected result**: Walkthrough “yes” cannot conflict with “must name the path”
for special-handling items.

### Step 5: Mirror consistency

**Maps to**: AC7, BR9

1. Grep Claude command, Cursor command, Claude skill, and both
   workflow-sync-template wrappers for `Decide with me` and
   `Accept recommendations`.
2. Confirm each surface describes the same primary modes and hard-stop /
   approval rules (frontmatter differences are OK).
3. Confirm wrappers no longer present `"apply all"` as a primary option.

**Expected result**: Claude, Cursor, and Codex entrypoints stay consistent with
the canonical protocol for apply modes.

### Step 6: No mutation before confirmation

**Maps to**: AC8, BR10

1. Confirm Step 3 still forbids file modification until the maintainer confirms
   a primary mode.
2. Confirm Accept recommendations also forbids discretionary mutation until the
   disposition plan is confirmed.

**Expected result**: Mode (and plan) confirmation gates all mutation.

---

## Assertions Checklist

- [ ] AC1: Primary confirmation is Decide with me / Accept recommendations; old
      peer pair is gone
- [ ] AC2: Decide with me walks discretionary items with recommendation + yes/skip
- [ ] AC3: Accept recommendations has disposition table, one confirm, and log
- [ ] AC4: Hard stops remain unapplied without explicit naming/confirmation
- [ ] AC5: Special-handling is not discretionary walkthrough content
- [ ] AC6: Always-sync only is absent or clearly demoted
- [ ] AC7: Claude / Cursor / Codex mirrors agree on modes and hard stops
- [ ] AC8: No mutation before mode confirmation (and plan confirmation for Accept)

---

## Seed Data Reference

None required.

# Sync-Template Apply Modes (Decide With Me vs Accept Recommendations) — Spec

---

## Overview

Maintainers running template sync need a clear choice about **who decides** on
discretionary items after the mandatory always-sync batch, not a choice about
how much of the sync to run. Today the primary confirmation splits on coverage
(“apply all” vs “apply always-sync only”), which pushes the useful autonomy
split into informal verbal overrides. This feature replaces that primary prompt
with **Decide with me** and **Accept recommendations**, keeps hard stops for
high-blast-radius paths, resolves the contradiction between walkthrough “yes”
and “must name the path,” and demotes partial always-sync-only syncs away from
the primary options. Claude, Cursor, and Codex entrypoints must stay consistent
with the canonical sync-template protocol.

## Brief Objective List

1. Replace the primary confirmation with Decide with me vs Accept recommendations.
2. Decide with me walks every discretionary item with recommendation plus yes/skip.
3. Accept recommendations applies agent dispositions after one plan confirmation,
   with a post-apply disposition log.
4. Special-handling, rename cleanup, and placeholder-guard cases still require
   explicit escalation in both modes.
5. Resolve the special-handling vs manual-review contradiction in the protocol.
6. Remove or clearly demote “always-sync only” from the primary options.
7. Keep mirrored sync-template entrypoints (Claude / Cursor / Codex) consistent
   with the canonical protocol.

---

## Use Cases

### Use Case 1: Maintainer chooses Decide with me

**Actor**: Template sync maintainer (human operator of `/sync-template`).
**Preconditions**: Pre-flight and comparison are complete; the change summary
has been presented; no files have been modified yet.

**Steps**:

1. The agent asks the maintainer how to proceed on discretionary items.
2. The maintainer chooses **Decide with me**.
3. The agent applies the always-sync Add and Update batch in one pass.
4. For each discretionary item (optional additive updates and any other
   non-hard-stop items that today appear under a “you decide” walkthrough), the
   agent shows the diff or proposed addition, states a recommendation, and asks
   yes or skip.
5. The agent applies immediately on yes and skips on skip (or any non-yes
   answer), then continues to the next item.
6. High-blast-radius items (special-handling paths, rename cleanup actions, and
   placeholder-guard cases) are not treated as walkthrough yes/skip items; they
   escalate for explicit named-path or second confirmation as required today.

**Postconditions**: Always-sync changes that were approved by mode selection are
applied; each discretionary item has an explicit human yes or skip; escalated
items remain unapplied unless the maintainer named and confirmed them.

**Information shown**:

- Primary mode choice with clear names: Decide with me and Accept recommendations.
- Per discretionary item: diff or proposed addition, recommendation, and yes/skip
  prompt.
- Escalation prompts that name the exact path or action for hard-stop cases.

**Actions available**:

- Choose Decide with me.
- Answer yes or skip per discretionary item.
- Explicitly name and confirm escalated hard-stop paths or actions.

**Considerations**:

- Bulk phrases such as “apply everything” or “yes to all” must not authorize
  hard-stop paths.
- Decide with me is the interactive autonomy mode; it is not a partial sync.

### Use Case 2: Maintainer chooses Accept recommendations

**Actor**: Template sync maintainer.
**Preconditions**: Same as Use Case 1.

**Steps**:

1. The agent asks the maintainer how to proceed on discretionary items.
2. The maintainer chooses **Accept recommendations**.
3. The agent prints a planned disposition table covering every discretionary
   item (recommended apply or skip, with a short why).
4. The maintainer confirms the plan once (or declines / switches mode).
5. After plan confirmation, the agent applies the always-sync batch, then
   applies each recommended discretionary disposition without further per-item
   prompts.
6. Hard-stop items remain escalated; they are listed in the plan as escalated /
   not auto-applied and still require explicit named-path or second confirmation.
7. After apply, the agent prints a disposition log (applied / skipped /
   escalated and why).

**Postconditions**: Always-sync and recommended discretionary dispositions are
applied according to the confirmed plan; hard-stop items are untouched unless
explicitly approved; the disposition log is available for PR reviewability.

**Information shown**:

- Planned disposition table before any discretionary apply.
- One confirmation of the plan.
- Post-apply disposition log with applied / skipped / escalated outcomes.

**Actions available**:

- Confirm the plan, decline it, or switch to Decide with me.
- Explicitly name and confirm escalated hard-stop paths or actions.

**Considerations**:

- Accept recommendations must not silently apply special-handling, rename
  cleanup, or placeholder-guard cases.
- The plan confirmation authorizes only the listed discretionary dispositions,
  not hard-stop paths.

### Use Case 3: Maintainer needs a partial always-sync escape hatch

**Actor**: Template sync maintainer.
**Preconditions**: Change summary is presented; maintainer intentionally wants
only the always-sync batch and no discretionary work.

**Steps**:

1. The primary prompt does not present “always-sync only” as a peer of the two
   autonomy modes.
2. If an advanced or escape-hatch path remains, it is clearly labeled as secondary
   (for example, after the primary choice or as an advanced option), not as the
   default coverage split.
3. Choosing the escape hatch applies always-sync only and leaves discretionary
   and hard-stop items unapplied unless later named explicitly.

**Postconditions**: Partial sync is possible only through a demoted path; the
default mental model remains full discretionary coverage with an autonomy choice.

**Information shown**:

- Primary options: Decide with me and Accept recommendations.
- If retained, a clearly demoted always-sync-only escape hatch.

**Actions available**:

- Prefer one of the two primary modes.
- Optionally invoke the demoted escape hatch when intentionally skipping
  discretionary work.

---

## Business Rules

- BR1: The primary post-summary confirmation asks who decides on discretionary
  items: **Decide with me** or **Accept recommendations**.
- BR2: Both primary modes apply the always-sync Add/Update batch after the
  maintainer selects a mode (and, for Accept recommendations, after plan
  confirmation). Neither primary mode is a “skip discretionary work” mode.
- BR3: Discretionary items are optional additive updates and other non-hard-stop
  “you decide” items. They are distinct from hard-stop items. Paths classified as
  special-handling are never discretionary, even if a summary section historically
  labeled them “manual review.”
- BR4: Hard-stop items always escalate and never auto-apply under either primary
  mode:
  - special-handling paths (for example deploy workflow, e2e regression
    workflow, e2e suite, Claude settings), including items formerly shown under a
    “Requires manual review” heading when those items are special-handling
  - rename cleanup actions (including directory deletes and cross-reference
    rewrites for renamed always-sync trees)
  - placeholder-guard cases (real project workflow versus template stub)
- BR5: Bulk approval phrases never authorize hard-stop items. Hard-stop approval
  requires naming the path or action (and a second confirmation when the
  placeholder guard fires).
- BR6: The protocol must not treat a walkthrough “yes” on a hard-stop path as
  sufficient approval. Hard-stop items are excluded from the discretionary
  walkthrough and from Accept recommendations auto-apply.
- BR7: Accept recommendations must present a planned disposition table and obtain
  one plan confirmation before applying discretionary dispositions, then print a
  disposition log afterward.
- BR8: “Always-sync only” must be removed from the primary prompt or demoted to a
  clearly labeled advanced/escape-hatch option.
- BR9: Claude, Cursor, and Codex sync-template mirrors must describe the same
  primary modes, hard stops, and approval rules as the canonical protocol.
- BR10: No files are modified until the maintainer has confirmed a primary mode
  (and, for Accept recommendations, the disposition plan).

## Decision-Gate Consistency Matrix

| Gate input | Allowed outcomes | Required next action | Mirror surfaces | Examples |
| --- | --- | --- | --- | --- |
| Primary mode prompt after change summary | Decide with me; Accept recommendations; (optional demoted always-sync-only escape hatch) | Enter selected mode; do not mutate before confirmation | Canonical sync-template command; Cursor command; Codex/skill wrappers | Maintainer answers “Decide with me” |
| Discretionary item under Decide with me | Apply; Skip | Show diff + recommendation; ask yes/skip; apply or skip; continue | Same mirrors | Optional AGENTS.md additive update → skip |
| Discretionary set under Accept recommendations | Confirm plan; Decline/switch mode | Show disposition table; one confirm; then apply recommended dispositions | Same mirrors | Table lists 3 apply / 1 skip; maintainer confirms |
| Special-handling path in either mode | Escalate; Apply only after named-path approval | Exclude from discretionary auto-yes; require explicit path name | Same mirrors | Maintainer says “apply `.github/workflows/deploy.yml`” |
| Rename cleanup action in either mode | Escalate; Apply only after named action approval | Require explicit delete or cross-reference update approval | Same mirrors | Maintainer says “delete docs/ai/” |
| Placeholder-guard case in either mode | Refuse; Apply only after second named confirmation | Compare project vs template size heuristic; refuse until second confirm names file | Same mirrors | Large project deploy.yml vs short template stub |

---

## UX Rules

- UX1: Primary option names must be human-readable and unambiguous: **Decide with
  me** and **Accept recommendations**. Do not reuse ambiguous “apply all” as the
  primary label.
- UX2: Decide with me shows recommendation text before each yes/skip prompt.
- UX3: Accept recommendations shows the planned disposition table before any
  discretionary mutation and a disposition log after apply.
- UX4: Hard-stop escalations must name the exact path or action and state why
  automatic approval is blocked.
- UX5: If always-sync-only remains, its label must mark it as advanced or escape
  hatch so it is not visually peer to the two primary modes.

---

## Operational Visibility

- **Planned disposition table** (Accept recommendations): lists each
  discretionary item and recommended apply/skip before mutation.
- **Disposition log** (Accept recommendations): records applied / skipped /
  escalated outcomes after apply so the sync PR remains reviewable.
- **Decide with me transcript**: per-item recommendation and yes/skip answers
  remain visible in the conversation.
- **Escalation prompts**: hard-stop refusals remain explicit in the run output.

---

## Acceptance Criteria

- [ ] AC1: After the change summary, the primary confirmation offers Decide with
      me and Accept recommendations with those (or equally clear) names, and does
      not present “apply all” / “apply always-sync only” as the primary peer pair.
- [ ] AC2: Decide with me applies always-sync, then walks every discretionary
      item with a recommendation and a yes/skip prompt.
- [ ] AC3: Accept recommendations prints a planned disposition table, requires
      one plan confirmation, then applies recommended discretionary dispositions
      without per-item prompts, and prints a post-apply disposition log.
- [ ] AC4: In both modes, special-handling paths, rename cleanup actions, and
      placeholder-guard cases remain unapplied unless the maintainer explicitly
      names/confirms them (including second confirm for placeholder guard).
- [ ] AC5: The protocol no longer allows a discretionary walkthrough “yes” to
      conflict with “must name the path” for special-handling: hard-stop items are
      excluded from discretionary walkthrough/auto-apply and documented as
      escalation-only.
- [ ] AC6: “Always-sync only” is absent from the primary options or clearly
      demoted to an advanced/escape-hatch path.
- [ ] AC7: Claude, Cursor, and Codex sync-template entrypoints describe the same
      primary modes, hard stops, and approval rules as the canonical protocol.
- [ ] AC8: Selecting either primary mode does not mutate files before the mode
      confirmation (and, for Accept recommendations, before plan confirmation).

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| Primary confirmation Decide with me vs Accept recommendations | BR1, UX1, Use Cases 1–2 | AC1, AC8 |
| Decide with me walks discretionary items with recommendation + yes/skip | Use Case 1, UX2, BR3 | AC2 |
| Accept recommendations plan confirmation + disposition log | Use Case 2, BR7, UX3, Operational Visibility | AC3 |
| Hard stops for special-handling / rename / placeholder guard | BR4, BR5, Use Cases 1–2, Decision-Gate matrix | AC4 |
| Resolve special-handling vs manual-review contradiction | BR6, AC5, Decision-Gate matrix | AC5 |
| Demote or remove always-sync only | BR8, Use Case 3, UX5 | AC6 |
| Keep Claude / Cursor / Codex mirrors consistent | BR9 | AC7 |

## Out of Scope (MVP)

- Changing which paths belong to always-sync, special-handling, or
  project-specific categories (category membership stays as today except for
  clarifying discretionary vs hard-stop approval behavior).
- Redesigning dry-run, pre-flight diagnostics, CI health checks, or post-sync
  reviewer-loop steps beyond wording needed for the new apply modes.
- Building a separate interactive UI outside the existing command/agent chat
  confirmation flow.
- Automatically applying hard-stop paths under any bulk or recommendation mode.
- Sibling batch items about other sync-template concerns (orthogonal; not part
  of this feature).

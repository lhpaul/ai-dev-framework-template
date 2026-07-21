# Sync-Template Apply Modes (Decide With Me vs Accept Recommendations) — Implementation Plan

**Spec**: [1_1284-sync-template-decide-vs-accept_specs.md](1_1284-sync-template-decide-vs-accept_specs.md)
**Smoke test runbook**: [1284-sync-template-decide-vs-accept.smoke-test.md](../../../testing/workflow/1284-sync-template-decide-vs-accept.smoke-test.md)

---

## Summary

**Approach**: Rewrite the sync-template Step 3 primary confirmation and Step 4
apply paths so autonomy is the primary choice (**Decide with me** vs **Accept
recommendations**), keep always-sync as a shared batch after mode confirmation,
and reclassify special-handling / rename cleanup / placeholder-guard as
escalation-only hard stops excluded from discretionary yes/skip and from Accept
recommendations auto-apply. Propagate the same wording to Claude, Cursor, and
Codex mirrors.

**Estimated complexity**: M

**Rationale**: No new runtime service or helper is required. The work is a
high-blast-radius protocol rewrite across three near-identical command/skill
bodies plus thin Codex wrappers, including a decision-gate matrix and smoke
coverage for the contradiction between walkthrough “yes” and “must name the
path.”

**Dependencies**: Spec PR #1291 is merged. Sibling sync-template items
(#1281 / #1282) are orthogonal and must not be edited in this branch.

---

## Template-Fit Check

`template.is_template: true`. This item improves template sync workflow
tooling and documentation shared by every downstream consumer regardless of
app stack. **Pass** — proceed.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `2fa9671` |
| Template-fit | `awk` / read `.ai-dev-workflow.yaml` `template.is_template` | `true`; feature is generic workflow tooling |
| Approved spec | `docs/specs/developments/20260721132934_1284-sync-template-decide-vs-accept/1_1284-sync-template-decide-vs-accept_specs.md` | Defines Decide with me / Accept recommendations, hard stops, demoted always-sync-only, AC1–AC8 |
| Canonical protocol primary prompt | `rg -n 'apply all\|apply always-sync only\|Decide with me' .claude/commands/sync-template.md` | Primary peer pair is still `"apply all"` / `"apply always-sync only"` (lines ~517–518) |
| Contradiction evidence | Summary section `Requires manual review (you decide)` includes `.claude/settings.json`; `sync-manifest.yaml` lists that path under `special_handling` | Special-handling path is currently presented as a discretionary walkthrough item |
| Mirror surfaces | `diff -q` Claude command vs Cursor command vs Claude skill; Codex wrappers | Claude↔Cursor differ only by `allowed-tools` frontmatter; Claude skill differs by frontmatter + trailing ground-truth section; Codex/agents wrappers still name `"apply all"` |
| Apply-mode wording surfaces | `rg -n 'apply all\|apply always-sync only' .claude/commands/sync-template.md .cursor/commands/sync-template.md .claude/skills/sync-template.md .codex/skills/workflow-sync-template/SKILL.md .agents/skills/workflow-sync-template/SKILL.md` | 34 matches across 5 files (thin `.agents/skills/sync-template/SKILL.md` delegates and has no apply-mode wording) |

---

## Classifier results (protocol 02)

| Classifier | Applies? | Rationale |
| --- | --- | --- |
| Parser-risk | No | Documentation/protocol wording only; no new scanners, regex engines, or lint parsers |
| Concurrent-event-source | No | No multi-listener / shared mutable runtime state |
| Cross-cutting checklist | No | Does not add or rename a checklist category in `REVIEW.md` or planning/implementation protocols |
| Complex workflow decision-gate | **Yes** | Changes primary mode gate, discretionary outcomes, hard-stop escalation, and mirrored surfaces |

---

## Decision-Gate Consistency Matrix

| Gate input | Allowed outcomes | Required next action | Mirror surfaces | Examples |
| --- | --- | --- | --- | --- |
| Primary mode prompt after change summary | Decide with me; Accept recommendations; optional demoted always-sync-only escape hatch | Enter selected mode; **no file mutation** before confirmation | `.claude/commands/sync-template.md`; `.cursor/commands/sync-template.md`; `.claude/skills/sync-template.md`; Codex/agents `workflow-sync-template` wrappers | Maintainer answers “Decide with me” |
| Discretionary item under Decide with me | Apply; Skip | Show diff + recommendation; ask yes/skip; apply or skip; continue | Same mirrors | Optional `AGENTS.md` additive update → skip |
| Discretionary set under Accept recommendations | Confirm plan; Decline / switch to Decide with me | Show disposition table; one confirm; apply recommended dispositions; print disposition log | Same mirrors | Table lists 3 apply / 1 skip; maintainer confirms |
| Special-handling path (either mode) | Escalate; Apply only after named-path approval | Exclude from discretionary walkthrough and Accept auto-apply | Same mirrors | Maintainer says `apply .github/workflows/deploy.yml` |
| Rename cleanup action (either mode) | Escalate; Apply only after named action approval | Require explicit delete or cross-reference update approval | Same mirrors | Maintainer says `delete docs/ai/` |
| Placeholder-guard case (either mode) | Refuse; Apply only after second named confirmation | Keep existing line-count heuristic; refuse until second confirm names the file | Same mirrors | Large project `deploy.yml` vs short template stub |
| Demoted always-sync-only escape hatch | Apply always-sync batch only; leave discretionary + hard-stop unapplied | Must not appear as a peer of the two primary autonomy modes | Same mirrors | Advanced/escape-hatch line after primary prompt |

---

## Layer-by-Layer Changes

### Workflow protocol / agent guidance (primary)

- [ ] Rewrite Step 3 confirmation in `.claude/commands/sync-template.md`:
      - Primary options: **Decide with me** and **Accept recommendations**
        (AC1, UX1).
      - Explicitly forbid presenting `"apply all"` /
        `"apply always-sync only"` as the primary peer pair (AC1, AC6).
      - State that neither primary mode mutates files before mode confirmation
        (AC8); Accept recommendations also waits for plan confirmation (AC3,
        BR10).
- [ ] Rewrite Step 3 summary taxonomy so hard-stop items are not labeled
      discretionary (AC5, BR3, BR6):
      - Keep **Optional additive updates** as the discretionary bucket.
      - Replace / split **Requires manual review (you decide)** so
        `categories.special_handling` paths (including
        `.claude/settings.json`, deploy/e2e workflows, `e2e/`) appear under an
        escalation / hard-stop heading, not under “you decide.”
      - Keep **Rename cleanup** as escalation-only (already separately
        approved today); ensure bulk phrases and Accept recommendations never
        authorize it (AC4).
- [ ] Rewrite Step 4 apply paths:
      - **Shared always-sync batch**: both primary modes apply Add/Update
        always-sync after the relevant confirmation (BR2).
      - **Decide with me**: after always-sync, walk every discretionary item
        with diff + recommendation + yes/skip; apply immediately on yes; skip
        otherwise (AC2, UX2). Hard-stop items are excluded from this walk.
      - **Accept recommendations**: print a planned disposition table for
        every discretionary item (recommended apply/skip + short why); obtain
        one plan confirmation (or decline / switch mode); apply recommended
        dispositions without per-item prompts; print post-apply disposition
        log with applied / skipped / escalated (AC3, UX3, BR7).
      - **Hard stops**: special-handling, rename cleanup, and placeholder-guard
        remain unapplied unless the maintainer explicitly names/confirms them
        (including second confirm for placeholder guard) (AC4, BR4, BR5).
      - Update bulk-phrase language: `"apply everything"`, `"yes to all"`, and
        any legacy `"apply all"` phrasing never authorize hard stops.
      - **Always-sync only**: demote to a clearly labeled advanced/escape-hatch
        option (AC6, UX5). Prefer placing it after the primary prompt, not as a
        peer bullet of the two autonomy modes.
- [ ] Propagate the same Step 3 confirmation + Step 4 apply-mode body to:
      - `.cursor/commands/sync-template.md` (preserve Cursor frontmatter;
        today differs only by omitting Claude `allowed-tools`)
      - `.claude/skills/sync-template.md` (preserve skill frontmatter; do not
        require resolving the pre-existing trailing ground-truth section drift
        unless it is touched while editing — AC7 requires matching primary
        modes / hard stops / approval rules, not byte-identical trailing
        sections)
- [ ] Update thin wrappers that still name the old primary options:
      - `.codex/skills/workflow-sync-template/SKILL.md` steps 5–6
      - `.agents/skills/workflow-sync-template/SKILL.md` steps 5–6
      - Leave `.agents/skills/sync-template/SKILL.md` as a pure alias unless
        implementation discovers apply-mode wording there (Verification Log:
        currently none).

### Scripts / tests

- [ ] No new sync helper is required for MVP (Out of Scope: category membership
      unchanged; confirmation remains chat-driven).
- [ ] Optional: add a small documentation assertion shell test under
      `scripts/development-workflow/tests/` that greps the three command/skill
      bodies for `Decide with me` / `Accept recommendations` and asserts the
      primary peer pair is not `"apply all"` / `"apply always-sync only"`.
      Prefer this only if implementation wants CI regression beyond the smoke
      runbook; smoke coverage alone is acceptable for MVP.

### Database / Frontend / Infrastructure

- [ ] None.

---

## Files to modify

| File | Change |
| --- | --- |
| `.claude/commands/sync-template.md` | Canonical Step 3/4 rewrite: primary modes, summary taxonomy, hard-stop exclusion, Accept recommendations plan + log, demoted escape hatch |
| `.cursor/commands/sync-template.md` | Same Step 3/4 body as canonical; keep Cursor frontmatter |
| `.claude/skills/sync-template.md` | Same Step 3/4 body for modes/hard stops/approval rules; keep skill frontmatter |
| `.codex/skills/workflow-sync-template/SKILL.md` | Replace `"apply all"` / `"apply always-sync only"` wording with Decide with me / Accept recommendations |
| `.agents/skills/workflow-sync-template/SKILL.md` | Same as Codex wrapper |
| `docs/testing/workflow/1284-sync-template-decide-vs-accept.smoke-test.md` | Already created in Plan Ready; developer verifies during implementation |
| `CHANGELOG.md` | Add Unreleased entry during **implementation** (not on this plan branch) |

**Explicitly out of scope for this branch / implementation**:

- `sync-manifest.yaml` category membership changes
- Sibling items #1281 / #1282
- Dry-run / pre-flight / CI health / reviewer-loop redesign beyond wording needed for the new modes

---

## Testing Strategy

**Test types**: Smoke (protocol text + decision-gate matrix verification). Optional
lightweight shell doc-regression test if implementation chooses CI coverage.

**Key scenarios to test**:

1. Primary prompt offers Decide with me / Accept recommendations and does not
   peer `"apply all"` with `"apply always-sync only"` — AC1, AC6
2. Decide with me walkthrough language requires recommendation + yes/skip for
   discretionary items only — AC2
3. Accept recommendations requires disposition table, one confirmation, and
   post-apply disposition log — AC3
4. Hard-stop paths (special-handling example `.claude/settings.json`, rename
   cleanup, placeholder guard) are escalation-only in both modes — AC4, AC5
5. Claude / Cursor / Codex surfaces describe the same modes and hard-stop rules
   — AC7
6. No-mutation-before-confirmation wording remains for both primary modes
   (and plan confirmation for Accept recommendations) — AC8

**Smoke test runbook**:
`docs/testing/workflow/1284-sync-template-decide-vs-accept.smoke-test.md`

**Residual verification strategy** (pattern completeness for mirrored wording):
Before implementation readiness, re-run the Verification Log `rg` across the
five apply-mode wording surfaces and confirm zero remaining primary-peer uses
of `"apply all"` / `"apply always-sync only"`. Evidence source: live repo
search output in the implementation PR description (not a frozen count from
this plan).

---

## Seed Data

None. This feature is protocol/documentation only; no application entities or
DB fixtures are required.

---

## Documentation Updates

Project docs the developer must update during **implementation** (not during
Plan Ready):

- [ ] `CHANGELOG.md` — under `[Unreleased]` / `### Changed`, add:
      `- **Sync-template decide-with-me vs accept-recommendations** (#1284): replaces the primary sync apply confirmation with Decide with me and Accept recommendations, keeps hard stops for special-handling / rename cleanup / placeholder-guard cases, and demotes always-sync-only to an escape hatch.`
- [ ] `AGENTS.md` — only if a user-facing sync-template command blurb currently
      describes the old `"apply all"` pair (Verification Log: maintenance table
      mentions `/sync-template` but not apply modes — likely **no change**).
- [ ] `docs/workflow/development-workflow/README.md` — only if it documents the
      old sync apply confirmation options (Verification Log: no apply-mode
      wording found; likely **no change**).

Canonical sync-template command/skill files are listed under **Files to modify**
above and are the primary documentation surfaces for this feature.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Mirror drift between Claude / Cursor / skill bodies | Med | Med | Edit canonical first; copy Step 3/4 body; smoke step greps all three for mode names and hard-stop rules |
| Leaving special-handling under a “you decide” heading recreates the contradiction | Med | High | Explicit summary taxonomy rewrite + smoke assertion that `.claude/settings.json` is not under a discretionary “you decide” walkthrough heading |
| Operators still say “apply all” out of habit | Med | Low | Keep bulk-phrase hard-stop refusals; map legacy phrases in protocol notes to Decide with me semantics only for discretionary items, never for hard stops |
| Accidental edits to #1281 / #1282 surfaces | Low | Med | Branch scope limited to sync-template apply-mode files listed above; do not touch graduation or graphical-design assets work |

---

## Code Samples

Illustrative — adapt during implementation.

### Primary confirmation (Step 3)

```markdown
<!-- Illustrative — adapt during implementation -->
> Ready to apply? Choose how to handle discretionary items:
>
> - **"Decide with me"** — Apply always-sync, then walk each discretionary
>   item with my recommendation and a yes/skip prompt.
> - **"Accept recommendations"** — Show a planned disposition table for every
>   discretionary item; after you confirm once, apply those dispositions and
>   print a disposition log.
>
> Hard-stop items (special-handling paths, rename cleanup, placeholder-guard
> cases) are never auto-applied. Name each path/action explicitly to approve.
>
> Advanced / escape hatch: **"always-sync only"** — apply the always-sync batch
> and skip discretionary work (hard stops still require explicit naming).
```

### Accept recommendations disposition table (Step 4)

```text
<!-- Illustrative — adapt during implementation -->
## Planned discretionary dispositions
| Item | Recommendation | Why |
| --- | --- | --- |
| AGENTS.md additive block | apply | Template adds sync-template command mention |
| README.md | skip | Project already has equivalent section |

## Escalated (not auto-applied)
| Item | Why blocked |
| --- | --- |
| .claude/settings.json | special-handling — name path to approve |
| delete docs/ai/ | rename cleanup — name action to approve |
```

---

## Implementation Order

1. **Canonical protocol rewrite** — Edit `.claude/commands/sync-template.md`
   Step 3 summary headings, primary confirmation, and Step 4 apply paths per
   Layer-by-Layer Changes. Include the decision-gate behaviors from the matrix
   above. Verify: open the confirmation block and confirm primary options are
   Decide with me / Accept recommendations; confirm special-handling example
   paths are not under a discretionary “you decide” walkthrough.
2. **Propagate to Cursor + Claude skill mirrors** — Apply the same Step 3/4
   body to `.cursor/commands/sync-template.md` and
   `.claude/skills/sync-template.md`, preserving each file’s frontmatter (and
   any intentional trailing-section differences outside the apply-mode
   rewrite). Verify with `diff` on the rewritten sections or by grepping all
   three for `Decide with me` and `Accept recommendations`.
3. **Update Codex/agents wrappers** — Edit steps 5–6 in
   `.codex/skills/workflow-sync-template/SKILL.md` and
   `.agents/skills/workflow-sync-template/SKILL.md` so they describe Decide
   with me / Accept recommendations, hard stops, and no-mutation-before-
   confirmation. Verify wrappers no longer present `"apply all"` as a primary
   option.
4. **Residual wording sweep** — Re-run:
   `rg -n 'apply all|apply always-sync only' .claude/commands/sync-template.md .cursor/commands/sync-template.md .claude/skills/sync-template.md .codex/skills/workflow-sync-template/SKILL.md .agents/skills/workflow-sync-template/SKILL.md`
   Confirm remaining hits (if any) are only historical bulk-phrase refusal
   language or clearly demoted escape-hatch labels — not the primary peer pair.
   Paste the command output into the implementation PR description.
5. **Optional CI doc assertion** — Only if chosen: add
   `scripts/development-workflow/tests/test-sync-template-apply-modes.sh` and
   wire it into the existing workflow test runner patterns used by nearby
   sync-template tests.
6. **Execute smoke runbook** —
   `docs/testing/workflow/1284-sync-template-decide-vs-accept.smoke-test.md`
   against the implementation diff; check every assertion.
7. **Documentation updates** — Apply the Documentation Updates checklist
   (`CHANGELOG.md` literal above; touch `AGENTS.md` /
   `docs/workflow/development-workflow/README.md` only if live search finds
   stale apply-mode wording).
8. **Open implementation PR** targeting `develop` from
   `feature/1284-sync-template-decide-vs-accept` (or the repo’s feature-branch
   naming for this path). Do not include plan-only files as the sole content of
   the feature PR; implement on a `feature/*` branch after this plan merges.

---

## Spec → Plan coverage

| Spec AC / objective | Plan coverage |
| --- | --- |
| AC1 primary Decide with me / Accept recommendations | Step 3 rewrite; Implementation Order 1; smoke Step 1 |
| AC2 Decide with me walkthrough | Step 4 Decide with me path; smoke Step 2 |
| AC3 Accept recommendations table + confirm + log | Step 4 Accept path; Code Samples; smoke Step 3 |
| AC4 hard stops unapplied without naming | Hard-stop rules + matrix; smoke Step 4 |
| AC5 resolve walkthrough vs must-name contradiction | Summary taxonomy rewrite; smoke Step 4 |
| AC6 demote always-sync only | Demoted escape hatch; smoke Step 1 |
| AC7 Claude / Cursor / Codex mirrors | Files to modify + Order 2–3; smoke Step 5 |
| AC8 no mutation before confirmations | Step 3/4 wording; smoke Step 6 |

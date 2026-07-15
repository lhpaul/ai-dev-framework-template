# Smoke Test Runbook: Fast Track Blast Radius Call-Site Volume

**Feature**: Fast Track blast-radius call-site volume
**Spec**: [1_1207-fast-track-blast-radius-call-site-volume_specs.md](../../specs/developments/20260714170008_1207-fast-track-blast-radius-call-site-volume/1_1207-fast-track-blast-radius-call-site-volume_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are on the implementation branch for issue #1207.
- [ ] The implementation diff is complete.
- [ ] No CHANGELOG verification is required for this plan PR; the later implementation PR must include its own CHANGELOG entry.

---

## Test Data

| Item | Value |
| --- | --- |
| Issue | `#1207` |
| Primary protocol | `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` |
| Fast Track mirror protocol | `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` |
| Workflow overview | `docs/workflow/development-workflow/README.md` |

---

## Smoke Test Steps

### Step 1: Verify Protocol 91 Blast-Radius Gate

**Maps to**: AC-1, AC-2, AC-3, AC-4, AC-5, AC-6, AC-8, AC-9, AC-10

1. Open `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`.
2. Locate the Fast Track routing gate in Step 2.
3. Confirm it requires identifying the primary entity when one is available.
4. Confirm it requires checking call-site volume across non-test source references.
5. Confirm it states that high call-site volume is supplementary to the existing cross-layer check.
6. Confirm it defines the high-volume threshold or where that threshold is documented.
7. Confirm it says high volume routes to Full Pipeline unless a human explicitly overrides.
8. Confirm it defines what to do when the primary entity is ambiguous.
9. Confirm it includes an external-system configuration or integration-contract prompt.
10. Confirm known or likely external-system impact blocks immediate Fast Track dispatch unless a tracked pre-flight follow-up exists.

**Expected result**: Protocol 91 alone is sufficient for a Work Item Runner to make and report the routing decision without guessing.

### Step 2: Verify Fast Track Mirror Surfaces

**Maps to**: AC-2, AC-7, AC-8, AC-9

1. Open `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`.
2. Confirm Path 3 Fast Track criteria mention the Protocol 91 blast-radius gate or include matching call-site and external-system criteria.
3. Open `docs/workflow/development-workflow/README.md`.
4. Confirm the Fast Track overview describes call-site volume as distinct from architectural layer presence.
5. Confirm neither file contradicts Protocol 91's threshold, routing outcome, or external-system handling.

**Expected result**: The overview and implementation protocol mirror the canonical routing rule without creating a second source of truth.

### Step 3: Verify Direct-Entry Agent Guidance

**Maps to**: AC-1, AC-5, AC-8, AC-9

1. Open `.claude/agents/developer.md`.
2. Open `.cursor/agents/developer.md`.
3. Open `.cursor/commands/implement-development.md`.
4. Open `.codex/skills/workflow-implementer/SKILL.md`.
5. Confirm each file points Fast Track work back to the Protocol 91 or Protocol 03 eligibility gate.
6. Confirm each file tells direct-entry implementers to stop when call-site volume or external-system impact is discovered after dispatch.

**Expected result**: Direct implementer entry points do not silently bypass the new routing evidence requirements.

### Step 4: Run Cross-Reference Search

**Maps to**: AC-2, AC-7, AC-10

1. Run searches for the changed policy terms:

   ```bash
   rg -n "Fast Track|cross-layer scope check|call-site volume|external-system|blast-radius" docs/workflow .claude .cursor .codex
   ```

2. Review the output.
3. Confirm all substantive Fast Track eligibility references either use the new terminology or explicitly defer to Protocol 91.

**Expected result**: No remaining Fast Track guidance says cross-layer signals are the only blast-radius disqualifier.

### Step 5: Run Markdown Lint

**Maps to**: all ACs

1. Run markdownlint on every changed markdown file.
2. Fix any reported trailing whitespace, relative-link, or newline issues.

**Expected result**: Markdown lint passes for the plan, runbook, and implementation documentation changes.

---

## Assertions Checklist

- [ ] AC-1: Work Item Runner Fast Track guidance requires a call-site volume check before Fast Track dispatch.
- [ ] AC-2: The guidance states call-site volume and cross-layer signals are independent Full Pipeline routing signals.
- [ ] AC-3: The guidance requires identifying the primary entity when identifiable.
- [ ] AC-4: The guidance focuses call-site volume on non-test source references.
- [ ] AC-5: High call-site volume routes to Full Pipeline and requires visible routing evidence.
- [ ] AC-6: Ambiguous primary entity handling is explicit.
- [ ] AC-7: The workflow overview documents call-site volume as distinct from layer presence.
- [ ] AC-8: Fast Track routing includes an external-system configuration prompt.
- [ ] AC-9: Known or likely external-system impact blocks immediate Fast Track implementation unless Full Pipeline or a tracked pre-flight follow-up handles it.
- [ ] AC-10: Thresholds and search mechanics are documented by the implementation.

---

## Seed Data Reference

None.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| `rg` search shows old cross-layer-only wording | A mirror surface was missed | Update the mirror or replace the duplicated criteria with a Protocol 91 reference |
| Markdownlint reports broken relative links | Link depth differs between `docs/specs/...` and `docs/testing/workflow/...` | Recalculate the relative path from the file being linted |
| Agent guidance repeats detailed thresholds differently | Criteria were duplicated outside Protocol 91 | Keep detailed thresholds in Protocol 91 and use short references elsewhere |

---

## Known Limitations

- This smoke test verifies workflow documentation behavior. It does not execute a real tracker item through Fast Track routing.

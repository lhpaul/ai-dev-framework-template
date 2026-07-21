# Graphical Design Assets in the Workflow — Spec

---

## Overview

Some backlog items arrive with graphical design references — HTML mockups,
photos, screenshots, or similar files. Today the workflow has no shared
convention for capturing those assets at backlog creation, storing them where
later stages can find them, or using them during plan and smoke validation.
This feature makes graphical design assets a first-class, lightweight workflow
input: `/add-backlog-item` can recognize and stage them, agents can discover
them reliably, and smoke/plan guidance includes fidelity checks when assets
exist — without building a full visual-regression platform.

## Brief Objective List

1. Extend `/add-backlog-item` (protocol, helper guidance, and Cursor/Claude/Codex
   command surfaces) so candidate graphical files supplied during backlog
   creation are recognized, attached or staged, and recorded for later stages.
2. Ask a brief clarifying question when it is ambiguous whether a supplied file
   is a design reference versus an incidental attachment.
3. Define a clear asset storage convention (tracker attachments and/or a
   development-folder assets location once a development folder exists).
4. Document agent discovery rules covering tracker attachments, linked files,
   development-folder assets, and backlog-creation handoff notes.
5. Extend plan and smoke-test runbook guidance so that when assets exist, smoke
   steps include expected-vs-actual UI fidelity checks against those assets.
6. Keep the solution lightweight and enabling for the separate post-merge QA
   command (#1283); do not invent a full visual-regression platform.
7. Explicitly leave full `/merged-qa` (#1283) and design-reviewer-as-primary
   fidelity gate out of this item.

## Use Cases

### Use Case 1: Capture graphical assets while creating a backlog item

**Actor**: Human operator using `/add-backlog-item` (or the matching Claude /
Codex command surface).
**Preconditions**: The operator is creating a backlog item and has supplied one
or more candidate files (chat attachments, local paths, HTML mockups, images,
or PDF mockups) along with the usual title and problem/outcome context.

**Steps**:

1. The operator invokes `/add-backlog-item` with natural-language input and one
   or more candidate files.
2. The command recognizes likely design assets by common file kinds (for
   example HTML mockups, images, and PDF mockups).
3. When intent is clear, the command attaches the assets to the tracker item
   and/or stages them according to the asset convention.
4. When intent is ambiguous (design reference versus incidental file), the
   command asks one brief clarifying question before treating the file as a
   design asset.
5. The created backlog item body records where the assets live and that later
   plan/smoke stages should use them as fidelity references.

**Postconditions**: Exactly one backlog item exists; recognized design assets
are attached or staged; the issue body points later stages to those assets.

**Information shown**:

- Created item identifier and URL.
- Which files were treated as design assets.
- Where those assets are stored (tracker attachment and/or staged path note).
- Any clarifying question asked before creation when intent was ambiguous.

**Actions available**:

- Confirm or reject ambiguous files as design references.
- Proceed with normal backlog creation when no candidate files are present.
- Continue without inventing assets when the operator supplies none.

**Considerations**:

- Files that are clearly not design references (for example logs or unrelated
  docs) must not be forced into the design-asset path.
- Creation still produces exactly one backlog item; asset handling must not
  create duplicate items across clarification turns.

### Use Case 2: Agent discovers design assets for a work item

**Actor**: Workflow agent (spec writer, plan writer, implementer, or smoke
tester) advancing an item that may have design assets.
**Preconditions**: A work item exists; assets may be present as tracker
attachments, issue-body location notes, linked files, or
development-folder assets once a development folder exists.

**Steps**:

1. Before drafting or validating UI-facing work, the agent checks the discovery
   surfaces: tracker attachments, issue-body asset notes, linked files, and
   any development-folder assets location.
2. If assets are found, the agent treats them as the expected visual reference
   for the item.
3. If no assets are found, the agent continues with normal workflow behavior
   and does not invent mockups.

**Postconditions**: When assets exist, the agent knows where they are and that
they are design references; when they do not, the agent proceeds without a
fidelity reference.

**Information shown**:

- Presence or absence of design assets.
- Canonical location(s) to read them from.
- Any issue-body note describing how later stages should use them.

**Actions available**:

- Use discovered assets as fidelity references in plan/smoke work.
- Skip fidelity checks when no assets exist.
- Ask the human only when conflicting asset locations make the expected
  reference unclear.

**Considerations**:

- Discovery must be documented in workflow guidance so agents do not depend on
  ad-hoc tribal knowledge.
- Orthogonal sibling items are not asset sources for this item.

### Use Case 3: Plan and smoke fidelity checks when assets exist

**Actor**: Plan writer (creating or updating the smoke runbook) and smoke
tester (executing the runbook).
**Preconditions**: The work item has one or more graphical design assets
discoverable via the documented convention.

**Steps**:

1. During plan/runbook authoring, the plan writer notices that design assets
   exist for the item.
2. The smoke runbook includes one or more fidelity steps that compare the
   implemented UI against the design assets (expected versus actual).
3. The smoke tester executes those steps and records PASS/FAIL with observed
   differences when the UI diverges from the reference.
4. When no design assets exist, the plan and smoke flow omit fidelity steps
   rather than inventing a visual baseline.

**Postconditions**: Assets that exist are reflected in smoke guidance; smoke
results include fidelity outcomes when those steps apply.

**Information shown**:

- Which asset(s) are the expected reference.
- Expected visual/behavior outcome for each fidelity step.
- Observed result and any material differences on failure.

**Actions available**:

- Mark fidelity steps PASS when the implemented UI matches the reference at
  the agreed lightweight level.
- Mark FAIL with expected-vs-actual notes when it does not.
- Skip fidelity steps entirely when no assets are present.

**Considerations**:

- Fidelity checks are lightweight human/agent comparisons, not a pixel-diff or
  visual-regression platform.
- Design-reviewer is not the primary fidelity gate in this MVP.
- This work enables a future post-merge QA command (#1283) but does not
  implement that command.

## Business Rules

- When the operator supplies candidate graphical files during backlog
  creation, `/add-backlog-item` must attempt to recognize likely design assets
  rather than silently ignoring them.
- Ambiguous file intent requires a brief clarifying question before treating
  the file as a design asset; unambiguous non-design files must not be staged
  as design references.
- Created backlog items that include design assets must record asset location
  and later-stage usage guidance in the item body.
- Asset storage follows a documented convention: tracker attachments at
  backlog time, and a development-folder assets location once a development
  folder exists (exact path layout is an implementation-plan detail constrained
  to stay under the item's development folder).
- Agents must discover assets from the documented surfaces before UI-facing
  plan or smoke work; absence of assets means no fidelity baseline, not a
  failure.
- When assets exist, plan/smoke guidance must include expected-vs-actual
  fidelity checks against those assets.
- This feature must remain lightweight: no full visual-regression platform,
  no mandatory automated screenshot diffing, and no requirement that every
  backlog item have design assets.
- This item enables #1283 by establishing capture, storage, discovery, and
  smoke hooks; it must not implement the post-merge QA command itself.
- Design-reviewer is not the primary mockup-fidelity gate for this MVP.
- Sibling items #1281 and #1284 are orthogonal and must not be treated as
  dependencies of this feature.

## Operational Visibility

- **Backlog evidence**: Created items that include design assets show where
  those assets live and that later stages should use them.
- **Agent discovery**: Spec, plan, implement, and smoke agents can determine
  whether design assets exist without guessing.
- **Smoke evidence**: When fidelity steps apply, smoke results record
  expected-vs-actual outcomes against the design reference.
- **Non-asset path**: Items without design assets remain fully valid and show
  no spurious fidelity failures.

## Acceptance Criteria

- [ ] AC1: Given an operator supplies one or more likely design files while
      creating a backlog item, `/add-backlog-item` recognizes them as candidate
      design assets and attaches or stages them per the documented convention.
- [ ] AC2: Given an operator supplies a file whose intent is ambiguous, the
      command asks a brief clarifying question before treating it as a design
      asset, and still creates exactly one backlog item after clarification.
- [ ] AC3: Given design assets are captured for a backlog item, the item body
      records where the assets live and that later plan/smoke stages should use
      them as fidelity references.
- [ ] AC4: Given a work item has tracker attachments and/or development-folder
      assets (once a development folder exists), a workflow agent following the
      documented discovery rules can locate those design assets without relying
      on undocumented paths.
- [ ] AC5: Given a work item has no design assets, plan and smoke guidance do
      not invent a visual baseline and do not fail solely because assets are
      absent.
- [ ] AC6: Given design assets exist for an item, the smoke runbook (authored
      or updated in the plan stage) includes at least one expected-vs-actual
      fidelity step that references those assets.
- [ ] AC7: Given a smoke tester runs a fidelity step, the result records PASS
      or FAIL with enough expected-vs-actual detail to understand any mismatch.
- [ ] AC8: Given this feature is implemented, workflow docs/commands cover the
      add-backlog capture path, storage convention, discovery rules, and
      plan/smoke fidelity hooks without introducing a full visual-regression
      platform.
- [ ] AC9: Given this feature ships, full post-merge QA (`/merged-qa`, #1283)
      and design-reviewer-as-primary fidelity gate remain out of scope and are
      not required for acceptance of this item.

## Coverage Matrix

| Brief objective | Covered by | Acceptance criteria |
| --- | --- | --- |
| 1. Extend `/add-backlog-item` to recognize, attach/stage, and record graphical assets | Use Case 1, Business Rules | AC1, AC3, AC8 |
| 2. Ask briefly when design-vs-incidental intent is ambiguous | Use Case 1, Business Rules | AC2 |
| 3. Define asset storage convention (attachments and/or development-folder assets) | Use Case 1, Business Rules | AC1, AC3, AC4 |
| 4. Document agent discovery rules | Use Case 2, Operational Visibility | AC4, AC5, AC8 |
| 5. Extend plan/smoke guidance with fidelity checks when assets exist | Use Case 3, Business Rules | AC5, AC6, AC7 |
| 6. Keep lightweight; enable #1283; no visual-regression platform | Overview, Business Rules | AC8, AC9 |
| 7. Out of scope: #1283 itself; design-reviewer as primary fidelity gate | Out of Scope, Business Rules | AC9 |

## Out of Scope (MVP)

- Full post-merge QA command `/merged-qa` (tracked separately as #1283).
  **Deferral note**: Product confirmed this item only enables #1283 via asset
  capture/discovery/smoke hooks; implementing `/merged-qa` is a separate
  backlog item. Human confirmation already recorded on #1282.
- Extending design-reviewer to be the primary mockup-fidelity gate.
  **Deferral note**: Optional follow-up unless later needed for asset
  discovery; smoke/plan fidelity hooks are the MVP gate. Human confirmation
  already recorded on #1282.
- Automated visual-regression platform (pixel diffs, baseline image vaults,
  CI screenshot suites).
  **Deferral note**: Explicitly excluded to keep the MVP lightweight.
- Changing tracker provider selection, merge authority, or unrelated workflow
  orchestration behavior.
- Touching sibling items #1281 or #1284.

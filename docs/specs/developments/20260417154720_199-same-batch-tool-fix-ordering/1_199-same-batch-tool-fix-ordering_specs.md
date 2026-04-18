# Same-Batch Tool-Fix Ordering Hazard Detection — Spec

**Depends on**: None

---

## Overview

When the Portfolio Orchestrator dispatches a parallel batch, some items may fix workflow tooling
(scripts or protocol docs) that other items in the same batch will invoke during their own PR
readiness loops. If the tool-fix item and a downstream consumer item are dispatched in parallel,
the consumer item will exercise the unfixed version of the tool, potentially hitting the exact
defect that the tool-fix item is resolving.

This feature extends Protocol 90 Step 3 (batch-building logic) and the `workflow-batch-plan.sh`
helper script to detect this ordering hazard at batch-build time and either serialize the tool-fix
item ahead of its consumers or surface a human confirmation gate before parallel dispatch proceeds.

---

## Use Cases

### Use Case 1: Orchestrator detects a tool-fix item in a candidate batch

**Actor**: Portfolio Orchestrator (automated agent running Protocol 90)

**Preconditions**:
- The orchestrator has completed Step 2 eligibility determination and is building the parallel
  batch in Step 3.
- The candidate batch contains at least one item classified as a **tool-fix item** (see
  **Business Rules — Tool-fix classification** for the canonical file set).
- The candidate batch also contains one or more other items that are not tool-fix items (i.e.,
  consumer items that are not yet `ready-for-human-review`).

**Steps**:
1. During Step 3 batch-building, the orchestrator (or `workflow-batch-plan.sh`) checks whether
   any candidate item is classified as a **tool-fix item** (see Business Rules).
2. The orchestrator checks whether the same batch contains at least one non-tool-fix item that
   is not already `ready-for-human-review` (any in-flight spec, plan, or implementation item).
3. The ordering hazard is flagged.
4. The orchestrator applies the **serialize-first** strategy: the tool-fix item is placed in its
   own serial sub-batch that must complete before the remaining items are dispatched in a
   subsequent batch.

**Postconditions**:
- The tool-fix item is dispatched first, alone.
- After the tool-fix item reaches `ready-for-human-review`, the orchestrator pauses and reports
  the situation to the human: the tool-fix must be merged before the remaining items are
  dispatched, because those items depend on the fixed tooling.
- The remaining items are held as "pending tool-fix merge" in the orchestrator's summary.

**Information shown**:
- A clear log message identifying which item is the tool-fix, which files it modifies, and which
  downstream items were held back.

**Actions available**:
- Human can merge the tool-fix PR and then re-run the orchestrator to advance the held items.
- Human can override and allow parallel dispatch anyway (explicitly acknowledging the hazard) — see Use Case 2.

**Considerations**:
- If the tool-fix item itself is already `ready-for-human-review` or `Spec in Review` / `Plan in
  Review` (already waiting for merge), the orchestrator should detect this, report it as a
  "pending tool-fix" blocker for the other items, and hold them without redispatching the tool-fix
  item.
- If there are multiple tool-fix items in the same candidate batch, each is serialized
  independently: tool-fix items are dispatched one at a time before downstream consumer items.

---

### Use Case 2: Human overrides the serialize-first gate

**Actor**: Human operator

**Preconditions**:
- The orchestrator has flagged an ordering hazard and reported it to the human (Use Case 1).
- The human has reviewed the hazard and determined that the risk is acceptable (e.g., the
  affected tool path is not actually exercised by the consumer items, or a manual workaround is
  in place).

**Steps**:
1. The human explicitly instructs the orchestrator to proceed with parallel dispatch despite the
   hazard.
2. The orchestrator logs the override, annotates the batch summary with a warning, and dispatches
   all items in parallel as originally planned.

**Postconditions**:
- All items dispatched in parallel; the tool-fix item is not serialized.
- The batch summary records the override with a human-acknowledgment note.

**Information shown**:
- A warning in the batch summary: "Human override: tool-fix ordering hazard acknowledged for
  item #N. Dispatching in parallel."

**Actions available**:
- Human can monitor progress and apply manual workarounds if the consumer items hit the unfixed
  tool defect.

**Considerations**:
- The orchestrator never applies this override autonomously; it always requires explicit human
  instruction.

---

### Use Case 3: `workflow-batch-plan.sh` emits a tool-fix hazard signal

**Actor**: Portfolio Orchestrator (reading `workflow-batch-plan.sh` output)

**Preconditions**:
- `workflow-batch-plan.sh` is invoked with one or more development folder paths as part of Step
  3 batch-building.
- At least one of the candidate development folders is classified as a tool-fix item.

**Steps**:
1. `workflow-batch-plan.sh` classifies tool-fix items from each candidate's spec/plan document
   only and emits `TOOL_FIX=yes|no|unknown` based on document evidence or availability. Tracker
   title/description signals are not read by the script; they are used separately by the
   orchestrator (see Business Rules — Tool-fix classification).
2. For tool-fix items, the script emits an additional key-value pair in its per-item output
   block: `TOOL_FIX=yes` and `TOOL_FIX_FILES=<comma-separated list of affected tool paths>`.
3. The orchestrator reads these script signals and may additionally apply tracker-derived
   classification. If tracker-derived classification indicates a tool-fix risk that the script
   output does not reflect, the orchestrator takes the conservative path and treats the item as
   a hazard candidate. The orchestrator then applies the ordering rules (Use Case 1).

**Postconditions**:
- The orchestrator has machine-readable signals to drive batch-building logic without needing to
  re-parse spec documents itself.

**Information shown**:
- `TOOL_FIX=yes` and `TOOL_FIX_FILES=...` in the `workflow-batch-plan.sh` output for affected
  items.

**Actions available**:
- Orchestrator uses these signals to apply serialize-first or to flag the hazard for human
  confirmation.

**Considerations**:
- If the spec/plan document is not yet written (e.g., the item is still in the `Writing Spec`
  state), `workflow-batch-plan.sh` should conservatively emit `TOOL_FIX=unknown` and the
  orchestrator should treat it as a potential hazard.
- The detection is pattern-based (file path matching against the known tool file list) and may
  produce false positives. This is intentional: false positives (unnecessary serialization) are
  preferable to false negatives (missed hazards).

---

## Business Rules

- **Tool-fix classification**: an item is classified as a tool-fix item if its spec document or
  implementation plan references modifications to any of the following files (exact path match,
  relative to repo root). `workflow-batch-plan.sh` determines `TOOL_FIX` exclusively from the
  spec/plan document. The orchestrator may additionally classify from tracker title/description;
  if tracker-derived classification conflicts with script output (e.g., the script emits
  `TOOL_FIX=no` but the tracker title references a tool file), the orchestrator takes the
  conservative path and treats the item as a hazard candidate:
  - `scripts/development-workflow/pr-review-loop.sh`
  - `scripts/development-workflow/pr-ci-loop.sh`
  - `scripts/development-workflow/batch-merge.sh`
  - `scripts/development-workflow/post-merge-cleanup.sh`
  - Any file matching the glob `docs/ai/development-workflow/protocols/*.md`
  - `.ai-dev-workflow.yaml`
- **Serialize-first is the default**: when a tool-fix item and a consumer item are in the same
  candidate batch, the tool-fix item must be dispatched in its own serial sub-batch first. The
  remaining items are held until the tool-fix is merged, unless the human explicitly overrides.
- **Human override is required for parallel dispatch**: the orchestrator must never autonomously
  skip the serialize-first gate. Only an explicit human instruction enables parallel dispatch
  when an ordering hazard has been detected.
- **Any non-tool-fix item in the same batch is a consumer**: a consumer item is any non-tool-fix
  item in the same candidate batch, regardless of what phase of the batch it is in. This covers
  items that will invoke the affected tool during Steps 7–8 (PR review loop, CI loop) as well as
  items that will invoke it during the batch-merge or post-merge phases. Items that are already
  `ready-for-human-review` before batch dispatch are not affected (they are no longer in-flight
  within the batch).
- **Multiple tool-fix items**: if two tool-fix items are in the same batch, they are each
  serialized. The ordering between multiple tool-fix items follows standard priority (due date,
  then priority, then creation date).
- **False positives are acceptable**: conservative over-classification as a tool-fix item is
  preferred over missed hazards. An item mis-classified as a tool-fix item results in unnecessary
  serialization, not a missed defect.
- **Scope boundary**: this feature modifies only Protocol 90 Step 3 wording and
  `workflow-batch-plan.sh`. It does not modify `pr-review-loop.sh`, `pr-ci-loop.sh`,
  `post-merge-cleanup.sh`, `batch-merge.sh`, or any other protocol.

---

## Acceptance Criteria

- [ ] When `workflow-batch-plan.sh` is run against a development folder whose spec/plan document
  references `scripts/development-workflow/pr-review-loop.sh`, the output includes
  `TOOL_FIX=yes` and `TOOL_FIX_FILES=` containing the exact repo-relative path
  `scripts/development-workflow/pr-review-loop.sh` (matched via string equality or an anchored
  regex, not a substring containment check).
- [ ] When `workflow-batch-plan.sh` is run against a development folder whose spec/plan document
  references `scripts/development-workflow/pr-ci-loop.sh`, the output includes `TOOL_FIX=yes`
  and `TOOL_FIX_FILES=` containing the exact repo-relative path
  `scripts/development-workflow/pr-ci-loop.sh` (exact-path match, not a substring).
- [ ] When `workflow-batch-plan.sh` is run against a development folder whose spec/plan document
  references a `docs/ai/development-workflow/protocols/*.md` file, the output includes
  `TOOL_FIX=yes` and `TOOL_FIX_FILES=` containing the exact matched protocol file path
  (e.g., `docs/ai/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`),
  matched via string equality or an anchored regex.
- [ ] When `workflow-batch-plan.sh` is run against a development folder whose spec/plan document
  references `scripts/development-workflow/batch-merge.sh`, the output includes `TOOL_FIX=yes`
  and `TOOL_FIX_FILES=` containing the exact repo-relative path
  `scripts/development-workflow/batch-merge.sh` (exact-path match, not a substring).
- [ ] When `workflow-batch-plan.sh` is run against a development folder whose spec/plan document
  references `scripts/development-workflow/post-merge-cleanup.sh`, the output includes
  `TOOL_FIX=yes` and `TOOL_FIX_FILES=` containing the exact repo-relative path
  `scripts/development-workflow/post-merge-cleanup.sh` (exact-path match, not a substring).
- [ ] When `workflow-batch-plan.sh` is run against a development folder whose spec/plan document
  references `.ai-dev-workflow.yaml`, the output includes `TOOL_FIX=yes` and `TOOL_FIX_FILES=`
  containing the exact repo-relative path `.ai-dev-workflow.yaml` (exact-path match, not a
  substring).
- [ ] When `workflow-batch-plan.sh` is run against a development folder with no workflow tool
  references, the output includes `TOOL_FIX=no` (the script emits an explicit `no` per the
  machine-readable `yes|no|unknown` contract, not an omitted `TOOL_FIX` line).
- [ ] When `workflow-batch-plan.sh` emits `TOOL_FIX=no` for an item but the orchestrator detects
  that the item's tracker title or description references a tool file from the canonical list,
  Protocol 90 Step 3 instructs the orchestrator to treat the item as a tool-fix hazard candidate
  (conservative override of the script output).
- [ ] When an orchestrator following Protocol 90 Step 3 encounters a batch with a tool-fix item
  alongside consumer items, the protocol instructs the orchestrator to serialize the tool-fix
  item first and hold the consumer items.
- [ ] When an orchestrator following Protocol 90 Step 3 encounters a batch with two or more
  tool-fix items alongside consumer items, the protocol instructs the orchestrator to serialize
  each tool-fix item into its own sub-batch dispatched one at a time before any consumer item
  is dispatched (i.e., the consumer items are held until every tool-fix item has reached
  `ready-for-human-review` and been merged).
- [ ] When an orchestrator following Protocol 90 Step 3 must order multiple tool-fix items that
  appear in the same candidate batch, the protocol instructs the orchestrator to apply the
  standard priority order — due date within 2 weeks (earliest first), then priority (Urgent →
  High → Normal → Low), then creation date (earliest first) — mirroring the Step 2 priority
  rules.
- [ ] Protocol 90 Step 3 explicitly names the same-batch tool-fix ordering hazard and describes
  the serialize-first rule.
- [ ] Protocol 90 Step 3 does not modify Step 5.1 (Post-Dispatch PR Verification) — that section
  remains unchanged.
- [ ] The human override path (Use Case 2) is documented in Protocol 90 Step 3 with a clear
  statement that it requires explicit human instruction.
- [ ] When `workflow-batch-plan.sh` is run against a development folder whose spec/plan document
  does not yet exist (e.g., the item is in `Writing Spec` state), the output includes
  `TOOL_FIX=unknown`.
- [ ] When the orchestrator encounters a `TOOL_FIX=unknown` item in a candidate batch alongside
  consumer items, Protocol 90 Step 3 instructs the orchestrator to treat it as a potential
  tool-fix hazard and apply the serialize-first strategy (same behavior as `TOOL_FIX=yes`).

---

## Out of Scope (MVP)

- Detecting ordering hazards for workflow scripts not in the explicitly listed set (e.g.,
  `workflow-next-action.sh`, `discover-workflow-state.sh`) — these can be added in a follow-up.
- Automatic merging of the tool-fix PR before dispatching consumer items — human merge gate is
  always required.
- Recursive dependency tracking (tool-fix item A fixes a script used by tool-fix item B which
  is also in the batch) — treat each tool-fix item independently.
- Changes to Protocol 91 internals or any protocol other than Protocol 90 Step 3.
- Changes to `pr-review-loop.sh`, `pr-ci-loop.sh`, `batch-merge.sh`, or `post-merge-cleanup.sh`.
- Modifying Protocol 90 Step 5.1 (Post-Dispatch PR Verification) — that is issue #167's scope.

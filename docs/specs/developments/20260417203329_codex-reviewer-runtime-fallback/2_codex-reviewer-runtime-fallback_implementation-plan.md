# Codex Reviewer Runtime Fallback — Implementation Plan

**Spec**: [`1_codex-reviewer-runtime-fallback_specs.md`](1_codex-reviewer-runtime-fallback_specs.md)
**Smoke test runbook**: [`../../../testing/workflow/codex-reviewer-runtime-fallback.smoke-test.md`](../../../testing/workflow/codex-reviewer-runtime-fallback.smoke-test.md)

---

## Summary

**Approach**: Update Protocol 91 Step 7a to add a runtime-availability check before dispatching any internal reviewer. The check uses runner-context identity to classify each listed reviewer as `reachable` or `unreachable`, then applies the configured policy (`warn` default or `fail-if-any-unavailable`) to decide whether to proceed, skip with a warning, or hard-fail the gate. Wherever a reviewer is skipped or the gate exits, a mandatory Step 7a summary comment is posted to the PR.

**Estimated complexity**: S

**Rationale**: The change is entirely in a single protocol document (`91-orchestrate-work-protocol.md`). No scripts, configuration schema, or integration files need new code. The new wording adds a bounded sub-section to the existing Step 7a block with clear decision tables and no architectural changes to adjacent steps.

**Dependencies**: None

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] Add `internal_reviewers_unavailable_policy` key (optional, defaults to `warn`) to the `.ai-dev-workflow.yaml` schema documentation comment. The key is purely advisory in the YAML file — Protocol 91 is the enforcement point. No schema validator enforces the key today, so add it as a documented comment-level option alongside the existing `internal_reviewers` annotation.

### Protocol / Documentation Layer

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 7a**: Insert a new sub-section titled **"Runtime-availability check"** immediately before the existing "Reviewer dispatch map" table. The sub-section must:
  1. Instruct the runner to classify each reviewer in the resolved list as `reachable` or `unreachable` based on runner-context identity (BR-8).
  2. Define the reachability classification table for known runners and reviewers (e.g., Claude Code subagent cannot invoke `codex`; direct human or Codex runner can invoke both).
  3. Apply the resolved policy:
     - If `internal_reviewers_unavailable_policy` is `warn` (default) and at least one reviewer is reachable: emit a warning comment on the PR for each skipped reviewer, log the skip, then proceed with the reachable subset.
     - If `internal_reviewers_unavailable_policy` is `fail-if-any-unavailable` and any reviewer is unreachable: hard-fail the gate (same outcome as BR-3).
     - If zero reviewers are reachable regardless of policy: hard-fail (BR-3).
  4. Specify the warning PR comment format for skipped reviewers (Use Case 1, step 4 exact wording).
  5. Specify the hard-fail PR comment format (Use Case 2, step 3 exact wording), which doubles as the BR-7 summary comment in that case.
  6. Specify the local override log message format (Use Case 4, step 5 exact wording).

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 7a "Step 7a summary comment" requirement**: Add a new rule in the multi-reviewer execution rules table (or as a standalone paragraph) mandating that a Step 7a summary comment is always posted to the PR when the gate exits — whether all reviewers ran, some were skipped, or the gate hard-failed (BR-7). Specify the required fields: effective reviewer set, skipped reviewers (with reason), and final verdict. Clarify that the hard-fail comment from BR-3 already satisfies this requirement; no separate comment is needed in that case.

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — Step 8c independent verification**: Update the "Automated reviewer loop summary" check note to clarify that the Step 7a summary comment satisfies a different requirement (internal gate visibility) and does not substitute for the Step 7 "Automated Reviewer Loop Summary" comment required for `ready-for-human-review`. No functional change to Step 8c is needed; add a brief parenthetical to avoid confusion.

---

## Testing Strategy

**Test types**: Manual / Smoke

**Key scenarios to test**:

1. `codex` unreachable from Claude Code subagent — warning posted, `claude` runs, gate succeeds (maps to Use Case 1 and AC 1–5)
2. All reviewers unreachable — hard-fail, draft PR stays draft, item escalated (maps to Use Case 2 and AC 6)
3. All reviewers reachable — no extra comments, existing behavior unchanged (maps to Use Case 3)
4. Local `.tmp/template-config.json` override present — override list used, INFO log emitted, no warning comment posted (maps to Use Case 4 and AC 8)
5. `fail-if-any-unavailable` policy — any unreachable reviewer triggers hard-fail (maps to BR-5 and AC 7 partial)

**Smoke test runbook**: [`docs/testing/workflow/codex-reviewer-runtime-fallback.smoke-test.md`](../../../testing/workflow/codex-reviewer-runtime-fallback.smoke-test.md)

---

## Seed Data

Not applicable — this feature is a protocol/documentation change with no runtime data requirements.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — primary change (see Layer-by-Layer Changes above)
- [ ] `.ai-dev-workflow.yaml` — add `internal_reviewers_unavailable_policy` as a commented-out optional key with its default value and allowed values documented inline

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Protocol wording is ambiguous for edge cases (e.g., partial reachability with `fail-if-any-unavailable`) | Low | Med | Use decision tables and worked examples in the protocol text; reviewer will catch ambiguity before merge |
| YAML comment annotation for the new policy key is misread as required | Low | Low | Mark it clearly as `# optional, default: warn` in the comment |
| Step 7a summary comment requirement conflicts with Step 8c "Automated Reviewer Loop Summary" check | Low | Low | Add a parenthetical in Step 8c clarifying they are separate requirements (Step 7a summary ≠ Step 7 summary) |

---

## Code Samples

Not applicable — changes are prose and decision-table additions to a protocol Markdown document.

---

## Implementation Order

1. Read the current `91-orchestrate-work-protocol.md` Step 7a block in full to locate the insertion points.
2. Insert the "Runtime-availability check" sub-section before the existing "Reviewer dispatch map" table in Step 7a:
   - Reachability classification table (runner context → reviewer → reachable/unreachable)
   - Policy resolution logic (`warn` vs. `fail-if-any-unavailable` vs. zero-reachable hard-fail)
   - Warning comment format for skipped reviewers
   - Hard-fail comment format (doubles as BR-7 summary in the zero-reachable case)
   - Local override log message format
3. Add the Step 7a summary comment requirement to the multi-reviewer execution rules in Step 7a (new table row or paragraph after the outcome table).
4. Add the clarifying parenthetical to the Step 8c "Automated reviewer loop summary" check row to distinguish it from the Step 7a summary comment.
5. Add `internal_reviewers_unavailable_policy` as a commented-out optional key in `.ai-dev-workflow.yaml` beneath `internal_reviewers`, with default value `warn` and valid values documented.
6. Write the smoke test runbook at `docs/testing/workflow/codex-reviewer-runtime-fallback.smoke-test.md`.
7. Verify the smoke test runbook relative link from the plan file resolves correctly (three `../` hops from `docs/specs/developments/<folder>/` to `docs/testing/workflow/`).
8. Update `CHANGELOG.md` under `[Unreleased]`.

# Stale Tracker Status Transitions — Implementation Plan

**Spec**: [1_487-stale-tracker-status-transitions_specs.md](./1_487-stale-tracker-status-transitions_specs.md)
**Smoke test runbook**: [docs/testing/workflow/487-stale-tracker-status-transitions.smoke-test.md](../../../testing/workflow/487-stale-tracker-status-transitions.smoke-test.md)

---

## Summary

**Approach**: Audit each of the three enforcement surfaces for Case A (post-merge status mapping),
then add stale "In Development" detection and correction logic (Case B) to both Protocol 90 and
Protocol 91. The audit reveals that `post-merge-cleanup.sh` and `update-tracker-on-merge.yml`
already apply correct branch-type → status mappings; the primary Case A gap is the absence of an
automated verification script (AC-9). For Case B, no stale-detection logic exists yet in either
orchestrator protocol.

**Estimated complexity**: S

**Rationale**: All three Case A enforcement surfaces already emit correct status values — the spec
confirms they must be consistent, but the actual code is already aligned. The remaining Case A work
is adding an automated check script to guard against future divergence (AC-9). Case B requires
inserting a clearly-bounded protocol rule and supporting Bash snippet in two protocol documents.
No new scripts are needed for Case B — the detection logic is prose + inline shell embedded in the
protocol text.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
|---|---|---|
| Repo revision | `git rev-parse --short HEAD` | `e37c5f0` |
| `post-merge-cleanup.sh` mapping for `spec/*` | `grep -A3 "BRANCH_TYPE.*spec" scripts/development-workflow/post-merge-cleanup.sh` | Line 210: `update_tracker_status_best_effort "$ISSUE_NUMBER" "Spec Ready"` — correct |
| `post-merge-cleanup.sh` mapping for `implementation-plan/*` | `grep -A3 "BRANCH_TYPE.*plan" scripts/development-workflow/post-merge-cleanup.sh` | Line 215: `update_tracker_status_best_effort "$ISSUE_NUMBER" "Plan Ready"` — correct |
| `post-merge-cleanup.sh` mapping for implementation branches | `grep -A1 "BRANCH_TYPE.*implementation" scripts/development-workflow/post-merge-cleanup.sh` | Line 182: `update_tracker_status_best_effort "$ISSUE_NUMBER" "Merged"` — correct |
| `update-tracker-on-merge.yml` mapping | `grep -A2 "BRANCH_TYPE\|TARGET_STATUS" .github/workflows/update-tracker-on-merge.yml \| head -20` | `spec/*` → `Spec Ready`, `implementation-plan/*` → `Plan Ready`, `feature/*`/`fix/*`/`refactor/*`/`hotfix/*` → `Merged` — correct |
| Protocol 91 Step 10 rule table | `grep -A5 "Merged PR branch type" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Lists: `spec/*` → Spec Ready, `implementation-plan/*` → Plan Ready, `feature/*`/`fix/*`/`refactor/*`/`hotfix/*` → Merged — correct |
| Stale "In Development" detection in Protocol 90 | `grep -c "stale.*In Development\|In Development.*stale" docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | 0 — no stale detection exists |
| Stale "In Development" detection in Protocol 91 | `grep -c "stale.*In Development\|In Development.*stale" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | 0 — no stale detection exists |
| Existing automated check scripts for workflow mappings | `ls scripts/development-workflow/check-*.sh scripts/lint/check-*.sh` | `check-workflow-branch.sh`, `check-changelog-duplicate-headers.sh` — no mapping verification script exists |

---

## Layer-by-Layer Changes

### Scripts / Tooling

- [ ] **Create `scripts/development-workflow/check-tracker-merge-mapping.sh`** — new verification
  script (AC-9). The script reads the branch-type → status mapping from
  `update-tracker-on-merge.yml` and asserts that each of the six required branch prefixes
  (`spec/*`, `implementation-plan/*`, `feature/*`, `fix/*`, `refactor/*`, `hotfix/*`) maps to the
  correct target status. Exits non-zero if any mapping is incorrect or missing.

### Protocol Documents

- [ ] **`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`**
  — Add a "Stale `In Development` correction" sub-step inside Step 2 (eligibility determination).
  When the portfolio scan encounters an item whose tracker status is "In Development" and the
  branch/PR existence check returns no match, the protocol must correct the status to "Plan Ready"
  and log the correction before treating the item as eligible for dispatch (AC-6, AC-7, AC-8,
  AC-10, BR-5, BR-6, BR-7, BR-8, BR-10).

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`**
  — Add a "Stale `In Development` pre-dispatch check" rule inside Step 2 (determine next
  deterministic action). When a single-item runner reads "In Development" from the tracker and the
  branch/PR existence check returns no match, the protocol must correct the status to "Plan Ready"
  and log the correction before dispatching the implementation stage (same AC set as above; see
  BR-7 — applies to items dispatched from Protocol 90 only).

### GitHub Actions Workflow

- [ ] **`.github/workflows/update-tracker-on-merge.yml`** — No mapping changes required (the
  mapping is already correct). Add one step that prints a human-readable mapping summary to the
  Actions log so reviewers can verify consistency without reading the raw YAML. This satisfies
  AC-1, AC-2, AC-3 by making the mapping explicit and auditable in CI output.

---

## Testing Strategy

**Test types**: Manual smoke test (human-readable verification of script behaviour) + code review
inspection (for protocol text correctness).

No automated unit tests are required: the new `check-tracker-merge-mapping.sh` script is itself
the AC-9 automated check (it validates the workflow YAML, not its own internal logic). The
protocol changes are prose edits — they are reviewed, not unit-tested. This plan does **not**
classify as parser-risk (no new regex scanners or lint parsers) or concurrent-event-source.

**Key scenarios to test**:

1. **AC-1/AC-2/AC-3**: Run `check-tracker-merge-mapping.sh` against the unmodified workflow —
   it should exit 0 (all six mappings correct). Manually introduce an incorrect mapping in a test
   copy and verify the script exits non-zero.
2. **AC-4**: Compare the mapping table in `post-merge-cleanup.sh` against `update-tracker-on-merge.yml`
   manually (reviewer inspection). Both already use Spec Ready / Plan Ready / Merged.
3. **AC-5**: Read Step 10 of Protocol 91 and confirm it explicitly lists the branch-type →
   status table with the correct values and includes a note prohibiting "Merged" for spec or plan
   branches.
4. **AC-6/AC-7/AC-8**: Follow the smoke test runbook steps — simulate a stale "In Development"
   item (tracker shows "In Development", no branch/PR present) and verify the protocol rule
   corrects it to "Plan Ready" and dispatches exactly once.
5. **AC-9**: Run `check-tracker-merge-mapping.sh` as a standalone script; verify exit 0 on a
   correct workflow and exit 1 on a deliberately wrong one.
6. **AC-10**: Inspect the orchestrator's run output after a stale correction and confirm the log
   note is present.

**Smoke test runbook**: `docs/testing/workflow/487-stale-tracker-status-transitions.smoke-test.md`

---

## Seed Data

Not applicable. This fix operates on tracker state and VCS state; no application seed data is
involved.

| Entity | Values / Scenario | File |
|---|---|---|
| (none) | — | — |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` —
  updated directly as part of this implementation (see Layer-by-Layer Changes).
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` —
  updated directly as part of this implementation (see Layer-by-Layer Changes).

No other `docs/project/` or `AGENTS.md` updates are required — the fix affects internal
orchestration logic, not externally documented project concepts.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The stale correction rule in Protocol 91 is triggered on items dispatched outside Protocol 90/91 (violating BR-7) | Low | Low | Scope the rule explicitly to items dispatched through Protocol 90 (i.e., when `BATCH_CONTEXT=true` OR when the runner is the item-orchestrator dispatched from the portfolio orchestrator). Direct standalone invocations of Protocol 91 by a human operator should apply no-rollback (BR-4) rather than automatic correction — document this explicitly in the rule. |
| The `check-tracker-merge-mapping.sh` script parses YAML with `grep`/`sed` and misidentifies mapping values if the YAML is reformatted | Low | Low | The YAML structure in `update-tracker-on-merge.yml` is controlled by this template and rarely changes shape. Use anchored grep patterns tied to the specific YAML key paths; document the required YAML structure in the script header. |
| Adding a log line for stale corrections (AC-10) inflates normal output when many items are in flight | Very Low | Low | The log note is emitted only when a correction is made (not on every item scan). Use a distinguishable prefix (e.g., `STALE_STATUS_CORRECTION:`) so operators can grep it selectively. |

---

## Code Samples

> All code samples below are illustrative — adapt during implementation.

### Illustrative: `check-tracker-merge-mapping.sh` core logic

```bash
# Illustrative — adapt during implementation
# Asserts that update-tracker-on-merge.yml maps each branch prefix to the correct status.
# Returns exit 1 if any mapping is wrong or missing.

declare -A EXPECTED_MAPPING
EXPECTED_MAPPING["spec"]="Spec Ready"
EXPECTED_MAPPING["implementation-plan"]="Plan Ready"
EXPECTED_MAPPING["feature"]="Merged"
EXPECTED_MAPPING["fix"]="Merged"
EXPECTED_MAPPING["refactor"]="Merged"
EXPECTED_MAPPING["hotfix"]="Merged"

WORKFLOW_FILE=".github/workflows/update-tracker-on-merge.yml"
ERRORS=0

for PREFIX in "${!EXPECTED_MAPPING[@]}"; do
  EXPECTED="${EXPECTED_MAPPING[$PREFIX]}"
  # Locate the TARGET_STATUS line that follows the branch-type detection block for this prefix
  ACTUAL=$(grep -A3 "${PREFIX}/\*" "$WORKFLOW_FILE" | grep "TARGET_STATUS=" | head -1 | sed 's/.*TARGET_STATUS="\([^"]*\)".*/\1/')
  if [ "$ACTUAL" != "$EXPECTED" ]; then
    echo "ERROR: branch '$PREFIX/*' → expected '$EXPECTED', got '${ACTUAL:-missing}'"
    ERRORS=$((ERRORS + 1))
  fi
done

[ "$ERRORS" -eq 0 ] && echo "All mappings correct." || exit 1
```

### Illustrative: Stale "In Development" detection snippet for Protocol 90 Step 2

```bash
# Illustrative — adapt during implementation
# Inline example for the protocol rule; not a standalone script.
if [ "$TRACKER_STATUS" = "In Development" ]; then
  ISSUE_NUMBER="<extracted from item>"
  # Check for any implementation branch or PR
  HAS_BRANCH=$(git ls-remote origin "refs/heads/feature/${ISSUE_NUMBER}-*" \
    "refs/heads/fix/${ISSUE_NUMBER}-*" \
    "refs/heads/refactor/${ISSUE_NUMBER}-*" \
    "refs/heads/hotfix/${ISSUE_NUMBER}-*" 2>/dev/null | wc -l)
  HAS_PR=$(gh pr list --state open --search "is:pr #${ISSUE_NUMBER}" \
    --json headRefName --jq "[.[] | select(.headRefName | test(\"/(feature|fix|refactor|hotfix)/\"))] | length" 2>/dev/null || echo 0)
  if [ "$HAS_BRANCH" -eq 0 ] && [ "$HAS_PR" -eq 0 ]; then
    echo "STALE_STATUS_CORRECTION: issue #${ISSUE_NUMBER} tracker shows 'In Development' but no branch or PR found. Correcting to 'Plan Ready'."
    update_tracker_status_best_effort "$ISSUE_NUMBER" "Plan Ready"
    TRACKER_STATUS="Plan Ready"
  fi
fi
```

---

## Implementation Order

1. **Read and understand all three Case A surfaces** — verify the current mapping in
   `post-merge-cleanup.sh`, `update-tracker-on-merge.yml`, and Protocol 91 Step 10. Confirm they
   are already consistent (Verification Log above confirms this).

2. **Create `scripts/development-workflow/check-tracker-merge-mapping.sh`** (AC-9):
   - Parse the `update-tracker-on-merge.yml` detect step to extract the actual `TARGET_STATUS`
     value assigned for each supported branch prefix.
   - Assert the six expected mappings: `spec/*` → `Spec Ready`, `implementation-plan/*` →
     `Plan Ready`, `feature/*` / `fix/*` / `refactor/*` / `hotfix/*` → `Merged`.
   - Exit 0 when all mappings are correct; exit 1 with a descriptive error line for each
     incorrect or missing mapping.
   - Add a `#!/usr/bin/env bash` header, `set -euo pipefail`, and a short usage comment.
   - Make the file executable: `chmod +x scripts/development-workflow/check-tracker-merge-mapping.sh`.
   - Verification: run the script against the unmodified workflow and confirm exit 0; manually
     alter one `TARGET_STATUS` value in a temp copy and confirm exit 1.

3. **Add the "Stale `In Development` correction" rule to Protocol 90 Step 2** (AC-6, AC-7, AC-8,
   AC-10):
   - Insert a new sub-step immediately after the eligibility scan in Step 2 (after the per-item
     tracker status read loop, before building the candidate list for Step 3).
   - The rule must:
     - Apply only when the tracker status is exactly "In Development".
     - Check for any open or unmerged implementation branch (`feature/*`, `fix/*`,
       `refactor/*`, `hotfix/*`) with an issue-number segment matching the item ID, using
       `git ls-remote` and `gh pr list`.
     - Apply only when **both** branch and PR checks return empty (BR-5).
     - Correct the status to "Plan Ready" using `update_tracker_status_best_effort` (BR-6).
     - Emit a log line prefixed `STALE_STATUS_CORRECTION:` (BR-10, AC-10).
     - Treat the now-corrected item as eligible for dispatch in the "Plan Ready" row of the
       Step 2 eligibility table (BR-6).
     - Note that the item is dispatched at most once per run (BR-8) — the correction itself
       does not create an extra dispatch; the item simply advances through the normal Plan Ready
       path.
   - Scope the rule explicitly to the portfolio orchestrator run (BR-7): items discovered outside
     a Protocol 90/91 orchestrated run are not covered.

4. **Add the "Stale `In Development` pre-dispatch check" rule to Protocol 91 Step 2** (same
   AC/BR set; BR-7 scoping):
   - Insert a new block immediately after the "Pre-dispatch tracker status update (single-item
     path)" sub-section (i.e., before the "Pre-dispatch branch check" sub-section).
   - The rule must match the logic in Step 3 above (same checks, same correction target, same
     log prefix).
   - Scope explicitly: this rule applies only when the Work Item Runner was dispatched from the
     Portfolio Orchestrator (i.e., `BATCH_CONTEXT=true` or the runner is `item-orchestrator`).
     A direct human invocation that encounters "In Development" with no branch should prompt the
     human rather than silently resetting — document this distinction.

5. **Add a mapping-summary log step to `update-tracker-on-merge.yml`** — append a `run:` step
   to the `update-tracker` job that prints the branch → status mapping in a human-readable form
   to the Actions log after the detect step. This satisfies the intent of AC-1/AC-2/AC-3 by
   making the mapping visible in every CI run's output. The step is informational only (no
   assertions); assertions are the responsibility of `check-tracker-merge-mapping.sh`.

6. **Update CHANGELOG.md** under `[Unreleased]`:

   ```markdown
   - **Fix stale tracker status transitions in orchestrator pre-dispatch** (#487): corrects
     post-merge status mapping documentation and adds stale "In Development" detection and
     correction to Protocol 90 and 91; adds `check-tracker-merge-mapping.sh` to verify the
     workflow-to-tracker mapping (AC-9).
   ```

7. **Verify the smoke test runbook** — follow `docs/testing/workflow/487-stale-tracker-status-transitions.smoke-test.md`
   to manually confirm the new protocol rules are coherent and the check script behaves correctly.

8. **Update project docs per Documentation Updates section** — no external docs require changes
   beyond the protocol files already modified in this implementation.

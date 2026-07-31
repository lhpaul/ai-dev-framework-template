# Smoke Test Runbook: Delivery Bundle Issue And Manifest Workflow

**Feature**: Delivery bundle issue and manifest workflow
**Spec**:
[`1_1357-delivery-bundle-issue-manifest-workflow_specs.md`](../../specs/developments/20260731164352_1357-delivery-bundle-issue-manifest-workflow/1_1357-delivery-bundle-issue-manifest-workflow_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are on the #1357 implementation branch after the implementation PR
      changes are present.
- [ ] `jq`, `git`, and Bash are available.
- [ ] The repository has no unrelated local changes that would obscure smoke
      test output.
- [ ] `scripts/development-workflow/delivery-bundle-manifest.sh` exists and is
      executable.

---

## Test Data

| Item | Value |
| --- | --- |
| Parent epic | `#1352` |
| Bundle title | `Mobile and Web July delivery` |
| Manifest path | `$SMOKE_TMP/delivery-bundle.json` |
| Component A | `mobile-app` with complete release evidence |
| Component B | `web-app` with complete release evidence |
| Negative component | `api-service` with pending or failed outcome evidence |

Create a temp directory before running the steps:

```bash
SMOKE_TMP="$(mktemp -d)"
trap 'rm -rf "$SMOKE_TMP"' EXIT
```

The implementation may provide a fixture helper. If it does, use that helper to
write the component evidence files. If no helper exists, create minimal
`component_release_evidence.v1` JSON files matching the final helper's required
fields.

---

## Smoke Test Steps

### Step 1: Create A Delivery Bundle

**Maps to**: Acceptance Criteria 1 and 2

1. Run the delivery bundle helper's create command with bundle title, purpose,
   parent epic `#1352`, declared components `mobile-app` and `web-app`, known
   child items, finalization owner, and rollout notes.
2. Write the manifest to `$SMOKE_TMP/delivery-bundle.json`.
3. Inspect the JSON with `jq`.

**Expected result**: The manifest uses schema
`delivery_bundle_manifest.v1`, has revision `1`, status `open`, includes the
bundle metadata, records declared components, and has a creation audit event.

### Step 2: Attach Complete Component Evidence

**Maps to**: Acceptance Criterion 3

1. Generate or provide a complete `component_release_evidence.v1` file for
   `mobile-app`.
2. Run the helper's component update command against the current manifest
   revision.
3. Inspect the updated manifest.

**Expected result**: The manifest revision increments, the `mobile-app`
component entry records stable identity fields, version or tag, source and
release pull requests, routing outcome, release outcome, CI outcome, deployment
outcome, cleanup outcome, hub tracker reconciliation outcome, child release
state, and an update audit event. The `web-app` entry remains present.

### Step 3: Reapply Identical Evidence

**Maps to**: Acceptance Criterion 4

1. Re-run the same component update command with the same `mobile-app` evidence.
2. Inspect the manifest and helper output.

**Expected result**: The helper reports an idempotent replay or no-op. The
manifest does not contain a duplicate `mobile-app` component entry.

### Step 4: Inspect An Incomplete Bundle

**Maps to**: Acceptance Criterion 5

1. Run the helper's inspect command with JSON output.
2. Read the blocker summary for `web-app`.

**Expected result**: Inspection reports that `web-app` is missing required
component release evidence and names the missing finalization requirements,
including release, CI, deployment, cleanup, hub tracker reconciliation, and
child release-state evidence.

### Step 5: Reject Conflicting Evidence

**Maps to**: Acceptance Criterion 6

1. Copy the accepted `mobile-app` evidence and change one stable identity field,
   version or tag, release correlation key, or contract revision.
2. Run the component update command with the conflicting evidence.
3. Compare the manifest before and after the command.

**Expected result**: The helper exits non-zero, reports a conflict, and leaves
the accepted manifest state unchanged.

### Step 6: Reject Stale Revision Mutation

**Maps to**: Acceptance Criterion 7

1. Record an older manifest revision number.
2. Advance the manifest with a valid update or removal.
3. Attempt another update or finalization using the older expected revision.

**Expected result**: The helper exits non-zero, reports stale revision state,
and leaves the current manifest unchanged.

### Step 7: Remove A Component Before Finalization

**Maps to**: Acceptance Criterion 8

1. Remove one declared component with an explicit removal reason.
2. Inspect the manifest and historical revision data.

**Expected result**: The manifest revision increments, the current component
list no longer includes the removed component, the removal reason is recorded,
the audit trail includes the removal event, and prior revision history remains
available for audit.

### Step 8: Invalidate Readiness After Mutation

**Maps to**: Acceptance Criterion 9

1. Build a bundle that reaches `ready_to_finalize`.
2. Add, update, or remove a component before finalization.
3. Inspect the bundle status.

**Expected result**: The bundle leaves `ready_to_finalize` and returns to
`open` or `blocked`; readiness must be recomputed for the current revision.

### Step 9: Block Invalid Finalization

**Maps to**: Acceptance Criteria 10, 11, and 12

1. Attempt finalization with a component missing a version or tag.
2. Attempt finalization with missing release, CI, deployment, cleanup, hub
   tracker reconciliation, or child release-state evidence.
3. Attempt finalization with failed, blocked, pending, conflicting, or stale
   outcomes.

**Expected result**: Every invalid finalization attempt exits non-zero, reports
the blocking component and requirement, and leaves the manifest unfinalized.

### Step 10: Finalize A Complete Bundle

**Maps to**: Acceptance Criteria 13 and 14

1. Attach complete evidence for every declared component.
2. Run inspect or finalization readiness computation for the current revision.
3. Run the finalization command.
4. Inspect the final manifest.

**Expected result**: The manifest status is `finalized`, the revision
increments, the finalization audit event is present, every component has
complete and consistent evidence for the finalized revision, and no shared
suite version or shared release branch is created.

### Step 11: Preserve Source Evidence

**Maps to**: Acceptance Criterion 15

1. Hash each source `component_release_evidence.v1` file before bundle create,
   update, inspect, removal, and finalization commands.
2. Hash the same evidence files again after all commands.

**Expected result**: Source component release evidence files are unchanged.

### Last Step: Validate And Shut Down

- Verify all assertions in the checklist below are met.
- Remove `$SMOKE_TMP` through the trap or manual cleanup.

---

## Assertions Checklist

- [ ] AC1: A hub-owned delivery bundle can be created from required template
      metadata.
- [ ] AC2: The delivery manifest is authoritative and records the current
      revision.
- [ ] AC3: Completed component release evidence updates one matching component
      without losing unrelated entries.
- [ ] AC4: Identical evidence replay does not duplicate component entries.
- [ ] AC5: Inspection reports missing and stale finalization requirements.
- [ ] AC6: Conflicting evidence stops without mutating accepted state.
- [ ] AC7: Stale revision writes stop without mutating accepted state.
- [ ] AC8: Component removal records a reason and preserves prior revisions.
- [ ] AC9: Mutations after readiness invalidate readiness.
- [ ] AC10: Missing component version or tag blocks finalization.
- [ ] AC11: Missing required evidence blocks finalization.
- [ ] AC12: Failed, blocked, pending, missing, conflicting, or stale outcomes
      block finalization.
- [ ] AC13: Finalization succeeds only with complete current-revision evidence
      and records the finalization atomically.
- [ ] AC14: Finalization does not create a shared suite version or release
      branch.
- [ ] AC15: Existing component release evidence remains unchanged.

---

## Seed Data Reference

| Entity | Scenario | How to load |
| --- | --- | --- |
| Bundle metadata | Parent epic `#1352`, two declared components, finalization owner, and rollout notes | Pass as helper arguments or a helper-supported metadata JSON fixture. |
| Complete component evidence | Completed release, passed CI, recorded deployment, complete cleanup, complete hub reconciliation, and released or merged child state | Use the implementation's fixture helper or create `component_release_evidence.v1` JSON in `$SMOKE_TMP`. |
| Invalid component evidence | Missing version, conflicting stable identity, stale revision, failed outcome, blocked outcome, pending outcome, and malformed JSON | Mutate fixture copies in `$SMOKE_TMP`. |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Helper reports missing command or file | Implementation branch is not checked out or helper is not executable | Check out the #1357 implementation branch and run `chmod +x` only if the implementation forgot executable mode. |
| `jq` validation fails on fixture input | Fixture is missing required final helper fields | Regenerate fixtures from the implementation's fixture helper or update the minimal JSON to match the documented schema. |
| Finalization remains blocked after complete evidence | One outcome field is still pending, failed, blocked, missing, conflicting, or stale | Run inspect with JSON output and correct the named blocker. |
| Source evidence hash changes | Bundle helper rewrote component release evidence | Treat as a test failure; bundle commands must only read component evidence. |

---

## Known Limitations

- This smoke test validates hub-owned workflow behavior only. It does not test
  #1358 milestone reconciliation or #1359 adoption and assurance workflows.

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
| Delivery purpose | `Coordinated customer-facing July workflow-hub delivery` |
| Finalization owner | `@workflow-operator` |
| Rollout notes | `Roll out mobile and web components independently; no shared suite branch.` |
| Known child items | `#1356`, `#1357` |
| Bundle key | `mobile-web-july-delivery` |
| Manifest path | `$SMOKE_TMP/delivery-bundle.json` |
| Component A | `mobile-app`, tag `mobile-v1.4.0`, version `1.4.0` |
| Component B | `web-app`, tag `web-v2.8.1`, version `2.8.1` |
| Incomplete component fixture | `web-app` declared in Step 1 but missing evidence until Step 10 |
| Negative fixture source | Mutated copies of `mobile-app` or `web-app` evidence |

Create a temp directory and common shell variables before running the steps:

```bash
set -euo pipefail

if ! SMOKE_TMP="$(mktemp -d)" || [ -z "$SMOKE_TMP" ] || [ ! -d "$SMOKE_TMP" ]; then
  echo "ERROR_CODE=smoke_tmp_setup_failed message='failed to create temp directory'" >&2
  exit 1
fi
cleanup_smoke_tmp() {
  if [ -n "${SMOKE_TMP:-}" ] && [ -d "$SMOKE_TMP" ]; then
    rm -rf "$SMOKE_TMP"
  fi
}
trap cleanup_smoke_tmp EXIT

HELPER="scripts/development-workflow/delivery-bundle-manifest.sh"
BUNDLE_KEY="mobile-web-july-delivery"
BUNDLE="$SMOKE_TMP/delivery-bundle.json"
MOBILE_EVIDENCE="$SMOKE_TMP/mobile-evidence.json"
WEB_EVIDENCE="$SMOKE_TMP/web-evidence.json"
```

The implementation may provide a fixture helper. If it does, use that helper to
write `$MOBILE_EVIDENCE` and `$WEB_EVIDENCE`. If no helper exists, create
minimal `component_release_evidence.v1` JSON files matching the final helper's
required fields.

Use this evidence-integrity guard immediately before and after every command
that reads a `component_release_evidence.v1` file:

```bash
BEFORE_HASH="$(git hash-object "$MOBILE_EVIDENCE" "$WEB_EVIDENCE" 2>/dev/null || true)"
# Run exactly one bundle command here.
AFTER_HASH="$(git hash-object "$MOBILE_EVIDENCE" "$WEB_EVIDENCE" 2>/dev/null || true)"
test "$BEFORE_HASH" = "$AFTER_HASH"
```

---

## Smoke Test Steps

### Step 1: Create A Delivery Bundle

**Maps to**: Acceptance Criteria 1 and 2

```bash
"$HELPER" create \
  --manifest "$BUNDLE" \
  --bundle-key "$BUNDLE_KEY" \
  --title "Mobile and Web July delivery" \
  --purpose "Coordinated customer-facing July workflow-hub delivery" \
  --parent-ref "#1352" \
  --component mobile-app \
  --component web-app \
  --child-item "#1356" \
  --child-item "#1357" \
  --finalization-owner "@workflow-operator" \
  --rollout-notes "Roll out mobile and web components independently; no shared suite branch." \
  --json

jq -e '
  .schema_version == "delivery_bundle_manifest.v1" and
  .bundle_key == "mobile-web-july-delivery" and
  .revision == 1 and
  .status == "open" and
  .parent_ref == "#1352" and
  (.components | length) == 2 and
  (.audit_events | length) == 1
' "$BUNDLE"
```

**Expected result**: The manifest uses schema
`delivery_bundle_manifest.v1`, has revision `1`, status `open`, includes the
bundle metadata, records `mobile-app` and `web-app`, and has a creation audit
event.

### Step 2: Attach Complete Component Evidence

**Maps to**: Acceptance Criterion 3

```bash
REVISION="$(jq -r '.revision' "$BUNDLE")"

"$HELPER" update-component \
  --manifest "$BUNDLE" \
  --bundle-key "$BUNDLE_KEY" \
  --expected-revision "$REVISION" \
  --component-key mobile-app \
  --evidence-file "$MOBILE_EVIDENCE" \
  --component-tag mobile-v1.4.0 \
  --component-version 1.4.0 \
  --source-pr 1411 \
  --release-pr 1501 \
  --child-item "#1356" \
  --child-release-state merged \
  --json

jq -e '
  .revision == 2 and
  (.components[] | select(.component_key == "mobile-app") |
    .component_tag == "mobile-v1.4.0" and
    .component_version == "1.4.0" and
    .evidence_state == "verified") and
  (.components[] | select(.component_key == "web-app"))
' "$BUNDLE"
```

**Expected result**: The manifest revision increments. The `mobile-app` entry
records stable identity fields, required component tag, optional component
version, source and release pull requests, routing outcome, release outcome, CI
outcome, deployment outcome, cleanup outcome, hub tracker reconciliation
outcome, child release state, and an update audit event. The `web-app` entry
remains present and incomplete.

### Step 3: Reapply Identical Evidence

**Maps to**: Acceptance Criterion 4

```bash
REVISION_BEFORE="$(jq -r '.revision' "$BUNDLE")"
AUDIT_COUNT_BEFORE="$(jq -r '.audit_events | length' "$BUNDLE")"

"$HELPER" update-component \
  --manifest "$BUNDLE" \
  --bundle-key "$BUNDLE_KEY" \
  --expected-revision "$REVISION_BEFORE" \
  --component-key mobile-app \
  --evidence-file "$MOBILE_EVIDENCE" \
  --component-tag mobile-v1.4.0 \
  --component-version 1.4.0 \
  --source-pr 1411 \
  --release-pr 1501 \
  --child-item "#1356" \
  --child-release-state merged \
  --json

test "$REVISION_BEFORE" = "$(jq -r '.revision' "$BUNDLE")"
test "$AUDIT_COUNT_BEFORE" = "$(jq -r '.audit_events | length' "$BUNDLE")"
test "$(jq '[.components[] | select(.component_key == "mobile-app")] | length' "$BUNDLE")" = "1"
```

**Expected result**: The helper reports an idempotent replay or no-op. Revision,
audit-event count, and component entry count stay unchanged.

### Step 4: Inspect An Incomplete Bundle

**Maps to**: Acceptance Criterion 5

```bash
"$HELPER" inspect \
  --manifest "$BUNDLE" \
  --bundle-key "$BUNDLE_KEY" \
  --json > "$SMOKE_TMP/inspect-partial.json"

jq -e '
  .status == "blocked" and
  (.components[] | select(.component_key == "web-app") |
    .evidence_state == "missing" and
    (.blockers | index("routing_evidence_missing")) and
    (.blockers | index("release_evidence_missing")) and
    (.blockers | index("ci_evidence_missing")) and
    (.blockers | index("deployment_evidence_missing")) and
    (.blockers | index("cleanup_evidence_missing")) and
    (.blockers | index("hub_tracker_reconciliation_missing")) and
    (.blockers | index("child_release_state_missing")))
' "$SMOKE_TMP/inspect-partial.json"
```

**Expected result**: Inspection reports that `web-app` is missing required
component release evidence and names every missing finalization requirement,
including routing evidence.

### Step 5: Reject Conflicting Evidence

**Maps to**: Acceptance Criterion 6

```bash
cp "$MOBILE_EVIDENCE" "$SMOKE_TMP/mobile-conflict.json"
jq '.contract_revision = "sha256:conflict"' \
  "$SMOKE_TMP/mobile-conflict.json" > "$SMOKE_TMP/mobile-conflict.tmp"
mv "$SMOKE_TMP/mobile-conflict.tmp" "$SMOKE_TMP/mobile-conflict.json"

MANIFEST_HASH_BEFORE="$(git hash-object "$BUNDLE")"
REVISION="$(jq -r '.revision' "$BUNDLE")"

if "$HELPER" update-component \
  --manifest "$BUNDLE" \
  --bundle-key "$BUNDLE_KEY" \
  --expected-revision "$REVISION" \
  --component-key mobile-app \
  --evidence-file "$SMOKE_TMP/mobile-conflict.json" \
  --component-tag mobile-v1.4.0 \
  --component-version 1.4.0 \
  --source-pr 1411 \
  --release-pr 1501 \
  --child-item "#1356" \
  --child-release-state merged \
  --json 2> "$SMOKE_TMP/conflict.err"
then
  echo "conflicting evidence was accepted" >&2
  exit 1
fi

rg -q 'ERROR_CODE=conflicting_component_evidence' "$SMOKE_TMP/conflict.err"
test "$MANIFEST_HASH_BEFORE" = "$(git hash-object "$BUNDLE")"
```

**Expected result**: The helper exits non-zero, reports a conflict, and leaves
the accepted manifest state unchanged.

### Step 6: Reject Stale Revision Mutation

**Maps to**: Acceptance Criterion 7

```bash
STALE_REVISION="$(jq -r '.revision' "$BUNDLE")"

"$HELPER" remove-component \
  --manifest "$BUNDLE" \
  --bundle-key "$BUNDLE_KEY" \
  --expected-revision "$STALE_REVISION" \
  --component-key web-app \
  --reason "Temporarily split web delivery from this bundle" \
  --json

REVISION_AFTER_REMOVAL="$(jq -r '.revision' "$BUNDLE")"
test "$REVISION_AFTER_REMOVAL" -gt "$STALE_REVISION"
jq -e '([.components[] | select(.component_key == "web-app")] | length) == 0' "$BUNDLE"

MANIFEST_HASH_BEFORE="$(git hash-object "$BUNDLE")"

if "$HELPER" finalize \
  --manifest "$BUNDLE" \
  --bundle-key "$BUNDLE_KEY" \
  --expected-revision "$STALE_REVISION" \
  --json 2> "$SMOKE_TMP/stale.err"
then
  echo "stale finalization was accepted" >&2
  exit 1
fi

rg -q 'ERROR_CODE=stale_manifest_revision' "$SMOKE_TMP/stale.err"
test "$MANIFEST_HASH_BEFORE" = "$(git hash-object "$BUNDLE")"
```

**Expected result**: The helper exits non-zero, reports stale revision state,
and leaves the current manifest unchanged.

### Step 7: Verify Component Removal Audit

**Maps to**: Acceptance Criterion 8

```bash
jq -e '
  .revision == 3 and
  ([.components[] | select(.component_key == "web-app")] | length) == 0 and
  (.removed_components[] |
    .component_key == "web-app" and
    .reason == "Temporarily split web delivery from this bundle") and
  (.audit_events[] | select(.event == "component_removed"))
' "$BUNDLE"
```

**Expected result**: The current component list excludes `web-app`, the removal
reason is recorded, the audit trail includes the removal event, and prior
revision history remains available for audit.

### Step 8: Invalidate Readiness After Each Mutation Type

**Maps to**: Acceptance Criterion 9

Create a complete bundle fixture that reaches `ready_to_finalize`, then run
separate add, update, and removal cases:

```bash
"$HELPER" create \
  --manifest "$SMOKE_TMP/ready-bundle.json" \
  --bundle-key "$BUNDLE_KEY" \
  --title "Mobile and Web July delivery" \
  --purpose "Coordinated customer-facing July workflow-hub delivery" \
  --parent-ref "#1352" \
  --component mobile-app \
  --component web-app \
  --child-item "#1356" \
  --child-item "#1357" \
  --finalization-owner "@workflow-operator" \
  --rollout-notes "Roll out mobile and web components independently; no shared suite branch." \
  --json

"$HELPER" update-component \
  --manifest "$SMOKE_TMP/ready-bundle.json" \
  --bundle-key "$BUNDLE_KEY" \
  --expected-revision "$(jq -r '.revision' "$SMOKE_TMP/ready-bundle.json")" \
  --component-key mobile-app \
  --evidence-file "$MOBILE_EVIDENCE" \
  --component-tag mobile-v1.4.0 \
  --component-version 1.4.0 \
  --source-pr 1411 \
  --release-pr 1501 \
  --child-item "#1356" \
  --child-release-state merged \
  --json

"$HELPER" update-component \
  --manifest "$SMOKE_TMP/ready-bundle.json" \
  --bundle-key "$BUNDLE_KEY" \
  --expected-revision "$(jq -r '.revision' "$SMOKE_TMP/ready-bundle.json")" \
  --component-key web-app \
  --evidence-file "$WEB_EVIDENCE" \
  --component-tag web-v2.8.1 \
  --component-version 2.8.1 \
  --source-pr 1414 \
  --release-pr 1503 \
  --child-item "#1357" \
  --child-release-state merged \
  --json

"$HELPER" inspect \
  --manifest "$SMOKE_TMP/ready-bundle.json" \
  --bundle-key "$BUNDLE_KEY" \
  --json > "$SMOKE_TMP/ready-inspect.json"

jq -e '.status == "ready_to_finalize"' "$SMOKE_TMP/ready-inspect.json"

cp "$SMOKE_TMP/ready-bundle.json" "$SMOKE_TMP/ready-add.json"
cp "$SMOKE_TMP/ready-bundle.json" "$SMOKE_TMP/ready-update.json"
cp "$SMOKE_TMP/ready-bundle.json" "$SMOKE_TMP/ready-remove.json"
```

For the add case:

```bash
"$HELPER" add-component \
  --manifest "$SMOKE_TMP/ready-add.json" \
  --bundle-key "$BUNDLE_KEY" \
  --expected-revision "$(jq -r '.revision' "$SMOKE_TMP/ready-add.json")" \
  --component-key api-service \
  --json

jq -e '
  (.status == "open" or .status == "blocked") and
  (
    .readiness == null or
    (.readiness.revision == .revision and .readiness.status != "ready_to_finalize")
  )
' "$SMOKE_TMP/ready-add.json"
```

For the update case:

```bash
"$HELPER" update-component \
  --manifest "$SMOKE_TMP/ready-update.json" \
  --bundle-key "$BUNDLE_KEY" \
  --expected-revision "$(jq -r '.revision' "$SMOKE_TMP/ready-update.json")" \
  --component-key mobile-app \
  --evidence-file "$MOBILE_EVIDENCE" \
  --component-tag mobile-v1.4.1 \
  --component-version 1.4.1 \
  --source-pr 1411 \
  --release-pr 1502 \
  --child-item "#1356" \
  --child-release-state merged \
  --json

jq -e '
  (.status == "open" or .status == "blocked") and
  (
    .readiness == null or
    (.readiness.revision == .revision and .readiness.status != "ready_to_finalize")
  )
' "$SMOKE_TMP/ready-update.json"
```

For the removal case:

```bash
"$HELPER" remove-component \
  --manifest "$SMOKE_TMP/ready-remove.json" \
  --bundle-key "$BUNDLE_KEY" \
  --expected-revision "$(jq -r '.revision' "$SMOKE_TMP/ready-remove.json")" \
  --component-key web-app \
  --reason "Exclude web from this finalized bundle" \
  --json

jq -e '
  (.status == "open" or .status == "blocked") and
  (
    .readiness == null or
    (.readiness.revision == .revision and .readiness.status != "ready_to_finalize")
  )
' "$SMOKE_TMP/ready-remove.json"
```

**Expected result**: Add, update, and removal each leave
`ready_to_finalize`. Readiness is cleared or recomputed for the current
revision; stale readiness from the prior revision is not retained.

### Step 9: Block Invalid Finalization

**Maps to**: Acceptance Criteria 10, 11, and 12

```bash
jq 'del((.components[] | select(.component_key == "mobile-app")).component_tag)' \
  "$SMOKE_TMP/ready-bundle.json" > "$SMOKE_TMP/missing-tag.json"
jq '(.components[] | select(.component_key == "web-app")).evidence_state = "missing"' \
  "$SMOKE_TMP/ready-bundle.json" > "$SMOKE_TMP/missing-evidence.json"
jq '(.components[] | select(.component_key == "mobile-app")).release_outcome = "failed"' \
  "$SMOKE_TMP/ready-bundle.json" > "$SMOKE_TMP/failed-outcome.json"
jq '(.components[] | select(.component_key == "mobile-app")).release_outcome = "blocked"' \
  "$SMOKE_TMP/ready-bundle.json" > "$SMOKE_TMP/blocked-outcome.json"
jq '(.components[] | select(.component_key == "mobile-app")).ci_outcome = "pending"' \
  "$SMOKE_TMP/ready-bundle.json" > "$SMOKE_TMP/pending-outcome.json"
jq '(.components[] | select(.component_key == "mobile-app")).evidence_state = "conflicting"' \
  "$SMOKE_TMP/ready-bundle.json" > "$SMOKE_TMP/conflicting-outcome.json"
jq '.readiness.revision = (.revision - 1)' \
  "$SMOKE_TMP/ready-bundle.json" > "$SMOKE_TMP/stale-readiness.json"

for fixture in \
  "$SMOKE_TMP/missing-tag.json|missing_component_tag" \
  "$SMOKE_TMP/missing-evidence.json|missing_component_evidence" \
  "$SMOKE_TMP/failed-outcome.json|blocked_component_outcome" \
  "$SMOKE_TMP/blocked-outcome.json|blocked_component_outcome" \
  "$SMOKE_TMP/pending-outcome.json|pending_component_outcome" \
  "$SMOKE_TMP/conflicting-outcome.json|conflicting_component_evidence" \
  "$SMOKE_TMP/stale-readiness.json|stale_readiness"
do
  fixture_path="${fixture%%|*}"
  expected_error="${fixture##*|}"
  stderr_path="$fixture_path.err"
  MANIFEST_HASH_BEFORE="$(git hash-object "$fixture_path")"
  if "$HELPER" finalize \
    --manifest "$fixture_path" \
    --bundle-key "$BUNDLE_KEY" \
    --expected-revision "$(jq -r '.revision' "$fixture_path")" \
    --json 2> "$stderr_path"
  then
    echo "invalid finalization was accepted for $fixture_path" >&2
    exit 1
  fi
  rg -q "ERROR_CODE=$expected_error" "$stderr_path"
  test "$MANIFEST_HASH_BEFORE" = "$(git hash-object "$fixture_path")"
done
```

**Expected result**: Every invalid finalization attempt exits non-zero, reports
the blocking component and requirement, and leaves the manifest unfinalized.

### Step 10: Finalize A Complete Bundle

**Maps to**: Acceptance Criteria 13 and 14

```bash
REVISION="$(jq -r '.revision' "$BUNDLE")"

"$HELPER" add-component \
  --manifest "$BUNDLE" \
  --bundle-key "$BUNDLE_KEY" \
  --expected-revision "$REVISION" \
  --component-key web-app \
  --json

"$HELPER" update-component \
  --manifest "$BUNDLE" \
  --bundle-key "$BUNDLE_KEY" \
  --expected-revision "$(jq -r '.revision' "$BUNDLE")" \
  --component-key web-app \
  --evidence-file "$WEB_EVIDENCE" \
  --component-tag web-v2.8.1 \
  --component-version 2.8.1 \
  --source-pr 1414 \
  --release-pr 1503 \
  --child-item "#1357" \
  --child-release-state merged \
  --json

"$HELPER" inspect \
  --manifest "$BUNDLE" \
  --bundle-key "$BUNDLE_KEY" \
  --json > "$SMOKE_TMP/inspect-ready.json"

jq -e '.status == "ready_to_finalize"' "$SMOKE_TMP/inspect-ready.json"

REVISION_BEFORE_FINALIZE="$(jq -r '.revision' "$BUNDLE")"
SHARED_REFS_BEFORE="$(
  git for-each-ref --format='%(refname)' refs/heads refs/remotes refs/tags |
    rg 'mobile-and-web-july-delivery|shared-suite|delivery-bundle' || true
)"

"$HELPER" finalize \
  --manifest "$BUNDLE" \
  --bundle-key "$BUNDLE_KEY" \
  --expected-revision "$REVISION_BEFORE_FINALIZE" \
  --json

SHARED_REFS_AFTER="$(
  git for-each-ref --format='%(refname)' refs/heads refs/remotes refs/tags |
    rg 'mobile-and-web-july-delivery|shared-suite|delivery-bundle' || true
)"

jq -e '
  .status == "finalized" and
  .revision == ($revision_before | tonumber) + 1 and
  (.shared_suite_version? == null) and
  (.shared_release_branch? == null) and
  (.audit_events[] | select(.event == "bundle_finalized")) and
  ([.components[] |
    select(
      .component_tag == null or
      .routing_outcome != "component_release_routed" or
      .release_outcome != "completed" or
      (.ci_outcome != "passed" and .ci_outcome != "not_applicable") or
      (.deployment_outcome != "recorded" and .deployment_outcome != "not_applicable") or
      .cleanup_outcome != "complete" or
      (.hub_tracker_reconciliation_outcome != "complete" and
       .hub_tracker_reconciliation_outcome != "deferred") or
      (.child_release_state != "released" and .child_release_state != "merged")
    )] | length) == 0
' --arg revision_before "$REVISION_BEFORE_FINALIZE" "$BUNDLE"

test "$SHARED_REFS_BEFORE" = "$SHARED_REFS_AFTER"
test -z "$(
  jq -r '.shared_suite_version? // empty, .shared_release_branch? // empty' "$BUNDLE"
)"
```

**Expected result**: The manifest status is `finalized`, the revision
increments, the finalization audit event is present, every component has
complete and consistent evidence for the finalized revision, and no shared
suite version or shared release branch is created.

### Step 11: Preserve Source Evidence

**Maps to**: Acceptance Criterion 15

Immediately before and after every create, update, inspect, removal, and
finalization command above, compare the source evidence hashes:

```bash
BEFORE_HASH="$(git hash-object "$MOBILE_EVIDENCE" "$WEB_EVIDENCE" 2>/dev/null || true)"
# Run exactly one bundle command here.
AFTER_HASH="$(git hash-object "$MOBILE_EVIDENCE" "$WEB_EVIDENCE" 2>/dev/null || true)"
test "$BEFORE_HASH" = "$AFTER_HASH"
```

**Expected result**: Source component release evidence files are unchanged after
each individual bundle command and after the full smoke sequence.

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
- [ ] AC4: Identical evidence replay does not duplicate component entries,
      change the revision, or add an audit event.
- [ ] AC5: Inspection reports missing and stale finalization requirements.
- [ ] AC6: Conflicting evidence stops without mutating accepted state.
- [ ] AC7: Stale revision writes stop without mutating accepted state.
- [ ] AC8: Component removal records a reason and preserves prior revisions.
- [ ] AC9: Add, update, and removal after readiness clear or recompute readiness
      for the current revision.
- [ ] AC10: Missing component tag blocks finalization.
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
| Bundle metadata | Parent epic `#1352`, components `mobile-app` and `web-app`, child items `#1356` and `#1357`, finalization owner `@workflow-operator`, and rollout notes | Pass the explicit values from **Test Data** to the create command. |
| Complete component evidence | Completed release, passed CI, recorded deployment, complete cleanup, complete hub reconciliation, released or merged child state, and component tag | Use the implementation's fixture helper or create `component_release_evidence.v1` JSON in `$SMOKE_TMP`. |
| Invalid component evidence | Missing component tag, conflicting stable identity, stale revision, failed outcome, blocked outcome, pending outcome, and malformed JSON | Mutate fixture copies in `$SMOKE_TMP`. |

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

# Delivery-Bundle Evidence Trust Boundary Smoke Test

**Work item**: [#1529](https://github.com/lhpaul/ai-dev-framework-template/issues/1529)
**Implementation plan**: [`2_1529-delivery-bundle-trust-boundary_implementation-plan.md`](../../specs/developments/20260912021032_1529-delivery-bundle-trust-boundary/2_1529-delivery-bundle-trust-boundary_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Scope

This runbook verifies the delivery-bundle evidence trust boundary after
implementation: that the producer's emitted-field contract is documented and
enforced, that every consumer which accepts a caller-supplied override requires
and matches the corresponding evidence field, that `component_version` is bound,
and that each fabricated-value case is rejected.

It is a command-line runbook. There is no UI surface, and the work item body
contains no `## Design assets` section and no tracker attachments, so no
design-fidelity step applies.

## Preconditions

- [ ] The repository is checked out on the #1529 implementation branch.
- [ ] `jq`, `python3`, `git`, and `bash` are available on `PATH`.
- [ ] No production secrets, deployments, private local paths, or `workflow_hub`
      configuration are required. Every step runs against temporary fixtures.
- [ ] A scratch directory is available: `export SMOKE_TMP="$(mktemp -d)"`.

## Test Data

| Item | Value |
| --- | --- |
| Scratch directory | `$SMOKE_TMP` |
| Product repository key | `mobile-app` |
| Canonical identity | `example/mobile-app` |
| Release branch | `mobile-app/release/v1.0.0` |
| Honest component tag | `mobile-v1.4.0` |
| Honest component version | `1.4.0` |
| Fabricated component tag | `fabricated-v99.0.0` |
| Fabricated component version | `99.0.0` |
| Bundle key | `mobile-web-july-delivery` |

---

## Smoke Test Steps

### Step 1: Syntax and shell lint

```bash
bash -n scripts/development-workflow/component-release-evidence.sh \
  scripts/development-workflow/delivery-bundle-manifest.sh \
  scripts/development-workflow/component-milestone-reconciliation.sh \
  scripts/development-workflow/multi-repo-release-assurance.sh \
  scripts/development-workflow/prepare-release-post-merge-cleanup.sh
shellcheck scripts/development-workflow/component-release-evidence.sh \
  scripts/development-workflow/delivery-bundle-manifest.sh \
  scripts/development-workflow/component-milestone-reconciliation.sh \
  scripts/development-workflow/multi-repo-release-assurance.sh \
  scripts/development-workflow/prepare-release-post-merge-cleanup.sh
```

**Expected result**: no syntax errors and no new shellcheck findings.

### Step 2: Automated suites

**Maps to**: Acceptance Criterion 4 (regression tests assert rejection for each
fabricated-value case).

```bash
for suite in component-release-evidence delivery-bundle-manifest \
             component-milestone-reconciliation multi-repo-release-assurance \
             prepare-release-tracker-cleanup component-release-target \
             workflow-hub-docs; do
  echo "== $suite"
  bash "scripts/development-workflow/tests/test-${suite}.sh"
done
```

**Expected result**: every suite reports zero failures. Confirm by reading the
output that the evidence, bundle, and reconciliation suites each name new
rejection cases (unbound version, mismatched version, wrong routing outcome,
missing hub-input flags, invalid evidence state, empty identity field).

### Step 3: Red-before-green evidence for each fabricated-value case

**Maps to**: Acceptance Criterion 4.

Read the implementation PR description (or the commit series). For each of the
rejection tests T1-T21 listed in the plan's Testing Strategy, locate the captured
failing output recorded before its fix. Three tests are exempt: T22 is a
regression guard for a defect already fixed in review round 3; T6b pins the
producer's deliberately unchanged `null` passthrough for `single_repo_release`
routing; and T15b pins reconciliation's deliberately unchanged non-blocking
treatment of `evidence_state: "released"` (already accepted before this plan,
and D9's disposition table preserves that behavior rather than tightening it).
All three are green against unmodified runtime code by design, and the plan
records them as the only three exemptions.

**Expected result**: every rejection test except T6b, T15b, and T22 has a
recorded failure against the unmodified runtime code and a recorded pass after
the fix. A non-exempt test with no recorded red state is a FAIL for this step.
T6b, T15b, and T22 must each be recorded as green both before and after: T6b
proving the new identity precondition was not over-applied, T15b proving
`released` still is not blocked, and T22 proving the earlier fix did not
regress.

### Step 4: The producer binds and emits `component_version`

**Maps to**: Acceptance Criteria 3 and 5.

```bash
bash scripts/development-workflow/tests/setup-component-release-fixture.sh \
  --work-dir "$SMOKE_TMP/fixture" --json > "$SMOKE_TMP/fixture.json"
# The fixture resolves the workflow-hub target binding itself and writes it to
# <work-dir>/component-target.json; no separate resolve step is required.
TARGET="$SMOKE_TMP/fixture/component-target.json"
jq -c '{routing_outcome, mutation_allowed, release_branch_pattern}' "$TARGET"
scripts/development-workflow/component-release-evidence.sh \
  --target-file "$TARGET" --binding-file "$TARGET" \
  --release-branch mobile-app/release/v1.0.0 \
  --release-outcome completed --ci-outcome passed \
  --deployment-outcome recorded --cleanup-outcome complete \
  --hub-tracker-ref "#1529" \
  --component-tag mobile-v1.4.0 \
  --component-version 1.4.0 \
  --output "$SMOKE_TMP/evidence-bound.json"
jq '{component_tag, component_version}' "$SMOKE_TMP/evidence-bound.json"
```

**Expected result**: the fixture target reports
`routing_outcome: "component_release_routed"` and `mutation_allowed: true`, and
the rendered record contains `"component_tag": "mobile-v1.4.0"` and
`"component_version": "1.4.0"`.

Then render the same evidence **without** `--component-version` to
`$SMOKE_TMP/evidence-unbound.json` and inspect it.

**Expected result**: `component_version` is present and JSON `null` — not absent
and not an empty string.

### Step 5: The producer rejects malformed and empty inputs

**Maps to**: Acceptance Criteria 2 and 5.

Run the producer five more times, each time changing one input:

1. `--component-tag "bad tag"` (contains a space)
2. `--component-version "1.0.0;echo"` (contains a semicolon)
3. a target binding whose `contract_revision` is `""`
4. a target binding whose `release_correlation_key` is `""`
5. a target binding whose `routing_outcome` is `component_release_routed` and
   whose `selected_product_repo_key` is `null`

**Expected result**: each run exits non-zero. Runs 1 and 2 exit `2` and the
message names the offending flag. Runs 3, 4, and 5 exit `1` and the message names
the missing identity field — run 5 naming `selected_product_repo_key`. No
evidence file is written in any of the five runs.

Then run the producer once more against a target binding whose `routing_outcome`
is `single_repo_release` and whose `selected_product_repo_key` is `null`.

**Expected result**: the record **is** written and its `selected_product_repo_key`
is JSON `null`. This is the `producer_required_nullable` contract: `null` occurs
if and only if routing is `single_repo_release`, so run 5's precondition must not
fire here.

### Step 6: The bundle requires and matches `component_version`

**Maps to**: Acceptance Criteria 2 and 3.

Create a bundle, then attempt `update-component` three times against the same
manifest:

1. with `--evidence-file "$SMOKE_TMP/evidence-unbound.json"` and
   `--component-version 1.4.0`
2. with `--evidence-file "$SMOKE_TMP/evidence-bound.json"` and
   `--component-version 99.0.0`
3. with `--evidence-file "$SMOKE_TMP/evidence-bound.json"` and
   `--component-version` omitted entirely

**Expected result**:

- Case 1 fails with `ERROR_CODE=component_version_unbound`.
- Case 2 fails with `ERROR_CODE=component_version_mismatch`.
- Case 3 fails with `ERROR_CODE=invalid_arguments` and exit code `2`, because
  `--component-version` is now required.
- The manifest revision is unchanged after all three attempts.

Then run the honest update (bound evidence, matching tag and version).

**Expected result**: the update succeeds and the stored component record carries
`component_version`, `component_tag`, and `release_branch` from the evidence.

### Step 7: The bundle still rejects a fabricated tag

**Maps to**: Acceptance Criterion 2 (regression guard for the round-4 finding).

Attempt `update-component` with `--component-tag fabricated-v99.0.0` against
`$SMOKE_TMP/evidence-bound.json`.

**Expected result**: `ERROR_CODE=component_tag_mismatch`, manifest revision
unchanged, and `finalize` still reports the component as blocked.

### Step 8: Reconciliation refuses non-hub routing

**Maps to**: Acceptance Criteria 1 and 2.

Run `component-milestone-reconciliation.sh inspect-component` on the hub path
with an evidence file whose `routing_outcome` is `single_repo_release`.

**Expected result**: `reconciliation_outcome=component_target_mismatch`,
`blockers` contains `routing_outcome_mismatch`, and `mutation_allowed` is
`false`.

### Step 9: Reconciliation refuses hub facts smuggled through the evidence file

**Maps to**: Acceptance Criteria 1 and 2.

Run `inspect-component` on the hub path with an evidence file that additionally
carries `hub_tracker_reconciliation_outcome: "complete"` and
`child_release_state: "released"`, and **omit** both CLI flags.

**Expected result**: `blockers` contains
`hub_tracker_reconciliation_outcome_required` and
`child_release_state_required`; the values embedded in the evidence file are not
used; `mutation_allowed` is `false`.

### Step 10: Reconciliation rejects an unrecognized evidence state

**Maps to**: Acceptance Criterion 2.

Run `inspect-component` four times, with an evidence file whose `evidence_state`
is in turn `totally-fine`, `partial`, `missing`, and `released`.

**Expected result**: the first three are rejected — `blockers` contains
`invalid_evidence_state`, `partial_component_evidence`, and
`missing_component_evidence` respectively, and `mutation_allowed` is `false` in
all three. The `released` run carries no `evidence_state` blocker, matching the
per-value disposition table in plan decision D9.

### Step 11: Single-repository mode refuses a silently ignored evidence file

**Maps to**: Acceptance Criterion 2.

1. Run `apply-component --mode single_repo --version v1.2.3 --evidence-file <any path>`.
2. Run the same command without `--evidence-file`.

**Expected result**: run 1 fails with `evidence_not_supported_in_single_repo` and
makes no tracker mutation. Run 2 succeeds with
`reconciliation_outcome=single_repo_milestone` and reports
`trust_basis: "caller_asserted"`.

### Step 12: Cleanup rejects evidence with an empty identity field or an empty `release_branch`

**Maps to**: Acceptance Criterion 2.

Run `prepare-release-post-merge-cleanup.sh` with `--repo` and an
`--evidence-file` whose `target_binding.contract_revision` is `""`.

**Expected result**: exit `1` with a message naming the missing identity field.
No product release branch is deleted and no tracker state changes.

Then repeat with an otherwise-valid evidence file whose top-level
`release_branch` is `""` (or the key omitted), passing a positional release
argument that does not correspond to any real branch (T20c).

**Expected result**: exit `1` naming `release_branch` as a missing required
field, before the positional argument is ever compared against it. No product
release branch is deleted and no tracker state changes.

### Step 13: The assurance harness declares its trust class

**Maps to**: Acceptance Criterion 1.

```bash
scripts/development-workflow/tests/setup-multi-repo-release-assurance-fixture.sh \
  --output-dir "$SMOKE_TMP/assurance" --json > "$SMOKE_TMP/assurance-fixtures.json"
scripts/development-workflow/multi-repo-release-assurance.sh \
  --fixture-dir "$SMOKE_TMP/assurance/valid" --json | jq '{adoption_status, trust_class}'
```

**Expected result**: `adoption_status` is `validated` and `trust_class` is
`attestation`.

### Step 14: The contract document is complete and reachable

**Maps to**: Acceptance Criteria 1 and 5.

Open `docs/workflow/development-workflow/component-release-evidence-contract.md`
and confirm each of the following:

1. The five trust classes are defined with each one's consumer duty:
   `producer_required`, `producer_required_nullable`, `producer_conditional`,
   `hub_input`, and `attestation`. The `producer_required_nullable` entry states
   its `null` handling explicitly — require the key present, accept a non-empty
   string or JSON `null`, treat `null` as unbound, and require
   `routing_outcome == component_release_routed` first — so it does not
   contradict `producer_required`'s "require non-empty" duty.
2. The producer's emitted-field table lists every field the producer emits, each
   carrying exactly one trust class, and no field's entry contradicts the
   definition of the class it carries. `selected_product_repo_key` is
   `producer_required_nullable`; every other always-emitted field is
   `producer_required`.
3. The field x consumer matrix has one row per emitted field and per
   never-emitted field a consumer reads, and one column per consumer:
   `delivery-bundle-manifest.sh`, `component-milestone-reconciliation.sh`,
   `multi-repo-release-assurance.sh`, `prepare-release-post-merge-cleanup.sh`.
4. The `evidence_state` entry records a disposition for every enum member
   (`verified`, `released`, `stale`, `conflicting`, `missing`, `partial`, any
   unknown value, and an absent value), not just the accepted list.
5. A "fields the producer never emits" section lists `evidence_state`,
   `hub_tracker_reconciliation_outcome`, `child_release_state`, `component_key`,
   `child_item`, `source_pr`, and `release_pr`.
6. A Known gaps section records the undefined `hub_tracker_ref` semantics, the
   absent tag/branch-version relation, the unbound `apply-component` target, the
   six unvalidated assurance fields, the hub-checkout-scoped cleanup lease, and
   the absent release-tag deletion.

Then confirm the document is linked from `repository-modes.md`,
`multi-repo-release-adoption.md`, and `scripts/development-workflow/README.md`.

Cross-check the field table against the running code:

```bash
scripts/development-workflow/component-release-evidence.sh --help 2>&1 | head -5
jq 'keys' "$SMOKE_TMP/evidence-bound.json"
```

**Expected result**: the key list from the rendered record matches the document's
emitted-field table exactly — no field in the record is missing from the table,
and no field in the table is absent from the record.

### Step 15: The documented release sequence is executable

**Maps to**: Acceptance Criterion 5.

Read the producer snippet in
`docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md` and
in `docs/workflow/development-workflow/cross-repo-pr-flow.md`.

**Expected result**: each file documents both the initial `pending` render and
the post-release re-render that binds `--component-tag` and
`--component-version`, and states that bundle attachment requires the re-rendered
file. Following the documented order no longer ends in
`component_tag_unbound`.

Also confirm that `.agents/skills/prepare-release/SKILL.md` step 8 no longer
claims the evidence "must include" `hub_tracker_reconciliation_outcome` or
`child_release_state`.

### Step 16: Residual verification gate

**Maps to**: Plan Residual Verification Strategy.

```bash
gh issue view 1529 --json body --jq .body > "$SMOKE_TMP/1529-body.md"
./scripts/development-workflow/scope-residual-gate.sh verify \
  --issue-title "workflow-hub: audit the delivery-bundle evidence trust boundary — consumers accept unvalidated caller-supplied values" \
  --issue-body-file "$SMOKE_TMP/1529-body.md" \
  --evidence docs/specs/developments/20260912021032_1529-delivery-bundle-trust-boundary/residual-evidence.json
```

**Expected result**: `RESULT=pass` with `SCOPE_CLASSIFICATION=numeric_sweep`.

### Last Step: Validate and clean up

- [ ] Every assertion in the checklist below is met.
- [ ] `rm -rf "$SMOKE_TMP"`.

---

## Assertions Checklist

- [ ] **AC-1** — A trust matrix covering every `component_release_evidence.v1`
      field against all four consumers exists and is reachable from the workflow
      docs (Steps 8, 9, 10, 13, 14).
- [ ] **AC-2** — No consumer treats a missing overridable field as a match:
      unbound version, mismatched version, mismatched tag, wrong routing outcome,
      smuggled hub facts, unrecognized and degraded evidence states, silently
      ignored evidence file, and empty identity fields are all rejected (Steps 5,
      6, 7, 8, 9, 10, 11, 12).
- [ ] **AC-3** — `component_version` is emitted by the producer and
      require-and-matched by every consumer that accepts a caller-supplied value
      (Steps 4, 6, 11).
- [ ] **AC-4** — Regression tests assert rejection for each fabricated-value case
      and each was confirmed failing before its fix (Steps 2, 3).
- [ ] **AC-5** — The producer's emitted-field contract is documented well enough
      that a future consumer can tell required from optional without reading the
      producer, and the documented release sequence is executable (Steps 4, 5,
      14, 15).

---

## Seed Data Reference

| Entity | Scenario | How to load |
| --- | --- | --- |
| Component release target binding | Valid `workflow_hub` routing with `mutation_allowed: true` | `scripts/development-workflow/tests/setup-component-release-fixture.sh --work-dir "$SMOKE_TMP/fixture" --json` (writes `component-target.json` into that directory) |
| Milestone fixture with `gh` stub | Hub tracker calls captured to a log instead of executed | `scripts/development-workflow/tests/setup-component-milestone-fixture.sh` |
| Assurance fixture | Valid and `release_contract: "garbage"` variants | `scripts/development-workflow/tests/setup-multi-repo-release-assurance-fixture.sh --output-dir "$SMOKE_TMP/assurance" --json` |
| Fabricated-value evidence variants | Unbound version, empty identity field, wrong routing outcome, smuggled hub facts, invalid evidence state | Hand-edited copies of `$SMOKE_TMP/evidence-bound.json` created inside each step |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| The producer exits `2` with "target binding is not mutation-allowed" | The fixture target was generated for a stop outcome | Regenerate the fixture and confirm `mutation_allowed` is `true` in the target file |
| `update-component` reports `stale_manifest_revision` | `--expected-revision` was not refreshed after a successful update | Re-read `jq -r '.revision' "$MANIFEST"` before each call |
| `apply-component` attempts a real GitHub call | The `gh` stub from the milestone fixture is not first on `PATH` | Re-export `PATH` with the fixture's stub directory prepended |
| Cleanup reports "lock is already held" | A previous run left the hub-scoped lease directory behind | Remove the named lock directory reported in the error, then re-run |
| `scope-residual-gate.sh` reports `RESULT=escalate` | `--evidence` was omitted | Pass the residual evidence file produced during implementation |

---

## Known Limitations

- This runbook cannot exercise a real `workflow_hub` deployment: this repository
  resolves to `single_repo` mode and configures no product repositories, so every
  hub-mode step runs against temporary fixtures.
- `hub_tracker_ref` is not verified against any tracker issue. Its semantics are
  undefined across the repository's own examples, and binding it is recorded as an
  out-of-scope residual in the implementation plan.
- The cleanup lease is verified only within one hub checkout. Cross-machine lease
  behavior is a pre-existing limitation carried forward from the work item brief
  and is not covered here.
- No release-tag deletion is exercised, because
  `prepare-release-post-merge-cleanup.sh` implements none. The
  `remote_tag_deleted` field in the older #1356 runbook describes functionality
  that was never built.

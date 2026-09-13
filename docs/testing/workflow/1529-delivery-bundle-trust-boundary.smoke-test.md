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
- [ ] `jq`, `python3`, `git`, `bash`, and `shellcheck` are available on `PATH`.
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
missing hub-input flags, invalid evidence state, empty identity field,
producer-unemittable `ci_outcome: "skipped"`, non-string `ci_outcome`/
`deployment_outcome`).

### Step 3: Red-before-green evidence for each fabricated-value case

**Maps to**: Acceptance Criterion 4.

Read the implementation PR description (or the commit series). For each of the
rejection tests T1-T26 (plus T6f, T6g, T6h, T10a, T13a, T14a, and T20g) listed
in the plan's Testing Strategy, locate the captured failing output recorded
before its fix. Nine tests are exempt: T22 is a regression guard for a defect
already fixed in review round 3; T6b pins the producer's deliberately
unchanged `null` passthrough for `single_repo_release` routing; T15b pins
reconciliation's deliberately unchanged non-blocking treatment of
`evidence_state: "released"` (already accepted before this plan, and D9's
disposition table preserves that behavior rather than tightening it); T15c
pins reconciliation's deliberately unchanged treatment of an evidence record
whose `evidence_state` key is entirely absent (synthesized as `verified` when
`schema_version` matches, per D9's `absent` row — a pre-existing behavior this
plan does not touch); T13a/T14a each pin a pre-existing, unchanged
`pending`-value regression for one of the two hub-input flags (the
`not in {"complete", "deferred"}` / `not in {"released", "merged"}` blocker
comparisons are untouched by GAP-5/D5); T10b pins that
`--child-release-state failed` was already accepted before this plan (no
`choices=` validator exists yet on `delivery-bundle-manifest.sh
update-component`) and is still accepted by the new parse-time closed-enum
validator, because `failed` is one of that flag's pre-existing, meaningful
values (`classify_component` line 357), not a value the new validator should
reject; and T10c/T10d pin the same already-accepted-today behavior for the two
newly admitted `--child-release-state` values, `blocked` and `not_started`
(spec #1358 lines 268-276) — like `failed`, both already parse successfully
under the current, unrestricted flag (no `choices=` exists yet), so there is
no fix for either test to be red against, and they exist so the new
parse-time closed enum does not accidentally narrow to exclude these two
established component-child states before `blocker_for_component` can
classify them. All nine are green against unmodified runtime code by design,
and the plan records them as the only nine exemptions. T23 and T24 (GAP-14,
the `ci_outcome: "skipped"` rejection), T20g (GAP-15, the empty/missing
`cleanup_outcome` rejection), and T10a (the new
`--hub-tracker-reconciliation-outcome` parse-time closed-enum rejection,
symmetric to the already-existing T10) are **not** exempt and must each show a
captured red state.

T4 requires one additional check beyond "a recorded red state exists": confirm
the recorded red state was captured **after** `--component-version` argument
parsing (D1) landed but **before** the charset validator (D3) did — i.e., the
recorded "before" behavior is that `--component-version "1.0.0;rm"` was
*accepted* and emitted verbatim, not that it was rejected with exit 2 by the
pre-D1 catch-all `Unknown argument` branch. A red capture for T4 taken before
D1 landed (or one showing exit 2 for the "wrong" reason) does not satisfy this
step even though it superficially looks like a captured failure — it proves
nothing about the charset validator this test exists to cover.

**Expected result**: every rejection test except T6b, T10b, T10c, T10d, T13a,
T14a, T15b, T15c, and T22 has a recorded failure against the runtime code as
it stood immediately before that specific test's own fix (for T4, that
baseline is the post-D1/pre-D3 state described above, not the unmodified
pre-D1 code; for every other non-exempt test, it is the unmodified runtime
code) and a recorded pass after the fix (this includes T10a, which proves the
*new* `--hub-tracker-reconciliation-outcome` parse-time rejection; T15d, which
proves the *new* `invalid_evidence_state` disposition for a present but
non-string `evidence_state` value such as JSON `null`, distinct from the
unchanged absent-key case in T15c; T23/T24, which prove the *new* rejection of
`ci_outcome: "skipped"` at both consumers; T20g, which proves the *new*
rejection of an empty/missing `cleanup_outcome`; and T25/T26, which prove the
*new* type guard on `ci_outcome`/`deployment_outcome`). T25/T26's red capture
is not a clean wrong-blocker exit like every other non-exempt test: the
unmodified script raises an uncaught `TypeError` (unhashable type) and
crashes instead of returning any blocker at all, because the pre-fix code
passes a present, non-string evidence value (a JSON array) straight into a
Python set-membership check; capture that crash as the red state, and confirm
the post-fix run instead exits cleanly with `ci_outcome_invalid` /
`deployment_outcome_invalid` and `mutation_allowed: false`. A non-exempt test
with no recorded red state, or with a T4 red state captured at the wrong
baseline, is a FAIL for this step. T6b, T10b, T10c, T10d, T13a, T14a, T15b, T15c, and T22
must each be recorded as green both before and after: T6b proving the new
identity precondition was not over-applied, T10b proving `--child-release-state
failed` was accepted before the new validator and still is after, T10c/T10d
proving `--child-release-state blocked`/`not_started` were accepted before the
new validator and still are after (and are correctly classified by the
unchanged `blocker_for_component` logic), T13a/T14a proving a `pending`
hub-input flag value was already blocked before this plan and still is after,
T15b proving `released` still is not blocked, T15c proving an absent
`evidence_state` key still is not blocked, and T22 proving the earlier fix did
not regress.

### Step 4: The producer binds and emits `component_version`

**Maps to**: Acceptance Criteria 3 and 5.

```bash
bash scripts/development-workflow/tests/setup-component-release-fixture.sh \
  --work-dir "$SMOKE_TMP/fixture" --json > "$SMOKE_TMP/fixture.json"
# The fixture's own <work-dir>/component-target.json resolves the target
# without binding a release branch (setup-component-release-fixture.sh calls
# component-release-target.sh with no --release-branch), so its
# release_correlation_key is the routing-only value, not a per-attempt one.
# Re-resolve the target directly here, binding the same release branch this
# step's evidence renders against, so target_binding.release_correlation_key
# is the per-attempt value Step 12's cleanup re-resolution will independently
# reproduce later from evidence.release_branch -- component-release-evidence.sh
# validates and records --release-branch but copies release_correlation_key
# from the target file verbatim, it does not recompute it, so the target
# itself must already be branch-bound before evidence is rendered from it.
HUB_REPO="$(jq -r '.hub_repo' "$SMOKE_TMP/fixture.json")"
TARGET="$SMOKE_TMP/fixture/component-target-bound.json"
scripts/development-workflow/component-release-target.sh \
  --repo-root "$HUB_REPO" --repo mobile-app \
  --release-branch mobile-app/release/v1.0.0 --json > "$TARGET"
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
5. a target binding whose `routing_outcome` is `component_release_routed`,
   whose `selected_product_repo_key` is `null`, and whose `release_branch_pattern`
   is **omitted (empty)** rather than the base fixture's
   `{product_repo}/release/v{version}` — with the pattern non-empty, the
   pre-existing branch-pattern check would substitute the null key's empty
   string into `{product_repo}` and reject the run there instead of at the new
   guard this step is meant to exercise, because no `--release-branch` value can
   satisfy both a `{product_repo}`-shaped pattern and a null key at once

**Expected result**: each run exits non-zero. Runs 1 and 2 exit `2` and the
message names the offending flag — for run 2, the message must be the charset
validator's own diagnostic (naming `--component-version`), not the generic
`Unknown argument: --component-version` an unrecognized flag would produce; by
this point in the runbook `--component-version` is already a recognized,
charset-validated flag, so this distinction only matters for how run 2's
implementation-time red capture was taken (see Step 3's T4 note) — an
implementation that skipped the charset validator entirely but still rejected
run 2 via the catch-all unrecognized-argument path would be indistinguishable
from a correct implementation at this step, which is exactly why Step 3
carries the extra T4-specific check. Runs 3, 4, and 5 exit `1` and the message
names the missing identity field — run 5 naming `selected_product_repo_key`.
No evidence file is written in any of the five runs.

Then run the producer once more against a target binding whose `routing_outcome`
is `single_repo_release`, whose `selected_product_repo_key` is `null`, and whose
`release_branch_pattern` is likewise omitted (empty), for the same reason as run 5.

**Expected result**: the record **is** written and its `selected_product_repo_key`
is JSON `null`. This is the forward half of the `producer_required_nullable`
contract: `null` occurs if and only if routing is `single_repo_release`, so run
5's precondition must not fire here.

Then run the producer once more against a target binding whose `routing_outcome`
is `single_repo_release` and whose `selected_product_repo_key` is a **non-null,
non-empty** value (e.g. `mobile-app`), with `release_branch_pattern` again
omitted (empty) for the same structural reason as the earlier runs (T6e).

**Expected result**: exit `1` with a message naming that the target binding must
not bind `selected_product_repo_key` under `single_repo_release` routing; no
evidence file is written. This is the reverse half of the
`producer_required_nullable` contract: a `single_repo_release` record that
carries a bound (non-null) key is just as much a contract violation as a
`component_release_routed` record that carries `null` — `compare_field` alone
cannot catch this, because target and binding here agree with each other, they
merely agree on the wrong thing for this routing outcome. Only with this run
passing alongside run 5 and the preceding `null`-passthrough run is the "if and
only if" claim actually exercised in both directions.

Then run the producer once more against a target binding whose `routing_outcome`
is `unknown` (a non-empty value that is neither `component_release_routed` nor
`single_repo_release`, matching in both the target and binding files),
`mutation_allowed: true`, `selected_product_repo_key: null`, and
`release_branch_pattern` again omitted (empty) for the same structural reason
as the earlier runs (T6h).

**Expected result**: exit `1` with a message naming that `routing_outcome` must
be `component_release_routed` or `single_repo_release`; no evidence file is
written. This is the closed-enum precondition on `routing_outcome` itself: a
non-empty-but-unrecognized value passes the plain non-empty check but matches
neither of the two conditional `selected_product_repo_key` branches above, so
without this run's guard a matching target/binding pair carrying `unknown`
routing and a `null` key would pass every other check in this step unrejected.

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
unchanged, and the stored `mobile-app` component still carries the honest
values from Step 6's update (`component_tag: "mobile-v1.4.0"`,
`component_version: "1.4.0"`) — the rejected fabricated-tag attempt writes
nothing to the manifest, so the bundle remains exactly as ready as Step 6 left
it (do not call `finalize` here: Step 17 reuses this same unfinalized,
otherwise-ready state).

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

Then run `inspect-component` on the hub path with otherwise-ready evidence and
`--hub-tracker-reconciliation-outcome pending` supplied explicitly (the other
hub-input flag left at a non-blocking value) (T13a); repeat with
`--child-release-state pending` supplied instead (T14a). `pending` is a real,
non-terminal value for both flags — it is not an unrecognized string, and it
must still block.

**Expected result**: the first run's `blockers` contains
`hub_tracker_reconciliation_pending` and the second run's `blockers` contains
`child_release_state_pending`; `mutation_allowed` is `false` in both. Neither
run may pass with an empty `blockers` list.

### Step 10: Reconciliation rejects an unrecognized evidence state

**Maps to**: Acceptance Criterion 2.

Run `inspect-component` six times, with an evidence file whose `evidence_state`
is in turn `totally-fine`, `partial`, `missing`, `released`, entirely absent
(the key removed from the evidence file), and JSON `null` (the key present with
a `null` value).

**Expected result**: the first three (`totally-fine`, `partial`, `missing`) are
rejected — `blockers` contains `invalid_evidence_state`,
`partial_component_evidence`, and `missing_component_evidence` respectively,
and `mutation_allowed` is `false` in all three. The `released` run carries no
`evidence_state` blocker, matching the per-value disposition table in plan
decision D9. The absent-key run also carries no `evidence_state` blocker —
`evidence_state` is synthesized as `verified` when `schema_version` matches,
exactly as it was before this plan (D9's `absent` row, pre-existing behavior at
lines 179-196 that this plan does not change). The `null` run is rejected —
`blockers` contains `invalid_evidence_state` and `mutation_allowed` is
`false` — because a *present* non-string value falls under D9's `any other
string, or a non-string` row, not the `absent` row; this is the case that
distinguishes "key missing" from "key present but not a valid enum string."

### Step 11: Single-repository mode refuses a silently ignored evidence file

**Maps to**: Acceptance Criterion 2.

`apply-component` requires `--issue` and `--target-kind` (both are
`required=True` on the parser) and, on a successful `single_repo` run, makes a
real milestone-mutation `gh` call through `ensure_milestone`/
`assign_milestone`. Set up the milestone fixture and its `gh` stub — **not**
the real `gh` CLI — before either invocation below, mirroring the pattern
`tests/test-component-milestone-reconciliation.sh` uses for its own
`single_repo` apply coverage. This mock stub must be scoped to this step
only: it rejects every invocation whose first argument is not `api` (see the
stub's source in `setup-component-milestone-fixture.sh`), so leaving it first
on `PATH` after this step would break Step 16's real `gh issue view` call
later in this runbook. Save the current `PATH` before prepending the stub's
directory, and restore it — along with unsetting the fixture-scoped variables
below — immediately after both invocations finish and before Step 12 begins:

```bash
bash scripts/development-workflow/tests/setup-component-milestone-fixture.sh \
  --output-dir "$SMOKE_TMP/milestone-fixture" --json > "$SMOKE_TMP/milestone-fixture.json"
MOCK_GH_BIN="$(jq -r '.mock_gh.bin_dir' "$SMOKE_TMP/milestone-fixture.json")"
ORIGINAL_PATH="$PATH"
export PATH="$MOCK_GH_BIN:$PATH"
export COMPONENT_MILESTONE_MOCK_STATE
export COMPONENT_MILESTONE_GH_CALL_LOG
COMPONENT_MILESTONE_MOCK_STATE="$(jq -r '.mock_gh.state' "$SMOKE_TMP/milestone-fixture.json")"
COMPONENT_MILESTONE_GH_CALL_LOG="$(jq -r '.mock_gh.call_log' "$SMOKE_TMP/milestone-fixture.json")"
export GITHUB_REPOSITORY="example/mobile-app"
COMPONENT_CHILD_ISSUE="$(jq -r '.issues.component_child' "$SMOKE_TMP/milestone-fixture.json")"
```

With the mock `gh` stub first on `PATH` and both `COMPONENT_MILESTONE_*`
variables and `GITHUB_REPOSITORY` exported:

1. Run `apply-component --mode single_repo --issue "$COMPONENT_CHILD_ISSUE"
   --target-kind component_child --version v1.2.3 --evidence-file
   "$SMOKE_TMP/evidence-bound.json" --json`.
2. Run the same command without `--evidence-file`.

**Expected result**: run 1 fails with `evidence_not_supported_in_single_repo`
and `$COMPONENT_MILESTONE_GH_CALL_LOG` is unchanged (no line appended) — no
tracker mutation. Run 2 succeeds with `reconciliation_outcome=single_repo_milestone`
and reports `trust_basis: "caller_asserted"`. The fixture only pre-seeds a
`mobile-app@mobile-v1.4.0` milestone — no `v1.2.3` milestone exists yet — so a
correct implementation's `ensure_milestone` call must create it before
`assign_milestone` can assign it: confirm `$COMPONENT_MILESTONE_GH_CALL_LOG`
gains exactly **two** new lines from run 2, a milestone-creation call
(`-X POST .../milestones` with `title=v1.2.3`) followed by a
milestone-assignment call (`-X PATCH .../issues/$COMPONENT_CHILD_ISSUE` with
the newly created milestone number) — confirming both mutations went through
the stub, not the real `gh` CLI. A single-line result is a FAIL for this step:
it means either the milestone-creation call never happened (and the
assignment would then be against a pre-existing, unrelated milestone) or the
log was not read correctly.

Immediately after run 2, restore the environment before Step 12 runs:

```bash
export PATH="$ORIGINAL_PATH"
unset COMPONENT_MILESTONE_MOCK_STATE COMPONENT_MILESTONE_GH_CALL_LOG GITHUB_REPOSITORY
```

No later step in this runbook needs the mock `gh` stub, and Step 16 makes a
real `gh issue view` call — leaving the stub first on `PATH` would make that
call fail, because the stub only implements `gh api ...` and rejects
everything else.

### Step 12: Cleanup rejects evidence with an empty identity field, an empty `release_branch`, or an empty/missing `cleanup_outcome`

**Maps to**: Acceptance Criterion 2.

`prepare-release-post-merge-cleanup.sh` derives `HUB_REPO_ROOT` from `$PWD`
unconditionally and, if `--repo-root` is also supplied, rejects any value that
does not canonically match `$PWD` (`"--repo-root must point at the current
workflow hub checkout for release tracker cleanup."`). Every invocation in
this step must therefore run with the fixture's hub checkout (`$HUB_REPO`,
set in Step 4) as its current directory, not the repository root the rest of
this runbook runs from. Capture the cleanup script's absolute path before
changing directory, and invoke it in a subshell so the `cd` does not leak
into later steps:

```bash
CLEANUP_SCRIPT="$PWD/scripts/development-workflow/prepare-release-post-merge-cleanup.sh"
run_cleanup() {
  # Usage: run_cleanup <evidence-file> [release-branch-arg]
  # Defaults the positional release argument to the real, matching branch;
  # only T20c below overrides it with a branch that does not exist.
  local evidence_file="$1"
  local release_arg="${2:-mobile-app/release/v1.0.0}"
  (cd "$HUB_REPO" && "$CLEANUP_SCRIPT" --repo mobile-app --repo-root "$HUB_REPO" \
    --evidence-file "$evidence_file" "$release_arg")
}
```

Every hand-edited evidence file in this step (T19, T20, T20b, T20d, T20e, T20f, and T20g)
starts from a `jq` copy of `$SMOKE_TMP/evidence-bound.json` — the file Step 4 rendered
from the branch-bound `$TARGET` (resolved there via `component-release-target.sh
--release-branch mobile-app/release/v1.0.0`, not from the fixture's own un-branched
`component-target.json`) — with exactly the one field under test changed. Do **not**
substitute the fixture's raw, un-branched target/evidence anywhere in this step: that
target's `release_correlation_key` was computed with no release branch folded in at
all, so `prepare-release-post-merge-cleanup.sh`'s real target re-resolution — which
re-derives the correlation key by re-running `component-release-target.sh` with
`--release-branch "$(evidence.release_branch)"` — would reject it on a
`release_correlation_key`/`release_branch` mismatch (or the missing-`release_branch`
guard, once one is edited) before the run ever reaches the specific field this step
means to test. Starting from `evidence-bound.json` keeps `release_branch` and
`release_correlation_key` mutually consistent with a real branch for every edit in this
step except T20c, which deliberately breaks that consistency on purpose (see its own
instructions below).

```bash
jq '.target_binding.contract_revision = ""' "$SMOKE_TMP/evidence-bound.json" \
  > "$SMOKE_TMP/cleanup-t19.json"
run_cleanup "$SMOKE_TMP/cleanup-t19.json"
```

**Expected result**: exit `1` with exactly `Component release evidence is
missing required identity field: contract_revision`. This must be the new
GAP-8 diagnostic, not the pre-existing `Component release evidence mismatch
for .contract_revision: current=... evidence=...` message: since
`contract_revision` is compared last among the six ordered
`compare_component_field` calls, a build that omits GAP-8 entirely would
still exit `1` naming `contract_revision` (via the mismatch check, once the
five earlier compares pass), which would look like a pass against a looser
"names the field" assertion — treat any run producing the mismatch-format
message instead of the exact GAP-8 message as a FAIL for this case. No
product release branch is deleted and no tracker state changes.

Repeat the same `jq`-edit-then-`run_cleanup` pattern with
`target_binding.canonical_repository_identity: ""` (T20), then
`target_binding.release_correlation_key: ""` (T20b), then
`target_binding.routing_outcome: ""` (T20d), then
`target_binding.selected_product_repo_key: ""` or the key absent (T20e), then
once per `artifact_owners` sub-field (`release`, `ci`, `github_release`,
`deployment`, `cleanup`, `tracker`) — each run emptying exactly one sub-field
with the other five populated (T20f, six runs).

**Expected result**: each run exits `1` with exactly `Component release
evidence is missing required identity field: <field>`
(`canonical_repository_identity`, `release_correlation_key`, `routing_outcome`,
`selected_product_repo_key`, or `artifact_owners` respectively) — the same
exact-diagnostic requirement as the T19 case above, for the same reason: the
freshly resolved target's real value for each of these fields already
disagrees with the evidence's edited `""`, so the pre-existing
`compare_component_field` mismatch check would independently exit `1` naming
the same field even without GAP-8. A run that exits `1` with the
`Component release evidence mismatch for ...` message instead of the exact
GAP-8 message is a FAIL for that case, not a pass. No product release branch
is deleted and no tracker state changes in any run.

Then repeat with a fresh evidence file rendered exactly like Step 4's, target
resolution and all: re-run `component-release-target.sh --repo-root "$HUB_REPO"
--repo mobile-app --release-branch <a-real-branch>` (any real branch is fine,
including reusing `mobile-app/release/v1.0.0`) to get a target whose
`release_correlation_key` is the genuine per-attempt value that branch
produces, not a fixed or contract-level key, then render evidence from that
target with the same `--release-branch`. Only after that render, edit **only**
the top-level `release_branch` to `""` (or remove the key) while leaving
`target_binding.release_correlation_key` untouched, and run it through
`run_cleanup` with a second argument naming a release that does not
correspond to any real branch, e.g. `run_cleanup
"$SMOKE_TMP/cleanup-t20c.json" mobile-app/release/v9.9.9-nonexistent` (T20c).
Do not substitute a fixed/attempt-independent correlation key here — and do
not reuse `evidence-bound.json` unedited for the target-resolution step,
since that would only prove the guard against the same fixture the other six
sub-tests already use: an empty `release_branch` means cleanup's target
re-resolution omits `--release-branch`, so the freshly resolved target
computes a release correlation key from an empty attempt-branch input, which
will disagree with the genuine per-attempt key already recorded in
`target_binding` — this disagreement is what proves the new `release_branch`
guard runs before, not after, cleanup's
`compare_component_field '.release_correlation_key'` check.

**Expected result**: exit `1` naming `release_branch` as a missing required
field, before the positional argument is ever compared against it **and**
before any `release_correlation_key` mismatch is reported. If the failure
instead names a `release_correlation_key` mismatch, the guard is implemented in
the wrong place (after target re-resolution and the identity compares) rather
than immediately after `evidence_branch` is read — treat that as a FAIL for
this step. No product release branch is deleted and no tracker state changes.

Then repeat with an otherwise valid, ready-to-clean-up evidence file (again a
`jq` copy of `evidence-bound.json`) whose top-level `cleanup_outcome` is `""`,
then again with the `cleanup_outcome` key removed entirely, each run through
`run_cleanup` (T20g).

**Expected result**: both runs exit `1` with `Component release evidence is
missing required field: cleanup_outcome`. Neither run may fall through and
perform an actual cleanup — that would mean the missing/empty value was
silently treated the same as any other non-`complete` value instead of being
rejected outright. No product release branch is deleted and no tracker state
changes in either run.

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

1. The six trust classes are defined with each one's consumer duty:
   `producer_required`, `producer_required_nullable`, `producer_conditional`,
   `hub_input`, `hub_input_identifier`, and `attestation`. The
   `producer_required_nullable` entry states its `null` handling explicitly —
   require the key present, accept a non-empty string or JSON `null`, treat
   `null` as unbound, and require `routing_outcome == component_release_routed`
   first — so it does not contradict `producer_required`'s "require non-empty"
   duty. The `hub_input` entry (closed-enum outcome flags) and the
   `hub_input_identifier` entry (open-ended identifiers: component key, issue,
   source PR, release PR) state their duties separately, and the `hub_input`
   entry's note on `hub_tracker_reconciliation_outcome`'s bundle-side
   `default="pending"` explains why an optional flag with a closed-enum default
   does not contradict "require the flag" (plan decision D13).
2. The producer's emitted-field table lists every field the producer emits, each
   carrying exactly one trust class, and no field's entry contradicts the
   definition of the class it carries. `selected_product_repo_key` is
   `producer_required_nullable`; `component_tag` and `component_version` are
   `producer_conditional` (the key is always emitted, but the value is `null`
   when the corresponding flag was not supplied); every other always-emitted
   field — always emitted with a non-empty value, never conditionally `null` —
   is `producer_required`.
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
7. A `classify_component` mutation-eligibility decision-gate section embeds a
   verbatim copy of Table A (ordered preconditions) and Table B (accumulating
   outcome) from the plan's "Decision gate — `classify_component` mutation
   eligibility (hub path)" subsection, including the repository-mode-is-first-gate
   paragraph preceding Table A and the `child_release_state`
   precedence-resolution paragraph following Table B — not merely a pointer
   into the plan, because `sync-manifest.yaml` makes `docs/workflow/`
   `always_sync` to downstream template consumers while `docs/specs/` is never
   synced, so a bare pointer into the unsynced plan would be broken for those
   readers.

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

This step uses the real `gh` CLI, not the Step 11 milestone fixture's mock
stub. Confirm `PATH` no longer has that stub's directory ahead of the real
`gh` (Step 11 restores it, but re-check if any earlier step in this run was
retried or reordered), then fetch the issue body and stop immediately if the
fetch did not actually produce one — an empty or missing body file must never
be passed on to the gate silently:

```bash
gh issue view 1529 --json body --jq .body > "$SMOKE_TMP/1529-body.md"
[ -s "$SMOKE_TMP/1529-body.md" ] || {
  echo "gh issue view 1529 produced an empty body — stop here; check that" \
       "PATH is not still pointing at the Step 11 mock gh stub and that" \
       "gh is authenticated for this repository" >&2
  exit 1
}
./scripts/development-workflow/scope-residual-gate.sh verify \
  --issue-title "workflow-hub: audit the delivery-bundle evidence trust boundary — consumers accept unvalidated caller-supplied values" \
  --issue-body-file "$SMOKE_TMP/1529-body.md" \
  --evidence docs/specs/developments/20260912021032_1529-delivery-bundle-trust-boundary/residual-evidence.json
```

**Expected result**: the `gh issue view` fetch succeeds and produces a
non-empty `$SMOKE_TMP/1529-body.md`; if it does not, stop and fix the fetch
(this is a hard precondition failure, not a soft one to route around) before
re-running the gate. `scope-residual-gate.sh verify` then reports
`RESULT=pass` with `SCOPE_CLASSIFICATION=numeric_sweep`.

### Step 17: Both consumers reject a producer-unemittable `ci_outcome: "skipped"` (GAP-14)

**Maps to**: Acceptance Criterion 2.

`component-release-evidence.sh`'s `--ci-outcome` enum is
`pending|passed|failed|not_applicable` — it can never emit `skipped`. Confirm
neither consumer that reads `ci_outcome` still admits that value.

1. Take an **unfinalized**, otherwise-ready bundle (as in Step 6's honest
   update, but before any successful `finalize` call against it — `finalize`
   on an already-finalized manifest short-circuits on the idempotency check
   and returns `{"result": "idempotent", ...}` without ever re-evaluating
   component readiness, which would never exercise this guard) and directly
   mutate its `mobile-app` component's stored `ci_outcome` to `"skipped"`,
   then run `finalize` on the manifest for the first time.

   **Expected result**: `finalize` fails with
   `ERROR_CODE=blocked_component_outcome`; the manifest revision is unchanged
   (T23).

2. Run `inspect-component` on the hub path with an evidence file that is
   otherwise valid except `ci_outcome: "skipped"`.

   **Expected result**: `blockers` contains `ci_outcome_skipped` and
   `mutation_allowed` is `false` (T24).

### Step 18: Reconciliation rejects a non-string `ci_outcome` or `deployment_outcome` without crashing (GAP-16)

**Maps to**: Acceptance Criterion 2.

`classify_component`'s hub path checks `ci_outcome` and `deployment_outcome` with
Python set membership, which hashes its left operand. Before this fix, a
present, non-string JSON value (for example a JSON array) for either field made
that check raise an uncaught `TypeError` instead of returning a blocker.
Confirm the fix rejects both cleanly.

`inspect-component` never uses a non-zero exit code to signal a blocker —
`cmd_inspect_component` only prints `classify_component`'s result and `main`
returns 0 for every subcommand dispatch that completes without raising, so a
blocked (`mutation_allowed: false`) result is reported entirely through the
JSON body, exactly as it is in Steps 8, 9, and 10. This is different from
`apply-component`, whose `cmd_apply_component` explicitly calls `fail(...)`
(exit 1) when `mutation_allowed` is not `true`. The defect this step guards
against is the unmodified script *crashing* — exiting non-zero for the wrong
reason (an uncaught `TypeError`/traceback) instead of returning 0 with the
blocker in the JSON body — so "exits cleanly" below means exit `0`, not a
non-zero status.

1. Run `inspect-component` on the hub path with an evidence file that is
   otherwise valid except `ci_outcome: []` (a JSON array, not a string).

   **Expected result**: the command exits `0` and prints a JSON result — no
   Python traceback, no uncaught exception, no non-zero crash exit. `blockers`
   contains `ci_outcome_invalid` and `mutation_allowed` is `false` (T25).

2. Run `inspect-component` on the hub path with an evidence file that is
   otherwise valid except `deployment_outcome: []`.

   **Expected result**: the command exits `0` and prints a JSON result — no
   Python traceback, no uncaught exception, no non-zero crash exit. `blockers`
   contains `deployment_outcome_invalid` and `mutation_allowed` is `false`
   (T26).

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
      ignored evidence file, empty identity fields, a producer-unemittable
      `ci_outcome: "skipped"`, and a non-string `ci_outcome`/`deployment_outcome`
      are all rejected cleanly, without crashing (Steps 5, 6, 7, 8, 9, 10, 11, 12,
      17, 18).
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

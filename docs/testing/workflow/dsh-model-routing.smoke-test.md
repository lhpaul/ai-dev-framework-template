# Smoke Test Runbook: DSH Per-Role Model Routing

**Feature**: #1927, DSH model routing
**Spec**: [Product contract](../../specs/developments/20261008075556_dsh-model-routing/1_dsh-model-routing_specs.md)
**Plan**: [Implementation contract](../../specs/developments/20261008075556_dsh-model-routing/2_dsh-model-routing_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: Implementation — actual DSH routing evidence recorded below.

## Prerequisites

- [x] Implementation branch has the resolver, tests and documented dispatch contract.
- [x] Python3 with the existing strict reader's PyYAML dependency is available.
- [x] Local DSH supports the verified child-selection contract; record dsh --version.
- [x] Operator already has working permitted routes for different balanced/premium models. Provider/account setup is excluded.
- [x] Use a temporary workspace, shared/local YAML fixtures and a temporary host overlay. Do not change the repository's real local YAML/env or checkpoint-policy.json.
- [x] Read the implemented DSH guide's fresh-session and exact allowlist setup. No supplied design assets; no fidelity baseline is needed.

## Test Data

Tests generate deterministic temporary configurations for the plan's parser-risk
classes. Use synthetic route strings for config-only checks; use operator-existing
working provider/model ids for the live session. Record no secrets or full host
configuration. The live allowlist contains all pairs selected by the smoke.

The committed shared policy remains unchanged throughout the local-override
journey. Save its before/after content digest in private smoke evidence. Retain
branches and existing data; discard no repository work during smoke.

## Smoke Test Steps

### Step 1: Prove absent policy and commented template defaults

**Maps to**: AC1, AC8.

1. Run model-route for developer against a temporary directory with neither
   policy file, then files containing only unrelated configuration.
2. Confirm SOURCE is inherited and no route fields are selected.
3. Check the shipped shared/local example routing blocks are fully commented.
4. Compare absent-routing validation and reviewer behavior with existing tests.

**Expected result**: No routing activation; legacy behavior remains unchanged.

### Step 2: Inspect composition, precedence and listing

**Maps to**: AC2, AC3, AC4.

1. Run the new DSH/config suites using their isolated fixture setup.
2. Inspect examples exercising every source: local-role, committed-role,
   local-tier, committed-tier, inherited; include a role reference and direct
   role route. Confirm a shared direct role route outranks a local default tier.
3. Apply a provider-only local mapping override, retaining its shared model;
   override an unrelated role and confirm other settings remain effective.
4. Exercise mapping/reference replacement and a local empty mapping.
5. Inspect PROVIDER, MODEL, REASONING_EFFORT, SOURCE, SOURCE_FILE and TIER.
6. Run model-routes against the fixture; ensure the listing includes effective
   configured routes reachable by roles and explicit tier requests, including
   a configured tier unused by current role overrides.

**Expected result**: Results follow plan D1–D4 and spec BR2–BR5; inspection writes
nothing and creates no child session.

### Step 3: Reject malformed policy with the same validator errors

**Maps to**: AC5.

1. Exercise the plan's concrete parser-risk cases through model-route and
   validate-workflow-config.sh against temporary fixtures.
2. Confirm unknown role/tier, wrong types, incomplete effective routes, empty
   required ids, unknown route keys and dangling winning references fail.
3. Include malformed lower-layer types masked by a local override; they must
   still fail. Include a valid lower-layer reference replaced by a local direct
   route; only the winning reference is checked for dangling resolution.
4. At a recorded fixture file and line, plant a provider-only effective route,
   observe failure, supply the missing model and observe pass.
5. Confirm failure emits a structured diagnostic without a success route or
   unrelated configuration contents.

**Expected result**: Invalid configured routing is visibly blocked; no silent
inheritance or configuration writes.

### Step 4: Verify contract, allowlist setup and headless boundary

**Maps to**: AC6, AC7, AC8.

1. Run the DSH documentation/role parity assertions and existing Step7a
   consistency suite. Show any newly added check's planted-violation failure
   and corrected pass in a temporary documentation fixture.
2. Follow the guide's UI or temporary profile-overlay path to enable model
   selection and allowlist the smoke route pairs. Start a fresh DSH session
   after configuring that overlay; do not depend on changes affecting an old
   session's captured allowlist.
3. Inspect the selected subagent tool's fields and session policy. Record the
   installed backend capability; model catalog absence alone does not prove
   an allowlist denial.
4. Check that the guide separately explains headless agent-default-model/profile
   or invocation-overlay pinning and that role policy does not select it.

**Expected result**: Setup instructions agree with actual capability and source
policy. Headless and child-dispatch model controls remain distinct.

### Step 5: Run balanced and premium children in one real DSH session

**Maps to**: AC6, AC9.

1. In the temporary fixture workspace, assign a working route to balanced and
   a different working route to premium; choose developer and product-manager
   as example roles with no direct role override.
2. Resolve both roles with the implemented resolver and retain their complete
   routing records. Ask the DSH driving session to follow resolve/pass/record
   and dispatch each child in the foreground with those provider/model fields.
3. Ask each child for a minimal fixed acknowledgement, avoiding external writes.
4. Inspect actual child creation/request or runtime session evidence, rather
   than relying on the child's self-reported model name.
5. Record the same parent session id, child ids, actual provider/model, resolver
   source/file/tier, and dispatch request fields for each child.

**Expected result**: Both children run on the configured distinct routes in the
same real DSH session, with route/source evidence. Mock adapter or configuration
output alone cannot pass this step.

### Step 6: Change one role privately and prove actual dispatch

**Maps to**: AC2, AC4, AC9.

1. Add a temporary local override for developer using another already permitted
   working route; keep that pair in the session's original allowlist.
2. Resolve developer again, showing local-role source. Confirm product-manager
   still resolves its previous route and shared policy's digest is unchanged.
3. In the same parent session, dispatch a fresh developer child with the newly
   resolved fields. Inspect its actual runtime route and record child id/source.

**Expected result**: One role changes through private policy only; actual child
routing matches the override, other role/shared policy remain unchanged.

### Step 7: Exercise visible inherited fallback

**Maps to**: AC6.

1. Start a separate fresh session with selection disabled in its temporary host
   overlay. Resolve a valid configured role, then follow the contract's visible
   fallback: state selection-disabled reason and omit all route fields.
2. In a fresh session with selection enabled but the requested pair denied by
   its exact allowlist, follow the same process with an allowlist-denied reason.
3. Record requested route/source, actual inherited route, and omitted dispatch
   fields. Do not use a provider failure or advisory catalog absence to stand
   in for either setup condition.

**Expected result**: Both host restriction paths expose fallback, while invalid
policy and actual stage/provider failures remain errors under their own paths.

### Step 8: Verify consumer sync and finish evidence

**Maps to**: AC10.

1. Run sync-manifest coverage and release-fragment validation.
2. Run diff-selected workflow regression suites; keep no-routing consumer
   fixtures passing and verify the proposed unit file/runbook are shipped.
3. Recheck git diff --check and the root's real local-file digests without
   displaying their contents. They must be unchanged.
4. Stop the temporary smoke runtime cleanly. Retain requested branches/data and
   leave the actual execution evidence available privately for the parent.

**Expected result**: All acceptance checks have concrete evidence; consumers
without DSH routing keep their existing behavior.

## Assertions Checklist

- [x] AC1: Inherited absence and commented inactive defaults verified.
- [x] AC2: Partial/local overrides preserve unrelated entries and shared policy.
- [x] AC3: Every source/precedence/reference/direct form checked.
- [x] AC4: Route/source/file/tier and effective route listing checked.
- [x] AC5: Structured strict errors and validator parity checked.
- [x] AC6: Dispatch contract, source evidence and both fallback reasons checked.
- [x] AC7: Host setup and headless pinning guidance verified against runtime.
- [x] AC8: Policy parity/commented examples checked.
- [x] AC9: Same actual DSH parent session runs distinct tier children and fresh
  locally overridden child with runtime route evidence.
- [x] AC10: Regression, manifest ownership and release fragment verified.

## Evidence Record

Record implementation head, DSH version, suite commands/results, exact planted
fixture file/line, parent/child ids, requested/effective route and SOURCE for each
live dispatch, fallback reason, shared-policy digest comparison and any blocker.
Private file paths and runtime logs are not copied into public audit comments;
public summaries may contain route ids, version and concise results.

The execution record below describes the implementation verification run.
Repeat these steps and refresh the evidence when a later resolver changes
behavior.

## Actual Execution Evidence — 2026-10-08

DSH `0.2.0-rc.2` passed the live routing journey through its public AgentRegistry
factory and native subagent tool registry using a real in-process spawn backend.
Actual request/context events verified provider/model and parent/child lineage;
each child returned the exact fixed acknowledgement. These are runtime results,
not model self-reports or mocked adapter output. The temporary host overlay used
existing working routes; the temporary smoke preset declared no
file/network/Claude tools.

Actual runs used resolver checkpoint `619f70841ce67fb07c1fb7dd2154cb79f0df3243`.
A replay against implementation resolver revision
`6cb5d20d589488ee921f36f57a51255d08bf8b69` matched all five captured resolutions
using immutable per-case fixtures: role, tier, provider/model/effort, SOURCE and
source filename. The resolver content digest was retained privately; future
behavioral resolver changes require renewed replay or live smoke as appropriate.

All routes below use existing provider `bailian-tpp`. SOURCE_FILE was the isolated
shared `.ai-dev-workflow.yaml`, except the private role override used isolated
`.ai-dev-workflow.local.yaml`. No real repository local configuration changed.

| Case | Parent session | Child session | Requested / actual model | Source / outcome |
| --- | --- | --- | --- | --- |
| balanced | adf1927-374e052f-e24a-4f10-8bd3-f71325b63d55 | 12c95786-2417-410a-b5d1-4fa6697a304f | qwen3.7-plus / qwen3.7-plus | committed-tier; passed |
| premium | adf1927-374e052f-e24a-4f10-8bd3-f71325b63d55 | a9945aa3-159b-4707-8a64-59cbc0405510 | qwen3.7-max / qwen3.7-max | committed-tier; passed |
| local-role-override | adf1927-374e052f-e24a-4f10-8bd3-f71325b63d55 | ce6dc9c1-a8f3-4ece-89be-6a890a3d731e | glm-5.3 / glm-5.3 | local-role; passed |
| disabled | adf1927-9005fdf0-778b-43ae-a699-6376a9af4cf7 | dc70aa9b-3738-4ee6-bfaf-102275285a08 | qwen3.7-plus / glm-5.3 | committed-tier; selection-disabled |
| denied | adf1927-48c0ec01-a016-42b8-8e40-6b15d6394c00 | 16512dff-67c9-4936-94c2-a206359f3d41 | qwen3.7-plus / glm-5.3 | committed-tier; allowlist-denied |

Balanced, premium and local-role children share one parent. The product-manager
route remained unchanged after the local developer override. Shared policy's
before/after SHA256 was identical:
`57708645cb13fb131c54f62fdd4760f5f0179f9d85a9bced199819b187162f6d`.
Selection-disabled and allowlist-denied each used a fresh separate parent and
passed an empty dispatch field object, then actually inherited `glm-5.3`.
All temporary runtimes shut down gracefully; fixture/session data was retained.

Configuration and contract verification: the DSH suite's 18 unit methods cover
all planned input classes; the existing resolver suite passed 798 assertions,
hub-smoke fixtures passed 70 and Step7a consistency passed 25. All 37 final
diff-selected workflow suites passed, including consumer sync, release fragments
and merge-session recovery. Manifest coverage passed for single_repo,
workflow_hub and product_repo; real local-file digests remained unchanged.
Planted checks
failed for a provider-only route at fixture line 6 and for an omitted
selection-disabled contract at fixture line 230, then passed after correction.
These fixture paths remain private; they contain synthetic data only.

## Troubleshooting and Known Limitations

| Symptom | Action |
| --- | --- |
| Unknown role or tier | Use the plan's canonical catalogue; do not infer runner-specific aliases |
| YAML fixture rejected | Use block mappings and the existing strict-reader subset |
| Selection fields absent | Confirm temporary opt-in, backend capability and fresh session; report disabled fallback visibly |
| Previously allowed route still denied | Inspect the session's captured exact policy, not later host-setting edits |
| Working route unavailable or provider failure | Report actual failure to the parent; no account setup, secret output or mocked substitute |
| Headless child inherits | Expected boundary; headless default pinning is separate from project role policy |

Real-route availability is an operator prerequisite. Missing working routes,
permissions or runtime capability block the live acceptance step; they do not
make the configuration tests sufficient evidence for actual DSH child routing.

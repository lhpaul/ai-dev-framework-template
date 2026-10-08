# DSH Per-Role Model Routing — Spec

**Issue**: #1927

## Overview

Operators can assign different model routes to DSH workflow roles using shared
project policy and private machine overrides. A DSH Work Item Runner resolves
that policy before dispatch, reports which policy supplied the route, and makes
any host-imposed fallback visible. Projects without routing policy retain their
current inherited-session behavior; the template enables no provider or model.

The approved scope is [issue #1927](https://github.com/lhpaul/ai-dev-framework-template/issues/1927)
and its acceptance criteria. Luis confirmed continuation on 2026-10-08 and
waived the technical checkpoint because provider credentials and account setup
are explicitly excluded. Related items #1891, #1761, and #1760 are precedents,
not new dependencies or work included here. No design assets were supplied.

## Use Cases

### Use Case 1: Configure shared and machine-specific routes

**Actor**: Project operator.
**Preconditions**: The project uses DSH; the operator can edit project policy
and, separately, private machine policy.

**Steps**:

1. Assign routes to the economy, balanced, and premium tiers as needed.
2. Optionally assign a workflow role to a tier or directly to a route.
3. Override selected settings privately on one machine.
4. Inspect the effective route for a role, its source layer, source file, and
   tier; list effective routes to prepare the host allowlist.

**Postconditions**: Local changes affect the selected settings while unrelated
shared settings remain effective. Inspection changes neither policy nor host
settings and does not start a child session.

**Information shown**: Provider, model, optional reasoning effort, source layer,
source file, and tier used; inherited routes explicitly say no route is selected.

**Actions available**: Correct invalid policy, revise a local override, inspect
another role, or use the inherited session model by leaving policy absent.

**Considerations**: Configuration discovery works in ordinary checkouts and
temporary worktrees. Invalid policy produces an actionable structured error;
it is never silently treated as absent policy.

### Use Case 2: Dispatch a role under DSH

**Actor**: DSH Work Item Runner, on behalf of the workflow operator.
**Preconditions**: A workflow stage requires a child role; current policy can
be read and validated.

**Steps**:

1. Resolve the role using the current policy and its recommended tier.
2. Request the effective route for that child when host model selection permits
   it; request no route when the result is inherited.
3. If selection is disabled or the route is not allowlisted, visibly report the
   restriction and use the inherited session model for the child.
4. Record the resolution, source, and actual dispatch decision in the runner
   summary or review evidence.

**Postconditions**: Evidence distinguishes a requested configured route from a
host-limited inherited fallback. Invalid policy blocks routed dispatch until
corrected, rather than starting a child with an invented route.

**Information shown**: Role, selected tier, requested route and policy source,
actual configured or inherited dispatch, and a reason for any fallback.

**Actions available**: Continue the existing stage lifecycle with valid dispatch,
correct invalid policy, or enable and allowlist a configured route explicitly.

**Considerations**: A failure after dispatch is an ordinary stage/review failure,
not evidence that policy was absent or host model selection was disabled.

### Use Case 3: Prepare host settings and headless reviews

**Actor**: DSH operator or review operator.
**Preconditions**: DSH is installed and operator-controlled host settings exist.

**Steps**:

1. Follow documented UI or profile-overlay guidance to enable child model
   selection and allowlist the routes the effective project policy can produce.
2. For a headless review, explicitly pin the headless default in its profile or
   an invocation overlay when a particular model is desired.
3. Verify two tier-assigned child roles use distinct permitted routes and that
   a private override changes one role without changing shared policy.

**Postconditions**: Operators understand that project role routes govern child
dispatch, while headless default-model selection remains separately controlled.

**Information shown**: Setup instructions, effective routes for allowlist
maintenance, the headless limitation, and a smoke evidence checklist.

**Actions available**: Adjust host settings, pin a headless default, or retain
inheritance. No credentials or provider accounts are provisioned by this item.

## Business Rules

- BR1: Shared project policy and machine-local policy are optional. Missing
  files or routing blocks preserve inheritance; the shipped template contains
  only commented routing examples and activates no provider/model names.
- BR2: Local policy deep-merges over shared policy by key. Unchanged tiers,
  roles, and route fields are inherited. A scalar tier reference replaces a
  route mapping, and a route mapping replaces a scalar reference; conflicting
  entry forms are not combined into a hybrid. Validate the effective route
  after composing partial overrides; a provider or model left without its
  counterpart is invalid.
- BR3: For a role, the first applicable role entry wins: local role, then shared
  role. A direct route is used directly. A tier reference selects that tier,
  resolved local tier before shared tier. With no role entry, use the role's
  recommended tier, resolve local tier before shared tier, then inherit if
  neither exists. An explicit tier reference that resolves nowhere is invalid,
  and cannot fall through to inheritance.
- BR4: Economy, balanced, and premium are the supported tiers. Supported roles
  and default tier assignments follow the existing workflow role policy. A
  caller may request a supported tier explicitly; an explicit role policy still
  takes precedence. Unknown roles/tiers, wrong types, empty required route
  values, incomplete effective routes, and dangling references fail closed.
- BR5: Evidence names local role, shared role, local tier, shared tier, or
  inherited as the resolution source. For a composed selected entry, the local
  layer is reported when it contributes an override to that selected entry;
  otherwise the shared layer is reported. A tier-based result identifies the
  tier route's source layer/file and the selected tier. A direct role route has
  no tier used; inheritance has no route or route-source file. Route listing
  exposes all effective configured routes needed for host allowlist setup.
- BR6: Each resolution is read-only and uses the configuration current for that
  invocation. Recorded evidence applies to that resolution and child dispatch;
  old evidence does not establish a later invocation's route. Existing strict
  configuration reading and local discovery semantics remain authoritative.
- BR7: Disabled selection and a denied allowlist route have a visible inherited
  fallback. Malformed policy and post-dispatch failures do not use that fallback.
  No workflow authority, review gate, permission, or merge-risk limit changes.
- BR8: Child routing does not change the headless review default, fork child
  routing, other runners' model selection, or the shipped draft-review runner.

## Decision Contract and Consistency Matrix

Rows are evaluated top to bottom. A matching local/shared role reference chooses
its tier before the tier rows; unrelated local tiers cannot outrank a shared
role's direct route. Partial mappings follow BR2 before validation (BR4).

| Inputs | Outcome | Required next action | Governing surfaces | Example |
| --- | --- | --- | --- | --- |
| Invalid role, tier, policy type, or effective route | Configuration error | Show structured diagnostic; correct policy before routed dispatch | Resolver, config validation, routing guidance | Provider with no effective model |
| Local role exists as a direct route | Local role | Use composed role route | Resolver, runner contract, routing docs/examples | Override only one developer route |
| Shared role exists as a direct route; no local role | Shared role | Use shared role route | Same routing surfaces | Shared direct reviewer route wins over a local default-tier route |
| Winning role is a tier reference | Selected tier | Resolve that tier locally then shared; error if absent | Same routing surfaces | Local role chooses premium; shared premium supplies route |
| No role entry; selected/default tier has a local contribution | Local tier | Use composed tier route | Same routing surfaces | Only premium is overridden locally |
| No role entry; selected/default tier exists only shared | Shared tier | Use shared tier route | Same routing surfaces | Balanced role inherits the shared balanced route |
| No role entry; selected/default tier absent in both layers | Inherited | Pass no route | Same routing surfaces | No routing block in either file |
| Valid configured result; host selection enabled and route permitted | Configured dispatch | Pass selected route; record route and source | Runner contract, DSH guidance, smoke runbook | Balanced and premium children use different permitted models |
| Valid configured result; selection disabled or route denied | Visible inherited fallback | Report reason; pass no route; record actual inheritance and requested source | Same dispatch surfaces | Host allowlist omits requested premium route |
| Resolution complete; child then fails | Stage/review failure | Follow existing stage failure handling | Existing stage lifecycle | Child review returns no valid verdict |

Resolution rows and dispatch rows describe consecutive phases; they are not
competing matches. Configured dispatch and visible inherited fallback continue
the existing workflow. Configuration error waits for correction; a stage failure
uses the existing fix/escalation path. No new item-terminal state is introduced.

## Operational Visibility

Resolution inspection and validation expose structured, actionable diagnostics
without mutating configuration. Runner summaries and review evidence record the
role, effective/requested route, source layer/file and tier, actual dispatch,
and any host fallback reason. No product analytics, notifications, or new
retention service is required; use the existing workflow evidence surfaces.

## Acceptance Criteria

- [ ] AC1: With neither policy file or neither routing block present, role
  resolution is inherited and child dispatch receives no route; enabled
  behavior remains unchanged and template examples activate no model names.
- [ ] AC2: Shared tier/role settings plus a local override of only premium or
  only developer preserve unrelated settings. Partial mapping-field overrides
  compose as BR2 defines; mapping/reference replacements are deterministic.
- [ ] AC3: Fixtures demonstrate local role, shared role, local tier, shared tier,
  and inherited precedence; direct role routes outrank default-tier routes,
  and tier-reference roles resolve local before shared tier.
- [ ] AC4: Inspection reports provider, model, optional reasoning effort, source
  layer, file, and tier consistently with BR5. Effective route listing lets an
  operator keep the host allowlist complete.
- [ ] AC5: Unknown roles, unknown tiers, wrong types, empty required values,
  incomplete effective routes, and dangling tier references emit structured
  errors and block routed dispatch. Standalone config validation reports the
  same policy errors. Partial valid compositions and absent files are covered.
- [ ] AC6: The Work Item Runner contract and DSH guidance describe resolve,
  pass, and record, plus visible inheritance when selection is disabled or a
  route is denied. Routing evidence and documentation consistency are checked.
- [ ] AC7: Operator guidance covers UI and profile-overlay allowlist setup,
  effective-route listing, and headless default pinning through a profile or
  invocation overlay. Headless defaults do not consume role dispatch policy.
- [ ] AC8: Model-policy guidance explains DSH layered routing and precedence
  alongside existing Codex guidance; shared and local example files contain
  commented examples. Later generalization to other runners is identified as
  outside this item.
- [ ] AC9: The smoke runbook verifies, in one DSH session, balanced and premium
  role children using distinct permitted routes, then a temporary local override
  changing one role without editing shared policy, recording route and source.
  Smoke examples use fixtures/temporary directories and do not change real
  machine-local files.
- [ ] AC10: The implementation includes routing regression/error coverage,
  applicable template sync ownership entries, and a release-note fragment.
  Specification and plan PRs remain documentation-only stages.

## Brief Objective List and Coverage Matrix

| Objective | Brief requirement | Coverage |
| --- | --- | --- |
| O1 | Optional shared/local tier and role policy; template activates no models | AC1, AC2, AC8 |
| O2 | Per-key local deep merge and exact precedence; role reference/direct forms | AC2, AC3; BR2–BR4 |
| O3 | Read-only strict resolver; effective route, source, file, tier; route listing | AC4, AC5; BR5–BR6 |
| O4 | Config validation and tests for precedence, invalid input, absent files | AC3, AC5, AC10 |
| O5 | Runner and DSH dispatch contract, visible fallback, consistency coverage | AC6; decision matrix |
| O6 | Host UI/profile allowlist guidance and headless pinning note | AC7 |
| O7 | Model-policy parity documentation and commented examples | AC8 |
| O8 | Two-route DSH smoke, local override, evidence, sync entries, release note | AC9, AC10 |
| O9 | Optional static per-tier preset bundle | Out of Scope S1; deferred |
| O10 | Respect excluded runners, credentials, upstream and fork changes | Out of Scope S2–S8; BR8 |

## Out of Scope (MVP)

- S1: Static per-tier DSH preset bundle. Optional follow-up, explicitly excluded
  from this run; it is unnecessary for the approved dynamic dispatch contract.
- S2: In-repository DSH role-agent files mirroring other runners.
- S3: Changing the shipped draft-review runner default.
- S4: Vendor credentials and provider account setup.
- S5: DSH upstream changes.
- S6: Fork child route selection; existing parent-route inheritance continues.
- S7: Moving the local AI reviewer to DSH.
- S8: Model overrides for Claude Code, Cursor, or Codex; generalizing routing
  policy to other runners requires a later item.

## Deferral Notes

O9's static per-tier preset bundle is deferred because the approved brief marks
it optional and Luis's execution instruction excludes it unless the approved
plan includes it. This spec does not include it; no further confirmation is
requested. O10's exclusions remain excluded because #1927 and the confirmed
execution scope explicitly set those boundaries; no confirmation is requested.
Implementation naming and technical design are decided in the plan stage.

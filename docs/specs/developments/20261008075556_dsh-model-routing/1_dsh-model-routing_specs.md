# DSH Per-Role Model Routing — Spec

**Issue**: #1927

## Amendment status

This proposed amendment replaces the reading/activation boundary approved in
spec PR #1932. Luis selected a dependency-free strict subset on 2026-10-08 and
authorized documentation PRs only, without merge. The original merged history
and implementation PR #1934/local candidate `43bddf22` remain unchanged.
Implementation must wait for human approval and merge of both amendments.

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

1. Explicitly activate each contributing file with the BR9 envelope, then
   assign routes to the economy, balanced, and premium tiers as needed.
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
  files or files without the explicit activation defined below preserve
  inheritance; an unactivated `models.dsh` is legacy data, not routing policy.
  The shipped template contains
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
  old evidence does not establish a later invocation's route. Existing local
  discovery is unchanged. Unactivated files retain their legacy reading contract;
  activated policy uses the strict format below, without a YAML dependency.
- BR7: Disabled selection and a denied allowlist route have a visible inherited
  fallback. Malformed policy and post-dispatch failures do not use that fallback.
  No workflow authority, review gate, permission, or merge-risk limit changes.
- BR8: Child routing does not change the headless review default, fork child
  routing, other runners' model selection, or the shipped draft-review runner.

## Strict DSH Format and Activation

BR9 is the single format contract for routing policy. This is an intentional
amendment to bare `models.dsh` activation, not transparent support for all YAML.
Each selected shared/local file independently opts in using these exact lines:

```yaml
# adf-models-dsh: v1
models:
  dsh:
    tiers:
      balanced:
        provider: "provider-id"
        model: 'model-id'
    roles:
      developer: balanced
# adf-models-dsh: end
mode: single_repo
```

- **BR9a — Activation/envelope:** the opening marker must be the first physical
  line (column zero, UTF-8 without BOM). LF and CRLF are allowed. A BOM
  followed by the reserved prefix is an invalid envelope, not inactive policy. A first line
  beginning `# adf-models-dsh:` reserves this protocol: unknown version, wrong
  spacing, premature end, or any malformed opener fails closed. No prefix means
  no activation; later markers/comments or bare `models.dsh` do not activate it.
  The exact end marker at column zero is mandatory and closes the policy.
  Inside: one root `models` mapping, empty or containing exactly `dsh`; blank lines and ordinary
  comments may surround entries. An empty policy is `models: {}`; `dsh: {}`,
  `tiers: {}` and `roles: {}` are also allowed and select no route by themselves.
  A route `{}` remains subject to effective completeness after composition.
- **BR9b — Grammar:** block mappings, exactly two ASCII spaces per nesting
  level, no tabs or indentation jumps. Keys are unquoted ASCII identifiers
  `[A-Za-z_][A-Za-z0-9_-]*`. Membership is checked only in the schema
  phase: a lexically valid unknown key is a schema-name error, not syntax.
  Accepted keys belong to their schema level: `models`,
  `dsh`, `tiers`/`roles`, supported tier/role catalogue, or
  `provider`/`model`/`reasoning_effort`. The only inline collection is `{}`.
  Accepted values are single-line strings or mappings. The lexer recognizes
  null/boolean/numeric tokens for schema-type rejection, not syntax rejection.
  Bare strings use only ASCII
  letters/digits and `_ . / : @ + -`, without spaces; `null` (any case), `~`,
  `true`/`false` (any case), and decimal numeric literals are invalid types,
  not route strings. Numeric literals mean signed integers or decimal/exponent
  forms, including `.5`, `1.` and `1e3`; quote them to use them as identifiers.
  `yes`, `no`, `on` and `off` are strings; no YAML 1.1 implicit coercion applies.
- **BR9c — Quoting/comments:** single-quoted strings escape a quote with `''`;
  backslashes are literal. Double-quoted strings accept only `\\` and `\"`
  escapes. Other escapes, unmatched quotes, raw/decoded control characters,
  NEL/U+2028/U+2029 and multiline strings are rejected. Printable Unicode is
  allowed inside quotes. After a value, only spaces or a space-separated `#`
  comment may follow; `#` inside quotes is literal. Empty/blank required route
  strings fail schema validation. Quoted `"null"` is a string. Quoted `"&x"`,
  `"*x"` and `"<<"` are literal values, not operators.
- **BR9d — Explicit rejection:** fail closed on sequences/lists with or without
  indentation, nonempty flow mappings/sequences (including trailing commas),
  dangling items, unclosed delimiters, multiline/block scalars, tags,
  directives/document markers, duplicate keys, anchors, aliases, merge keys,
  unknown keys and null/boolean/numeric or other incorrect types in policy.
  Both `models:\n- dsh: {}` and its indented-list counterpart are errors;
  neither is absence. Malformed or unsupported activated syntax cannot be
  recovered by another parser or treated as inherited routing.
- **BR9e — Legacy region:** the text after the end marker is ordinary legacy
  configuration; it must not supply another root `models` key or envelope.
  Validate its syntax through the existing dependency-free legacy reader after
  removing the policy region while preserving line positions. Retain legacy
  context semantics/arguments. All three commands share that reading result;
  extra repository-context checks belong only to validate. For files without
  activation, retain original legacy semantics for the same input bytes, with no strict
  DSH scan, YAML-library import or newly rejected syntax. Such a file contributes
  no routes even if it contains bare `models.dsh`. Operators must explicitly
  migrate that policy into the envelope; there is no automatic conversion.
  The existing `set-local-path` operation must preserve an activated local
  policy and its envelope while updating unrelated repository paths. It must
  reject malformed activated input before writing, rather than silently
  deactivate policy. Unactivated editing behavior stays unchanged.

### Format outcomes and parity matrix

Rows are evaluated per selected layer, before composition; any activated error
wins over successful absence or a valid override in the other layer. Within an
activated layer: envelope, policy grammar, legacy-region syntax, schema, then
composition/reference validation. The same ordered reader/validator governs
all three commands and the shell validation wrapper.

| Input | Outcome | Required next action | Example |
| --- | --- | --- | --- |
| File missing or no reserved first-line prefix | No routing contribution; legacy behavior | Opt in explicitly to configure routes | Bare models.dsh remains inactive |
| Reserved prefix malformed, version unknown, missing/repeated end, second envelope or tail models | Structured envelope error, exit 2 | Correct envelope; do not dispatch | v2 opener or missing end |
| Active unsupported/malformed grammar | Structured syntax error, exit 2 | Correct to BR9 subset | Indentless models list or unfinished flow item |
| Active policy wrong type/name or invalid effective route | Structured schema/route error, exit 2 | Correct schema/composition | dsh: null or dangling tier |
| Active valid partial/empty policy | Compose with other selected layer | Resolve using BR2–BR5 | Local provider inherits shared model |

The existing resolution/dispatch matrix remains applicable after this format
matrix. A malformed activated policy never reaches host fallback. Current
invocation evidence governs; an earlier successful parse cannot authorize a
later dispatch.

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

- [ ] AC1: With no activated policy or only valid empty activated policies,
  resolution is inherited and child
  dispatch receives no route; legacy validation/output/dependencies and enabled
  behavior remains unchanged and template examples activate no model names.
- [ ] AC2: Shared tier/role settings plus a local override of only premium or
  only developer preserve unrelated settings. Partial mapping-field overrides
  compose as BR2 defines; mapping/reference replacements are deterministic.
  Updating a repository path through `set-local-path` preserves the local
  activated policy and the effective route; malformed activated input causes
  no write. Exercise both cases only in temporary fixtures.
- [ ] AC3: Fixtures demonstrate local role, shared role, local tier, shared tier,
  and inherited precedence; direct role routes outrank default-tier routes,
  and tier-reference roles resolve local before shared tier.
- [ ] AC4: Inspection reports provider, model, optional reasoning effort, source
  layer, file, and tier consistently with BR5. Effective route listing lets an
  operator keep the host allowlist complete.
- [ ] AC5: Unknown roles, unknown tiers, wrong types, empty required values,
  incomplete effective routes, and dangling tier references emit structured
  errors and block routed dispatch. Standalone config validation reports the
  same policy errors. For each activated input with a policy error, validate, model-route and
  model-routes share the same policy diagnostic CODE/FILE/FIELD/MESSAGE and exit 2,
  with no successful route/context on stdout. Partial compositions, missing
  files and the explicit unactivated legacy boundary are covered.
- [ ] AC6: The Work Item Runner contract and DSH guidance describe resolve,
  pass, and record, plus visible inheritance when selection is disabled or a
  route is denied. Routing evidence and documentation consistency are checked.
- [ ] AC7: Operator guidance covers UI and profile-overlay allowlist setup,
  effective-route listing, and headless default pinning through a profile or
  invocation overlay. Headless defaults do not consume role dispatch policy.
- [ ] AC8: Model-policy guidance explains DSH layered routing and precedence
  alongside existing Codex guidance; shared and local example files contain
  commented examples showing BR9 activation/envelope and quoting. Later generalization to other runners is identified as
  outside this item.
- [ ] AC9: The smoke runbook verifies, in one DSH session, balanced and premium
  role children using distinct permitted routes, then a temporary local override
  changing one role without editing shared policy, recording route and source.
  Smoke examples use fixtures/temporary directories and do not change real
  machine-local files.
- [ ] AC10: The implementation includes routing regression/error coverage,
  applicable template sync ownership entries, and a release-note fragment.
  The parameterized matrix covers the BR9 outcomes through all three commands,
  asserting expected rejection as well as parity. Specification and plan PRs
  remain documentation-only stages; no parser implementation is included here.

## Brief Objective List and Coverage Matrix

| Objective | Brief requirement | Coverage |
| --- | --- | --- |
| O1 | Optional activated shared/local tier and role policy; inactive legacy preserved | AC1, AC2, AC8; BR9 |
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

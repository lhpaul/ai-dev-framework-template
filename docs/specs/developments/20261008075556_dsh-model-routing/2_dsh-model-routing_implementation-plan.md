# DSH Per-Role Model Routing — Implementation Plan

**Issue**: #1927
**Spec**: [Approved product contract](1_dsh-model-routing_specs.md)
**Smoke test runbook**: [DSH routing smoke](../../../testing/workflow/dsh-model-routing.smoke-test.md)

## Amendment status

Documentation-only amendment to plan PR #1933 for Luis's selected strict,
dependency-free parser design. The [proposed spec amendment #1935](https://github.com/lhpaul/ai-dev-framework-template/pull/1935) to #1932 supplies
BR9, the normative format/activation contract
([review baseline](https://github.com/lhpaul/ai-dev-framework-template/blob/ad8cddc4/docs/specs/developments/20261008075556_dsh-model-routing/1_dsh-model-routing_specs.md)); the base's original spec remains
historical until that amendment merges. This plan is prepared for paired human
review, not permission to implement against an unmerged specification.
No changes to implementation PR #1934 or retained candidate `43bddf22` are
included. Both amendment PRs target develop; merge spec amendment first, then
this plan, only after Luis approves. This run merges neither.

## Summary

Extend the existing workflow configuration resolver with optional DSH routing,
strict schema validation, per-key local composition and explicit provenance.
Document the DSH parent's resolve/pass/record contract and operator setup;
prove configuration behavior with isolated fixtures and child routing with an
actual DSH session. The approved spec supplies product rules; Technical
Decisions below is the single implementation contract.

**Estimated complexity**: M, with parser/compatibility risk requiring explicit
review; no claim that a custom parser automatically qualifies for medium risk.
A later implementation must classify at medium or below before delegated merge.
**Dependencies**: Original spec PR #1932 is merged; both proposed document
amendments must be approved and merged before any implementation resumes. No further ADF feature,
provider account setup, upstream patch, or optional preset bundle is required.
The live smoke requires an installed DSH and existing working permitted routes.
No database, application frontend, production deployment, or new service changes.
Before implementation edits, verify the spec and plan amendment PRs are merged
and their approved revisions are present on the selected implementation base. If either prerequisite
fails, stop and report the missing dependency to the parent; do not substitute
an unapproved or absent spec.

## Amendment Verification Log

Evidence below is from develop `98f5de0d7d72748abced53c9a36dc461934f8ef0`,
2026-10-08; historical runtime evidence below remains explicitly historical.

| Fact / bounded scope | Reproducing query at that revision | Result / discharge |
| --- | --- | --- |
| Template fit | `rg -n 'is_template' .ai-dev-workflow.yaml` | Framework tooling, no consumer language dependency |
| Legacy versus strict readers | `rg -n '^def (parse_yaml_subset|parse_review_yaml|resolve_local_config|cmd_resolve)' scripts/development-workflow/workflow-config-resolver.py; sed -n '374,388p' scripts/development-workflow/workflow-config-resolver.py` | Existing entry points; preserve_empty_values=True delegates to PyYAML, default branch does not; new parser is proposed |
| Shared reader consumers | `rg -n 'parse_yaml_subset|preprocess_yaml|parse_mapping\(|parse_list\(|parse_scalar\(|load_configs\(' scripts --glob '*.py' --glob '*.sh'` plus `rg -n '^def |load_configs\(|parse_yaml_subset\(' scripts/development-workflow/workflow-config-resolver.py` | Existing composed paths in Composed Call Sites; review/auth/ordinary resolve remain unchanged; active validate/model commands share D2 result |
| Existing suites/runbook | `rg --files scripts/development-workflow/tests docs/testing/workflow | rg 'config-resolver|hub-smoke|step7a|dsh-model-routing'` | Existing legacy suites/runbook; new unit/harness paths are proposals on develop |
| Allowed implementation population | `sed -n '/^## Files to Modify/,/^## Risks/p' docs/specs/developments/20261008075556_dsh-model-routing/2_dsh-model-routing_implementation-plan.md` (count table paths with `rg -c '^\| (scripts/|docs/|\.ai-dev|sync-manifest|changelog.d/)'`) | Original named allowlist reproduced; normative count/scope is in amendment scope boundary |

Operational assumption check for this bounded documentation invocation: original
spec/plan are merged at the stated revisions; PR #1934 is a retained same-surface
candidate, not a competing execution. Proposed paired amendments intentionally
replace its reading contract, and implementation is held until both merge.
The parent records current PR heads and original-branch retention separately;
no portfolio scan or mutation of #1934 is authorized.

## Verification Log

Repository-derived evidence below was gathered at
`46a4c82d1acba3ac00eb7eae14ced4086853124e` on 2026-10-08. Run searches from the
repository root at that revision; future implementation paths are proposals,
not existence claims.

| Check | Reproducing command/query | Observed result |
| --- | --- | --- |
| Revision/spec merge | `git show --no-patch --format='%H %s' 46a4c82d` | Approved spec merge #1932 |
| Template fit | `rg -n 'is_template' .ai-dev-workflow.yaml` | Template mode true; this feature concerns framework workflow tooling |
| Strict reader and local discovery | `rg -n '^def (parse_review_yaml|parse_yaml_subset|resolve_local_config|linked_worktree_main_root)' scripts/development-workflow/workflow-config-resolver.py` | Existing strict parser and override-root/checkout/main-clone discovery entry points |
| Existing validate composition | `sed -n '1814,1840p' scripts/development-workflow/workflow-config-resolver.py` | resolve and validate currently share cmd_resolve; new validation must preserve existing repository-context results |
| New capability absence | `rg -n 'model-route|models.dsh' scripts docs/workflow .ai-dev-workflow.yaml .ai-dev-workflow.local.example.yaml` | No matches; routing commands and policy not yet implemented on these plausible shipped surfaces |
| Validation consumers | `rg -n 'workflow_validate_repository_context|resolver_args=\(validate|RESOLVER.*validate|workflow-config-resolver.py.*validate' scripts/development-workflow --glob '*.sh'` | CLI wrapper, workflow-lib wrapper, post-merge-cleanup calls, component-release-target calls and existing test consumers; see Composed Call Sites |
| Role population | `sed -n '/## Agent Assignments (Tier-Based)/,/### Runner Notes/p' docs/workflow/development-workflow/agent-model-config.md` | The canonical table contains the 12 roles enumerated in D1; this table, not Cursor-specific profiles, defines the population |
| Test selection | `rg -n 'covers:|Naming convention|Self-declaration' scripts/development-workflow/select-test-suites.sh` | Suite-local covers headers and naming map drive diff-based CI selection |
| Sync ownership | `rg -n 'scripts/development-workflow/|docs/workflow/|workflow-config-resolver.py|local.example|docs/testing/workflow' sync-manifest.yaml` | Existing tooling/docs ownership plus explicit smoke-runbook precedent; add the proposed runbook entry |
| Existing tests | `rg --files scripts/development-workflow/tests` | Config resolver, Step7a consistency, sync coverage and shell-snippet suites available |
| Docs scope search | `rg -n 'DSH|models|model route' docs/project docs/best-practices AGENTS.md docs/workflow/development-workflow/agent-model-config.md docs/workflow/development-workflow/integrations/dsh.md` | Routing guidance lives in model-policy/DSH integration docs; placeholder project architecture is not a routing authority |

The role-population query enumerates the named table's rows, excluding its
headings/header. A reproducible count at the recorded revision is
`sed -n '/## Agent Assignments (Tier-Based)/,/### Runner Notes/p' docs/workflow/development-workflow/agent-model-config.md | awk '/^[|] `/{n++} END {print n}'`,
which returns 12. D1 preserves that enumeration and its
tier values. No test-case count or whole-repository sweep is a binding target.

## Factual Claim Evidence and Authoring Rigor

- Rule 1 — Not applicable: this design does not match or parse external free-text
  responses. The routing data is ADF-owned structured configuration; host
  capability/allowlist decisions use explicit session policy, never matching
  error wording or treating advisory model catalog absence as denial.
- Rule 2 — Satisfied: each implementation decision is stated once in D1–D7;
  steps, tests and file scope refer to those decisions. Product invariants are
  referenced from the approved spec rather than independently redefined.
- Rule 3 — Satisfied: the existing role population is directly enumerated by the
  recorded canonical-table query, at the recorded revision. Projected tests and
  files express coverage intent and carry no binding scaffolding enumeration.
- Rule 4 — Satisfied: existence/absence and scope claims are supported by the
  Verification Log's named searches in actual parser, callers, tests and docs.
- Rule 5 — Satisfied: the validation unit's changed behavior is traced at each
  discovered ordered consumer in Composed Call Sites, including unchanged
  resolve/review commands and their separate paths.
- Rule 6 — Satisfied: D2–D7 name governed input classes, invocation scope and
  discharge points; Implementation Order applies those decisions at explicit
  steps. A changed operational assumption stops before implementation edits.

### Verified DSH Runtime Contract

Verified 2026-10-08 against installed `@deepseek-ai/dsh-tool-subagent` and `dsh`
version `0.2.0-rc.2`. Reproduce using the installed package's `package.json`,
`README.md` section "Selecting a child LLM", and `lib/index.js` /
`lib/model-selection-settings.js`. These are primary package sources; upstream
source is [deepseek-harness, tool-subagent at dsh-v0.2.0-rc.2](https://github.com/deepseek-ai/deepseek-harness/tree/dsh-v0.2.0-rc.2/packages/subagent/tool-subagent).

The tool's opt-in uses `modelSelectionSettings: true`; the host settings owner
is `subagent-model-selection-settings`, with `enabled` and exact
`allowedModels` provider/model pairs. Enabled policy needs a nonempty list and
is captured at fresh top-level session composition, inherited by children and
frozen for that session. Restored sessions without a recorded policy remain
disabled. Child selection exposes `provider`, `model`, `reasoning_effort`, and
`list_subagent_models`; provider/model are supplied together. Effort ids and
model availability are adapter-owned; discovery is advisory, not proof that an
unlisted model is denied. This capability requires a backend with agentOptions;
ACP/Codex/Claude backends reject selection rather than ignore it.

The shipped web preset opts the subagent tool into selection; the base/headless
preset's tool does not. Reproduce that distinction in the installed
`@deepseek-ai/dsh-web-app/presets/cordis.patch.yml` and
`@deepseek-ai/dsh-base/cordis.patch.yml` subagent entries. D7 applies this
verified contract; no application-side host-policy parser or upstream changes
are proposed. Reverify installed capability if the runtime version changes.

## Cross-Cutting Operational Assumption Check

Verified at 2026-10-08T11:54:03Z and the Verification Log revision. The bounded
invocation contains only #1927. Parent supplied a live same-surface open-PR
check with no competing PR on the exact resolver/validator/routing-doc/config
surfaces; shared DSH keywords alone are not conflict evidence.

| Assumption surface | Recorded value | Authoritative source | Bounded scope | Result |
| --- | --- | --- | --- | --- |
| Artifact ownership/base | single_repo; this repository; develop | Parent invocation binding, current branch/base ancestry and workflow manifest | #1927 only; no competing exact-surface PR | Verified |
| Shared reviewer default | Shipped review.on_draft.runner remains claude; this authorized run selects Codex through existing local override | Committed manifest and explicit issue/prompt exclusion | #1927; no mutation of real local override | Verified |
| Optional routing activation | Template activates no DSH models; policy is opt-in | Approved spec BR1 and #1927 | Shared config/example and resolver surfaces only | Verified |
| DSH selection boundary | Child dispatch and frozen session allowlist; headless defaults remain separate | Primary runtime contract above and existing integration doc | Installed runtime/version and #1927 contract | Verified |

At implementation start, reread the current authoritative sources and record
Still valid. Changed/unverifiable ownership, base, shared default or runtime
capability is Stale or conflicting: stop before file edits and return the
specific evidence to the parent. No real portfolio/board scan is authorized.

## Layer-by-Layer Changes

### Technical Decisions

#### D1: Role policy and command surfaces

Implement the following canonical role/tier catalogue in the resolver; test its
parity with the canonical Agent Assignments table rather than parsing Markdown
at runtime. Cursor-specific role additions and aliases are not implicitly
accepted. Unknown role names produce D5's diagnostic.

| Role | Default tier |
| --- | --- |
| orchestrator | economy |
| item-orchestrator | balanced |
| automated-reviewer-loop | economy |
| product-manager | premium |
| spec-reviewer | balanced |
| tech-lead | premium |
| implementation-plan-reviewer | balanced |
| developer | balanced |
| code-reviewer | balanced |
| project-setup | balanced |
| smoke-tester | balanced |
| retrospective | balanced |

Add `model-route --runner dsh [--role ROLE] [--tier TIER] [--repo-root PATH]
[--json]`, requiring role or tier. With both present, the explicit tier replaces
only the default tier; a configured role entry still wins (spec BR4). A known
explicit tier without a configured route inherits unless a selected role entry
explicitly references that absent tier (spec BR3's dangling-reference error).

Add `model-routes --runner dsh [--repo-root PATH] [--json]` for allowlist setup.
Return effective configured routes reachable through canonical roles and direct
tier requests, with their resolution records; deduplicate route tuples while
retaining the contributing resolution records. Ignore inherited results when
forming the configured route list. Do not omit an otherwise unused configured
tier that an explicit tier request can select.

#### D2: Strict parser, envelope and legacy compatibility

Implement BR9 with Python standard-library code inside the existing resolver;
no PyYAML/ruamel import, optional fallback parser, package provisioning or network
call on this model-policy path. Existing review/auth readers and their separate
dependencies are not changed by this decision. `resolve_local_config` continues
to choose the same override-root, checkout and main-clone files.

Create one `load_model_policy` reading/validation path used by validate,
model-route and model-routes. Snapshot the selected raw shared/local pair once
per invocation. Parse each active envelope once; retain parsed policy, projected
legacy configuration and source positions in an immutable result. Reuse that
result for layer validation, composition, route listing and validate's context
checks. No command may rediscover activation, reparse model policy, reread a
selected file or hide reader exceptions as absence. Files are read once each;
this is not an atomic transaction across simultaneous edits in different files.

Activation is a deterministic first-line protocol, not a search for `dsh` in
YAML. Classify the exact reserved prefix in BR9a, including a BOM followed by
that prefix as an invalid envelope, then verify the version/opener and mandatory
end. Once reserved, malformed input cannot return to the inactive branch.
Misplaced markers in an unactivated file remain ordinary legacy text. Reject
extra reserved column-zero marker lines after the close and reject a root models
key in the parsed legacy projection. Policy `{}` variants follow BR9a.

The envelope grammar/escaping is exclusively spec BR9b–BR9d. Use a small lexer
tracking quote/comment state and a mapping stack tracking exact two-space
increments, per-mapping seen-key sets and source paths. Require complete scalar
and line consumption; reject dangling punctuation or unsupported tokens instead
of ignoring the suffix. Recognize numeric/null/boolean tokens as invalid typed
values, using BR9b's lexical forms; retain quote metadata so quoted identifiers
are strings. Unsupported constructs, including indentless/indented sequences,
are explicit rejection tokens; they do not close the models region. No general
YAML features or implicit coercions are implemented.

In an active file, replace envelope lines by blank lines for the legacy projection
so tail line positions remain stable. Factor a private raw-snapshot adapter from the legacy reader's default
`preserve_empty_values=False` preprocessing/mapping/scalar path, preserving the
existing public path-based API for its other consumers. Apply that dependency-free
adapter to the projection; translate failures into D5 errors. Do not call
preserve_empty_values=True: at the recorded revision that branch delegates to
parse_review_yaml and imports PyYAML. Do not use `parse_review_yaml` or `routing_declared` for activation or
policy parsing. For an unactivated file, contribute no model routes; validate
reuses the same legacy semantics/output/arguments from its raw snapshots,
without a DSH grammar pass; do not reread files to obtain context.
Bare unactivated models.dsh is deliberately inactive, even if YAML-like; this
compatibility/migration boundary must be prominent in operator examples.

The existing `set-local-path` writer is a separate mutation consumer: today
`set_local_product_repo_path` serializes the entire local mapping through
`dump_yaml_subset`, losing comment markers and silently deactivating policy.
For an activated checkout-local file, reuse the common envelope reader and
layer validation before any write; retain the opener, policy region and end
marker as their original bytes. Apply existing path normalization/update
semantics only to the parsed legacy projection, serialize only that tail, and
join it after the preserved envelope. Preserve its closing line separator;
never reserialize policy or duplicate a root models key. Malformed activated
input fails before writing and leaves the file byte-identical. Unactivated
files retain the current writer behavior; main-clone fallback remains read-only.
This change stays inside workflow-config-resolver.py and the existing permitted
resolver/DSH fixture tests. It does not make the three model-reading commands
mutating or authorize changes to any real private configuration in this run.

Validate each supplied policy layer against D1's names and route fields before
D3 composition, even if the other layer masks an invalid value. Nonblank strings
are required for present route fields; empty route mappings/partial fields can
contribute to a complete composed entry. Check effective completeness and
winning tier references after composition. BR9 format outcomes precede the
existing routing and host-dispatch decision matrix.

#### D3: Composition and precedence

Implement spec BR2–BR3 using pure recursive mapping composition: local values
replace equal keys; mapping/mapping values recurse; scalar/reference versus
mapping replacement is whole-entry. Retain enough layer contribution metadata
for D4. Do not mutate the parsed inputs or write either configuration file.
Completeness is checked after composition, so a local provider-only override
can inherit the shared model, while a provider-only effective route fails.
Empty local mappings contribute no route-field override; null/empty scalar
values are errors, not deletion instructions. Invalid winning policy never
falls through to lower-priority policy or inheritance.

#### D4: Successful output and provenance

Single-route shell output uses the existing shlex-quoted KEY=value printer.
JSON output carries equivalent uppercase fields: ROLE, TIER, PROVIDER, MODEL,
REASONING_EFFORT, SOURCE, SOURCE_FILE. Empty optional/unselected values are empty
strings; no secret-bearing unrelated configuration is emitted.

SOURCE is local-role/committed-role for a direct role route, local-tier/
committed-tier for a tier-derived route, or inherited. The selected entry's
highest contributing layer determines SOURCE_FILE; a partial local mapping
reports its local source even when another field is inherited. Empty mapping
contributions do not falsely claim a local override. Tier-reference role results
identify the tier route's contributing file and selected TIER; direct role
results have empty TIER. Inherited results have no route/file and identify the
selected/default tier. D1 listing emits these same resolution records and
configured route tuples as JSON, or deterministically indexed shell records.

#### D5: Failure and bounding

Model-schema/query failures exit 2 with a structured JSON diagnostic on stderr:
CODE, FILE, FIELD, MESSAGE. Use stable code classes for unknown role/tier,
invalid schema/type, incomplete route and dangling reference. The common
reader uses `invalid_envelope` for activation/delimiters/forbidden tail models,
`invalid_yaml` for unsupported grammar, duplicate keys, malformed UTF-8 in an
active file or active legacy-projection syntax failure, and `invalid_type` for
null/boolean/numeric or nonmapping policy values. Name/field/value errors retain
`unknown_name`, `unknown_field`, `invalid_value`; effective errors use
`incomplete_route` and `dangling_reference`. Query errors remain `unknown_role`
and `unknown_tier`. Syntax is checked before schema; shared-layer errors precede
local-layer errors, then composition, then query validation. All three commands
and the wrapper expose the identical first policy error object and exit 2.
There is no dependency_missing fallback on this dependency-free policy path. Do not print the entire configuration or
invalid raw values. No success route appears on an error path. Existing
unrelated legacy diagnostics remain unchanged.
Legacy parser exception text can contain source snippets.
The common active reader must replace that text with
a stable sanitized MESSAGE, retaining safe file/field/location evidence without
raw input. A malformed temporary fixture containing a private test sentinel
must fail without that sentinel appearing in stdout or stderr; legacy command
diagnostics remain unchanged.

Resolution is a finite local configuration walk bounded by the selected files
and D1 catalogue. It invokes no provider, network service, host provisioning or
child session. Existing local-file discovery uses filesystem inspection of the worktree
.git pointer (linked_worktree_main_root), without invoking git; model resolution
adds no external retry or polling loop.

#### D6: Validation consumer behavior and regression

Keep command dispatch for resolve/review commands separate from the new
validate model hook. The Composed Call Sites table defines the expectation at
actual consumers; tests exercise absent routing as well as valid/invalid opt-in
policy at those paths. No shared review schema, policy keys or output are
redefined by this feature.

#### D7: DSH dispatch and operator documentation

For a DSH driving session, resolve D1's target role before each fresh stage/review
child dispatch; parse the resolver's JSON result without eval. With SOURCE
inherited, pass no route. For a valid configured route, use the exposed child
selection capability and the session's captured exact-route policy; pass
provider/model together and effort only when configured. Record requested route,
SOURCE/file/tier and actual dispatch in the runner summary/review evidence.

Selection disabled or the exact pair denied by the session allowlist means a
visible inherited fallback: state the reason, retain requested-source evidence,
and omit all route fields. Do not retry arbitrary provider errors as inherited
success, confuse model-catalog absence with allowlist denial, or classify a
post-dispatch failure as missing policy. An unknown capability/policy state
requires explicit clarification through the existing runner failure/decision
path; do not silently invent permission. These instructions govern DSH child
dispatch only, not cross-runner headless default selection.

List documentation updates in Documentation Updates; the operator guidance
covers the verified runtime contract, UI path Plugins → Subagent → Model
selection, a profile overlay using the settings-owner id, exact-route
allowlist maintenance via D1 listing, and fresh-session requirements. Explain
headless default pinning through agent-default-model/profile or invocation
--patch overlay; routing policy does not choose a headless default. Examples
use block YAML accepted by D2; template/shared and local-example examples stay
fully commented. Executable snippets declare bash when launching Bash, otherwise
bash-zsh; run the existing diff-aware shell snippet lint on implementation.

### Decision-Gate Consistency Matrix

Classification: applicable; D3 precedence plus D7 host capability yield different
outcomes and next actions. Resolution ordering is governed only by D3/spec BR3;
this table maps resolved inputs to dispatch actions without redefining that
precedence. Mirrors are Protocol91, DSH integration and model-policy guidance;
commented config examples and the runbook demonstrate the same contract.

| Inputs at decision point | Allowed outcome | Required next action | Governing decision/example |
| --- | --- | --- | --- |
| Unknown/malformed input or invalid effective route | Configuration error | Show D5 diagnostic; correct before any routed child dispatch | D2/D5; dangling winning tier reference |
| Valid resolution, inherited source | Inherited dispatch | Pass no route; record source/tier and actual inheritance | D4/D7; no routing configured |
| Valid configured route and enabled/permitted session policy | Configured dispatch | Pass D7 fields and record actual dispatch | D7; distinct tier children |
| Valid route, selection disabled | Visible inherited fallback | State disabled reason, omit route fields, retain requested-source record | D7; runbook Step7 |
| Valid route, exact pair denied by session allowlist | Visible inherited fallback | State denied reason, omit route fields, retain requested-source record | D7; runbook Step7 |
| Capability/policy unknown or cannot be verified | Existing runner failure/decision path | Return specific evidence to parent; do not invent permission | D7; inaccessible policy |
| Child started and subsequently failed | Existing stage/review failure | Preserve route evidence; follow existing fix/escalation handling | D7; provider error is not a host-restriction fallback |

Resolution and dispatch are consecutive phases. Invalid policy blocks dispatch;
valid dispatch/fallback continues the existing stage; unknown evidence waits for
parent handling, and child failures use its existing failure/escalation path.
D2/D4 bind evidence to this invocation; an old resolution cannot prove a new
child's route. Empty/missing/unknown input handling is covered by D1/D2/D5.

### Composed Call Sites

The Amendment Verification Log's whole-scripts query enumerates reader/helper
and load_configs consumers, including external dynamic imports and direct tests.
The unrelated same-named parse_scalar in select-sync-manifest-entries.py is its
own implementation, not a consumer of this resolver; workflow-lib.sh's matching
key-presence comment is a contract reference, not a direct parser call. The table
below traces the real consumer population as well as the validation wrapper chain. Preserve
legacy repository-context semantics; common policy reading precedes context
validation/output for activated files. Model-schema failure is an additional
read-only rejection only for configured DSH routing. No side effect moves ahead
of a failed validation result.

| Consumer/site | Ordered path and expected observable outcome |
| --- | --- |
| validate-workflow-config.sh | CLI arguments → D2 common policy reader → resolver context checks/output; invalid opt-in routing exits nonzero, absent routing retains prior output/exit |
| workflow-lib.sh workflow_validate_repository_context | Wrapper → same validate command; preserve repo/require-local semantics, propagate D5 failure |
| post-merge-cleanup.sh selected_repo_context/repo_context calls | Wrapper validation precedes cleanup target use; invalid policy prevents proceeding on an unvalidated context; existing valid/absent policy follows its normal branch |
| component-release-target.sh validate calls | Context validation precedes release-target interpretation; new model failure propagates without claiming a valid target |
| Existing test-workflow-config-resolver.sh validate/wrapper tests | Wrapper success preserves absent-routing context; direct require-local failure at line583 remains a repository-context error, with D2 invalid opt-in policy rejected before successful validation |
| Existing test-workflow-hub-smoke-fixtures.sh validate calls | Lines255/258 preserve mobile/admin require-local success with absent policy; line313 preserves missing-checkout rejection. D2 invalid opted-in policy is rejected at the same validate entry before any successful context; run this existing suite unchanged |
| Ordinary resolve | cmd_resolve → resolve_context → load_configs → default parse_yaml_subset; original context/release/path semantics and errors remain, without model-schema validation or projection |
| mode | cmd_mode → load_configs → default reader → mode_from_shared; same mode/output and inline-list acceptance in unrelated legacy data |
| auth | cmd_auth → resolve_auth_context → load_configs → default reader; same auth hints/precedence/errors, no strict DSH import or validation |
| list-product-repos | cmd_list_product_repos → load_configs → default reader → product_repos; same workflow_hub requirement, list output and errors |
| set-local-path | cmd_set_local_path → load_configs for selection, then set_local_product_repo_path on checkout-local file only. Unactivated writer stays unchanged; activated writer uses D2 envelope/layer validation, preserves raw envelope/policy bytes and serializes only the updated legacy tail. Prove route and marker survival, malformed-input no-write and main-clone ownership in temporary fixtures |
| Legacy review-overrides | cmd_review_overrides → resolve_review_overrides → resolve_local_review_config → default reader; checkout without review still falls through to main-clone reviewer overrides; unchanged outputs, override origin and fallback rules |
| review-effective/review-github-effective | Respective cmd/resolve_review functions → preserve_empty_values=True → parse_review_yaml, including selected/shared/main-clone reads; strict review errors and existing library dependency remain. The new raw adapter is not inserted into these branches |
| Legacy parser helpers | Default parse_yaml_subset → preprocess_yaml → parse_mapping/parse_list → parse_scalar (and recursive calls); extracted snapshot adapter preserves all existing whitespace/comment/inline-list/coercion behavior. BR9 collection/type restrictions occur only in the separate policy parser, never these legacy helpers |
| run-bounded-prelude.sh guardrails reader | Dynamic resolver import → default parse_yaml_subset → guardrails snapshot; preserve present/default guardrails and unreadable exit 2. The adapter must not convert unrelated inline lists into unreadable policy. Regression is fixture-only, never a real run-item/run-work invocation |
| run-work-router.sh guardrails reader | Dynamic import → default reader → section/mode/backlog-start output; preserve present/delegated data and conservative fallback on genuine legacy failure. Do not run against the real board for this item |
| validate-workflow-hub-skeletons.py validate_skeleton_manifest | Imported resolver default reader → skeleton_role/entries validation; keep list manifests accepted, required-file checks and validation errors unchanged |
| workflow-merge-budget.py config/reserve | Dynamic module.load_configs → default shared/local reader → reserve selection; preserve layer/override precedence and Stop on owning configuration unreadable; no merge/budget admission is executed by parser regressions |
| workflow-portfolio-scan.py configuration | resolver.parse_yaml_subset(..., preserve_empty_values=True) → existing strict reader → tracker/portfolio reserve config; retain its dependency, precedence and ReadError behavior. Scope is direct fixture parsing, no live portfolio scan |
| test-workflow-config-resolver.sh direct parser assertions | Default parse_yaml_subset at line775 and default parse_scalar/inline-list/control-value assertions retain legacy results; preserve_empty_values=True and review_effective=True assertions keep the strict-reader behavior. This population is separate from the suite's validate/wrapper consumers |
| test-review-effective-yaml-parser.sh direct parser assertions | Strict parse_yaml_subset(..., preserve_empty_values=True) → parse_review_yaml; YAML quoting/line-break/error expectations and its existing dependency remain unchanged |


No deleted branch's inputs need reassignment: this is additive validation.

### Parser-Risk Edge Cases and Unit Mapping

Applicable: a custom structured-text lexer/parser changes tooling-path behavior.
The following matrix is indicative test organization, not a Binding enumeration.
Every semantic input class must be covered; equivalent consolidation is allowed.
Implement the parametrized cases in test_workflow_dsh_model_routing.py and expose
them through test-dsh-model-routing.sh. For each active malformed case, invoke
validate, model-route, model-routes and the validation wrapper against the same
fixture pair; assert D5's expected CODE/FILE/FIELD/MESSAGE, exit 2, empty stdout
and identical diagnostics. Equality alone is insufficient: common inheritance
or common acceptance of invalid input fails the test.

| Input class / concrete example | Expected proof |
| --- | --- |
| Missing files; unactivated legacy; misplaced marker; bare models.dsh without opener | Inherited routes; validate retains original context/output/errors; no YAML import, including python -S |
| Exact opener/end; models: {}, dsh: {}, tiers/roles empty | Active valid empties; composition/provenance follow D3/D4 |
| Unknown version, malformed reserved opener, BOM before opener, missing/repeated end, second envelope, tail models | invalid_envelope at common reader; never recover as absence |
| Block mappings, exact indentation, LF/CRLF, comments, quoted hash/operator literals | Accepted boundaries; no false anchor/alias or comment interpretation |
| Single-quote doubling, double-quote/backslash escapes; unsupported escape, unmatched quote, tabs, indentation jump | Accepted escapes decoded as BR9c; unsupported cases invalid_yaml |
| models: dsh: {}; anchor adjacent to flow mapping | Historical malformed inline/metadata forms reject as invalid_yaml |
| Indented models sequence; models with newline then - dsh: {} at column zero | Both list forms invalid_yaml, never inherited |
| models list item other: {} followed by dsh: null; direct dsh: null | List form invalid_yaml; direct null invalid_type; same error across commands |
| Flow sequence/mapping without close, dangling final item, trailing comma, nonempty flow, even if valid general YAML | invalid_yaml by subset, including historical models: [{dsh: {}} |
| Block/multiline scalars, tags/directives/document markers, anchors/aliases/merge keys, duplicate keys | invalid_yaml; quoted operator strings remain accepted |
| Boolean/numeric/null tokens versus quoted versions; wrong scalar in mapping position | invalid_type for wrong source types; quoted ids remain strings subject to schema |
| Unknown role/tier/key, blank id, incomplete effective route, dangling winning reference | Corresponding D5 schema/effective error; invalid lower layer cannot be masked |
| Partial fields, deep merge, mapping/reference replacement, empty local overrides | Existing BR2–BR5 coverage retained; no hybrid/provenance regression |
| Discovery override-root/checkout/main-clone, unrelated nested dsh text | Existing discovery unchanged; only envelope controls activation |
| set-local-path on activated local policy plus product_repos tail; malformed active policy; unactivated control | All three commands retain the same effective route after the path update; envelope/policy bytes unchanged, only checkout tail updated; invalid active input leaves bytes unchanged; old unactivated behavior preserved |
| Synthetic private sentinel and control/newline attempts | Redacted common error, no injected output lines or raw source leakage |
| Instrumented common reader in each command; multi-route listing | One snapshot/read and one policy parse per active layer; no separate detector |

Add bounded generative lexer tests for quote/comment/indentation/delimiter
combinations under BR9, with a deterministic seed. Check accepted ASTs and
expected rejected classes, not only command agreement. Existing resolver, hub,
Step7a and no-routing tests remain; update only fixtures asserting the superseded
bare-policy activation contract. Keep historical blocking shapes as regression
coverage, placing each inside an activated envelope. Add unactivated counterparts
to prove the deliberate compatibility boundary. No fresh real local files or
provider calls are used in these parser tests.

Suppression semantics: not applicable; no syntax suppressions are supported.
The fixed grammar is the operator contract, not a claimed sample of all YAML.
Historical rejection cases motivate coverage; they are not its completeness proof.
Concurrency classification: Not applicable; finite synchronous reads/pure
composition introduce no concurrent event sources or shared mutable cache.
Cross-cutting checklist classification: Not applicable; D7 adds a runner-specific
routing contract, not a new safety/quality checklist for independent features.

## Testing Strategy

Use unit/config-CLI integration, documentation consistency, existing workflow
regression and actual DSH smoke. Extend the diff-selected shell harness with
covers headers for resolver, validator, routing docs/examples and its Python
unit file; do not add a new CI job or provider-dependent CI test.

- AC1–AC5: D1–D5 unit/CLI tests cover all precedence sources, direct/reference
  forms, partial overrides, provenance, errors, read-only outputs and listing.
- AC6–AC8: Assert the dispatch documentation's resolve/pass/record/fallback,
  headless boundary and commented examples; role catalogue parity references the
  canonical table. Existing Step7a consistency suite must remain green; update
  its assertions only where parsed prose intentionally changes.
- AC9: Execute the linked runbook with existing real routes. A mocked subagent
  adapter can supplement unit coverage but cannot establish live DSH acceptance.
- AC10: Run sync coverage and fragment validation, plus the diff-selected suites
  and consumer fixtures with no routing configured.

**Coverage intent/proportionality**: parser cases target actual introduced schema
and composition failure classes, not a custom parser for prose-only documents.
Reuse fixture helpers and table-driven tests; enumeration is indicative. Gate B
self-check is satisfied by keeping tests limited to the production resolver and
contract surfaces this change owns.

**Planted-violation proof**: in a temporary fixture, identify the exact file/line
holding an invalid model route; demonstrate validate fails, correct that route,
and demonstrate pass. For a new/materially changed documentation assertion,
plant an omitted dispatch/evidence requirement in its temporary source fixture,
show its check fails, restore it and show pass. Record concrete evidence on the
implementation PR, rather than trusting a declared control.

**Residual verification**: implementation reruns the Verification Log surface
searches, diff-based suite selection and role-catalogue parity; report changed
files against the approved Files to Modify list and any uncovered residue.
A genuinely required additional file or broader architecture is a parent scope
decision before editing, not an automatic sweep.

## Seed Data

No application/database seed changes. Python tests create deterministic temporary
shared/local YAML fixtures for every edge-case class above; shell integration
creates temporary Git checkouts/worktrees for local-discovery behavior. Live
smoke uses a temporary workspace and host overlay; operator-existing permitted
routes supply the provider/model identifiers. No real machine-local YAML/env
file is modified, and no credentials are emitted or stored in fixtures.

## Documentation Updates

The developer executes these updates under D7:

- `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` — DSH stage/review dispatch and summary contract.
- `docs/workflow/development-workflow/integrations/dsh.md` — layered routing, resolver/listing, host setup and headless boundary.
- `docs/workflow/development-workflow/agent-model-config.md` — DSH tier/role routing parity, precedence and later-runner deferral.
- `docs/testing/workflow/dsh-model-routing.smoke-test.md` — actual smoke evidence and version; runbook created by this plan PR.
- `.ai-dev-workflow.yaml` and `.ai-dev-workflow.local.example.yaml` — fully commented DSH block examples.

`AGENTS.md`, `REVIEW.md`, project placeholder docs and best practices need no
new policy for this runner-specific contract. No new DSH agent tree, separate
dispatch-profile document, skill model pins or static preset bundle is planned.

## Files to Modify

Implementation is bounded to the following paths; this plan PR contains only
this plan and the smoke runbook. The spec amendment is a separate spec-stage
PR; these document amendments are explicitly authorized outside the implementation
allowlist. No runtime/config/test edit is made by either amendment PR.

| Path | Work / decision | AC coverage |
| --- | --- | --- |
| scripts/development-workflow/workflow-config-resolver.py | D1–D6 commands/schema/composition/provenance and dedicated validate hook | AC1–AC5 |
| scripts/development-workflow/validate-workflow-config.sh | Help/contract clarification if required for the existing validation wrapper; preserve arguments | AC5 |
| scripts/development-workflow/tests/test-dsh-model-routing.sh | New fixture/CLI/docs test harness with explicit covers headers | AC1–AC8, AC10 |
| scripts/development-workflow/tests/test_workflow_dsh_model_routing.py | New table-driven unit tests for the edge-case mapping | AC1–AC5 |
| scripts/development-workflow/tests/test-workflow-config-resolver.sh | Add opted-in/absent validation integration assertions using its existing fixture pattern | AC1, AC5 |
| scripts/development-workflow/tests/test-step7a-surface-consistency.sh | Preserve or update intentionally affected parsed dispatch prose | AC6 |
| docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md | D7 | AC6 |
| docs/workflow/development-workflow/integrations/dsh.md | D7 | AC6–AC8 |
| docs/workflow/development-workflow/agent-model-config.md | D1 parity and D7 | AC8 |
| .ai-dev-workflow.yaml | D7, commented example only | AC1, AC8 |
| .ai-dev-workflow.local.example.yaml | D7, commented example only | AC8 |
| docs/testing/workflow/dsh-model-routing.smoke-test.md | Complete runbook/evidence | AC9 |
| sync-manifest.yaml | Add explicit hub-only smoke entry; existing tooling/docs globs cover other files | AC10 |
| changelog.d/1927.added.dsh-model-routing.md | Feature release note in required bold-title format | AC10 |

### Scope boundary of this amendment

The implementation Files to Modify table remains the original 14-path allowlist.
The custom parser fits inside workflow-config-resolver.py; no new parser module,
vendored library, requirements/bootstrap or CI file is approved. The amended
smoke runbook is already one of those paths. Changes to the two spec/plan files
are separately authorized documentation-stage work, not an implementation scope
expansion. If implementation proves another file is required, stop before editing
and ask Luis; do not silently add it. Shared/local example edits remain comments
only, showing the activation/envelope without enabling template routes.

## Risks & Mitigations

### Reversal procedure

If the published feature requires reversal, prepare a normal reviewed PR that
reverts its coherent implementation changes: resolver CLI/schema/output and
the D2/D6 validation hook, matching tests, D7 dispatch/operator documentation,
commented examples and sync ownership. Restore the pre-feature standalone
validation contract together with the prior session-inherited DSH dispatch;
do not remove validation alone while leaving documentation promising routing.
Run the config-resolver, hub-smoke-fixtures, Step7a and sync-manifest suites to
prove the restored behavior, then complete ordinary review/CI before merge.
Consumers that received the feature use a reviewed follow-up sync PR to the
approved reverted template snapshot. Do not rewrite history, delete retained
branches or alter real machine-local YAML/env during reversal. Existing local
routing keys cease selecting child routes after this coherent reversal; record
that effect explicitly. Release-note handling follows the normal release
protocol for the actual published state.

| Risk | Likelihood / impact | Mitigation |
| --- | --- | --- |
| Partial override or reference replacement gives incorrect provenance | Medium / medium | D3–D4 unit matrix; no last-minute alternative merge semantics |
| Strict routing validation changes absent-policy consumers | Medium / medium | D2 compatibility boundary and D6 composed-call regression |
| DSH session retains old allowlist after operator edit | Medium / medium | Verified runtime contract; fresh session in smoke |
| Host is installed but permitted routes fail | Medium / medium | Show actual error; stop smoke/dispatch under normal failure path, never claim mocked parity |
| Consumer sync misses the runbook or unit dependency | Low / medium | Manifest ownership plus coverage test and covers headers |

## Implementation Order

1. Verify the approved spec dependency above and operational assumptions Still valid; inspect current implementation
   baseline and preserve original restrictions. This discharges the assumption
   check before any implementation edits.
2. Implement D1–D5 with the Python edge cases. Complete and verify a coherent
   resolver/test checkpoint commit before moving to integration.
3. Wire D2/D6 validation and CLI fixtures. Run config-resolver, existing hub-smoke-fixtures and new DSH tests;
   produce the model-schema planted-violation proof before committing this part.
4. Execute D7's Documentation Updates and consistency coverage. Produce any new
   documentation-control planted proof, run Step7a consistency and the existing
   workflow shell-snippet linter against origin/develop; commit the verified part.
5. Add sync ownership and the release fragment; run sync coverage and fragment
   validation. Fragment body follows `- **DSH per-role model routing** (#1927):`
   followed by the user-visible routing behavior, never a commit-message literal.
6. Run the smoke runbook in fixtures and one real DSH session; capture actual
   child route/source evidence with existing permitted providers. Correct only
   in-scope deterministic defects; missing provider capability/working routes is
   an explicit blocker requiring parent handling, not false passing evidence.
7. Run diff-selected regression suites, residual verification and consumer
   compatibility checks; git diff --check. Commit smoke/evidence updates only
   after their assertions pass. Leave all real local configuration untouched.
8. Push once after each completed review-fix cycle, with explicit branch refspec
   and remote SHA verification. Follow Protocol91 internal review, external loop,
   regression label, CI, full readiness, audit and tracker checks at the current
   head; parent owns durable merge admission and any authorized merge.

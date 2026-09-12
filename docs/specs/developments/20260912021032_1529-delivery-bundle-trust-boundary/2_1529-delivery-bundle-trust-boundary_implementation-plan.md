# Delivery-Bundle Evidence Trust Boundary Audit — Implementation Plan

**Work item brief**: [#1529](https://github.com/lhpaul/ai-dev-framework-template/issues/1529) (Refactor item — no spec; the tracker brief is the requirements source)
**Smoke test runbook**: [`1529-delivery-bundle-trust-boundary.smoke-test.md`](../../../testing/workflow/1529-delivery-bundle-trust-boundary.smoke-test.md)

---

## Step 0: Template-Fit Check

**Detection**: `.ai-dev-workflow.yaml` sets `template.is_template: true` (line 238), so this
check is mandatory.

**Evaluation**: **PASS — generic.** The work changes this template's own workflow tooling:
five Bash/embedded-Python helpers under `scripts/development-workflow/`, their test suites,
and the workflow documentation that describes them. It references no downstream language,
runtime, or framework (no React, Rails, Django, Go, Vue, Spring Boot, Laravel). Its
acceptance criteria are expressed in framework-agnostic terms — an evidence record contract
and the validation duties of its consumers — and every downstream project that adopts
`workflow_hub` mode inherits the hardened helpers regardless of its stack.

**Action**: continue to Step 1. No human confirmation required.

---

## Summary

**Approach**: Replace consumer-by-consumer patching with an explicit, documented trust
boundary. First, enumerate every field `component-release-evidence.sh` emits and classify it
into one of six trust classes (`producer_required`, `producer_required_nullable`,
`producer_conditional`, `hub_input`, `hub_input_identifier`, `attestation`). Second, publish that classification plus
a field x consumer matrix as a new contract document. Third, close every cell where a consumer
accepts a caller-supplied value without require-and-match, or treats an absent field as a
match — including the known `component_version` gap — by binding the value at the producer (the
single choke point) and enforcing require-and-match at each consumer. Fourth, add regression
tests that assert rejection for each fabricated-value case, each confirmed red before its fix.

**Estimated complexity**: **M** (1-3 days).

**Rationale**: The change set is five runtime helpers, five test suites plus two fixture
helpers, one new contract document, and six existing documents. No new subsystem, no new data format, no schema-version bump
(`component_release_evidence.v1` gains one optional-to-emit field and tighter emission
preconditions; every currently valid record stays valid except ones the audit deliberately
rejects). The cost is in breadth and in the "confirm red before green" discipline of AC-4,
not in algorithmic difficulty.

**Dependencies**: None. This tooling is dormant in this repository (`WORKFLOW_MODE` resolves
to `single_repo`; no `workflow_hub` block is configured), so no item must merge first and no
release is gated on this.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `c367abf0` |
| Producer emitted-field enumeration | `sed -n '208,224p' scripts/development-workflow/component-release-evidence.sh \| grep -cE '^\s+[a-z_]+:'` | `15` top-level fields: `schema_version`, `target_binding`, `routing_outcome`, `selected_product_repo_key`, `canonical_repository_identity`, `artifact_owners`, `release_correlation_key`, `contract_revision`, `release_branch`, `release_outcome`, `ci_outcome`, `deployment_outcome`, `cleanup_outcome`, `hub_tracker_ref`, `component_tag` |
| `component_version` is absent from the producer | `grep -n "component_version" scripts/development-workflow/component-release-evidence.sh` | No matches — confirms the brief's "known-unaddressed instance" |
| Consumer evidence reads | `grep -oE 'evidence\.get\("[a-z_]+"\|stable_value\(evidence, "[a-z_]+"' scripts/development-workflow/delivery-bundle-manifest.sh scripts/development-workflow/component-milestone-reconciliation.sh \| sort -u` | Bundle names 13 distinct evidence fields, reconciliation 12 — in both cases 2 of them (`schema_version`, `target_binding`) are structural rather than content fields, leaving 11 and 10. Reconciliation additionally requires 4 identity fields through the `required_identity` loop at lines 300-307, which reads them via `stable_value(evidence, field)` and so is not itemized by the literal-string grep |
| Cleanup evidence reads | `grep -nE 'json_field "\$EVIDENCE_FILE"\|compare_component_field' scripts/development-workflow/prepare-release-post-merge-cleanup.sh` | Reads `schema_version`, `release_branch`, `cleanup_outcome`; compares 6 identity fields against a freshly resolved target binding |
| Caller-supplied overrides on the bundle | `grep -n 'update.add_argument' scripts/development-workflow/delivery-bundle-manifest.sh` | 9 flags; `--component-version` is `default=None` and never cross-checked |
| Caller-supplied overrides on reconciliation | `grep -n 'parser.add_argument' scripts/development-workflow/component-milestone-reconciliation.sh` | 14 lines: 10 in `add_component_common` (lines 730-741, the component subcommands this plan changes) and 4 in `add_parent_common` (lines 745-748). `--version` is consumed only on the `single_repo` path, `--evidence-file` is ignored there |
| All invocation sites of the producer | `grep -rl "component-release-evidence.sh" . --exclude-dir=.git` | 17 paths at `c367abf0` (19 on this plan branch, which adds the plan and the runbook). 8 are runtime/doc surfaces this plan updates: `component-release-evidence.sh`, `delivery-bundle-manifest.sh`, `component-milestone-reconciliation.sh`, `tests/test-component-release-evidence.sh`, `cross-repo-pr-flow.md`, `repository-modes.md`, `05-prepare-release-protocol.md`, `scripts/development-workflow/README.md`. The other 9 are `CHANGELOG.md`, 3 historical specs, 2 historical runbooks, `05b-graduate-development-protocol.md` and `94-batch-merge-protocol.md` (name-only references), and `tests/test-workflow-hub-docs.sh` (asserts on the docs, not on the helper's flags) — all excluded with rationale in Files to Modify |
| Agent/skill surfaces naming these helpers | `grep -rn "component-release-evidence\|component_release_evidence\|component-milestone-reconciliation\|delivery-bundle-manifest" .agents/ .codex/ .claude/ .cursor/` | 2 hits, both in `.agents/skills/prepare-release/SKILL.md`; no `.codex/`, `.claude/`, or `.cursor/` surface names these helpers |
| Test-suite auto-selection | `sed -n '1,32p' scripts/development-workflow/select-test-suites.sh` | A suite named `test-<name>.sh` covers `scripts/development-workflow/<name>.sh` by naming convention, so extending existing suites needs no CI wiring |
| Cleanup suite coverage declaration | `grep -n 'covers:' scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh` | Declares `prepare-release-post-merge-cleanup.sh`, `component-release-target.sh`, `workflow-config-resolver.py` |
| Docs consistency suite | `sed -n '1,12p' scripts/development-workflow/tests/test-workflow-hub-docs.sh` | `covers:` the six workflow-hub docs plus `scripts/development-workflow/README.md` and `05-prepare-release-protocol.md` |
| Residual-gate classification | `./scripts/development-workflow/scope-residual-gate.sh classify --issue-title "<#1529 title>" --issue-body-file <body>` | `RESULT=requires_verification SCOPE_CLASSIFICATION=numeric_sweep TARGET_COUNT=4` |
| `hub_tracker_ref` value shapes in the repository | `grep -rn "hub_tracker_ref\|hub-tracker-ref" --include="*.md" --include="*.sh" . \| grep -v '^./docs/specs'` | Three mutually incompatible shapes in use: `#1356`, `fixture:1356`, and the documented placeholder `<tracker-item-or-epic>` |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Repository mode of this repository (decides whether these helpers are live here) | `single_repo` — no `mode:` key is present in `.ai-dev-workflow.yaml`, and `component-release-target.sh` defaults to `single_repo` when the resolver reports none | `.ai-dev-workflow.yaml` (no `mode:` key) and `scripts/development-workflow/component-release-target.sh` line 159 (`.WORKFLOW_MODE // "single_repo"`) | 2026-09-12, repo revision `c367abf0` | Current invocation items 1462, 1496, 1515, 1529, 1561, 1583; same-surface open PR evidence: none (0 open PRs in the repository at dispatch) | `Verified` |
| Plan artifact base branch | `develop` | Parent orchestrator handoff (`APPROVED_BASE=develop`) and `AGENTS.md` "Git & Branching" | 2026-09-12, repo revision `c367abf0` | Same bounded item list; no open PR changes the artifact base | `Verified` |
| Artifact owner for this plan | This repository (`single_repo`; hub/product routing not configured) | `WORKFLOW_MODE=single_repo` in the parent handoff plus the absent `mode:` key above | 2026-09-12, repo revision `c367abf0` | Same bounded item list | `Verified` |

**Bounded cross-check reasoning**: of the five sibling items in this invocation, #1583
(`tracker: Type=Workflow destroys routing classification in the template repo itself`) is the
only one sharing vocabulary with this plan ("routing", "classification"). It concerns the
GitHub Projects **Type** field used for work-item classification — a tracker surface. This
plan concerns `routing_outcome` in `component_release_target.v1` / `component_release_evidence.v1`
— a release-target surface. Different operational assumption surfaces; a shared keyword alone
is not conflict evidence, so this is **not** classified as a conflict. Items 1462, 1496, 1515,
and 1561 touch Cursor dispatch profiles, Protocol 02 authoring rigor, escalation
classification, and reviewer preflight respectively — none touches repository mode, the
approved base, artifact ownership, or the component release contract.

**Implementation-start recheck**: before the first file edit, the implementation agent must
re-read `.ai-dev-workflow.yaml` for a `mode:` key. If one has appeared, or if a
`workflow_hub` block has been configured, stop before edits and return the evidence to the
parent orchestrator (`Stale or conflicting`) — the "dormant here, cannot misfire" risk
framing that justifies landing behavior-tightening changes without a migration window would
no longer hold.

---

## Trust Model

### Trust classes

Every field that reaches a consumer belongs to exactly one class, and the class alone
determines the consumer's duty: no field is an exception to the class it carries. That is what
lets a future consumer tell required from optional without reading the producer (AC-5).

| Class | Definition | Consumer duty |
| --- | --- | --- |
| `producer_required` | `component-release-evidence.sh` always emits the field with a non-empty value, and refuses to emit a record at all when it cannot. The value is never `null` and never `""`; a field that may legitimately be `null` is `producer_required_nullable` instead, never this class | Require non-empty. Where the caller can also supply the same fact, **require-and-match**. Never infer from absence. |
| `producer_required_nullable` | The producer always emits the **key** and still refuses to emit a record when it cannot resolve the field, but the value is legitimately JSON `null` in exactly one defined case: `single_repo_release` routing, where `component-release-target.sh` emits the key empty (line 257) and renders it as `null` (line 105). `selected_product_repo_key` is the only member. D4 guards **both** directions of the relationship, not only one: under `component_release_routed` routing the value must be non-empty (emission refused otherwise), and under `single_repo_release` routing the value must be `null` (emission refused when it is non-empty) — so `null` and `single_repo_release` routing imply each other in both directions, not merely by convention | Require the key to be **present**, and accept only a non-empty string or JSON `null`; an absent key or `""` is a rejection. Treat `null` as **not bound**: never match it against a caller-supplied value and never read agreement into it. A consumer must first require `routing_outcome == component_release_routed`, after which the duty is identical to `producer_required` — require non-empty, and **require-and-match** where the caller can also supply the fact. |
| `producer_conditional` | The producer emits the field only when the corresponding flag was supplied; otherwise it emits `null` | A consumer that accepts a caller override must **reject when the evidence does not bind the field** (`*_unbound`), then match (`*_mismatch`). "Check only if present" is forbidden. |
| `hub_input` | A hub-owned fact expressed as a **closed-enum outcome value** that the product release producer cannot know, supplied by the hub caller at consumption time. Its only members are `hub_tracker_reconciliation_outcome` and `child_release_state` — the closed-enum subset of hub-supplied facts | Require the flag: the caller must supply it, or — in the one documented case, described in the note preceding the Trust matrix table below, where a consumer defines its own explicit "not yet known" default for an omitted flag, and that default is itself a member of the closed enum and never satisfies that consumer's own completion gate — accept that default in its place. Either way, validate the resulting value against the closed enum and fail closed on any unknown value, and **never** fall back to the evidence file for it. |
| `hub_input_identifier` | A hub-owned **identifier** — a component key, tracker issue number, source PR reference, or release PR reference — that the product release producer cannot know, supplied by the hub caller at consumption time. Its members are `component_key`, `child_item`, `source_pr`, `release_pr`, and reconciliation's `--issue`. Unlike `hub_input`, its values are open-ended (repository keys, PR/issue numbers), not drawn from a fixed vocabulary, so no closed-enum validation applies to this class | Require the caller to supply the value; **never** source it from the evidence file. Apply whatever narrower per-field duty the trust matrix cell states: require-and-match against a specific, separately classified evidence field where the cell says so (e.g., `component_key` against `selected_product_repo_key`), or record it for audit without gating on it where the cell says `record`. No charset or shape validation applies unless a specific matrix cell states one — this class is a required, unvalidated-format identifier, not a closed enum. |
| `attestation` | A self-declared reference string in an assurance summary; the referenced artifact is not loaded | Shape-check only where this codebase already establishes an objective format. Record the class in output so no downstream reader mistakes it for verification. |

### Producer emitted-field contract

Target state after this work (`component_release_evidence.v1`, 16 top-level fields):

| Field | Class | Emission rule |
| --- | --- | --- |
| `schema_version` | `producer_required` | Constant `component_release_evidence.v1` |
| `target_binding` | `producer_required` | Whole `component_release_target.v1` object, verified `mutation_allowed: true` |
| `routing_outcome` | `producer_required` | Copied from the target binding after `compare_field` agreement; **new**: emission refused when empty (D4) |
| `selected_product_repo_key` | `producer_required_nullable` | Copied from the target; the key is always emitted, and the value is legitimately `null` for `single_repo_release` routing. **New**: emission refused when `routing_outcome` is `component_release_routed` and the value is empty, **and** emission refused when `routing_outcome` is `single_repo_release` and the value is non-empty — both directions of the `null` ⇔ `single_repo_release` relationship are enforced (D4) |
| `canonical_repository_identity` | `producer_required` | Copied from the target; **new**: emission refused when empty |
| `artifact_owners` | `producer_required` | Copied from the target after `compare_field` agreement; **new**: emission refused when any of its six sub-fields (`release`, `ci`, `github_release`, `deployment`, `cleanup`, `tracker`) is empty (D4) |
| `release_correlation_key` | `producer_required` | Copied from the target; **new**: emission refused when empty |
| `contract_revision` | `producer_required` | Copied from the target; **new**: emission refused when empty |
| `release_branch` | `producer_required` | `--release-branch`, validated by `git check-ref-format` and against `release_branch_pattern` |
| `release_outcome` | `producer_required` | `--release-outcome`, enum `pending\|completed\|failed\|blocked` |
| `ci_outcome` | `producer_required` | `--ci-outcome`, enum `pending\|passed\|failed\|not_applicable` |
| `deployment_outcome` | `producer_required` | `--deployment-outcome`, enum `pending\|recorded\|failed\|not_applicable` |
| `cleanup_outcome` | `producer_required` | `--cleanup-outcome`, enum `not_started\|partial\|complete\|blocked` |
| `hub_tracker_ref` | `producer_required` | `--hub-tracker-ref`, non-empty free-form string, **semantics undefined** (see RESIDUAL-1) |
| `component_tag` | `producer_conditional` | `--component-tag` when supplied, else `null`; **new**: charset-validated |
| `component_version` | `producer_conditional` | **New field.** `--component-version` when supplied, else `null`; charset-validated |

Fields the producer **never** emits, and which therefore may never be sourced from an
evidence file: `evidence_state`, `hub_tracker_reconciliation_outcome`, `child_release_state`,
`component_key`, `child_item`, `source_pr`, `release_pr`.

### Trust matrix — field x consumer

Legend: `req+match` = caller override accepted, evidence must bind it and must match ·
`require` = required non-empty from evidence, no caller override · `record` = stored for
audit, not gated · `compare` = compared against an independently resolved target binding ·
`n/a` = not consumed · `GAP-n` = defect closed by this plan.

`selected_product_repo_key` is the only `producer_required_nullable` field, and every consumer
below reaches it only after requiring `routing_outcome == component_release_routed`: the bundle
already requires it, GAP-4 adds it to reconciliation, cleanup requires the independently
resolved target to be routed, and the assurance harness never loads an evidence file. The
`null` case is therefore unreachable in every cell of that row, and the `req+match` / `compare`
duties below apply to a non-empty value.

`hub_tracker_reconciliation_outcome` carries the `hub_input` closed-enum duty at every consumer
that reads it, but its two consumers enforce that duty differently, and that difference is a
deliberate, narrow exception rather than a contradiction. `component-milestone-reconciliation.sh`'s
hub path has no default and blocks outright on an absent `--hub-tracker-reconciliation-outcome`
flag (GAP-5, D5) — the flag is unconditionally required there. `delivery-bundle-manifest.sh
update-component`, by contrast, tolerates an omitted `--hub-tracker-reconciliation-outcome` flag
via a documented `default="pending"` (line 591), pinned by
`tests/test-delivery-bundle-manifest.sh`'s `hub_reconciliation_defaults_pending` assertion. This
does not contradict "require the flag": `pending` is itself a member of the closed enum the
field's readers gate on, not a bypass of the enum, and `blocker_for_component`'s completion check
(`hub not in ("complete", "deferred")` blocks; `hub == "pending"` returns
`pending_component_outcome`, never `verified`) means an omitted flag on the bundle path can never
be read as complete — it degrades the component to a pending, still-blocked state instead. The
default is scoped to this one consumer, whose own component record already tracks incremental
in-progress state before hub reconciliation completes; it grants no license for
`component-milestone-reconciliation.sh`'s hub path, or for `child_release_state` (which the bundle
already declares `required=True` with no default), to treat an absent flag as anything but a hard
failure.

| Field | Class | `delivery-bundle-manifest.sh` | `component-milestone-reconciliation.sh` | `multi-repo-release-assurance.sh` | `prepare-release-post-merge-cleanup.sh` |
| --- | --- | --- | --- | --- | --- |
| `schema_version` | `producer_required` | `require` (exact match) | `require` (exact match) | `attestation` string only | `require` (exact match) |
| `target_binding` | `producer_required` | fallback source for `stable_value` | fallback source for `stable_value` | `n/a` | `compare` (6 sub-fields) |
| `routing_outcome` | `producer_required` | `require` == `component_release_routed` | **GAP-4** not checked -> `require` == `component_release_routed` on the hub path | `n/a` | target must be `component_release_routed`; `compare`; **GAP-8** add non-empty precondition on the evidence value before comparing |
| `selected_product_repo_key` | `producer_required_nullable` | `req+match` vs `--component-key` | `req+match` vs `--product-repo` | `attestation` shape check | `compare`; **GAP-8** require the key present and non-empty before comparing (the `null` case is unreachable here — cleanup already requires `component_release_routed`) |
| `canonical_repository_identity` | `producer_required` | `require` | `require` | `attestation` shape check | `compare`; **GAP-8** add non-empty precondition |
| `artifact_owners` | `producer_required` | `n/a` | `n/a` | `n/a` | `compare`; **GAP-8** add a non-empty precondition on each of the six sub-fields before comparing |
| `release_correlation_key` | `producer_required` | `require` + cross-update stability | `require` | `attestation` (`release_contract`, `sha256:` prefix) | `compare`; **GAP-8** add non-empty precondition |
| `contract_revision` | `producer_required` | `require` + cross-update stability | `require` | `n/a` | `compare`; **GAP-8** add non-empty precondition |
| `release_branch` | `producer_required` | **GAP-9** not stored -> `record` | `n/a` | `n/a` | `req+match` vs the positional `<version\|release-branch>`; **GAP-13** empty/missing `evidence.release_branch` skips the match -> require non-empty first |
| `release_outcome` | `producer_required` | `require` == `completed` | `require` == `completed` | `n/a` | `n/a` |
| `ci_outcome` | `producer_required` | `require` in `passed\|not_applicable\|skipped` | `require` in `passed\|skipped\|not_applicable` | `n/a` | `n/a` |
| `deployment_outcome` | `producer_required` | `require` in `recorded\|not_applicable` | `require` in `recorded\|not_applicable` | `n/a` | `n/a` |
| `cleanup_outcome` | `producer_required` | `require` == `complete` | `require` == `complete` | `n/a` | `require`; `complete` is the idempotent-rerun signal |
| `hub_tracker_ref` | `producer_required` | `record` (RESIDUAL-1) | `require` non-empty (RESIDUAL-1) | `n/a` | `n/a` |
| `component_tag` | `producer_conditional` | `req+match` vs `--component-tag` (fixed round 4) | `req+match` vs `--component-tag` (fixed round 3) | `attestation` (inside `<repo>@<tag>` title) | `n/a` (no caller override; no defined tag<->branch relation — RESIDUAL-2) |
| `component_version` | `producer_conditional` | **GAP-1** unbound -> `req+match` vs `--component-version` | `n/a` on the hub path; **GAP-7** `--version` on the `single_repo` path -> reject `--evidence-file` there | `n/a` | `n/a` |
| `evidence_state` (never emitted) | n/a | consumer-set on its own component view | **GAP-6** any string accepted -> closed enum with a per-value disposition (D9), fail closed on unknown | `n/a` | `n/a` |
| `hub_tracker_reconciliation_outcome` (never emitted) | `hub_input` | flag optional at parse time (`default="pending"`, see the note preceding this matrix); the omitted-flag default is itself a closed-enum member that fails the finalize gate, so omission never reads as verified — fail closed on unknown | **GAP-5** falls back to the evidence file -> require the flag, no fallback, no default | `n/a` | `n/a` |
| `child_release_state` (never emitted) | `hub_input` | `require` flag, fail closed on unknown | **GAP-5** falls back to the evidence file -> require the flag, no fallback | `n/a` | `n/a` |
| `component_key` (never emitted) | `hub_input_identifier` | `req+match` vs `--component-key` (matched against the evidence's `selected_product_repo_key`, per D13) | `n/a` — reconciliation reads its own `--issue` identifier, not `component_key`; see the note below the matrix | `n/a` | `n/a` |
| `child_item` (never emitted) | `hub_input_identifier` | `record` | `n/a` — see the note below the matrix | `n/a` | `n/a` |
| `source_pr` (never emitted) | `hub_input_identifier` | `record` | `n/a` — see the note below the matrix | `n/a` | `n/a` |
| `release_pr` (never emitted) | `hub_input_identifier` | `record` | `n/a` — see the note below the matrix | `n/a` | `n/a` |

**Note on reconciliation's `--issue` flag**: `--issue` is itself a `hub_input_identifier` member (D13), required but deliberately unbound (RESIDUAL-1). It has no evidence-file field counterpart and is not one of the producer's seven never-emitted fields listed above — it is `component-milestone-reconciliation.sh`'s own identifier argument, analogous in role to the bundle's `component_key` but not the same field. That is why every `component-milestone-reconciliation.sh` cell in the four rows above reads `n/a`: reconciliation never reads `component_key`, `child_item`, `source_pr`, or `release_pr` by those names, and `--issue` does not appear as its own matrix row because the field axis above enumerates producer fields (emitted or never-emitted), not consumer-only CLI arguments.

### Gap register

| ID | Where | Defect | Fix |
| --- | --- | --- | --- |
| GAP-1 | producer + `delivery-bundle-manifest.sh` | `component_version` is never emitted, and `--component-version` (`default=None`) is stored into the shipped-composition manifest unchecked | Add `--component-version` to the producer, emit `component_version`; make the bundle flag required and require-and-match |
| GAP-2 | producer | `--component-tag` accepts any string; charset is enforced only downstream, and only by reconciliation | Charset-validate `--component-tag` and `--component-version` at the producer |
| GAP-3 | producer | `compare_field` passes when target and binding are *equally empty* (or *equally non-empty*), so a record can be emitted with empty `canonical_repository_identity` / `release_correlation_key` / `contract_revision` / `routing_outcome` / any `artifact_owners` sub-field — breaking the `producer_required` promise — or with an empty `selected_product_repo_key` under `component_release_routed` routing, or a non-empty `selected_product_repo_key` under `single_repo_release` routing, either of which would break the `producer_required_nullable` promise that `null` means `single_repo_release` **and** `single_repo_release` means `null` | Refuse emission when any of those four scalar fields (or an `artifact_owners` sub-field) is empty, when `selected_product_repo_key` is empty while `routing_outcome` is `component_release_routed`, and when `selected_product_repo_key` is non-empty while `routing_outcome` is `single_repo_release` (D4) |
| GAP-4 | `component-milestone-reconciliation.sh` | `routing_outcome` is never checked, so `single_repo_release` evidence is accepted on the `workflow_hub` milestone path | Require `component_release_routed` on the hub path |
| GAP-5 | `component-milestone-reconciliation.sh` | `hub_tracker_reconciliation_outcome` and `child_release_state` fall back to the evidence file — hub-owned facts sourced from a product-owned record | Remove the fallback; require the flags |
| GAP-6 | `component-milestone-reconciliation.sh` | Any `evidence_state` string is accepted; only `stale`/`conflicting` block, so an unknown value — and the bundle's own `missing` / `partial` degraded states — pass as non-blocking | Closed enum with the per-value disposition table in D9; fail closed on unknown |
| GAP-7 | `component-milestone-reconciliation.sh` | `--evidence-file` is silently ignored in `single_repo` mode while `--version` alone drives a real milestone mutation | Reject `--evidence-file` in `single_repo` mode; record `trust_basis` in the result |
| GAP-8 | `prepare-release-post-merge-cleanup.sh` | `canonical_repository_identity`, `release_correlation_key`, and `contract_revision` are compared but never required non-empty, so a pre-fix record with empty identity still passes. The identical compare-without-requiring-non-empty gap applies to every other `producer_required` field cleanup compares — `routing_outcome` and every `artifact_owners` sub-field (`release`, `ci`, `github_release`, `deployment`, `cleanup`, `tracker`) — and to `selected_product_repo_key` under its `producer_required_nullable` duty (require the key present; accept only a non-empty string or JSON `null`; reject an absent key or `""`). Cleanup never reaches the `single_repo_release` case (its target-outcome check already requires `component_release_routed` first, per the note preceding the Trust matrix table), so at this consumer the nullable duty reduces to require-non-empty exactly like the other identity fields | Require non-empty (`routing_outcome`, `canonical_repository_identity`, `release_correlation_key`, `contract_revision`, all six `artifact_owners` sub-fields) or require-present-non-empty (`selected_product_repo_key`) in the evidence, before any of the six `compare_component_field` calls |
| GAP-9 | `delivery-bundle-manifest.sh` | `release_branch` is not recorded, so the manifest cannot show which branch produced the shipped tag | Record it on the component view |
| GAP-10 | `multi-repo-release-assurance.sh` | Consumes self-declared reference strings, never a real evidence file; the trust class was never stated anywhere | Emit `trust_class: "attestation"`; document the bounded guarantee |
| GAP-11 | `05-prepare-release-protocol.md`, `cross-repo-pr-flow.md`, `scripts/development-workflow/README.md` | The documented producer invocations omit `--component-tag`, so the documented bundle-attach sequence fails at `component_tag_unbound` | Document the two-phase render (pending record, then a re-render that binds `--component-tag` and `--component-version`) |
| GAP-12 | `.agents/skills/prepare-release/SKILL.md` | States the evidence "must include" `hub_tracker_reconciliation_outcome` and `child_release_state` — fields the producer never emits, and which GAP-5 makes definitively hub-supplied | Correct the skill to name them as hub-supplied flags |
| GAP-13 | `prepare-release-post-merge-cleanup.sh` | `validate_component_release_cleanup` only compares `evidence.release_branch` against the resolved `RELEASE_INPUT` when `evidence.release_branch` is non-empty, so an evidence file with an empty or missing `release_branch` lets the positional `<version\|release-branch>` argument through unbound — the "compare only if present" defect class, unclosed for this field | Require `evidence.release_branch` to be non-empty **immediately after it is read from the evidence file** (the existing `evidence_branch="$(json_field ...)"` line), **before** `component-release-target.sh` re-resolves the target and **before** any of the six `compare_component_field` calls; reject when empty or missing. Placing the guard first, rather than later at the `RELEASE_INPUT` fallback/mismatch block, matters because an empty `evidence_branch` also changes what `--release-branch` is passed to target re-resolution, which changes the freshly resolved `release_correlation_key` (a per-attempt value) and can make `compare_component_field '.release_correlation_key'` fail with a mismatch **before** this guard ever runs if the guard is placed later — masking the intended rejection behind an unrelated identity-mismatch exit (D12) |

### Residual register (deliberately not closed by this audit)

| ID | Residual | Disposition | Rationale |
| --- | --- | --- | --- |
| RESIDUAL-1 | `hub_tracker_ref` is never matched against `--issue` (reconciliation) or `--child-item` (bundle), so any issue can be stamped with a valid milestone | `out_of_scope` | The field's semantics are genuinely undefined: `05-prepare-release-protocol.md` documents `<tracker-item-or-epic>`, `cross-repo-pr-flow.md` uses `#123`, and `tests/setup-component-release-fixture.sh` uses `fixture:1356`. Binding it requires first deciding whether it names the component child, the parent epic, or the delivery bundle — a contract decision, not an audit finding. Recorded in the contract doc's Known gaps. |
| RESIDUAL-2 | `component_tag` has no enforced relation to the version segment of `release_branch` (fixtures pair tag `mobile-v1.4.0` with branch `mobile-app/release/v1.0.0`) | `out_of_scope` | No normalization rule exists in this codebase; inventing one would be a guess and would break existing fixtures. See Decision D1. |
| RESIDUAL-3 | `apply-component` mutates GitHub milestones from the evidence file alone, without re-resolving an independent target binding the way cleanup does | `out_of_scope` | Closing it changes the required CLI contract of a mutating helper and adds a hub-config prerequisite to every caller — larger than this audit and not named by any acceptance criterion. |
| RESIDUAL-4 | `multi-repo-release-assurance.sh` applies no shape validator to `hub_config`, `product_config`, `run_id`, `step_id`, `supersedes`, `idempotency_guard` | `out_of_scope` | This codebase establishes no objective format for any of the six. The existing validators were deliberately limited to fields with an established format; inventing formats would produce false rejections. |
| RESIDUAL-5 | `prepare-release-post-merge-cleanup.sh`'s cleanup lease is hub-checkout-scoped, not cross-machine; and it has no release-tag deletion logic at all, while the smoke-test document's `remote_tag_deleted` field describes functionality that was never implemented | `out_of_scope` | Explicitly carried forward from the brief's "Residual limitations recorded at merge" section, which states these are not part of this audit. Recorded in the contract doc so they are not lost. |
| RESIDUAL-6 | T2 asserts the rendered record's key list against a hardcoded 16-key list inside the test file, not against the emitted-field contract table itself; nothing in this plan mechanically derives one from the other, so a maintainer who updates the producer's `jq` emission object and T2's hardcoded list together, while forgetting the contract table, introduces silent drift between the running code and the published documentation that no test catches | `out_of_scope` | This codebase has no existing tooling that extracts a field list from a markdown table for use in a test assertion (checked: no such helper exists under `scripts/lint/` or `scripts/development-workflow/`), and inventing one is outside this audit's boundary-closing scope — it would add new parsing/tooling surface the brief never asked for. T2's real, narrower guarantee is drift detection between the running producer and T2's own list; the gap between that list and the contract table is accepted here rather than assumed away. |

---

## Decisions Made During Alignment

Guardrail mode was `delegated` and no human was available mid-run. Each decision below was
resolvable from the brief, the acceptance criteria, or the code; none is a genuinely open
architecture question.

**D1 — Bind `component_version` symmetrically with `component_tag`, do not derive it from
`release_branch`.** The producer gains `--component-version` and emits the value, exactly as
it already does for `--component-tag`. *Rejected alternative*: derive `component_version`
from the `{version}` capture of `release_branch_pattern` applied to `--release-branch`. That
is structurally stronger (non-forgeable relative to the branch) but requires inventing a
normalization rule — the repository's own fixtures pair `--component-version 1.4.0` with
branch `mobile-app/release/v1.0.0`, so no `v`-prefix or equality convention exists to derive
from. AC-3 asks that the field be "bound and matched wherever a caller can supply it", which
D1 satisfies without inventing a contract. Recorded as RESIDUAL-2.

**D2 — `--component-version` becomes required on `delivery-bundle-manifest.sh
update-component`.** Leaving it optional reproduces the exact defect class the brief
condemns: an optional overridable field whose absence is not a rejection. It mirrors
`--component-tag`, which is already `required=True`. Every in-repository caller
(`tests/test-delivery-bundle-manifest.sh`, `scripts/development-workflow/README.md`,
`05-prepare-release-protocol.md`) already passes it.

**D3 — Charset for `--component-tag` and `--component-version` is `^[A-Za-z0-9._-]+$`,
enforced at the producer.** This is the charset already used three times downstream:
`TAG_RE` in `component-milestone-reconciliation.sh`, `KEY_RE` in
`delivery-bundle-manifest.sh`, and `_is_valid_milestone_title` in
`multi-repo-release-assurance.sh`. Enforcing it at the producer makes it one choke point
instead of three partial ones, and guarantees a milestone title `<repo>@<tag>` that the
assurance validator will accept.

**D4 — The producer refuses to emit when `canonical_repository_identity`,
`release_correlation_key`, `contract_revision`, `routing_outcome`, or any `artifact_owners`
sub-field is empty; when `selected_product_repo_key` is empty under
`component_release_routed` routing; and, in the reverse direction, when
`selected_product_repo_key` is non-empty under `single_repo_release` routing.** `compare_field`
compares target against binding, so two equally empty values pass — and, symmetrically, two
equally non-empty values pass regardless of what `routing_outcome` says they should be.
`selected_product_repo_key` cannot carry the unconditional non-empty precondition, because
`component-release-target.sh`
emits it as `null` for `single_repo_release` routing by design (the empty key at line 257,
rendered `null` at line 105). It is therefore classified `producer_required_nullable` rather
than `producer_required`, and its precondition is conditional on routing instead of absolute —
conditional in both directions, not only the `component_release_routed` direction: the guard
also refuses emission when routing is `single_repo_release` but the target and binding agree on
a non-null key, because `compare_field`'s plain equality check has no opinion on `routing_outcome`
at all and would otherwise let two callers agree on a bound key under `single_repo_release`
routing without complaint. The conditional form is what makes the class self-sufficient only once
both halves of the guard are in place: `null` occurs **if and only if**
routing is `single_repo_release` — the forward half (a `component_release_routed` record must
carry a non-empty key) and the reverse half (a `single_repo_release` record must carry `null`)
are two separate rejections, each closing one direction of the same "if and only if", so a
consumer that has already required `component_release_routed` may require non-empty without
consulting the producer.
`routing_outcome` and `artifact_owners` share the identical `compare_field` weakness: the
emitted-field contract table already classified both `producer_required`, but before this
decision nothing enforced non-empty on either one before emission, so two independently
agreeing-but-empty values passed `compare_field` exactly as they did for the other three
scalar fields — the same "producer_required promise the producer does not keep" gap, just
unexamined for these two. `artifact_owners` is an object with six string sub-fields (`release`,
`ci`, `github_release`, `deployment`, `cleanup`, `tracker`); the precondition checks each
sub-field individually, not the object as a whole, because `emit_target` in
`component-release-target.sh` always emits a populated object shape — the object itself is
never empty or null, only an individual sub-field's value can be.
*Rejected alternative*: leave the field in `producer_required` and record the `null` case as
prose. That is the contradiction this decision removes — a class whose stated duty ("require
non-empty") is wrong for one of its own members sends every future consumer back into the
producer source, which is exactly what AC-5 forbids. Without D4 the `producer_required` class
is a promise the producer does not keep, and every consumer that relies on presence is relying
on nothing.

**D5 — Remove the evidence-file fallback for `hub_tracker_reconciliation_outcome` and
`child_release_state` in `component-milestone-reconciliation.sh`; require the CLI flags.**
The in-code comment justifies the fallback by "callers that already embed them there (for
example a manifest-derived component view)". That caller is unreachable: line 257 rejects any
evidence object whose top-level `schema_version` is not `component_release_evidence.v1`, and a
delivery-bundle component record carries `evidence_schema_version`, not `schema_version` (see
`component_from_evidence`). So the only object that can reach the fallback is a hand-authored
file claiming to be producer output while carrying fields the producer never emits — the
defect class itself. *Rejected alternative*: keep the fallback but gate it on a hub-authored
marker. That adds a marker no producer writes, to serve a caller that does not exist.

**D6 — Reject `--evidence-file` in `single_repo` mode rather than silently ignoring it.**
`non_hub_result` never reads the evidence file, so an operator who supplies one today
believes a check happened that did not. Failing closed with
`evidence_not_supported_in_single_repo` is trivially reversible (omit the flag) and removes a
silent-ignore surface. The `single_repo` result additionally carries
`trust_basis: "caller_asserted"` so the milestone title's provenance is explicit in output.

**D7 — Do not bind `hub_tracker_ref` to `--issue` or `--child-item`.** See RESIDUAL-1: the
semantics are undefined across three in-repository shapes. The conservative choice is to
document the ambiguity rather than guess which issue it names.

**D8 — `multi-repo-release-assurance.sh` is classified `attestation`; add no invented format
validators.** It never loads a real evidence file — by design, per its own header comment
("the assurance summary remains self-review evidence, not a replacement for the release
helpers it checks"). The in-scope change is to make that class machine-visible
(`trust_class: "attestation"` in the result) and documented, not to fabricate formats for the
six fields in RESIDUAL-4.

**D9 — `evidence_state` becomes a closed enum with a stated disposition per member**, instead
of treating unrecognized strings as non-blocking. The member list is taken from the values
this subsystem actually produces, not invented: `delivery-bundle-manifest.sh` lines 216-222
emit `verified`, `missing`, `conflicting`, and `partial`;
`component-milestone-reconciliation.sh` line 521 additionally accepts `released` on the
manifest-component path and line 535 blocks on `stale`/`conflicting`. Enumerating the values
without deciding each one's disposition would leave a permissive branch inside a rule
asserted as fail-closed, so the decision is:

| `evidence_state` value | Disposition on the hub evidence path | Why |
| --- | --- | --- |
| `verified` | non-blocking | The success state `evidence_state()` already synthesizes for a schema-correct record. |
| `released` | non-blocking | Already accepted at line 521; rejecting it here would make one script disagree with itself. |
| `stale` | blocker `stale_component_evidence` | Existing behavior at line 535, preserved. |
| `conflicting` | blocker `conflicting_component_evidence` | Existing behavior at line 535, preserved. |
| `missing` | blocker `missing_component_evidence` | **New.** The bundle emits it when a component has no usable evidence; admitting it as non-blocking is the "absent value treated as a match" defect this audit exists to close. |
| `partial` | blocker `partial_component_evidence` | **New.** The bundle emits it for a component whose outcomes are still pending (`tests/test-delivery-bundle-manifest.sh`, assertion `pending_default_persisted_partial`); a partially evidenced component must not stamp a milestone. |
| any other string, or a non-string | blocker `invalid_evidence_state` | Fail closed on unknown. |
| absent | unchanged: synthesized as `verified` when `schema_version` matches, otherwise blocker `evidence_state_missing` | Pre-existing behavior at lines 179-196; this plan does not change it. |

**D10 — Extend the five existing test suites; do not add a new one.**
`select-test-suites.sh` maps `test-<name>.sh` to `scripts/development-workflow/<name>.sh` by
naming convention, so every suite this plan touches is already selected by a change to its
script. A new cross-cutting suite would need a hand-maintained `# covers:` header and would
duplicate fixture construction that already exists in each suite.

**D11 — The trust matrix lives in a new dedicated document**,
`docs/workflow/development-workflow/component-release-evidence-contract.md`, linked from
`repository-modes.md`, `multi-repo-release-adoption.md`, and
`scripts/development-workflow/README.md`. AC-1 and AC-5 are both documentation deliverables
about one artifact; `repository-modes.md` already carries the repository-mode contract and is
the wrong home for a field-level producer/consumer matrix.

**D12 — `prepare-release-post-merge-cleanup.sh` refuses to proceed when `evidence.release_branch`
is empty or missing, instead of letting the positional `<version|release-branch>` argument
through unchecked.** `validate_component_release_cleanup` only runs the
`normalize_release_branch` mismatch check `[ -n "$evidence_branch" ] && ... != ...` when
`evidence_branch` is non-empty, so an evidence file whose `release_branch` is empty or absent —
the same "compare only if present" defect class GAP-3 closes at the producer for the
`target_binding` identity fields — lets any positional argument through as if it had already
been validated against the evidence, even though the trust matrix's `release_branch` /
`prepare-release-post-merge-cleanup.sh` cell claims unconditional `req+match`.
`component-release-evidence.sh` requires `--release-branch` to be non-empty before it will emit
a record (line 140-143), so a genuinely producer-emitted record can never carry an empty
`release_branch`; an empty or missing value reaching cleanup is therefore proof the file was not
produced by the real producer — hand-authored, corrupted, or a pre-audit record — and cleanup
must reject it rather than trust the caller-supplied argument alone. *Fix*: require
`evidence_branch` to be non-empty **immediately after `validate_component_release_cleanup` reads
it from the evidence file** — the existing `evidence_branch="$(json_field "$EVIDENCE_FILE"
'.release_branch')"` line — and **before** `component-release-target.sh` re-resolves the target
and **before** any of the six `compare_component_field` calls. It is not enough to place the
guard merely "before the `RELEASE_INPUT` fallback/mismatch block": that block sits far
downstream, after the target re-resolution call and after all six `compare_component_field`
calls already run, so a guard placed there — while still technically "before" that specific
block — leaves every check that runs between `evidence_branch`'s read and that block free to
fire first. Ordering matters here in a way it does not for the other
`GAP-8` identity fields: `evidence_branch`, when non-empty, is also passed to
`component-release-target.sh` as `--release-branch` so the freshly resolved target reproduces the
same per-attempt `release_correlation_key` recorded in the evidence (see the comment above
`evidence_branch`'s existing read). When `evidence_branch` is empty, that flag is omitted, the
re-resolved target computes its `release_correlation_key` from an empty attempt-branch input
instead, and — because that key is a hash of the attempt branch among other inputs — it will
generally disagree with the non-empty-attempt-branch key already recorded in the evidence's
`target_binding`. If this guard runs after the six `compare_component_field` calls, that
disagreement fires `compare_component_field '.release_correlation_key'`'s mismatch exit first,
which still exits `1` but never reaches this guard or its distinguishing message — so a test
fixture whose `release_correlation_key` reflects a real per-attempt value (as a genuine evidence
file's does) would exercise the wrong rejection path even though the run still exits non-zero.
Running this guard first, before either the re-resolution call or any compare, removes that
ordering dependency entirely: an empty `evidence_branch` is rejected on its own before any other
check can fire ahead of it. Exit `1` with `Component release evidence is missing required
field: release_branch` when it is empty (GAP-13). *Rejected alternative*: leave the check
conditional on `evidence_branch` being present, or place it "before the `RELEASE_INPUT`
fallback/mismatch block" without specifying that this is downstream of re-resolution and the six
compares. Either omission reproduces the same "compare only if present" defect class this
decision exists to close — a required field's absence must never be read as "nothing to check",
the same principle AC-2 states for every other overridable field, and an ambiguous ordering
instruction leaves the implementer free to place the guard somewhere it can be masked by an
unrelated, earlier-firing check.

**D13 — Split `hub_input` into `hub_input` (closed-enum outcome flags) and
`hub_input_identifier` (open-ended identifiers).** The single `hub_input` class's stated duty —
"validate against a closed enum, fail closed on any unknown value" — is true of
`hub_tracker_reconciliation_outcome` and `child_release_state`, but was never true of
`component_key`, `child_item`, `source_pr`, `release_pr`, or reconciliation's `--issue`: these are
component keys, PR references, and an issue number, none drawn from a fixed vocabulary, and the
trust matrix already gave them a different duty (`component_key` matched against a *different*
evidence field, `selected_product_repo_key`; `child_item`/`source_pr`/`release_pr` merely
`record`; `--issue` required but deliberately unbound per RESIDUAL-1). Nothing about that existing
behavior changes — this decision corrects the class table to match the matrix cells it was
already contradicting, rather than inventing new behavior for the identifier fields. *Rejected
alternative*: keep one `hub_input` class and add prose carving out the identifier fields as an
exception. AC-5's promise is that "the class alone determines the consumer's duty: no field is an
exception to the class it carries" — an exception clause inside the one class definition is the
same contradiction the class table is not supposed to contain, just relocated into prose instead
of a table cell.

---

## Layer-by-Layer Changes

This repository has no database, backend service, or frontend. The affected layers are
workflow tooling scripts, their test suites, workflow documentation, and one agent-skill
surface.

### Workflow tooling — producer

- [ ] `scripts/development-workflow/component-release-evidence.sh`
  - Add `--component-version VERSION` argument parsing and usage text (D1).
  - Add a `validate_identifier` helper applying `^[A-Za-z0-9._-]+$` to `--component-tag` and
    `--component-version` when supplied; exit `2` with
    `--component-tag must use letters, numbers, dot, underscore, or hyphen` (D3).
  - After the six `compare_field` calls, refuse emission when `canonical_repository_identity`,
    `release_correlation_key`, `contract_revision`, or `routing_outcome` resolves empty, or when
    any `artifact_owners` sub-field (`release`, `ci`, `github_release`, `deployment`, `cleanup`,
    `tracker`) resolves empty; exit `1` with
    `target binding is missing required identity field: <field>` (D4).
  - In the same block, refuse emission when `selected_product_repo_key` resolves empty while
    `routing_outcome` is `component_release_routed`; exit `1` with
    `target binding is missing required identity field: selected_product_repo_key`.
  - In the same block, also refuse emission in the reverse direction: when `routing_outcome` is
    `single_repo_release` and `selected_product_repo_key` resolves **non-empty**; exit `1` with
    `target binding must not bind selected_product_repo_key under single_repo_release routing`.
    Without this second guard, `compare_field '.selected_product_repo_key'` only checks that the
    target and binding agree with each other, not that the agreed value is consistent with
    `routing_outcome` — a target and binding could both carry the same non-null key alongside
    `single_repo_release` routing and pass unexamined. Together, the two guards make `null`
    occur if and only if routing is `single_repo_release`, which is what keeps
    `producer_required_nullable` derivable (D4).
  - Emit `component_version` in the `jq` object, `null` when the flag was omitted, mirroring
    `component_tag` (line 223).
  - Shell contract: `bash` (the file has a `#!/usr/bin/env bash` shebang and uses
    `set -euo pipefail`); no new iteration or positional-splitting guidance is introduced.

### Workflow tooling — consumers

- [ ] `scripts/development-workflow/delivery-bundle-manifest.sh`
  - Make `--component-version` `required=True` (D2).
  - In `component_from_evidence`, after the existing `component_tag` block, add the mirrored
    `component_version` block: fail `component_version_unbound` when
    `evidence.get("component_version")` is falsy, then fail `component_version_mismatch` when
    it differs from `args.component_version` (GAP-1).
  - Record `release_branch` from the evidence on the component dict (GAP-9). It is audit
    metadata only: it must **not** join `stable_fields`, because a legitimate re-tag under a
    new `release_pr` changes it.
  - Validate `--hub-tracker-reconciliation-outcome` and `--child-release-state` against their
    closed enums at parse time so the error names the flag rather than surfacing later as a
    generic `blocked_component_outcome`. Preserve
    `--hub-tracker-reconciliation-outcome`'s existing `default="pending"` (line 591): the
    validation applies to a supplied value, not to the default, and
    `tests/test-delivery-bundle-manifest.sh` pins that default in
    `hub_reconciliation_defaults_pending`.
- [ ] `scripts/development-workflow/component-milestone-reconciliation.sh`
  - `classify_component`, hub path: require
    `stable_value(evidence, "routing_outcome") == "component_release_routed"`; on mismatch set
    `reconciliation_outcome="component_target_mismatch"`, `child_release_state="blocked"`,
    blocker `routing_outcome_mismatch` (GAP-4).
  - Replace the `hub_reconciliation` / `child_state` fallback chains (lines 328-333) with the
    CLI flags only; emit blockers `hub_tracker_reconciliation_outcome_required` and
    `child_release_state_required` when absent (GAP-5, D5).
  - `evidence_state()`: return the raw value only when it is in the closed enum; otherwise
    return a sentinel that produces the blocker `invalid_evidence_state`. In the blocker
    assembly that follows, extend the existing `stale`/`conflicting` branch to the full
    disposition table in D9, so `missing` and `partial` add
    `missing_component_evidence` / `partial_component_evidence` instead of passing as
    non-blocking (GAP-6, D9).
  - `single_repo` path: fail with `evidence_not_supported_in_single_repo` when
    `--evidence-file` is supplied, and add `trust_basis: "caller_asserted"` to the
    `non_hub_result` payload (GAP-7, D6).
  - Add `trust_basis: "evidence_bound"` to the hub-path result so both paths report the same
    key with different values.
- [ ] `scripts/development-workflow/prepare-release-post-merge-cleanup.sh`
  - In `validate_component_release_cleanup`, before the six `compare_component_field` calls,
    require every `producer_required` field those calls compare —
    `.target_binding.routing_outcome`, `.target_binding.canonical_repository_identity`,
    `.target_binding.release_correlation_key`, `.target_binding.contract_revision`, and each of
    the six `.target_binding.artifact_owners` sub-fields (`release`, `ci`, `github_release`,
    `deployment`, `cleanup`, `tracker`) — to be non-empty in the evidence; exit `1` with
    `Component release evidence is missing required identity field: <field>` (GAP-8). Require
    `.target_binding.selected_product_repo_key` to be present and non-empty in the evidence with
    the same exit and message (the `producer_required_nullable` duty reduces to require-non-empty
    here, because the `target_outcome` check earlier in the function already requires the freshly
    resolved target to be `component_release_routed` before any of these checks run, so the
    `single_repo_release` / `null` case is unreachable at this consumer, per the note preceding
    the Trust matrix table) (GAP-8).
  - Require the top-level `evidence.release_branch` to be non-empty **immediately after**
    `evidence_branch` is read from the evidence file (the existing
    `evidence_branch="$(json_field "$EVIDENCE_FILE" '.release_branch')"` line) and **before**
    `component-release-target.sh` is invoked to re-resolve the target, and therefore before the
    GAP-8 non-empty preconditions above and all six `compare_component_field` calls as well; exit
    `1` with `Component release evidence is missing required field: release_branch` when it is
    empty or absent, so an empty/missing evidence value can never let the positional
    `<version|release-branch>` argument through unmatched, and — because target re-resolution
    uses `evidence_branch` to reproduce the recorded per-attempt `release_correlation_key` — an
    empty `evidence_branch` can never instead surface as a `compare_component_field
    '.release_correlation_key'` mismatch that masks this guard's own rejection message
    (GAP-13, D12).
  - Shell contract: `bash`. No new doc snippets are added to this file.
- [ ] `scripts/development-workflow/multi-repo-release-assurance.sh`
  - Add `"trust_class": "attestation"` to the result object and to the key/value output as
    `TRUST_CLASS=attestation` (GAP-10, D8).

### Test suites

- [ ] `scripts/development-workflow/tests/test-component-release-evidence.sh`
- [ ] `scripts/development-workflow/tests/test-delivery-bundle-manifest.sh`
- [ ] `scripts/development-workflow/tests/test-component-milestone-reconciliation.sh`
- [ ] `scripts/development-workflow/tests/test-multi-repo-release-assurance.sh`
- [ ] `scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh`
- [ ] `scripts/development-workflow/tests/setup-component-release-fixture.sh` and
      `scripts/development-workflow/tests/setup-component-milestone-fixture.sh` — extend the
      emitted fixture evidence with `component_version` so fixtures satisfy the tightened
      contract.

### Documentation

See **Documentation Updates** below for the full enumeration and the change each file needs.

### Infrastructure / configuration

- [ ] None. `select-test-suites.sh` already selects each touched suite by naming convention
      (Verification Log), and no GitHub Actions workflow enumerates these suites by name.

---

## Files to Modify — Full Enumeration

The brief's intent is pattern-based ("for each field ... and for each consumer"), so this
list comes from the live searches recorded in the Verification Log at revision `c367abf0`,
not from a prior enumeration.

**Runtime (5)**

1. `scripts/development-workflow/component-release-evidence.sh`
2. `scripts/development-workflow/delivery-bundle-manifest.sh`
3. `scripts/development-workflow/component-milestone-reconciliation.sh`
4. `scripts/development-workflow/multi-repo-release-assurance.sh`
5. `scripts/development-workflow/prepare-release-post-merge-cleanup.sh`

**Tests and fixtures (7)**

1. `scripts/development-workflow/tests/test-component-release-evidence.sh`
2. `scripts/development-workflow/tests/test-delivery-bundle-manifest.sh`
3. `scripts/development-workflow/tests/test-component-milestone-reconciliation.sh`
4. `scripts/development-workflow/tests/test-multi-repo-release-assurance.sh`
5. `scripts/development-workflow/tests/test-prepare-release-tracker-cleanup.sh`
6. `scripts/development-workflow/tests/setup-component-release-fixture.sh`
7. `scripts/development-workflow/tests/setup-component-milestone-fixture.sh`

**Documentation and release notes (8; two created by the implementation, one already created on this plan branch)**

1. `docs/workflow/development-workflow/component-release-evidence-contract.md` — **new**
2. `docs/workflow/development-workflow/repository-modes.md`
3. `docs/workflow/development-workflow/multi-repo-release-adoption.md`
4. `docs/workflow/development-workflow/cross-repo-pr-flow.md`
5. `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`
6. `scripts/development-workflow/README.md`
7. `docs/testing/workflow/1529-delivery-bundle-trust-boundary.smoke-test.md` — created on this plan branch; the implementation updates it with recorded PASS/FAIL results
8. `changelog.d/1529.fixed.delivery-bundle-evidence-trust-boundary.md` — **new**

**Agent / skill surfaces (1)**

1. `.agents/skills/prepare-release/SKILL.md` (GAP-12)

**Deliberately excluded, with evidence**

- `.claude/agents/*`, `.cursor/agents/*`, `.codex/skills/*` — the live search
  (`grep -rn "component-release-evidence\|component_release_evidence\|component-milestone-reconciliation\|delivery-bundle-manifest" .agents/ .codex/ .claude/ .cursor/`)
  returned hits only in `.agents/skills/prepare-release/SKILL.md`. There is no
  `.codex/skills/prepare-release` mirror (`ls .codex/skills/` lists 16 entries, none of them
  `prepare-release`).
- `REVIEW.md`, `02-generate-implementation-plan-protocol.md`,
  `03-implement-development-protocol.md` — this plan adds a subsystem contract, not a
  checklist category that every future feature plan must satisfy, so the cross-cutting
  checklist block's agent/skill mirror list does not apply. See the Document Quality Gate
  entry.
- `docs/specs/developments/**` (5 historical plans) and `CHANGELOG.md` — historical records;
  never retro-edited.
- `docs/testing/workflow/1356-*`, `1357-*`, `1358-*`, `1359-*.smoke-test.md` — historical
  runbooks for merged items. Their recorded commands remain a truthful record of what was run
  at the time; this item's runbook covers the new behavior.
- `docs/workflow/development-workflow/protocols/05b-graduate-development-protocol.md` and
  `94-batch-merge-protocol.md` — both reference the producer by name only, with no flag list
  or field list to correct.
- `scripts/development-workflow/tests/test-workflow-hub-docs.sh` — it `covers:` five of the
  documents this plan edits, but every assertion on them is an additive `run_contains`
  substring check (lines 132-188), so adding the two-phase render, the `attestation` class,
  and the contract-document links cannot break it. The suite is still executed in
  Implementation Order step 15. If a `run_contains` string is ever reworded rather than
  added to, update the suite in the same commit.

---

## Testing Strategy

**Test types**: Unit/behavioral shell suites (primary) + smoke runbook (secondary). No
end-to-end or browser testing applies.

**AC-4 discipline (mandatory)**: for each fabricated-value case below, the implementation
agent must (1) add the test, (2) run the suite against unmodified runtime code and capture the
**failing** output, (3) apply the fix, (4) re-run and capture the passing output. The captured
red-then-green pairs are the completion evidence recorded on the implementation PR. Two test
identifiers are explicitly parameterized rather than a single fabricated-value case each: T6d
must capture six red-then-green pairs, one per `artifact_owners` sub-field (`release`, `ci`,
`github_release`, `deployment`, `cleanup`, `tracker`), because a single sub-field capture cannot
prove a six-sub-field guard actually checks all six; T20f (see the Fabricated-value rejection
cases table) is the identical parameterization for the equivalent guard in
`prepare-release-post-merge-cleanup.sh`. Every other test identifier captures exactly one
red-then-green pair.

**Three tests are exempt from red-capture, and only these three.** T22 guards a defect already
fixed in review round 3, so it is green against unmodified runtime code by construction and
cannot be confirmed red. T6b pins behavior this plan deliberately leaves unchanged — the
producer's `null` passthrough for `single_repo_release` routing — so that T6a's new
precondition cannot be over-applied to the one routing case where `null` is the contracted
value; it is likewise green by construction. T15b pins behavior this plan deliberately leaves
unchanged for the same reason as T6b: `released` is already non-blocking in the current
implementation (line 521), and D9's disposition table preserves that behavior explicitly
("Already accepted at line 521; rejecting it here would make one script disagree with
itself") rather than tightening it — so there is no fix for T15b to be red against, and it is
likewise green by construction. Record all three as green-before and green-after.
Every other numbered test must show a captured red state: T1-T21 other than T6b and T15b,
including T5b, T6a, T6c, T6d, T6e, T15a, T20b, T20c, T20d, T20e, and T20f, all target behavior this
plan introduces.

### Fabricated-value rejection cases

| # | Suite | Fabricated input | Expected rejection |
| --- | --- | --- | --- |
| T1 | `test-component-release-evidence.sh` | `--component-version v99.0.0` supplied, record inspected | `component_version` present and equal to the supplied value |
| T2 | `test-component-release-evidence.sh` | `--component-version` omitted | `component_version` is JSON `null` (not absent, not `""`), **and** `jq -r 'keys \| join(",")'` on the rendered record equals a hardcoded 16-key list mirroring the emitted-field contract table exactly — this pins the running producer's key set against T2's own list (RESIDUAL-6 records the gap between that list and the contract table itself) |
| T3 | `test-component-release-evidence.sh` | `--component-tag "bad tag"` (space) | exit 2, message names `--component-tag` |
| T4 | `test-component-release-evidence.sh` | `--component-version "1.0.0;rm"` | exit 2, message names `--component-version` |
| T5 | `test-component-release-evidence.sh` | target binding with `contract_revision: ""` | exit 1, `missing required identity field: contract_revision` |
| T5b | `test-component-release-evidence.sh` | target binding with `canonical_repository_identity: ""` | exit 1, `missing required identity field: canonical_repository_identity` |
| T6 | `test-component-release-evidence.sh` | target binding with `release_correlation_key: ""` | exit 1, names `release_correlation_key` |
| T6a | `test-component-release-evidence.sh` | target binding with `routing_outcome: "component_release_routed"`, `selected_product_repo_key: null`, and `release_branch_pattern` omitted (empty) — the pre-existing pattern check at lines 167-190 only runs when `.release_branch_pattern` is non-empty, and with the `{product_repo}` token present that check would substitute the null key's empty string, making no `--release-branch` value satisfy both the pattern and the null key at once; omitting the pattern lets the run reach D4's new guard instead of failing that unrelated check first | exit 1, `missing required identity field: selected_product_repo_key`; no record written |
| T6b | `test-component-release-evidence.sh` | target binding with `routing_outcome: "single_repo_release"`, `selected_product_repo_key: null`, and `release_branch_pattern` likewise omitted (empty), for the identical reason as T6a — the null key cannot satisfy a pattern containing `{product_repo}` regardless of routing outcome | record emitted; `selected_product_repo_key` is JSON `null` — the `producer_required_nullable` contract, and the guard that T6a's precondition is not over-applied (red-capture exempt) |
| T6c | `test-component-release-evidence.sh` | target binding with `routing_outcome: ""` | exit 1, `missing required identity field: routing_outcome` |
| T6d | `test-component-release-evidence.sh` | target binding with exactly one `artifact_owners` sub-field set to `""`, other five populated — run once per sub-field (`release`, `ci`, `github_release`, `deployment`, `cleanup`, `tracker`; six separate red-then-green captures under this one test identifier, T6d, each emptying a different sub-field so the guard is proven to check all six rather than only one) | each of the six runs: exit 1, `missing required identity field: artifact_owners`; no record written |
| T6e | `test-component-release-evidence.sh` | target binding with `routing_outcome: "single_repo_release"` and `selected_product_repo_key` set to a **non-null, non-empty** value (e.g. `mobile-app`), with `release_branch_pattern` omitted (empty) for the same structural reason as T6a/T6b — this proves the reverse direction of the `producer_required_nullable` guard: a target and binding that both agree on a bound key under `single_repo_release` routing must still be rejected, not merely allowed to pass because target and binding agree with each other | exit 1, `target binding must not bind selected_product_repo_key under single_repo_release routing`; no record written |
| T7 | `test-delivery-bundle-manifest.sh` | evidence binding `component_version: null`, `--component-version 1.4.0` | `ERROR_CODE=component_version_unbound` |
| T8 | `test-delivery-bundle-manifest.sh` | evidence binding `component_version: "1.4.0"`, `--component-version 99.0.0` | `ERROR_CODE=component_version_mismatch` |
| T9 | `test-delivery-bundle-manifest.sh` | `--component-version` omitted entirely | argparse failure, `ERROR_CODE=invalid_arguments`, exit 2 |
| T10 | `test-delivery-bundle-manifest.sh` | `--child-release-state shipped` (not in the enum) | rejected at parse time naming `--child-release-state` |
| T11 | `test-delivery-bundle-manifest.sh` | valid update | component record carries `release_branch` from the evidence |
| T12 | `test-component-milestone-reconciliation.sh` | evidence with `routing_outcome: "single_repo_release"` on the hub path | `component_target_mismatch`, blocker `routing_outcome_mismatch`, `mutation_allowed=false` |
| T13 | `test-component-milestone-reconciliation.sh` | evidence carrying `hub_tracker_reconciliation_outcome: "complete"`, flag omitted | blocker `hub_tracker_reconciliation_outcome_required`; the evidence value is **not** used |
| T14 | `test-component-milestone-reconciliation.sh` | evidence carrying `child_release_state: "released"`, flag omitted | blocker `child_release_state_required` |
| T15 | `test-component-milestone-reconciliation.sh` | evidence with `evidence_state: "totally-fine"` | blocker `invalid_evidence_state`, `mutation_allowed=false` |
| T15a | `test-component-milestone-reconciliation.sh` | evidence with `evidence_state: "partial"`, then a second run with `evidence_state: "missing"` | blockers `partial_component_evidence` and `missing_component_evidence` respectively, `mutation_allowed=false` in both (D9 disposition table) |
| T15b | `test-component-milestone-reconciliation.sh` | evidence with `evidence_state: "released"` and otherwise valid hub facts | no `evidence_state` blocker — the value stays non-blocking, matching line 521 |
| T16 | `test-component-milestone-reconciliation.sh` | `--mode single_repo --evidence-file <path>` | `evidence_not_supported_in_single_repo`, no `gh` call recorded |
| T17 | `test-component-milestone-reconciliation.sh` | `--mode single_repo --version v1.2.3`, no evidence | `trust_basis: "caller_asserted"` in the result |
| T18 | `test-component-milestone-reconciliation.sh` | valid hub-path apply | `trust_basis: "evidence_bound"` in the result |
| T19 | `test-prepare-release-tracker-cleanup.sh` | evidence whose `target_binding.contract_revision` is `""` | exit 1, `missing required identity field: contract_revision`; no branch deletion |
| T20 | `test-prepare-release-tracker-cleanup.sh` | evidence whose `target_binding.canonical_repository_identity` is `""` | exit 1, names the field |
| T20b | `test-prepare-release-tracker-cleanup.sh` | evidence whose `target_binding.release_correlation_key` is `""` | exit 1, names `release_correlation_key`; no branch deletion |
| T20c | `test-prepare-release-tracker-cleanup.sh` | evidence generated by `setup-component-release-fixture.sh`'s normal fixture path against a real `--release-branch` (so `target_binding.release_correlation_key` is the genuine per-attempt value that branch produces, exactly as the comment above cleanup's `evidence_branch` read describes), then the fixture's top-level `release_branch` is overwritten to `""` (or the key removed) **without** changing `target_binding.release_correlation_key` — this is deliberate: an empty `evidence_branch` means cleanup's target re-resolution omits `--release-branch`, so the freshly resolved target computes a *different* per-attempt `release_correlation_key` than the one already recorded in `target_binding`, and this fixture is the one that would surface that disagreement as a `compare_component_field '.release_correlation_key'` mismatch instead of the intended rejection if the new guard were implemented anywhere other than immediately after `evidence_branch` is read (a fixture that instead used a fixed, attempt-independent key would not expose that ordering defect) — with a positional release argument supplied that does not match any real branch | exit 1, `missing required field: release_branch`; no branch deletion; the message must **not** be a `release_correlation_key` mismatch, which would indicate the guard ran too late |
| T20d | `test-prepare-release-tracker-cleanup.sh` | evidence whose `target_binding.routing_outcome` is `""` | exit 1, names `routing_outcome`; no branch deletion |
| T20e | `test-prepare-release-tracker-cleanup.sh` | evidence whose `target_binding.selected_product_repo_key` is `""` (or the key absent) | exit 1, names `selected_product_repo_key`; no branch deletion |
| T20f | `test-prepare-release-tracker-cleanup.sh` | evidence with exactly one `target_binding.artifact_owners` sub-field set to `""`, other five populated — run once per sub-field (`release`, `ci`, `github_release`, `deployment`, `cleanup`, `tracker`; six separate red-then-green captures under this one test identifier, T20f, for the same reason as T6d) | each of the six runs: exit 1, names `artifact_owners`; no branch deletion |
| T21 | `test-multi-repo-release-assurance.sh` | valid fixture | output carries `trust_class: "attestation"` / `TRUST_CLASS=attestation` |
| T22 | `test-multi-repo-release-assurance.sh` | `release_contract: "garbage"` (regression guard for the round-3 fix) | `adoption_status: "blocked"` |

### Charset validator input enumeration (D3)

Although this plan is **not** parser-risk (see the Document Quality Gate), the new charset
validator deserves explicit accept/reject inputs so T3 and T4 are not the only coverage:

- **Accept**: `mobile-v1.4.0`, `1.4.0`, `v1.4.0-rc.1`, `a`, `A_B.c-9`
- **Reject (boundary)**: `""` (empty is treated as "flag omitted", not a charset failure —
  assert the `null` emission path of T2, not an error), `" v1.0.0"` (leading space),
  `"v1.0.0 "` (trailing space)
- **Reject (lookalike)**: `v1.0.0/rc` (slash), `v1.0.0@tag` (at-sign — would corrupt the
  `<repo>@<tag>` milestone title), `v1.0.0;echo` (semicolon), `v1.0.0$(id)` (command
  substitution characters), `../../etc/passwd` (path traversal)
- **Reject (multi-token on one value)**: `"v1.0.0 v2.0.0"`

### Regression suite

The repository's regression surface for this subsystem is the five shell suites above; they
are selected automatically by `select-test-suites.sh` when their scripts change. Full local
run:

```bash
for suite in component-release-evidence delivery-bundle-manifest \
             component-milestone-reconciliation multi-repo-release-assurance \
             prepare-release-tracker-cleanup component-release-target workflow-hub-docs; do
  bash "scripts/development-workflow/tests/test-${suite}.sh"
done
```

**Smoke test runbook**:
[`docs/testing/workflow/1529-delivery-bundle-trust-boundary.smoke-test.md`](../../../testing/workflow/1529-delivery-bundle-trust-boundary.smoke-test.md)

### Parser-risk addendum

**Not applicable.** No file under `scripts/lint/` or `scripts/parse/` changes; no new or
renamed module implies lint/parser/scanner/tokenizer responsibilities; and the only regex
introduced is a single anchored charset assertion on a CLI argument, not structured-text
scanning or a rule engine. Concrete accept/reject inputs for that validator are enumerated
above regardless, because they are cheap and they are exactly the fabricated-value shapes
this audit exists to reject.

### Concurrent-event-source addendum

**Not applicable.** All five helpers are single-shot CLI processes with no event listeners,
sockets, timers, or async queues. The two concurrency mechanisms in the subsystem — the
`delivery-bundle-manifest.sh` `with_lock` manifest lock and the
`prepare-release-post-merge-cleanup.sh` hub-scoped cleanup lease — already exist and are not
modified by this plan; the lease's known cross-machine limitation is carried forward
unchanged as RESIDUAL-5.

---

## Residual Verification Strategy

`scope-residual-gate.sh classify` returns `SCOPE_CLASSIFICATION=numeric_sweep`,
`TARGET_COUNT=4`, so `verify` requires explicit residual evidence before
`ready-for-human-review`.

**Evidence source**: occurrence counts from the same live searches recorded in the
Verification Log, re-run at implementation time, plus per-residual dispositions.

**Enumeration source**: the producer's own `jq` emission object
(`component-release-evidence.sh` lines 208-224) for the field axis, and the brief's named
four consumers for the consumer axis. Completeness evidence is that the matrix has one row per
emitted field plus one row per never-emitted field a consumer reads (16 emitted-field rows plus
7 never-emitted-field rows — `evidence_state`, `hub_tracker_reconciliation_outcome`,
`child_release_state`, `component_key`, `child_item`, `source_pr`, `release_pr`, each its own
row, per the Trust matrix section), and one column per named consumer — verifiable by re-running
the two enumeration commands, confirming every individual field name from both lists has its own
matrix row (not merely that the total row count matches, which cannot by itself distinguish one
correctly-split field from two fields silently collapsed into a single row), and comparing
counts as a secondary cross-check.

**Evidence file** the implementation agent must produce (path:
`docs/specs/developments/20260912021032_1529-delivery-bundle-trust-boundary/residual-evidence.json`)
and pass to `scope-residual-gate.sh verify --evidence <path>`:

```json
{
  "residual_groups": [
    {
      "summary": "hub_tracker_ref is never matched against --issue or --child-item (RESIDUAL-1)",
      "remaining_count": 2,
      "disposition": "out_of_scope"
    },
    {
      "summary": "component_tag has no enforced relation to the release_branch version segment (RESIDUAL-2)",
      "remaining_count": 1,
      "disposition": "out_of_scope"
    },
    {
      "summary": "apply-component mutates milestones without re-resolving an independent target binding (RESIDUAL-3)",
      "remaining_count": 1,
      "disposition": "out_of_scope"
    },
    {
      "summary": "multi-repo-release-assurance.sh has no shape validator for six fields with no established format (RESIDUAL-4)",
      "remaining_count": 6,
      "disposition": "out_of_scope"
    },
    {
      "summary": "cleanup lease is hub-checkout-scoped and no release-tag deletion exists; carried forward from the brief (RESIDUAL-5)",
      "remaining_count": 2,
      "disposition": "out_of_scope"
    },
    {
      "summary": "T2's hardcoded key list is not mechanically derived from the emitted-field contract table, so drift between the two is undetected (RESIDUAL-6)",
      "remaining_count": 1,
      "disposition": "out_of_scope"
    },
    {
      "summary": "Producer-emitted fields with no remaining unbound caller override after this work",
      "remaining_count": 0,
      "disposition": "completed"
    }
  ]
}
```

Every `remaining_count > 0` group carries `disposition: "out_of_scope"` with the rationale
recorded in the Residual register above and in the new contract document's Known gaps
section, which is what makes the gate satisfiable without fabricating follow-up issue links.

---

## Seed Data

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Component release target binding | `component_release_target.v1` with `mutation_allowed: true`, `routing_outcome: component_release_routed`, `release_branch_pattern: "{product_repo}/release/v{version}"` | `scripts/development-workflow/tests/setup-component-release-fixture.sh` (existing; extended) |
| Empty-identity target binding | Same, but `contract_revision: ""`; a second variant with `release_correlation_key: ""`; a third with `canonical_repository_identity: ""`; a fourth with `routing_outcome: ""`; a fifth family of six variants, each with exactly one `artifact_owners` sub-field (`release`, `ci`, `github_release`, `deployment`, `cleanup`, `tracker`) set to `""` and the other five populated | New temp fixtures inside `tests/test-component-release-evidence.sh` (T5, T5b, T6, T6c, T6d — T6d exercised once per `artifact_owners` sub-field) |
| Routed-null-key target binding | `component_release_target.v1` with `routing_outcome: "component_release_routed"`, `selected_product_repo_key: null`, and `release_branch_pattern` omitted (empty) — omitting the pattern is required because the base fixture's `{product_repo}/release/v{version}` pattern would substitute the null key's empty string, and no valid `--release-branch` value can satisfy both that pattern and the null key at once; with the pattern empty, `component-release-evidence.sh`'s branch-pattern check (which only runs when `.release_branch_pattern` is non-empty) is skipped, so the fixture reaches D4's new guard on its own merits | New temp fixture inside `tests/test-component-release-evidence.sh` (T6a) |
| Single-repository-routed target binding | `component_release_target.v1` with `routing_outcome: "single_repo_release"`, `mutation_allowed: true`, `selected_product_repo_key: null`, and `release_branch_pattern` omitted (empty) for the same structural reason as the routed-null-key fixture above | New temp fixture inside `tests/test-component-release-evidence.sh` (T6b) |
| Single-repository-routed bound-key target binding | `component_release_target.v1` with `routing_outcome: "single_repo_release"`, `mutation_allowed: true`, `selected_product_repo_key` set to a non-null, non-empty value (e.g. `mobile-app`), and `release_branch_pattern` omitted (empty) for the same structural reason as the routed-null-key fixture above — this is the reverse-direction counterpart to the routed-null-key and single-repository-routed fixtures, proving D4's guard rejects a bound key under `single_repo_release` routing rather than merely tolerating a `null` one | New temp fixture inside `tests/test-component-release-evidence.sh` (T6e) |
| Release-branch-empty evidence with a real per-attempt correlation key | `component_release_evidence.v1` record produced via `setup-component-release-fixture.sh`'s normal fixture path against a real `--release-branch` (so `target_binding.release_correlation_key` is genuinely computed from that attempt branch, not a fixed/contract-level value), then mutated to set the top-level `release_branch` to `""` (or remove the key) while leaving `target_binding.release_correlation_key` unchanged — otherwise a valid producer-shaped record. Using a fixed, attempt-independent correlation key here would let this fixture pass the new guard for the wrong reason: it would never exercise the disagreement between the evidence's recorded per-attempt key and the key cleanup's target re-resolution computes when `--release-branch` is omitted, which is exactly the case that exposes whether the guard runs before or after the six `compare_component_field` calls | New temp fixture inside `tests/test-prepare-release-tracker-cleanup.sh` (T20c) |
| Empty-identity evidence (cleanup) | `component_release_evidence.v1` records whose `target_binding.contract_revision` is `""`; a second variant with `target_binding.release_correlation_key: ""`; a third with `target_binding.canonical_repository_identity: ""`; a fourth with `target_binding.routing_outcome: ""`; a fifth with `target_binding.selected_product_repo_key: ""` (or the key absent); a sixth family of six variants, each with exactly one `target_binding.artifact_owners` sub-field (`release`, `ci`, `github_release`, `deployment`, `cleanup`, `tracker`) set to `""` and the other five populated — otherwise a valid producer-shaped record | New temp fixtures inside `tests/test-prepare-release-tracker-cleanup.sh` (T19, T20, T20b, T20d, T20e, T20f — T20f exercised once per `artifact_owners` sub-field) |
| Version-bound evidence | `component_release_evidence.v1` with `component_tag: "mobile-v1.4.0"`, `component_version: "1.4.0"` | `write_evidence` in `tests/test-delivery-bundle-manifest.sh` (extend the existing helper with a `component_version` positional) |
| Version-unbound evidence | Same record with `component_version: null` | `write_evidence` invoked with an empty version (T7) |
| Wrong-routing evidence | `routing_outcome: "single_repo_release"` with otherwise valid hub identity fields | `tests/test-component-milestone-reconciliation.sh` (T12) |
| Hub-fact-smuggling evidence | Producer-shaped record that also carries `hub_tracker_reconciliation_outcome: "complete"` and `child_release_state: "released"` | `tests/test-component-milestone-reconciliation.sh` (T13, T14) |
| Invalid `evidence_state` evidence | Producer-shaped record with `evidence_state: "totally-fine"` | `tests/test-component-milestone-reconciliation.sh` (T15) |
| Degraded `evidence_state` evidence | Producer-shaped records with `evidence_state` of `partial`, `missing`, and `released` | `tests/test-component-milestone-reconciliation.sh` (T15a, T15b) |
| Milestone fixture | Hub config plus `gh` stub call log, as today | `scripts/development-workflow/tests/setup-component-milestone-fixture.sh` (existing; extended with `component_version`) |
| Assurance fixture | Valid and `release_contract: "garbage"` variants | `scripts/development-workflow/tests/setup-multi-repo-release-assurance-fixture.sh` (existing, unchanged) |

---

## Documentation Updates

The developer executes these after implementation; they are only identified here.

- [ ] `docs/workflow/development-workflow/component-release-evidence-contract.md` — **create.**
      Sections: (1) the six trust classes and each one's consumer duty, stating explicitly
      how `producer_required_nullable` differs from `producer_required` in its `null` handling,
      and how `hub_input` differs from `hub_input_identifier` in closed-enum validation (D13);
      (2) the producer's emitted-field contract table (16 fields, each carrying exactly one of
      `producer_required`, `producer_required_nullable`, `producer_conditional`) — AC-5;
      (3) the field x consumer trust matrix — AC-1; (4) the `evidence_state` disposition
      table from D9, covering every enum member plus the unknown and absent cases;
      (5) fields the producer never emits and which may never be sourced from an evidence
      file; (6) Known gaps, carrying RESIDUAL-1 through RESIDUAL-6 verbatim with their
      rationales.
- [ ] `docs/workflow/development-workflow/repository-modes.md` — in the paragraph beginning
      "`scripts/development-workflow/component-release-evidence.sh` renders deterministic
      ..." (around line 73), link the new contract document and state that the producer
      refuses to emit on empty identity fields. In the
      `component-milestone-reconciliation.sh` paragraph (around line 101), correct the list of
      matched facts: `hub_tracker_reconciliation_outcome` and `child_release_state` are
      hub-supplied flags, not evidence fields.
- [ ] `docs/workflow/development-workflow/multi-repo-release-adoption.md` — in the evidence
      shape-check paragraph (around lines 102-110), state the `attestation` trust class
      explicitly, name the six fields with no format validator (RESIDUAL-4), add
      `trust_class` to the harness output list (around line 112), and link the contract
      document.
- [ ] `docs/workflow/development-workflow/cross-repo-pr-flow.md` — the producer snippet
      (around lines 59-70) renders a `pending` record with no tag. Add the second,
      post-release re-render that binds `--component-tag` and `--component-version`, and state
      that bundle attachment requires that re-rendered file (GAP-11). Keep the
      `<!-- workflow-shell-contract: bash-zsh -->` marker on every fenced snippet.
- [ ] `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md` — same
      two-phase correction for the producer snippet (around lines 158-170) so the documented
      sequence can actually reach the `update-component` snippet (around lines 183-198)
      without `component_tag_unbound`. Keep the shell-contract markers.
- [ ] `scripts/development-workflow/README.md` — update the `component-release-evidence.sh`
      usage block (around lines 348-368) with `--component-tag` and `--component-version`;
      note that `--component-version` is now required on `delivery-bundle-manifest.sh
      update-component` (around line 430); note the new `TRUST_CLASS` output of
      `multi-repo-release-assurance.sh` (around line 383); link the contract document from
      each of the five helper sections.
- [ ] `.agents/skills/prepare-release/SKILL.md` — step 8 currently says the evidence "must
      include `hub_tracker_ref`, `hub_tracker_reconciliation_outcome` ... and
      `child_release_state`". Correct it: the evidence must include `hub_tracker_ref`,
      `cleanup_outcome` of `complete`, and a bound `component_tag`/`component_version`; the
      reconciliation and child-release states are supplied as flags to
      `component-milestone-reconciliation.sh` (GAP-12).
- [ ] `AGENTS.md` — no change. It does not document these helpers or the evidence contract.
- [ ] `docs/project/*.md`, `docs/best-practices/*.md` — no change. These are template
      placeholders in this repository and describe no release-evidence contract.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Tightened emission preconditions reject evidence a downstream `workflow_hub` adopter already persisted | Low | Med | The brief records that this subsystem "should not be relied on for release gating in a `workflow_hub` deployment" until this audit lands, so no adopter should hold trusted records. The changelog fragment states the breaking preconditions and the remedy (re-render the evidence). |
| Making `--component-version` required breaks an out-of-repository caller | Low | Med | Every in-repository caller already passes it (Verification Log). The failure is a loud exit-2 argparse error naming the flag, not silent misbehavior. |
| Removing the `hub_tracker_reconciliation_outcome` / `child_release_state` evidence fallback breaks a real caller | Low | Med | D5 records the evidence that the documented caller is unreachable through the `schema_version` gate. Tests T13/T14 pin the new behavior, and the blockers name the missing flag. |
| Rejecting `--evidence-file` in `single_repo` mode surprises an operator mid-release | Low | Low | Recovery is to omit the flag. The alternative — silently ignoring a supplied evidence file — is the exact false-assurance the audit exists to remove. |
| The matrix is published but drifts as the helpers evolve | Med | Med | T2 asserts the rendered record's full top-level key list against a hardcoded 16-key list mirroring the emitted-field contract table, so any field added to or removed from the producer's `jq` emission object without a matching update to T2's own list fails `test-component-release-evidence.sh`. That guards drift between the running producer and T2's list; it is not a mechanical check that either one still matches the contract document's table, and this plan invents no tooling to make it one — a maintainer who updates the code and T2's list together while forgetting the table would introduce undetected drift there, which is recorded as RESIDUAL-6 (`out_of_scope`) rather than claimed as an anti-drift mechanism for the contract table itself. The Verification Log enumeration and smoke Step 14 are manual re-checks on top of it. The consumer axis has no equivalent automated guard, which is why Implementation Order step 2 re-runs the enumerations before any code is written. |
| AC-4's "confirmed to fail before its fix" is skipped under time pressure | Med | High | The Implementation Order makes red-capture a numbered step before each fix, and the residual/completion evidence on the PR must contain the red-then-green pairs. |
| This plan changes the published `component_release_evidence.v1` contract (adds `component_version`; tightens `canonical_repository_identity`, `release_correlation_key`, `contract_revision`, `routing_outcome`, every `artifact_owners` sub-field, and the routed case of `selected_product_repo_key` from optional-empty-tolerant to required-non-empty at the producer; separately tightens `release_branch` from conditionally-matched to unconditionally-required-non-empty at cleanup) and a later revert of that contract has no stated path | Low | Low | Reverting is a straightforward code revert: the producer and all four consumers change together in this plan's commits, so there is no partial-revert skew where one file expects the new shape and another still expects the old one. Per Dependencies, `WORKFLOW_MODE` resolves to `single_repo` in this repository and no `workflow_hub` block is configured, so this repository itself persists no `workflow_hub` evidence record today for a revert to break. The bounded residual risk is a future `workflow_hub` adopter of this template: `component-release-evidence.sh`'s output is a short-lived, single-release CLI artifact that is generated and consumed synchronously within one release attempt (bundle attach, reconciliation, cleanup all read the same file produced moments earlier), not a durable append-only log, so an adopter's release attempt straddling a future revert boundary can only present an older, more permissive consumer with a newer, stricter-shaped record — which the permissive consumer already accepts, since it is a superset of what it requires — never the reverse. No verification log entry in this plan measures adopter behavior beyond this repository, so this statement is scoped to what the Dependencies section already establishes and claims no more. |

---

## Code Samples

None. Every change is described in prose in the Layer-by-Layer section with the exact file,
function, and error code to add; no illustrative implementation code is included, so no sample
can be mistaken for production code.

---

## Implementation Order

1. **Re-verify the operational assumption.** Re-read `.ai-dev-workflow.yaml` for a `mode:`
   key. Stop and escalate if one has appeared (see the Cross-Cutting Operational Assumption
   Check).
2. **Re-run the Verification Log enumerations** at the implementation HEAD and confirm the
   producer still emits 15 fields and the consumer read sets are unchanged. If they differ,
   update the matrix before writing code.
3. **Write the contract document** `component-release-evidence-contract.md` first. It is the
   specification the code changes implement, and drafting it surfaces any matrix cell that is
   still ambiguous.
4. **Add the tests for the producer** (T1-T6e, including T5b, T6c, T6d, and T6e — T6d run once per
   `artifact_owners` sub-field, six red-then-green pairs; T6b is the red-capture exemption). Run
   `bash scripts/development-workflow/tests/test-component-release-evidence.sh`
   and capture the failures.
5. **Implement the producer changes** (D1, D3, D4). Re-run the suite green.
6. **Add the red tests for `delivery-bundle-manifest.sh`** (T7-T11), capture failures.
7. **Implement the bundle changes** (D2, GAP-1, GAP-9, enum validation). Re-run green.
8. **Add the red tests for `component-milestone-reconciliation.sh`** (T12-T18, including
   T15a; T15b is the red-capture exemption for this suite), capture failures.
9. **Implement the reconciliation changes** (GAP-4, D5, D9, D6, `trust_basis`). Re-run green.
10. **Add the red tests for cleanup and assurance** (T19-T22, including T20b, T20c, T20d, T20e,
    and T20f — T20f run once per `artifact_owners` sub-field, six red-then-green pairs; T22 is
    the red-capture exemption for this suite), capture failures.
11. **Implement the cleanup precondition** (GAP-8, GAP-13, D12) and the assurance
    `trust_class` output (D8). Re-run both suites green.
12. **Update the fixture helpers** (`setup-component-release-fixture.sh`,
    `setup-component-milestone-fixture.sh`) with `component_version`, then re-run all seven
    suites listed in the Testing Strategy.
13. **Execute the Documentation Updates** section, including `.agents/skills/prepare-release/SKILL.md`.
14. **Add the changelog fragment** `changelog.d/1529.fixed.delivery-bundle-evidence-trust-boundary.md`
    with exactly this body, **before** the lint gates in step 15 — this way the same
    `markdownlint-cli2 "changelog.d/**/*.md"` invocation that step 15 runs actually validates the
    fragment this plan adds, instead of running against `changelog.d/` before the fragment exists:

    ```markdown
    - **Close the delivery-bundle evidence trust boundary** (#1529): the component release evidence contract is now documented field by field — which fields the producer always emits, which it emits only on request, and which are hub-supplied and must never come from an evidence file — together with a trust matrix stating each consumer's duty for every field. `component-release-evidence.sh` binds `component_version` alongside `component_tag`, charset-validates both, and refuses to emit a record whose repository identity, release correlation key, or contract revision is empty, so consumers can rely on presence. `delivery-bundle-manifest.sh` now requires `--component-version` and rejects it as unbound or mismatched rather than recording an unverified shipped version. `component-milestone-reconciliation.sh` requires hub-routed evidence, takes the hub tracker reconciliation outcome and child release state only from its own flags instead of falling back to the product-supplied evidence file, rejects unrecognized and incomplete evidence states, and refuses a silently ignored evidence file in single-repository mode. Release cleanup rejects evidence with empty identity fields, and the adoption assurance harness reports that its scenario evidence is self-attested rather than verified. Known gaps that remain — the undefined semantics of `hub_tracker_ref`, the hub-checkout-scoped cleanup lease, and the absent release-tag deletion — are recorded in the contract document instead of being left implicit.
    ```

15. **Run the doc and lint gates**: `bash scripts/development-workflow/tests/test-workflow-hub-docs.sh`,
    `npx markdownlint-cli2 "docs/workflow/**/*.md" "docs/testing/workflow/1529-*.md" "changelog.d/**/*.md"`,
    and `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop` for the
    edited doc snippets. Because step 14 already created the changelog fragment, this pass lints
    it along with every other edited doc — no second, narrower lint invocation is needed.
16. **Walk the smoke test runbook** end to end and record PASS/FAIL per step.
17. **Write the residual evidence file** described in the Residual Verification Strategy and
    confirm `./scripts/development-workflow/scope-residual-gate.sh verify --issue-title "<#1529 title>" --issue-body-file <body> --evidence <path>`
    reports `RESULT=pass`.

---

## Acceptance Criteria Traceability

| Brief acceptance criterion | Where satisfied | Test / evidence |
| --- | --- | --- |
| A documented trust matrix covering every `component_release_evidence.v1` field against every consumer | New `component-release-evidence-contract.md` section 3; the matrix in this plan is its source | The published matrix's field column, diffed against the Producer emitted-field contract table (16 rows) and the never-emitted-fields list (7 rows), shows zero missing and zero extra fields across all four consumer columns (`delivery-bundle-manifest.sh`, `component-milestone-reconciliation.sh`, `multi-repo-release-assurance.sh`, `prepare-release-post-merge-cleanup.sh`) — a check that fails if the matrix section is absent, truncated, or omits any field, unlike a bare field-enumeration count. Verification Log field enumeration (15 emitted + never-emitted rows) x 4 consumers corroborates the source counts the diff is run against |
| No consumer treats a missing overridable field as a match | GAP-1 (bundle `component_version`), GAP-4, GAP-5, GAP-6, GAP-7, GAP-8, GAP-13; `component_tag` already fixed in rounds 3-4 and pinned by existing tests | T7, T12, T13, T14, T15, T15a, T16, T19, T20, T20b, T20c, T20d, T20e, T20f |
| `component_version` is bound and matched wherever a caller can supply it | D1 (producer emits it), D2 + GAP-1 (bundle requires and matches); reconciliation accepts no `component_version` override on the hub path, and GAP-7 closes the `single_repo` `--version` surface | T1, T2, T7, T8, T9, T16, T17 |
| Regression tests assert rejection for each fabricated-value case, each confirmed to fail before its fix | Testing Strategy AC-4 discipline; Implementation Order steps 4, 6, 8, 10 capture red before green | T1-T21 other than T6b and T15b (including T5b, T6a, T6c, T6d, T6e, T15a, T20b, T20c, T20d, T20e, and T20f) with captured red-then-green output on the implementation PR — T6d and T20f each capture six pairs, one per `artifact_owners` sub-field; T6b, T15b, and T22 are the three declared red-capture exemptions and are recorded green-before and green-after |
| The producer's emitted-field contract is documented, so a future consumer can tell required from optional without reading the producer | New contract document section 2 (the 16-field table, each field carrying exactly one class) and section 4 (never-emitted fields); no field contradicts the class it carries, so the class alone yields the duty | Document review; T2 pins the `null` emission of an unsupplied conditional field, T6a/T6e pin the two directions of the `producer_required_nullable` boundary (`null` if and only if `single_repo_release` routing — T6a pins that `component_release_routed` requires non-`null`, T6e pins that `single_repo_release` requires `null`) while T6b pins the `null` passthrough this plan leaves unchanged, and T6c/T6d pin the `producer_required` promise for `routing_outcome` and `artifact_owners` |

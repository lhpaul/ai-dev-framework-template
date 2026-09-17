# Component Release Evidence Contract

This document is the trust boundary for `component_release_evidence.v1`: which
fields `component-release-evidence.sh` emits, which trust class each field
carries, and what each consumer must do with that field. A future consumer
should be able to tell required from optional from this document alone, without
reading the producer source.

Related helpers:

- Producer: `scripts/development-workflow/component-release-evidence.sh`
- Consumers: `delivery-bundle-manifest.sh`, `component-milestone-reconciliation.sh`,
  `multi-repo-release-assurance.sh`, `prepare-release-post-merge-cleanup.sh`

---

## 1. Trust classes

Every field that reaches a consumer belongs to exactly one class, and the class alone
determines the consumer's duty: no field is an exception to the class it carries. That is what
lets a future consumer tell required from optional without reading the producer.
`release_branch` and `hub_tracker_ref` narrow that duty at exactly one consumer each, for a
stated reason rather than as an unexplained exception — see the note preceding the Trust matrix
table below.

| Class | Definition | Consumer duty |
| --- | --- | --- |
| `producer_required` | `component-release-evidence.sh` always emits the field with a non-empty value, and refuses to emit a record at all when it cannot. The value is never `null` and never `""`; a field that may legitimately be `null` is `producer_required_nullable` instead, never this class | Require non-empty. Where the caller can also supply the same fact, **require-and-match**. Never infer from absence. |
| `producer_required_nullable` | The producer always emits the **key** and still refuses to emit a record when it cannot resolve the field, but the value is legitimately JSON `null` in exactly one defined case: `single_repo_release` routing, where `component-release-target.sh` emits the key empty (line 257) and renders it as `null` (line 105). `selected_product_repo_key` is the only member. D4 guards **both** directions of the relationship, not only one: under `component_release_routed` routing the value must be non-empty (emission refused otherwise), and under `single_repo_release` routing the value must be **exactly JSON `null`** — emission refused whenever it is anything else, which is three distinct rejections, not one: a non-empty string, an empty string `""`, or the key being absent from the target/binding file entirely — so `null` and `single_repo_release` routing imply each other in both directions, not merely by convention, and an empty string is never treated as an acceptable stand-in for `null` | Require the key to be **present**, and accept only a non-empty string or JSON `null`; an absent key or `""` is a rejection. Treat `null` as **not bound**: never match it against a caller-supplied value and never read agreement into it. A consumer must first require `routing_outcome == component_release_routed`, after which the duty is identical to `producer_required` — require non-empty, and **require-and-match** where the caller can also supply the fact. |
| `producer_conditional` | The producer emits the field only when the corresponding flag was supplied; otherwise it emits `null` | A consumer that accepts a caller override must **reject when the evidence does not bind the field** (`*_unbound`), then match (`*_mismatch`). "Check only if present" is forbidden. |
| `hub_input` | A hub-owned fact expressed as a **closed-enum outcome value** that the product release producer cannot know, supplied by the hub caller at consumption time. Its only members are `hub_tracker_reconciliation_outcome` and `child_release_state` — the closed-enum subset of hub-supplied facts | Require the flag: the caller must supply it, or — in the one documented case, described in the note preceding the Trust matrix table below, where a consumer defines its own explicit "not yet known" default for an omitted flag, and that default is itself a member of the closed enum and never satisfies that consumer's own completion gate — accept that default in its place. Either way, validate the resulting value against the closed enum and fail closed on any unknown value, and **never** fall back to the evidence file for it. |
| `hub_input_identifier` | A hub-owned **identifier** — a component key, tracker issue number, source PR reference, or release PR reference — that the product release producer cannot know, supplied by the hub caller at consumption time. Its members are `component_key`, `child_item`, `source_pr`, `release_pr`, and reconciliation's `--issue`. Unlike `hub_input`, its values are open-ended (repository keys, PR/issue numbers), not drawn from a fixed vocabulary, so no closed-enum validation applies to this class | Require the caller to supply the value; **never** source it from the evidence file. Apply whatever narrower per-field duty the trust matrix cell states: require-and-match against a specific, separately classified evidence field where the cell says so (e.g., `component_key` against `selected_product_repo_key`), or record it for audit without gating on it where the cell says `record`. No charset or shape validation applies unless a specific matrix cell states one — this class is a required, unvalidated-format identifier, not a closed enum. |
| `attestation` | A self-declared reference string in an assurance summary; the referenced artifact is not loaded | Shape-check only where this codebase already establishes an objective format. Record the class in output so no downstream reader mistakes it for verification. |

---

## 2. Producer emitted-field contract

Target state (`component_release_evidence.v1`, 16 top-level fields):

| Field | Class | Emission rule |
| --- | --- | --- |
| `schema_version` | `producer_required` | Constant `component_release_evidence.v1` |
| `target_binding` | `producer_required` | Whole `component_release_target.v1` object, verified `mutation_allowed: true` |
| `routing_outcome` | `producer_required` | Copied from the target binding after `compare_field` agreement; **new**: emission refused when empty, **and** emission refused when the (non-empty) value is anything other than exactly `component_release_routed` or `single_repo_release` — the only two outcomes `component-release-target.sh` ever emits — so an unrecognized value such as `unknown` is rejected on its own, before either of `selected_product_repo_key`'s two conditional branches below is even consulted (D4) |
| `selected_product_repo_key` | `producer_required_nullable` | Copied from the target; the key is always emitted, and the value is legitimately `null` for `single_repo_release` routing. **New**: once `routing_outcome`'s own closed-enum precondition (above) has already passed, emission is refused when `routing_outcome` is `component_release_routed` and the value is empty, **and** emission refused when `routing_outcome` is `single_repo_release` and the value is not exactly JSON `null` — an empty string `""` or an absent key are rejected exactly like a non-empty string — both directions of the `null` ⇔ `single_repo_release` relationship are enforced (D4) |
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

Fields the producer **never** emits: `evidence_state`, `hub_tracker_reconciliation_outcome`,
`child_release_state`, `component_key`, `child_item`, `source_pr`, `release_pr`. Six of the
seven — every field except `evidence_state` — may never be sourced from an evidence file at
all: they are `hub_input` or `hub_input_identifier` facts that only the hub caller can supply,
and a consumer must take them as flags, never as a fallback to whatever evidence-shaped JSON it
was given, per each class's consumer duty above (`hub_tracker_reconciliation_outcome` and
`child_release_state` under `hub_input`, closed by GAP-5/D5; `component_key`, `child_item`,
`source_pr`, and `release_pr` under `hub_input_identifier`, which states the same "never source
it from the evidence file" duty directly and never had an evidence-file fallback to remove).
`evidence_state` is the one documented exception to "never sourced from an evidence file": unlike
the six hub-owned fields above, which `classify_component`'s hub path takes only as explicit CLI
flags and never reads from the evidence file, `evidence_state` is read directly from whatever
`--evidence-file` contains (`evidence_state()`, called only from `classify_component`). That file
is always `schema_version`-gated to `component_release_evidence.v1` first (line 257), so it can
never be a manifest-derived component view — a bundle component carries `evidence_schema_version`,
not `schema_version` (see `component_from_evidence`) — exactly the unreachable path D5 already
establishes. A producer-emitted file legitimately has no `evidence_state` key at all (D9's
`absent` row, synthesized as `verified` when `schema_version` matches, which it always does once
`classify_component` reaches this point); a present value is therefore always consumer-fabricated
inside a hand-authored evidence file, never producer-attested, which is exactly why D9 gates it
behind a closed enum (GAP-6) instead of passing it through unchecked. `delivery-bundle-manifest.sh`
separately sets `evidence_state` on its own component view for
`component-milestone-reconciliation.sh`'s distinct manifest-component path
(`component_blocker`/`component_is_released`, reached only through `inspect-parent`/`apply-parent`,
never through `classify_component`); that path is unrelated to and untouched by this plan, keeps
its pre-existing `stale`/`conflicting`-only check unchanged, and is not subject to the GAP-6/D9
closed-enum fix — D9's introductory survey cites its `released` value only to justify listing
`released` as a legitimate enum member on the hub path, not to claim the closed-enum fix applies
to that separate path too. "Never emits" therefore means "the producer's own contract carries no
such key," not "a present value is forbidden everywhere on the hub path."

---

## 3. Trust matrix — field × consumer

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

`release_branch` and `hub_tracker_ref` are `producer_required`, and each carries a `record`-only
duty at `delivery-bundle-manifest.sh` — after GAP-9 for `release_branch` — while a separate,
independently-invoked consumer carries a non-empty check on that same field name. This is a
genuine residual limitation of the bundle's own guarantee, not a closed guarantee that is merely
enforced somewhere else: `delivery-bundle-manifest.sh`'s own `cmd_finalize` /
`inspect_manifest` / `blocker_for_component` code path never invokes
`prepare-release-post-merge-cleanup.sh` or `component-milestone-reconciliation.sh`, so a bundle
can reach `finalized` status while its component record carries an empty `release_branch` or
`hub_tracker_ref` — the other consumer's non-empty check only ever runs if and when something
separately invokes that other, decoupled binary against the same evidence, which bundle
finalization neither requires nor verifies. The two fields are not in the same starting state
today: `release_branch` is not stored by `delivery-bundle-manifest.sh` at all currently
(`component_from_evidence` has no `release_branch` key) — GAP-9 is what newly introduces
`record`-only storage for it here, deliberately excluded from `stable_fields` because the value
is audit metadata that can legitimately change across a re-tag under a new `release_pr` (see the
`delivery-bundle-manifest.sh` implementation step); once GAP-9 ships, the field's non-empty duty
is enforced only when `prepare-release-post-merge-cleanup.sh` is later invoked against that same
evidence file, and GAP-13 closes that consumer's own "compare only if present" gap to "require
non-empty before comparing" (D12) — a guarantee about cleanup's own input, not about bundle
finalization's. `hub_tracker_ref` is already stored today, pre-existing and unchanged by this
plan (`component_from_evidence`'s `"hub_tracker_ref": evidence.get("hub_tracker_ref")`), with no
non-empty check anywhere in `delivery-bundle-manifest.sh` — `blocker_for_component`'s `missing`
list covers only `selected_product_repo_key`, `canonical_repository_identity`,
`release_correlation_key`, and `contract_revision`. Its non-empty duty is enforced only when
`component-milestone-reconciliation.sh`'s hub path is later invoked against that same evidence
(pre-existing `required_identity` check, unchanged by this plan) — again, a guarantee about that
other consumer's own input, not about the bundle's. Binding `hub_tracker_ref` further — matching
it against `--issue` or `--child-item` — is a separate, already-recorded gap (RESIDUAL-1); this
paragraph is about whether either field is required non-empty at the point the bundle itself
records it, which for both fields it is not. Recorded as RESIDUAL-8, filed as issue #1747
("decide: should `release_branch` / `hub_tracker_ref`'s `producer_required` non-empty duty
actually be enforced, and where?").

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
| `ci_outcome` | `producer_required` | **GAP-14** accepted `skipped`, a value the producer can never emit -> `require` in `passed\|not_applicable` (a present non-string value is also rejected safely today: tuple membership compares by equality, not by hashing — verified) | **GAP-14** accepted `skipped` on the hub path -> `require` in `passed\|not_applicable`; **GAP-16** a present non-string value (e.g. a JSON array or object) raised an uncaught `TypeError` via unguarded set-membership -> type-guard before the check, fail closed with `ci_outcome_invalid` | `n/a` | `n/a` |
| `deployment_outcome` | `producer_required` | `require` in `recorded\|not_applicable` (a present non-string value is also rejected safely today: tuple membership compares by equality, not by hashing — verified) | `require` in `recorded\|not_applicable`; **GAP-16** a present non-string value raised the identical uncaught `TypeError` as `ci_outcome` via unguarded set-membership -> type-guard before the check, fail closed with `deployment_outcome_invalid` | `n/a` | `n/a` |
| `cleanup_outcome` | `producer_required` | `require` == `complete` | `require` == `complete` | `n/a` | **GAP-15** empty/absent falls through to the same branch as any other non-`complete` value -> require non-empty first; `complete` is the idempotent-rerun signal |
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

---

## 4. `evidence_state` disposition (hub evidence path)

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

The `any other string, or a non-string` row and the `absent` row are mutually exclusive on
**key presence**, not on value shape: the closed-enum check runs only when `evidence_state` is
present in the evidence object at all (any JSON value — an unrecognized string, `null`, a
number, a boolean, or an array all count as "present" and therefore fall into the `any other
string, or a non-string` row). The `absent` row applies only when the key is missing from the
evidence object entirely, and that branch is untouched by this plan (T15c pins it). A present
`evidence_state: null` is therefore rejected with `invalid_evidence_state` (T15d), not silently
treated like a missing key.


---

## 5. Fields the producer never emits

The producer **never** emits: `evidence_state`, `hub_tracker_reconciliation_outcome`,
`child_release_state`, `component_key`, `child_item`, `source_pr`, `release_pr`.

Six of the seven — every field except `evidence_state` — may never be sourced from
an evidence file at all: they are `hub_input` or `hub_input_identifier` facts that
only the hub caller can supply, and a consumer must take them as flags, never as a
fallback to whatever evidence-shaped JSON it was given.

`evidence_state` is the one documented exception: unlike the six hub-owned fields
above, which `classify_component`'s hub path takes only as explicit CLI flags and
never reads from the evidence file, `evidence_state` is read directly from whatever
`--evidence-file` contains (`evidence_state()`, called only from `classify_component`).
That file is always `schema_version`-gated to `component_release_evidence.v1` first,
so it can never be a manifest-derived component view — a bundle component carries
`evidence_schema_version`, not `schema_version`. A producer-emitted file legitimately
has no `evidence_state` key at all (synthesized as `verified` when `schema_version`
matches); a present value is therefore always consumer-fabricated inside a
hand-authored evidence file, never producer-attested, which is why it is gated
behind the closed enum in section 4.

`delivery-bundle-manifest.sh` separately sets `evidence_state` on its own component
view for `component-milestone-reconciliation.sh`'s distinct manifest-component path
(`inspect-parent`/`apply-parent`, never through `classify_component`); that path is
unrelated to this contract's closed-enum fix and keeps its pre-existing
`stale`/`conflicting`-only check unchanged.

---

## 6. Known gaps

### Residual register (deliberately not closed by this audit)

| ID | Residual | Disposition | Rationale |
| --- | --- | --- | --- |
| RESIDUAL-1 | `hub_tracker_ref` is never matched against `--issue` (reconciliation) or `--child-item` (bundle), so any issue can be stamped with a valid milestone | `out_of_scope` | The field's semantics are genuinely undefined: `05-prepare-release-protocol.md` documents `<tracker-item-or-epic>`, `cross-repo-pr-flow.md` uses `#123`, and `tests/setup-component-release-fixture.sh` uses `fixture:1356`. Binding it requires first deciding whether it names the component child, the parent epic, or the delivery bundle — a contract decision, not an audit finding. Recorded in the contract doc's Known gaps. |
| RESIDUAL-2 | `component_tag` has no enforced relation to the version segment of `release_branch` (fixtures pair tag `mobile-v1.4.0` with branch `mobile-app/release/v1.0.0`) | `out_of_scope` | No normalization rule exists in this codebase; inventing one would be a guess and would break existing fixtures. See Decision D1. |
| RESIDUAL-3 | `apply-component` mutates GitHub milestones from the evidence file alone, without re-resolving an independent target binding the way cleanup does | `out_of_scope` | Closing it changes the required CLI contract of a mutating helper and adds a hub-config prerequisite to every caller — larger than this audit and not named by any acceptance criterion. |
| RESIDUAL-4 | `multi-repo-release-assurance.sh` applies no shape validator to `hub_config`, `product_config`, `run_id`, `step_id`, `supersedes`, `idempotency_guard` | `out_of_scope` | This codebase establishes no objective format for any of the six. The existing validators were deliberately limited to fields with an established format; inventing formats would produce false rejections. |
| RESIDUAL-5 | `prepare-release-post-merge-cleanup.sh`'s cleanup lease is hub-checkout-scoped, not cross-machine; and it has no release-tag deletion logic at all, while the smoke-test document's `remote_tag_deleted` field describes functionality that was never implemented | `out_of_scope` | Explicitly carried forward from the brief's "Residual limitations recorded at merge" section, which states these are not part of this audit. Recorded in the contract doc so they are not lost. |
| RESIDUAL-6 | T2 asserts the rendered record's key list against a hardcoded 16-key list inside the test file, not against the emitted-field contract table itself; nothing in this plan mechanically derives one from the other, so a maintainer who updates the producer's `jq` emission object and T2's hardcoded list together, while forgetting the contract table, introduces silent drift between the running code and the published documentation that no test catches | `out_of_scope` | This codebase has no existing tooling that extracts a field list from a markdown table for use in a test assertion (checked: no such helper exists under `scripts/lint/` or `scripts/development-workflow/`), and inventing one is outside this audit's boundary-closing scope — it would add new parsing/tooling surface the brief never asked for. T2's real, narrower guarantee is drift detection between the running producer and T2's own list; the gap between that list and the contract table is accepted here rather than assumed away. |
| RESIDUAL-7 | Spec #1357 (`docs/specs/developments/20260731164352_1357-delivery-bundle-issue-manifest-workflow/1_1357-delivery-bundle-issue-manifest-workflow_specs.md`, lines 101-103) documents `ci_outcome: "skipped"` as a contractually valid value for a product configured with `ci_policy: none`, but GAP-14 narrows both consumers to reject it, because `component-release-evidence.sh`'s `--ci-outcome` enum has never included `skipped` (it is, and has always been, `pending\|passed\|failed\|not_applicable`) and no `ci_policy`-equivalent field exists anywhere in the producer or any consumer to condition admission of it | `out_of_scope` | GAP-14 audits the producer's actual, currently running contract: a value the producer can never legitimately emit is forgeable by definition and must be rejected regardless of what a separate spec independently promises. Spec #1357's `skipped` allowance is therefore presently unimplemented/aspirational, not a contradiction this plan can resolve — closing it would mean one of two decisions genuinely outside this audit's boundary-closing scope: (a) build `ci_policy` binding end-to-end (the producer would need to accept and emit it, and at least one consumer would need to condition admission of `skipped` on it) — a feature spanning multiple helpers, not an audit finding; or (b) retire spec #1357's clause — a product decision to drop a documented capability, which this audit should not make as an unreviewed side effect of narrowing an enum. Filed as issue #1742 ("decide: does the delivery bundle support CI-not-required products? Build `ci_policy`, or retire spec #1357's `ci_outcome: skipped` clause") so the deferral is traceable rather than silent, and left to a human product decision rather than resolved here. |
| RESIDUAL-8 | `release_branch` and `hub_tracker_ref`'s `producer_required` non-empty duty is, for each field, actually enforced only by a separate, independently-invoked consumer (`prepare-release-post-merge-cleanup.sh` via GAP-13 for `release_branch`; `component-milestone-reconciliation.sh`'s pre-existing hub path for `hub_tracker_ref`), and `delivery-bundle-manifest.sh`'s own `cmd_finalize`/`inspect_manifest`/`blocker_for_component` code path never invokes either of those other scripts — a bundle can reach `finalized` status while its component record carries an empty value for either field. The two fields start from different states: `release_branch` is not stored by `delivery-bundle-manifest.sh` today at all (GAP-9 newly introduces `record`-only storage for it); `hub_tracker_ref` is already stored today with no non-empty check anywhere in `delivery-bundle-manifest.sh` | `out_of_scope` | Closing this changes what `delivery-bundle-manifest.sh` itself guarantees about two `producer_required` fields — either adding an independent non-empty presence check in `component_from_evidence` (a new GAP with implementation instructions, red-before-green test coverage, and Trust Model narrative changes) or accepting today's cross-consumer, evidence-file-coupled enforcement as the intended design. Either is a product/scope decision, not a wording or test-fixture correction, and is outside this audit's boundary-closing mandate the same way GAP-14's `ci_policy` question was (RESIDUAL-7). Filed as issue #1747 ("decide: should `release_branch` / `hub_tracker_ref`'s `producer_required` non-empty duty actually be enforced, and where?") so the deferral is traceable rather than silent, and left to a human product decision rather than resolved here. |
| RESIDUAL-9 | Spec #1357 (`docs/specs/developments/20260731164352_1357-delivery-bundle-issue-manifest-workflow/1_1357-delivery-bundle-issue-manifest-workflow_specs.md`, lines 106-107) states that `hub_tracker_reconciliation_outcome: "deferred"` counts toward bundle finalization only "with an explicit human action that does not change the product component version," but no field, flag, or mechanism for recording, carrying, or verifying that human action exists anywhere in the producer or either consumer. Verified against the running code: `delivery-bundle-manifest.sh`'s `blocker_for_component` (line 195, reached from `cmd_finalize` via line 214) and `component-milestone-reconciliation.sh`'s `component_is_released` (line 526) both treat `hub_tracker_reconciliation_outcome in {"complete", "deferred"}` identically — `deferred` passes as non-blocking exactly like `complete`, with no check of any kind for a human action, unconditionally, every time | `out_of_scope` | Closing this is a product/scope decision, not an audit finding: either (a) build the human-action mechanism end-to-end — a recorded field, carried through evidence, and required by both finalization paths before a `deferred` outcome may count — new implementation scope across the producer and both consumers; or (b) tighten both consumers to never let `deferred` count, which silently decides a product question by removing a path spec #1357 deliberately provides. Both exceed this audit's boundary-closing mandate the same way GAP-14's `ci_policy` question did (RESIDUAL-7). Filed as issue #1754 ("decide: how does a deferred hub tracker reconciliation count toward bundle finalization? Spec #1357 requires an explicit human action that has no mechanism") so the deferral is traceable rather than silent, and left to a human product decision rather than resolved here. |

---

---

## 7. `classify_component` mutation eligibility (hub path)

### Decision gate — `classify_component` mutation eligibility (hub path)

This plan changes `classify_component`'s hub-path (`args.mode != "single_repo"`) decision on
whether a component release milestone may be mutated, gating that single decision on multiple
independent inputs — repository mode, `routing_outcome` (GAP-4, new), `evidence_state` (GAP-6,
D9), `hub_tracker_reconciliation_outcome` and `child_release_state` (GAP-5, D5), plus the
pre-existing `release_outcome`/`ci_outcome`/`deployment_outcome`/`cleanup_outcome` checks
(`ci_outcome` narrowed by GAP-14; `ci_outcome`/`deployment_outcome` type-guarded by GAP-16) — each
producing its own outcome branch, blocker set, and
`required_next_action`. This is the complex workflow decision gate the Document Quality Gate
log must classify as applicable; this table is that matrix.

**Repository mode is the first gate.** `args.mode == "single_repo"` never reaches any of the
checks below: it returns `non_hub_result`, a structurally separate decision with its own single
input (`--version` presence and shape) and its own mutation rule
(`mutation_allowed = args.target_kind == "component_child"`); `--evidence-file` is rejected
outright in this mode (GAP-7, D6). Everything below applies only once `args.mode` is a
recognized non-`single_repo` value (malformed `--mode` values are rejected at CLI-parse time by
`validate_mode`, exit `2`, before `classify_component` runs at all — a gate precondition, not a
row in this table).

**Table A — ordered preconditions (hub path, `args.mode != "single_repo"`).** Each row is
evaluated in this order; the run returns at the first one that fails, so only one row's outcome
ever applies to a given evaluation. Existing (pre-plan) rows are unchanged by this plan and are
listed for gate completeness; new/changed rows are marked.

| # | Precondition | On failure: `reconciliation_outcome` | `child_release_state` | `mutation_allowed` | Blocker | Required next action | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | `args.target_kind == "component_child"` | `milestone_target_not_allowed` | `pending` (base default, not overridden) | `false` | `milestone_target_not_allowed` | "component milestones may only be applied to component child issues" | existing |
| 2 | `--product-repo`, if supplied, matches the identifier charset | `component_release_not_ready` | `pending` (base default, not overridden) | `false` | `invalid_product_repository` | "provide a product repository key using letters, numbers, dot, underscore, or hyphen" | existing |
| 3 | `--product-repo` is supplied at all | `missing_product_selection` | `pending` (base default, not overridden) | `false` | `missing_product_selection` | "select exactly one product repository before component milestone reconciliation" | existing |
| 4 | `--component-tag`, if supplied, matches the identifier charset | `component_release_not_ready` | `pending` (base default, not overridden) | `false` | `invalid_component_tag` | "provide a component tag using letters, numbers, dot, underscore, or hyphen" | existing |
| 5 | `--component-tag` is supplied at all | `component_tag_missing` | `pending` (base default, not overridden) | `false` | `component_tag_missing` | "provide the released component tag before milestone reconciliation" | existing |
| 6 | `--evidence-file` is supplied and successfully loads — `load_json_file(args.evidence_file, "evidence", required=False)` returns a non-`None` value (see the note below Table A for what happens when a supplied file exists but fails to load) | `component_release_pending` | `pending` | `false` | `component_release_evidence_missing` | "attach component_release_evidence.v1 before milestone reconciliation" | existing |
| 7 | `evidence.schema_version == component_release_evidence.v1` | `component_release_not_ready` | `blocked` | `false` | `invalid_evidence_schema` | "provide evidence with schema_version component_release_evidence.v1" | existing |
| 8 | **New (GAP-4):** `stable_value(evidence, "routing_outcome") == "component_release_routed"`. Malformed and empty inputs take the identical branch: this is a single equality test, not an enum-membership check, so `""`, `null`, an absent key (`stable_value` returns `None`), and an unrecognized non-empty value such as `"unknown"` all fail the same way — there is no separate "malformed" outcome to enumerate. Placed immediately after row 7 (basic evidence-shape validity) and before row 9 (product-identity match), because whether the evidence describes a routed component release at all must be established before any product/component identity comparison is meaningful | `component_target_mismatch` | `blocked` | `false` | `routing_outcome_mismatch` | "correct the evidence's routing outcome to component_release_routed, or re-run component release routing, before mutation" | **new** |
| 9 | `stable_value(evidence, "selected_product_repo_key") == product_repo` | `component_target_mismatch` | `blocked` | `false` | `product_repository_mismatch` | "correct the selected child or component release evidence before mutation" | existing |
| 10 | `evidence.get("component_tag")` is truthy | `component_target_mismatch` | `blocked` | `false` | `component_tag_unbound` | "render component release evidence with --component-tag before mutation" | existing |
| 11 | `evidence_tag == component_tag` | `component_target_mismatch` | `blocked` | `false` | `component_tag_mismatch` | "correct the component tag or evidence before mutation" | existing |
| 12 | Each of `canonical_repository_identity`, `release_correlation_key`, `contract_revision`, `hub_tracker_ref` is non-empty via `stable_value` | `component_release_not_ready` | `blocked` | `false` | `missing_<field>` per missing field (may list more than one) | "repair incomplete component release evidence before mutation" | existing |
| — | All of rows 1-12 pass | *(proceed to Table B)* | | | | | |

Row 6's "does not load" outcome applies only to a genuinely absent evidence file — `--evidence-file`
not supplied, or supplied but naming a path that does not exist — because
`load_json_file(args.evidence_file, "evidence", required=False)` returns `None` in exactly those
two cases and reconciliation continues to the graceful `component_release_pending` result the row
describes. It does **not** apply when the named file exists but contains malformed JSON, or valid
JSON that is not an object: `load_json_file`'s `json.JSONDecodeError`/non-`dict` checks run
unconditionally, regardless of `required`, and call `fail("invalid_json", ...)`, which prints
`ERROR_CODE=invalid_json` to stderr and exits `1` immediately — terminating the process before it
ever reaches, or returns, the `reconciliation_outcome`/`child_release_state`/`mutation_allowed`
result shape any row in this table produces. Confirmed directly against `load_json_file` with
`'{'` (malformed JSON) and `'[]'`/`'null'` (valid JSON, not an object): all three raise
`ERROR_CODE=invalid_json`, not `component_release_pending`. This is a hard, pre-existing script
termination this plan does not change — like the malformed-`--mode` case above Table A, it is a
gate precondition outside this table's outcome schema, not a row failure this plan should
represent as producing `component_release_pending`.

**Table B — accumulating outcome (only reached once every Table A row passes).** Unlike Table A,
these checks do not short-circuit: every condition is evaluated independently and any number of
failing conditions append their own blocker to one shared `blockers` list. Missing/malformed
handling is per-field, matching each field's trust class:

| Input | Non-blocking value(s) | Blocking condition -> appended blocker | Status |
| --- | --- | --- | --- |
| `evidence_state` (absent key) | n/a — falls through to pre-existing `schema_version` synthesis (D9 `absent` row) | key absent **and** `schema_version` does not match -> `evidence_state_missing` | existing, unchanged |
| `evidence_state` (present) | `verified`, `released` | present and not a closed-enum member (any non-member string, `null`, or other non-string JSON value) -> `invalid_evidence_state`; `stale`/`conflicting` -> `{state}_component_evidence`; `missing` -> `missing_component_evidence`; `partial` -> `partial_component_evidence` | `invalid_evidence_state`/`missing_component_evidence`/`partial_component_evidence` **new** (GAP-6/D9); `stale`/`conflicting` existing |
| `release_outcome` | `completed` | anything else, or absent -> `release_outcome_{value\|missing}` | existing |
| `ci_outcome` | `passed`, `not_applicable` | present, a `str`, and not a closed-enum member (including the no-longer-accepted `skipped`) -> `ci_outcome_{value}`; present and not a `str` (a JSON array, object, number, boolean, or `null`) -> `ci_outcome_invalid`, evaluated **before** the closed-enum membership check so the check never receives a non-`str` value; absent -> `ci_outcome_missing` | narrowed (GAP-14); type-guarded **new** (GAP-16) |
| `deployment_outcome` | `recorded`, `not_applicable` | present, a `str`, and not a closed-enum member -> `deployment_outcome_{value}`; present and not a `str` -> `deployment_outcome_invalid`, evaluated **before** the closed-enum membership check, same reason as `ci_outcome`; absent -> `deployment_outcome_missing` | type-guarded **new** (GAP-16) |
| `cleanup_outcome` | `complete` | anything else, or absent -> `cleanup_outcome_{value\|missing}` | existing |
| `hub_tracker_reconciliation_outcome` (flag only, no evidence fallback) | `complete`, `deferred` | flag absent -> `hub_tracker_reconciliation_outcome_required`; flag present with any value other than exactly `complete` or `deferred` -> `hub_tracker_reconciliation_{value}`. This is a plain two-member equality test, not a separate enum-membership step: every other value blocks the same way, including other legitimate, non-terminal members of this field's own closed enum (`pending`, per the note preceding this table) and any unrecognized string alike — there is no third "recognized-but-not-yet-terminal" outcome that escapes the blocker (T13a pins the `pending` case) | fallback removed, `_required` blocker **new** (GAP-5/D5) |
| `child_release_state` (flag only, no evidence fallback) | `released`, `merged` | flag absent -> `child_release_state_required`; flag present with any value other than exactly `released` or `merged` -> `child_release_state_{value}`. Same plain two-member equality test as `hub_tracker_reconciliation_outcome` above: `pending` and every other non-member string block identically (T14a pins the `pending` case) | fallback removed, `_required` blocker **new** (GAP-5/D5) |

If the accumulated `blockers` list is non-empty, `reconciliation_outcome = component_release_not_ready`,
`mutation_allowed = false`, `required_next_action = "repair or retry component release evidence
before milestone mutation"` (Table B's own aggregate required-next-action, unchanged by this
plan), and `child_release_state` is resolved by precedence: `failed` when
`release_outcome == "failed"` or `child_state == "failed"`; else `blocked` when
`release_outcome == "blocked"`, `evidence_state` is `stale`/`conflicting`, **or the
`evidence_state` row above appended `invalid_evidence_state`, `missing_component_evidence`, or
`partial_component_evidence` (changed — GAP-6/D9)**; else `pending`. The `blocked` branch's
`evidence_state`-driven members are widened, not merely re-derived from the existing
`stale`/`conflicting` case: an evidence record that is present but incomplete or invalid
(`missing`, `partial`, or an unrecognized/`null` value) previously fell through this precedence
to `pending` because none of `release_outcome == "blocked"` or `evidence_state in
{"stale", "conflicting"}` matched it, even though the evidence-state blocker itself was already
new/changed by GAP-6/D9. Spec #1358's component-child transition table
(`docs/specs/developments/20260731193728_1358-component-milestones-release-statuses/1_1358-component-milestones-release-statuses_specs.md`,
lines 295-297) states that an existing but incomplete or invalid evidence record moves a
`pending` child to `blocked`, not that it stays `pending`, so leaving this branch unwidened
would misreport a repair-required state as ordinary in-progress work; this precedence change
closes that gap without altering the `stale`/`conflicting` branch's own pre-existing behavior.
This does not affect `component_release_evidence_missing` (Table A row 6, no evidence file at
all), which still resolves to `pending` unchanged — that is a distinct case (`evidence.get()`
returning `None` before Table B ever runs, and this plan's own `component_release_pending` /
`pending` result at row 6 is untouched), not one of the three evidence-state blockers this
paragraph widens, and matches spec #1358's own "no release evidence record remains pending"
rule. If the list is empty, `reconciliation_outcome = component_released`,
`child_release_state = "released"`, `mutation_allowed = true`, and `required_next_action =
"create or reuse the namespaced component milestone and assign it only to the component child"`
— the only path that allows mutation.

**Mirror surfaces and examples**: this table is the authoritative precedence source; the new
`component-release-evidence-contract.md` document (Documentation Updates, item 1) embeds a
verbatim copy of Table A and Table B (not a pointer into this plan), because `sync-manifest.yaml`
makes `docs/workflow/` `always_sync` to downstream template consumers while `docs/specs/` is
never synced, so a pointer from the synced contract document into this unsynced plan would be a
broken reference for that reader; this plan's copy remains the source the developer copies from
at implementation time, and the `repository-modes.md` reconciliation
paragraph (Documentation Updates, item 2) is corrected to describe `routing_outcome`,
`evidence_state`, and the two hub-input flags as the gate's combined inputs instead of
describing them as independent, unordered facts. T12 (routing mismatch), T13/T14 (hub-input
flags required), T13a/T14a (hub-input flags present but non-terminal, e.g. `pending`),
T15/T15a/T15d (evidence-state disposition), T24 (`ci_outcome: "skipped"`), and T25/T26
(`ci_outcome`/`deployment_outcome` present with a non-`str` JSON value) are the fabricated-value
tests that exercise Table A row 8 and the Table B rows respectively.

---


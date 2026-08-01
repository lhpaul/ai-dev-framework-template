# Multi-Repository Release Adoption

Use this guide when a repository adopts workflow-hub release ownership across
one or more product repositories. It defines the operating sequence and the
assurance evidence needed before a hub-managed multi-repository release is
treated as ready.

Related references:

- [Workflow hub setup](workflow-hub-setup.md)
- [Product repository injection](product-repo-injection.md)
- [Repository modes](repository-modes.md)
- [Cross-repository PR flow](cross-repo-pr-flow.md)
- [Prepare release protocol](protocols/05-prepare-release-protocol.md)

## Adoption Boundary

Adoption is prospective. It proves that new workflow-hub release runs can route
product-owned release artifacts, compose hub-owned delivery evidence, and
reconcile tracker release state without rewriting historical records.

Do not change existing product tags, historical changelog entries, historical
GitHub Releases, historical milestones, closed delivery records, or historical
tracker records to make adoption pass. If old data is incomplete, record the gap
and start the new contract from the first adopted release.

Versioned configuration must contain only portable identity and release
metadata. Keep local checkout paths, credential references, private key paths,
tokens, secret names, secret values, and environment-specific account details
out of committed files and assurance evidence.

## Hub Adoption

Run location: workflow hub checkout.

1. Configure `mode: workflow_hub` and one `workflow_hub.product_repos[]` entry
   per adopted product repository.
2. Validate versioned and local config with
   `validate-workflow-config.sh --repo <product-repo> --require-local`.
3. Confirm each product checkout with `hub-status.sh --repo <product-repo>`.
4. Build non-mutating assurance inputs from the intended selected product,
   target binding, component evidence, delivery bundle state, milestone
   reconciliation, rerun identity, and historical baselines.
5. Run the assurance harness before release mutation. Continue only when
   `adoption_status=validated` and both hub-owned and product-owned historical
   baselines are unchanged.
6. After validation, resolve and persist the selected product target with
   `component-release-target.sh --repo <product-repo> --json`.
7. Create `component_release_evidence.v1`, update the hub-owned delivery
   bundle, reconcile component milestones, and attach the assurance summary to
   the release runbook or self-review evidence.

The hub owns tracker coordination, specs, implementation plans, delivery bundle
manifests, component release evidence handoffs, parent release status, and
assurance summaries. Product release branches, product changelogs, product
tags, product GitHub Releases, deployment evidence, cleanup evidence, product
CI, and product reviewer loops remain product-owned unless the repository mode
contract says otherwise.

## Product Adoption

Run location: product repository checkout unless noted otherwise.

1. Configure `mode: product_repo` in the product repository if the product
   needs local workflow runtime helpers.
2. Use sync-template role selection so the product receives only `shared` and
   `product_repo_injection` entries.
3. Keep hub-owned tracker records, historical specs, implementation plans,
   protocols, and delivery coordination runbooks out of product injection.
4. Validate product-owned release config before accepting a hub-routed release
   branch or cleanup task.
5. Return product PR, CI, reviewer-loop, deployment, and cleanup evidence to
   the hub without copying hub-only coordination state into the product repo.

Product adoption must not require product repositories to know the full hub
portfolio. Product-side evidence should identify the selected product, release
branch, release outcome, CI outcome, deployment outcome, cleanup outcome, and
stable evidence file paths or artifact URLs that the hub can reference.

## Assurance Contract

`scripts/development-workflow/multi-repo-release-assurance.sh` emits
`multi_repo_release_assurance.v1`. The summary is release self-review evidence,
not a replacement for the release helpers it checks. See
[`scripts/development-workflow/README.md`](../../../scripts/development-workflow/README.md#multi-repo-release-assurancesh)
for fixture inputs, baseline inputs, output location, and invocation details.
Attach the generated assurance evidence to the release self-review before
mutating release branches, changelogs, tags, GitHub Releases, delivery bundles,
milestones, cleanup evidence, or tracker release state.

| Scenario | Required evidence | Validated result |
| --- | --- | --- |
| Component routing | Selected product target binding and release contract | Missing, ambiguous, mismatched, or unsupported targets stop before release mutation. |
| Configuration validation | Hub config and product config validation records | The correcting owner is named for invalid hub or product config. |
| Namespaced component milestones | Component evidence and milestone reconciliation output | Only the matching component child can receive `<product-repo>@<component-tag>`. |
| Delivery bundle finalization | Delivery bundle manifest and accepted component evidence | Parent release status changes only after every declared current component is complete. |
| Partial failures | Failed, blocked, stale, missing, or conflicting evidence | Incorrect accepted evidence reports `fail`; missing or owner-waiting evidence reports `blocked`; stale corrected attempts report `retryable`. |
| Reruns | Durable run id, step id, supersession, and idempotency guard | Stale attempts are rejected and repeated cleanup or handoff side effects block adoption. |
| Migration no-rewrite | Hub-owned historical baseline and product-owned historical baseline | Historical files are byte-for-byte unchanged before and after assurance. |
| `single_repo` compatibility | Non-hub release fixture | Existing single-repository release and milestone behavior remains valid without hub fixtures. |

The harness output includes:

- `schema_version`
- `adoption_status`
- `scenario_results[]`
- `historical_no_rewrite[]`
- `owner_actions[]`
- `required_next_action`

## Outcome Vocabulary

Use these scenario outcomes exactly:

| Outcome | Meaning |
| --- | --- |
| `pass` | Required evidence is complete and consistent. |
| `fail` | Evidence proves the scenario is wrong or repeated a side effect. |
| `blocked` | Required evidence is missing, contradictory, or waiting on a named owner. |
| `skipped` | The scenario does not apply and has an approved rationale. |
| `retryable` | A corrected rerun may supersede a stale or incomplete attempt. |

Adoption status is `validated` only when every required scenario is `pass` or
approved `skipped` with rationale, and every historical no-rewrite baseline is
unchanged. Any `fail`, `blocked`, unapproved `skipped`, unresolved `retryable`,
missing required evidence for a `pass` scenario, or historical baseline mutation
makes adoption status `blocked`. `approved_skipped` must be a JSON boolean;
string values such as `"false"` are invalid input.

## Historical No-Rewrite

Assurance compares two independent baselines:

- Hub-owned historical baseline: delivery manifests, tracker release records,
  component evidence handoffs, and hub release-status evidence.
- Product-owned historical baseline: product tags, changelog entries, GitHub
  Releases, release branches, deployment records, and cleanup records.

The before and after copies must match byte-for-byte. If a baseline differs,
restore the historical record or document the discrepancy as a blocked adoption
finding. Do not "repair" old history by changing committed product or hub
records during adoption.

## Runbook Evidence

A release runbook or pre-merge self-review for adoption should include:

- Selected product repository and canonical repository identity.
- Product release target binding and contract revision.
- Component release evidence path or artifact URL.
- Delivery bundle manifest revision and component tag.
- Component milestone reconciliation outcome.
- Parent release-status outcome.
- Assurance summary with `adoption_status` and owner actions.
- Explicit statement that no secrets, local paths, or credential references
  were committed or copied into evidence.

When adoption is blocked, the runbook should stop before release mutation and
name the required next action from the assurance output.

## Troubleshooting

### Ambiguous Product Selection

Stop before release mutation. Re-run
`component-release-target.sh --repo <product-repo> --json` with exactly one
configured product repository and record the emitted routing outcome.

### Retryable Or Stale Run

Keep the newer corrected `run_id` and `step_id` as the current evidence. Do not
repeat cleanup or handoff side effects from an older attempt. Record the older
attempt in the assurance rationale if it explains the retry.

### Historical Baseline Changed

Compare the emitted `historical_no_rewrite[]` owner and `changed_files` values.
Restore the baseline from the pre-adoption copy or mark adoption blocked until a
human owner decides how to handle the historical discrepancy.

### Product Repository Received Hub Files

Run product repository injection selection in dry-run mode. Hub-owned protocols,
historical specs, implementation plans, and delivery coordination runbooks must
not appear in product injection output.

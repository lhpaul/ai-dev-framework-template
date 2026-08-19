# Cross-Repository PR Flow

Use this guide from the workflow hub checkout when a hub-managed item routes
implementation work to a selected product repository.

Related references:

- [Workflow hub setup](workflow-hub-setup.md)
- [Product repository injection](product-repo-injection.md)
- [Repository modes](repository-modes.md)
- [Multi-repository release adoption](multi-repo-release-adoption.md)
- [Workflow Hub GitHub App Authentication](integrations/workflow-hub-github-app.md)
- [Batch Orchestration Protocol](protocols/90-batch-orchestrate-work-protocol.md)
- [Work Item Orchestration Protocol](protocols/91-orchestrate-work-protocol.md)
- [Automated Reviewer Loop Protocol](protocols/93-automated-reviewer-loop-protocol.md)
- [Batch Merge Protocol](protocols/94-batch-merge-protocol.md)

## Ownership Model

| Artifact | Owner in workflow-hub product work |
| --- | --- |
| Tracker item | Workflow hub |
| Spec | Workflow hub |
| Implementation plan | Workflow hub |
| Product implementation branch | Selected product repository |
| Product PR | Selected product repository |
| Product CI | Selected product repository |
| Product reviewer loop | Selected product repository |
| Merge cleanup tracker update | Workflow hub |

## Release Artifact Owners

Before a hub-managed release creates or mutates product release artifacts,
validate the selected product repository contract and record the artifact owner.
Use [Repository modes](repository-modes.md#release-artifact-ownership) as the
canonical ownership table for release branches, product cleanup evidence, and
Tracker reconciliation evidence; this flow only adds the hub checkout execution
step.

Run from the hub checkout:

<!-- workflow-shell-contract: bash-zsh -->
```bash
TARGET_REPO_KEY="faind-mobile-app"
TARGET_BINDING_SAFE_KEY="$(printf '%s' "$TARGET_REPO_KEY" | tr -c 'A-Za-z0-9._-' '_')"
TARGET_BINDING_FILE="$(mktemp "${TMPDIR:-/tmp}/component-release-target.${TARGET_BINDING_SAFE_KEY}.XXXXXX")"
TARGET_BINDING_TMP="${TARGET_BINDING_FILE}.$$"
scripts/development-workflow/component-release-target.sh \
  --repo "$TARGET_REPO_KEY" \
  --json > "$TARGET_BINDING_TMP"
mv "$TARGET_BINDING_TMP" "$TARGET_BINDING_FILE"
```

Continue only when the helper reports `component_release_routed` and
`mutation_allowed=true`. Then persist the target binding and create a release
evidence handoff:

<!-- workflow-shell-contract: bash-zsh -->
```bash
scripts/development-workflow/component-release-evidence.sh \
  --target-file "$TARGET_BINDING_FILE" \
  --binding-file "$TARGET_BINDING_FILE" \
  --release-branch "$RELEASE_BRANCH" \
  --release-outcome pending \
  --ci-outcome pending \
  --deployment-outcome pending \
  --cleanup-outcome not_started \
  --hub-tracker-ref "#123" \
  --output /path/to/component-release-evidence.json
```

Stop before release mutation when product selection is missing, multiple,
unknown, or ambiguous; a release branch value is invalid; the product checkout
is unavailable; or versioned release config contains local paths, credentials,
token values, secret names, secret values, or environment-specific account
details.

After both release PRs merge, run component release cleanup from the hub with
the same product key and evidence file. Follow
[Prepare Release](protocols/05-prepare-release-protocol.md) and the canonical
[repository-mode release contract](repository-modes.md#release-artifact-ownership)
for cleanup validation rules.

After cleanup and tracker reconciliation complete, keep milestone and parent
release status updates in the hub. Use
`component-milestone-reconciliation.sh apply-component` to assign only the
matching component child issue a `<product-repo>@<component-tag>` milestone.
Use `inspect-parent` or `apply-parent` with the hub delivery manifest to report
partial, blocked, or finalized parent release state. Do not create a shared
suite version, stamp the parent epic, or stamp the delivery bundle issue.

Hub-only workflow improvements, such as updates to orchestration scripts or
workflow docs, still open implementation PRs in the hub repository.

For adopted multi-repository releases, attach release assurance evidence from
[Multi-repository release adoption](multi-repo-release-adoption.md) to the
release runbook or PR self-review. The evidence must show
`adoption_status=validated` and unchanged hub-owned and product-owned
historical baseline results before release mutation proceeds. Use the
[Runbook Evidence](multi-repo-release-adoption.md#runbook-evidence) section for
the canonical evidence field list. The existing `single_repo` path is exempt.

## Route The Work Item

Run location: hub checkout.

Confirm the next action and selected product repository:

<!-- workflow-shell-contract: bash-zsh -->
```bash
scripts/development-workflow/workflow-next-action.sh \
  --repo faind-mobile-app \
  --development docs/specs/developments/20260611204735_882-workflow-hub-docs
```

The output should name the workflow mode, action repository kind, action
repository, and GitHub repository. Follow the canonical
[implementation routing classifier](repository-modes.md#implementation-routing-classifier)
contract for routing outcome, artifact owner, fingerprint, and stop evidence.

## Prepare The Product Checkout

Run location: hub checkout.

Inspect the product checkout:

```bash
scripts/development-workflow/hub-status.sh --repo faind-mobile-app
```

Fast-forward a clean checkout:

```bash
scripts/development-workflow/hub-sync-product-repos.sh --repo faind-mobile-app
```

If the checkout is dirty, resolve product-local changes in the product checkout
before continuing.

## Open Or Preview The Product PR

Run location: hub checkout.

Dry-run product PR creation before credentials or live writes:

```bash
scripts/development-workflow/open-product-pr.sh \
  --repo faind-mobile-app \
  --base main \
  --approved-base main \
  --head feature/faind-example \
  --title "feat: add faind example" \
  --body-file /tmp/faind-product-pr-body.md \
  --dry-run
```

Live PR creation uses the selected product repository GitHub App credentials and
passes the installation token only to the child `gh pr create` invocation.
`--approved-base` is the parent-approved workflow base; if it differs from
`--base`, the helper stops before credentials or `gh pr create` are used.

## Run Reviewers And CI

Run location: hub checkout.

Run the reviewer loop against the product repository PR:

```bash
scripts/development-workflow/pr-review-loop.sh 123 \
  --repo example/faind-mobile-app \
  --branch feature/faind-example
```

Run the CI loop against the product repository PR:

```bash
scripts/development-workflow/pr-ci-loop.sh 123 \
  --repo example/faind-mobile-app
```

Do not apply readiness labels until reviewer loop and CI are clean or only
acceptable advisory findings remain.

## Merge And Cleanup

Run location: hub checkout.

Use the repository merge protocol for the PR owner. For product PRs, the target
repository is the selected product repository. After merge, run cleanup from
the hub so tracker state remains hub-owned:

```bash
scripts/development-workflow/post-merge-cleanup.sh \
  --repo faind-mobile-app \
  feature/faind-example
```

Verify:

- Product PR state is `MERGED`.
- Product branch cleanup completed.
- Hub tracker status moved to `Merged` when the implementation closes the item.
- The hub checkout returns to the integration branch for the topic.

## Troubleshooting

### Failed CI

Symptom: `pr-ci-loop.sh` reports `RESULT=red`.

Confirm from the hub checkout:

```bash
scripts/development-workflow/pr-ci-loop.sh 123 --repo example/faind-mobile-app
```

Safe repair:

- Inspect the failing product repository check logs.
- Fix the product branch in the selected product checkout.
- Push the fix and rerun reviewer loop and CI.

### Reviewer-Loop Failures

Symptom: `pr-review-loop.sh` reports `needs_fixes`, `escalate`, or
`reviewer-failed`.

Confirm from the hub checkout:

```bash
scripts/development-workflow/pr-review-loop.sh 123 \
  --repo example/faind-mobile-app \
  --branch feature/faind-example
```

Safe repair:

- Address blocking findings in the selected product checkout.
- Treat low-value advisory findings as acceptable only when they do not
  materially improve correctness, security, maintainability, or test coverage.
- Rerun reviewer loop before applying readiness labels.

### Missing Product Checkout

Symptom: routing or cleanup cannot resolve `faind-mobile-app`.

Confirm from the hub checkout:

```bash
scripts/development-workflow/hub-status.sh --repo faind-mobile-app
```

Safe repair:

- Add or correct the local checkout path in `.ai-dev-workflow.local.yaml`.
- Re-run status and sync before mutating product files.

### Dirty Product Repo

Symptom: sync or cleanup refuses to operate on the product checkout.

Safe repair:

- Inspect product-local changes directly.
- Commit, stash, or intentionally remove those changes using the product
  repository's normal workflow.
- Re-run `hub-status.sh --repo faind-mobile-app`.

### Missing App Credentials

Symptom: `open-product-pr.sh` reports missing app metadata or private key
access.

Safe repair:

- Verify non-secret App ID and installation ID in `.ai-dev-workflow.yaml`.
- Verify local credential references in `.ai-dev-workflow.local.yaml`.
- Use `github-app-token.sh --repo faind-mobile-app --dry-run` before live PR
  creation.
- Stop if the credential source is unavailable; do not use unrelated ambient
  credentials.

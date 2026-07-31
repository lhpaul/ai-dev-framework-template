# Workflow Hub Setup

Use this guide from the workflow hub checkout when a repository will coordinate
workflow items for one or more product repositories.

Related references:

- [Repository modes](repository-modes.md)
- [Workflow Hub GitHub App Authentication](integrations/workflow-hub-github-app.md)
- [Orchestrate Work Protocol](protocols/90-batch-orchestrate-work-protocol.md)
- [Work Item Orchestration Protocol](protocols/91-orchestrate-work-protocol.md)

## Example Topology

This guide uses a non-secret Faind-like example:

| Role | Local name | GitHub repository |
| --- | --- | --- |
| Workflow hub | `faind-workflow-hub` | `example/faind-workflow-hub` |
| Mobile product | `faind-mobile-app` | `example/faind-mobile-app` |
| Admin product | `faind-admin-portal` | `example/faind-admin-portal` |

All IDs, paths, and secret references below are placeholders.

## Versioned Hub Config

Run location: hub checkout.

Create or update `.ai-dev-workflow.yaml` with repository-safe identity and
non-secret product repository metadata:

```yaml
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: faind-mobile-app
      github_repo: example/faind-mobile-app
      default_branch: main
      ci_policy: required
      release:
        base: main
        branch_pattern: release/v{version}
        changelog_owner: product_repo
        tag_owner: product_repo
        github_release_owner: product_repo
        deployment_evidence_owner: product_repo
        cleanup_evidence_owner: product_repo
        tracker_reconciliation_owner: hub
      github_app:
        app_id: "12345"
        installation_id: "999999"
    - name: faind-admin-portal
      github_repo: example/faind-admin-portal
      default_branch: develop
      github_app:
        app_id: "12345"
        installation_id: "888888"
```

Keep this file free of local paths, private key paths, token values, and secret
material.

The `release` block is the product release contract. It may contain only
non-secret, portable release metadata. `base` defaults to the product
repository's `default_branch`, `branch_pattern` defaults to
`release/v{version}`, and product-owned release artifacts default to
`product_repo` while tracker reconciliation defaults to `hub`.

Before creating product-owned changelog entries, release branches, tags, GitHub
Releases, deployment evidence, or cleanup evidence, run:

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
`mutation_allowed=true`. See
[Repository modes](repository-modes.md#release-artifact-ownership) for the
canonical routing outcomes, validation rules, and binding fields.
The versioned release contract must still exclude local checkout paths,
credentials, token values, secret names, secret values, and
environment-specific account details.

After resolving a component release target, store the generated target binding
with the release evidence record. The local checkout path comes only from
`.ai-dev-workflow.local.yaml`; never add checkout paths or secret references to
the versioned `release` block.

## Local Hub Config

Run location: hub checkout.

Create `.ai-dev-workflow.local.yaml` for machine-local checkout paths and
credential references. This file is gitignored.

```yaml
product_repos:
  - name: faind-mobile-app
    local_path: ../repos/faind-mobile-app
    github_app:
      secret_ref: example-secret-ref-faind-mobile-app-github-app
  - name: faind-admin-portal
    local_path: ../repos/faind-admin-portal
    github_app:
      secret_ref: example-secret-ref-faind-admin-portal-github-app
```

Use a real secret manager only in your local environment. Do not commit secret
manager account names, private key paths, private keys, tokens, or generated
installation tokens.

## Validate Setup

Run location: hub checkout.

Validate shared and local config:

```bash
scripts/development-workflow/validate-workflow-config.sh
scripts/development-workflow/validate-workflow-config.sh --repo faind-mobile-app --require-local
scripts/development-workflow/validate-workflow-config.sh --repo faind-admin-portal --require-local
```

Inspect product checkouts without modifying them:

```bash
scripts/development-workflow/hub-status.sh --all
scripts/development-workflow/hub-status.sh --repo faind-mobile-app
```

Prepare clean product checkouts with fast-forward-only behavior:

```bash
scripts/development-workflow/hub-sync-product-repos.sh --all
scripts/development-workflow/hub-sync-product-repos.sh --repo faind-mobile-app
```

Bootstrap workflow readiness labels and validate CI policy on GitHub product
repositories before delegated `/run-epic` or portfolio dispatch:

```bash
scripts/development-workflow/hub-preflight-product-repos.sh --all
scripts/development-workflow/hub-preflight-product-repos.sh --repo faind-mobile-app
```

Product repositories with no GitHub Actions workflows must declare
`ci_policy: none` on the hub `workflow_hub.product_repos[]` entry, or preflight
fails with guidance before orchestration reaches delegated merge gates.

Run the non-secret workflow-hub smoke fixture:

```bash
bash scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh
```

## Troubleshooting

### Missing Product Checkout

Symptom: `hub-status.sh` reports `missing_path` or `missing_checkout`.

Confirm from the hub checkout:

```bash
scripts/development-workflow/hub-status.sh --repo faind-mobile-app
scripts/development-workflow/validate-workflow-config.sh --repo faind-mobile-app --require-local
```

Safe repair:

- Add the product checkout path to `.ai-dev-workflow.local.yaml`.
- Create or clone the product checkout outside the hub repository.
- Re-run validation before starting implementation work.

Escalate when the intended product repository or local checkout location is
ambiguous.

### Dirty Product Repo

Symptom: `hub-status.sh` reports `dirty`, or `hub-sync-product-repos.sh` blocks
before fetching.

Confirm from the hub checkout:

```bash
scripts/development-workflow/hub-status.sh --repo faind-mobile-app
```

Safe repair:

- Inspect the product checkout directly.
- Commit, stash, or otherwise resolve the product-local changes intentionally.
- Re-run `hub-sync-product-repos.sh --repo faind-mobile-app`.

Do not use destructive reset commands or force-update product branches to make
the workflow proceed.

### Missing App Credentials

Symptom: product PR creation reports `missing_app_id`, `missing_private_key`, or
`missing_installation`.

Confirm from the hub checkout:

```bash
scripts/development-workflow/github-app-token.sh --repo faind-mobile-app --status
scripts/development-workflow/github-app-token.sh --repo faind-mobile-app --dry-run
```

Safe repair:

- Put non-secret App ID and installation ID in `.ai-dev-workflow.yaml`.
- Put only local credential references in `.ai-dev-workflow.local.yaml`.
- Re-run dry-run checks before live PR creation.

Do not fall back to an unrelated user token when GitHub App configuration is
missing.

### Failed CI

Symptom: product PR validation reports a failing CI result.

Start from the hub checkout and follow the recovery path in
[Cross-Repository PR Flow](cross-repo-pr-flow.md#failed-ci). The first check is:

```bash
scripts/development-workflow/pr-ci-loop.sh 123 --repo example/faind-mobile-app
```

Fix the selected product branch in the product checkout, push the repair, and
rerun reviewer and CI loops before applying readiness labels.

### Reviewer-Loop Failures

Symptom: product PR review reports `needs_fixes`, `escalate`, or a reviewer
failure label.

Start from the hub checkout and follow the recovery path in
[Cross-Repository PR Flow](cross-repo-pr-flow.md#reviewer-loop-failures). The
first check is:

```bash
scripts/development-workflow/pr-review-loop.sh 123 \
  --repo example/faind-mobile-app \
  --branch feature/faind-example
```

Fix blocking findings in the selected product checkout and rerun the reviewer
loop before applying readiness labels.

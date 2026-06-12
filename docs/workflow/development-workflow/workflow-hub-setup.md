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

# Workflow Hub GitHub App Authentication

Workflow hubs can coordinate product repository implementation PRs without
using the hub repository remote or leaking local credentials. This guide covers
the GitHub App setup and helper commands used by workflow-hub product PR
operations.

## Required GitHub App Access

Install the GitHub App on every product repository that the workflow hub may
open implementation PRs against.

Minimum repository permissions:

- Metadata: read.
- Contents: read and write when the helper needs to create or update branches.
- Pull requests: read and write.
- Checks or commit statuses: read when later reviewer/CI helpers inspect PR
  readiness in the product repository.

The operator must record the App ID and installation ID for each product
repository. App ID and installation ID are non-secret identifiers and may be
stored in the shared workflow config. Private key paths, private key contents,
secret-manager account details, token values, and machine-local secret
locations must not be stored in the shared config.

## Shared Configuration

The shared `.ai-dev-workflow.yaml` records stable product repository identity
and non-secret GitHub App identifiers:

```yaml
schema_version: 2
mode: workflow_hub

workflow_hub:
  product_repos:
    - name: mobile-app
      github_repo: example/mobile-app
      default_branch: main
      github_app:
        app_id: "12345"
        installation_id: "999999"
    - name: admin-portal
      git_url: git@github.com:example/admin-portal.git
      default_branch: develop
      github_app:
        app_id: "12345"
        installation_id: "888888"
```

The resolver rejects local-only fields such as `private_key_path`, `secret_ref`,
`private_key`, `secret`, and `local_path` when they appear under shared
`workflow_hub.product_repos[]` entries.

## Local Configuration

Local auth references belong in `.ai-dev-workflow.local.yaml`, which is
gitignored. Prefer the nested `github_app` form for new setup:

```yaml
product_repos:
  - name: mobile-app
    local_path: ../repos/mobile-app
    github_app:
      private_key_path: ~/.config/example/mobile-app-github-app.pem
      secret_ref: op://ExampleVault/mobile-app-github-app/private-key
  - name: admin-portal
    github_app:
      secret_ref: op://ExampleVault/admin-portal-github-app/private-key
```

The legacy top-level local aliases remain accepted for compatibility:

```yaml
product_repos:
  - name: mobile-app
    private_key_path: ~/.config/example/mobile-app-github-app.pem
    secret_ref: op://ExampleVault/mobile-app-github-app/private-key
```

Secret-manager references are references only; the workflow does not require a
specific secret manager and does not store secret values in config files.

## Helper Commands

Check redacted auth metadata:

```bash
scripts/development-workflow/github-app-token.sh --repo mobile-app --status
```

Dry-run token metadata resolution:

```bash
scripts/development-workflow/github-app-token.sh --repo mobile-app --dry-run
```

Print an installation token for a machine caller:

```bash
scripts/development-workflow/github-app-token.sh --repo mobile-app --print-token
```

`--print-token` is the only mode that writes token material to stdout. Human
logs and error output must not contain token values or private key contents.

Dry-run a product repository PR operation before credentials are available:

```bash
scripts/development-workflow/open-product-pr.sh \
  --repo mobile-app \
  --base main \
  --approved-base main \
  --head feature/example \
  --title "feat: example product change" \
  --body-file /tmp/product-pr-body.md \
  --dry-run
```

The dry-run output includes the target `owner/repo`, base branch, head branch,
approved base branch, title, and a redacted
`gh pr create --repo <owner/repo>` command shape. It does not require or print
credentials. If `--approved-base` is supplied and does not match `--base`, the
helper stops before credentials or `gh pr create` are used.

Run the same dry-run for a second product repository to verify routing:

```bash
scripts/development-workflow/open-product-pr.sh \
  --repo admin-portal \
  --base develop \
  --approved-base develop \
  --head feature/example \
  --title "feat: example admin change" \
  --body-file /tmp/product-pr-body.md \
  --dry-run
```

Live PR creation obtains the selected product repository token and passes it
only to the child `gh pr create` invocation through `GH_TOKEN`.

## Failure States

The helpers fail before unsafe fallback when required auth is incomplete:

- `missing_app_id`: no App ID is configured for the selected product repo.
- `missing_private_key`: no readable local private key path or resolvable
  secret reference is configured.
- `missing_installation`: no installation ID is configured, or the token
  exchange cannot access the installation.
- `permission_denied`: GitHub returned a response that does not include an
  installation token.

The helpers do not silently fall back to the operator's ambient `gh` token when
workflow-hub product repository auth is incomplete.

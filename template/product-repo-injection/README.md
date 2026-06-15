# Product Repository Injection Skeleton

This skeleton describes the minimal framework files a `product_repo` may need
when implementation work is routed from a workflow hub. It is inspectable
reference material only: opening this directory does not copy files, alter
configuration, or register a product repository with a hub.

Use this skeleton when a repository owns product code and validation, while a
workflow hub owns portfolio tracking, specs, plans, and cross-repository
coordination.

## Intended Contents

Product repository injection should stay small. Candidate files are limited to:

- Local agent guidance such as `AGENTS.md`, adapted for the product repository.
- Shared review and development standards needed for product code PRs.
- Repository workflow configuration declaring `mode: product_repo` and the
  workflow hub reference.
- Local workflow configuration examples for checkout paths and secret
  references.
- The smallest workflow helper scripts required for product-repo validation,
  reviewer-loop execution, CI polling, or repository-context resolution.

The manifest references canonical source paths. It does not copy the full
framework into this directory.

## Explicit Exclusions

Product repository injection must exclude hub-owned planning and coordination
artifacts unless a later workflow explicitly marks a specific artifact as
required for product repository participation. Excluded categories include:

- Hub tracker state and portfolio coordination data.
- `docs/specs/` history, feature specs, and implementation plans.
- Hub-only workflow smoke runbooks.
- Cross-product coordination notes that are not required to run product code
  validation.

## Setup Mode

Choose this skeleton when `.ai-dev-workflow.yaml` declares:

```yaml
schema_version: 2
mode: product_repo

product_repo:
  workflow_hub:
    github_repo: example/workflow-hub
```

The current repository root remains the default `single_repo` setup path. A
product repository uses this skeleton only when it is connecting to a separate
workflow hub.

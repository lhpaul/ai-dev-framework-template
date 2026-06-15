# Workflow Hub Skeleton

This skeleton describes the framework-owned files that belong in a
`workflow_hub` repository. It is inspectable reference material only: opening
this directory does not run setup, sync files, create tracker items, or inject
content into any product repository.

Use this skeleton when one repository coordinates workflow across one or more
product repositories. The hub owns portfolio planning and workflow artifacts,
including:

- Canonical workflow protocols and workflow documentation.
- Workflow helper scripts for state discovery, PR readiness, reviewer loops,
  CI loops, release work, and configuration resolution.
- Claude Code, Cursor, and Codex agent or skill wrappers that invoke the
  canonical protocols.
- Repository workflow configuration files and examples.
- Hub-owned runbooks, smoke tests, and validation harnesses for workflow
  behavior.

The hub skeleton intentionally references canonical source paths instead of
copying the full framework tree into this directory. See
`skeleton-manifest.yaml` for the grouped path list.

## Relationship To Product Repositories

Product repositories that participate in a workflow hub should use
`template/product-repo-injection/` instead of this skeleton. Product repositories
own product code, product CI, product reviewer-loop execution, and product smoke
runbooks. They should not receive hub-owned tracker state, historical specs,
implementation plans, or cross-product coordination artifacts unless a later
workflow explicitly documents why a specific artifact is required.

## Setup Mode

Choose this skeleton when `.ai-dev-workflow.yaml` declares:

```yaml
schema_version: 2
mode: workflow_hub
```

The current repository root remains the default `single_repo` setup path for
existing adopters. This skeleton is a role-specific reference for teams creating
or adapting a workflow hub.

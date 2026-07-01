# Integration: CI/CD Deployments (Template Placeholder)

This template includes a placeholder GitHub Actions deploy workflow at:

- `.github/workflows/deploy.yml`

The workflow is intentionally generic so downstream repositories can implement their own provider-specific deployment logic (for example AWS, GCP, Azure, Vercel, Fly.io, Kubernetes, or custom infrastructure).

---

## Default Behavior

- Placeholder deploy jobs are inactive by default and do not run on push.
- Manual placeholder validation is supported with `workflow_dispatch`, an
  `environment` input (`develop` or `production`), and
  `confirm_placeholder: true`.
- Downstream repositories should reintroduce push triggers only after replacing
  the placeholder steps with project-specific deployment logic.

The included deploy steps are no-op placeholders (`echo` commands). They remain
available for explicit validation, but the template does not spend runner time
on every default-branch push before a downstream project has a real deployment
pipeline.

---

## Temporary Placeholder Validation

Use manual dispatch only when you intentionally want to validate that GitHub
Environments and workflow permissions are wired correctly:

1. Open the `Deploy (Template Placeholder)` workflow in GitHub Actions.
2. Choose `Run workflow`.
3. Select `develop` or `production`.
4. Set `confirm_placeholder` to `true`.

Leaving `confirm_placeholder` as `false` skips the placeholder deploy jobs.

---

## What Downstream Repositories Should Customize

Replace the placeholder deploy steps with project-specific logic, usually:

1. Install dependencies and build artifacts.
2. Authenticate with the deployment platform (OIDC/service principal/API token).
3. Execute deployment command(s) for the selected environment.
4. Optionally add post-deploy smoke checks and rollback hooks.

After replacing the placeholder with real deployment logic, choose the trigger
model that matches your release policy. Common downstream choices are:

- Push to `develop` deploys a staging or preview environment.
- Push to `main` deploys production after branch protection and release checks.
- Manual `workflow_dispatch` remains available for controlled promotions.

You should also configure repository/environment secrets and protection rules in GitHub Environments:

- `develop` (non-production)
- `production`

---

## Concurrency Design

Each job uses its own fixed concurrency group (`deploy-develop` and `deploy-production`) rather than a single `deploy-${{ github.ref }}` group. This matters for two reasons:

- **Environment isolation**: develop and production deploys never cancel each other, even when both branches are active simultaneously.
- **Production safety**: the `deploy-production` job sets `cancel-in-progress: false`. Two rapid pushes to `main` will queue the second production deploy rather than aborting the first mid-flight, avoiding inconsistent states such as migrations applied without a corresponding code rollout.

The `deploy-develop` job keeps `cancel-in-progress: true` so redundant staging deploys are discarded quickly.

Note: `workflow_dispatch` sets `github.ref` to the branch selected in the "Use workflow from" dropdown, not the target environment. Using fixed group names (`deploy-develop` / `deploy-production`) prevents a manual production deploy triggered from `develop` from being cancelled by another deploy workflow run.

---

## Notes

- This template does not store deployment credentials or provider-specific commands.
- The placeholder workflow is intentionally opt-in to avoid private downstream
  repositories spending Actions minutes before real deployment value exists.
- Keep production deployments protected (reviewers, required checks, branch protections) according to your project's risk profile.

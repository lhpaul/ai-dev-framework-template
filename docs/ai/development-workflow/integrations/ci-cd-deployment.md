# Integration: CI/CD Deployments (Template Placeholder)

This template includes a placeholder GitHub Actions deploy workflow at:

- `.github/workflows/deploy-template.yml`

The workflow is intentionally generic so downstream repositories can implement their own provider-specific deployment logic (for example AWS, GCP, Azure, Vercel, Fly.io, Kubernetes, or custom infrastructure).

---

## Default Behavior

- Push to `develop` runs the `deploy-develop` job and targets the `develop` GitHub Environment.
- Push to `main` runs the `deploy-production` job and targets the `production` GitHub Environment.
- Manual runs are supported with `workflow_dispatch` and an `environment` input (`develop` or `production`).

The included deploy steps are no-op placeholders (`echo` commands) so the workflow remains safe and passing in this template repository.

---

## What Downstream Repositories Should Customize

Replace the placeholder deploy steps with project-specific logic, usually:

1. Install dependencies and build artifacts.
2. Authenticate with the deployment platform (OIDC/service principal/API token).
3. Execute deployment command(s) for the selected environment.
4. Optionally add post-deploy smoke checks and rollback hooks.

You should also configure repository/environment secrets and protection rules in GitHub Environments:

- `develop` (non-production)
- `production`

---

## Notes

- This template does not store deployment credentials or provider-specific commands.
- Keep production deployments protected (reviewers, required checks, branch protections) according to your project's risk profile.

# Workflow Hub Smoke Fixture

This fixture is committed test data for the non-secret workflow-hub smoke
harness:

```bash
bash scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh
```

The topology is intentionally small and generic:

- `workflow-hub` owns the workflow configuration, tracker items, specs, plans,
  and orchestration scripts.
- `mobile-app` is a dummy product repository with identity
  `example/mobile-app`.
- `admin-portal` is a dummy product repository with identity
  `example/admin-portal`.

The harness copies these files into a temporary directory, creates temporary git
repositories for the products, and materializes local-only checkout paths there.
Do not commit real product names, customer names, team names, repository
identities, tokens, key material, or live credential locations in this fixture.

Default validation is fully local and does not require GitHub credentials. Live
GitHub App validation is separate and must be requested explicitly:

```bash
bash scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh --live-github-app
```

That live path is for safe test repositories only and is never run by default CI.

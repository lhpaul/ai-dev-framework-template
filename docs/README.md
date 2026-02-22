# Documentation

## Project Documentation

These files describe your specific project. They are generated via the [project setup agent](../docs/ai/setup/protocol.md) and refined over time.

| File | Description |
|---|---|
| [1-business-domain.md](project/1-business-domain.md) | Domain entities, actors, business rules, glossary |
| [2-repo-architecture.md](project/2-repo-architecture.md) | Repository structure, packages, apps, dependencies |
| [3-software-architecture.md](project/3-software-architecture.md) | Tech stack, design patterns, key architectural decisions |
| [4-database-model.md](project/4-database-model.md) | Data model, schema, access patterns (delete if not applicable) |

## Best Practices

Coding standards and conventions. Stack-specific practices are generated during project setup.

| File | Description |
|---|---|
| [best-practices/1-general.md](best-practices/1-general.md) | General development standards |
| [best-practices/2-version-control.md](best-practices/2-version-control.md) | Git and commit conventions |
| [best-practices/3-testing.md](best-practices/3-testing.md) | Testing strategy and standards |
| [best-practices/STACK-SPECIFIC.md](best-practices/STACK-SPECIFIC.md) | Stack-specific conventions (generated during setup) |

## AI Development Workflow

| File | Description |
|---|---|
| [ai/development-workflow/README.md](ai/development-workflow/README.md) | Master workflow document — start here |
| [ai/development-workflow/tooling-assumptions.md](ai/development-workflow/tooling-assumptions.md) | Required vs optional tools |
| [ai/development-workflow/protocols/](ai/development-workflow/protocols/) | Canonical stage-by-stage protocols |
| [ai/development-workflow/templates/](ai/development-workflow/templates/) | Document templates (spec, plan, smoke test) |
| [ai/development-workflow/integrations/](ai/development-workflow/integrations/) | Optional tool integrations |
| [ai/setup/protocol.md](ai/setup/protocol.md) | Project setup protocol (onboarding) |

## Feature Specs

Feature specifications and implementation plans live in:

```
docs/specs/developments/[YYYYMMDDHHMMSS]_[feature-slug]/
  1_[feature-slug]_specs.md
  2_[feature-slug]_implementation-plan.md
```

## Test Runbooks

Smoke test runbooks live in:

```
docs/testing/[app-or-section]/[feature-slug].smoke-test.md
```

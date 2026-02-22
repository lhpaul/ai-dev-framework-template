# Version Control Best Practices

## Commit Messages

This project follows the [Conventional Commits](https://www.conventionalcommits.org/) specification.

### Format

```
<type>[optional scope]: <description>

[optional body]

[optional footers]
```

### Types

| Type | When to use |
|---|---|
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | Documentation changes only |
| `style` | Formatting, whitespace — no logic change |
| `refactor` | Code restructuring — no feature or bug fix |
| `perf` | Performance improvements |
| `test` | Adding or correcting tests |
| `chore` | Build process, tooling, dependencies |
| `revert` | Reverting a previous commit |

### Examples

```
feat(auth): add email OTP login flow
fix(payments): correct rounding on invoice totals
docs: update setup instructions for new env vars
chore(deps): upgrade eslint to v9
```

### Rules

- Use the imperative mood in the description: "add feature" not "added feature"
- Keep the first line under 72 characters
- If the commit has a body, leave a blank line after the description
- Reference issue numbers in the footer: `Closes #123`

## Branching

| Branch type | Naming | Branch from | Merges into |
|---|---|---|---|
| Feature (full pipeline) | `feature/[slug]` | `develop` | `develop` |
| Bug / simple fix | `fix/[slug]` | `develop` | `develop` |
| Hotfix (critical prod) | `hotfix/[slug]` | `main` | `main` + `develop` |
| Spec | `spec/[slug]` | `develop` | `develop` |
| Implementation plan | `implementation-plan/[slug]` | `develop` | `develop` |
| Release | `release/v[X.Y.Z]` | `develop` | `main` + `develop` |

## Staging and Committing

- Stage only files that belong to the logical change being committed
- Review the diff before committing (`git diff --staged`)
- One logical change per commit — don't bundle unrelated fixes
- Don't automate commits; review staged changes manually before every commit

## Pull Requests

- Keep PRs focused on one logical change
- Write a clear title following the commit message convention
- Include context in the PR description: what, why, how to test
- Link the relevant issue if one exists
- Every PR must update `CHANGELOG.md` under `[Unreleased]` before merge

## Safety Rules

The following actions require explicit human approval before executing:

- `git push --force` or `git push --force-with-lease`
- `git reset --hard`
- `git rebase` on a shared (pushed) branch
- Deleting a remote branch that others may be using

When in doubt, stop and ask. The cost of confirming is low; the cost of lost work is high.

## CHANGELOG

This project uses [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format.

- Every feature/fix/hotfix PR adds an entry under `[Unreleased]` **before merge**
- Never defer CHANGELOG entries to release time
- Use the appropriate category: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`
- Release PRs move `[Unreleased]` entries to a versioned section: `[X.Y.Z] - YYYY-MM-DD`

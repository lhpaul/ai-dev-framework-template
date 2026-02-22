# General Best Practices

These conventions apply across all languages and frameworks in this project.

## File Naming

- Use lowercase and hyphens for file names: `user-profile.ts`, not `UserProfile.ts` or `user_profile.ts`
- Use descriptive, intent-revealing names — prefer `invoice-payment-service.ts` over `service.ts`
- Group files by feature/domain, not by type (components, services, etc.) when the codebase is large enough

## Code Quality

### Readability First

- Write code that is easy to read, not just easy to write
- Avoid abbreviations unless they are universally understood (e.g., `id`, `url`, `config`)
- One logical thing per function — if a function does two things, consider splitting it
- Keep functions short; if it doesn't fit on one screen, consider refactoring

### Avoid Over-Engineering

- Only make changes that are directly requested or clearly necessary
- Don't add features, refactoring, or "improvements" beyond what was asked
- The right amount of complexity is the minimum needed for the current task
- Three similar lines of code is often better than a premature abstraction

### Error Handling

- Handle errors at the right level — don't swallow errors silently
- Log errors with enough context to diagnose the problem
- Only validate at system boundaries (user input, external APIs); trust internal code and framework guarantees
- Prefer explicit error types over generic exceptions where the language supports it

### Comments

- Comment *why*, not *what* — the code says what it does; comments should explain intent
- Add comments only where the logic isn't self-evident
- Keep comments up to date — stale comments are worse than no comments

## Security

- Never commit secrets, API keys, or credentials to the repository
- Use environment variables for configuration that varies per environment
- Validate all user input at system boundaries
- Be careful with dynamic queries, template interpolation, and shell commands (injection risks)
- Apply the principle of least privilege: request only the permissions a component needs

## Testing

- See [`3-testing.md`](3-testing.md) for the testing strategy
- Write tests for business logic, not for implementation details
- A failing test is information — don't delete tests to make the build pass

## Formatting

- Use the project's automated formatter (see `docs/project/2-repo-architecture.md` for the command)
- No trailing whitespace in files
- Files end with a single newline
- Consistent indentation (tabs vs spaces defined per language in `STACK-SPECIFIC.md`)

## Dependency Management

- Prefer established, actively maintained libraries
- Evaluate the license before adding a dependency
- Pin dependency versions in lock files; update deliberately
- Prefer smaller, focused packages over large monolithic ones

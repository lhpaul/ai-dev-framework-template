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
- Spec, plan, and CHANGELOG markdown files are linted automatically on every PR touching
  `docs/specs/developments/`, `docs/testing/workflow/`, or `CHANGELOG.md`. Rules are
  configured in `.markdownlint.jsonc` (trailing whitespace, relative links, newline at EOF).
  Run locally:

  ```bash
  npx markdownlint-cli2 "docs/specs/developments/**/*.md" "docs/testing/workflow/**/*.md" "CHANGELOG.md"
  find docs/specs/developments docs/testing/workflow -name "*.md" -print0 \
    | xargs -0 python3 scripts/lint/markdown-heuristic-lint.py CHANGELOG.md
  ```

## Shell Scripting

### ShellCheck Suppression Directives

ShellCheck is required for all `.sh` files in this project (see `docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`). Occasionally ShellCheck emits false positives — warnings that flag intentional, correct code. When a genuine false positive cannot be resolved by rewriting the code, use a suppression directive.

**When suppression is appropriate:**

- Glob patterns in `case` statement arms that intentionally require unquoted expansion
- Intentionally unquoted word-splitting, such as passing a constructed argument list through a variable (`$FLAGS` where the split is intended by design)
- Constructs where quoting would change behavior and the unquoted form is deliberate and understood

**When suppression is NOT appropriate:**

- To silence a real bug or security risk
- Because the fix is inconvenient or requires refactoring
- As a shortcut to avoid understanding the warning

**Correct suppression syntax** — place the directive on the line immediately before the affected code and include a comment explaining why:

```bash
# shellcheck disable=SC2086  # $FLAGS must word-split to pass multiple arguments to the command
eval "$runner" $FLAGS

# shellcheck disable=SC2254  # Glob pattern in case arm is intentional — not a variable expansion
case "$input" in
  *.tar.gz) extract_tar "$input" ;;
  *.zip)    extract_zip "$input" ;;
esac
```

**Rules for all suppression directives:**

1. One `# shellcheck disable=` comment per suppressed occurrence — do not add blanket file-level disables.
2. The `# shellcheck disable=` line must include an inline explanation (after `#`) of why the suppression is needed — a bare disable with no explanation is a protocol violation.
3. Prefer the narrowest scope: use a line-level disable rather than a function-level or file-level one.
4. If the same construct recurs throughout the file, extract it into a helper function and suppress once there.

## Dependency Management

- Prefer established, actively maintained libraries
- Evaluate the license before adding a dependency
- Pin dependency versions in lock files; update deliberately
- Prefer smaller, focused packages over large monolithic ones

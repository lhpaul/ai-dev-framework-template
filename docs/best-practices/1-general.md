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

These rules apply whenever a change creates or significantly modifies a `.sh` file. They address the patterns most consistently missed in automated review cycles.

### Fail-open error handling

Never use `|| echo 0` (or similar) to suppress command failures — this masks real errors and silently returns wrong data. Use an explicit fallback block instead:

```bash
# Wrong — suppresses the error and returns 0 even when the command fails:
COUNT=$(some_command | wc -l || echo 0)

# Correct — distinguish absence of data from an actual command failure:
# pipefail required so the pipeline exit code reflects some_command's exit code
set -o pipefail
if ! COUNT=$(some_command | wc -l 2>/dev/null); then
  echo "WARNING: some_command failed — skipping" >&2
  COUNT=0
fi
```

### Input validation before external commands

Validate all positional parameters at the top of the script, before any `git`, `gh`, or API call. A missing argument causes confusing deep failures rather than a clear startup message.

```bash
#!/usr/bin/env bash
set -euo pipefail

ISSUE_NUMBER="${1:?Usage: $0 <issue_number>}"
OWNER="${2:?Usage: $0 <issue_number> <owner>}"
REPO="${3:?Usage: $0 <issue_number> <owner> <repo>}"
```

The `${VAR:?message}` form exits with an informative error if the variable is unset or empty.

### Grep pattern anchoring

Always anchor grep patterns to avoid substring false positives. For example, `fix/` as a bare pattern matches `hotfix/` too.

```bash
# Wrong — matches "hotfix/123-foo" as well as "fix/123-foo":
echo "$BRANCH" | grep "fix/"

# Correct — anchor to the start of the string:
echo "$BRANCH" | grep "^fix/"
# Or use word-boundary matching when anchoring to start is not possible:
echo "$BRANCH" | grep -w "fix"
```

### Pipe exit-code propagation

Use `set -o pipefail` when the exit code of the first command in a pipeline must be preserved. Without it, `cmd1 | cmd2` returns only `cmd2`'s exit code — a failing `cmd1` goes undetected.

```bash
#!/usr/bin/env bash
set -eo pipefail

# Now a non-zero exit from cmd1 propagates through the pipe:
cmd1 | cmd2
```

When `head`, `grep -m`, or other early-terminating commands appear in a pipeline under `pipefail`, they may produce a SIGPIPE (exit 141) that looks like an error. Guard these cases:

```bash
# Suppress SIGPIPE false-positive for early-terminating pipeline consumers:
some_command | head -1 || true
```

### Glob precision

Prefer patterns that anchor the issue-number or name segment to avoid matching unintended branches or paths.

```bash
# Wrong — matches any branch containing the number (e.g., "feature/1234-foo"):
git branch --list "*-${ISSUE_NUMBER}-*"

# Correct — anchor the prefix so only the intended branch type matches:
git branch --list "feature/${ISSUE_NUMBER}-*"
```

### Additional patterns

For the complete shell scripting checklist — including jq variable injection, `local` exit-code masking, timestamp sourcing, `gh` CLI error handling, and exit-code semantics under `set -e` — see [`../workflow/development-workflow/protocols/03-implement-development-protocol.md`](../workflow/development-workflow/protocols/03-implement-development-protocol.md) → "Shell Script Quality Checklist".

---

## Dependency Management

- Prefer established, actively maintained libraries
- Evaluate the license before adding a dependency
- Pin dependency versions in lock files; update deliberately
- Prefer smaller, focused packages over large monolithic ones

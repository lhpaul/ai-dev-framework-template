# LLM Rules

These rules govern how LLM agents should interact with this codebase. They are enforced by a pre-commit hook on **agent** commits (human commits pass through without this gate).

## Creating Pull Requests

Follow this repository's development workflow unless the human directs otherwise:

1. **Open PRs with `gh pr create`** per [`docs/workflow/development-workflow/protocols/03-implement-development-protocol.md`](docs/workflow/development-workflow/protocols/03-implement-development-protocol.md) — typically `--draft`, with the correct `--base` (`develop` for features/fixes/refactors; `main` for hotfixes).
2. Run guards documented in the protocol (board membership, base-branch checks) before and after create.
3. After the PR exists, advance through the automated reviewer loop (protocol 93) when `review.platforms` are configured in [`.ai-dev-workflow.yaml`](.ai-dev-workflow.yaml).

Do not skip CHANGELOG updates for feature/fix PRs. See [`AGENTS.md`](AGENTS.md) and [`docs/best-practices/2-version-control.md`](docs/best-practices/2-version-control.md).

### Optional: Haystack submit

If the human or team has adopted [Haystack Editor](https://haystackeditor.com/) for PR creation, you may use `haystack submit` when explicitly instructed. See [`docs/workflow/development-workflow/integrations/haystack.md`](docs/workflow/development-workflow/integrations/haystack.md).

```bash
haystack submit
haystack submit --review    # complex/uncertain changes
haystack triage <pr-number> # analysis after submit (--json for scripts)
```

When both workflows apply, prefer the human's stated choice. Default remains **`gh pr create`** + this framework's reviewer loop.

## General Agent Behavior

- When you write or edit LLM prompts in response to a failure running against some test data, be certain that your edit is not specific to the test data, and is actually addressing the more generic problem that caused the failure.
- If the user specifies a model, follow it. Your understanding of current LLM models is outdated.
- Do not add silent fallbacks.
- Do not add backwards compatibility, unless you confirmed with the user first that it's desired.
- Do not add TODOs and incomplete code unless they have been explicitly flagged to the user.

## No Truncation Without Permission

When writing or modifying agent code (tool calls, prompts, LLM pipelines):

- **Never truncate, slice, or omit content** from tool call inputs, tool call outputs, prompt context, search results, file contents, or any data passed to/from LLMs without explicit user permission.
- **Never summarize in place of full content** (e.g., "... [content omitted]", "showing first 50 lines", "[truncated for brevity]").
- **No silent length limits** - do not add code that silently cuts off text at N characters/lines/tokens.

If truncation is technically necessary (e.g., context limits):

1. **Disclose explicitly** that truncation will occur
2. **State what and how much** will be omitted
3. **Ask for user permission** before proceeding
4. **Offer alternatives** (e.g., chunking, pagination with user control)

This applies to: grep/search results, file reads, API responses, prompt templates, tool definitions, agent memory, conversation history, and any other text flowing through agent pipelines.

## No Hardcoded Repo Knowledge in Prompts

When writing LLM prompts for generic tools:

- **Never hardcode repo-specific examples** like component names, file paths, or internal terminology.
- **Use generic examples** that would work for any codebase (e.g., "Sidebar", "Card", "Modal").
- **Let the LLM infer from context** rather than baking in assumptions about your specific codebase.

This keeps tools portable and prevents prompts from becoming stale when the codebase changes.

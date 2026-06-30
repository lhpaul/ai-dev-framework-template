# Cursor Bugbot Rules

Cursor Bugbot reviews pull requests after they are pushed to GitHub. Treat these
rules as project-specific review guidance for this framework repository.

## Focus Areas

- Flag changes that weaken the staged workflow's terminal conditions, reviewer
  gates, CI gates, tracker reconciliation, or human-merge requirements.
- Flag protocol or command-wrapper changes that make Claude Code, Cursor, and
  Codex behavior diverge without explicitly documenting the reason.
- Flag workflow-script changes that ignore failed `gh`, `jq`, `git`, or network
  calls, especially when the result could make a PR look clean incorrectly.
- Flag documentation that describes script behavior without matching the actual
  script source, including result tokens, exit codes, option names, and emitted
  `KEY=value` signals.
- Flag additions of local paths, credentials, tokens, private key material, or
  user-specific configuration to versioned files.

## Non-Issues

- Do not require a `.cursor/skills/` mirror. The repository intentionally uses
  `.cursor/agents/`, `.cursor/commands/`, and shared `.agents/skills/` surfaces.
- Do not flag the default `review.on_draft.runner: [codex]` as a problem by
  itself. Local runner overrides belong in `.ai-dev-workflow.local.yaml`.
- Do not treat advisory reviewer findings as blockers unless the workflow
  contract says the specific finding type must block readiness.

## Review Tone

Prefer concrete, line-specific findings with the workflow impact stated plainly.
Avoid broad style comments unless they affect correctness, safety, or workflow
compatibility.

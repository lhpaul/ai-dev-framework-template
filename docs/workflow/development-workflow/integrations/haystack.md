# Integration: Haystack Editor (Git Hooks & Optional PR Workflow)

This document describes [Haystack Editor](https://haystackeditor.com/) (`@haystackeditor/cli`) as an **optional** complement to this framework's default PR and review workflow.

Haystack is **not** the same product as deepset's [Hayhooks](https://github.com/deepset-ai/hayhooks) (Haystack pipeline deployment). Haystack Editor focuses on AI-assisted development: PR triage, agent-session attribution, and local guardrails on agent commits.

The canonical workflow in this template still uses **`gh pr create`** and the automated reviewer loop (`pr-review-loop.sh`, protocol 93) with platforms declared in `.ai-dev-workflow.yaml` (for example CodeRabbit, PR-Agent). Haystack does not replace those unless your team explicitly adopts it end-to-end.

---

## What Haystack Adds

### Local git hooks (`hooks/`)

Installed via `haystack hooks install`:

| Hook | Purpose |
| ---- | ------- |
| `pre-commit` | Detects active AI agent sessions (Claude Code, Codex, Gemini CLI, OpenCode); runs truncation checks on staged agent/prompt code; enforces review of `LLM_RULES.md` on agent commits (two-step commit with bypass token) |
| `prepare-commit-msg` | Entire session tracking / commit message preparation |
| `commit-msg` | Entire trailer handling |
| `post-commit` | Condenses session data when an Entire checkpoint exists |
| `pre-push` | Pushes session logs; reminds agents about `haystack submit` when applicable |

Human commits skip the enforcement path in `pre-commit` and pass through immediately.

### Entire session linkage

Hooks delegate to Entire (`~/.haystack/bin/entire`) to attach agent conversation context to commits. Local session metadata lives under `.entire/metadata/` (gitignored). Shared settings are in `.entire/settings.json`.

### Optional PR triage and review (Haystack cloud)

When using the full Haystack product:

- **`haystack submit`** — push branch, open PR, run pre-PR triage
- **`haystack triage <pr-number>`** — risk rating, findings, fix prompts (`--json` for automation)
- Review UI that surfaces agent conversation and verification alongside diffs

This can run **in parallel** with CodeRabbit/Greptile/Devin configured in `.ai-dev-workflow.yaml`; they address different layers (local commit hygiene vs. hosted PR review).

---

## Installation

### One-time CLI

```bash
# Install Haystack CLI (see https://haystackeditor.com/ for current install instructions)
haystack setup
```

### Per-repository hooks

From the repo root:

```bash
haystack hooks install
```

This:

1. Copies hook scripts into `hooks/` and installs `hooks/package.json` dependencies (tree-sitter for truncation AST checks)
2. Sets `core.hooksPath` to `hooks/` (local git config)
3. Creates `.entire/settings.json`, `LLM_RULES.md`, and updates `.gitignore` for `.entire/metadata/`

**Teammates** must run `haystack hooks install` on each clone so `core.hooksPath` points at `hooks/`. Commit `hooks/`, `LLM_RULES.md`, and `.entire/settings.json`; do not commit `hooks/node_modules/` (covered by root `node_modules/` ignore).

After install, run `npm install` in `hooks/` only if the installer did not already install dependencies.

---

## Alignment With This Framework

| Concern | Default in this template | With Haystack hooks |
| ------- | ------------------------ | ------------------- |
| Open PRs | `gh pr create --draft` per protocol 03 | Optional `haystack submit` when team adopts Haystack PR flow |
| Automated review | `review.platforms` in `.ai-dev-workflow.yaml` + protocol 93 | Unchanged; Haystack triage is separate unless you standardize on Haystack review |
| Agent rules at commit | `AGENTS.md`, `REVIEW.md`, protocols | Additional `LLM_RULES.md` enforced on **agent** commits via pre-commit |
| Truncation in agent code | Best practice in docs | Automated scan on staged paths matching `agent/`, `prompts/`, `pipeline/`, etc. |

Customize `LLM_RULES.md` for your project. The template version keeps **`gh pr create`** as the default PR path and documents `haystack submit` as optional.

---

## Customizing `LLM_RULES.md`

`LLM_RULES.md` is shown to agents on the first blocked commit attempt, then a bypass token allows the second attempt with the same staged tree.

Recommended sections to tune:

1. **Creating Pull Requests** — match your VCS workflow (`gh` vs. Haystack-only teams)
2. **No Truncation Without Permission** — keep for agent/prompt-heavy repos; narrow `CHECKED_PATH_PATTERNS` in `hooks/truncation-checker/index.ts` if needed
3. **No Hardcoded Repo Knowledge in Prompts** — useful for template/framework repos

To disable Haystack's mandatory PR wording entirely, edit the PR section in `LLM_RULES.md`; the pre-commit hook only **displays** the file, it does not hardcode Haystack-specific logic beyond the default generated text.

---

## Agent Commit Flow (What Agents Experience)

1. Agent runs `git commit`
2. `pre-commit` detects session (e.g. Claude Code) and prints agent context to stderr
3. Truncation checker runs on relevant staged paths
4. First attempt: commit blocked; full `LLM_RULES.md` + staged stat shown
5. Second attempt (same staged tree): bypass token consumed; commit proceeds
6. Entire hooks run on `prepare-commit-msg`, `commit-msg`, `post-commit`, `pre-push`

Agents using Cursor are not detected by the stock agent-context parsers today; those commits behave like human commits unless detection is extended.

---

## Disabling or Removing

- **Temporarily skip hooks**: `git commit --no-verify` (human decision; do not use routinely for agent work)
- **Uninstall hooks path**: `git config --unset core.hooksPath` and remove or stop using `hooks/`
- **Remove from repo**: delete `hooks/`, `LLM_RULES.md`, `.entire/`, and revert `.gitignore` Entire entries; document the change in `CHANGELOG.md`

---

## Related Files

| Path | Role |
| ---- | ---- |
| `hooks/pre-commit` | Agent detection, truncation check, LLM rules gate |
| `hooks/truncation-checker/` | Pattern and AST-based truncation detection |
| `hooks/agent-context/` | Parsers for Claude, Codex, Gemini, OpenCode sessions |
| `LLM_RULES.md` | Project rules injected on agent commits |
| `.entire/settings.json` | Entire enabled/telemetry flags |
| `docs/best-practices/2-version-control.md` | Default PR conventions (`gh`) |

---

## See Also

- [`pr-review-platform.md`](pr-review-platform.md) — Step 7 multi-platform review loop
- [`coderabbit.md`](coderabbit.md) — CodeRabbit integration (common default reviewer)
- Protocol 93 — [`../protocols/93-automated-reviewer-loop-protocol.md`](../protocols/93-automated-reviewer-loop-protocol.md)
- Protocol 03 — [`../protocols/03-implement-development-protocol.md`](../protocols/03-implement-development-protocol.md) (`gh pr create` steps)

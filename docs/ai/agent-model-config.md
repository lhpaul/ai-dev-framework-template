# AI Agent Model Configuration

This document explains the model assigned to each agent in `.claude/agents/`, the rationale behind each choice, and how to override them when needed.

---

## Model Assignments

| Agent | Model | Rationale |
|---|---|---|
| `orchestrator` | `claude-haiku-4-5-20251001` | Reads state and dispatches subagents — mechanical work that needs to be fast and cheap. No deep reasoning required. |
| `product-manager` | `claude-sonnet-4-5-20250929` | Spec writing requires creativity and structured thinking, but the spec template provides strong scaffolding. Sonnet handles this well at a reasonable cost. |
| `spec-reviewer` | `claude-sonnet-4-5-20250929` | Review against a checklist. Sonnet is well within the capability required. |
| `tech-lead` | `claude-opus-4-5-20251101` | Architecture decisions and implementation planning are the highest-reasoning tasks in the workflow. A weak plan is expensive to fix downstream — this is where Opus pays for itself. |
| `implementation-plan-reviewer` | `claude-sonnet-4-5-20250929` | Validating a plan against a spec and codebase is review work; no architectural invention required. |
| `developer` | `claude-sonnet-4-5-20250929` | Code generation at scale. Sonnet is the cost/quality sweet spot for coding tasks, especially when it receives a strong spec + plan. |
| `code-reviewer` | `claude-sonnet-4-5-20250929` | Code review against known standards and a completed spec. Sonnet is capable here. |
| `project-setup` | `claude-sonnet-4-5-20250929` | Structured onboarding conversation with clear protocol guidance. Sonnet is sufficient. |

---

## Tool Restrictions

Agents that don't require shell access have `Bash` removed from their tool list. This enforces least-privilege — these agents read and write documentation files only.

| Agent | Has Bash? | Reason |
|---|---|---|
| `orchestrator` | ✅ | Needs `git branch`, `git status`, and similar to read repo state |
| `product-manager` | ❌ | Writes spec markdown files only |
| `spec-reviewer` | ❌ | Reads and edits spec files only |
| `tech-lead` | ✅ | May need to run commands to understand the codebase before planning |
| `implementation-plan-reviewer` | ❌ | Reads spec, plan, and source files only |
| `developer` | ✅ | Runs build, lint, and test commands as part of implementation |
| `code-reviewer` | ✅ | May run lint or tests to verify applied fixes |
| `project-setup` | ✅ | May need to initialize git, run project commands during setup |

---

## Overriding the Model for a Task

If a specific feature is unusually complex and you want Opus for the `developer` agent — or you want to cut costs and use Haiku for a trivial spec — you can override the model temporarily:

**Option 1 — In-session override (Claude Code):**
Pass `--model` when invoking an agent:
```
claude --agent developer --model claude-opus-4-5-20251101
```

**Option 2 — Permanent change:**
Edit the `model` field directly in the agent's `.md` file in `.claude/agents/`. This affects all future invocations until changed back.

---

## Updating Models After Anthropic Releases

When new Claude models are released, update the model strings here and in the agent frontmatter files. The current model strings follow the format `claude-[family]-[version]-[date]`.

Current models (as of 2026-02):

- Opus: `claude-opus-4-5-20251101`
- Sonnet: `claude-sonnet-4-5-20250929`
- Haiku: `claude-haiku-4-5-20251001`

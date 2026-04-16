# AI Agent Model Configuration

This document explains the *model tier* assigned to each agent, the rationale behind each choice, and how to override them when needed.

This template is designed to be **LLM-provider agnostic**. The concrete model IDs you use will depend on:

- Which provider(s) you have access to (Anthropic, OpenAI, Google, etc.)
- Which agent runner you use (Claude Code, Codex, Cursor, CI runner, etc.)
- Your cost/latency targets and context-window needs

---

## Model Tiers

Use a small set of tiers and map them to your provider’s current model lineup.

- **`economy`**: fast + cheap; good for mechanical coordination and checklist-style work
- **`balanced`**: general-purpose; best cost/quality default for most writing + coding tasks
- **`premium`**: highest reasoning reliability; reserve for architecture and high-leverage planning

If you prefer different names (`small/medium/large`, `fast/standard/pro`, etc.), keep the same intent.

---

## Agent Assignments (Tier-Based)

| Agent | Tier | Rationale |
|---|---|---|
| `orchestrator` | `economy` | **Portfolio Orchestrator**. Reads state, builds batches, and dispatches Work Item Runners; mechanical coordination that should stay fast and cheap. |
| `item-orchestrator` | `balanced` | **Work Item Runner**. Single-item control loop supervises review-fix-review cycles where parsing findings, determining correct fixes, and verifying them requires capable reasoning. Economy models struggle with multi-step reasoning in fix loops; balanced (sonnet minimum) is required. |
| `automated-reviewer-loop` | `economy` | Runs review + CI loop for a PR; mechanical coordination like the orchestration agents, no deep reasoning required. |
| `product-manager` | `balanced` | Spec writing requires creativity and structured thinking, but the spec template provides strong scaffolding. A balanced model handles this well at a reasonable cost. |
| `spec-reviewer` | `balanced` | Review against a checklist. A balanced model is well within the capability required. |
| `tech-lead` | `premium` | Architecture decisions and implementation planning are the highest-reasoning tasks in the workflow. A weak plan is expensive to fix downstream — this is where a premium model pays for itself. |
| `implementation-plan-reviewer` | `balanced` | Validating a plan against a spec and codebase is review work; no architectural invention required. |
| `developer` | `balanced` | Code generation at scale. A balanced model is typically the cost/quality sweet spot for coding tasks, especially with a strong spec + plan. |
| `code-reviewer` | `balanced` | Code review against known standards and a completed spec. A balanced model is capable here. |
| `project-setup` | `balanced` | Structured onboarding conversation with clear protocol guidance. A balanced model is sufficient. |
| `smoke-tester` | `balanced` | Executes the smoke test runbook using browser automation. A balanced model is sufficient for following step-by-step testing instructions. |
| `retrospective` | `economy` | **Retrospective Analyst**. Reads PR metadata and git history, synthesizes findings into a categorized list; mechanical analysis that should stay fast and cheap. |

### Runner Notes

Use the tier names as stable policy and map them to whatever your current runner and provider support.

- In Claude Code, map the tier to the model family or explicit model ID configured in `.claude/agents/*.md`.
- In Cursor, `fast` is usually a good fit for `economy`, while `inherit` or a pinned high-reasoning model is usually a better fit for `balanced` and `premium`.
- In any runner, prefer keeping the tier intent stable even when provider model names change.

---

## Tool Restrictions

Agents only get `Bash` when they need it to carry a stage through branch creation, commits, pushes, PR creation, or readiness loops. Agents only get `Agent` when they need to dispatch sub-agents to handle stage-specific work.

| Agent | Has Bash? | Has Agent? | Reason |
|---|---|---|---|
| `orchestrator` | ✅ | ✅ | Portfolio Orchestrator: needs `git branch`, `git status`, helper scripts, and issue / PR inspection to build and supervise batches; dispatches `item-orchestrator` sub-agents |
| `item-orchestrator` | ✅ | ✅ | Work Item Runner: needs helper scripts, git / PR inspection, and readiness loops to keep one item moving end to end; dispatches stage agents (developer, code-reviewer, etc.) |
| `automated-reviewer-loop` | ✅ | ✅ | Runs pr-review-loop.sh, pr-ci-loop.sh, git; dispatches fixer agents (spec-reviewer, implementation-plan-reviewer, code-reviewer) when needs_fixes |
| `product-manager` | ✅ | ❌ | Creates spec branches / PRs and may run readiness helpers |
| `spec-reviewer` | ✅ | ❌ | May commit, push, and re-run fixes during spec review loops |
| `tech-lead` | ✅ | ❌ | May need to run commands to understand the codebase before planning |
| `implementation-plan-reviewer` | ✅ | ❌ | May commit, push, and re-run fixes during plan review loops |
| `developer` | ✅ | ❌ | Runs build, lint, and test commands as part of implementation |
| `code-reviewer` | ✅ | ❌ | May run lint or tests to verify applied fixes |
| `project-setup` | ✅ | ❌ | May need to initialize git, run project commands during setup |
| `smoke-tester` | ✅ | ❌ | Runs browser automation and test scripts; needs Bash for execution |
| `retrospective` | ✅ | ❌ | Needs `gh` CLI for PR metadata queries, `git` for history analysis, and `gh issue create` for backlog items; does not dispatch sub-agents |

---

## Overriding the Model for a Task

If a specific task is unusually complex and you want a `premium` model for the `developer` agent — or you want to cut costs and use `economy` for a trivial spec — override the model temporarily.

**Option 1 — In-session override (runner-specific):**
Use your runner’s “one-off model override” mechanism.

Claude Code example (if applicable):

```bash
claude --agent developer --model claude-opus-4-7
```

**Cursor:**
Cursor subagents use the `model` field in `.cursor/agents/<agent>.md`. To override for a single run:

- Switch your Composer's model before invoking the subagent (e.g., `/developer`), or
- Create a duplicate agent file (e.g., `developer-premium.md`) with a different `model` value

**Option 2 — Permanent change:**
Edit the model configuration for the agent:

- **Claude Code**: Edit the `model` field in `.claude/agents/*.md`
- **Cursor**: Edit the `model` field in `.cursor/agents/*.md` (values: `fast`, `inherit`, or a specific model ID)

This affects all future invocations until changed back.

**Cursor model field values:**

- `fast`: Uses Cursor's fast model (recommended for economy-tier agents)
- `inherit`: Uses the current Composer model (recommended for balanced/premium-tier agents)
- Specific model ID: Uses that exact model (e.g., `claude-opus-4-7`, `gpt-4-turbo`)

**Precedence**: When multiple agent locations exist (`.cursor/agents/`, `.claude/agents/`, `.codex/agents/`), Cursor uses `.cursor/agents/` first, then `.claude/agents/`, then `.codex/agents/`.

---

## Updating Model IDs Over Time

Models change frequently across providers. When your provider releases new models (or deprecates old ones), update:

- The model IDs in your agent configuration (e.g. `.claude/agents/*.md` if you use Claude Code)
- Any docs where you’ve pinned concrete model IDs (prefer keeping docs tier-based)

Guideline: keep the **tier intent** stable (economy/balanced/premium) and swap in the closest current equivalents from your provider.

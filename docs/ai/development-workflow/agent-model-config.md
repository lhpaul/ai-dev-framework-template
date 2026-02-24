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
| `orchestrator` | `economy` | Reads state and dispatches subagents — mechanical work that needs to be fast and cheap. No deep reasoning required. |
| `product-manager` | `balanced` | Spec writing requires creativity and structured thinking, but the spec template provides strong scaffolding. A balanced model handles this well at a reasonable cost. |
| `spec-reviewer` | `balanced` | Review against a checklist. A balanced model is well within the capability required. |
| `tech-lead` | `premium` | Architecture decisions and implementation planning are the highest-reasoning tasks in the workflow. A weak plan is expensive to fix downstream — this is where a premium model pays for itself. |
| `implementation-plan-reviewer` | `balanced` | Validating a plan against a spec and codebase is review work; no architectural invention required. |
| `developer` | `balanced` | Code generation at scale. A balanced model is typically the cost/quality sweet spot for coding tasks, especially with a strong spec + plan. |
| `code-reviewer` | `balanced` | Code review against known standards and a completed spec. A balanced model is capable here. |
| `project-setup` | `balanced` | Structured onboarding conversation with clear protocol guidance. A balanced model is sufficient. |

### Example Mapping (Optional)

If you’re using Claude Code with Anthropic models, this repo’s current `.claude/agents/*.md` defaults map roughly like this:

- `economy` → `claude-haiku-*`
- `balanced` → `claude-sonnet-*`
- `premium` → `claude-opus-*`

Treat this as a *starting point*, not a requirement.

---

## Per-Agent Model Recommendations (Cross-Provider Examples)

The goal here is **optionality**: for each agent, pick one model you can access that matches the tier’s intent.

These examples are **current as of 2026-02-24** (model names/IDs change often). Prefer verifying against each provider’s “list models” docs/API.

### `orchestrator` (`economy`)

- OpenAI: `gpt-5-nano`, `gpt-5-mini`
- Anthropic: Claude Haiku (latest)
- Google: Gemini Flash-Lite (latest)
- Alibaba (Qwen): `qwen-flash`, `qwen-turbo`
- DeepSeek: `deepseek-v3`
- Baidu (ERNIE): `ernie-x1-turbo-32k`, `ernie-4.5-turbo-128k-preview`
- Tencent (Hunyuan): Hunyuan Lite / Turbo (latest)

### `product-manager` (`balanced`)

- OpenAI: `gpt-5-mini`, `gpt-5.2` (low/medium reasoning)
- Anthropic: Claude Sonnet (latest)
- Google: Gemini Flash (latest)
- xAI: Grok (latest)
- Alibaba (Qwen): `qwen-plus`, `qwen3-max-2026-01-23`
- DeepSeek: `deepseek-v3.2`
- Baidu (ERNIE): `ernie-4.5-turbo-128k-preview`, `ernie-4.5-21b-a3b-preview`
- Tencent (Hunyuan): Hunyuan TurboS / Standard (latest)
- Moonshot (Kimi): Kimi (latest) for long-context spec work

### `spec-reviewer` (`balanced`)

- OpenAI: `gpt-5-mini`, `gpt-5.2` (low/medium reasoning)
- Anthropic: Claude Sonnet (latest)
- Google: Gemini Flash (latest)
- DeepSeek: `deepseek-v3.2` (with/without “thinking” depending on latency)
- Alibaba (Qwen): `qwen-plus`, `qwen3-max-2026-01-23`
- Baidu (ERNIE): `ernie-4.5-turbo-128k-preview`
- Tencent (Hunyuan): Hunyuan Standard (latest)

### `tech-lead` (`premium`)

- OpenAI: `gpt-5.2` / `gpt-5.2-pro` (high reasoning)
- Anthropic: Claude Opus (latest)
- Google: Gemini Pro (latest)
- xAI: Grok (latest)
- DeepSeek: `deepseek-v3.2` (thinking)
- Alibaba (Qwen): `qwen3-max-2026-01-23` (reasoning-capable)
- Baidu (ERNIE): `ernie-5.0-thinking-preview`, `ernie-4.5-21b-a3b-thinking-preview`
- Tencent (Hunyuan): Hunyuan T1 (latest)
- Zhipu (GLM): `glm-4.7`, `glm-4.6`
- Cohere: `command-a-reasoning-08-2025`
- Mistral: Magistral Medium (latest)
- Open-weight/self-host: Llama 4 Maverick / Scout (pick the larger one for planning)

### `implementation-plan-reviewer` (`balanced`)

- OpenAI: `gpt-5-mini`, `gpt-5.2` (low/medium reasoning)
- Anthropic: Claude Sonnet (latest)
- Google: Gemini Flash (latest)
- DeepSeek: `deepseek-v3.2`
- Alibaba (Qwen): `qwen-plus`, `qwen3-max-2026-01-23`
- Baidu (ERNIE): `ernie-4.5-turbo-128k-preview`
- Tencent (Hunyuan): Hunyuan Standard / TurboS (latest)

### `developer` (`balanced`)

- OpenAI: `gpt-5-mini`, `gpt-5.2` (low reasoning for speed; raise if stuck)
- Anthropic: Claude Sonnet (latest)
- Google: Gemini Flash (latest)
- xAI: Grok (latest)
- Mistral: Codestral (latest) for heavy coding; Mistral Small for cheaper tasks
- Cohere: Command R+ (latest) for tool-heavy / retrieval-style coding
- Alibaba (Qwen): `qwen3-coder-plus`, `qwen3-coder-flash`
- DeepSeek: `deepseek-v3.2` (strong coding; optionally “thinking” for gnarly refactors)
- Zhipu (GLM): `glm-4.7`, `glm-4.7-flash`
- Open-weight/self-host: Llama 4 Scout/Maverick (larger for complex tasks)

### `code-reviewer` (`balanced`)

- OpenAI: `gpt-5-mini`, `gpt-5.2` (medium reasoning)
- Anthropic: Claude Sonnet (latest)
- Google: Gemini Flash (latest)
- DeepSeek: `deepseek-v3.2` (thinking optional)
- Alibaba (Qwen): `qwen3-coder-plus-2026-01-23`, `qwen-plus`
- Baidu (ERNIE): `ernie-4.5-turbo-128k-preview`
- Tencent (Hunyuan): Hunyuan Standard (latest)

### `project-setup` (`balanced`)

- OpenAI: `gpt-5-mini`, `gpt-5.2` (low/medium reasoning)
- Anthropic: Claude Sonnet (latest)
- Google: Gemini Flash (latest)
- Alibaba (Qwen): `qwen-plus`
- Baidu (ERNIE): `ernie-4.5-turbo-128k-preview`
- Tencent (Hunyuan): Hunyuan Standard (latest)

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

If a specific task is unusually complex and you want a `premium` model for the `developer` agent — or you want to cut costs and use `economy` for a trivial spec — override the model temporarily.

**Option 1 — In-session override (runner-specific):**
Use your runner’s “one-off model override” mechanism.

Claude Code example (if applicable):
```
claude --agent developer --model claude-opus-4-5-20251101
```

**Option 2 — Permanent change:**
Edit the model configuration for the agent (for Claude Code, this is the `model` field in `.claude/agents/*.md`). This affects all future invocations until changed back.

---

## Updating Model IDs Over Time

Models change frequently across providers. When your provider releases new models (or deprecates old ones), update:

- The model IDs in your agent configuration (e.g. `.claude/agents/*.md` if you use Claude Code)
- Any docs where you’ve pinned concrete model IDs (prefer keeping docs tier-based)

Guideline: keep the **tier intent** stable (economy/balanced/premium) and swap in the closest current equivalents from your provider.

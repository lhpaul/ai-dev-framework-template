# LLM Router Integration (Experimental / Opt-In)

> **Status:** Experimental pattern documentation only. The template does **not** ship, install, or configure any router product. Adopters wire their own router behind an OpenAI-compatible endpoint.

Use this guide when primary subscription quotas are exhausted during long `/run-work` batches or review-fix loops and you want **tier-aligned fallback chains** without forking the framework’s economy / balanced / premium policy.

Related:

- [`../agent-model-config.md`](../agent-model-config.md) — tier definitions and Cursor default model pins
- [`../provider-contingency-runner-failover.md`](../provider-contingency-runner-failover.md) — PR-level resume when a session aborts mid-turn

---

## Pattern overview

1. Define three router **combos** mapped to framework tiers:

   | Combo | Framework tier | Typical use |
   | ----- | -------------- | ----------- |
   | `fw-economy` | `economy` | Orchestration, reviewer-loop coordination |
   | `fw-balanced` | `balanced` | Implementation, fixers, most reviews |
   | `fw-premium` | `premium` | Spec and plan authoring |

2. Configure each combo as an ordered fallback chain, for example:

   - **Primary:** subscription model the runner already uses
   - **Secondary:** paid low-cost API model (e.g. GLM, DeepSeek, MiniMax — vendor-neutral examples)
   - **Stop:** do not chain to unstable “free forever” proxies for client or production code

3. Point Cursor, Claude Code, or Codex at a **local OpenAI-compatible base URL** served by your router (product-specific; not bundled here).

4. Align router model IDs with pinned values in `.cursor/agents/*.md` and `.claude/agents/*.md` so subagents stay on the intended tier when the router selects a fallback.

---

## Runner alignment

| Runner | Configuration surface |
| ------ | --------------------- |
| Cursor | `.cursor/agents/<agent>.md` `model` field + Cursor settings for custom OpenAI-compatible endpoints |
| Claude Code | `.claude/agents/*.md` model IDs + Claude Code provider / base URL settings |
| Codex | Provider and model settings for the Codex CLI or IDE integration |

Keep **tier intent** stable in agent files; change router combo mappings when you add or remove fallback models.

---

## Reference implementations (examples only)

These are **illustrative** third-party tools — not dependencies of this template:

- [9Router](https://github.com/deanxv/9router) — multi-provider OpenAI-compatible proxy
- [claude-code-router](https://github.com/musistudio/claude-code-router) — routing layer for Claude Code-style clients

Evaluate licensing, privacy, and operational fit before adoption.

---

## Guardrails (required reading)

### Terms of service and OAuth

Routing consumer OAuth sessions through unofficial proxies may violate provider terms (e.g. Anthropic consumer ToS updates in 2026). Prefer official API keys and documented enterprise paths for production or client work.

### Privacy

Do **not** route client repositories, credentials, or sensitive code through opaque free proxies. Run routers on infrastructure you control; log and retention policies must match your compliance requirements.

### Quality

Fallback models may fail review-fix loops or mis-parse workflow scripts. Reserve strong models for `balanced` and `premium` tiers; use economy fallbacks only for mechanical coordination.

### Continuity limits

Routers do not replace PR-level resume. Mid-turn failures still require [`provider-contingency-runner-failover.md`](../provider-contingency-runner-failover.md) and `workflow-next-action.sh`.

---

## Explicit non-goals

- No router install scripts in this template
- No default `.ai-dev-workflow.yaml` keys until the pattern is validated in downstream dogfooding
- No endorsement of a single vendor or “always free” model tier for production workflow automation

When dogfooding validates a pattern, downstream repos may document their router combo YAML in `.ai-dev-workflow.local.yaml` (local-only) and link back to this guide.

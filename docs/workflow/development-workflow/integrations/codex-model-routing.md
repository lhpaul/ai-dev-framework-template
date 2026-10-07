# Codex Role and Model Routing

Use the [shared role policy](../agent-model-config.md) to choose a tier, then select a model and reasoning effort supported by your Codex installation and provider. A skill's recommended tier is guidance: loading that skill does not switch the runtime model.

This adapter supplies opt-in task profiles and a native reviewer configuration. It does not install a dispatcher or activate project settings. Model IDs in the examples are deliberate replacement values; customize them before use.

## Surface audit and tier strategy

Audit at implementation base `2da2bad04d564327e3760bc8cce525ab0ed825fe`:

| Surface | Role in routing | Runtime enforcement |
| --- | --- | --- |
| `.codex/skills/workflow-*/SKILL.md` | Canonical role protocols and recommended tiers | Skill prose does not select a model |
| `.agents/skills/` | Repo discovery, shared skill wrappers and command aliases | An alias delegates to its canonical skill; it is not an agent model pin |
| Skill `agents/openai.yaml` metadata | Skill labels and invocation prompts | UI metadata is not a native custom-agent configuration |
| Root `AGENTS.md` | Workflow discovery and repository constraints | Applies instructions, without per-role model selection |
| `agent-model-config.md` | Canonical tier intent and role assignments | Operator or runtime config maps tiers to available models |
| Bundled local Codex reviewer preset | `LOCAL_CODEX_REVIEWER_BIN` and optional `LOCAL_CODEX_REVIEWER_MODEL` | Selects the executable/model for that separate review invocation |
| Native `.codex/agents/*.toml` | Optional role configuration, supplied here as an inactive example | Applies model/effort only when that named agent is actually spawned |

No active root `.codex/config.toml` or `.codex/agents/` configuration was shipped at that base. The examples below live under documentation and are not auto-loaded. Both skill trees were inspected; tier policy remains in their existing canonical definitions.

| Tier | Workflow roles | Selection strategy |
| --- | --- | --- |
| `economy` | Portfolio scan, reviewer-loop coordination, template sync | Choose an available fast, economical model for mechanical work |
| `balanced` | Item execution, implementation, reviews, setup, retrospectives | Choose a capable general model; raise effort for difficult review/fix loops |
| `premium` | Spec writing and technical planning | Choose the strongest suitable reasoning model for ambiguous requirements and architecture |

The shared role table is authoritative for individual assignments. A tier is not a price promise, and effort is a separate setting whose supported values depend on the chosen model. Consult the current account/provider catalog instead of assuming a model from an illustrative table is available.

## Verified capability boundary

Inspected on 2026-10-07 with `codex-cli 0.159.2`. `codex --help` and `codex exec --help` advertise `-m`/`--model`, `-c`/`--config` TOML overrides and `-p`/`--profile`.

Official configuration contracts:

- [Advanced configuration](https://learn.chatgpt.com/docs/config-file/config-advanced): task overrides, separate profile files, configuration precedence and user-level providers.
- [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents): standalone custom-agent fields, explicit delegation and model/effort precedence.
- [Configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference): model/provider settings and Responses wire protocol.

The delivered TOML was parsed and inspected against these contracts; CLI help was checked. Live model inference, native agent dispatch and 9Router interoperability were not executed. See the [smoke runbook](../../../testing/workflow/codex-model-routing.smoke-test.md) for reproducible checks and evidence.

## Task-level selection and fallback

For any stage, select a model available to the active provider and an effort it supports. These example commands perform review work when run; replace the model token before executing them.

<!-- workflow-shell-contract: bash -->
```bash
codex -m AVAILABLE_MODEL -c 'model_reasoning_effort="high"'
codex exec -m AVAILABLE_MODEL -c 'model_reasoning_effort="high"'   'Read REVIEW.md and review the explicitly selected artifact; report findings without editing.'
```

`-c` values use TOML syntax; quoting the effort string matters. A task-level choice controls that invocation, not every future workflow role. To change the role's route reliably without native delegation, start a separate invocation with the desired settings and pass its bounded artifact, branch, head and review contract. Record the effective selection and result in the workflow handoff.

The observed operator wrapper `codex-review-high` delegates to `codex -c model_reasoning_effort="high"`; the operator's devsession launcher also accepts `--effort`. Those are local entry points, not new Codex CLI flags or template defaults. The bundled reviewer preset's executable/model controls can select such a wrapper. The separate `LOCAL_CODEX_REVIEWER_EFFORT` feature is tracked in #1895 and is not implemented by this adapter.

### Current profile format

Customize [review.config.toml](examples/codex-model-routing/review.config.toml), then install it as `~/.codex/review.config.toml` (or under your existing `CODEX_HOME`). Preserve your existing user settings when installing any example.

<!-- workflow-shell-contract: bash -->
```bash
codex --profile review
codex exec --profile review 'Read REVIEW.md and review the selected artifact without editing.'
```

In Codex 0.134.0 and later, `--profile review` overlays `<CODEX_HOME>/review.config.toml` on the base user config. Use top-level keys in that file. Legacy `[profiles.review]` tables in `config.toml` and the top-level `profile` selector are no longer read. Project and CLI layers can override profile settings; inspect your selected configuration rather than assuming a profile always wins. Older clients require their version's documented format.

## Native role configuration and explicit dispatch

Current documented native custom agents support standalone TOML in `~/.codex/agents/` or project `.codex/agents/`. Customize [reviewer.toml](examples/codex-model-routing/reviewer.toml), including its model and supported effort, then install it as `reviewer.toml` in one of those directories. Its required fields are `name`, `description` and `developer_instructions`; this example also sets `model` and `model_reasoning_effort` explicitly.

Start an interactive Codex session in the target repository and explicitly request the installed role, for example:

```text
Use the native custom agent named reviewer to review PR #N at head SHA H.
Read AGENTS.md and REVIEW.md and apply the matching stage checklist.
Wait for that agent and report its reviewed SHA, selected model/effort and findings.
Do not edit or merge. If the named agent is unavailable, report that limitation.
```

This is a delegation instruction, not a `--agent` CLI flag. Confirm the spawned agent is the named role and has the intended settings; an ordinary inline review does not demonstrate per-role routing. Skill discovery alone does not dispatch this agent. The sample name `reviewer` takes precedence over a built-in role of the same name if present; choose a different name and matching request when that substitution is unwanted.

Model and effort first resolve from explicit spawn settings, then `[agents]` defaults, then the parent. A spawn/default selecting a model without an effort uses that model's default effort. Settings present in the custom-agent file override the resolved values. A file setting only `model` can preserve an incompatible resolved effort, so this sample sets both. Other omitted session settings inherit; this sample leaves provider selection to the parent and does not demonstrate different providers per role.

If native configuration is unsupported, disabled or not observed in your client, use the separate task invocation above and report native dispatch as unavailable or untested. A native role does not replace workflow scope, review gates, tracker checks or merge authorization.

## Optional Responses router

Customize [router.config.toml](examples/codex-model-routing/router.config.toml) and install it as a user profile at `~/.codex/router.config.toml`. Select a real endpoint, its supported model ID and a supported effort. The example references an environment variable for authentication and contains no credential value; supply that variable through your existing secure environment.

<!-- workflow-shell-contract: bash -->
```bash
codex --profile router
```

Provider definitions belong to user-level configuration/profile files. Project `.codex/config.toml` ignores provider/auth/profile keys; putting them there does not activate a route. This opt-in profile chooses a separate provider ID, leaves the built-in provider unchanged, and is inactive unless selected. For other proxy choices, follow the official provider documentation rather than copying incompatible client settings.

Codex requires the Responses wire protocol (`wire_api = "responses"`). A generic OpenAI-compatible or Chat Completions endpoint claim is insufficient: verify Responses requests, streaming, authentication, selected-model availability and tool-call/result semantics against your actual router. Before calling a route usable, perform a small authorized live task, including a harmless tool call, and confirm the route and result; record version, model, protocol and observed limitations without credentials. Static TOML parsing proves syntax, not interoperability.

Keep tier intent stable while mapping router model IDs locally. This guide does not establish live 9Router support or cross-provider native-role parity. #1760 remains independent and the practical OpenCode CLI adapter track for router-based per-agent routing unless equivalent Codex support is demonstrated in the target environment. See [router integration](llm-router.md) for the optional pattern and [runner failover](../provider-contingency-runner-failover.md) for resuming interrupted PR work.

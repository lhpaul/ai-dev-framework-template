# Codex Model Routing — Implementation Plan

**Spec**: [Approved spec](1_codex-model-routing_specs.md)
**Smoke test runbook**: [Codex routing smoke checks](../../../testing/workflow/codex-model-routing.smoke-test.md)

## Summary

**Approach**: Deliver an opt-in Codex adapter guide and editable TOML examples, using official configuration contracts and the installed CLI as capability evidence. Keep tier intent in existing skills; distinguish task settings, native custom agents, and router compatibility. No active consumer configuration or workflow dispatcher changes are introduced.

**Estimated complexity**: S — documentation, optional configuration examples, and smoke evidence; no service or executable adapter is installed.
**Dependencies**: None. Related #1760 and #1895 remain separate tracks under the approved spec's boundaries.

## Verification Log

Repository evidence revision: `087fcc03638c3d340a4963a6c057dc1bae07ad4b` (merged spec).

| Check | Reproducible command/query | Result |
| --- | --- | --- |
| Role tier recommendations | `rg -n '^Recommended model tier' .codex/skills/workflow-*/SKILL.md .agents/skills/workflow-*/SKILL.md` | Both trees carry role tier guidance; spec/plan writers use premium, implementer/code reviewer/item runner balanced, portfolio runner economy. |
| Native project configuration presence | `rg --files .codex .agents` | Skill files and skill UI metadata are present; no root `.codex/config.toml` or root `.codex/agents/*.toml` is shipped at this revision. |
| Root and shared model guidance | `rg -n 'Codex|codex' AGENTS.md docs/workflow/development-workflow/agent-model-config.md docs/workflow/development-workflow/integrations/llm-router.md` | Existing guidance identifies Codex skills/tiers and generic provider/model settings, without a dedicated routing guide. |
| Local reviewer model selection | `rg -n 'LOCAL_CODEX_REVIEWER_BIN|LOCAL_CODEX_REVIEWER_MODEL|codex_args' scripts/development-workflow/local-codex-review-command.sh` | The bundled preset accepts a selected executable and optional model; it delegates execution to Codex. |
| Sync ownership | `rg -n 'docs/workflow/|docs/testing/workflow/|AGENTS.md' sync-manifest.yaml` | Workflow docs are recursively synced; root agent guidance has mixed ownership; smoke runbooks use explicit entries. |
| E2E applicability | `rg -n 'placeholder\|E2E' .github/workflows/e2e-regression.yml`; `rg --files e2e/tests`; `rg -n 'placeholder\|expect\(true\)' e2e/tests/baseline.spec.ts` | Workflow declares Template Placeholder and is gated by ENABLE_TEMPLATE_PLACEHOLDER_REGRESSION; the committed test directory contains baseline.spec.ts, whose baseline placeholder asserts true. REVIEW.md explicitly exempts this template placeholder from the non-placeholder E2E fixture requirement. |
| Installed CLI | `codex --version` and `codex exec --help` | `codex-cli 0.159.2`; model, TOML config override, and file-layer profile flags are advertised. |

### Factual claim evidence

Official sources inspected on 2026-10-07:

- [Advanced configuration](https://learn.chatgpt.com/docs/config-file/config-advanced): task-level overrides, current profile-file format, the legacy profile migration boundary, and user-level provider ownership.
- [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents): standalone custom-agent schema, model/effort inheritance, and role override semantics.
- [Configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference): custom provider keys and Responses wire protocol.
- Context7 `/openai/codex`, query covering model/effort/profiles/providers/native roles: corroborates provider and role override source code. Its legacy role/profile snippets are not the format to copy for the installed CLI; use the current official sources above.

The guide will distinguish these documented capabilities from smoke checks actually executed. No live 9Router request or native subagent inference has been tested during planning; no equivalent OpenCode interoperability claim is justified.

## Cross-Cutting Operational Assumption Check

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact owner and base | Current single repository, PRs to develop | Invocation, bounded prelude, `.ai-dev-workflow.yaml` | 2026-10-07, Verification Log revision | Current invocation contains #1761 only; spec PR #1912 is merged into develop. The missing integration branch is resolved by the explicit operator base. | Verified |
| Consumer activation | Optional examples only; existing active configuration remains operator-owned | Approved spec Business Rules and Out of Scope | Same inspection as preceding row | No runtime change to #1760 or #1895; existing issue scope and operator boundary agree. | Verified |

Before implementation edits, re-read the cited sources and report `Still valid` for these rows; changed or unverifiable evidence stops implementation under Protocol 91.

## Layer-by-Layer Changes

### Documentation and optional configuration

Use the files listed below for AC1–AC5. Role policy remains canonical in the shared model document; the new guide owns Codex-specific runtime behavior. Existing skills keep tier guidance and are audited rather than individually patched. Native examples are inactive until copied/customized by an operator, with model IDs chosen from their provider's catalog. The optional provider example inherits into native agents from the parent session; it does not claim cross-provider role switching.

### Validation

Use the linked runbook for AC6. Validate actual TOML examples with Python's existing TOML parser, inspect required custom-agent fields against the cited schema, check CLI-supported flags against help, run existing Markdown/link lint, and inspect the rendered documentation flow. No custom parser, matcher, CI gate, or automated dispatcher is added.

## Files to Modify or Add During Implementation

| Path | Purpose / AC coverage |
| --- | --- |
| `docs/workflow/development-workflow/integrations/codex-model-routing.md` | Canonical adapter guide, surface audit and instructions; AC1–AC5 |
| `docs/workflow/development-workflow/integrations/examples/codex-model-routing/reviewer.toml` | Editable native balanced-role example with explicit model/effort and required instructions; AC3, AC6 |
| `docs/workflow/development-workflow/integrations/examples/codex-model-routing/review.config.toml` | Task profile example; AC2, AC6 |
| `docs/workflow/development-workflow/integrations/examples/codex-model-routing/router.config.toml` | User-level opt-in Responses provider/profile example; AC4, AC6 |
| `docs/workflow/development-workflow/agent-model-config.md` | Shared policy entry point; AC1, AC5 |
| `docs/workflow/development-workflow/integrations/llm-router.md` | Relevant runner compatibility entry point; AC4, AC5 |
| `docs/workflow/development-workflow/README.md` | Integration index; AC5 |
| `AGENTS.md` | Template-owned Codex routing discovery pointer; AC1, AC5 |
| `sync-manifest.yaml` | Explicit shipping entry for the runbook; examples and guide are covered by the existing workflow-docs glob; AC6 |
| `docs/testing/workflow/codex-model-routing.smoke-test.md` | Runbook and implementation evidence; AC6 |
| `changelog.d/1761-codex-model-routing.md` | Feature release note |

No application, database, credentials, local configuration, reviewer effort plumbing, or workflow runtime scripts need changes. New TOML files live under documentation, not the auto-loaded `.codex/agents/` directory.

## Testing Strategy

**Test types**: Configuration smoke checks, CLI capability checks, existing Markdown lint and manual documentation review.
**Coverage intent**: Cover task selection, native-role authoring, optional provider syntax/protocol boundaries, entry-point links and consumer sync. The runbook's scenarios are indicative coverage classes, not a frozen numerical enumeration. Static checks prove authoring/syntax only; live model availability, native dispatch inference and router interoperability require an operator's configured environment and must be reported untested when not executed.

No custom unit suite is proportionate to inactive examples and prose. Parser-risk, concurrent-event-source, new cross-cutting-checklist and planted-violation signals are not applicable: no parser or enforcement code is changed. The repository's E2E regression job is a placeholder; no application fixtures apply.

## Seed Data

None. Editable TOML examples are test inputs; no router credentials or production data are required for static validation.

## Implementation Order

1. Revalidate the operational assumptions and official source contracts at implementation start.
2. Deliver the optional configurations and canonical adapter guide as one coherent sub-part; execute configuration smoke checks before checkpoint commit (AC1–AC4, AC6).
3. Update the documentation entry points, shipping manifest and changelog listed in Files to Modify; complete runbook evidence and commit the integration sub-part after lint passes (AC5, AC6).
4. Complete both internal review passes, configured reviewer and CI loops, readiness gates, and live risk classification. The invocation authorizes merge only at low risk; a higher classification is a ready PR handoff, not a merge.

## Risks and Rollback

Configuration syntax changes across Codex versions; version-labeled official references and CLI verification bound the guide's claims. Placeholder model IDs require operator customization before use. A compatible-looking router may still lack Responses streaming or tool semantics; do not claim interoperability from static validation. All examples are inactive, so reverting the implementation PR removes guidance and examples without changing running consumer settings.

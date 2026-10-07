# Codex Model Routing — Spec

## Overview

Template operators need an explicit way to translate workflow roles and recommended model tiers into supported Codex execution settings. This feature provides verified routing guidance, explains which choices the operator or harness must make, and states where native capabilities do not establish parity with other runners. Consumer repositories retain provider-agnostic defaults and can adopt a compatible local model router without requiring it.

## Use Cases

### Use Case 1: Choose a route for a workflow task

**Actor**: Operator running a workflow stage in Codex.
**Preconditions**: The operator has a supported Codex installation and a selected workflow role.

**Steps**:

1. Read the role's recommended tier and the canonical role policy.
2. Consult the Codex adapter guide for supported task-level model and reasoning choices.
3. Select a locally available route and start the stage with the documented settings.

**Postconditions**: The operator can identify the selected model and reasoning setting without assuming the skill changes either automatically.

**Information shown**: Verified configuration examples, their scope, version caveats, and capability limitations.
**Actions available**: Choose task settings, use a local profile, or retain the current runner defaults.
**Considerations**: Model availability and supported reasoning levels vary by provider and installed version.

### Use Case 2: Evaluate local routing and specialist roles

**Actor**: Consumer repository maintainer.
**Preconditions**: The maintainer wants optional local routing or different models for specialist work.

**Steps**:

1. Review the Codex surface audit and native role configuration evidence.
2. Compare documented native capabilities with task-level fallback guidance.
3. Validate any optional router against the protocol Codex actually uses before adopting it.

**Postconditions**: The maintainer understands which routing is supported, which requires explicit dispatch/configuration, and which is unverified.

**Information shown**: Router compatibility requirements, skill versus runtime distinctions, and an independent OpenCode alternative.
**Actions available**: Adopt verified Codex settings, continue with task-level selection, or use the OpenCode adapter track.
**Considerations**: A generic compatible endpoint claim does not prove working Codex tool calls or role routing.

## Business Rules

- Recommended tiers express role intent; loading a skill does not itself select a runtime model.
- Guidance must be grounded in official documentation and the installed CLI, distinguishing documented support from locally executed smoke evidence.
- Local providers, model identifiers, credentials, and operator-specific defaults must not become mandatory template settings.
- Native specialist routing must be described only to the extent supported by verified configuration; unsupported parity claims must be replaced with an explicit fallback.
- The OpenCode work in #1760 is independent and remains the practical CLI path for router-based per-agent routing unless equivalent Codex support is demonstrated.
- The separate local-reviewer effort feature in #1895 is outside this feature's implementation scope; existing local wrappers can serve as capability evidence.

## Acceptance Criteria

- [ ] AC1: The maintainer can find a Codex surface audit covering both skill trees, root agent guidance, and workflow model documentation, with an explicit role/tier/model strategy.
- [ ] AC2: The guide demonstrates verified task-level model selection, reasoning configuration, and supported local profile usage, identifying their scope and installed-version caveats.
- [ ] AC3: The adapter distinguishes skill tier recommendations from native role/model enforcement. When native role-specific routing is verified, it supplies usable role-routing configuration and dispatch instructions with smoke validation. For capabilities not established, it supplies a usable task-level fallback.
- [ ] AC4: Optional local-router guidance preserves provider-agnostic defaults, states protocol and authentication requirements, and does not claim untested live router compatibility.
- [ ] AC5: Shared role/model documentation links to the adapter, preserves #1760 independence, and does not implement the separate #1895 feature.
- [ ] AC6: Reproducible smoke checks validate the task-level examples, any native role-routing configuration required by AC3, and relative documentation links; evidence identifies any live-network routing not tested.

## Brief Objective List and Coverage Matrix

| Objective from #1761 | Coverage |
| --- | --- |
| Audit current Codex skill, agent guidance, and workflow surfaces | AC1 |
| Define consumption of role/tier policy | AC1, AC2, AC3 |
| Add verified native routing guidance/configuration where supported | AC2, AC3, AC6 |
| State limitations and supported fallback honestly | AC3, AC4 |
| Align with OpenCode without a dependency | AC5 |
| Update canonical model policy and relevant adapter docs | AC5 |
| Preserve provider-neutral defaults and feasible router usage | AC4 |
| Cover introduced configuration, links, and behavior | AC6 |

## Out of Scope (MVP)

- Implementing the OpenCode adapter or making #1760 depend on this feature.
- Implementing the local-reviewer effort variable tracked by #1895.
- Installing a router, changing operator credentials/configuration, selecting consumer model defaults, or asserting live router interoperability without a live test.
- Changing workflow permissions, checkpoints, reviewer selection, or automatic role dispatch behavior.

No brief objectives are deferred. The exclusions bound adjacent work rather than omit requirements.

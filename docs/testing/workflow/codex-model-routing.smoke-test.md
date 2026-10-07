# Codex Model Routing — Smoke Test

**Feature**: #1761
**Spec**: [Codex routing spec](../../specs/developments/20261007101438_codex-model-routing/1_codex-model-routing_specs.md)
**Plan**: [Implementation plan](../../specs/developments/20261007101438_codex-model-routing/2_codex-model-routing_implementation-plan.md)

## Preconditions

Use the repository's Python with TOML support and installed Codex CLI. Static checks need no credentials. Live checks require an operator-selected model/provider and explicit authorization for that environment; static success does not establish live compatibility.

## Scenarios

### Task model and reasoning selection (AC1, AC2)

1. Inspect `codex --version`, `codex --help` and `codex exec --help`.
2. Confirm the guide uses the installed model/config/profile flags and identifies the profile format for that version.
3. Trace an example task from its skill tier to an operator-selected model and effort, without claiming the skill itself changes the model.

**Expected**: Instructions match help and official docs; model choice is explicit.

### Native role configuration (AC3)

1. Load the delivered native reviewer TOML with Python's TOML parser.
2. Confirm it declares name, description, developer instructions, model and reasoning effort, and points the operator to the workflow review contract.
3. Follow the guide's installation and explicit role-dispatch instructions conceptually; verify the model placeholder must be customized and the sample is not auto-loaded from the docs directory.

**Expected**: A schema-grounded editable role config and usable instructions are supplied. Static parsing does not claim that a live native-role inference was executed.

### Profiles and optional router (AC2, AC4)

1. Parse the task and router profile examples with Python's TOML parser.
2. Verify the router example uses user-level provider configuration, an environment-key reference, and the documented Responses wire protocol.
3. Verify the guide requires a model available on that route, preserves provider-neutral defaults, and keeps #1760 independent.

**Expected**: No real credentials/endpoints or mandatory provider pins. Unsupported or unverified live compatibility is identified explicitly.

### Discovery and consumer shipping (AC1, AC5, AC6)

1. Follow the new entry-point links from root agent guidance, the model policy, the workflow index and router guide.
2. Confirm both skill trees are represented by the surface audit and preserve tier recommendations.
3. Confirm the sync manifest covers the new guide/examples and explicitly includes this runbook.
4. Run existing Markdown lint, shell-snippet lint when executable snippets are added, and `git diff --check`.

**Expected**: Links resolve, consumers receive the guidance, and existing defaults remain optional.

## Execution Evidence

Populate in the implementation PR with version, commands, results and head SHA. Live native-role inference and live 9Router interoperability must be marked untested unless actually executed; do not infer either from static smoke checks.

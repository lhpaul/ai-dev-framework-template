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

## Reproducible static check

From the repository root, run this with Python 3.11 or later. It parses the delivered examples and checks the fields used by this adapter against the cited official contract; it does not load them into Codex or contact a provider.

```python
from pathlib import Path
import tomllib

examples = Path("docs/workflow/development-workflow/integrations/examples/codex-model-routing")
for name in ("review.config.toml", "reviewer.toml", "router.config.toml"):
    config = tomllib.loads((examples / name).read_text())
    assert config["model"]
    assert config["model_reasoning_effort"] == "high"
    if name == "reviewer.toml":
        for key in ("name", "description", "developer_instructions"):
            assert isinstance(config[key], str) and config[key]
    if name == "router.config.toml":
        provider = config["model_providers"][config["model_provider"]]
        assert provider["wire_api"] == "responses"
        assert provider["env_key"] == "WORKFLOW_ROUTER_API_KEY"
    print(name, "PASS")
```

Use `codex --version`, `codex --help` and `codex exec --help` for capability inspection. Run Markdown/link lint on the changed Markdown files, `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`, `bash scripts/development-workflow/changelog-fragments.sh validate`, and `git diff --check` for integration validation.

## Execution Evidence

Implementation inspection on 2026-10-07, guide/examples checkpoint `9b4bf010` on base `2da2bad04d564327e3760bc8cce525ab0ed825fe`. The implementation PR's gate summary binds final evidence to its reviewed head.

| Check | Result |
| --- | --- |
| `codex --version`, `codex --help`, `codex exec --help` | 0.159.2; model, config and profile flags advertised |
| Delivered TOML parse and field checks above | PASS for task profile, native reviewer and router profile |
| Native schema and dispatch instructions | Inspected against current official Subagents docs; explicit role request, model/effort overrides and parent-provider inheritance described |
| Task/profile instructions | Inspected against current Advanced configuration docs; separate profile files, version boundary and precedence described |
| Root/model/index/router links | Markdown relative-link lint passes; each entry point leads to the adapter |
| Consumer shipping | Workflow docs/examples covered by existing recursive manifest entry; runbook explicitly added with the same hub-only scope |
| Markdown, shell-snippet and fragment lint; `git diff --check` | PASS after correcting shared-shell snippet declarations |
| Live model inference and native dispatch | UNTESTED; example models require operator customization |
| Live 9Router requests, streaming and tool calls | UNTESTED; static syntax does not demonstrate compatibility |

Manual documentation-flow review followed both spec use cases: role/tier to explicit task settings, and optional native role/router evaluation. No active configuration was installed, no credentials were supplied, and no OpenCode or reviewer-effort-variable feature was implemented.

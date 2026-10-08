# Integration: DeepSeek Harness (DSH)

DSH is a first-class **local-runtime** runner for this template’s staged workflow:
command matrices, Protocol 91 Step 7a draft review, shared reviewer skills against
[`REVIEW.md`](../../../../REVIEW.md), model-tier guidance, and provider failover.

The shipped `review.on_draft.runner` list remains Claude-only (`[claude]`). Opt DSH
into Step 7a with a machine-local override — do not change the shared template
default for clones that do not install DSH.

Minimum CLI verified for the contracts below: `dsh` `0.2.0-rc.2` (`dsh --version`).
Re-verify headless and permission-preset wiring after major DSH upgrades.

---

## Install

1. Install the DeepSeek Harness CLI so the `dsh` binary is on `PATH`.
2. Confirm the probe used by Step 7a availability:

   <!-- workflow-shell-contract: bash-zsh -->
   ```bash
   dsh --version
   ```

3. Boot a profile once to complete provider auth / settings for your machine
   (interactive `web` is the usual first path; see Profiles).

This template does **not** package or distribute the DSH binary. Availability
probing is `dsh --version` via the same local-runtime path as Claude / Cursor /
Codex (`scripts/development-workflow/resolve-reviewer-availability.sh`).

---

## Profiles

A **profile** is what `dsh --profile <name>` boots (an ordered stack of plugin-bundle
layers under local overrides). Common shipped profiles:

| Profile | Use |
| ------- | --- |
| `web` | Interactive browser UI (loopback). |
| `headless` | One-shot task: print the final answer to stdout and exit. |

Examples:

<!-- workflow-shell-contract: bash-zsh -->
```bash
dsh web
dsh --profile headless "Summarize the open PR"
```

`dsh headless …` is accepted as a short form of `dsh --profile headless …`.

---

## Provider routes

DSH composes session-default model routes from the active profile’s bundle and the user’s local
settings (not from in-repo agent frontmatter). The base bundle’s default route is
provider/model configuration owned by the DSH install — operators pin or swap
routes in DSH settings / profile overlays, then keep workflow **tier intent**
stable (see [`agent-model-config.md`](../agent-model-config.md)).

Commercial API keys and org credentials stay outside the repository (1Password or
the harness’s own credential store). This guide does not invent vendor-specific
setup beyond “configure a working route before relying on headless review.”

---

## Subagent model selection

DSH has **no** in-repo per-role agent tree analogous to `.claude/agents/` or
`.cursor/agents/`. Stage reviews dispatch the shared workflow skills Codex uses:

| Stage | Skill (against `REVIEW.md`) |
| ----- | --------------------------- |
| Spec | `workflow-spec-reviewer` |
| Plan | `workflow-plan-reviewer` |
| Implementation | `workflow-code-reviewer` |

For children in a DSH driving session, resolve optional project role/tier policy
and pass the selected route through the subagent tool as described below.
Cross-runner headless review pins its invocation default separately; no
checked-in DSH role file is required.

---

## Project role and tier routing

Optional `models.dsh` policy belongs in `.ai-dev-workflow.yaml`; private machine
changes belong in `.ai-dev-workflow.local.yaml`. The template and local example
contain fully commented examples and activate no model. This is DSH child
routing; other runners and headless defaults keep their existing behavior.

YAML anchors, aliases and merge keys are unsupported in `models.dsh`.
Write explicit block mappings instead: `&` anchors, `*` aliases and `<<` merge
keys fail closed with `invalid_yaml`, exit 2 and no success route. Their syntax
is recognized only to activate strict rejection; it is never applied to route
composition. Those characters inside quoted scalar ids remain ordinary text.

Use block mappings supported by the existing strict reader. Configure
`tiers.economy`, `tiers.balanced`, `tiers.premium` with `provider`, `model`, and
optional `reasoning_effort`. A `roles` entry uses a canonical role name from
[Agent Assignments](../agent-model-config.md#agent-assignments-tier-based) and is
either a supported tier name or a direct route mapping. Effort ids belong to
the installed adapter; ADF does not define another effort enum.

```yaml
models:
  dsh:
    tiers:
      balanced:
        provider: YOUR_PROVIDER
        model: YOUR_BALANCED_MODEL
      premium:
        provider: YOUR_PROVIDER
        model: YOUR_PREMIUM_MODEL
    roles:
      developer: balanced
      product-manager: premium
```

Replace the illustrative ids with already working routes; provider/account
setup is outside this feature. Local maps deep-merge over committed maps by
key and route field. For example, a local provider-only override retains the
committed model; unrelated roles and tiers retain their values. A tier-reference
string replaces a route mapping and a mapping replaces a reference. Empty
local maps add no field override; null and empty scalar values are errors.

For role R, a local role entry wins over a committed role entry. A direct role
route outranks any default-tier route; a reference selects its named tier,
composed locally over committed tier fields. Without a role entry, resolve the
role's recommended tier locally over committed policy, then inherit if absent.
An explicit `--tier` changes only that default, so a configured role still wins.
A winning reference to a tier with no configured route is an error.

### Read-only inspection and validation

<!-- workflow-shell-contract: bash-zsh -->
```bash
python3 scripts/development-workflow/workflow-config-resolver.py model-route \
  --runner dsh --role developer --repo-root "$PWD" --json
python3 scripts/development-workflow/workflow-config-resolver.py model-routes \
  --runner dsh --repo-root "$PWD" --json
bash scripts/development-workflow/validate-workflow-config.sh --repo-root "$PWD"
```

`model-route` requires `--role` or `--tier`. Its JSON keys and shell KEY=value
fields are ROLE, TIER, PROVIDER, MODEL, REASONING_EFFORT, SOURCE, SOURCE_FILE;
optional or unselected values are empty strings. SOURCE is local-role,
committed-role, local-tier, committed-tier, or inherited. A partial local map
reports local only when it contributes a selected field; an empty map over a
committed map retains committed provenance. A tier-reference result names the
tier route's source/file, regardless of the role reference's layer. Direct role
routes have empty TIER; inherited results have no route/source file.

`model-routes` emits ROUTES (deduplicated provider/model/effort tuples) and
RESOLUTIONS (all canonical roles and explicit tier requests). It includes unused
configured tiers and preserves resolution records sharing a route. Shell output
uses ROUTE_COUNT, RESOLUTION_COUNT, and indexed ROUTE_n_/RESOLUTION_n_ fields.
For a host allowlist, deduplicate exact provider/model pairs separately: effort
is retained in the resolution record but is not part of the host pair identity.

<!-- workflow-shell-contract: bash-zsh -->
```bash
set -euo pipefail
python3 scripts/development-workflow/workflow-config-resolver.py model-routes \
  --runner dsh --repo-root "$PWD" --json \
  | jq '.ROUTES | map({provider: .PROVIDER, model: .MODEL}) | unique_by([.provider, .model])'
```

Inspection never writes configuration, provisions a host/provider, or starts a
child. Local discovery follows the existing override-root, checkout, then
linked-worktree main-clone lookup. Each resolution uses one parsed selected
configuration pair; its evidence applies only to that invocation, not to a
later child dispatch or an atomic transaction across concurrent file edits.

Configured routing rejects unknown roles/tiers/keys, wrong types in either
layer even if masked, invalid YAML, empty ids, incomplete effective routes and
dangling winning references. `model-route` and opted-in `validate` report
structured JSON on stderr with CODE, FILE, FIELD, MESSAGE and exit 2; no success
route or raw YAML snippet is emitted. Fix policy before dispatch. Absent routing
keeps standalone validation's existing grammar/dependency/output behavior.

### Enable child selection and maintain the allowlist

Verified against DSH `0.2.0-rc.2`, the primary `@deepseek-ai/dsh-tool-subagent`
[Selecting a child LLM contract](https://github.com/deepseek-ai/deepseek-harness/tree/dsh-v0.2.0-rc.2/packages/subagent/tool-subagent).
In the Web UI use **Plugins → Subagent → Model selection**, enable selection and
supply a nonempty exact provider/model allowlist. The shipped Web subagent tool
opts in with `modelSelectionSettings: true`; a custom profile must explicitly
opt its chosen subagent tool in. The base/headless tool keeps its existing
non-opted-in behavior. Use a backend advertising `agentOptions`; in-process and
DSH SDK backends support selection, while ACP/Codex/Claude Code reject it.

Alternatively, prepare an operator-controlled profile/invocation overlay for
the settings owner id below; copy effective pairs from the inspection listing.
Overlay rows replace the targeted whole config, so retain required fields when
editing an existing overlay. The following ids are illustrative placeholders.

```yaml
- id: subagent-model-selection-settings
  config:
    enabled: true
    allowedModels:
      - provider: YOUR_PROVIDER
        model: YOUR_BALANCED_MODEL
      - provider: YOUR_PROVIDER
        model: YOUR_PREMIUM_MODEL
```

<!-- workflow-shell-contract: bash-zsh -->
```bash
dsh --profile web --patch /path/to/private-model-selection.yml
```

Start a **fresh top-level session** after changing settings. Its captured exact
allowlist is inherited by children and frozen; later settings changes do not
alter that session. Restored sessions lacking a recorded policy stay disabled.
The opt-in exposes `provider`, `model`, `reasoning_effort`, and
`list_subagent_models`. Catalog membership is advisory: a route absent from the
catalog is not necessarily denied by the exact allowlist or live adapter.

### Resolve, pass, and record at every child dispatch

The DSH parent follows Protocol 91's DSH dispatch contract before each fresh
stage/review child. Resolve the target canonical role and parse its JSON;
never eval it. For SOURCE inherited, omit all route fields. For a configured
route, verify the session's captured selection policy and backend capability,
then pass provider/model together and reasoning_effort only when configured.
Use foreground dispatch where the workflow requires a completed result.

Record the role, tier, requested route, SOURCE/file, actual child route and
parent/child ids in the runner summary or review evidence. If selection is
disabled, report **selection-disabled** visibly and omit all route fields. If
the exact pair is denied, report **allowlist-denied** visibly and omit route
fields. Both inherit the parent route while retaining the requested-source
record. Unknown capability/policy requires the existing runner clarification or
failure path; do not invent permission from catalog output. Invalid project
policy blocks dispatch; post-dispatch/provider failures use ordinary stage
failure handling and are never recast as successful inherited fallback.

### Headless default is separate

Project `models.dsh` does not pick the headless review default or change fork
routing. To pin a headless invocation, configure `agent-default-model` in its
profile or a private invocation overlay using the desired provider/model:

```yaml
- id: agent-default-model
  config:
    provider: YOUR_PROVIDER
    model: YOUR_HEADLESS_MODEL
```

<!-- workflow-shell-contract: bash-zsh -->
```bash
DSH_PERMISSION_MODE=read-only dsh --profile headless \
  --patch /path/to/private-headless-default.yml "Review the current change"
```

Headless defaults and child selection have separate owners. Reverify runtime
capabilities after upgrades. Follow the [DSH routing smoke runbook](../../../testing/workflow/dsh-model-routing.smoke-test.md)
for fixture validation, real distinct tier children in one parent session,
private role override, and both visible host-restriction fallbacks. Config-only
output or mocked adapters cannot establish actual child routing.

---

## Headless mode (cross-runner read-only review)

For one-shot reviews from another runner or automation, use the headless profile
and compose the shipped base-bundle **`read-only` permission preset** through
`DSH_PERMISSION_MODE`. Prompt-only “do not write files” instructions are **not**
sufficient for Step 7a cross-runner parity with Codex’s read-only sandbox.

<!-- workflow-shell-contract: bash-zsh -->
```bash
DSH_PERMISSION_MODE=read-only dsh --profile headless \
  "Read-only review against REVIEW.md for <stage>. Emit exactly one line: VERDICT: APPROVED or VERDICT: NEEDS REVISION."
```

- Final answer goes to **stdout**; diagnostics go to stderr.
- Exit `0` with exactly one valid terminal verdict is required for approval
  (same parent-owned fix / re-run contract as other local-runtime CLIs in
  Protocol 91 Step 7a).
- Never add permission-bypass flags.

Protocol reference: Step 7a “Reviewer dispatch map” cross-runner CLI paragraph in
[`91-orchestrate-work-protocol.md`](../protocols/91-orchestrate-work-protocol.md).

---

## Opt into Step 7a draft review

In `.ai-dev-workflow.local.yaml` (gitignored):

```yaml
review:
  on_draft:
    runner:
      - claude
      - dsh
```

Under the shipped `warn` availability policy, a configured-but-absent `dsh`
binary is `runtime-absent` with the shared install-or-remove remedy; it does not
invent a harder DSH-only failure mode. With only `dsh` configured and the binary
missing, the gate still hard-fails as `zero-reachable`.

Draft-restriction: **Never** — DSH reviews draft PRs without requiring
draft-to-ready conversion solely for DSH eligibility.

---

## Parent-orchestrated dispatch

**Default contract for DSH:** parent-orchestrated.

The driving session (Work Item Runner / Protocol 91) absorbs item orchestration
and hands stage review work to the shared reviewer skill for the active branch
prefix. DSH does **not** rely on a separate two-hop native handoff profile
document (unlike Cursor’s [`cursor-dispatch-profiles.md`](cursor-dispatch-profiles.md)).

Implications:

1. Do not create a `dsh-dispatch-profiles.md` (or similar) sibling document for
   this feature — dispatch guidance lives in **this section only**.
2. The parent owns deterministic fixes, commits, pushes, and required review
   re-runs after a cross-runner headless verdict (Protocol 91).
3. Failover to Claude / Cursor / Codex uses the same protocols and shared skills;
   only the invocation surface changes — see
   [`provider-contingency-runner-failover.md`](../provider-contingency-runner-failover.md).

---

## Related surfaces

| Surface | Role |
| ------- | ---- |
| [`REVIEW.md`](../../../../REVIEW.md) | Canonical review contract |
| Protocol 91 Step 7a | Availability, draft-restriction, dispatch map |
| [`agent-model-config.md`](../agent-model-config.md) | Tier mapping + DSH pinning notes |
| [`provider-contingency-runner-failover.md`](../provider-contingency-runner-failover.md) | Runner-unavailable failover |
| `.ai-dev-workflow.yaml` / `.ai-dev-workflow.local.yaml` | Supported values vs local opt-in |

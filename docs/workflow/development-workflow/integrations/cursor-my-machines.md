# Cursor My Machines / Remote Control for Workflow Hubs

Use this runbook to prepare a machine for bounded framework runs from a workflow
hub. My Machines (also called Remote Control) runs tool calls on your worker;
the agent loop still runs in Cursor's cloud. See Cursor's
[My Machines guide](https://cursor.com/docs/cloud-agent/self-hosted/my-machines).

## Choose an execution target

| Target | Choose it when | Prepare before a hub run |
| --- | --- | --- |
| Hosted Cloud | An isolated VM can reproduce the task's repositories, dependencies, and network access. | Provision the hub and needed products in the VM; configure its environment and Cloud Secrets. Your workstation's paths and credentials are not available there. |
| My Machines / Remote Control | Work needs existing product checkouts, tools, or machine-local access. | Start a worker at the hub and validate the product paths and authentication on that same machine. |
| Cursor desktop | You want interactive local development and can supervise the workspace directly. | Open the hub, validate its product checkouts, and confirm handoff capability for this session. |

Hosted Cloud can support a hub if you provision its required local checkouts;
it cannot reuse paths from a different machine. Its `.cursor/environment.json`
and saved environment are separate from the setup of a My Machines worker.
See [Cloud Agent setup](https://cursor.com/docs/cloud-agent).

Execution target does not determine a dispatch profile or grant review, merge,
checkpoint, or destructive-action authority.

## Prepare the worker and local layout

An operator installs the [Cursor CLI](https://cursor.com/docs/cli/installation)
on the worker machine and signs in there. These commands are for the operator;
a documentation or validation run must not start a live worker automatically.

<!-- workflow-shell-contract: bash-zsh -->
```bash
set -euo pipefail
curl https://cursor.com/install -fsS | bash
agent --version
agent login
```

Use an existing hub clone and product clones. For example, this fabricated
layout keeps products beside the hub:

```text
workspace/
  workflow-hub/
  products/
    sample-app/
```

Declare portable identities in the hub's versioned `.ai-dev-workflow.yaml`:

```yaml
schema_version: 2
mode: workflow_hub
workflow_hub:
  product_repos:
    - name: sample-app
      github_repo: example/sample-app
      default_branch: develop
```

The operator configures the corresponding machine-local mapping in the hub's
ignored `.ai-dev-workflow.local.yaml`:

```yaml
product_repos:
  - name: sample-app
    local_path: ../products/sample-app
```

The name must match the shared product entry. Relative local paths resolve from
the hub root. See [Repository Modes](../repository-modes.md#local-configuration)
for `checkout_root` and path precedence. Do not commit machine paths or private
configuration. Agents must not open, print, or copy private configuration or
credential files; authorized workflow scripts may read the selected local
configuration. Use fabricated configuration in regression fixtures.

## Preflight before starting workflow mutations

Run from the hub checkout, under the same OS user and environment that will run
the worker. Replace the fabricated product identity with the configured target.
Stop on any failed command and correct the named path, checkout, or access
problem before dispatching work.

<!-- workflow-shell-contract: bash-zsh -->
```bash
set -euo pipefail
cd /path/to/workspace/workflow-hub
git rev-parse --show-toplevel
bash scripts/development-workflow/validate-workflow-config.sh --repo sample-app --require-local
bash scripts/development-workflow/hub-status.sh --all
gh repo view example/workflow-hub --json nameWithOwner
gh repo view example/sample-app --json nameWithOwner
git -C ../products/sample-app ls-remote --exit-code origin refs/heads/develop >/dev/null
```

Check the reported root against the intended hub. Validate each product selected
for this run with `--repo <name> --require-local`; a successful check of one
product does not validate another. `hub-status.sh --all` reports checkout and
dirty-state information; it does not accept `--require-local` and does not prove
authenticated remote access. The `gh` probes check repository visibility, while
`git ls-remote` checks the Git transport and expected base ref. Neither proves
write permission; keep the framework's later push-verification gates.

Review dirty state and conflicting active runs before selecting a branch or
worktree. Do not reset, stash, delete, or switch a checkout owned by another run
to make preflight pass. Inspection output can contain local paths and remote
URLs: keep it local and share only sanitized outcomes, never credential-bearing
URLs or private configuration values.

The dedicated hub-worker preflight is tracked in
[#1721](https://github.com/lhpaul/ai-dev-framework-template/issues/1721), a sibling
of this runbook under [#1719](https://github.com/lhpaul/ai-dev-framework-template/issues/1719).
This checklist uses existing helpers and does not claim that worker detection
or an automatic preflight hook has been added to bounded commands.

## Start and select the worker

After preflight succeeds, start the worker from the hub:

<!-- workflow-shell-contract: bash-zsh -->
```bash
set -euo pipefail
cd /path/to/workspace/workflow-hub
agent worker start --name "hub-devbox"
```

Alternatively, register the hub explicitly from another directory:

<!-- workflow-shell-contract: bash-zsh -->
```bash
agent worker start --name "hub-devbox" --worker-dir /path/to/workspace/workflow-hub
```

Keep the worker process running. At
[cursor.com/agents](https://cursor.com/agents), select that machine under
My Machines and target the hub repository. Confirm the account, machine name,
and registered hub remote if routing fails. A worker registered only for a
product repository is not a substitute for the hub worker. Local product path
mapping lets framework helpers reach products; it does not register those
products as independent Cursor routing targets.

## Authentication and secrets

My Machines uses machine-local tools and credentials; Cloud dashboard secrets
are not delivered to this personal worker. Configure Git authentication, `gh`
repository access, and any required tool login as the worker's OS user. An
interactive shell's setup must also be available to the worker process. Hosted
Cloud needs its own environment secrets and access setup. See Cursor's
[self-hosted environment contract](https://cursor.com/docs/cloud-agent/self-hosted#environments-on-self-hosted-machines).

Use `agent login` for the personal worker. Do not paste tokens into commands,
prompts, PRs, screenshots, or diagnostics. Do not dump environment variables,
credential stores, private local YAML, or process argument lists. Stop on missing
access and let an operator provision it through the intended credential manager.
Local execution still sends task context and tool results to Cursor; it is not
a promise that all data stays on the machine. See the
[self-hosted data boundary](https://cursor.com/docs/cloud-agent/self-hosted#what-leaves-your-network).

## Apply the dispatch profile before mutation

Follow the canonical [Cursor Dispatch Profiles](cursor-dispatch-profiles.md)
from [#1462](https://github.com/lhpaul/ai-dev-framework-template/issues/1462).
Declare the accountable orchestration role, posture, and profile before any
mutating action. First confirm initial handoff; only then assess onward handoff.

- `cursor-native-handoff`: both orchestration handoff and onward stage handoff
  are confirmed.
- `cursor-parent-orchestrated`: initial handoff is confirmed, but onward handoff
  is unavailable or unconfirmed. The parent absorbs the complete orchestration
  contract and delegates stage work; it does not implement or review inline.
- `cursor-inline-fallback`: initial handoff cannot be confirmed, or the required
  stage handoff is lost under parent orchestration. Remain read-only and report
  the canonical stop and recovery action.

A reachable stage role refusing an action for missing credentials is an access
stop, not evidence that handoff is unavailable. Worker startup alone never
proves nested `Task` availability. Use the canonical profile's evaluation,
transition, and recovery rules rather than assuming every Remote Control run
has the same capabilities. Stage model pins come from the applicable
`.cursor/agents/<role>.md`; follow
[Agent Model Configuration](../agent-model-config.md).

After the declaration, use `/run-item`, `/run-items`, or `/run-epic` with explicit
scope and autonomy policy. Preserve every workflow gate, including unresolved
human checkpoints. If the worker disconnects, inspect durable branch, PR,
review, CI, and checkpoint state before resuming; do not repeat an uncertain
push or merge. This runbook changes no framework command, dispatch policy, or
credential-provisioning mechanism.

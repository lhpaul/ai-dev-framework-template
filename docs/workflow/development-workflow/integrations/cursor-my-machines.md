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

For each My Machines / Remote Control hub run, the operator identifies the
worker target and selected hub, invokes the preflight in the worker environment,
and gives the bounded runner the resulting file and run details. The runner
must run the verifier successfully before its first workflow write, including
branch, file, tracker, or PR changes. Read-only checkpoints do not require the
preflight. Hosted Cloud, desktop and non-hub runs retain their existing rules.

The following example uses a fabricated path. Run under the worker's OS user;
select the actual hub and the worker directory registered for that same hub.
`WORKER_RUN_START` is recorded before selecting the hub, and
`WORKER_HUB_SELECTED_AT` immediately after selection, using UTC microsecond
precision so events within the same second can be ordered. The result file stays on
the worker; share it only with the intended bounded runner.

<!-- workflow-shell-contract: bash-zsh -->
```bash
set -euo pipefail
WORKER_RUN_START=$(python3 -c 'from datetime import datetime, timezone; print(datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z"))')
WORKER_HUB=/path/to/workspace/workflow-hub
WORKER_DIR="$WORKER_HUB"
WORKER_HUB_SELECTED_AT=$(python3 -c 'from datetime import datetime, timezone; print(datetime.now(timezone.utc).isoformat(timespec="microseconds").replace("+00:00", "Z"))')
WORKER_RUN_ID=$(python3 -c 'import uuid; print(uuid.uuid4())')
WORKER_RESULT_FILE=$(mktemp)
if ! python3 "$WORKER_HUB/scripts/development-workflow/hub-worker-preflight.py" check \
  --hub-dir "$WORKER_HUB" --worker-dir "$WORKER_DIR" \
  --run-id "$WORKER_RUN_ID" > "$WORKER_RESULT_FILE"; then
  cat "$WORKER_RESULT_FILE"
  exit 1
fi
python3 "$WORKER_HUB/scripts/development-workflow/hub-worker-preflight.py" verify \
  --hub-dir "$WORKER_HUB" --run-id "$WORKER_RUN_ID" \
  --run-start "$WORKER_RUN_START" --hub-selected-at "$WORKER_HUB_SELECTED_AT" \
  --result-file "$WORKER_RESULT_FILE"
```

Pass the result file, selected hub, run UUID and both timestamps to the bounded
runner. It repeats the verifier before mutation; missing, failed, stale,
malformed or mismatched evidence stops the run. An explicit `--worker-dir` may
be used when the worker was registered from another directory, but it must
identify the selected hub checkout itself. Use a fresh preflight for each run.
The result records check outcomes, time, run UUID, and opaque hashes of the hub,
configuration and product identities. These hashes can be guessed and are not
credentials or tamper-proof evidence; the runner relies on the operator's
assertion. Keep the output local and do not paste private configuration.

A failing product check reports a one-based `product_ordinal` in the original
shared `workflow_hub.product_repos` list order. The operator can inspect that
entry and its local mapping privately to correct it; the agent must not print
those configurations. GitHub probes check read visibility on `github.com`, not
write permission or Git transport. Existing push verification still applies.
Do not reset, stash, delete, or switch another run's checkout to make it pass.

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

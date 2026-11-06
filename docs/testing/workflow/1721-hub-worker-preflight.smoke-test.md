# Hub Worker Preflight — Smoke Test

Use disposable fabricated hub and product Git checkouts and a fake `gh` executable. Do not use private YAML or real credentials. Follow the final command's `--help` and the operator runbook.

1. Configure two fabricated products, invoke preflight with the hub root, matching worker directory, and a unique run ID. Expect success, all required check outcomes, matching hub identity, run ID, and check time.
2. Repeat with an explicit worker directory pointing elsewhere, a missing local product, an incorrect product origin, and a denied GitHub probe. Each must stop with a safe actionable diagnostic; no partial result may pass.
3. Inspect the output and checkouts: no planted secret, raw credential-bearing URL, private YAML, local or remote mutation appears.
4. For each of `/run-item`, `/run-items`, and `/run-epic`, confirm the instructions require an operator-provided current successful worker result before mutation, reject absent, stale or mismatched evidence, and leave read-only and non-worker paths under existing rules.

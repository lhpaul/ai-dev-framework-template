# Hub Worker Preflight — Implementation Plan

**Spec**: [Hub Worker Preflight](1_1721-hub-worker-preflight_specs.md)  
**Smoke test runbook**: [Worker preflight smoke test](../../../testing/workflow/1721-hub-worker-preflight.smoke-test.md)

## Summary

Implement a read-only, operator-invoked worker preflight that validates the selected hub and all configured products, performs bounded GitHub visibility probes, and emits a result the operator can provide to a bounded run. Update the Cursor command and documentation surfaces to require that current result before worker-hub mutations. Complexity: M, because configuration, Git identity, sanitized subprocess failures, documentation gates, and realistic negative tests interact. Dependencies: merged #1462, #1378, #1720 and this spec; Git and authenticated `gh` on the worker. No database, application API, UI, new credential store, or new service is introduced.

## Verification Log

Evidence collected at `0715f6a1e52db45d6ec160de915565e72f5552cc` on 2026-11-02 UTC; invocation scope is #1721 only.

| Check | Reproduction | Result |
| --- | --- | --- |
| Resolver behavior | `rg -n 'def (cmd_validate\|cmd_list_product_repos\|resolve_context\|github_repo_from_url)' scripts/development-workflow/workflow-config-resolver.py` | Existing resolver lists products and resolves local overrides; `validate --require-local` requires a mapping but does not prove the checkout exists. |
| Existing preflight | `rg -n 'gh label create\|hub_require_workflow_hub_mode' scripts/development-workflow/hub-preflight-product-repos.sh` | Existing similarly named preflight can create labels; do not invoke it from the read-only worker preflight. |
| Entrypoints | `rg -n 'cursor-dispatch-profiles' .cursor/commands/run-{item,items,epic}.md` | Each of the three issue-named Cursor command files references the profile contract. The spec names these three, not a repository-wide command sweep. |
| Sync ownership | `rg -n 'path: (docs/workflow/\|.cursor/commands/\|scripts/development-workflow/)' sync-manifest.yaml` | The containing template-owned directories are listed. Run coverage validation for new files. |
| Same-surface PRs | `gh search prs '"hub worker"' --repo lhpaul/ai-dev-framework-template --state open`; repeat with `"hub preflight"` | No matching open PRs observed at planning. Keyword search is a bounded signal, not proof that no unrelated PR exists. |

## Cross-Cutting Operational Assumption Check

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Artifact owner and base | Template repository, `develop`; #1721 only | User scope, merged spec, PR #2096 | 2026-11-02 UTC, `0715f6a1` | #1721; no matching same-surface open PR in the verification log | Verified |
| Config and access contract | Hub product identities are portable shared config, paths are machine-local; GitHub read access only | `repository-modes.md`, `workflow-config-resolver.py`, merged spec | 2026-11-02 UTC, `0715f6a1` | #1721 and the two documented search queries above | Verified |

Implementation must re-read these sources and same-surface evidence before editing and record `Still valid` or stop for conflict.

## Implementation

1. Add `scripts/development-workflow/hub-worker-preflight.py` with `--hub-dir`, `--worker-dir`, and `--run-id` required. The first two identify the operator-selected hub and worker directory; the run ID binds the result to the bounded invocation. Reject missing/empty/invalid values without echoing arbitrary supplied text. The operator runs this on the worker as the same OS user/environment as the bounded run.
2. Resolve both directory paths physically and require both to identify the same Git worktree root: `git -C <dir> rev-parse --show-toplevel` must succeed and resolve to each supplied directory, and the roots must match. Do not accept a parent, subdirectory, bare repository, or unrelated nested checkout as the hub. Require the hub's workflow mode to be `workflow_hub` using the existing resolver. Worktrees with `.git` files are valid.
3. Use the existing resolver's `list-product-repos --json` and, for every name, `validate --repo <name> --require-local --json`. Reject an empty list, malformed output, unresolved mapping, missing/non-directory checkout, or checkout whose physical Git top-level is not the resolved product path. Do not use `hub-status.sh` as a checkout validity oracle: it checks for `.git` directories and may print remote URLs. Read resolver output internally, never print the local YAML or raw resolver output.
4. Determine the hub GitHub repository from its `origin` via `git remote get-url origin` and the existing resolver's GitHub URL normalization; require a valid, non-credential-bearing GitHub identity. Use each product's resolver-provided `TARGET_GITHUB_REPO` or normalized `git_url`, reject missing or unsupported identity, and verify each checkout's origin resolves to the configured identity. Avoid displaying remote URLs or raw stderr. Probe `gh auth status` and `gh repo view <owner/repo> --json nameWithOwner` for the hub and every product. Use argument arrays, never a shell, disable interactive prompts, bound each subprocess with a finite timeout, and fail on timeout, errors, malformed data, mismatched identity, unavailable authentication, or inaccessible repo. A successful read probe is not a write-permission or Git transport guarantee. Do not invoke the label-creating product preflight, `git fetch`, or credential setup.
5. Emit a stable, machine-readable JSON result with overall pass/fail, selected hub identity, run ID, UTC check time, and outcome for worker directory, each local product checkout, and each GitHub repository probe. Failure includes a safe check identifier, affected configured name or safe repository identity when known, and actionable remediation; no raw paths from local configuration, remote URLs, command stderr, tokens, or private YAML in diagnostics. Only emit success after every required check passes. Keep optional dirty/sync warnings out of this implementation. The command never changes local or remote workflow state.
6. Update `.cursor/commands/run-item.md`, `.cursor/commands/run-items.md`, and `.cursor/commands/run-epic.md`: for an operator-identified My Machines / Remote Control hub run, request the operator-run command and its successful result for the current run, check run ID, selected hub, timestamp/order, and every required check outcome before the first local or remote workflow write, and stop with correction if missing, malformed, stale, mismatched, or failed. The run ID and timestamp are operator-supplied evidence, not cryptographic proof. Read-only checkpoints retain existing rules. Other targets and non-hub runs keep existing behavior. Keep the existing dispatch profile declaration independent; no target autodetection.
7. Update `docs/workflow/development-workflow/integrations/cursor-my-machines.md` and `cursor-dispatch-profiles.md` with the same operator-invoked gate, an example for `--worker-dir`, result contents, local-output confidentiality, and the limits of read-only access. Remove the obsolete #1721-pending text. Add a changelog fragment and cover any newly added template-owned files through `sync-manifest.yaml` as required by the coverage checker.

## Decision and Evidence Contract

For the three named Cursor bounded entrypoints, a worker run proceeds to its existing mutation gates only when the operator asserts a matching current-run, current-hub successful result with all required outcomes. Missing input, unavailable or incomplete result, mismatch, stale evidence, any failed or inconclusive probe, and unknown input stop before mutation. The preflight itself checks a single operator-selected hub and all configured products per invocation; no prior invocation's result is reusable. An explicit warning-only result is not required in this implementation. The entrypoints cannot authenticate a pasted result; they must not claim automatic enforcement beyond the operator assertion. Read-only work and non-worker contexts do not call the preflight. Existing dispatch, reviewer, CI, and checkpoint gates remain separate.

## Testing Strategy

Use a new focused regression suite `scripts/development-workflow/tests/test-hub-worker-preflight.sh` with fabricated shared/local YAML, disposable Git repositories and a fake `gh` executable; no real credentials or product repositories. Cover success for multiple products, a linked worktree and explicit worker directory; wrong/nested/missing hub, absent or malformed local mapping, non-Git and wrong-identity product, empty product list, invalid or credential-bearing remote, missing `gh`, auth/repo denial, malformed output, timeout, and no false success after partial work. Assert secrets and raw private values never reach stdout/stderr, no Git or remote mutation is invoked, and existing local/remote contents remain unchanged. Exercise JSON result fields and entrypoint instructions against absent, stale, mismatched, failed, and current result cases. Scenarios are indicative coverage classes, not a binding fixture enumeration.

Run focused tests, relevant existing hub resolver tests, shell/Python lint as applicable, documentation lint, template-sync coverage validation, and `git diff --check`. Add the new suite to the workflow test discovery/registry if needed, verified against the actual runner. Use the smoke runbook for operator-visible outcomes; never start a live worker or access real product configuration in tests. No seed data beyond disposable fabricated fixtures.

### Parser-risk edge cases and unit mapping

The preflight consumes structured JSON returned by the existing resolver and `gh`, so parser-risk applies. The focused test suite maps each of these to an automated case: empty, truncated, non-object, missing-key, wrong-type, and extra-field JSON; names containing spaces or control characters; empty, malformed and credential-bearing GitHub identities; multiple product entries including a later failing entry; and duplicate or nested configuration rejected by the existing resolver. The implementation delegates YAML parsing and URL normalization to existing resolver code rather than inventing a new grammar. Inline suppressions are not supported.

The selector discovers top-level `test-*.sh` suites in `scripts/development-workflow/select-test-suites.sh`; add explicit `# covers:` mappings for the new production script and affected command surfaces and verify selector output rather than relying on a default association.

## Risks and Mitigations

- Sensitive diagnostics: suppress untrusted subprocess output; test credential-bearing URLs and private values as planted sentinel strings.
- Wrong checkout or inaccessible host: compare actual Git roots and origin identities, fail closed on every unresolved probe, and keep timeout bounded.
- Operator assertion can be false: explicitly state the trust boundary; do not describe output as tamper-proof or as automatic environment detection.
- Config drift: repeat the preflight per bounded run; record result time and scope.
- Regression to non-worker execution: test the three command surfaces and document unchanged paths for other targets.

## Rule 6 Scoped Obligations

The local path and remote identity checks govern every configured product entry and the hub, discharged in the preflight before success. The evidence check governs all three named Cursor entrypoints for operator-identified worker hub runs, discharged before their first workflow write. The read-only exemption governs all checkpoints that perform no workflow writes; existing profile rules still apply there.

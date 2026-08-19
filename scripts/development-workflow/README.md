# Development workflow scripts

Scripts used by the staged AI development workflow. Referenced by `docs/workflow/development-workflow/` and by the Codex skills in `.agents/skills/` and `.codex/skills/`. Run from the repository root.

## `install-codex-skills.sh`

Installs the repository's bundled Codex skills into the local Codex skill directories by creating symlinks.

What it does:

- Reads repo-discoverable skills and command aliases from `.agents/skills/`
- Keeps legacy canonical skill compatibility from `.codex/skills/`
- Installs into `AGENTS_HOME/skills` if `AGENTS_HOME` is set, otherwise `~/.agents/skills`
- Also installs into `CODEX_HOME/skills` if `CODEX_HOME` is set, otherwise `~/.codex/skills`, for older local setups
- Skips an existing destination if it is not a symlink

Use this when:

- You want to make the template's bundled Codex skills and command-style aliases available in your local Codex environment
- You are testing the workflow skills in a downstream repository created from this template

### `actions-cost-audit.sh`

Summarizes recent GitHub Actions workflow run volume and wall time by workflow
using normal `gh run list` visibility.

Usage:

```bash
./scripts/development-workflow/actions-cost-audit.sh --limit 100
./scripts/development-workflow/actions-cost-audit.sh --repo owner/repo --since 2026-07-01T00:00:00Z
```

What it does:

- Groups recent workflow runs by workflow name
- Reports run count, completed count, incomplete duration count, total wall time,
  average wall time, trigger events, and recent run links
- Prints public/private repository cost-risk framing
- Emits a recommendation worksheet for retrospectives and template-sync reviews

Use this when:

- You want to identify high-volume or high-wall-time workflow defaults without
  billing-admin access
- You are reviewing whether a workflow should be kept, narrowed, made opt-in,
  replaced, disabled, or investigated
- A downstream private repository may inherit template workflows that are
  zero-billable in the public template but expensive after sync

### `add-backlog-item.sh`

Resolves the configured issue tracker destination for backlog creation and can create a GitHub issue when `issue_tracker.provider` maps to GitHub Issues / GitHub Projects.

Usage:

```bash
./scripts/development-workflow/add-backlog-item.sh resolve
./scripts/development-workflow/add-backlog-item.sh create --title "Title" --body "Body"
./scripts/development-workflow/add-backlog-item.sh create --title "Title" --body-file path/to/body.md
```

What it does:

- `resolve` prints `ISSUE_TRACKER_PROVIDER`, `DESTINATION_KIND` (`github`, `linear`, `other`, `none`), and a `CREATE_VIA` hint for agents.
- `create` runs `gh issue create` when the destination kind is `github` (requires authenticated `gh`).
- For Linear or unsupported providers, exits non-zero with guidance so agents follow `docs/workflow/development-workflow/protocols/00-add-backlog-item-protocol.md` instead of guessing.

Use this when:

- An agent needs a deterministic destination check before creating a backlog item.
- You want to create a GitHub issue from a shell environment without manual `gh` typing.

### `discover-workflow-state.sh`

Prints a compact snapshot of the repository's workflow-related state.

What it does:

- Shows `git status --short --branch`
- Lists workflow branches (`spec/`, `implementation-plan/`, `feature/`, `refactor/`, `fix/`, `hotfix/`, `release/`)
- Lists active git worktrees
- Lists directories under `docs/specs/developments/` if they exist
- Lists open pull requests, labels, and check summaries when `gh` is available

Use this when:

- You want a quick view of what work is already in progress
- The orchestrator needs a deterministic summary before choosing the next stage

### `component-release-target.sh`

Resolves the canonical release target before a single-repo or workflow-hub
component release mutates changelog entries, branches, tags, release evidence,
or tracker state.

Usage:

<!-- workflow-shell-contract: bash-zsh -->
```bash
./scripts/development-workflow/component-release-target.sh --json
./scripts/development-workflow/component-release-target.sh --repo mobile-app --json
```

What it does:

- Emits `component_release_target.v1` in shell or JSON form.
- Reports one routing outcome, `mutation_allowed`, artifact owners,
  `release_correlation_key`, and `contract_revision`.
- Fails closed for missing, multiple, unknown, ambiguous, invalid, unavailable,
  or unsupported component release targets before mutation.
- Uses the canonical component release contract documented in
  `docs/workflow/development-workflow/repository-modes.md`.

### `component-release-evidence.sh`

Renders deterministic component release evidence from an independent target
binding and rejects mismatched repository identity, artifact owners,
`release_correlation_key`, or `contract_revision`.

Usage:

<!-- workflow-shell-contract: bash-zsh -->
```bash
./scripts/development-workflow/component-release-evidence.sh \
  --target-file /tmp/component-release-target.json \
  --binding-file /tmp/component-release-target.json \
  --release-branch mobile-app/release/v1.2.3 \
  --release-outcome pending \
  --ci-outcome pending \
  --deployment-outcome pending \
  --cleanup-outcome not_started \
  --hub-tracker-ref "#123" \
  --output /tmp/component-release-evidence.json
```

### `multi-repo-release-assurance.sh`

Validates deterministic workflow-hub adoption fixtures before a
multi-repository release is treated as adopted.

Usage:

<!-- workflow-shell-contract: bash-zsh -->
```bash
./scripts/development-workflow/tests/setup-multi-repo-release-assurance-fixture.sh \
  --output-dir /tmp/multi-repo-release-assurance \
  --json > /tmp/multi-repo-release-assurance-fixtures.json &&

./scripts/development-workflow/multi-repo-release-assurance.sh \
  --fixture-dir /tmp/multi-repo-release-assurance/valid \
  --json
```

What it does:

- Emits `multi_repo_release_assurance.v1`.
- Reads explicit fixture directories containing scenario inputs and historical
  before/after baselines.
- Writes JSON to stdout; redirect it to the release runbook or self-review
  evidence path chosen by the operator.
- Aggregates scenario outcomes into `adoption_status` using the canonical
  contract in
  `docs/workflow/development-workflow/multi-repo-release-adoption.md`.
- Compares hub-owned and product-owned historical no-rewrite baselines.
- Emits `owner_actions[]` and `required_next_action` for release runbook
  evidence.

Run focused coverage with:

<!-- workflow-shell-contract: bash -->
```bash
bash scripts/development-workflow/tests/test-multi-repo-release-assurance.sh
```

### `delivery-bundle-manifest.sh`

Creates and updates hub-owned delivery bundle manifests that compose
independently released product components into one customer-facing delivery.

Usage:

<!-- workflow-shell-contract: bash-zsh -->
```bash
./scripts/development-workflow/delivery-bundle-manifest.sh create \
  --manifest /tmp/delivery-bundle.json \
  --bundle-key mobile-web-july-delivery \
  --title "Mobile and Web July delivery" \
  --purpose "Coordinated customer-facing delivery" \
  --parent-ref "#1352" \
  --component mobile-app \
  --component web-app \
  --child-item "#1356" \
  --finalization-owner "@workflow-operator" \
  --json

./scripts/development-workflow/delivery-bundle-manifest.sh update-component \
  --manifest /tmp/delivery-bundle.json \
  --bundle-key mobile-web-july-delivery \
  --expected-revision 1 \
  --component-key mobile-app \
  --evidence-file /tmp/component-release-evidence.json \
  --component-tag mobile-v1.4.0 \
  --component-version 1.4.0 \
  --source-pr 1411 \
  --release-pr 1501 \
  --hub-tracker-reconciliation-outcome complete \
  --child-item "#1356" \
  --child-release-state merged \
  --json

./scripts/development-workflow/delivery-bundle-manifest.sh add-component \
  --manifest /tmp/delivery-bundle.json \
  --bundle-key mobile-web-july-delivery \
  --expected-revision 2 \
  --component-key web-app \
  --json

./scripts/development-workflow/delivery-bundle-manifest.sh remove-component \
  --manifest /tmp/delivery-bundle.json \
  --bundle-key mobile-web-july-delivery \
  --expected-revision 3 \
  --component-key web-app \
  --reason "Moved to a later delivery" \
  --json

./scripts/development-workflow/delivery-bundle-manifest.sh inspect \
  --manifest /tmp/delivery-bundle.json \
  --bundle-key mobile-web-july-delivery \
  --json

./scripts/development-workflow/delivery-bundle-manifest.sh finalize \
  --manifest /tmp/delivery-bundle.json \
  --bundle-key mobile-web-july-delivery \
  --expected-revision 4 \
  --json
```

| Subcommand | Required flags beyond `--manifest` and `--bundle-key` |
| --- | --- |
| `create` | `--title`, `--purpose`, `--parent-ref`, `--component`, `--finalization-owner` |
| `add-component` | `--expected-revision`, `--component-key` |
| `update-component` | `--expected-revision`, `--component-key`, `--evidence-file`, `--component-tag`, `--source-pr`, `--release-pr`, `--child-item`, `--child-release-state` |
| `remove-component` | `--expected-revision`, `--component-key`, `--reason` |
| `inspect` | none |
| `finalize` | `--expected-revision` |

What it does:

- Emits and validates `delivery_bundle_manifest.v1`.
- Requires both `--manifest` and immutable `--bundle-key` so a temporary file
  path is never the only delivery identity.
- Preserves component release evidence and records stable identity fields,
  component tags, PR references, release outcomes, cleanup outcomes, hub
  tracker reconciliation, child release state, readiness, and audit events in
  the hub manifest.
- Uses a manifest lock, expected-revision checks, staged JSON validation, and
  atomic replacement for accepted mutations.
- Records lock owner metadata in `<manifest>.lock/owner.json`; if a process is
  killed mid-mutation, inspect that file and remove the lock directory only
  after confirming the owner process is no longer active.
- Fails closed with stable `ERROR_CODE=<code>` stderr for stale revisions,
  conflicting evidence, malformed JSON, missing component tags, incomplete
  evidence, and blocked finalization outcomes.
- Finalizes only when every declared current component is complete and never
  creates a shared suite version or shared release branch.

### `component-milestone-reconciliation.sh`

Reconciles hub-owned component release status after component evidence and,
when present, delivery bundle evidence are available.

Usage:

<!-- workflow-shell-contract: bash-zsh -->
```bash
./scripts/development-workflow/component-milestone-reconciliation.sh inspect-component \
  --issue 1358 \
  --target-kind component_child \
  --product-repo mobile-app \
  --component-tag mobile-v1.4.0 \
  --evidence-file /tmp/component-release-evidence.json \
  --json

./scripts/development-workflow/component-milestone-reconciliation.sh apply-component \
  --issue 1358 \
  --target-kind component_child \
  --product-repo mobile-app \
  --component-tag mobile-v1.4.0 \
  --evidence-file /tmp/component-release-evidence.json \
  --json

./scripts/development-workflow/component-milestone-reconciliation.sh inspect-parent \
  --parent-issue 1352 \
  --delivery-manifest /tmp/delivery-bundle.json \
  --require-finalized \
  --json

./scripts/development-workflow/component-milestone-reconciliation.sh apply-parent \
  --parent-issue 1352 \
  --delivery-manifest /tmp/delivery-bundle.json \
  --require-finalized \
  --json
```

What it does:

- Emits `component_milestone_reconciliation.v1`.
- In `workflow_hub` mode, creates or reuses a namespaced component milestone
  titled `<product-repo>@<component-tag>` and assigns it only to the matching
  component child issue after complete matching `component_release_evidence.v1`.
- Rejects `parent_epic` and `delivery_bundle` milestone writes before any
  GitHub mutation.
- Reports parent release states from `delivery_bundle_manifest.v1` as
  `not_released`, `partially_released`, `blocked`, or `released`.
- Persists parent `release_status` and an audit event in the delivery bundle
  manifest only when finalized bundle evidence allows `parent_released`.
- Preserves non-hub compatibility with the existing plain `vX.Y.Z` milestone
  path via `--mode single_repo --version <version>`.

### `check-workflow-branch.sh`

Checks whether a specific workflow branch already exists locally, remotely, or in an active worktree.

Usage:

```bash
./scripts/development-workflow/check-workflow-branch.sh <branch-name>
```

What it does:

- Reports matching local branches
- Reports matching remote branches
- Reports matching worktrees
- Exits with status `0` if the branch exists anywhere
- Exits with status `1` if the branch is missing

Use this when:

- The orchestrator needs to verify whether a workflow item has already been started
- You want to avoid re-dispatching work for an item that already has a branch or worktree

### validate-workflow-branch-name.sh

Validates a tracked workflow branch name before branch creation or push.

It accepts supported workflow prefixes with bare numeric tracker identifiers and
rejects #, ?, ^, ~, :, backslash, and spaces with a compliant replacement
example. It does not replace Git ref-format validation; it enforces the
repository workflow convention before guarded creation and PR paths continue.

### `run-nested-artifact-guard.sh`

Prevents nested or spawned agents from silently creating duplicate issue-scoped
workflow artifacts or opening PRs against an unapproved base.

Usage:

```bash
./scripts/development-workflow/run-nested-artifact-guard.sh \
  --mode pre-create \
  --issue 1200 \
  --expected-branch feature/1200-example \
  --approved-base develop \
  --repo-root "$(pwd)"
```

What it does:

- Scans registered worktrees, local branches, remote branches, and open PRs.
- Treats the expected branch or expected worktree as canonical.
- Compares non-PR artifacts against the expected workflow stage so merged
  prior-stage `spec/*`, `implementation-plan/*`, or `hotfix/*` branches do not
  block the next legitimate stage.
- Reports duplicate issue-scoped artifacts as `RESULT=blocked_duplicate`.
- Reports wrong-base open PRs as `RESULT=wrong_base`.
- Reports parent audit forks as `RESULT=unexpected_fork`.
- Reports missing parent-approved base context as `RESULT=missing_base` in all
  modes, including `audit`.
- Reports scan failures as `RESULT=scan_failed` instead of assuming clean.
- Uses `--repo-root` to choose which repository owns the artifacts being
  scanned; in `workflow_hub` mode, product implementation artifacts must scan
  the selected product checkout rather than the hub checkout.

Use this when:

- A parent runner is about to dispatch a child agent that may create a branch.
- A stage agent is about to open or ready a workflow PR.
- A parent runner is auditing in-scope forks before dispatch or after a child
  returns control.
- A deliberate split needs explicit `--allow-split true` approval with the
  approved base recorded in the parent summary.

### `item-completion-self-check.sh`

Builds the mandatory ground-truth verification section for Work Item Runner and
batch terminal reports.

Usage:

```bash
./scripts/development-workflow/item-completion-self-check.sh \
  --issue 1202 \
  --branch feature/1202-example \
  --stage implementation \
  --worktree-path "$(pwd)" \
  --pr 123 \
  --expected-base develop \
  --expected-label ready-for-human-review \
  --expected-label ready-for-regression \
  --forbid-label needs-fixes \
  --require-review-summary true \
  --require-review-threads true
```

What it does:

- Prints a Markdown section headed `## Ground-Truth Completion Verification`.
- Verifies current branch, HEAD, worktree path, workspace cleanliness, and
  `git worktree list` evidence.
- When `--pr` is supplied, verifies live PR head/base, draft state, labels,
  changed files, CI rollup, reviewer-loop summary, and optionally review
  threads.
- Reads tracker status via `workflow-lib.sh` when tracker evidence is required
  or expected.
- Records external runtime/browser/database claims through explicit
  `--claim <name|required|evidence>` records.
- Exits non-zero for any `discrepancy` or `unavailable_required` result.

Use this when:

- A Work Item Runner is about to report an item as ready, done, blocked,
  escalated, waiting on a human, waiting on merge, or cleanup complete.
- A Portfolio Orchestrator needs item-level evidence before accepting a batch
  item as terminal.

### `pr-ci-loop.sh`

Polls GitHub status checks for a PR until they are green, failing, or timed out.

Usage:

```bash
./scripts/development-workflow/pr-ci-loop.sh <pr-number> [--poll-interval 60] [--max-wait 1800]
```

What it does:

- Reads the PR's `statusCheckRollup` via `gh`
- Reports a stable `RESULT=green|red|timeout`
- Emits parseable `key=value` lines for failing and pending checks

Use this when:

- A stage has opened a PR and needs to wait for CI before signaling readiness
- The orchestrator is resuming a partially completed PR

### `pr-review-loop.sh`

Runs one or more automated PR review platforms in order, then classifies findings into blocking vs suggestion.

Usage:

<!-- workflow-shell-contract: bash -->
```bash
bash ./scripts/development-workflow/pr-review-loop.sh <pr-number> [--branch feature/my-branch] [--platform greptile] [--platform devin] [--platform coderabbit] [--platform coderabbit-cli]
```

What it does:

- Evaluates configured draft and ready GitHub review platforms sequentially
- Runs the platform adapter for each supported platform
- Stops on the first platform that reports blocking findings or escalation
- Reports a stable aggregate `RESULT=clean|needs_fixes|escalate|skipped`
- Emits ordered per-platform `PLATFORM_<n>_*` records plus the matching compatibility fixer
- Supports `coderabbit` for the CodeRabbit GitHub App and `coderabbit-cli` for
  the local CodeRabbit CLI; unavailable CLI/auth/rate-limit states are reported
  as skipped or escalated evidence, not as a fresh clean review
- If no GitHub reviewers are configured, reports `RESULT=skipped`

Use this when:

- A stage has pushed to a PR branch and must resolve automated review before requesting human review
- The orchestrator is resuming a PR after a prior push or interruption
- More than one automated reviewer is configured for a repository

### `run-advisory-checks.sh`

Optional project extension point invoked by `pr-review-loop.sh` after platform
review aggregation and before the final reviewer-loop summary is posted.

Usage:

<!-- workflow-shell-contract: bash-zsh -->
```bash
./scripts/development-workflow/run-advisory-checks.sh <pr-number>
```

What it does by default:

- Exits successfully and emits no stdout.
- Defines the stable customization point for downstream projects that want to
  append diff-scoped informational checks to the reviewer-loop summary.
- Receives exactly one positional argument: the pull request number currently
  being reviewed.

Customization contract:

- Write a complete Markdown-ready advisory section to stdout when there is
  useful informational output, including the section heading. Example:

  <!-- workflow-shell-contract: bash-zsh -->
  ```bash
  printf '\n\n**Advisory checks** _(informational - never blocks merge)_\n'
  printf -- '- Dead exports: none found\n'
  ```

- Keep diagnostics on stderr. `pr-review-loop.sh` suppresses extension stderr in
  the summary.
- The extension is advisory-only. Its output, failure, or absence never changes
  `RESULT`, blocker counts, readiness labels, or the reviewer-loop exit status.
- Missing PR context, a missing script, or empty stdout produces no summary
  section.

### `workflow-next-action.sh`

Classifies the next deterministic workflow action for a branch, PR, or development folder.

Usage:

```bash
./scripts/development-workflow/workflow-next-action.sh --branch feature/my-branch
./scripts/development-workflow/workflow-next-action.sh --pr 42
./scripts/development-workflow/workflow-next-action.sh --development docs/specs/developments/20260307120000_my-feature
```

What it does:

- Detects whether a branch still needs reviewer-gate work or PR readiness work
- Detects whether a PR is waiting on fixes or on human review
- For `--development`: derives workflow status from repo state (presence of implementation plan file, feature branch) so the **issue tracker remains the source of truth**; no `**Status**` line in the spec is required. Outputs `LINEAR_ISSUE` when the spec has `**Linear Issue**: <id>` (note the space after the colon) for orchestrator use. Runs `git fetch --prune origin` unless `WORKFLOW_SKIP_FETCH` is set (e.g. run one fetch before looping over many development folders); if fetch fails, a warning is printed to stderr and refs may be stale. Without an issue tracker, items that were merged and had their branch deleted can appear as Plan Ready; prefer filtering by tracker status when available. The `--development` branch-detection logic has no automated tests; edge cases (slugs with regex metacharacters, Linear-prefixed branch names) should be validated manually when changing that path.

Use this when:

- The orchestrator needs to resume work after an interrupted run
- A stage-specific agent needs to determine whether work is still in-progress or already waiting on a human

For resume behavior, run `workflow-next-action.sh` with `--branch`, `--pr`, or `--development`; it reports the next deterministic action for a partially completed run.

### `workflow-batch-plan.sh`

Classifies development folders into batch-planning candidates for the batch orchestrator.

Usage:

```bash
./scripts/development-workflow/workflow-batch-plan.sh
./scripts/development-workflow/workflow-batch-plan.sh docs/specs/developments/20260307120000_my-feature
```

What it does:

- Scans one or more development folders
- Uses `workflow-next-action.sh --development` to derive the next deterministic action
- Emits stable `key=value` records including `BATCH_HINT` and `PARALLEL_SAFE`

Use this when:

- The batch orchestrator needs a deterministic first-pass list of development-folder candidates
- You want to separate portfolio-level batch planning from single-item orchestration

### `workflow-batch-overlap.sh`

Classifies concrete, suspected, and non-actionable implementation overlap for
multi-item batch proposals from a provider-neutral item snapshot.

Usage:

<!-- workflow-shell-contract: bash-zsh -->
```bash
./scripts/development-workflow/workflow-batch-overlap.sh --input batch-items.json --json
```

Input items include `id`, current tracker `title` and `brief`, plan-derived
`fileSet`, `priority`, `createdAt`, and `nextAction`. Optional JSONL decision
records can authorize `allow_parallel` only for a suspected pair when the batch
fingerprint, pair ID, and evidence hash match the current proposal.

What it does:

- Preserves exact plan file-set intersections as concrete overlap
- Extracts explicit file, route, function, and module/helper/script targets from
  planless item briefs
- Serializes concrete overlaps and unconfirmed suspected overlaps by default
- Emits stable pair IDs, evidence hashes, accepted/stale decisions, and
  transitive serial groups

Use this when:

- Protocol 90 needs to evaluate implementation overlap before assigning
  multiple planless or mixed-evidence items to parallel lanes

### `workflow-batch-lanes.sh`

Assigns stage lanes and `proposed` vs `held` dispatch status for portfolio batch
proposals. Consumes `workflow-batch-plan.sh` output (or `--scan`) and can apply
serial groups from `workflow-batch-overlap.sh`.

Usage:

<!-- workflow-shell-contract: bash-zsh -->
```bash
./scripts/development-workflow/workflow-batch-plan.sh | ./scripts/development-workflow/workflow-batch-lanes.sh
./scripts/development-workflow/workflow-batch-lanes.sh --scan
./scripts/development-workflow/workflow-batch-lanes.sh --overlap-input batch-items.json < batch-plan-output.txt
```

What it does:

- Applies `max_concurrent_by_stage` caps (default: unlimited spec/plan/review, implementation `1`)
- Emits `STAGE_LANE`, `DISPATCH`, `HOLD_REASON`, and `HELD_SUMMARY` per item
- Honors `LOCAL_RUNTIME=exclusive` holds when multiple implementation items would contend
- Holds lower-priority members of classifier serial groups until the prior item
  merges into the approved base

Use this when:

- Protocol 90 Step 3 needs deterministic lane assignments before dispatch

### Workflow hub product repository commands

These commands run only when `.ai-dev-workflow.yaml` resolves to
`mode: workflow_hub`. They use the shared repository-context resolver, support
`--repo <name>` for one configured product repository and `--all` for every
configured product repository, and fail before checkout inspection when the
current repository is not a workflow hub.

#### `hub-status.sh`

Inspects local product repository checkouts without modifying them.

Usage:

```bash
./scripts/development-workflow/hub-status.sh --repo mobile-app
./scripts/development-workflow/hub-status.sh --all
```

What it reports:

- Product repository name and local checkout path
- Current branch when the checkout exists
- `clean`, `dirty`, `missing_path`, `missing_checkout`, or `failed` status
- Origin remote visibility
- A final categorized summary across all selected repositories

Use this before routing implementation work from a workflow hub to confirm that
the selected checkout exists and that dirty state is visible.

### Workflow hub smoke fixture

Run the non-secret workflow-hub smoke fixture with:

```bash
bash scripts/development-workflow/tests/test-workflow-hub-smoke-fixtures.sh
```

The harness copies the committed seed under
`scripts/development-workflow/tests/fixtures/workflow-hub-smoke/` into a
temporary hub checkout, creates two dummy product repositories, and validates
configuration parsing, local checkout resolution, product status/sync commands,
product PR dry-run routing, mode-scope classification, and single-repository
regression behavior. It never needs private product repositories or live GitHub
App credentials by default.

Optional live GitHub App validation is separate and must be requested with
`--live-github-app` plus operator-supplied safe-test repository environment
variables. Do not wire the live path into default CI.

### `select-sync-manifest-entries.py`

Selects `sync-manifest.yaml` entries for a repository role before sync-template
compares or applies files.

Usage:

```bash
python3 scripts/development-workflow/select-sync-manifest-entries.py \
  --manifest sync-manifest.yaml \
  --role workflow_hub
```

What it does:

- Validates declared `mode_scope` values.
- Selects all entries for `single_repo` compatibility.
- Selects `shared` plus `hub_only` for `workflow_hub`.
- Selects `shared` plus `product_repo_injection` for `product_repo`.
- Prints selected and skipped entries with stable `KEY=value` output for tests
  and sync-template summaries.
- Fails closed on unknown roles, missing entry scopes, and unknown scope values
  before any file mutation path can proceed.

Run focused coverage with:

```bash
bash scripts/development-workflow/tests/test-sync-template-mode-scopes.sh
```

#### `hub-sync-product-repos.sh`

Safely prepares clean product repository checkouts.

Usage:

```bash
./scripts/development-workflow/hub-sync-product-repos.sh --repo mobile-app
./scripts/development-workflow/hub-sync-product-repos.sh --all
./scripts/development-workflow/hub-sync-product-repos.sh --repo mobile-app --bootstrap-local-path --yes
```

What it does:

- Refuses dirty checkouts before fetch or fast-forward work
- Fetches the configured default branch and fast-forwards only when local state
  is not ahead of origin
- Blocks ahead-only or diverged checkouts instead of rebasing, stashing,
  resetting, force-updating, or pushing
- Reports partial success and blocked or failed repositories in the final
  summary
- Writes a missing local path to `.ai-dev-workflow.local.yaml` only when
  `--bootstrap-local-path` is set and the operator confirms the prompt, or when
  `--yes` is also supplied

#### `hub-preflight-product-repos.sh`

Bootstrap workflow readiness labels and validate CI policy on product GitHub
repositories before delegated orchestration.

Usage:

```bash
./scripts/development-workflow/hub-preflight-product-repos.sh --repo mobile-app
./scripts/development-workflow/hub-preflight-product-repos.sh --all
./scripts/development-workflow/hub-preflight-product-repos.sh --all --labels-only
```

What it does:

- Creates missing operational labels (`ready-for-human-review`, `needs-fixes`,
  `ready-for-regression`, `human-checkpoint-required`) on each configured product
  GitHub repository
- Probes GitHub Actions workflow count when `ci_policy` is `required` (default)
- Passes when `ci_policy: none` is declared for repositories without CI workflows
- Requires `gh` authentication for remote inspection

#### `scope-residual-gate.sh`

Classifies broad-scope sweep, batch, helper-extraction, and
pattern-completeness items and validates structured residual evidence before
workflow readiness.

Usage:

```bash
./scripts/development-workflow/scope-residual-gate.sh classify \
  --issue-title "Clean 127 console.log occurrences across apps/admin"

./scripts/development-workflow/scope-residual-gate.sh verify \
  --issue-title "Clean 127 console.log occurrences across apps/admin" \
  --evidence /tmp/residual-evidence.json
```

The helper is read-only. `classify` emits `RESULT=requires_verification` for
applicable scopes and `RESULT=not_applicable` otherwise. `verify` emits
`RESULT=pass|block|escalate|not_applicable`. Both modes emit
`SCOPE_CLASSIFICATION`, `RESIDUAL_GROUPS`, `FOLLOW_UPS`, and `SUMMARY` fields,
and never update labels, trackers, comments, PRs, branches, or issues.

#### `hub-list-prs.sh`

Lists open pull requests for selected product repositories without modifying
remote state.

Usage:

```bash
./scripts/development-workflow/hub-list-prs.sh --repo mobile-app
./scripts/development-workflow/hub-list-prs.sh --all
```

The command resolves `github_repo` directly, or derives `owner/repo` from
GitHub-form `git_url` values such as `git@github.com:owner/repo.git` and
`https://github.com/owner/repo.git`. If no GitHub repository slug can be
resolved, it fails for that product repository instead of falling back to the
workflow hub repository.

### `post-merge-cleanup.sh`

After a development PR is merged and the remote branch deleted, sync with
origin, switch to the merged PR's base branch, pull, and delete the local
branch.

Usage:

```bash
./scripts/development-workflow/post-merge-cleanup.sh [--base develop-workflow-hub-mode] [BRANCH]
```

- No argument: use the current branch (run while still on the merged branch).
- With `BRANCH`: branch name to delete (e.g. `feature/my-feature`).
- With `--base`: explicitly choose the cleanup base branch. When omitted for
  hub-owned branches, the script queries the merged PR base and fails closed if
  that lookup is unavailable.

Use this when:

- You have merged a feature/plan/spec PR and deleted the remote branch, and want
  to clean up the local branch and update the correct base branch.

### `prepare-release-post-merge-cleanup.sh`

After both release PRs (`release/*` -> `main` and `release/*` -> `develop`) are merged, verify merge state, remove the release branch remotely and locally, and transition scoped tracker items from `Merged` to `Released`.

Usage:

```bash
./scripts/development-workflow/prepare-release-post-merge-cleanup.sh <version|release-branch> [--from-changelog] [--issue N]... [--issues N,N,...]
```

Examples:

```bash
./scripts/development-workflow/prepare-release-post-merge-cleanup.sh v1.2.3 --from-changelog
./scripts/development-workflow/prepare-release-post-merge-cleanup.sh v1.2.3 --issues 232,240
./scripts/development-workflow/prepare-release-post-merge-cleanup.sh release/v1.2.3 --issue 232
```

Use this when:

- Both release PRs are already merged and you need deterministic release-branch cleanup.
- You want explicit, scoped tracker transitions to the terminal shipped status.
- You want `--from-changelog` to derive the shipped issue scope from the finalized version section instead of manually copying issue IDs.
- You need a fail-closed handoff for Linear: `TRACKER_ACTION=linear_mcp_or_api_required` means the listed issues still need MCP/API status transitions before release closeout is complete.

### `batch-merge.sh`

Deterministic merge pipeline for parallel batch PRs. Handles PR discovery (auto or explicit), metadata collection, merge ordering (non-CHANGELOG PRs first by ascending PR number, then CHANGELOG PRs by ascending PR number), and single-PR merge execution with structured key-value output.

Usage:

```bash
# Discovery mode — auto-discover all ready-for-human-review PRs targeting develop
./scripts/development-workflow/batch-merge.sh discover

# Discovery mode — explicit PR list
./scripts/development-workflow/batch-merge.sh discover --prs 101,102,103

# Per-PR merge — attempt to merge one PR into develop (called in a loop by the agent)
./scripts/development-workflow/batch-merge.sh merge --pr 101
```

Outputs structured `KEY=VALUE` lines. See the script header for the full output format.

Use this when:

- The agent protocol `94-batch-merge-protocol.md` is running a batch merge.
- You want to inspect the merge ordering for a set of PRs before invoking the agent command.
- Called by the `/batch-merge` Claude Code command, `/batch-merge` Cursor command, or the `/batch-merge` / `batch-merge` Codex skill alias.

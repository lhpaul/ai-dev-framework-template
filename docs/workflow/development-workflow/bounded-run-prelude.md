# Shared Bounded Run Prelude

Read-only helpers that unify scope resolution, repository guardrails snapshot,
and policy/checkpoint recommendation for **`/run-item`**, **`/run-items`**, and
**`/run-epic`** before any artifact mutation.

Related:

- [`protocols/95-run-epic-protocol.md`](protocols/95-run-epic-protocol.md) — epic bounded runs
- [`protocols/91-orchestrate-work-protocol.md`](protocols/91-orchestrate-work-protocol.md) — single-item control loop (after prelude)
- [`guardrails-enforcement.md`](guardrails-enforcement.md) — effective guardrails layering
- Spec: [`../../specs/developments/20260625150000_1048-orchestration-command-refactor/1_1048-orchestration-command-refactor_specs.md`](../../specs/developments/20260625150000_1048-orchestration-command-refactor/1_1048-orchestration-command-refactor_specs.md)

---

## Scripts

| Script | Purpose |
| ------ | ------- |
| `run-bounded-prelude.sh` | **Primary entry** — scope + guardrails + policy recommender JSON |
| `run-item-scope-resolver.sh` | Resolve one non-epic target to recommender-compatible scope (`scopeSource=item`) |
| `run-epic-scope-resolver.sh` | Epic scope (`scopeSource=epic`); `--items` is an internal-only flag |
| `run-epic-policy-recommender.sh` | Policy, checkpoints, and copy-paste command (shared) |

---

## Usage

**Single item** (issue, branch, PR, development folder, or router token):

```bash
./scripts/development-workflow/run-bounded-prelude.sh \
  --original-command "/run-item 1049" \
  --issue 1049 \
  --delegate-review --may-merge --may-start-backlog true --max-risk medium \
  --json
```

**Epic**:

```bash
./scripts/development-workflow/run-bounded-prelude.sh \
  --original-command "/run-epic issues 1047" \
  --epic 1047 \
  --delegate-review --may-merge --may-start-backlog true --max-risk medium \
  --json
```

**Explicit item list**:

```bash
./scripts/development-workflow/run-bounded-prelude.sh \
  --original-command "/run-items 1049 1050" \
  --items "1049,1050" \
  --delegate-review --may-merge --may-start-backlog true --max-risk medium \
  --json
```

The JSON output includes:

- `scope` — full resolver payload (`groups`, `items`, `baseBranch`, `policy` flags)
- `scope.baseReason`, `scope.baseWarnings`, and `scope.baseValidation` — the
  selected base branch rationale, visible fallback warnings, and read-only
  remote-branch validation result
- `guardrails` — repository `guardrails` snapshot (`mode`, `backlog_start`)
- `policyRecommendation` — same shape as `run-epic-policy-recommender.sh` alone
- `policyRecommendation.confirmationSummary` — operator-facing summary lines for
  resolved scope, effective policy, field sources, checkpoints, copy-paste
  equivalent, read-only guarantee, and the Protocol 91 invocation binding.

---

## Contract

1. **Read-only** — no tracker updates, branches, PRs, merges, or issue closure.
2. **One policy path** — single-item and explicit-list runs use the same
   recommender and checkpoint schema as `/run-epic` (no parallel autonomy
   system).
3. **Always-confirm** — `requiresConfirmation` is always `true`. The orchestrator
   must present `policyRecommendation.confirmationSummary` before any mutation.
   When all autonomy flags were provided explicitly in the invocation command,
   those explicit flags serve as the human's confirmation and the orchestrator
   may proceed immediately after printing the policy summary and recording the
   invocation-scoped confirmation binding. When any flag was inferred, scope is
   ambiguous, or pending checkpoints remain, the orchestrator must stop and wait
   for explicit human acceptance, checkpoint policy input, or re-invocation with
   corrected flags.
4. **Invocation-scoped continuation** — after confirmation, Protocol 91 records
   `RUN_ITEM_POLICY_CONFIRMED=true` with companion resolved-item and normalized
   selected-policy bindings. The binding satisfies only redundant prompts for
   the same item and policy. It never waives new guardrail stops, failed review,
   failed CI, risk violations, missing permissions, destructive-action stops, or
   pending checkpoints.
5. **Epic-like items** — `run-item-scope-resolver.sh` rejects epic issues; use
   `--epic` instead.
6. **Explicit-list base selection** — `--items` considers only the listed items.
   No integration labels resolve to `develop`. Partial or mixed
   `integration-branch:<slug>` coverage resolves to `develop` with a visible
   warning. A shared label may resolve to `develop-<slug>` only when the current
   repository remote confirms that branch exists; missing or unverifiable
   branches fall back to `develop` with a warning. In workflow-hub mode, product
   implementation base validation is deferred until the product repository is
   selected.

---

## Orchestrator integration

- **`/run-item`** and **`/run-epic`** agents should call `run-bounded-prelude.sh`
  before Protocol 91 or 95 mutation steps.
- **`/run-items`** agents should call `run-bounded-prelude.sh` before Protocol
  90 `explicit_list` mutation steps.
- **`/run-work`** portfolio runs do **not** use this prelude (Protocol 90 batch
  proposal path).

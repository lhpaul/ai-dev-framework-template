# Shared Bounded Run Prelude

Read-only helpers that unify scope resolution, repository guardrails snapshot,
and policy/checkpoint recommendation for **`/run-item`** and **`/run-epic`** before
any artifact mutation.

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
| `run-epic-scope-resolver.sh` | Epic or explicit item list scope (`scopeSource=epic` or `items`) |
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

The JSON output includes:

- `scope` — full resolver payload (`groups`, `items`, `baseBranch`, `policy` flags)
- `guardrails` — repository `guardrails` snapshot (`mode`, `backlog_start`)
- `policyRecommendation` — same shape as `run-epic-policy-recommender.sh` alone

---

## Contract

1. **Read-only** — no tracker updates, branches, PRs, merges, or issue closure.
2. **One policy path** — single-item runs use the same recommender and checkpoint
   schema as `/run-epic` (no parallel autonomy system).
3. **Human confirmation** — when `requiresConfirmation` is true, accept or
   customize policy/checkpoints before mutation (waive checkpoints in PR body
   or via `--checkpoints-file` on re-run).
4. **Epic-like items** — `run-item-scope-resolver.sh` rejects epic issues; use
   `--epic` instead.

---

## Orchestrator integration

- **`/run-item`** and **`/run-epic`** agents should call `run-bounded-prelude.sh`
  before Protocol 91 or 95 mutation steps.
- **`/run-work`** portfolio runs do **not** use this prelude (Protocol 90 batch
  proposal path).

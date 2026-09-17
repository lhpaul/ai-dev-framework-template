# Reviewer Preflight — Implementation Plan

**Spec**: [`1_1561-reviewer-preflight_specs.md`](1_1561-reviewer-preflight_specs.md)
**Smoke test runbook**: [`../../../testing/workflow/1561-reviewer-preflight.smoke-test.md`](../../../testing/workflow/1561-reviewer-preflight.smoke-test.md)
**Issue**: #1561

---

## Summary

**Approach**: Add a read-only **reviewer preflight** that cross-checks the three configuration surfaces (shared workflow reviewer configuration, machine-local override, and each platform's own configuration) before Protocol 91 dispatches an item. A new helper `scripts/development-workflow/reviewer-preflight.sh` resolves inputs for the three resume paths (pre-dispatch, existing branch without PR, existing PR), calls a new Python module `scripts/development-workflow/reviewer_preflight.py` for deterministic cross-check logic, prints a stable `KEY=value` report, and exits with codes that Protocol 91 treats as proceed vs stop. Protocol 91 invokes the preflight immediately before the item's first mutation on fresh runs and uses the branch/PR resume paths when resuming. Integration docs (starting with CodeRabbit) document branch-in-force resolution (AC-3).

**Estimated complexity**: L

<!-- S: < 1 day | M: 1-3 days | L: 3+ days -->

**Rationale**: The spec defines three resume paths, four disagreement reasons, five run outcomes, per-bucket supported-platform lists, draft-state adjustment parity with Step 7a, and strict side-effect freedom. Implementation touches a new Python cross-check engine, a shell wrapper with git ref reads matching `pr-review-loop.sh`, Protocol 91 orchestration, item-orchestrator agent mirrors, platform integration docs, and three automated test suites (Python unit, shell contract, protocol surface consistency). Reuse from #1495 (`review-effective`, CodeRabbit YAML probes) reduces risk but does not remove the cross-surface matrix.

**Dependencies**: Spec PR #1733 merged on `develop`. No other feature must merge first.

**Precondition at implementation start**: Re-read [`1_1561-reviewer-preflight_specs.md`](1_1561-reviewer-preflight_specs.md) at current `develop` head before the first file edit. If acceptance criteria or the decision-gate matrix changed, reconcile this plan and record it in the implementation PR.

---

## Verification Log

Commands run at repo revision `32605700` (`origin/develop`) on 2026-09-17T11:10:20Z from the repository root.

| Check | Command / query | Result |
| --- | --- | --- |
| VL-1 — Repo revision | `git rev-parse --short HEAD` | `32605700` |
| VL-2 — No preflight implementation yet | `grep -rln 'reviewer.preflight\|reviewer_preflight' scripts/` | No matches |
| VL-3 — PR base config pattern | `grep -n 'git show "origin/${_pr_base}:.ai-dev-workflow.yaml"' scripts/development-workflow/pr-review-loop.sh` | Line ~12109 — canonical pattern for shared list on PR target base |
| VL-4 — Step 7a resolver | `test -f scripts/development-workflow/resolve-reviewer-availability.sh && test -f scripts/development-workflow/workflow-config-resolver.py` | Both present; `review-effective` subcommand ships (#1495) |
| VL-5 — CodeRabbit config probe reuse | `grep -n '\.coderabbit\.yaml' scripts/development-workflow/resolve-reviewer-availability.sh` | Existing bounded read + `reviews.auto_review.enabled` interpretation |
| VL-6 — AC-3 doc gap | `grep -rln "pull request's own branch\|branch-in-force" docs/workflow/development-workflow/integrations/` | No matches — documentation work required |
| VL-7 — Protocol 91 hook point | `grep -n 'Step 3\|first mutation\|nested-artifact-guard' docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md \| head -20` | Guards and dispatch live in early Step 3 / Step 4 region — preflight inserts before first mutation there |
| VL-8 — Bounded same-surface open PRs | Handoff: `same-surface open PRs: none` for batch; `gh pr list --head implementation-plan/1561-reviewer-preflight` | Empty |
| VL-9 — Nested artifact guard | `run-nested-artifact-guard.sh --mode pre-create --issue 1561 ...` | `RESULT=clean`, `APPROVED_BASE=develop` |

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved plan base branch | `develop` | Handoff + `run-nested-artifact-guard.sh` | 2026-09-17T11:10:20Z at `32605700` | Item #1561 only | `Verified` |
| Spec merged prerequisite | Spec at `docs/specs/developments/20260911230501_1561-reviewer-preflight/1_1561-reviewer-preflight_specs.md` on `develop` | `workflow-next-action.sh --development ...` → `STATUS=Spec Ready`, `NEXT_ACTION=write-plan` | Same | Same invocation | `Verified` |
| Same-surface concurrent PRs | None changing reviewer preflight surfaces | Parent handoff `same-surface open PRs: none` | Same | Batch list 1757,1462,1496,1515,1561,1583,1529 — only #1561 touches this feature | `Verified` |

No conflicts were found.

---

## Definitions

- **Shared workflow reviewer configuration** — `review.on_draft.runner`, `review.on_draft.github`, and `review.on_ready.github` in `.ai-dev-workflow.yaml`, read from the ref rules in the spec (target base for shared list when a PR exists; targeted execution base otherwise).
- **Machine-local override** — `.ai-dev-workflow.local.yaml` review keys, resolved once from the machine running the preflight; replaces the shared list per stage outright when present.
- **Platform own configuration** — repository-hosted files the platform reads from the **branch in force** (for example `.coderabbit.yaml` on the item branch or PR head).
- **Resolved reviewer list** — per lifecycle bucket, the list this machine will actually use after override replacement.
- **Remaining lifecycle stages** — every stage bucket this item's execution will still exercise from the preflight call forward (not only the next stage).

---

## Decisions

### Decision 1 — Preflight lives in Protocol 91, not the bounded prelude

The bounded prelude (`run-bounded-prelude.sh`) stays read-only by contract. The preflight runs **immediately before the item's first mutation** inside Protocol 91 (fresh, branch-resume, and PR-resume paths). Batch dispatch (#1743) remains out of scope; each item still gets its own preflight per spec Out of Scope entry 12.

**Rejected**: `--preflight` mode on `pr-review-loop.sh` (spec Out of Scope entry 2 — would run after PR exists for fresh items).

### Decision 2 — Python owns cross-check logic; shell owns git refs and printing

`reviewer_preflight.py` implements supported-platform checks, disagreement reason aggregation, outcome determination, and bounded file reads. `reviewer-preflight.sh` resolves git refs (`git show origin/<base>:...`, `git show <branch>:...`), fetches PR fields via `gh` when needed, passes JSON stdin to Python, and prints the `KEY=value` block. This mirrors the #1495 split (resolver + availability shell).

### Decision 3 — Time budget: 15 seconds total, 4 seconds per platform read

Satisfies the spec's product property (slow/unreachable → Undetermined, cost negligible vs guarded work). Constants: `PREFLIGHT_BUDGET_SECONDS=15`, `PREFLIGHT_PER_PLATFORM_CAP_SECONDS=4`. Test mode honors `WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE=1` with overridable caps for hermetic tests only.

### Decision 4 — Open Question 4: one report row per platform name; bucket detail in structured fields

When the same platform name appears in multiple lifecycle buckets with different bucket-scoped outcomes, emit **one** `PLATFORM_N_*` group per platform name (spec "exactly once"). Set `PLATFORM_N_VERDICT` to the most severe bucket outcome (`cannot-review` > `undetermined` > `can-review`). Include `PLATFORM_N_BUCKET_JSON` — a JSON array of `{bucket, verdict, reasons[]}` — so operators see per-bucket contradictions without duplicate rows. Run outcome still uses the canonical most-severe rule across platforms.

### Decision 5 — Open Question 3: no second malformed-scalar detector in preflight

When the pre-existing configuration loader resolves a malformed scalar to an empty list, the run fails before preflight as today. The preflight does not add independent detection for that case (spec default). Document in troubleshooting only.

### Decision 6 — Reuse CodeRabbit interpretation from Step 7a

Extract the bounded `.coderabbit.yaml` read from `resolve-reviewer-availability.sh` into a shared Python helper imported by both Step 7a probes and preflight (single source for `reviews.auto_review.enabled`, drafts, and `base_branches`). Step 7a behavior must not change except via shared helper refactor with existing tests still passing.

### Decision 7 — Stage-excluded uses the same draft→ready adjustment as Step 7a

When Protocol 91's internal review gate would convert draft→non-draft before dispatching a draft-declining runner reviewer, preflight evaluates that platform against post-adjustment PR state (spec Example 5 / AC stage-excluded bullet).

### Decision 8 — Hosted platforms without repo-local config

Platforms with no readable in-repo configuration classify as **Undetermined** (`no-readable-surface`), not Cannot review — matching spec Use Case 4. This includes platforms dispatched only via GitHub App settings outside the repo.

---

## Contracts

### `reviewer-preflight.sh`

```text
scripts/development-workflow/reviewer-preflight.sh \
  --repo-root <path> \
  --mode pre-dispatch|branch-resume|pr-resume \
  --target-base <branch> \
  [--branch <name>] \
  [--pr <number>] \
  [--owner <owner> --repo <repo>] \
  [--remaining-stages <csv>] \
  [--draft-state <draft|ready>] \
  [--json]
```

Read-only: no `git` state changes, no `gh` mutations, no file writes under `--repo-root`.

**Exit codes**

| Code | Meaning |
| --- | --- |
| `0` | Outcome `passed`, `passed-unverified`, or `no-review-remaining` — caller may dispatch |
| `1` | Outcome `blocked` — do not dispatch |
| `2` | Outcome `prerequisite-failed` — fix inputs and re-run |
| `3` | Internal failure (tooling error) |

**Summary block** (stable keys; extend only additively)

```text
OUTCOME=<passed|passed-unverified|blocked|prerequisite-failed|no-review-remaining>
OUTCOME_LABEL=<display label from spec>
CHECKED_SHARED_CONFIG_REF=<ref description>
CHECKED_PLATFORM_CONFIG_REF=<ref description>
LOCAL_OVERRIDE_STATE=<none|applied|present-unpropagated details>
PLATFORM_COUNT=<n>
PLATFORM_1_NAME=<name>
PLATFORM_1_VERDICT=<operable|not-operable|undetermined|override-excluded>
PLATFORM_1_REASONS=<comma-separated reason codes>
PLATFORM_1_SURFACE=<file path>
PLATFORM_1_SETTING=<setting name>
PLATFORM_1_DETAIL=<human contradiction text>
PLATFORM_1_REMEDY=<action text>
PLATFORM_1_BUCKET_JSON=<json array>
... numbered through PLATFORM_COUNT ...
ELAPSED_SECONDS=<decimal>
BUDGET_SECONDS=15
```

### `reviewer_preflight.py`

Invoked as:

```text
python3 scripts/development-workflow/reviewer_preflight.py \
  --input-json <file>
```

Input JSON carries: mode, target_base, branch, pr metadata, remaining stage buckets, per-stage PR state after adjustments, resolved lists per bucket (from resolver + override), and platform config payloads read by the shell. Output JSON mirrors the platform groups and outcome; shell translates to `KEY=value`.

---

## Layer-by-Layer Changes

### Shared Packages / Libraries

- [ ] **`scripts/development-workflow/reviewer_preflight.py`** (new): cross-check engine, outcome matrix, reason codes aligned with spec enums.
- [ ] **`scripts/development-workflow/reviewer_preflight_coderabbit.py`** (new, or module section): shared CodeRabbit config parser extracted from availability probe logic.
- [ ] **`workflow-config-resolver.py`**: add `review-github-effective` (or extend `review-effective`) to return `on_draft.github` and `on_ready.github` effective lists + parse states + override exclusions per bucket (read-only, no `git`/`gh`).

### Backend / Workflow Scripts

- [ ] **`scripts/development-workflow/reviewer-preflight.sh`** (new): CLI, git ref resolution, bounded reads, report printing, exit codes.
- [ ] **`resolve-reviewer-availability.sh`**: refactor to call shared CodeRabbit helper (behavior-preserving).

### Backend / Protocol Surfaces

- [ ] **`docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`**: invoke preflight before first mutation; document three resume paths, outcomes, and that Step 7/7a behavior is unchanged after pass.
- [ ] **`.cursor/agents/item-orchestrator.md`** and **`.claude/agents/item-orchestrator.md`**: require preflight stop on `blocked` / `prerequisite-failed`; print report before item output.
- [ ] **`docs/workflow/development-workflow/README.md`**: short operator subsection linking to preflight behavior.

### Integration Documentation (AC-3)

- [ ] **`docs/workflow/development-workflow/integrations/coderabbit.md`**: branch-in-force rule, two consequences, PR #1532 observation reference.
- [ ] **`docs/workflow/development-workflow/integrations/codex-github.md`**: same rule for `.github/codex/` or documented config path if applicable.
- [ ] **`docs/workflow/development-workflow/integrations/pr-review-platform.md`**: cross-link preflight vs Step 7 reachability (configuration coherence vs runtime probe).

### Configuration / Manifest

- [ ] **`sync-manifest.yaml`**: include new scripts if product-repo injection lists individual helpers (mirror `resolve-reviewer-availability.sh` entry pattern).

### Documentation Updates (developer executes post-implementation)

- `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` (already in scope above)
- Integration docs listed above
- `AGENTS.md` — one row in workflow table if a dedicated command is exposed (optional alias in `.cursor/commands/` only if parity needed)

**None** beyond the above for `docs/project/*` or stack docs.

---

## Testing Strategy

| Suite | File | Covers |
| --- | --- | --- |
| Python unit | `scripts/development-workflow/tests/test_reviewer_preflight.py` | All four disagreement reasons, undetermined paths, prerequisite ordering, multi-reason aggregation, OQ4 bucket JSON, empty resolved list → passed, no-review-remaining |
| Shell contract | `scripts/development-workflow/tests/test-reviewer-preflight.sh` | `# covers: reviewer-preflight.sh` — hermetic git fixtures via temp repos, exit codes, side-effect freedom (clean tree before/after), timeout → undetermined |
| Surface consistency | `scripts/development-workflow/tests/test-reviewer-preflight-surfaces.sh` | Protocol 91 + agent mirrors name same outcomes/labels as spec matrix |

Run via existing `select-test-suites.sh` discovery (`# covers:` header).

**Smoke test**: `docs/testing/workflow/1561-reviewer-preflight.smoke-test.md` — end-to-end on this repository with fixture overrides; maps to AC-1, AC-2, AC-3 spot checks.

---

## Residual Verification Strategy

Before applying `ready-for-human-review` on the implementation PR, re-run:

```bash
grep -rln 'reviewer.preflight\|reviewer_preflight' scripts/ docs/workflow/
```

Confirm every hit is accounted for in the plan's file list. Re-run surface consistency suite after any late doc edit.

---

## Implementation Order

1. *(Spec — AC-1/2 core)* Implement `reviewer_preflight.py` with unit tests for outcome matrix and reason codes.
   *Verify*: `python3 -m pytest scripts/development-workflow/tests/test_reviewer_preflight.py` or `python3 scripts/development-workflow/tests/test_reviewer_preflight.py` — all pass.

2. *(Spec — shared lists)* Extend `workflow-config-resolver.py` for per-bucket GitHub reviewer effective lists; extend `tests/test-workflow-config-resolver.sh`.
   *Verify*: resolver tests pass; JSON includes draft and ready github lists with override exclusions.

3. *(Spec — Decision 6)* Extract shared CodeRabbit config helper; wire into `resolve-reviewer-availability.sh` without changing existing T-* expectations.
   *Verify*: `bash scripts/development-workflow/tests/test-resolve-reviewer-availability.sh` — all pass.

4. *(Spec — contracts)* Implement `reviewer-preflight.sh` + `tests/test-reviewer-preflight.sh`.
   *Verify*: `shellcheck --severity=warning scripts/development-workflow/reviewer-preflight.sh`; shell test suite pass.

5. *(Spec — AC "reachable where needed")* Update Protocol 91 and item-orchestrator agents; add `tests/test-reviewer-preflight-surfaces.sh`.
   *Verify*: surface suite pass; grep confirms preflight before first mutation language.

6. *(Spec — AC-3)* Update integration docs (CodeRabbit, codex-github, pr-review-platform).
   *Verify*: read docs and confirm branch-in-force + two consequences + PR #1532 traceability.

7. *(Process)* Execute smoke runbook; record results in implementation PR.

8. *(Process)* Add changelog fragment on implementation PR:

   ```markdown
   - **Reviewer preflight before item dispatch** (#1561): cross-check shared workflow reviewer configuration, machine-local overrides, and each platform's own configuration before Protocol 91 creates branches or pull requests, reporting Blocked with file/setting/contradiction detail when surfaces disagree, and documenting branch-in-force configuration for hosted reviewers.
   ```

---

## Out-of-scope notes

- Batch-level aggregated preflight (#1743) — per spec entry 12.
- Scratch PR creation — spec entry 1.
- Live GitHub App / service availability probes — spec entry 11; Step 7a reachability unchanged.
- Changing reviewer gate behavior after preflight passes — spec mirror surfaces.
- `--preflight` on `pr-review-loop.sh` — spec entry 2.

---

## Cross-Cutting Operational Assumptions (implementation handoff)

| Assumption | Still valid if |
| --- | --- |
| Single-repo mode; artifact owner is this repository | `.ai-dev-workflow.yaml` has no conflicting `mode` change |
| Integration branch `develop` | Unchanged in workflow config |
| #1495 resolver contracts stable | `review-effective` tests still pass at implementation start |

Implementation agent must record `Still valid` or stop with evidence per protocol 03.

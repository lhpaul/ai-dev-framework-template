# Smoke Test Runbook: Reviewer Preflight

**Feature**: Reviewer preflight before item dispatch
**Spec**: [`1_1561-reviewer-preflight_specs.md`](../../specs/developments/20260911230501_1561-reviewer-preflight/1_1561-reviewer-preflight_specs.md)
**Implementation plan**: [`2_1561-reviewer-preflight_implementation-plan.md`](../../specs/developments/20260911230501_1561-reviewer-preflight/2_1561-reviewer-preflight_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Workflow tooling only — no application server.

- [ ] Implementation branch for #1561 with `reviewer-preflight.sh` and `reviewer_preflight.py` present.
- [ ] `bash`, `git`, `python3` (+ `PyYAML==6.0.2`), `jq`, and `gh` (authenticated) available.
- [ ] Run snippets from repository root in `bash --noprofile --norc`.
- [ ] Preserve `.ai-dev-workflow.local.yaml` if present (move aside before fixtures, restore in `trap`).

---

## Test Data

| Item | Value |
| --- | --- |
| Preflight script | `scripts/development-workflow/reviewer-preflight.sh` |
| Repository root | checkout under test |
| Default target base | `develop` |
| Shipped runner list | `claude`, `cursor`, `codex` (local-runtime — expect undetermined or can-review per machine) |

---

## Smoke Test Steps

### Step 0: Clean tree baseline (AC-2)

**Maps to**: AC-2 side-effect freedom

<!-- workflow-shell-contract: bash -->
```bash
set -euo pipefail
git status --porcelain
test -z "$(git status --porcelain)"
```

Record: working tree clean before preflight.

### Step 1: Pre-dispatch pass on shipped configuration (AC-2)

**Maps to**: AC-2 Passed path on coherent config

<!-- workflow-shell-contract: bash -->
```bash
set -euo pipefail
report="$(mktemp)"
./scripts/development-workflow/reviewer-preflight.sh \
  --repo-root "$(pwd -P)" \
  --mode pre-dispatch \
  --target-base develop \
  --remaining-stages on_draft.runner,on_draft.github,on_ready.github \
  | tee "$report"
rc=${PIPESTATUS[0]}
printf 'exit=%s\n' "$rc"
grep '^OUTCOME=' "$report"
test -z "$(git status --porcelain)"
```

**Expected**: Exit `0`; `OUTCOME` is `passed` or `passed-unverified` (not `blocked`). Tree still clean afterward.

### Step 2: Automatic review off → Blocked (AC-1)

**Maps to**: AC-1 review-disabled

Use a temporary fixture directory with `.coderabbit.yaml` having `reviews.auto_review.enabled: false` and a workflow yaml listing `coderabbit` in `review.on_draft.github`. Point `--repo-root` at the fixture (implementation must support fixture root).

**Expected**: Exit `1`; `OUTCOME=blocked`; platform names `Automatic review turned off` / reason `review-disabled`; names file and setting.

### Step 3: Branch-in-force documentation (AC-3)

**Maps to**: AC-3

Read `docs/workflow/development-workflow/integrations/coderabbit.md` and confirm it states:

1. Platform config is read from the PR's own branch (head), not target base.
2. Fix on branch applies to that PR without merge.
3. Branch can diverge silently from integration policy.
4. Traceability to live observation (PR #1532).
5. The four disagreement cases (automatic review off, stage not covered, base branch not covered, unsupported reviewer) each appear with at least one remedy.

### Step 4: Existing PR resume path (B-5 / AC existing PR)

**Maps to**: Existing-PR acceptance group

With an open workflow PR in this repo (or a test PR number in a fork), run:

<!-- workflow-shell-contract: bash -->
```bash
set -euo pipefail
./scripts/development-workflow/reviewer-preflight.sh \
  --repo-root "$(pwd -P)" \
  --mode pr-resume \
  --pr <number> \
  --owner lhpaul --repo ai-dev-framework-template \
  --target-base develop \
  --remaining-stages on_draft.runner,on_draft.github,on_ready.github \
  --pr-state on_draft.runner=draft,on_draft.github=draft,on_ready.github=ready
```

**Expected**: Report distinguishes shared config checked against PR target base vs platform config checked against PR head branch (`CHECKED_*_REF` fields). Omitting `--remaining-stages` or any required `--pr-state` entry must yield `prerequisite-failed` (exit `2`), not `passed`.

### Step 5: No review remaining (resume cleanup)

**Maps to**: No review remaining outcome

Invoke with `--remaining-stages` empty (or flag meaning no reviewer stages left).

**Expected**: Exit `0`; `OUTCOME=no-review-remaining`; no `PLATFORM_*` cross-check rows.

---

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `prerequisite-failed` | Missing/invalid `--target-base` or malformed `--remaining-stages` |
| All platforms undetermined | Local-only platforms without repo config — expected; outcome should be `passed-unverified` if nothing is Cannot review |
| Timeout undetermined | Incomplete read with no prior disagreement → `check-inconclusive`; if disagreement was already proven, expect `cannot-review` instead. Increase caps only under `WORKFLOW_REVIEWER_PREFLIGHT_TEST_MODE=1` in tests |

## Known Limitations

Configuration coherence only — removed GitHub Apps still read as Can review until dispatch fails (spec Out of Scope item 11).

---

## Results

| Step | Pass / Fail | Notes |
| --- | --- | --- |
| 0 | Pass | `git status --porcelain` empty before the run |
| 1 | Pass | `OUTCOME=passed-unverified` against this repository's own shipped `.ai-dev-workflow.yaml` (`claude`, `pr-agent`, `bugbot` all `Undetermined`/`no-readable-surface` — no in-repo own-configuration to cross-check; matches Decision 8). Exit `0`. Tree clean after. |
| 2 | Pass | Reproduced with a hermetic fixture repo (`.coderabbit.yaml` with `reviews.auto_review.enabled: false`, `.ai-dev-workflow.yaml` listing `coderabbit` in `review.on_draft.github`): `OUTCOME=blocked`, exit `1`, `PLATFORM_1_REASONS=review-disabled`, `PLATFORM_1_SURFACE=.coderabbit.yaml`, `PLATFORM_1_SETTING=reviews.auto_review.enabled`, remedy names both the config edit and the shared-list edit. Matches the spec's "Automatic review turned off" worked example verbatim. Also covered automatically by `test-reviewer-preflight.sh` T-2. |
| 3 | Pass | `coderabbit.md` states the branch-in-force rule (§6), both consequences, PR #1532 traceability, and all four disagreement cases with remedies in a table; `codex-github.md` and `pr-review-platform.md` cross-link it. Verified automatically by `test-reviewer-preflight-surfaces.sh`. |
| 4 | Partial | No open PR existed on this repository at implementation time (`gh pr list` returned empty), so the live-PR variant of this step could not be executed against a real GitHub pull request. The `pr-resume` mode's ref-distinguishing behavior (`CHECKED_SHARED_CONFIG_REF` names the PR's target base; `CHECKED_PLATFORM_CONFIG_REF` names the PR's own head branch, not the base) is instead verified by `test-reviewer-preflight.sh` T-6 against a hermetic git fixture with a faked `gh pr view` response, and manually confirmed `--remaining-stages`/`--pr-state` omission produces `prerequisite-failed` (exit `2`) via T-3/T-5 in the same suite. |
| 5 | Pass | `--remaining-stages ""` (explicit empty): `OUTCOME=no-review-remaining`, exit `0`, `PLATFORM_COUNT=0`. Omitting `--remaining-stages` entirely instead produces `OUTCOME=prerequisite-failed`, exit `2` (distinguishing unresolved from resolved-empty, per the spec's Triggers section). |

**Platform tested**: macOS (Darwin 25.6.0), bash, git, python3 (PyYAML 6.0.2), jq, gh.

**Tester**: developer agent (issue #1561 implementation).

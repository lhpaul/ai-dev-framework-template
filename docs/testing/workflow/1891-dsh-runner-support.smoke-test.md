# Smoke Test Runbook: First-class DSH Runner Support

**Feature**: First-class DSH (DeepSeek Harness) runner support
**Spec**: [`1_dsh-runner-support_specs.md`](../../specs/developments/20261006213017_dsh-runner-support/1_dsh-runner-support_specs.md)
**Implementation plan**: [`2_dsh-runner-support_implementation-plan.md`](../../specs/developments/20261006213017_dsh-runner-support/2_dsh-runner-support_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

This feature is workflow tooling, not an application. There is no server to start and no database to seed.

- [ ] You are on the implementation branch for #1891 with the change applied.
- [ ] `python3`, `jq`, `git`, and `bash` are available. Start one dedicated Bash session with `bash --noprofile --norc` from the repository root, then run all snippets in that session. Every mutation fails closed; expected resolver non-zero exits are captured with `smoke_status=0; … || smoke_status=$?` (do not let `set -e` abort the session on an expected block).
- [ ] Preserve the checkout’s original override before any fixture writes (same restore pattern as the #1495 smoke runbook). On interruption, retain the printed state-directory path for recovery.

  <!-- workflow-shell-contract: bash -->
  ```bash
  set -euo pipefail
  SMOKE_REPO_ROOT="$(pwd -P)"
  SMOKE_STATE="$(mktemp -d "${TMPDIR:-/tmp}/dsh-runner-smoke.XXXXXX")"
  SMOKE_TMP="$SMOKE_STATE/fixtures"
  mkdir "$SMOKE_TMP"
  export SMOKE_TMP
  printf 'Smoke recovery directory: %s\n' "$SMOKE_STATE"
  SMOKE_OVERRIDE_STATE=pending
  smoke_restore_override() {
    case "$SMOKE_OVERRIDE_STATE" in
      absent|saved) ;;
      pending|restored) return 0 ;;
      *) return 1 ;;
    esac
    if [ "$SMOKE_OVERRIDE_STATE" = saved ]; then
      if [ ! -e "$SMOKE_STATE/original-override" ] && [ ! -L "$SMOKE_STATE/original-override" ]; then
        printf 'Original override missing; inspect %s\n' "$SMOKE_STATE" >&2
        return 1
      fi
    fi
    if [ -e "$SMOKE_REPO_ROOT/.ai-dev-workflow.local.yaml" ] || [ -L "$SMOKE_REPO_ROOT/.ai-dev-workflow.local.yaml" ]; then
      smoke_leftover="$(mktemp -d "$SMOKE_STATE/leftover.XXXXXX")" || return 1
      mv "$SMOKE_REPO_ROOT/.ai-dev-workflow.local.yaml" "$smoke_leftover/test-override" || return 1
    fi
    if [ "$SMOKE_OVERRIDE_STATE" = saved ]; then
      mv "$SMOKE_STATE/original-override" "$SMOKE_REPO_ROOT/.ai-dev-workflow.local.yaml" || return 1
    fi
    SMOKE_OVERRIDE_STATE=restored
    printf '%s\n' "$SMOKE_OVERRIDE_STATE" > "$SMOKE_STATE/override-state" || return 1
  }
  trap 'smoke_exit=$?; if ! smoke_restore_override; then printf "Override restoration failed; inspect %s\n" "$SMOKE_STATE" >&2; smoke_exit=1; fi; exit "$smoke_exit"' EXIT
  if [ -e .ai-dev-workflow.local.yaml ] || [ -L .ai-dev-workflow.local.yaml ]; then
    mv .ai-dev-workflow.local.yaml "$SMOKE_STATE/original-override"
    SMOKE_OVERRIDE_STATE=saved
  else
    SMOKE_OVERRIDE_STATE=absent
  fi
  printf '%s\n' "$SMOKE_OVERRIDE_STATE" > "$SMOKE_STATE/override-state"
  ```

- [ ] Note which of `claude`, `cursor-agent`, `codex`, and `dsh` are on your `PATH`:

  <!-- workflow-shell-contract: bash -->
  ```bash
  set -euo pipefail
  for b in claude cursor-agent codex dsh; do printf '%s: %s\n' "$b" "$(command -v "$b" || echo absent)"; done
  ```

No design assets exist for this item — it changes no user interface — so this runbook contains no design-fidelity step.

---

## Smoke Test Steps

### Step 1: Shipped default stays Claude-only

**Maps to**: AC-11, BR-2, BR-3

1. Confirm `.ai-dev-workflow.yaml` `review.on_draft.runner` lists only `claude`.
2. Confirm `docs/workflow/development-workflow/README.md` still contains the exact prose `The shipped list is \`[claude]\``.
3. Run `bash scripts/development-workflow/tests/test-step7a-surface-consistency.sh` and confirm it passes (includes D-9 parse).

**Expected result**: Shipped default and README parse contract remain Claude-only; surface-consistency suite is green.

### Step 2: Opt-in `dsh` is accepted and probed

**Maps to**: AC-1, AC-2, UC-1

Use a hermetic `PATH` for this step. Do **not** rely on the machine’s real PATH: if `dsh` is already installed (common on this template’s authoring machines), an “absent” probe will falsely report `reachable`.

1. Write a local override that sets `review.on_draft.runner` to `[dsh]` only (keep shipped `warn` policy):

   <!-- workflow-shell-contract: bash -->
   ```bash
   set -euo pipefail
   printf 'review:\n  on_draft:\n    runner:\n      - dsh\n' > .ai-dev-workflow.local.yaml
   ```

2. Build a hermetic PATH that deliberately omits `dsh`, then run the resolver (capture the expected non-zero exit — sole configured reviewer absent → `zero-reachable`):

   <!-- workflow-shell-contract: bash -->
   ```bash
   set -euo pipefail
   mkdir -p "$SMOKE_TMP/bin"
   for c in awk bash cat cut date dirname git grep gh head jq mktemp perl printf python3 rm sed sleep sort tr wc; do
     src="$(type -P "$c")" || { printf 'Missing executable: %s\n' "$c" >&2; exit 1; }
     ln -sf "$src" "$SMOKE_TMP/bin/$c"
   done
   smoke_status=0
   PATH="$SMOKE_TMP/bin" bash scripts/development-workflow/resolve-reviewer-availability.sh \
     --repo-root "$(pwd -P)" --owner example --repo test --runner-kind claude \
     | tee "$SMOKE_TMP/dsh-absent.out" || smoke_status=$?
   printf 'exit=%s\n' "$smoke_status"
   [ "$smoke_status" -eq 1 ]
   ```

3. Confirm the indexed `dsh` record is `STATUS=unreachable` with `REASON=runtime-absent`, a non-empty `REMEDY` that matches the shared local-runtime pattern (install the reviewer’s runtime, or remove the entry from `review.on_draft.runner` in `.ai-dev-workflow.local.yaml` — the shipped remedy text is generic, not a DSH-named string), `OUTCOME=blocked`, and `BLOCK_CAUSE=zero-reachable`.

4. Put a stub `dsh` on that hermetic PATH that exits 0 for `--version`, re-run, and confirm `reachable` with exit `0`:

   <!-- workflow-shell-contract: bash -->
   ```bash
   set -euo pipefail
   printf '#!/bin/sh\necho "dsh 0.0.0-stub"\n' > "$SMOKE_TMP/bin/dsh"
   chmod +x "$SMOKE_TMP/bin/dsh"
   smoke_status=0
   PATH="$SMOKE_TMP/bin" bash scripts/development-workflow/resolve-reviewer-availability.sh \
     --repo-root "$(pwd -P)" --owner example --repo test --runner-kind claude \
     | tee "$SMOKE_TMP/dsh-present.out" || smoke_status=$?
   printf 'exit=%s\n' "$smoke_status"
   [ "$smoke_status" -eq 0 ]
   ```

5. Confirm `dsh` is `STATUS=reachable` in `$SMOKE_TMP/dsh-present.out`. Leave the hermetic bin / override in place for Step 3, or recreate them the same way if you reset.

**Expected result**: Validation accepts `dsh`; hermetic probe distinguishes absent (`runtime-absent` + `zero-reachable`) vs present (`reachable`).

### Step 3: Driving-session kind `dsh` and unknown rejection

**Maps to**: AC-1a, AC-1

1. With a reachable `dsh` override (Step 2 stub still on hermetic PATH, or recreate it), run with `--runner-kind dsh` and confirm exit `0` (no `unsupported runner-kind`):

   <!-- workflow-shell-contract: bash -->
   ```bash
   set -euo pipefail
   smoke_status=0
   PATH="$SMOKE_TMP/bin" bash scripts/development-workflow/resolve-reviewer-availability.sh \
     --repo-root "$(pwd -P)" --owner example --repo test --runner-kind dsh \
     | tee "$SMOKE_TMP/runner-kind-dsh.out" || smoke_status=$?
   printf 'exit=%s\n' "$smoke_status"
   [ "$smoke_status" -eq 0 ]
   ```

2. Run with an unsupported kind and confirm the helper fails closed (message is on stderr):

   <!-- workflow-shell-contract: bash -->
   ```bash
   set -euo pipefail
   smoke_status=0
   PATH="$SMOKE_TMP/bin" bash scripts/development-workflow/resolve-reviewer-availability.sh \
     --repo-root "$(pwd -P)" --owner example --repo test --runner-kind not-a-runner \
     >"$SMOKE_TMP/runner-kind-bad.out" 2>&1 || smoke_status=$?
   printf 'exit=%s\n' "$smoke_status"
   [ "$smoke_status" -ne 0 ]
   grep -q 'unsupported runner-kind' "$SMOKE_TMP/runner-kind-bad.out"
   ```

3. Configure a nonsense reviewer value in the override and confirm `value-not-supported` (not silent drop); capture the expected non-zero exit:

   <!-- workflow-shell-contract: bash -->
   ```bash
   set -euo pipefail
   printf 'review:\n  on_draft:\n    runner:\n      - not-a-real-reviewer\n' > .ai-dev-workflow.local.yaml
   smoke_status=0
   PATH="$SMOKE_TMP/bin" bash scripts/development-workflow/resolve-reviewer-availability.sh \
     --repo-root "$(pwd -P)" --owner example --repo test --runner-kind claude \
     | tee "$SMOKE_TMP/value-not-supported.out" || smoke_status=$?
   printf 'exit=%s\n' "$smoke_status"
   [ "$smoke_status" -eq 1 ]
   grep -q 'value-not-supported' "$SMOKE_TMP/value-not-supported.out"
   ```

4. Confirm a hosted value such as `coderabbit` or `codex-github` remains accepted when configured (skip live hosted probes if `gh`/network unavailable; unit suite coverage is enough for hosted probe mechanics). Restore a sensible override afterward if later steps need `[dsh]`.

**Expected result**: `dsh` is a first-class driving kind; unknown values still reject; hosted values remain in the supported set.

### Step 4: Protocol 91 surfaces name `dsh`

**Maps to**: AC-3, AC-3a, AC-5, AC-6

1. In `91-orchestrate-work-protocol.md`, confirm:
   - Supported reviewer values include `dsh` as local-runtime.
   - Draft-restriction mapping includes `dsh` with Never.
   - Dispatch map has `dsh` rows for `spec/*`, `implementation-plan/*`, and implementation prefixes routing to shared workflow reviewer skills against `REVIEW.md`.
   - Cross-runner CLI paragraph includes `DSH_PERMISSION_MODE=read-only dsh --profile headless`.
2. Re-run `test-step7a-surface-consistency.sh` if you edited those surfaces after Step 1.

**Expected result**: Protocol surfaces and D-1/D-6 contracts agree.

### Step 5: Operator docs discoverability

**Maps to**: AC-7, AC-8, AC-9, AC-10, UC-4

1. Confirm `docs/workflow/development-workflow/integrations/dsh.md` exists and includes install, profiles, provider routes, subagent model selection, headless mode, and a parent-orchestrated dispatch section (no separate dispatch-profile doc).
2. Confirm AGENTS.md and the workflow README command matrices include a DSH column (or equivalent first-class cell).
3. Confirm `agent-model-config.md` has DSH tier / dispatch-time pinning guidance.
4. Confirm `provider-contingency-runner-failover.md` mentions DSH in the runner-unavailable failover path.
5. Confirm the workflow README Integration Guides list links `integrations/dsh.md`.

**Expected result**: An operator can configure and fail over DSH from published docs alone.

### Step 6: Headless read-only composition (when DSH is installed)

**Maps to**: AC-6, BR-6, UC-3

1. If `dsh` is not installed, mark this step SKIPPED with reason `dsh absent` (unit/docs coverage still required).
2. If installed, from the repo root run a trivial headless invocation under the read-only preset, for example:

   <!-- workflow-shell-contract: bash -->
   ```bash
   set -euo pipefail
   DSH_PERMISSION_MODE=read-only dsh --profile headless 'Reply with exactly: ok'
   ```

3. Confirm the process prints a final answer and exits successfully (or documents a clear auth/provider failure distinct from a missing read-only preset).
4. Confirm docs state that read-only enforcement uses the permission preset / `DSH_PERMISSION_MODE` composition, not prompt-only instructions.

**Expected result**: Headless one-shot path works under read-only composition; docs match D3.

### Step 7: Automated suites

**Maps to**: AC-12, AC-13

1. Run:

   <!-- workflow-shell-contract: bash -->
   ```bash
   set -euo pipefail
   bash scripts/development-workflow/tests/test-resolve-reviewer-availability.sh
   bash scripts/development-workflow/tests/test-step7a-surface-consistency.sh
   bash scripts/development-workflow/tests/test-step7a-surface-consistency.sh --prove-plants
   bash scripts/development-workflow/tests/test-reviewer-preflight.sh
   ```

   The `--prove-plants` pass must include isolated FAIL/PASS cycles for the DSH
   D-1 supported-value plant and the D-6 headless read-only command plant (see
   `test-step7a-surface-consistency.sh` plants list).

2. If implementation touched sync-manifest inputs, run `check-sync-manifest-coverage.py` for this repo role and confirm no new gaps for touched paths.
3. Confirm `changelog.d/1891.added.dsh-runner-support.md` exists on the implementation PR (not required on the plan PR).

**Expected result**: Suites green; sync coverage clean; changelog fragment present on the implementation path.

#### Planted-violation proofs (DSH D-1 / D-6)

REVIEW.md requires demonstrated FAIL/PASS cycles at concrete locations for new
Step 7a surface checks. Run on the implementation PR head:

<!-- workflow-shell-contract: bash -->

```bash
set -euo pipefail
bash scripts/development-workflow/tests/test-step7a-surface-consistency.sh --prove-plants
```

**Demonstrated output** (2026-10-06, PR #1894 head `dd076536`; DSH-specific rows):

```text
PROOF 15 D-1: FAIL at docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md:1693
PROOF 15 D-1: PASS after repair
PROOF 16 D-6: FAIL at docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md:2038
PROOF 16 D-6: PASS after repair
39 isolated planted violations failed and repaired; source checkout untouched.
```

### Last Step: Validate & Shut Down

- Verify the checklist below.
- Allow the EXIT trap to restore `.ai-dev-workflow.local.yaml`.
- Remove `$SMOKE_STATE` only after confirming restore succeeded.

---

## Validation Checklist

- [ ] AC-1 / AC-1a: `dsh` accepted as draft runner and driving-session kind; unknowns still rejected; hosted values remain
- [ ] AC-2: reachable vs runtime-absent probe behavior observed under hermetic PATH (not the machine PATH)
- [ ] AC-3 / AC-3a / AC-4 / AC-5: Protocol 91 + YAML comments + dispatch rows
- [ ] AC-6: headless read-only composition documented (and exercised when `dsh` installed)
- [ ] AC-7 / AC-8 / AC-9 / AC-10: matrices, integration guide, model-config, failover
- [ ] AC-11: shipped default + README parse unchanged
- [ ] AC-12 / AC-13 / AC-14: tests, sync-manifest, changelog (implementation PR)

---

## Notes for Testers

- Under shipped `warn` policy, an absent `dsh` in a multi-runner override should reduce coverage rather than invent a harder DSH-only failure mode.
- Do not add `dsh` to the committed `.ai-dev-workflow.yaml` list body while testing — opt in only via the local override.
- `CLAUDE.md` and `GEMINI.md` are symlinks to `AGENTS.md`; verify the matrix once.

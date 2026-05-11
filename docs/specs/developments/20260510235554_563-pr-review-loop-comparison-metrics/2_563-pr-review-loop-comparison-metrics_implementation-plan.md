# PR Review Loop Comparison Mode and Platform Metrics Tracking — Implementation Plan

**Spec**: [1_563-pr-review-loop-comparison-metrics_specs.md](./1_563-pr-review-loop-comparison-metrics_specs.md)
**Smoke test runbook**: [docs/testing/workflow/563-pr-review-loop-comparison-metrics.smoke-test.md](../../../testing/workflow/563-pr-review-loop-comparison-metrics.smoke-test.md)

---

## Summary

**Approach**: Add a `--compare` flag to `pr-review-loop.sh` that disables the early `break` in the platform loop, runs every configured platform to completion, maps each platform's raw result to a normalized verdict (clean / blocking / advisory / timed out / unavailable), computes the overall exit code using the same first-blocking-platform logic as normal mode, and appends a single structured row to `docs/workflow/retro-metrics-platforms.md`. The meta-retrospective protocol (`06b-meta-retrospective-protocol.md`) receives a new platform evaluation step that reads the new metrics file.

**Estimated complexity**: M

**Rationale**: All platform-runner functions already exist and return structured key=value output. The primary change is control-flow (remove early break, collect verdicts) plus a new file-write step and a protocol update. No new external services or large data transformations are required.

**Dependencies**: structured-retro-metrics (#458) — closed and merged. No open dependencies.

---

## Verification Log

| Check | Command / query | Result |
|---|---|---|
| Repo revision | `git rev-parse --short HEAD` | `ddeb154` |
| pr-review-loop.sh line count | `wc -l scripts/development-workflow/pr-review-loop.sh` | 2681 lines |
| Existing platform loop location | `grep -n "for index in" scripts/development-workflow/pr-review-loop.sh` | line 2363 |
| Existing `break` in platform loop | `grep -n "break$" scripts/development-workflow/pr-review-loop.sh` | line 2414 |
| Argument-parsing block start | `grep -n 'while \[ "\$#"' scripts/development-workflow/pr-review-loop.sh` | line 2262 |
| Metrics file exists | `ls docs/workflow/retro-metrics-platforms.md` | not present (must be created) |
| Meta-retrospective protocol | `wc -l docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md` | 193 lines |
| Retrospective agent files | `grep -rl "06b-meta-retrospective" .claude/agents/ .cursor/agents/ .codex/skills/` | `.claude/agents/retrospective.md`, `.cursor/agents/retrospective.md`, `.codex/skills/workflow-retrospective/SKILL.md` |
| automated-reviewer-loop agent references pr-review-loop | `grep -c "pr-review-loop" .claude/agents/automated-reviewer-loop.md` | 0 (indirect via protocol 93) |

---

## Layer-by-Layer Changes

### Scripts / Shell

- [ ] `scripts/development-workflow/pr-review-loop.sh` — add `--compare` flag to argument parser; add `compare_mode=0` variable; in the platform loop, skip the `break` when `compare_mode=1` and a platform returns `needs_fixes` or `escalate`; collect per-platform verdicts into an associative array; after the loop, compute overall result from the stored verdicts (same first-blocking logic as normal mode); call `append_compare_metrics_row` to write the metrics row; emit `COMPARE_MODE=1` and per-platform verdict key=value lines in compare mode.

- [ ] `scripts/development-workflow/pr-review-loop.sh` — add `append_compare_metrics_row` helper function: accepts `pr_number`, `branch_name`, and per-platform verdicts; maps platform result values to the five normalized verdict tokens (`clean`, `blocking`, `advisory`, `timed out`, `unavailable`); appends one row to `docs/workflow/retro-metrics-platforms.md`; creates the file with header if absent; is a no-op when called in normal (non-compare) mode.

### Documentation / Protocol

- [ ] `docs/workflow/retro-metrics-platforms.md` — create (append-only); header section documents graduation criteria (BR-6); Markdown table with columns: `PR`, `Branch Type`, one column per platform in config order, `Overall Result`, `Block Was Real Bug`.

- [ ] `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md` — add a new Step 2b (Platform Evaluation) between existing Steps 2 and 3; the step reads `docs/workflow/retro-metrics-platforms.md`, computes per-platform exclusive-block counts and rates, compares against graduation criteria, explicitly flags when fewer than 30 runs have been logged.

### Agent / Skill Files

- [ ] `.claude/agents/retrospective.md` — add a bullet noting the platform evaluation step in the meta-retrospective (reference `docs/workflow/retro-metrics-platforms.md` and the graduation criteria check).

- [ ] `.cursor/agents/retrospective.md` — same update as `.claude/agents/retrospective.md`.

- [ ] `.codex/skills/workflow-retrospective/SKILL.md` — add the same platform evaluation note.

---

## Testing Strategy

**Test types**: Smoke / Manual

**Key scenarios to test**:

1. `--compare` flag runs all platforms to completion — maps to AC 1, 2
2. Overall exit code and `RESULT` in compare mode match normal mode for same verdicts — maps to AC 2
3. One row appended to `docs/workflow/retro-metrics-platforms.md` after each compare run — maps to AC 3
4. Metrics log header documents graduation criteria — maps to AC 4
5. Platform-exclusive block recorded correctly when one platform blocks and another is clean — maps to AC 5
6. Normal (non-compare) invocation is unaffected — maps to AC 6
7. Meta-retrospective protocol step reads the metrics file and reports rates — maps to AC 7
8. Fewer than 30 runs triggers explicit "data insufficient" message — maps to AC 8

**Smoke test runbook**: `docs/testing/workflow/563-pr-review-loop-comparison-metrics.smoke-test.md`

---

## Seed Data

No database seed data is required. The metrics file (`docs/workflow/retro-metrics-platforms.md`) is created by the implementation itself; the smoke test exercises it by running the script against a real or stubbed PR.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/06b-meta-retrospective-protocol.md` — add Step 2b (Platform Evaluation) as described in Layer-by-Layer Changes.
- [ ] `docs/workflow/retro-metrics-platforms.md` — new file created during implementation.

All other project docs in `docs/project/`, `docs/best-practices/`, and `AGENTS.md` are not affected by this feature — it modifies workflow tooling scripts and the meta-retrospective protocol only.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `append_compare_metrics_row` fails to create the file atomically if two concurrent compare runs target the same PR | Low | Low | File append is single-process (the lock guard at the top of `pr-review-loop.sh` prevents concurrent runs for the same PR number) |
| Branch-type detection regex in `append_compare_metrics_row` does not match an unusual branch name | Low | Low | Default to `other` as the branch type when no pattern matches; this is a metrics-only field and does not affect exit code |
| Meta-retrospective step reads a partially written row (file truncated mid-append) | Very low | Low | Shell `>>` append is atomic for lines shorter than PIPE_BUF (4 KB) on Linux/macOS; the row is short enough that this is safe |
| `--compare` used in normal orchestration inadvertently, slowing reviews | Low | Med | Flag is opt-in and not set in any default orchestration path; document intended usage in the `usage()` function |

---

## Code Samples

```bash
# Illustrative — adapt during implementation

# In argument parser (add after --post-final-summary block):
--compare)
  compare_mode=1
  shift
  ;;

# Verdict normalization helper (illustrative):
normalize_verdict() {
  local result="$1"
  case "$result" in
    clean)            printf 'clean' ;;
    needs_fixes)      printf 'blocking' ;;
    skipped)          printf 'clean' ;;   # skipped == no findings
    escalate)
      # distinguish timeout from unavailable via REASON if available
      printf 'timed out' ;;
    *)                printf 'unavailable' ;;
  esac
}

# append_compare_metrics_row (illustrative — adapt during implementation):
append_compare_metrics_row() {
  local pr_number="$1"
  local branch_name="$2"
  # remaining args: pairs of platform_name verdict_token
  local metrics_file
  metrics_file="$(workflow_repo_root)/docs/workflow/retro-metrics-platforms.md"

  local branch_type
  case "$branch_name" in
    feature/*)  branch_type="feature" ;;
    fix/*)      branch_type="fix" ;;
    refactor/*) branch_type="refactor" ;;
    hotfix/*)   branch_type="hotfix" ;;
    spec/*)     branch_type="spec" ;;
    implementation-plan/*) branch_type="plan" ;;
    *)          branch_type="other" ;;
  esac

  # Create file with header if absent
  if [ ! -f "$metrics_file" ]; then
    _write_metrics_header "$metrics_file"
  fi

  # Build row and append
  # ...
}
```

---

## Implementation Order

1. **Add `--compare` flag to argument parser in `pr-review-loop.sh`**

   In the `while [ "$#" -gt 0 ]` argument-parsing loop (around line 2262), add a case for `--compare`:

   ```bash
   --compare)
     compare_mode=1
     shift
     ;;
   ```

   Initialize `compare_mode=0` alongside the other variables near line 2253. Also add `compare_mode` to the `usage()` function's option list.

   Verify: run `./scripts/development-workflow/pr-review-loop.sh --help` and confirm `--compare` appears in the output.

2. **Refactor the platform loop to support compare mode**

   In the platform loop (starting at line 2363), wrap the `break` statement at line 2414 in a condition:

   ```bash
   needs_fixes|escalate)
     aggregate_result="$platform_result"
     aggregate_reason="$(kv_value_default REASON "$platform_output" "")"
     aggregate_output="$platform_output"
     aggregate_status=$platform_status
     if [ "$compare_mode" -eq 0 ]; then
       break   # normal mode: short-circuit on first block
     fi
     # compare mode: record verdict and continue
     ;;
   ```

   Also store per-platform verdicts in a parallel array (e.g., `compare_verdicts`) so `append_compare_metrics_row` can access them after the loop:

   ```bash
   compare_verdicts+=("${platform_name}=$(normalize_platform_verdict "$platform_result" "$platform_output")")
   ```

   Verify: add a local echo statement temporarily to confirm the loop runs all platforms in compare mode.

3. **Add `normalize_platform_verdict` helper function**

   Insert a new function before `run_platform_review`. It accepts a result token and the full platform output (for REASON extraction), and returns one of: `clean`, `blocking`, `advisory`, `timed out`, `unavailable`.

   Mapping table:
   - `clean` → `clean`
   - `needs_fixes` → `blocking`
   - `skipped` → `clean` (no findings; counts as clean for comparison purposes)
   - `escalate` + `REASON=timeout` (or similar) → `timed out`
   - `escalate` + other REASON → `unavailable`
   - `advisory` (if a future platform emits this) → `advisory`
   - anything else → `unavailable`

   Verify: unit-test by calling the function directly with each input and confirming expected outputs.

4. **Compute overall result in compare mode**

   After the platform loop, when `compare_mode=1`, recompute the aggregate result from the collected verdicts to enforce the "first blocking platform in config order governs" rule (BR-1). This ensures the compare-mode result is identical to what normal mode would have produced.

   Implementation: iterate `compare_verdicts` in order; the first entry whose verdict is `blocking` or `timed out` / `unavailable` (if that platform would have triggered an `escalate` exit in normal mode) sets the overall exit path.

   Verify: run a compare-mode test scenario where platform A is clean and platform B is blocking; confirm `RESULT=needs_fixes` and exit code 1.

5. **Add `append_compare_metrics_row` function and metrics file creation**

   Insert the function before the final `case "$aggregate_result"` block. Steps:

   a. Determine the metrics file path using `workflow_repo_root` (defined in `workflow-lib.sh` — returns the repo root path without changing CWD; already sourced at the top of `pr-review-loop.sh`): `metrics_file="$(workflow_repo_root)/docs/workflow/retro-metrics-platforms.md"`. Do NOT use `cd_workflow_repo_root` here — that changes the shell CWD, which would interfere with the script's own path assumptions.

   b. If the file does not exist, write the header:

   ```markdown
   # Platform Comparison Metrics Log

   This file is append-only. One row is appended per compare-mode reviewer loop run.
   Do not delete or rewrite existing rows. The "Block Was Real Bug?" column may be
   filled in manually after a run when post-hoc analysis determines whether a
   platform-exclusive blocking finding corresponded to a real code defect.

   ## Graduation Criteria

   A platform may be considered safe for removal when, across 30 or more consecutive
   compare-mode runs covering at least one run each of `fix`, `feature`, and `refactor`
   branch types, it has zero platform-exclusive blocking findings (runs where that
   platform blocked but at least one other configured platform was clean).

   Fewer than 30 runs is always insufficient data for a graduation decision.

   ## Metrics Table

   | PR | Branch Type | <platform columns> | Overall Result | Block Was Real Bug? |
   |---|---|...---|---|---|
   ```

   The platform column headers are derived from the configured platform list at run time. Because the configured set may change over time, new runs with different platform configurations append rows with the columns that match the header. If the configured platforms differ from the existing header, append a sub-header row marking the configuration change (see note in Step 5c).

   c. Append one row. The row format:

   ```
   | #<pr_number> | <branch_type> | <verdict-per-platform> | <overall_result> | |
   ```

   One column per platform in the configured order for this run. If the current run's platform list differs from the header (detected by comparing column count), prepend a separator row:

   ```
   | *(platforms changed: <new list>)* | | ... | | |
   ```

   d. Call `append_compare_metrics_row` at the end of the platform loop block when `compare_mode=1`.

   Verify: after a compare-mode run, confirm one new row exists in the file. Run a second time and confirm two rows exist with no corruption to the first.

6. **Emit compare-mode key=value output lines**

   After the platform loop, when `compare_mode=1`, emit:

   ```
   COMPARE_MODE=1
   COMPARE_VERDICT_<N>_PLATFORM=<platform_name>
   COMPARE_VERDICT_<N>_RESULT=<normalized_verdict>
   ```

   where `N` is 1-indexed in platform order. This makes compare-mode output machine-readable for future tooling.

   Verify: capture script output in compare mode and confirm `COMPARE_MODE=1` and all `COMPARE_VERDICT_*` lines appear.

7. **Create `docs/workflow/retro-metrics-platforms.md`**

   The file is created automatically by `append_compare_metrics_row` if absent. However, to make it part of this PR (so reviewers can see the graduation criteria header), create the empty file with just the header (no data rows) as part of the implementation commit.

   Verify: confirm the file exists at `docs/workflow/retro-metrics-platforms.md` with the header section and empty table.

8. **Add Step 2b (Platform Evaluation) to `06b-meta-retrospective-protocol.md`**

   Insert a new step between existing Step 2 (Trend Analysis) and Step 3 (Classify Prior Action Items). The new step:

   a. Reads `docs/workflow/retro-metrics-platforms.md`.
   b. If the file does not exist or has zero data rows: state "No compare-mode runs logged yet — platform evaluation skipped."
   c. If fewer than 30 rows are present: state explicitly "Only N compare-mode runs logged — fewer than 30 runs required for a graduation decision. Data is insufficient."
   d. Computes per-platform exclusive-block rate: for each platform, count rows where that platform is `blocking` AND at least one other platform is `clean`. Divide by total rows to get the rate.
   e. Compares against the graduation criteria (zero exclusive blocks across ≥ 30 runs covering fix, feature, and refactor branch types).
   f. Reports one of three outcomes per platform: "safe to evaluate removal" (graduation criteria met), "data insufficient" (< 30 runs), or "not yet ready" (exclusive blocks found).

   Verify: read the updated protocol and confirm Step 2b appears with all required sub-steps.

9. **Update retrospective agent and skill files**

   In `.claude/agents/retrospective.md`, `.cursor/agents/retrospective.md`, and `.codex/skills/workflow-retrospective/SKILL.md`, add a bullet under the meta-retrospective guidance line noting that the meta-retrospective now includes a platform evaluation step that reads `docs/workflow/retro-metrics-platforms.md` and applies graduation criteria.

   Verify: open each updated file and confirm the new bullet is present.

10. **Run smoke test runbook**

    Follow `docs/testing/workflow/563-pr-review-loop-comparison-metrics.smoke-test.md` to verify all acceptance criteria manually.

11. **Update project docs per Documentation Updates section above**

    Both updates listed in the Documentation Updates section (Step 2b addition to `06b-meta-retrospective-protocol.md` and the new `docs/workflow/retro-metrics-platforms.md` header file) are performed in the **implementation PR** (not this plan PR). This step is a reminder for the developer to execute those changes as part of implementation.

12. **Update `CHANGELOG.md` under `[Unreleased]`**

    ```
    - **Add comparison mode and platform metrics tracking to pr-review-loop.sh** (#563): adds a `--compare` flag that runs all configured review platforms to completion, records per-platform verdicts, appends a structured row to `docs/workflow/retro-metrics-platforms.md`, and adds a platform evaluation step to the meta-retrospective protocol.
    ```

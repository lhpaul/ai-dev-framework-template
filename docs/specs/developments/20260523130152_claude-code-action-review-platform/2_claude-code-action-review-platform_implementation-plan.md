# Claude Code Action Review Platform — Implementation Plan

**Spec**: [1_claude-code-action-review-platform_specs.md](./1_claude-code-action-review-platform_specs.md)
**Smoke test runbook**: [docs/testing/workflow/705-claude-code-action-review-platform.smoke-test.md](../../../../docs/testing/workflow/705-claude-code-action-review-platform.smoke-test.md)

---

## Summary

**Approach**: Add a new `run_claude_code_action_review()` function to `scripts/development-workflow/pr-review-loop.sh` following the same three-phase pattern as `run_codex_github_review()`, and create a new companion script `scripts/development-workflow/claude-code-action-reviewer.sh` that dispatches a GitHub Actions workflow run, polls for completion via the Actions API, and returns an exit code based on the run result. The `run_platform_review()` dispatch table and `bot_login_for_platform()` function in `pr-review-loop.sh` are updated to recognize `claude-code-action` as a valid platform name.

**Estimated complexity**: M

**Rationale**: The implementation mirrors the codex-github reviewer path closely. The primary difference is the trigger mechanism: instead of posting a PR comment to prompt a bot, the script dispatches a `workflow_dispatch` event and tracks the resulting Actions run by polling `GET /repos/{owner}/{repo}/actions/runs`. This requires a new standalone reviewer script on the same model as `codex-github-reviewer.sh`, plus a small addition to `pr-review-loop.sh`. No protocol files, agent definitions, or external config files change for this item (doc updates are covered by sibling items #707 and #708).

**Dependencies**: None (sibling items #706, #707, #708 may be developed in parallel; this item has no runtime dependency on them, as the feature is gated by the platform being listed in `.ai-dev-workflow.yaml`).

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `124d13b` |
| `run_codex_github_review` function location | `grep -n "run_codex_github_review" scripts/development-workflow/pr-review-loop.sh` | Lines 619, 682, 2932 |
| `run_platform_review` dispatch table location | `grep -n "run_platform_review\|codex-github)" scripts/development-workflow/pr-review-loop.sh` | Dispatch table at line 2911, codex-github case at 2931 |
| `bot_login_for_platform` location | `grep -n "bot_login_for_platform\|codex-github)" scripts/development-workflow/pr-review-loop.sh` | Function at line 2780, codex-github case at 2790 |
| Companion script exists | `ls scripts/development-workflow/codex-github-reviewer.sh` | File present (24.3 KB) |
| claude-code-action not yet present | `grep -c "claude-code-action" scripts/development-workflow/pr-review-loop.sh` | `0` (not yet implemented) |
| Smoke test naming convention | `ls docs/testing/workflow/` | Files follow `{issue}-{slug}.smoke-test.md` pattern |

---

## Layer-by-Layer Changes

### Shared Packages / Libraries

- [ ] **`scripts/development-workflow/pr-review-loop.sh`** — add `run_claude_code_action_review()` function following the `run_codex_github_review()` pattern (Phase 1: pre-dispatch thread check; Phase 2: delegate to `claude-code-action-reviewer.sh`; exit-code-to-kv mapping identical to codex-github).
- [ ] **`scripts/development-workflow/pr-review-loop.sh`** — add `claude-code-action)` case to `bot_login_for_platform()` function (line ~2786), returning the configurable bot login (default: `claude[bot]`, overridable by `CLAUDE_CODE_ACTION_BOT_LOGIN` env var).
- [ ] **`scripts/development-workflow/pr-review-loop.sh`** — add `claude-code-action)` case to the `run_platform_review()` dispatch table (line ~2931), calling `run_claude_code_action_review()` with the same four positional arguments.
- [ ] **`scripts/development-workflow/claude-code-action-reviewer.sh`** — new script: dispatches the Claude Code Action GHA workflow, polls for run completion, inspects PR review threads, and exits with the same three exit codes used by `codex-github-reviewer.sh` (0 = APPROVED, 1 = NEEDS_REVISION, 2 = TIMED_OUT).

### Infrastructure / Configuration

- [ ] **`.ai-dev-workflow.yaml` comment block** — no content change required for this item; the `Supported today by pr-review-loop.sh:` comment line (line 28) will be updated by sibling item #708 to list `claude-code-action`. This item only adds the script-level support.

---

## `claude-code-action-reviewer.sh` Design

### Purpose and exit-code contract

The script follows the same contract as `codex-github-reviewer.sh`:

- Exit 0 — APPROVED (Actions run completed, no new blocking review threads posted by the bot)
- Exit 1 — NEEDS_REVISION (Actions run completed, bot posted new blocking review threads)
- Exit 2 — TIMED_OUT (Actions run did not complete within `MAX_WAIT`, dispatch failed, or workflow file absent)

### Arguments and options

```
claude-code-action-reviewer.sh <pr_number> <owner> <repo> [options]

Options:
  --workflow-file <name>   Filename of the GHA workflow to dispatch (default: claude-code-review.yml)
                           Also overridable via CLAUDE_CODE_ACTION_WORKFLOW_FILE env var.
  --bot-login     <login>  GitHub login of the Claude Code Action bot account (default: claude[bot])
                           Also overridable via CLAUDE_CODE_ACTION_BOT_LOGIN env var.
  --poll-interval <secs>   Seconds between polling attempts. Default: 30
  --max-wait      <secs>   Maximum total wait for Actions run to complete. Default: 600
```

### Implementation phases

**Phase 0 — Input validation**: Validate `pr_number` (positive integer), `owner`/`repo` (alphanumeric plus `-._`), numeric options. Same pattern as `codex-github-reviewer.sh`.

**Phase 1 — Dispatch workflow**: Call `gh api repos/{owner}/{repo}/actions/workflows/{workflow_file}/dispatches --method POST --field ref={base_branch} --field inputs[pr_number]={pr_number}`. Capture the `dispatch_time` as the server-assigned timestamp by recording the time immediately before dispatch (ISO 8601). If the API call fails (404 = workflow file absent, 422 = validation error, other = generic error), emit `VERDICT: TIMED_OUT` and exit 2. Store the `dispatch_time` to scope subsequent run polling.

**Phase 2 — Poll for run completion**: After dispatch, poll `GET /repos/{owner}/{repo}/actions/runs?event=workflow_dispatch&created=>={dispatch_time}` at `POLL_INTERVAL` intervals until a run matching `workflow_file` and triggered after `dispatch_time` reaches a terminal status (`completed`, `failure`, `cancelled`, `skipped`, `timed_out`, `startup_failure`). If `MAX_WAIT` is exhausted before the run completes, emit `VERDICT: TIMED_OUT` and exit 2. Capture the run's `conclusion` and `html_url` for logging.

**Phase 3 — Parse result**: If the run's conclusion is not `success`, emit `VERDICT: TIMED_OUT` with the run URL for traceability and exit 2 (the spec calls this `escalate` with reason `timeout`; the caller maps exit 2 to that signal). If conclusion is `success`, the reviewer loop will inspect PR review threads (Phase 1 of `run_claude_code_action_review()` is already run before dispatch; after the run completes, a post-dispatch thread check is performed against the bot login). Exit 0 (APPROVED) when no new blocking threads are found; exit 1 (NEEDS_REVISION) otherwise.

### Key differences from `codex-github-reviewer.sh`

| Aspect | codex-github | claude-code-action |
| --- | --- | --- |
| Trigger mechanism | Post PR comment (`@codex review`) | `gh api workflow_dispatch` |
| Response detection | Poll PR comments + PR reviews for bot comment | Poll GHA run status; check PR review threads post-run |
| Idempotency guard | Check for existing trigger comment with SHA | Check for existing completed run after `dispatch_time` with matching workflow name |
| Retrigger support | `--max-retriggers` flag | Not included in MVP (single dispatch attempt; `escalate` on timeout per spec Out of Scope) |

### `run_claude_code_action_review()` in `pr-review-loop.sh`

This function wraps the companion script with the same three-phase pattern used by `run_codex_github_review()`:

1. **Pre-dispatch thread check** (`check_unresolved_threads`): If the bot already has unresolved threads on the PR, return `needs_fixes` immediately without dispatching a new run. This is identical to the codex-github Phase 1.
2. **Delegate to companion script**: Call `claude-code-action-reviewer.sh` with `--poll-interval`, `--max-wait`, and `--bot-login`. Capture exit code.
3. **Map exit code to kv output**:
   - Exit 0 → `RESULT=clean` + standard kv block (no retrigger, no post-dispatch thread recheck needed — companion script already verified no blocking threads)
   - Exit 1 → `RESULT=needs_fixes` + re-run `check_unresolved_threads` to get accurate `BLOCKING_COUNT` (same pattern as codex-github)
   - Exit 2 → `RESULT=escalate`, `REASON=timeout` (true timeout: run started but did not complete within `MAX_WAIT`)
   - Exit 3 → `RESULT=escalate`, `REASON=unavailable` (dispatch failure: workflow file absent, 404, or permissions error before the run could start)

---

## Testing Strategy

**Test types**: Smoke / Manual

**Key scenarios to test**:

1. **Happy path (clean)**: `claude-code-action` listed in `.ai-dev-workflow.yaml` `platforms`; bot has no existing unresolved threads; dispatched Actions run completes with `success`; bot posts no blocking review threads → `RESULT=clean` (AC-1, AC-2)
2. **Pre-existing threads (no dispatch)**: Bot has unresolved threads before the loop runs → `RESULT=needs_fixes`, `BLOCKING_COUNT` equals count of unresolved threads, no new Actions run dispatched (AC-3)
3. **New blocking threads**: Actions run completes successfully; bot posts blocking review threads → `RESULT=needs_fixes`, `BLOCKING_COUNT` equals count of new threads (AC-4)
4. **Timeout**: Actions run does not complete within `MAX_WAIT` → `RESULT=escalate`, `REASON=timeout` (AC-5)
5. **Workflow file absent**: `gh workflow dispatch` receives 404 → `RESULT=escalate`, `REASON=unavailable` (AC-6; companion script exits 3, mapped to `REASON=unavailable` to distinguish from a true run timeout)
6. **Configurable bot login**: `CLAUDE_CODE_ACTION_BOT_LOGIN` set to custom value; loop uses that login for thread identification (AC-7)
7. **Phase after clean**: `claude-code-action` listed in `phase_after_clean`; loop skips it until pre-clean platforms report clean (AC-8)
8. **kv output format**: Compare kv keys emitted for `claude-code-action` with those emitted for `codex-github`; confirm identical set (AC-9)
9. **End-to-end via `pr-review-loop.sh`**: `claude-code-action` is listed in `.ai-dev-workflow.yaml` `platforms`; the full loop invocation emits `PLATFORM=claude-code-action` with the correct `RESULT` token (AC-1)

**Smoke test runbook**: `docs/testing/workflow/705-claude-code-action-review-platform.smoke-test.md`

---

## Seed Data

Not applicable. No database or seed data changes.

---

## Implementation Order

### Step 1: Create `scripts/development-workflow/claude-code-action-reviewer.sh`

Create the new reviewer script at `scripts/development-workflow/claude-code-action-reviewer.sh`. Model it after `codex-github-reviewer.sh` for structure (argument parsing, validation, auth check), but replace the trigger-comment mechanism with a `workflow_dispatch` call and replace the comment-polling mechanism with run-status polling.

Key implementation details:

- Argument parsing: positional args `<pr_number> <owner> <repo>`, then flags `--workflow-file`, `--bot-login`, `--poll-interval`, `--max-wait`. Provide env var overrides for `--workflow-file` (`CLAUDE_CODE_ACTION_WORKFLOW_FILE`, default `claude-code-review.yml`) and `--bot-login` (`CLAUDE_CODE_ACTION_BOT_LOGIN`, default `claude[bot]`).
- Input validation: validate `pr_number` as a positive integer; validate `owner`/`repo` as alphanumeric-plus-`-._`; validate `poll_interval` and `max_wait` as positive integers. Exit 2 with a clear error message on validation failure.
- Pre-flight: `gh auth status` check (same as codex-github-reviewer.sh pattern).
- Resolve PR base branch for the workflow dispatch `ref` parameter: `gh pr view $PR_NUMBER --repo $OWNER/$REPO --json baseRefName --jq '.baseRefName'`.
- Dispatch: `gh api repos/$OWNER/$REPO/actions/workflows/$WORKFLOW_FILE/dispatches --method POST --field ref=$BASE_REF --field inputs[pr_number]=$PR_NUMBER`. On non-zero exit, check whether the error body contains "workflow was not found" (404) vs. other errors and emit appropriate `VERDICT: TIMED_OUT` with `reason=unavailable` or `reason=dispatch_error`.
- Record `dispatch_time` immediately before the dispatch call (use `date -u +%Y-%m-%dT%H:%M:%SZ`).
- Poll loop: every `POLL_INTERVAL` seconds, call `gh api repos/$OWNER/$REPO/actions/runs --jq '[.workflow_runs[] | select(.path | endswith($wf)) | select(.created_at >= $dispatch_time)] | first'`. When a run reaches a terminal status (`completed`), inspect `conclusion`. If not `success`, exit 2 with `VERDICT: TIMED_OUT`. If `success`, proceed to thread check.
- Thread check (post-run): after a successful run, query `gh api repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews` for reviews posted by `BOT_LOGIN` after `dispatch_time`. If any have `state=CHANGES_REQUESTED` or blocking body patterns, exit 1 with `VERDICT: NEEDS_REVISION`. Otherwise exit 0 with `VERDICT: APPROVED`.
- Make the file executable: `chmod +x scripts/development-workflow/claude-code-action-reviewer.sh`.

Verification: run `bash -n scripts/development-workflow/claude-code-action-reviewer.sh` to confirm no syntax errors; run `./scripts/development-workflow/claude-code-action-reviewer.sh --help` (or with no args) to confirm the usage message prints and exits 2.

### Step 2: Add `run_claude_code_action_review()` to `pr-review-loop.sh`

In `scripts/development-workflow/pr-review-loop.sh`, add the new function immediately after `run_codex_github_review()` (after line 734). The function signature and structure mirror `run_codex_github_review()`:

```bash
run_claude_code_action_review() {
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="claude-code-action"
  local bot_login="${CLAUDE_CODE_ACTION_BOT_LOGIN:-claude[bot]}"
  local graphql_bot_login="${bot_login%\[bot\]}"
  local repo
  local reviewer_script
  local script_exit=0
  local thread_check_output=""
  local thread_check_status=0
  local unresolved_count=0

  require_gh
  cd_workflow_repo_root
  repo="$(repo_slug)"

  # Phase 1: Check for existing unresolved review threads from the Claude Code Action bot
  set +e
  thread_check_output="$(check_unresolved_threads "$pr_number" "$repo" "$graphql_bot_login")"
  thread_check_status=$?
  set -e
  if [ "$thread_check_status" -eq 0 ]; then
    unresolved_count="$thread_check_output"
  fi

  if [ "$unresolved_count" -gt 0 ]; then
    print_kv RESULT needs_fixes
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv REASON existing_findings
    print_kv COMMENT_COUNT "$unresolved_count"
    print_kv BLOCKING_COUNT "$unresolved_count"
    print_kv SUGGESTION_COUNT 0
    return 1
  fi

  # Phase 2: Dispatch the Claude Code Action workflow and wait for completion
  reviewer_script="$(workflow_repo_root)/scripts/development-workflow/claude-code-action-reviewer.sh"

  local owner repo_name
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

  local effective_poll_interval
  effective_poll_interval="$poll_interval"
  if [ "$effective_poll_interval" -gt "$max_wait" ]; then
    effective_poll_interval="$max_wait"
  fi
  set +e
  "$reviewer_script" "$pr_number" "$owner" "$repo_name" \
    --bot-login "$bot_login" \
    --poll-interval "$effective_poll_interval" \
    --max-wait "$max_wait" >/dev/null 2>&1
  script_exit=$?
  set -e

  case "$script_exit" in
    0)
      print_kv RESULT clean
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 0
      ;;
    1)
      unresolved_count=0
      set +e
      thread_check_output="$(check_unresolved_threads "$pr_number" "$repo" "$graphql_bot_login")"
      thread_check_status=$?
      set -e
      if [ "$thread_check_status" -eq 0 ]; then
        unresolved_count="$thread_check_output"
      fi
      [ "$unresolved_count" -eq 0 ] && unresolved_count=1

      print_kv RESULT needs_fixes
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REASON unresolved_review_threads
      print_kv COMMENT_COUNT "$unresolved_count"
      print_kv BLOCKING_COUNT "$unresolved_count"
      print_kv SUGGESTION_COUNT 0
      return 1
      ;;
    2)
      print_kv RESULT escalate
      print_kv REASON timeout
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      return 2
      ;;
    *)
      print_kv RESULT escalate
      print_kv REASON unavailable
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      return 2
      ;;
  esac
}
```

Verification: run `bash -n scripts/development-workflow/pr-review-loop.sh` to confirm no syntax errors.

### Step 3: Update `bot_login_for_platform()` in `pr-review-loop.sh`

In the `bot_login_for_platform()` function (around line 2786), add the `claude-code-action` case before the catch-all `*)`:

```bash
claude-code-action) printf '%s\n' "${CLAUDE_CODE_ACTION_BOT_LOGIN:-claude[bot]}" ;;
```

Verification: run `bash -n scripts/development-workflow/pr-review-loop.sh` after the edit.

### Step 4: Update `run_platform_review()` dispatch table in `pr-review-loop.sh`

In the `run_platform_review()` function (around line 2931), add the `claude-code-action` case immediately after the `codex-github)` case:

```bash
claude-code-action)
  run_claude_code_action_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
  ;;
```

Verification: run `bash -n scripts/development-workflow/pr-review-loop.sh` after the edit.

### Step 5: Update the `.ai-dev-workflow.yaml` supported platforms comment (header comment only)

In `.ai-dev-workflow.yaml`, update the `Supported today by pr-review-loop.sh:` comment (line 28) to include `claude-code-action`:

Before:
```yaml
  # Supported today by pr-review-loop.sh: greptile, devin, coderabbit, pr-agent, codex-github
```

After:
```yaml
  # Supported today by pr-review-loop.sh: greptile, devin, coderabbit, pr-agent, codex-github, claude-code-action
```

Note: This step updates only the comment; it does not add `claude-code-action` to the active `platforms` list (that is covered by sibling item #708). Updating the comment here is appropriate because this item introduces the script-level support.

Verification: run `git diff .ai-dev-workflow.yaml` and confirm only the comment line changed.

### Step 6: Write the smoke test runbook

Create `docs/testing/workflow/705-claude-code-action-review-platform.smoke-test.md` using the smoke test runbook template. Cover the nine test scenarios listed in the Testing Strategy section above (AC-1 through AC-9 from the spec).

Verification:

```bash
markdownlint-cli2 "docs/testing/workflow/705-claude-code-action-review-platform.smoke-test.md"
python3 scripts/lint/markdown-heuristic-lint.py "docs/testing/workflow/705-claude-code-action-review-platform.smoke-test.md"
```

Confirm both commands exit 0 with no errors.

### Step 7: Commit

```bash
git add \
  scripts/development-workflow/claude-code-action-reviewer.sh \
  scripts/development-workflow/pr-review-loop.sh \
  .ai-dev-workflow.yaml \
  docs/specs/developments/20260523130152_claude-code-action-review-platform/2_claude-code-action-review-platform_implementation-plan.md \
  docs/testing/workflow/705-claude-code-action-review-platform.smoke-test.md
git commit -m "feat(pr-review-loop): add claude-code-action review platform (#705)"
```

Note: CHANGELOG is intentionally omitted here. CHANGELOG entries for feature PRs targeting `develop-claude-review-platform` (integration branch) will be added when the integration branch merges to `develop`. Individual sub-item plan PRs targeting `develop-claude-review-platform` are exempt per the integration-branch batching convention — the sibling item #708 covers the CHANGELOG entry for this feature group.

---

## Documentation Updates Required After Implementation

- None for this item. Documentation updates (`docs/workflow/development-workflow/integrations/`, `.ai-dev-workflow.yaml` schema comment expansion, and CHANGELOG) are covered by sibling items #707 and #708.

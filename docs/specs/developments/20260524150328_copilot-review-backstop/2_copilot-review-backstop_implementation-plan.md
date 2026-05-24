# GitHub Copilot Code Review Backstop — Implementation Plan

**Spec**: [`1_copilot-review-backstop_specs.md`](./1_copilot-review-backstop_specs.md)
**Smoke test runbook**: [`../../../testing/workflow/709-copilot-review-backstop.smoke-test.md`](../../../testing/workflow/709-copilot-review-backstop.smoke-test.md)

---

## Summary

**Approach**: Add a `run_copilot_review()` platform function inline in
`pr-review-loop.sh` that requests Copilot as a reviewer via the GitHub Pulls
API, polls the pull-request reviews endpoint until Copilot posts its verdict,
and maps the review state to the standard exit-code contract (0 = clean,
1 = needs\_fixes, 2 = escalate). No companion script is required; the entire
logic fits within the existing platform-function pattern used by `codex-github`
and `claude-code-action`. A new integration guide is added under
`docs/workflow/development-workflow/integrations/`, and the `.ai-dev-workflow.yaml`
template comment listing supported platforms is updated to include `copilot`.

**Estimated complexity**: S

**Rationale**: The change is scoped to three files: one script
(`pr-review-loop.sh`) for the platform function and dispatch registration, one
new documentation file (the Copilot integration guide), and one minor YAML
comment update. There is no new companion script, no database changes, and no
frontend work. The GitHub Copilot reviewer API is the same reviewer-request
mechanism used for human reviewers; no special SDK is required. The HARNESS_MODE
unit test infrastructure is already in place and follows an established pattern.

**Dependencies**: The `develop-claude-review-platform` integration branch (which
contains sibling items #705–#708 for Claude Code Action) is the base branch for
this item. No specific sibling item must be merged before this plan can be
implemented — the `run_copilot_review()` function is independent of the
`run_claude_code_action_review()` function.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `d6d5f86` |
| Existing platform functions in `pr-review-loop.sh` | `grep -c "^run_.*_review()" scripts/development-workflow/pr-review-loop.sh` | 6 functions: `run_greptile_review`, `run_codex_github_review`, `run_claude_code_action_review`, `run_devin_review`, `run_pr_agent_review`, `run_coderabbit_review` |
| `run_platform_review` dispatch cases | `grep -A2 "case.*platform" scripts/development-workflow/pr-review-loop.sh \| grep -v "^--"` | 6 cases: `greptile`, `devin`, `coderabbit`, `pr-agent`, `codex-github`, `claude-code-action` |
| `bot_login_for_platform` cases | `grep -A8 "^bot_login_for_platform" scripts/development-workflow/pr-review-loop.sh` | 6 platform entries; `copilot` absent — must be added |
| Existing integration guides | `ls docs/workflow/development-workflow/integrations/` | 13 files; `copilot.md` absent — must be created |
| Supported platforms comment in `.ai-dev-workflow.yaml` | `grep "Supported today" .ai-dev-workflow.yaml` | Lists `greptile, devin, coderabbit, pr-agent, codex-github` — `copilot` and `claude-code-action` absent; must add `copilot` |
| HARNESS_MODE test file | `ls scripts/development-workflow/tests/test-pr-review-loop.sh` | Present — used for AC-8 unit tests |
| `pr-review-loop.sh` line count | `wc -l scripts/development-workflow/pr-review-loop.sh` | 4022 lines |

---

## Layer-by-Layer Changes

### Script Layer (`scripts/development-workflow/`)

- [ ] **`pr-review-loop.sh` — add `run_copilot_review()` function**: Insert the
  new function after `run_claude_code_action_review()` (after line 881) and
  before `run_devin_review()`. The function follows the same four-argument
  signature (`pr_number`, `branch_name`, `poll_interval`, `max_wait`) and
  exit-code contract (0 = clean, 1 = needs\_fixes, 2 = escalate) as every
  other platform function. See Code Samples section for the illustrative
  implementation.

- [ ] **`pr-review-loop.sh` — add `copilot` to `run_platform_review()`**: In
  the `case "$platform" in` block inside `run_platform_review()`, add a
  `copilot)` case that calls `run_copilot_review "$pr_number" "$branch_name"
  "$poll_interval" "$max_wait"`. Insert it after the `claude-code-action)` case
  and before the `*)` fallback (approximately line 3088 on the integration
  branch after the `claude-code-action` case is inserted).

- [ ] **`pr-review-loop.sh` — add `copilot` to `bot_login_for_platform()`**: In
  the `case "$1" in` block inside `bot_login_for_platform()`, add a `copilot)`
  case that returns the bot login. Copilot posts reviews as
  `copilot-pull-request-reviewer[bot]` on GitHub.com (verify at runtime via
  `COPILOT_BOT_LOGIN` env var override for flexibility). Insert after the
  `claude-code-action)` case.

### Configuration Layer

- [ ] **`.ai-dev-workflow.yaml` — update `Supported today` comment**: The
  comment on the `platforms:` key currently lists
  `greptile, devin, coderabbit, pr-agent, codex-github`. Update it to also
  include `claude-code-action, copilot` (two new entries added by the
  integration branch items). Add a comment block for `copilot` analogous to the
  existing `codex-github` configurable options block, noting that Copilot code
  review requires an active Copilot seat or the Copilot for Pull Requests feature
  enabled on the repository, and that `COPILOT_BOT_LOGIN` can override the
  default bot login.

### Documentation Layer

- [ ] **`docs/workflow/development-workflow/integrations/copilot.md` — create**:
  New integration guide following the same structure as `greptile.md` and
  `claude-code-action.md`. Must be clearly marked optional and must describe:
  - What Copilot code review adds (lightweight secondary review at no extra cost
    when a Copilot seat is active)
  - Prerequisites (active GitHub Copilot seat or Copilot for Pull Requests feature
    on the repository)
  - Setup instructions (add `copilot` to `review.platforms` in
    `.ai-dev-workflow.yaml`)
  - Step 7 implementation details: how `pr-review-loop.sh` requests Copilot as a
    reviewer via the GitHub Reviews API and polls the reviews endpoint
  - The `COPILOT_BOT_LOGIN` env var override for non-standard bot login names
  - Known limitations (GHES not supported; Copilot review instructions not
    configurable via `.ai-dev-workflow.yaml`)

### Test Layer (`scripts/development-workflow/tests/`)

- [ ] **`test-pr-review-loop.sh` — add HARNESS_MODE unit tests for Copilot
  platform (AC-8)**: Add a new test area section (e.g., "Area N: Copilot
  platform function"). The tests must cover at minimum:
  - **Clean path**: mock `gh` returning a `APPROVED` review state → verify
    `run_copilot_review` exits 0 and emits `RESULT=clean`, `BLOCKING_COUNT=0`
  - **Needs-fixes path**: mock `gh` returning a `CHANGES_REQUESTED` review
    state → verify exit 1 and `RESULT=needs_fixes`, `BLOCKING_COUNT>=1`
  - **Escalate (timeout) path**: mock `gh` returning no Copilot review within
    the wait window → verify exit 2 and `RESULT=escalate`,
    `REASON=timeout` or `REASON=unavailable`

---

## Testing Strategy

**Test types**: Unit (HARNESS_MODE), Manual / smoke

**Key scenarios to test**:

1. `copilot` recognized by `run_platform_review` — no `unsupported-platform`
   fallback (maps to AC-1, AC-5)
2. `CHANGES_REQUESTED` review from Copilot → exit 1, `RESULT=needs_fixes`,
   `BLOCKING_COUNT>=1` (maps to AC-2)
3. `APPROVED` review from Copilot → exit 0, `RESULT=clean`, `BLOCKING_COUNT=0`
   (maps to AC-3)
4. Copilot feature absent / no review posted within timeout → exit 2,
   `RESULT=escalate`, `REASON=unavailable` or `REASON=timeout` (maps to AC-4)
5. Repository without `copilot` in `review.platforms` — no behavior change
   (maps to AC-5)
6. Integration guide file present and correct prerequisites described (maps
   to AC-6)
7. `.ai-dev-workflow.yaml` comment updated to include `copilot` (maps to AC-7)
8. HARNESS_MODE unit tests pass for clean, needs-fixes, and escalate paths
   (maps to AC-8)

**Smoke test runbook**: `docs/testing/workflow/709-copilot-review-backstop.smoke-test.md`

---

## Seed Data

None — shell script, documentation, and test additions only. No application
data requirements.

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/integrations/copilot.md` — Created as
  primary documentation deliverable (see Layer-by-Layer Changes above)
- [ ] `.ai-dev-workflow.yaml` — Updated `Supported today` comment (advisory
  documentation in a config file — see Layer-by-Layer Changes above)

No updates to `docs/project/`, `docs/best-practices/`, or `AGENTS.md` are
required. The change adds a new optional review platform; it does not change any
existing workflow conventions.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Copilot bot login name differs across GitHub plans or changes in future | Med | Low | Accept `COPILOT_BOT_LOGIN` env var override (same pattern as `CODEX_GITHUB_BOT_LOGIN`, `CLAUDE_CODE_ACTION_BOT_LOGIN`); document in integration guide |
| Copilot does not post a formal GitHub Review for all PR types (may post comment instead) | Med | Med | Poll both reviews endpoint and PR comments in the function; treat any `APPROVED` signal from either source as clean; fall back to timeout/unavailable if neither posts within `max_wait` |
| GitHub Copilot reviewer request API endpoint or behavior changes | Low | Med | Integration guide documents the current mechanism; the function is self-contained and can be updated independently without protocol changes |
| Copilot review request silently ignored (no error, no review posted) | Med | Low | Timeout path already handles this; `REASON=unavailable` or `REASON=timeout` is returned so the loop can apply the configured unavailability policy |
| HARNESS_MODE unit tests tightly coupled to internal function shape | Low | Low | Follow the existing pattern in `test-pr-review-loop.sh` (mock `gh` output, source the script, call the function directly) |

---

## Code Samples

> All samples below are illustrative — adapt during implementation.

### `run_copilot_review()` in `pr-review-loop.sh` (illustrative)

```bash
# Illustrative — adapt during implementation

run_copilot_review() {
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="copilot"
  local bot_login="${COPILOT_BOT_LOGIN:-copilot-pull-request-reviewer[bot]}"
  local repo
  local elapsed=0
  local review_state=""
  local exit_code=2

  require_gh
  cd_workflow_repo_root
  repo="$(repo_slug)"

  local owner repo_name
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

  # Step 1: Request Copilot as a reviewer (idempotent — request again if not
  # already requested; GitHub silently deduplicates reviewer requests).
  set +e
  gh api "repos/$owner/$repo_name/pulls/$pr_number/requested_reviewers" \
    --method POST \
    --raw-field '{"reviewers":["copilot"]}' > /dev/null 2>&1
  local request_exit=$?
  set -e

  if [ "$request_exit" -ne 0 ]; then
    # Request failed — Copilot feature likely not available on this repository.
    print_kv RESULT escalate
    print_kv REASON unavailable
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    return 2
  fi

  # Step 2: Poll the pull-request reviews endpoint until Copilot posts its review.
  local effective_poll_interval="$poll_interval"
  if [ "$effective_poll_interval" -gt "$max_wait" ]; then
    effective_poll_interval="$max_wait"
  fi

  while [ "$elapsed" -lt "$max_wait" ]; do
    set +e
    review_state="$(gh api "repos/$owner/$repo_name/pulls/$pr_number/reviews" \
      --jq "[.[] | select(.user.login == \"$bot_login\" or .user.login == \"${bot_login%\[bot\]}\") | .state] | last // empty" \
      2>/dev/null)"
    set -e

    case "$review_state" in
      APPROVED)
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
      CHANGES_REQUESTED)
        print_kv RESULT needs_fixes
        print_kv PLATFORM "$platform"
        print_kv PR_NUMBER "$pr_number"
        print_kv BRANCH "$branch_name"
        print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
        print_kv REASON changes_requested
        print_kv COMMENT_COUNT 1
        print_kv BLOCKING_COUNT 1
        print_kv SUGGESTION_COUNT 0
        return 1
        ;;
      COMMENTED)
        # Non-blocking comment only — treat as clean.
        print_kv RESULT clean
        print_kv PLATFORM "$platform"
        print_kv PR_NUMBER "$pr_number"
        print_kv BRANCH "$branch_name"
        print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
        print_kv COMMENT_COUNT 1
        print_kv BLOCKING_COUNT 0
        print_kv SUGGESTION_COUNT 1
        return 0
        ;;
    esac

    _interruptible_sleep "$effective_poll_interval"
    elapsed=$(( elapsed + effective_poll_interval ))
  done

  # Timeout — no review posted within max_wait.
  print_kv RESULT escalate
  print_kv REASON timeout
  print_kv PLATFORM "$platform"
  print_kv PR_NUMBER "$pr_number"
  print_kv BRANCH "$branch_name"
  print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
  return 2
}
```

### `bot_login_for_platform` case addition (illustrative)

```bash
# Illustrative — adapt during implementation
copilot) printf '%s\n' "${COPILOT_BOT_LOGIN:-copilot-pull-request-reviewer[bot]}" ;;
```

### `run_platform_review` dispatch addition (illustrative)

```bash
# Illustrative — adapt during implementation
copilot)
  run_copilot_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
  ;;
```

### HARNESS_MODE unit tests (illustrative)

```bash
# Illustrative — adapt during implementation

echo ""
echo "=== Area N: Copilot platform function ==="

# Test N.1: clean path — Copilot posts APPROVED review
MOCK_GH_OUTPUT='[{"user":{"login":"copilot-pull-request-reviewer[bot]"},"state":"APPROVED"}]'
MOCK_GH_POST_OUTPUT='{}'
actual_exit=0
actual_output=""
actual_output="$(
  set +e
  (
    cd_workflow_repo_root() { :; }
    repo_slug() { printf 'owner/repo\n'; }
    run_copilot_review 42 "feature/42-test" 1 5
  )
  actual_exit=$?
  echo "EXIT=$actual_exit"
)" || true
run_test "copilot clean: RESULT=clean" "RESULT=clean" \
  "$(printf '%s\n' "$actual_output" | grep "^RESULT=")"
run_test "copilot clean: BLOCKING_COUNT=0" "BLOCKING_COUNT=0" \
  "$(printf '%s\n' "$actual_output" | grep "^BLOCKING_COUNT=")"

# Test N.2: needs-fixes path — Copilot posts CHANGES_REQUESTED
# ... (similar structure)

# Test N.3: escalate path — no review within max_wait
# ... (similar structure)
```

---

## Implementation Order

1. **Read `scripts/development-workflow/pr-review-loop.sh` in full** — note
   the exact line numbers of (a) the end of `run_claude_code_action_review()`
   (after the closing `}` and before `run_devin_review()`), (b) the
   `run_platform_review()` `case` block, and (c) the `bot_login_for_platform()`
   `case` block. Use these line numbers to place the additions precisely.

2. **Add `run_copilot_review()` to `pr-review-loop.sh`** — insert the new
   function after the closing `}` of `run_claude_code_action_review()` and
   before the opening line of `run_devin_review()`. The function must follow the
   illustrative code sample in this plan. Verify after insertion that:
   - The function signature takes exactly four positional args: `pr_number`,
     `branch_name`, `poll_interval`, `max_wait`
   - Exit codes 0, 1, and 2 are all reachable
   - Every `print_kv` call uses `PLATFORM "$platform"` (not a hardcoded string)
   - `_interruptible_sleep` is used for the polling loop (not `sleep`) to
     respect the SIGTERM trap

3. **Add `copilot` case to `run_platform_review()`** — in the `case "$platform"
   in` block, insert `copilot) run_copilot_review "$pr_number" "$branch_name"
   "$poll_interval" "$max_wait" ;;` after the `claude-code-action)` case and
   before the `*)` fallback. Verify the case label is exactly `copilot` (no
   quotes, no prefix).

4. **Add `copilot` entry to `bot_login_for_platform()`** — insert
   `copilot) printf '%s\n' "${COPILOT_BOT_LOGIN:-copilot-pull-request-reviewer[bot]}" ;;`
   after the `claude-code-action)` entry. Verify the default bot login string
   is enclosed in double quotes and uses the `[bot]` suffix format consistent
   with other entries.

5. **Update `.ai-dev-workflow.yaml` comment** — locate the `# Supported today
   by pr-review-loop.sh:` comment on the `platforms:` key. Update it to list
   all currently supported platforms: `greptile, devin, coderabbit, pr-agent,
   codex-github, claude-code-action, copilot`. Add a comment block for `copilot`
   noting the `COPILOT_BOT_LOGIN` override variable, analogous to the
   `CODEX_GITHUB_BOT_LOGIN` block above it.

6. **Create `docs/workflow/development-workflow/integrations/copilot.md`** —
   write the integration guide following the structure of `greptile.md` and
   `claude-code-action.md` (What it Adds, Setup, Step 7 implementation details,
   known limitations). Mark as optional in the opening paragraph. Include the
   `COPILOT_BOT_LOGIN` env var reference. Do not copy internal API call syntax
   verbatim — reference `pr-review-loop.sh` as the authoritative implementation.

7. **Add HARNESS_MODE unit tests to
   `scripts/development-workflow/tests/test-pr-review-loop.sh`** — append a
   new test area section covering the three required scenarios (clean,
   needs-fixes, escalate/timeout). Follow the test infrastructure already
   present in the file: mock `gh` via `MOCK_GH_OUTPUT` / `MOCK_GH_POST_OUTPUT`,
   call `run_copilot_review` directly after sourcing with `HARNESS_MODE=1`, and
   use `run_test` for assertions. Confirm the test file still exits 0 after the
   addition by running:

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   bash "$REPO_ROOT/scripts/development-workflow/tests/test-pr-review-loop.sh"
   ```

8. **Pre-commit lint** — run `markdownlint-cli2` on the plan, smoke test runbook,
   and new integration guide:

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/specs/developments/20260524150328_copilot-review-backstop/2_copilot-review-backstop_implementation-plan.md" \
     "docs/testing/workflow/709-copilot-review-backstop.smoke-test.md" \
     "docs/workflow/development-workflow/integrations/copilot.md"
   ```

   Fix any reported violations before committing.

9. **Cross-section consistency self-check** — verify that:
   - The bot login default string (`copilot-pull-request-reviewer[bot]`) is
     identical in `run_copilot_review()`, `bot_login_for_platform()`, the
     integration guide, and the HARNESS_MODE tests
   - The `COPILOT_BOT_LOGIN` env var name is spelled identically in all four
     locations
   - Exit codes are consistent: 0 = clean, 1 = needs\_fixes, 2 = escalate
     everywhere the plan references them

10. **Commit** — `feat(pr-review-loop): add GitHub Copilot code review platform
    (#709)`

11. **Update `CHANGELOG.md`** under `[Unreleased]` — add:

    ```
    - **Add GitHub Copilot code review as optional PR review platform** (#709): `copilot` is now a supported value for `review.platforms` in `.ai-dev-workflow.yaml`; when declared, `pr-review-loop.sh` requests Copilot as a reviewer, polls for its verdict, and maps the result to the standard `clean` / `needs_fixes` / `escalate` output contract. Copilot review is optional and requires an active GitHub Copilot seat or the Copilot for Pull Requests feature on the repository.
    ```

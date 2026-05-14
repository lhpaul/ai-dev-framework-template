# Script Quality Gates to Prevent Downstream Drift — Implementation Plan

**Spec**: [docs/specs/developments/20260512122855_585-script-quality-gates/1_585-script-quality-gates_specs.md](./1_585-script-quality-gates_specs.md)
**Smoke test runbook**: [docs/testing/workflow/585-script-quality-gates.smoke-test.md](../../../testing/workflow/585-script-quality-gates.smoke-test.md)

---

## Summary

**Approach**: Add a self-contained shell test harness at
`scripts/development-workflow/tests/test-pr-review-loop.sh` that exercises the three
highest-risk logic areas of `pr-review-loop.sh` using mock `gh`/`git`/`curl`
commands. Extend the existing `shellcheck.yml` CI workflow with a path-triggered step
that runs the harness on any PR touching `pr-review-loop.sh` or `workflow-lib.sh`.
Amend the prepare-release protocol to include two explicit checklist items: one
requiring the automated reviewer loop (including CodeRabbit when available) to cover
all modified workflow scripts before the production PR is labeled
`ready-for-human-review`, and one prompting the operator to review open
downstream-script-bug issues before cutting the release.

**Estimated complexity**: M

**Rationale**: The test harness is a new shell file (~200–300 lines) with no external
dependencies. CI integration is a single workflow file edit. Protocol edits are small
targeted insertions. No existing scripts or protocols are restructured.

**Dependencies**: None — the bugs targeted by the harness are already fixed (PR #588).
This item adds the quality gate, not the fixes.

---

## Verification Log

| Check | Command / query | Result |
|---|---|---|
| Repo revision | `git rev-parse --short HEAD` | `6c7ef05` |
| Existing test infrastructure under `scripts/` | `find scripts/ -name "test-*"` | No matches — no tests directory yet |
| `normalize_platform_verdict` function location | `grep -n "normalize_platform_verdict" scripts/development-workflow/pr-review-loop.sh` | Defined at line 2651 |
| `check_unreplied_rest_comments` function location | `grep -n "check_unreplied_rest_comments()" scripts/development-workflow/pr-review-loop.sh` | Defined at line 1465 |
| Compare-mode platform-config detection location | `grep -n "existing_platform_str\|current_platform_str" scripts/development-workflow/pr-review-loop.sh` | Lines 2776–2785 in `append_compare_metrics_row` |
| `kv_value` / `kv_value_default` helper location | `grep -n "^kv_value" scripts/development-workflow/pr-review-loop.sh` | Defined at lines 140–157 in `pr-review-loop.sh` itself |
| Existing CI workflow for shell scripts | `ls .github/workflows/` | `shellcheck.yml` exists; no separate test-harness workflow |
| Prepare-release protocol script-bug mentions | `grep -n "script.*bug\|workflow script\|reviewer loop.*script" docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md` | Zero matches — no existing explicit requirement |
| Retrospective downstream-script-bug prompt | `grep -n "template.*script\|downstream.*fix" docs/workflow/development-workflow/protocols/06-retrospective-protocol.md` | Zero matches — no explicit prompt |

---

## Layer-by-Layer Changes

### Infrastructure / Configuration

- [ ] Add a new CI step to `.github/workflows/shellcheck.yml` that runs the test
  harness on pull requests that modify `scripts/development-workflow/pr-review-loop.sh`
  or `scripts/development-workflow/workflow-lib.sh`. The step uses a `paths` filter
  identical to the scope of the harness: only those two files. The step runs
  `bash scripts/development-workflow/tests/test-pr-review-loop.sh` and fails the
  CI run if the exit code is non-zero.

### Scripts / Tooling

- [ ] Create the directory `scripts/development-workflow/tests/` (no `__init__` or
  package file needed — plain directory).
- [ ] Create `scripts/development-workflow/tests/test-pr-review-loop.sh` as an
  executable (`chmod +x`) self-contained bash test harness. See the Architecture
  section below for the design.

### Documentation / Protocols

- [ ] In `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`,
  add two explicit checklist items inside **Step 7.3** (Automated reviewer loop), placed
  immediately after the introductory paragraph and before the `Interpret RESULT` table:
  1. **Script-coverage requirement**: the automated reviewer loop (including CodeRabbit
     when available) must cover all `scripts/development-workflow/` files modified since
     the last release. If CodeRabbit is not installed the operator must manually review
     changed scripts or escalate.
  2. **Downstream script-bug issue review**: before labeling the production PR
     `ready-for-human-review`, check GitHub issues labeled `workflow` or `script-bug`
     that were filed from downstream sync retrospectives — if any known bugs remain open
     and are present in the release, address them in the release branch or document the
     decision to defer.
- [ ] In `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`,
  add an explicit prompt in **Step 3a** (Backlog query / issue scan), after the existing
  "File a new backlog issue" guidance: "Were any template script bugs fixed in a
  downstream sync PR during this cycle? If so, file a template issue tagged `workflow`
  and link it from the downstream fix commit."

---

## Architecture: Test Harness Design

### Harness structure

The harness is a single bash script at
`scripts/development-workflow/tests/test-pr-review-loop.sh`. It:

1. **Sources the subset of `pr-review-loop.sh` it needs** by extracting function
   definitions into a temp file using `sed`/`awk` and sourcing that, or — simpler and
   more robust — sources `pr-review-loop.sh` with a `HARNESS_MODE=1` guard so the main
   execution block at the bottom of the script is skipped. The guard approach reuses the
   existing shebang and `set -euo pipefail` context correctly.

   Because `pr-review-loop.sh` sources `workflow-lib.sh` at the top, the harness must
   provide mock implementations of any `workflow-lib.sh` functions called by the tested
   functions before sourcing `pr-review-loop.sh`. Functions not called by the targeted
   logic areas can remain unimplemented (they will not be invoked).

2. **Provides a minimal mock layer** for external commands (`gh`, `git`) via `PATH`
   override: the harness creates a temp directory, writes small mock scripts into it,
   and prepends it to `PATH`. Each mock script returns a configurable output stored in
   environment variables set by the test case. The mocks are cleaned up in a `trap`.

3. **Runs named test cases** sequentially. Each test case:
   - Sets mock environment variables
   - Calls the function under test
   - Compares the output or exit code to the expected value
   - Prints `PASS: <test-name>` or `FAIL: <test-name> — expected <X>, got <Y>`
   - Increments a pass/fail counter

4. **Exits 0** if all test cases pass; **exits 1** if any test case failed.

5. **Prints a summary** at the end: `Tests: N passed, M failed`.

### HARNESS_MODE guard in pr-review-loop.sh

To enable sourcing without executing, add a guard at the start of the main execution
block in `pr-review-loop.sh`. The main block begins after all function definitions — it
starts with the argument-parsing section and the call to `run_review_loop` (or
equivalent). Wrap that entire section with:

```bash
# Illustrative — adapt during implementation
if [ "${HARNESS_MODE:-0}" -ne 1 ]; then
  # ... existing main execution block ...
fi
```

This does not change production behavior: `HARNESS_MODE` is unset in all normal
invocations, so the guard evaluates to false and execution proceeds identically.

ShellCheck must remain clean after this change — the guard uses portable POSIX syntax.

### Test cases

#### Area 1: `normalize_platform_verdict`

| Test name | Input `result` | Input `output` (REASON) | Expected output |
|---|---|---|---|
| `verdict_clean` | `clean` | (empty) | `clean` |
| `verdict_needs_fixes` | `needs_fixes` | (empty) | `blocking` |
| `verdict_advisory` | `advisory` | (empty) | `advisory` |
| `verdict_skipped` | `skipped` | (empty) | `unavailable` |
| `verdict_needs_rerun` | `needs_rerun` | (empty) | `blocking` |
| `verdict_escalate_timeout` | `escalate` | `REASON=timeout` | `timed out` |
| `verdict_escalate_timed_out` | `escalate` | `REASON=timed_out` | `timed out` |
| `verdict_escalate_max_wait` | `escalate` | `REASON=max_wait_exceeded` | `timed out` |
| `verdict_escalate_no_response` | `escalate` | `REASON=no_response` | `timed out` |
| `verdict_escalate_unknown` | `escalate` | `REASON=service_error` | `unavailable` |
| `verdict_unknown_token` | `something_else` | (empty) | `unavailable` |

#### Area 2: `check_unreplied_rest_comments`

These tests mock `gh api` to return a controlled JSON payload and verify the jq pipeline
correctly counts unreplied root comments.

| Test name | Mock payload description | Expected count |
|---|---|---|
| `rest_no_comments` | Empty array `[]` | `0` |
| `rest_single_bot_root_unreplied` | One root comment from `coderabbitai[bot]`, no replies | `1` |
| `rest_bot_root_with_human_reply` | One root comment from `coderabbitai[bot]`, one reply from a human user | `0` |
| `rest_bot_root_with_bot_reply_only` | One root comment from `coderabbitai[bot]`, one reply from another `[bot]`-suffixed account | `1` (bot reply does not count) |
| `rest_addressed_marker` | One root comment from `coderabbitai[bot]` containing `✅ Addressed` in body | `0` |
| `rest_resolved_id_excluded` | One root comment from `coderabbitai[bot]`, resolved_ids includes its `.id` | `0` |
| `rest_human_comment_ignored` | One root comment from a non-bot human user, no replies | `0` (only bot root comments are counted) |
| `rest_multiple_bot_comments_partial_replied` | Three bot root comments, one with human reply | `2` |

The mock `gh` script for these tests writes the payload from an env variable to stdout
and exits 0. The `bot_login` argument is `coderabbitai[bot]` in all cases.

#### Area 3: Compare-mode platform config change detection (`append_compare_metrics_row`)

These tests verify that the header-row comparison in `append_compare_metrics_row`
correctly detects platform configuration changes (ordered name comparison, not column
count comparison).

| Test name | Scenario | Expected behavior |
|---|---|---|
| `compare_no_existing_file` | Metrics file does not exist | Creates file with header and one data row |
| `compare_same_platform_set` | Existing file has same platforms in same order | Appends data row without separator comment |
| `compare_platform_added` | Existing file has fewer platforms | Inserts `*(platforms changed: ...)* ` row then new header + data row |
| `compare_platform_reordered` | Same platform count but different order | Inserts separator comment row (order is semantically significant) |
| `compare_platform_renamed` | Same count, different names | Inserts separator comment row |

These tests require a writable temp file for the metrics log. Use `mktemp` and clean up
in a `trap`. The mock `workflow_repo_root` function returns the temp directory.

---

## Testing Strategy

**Test types**: Unit (test harness), CI gate (GitHub Actions path filter), Manual
(smoke test)

**Key scenarios to test**:
1. Harness passes locally with `bash scripts/development-workflow/tests/test-pr-review-loop.sh` — maps to AC: harness runs without external tooling
2. Harness CI step triggers on a PR that modifies `pr-review-loop.sh` — maps to AC: CI runs harness on affected PRs
3. Harness CI step does NOT trigger on a PR that only modifies unrelated files — maps to AC: harness not required on every PR
4. Prepare-release protocol Step 7.3 shows the two new checklist items — maps to ACs for prepare-release changes
5. Retrospective protocol Step 3a shows the downstream script-bug prompt — maps to retrospective AC

**Smoke test runbook**: `docs/testing/workflow/585-script-quality-gates.smoke-test.md`

---

## Seed Data

None — the test harness uses self-contained mock data; no external seed data is needed.

---

## Documentation Updates

- `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md` — add
  script-coverage and downstream-bug-review checklist items in Step 7.3 (detailed in
  Layer-by-Layer Changes above).
- `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md` — add
  downstream script-bug prompt in Step 3a (detailed in Layer-by-Layer Changes above).
- No changes to `docs/project/`, `AGENTS.md`, or best-practices docs — this feature
  does not affect project-level docs.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| `HARNESS_MODE` guard breaks existing tests (none exist) or the lock guard at the top of `pr-review-loop.sh` | Low | Med | The lock guard runs before any function definitions; `HARNESS_MODE` is checked only around the main execution block after all functions are defined. Place the guard carefully and verify with `bash -n` (syntax check) and ShellCheck. |
| Sourcing `pr-review-loop.sh` in HARNESS_MODE triggers the lock guard and exits early | Med | High | The lock guard is at the very top and reads `$@`. In `HARNESS_MODE`, the harness sources the script with no positional arguments; the lock guard computes `_PR_ARG=""`, creating `.lockdir` for `unknown`. Add an early-exit bypass: `[ "${HARNESS_MODE:-0}" -eq 1 ] && { trap '' EXIT; true; }` immediately after the `trap` registration so the lock cleanup trap is a no-op. Alternatively, set `_SKIP_LOCK=1` before sourcing and check that in the lock block. Document the chosen approach in the harness. |
| jq pipeline in `check_unreplied_rest_comments` behaves differently when `gh api --paginate` output is mocked as a flat array vs. nested pages | Med | Med | The function pipes through `jq -s` which collapses all pages. The mock must match the paginated shape: a JSON array of arrays (one sub-array per page). For a single-page mock, wrap the payload in an outer array: `[[...items...]]`. Document this in the test case setup comments. |
| ShellCheck flags the new harness file | Low | Low | Run `shellcheck scripts/development-workflow/tests/test-pr-review-loop.sh` locally before committing; existing `shellcheck.yml` will also check it automatically. |

---

## Code Samples

All code samples below are illustrative — adapt during implementation.

### HARNESS_MODE guard placement in `pr-review-loop.sh`

```bash
# Illustrative — adapt during implementation
# At the bottom of pr-review-loop.sh, after all function definitions,
# wrap the main execution block:

# Skip execution when sourced in test-harness mode.
[ "${HARNESS_MODE:-0}" -eq 1 ] && return 0 2>/dev/null || true

# ... existing main execution block (argument parsing, run_review_loop call, etc.) ...
```

Using `return 0` instead of `exit 0` is important when the file is sourced: `exit`
would terminate the caller's shell, while `return` exits only the sourced context.
`2>/dev/null || true` suppresses the "return: can only return from a function or
sourced script" error on the rare bash version that issues it when `return` is used
at top level in a sourced file.

### Harness mock PATH setup

```bash
# Illustrative — adapt during implementation
MOCK_BIN="$(mktemp -d)"
trap 'rm -rf "$MOCK_BIN"' EXIT

# Mock gh: prints $MOCK_GH_OUTPUT and exits with $MOCK_GH_EXIT (default 0)
cat > "$MOCK_BIN/gh" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "${MOCK_GH_OUTPUT:-[]}"
exit "${MOCK_GH_EXIT:-0}"
MOCK
chmod +x "$MOCK_BIN/gh"

export PATH="$MOCK_BIN:$PATH"
```

### Paginated `gh api` mock payload format

```bash
# Illustrative — adapt during implementation
# check_unreplied_rest_comments pipes through: gh api ... | jq -s ...
# jq -s wraps multiple JSON documents into an array.
# gh api --paginate writes one JSON array per page as separate documents.
# A single-page mock must output one JSON array (one document):
MOCK_GH_OUTPUT='[
  {"id": 1, "in_reply_to_id": null, "user": {"login": "coderabbitai[bot]"}, "body": "Finding X"},
  {"id": 2, "in_reply_to_id": 1,    "user": {"login": "humanuser"},         "body": "Acknowledged"}
]'
# jq -s will produce [[...]], which the pipeline handles correctly.
```

### Test case structure

```bash
# Illustrative — adapt during implementation
PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$actual" = "$expected" ]; then
    echo "PASS: $name"
    PASS_COUNT=$(( PASS_COUNT + 1 ))
  else
    echo "FAIL: $name — expected '$expected', got '$actual'"
    FAIL_COUNT=$(( FAIL_COUNT + 1 ))
  fi
}

# Example usage:
actual="$(normalize_platform_verdict "clean" "")"
run_test "verdict_clean" "clean" "$actual"
```

---

## Implementation Order

1. **Add `HARNESS_MODE` guard to `pr-review-loop.sh`**

   At the bottom of `scripts/development-workflow/pr-review-loop.sh`, immediately
   before the main execution block (the argument-parsing section that starts with `for
   _arg in "$@"` for argument parsing or the direct `run_review_loop` call — identify
   the exact split point by locating the last function definition and the first line
   of non-function non-comment code after it), add:

   ```bash
   [ "${HARNESS_MODE:-0}" -eq 1 ] && return 0 2>/dev/null || true
   ```

   Verify: run `bash -n scripts/development-workflow/pr-review-loop.sh` (syntax check
   passes) and confirm the script still operates normally with
   `bash scripts/development-workflow/pr-review-loop.sh --help` (usage printed, no
   lock-guard error).

2. **Create `scripts/development-workflow/tests/test-pr-review-loop.sh`**

   Create the directory and the test harness file with these sections in order:

   a. Shebang and `set -euo pipefail`
   b. Locate script directory and set `REPO_ROOT` (using `git rev-parse
      --git-common-dir`):
      ```bash
      SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
      REPO_ROOT="$(CDPATH='' cd -- "$(git -C "$SCRIPT_DIR" rev-parse --git-common-dir)/.." && pwd)"
      ```
   c. Mock PATH setup (temp dir with `gh` and `git` mocks; `trap` cleanup)
   d. Mock `workflow-lib.sh` functions needed by the tested logic (at minimum:
      `workflow_repo_root`, `print_kv`, `workflow_config_review_platforms`).
      These can be simple shell functions defined directly in the harness before
      sourcing `pr-review-loop.sh`.
   e. Source `pr-review-loop.sh` with `HARNESS_MODE=1`:
      ```bash
      HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"
      ```
   f. Counter initialization (`PASS_COUNT=0`, `FAIL_COUNT=0`)
   g. `run_test` helper function
   h. All test cases organized by area (see Architecture section)
   i. Summary and exit:
      ```bash
      echo "Tests: $PASS_COUNT passed, $FAIL_COUNT failed"
      [ "$FAIL_COUNT" -eq 0 ]
      ```

   Make the file executable: `chmod +x scripts/development-workflow/tests/test-pr-review-loop.sh`

   Verify locally: `bash scripts/development-workflow/tests/test-pr-review-loop.sh`
   should print all PASS lines and exit 0.

3. **Extend `.github/workflows/shellcheck.yml` with a harness step**

   Add a `test-harness` job that triggers only when the two target files change.
   Prefer a dedicated workflow file over adding it to `shellcheck.yml` so the two
   jobs trigger on different path sets and their failures remain distinguishable.
   The two target files to monitor are:
   - `scripts/development-workflow/pr-review-loop.sh`
   - `scripts/development-workflow/workflow-lib.sh`

   The step runs:
   ```bash
   bash scripts/development-workflow/tests/test-pr-review-loop.sh
   ```

   No additional dependencies or setup are required — the harness uses only `bash` and
   `git`.

   Path filtering in GitHub Actions is defined at the workflow trigger level (`on:
   pull_request: paths:`), not at the job level. Use a separate workflow file
   (`.github/workflows/test-pr-review-loop.yml`) with its own `paths` filter scoped
   to only the two target files. This is the cleanest approach: the harness job
   triggers only when the files it tests actually change, independently of the
   ShellCheck workflow.

   Illustrative structure for `.github/workflows/test-pr-review-loop.yml`:

   ```yaml
   # Illustrative — adapt during implementation
   on:
     pull_request:
       branches:
         - develop
         - main
       paths:
         - 'scripts/development-workflow/pr-review-loop.sh'
         - 'scripts/development-workflow/workflow-lib.sh'

   jobs:
     test-harness:
       name: pr-review-loop test harness
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@93cb6efe18208431cddfb8368fd83d5badbf9bfd
         - name: Run test harness
           run: bash scripts/development-workflow/tests/test-pr-review-loop.sh
   ```

   Alternatively, add the `test-harness` job to the existing `shellcheck.yml` file
   by extending its `on.pull_request.paths` trigger to include the two target files
   and adding the job definition there.

   Verify: confirm the new CI check appears in the PR checks list and fails when a test
   case is intentionally broken.

4. **Update `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`**

   In **Step 7.3 (Automated reviewer loop)**, after the introductory paragraph
   ("Run `pr-review-loop.sh` to completion...") and before the `Interpret RESULT`
   table, insert:

   > **Script-coverage requirement**: Before running the reviewer loop, confirm that
   > `CodeRabbit` (when available) is configured to review all files in
   > `scripts/development-workflow/` that were modified since the last release. If
   > CodeRabbit is not installed, manually review changed workflow scripts for logic
   > bugs before labeling the production PR `ready-for-human-review`.
   >
   > **Downstream script-bug review**: Before labeling the production PR
   > `ready-for-human-review`, search for open GitHub issues labeled `workflow` that
   > were filed from downstream sync retrospectives:
   > ```bash
   > gh issue list --label workflow --state open --repo <owner>/<repo>
   > ```
   > If any known script bugs remain open and affect code in this release, address them
   > in the release branch or document the decision to defer with a comment on the issue.

5. **Update `docs/workflow/development-workflow/protocols/06-retrospective-protocol.md`**

   In **Step 3a** (the backlog query section), locate the paragraph or instruction about
   filing new backlog issues. Append the following sentence or short paragraph
   immediately after:

   > **Downstream script-bug tracking prompt**: Were any template workflow script bugs
   > fixed in a downstream sync PR during this retrospective's cycle? If yes, file a
   > GitHub issue in the template repository tagged with the `workflow` label and include
   > a link to the downstream fix commit in the issue body. This prevents the same bug
   > from shipping to future downstream syncs.

6. **Pre-commit lint check**

   Run markdownlint on the plan and smoke test runbook:

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/specs/developments/20260512122855_585-script-quality-gates/2_585-script-quality-gates_implementation-plan.md" \
     "docs/testing/workflow/585-script-quality-gates.smoke-test.md"
   ```

   Fix any reported violations before committing.

7. **Run ShellCheck on the new harness file**

   ```bash
   shellcheck scripts/development-workflow/tests/test-pr-review-loop.sh
   ```

   Fix any warnings before committing.

8. **Update CHANGELOG.md** under `[Unreleased]`:

   ```
   - **Script quality gates for pr-review-loop.sh** (#585): add a shell test harness
     covering `normalize_platform_verdict`, `check_unreplied_rest_comments`, and
     compare-mode analytics; add path-triggered CI step; add prepare-release script
     coverage and downstream bug-review checklist items.
   ```

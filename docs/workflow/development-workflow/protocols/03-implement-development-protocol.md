# Protocol: Implement Development (In Development Stage)

**Agent role**: Developer
**Stage**: In Development
**Paths**: Full Pipeline | Refactor | Fast Track | Hotfix

---

## Which Path to Use?

| Path              | Branch                           | Use when                                                                         |
| ----------------- | -------------------------------- | -------------------------------------------------------------------------------- |
| **Full Pipeline** | `feature/[slug]` from `develop`  | Feature with approved spec + plan                                                |
| **Refactor**      | `refactor/[slug]` from `develop` | Code restructuring with approved plan (no spec)                                  |
| **Fast Track**    | `fix/[slug]` from `develop`      | Bug or simple change — clear scope, ≤3 files, no schema changes, no new patterns |
| **Hotfix**        | `hotfix/[slug]` from `main`      | Critical production bug requiring immediate deployment                           |

---

## GitHub Actions Workflow Security Checklist

When your change creates or materially modifies `.github/workflows/*.yml`, complete this checklist before opening the development PR.

- Add an explicit `permissions:` block at workflow or job scope with least privilege (default to `contents: read` unless broader access is required)
- Pin all `uses:` references to a full commit SHA, with the pinned version tag noted in an adjacent comment (for example: `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2`)
- Add `paths:` / `paths-ignore:` filters when the workflow only needs to run for specific files or directories
- Add a `concurrency` group when duplicate runs on the same ref should be prevented
- **Fork-PR guard (mandatory for any step that writes to the repository)**: every step that mutates repository state — adding or removing labels, posting comments, creating deployments or releases, writing status checks or check runs, or triggering other workflows via `GITHUB_TOKEN` — must include an `if:` condition that restricts execution to PRs originating from the same repository. Use `if: github.event.pull_request.head.repo.full_name == github.repository` or an equivalent fork-origin check. Without this guard, a fork-originated PR can trigger label changes or other write operations on the base repository. Exception: jobs or steps that run on `push` (not `pull_request`) events, or that are already scoped to protected branches, are exempt because fork PRs cannot trigger `push` workflows on the base repo.

---

## Shell Script Quality Checklist

When your change **creates or significantly modifies a `.sh` file**, or when your change **adds or edits shell code blocks (```` ```bash ```` / ```` ```sh ```` fenced blocks) inside a protocol or documentation `.md` file**, complete this checklist before opening the development PR. These are the most common bash scripting anti-patterns that cause rework in the automated reviewer loop.

### 1. jq variable injection

Always use `--arg name value` for string values and `--argjson name value` for JSON values. Never expand shell variables directly inside jq filter strings.

```bash
# Wrong — shell variable injected into filter string (injection risk, quoting fragile):
result=$(echo "$json" | jq ".items[] | select(.name == \"$NAME\")")

# Correct — use --arg for string values:
result=$(echo "$json" | jq --arg name "$NAME" '.items[] | select(.name == $name)')

# Correct — use --argjson for JSON values (numbers, booleans, objects, arrays):
result=$(echo "$json" | jq --argjson count "$COUNT" '.items | .[:$count]')
```

### 2. `pipefail` + SIGPIPE

When using `set -o pipefail` (or `set -eo pipefail`), commands like `head`, `grep -m`, and others that close a pipe early will cause the writing process to receive SIGPIPE (exit code 141). Under `pipefail`, the parent shell observes the 141 exit code from the child process and (combined with `set -e`) exits the script. This looks like an error even when the behavior is intentional.

**Note**: `trap ... PIPE` does **not** fire for pipeline SIGPIPE. SIGPIPE is delivered to the _child subprocess_ writing to the closed pipe, not to the parent shell. The parent shell only observes the 141 exit code via `waitpid`. To catch this at the script level, use `trap ... EXIT` — it fires when `set -e` causes the shell to exit due to the pipefail-detected 141 status.

Guard against SIGPIPE false-positives on pipelines that may close early:

```bash
# Option A — trap EXIT at script level (apply when the full script uses set -o pipefail):
set -eo pipefail
trap 'case $? in 141) exit 0 ;; *) exit $? ;; esac' EXIT

# Option B — suppress SIGPIPE for a single pipeline:
some_command | head -1 || true

# Option C — use process substitution to avoid the pipe entirely:
while IFS= read -r line; do
  process "$line"
done < <(some_command)
```

Choose the option that matches your script's error-handling strategy. Option A is preferred for scripts where most SIGPIPE exits should be treated as clean exits.

### 3. Exit code semantics under `set -e`

Under `set -e`, any command that exits non-zero causes the script to abort — **including commands inside compound expressions**. The rules for compound expressions are counter-intuitive:

| Expression      | `set -e` behavior                                         |
| --------------- | --------------------------------------------------------- |
| `cmd` (bare)    | Abort on non-zero                                         |
| `if cmd; then`  | Safe — exit code is tested by `if`, never propagated      |
| `cmd \|\| true` | Safe — `true` always exits 0, so the `\|\|` chain exits 0 |
| `cmd && other`  | Safe — `set -e` does not abort on the left side of `&&`   |
| `result=$(cmd)` | **Abort on non-zero** — same as bare command              |

Capture exit codes explicitly when the command can legitimately fail:

```bash
# Wrong under set -e — aborts if gh pr view exits non-zero (e.g., PR not found):
PR_STATE=$(gh pr view "$PR_NUMBER" --json state --jq '.state')

# Correct — capture exit code separately:
PR_STATE=$(gh pr view "$PR_NUMBER" --json state --jq '.state' 2>/dev/null) || true
# or, when you need to distinguish success from failure:
if ! PR_STATE=$(gh pr view "$PR_NUMBER" --json state --jq '.state' 2>/dev/null); then
  echo "PR $PR_NUMBER not found — skipping"
  PR_STATE=""
fi
```

### 4. Timestamp sourcing

When ordering or comparing events (e.g., determining which comment came first, whether a review happened after the last push), always use **server-returned timestamps from API responses**, not local `date` output. Local clocks can be skewed relative to the server by seconds or minutes.

```bash
# Wrong — local clock may not match server time:
TRIGGER_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Correct — capture the timestamp from the API response:
RESPONSE=$(gh pr comment "$PR_NUMBER" --body "$TRIGGER_BODY")
TRIGGER_TIME=$(echo "$RESPONSE" | jq -r '.createdAt')
```

### 5. Subshell exit codes — the `local` trap

In bash, a bare assignment `OUTPUT=$(cmd)` exposes `$?` as the exit code of `cmd` — the assignment itself does not mask it. However, when the assignment is combined with a variable declaration keyword (`local`, `export`, or `declare`), the keyword's own exit code (always 0) overwrites the substitution's exit code, silently swallowing failures.

Under `set -e`, bare `OUTPUT=$(cmd)` still aborts on non-zero (same as a bare command). To safely capture output and check success, use `if ! OUTPUT=$(cmd); then` or `OUTPUT=$(cmd) || INNER_EXIT=$?`.

```bash
# Correct — check failure inline (works under set -e):
if ! OUTPUT=$(inner_command); then
  echo "inner_command failed"
  exit 1
fi

# Dangerous inside functions — local masks the exit code (local itself exits 0):
my_func() {
  local OUTPUT=$(inner_command)  # $? is 0 even if inner_command failed!
  echo "Exit was: $?"  # Always prints "Exit was: 0"
}

# Safe inside functions — declare then assign, using if ! to handle failure:
my_func() {
  local OUTPUT
  if ! OUTPUT=$(inner_command); then
    echo "inner_command failed"
    return 1
  fi
}
```

The same masking behavior applies to `export VAR=$(cmd)` and `declare VAR=$(cmd)`. Always separate declaration from assignment when the exit code matters.

### 6. `gh` CLI / API error handling

`gh` commands exit non-zero when the API request fails, the resource is not found, or the user lacks permissions. Always guard `gh` calls that may legitimately fail:

```bash
# Wrong — no error handling; gh api exits non-zero on HTTP 4xx/5xx:
RESULT=$(gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER" --jq '.state')

# Correct — handle failure and empty output explicitly:
if ! RESULT=$(gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER" --jq '.state' 2>/dev/null); then
  echo "Failed to fetch PR $PR_NUMBER — skipping"
  RESULT=""
fi
[ -z "$RESULT" ] && { echo "Empty state returned for PR $PR_NUMBER"; exit 1; }
```

### 7. Input validation at script entry

Validate all positional parameters before any network or filesystem operation. A missing argument causes confusing errors deep in the script rather than a clear message at startup.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Always validate at the top, before any gh / API calls:
PR_NUMBER="${1:?Usage: $0 <pr_number> <owner> <repo>}"
OWNER="${2:?Usage: $0 <pr_number> <owner> <repo>}"
REPO="${3:?Usage: $0 <pr_number> <owner> <repo>}"
```

The `${VAR:?message}` form causes the script to exit with an informative error if the variable is unset or empty. Use it for all required positional parameters.

### 8. Shell snippets in protocol and documentation `.md` files

Shell code blocks embedded in protocol and documentation markdown files are copied verbatim by agents and humans following the protocol. Apply the same quality bar as for `.sh` files — there is no separate "docs exception."

**Multi-command state-mutating blocks** (blocks that create branches, push, write files, label PRs, or otherwise modify persistent state):

- Begin with `set -euo pipefail` (or, when running inside a function/sub-shell context where `set` is already active, document the inherited error-handling assumption in an inline comment).
- Capture `gh` / `git` exit codes explicitly; do not rely on a bare command that would silently swallow a failure.
- Redirect error output to `stderr` (`2>/dev/null` only when failure is truly expected and the caller handles it; otherwise let errors surface).

**Blocks that commit or push to a branch**:

- Add a wrong-branch guard before the commit or push. Check that the current branch matches the expected pattern before proceeding:

  ```bash
  CURRENT=$(git rev-parse --abbrev-ref HEAD)
  [[ "$CURRENT" == fix/* ]] || { echo "ERROR: expected fix/* branch, got $CURRENT" >&2; exit 1; }
  ```

**Single-liner examples** (illustrative commands shown without multi-step context):

- If the snippet can fail silently in a way that corrupts downstream state (e.g., a silent `gh` call whose output is consumed by the next step), add an explicit `|| exit 1` or `|| { echo "ERROR: ..."; exit 1; }`.
- Single-liner `read`-only queries (`gh pr view`, `git log`, etc.) that do not modify state are exempt.

These rules apply equally to all protocol documents under `docs/workflow/development-workflow/protocols/` and to any other markdown file that embeds shell commands intended to be run by agents or humans.

### 9. `jq` parse-failure handling

`jq` exits non-zero when the input is not valid JSON. Without `-e` or an explicit exit-code check, a parse failure silently produces an empty string and the script continues with a missing value.

Always guard `jq` calls against parse failures:

```bash
# Wrong — malformed JSON produces empty string; script continues undetected:
VALUE=$(echo "$RESPONSE" | jq -r '.field')

# Correct — use -e so jq exits 1 on a null/false result, and check the exit code:
if ! VALUE=$(echo "$RESPONSE" | jq -re '.field' 2>/dev/null); then
  echo "ERROR: jq parse failed or field is null/missing" >&2
  exit 1
fi

# Correct alternative — explicit OR handler for inline use:
VALUE=$(echo "$RESPONSE" | jq -re '.field') || { echo "ERROR: jq parse failed" >&2; exit 1; }
```

Also validate that the parsed value is non-empty before using it when an empty string is not a valid sentinel:

```bash
[ -z "$VALUE" ] && { echo "ERROR: parsed value is empty" >&2; exit 1; }
```

This pattern is required for every `jq` call whose output is passed to a downstream command, comparison, or API call. Pure logging/display calls that do not affect control flow are exempt.

### 10. External CLI timeout budget

External CLI calls (`gh`, `curl`, `haystack`, `timeout`, custom tools) can block indefinitely if the remote service is slow or unresponsive. Scripts that impose a timeout budget must propagate and check the result.

```bash
# Wrong — no timeout; hangs indefinitely if the service is slow:
RESULT=$(gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER")

# Correct — capture exit code before the if test, then check it:
RESULT=$(timeout 30 gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER" 2>/dev/null) || {
  EXIT_CODE=$?
  if [ "$EXIT_CODE" -eq 124 ]; then
    echo "ERROR: gh api timed out after 30 s" >&2
  else
    echo "ERROR: gh api exited with code $EXIT_CODE" >&2
  fi
  exit 1
}

# Alternative — background-wait pattern with an enforced deadline:
# (bash 3.2 compatible — uses a polling loop instead of wait -n)
gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER" > /tmp/result.json &
API_PID=$!
DEADLINE=$(($(date +%s) + 30))
while kill -0 "$API_PID" 2>/dev/null && [ "$(date +%s)" -lt "$DEADLINE" ]; do
  sleep 1
done
if kill -0 "$API_PID" 2>/dev/null; then
  kill "$API_PID" 2>/dev/null
  wait "$API_PID" 2>/dev/null
  echo "ERROR: API call timed out after 30 s" >&2
  exit 1
fi
wait "$API_PID" || { echo "ERROR: API call failed" >&2; exit 1; }
```

When a script receives a timeout budget from its caller (e.g., a `MAX_WAIT` parameter or environment variable), derive per-call timeouts from it rather than hard-coding constants. Never silently absorb a timeout by catching exit code 124 and returning an empty string — the caller must be informed.

### 11. Structured-data input validation before use

Scripts that accept structured input (JSON, YAML, TSV, newline-delimited data) from a previous command, file, or pipe must validate that the input is non-empty before attempting to parse or iterate over it. Proceeding with an empty input silently skips all iterations and produces no error, which can look like a successful run.

```bash
# Wrong — empty RESPONSE silently produces no iterations:
echo "$RESPONSE" | jq -r '.items[]' | while read -r item; do
  process_item "$item"
done

# Correct — validate before parsing:
if [ -z "$RESPONSE" ]; then
  echo "ERROR: empty response — cannot parse items" >&2
  exit 1
fi
ITEMS=$(echo "$RESPONSE" | jq -r '.items[]') || { echo "ERROR: jq failed on response" >&2; exit 1; }
if [ -z "$ITEMS" ]; then
  echo "WARNING: response contained no items — nothing to process"
  exit 0  # or exit 1, depending on whether an empty list is expected
fi
echo "$ITEMS" | while read -r item; do
  process_item "$item"
done
```

This validation is especially important in PR-review loop scripts and CI tools where a silent empty-parse produces a false-clean result.

---

## Test Harness Coverage Checklist

When your implementation includes **any test script, test function, or validation harness** (a script, function, or workflow that validates other scripts or logic), complete this checklist before self-approving at the verify/pre-commit step.

**Why this checklist exists**: Agents naturally optimize for the happy path — writing tests that verify the code works under normal inputs. Edge cases (empty input, missing environment variables, concurrent invocations) are consistently missed during self-review and surface only in the external automated review phase (CodeRabbit, PR-Agent), causing multiple fix rounds. This checklist prompts deliberate coverage of boundary conditions before the PR is opened.

**When to apply**: Mandatory for any implementation that ships or modifies a test script, test function, CI workflow step that runs tests, or any other harness that validates script or function behavior. Not required for non-test implementation files (application logic, documentation, configuration) that happen to be covered by existing tests.

Complete every item below. If an item is not applicable, state why before skipping it — do not silently skip.

- [ ] **Empty / zero-length input**: does the harness include at least one test where the primary input (string, array, file) is empty or zero-length, and the assertion verifies the correct behavior (error, warning, or defined default)?
- [ ] **Whitespace-only input**: does the harness test input that is non-empty but contains only whitespace characters (spaces, tabs, newlines), where the expected behavior differs from a non-blank string?
- [ ] **Boundary values**: does the harness test the minimum and maximum expected values (e.g., count = 0, count = 1, count = max, thresholds at the boundary, off-by-one positions)?
- [ ] **Missing / absent environment variables**: does the harness test behavior when required environment variables (`GITHUB_TOKEN`, `OWNER`, `REPO`, custom vars) are unset or empty, and assert that the script exits with a clear error rather than silently proceeding?
- [ ] **Concurrent / parallel execution**: for scripts that write shared state (files, git objects, GitHub API rate-limited resources), does the harness include at least one scenario that considers what happens under concurrent invocation, or explicitly document why isolation makes this safe?
- [ ] **Negative assertions**: for every positive assertion ("output equals X when input is Y"), is there at least one corresponding negative assertion ("assertion fails when the code is broken") — for example, testing that a function returns non-zero on bad input, or that a mock captures the call that would be skipped on the wrong branch?

**Additional items for Bash test harnesses** (apply when the harness is a `.sh` script that sources or invokes other shell scripts):

- [ ] **Single EXIT trap**: does the harness register at most one `trap ... EXIT` handler? Multiple `trap` registrations silently overwrite the previous handler; verify the harness does not lose cleanup logic by checking that any additional cleanup is chained inside a single trap.
- [ ] **Variable-length quoting safety**: does the harness include at least one test with variable-length or path-like input (filenames with spaces, tabs, glob characters, or newlines) and verify that variables are consistently quoted (`"$var"`, `"${arr[@]}"`) so word-splitting and globbing do not alter behavior?
- [ ] **`BASH_SOURCE` / `HARNESS_MODE` guard placement**: if the harness uses `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` or a `HARNESS_MODE` guard to distinguish sourced vs. executed contexts, verify the guard is top-level and evaluated before side effects/main execution, while keeping required function definitions and source statements available for sourced mode; tests must exercise both sourced and executed paths.
- [ ] **Sourced-function ordering**: when the harness sources other scripts to expose functions under test, verify the source order matches the dependency order — a function sourced after the file that calls it will silently use the caller's stale definition rather than the updated one.

If any item is unchecked after honest review: add the missing test cases before committing. Do not open the PR with known coverage gaps — the automated external reviewers (CodeRabbit) will catch them and require a fix round.

---

## Filter-Schema Canary Test Checklist

**When to apply**: Conditional — applies **only when this PR adds one or more new filter parameters to a tool schema** (Zod, JSON Schema, Joi, Pydantic, OpenAPI, or any equivalent contract-declaration mechanism). If your PR does not add new filter parameters, skip this section entirely. Modifying or removing an existing filter parameter without changing the schema contract does not trigger this obligation.

**Why this checklist exists**: A filter added to a schema is accepted by the API but may not be wired to the query builder's WHERE clause or equivalent filter-application function. Without a canary test, this silent no-op reaches production undetected — the filter appears to work (no error is thrown), but the result set is never narrowed.

Complete every item below for each newly added filter parameter before opening the PR:

- [ ] **Canary test present**: a canary test exists for each newly added filter.
- [ ] **Two-invocation pattern**: the canary test calls the tool with the new filter set to a value that narrows or alters the result set, and calls the tool again with the filter absent or set to a meaningfully different value.
- [ ] **Result-set assertion**: the canary test asserts that the two result sets differ.
- [ ] **Observable effect**: the test data is designed so the filter has a visible effect — identical results for both invocations do not satisfy this requirement.
- [ ] **Same-PR inclusion**: the canary test is included in this PR, not deferred to a follow-up.
- [ ] **Impracticality documented**: if a canary test is impractical (e.g., no test fixtures, no in-memory DB), the constraint is documented explicitly in the PR and an alternative verification approach is proposed — silence is not acceptable.

This requirement applies to **new** filter parameters only. Modifications to existing filter parameters that do not change the schema contract are exempt.

---

## Script-Accuracy Self-Check Checklist

**When to apply**: Conditional — applies **only when this PR is a documentation PR that describes the behavior of a script** (including CLI output format, option flags, exit codes, API call patterns, or input/output format). If your PR does not document what a script does, skip this section entirely.

**Why this checklist exists**: PR #731 had a 75% fix-commit ratio because the implementing agent acted on a Haystack reviewer finding about `claude-code-action-reviewer.sh` without verifying the claim against the actual script source, introducing a regression. Documentation that describes script behavior must be verified against the script — memory and inference are unreliable.

**How to apply**: Before opening the PR, run 3–5 targeted greps against the referenced script(s) to confirm each documented claim. Do not audit the full script; focus on the specific claims your documentation makes.

Complete every item below for each script described in the PR before opening the PR:

- [ ] **Claims enumerated**: list every claim the PR documentation makes about the script (input format, output format, exit codes, option flags, API calls, environment variables, trigger conditions).
- [ ] **Each claim verified against source**: for each claim, run a targeted grep or read the relevant section of the script source directly. Do not rely on memory or on what a reviewer asserted — the script source is the authoritative value.

  ```bash
  # Example: verify an exit code claim
  grep -n 'exit 0\|exit 1\|exit 2' scripts/development-workflow/my-script.sh

  # Example: verify a flag or option name
  grep -n -- '--flag-name\|FLAG_NAME' scripts/development-workflow/my-script.sh

  # Example: verify an output format claim (e.g., a RESULT= or STATUS= value)
  grep -n 'RESULT=\|STATUS=' scripts/development-workflow/my-script.sh
  ```

- [ ] **Discrepancies resolved**: if any grep reveals a mismatch between the documentation and the script source, update the documentation to match the script — do not update the script to match the documentation (unless the script itself is wrong and that fix is in scope).
- [ ] **Self-check log posted**: after completing the checks above, append a brief self-check log to the PR description confirming each verified claim. Example format:

  ```text
  ## Script-Accuracy Self-Check

  Script: scripts/development-workflow/my-script.sh
  - Exit code 0 = APPROVED: verified (grep line 47)
  - Exit code 1 = NEEDS_REVISION: verified (grep line 52)
  - `--poll-interval` flag: verified (grep line 23)
  - Output format `RESULT=`: verified (grep line 61)
  ```

This checklist does not require a full script audit — only the specific claims made in the PR documentation. If a claim cannot be verified by grep (e.g., it is an emergent behavior of multiple code paths), read the relevant function body directly and note the line range in the self-check log.

---

## Path 1: Full Pipeline

### Step 1: Non-Negotiable Prep

Read **all** of the following before writing a single line of code. Do not skip.

1. `docs/specs/developments/[timestamp]_[slug]/1_[slug]_specs.md` — spec (acceptance criteria, use cases, business rules)
2. `docs/specs/developments/[timestamp]_[slug]/2_[slug]_implementation-plan.md` — plan (what to build, in what order)
3. `docs/testing/[section]/[slug].smoke-test.md` — smoke test runbook (what "done" looks like)
4. `docs/project/3-software-architecture.md` — architecture patterns
5. `docs/best-practices/` — all best practice docs
6. Relevant existing code — read actual files for the areas you will modify
7. If an issue tracker exists for this item, follow `docs/workflow/development-workflow/integrations/issue-tracker.md` for `In Development (Full Pipeline)` expectations before coding.

Extract from your reading:

- The full list of acceptance criteria
- Every file or area you will touch
- The implementation order from the plan
- Seed data requirements

**Dependency check**: Read the `Depends on` field in the spec. If any dependency is not yet Merged or Released, stop and report to the human.

### Step 1b: Pre-Implementation Scope Checklist

Complete this checklist **before writing any code**. It takes 5–10 minutes and prevents review round-trips caused by missed files, scope drift, or inconsistencies with related protocols.

1. **Enumerate all files** that need changes. List every file path explicitly.
2. **For each file**, describe the specific changes needed (e.g., "add section X", "update step Y to handle case Z").
3. **Verify scope**: confirm all listed changes are within the issue's stated scope. Remove anything that is not.
4. **Consider edge cases** before touching any file:
   - What if the branch already exists locally or remotely?
   - What if this runs inside a worktree?
   - What are the failure modes or missing inputs?
   - Are there related files that must stay consistent with the changed files?
5. **Cross-reference related protocols**: if any changed file references or is referenced by other protocol documents, read those documents and confirm your changes are consistent with them.
6. **Cross-reference consistency check** (required when the change modifies policy or rule text): grep for all existing references to the policy being changed **before writing any code**. Do not rely on your prior knowledge of where a policy lives — the grep is how you discover all locations. Run the search across all relevant directories and file types, list every matched file, and confirm each location will be updated consistently. Verify that headings, signal names, and language do not contradict each other across files. All matched files are candidates for the same update; explicitly confirm coverage of each before submitting.

   ```bash
   # Run this BEFORE writing any code — grep discovers all locations that must change together
   grep -r "key phrase" docs/ .cursor/ .claude/ .codex/ AGENTS.md README.md REVIEW.md --include="*.md" --include="*.mdc" -l
   ```

7. **Script-emitted signal verification** (required when the change writes or edits protocol text that cites a script-emitted signal value such as `REASON=`, `RESULT=`, or `STATUS=`): read the relevant source script and verify the exact string before committing. Do not cite a signal value from memory or from protocol text alone — the script is the authoritative source.

   ```bash
   # Example: verify the exact REASON= value emitted by pr-review-loop.sh
   grep -n 'REASON=' scripts/development-workflow/pr-review-loop.sh
   ```

Do not proceed to Step 2 until this checklist is complete and all seven points are answered.

### Step 2: Human Review Shortcut (Optional)

Default behavior is **max autonomy**: once the approved spec and plan are understood and there is no unresolved product or architecture ambiguity, continue through implementation, the review gate, PR creation, and PR readiness without an extra pause.

Pause only if:

- The human explicitly asked to review the execution plan before coding
- The spec or plan is missing a decision you cannot safely invent
- The reviewer gate returns `NEEDS REVISION` because a human decision is required

### Step 3: Branch

Determine the branch slug:

- **With issue tracker**: `[issue-id]-[slug]` (e.g., `ENG-123-user-auth`)
- **Without issue tracker**: `[slug]` (e.g., `user-auth`)

**Integration-branch check**: Before creating the branch, check whether the work item carries an `integration-branch:<slug>` label (the orchestrator will have noted this in the handoff). If the label is present, use `develop-<slug>` as the base branch instead of `develop`:

```bash
# Standard:
git checkout develop && git pull origin develop
# If integration-branch:<slug> label is present, use develop-<slug> instead:
# git checkout develop-<slug> && git pull origin develop-<slug>
git checkout -b feature/[branch-slug]   # or fix/[branch-slug], refactor/[branch-slug]
```

The PR opened at the end of this path must target `develop-<slug>` when the label is present. If the integration branch does not exist yet, the orchestrator should have created it before dispatching this protocol — do not create it here; instead, stop and inform the Work Item Runner.

**Worktree context (`BATCH_CONTEXT=true`)**: If this step runs inside an isolated worktree created by the item-orchestrator (Protocol 91 Step 3), skip the `git checkout develop` / `git checkout -b` commands above — the worktree was already created on the correct branch. Run only `git fetch origin` if you need the latest remote refs. Before running any git state-changing command, confirm your working directory is inside the worktree path, not the main repo root (run `pwd` and compare). See the "Critical: Worktree Git Discipline" block in Protocol 91 Step 3 for the full pre-operation checklist.

### Step 4: Implement

Execute each step from the implementation plan in order.

**Rules during implementation**:

- Follow `docs/best-practices/` for all code written
- Follow the implementation order in the plan
- If you hit a spec gap (something not covered by the spec), **stop and report** — do not make unilateral decisions
- If the scope is larger than the plan described, **stop and report**
- After each logical chunk of work, verify your changes are still building

**After schema/model changes** (if applicable):

- Run type generation if your project uses generated types from the schema
- Verify generated types are committed

**Seed data**: If the plan requires seed data changes, make them and verify they load correctly.

**End-to-end spec maintenance**: If a committed automated spec exists for the feature under test, keep it in sync with your changes. If the feature is new and a smoke test runbook exists, create the corresponding spec as part of the implementation. See `docs/project/3-software-architecture.md` → Testing Strategy for the two-tier approach.

### Step 5: Pre-Commit Verification

Before committing, verify:

**Test Harness Coverage Checklist (if the implementation includes any test script, test function, or validation harness)**: Complete the [Test Harness Coverage Checklist](#test-harness-coverage-checklist) before self-approving. Do not open the PR with known coverage gaps.

**Filter-Schema Canary Test Checklist (if this PR adds new filter parameters to a tool schema)**: Complete the [Filter-Schema Canary Test Checklist](#filter-schema-canary-test-checklist) before opening the PR. A missing canary test is a blocking code-review finding.

**Script-Accuracy Self-Check Checklist (if this PR is a documentation PR that describes script behavior)**: Complete the [Script-Accuracy Self-Check Checklist](#script-accuracy-self-check-checklist) before opening the PR. Verify each documented claim about input/output format, exit codes, option flags, and API calls against the actual script source.

**ShellCheck (if any `.sh` files were modified)**:

```bash
# If any .sh files are modified, run ShellCheck before committing
CHANGED_SH=$({ git diff --name-only --diff-filter=d; git ls-files --others --exclude-standard; } | grep '\.sh$' | sort -u || true)
if [ -n "$CHANGED_SH" ]; then
  echo "Running ShellCheck on modified .sh files..."
  # shellcheck disable=SC2086
  shellcheck --severity=warning $CHANGED_SH
fi
```

Fix all ShellCheck warnings before committing. Do not commit `.sh` files with ShellCheck violations — they will fail the CI `shellcheck.yml` check and trigger unnecessary review-loop churn. Workflow scripts must also be bash 3.2 compatible (macOS ships bash 3.2 by default); do not use `local -A`, `declare -A`, or other bash 4+-only syntax — use parallel indexed arrays instead (e.g., `local -a keys; local -a vals`). ShellCheck does not warn on this by default when the shebang is `#!/usr/bin/env bash`.

```bash
# Build — must succeed
[your build command]

# Lint — must pass with zero errors
[your lint command]

# Unit / integration tests — must pass
[your test command]

# End-to-end suite — run if a spec exists for the affected feature
[your e2e command]
```

Fix any failures before committing. Do not push a broken build.

### Step 6: Update CHANGELOG

Add an entry under `[Unreleased]` in `CHANGELOG.md`:

- Use the appropriate category: `Added`, `Changed`, `Fixed`, `Security`, `Deprecated`, `Removed`
- Write from the user's perspective: what can they now do / what is now fixed?
- If this PR fixes or adjusts an unreleased development that already has an `[Unreleased]` entry, update the existing entry instead of adding a new one; if the entry already describes the corrected behavior, no change is needed

**Duplicate-section prevention (check before writing)**: Before writing the CHANGELOG entry, read the existing `[Unreleased]` block and check whether a section header matching your target category already exists (e.g., `### Changed`, `### Added`, `### Fixed`). Apply the following rule:

- **Category section already exists** under `[Unreleased]`: append your bullet(s) to the existing section — do **not** create a new `### Category` header.
- **Category section does not exist** under `[Unreleased]`: create a new `### Category` header followed by your bullet(s).

After writing, run a quick sanity check to confirm there is exactly one instance of each used category header within the `[Unreleased]` block:

```bash
# Replace "Changed" with your actual category (Added, Fixed, etc.)
awk '/^## \[Unreleased\]/{found=1} /^## \[/{if(found && !/Unreleased/) exit} found' CHANGELOG.md | grep -c "^### Changed"
# Expected output: 1
```

If the count is greater than 1, merge the duplicate sections before staging.

**CHANGELOG format verification (before staging)**: After writing the CHANGELOG entry, verify the entry for the following defects and fix them in-place before staging:

1. **Trailing whitespace**: No line in the written entry should end with one or more whitespace characters. Note: intentional two-space Markdown hard line breaks (`<text>  ` with exactly two trailing spaces followed by a newline) are not trailing whitespace and must not be removed.
2. **Trailing blank lines**: The entry must not end with two or more consecutive blank lines.
3. **Link reference definitions**: If you renamed `[Unreleased]` to a versioned section (e.g., `## [1.2.3] - 2026-01-01`), verify that a corresponding link reference definition exists at the bottom of the file (e.g., `[1.2.3]: https://github.com/owner/repo/compare/v1.2.2...v1.2.3`). Run the check to catch any missing definitions:

   ```bash
   bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md
   ```

A quick shell check for trailing whitespace on pending CHANGELOG changes (run **before** `git add`, per the "before staging" timing requirement):

```bash
git diff CHANGELOG.md | grep '^+' | grep -E '[[:space:]]+$'
```

If this returns output, inspect each flagged line: leave intentional two-space Markdown hard line breaks (exactly two trailing spaces followed by a newline) intact, and fix any other trailing whitespace (e.g., a single trailing space, a tab, or three or more trailing spaces) before committing.

**MD047 trailing-newline check (before staging)**: After editing any markdown file, verify that every modified `.md` file ends with a newline (MD047). Run this check on each markdown file you are about to stage:

```bash
# Check each modified (non-deleted) or newly created .md file for a missing trailing newline (run before git add)
{ git diff --name-only --diff-filter=d; git ls-files --others --exclude-standard; } | grep '\.md$' | sort -u | while read -r f; do
  python3 -c "import sys; d=open(sys.argv[1],'rb').read(); sys.exit(0 if d.endswith(b'\n') else 1)" "$f" \
    || echo "MISSING trailing newline: $f"
done
```

If any file is flagged, append a newline to it (e.g., `echo "" >> <file>` or reopen and save in your editor) before staging.

### Step 7: Commit & Push

```bash
git add [files]
git commit -m "feat([scope]): [description]"
git push -u origin feature/[slug]
```

Use Conventional Commits (see `docs/best-practices/2-version-control.md`).

### Step 8: Open PR (Draft)

**Board membership check (mandatory — before opening the PR)**: Before running `gh pr create`, call `ensure_on_project_board <issue_number> "In Development"` (sourcing `scripts/development-workflow/workflow-lib.sh`). If the issue is already on the project board, this is a no-op. If it is not, the function adds it and sets initial status to "In Development". On any API failure, the function logs a warning and continues — this step must never block the PR creation.

Open a **draft** PR targeting `develop` with:

- **Title**: `feat([scope]): [feature-name]`
- **Description**:
  - What was implemented
  - Link to spec and plan
  - Test plan (how to validate)
  - Any deviations from the plan (with justification)
  - CHANGELOG entry preview

**Pre-PR-create base-branch guard (mandatory — run before every `gh pr create`)**:

Before running `gh pr create`, verify that the current branch was actually cut from `develop` and confirm the intended base matches:

```bash
# 1. Verify the current branch descends from origin/develop (not from main or another branch)
if ! git merge-base --is-ancestor origin/develop HEAD; then
  echo "ERROR: Current branch does not descend from origin/develop. Verify the branch was cut from develop before opening the PR."
  exit 1
fi
echo "Base-branch guard passed: branch descends from origin/develop"
```

**Post-create base-branch assertion (mandatory — run immediately after `gh pr create`)**:

```bash
gh pr create --draft --base develop --title "feat([scope]): [feature-name]" --body "..."
PR_NUMBER=$(gh pr view --json number -q '.number')

# Assert the opened PR targets develop
ACTUAL_BASE=$(gh pr view "$PR_NUMBER" --json baseRefName -q '.baseRefName')
if [ "$ACTUAL_BASE" != "develop" ]; then
  echo "ERROR: PR was created with base '$ACTUAL_BASE' instead of 'develop'. Closing the malformed PR."
  gh pr close "$PR_NUMBER" --comment "Closed: PR was opened against wrong base branch '$ACTUAL_BASE'. Will reopen against develop."
  exit 1
fi
echo "Post-create assertion passed: PR base is '$ACTUAL_BASE'"
```

**Important**: Always use `--base develop` to explicitly target the `develop` branch. This prevents accidental PR creation to `main` or other branches. The pre-create guard and post-create assertion above are the enforcement mechanism — do not skip them.

### Step 9: Handoff to Work Item Runner

After the draft PR exists, the **Work Item Runner** owns the rest of the lifecycle for this item:

- Run the internal code review gate (`code-reviewer` / `03-review-implementation-protocol.md`) on the draft PR
- Run the automated reviewer loop and CI loop to completion
- Apply `ready-for-human-review` and move the tracker to **Development in Review** when the PR is human-ready
- Stop only when the PR is waiting on human review / merge or the run has escalated

**Label derivation rule**: The `ready-for-regression` label requirement is determined by the **branch prefix**, not by the content of the PR. `feature/*` branches always require `ready-for-regression` regardless of whether the changes are code, documentation, or configuration. See `91-orchestrate-work-protocol.md` Step 8a for the full branch-prefix-to-label table.

**Pre-label ordering gate (hard sequential gate — do not skip)**:

Before applying any readiness label, execute and verify **every item** in this two-phase checklist. Do not collapse phases or apply labels simultaneously. Each item requires a specific command to run and a pass condition to confirm — skipping any item is a protocol violation.

**Phase 1 checklist — run ALL of these before applying `ready-for-regression`**:

Step 1.1 — Confirm the reviewer loop summary comment exists:

```bash
# Must return at least one match. If empty: Step 7 has not run to completion — do not apply ready-for-regression.
gh pr view <pr_number> --json comments --jq '.comments[].body' \
  | grep -c "Automated Reviewer Loop Summary\|Reviewer Loop Summary\|No blocking PR feedback"
```

Pass condition: output is `1` or higher. **`pr-review-loop.sh` posts this comment automatically on `clean` and `escalate` exits**, so a count of `0` means the script did not run to completion. If `0`: re-run `./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch>` and wait for it to complete before proceeding.

Skip this check only when no review platforms are configured and the reviewer loop result was `skipped`.

Step 1.2 — Confirm all automated-reviewer threads are resolved:

```bash
# Must return empty output. Any line of output means unresolved bot threads exist — do not apply ready-for-regression.
gh api graphql -f query='
  query($owner:String!, $repo:String!, $number:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$number) {
        reviewThreads(first: 100) {
          nodes { isResolved comments(first: 1) { nodes { author { login } body } } }
        }
      }
    }
  }' -f owner=<owner> -f repo=<repo> -F number=<pr_number> \
  | jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | select(.comments.nodes[0].author.login as $a | ["coderabbitai","devin-ai-integration","greptile-apps"] | index($a) != null)
        | select((.comments.nodes[0].body // "") | test("✅ Addressed") | not)'
```

Pass condition: empty output. If non-empty: resolve or address each reported thread before proceeding.

Step 1.3 — Apply `ready-for-regression`:

```bash
# Only after Steps 1.1 and 1.2 pass:
gh pr edit <pr_number> --add-label "ready-for-regression"
```

**Phase 2 checklist — run ALL of these before applying `ready-for-human-review`**:

Step 2.1 — Wait for CI to settle (run the CI loop script):

```bash
# Must emit RESULT=green. RESULT=red or RESULT=timeout means do not apply ready-for-human-review.
./scripts/development-workflow/pr-ci-loop.sh <pr_number>
```

Pass condition: script exits with `RESULT=green`. If `RESULT=red`: fix the failing checks, push, and re-run from Phase 1. If `RESULT=timeout`: escalate to human.

Step 2.2 — Apply `ready-for-human-review`:

```bash
# Only after Step 2.1 passes:
gh pr edit <pr_number> --add-label "ready-for-human-review"
```

This two-phase sequence aligns with `91-orchestrate-work-protocol.md` Steps 7b → 8 → 8a → 8c. When invoked through the Work Item Runner, those steps enforce this gate automatically. When invoked standalone, execute each numbered step above explicitly and verify its pass condition before proceeding to the next.

If this protocol is invoked **standalone** rather than through the Work Item Runner, hand off manually by following `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` from the newly opened draft PR.

See `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` and `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`.

---

## Path 2: Refactor (Code Restructuring / Tech Debt)

**Criteria**: Code restructuring, tech-debt cleanup, or internal reorganization that has an approved implementation plan but no product spec.

### Step 1: Non-Negotiable Prep

Read **all** of the following before writing a single line of code. Do not skip.

1. `docs/specs/developments/[timestamp]_[slug]/2_[slug]_implementation-plan.md` — plan (what to restructure, in what order)
2. `docs/testing/[section]/[slug].smoke-test.md` — smoke test runbook (what "done" looks like)
3. `docs/project/3-software-architecture.md` — architecture patterns
4. `docs/best-practices/` — all best practice docs
5. Relevant existing code — read actual files for the areas you will modify
6. If an issue tracker exists for this item, follow `docs/workflow/development-workflow/integrations/issue-tracker.md` for `In Development (Refactor)` expectations before coding.
7. If your changes touch `.github/workflows/*.yml`, apply `## GitHub Actions Workflow Security Checklist` before opening the PR.

Extract from your reading:

- Every file or area you will touch
- The implementation order from the plan
- The acceptance criteria from the plan

**Dependency check**: Read the `Depends on` field in the plan. If any dependency is not yet Merged or Released, stop and report to the human.

### Step 1b: Pre-Implementation Scope Checklist

Complete this checklist **before writing any code**. It takes 5–10 minutes and prevents review round-trips caused by missed files, scope drift, or inconsistencies with related protocols.

1. **Enumerate all files** that need changes. List every file path explicitly.
2. **For each file**, describe the specific changes needed (e.g., "restructure section X", "rename Y to Z").
3. **Verify scope**: confirm all listed changes are within the refactor's stated scope. Remove anything that is not.
4. **Consider edge cases** before touching any file:
   - What if the branch already exists locally or remotely?
   - What if this runs inside a worktree?
   - Are there callers or dependents of the refactored code that must be updated in sync?
   - What behavior is preserved vs. changed?
5. **Cross-reference related protocols**: if any changed file references or is referenced by other protocol documents, read those documents and confirm your changes are consistent with them.
6. **Cross-reference consistency check** (required when the change modifies policy or rule text): grep for all existing references to the policy being changed **before writing any code**. Do not rely on your prior knowledge of where a policy lives — the grep is how you discover all locations. Run the search across all relevant directories and file types, list every matched file, and confirm each location will be updated consistently. Verify that headings, signal names, and language do not contradict each other across files. All matched files are candidates for the same update; explicitly confirm coverage of each before submitting.

   ```bash
   # Run this BEFORE writing any code — grep discovers all locations that must change together
   grep -r "key phrase" docs/ .cursor/ .claude/ .codex/ AGENTS.md README.md REVIEW.md --include="*.md" --include="*.mdc" -l
   ```

7. **Script-emitted signal verification** (required when the change writes or edits protocol text that cites a script-emitted signal value such as `REASON=`, `RESULT=`, or `STATUS=`): read the relevant source script and verify the exact string before committing. Do not cite a signal value from memory or from protocol text alone — the script is the authoritative source.

   ```bash
   # Example: verify the exact REASON= value emitted by pr-review-loop.sh
   grep -n 'REASON=' scripts/development-workflow/pr-review-loop.sh
   ```

Do not proceed to the Refactor Steps until this checklist is complete and all seven points are answered.

### Refactor Steps

1. If no blocking ambiguity remains, proceed without an extra approval pause; otherwise stop and ask the human
2. Branch from `develop` (slug: `[issue-id]-[slug]` with tracker, `[slug]` without):

```bash
git fetch origin
git checkout develop
git pull origin develop
git checkout -b refactor/[branch-slug]
```

**Worktree context (`BATCH_CONTEXT=true`)**: If this step runs inside an isolated worktree created by the item-orchestrator (Protocol 91 Step 3), skip the `git checkout develop` / `git checkout -b` commands above — the worktree was already created on the correct branch. Run only `git fetch origin` if you need the latest remote refs. Before running any git state-changing command, confirm your working directory is inside the worktree path, not the main repo root (run `pwd` and compare). See the "Critical: Worktree Git Discipline" block in Protocol 91 Step 3 for the full pre-operation checklist.

3. Implement following the plan order. Follow `docs/best-practices/` for all code written.

   **Mass-rename sub-step (applies when the refactor renames a path, identifier, or string across multiple files):**

   After performing any global substitution (find-and-replace, `sed`, `git mv`, or IDE rename), verify all three reference categories before committing:

   | Category                  | What to check                                                                                         | Example pattern                    |
   | ------------------------- | ----------------------------------------------------------------------------------------------------- | ---------------------------------- |
   | **Link targets**          | `[text](old-path)` — both the link target and `text` when text mirrors the old path                   | `[docs/ai/old](docs/ai/old)`       |
   | **Display text in links** | `[old-path-text](new-path)` — link target already updated but display text still shows the old string | `[docs/ai/old](docs/workflow/new)` |
   | **Non-link occurrences**  | Bare old-string in prose, code blocks, directory trees, YAML values, and shell scripts                | `docs/ai/old` inside a code fence  |

   Run a residual-occurrence check immediately after the substitution and before staging:

   ```bash
   # Replace "old-string" with the actual old path / identifier being renamed
   grep -r "old-string" . --include="*.md" --include="*.mdc" --include="*.yaml" --include="*.yml" --include="*.sh" \
     --exclude-dir=".git" --exclude-dir="worktrees" -l
   # Output should be empty, or contain only files where the old string
   # appears intentionally as subject-matter text (e.g., a CHANGELOG entry
   # describing the rename, or a comment explaining the old name).
   ```

   For each file listed in the output:
   1. Open it and confirm whether the occurrence is intentional (e.g., historical CHANGELOG entry, explanatory comment) or a missed substitution.
   2. Fix every missed substitution before staging.
   3. Re-run the check until the output contains only intentional occurrences.

4. If scope is larger than the plan described, **stop and report**
5. Verify: build, lint, tests pass; run e2e suite if a spec exists for the affected area.

   **Test Harness Coverage Checklist (if the implementation includes any test script, test function, or validation harness)**: Complete the [Test Harness Coverage Checklist](#test-harness-coverage-checklist) before self-approving. Do not open the PR with known coverage gaps.

   **Filter-Schema Canary Test Checklist (if this PR adds new filter parameters to a tool schema)**: Complete the [Filter-Schema Canary Test Checklist](#filter-schema-canary-test-checklist) before opening the PR. A missing canary test is a blocking code-review finding.

   **Script-Accuracy Self-Check Checklist (if this PR is a documentation PR that describes script behavior)**: Complete the [Script-Accuracy Self-Check Checklist](#script-accuracy-self-check-checklist) before opening the PR. Verify each documented claim about input/output format, exit codes, option flags, and API calls against the actual script source.

   If any `.sh` files were modified, run ShellCheck before committing:

   ```bash
   CHANGED_SH=$({ git diff --name-only --diff-filter=d; git ls-files --others --exclude-standard; } | grep '\.sh$' | sort -u || true)
   if [ -n "$CHANGED_SH" ]; then
     echo "Running ShellCheck on modified .sh files..."
     # shellcheck disable=SC2086
     shellcheck --severity=warning $CHANGED_SH
   fi
   ```

   Fix all ShellCheck warnings before committing. Workflow scripts must also be bash 3.2 compatible (macOS ships bash 3.2 by default); do not use `local -A`, `declare -A`, or other bash 4+-only syntax — use parallel indexed arrays instead (e.g., `local -a keys; local -a vals`). ShellCheck does not warn on this by default when the shebang is `#!/usr/bin/env bash`.

6. Update CHANGELOG under `[Unreleased]` with a `Changed` entry (skip if this refactor adjusts unreleased work that already has an entry — update the existing entry instead, or leave it unchanged if it already describes the correct behavior).

   **Duplicate-section prevention (check before writing)**: Before writing the CHANGELOG entry, read the existing `[Unreleased]` block and check whether a `### Changed` section header already exists. If it does, append your bullet(s) to the existing section — do **not** create a new `### Changed` header. If `### Changed` does not yet exist under `[Unreleased]`, create it. After writing, verify that the header appears exactly once within the `[Unreleased]` block: `awk '/^## \[Unreleased\]/{found=1} /^## \[/{if(found && !/Unreleased/) exit} found' CHANGELOG.md | grep -c "^### Changed"` — expected output: 1; if greater than 1, merge the duplicate sections before staging.

   **CHANGELOG format verification (before staging)**: After writing the CHANGELOG entry, verify the entry for the following defects and fix them in-place before staging:
   1. **Trailing whitespace**: No line in the written entry should end with one or more whitespace characters. Note: intentional two-space Markdown hard line breaks (`<text>  ` with exactly two trailing spaces followed by a newline) are not trailing whitespace and must not be removed.
   2. **Trailing blank lines**: The entry must not end with two or more consecutive blank lines.
   3. **Link reference definitions**: If you renamed `[Unreleased]` to a versioned section (e.g., `## [1.2.3] - 2026-01-01`), verify that a corresponding link reference definition exists at the bottom of the file (e.g., `[1.2.3]: https://github.com/owner/repo/compare/v1.2.2...v1.2.3`). Run the check to catch any missing definitions:

      ```bash
      bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md
      ```

   A quick shell check for trailing whitespace on pending CHANGELOG changes (run **before** `git add`, per the "before staging" timing requirement):

   ```bash
   git diff CHANGELOG.md | grep '^+' | grep -E '[[:space:]]+$'
   ```

   If this returns output, inspect each flagged line: leave intentional two-space Markdown hard line breaks (exactly two trailing spaces followed by a newline) intact, and fix any other trailing whitespace (e.g., a single trailing space, a tab, or three or more trailing spaces) before committing.

   **MD047 trailing-newline check (before staging)**: After editing any markdown file, verify that every modified `.md` file ends with a newline (MD047). Run this check on each markdown file you are about to stage:

   ```bash
   # Check each modified (non-deleted) or newly created .md file for a missing trailing newline (run before git add)
   { git diff --name-only --diff-filter=d; git ls-files --others --exclude-standard; } | grep '\.md$' | sort -u | while read -r f; do
     python3 -c "import sys; d=open(sys.argv[1],'rb').read(); sys.exit(0 if d.endswith(b'\n') else 1)" "$f" \
       || echo "MISSING trailing newline: $f"
   done
   ```

   If any file is flagged, append a newline to it (e.g., `echo "" >> <file>` or reopen and save in your editor) before staging.

7. Commit: `refactor([scope]): [description]`
8. Push branch to remote
9. **Board membership check (mandatory — before opening the PR)**: Before running `gh pr create`, call `ensure_on_project_board <issue_number> "In Development"` (sourcing `scripts/development-workflow/workflow-lib.sh`). If the issue is already on the project board, this is a no-op. If it is not, the function adds it and sets initial status to "In Development". On any API failure, the function logs a warning and continues — this step must never block the PR creation.
10. Open a **draft** PR targeting `develop` with refactor-appropriate metadata (do **not** reuse Path 1 Step 8 verbatim — that path uses `feat(...)` and a spec link):
    - **Title**: `refactor([scope]): [short description]`
    - **Description**:
      - What was refactored and why
      - Link to the **implementation plan** only (no spec)
      - Test plan (how to validate)
      - Any deviations from the plan (with justification)
      - CHANGELOG entry preview

**Pre-PR-create base-branch guard (mandatory — run before every `gh pr create`)**:

```bash
# 1. Verify the current branch descends from origin/develop
if ! git merge-base --is-ancestor origin/develop HEAD; then
  echo "ERROR: Current branch does not descend from origin/develop. Verify the branch was cut from develop before opening the PR."
  exit 1
fi
echo "Base-branch guard passed: branch descends from origin/develop"
```

**Post-create base-branch assertion (mandatory — run immediately after `gh pr create`)**:

```bash
gh pr create --draft --base develop --title "refactor([scope]): [short description]" --body "..."
PR_NUMBER=$(gh pr view --json number -q '.number')

# Assert the opened PR targets develop
ACTUAL_BASE=$(gh pr view "$PR_NUMBER" --json baseRefName -q '.baseRefName')
if [ "$ACTUAL_BASE" != "develop" ]; then
  echo "ERROR: PR was created with base '$ACTUAL_BASE' instead of 'develop'. Closing the malformed PR."
  gh pr close "$PR_NUMBER" --comment "Closed: PR was opened against wrong base branch '$ACTUAL_BASE'. Will reopen against develop."
  exit 1
fi
echo "Post-create assertion passed: PR base is '$ACTUAL_BASE'"
```

**Important**: Always use `--base develop` to explicitly target the `develop` branch. The pre-create guard and post-create assertion above are the enforcement mechanism — do not skip them.

11. Hand off to the Work Item Runner with the same lifecycle expectations as Path 1 Step 9 (internal review gate, automated reviewer loop, CI, labels). **Label derivation rule**: `refactor/*` branches always require `ready-for-regression` based on branch prefix, not content type. See `91-orchestrate-work-protocol.md` Step 8a for the full branch-prefix-to-label table. See `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` and `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`.

---

## Path 3: Fast Track (Bug / Simple Change)

**Criteria check — all must be true**:

- [ ] The scope is clear and bounded from the start
- [ ] ≤ 3 files will be modified (estimate before starting)
- [ ] No new database schema migrations
- [ ] No new architectural patterns
- [ ] Human provided a clear, self-contained brief
- [ ] **No multi-layer scope signals** — the issue title, body, and any linked spec/plan do not contain concrete signals that the change spans more than one architectural layer (see "Cross-layer scope check" below)

**Cross-layer scope check**: Apply the deterministic decision rule in
[`91-orchestrate-work-protocol.md` Step 2 — Cross-layer scope check](./91-orchestrate-work-protocol.md)
before selecting Fast Track. That section is the authoritative definition of multi-layer signals, the inspection scope, and the routing decision.

**If any criterion fails**: Use the Full Pipeline instead.

**If scope expands during implementation**: Stop immediately. Report to the human. Do not silently expand scope.

### Step 1: Read Brief

Read the brief. If the work item exists in an issue tracker, follow `docs/workflow/development-workflow/integrations/issue-tracker.md` for `In Development (Fast Track)` expectations.

If your changes touch `.github/workflows/*.yml`, apply `## GitHub Actions Workflow Security Checklist` before opening the PR.

#### Verify-Before-Add (mandatory for tickets claiming a feature is missing or unavailable)

When the issue claims that a feature, field, or capability is "missing," "unavailable," or "not working" — but does not include a stack trace, failing test, or other reproducible artifact — you must verify the gap exists before writing any code.

**Apply this check when the ticket uses language such as:**

- "X is not available in Y"
- "Y does not return X"
- "X is missing from the response"
- "X is not supported"

**Do not apply this check to:** confirmed bugs with stack traces, failing automated tests, or issues with explicit reproduction steps that you have already verified independently.

**Verification steps (run before Step 1b):**

1. **Reproduce the reported gap independently** using the exact steps described in the ticket — do not assume the reporter's description is complete or correct.
2. **If the gap cannot be reproduced** (the feature already exists or works as described): cancel the ticket, post a comment explaining the finding, and stop. Do not implement anything.
3. **If the gap is confirmed reproducible**: continue to Step 1b and proceed with implementation.

> **Example**: A ticket claims "`qualificationDate` is not available in `search_projects`." Before writing any code, call `search_projects` with a `fields` projection that includes `qualificationDate`. If the field is returned, the feature already exists — the ticket is based on a misreading of the API description. Cancel the ticket and document the finding. Only proceed if `qualificationDate` is genuinely absent and cannot be obtained via any supported projection.

### Step 1b: Pre-Implementation Scope Checklist

Complete this checklist **before writing any code**. It takes 5–10 minutes and prevents review round-trips caused by missed files, scope drift, or inconsistencies with related files.

1. **Enumerate all files** that need changes (list every file path explicitly).
2. **For each file**, describe the specific changes needed.
3. **Verify scope**: confirm all listed changes are within the issue's stated scope. Remove anything that is not.
4. **Consider edge cases**: what if the branch already exists locally or remotely? What if this runs in a worktree? What are the failure modes?
5. **Cross-reference related protocols**: if any changed file references or is referenced by other protocol documents, read those documents and confirm your changes are consistent with them.
6. **Cross-reference consistency check** (required when the change modifies policy or rule text): grep for all existing references to the policy being changed **before writing any code**. Do not rely on your prior knowledge of where a policy lives — the grep is how you discover all locations. Run the search across all relevant directories and file types, list every matched file, and confirm each location will be updated consistently. Verify that headings, signal names, and language do not contradict each other across files. All matched files are candidates for the same update; explicitly confirm coverage of each before submitting.

   ```bash
   # Run this BEFORE writing any code — grep discovers all locations that must change together
   grep -r "key phrase" docs/ .cursor/ .claude/ .codex/ AGENTS.md README.md REVIEW.md --include="*.md" --include="*.mdc" -l
   ```

7. **Script-emitted signal verification** (required when the change writes or edits protocol text that cites a script-emitted signal value such as `REASON=`, `RESULT=`, or `STATUS=`): read the relevant source script and verify the exact string before committing. Do not cite a signal value from memory or from protocol text alone — the script is the authoritative source.

   ```bash
   # Example: verify the exact REASON= value emitted by pr-review-loop.sh
   grep -n 'REASON=' scripts/development-workflow/pr-review-loop.sh
   ```

Do not proceed to Step 2 until this checklist is complete and all seven points are answered.

### Step 2: Ambiguity Check

If no blocking ambiguity remains, proceed without an extra approval pause; otherwise stop and ask the human.

### Step 3: Branch

Branch from `develop` (slug: `[issue-id]-[slug]` with tracker, `[slug]` without):

**Integration-branch check**: Before creating the branch, check whether the work item carries an `integration-branch:<slug>` label (the orchestrator will have noted this in the handoff). If the label is present, use `develop-<slug>` as the base branch instead of `develop`:

```bash
# Standard:
git checkout develop && git pull origin develop
# If integration-branch:<slug> label is present, use develop-<slug> instead:
# git checkout develop-<slug> && git pull origin develop-<slug>
git checkout -b fix/[branch-slug]
```

The PR opened at the end of this path must target `develop-<slug>` when the label is present. If the integration branch does not exist yet, the orchestrator should have created it before dispatching this protocol — do not create it here; instead, stop and inform the Work Item Runner.

**Worktree context (`BATCH_CONTEXT=true`)**: If this step runs inside an isolated worktree created by the item-orchestrator (Protocol 91 Step 3), skip the `git checkout develop` / `git checkout -b` commands above — the worktree was already created on the correct branch. Run only `git fetch origin` if you need the latest remote refs. Before running any git state-changing command, confirm your working directory is inside the worktree path, not the main repo root (run `pwd` and compare). See the "Critical: Worktree Git Discipline" block in Protocol 91 Step 3 for the full pre-operation checklist.

### Step 4: Implement

Implement the fix.

### Step 5: Verify

Verify: build, lint, tests pass; run e2e suite if a spec exists for the affected area.

**Test Harness Coverage Checklist (if the implementation includes any test script, test function, or validation harness)**: Complete the [Test Harness Coverage Checklist](#test-harness-coverage-checklist) before self-approving. Do not open the PR with known coverage gaps.

**Filter-Schema Canary Test Checklist (if this PR adds new filter parameters to a tool schema)**: Complete the [Filter-Schema Canary Test Checklist](#filter-schema-canary-test-checklist) before opening the PR. A missing canary test is a blocking code-review finding.

**Script-Accuracy Self-Check Checklist (if this PR is a documentation PR that describes script behavior)**: Complete the [Script-Accuracy Self-Check Checklist](#script-accuracy-self-check-checklist) before opening the PR. Verify each documented claim about input/output format, exit codes, option flags, and API calls against the actual script source.

**ShellCheck (if any `.sh` files were modified)**:

```bash
CHANGED_SH=$({ git diff --name-only --diff-filter=d; git ls-files --others --exclude-standard; } | grep '\.sh$' | sort -u || true)
if [ -n "$CHANGED_SH" ]; then
  echo "Running ShellCheck on modified .sh files..."
  # shellcheck disable=SC2086
  shellcheck --severity=warning $CHANGED_SH
fi
```

Fix all ShellCheck warnings before committing. Do not commit `.sh` files with ShellCheck violations — they will fail the CI `shellcheck.yml` check and trigger unnecessary review-loop churn. Workflow scripts must also be bash 3.2 compatible (macOS ships bash 3.2 by default); do not use `local -A`, `declare -A`, or other bash 4+-only syntax — use parallel indexed arrays instead (e.g., `local -a keys; local -a vals`). ShellCheck does not warn on this by default when the shebang is `#!/usr/bin/env bash`.

### Step 6: Update CHANGELOG

Update CHANGELOG under `[Unreleased]` with a `Fixed` entry (skip if this fixes unreleased work that already has an entry — update the existing entry instead, or leave it unchanged if it already describes the correct behavior).

**Duplicate-section prevention (check before writing)**: Before writing the CHANGELOG entry, read the existing `[Unreleased]` block and check whether a `### Fixed` section header already exists. If it does, append your bullet(s) to the existing section — do **not** create a new `### Fixed` header. If `### Fixed` does not yet exist under `[Unreleased]`, create it. After writing, verify that the header appears exactly once within the `[Unreleased]` block: `awk '/^## \[Unreleased\]/{found=1} /^## \[/{if(found && !/Unreleased/) exit} found' CHANGELOG.md | grep -c "^### Fixed"` — expected output: 1; if greater than 1, merge the duplicate sections before staging.

**CHANGELOG format verification (before staging)**: After writing the CHANGELOG entry, verify the entry for the following defects and fix them in-place before staging:

1. **Trailing whitespace**: No line in the written entry should end with one or more whitespace characters. Note: intentional two-space Markdown hard line breaks (`<text>  ` with exactly two trailing spaces followed by a newline) are not trailing whitespace and must not be removed.
2. **Trailing blank lines**: The entry must not end with two or more consecutive blank lines.
3. **Link reference definitions**: If you renamed `[Unreleased]` to a versioned section (e.g., `## [1.2.3] - 2026-01-01`), verify that a corresponding link reference definition exists at the bottom of the file (e.g., `[1.2.3]: https://github.com/owner/repo/compare/v1.2.2...v1.2.3`). Run the check to catch any missing definitions:

   ```bash
   bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md
   ```

A quick shell check for trailing whitespace on pending CHANGELOG changes (run **before** `git add`, per the "before staging" timing requirement):

```bash
git diff CHANGELOG.md | grep '^+' | grep -E '[[:space:]]+$'
```

If this returns output, inspect each flagged line: leave intentional two-space Markdown hard line breaks (exactly two trailing spaces followed by a newline) intact, and fix any other trailing whitespace (e.g., a single trailing space, a tab, or three or more trailing spaces) before committing.

**MD047 trailing-newline check (before staging)**: After editing any markdown file, verify that every modified `.md` file ends with a newline (MD047). Run this check on each markdown file you are about to stage:

```bash
# Check each modified (non-deleted) or newly created .md file for a missing trailing newline (run before git add)
{ git diff --name-only --diff-filter=d; git ls-files --others --exclude-standard; } | grep '\.md$' | sort -u | while read -r f; do
  python3 -c "import sys; d=open(sys.argv[1],'rb').read(); sys.exit(0 if d.endswith(b'\n') else 1)" "$f" \
    || echo "MISSING trailing newline: $f"
done
```

If any file is flagged, append a newline to it (e.g., `echo "" >> <file>` or reopen and save in your editor) before staging.

### Step 7: Commit & Push

```bash
git add [files]
git commit -m "fix([scope]): [description]"
git push -u origin fix/[branch-slug]
```

### Step 8: Open PR (Draft)

**Board membership check (mandatory — before opening the PR)**: Before running `gh pr create`, call `ensure_on_project_board <issue_number> "In Development"` (sourcing `scripts/development-workflow/workflow-lib.sh`). If the issue is already on the project board, this is a no-op. If it is not, the function adds it and sets initial status to "In Development". On any API failure, the function logs a warning and continues — this step must never block the PR creation.

Open a **draft** PR targeting `develop` using the same structure as Path 1 `### Step 8: Open PR (Draft)`, but with a **`fix(...)`** title and a fix-focused description (omit spec/plan links when none exist):

**Pre-PR-create base-branch guard (mandatory — run before every `gh pr create`)**:

```bash
# 1. Verify the current branch descends from origin/develop
if ! git merge-base --is-ancestor origin/develop HEAD; then
  echo "ERROR: Current branch does not descend from origin/develop. Verify the branch was cut from develop before opening the PR."
  exit 1
fi
echo "Base-branch guard passed: branch descends from origin/develop"
```

**Post-create base-branch assertion (mandatory — run immediately after `gh pr create`)**:

```bash
gh pr create --draft --base develop --title "fix([scope]): [description]" --body "..."
PR_NUMBER=$(gh pr view --json number -q '.number')

# Assert the opened PR targets develop
ACTUAL_BASE=$(gh pr view "$PR_NUMBER" --json baseRefName -q '.baseRefName')
if [ "$ACTUAL_BASE" != "develop" ]; then
  echo "ERROR: PR was created with base '$ACTUAL_BASE' instead of 'develop'. Closing the malformed PR."
  gh pr close "$PR_NUMBER" --comment "Closed: PR was opened against wrong base branch '$ACTUAL_BASE'. Will reopen against develop."
  exit 1
fi
echo "Post-create assertion passed: PR base is '$ACTUAL_BASE'"
```

**Important**: Always use `--base develop` to explicitly target the `develop` branch. This prevents accidental PR creation to `main` or other branches. The pre-create guard and post-create assertion above are the enforcement mechanism — do not skip them.

### Step 9: Handoff to Work Item Runner

After the draft PR exists, the **Work Item Runner** owns the rest of the lifecycle:

- Run the internal code review gate (`code-reviewer` / `03-review-implementation-protocol.md`) on the draft PR
- Run the automated reviewer loop and CI loop to completion
- Apply `ready-for-human-review` and move the tracker to **Development in Review** when the PR is human-ready
- Stop only when the PR is waiting on human review / merge or the run has escalated

**Label derivation rule**: `fix/*` branches always require `ready-for-regression` based on branch prefix, not content type. See `91-orchestrate-work-protocol.md` Step 8a for the full branch-prefix-to-label table.

**`BATCH_CONTEXT=true` note — Step 7b is mandatory in parallel dispatch**: In parallel batch dispatches, agents follow a compressed execution path and may inadvertently omit Step 7b. The three steps below (Phase 1) are **not optional** regardless of dispatch mode — treat each as a mandatory checkpoint before entering Step 8.

**Phase 1 checklist — run ALL of these before applying `ready-for-regression`**:

Step 1.1 — Confirm the reviewer loop summary comment exists:

```bash
# Must return at least one match. If empty: Step 7 has not run to completion — do not apply ready-for-regression.
gh pr view <pr_number> --json comments --jq '.comments[].body' \
  | grep -c "Automated Reviewer Loop Summary\|Reviewer Loop Summary\|No blocking PR feedback"
```

Pass condition: output is `1` or higher. **`pr-review-loop.sh` posts this comment automatically on `clean` and `escalate` exits**, so a count of `0` means the script did not run to completion. If `0`: re-run `./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch>` and wait for it to complete before proceeding.

Skip this check only when no review platforms are configured and the reviewer loop result was `skipped`.

Step 1.2 — Confirm all automated-reviewer threads are resolved:

```bash
# Must return empty output. Any line of output means unresolved bot threads exist — do not apply ready-for-regression.
gh api graphql -f query='
  query($owner:String!, $repo:String!, $number:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$number) {
        reviewThreads(first: 100) {
          nodes { isResolved comments(first: 1) { nodes { author { login } body } } }
        }
      }
    }
  }' -f owner=<owner> -f repo=<repo> -F number=<pr_number> \
  | jq '.data.repository.pullRequest.reviewThreads.nodes[]
        | select(.isResolved == false)
        | select(.comments.nodes[0].author.login as $a | ["coderabbitai","devin-ai-integration","greptile-apps"] | index($a) != null)
        | select((.comments.nodes[0].body // "") | test("✅ Addressed") | not)'
```

Pass condition: empty output. If non-empty: resolve or address each reported thread before proceeding.

Step 1.3 — Apply `ready-for-regression`:

```bash
# Only after Steps 1.1 and 1.2 pass:
gh pr edit <pr_number> --add-label "ready-for-regression"
```

For Phase 2 (`ready-for-human-review` gate) and the full pre-label ordering contract, follow Path 1 `### Step 9: Handoff to Work Item Runner`. When invoked through the Work Item Runner, `91-orchestrate-work-protocol.md` Steps 7b → 8 → 8a → 8c enforce this gate automatically. When invoked standalone, execute each numbered step explicitly and verify its pass condition before proceeding to the next.

See `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` and `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`.

---

## Path 4: Hotfix (Critical Production Bug)

**Criteria**: Active production incident or critical security issue.

### Step 1: Read Brief

Read the incident brief from the human.

If your changes touch `.github/workflows/*.yml`, apply `## GitHub Actions Workflow Security Checklist` before opening the PR.

### Step 2: Confirm Production

Confirm it's a production-only issue (not a dev/staging issue).

### Step 2b: Pre-Implementation Scope Checklist

Complete this checklist **before writing any code**. It takes 5–10 minutes and prevents review round-trips caused by missed files or scope creep in a production-critical context.

1. **Enumerate all files** that need changes (list every file path explicitly).
2. **For each file**, describe the specific changes needed.
3. **Verify scope**: confirm all listed changes address the production incident directly. Remove anything that is not strictly necessary.
4. **Consider edge cases**: what if the branch already exists locally or remotely? What is the minimal safe change? Are there related files that must stay consistent?
5. **Cross-reference related protocols**: if the fix touches shared utilities or configuration files used by other flows, confirm consistency.
6. **Cross-reference consistency check** (required when the fix modifies policy or rule text): grep for all existing references to the policy being changed **before writing any code**. Do not rely on your prior knowledge of where a policy lives — the grep is how you discover all locations. Run the search across all relevant directories and file types, list every matched file, and confirm each location will be updated consistently. Verify that headings, signal names, and language do not contradict each other across files. All matched files are candidates for the same update; explicitly confirm coverage of each before submitting.

   ```bash
   # Run this BEFORE writing any code — grep discovers all locations that must change together
   grep -r "key phrase" docs/ .cursor/ .claude/ .codex/ AGENTS.md README.md REVIEW.md --include="*.md" --include="*.mdc" -l
   ```

7. **Script-emitted signal verification** (required when the fix writes or edits protocol text that cites a script-emitted signal value such as `REASON=`, `RESULT=`, or `STATUS=`): read the relevant source script and verify the exact string before committing. Do not cite a signal value from memory or from protocol text alone — the script is the authoritative source.

   ```bash
   # Example: verify the exact REASON= value emitted by pr-review-loop.sh
   grep -n 'REASON=' scripts/development-workflow/pr-review-loop.sh
   ```

Do not proceed to Step 3 until this checklist is complete and all seven points are answered.

### Step 3: Branch

Branch from `main` (slug: `[issue-id]-[slug]` with tracker, `[slug]` without):

```bash
git fetch origin
git checkout main
git pull origin main
git checkout -b hotfix/[branch-slug]
```

**Worktree context (`BATCH_CONTEXT=true`)**: If this step runs inside an isolated worktree created by the item-orchestrator (Protocol 91 Step 3), skip the `git checkout main` / `git checkout -b` commands above — the worktree was already created on the correct branch. Run only `git fetch origin` if you need the latest remote refs. Before running any git state-changing command, confirm your working directory is inside the worktree path, not the main repo root (run `pwd` and compare). See the "Critical: Worktree Git Discipline" block in Protocol 91 Step 3 for the full pre-operation checklist.

### Step 4: Implement

Implement the minimal fix (do not bundle unrelated changes).

**Pre-commit edge-case reasoning (required before your first commit)**: Before writing any code or making any change, briefly reason through edge cases for the fix:

- Are there inputs or response formats where the change behaves unexpectedly?
- For regex or string matching changes, test against both the false-positive case (what you are trying to allow) and the true-positive case (what you must still catch), including cases where both appear in the same string or line.
- For conditional or filtering logic, verify that a condition you add to suppress a false positive does not also suppress a genuine match when both appear together in the same input.

### Step 5: Verify

Verify: build, lint, tests pass.

**Test Harness Coverage Checklist (if the implementation includes any test script, test function, or validation harness)**: Complete the [Test Harness Coverage Checklist](#test-harness-coverage-checklist) before self-approving. Do not open the PR with known coverage gaps.

**Filter-Schema Canary Test Checklist (if this PR adds new filter parameters to a tool schema)**: Complete the [Filter-Schema Canary Test Checklist](#filter-schema-canary-test-checklist) before opening the PR. A missing canary test is a blocking code-review finding.

**Script-Accuracy Self-Check Checklist (if this PR is a documentation PR that describes script behavior)**: Complete the [Script-Accuracy Self-Check Checklist](#script-accuracy-self-check-checklist) before opening the PR. Verify each documented claim about input/output format, exit codes, option flags, and API calls against the actual script source.

**ShellCheck (if any `.sh` files were modified)**:

```bash
CHANGED_SH=$({ git diff --name-only --diff-filter=d; git ls-files --others --exclude-standard; } | grep '\.sh$' | sort -u || true)
if [ -n "$CHANGED_SH" ]; then
  echo "Running ShellCheck on modified .sh files..."
  # shellcheck disable=SC2086
  shellcheck --severity=warning $CHANGED_SH
fi
```

Fix all ShellCheck warnings before committing. Do not commit `.sh` files with ShellCheck violations — they will fail the CI `shellcheck.yml` check and trigger unnecessary review-loop churn. Workflow scripts must also be bash 3.2 compatible (macOS ships bash 3.2 by default); do not use `local -A`, `declare -A`, or other bash 4+-only syntax — use parallel indexed arrays instead (e.g., `local -a keys; local -a vals`). ShellCheck does not warn on this by default when the shebang is `#!/usr/bin/env bash`.

### Step 6: Update CHANGELOG

**Hotfix CHANGELOG exception — versioned section, not `[Unreleased]`**: Because a hotfix patches already-released code on `main`, its CHANGELOG entry must go in a **new versioned section** (e.g., `[1.0.1] - YYYY-MM-DD`), not under `[Unreleased]`. The `[Unreleased]` block contains work that has not yet been released; a hotfix is released immediately when the `hotfix/*` PR merges to `main`.

To write the entry correctly:

1. Determine the next patch version from the most recent released section header (e.g., if the latest is `[1.0.0]`, the hotfix version is `[1.0.1]`).
2. Insert the new versioned section **directly below `[Unreleased]`** (above all prior versioned sections). `auto-tag-release.yml` extracts the hotfix version by finding the first semver header (`## [X.Y.Z...]`) that appears after `[Unreleased]` in the file, so the hotfix section must be placed directly below `[Unreleased]`. The resulting structure should be:

```markdown
## [Unreleased]

## [1.0.1] - YYYY-MM-DD

### Fixed

- **Your hotfix description** (hotfix): brief user-facing summary of what was patched.

## [1.0.0] - YYYY-MM-DD
```

3. Do **not** add an entry under `[Unreleased]` for hotfix PRs.

**Duplicate-section prevention (check before writing)**: Before inserting the new versioned section, confirm no section with the same version number already exists in `CHANGELOG.md`. After writing, run: `grep -c "^## \[1\.0\.1\]" CHANGELOG.md` (replace `1.0.1` with the actual version) — expected output: 1. Also confirm `[Unreleased]` still appears before the new section (`grep -n "^## " CHANGELOG.md | head -3`).

> **Note for backport PRs**: When the hotfix content is backported to `develop` (Step 9 below), do **not** add another CHANGELOG entry. The versioned entry already exists in `CHANGELOG.md` on `main`, and the backport merge will carry it to `develop` automatically.

**CHANGELOG format verification (before staging)**: After writing the CHANGELOG entry, verify the entry for the following defects and fix them in-place before staging:

1. **Trailing whitespace**: No line in the written entry should end with one or more whitespace characters. Note: intentional two-space Markdown hard line breaks (`<text>  ` with exactly two trailing spaces followed by a newline) are not trailing whitespace and must not be removed.
2. **Trailing blank lines**: The entry must not end with two or more consecutive blank lines.
3. **Link reference definitions**: If you renamed `[Unreleased]` to a versioned section (e.g., `## [1.2.3] - 2026-01-01`), verify that a corresponding link reference definition exists at the bottom of the file (e.g., `[1.2.3]: https://github.com/owner/repo/compare/v1.2.2...v1.2.3`). Run the check to catch any missing definitions:

   ```bash
   bash scripts/lint/check-changelog-duplicate-headers.sh CHANGELOG.md
   ```

A quick shell check for trailing whitespace on pending CHANGELOG changes (run **before** `git add`, per the "before staging" timing requirement):

```bash
git diff CHANGELOG.md | grep '^+' | grep -E '[[:space:]]+$'
```

If this returns output, inspect each flagged line: leave intentional two-space Markdown hard line breaks (exactly two trailing spaces followed by a newline) intact, and fix any other trailing whitespace (e.g., a single trailing space, a tab, or three or more trailing spaces) before committing.

**MD047 trailing-newline check (before staging)**: After editing any markdown file, verify that every modified `.md` file ends with a newline (MD047). Run this check on each markdown file you are about to stage:

```bash
# Check each modified (non-deleted) or newly created .md file for a missing trailing newline (run before git add)
{ git diff --name-only --diff-filter=d; git ls-files --others --exclude-standard; } | grep '\.md$' | sort -u | while read -r f; do
  python3 -c "import sys; d=open(sys.argv[1],'rb').read(); sys.exit(0 if d.endswith(b'\n') else 1)" "$f" \
    || echo "MISSING trailing newline: $f"
done
```

If any file is flagged, append a newline to it (e.g., `echo "" >> <file>` or reopen and save in your editor) before staging.

### Step 7: Commit & Push

```bash
git add [files]
git commit -m "fix([scope]): [description] (hotfix)"
git push -u origin hotfix/[branch-slug]
```

### Step 8: Open PR (Draft)

**Board membership check (mandatory — before opening the PR)**: Before running `gh pr create`, call `ensure_on_project_board <issue_number> "In Development"` (sourcing `scripts/development-workflow/workflow-lib.sh`). If the issue is already on the project board, this is a no-op. If it is not, the function adds it and sets initial status to "In Development". On any API failure, the function logs a warning and continues — this step must never block the PR creation.

Open a **draft** PR targeting `main` by adapting Path 1 `### Step 8: Open PR (Draft)` for hotfix (`fix(...)` title with `(hotfix)` as needed, incident-focused body, target branch `main`):

**Pre-PR-create base-branch guard (mandatory — run before every `gh pr create`)**:

```bash
# 1. Verify the current branch descends from origin/main (hotfixes are cut from main)
if ! git merge-base --is-ancestor origin/main HEAD; then
  echo "ERROR: Current branch does not descend from origin/main. Verify the branch was cut from main before opening the hotfix PR."
  exit 1
fi
echo "Base-branch guard passed: branch descends from origin/main"
```

**Post-create base-branch assertion (mandatory — run immediately after `gh pr create`)**:

```bash
gh pr create --draft --base main --title "fix([scope]): [description] (hotfix)" --body "..."
PR_NUMBER=$(gh pr view --json number -q '.number')

# Assert the opened PR targets main
ACTUAL_BASE=$(gh pr view "$PR_NUMBER" --json baseRefName -q '.baseRefName')
if [ "$ACTUAL_BASE" != "main" ]; then
  echo "ERROR: PR was created with base '$ACTUAL_BASE' instead of 'main'. Closing the malformed PR."
  gh pr close "$PR_NUMBER" --comment "Closed: Hotfix PR was opened against wrong base branch '$ACTUAL_BASE'. Will reopen against main."
  exit 1
fi
echo "Post-create assertion passed: PR base is '$ACTUAL_BASE'"
```

**Important**: Use `--base main` for hotfixes (not `develop`). A hotfix merges to production first, then must be backported to `develop`. The pre-create guard and post-create assertion above are the enforcement mechanism — do not skip them.

### Step 9: Handoff to Work Item Runner

Hand off to the Work Item Runner per Path 1 `### Step 9: Handoff to Work Item Runner`. **Label derivation rule**: `hotfix/*` branches always require `ready-for-regression` based on branch prefix, not content type. See `91-orchestrate-work-protocol.md` Step 8a for the full branch-prefix-to-label table.

**After the `hotfix/*` PR merges to `main`**: perform the mandatory backport to prevent `main` and `develop` from drifting apart.

#### Backport process (mandatory)

The `hotfix/*` branch is **not** reused for the backport. Create a dedicated backport branch from `main` after the hotfix merge:

```bash
git fetch origin
git checkout -b backport/hotfix/[slug] origin/main
```

Open a PR targeting `develop`:

**Pre-PR-create base-branch guard (mandatory)**:

```bash
# Verify the backport branch descends from origin/main (it was cut from origin/main post-merge)
if ! git merge-base --is-ancestor origin/main HEAD; then
  echo "ERROR: Backport branch does not descend from origin/main. Verify the branch was created from origin/main after the hotfix merge."
  exit 1
fi
echo "Base-branch guard passed: backport branch descends from origin/main"
```

**Post-create base-branch assertion (mandatory)**:

```bash
gh pr create --draft --base develop \
  --title "chore(hotfix): backport [slug] to develop" \
  --body "Backports hotfix '[slug]' (merged to main) to keep develop in sync.

Closes the backport requirement for hotfix/[slug]."
PR_NUMBER=$(gh pr view --json number -q '.number')

# Assert the opened backport PR targets develop
ACTUAL_BASE=$(gh pr view "$PR_NUMBER" --json baseRefName -q '.baseRefName')
if [ "$ACTUAL_BASE" != "develop" ]; then
  echo "ERROR: Backport PR was created with base '$ACTUAL_BASE' instead of 'develop'. Closing the malformed PR."
  gh pr close "$PR_NUMBER" --comment "Closed: Backport PR was opened against wrong base branch '$ACTUAL_BASE'. Will reopen against develop."
  exit 1
fi
echo "Post-create assertion passed: backport PR base is '$ACTUAL_BASE'"
```

**Backport PR readiness steps (mandatory — mirrors the main hotfix PR path)**:

Regardless of whether the backport is an identical cherry-pick or introduces conflict-resolution changes, the following steps are required before the human merges:

1. **Run `gh pr ready <backport_pr_number>`** to convert the draft PR to non-draft.

2. **Run the automated reviewer loop**:

   ```bash
   ./scripts/development-workflow/pr-review-loop.sh <backport_pr_number> --branch backport/hotfix/[slug]
   ```

   For identical cherry-pick backports (no changes beyond what was reviewed on the main hotfix PR), the reviewer loop is abbreviated: if all configured reviewers post a clean result or no result, the PR is considered clean. If any reviewer posts a blocking finding, it must be addressed before proceeding.

   If the backport PR introduces any changes beyond a plain cherry-pick (e.g., conflict resolution changes, develop-only fixups), treat it as a normal implementation PR and run the full internal review gate (Step 7a), automated reviewer loop (Step 7), and CI loop (Step 8) per Protocol 91.

3. **Apply `ready-for-regression`** after the reviewer loop is clean:

   ```bash
   gh pr edit <backport_pr_number> --add-label "ready-for-regression"
   ```

4. **Verify CI is green** using `pr-ci-loop.sh` or by checking the PR's status checks.

5. **Apply `ready-for-human-review`** after CI is green and all reviewer loop threads are resolved:

   ```bash
   gh pr edit <backport_pr_number> --add-label "ready-for-human-review"
   ```

Both `ready-for-regression` and `ready-for-human-review` are required on the backport PR before the human merges it. The orchestrator's Step 5.1 verification (Protocol 91) checks for these labels on `backport/hotfix/*` branches and will flag missing labels as a protocol deviation. The backport PR can be merged by the human alongside or after the main hotfix review.

**Branch lifecycle summary**:

| Branch                   | Created from               | Merges into | Reused for backport? |
| ------------------------ | -------------------------- | ----------- | -------------------- |
| `hotfix/[slug]`          | `main`                     | `main`      | No                   |
| `backport/hotfix/[slug]` | `origin/main` (post-merge) | `develop`   | —                    |

**CHANGELOG on backport PR**: Do **not** add a new CHANGELOG entry on the backport branch. The versioned entry written in Step 6 already exists in `main` and will flow into `develop` via the merge.

---

## Spec Gaps & Workflow Hardening

When you encounter something the spec or plan doesn't cover:

1. **Stop** — do not make a unilateral product decision
2. **Report**: "The spec doesn't address X. Here are my options: A (simpler), B (more complete). Which do you prefer?"
3. Human decides
4. **Update** the spec or plan with the clarification
5. **Resume** implementation
6. If the gap reveals a recurring weakness in the spec template or protocol, flag it so the template can be improved

---

## Quality Rules

- **Cross-reference consistency**: When a change modifies policy or rule text, grep for all existing references to that policy **before writing any code** — do not assume you already know all locations. The grep is the discovery step. Before opening the PR:
  1. Grep for key phrases and signal names from the changed rule across all relevant locations (`docs/`, `AGENTS.md`, `README.md`, `REVIEW.md`, `.cursor/`, `.claude/`, `.codex/`) — including sibling agent instruction files (`.cursor/agents/`, `.claude/agents/`) and Cursor rules (`.cursor/rules/`)
  2. List every matched file as a candidate for the same update
  3. Explicitly confirm coverage of each matched file before submitting
  4. Verify headings, signal names, and language do not contradict each other across files

  Skipping this grep is the primary cause of multi-cycle review loops on cross-cutting documentation changes (e.g., updating a protocol but missing `.cursor/rules/workflow.mdc` and `AGENTS.md` that mirror the same policy text).

- **Script-emitted signal verification**: When writing or editing protocol text that cites a script-emitted signal value (e.g., `REASON=`, `RESULT=`, `STATUS=`), read the relevant source script and verify the exact string before committing. Do not copy a signal value from memory or from other protocol text — the source script is the authoritative value. A one-line grep takes seconds and prevents broken references from shipping:

  ```bash
  # Verify the exact REASON= values emitted by pr-review-loop.sh before citing them in protocol text
  grep -n 'REASON=' scripts/development-workflow/pr-review-loop.sh
  ```

- **Scope boundary**: Modify **only** files directly related to the assigned issue. If a code review or linter finding requires changes outside the issue's scope (e.g., fixing issues in adjacent modules, refactoring unrelated utilities, or addressing tech debt in other areas):
  1. **Do not fix it** in the current PR
  2. **Document it** as a separate issue or review finding
  3. **Move on** without implementing the out-of-scope fix

  This prevents merge conflicts, scope creep, and wasted review cycles. Scope boundaries are especially critical in parallel batch orchestration where multiple agents work simultaneously.

- Follow all best practices in `docs/best-practices/`
- Never expose raw internal values (enum codes, IDs) directly in user-facing output — use display labels
- Extract duplication only when the same logic appears 3+ times and the abstraction is clear
- Do not refactor code outside the scope of the current change
- Do not add comments to code you didn't modify

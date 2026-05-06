# Protocol: Implement Development (In Development Stage)

**Agent role**: Developer
**Stage**: In Development
**Paths**: Full Pipeline | Refactor | Fast Track | Hotfix

---

## Which Path to Use?

| Path | Branch | Use when |
|---|---|---|
| **Full Pipeline** | `feature/[slug]` from `develop` | Feature with approved spec + plan |
| **Refactor** | `refactor/[slug]` from `develop` | Code restructuring with approved plan (no spec) |
| **Fast Track** | `fix/[slug]` from `develop` | Bug or simple change — clear scope, ≤3 files, no schema changes, no new patterns |
| **Hotfix** | `hotfix/[slug]` from `main` | Critical production bug requiring immediate deployment |

---

## GitHub Actions Workflow Security Checklist

When your change creates or materially modifies `.github/workflows/*.yml`, complete this checklist before opening the development PR.

- Add an explicit `permissions:` block at workflow or job scope with least privilege (default to `contents: read` unless broader access is required)
- Pin all `uses:` references to a full commit SHA, with the pinned version tag noted in an adjacent comment (for example: `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2`)
- Add `paths:` / `paths-ignore:` filters when the workflow only needs to run for specific files or directories
- Add a `concurrency` group when duplicate runs on the same ref should be prevented

---

## Shell Script Quality Checklist

When your change **creates or significantly modifies a `.sh` file**, complete this checklist before opening the development PR. These are the most common bash scripting anti-patterns that cause rework in the automated reviewer loop.

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

**Note**: `trap ... PIPE` does **not** fire for pipeline SIGPIPE. SIGPIPE is delivered to the *child subprocess* writing to the closed pipe, not to the parent shell. The parent shell only observes the 141 exit code via `waitpid`. To catch this at the script level, use `trap ... EXIT` — it fires when `set -e` causes the shell to exit due to the pipefail-detected 141 status.

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

| Expression | `set -e` behavior |
|---|---|
| `cmd` (bare) | Abort on non-zero |
| `if cmd; then` | Safe — exit code is tested by `if`, never propagated |
| `cmd \|\| true` | Safe — `true` always exits 0, so the `\|\|` chain exits 0 |
| `cmd && other` | Safe — `set -e` does not abort on the left side of `&&` |
| `result=$(cmd)` | **Abort on non-zero** — same as bare command |

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

```bash
git fetch origin
git checkout develop
git pull origin develop
git checkout -b feature/[branch-slug]
```

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

Open a **draft** PR targeting `develop` with:

- **Title**: `feat([scope]): [feature-name]`
- **Description**:
  - What was implemented
  - Link to spec and plan
  - Test plan (how to validate)
  - Any deviations from the plan (with justification)
  - CHANGELOG entry preview

```bash
gh pr create --draft --base develop --title "feat([scope]): [feature-name]" --body "..."
```

**Important**: Always use `--base develop` to explicitly target the `develop` branch. This prevents accidental PR creation to `main` or other branches.

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

Pass condition: output is `1` or higher. If `0`: re-run `./scripts/development-workflow/pr-review-loop.sh <pr_number> --branch <branch>` and wait for it to complete before proceeding.

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

   | Category | What to check | Example pattern |
   |---|---|---|
   | **Link targets** | `[text](old-path)` — both the link target and `text` when text mirrors the old path | `[docs/ai/old](docs/ai/old)` |
   | **Display text in links** | `[old-path-text](new-path)` — link target already updated but display text still shows the old string | `[docs/ai/old](docs/workflow/new)` |
   | **Non-link occurrences** | Bare old-string in prose, code blocks, directory trees, YAML values, and shell scripts | `docs/ai/old` inside a code fence |

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
5. Verify: build, lint, tests pass; run e2e suite if a spec exists for the affected area. If any `.sh` files were modified, run ShellCheck before committing:

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
9. Open a **draft** PR targeting `develop` with refactor-appropriate metadata (do **not** reuse Path 1 Step 8 verbatim — that path uses `feat(...)` and a spec link):
   - **Title**: `refactor([scope]): [short description]`
   - **Description**:
     - What was refactored and why
     - Link to the **implementation plan** only (no spec)
     - Test plan (how to validate)
     - Any deviations from the plan (with justification)
     - CHANGELOG entry preview

```bash
gh pr create --draft --base develop --title "refactor([scope]): [short description]" --body "..."
```

**Important**: Always use `--base develop` to explicitly target the `develop` branch.

10. Hand off to the Work Item Runner with the same lifecycle expectations as Path 1 Step 9 (internal review gate, automated reviewer loop, CI, labels). **Label derivation rule**: `refactor/*` branches always require `ready-for-regression` based on branch prefix, not content type. See `91-orchestrate-work-protocol.md` Step 8a for the full branch-prefix-to-label table. See `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` and `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`.

---

## Path 3: Fast Track (Bug / Simple Change)

**Criteria check — all must be true**:

- [ ] The scope is clear and bounded from the start
- [ ] ≤ 3 files will be modified (estimate before starting)
- [ ] No new database schema migrations
- [ ] No new architectural patterns
- [ ] Human provided a clear, self-contained brief

**If any criterion fails**: Use the Full Pipeline instead.

**If scope expands during implementation**: Stop immediately. Report to the human. Do not silently expand scope.

### Step 1: Read Brief

Read the brief. If the work item exists in an issue tracker, follow `docs/workflow/development-workflow/integrations/issue-tracker.md` for `In Development (Fast Track)` expectations.

If your changes touch `.github/workflows/*.yml`, apply `## GitHub Actions Workflow Security Checklist` before opening the PR.

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

```bash
git fetch origin
git checkout develop
git pull origin develop
git checkout -b fix/[branch-slug]
```

**Worktree context (`BATCH_CONTEXT=true`)**: If this step runs inside an isolated worktree created by the item-orchestrator (Protocol 91 Step 3), skip the `git checkout develop` / `git checkout -b` commands above — the worktree was already created on the correct branch. Run only `git fetch origin` if you need the latest remote refs. Before running any git state-changing command, confirm your working directory is inside the worktree path, not the main repo root (run `pwd` and compare). See the "Critical: Worktree Git Discipline" block in Protocol 91 Step 3 for the full pre-operation checklist.

### Step 4: Implement

Implement the fix.

### Step 5: Verify

Verify: build, lint, tests pass; run e2e suite if a spec exists for the affected area.

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

Open a **draft** PR targeting `develop` using the same structure as Path 1 `### Step 8: Open PR (Draft)`, but with a **`fix(...)`** title and a fix-focused description (omit spec/plan links when none exist):

```bash
gh pr create --draft --base develop --title "fix([scope]): [description]" --body "..."
```

### Step 9: Handoff to Work Item Runner

Hand off to the Work Item Runner per Path 1 `### Step 9: Handoff to Work Item Runner`. **Label derivation rule**: `fix/*` branches always require `ready-for-regression` based on branch prefix, not content type. See `91-orchestrate-work-protocol.md` Step 8a for the full branch-prefix-to-label table.

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

### Step 5: Verify

Verify: build, lint, tests pass.

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
2. Insert the new versioned section **directly below `[Unreleased]`** (above all prior versioned sections). `auto-tag-release.yml` extracts the hotfix version via `grep -Em 1 '^## \[[0-9]+\.[0-9]+\.[0-9]+'`, which matches semver headers (X.Y.Z) and skips `[Unreleased]` and any non-versioned headers. The resulting structure should be:

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

Open a **draft** PR targeting `main` by adapting Path 1 `### Step 8: Open PR (Draft)` for hotfix (`fix(...)` title with `(hotfix)` as needed, incident-focused body, target branch `main`):

```bash
gh pr create --draft --base main --title "fix([scope]): [description] (hotfix)" --body "..."
```

**Important**: Use `--base main` for hotfixes (not `develop`). A hotfix merges to production first, then must be backported to `develop`.

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

```bash
gh pr create --draft --base develop \
  --title "chore(hotfix): backport [slug] to develop" \
  --body "Backports hotfix '[slug]' (merged to main) to keep develop in sync.

Closes the backport requirement for hotfix/[slug]."
```

Run the same internal review gate, automated reviewer loop, and CI loop as any other implementation PR. Apply `ready-for-regression` and `ready-for-human-review` labels when the PR is clean. The backport PR can be merged by the human alongside or after the main hotfix review.

**Branch lifecycle summary**:

| Branch | Created from | Merges into | Reused for backport? |
|---|---|---|---|
| `hotfix/[slug]` | `main` | `main` | No |
| `backport/hotfix/[slug]` | `origin/main` (post-merge) | `develop` | — |

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

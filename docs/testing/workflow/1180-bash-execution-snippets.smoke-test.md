# Smoke Test Runbook: Explicit Bash Execution for Workflow-Owned Snippets

**Feature**: Explicit Bash and verified Bash/zsh workflow snippet contracts
**Spec**: [1_1180-bash-execution-snippets_specs.md](../../specs/developments/20260723113846_1180-bash-execution-snippets/1_1180-bash-execution-snippets_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] Bash, zsh, Python 3, and ShellCheck are available.
- [ ] The snippet linter and its test harness exist.
- [ ] The implementation branch is checked out.
- [ ] Test fixtures can create and execute temporary scripts.

---

## Test Data

| Item | Value |
| --- | --- |
| Item list | Three distinct workflow item tokens |
| Pair list | Multiple owner/repo/number records |
| Unsafe loop | `for item in $LIST` |
| Unsafe extraction | `set -- $pair` |
| Bash boundary | `bash -lc`, `bash <<'BASH'`, or `bash <script>` |
| Portable boundary | `workflow-shell-contract: bash-zsh` |
| Expected evidence | Exact record values and counts, not exit code alone |

---

## Smoke Test Steps

### Step 1: Run the Snippet Linter Harness

**Maps to**: Acceptance Criteria 1, 3, 4, 5, 7, 8

1. Run
   `bash scripts/lint/tests/test-workflow-shell-snippet-lint.sh`.
2. Confirm parser, scope, contract, split-pattern, Bash-version, and
   behavioral cases pass.

**Expected result**: The harness exits successfully with zero failed cases.

### Step 2: Launch a Bash-Dependent Loop from Both Parent Shells

**Maps to**: Acceptance Criteria 1, 2, 6, 9

1. Execute the Bash-contract loop fixture from a Bash parent.
2. Execute the same launcher from a zsh parent.
3. Capture processed item records.

**Expected result**: Both parents visibly invoke Bash and produce the same three
ordered item records. A zero exit with fewer records fails.

### Step 3: Launch Bash Positional Extraction from Both Parent Shells

**Maps to**: Acceptance Criteria 1, 2, 6, 9

1. Execute the corrected owner/repo/number extraction fixture from Bash.
2. Execute the same Bash launcher from zsh.
3. Compare each extracted argument group.

**Expected result**: Both runs emit every expected owner/repo/number group with
identical field boundaries.

### Step 4: Execute a Portable Snippet Unchanged

**Maps to**: Acceptance Criteria 3, 6, 9

1. Run the `bash-zsh` fixture unchanged under Bash.
2. Run it unchanged under zsh.
3. Compare values, ordering, iteration count, and argument groups.

**Expected result**: Logical output is byte-equivalent or matches the fixture's
normalized record set in both shells.

### Step 5: Reject Unsafe Portable Guidance

**Maps to**: Acceptance Criteria 4, 5

1. Lint a framework-owned diff adding `for item in $LIST` under a `bash-zsh`
   contract.
2. Lint a second diff adding `set -- $pair`.

**Expected result**: WS003 and WS004 identify the exact file/fence and explain
that the author must launch Bash or rewrite portable parsing.

### Step 6: Enforce the Bash Execution Boundary

**Maps to**: Acceptance Criteria 1, 5

1. Lint a `bash` fence whose commands do not launch Bash.
2. Add `bash <<'BASH'` or an explicit script launcher and rerun.

**Expected result**: The ambiguous block fails WS002; the corrected block
passes. Fence syntax highlighting alone is not accepted as enforcement.

### Step 7: Preserve Bash 3.2 Compatibility

**Maps to**: Acceptance Criteria 7

1. Lint fenced Bash-contract fixtures containing associative arrays, `mapfile`,
   and `readarray` with the snippet linter.
2. Run a complete accepted Bash script fixture through the snippet linter and
   ShellCheck's Bash dialect.
3. Run the existing workflow shell guard only for changed stored scripts under
   `scripts/development-workflow/**/*.sh`; do not treat an out-of-scope clean
   result as evidence for a fenced or temporary fixture.
4. On macOS, execute the accepted fixture with `/bin/bash` and record
   `bash --version`.

**Expected result**: Bash 4+ fixture constructs fail WS006. SH005 continues to
guard applicable stored workflow scripts. Accepted fixtures use Bash
3.2-compatible constructs and pass the checks that actually inspect them.

### Step 8: Verify Scope and Documentation

**Maps to**: Acceptance Criteria 5, 8

1. Lint the same unsafe snippet once under a framework-owned command/skill path
   and once under an arbitrary downstream application path.
2. Inspect the best-practice, protocol, review, and creator guidance.

**Expected result**: The framework-owned path is checked with actionable output;
the downstream path is outside scope. Guidance consistently states the boundary.

### Last Step: Validate and Shut Down

- Run the live diff-aware linter, existing workflow shell guard, ShellCheck,
  and Markdown lint.
- Verify every assertion below.
- Remove all temporary scripts and captured output.

---

## Assertions Checklist

- [ ] Bash-dependent snippets visibly invoke/enforce Bash. AC1.
- [ ] Bash/zsh parent environments produce the same intended Bash results.
      AC2.
- [ ] Portable snippets produce the same logical records under both shells.
      AC3.
- [ ] Unsafe new implicit splitting is rejected. AC4.
- [ ] Diagnostics identify source and correction choice. AC5.
- [ ] Loop and positional extraction fixtures are covered. AC6.
- [ ] Accepted Bash snippets remain Bash 3.2-compatible. AC7.
- [ ] Only framework-owned executable guidance is in scope. AC8.
- [ ] Verification asserts processed records/counts, not exit status alone.
      AC9.

---

## Seed Data Reference

No database seed data is required.

| Entity | Scenario | How to load |
| --- | --- | --- |
| Synthetic diff | Contract/fence/splitting and scope variants | Generated by the linter harness |
| Shell fixture | Item and owner/repo/number records | Generated by the linter harness |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| zsh test silently skips | zsh dependency was treated as optional | Fail the harness with a clear prerequisite message |
| Bash fence passes without launcher | Fence language was mistaken for execution enforcement | Require WS002's launcher/shebang mechanism |
| Portable fixture differs only in count | Test checked status but not records | Assert exact item and argument-group output |
| Existing unrelated docs fail | Linter scanned untouched historical fences | Restrict default behavior to added/modified blocks |
| Product docs are flagged | Framework-owned path allowlist is too broad | Exclude downstream application surfaces |

---

## Known Limitations

- The MVP guarantees only Bash and zsh behavior for portable snippets.
- Historical untouched workflow fences are checked when modified, not
  retroactively rewritten in this item.

# Smoke Test Runbook: Advisory Checks Hook for Reviewer Loop

**Feature**: Advisory Checks Hook for Reviewer Loop
**Spec**: [1_1279-advisory-checks-hook_specs.md](../../specs/developments/20260723115259_1279-advisory-checks-hook/1_1279-advisory-checks-hook_specs.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

- [ ] The implementation branch contains the reviewer-loop hook, supplied no-op
  entry point, focused tests, and documentation updates.
- [ ] `bash`, `jq`, and the repository shell-test dependencies are available.
- [ ] Tests use local executable fixtures and mocked GitHub responses; no live
  pull request is mutated.

---

## Test Data

| Fixture | Behavior |
| --- | --- |
| Default entry point | Exits zero and writes no stdout |
| Marker extension | Appends its received PR identifier to a temporary counter file |
| Multiline extension | Emits two Markdown advisory lines and exits zero |
| Failing extension with output | Emits diagnostic body text and exits non-zero |
| Failing extension without output | Exits non-zero with empty stdout |
| Missing extension | Points to a nonexistent temporary path |
| Summary capture | Mocked PR comment body containing phase, compare, platform-advisory, project-advisory, and regression markers |

---

## Smoke Test Steps

### Step 1: Verify the Supplied No-Op

**Maps to**: AC3, AC8

1. Run
   `bash scripts/development-workflow/run-advisory-checks.sh 123`.
2. Capture stdout and the exit code.
3. Read the script comments and confirm they document the PR argument and
   complete Markdown-section stdout contract without prescribing a project
   tool.

**Expected result**: The script exits zero, stdout is empty, and the supplied
entry point is framework-neutral.

### Step 2: Guard Empty and Missing Context

**Maps to**: AC4, AC5, AC9

1. Run the focused cases in
   `bash scripts/development-workflow/tests/test-pr-review-loop.sh`.
2. Call `run_project_advisory_checks` with an empty PR identifier and the marker
   extension.
3. Confirm the marker file was not created or changed.
4. Call the helper with a valid PR identifier and the missing-extension path.

**Expected result**: Both calls return success with empty stdout and no inferred
target or extension invocation.

### Step 3: Render Non-Empty Multiline Output

**Maps to**: AC1, AC2, AC9

1. Run the multiline extension through the helper.
2. Capture a summary containing phase, compare, existing platform-advisory, and
   regression-warning markers.
3. Inspect the rendered summary marker order.

**Expected result**: Exactly one distinct advisory-checks section from the
extension contains both output lines. It follows
phase/compare/platform-advisory detail and precedes the regression annotation.

### Step 4: Contain Extension Failures

**Maps to**: AC6, AC9

1. Run the failing extension that writes diagnostic stdout.
2. Confirm the helper returns zero and preserves the diagnostic text in the
   project advisory section.
3. Repeat with the failing extension that writes no stdout.

**Expected result**: Non-zero extension status never propagates. Useful stdout
is visible; empty failure output adds no section.

### Step 5: Preserve Every Reviewer Outcome

**Maps to**: AC3, AC4, AC6, AC7, AC9

1. Exercise the harness with advisory output on platform-derived `clean`,
   `needs_fixes`, `needs_rerun`, and `escalate` paths.
2. Repeat representative paths with empty or missing advisory output.
3. Compare result, reason, blocking/suggestion counts, readiness-related fields,
   and process exit status.

**Expected result**: Every field and exit remains governed by the existing
reviewer-loop result. Advisory text neither upgrades nor downgrades an outcome
and never hides a blocker.

### Step 6: Verify One Invocation and Operator Guidance

**Maps to**: AC8, AC9

1. Run the marker extension through one normal reviewer-loop execution.
2. Confirm its counter records one invocation with the requested PR identifier.
3. Inspect `scripts/development-workflow/README.md` and Protocol 93.

**Expected result**: The extension runs once. Documentation explains the
customization contract, lifecycle, output placement, no-op behavior, and the
distinction from platform advisory dispositions.

### Last Step: Validate and Shut Down

1. Run the implementation plan's focused tests, ShellCheck, workflow shell
   guard, and markdown lint commands.
2. Confirm all temporary scripts, counters, and comment captures were removed.
3. Confirm no live PR comments, labels, checks, or tracker records were changed.

---

## Assertions Checklist

- [ ] AC1: Non-empty extension output appears in a distinct summary section.
- [ ] AC2: Project advisory output has the required findings-area ordering.
- [ ] AC3: The supplied no-op adds no empty section or behavioral change.
- [ ] AC4: A missing extension is a silent no-op.
- [ ] AC5: Empty PR context never invokes or targets the extension.
- [ ] AC6: Non-zero extension outcomes remain advisory and may preserve useful
  stdout.
- [ ] AC7: Existing blocking, rerun, and escalated outcomes stay authoritative.
- [ ] AC8: Projects can customize the supplied entry point without editing the
  reviewer-loop summary flow.
- [ ] AC9: Automated tests cover guards, output, ordering, one-time invocation,
  and result integrity.

---

## Seed Data Reference

No application seed data is required. Shell tests create all extension and
summary fixtures in a temporary directory and remove them through a cleanup
trap.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Advisory body is absent | Extension wrote only to stderr or returned empty stdout | Emit body text on stdout; keep diagnostics on stderr |
| Advisory output blends into surrounding text | Customized script omitted its section heading | Emit a complete Markdown-ready section with a distinct advisory heading |
| Test reports more than one invocation | Hook call was placed inside multiple terminal branches | Move the single helper call before terminal dispatch and pass its result to each branch |

---

## Known Limitations

- The template does not define which static-analysis tools a project should
  execute.
- The advisory hook has no independent timeout; project customizations should
  keep their own checks bounded.
- Project advisory notes are informational and do not create platform advisory
  disposition requirements or a new readiness gate.

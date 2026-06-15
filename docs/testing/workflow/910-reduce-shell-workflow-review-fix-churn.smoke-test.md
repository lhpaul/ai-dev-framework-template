# Smoke Test Runbook: Reduce Shell Workflow Review-Fix Churn

**Feature**: Reduce shell workflow review-fix churn before PR submission
**Spec**: Tracker brief [#910](https://github.com/lhpaul/ai-dev-framework-template/issues/910)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] You are on the implementation branch for #910.
- [ ] `origin/develop` is fetched locally.
- [ ] Python 3, Bash, ShellCheck, and Node dependencies used by markdown lint are
  available in the checkout.

---

## Test Data

| Item | Value |
| --- | --- |
| Guard script | `scripts/lint/workflow-shell-guard-lint.py` |
| Guard harness | `scripts/lint/tests/test-workflow-shell-guard-lint.sh` |
| Base ref | `origin/develop` |

---

## Smoke Test Steps

### Step 1: Run the Shell Guard Harness

**Maps to**: #910 review-fix churn objective.

1. Run:

   ```bash
   bash scripts/lint/tests/test-workflow-shell-guard-lint.sh
   ```

2. Confirm every rule has at least one failing fixture, one passing fixture, and
   one suppression fixture.

**Expected result**: The harness exits 0 and prints a passing summary.

### Step 2: Run the Guard Against the Branch Diff

**Maps to**: pre-submission detection before reviewer feedback.

1. Run:

   ```bash
   python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop
   ```

2. Inspect any findings. If a finding is intentional, confirm it uses a
   rule-specific inline suppression with a rationale.

**Expected result**: The command exits 0, or every reported finding is corrected
before PR submission.

### Step 3: Verify ShellCheck Remains Clean

1. Run ShellCheck on changed shell files.

   ```bash
   git diff --name-only origin/develop...HEAD -- '*.sh' |
     while IFS= read -r file; do
       shellcheck --severity=warning -- "$file"
     done
   ```

**Expected result**: ShellCheck exits 0.

### Step 4: Verify Documentation Mentions the Guard

1. Confirm the lint README documents all rule IDs.
2. Confirm the implementation protocol instructs developers to run the guard for
   workflow shell changes.
3. Confirm reviewer guidance treats a missing guard run as review-relevant.

**Expected result**: Documentation and reviewer guidance match the implemented
rule IDs and command syntax.

---

## Assertions Checklist

- [ ] Risky shell patterns that caused #908 review churn are caught before PR
  submission.
- [ ] Safe shell patterns and out-of-scope files are not flagged.
- [ ] Intentional exceptions require rule-specific rationale.
- [ ] CI and local commands use the same guard entrypoint.
- [ ] Documentation and reviewer guidance match the implemented behavior.

---

## Seed Data Reference

No seed data is required. The harness creates synthetic diff fixtures in a
temporary directory.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Guard reports historical repository issues | Scanner is not limited to added diff lines | Confirm the default path uses `git diff origin/develop...HEAD` |
| Suppression does not work | Rule ID or rationale format is wrong | Use `workflow-shell-guard: allow <RULE_ID> - <reason>` on the same logical line |
| ShellCheck fails on the runbook snippet | The snippet is copied into a script without quoting adjustments | Use the implementation protocol's changed-shell command instead |

---

## Known Limitations

- The guard is intentionally heuristic. It catches high-signal review-churn
  patterns and still relies on ShellCheck, tests, and review for broader shell
  correctness.

# Planted-Violation Proofs: Split pr-review-loop Harness (#1876)

**Item**: [#1876](https://github.com/lhpaul/ai-dev-framework-template/issues/1876)

The pr-review-loop harness is now split across several suites. Area 1876 in
`test-pr-review-loop.sh` adds structural guards that keep it split and keep
ShellCheck linting one file per process. For each guard, a violation was
planted in the working tree and the area was run. The guard failed, the file
was restored, and the area was run again and passed. Nothing planted was
committed.

**Restored harness** (every row below passes):

<!-- workflow-shell-contract: bash -->

```bash
bash scripts/development-workflow/tests/test-pr-review-loop.sh --area 1876
```

**Demonstrated output** (2026-10-02, PR #1888 head):

```text
PASS: 1876_harness_is_split_across_suites
PASS: 1876_every_suite_under_line_cap
PASS: 1876_every_suite_sources_shared_harness
PASS: 1876_every_suite_covers_loop_and_harness
PASS: 1876_harness_refuses_direct_execution
PASS: 1876_list_areas_reads_calling_suite
PASS: 1876_area_filter_is_per_suite
PASS: 1876_shellcheck_lints_one_file_per_process
PASS: 1876_shellcheck_job_has_timeout

Tests: 9 passed, 0 failed
```

## Planted violations

Each run used `test-pr-review-loop.sh --area 1876` with a 120-second bound.
"Planted" is the result with the violation in place. "Restored" is the result
after the file was put back.

| Planted violation | File | Guard | Planted | Restored |
| ----------------- | ---- | ----- | ------- | -------- |
| All sibling suites moved out (harness merged back into one file) | `tests/test-pr-review-loop-*.sh` | `1876_harness_is_split_across_suites` | FAIL, exit 1 | 9 passed |
| Suite grown past the 4000-line cap (+2100 comment lines) | `tests/test-pr-review-loop-staged-gates.sh` | `1876_every_suite_under_line_cap` | FAIL, exit 1 | 9 passed |
| Library grown past the cap (+3700 comment lines) | `tests/lib/pr-review-loop-harness.sh` | `1876_every_suite_under_line_cap` | FAIL, exit 1 | 9 passed |
| Suite loads the library with `.` instead of the canonical `source` line | `tests/test-pr-review-loop-cycles-labels.sh` | `1876_every_suite_sources_shared_harness` | FAIL, exit 1 | 9 passed |
| Suite drops `# covers:` for the library | `tests/test-pr-review-loop-release-bugbot.sh` | `1876_every_suite_covers_loop_and_harness` | FAIL, exit 1 | 9 passed |
| Suite drops `# covers:` for `pr-review-loop.sh` | `tests/test-pr-review-loop-no-verdict-yet.sh` | `1876_every_suite_covers_loop_and_harness` | FAIL, exit 1 | 9 passed |
| Library's direct-execution guard disabled | `tests/lib/pr-review-loop-harness.sh` | `1876_harness_refuses_direct_execution` | FAIL, exit 1 | 9 passed |
| Calling suite's Area 13 title changed, so `--list-areas` no longer shows it | `tests/test-pr-review-loop-failure-paths-2.sh` | `1876_list_areas_reads_calling_suite` | FAIL, exit 1 | 9 passed |
| Calling suite gains an `Area 0a` title, so `--area 0a` resolves in it | `tests/test-pr-review-loop-failure-paths-2.sh` | `1876_area_filter_is_per_suite` | FAIL, exit 1 | 9 passed |
| ShellCheck batches files (`xargs -0 -P 2`, no `-n 1`) | `.github/workflows/shellcheck.yml` | `1876_shellcheck_lints_one_file_per_process` | FAIL, exit 1 | 9 passed |
| ShellCheck job timeout removed | `.github/workflows/shellcheck.yml` | `1876_shellcheck_job_has_timeout` | FAIL, exit 1 | 9 passed |

In the `--area 0a` row, `1876_list_areas_reads_calling_suite` also failed. The
same edit removed the Area 13 title that guard looks for, so that is expected.

`1876_harness_is_split_across_suites` was planted by temporarily moving all
nine `test-pr-review-loop-*.sh` suites out of `tests/`, leaving only
`test-pr-review-loop.sh`. That is the shape of a harness merged back into one
file. The planted run exited 1 with
`FAIL: 1876_harness_is_split_across_suites — expected 'yes', got 'no'`. The two
per-suite filter guards also failed, as expected, because the suite they
target was gone. With the suites moved back, the area passed 9 of 9.

The first attempt at the direct-execution row ran away. With the guard
disabled, the library followed the parent run's exported
`TEST_PR_REVIEW_LOOP_ORIGIN` and re-ran the whole core suite, recursively. The
guard now also unsets that variable before running the library directly, so a
regression fails cleanly instead of recursing. The row above was recorded after
that fix.

## CI selection for sibling-only changes

`test-pr-review-loop.sh` declares
`# covers: scripts/development-workflow/tests/test-pr-review-loop-*.sh`. A PR
that changes only one of the other suites therefore still runs these guards:

```text
$ printf '%s\n' scripts/development-workflow/tests/test-pr-review-loop-staged-gates.sh > changed.txt
$ bash scripts/development-workflow/select-test-suites.sh --changed-files changed.txt
scripts/development-workflow/tests/test-pr-review-loop-staged-gates.sh
scripts/development-workflow/tests/test-pr-review-loop.sh
scripts/development-workflow/tests/test-step7a-surface-consistency.sh
```

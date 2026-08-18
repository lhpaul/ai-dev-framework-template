# Smoke Test Runbook: Conservative Verdict Classifier

**Feature**: Conservative (allow-list) verdict classifier for `codex-github-reviewer.sh` (Issue #1491)
**Spec**: None — Refactor path. Work item brief: [Issue #1491](https://github.com/lhpaul/ai-dev-framework-template/issues/1491)
**Implementation plan**: [`docs/specs/developments/20260817203204_1491-conservative-verdict-classifier/2_1491-conservative-verdict-classifier_implementation-plan.md`](../../specs/developments/20260817203204_1491-conservative-verdict-classifier/2_1491-conservative-verdict-classifier_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] The implementation branch for issue #1491 is checked out
- [ ] `bash`, `grep`, `sed`, `awk`, `jq`, and `gh` are available on `PATH`
- [ ] `gh auth status` succeeds (needed only for Step 5)
- [ ] You know which platform's tooling you are on (macOS/BSD or Linux/GNU) so you can note it in the results

**Design assets**: none. This work item has no `## Design assets` section, no tracker attachments, no linked
design files, and no `assets/` directory in its development folder. No expected-versus-actual fidelity step
is included, and no visual baseline should be invented.

---

## Test Data

| Item | Value |
| --- | --- |
| Reviewer script | `scripts/development-workflow/codex-github-reviewer.sh` |
| Test harness | `scripts/development-workflow/tests/test-pr-review-loop.sh` |
| Integration doc | `docs/workflow/development-workflow/integrations/codex-github.md` |
| Reviewer loop protocol | `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` |
| Real clean Codex comment source | PR #1489 in `lhpaul/ai-dev-framework-template` |
| Scratch directory | any writable temporary directory |

---

## Smoke Test Steps

### Step 1: The full harness passes

**Maps to**: Testing Strategy — residual verification evidence item 1

1. From the repository root, run:

   ```bash
   bash scripts/development-workflow/tests/test-pr-review-loop.sh
   ```

2. Read the summary line at the end of the output.

**Expected result**: the run exits 0 and reports zero failures. Note the total assertion count so it can be
compared against the pre-change count recorded in the PR description.

---

### Step 2: Removed symbols are actually gone

**Maps to**: Implementation Order steps 2 and 5

1. Run:

   ```bash
   grep -n "CODEX_NEGATED_APPROVAL\|not_only\|CODEX_APPROVAL_PATTERN" \
     scripts/development-workflow/codex-github-reviewer.sh
   ```

2. Run:

   ```bash
   grep -n "CODEX_CLEAN_SIGNAL_PATTERN\|CODEX_APPROVAL_DISQUALIFIER_PATTERN\|codex_strip_codex_footer\|codex_response_first_paragraph" \
     scripts/development-workflow/codex-github-reviewer.sh
   ```

**Expected result**: the first command prints nothing (all three superseded symbols are removed). The second
command prints at least one definition line for each of the four new symbols.

---

### Step 3: The blocking classifier is untouched

**Maps to**: Decision 5

1. Run:

   ```bash
   grep -n "CODEX_BLOCKING_PATTERN=\|CODEX_MERGE_REFUSAL_PATTERN=\|CODEX_NEGATION_WORDS=" \
     scripts/development-workflow/codex-github-reviewer.sh
   ```

2. Compare the printed pattern definitions against the same lines on `develop`:

   ```bash
   git diff origin/develop -- scripts/development-workflow/codex-github-reviewer.sh | grep -n "^[-+].*CODEX_BLOCKING_PATTERN\|^[-+].*CODEX_NEGATION_WORDS\|^[-+].*CODEX_MERGE_REFUSAL_PATTERN"
   ```

**Expected result**: the three blocking-side pattern definitions are present and the diff shows no change to
their values. The only diff touching `codex_response_is_blocking` is the removed
`codex_strip_not_only_idiom` call.

---

### Step 4: A clean response with an unrelated negation now safe-fails

**Maps to**: Test disposition Group C; Operational cost section

1. Create a scratch directory and a mock `gh` that returns a SHA-pinned Codex root comment reading
   `Looks good overall; tests were not run.`, following the mock convention used by the neighbouring
   scenarios in the harness (auth status, `pr view … headRefOid`, empty reviews and inline comments, and the
   comment payload).
2. Run the reviewer with a short poll budget:

   ```bash
   PATH="$SCRATCH:$PATH" scripts/development-workflow/codex-github-reviewer.sh \
     42 owner repo --poll-interval 1 --max-wait 1 --max-retriggers 0
   ```

**Expected result**: the command exits 1, prints
`VERDICT: NEEDS_REVISION (unrecognized response format — safe-fail)`, and emits an
`INFO: Codex clean signal present but disqualified` line naming the negation/hedge/actionable reason. Before
this change the same body returned `VERDICT: APPROVED`; the flip is intended.

---

### Step 5: A real vendor clean response still approves

**Maps to**: Edge case E9; residual verification evidence item 3 — this is the highest-impact check in the
runbook

1. Capture the current real clean-response body:

   ```bash
   gh api repos/lhpaul/ai-dev-framework-template/issues/1489/comments \
     --jq '.[] | select(.user.login | test("codex"; "i")) | .body'
   ```

2. Confirm it still has the shape the plan recorded: a `Codex Review: Didn't find any major issues.` opening
   line, a `**Reviewed commit:**` marker, and an "About Codex in GitHub" `<details>` footer containing a
   bulleted list.
3. Build a mock `gh` that serves that exact body as a SHA-pinned root comment (with the `Reviewed commit`
   marker rewritten to the mock head SHA) and run the reviewer as in Step 4.

**Expected result**: the command exits 0 and prints `VERDICT: APPROVED`. If the captured body no longer has
the recorded shape, stop and report it — the allow-list may need a reviewed addition rather than a workaround.

---

### Step 6: The vendor footer cannot hide a refusal

**Maps to**: Edge case E10; Decision 6

1. Take the Step 5 body and insert the sentence `This must not be merged.` **inside** the `<details>` block.
2. Run the reviewer against it with the same mock setup.

**Expected result**: the command exits 1 and prints `VERDICT: NEEDS_REVISION` (blocking branch, no
`unrecognized response format` suffix), because `codex_response_is_blocking` scans the untruncated body
before approval is considered.

---

### Step 7: Documentation reflects the new contract

**Maps to**: Documentation Updates

1. Open `docs/workflow/development-workflow/integrations/codex-github.md` and locate the verdict
   classification section.
2. Open `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md` and locate the
   "Codex GitHub terminal evidence" block.
3. Open `CHANGELOG.md` and locate the `[Unreleased]` → `### Changed` entry.

**Expected result**: the integration doc states that `APPROVED` requires an unhedged allow-listed clean signal
in the opening paragraph and that anything else safe-fails; the protocol block states that SHA-pinned terminal
evidence is necessary but not sufficient; the CHANGELOG entry uses the `**Bold Title** (#1491):` format and
appears under `### Changed`.

---

### Step 8: Lint gates are clean

**Maps to**: Implementation Order step 9

1. Run the markdown lint and heuristic lint commands from `AGENTS.md` against the changed markdown files.
2. Run `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`.

**Expected result**: every command exits 0 with no reported violations.

---

## Results

| Step | Pass / Fail | Notes |
| --- | --- | --- |
| 1 | | |
| 2 | | |
| 3 | | |
| 4 | | |
| 5 | | |
| 6 | | |
| 7 | | |
| 8 | | |

**Platform tested**: (macOS/BSD or Linux/GNU)

**Tester**:

**Date**:

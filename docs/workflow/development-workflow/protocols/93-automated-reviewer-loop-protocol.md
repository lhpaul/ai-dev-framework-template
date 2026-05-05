# Protocol: Automated Reviewer Loop (Standalone)

**Agent role**: Runner of the automated reviewer loop
**Purpose**: Run the automated reviewer loop and CI loop for one or more PRs until each PR is clean and ready for human review, or escalate to human

This protocol is **standalone**: it can be invoked for any open PR (or set of PRs) without full orchestration. It reuses **Step 7** and **Step 8** of `91-orchestrate-work-protocol.md` as-is; this document only adds how to choose the target PR(s) and how to report.

---

## When to use

- A human asks to run the automated reviewer loop on a specific PR or on the current branch's PR
- You want to advance one or more open PRs through automated review and CI without running full workflow discovery
- After pushing fixes to a PR, to re-run the loop until clean or escalate

---

## Scope: which PR(s)

Determine the target PR(s) in this order:

1. **Explicit PR number** — from the command or user message (e.g. "run reviewer loop on PR 42")
2. **Current branch** — if the user said "current" or "this PR" or did not specify: resolve the PR for the current branch, e.g. `gh pr view --json number --jq '.number'` from the repo root (or equivalent)
3. **Multiple PRs** — only if the user explicitly asked for "all open workflow PRs" or similar; then discover open PRs (e.g. branches `spec/*`, `implementation-plan/*`, `feature/*`, `refactor/*`, `fix/*`, `hotfix/*`) and run the loop for each, one at a time unless the tool supports parallel runs

If no PR can be determined, ask the user to specify a PR number or to run from a branch that has an open PR.

---

## Procedure (per PR)

### Pre-flight: check for existing unresolved review findings

Before running any scripts, inspect the PR's current review state:

```bash
gh pr view <number> --json reviews
gh api repos/{owner}/{repo}/pulls/<number>/comments
```

#### Blocking classification (Devin)

Devin always uses `COMMENTED` as its review state regardless of finding severity — it never uses `CHANGES_REQUESTED`, even for bugs. A Devin `COMMENTED` review must be treated as **blocking** (same as `CHANGES_REQUESTED`) when **either** of the following is true:

- The review body starts with `**Devin Review**` (Devin's standard summary format), OR
- The review is accompanied by unresolved inline PR review comments from `devin-ai-integration[bot]` (the `COMMENTED` review is the umbrella review object for those inline findings)

Only treat a `COMMENTED` Devin review as non-blocking when **both** of the following hold:
- The body does NOT start with `**Devin Review**`, AND
- There are NO unresolved inline PR review comments from Devin on the current HEAD

This behavior is implemented in `pr-review-loop.sh` (`run_devin_review`): the existing-reviews filter now includes all `COMMENTED` and `CHANGES_REQUESTED` reviews from Devin, and the blocking classification loop skips a `COMMENTED` review only when neither the body prefix matches nor any blocking inline comments exist.

#### What counts as an unresolved finding

A **blocking** inline comment or review from a configured platform (see `.ai-dev-workflow.yaml` under `review.platforms`) counts as **unresolved** when:

1. It applies to **any commit in this PR's history** (not only commits after the current `HEAD`). After merging the base branch (e.g. `develop`) into the PR branch, older bot comments are still open unless the **substantive issue** they describe is fixed in the codebase. A merge commit does not dismiss them.
2. There is no later resolved confirmation **for that same finding** (match by `(platform, path, body_snippet)` or Devin's inline comment id in the body, not by "most recent comment on the PR"). A resolved comment from Devin about *one* issue does not resolve a different blocking finding. Devin's resolved comments start with `✅` and must be excluded from blocking counts.

#### Merge / rebase trap

Do not assume the latest bot comment is the only active issue. A fixer may address a doc-only or secondary item while leaving an earlier code bug untouched. After each fixer push, verify the change fixes the **substantive problem** described in each open finding (e.g. the referenced file and behavior), not only a stale reference or a single resolved thread.

#### Verification: Re-read to confirm each fix

**Critical:** When a fixer agent addresses a review finding and commits changes:

1. **Before marking a finding resolved**: The fixer agent must re-read the specific file and line referenced in the finding to confirm the fix is actually present in the current code.
2. **Do not rely on memory alone**: Just because the agent planned or implemented a fix does not mean it is present. Dismissing findings as "already handled" without verification can mask unaddressed issues.
3. **Per-finding re-read**: For each blocking finding, explicitly read the file/line after changes are committed, then confirm in the PR comment that the verification was performed. Example: _"Confirmed: re-read `/src/foo.ts:42` and verified the fix is present."_
4. **Document verification in fix comments**: In the "Automated Fix" commit comment posted to the PR, state which findings were verified as resolved vs. which remain open.

This prevents premature dismissal of findings and ensures the PR feedback tracking ledger accurately reflects substantive code changes.

#### Commit SHA verification (mandatory before marking resolved)

Before citing any commit SHA in a fix comment or marking a finding resolved in the PR feedback ledger, the agent **must** verify the commit actually exists in the repository:

```bash
git log --oneline | grep "^<short_sha>"
# or equivalently:
git rev-parse --verify <short_sha> 2>/dev/null && echo "exists" || echo "not found"
```

If the SHA is **not found**, the agent must **not** record it as the resolved commit and must **not** claim the finding is resolved. Instead:

1. Run `git status` to check for uncommitted changes.
2. If changes are present but not committed, commit them:
   ```bash
   git add <changed-files>
   git commit -m "<commit message>"
   REAL_SHA=$(git log --oneline -1 | awk '{print $1}')
   ```
3. Use the real SHA returned by `git log` — never a remembered or planned SHA.

**Rationale**: An agent may edit files and internally track a planned commit SHA without ever running `git commit`. Citing a SHA that does not exist in `git log` produces a false audit trail, misleads human reviewers, and can result in the PR being labeled `ready-for-human-review` with uncommitted fixes that will be silently lost on branch cleanup.

**Escalation**: If `git commit` fails (e.g., pre-commit hook rejection or empty diff), investigate and resolve the failure before marking any finding resolved. Do not fabricate a SHA or skip the commit step.

#### Stale review after timeout

Also handle the case where a platform posted blocking findings after a previous run timed out and the agent moved on: if those findings are still unresolved per the rules above, dispatch a fixer, wait for the push, then run the scripts.

If unresolved findings exist: dispatch a fixer agent, wait for the push, then proceed to the scripts. Do not re-trigger the reviewer loop against stale findings — fix first.

### Worktree discipline for fixer agents (`BATCH_CONTEXT=true`)

When this protocol runs inside a worktree (the item was dispatched as part of a parallel batch, `BATCH_CONTEXT=true`), all fixer agents dispatched during the reviewer loop **must** stay inside the worktree. The same rules from Protocol 91 Step 3 "Critical: Worktree Git Discipline" apply here:

- **Before any git state-changing command** (`git switch`, `git checkout`, `git commit`, `git push`, `git reset`, `git restore`): confirm the working directory is inside the worktree path, not the main repo root. Run `pwd` and compare against `<worktree-path>`.
- **Never run `git checkout develop` or any base-branch switch** from inside the worktree — the base branch is already checked out in the main working tree and cannot be checked out in the worktree simultaneously.
- When delegating a fixer subagent, pass the resolved `<worktree-path>` in the handoff and instruct the fixer to validate all `Write`/`Edit` tool call paths start with `<worktree-path>/`.

Violations leave the main repo on a feature branch, breaking all subsequent agents and the human operator. The Portfolio Orchestrator's Step 5.2 check catches leaks after the fact, but prevention here avoids the need for correction.

### Fixer agent batching rule (mandatory)

Reviewer bots (e.g. Devin) start a new review cycle within 5–8 minutes of each push. Pushing after each individual fix means the reviewer starts re-reviewing stale state before all fixes are done, creating a "one cycle behind" pattern that can spin for 12+ review cycles on a single PR.

**Required sequence for every fixer dispatch:**

1. **Read ALL blocking findings first** — before editing any file, collect the complete list of open blocking findings from the current review cycle. Do not start fixing until you have the full picture.
2. **Apply ALL addressable fixes** — implement every fix you can address in this dispatch, across all files and findings.
3. **One commit, then push** — bundle every fix into a single commit and push exactly once per dispatch. Do not push after each individual fix.

Findings that cannot be addressed in this dispatch (e.g. require a human decision, are out of scope, or are genuinely contradictory) should be noted. Do not withhold the push for unresolvable findings — push all the fixes you can, then document what remains.

**When delegating to a fixer subagent**, include this rule explicitly in the subagent instruction so it knows not to push incrementally.

### Attempt-context injection rule

This rule mirrors the Attempt-context injection rule in Protocol 91 Step 7. It governs
what the orchestrator prepends to the fixer agent's prompt on each dispatch when running
the standalone reviewer loop path.

**First dispatch (cycle = 1)**

No attempt-context prefix is added. The fixer receives only the standard
blocking-findings list and the batching rule above.

**Retry dispatches (cycle ≥ 2)**

Before dispatching the fixer, the orchestrator prepends an attempt-context header
to the fixer's prompt using the following format:

> Attempt N/M: prior attempt(s) tried [per-attempt summaries]. The following findings
> remain open: [standard blocking-findings list]. Try a different approach for each
> remaining finding.

Where:

- `N` = the current `cycle` value (matches the loop's `cycle` counter exactly)
- `M` = `max_cycles` (the loop escalation limit — default: 10)
- `[per-attempt summaries]` = one entry per prior dispatch, each one-to-two plain-language
  sentences describing what that attempt changed and which findings it addressed or left
  open. Derive each entry from the PR feedback ledger and the fixer's commit message /
  response for that cycle.
- `[standard blocking-findings list]` = the same findings list passed in any dispatch —
  the attempt-context prefix does not replace it

**Accumulating summaries across retries**

For cycle N, include summaries for all N-1 prior attempts, not only the most recent.
Each entry should be keyed to its cycle number for clarity:

> Attempt 1: rewrote the `foo()` function signature in `bar.sh`; MD009 trailing-space
> finding on line 42 remained open.
> Attempt 2: removed trailing space on line 42; `relative-links` finding on `baz.md`
> remained open.

**Fallback when no prior-attempt summary is available**

If no summary was recorded for a prior attempt (e.g., the fixer did not respond or
the attempt had no ledger entries), use the minimal fallback:

> Attempt N/M: prior attempt did not fully resolve all findings. Try a different approach.

**Reappearance notation**

When a finding that was marked `resolved` in a prior cycle reappears in the current
ledger (same `(platform, path, body_snippet)` key, status reverted to `open`), the
per-attempt summary for the cycle in which it was "resolved" must note the reappearance:

> Attempt 2: removed trailing space on line 42 (fix did not hold — finding reappeared
> in cycle 3).

**In-session state only**

Attempt summaries live in the orchestrator's in-session state for the duration of the
PR's review loop. They are not persisted to disk or to any external tracker. They are
discarded when the orchestration session ends.

### Shell script fix verification (fixer agents)

When findings target `*.sh` workflow scripts (especially under `scripts/development-workflow/`), the fixer must **verify locally before pushing**:

1. Run `bash -n <path>` on every edited script for syntax errors.
2. Run at least one **narrow behavioral check** appropriate to the change — for example exercising the edited code path with a small controlled input, running the script’s `--help`, or running the smallest documented smoke command for that script.

If verification fails, iterate without pushing. When a prior attempt introduced regressions (e.g., misunderstood `IFS`, `read`, or `git worktree list --porcelain` ordering), prefer the **orchestrating agent** applying the fix inline with full conversation context rather than re-dispatching a blind fixer on the same subtle finding.

### Run the loops

Execute **Step 7a: Internal Review Gate**, **Step 7: Automated Reviewer Loop**, **Step 8: CI Loop**, **Step 8a: Label Readiness Checklist**, **Step 8b: Update Tracker Status**, and **Step 8c: Post-Label Independent Verification** exactly as defined in `91-orchestrate-work-protocol.md` (scripts, result interpretation, sequential platform policy, fixer mapping, parameters, and labels). Do not duplicate that logic here — follow 91.

For each PR: run Step 7a first. Step 7a runs **all** configured internal reviewers sequentially (per the `review.internal_reviewers` list in `.ai-dev-workflow.yaml`, with `.tmp/template-config.json` local overrides taking precedence). All internal reviewers must APPROVE before proceeding. Once Step 7a produces `APPROVED` from all internal reviewers, run `gh pr ready <pr_number>` to convert the draft PR to non-draft, then run Step 7 to completion, then Step 7b (regression label, implementation PRs only), then Step 8. Dispatch fixers and re-run as specified in 91 until the PR is clean and ready for human review or escalated. After Step 8 returns `green`, run Step 8a (label readiness checklist — this is a **hard gate** that verifies non-draft status, `ready-for-regression` label on implementation PRs, and applies `ready-for-human-review`). Once Step 8a passes, run Step 8b to update tracker status, then run Step 8c (post-label independent verification — this is a **hard gate** that independently verifies actual PR state via `gh pr view` before reporting ready). Only after Step 8c passes should the PR be reported as ready for human review.

### Re-query reviewThreads after each push (mandatory)

**After every push that addresses reviewer feedback — including the final push before Step 8c — you MUST re-issue the GraphQL `reviewThreads` query (as defined in Protocol 91 Step 8c) before proceeding to check readiness.**

Do not rely on thread state observed before the push. A bot reviewer (CodeRabbit, Devin, or any configured platform) may open new review threads within seconds of a push landing. These new threads will not be visible in any cached or pre-push snapshot.

The sequence after each fixer push is:

1. Push the fix commit.
2. Wait for configured bot reviewers to process the push (as part of the `pr-review-loop.sh` poll cycle).
3. **Re-issue the GraphQL `reviewThreads` query** (Protocol 91 Step 8c) to get the current thread state.
4. If new unresolved threads are found: handle them before proceeding (dispatch a fixer or resolve via reply, then repeat from step 1).
5. Only when the re-issued query returns no unresolved threads from configured bot reviewers: proceed to Step 7b (implementation PRs) then Step 8, then Step 8c.

**This check is not optional and cannot be skipped, even when the review loop script reported `clean`.** The script checks review state (blocking inline comments and `CHANGES_REQUESTED` reviews), not the resolved/unresolved state of `reviewThreads`. New threads created by a push may appear after the script's poll window closes. The GraphQL query is the only authoritative source for thread resolution state.

### Stuck-loop detection and escalation

The automated reviewer loop can become stuck if findings are not being resolved or if the same issues keep reappearing. Complement the per-platform timeouts in `pr-review-loop.sh` (20 min) with these higher-level heuristics to detect when a fix-review cycle is not making progress:

#### Detection rules

Use the **PR feedback ledger** (keyed by `(platform, path, body_snippet)`) to detect stuck loops. Check these conditions **after each fixer push + re-review cycle**:

1. **No progress over N consecutive cycles**: If the count of **open findings** (status = `open`) remains the same or increases after 2 or more consecutive fixer push cycles, the loop is not converging. Escalate.

2. **Finding reappears after fix**: If a finding that was marked `resolved` in a previous cycle reappears in the ledger (same `(platform, path, body_snippet)` key, status reverts to `open`), the fix did not hold. After one reappearance, dispatch the fixer once more. If it reappears again in the following cycle, flag as potentially unfixable and escalate to human.

3. **Maximum cycle count**: As specified in `91-orchestrate-work-protocol.md`, escalate when `cycle >= max_cycles` (default: 10). This is a hard limit independent of finding counts.

#### Escalation trigger

Stop the loop and escalate to human when any of the above conditions are met. In the final summary comment (see "PR feedback tracking and comments" below), include:

- Which stuck-loop heuristic triggered escalation
- A table showing the ledger state (all findings, their current status, and the cycles they have been open)
- A recommendation to the human (e.g., "Finding X appears unfixable by current fix agent; consider manual fix" or "Review cycle has not converged; recommend pausing to reassess root cause")

Example escalation comment:
````markdown
### Automated Reviewer Loop Escalation

**Reason:** No progress detected — 3 consecutive cycles with 2 unresolved findings.

| # | Platform | File | Status | Cycles open | Resolved in | Reappeared in |
|---|----------|------|--------|-------------|-------------|---------------|
| 1 | greptile | `src/foo.ts` | Open | 4 | -- | -- |
| 2 | devin | `src/bar.ts` | Open | 3 | `abc1234` | `def5678` |

**Recommendation:** Finding #2 reappeared after fix in cycle 4. This may indicate a fundamental issue that the automated fixer cannot resolve; consider manual review and fix.
````

### After fixing findings: cross-reference check

Before committing a fix, search the entire file for other mentions of the same concept. For example, if you changed a variable name, function signature, API pattern, or storage mechanism, grep for the old term throughout the document and update every occurrence. A single-point fix that leaves contradictory references in other sections will generate new findings on the next review cycle.

```bash
grep -n "<old-term>" <file>  # verify no stale references remain
```

After committing, apply the re-read verification described in [Verification: Re-read to confirm each fix](#verification-re-read-to-confirm-each-fix) above before marking the finding as resolved.

### All-occurrences rule for literal value fixes (mandatory)

When a reviewer flags a specific literal value — a numeric constant, hex value, identifier string, repeated phrase, or any other repeated literal — the fixer agent **must** fix every occurrence of that value across all affected files in the PR, not only the specific line flagged by the reviewer. Fixing one occurrence while leaving identical values elsewhere forces multiple unnecessary review passes and is a protocol violation.

**Required sequence before committing any literal-value fix:**

1. **Search the entire document** for all occurrences of the old value:

   ```bash
   grep -n "<old_value>" <file>
   ```

2. **Search all other files affected by the PR** for the same value:

   ```bash
   # For each file changed in this PR:
   git diff --name-only HEAD~1 HEAD | xargs grep -ln "<old_value>"
   ```

3. **Fix every occurrence** in the same commit — do not leave any behind.

4. **Verify with grep** on all affected files to confirm no occurrences remain before pushing:

   ```bash
   grep -rn "<old_value>" <all-affected-files>
   # Expected: no output (zero occurrences)
   ```

This rule applies to any value type: version numbers, timeout values, port numbers, hex color codes, string constants, label names, section headers, or any other repeated literal. If a reviewer flags one instance, treat it as a signal to fix all instances — the reviewer will check all occurrences on the next cycle and finding any remaining instance resets the review loop.

### PR feedback tracking and comments

Follow the "PR feedback tracking and comments" subsection of Step 7 in `91-orchestrate-work-protocol.md`:

- **Ledger bootstrap:** Before starting Step 7, seed the PR feedback ledger with **all** open blocking findings visible on the PR across its full history (not only comments timestamped after the current `HEAD`). That way a fresh run does not declare clean while a code bug from an earlier commit on the branch is still open. Align with the pre-flight rules above. Note: `pr-review-loop.sh` performs a **stale findings recovery** for Devin — when Devin does not review the current HEAD (no check run), the script scans the full PR history for unresolved findings and reports `needs_fixes` with reason `stale_findings`.
- Maintain a PR feedback ledger tracking all blocking findings across cycles (keyed by `(platform, path, body_snippet)`).
- After each fixer push, post a **fix commit comment** on the PR listing which findings that commit resolved and any remaining open findings.
- After each fixer push, **reply to each addressed inline review comment** on the PR to mark it as resolved. This is mandatory. Follow Protocol 91 ("Resolve inline review comments") for the exact `gh api` command format and delegation requirements for fixer subagents.
- When the loop terminates, post a **final summary table** on the PR with all findings and their statuses (`resolved` / `unresolved`).
- If the result is `skipped` (no platforms configured), do not post a summary comment.

### Review comments audit (post-clean gate)

After the review loop script returns `clean` for all platforms and before declaring the PR ready, **audit all review comments on the PR's code changes** to verify nothing was missed. The review loop script checks the latest review state, but comments from earlier commits or async reviewer posts can be overlooked.

1. **Fetch all review comments**:

   ```bash
   gh api repos/{owner}/{repo}/pulls/<number>/comments \
     --jq '.[] | select(.user.login | test("devin|coderabbit|greptile")) | {id: .id, user: .user.login, path: .path, body: .body[:150], created_at: .created_at}'
   ```

2. **For each reviewer comment**, check whether it has been addressed:
   - A reply from the PR author or agent confirming the fix (e.g., "Fixed in commit ...")
   - A "Resolved" status from the reviewer bot itself

   A subsequent commit modifying the same file or line is **not** sufficient on its own — the concern may still be unresolved even if the line changed. Require an explicit resolution signal (bot "Resolved" status or a confirming author/agent reply) plus verification that the specific concern is actually addressed.

3. **If any unaddressed comment is found**:
   - Dispatch a fixer to address it
   - Push the fix and reply to the comment confirming resolution
   - Re-run the review loop script to verify the fix didn't introduce new findings
   - Repeat this gate until all comments are addressed

4. **Only after all review comments are confirmed addressed**, proceed to the summary and readiness steps.

This prevents declaring a PR "clean" while substantive reviewer findings remain unresolved in the code changes view.

---

## Summary to the user

After processing the requested PR(s), report:

- **Ready for human review**: PR link, branch, and that the internal review gate, every configured automated reviewer, and CI are all clean (or skipped). Confirm that `gh pr ready` was run (after Step 7a APPROVED, before Step 7) to convert the draft PR to non-draft.
- **Escalated**: PR link, reason (no progress over consecutive cycles, finding reappeared after fix, max cycles, timeout, or review platform escalate).
- **Skipped**: If no review platform is configured, or a configured platform is currently unsupported and therefore skipped, note that in the result for the listed PR(s).

The final summary comment posted on the PR (per the PR feedback tracking subsection) serves as the durable record; the summary to the user is a concise pointer to the PR and its outcome.

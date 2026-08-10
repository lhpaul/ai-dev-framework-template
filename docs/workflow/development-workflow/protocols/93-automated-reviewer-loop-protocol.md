# Protocol: Automated Reviewer Loop (Standalone)

**Agent role**: Runner of the automated reviewer loop
**Purpose**: Run the automated reviewer loop and CI loop for one or more PRs until each PR is clean and ready for human review, or escalate to human

This protocol is **standalone**: it can be invoked for any open PR (or set of PRs) without full orchestration. It reuses **Step 7** and **Step 8** of `91-orchestrate-work-protocol.md` as-is; this document only adds how to choose the target PR(s) and how to report.

---

## When to use

- A human asks to run the automated reviewer loop on a specific PR or on the current branch's PR
- You want to advance one or more open PRs through automated review and CI without running full workflow discovery
- After pushing fixes to a PR, to re-run the loop until clean or escalate

> **Release PR exemption**: The automated reviewer loop applies only to develop-targeting PRs (feature, fix, refactor, hotfix backport). PRs whose head branch matches `release/*` or `hotfix/*` are **exempt** — `pr-review-loop.sh` automatically exits with `RESULT=skipped` and `REASON=release_pr` for these PRs. All changes in a release PR were already reviewed when their individual feature/fix PRs merged into `develop`. For release PR readiness, follow [`05-prepare-release-protocol.md`](05-prepare-release-protocol.md) Step 7 instead.

> **Run in the foreground — do not background-and-yield**: This protocol reuses Step 7 and Step 8 of [`91-orchestrate-work-protocol.md`](91-orchestrate-work-protocol.md) as-is, including the mandatory foreground-execution rule defined in those steps ("run in the foreground, never background-and-yield"). See that document for the full rule and rationale; it applies here exactly as written there.

---

## Scope: which PR(s)

Determine the target PR(s) in this order:

1. **Explicit PR number** — from the command or user message (e.g. "run reviewer loop on PR 42")
2. **Current branch** — if the user said "current" or "this PR" or did not specify: resolve the PR for the current branch, e.g. `gh pr view --json number --jq '.number'` from the repo root (or equivalent)
3. **Multiple PRs** — only if the user explicitly asked for "all open workflow PRs" or similar; then discover open PRs (e.g. branches `spec/*`, `implementation-plan/*`, `feature/*`, `refactor/*`, `fix/*`, `hotfix/*`) and run the loop for each, one at a time unless the tool supports parallel runs

If no PR can be determined, ask the user to specify a PR number or to run from a branch that has an open PR.

Before running reviewer or CI scripts, preserve repository context from the
caller. In `single_repo`, target the current repository as before. In
`workflow_hub`, implementation PR review/CI must target the selected product
repository, while spec/plan and hub-only workflow PRs target the hub. Pass
repository context through to shared scripts such as `pr-review-loop.sh` and
`pr-ci-loop.sh`; do not duplicate product repository selection logic inside a
command wrapper.

---

## Procedure (per PR)

### Pre-flight: draft-state check

Before running any scripts, check whether the PR is in draft state:

```bash
gh pr view <number> --json isDraft --jq '.isDraft'
```

If the result is `true`, do **not** mark the PR ready before the draft GitHub
gate. Run `review.on_draft.github` first, then let `pr-review-loop.sh` convert
the PR at the ready-phase boundary before dispatching `review.on_ready.github`.
Protocol 91 Step 7a is the source of truth for the reviewer-to-draft-restriction
mapping; see its "Draft-state pre-check" section for the full table. For
CodeRabbit specifically, check `.coderabbit.yaml`:

```bash
grep -E '^\s*drafts:\s*false' .coderabbit.yaml
```

If the file is absent or the key is not present, CodeRabbit defaults to
`drafts: false` — treat it as draft-restricting.

When a draft-restricting reviewer is listed in `review.on_ready.github`, the
ready transition happens after the draft gate:

```bash
./scripts/development-workflow/pr-review-loop.sh <number> --draft-github-only
./scripts/development-workflow/pr-review-loop.sh <number>
```

The second command marks the PR ready immediately before the first ready-phase
reviewer. This prevents silent reviewer skip while preserving draft-phase
coverage — CodeRabbit configured with `auto_review.drafts: false` produces no
comment when it bypasses a draft PR, making the omission invisible to the agent.

#### Haystack large-PR analysis limit

When the current-head `Haystack / Review` check is completed and explicitly
states that the pull request exceeds Haystack's analysis or file limit,
`haystack-reviewer.sh` terminates promptly with `RESULT=skipped`,
`REASON=analysis_skipped_file_limit`, and
`DISPLAY_RESULT=skipped (analysis file limit)`. This is a permissive skip for
Haystack only. It remains visible in the script-owned Automated Reviewer Loop
Summary and `reviewer_loop_history.v1`, and it must not bypass a blocker from
another reviewer, CI, unresolved review threads, regression, documentation
alignment, completion verification, or readiness gates.

Generic skip-like text, comments, incomplete check runs, and prior-head
evidence are not authoritative. If the exact terminal reason is absent, keep
following the existing pending, unavailable, finding, or timeout path rather
than manually posting a clean summary.

#### CodeRabbit CLI unavailable or rate-limited reviews

When `coderabbit-cli` is configured in `review.on_draft.github` or
`review.on_ready.github`, `pr-review-loop.sh` dispatches
`coderabbit-cli-reviewer.sh` instead of the CodeRabbit GitHub App path. The CLI
platform may return `RESULT=skipped` for missing CLI installation, missing auth,
invalid or ambiguous output, timeout, or warning-policy rate limits. This is
permissive for aggregate sequencing but is not evidence that a fresh CodeRabbit
CLI review found no issues.

Strict CLI rate-limit policy returns `RESULT=escalate` with
`REASON=rate_limited`. Treat that like any other platform escalation.

**Scope note**: This pre-flight checks `review.on_draft.github` and
`review.on_ready.github` (external reviewers used by Protocol 93 / Step 7). The
internal reviewer gate in Protocol 91 Step 7a separately checks
`review.on_draft.runner` and performs its own draft-state pre-check before any
runner reviewer is dispatched. When Protocol 93 is invoked via Protocol 91 (the
normal orchestrated path), the Step 7a pre-check and draft GitHub gate have
already controlled the ready transition; this pre-flight check is a safety net
for standalone invocations.

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

A **blocking** inline comment or review from a configured platform (see
`.ai-dev-workflow.yaml` under `review.on_draft.github` and
`review.on_ready.github`) counts as **unresolved** when:

1. It applies to **any commit in this PR's history** (not only commits after the current `HEAD`). After merging the base branch (e.g. `develop`) into the PR branch, older bot comments are still open unless the **substantive issue** they describe is fixed in the codebase. A merge commit does not dismiss them.
2. There is no later resolved confirmation **for that same finding** (match by `(platform, path, body_snippet)` or Devin's inline comment id in the body, not by "most recent comment on the PR"). A resolved comment from Devin about _one_ issue does not resolve a different blocking finding. Devin's resolved comments start with `✅` and must be excluded from blocking counts.

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

Also handle the case where a platform posted blocking findings after a previous run timed out and the agent moved on: if those findings are still unresolved per the rules above, address them before re-running the scripts. Apply the **Inline fix rule below first** when all findings are mechanical (single file, fully described, ≤ 5 lines); fall back to dispatching a fixer sub-agent only when the inline rule does not apply. In either case, wait for the push to land before running the scripts again — do not re-trigger the reviewer loop against stale findings.

### Inline fix rule (attempt before sub-agent dispatch)

Before dispatching a fixer sub-agent, check whether ALL blocking findings are **mechanical** — meeting every one of these criteria:

1. **Single file across the batch**: all blocking findings reference the **same single file** (one file total across the batch — not one file per finding). If two findings name two different files, the inline path does not apply; dispatch a sub-agent.
2. **Fully described**: each finding's body completely and unambiguously specifies the change (e.g., "replace `grep '^\s*'` with `grep '^[[:space:]]*'`", "add `--limit 100` to the `gh issue list` call", "remove the `states:OPEN` argument").
3. **Small scope**: the total estimated change across all blocking findings is ≤ 5 lines.

**When ALL criteria are met — apply the fixes directly** in the current session using Edit/Bash tools:

1. If `BATCH_CONTEXT=true`, complete the Protocol 91 pre-mutation isolation
   self-check before any inline edit, branch-changing command, commit, push, PR
   mutation, or tracker mutation: the full Protocol 90 isolation assignment
   must be present (`BATCH_CONTEXT=true`, resolved absolute worktree path,
   expected branch, artifact repo root, approved base branch, mutation
   classification, and `isolation: "worktree"`), `pwd -P` must equal the
   assigned worktree path or begin with that path followed by `/`, and
   `git rev-parse --abbrev-ref HEAD` must match the expected branch. Stop before
   mutation if the check fails.
2. Apply every blocking finding in one pass. For substantial fixer work, create
   coherent local checkpoint commits after completed logical sub-parts so
   partial progress survives runner interruption.
3. Push once after all addressable fixes for the current reviewer-loop cycle
   are complete. Do not push after each individual fix or checkpoint commit.
   Use descriptive commit messages for the final local commit sequence.
   _(Push before resolving threads — if push fails, threads must not be falsely
   marked resolved.)_
4. **Mandatory post-push SHA verification** — immediately after the push, verify the commit has landed on the remote:

   ```bash
   LOCAL_SHA=$(git rev-parse HEAD)
   REMOTE_SHA=$(gh pr view <pr_number> --json headRefOid --jq '.headRefOid')
   if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
     echo "Push verification failed: local HEAD $LOCAL_SHA != remote HEAD $REMOTE_SHA — retrying push"
     git push
     REMOTE_SHA=$(gh pr view <pr_number> --json headRefOid --jq '.headRefOid')
     if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
       echo "BLOCKED: push retry also failed (local $LOCAL_SHA != remote $REMOTE_SHA) — not marking fix complete"
       # Do not resolve threads or declare the fix pass complete. Report BLOCKED to the human.
       exit 1
     fi
   fi
   echo "Push verified: remote HEAD matches local HEAD ($LOCAL_SHA)"
   ```

   If verification fails after one retry, report a BLOCKED state, do not resolve any threads, and do not apply any readiness labels. This is a hard stop — do not proceed past this point until the push is confirmed.

5. Reply to each finding's review thread with the fix description and commit SHA.
6. Resolve each addressed thread via the GraphQL `resolveReviewThread` mutation.
7. **Increment `cycle`** (the same counter used in the sub-agent loop). Inline fix retries are bounded by `max_cycles` exactly like sub-agent retries — the inline path is a faster lane, not an unbounded one.
8. Re-run the reviewer loop script from the top. If it returns `clean`, proceed normally. If the loop still reports unresolved blocking findings **and** `cycle >= max_cycles`, escalate to human (the just-pushed fix is always given a chance to be verified before escalating).

**Do not dispatch a sub-agent for mechanical findings.** Sub-agent startup overhead (context loading, planning) typically costs 10–20 minutes for changes that take 30 seconds to apply directly.

**When ANY criterion fails** — fall through to the sub-agent dispatch path. The inline path is a fast lane, not a mandatory gate. When in doubt about whether a finding is fully described or single-file, dispatch the sub-agent.

### Worktree discipline for fixer agents (`BATCH_CONTEXT=true`)

When this protocol runs inside a worktree (the item was dispatched as part of an explicit-list batch, `BATCH_CONTEXT=true`), all fixer agents dispatched during the reviewer loop **must** stay inside the worktree. The same rules from Protocol 91 Step 3 "Critical: Worktree Git Discipline" apply here:

- **Before any git state-changing command** (`git switch`, `git checkout`, `git commit`, `git push`, `git reset`, `git restore`): confirm the working directory is inside the worktree path, not the main repo root. Run `pwd -P` and confirm it equals `<worktree-path>` or begins with `<worktree-path>/`.
- **Never run `git checkout develop` or any base-branch switch** from inside the worktree — the base branch is already checked out in the main working tree and cannot be checked out in the worktree simultaneously.
- When delegating a fixer subagent, pass the full Protocol 90 isolation assignment in the handoff: `BATCH_CONTEXT=true`, resolved absolute worktree path, expected branch, artifact repo root, approved base branch, mutation classification, and `isolation: "worktree"`. Instruct the fixer to validate all `Write`/`Edit` tool call paths start with `<worktree-path>/`.

Violations leave the main repo on a feature branch, breaking all subsequent agents and the human operator. The Portfolio Orchestrator's Step 5.2 check catches leaks after the fact, but prevention here avoids the need for correction.

### Fixer agent batching rule (mandatory)

Reviewer bots (e.g. Devin) start a new review cycle within 5–8 minutes of each push. Pushing after each individual fix means the reviewer starts re-reviewing stale state before all fixes are done, creating a "one cycle behind" pattern that can spin for 12+ review cycles on a single PR.

**Required sequence for every fixer dispatch:**

1. **Read ALL blocking findings first** — before editing any file, collect the complete list of open blocking findings from the current review cycle. Do not start fixing until you have the full picture.
2. **Apply ALL addressable fixes** — implement every fix you can address in this dispatch, across all files and findings.
3. **Use local checkpoint commits when useful** — for substantial fixer work,
   create coherent local checkpoint commits after completed logical sub-parts so
   partial progress survives runner interruption.
4. **Push once after all addressable fixes** — push only after all addressable
   fixes for the current reviewer-loop cycle are complete. Do not push after
   each individual fix or checkpoint commit.
5. **Mandatory post-push SHA verification** — immediately after the push, verify the commit has landed on the remote before replying to review threads or declaring the fix pass complete:

   ```bash
   LOCAL_SHA=$(git rev-parse HEAD)
   REMOTE_SHA=$(gh pr view <pr_number> --json headRefOid --jq '.headRefOid')
   if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
     echo "Push verification failed: local HEAD $LOCAL_SHA != remote HEAD $REMOTE_SHA — retrying push"
     git push
     REMOTE_SHA=$(gh pr view <pr_number> --json headRefOid --jq '.headRefOid')
     if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
       echo "BLOCKED: push retry also failed (local $LOCAL_SHA != remote $REMOTE_SHA) — not marking fix complete"
       # Do not resolve threads or declare the fix pass complete. Report BLOCKED to the human.
       exit 1
     fi
   fi
   echo "Push verified: remote HEAD matches local HEAD ($LOCAL_SHA)"
   ```

   If verification fails after one retry, report a BLOCKED state, do not resolve any threads, and do not apply any readiness labels. This is a hard stop — do not proceed past this point until the push is confirmed.

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

### Cross-file expansion: defer out-of-scope suggestions to a new issue

Automated reviewers (CodeRabbit, PR-Agent, Devin) can expand their review beyond the
files intentionally changed in the PR. This "scope inflation" causes agents to make
additional edits that increase PR diff size, add review burden, and risk unintended
side-effects.

**Definition of out-of-scope**: A reviewer finding targets a file that is **not** in the
PR's intentional diff scope — i.e., it was not modified by the PR and its content is not
required to validate or use the change being reviewed.

**Mandatory handling when out-of-scope findings appear:**

1. **Do not address the finding inline.** Do not edit the file, do not commit changes to
   it, and do not resolve the thread by making substantive edits to unintended files.

2. **Reply to the review thread** acknowledging the finding and noting it will be tracked
   in a separate issue:

   > "This finding is outside the intended scope of this PR (file `<path>` was not
   > intentionally modified). Deferring to a separate backlog item to avoid scope
   > inflation. This thread is closed without changes to this PR."

3. **Resolve the thread** via the GraphQL `resolveReviewThread` mutation (same as any
   other addressed thread) so it does not block the PR readiness gate.

4. **Create a new backlog issue** (or add to an existing open issue if one already covers
   the same concern) describing the suggested improvement. Title it descriptively and
   include a link to the review comment for traceability. Use the issue tracker configured
   in `.ai-dev-workflow.yaml`.

5. **Do not label the PR `needs-fixes`** solely on the basis of out-of-scope findings.
   Out-of-scope findings that are replied to and thread-resolved do not block
   `ready-for-human-review`.

**Important caveat — cross-cutting consistency fixes**: If a reviewer finding targets a
file outside the diff but the finding is a _consistency issue_ introduced by this PR (for
example, the PR adds a new signal value to a script but a protocol doc that references
that script still shows the old value), treat it as **in-scope**. The test is whether
_this PR's changes_ created the inconsistency, not whether the file was originally in the
diff. When in doubt, fix the consistency issue inline rather than deferring it.

### CodeRabbit silence patterns

`pr-review-loop.sh` handles two situations where CodeRabbit produces no review after a push
and would otherwise stall the loop indefinitely. Both are automatic — agents running the
script do not need to intervene. This section documents what each pattern looks like and
what to check when diagnosing a stalled loop.

#### Pattern 1: "Reviews paused"

**What happens**: CodeRabbit auto-pauses reviews after many commits on a PR. When paused,
CodeRabbit posts a "Reviews paused" issue comment on the PR and does not post a new review.
The push appears to complete normally but no review follows.

**Script behavior**: After half the max-wait window has elapsed with no activity
(`elapsed >= max_wait / 2`), `pr-review-loop.sh` checks for a "Reviews paused" issue
comment from `coderabbitai[bot]` posted after the current HEAD's `since_iso` timestamp. If
found, the script posts `@coderabbitai review` to resume, sets the `coderabbit_retrigger_attempted`
flag (so the auto-resume is only attempted once per HEAD cycle), and resets the elapsed
timer to give the resumed review a full polling window.

**Trigger condition**: Only attempted once per HEAD cycle (`coderabbit_retrigger_attempted`
flag). If CodeRabbit remains unresponsive after the retrigger and the max-wait window
elapses, the loop times out and exits `escalate`.

#### Pattern 2: Silent non-trigger

**What happens**: CodeRabbit simply does not auto-trigger after a push — no review appears,
no "Reviews paused" comment, and no rate-limit comment. CodeRabbit stays silent with no
visible signal.

**Script behavior**: After `CODERABBIT_NO_TRIGGER_TIMEOUT` seconds of silence with no
activity, no "Reviews paused" comment, and no rate-limit comment, `pr-review-loop.sh` posts
`@coderabbitai review` to force a fresh review. The `coderabbit_no_trigger_retriggers`
counter is incremented; `CODERABBIT_RATE_LIMIT_MAX_RETRIES` is the combined cap for total
retrigger attempts across both this mechanism and the rate-limit retry path. The elapsed
timer resets after posting so the triggered review has a full polling window.

**Default timeout (issue #1433)**: reduced from a fixed 600 s to a computed default via
`coderabbit_no_trigger_timeout_default` in `pr-review-loop.sh`, following this effective-timeout
rule based on the invocation's `--max-wait`:

| `--max-wait`          | Effective `CODERABBIT_NO_TRIGGER_TIMEOUT` default                                                                             |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| >= 360 s (e.g. the 1200 s script default, or the 2400 s large-diff default) | 180 s — the hardcoded default; the half-`max_wait` cap does not bind.                                    |
| 60 s – 359 s            | `floor(max_wait / 2)` — the cap binds and is always less than `max_wait`, guaranteeing room for a subsequent poll cycle before the outer timeout. |
| < 60 s (e.g. the 180 s spec/\*/implementation-plan/\* doc-branch default) | `max(30 s, floor(max_wait / 2))` — a 30 s floor takes precedence over the halved cap; for `max_wait` at or below ~30 s this can leave little or no room before the outer timeout, but this repo never configures `--max-wait` below 180 s, so this is a defensive edge case rather than a realistic operating point. |

An explicit `CODERABBIT_NO_TRIGGER_TIMEOUT` env var override is honored as-is (uncapped);
`coderabbit_resolve_no_trigger_timeout` validates it and falls back to the computed default
(with a `WARN` message) only when the override is not a positive integer.

**Trigger condition**: Allowed up to `CODERABBIT_RATE_LIMIT_MAX_RETRIES` times total. If
the cap is reached and CodeRabbit still has not responded, the loop exits `escalate`.

#### Diagnosing a stalled loop (manual polling)

When an agent is polling manually — or when `pr-review-loop.sh` has been running for more
than the effective `CODERABBIT_NO_TRIGGER_TIMEOUT` window with no CodeRabbit activity (180 s
on the default 1200 s `--max-wait` invocation; see the effective-timeout table above for
other `--max-wait` values) — check these markers before escalating:

1. **Check for a "Reviews paused" comment**: run:

   ```bash
   gh api repos/{owner}/{repo}/issues/{pr_number}/comments \
     --jq '[.[] | select(.user.login == "coderabbitai[bot]") | .body] | last'
   ```

   Look for "Reviews paused" text. If present, Pattern 1 applies.

2. **Check whether the script has already posted `@coderabbitai review`**: look for an
   issue comment with body `@coderabbitai review` posted by the workflow bot after the
   current HEAD push. If the script already posted the retrigger, wait for the full
   `max_wait` window before concluding CodeRabbit is unresponsive.

3. **If neither marker is present and the effective `CODERABBIT_NO_TRIGGER_TIMEOUT` window has
   elapsed with no activity** (see the effective-timeout table above), Pattern 2 (silent
   non-trigger) is likely. The script will post the retrigger automatically once that window
   elapses.

#### When to escalate vs. wait

Do **not** escalate while the script is still within its wait window or while an
auto-retrigger was just posted. Escalate only when **both** of the following are true:

- The script has posted `@coderabbitai review` (auto-retrigger for either pattern), AND
- A full `max_wait` window has elapsed after the retrigger with still no CodeRabbit review.

If you are running the script, it handles escalation automatically. If you are polling
manually, apply this rule before concluding the loop is stuck and escalating to human.

### CodeRabbit summary comment update-in-place pattern

CodeRabbit edits its single summary/walkthrough issue comment in-place after each review
cycle — it does **not** post a new comment per cycle. This has a critical implication for
agents trying to infer whether CodeRabbit has reviewed the current HEAD:

- The comment's **timestamp** reflects when it was **first created**, not when the most
  recent review cycle completed. A "stale-looking" timestamp does not mean CodeRabbit has
  not yet reviewed the latest push.
- An agent reading the PR timeline may observe a comment that appears old and incorrectly
  conclude that CodeRabbit has not yet reviewed the current HEAD commit.

> **Note**: Do **not** use the CodeRabbit summary comment's age or timestamp to infer
> whether a review of the current HEAD has completed. The timestamp is unreliable for
> this purpose.

The authoritative signals for review completion are:

1. **GraphQL thread audit** (`isResolved` state per `check_unresolved_threads` / Step 8c):
   the canonical cleanness check — if all CodeRabbit review threads report `isResolved: true`,
   the review is clean for the current HEAD.
2. **CodeRabbit SUCCESS commit status**: the machine-readable equivalent checked by
   `pr-review-loop.sh` as part of its polling loop. A `SUCCESS` status on the current HEAD
   SHA confirms CodeRabbit has reviewed that exact commit.

When verifying CodeRabbit review completion manually, always check one of these two signals
rather than inferring from comment age.

---

### Run the loops

Execute **Step 7a: Internal Review Gate**, **Step 7: Automated Reviewer Loop**, **Step 8: CI Loop**, **Step 8a: Label Readiness Checklist**, **Step 8b: Update Tracker Status**, and **Step 8c: Post-Label Independent Verification** exactly as defined in `91-orchestrate-work-protocol.md` (scripts, result interpretation, sequential platform policy, fixer mapping, parameters, and labels). Do not duplicate that logic here — follow 91.

For each PR: run Step 7a first. Step 7a runs **all** configured runner
reviewers sequentially (per the `review.on_draft.runner` list in
`.ai-dev-workflow.yaml`, with `.ai-dev-workflow.local.yaml` local overrides
taking precedence). All runner reviewers must APPROVE before proceeding. Then
run the draft GitHub reviewer gate (`pr-review-loop.sh --draft-github-only`) for
`review.on_draft.github`. Once Step 7a and the draft GitHub gate are clean, run
`gh pr ready <pr_number>` to convert the draft PR to non-draft, then run Step 7
to completion for `review.on_ready.github`, then Step 7b (regression label,
implementation PRs only), then Step 8. Dispatch fixers and re-run as specified
in 91 until the PR is clean and ready for human review or escalated. After Step
8 returns `green`, run Step 8a (label readiness checklist — this is a **hard
gate** that verifies non-draft status, `ready-for-regression` label on
implementation PRs, documentation-stage alignment on `spec/*` and
`implementation-plan/*` PRs, and applies `ready-for-human-review`). Standalone
reviewer-loop users preparing spec or plan PRs must route through Protocol 91
Step 8a and must not apply readiness directly after reviewer/CI success. Once
Step 8a passes, run Step 8b to update tracker status, then run Step 8c
(post-label independent verification — this is a **hard gate** that
independently verifies actual PR state via `gh pr view` before reporting ready).
Only after Step 8c passes should the PR be reported as ready for human review.

### Long spec/plan review-cycle guidance

When a spec or implementation-plan PR enters repeated reviewer cycles, inspect
the creator-stage `Document Quality Gate` log before deciding whether to keep
looping, fix the document, or escalate. The log is diagnostic evidence, not a
waiver for reviewer findings.

Check all of the following before continuing a long document-review loop:

- The PR description contains a `Document Quality Gate` section.
- The log references the current spec or plan content, not an earlier revision.
- `Not applicable` entries include concrete rationales.
- Reviewer-loop summary comments and advisory dispositions are current for the
  latest head SHA.
- Remaining reviewer findings are either directly addressed, recorded with a
  defensible disposition, or escalated when they require a human decision.

A missing, stale, or contradictory quality-gate log should be fixed before
another automated review cycle unless the next action is an explicit human
escalation.

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

4. **PR-Agent low-confidence Security Concern loop**: If PR-Agent applies
   `Security Concern` in two or more consecutive cycles while another configured
   reviewer is clean, inspect the PR-Agent finding text before dispatching another
   fix pass. When the finding text itself describes the concern as theoretical,
   unlikely, technically correct, low risk, or not a vulnerability, treat the loop
   as stuck and escalate with that evidence instead of making non-substantive code
   changes. PR-Agent is configured to reserve `Security Concern` for
   high-confidence actionable defects and to use `Possible Issue` for these
   low-confidence cases; repeated low-confidence security labels indicate reviewer
   calibration drift, not necessarily a code defect.

#### Escalation trigger

Stop the loop and escalate to human when any of the above conditions are met. In the final summary comment (see "PR feedback tracking and comments" below), include:

- Which stuck-loop heuristic triggered escalation
- A table showing the ledger state (all findings, their current status, and the cycles they have been open)
- A recommendation to the human (e.g., "Finding X appears unfixable by current fix agent; consider manual fix" or "Review cycle has not converged; recommend pausing to reassess root cause")

Example escalation comment:

```markdown
### Automated Reviewer Loop Escalation

**Reason:** No progress detected — 3 consecutive cycles with 2 unresolved findings.

| #   | Platform | File         | Status | Cycles open | Resolved in | Reappeared in |
| --- | -------- | ------------ | ------ | ----------- | ----------- | ------------- |
| 1   | greptile | `src/foo.ts` | Open   | 4           | --          | --            |
| 2   | devin    | `src/bar.ts` | Open   | 3           | `abc1234`   | `def5678`     |

**Recommendation:** Finding #2 reappeared after fix in cycle 4. This may indicate a fundamental issue that the automated fixer cannot resolve; consider manual review and fix.
```

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

### Draft GitHub Gate Before Ready-Phase Reviewers

Repositories may list one or more platforms under `review.on_ready.github` in
`.ai-dev-workflow.yaml`. `pr-review-loop.sh` treats these as the ready phase and
emits:

- `READY_PHASE_ENABLED=1`
- `READY_PHASE_PLATFORM_LIST=<platforms>`
- `READY_PHASE_FILTERED_OUT=<platforms>` when ready-phase platforms are
  configured but absent from the active invocation
- `READY_PHASE_STARTED=0|1`
- `READY_PHASE_GATE_RESULT=<result>` when the ready phase starts
- `READY_PHASE_SKIP_REASON=<result>` when the ready phase never starts
- `READY_PHASE_NET_NEW_BLOCKER=0|1`
- `READY_PHASE_BLOCKING_PLATFORM=<platform>` when applicable

For one transition release, the script also emits compatibility
`PHASE_AFTER_CLEAN_*` keys and accepts `review.phase_after_clean`,
`--phase-after-clean`, and `--pre-after-clean-only` as aliases for the new
ready-phase config and `--draft-github-only` flag.

For this template, `haystack` is the ready-phase platform. Keep implementation
PRs as drafts while the `review.on_draft.github` gate runs, then convert the PR
to non-draft and run the full configured loop. This prevents ready-only
reviewers from starting before draft reviewers have reached `clean`.

Use `READY_PHASE_NET_NEW_BLOCKER` as the primary value signal:

- `0` means the ready-phase reviewer did not find a blocker after draft GitHub
  reviewers were already clean.
- `1` means the ready-phase reviewer found net-new blocking feedback that the
  draft GitHub phase missed.

This signal is for tool-evaluation and graduation decisions. It does not weaken
the normal merge gates: any net-new blocker still follows the standard
`needs_fixes` loop.

### PR-Agent "Possible Issue" advisory labels

When `pr-review-loop.sh` returns `RESULT=clean` and the output contains an
`ADVISORY_LABELS` key with `Possible Issue` entries, PR-Agent flagged advisory
concerns but no hard-blocker labels. **No orchestrator action is required.**

`Possible Issue` findings are automatically acknowledged by the script and the loop
exits clean. The advisory label is recorded in `ADVISORY_LABELS`. Do not dispatch a
code-reviewer agent or re-invoke the loop because of these labels. Continue to record
advisory dispositions in the post-clean summary flow defined below.

---

### Advisory finding dispositions (post-clean)

When `pr-review-loop.sh` exits `clean` and the output contains a non-empty `ADVISORY_LABELS` value (advisory findings from any configured platform), the runner must document the disposition of each advisory finding and update the summary comment before marking the PR ready. This closes the gap between "we saw this finding" and "here is why it was or was not addressed."

#### When this step triggers

Any clean exit where the script output includes one or more advisory label entries in the `ADVISORY_LABELS` key (comma-separated names, e.g. `Possible Issue,Logic Issue`).

#### Procedure

1. **For each advisory finding** listed in the "Advisory findings" section of the Automated Reviewer Loop Summary comment, read the full finding text from the linked PR comment.

2. **Determine the disposition** — choose one per finding:
   - **Addressed** — the finding describes a real issue that was fixed in this PR. Cite the commit SHA.
   - **Accepted** — the finding is technically valid but intentionally not fixed. Provide a one-line rationale (e.g., "edge case that cannot occur in practice because platform names are always set programmatically").
   - **Deferred** — the finding will be tracked separately. Note the issue or backlog reference.
   - **Rejected** — the finding is a false positive. Explain why (e.g., "regex verified correct via manual test — pattern correctly excludes `[bot]`-suffixed logins").

3. **Update the Automated Reviewer Loop Summary comment** to append an "Advisory dispositions" subsection immediately after the advisory findings list:

   ```
   **Advisory dispositions:**
   - *Finding Name*: [Addressed in `<sha>` | Accepted | Deferred | Rejected] — one-line reason.
   ```

4. **Edit the comment in place** using `gh api PATCH`:

   ```bash
   # Find the summary comment ID (last match in case of multiple).
   # Use the same multi-marker pattern as Step 8c to cover all accepted summary forms.
   comment_id=$(gh api repos/{owner}/{repo}/issues/{pr_number}/comments \
     --jq '[.[] | select(.body | test("Automated Reviewer Loop Summary|Reviewer Loop Summary|No blocking PR feedback"))] | last | .id')

   # Patch with the updated body (include dispositions section at the end, before the script footer)
   gh api repos/{owner}/{repo}/issues/comments/$comment_id \
     -X PATCH -f body="<updated body>"
   ```

This step is mandatory when advisory findings are present. A summary comment that only lists finding names and links without dispositions leaves human reviewers and future retrospectives without visibility into whether findings were considered and why.

### Project advisory checks hook

After configured platform reviewers, review-thread checks, compare-mode
settlement, and reviewer-failed label reconciliation have completed,
`pr-review-loop.sh` runs the optional project extension
`scripts/development-workflow/run-advisory-checks.sh <pr-number>` once when a
PR number is available and the script exists.

The extension is a summary hook only:

- The supplied template script is a no-op that exits zero and emits no stdout.
- Downstream projects may customize the script to run diff-scoped static
  analysis or similar checks.
- Non-empty stdout is inserted into the automated reviewer summary after ready
  phase, compare-mode, and platform advisory details, and before any
  regression-readiness annotation.
- The extension owns its complete Markdown section heading. The recommended
  heading is `**Advisory checks** _(informational - never blocks merge)_`.
- Extension stderr is not included in the summary.
- Missing PR context, a missing script, empty stdout, or a non-zero extension
  exit is fail-open and never changes `RESULT`, `REASON`, blocker/suggestion
  counts, labels, readiness decisions, or the reviewer-loop process exit.

Project advisory checks are distinct from platform advisory dispositions. The
mandatory `ADVISORY_LABELS` disposition flow above applies only to advisory
findings emitted by configured review platforms. Project advisory notes are
informational operator context unless another existing gate independently
reports the same concern as blocking.

---

### Pre-post verification guard (mandatory before every `gh pr comment` / `gh pr review` call)

Before executing any `gh pr comment` or `gh pr review` command that summarises or
characterises platform results (approval, pass, clean, or any equivalent verdict claim),
the agent **must** complete this three-step guard. This applies equally to inline fix-pass
summaries and to the final reviewer-loop summary comment.

**Step 1 — Re-read the platform transcript.**

Retrieve the raw platform response immediately before composing the comment body. Do not
rely on in-session memory of what a platform said earlier in the loop. For each platform
whose result will be cited, run a fresh fetch:

```bash
# Fetch the most recent review comment from a bot (adjust login pattern as needed)
gh api repos/{owner}/{repo}/pulls/{pr_number}/comments \
  --jq '[.[] | select(.user.login | test("coderabbit|devin|greptile|pr-agent"))] | last'

# Or fetch the most recent issue comment
gh api repos/{owner}/{repo}/issues/{pr_number}/comments \
  --jq '[.[] | select(.user.login | test("coderabbit|devin|greptile|pr-agent"))] | last'
```

For script-posted summaries (auto-posted by `pr-review-loop.sh` on
`clean`/`needs_fixes`/`escalate` exits), the script itself is the authoritative transcript
source — this guard applies to agent-composed comments, not script-composed output.

**Step 2 — Cross-check every claim against the transcript.**

For every claim of approval, pass, or clean status in the draft comment body:

1. Identify the exact excerpt in the freshly fetched transcript that supports the claim.
2. If no excerpt supports the claim, remove or reword the claim before posting.

Examples of claims that must be directly supported:

- "CodeRabbit APPROVED" — requires a review event with `state: APPROVED` or a transcript
  excerpt such as "All discussions resolved" or an explicit approval statement.
- "CodeRabbit CLI found no issues" — requires `coderabbit-cli` script output
  with `RESULT=clean`; `RESULT=skipped` with `REASON=unavailable`,
  `unauthorized`, or `rate_limited` is not a clean review.
- "Devin found no issues" — requires a Devin comment body confirming no findings, not
  merely the absence of a `CHANGES_REQUESTED` review.
- "All platforms passed" — requires at least one supporting excerpt per platform cited.

**Step 3 — Apply the conservative fallback when the transcript is absent or ambiguous.**

If the transcript is unavailable (fetch returned empty, rate-limited, or timed out) or
ambiguous (the platform comment does not clearly indicate approval or pass), **do not
fabricate a result**. Use the following conservative fallback message instead of a
fabricated summary:

> "Review completed — see individual platform comments for details."

This fallback is always safe to post. It does not make a false claim and does not block
the PR from proceeding; human reviewers can read the platform comments directly.

#### Classifier-safe label-only fallback for PR-Agent comments

If the runner's safety classifier or tool policy blocks the agent from reading a full
PR-Agent review body, **do not hand off to a human immediately**. Reading reviewer
comments is a normal Protocol 93 operation, and PR-Agent's structured HTML can trip
classifiers even when the underlying operation is routine. Use the label-only path below
before escalating:

1. Re-run the PR-Agent platform through the repository helper and consume only its
   key-value output:

   ```bash
   set -euo pipefail

   ./scripts/development-workflow/pr-review-loop.sh <pr_number> \
     --branch <branch_name> \
     --platform pr-agent \
     --max-wait 600
   ```

   Treat `RESULT`, `BLOCKING_COUNT`, `SUGGESTION_COUNT`, and any
   `ADVISORY_LABELS`/`POSSIBLE_ISSUE_EVAL_OUTCOME` lines as the authoritative
   classification for this pass. Do not attempt to quote or paraphrase the PR-Agent
   body if the classifier blocked body access.

2. If a traceable URL is needed, fetch metadata without printing the review body:

   ```bash
   gh api repos/{owner}/{repo}/issues/{pr_number}/comments \
     --jq '[.[] | select(.user.login == "github-actions[bot]" and (.body | contains("PR Reviewer Guide"))) | {id, html_url, created_at, updated_at}] | last'
   ```

3. Continue the reviewer loop from the helper result:
   - `RESULT=clean` → proceed normally; mention only that PR-Agent was clean or
     advisory-only per the helper output.
   - `RESULT=needs_fixes` → dispatch the fixer using the label/category surfaced by
     the helper output; avoid reading the blocked body unless a human explicitly
     provides the excerpt.
   - `RESULT=escalate` / `RESULT=skipped` with repeated fetch failures → escalate
     with the helper output and metadata URL.

Only escalate for human handoff after the label-only path also fails or returns an
unfixable/blocking state. A classifier block on the raw PR-Agent body alone is not a
terminal condition.

**Escalation on repeated transcript unavailability.**

If the transcript fetch fails on two or more consecutive attempts for the same platform,
log a warning in the fix commit comment and escalate to human review rather than continuing
to compose summary comments without transcript support.

---

### PR feedback tracking and comments

Follow the "PR feedback tracking and comments" subsection of Step 7 in `91-orchestrate-work-protocol.md`:

- **Ledger bootstrap:** Before starting Step 7, seed the PR feedback ledger with **all** open blocking findings visible on the PR across its full history (not only comments timestamped after the current `HEAD`). That way a fresh run does not declare clean while a code bug from an earlier commit on the branch is still open. Align with the pre-flight rules above. Note: `pr-review-loop.sh` performs a **stale findings recovery** for Devin — when Devin does not review the current HEAD (no check run), the script scans the full PR history for unresolved findings and reports `needs_fixes` with reason `stale_findings`.
- Maintain a PR feedback ledger tracking all blocking findings across cycles (keyed by `(platform, path, body_snippet)`).
- After each fixer push, post a **fix commit comment** on the PR listing which findings that commit resolved and any remaining open findings. Apply the [Pre-post verification guard](#pre-post-verification-guard-mandatory-before-every-gh-pr-comment--gh-pr-review-call) before composing each fix commit comment.
- After each fixer push, **reply to each addressed inline review comment** on the PR to mark it as resolved. This is mandatory. Follow Protocol 91 ("Resolve inline review comments") for the exact `gh api` command format and delegation requirements for fixer subagents.
- When the loop terminates with `clean`, `needs_fixes`, or `escalate`, **`pr-review-loop.sh` automatically posts or updates the "Automated Reviewer Loop Summary" comment** — you do not need to post it manually for those exits. On `needs_fixes`, the script updates the existing summary in place so active findings are visible while the fixer loop continues. The script-posted comment satisfies the Step 8c `hasReviewSummary` check.
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

- **Ready for human review**: PR link, branch, and that the internal review gate, every configured automated reviewer, and CI are all clean (or skipped). For spec and plan PRs, mention that the `Document Quality Gate` log is present. Confirm that `gh pr ready` was run (after Step 7a APPROVED, before Step 7) to convert the draft PR to non-draft.
- **Escalated**: PR link, reason (no progress over consecutive cycles, finding reappeared after fix, max cycles, timeout, or review platform escalate).
- **Skipped**: If no review platform is configured, or a configured platform is
  currently unsupported, unavailable, unauthenticated, rate-limited under
  warning policy, or otherwise skipped, note that in the result for the listed
  PR(s).

The final summary comment posted on the PR (per the PR feedback tracking subsection) serves as the durable record; the summary to the user is a concise pointer to the PR and its outcome.

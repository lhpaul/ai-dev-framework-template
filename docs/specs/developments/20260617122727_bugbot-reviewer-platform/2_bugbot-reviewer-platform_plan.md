# Bugbot Automated PR Reviewer Platform Support — Implementation Plan

**Spec**: [`1_bugbot-reviewer-platform_specs.md`](./1_bugbot-reviewer-platform_specs.md)
**Smoke test runbook**: [`../../../testing/workflow/990-bugbot-reviewer-platform.smoke-test.md`](../../../testing/workflow/990-bugbot-reviewer-platform.smoke-test.md)

---

## Summary

**Approach**: Add a `run_bugbot_review()` platform function inline in
`pr-review-loop.sh` that participates in the existing reviewer-loop platform
mechanism exactly like the other supported platforms. Cursor Bugbot is a
**check-run + review/comment hybrid** (similar in shape to Devin): it publishes
a "Cursor Bugbot" check run on the PR head SHA and posts its findings as
`cursor[bot]` reviews and review comments. The function (1) ensures a fresh
Bugbot review against the current head by posting a top-level `bugbot run`
trigger comment when no in-progress/recent run exists, (2) polls the "Cursor
Bugbot" check run on the current head SHA and classifies its conclusion
(`success` → no blocking findings, `action_required`/`failure` → blocking,
`neutral`/`cancelled`/`skipped` → non-blocking informational, missing/never
published or `timed_out` → timeout/unavailable), (3) reads `cursor[bot]`
reviews/comments scoped to the current head to count and summarize blocking
findings with severity and location context, and (4) emits the standard
per-platform telemetry. Registration mirrors every other platform: a dispatch
case in `run_platform_review()` and an entry in `bot_login_for_platform()` so
Bugbot's `cursor[bot]` threads are included in platform thread auditing. The
`.ai-dev-workflow.yaml` "Supported today" comment is updated to list `bugbot`.

**Estimated complexity**: M

<!-- S: < 1 day | M: 1-3 days | L: 3+ days -->

**Rationale**: The change is scoped to three files — one script
(`pr-review-loop.sh`) for the new platform function plus the two registration
points (`run_platform_review()` dispatch and `bot_login_for_platform()`), one
config-comment update (`.ai-dev-workflow.yaml`), and one new test file area plus
the smoke runbook. There is no new companion script, no database change, and no
frontend work. The classification is slightly more involved than Copilot's
review-state mapping because Bugbot's verdict is carried by a check-run
conclusion **and** its findings are carried by reviews/comments, so the function
must reconcile both signals (mirroring the established `run_devin_review()`
pattern) and parse a small set of structured Bugbot finding markers
(`BUGBOT_REVIEW`, `BUGBOT_BUG_ID`, `LOCATIONS`, severity headings) for the
summary. The HARNESS_MODE unit-test infrastructure already exists and follows a
well-worn pattern.

**Dependencies**: The spec (PR #997) is already merged into the base integration
branch `develop-cursor-bugbot-integration`; this plan and its implementation
target that branch (not `develop`). No sibling epic child must be merged first —
`run_bugbot_review()` is self-contained and independent of the deferred Cursor
surface-parity and Bugbot setup-documentation items (epic #988 children). The
Cursor GitHub App that provides Bugbot must be installed on a repository for the
live (non-harness) paths to exercise, but that is a runtime prerequisite, not a
build-time dependency.

---

## Verification Log

> Reproducible plan-time checks that drive the scope, counts, and file lists below.

| Check | Command / query | Result |
| --- | --- | --- |
| Base branch revision | `git rev-parse --short origin/develop-cursor-bugbot-integration` | `973e233` |
| Spec PR merged into base | `gh pr view 997 --json state,baseRefName,mergedAt` | `MERGED` into `develop-cursor-bugbot-integration` at `2026-06-17T16:37:16Z` |
| Existing platform functions | `grep -c "^run_.*_review() {" scripts/development-workflow/pr-review-loop.sh` | 8 platform functions (`greptile`, `codex_github`, `claude_code_action`, `copilot`, `haystack`, `devin`, `pr_agent`, `coderabbit`); `bugbot` absent — must be added |
| `run_platform_review` dispatch cases | inspection of `run_platform_review()` `case` block | 8 cases: `greptile`, `devin`, `coderabbit`, `pr-agent`, `codex-github`, `claude-code-action`, `copilot`, `haystack`; `bugbot` absent — must be added |
| `bot_login_for_platform` cases | inspection of `bot_login_for_platform()` `case` block | 8 platform entries; `bugbot` absent — must be added so `cursor[bot]` threads are audited |
| Check-run polling precedent | `grep -n "commits/$head_sha/check-runs" scripts/development-workflow/pr-review-loop.sh` | `run_devin_review()` already polls `repos/$repo/commits/$head_sha/check-runs` and filters by `.app.slug` / `.name | test(...)` — reuse this pattern for the "Cursor Bugbot" check run |
| HARNESS_MODE test file | inspection of `scripts/development-workflow/tests/test-pr-review-loop.sh` | Present (1999 lines); mocks `gh`/`git`, sources the script with `HARNESS_MODE=1`, calls platform functions directly — used for AC-9 unit tests |
| `Supported today` comment | `grep -n "Supported today" .ai-dev-workflow.yaml` | Line 44: lists `greptile, devin, coderabbit, pr-agent, codex-github, ...`; `bugbot` absent — must be added |
| Setup-doc scope boundary | Spec "Non-Goals" + "Out of Scope (MVP)" | Downstream Bugbot setup documentation (`.cursor/BUGBOT.md`, integration guide, rollout defaults) is explicitly deferred to a **separate epic child** — this plan must NOT create a `bugbot.md` integration guide |
| `pr-review-loop.sh` line count | `wc -l scripts/development-workflow/pr-review-loop.sh` | 5174 lines |

---

## Layer-by-Layer Changes

> Database, Shared-package, and Frontend layers do not apply to this feature.

### Script Layer (`scripts/development-workflow/`)

- [ ] **`pr-review-loop.sh` — add `run_bugbot_review()` function** (AC-1, AC-2,
  AC-3, AC-4, AC-5, AC-6): Insert the new function alongside the other platform
  functions (recommended placement: immediately after `run_copilot_review()`
  and before `run_haystack_review()`). It must follow the same four-argument
  signature (`pr_number`, `branch_name`, `poll_interval`, `max_wait`) and
  exit-code contract (0 = clean, 1 = needs\_fixes, 2 = escalate) used by every
  other platform function. Behavior:
  - Resolve the current head SHA; if it cannot be resolved, emit
    `RESULT=escalate REASON=head-sha-unavailable` and return 2 (mirrors
    `run_devin_review()` / `run_copilot_review()`).
  - **Phase 1 — existing-findings check**: scan `cursor[bot]` reviews/review
    comments scoped to the current head for unresolved blocking findings. If any
    exist, emit `RESULT=needs_fixes REASON=existing_findings` with the blocking
    summary and return 1 (mirrors `run_devin_review()` Phase 1).
  - **Phase 2 — trigger**: when no recent/in-progress Bugbot run is detected for
    the current head, post the top-level trigger comment `bugbot run` (constant
    overridable via `BUGBOT_TRIGGER_COMMENT`). Triggering must be idempotent —
    do not post a second trigger if a Bugbot check run for the current head is
    already queued/in-progress.
  - **Phase 3 — poll the "Cursor Bugbot" check run** on
    `repos/$repo/commits/$head_sha/check-runs`, filtering by `.app.slug` for the
    Cursor app and/or `.name` matching the check-run name (constant
    `BUGBOT_CHECK_NAME`, default `Cursor Bugbot`, overridable via
    `BUGBOT_CHECK_NAME`). Re-resolve the head SHA each poll iteration so a
    mid-review push retargets the filter (mirrors `run_copilot_review()`).
  - **Classification** of the check-run conclusion once `status == completed`:
    - `success` → no blocking findings (proceed to read comments; if none
      blocking, RESULT=clean)
    - `failure` or `action_required` → blocking → RESULT=needs\_fixes
    - `neutral`, `cancelled`, `skipped` → non-blocking informational →
      RESULT=clean with the finding counted as a suggestion, not a blocker
    - `timed_out` → RESULT=escalate REASON=timeout
  - **Timeout / unavailable**: if the check run never reaches `completed` within
    `max_wait`, or the check run never appears at all (and no `cursor[bot]`
    verdict is present), emit `RESULT=escalate` with `REASON=timeout` (poll
    budget exhausted) or `REASON=unavailable` (Cursor app not installed / no
    check run ever published). A missing/absent verdict must **never** be
    reported as clean (AC-5).
  - **Finding summary** (AC-6): for blocking outcomes, read `cursor[bot]`
    reviews/review comments scoped to the current head and emit
    `BLOCKING_<n>_PATH`, `BLOCKING_<n>_LINE`, and `BLOCKING_<n>_BODY` lines
    (using `print_kv` / `print_kv_escaped`, same as `run_greptile_review()` /
    `run_devin_review()`). The body extraction should surface the Bugbot finding
    markers present in the comment (`BUGBOT_REVIEW`, `BUGBOT_BUG_ID`,
    `LOCATIONS`, and the severity heading) so the summary carries severity and
    location context.
  - Every `print_kv` must use `PLATFORM "$platform"` (where `platform="bugbot"`)
    and always emit `RESULT`, `COMMENT_COUNT`, `BLOCKING_COUNT`, and
    `SUGGESTION_COUNT` on terminal paths (AC-2). Use `_interruptible_sleep` (not
    `sleep`) in the poll loop so the SIGTERM/SIGINT traps fire promptly.

- [ ] **`pr-review-loop.sh` — add `bugbot` to `run_platform_review()`** (AC-1):
  In the `case "$platform" in` block, add a `bugbot)` case that calls
  `run_bugbot_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"`.
  Insert it after the `haystack)` case and before the `*)` fallback. The case
  label must be exactly `bugbot`.

- [ ] **`pr-review-loop.sh` — add `bugbot` to `bot_login_for_platform()`**
  (AC-7): In the `case "$1" in` block, add a `bugbot)` case returning the bot
  login `cursor[bot]` (constant overridable via `BUGBOT_BOT_LOGIN`). This makes
  Bugbot's review threads eligible for the framework's platform thread auditing
  wherever that auditing maps platforms to bot logins (the same mechanism used
  by `copilot`, `codex-github`, `claude-code-action`, etc.).

### Configuration Layer

- [ ] **`.ai-dev-workflow.yaml` — update `Supported today` comment** (AC-1): The
  comment on the `github:` reviewer keys (line ~44) lists the currently
  supported platforms. Add `bugbot` to that list. Optionally add a short
  comment block documenting the `BUGBOT_BOT_LOGIN`, `BUGBOT_CHECK_NAME`, and
  `BUGBOT_TRIGGER_COMMENT` override variables, analogous to the existing
  `codex-github` / `copilot` option blocks. **Do not** add a new integration
  guide file — downstream Bugbot setup documentation is a separate epic child
  (see Verification Log: setup-doc scope boundary). This is the only config
  change; it does not alter behavior for repositories that do not list `bugbot`
  (AC-8).

### Test Layer (`scripts/development-workflow/tests/`)

- [ ] **`test-pr-review-loop.sh` — add HARNESS_MODE unit tests for the Bugbot
  platform** (AC-9): Append a new test area section (e.g., "Area N: Bugbot
  platform function"). See **Testing Strategy** for the required scenarios and
  representative payloads. Reuse the existing mock infrastructure
  (`MOCK_GH_OUTPUT`, `MOCK_GH_CALL_LOG`, head-SHA / check-runs mocks) and the
  `run_test` assertion helper; source the script with `HARNESS_MODE=1` and call
  `run_bugbot_review` directly.

---

## Testing Strategy

**Test types**: Unit (HARNESS_MODE), Manual / smoke

**Key scenarios to test** (each maps to a spec AC):

1. `bugbot` is recognized by `run_platform_review` — no `unsupported-platform`
   fallback; `bot_login_for_platform bugbot` returns `cursor[bot]` (AC-1, AC-7).
2. **No-findings outcome**: "Cursor Bugbot" check run completes with conclusion
   `success` and no blocking `cursor[bot]` comments → exit 0, `RESULT=clean`,
   `BLOCKING_COUNT=0`, plus `COMMENT_COUNT` and `SUGGESTION_COUNT` emitted (AC-2,
   AC-4).
3. **Blocking-findings outcome**: check run completes with conclusion
   `action_required` (or `failure`) and one or more `cursor[bot]` review
   comments carrying `BUGBOT_REVIEW` / `BUGBOT_BUG_ID` / `LOCATIONS` and a
   severity heading → exit 1, `RESULT=needs_fixes`, `BLOCKING_COUNT>=1`, and at
   least one `BLOCKING_1_PATH` / `BLOCKING_1_LINE` / `BLOCKING_1_BODY` summary
   line with severity + location context (AC-2, AC-3, AC-6).
4. **Timeout outcome**: check run never reaches `completed` within `max_wait` →
   exit 2, `RESULT=escalate`, `REASON=timeout`, and not reported as clean (AC-5).
5. **Unavailable outcome**: the "Cursor Bugbot" check run never appears and no
   `cursor[bot]` verdict is present (Cursor app not installed) → exit 2,
   `RESULT=escalate`, `REASON=unavailable`, and not reported as clean (AC-5).
6. **Informational note is not a blocker**: a `neutral`/`cancelled` conclusion,
   or a non-blocking `cursor[bot]` note, is counted as a suggestion and does not
   set `BLOCKING_COUNT>0` or hold the PR back (AC-4).
7. No behavior change for a repository that does not list `bugbot` (AC-8).
8. HARNESS_MODE unit tests pass for the no-findings, blocking, and
   timeout/unavailable paths (AC-9).

**Representative payloads to mock** (AC-9 requires at minimum the blocking,
no-findings, and timeout/unavailable outcomes):

- A `check-runs` JSON response where the `Cursor Bugbot` run has
  `status:"completed"` and `conclusion:"success"` (no-findings).
- A `check-runs` JSON response where the run has
  `conclusion:"action_required"`, plus a `cursor[bot]` review-comment payload
  whose body contains `BUGBOT_REVIEW`, `BUGBOT_BUG_ID`, `LOCATIONS`, and a
  severity heading (blocking + summary).
- A `check-runs` JSON response where the run stays `status:"in_progress"` for
  the whole poll window (timeout) and one where the `Cursor Bugbot` run is
  entirely absent (unavailable).

**Smoke test runbook**:
`docs/testing/workflow/990-bugbot-reviewer-platform.smoke-test.md`

**Regression suite**: The repository's regression coverage for the reviewer
loop is the HARNESS_MODE unit suite `test-pr-review-loop.sh`; the new Bugbot
area is the regression coverage for this feature. No separate regression-spec
framework exists in this repository.

### Parser-risk addendum

**Not applicable.** Although `run_bugbot_review()` extracts a small set of
structured Bugbot finding markers (`BUGBOT_REVIEW`, `BUGBOT_BUG_ID`,
`LOCATIONS`, severity headings) from `cursor[bot]` comment bodies, this is
lightweight field lookup over GitHub-API JSON comment bodies — not a custom
parser/lint/scanner module. The change introduces no file under
`scripts/lint/` or `scripts/parse/`, no module named `*lint*` / `*parser*` /
`*scanner*` / `*tokenizer*`, and no regex-engine or structured-text rule engine
over markdown/code/config/logs. The classification driver is the check-run
**conclusion** (a discrete enum), not text parsing. Finding-marker extraction is
covered by the blocking-findings unit scenario above, which asserts the severity
and location context appear in the emitted `BLOCKING_*_BODY` summary.

### Concurrent-event-source addendum

**Not applicable.** `run_bugbot_review()` is a synchronous, single-threaded
bash poll loop. It does not register concurrent event listeners, socket
callbacks, or timers sharing mutable state; it polls a GitHub endpoint
sequentially and uses the script's existing single-instance lock and
`_interruptible_sleep` mechanism for orderly interruption. No new concurrency
pattern is introduced.

---

## Seed Data

None — this is a shell-script, configuration-comment, and test change. No
application data is required. All test inputs are mocked `gh` API JSON payloads
defined inline in `test-pr-review-loop.sh`.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| N/A | N/A | N/A |

---

## Documentation Updates

> Listed for the developer to execute during implementation — not performed at
> Plan Ready.

- [ ] `.ai-dev-workflow.yaml` — Update the `Supported today` reviewer-platform
  comment to include `bugbot`, and optionally add a `bugbot` override-variable
  comment block (`BUGBOT_BOT_LOGIN`, `BUGBOT_CHECK_NAME`,
  `BUGBOT_TRIGGER_COMMENT`). This is advisory documentation inside a config file
  (see Layer-by-Layer Changes).

No updates to `docs/project/`, `docs/best-practices/`, or `AGENTS.md` are
required: this feature adds one optional reviewer platform behind the existing
config mechanism and changes no existing workflow convention. The downstream
Bugbot integration guide / `.cursor/BUGBOT.md` setup documentation is explicitly
**out of scope** for this item (separate epic #988 child) and must not be
created here.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Bugbot's actual check-run name or `cursor[bot]` login differs from the assumed values across Cursor app versions | Med | Med | Make the check-run name (`BUGBOT_CHECK_NAME`, default `Cursor Bugbot`) and bot login (`BUGBOT_BOT_LOGIN`, default `cursor[bot]`) env-overridable, the same pattern as `CODEX_GITHUB_BOT_LOGIN` / `COPILOT_BOT_LOGIN`. Filter check runs by both `.app.slug` and `.name` (as `run_devin_review()` does) to be resilient. |
| Bugbot signals its verdict only via check run **or** only via reviews/comments depending on outcome | Med | Med | Reconcile both signals (check-run conclusion + `cursor[bot]` reviews/comments), mirroring the established `run_devin_review()` dual-signal handling; classify on the conclusion but read comments for the blocking summary. |
| A missing/absent Bugbot verdict is misread as "clean" | Low | High | Explicitly map "no completed check run within `max_wait`" and "check run never published" to `RESULT=escalate` (`timeout` / `unavailable`), never `clean` (AC-5). Covered by the timeout and unavailable unit scenarios. |
| Trigger comment posted repeatedly across poll cycles | Low | Low | Trigger only when no recent/in-progress Bugbot run exists for the current head; idempotent trigger (same pattern as greptile's recent-trigger detection). |
| Bugbot informational note miscounted as a blocker | Med | Low | Treat `neutral`/`cancelled`/`skipped` conclusions and non-blocking notes as suggestions (`SUGGESTION_COUNT`), not blockers (AC-4). Covered by the informational-note unit scenario. |
| HARNESS_MODE unit tests tightly coupled to internal function shape | Low | Low | Follow the existing `test-pr-review-loop.sh` pattern (mock `gh` output, source with `HARNESS_MODE=1`, call the function directly). |

---

## Code Samples

> All samples below are illustrative — adapt during implementation. Production
> code belongs in the implementation PR.

### `run_platform_review` dispatch addition (illustrative)

```bash
# Illustrative — adapt during implementation
bugbot)
  run_bugbot_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
  ;;
```

### `bot_login_for_platform` case addition (illustrative)

```bash
# Illustrative — adapt during implementation
bugbot) printf '%s\n' "${BUGBOT_BOT_LOGIN:-cursor[bot]}" ;;
```

### `run_bugbot_review()` skeleton (illustrative)

```bash
# Illustrative — adapt during implementation. Mirrors run_devin_review() (check
# run) + run_greptile_review() (comment/review finding summary). Not production code.

run_bugbot_review() {
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="bugbot"
  local bot_login="${BUGBOT_BOT_LOGIN:-cursor[bot]}"
  local check_name="${BUGBOT_CHECK_NAME:-Cursor Bugbot}"
  local trigger_comment="${BUGBOT_TRIGGER_COMMENT:-bugbot run}"
  local repo head_sha elapsed=0 conclusion="" status=""

  require_gh
  cd_workflow_repo_root
  repo="$(repo_slug)"

  head_sha="$(gh api "repos/$repo/pulls/$pr_number" --jq '.head.sha')"
  if [ -z "$head_sha" ]; then
    print_kv RESULT escalate
    print_kv REASON head-sha-unavailable
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    return 2
  fi

  # Phase 1: existing blocking cursor[bot] findings on current head → needs_fixes (return 1)
  # Phase 2: post "$trigger_comment" only if no recent/in-progress Cursor Bugbot run
  # Phase 3: poll the "Cursor Bugbot" check run on $head_sha until completed or timeout

  while [ "$elapsed" -lt "$max_wait" ]; do
    # Re-resolve head SHA each iteration so a mid-review push retargets the filter.
    read -r status conclusion < <(
      gh api "repos/$repo/commits/$head_sha/check-runs" --paginate \
        | jq -s -r --arg name "$check_name" '
            [ .[].check_runs[]
              | select((.app.slug | test("cursor"; "i")) or (.name == $name)) ]
            | last
            | (.status // "") + " " + (.conclusion // "")
          '
    )
    if [ "$status" = "completed" ]; then
      case "$conclusion" in
        success)                 : ;;  # read comments; clean if no blocking findings
        failure|action_required) : ;;  # blocking → needs_fixes (return 1) with summary
        neutral|cancelled|skipped) : ;;  # informational → clean, count as suggestion
        timed_out)
          print_kv RESULT escalate
          print_kv REASON timeout
          print_kv PLATFORM "$platform"
          print_kv PR_NUMBER "$pr_number"
          print_kv BRANCH "$branch_name"
          print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
          return 2
          ;;
      esac
      break
    fi
    _interruptible_sleep "$poll_interval"
    elapsed=$(( elapsed + poll_interval ))
  done

  # If no completed run within max_wait → escalate timeout (or unavailable when
  # the check run never appeared). Never report clean on an absent verdict.
}
```

### HARNESS_MODE unit test sketch (illustrative)

```bash
# Illustrative — adapt during implementation

echo ""
echo "=== Area N: Bugbot platform function ==="

# Test N.1: no-findings — Cursor Bugbot check run conclusion=success
MOCK_GH_OUTPUT='[{"check_runs":[{"name":"Cursor Bugbot","app":{"slug":"cursor"},"status":"completed","conclusion":"success"}]}]'
# ... source with HARNESS_MODE=1, call run_bugbot_review, assert RESULT=clean, BLOCKING_COUNT=0

# Test N.2: blocking — conclusion=action_required + cursor[bot] finding with markers
# ... assert RESULT=needs_fixes, BLOCKING_COUNT>=1, BLOCKING_1_BODY carries severity + LOCATIONS

# Test N.3: timeout — check run stays in_progress for the whole window
# ... assert RESULT=escalate, REASON=timeout, exit 2
```

---

## Implementation Order

> Later steps may depend on earlier ones.

1. **Read `scripts/development-workflow/pr-review-loop.sh` in full** — note the
   exact line numbers of (a) the end of `run_copilot_review()` and the start of
   `run_haystack_review()` (insertion point for the new function), (b) the
   `run_platform_review()` `case` block, and (c) the `bot_login_for_platform()`
   `case` block. Study `run_devin_review()` (check-run polling) and
   `run_greptile_review()` (comment/review blocking summary) as the two patterns
   to combine.

2. **Add `run_bugbot_review()`** after `run_copilot_review()` and before
   `run_haystack_review()`, following the illustrative skeleton and the
   Layer-by-Layer behavior list. Verify after insertion that:
   - the signature takes exactly four positional args
     (`pr_number`, `branch_name`, `poll_interval`, `max_wait`);
   - exit codes 0, 1, and 2 are all reachable;
   - every `print_kv` uses `PLATFORM "$platform"` (not a hardcoded string) and
     terminal paths always emit `RESULT`, `COMMENT_COUNT`, `BLOCKING_COUNT`,
     `SUGGESTION_COUNT`;
   - `_interruptible_sleep` (not `sleep`) is used in the poll loop;
   - an absent/missing verdict maps to `escalate` (`timeout`/`unavailable`),
     never `clean`.

3. **Add the `bugbot)` case to `run_platform_review()`** after the `haystack)`
   case and before the `*)` fallback. Confirm the case label is exactly `bugbot`.

4. **Add the `bugbot)` entry to `bot_login_for_platform()`** returning
   `"${BUGBOT_BOT_LOGIN:-cursor[bot]}"`. Confirm the default uses the `[bot]`
   suffix format consistent with the other entries.

5. **Update `.ai-dev-workflow.yaml`** — add `bugbot` to the `Supported today`
   reviewer-platform comment, and optionally add a `bugbot` override-variable
   comment block (`BUGBOT_BOT_LOGIN`, `BUGBOT_CHECK_NAME`,
   `BUGBOT_TRIGGER_COMMENT`). Do **not** create any integration guide file.

6. **Add HARNESS_MODE unit tests** to
   `scripts/development-workflow/tests/test-pr-review-loop.sh` — append a new
   test area covering the no-findings, blocking (with marker summary), and
   timeout/unavailable scenarios (plus the informational-note non-blocking
   scenario). Follow the existing mock + `run_test` infrastructure. Confirm the
   suite still exits 0:

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   bash "$REPO_ROOT/scripts/development-workflow/tests/test-pr-review-loop.sh"
   ```

7. **Verify the smoke test runbook** at
   `docs/testing/workflow/990-bugbot-reviewer-platform.smoke-test.md` is accurate
   against the implemented behavior and that every acceptance criterion is
   exercised by a runbook step.

8. **Pre-commit lint** — run `markdownlint-cli2` on the plan and smoke runbook:

   ```bash
   REPO_ROOT=$(git rev-parse --git-common-dir)/..
   "$REPO_ROOT/node_modules/.bin/markdownlint-cli2" \
     "docs/specs/developments/20260617122727_bugbot-reviewer-platform/2_bugbot-reviewer-platform_plan.md" \
     "docs/testing/workflow/990-bugbot-reviewer-platform.smoke-test.md"
   ```

9. **Cross-section consistency self-check** — confirm these are identical
   everywhere they appear: function name `run_bugbot_review`; platform token
   `bugbot`; bot login default `cursor[bot]` and env var `BUGBOT_BOT_LOGIN`;
   check-run name default `Cursor Bugbot` and env var `BUGBOT_CHECK_NAME`;
   trigger comment default `bugbot run` and env var `BUGBOT_TRIGGER_COMMENT`;
   exit-code contract 0 = clean, 1 = needs\_fixes, 2 = escalate.

10. **Commit** — `feat(pr-review-loop): add Cursor Bugbot review platform (#990)`.

11. **Update `CHANGELOG.md`** under `[Unreleased]` — add:

    ```text
    - **Add Cursor Bugbot as a supported automated PR reviewer platform** (#990): `bugbot` is now a recognized value for `review.on_draft.github` / `review.on_ready.github` in `.ai-dev-workflow.yaml`; when declared, `pr-review-loop.sh` triggers Cursor Bugbot, polls the "Cursor Bugbot" check run on the PR head, classifies the verdict (clean / blocking / timeout / unavailable), summarizes blocking `cursor[bot]` findings with severity and location context, and emits the standard per-platform telemetry. Bugbot's threads are included in platform thread auditing. Timeout and unavailable states are surfaced explicitly and are never treated as a clean pass.
    ```

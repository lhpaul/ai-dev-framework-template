#!/usr/bin/env bash

set -euo pipefail

# Use BASH_SOURCE[0] so that SCRIPT_DIR resolves correctly even when this
# script is sourced by the test harness (in HARNESS_MODE=1).  When executed
# directly, BASH_SOURCE[0] is identical to $0.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

# Effective harness mode: only active when HARNESS_MODE=1 AND the script is
# sourced (BASH_SOURCE[0] != $0). When executed directly with HARNESS_MODE=1
# set in the environment, treat it as a normal run so the lock guard and all
# signal traps remain active and protect the real PR.
_HARNESS_MODE_EFFECTIVE=0
if [ "${HARNESS_MODE:-0}" -eq 1 ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then
  _HARNESS_MODE_EFFECTIVE=1
fi

# ---------------------------------------------------------------------------
# Truncated-run detection (issue #1562)
#
# A run killed part-way through — by an outer `timeout` shorter than a
# legitimate rate-limit wait, or by an operator, or by a session ending —
# used to produce output with no terminal RESULT= line at all. A caller
# grepping for RESULT= finds nothing, and "no blocking findings were reported"
# reads uncomfortably like "no blocking findings exist". The exit code is
# non-zero in that case (124 from timeout, 143 from SIGTERM), but the exit code
# is precisely what an orchestrator loses when it captures stdout through a
# pipeline or a log file.
#
# So every exit is made to carry a terminal RESULT=. print_kv is wrapped here
# to record that a RESULT line was emitted, and the EXIT trap below emits
# RESULT=escalate / REASON=truncated_run when none ever was.
_RESULT_EMITTED=0

# Overrides the definition sourced from workflow-lib.sh, deliberately: wrapping
# the single choke point every RESULT line already passes through is what makes
# this cover all ~100 emission sites without annotating each one.
print_kv() {
  if [ "$1" = "RESULT" ]; then
    _RESULT_EMITTED=1
  fi
  printf '%s=%s\n' "$1" "$2"
}

# _emit_truncation_guard <exit-status>
#
# Emits a terminal RESULT for a run that produced none. The status the caller
# should exit with is the function's RETURN CODE, not stdout: stdout is where
# the RESULT lines go, so returning the status there would have made
# `status="$(_emit_truncation_guard "$status")"` capture the RESULT lines into
# the status and hand `exit` a multi-line string.
_emit_truncation_guard() {
  local status="$1"
  if [ "$_RESULT_EMITTED" -eq 1 ]; then
    return "$status"
  fi
  print_kv RESULT escalate
  print_kv REASON truncated_run
  print_kv TRUNCATED 1
  print_kv TRUNCATED_EXIT_STATUS "$status"
  echo "ERROR: pr-review-loop.sh exited without reaching a verdict (status ${status})." >&2
  echo "  This run was truncated — treat it as NOT reviewed, not as clean." >&2
  echo "  Common cause: an outer 'timeout' shorter than a single rate-limit wait." >&2
  echo "  See PR_REVIEW_LOOP_EXECUTION_BUDGET in this script's header for the" >&2
  echo "  wall clock a caller must allow." >&2
  # A truncated run must never look successful, whatever killed it.
  if [ "$status" -eq 0 ]; then
    status=2
  fi
  return "$status"
}

BUGBOT_HANDLED_SKIP_RC=3

# ---------------------------------------------------------------------------
# Execution budget vs. rate-limit ceiling (issue #1562)
#
# These two numbers were in direct tension and nothing reconciled them:
#
#   - The worst-case legitimate CodeRabbit rate-limit wait is
#     CODERABBIT_RATE_LIMIT_MAX_RETRIES x CODERABBIT_RATE_LIMIT_WAIT, which at
#     the defaults (4 x 900s) is 3600s — a full hour in which the loop is
#     working correctly and has nothing to report.
#   - A run was killed at roughly 65 minutes of foreground polling during the
#     #1503 work. So the maximum legitimate wait sat within a few minutes of
#     the observed kill threshold.
#
# Two runners then made it worse by wrapping the loop in an outer `timeout`
# SHORTER than a single 900s rate-limit wait, guaranteeing truncation on any
# rate-limited PR.
#
# PR_REVIEW_LOOP_EXECUTION_BUDGET is the wall clock a caller must allow for
# this script. The invariant is checked at startup: the worst-case rate-limit
# wait must be strictly less than the budget, so a correctly-configured run can
# always finish waiting before the budget it declares. Raising the retry count
# or the per-retry wait without also raising the budget is a configuration
# error, and is reported as one rather than discovered as a truncated run an
# hour later.
#
# Callers: allow at least this many seconds. Do NOT wrap this script in a
# `timeout` shorter than it. If you must bound it more tightly, lower
# CODERABBIT_RATE_LIMIT_MAX_RETRIES or CODERABBIT_RATE_LIMIT_WAIT and lower the
# budget to match, so the invariant still holds.
# The shipped CodeRabbit rate-limit defaults, declared once. Both the review
# path and the budget invariant below read them from here: the two must agree,
# and they previously restated 4 and 900 independently, which is precisely the
# drift that lets a budget check pass while the real wait is something else.
# Raised to span an hourly vendor quota reset by issue #1509.
CODERABBIT_RATE_LIMIT_MAX_RETRIES_DEFAULT=4
CODERABBIT_RATE_LIMIT_WAIT_DEFAULT=900

PR_REVIEW_LOOP_EXECUTION_BUDGET_DEFAULT=5400
PR_REVIEW_LOOP_EXECUTION_BUDGET="${PR_REVIEW_LOOP_EXECUTION_BUDGET:-$PR_REVIEW_LOOP_EXECUTION_BUDGET_DEFAULT}"

# _check_execution_budget — verify worst-case rate-limit wait < execution budget.
# Emits BUDGET_* key/value lines so a caller can record what it must allow.
_check_execution_budget() {
  local retries="${CODERABBIT_RATE_LIMIT_MAX_RETRIES:-$CODERABBIT_RATE_LIMIT_MAX_RETRIES_DEFAULT}"
  local wait_s="${CODERABBIT_RATE_LIMIT_WAIT:-$CODERABBIT_RATE_LIMIT_WAIT_DEFAULT}"
  local budget="$PR_REVIEW_LOOP_EXECUTION_BUDGET"

  case "$retries" in ''|*[!0-9]*) retries="$CODERABBIT_RATE_LIMIT_MAX_RETRIES_DEFAULT" ;; esac
  case "$wait_s" in ''|*[!0-9]*) wait_s="$CODERABBIT_RATE_LIMIT_WAIT_DEFAULT" ;; esac
  case "$budget" in ''|*[!0-9]*) budget="$PR_REVIEW_LOOP_EXECUTION_BUDGET_DEFAULT" ;; esac

  # Upper bounds, checked BEFORE any arithmetic. Bash integers are 64-bit and
  # wrap silently: retries=99999999999999999 multiplied out to a NEGATIVE worst
  # case, which then compared as comfortably under budget and reported the
  # invariant satisfied — the check accepting exactly the unsafe configuration
  # it exists to reject. Bounding the inputs is what makes the comparison
  # below meaningful; a digit string beyond these is a misconfiguration, not a
  # value to clamp silently.
  #
  # The limits are deliberately generous — far past anything operationally
  # sensible — because their job is to keep the arithmetic honest, not to
  # express policy.
  local max_retries=1000        # 1000 retries at any sane wait is already days
  local max_wait=86400          # one day per retry
  local max_budget=604800       # one week of wall clock
  local bound_error=""
  if [ "${#retries}" -gt 10 ] || [ "$(( 10#$retries ))" -gt "$max_retries" ]; then
    bound_error="CODERABBIT_RATE_LIMIT_MAX_RETRIES=$retries exceeds the maximum of $max_retries"
  elif [ "${#wait_s}" -gt 10 ] || [ "$(( 10#$wait_s ))" -gt "$max_wait" ]; then
    bound_error="CODERABBIT_RATE_LIMIT_WAIT=$wait_s exceeds the maximum of $max_wait"
  elif [ "${#budget}" -gt 10 ] || [ "$(( 10#$budget ))" -gt "$max_budget" ]; then
    bound_error="PR_REVIEW_LOOP_EXECUTION_BUDGET=$budget exceeds the maximum of $max_budget"
  fi
  if [ -n "$bound_error" ]; then
    print_kv BUDGET_INVARIANT violated
    echo "ERROR: $bound_error." >&2
    echo "  Values beyond these bounds overflow 64-bit arithmetic and would make" >&2
    echo "  the budget comparison meaningless." >&2
    print_kv RESULT escalate
    print_kv REASON execution_budget_misconfigured
    return 1
  fi

  # 10# forces base 10. The guards above accept any all-digit string, including
  # a zero-padded one, and bash reads a leading-zero operand inside $(( )) as
  # octal — so CODERABBIT_RATE_LIMIT_MAX_RETRIES=08 passed the guard and then
  # died with "value too great for base", crashing the very check that exists
  # to turn a misconfiguration into a clean escalation.
  local worst
  worst=$(( 10#$retries * 10#$wait_s ))
  budget=$(( 10#$budget ))
  print_kv BUDGET_EXECUTION_SECONDS "$budget"
  print_kv BUDGET_WORST_CASE_RATE_LIMIT_WAIT_SECONDS "$worst"

  if [ "$worst" -ge "$budget" ]; then
    print_kv BUDGET_INVARIANT violated
    echo "ERROR: worst-case rate-limit wait (${retries} x ${wait_s}s = ${worst}s) is not less than" >&2
    echo "  the execution budget (${budget}s). A rate-limited PR could not finish waiting" >&2
    echo "  inside the budget this run declares, so it would be truncated rather than" >&2
    echo "  reviewed. Raise PR_REVIEW_LOOP_EXECUTION_BUDGET, or lower" >&2
    echo "  CODERABBIT_RATE_LIMIT_MAX_RETRIES / CODERABBIT_RATE_LIMIT_WAIT." >&2
    print_kv RESULT escalate
    print_kv REASON execution_budget_misconfigured
    return 1
  fi
  print_kv BUDGET_INVARIANT ok
  return 0
}

# CODERABBIT_SKIP_BANNER_RE — matches the CodeRabbit "Review skipped" banner.
#
# CodeRabbit posts this banner instead of a review whenever it declines to review a
# PR by configuration rather than by capacity: `reviews.auto_review.enabled: false`
# ("Auto reviews are disabled on this repository"), `auto_review.drafts: false` on a
# draft PR, or an `auto_review.base_branches` list that does not match the PR base
# (e.g. only `develop` listed while the PR targets a `develop-<slug>` integration
# branch).
#
# It must never be counted as review activity. Before this constant existed, the
# activity probe in run_coderabbit_review excluded only the pause, rate-limit, and
# resume markers, so the skip banner satisfied "CodeRabbit posted something" and
# broke the poll loop into Phase 3 — which then collected zero inline comments and
# zero CHANGES_REQUESTED reviews and returned RESULT=clean for a PR CodeRabbit had
# never looked at. Same false-clean class as #1437 (rate-limited SUCCESS status) and
# the PR #650 pause-banner incident, both already fixed for their own banner shapes.
#
# Deliberately NOT a bare "review skipped" substring match. A genuine walkthrough
# is free to contain that phrase in prose ("this review skipped the generated
# files"), and misclassifying a real review as a banner is the mirror-image
# failure: the loop would ignore an actual review, poll to timeout, and escalate.
# The three alternatives are ordered most to least machine-specific:
#   1. the HTML marker CodeRabbit stamps on skip comments and on no other kind;
#   2. the banner's markdown heading, REQUIRED to carry the blockquote prefix
#      CodeRabbit always renders it with (the banner lives inside a
#      "> [!IMPORTANT]" callout, so the body contains "> ## Review skipped").
#      A bare "## Review skipped" heading is deliberately NOT matched: a genuine
#      comment is free to use that heading, and misclassifying a real review as a
#      banner is the mirror-image failure — the review would be dropped from the
#      activity probe, polled to timeout, and escalated. If the vendor ever drops
#      the callout wrapper, alternative 1 still covers the banner;
#   3. the auto-review-disabled sentence, as a belt-and-braces fallback.
#
# Passed into jq as --arg skip_re with test($skip_re; "i") and to grep -qiE, so it
# must stay an alternation valid in both Oniguruma and POSIX ERE, with no anchors
# and no backslash escapes that differ between the two.
CODERABBIT_SKIP_BANNER_RE='skip review by coderabbit|> *#{1,6} *review skipped|auto reviews are disabled'

# --- unlock subcommand ---
# Must run before the single-instance lock guard so stale-lock recovery always
# works: if a previous invocation crashed, the lock guard would re-acquire the
# lock for this process before `unlock` could check it, causing `unlock` to see
# a live PID and refuse to remove the (now re-owned) lock dir.
if [ "${1:-}" = "unlock" ]; then
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
    echo "Usage: $0 unlock <pr-number>" >&2
    exit 64
  fi
  _UNLOCK_PR="$2"
  _UNLOCK_LOCK_DIR="/tmp/pr-review-loop-${_UNLOCK_PR}.lockdir"
  # Read lock metadata only when the dir exists; surface failures explicitly so
  # filesystem or permission errors are not silently swallowed.
  _UNLOCK_PID=""
  _UNLOCK_CMD=""
  if [ -d "$_UNLOCK_LOCK_DIR" ]; then
    if ! _UNLOCK_PID="$(cat "$_UNLOCK_LOCK_DIR/pid" 2>/dev/null)"; then
      echo "ERROR: could not read lock PID from $_UNLOCK_LOCK_DIR/pid — cannot verify ownership." >&2
      echo "  If you are certain no process holds this lock, remove it manually: rm -rf $_UNLOCK_LOCK_DIR" >&2
      exit 1
    fi
    if ! _UNLOCK_CMD="$(cat "$_UNLOCK_LOCK_DIR/cmd" 2>/dev/null)"; then
      echo "ERROR: could not read lock cmd from $_UNLOCK_LOCK_DIR/cmd — cannot verify ownership." >&2
      echo "  If you are certain no process holds this lock, remove it manually: rm -rf $_UNLOCK_LOCK_DIR" >&2
      exit 1
    fi
  fi
  if [ -n "$_UNLOCK_PID" ] && kill -0 "$_UNLOCK_PID" 2>/dev/null && [ "$_UNLOCK_CMD" = "$(basename "$0")" ]; then
    echo "ERROR: A live pr-review-loop.sh process (PID $_UNLOCK_PID) currently holds the lock for PR #${_UNLOCK_PR}. Not removing a live lock." >&2
    echo "  Wait for the process to finish, or send it SIGTERM to stop it gracefully." >&2
    exit 1
  fi
  if [ -d "$_UNLOCK_LOCK_DIR" ]; then
    rm -rf "$_UNLOCK_LOCK_DIR"
    echo "OK: stale lock removed for PR #${_UNLOCK_PR} ($_UNLOCK_LOCK_DIR)."
    exit 0
  else
    echo "OK: no lock found for PR #${_UNLOCK_PR} ($_UNLOCK_LOCK_DIR). Nothing to remove."
    exit 0
  fi
fi

# In harness mode (sourced), skip the single-instance lock guard entirely.
# The guard is irrelevant when the script is sourced by the test harness
# (no real PR is being processed and no lock directory should be created).
if [ "$_HARNESS_MODE_EFFECTIVE" -ne 1 ]; then

# --- Single-instance guard ---
# Prevent two simultaneous invocations for the same PR. Uses an atomic mkdir
# lock directory (POSIX-guaranteed atomic) so two concurrent callers cannot
# both acquire the lock. The lock dir name includes the PR number so parallel
# runs for different PRs do not interfere with each other.
#
# Layout:
#   /tmp/pr-review-loop-<pr>.lockdir/   — lock directory (atomic creation)
#   /tmp/pr-review-loop-<pr>.lockdir/pid — PID of the owner process
#   /tmp/pr-review-loop-<pr>.lockdir/cmd — basename of script ($0) for verification
_PR_ARG=""
_skip_next=0
for _arg in "$@"; do
  if [ "$_skip_next" -eq 1 ]; then _skip_next=0; continue; fi
  case "$_arg" in
    --branch|--platform|--poll-interval|--max-wait|--pre-trigger-wait|--repo|--product-repo|--repo-root) _skip_next=1 ;;
    [0-9]*) _PR_ARG="$_arg"; break ;;
  esac
done
unset _skip_next
_LOCK_DIR="/tmp/pr-review-loop-${_PR_ARG:-unknown}.lockdir"
_OWN_LOCK=0
_PR_CONFIG_TMPFILE=""
# PID of the current background child (sleep or gh api) started by
# _interruptible_sleep / _interruptible_gh.  The TERM/INT handlers kill this
# child before removing the lock so the signal fires promptly instead of waiting
# for the foreground command to return on its own.
CURRENT_CHILD_PID=""

if mkdir "$_LOCK_DIR" 2>/dev/null; then
  # We created the lock dir atomically — we own the lock.
  printf '%d\n' "$$"           > "$_LOCK_DIR/pid"
  printf '%s\n' "$(basename "$0")" > "$_LOCK_DIR/cmd"
  _OWN_LOCK=1
else
  # Lock dir already exists — check whether the recorded owner is still alive
  # and actually belongs to this script (guards against stale locks from crashes).
  _LOCK_PID="$(cat "$_LOCK_DIR/pid" 2>/dev/null || true)"
  _LOCK_CMD="$(cat "$_LOCK_DIR/cmd" 2>/dev/null || true)"
  if [ -n "$_LOCK_PID" ] && kill -0 "$_LOCK_PID" 2>/dev/null && [ "$_LOCK_CMD" = "$(basename "$0")" ]; then
    echo "ERROR: pr-review-loop.sh is already running for PR #${_PR_ARG:-unknown} (PID $_LOCK_PID). Exiting to prevent parallel execution." >&2
    echo "  Lock file: $_LOCK_DIR" >&2
    echo "  If the process is dead (stale lock from a crash), recover with:" >&2
    echo "    ./scripts/development-workflow/pr-review-loop.sh unlock ${_PR_ARG:-<pr>}" >&2
    echo "  Or manually: rm -rf $_LOCK_DIR" >&2
    print_kv RESULT escalate
    print_kv REASON lock_contention
    print_kv LOCK_DIR "$_LOCK_DIR"
    print_kv PR_NUMBER "${_PR_ARG:-}"
    exit 75  # EX_TEMPFAIL — lock contention; not a normal review result (0/1/2)
  fi
  # Stale lock (process gone or belongs to a different script) — reclaim atomically.
  # Use mv (atomic rename) to move the stale dir out of the way, then mkdir.
  # If two callers reach this point simultaneously, only one mv succeeds (rename
  # is atomic on POSIX); the loser's mv fails because the source is gone. Then
  # both try mkdir; only one succeeds and the other exits via the else branch.
  mv "$_LOCK_DIR" "${_LOCK_DIR}.stale.$$" 2>/dev/null || true
  rm -rf "${_LOCK_DIR}.stale.$$" 2>/dev/null || true
  if mkdir "$_LOCK_DIR" 2>/dev/null; then
    printf '%d\n' "$$"           > "$_LOCK_DIR/pid"
    printf '%s\n' "$(basename "$0")" > "$_LOCK_DIR/cmd"
    _OWN_LOCK=1
  else
    echo "ERROR: pr-review-loop.sh is already running for PR #${_PR_ARG:-unknown} (concurrent startup race). Exiting to prevent parallel execution." >&2
    echo "  Lock file: $_LOCK_DIR" >&2
    echo "  If the process is dead (stale lock from a crash), recover with:" >&2
    echo "    ./scripts/development-workflow/pr-review-loop.sh unlock ${_PR_ARG:-<pr>}" >&2
    echo "  Or manually: rm -rf $_LOCK_DIR" >&2
    print_kv RESULT escalate
    print_kv REASON lock_contention
    print_kv LOCK_DIR "$_LOCK_DIR"
    print_kv PR_NUMBER "${_PR_ARG:-}"
    exit 75
  fi
fi
_on_exit() {
  local status=$?
  [ "$_OWN_LOCK" -eq 1 ] && rm -rf "$_LOCK_DIR"
  [ -n "$_PR_CONFIG_TMPFILE" ] && rm -f "$_PR_CONFIG_TMPFILE"
  # Runs on death-by-signal too: the TERM/INT handlers below re-raise, and bash
  # still runs the EXIT trap on the way out (verified for both `timeout` and a
  # direct SIGTERM), which is what lets a killed run report itself.
  _emit_truncation_guard "$status" || status=$?
  exit "$status"
}
trap _on_exit EXIT
# SIGTERM/SIGINT handlers: kill the current background child (if any) so the
# handler fires promptly even while a foreground sleep or gh api call is
# running, then clean up the lock dir and re-raise the signal so the parent
# process sees the correct exit status (death-by-signal, not 0).
# The re-raise pattern (trap - SIG; kill -SIG $$) is required because bash
# normally translates signal death to exit code 128+N, which callers rely on
# to distinguish a killed process from a clean exit.
trap '[ -n "$CURRENT_CHILD_PID" ] && kill -TERM "$CURRENT_CHILD_PID" 2>/dev/null || true; [ "$_OWN_LOCK" -eq 1 ] && rm -rf "$_LOCK_DIR"; trap - TERM; kill -TERM "$$"' TERM
trap '[ -n "$CURRENT_CHILD_PID" ] && kill -TERM "$CURRENT_CHILD_PID" 2>/dev/null || true; [ "$_OWN_LOCK" -eq 1 ] && rm -rf "$_LOCK_DIR"; trap - INT;  kill -INT  "$$"' INT

fi  # end HARNESS_MODE guard (single-instance lock guard skipped in harness mode)

# ---------------------------------------------------------------------------
# _interruptible_sleep <seconds>
#
# Runs "sleep <seconds>" as a background job, records its PID in
# CURRENT_CHILD_PID, then waits for it.  Bash's built-in `wait` IS
# interruptible by signals (unlike a foreground `sleep`), so TERM/INT traps
# fire promptly.  The trap handler kills CURRENT_CHILD_PID before removing
# the lock, completing the prompt-cleanup chain.
# ---------------------------------------------------------------------------
_interruptible_sleep() {
  sleep "$1" &
  CURRENT_CHILD_PID=$!
  wait "$CURRENT_CHILD_PID" 2>/dev/null || true
  CURRENT_CHILD_PID=""
}

usage() {
  cat <<'EOF'
Usage: ./scripts/development-workflow/pr-review-loop.sh <pr-number> [--branch name] [--repo owner/repo|product-name] [--product-repo name] [--repo-root path] [--platform greptile] [--platform greptile,devin,pr-agent,coderabbit,coderabbit-cli,local-ai-reviewer,codex-github,claude-code-action,copilot,haystack,bugbot] [--ready-phase haystack] [--phase-after-clean haystack] [--draft-github-only] [--pre-after-clean-only] [--poll-interval seconds] [--max-wait seconds] [--pre-trigger-wait seconds] [--post-final-summary] [--compare]
       ./scripts/development-workflow/pr-review-loop.sh unlock <pr-number>

Runs the automated PR review loop for one or more platforms in sequence. Before
triggering a new review, each platform checks for existing blocking findings. If
any platform reports blocking findings, the script stops immediately and exits 1.
If a platform times out or escalates, the script exits 2. If all configured
platforms are clean or skipped, the script exits 0. If a second instance is
detected for the same PR number, the script emits RESULT=escalate with
REASON=lock_contention and exits 75 (EX_TEMPFAIL).

Subcommands:
  unlock <pr-number>
    Remove the stale lock directory for a PR whose previous run crashed without
    cleaning up. Safe to run when no review loop is actively running for that PR.
    Use this to recover autonomously when lock_contention is reported but the
    recorded PID is no longer alive.

    Example:
      ./scripts/development-workflow/pr-review-loop.sh unlock 123

    The lock directory path is /tmp/pr-review-loop-<pr>.lockdir. You can also
    remove it manually with: rm -rf /tmp/pr-review-loop-<pr>.lockdir

--post-final-summary:
  Compatibility no-op. The script now posts or updates the
  "Automated Reviewer Loop Summary" comment on every needs_fixes exit, not only
  final/max-cycle exits. Existing callers may keep passing this flag.

--compare:
  Run all configured platforms to completion regardless of individual verdicts
  (disables the short-circuit on the first blocking platform). After all platforms
  run, the overall exit code and RESULT are identical to what normal mode would
  produce: the first platform that would have blocked in config order governs.
  Per-platform verdicts are emitted as COMPARE_VERDICT_<n>_PLATFORM /
  COMPARE_VERDICT_<n>_RESULT key=value lines, and one row is appended to
  docs/workflow/retro-metrics-platforms.md. Intended for platform evaluation only —
  not for normal orchestration where early exit is desired.

--ready-phase:
  Mark one or more platforms as ready-phase reviewers that should run only after
  draft-phase GitHub reviewers are clean and the PR has been converted with
  gh pr ready. This does not override normal platform order; it emits
  READY_PHASE_* key=value telemetry and compatibility PHASE_AFTER_CLEAN_* keys.
  When omitted, the script reads review.on_ready.github from
  .ai-dev-workflow.yaml when present.

--phase-after-clean:
  Deprecated compatibility alias for --ready-phase.

--draft-github-only:
  Run only review.on_draft.github reviewers. Use this for draft PR gates that
  must clear draft-compatible GitHub reviewers before converting the PR to ready
  and allowing ready-phase reviewers to run.

--pre-after-clean-only:
  Deprecated compatibility alias for --draft-github-only.

Platform selection (in priority order):
  1. --platform flag(s) passed on the command line
  2. review.on_draft.github + review.on_ready.github in .ai-dev-workflow.yaml
     at the repo root
  3. Legacy review.platforms / review.phase_after_clean compatibility mapping

Branch-type-aware default timeout:
  On spec/* and implementation-plan/* branches, Devin has no trigger condition and
  exits immediately with REASON=no_check_run. To avoid wasting the full 20-minute
  default wait budget on these branches, the script automatically reduces
  --max-wait to PR_REVIEW_LOOP_DOC_MAX_WAIT seconds (default: 180) and
  --poll-interval to 30 s when the branch matches spec/* or
  implementation-plan/* and the caller did not pass the respective flag
  explicitly. poll_interval is also reduced when needed so it stays below
  max_wait — the per-loop timeout check requires elapsed >= max_wait, which can
  only fire after at least one poll_interval has elapsed. Pass --max-wait and/or
  --poll-interval explicitly to override either value.

Large-diff poll-window extension:
  CodeRabbit takes significantly longer to post its review on PRs with a large
  number of changed files (e.g., release PRs or sync-template PRs). When the
  caller did not pass --max-wait explicitly, the script fetches the PR's changed-
  files count and extends max_wait when it exceeds a threshold.

  Environment variables (both optional):
    LARGE_DIFF_THRESHOLD  — changed-files count above which the extension applies
                            (default: 50; must be a positive integer)
    LARGE_DIFF_MAX_WAIT   — extended max_wait in seconds for large-diff PRs
                            (default: 2400, i.e. 40 minutes; must be a positive integer)

  The extension is suppressed when --max-wait is passed explicitly. The emitted
  key=value output includes CHANGED_FILES_COUNT so callers can inspect the value.

Outputs stable key=value lines including:
  RESULT=clean|needs_fixes|needs_rerun|waiting_on_reviewer|escalate|skipped
  PLATFORM_<n>_NAME / PLATFORM_<n>_RESULT
  REASON=lock_contention (when exit code is 75)
  CHANGED_FILES_COUNT=<n> (PR's changed-files count, or -1 when the fetch failed)
  LARGE_DIFF_EXTENDED=1 (present and set to 1 when max_wait was extended for a large-diff PR)
  REASON=late_review_threads (when post-clean recheck finds new unresolved threads)
  COMPARE_MODE=1 (when --compare is active)
  COMPARE_VERDICT_<n>_PLATFORM / COMPARE_VERDICT_<n>_RESULT (when --compare is active)
  DRAFT_GITHUB_ONLY=0|1
  READY_PHASE_ENABLED=0|1
  READY_PHASE_STARTED=0|1
  READY_PHASE_PLATFORM_LIST=<comma-separated platforms>
  READY_PHASE_FILTERED_OUT=<comma-separated platforms> (when configured ready-phase platforms are absent from this invocation)
  READY_PHASE_GATE_RESULT=<result> (emitted only after the phase starts)
  READY_PHASE_SKIP_REASON=<result> (emitted when the phase never starts)
  READY_PHASE_NET_NEW_BLOCKER=0|1 (1 when a ready-phase platform blocks)
  PHASE_AFTER_CLEAN_ENABLED=0|1
  PHASE_AFTER_CLEAN_STARTED=0|1
  PHASE_AFTER_CLEAN_PLATFORM_LIST=<comma-separated platforms>
  PHASE_AFTER_CLEAN_FILTERED_OUT=<comma-separated platforms> (compatibility alias for READY_PHASE_FILTERED_OUT)
  PHASE_AFTER_CLEAN_GATE_RESULT=<result> (emitted only after the phase starts)
  PHASE_AFTER_CLEAN_SKIP_REASON=<result> (emitted when the phase never starts)
  PHASE_AFTER_CLEAN_NET_NEW_BLOCKER=0|1 (compatibility alias for READY_PHASE_NET_NEW_BLOCKER)
  LOCAL_SECOND_PASS=0|1 (1 when a second local pass ran before the ready-phase gate)
  LOCAL_SECOND_PASS_REASON=not_required|head_changed|prior_findings|no_evidence|no_local_reviewer|failed_for_head|head_moved_during_pass|local_pass_unavailable
  POST_CLEAN_RECHECK=0|1 (1 when the post-clean settle-and-recheck ran)
  POST_CLEAN_RECHECK_SKIP_REASON=<reason> (present only when POST_CLEAN_RECHECK=0: not_clean,
    compare_mode, skip_env, no_thread_posting_platforms, or no_pr_number — so a caller can tell
    "nothing to settle" from "settling was suppressed" (issue #1574))
  POST_CLEAN_SETTLED=0|1 (1 when the platform went quiet for the full required period; 0 when the
    window was exhausted while it was still active — the verdict is still clean, but weaker)
  POST_CLEAN_SETTLE_TIMEOUT=1 (present only when the window was exhausted before silence)
  POST_CLEAN_SETTLE_WINDOW_SECONDS / POST_CLEAN_SETTLE_QUIET_SECONDS (the values in force)
  POST_CLEAN_ACTIVITY_SEEN=1 (present when the platform acted during the settle window)
  POST_CLEAN_ACTIVITY_PROBE_FAILED=1 (present when an activity query failed; a failed probe is
    never counted as silence)
  POST_CLEAN_SETTLED_AT=<iso8601> (when the verdict was established — a caller that inserts a long
    poll between this and the readiness label is acting on a stale check)
  POST_CLEAN_HEAD_SHA=<sha> (the PR head this run reviewed, read BEFORE any reviewer was dispatched and
    emitted on every clean path; Protocol 91 Check 0.6 refuses the verdict when the live head differs —
    a push after Step 7 voids it — issue #1574)
  LOCAL_AI_CONFIGURED=0|1 (1 when local-ai-reviewer is in the resolved platform list — the applicability
    signal; an absent key means telemetry never reached the consumer and is fail-closed)
  LOCAL_AI_REVIEWED_HEAD=<sha> (the reviewed head reported by local-ai-reviewer; empty when not
    configured or when the reviewer reported no head)
  LOCAL_AI_HEAD_CURRENT=1|0| (1 when local-ai-reviewer classification is current; 0 when not-current;
    empty when not-reported or when local-ai-reviewer is not configured — missing evidence is not a pass)
  Reviewer-loop history ledger (reviewer_loop_history.v1, additive fields; schema string unchanged):
    platform_results[] — per-platform normalized outcome + raw RESULT/REASON (no head; heads stay in
      reviewed_heads[] from #1648). Used to select the local reviewer's most recent verdict.
    missed_findings[] — one element per external platform that reported blocking findings this round
      on an attributable commit: reviewer, reviewed_head, blocking_count, full deduped paths,
      path_total, local_evidence_state, and classification (confirmed_miss|possible_miss|not_a_miss).
      Observational only — never changes readiness, labels, or merge decisions. Summary shows one
      ≤200-character line per record. When history is unappendable and a record was owed, the prior
      history block is preserved and the summary reports the telemetry failure.
  RESULT=needs_fixes REASON=head_moved_during_run (the PR head changed while the reviewers ran, so
    the clean verdict describes a commit the PR has left; nothing to fix — re-run the loop for the
    current HEAD)
  LATE_THREADS_FOUND=<N> (count of newly-found unresolved threads; -1 on audit failure; 0 when POST_CLEAN_RECHECK=0)
  RUN_ID=<id> (this invocation's resolved orchestration-run identifier — either PR_REVIEW_LOOP_RUN_ID
                  verbatim, or a freshly generated "auto-<epoch>-<pid>-<random>" id when unset. See
                  PR_REVIEW_LOOP_RUN_ID below for why callers should set this explicitly to make the
                  per-run cap meaningful across multiple invocations.)
  CYCLE_COUNT=<n> (PER-RUN cap count — Protocol 91's `cycle` value at the start of this invocation:
                  the number of fixer dispatches already issued for RUN_ID, read from the persisted
                  reviewer_loop_history.v1 ledger; -1 when the ledger could not be read reliably.
                  Resets to 0 at each orchestration-run boundary (i.e. whenever RUN_ID changes).
                  Never reset by a HEAD SHA change alone — see max_cycles below.)
  MAX_CYCLES=<n> (the configured PER-RUN cycle cap; default 10, see PR_REVIEW_LOOP_MAX_CYCLES below)
  TOTAL_CYCLE_COUNT=<n> (LIFETIME ceiling count — the same distinct-HEAD-SHA fixer-dispatch count as
                  CYCLE_COUNT, but across the PR's ENTIRE review-loop lifetime regardless of RUN_ID;
                  never resets. -1 when the ledger could not be read reliably (always -1 exactly when
                  CYCLE_COUNT is also -1 — both come from the same ledger read).)
  MAX_TOTAL_CYCLES=<n> (the configured LIFETIME cycle ceiling; default 25, see
                  PR_REVIEW_LOOP_MAX_TOTAL_CYCLES below)
  REASON=max_cycles_exceeded (RESULT=escalate; emitted when CYCLE_COUNT reaches MAX_CYCLES (the
                  PER-RUN cap) while the loop would otherwise still report needs_fixes or needs_rerun
                  — Protocol 91:1719's cap, conforming verbatim: "Initialize cycle = 0 once per
                  orchestration run ... escalate when the run reaches max_cycles". A "clean" result is
                  never overridden by this check. The cap applies uniformly to every re-invocation of
                  this script within the same RUN_ID regardless of whether the fix that triggered it
                  was applied inline or by a dispatched fixer subagent — there is only one per-run
                  counter.)
  REASON=max_total_cycles_exceeded (RESULT=escalate; emitted when TOTAL_CYCLE_COUNT reaches
                  MAX_TOTAL_CYCLES (the LIFETIME ceiling, which never resets) while the loop would
                  otherwise still report needs_fixes or needs_rerun. Checked only after the per-run
                  cap does not fire, so this REASON specifically signals "many separate orchestration
                  runs, each individually under the per-run cap, cumulatively exceeded the lifetime
                  budget" — distinct from max_cycles_exceeded so an operator can tell the two apart.)
  REASON=cycle_count_unavailable (RESULT=escalate; emitted when CYCLE_COUNT/TOTAL_CYCLE_COUNT are -1
                  — the persisted cycle ledger could not be read after retries — while the loop would
                  otherwise still report needs_fixes or needs_rerun. Fails closed rather than silently
                  disabling both cap backstops indefinitely for this PR.)
  REASON=ledger_persist_failed (RESULT=escalate, exit 2; emitted when this cycle's own
                  reviewer_loop_history.v1 ledger entry could not be reliably written — either
                  because both the PATCH to the existing summary comment and the create-fallback
                  failed, OR because the pre-write READ of the existing comment failed (which makes
                  the write fall back to an "unavailable" stub that silently drops this cycle's entry
                  even when the stub itself is posted successfully) — while this cycle's own result
                  was needs_fixes or needs_rerun. Without this check, the caller would dispatch a
                  fixer for a cycle that a future invocation's cycle count would never see, letting
                  repeated persistence or read failures (e.g. a token that can read but not write
                  comments, or a transient read blip on an otherwise-successful write) slip past both
                  caps indefinitely. Persistence is attempted, and this correction applied, BEFORE
                  RESULT=/REASON= are printed — exactly ONE RESULT= / REASON= pair is ever emitted per
                  invocation, so this REASON is safe to read with either a "first match" or "last
                  match" key=value parser.)
  EXPENSIVE_REVIEWERS_REORDERED=1 (emitted once per run when expensive reviewers were moved last
                  within their own phase bucket; never crosses the draft/ready boundary)
  EXPENSIVE_GATE_PLATFORM / EXPENSIVE_GATE_RESULT / EXPENSIVE_GATE_REASON / EXPENSIVE_GATE_HEAD
  EXPENSIVE_GATE_DEFERRALS / EXPENSIVE_GATE_MAX_DEFERRALS
                  Emitted per expensive platform (currently codex-github) immediately before dispatch.
                  RESULT is dispatched|deferred|forced|deferral_cap. Conditions are evaluated in order:
                  (1) local-ai-reviewer configured and current-head clean evidence,
                  (2) every preceding peer (same-bucket non-expensive + earlier buckets) has
                  acceptable evidence (clean, or skipped with allow-listed reason),
                  (3) zero unresolved non-outdated review threads on the same head,
                  (4) non-empty non-reviewer baseline checks all green on the same head.
                  Fail-closed on unreadable inputs (evidence_unavailable_*). A deferred outcome sets
                  RESULT=needs_fixes REASON=expensive_gate_deferred so readiness is withheld and
                  Step 7 re-runs; it also breaks the platform iteration so later ready-phase platforms
                  do not run. When the ready-phase transition is about to start and any remaining
                  ready-phase platform is expensive, those expensive gates are preflighted BEFORE
                  gh pr ready with peer scope earlier_buckets (same-bucket peers like bugbot are
                  not required yet — they need ready state themselves); the full per-platform
                  gate still runs again immediately before run_platform_review. Deferrals are bounded
                  by PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS
                  (default 3, head-scoped occurrence count); at the cap the loop escalates.
  EXPENSIVE_GATE_ESCALATION=expensive_gate_deferral_cap|expensive_gate_deferral_budget_unreadable
                  Emitted ONLY when EXPENSIVE_GATE_RESULT=deferral_cap — exhausted budget vs
                  unreadable ledger. Absent otherwise.
  REASON=expensive_gate_deferred (RESULT=needs_fixes; expensive reviewer held back)
  REASON=expensive_gate_deferral_cap|expensive_gate_deferral_budget_unreadable (RESULT=escalate)

Environment variables:
  POST_CLEAN_SETTLE_QUIET=<sec>      Consecutive seconds of platform silence required before a clean verdict is
                                     called settled (issue #1556). Defaults per platform: 120 for coderabbit /
                                     coderabbit-cli, 60 otherwise. Any platform activity — including an in-place
                                     EDIT of an existing bot comment — resets this timer.
  POST_CLEAN_SETTLE_WINDOW=<sec>     Maximum total time to spend settling (default: 900 for coderabbit /
                                     coderabbit-cli, 180 otherwise — sized from the measured ~12 min
                                     walkthrough-to-review gap on PR #1573). If the window is exhausted while the platform
                                     is still active, the verdict stays clean but is reported UNSETTLED via
                                     POST_CLEAN_SETTLED=0 and POST_CLEAN_SETTLE_TIMEOUT=1.
  POST_CLEAN_POLL=<seconds>          Interval between settle re-checks (default: 60 for coderabbit /
                                     coderabbit-cli, 30 otherwise).
  POST_CLEAN_REQUIRE_REVIEW=0|1      Whether silence alone may satisfy the settle, or whether a SUBMITTED review
                                     for the current HEAD is required first (default: 1 for coderabbit /
                                     coderabbit-cli, 0 otherwise). CodeRabbit posts a walkthrough issue comment
                                     within a minute of the push and then submits the actual review much later —
                                     twelve minutes, measured on PR #1573 — so silence in between means it is
                                     still working, not that it finished. When no review arrives inside the
                                     window the verdict stays clean but reports POST_CLEAN_NO_SUBMITTED_REVIEW=1
                                     alongside POST_CLEAN_SETTLED=0.
  <PLATFORM>_POST_CLEAN_SETTLE_QUIET / _SETTLE_WINDOW / _POLL
                                     Per-platform overrides, taking precedence over the generic forms above.
                                     The platform name is upper-cased with '-' replaced by '_', except that
                                     coderabbit-cli shares the CODERABBIT_ prefix. Example:
                                     CODERABBIT_POST_CLEAN_SETTLE_QUIET=240
                                     When several platforms are configured, the LONGEST window and quiet period
                                     across them are used — any of them can be the one that posts late.
  POST_CLEAN_WAIT=<seconds>          Legacy alias, still honoured: sets the quiet period when no more specific
                                     POST_CLEAN_SETTLE_QUIET (generic or per-platform) is set.
  SKIP_POST_CLEAN_RECHECK=1          Suppress the post-clean recheck. Set by callers re-dispatching after a prior
                                     late-thread fix cycle, so the corrective invocation does not recheck again.
  FALLBACK_THREAD_SETTLE_WAIT=<sec>  Seconds to wait before running the thread audit when using
                                     coderabbit_status_success_fallback (default: 60). CodeRabbit can set a
                                     SUCCESS commit status before finishing its async inline-thread posting; this
                                     wait lets those threads arrive so the audit does not produce a false-clean.
  PR_REVIEW_LOOP_MAX_CYCLES=<n>      Override the PER-RUN reviewer-loop cycle cap (default: 10, matching
                                     Protocol 91:1719's documented value). Also configurable via review.max_cycles
                                     in .ai-dev-workflow.yaml; this env var takes precedence over the config file.
  PR_REVIEW_LOOP_MAX_TOTAL_CYCLES=<n> Override the LIFETIME reviewer-loop cycle ceiling (default: 25). Also
                                     configurable via review.max_total_cycles in .ai-dev-workflow.yaml; this env
                                     var takes precedence over the config file.
  PR_REVIEW_LOOP_RUN_ID=<id>         Set by an orchestrator to group multiple pr-review-loop.sh invocations
                                     under one Protocol-91-style "orchestration run", so the per-run cap
                                     (CYCLE_COUNT/MAX_CYCLES) accumulates correctly across those invocations and
                                     resets when the orchestrator starts a genuinely new run with a new id. When
                                     unset, each invocation is treated as its own isolated run for per-run-cap
                                     purposes (CYCLE_COUNT effectively stays 0) — the LIFETIME ceiling
                                     (TOTAL_CYCLE_COUNT/MAX_TOTAL_CYCLES) still enforces regardless.
  PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS=<n>
                                     Bound on head-scoped expensive-reviewer gate deferrals (default: 3).
                                     Valid range 1–999999; invalid values WARN and fall back to 3.
  PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS=1
                                     Bypass the expensive-reviewer gate for manual escalation. The gate still
                                     evaluates and emits EXPENSIVE_GATE_* with RESULT=forced and the reason it
                                     would have deferred; justify use in the PR.
  PR_REVIEW_LOOP_SMALL_FINDINGS_STOP_ROUNDS=<n>
                                     Consecutive small-findings rounds required before RESULT=clean with
                                     REASON=small_findings_terminal (default: 2; valid range 1–999). A round
                                     qualifies only when every blocking finding is small under the two-tier
                                     rule (normative documents are never small; other non-shipped paths are
                                     small unless the body touches a contract surface), the strict thread
                                     audit is zero, and both prior counted rounds and the deciding round are
                                     on the current PR head for every contributing platform. See Protocol 93.
  SMALL_FINDINGS_BLOCKED_BY=<cause>  Emitted when the small-findings terminal rule does not fire for a content
                                     or currency cause: shipped_path | contract_surface | stale_head |
                                     head_unknown. Within-group precedence: shipped_path over contract_surface;
                                     stale_head over head_unknown. Empty when the rule fired or the run was
                                     simply short. Contract-surface identities include acceptance_criteria,
                                     decision_gates_and_matrices, parser_and_input_behavior, scope_and_coverage,
                                     fail_closed_semantics, state_and_status_models, telemetry_and_contracts,
                                     proof_obligations.
EOF
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

append_platforms() {
  local raw="$1"
  local entry
  IFS=',' read -r -a entries <<< "$raw"
  for entry in "${entries[@]}"; do
    entry="$(trim "$entry")"
    [ -n "$entry" ] && platforms+=("$entry")
  done
}

append_phase_after_clean_platforms() {
  local raw="$1"
  local entry
  IFS=',' read -r -a entries <<< "$raw"
  for entry in "${entries[@]}"; do
    entry="$(trim "$entry")"
    [ -n "$entry" ] && phase_after_clean_platforms+=("$entry")
  done
}

append_ready_phase_platforms() {
  append_phase_after_clean_platforms "$1"
}

array_contains_value() {
  local needle="$1"
  shift
  local value
  for value in "$@"; do
    [ "$needle" = "$value" ] && return 0
  done
  return 1
}

is_phase_after_clean_platform() {
  local candidate="$1"
  array_contains_value "$candidate" "${phase_after_clean_platforms[@]:-}"
}

# Expensive reviewers (issue #1649): platforms whose dispatch is gated on
# current-head local-clean evidence, preceding peer evidence, resolved
# review threads, and green non-reviewer baseline checks. Membership is a
# property of the reviewer, not of repository config.
EXPENSIVE_REVIEWER_PLATFORMS=(codex-github)
EXPENSIVE_GATE_ACCEPTED_SKIP_REASONS=(not_configured explicit-skip release_pr unsupported-platform)
# Resolved once per run by expensive_gate_resolve_max_deferrals (default 3).
expensive_gate_max_deferrals=""
expensive_reviewers_reordered=0
# Last gate outcome for summary/history surfaces (set by expensive_reviewer_gate).
expensive_gate_last_platform=""
expensive_gate_last_result=""
expensive_gate_last_reason=""
expensive_gate_last_head=""
# Strict-spec ledger globals (#1650); set by capture_strict_spec_globals_from_output
# when local-ai-reviewer runs. Object absent from history when not recorded.
strict_spec_recorded=0
strict_spec_state=""
strict_spec_count=""
strict_spec_checks=""
strict_spec_unknown_count=""
strict_spec_reason=""
strict_spec_summary_section=""
# Strict-plan ledger globals (#1655)
strict_plan_recorded=0
strict_plan_state=""
strict_plan_count=""
strict_plan_checks=""
strict_plan_applied=""
strict_plan_unknown_count=""
strict_plan_reason=""
strict_plan_summary_section=""
# Peer evidence collected during this invocation: "platform|result|reason".
declare -a platform_peer_evidence=()

# expensive_gate_sync_last_from_output <gate_kv_output>
#
# Command substitution runs expensive_reviewer_gate in a subshell, so assignments
# to expensive_gate_last_* inside the gate are lost. Rehydrate them from the
# captured EXPENSIVE_GATE_* telemetry before the caller branches or history runs.
expensive_gate_sync_last_from_output() {
  local out="$1"
  expensive_gate_last_platform="$(kv_value_default EXPENSIVE_GATE_PLATFORM "$out" "${expensive_gate_last_platform:-}")"
  expensive_gate_last_result="$(kv_value_default EXPENSIVE_GATE_RESULT "$out" "")"
  expensive_gate_last_reason="$(kv_value_default EXPENSIVE_GATE_REASON "$out" "")"
  expensive_gate_last_head="$(kv_value_default EXPENSIVE_GATE_HEAD "$out" "${expensive_gate_last_head:-}")"
}

is_expensive_reviewer_platform() {
  array_contains_value "$1" "${EXPENSIVE_REVIEWER_PLATFORMS[@]:-}"
}

# reorder_expensive_reviewers_last
#
# Moves expensive reviewers to the end of their own phase bucket without
# crossing the draft/ready boundary. Partitions platforms into non-phase
# and phase_after_clean buckets using is_phase_after_clean_platform, then
# within each bucket places non-expensive platforms first (preserving
# relative order) and expensive platforms last. Sets
# expensive_reviewers_reordered=1 when order changed. Called once after
# platform list resolution, before iteration; the caller emits telemetry.
reorder_expensive_reviewers_last() {
  local platform
  local -a non_phase_cheap=()
  local -a non_phase_expensive=()
  local -a phase_cheap=()
  local -a phase_expensive=()
  local -a reordered=()
  local original_list=""
  local new_list=""

  expensive_reviewers_reordered=0
  [ "${#platforms[@]}" -gt 0 ] || return 0

  original_list="$(IFS=,; printf '%s' "${platforms[*]}")"

  for platform in "${platforms[@]}"; do
    if is_phase_after_clean_platform "$platform"; then
      if is_expensive_reviewer_platform "$platform"; then
        phase_expensive+=("$platform")
      else
        phase_cheap+=("$platform")
      fi
    else
      if is_expensive_reviewer_platform "$platform"; then
        non_phase_expensive+=("$platform")
      else
        non_phase_cheap+=("$platform")
      fi
    fi
  done

  reordered=()
  [ "${#non_phase_cheap[@]}" -gt 0 ] && reordered+=("${non_phase_cheap[@]}")
  [ "${#non_phase_expensive[@]}" -gt 0 ] && reordered+=("${non_phase_expensive[@]}")
  [ "${#phase_cheap[@]}" -gt 0 ] && reordered+=("${phase_cheap[@]}")
  [ "${#phase_expensive[@]}" -gt 0 ] && reordered+=("${phase_expensive[@]}")

  new_list="$(IFS=,; printf '%s' "${reordered[*]}")"
  if [ "$new_list" != "$original_list" ]; then
    expensive_reviewers_reordered=1
    platforms=("${reordered[@]}")
  fi
  return 0
}

# expensive_gate_resolve_max_deferrals
#
# Mirrors reviewer_loop_resolve_max_cycles: default 3, accept 1–999999,
# WARN and fall back on anything else. Reads PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS.
expensive_gate_resolve_max_deferrals() {
  local configured="${PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS:-}"
  local source="env"

  if [ -z "$configured" ]; then
    configured=3
    source="default"
  fi
  if ! [[ "$configured" =~ ^[1-9][0-9]{0,5}$ ]]; then
    echo "WARN: PR_REVIEW_LOOP_MAX_EXPENSIVE_DEFERRALS value '$configured' (source: $source) is not a positive integer within the supported range (1-999999); defaulting to 3" >&2
    configured=3
  fi
  printf '%s\n' "$configured"
}

# expensive_gate_local_ai_configured
#
# Returns 1 when local-ai-reviewer is configured for the repository (from the
# repository's configured platform list, not invocation-filtered platforms[]),
# else 0 (#1656 / #1649 composition).
expensive_gate_local_ai_configured() {
  local configured_line
  if declare -p repo_review_platforms >/dev/null 2>&1 \
      && [ "${#repo_review_platforms[@]}" -gt 0 ]; then
    for configured_line in "${repo_review_platforms[@]}"; do
      configured_line="$(trim "$configured_line")"
      if [ "$configured_line" = "local-ai-reviewer" ]; then
        printf '1\n'
        return 0
      fi
    done
  elif declare -p platforms >/dev/null 2>&1; then
    # Harness fallback when repo_review_platforms was not populated.
    for configured_line in "${platforms[@]:-}"; do
      if [ "$configured_line" = "local-ai-reviewer" ]; then
        printf '1\n'
        return 0
      fi
    done
  else
    while IFS= read -r configured_line; do
      configured_line="$(trim "$configured_line")"
      if [ "$configured_line" = "local-ai-reviewer" ]; then
        printf '1\n'
        return 0
      fi
    done < <(reviewer_loop_repo_configured_platforms)
  fi
  printf '0\n'
}

# expensive_gate_local_ai_head_current <head_sha>
#
# Applies reviewer_loop_head_evidence_classify to the local-ai-reviewer entry
# of platform_reviewed_heads against <head_sha>. Prints 1 (current), 0
# (not-current), or empty (not-reported / missing entry).
expensive_gate_local_ai_head_current() {
  local head_sha="${1:-}"
  local entry platform_name reviewed_head classification state
  local found=0
  local last_reviewed_head=""

  if ! declare -p platform_reviewed_heads >/dev/null 2>&1; then
    printf '\n'
    return 0
  fi

  for entry in "${platform_reviewed_heads[@]:-}"; do
    platform_name="${entry%%:*}"
    reviewed_head="${entry#*:}"
    if [ "$platform_name" = "local-ai-reviewer" ]; then
      found=1
      last_reviewed_head="$reviewed_head"
    fi
  done

  if [ "$found" -eq 1 ]; then
    classification="$(reviewer_loop_head_evidence_classify "$last_reviewed_head" "$head_sha")"
    state="${classification%%|*}"
    case "$state" in
      current) printf '1\n' ;;
      not-current) printf '0\n' ;;
      *) printf '\n' ;;
    esac
    return 0
  fi

  if [ "$found" -eq 0 ]; then
    printf '\n'
  fi
}

# expensive_gate_peer_evidence_acceptable <result> <reason>
#
# Acceptable when result is clean, or skipped with an allow-listed reason
# AND reviewer_failed_label_required_for_result returns false for the pair.
expensive_gate_peer_evidence_acceptable() {
  local result="$1"
  local reason="${2:-}"

  case "$result" in
    clean)
      return 0
      ;;
    skipped)
      if array_contains_value "$reason" "${EXPENSIVE_GATE_ACCEPTED_SKIP_REASONS[@]}"; then
        if ! reviewer_failed_label_required_for_result "$result" "$reason"; then
          return 0
        fi
      fi
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

# expensive_gate_lookup_peer_evidence <platform>
#
# Prints "result|reason" when the platform has run in this invocation,
# or empty when it has not.
expensive_gate_lookup_peer_evidence() {
  local platform="$1"
  local entry peer_name rest
  local last_rest=""

  for entry in "${platform_peer_evidence[@]:-}"; do
    peer_name="${entry%%|*}"
    rest="${entry#*|}"
    if [ "$peer_name" = "$platform" ]; then
      last_rest="$rest"
    fi
  done
  if [ -n "$last_rest" ]; then
    printf '%s\n' "$last_rest"
    return 0
  fi
  printf '\n'
}

# expensive_gate_check_peers <expensive_platform> [peer_scope]
#
# Condition 2: every platform that precedes this expensive reviewer under
# the reordered list (same-bucket non-expensive + every earlier bucket) must
# have run with acceptable evidence. Prints empty on success, or
# peer_reviewer_not_run / peer_reviewer_not_clean.
#
# peer_scope:
#   full (default) — earlier buckets + same-bucket predecessors
#   earlier_buckets — earlier buckets only (used by ready-phase preflight so
#     same-bucket peers like bugbot are not required before gh pr ready)
expensive_gate_check_peers() {
  local expensive_platform="$1"
  local peer_scope="${2:-full}"
  local idx=0
  local expensive_idx=-1
  local platform peer_evidence peer_result peer_reason
  local -a peer_set=()

  for platform in "${platforms[@]:-}"; do
    if [ "$platform" = "$expensive_platform" ]; then
      expensive_idx=$idx
      break
    fi
    idx=$((idx + 1))
  done

  if [ "$expensive_idx" -lt 0 ]; then
    # Platform not in list — defensive; treat as not-run peers.
    printf 'peer_reviewer_not_run\n'
    return 0
  fi

  idx=0
  for platform in "${platforms[@]:-}"; do
    if [ "$idx" -ge "$expensive_idx" ]; then
      break
    fi
    if [ "$peer_scope" = "earlier_buckets" ] && is_phase_after_clean_platform "$platform"; then
      # Ready-phase preflight: same-bucket peers have not run yet (and often
      # cannot, because they themselves require gh pr ready).
      idx=$((idx + 1))
      continue
    fi
    # Peer set: every preceding platform (earlier buckets + same-bucket
    # non-expensive). Expensive members of earlier buckets are included;
    # same-bucket expensive peers that somehow precede us are also peers.
    peer_set+=("$platform")
    idx=$((idx + 1))
  done

  for platform in "${peer_set[@]:-}"; do
    peer_evidence="$(expensive_gate_lookup_peer_evidence "$platform")"
    if [ -z "$peer_evidence" ]; then
      printf 'peer_reviewer_not_run\n'
      return 0
    fi
    peer_result="${peer_evidence%%|*}"
    peer_reason="${peer_evidence#*|}"
    if [ "$peer_reason" = "$peer_result" ]; then
      peer_reason=""
    fi
    if ! expensive_gate_peer_evidence_acceptable "$peer_result" "$peer_reason"; then
      printf 'peer_reviewer_not_clean\n'
      return 0
    fi
  done
  printf '\n'
}

# expensive_gate_unresolved_threads_status <pr_number>
#
# Fetches review threads + live head. Prints "<status> <count_or_-> <head>"
# where status is ok|unavailable. count is unresolved non-outdated threads.
expensive_gate_unresolved_threads_status() {
  local pr_number_arg="$1"
  local repo=""
  local owner name
  local cursor=""
  local has_next=1
  local page=0
  local max_pages=20
  local unresolved=0
  local head_sha=""
  local result=""
  local graphql_query

  if [ -z "$pr_number_arg" ]; then
    printf 'unavailable - \n'
    return 0
  fi

  if ! repo="$(repo_slug 2>/dev/null)" || [ -z "$repo" ]; then
    printf 'unavailable - \n'
    return 0
  fi
  owner="${repo%%/*}"
  name="${repo#*/}"

  graphql_query='query($owner:String!,$repo:String!,$pr:Int!,$cursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$pr){headRefOid reviewThreads(first:100,after:$cursor){pageInfo{hasNextPage endCursor}nodes{isResolved isOutdated}}}}}'

  while [ "$has_next" = "1" ] || [ "$has_next" = "true" ]; do
    page=$((page + 1))
    if [ "$page" -gt "$max_pages" ]; then
      printf 'unavailable - \n'
      return 0
    fi
    if [ -n "$cursor" ]; then
      if ! result="$(
        gh api graphql \
          -f query="$graphql_query" \
          -f owner="$owner" \
          -f repo="$name" \
          -F pr="$pr_number_arg" \
          -f cursor="$cursor" \
          --jq '.data.repository.pullRequest' 2>/dev/null
      )"; then
        printf 'unavailable - \n'
        return 0
      fi
    else
      if ! result="$(
        gh api graphql \
          -f query="$graphql_query" \
          -f owner="$owner" \
          -f repo="$name" \
          -F pr="$pr_number_arg" \
          --jq '.data.repository.pullRequest' 2>/dev/null
      )"; then
        printf 'unavailable - \n'
        return 0
      fi
    fi
    if [ -z "$result" ] || [ "$result" = "null" ]; then
      printf 'unavailable - \n'
      return 0
    fi
    if [ -z "$head_sha" ]; then
      if ! head_sha="$(printf '%s\n' "$result" | jq -r '.headRefOid // ""' 2>/dev/null)"; then
        printf 'unavailable - \n'
        return 0
      fi
    fi
    _eg_page_unresolved=""
    if ! _eg_page_unresolved="$(
      printf '%s\n' "$result" | jq '
        [.reviewThreads.nodes[]?
         | select((.isResolved | not) and (.isOutdated | not))]
        | length'
    )"; then
      printf 'unavailable - \n'
      return 0
    fi
    if [ -z "${_eg_page_unresolved}" ]; then
      printf 'unavailable - \n'
      return 0
    fi
    case "${_eg_page_unresolved}" in
      *[!0-9]*)
        printf 'unavailable - \n'
        return 0
        ;;
    esac
    unresolved=$((unresolved + _eg_page_unresolved))
    unset _eg_page_unresolved
    if ! has_next="$(printf '%s\n' "$result" | jq -r '.reviewThreads.pageInfo.hasNextPage // false')"; then
      printf 'unavailable - \n'
      return 0
    fi
    if ! cursor="$(printf '%s\n' "$result" | jq -r '.reviewThreads.pageInfo.endCursor // empty')"; then
      printf 'unavailable - \n'
      return 0
    fi
    if [ "$has_next" != "true" ] && [ "$has_next" != "1" ]; then
      break
    fi
    if [ -z "$cursor" ]; then
      printf 'unavailable - \n'
      return 0
    fi
  done

  printf 'ok %s %s\n' "$unresolved" "$head_sha"
}

# expensive_gate_baseline_checks_status <pr_number> <expected_head>
#
# Snapshot of non-reviewer checks on the PR. Prints
# "<state> <live_head>" where state is green|failed|pending|empty|unavailable.
# Does NOT call pr-ci-loop.sh. Collapses statusCheckRollup duplicates to the
# latest entry per check key (same normalization as pr-ci-loop.sh) before
# excluding reviewer-owned names and classifying.
expensive_gate_baseline_checks_status() {
  local pr_number_arg="$1"
  local payload=""
  local live_head=""
  local reviewer_names=""
  local normalized_json=""
  local baseline_json=""
  local state=""

  if [ -z "$pr_number_arg" ]; then
    printf 'unavailable \n'
    return 0
  fi

  if ! payload="$(
    gh pr view "$pr_number_arg" --json statusCheckRollup,headRefOid 2>/dev/null
  )"; then
    printf 'unavailable \n'
    return 0
  fi

  live_head="$(printf '%s\n' "$payload" | jq -r '.headRefOid // ""' 2>/dev/null)" || live_head=""
  reviewer_names="$(configured_reviewer_check_names_json "")" || reviewer_names='[]'

  if ! normalized_json="$(
    printf '%s\n' "$payload" | jq '
      (.statusCheckRollup // [])
      | map(
          . + {
            __check_key: (
              if (.context // "") != "" then
                "status:" + .context
              elif (.workflowName // "") != "" and (.name // "") != "" then
                "check:" + .workflowName + "/" + .name
              elif (.name // "") != "" then
                "check:" + .name
              else
                "unknown"
              end
            ),
            __check_ts: (.startedAt // .completedAt // .createdAt // "")
          }
        )
      | sort_by(.__check_key, .__check_ts)
      | group_by(.__check_key)
      | map(last | del(.__check_key, .__check_ts))
    ' 2>/dev/null
  )"; then
    printf 'unavailable %s\n' "$live_head"
    return 0
  fi

  if ! baseline_json="$(
    printf '%s\n' "$normalized_json" | jq --argjson reviewer_names "$reviewer_names" '
      [
        .[]
        | select(
            (.name // .context // .workflowName // "unknown") as $check_name
            | ($reviewer_names | index($check_name) | not)
          )
      ]
    ' 2>/dev/null
  )"; then
    printf 'unavailable %s\n' "$live_head"
    return 0
  fi

  state="$(
    printf '%s\n' "$baseline_json" | jq -r '
      if length == 0 then
        "empty"
      elif any(
            ((.status // "") != "COMPLETED" and (.status // "") != "")
            or ((.state // "") == "PENDING")
            or ((.state // "") == "EXPECTED")
          ) then
        "pending"
      elif any(
            ((.conclusion // "") != "" and (.conclusion // "" | ascii_upcase) as $c
              | ($c != "SUCCESS" and $c != "SKIPPED" and $c != "NEUTRAL" and $c != "NONE"))
            or ((.state // "" | ascii_upcase) as $s
              | ($s == "FAILURE" or $s == "ERROR"))
          ) then
        "failed"
      else
        "green"
      end
    ' 2>/dev/null
  )" || state="unavailable"

  printf '%s %s\n' "${state:-unavailable}" "$live_head"
}

# expensive_gate_deferral_count <head_sha>
#
# Occurrence count of ledger entries whose expensive_gate.result is deferred
# and expensive_gate.head equals <head_sha>. Returns 0 for absent ledger,
# -1 for unreadable ledger (marker present but unparseable / wrong schema /
# history_status != available).
expensive_gate_deferral_count() {
  local head_sha="${1:-}"
  local pr_number_arg="${pr_number:-}"
  local repo="" record="" body="" json="" count=""

  if [ -z "$pr_number_arg" ]; then
    # No PR context (harness unit tests may stub body via MOCK). Treat as absent.
    if [ -n "${EXPENSIVE_GATE_MOCK_LEDGER_BODY+x}" ]; then
      body="${EXPENSIVE_GATE_MOCK_LEDGER_BODY}"
    else
      printf '0\n'
      return 0
    fi
  else
    if [ -n "${EXPENSIVE_GATE_MOCK_LEDGER_BODY+x}" ]; then
      body="${EXPENSIVE_GATE_MOCK_LEDGER_BODY}"
    else
      if ! repo="$(repo_slug 2>/dev/null)" || [ -z "$repo" ]; then
        printf '%s\n' '-1'
        return 0
      fi
      if ! record="$(
          set -o pipefail
          gh api "repos/$repo/issues/$pr_number_arg/comments" --paginate 2>/dev/null \
            | reviewer_loop_history_select_latest_summary_record
        )"; then
        printf '%s\n' '-1'
        return 0
      fi
      body="$(printf '%s\n' "$record" | jq -r '.body // ""' 2>/dev/null)" || body=""
    fi
  fi

  if [ -z "$body" ]; then
    printf '0\n'
    return 0
  fi

  json="$(printf '%s\n' "$body" | reviewer_loop_history_extract_latest_json)"
  if [ -z "$json" ]; then
    if printf '%s\n' "$body" | grep -Fq "$REVIEWER_LOOP_HISTORY_MARKER"; then
      printf '%s\n' '-1'
    else
      printf '0\n'
    fi
    return 0
  fi

  if ! printf '%s\n' "$json" | jq -e --arg schema "$REVIEWER_LOOP_HISTORY_SCHEMA" '
        .schema == $schema
        and (.entries | type) == "array"
        and ((.history_status // "available") == "available")
      ' >/dev/null 2>&1; then
    printf '%s\n' '-1'
    return 0
  fi

  count="$(
    printf '%s\n' "$json" | jq -r --arg head "$head_sha" '
      [
        .entries[]?
        | select((.expensive_gate.result // "") == "deferred")
        | select((.expensive_gate.head // "") == $head)
      ] | length
    ' 2>/dev/null
  )" || count=""

  if ! [[ "$count" =~ ^[0-9]+$ ]]; then
    printf '%s\n' '-1'
    return 0
  fi
  printf '%s\n' "$count"
}

# expensive_reviewer_gate <pr_number> <platform> <head_sha> [peer_scope]
#
# Returns 0 to dispatch, 1 to defer/escalate. Emits EXPENSIVE_GATE_* keys.
# Stops at the first unmet condition so the reason names a single cause.
# peer_scope: full (default) | earlier_buckets (ready-phase preflight).
expensive_reviewer_gate() {
  local pr_number_arg="$1"
  local platform="$2"
  local head_sha="$3"
  local peer_scope="${4:-full}"
  local reason=""
  local deferrals=""
  local configured=""
  local head_current=""
  local peer_reason=""
  local threads_status="" threads_count="" threads_head=""
  local checks_state="" checks_head=""
  local gate_result=""
  local escalation=""

  expensive_gate_last_platform="$platform"
  expensive_gate_last_head="$head_sha"
  expensive_gate_last_reason=""
  expensive_gate_last_result=""

  configured="$(expensive_gate_local_ai_configured)"
  head_current="$(expensive_gate_local_ai_head_current "$head_sha")"

  if [ -z "$head_sha" ]; then
    reason="evidence_unavailable_head"
  elif [ "$configured" = "0" ]; then
    reason="local_reviewer_not_configured"
  elif [ "$configured" != "1" ]; then
    reason="local_evidence_missing"
  elif [ "$head_current" = "0" ]; then
    reason="local_evidence_stale"
  elif [ "$head_current" != "1" ]; then
    reason="local_evidence_missing"
  fi

  if [ -z "$reason" ]; then
    peer_reason="$(expensive_gate_check_peers "$platform" "$peer_scope")"
    if [ -n "$peer_reason" ]; then
      reason="$peer_reason"
    fi
  fi

  if [ -z "$reason" ]; then
    read -r threads_status threads_count threads_head < <(expensive_gate_unresolved_threads_status "$pr_number_arg") || true
    if [ "${threads_status:-}" != "ok" ]; then
      reason="evidence_unavailable_review_threads"
    elif [ -z "${threads_head:-}" ] || [ "$threads_head" != "$head_sha" ]; then
      reason="evidence_head_moved"
    elif [ "${threads_count:-0}" -gt 0 ] 2>/dev/null; then
      reason="unresolved_threads"
    fi
  fi

  if [ -z "$reason" ]; then
    read -r checks_state checks_head < <(expensive_gate_baseline_checks_status "$pr_number_arg" "$head_sha") || true
    if [ -z "${checks_state:-}" ] || [ "$checks_state" = "unavailable" ]; then
      reason="evidence_unavailable_checks"
    elif [ -z "${checks_head:-}" ] || [ "$checks_head" != "$head_sha" ]; then
      reason="evidence_head_moved"
    else
      case "$checks_state" in
        green) : ;;
        failed) reason="baseline_checks_not_green" ;;
        pending) reason="baseline_checks_pending" ;;
        empty) reason="baseline_checks_unobserved" ;;
        *) reason="evidence_unavailable_checks" ;;
      esac
    fi
  fi

  deferrals="$(expensive_gate_deferral_count "$head_sha")"
  if [ -z "${expensive_gate_max_deferrals:-}" ]; then
    expensive_gate_max_deferrals="$(expensive_gate_resolve_max_deferrals)"
  fi

  print_kv EXPENSIVE_GATE_PLATFORM "$platform"
  print_kv EXPENSIVE_GATE_HEAD "$head_sha"
  print_kv EXPENSIVE_GATE_REASON "$reason"
  print_kv EXPENSIVE_GATE_DEFERRALS "$deferrals"
  print_kv EXPENSIVE_GATE_MAX_DEFERRALS "$expensive_gate_max_deferrals"

  if [ -n "$reason" ]; then
    if [ "${PR_REVIEW_LOOP_FORCE_EXPENSIVE_REVIEWERS:-0}" = "1" ]; then
      gate_result="forced"
      expensive_gate_last_result="$gate_result"
      expensive_gate_last_reason="$reason"
      print_kv EXPENSIVE_GATE_RESULT forced
      return 0
    fi
    if [ "$deferrals" = "-1" ]; then
      gate_result="deferral_cap"
      escalation="expensive_gate_deferral_budget_unreadable"
      expensive_gate_last_result="$gate_result"
      expensive_gate_last_reason="$reason"
      print_kv EXPENSIVE_GATE_RESULT deferral_cap
      print_kv EXPENSIVE_GATE_ESCALATION "$escalation"
      return 1
    fi
    if [ "$deferrals" -ge "$expensive_gate_max_deferrals" ] 2>/dev/null; then
      gate_result="deferral_cap"
      escalation="expensive_gate_deferral_cap"
      expensive_gate_last_result="$gate_result"
      expensive_gate_last_reason="$reason"
      print_kv EXPENSIVE_GATE_RESULT deferral_cap
      print_kv EXPENSIVE_GATE_ESCALATION "$escalation"
      return 1
    fi
    gate_result="deferred"
    expensive_gate_last_result="$gate_result"
    expensive_gate_last_reason="$reason"
    print_kv EXPENSIVE_GATE_RESULT deferred
    return 1
  fi

  gate_result="dispatched"
  expensive_gate_last_result="$gate_result"
  expensive_gate_last_reason=""
  print_kv EXPENSIVE_GATE_RESULT dispatched
  return 0
}

filter_pre_after_clean_platforms() {
  local configured_platform
  declare -a filtered=()
  for configured_platform in "${platforms[@]:-}"; do
    if ! is_phase_after_clean_platform "$configured_platform"; then
      filtered+=("$configured_platform")
    fi
  done
  if [ "${#filtered[@]}" -gt 0 ]; then
    platforms=("${filtered[@]}")
  else
    platforms=()
  fi
}

filter_phase_after_clean_platforms() {
  local phase_platform configured_platform matched
  declare -a filtered=()
  declare -a filtered_out=()
  for phase_platform in "${phase_after_clean_platforms[@]:-}"; do
    matched=0
    for configured_platform in "${platforms[@]:-}"; do
      if [ "$phase_platform" = "$configured_platform" ]; then
        filtered+=("$phase_platform")
        matched=1
        break
      fi
    done
    [ "$matched" -eq 0 ] && filtered_out+=("$phase_platform")
  done
  if [ "${#filtered[@]}" -gt 0 ]; then
    phase_after_clean_platforms=("${filtered[@]}")
  else
    phase_after_clean_platforms=()
  fi
  if [ "${#filtered_out[@]}" -gt 0 ]; then
    phase_after_clean_filtered_out="$(IFS=,; printf '%s' "${filtered_out[*]}")"
  else
    phase_after_clean_filtered_out=""
  fi
}

emit_review_lifecycle_duplicate_warnings() {
  local config_file="$1"
  local duplicates
  local duplicate

  [ -f "$config_file" ] || return 0

  duplicates="$(
    {
      workflow_config_review_on_draft_runner "$config_file"
      workflow_config_review_on_draft_github "$config_file"
      workflow_config_review_on_ready_github "$config_file"
    } | sort | uniq -d
  )" || return 0

  while IFS= read -r duplicate; do
    [ -z "$duplicate" ] && continue
    printf 'WARN: review lifecycle config lists reviewer "%s" in more than one bucket; each reviewer should appear only once across on_draft.runner, on_draft.github, and on_ready.github.\n' "$duplicate" >&2
  done <<_REVIEW_DUPLICATE_LINES_
$duplicates
_REVIEW_DUPLICATE_LINES_
}

kv_value() {
  local key="$1"
  local kv_output="$2"
  printf '%s\n' "$kv_output" | awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }'
}

kv_value_default() {
  local key="$1"
  local kv_output="$2"
  local default_value="$3"
  local value
  value="$(kv_value "$key" "$kv_output")"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$default_value"
  fi
}

emit_prefixed_platform_output() {
  local index="$1"
  local kv_output="$2"
  local line
  local key
  local value

  while IFS= read -r line; do
    [ -z "${line:-}" ] && continue
    key="${line%%=*}"
    value="${line#*=}"
    case "$key" in
      RESULT|PR_NUMBER|BRANCH|FIX_AGENT|PLATFORM)
        continue
        ;;
    esac
    printf 'PLATFORM_%s_%s=%s\n' "$index" "$key" "$value"
  done <<< "$kv_output"
}

run_greptile_review() {
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="greptile"
  local bot_login="greptile-apps[bot]"
  local trigger_comment="@greptile review"
  local trigger_author_login="${PR_REVIEW_TRIGGER_AUTHOR_LOGIN:-}"
  local repo
  local review_comment_id=""
  local review_window_start=""
  local recent_trigger_comment
  local existing_thumbs_up
  local head_sha=""
  local since_iso=""
  local existing_comments=""
  local existing_reviews=""
  local existing_blocking_file=""
  local existing_blocking_count=0
  local existing_suggestion_count=0
  local comment_json=""
  local review_json=""
  local body=""
  local blocking_lines_file=""
  local elapsed=0
  local thumbs_up=0
  local comments=""
  local blocking_reviews=""
  local blocking_count=0
  local suggestion_count=0
  local comment_count=0
  local index=1
  local blocking_json=""

  trap 'rm -f "${existing_blocking_file:-}" "${blocking_lines_file:-}"' RETURN

  require_gh
  cd_workflow_repo_root
  repo="$(repo_slug)"

  if [ -z "$trigger_author_login" ]; then
    trigger_author_login="$(gh api user --jq '.login')"
  fi

  recent_trigger_comment="$(
    gh api "repos/$repo/issues/$pr_number/comments" --paginate \
      | jq --arg author "$trigger_author_login" \
          --arg trigger "$trigger_comment" \
          --argjson max_wait "$max_wait" \
          '
            .[]
            | select(
                .user.login == $author and
                .body == $trigger and
                ((now - (.created_at | fromdateiso8601)) <= $max_wait)
              )
            | {id, created_at}
          ' \
      | jq -s 'sort_by(.created_at) | last // empty'
  )"

  if [ -n "$recent_trigger_comment" ]; then
    review_comment_id="$(printf '%s\n' "$recent_trigger_comment" | jq -r '.id')"
    review_window_start="$(printf '%s\n' "$recent_trigger_comment" | jq -r '.created_at')"
    existing_thumbs_up="$(
      gh api "repos/$repo/issues/comments/$review_comment_id/reactions" \
        | jq --arg bot "$bot_login" '[.[] | select(.content == "+1" and .user.login == $bot)] | length'
    )"
    if [ "$existing_thumbs_up" -gt 0 ]; then
      review_comment_id=""
      review_window_start=""
    fi
  fi

  if [ -z "$review_comment_id" ]; then
    head_sha="$(gh api "repos/$repo/pulls/$pr_number" --jq '.head.sha')"
    if [ -n "$head_sha" ]; then
      since_iso="$(gh api "repos/$repo/commits/$head_sha" --jq '.commit.committer.date // empty')"
    fi
    if [ -z "$since_iso" ]; then
      since_iso="$(date -u -v-24H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '24 hours ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo '1970-01-01T00:00:00Z')"
    fi

    existing_comments="$(
      gh api "repos/$repo/pulls/$pr_number/comments" --paginate \
        | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
            .[]
            | select(.user.login == $bot and .created_at > $since)
            | { path, line: (.line // .original_line // 0), body: (.body // ""), commit_id: (.commit_id // "") }
            | @json
          '
    )"
    existing_reviews="$(
      gh api "repos/$repo/pulls/$pr_number/reviews" --paginate \
        | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
            .[]
            | select(
                .user.login == $bot and
                .submitted_at > $since and
                .state == "CHANGES_REQUESTED"
              )
            | { path: "", line: 0, body: (.body // "CHANGES_REQUESTED review without body"), commit_id: (.commit_id // .commitId // "") }
            | @json
          '
    )"

    existing_blocking_file="$(mktemp)"
    while IFS= read -r comment_json; do
      [ -z "${comment_json:-}" ] && continue
      body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
      [ -z "$body" ] && continue
      if is_soft_suggestion "$body"; then
        existing_suggestion_count=$((existing_suggestion_count + 1))
        continue
      fi
      existing_blocking_count=$((existing_blocking_count + 1))
      printf '%s\n' "$comment_json" >> "$existing_blocking_file"
    done <<< "$existing_comments"

    while IFS= read -r review_json; do
      [ -z "${review_json:-}" ] && continue
      body="$(printf '%s\n' "$review_json" | jq -r '.body')"
      [ -z "$body" ] && continue
      existing_blocking_count=$((existing_blocking_count + 1))
      printf '%s\n' "$review_json" >> "$existing_blocking_file"
    done <<< "$existing_reviews"

    if [ "$existing_blocking_count" -gt 0 ]; then
      print_kv RESULT needs_fixes
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REASON existing_findings
      print_kv COMMENT_COUNT "$((existing_blocking_count + existing_suggestion_count))"
      print_kv BLOCKING_COUNT "$existing_blocking_count"
      print_kv SUGGESTION_COUNT "$existing_suggestion_count"
      while IFS= read -r blocking_json; do
        [ -z "${blocking_json:-}" ] && continue
        print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
        print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
        print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
        index=$((index + 1))
      done < "$existing_blocking_file"
      reviewer_loop_print_reviewed_head_from_json_lines < "$existing_blocking_file"
      rm -f "$existing_blocking_file"
      return 1
    fi

    rm -f "$existing_blocking_file"
    review_window_start="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    review_comment_id="$(gh api "repos/$repo/issues/$pr_number/comments" --method POST --raw-field body="$trigger_comment" --jq '.id')"
  fi

  if [ -z "$review_comment_id" ]; then
    echo "Failed to determine review comment ID for PR #$pr_number." >&2
    return 2
  fi

  blocking_lines_file="$(mktemp)"

  while :; do
    thumbs_up="$(
      gh api "repos/$repo/issues/comments/$review_comment_id/reactions" \
        | jq --arg bot "$bot_login" '[.[] | select(.content == "+1" and .user.login == $bot)] | length'
    )"

    if [ "$thumbs_up" -gt 0 ]; then
      break
    fi

    if [ "$elapsed" -ge "$max_wait" ]; then
      rm -f "$blocking_lines_file"
      print_kv RESULT escalate
      print_kv REASON timeout
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID "$review_comment_id"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      return 2
    fi

    _interruptible_sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
  done

  comments="$(
    gh api "repos/$repo/pulls/$pr_number/comments" --paginate \
      | jq -r --arg bot "$bot_login" --arg since "$review_window_start" '
        .[]
        | select(.user.login == $bot and .created_at > $since)
        | {
            path,
            line: (.line // .original_line // 0),
            body: (.body // ""),
            commit_id: (.commit_id // "")
          }
        | @json
      '
  )"

  blocking_reviews="$(
    gh api "repos/$repo/pulls/$pr_number/reviews" --paginate \
      | jq -r --arg bot "$bot_login" --arg since "$review_window_start" '
        .[]
        | select(
            .user.login == $bot and
            .submitted_at > $since and
            .state == "CHANGES_REQUESTED"
          )
        | {
            path: "",
            line: 0,
            body: (.body // "CHANGES_REQUESTED review without body"),
            commit_id: (.commit_id // .commitId // "")
        }
        | @json
      '
  )"

  while IFS= read -r comment_json; do
    [ -z "${comment_json:-}" ] && continue
    body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    comment_count=$((comment_count + 1))
    if is_soft_suggestion "$body"; then
      suggestion_count=$((suggestion_count + 1))
      continue
    fi
    blocking_count=$((blocking_count + 1))
    printf '%s\n' "$comment_json" >> "$blocking_lines_file"
  done <<< "$comments"

  while IFS= read -r review_json; do
    [ -z "${review_json:-}" ] && continue
    body="$(printf '%s\n' "$review_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    comment_count=$((comment_count + 1))
    blocking_count=$((blocking_count + 1))
    printf '%s\n' "$review_json" >> "$blocking_lines_file"
  done <<< "$blocking_reviews"

  if [ "$blocking_count" -gt 0 ]; then
    print_kv RESULT needs_fixes
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID "$review_comment_id"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT "$comment_count"
    print_kv BLOCKING_COUNT "$blocking_count"
    print_kv SUGGESTION_COUNT "$suggestion_count"
    while IFS= read -r blocking_json; do
      [ -z "${blocking_json:-}" ] && continue
      print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
      print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
      print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
      index=$((index + 1))
    done < "$blocking_lines_file"
    reviewer_loop_print_reviewed_head_from_json_lines < "$blocking_lines_file"
    rm -f "$blocking_lines_file"
    return 1
  fi

  rm -f "$blocking_lines_file"
  print_kv RESULT clean
  print_kv PLATFORM "$platform"
  print_kv PR_NUMBER "$pr_number"
  print_kv BRANCH "$branch_name"
  print_kv REVIEW_COMMENT_ID "$review_comment_id"
  print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
  print_kv COMMENT_COUNT "$comment_count"
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT "$suggestion_count"
  # Clean path: unique commit_id across the comments/reviews just examined.
  {
    printf '%s\n' "$comments"
    printf '%s\n' "$blocking_reviews"
  } | reviewer_loop_print_reviewed_head_from_json_lines
  return 0
}

run_codex_github_review() {
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local pre_trigger_wait="${5:-${CODEX_GITHUB_PRE_TRIGGER_WAIT:-}}"
  local platform="codex-github"
  local bot_login="${CODEX_GITHUB_BOT_LOGIN:-chatgpt-codex-connector[bot]}"
  # REST API endpoints (e.g. /pulls/{n}/reviews, /issues/{n}/comments) return
  # bot logins WITH the "[bot]" suffix (e.g. "chatgpt-codex-connector[bot]").
  # GraphQL API returns bot logins WITHOUT the "[bot]" suffix
  # (e.g. "chatgpt-codex-connector"). Strip it here so check_unresolved_threads,
  # which queries GraphQL, compares against the correct login form.
  local graphql_bot_login="${bot_login%\[bot\]}"
  local repo
  local reviewer_script
  local script_exit=0
  local script_output=""
  local thread_check_output=""
  local thread_check_status=0
  local unresolved_count=0

  require_gh
  cd_workflow_repo_root
  repo="$(repo_slug)"

  # Phase 1: Check for existing unresolved review threads from the codex bot.
  # mode=provisional (#1508): a thread whose last comment is a non-bot reply
  # posted after the current head commit does not block re-triggering the
  # review here — see check_unresolved_threads for why this cannot cause a
  # false RESULT=clean.
  set +e
  thread_check_output="$(check_unresolved_threads "$pr_number" "$repo" provisional "$graphql_bot_login")"
  thread_check_status=$?
  set -e
  if [ "$thread_check_status" -eq 0 ]; then
    unresolved_count="$thread_check_output"
  else
    # Thread check failed — escalate rather than proceeding with stale unresolved_count=0,
    # which would dispatch a new review even if blocking threads already exist.
    print_kv RESULT escalate
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv REASON thread-check-failed
    return 2
  fi

  if [ "$unresolved_count" -gt 0 ]; then
    reviewer_loop_print_reviewed_head_from_unresolved_bot_threads "$pr_number" "$repo" "$graphql_bot_login"
    reviewer_loop_print_blocking_from_unresolved_bot_threads "$pr_number" "$repo" "$graphql_bot_login" || true
    print_kv RESULT needs_fixes
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv REASON existing_findings
    print_kv COMMENT_COUNT "$unresolved_count"
    print_kv BLOCKING_COUNT "$unresolved_count"
    print_kv SUGGESTION_COUNT 0
    return 1
  fi

  # Phase 2: Trigger the codex-github review and wait for response
  reviewer_script="$(workflow_repo_root)/scripts/development-workflow/codex-github-reviewer.sh"

  local owner repo_name
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"
  local max_retriggers
  max_retriggers="${CODEX_GITHUB_MAX_RETRIGGERS:-1}"
  case "$max_retriggers" in
    ''|*[!0-9]*) max_retriggers=1 ;;
  esac

  # Keep polling interval bounded by the wait budget to avoid zero-poll attempts
  # when a caller provides poll_interval > max_wait.
  local effective_poll_interval
  effective_poll_interval="$poll_interval"
  if [ "$effective_poll_interval" -gt "$max_wait" ]; then
    effective_poll_interval="$max_wait"
  fi
  local reviewer_args=(
    "$pr_number" "$owner" "$repo_name"
    --bot-login "$bot_login"
    --poll-interval "$effective_poll_interval"
    --max-wait "$max_wait"
    --max-retriggers "$max_retriggers"
  )
  if [ -n "$pre_trigger_wait" ]; then
    reviewer_args+=(--pre-trigger-wait "$pre_trigger_wait")
  fi
  set +e
  script_output="$("$reviewer_script" "${reviewer_args[@]}" 2>&1)"
  script_exit=$?
  set -e

  case "$script_exit" in
    0)
      print_kv RESULT clean
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      print_kv REVIEWED_HEAD "$(kv_value_default REVIEWED_HEAD "$script_output" "")"
      return 0
      ;;
    1)
      unresolved_count=0
      local actual_unresolved_count=0
      # mode=strict: this recount feeds the caller's needs_fixes/COMMENT_COUNT
      # reporting and must reflect true resolution state, not the provisional
      # reply relaxation used to decide whether to trigger the review above.
      set +e
      thread_check_output="$(check_unresolved_threads "$pr_number" "$repo" strict "$graphql_bot_login")"
      thread_check_status=$?
      set -e
      if [ "$thread_check_status" -eq 0 ]; then
        unresolved_count="$thread_check_output"
        actual_unresolved_count="$unresolved_count"
      fi
      [ "$unresolved_count" -eq 0 ] && unresolved_count=1

      reviewer_loop_print_reviewed_head_from_unresolved_bot_threads "$pr_number" "$repo" "$graphql_bot_login"
      reviewer_loop_print_blocking_from_unresolved_bot_threads "$pr_number" "$repo" "$graphql_bot_login" || true

      # Companion script REVIEWED_HEAD is artifact-derived on terminal safe-fail
      # paths with no unresolved threads; do not fall back when threads exist
      # (multi-commit thread heads must stay unattributable per AC-11) or when
      # the thread audit could not be completed.
      if [ "$thread_check_status" -eq 0 ] && [ "$actual_unresolved_count" -eq 0 ]; then
        local companion_reviewed_head
        companion_reviewed_head="$(kv_value_default REVIEWED_HEAD "$script_output" "")"
        [ -n "$companion_reviewed_head" ] && print_kv REVIEWED_HEAD "$companion_reviewed_head"
      fi

      print_kv RESULT needs_fixes
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REASON unresolved_review_threads
      print_kv COMMENT_COUNT "$unresolved_count"
      print_kv BLOCKING_COUNT "$unresolved_count"
      print_kv SUGGESTION_COUNT 0
      return 1
      ;;
    3)
      print_kv RESULT escalate
      print_kv REASON codex-github-usage-limit
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 2
      ;;
    4)
      print_kv RESULT waiting_on_reviewer
      print_kv REASON "$(kv_value_default REASON "$script_output" codex-github-review-pending)"
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      print_kv PENDING_REVIEWER "$(kv_value_default PENDING_REVIEWER "$script_output" "$platform")"
      print_kv PENDING_REVIEW_HEAD_SHA "$(kv_value_default PENDING_REVIEW_HEAD_SHA "$script_output" "")"
      print_kv PENDING_REVIEW_TRIGGER_COMMENT_ID "$(kv_value_default PENDING_REVIEW_TRIGGER_COMMENT_ID "$script_output" "")"
      print_kv PENDING_REVIEW_TRIGGER_TIME "$(kv_value_default PENDING_REVIEW_TRIGGER_TIME "$script_output" "")"
      return 4
      ;;
    *)
      local codex_reason
      codex_reason="$(kv_value_default REASON "$script_output" timeout)"
      print_kv RESULT escalate
      print_kv REASON "$codex_reason"
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 2
      ;;
  esac
}

run_claude_code_action_review() {
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="claude-code-action"
  local bot_login="${CLAUDE_CODE_ACTION_BOT_LOGIN:-claude[bot]}"
  # GraphQL author.login returns the login WITHOUT the "[bot]" suffix that the
  # REST API uses. Strip it here so check_unresolved_threads comparisons work.
  local graphql_bot_login="${bot_login%\[bot\]}"
  local repo
  local reviewer_script
  local script_exit=0
  local thread_check_output=""
  local thread_check_status=0
  local unresolved_count=0

  require_gh
  cd_workflow_repo_root
  repo="$(repo_slug)"

  # Phase 1: Check for existing unresolved review threads from the Claude Code Action bot.
  # mode=provisional (#1508): see run_codex_github_review's phase 1 for rationale.
  set +e
  thread_check_output="$(check_unresolved_threads "$pr_number" "$repo" provisional "$graphql_bot_login")"
  thread_check_status=$?
  set -e
  if [ "$thread_check_status" -eq 0 ]; then
    unresolved_count="$thread_check_output"
  fi

  if [ "$unresolved_count" -gt 0 ]; then
    print_kv RESULT needs_fixes
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv REASON existing_findings
    print_kv COMMENT_COUNT "$unresolved_count"
    print_kv BLOCKING_COUNT "$unresolved_count"
    print_kv SUGGESTION_COUNT 0
    return 1
  fi

  # Phase 2: Dispatch the Claude Code Action workflow and wait for completion
  reviewer_script="$(workflow_repo_root)/scripts/development-workflow/claude-code-action-reviewer.sh"

  local owner repo_name
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

  # Keep polling interval bounded by the wait budget to avoid zero-poll attempts
  # when a caller provides poll_interval > max_wait.
  local effective_poll_interval
  effective_poll_interval="$poll_interval"
  if [ "$effective_poll_interval" -gt "$max_wait" ]; then
    effective_poll_interval="$max_wait"
  fi
  set +e
  "$reviewer_script" "$pr_number" "$owner" "$repo_name" \
    --bot-login "$bot_login" \
    --poll-interval "$effective_poll_interval" \
    --max-wait "$max_wait" >/dev/null 2>&1
  script_exit=$?
  set -e

  case "$script_exit" in
    0)
      print_kv RESULT clean
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 0
      ;;
    1)
      unresolved_count=0
      # mode=strict: this recount feeds the caller's needs_fixes/COMMENT_COUNT
      # reporting and must reflect true resolution state, not the provisional
      # reply relaxation used to decide whether to trigger the review above.
      set +e
      thread_check_output="$(check_unresolved_threads "$pr_number" "$repo" strict "$graphql_bot_login")"
      thread_check_status=$?
      set -e
      if [ "$thread_check_status" -eq 0 ]; then
        unresolved_count="$thread_check_output"
      fi
      [ "$unresolved_count" -eq 0 ] && unresolved_count=1

      print_kv RESULT needs_fixes
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REASON unresolved_review_threads
      print_kv COMMENT_COUNT "$unresolved_count"
      print_kv BLOCKING_COUNT "$unresolved_count"
      print_kv SUGGESTION_COUNT 0
      return 1
      ;;
    2)
      print_kv RESULT escalate
      print_kv REASON timeout
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      return 2
      ;;
    *)
      print_kv RESULT escalate
      print_kv REASON unavailable
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      return 2
      ;;
  esac
}

run_copilot_review() {
  # Requests GitHub Copilot as a reviewer via the GitHub Pulls API, polls the
  # pull-request reviews endpoint until Copilot posts its verdict, and maps the
  # review state to the standard exit-code contract:
  #   0 → RESULT=clean      (APPROVED or COMMENTED only)
  #   1 → RESULT=needs_fixes (CHANGES_REQUESTED)
  #   2 → RESULT=escalate   (timeout or Copilot feature unavailable)
  #
  # Env var override:
  #   COPILOT_BOT_LOGIN  — override the default bot login
  #                        (default: "copilot-pull-request-reviewer[bot]")
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="copilot"
  local bot_login="${COPILOT_BOT_LOGIN:-copilot-pull-request-reviewer[bot]}"
  local repo
  local elapsed=0
  local review_state=""
  local head_sha=""

  require_gh
  cd_workflow_repo_root
  repo="$(repo_slug)"

  local owner repo_name
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

  # Resolve head SHA before requesting review so the poll loop can filter
  # reviews to only those submitted against the current commit (#759).
  head_sha="$(gh pr view "$pr_number" --json headRefOid --jq '.headRefOid' 2>/dev/null || true)"
  if [ -z "$head_sha" ]; then
    # Cannot determine current commit — escalate rather than risk matching a
    # stale unscoped review from a previous cycle.
    print_kv RESULT escalate
    print_kv REASON head-sha-unavailable
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    return 2
  fi

  # Step 1: Request Copilot as a reviewer (idempotent — GitHub silently
  # deduplicates reviewer requests if Copilot is already requested).
  set +e
  gh api "repos/$owner/$repo_name/pulls/$pr_number/requested_reviewers" \
    --method POST \
    --field 'reviewers[]=copilot' > /dev/null 2>&1
  local request_exit=$?
  set -e

  if [ "$request_exit" -ne 0 ]; then
    # Request failed — Copilot feature likely not enabled on this repository.
    print_kv RESULT escalate
    print_kv REASON unavailable
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    return 2
  fi

  # Step 2: Poll the pull-request reviews endpoint until Copilot posts a review.
  local effective_poll_interval="$poll_interval"
  if [ "$effective_poll_interval" -gt "$max_wait" ]; then
    effective_poll_interval="$max_wait"
  fi
  [ "$effective_poll_interval" -le 0 ] && effective_poll_interval=1

  while [ "$elapsed" -lt "$max_wait" ]; do
    # Re-fetch the HEAD SHA on each iteration so that if a new commit is pushed
    # while Copilot's review is still in-flight, the filter matches the review
    # against the current commit rather than timing out on a stale SHA.
    set +e
    current_sha="$(gh pr view "$pr_number" --repo "$owner/$repo_name" --json headRefOid --jq '.headRefOid' 2>/dev/null)"
    _sha_rc=$?
    set -e
    if [ "$_sha_rc" -ne 0 ] || [ -z "$current_sha" ]; then
      echo "WARN: could not refresh HEAD SHA for PR $pr_number (exit $_sha_rc) — falling back to initial SHA $head_sha" >&2
      current_sha="$head_sha"
    fi
    unset _sha_rc
    set +e
    review_state="$(gh api --paginate "repos/$owner/$repo_name/pulls/$pr_number/reviews" 2>/dev/null \
      | jq -rs --arg login "$bot_login" --arg sha "$current_sha" \
        '[ .[] | .[] | select(.user.login == $login and .commit_id == $sha) ] | last | .state // empty')"
    set -e

    case "$review_state" in
      APPROVED)
        print_kv RESULT clean
      [ -n "${current_sha:-${head_sha:-}}" ] && print_kv REVIEWED_HEAD "${current_sha:-$head_sha}"
        print_kv PLATFORM "$platform"
        print_kv PR_NUMBER "$pr_number"
        print_kv BRANCH "$branch_name"
        print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
        print_kv COMMENT_COUNT 0
        print_kv BLOCKING_COUNT 0
        print_kv SUGGESTION_COUNT 0
        return 0
        ;;
      CHANGES_REQUESTED)
        # Fetch the actual review-comment count so COMMENT_COUNT/BLOCKING_COUNT
        # reflect how many inline findings Copilot posted, not just "at least 1".
        local _copilot_review_id _copilot_comment_count
        _copilot_review_id=""
        _copilot_comment_count=0
        set +e
        _copilot_review_id="$(gh api --paginate \
          "repos/$owner/$repo_name/pulls/$pr_number/reviews" 2>/dev/null \
          | jq -rs --arg login "$bot_login" --arg sha "$current_sha" \
            '[ .[] | .[] | select(.user.login == $login and .commit_id == $sha) ] | last | .id // empty')"
        if [ -n "$_copilot_review_id" ]; then
          local _cnt
          _cnt="$(gh api --paginate \
            "repos/$owner/$repo_name/pulls/$pr_number/reviews/$_copilot_review_id/comments" \
            2>/dev/null | jq -rs '[ .[] | .[] ] | length' 2>/dev/null)"
          [ -n "$_cnt" ] && [ "$_cnt" -gt 0 ] && _copilot_comment_count="$_cnt"
        fi
        set -e
        # Copilot may place findings in the review body rather than as inline
        # comments. Ensure BLOCKING_COUNT >= 1 so callers always see at least
        # one blocking finding when the verdict is CHANGES_REQUESTED.
        [ "$_copilot_comment_count" -eq 0 ] && _copilot_comment_count=1
        print_kv RESULT needs_fixes
      [ -n "${current_sha:-${head_sha:-}}" ] && print_kv REVIEWED_HEAD "${current_sha:-$head_sha}"
        print_kv PLATFORM "$platform"
        print_kv PR_NUMBER "$pr_number"
        print_kv BRANCH "$branch_name"
        print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
        print_kv REASON changes_requested
        print_kv COMMENT_COUNT "$_copilot_comment_count"
        print_kv BLOCKING_COUNT "$_copilot_comment_count"
        print_kv SUGGESTION_COUNT 0
        return 1
        ;;
      COMMENTED)
        # Non-blocking comment only — treat as clean.
        print_kv RESULT clean
      [ -n "${current_sha:-${head_sha:-}}" ] && print_kv REVIEWED_HEAD "${current_sha:-$head_sha}"
        print_kv PLATFORM "$platform"
        print_kv PR_NUMBER "$pr_number"
        print_kv BRANCH "$branch_name"
        print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
        print_kv COMMENT_COUNT 1
        print_kv BLOCKING_COUNT 0
        print_kv SUGGESTION_COUNT 1
        return 0
        ;;
      "")
        # review_state is empty — gh api or jq failed under set +e.
        # Log a warning so the failure is visible; continue polling rather
        # than escalating on a single transient error.
        echo "WARN: review state API call returned empty for PR $pr_number SHA $current_sha — retrying in ${effective_poll_interval}s" >&2
        ;;
    esac

    _interruptible_sleep "$effective_poll_interval"
    elapsed=$(( elapsed + effective_poll_interval ))
  done

  # Timeout — no review posted within max_wait.
  print_kv RESULT escalate
  print_kv REASON timeout
  print_kv PLATFORM "$platform"
  print_kv PR_NUMBER "$pr_number"
  print_kv BRANCH "$branch_name"
  print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
  return 2
}

bugbot_return_disabled() {
  local pr_number="$1"
  local branch_name="$2"

  echo "INFO: Bugbot is disabled for this repository. Enable Bugbot for this repository in the Cursor dashboard, then rerun the reviewer loop." >&2
  print_kv RESULT escalate
  print_kv REASON bugbot-disabled
  print_kv PLATFORM bugbot
  print_kv PR_NUMBER "$pr_number"
  print_kv BRANCH "$branch_name"
  print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
  print_kv COMMENT_COUNT 0
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT 0
  return 2
}

bugbot_return_usage_limit() {
  local pr_number="$1"
  local branch_name="$2"

  echo "INFO: Bugbot could not run because the Cursor usage or spend limit was reached. Raise the limit or wait for quota reset, then rerun the reviewer loop." >&2
  print_kv RESULT escalate
  print_kv REASON bugbot-usage-limit
  print_kv PLATFORM bugbot
  print_kv PR_NUMBER "$pr_number"
  print_kv BRANCH "$branch_name"
  print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
  print_kv COMMENT_COUNT 0
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT 0
  return 2
}

bugbot_return_explicit_skip() {
  if [ "$#" -ne 2 ]; then
    echo "ERROR: bugbot_return_explicit_skip requires exactly 2 arguments." >&2
    return 1
  fi

  local pr_number="$1"
  local branch_name="$2"

  echo "WARN: Bugbot explicitly skipped this PR. Treating the skip as a non-blocking warning; no Bugbot review findings were produced." >&2
  print_kv RESULT skipped
  print_kv REASON explicit-skip
  print_kv PLATFORM bugbot
  print_kv PR_NUMBER "$pr_number"
  print_kv BRANCH "$branch_name"
  print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
  print_kv COMMENT_COUNT 1
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT 1
  return 0
}

bugbot_since_iso_for_sha() {
  local repo="$1"
  local head_sha="$2"
  local since_iso
  local _bb_now_iso

  if ! since_iso="$(gh api "repos/$repo/commits/$head_sha" --jq '.commit.committer.date // empty' 2>/dev/null)"; then
    return 1
  fi
  if [ -z "$since_iso" ]; then
    return 1
  fi
  _bb_now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  if [ "$since_iso" \> "$_bb_now_iso" ]; then
    return 1
  fi
  printf '%s\n' "$since_iso"
}

bugbot_check_disabled_issue_comments() {
  local repo="$1"
  local pr_number="$2"
  local bot_login="$3"
  local since_iso="$4"

  set +e
  local output
  output="$(
    gh api "repos/$repo/issues/$pr_number/comments" --paginate 2>/dev/null \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
          .[]
          | select(
              (.user.login == $bot or .user.login == ($bot + "[bot]")) and
              .created_at > $since
            )
          | .body // ""
        ' 2>/dev/null
  )"
  local _comments_rc=$?
  set -e
  if [ "$_comments_rc" -ne 0 ]; then
    return 1
  fi
  printf '%s\n' "$output"
  return 0
}

# Returns:
#   0 when no unavailable/skip comment applies
#   2 when an escalation or disabled/usage-limit outcome was emitted
#   BUGBOT_HANDLED_SKIP_RC when an explicit successful skip outcome was emitted
bugbot_escalate_for_unavailable_issue_comments() {
  local repo="$1"
  local pr_number="$2"
  local branch_name="$3"
  local bot_login="$4"
  local since_iso="$5"
  local context="$6"
  local allow_usage_limit="${7:-1}"
  local body
  local unavailable_bodies
  local _comments_rc=0

  set +e
  unavailable_bodies="$(bugbot_check_disabled_issue_comments "$repo" "$pr_number" "$bot_login" "$since_iso")"
  _comments_rc=$?
  set -e
  if [ "$_comments_rc" -ne 0 ]; then
    echo "WARN: run_bugbot_review: ${context} issue-comment fetch failed for PR #$pr_number" >&2
    print_kv RESULT escalate
    print_kv REASON fetch-failed
    print_kv PLATFORM bugbot
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT 0
    print_kv BLOCKING_COUNT 0
    print_kv SUGGESTION_COUNT 0
    return 2
  fi

  while IFS= read -r body; do
    [ -z "$body" ] && continue
    if is_bugbot_disabled_message "$body"; then
      bugbot_return_disabled "$pr_number" "$branch_name"
      return 2
    fi
    if [ "$allow_usage_limit" -eq 1 ] && is_bugbot_usage_limit_message "$body"; then
      bugbot_return_usage_limit "$pr_number" "$branch_name"
      return 2
    fi
    if is_bugbot_explicit_skip_message "$body"; then
      bugbot_return_explicit_skip "$pr_number" "$branch_name"
      return "$BUGBOT_HANDLED_SKIP_RC"
    fi
  done <<< "$unavailable_bodies"

  return 0
}

bugbot_cursor_check_run_count() {
  local repo="$1"
  local head_sha="$2"
  local check_name="$3"
  local count

  set +e
  count="$(
    gh api "repos/$repo/commits/$head_sha/check-runs" --paginate 2>/dev/null \
      | jq -se --arg name "$check_name" '
          [ .[].check_runs[]
            | select(
                ((.app.slug // "") | test("cursor"; "i")) or
                (.name == $name)
              )
          ] | length
        ' 2>/dev/null
  )"
  set -e
  if [ -z "${count:-}" ]; then
    return 1
  fi
  printf '%s\n' "$count"
  return 0
}

# Returns: 0 when disabled issue comments should be evaluated for this head,
# 1 when a completed successful Cursor check run makes them stale,
# 2 when the check-run lookup could not be fetched.
bugbot_disabled_preflight_applies_for_head() {
  local repo="$1"
  local head_sha="$2"
  local check_name="$3"
  local fetch_output=""
  local status=""
  local conclusion=""
  local _fetch_rc=0

  set +e
  fetch_output="$(
    gh api "repos/$repo/commits/$head_sha/check-runs" --paginate 2>/dev/null \
      | jq -se -r --arg name "$check_name" '
          [ .[].check_runs[]
            | select(
                ((.app.slug // "") | test("cursor"; "i")) or
                (.name == $name)
              )
          ]
          | sort_by(.started_at) | last
          | ((.status // "") + " " + (.conclusion // ""))
        ' 2>/dev/null
  )"
  _fetch_rc=$?
  set -e
  if [ "$_fetch_rc" -ne 0 ]; then
    return 2
  fi
  if [ -z "$fetch_output" ]; then
    return 0
  fi
  read -r status conclusion <<< "$fetch_output"
  status="${status:-}"
  conclusion="${conclusion:-}"
  if [ "$status" = "completed" ] && [ "$conclusion" = "success" ]; then
    return 1
  fi
  return 0
}

bugbot_escalate_if_disabled_without_check_run() {
  local repo="$1"
  local pr_number="$2"
  local branch_name="$3"
  local bot_login="$4"
  local since_iso="$5"
  local head_sha="$6"
  local check_name="$7"
  local _preflight_rc=0

  set +e
  bugbot_disabled_preflight_applies_for_head "$repo" "$head_sha" "$check_name"
  _preflight_rc=$?
  set -e
  if [ "$_preflight_rc" -eq 2 ]; then
    echo "WARN: run_bugbot_review: check-run count fetch failed during disabled preflight for PR #$pr_number" >&2
    print_kv RESULT escalate
    print_kv REASON fetch-failed
    print_kv PLATFORM bugbot
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT 0
    print_kv BLOCKING_COUNT 0
    print_kv SUGGESTION_COUNT 0
    return 2
  fi
  if [ "$_preflight_rc" -eq 1 ]; then
    return 0
  fi

  set +e
  bugbot_escalate_for_unavailable_issue_comments \
    "$repo" "$pr_number" "$branch_name" "$bot_login" "$since_iso" "disabled-preflight" 0
  local _unavailable_comments_rc=$?
  set -e
  if [ "$_unavailable_comments_rc" -eq 2 ]; then
    return 2
  fi
  if [ "$_unavailable_comments_rc" -eq "$BUGBOT_HANDLED_SKIP_RC" ]; then
    return "$BUGBOT_HANDLED_SKIP_RC"
  fi

  return 0
}

run_bugbot_review() {
  # Triggers Cursor Bugbot for the given PR, polls the "Cursor Bugbot" check run
  # on the PR head SHA until the run completes or the budget is exhausted, then
  # classifies the conclusion and summarises any blocking cursor[bot] findings.
  #
  # Exit code mapping:
  #   0 → RESULT=clean      (conclusion=success with no blocking comments, or
  #                           neutral/cancelled/skipped informational)
  #   1 → RESULT=needs_fixes (conclusion=failure/action_required, or existing
  #                           blocking cursor[bot] findings on current head)
  #   2 → RESULT=escalate   (timeout, unavailable, or head-sha-unavailable)
  #
  # Env var overrides:
  #   BUGBOT_BOT_LOGIN        — override bot login (default: "cursor[bot]")
  #   BUGBOT_CHECK_NAME       — override check-run name (default: "Cursor Bugbot")
  #   BUGBOT_TRIGGER_COMMENT  — override trigger comment (default: "bugbot run")
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="bugbot"
  local bot_login="${BUGBOT_BOT_LOGIN:-cursor[bot]}"
  local check_name="${BUGBOT_CHECK_NAME:-Cursor Bugbot}"
  local trigger_comment="${BUGBOT_TRIGGER_COMMENT:-bugbot run}"
  local repo
  local owner repo_name
  local head_sha=""
  local since_iso=""
  local existing_comments=""
  local existing_reviews=""
  local existing_blocking_file=""
  local existing_blocking_count=0
  local existing_suggestion_count=0
  local comment_json=""
  local review_json=""
  local body=""
  local blocking_lines_file=""
  local elapsed=0
  local conclusion=""
  local status_val=""
  local blocking_count=0
  local suggestion_count=0
  local comment_count=0
  local index=1
  local blocking_json=""
  local check_appeared=0

  trap 'rm -f "${existing_blocking_file:-}" "${blocking_lines_file:-}"' RETURN

  require_gh
  cd_workflow_repo_root
  repo="$(repo_slug)"
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

  # Resolve head SHA. A missing SHA means we cannot scope findings to the
  # current commit — escalate rather than risk matching stale results.
  set +e
  head_sha="$(gh api "repos/$repo/pulls/$pr_number" --jq '.head.sha' 2>/dev/null)"
  set -e
  if [ -z "$head_sha" ]; then
    print_kv RESULT escalate
    print_kv REASON head-sha-unavailable
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT 0
    print_kv BLOCKING_COUNT 0
    print_kv SUGGESTION_COUNT 0
    return 2
  fi

  # Resolve the commit timestamp to scope findings to this HEAD.
  if ! since_iso="$(bugbot_since_iso_for_sha "$repo" "$head_sha")"; then
    echo "WARN: run_bugbot_review: could not resolve commit timestamp for PR #$pr_number (SHA=$head_sha) — returning unavailable" >&2
    print_kv RESULT escalate
    print_kv REASON fetch-failed
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT 0
    print_kv BLOCKING_COUNT 0
    print_kv SUGGESTION_COUNT 0
    return 2
  fi

  # --- Phase 1: Check for existing blocking cursor[bot] findings on current HEAD ---
  # If blocking findings already exist (e.g. from a previous trigger in the same
  # review cycle) return needs_fixes immediately without re-triggering.
  set +e
  local _existing_comments_rc=0
  local _existing_reviews_rc=0
  existing_comments="$(
    gh api "repos/$repo/pulls/$pr_number/comments" --paginate 2>/dev/null \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" --arg sha "$head_sha" '
          .[]
          | select((.user.login == $bot or .user.login == ($bot + "[bot]")) and .created_at > $since and .commit_id == $sha and .in_reply_to_id == null)
          | { path, line: (.line // .original_line // 0), body: (.body // ""), commit_id: (.commit_id // "") }
          | @json
        ' 2>/dev/null
  )"
  _existing_comments_rc=$?
  existing_reviews="$(
    gh api "repos/$repo/pulls/$pr_number/reviews" --paginate 2>/dev/null \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" --arg sha "$head_sha" '
          .[]
          | select(
              (.user.login == $bot or .user.login == ($bot + "[bot]")) and
              .submitted_at > $since and
              .commit_id == $sha and
              (
                .state == "CHANGES_REQUESTED" or
                .state == "COMMENTED"
              )
            )
          | { path: "", line: 0, body: (.body // "review without body"), state: .state, commit_id: (.commit_id // .commitId // "") }
          | @json
        ' 2>/dev/null
  )"
  _existing_reviews_rc=$?
  set -e
  if [ "$_existing_comments_rc" -ne 0 ] || [ "$_existing_reviews_rc" -ne 0 ]; then
    echo "WARN: run_bugbot_review: existing finding fetch/parse failed for PR #$pr_number — returning unavailable" >&2
    print_kv RESULT escalate
    print_kv REASON fetch-failed
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT 0
    print_kv BLOCKING_COUNT 0
    print_kv SUGGESTION_COUNT 0
    return 2
  fi

  existing_blocking_file="$(mktemp)"
  local existing_explicit_skip_seen=0

  while IFS= read -r comment_json; do
    [ -z "${comment_json:-}" ] && continue
    body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    if is_bugbot_disabled_message "$body"; then
      set +e
      bugbot_disabled_preflight_applies_for_head "$repo" "$head_sha" "$check_name"
      local _bb_disabled_rc=$?
      set -e
      if [ "$_bb_disabled_rc" -eq 2 ]; then
        rm -f "$existing_blocking_file"
        echo "WARN: run_bugbot_review: check-run count fetch failed during disabled preflight for PR #$pr_number" >&2
        print_kv RESULT escalate
        print_kv REASON fetch-failed
        print_kv PLATFORM "$platform"
        print_kv PR_NUMBER "$pr_number"
        print_kv BRANCH "$branch_name"
        print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
        print_kv COMMENT_COUNT 0
        print_kv BLOCKING_COUNT 0
        print_kv SUGGESTION_COUNT 0
        return 2
      fi
      if [ "$_bb_disabled_rc" -eq 0 ]; then
        rm -f "$existing_blocking_file"
        bugbot_return_disabled "$pr_number" "$branch_name"
        return 2
      fi
      existing_suggestion_count=$((existing_suggestion_count + 1))
      continue
    fi
    if is_bugbot_explicit_skip_message "$body"; then
      existing_explicit_skip_seen=1
      existing_suggestion_count=$((existing_suggestion_count + 1))
      continue
    fi
    # Bugbot informational notes are counted as suggestions, not blockers (AC-4).
    if is_soft_suggestion "$body" || is_bugbot_clean_review "$body"; then
      existing_suggestion_count=$((existing_suggestion_count + 1))
      continue
    fi
    existing_blocking_count=$((existing_blocking_count + 1))
    printf '%s\n' "$comment_json" >> "$existing_blocking_file"
  done <<< "$existing_comments"

  while IFS= read -r review_json; do
    [ -z "${review_json:-}" ] && continue
    body="$(printf '%s\n' "$review_json" | jq -r '.body')"
    _rv_state="$(printf '%s\n' "$review_json" | jq -r '.state // ""')"
    if [ "$_rv_state" = "CHANGES_REQUESTED" ]; then
      existing_blocking_count=$((existing_blocking_count + 1))
      printf '%s\n' "$review_json" >> "$existing_blocking_file"
      continue
    fi
    [ -z "$body" ] && continue
    if is_bugbot_disabled_message "$body"; then
      set +e
      bugbot_disabled_preflight_applies_for_head "$repo" "$head_sha" "$check_name"
      local _bb_disabled_review_rc=$?
      set -e
      if [ "$_bb_disabled_review_rc" -eq 2 ]; then
        rm -f "$existing_blocking_file"
        echo "WARN: run_bugbot_review: check-run count fetch failed during disabled preflight for PR #$pr_number" >&2
        print_kv RESULT escalate
        print_kv REASON fetch-failed
        print_kv PLATFORM "$platform"
        print_kv PR_NUMBER "$pr_number"
        print_kv BRANCH "$branch_name"
        print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
        print_kv COMMENT_COUNT 0
        print_kv BLOCKING_COUNT 0
        print_kv SUGGESTION_COUNT 0
        return 2
      fi
      if [ "$_bb_disabled_review_rc" -eq 0 ]; then
        rm -f "$existing_blocking_file"
        bugbot_return_disabled "$pr_number" "$branch_name"
        return 2
      fi
      existing_suggestion_count=$((existing_suggestion_count + 1))
      continue
    fi
    if is_bugbot_explicit_skip_message "$body"; then
      existing_explicit_skip_seen=1
      existing_suggestion_count=$((existing_suggestion_count + 1))
      continue
    fi
    if is_soft_suggestion "$body" || is_bugbot_clean_review "$body"; then
      existing_suggestion_count=$((existing_suggestion_count + 1))
      continue
    fi
    existing_blocking_count=$((existing_blocking_count + 1))
    printf '%s\n' "$review_json" >> "$existing_blocking_file"
  done <<< "$existing_reviews"

  if [ "$existing_explicit_skip_seen" -eq 1 ] && [ "$existing_blocking_count" -eq 0 ]; then
    rm -f "$existing_blocking_file"
    bugbot_return_explicit_skip "$pr_number" "$branch_name"
    return 0
  fi

  if [ "$existing_blocking_count" -gt 0 ]; then
    print_kv RESULT needs_fixes
      [ -n "${_current_sha:-${head_sha:-}}" ] && print_kv REVIEWED_HEAD "${_current_sha:-$head_sha}"
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv REASON existing_findings
    print_kv COMMENT_COUNT "$((existing_blocking_count + existing_suggestion_count))"
    print_kv BLOCKING_COUNT "$existing_blocking_count"
    print_kv SUGGESTION_COUNT "$existing_suggestion_count"
    while IFS= read -r blocking_json; do
      [ -z "${blocking_json:-}" ] && continue
      print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
      print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
      print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
      index=$((index + 1))
    done < "$existing_blocking_file"
    rm -f "$existing_blocking_file"
    return 1
  fi

  rm -f "$existing_blocking_file"

  # --- Phase 2: Trigger — post trigger comment when no in-progress/recent run ---
  # Check for a queued/in-progress/recently-completed Cursor Bugbot check run on
  # the current head. If none exists, post the trigger comment (idempotent).
  set +e
  local _bb_run_count
  local _bb_run_count_rc=0
  _bb_run_count="$(
    gh api "repos/$repo/commits/$head_sha/check-runs" --paginate 2>/dev/null \
      | jq -se --arg name "$check_name" '
          [ .[].check_runs[]
            | select(
                ((.app.slug // "") | test("cursor"; "i")) or
                (.name == $name)
              )
          ] | length
        ' 2>/dev/null
  )"
  _bb_run_count_rc=$?
  set -e
  if [ "$_bb_run_count_rc" -ne 0 ] || [ -z "$_bb_run_count" ]; then
    echo "WARN: run_bugbot_review: check-run fetch/parse failed for PR #$pr_number (SHA=$head_sha) — returning unavailable" >&2
    print_kv RESULT escalate
    print_kv REASON fetch-failed
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT 0
    print_kv BLOCKING_COUNT 0
    print_kv SUGGESTION_COUNT 0
    return 2
  fi
  _bb_run_count="${_bb_run_count:-0}"

  if [ "$_bb_run_count" -eq 0 ]; then
    set +e
    bugbot_escalate_if_disabled_without_check_run \
      "$repo" "$pr_number" "$branch_name" "$bot_login" "$since_iso" "$head_sha" "$check_name"
    local _bb_disabled_rc=$?
    set -e
    if [ "$_bb_disabled_rc" -eq 2 ]; then
      return 2
    fi
    if [ "$_bb_disabled_rc" -eq "$BUGBOT_HANDLED_SKIP_RC" ]; then
      return 0
    fi
    # No Cursor Bugbot check run for this head — post the trigger comment.
    set +e
    gh api "repos/$repo/issues/$pr_number/comments" --method POST \
      --raw-field body="$trigger_comment" > /dev/null 2>&1
    local _bb_trigger_rc=$?
    set -e
    if [ "$_bb_trigger_rc" -ne 0 ]; then
      echo "WARN: run_bugbot_review: trigger comment post failed for PR #$pr_number" >&2
      print_kv RESULT escalate
      print_kv REASON trigger-failed
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 2
    fi
  fi

  # --- Phase 3: Poll the "Cursor Bugbot" check run on the current head SHA ---
  while [ "$elapsed" -lt "$max_wait" ]; do
    # Re-resolve head SHA each iteration so a mid-review push retargets the filter.
    set +e
    local _current_sha
    _current_sha="$(gh pr view "$pr_number" --repo "$owner/$repo_name" --json headRefOid --jq '.headRefOid' 2>/dev/null)"
    local _sha_rc=$?
    set -e
    if [ "$_sha_rc" -ne 0 ] || [ -z "$_current_sha" ]; then
      echo "WARN: run_bugbot_review: could not refresh HEAD SHA for PR $pr_number — falling back to $head_sha" >&2
      _current_sha="$head_sha"
    fi
    unset _sha_rc
    local _current_since_iso
    if ! _current_since_iso="$(bugbot_since_iso_for_sha "$repo" "$_current_sha")"; then
      echo "WARN: run_bugbot_review: could not resolve commit timestamp for PR #$pr_number (SHA=$_current_sha) — returning unavailable" >&2
      print_kv RESULT escalate
      print_kv REASON fetch-failed
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 2
    fi

    set +e
    local _fetch_rc=0
    local _fetch_output
    _fetch_output="$(
      gh api "repos/$repo/commits/$_current_sha/check-runs" --paginate 2>/dev/null \
        | jq -se -r --arg name "$check_name" '
            [ .[].check_runs[]
              | select(
                  ((.app.slug // "") | test("cursor"; "i")) or
                  (.name == $name)
                )
            ]
            | sort_by(.started_at) | last
            | ((.status // "") + " " + (.conclusion // "") + " " + (.started_at // ""))
          ' 2>/dev/null
    )"
    _fetch_rc=$?
    set -e
    if [ "$_fetch_rc" -ne 0 ] || [ -z "$_fetch_output" ]; then
      echo "WARN: run_bugbot_review: check-run fetch/parse failed for PR #$pr_number (SHA=$_current_sha) — returning unavailable" >&2
      print_kv RESULT escalate
      print_kv REASON fetch-failed
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 2
    fi
    local check_started_at=""
    read -r status_val conclusion check_started_at <<< "$_fetch_output"
    status_val="${status_val:-}"
    conclusion="${conclusion:-}"
    check_started_at="${check_started_at:-}"

    if [ "$status_val" != "completed" ]; then
      set +e
      bugbot_escalate_if_disabled_without_check_run \
        "$repo" "$pr_number" "$branch_name" "$bot_login" "$_current_since_iso" "$_current_sha" "$check_name"
      local _bb_disabled_poll_rc=$?
      set -e
      if [ "$_bb_disabled_poll_rc" -eq 2 ]; then
        return 2
      fi
      if [ "$_bb_disabled_poll_rc" -eq "$BUGBOT_HANDLED_SKIP_RC" ]; then
        return 0
      fi
    fi

    if [ "$status_val" = "completed" ]; then
      check_appeared=1
      case "$conclusion" in
        success)
          # No blocking findings per the check run. Read cursor[bot] inline
          # comments to confirm and collect any suggestions.
          blocking_lines_file="$(mktemp)"
          local clean_explicit_skip_seen=0
          set +e
	          local _clean_comments
	          local _clean_comments_rc=0
	          _clean_comments="$(
	            gh api "repos/$repo/pulls/$pr_number/comments" --paginate 2>/dev/null \
	              | jq -r --arg bot "$bot_login" --arg since "$_current_since_iso" --arg sha "$_current_sha" '
	                  .[]
	                  | select((.user.login == $bot or .user.login == ($bot + "[bot]")) and .created_at > $since and .commit_id == $sha and .in_reply_to_id == null)
	                  | { path, line: (.line // .original_line // 0), body: (.body // ""), commit_id: (.commit_id // "") }
                  | @json
                ' 2>/dev/null
          )"
          _clean_comments_rc=$?
          set -e
          if [ "$_clean_comments_rc" -ne 0 ]; then
            echo "WARN: run_bugbot_review: success-path comment fetch/parse failed for PR #$pr_number — returning unavailable" >&2
            print_kv RESULT escalate
            print_kv REASON fetch-failed
            print_kv PLATFORM "$platform"
            print_kv PR_NUMBER "$pr_number"
            print_kv BRANCH "$branch_name"
            print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
            print_kv COMMENT_COUNT 0
            print_kv BLOCKING_COUNT 0
            print_kv SUGGESTION_COUNT 0
            rm -f "$blocking_lines_file"
            return 2
          fi
          while IFS= read -r comment_json; do
            [ -z "${comment_json:-}" ] && continue
            body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
            [ -z "$body" ] && continue
            comment_count=$((comment_count + 1))
            if is_soft_suggestion "$body" || is_bugbot_clean_review "$body"; then
              suggestion_count=$((suggestion_count + 1))
            elif is_bugbot_explicit_skip_message "$body"; then
              clean_explicit_skip_seen=1
              suggestion_count=$((suggestion_count + 1))
            else
              blocking_count=$((blocking_count + 1))
              printf '%s\n' "$comment_json" >> "$blocking_lines_file"
            fi
          done <<< "${_clean_comments:-}"

          if [ "$blocking_count" -gt 0 ]; then
            # Check run said success but cursor[bot] posted blocking comments.
            print_kv RESULT needs_fixes
      [ -n "${_current_sha:-${head_sha:-}}" ] && print_kv REVIEWED_HEAD "${_current_sha:-$head_sha}"
            print_kv PLATFORM "$platform"
            print_kv PR_NUMBER "$pr_number"
            print_kv BRANCH "$branch_name"
            print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
            print_kv REASON blocking_comments
            print_kv COMMENT_COUNT "$comment_count"
            print_kv BLOCKING_COUNT "$blocking_count"
            print_kv SUGGESTION_COUNT "$suggestion_count"
            while IFS= read -r blocking_json; do
              [ -z "${blocking_json:-}" ] && continue
              print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
              print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
              print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
              index=$((index + 1))
            done < "$blocking_lines_file"
            rm -f "$blocking_lines_file"
            return 1
          fi

          if [ "$clean_explicit_skip_seen" -eq 1 ] && [ "$blocking_count" -eq 0 ]; then
            rm -f "$blocking_lines_file"
            bugbot_return_explicit_skip "$pr_number" "$branch_name"
            return 0
          fi

          rm -f "$blocking_lines_file"
          print_kv RESULT clean
      [ -n "${_current_sha:-${head_sha:-}}" ] && print_kv REVIEWED_HEAD "${_current_sha:-$head_sha}"
          print_kv PLATFORM "$platform"
          print_kv PR_NUMBER "$pr_number"
          print_kv BRANCH "$branch_name"
          print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
          print_kv COMMENT_COUNT "$comment_count"
          print_kv BLOCKING_COUNT 0
          print_kv SUGGESTION_COUNT "$suggestion_count"
          return 0
          ;;

        failure|action_required)
          # Blocking findings. Read cursor[bot] reviews/comments for the summary.
          blocking_lines_file="$(mktemp)"
          local blocking_explicit_skip_seen=0
          set +e
	          local _blocking_comments _blocking_reviews
	          local _blocking_comments_rc=0
	          local _blocking_reviews_rc=0
	          _blocking_comments="$(
	            gh api "repos/$repo/pulls/$pr_number/comments" --paginate 2>/dev/null \
	              | jq -r --arg bot "$bot_login" --arg since "$_current_since_iso" --arg sha "$_current_sha" '
	                  .[]
	                  | select((.user.login == $bot or .user.login == ($bot + "[bot]")) and .created_at > $since and .commit_id == $sha and .in_reply_to_id == null)
	                  | { path, line: (.line // .original_line // 0), body: (.body // ""), commit_id: (.commit_id // "") }
                  | @json
                ' 2>/dev/null
          )"
	          _blocking_comments_rc=$?
	          _blocking_reviews="$(
	            gh api "repos/$repo/pulls/$pr_number/reviews" --paginate 2>/dev/null \
	              | jq -r --arg bot "$bot_login" --arg since "$_current_since_iso" --arg sha "$_current_sha" '
	                  .[]
	                  | select(
	                      (.user.login == $bot or .user.login == ($bot + "[bot]")) and
	                      .submitted_at > $since and
	                      .commit_id == $sha and
	                      (
                        .state == "CHANGES_REQUESTED" or
                        .state == "COMMENTED"
                      )
                    )
                  | { path: "", line: 0, body: (.body // "review without body"), state: .state, commit_id: (.commit_id // .commitId // "") }
                  | @json
                ' 2>/dev/null
          )"
          _blocking_reviews_rc=$?
          set -e
          if [ "$_blocking_comments_rc" -ne 0 ] || [ "$_blocking_reviews_rc" -ne 0 ]; then
            echo "WARN: run_bugbot_review: blocking finding fetch/parse failed for PR #$pr_number — returning unavailable" >&2
            print_kv RESULT escalate
            print_kv REASON fetch-failed
            print_kv PLATFORM "$platform"
            print_kv PR_NUMBER "$pr_number"
            print_kv BRANCH "$branch_name"
            print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
            print_kv COMMENT_COUNT 0
            print_kv BLOCKING_COUNT 0
            print_kv SUGGESTION_COUNT 0
            rm -f "$blocking_lines_file"
            return 2
          fi

          local inline_count=0
          while IFS= read -r comment_json; do
            [ -z "${comment_json:-}" ] && continue
            body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
            [ -z "$body" ] && continue
            comment_count=$((comment_count + 1))
            if is_soft_suggestion "$body" || is_bugbot_clean_review "$body"; then
              suggestion_count=$((suggestion_count + 1))
            elif is_bugbot_explicit_skip_message "$body"; then
              blocking_explicit_skip_seen=1
              suggestion_count=$((suggestion_count + 1))
            else
              blocking_count=$((blocking_count + 1))
              inline_count=$((inline_count + 1))
              printf '%s\n' "$comment_json" >> "$blocking_lines_file"
            fi
          done <<< "${_blocking_comments:-}"

          while IFS= read -r review_json; do
            [ -z "${review_json:-}" ] && continue
            body="$(printf '%s\n' "$review_json" | jq -r '.body')"
            local _rv_state
            _rv_state="$(printf '%s\n' "$review_json" | jq -r '.state // ""')"
            if [ "$_rv_state" = "CHANGES_REQUESTED" ]; then
              : # requested changes are always blocking regardless of body text
            elif [ -z "$body" ]; then
              continue
            elif is_soft_suggestion "$body" || is_bugbot_clean_review "$body"; then
              suggestion_count=$((suggestion_count + 1))
              comment_count=$((comment_count + 1))
              continue
            elif is_bugbot_explicit_skip_message "$body"; then
              blocking_explicit_skip_seen=1
              suggestion_count=$((suggestion_count + 1))
              comment_count=$((comment_count + 1))
              continue
            fi
            # For COMMENTED reviews, treat as blocking when there are inline
            # blocking comments (umbrella review) or when the body carries
            # Bugbot finding markers (BUGBOT_REVIEW / BUGBOT_BUG_ID / LOCATIONS).
            if [ "$_rv_state" = "COMMENTED" ]; then
              if [ "$inline_count" -gt 0 ]; then
                : # umbrella COMMENTED for inline findings — blocking
              elif printf '%s\n' "$body" | grep -q "BUGBOT_REVIEW\|BUGBOT_BUG_ID\|LOCATIONS"; then
                : # body carries Bugbot finding markers — blocking
              else
                suggestion_count=$((suggestion_count + 1))
                comment_count=$((comment_count + 1))
                continue
              fi
            fi
            comment_count=$((comment_count + 1))
            blocking_count=$((blocking_count + 1))
            printf '%s\n' "$review_json" >> "$blocking_lines_file"
          done <<< "${_blocking_reviews:-}"

          if [ "$blocking_explicit_skip_seen" -eq 1 ] && [ "$blocking_count" -eq 0 ]; then
            rm -f "$blocking_lines_file"
            bugbot_return_explicit_skip "$pr_number" "$branch_name"
            return 0
          fi

          # Ensure BLOCKING_COUNT >= 1 when the check run verdict is blocking,
          # even when cursor[bot] embeds all findings in the review body.
          if [ "$blocking_count" -eq 0 ]; then
            blocking_count=1
            comment_count=$((comment_count + 1))
          fi

          print_kv RESULT needs_fixes
      [ -n "${_current_sha:-${head_sha:-}}" ] && print_kv REVIEWED_HEAD "${_current_sha:-$head_sha}"
          print_kv PLATFORM "$platform"
          print_kv PR_NUMBER "$pr_number"
          print_kv BRANCH "$branch_name"
          print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
          print_kv REASON blocking_findings
          print_kv COMMENT_COUNT "$comment_count"
          print_kv BLOCKING_COUNT "$blocking_count"
          print_kv SUGGESTION_COUNT "$suggestion_count"
          while IFS= read -r blocking_json; do
            [ -z "${blocking_json:-}" ] && continue
            print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
            print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
            print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
            index=$((index + 1))
          done < "$blocking_lines_file"
          rm -f "$blocking_lines_file"
          return 1
          ;;

        neutral|cancelled|skipped)
          # A neutral check is clean only when Cursor did not also post an
          # unavailable/quota issue comment for this head.
          local _unavailable_since_iso="$_current_since_iso"
          if [ -n "$check_started_at" ] && [ "$check_started_at" \> "$_unavailable_since_iso" ]; then
            _unavailable_since_iso="$check_started_at"
          fi
          set +e
          bugbot_escalate_for_unavailable_issue_comments \
            "$repo" "$pr_number" "$branch_name" "$bot_login" "$_unavailable_since_iso" "neutral-conclusion" 1
          local _bb_neutral_unavailable_rc=$?
          set -e
          if [ "$_bb_neutral_unavailable_rc" -eq 2 ]; then
            return 2
          fi
          if [ "$_bb_neutral_unavailable_rc" -eq "$BUGBOT_HANDLED_SKIP_RC" ]; then
            return 0
          fi

          # Non-blocking informational outcome — clean, no real findings.
          print_kv RESULT clean
      [ -n "${_current_sha:-${head_sha:-}}" ] && print_kv REVIEWED_HEAD "${_current_sha:-$head_sha}"
          print_kv PLATFORM "$platform"
          print_kv PR_NUMBER "$pr_number"
          print_kv BRANCH "$branch_name"
          print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
          print_kv COMMENT_COUNT 0
          print_kv BLOCKING_COUNT 0
          print_kv SUGGESTION_COUNT 0
          return 0
          ;;

        timed_out)
          # Bugbot's own internal timeout.
          print_kv RESULT escalate
          print_kv REASON timeout
          print_kv PLATFORM "$platform"
          print_kv PR_NUMBER "$pr_number"
          print_kv BRANCH "$branch_name"
          print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
          print_kv COMMENT_COUNT 0
          print_kv BLOCKING_COUNT 0
          print_kv SUGGESTION_COUNT 0
          return 2
          ;;

        *)
          # Unknown conclusion — escalate conservatively.
          print_kv RESULT escalate
          print_kv REASON "unknown-conclusion-${conclusion}"
          print_kv PLATFORM "$platform"
          print_kv PR_NUMBER "$pr_number"
          print_kv BRANCH "$branch_name"
          print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
          print_kv COMMENT_COUNT 0
          print_kv BLOCKING_COUNT 0
          print_kv SUGGESTION_COUNT 0
          return 2
          ;;
      esac
    fi

    # Track whether any Cursor Bugbot run has appeared (for unavailable detection).
    if [ "$check_appeared" -eq 0 ] && [ -n "$status_val" ]; then
      check_appeared=1
    fi

    # Signal safety: _interruptible_sleep runs `sleep` as a background job and
    # blocks on bash's built-in `wait`, which is interruptible by signals.  When
    # SIGTERM arrives during this wait, the TERM trap fires immediately — killing
    # the background sleep subprocess (CURRENT_CHILD_PID) and re-raising SIGTERM
    # — so the process exits within milliseconds regardless of poll_interval size.
    _interruptible_sleep "$poll_interval"
    elapsed=$(( elapsed + poll_interval ))
  done

  # Poll budget exhausted.  Distinguish timeout (run appeared) from unavailable
  # (no Cursor Bugbot check run ever appeared — Cursor app likely not installed).
  # Either way, never report as clean (AC-5).
  if [ "$check_appeared" -eq 0 ]; then
    print_kv RESULT escalate
    print_kv REASON unavailable
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT 0
    print_kv BLOCKING_COUNT 0
    print_kv SUGGESTION_COUNT 0
    return 2
  fi

  print_kv RESULT escalate
  print_kv REASON timeout
  print_kv PLATFORM "$platform"
  print_kv PR_NUMBER "$pr_number"
  print_kv BRANCH "$branch_name"
  print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
  print_kv COMMENT_COUNT 0
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT 0
  return 2
}

run_haystack_review() {
  # Runs haystack-reviewer.sh for the given PR and maps its exit codes to the
  # standard pr-review-loop key-value output contract.
  #
  # The companion script polls haystack triage internally (poll-retry loop for
  # status=pending). The timeout is passed via --timeout.
  #
  # Exit code mapping from haystack-reviewer.sh:
  #   0 → RESULT=clean    (no blocking findings)
  #   1 → RESULT=needs_fixes (one or more blocking findings)
  #   2 → RESULT=escalate; REASON forwarded from companion script:
  #         REASON=timeout         — per-call OS timeout exhausted budget
  #         REASON=pending_timeout — analysis stayed pending past timeout budget
  #   3 → RESULT=skipped; REASON and DISPLAY_RESULT forwarded
  #         (unavailable, unauthorized, forbidden,
  #          analysis_skipped_file_limit, …)
  local pr_number="$1"
  local branch_name="$2"
  # poll_interval and max_wait passed for interface consistency; haystack-reviewer.sh
  # manages its own internal poll interval (HAYSTACK_POLL_INTERVAL env var), so
  # poll_interval from the caller is not used here. max_wait is passed as --timeout.
  local poll_interval="$3"
  local max_wait="$4"
  local platform="haystack"
  local reviewer_script
  local script_exit=0
  local script_output=""
  local blocking_count=0
  local suggestion_count=0
  local comment_count=0

  require_gh
  cd_workflow_repo_root

  local owner repo_name repo
  repo="$(repo_slug)"
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

  set +e
  local is_draft
  local _draft_rc=0
  is_draft="$(gh pr view "$pr_number" --repo "$owner/$repo_name" --json isDraft --jq '.isDraft' 2>/dev/null)"
  _draft_rc=$?
  set -e
  if [ "$_draft_rc" -ne 0 ] || [ -z "$is_draft" ]; then
    echo "WARN: could not determine draft state for PR #$pr_number before Haystack review" >&2
    print_kv RESULT escalate
    print_kv REASON draft-state-unavailable
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT 0
    print_kv BLOCKING_COUNT 0
    print_kv SUGGESTION_COUNT 0
    return 2
  fi
  if [ "$is_draft" = "true" ]; then
    echo "INFO: PR #$pr_number is draft — Haystack does not review draft PRs; mark ready with gh pr ready $pr_number before rerunning" >&2
    print_kv RESULT skipped
    print_kv REASON pr-is-draft
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT 0
    print_kv BLOCKING_COUNT 0
    print_kv SUGGESTION_COUNT 0
    return 0
  fi

  reviewer_script="$(workflow_repo_root)/scripts/development-workflow/haystack-reviewer.sh"

  # Haystack-reviewer.sh manages its own poll-retry loop internally; honor the
  # caller-provided max_wait budget as the overall timeout.
  local effective_timeout
  effective_timeout="$max_wait"

  local haystack_stderr_file
  haystack_stderr_file="$(mktemp)"
  trap 'rm -f "${haystack_stderr_file:-}"' RETURN

  set +e
  script_output="$("$reviewer_script" "$pr_number" "$owner" "$repo_name" --timeout "$effective_timeout" 2>"$haystack_stderr_file")"
  script_exit=$?
  set -e

  # Surface haystack-reviewer.sh stderr (INFO: diagnostics) to our own stderr so
  # callers can determine why a result was returned (e.g. status=pending, unavailable,
  # auth failure, CLI not installed).
  if [ -s "$haystack_stderr_file" ]; then
    echo "INFO: haystack-reviewer.sh stderr:" >&2
    cat "$haystack_stderr_file" >&2
  fi
  rm -f "$haystack_stderr_file"

  # Parse output from the companion script (key=value lines on stdout).
  blocking_count="$(printf '%s\n' "$script_output" | grep '^BLOCKING_COUNT=' | cut -d= -f2 | head -n 1)"
  suggestion_count="$(printf '%s\n' "$script_output" | grep '^SUGGESTION_COUNT=' | cut -d= -f2 | head -n 1)"
  comment_count="$(printf '%s\n' "$script_output" | grep '^COMMENT_COUNT=' | cut -d= -f2 | head -n 1)"

  # Default to 0 if any field is missing.
  blocking_count="${blocking_count:-0}"
  suggestion_count="${suggestion_count:-0}"
  comment_count="${comment_count:-0}"

  case "$script_exit" in
    0)
      print_kv RESULT clean
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT "$comment_count"
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT "$suggestion_count"
      print_kv REVIEWED_HEAD "$(kv_value_default REVIEWED_HEAD "$script_output" "")"
      return 0
      ;;
    1)
      # Ensure blocking_count >= 1 even if stdout parsing failed, and keep
      # comment_count consistent so downstream consumers don't see blocking
      # findings with zero comments.
      [ "$blocking_count" -eq 0 ] && blocking_count=1
      [ "$comment_count" -eq 0 ] && comment_count=1
      print_kv RESULT needs_fixes
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REASON haystack_blocking_findings
      print_kv COMMENT_COUNT "$comment_count"
      print_kv BLOCKING_COUNT "$blocking_count"
      print_kv SUGGESTION_COUNT "$suggestion_count"
      print_kv REVIEWED_HEAD "$(kv_value_default REVIEWED_HEAD "$script_output" "")"
      return 1
      ;;
    2)
      # Forward the REASON from the companion script (timeout or pending_timeout).
      local haystack_reason
      haystack_reason="$(printf '%s\n' "$script_output" | grep '^REASON=' | cut -d= -f2 | head -n 1)"
      haystack_reason="${haystack_reason:-timeout}"  # default to timeout if missing
      print_kv RESULT escalate
      print_kv REASON "$haystack_reason"
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REVIEWED_HEAD "$(kv_value_default REVIEWED_HEAD "$script_output" "")"
      return 2
      ;;
    *)
      # Exit 3 (UNAVAILABLE/auth errors) and any unexpected exit code → skipped.
      local haystack_reason
      local haystack_display_result
      haystack_reason="$(printf '%s\n' "$script_output" | grep '^REASON=' | cut -d= -f2 | head -n 1)"
      haystack_reason="${haystack_reason:-unavailable}"
      haystack_display_result="$(kv_value_default DISPLAY_RESULT "$script_output" "")"
      print_kv RESULT skipped
      print_kv REASON "$haystack_reason"
      [ -n "$haystack_display_result" ] && print_kv DISPLAY_RESULT "$haystack_display_result"
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      print_kv REVIEWED_HEAD "$(kv_value_default REVIEWED_HEAD "$script_output" "")"
      return 0
      ;;
  esac
}

run_coderabbit_cli_review() {
  # Runs coderabbit-cli-reviewer.sh and maps its exit codes to the standard
  # pr-review-loop key=value output contract. This is separate from the
  # coderabbit GitHub App platform, which uses bot comments/reviews.
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="coderabbit-cli"
  local reviewer_script
  local script_exit=0
  local script_output=""
  local blocking_count=0
  local suggestion_count=0
  local comment_count=0

  : "$poll_interval"
  require_gh
  reviewer_script="$(workflow_repo_root)/scripts/development-workflow/coderabbit-cli-reviewer.sh"
  review_repo_root="${repo_root:-$(workflow_repo_root)}"
  cd "$review_repo_root"

  local owner repo_name repo
  repo="$(repo_slug)"
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

  local coderabbit_cli_stderr_file
  local coderabbit_cli_config_file="${AI_DEV_WORKFLOW_CONFIG_FILE:-${config_file:-}}"
  coderabbit_cli_stderr_file="$(mktemp)"
  trap 'rm -f "${coderabbit_cli_stderr_file:-}"' RETURN

  set +e
  if [ -n "$coderabbit_cli_config_file" ] && [ -f "$coderabbit_cli_config_file" ]; then
    script_output="$(AI_DEV_WORKFLOW_CONFIG_FILE="$coderabbit_cli_config_file" "$reviewer_script" "$pr_number" "$owner" "$repo_name" --timeout "$max_wait" --repo-root "$review_repo_root" 2>"$coderabbit_cli_stderr_file")"
  else
    script_output="$("$reviewer_script" "$pr_number" "$owner" "$repo_name" --timeout "$max_wait" --repo-root "$review_repo_root" 2>"$coderabbit_cli_stderr_file")"
  fi
  script_exit=$?
  set -e

  if [ -s "$coderabbit_cli_stderr_file" ]; then
    echo "INFO: coderabbit-cli-reviewer.sh stderr:" >&2
    cat "$coderabbit_cli_stderr_file" >&2
  fi
  rm -f "$coderabbit_cli_stderr_file"

  blocking_count="$(kv_value_default BLOCKING_COUNT "$script_output" 0)"
  suggestion_count="$(kv_value_default SUGGESTION_COUNT "$script_output" 0)"
  comment_count="$(kv_value_default COMMENT_COUNT "$script_output" 0)"

  case "$script_exit" in
    0)
      print_kv RESULT clean
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT "$comment_count"
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT "$suggestion_count"
      print_kv REVIEWED_HEAD "$(kv_value_default REVIEWED_HEAD "$script_output" "")"
      return 0
      ;;
    1)
      local coderabbit_cli_script_result
      coderabbit_cli_script_result="$(kv_value_default RESULT "$script_output" needs_fixes)"
      if [ "$coderabbit_cli_script_result" != "needs_rerun" ]; then
        [ "$blocking_count" -eq 0 ] && blocking_count=1
        [ "$comment_count" -eq 0 ] && comment_count=1
      fi
      case "$coderabbit_cli_script_result" in
        needs_rerun) print_kv RESULT needs_rerun ;;
        *) print_kv RESULT needs_fixes ;;
      esac
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REASON coderabbit_cli_blocking_findings
      print_kv COMMENT_COUNT "$comment_count"
      print_kv BLOCKING_COUNT "$blocking_count"
      print_kv SUGGESTION_COUNT "$suggestion_count"
      for index in $(seq 1 "$blocking_count"); do
        print_kv "BLOCKING_${index}_PATH" "$(kv_value_default "BLOCKING_${index}_PATH" "$script_output" "")"
        print_kv "BLOCKING_${index}_LINE" "$(kv_value_default "BLOCKING_${index}_LINE" "$script_output" "")"
        print_kv "BLOCKING_${index}_BODY" "$(kv_value_default "BLOCKING_${index}_BODY" "$script_output" "")"
      done
      print_kv REVIEWED_HEAD "$(kv_value_default REVIEWED_HEAD "$script_output" "")"
      return 1
      ;;
    2)
      local coderabbit_cli_reason
      local coderabbit_cli_display_result
      coderabbit_cli_reason="$(kv_value_default REASON "$script_output" rate_limited)"
      coderabbit_cli_display_result="$(kv_value_default DISPLAY_RESULT "$script_output" "")"
      print_kv RESULT escalate
      print_kv REASON "$coderabbit_cli_reason"
      [ -n "$coderabbit_cli_display_result" ] && print_kv DISPLAY_RESULT "$coderabbit_cli_display_result"
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT "$comment_count"
      print_kv BLOCKING_COUNT "$blocking_count"
      print_kv SUGGESTION_COUNT "$suggestion_count"
      print_kv REVIEWED_HEAD "$(kv_value_default REVIEWED_HEAD "$script_output" "")"
      return 2
      ;;
    *)
      local coderabbit_cli_reason
      local coderabbit_cli_display_result
      coderabbit_cli_reason="$(kv_value_default REASON "$script_output" unavailable)"
      coderabbit_cli_display_result="$(kv_value_default DISPLAY_RESULT "$script_output" "")"
      print_kv RESULT skipped
      print_kv REASON "$coderabbit_cli_reason"
      [ -n "$coderabbit_cli_display_result" ] && print_kv DISPLAY_RESULT "$coderabbit_cli_display_result"
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT "$comment_count"
      print_kv BLOCKING_COUNT "$blocking_count"
      print_kv SUGGESTION_COUNT "$suggestion_count"
      print_kv REVIEWED_HEAD "$(kv_value_default REVIEWED_HEAD "$script_output" "")"
      return 0
      ;;
  esac
}

# Forward STRICT_SPEC_* and STRICT_PLAN_* keys from local-ai-reviewer.sh output unchanged.
emit_local_ai_strict_spec_keys() {
  local script_output="$1"
  local line key
  while IFS= read -r line; do
    [ -z "${line:-}" ] && continue
    key="${line%%=*}"
    case "$key" in
      STRICT_SPEC_STATE|STRICT_SPEC_COUNT|STRICT_SPEC_CHECKS|STRICT_SPEC_UNKNOWN_COUNT|STRICT_SPEC_REASON)
        print_kv "$key" "${line#*=}"
        ;;
      STRICT_PLAN_STATE|STRICT_PLAN_COUNT|STRICT_PLAN_CHECKS|STRICT_PLAN_APPLIED|STRICT_PLAN_UNKNOWN_COUNT|STRICT_PLAN_REASON)
        print_kv "$key" "${line#*=}"
        ;;
      STRICT_[0-9]*_CHECK|STRICT_[0-9]*_PATH|STRICT_[0-9]*_LINE|STRICT_[0-9]*_BODY)
        print_kv "$key" "${line#*=}"
        ;;
    esac
  done <<< "$script_output"
}

emit_local_ai_review_stage_keys() {
  local script_output="$1"
  local stage source checklists
  stage="$(kv_value_default REVIEW_STAGE "$script_output" "")"
  source="$(kv_value_default REVIEW_STAGE_SOURCE "$script_output" "")"
  checklists="$(kv_value_default REVIEW_CHECKLISTS "$script_output" "")"
  [ -n "$stage" ] && print_kv REVIEW_STAGE "$stage"
  [ -n "$source" ] && print_kv REVIEW_STAGE_SOURCE "$source"
  [ -n "$checklists" ] && print_kv REVIEW_CHECKLISTS "$checklists"
}

emit_local_ai_review_doctrine_keys() {
  local script_output="$1"
  local state pattern_count version
  if ! grep -q '^REVIEW_DOCTRINE_STATE=' <<< "$script_output"; then
    return 0
  fi
  state="$(kv_value_default REVIEW_DOCTRINE_STATE "$script_output" "")"
  pattern_count="$(kv_value_default REVIEW_DOCTRINE_PATTERN_COUNT "$script_output" "0")"
  version="$(kv_value_default REVIEW_DOCTRINE_VERSION "$script_output" "")"
  print_kv REVIEW_DOCTRINE_STATE "$state"
  print_kv REVIEW_DOCTRINE_PATTERN_COUNT "$pattern_count"
  print_kv REVIEW_DOCTRINE_VERSION "$version"
}

# Capture STRICT_SPEC_* into globals for reviewer_loop_history_build_entry.
# Present object vs absent object is gated by strict_spec_recorded.
capture_strict_spec_globals_from_output() {
  local script_output="$1"
  local state
  local idx
  local check path line body
  state="$(kv_value_default STRICT_SPEC_STATE "$script_output" "")"
  if [ -z "$state" ]; then
    return 0
  fi
  strict_spec_recorded=1
  strict_spec_state="$state"
  strict_spec_count="$(kv_value_default STRICT_SPEC_COUNT "$script_output" "")"
  strict_spec_checks="$(kv_value_default STRICT_SPEC_CHECKS "$script_output" "")"
  strict_spec_unknown_count="$(kv_value_default STRICT_SPEC_UNKNOWN_COUNT "$script_output" "")"
  strict_spec_reason="$(kv_value_default STRICT_SPEC_REASON "$script_output" "")"
  strict_spec_summary_section=""
  if [ "$state" = "applied" ] && [ -n "$strict_spec_count" ] && [ "$strict_spec_count" -gt 0 ]; then
    strict_spec_summary_section="

**Strict spec findings (non-blocking):**"
    idx=1
    while true; do
      check="$(kv_value_default "STRICT_${idx}_CHECK" "$script_output" "")"
      [ -z "$check" ] && break
      path="$(kv_value_default "STRICT_${idx}_PATH" "$script_output" "")"
      line="$(kv_value_default "STRICT_${idx}_LINE" "$script_output" "")"
      body="$(kv_value_default "STRICT_${idx}_BODY" "$script_output" "")"
      strict_spec_summary_section="${strict_spec_summary_section}
- \`${check}\` ${path}:${line} — ${body}"
      idx=$((idx + 1))
    done
  fi
}

capture_strict_plan_globals_from_output() {
  local script_output="$1"
  local state
  local idx
  local check path line body
  state="$(kv_value_default STRICT_PLAN_STATE "$script_output" "")"
  if [ -z "$state" ]; then
    return 0
  fi
  strict_plan_recorded=1
  strict_plan_state="$state"
  strict_plan_count="$(kv_value_default STRICT_PLAN_COUNT "$script_output" "")"
  strict_plan_checks="$(kv_value_default STRICT_PLAN_CHECKS "$script_output" "")"
  strict_plan_applied="$(kv_value_default STRICT_PLAN_APPLIED "$script_output" "")"
  strict_plan_unknown_count="$(kv_value_default STRICT_PLAN_UNKNOWN_COUNT "$script_output" "")"
  strict_plan_reason="$(kv_value_default STRICT_PLAN_REASON "$script_output" "")"
  strict_plan_summary_section=""
  if [ "$state" = "applied" ] && [ -n "$strict_plan_count" ] && [ "$strict_plan_count" -gt 0 ]; then
    strict_plan_summary_section="

**Strict plan findings (non-blocking):** applied checks: \`${strict_plan_applied:-}\`"
    idx=1
    while true; do
      check="$(kv_value_default "STRICT_${idx}_CHECK" "$script_output" "")"
      [ -z "$check" ] && break
      path="$(kv_value_default "STRICT_${idx}_PATH" "$script_output" "")"
      line="$(kv_value_default "STRICT_${idx}_LINE" "$script_output" "")"
      body="$(kv_value_default "STRICT_${idx}_BODY" "$script_output" "")"
      strict_plan_summary_section="${strict_plan_summary_section}
- \`${check}\` ${path}:${line} — ${body}"
      idx=$((idx + 1))
    done
  fi
}

run_local_ai_reviewer_review() {
  # Runs local-ai-reviewer.sh and maps its exit codes to the standard
  # pr-review-loop key=value output contract.
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="local-ai-reviewer"
  local reviewer_script
  local script_exit=0
  local script_output=""
  local blocking_count=0
  local suggestion_count=0
  local comment_count=0

  : "$poll_interval"
  require_gh
  reviewer_script="$(workflow_repo_root)/scripts/development-workflow/local-ai-reviewer.sh"
  review_repo_root="${repo_root:-$(workflow_repo_root)}"
  cd "$review_repo_root"

  local owner repo_name repo
  repo="$(repo_slug)"
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

  local local_ai_stderr_file
  local local_ai_config_file="${AI_DEV_WORKFLOW_CONFIG_FILE:-${config_file:-}}"
  local_ai_stderr_file="$(mktemp)"
  trap 'rm -f "${local_ai_stderr_file:-}"' RETURN

  set +e
  if [ -n "$local_ai_config_file" ] && [ -f "$local_ai_config_file" ]; then
    script_output="$(AI_DEV_WORKFLOW_CONFIG_FILE="$local_ai_config_file" "$reviewer_script" "$pr_number" "$owner" "$repo_name" --timeout "$max_wait" --repo-root "$review_repo_root" 2>"$local_ai_stderr_file")"
  else
    script_output="$("$reviewer_script" "$pr_number" "$owner" "$repo_name" --timeout "$max_wait" --repo-root "$review_repo_root" 2>"$local_ai_stderr_file")"
  fi
  script_exit=$?
  set -e

  if [ -s "$local_ai_stderr_file" ]; then
    echo "INFO: local-ai-reviewer.sh stderr:" >&2
    cat "$local_ai_stderr_file" >&2
  fi
  rm -f "$local_ai_stderr_file"

  blocking_count="$(kv_value_default BLOCKING_COUNT "$script_output" 0)"
  suggestion_count="$(kv_value_default SUGGESTION_COUNT "$script_output" 0)"
  comment_count="$(kv_value_default COMMENT_COUNT "$script_output" 0)"

  case "$script_exit" in
    0)
      print_kv RESULT clean
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT "$comment_count"
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT "$suggestion_count"
      print_kv REVIEWED_HEAD "$(kv_value_default REVIEWED_HEAD "$script_output" "")"
      print_kv GRAPH_CONTEXT "$(kv_value_default GRAPH_CONTEXT "$script_output" "")"
      emit_local_ai_strict_spec_keys "$script_output"
      emit_local_ai_review_stage_keys "$script_output"
      emit_local_ai_review_doctrine_keys "$script_output"
      return 0
      ;;
    1)
      local local_ai_script_result
      local_ai_script_result="$(kv_value_default RESULT "$script_output" needs_fixes)"
      if [ "$local_ai_script_result" != "needs_rerun" ]; then
        [ "$blocking_count" -eq 0 ] && blocking_count=1
        [ "$comment_count" -eq 0 ] && comment_count=1
      fi
      case "$local_ai_script_result" in
        needs_rerun) print_kv RESULT needs_rerun ;;
        *) print_kv RESULT needs_fixes ;;
      esac
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REASON "$(kv_value_default REASON "$script_output" local_ai_review_findings)"
      print_kv COMMENT_COUNT "$comment_count"
      print_kv BLOCKING_COUNT "$blocking_count"
      print_kv SUGGESTION_COUNT "$suggestion_count"
      for index in $(seq 1 "$blocking_count"); do
        print_kv "BLOCKING_${index}_PATH" "$(kv_value_default "BLOCKING_${index}_PATH" "$script_output" "")"
        print_kv "BLOCKING_${index}_LINE" "$(kv_value_default "BLOCKING_${index}_LINE" "$script_output" "")"
        print_kv "BLOCKING_${index}_BODY" "$(kv_value_default "BLOCKING_${index}_BODY" "$script_output" "")"
      done
      print_kv REVIEWED_HEAD "$(kv_value_default REVIEWED_HEAD "$script_output" "")"
      print_kv GRAPH_CONTEXT "$(kv_value_default GRAPH_CONTEXT "$script_output" "")"
      emit_local_ai_strict_spec_keys "$script_output"
      emit_local_ai_review_stage_keys "$script_output"
      emit_local_ai_review_doctrine_keys "$script_output"
      return 1
      ;;
    2)
      local local_ai_reason
      local local_ai_display_result
      local_ai_reason="$(kv_value_default REASON "$script_output" malformed_output)"
      local_ai_display_result="$(kv_value_default DISPLAY_RESULT "$script_output" "")"
      print_kv RESULT escalate
      print_kv REASON "$local_ai_reason"
      [ -n "$local_ai_display_result" ] && print_kv DISPLAY_RESULT "$local_ai_display_result"
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT "$comment_count"
      print_kv BLOCKING_COUNT "$blocking_count"
      print_kv SUGGESTION_COUNT "$suggestion_count"
      print_kv REVIEWED_HEAD "$(kv_value_default REVIEWED_HEAD "$script_output" "")"
      print_kv GRAPH_CONTEXT "$(kv_value_default GRAPH_CONTEXT "$script_output" "")"
      emit_local_ai_strict_spec_keys "$script_output"
      emit_local_ai_review_stage_keys "$script_output"
      emit_local_ai_review_doctrine_keys "$script_output"
      return 2
      ;;
    *)
      local local_ai_reason
      local local_ai_display_result
      local_ai_reason="$(kv_value_default REASON "$script_output" disabled_by_config)"
      local_ai_display_result="$(kv_value_default DISPLAY_RESULT "$script_output" "")"
      print_kv RESULT skipped
      print_kv REASON "$local_ai_reason"
      [ -n "$local_ai_display_result" ] && print_kv DISPLAY_RESULT "$local_ai_display_result"
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT "$comment_count"
      print_kv BLOCKING_COUNT "$blocking_count"
      print_kv SUGGESTION_COUNT "$suggestion_count"
      print_kv REVIEWED_HEAD "$(kv_value_default REVIEWED_HEAD "$script_output" "")"
      print_kv GRAPH_CONTEXT "$(kv_value_default GRAPH_CONTEXT "$script_output" "")"
      emit_local_ai_strict_spec_keys "$script_output"
      emit_local_ai_review_stage_keys "$script_output"
      emit_local_ai_review_doctrine_keys "$script_output"
      return 0
      ;;
  esac
}

run_devin_review() {
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="devin"
  local bot_login="devin-ai-integration[bot]"
  local repo
  local head_sha=""
  local since_iso=""
  local existing_comments=""
  local existing_reviews=""
  local existing_blocking_file=""
  local existing_blocking_count=0
  local existing_inline_blocking_count=0
  local inline_comment_count=0
  local review_state=""
  local comment_json=""
  local review_json=""
  local body=""
  local blocking_lines_file=""
  local elapsed=0
  local check_completed=0
  local comments=""
  local blocking_reviews=""
  local blocking_count=0
  local comment_count=0
  local index=1
  local blocking_json=""
  local stale_file=""

  trap 'rm -f "${existing_blocking_file:-}" "${blocking_lines_file:-}" "${stale_file:-}"' RETURN

  require_gh
  cd_workflow_repo_root
  repo="$(repo_slug)"

  head_sha="$(gh api "repos/$repo/pulls/$pr_number" --jq '.head.sha')"
  if [ -z "$head_sha" ]; then
    print_kv RESULT escalate
    print_kv REASON "head-sha-unavailable"
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID ""
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    return 2
  fi
  since_iso="$(gh api "repos/$repo/commits/$head_sha" --jq '.commit.committer.date // empty')"
  if [ -z "$since_iso" ]; then
    since_iso="$(date -u -v-24H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '24 hours ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo '1970-01-01T00:00:00Z')"
  fi
  # Cap to now: a future committer.date (clock skew or rebase) would exclude all
  # existing bot comments, causing false-clean results or duplicate review requests.
  _now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  [ "$since_iso" \> "$_now_iso" ] && since_iso="$_now_iso"
  unset _now_iso

  # --- Phase 1: Check for existing blocking findings on the current HEAD ---
  existing_comments="$(
    gh api "repos/$repo/pulls/$pr_number/comments" --paginate \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
          .[]
          | select(.user.login == $bot and .created_at > $since and .in_reply_to_id == null)
          | { path, line: (.line // .original_line // 0), body: (.body // ""), commit_id: (.commit_id // "") }
          | @json
        '
  )"
  existing_reviews="$(
    gh api "repos/$repo/pulls/$pr_number/reviews" --paginate \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
          .[]
          | select(
              .user.login == $bot and
              .submitted_at > $since and
              (
                .state == "CHANGES_REQUESTED" or
                .state == "COMMENTED"
              )
            )
          | { path: "", line: 0, body: (.body // "review without body"), state: .state, commit_id: (.commit_id // .commitId // "") }
          | @json
        '
  )"
  existing_blocking_file="$(mktemp)"
  # Process inline comments first so existing_blocking_count reflects inline findings
  # before we evaluate COMMENTED reviews (used for the inline-findings gate below).
  while IFS= read -r comment_json; do
    [ -z "${comment_json:-}" ] && continue
    body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then continue; fi
    if printf '%s\n' "$body" | grep -q "^✅"; then continue; fi
    existing_blocking_count=$((existing_blocking_count + 1))
    printf '%s\n' "$comment_json" >> "$existing_blocking_file"
  done <<< "$existing_comments"
  # Snapshot the inline blocking count before processing reviews (used below).
  existing_inline_blocking_count="$existing_blocking_count"

  while IFS= read -r review_json; do
    [ -z "${review_json:-}" ] && continue
    body="$(printf '%s\n' "$review_json" | jq -r '.body')"
    review_state="$(printf '%s\n' "$review_json" | jq -r '.state // ""')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then continue; fi
    if printf '%s\n' "$body" | grep -q "^✅"; then continue; fi
    # For COMMENTED reviews, only treat as blocking when:
    # (a) the body starts with "**Devin Review**" (Devin uses COMMENTED instead of
    #     CHANGES_REQUESTED regardless of finding severity), OR
    # (b) there are blocking inline comments from Devin (the COMMENTED review is the
    #     umbrella review object that accompanies those inline findings).
    # COMMENTED reviews with no inline findings are informational and not blocking.
    if [ "$review_state" = "COMMENTED" ]; then
      if printf '%s\n' "$body" | grep -qi "^\\*\\*Devin Review\\*\\*"; then
        : # falls through to blocking logic below
      elif [ "$existing_inline_blocking_count" -gt 0 ]; then
        : # COMMENTED review with inline findings — treat as blocking
      else
        continue  # COMMENTED review with no inline findings — not blocking
      fi
    fi
    existing_blocking_count=$((existing_blocking_count + 1))
    printf '%s\n' "$review_json" >> "$existing_blocking_file"
  done <<< "$existing_reviews"

  if [ "$existing_blocking_count" -gt 0 ]; then
    print_kv RESULT needs_fixes
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID ""
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv REASON existing_findings
    print_kv COMMENT_COUNT "$existing_blocking_count"
    print_kv BLOCKING_COUNT "$existing_blocking_count"
    print_kv SUGGESTION_COUNT 0
    while IFS= read -r blocking_json; do
      [ -z "${blocking_json:-}" ] && continue
      print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
      print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
      print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
      index=$((index + 1))
    done < "$existing_blocking_file"
    reviewer_loop_print_reviewed_head_from_json_lines < "$existing_blocking_file"
    rm -f "$existing_blocking_file"
    return 1
  fi

  rm -f "$existing_blocking_file"

  # --- Phase 2: Poll for Devin review completion ---
  # Devin signals completion by either:
  # 1. A summary review (body contains "**Devin Review**" or "Devin Review has completed"), or
  # 2. A "No Issues Found" review when it finds nothing to report (often no check run in that case), or
  # 3. Check run completed plus a grace period (for inline-only or no summary).
  # We check for (1) and (2) every iteration so we notice as soon as Devin posts.
  #
  local devin_any_check_count=0
  local check_completed_at=-1   # -1 = not yet seen; record first-seen time
  local devin_post_check_grace=120  # seconds to wait after check completes
  local devin_summary_count=0
  local since_check_completed=0
  local devin_status_count=0
  local devin_completed_status_count=0

  while :; do
    # Check for any Devin completion review every iteration (so "No Issues Found" is detected)
    devin_summary_count="$(
      gh api "repos/$repo/pulls/$pr_number/reviews" --paginate \
        | jq --arg bot "$bot_login" --arg since "$since_iso" '
            [.[]
             | select(
                 .user.login == $bot and
                 .submitted_at > $since and
                 (.body // "" | test("\\*\\*Devin Review\\*\\*|Devin Review has completed|No Issues Found"; "i"))
               )
            ] | length
          '
    )"
    devin_summary_count="${devin_summary_count:-0}"
    if [ "$devin_summary_count" -gt 0 ]; then
      # Summary or "No Issues Found" review — Devin is done
      break
    fi

    read -r devin_any_check_count check_completed < <(
      gh api "repos/$repo/commits/$head_sha/check-runs" --paginate \
        | jq -s -r '
            [.[].check_runs[] | select(
              (.app.slug == "devin-ai-integration") or
              (.name | test("devin"; "i"))
            )] as $runs
            | ($runs | length),
              ($runs | map(select(.status == "completed")) | length)
            | tostring
          ' | tr '\n' ' '; echo
    )
    devin_any_check_count="${devin_any_check_count:-0}"
    check_completed="${check_completed:-0}"

    # Also count Devin status contexts (Devin sometimes signals via a GitHub Status
    # Context on the commit rather than a Check Run — both mean Devin has completed).
    # devin_status_count: any Devin status context (including pending) — used for
    #   devin_any_check_count so we know Devin is configured and active.
    # devin_completed_status_count: only terminal states (success/failure/error) — used
    #   for check_completed so a pending status never starts the grace timer prematurely.
    # Deduplicate by context (keep latest entry per context) to avoid double-counting
    # when the same context transitions through multiple states (e.g. pending → success).
    read -r devin_status_count devin_completed_status_count < <(
      gh api "repos/$repo/commits/$head_sha/statuses" --paginate \
        | jq -s -r '
            ( [.[].[] | select(.context | test("devin"; "i"))]
              | group_by(.context) | map(max_by(.updated_at)) | length ),
            ( [.[].[] | select(.context | test("devin"; "i"))]
              | group_by(.context) | map(max_by(.updated_at))
              | map(select(.state == "success" or .state == "failure" or .state == "error"))
              | length )
            | tostring
          ' | tr '\n' ' '; echo
    )
    devin_status_count="${devin_status_count:-0}"
    devin_completed_status_count="${devin_completed_status_count:-0}"
    if [ "$devin_status_count" -gt 0 ]; then
      devin_any_check_count=$(( devin_any_check_count + devin_status_count ))
    fi

    # Only count status contexts in terminal states toward check_completed.
    if [ "$devin_completed_status_count" -gt 0 ]; then
      check_completed=$(( check_completed + devin_completed_status_count ))
    fi

    if [ "$check_completed" -gt 0 ]; then
      if [ "$check_completed_at" -eq -1 ]; then
        check_completed_at="$elapsed"
      fi
      since_check_completed=$(( elapsed - check_completed_at ))
      if [ "$since_check_completed" -ge "$devin_post_check_grace" ]; then
        break
      fi
    fi

    if [ "$elapsed" -ge "$max_wait" ]; then
      if [ "$devin_any_check_count" -eq 0 ]; then
        # Devin didn't review this HEAD (common after merging the base branch
        # when the diff didn't change). Before reporting "skipped", scan the
        # full PR history for unresolved Devin findings from prior reviews.
        local stale_count=0
        local stale_comments
        # Only consider unresolved inline comments here. Historical review-level
        # summaries (e.g., CHANGES_REQUESTED/COMMENTED) may have been superseded
        # by later clean runs and can cause false stale blockers.
        stale_comments="$(
          gh api "repos/$repo/pulls/$pr_number/comments" --paginate \
            | jq -s -r --arg bot "$bot_login" '
                (
                  [
                    .[][]
                    | select(
                        .user.login == $bot and
                        .in_reply_to_id != null and
                        ((.body // "") | test("^✅"))
                      )
                    | .in_reply_to_id
                  ]
                ) as $resolved_ids
                | .[][]
                | select(
                    .user.login == $bot and
                    .in_reply_to_id == null and
                    ((.body // "") | test("^✅") | not) and
                    ((.body // "") | test("✅ Addressed") | not) and
                    ((.body // "") | test("No Issues Found"; "i") | not) and
                    (.id as $comment_id | ($resolved_ids | index($comment_id) | not))
                  )
                | { path, line: (.line // .original_line // 0), body: (.body // ""), commit_id: (.commit_id // "") }
                | @json
              '
        )"
        stale_file="$(mktemp)"
        while IFS= read -r comment_json; do
          [ -z "${comment_json:-}" ] && continue
          stale_count=$((stale_count + 1))
          printf '%s\n' "$comment_json" >> "$stale_file"
        done <<< "$stale_comments"

        if [ "$stale_count" -gt 0 ]; then
          print_kv RESULT needs_fixes
          print_kv PLATFORM "$platform"
          print_kv PR_NUMBER "$pr_number"
          print_kv BRANCH "$branch_name"
          print_kv REVIEW_COMMENT_ID ""
          print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
          print_kv REASON stale_findings
          print_kv COMMENT_COUNT "$stale_count"
          print_kv BLOCKING_COUNT "$stale_count"
          print_kv SUGGESTION_COUNT 0
          while IFS= read -r blocking_json; do
            [ -z "${blocking_json:-}" ] && continue
            print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
            print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
            print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
            index=$((index + 1))
          done < "$stale_file"
          reviewer_loop_print_reviewed_head_from_json_lines < "$stale_file"
          rm -f "$stale_file"
          return 1
        fi
        rm -f "$stale_file"

        print_kv RESULT skipped
        print_kv REASON no_check_run
        print_kv PLATFORM "$platform"
        print_kv PR_NUMBER "$pr_number"
        print_kv BRANCH "$branch_name"
        print_kv REVIEW_COMMENT_ID ""
        print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
        print_kv COMMENT_COUNT 0
        print_kv BLOCKING_COUNT 0
        print_kv SUGGESTION_COUNT 0
        return 0
      fi
      print_kv RESULT escalate
      print_kv REASON timeout
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      return 2
    fi

    _interruptible_sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
  done

  # --- Phase 3: Collect results after completion ---
  blocking_lines_file="$(mktemp)"

  comments="$(
    gh api "repos/$repo/pulls/$pr_number/comments" --paginate \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
        .[]
        | select(.user.login == $bot and .created_at > $since and .in_reply_to_id == null)
        | {
            path,
            line: (.line // .original_line // 0),
            body: (.body // ""),
            commit_id: (.commit_id // "")
          }
        | @json
      '
  )"

  blocking_reviews="$(
    gh api "repos/$repo/pulls/$pr_number/reviews" --paginate \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
        .[]
        | select(
            .user.login == $bot and
            .submitted_at > $since and
            (
              .state == "CHANGES_REQUESTED" or
              .state == "COMMENTED"
            )
          )
        | {
            path: "",
            line: 0,
            body: (.body // "review without body"),
            state: .state,
            commit_id: (.commit_id // .commitId // "")
          }
        | @json
      '
  )"

  # Count blocking inline comments from this HEAD for the COMMENTED-with-findings check.
  inline_comment_count=0
  while IFS= read -r comment_json; do
    [ -z "${comment_json:-}" ] && continue
    body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then continue; fi
    if printf '%s\n' "$body" | grep -q "^✅"; then continue; fi
    comment_count=$((comment_count + 1))
    blocking_count=$((blocking_count + 1))
    inline_comment_count=$((inline_comment_count + 1))
    printf '%s\n' "$comment_json" >> "$blocking_lines_file"
  done <<< "$comments"

  while IFS= read -r review_json; do
    [ -z "${review_json:-}" ] && continue
    body="$(printf '%s\n' "$review_json" | jq -r '.body')"
    review_state="$(printf '%s\n' "$review_json" | jq -r '.state // ""')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then continue; fi
    if printf '%s\n' "$body" | grep -q "^✅"; then continue; fi
    # For COMMENTED reviews, only treat as blocking when:
    # (a) the body starts with "**Devin Review**" (Devin uses COMMENTED instead of
    #     CHANGES_REQUESTED regardless of finding severity), OR
    # (b) there are blocking inline comments from Devin (the COMMENTED review is the
    #     umbrella review object that accompanies those inline findings).
    # Non-matching COMMENTED reviews with no inline comments are informational and
    # not blocking.
    if [ "$review_state" = "COMMENTED" ]; then
      if printf '%s\n' "$body" | grep -qi "^\\*\\*Devin Review\\*\\*"; then
        : # falls through to blocking logic below
      elif [ "$inline_comment_count" -gt 0 ]; then
        : # COMMENTED review with inline findings — treat as blocking
      else
        continue  # COMMENTED review with no inline comments — not blocking
      fi
    fi
    comment_count=$((comment_count + 1))
    blocking_count=$((blocking_count + 1))
    printf '%s\n' "$review_json" >> "$blocking_lines_file"
  done <<< "$blocking_reviews"

  if [ "$blocking_count" -gt 0 ]; then
    print_kv RESULT needs_fixes
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID ""
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT "$comment_count"
    print_kv BLOCKING_COUNT "$blocking_count"
    print_kv SUGGESTION_COUNT 0
    while IFS= read -r blocking_json; do
      [ -z "${blocking_json:-}" ] && continue
      print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
      print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
      print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
      index=$((index + 1))
    done < "$blocking_lines_file"
    reviewer_loop_print_reviewed_head_from_json_lines < "$blocking_lines_file"
    rm -f "$blocking_lines_file"
    return 1
  fi

  rm -f "$blocking_lines_file"
  print_kv RESULT clean
    {
      [ -n "${comments:-}" ] && printf '%s\n' "$comments"
      [ -n "${existing_comments:-}" ] && printf '%s\n' "$existing_comments"
      [ -n "${blocking_reviews:-}" ] && printf '%s\n' "$blocking_reviews"
      [ -n "${existing_reviews:-}" ] && printf '%s\n' "$existing_reviews"
      [ -n "${reviews:-}" ] && printf '%s\n' "$reviews"
    } | reviewer_loop_print_reviewed_head_from_json_lines
  print_kv PLATFORM "$platform"
  print_kv PR_NUMBER "$pr_number"
  print_kv BRANCH "$branch_name"
  print_kv REVIEW_COMMENT_ID ""
  print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
  print_kv COMMENT_COUNT "$comment_count"
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT 0
  return 0
}

run_pr_agent_review() {
  # PR-Agent posts all review output as plain PR issue comments — it does NOT submit
  # formal GitHub PR reviews (APPROVED/CHANGES_REQUESTED/COMMENTED). The summary
  # comment always contains "PR Reviewer Guide" in its body. Two stable body markers
  # distinguish clean from has-issues:
  #   "No major issues detected"                                → clean
  #   "Recommended focus areas for review" → may or may not be blocking (see below)
  #
  # PR-Agent always emits "Recommended focus areas for review" when it finds any
  # suggestion — including purely advisory ones. The bold labels inside that
  # section determine the verdict:
  #   Hard-blocker / security / compatibility labels → needs_fixes (case-insensitive):
  #     Critical, Must Fix, Breaking Change, Security Concern,
  #     API Change, Backward Compatibility
  #   All other labels → clean (advisory-only — PR-Agent uses a wide variety of
  #     quality/style labels that are non-blocking by nature)
  #   No labels parseable → needs_fixes (unreadable format — conservative)
  #
  # Bot login is "github-actions[bot]" when using GITHUB_TOKEN. Override with
  # PR_AGENT_BOT_LOGIN when using a GitHub App token (e.g. for fork PR support).
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="pr-agent"
  local bot_login="${PR_AGENT_BOT_LOGIN:-github-actions[bot]}"
  local repo
  local head_sha=""
  local since_iso=""
  local elapsed=0
  local comment_body=""
  local trigger_body="/review"

  require_gh
  cd_workflow_repo_root
  repo="$(repo_slug)"

  head_sha="$(gh api "repos/$repo/pulls/$pr_number" --jq '.head.sha')"
  if [ -z "$head_sha" ]; then
    print_kv RESULT escalate
    print_kv REASON "head-sha-unavailable"
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID ""
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    return 2
  fi
  # Use the HEAD commit's push timestamp to scope comments to this review cycle.
  since_iso="$(gh api "repos/$repo/commits/$head_sha" --jq '.commit.committer.date // empty')"
  if [ -z "$since_iso" ]; then
    since_iso="$(date -u -v-24H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '24 hours ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo '1970-01-01T00:00:00Z')"
  fi
  # Cap to now: a future committer.date (clock skew or rebase) would exclude all
  # existing bot comments, causing false-clean results or duplicate review requests.
  _now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  [ "$since_iso" \> "$_now_iso" ] && since_iso="$_now_iso"
  unset _now_iso

  # Common helper: fetch the matching PR-Agent comment and return one of its fields.
  # Parameters: field (e.g. "body" or "html_url"), match_mode (optional, default "strict_sha").
  # Returns the empty string when no matching comment is found.
  _pr_agent_latest_comment_field() {
    local field="$1"
    local match_mode="${2:-strict_sha}"
    gh api "repos/$repo/issues/$pr_number/comments" --paginate \
      | jq -rs --arg bot "$bot_login" --arg sha "$head_sha" --arg since "$since_iso" \
               --arg mode "$match_mode" --arg field "$field" '
          add // []
          | [.[]
             | select(
                 .user.login == $bot and
                 (
                   ($mode == "strict_sha" and ((.body // "") | contains($sha))) or
                   ($mode == "recent_or_sha" and (((.body // "") | contains($sha)) or .updated_at > $since))
                 ) and
                 ((.body // "") | test("PR Reviewer Guide"; "i"))
               )
            ]
          | sort_by(.updated_at)
          | last
          | .[$field] // ""
        '
  }

  _pr_agent_latest_comment() {
    _pr_agent_latest_comment_field "body" "${1:-strict_sha}"
  }

  _pr_agent_latest_comment_url() {
    _pr_agent_latest_comment_field "html_url" "${1:-strict_sha}"
  }

  _pr_agent_active_review_check_count() {
    gh api "repos/$repo/commits/$head_sha/check-runs" --paginate \
      | jq -rs '[.[].check_runs[]? | select(.name == "PR-Agent review" and (.status == "queued" or .status == "in_progress" or .status == "waiting" or .status == "requested" or .status == "pending"))] | length' \
      2>/dev/null \
      || printf '0'
  }

  _pr_agent_recent_trigger_comment_created_at() {
    local trigger_reuse_window="${PR_AGENT_TRIGGER_REUSE_WINDOW_SECONDS:-$max_wait}"

    case "$trigger_reuse_window" in
      ''|*[!0-9]*)
        trigger_reuse_window="$max_wait"
        ;;
    esac

    gh api "repos/$repo/issues/$pr_number/comments" --paginate \
      | jq -rs --arg body "$trigger_body" --arg since "$since_iso" --argjson reuse_window "$trigger_reuse_window" '
          add // []
          | [.[]
             | . as $comment
             | (($comment.created_at // $comment.updated_at // "") | fromdateiso8601?) as $trigger_time
             | select(
                 ((.body // "") == $body) and
                 ((.created_at // .updated_at // "") > $since) and
                 ($trigger_time != null) and
                 ((now - $trigger_time) <= $reuse_window)
               )
            ]
          | sort_by(.created_at // .updated_at)
          | last
          | .created_at // .updated_at // ""
        '
  }

  _pr_agent_trigger_already_pending() {
    local active_check_count
    local recent_trigger_created_at

    active_check_count="$(_pr_agent_active_review_check_count)"
    if [ "${active_check_count:-0}" -gt 0 ] 2>/dev/null; then
      print_kv PR_AGENT_TRIGGER_SKIPPED active_review_in_progress
      print_kv PR_AGENT_ACTIVE_CHECK_COUNT "$active_check_count"
      return 0
    fi

    recent_trigger_created_at="$(_pr_agent_recent_trigger_comment_created_at)"
    if [ -n "$recent_trigger_created_at" ]; then
      print_kv PR_AGENT_TRIGGER_SKIPPED recent_review_trigger
      print_kv PR_AGENT_TRIGGER_COMMENT_CREATED_AT "$recent_trigger_created_at"
      return 0
    fi

    return 1
  }

  _pr_agent_trigger_review() {
    local trigger_response

    if ! trigger_response="$(gh api -X POST "repos/$repo/issues/$pr_number/comments" -f body="$trigger_body" 2>/dev/null)"; then
      return 1
    fi
    if [ -n "$trigger_response" ]; then
      local trigger_created_at
      trigger_created_at="$(printf '%s\n' "$trigger_response" | jq -r '.created_at // empty' 2>/dev/null || true)"
      if [ -n "$trigger_created_at" ]; then
        print_kv PR_AGENT_TRIGGER_COMMENT_CREATED_AT "$trigger_created_at"
      fi
    fi
    print_kv PR_AGENT_TRIGGER_COMMENT "$trigger_body"
    return 0
  }

  # Extract <strong>LABEL</strong> tokens from the "Recommended focus areas for
  # review" section of a PR-Agent comment body.
  # Returns newline-delimited label strings (empty when section is absent or
  # yields no tokens). Shared by _pr_agent_extract_advisory_labels and
  # _pr_agent_classify to avoid duplicating the awk/grep/sed pipeline.
  _pr_agent_extract_focus_labels() {
    local body="$1"
    if ! printf '%s\n' "$body" | grep -qF "Recommended focus areas for review"; then
      return
    fi
    printf '%s\n' "$body" \
      | awk '/Recommended focus areas for review/{found=1; next}
             found && /^[[:space:]]*(\*\*|<\/td>|<tr>)|^---$/{found=0}
             found{print}' \
      | grep -oE '<strong>[^<]+</strong>' \
      | sed 's|<strong>||g;s|</strong>||g;s|^[[:space:]]*||;s|[[:space:]]*$||' \
      || true
  }

  # Extract advisory (non-blocking) labels from a PR-Agent comment body.
  # Outputs labels pipe-delimited (|) for safe single-line transport through
  # print_kv. Only labels that are NOT in the hard-blocker set are returned.
  # Returns empty string when body has no "Recommended focus areas for review"
  # section, or when all labels are blocking (handled by _pr_agent_classify).
  _pr_agent_extract_advisory_labels() {
    local body="$1"
    local label label_lower advisory_labels=""
    local labels
    labels="$(_pr_agent_extract_focus_labels "$body")"
    if [ -n "$labels" ]; then
      while IFS= read -r label; do
        [ -z "$label" ] && continue
        label_lower="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')"
        case "$label_lower" in
          critical|"must fix"|"breaking change"|"security concern"|"api change"|"backward compatibility")
            # Hard-blocker — skip; these are handled by _pr_agent_classify as needs_fixes.
            ;;
          *)
            if [ -n "$advisory_labels" ]; then
              advisory_labels="${advisory_labels}|${label}"
            else
              advisory_labels="$label"
            fi
            ;;
        esac
      done <<_PR_AGENT_ADVISORY_LABELS_
$labels
_PR_AGENT_ADVISORY_LABELS_
    fi
    printf '%s' "$advisory_labels"
  }

  # Returns pipe-delimited labels that match "possible issue" (case-insensitive).
  # Input:  pipe-delimited advisory labels string (e.g. "Possible Issue|Edge Case")
  # Output: pipe-delimited matching labels, or empty string.
  _extract_possible_issue_labels() {
    local advisory="$1"
    local result=""
    local label label_lower
    local _labels_normalized
    _labels_normalized="$(printf '%s' "$advisory" | tr '|' '\n')"
    while IFS= read -r label; do
      [ -z "$label" ] && continue
      # Trim leading and trailing whitespace before comparing (defensive — labels
      # from _pr_agent_extract_advisory_labels are already trimmed by sed, but
      # callers may pass labels with surrounding spaces).
      label="${label#"${label%%[![:space:]]*}"}"
      label="${label%"${label##*[![:space:]]}"}"
      [ -z "$label" ] && continue
      label_lower="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')"
      if [ "$label_lower" = "possible issue" ]; then
        if [ -n "$result" ]; then
          result="${result}|${label}"
        else
          result="$label"
        fi
      fi
    done <<_EXTRACT_POSSIBLE_ISSUE_LABELS_
$_labels_normalized
_EXTRACT_POSSIBLE_ISSUE_LABELS_
    printf '%s' "$result"
  }

  # Evaluate "Possible Issue" advisory labels found in a PR-Agent clean result.
  # "Possible Issue" findings are always treated as acknowledged without dispatching
  # a code-reviewer agent. In practice these findings have never been real blockers
  # for this repo type; the dispatch loop caused fix-round spirals (issue #511 pattern).
  # Returns:
  #   0  — always (no "Possible Issue" label found, or finding acknowledged immediately)
  run_pr_agent_possible_issue_evaluation() {
    local advisory_labels="$1"  # pipe-delimited, already extracted from comment
    # comment_body ($2), pr_number_eval ($3), branch_name_eval ($4) unused — kept for
    # signature compatibility with the call site.

    local possible_issue_labels
    possible_issue_labels="$(_extract_possible_issue_labels "$advisory_labels")"

    # Short-circuit: no "Possible Issue" label present.
    if [ -z "$possible_issue_labels" ]; then
      return 0
    fi

    # Always acknowledge immediately — do not dispatch a code-reviewer agent.
    print_kv POSSIBLE_ISSUE_EVAL_OUTCOME "acknowledged"
    return 0
  }

  _pr_agent_classify() {
    local body="$1"
    local label label_lower labels
    if [ -z "$body" ]; then
      printf 'none'
    elif printf '%s\n' "$body" | grep -q "No major issues detected"; then
      printf 'clean'
    elif printf '%s\n' "$body" | grep -q "Recommended focus areas for review"; then
      # Inspect every bold label in the section to classify.
      # Labels are lowercased before matching (case-insensitive — PR-Agent
      # sometimes varies capitalisation across runs).
      #   - Hard-blocker / security / compatibility labels → needs_fixes immediately
      #     (critical, must fix, breaking change, security concern,
      #      api change, backward compatibility)
      #   - All other labels → non-blocking (advisory).
      #     PR-Agent uses a wide variety of quality labels (Race Condition, Logic Error,
      #     Inconsistent Error Handling, Performance Concern, Possible Issue, etc.)
      #     that are advisory in nature. Security-critical concerns are always
      #     labelled one of the hard-blocker patterns above by PR-Agent.
      #   - If no labels are parseable → needs_fixes (unreadable format — conservative)
      labels="$(_pr_agent_extract_focus_labels "$body")"
      if [ -z "$labels" ]; then
        # No finding-label tokens found — treat as unknown/unreadable, be conservative.
        printf 'needs_fixes'
        return
      fi
      while IFS= read -r label; do
        [ -z "$label" ] && continue
        # Normalize to lowercase for case-insensitive matching.
        # PR-Agent occasionally varies label capitalisation across runs.
        label_lower="$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')"
        case "$label_lower" in
          critical|"must fix"|"breaking change"|"security concern"|"api change"|"backward compatibility")
            # Hard-blocker or security/compatibility concern — block immediately.
            printf 'needs_fixes'
            return
            ;;
          *)
            # All other labels are treated as advisory-only (non-blocking).
            # PR-Agent uses a wide variety of quality/style labels (Race Condition,
            # Logic Error, Inconsistent Error Handling, Performance Concern, etc.)
            # that represent code-quality suggestions, not security/breaking issues.
            # Security-critical concerns are always separately labelled one of the
            # hard-blocker patterns above.
            ;;
        esac
      done <<_PR_AGENT_LABELS_
$labels
_PR_AGENT_LABELS_
      # No hard-blocker label was found — all labels are advisory.
      printf 'clean'
    else
      printf 'escalate'
    fi
  }

  # --- Phase 1: Check for an existing PR-Agent summary comment on this HEAD ---
  comment_body="$(_pr_agent_latest_comment strict_sha)"
  local verdict
  verdict="$(_pr_agent_classify "$comment_body")"

  case "$verdict" in
    clean)
      local _advisory_labels _comment_url _advisory_entry _eval_status
      _advisory_labels="$(_pr_agent_extract_advisory_labels "$comment_body")"
      if [ -n "$_advisory_labels" ]; then
        _comment_url="$(_pr_agent_latest_comment_url strict_sha)"
        _advisory_entry="${_advisory_labels}@@@${_comment_url}"
      else
        _advisory_entry=""
      fi
      # Evaluate any "Possible Issue" advisory labels before emitting clean.
      _eval_status=0
      run_pr_agent_possible_issue_evaluation \
        "$_advisory_labels" "$comment_body" "$pr_number" "$branch_name" || _eval_status=$?
      if [ "$_eval_status" -eq 3 ]; then
        # Fix was pushed — signal to caller to re-run the loop on the new HEAD.
        print_kv RESULT needs_rerun
        print_kv PLATFORM "$platform"
        print_kv PR_NUMBER "$pr_number"
        print_kv BRANCH "$branch_name"
        print_kv REVIEW_COMMENT_ID ""
        print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
        print_kv COMMENT_COUNT 0
        print_kv BLOCKING_COUNT 0
        print_kv SUGGESTION_COUNT 0
        [ -n "$_advisory_entry" ] && print_kv ADVISORY_LABELS "$_advisory_entry"
        return 3
      fi
      print_kv RESULT clean
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      [ -n "$_advisory_entry" ] && print_kv ADVISORY_LABELS "$_advisory_entry"
      return 0
      ;;
    needs_fixes)
      print_kv RESULT needs_fixes
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REASON existing_findings
      print_kv COMMENT_COUNT 1
      print_kv BLOCKING_COUNT 1
      print_kv SUGGESTION_COUNT 0
      return 1
      ;;
    escalate)
      print_kv RESULT escalate
      print_kv REASON pr_agent_ambiguous_review
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 2
      ;;
  esac

  if ! _pr_agent_trigger_already_pending && ! _pr_agent_trigger_review; then
    print_kv RESULT escalate
    print_kv REASON pr_agent_trigger_failed
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID ""
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT 0
    print_kv BLOCKING_COUNT 0
    print_kv SUGGESTION_COUNT 0
    return 2
  fi

  # --- Phase 2: Poll until PR-Agent posts its summary comment ---
  while :; do
    comment_body="$(_pr_agent_latest_comment recent_or_sha)"
    verdict="$(_pr_agent_classify "$comment_body")"

    if [ "$verdict" != "none" ]; then
      break
    fi

    if [ "$elapsed" -ge "$max_wait" ]; then
      print_kv RESULT skipped
      print_kv REASON no_review
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 0
    fi

    _interruptible_sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
  done

  # --- Phase 3: Classify the comment body ---
  case "$verdict" in
    clean)
      local _advisory_labels _comment_url _advisory_entry _eval_status
      _advisory_labels="$(_pr_agent_extract_advisory_labels "$comment_body")"
      if [ -n "$_advisory_labels" ]; then
        _comment_url="$(_pr_agent_latest_comment_url recent_or_sha)"
        _advisory_entry="${_advisory_labels}@@@${_comment_url}"
      else
        _advisory_entry=""
      fi
      # Evaluate any "Possible Issue" advisory labels before emitting clean.
      _eval_status=0
      run_pr_agent_possible_issue_evaluation \
        "$_advisory_labels" "$comment_body" "$pr_number" "$branch_name" || _eval_status=$?
      if [ "$_eval_status" -eq 3 ]; then
        # Fix was pushed — signal to caller to re-run the loop on the new HEAD.
        print_kv RESULT needs_rerun
        print_kv PLATFORM "$platform"
        print_kv PR_NUMBER "$pr_number"
        print_kv BRANCH "$branch_name"
        print_kv REVIEW_COMMENT_ID ""
        print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
        print_kv COMMENT_COUNT 0
        print_kv BLOCKING_COUNT 0
        print_kv SUGGESTION_COUNT 0
        [ -n "$_advisory_entry" ] && print_kv ADVISORY_LABELS "$_advisory_entry"
        return 3
      fi
      print_kv RESULT clean
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      [ -n "$_advisory_entry" ] && print_kv ADVISORY_LABELS "$_advisory_entry"
      return 0
      ;;
    needs_fixes)
      print_kv RESULT needs_fixes
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REASON existing_findings
      print_kv COMMENT_COUNT 1
      print_kv BLOCKING_COUNT 1
      print_kv SUGGESTION_COUNT 0
      return 1
      ;;
    *)
      print_kv RESULT escalate
      print_kv REASON pr_agent_ambiguous_review
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 2
      ;;
  esac
}

check_unreplied_rest_comments() {
  # Count CodeRabbit root review comments that have received no human (non-bot) reply.
  # "Root" means in_reply_to_id == null (the original comment, not a reply).
  #
  # Unlike check_unresolved_threads (GraphQL reviewThreads), this uses the REST
  # pulls-comments endpoint which includes outside-diff comments (line == null /
  # "LNone" in the GitHub UI). These outside-diff comments never create proper
  # GitHub review threads and are therefore invisible to the GraphQL query, but
  # they appear in the GitHub PR page as unresolved findings that reviewers can see.
  #
  # A root comment is considered "replied" when at least one reply comment exists
  # whose author is NOT the CodeRabbit bot (i.e., a human or agent acknowledgment).
  # CodeRabbit's own auto-acknowledgment replies do not count.
  # Comments containing "✅ Addressed" in the body are also excluded (self-resolved).
  #
  # Root REST comments whose corresponding GraphQL review thread is already resolved
  # (isResolved=true) are also excluded. This prevents false-positive "unreplied"
  # counts when a reviewer resolves a thread via the GitHub UI without adding a reply:
  # the GraphQL isResolved flag reflects the true resolved state, so any REST comment
  # that belongs to an already-resolved thread must not block the review loop.
  # The caller supplies the set of resolved root comment database IDs via $4.
  #
  # Arguments:
  #   $1  pr_number              - PR number (integer)
  #   $2  repo                   - "owner/repo" slug
  #   $3  bot_login              - Full bot login including [bot] suffix (e.g. "coderabbitai[bot]")
  #                                REST API returns the full login; unlike GraphQL, no stripping needed.
  #   $4  resolved_ids_json      - (optional) JSON array of integer database IDs for root comments
  #                                whose GraphQL thread is already resolved (isResolved=true).
  #                                Pass "[]" or omit to skip this filter.
  #
  # Prints the count of unreplied root CodeRabbit comments on stdout.
  # Exit codes: 0 = success, 3 = REST API failure.
  local pr_number="$1"
  local repo="$2"
  local bot_login="$3"
  local resolved_ids_json="${4:-[]}"

  local result
  result="$(
    gh api "repos/$repo/pulls/$pr_number/comments" --paginate 2>/dev/null \
    | jq -s --arg bot "$bot_login" --argjson resolved_ids "$resolved_ids_json" '
        # gh api --paginate | jq -s produces [[page1_items], [page2_items], ...].
        # Use .[][] to flatten pages before selecting individual comment objects.
        #
        # Build the set of root-comment IDs that have received a human (non-bot) reply.
        # Exclude the primary bot login AND any other GitHub bot accounts (login ends with "[bot]").
        (
          [.[][] | select(
            .in_reply_to_id != null and
            .user.login != $bot and
            (.user.login | test("\\[bot\\]$") | not)
          ) | .in_reply_to_id] | unique
        ) as $human_replied_ids
        # Count root CR comments that have NOT been acknowledged by a human reply,
        # whose body does not self-resolve with "✅ Addressed", and whose GraphQL
        # review thread has not already been resolved (isResolved=true).
        | [.[][] | select(
            .user.login == $bot and
            .in_reply_to_id == null and
            ((.body // "") | test("✅ Addressed") | not)
          ) | select(
            .id as $id |
            ($human_replied_ids | index($id)) == null
          ) | select(
            .id as $id |
            ($resolved_ids | index($id)) == null
          )] | length
      '
  )" || {
    echo "WARN: check_unreplied_rest_comments: REST query failed for PR #$pr_number" >&2
    return 3
  }

  printf '%d\n' "${result:-0}"
}

# Newline-delimited JSON objects {path,line,body,commit_id} for unreplied
# CodeRabbit REST root comments (outside-diff supplement). Exit 3 on API failure.
_unreplied_rest_blocking_comment_json_lines() {
  local pr_number="$1"
  local repo="$2"
  local bot_login="$3"
  local resolved_ids_json="${4:-[]}"

  gh api "repos/$repo/pulls/$pr_number/comments" --paginate 2>/dev/null \
    | jq -rs --arg bot "$bot_login" --argjson resolved_ids "$resolved_ids_json" '
        (
          [.[][] | select(
            .in_reply_to_id != null and
            .user.login != $bot and
            (.user.login | test("\\[bot\\]$") | not)
          ) | .in_reply_to_id] | unique
        ) as $human_replied_ids
        | [.[][] | select(
            .user.login == $bot and
            .in_reply_to_id == null and
            ((.body // "") | test("✅ Addressed") | not)
          ) | select(
            .id as $id |
            ($human_replied_ids | index($id)) == null
          ) | select(
            .id as $id |
            ($resolved_ids | index($id)) == null
          ) | {
              path: (.path // ""),
              line: (.line // .original_line // 0),
              body: (.body // ""),
              commit_id: (.commit_id // "")
            }]
        | .[] | @json
      ' 2>/dev/null || return 3
}

# Emit BLOCKING_<n>_PATH/LINE/BODY and REVIEWED_HEAD from unreplied REST comments.
reviewer_loop_print_blocking_from_unreplied_rest_comments() {
  local pr_number="$1"
  local repo="$2"
  local bot_login="$3"
  local resolved_ids_json="${4:-[]}"
  local blocking_file idx=0 blocking_json path line body title

  blocking_file="$(mktemp)"
  if ! _unreplied_rest_blocking_comment_json_lines \
      "$pr_number" "$repo" "$bot_login" "$resolved_ids_json" >"$blocking_file"; then
    rm -f "$blocking_file"
    return 3
  fi

  while IFS= read -r blocking_json; do
    [ -z "${blocking_json:-}" ] && continue
    idx=$((idx + 1))
    path="$(printf '%s\n' "$blocking_json" | jq -r '.path // ""')"
    line="$(printf '%s\n' "$blocking_json" | jq -r '.line // 0')"
    body="$(printf '%s\n' "$blocking_json" | jq -r '.body // ""')"
    title="$(printf '%s\n' "$body" | sed -n 's/^### //p;q')"
    if [ -z "$title" ]; then
      title="$(printf '%.120s' "$(printf '%s\n' "$body" | tr '\n' ' ')")"
    fi
    print_kv "BLOCKING_${idx}_PATH" "${path:-unknown}"
    print_kv "BLOCKING_${idx}_LINE" "$line"
    print_kv_escaped "BLOCKING_${idx}_BODY" "$title"
  done < "$blocking_file"

  reviewer_loop_print_reviewed_head_from_json_lines < "$blocking_file"
  rm -f "$blocking_file"
  return 0
}

auto_reply_unreplied_rest_comments() {
  # Post a brief acknowledgement reply to each unreplied CodeRabbit REST review
  # comment that has no corresponding resolved GraphQL thread (i.e., outside-diff
  # comments with no GraphQL thread representation).  Called by
  # coderabbit_thread_gate_clean after the GraphQL thread audit passes but the
  # REST supplement still reports unreplied outside-diff comments.  Replying
  # satisfies the check_unreplied_rest_comments gate so the loop can advance to
  # RESULT=clean without requiring manual intervention.
  #
  # Arguments:
  #   $1  pr_number              - PR number (integer)
  #   $2  repo                   - "owner/repo" slug
  #   $3  bot_login              - Full bot login including [bot] suffix
  #   $4  resolved_ids_json      - JSON array of already-resolved root comment IDs
  #
  # Prints the number of replies successfully posted on stdout.
  # Exit codes: 0 = all replies posted (or nothing to reply to),
  #             1 = one or more replies failed (partial — some may have been posted).
  local pr_number="$1"
  local repo="$2"
  local bot_login="$3"
  local resolved_ids_json="${4:-[]}"
  # This reply is an automated acknowledgement only — it does not assert that the
  # specific comment content was addressed. It is posted solely to satisfy the
  # check_unreplied_rest_comments gate for outside-diff comments that have no
  # corresponding GraphQL review thread and therefore cannot be resolved via the
  # normal thread-resolution mechanism. All GraphQL review threads have already
  # been verified resolved before this function is called.
  local reply_body="Acknowledged — outside-diff comment noted. All review threads for this PR have been resolved via the standard review process."

  # Fetch IDs of root CodeRabbit comments that need a reply (same filter logic
  # as check_unreplied_rest_comments, but returns IDs instead of a count).
  local unreplied_ids
  unreplied_ids="$(
    gh api "repos/$repo/pulls/$pr_number/comments" --paginate 2>/dev/null \
    | jq -s --arg bot "$bot_login" --argjson resolved_ids "$resolved_ids_json" '
        (
          [.[][] | select(
            .in_reply_to_id != null and
            .user.login != $bot and
            (.user.login | test("\\[bot\\]$") | not)
          ) | .in_reply_to_id] | unique
        ) as $human_replied_ids
        | [.[][] | select(
            .user.login == $bot and
            .in_reply_to_id == null and
            ((.body // "") | test("✅ Addressed") | not)
          ) | select(
            .id as $id |
            ($human_replied_ids | index($id)) == null
          ) | select(
            .id as $id |
            ($resolved_ids | index($id)) == null
          ) | .id]
      '
  )" || {
    echo "WARN: auto_reply_unreplied_rest_comments: REST query failed for PR #$pr_number" >&2
    return 1
  }

  local reply_count=0
  local fail_count=0
  local comment_id
  while IFS= read -r comment_id; do
    [ -z "$comment_id" ] && continue
    local reply_json
    reply_json="$(jq -n --arg body "$reply_body" '{"body": $body}')"
    if printf '%s' "$reply_json" \
         | gh api "repos/$repo/pulls/$pr_number/comments/$comment_id/replies" \
             --method POST \
             --input - \
             --silent > /dev/null 2>&1; then
      reply_count=$((reply_count + 1))
      echo "INFO: auto-replied to REST comment $comment_id on PR #$pr_number" >&2
    else
      fail_count=$((fail_count + 1))
      echo "WARN: auto_reply_unreplied_rest_comments: failed to reply to comment $comment_id on PR #$pr_number" >&2
    fi
  done < <(printf '%s\n' "$unreplied_ids" | jq -r '.[]')

  printf '%d\n' "$reply_count"
  [ "$fail_count" -eq 0 ]
}

get_resolved_thread_comment_ids() {
  # Fetch the database IDs of root comments from already-resolved GraphQL review
  # threads on a PR. These IDs are used by check_unreplied_rest_comments to skip
  # REST comments whose corresponding thread was resolved via the GitHub UI
  # (isResolved=true), even when no non-bot reply exists on that thread.
  #
  # A thread's "root comment" is its first comment; its databaseId matches the
  # REST pulls-comments API .id field, enabling cross-API correlation.
  #
  # Arguments:
  #   $1  pr_number      - PR number (integer)
  #   $2  repo           - "owner/repo" slug
  #   $3  graphql_bot_login - Bot login WITHOUT [bot] suffix (as returned by GraphQL API)
  #
  # Prints a compact JSON array of integer IDs on stdout, e.g. [123456, 789012].
  # Prints "[]" when no resolved threads exist or on any API failure (non-fatal).
  # Exit codes: always 0 (failures are non-fatal; caller receives "[]").
  local pr_number="$1"
  local repo="$2"
  local graphql_bot_login="$3"

  local owner repo_name
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

  # GraphQL query: paginate reviewThreads, fetch first comment databaseId per thread.
  # Select only resolved threads whose first comment was authored by the bot.
  local graphql_query
  graphql_query='query($owner:String!,$repo:String!,$pr:Int!,$cursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$pr){reviewThreads(first:100,after:$cursor){pageInfo{hasNextPage endCursor}nodes{isResolved comments(first:1){nodes{databaseId author{login}}}}}}}}'

  local all_ids="[]"
  local cursor=""
  local has_next_page="true"
  local page=0
  local max_pages=10

  while [ "$has_next_page" = "true" ]; do
    page=$((page + 1))
    if [ "$page" -gt "$max_pages" ]; then
      echo "WARN: get_resolved_thread_comment_ids: exceeded $max_pages pages for PR #$pr_number — returning partial results" >&2
      break
    fi

    local result
    if [ -n "$cursor" ]; then
      result="$(gh api graphql \
        -f query="$graphql_query" \
        -f owner="$owner" -f repo="$repo_name" -F pr="$pr_number" -f cursor="$cursor" \
        --jq '.data.repository.pullRequest.reviewThreads' 2>/dev/null)" || {
        echo "WARN: get_resolved_thread_comment_ids: GraphQL query failed for PR #$pr_number — returning partial results" >&2
        break
      }
    else
      result="$(gh api graphql \
        -f query="$graphql_query" \
        -f owner="$owner" -f repo="$repo_name" -F pr="$pr_number" \
        --jq '.data.repository.pullRequest.reviewThreads' 2>/dev/null)" || {
        echo "WARN: get_resolved_thread_comment_ids: GraphQL query failed for PR #$pr_number — returning partial results" >&2
        break
      }
    fi

    has_next_page="$(printf '%s\n' "$result" | jq -r '.pageInfo.hasNextPage')"
    cursor="$(printf '%s\n' "$result" | jq -r '.pageInfo.endCursor // empty')"
    if [ "$has_next_page" = "true" ] && [ -z "$cursor" ]; then
      echo "WARN: get_resolved_thread_comment_ids: hasNextPage=true but endCursor is empty for PR #$pr_number — returning partial results" >&2
      break
    fi

    # Accumulate databaseIds of root comments from resolved bot-authored threads.
    local page_ids
    page_ids="$(printf '%s\n' "$result" \
      | jq --arg bot "$graphql_bot_login" '
          [.nodes[] |
            select(.isResolved == true) |
            select(.comments.nodes[0].author.login == $bot) |
            .comments.nodes[0].databaseId
          ]
        ')" || continue

    all_ids="$(printf '%s\n%s\n' "$all_ids" "$page_ids" \
      | jq -s 'add | unique')" || continue
  done

  printf '%s\n' "$all_ids"
}

is_coderabbit_blocking() {
  # Returns 0 (true) if the comment body contains a blocking severity marker.
  # Critical (🔴) and Major (🟠) are blocking; Minor (🟡) and Low (🟢) are not.
  # However, CodeRabbit appends "✅ Addressed in commit ..." at the end of the
  # comment body when the finding has been fixed in a subsequent commit. These
  # resolved findings are NOT blocking even if they still contain 🔴/🟠 markers.
  local body="$1"
  if printf '%s\n' "$body" | grep -q "✅ Addressed"; then return 1; fi
  if printf '%s\n' "$body" | grep -q "🔴"; then return 0; fi
  if printf '%s\n' "$body" | grep -q "🟠"; then return 0; fi
  return 1
}

# Returns the validated THREAD_AUDIT_MAX_RETRIES value (a positive integer).
# If the environment variable is unset, empty, non-integer, or non-positive,
# emits a WARN on stderr and returns the default (3).
thread_audit_max_retries_value() {
  local value="${THREAD_AUDIT_MAX_RETRIES:-3}"
  if ! printf '%s' "$value" | grep -qE '^[0-9]+$' || [ "$value" -le 0 ] 2>/dev/null; then
    echo "WARN: THREAD_AUDIT_MAX_RETRIES must be a positive integer; defaulting to 3" >&2
    value=3
  fi
  printf '%s\n' "$value"
}

# Returns 0 when CodeRabbit may treat the PR as thread-clean for this pass.
# Returns 1 after emitting RESULT=needs_fixes (unresolved GraphQL threads).
# Returns 2 after emitting RESULT=escalate (thread page cap exceeded or
#   GraphQL failure after all retries exhausted).
# On transient GraphQL failure (exit 3 from check_unresolved_threads), retries
# up to THREAD_AUDIT_MAX_RETRIES times before escalating. Never returns 0 when
# the thread audit could not be completed — RESULT=clean is only emitted by the
# caller once this function returns 0 with a confirmed zero unresolved count.
coderabbit_thread_gate_clean() {
  local pr_number="$1" repo="$2" bot_login="$3" branch_name="$4"
  local platform="coderabbit"
  local out st
  local thread_audit_max_retries
  thread_audit_max_retries="$(thread_audit_max_retries_value)"
  local thread_audit_attempt=0
  # REST API endpoints (e.g. /pulls/{n}/reviews, /issues/{n}/comments) return
  # bot logins WITH the "[bot]" suffix (e.g. "coderabbit-ai[bot]").
  # GraphQL API returns bot logins WITHOUT the "[bot]" suffix
  # (e.g. "coderabbit-ai"). Strip it here so check_unresolved_threads,
  # which queries GraphQL, compares against the correct login form.
  local graphql_bot_login="${bot_login%\[bot\]}"

  # check_unresolved_threads re-enables errexit internally; capture and restore
  # shellopts so set -e does not leak into run_coderabbit_review (dead rc capture).
  local prev_errexit
  prev_errexit="$(set +o | grep errexit)"

  while true; do
    thread_audit_attempt=$((thread_audit_attempt + 1))
    set +e
    # mode=strict: this gate decides RESULT=clean for CodeRabbit and must
    # never be relaxed by a reply-without-resolve (see check_unresolved_threads).
    out="$(check_unresolved_threads "$pr_number" "$repo" strict "$graphql_bot_login")"
    st=$?
    eval "$prev_errexit"

    if [ "$st" -eq 2 ]; then
      echo "WARN: check_unresolved_threads exceeded page cap for PR #$pr_number (CodeRabbit pass)" >&2
      print_kv RESULT escalate
      print_kv REASON unresolved_thread_check_incomplete
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 2
    fi

    if [ "$st" -eq 3 ]; then
      if [ "$thread_audit_attempt" -le "$thread_audit_max_retries" ]; then
        echo "WARN: check_unresolved_threads GraphQL failure for PR #$pr_number (CodeRabbit pass, attempt $thread_audit_attempt/$thread_audit_max_retries) — retrying" >&2
        sleep 5
        continue
      fi
      echo "ERROR: check_unresolved_threads GraphQL failure for PR #$pr_number (CodeRabbit pass) — all $thread_audit_attempt attempts ($thread_audit_max_retries retries) failed; escalating" >&2
      print_kv RESULT escalate
      print_kv REASON review_thread_audit_failed
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 2
    fi

    if [ "$st" -ne 0 ]; then
      echo "ERROR: check_unresolved_threads unexpected exit $st for PR #$pr_number (CodeRabbit pass) — escalating" >&2
      print_kv RESULT escalate
      print_kv REASON review_thread_audit_failed
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 2
    fi

    break
  done

  if [ "${out:-0}" -gt 0 ]; then
    reviewer_loop_print_reviewed_head_from_unresolved_bot_threads "$pr_number" "$repo" "$graphql_bot_login"
    print_kv RESULT needs_fixes
    print_kv REASON coderabbit_unresolved_review_threads
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID ""
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT "$out"
    print_kv BLOCKING_COUNT "$out"
    print_kv SUGGESTION_COUNT 0
    print_kv UNRESOLVED_THREAD_COUNT "$out"
    return 1
  fi

  # --- Supplementary REST check for outside-diff comments ---
  # GraphQL reviewThreads only sees comments anchored to diff lines. CodeRabbit
  # sometimes posts comments on lines outside the PR diff (line == null); these
  # never create proper GitHub review threads and are invisible to the GraphQL
  # query above, but they ARE visible in the GitHub PR UI as unresolved findings.
  # Detect them via the REST pulls-comments endpoint and require a human reply
  # before allowing RESULT=clean.
  #
  # Fetch the database IDs of root comments from already-resolved GraphQL threads
  # so that check_unreplied_rest_comments can skip them. When a reviewer resolves
  # a thread via the GitHub UI (isResolved=true), the REST comment is still present
  # but the thread is already resolved — it must not block the review loop.
  local resolved_ids_json
  set +e
  resolved_ids_json="$(get_resolved_thread_comment_ids "$pr_number" "$repo" "$graphql_bot_login")"
  eval "$prev_errexit"
  resolved_ids_json="${resolved_ids_json:-[]}"

  local rest_unreplied_raw rest_check_st
  set +e
  rest_unreplied_raw="$(check_unreplied_rest_comments "$pr_number" "$repo" "$bot_login" "$resolved_ids_json")"
  rest_check_st=$?
  eval "$prev_errexit"

  if [ "$rest_check_st" -eq 0 ] && [ "${rest_unreplied_raw:-0}" -gt 0 ]; then
    # All GraphQL threads are resolved, but the REST supplement still sees
    # unreplied outside-diff comments.  Auto-reply to each one so the gate
    # can advance without requiring manual intervention.
    echo "INFO: ${rest_unreplied_raw} unreplied CodeRabbit REST comment(s) on PR #$pr_number — auto-replying" >&2
    local auto_reply_st auto_replied_count
    set +e
    auto_replied_count="$(auto_reply_unreplied_rest_comments "$pr_number" "$repo" "$bot_login" "$resolved_ids_json")"
    auto_reply_st=$?
    eval "$prev_errexit"
    echo "INFO: auto-replied to ${auto_replied_count:-0} REST comment(s) on PR #$pr_number" >&2

    if [ "$auto_reply_st" -ne 0 ]; then
      # One or more replies failed; fall back to needs_fixes so the agent can
      # address the remaining comments manually.
      echo "WARN: auto-reply failed for one or more REST comments on PR #$pr_number — returning needs_fixes" >&2
      reviewer_loop_print_blocking_from_unreplied_rest_comments \
        "$pr_number" "$repo" "$bot_login" "$resolved_ids_json" || true
      print_kv RESULT needs_fixes
      print_kv REASON coderabbit_unreplied_rest_comments
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT "${rest_unreplied_raw:-0}"
      print_kv BLOCKING_COUNT "${rest_unreplied_raw:-0}"
      print_kv SUGGESTION_COUNT 0
      print_kv UNRESOLVED_THREAD_COUNT "${rest_unreplied_raw:-0}"
      return 1
    fi
    # Re-validate the gate after auto-replies to confirm the count is now zero.
    # A partial success from auto_reply_unreplied_rest_comments (exit 0 but some
    # replies silently dropped) would otherwise cause a false clean return.
    local recheck_raw recheck_st
    set +e
    recheck_raw="$(check_unreplied_rest_comments "$pr_number" "$repo" "$bot_login" "$resolved_ids_json")"
    recheck_st=$?
    eval "$prev_errexit"
    if [ "$recheck_st" -ne 0 ]; then
      # Re-check REST query failed — cannot confirm gate is clean; treat as
      # needs_fixes so the agent re-inspects rather than claiming false clean.
      echo "WARN: REST re-check failed (exit $recheck_st) after auto-reply on PR #$pr_number — returning needs_fixes" >&2
      reviewer_loop_print_blocking_from_unreplied_rest_comments \
        "$pr_number" "$repo" "$bot_login" "$resolved_ids_json" || true
      print_kv RESULT needs_fixes
      print_kv REASON coderabbit_unreplied_rest_comments
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT "${rest_unreplied_raw:-0}"
      print_kv BLOCKING_COUNT "${rest_unreplied_raw:-0}"
      print_kv SUGGESTION_COUNT 0
      print_kv UNRESOLVED_THREAD_COUNT "${rest_unreplied_raw:-0}"
      return 1
    fi
    if [ "${recheck_raw:-0}" -gt 0 ]; then
      echo "WARN: ${recheck_raw} unreplied REST comment(s) remain after auto-reply on PR #$pr_number — returning needs_fixes" >&2
      reviewer_loop_print_blocking_from_unreplied_rest_comments \
        "$pr_number" "$repo" "$bot_login" "$resolved_ids_json" || true
      print_kv RESULT needs_fixes
      print_kv REASON coderabbit_unreplied_rest_comments
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT "${recheck_raw:-0}"
      print_kv BLOCKING_COUNT "${recheck_raw:-0}"
      print_kv SUGGESTION_COUNT 0
      print_kv UNRESOLVED_THREAD_COUNT "${recheck_raw:-0}"
      return 1
    fi
    # Gate confirmed clean after auto-replies — fall through to return 0.
  fi
  if [ "$rest_check_st" -ne 0 ]; then
    # REST failure is non-fatal: the GraphQL thread check already passed.
    # Log the warning and allow RESULT=clean to proceed.
    echo "WARN: check_unreplied_rest_comments failed (exit $rest_check_st) for PR #$pr_number — skipping outside-diff supplement" >&2
  fi

  return 0
}

# Returns the count of CodeRabbit commit statuses for $head_sha on $repo that
# are genuinely successful — i.e., context matches "coderabbit" (case
# insensitive), the latest status per context has state == "success", AND the
# status description does not match a rate-limit / not-actually-reviewed
# pattern.
#
# Background (issue #1437): CodeRabbit can set a `success` commit status for
# branch-protection compatibility while its description explicitly states the
# review did not actually run. The confirmed real-world text (observed on
# lhpaul/personal-finances PR #33) is "Review limit reached ... Next review
# available in: N minutes" — note this does NOT contain the substring "rate
# limit", so matching only the existing test("rate.?limit"; "i") comment-marker
# regex used elsewhere in this script would miss it. The pattern below matches
# both: the generic "rate limit" phrasing (kept for consistency with the
# existing comment-marker regex, in case CodeRabbit also uses that wording in
# a status description) AND the confirmed "review limit" / "next review
# available" banner wording. Checking .state alone treats either case as a
# completed clean review — a false clean. Both coderabbit_status_success_fallback
# call sites in run_coderabbit_review use this helper so the description guard
# is applied identically at both sites.
#
# Deduplicates by context (keeping the latest entry per context via
# max_by(.updated_at)) before checking state/description, so a superseded
# status is not counted — same dedup pattern used before this fix existed.
coderabbit_success_status_count() {
  local repo="$1" head_sha="$2"
  # Validate arguments before the API call: a missing repo or head_sha would
  # otherwise build an invalid endpoint and fail inside the pipeline with an
  # unstructured shell error. Print "0" and return 0 (rather than a nonzero
  # exit) because both call sites assign this function's output directly via
  # `var="$(coderabbit_success_status_count ...)"` under `set -e` — a nonzero
  # return there aborts the entire reviewer-loop script immediately instead of
  # letting the caller's normal "no success status found" path run. Treating
  # invalid arguments as "no genuine success status found" is the same safe
  # default the rest of this function already falls back to on API failure.
  if [ -z "$repo" ] || [ -z "$head_sha" ]; then
    echo "ERROR: coderabbit_success_status_count requires non-empty repo and head_sha arguments (got repo='${repo:-}' head_sha='${head_sha:-}')" >&2
    printf '%s\n' 0
    return 0
  fi
  gh api "repos/$repo/commits/$head_sha/statuses" --paginate \
    | jq -s '[.[].[] | select(
              (.context // "" | ascii_downcase | test("coderabbit"))
            )]
            | group_by(.context) | map(max_by(.updated_at))
            | map(select(
                .state == "success"
                and ((.description // "")
                     | test("rate.?limit|review limit|next review available"; "i")
                     | not)
              ))
            | length'
}

# coderabbit_no_trigger_timeout_default <max_wait>
#
# Computes the default silent-non-trigger fallback timeout (issue #1433):
# how long run_coderabbit_review waits with zero CodeRabbit activity before
# proactively posting "@coderabbitai review" (see the "Auto-retrigger: detect
# CodeRabbit silent non-trigger after push" block below).
#
# Background: the previous fixed default was 600 s, decoupled from max_wait.
# Two problems: (1) on the common default invocation (max_wait=1200 s), it
# burned up to 10 minutes of pure idle wait before nudging CodeRabbit — the
# exact "waited out CodeRabbit auto-trigger timeouts" latency reported in
# #1433 from the #1429/#1431 retrospective; (2) on short-max_wait
# invocations (e.g. the 180 s spec/*  and implementation-plan/* doc-branch
# default — see the "Branch-type-aware default timeout" section in --help),
# elapsed could never reach 600 before the outer max_wait timeout exits the
# loop, so the silent-non-trigger safety net never had a chance to fire at
# all on those branches.
#
# Fix: default to 180 s — the "give CodeRabbit time, then nudge" cadence
# CODERABBIT_RATE_LIMIT_WAIT originally shared. The two knobs have since
# diverged deliberately and must not be re-coupled: this one waits out a
# *silent* CodeRabbit (nothing posted at all), where 3 minutes is ample and a
# longer wait is pure idle latency, while CODERABBIT_RATE_LIMIT_WAIT waits out
# an *acknowledged* vendor quota block whose reset is hourly, so it is now
# sized in quarter-hours (see its declaration in run_coderabbit_review).
#
# Effective-timeout rule (piecewise, by max_wait):
#   - max_wait >= 360 s: effective = 180 s (the hardcoded default; the half-
#     max_wait cap below does not bind).
#   - 60 s <= max_wait < 360 s: effective = floor(max_wait / 2) (the cap
#     binds and is always < max_wait, so a subsequent poll cycle is
#     guaranteed to have room before the outer max_wait timeout).
#   - max_wait < 60 s: effective = max(30, floor(max_wait / 2)) — the 30 s
#     floor takes precedence over the halved cap in this range. For
#     max_wait <= ~30 s this can leave little or no room before the outer
#     timeout (the floor exists only so a pathologically small max_wait
#     still gets one nudge attempt rather than a zero-second window). This
#     repo never configures --max-wait below 180 s (the doc-branch default;
#     see PR_REVIEW_LOOP_DOC_MAX_WAIT in --help), so this range is a
#     defensive edge case, not a realistic operating point.
#
# This is purely a *timing* change: it does not touch, weaken, or bypass the
# coderabbit_success_status_count description guard (#1437) that prevents a
# rate-limited "success" commit status from being treated as a real clean
# review — that check runs unconditionally on whatever HEAD SHA state exists
# when it is reached, regardless of how quickly this function got there.
#
# Only used to compute the *default* — an explicit CODERABBIT_NO_TRIGGER_TIMEOUT
# env var override is honored as-is (uncapped) by the caller, matching how
# other env-var overrides in this script are treated.
coderabbit_no_trigger_timeout_default() {
  local max_wait="${1:-0}"
  local hardcoded_default=180
  local floor=30
  local effective="$hardcoded_default"
  if [[ "$max_wait" =~ ^[0-9]+$ ]] && [ "$((10#$max_wait))" -gt 0 ]; then
    # Force base-10 interpretation with the `10#` prefix: a caller-supplied
    # value with a leading zero (e.g. "080") passes the ^[0-9]+$ digit check
    # above but is otherwise parsed as octal by bash arithmetic expansion,
    # and "080" is not a valid octal literal (8 is not an octal digit) —
    # `$((080 / 2))` errors with "value too great for base" and aborts the
    # script under `set -euo pipefail`. See the
    # no_trigger_timeout_default_leading_zero_max_wait_normalized_base10 test.
    local half_max_wait
    half_max_wait=$((10#$max_wait / 2))
    if [ "$half_max_wait" -lt "$effective" ]; then
      effective="$half_max_wait"
    fi
  fi
  if [ "$effective" -lt "$floor" ]; then
    effective="$floor"
  fi
  printf '%s\n' "$effective"
}

# coderabbit_resolve_no_trigger_timeout <max_wait>
#
# Resolves the effective CODERABBIT_NO_TRIGGER_TIMEOUT for a given max_wait:
# honors an explicit CODERABBIT_NO_TRIGGER_TIMEOUT env var override (uncapped)
# when it is set and a valid positive integer, printing a WARN to stderr and
# falling back to coderabbit_no_trigger_timeout_default(<max_wait>) when it is
# set but invalid, or computing that default directly when it is unset.
#
# Extracted as its own function (rather than inlined in run_coderabbit_review)
# specifically so tests can exercise the production override-resolution path
# directly — including the env var precedence and validation-failure fallback
# — without needing to drive run_coderabbit_review's full polling loop.
coderabbit_resolve_no_trigger_timeout() {
  local max_wait="$1"
  local override="${CODERABBIT_NO_TRIGGER_TIMEOUT:-}"
  if [ -z "$override" ]; then
    coderabbit_no_trigger_timeout_default "$max_wait"
    return 0
  fi
  if ! [[ "$override" =~ ^[0-9]+$ ]] || [ "$((10#$override))" -le 0 ]; then
    local fallback
    fallback="$(coderabbit_no_trigger_timeout_default "$max_wait")"
    echo "WARN: CODERABBIT_NO_TRIGGER_TIMEOUT must be a positive integer; defaulting to ${fallback}" >&2
    printf '%s\n' "$fallback"
    return 0
  fi
  printf '%s\n' "$override"
}

# ---------------------------------------------------------------------------
# coderabbit_rate_limit_wait_seconds
#
# CodeRabbit states how long the caller must wait inside its rate-limit
# comment, e.g.
#
#     **Next included review available in 27 minutes.**
#
# Sizing the retry wait from that sentence rather than from a fixed constant is
# what lets a retry land when the vendor can actually answer. See issue #1579:
# measured on 2026-08-24 the org allowance was 1 review per hour, against which
# a fixed 4 x 900 s budget spends every retry inside a window that grants at
# most one review, then escalates at roughly the moment the review becomes
# available (PR #1589: four retries, four "Reviews resumed" acknowledgements,
# zero reviews, then RESULT=escalate REASON=rate_limit_max_retries).
#
# Args:
#   $1 - body of the newest CodeRabbit rate-limit comment (may be empty)
#   $2 - fallback wait in seconds, used when the sentence is absent or
#        unparseable. Vendor wording changes, so absence is never fatal.
#
# Prints the wait in seconds on stdout, always a positive integer.
#
# CODERABBIT_RATE_LIMIT_WAIT_BUFFER (default 30) is added to the stated window
# so the retry lands just after the vendor boundary rather than exactly on it.
# CODERABBIT_RATE_LIMIT_WAIT_MAX (default 3600) clamps the result so that a
# malformed or hostile "available in 100000 minutes" cannot park an unattended
# run for a day. Both are validated here: a non-numeric or non-positive
# override degrades to the documented default instead of yielding a zero wait
# (a zero wait would busy-spin the retry against the vendor).
coderabbit_rate_limit_wait_seconds() {
  local body="${1:-}" fallback="${2:-}"
  local buffer="${CODERABBIT_RATE_LIMIT_WAIT_BUFFER:-30}"
  local max_seconds="${CODERABBIT_RATE_LIMIT_WAIT_MAX:-3600}"

  case "$buffer" in
    '' | *[!0-9]*) buffer=30 ;;
  esac
  case "$max_seconds" in
    '' | *[!0-9]*) max_seconds=3600 ;;
  esac
  case "$fallback" in
    '' | *[!0-9]*) fallback="$CODERABBIT_RATE_LIMIT_WAIT_DEFAULT" ;;
  esac
  # Strip leading zeros from every digit-only override before it can reach an
  # arithmetic context: a digit-only string like "008" passes the checks above
  # unchanged, but $((...)) below reads a leading-zero literal as octal, and
  # "008" is not a valid octal literal (8 is not an octal digit) — an operator
  # override of CODERABBIT_RATE_LIMIT_WAIT_BUFFER=008 aborts the whole script
  # under `set -e` without this. Same idiom used below for the vendor-parsed
  # value, applied here to the three operator-supplied numbers instead.
  buffer="${buffer#"${buffer%%[!0]*}"}"
  [ -z "$buffer" ] && buffer=0
  max_seconds="${max_seconds#"${max_seconds%%[!0]*}"}"
  [ -z "$max_seconds" ] && max_seconds=0
  fallback="${fallback#"${fallback%%[!0]*}"}"
  [ -z "$fallback" ] && fallback=0
  if [ "$max_seconds" -le 0 ]; then
    max_seconds=3600
  fi
  if [ "$fallback" -le 0 ]; then
    fallback="$CODERABBIT_RATE_LIMIT_WAIT_DEFAULT"
  fi

  # Lowercase, then treat every run of non-alphanumeric bytes between the
  # fixed words as a separator. That absorbs markdown emphasis, line wraps and
  # the non-breaking spaces CodeRabbit sometimes emits, none of which the
  # vendor guarantees to keep stable, without having to enumerate them.
  local flat
  flat="$(printf '%s' "$body" | tr '[:upper:]' '[:lower:]' | tr '\n' ' ')"

  local parsed=""
  # CodeRabbit uses at least two wordings for the same fact, both observed on
  # 2026-08-24 within one hour:
  #
  #   "**Next included review available in 27 minutes.**"          (PR #1590)
  #   "Your next included review will be available in 7 minutes."  (PR #1588)
  #
  # So the gap between "included" and "available" cannot be assumed to be just
  # " review ". Allow a bounded run of non-digits there — bounded, not `*`, so
  # the match cannot reach across unrelated prose to a number elsewhere in the
  # comment. Requiring the word "included" keeps this off any other "available
  # in N minutes" sentence the vendor might add.
  if [[ "$flat" =~ included[^0-9]{0,40}available[^a-z0-9]*in[^a-z0-9]*([0-9]+)[^a-z0-9]*(second|minute|hour) ]]; then
    local value="${BASH_REMATCH[1]}" unit="${BASH_REMATCH[2]}"
    # Strip leading zeros before any arithmetic: bash reads "08" as an invalid
    # octal literal and aborts the whole script under `set -e`.
    value="${value#"${value%%[!0]*}"}"
    if [ -z "$value" ]; then
      value=0
    fi
    # More than six digits is not a real vendor window. Refuse to multiply it
    # rather than letting the product wrap a signed 64-bit integer negative.
    if [ "${#value}" -le 6 ]; then
      local multiplier=1
      case "$unit" in
        second) multiplier=1 ;;
        minute) multiplier=60 ;;
        hour) multiplier=3600 ;;
      esac
      parsed=$((value * multiplier + buffer))
    fi
  fi

  if [ -n "$parsed" ]; then
    if [ "$parsed" -gt "$max_seconds" ]; then
      parsed="$max_seconds"
    fi
    if [ "$parsed" -le 0 ]; then
      parsed=30
    fi
    printf '%s\n' "$parsed"
    return 0
  fi

  printf '%s\n' "$fallback"
}

# ---------------------------------------------------------------------------
# _iso8601_to_epoch
#
# Convert an ISO-8601 UTC timestamp ("2026-08-24T03:12:02Z", the form every
# GitHub REST timestamp uses) to seconds since the epoch. BSD date (macOS,
# where this is developed) needs `-j -f`; GNU date (Linux, where CI runs)
# needs `-d` and rejects `-j`. Try BSD first, fall back to GNU, and return
# non-zero rather than printing garbage if neither parses the input.
_iso8601_to_epoch() {
  local iso="${1:-}"
  [ -n "$iso" ] || return 1
  date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$iso" +%s 2>/dev/null && return 0
  date -u -d "$iso" +%s 2>/dev/null && return 0
  return 1
}

# ---------------------------------------------------------------------------
# coderabbit_rate_limit_comment_is_current
#
# Decide whether a CodeRabbit rate-limit comment still describes a live limit.
#
# This is the core of issue #1579. Detection previously asked only "does a
# rate-limit comment exist after the HEAD commit time", so a single stale reply
# suppressed every later trigger on that HEAD forever. Measured on PR #1575: a
# rate-limit comment at 16:06 was still being treated as live 21 hours later,
# with no CodeRabbit activity of any kind in between, and the loop waited out
# its whole retry budget without ever posting a fresh review request.
#
# A rate-limit comment announces its own expiry ("Next included review
# available in N minutes"), so the honest test is whether that window has
# passed — not how the comment's timestamp compares to the HEAD commit.
#
# Args:
#   $1 - comment body
#   $2 - comment created_at (ISO-8601 UTC)
#
# Returns 0 when the announced window has not yet elapsed (the limit is live
# and the caller should wait), 1 when it has (the comment is spent and must not
# suppress a fresh trigger).
#
# When the body states no window, CODERABBIT_RATE_LIMIT_STALE_AFTER (default
# 3600s, one vendor quota hour) bounds how long the comment stays believable.
# When the timestamp cannot be parsed at all the comment is reported as
# current: that preserves the previous behaviour exactly, so a date-parsing
# failure degrades to today's conservative wait rather than to spending a
# review attempt the caller may not have.
coderabbit_rate_limit_comment_is_current() {
  local body="${1:-}" created_at="${2:-}" last_trigger_iso="${3:-}"
  local stale_after="${CODERABBIT_RATE_LIMIT_STALE_AFTER:-3600}"

  case "$stale_after" in
    '' | *[!0-9]*) stale_after=3600 ;;
  esac
  # Strip leading zeros before any arithmetic context: a digit-only string like
  # "008" passes the check above, but bash reads it as an invalid octal literal
  # and aborts the script under `set -e`. Same guard as the other overrides —
  # this was the one that still lacked it.
  stale_after="${stale_after#"${stale_after%%[!0]*}"}"
  if [ -z "$stale_after" ]; then
    stale_after=3600
  fi
  if [ "$stale_after" -le 0 ]; then
    stale_after=3600
  fi

  local created_epoch now_epoch
  created_epoch="$(_iso8601_to_epoch "$created_at")" || return 0
  now_epoch="$(date -u +%s 2>/dev/null)" || return 0
  case "$created_epoch" in
    '' | *[!0-9]*) return 0 ;;
  esac
  case "$now_epoch" in
    '' | *[!0-9]*) return 0 ;;
  esac

  # A comment stamped in the future (clock skew) is not stale.
  if [ "$created_epoch" -ge "$now_epoch" ]; then
    return 0
  fi

  # A reply older than this run's most recent trigger describes a limit the
  # loop has already waited on. It must not stand in for an answer to the
  # trigger just posted, or the loop reports "rate limited" without ever
  # letting CodeRabbit respond (issue #1579, AC-1). Only applied when the
  # caller has actually posted a trigger this run: on a fresh run the anchor
  # is empty and the announced-window rule below decides alone, which is what
  # keeps a genuinely live limit from being ignored at startup.
  if [ -n "$last_trigger_iso" ]; then
    local trigger_epoch
    if trigger_epoch="$(_iso8601_to_epoch "$last_trigger_iso")"; then
      case "$trigger_epoch" in
        '' | *[!0-9]*) : ;;
        *)
          # Tolerance, because the two sides come from different clocks: the
          # anchor is stamped locally with `date`, the comment timestamp comes
          # from GitHub. Without slack, a few seconds of skew would discard
          # CodeRabbit's genuine answer to the trigger just posted, and the
          # loop would re-trigger and spend quota it may not have.
          local anchor_skew="${CODERABBIT_TRIGGER_ANCHOR_SKEW:-60}"
          case "$anchor_skew" in
            '' | *[!0-9]*) anchor_skew=60 ;;
          esac
          # Strip leading zeros before the arithmetic below: a digit-only
          # string like "008" passes the check above unchanged, but bash reads
          # it as an invalid octal literal in `$((...))` and aborts the whole
          # script under `set -e` (same class of bug guarded against for the
          # vendor-parsed value in coderabbit_rate_limit_wait_seconds).
          anchor_skew="${anchor_skew#"${anchor_skew%%[!0]*}"}"
          [ -z "$anchor_skew" ] && anchor_skew=0
          if [ "$created_epoch" -lt "$((trigger_epoch - anchor_skew))" ]; then
            return 1
          fi
          ;;
      esac
    fi
  fi

  # Reuse the same parser the wait uses, so the window that governs staleness
  # and the window the loop actually sleeps for can never drift apart.
  local window
  window="$(coderabbit_rate_limit_wait_seconds "$body" "$stale_after")"
  case "$window" in
    '' | *[!0-9]*) window="$stale_after" ;;
  esac

  if [ "$((now_epoch - created_epoch))" -lt "$window" ]; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# coderabbit_rate_limit_remaining_seconds
#
# How long is left of the window a rate-limit comment announced, given when
# that comment was posted.
#
# coderabbit_rate_limit_wait_seconds returns the FULL announced window, which
# is only the right thing to sleep at the instant the comment appears. A loop
# that starts (or re-enters this branch) part-way through the window would
# otherwise sleep the whole thing again: a 27-minute window on a comment
# already 26 minutes old would wait a further 27m30s instead of ~90s, pushing
# the retry a full extra quota cycle past the moment a review became
# available. Against a one-review-per-hour allowance that is the difference
# between finishing a PR this hour and finishing it next hour.
#
# Args: $1 body, $2 created_at (ISO-8601 UTC), $3 fallback seconds
# Prints a positive integer. Falls back to the full window whenever the age
# cannot be computed, which is the pre-existing behaviour.
coderabbit_rate_limit_remaining_seconds() {
  local body="${1:-}" created_at="${2:-}" fallback="${3:-}"
  local full
  full="$(coderabbit_rate_limit_wait_seconds "$body" "$fallback")"

  # A floor, so a window that has just expired still leaves a beat for the
  # vendor to settle rather than re-triggering instantly in a tight loop.
  local floor="${CODERABBIT_RATE_LIMIT_MIN_WAIT:-30}"
  case "$floor" in
    '' | *[!0-9]*) floor=30 ;;
  esac
  floor="${floor#"${floor%%[!0]*}"}"
  [ -z "$floor" ] && floor=0

  local created_epoch now_epoch
  created_epoch="$(_iso8601_to_epoch "$created_at")" || { printf '%s\n' "$full"; return 0; }
  now_epoch="$(date -u +%s 2>/dev/null)" || { printf '%s\n' "$full"; return 0; }
  case "$created_epoch" in '' | *[!0-9]*) printf '%s\n' "$full"; return 0 ;; esac
  case "$now_epoch" in '' | *[!0-9]*) printf '%s\n' "$full"; return 0 ;; esac
  # Clock skew: a comment stamped in the future has no elapsed age.
  if [ "$created_epoch" -ge "$now_epoch" ]; then
    printf '%s\n' "$full"
    return 0
  fi

  local age remaining
  age=$((now_epoch - created_epoch))
  remaining=$((full - age))
  if [ "$remaining" -lt "$floor" ]; then
    remaining="$floor"
  fi
  if [ "$remaining" -le 0 ]; then
    remaining=30
  fi
  printf '%s\n' "$remaining"
}

# ---------------------------------------------------------------------------
# coderabbit_newest_rate_limit_comment
#
# Print the newest CodeRabbit rate-limit comment for this HEAD window as a
# compact JSON object, or print nothing when there is none.
#
# Shared by the rate-limit retry block and the silent-non-trigger guard so both
# decide "is CodeRabbit rate limited right now" from the same evidence. They
# previously each ran their own count query, which is how a spent rate-limit
# comment could suppress the retrigger in one place while the other waited on
# it (#1579).
# Exit status is the caller's signal, and the three cases are NOT equivalent:
#   0 with output  - a rate-limit comment was found (printed as compact JSON)
#   0 with nothing - the lookup succeeded and there is no rate-limit comment
#   2              - the lookup could not be performed
#
# The previous form piped straight into jq without `pipefail` and ended in
# `|| printf ''`, so a failed `gh api` (network, auth, secondary rate limit)
# was indistinguishable from "no rate-limit comment". Both call sites then
# concluded CodeRabbit was not rate limited and posted a fresh
# `@coderabbitai review`, spending a review from an allowance measured at 1
# per hour — on evidence that was never actually read, and with nothing in the
# log to say so.
coderabbit_newest_rate_limit_comment() {
  # Validate before reading positional parameters. A missing argument would
  # otherwise build a malformed endpoint or an empty `--arg`, and `gh` would
  # fail in a way that now reports "lookup failure" — technically correct but
  # indistinguishable from a real API outage, which is the very confusion this
  # function was just changed to remove. Fail with the same status 2 contract,
  # but say plainly that the caller, not the API, is at fault.
  if [ "$#" -ne 4 ]; then
    echo "ERROR: coderabbit_newest_rate_limit_comment requires 4 arguments (repo pr_number bot_login since_iso), got $#" >&2
    return 2
  fi
  if [ -z "${1:-}" ] || [ -z "${2:-}" ] || [ -z "${3:-}" ] || [ -z "${4:-}" ]; then
    echo "ERROR: coderabbit_newest_rate_limit_comment requires non-empty repo, pr_number, bot_login and since_iso (got repo='${1:-}' pr_number='${2:-}' bot_login='${3:-}' since_iso='${4:-}')" >&2
    return 2
  fi
  local repo="$1" pr_number="$2" bot_login="$3" since_iso="$4"
  local raw="" status=0
  raw="$(gh api "repos/$repo/issues/$pr_number/comments" --paginate 2>/dev/null)" || status=$?
  if [ "$status" -ne 0 ]; then
    echo "WARN: coderabbit_newest_rate_limit_comment: could not read comments for PR #$pr_number (gh exited $status) — reporting a lookup failure, not an absence of rate limiting" >&2
    return 2
  fi
  local selected="" jq_status=0
  selected="$(printf '%s' "$raw" | jq -cs --arg bot "$bot_login" --arg since "$since_iso" '
        [.[].[] | select(
            .user.login == $bot and
            # CodeRabbit revises its walkthrough comment IN PLACE rather than
            # posting a new one, so a rate-limit banner can arrive on a comment
            # created before this HEAD (#1556 documents the same behaviour for
            # the activity probe). Select on the later of the two timestamps.
            (.created_at > $since or (.updated_at // .created_at) > $since) and
            # Three banner shapes have been observed and no single marker
            # covers them all: the standalone comment matches only the HTML
            # marker "rate limited by coderabbit.ai" while its visible text
            # reads "Review limit reached", and the command refusal carries no
            # marker at all and matches only the visible "Review rate limited."
            # Matching one of them means a live limit reads as absent, which
            # spends a review from a one-per-hour allowance.
            ((.body // "") | test("rate.?limit|review limit reached|next included review"; "i"))
        )]
        | sort_by((.updated_at // .created_at))
        | (last // empty)
        # The filter accepts on, and sorts by, the LATER of created_at and
        # updated_at, because CodeRabbit revises a comment in place. Emitting
        # that value as `effective_at` keeps consumers from re-deriving it and
        # disagreeing: reading `.created_at` for a comment selected on its
        # updated_at would age it from the wrong instant, and the age is what
        # the staleness and remaining-window arithmetic depend on.
        | . + { effective_at: (.updated_at // .created_at) }
      ' 2>/dev/null)" || jq_status=$?
  if [ "$jq_status" -ne 0 ]; then
    echo "WARN: coderabbit_newest_rate_limit_comment: could not parse comments for PR #$pr_number (jq exited $jq_status) — reporting a lookup failure" >&2
    return 2
  fi
  printf '%s' "$selected"
}

# ---------------------------------------------------------------------------
# coderabbit_rate_limit_is_live
#
# Given the JSON object from coderabbit_newest_rate_limit_comment, return 0
# when CodeRabbit is rate limited right now and 1 when it is not (no comment,
# or a comment whose announced window has already elapsed).
coderabbit_rate_limit_is_live() {
  local comment_json="${1:-}" last_trigger_iso="${2:-}"
  [ -n "$comment_json" ] || return 1
  # Reject anything that is not a JSON object before reading fields. Without
  # this, a malformed blob yields two empty strings, and an empty timestamp is
  # deliberately treated as "still current" by
  # coderabbit_rate_limit_comment_is_current — so garbage would read as a live
  # rate limit and stall the loop for the full retry budget. An unparseable
  # blob is no evidence of a limit at all, which is a different question from
  # a real comment whose timestamp could not be read.
  printf '%s' "$comment_json" | jq -e 'type == "object"' >/dev/null 2>&1 || return 1
  local body created
  body="$(printf '%s' "$comment_json" | jq -r '.body // ""' 2>/dev/null)" || body=""
  # effective_at is what the selector matched and sorted on; fall back to
  # created_at only for an object that did not come from that selector.
  created="$(printf '%s' "$comment_json" | jq -r '.effective_at // .created_at // ""' 2>/dev/null)" || created=""
  coderabbit_rate_limit_comment_is_current "$body" "$created" "$last_trigger_iso"
}

run_coderabbit_review() {
  local pr_number="$1"
  local branch_name="$2"
  local poll_interval="$3"
  local max_wait="$4"
  local platform="coderabbit"
  local bot_login="coderabbitai[bot]"
  local repo
  local head_sha=""
  local since_iso=""
  local existing_comments=""
  local existing_reviews=""
  local existing_blocking_file=""
  local existing_blocking_count=0
  local existing_suggestion_count=0
  local comment_json=""
  local review_json=""
  local body=""
  local blocking_lines_file=""
  local elapsed=0
  local comments=""
  local blocking_reviews=""
  local blocking_count=0
  local suggestion_count=0
  local comment_count=0
  local index=1
  local blocking_json=""
  local stale_file=""
  local coderabbit_trigger_attempts=0

  trap 'rm -f "${existing_blocking_file:-}" "${blocking_lines_file:-}" "${stale_file:-}"' RETURN

  require_gh
  cd_workflow_repo_root
  repo="$(repo_slug)"

  head_sha="$(gh api "repos/$repo/pulls/$pr_number" --jq '.head.sha')"
  if [ -z "$head_sha" ]; then
    print_kv RESULT escalate
    print_kv REASON "head-sha-unavailable"
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID ""
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv CODERABBIT_TRIGGER_ATTEMPTS "$coderabbit_trigger_attempts"
    print_kv CODERABBIT_REVIEWS_RECEIVED 0
    return 2
  fi
  since_iso="$(gh api "repos/$repo/commits/$head_sha" --jq '.commit.committer.date // empty')"
  if [ -z "$since_iso" ]; then
    since_iso="$(date -u -v-24H +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -d '24 hours ago' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo '1970-01-01T00:00:00Z')"
  fi
  # Cap to now: a future committer.date (clock skew or rebase) would exclude all
  # existing bot comments, causing false-clean results or duplicate review requests.
  _now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  [ "$since_iso" \> "$_now_iso" ] && since_iso="$_now_iso"
  unset _now_iso

  # --- Phase 1: Check for existing blocking findings on the current HEAD ---
  existing_comments="$(
    gh api "repos/$repo/pulls/$pr_number/comments" --paginate \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
          .[]
          | select(.user.login == $bot and .created_at > $since and .in_reply_to_id == null)
          | { path, line: (.line // .original_line // 0), body: (.body // ""), commit_id: (.commit_id // "") }
          | @json
        '
  )"
  existing_reviews="$(
    gh api "repos/$repo/pulls/$pr_number/reviews" --paginate \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
          .[]
          | select(
              .user.login == $bot and
              .submitted_at > $since and
              .state == "CHANGES_REQUESTED"
            )
          | { path: "", line: 0, body: (.body // "CHANGES_REQUESTED review without body"), commit_id: (.commit_id // .commitId // "") }
          | @json
        '
  )"

  existing_blocking_file="$(mktemp)"
  while IFS= read -r comment_json; do
    [ -z "${comment_json:-}" ] && continue
    body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    if is_coderabbit_blocking "$body"; then
      existing_blocking_count=$((existing_blocking_count + 1))
      printf '%s\n' "$comment_json" >> "$existing_blocking_file"
    else
      existing_suggestion_count=$((existing_suggestion_count + 1))
    fi
  done <<< "$existing_comments"

  while IFS= read -r review_json; do
    [ -z "${review_json:-}" ] && continue
    body="$(printf '%s\n' "$review_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    existing_blocking_count=$((existing_blocking_count + 1))
    printf '%s\n' "$review_json" >> "$existing_blocking_file"
  done <<< "$existing_reviews"

  if [ "$existing_blocking_count" -gt 0 ]; then
    print_kv RESULT needs_fixes
    reviewer_loop_print_reviewed_head_from_json_lines < "$existing_blocking_file"
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID ""
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv REASON existing_findings
    print_kv COMMENT_COUNT "$((existing_blocking_count + existing_suggestion_count))"
    print_kv BLOCKING_COUNT "$existing_blocking_count"
    print_kv SUGGESTION_COUNT "$existing_suggestion_count"
    print_kv CODERABBIT_TRIGGER_ATTEMPTS "$coderabbit_trigger_attempts"
    print_kv CODERABBIT_REVIEWS_RECEIVED 0
    while IFS= read -r blocking_json; do
      [ -z "${blocking_json:-}" ] && continue
      print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
      print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
      print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
      index=$((index + 1))
    done < "$existing_blocking_file"
    rm -f "$existing_blocking_file"
    return 1
  fi

  rm -f "$existing_blocking_file"

  # --- Phase 0: Detect and auto-resume CodeRabbit auto-pause before entering the poll loop ---
  # CodeRabbit auto-pauses after 3+ rapid pushes in quick succession and posts a
  # "Reviews paused" issue comment. When paused, it posts no review for the current HEAD,
  # so Phase 1 finds 0 blocking findings (trivially true) and Phase 2 times out with
  # RESULT=skipped/REASON=no_review (exit 0 — treated as clean by callers).
  #
  # Root cause of the Batch 52 incident (PR #650): the pause comment was posted BEFORE
  # the HEAD commit timestamp (since_iso), so the Phase 2 detection (which filters by
  # since_iso) never matched it. The script returned clean with CodeRabbit having not
  # reviewed the latest commit.
  #
  # Fix: inspect the MOST RECENT CodeRabbit issue comment on the PR without a since_iso
  # filter. If that latest comment contains a "Reviews paused" marker, CodeRabbit is still
  # in a paused state — post "@coderabbitai resume" immediately and reset since_iso so the
  # resulting review is captured. Set coderabbit_phase0_retrigger=1 so Phase 2 skips its
  # own pause-detection block and does not double-post.
  local coderabbit_phase0_retrigger=0
  local phase0_most_recent_body
  # Use -rs with add // [] to flatten all paginated pages into a single array
  # before sorting, so the "most recent" selection spans the entire comment history
  # rather than being limited to the last item on whichever page arrived last.
  phase0_most_recent_body="$(
    gh api "repos/$repo/issues/$pr_number/comments" --paginate \
      | jq -rs --arg bot "$bot_login" '
          add // []
          | map(select(.user.login == $bot))
          | sort_by(.created_at)
          | last
          | .body // ""
        '
  )"
  if printf '%s\n' "$phase0_most_recent_body" | grep -qi "reviews\? paused"; then
    echo "INFO: CodeRabbit is in auto-pause state (most recent CR comment is a pause banner) — posting @coderabbitai resume before entering poll loop" >&2
    local phase0_resume_since_iso
    # Capture the timestamp BEFORE posting so any same-second CodeRabbit response
    # is still within the detection window (queries use strict > $since_iso).
    phase0_resume_since_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    if gh pr comment "$pr_number" --body "@coderabbitai resume" >/dev/null 2>&1; then
      coderabbit_phase0_retrigger=1
      coderabbit_trigger_attempts=$((coderabbit_trigger_attempts + 1))
      since_iso="$phase0_resume_since_iso"
      echo "INFO: @coderabbitai resume posted; since_iso reset to $since_iso" >&2
    else
      # The resume post failed while CodeRabbit is still paused. If we proceed without
      # resetting since_iso, the timeout guard at the end of the poll loop may miss the
      # old pause banner (its timestamp predates since_iso) and fall through to a false-
      # clean RESULT=skipped/REASON=no_review. Escalate immediately instead.
      echo "ERROR: failed to post @coderabbitai resume for pre-existing pause banner — escalating to avoid false-clean no_review exit" >&2
      print_kv RESULT escalate
      print_kv REASON rate_limit_max_retries
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      print_kv CODERABBIT_TRIGGER_ATTEMPTS "$coderabbit_trigger_attempts"
      print_kv CODERABBIT_REVIEWS_RECEIVED 0
      return 2
    fi
  fi

  # --- Phase 2: Poll for CodeRabbit review completion ---
  # CodeRabbit signals completion by posting a COMMENTED review after the HEAD commit.
  # Unlike Devin, there are no check runs to monitor — we rely solely on the review.
  #
  local coderabbit_review_count=0
  local coderabbit_any_activity=0
  # Initialize retrigger flag from Phase 0 so Phase 2 does not double-post a resume.
  local coderabbit_retrigger_attempted=$coderabbit_phase0_retrigger
  local coderabbit_rate_limit_retries=0
  # When this run last asked CodeRabbit for a review. Anchors rate-limit
  # staleness so a reply the loop has already waited on cannot answer a newer
  # trigger (#1579, AC-1). Empty until this run posts its first trigger.
  local coderabbit_last_trigger_iso=""
  local coderabbit_last_quota_refusal_trigger_iso=""
  local coderabbit_rate_limit_hold_seen=0
  # Defaults are sized against CodeRabbit's *hourly* quota reset: 4 retries x 900 s
  # covers 60 minutes of waiting, so a loop that hits the cap early in an hour can
  # still succeed once the vendor window rolls over. The previous 2 x 180 s (~6 min)
  # exhausted its retries roughly 54 minutes before the vendor could possibly answer
  # and escalated PRs that had nothing wrong with them — the dominant failure mode
  # for unattended overnight runs. Both env vars still override.
  local coderabbit_rate_limit_max_retries="${CODERABBIT_RATE_LIMIT_MAX_RETRIES:-$CODERABBIT_RATE_LIMIT_MAX_RETRIES_DEFAULT}"
  local coderabbit_rate_limit_wait="${CODERABBIT_RATE_LIMIT_WAIT:-$CODERABBIT_RATE_LIMIT_WAIT_DEFAULT}"
  # See coderabbit_resolve_no_trigger_timeout / coderabbit_no_trigger_timeout_default
  # (issue #1433) for why the default is computed from max_wait rather than a
  # fixed constant, and for env var override / validation-fallback handling
  # (including the WARN-and-fallback path for an invalid explicit override).
  local coderabbit_no_trigger_timeout
  coderabbit_no_trigger_timeout="$(coderabbit_resolve_no_trigger_timeout "$max_wait")"
  local coderabbit_no_trigger_retriggers=0
  if ! [[ "$coderabbit_rate_limit_max_retries" =~ ^[0-9]+$ ]]; then
    echo "WARN: CODERABBIT_RATE_LIMIT_MAX_RETRIES must be a non-negative integer; defaulting to 4" >&2
    coderabbit_rate_limit_max_retries=4
  fi
  if ! [[ "$coderabbit_rate_limit_wait" =~ ^[0-9]+$ ]] || [ "$coderabbit_rate_limit_wait" -le 0 ]; then
    echo "WARN: CODERABBIT_RATE_LIMIT_WAIT must be a positive integer; defaulting to 900" >&2
    coderabbit_rate_limit_wait=900
  fi

  while :; do
    # Check for any CodeRabbit review submitted after the HEAD commit
    coderabbit_review_count="$(
      gh api "repos/$repo/pulls/$pr_number/reviews" --paginate \
        | jq --arg bot "$bot_login" --arg since "$since_iso" '
            [.[]
             | select(
                 .user.login == $bot and
                 .submitted_at > $since
               )
            ] | length
          '
    )"
    coderabbit_review_count="${coderabbit_review_count:-0}"

    if [ "$coderabbit_review_count" -gt 0 ]; then
      coderabbit_any_activity=1
      break
    fi

    # Also check for CodeRabbit issue comments (summary comment) as activity signal.
    # Filter by since_iso so historical comments from prior pushes do not incorrectly
    # mark this HEAD cycle as having activity (which would suppress stale-findings recovery).
    #
    # Both created_at AND updated_at are accepted (issue #1556). CodeRabbit revises
    # its walkthrough comment IN PLACE rather than posting a new one, so the comment
    # keeps its original created_at. Observed on PR #1532: created 23:23 — before the
    # 23:34 HEAD commit — and edited 23:52 to carry the new review. A created_at-only
    # filter cannot see that at all; the run only survived because CodeRabbit also
    # submitted a formal review, which is matched separately on submitted_at. The
    # timeout guard already accepted updated_at; this probe did not.
    # Exclude "Reviews paused" comments (pause marker), "rate limit" comments (rate-limit
    # marker), "Reviews resumed" acknowledgement comments, and "Review skipped" banners
    # (skip marker — see CODERABBIT_SKIP_BANNER_RE) — none of these represent a
    # completed review and must not trigger an early break from the poll loop.
    if [ "$coderabbit_any_activity" -eq 0 ]; then
      local activity_count
      activity_count="$(
        gh api "repos/$repo/issues/$pr_number/comments" --paginate \
          | jq -s --arg bot "$bot_login" --arg since "$since_iso" \
               --arg skip_re "$CODERABBIT_SKIP_BANNER_RE" '
              [.[].[] | select(
                  .user.login == $bot and
                  (.created_at > $since or (.updated_at // .created_at) > $since) and
                  ((.body // "") | test("Reviews paused|review paused"; "i") | not) and
                  ((.body // "") | test("rate.?limit"; "i") | not) and
                  ((.body // "") | test("reviews resumed"; "i") | not) and
                  ((.body // "") | test($skip_re; "i") | not)
              )] | length
            '
      )"
      if [ "${activity_count:-0}" -gt 0 ]; then
        coderabbit_any_activity=1
        # Issue-comment activity means CodeRabbit finished this HEAD cycle, but unlike
        # a formal PR review it does not hit the `break` above — continue to Phase 3.
        break
      fi
    fi

    # --- Auto-retrigger: detect CodeRabbit "reviews paused" state ---
    # CodeRabbit auto-pauses reviews after many commits. When this happens, no
    # review is posted for the current HEAD, causing the loop to time out. Detect
    # the pause by checking for a "Reviews paused" issue comment and post
    # "@coderabbitai resume" to resume the paused review. Only attempt once.
    if [ "$coderabbit_any_activity" -eq 0 ] && [ "$coderabbit_retrigger_attempted" -eq 0 ] && [ "$elapsed" -ge "$((max_wait / 2))" ]; then
      # Check if the most recent CodeRabbit bot comment created after since_iso contains
      # a "Reviews paused" marker. Use since_iso filter to avoid false positives from
      # historical pause banners from prior HEAD commits.
      local paused_count
      paused_count="$(
        gh api "repos/$repo/issues/$pr_number/comments" --paginate \
          | jq -s --arg bot "$bot_login" --arg since "$since_iso" '
              [.[].[] | select(
                  .user.login == $bot and
                  .created_at > $since and
                  ((.body // "") | test("Reviews paused|review paused"; "i"))
              )] | length
            '
      )"
      if [ "${paused_count:-0}" -gt 0 ]; then
        echo "INFO: CodeRabbit reviews are paused — posting @coderabbitai resume to trigger a fresh review" >&2
        if gh pr comment "$pr_number" --body "@coderabbitai resume" >/dev/null 2>&1; then
          coderabbit_retrigger_attempted=1
          coderabbit_trigger_attempts=$((coderabbit_trigger_attempts + 1))
          # Reset the elapsed timer to give the retrigger time to complete.
          elapsed=0
        else
          echo "WARN: failed to post @coderabbitai resume — will not reset timer" >&2
          coderabbit_retrigger_attempted=1
        fi
        _interruptible_sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
        continue
      fi
    fi

    # --- Auto-retrigger: detect CodeRabbit silent non-trigger after push ---
    # CodeRabbit sometimes does not auto-trigger after a push commit: no review
    # appears, no "Reviews paused" comment, and no rate-limit comment — CodeRabbit
    # simply stays silent. When no activity has been seen after
    # CODERABBIT_NO_TRIGGER_TIMEOUT seconds (default: see
    # coderabbit_no_trigger_timeout_default — 180 s, capped at half of
    # max_wait; issue #1433), post "@coderabbitai review" to force a fresh
    # review. Uses CODERABBIT_RATE_LIMIT_MAX_RETRIES as the combined retrigger
    # cap so callers have a single knob for total retrigger attempts across
    # both mechanisms.
    if [ "$coderabbit_any_activity" -eq 0 ] \
        && [ "$coderabbit_retrigger_attempted" -eq 0 ] \
        && [ "$coderabbit_rate_limit_hold_seen" -eq 0 ] \
        && [ "$coderabbit_no_trigger_retriggers" -lt "$coderabbit_rate_limit_max_retries" ] \
        && [ "$elapsed" -ge "$coderabbit_no_trigger_timeout" ]; then
      # Confirm neither a "paused" comment nor a *live* rate limit is present —
      # those are handled by their own dedicated blocks above/below.
      #
      # The rate-limit half is deliberately not a presence check. A rate-limit
      # comment whose announced window has already elapsed is spent, and must
      # not suppress this retrigger: a spent comment doing exactly that is what
      # left PR #1575 with no CodeRabbit activity for 21 hours while the loop
      # declined to post a trigger (#1579).
      local silent_paused_count
      silent_paused_count="$(
        gh api "repos/$repo/issues/$pr_number/comments" --paginate \
          | jq -s --arg bot "$bot_login" --arg since "$since_iso" '
              [.[].[] | select(
                  .user.login == $bot and
                  .created_at > $since and
                  ((.body // "") | test("Reviews paused|review paused"; "i"))
              )] | length
            '
      )"
      local silent_blocked=0
      if [ "${silent_paused_count:-0}" -gt 0 ]; then
        silent_blocked=1
      else
        local silent_rate_limit_json="" silent_lookup_status=0
        silent_rate_limit_json="$(coderabbit_newest_rate_limit_comment "$repo" "$pr_number" "$bot_login" "$since_iso")" || silent_lookup_status=$?
        if [ "$silent_lookup_status" -ne 0 ]; then
          # The lookup failed, so whether CodeRabbit is rate limited is unknown.
          # Hold the retrigger rather than spend a review on a guess: the
          # allowance was measured at 1 per hour, so a wasted trigger costs the
          # PR an hour, while holding costs one poll interval.
          echo "WARN: could not determine CodeRabbit rate-limit state for PR #$pr_number — holding the silent non-trigger retrigger rather than spending a review on an unread signal" >&2
          silent_blocked=1
        elif [ -n "$silent_rate_limit_json" ]; then
          if coderabbit_rate_limit_is_live "$silent_rate_limit_json" "$coderabbit_last_trigger_iso"; then
            silent_blocked=1
          else
            echo "INFO: a spent CodeRabbit rate-limit comment is present but its window has elapsed — not letting it suppress the silent non-trigger retrigger (#1579)" >&2
          fi
        fi
      fi
      if [ "$silent_blocked" -eq 0 ]; then
        coderabbit_no_trigger_retriggers=$((coderabbit_no_trigger_retriggers + 1))
        echo "INFO: CodeRabbit has not auto-triggered after ${elapsed}s (silent non-trigger, attempt ${coderabbit_no_trigger_retriggers}/${coderabbit_rate_limit_max_retries}) — posting @coderabbitai review" >&2
        if gh pr comment "$pr_number" --body "@coderabbitai review" >/dev/null 2>&1; then
          coderabbit_rate_limit_hold_seen=0
          coderabbit_trigger_attempts=$((coderabbit_trigger_attempts + 1))
          coderabbit_last_trigger_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
          echo "INFO: @coderabbitai review trigger posted" >&2
        else
          echo "WARN: failed to post @coderabbitai review trigger for silent non-trigger" >&2
        fi
        # Reset the elapsed timer to give the retrigger a full polling window.
        elapsed=0
        _interruptible_sleep "$poll_interval"
        elapsed=$((elapsed + poll_interval))
        continue
      fi
    fi

    # --- Rate-limit detection: CodeRabbit posts a comment when it cannot review yet ---
    # When CodeRabbit is rate-limited it posts an issue comment containing "rate limit"
    # text. Detect this, wait, then post "@coderabbitai resume" to request CodeRabbit
    # to resume its review. Retried up to coderabbit_rate_limit_max_retries times.
    # When retries are exhausted, the timeout block below escalates instead of returning
    # a false-clean no_review result (see the incomplete-review guard before no_review exit).
    if [ "$coderabbit_any_activity" -eq 0 ] && [ "$coderabbit_rate_limit_retries" -lt "$coderabbit_rate_limit_max_retries" ]; then
      # Select the NEWEST matching rate-limit comment as a whole object, not a
      # count. Its body carries the vendor's own remaining window ("Next
      # included review available in N minutes") and its created_at says when
      # that window started — the two inputs needed to size the wait and to
      # tell a live limit from a spent one (#1579).
      local rate_limit_comment_json="" rate_limit_comment_body="" rate_limit_comment_created=""
      local rate_limit_lookup_status=0
      rate_limit_comment_json="$(coderabbit_newest_rate_limit_comment "$repo" "$pr_number" "$bot_login" "$since_iso")" || rate_limit_lookup_status=$?
      if [ "$rate_limit_lookup_status" -ne 0 ]; then
        # Say so. Clearing the value silently is how a lookup that never
        # happened becomes "there is no rate limit" — the exact conflation the
        # status-2 contract was introduced to remove. The retry branch below
        # is skipped either way, but a silent skip leaves nothing in the log to
        # explain why the loop went on to spend a review.
        echo "WARN: could not read the rate-limit comment for PR #$pr_number (lookup exit $rate_limit_lookup_status) — proceeding without rate-limit evidence for this pass, NOT concluding that no limit exists" >&2
        rate_limit_comment_json=""
      fi

      local rate_limit_comment_count=0
      if [ -n "$rate_limit_comment_json" ]; then
        # `-r` on the body is deliberate: it is consumed as text by the regex
        # parser, and a JSON-quoted string would not match.
        rate_limit_comment_body="$(printf '%s' "$rate_limit_comment_json" | jq -r '.body // ""' 2>/dev/null)" || rate_limit_comment_body=""
        rate_limit_comment_created="$(printf '%s' "$rate_limit_comment_json" | jq -r '.effective_at // .created_at // ""' 2>/dev/null)" || rate_limit_comment_created=""
        if coderabbit_rate_limit_is_live "$rate_limit_comment_json" "$coderabbit_last_trigger_iso"; then
          if [ -n "$coderabbit_last_trigger_iso" ] && [ "$coderabbit_last_quota_refusal_trigger_iso" != "$coderabbit_last_trigger_iso" ]; then
            coderabbit_last_quota_refusal_trigger_iso="$coderabbit_last_trigger_iso"
            if [ "$coderabbit_rate_limit_retries" -gt 0 ]; then
              coderabbit_rate_limit_retries=$((coderabbit_rate_limit_retries - 1))
            fi
            echo "INFO: CodeRabbit quota refusal observed for last trigger — not counting it toward CODERABBIT_RATE_LIMIT_MAX_RETRIES" >&2
          fi
          rate_limit_comment_count=1
        else
          echo "INFO: newest CodeRabbit rate-limit comment (${rate_limit_comment_created:-unknown time}) is past the window it announced — treating it as spent rather than waiting on it again (#1579)" >&2
          if [ "$coderabbit_rate_limit_hold_seen" -eq 1 ] && [ "$coderabbit_rate_limit_retries" -lt "$coderabbit_rate_limit_max_retries" ]; then
            echo "INFO: CodeRabbit rate-limit window elapsed after a held wait — posting @coderabbitai review" >&2
            if gh pr comment "$pr_number" --body "@coderabbitai review" >/dev/null 2>&1; then
              coderabbit_rate_limit_hold_seen=0
              coderabbit_rate_limit_retries=$((coderabbit_rate_limit_retries + 1))
              coderabbit_trigger_attempts=$((coderabbit_trigger_attempts + 1))
              coderabbit_last_trigger_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
              echo "INFO: posted @coderabbitai review after rate-limit window elapsed" >&2
            else
              echo "WARN: failed to post @coderabbitai review after rate-limit window elapsed" >&2
            fi
            elapsed=0
            _interruptible_sleep "$poll_interval"
            elapsed=$((elapsed + poll_interval))
            continue
          fi
        fi
      fi
      if [ "${rate_limit_comment_count:-0}" -gt 0 ]; then
        echo "INFO: CodeRabbit rate limit detected (retry attempts spent $coderabbit_rate_limit_retries/$coderabbit_rate_limit_max_retries) — checking for SUCCESS commit status before waiting" >&2
        # --- Early SUCCESS check before retry wait ---
        # Check whether CodeRabbit already posted a genuine SUCCESS commit status for
        # the current HEAD SHA (state == "success" AND description is not a rate-limit
        # message — see coderabbit_success_status_count / issue #1437). This happens
        # when CodeRabbit signals the result via a commit status during a rate-limit
        # window on a parallel batch. If found, skip the retry wait entirely and treat
        # the PR as clean via coderabbit_status_success_fallback.
        local coderabbit_early_success_count
        coderabbit_early_success_count="$(coderabbit_success_status_count "$repo" "$head_sha")"
        if [ "${coderabbit_early_success_count:-0}" -gt 0 ]; then
          # SUCCESS status can appear while older CodeRabbit review threads stay unresolved
          # on the PR. Do not short-circuit to clean until GraphQL thread audit passes —
          # same pattern as the timeout SUCCESS fallback below.
          # Wait before the audit: CodeRabbit may set SUCCESS while still posting inline
          # threads asynchronously. FALLBACK_THREAD_SETTLE_WAIT (default 60s) gives those
          # threads time to arrive so the audit does not return a false-clean count.
          local fallback_settle_wait="${FALLBACK_THREAD_SETTLE_WAIT:-60}"
          if [ "$fallback_settle_wait" -gt 0 ]; then
            echo "INFO: coderabbit_status_success_fallback — waiting ${fallback_settle_wait}s for async threads to settle before thread audit" >&2
            _interruptible_sleep "$fallback_settle_wait"
          fi
          local cr_early_gate_rc
          coderabbit_thread_gate_clean "$pr_number" "$repo" "$bot_login" "$branch_name"
          cr_early_gate_rc=$?
          if [ "$cr_early_gate_rc" -eq 0 ]; then
            echo "INFO: CodeRabbit SUCCESS commit-status found for HEAD $head_sha before retry wait — treating PR as clean (coderabbit_status_success_fallback)" >&2
            print_kv RESULT clean
      {
        [ -n "${comments:-}" ] && printf '%s\n' "$comments"
        [ -n "${existing_comments:-}" ] && printf '%s\n' "$existing_comments"
        [ -n "${blocking_reviews:-}" ] && printf '%s\n' "$blocking_reviews"
        [ -n "${existing_reviews:-}" ] && printf '%s\n' "$existing_reviews"
        [ -n "${reviews:-}" ] && printf '%s\n' "$reviews"
      } | reviewer_loop_print_reviewed_head_from_json_lines
            print_kv REASON coderabbit_status_success_fallback
            print_kv PLATFORM "$platform"
            print_kv PR_NUMBER "$pr_number"
            print_kv BRANCH "$branch_name"
            print_kv REVIEW_COMMENT_ID ""
            print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
            print_kv COMMENT_COUNT 0
            print_kv BLOCKING_COUNT 0
            print_kv SUGGESTION_COUNT 0
            print_kv CODERABBIT_TRIGGER_ATTEMPTS "$coderabbit_trigger_attempts"
            print_kv CODERABBIT_REVIEWS_RECEIVED "$coderabbit_review_count"
            return 0
          fi
          if [ "$cr_early_gate_rc" -eq 1 ] || [ "$cr_early_gate_rc" -eq 2 ]; then
            return "$cr_early_gate_rc"
          fi
        fi
        # Size this wait from the vendor's own stated window when it gives one,
        # falling back to the configured constant otherwise. A fixed constant
        # cannot track an allowance the vendor changes (measured at 1 review
        # per hour on 2026-08-24), so it either retries far too early — burning
        # the retry budget without a review — or far too late.
        local coderabbit_this_wait
        coderabbit_this_wait="$(coderabbit_rate_limit_remaining_seconds "$rate_limit_comment_body" "$rate_limit_comment_created" "$coderabbit_rate_limit_wait")"
        if [ "$coderabbit_this_wait" != "$coderabbit_rate_limit_wait" ]; then
          echo "INFO: no SUCCESS commit status found — CodeRabbit states its next review window; waiting ${coderabbit_this_wait}s (configured fallback ${coderabbit_rate_limit_wait}s) before re-triggering" >&2
        else
          echo "INFO: no SUCCESS commit status found — waiting ${coderabbit_this_wait}s before re-triggering" >&2
        fi
        _interruptible_sleep "$coderabbit_this_wait"
        local coderabbit_post_wait_rate_limit_json="" coderabbit_post_wait_lookup_status=0
        local coderabbit_skip_rate_limit_retrigger=0
        coderabbit_post_wait_rate_limit_json="$(coderabbit_newest_rate_limit_comment "$repo" "$pr_number" "$bot_login" "$since_iso")" || coderabbit_post_wait_lookup_status=$?
        if [ "$coderabbit_post_wait_lookup_status" -ne 0 ]; then
          echo "WARN: could not re-check CodeRabbit rate-limit state after waiting for PR #$pr_number — holding retrigger rather than spending a review attempt on unread quota state" >&2
          _interruptible_sleep "$poll_interval"
          elapsed=$((elapsed + coderabbit_this_wait + poll_interval))
          if [ "$elapsed" -lt "$max_wait" ]; then
            coderabbit_rate_limit_hold_seen=1
            continue
          fi
          coderabbit_skip_rate_limit_retrigger=1
        fi
        if coderabbit_rate_limit_is_live "$coderabbit_post_wait_rate_limit_json" "$coderabbit_last_trigger_iso"; then
          echo "INFO: CodeRabbit rate limit is still live after waiting — not posting a trigger while quota refusal remains outstanding" >&2
          _interruptible_sleep "$poll_interval"
          elapsed=$((elapsed + coderabbit_this_wait + poll_interval))
          if [ "$elapsed" -lt "$max_wait" ]; then
            coderabbit_rate_limit_hold_seen=1
            continue
          fi
          coderabbit_skip_rate_limit_retrigger=1
        fi
        if [ "$coderabbit_skip_rate_limit_retrigger" -eq 0 ]; then
          # Do NOT reset since_iso — keep the original HEAD-commit timestamp so any review
          # posted by CodeRabbit during or after the wait is still within the detection window.
          elapsed=0
          # Re-trigger with "review", not "resume". "resume" only lifts a paused
          # state; against a rate limit CodeRabbit answers "Reviews resumed" and
          # reviews nothing, so the loop spends its whole budget on
          # acknowledgements (PR #1589: four resumes, zero reviews). A pause and a
          # rate limit need different verbs, and this branch is the rate-limit one.
          if gh pr comment "$pr_number" --body "@coderabbitai review" >/dev/null 2>&1; then
            coderabbit_rate_limit_hold_seen=0
            coderabbit_rate_limit_retries=$((coderabbit_rate_limit_retries + 1))
            coderabbit_trigger_attempts=$((coderabbit_trigger_attempts + 1))
            coderabbit_last_trigger_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
            echo "INFO: posted @coderabbitai review after rate-limit wait" >&2
          else
            echo "WARN: failed to post @coderabbitai review after rate-limit wait" >&2
          fi
          _interruptible_sleep "$poll_interval"
          elapsed=$((elapsed + poll_interval))
          continue
        fi
      fi
    fi

    if [ "$elapsed" -ge "$max_wait" ]; then
      if [ "$coderabbit_any_activity" -eq 0 ]; then
        # --- SUCCESS commit-status fallback ---
        # Before running stale-findings recovery or escalating, check whether CodeRabbit
        # already posted a genuine SUCCESS commit-status context for the current HEAD SHA
        # (state == "success" AND description is not a rate-limit message — see
        # coderabbit_success_status_count / issue #1437). This happens during rate-limit
        # windows on parallel batches: CodeRabbit signals the result via a commit status
        # rather than an inline review comment. If found, treat the PR as clean and return
        # immediately without scanning for stale findings. Context name is matched
        # case-insensitively to guard against future renames.
        local coderabbit_success_status_result_count
        coderabbit_success_status_result_count="$(coderabbit_success_status_count "$repo" "$head_sha")"
        if [ "${coderabbit_success_status_result_count:-0}" -gt 0 ]; then
          # SUCCESS status can appear while older CodeRabbit review threads stay unresolved
          # on the PR. Do not short-circuit to clean until GraphQL thread audit passes.
          # Wait before the audit: CodeRabbit may set SUCCESS while still posting inline
          # threads asynchronously. FALLBACK_THREAD_SETTLE_WAIT (default 60s) gives those
          # threads time to arrive so the audit does not return a false-clean count.
          local fallback_settle_wait_timeout="${FALLBACK_THREAD_SETTLE_WAIT:-60}"
          if [ "$fallback_settle_wait_timeout" -gt 0 ]; then
            echo "INFO: coderabbit_status_success_fallback — waiting ${fallback_settle_wait_timeout}s for async threads to settle before thread audit" >&2
            _interruptible_sleep "$fallback_settle_wait_timeout"
          fi
          coderabbit_thread_gate_clean "$pr_number" "$repo" "$bot_login" "$branch_name"
          cr_success_gate_rc=$?
          if [ "$cr_success_gate_rc" -eq 0 ]; then
            echo "INFO: CodeRabbit SUCCESS commit-status found for HEAD $head_sha — treating PR as clean (coderabbit_status_success_fallback)" >&2
            print_kv RESULT clean
      {
        [ -n "${comments:-}" ] && printf '%s\n' "$comments"
        [ -n "${existing_comments:-}" ] && printf '%s\n' "$existing_comments"
        [ -n "${blocking_reviews:-}" ] && printf '%s\n' "$blocking_reviews"
        [ -n "${existing_reviews:-}" ] && printf '%s\n' "$existing_reviews"
        [ -n "${reviews:-}" ] && printf '%s\n' "$reviews"
      } | reviewer_loop_print_reviewed_head_from_json_lines
            print_kv REASON coderabbit_status_success_fallback
            print_kv PLATFORM "$platform"
            print_kv PR_NUMBER "$pr_number"
            print_kv BRANCH "$branch_name"
            print_kv REVIEW_COMMENT_ID ""
            print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
            print_kv COMMENT_COUNT 0
            print_kv BLOCKING_COUNT 0
            print_kv SUGGESTION_COUNT 0
            print_kv CODERABBIT_TRIGGER_ATTEMPTS "$coderabbit_trigger_attempts"
            print_kv CODERABBIT_REVIEWS_RECEIVED "$coderabbit_review_count"
            return 0
          fi
          if [ "$cr_success_gate_rc" -eq 1 ] || [ "$cr_success_gate_rc" -eq 2 ]; then
            return "$cr_success_gate_rc"
          fi
        fi

        # CodeRabbit didn't review this HEAD. Check for stale findings before skipping.
        # Only consider unresolved inline comments here. Exclude resolved findings
        # (replies starting with ✅ resolve their parent comment) — same pattern as Devin.
        local stale_count=0
        local stale_blocking_count=0
        local stale_comments
        stale_comments="$(
          gh api "repos/$repo/pulls/$pr_number/comments" --paginate \
            | jq -s -r --arg bot "$bot_login" '
                (
                  [
                    .[][]
                    | select(
                        .user.login == $bot and
                        .in_reply_to_id != null and
                        ((.body // "") | test("^✅"))
                      )
                    | .in_reply_to_id
                  ]
                ) as $resolved_ids
                | .[][]
                | select(
                    .user.login == $bot and
                    .in_reply_to_id == null and
                    ((.body // "") | test("^✅") | not) and
                    ((.body // "") | test("✅ Addressed") | not) and
                    (.id as $comment_id | ($resolved_ids | index($comment_id) | not))
                  )
                | { path, line: (.line // .original_line // 0), body: (.body // ""), commit_id: (.commit_id // "") }
                | @json
              '
        )"
        stale_file="$(mktemp)"
        while IFS= read -r comment_json; do
          [ -z "${comment_json:-}" ] && continue
          body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
          [ -z "$body" ] && continue
          if is_coderabbit_blocking "$body"; then
            stale_blocking_count=$((stale_blocking_count + 1))
            printf '%s\n' "$comment_json" >> "$stale_file"
          fi
          stale_count=$((stale_count + 1))
        done <<< "$stale_comments"

        if [ "$stale_blocking_count" -gt 0 ]; then
          print_kv RESULT needs_fixes
          print_kv PLATFORM "$platform"
          print_kv PR_NUMBER "$pr_number"
          print_kv BRANCH "$branch_name"
          print_kv REVIEW_COMMENT_ID ""
          print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
          print_kv REASON stale_findings
          print_kv COMMENT_COUNT "$stale_count"
          print_kv BLOCKING_COUNT "$stale_blocking_count"
          print_kv SUGGESTION_COUNT "$((stale_count - stale_blocking_count))"
          print_kv CODERABBIT_TRIGGER_ATTEMPTS "$coderabbit_trigger_attempts"
          print_kv CODERABBIT_REVIEWS_RECEIVED "$coderabbit_review_count"
          while IFS= read -r blocking_json; do
            [ -z "${blocking_json:-}" ] && continue
            print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
            print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
            print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
            index=$((index + 1))
          done < "$stale_file"
          reviewer_loop_print_reviewed_head_from_json_lines < "$stale_file"
          rm -f "$stale_file"
          return 1
        fi
        rm -f "$stale_file"

        # --- Incomplete-review guard before no_review clean exit ---
        # If a CodeRabbit rate-limit comment OR a "Reviews paused" banner is still
        # active (posted or edited since since_iso), CodeRabbit has not completed
        # its review. Returning clean here would be a false-clean. Instead, escalate
        # so the caller knows CodeRabbit was still rate-limited or paused when the
        # poll window ended. This covers both the case where retries were exhausted
        # and the case where the poll window ended mid-retry (e.g. elapsed >= max_wait
        # before the retry could fire), and the case where only a pause banner
        # (without a rate-limit comment) caused the no-review outcome. Note: CodeRabbit
        # sometimes signals rate-limits by editing its existing walkthrough comment
        # rather than posting a new one, so we check both created_at and updated_at.
        local timeout_incomplete_count
        timeout_incomplete_count="$(
          gh api "repos/$repo/issues/$pr_number/comments" --paginate \
            | jq -s --arg bot "$bot_login" --arg since "$since_iso" '
                [.[].[] | select(
                    .user.login == $bot and
                    (.created_at > $since or .updated_at > $since) and
                    (
                      ((.body // "") | test("rate.?limit"; "i")) or
                      ((.body // "") | test("Reviews paused|review paused"; "i"))
                    )
                )] | length
              '
        )"
        # A "Review skipped" banner is a distinct terminal non-review outcome from a
        # rate limit or a pause: CodeRabbit consciously declined to review this PR
        # (auto_review disabled, drafts excluded, or base_branches not matching) rather
        # than being unable to. It is detected separately so the escalation REASON tells
        # the operator which knob to turn — review_skipped_banner points at
        # .coderabbit.yaml, rate_limit_max_retries points at vendor quota.
        #
        # Matched on the LATEST CodeRabbit comment WITHIN the current HEAD window.
        # Both halves of that are load-bearing, and each one alone misattributes in the
        # opposite direction:
        #
        #   - "Any banner in the window" (no latest constraint) blames a stale banner
        #     for a later outcome. A repository that sets auto_review.drafts to false —
        #     the recommended setting when coderabbit runs in on_ready.github — collects
        #     a "Review skipped / Draft detected" banner on every PR while it is still a
        #     draft, timestamped after the HEAD commit. Without the latest constraint,
        #     every subsequent ready-phase timeout would report review_skipped_banner
        #     even when CodeRabbit had since posted a pause or rate-limit notice.
        #
        #   - "Latest comment overall" (no window constraint) blames a banner from a
        #     PREVIOUS HEAD. Push a new commit after a draft-phase banner and that
        #     banner is still the newest comment on the PR, so a silent or rate-limited
        #     review of the *current* HEAD would be reported as a configuration problem.
        #
        # Taking the latest in-window comment also yields correctly to the pause and
        # rate-limit handlers below whenever CodeRabbit has since said something more
        # specific. updated_at is accepted alongside created_at because CodeRabbit
        # revises its existing comment in place rather than always posting a new one.
        #
        # For the same reason the sort key is the EFFECTIVE event time,
        # updated_at // created_at, not created_at. Admitting a comment on updated_at
        # and then ordering on created_at contradicts itself: an older comment that
        # CodeRabbit edited a moment ago is genuinely the most recent thing it said,
        # but a created_at sort would rank a banner posted in between above it. That is
        # not hypothetical — on PR #1532 the walkthrough comment was created at 23:23
        # and revised at 23:52, straddling later comments.
        local timeout_latest_cr_body
        timeout_latest_cr_body="$(
          gh api "repos/$repo/issues/$pr_number/comments" --paginate \
            | jq -rs --arg bot "$bot_login" --arg since "$since_iso" '
                add // []
                | map(select(
                    .user.login == $bot and
                    (.created_at > $since or .updated_at > $since)
                  ))
                | sort_by(.updated_at // .created_at)
                | last
                | .body // ""
              '
        )"
        local timeout_skip_banner_count=0
        if printf '%s\n' "$timeout_latest_cr_body" \
             | grep -qiE "$CODERABBIT_SKIP_BANNER_RE"; then
          timeout_skip_banner_count=1
        fi
        if [ "${timeout_skip_banner_count:-0}" -gt 0 ]; then
          echo "ERROR: CodeRabbit posted a 'Review skipped' banner and never reviewed HEAD $head_sha — escalating instead of returning clean. Check reviews.auto_review.enabled / .drafts / .base_branches in .coderabbit.yaml against this PR's draft state and base branch." >&2
          print_kv RESULT escalate
          print_kv REASON review_skipped_banner
          print_kv PLATFORM "$platform"
          print_kv PR_NUMBER "$pr_number"
          print_kv BRANCH "$branch_name"
          print_kv REVIEW_COMMENT_ID ""
          print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
          print_kv COMMENT_COUNT 0
          print_kv BLOCKING_COUNT 0
          print_kv SUGGESTION_COUNT 0
          print_kv CODERABBIT_TRIGGER_ATTEMPTS "$coderabbit_trigger_attempts"
          print_kv CODERABBIT_REVIEWS_RECEIVED "$coderabbit_review_count"
          return 2
        fi
        if [ "${timeout_incomplete_count:-0}" -gt 0 ] || [ "$coderabbit_phase0_retrigger" -eq 1 ]; then
          echo "INFO: CodeRabbit rate-limit or pause still unresolved at timeout (incomplete_count=${timeout_incomplete_count:-0}, phase0_retrigger=$coderabbit_phase0_retrigger) — escalating instead of returning clean" >&2
          print_kv RESULT escalate
          print_kv REASON rate_limit_max_retries
          print_kv PLATFORM "$platform"
          print_kv PR_NUMBER "$pr_number"
          print_kv BRANCH "$branch_name"
          print_kv REVIEW_COMMENT_ID ""
          print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
          print_kv COMMENT_COUNT 0
          print_kv BLOCKING_COUNT 0
          print_kv SUGGESTION_COUNT 0
          print_kv CODERABBIT_TRIGGER_ATTEMPTS "$coderabbit_trigger_attempts"
          print_kv CODERABBIT_REVIEWS_RECEIVED "$coderabbit_review_count"
          return 2
        fi

        print_kv RESULT skipped
        print_kv REASON no_review
        print_kv PLATFORM "$platform"
        print_kv PR_NUMBER "$pr_number"
        print_kv BRANCH "$branch_name"
        print_kv REVIEW_COMMENT_ID ""
        print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
        print_kv COMMENT_COUNT 0
        print_kv BLOCKING_COUNT 0
        print_kv SUGGESTION_COUNT 0
        print_kv CODERABBIT_TRIGGER_ATTEMPTS "$coderabbit_trigger_attempts"
        print_kv CODERABBIT_REVIEWS_RECEIVED "$coderabbit_review_count"
        return 0
      fi
      print_kv RESULT escalate
      print_kv REASON timeout
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv REVIEW_COMMENT_ID ""
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv CODERABBIT_TRIGGER_ATTEMPTS "$coderabbit_trigger_attempts"
      print_kv CODERABBIT_REVIEWS_RECEIVED "$coderabbit_review_count"
      return 2
    fi

    _interruptible_sleep "$poll_interval"
    elapsed=$((elapsed + poll_interval))
  done

  # --- Phase 3: Collect results after completion ---
  blocking_lines_file="$(mktemp)"

  comments="$(
    gh api "repos/$repo/pulls/$pr_number/comments" --paginate \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
        .[]
        | select(.user.login == $bot and .created_at > $since and .in_reply_to_id == null)
        | {
            path,
            line: (.line // .original_line // 0),
            body: (.body // ""),
            commit_id: (.commit_id // "")
          }
        | @json
      '
  )"

  blocking_reviews="$(
    gh api "repos/$repo/pulls/$pr_number/reviews" --paginate \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
        .[]
        | select(
            .user.login == $bot and
            .submitted_at > $since and
            .state == "CHANGES_REQUESTED"
          )
        | {
            path: "",
            line: 0,
            body: (.body // "CHANGES_REQUESTED review without body"),
            commit_id: (.commit_id // .commitId // "")
          }
        | @json
      '
  )"

  while IFS= read -r comment_json; do
    [ -z "${comment_json:-}" ] && continue
    body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    comment_count=$((comment_count + 1))
    if is_coderabbit_blocking "$body"; then
      blocking_count=$((blocking_count + 1))
      printf '%s\n' "$comment_json" >> "$blocking_lines_file"
    else
      suggestion_count=$((suggestion_count + 1))
    fi
  done <<< "$comments"

  while IFS= read -r review_json; do
    [ -z "${review_json:-}" ] && continue
    body="$(printf '%s\n' "$review_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    comment_count=$((comment_count + 1))
    blocking_count=$((blocking_count + 1))
    printf '%s\n' "$review_json" >> "$blocking_lines_file"
  done <<< "$blocking_reviews"

  if [ "$blocking_count" -gt 0 ]; then
    print_kv RESULT needs_fixes
    reviewer_loop_print_reviewed_head_from_json_lines < "$blocking_lines_file"
    print_kv PLATFORM "$platform"
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "$branch_name"
    print_kv REVIEW_COMMENT_ID ""
    print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
    print_kv COMMENT_COUNT "$comment_count"
    print_kv BLOCKING_COUNT "$blocking_count"
    print_kv SUGGESTION_COUNT "$suggestion_count"
    print_kv CODERABBIT_TRIGGER_ATTEMPTS "$coderabbit_trigger_attempts"
    print_kv CODERABBIT_REVIEWS_RECEIVED "$coderabbit_review_count"
    while IFS= read -r blocking_json; do
      [ -z "${blocking_json:-}" ] && continue
      print_kv "BLOCKING_${index}_PATH" "$(printf '%s\n' "$blocking_json" | jq -r '.path')"
      print_kv "BLOCKING_${index}_LINE" "$(printf '%s\n' "$blocking_json" | jq -r '.line')"
      print_kv_escaped "BLOCKING_${index}_BODY" "$(printf '%s\n' "$blocking_json" | jq -r '.body')"
      index=$((index + 1))
    done < "$blocking_lines_file"
    rm -f "$blocking_lines_file"
    return 1
  fi

  rm -f "$blocking_lines_file"
  coderabbit_thread_gate_clean "$pr_number" "$repo" "$bot_login" "$branch_name"
  cr_phase3_gate_rc=$?
  if [ "$cr_phase3_gate_rc" -ne 0 ]; then
    return "$cr_phase3_gate_rc"
  fi
  print_kv RESULT clean
      {
        [ -n "${comments:-}" ] && printf '%s\n' "$comments"
        [ -n "${existing_comments:-}" ] && printf '%s\n' "$existing_comments"
        [ -n "${blocking_reviews:-}" ] && printf '%s\n' "$blocking_reviews"
        [ -n "${existing_reviews:-}" ] && printf '%s\n' "$existing_reviews"
        [ -n "${reviews:-}" ] && printf '%s\n' "$reviews"
      } | reviewer_loop_print_reviewed_head_from_json_lines
  print_kv PLATFORM "$platform"
  print_kv PR_NUMBER "$pr_number"
  print_kv BRANCH "$branch_name"
  print_kv REVIEW_COMMENT_ID ""
  print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
  print_kv COMMENT_COUNT "$comment_count"
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT "$suggestion_count"
  print_kv CODERABBIT_TRIGGER_ATTEMPTS "$coderabbit_trigger_attempts"
  print_kv CODERABBIT_REVIEWS_RECEIVED "$coderabbit_review_count"
  return 0
}

bot_login_for_platform() {
  # Returns the GitHub bot login for a given review platform name.
  # Used to filter reviewThreads by bot-authored comments only.
  # pr-agent is excluded (returns empty): its blocking signal comes from review state,
  # not inline threads, so mapping it to "github-actions" would incorrectly attribute
  # threads from any other GHA workflow to PR-Agent.
  case "$1" in
    coderabbit)   printf 'coderabbitai\n' ;;
    coderabbit-cli) printf '\n' ;;
    local-ai-reviewer) printf '\n' ;;
    devin)        printf 'devin-ai-integration\n' ;;
    greptile)     printf 'greptile-apps\n' ;;
    pr-agent)     printf '\n' ;;
    codex-github)        printf '%s\n' "${CODEX_GITHUB_BOT_LOGIN:-chatgpt-codex-connector[bot]}" ;;
    claude-code-action)  printf '%s\n' "${CLAUDE_CODE_ACTION_BOT_LOGIN:-claude[bot]}" ;;
    copilot)             printf '%s\n' "${COPILOT_BOT_LOGIN:-copilot-pull-request-reviewer[bot]}" ;;
    haystack)            printf '\n' ;;
    bugbot)              printf '%s\n' "${BUGBOT_BOT_LOGIN:-cursor[bot]}" ;;
    *)                   printf '\n' ;;
  esac
}

check_unresolved_threads() {
  # Enumerate all reviewThreads on a PR via the GitHub GraphQL API (cursor-based
  # pagination), filter to bot-authored threads, and return the count of unresolved
  # threads on stdout as a plain integer.
  #
  # A thread is considered resolved when:
  #   - isResolved=true (GitHub resolved it via the Resolve button / mutation), OR
  #   - isOutdated=true (GitHub marked it stale after a newer commit), OR
  #   - the first comment body contains "✅ Addressed" (bot self-marked it resolved)
  #
  # Only threads whose first comment was authored by a configured bot login are counted.
  # Human-authored threads are ignored.
  #
  # Arguments:
  #   $1    pr_number  - PR number (integer)
  #   $2    repo       - "owner/repo" slug
  #   $3    mode       - "strict" or "provisional" (see below); unrecognized values
  #                       fail safe to "strict"
  #   $4... bot_logins - one or more bot login strings (e.g. "coderabbitai", "devin-ai-integration")
  #
  # Bot logins are passed as individual positional arguments (not space-separated)
  # to ensure safe iteration in the comparison loop without word splitting.
  #
  # mode=provisional (issue #1508): in addition to the strict resolution checks
  # above, a thread is also treated as NOT unresolved when its LAST comment was
  # authored by someone other than a configured bot login (i.e. a maintainer or
  # fixer-agent reply) AND that comment's createdAt is after the PR's current
  # head-commit committedDate. This models "fixed and replied to, but the human/
  # agent has not yet called resolveReviewThread" — the common state immediately
  # after a fixer pushes (see #1508). It exists ONLY to unblock phase-1 gates that
  # decide whether to re-trigger a review; it must never be used by a gate that
  # decides RESULT=clean. Callers making that "declare clean" decision (the
  # aggregate thread gate, coderabbit_thread_gate_clean, and any post-review
  # findings recount) must keep using mode=strict, so a reply alone can never
  # cause a false RESULT=clean — only true GraphQL resolution can.
  #
  # Re-enable errexit within this function. When called from a command substitution
  # with set +e active in the parent (as in the thread gate), the subshell inherits
  # set +e. Without this explicit re-enablement, gh api graphql failures inside this
  # function would be silently ignored and the function would always return exit 0,
  # making the caller's error-handling code unreachable.
  set -e
  local pr_number="$1"
  local repo="$2"
  local mode="$3"
  shift 3
  case "$mode" in
    provisional) ;;
    *) mode="strict" ;;
  esac
  # Remaining positional args are bot login strings; store in an array for safe iteration.
  local -a bot_logins=("$@")

  local owner repo_name
  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

  local unresolved_count=0
  local cursor=""
  local has_next_page="true"
  local page=0
  local max_pages=10
  local head_committed_date=""

  # GraphQL query: paginate reviewThreads 100 at a time, fetch the first comment
  # (aliased firstComment) per thread. In provisional mode, also fetch each
  # thread's last comment (aliased lastComment) and the PR head commit's
  # committedDate, needed for the post-push-reply check above.
  local nodes_fields='id isResolved isOutdated firstComment:comments(first:1){nodes{author{login}body}}'
  local pr_fields=''
  if [ "$mode" = "provisional" ]; then
    nodes_fields="$nodes_fields"'lastComment:comments(last:1){nodes{author{login}body createdAt}}'
    pr_fields='commits(last:1){nodes{commit{committedDate}}}'
  fi
  # Using inline query string to avoid heredoc quoting issues in subshells.
  local graphql_query
  graphql_query='query($owner:String!,$repo:String!,$pr:Int!,$cursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$pr){'"$pr_fields"'reviewThreads(first:100,after:$cursor){pageInfo{hasNextPage endCursor}nodes{'"$nodes_fields"'}}}}}'

  while [ "$has_next_page" = "true" ]; do
    page=$((page + 1))
    if [ "$page" -gt "$max_pages" ]; then
      # Fail-safe: returning exit code 2 (page-cap exceeded) tells the caller to BLOCK
      # the PR rather than degrade — threads past page 10 would be silently ignored,
      # so a very large PR could otherwise be marked ready-for-human-review despite
      # unresolved threads beyond the cap. Exit 3 (below) is for transient GraphQL
      # failures; callers must escalate (not degrade) on exit 3 to prevent RESULT=clean
      # when the thread audit could not be completed.
      echo "WARN: check_unresolved_threads: exceeded $max_pages pages for PR #$pr_number; cannot confirm all threads checked" >&2
      return 2
    fi

    local result
    if [ -n "$cursor" ]; then
      result="$(gh api graphql \
        -f query="$graphql_query" \
        -f owner="$owner" -f repo="$repo_name" -F pr="$pr_number" -f cursor="$cursor" \
        --jq '.data.repository.pullRequest')" \
        || { echo "WARN: check_unresolved_threads: GraphQL query failed for PR #$pr_number" >&2; return 3; }
    else
      result="$(gh api graphql \
        -f query="$graphql_query" \
        -f owner="$owner" -f repo="$repo_name" -F pr="$pr_number" \
        --jq '.data.repository.pullRequest')" \
        || { echo "WARN: check_unresolved_threads: GraphQL query failed for PR #$pr_number" >&2; return 3; }
    fi

    if [ "$mode" = "provisional" ]; then
      head_committed_date="$(printf '%s\n' "$result" | jq -r '.commits.nodes[0].commit.committedDate // ""')"
    fi

    # Use jq -r (not -re) for boolean/nullable fields: jq -e exits non-zero when the
    # output value is false or null, which would misinterpret valid values like
    # hasNextPage=false or isResolved=false as errors. Rely on gh api's own exit code
    # (caught above) for real API failures; use jq -r only for data extraction.
    has_next_page="$(printf '%s\n' "$result" | jq -r '.reviewThreads.pageInfo.hasNextPage')"
    cursor="$(printf '%s\n' "$result" | jq -r '.reviewThreads.pageInfo.endCursor // empty')"

    local thread_json
    while IFS= read -r thread_json; do
      [ -z "${thread_json:-}" ] && continue

      local is_resolved is_outdated author body
      is_resolved="$(printf '%s\n' "$thread_json" | jq -r '.isResolved')"
      is_outdated="$(printf '%s\n' "$thread_json" | jq -r '.isOutdated // false')"
      author="$(printf '%s\n' "$thread_json" | jq -r '.firstComment.nodes[0].author.login // ""')"
      body="$(printf '%s\n' "$thread_json" | jq -r '.firstComment.nodes[0].body // ""')"

      # Only count threads authored by configured bot logins.
      # Bot logins from the GraphQL API do not include the [bot] suffix.
      local is_bot=0
      local bot_login
      for bot_login in "${bot_logins[@]}"; do
        if [ "$author" = "$bot_login" ]; then is_bot=1; break; fi
      done
      [ "$is_bot" -eq 0 ] && continue

      # Thread is resolved if isResolved=true, isOutdated=true, or body contains "✅ Addressed"
      if [ "$is_resolved" = "true" ]; then continue; fi
      if [ "$is_outdated" = "true" ]; then continue; fi
      if printf '%s\n' "$body" | grep -q "✅ Addressed"; then continue; fi

      if [ "$mode" = "provisional" ] && [ -n "$head_committed_date" ]; then
        local last_author last_created_at last_is_bot
        last_author="$(printf '%s\n' "$thread_json" | jq -r '.lastComment.nodes[0].author.login // ""')"
        last_created_at="$(printf '%s\n' "$thread_json" | jq -r '.lastComment.nodes[0].createdAt // ""')"
        last_is_bot=0
        if [ -n "$last_author" ]; then
          for bot_login in "${bot_logins[@]}"; do
            if [ "$last_author" = "$bot_login" ]; then last_is_bot=1; break; fi
          done
        fi
        if [ "$last_is_bot" -eq 0 ] && [ -n "$last_author" ] && [ -n "$last_created_at" ] \
            && [ "$last_created_at" \> "$head_committed_date" ]; then
          local thread_id
          thread_id="$(printf '%s\n' "$thread_json" | jq -r '.id // "unknown"')"
          echo "INFO: check_unresolved_threads: thread $thread_id provisionally addressed (reply by $last_author after head commit $head_committed_date) — not blocking re-review; still requires resolveReviewThread before RESULT=clean" >&2
          continue
        fi
      fi

      unresolved_count=$((unresolved_count + 1))
    done < <(printf '%s\n' "$result" | jq -c '.reviewThreads.nodes[]')

    if [ "$has_next_page" = "true" ] && [ -z "$cursor" ]; then
      echo "WARN: check_unresolved_threads: hasNextPage=true but endCursor is empty for PR #$pr_number; cannot confirm all threads checked" >&2
      return 2
    fi
  done

  printf '%d\n' "$unresolved_count"
}

run_platform_review() {
  local platform="$1"
  local pr_number="$2"
  local branch_name="$3"
  local poll_interval="$4"
  local max_wait="$5"

  case "$platform" in
    greptile)
      run_greptile_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
      ;;
    devin)
      run_devin_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
      ;;
    coderabbit)
      run_coderabbit_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
      ;;
    coderabbit-cli)
      run_coderabbit_cli_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
      ;;
    local-ai-reviewer)
      run_local_ai_reviewer_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
      ;;
    pr-agent)
      run_pr_agent_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
      ;;
    codex-github)
      run_codex_github_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait" "$codex_github_pre_trigger_wait"
      ;;
    claude-code-action)
      run_claude_code_action_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
      ;;
    copilot)
      run_copilot_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
      ;;
    haystack)
      run_haystack_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
      ;;
    bugbot)
      run_bugbot_review "$pr_number" "$branch_name" "$poll_interval" "$max_wait"
      ;;
    *)
      print_kv RESULT skipped
      print_kv PLATFORM "$platform"
      print_kv PR_NUMBER "$pr_number"
      print_kv BRANCH "$branch_name"
      print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
      print_kv REASON unsupported-platform
      print_kv COMMENT_COUNT 0
      print_kv BLOCKING_COUNT 0
      print_kv SUGGESTION_COUNT 0
      return 0
      ;;
  esac
}

# gh_rate_limit_exhausted_reset
#
# Probes `gh api rate_limit` (a check that GitHub explicitly exempts from
# consuming the very quota it reports, so it remains reliable to call even
# when a run has just exhausted its core or graphql budget) and prints the
# epoch reset timestamp of whichever of those two resources currently has
# zero remaining calls. Prints nothing and returns 1 when neither resource
# is exhausted, the probe call itself fails, or the response cannot be
# parsed — a probe failure carries no information either way, so callers
# must treat it the same as "not (confirmably) rate limited", not as proof
# the original failure had some other cause.
#
# Used by ensure_pr_ready_for_ready_phase (issue #1509) to distinguish a
# transient GitHub API/rate-limit outage from a genuine review-gate failure,
# the same way CODERABBIT_SKIP_BANNER_RE (issue #1531) gives a distinct,
# actionable REASON to a distinct failure cause instead of overloading a
# single generic escalation.
gh_rate_limit_exhausted_reset() {
  local rl_json
  if ! rl_json="$(gh api rate_limit 2>/dev/null)"; then
    return 1
  fi

  # The `|| reset=""` guard is load-bearing under `set -e`: this is a plain
  # (unguarded-by-if) assignment, so if jq exits non-zero (e.g. malformed
  # JSON from the probe), the assignment statement's own exit status would
  # otherwise propagate and abort the whole script instead of letting this
  # function fail closed and return 1 like every other parse-failure path
  # here.
  local reset
  reset="$(printf '%s\n' "$rl_json" | jq -r '
      [.resources.core, .resources.graphql]
      | map(select(. != null and .remaining == 0))
      | sort_by(.reset)
      | .[0].reset // empty
    ' 2>/dev/null)" || reset=""

  if [ -z "$reset" ]; then
    return 1
  fi

  printf '%s\n' "$reset"
  return 0
}

# READY_PHASE_GATE_RATE_LIMIT_RESET is set by ensure_pr_ready_for_ready_phase
# (as a plain global, since the function's only current callers use its exit
# code directly rather than command-substituting its stdout) whenever it
# returns 3, carrying the GitHub API rate-limit reset epoch so the caller can
# report it. Cleared at the start of every call so a stale value from a prior
# cycle is never mistaken for this cycle's cause.
READY_PHASE_GATE_RATE_LIMIT_RESET=""

ensure_pr_ready_for_ready_phase() {
  # Ready-phase platforms are intended to run only once draft-compatible GitHub
  # reviewers have cleared. Some external reviewers, including Haystack triage,
  # do not reliably complete while the PR is still draft, so convert the PR to
  # ready before dispatching the first ready-phase platform.
  local pr_number="$1"
  local is_draft

  READY_PHASE_GATE_RATE_LIMIT_RESET=""

  if ! is_draft="$(gh pr view "$pr_number" --json isDraft --jq '.isDraft' 2>/dev/null)"; then
    # Distinguish "GitHub's API was temporarily unavailable/rate-limited" from
    # "this PR genuinely could not be prepared for the ready phase" (issue
    # #1509): probe the rate-limit endpoint before concluding this is an
    # unexplained failure. A confirmed exhaustion returns exit 3 so the caller
    # can report REASON=rate_limited instead of the generic
    # ready_for_review_failed, and skip the reviewer-failed label — the same
    # distinction CODERABBIT_RATE_LIMIT_WAIT/CODERABBIT_SKIP_BANNER_RE draw
    # between an acknowledged vendor quota block and a silent reviewer.
    local rl_reset
    if rl_reset="$(gh_rate_limit_exhausted_reset)"; then
      READY_PHASE_GATE_RATE_LIMIT_RESET="$rl_reset"
      echo "WARN: could not determine draft state for PR #$pr_number before ready phase — GitHub API rate limit exhausted (resets $rl_reset)" >&2
      return 3
    fi
    echo "WARN: could not determine draft state for PR #$pr_number before ready phase" >&2
    return 2
  fi

  if [ "$is_draft" = "true" ]; then
    echo "INFO: converting PR #$pr_number to ready before ready-phase reviewers" >&2
    if ! gh pr ready "$pr_number" >/dev/null 2>&1; then
      local rl_reset_ready
      if rl_reset_ready="$(gh_rate_limit_exhausted_reset)"; then
        READY_PHASE_GATE_RATE_LIMIT_RESET="$rl_reset_ready"
        echo "WARN: failed to mark PR #$pr_number ready before ready phase — GitHub API rate limit exhausted (resets $rl_reset_ready)" >&2
        return 3
      fi
      echo "WARN: failed to mark PR #$pr_number ready before ready phase" >&2
      return 2
    fi
  fi

  return 0
}

ensure_pr_ready_for_after_clean() {
  ensure_pr_ready_for_ready_phase "$@"
}

run_project_advisory_checks() {
  local pr_number_arg="${1:-}"
  local script_path="${2:-$SCRIPT_DIR/run-advisory-checks.sh}"
  local advisory_output=""

  if [ -z "$pr_number_arg" ] || [ ! -f "$script_path" ]; then
    return 0
  fi

  set +e
  advisory_output="$(bash "$script_path" "$pr_number_arg" 2>/dev/null)"
  set -e

  if [ -n "$advisory_output" ]; then
    printf '%s\n' "$advisory_output"
  fi

  return 0
}

# --- Compare-mode helpers ---
# These functions are defined here (before the main execution block) so that
# the test harness can load them via HARNESS_MODE=1 sourcing without executing
# the argument-parsing and main-loop sections below.

# normalize_platform_verdict: map a raw platform result token to one of the six
# canonical compare-mode verdict values: clean, blocking, advisory, waiting, timed out, unavailable.
# $1 = platform_result token (e.g. clean, needs_fixes, skipped, escalate, needs_rerun)
# $2 = full platform output (key=value block; used to inspect REASON for timeout detection)
normalize_platform_verdict() {
  local result="$1"
  local output="${2:-}"
  local reason
  reason="$(kv_value_default REASON "$output" "")"
  if [ "$result" = "clean" ] && [ "$(kv_value_default POLICY_REVIEW_REQUIRED "$output" 0)" = "1" ]; then
    printf 'advisory'
    return
  fi
  case "$result" in
    clean)       printf 'clean' ;;
    needs_fixes) printf 'blocking' ;;
    advisory)    printf 'advisory' ;;
    skipped)     printf 'unavailable' ;;
    needs_rerun) printf 'blocking' ;;
    waiting_on_reviewer) printf 'waiting' ;;
    escalate)
      # Distinguish timeout from service-unavailable via REASON.
      case "$reason" in
        timeout|timed_out|max_wait_exceeded|no_response|rate_limit_max_retries|pending_timeout)
          printf 'timed out' ;;
        *)
          printf 'unavailable' ;;
      esac
      ;;
    *)           printf 'unavailable' ;;
  esac
}

REVIEWER_FAILED_LABEL="reviewer-failed"
REVIEWER_FAILED_LABEL_COLOR="b60205"
REVIEWER_FAILED_LABEL_DESCRIPTION="Automated reviewer platform failed, timed out, or was unavailable"

reviewer_failed_label_required_for_result() {
  local result="$1"
  local reason="${2:-}"

  case "$result" in
    escalate)
      case "$reason" in
        # rate_limited (issue #1509) means the ready-phase gate confirmed a
        # GitHub API rate-limit exhaustion, not a genuine review verdict on
        # the PR — applying reviewer-failed here would blame the PR (and its
        # author) for transient vendor/infrastructure unavailability.
        rate_limited)
          return 1
          ;;
      esac
      return 0
      ;;
    skipped)
      case "$reason" in
        unavailable|timeout|thread-check-failed|pending_timeout|forbidden|unauthorized)
          return 0
          ;;
      esac
      ;;
  esac

  return 1
}

ensure_reviewer_failed_label_exists() {
  if gh label view "$REVIEWER_FAILED_LABEL" >/dev/null 2>&1; then
    return 0
  fi

  if ! gh label create "$REVIEWER_FAILED_LABEL" \
      --color "$REVIEWER_FAILED_LABEL_COLOR" \
      --description "$REVIEWER_FAILED_LABEL_DESCRIPTION" >/dev/null; then
    echo "WARN: failed to create ${REVIEWER_FAILED_LABEL} label; proceeding with reviewer loop" >&2
  fi

  return 0
}

pr_has_reviewer_failed_label() {
  local pr_number_arg="$1"
  local labels

  if ! labels="$(gh pr view "$pr_number_arg" --json labels --jq '.labels[].name' 2>/dev/null)"; then
    return 2
  fi

  printf '%s\n' "$labels" | grep -Fxq "$REVIEWER_FAILED_LABEL"
}

sync_reviewer_failed_label() {
  local pr_number_arg="$1"
  local required="$2"
  local label_check_status

  [ -n "${pr_number_arg:-}" ] || return 0

  if [ "$required" = "1" ]; then
    ensure_reviewer_failed_label_exists
    if ! gh pr edit "$pr_number_arg" --add-label "$REVIEWER_FAILED_LABEL" >/dev/null; then
      echo "WARN: failed to apply ${REVIEWER_FAILED_LABEL} label to PR #${pr_number_arg}; proceeding with reviewer loop" >&2
    fi
  else
    label_check_status=1
    if pr_has_reviewer_failed_label "$pr_number_arg"; then
      label_check_status=0
    else
      label_check_status=$?
    fi
    if [ "$label_check_status" -eq 1 ]; then
      return 0
    fi
    if ! gh pr edit "$pr_number_arg" --remove-label "$REVIEWER_FAILED_LABEL" >/dev/null; then
      echo "WARN: failed to remove ${REVIEWER_FAILED_LABEL} label from PR #${pr_number_arg}; proceeding with reviewer loop" >&2
    fi
  fi

  return 0
}

# append_compare_metrics_row: append one structured row to the platform metrics log.
# Called at the end of the platform loop when compare_mode=1.
# $1 = pr_number
# $2 = branch_name
# $3 = overall_result (the aggregate after all platforms ran)
# Remaining args: pairs of platform_name verdict_token (e.g. coderabbit blocking greptile clean)
append_compare_metrics_row() {
  local pr_number_arg="$1"
  local branch_name_arg="$2"
  local overall_result_arg="$3"
  shift 3

  local metrics_file
  metrics_file="$(workflow_repo_root)/docs/workflow/retro-metrics-platforms.md"

  # Derive branch type from the branch name prefix.
  local branch_type
  case "$branch_name_arg" in
    feature/*)            branch_type="feature" ;;
    fix/*)                branch_type="fix" ;;
    refactor/*)           branch_type="refactor" ;;
    hotfix/*)             branch_type="hotfix" ;;
    spec/*)               branch_type="spec" ;;
    implementation-plan/*) branch_type="plan" ;;
    *)                    branch_type="other" ;;
  esac

  # Collect pairs: platform_names and verdict_tokens in order.
  local -a platform_names=()
  local -a verdict_tokens=()
  while [ "$#" -ge 2 ]; do
    platform_names+=("$1")
    verdict_tokens+=("$2")
    shift 2
  done

  # Build dynamic platform-column headers from the current run's platform list.
  local header_platform_cols=""
  for _pname in "${platform_names[@]}"; do
    header_platform_cols="${header_platform_cols} ${_pname} |"
  done
  local separator_platform_cols=""
  for _pname in "${platform_names[@]}"; do
    separator_platform_cols="${separator_platform_cols}---|"
  done

  # Create the file with the full header when it does not yet exist.
  # If the file exists (e.g. pre-created with prose only) but has no table header
  # row yet (detected by absence of the "|---|" separator line), append the table
  # header rows so the Markdown table is valid before the first data row.
  if [ ! -f "$metrics_file" ]; then
    cat > "$metrics_file" <<METRICS_HEADER
# Platform Comparison Metrics Log

This file is append-only. One row is appended per compare-mode reviewer loop run.
Do not delete or rewrite existing rows. The "Block Was Real Bug?" column may be
filled in manually after a run when post-hoc analysis determines whether a
platform-exclusive blocking finding corresponded to a real code defect.

## Graduation Criteria

A platform may be considered safe for removal when, across 30 or more consecutive
compare-mode runs covering at least one run each of \`fix\`, \`feature\`, and \`refactor\`
branch types, it has zero platform-exclusive blocking findings (runs where that
platform blocked but at least one other configured platform was clean).

Fewer than 30 runs is always insufficient data for a graduation decision.

## Metrics Table

| PR | Branch Type |${header_platform_cols} Overall Result | Block Was Real Bug? |
|---|---|${separator_platform_cols}---|---|
METRICS_HEADER
  elif ! grep -q '^|---|' "$metrics_file" 2>/dev/null; then
    # File exists but has no table separator row — append the table header now.
    # Ensure there is a blank line before the table if the file has content.
    if [ -s "$metrics_file" ]; then
      printf '\n' >> "$metrics_file"
    fi
    printf '| PR | Branch Type |%s Overall Result | Block Was Real Bug? |\n' \
      "$header_platform_cols" >> "$metrics_file"
    printf '|---|---|%s---|---|\n' \
      "$separator_platform_cols" >> "$metrics_file"
  else
    # File exists and already has a table. Check whether the current platform
    # set matches the existing header. If not, insert a separator comment row
    # before appending the data row so human readers can see the config changed.
    # Detection: compare platform names (and order) by parsing the header row
    # above the last separator row. A count-only check misses platform renames
    # or reordering with the same count.
    # Column order: PR, Branch Type, <platforms...>, Overall Result, Block Was Real Bug?
    # Fixed columns = 4 (PR, Branch Type, Overall Result, Block Was Real Bug?)
    existing_sep_row="$(grep '^|---|' "$metrics_file" | tail -1)"
    existing_platform_col_count=$(printf '%s' "$existing_sep_row" | tr -cd '|' | wc -c | tr -d ' ')
    # pipe count = platform_cols + 4 fixed cols + 1 leading pipe → total pipes = platform_cols + 5
    existing_platform_count=$(( existing_platform_col_count - 5 ))
    current_platform_count="${#platform_names[@]}"
    # Parse platform names from the header row above the last separator row.
    existing_sep_line_num="$(grep -n '^|---|' "$metrics_file" | tail -1 | cut -d: -f1)"
    existing_header_row="$(sed -n "$(( existing_sep_line_num - 1 ))p" "$metrics_file")"
    # awk splits by |: field 1=empty, 2=PR, 3=Branch Type, 4..NF-3=platforms, NF-2=Overall Result, NF-1=Block Was Real Bug?, NF=empty
    existing_platform_str="$(printf '%s' "$existing_header_row" | awk -F'|' '{
      sep=""
      for (i = 4; i <= NF - 3; i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", $i)
        printf "%s%s", sep, $i
        sep = ","
      }
    }')"
    current_platform_str="$(IFS=,; printf '%s' "${platform_names[*]}")"
    if [ "$current_platform_count" -ne "$existing_platform_count" ] || [ "$existing_platform_str" != "$current_platform_str" ]; then
      # Platform configuration changed: insert an annotation row (in the OLD layout
      # so it is a valid row for that table) then write a new header block for the
      # new layout so subsequent rows are correctly labeled.
      # Build blank cells matching the EXISTING header's column count.
      _sep_blank_cols=""
      _sep_i=0
      while [ "$_sep_i" -lt $(( existing_platform_count + 3 )) ]; do
        _sep_blank_cols="${_sep_blank_cols} |"
        _sep_i=$(( _sep_i + 1 ))
      done
      printf '| *(platforms changed: %s)* |%s\n' \
        "$(IFS=,; printf '%s' "${platform_names[*]}")" \
        "$_sep_blank_cols" \
        >> "$metrics_file"
      # New header block for the updated platform layout.
      printf '\n| PR | Branch Type |%s Overall Result | Block Was Real Bug? |\n' \
        "$header_platform_cols" >> "$metrics_file"
      printf '|---|---|%s---|---|\n' \
        "$separator_platform_cols" >> "$metrics_file"
    fi
  fi

  # Build the verdict columns for this row.
  local row_verdict_cols=""
  for _vtoken in "${verdict_tokens[@]}"; do
    row_verdict_cols="${row_verdict_cols} ${_vtoken} |"
  done

  # Append one row.
  printf '| #%s | %s |%s %s | |\n' \
    "$pr_number_arg" \
    "$branch_type" \
    "$row_verdict_cols" \
    "$overall_result_arg" \
    >> "$metrics_file"
}

# restore_regression_label_if_missing — Step 7b regression-label auto-restore.
# Re-applies the ready-for-regression label at the start of every pr-review-loop.sh
# invocation for implementation branches so the label is always present when the CI
# loop (Step 8) begins — eliminating the recurring manual re-application pattern.
#
# Arguments:
#   $1  pr_number   — numeric PR number
#   $2  branch_name — full branch ref (e.g. fix/805-slug)
#
# Behaviour:
#   - Runs only for feature/*, fix/*, refactor/*, hotfix/* branches.
#   - Checks current label state via `gh pr view --json labels`.
#     On gh failure the check is skipped (fail-open; WARN emitted to stderr).
#   - When the label is absent, gates the restore on current-head clean-loop
#     evidence from the newest "Automated Reviewer Loop Summary" comment:
#       • latest summary result clean/skipped + head_sha matches current PR head
#         → RESTORE.
#       • no summary, stale-head summary, non-clean summary, or unreadable
#         summary history → do NOT restore.
#     This keeps the helper aligned with the PR policy workflow: a historical
#     clean summary must not resurrect ready-for-regression after later pushes
#     introduce reviewer findings.
#   - If the comment-presence query fails (gh/API error): fail-open — the restore
#     IS attempted and a WARN is emitted. This mirrors the higher-frequency
#     real-world failure (#805) being more harmful than a spurious re-apply.
#   - The operation is idempotent: if the label is already present, gh pr edit
#     --add-label is a documented no-op.
#   - Marker: "### Automated Reviewer Loop Summary" (author-agnostic; the comment
#     is posted by the maintainer's gh token when run locally, not necessarily by
#     a bot account). Do NOT scope by [bot] — that silently misses local-run cases.
#
# Returns 0 in all cases (best-effort; never aborts the caller).
restore_regression_label_if_missing() {
  local pr_number="$1"
  local branch_name="$2"
  case "${branch_name:-}" in
    feature/*|fix/*|refactor/*|hotfix/*)
      local _rfr_has_label=""
      # pipefail is needed here: if gh fails, jq would still see empty input and
      # output "false", causing a spurious re-apply. Use command substitution with
      # explicit exit-code capture instead, equivalent to pipefail on a single-stage
      # pipeline (gh --jq is one command, not a pipe).
      if ! _rfr_has_label="$(gh pr view "$pr_number" --json labels \
          --jq '[.labels[].name] | any(. == "ready-for-regression")')"; then
        echo "WARN: gh pr view failed for regression-label auto-restore (PR ${pr_number}); skipping" >&2
        return 0
      fi
      if [ "${_rfr_has_label:-}" = "false" ]; then
        # Gate the restore on current-head clean-loop evidence. A historical
        # clean summary on an older head must not resurrect a stale label after
        # a push that introduced reviewer findings.
        local _rfr_repo=""
        # repo_slug failure is handled explicitly below: an empty slug falls
        # into the else branch (fail-open WARN + restore). Do not use || true
        # here — capture the exit code and let the if-condition detect the
        # empty string rather than masking the failure.
        if ! _rfr_repo="$(repo_slug 2>/dev/null)"; then
          _rfr_repo=""
        fi
        local _rfr_current_head_sha=""
        if ! _rfr_current_head_sha="$(gh pr view "$pr_number" --json headRefOid --jq '.headRefOid // ""' 2>/dev/null)" \
            || [ -z "${_rfr_current_head_sha:-}" ]; then
          echo "WARN: could not resolve current head for ready-for-regression restore on PR #${pr_number}; skipping restore." >&2
          return 0
        fi
        local _rfr_latest_summary_record=""
        local _rfr_latest_summary_body=""
        local _rfr_latest_summary_json=""
        local _rfr_latest_summary_result=""
        local _rfr_latest_summary_head=""
        local _rfr_restore_allowed=0
        local _rfr_restore_reason="current-head clean reviewer-loop summary found"
        local _rfr_comments_raw=""
        if [ -n "${_rfr_repo:-}" ] && _rfr_comments_raw="$(gh api \
            "repos/${_rfr_repo}/issues/${pr_number}/comments" \
            --paginate 2>/dev/null)"; then
          _rfr_latest_summary_record="$(printf '%s\n' "$_rfr_comments_raw" \
            | reviewer_loop_history_select_latest_summary_record 2>/dev/null)" || _rfr_latest_summary_record=""
          if [ -n "${_rfr_latest_summary_record:-}" ]; then
            _rfr_latest_summary_body="$(printf '%s\n' "$_rfr_latest_summary_record" \
              | jq -r '.body // ""' 2>/dev/null)" || _rfr_latest_summary_body=""
          fi
          if [ -n "${_rfr_latest_summary_body:-}" ]; then
            _rfr_latest_summary_json="$(printf '%s\n' "$_rfr_latest_summary_body" \
              | reviewer_loop_history_extract_latest_json 2>/dev/null)" || _rfr_latest_summary_json=""
          fi
          if [ -n "${_rfr_latest_summary_json:-}" ]; then
            _rfr_latest_summary_result="$(printf '%s\n' "$_rfr_latest_summary_json" \
              | jq -r '(.entries // []) | last | .result // ""' 2>/dev/null)" || _rfr_latest_summary_result=""
            _rfr_latest_summary_head="$(printf '%s\n' "$_rfr_latest_summary_json" \
              | jq -r '(.entries // []) | last | .head_sha // ""' 2>/dev/null)" || _rfr_latest_summary_head=""
          fi
          if { [ "${_rfr_latest_summary_result:-}" = "clean" ] \
              || [ "${_rfr_latest_summary_result:-}" = "skipped" ]; } \
              && [ -n "${_rfr_latest_summary_head:-}" ] \
              && [ "${_rfr_latest_summary_head:-}" = "${_rfr_current_head_sha:-}" ]; then
            _rfr_restore_allowed=1
          fi
        else
          echo "WARN: gh api failed for summary-comment gate on PR ${pr_number}; failing open — restoring label." >&2
          _rfr_restore_allowed=1
          _rfr_restore_reason="summary-comment lookup failed; fail-open restore"
        fi
        if [ "${_rfr_restore_allowed:-0}" -eq 1 ]; then
          echo "INFO: ready-for-regression label missing on PR #${pr_number} (${branch_name}); ${_rfr_restore_reason} — restoring before loop runs." >&2
          # Do NOT redirect stderr here: surface gh errors so failures are observable
          # rather than silently swallowed. The || branch handles the non-zero exit.
          if ! gh pr edit "$pr_number" --add-label "ready-for-regression"; then
            echo "WARN: failed to restore ready-for-regression label on PR #${pr_number}; proceeding without it" >&2
          fi
        else
          echo "INFO: ready-for-regression label missing on PR #${pr_number} (${branch_name}); no current-head clean reviewer-loop summary found — skipping restore." >&2
        fi
      fi
      ;;
  esac
  return 0
}

doc_branch_default_max_wait() {
  local configured="${PR_REVIEW_LOOP_DOC_MAX_WAIT:-180}"
  if ! [[ "$configured" =~ ^[1-9][0-9]*$ ]]; then
    echo "WARN: PR_REVIEW_LOOP_DOC_MAX_WAIT must be a positive integer; defaulting to 180" >&2
    configured=180
  fi
  printf '%s\n' "$configured"
}

doc_branch_default_poll_interval() {
  local max_wait="$1"
  local interval=30
  if [ "$interval" -ge "$max_wait" ]; then
    interval=$((max_wait / 2))
    [ "$interval" -lt 1 ] && interval=1
  fi
  printf '%s\n' "$interval"
}

codex_github_default_max_wait() {
  local configured="${CODEX_GITHUB_MAX_WAIT:-1800}"
  if ! [[ "$configured" =~ ^[1-9][0-9]*$ ]]; then
    echo "WARN: CODEX_GITHUB_MAX_WAIT must be a positive integer; defaulting to 1800" >&2
    configured=1800
  fi
  printf '%s\n' "$configured"
}

codex_github_default_poll_interval() {
  local configured="${CODEX_GITHUB_POLL_INTERVAL:-60}"
  local max_wait="$1"
  if ! [[ "$configured" =~ ^[1-9][0-9]*$ ]]; then
    echo "WARN: CODEX_GITHUB_POLL_INTERVAL must be a positive integer; defaulting to 60" >&2
    configured=60
  fi
  if [ "$configured" -ge "$max_wait" ]; then
    configured=$((max_wait / 2))
    [ "$configured" -lt 1 ] && configured=1
  fi
  printf '%s\n' "$configured"
}

codex_github_defaults_should_apply() {
  array_contains_value "codex-github" "${platforms[@]:-}"
}

REVIEWER_LOOP_HISTORY_SCHEMA="reviewer_loop_history.v1"
REVIEWER_LOOP_HISTORY_MARKER="<!-- reviewer-loop-history:v1 -->"

reviewer_loop_history_extract_latest_json() {
  awk -v marker="$REVIEWER_LOOP_HISTORY_MARKER" '
    index($0, marker) > 0 {
      seen_marker = 1
      in_json = 0
      block = ""
      next
    }
    seen_marker && $0 ~ /^```json[[:space:]]*$/ {
      in_json = 1
      block = ""
      next
    }
    in_json && $0 ~ /^```[[:space:]]*$/ {
      latest = block
      in_json = 0
      seen_marker = 0
      next
    }
    in_json {
      block = block $0 "\n"
    }
    END {
      printf "%s", latest
    }
  '
}

reviewer_loop_history_platforms_json() {
  local platform_list="${1:-}"

  printf '%s\n' "$platform_list" |
    jq -R -s -c 'split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0 and . != "none"))'
}

# Tier 1 fail-closed guard (#1652): a blocking finding on a normative document
# is never small, whatever its wording. Consulted from
# reviewer_loop_path_is_non_shipped_artifact before the existing patterns so
# normative paths are excluded from the non-shipped (small-findings) set.
reviewer_loop_path_is_normative_document() {
  case "${1:-}" in
    REVIEW.md|AGENTS.md|CLAUDE.md|GEMINI.md|LLM_RULES.md|.ai-dev-workflow.yaml)
      return 0 ;;
    docs/workflow/*|docs/best-practices/*|docs/specs/developments/*|docs/testing/workflow/*|docs/project/*)
      return 0 ;;
  esac
  return 1
}

reviewer_loop_path_is_non_shipped_artifact() {
  local path="${1:-}"

  # Normative documents are never treated as small-finding (non-shipped) paths.
  if reviewer_loop_path_is_normative_document "$path"; then
    return 1
  fi

  case "$path" in
    ""|docs/*|test/*|tests/*|fixtures/*|fixture/*|__fixtures__/*|__tests__/*|*.md|*.mdx|test-*|*.snap)
      return 0
      ;;
  esac

  case "$path" in
    */docs/*|*/test/*|*/tests/*|*/fixtures/*|*/fixture/*|*/__fixtures__/*|*/__tests__/*|*/test-*|*/snapshots/*)
      return 0
      ;;
  esac

  return 1
}

# Tier 2 escalation (#1652): allow-list of contract-bearing surfaces as ordered
# (identity, pattern) pairs. Prints the matched surface identity and returns
# success; prints nothing and returns failure on no match. First match in table
# order wins. Every pattern is a phrase or qualified form — bare common words
# (gate, scope, state, status, proof, parse, contract) are deliberately absent.
# Separators are literal, never the regex wildcard ".".
REVIEWER_LOOP_CONTRACT_SURFACES=(
  'acceptance_criteria|acceptance criterion|acceptance criteria|AC-[0-9]+'
  'decision_gates_and_matrices|decision gate|decision matrix|matrix row|readiness gate|gate condition|gating'
  'parser_and_input_behavior|parser|regex|input surface|word boundary'
  'scope_and_coverage|out of scope|in scope|scope creep|coverage matrix|brief objective'
  'fail_closed_semantics|fail-closed|fail closed|allow-list|deny-list|vacuous'
  'state_and_status_models|state machine|state table|evidence state|valid transition|status label|status transition'
  'telemetry_and_contracts|telemetry|stdout key|key=value contract|output contract'
  'proof_obligations|planted-violation|planted violation|proof obligation'
)

# Case-insensitive word-boundary match via POSIX ERE character classes — never
# \b (GNU/PCRE only; BSD grep on stock macOS does not recognise it).
reviewer_loop_finding_touches_contract_surface() {
  local body="${1:-}"
  local entry identity pattern

  [ -n "${body//[[:space:]]/}" ] || return 1

  for entry in "${REVIEWER_LOOP_CONTRACT_SURFACES[@]}"; do
    identity="${entry%%|*}"
    pattern="${entry#*|}"
    if printf '%s' "$body" \
      | grep -Eqi "(^|[^[:alnum:]_])(${pattern})([^[:alnum:]_]|\$)"; then
      printf '%s\n' "$identity"
      return 0
    fi
  done

  return 1
}

reviewer_loop_small_findings_required_rounds() {
  local configured="${PR_REVIEW_LOOP_SMALL_FINDINGS_STOP_ROUNDS:-2}"

  if ! [[ "$configured" =~ ^[1-9][0-9]*$ ]] || [ "$configured" -gt 999 ]; then
    echo "WARN: PR_REVIEW_LOOP_SMALL_FINDINGS_STOP_ROUNDS must be an integer from 1-999; defaulting to 2" >&2
    configured=2
  fi

  printf '%s\n' "$configured"
}

reviewer_loop_blocking_paths_from_output() {
  local output="${1:-}"
  local blocking_count="${2:-0}"
  local index
  local path

  [[ "$blocking_count" =~ ^[0-9]+$ ]] || blocking_count=0
  [ "$blocking_count" -gt 0 ] || return 0

  for index in $(seq 1 "$blocking_count"); do
    path="$(kv_value_default "BLOCKING_${index}_PATH" "$output" "")"
    [ -n "$path" ] && printf '%s\n' "$path"
  done
}

# Emit one compact JSON finding object per blocking finding (#1652).
# Platform is a third argument from the caller's platform_name — reviewer
# output carries no per-finding platform key. Does not skip empty paths:
# all_findings_are_small fail-closes on them. Bodies are stored as received;
# newline-sequence normalisation happens only at match time.
reviewer_loop_blocking_findings_from_output() {
  local output="${1:-}"
  local blocking_count="${2:-0}"
  local platform="${3:-}"
  local index path body

  [[ "$blocking_count" =~ ^[0-9]+$ ]] || blocking_count=0
  [ "$blocking_count" -gt 0 ] || return 0

  for index in $(seq 1 "$blocking_count"); do
    path="$(kv_value_default "BLOCKING_${index}_PATH" "$output" "")"
    body="$(kv_value_default "BLOCKING_${index}_BODY" "$output" "")"
    jq -c -n \
      --arg path "$path" \
      --arg platform "$platform" \
      --arg body "$body" \
      '{path: $path, platform: $platform, body: $body}'
  done
}

# Normalise a finding body for contract-surface matching only (#1652).
# local-ai-reviewer emits real newlines as the two-character sequence \n
# without escaping pre-existing backslashes — lossy and not reversible.
# Replacing \n with a space restores word boundaries for matching without
# claiming to decode. Never used for storage.
reviewer_loop_normalize_finding_body_for_match() {
  local body="${1:-}"
  # Replace every literal two-character sequence \n with a space.
  printf '%s' "${body//\\n/ }"
}

# --- Missed-finding telemetry helpers (#1651) -------------------------------

# reviewer_loop_commit_ancestry <clean_head> <reviewed_head>
# Prints exactly one of: same | ancestor | descendant | unrelated | undecidable
# Under set -e, every merge-base status is captured with || status=$?.
reviewer_loop_commit_ancestry() {
  local clean="${1:-}" reviewed="${2:-}" status

  [ -n "$clean" ] && [ -n "$reviewed" ] || { printf 'undecidable\n'; return 0; }

  # Existence BEFORE equality: two identical missing SHAs are undecidable, not same.
  git cat-file -e "${clean}^{commit}" 2>/dev/null || { printf 'undecidable\n'; return 0; }
  git cat-file -e "${reviewed}^{commit}" 2>/dev/null || { printf 'undecidable\n'; return 0; }

  [ "$clean" = "$reviewed" ] && { printf 'same\n'; return 0; }

  status=0
  git merge-base --is-ancestor "$clean" "$reviewed" >/dev/null 2>&1 || status=$?
  [ "$status" -eq 0 ] && { printf 'ancestor\n'; return 0; }
  [ "$status" -ne 1 ] && { printf 'undecidable\n'; return 0; }

  status=0
  git merge-base --is-ancestor "$reviewed" "$clean" >/dev/null 2>&1 || status=$?
  [ "$status" -eq 0 ] && { printf 'descendant\n'; return 0; }
  [ "$status" -ne 1 ] && { printf 'undecidable\n'; return 0; }

  printf 'unrelated\n'
}

# Normalize a companion-script RESULT/REASON pair into the stored platform_results
# outcome. Prints: clean|needs_fixes|unavailable|not_configured|skipped|unknown
reviewer_loop_normalize_platform_outcome() {
  local raw_result="${1:-}"
  local raw_reason="${2:-}"

  case "$raw_result" in
    clean) printf 'clean\n' ;;
    needs_fixes) printf 'needs_fixes\n' ;;
    skipped)
      case "$raw_reason" in
        unavailable) printf 'unavailable\n' ;;
        not_configured) printf 'not_configured\n' ;;
        *) printf 'skipped\n' ;;
      esac
      ;;
    escalate) printf 'unavailable\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

# Build one compact platform_results JSON object from raw RESULT/REASON.
reviewer_loop_platform_result_record_json() {
  local platform="${1:-}"
  local raw_result="${2:-}"
  local raw_reason="${3:-}"
  local normalized

  normalized="$(reviewer_loop_normalize_platform_outcome "$raw_result" "$raw_reason")"
  jq -nc \
    --arg platform "$platform" \
    --arg result "$normalized" \
    --arg raw_result "$raw_result" \
    --arg raw_reason "$raw_reason" \
    '{platform: $platform, result: $result, raw_result: $raw_result, raw_reason: $raw_reason}'
}

# reviewer_loop_replace_current_round_platform_record <platform_name>
#
# Drop prior current-round records for one platform so a second local pass (#1656)
# replaces stale first-pass evidence instead of appending beside it.
reviewer_loop_replace_current_round_platform_record() {
  local platform_name="${1:-}"
  local entry record kept_heads=() kept_records=() kept_peer=() kept_tokens=()
  local blocking_name kept_blocking=()

  [ -n "$platform_name" ] || return 0

  if declare -p platform_reviewed_heads >/dev/null 2>&1 \
      && [ "${#platform_reviewed_heads[@]}" -gt 0 ]; then
    for entry in "${platform_reviewed_heads[@]}"; do
      if [ "${entry%%:*}" != "$platform_name" ]; then
        kept_heads+=("$entry")
      fi
    done
    platform_reviewed_heads=("${kept_heads[@]+"${kept_heads[@]}"}")
  fi

  if declare -p platform_result_records >/dev/null 2>&1 \
      && [ "${#platform_result_records[@]}" -gt 0 ]; then
    for record in "${platform_result_records[@]}"; do
      if [ "$(printf '%s' "$record" | jq -r '.platform // ""')" != "$platform_name" ]; then
        kept_records+=("$record")
      fi
    done
    platform_result_records=("${kept_records[@]+"${kept_records[@]}"}")
  fi

  if declare -p platform_peer_evidence >/dev/null 2>&1 \
      && [ "${#platform_peer_evidence[@]}" -gt 0 ]; then
    for entry in "${platform_peer_evidence[@]}"; do
      if [ "${entry%%|*}" != "$platform_name" ]; then
        kept_peer+=("$entry")
      fi
    done
    platform_peer_evidence=("${kept_peer[@]+"${kept_peer[@]}"}")
  fi

  if declare -p platform_result_tokens >/dev/null 2>&1 \
      && [ "${#platform_result_tokens[@]}" -gt 0 ]; then
    for entry in "${platform_result_tokens[@]}"; do
      if [ "${entry%%:*}" != "$platform_name" ]; then
        kept_tokens+=("$entry")
      fi
    done
    platform_result_tokens=("${kept_tokens[@]+"${kept_tokens[@]}"}")
  fi

  if declare -p platform_blocking_outputs >/dev/null 2>&1 \
      && [ "${#platform_blocking_outputs[@]}" -gt 0 ]; then
    for entry in "${platform_blocking_outputs[@]}"; do
      blocking_name="${entry%%$'\036'*}"
      if [ "$blocking_name" != "$platform_name" ]; then
        kept_blocking+=("$entry")
      fi
    done
    platform_blocking_outputs=("${kept_blocking[@]+"${kept_blocking[@]}"}")
  fi
}

# reviewer_loop_local_latest_verdict <history_payload> <configured_platforms>
# configured_platforms is newline-delimited. Membership uses grep -Fxq here-string.
# When the current invocation filters platforms (--platform), prior PR history can
# still contain local-ai-reviewer verdicts; consult history before not_configured.
reviewer_loop_local_latest_verdict() {
  local payload="${1:-}"
  local configured="${2:-}"

  if ! grep -Fxq -- 'local-ai-reviewer' <<<"$configured"; then
    if ! printf '%s' "$payload" | jq -e '
        (.entries // [])[]
        | (.platform_results // [])[]
        | select(.platform == "local-ai-reviewer")
      ' >/dev/null 2>&1; then
      printf '{"outcome":"not_configured","head_sha":"","iteration":0}\n'
      return 0
    fi
  fi

  printf '%s' "$payload" | jq -c '
    (.entries // []) as $entries
    | [ $entries[]
        | . as $entry
        | ((.platform_results // [])[]
           | select(.platform == "local-ai-reviewer")
           | {outcome: (.result // "unknown"),
              head_sha: (
                ($entry.reviewed_heads // [])
                | map(select(.platform == "local-ai-reviewer"))
                | last
                | .reviewed_head // ""
              ),
              iteration: ($entry.iteration // 0)})
      ] as $local_verdicts
    | if ($local_verdicts | length) > 0 then
        ($local_verdicts | sort_by(.iteration) | last)
      elif [ $entries[]
          | select(
              ((.platforms // []) | index("local-ai-reviewer")) != null
              or any(.reviewed_heads[]?; .platform == "local-ai-reviewer")
            )
        ] | length > 0 then
        {outcome: "unknown", head_sha: "", iteration: 0}
      else
        {outcome: "not_yet_run", head_sha: "", iteration: 0}
      end
    | if .outcome == "not_configured" then .outcome = "unavailable" else . end'
}

# reviewer_loop_repo_configured_platforms
#
# Newline-delimited repository-configured review.on_draft.runner platforms,
# resolved unconditionally from the workflow config — never from the
# invocation-filtered platforms[] array (#1656).
reviewer_loop_repo_configured_platforms() {
  local line
  if declare -p repo_review_platforms >/dev/null 2>&1 \
      && [ "${#repo_review_platforms[@]}" -gt 0 ]; then
    for line in "${repo_review_platforms[@]}"; do
      line="$(trim "$line")"
      [ -n "$line" ] && printf '%s\n' "$line"
    done
    return 0
  fi
  local cfg="${config_file:-$(workflow_config_file)}"
  if [ ! -f "$cfg" ]; then
    return 0
  fi
  while IFS= read -r line; do
    line="$(trim "$line")"
    [ -n "$line" ] && printf '%s\n' "$line"
  done < <(WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 workflow_config_review_platforms "$cfg")
}

# reviewer_loop_compose_current_round_payload <history_payload> <iteration>
reviewer_loop_compose_current_round_payload() {
  local history_payload="${1:-{\}}"
  local iteration="${2:-0}"
  local results_json heads_json

  results_json='[]'
  if declare -p platform_result_records >/dev/null 2>&1 \
      && [ "${#platform_result_records[@]}" -gt 0 ]; then
    results_json="$(printf '%s\n' "${platform_result_records[@]}" | jq -s -c '.')"
  fi

  if declare -p platform_reviewed_heads >/dev/null 2>&1 \
      && [ "${#platform_reviewed_heads[@]}" -gt 0 ]; then
    heads_json="$(reviewer_loop_head_evidence_json "${loop_head_sha:-}" "${platform_reviewed_heads[@]}")"
  else
    heads_json="$(reviewer_loop_head_evidence_json "${loop_head_sha:-}")"
  fi

  printf '%s' "${history_payload:-{\}}" | jq -c \
    --argjson iteration "$iteration" \
    --argjson results "$results_json" \
    --argjson heads "$heads_json" \
    '
      . as $root
      | ($root.entries // []) as $entries
      | $root
      | .schema = (.schema // "reviewer_loop_history.v1")
      | .entries = ($entries + [{
          iteration: $iteration,
          platform_results: $results,
          reviewed_heads: $heads
        }])
    '
}

# reviewer_loop_prior_history_payload_from_pr <pr_number>
reviewer_loop_prior_history_payload_from_pr() {
  local pr_number_arg="${1:-}"
  local repo="" record="" body="" json="" payload=""

  if [ -z "$pr_number_arg" ]; then
    printf '%s\n' '{"schema":"reviewer_loop_history.v1","entries":[]}'
    return 0
  fi
  if ! repo="$(repo_slug 2>/dev/null)" || [ -z "$repo" ]; then
    jq -nc --arg schema "$REVIEWER_LOOP_HISTORY_SCHEMA" \
      '{schema: $schema, history_status: "unavailable", history_unavailable_reason: "repo_unavailable", entries: []}'
    return 0
  fi
  if ! record="$(
    set -o pipefail
    gh api "repos/$repo/issues/$pr_number_arg/comments" --paginate 2>/dev/null \
      | reviewer_loop_history_select_latest_summary_record
  )"; then
    jq -nc --arg schema "$REVIEWER_LOOP_HISTORY_SCHEMA" \
      '{schema: $schema, history_status: "unavailable", history_unavailable_reason: "comment_fetch_failed", entries: []}'
    return 0
  fi
  body="$(printf '%s\n' "$record" | jq -r '.body // ""' 2>/dev/null)" || body=""
  json="$(printf '%s' "$body" | reviewer_loop_history_extract_latest_json)"
  if [ -n "$json" ] \
      && payload="$(printf '%s' "$json" | jq -c '.' 2>/dev/null)" \
      && printf '%s' "$payload" | jq -e --arg schema "$REVIEWER_LOOP_HISTORY_SCHEMA" \
        '.schema == $schema and ((.entries | type) == "array")' >/dev/null 2>&1; then
    printf '%s\n' "$payload"
    return 0
  fi
  if printf '%s' "$body" | grep -Fq "$REVIEWER_LOOP_HISTORY_MARKER"; then
    jq -nc --arg schema "$REVIEWER_LOOP_HISTORY_SCHEMA" \
      '{schema: $schema, history_status: "unavailable", history_unavailable_reason: "prior_unavailable", entries: []}'
    return 0
  fi
  printf '%s\n' '{"schema":"reviewer_loop_history.v1","entries":[]}'
}

# reviewer_loop_local_second_pass_failed_for_head <history_payload> <head_sha>
reviewer_loop_local_second_pass_failed_for_head() {
  local payload="${1:-}" head="${2:-}"
  printf '%s' "$payload" | jq -r --arg head "$head" '
    [(.entries // [])[]
      | select((.local_second_pass_failed_head // "") == $head)
    ] | length
  '
}

# reviewer_loop_local_pass_required <history_payload> <loop_head_sha> <configured_platforms>
reviewer_loop_local_pass_required() {
  local payload="${1:-}" head="${2:-}" configured="${3:-}"
  local verdict outcome verdict_head

  # Honor the repository configured list before #1651's selector: history can still
  # name local-ai-reviewer even when this repository no longer configures it.
  if ! grep -Fxq -- 'local-ai-reviewer' <<<"$configured"; then
    printf 'no_local_reviewer\n'
    return 0
  fi

  verdict="$(reviewer_loop_local_latest_verdict "$payload" "$configured")"
  outcome="$(printf '%s' "$verdict" | jq -r '.outcome // "unknown"')"
  verdict_head="$(printf '%s' "$verdict" | jq -r '.head_sha // ""')"

  case "$outcome" in
    not_configured) printf 'no_local_reviewer\n'; return 0 ;;
    not_yet_run|unknown) printf 'no_evidence\n'; return 0 ;;
    clean) ;;
    *) printf 'prior_findings\n'; return 0 ;;
  esac

  if [ -n "$head" ] && [ "$verdict_head" = "$head" ]; then
    printf 'not_required\n'
  else
    printf 'head_changed\n'
  fi
}

# reviewer_loop_second_local_pass_gate_result <pass_result> <pass_reason>
# Prints tab-separated: aggregate_result<TAB>aggregate_reason
reviewer_loop_second_local_pass_gate_result() {
  local pass_result="${1:-}" pass_reason="${2:-}"

  case "$pass_result" in
    clean) printf 'proceed\t\n' ;;
    needs_fixes) printf 'needs_fixes\t%s\n' "${pass_reason:-}" ;;
    escalate) printf 'escalate\t%s\n' "${pass_reason:-}" ;;
    skipped|needs_rerun|*)
      printf 'escalate\tlocal_pass_unavailable\n' ;;
  esac
}

# reviewer_loop_second_local_pass_confirm_live_head <pr_number>
#
# Re-reads the live PR head and compares it to loop_head_sha before any
# proceed-to-ready path. Fail closed on an unreadable head or a mismatch so
# ready-phase reviewers cannot start on a commit with no local evidence.
# Returns 0 when the live head matches; 1 after setting aggregate_* on failure.
reviewer_loop_second_local_pass_confirm_live_head() {
  local pr_number_arg="${1:-}"
  local _sl_head_now="" _sl_gh_st=0

  set +e
  _sl_head_now="$(gh pr view "$pr_number_arg" --json headRefOid --jq '.headRefOid' 2>/dev/null)"
  _sl_gh_st=$?
  set -e
  if [ "$_sl_gh_st" -ne 0 ] || [ -z "$_sl_head_now" ]; then
    local_second_pass_reason="local_pass_unavailable"
    aggregate_result="escalate"
    aggregate_reason="local_pass_unavailable"
    aggregate_output="$(printf 'RESULT=escalate\nREASON=local_pass_unavailable\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n')"
    aggregate_status=2
    last_platform="local-ai-reviewer"
    return 1
  fi
  if [ -n "$loop_head_sha" ] && [ "$_sl_head_now" != "$loop_head_sha" ]; then
    local_second_pass_reason="head_moved_during_pass"
    aggregate_result="needs_fixes"
    aggregate_reason="head_moved_during_run"
    aggregate_output="$(printf 'RESULT=needs_fixes\nREASON=head_moved_during_run\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n')"
    aggregate_status=1
    last_platform="local-ai-reviewer"
    return 1
  fi
  return 0
}

# reviewer_loop_second_local_pass_before_ready_gate <pr_number>
#
# Runs the #1656 guard immediately before ensure_pr_ready_for_ready_phase.
# Returns 0 to proceed to the ready gate, 1 when the platform loop must break
# (aggregate_result already set).
reviewer_loop_second_local_pass_before_ready_gate() {
  local pr_number_arg="${1:-}"
  local _sl_prior_payload _sl_next_iteration _sl_configured _sl_composed _sl_required
  local _sl_output _sl_status _sl_platform_index _sl_pass_result _sl_pass_reason
  local _sl_gate_result _sl_gate_reason _sl_reviewed_head _sl_head_state

  local_second_pass_reason="not_required"
  if [ "$phase_after_clean_enabled" -ne 1 ]; then
    return 0
  fi

  _sl_prior_payload="$(reviewer_loop_prior_history_payload_from_pr "$pr_number_arg")"
  _sl_next_iteration="$(printf '%s\n' "$_sl_prior_payload" | jq '(.entries // []) | length + 1' 2>/dev/null)" || _sl_next_iteration=1
  [[ "$_sl_next_iteration" =~ ^[0-9]+$ ]] || _sl_next_iteration=1
  _sl_configured="$(reviewer_loop_repo_configured_platforms)"
  _sl_composed="$(reviewer_loop_compose_current_round_payload "$_sl_prior_payload" "$_sl_next_iteration")"
  _sl_required="$(reviewer_loop_local_pass_required "$_sl_composed" "$loop_head_sha" "$_sl_configured")"
  local_second_pass_reason="$_sl_required"

  if [ "$_sl_required" = "not_required" ] || [ "$_sl_required" = "no_local_reviewer" ]; then
    if reviewer_loop_second_local_pass_confirm_live_head "$pr_number_arg"; then
      return 0
    fi
    return 1
  fi

  if [ "$(printf '%s' "$_sl_prior_payload" | jq -r '.history_status // "available"')" = "unavailable" ]; then
    local_second_pass_reason="local_pass_unavailable"
    aggregate_result="escalate"
    aggregate_reason="local_pass_unavailable"
    aggregate_output="$(printf 'RESULT=escalate\nREASON=local_pass_unavailable\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n')"
    aggregate_status=2
    last_platform="local-ai-reviewer"
    return 1
  fi

  if [ "$(reviewer_loop_local_second_pass_failed_for_head "$_sl_prior_payload" "$loop_head_sha")" -gt 0 ] 2>/dev/null; then
    local_second_pass=0
    local_second_pass_reason="failed_for_head"
    aggregate_result="escalate"
    aggregate_reason="failed_for_head"
    aggregate_output="$(printf 'RESULT=escalate\nREASON=failed_for_head\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n')"
    aggregate_status=2
    last_platform="local-ai-reviewer"
    return 1
  fi

  local_second_pass=1
  set +e
  _sl_output="$(run_platform_review "local-ai-reviewer" "$pr_number_arg" "$branch_name" "$poll_interval" "$max_wait")"
  _sl_status=$?
  set -e
  _sl_platform_index=$((${#platforms[@]} + 1))
  reviewer_loop_platform_loop_should_break=0
  reviewer_loop_process_platform_output "local-ai-reviewer" "$_sl_platform_index" "$_sl_output" "$_sl_status" 0
  _sl_pass_result="$reviewer_loop_last_platform_result"
  _sl_pass_reason="$reviewer_loop_last_platform_reason"
  _sl_pass_output="$reviewer_loop_last_platform_output"
  _sl_pass_status="$reviewer_loop_last_platform_status"
  local_second_pass_result="$_sl_pass_result"

  if [ "$_sl_pass_result" = "clean" ]; then
    _sl_reviewed_head="$(kv_value_default REVIEWED_HEAD "$_sl_output" "")"
    _sl_head_state="$(reviewer_loop_head_evidence_classify "$_sl_reviewed_head" "$loop_head_sha")"
    _sl_head_state="${_sl_head_state%%|*}"
    if [ "$_sl_head_state" != "current" ]; then
      local_second_pass_reason="local_pass_unavailable"
      aggregate_result="escalate"
      aggregate_reason="local_pass_unavailable"
      aggregate_output="$(printf 'RESULT=escalate\nREASON=local_pass_unavailable\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n')"
      aggregate_status=2
      last_platform="local-ai-reviewer"
      return 1
    fi
    if ! reviewer_loop_second_local_pass_confirm_live_head "$pr_number_arg"; then
      return 1
    fi
    return 0
  fi

  IFS=$'\t' read -r _sl_gate_result _sl_gate_reason < <(reviewer_loop_second_local_pass_gate_result "$_sl_pass_result" "$_sl_pass_reason")
  aggregate_result="$_sl_gate_result"
  aggregate_reason="$_sl_gate_reason"
  if [ "$_sl_gate_result" = "escalate" ]; then
    local_second_pass_reason="local_pass_unavailable"
  fi
  local_second_pass_failed_head_record="$loop_head_sha"
  if [ "$_sl_gate_result" = "needs_fixes" ]; then
    aggregate_output="$(printf 'RESULT=needs_fixes\nREASON=%s\nCOMMENT_COUNT=%s\nBLOCKING_COUNT=%s\nSUGGESTION_COUNT=%s\n' \
      "${_sl_gate_reason:-}" \
      "$(kv_value_default COMMENT_COUNT "$_sl_pass_output" 0)" \
      "$(kv_value_default BLOCKING_COUNT "$_sl_pass_output" 0)" \
      "$(kv_value_default SUGGESTION_COUNT "$_sl_pass_output" 0)")"
    aggregate_status="$_sl_pass_status"
  else
    aggregate_output="$(printf 'RESULT=escalate\nREASON=%s\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n' "${_sl_gate_reason:-local_pass_unavailable}")"
    aggregate_status=2
  fi
  last_platform="local-ai-reviewer"
  return 1
}

# reviewer_loop_process_platform_output <platform_name> <platform_index> <output> <status> [update_aggregate]
#
# Shared post-dispatch processor for the platform loop and the second local pass
# guard (#1656). When update_aggregate is 0, only records telemetry without
# touching aggregate_* (guard reads pass result separately).
reviewer_loop_process_platform_output() {
  local platform_name="$1"
  local platform_index="$2"
  local platform_output="$3"
  local platform_status="$4"
  local update_aggregate="${5:-1}"
  local platform_result platform_comment_count platform_blocking_count
  local platform_suggestion_count platform_advisory_labels platform_reason
  local _prt_reason _prt_display_override _prt_disp _reviewed_head
  local _policy_status_available _policy_bucket _policy_needs_human
  local _policy_disposition _policy_verdict _policy_analysis_status
  local _policy_rating _policy_has_reviewer _policy_note
  local _blocking_path _blocking_finding

  platform_result="$(kv_value_default RESULT "$platform_output" skipped)"
  platform_comment_count="$(kv_value_default COMMENT_COUNT "$platform_output" 0)"
  platform_blocking_count="$(kv_value_default BLOCKING_COUNT "$platform_output" 0)"
  platform_suggestion_count="$(kv_value_default SUGGESTION_COUNT "$platform_output" 0)"
  platform_advisory_labels="$(kv_value_default ADVISORY_LABELS "$platform_output" "")"
  platform_reason="$(kv_value_default REASON "$platform_output" "")"
  if [ "$platform_name" = "local-ai-reviewer" ]; then
    reviewer_loop_replace_current_round_platform_record "$platform_name"
  fi
  platform_peer_evidence+=("${platform_name}|${platform_result}|${platform_reason}")
  if reviewer_failed_label_required_for_result "$platform_result" "$platform_reason"; then
    reviewer_failed_required=1
  fi

  total_comment_count=$((total_comment_count + platform_comment_count))
  total_blocking_count=$((total_blocking_count + platform_blocking_count))
  total_suggestion_count=$((total_suggestion_count + platform_suggestion_count))
  while IFS= read -r _blocking_path; do
    [ -n "$_blocking_path" ] && aggregate_blocking_paths+=("$_blocking_path")
  done < <(reviewer_loop_blocking_paths_from_output "$platform_output" "$platform_blocking_count")
  unset _blocking_path
  while IFS= read -r _blocking_finding; do
    [ -n "$_blocking_finding" ] && aggregate_blocking_findings+=("$_blocking_finding")
  done < <(reviewer_loop_blocking_findings_from_output "$platform_output" "$platform_blocking_count" "$platform_name")
  unset _blocking_finding
  if [ -n "$platform_advisory_labels" ]; then
    if [ -n "$aggregate_advisory_labels" ]; then
      aggregate_advisory_labels="${aggregate_advisory_labels}|||${platform_advisory_labels}"
    else
      aggregate_advisory_labels="$platform_advisory_labels"
    fi
  fi
  last_platform="$platform_name"

  print_kv "PLATFORM_${platform_index}_NAME" "$platform_name"
  print_kv "PLATFORM_${platform_index}_RESULT" "$platform_result"
  emit_prefixed_platform_output "$platform_index" "$platform_output"
  if [ "$platform_name" = "local-ai-reviewer" ]; then
    capture_strict_spec_globals_from_output "$platform_output"
    capture_strict_plan_globals_from_output "$platform_output"
  fi
  _prt_reason="$platform_reason"
  _prt_display_override="$(kv_value_default DISPLAY_RESULT "$platform_output" "")"
  if [ -n "$_prt_display_override" ]; then
    _prt_disp="$_prt_display_override"
  else
    case "$platform_result" in
      clean)      _prt_disp="clean" ;;
      skipped)
        if [ "$_prt_reason" = "unavailable" ] || [ "$_prt_reason" = "not_configured" ]; then
          _prt_disp="unavailable"
        else
          _prt_disp="skipped"
        fi
        ;;
      escalate)   _prt_disp="escalated (${_prt_reason:-unknown})" ;;
      needs_fixes) _prt_disp="needs_fixes" ;;
      *)           _prt_disp="$platform_result" ;;
    esac
  fi
  platform_result_tokens+=("${platform_name}:${_prt_disp}")
  _reviewed_head="$(kv_value_default REVIEWED_HEAD "$platform_output" "")"
  platform_reviewed_heads+=("${platform_name}:${_reviewed_head}")
  unset _reviewed_head
  platform_result_records+=("$(reviewer_loop_platform_result_record_json "$platform_name" "$platform_result" "$platform_reason")")
  platform_blocking_outputs+=("${platform_name}"$'\036'"${platform_output}")

  _policy_status_available="$(kv_value_default POLICY_STATUS_AVAILABLE "$platform_output" 0)"
  if [ "$_policy_status_available" = "1" ]; then
    _policy_bucket="$(kv_value_default POLICY_BUCKET "$platform_output" "")"
    _policy_needs_human="$(kv_value_default POLICY_NEEDS_HUMAN "$platform_output" "")"
    _policy_disposition="$(kv_value_default POLICY_DISPOSITION "$platform_output" "")"
    _policy_verdict="$(kv_value_default POLICY_VERDICT "$platform_output" "")"
    _policy_analysis_status="$(kv_value_default POLICY_ANALYSIS_STATUS "$platform_output" "")"
    _policy_rating="$(kv_value_default POLICY_RATING "$platform_output" "")"
    _policy_has_reviewer="$(kv_value_default POLICY_HAS_REVIEWER "$platform_output" "")"
    _policy_note="${platform_name}:"
    [ -n "$_policy_bucket" ] && _policy_note="${_policy_note} bucket=${_policy_bucket};"
    [ -n "$_policy_needs_human" ] && _policy_note="${_policy_note} needsHumanReview=${_policy_needs_human};"
    [ -n "$_policy_disposition" ] && _policy_note="${_policy_note} disposition=${_policy_disposition};"
    [ -n "$_policy_verdict" ] && _policy_note="${_policy_note} verdict=${_policy_verdict};"
    [ -n "$_policy_analysis_status" ] && _policy_note="${_policy_note} analysisStatus=${_policy_analysis_status};"
    [ -n "$_policy_rating" ] && _policy_note="${_policy_note} rating=${_policy_rating};"
    [ -n "$_policy_has_reviewer" ] && _policy_note="${_policy_note} hasReviewer=${_policy_has_reviewer};"
    platform_policy_status_notes+=("$_policy_note")
  fi
  unset _prt_reason _prt_display_override _prt_disp
  unset _policy_status_available _policy_bucket _policy_needs_human
  unset _policy_disposition _policy_verdict _policy_analysis_status
  unset _policy_rating _policy_has_reviewer _policy_note

  if [ "$compare_mode" -eq 1 ]; then
    compare_verdicts+=("$platform_name" "$(normalize_platform_verdict "$platform_result" "$platform_output")")
  fi

  reviewer_loop_last_platform_result="$platform_result"
  reviewer_loop_last_platform_reason="$platform_reason"
  reviewer_loop_last_platform_output="$platform_output"
  reviewer_loop_last_platform_status="$platform_status"

  [ "$update_aggregate" -eq 1 ] || return 0

  case "$platform_result" in
    clean)
      aggregate_result="clean"
      aggregate_output="$platform_output"
      aggregate_status=$platform_status
      ;;
    skipped)
      if [ "$aggregate_result" = "skipped" ]; then
        aggregate_output="$platform_output"
        aggregate_status=$platform_status
      fi
      aggregate_result="clean"
      ;;
    waiting_on_reviewer)
      aggregate_result="$platform_result"
      aggregate_reason="$(kv_value_default REASON "$platform_output" "")"
      aggregate_output="$platform_output"
      aggregate_status=$platform_status
      if [ "$compare_mode" -eq 0 ]; then
        reviewer_loop_platform_loop_should_break=1
      fi
      if [ -z "$compare_first_blocking_result" ]; then
        compare_first_blocking_result="$platform_result"
        compare_first_blocking_reason="$aggregate_reason"
        compare_first_blocking_output="$platform_output"
        compare_first_blocking_status=$platform_status
      fi
      ;;
    needs_fixes|escalate)
      if [ "$phase_after_clean_enabled" -eq 1 ] \
          && [ "$phase_after_clean_started" -eq 1 ] \
          && is_phase_after_clean_platform "$platform_name"; then
        phase_after_clean_net_new_blocker=1
        phase_after_clean_blocking_platform="$platform_name"
      fi
      aggregate_result="$platform_result"
      aggregate_reason="$(kv_value_default REASON "$platform_output" "")"
      aggregate_output="$platform_output"
      aggregate_status=$platform_status
      if [ "$compare_mode" -eq 0 ]; then
        reviewer_loop_platform_loop_should_break=1
      fi
      if [ -z "$compare_first_blocking_result" ]; then
        compare_first_blocking_result="$platform_result"
        compare_first_blocking_reason="$aggregate_reason"
        compare_first_blocking_output="$platform_output"
        compare_first_blocking_status=$platform_status
      fi
      ;;
    needs_rerun)
      aggregate_result="needs_rerun"
      aggregate_output="$platform_output"
      aggregate_status=$platform_status
      if [ "$compare_mode" -eq 0 ]; then
        reviewer_loop_platform_loop_should_break=1
      fi
      if [ -z "$compare_first_blocking_result" ]; then
        compare_first_blocking_result="needs_rerun"
        compare_first_blocking_reason=""
        compare_first_blocking_output="$platform_output"
        compare_first_blocking_status=$platform_status
      fi
      ;;
    *)
      aggregate_result="escalate"
      aggregate_reason="unknown-platform-result"
      aggregate_output="$platform_output"
      aggregate_status=2
      if [ "$compare_mode" -eq 0 ]; then
        reviewer_loop_platform_loop_should_break=1
      fi
      if [ -z "$compare_first_blocking_result" ]; then
        compare_first_blocking_result="escalate"
        compare_first_blocking_reason="unknown-platform-result"
        compare_first_blocking_output="$platform_output"
        compare_first_blocking_status=2
      fi
      ;;
  esac
}

# reviewer_loop_local_evidence_state <local_verdict_json> <reviewed_head>
reviewer_loop_local_evidence_state() {
  local verdict_json="${1:-}"
  local reviewed_head="${2:-}"
  local outcome head_sha ancestry

  outcome="$(printf '%s' "$verdict_json" | jq -r '.outcome // "unknown"')"
  head_sha="$(printf '%s' "$verdict_json" | jq -r '.head_sha // ""')"

  case "$outcome" in
    clean)
      ancestry="$(reviewer_loop_commit_ancestry "$head_sha" "$reviewed_head")"
      case "$ancestry" in
        same) printf 'clean_same_commit\n' ;;
        ancestor) printf 'clean_earlier_commit\n' ;;
        descendant) printf 'clean_later_commit\n' ;;
        unrelated) printf 'clean_unrelated_commit\n' ;;
        *) printf 'unknown\n' ;;
      esac
      ;;
    needs_fixes) printf 'not_clean\n' ;;
    skipped) printf 'skipped\n' ;;
    unavailable) printf 'unavailable\n' ;;
    not_yet_run) printf 'not_yet_run\n' ;;
    not_configured) printf 'not_configured\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

# Map local evidence state to the three-value classification enum.
reviewer_loop_missed_finding_classification() {
  case "${1:-}" in
    clean_same_commit) printf 'confirmed_miss\n' ;;
    clean_earlier_commit) printf 'possible_miss\n' ;;
    *) printf 'not_a_miss\n' ;;
  esac
}

# Spec display labels for local evidence states.
reviewer_loop_local_evidence_state_label() {
  case "${1:-}" in
    clean_same_commit) printf 'Clean, same commit\n' ;;
    clean_earlier_commit) printf 'Clean, earlier commit\n' ;;
    clean_later_commit) printf 'Clean, later commit\n' ;;
    clean_unrelated_commit) printf 'Clean, unrelated commit\n' ;;
    not_clean) printf 'Reported findings\n' ;;
    skipped) printf 'Skipped\n' ;;
    unavailable) printf 'Unavailable\n' ;;
    not_yet_run) printf 'Not yet run\n' ;;
    not_configured) printf 'Not configured\n' ;;
    *) printf 'Unknown\n' ;;
  esac
}

# De-duplicate paths preserving first-appearance order. stdin -> stdout.
reviewer_loop_dedupe_paths() {
  awk 'NF && !seen[$0]++ { print }'
}

# Join reviewed_head for a platform from reviewed_heads[] JSON array.
reviewer_loop_reviewed_head_for_platform() {
  local reviewed_heads_json="${1:-[]}"
  local platform="${2:-}"

  printf '%s' "$reviewed_heads_json" | jq -r --arg p "$platform" '
    ([.[]? | select(.platform == $p) | .reviewed_head // ""] | first) // ""
  '
}

# Emit REVIEWED_HEAD when stdin has exactly one unique non-empty commit line.
reviewer_loop_print_reviewed_head_from_commits() {
  local unique count sha
  unique="$(grep -v '^$' | sort -u || true)"
  count="$(printf '%s\n' "$unique" | grep -c . || true)"
  [ "$count" -eq 1 ] || return 0
  sha="$(printf '%s\n' "$unique" | head -n 1)"
  [ -n "$sha" ] || return 0
  print_kv REVIEWED_HEAD "$sha"
}

# Extract unique commit_id values from newline-delimited JSON objects on stdin
# and print REVIEWED_HEAD when exactly one unique non-empty value exists.
reviewer_loop_print_reviewed_head_from_json_lines() {
  local commits
  commits="$(jq -r '.commit_id // empty' 2>/dev/null | grep -v '^$' || true)"
  printf '%s\n' "$commits" | reviewer_loop_print_reviewed_head_from_commits
}

# Collect strict-mode blocking bot threads as JSON [{path,line,body,commit},...].
# Paginates like check_unresolved_threads. Exit 0 complete, 2 page cap, 3 GraphQL.
_reviewer_loop_blocking_unresolved_bot_threads_json() {
  local pr_number="$1"
  local repo="$2"
  local graphql_bot_login="$3"
  local owner repo_name cursor has_next_page page max_pages result graphql_query nodes_fields
  local records='[]' page_records

  owner="$(printf '%s\n' "$repo" | cut -d/ -f1)"
  repo_name="$(printf '%s\n' "$repo" | cut -d/ -f2)"

  cursor=""
  has_next_page="true"
  page=0
  max_pages=10

  nodes_fields='id isResolved isOutdated path line firstComment:comments(first:1){nodes{author{login}body originalCommit{oid}}}'
  graphql_query='query($owner:String!,$repo:String!,$pr:Int!,$cursor:String){repository(owner:$owner,name:$repo){pullRequest(number:$pr){reviewThreads(first:100,after:$cursor){pageInfo{hasNextPage endCursor}nodes{'"$nodes_fields"'}}}}}'

  while [ "$has_next_page" = "true" ]; do
    page=$((page + 1))
    if [ "$page" -gt "$max_pages" ]; then
      return 2
    fi

    if [ -n "$cursor" ]; then
      result="$(gh api graphql \
        -f query="$graphql_query" \
        -f owner="$owner" -f repo="$repo_name" -F pr="$pr_number" -f cursor="$cursor" \
        --jq '.data.repository.pullRequest' 2>/dev/null)" \
        || return 3
    else
      result="$(gh api graphql \
        -f query="$graphql_query" \
        -f owner="$owner" -f repo="$repo_name" -F pr="$pr_number" \
        --jq '.data.repository.pullRequest' 2>/dev/null)" \
        || return 3
    fi

    has_next_page="$(printf '%s\n' "$result" | jq -r '.reviewThreads.pageInfo.hasNextPage')"
    cursor="$(printf '%s\n' "$result" | jq -r '.reviewThreads.pageInfo.endCursor // empty')"

    page_records="$(printf '%s\n' "$result" | jq -c --arg bot "$graphql_bot_login" '
      [.reviewThreads.nodes[]
        | select((.firstComment.nodes[0].author.login // "") == $bot)
        | select(.isResolved != true)
        | select((.isOutdated // false) != true)
        | select((.firstComment.nodes[0].body // "") | contains("✅ Addressed") | not)
        | {
            path: (.path // ""),
            line: (.line // 0),
            body: (.firstComment.nodes[0].body // ""),
            commit: (.firstComment.nodes[0].originalCommit.oid // "")
          }
      ]')" || return 3
    records="$(printf '%s\n%s\n' "$records" "$page_records" | jq -s 'add')"

    if [ "$has_next_page" = "true" ] && [ -z "$cursor" ]; then
      return 2
    fi
  done

  printf '%s\n' "$records"
  return 0
}

# Collect commit OIDs from strict-mode blocking bot threads.
reviewer_loop_blocking_unresolved_thread_commit_oids() {
  local pr_number="$1"
  local repo="$2"
  local graphql_bot_login="$3"
  local json st

  set +e
  json="$(_reviewer_loop_blocking_unresolved_bot_threads_json \
    "$pr_number" "$repo" "$graphql_bot_login" 2>/dev/null)"
  st=$?
  set -e
  if [ "$st" -ne 0 ]; then
    return "$st"
  fi

  printf '%s\n' "$json" | jq -r '.[].commit // empty'
  return 0
}

# Emit BLOCKING_<n>_PATH/LINE/BODY from strict-mode blocking bot threads.
reviewer_loop_print_blocking_from_unresolved_bot_threads() {
  local pr_number="$1"
  local repo="$2"
  local graphql_bot_login="$3"
  local json st idx=0 path line body title row

  set +e
  json="$(_reviewer_loop_blocking_unresolved_bot_threads_json \
    "$pr_number" "$repo" "$graphql_bot_login" 2>/dev/null)"
  st=$?
  set -e
  if [ "$st" -ne 0 ]; then
    return "$st"
  fi

  while IFS= read -r row; do
    [ -n "$row" ] || continue
    idx=$((idx + 1))
    path="$(printf '%s' "$row" | jq -r '.path // ""')"
    line="$(printf '%s' "$row" | jq -r '.line // 0')"
    body="$(printf '%s' "$row" | jq -r '.body // ""')"
    title="$(printf '%s\n' "$body" | sed -n 's/^### //p;q')"
    if [ -z "$title" ]; then
      title="$(printf '%.120s' "$(printf '%s\n' "$body" | tr '\n' ' ')")"
    fi
    print_kv "BLOCKING_${idx}_PATH" "${path:-unknown}"
    print_kv "BLOCKING_${idx}_LINE" "$line"
    print_kv_escaped "BLOCKING_${idx}_BODY" "$title"
  done < <(printf '%s\n' "$json" | jq -c '.[]?')
  return 0
}

# Emit REVIEWED_HEAD when strict-mode blocking threads for a bot login share
# exactly one unique originalCommitOid.
reviewer_loop_print_reviewed_head_from_unresolved_bot_threads() {
  local pr_number="$1"
  local repo="$2"
  local graphql_bot_login="$3"
  local commits st

  set +e
  commits="$(reviewer_loop_blocking_unresolved_thread_commit_oids \
    "$pr_number" "$repo" "$graphql_bot_login" 2>/dev/null)"
  st=$?
  set -e
  if [ "$st" -ne 0 ]; then
    return 0
  fi

  printf '%s\n' "$commits" | reviewer_loop_print_reviewed_head_from_commits
}

# When post-clean settle finds late unresolved threads after an otherwise-clean
# platform pass, synthesize platform_result_records + blocking outputs so
# missed-finding telemetry can still run in _post_review_summary (AC-1/AC-10).
reviewer_loop_append_late_thread_missed_findings() {
  local pr_number="$1"
  local repo="$2"
  local platform_name bot_login graphql_bot_login count json head output_blob
  local idx=0 row path line body title

  for platform_name in "${platforms[@]:-}"; do
    bot_login="$(bot_login_for_platform "$platform_name")"
    graphql_bot_login="${bot_login%\[bot\]}"
    [ -n "$graphql_bot_login" ] || continue

    set +e
    count="$(check_unresolved_threads "$pr_number" "$repo" strict "$graphql_bot_login")"
    set -e
    [ "${count:-0}" -gt 0 ] 2>/dev/null || continue

    if ! declare -p platform_result_records >/dev/null 2>&1; then
      declare -a platform_result_records=()
    fi
    platform_result_records+=("$(reviewer_loop_platform_result_record_json \
      "$platform_name" needs_fixes late_review_threads)")

    json="$(_reviewer_loop_blocking_unresolved_bot_threads_json \
      "$pr_number" "$repo" "$graphql_bot_login" 2>/dev/null)" || continue

    head="$(printf '%s\n' "$json" | jq -r '
      [.[].commit // empty | select(length > 0)] | unique
      | if length == 1 then .[0] else empty end' 2>/dev/null)" || head=""
    if [ -n "$head" ]; then
      if ! declare -p platform_reviewed_heads >/dev/null 2>&1; then
        declare -a platform_reviewed_heads=()
      fi
      platform_reviewed_heads+=("${platform_name}:${head}")
    fi

    output_blob="RESULT=needs_fixes"$'\n'"BLOCKING_COUNT=${count}"$'\n'
    idx=0
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      idx=$((idx + 1))
      path="$(printf '%s' "$row" | jq -r '.path // ""')"
      line="$(printf '%s' "$row" | jq -r '.line // 0')"
      body="$(printf '%s' "$row" | jq -r '.body // ""')"
      title="$(printf '%s\n' "$body" | sed -n 's/^### //p;q')"
      if [ -z "$title" ]; then
        title="$(printf '%.120s' "$(printf '%s\n' "$body" | tr '\n' ' ')")"
      fi
      output_blob="${output_blob}BLOCKING_${idx}_PATH=${path:-unknown}"$'\n'
      output_blob="${output_blob}BLOCKING_${idx}_LINE=${line}"$'\n'
      output_blob="${output_blob}BLOCKING_${idx}_BODY=${title}"$'\n'
    done < <(printf '%s\n' "$json" | jq -c '.[]?' 2>/dev/null)

    if ! declare -p platform_blocking_outputs >/dev/null 2>&1; then
      declare -a platform_blocking_outputs=()
    fi
    platform_blocking_outputs+=("${platform_name}"$'\036'"${output_blob}")
  done
}

# Build missed_findings JSON array for the current round.
# Args:
#   $1 history_payload (persisted entries; may be empty object with entries:[])
#   $2 configured_platforms (newline-delimited)
#   $3 current_platform_results_json (array)
#   $4 current_reviewed_heads_json (array, #1648 shape)
#   $5 platform_outputs_json — array of {platform, blocking_count, output} for path extraction
#      OR we pass paths via a parallel mechanism.
# Simpler signature used by call site:
# Globals read:
#   platform_result_records[]  — JSON objects
#   platform_reviewed_heads[]  — "name:sha"
#   platform_blocking_outputs[] — optional "name<RS>output" (RS=\036) for path extraction
#   missed_finding_attribution_failures — set by this function (newline messages)
#
# Returns JSON array on stdout. Also sets:
#   missed_finding_records_json
#   missed_finding_attribution_reports (human-readable lines)
reviewer_loop_missed_finding_records() {
  local history_payload="${1:-}"
  local configured="${2:-}"
  local iteration="${3:-0}"
  local results_json heads_json composed_payload local_verdict
  local platform_name normalized reviewed_head blocking_count paths_text path_total
  local state classification record records_json="[]"
  local entry_name output_blob paths_json

  missed_finding_attribution_reports=""

  results_json='[]'
  if declare -p platform_result_records >/dev/null 2>&1 && [ "${#platform_result_records[@]}" -gt 0 ]; then
    results_json="$(printf '%s\n' "${platform_result_records[@]}" | jq -s -c '.')"
  fi

  if declare -p platform_reviewed_heads >/dev/null 2>&1 && [ "${#platform_reviewed_heads[@]}" -gt 0 ]; then
    heads_json="$(reviewer_loop_head_evidence_json "${loop_head_sha:-}" "${platform_reviewed_heads[@]}")"
  else
    heads_json="$(reviewer_loop_head_evidence_json "${loop_head_sha:-}")"
  fi

  # Compose synthetic current-round entry into the payload before selecting.
  composed_payload="$(printf '%s' "${history_payload:-{\}}" | jq -c \
    --argjson iteration "$iteration" \
    --argjson results "$results_json" \
    --argjson heads "$heads_json" \
    '
      . as $root
      | ($root.entries // []) as $entries
      | $root
      | .schema = (.schema // "reviewer_loop_history.v1")
      | .entries = ($entries + [{
          iteration: $iteration,
          platform_results: $results,
          reviewed_heads: $heads
        }])
    ')"

  local_verdict="$(reviewer_loop_local_latest_verdict "$composed_payload" "$configured")"

  # Walk platform_result_records for external platforms with blocking findings.
  if ! declare -p platform_result_records >/dev/null 2>&1; then
    printf '%s\n' "$records_json"
    return 0
  fi

  local idx=0
  for record in "${platform_result_records[@]}"; do
    platform_name="$(printf '%s' "$record" | jq -r '.platform // ""')"
    normalized="$(printf '%s' "$record" | jq -r '.result // ""')"
    [ -n "$platform_name" ] || continue

    # Exclusion 1: local reviewer cannot miss its own findings
    if [ "$platform_name" = "local-ai-reviewer" ]; then
      continue
    fi

    # Exclusion 2: only blocking findings qualify (needs_fixes)
    if [ "$normalized" != "needs_fixes" ]; then
      continue
    fi

    # Join head from reviewed_heads[] — prefer the last entry for this platform
    # so late-thread append wins over an earlier clean pass (#1651).
    reviewed_head=""
    if declare -p platform_reviewed_heads >/dev/null 2>&1; then
      for entry_name in "${platform_reviewed_heads[@]}"; do
        if [ "${entry_name%%:*}" = "$platform_name" ]; then
          reviewed_head="${entry_name#*:}"
        fi
      done
    fi

    # Exclusion 3: unattributable commit
    if [ -z "$reviewed_head" ]; then
      missed_finding_attribution_reports="${missed_finding_attribution_reports}${missed_finding_attribution_reports:+$'\n'}missed-finding attribution failed: ${platform_name} — reviewed commit could not be established (no REVIEWED_HEAD)"
      continue
    fi

    # Paths from companion output — prefer the last blob for this platform so
    # late-thread synthesis wins over an earlier clean pass (#1651).
    blocking_count=0
    paths_text=""
    if declare -p platform_blocking_outputs >/dev/null 2>&1; then
      for output_blob in "${platform_blocking_outputs[@]}"; do
        if [ "${output_blob%%$'\036'*}" = "$platform_name" ]; then
          output_blob="${output_blob#*$'\036'}"
          blocking_count="$(kv_value_default BLOCKING_COUNT "$output_blob" 0)"
          paths_text="$(reviewer_loop_blocking_paths_from_output "$output_blob" "$blocking_count" | reviewer_loop_dedupe_paths)"
        fi
      done
    fi
    [[ "$blocking_count" =~ ^[0-9]+$ ]] || blocking_count=0
    # If blocking_count came from normalized needs_fixes but output missing, still count >=1
    if [ "$blocking_count" -eq 0 ]; then
      blocking_count=1
    fi

    path_total=0
    if [ -n "$paths_text" ]; then
      path_total="$(printf '%s\n' "$paths_text" | grep -c . || true)"
    fi
    paths_json="$(printf '%s\n' "$paths_text" | jq -R -s -c 'split("\n") | map(select(length > 0))')"

    state="$(reviewer_loop_local_evidence_state "$local_verdict" "$reviewed_head")"
    classification="$(reviewer_loop_missed_finding_classification "$state")"

    record="$(jq -nc \
      --arg reviewer "$platform_name" \
      --arg reviewed_head "$reviewed_head" \
      --argjson blocking_count "$blocking_count" \
      --argjson paths "$paths_json" \
      --argjson path_total "$path_total" \
      --arg local_evidence_state "$state" \
      --arg classification "$classification" \
      '{
        reviewer: $reviewer,
        reviewed_head: $reviewed_head,
        blocking_count: $blocking_count,
        paths: $paths,
        path_total: $path_total,
        local_evidence_state: $local_evidence_state,
        classification: $classification
      }')"
    records_json="$(jq -nc --argjson arr "$records_json" --argjson rec "$record" '$arr + [$rec]')"
    idx=$((idx + 1))
  done

  # Assign globals in the current shell. Callers that need attribution reports
  # must invoke this function without command substitution ($(...)).
  missed_findings_json="$records_json"
  printf '%s\n' "$records_json"
}

# Collect all missed-finding records persisted in a history payload.
reviewer_loop_missed_findings_from_history_payload() {
  local payload="${1:-}"
  printf '%s' "$payload" | jq -c '[(.entries // [])[] | (.missed_findings // [])[]]' 2>/dev/null \
    || printf '[]\n'
}

# Render one summary line (<=200 chars) for a missed-finding record JSON object.
reviewer_loop_missed_finding_summary_line() {
  local record_json="${1:-}"
  local reviewer short_sha blocking path_total state classification label
  local prefix suffix remainder_max budget named=0 path next_len rem rem_text line
  local -a paths=()

  reviewer="$(printf '%s' "$record_json" | jq -r '.reviewer // ""')"
  short_sha="$(printf '%s' "$record_json" | jq -r '.reviewed_head // ""' | cut -c1-8)"
  blocking="$(printf '%s' "$record_json" | jq -r '.blocking_count // 0')"
  path_total="$(printf '%s' "$record_json" | jq -r '.path_total // 0')"
  state="$(printf '%s' "$record_json" | jq -r '.local_evidence_state // "unknown"')"
  classification="$(printf '%s' "$record_json" | jq -r '.classification // "not_a_miss"')"
  label="$(reviewer_loop_local_evidence_state_label "$state")"

  while IFS= read -r path; do
    [ -n "$path" ] && paths+=("$path")
  done < <(printf '%s' "$record_json" | jq -r '.paths[]? // empty')

  prefix="missed-finding: ${reviewer} on ${short_sha} — ${blocking} blocking, ${path_total} files ("
  suffix=") — local: ${label} [${classification}]"
  remainder_max=", +${path_total} more"
  budget=$((200 - ${#prefix} - ${#suffix} - ${#remainder_max}))
  [ "$budget" -lt 0 ] && budget=0

  named=0
  local path_part=""
  local i=0
  while [ "$i" -lt "${#paths[@]}" ] && [ "$named" -lt 3 ]; do
    path="${paths[$i]}"
    if [ "$named" -eq 0 ]; then
      next_len=${#path}
    else
      next_len=$((2 + ${#path}))  # ", "
    fi
    if [ "$next_len" -gt "$budget" ]; then
      break
    fi
    if [ "$named" -eq 0 ]; then
      path_part="$path"
    else
      path_part="${path_part}, ${path}"
    fi
    budget=$((budget - next_len))
    named=$((named + 1))
    i=$((i + 1))
  done

  rem=$((path_total - named))
  rem_text=""
  if [ "$rem" -gt 0 ]; then
    rem_text=", +${rem} more"
  fi

  line="${prefix}${path_part}${rem_text}${suffix}"
  # Hard safety: never exceed 200 even if arithmetic drifts
  if [ "${#line}" -gt 200 ]; then
    line="${line:0:200}"
  fi
  printf '%s\n' "$line"
}

# Render all missed-finding summary lines from a JSON array.
reviewer_loop_missed_findings_summary_section() {
  local records_json="${1:-[]}"
  local record line section=""

  while IFS= read -r record; do
    [ -n "$record" ] || continue
    line="$(reviewer_loop_missed_finding_summary_line "$record")"
    section="${section}
${line}"
  done < <(printf '%s' "$records_json" | jq -c '.[]?' 2>/dev/null)

  printf '%s' "$section"
}



# Classify whether every finding record is "small" (#1652).
# Reads newline-delimited JSON objects {path,platform,body} from stdin.
# Fail-closed: empty array → failure; any empty/absent path → failure.
# A finding is non-small when it is on a normative document, has a shipped
# path, or touches a contract surface (after body normalisation for matching).
reviewer_loop_all_findings_are_small() {
  local line path body normalized
  local -a lines=()

  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    lines+=("$line")
  done

  [ "${#lines[@]}" -gt 0 ] || return 1

  for line in "${lines[@]}"; do
    path="$(printf '%s' "$line" | jq -r '.path // empty' 2>/dev/null)" || path=""
    body="$(printf '%s' "$line" | jq -r '.body // empty' 2>/dev/null)" || body=""
    [ -n "$path" ] || return 1
    if reviewer_loop_path_is_normative_document "$path"; then
      return 1
    fi
    if ! reviewer_loop_path_is_non_shipped_artifact "$path"; then
      return 1
    fi
    normalized="$(reviewer_loop_normalize_finding_body_for_match "$body")"
    if reviewer_loop_finding_touches_contract_surface "$normalized" >/dev/null; then
      return 1
    fi
  done

  return 0
}

# Thin path-only wrapper kept for existing harness callers (#1652). Converts
# newline-delimited paths into cosmetic finding records and delegates to
# reviewer_loop_all_findings_are_small. Outside this change set, no production
# caller remains — the main loop uses the findings array directly.
reviewer_loop_all_paths_non_shipped() {
  local path
  local -a findings=()
  local record

  while IFS= read -r path || [ -n "$path" ]; do
    [ -n "$path" ] || continue
    record="$(jq -c -n --arg path "$path" --arg platform "" --arg body "" \
      '{path: $path, platform: $platform, body: $body}')" || return 1
    findings+=("$record")
  done

  [ "${#findings[@]}" -gt 0 ] || return 1
  printf '%s\n' "${findings[@]}" | reviewer_loop_all_findings_are_small
}

# Analyse finding records for content causes and summary detail (#1652).
# Reads newline-delimited JSON findings from stdin.
# Prints one compact JSON object:
#   {"blocked_by":"shipped_path|contract_surface|",
#    "shipped_paths":[...],"contract_surfaces":[...],"all_small":true|false}
# Within the content group, shipped_path outranks contract_surface.
reviewer_loop_small_findings_content_analysis() {
  local line path body normalized surface
  local -a lines=() shipped_paths=() surfaces=()
  local has_shipped=0 has_contract=0 has_empty_path=0 all_small=1
  local blocked_by="" shipped_json surfaces_json

  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    lines+=("$line")
  done

  if [ "${#lines[@]}" -eq 0 ]; then
    jq -c -n '{blocked_by:"", shipped_paths:[], contract_surfaces:[], all_small:false}'
    return 0
  fi

  for line in "${lines[@]}"; do
    path="$(printf '%s' "$line" | jq -r '.path // empty' 2>/dev/null)" || path=""
    body="$(printf '%s' "$line" | jq -r '.body // empty' 2>/dev/null)" || body=""
    if [ -z "$path" ]; then
      has_empty_path=1
      all_small=0
      continue
    fi
    if reviewer_loop_path_is_normative_document "$path" \
        || ! reviewer_loop_path_is_non_shipped_artifact "$path"; then
      has_shipped=1
      all_small=0
      shipped_paths+=("$path")
      continue
    fi
    normalized="$(reviewer_loop_normalize_finding_body_for_match "$body")"
    surface=""
    if surface="$(reviewer_loop_finding_touches_contract_surface "$normalized")"; then
      has_contract=1
      all_small=0
      surfaces+=("$surface")
    fi
  done

  if [ "$has_empty_path" -eq 1 ]; then
    # Unlocatable blockers cannot be classified small; no single blocked_by
    # value applies (not in the four-value set). Leave blocked_by empty.
    blocked_by=""
  elif [ "$has_shipped" -eq 1 ]; then
    blocked_by="shipped_path"
  elif [ "$has_contract" -eq 1 ]; then
    blocked_by="contract_surface"
  fi

  if [ "${#shipped_paths[@]}" -gt 0 ]; then
    shipped_json="$(printf '%s\n' "${shipped_paths[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0)) | unique')"
  else
    shipped_json='[]'
  fi
  if [ "${#surfaces[@]}" -gt 0 ]; then
    surfaces_json="$(printf '%s\n' "${surfaces[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0)) | unique')"
  else
    surfaces_json='[]'
  fi

  jq -c -n \
    --arg blocked_by "$blocked_by" \
    --argjson shipped_paths "$shipped_json" \
    --argjson contract_surfaces "$surfaces_json" \
    --argjson all_small "$all_small" \
    '{
      blocked_by: $blocked_by,
      shipped_paths: $shipped_paths,
      contract_surfaces: $contract_surfaces,
      all_small: ($all_small == 1)
    }'
}

# True when a head is absent, empty, synthetic unknown-*, or not a full SHA.
reviewer_loop_head_is_unknown_or_invalid() {
  local head="${1:-}"
  [ -n "$head" ] || return 0
  case "$head" in
    unknown-*) return 0 ;;
  esac
  if reviewer_loop_head_evidence_full_sha "$head"; then
    return 1
  fi
  return 0
}

# Count consecutive prior small-findings rounds on the current head (#1652).
# Args: <summary_body> <current_loop_head_sha>
# Emits one compact JSON object: {"count":N,"stop_reason":"..."}.
# stop_reason is one of: exhausted | not_small | stale_head | head_unknown.
# Malformed caller parse should treat missing/invalid output as count 0 /
# head_unknown (see reviewer_loop_parse_small_findings_count).
reviewer_loop_small_findings_prior_consecutive_count() {
  local body="${1:-}"
  local current_head="${2:-}"
  local json
  local count=0
  local stop_reason="exhausted"
  local entries_json entry classification_head contributing_json
  local platform reviewed_head idx total contrib_stop

  json="$(printf '%s\n' "$body" | reviewer_loop_history_extract_latest_json)"
  if [ -z "$json" ]; then
    jq -c -n --argjson count 0 --arg stop_reason "head_unknown" \
      '{count: $count, stop_reason: $stop_reason}'
    return 0
  fi

  if ! printf '%s\n' "$json" | jq -e '
      .schema == "reviewer_loop_history.v1"
      and ((.history_status // "available") == "available")
      and ((.entries | type) == "array")
    ' >/dev/null 2>&1; then
    jq -c -n --argjson count 0 --arg stop_reason "head_unknown" \
      '{count: $count, stop_reason: $stop_reason}'
    return 0
  fi

  entries_json="$(printf '%s\n' "$json" | jq -c '[(.entries // []) | reverse[]]' 2>/dev/null)" || entries_json='[]'
  total="$(printf '%s' "$entries_json" | jq -r 'length' 2>/dev/null)" || total=0
  [[ "$total" =~ ^[0-9]+$ ]] || total=0

  idx=0
  while [ "$idx" -lt "$total" ]; do
    entry="$(printf '%s' "$entries_json" | jq -c --argjson i "$idx" '.[$i]' 2>/dev/null)" || entry=""
    [ -n "$entry" ] || break

    if [ "$(printf '%s' "$entry" | jq -r '.small_findings_only // false')" != "true" ]; then
      stop_reason="not_small"
      break
    fi

    classification_head="$(printf '%s' "$entry" | jq -r '.classification_head // empty' 2>/dev/null)" || classification_head=""
    if reviewer_loop_head_is_unknown_or_invalid "$classification_head"; then
      stop_reason="head_unknown"
      break
    fi
    # Compare case-insensitively like head_evidence_classify.
    if [ "$(printf '%s' "$classification_head" | tr 'A-F' 'a-f')" != "$(printf '%s' "$current_head" | tr 'A-F' 'a-f')" ]; then
      stop_reason="stale_head"
      break
    fi

    contributing_json="$(printf '%s' "$entry" | jq -c '.contributing_platforms // empty' 2>/dev/null)" || contributing_json=""
    if [ -z "$contributing_json" ] || [ "$contributing_json" = "null" ] \
        || [ "$(printf '%s' "$contributing_json" | jq -r 'if type == "array" then length else 0 end')" = "0" ]; then
      stop_reason="head_unknown"
      break
    fi

    # Check every contributing platform's reviewed_heads entry.
    contrib_stop=""
    while IFS= read -r platform; do
      [ -n "$platform" ] || continue
      reviewed_head="$(printf '%s' "$entry" | jq -r --arg p "$platform" '
        ([.reviewed_heads // [] | .[]? | select(.platform == $p) | .reviewed_head // ""] | first) // ""
      ' 2>/dev/null)" || reviewed_head=""
      if reviewer_loop_head_is_unknown_or_invalid "$reviewed_head"; then
        contrib_stop="head_unknown"
        break
      fi
      if [ "$(printf '%s' "$reviewed_head" | tr 'A-F' 'a-f')" != "$(printf '%s' "$classification_head" | tr 'A-F' 'a-f')" ]; then
        contrib_stop="stale_head"
        break
      fi
    done < <(printf '%s' "$contributing_json" | jq -r '.[]?' 2>/dev/null)

    if [ -n "$contrib_stop" ]; then
      stop_reason="$contrib_stop"
      break
    fi

    count=$((count + 1))
    idx=$((idx + 1))
  done

  jq -c -n --argjson count "$count" --arg stop_reason "$stop_reason" \
    '{count: $count, stop_reason: $stop_reason}'
}

# Parse counter JSON fail-closed (#1652). Prints "count stop_reason".
# Malformed / missing / out-of-domain → "0 head_unknown".
reviewer_loop_parse_small_findings_count() {
  local raw="${1:-}"
  local count stop_reason

  count="$(printf '%s' "$raw" | jq -r '.count // empty' 2>/dev/null)" || count=""
  stop_reason="$(printf '%s' "$raw" | jq -r '.stop_reason // empty' 2>/dev/null)" || stop_reason=""

  if ! [[ "$count" =~ ^[0-9]+$ ]]; then
    printf '0 head_unknown\n'
    return 0
  fi
  case "$stop_reason" in
    exhausted|not_small|stale_head|head_unknown) ;;
    *)
      printf '0 head_unknown\n'
      return 0
      ;;
  esac
  printf '%s %s\n' "$count" "$stop_reason"
}

# Check current-round contributing platforms against loop_head_sha (#1652).
# Args: current_head, then optional "platform:sha" entries (platform_reviewed_heads).
# Reads contributing platform names from stdin (one per line).
# Prints one compact JSON object:
#   {"status":"ok|stale_head|head_unknown","blocked_by":"...",
#    "details":["stale_head:plat",...]}
# Within the currency group, stale_head outranks head_unknown for blocked_by;
# details lists every currency cause present for the summary line.
reviewer_loop_current_round_heads_ok() {
  local current_head="${1:-}"
  shift
  local -a reviewed_entries=("$@")
  local platform reviewed_head entry found
  local -a details=()
  local has_stale=0 has_unknown=0
  local blocked_by="" status="ok" details_json

  # Fail closed: without a verifiable current head, currency cannot be established.
  if reviewer_loop_head_is_unknown_or_invalid "$current_head"; then
    while IFS= read -r platform || [ -n "$platform" ]; do
      [ -n "$platform" ] || continue
      has_unknown=1
      details+=("head_unknown:${platform}")
    done
  else
    while IFS= read -r platform || [ -n "$platform" ]; do
      [ -n "$platform" ] || continue
      found=0
      reviewed_head=""
      for entry in "${reviewed_entries[@]:-}"; do
        if [ "${entry%%:*}" = "$platform" ]; then
          reviewed_head="${entry#*:}"
          found=1
        fi
      done
      if [ "$found" -eq 0 ] || reviewer_loop_head_is_unknown_or_invalid "$reviewed_head"; then
        has_unknown=1
        details+=("head_unknown:${platform}")
        continue
      fi
      if [ "$(printf '%s' "$reviewed_head" | tr 'A-F' 'a-f')" != "$(printf '%s' "$current_head" | tr 'A-F' 'a-f')" ]; then
        has_stale=1
        details+=("stale_head:${platform}")
      fi
    done
  fi

  if [ "$has_stale" -eq 1 ]; then
    blocked_by="stale_head"
    status="stale_head"
  elif [ "$has_unknown" -eq 1 ]; then
    blocked_by="head_unknown"
    status="head_unknown"
  fi

  if [ "${#details[@]}" -gt 0 ]; then
    details_json="$(printf '%s\n' "${details[@]}" | jq -R -s -c 'split("\n") | map(select(length > 0))')"
  else
    details_json='[]'
  fi

  jq -c -n \
    --arg status "$status" \
    --arg blocked_by "$blocked_by" \
    --argjson details "$details_json" \
    '{status: $status, blocked_by: $blocked_by, details: $details}'
}

# Evaluate the production small-findings terminal decision (#1652).
# Args: <summary_body> <loop_head_sha> <required_rounds> <unresolved_thread_count>
#       then optional platform:reviewed_head entries; finding JSON records on stdin.
# Prints one compact JSON object:
#   {result, reason, small_findings_only, small_findings_stop, small_findings_rounds,
#    small_findings_blocked_by, currency_detail}
reviewer_loop_evaluate_small_findings_terminal() {
  local summary_body="${1:-}"
  local loop_head_sha="${2:-}"
  local required_rounds="${3:-2}"
  local unresolved_thread_count="${4:-0}"
  shift 4 2>/dev/null || true
  local -a platform_reviewed_heads=("$@")
  local -a aggregate_blocking_findings=()
  local line aggregate_result="needs_fixes" aggregate_reason=""
  local small_findings_only=0 small_findings_stop=0 small_findings_rounds=0
  local small_findings_blocked_by=""
  local small_findings_prior_count=0
  local currency_detail=""
  local _sf_content_json _sf_count_json _sf_prior_stop _sf_contributors
  local _sf_current_json _sf_current_currency _sf_currency_detail_list=""

  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    aggregate_blocking_findings+=("$line")
  done

  if [ "${#aggregate_blocking_findings[@]}" -eq 0 ]; then
    jq -c -n \
      --arg result "needs_fixes" --arg reason "" \
      --argjson small_findings_only 0 --argjson small_findings_stop 0 \
      --argjson small_findings_rounds 0 --arg small_findings_blocked_by "" \
      '{result: $result, reason: $reason, small_findings_only: ($small_findings_only == 1),
        small_findings_stop: ($small_findings_stop == 1), small_findings_rounds: $small_findings_rounds,
        small_findings_blocked_by: $small_findings_blocked_by}'
    return 0
  fi

  _sf_content_json="$(printf '%s\n' "${aggregate_blocking_findings[@]}" | reviewer_loop_small_findings_content_analysis)"
  if [ "$(printf '%s' "$_sf_content_json" | jq -r '.all_small // false')" = "true" ]; then
    small_findings_only=1
  else
    small_findings_blocked_by="$(printf '%s' "$_sf_content_json" | jq -r '.blocked_by // empty')"
    jq -c -n \
      --arg result "$aggregate_result" --arg reason "$aggregate_reason" \
      --argjson small_findings_only "$small_findings_only" \
      --argjson small_findings_stop "$small_findings_stop" \
      --argjson small_findings_rounds "$small_findings_rounds" \
      --arg small_findings_blocked_by "$small_findings_blocked_by" \
      '{result: $result, reason: $reason, small_findings_only: ($small_findings_only == 1),
        small_findings_stop: ($small_findings_stop == 1), small_findings_rounds: $small_findings_rounds,
        small_findings_blocked_by: $small_findings_blocked_by}'
    return 0
  fi

  if [ "$unresolved_thread_count" -gt 0 ]; then
    aggregate_result="needs_fixes"
    aggregate_reason="unresolved_review_threads"
    jq -c -n \
      --arg result "$aggregate_result" --arg reason "$aggregate_reason" \
      --argjson small_findings_only "$small_findings_only" \
      --argjson small_findings_stop 0 \
      --argjson small_findings_rounds 0 \
      --arg small_findings_blocked_by "" \
      '{result: $result, reason: $reason, small_findings_only: ($small_findings_only == 1),
        small_findings_stop: ($small_findings_stop == 1), small_findings_rounds: $small_findings_rounds,
        small_findings_blocked_by: $small_findings_blocked_by}'
    return 0
  fi

  _sf_count_json="$(reviewer_loop_small_findings_prior_consecutive_count "$summary_body" "$loop_head_sha")"
  read -r small_findings_prior_count _sf_prior_stop < <(reviewer_loop_parse_small_findings_count "$_sf_count_json")
  [[ "${small_findings_prior_count:-}" =~ ^[0-9]+$ ]] || small_findings_prior_count=0
  _sf_prior_stop="${_sf_prior_stop:-head_unknown}"

  _sf_contributors="$(
    printf '%s\n' "${aggregate_blocking_findings[@]}" \
      | jq -r '.platform // empty' 2>/dev/null \
      | awk 'NF && !seen[$0]++'
  )"
  if [ -n "$_sf_contributors" ]; then
    _sf_current_json="$(
      printf '%s\n' "$_sf_contributors" \
        | reviewer_loop_current_round_heads_ok "$loop_head_sha" "${platform_reviewed_heads[@]:-}"
    )"
  else
    _sf_current_json='{"status":"head_unknown","blocked_by":"head_unknown","details":["head_unknown:"]}'
  fi
  _sf_current_currency="$(printf '%s' "$_sf_current_json" | jq -r '.blocked_by // empty')"
  _sf_currency_detail_list="$(printf '%s' "$_sf_current_json" | jq -r '.details // [] | join(", ")')"

  small_findings_rounds=$((small_findings_prior_count + 1))

  if [ -n "$_sf_current_currency" ]; then
    small_findings_blocked_by="$_sf_current_currency"
    if [ "$_sf_current_currency" = "head_unknown" ] && [ "$_sf_prior_stop" = "stale_head" ]; then
      small_findings_blocked_by="stale_head"
    fi
    currency_detail="$_sf_currency_detail_list"
    if [ "$_sf_prior_stop" = "stale_head" ] || [ "$_sf_prior_stop" = "head_unknown" ]; then
      if [[ "$currency_detail" != *"$_sf_prior_stop"* ]]; then
        currency_detail="${currency_detail}; prior:${_sf_prior_stop}"
      fi
    fi
  elif [ "$small_findings_rounds" -ge "$required_rounds" ]; then
    aggregate_result="clean"
    aggregate_reason="small_findings_terminal"
    small_findings_stop=1
    small_findings_blocked_by=""
  elif [ "$_sf_prior_stop" = "stale_head" ] || [ "$_sf_prior_stop" = "head_unknown" ]; then
    small_findings_blocked_by="$_sf_prior_stop"
    currency_detail="prior:${_sf_prior_stop}"
  fi

  jq -c -n \
    --arg result "$aggregate_result" \
    --arg reason "$aggregate_reason" \
    --argjson small_findings_only "$small_findings_only" \
    --argjson small_findings_stop "$small_findings_stop" \
    --argjson small_findings_rounds "$small_findings_rounds" \
    --arg small_findings_blocked_by "$small_findings_blocked_by" \
    --arg currency_detail "$currency_detail" \
    '{result: $result, reason: $reason, small_findings_only: ($small_findings_only == 1),
      small_findings_stop: ($small_findings_stop == 1), small_findings_rounds: $small_findings_rounds,
      small_findings_blocked_by: $small_findings_blocked_by, currency_detail: $currency_detail}'
}

reviewer_loop_head_evidence_full_sha() {
  local value="$1"

  case "$value" in
    ''|*[!0-9a-fA-F]*) return 1 ;;
  esac
  [ "${#value}" -eq 40 ]
}

reviewer_loop_head_evidence_classify() {
  local reviewed="$1"
  local current="$2"

  if [ -z "$reviewed" ]; then
    printf 'not-reported\n'
    return 0
  fi
  if ! reviewer_loop_head_evidence_full_sha "$reviewed"; then
    printf 'not-current|unverifiable_reviewed_head\n'
    return 0
  fi
  if ! reviewer_loop_head_evidence_full_sha "$current"; then
    printf 'not-current|unverifiable_current_head\n'
    return 0
  fi

  reviewed="$(printf '%s' "$reviewed" | tr 'A-F' 'a-f')"
  current="$(printf '%s' "$current" | tr 'A-F' 'a-f')"

  if [ "$reviewed" = "$current" ]; then
    printf 'current\n'
  else
    printf 'not-current|head_mismatch\n'
  fi
}

reviewer_loop_head_evidence_render() {
  local current_head="$1"
  shift
  local entry platform_name reviewed_head classification state reason line

  printf '**Head evidence:** current PR head `%s`\n' "$current_head"
  [ "$#" -gt 0 ] || return 0

  for entry in "$@"; do
    platform_name="${entry%%:*}"
    reviewed_head="${entry#*:}"
    classification="$(reviewer_loop_head_evidence_classify "$reviewed_head" "$current_head")"
    state="${classification%%|*}"
    reason="${classification#*|}"
    if [ "$reason" = "$state" ]; then
      reason=""
    fi
    case "$state" in
      current)
        if [ -n "$reviewed_head" ]; then
          line="- ${platform_name}: reviewed \`${reviewed_head}\` — current"
        else
          line="- ${platform_name}: not-reported"
        fi
        ;;
      not-reported)
        line="- ${platform_name}: not-reported"
        ;;
      not-current)
        if [ -n "$reviewed_head" ]; then
          line="- ${platform_name}: reviewed \`${reviewed_head}\` — not-current (${reason})"
        else
          line="- ${platform_name}: not-reported"
        fi
        ;;
      *)
        line="- ${platform_name}: ${state}"
        ;;
    esac
    printf '%s\n' "$line"
  done
}

reviewer_loop_head_evidence_json() {
  local current_head="$1"
  shift
  local entry platform_name reviewed_head classification state reason
  local -a jq_parts=()
  local idx=0

  for entry in "$@"; do
    platform_name="${entry%%:*}"
    reviewed_head="${entry#*:}"
    classification="$(reviewer_loop_head_evidence_classify "$reviewed_head" "$current_head")"
    state="${classification%%|*}"
    reason="${classification#*|}"
    if [ "$reason" = "$state" ]; then
      reason=""
    fi
    jq_parts+=("--arg" "p${idx}" "$platform_name" "--arg" "rh${idx}" "$reviewed_head" "--arg" "st${idx}" "$state" "--arg" "rs${idx}" "$reason")
    idx=$((idx + 1))
  done

  if [ "$idx" -eq 0 ]; then
    printf '[]'
    return 0
  fi

  local jq_prog='['
  local i=0
  while [ "$i" -lt "$idx" ]; do
    [ "$i" -gt 0 ] && jq_prog+=','
    jq_prog+="{platform: \$p${i}, reviewed_head: \$rh${i}, state: \$st${i}, reason: \$rs${i}}"
    i=$((i + 1))
  done
  jq_prog+=']'

  jq -n "${jq_parts[@]}" "$jq_prog"
}

reviewer_loop_emit_local_ai_head_evidence_keys() {
  local local_ai_configured=0
  local local_ai_reviewed_head=""
  local local_ai_head_current=""
  local entry platform_name reviewed_head classification state

  if [ "$(expensive_gate_local_ai_configured)" = "1" ]; then
    local_ai_configured=1
  fi

  if [ "$local_ai_configured" -eq 1 ] && declare -p platform_reviewed_heads >/dev/null 2>&1; then
    for entry in "${platform_reviewed_heads[@]}"; do
      platform_name="${entry%%:*}"
      reviewed_head="${entry#*:}"
      if [ "$platform_name" = "local-ai-reviewer" ]; then
        local_ai_reviewed_head="$reviewed_head"
        classification="$(reviewer_loop_head_evidence_classify "$reviewed_head" "$loop_head_sha")"
        state="${classification%%|*}"
        case "$state" in
          current) local_ai_head_current=1 ;;
          not-current) local_ai_head_current=0 ;;
          not-reported) local_ai_head_current="" ;;
        esac
      fi
    done
  fi

  print_kv LOCAL_AI_CONFIGURED "$local_ai_configured"
  print_kv LOCAL_AI_REVIEWED_HEAD "$local_ai_reviewed_head"
  print_kv LOCAL_AI_HEAD_CURRENT "$local_ai_head_current"
}

reviewer_loop_history_current_head_sha() {
  local head_sha=""
  [ -n "${pr_number:-}" ] || return 0
  if ! head_sha="$(gh pr view "$pr_number" --json headRefOid --jq '.headRefOid // ""' 2>/dev/null)"; then
    head_sha=""
  fi
  if [ -z "$head_sha" ]; then
    # Fallback identifier (#1502 dual-cap follow-up): a failed or empty HEAD
    # SHA lookup must not silently make this ledger entry uncountable.
    # reviewer_loop_history_entries_count excludes entries with an empty
    # head_sha from both cap counts (a defensive guard against distinct-
    # but-unresolved SHAs accidentally collapsing into one bucket) — but
    # that same guard would let a REPEATED lookup failure (e.g. a
    # persistent GH API issue affecting only this endpoint) grant an
    # unlimited number of uncounted dispatches, defeating both caps (found
    # in review of PR #1507). Generate a guaranteed-unique, non-empty
    # placeholder so this entry is always countable as its own distinct
    # event instead of silently vanishing from both counters.
    head_sha="unknown-$(date +%s 2>/dev/null || printf '0')-$$-${RANDOM:-0}"
    echo "WARN: could not resolve current HEAD SHA for PR #${pr_number} while building a reviewer-loop history entry; using synthetic placeholder '$head_sha' so this cycle remains countable" >&2
  fi
  printf '%s\n' "$head_sha"
}

reviewer_loop_history_recorded_at() {
  local recorded_at=""
  [ -n "${pr_number:-}" ] || return 0
  if ! recorded_at="$(gh pr view "$pr_number" --json updatedAt --jq '.updatedAt // ""' 2>/dev/null)"; then
    recorded_at=""
  fi
  printf '%s\n' "$recorded_at"
}

reviewer_loop_history_build_entry() {
  local iteration="$1"
  local result="$2"
  local reason="$3"
  local platform_list="$4"
  local blocking="$5"
  local suggestions="$6"
  local phase_enabled="${7:-0}"
  local phase_platform_list="${8:-}"
  local phase_started="${9:-0}"
  local phase_net_new_blocker="${10:-0}"
  local phase_blocking_platform="${11:-}"
  local platforms_json
  local head_sha
  local recorded_at

  platforms_json="$(reviewer_loop_history_platforms_json "$platform_list")" || platforms_json='[]'
  head_sha="$(reviewer_loop_history_current_head_sha)"
  recorded_at="$(reviewer_loop_history_recorded_at)"
  local reviewed_heads_json
  if declare -p platform_reviewed_heads >/dev/null 2>&1 && [ "${#platform_reviewed_heads[@]}" -gt 0 ]; then
    reviewed_heads_json="$(reviewer_loop_head_evidence_json "${loop_head_sha:-}" "${platform_reviewed_heads[@]}")"
  else
    reviewed_heads_json="$(reviewer_loop_head_evidence_json "${loop_head_sha:-}")"
  fi

  # platform_results / missed_findings (#1651): caller-set globals, same
  # convention as unresolved_thread_count / current_run_id. Schema stays v1.
  local platform_results_for_entry="${platform_results_json:-[]}"
  local missed_findings_for_entry="${missed_findings_json:-[]}"
  if ! printf '%s' "$platform_results_for_entry" | jq -e 'type == "array"' >/dev/null 2>&1; then
    platform_results_for_entry='[]'
  fi
  if ! printf '%s' "$missed_findings_for_entry" | jq -e 'type == "array"' >/dev/null 2>&1; then
    missed_findings_for_entry='[]'
  fi

  # contributing_platforms (#1652): platforms that produced a counted blocking
  # finding this round. Derived from aggregate_blocking_findings; empty when
  # none. Prior ledger entries without this field fail closed in the
  # small-findings counter.
  local contributing_platforms_json='[]'
  if declare -p aggregate_blocking_findings >/dev/null 2>&1 \
      && [ "${#aggregate_blocking_findings[@]}" -gt 0 ]; then
    contributing_platforms_json="$(
      printf '%s\n' "${aggregate_blocking_findings[@]}" \
        | jq -s -c '[.[].platform // empty | select(length > 0)] | unique'
    )" || contributing_platforms_json='[]'
  fi

  # run_id (#1502 dual-cap follow-up): read from the current_run_id global,
  # following the same convention already used in this function for
  # unresolved_thread_count/late_thread_count (set by the caller before
  # invoking, not passed as a positional argument, to avoid growing an
  # already-long parameter list). Resolved once per invocation by
  # reviewer_loop_resolve_run_id in the main flow; tests set it directly.
  # Empty when unset, which jq below distinguishes from a present run_id
  # via the back-compat "(.run_id // "")" pattern used at read time.
  jq -n \
    --argjson iteration "$iteration" \
    --arg recordedAt "$recorded_at" \
    --arg headSha "$head_sha" \
    --arg runId "${current_run_id:-}" \
    --arg result "$result" \
    --arg reason "$reason" \
    --argjson platforms "$platforms_json" \
    --argjson blockingCount "${blocking:-0}" \
    --argjson suggestionCount "${suggestions:-0}" \
    --argjson unresolvedThreadCount "${unresolved_thread_count:-0}" \
    --argjson lateThreadsFound "${late_thread_count:-0}" \
    --argjson phaseEnabled "${phase_enabled:-0}" \
    --arg phasePlatforms "$phase_platform_list" \
    --argjson phaseStarted "${phase_started:-0}" \
    --argjson phaseNetNewBlocker "${phase_net_new_blocker:-0}" \
    --arg phaseBlockingPlatform "$phase_blocking_platform" \
    --argjson smallFindingsOnly "${small_findings_only:-0}" \
    --argjson smallFindingsStop "${small_findings_stop:-0}" \
    --argjson smallFindingsRounds "${small_findings_rounds:-0}" \
    --argjson smallFindingsRequiredRounds "${small_findings_required_rounds:-0}" \
    --arg smallFindingsPaths "${small_findings_paths:-}" \
    --arg classificationHead "${loop_head_sha:-}" \
    --argjson reviewedHeads "$reviewed_heads_json" \
    --argjson contributingPlatforms "$contributing_platforms_json" \
    --argjson platformResults "$platform_results_for_entry" \
    --argjson missedFindings "$missed_findings_for_entry" \
    --arg egPlatform "${expensive_gate_last_platform:-}" \
    --arg egResult "${expensive_gate_last_result:-}" \
    --arg egReason "${expensive_gate_last_reason:-}" \
    --arg egHead "${expensive_gate_last_head:-}" \
    --argjson strictRecorded "${strict_spec_recorded:-0}" \
    --arg strictState "${strict_spec_state:-}" \
    --arg strictCount "${strict_spec_count:-}" \
    --arg strictChecks "${strict_spec_checks:-}" \
    --arg strictUnknown "${strict_spec_unknown_count:-}" \
    --arg strictReason "${strict_spec_reason:-}" \
    --argjson strictPlanRecorded "${strict_plan_recorded:-0}" \
    --arg strictPlanState "${strict_plan_state:-}" \
    --arg strictPlanCount "${strict_plan_count:-}" \
    --arg strictPlanChecks "${strict_plan_checks:-}" \
    --arg strictPlanApplied "${strict_plan_applied:-}" \
    --arg strictPlanUnknown "${strict_plan_unknown_count:-}" \
    --arg strictPlanReason "${strict_plan_reason:-}" \
    --argjson localSecondPass "${local_second_pass:-0}" \
    --arg localSecondPassReason "${local_second_pass_reason:-not_required}" \
    --arg localSecondPassFailedHead "${local_second_pass_failed_head_record:-}" \
    '{
      iteration: $iteration,
      recorded_at: $recordedAt,
      head_sha: $headSha,
      classification_head: $classificationHead,
      reviewed_heads: $reviewedHeads,
      contributing_platforms: $contributingPlatforms,
      platform_results: $platformResults,
      missed_findings: $missedFindings,
      run_id: $runId,
      result: $result,
      reason: $reason,
      platforms: $platforms,
      blocking_count: $blockingCount,
      suggestion_count: $suggestionCount,
      unresolved_thread_count: $unresolvedThreadCount,
      late_threads_found: $lateThreadsFound,
      phase_after_clean: {
        enabled: ($phaseEnabled == 1),
        platforms: ($phasePlatforms | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))),
        started: ($phaseStarted == 1),
        net_new_blocker: ($phaseNetNewBlocker == 1),
        blocking_platform: $phaseBlockingPlatform
      },
      small_findings_only: ($smallFindingsOnly == 1),
      small_findings_stop: ($smallFindingsStop == 1),
      small_findings_rounds: $smallFindingsRounds,
      small_findings_required_rounds: $smallFindingsRequiredRounds,
      small_findings_paths: ($smallFindingsPaths | split("\n") | map(select(length > 0)))
    }
    | if ($egResult | length) > 0 then
        . + {expensive_gate: {platform: $egPlatform, result: $egResult, reason: $egReason, head: $egHead}}
      else
        .
      end
    | if $strictRecorded == 1 then
        . + {
          strict_spec: (
            { state: $strictState }
            | if $strictState == "applied" then
                . + {
                  count: ($strictCount | tonumber),
                  checks: ($strictChecks | if . == "" then [] else (split(",") | map(select(length > 0))) end)
                }
                | if ($strictUnknown | length) > 0 then
                    . + { unknown_count: ($strictUnknown | tonumber) }
                  else
                    .
                  end
              elif $strictState == "unavailable" then
                . + { reason: $strictReason }
              else
                .
              end
          )
        }
      else
        .
      end
    | if $strictPlanRecorded == 1 then
        . + {
          strict_plan: (
            { state: $strictPlanState }
            | if $strictPlanState == "applied" then
                . + {
                  count: ($strictPlanCount | tonumber),
                  checks: ($strictPlanChecks | if . == "" then [] else (split(",") | map(select(length > 0))) end),
                  applied: ($strictPlanApplied | if . == "" then [] else (split(",") | map(select(length > 0))) end)
                }
                | if ($strictPlanUnknown | length) > 0 then
                    . + { unknown_count: ($strictPlanUnknown | tonumber) }
                  else
                    .
                  end
              elif ($strictPlanState == "unavailable" or $strictPlanState == "not_applicable") then
                . + { reason: $strictPlanReason }
              else
                .
              end
          )
        }
      else
        .
      end
    | . + {
        local_second_pass: ($localSecondPass == 1),
        local_second_pass_reason: $localSecondPassReason
      }
    | if ($localSecondPassFailedHead | length) > 0 then
        . + {local_second_pass_failed_head: $localSecondPassFailedHead}
      else
        .
      end'
}

reviewer_loop_history_payload_from_existing() {
  local existing_body="${1:-}"
  local result="$2"
  local reason="$3"
  local platform_list="$4"
  local blocking="$5"
  local suggestions="$6"
  local phase_enabled="${7:-0}"
  local phase_platform_list="${8:-}"
  local phase_started="${9:-0}"
  local phase_net_new_blocker="${10:-0}"
  local phase_blocking_platform="${11:-}"
  local existing_json=""
  local payload=""
  local history_status="available"
  local unavailable_reason=""
  local append_safe=1
  local entry=""
  local iteration=1
  local updated_at

  existing_json="$(printf '%s\n' "$existing_body" | reviewer_loop_history_extract_latest_json)"
  if [ -n "$existing_json" ]; then
    if ! payload="$(printf '%s\n' "$existing_json" | jq -c '.' 2>/dev/null)"; then
      history_status="unavailable"
      unavailable_reason="malformed_history"
      append_safe=0
    elif ! printf '%s\n' "$payload" |
        jq -e --arg schema "$REVIEWER_LOOP_HISTORY_SCHEMA" '.schema == $schema and (.entries | type) == "array"' >/dev/null 2>&1; then
      history_status="unavailable"
      unavailable_reason="unknown_schema"
      append_safe=0
    elif [ "$(printf '%s\n' "$payload" | jq -r '.history_status // "available"')" = "unavailable" ]; then
      history_status="unavailable"
      unavailable_reason="$(printf '%s\n' "$payload" | jq -r '.history_unavailable_reason // "prior_unavailable"')"
      append_safe=0
    fi
  elif printf '%s\n' "$existing_body" | grep -Fq "$REVIEWER_LOOP_HISTORY_MARKER"; then
    history_status="unavailable"
    unavailable_reason="missing_history_json"
    append_safe=0
  else
    payload="$(jq -n \
      --arg schema "$REVIEWER_LOOP_HISTORY_SCHEMA" \
      --argjson prNumber "${pr_number:-0}" \
      '{schema: $schema, pr_number: $prNumber, updated_at: "", history_status: "available", history_unavailable_reason: "", entries: []}')"
  fi

  if [ "$append_safe" -eq 1 ]; then
    iteration="$(printf '%s\n' "$payload" | jq '(.entries // []) | length + 1')"
    entry="$(reviewer_loop_history_build_entry "$iteration" "$result" "$reason" "$platform_list" \
      "$blocking" "$suggestions" "$phase_enabled" "$phase_platform_list" \
      "$phase_started" "$phase_net_new_blocker" "$phase_blocking_platform")"
    updated_at="$(printf '%s\n' "$entry" | jq -r '.recorded_at // ""')"
    printf '%s\n' "$payload" | jq \
      --arg updatedAt "$updated_at" \
      --argjson entry "$entry" \
      '.updated_at = $updatedAt
       | .history_status = "available"
       | .history_unavailable_reason = ""
       | .entries = ((.entries // []) + [$entry])'
  else
    # #1651 AC-7a: do not replace a prior history block with an empty stub.
    # Signal unappendable state via globals; append_to_summary preserves the
    # prior details block when one exists, and only writes the stub when there
    # is no prior block at all.
    updated_at="$(reviewer_loop_history_recorded_at)"
    jq -n \
      --arg schema "$REVIEWER_LOOP_HISTORY_SCHEMA" \
      --argjson prNumber "${pr_number:-0}" \
      --arg updatedAt "$updated_at" \
      --arg status "$history_status" \
      --arg reason "$unavailable_reason" \
      '{
        schema: $schema,
        pr_number: $prNumber,
        updated_at: $updatedAt,
        history_status: $status,
        history_unavailable_reason: $reason,
        entries: []
      }'
  fi

  # Expose append decision to the summary renderer (#1651).
  reviewer_loop_history_last_append_safe="$append_safe"
  reviewer_loop_history_last_unavailable_reason="$unavailable_reason"
  if printf '%s\n' "$existing_body" | grep -Fq "$REVIEWER_LOOP_HISTORY_MARKER"; then
    reviewer_loop_history_had_prior_block=1
  else
    reviewer_loop_history_had_prior_block=0
  fi
}

reviewer_loop_history_render_section() {
  local payload="$1"
  local status
  local reason
  local count

  status="$(printf '%s\n' "$payload" | jq -r '.history_status // "available"')"
  reason="$(printf '%s\n' "$payload" | jq -r '.history_unavailable_reason // ""')"
  count="$(printf '%s\n' "$payload" | jq '(.entries // []) | length')"

  printf '\n\n<details>\n'
  if [ "$status" = "available" ]; then
    printf '<summary>Reviewer-loop history (%s iteration%s)</summary>\n\n' \
      "$count" "$([ "$count" -eq 1 ] && printf '' || printf 's')"
  else
    printf '<summary>Reviewer-loop history unavailable (%s)</summary>\n\n' "${reason:-unknown}"
  fi
  printf '%s\n' "$REVIEWER_LOOP_HISTORY_MARKER"
  printf '```json\n'
  printf '%s\n' "$payload" | jq '.'
  printf '```\n'
  printf '</details>'
}

reviewer_loop_history_unavailable_stub_body() {
  local reason="${1:-unknown}"
  local updated_at
  updated_at="$(reviewer_loop_history_recorded_at)"

  printf '%s\n' "$REVIEWER_LOOP_HISTORY_MARKER"
  printf '```json\n'
  jq -n \
    --arg schema "$REVIEWER_LOOP_HISTORY_SCHEMA" \
    --argjson prNumber "${pr_number:-0}" \
    --arg updatedAt "$updated_at" \
    --arg reason "$reason" \
    '{
      schema: $schema,
      pr_number: $prNumber,
      updated_at: $updatedAt,
      history_status: "unavailable",
      history_unavailable_reason: $reason,
      entries: []
    }'
  printf '```\n'
}

reviewer_loop_history_select_summary_record() {
  jq -rs '
    (add // []) as $all
    | [
        $all[]
        | select(
            (.body // "" | contains("### Automated Reviewer Loop Summary")) and
            (.body // "" | contains("*Posted automatically by `pr-review-loop.sh`.*"))
          )
      ]
    | sort_by(.created_at) as $comments
    | (
        $comments
        | map(
            select(
              (.body // "" | contains("reviewer_loop_history.v1")) and
              (.body // "" | test("\"history_status\"[[:space:]]*:[[:space:]]*\"available\""))
            )
          )
        | last
      ) as $history_source
    | ($comments | last) as $target
    | {
        id: ($target.id // ""),
        body: (($history_source.body // $target.body) // "")
      }
  '
}

# reviewer_loop_history_select_latest_summary_record
#
# Like reviewer_loop_history_select_summary_record, but WITHOUT the
# render-continuity fallback to an older "available" history body when the
# newest summary comment's own history is unavailable. Selects strictly the
# newest "Automated Reviewer Loop Summary" comment by created_at and returns
# ITS OWN body verbatim, regardless of whether its embedded history block
# says available or unavailable.
#
# Use this selector for CYCLE-COUNTING purposes (reviewer_loop_resolve_
# cycle_counts) — reviewer_loop_history_select_summary_record's older-
# history fallback exists to keep the VISIBLE summary comment's rendered
# history table from regressing when a transient write failure marks the
# newest entry unavailable, but that same fallback would silently return a
# STALE (and possibly under-counted) cycle count to the cap-enforcement
# logic while masking the fact that the newest ledger state is actually
# unreadable — defeating the fail-closed guarantee in reviewer_loop_
# cycle_count_unavailable_should_escalate (found in review of PR #1507).
# Counting must always see the newest ledger's true status, even when that
# status is "unavailable".
reviewer_loop_history_select_latest_summary_record() {
  jq -rs '
    (add // []) as $all
    | [
        $all[]
        | select(
            (.body // "" | contains("### Automated Reviewer Loop Summary")) and
            (.body // "" | contains("*Posted automatically by `pr-review-loop.sh`.*"))
          )
      ]
    | sort_by(.created_at)
    | last
    | {
        id: (.id // ""),
        body: (.body // "")
      }
  '
}

reviewer_loop_history_extract_preserved_section() {
  local existing_body="$1"
  local prior=""

  prior="$(printf '%s\n' "$existing_body" | awk '
    /<details>/ { in_details=1 }
    in_details { buf = buf $0 "\n" }
    /<\/details>/ && in_details {
      if (index(buf, "<!-- reviewer-loop-history:v1 -->") > 0) {
        latest = buf
      }
      buf = ""
      in_details = 0
    }
    END { printf "%s", latest }
  ')"
  if [ -n "$prior" ]; then
    printf '%s' "$prior"
    return 0
  fi

  if ! printf '%s\n' "$existing_body" | grep -Fq "$REVIEWER_LOOP_HISTORY_MARKER"; then
    return 1
  fi

  # Marker-only blocks (e.g. unavailable stub) have no <details> wrapper.
  printf '%s\n' "$existing_body" | awk -v marker="$REVIEWER_LOOP_HISTORY_MARKER" '
    index($0, marker) { in_block=1 }
    in_block {
      print
      if ($0 ~ /^```json/) { in_fence=1; next }
      if (in_fence && $0 ~ /^```[[:space:]]*$/) { exit }
    }
  '
}

reviewer_loop_history_append_to_summary() {
  local comment_body="$1"
  local existing_body="${2:-}"
  shift 2
  local payload
  local section
  local prior_section=""

  reviewer_loop_history_last_append_safe=1
  reviewer_loop_history_last_unavailable_reason=""
  reviewer_loop_history_had_prior_block=0

  # Capture payload without losing append_safe globals: write to a temp file
  # from the current shell, then read it back.
  local _payload_tmp
  _payload_tmp="$(mktemp)"
  if ! reviewer_loop_history_payload_from_existing "$existing_body" "$@" >"$_payload_tmp" 2>/dev/null; then
    reviewer_loop_history_last_append_safe=0
    reviewer_loop_history_last_unavailable_reason="history_render_failed"
    if printf '%s\n' "$existing_body" | grep -Fq "$REVIEWER_LOOP_HISTORY_MARKER"; then
      reviewer_loop_history_had_prior_block=1
    fi
    jq -n \
      --arg schema "$REVIEWER_LOOP_HISTORY_SCHEMA" \
      --argjson prNumber "${pr_number:-0}" \
      --arg updatedAt "$(reviewer_loop_history_recorded_at)" \
      --arg reason "${reviewer_loop_history_last_unavailable_reason:-history_render_failed}" \
      '{
        schema: $schema,
        pr_number: $prNumber,
        updated_at: $updatedAt,
        history_status: "unavailable",
        history_unavailable_reason: $reason,
        entries: []
      }' >"$_payload_tmp"
  fi
  payload="$(cat "$_payload_tmp")"
  rm -f "$_payload_tmp"

  # #1651 AC-7a: when history cannot be appended and a prior block exists,
  # leave that block byte-for-byte unchanged — do not re-render a stub over it.
  if [ "${reviewer_loop_history_last_append_safe:-1}" -eq 0 ] \
      && [ "${reviewer_loop_history_had_prior_block:-0}" -eq 1 ]; then
    prior_section="$(reviewer_loop_history_extract_preserved_section "$existing_body")"
    if [ -n "$prior_section" ]; then
      printf '%s\n\n%s\n' "$comment_body" "$prior_section"
      return 0
    fi
  fi

  section="$(reviewer_loop_history_render_section "$payload")"
  printf '%s%s\n' "$comment_body" "$section"
}

# ---------------------------------------------------------------------------
# reviewer-loop max_cycles enforcement (#1502, dual-cap follow-up)
#
# Protocol 93 documents a hard cycle cap ("a hard limit independent of
# finding counts") but nothing enforced it — the loop relied entirely on the
# calling orchestrator/agent to count cycles and escalate manually. Evidence:
# PR #1492 in this repository reached 18 reviewer-loop iterations against a
# documented cap of 10 (see reviewer_loop_history.v1 on that PR) with no
# max_cycles escalation. This block makes the script itself the source of
# truth for the cycle count and the enforcement point, independent of
# whatever the caller does or fails to do.
#
# TWO independent caps, per operator decision on PR #1507's review:
#
#   1. Per-run cap (CYCLE_COUNT / MAX_CYCLES, review.max_cycles, default 10):
#      resets to 0 at each orchestration-run boundary. This conforms to
#      Protocol 91:1719 verbatim: "Initialize cycle = 0 once per
#      orchestration run for the PR. Increment cycle each time a fixer
#      agent is dispatched. Do not reset cycle after a fixer push; escalate
#      when the run reaches max_cycles." Escalates with
#      REASON=max_cycles_exceeded.
#   2. Lifetime ceiling (TOTAL_CYCLE_COUNT / MAX_TOTAL_CYCLES,
#      review.max_total_cycles, default 25): never resets, counts across
#      the PR's entire review-loop lifetime regardless of run boundaries.
#      Escalates with the distinct REASON=max_total_cycles_exceeded.
#
# Why both, not either/or: a per-run-only cap leaves total effort unbounded
# — a PR resumed across many separate orchestration runs gets a fresh
# budget every time, which is exactly the "runs until someone notices"
# failure #1502 exists to end (the ~50-cycle / 18-hour downstream incident
# cited in #1502 plausibly spanned multiple runs). A lifetime-only cap
# contradicts Protocol 91:1719's explicit "initialize cycle = 0 once per
# orchestration run" instruction. Both together satisfy each: the per-run
# cap matches the protocol exactly, and the lifetime ceiling is the
# structural backstop that does not depend on every caller correctly
# threading a stable run identifier through every invocation.
#
# What is counted (both caps): fixer-dispatch-triggering cycles. Only prior
# ledger entries whose `result` is `needs_fixes` or `needs_rerun` are
# candidates — each such result is exactly the trigger condition for a
# fixer dispatch (or, for needs_rerun, PR-Agent's equivalent auto-push
# retry). The initial review and any `clean`/`skipped` entries are excluded.
# Among candidates, only DISTINCT (HEAD SHA, result) PAIRS are counted (not
# raw entry count, and not distinct HEAD SHA alone): a completed fixer
# cycle is required to push a new commit before the next review runs
# (Protocol 93's mandatory push-once-per-cycle discipline), so two
# candidates sharing one HEAD SHA AND the SAME result mean no fix was
# actually applied between them (a restarted runner, a duplicate/retried
# invocation, or a review re-run before the orchestrator dispatched a
# fixer) and must not be double-counted. Deduping by HEAD SHA alone would
# be too aggressive: a needs_rerun entry (PR-Agent's auto-push evaluation
# completing a fix cycle) immediately followed by a needs_fixes entry on
# THAT SAME resulting HEAD SHA (a different reviewer finding a NEW,
# unrelated issue on the post-auto-fix state) are two genuinely distinct
# dispatch events, not a duplicate of one — collapsing them into one would
# let more than the configured number of real fixes happen before either
# cap fires (found in review of PR #1507). Keying on (head_sha, result)
# instead of head_sha alone dedupes true duplicates (same head_sha AND
# same result — no progress since the last check) while still counting a
# needs_rerun→needs_fixes sequence on the same head_sha as two events.
#
# Run-boundary tracking (schema, chosen deliberately as an ADDITIVE field,
# not a schema version bump): each ledger entry now carries an optional
# `run_id` string, resolved once per invocation by
# reviewer_loop_resolve_run_id and threaded into
# reviewer_loop_history_build_entry via the `current_run_id` global (the
# same pattern already used for `unresolved_thread_count`/`late_thread_count`
# in that function — no signature change needed). An additive optional
# field (not a `reviewer_loop_history.v2` schema bump) was chosen because:
#   - It is fully backward- and forward-compatible: every existing
#     `.schema == "reviewer_loop_history.v1"` check across this script
#     continues to validate unchanged, and no in-flight PR's already-
#     recorded history needs migrating mid-flight.
#   - The field is genuinely optional at read time (see back-compat policy
#     below), so there is no ambiguity a version bump would need to resolve.
#
# Back-compat policy for entries with no `run_id` (written by the
# pre-dual-cap version of this script — this literally happened on PR #1507
# itself, cycles 1-5, before this field existed): such entries ARE counted
# toward the LIFETIME ceiling (they represent real historical fixer
# dispatches — the lifetime cap must not blind itself to real prior
# effort), but they can NEVER satisfy any specific per-run count, because
# an entry with no `run_id` cannot match any current invocation's
# (non-empty) resolved run_id. This means an old PR does not get an
# artificially reset per-run budget just because its early history predates
# run-id tracking — the lifetime ceiling still sees that history — while
# the per-run counter correctly starts fresh for the first run-id-aware
# invocation (since no prior entry could possibly match a brand-new run id).
#
# Reset semantic per axis (deliberately NOT reset-on-new-head-SHA on
# EITHER axis): a genuinely new HEAD SHA always adds to both counts; this
# is the opposite of the "reset on new push" option the originating issue
# offered as an alternative, and the choice is deliberate on this axis
# specifically: the motivating failure (PR #1492, 18 cycles) involved a new
# HEAD SHA on nearly every cycle, because each cycle's fix is a new commit.
# A reset-on-head-change design would set both counters back to 0 on almost
# every invocation and would never have caught that exact case.
#
# The inline-fix retry lane (Protocol 93's "fast lane" for mechanical fixes)
# is bounded by the same two counters without any extra logic: every
# re-invocation of this script — whether triggered by an inline fix or a
# dispatched fixer subagent — reads the same persisted ledger and is
# subject to the same caps.
# ---------------------------------------------------------------------------

# reviewer_loop_resolve_run_id
#
# Resolves the run identifier for this invocation. Precedence:
#   1. PR_REVIEW_LOOP_RUN_ID env var — set by an orchestrator that wants to
#      group multiple pr-review-loop.sh invocations under one
#      Protocol-91-style "orchestration run" (so the per-run cap
#      accumulates correctly across those invocations, and resets when the
#      orchestrator starts a genuinely new run with a new id).
#   2. A freshly generated id (`auto-<epoch seconds>-<pid>-<$RANDOM>`) when
#      the env var is not set. Each such auto-generated invocation is, by
#      construction, its own isolated "run" for per-run cap purposes — no
#      prior ledger entry can share a freshly generated id — so the per-run
#      cap effectively becomes a no-op unless the caller opts in by setting
#      PR_REVIEW_LOOP_RUN_ID consistently across a session. The LIFETIME
#      ceiling is unaffected by this and still enforces regardless of
#      caller participation, which is exactly why both caps exist together.
reviewer_loop_resolve_run_id() {
  local configured="${PR_REVIEW_LOOP_RUN_ID:-}"

  if [ -n "$configured" ]; then
    printf '%s\n' "$configured"
    return 0
  fi

  printf 'auto-%s-%s-%s\n' "$(date +%s)" "$$" "$RANDOM"
}

# reviewer_loop_history_entries_count <comment_body> <run_id>
#
# Prints "<lifetime_count> <run_count> <status>" (space-separated) where:
#   lifetime_count — number of DISTINCT (head_sha, result) PAIRS among ALL
#            prior fixer-dispatch-triggering entries (result ==
#            "needs_fixes" or "needs_rerun", with a non-empty head_sha),
#            regardless of run_id — i.e. the lifetime-ceiling count — or -1
#            when that count cannot be determined reliably. Keying on the
#            pair rather than head_sha alone counts a needs_rerun entry
#            immediately followed by a needs_fixes entry on the SAME
#            resulting head_sha as two distinct dispatches (a completed
#            auto-fix, then a different NEW issue found on that state) —
#            see the block comment above for why deduping by head_sha
#            alone would be too aggressive.
#   run_count — the same DISTINCT-(head_sha,result)-PAIR count, but
#            restricted to entries whose `run_id` field exactly equals
#            <run_id> — i.e. the per-run-cap count (Protocol 91's `cycle`
#            value at the start of this invocation) — or -1 alongside
#            lifetime_count on failure.
#            Entries with no `run_id` (back-compat, pre-dual-cap entries)
#            never match and are excluded from this count, but ARE still
#            included in lifetime_count (see the back-compat policy in the
#            comment block above). An empty <run_id> never matches anything
#            — including another entry whose own run_id is also empty/
#            absent — so querying with an empty run_id always yields
#            run_count 0 rather than accidentally matching every back-
#            compat entry via "empty == empty".
#   status — "available" when both counts can be trusted, "unavailable"
#            otherwise (missing/malformed JSON, wrong schema, or a
#            persisted history block that itself already recorded
#            history_status=unavailable).
#
# An empty <comment_body>, or a body with no history marker at all, is the
# normal "no prior reviewer-loop run" state and returns "0 0 available"
# (cycle 0 on both axes, matching Protocol 91's initial value) — it is not
# an error condition.
reviewer_loop_history_entries_count() {
  local body="${1:-}"
  local run_id="${2:-}"
  local json counts lifetime_count run_count

  if [ -z "$body" ]; then
    printf '%s %s %s\n' 0 0 available
    return 0
  fi

  json="$(printf '%s\n' "$body" | reviewer_loop_history_extract_latest_json)"
  if [ -z "$json" ]; then
    if printf '%s\n' "$body" | grep -Fq "$REVIEWER_LOOP_HISTORY_MARKER"; then
      # Marker present but no parseable ```json block — history is present
      # but unreadable; do not silently treat it as zero cycles.
      printf '%s %s %s\n' -1 -1 unavailable
    else
      printf '%s %s %s\n' 0 0 available
    fi
    return 0
  fi

  if ! printf '%s\n' "$json" | jq -e --arg schema "$REVIEWER_LOOP_HISTORY_SCHEMA" '
        .schema == $schema
        and (.entries | type) == "array"
        and ((.history_status // "available") == "available")
      ' >/dev/null 2>&1; then
    printf '%s %s %s\n' -1 -1 unavailable
    return 0
  fi

  counts="$(printf '%s\n' "$json" | jq -r --arg runId "$run_id" '
        [
          .entries[]?
          | select((.result // "") == "needs_fixes" or (.result // "") == "needs_rerun")
          # A head that moved during an otherwise clean run dispatches no
          # fixer; it is a re-run, not a cycle (issue #1574).
          | select((.reason // "") != "head_moved_during_run")
        ] as $qualifying
        | ($qualifying
            | [.[] | select((.head_sha // "") | length > 0) | ((.head_sha // "") + "|" + (.result // ""))]
            | unique
            | length) as $lifetime
        | ($qualifying
            | [.[] | select(($runId | length) > 0 and (.run_id // "") == $runId and ((.head_sha // "") | length > 0)) | ((.head_sha // "") + "|" + (.result // ""))]
            | unique
            | length) as $run
        | "\($lifetime) \($run)"
      ' 2>/dev/null)" || counts=""
  read -r lifetime_count run_count <<<"$counts"

  if ! [[ "${lifetime_count:-}" =~ ^[0-9]+$ ]] || ! [[ "${run_count:-}" =~ ^[0-9]+$ ]]; then
    printf '%s %s %s\n' -1 -1 unavailable
    return 0
  fi

  printf '%s %s %s\n' "$lifetime_count" "$run_count" available
}

# reviewer_loop_resolve_max_cycles <config_value>
#
# Resolves the effective PER-RUN cap (Protocol 91:1719's `max_cycles`).
# Precedence:
#   1. PR_REVIEW_LOOP_MAX_CYCLES env var
#   2. <config_value> (caller passes the raw review.max_cycles string read
#      from .ai-dev-workflow.yaml via workflow_config_review_max_cycles)
#   3. Default: 10 (Protocol 93's documented value)
#
# Any value that is not a positive integer, or is outside the supported
# range (1-999999), falls back to the default with a WARN on stderr. The
# range is capped at 6 digits — comfortably below any risk of exceeding
# Bash's signed integer range in the later `[ "$cycle_count" -ge
# "$max_cycles" ]` comparison in reviewer_loop_cap_exceeded (which would
# otherwise emit "integer expression expected" and silently evaluate to
# false, defeating the cap for an absurdly large misconfigured value) — and
# no sane max_cycles value is anywhere near that large regardless.
reviewer_loop_resolve_max_cycles() {
  local config_value="${1:-}"
  local configured="${PR_REVIEW_LOOP_MAX_CYCLES:-}"
  local source="env"

  if [ -z "$configured" ]; then
    configured="$config_value"
    source="config (review.max_cycles)"
  fi
  if [ -z "$configured" ]; then
    configured=10
    source="default"
  fi
  if ! [[ "$configured" =~ ^[1-9][0-9]{0,5}$ ]]; then
    echo "WARN: max_cycles value '$configured' (source: $source) is not a positive integer within the supported range (1-999999); defaulting to 10" >&2
    configured=10
  fi
  printf '%s\n' "$configured"
}

# reviewer_loop_resolve_max_total_cycles <config_value>
#
# Resolves the effective LIFETIME ceiling. Precedence:
#   1. PR_REVIEW_LOOP_MAX_TOTAL_CYCLES env var
#   2. <config_value> (caller passes the raw review.max_total_cycles string
#      read from .ai-dev-workflow.yaml via
#      workflow_config_review_max_total_cycles)
#   3. Default: 25
#
# Same validation rule as reviewer_loop_resolve_max_cycles (positive
# integer, 1-999999) for the same reasons.
reviewer_loop_resolve_max_total_cycles() {
  local config_value="${1:-}"
  local configured="${PR_REVIEW_LOOP_MAX_TOTAL_CYCLES:-}"
  local source="env"

  if [ -z "$configured" ]; then
    configured="$config_value"
    source="config (review.max_total_cycles)"
  fi
  if [ -z "$configured" ]; then
    configured=25
    source="default"
  fi
  if ! [[ "$configured" =~ ^[1-9][0-9]{0,5}$ ]]; then
    echo "WARN: max_total_cycles value '$configured' (source: $source) is not a positive integer within the supported range (1-999999); defaulting to 25" >&2
    configured=25
  fi
  printf '%s\n' "$configured"
}

# reviewer_loop_cap_exceeded <cycle_count> <max_cycles> <result>
#
# Generic cap check reused for BOTH axes (call once with the per-run count
# and per-run limit, and again with the lifetime count and lifetime limit).
# Returns 0 (true — cap exceeded, caller should escalate) only when the loop
# would otherwise keep going (result is needs_fixes or needs_rerun) and
# cycle_count is known (>= 0) and has reached or passed max_cycles. A result
# of "clean" is never overridden — a genuinely resolved PR is not escalated
# just because it took many cycles to get there. An unknown cycle_count (-1,
# from unreadable history) is handled separately by
# reviewer_loop_cycle_count_unavailable_should_escalate below — this
# function's job is strictly "is the known count at or past the cap".
reviewer_loop_cap_exceeded() {
  local cycle_count="$1"
  local max_cycles="$2"
  local result="$3"

  case "$result" in
    needs_fixes|needs_rerun) : ;;
    *) return 1 ;;
  esac

  [ "$cycle_count" -ge 0 ] && [ "$cycle_count" -ge "$max_cycles" ]
}

# reviewer_loop_cycle_count_unavailable_should_escalate <cycle_count> <result>
#
# Returns 0 (true — escalate) when the cycle ledger could not be read
# reliably (cycle_count == -1) and the loop would otherwise keep going
# (result is needs_fixes or needs_rerun). Fails CLOSED, matching this
# script's existing convention for other safety-critical audits (see
# check_unresolved_threads: "we cannot confirm threads are resolved, so
# RESULT=clean must not be emitted ... never degrade gracefully — a silent
# bypass ... can allow PRs with unresolved review threads to be labeled
# ready-for-human-review"). A hard cycle-count backstop that silently goes
# dark whenever its own state cannot be read would defeat the purpose it
# exists for exactly as much as if it had never been implemented (found in
# review of PR #1507) — reviewer_loop_resolve_cycle_counts already retries
# transient failures before returning -1, so a -1 here reflects a
# genuinely unreadable ledger, not a single flaky API call. Both the
# per-run and lifetime counts always fail together (they come from the same
# ledger read), so this is checked once against either count.
reviewer_loop_cycle_count_unavailable_should_escalate() {
  local cycle_count="$1"
  local result="$2"

  case "$result" in
    needs_fixes|needs_rerun) : ;;
    *) return 1 ;;
  esac

  [ "$cycle_count" -eq -1 ]
}

# reviewer_loop_persist_failure_should_escalate <post_summary_exit_code> <result>
#
# Returns 0 (true — escalate) when this cycle's reviewer_loop_history.v1
# ledger entry could not be persisted (<post_summary_exit_code> is non-zero
# — both _post_review_summary's PATCH and create-fallback failed) AND this
# cycle's own result was needs_fixes or needs_rerun (dispatch-triggering).
# A "clean" or already-"escalate" result is never affected — no fixer
# dispatch is at risk of going uncounted in those cases. Fails CLOSED,
# matching the same rationale as reviewer_loop_cycle_count_unavailable_
# should_escalate: a persistence failure that silently lets the caller
# dispatch an uncounted fixer defeats both caps exactly as much as an
# unreadable ledger does (found in review of PR #1507).
#
# Kept as its own pure, directly-testable function (defined before the
# HARNESS_MODE return point) because _post_review_summary itself is defined
# after that point (it does real gh API side effects) and is not directly
# unit-testable from the harness — this function isolates the decision
# logic so it can be verified without a full main-loop subprocess run.
reviewer_loop_persist_failure_should_escalate() {
  local post_summary_exit_code="$1"
  local result="$2"
  local reason="${3:-}"

  case "$result" in
    needs_fixes|needs_rerun) : ;;
    *) return 1 ;;
  esac
  # A head that moved during a clean run dispatches no fixer and is not
  # counted as a cycle, so an unpersisted ledger cannot let an unbounded
  # dispatch through; a transient comment failure there is not a reason to
  # pull a human in (issue #1574).
  [ "$reason" != "head_moved_during_run" ] || return 1

  [ "$post_summary_exit_code" -ne 0 ]
}

# reviewer_loop_resolve_cycle_counts <pr_number> <run_id>
#
# Resolves BOTH this invocation's per-run cycle count (Protocol 91's `cycle`
# value, scoped to <run_id>) and the PR's lifetime cycle count, by reading
# the persisted reviewer_loop_history.v1 ledger from the PR's "Automated
# Reviewer Loop Summary" comment (the same ledger written by
# reviewer_loop_history_append_to_summary / _post_review_summary) via
# reviewer_loop_history_entries_count. Prints "<lifetime_count> <run_count>"
# (space-separated), or "-1 -1" when the prior counts could not be
# determined reliably (repo slug unresolved, GitHub API failure after
# retries, or an unreadable/malformed history block) — never guesses.
#
# The GitHub comments fetch is retried (default: 1 retry, i.e. 2 total
# attempts) before giving up, so a single transient API blip does not
# immediately surface as "unavailable" (which reviewer_loop_cycle_count_
# unavailable_should_escalate treats as a hard escalation). Configurable via
# CYCLE_LEDGER_MAX_RETRIES (attempts beyond the first) and
# CYCLE_LEDGER_RETRY_WAIT (seconds between attempts; tests set this to 0).
#
# Uses reviewer_loop_history_select_latest_summary_record (NOT
# reviewer_loop_history_select_summary_record) — the newest summary
# comment's own history status must govern counting, even when it is
# "unavailable". reviewer_loop_history_select_summary_record's older-
# history fallback exists for the render path only (so the visible summary
# comment's history table does not regress on a transient write failure);
# using it here would let a genuinely unreadable newest ledger state
# silently resolve to a stale (and possibly under-counted) prior count
# instead of -1, masking a real dispatch from both caps and defeating the
# fail-closed guarantee (found in review of PR #1507).
#
# Kept as its own function (defined before the HARNESS_MODE return point, like
# restore_regression_label_if_missing) so it is directly unit-testable via the
# MOCK_GH_COMMENTS_OUTPUT / MOCK_GH_COMMENTS_EXIT harness conventions, without
# requiring a full main-loop subprocess run.
reviewer_loop_resolve_cycle_counts() {
  local pr_number_arg="$1"
  local run_id_arg="${2:-}"
  local repo="" record="" body="" lifetime_count run_count status
  local max_retries retry_wait attempt

  if [ -z "$pr_number_arg" ]; then
    printf '%s %s\n' -1 -1
    return 0
  fi

  if ! repo="$(repo_slug 2>/dev/null)" || [ -z "$repo" ]; then
    echo "WARN: could not resolve repo slug while resolving reviewer cycle counts for PR #${pr_number_arg}; treating prior cycle counts as unavailable" >&2
    printf '%s %s\n' -1 -1
    return 0
  fi

  # Bounded the same way as reviewer_loop_resolve_max_cycles/
  # reviewer_loop_resolve_max_total_cycles (1-999999, up to 6 digits): an
  # unbounded ^[0-9]+$ regex would accept a digit-only value outside Bash's
  # signed integer range, and the later `[ "$attempt" -gt "$max_retries" ]`
  # comparison would then emit "integer expression expected" and evaluate
  # as false every time (a `[ ]` failure inside an `if` condition does not
  # trigger `set -e`) — so the retry loop would never reach its "give up"
  # branch and retry indefinitely instead of failing closed (found in
  # review of PR #1507).
  max_retries="${CYCLE_LEDGER_MAX_RETRIES:-1}"
  if ! [[ "$max_retries" =~ ^[0-9]{1,6}$ ]]; then
    max_retries=1
  fi
  retry_wait="${CYCLE_LEDGER_RETRY_WAIT:-2}"
  if ! [[ "$retry_wait" =~ ^[0-9]{1,6}$ ]]; then
    retry_wait=2
  fi

  attempt=0
  record=""
  while true; do
    attempt=$((attempt + 1))
    if record="$(
        set -o pipefail
        gh api "repos/$repo/issues/$pr_number_arg/comments" --paginate 2>/dev/null \
          | reviewer_loop_history_select_latest_summary_record
      )"; then
      break
    fi
    if [ "$attempt" -gt "$max_retries" ]; then
      echo "WARN: failed to fetch existing summary comments for PR ${pr_number_arg} while resolving reviewer cycle counts (attempt $attempt/$((max_retries + 1))); treating prior cycle counts as unavailable" >&2
      printf '%s %s\n' -1 -1
      return 0
    fi
    echo "WARN: failed to fetch existing summary comments for PR ${pr_number_arg} while resolving reviewer cycle counts (attempt $attempt/$((max_retries + 1))) — retrying" >&2
    [ "$retry_wait" -gt 0 ] && sleep "$retry_wait"
  done

  body="$(printf '%s\n' "$record" | jq -r '.body // ""' 2>/dev/null)" || body=""
  read -r lifetime_count run_count status < <(reviewer_loop_history_entries_count "$body" "$run_id_arg")

  if [ "$status" = "available" ]; then
    printf '%s %s\n' "$lifetime_count" "$run_count"
  else
    printf '%s %s\n' -1 -1
  fi
}

reviewer_loop_fetch_latest_summary_body() {
  local pr_number_arg="$1"
  local repo="" record="" body=""

  if [ -z "$pr_number_arg" ]; then
    return 0
  fi
  if ! repo="$(repo_slug 2>/dev/null)" || [ -z "$repo" ]; then
    return 0
  fi
  record="$(
    set -o pipefail
    gh api "repos/$repo/issues/$pr_number_arg/comments" --paginate 2>/dev/null \
      | reviewer_loop_history_select_latest_summary_record
  )" || return 0
  body="$(printf '%s\n' "$record" | jq -r '.body // ""' 2>/dev/null)" || body=""
  printf '%s\n' "$body"
}


# ---------------------------------------------------------------------------
# _check_release_pr_guard <pr_number> [<branch_name>]
#
# Determines whether the given PR is a release or hotfix PR that should skip
# the automated reviewer loop. Returns 0 (guard fires → skip) or 1 (guard
# does not fire → continue normally).
#
# Detection is based exclusively on the head branch name:
#   release/* — release PR (release/vX.Y.Z → main or develop backport)
#   hotfix/*  — hotfix PR (hotfix/vX.Y.Z → main)
#
# Relying on the head branch name (not base branch) avoids false-positive
# matches for non-release PRs that might target main outside the standard
# gitflow workflow. In this workflow, all release and hotfix PRs use the
# release/* or hotfix/* prefix by convention.
#
# Output (stdout, key=value lines):
#   RELEASE_GUARD_HEAD=<head branch or empty>
#   RELEASE_GUARD_FIRED=0|1
#
# When <branch_name> is provided, it is used directly for head-branch matching
# without a network call. When omitted, the head branch is fetched from the PR.
# ---------------------------------------------------------------------------
_check_release_pr_guard() {
  local pr_num="$1"
  local given_branch="${2:-}"
  local guard_head=""
  local is_release=0

  guard_head="$given_branch"

  if [ -z "$guard_head" ]; then
    # Fetch the head branch from GitHub. Steps are separated so that gh failures
    # and jq parse failures are each caught explicitly.
    #
    # Fail-safe design: if the branch cannot be determined (gh failure, empty
    # JSON, or jq error), guard_head stays empty. An empty guard_head does NOT
    # match release/* or hotfix/*, so the guard does not fire and the reviewer
    # loop runs normally. For this SKIP guard (not a BLOCK guard), failing open
    # means running the reviewer loop — the safe default, not a dangerous one.
    local _gh_json=""
    local _gh_exit=0
    set +e
    _gh_json="$(gh pr view "$pr_num" --json headRefName 2>/dev/null)"
    _gh_exit=$?
    set -e
    if [ "$_gh_exit" -eq 0 ] && [ -n "$_gh_json" ]; then
      local _jq_exit=0
      set +e
      guard_head="$(printf '%s\n' "$_gh_json" | jq -r '.headRefName // ""' 2>/dev/null)"
      _jq_exit=$?
      set -e
      [ "$_jq_exit" -ne 0 ] && guard_head=""
    fi
    # guard_head remains empty on any failure — guard does not fire.
  fi

  case "$guard_head" in
    release/*|hotfix/*) is_release=1 ;;
  esac

  printf 'RELEASE_GUARD_HEAD=%s\n' "$guard_head"
  printf 'RELEASE_GUARD_FIRED=%s\n' "$is_release"

  if [ "$is_release" -eq 1 ]; then
    return 0
  fi
  return 1
}

# resolve_local_review_override_root <initiating_root>
#
# Prints the directory whose .ai-dev-workflow.local.yaml carries the review
# policy for this run, or nothing when the policy is the shared config. The
# resolver reports LOCAL_OVERRIDE_FILE, which is the initiating root's own file
# or — when the initiating root is a linked worktree without one — the main
# clone's (#1560). Printing the file's directory rather than the initiating
# root keeps the exported WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT pointing at a
# directory that actually holds the file.
resolve_local_review_override_root() {
  local initiating_root="$1"
  local caller_override_root="${WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT:-}"
  local override_context=""
  local override_source=""
  local override_file=""

  if [ -n "$caller_override_root" ]; then
    if [ ! -d "$caller_override_root" ]; then
      return 1
    fi
    printf '%s\n' "$caller_override_root"
    return 0
  fi

  if ! override_context="$(workflow_review_override_context "$initiating_root")"; then
    return 1
  fi
  override_source="$(workflow_context_value "LOCAL_OVERRIDE_SOURCE" "$override_context")"
  override_file="$(workflow_context_value "LOCAL_OVERRIDE_FILE" "$override_context")"
  if [ -n "$override_source" ]; then
    if [ -n "$override_file" ]; then
      printf '%s\n' "$(dirname -- "$override_file")"
    else
      printf '%s\n' "$initiating_root"
    fi
  fi
}

# Skip the main execution block when sourced in test-harness mode.
# All function definitions above (including normalize_platform_verdict,
# append_compare_metrics_row, and restore_regression_label_if_missing) are
# loaded; only the argument-parsing and execution sections below are skipped.
# ---------------------------------------------------------------------------
# Post-clean settle window (issue #1556)
#
# The old behaviour was a single 30-second wait followed by one thread re-query.
# That is far too short for CodeRabbit, which posts findings minutes after it
# first goes quiet. Measured: PR #1532 two late findings, #1541 three across
# three rounds, #1555 five across two rounds, and again during #1537/#1562 —
# eight on one PR across two post-clean rounds, two of them Major. Every late
# finding was real. Nothing escaped only because runners were told to hold a
# 2-3 minute quiet window and re-query by hand, which is operator discipline
# standing in for a tooling guarantee.
#
# The verdict now means "clean, and still clean after the vendor went quiet":
# poll until the platform has produced NO activity for a full quiet period, or
# until the overall window is exhausted. Any activity resets the quiet timer,
# because a vendor that just spoke is likely to speak again.
#
# _settle_config_for_platform <platform> — echoes "window quiet poll" seconds.
#
# Per-platform (AC-4), because vendors differ by an order of magnitude and a
# window sized for the slowest would tax every other platform. Resolution
# order, most specific first:
#   1. <PLATFORM>_POST_CLEAN_SETTLE_WINDOW / _QUIET / _POLL   (e.g. CODERABBIT_)
#   2. POST_CLEAN_SETTLE_WINDOW / POST_CLEAN_SETTLE_QUIET / POST_CLEAN_POLL
#   3. the per-platform defaults below
#
# POST_CLEAN_WAIT is still honoured as the quiet period when nothing more
# specific is set, so existing callers keep working.
_settle_config_for_platform() {
  local platform="$1"
  local window quiet poll
  local prefix
  # coderabbit-cli shares CodeRabbit's posting behaviour.
  case "$platform" in
    coderabbit|coderabbit-cli) prefix="CODERABBIT" ;;
    *) prefix="$(printf '%s' "$platform" | tr '[:lower:]-' '[:upper:]_')" ;;
  esac
  # The prefix is interpolated into a variable NAME below. Reject anything that
  # is not a valid shell identifier rather than trusting the tr transform to
  # have neutralised it: platform reaches here from --platform and from the
  # workflow config, neither of which is validated upstream. An unusable prefix
  # simply means no per-platform overrides — the generic knobs and the defaults
  # still apply, so a strange platform name degrades instead of failing.
  case "$prefix" in
    ''|*[!A-Za-z0-9_]*) prefix="" ;;
    [0-9]*) prefix="" ;;
  esac

  # require_review: whether silence alone may satisfy the settle, or whether a
  # formal review submission for the current HEAD is required first.
  #
  # This is the distinction the first implementation of #1556 missed, and the
  # measurement that forced it: on PR #1573, HEAD landed at 00:17:29, CodeRabbit
  # posted its WALKTHROUGH comment 48s later at 00:18:17, and the loop treated
  # that as "reviewed, no findings" and returned clean. The actual review was
  # submitted at 00:30:32 — twelve minutes after the walkthrough — carrying
  # three findings. A quiet period cannot help here: CodeRabbit was completely
  # silent for the whole 180s window because it was still thinking.
  #
  # Silence is an absence signal and cannot distinguish "done" from "working".
  # For CodeRabbit the settle therefore waits for a positive one.
  local require_review
  case "$platform" in
    coderabbit|coderabbit-cli)
      # Window sized from the observed walkthrough-to-review gap (~12 min),
      # not guessed.
      window=900; quiet=120; poll=60; require_review=1
      ;;
    *)
      window=180; quiet=60; poll=30; require_review=0
      ;;
  esac

  local v _n
  v=""
  if [ -n "$prefix" ]; then _n="${prefix}_POST_CLEAN_SETTLE_WINDOW"; v="${!_n:-}"; fi
  [ -n "$v" ] || v="${POST_CLEAN_SETTLE_WINDOW:-}"
  case "$v" in ''|*[!0-9]*) ;; *) window="$v" ;; esac

  v=""
  if [ -n "$prefix" ]; then _n="${prefix}_POST_CLEAN_SETTLE_QUIET"; v="${!_n:-}"; fi
  [ -n "$v" ] || v="${POST_CLEAN_SETTLE_QUIET:-${POST_CLEAN_WAIT:-}}"
  case "$v" in ''|*[!0-9]*) ;; *) quiet="$v" ;; esac

  v=""
  if [ -n "$prefix" ]; then _n="${prefix}_POST_CLEAN_POLL"; v="${!_n:-}"; fi
  [ -n "$v" ] || v="${POST_CLEAN_POLL:-}"
  case "$v" in ''|*[!0-9]*) ;; *) poll="$v" ;; esac

  # A quiet period longer than the window can never be satisfied, which would
  # burn the whole window and then report settled without ever having been.
  [ "$quiet" -gt "$window" ] && quiet="$window"
  [ "$poll" -lt 1 ] && poll=1
  [ "$poll" -gt "$quiet" ] && [ "$quiet" -gt 0 ] && poll="$quiet"

  v=""
  if [ -n "$prefix" ]; then _n="${prefix}_POST_CLEAN_REQUIRE_REVIEW"; v="${!_n:-}"; fi
  [ -n "$v" ] || v="${POST_CLEAN_REQUIRE_REVIEW:-}"
  case "$v" in 0|1) require_review="$v" ;; esac

  printf '%s %s %s %s' "$window" "$quiet" "$poll" "$require_review"
}

# _review_body_is_substantive <body>
#
# The GitHub reviews endpoint includes zero-body "review" containers when a bot
# replies inside existing review threads. Those containers are not a review of
# the current code and must not satisfy POST_CLEAN_REQUIRE_REVIEW.
_review_body_is_substantive() {
  local body="${1:-}"
  local normalized normalized_key
  normalized="$(printf '%s' "$body" | tr '\r\n\t' '   ' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$normalized" ] || return 1
  normalized_key="$(printf '%s' "$normalized" | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:][:punct:]]*$//')"

  case "$normalized_key" in
    "thanks"|"thank you"|"acknowledged"|"got it"|"the change is correct")
      return 1
      ;;
  esac

  return 0
}

# _bot_review_submitted_since <repo> <pr> <since-iso> [head-sha] <bot-login>...
#
# Echoes 1 when any listed bot has SUBMITTED a formal review at or after
# <since-iso>, 0 when none has, and -1 when the query failed. This is the
# positive completion signal: CodeRabbit's walkthrough issue comment appears
# within a minute of the push and means only that it has noticed the PR, while
# the submitted review is what carries the findings.
_bot_review_submitted_since() {
  local repo="$1" pr="$2" since="$3"
  shift 3
  local head_sha=""
  if [ "$#" -gt 0 ]; then
    case "$1" in
      [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]*)
        head_sha="$1"
        shift
        ;;
    esac
  fi
  local logins_json reviews matched=0 reviews_status=0
  logins_json="$(printf '%s\n' "$@" | jq -R . | jq -sc .)"
  reviews="$(gh api "repos/$repo/pulls/$pr/reviews" --paginate 2>/dev/null \
    | jq -sr --argjson bots "$logins_json" --arg since "$since" --arg head "$head_sha" '
        .[][]? | select(
            ((.user.login // "")) as $raw
            | ($raw | rtrimstr("[bot]")) as $l
            | ((($bots | index($l)) != null) or (($bots | index($raw)) != null))
          )
        | select((.submitted_at // "") > $since)
        | select(($head == "") or ((.commit_id // $head) == $head))
        | (.body // "")
      ' 2>/dev/null)" || reviews_status=$?
  if [ "$reviews_status" -ne 0 ]; then
    printf '%s' "-1"
    return 0
  fi
  if [ -z "$reviews" ]; then
    printf '0'
    return 0
  fi

  while IFS= read -r body; do
    if _review_body_is_substantive "$body"; then
      matched=1
      break
    fi
  done <<< "$reviews"

  [ "$matched" -eq 1 ] && printf '1' || printf '0'
}

# _bot_activity_since <repo> <pr> <since-iso> <bot-login>...
#
# Counts bot activity at or after <since-iso> across issue comments, review
# comments, and submitted reviews. Accepts updated_at as well as created_at,
# so an in-place edit counts — the same blind spot fixed in the CodeRabbit
# activity probe. Echoes an integer, or "-1" if the query failed (which the
# caller must not read as "quiet").
_bot_activity_since() {
  local repo="$1" pr="$2" since="$3"
  shift 3
  local logins_json
  logins_json="$(printf '%s\n' "$@" | jq -R . | jq -sc .)"

  local issue_n review_n comment_n
  issue_n="$(gh api "repos/$repo/issues/$pr/comments" --paginate 2>/dev/null \
    | jq -s --argjson bots "$logins_json" --arg since "$since" '
        [ .[][]? | select(
            ((.user.login // "")) as $raw
            | ($raw | rtrimstr("[bot]")) as $l
            | ((($bots | index($l)) != null) or (($bots | index($raw)) != null)) 
          ) | select((.created_at > $since) or ((.updated_at // .created_at) > $since))
        ] | length' 2>/dev/null)" || issue_n=""
  comment_n="$(gh api "repos/$repo/pulls/$pr/comments" --paginate 2>/dev/null \
    | jq -s --argjson bots "$logins_json" --arg since "$since" '
        [ .[][]? | select(
            ((.user.login // "")) as $raw
            | ($raw | rtrimstr("[bot]")) as $l
            | ((($bots | index($l)) != null) or (($bots | index($raw)) != null))
          ) | select((.created_at > $since) or ((.updated_at // .created_at) > $since))
        ] | length' 2>/dev/null)" || comment_n=""
  review_n="$(gh api "repos/$repo/pulls/$pr/reviews" --paginate 2>/dev/null \
    | jq -s --argjson bots "$logins_json" --arg since "$since" '
        [ .[][]? | select(
            ((.user.login // "")) as $raw
            | ($raw | rtrimstr("[bot]")) as $l
            | ((($bots | index($l)) != null) or (($bots | index($raw)) != null))
          ) | select((.submitted_at // "") > $since)
        ] | length' 2>/dev/null)" || review_n=""

  case "${issue_n}${comment_n}${review_n}" in
    ''|*[!0-9]*) printf '%s' "-1"; return 0 ;;
  esac
  printf '%s' "$(( issue_n + comment_n + review_n ))"
}

[ "$_HARNESS_MODE_EFFECTIVE" -eq 1 ] && return 0 2>/dev/null || true

if [ "$#" -lt 1 ]; then
  usage >&2
  exit 64
fi

pr_number=""
branch_name=""
repo_selector=""
repo_root="$(workflow_repo_root)"
local_review_override_root=""
review_policy_source="shared"
poll_interval=120
poll_interval_explicit=0
max_wait=1200
max_wait_explicit=0
codex_github_pre_trigger_wait=""
post_final_summary=0
compare_mode=0
pre_after_clean_only=0
review_lifecycle_duplicate_warnings_emitted=0
declare -a platforms=()
declare -a repo_review_platforms=()
declare -a phase_after_clean_platforms=()
phase_after_clean_filtered_out=""

require_option_value() {
  local option="$1"
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
    echo "$option requires a value." >&2
    usage >&2
    exit 64
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --branch)
      require_option_value "$@"
      branch_name="$2"
      shift 2
      ;;
    --repo)
      require_option_value "$@"
      repo_selector="$2"
      shift 2
      ;;
    --product-repo)
      require_option_value "$@"
      repo_selector="$2"
      shift 2
      ;;
    --repo-root)
      require_option_value "$@"
      repo_root="$2"
      shift 2
      ;;
    --platform)
      require_option_value "$@"
      append_platforms "$2"
      shift 2
      ;;
    --phase-after-clean)
      require_option_value "$@"
      append_phase_after_clean_platforms "$2"
      shift 2
      ;;
    --ready-phase)
      require_option_value "$@"
      append_ready_phase_platforms "$2"
      shift 2
      ;;
    --draft-github-only)
      pre_after_clean_only=1
      shift
      ;;
    --pre-after-clean-only)
      pre_after_clean_only=1
      shift
      ;;
    --poll-interval)
      require_option_value "$@"
      poll_interval="$2"
      poll_interval_explicit=1
      shift 2
      ;;
    --max-wait)
      require_option_value "$@"
      max_wait="$2"
      max_wait_explicit=1
      shift 2
      ;;
    --pre-trigger-wait)
      require_option_value "$@"
      codex_github_pre_trigger_wait="$2"
      shift 2
      ;;
    --post-final-summary)
      post_final_summary=1
      shift
      ;;
    --compare)
      compare_mode=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Unknown option: $1" >&2
      exit 64
      ;;
    *)
      if [ -n "$pr_number" ]; then
        echo "Only one PR number may be provided." >&2
        exit 64
      fi
      pr_number="$1"
      shift
      ;;
  esac
done

if ! local_review_override_root="$(resolve_local_review_override_root "$repo_root")"; then
  echo "ERROR: could not resolve the initiating checkout's local reviewer policy." >&2
  exit 2
fi
if [ -n "$local_review_override_root" ]; then
  export WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT="$local_review_override_root"
  review_policy_source="local_override"
else
  unset WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT
fi

if [ -z "$pr_number" ]; then
  usage >&2
  exit 64
fi

if [ -n "$repo_selector" ]; then
  if workflow_is_valid_github_repo_slug "$repo_selector"; then
    target_github_repo="$repo_selector"
  else
    repo_context="$(workflow_repository_context "$repo_selector" "$repo_root")"
    target_github_repo="$(workflow_github_repo_from_context "$repo_context")"
  fi
  if [ -z "$target_github_repo" ]; then
    echo "ERROR: could not resolve GitHub repository for PR review loop; pass --repo owner/repo or --product-repo <name>." >&2
    exit 64
  fi
  export WORKFLOW_TARGET_GITHUB_REPO="$target_github_repo"
  export GH_REPO="$target_github_repo"
  print_kv REPO "$target_github_repo"
fi

# --- Reviewer-loop run identifier (#1502 follow-up: dual cap) ---
# Resolved as early as possible (pr_number is now stable) so every code path
# that can append a reviewer_loop_history.v1 ledger entry for this PR --
# including the release-guard and not-configured skip paths below -- writes
# a consistent run_id. See reviewer_loop_resolve_run_id for the resolution
# rule (explicit PR_REVIEW_LOOP_RUN_ID env var, else a freshly generated
# per-invocation id).
current_run_id="$(reviewer_loop_resolve_run_id)"
print_kv RUN_ID "$current_run_id"

# Reconcile the rate-limit ceiling against the declared execution budget before
# any waiting starts (issue #1562). Failing here costs a second; discovering the
# same misconfiguration by being killed mid-wait costs an hour and reports
# nothing.
if ! _check_execution_budget; then
  exit 2
fi

# --- Release PR early-exit guard ---
# Release PRs (release/* -> main) and hotfix PRs (hotfix/* -> main) carry
# large diffs that were already reviewed when each feature/fix PR merged into
# develop. Running external reviewer tools (Haystack, CodeRabbit, PR-Agent,
# etc.) on these PRs produces no review value and wastes the poll timeout
# (historically ~40 min for large-diff Haystack waits). Skip the reviewer
# loop entirely for these PR types and return RESULT=skipped so callers treat
# the result as a clean non-blocking outcome.
#
# Detection: head branch matches release/* or hotfix/*
_release_guard_output=""
set +e
_release_guard_output="$(_check_release_pr_guard "$pr_number" "${branch_name:-}")"
_release_guard_fired=$?
set -e

_release_guard_head="$(printf '%s\n' "$_release_guard_output" | awk -F= '/^RELEASE_GUARD_HEAD=/{sub(/^[^=]*=/,""); print; exit}')"

# Propagate the fetched head branch to branch_name so later blocks do not
# need to re-fetch it (mirrors the existing pattern in the platforms block).
if [ -z "$branch_name" ] && [ -n "$_release_guard_head" ]; then
  branch_name="$_release_guard_head"
fi

post_release_guard_summary() {
  local _pr_number="$1"
  local _branch_name="$2"
  local _repo _existing_comment_id _patch_payload _comment_posted _body_tmpfile
  local _comment_body
  local _existing_comment_body=""
  local _existing_comment_record=""

  if [ -z "$_pr_number" ]; then
    return 0
  fi

  _comment_body="$(cat <<EOF
### Automated Reviewer Loop Summary

**Result:** skipped — release/hotfix PR reviewer loop intentionally skipped
**Platforms:** none
**Findings:** 0 blocking, 0 suggestions
**Release readiness:** Review happens on develop-targeting feature/fix PRs. For \`${_branch_name:-release/hotfix}\` PRs targeting \`main\`, validate release artifacts, run \`pr-ci-loop.sh\`, then apply \`ready-for-human-review\` when CI is green.

*Posted automatically by \`pr-review-loop.sh\`.*
EOF
)"

  set +e

  _existing_comment_id=""
  _repo="$(repo_slug 2>/dev/null)"
  if [ -n "$_repo" ]; then
    if ! _existing_comment_record="$(
        set -o pipefail
        gh api "repos/$_repo/issues/$_pr_number/comments" --paginate 2>/dev/null \
          | reviewer_loop_history_select_summary_record
      )"; then
      echo "WARN: failed to fetch existing summary comments for PR ${_pr_number}; will create a new comment with unavailable history" >&2
      _existing_comment_record=""
      _existing_comment_body="$(reviewer_loop_history_unavailable_stub_body comment_read_failed)"
    fi
    if [ -n "$_existing_comment_record" ]; then
      _existing_comment_id="$(printf '%s\n' "$_existing_comment_record" | jq -r '.id // empty' 2>/dev/null)" || _existing_comment_id=""
      _existing_comment_body="$(printf '%s\n' "$_existing_comment_record" | jq -r '.body // ""' 2>/dev/null)" || _existing_comment_body=""
    fi
  fi

  _comment_body="$(reviewer_loop_history_append_to_summary "$_comment_body" "$_existing_comment_body" \
    "skipped" "release_pr" "none" "0" "0" "0" "" "0" "0" "")"

  _patch_payload="$(jq -n --arg body "$_comment_body" '{body: $body}')"
  _comment_posted=0
  if [ -n "$_repo" ] && [ -n "$_existing_comment_id" ]; then
    if gh api "repos/$_repo/issues/comments/$_existing_comment_id" \
        --method PATCH \
        --input - <<< "$_patch_payload" >/dev/null 2>&1; then
      _comment_posted=1
    fi
  fi
  if [ "$_comment_posted" -eq 0 ]; then
    _body_tmpfile="$(mktemp)"
    printf '%s' "$_comment_body" > "$_body_tmpfile"
    if gh pr comment "$_pr_number" --body-file "$_body_tmpfile" >/dev/null 2>&1; then
      _comment_posted=1
    else
      echo "WARN: failed to post release guard summary comment for PR ${_pr_number}" >&2
    fi
    rm -f "$_body_tmpfile"
  fi

  set -e
  if [ "$_comment_posted" -eq 0 ]; then
    return 1
  fi
  return 0
}

if [ "$_release_guard_fired" -eq 0 ]; then
  echo "Release PR detected — reviewer loop skipped." >&2
  echo "Review happens on develop-targeting feature/fix PRs, not on release/* or hotfix/* branches." >&2
  echo "Release readiness path: validate release artifacts → run pr-ci-loop.sh → apply ready-for-human-review when CI is green." >&2
  # Remove any stale reviewer-failed label left from a prior failed run so the
  # PR is not misleadingly labeled after a clean release-guard skip exit.
  sync_reviewer_failed_label "$pr_number" 0
  if ! post_release_guard_summary "$pr_number" "${branch_name:-}"; then
    print_kv RESULT escalate
    print_kv REASON release_guard_summary_failed
    print_kv PR_NUMBER "$pr_number"
    print_kv BRANCH "${branch_name:-}"
    exit 1
  fi
  print_kv RESULT skipped
  print_kv REASON release_pr
  print_kv PR_NUMBER "$pr_number"
  print_kv BRANCH "${branch_name:-}"
  exit 0
fi
# --- End release PR early-exit guard ---

# Resolve config from the PR's target branch so platform coverage is consistent
# regardless of the operator's local checkout state (#756). Always snapshot
# repo_review_platforms for missed-finding membership even when --platform
# filters the invocation list.
set +e
_pr_base_raw="$(gh pr view "$pr_number" --json baseRefName --jq '.baseRefName' 2>&1)"
_pr_base_exit=$?
set -e
_pr_base=""
if [ "$_pr_base_exit" -eq 0 ]; then
  _pr_base="$_pr_base_raw"
elif ! printf '%s\n' "$_pr_base_raw" | grep -qi "Could not resolve\|not found"; then
  printf 'WARNING: failed to resolve PR base branch (exit %d): %s — falling back to working-tree config\n' \
    "$_pr_base_exit" "$_pr_base_raw" >&2
fi
if [ -n "$_pr_base" ]; then
  if _PR_CONFIG_TMPFILE="$(mktemp 2>/dev/null)"; then
    # Refresh the remote-tracking ref so git show reads the current target
    # branch config, not a potentially stale cached ref (#777).
    git fetch origin "$_pr_base" 2>/dev/null || true  # workflow-shell-guard: allow SH001 - best-effort refresh of remote base ref for config read
    if ! git show "origin/${_pr_base}:.ai-dev-workflow.yaml" > "$_PR_CONFIG_TMPFILE" 2>/dev/null; then
      rm -f "$_PR_CONFIG_TMPFILE"
      _PR_CONFIG_TMPFILE=""
    fi
  fi
fi
config_file="${_PR_CONFIG_TMPFILE:-$(workflow_config_file)}"
if [ -f "$config_file" ]; then
  if [ "$review_lifecycle_duplicate_warnings_emitted" -eq 0 ]; then
    WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 emit_review_lifecycle_duplicate_warnings "$config_file"
    review_lifecycle_duplicate_warnings_emitted=1
  fi
  while IFS= read -r line; do
    line="$(trim "$line")"
    [ -n "$line" ] && repo_review_platforms+=("$line")
  done < <(WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 workflow_config_review_platforms "$config_file")
fi

if [ "${#platforms[@]}" -eq 0 ] && [ "${#repo_review_platforms[@]}" -gt 0 ]; then
  platforms=("${repo_review_platforms[@]}")
fi

if [ "${#phase_after_clean_platforms[@]}" -eq 0 ]; then
  config_file="${config_file:-$(workflow_config_file)}"
  if [ -f "$config_file" ]; then
    if [ "$review_lifecycle_duplicate_warnings_emitted" -eq 0 ]; then
      WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 emit_review_lifecycle_duplicate_warnings "$config_file"
      review_lifecycle_duplicate_warnings_emitted=1
    fi
    while IFS= read -r line; do
      line="$(trim "$line")"
      [ -n "$line" ] && phase_after_clean_platforms+=("$line")
    done < <(WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 workflow_config_review_phase_after_clean_platforms "$config_file")
  fi
fi

print_kv REVIEW_POLICY_SOURCE "$review_policy_source"

if [ "$pre_after_clean_only" -eq 1 ]; then
  filter_pre_after_clean_platforms
  # Do NOT call filter_phase_after_clean_platforms here: filter_pre_after_clean_platforms
  # already removed phase platforms from `platforms`, so a subsequent
  # filter_phase_after_clean_platforms call would find no matching entries and empty
  # phase_after_clean_platforms — losing the configured phase list and causing
  # PHASE_AFTER_CLEAN_PLATFORM_LIST telemetry to be blank (issue #693).
else
  filter_phase_after_clean_platforms
fi

# Issue #1649: move expensive reviewers last within each phase bucket so the
# gate's peer precondition is reachable (never across the draft/ready boundary).
reorder_expensive_reviewers_last

if [ "${#platforms[@]}" -gt 0 ]; then
  require_gh
  cd "$repo_root" || exit 1

  if [ -z "$branch_name" ]; then
    if ! branch_name="$(gh pr view "$pr_number" --json headRefName --jq '.headRefName')"; then
      echo "ERROR: could not resolve PR #$pr_number head branch." >&2
      exit 1
    fi
  fi
fi

# Branch-type-aware timeout: spec/* and implementation-plan/* branches produce
# REASON=no_check_run immediately when Devin has no trigger condition (non-implementation
# branches). Waiting the full 1200-second default wastes orchestrator budget.
# Apply a bounded doc-branch max_wait / poll_interval=30 default when the caller
# did not pass --max-wait / --poll-interval explicitly. poll_interval must be
# less than max_wait so the per-loop timeout check can fire within the budget.
if [ "$max_wait_explicit" -eq 0 ]; then
  case "$branch_name" in
    spec/*|implementation-plan/*)
      max_wait="$(doc_branch_default_max_wait)"
      if [ "$poll_interval_explicit" -eq 0 ]; then
        poll_interval="$(doc_branch_default_poll_interval "$max_wait")"
      fi
      ;;
  esac
fi

if codex_github_defaults_should_apply; then
  if [ "$max_wait_explicit" -eq 0 ]; then
    max_wait="$(codex_github_default_max_wait)"
  fi
  if [ "$poll_interval_explicit" -eq 0 ]; then
    poll_interval="$(codex_github_default_poll_interval "$max_wait")"
  fi
fi

# Large-diff poll-window extension.
# CodeRabbit takes significantly longer to post its review on large-diff PRs
# (e.g. release PRs with hundreds of changed files). The default max_wait=1200 s
# was calibrated for typical feature PRs and is too short for large release diffs:
# during release v0.27.0 (PR #665, 185-file diff), the loop returned RESULT=clean
# before CodeRabbit finished posting 16 findings.
#
# When the caller did not pass --max-wait explicitly, fetch the PR's changed-files
# count and extend max_wait to LARGE_DIFF_MAX_WAIT (default 2400 s) when the count
# exceeds LARGE_DIFF_THRESHOLD (default 50 files). A case guard excludes spec/* and
# implementation-plan/* branches — those are already handled by the branch-type-aware
# timeout block above and must not have their bounded doc-branch budget overridden.
large_diff_threshold="${LARGE_DIFF_THRESHOLD:-50}"
large_diff_max_wait="${LARGE_DIFF_MAX_WAIT:-2400}"
if ! [[ "$large_diff_threshold" =~ ^[1-9][0-9]*$ ]]; then
  echo "WARN: LARGE_DIFF_THRESHOLD must be a positive integer; defaulting to 50" >&2
  large_diff_threshold=50
fi
if ! [[ "$large_diff_max_wait" =~ ^[1-9][0-9]*$ ]]; then
  echo "WARN: LARGE_DIFF_MAX_WAIT must be a positive integer; defaulting to 2400" >&2
  large_diff_max_wait=2400
fi
changed_files_count=-1
large_diff_extended=0
if [ "$max_wait_explicit" -eq 0 ]; then
  case "$branch_name" in
    spec/*|implementation-plan/*)
      # Already handled by the branch-type rule above — do not extend.
      ;;
    *)
      if [ -n "$pr_number" ] && [ "${#platforms[@]}" -gt 0 ]; then
        set +e
        changed_files_count="$(gh api "repos/$(repo_slug)/pulls/$pr_number" \
          --jq '.changed_files // -1' 2>/dev/null)"
        set -e
        if ! [[ "${changed_files_count:-}" =~ ^-?[0-9]+$ ]]; then
          echo "WARN: failed to fetch changed_files count for PR #$pr_number — skipping large-diff extension" >&2
          changed_files_count=-1
        fi
        if [ "$changed_files_count" -ge 0 ] && [ "$changed_files_count" -gt "$large_diff_threshold" ]; then
          if [ "$large_diff_max_wait" -gt "$max_wait" ]; then
            echo "INFO: PR #$pr_number has ${changed_files_count} changed files (threshold: ${large_diff_threshold}) — extending max_wait from ${max_wait}s to ${large_diff_max_wait}s for large-diff poll window" >&2
            max_wait="$large_diff_max_wait"
            large_diff_extended=1
          fi
        fi
      fi
      ;;
  esac
fi

# Step 7b regression-label auto-restore (implementation PRs only).
# Delegates to restore_regression_label_if_missing() (defined in the function
# section above) so the logic can be unit-tested in harness mode.
if [ -n "$pr_number" ] && [ "${#platforms[@]}" -gt 0 ]; then
  restore_regression_label_if_missing "$pr_number" "${branch_name:-}"
fi

# --- Reviewer cycle cap (max_cycles / max_total_cycles) resolution (#1502) ---
# Read the persisted reviewer_loop_history.v1 ledger (the same one written by
# _post_review_summary/reviewer_loop_history_append_to_summary below) to
# determine, for THIS invocation's run_id (current_run_id, resolved above),
# how many fixer dispatches have already occurred this run (Protocol 91's
# `cycle` counter) AND across the PR's whole lifetime, then resolve both
# configured caps. See the "reviewer-loop max_cycles enforcement" comment
# block above reviewer_loop_history_entries_count for what is counted (only
# needs_fixes/needs_rerun entries, deduped by distinct HEAD SHA) and the
# dual-cap rationale (per-run resets at the orchestration-run boundary;
# lifetime never resets).
#
# Both counts are -1 together when the prior ledger could not be read
# reliably; the cap checks fail open in that case (see
# reviewer_loop_cap_exceeded) — reviewer_loop_cycle_count_unavailable_
# should_escalate below handles failing CLOSED instead when the loop would
# otherwise keep going.
max_cycles="$(reviewer_loop_resolve_max_cycles "$(workflow_config_review_max_cycles "${config_file:-$(workflow_config_file)}" 2>/dev/null || true)")"
max_total_cycles="$(reviewer_loop_resolve_max_total_cycles "$(workflow_config_review_max_total_cycles "${config_file:-$(workflow_config_file)}" 2>/dev/null || true)")"
expensive_gate_max_deferrals="$(expensive_gate_resolve_max_deferrals)"
lifetime_cycle_count=-1
cycle_count=-1
if [ -n "$pr_number" ] && [ "${#platforms[@]}" -gt 0 ]; then
  read -r lifetime_cycle_count cycle_count < <(reviewer_loop_resolve_cycle_counts "$pr_number" "$current_run_id")
fi

aggregate_result="skipped"
aggregate_reason=""
last_platform=""
aggregate_output=""
aggregate_status=0
total_comment_count=0
total_blocking_count=0
total_suggestion_count=0
aggregate_advisory_labels=""
reviewer_failed_required=0
small_findings_required_rounds="$(reviewer_loop_small_findings_required_rounds)"
small_findings_only=0
small_findings_stop=0
small_findings_rounds=0
small_findings_paths=""
small_findings_paths_inline=""
small_findings_blocked_by=""
small_findings_shipped_detail=""
small_findings_surfaces_detail=""
small_findings_currency_detail=""
declare -a compare_verdicts=()
declare -a aggregate_blocking_paths=()
# Parallel to aggregate_blocking_paths: one JSON finding record per blocking
# finding, never deduplicated (#1652).
declare -a aggregate_blocking_findings=()
# The head this run reviews, captured BEFORE any reviewer is dispatched
# (issue #1574). Every verdict below describes this commit; the settle emits it
# as POST_CLEAN_HEAD_SHA, and the head-move guard after the settle turns a
# clean verdict into needs_fixes/head_moved_during_run if the PR moved away
# from it while the loop ran. Reading it later would bind the verdict to
# whatever was pushed in the meantime.
loop_head_sha=""
if [ -n "$pr_number" ]; then
  if ! loop_head_sha="$(gh pr view "$pr_number" --json headRefOid --jq '.headRefOid' 2>/dev/null)"; then
    loop_head_sha=""
    echo "WARN: could not read the PR head before dispatching reviewers; POST_CLEAN_HEAD_SHA will be empty and Protocol 91 Check 0.6 will refuse this verdict" >&2
  fi
fi
# Per-platform result tokens for the PR summary comment.
# Each entry is "platform_name:display_token" (e.g. "haystack:unavailable").
declare -a platform_result_tokens=()
# Per-platform reviewed heads for head-evidence surfaces (issue #1648).
declare -a platform_reviewed_heads=()
# Per-platform raw outcomes for missed-finding telemetry (issue #1651).
declare -a platform_result_records=()
# Parallel platform outputs for path extraction when building missed_findings.
declare -a platform_blocking_outputs=()
missed_findings_json='[]'
platform_results_json='[]'
missed_finding_attribution_reports=""
# Peer evidence for the expensive-reviewer gate (issue #1649): "platform|result|reason".
platform_peer_evidence=()
expensive_gate_last_platform=""
expensive_gate_last_result=""
expensive_gate_last_reason=""
expensive_gate_last_head=""
# Per-platform review-policy status notes for the PR summary comment. Haystack
# emits these from `pr-status`; other platforms normally leave this empty.
declare -a platform_policy_status_notes=()
# Compare-mode: track the first blocking platform seen so later clean platforms
# do not overwrite the aggregate. These variables are set once and never reset.
compare_first_blocking_result=""
compare_first_blocking_reason=""
compare_first_blocking_output=""
compare_first_blocking_status=0
phase_after_clean_enabled=0
phase_after_clean_started=0
phase_after_clean_net_new_blocker=0
phase_after_clean_blocking_platform=""
phase_after_clean_gate_result="not_started"
phase_after_clean_skip_reason=""
local_second_pass=0
local_second_pass_reason="not_required"
local_second_pass_result=""
local_second_pass_failed_head_record=""
reviewer_loop_platform_loop_should_break=0
reviewer_loop_last_platform_result=""
reviewer_loop_last_platform_reason=""
reviewer_loop_last_platform_output=""
reviewer_loop_last_platform_status=0
if [ "${#phase_after_clean_platforms[@]}" -gt 0 ]; then
  phase_after_clean_enabled=1
fi

print_kv PR_NUMBER "$pr_number"
print_kv BRANCH "$branch_name"
print_kv FIX_AGENT "$(reviewer_for_branch "$branch_name")"
print_kv PLATFORM_COUNT "${#platforms[@]}"
# So callers can verify config was respected (e.g. no greptile when only devin is in .ai-dev-workflow.yaml)
print_kv PLATFORM_LIST "$(IFS=,; printf '%s' "${platforms[*]}")"
[ "${expensive_reviewers_reordered:-0}" -eq 1 ] && print_kv EXPENSIVE_REVIEWERS_REORDERED 1
print_kv DRAFT_GITHUB_ONLY "$pre_after_clean_only"
print_kv PRE_AFTER_CLEAN_ONLY "$pre_after_clean_only"
print_kv READY_PHASE_ENABLED "$phase_after_clean_enabled"
print_kv PHASE_AFTER_CLEAN_ENABLED "$phase_after_clean_enabled"
[ -n "$phase_after_clean_filtered_out" ] && \
  print_kv READY_PHASE_FILTERED_OUT "$phase_after_clean_filtered_out"
[ -n "$phase_after_clean_filtered_out" ] && \
  print_kv PHASE_AFTER_CLEAN_FILTERED_OUT "$phase_after_clean_filtered_out"
[ "$phase_after_clean_enabled" -eq 1 ] && \
  print_kv READY_PHASE_PLATFORM_LIST "$(IFS=,; printf '%s' "${phase_after_clean_platforms[*]}")"
[ "$phase_after_clean_enabled" -eq 1 ] && \
  print_kv PHASE_AFTER_CLEAN_PLATFORM_LIST "$(IFS=,; printf '%s' "${phase_after_clean_platforms[*]}")"
print_kv CHANGED_FILES_COUNT "${changed_files_count:--1}"
[ "$large_diff_extended" -eq 1 ] && print_kv LARGE_DIFF_EXTENDED 1
# Reviewer cycle cap telemetry (#1502, dual-cap): CYCLE_COUNT is the number
# of fixer dispatches already issued THIS ORCHESTRATION RUN (resets to 0 at
# each run boundary — see RUN_ID above); TOTAL_CYCLE_COUNT is the same
# distinct-HEAD-SHA count across the PR's ENTIRE lifetime and never resets.
# Both are -1 when the prior ledger could not be read. Emitted so a
# supervising runner can see how close the loop is to either cap before it
# trips, independent of whether this cycle ends up escalating.
print_kv CYCLE_COUNT "$cycle_count"
print_kv MAX_CYCLES "$max_cycles"
print_kv TOTAL_CYCLE_COUNT "$lifetime_cycle_count"
print_kv MAX_TOTAL_CYCLES "$max_total_cycles"

for index in "${!platforms[@]}"; do
  platform_index=$((index + 1))
  platform_name="${platforms[$index]}"

  if [ "$phase_after_clean_enabled" -eq 1 ] \
      && [ "$phase_after_clean_started" -eq 0 ] \
      && is_phase_after_clean_platform "$platform_name"; then
    if [ "$compare_mode" -eq 0 ] || [ -z "$compare_first_blocking_result" ]; then
      # Issue #1656: second local pass before expensive preflight and gh pr ready.
      if reviewer_loop_second_local_pass_before_ready_gate "$pr_number"; then
        :
      else
        break
      fi
      # Issue #1649: preflight expensive ready-phase gates BEFORE gh pr ready.
      # Codex (and similar) may auto-start when a draft is marked ready; running
      # ensure_pr_ready first would spend that reviewer before local/thread/
      # baseline evidence (and earlier-bucket peers) is confirmed. Peer scope is
      # earlier_buckets only — same-bucket peers like bugbot require ready state
      # themselves, so requiring them here would deadlock the ready transition.
      # The full per-platform gate (including same-bucket peers) still runs
      # immediately before run_platform_review after ready-phase peers complete.
      _eg_ready_preflight_failed=0
      for ((_eg_i = index; _eg_i < ${#platforms[@]}; _eg_i++)); do
        _eg_plat="${platforms[$_eg_i]}"
        if ! is_phase_after_clean_platform "$_eg_plat"; then
          continue
        fi
        if ! is_expensive_reviewer_platform "$_eg_plat"; then
          continue
        fi
        set +e
        expensive_gate_output="$(expensive_reviewer_gate "$pr_number" "$_eg_plat" "$loop_head_sha" "earlier_buckets")"
        expensive_gate_status=$?
        set -e
        expensive_gate_sync_last_from_output "$expensive_gate_output"
        if [ "$expensive_gate_status" -eq 0 ]; then
          # Successful preflight is not a dispatch and must not emit
          # EXPENSIVE_GATE_RESULT=dispatched/forced (or any new enum value) into
          # the machine-consumed stdout contract / summary / history. Deferrals
          # still emit the full EXPENSIVE_GATE_* block below.
          echo "INFO: expensive-gate ready preflight passed for ${_eg_plat} (earlier_buckets); full gate still runs before dispatch" >&2
          expensive_gate_last_platform=""
          expensive_gate_last_result=""
          expensive_gate_last_reason=""
          expensive_gate_last_head=""
          unset expensive_gate_output expensive_gate_status
          continue
        fi
        printf '%s\n' "$expensive_gate_output"
        if [ "$expensive_gate_status" -ne 0 ]; then
          last_platform="$_eg_plat"
          if [ "${expensive_gate_last_result:-}" = "deferral_cap" ]; then
            aggregate_result="escalate"
            _eg_escalation="$(kv_value_default EXPENSIVE_GATE_ESCALATION "$expensive_gate_output" "")"
            if [ "$_eg_escalation" = "expensive_gate_deferral_budget_unreadable" ]; then
              aggregate_reason="expensive_gate_deferral_budget_unreadable"
            else
              aggregate_reason="expensive_gate_deferral_cap"
            fi
            unset _eg_escalation
            aggregate_output="$(printf 'RESULT=escalate\nREASON=%s\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n' "$aggregate_reason")"
            aggregate_status=2
            platform_result_tokens+=("${_eg_plat}:deferred (${expensive_gate_last_reason:-cap})")
          else
            aggregate_result="needs_fixes"
            aggregate_reason="expensive_gate_deferred"
            aggregate_output="$(printf 'RESULT=needs_fixes\nREASON=expensive_gate_deferred\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n')"
            aggregate_status=1
            platform_result_tokens+=("${_eg_plat}:deferred (${expensive_gate_last_reason:-unknown})")
          fi
          _eg_ready_preflight_failed=1
          unset expensive_gate_output expensive_gate_status
          break
        fi
        unset expensive_gate_output expensive_gate_status
      done
      unset _eg_i _eg_plat
      if [ "$_eg_ready_preflight_failed" -eq 1 ]; then
        unset _eg_ready_preflight_failed
        break
      fi
      unset _eg_ready_preflight_failed
      set +e
      ensure_pr_ready_for_ready_phase "$pr_number"
      ready_status=$?
      set -e
      if [ "$ready_status" -ne 0 ]; then
        phase_after_clean_started=1
        phase_after_clean_gate_result="ready_failed"
        phase_after_clean_net_new_blocker=1
        phase_after_clean_blocking_platform="ready_for_review"
        aggregate_result="escalate"
        # Exit 3 means ensure_pr_ready_for_ready_phase confirmed (via
        # gh_rate_limit_exhausted_reset) that the underlying `gh` failure was a
        # GitHub API rate-limit exhaustion rather than a genuine review-gate
        # failure (issue #1509). Give it a distinct, actionable REASON instead
        # of the generic ready_for_review_failed, and carry the reset
        # timestamp so a human/supervisor knows when it is safe to retry.
        # reviewer_failed_label_required_for_result() excludes this REASON
        # from the reviewer-failed label — vendor/infrastructure unavailability
        # is not a review verdict on the PR.
        if [ "$ready_status" -eq 3 ]; then
          aggregate_reason="rate_limited"
          aggregate_output="$(printf 'RESULT=escalate\nREASON=rate_limited\nRATE_LIMIT_RESET=%s\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n' "$READY_PHASE_GATE_RATE_LIMIT_RESET")"
        else
          aggregate_reason="ready_for_review_failed"
          aggregate_output="$(printf 'RESULT=escalate\nREASON=ready_for_review_failed\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n')"
        fi
        aggregate_status=2
        break
      fi
      unset ready_status
      phase_after_clean_started=1
      phase_after_clean_gate_result="clean"
    fi
  fi

  # Issue #1649: expensive-reviewer gate — require current-head local clean,
  # preceding peer evidence, resolved threads, and green baseline checks
  # before dispatching. A defer sets needs_fixes and breaks so later platforms
  # (including ready-phase) do not run.
  if is_expensive_reviewer_platform "$platform_name"; then
    set +e
    expensive_gate_output="$(expensive_reviewer_gate "$pr_number" "$platform_name" "$loop_head_sha")"
    expensive_gate_status=$?
    set -e
    expensive_gate_sync_last_from_output "$expensive_gate_output"
    # Re-emit gate telemetry on the loop's stdout contract.
    printf '%s\n' "$expensive_gate_output"
    if [ "$expensive_gate_status" -ne 0 ]; then
      last_platform="$platform_name"
      if [ "${expensive_gate_last_result:-}" = "deferral_cap" ]; then
        aggregate_result="escalate"
        _eg_escalation="$(kv_value_default EXPENSIVE_GATE_ESCALATION "$expensive_gate_output" "")"
        if [ "$_eg_escalation" = "expensive_gate_deferral_budget_unreadable" ]; then
          aggregate_reason="expensive_gate_deferral_budget_unreadable"
        else
          aggregate_reason="expensive_gate_deferral_cap"
        fi
        unset _eg_escalation
        aggregate_output="$(printf 'RESULT=escalate\nREASON=%s\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n' "$aggregate_reason")"
        aggregate_status=2
        platform_result_tokens+=("${platform_name}:deferred (${expensive_gate_last_reason:-cap})")
      else
        aggregate_result="needs_fixes"
        aggregate_reason="expensive_gate_deferred"
        aggregate_output="$(printf 'RESULT=needs_fixes\nREASON=expensive_gate_deferred\nCOMMENT_COUNT=0\nBLOCKING_COUNT=0\nSUGGESTION_COUNT=0\n')"
        aggregate_status=1
        platform_result_tokens+=("${platform_name}:deferred (${expensive_gate_last_reason:-unknown})")
      fi
      break
    fi
    # forced / dispatched continue to run_platform_review
    unset expensive_gate_output expensive_gate_status
  fi

  set +e
  platform_output="$(run_platform_review "$platform_name" "$pr_number" "$branch_name" "$poll_interval" "$max_wait")"
  platform_status=$?
  set -e

  reviewer_loop_platform_loop_should_break=0
  reviewer_loop_process_platform_output "$platform_name" "$platform_index" "$platform_output" "$platform_status" 1
  if [ "$reviewer_loop_platform_loop_should_break" -eq 1 ]; then
    break
  fi
done

# --- Automated Reviewer Loop Summary comment ---
# Post a summary comment to the PR on terminal exit paths so the Step 8c
# hasReviewSummary check is satisfied automatically. The comment body matches
# the regex used by workflow-next-action.sh and Protocol 90 Step 5.1:
#   "Automated Reviewer Loop Summary|Reviewer Loop Summary|No blocking PR feedback"
# Post on `clean`, `escalate`, and `needs_fixes` exits. The summary comment is
# updated in place, so posting on fixable `needs_fixes` cycles does not create
# duplicates and prevents stale clean summaries from masking active findings.
# `skipped` exits (no platforms configured) also do not post per protocol spec.
_post_review_summary() {
  local result="$1"
  local reason="$2"
  local platform_list="$3"
  local blocking="$4"
  local suggestions="$5"
  local advisory_labels="${6:-}"
  local possible_issue_eval_outcome="${7:-}"
  local phase_enabled="${8:-0}"
  local phase_platform_list="${9:-}"
  local phase_started="${10:-0}"
  local phase_net_new_blocker="${11:-0}"
  local phase_blocking_platform="${12:-}"
  local pre_after_clean_only_mode="${13:-0}"
  local advisory_checks_section="${14:-}"

  if [ -z "$pr_number" ]; then
    return 0
  fi

  local result_line
  case "$result" in
    clean)
      if [ "${small_findings_stop:-0}" -eq 1 ]; then
        result_line="clean (small-findings stop) — small non-shipped tail on current head recorded for human merge audit"
      elif [ "$blocking" -eq 0 ] && [ "$suggestions" -eq 0 ]; then
        result_line="clean — no blocking findings"
      else
        result_line="clean"
      fi
      ;;
    needs_fixes)
      case "$reason" in
        head_moved_during_run)
          # This is the only needs_fixes reason with a zero blocking count
          # (issue #1574): every reviewer was clean, but the PR head moved
          # while they ran, so "N blocking finding(s)" would misreport why
          # this cycle is not clean. Name the reason explicitly instead.
          result_line="needs_fixes (head_moved_during_run) — the clean verdict was for a HEAD the PR has since moved past; nothing to fix, re-run Step 7 for the current HEAD"
          ;;
        expensive_gate_deferred)
          result_line="needs_fixes (expensive_gate_deferred) — expensive reviewer held back until current-head evidence is complete; readiness withheld so Step 7 re-runs"
          ;;
        *)
          result_line="${blocking} blocking finding(s) require fixes"
          ;;
      esac
      ;;
    escalate)
      result_line="escalated (${reason:-unknown})"
      ;;
    waiting_on_reviewer)
      result_line="waiting_on_reviewer (${reason:-codex-github-review-pending}) — current-head review trigger posted; reviewer has not returned terminal evidence yet"
      ;;
    skipped)
      result_line="skipped — no GitHub reviewers configured in review.on_draft.github or review.on_ready.github"
      ;;
    *)
      result_line="$result"
      ;;
  esac

  # Build the optional advisory findings section.
  # advisory_labels format: "<labels>@@@<url>" entries separated by "|||"
  # Each entry's labels are pipe-separated. Render each label as a list item,
  # linking to the PR-Agent comment URL when available.
  local advisory_section=""
  if [ -n "$advisory_labels" ]; then
    local _entry _labels _url _label
    advisory_section="

**Advisory findings (non-blocking):**"
    # Split entries by ||| separator using sed (IFS does not support multi-char
    # separators). Each entry has the form "<pipe-delimited labels>@@@<url>".
    local _entries_normalized
    _entries_normalized="$(printf '%s' "$advisory_labels" | sed 's/|||/\n/g')"
    while IFS= read -r _entry; do
      [ -z "$_entry" ] && continue
      _labels="${_entry%@@@*}"
      _url="${_entry##*@@@}"
      # Split pipe-delimited labels within this entry
      local _labels_normalized
      _labels_normalized="$(printf '%s' "$_labels" | tr '|' '\n')"
      while IFS= read -r _label; do
        [ -z "$_label" ] && continue
        if [ -n "$_url" ] && [ "$_url" != "$_labels" ]; then
          advisory_section="${advisory_section}
- ${_label} ([view comment](${_url}))"
        else
          advisory_section="${advisory_section}
- ${_label}"
        fi
      done <<_ADVISORY_LABEL_LINES_
$_labels_normalized
_ADVISORY_LABEL_LINES_
    done <<_ADVISORY_ENTRY_LINES_
$_entries_normalized
_ADVISORY_ENTRY_LINES_
    # Append "Possible Issue" evaluation outcome when available.
    if [ -n "$possible_issue_eval_outcome" ]; then
      local _eval_note
      case "$possible_issue_eval_outcome" in
        acknowledged)
          _eval_note="Auto-acknowledged: Possible Issue is advisory-only — loop proceeded clean"
          ;;
        fix_pushed)
          _eval_note="Evaluated by code-reviewer: fix pushed — loop re-ran on new HEAD"
          ;;
        unavailable)
          _eval_note="Evaluated by code-reviewer: unavailable — fell back to advisory-only (clean)"
          ;;
        *)
          _eval_note="Evaluated by code-reviewer: outcome=${possible_issue_eval_outcome}"
          ;;
      esac
      advisory_section="${advisory_section}
  _Possible Issue evaluation_: ${_eval_note}"
    fi
  fi

  # Step 7b regression-label assertion (clean path, implementation PRs only).
  # When the reviewer loop exits clean for a feature/fix/refactor/hotfix branch,
  # the next required step is Step 7b (apply ready-for-regression before Step 8).
  # Check whether the label is already present and append a warning to the summary
  # comment if it is missing. This makes the missing label visible to agents and
  # orchestrators that read the summary comment, without blocking the script's exit.
  # The check is best-effort: suppress all errors so a gh failure does not change
  # the script's exit code or prevent the summary comment from being posted.
  local regression_label_section=""
  if [ "$result" = "clean" ]; then
    case "${branch_name:-}" in
      feature/*|fix/*|refactor/*|hotfix/*)
        local _has_regression_label
        _has_regression_label="$(gh pr view "$pr_number" --json labels \
          --jq '[.labels[].name] | any(. == "ready-for-regression")' 2>/dev/null)" \
          || { echo "WARN: gh pr view failed for ready-for-regression check (PR ${pr_number}); label check skipped" >&2; _has_regression_label=""; }
        if [ "${_has_regression_label:-}" = "false" ]; then
          regression_label_section="

**Step 7b WARNING: \`ready-for-regression\` label is missing.** Apply it now before entering Step 8 (CI loop):
\`\`\`
gh pr edit ${pr_number} --add-label \"ready-for-regression\"
\`\`\`
Protocol 91 Step 7b requires this label on all \`${branch_name%%/*}/*\` PRs after Step 7 completes clean."
        fi
        ;;
    esac
  fi

  # Build optional compare-mode per-platform section.
  local compare_section=""
  if [ "$compare_mode" -eq 1 ] && [ "${#compare_verdicts[@]}" -gt 0 ]; then
    compare_section="

**Compare mode — per-platform verdicts:**"
    _idx=0
    while [ "$_idx" -lt "${#compare_verdicts[@]}" ]; do
      _cvname="${compare_verdicts[$_idx]}"
      _cvtoken="${compare_verdicts[$((_idx + 1))]}"
      compare_section="${compare_section}
- ${_cvname}: ${_cvtoken}"
      _idx=$((_idx + 2))
    done
    if [ "${_compare_metrics_appended:-0}" -eq 1 ]; then
      compare_section="${compare_section}

*Metrics row appended to \`docs/workflow/retro-metrics-platforms.md\`.*"
    fi
  fi

  local head_evidence_section=""
  if declare -p platform_reviewed_heads >/dev/null 2>&1 \
      && { [ "${#platform_reviewed_heads[@]}" -gt 0 ] || [ -n "${loop_head_sha:-}" ]; }; then
    head_evidence_section="

$(reviewer_loop_head_evidence_render "${loop_head_sha:-}" "${platform_reviewed_heads[@]}")"
  fi

  local expensive_gate_section=""
  if [ -n "${expensive_gate_last_result:-}" ]; then
    case "${expensive_gate_last_result}" in
      deferred)
        expensive_gate_section="

**Expensive reviewer gate:** ${expensive_gate_last_platform} — deferred (${expensive_gate_last_reason}) at head \`${expensive_gate_last_head}\`. The reviewer was not run; this loop result is \`needs_fixes\` so readiness is withheld and Step 7 will re-run."
        ;;
      deferral_cap)
        expensive_gate_section="

**Expensive reviewer gate:** ${expensive_gate_last_platform} — deferral cap reached (${expensive_gate_last_reason}) at head \`${expensive_gate_last_head}\`. Escalating so a human can unblock."
        ;;
      forced)
        expensive_gate_section="

**Expensive reviewer gate:** ${expensive_gate_last_platform} — forced (would have deferred: ${expensive_gate_last_reason}) at head \`${expensive_gate_last_head}\`."
        ;;
      dispatched)
        expensive_gate_section="

**Expensive reviewer gate:** ${expensive_gate_last_platform} — dispatched at head \`${expensive_gate_last_head}\`."
        ;;
      *)
        expensive_gate_section="

**Expensive reviewer gate:** ${expensive_gate_last_platform} — ${expensive_gate_last_result} (${expensive_gate_last_reason:-none}) at head \`${expensive_gate_last_head}\`."
        ;;
    esac
  fi

  local second_local_pass_section=""
  if [ "${local_second_pass:-0}" -eq 1 ] && [ -n "${local_second_pass_result:-}" ]; then
    second_local_pass_section="

**Second local pass:** second local pass: ${local_second_pass_reason:-unknown} → ${local_second_pass_result}"
  fi

  local phase_section=""
  if [ "$phase_enabled" -eq 1 ]; then
    local _phase_value_line
    local _phase_subject="${phase_platform_list:-ready-phase reviewer}"
    if [ "$phase_started" -eq 1 ]; then
      if [ "$phase_net_new_blocker" -eq 1 ]; then
        _phase_value_line="${_phase_subject} found a net-new blocker after the draft GitHub gate (${phase_blocking_platform:-unknown})."
      else
        _phase_value_line="No net-new blocker was found after the draft GitHub gate."
      fi
    elif [ "$pre_after_clean_only_mode" -eq 1 ]; then
      _phase_value_line="Ready phase was not run — invoked in draft-GitHub-only mode."
    else
      _phase_value_line="Ready phase was not reached because an earlier draft GitHub reviewer did not exit clean."
    fi
    phase_section="

**Ready reviewer phase:** ${_phase_value_line}
**Ready-phase platforms:** ${phase_platform_list:-none}"
  fi

  local policy_status_section=""
  if declare -p platform_policy_status_notes >/dev/null 2>&1 \
      && [ "${#platform_policy_status_notes[@]}" -gt 0 ]; then
    local _policy_status_note
    policy_status_section="
**Policy acknowledgements:**"
    for _policy_status_note in "${platform_policy_status_notes[@]}"; do
      policy_status_section="${policy_status_section}
- ${_policy_status_note}"
    done
  fi

  local small_findings_section=""
  if [ "${small_findings_stop:-0}" -eq 1 ]; then
    small_findings_section="
**Small-findings stop:** ${small_findings_rounds:-0}/${small_findings_required_rounds:-0} consecutive review rounds contained only small non-shipped-artifact findings on the current head, and the strict review-thread audit reported zero unresolved threads. Exact-head tests and CI still gate readiness after this review result.
**Unreviewed tail:** ${small_findings_paths_inline:-none}"
  elif [ -n "${small_findings_blocked_by:-}" ] || [ "${small_findings_only:-0}" -eq 1 ]; then
    # Name every collected cause so precedence on SMALL_FINDINGS_BLOCKED_BY
    # does not hide co-occurring causes within the reached group (#1652).
    local _sf_cause_bits=""
    [ -n "${small_findings_shipped_detail:-}" ] && _sf_cause_bits="${_sf_cause_bits} shipped_paths=${small_findings_shipped_detail};"
    [ -n "${small_findings_surfaces_detail:-}" ] && _sf_cause_bits="${_sf_cause_bits} contract_surfaces=${small_findings_surfaces_detail};"
    [ -n "${small_findings_currency_detail:-}" ] && _sf_cause_bits="${_sf_cause_bits} currency=${small_findings_currency_detail};"
    if [ -n "${small_findings_blocked_by:-}" ]; then
      small_findings_section="
**Small-findings:** terminal rule blocked by \`${small_findings_blocked_by}\`.${_sf_cause_bits:+ Causes:}${_sf_cause_bits}
**Candidate tail:** ${small_findings_paths_inline:-none}"
    elif [ "${small_findings_only:-0}" -eq 1 ]; then
      small_findings_section="
**Small-findings:** ${small_findings_rounds:-0}/${small_findings_required_rounds:-0} consecutive small rounds so far (threshold not reached; not a blocking cause).
**Candidate tail:** ${small_findings_paths_inline:-none}"
    fi
    unset _sf_cause_bits
  fi

  # Errors in the comment-posting block must not change the script's exit code or
  # prevent key=value output from reaching the caller. Log warnings to stderr so
  # failures are visible in CI logs without being fatal.
  set +e

  # Update-in-place: find an existing script-posted summary comment and edit it
  # rather than creating a new one. This prevents redundant intermediate summary
  # comments when the orchestrator invokes the script multiple times (e.g. once
  # per fix cycle). Only one "Automated Reviewer Loop Summary" comment should
  # ever exist on the PR timeline at a time.
  # The marker string "*Posted automatically by `pr-review-loop.sh`.*" is unique
  # to this script and is present in every comment it posts.
  local _existing_comment_id=""
  local _existing_comment_body=""
  local _repo
  local _existing_comment_record=""
  # Tracked separately from the write outcome below (#1502 dual-cap
  # follow-up): when this READ fails, the code falls back to an
  # "unavailable" stub as the existing body, which reviewer_loop_history_
  # payload_from_existing then refuses to append this cycle's entry onto
  # (append_safe=0 for a persisted "unavailable" history_status) — so the
  # WRITE below can succeed (posting the stub) while this cycle's entry is
  # still never actually recorded. A later "clean" cycle's OWN posting-time
  # history_select_summary_record's deliberate render-continuity fallback is used
  # ONLY for missed-finding derivation input (_mf_prior_payload), never for the
  # comment id/body chosen for update-in-place — mixing newest id with an older
  # substituted body would patch over unappendable latest history (AC-7a).
  local _existing_read_failed=0
  _repo="$(repo_slug 2>/dev/null)" \
    || { echo "WARN: repo_slug failed in _post_review_summary; will post new comment without update-in-place check" >&2; _repo=""; _existing_read_failed=1; }
  if [ -n "$_repo" ]; then
    _existing_comment_record="$(
      set -o pipefail
      gh api "repos/$_repo/issues/$pr_number/comments" --paginate 2>/dev/null \
        | reviewer_loop_history_select_latest_summary_record
    )" \
      || {
        echo "WARN: failed to fetch existing summary comments for PR ${pr_number}; will create a new comment with unavailable history" >&2
        _existing_comment_record=""
        _existing_comment_body="$(reviewer_loop_history_unavailable_stub_body comment_read_failed)"
        _existing_read_failed=1
      }
    if [ -n "$_existing_comment_record" ]; then
      _existing_comment_id="$(printf '%s\n' "$_existing_comment_record" | jq -r '.id // empty' 2>/dev/null)" || _existing_comment_id=""
      _existing_comment_body="$(printf '%s\n' "$_existing_comment_record" | jq -r '.body // ""' 2>/dev/null)" || _existing_comment_body=""
    fi
  fi

  # #1651: derive missed-finding records BEFORE history writability (eligibility
  # first). Compose the current round into the prior payload for AC-1.
  local _prior_history_json=""
  local _prior_payload='{"schema":"reviewer_loop_history.v1","entries":[]}'
  local _mf_prior_payload=""
  local _configured_platforms=""
  local _next_iteration=1
  local _mf_count=0
  local missed_findings_section=""
  local missed_finding_telemetry_section=""
  local _attr_line=""

  _prior_history_json="$(printf '%s\n' "$_existing_comment_body" | reviewer_loop_history_extract_latest_json)"
  if [ -n "$_prior_history_json" ]; then
    if _prior_payload="$(printf '%s\n' "$_prior_history_json" | jq -c '.' 2>/dev/null)"; then
      :
    else
      _prior_payload='{"schema":"reviewer_loop_history.v1","entries":[]}'
    fi
  fi
  _mf_prior_payload="$_prior_payload"
  if [ "$(printf '%s\n' "$_prior_payload" | jq -r '.history_status // "available"')" = "unavailable" ] \
      || { [ -z "$_prior_history_json" ] \
           && printf '%s\n' "$_existing_comment_body" | grep -Fq "$REVIEWER_LOOP_HISTORY_MARKER"; }; then
    local _mf_fallback_record="" _mf_fallback_body="" _mf_fallback_json=""
    if [ -n "$_repo" ]; then
      _mf_fallback_record="$(
        set -o pipefail
        gh api "repos/$_repo/issues/$pr_number/comments" --paginate 2>/dev/null \
          | reviewer_loop_history_select_summary_record
      )" || _mf_fallback_record=""
      if [ -n "$_mf_fallback_record" ]; then
        _mf_fallback_body="$(printf '%s\n' "$_mf_fallback_record" | jq -r '.body // ""' 2>/dev/null)" || _mf_fallback_body=""
        _mf_fallback_json="$(printf '%s\n' "$_mf_fallback_body" | reviewer_loop_history_extract_latest_json 2>/dev/null)" || _mf_fallback_json=""
        if [ -n "$_mf_fallback_json" ] \
            && printf '%s\n' "$_mf_fallback_json" | jq -e --arg schema "$REVIEWER_LOOP_HISTORY_SCHEMA" \
              '.schema == $schema and (.entries | type) == "array" and (.history_status // "available") == "available"' \
              >/dev/null 2>&1; then
          _mf_prior_payload="$(printf '%s\n' "$_mf_fallback_json" | jq -c '.' 2>/dev/null)" || _mf_prior_payload="$_prior_payload"
        fi
      fi
    fi
  fi
  if declare -p repo_review_platforms >/dev/null 2>&1 && [ "${#repo_review_platforms[@]}" -gt 0 ]; then
    _configured_platforms="$(printf '%s\n' "${repo_review_platforms[@]}")"
  elif declare -p platforms >/dev/null 2>&1 && [ "${#platforms[@]}" -gt 0 ]; then
    _configured_platforms="$(printf '%s\n' "${platforms[@]}")"
  fi
  _next_iteration="$(printf '%s\n' "$_prior_payload" | jq '(.entries // []) | length + 1' 2>/dev/null)" || _next_iteration=1
  [[ "$_next_iteration" =~ ^[0-9]+$ ]] || _next_iteration=1

  if declare -p platform_result_records >/dev/null 2>&1 && [ "${#platform_result_records[@]}" -gt 0 ]; then
    platform_results_json="$(printf '%s\n' "${platform_result_records[@]}" | jq -s -c '.')"
  else
    platform_results_json='[]'
  fi

  missed_finding_attribution_reports=""
  missed_findings_json='[]'
  # Invoke in the current shell so attribution reports survive (no $(...)).
  reviewer_loop_missed_finding_records "$_mf_prior_payload" "$_configured_platforms" "$_next_iteration" >/dev/null
  _mf_count="$(printf '%s\n' "$missed_findings_json" | jq 'length' 2>/dev/null)" || _mf_count=0
  [[ "$_mf_count" =~ ^[0-9]+$ ]] || _mf_count=0

  local attribution_section=""
  if [ -n "${missed_finding_attribution_reports:-}" ]; then
    while IFS= read -r _attr_line; do
      [ -n "$_attr_line" ] || continue
      attribution_section="${attribution_section}
${_attr_line}"
    done <<< "$missed_finding_attribution_reports"
  fi

  # Probe writability with the same rules as payload_from_existing (AC-7a/7b).
  # Eligibility already ran above; only report telemetry failure when records
  # were owed (attributable external blockers) and history cannot be written.
  local _hist_append_safe=1
  local _hist_unavail_reason=""
  if [ -n "$_prior_history_json" ]; then
    if ! printf '%s\n' "$_prior_history_json" | jq -e '.' >/dev/null 2>&1; then
      _hist_append_safe=0
      _hist_unavail_reason="malformed_history"
    elif ! printf '%s\n' "$_prior_payload" |
        jq -e --arg schema "$REVIEWER_LOOP_HISTORY_SCHEMA" \
          '.schema == $schema and (.entries | type) == "array"' >/dev/null 2>&1; then
      _hist_append_safe=0
      _hist_unavail_reason="unknown_schema"
    elif [ "$(printf '%s\n' "$_prior_payload" | jq -r '.history_status // "available"')" = "unavailable" ]; then
      _hist_append_safe=0
      _hist_unavail_reason="$(printf '%s\n' "$_prior_payload" | jq -r '.history_unavailable_reason // "prior_unavailable"')"
    fi
  elif printf '%s\n' "$_existing_comment_body" | grep -Fq "$REVIEWER_LOOP_HISTORY_MARKER"; then
    _hist_append_safe=0
    _hist_unavail_reason="missing_history_json"
  fi
  if [ "$_existing_read_failed" -eq 1 ] && [ "$_hist_append_safe" -eq 1 ]; then
    # Read failed and fell back to an unavailable stub body — not appendable.
    _hist_append_safe=0
    _hist_unavail_reason="${_hist_unavail_reason:-comment_read_failed}"
  fi

  if [ "$_mf_count" -gt 0 ] && [ "$_hist_append_safe" -eq 0 ]; then
    # Records were owed but history is unwritable — clear them so build_entry
    # does not invent a write that append_to_summary will refuse, and report.
    # Do not show the would-be miss lines: AC-7a requires no record and a
    # telemetry-failure report, not a summary of data that was never stored.
    # Attribution failures (AC-11) remain visible — nothing was owed for those.
    missed_findings_json='[]'
    missed_findings_section=""
    missed_finding_telemetry_section="
**Missed-finding telemetry:** could not be recorded this round (${_hist_unavail_reason:-unknown}). Existing reviewer-loop history was left unchanged."
  fi

  local _display_missed_findings_json='[]'
  _display_missed_findings_json="$(reviewer_loop_missed_findings_from_history_payload "$_prior_payload")"
  if [ "$_mf_count" -gt 0 ] && [ "$_hist_append_safe" -eq 1 ]; then
    _display_missed_findings_json="$(jq -s 'add' \
      <(printf '%s\n' "$_display_missed_findings_json") \
      <(printf '%s\n' "$missed_findings_json"))"
  fi
  if [ "$(printf '%s\n' "$_display_missed_findings_json" | jq 'length' 2>/dev/null)" -gt 0 ] 2>/dev/null; then
    missed_findings_section="$(reviewer_loop_missed_findings_summary_section "$_display_missed_findings_json")"
  else
    missed_findings_section=""
  fi

  local comment_body
  comment_body="$(cat <<EOF
### Automated Reviewer Loop Summary

**Result:** ${result_line}
**Platforms:** ${platform_list:-none}${policy_status_section}
**Findings:** ${blocking} blocking, ${suggestions} suggestions
${small_findings_section}${missed_findings_section}${attribution_section}${missed_finding_telemetry_section}${head_evidence_section}${expensive_gate_section}${second_local_pass_section}${phase_section}${compare_section}${advisory_section}${advisory_checks_section}${strict_spec_summary_section}${strict_plan_summary_section}${regression_label_section}

*Posted automatically by \`pr-review-loop.sh\`.*
EOF
)"

  comment_body="$(reviewer_loop_history_append_to_summary "$comment_body" "$_existing_comment_body" \
    "$result" "$reason" "$platform_list" "$blocking" "$suggestions" \
    "$phase_enabled" "$phase_platform_list" "$phase_started" \
    "$phase_net_new_blocker" "$phase_blocking_platform")"

  local _patch_payload
  _patch_payload="$(jq -n --arg body "$comment_body" '{body: $body}')"
  local _comment_posted=0
  if [ -n "$_existing_comment_id" ]; then
    # Edit the existing comment in place; fall back to creating a new comment
    # if the PATCH fails (e.g. comment was deleted or a transient API error).
    if gh api "repos/$_repo/issues/comments/$_existing_comment_id" \
        --method PATCH \
        --input - <<< "$_patch_payload" >/dev/null 2>&1; then
      _comment_posted=1
    else
      echo "WARN: failed to update existing summary comment ${_existing_comment_id} for PR ${pr_number}; falling back to create" >&2
    fi
  fi
  if [ "$_comment_posted" -eq 0 ]; then
    local _body_tmpfile
    _body_tmpfile="$(mktemp)"
    printf '%s' "$comment_body" > "$_body_tmpfile"
    if gh pr comment "$pr_number" --body-file "$_body_tmpfile" >/dev/null 2>&1; then
      _comment_posted=1
    else
      echo "WARN: failed to post reviewer loop summary comment for PR ${pr_number}" >&2
    fi
    rm -f "$_body_tmpfile"
  fi

  set -e

  # Persistence failure signal (#1502 dual-cap follow-up): when BOTH the
  # PATCH and the create-fallback fail, this cycle's reviewer_loop_history.v1
  # entry (built by reviewer_loop_history_append_to_summary above and folded
  # into $comment_body) was never actually written to the PR. If the caller
  # does not react to this, the next invocation's reviewer_loop_resolve_
  # cycle_counts call re-reads the unchanged, stale ledger — the fixer still
  # gets dispatched, but that dispatch is never counted, and repeated
  # persistence failures (e.g. a token that can read but not write
  # comments) would let unbounded cycles slip past both caps (found in
  # review of PR #1507). Return non-zero so the caller (which invokes this
  # function BEFORE printing RESULT=/REASON=, specifically so a correction
  # here happens before anything is emitted — see the call site) can
  # correct aggregate_result to escalate/ledger_persist_failed and still
  # emit exactly ONE RESULT=/REASON= pair. An earlier design printed RESULT=
  # twice and relied on a "last line wins" parsing convention; that was
  # itself a bug (this script's own kv_value helper reads the FIRST match),
  # fixed by moving this call before the print instead.
  #
  # ALSO fail closed on a read failure even when the write itself succeeds
  # (see the _existing_read_failed comment above): a read failure means
  # this cycle's entry may have been silently dropped (folded into an
  # "unavailable" stub that reviewer_loop_history_payload_from_existing
  # refuses to append onto) even though the comment POST succeeded — the
  # write succeeding is not sufficient evidence that this cycle is
  # actually countable.
  if [ "$_comment_posted" -eq 0 ] || [ "$_existing_read_failed" -eq 1 ]; then
    return 1
  fi
  return 0
}

if [ -z "$last_platform" ]; then
  print_kv LOCAL_SECOND_PASS 0
  print_kv LOCAL_SECOND_PASS_REASON not_required
  print_kv RESULT skipped
  print_kv REASON not_configured
  print_kv PLATFORM ""
  print_kv COMMENT_COUNT 0
  print_kv BLOCKING_COUNT 0
  print_kv SUGGESTION_COUNT 0
  print_kv UNRESOLVED_THREAD_COUNT 0
  _post_review_summary "skipped" "not_configured" "none" "0" "0" "" "" "0" "" "0" "0" "" "0"
  sync_reviewer_failed_label "$pr_number" 0
  reviewer_loop_emit_local_ai_head_evidence_keys
  exit 0
fi

# --- Compare mode: restore first-blocking aggregate, emit output, write metrics ---
# When compare mode is active, all platforms ran to completion. Later clean platforms
# may have overwritten aggregate_result after the first blocking platform set it.
# Restore the first-blocking state now to ensure the overall result is identical to
# what normal mode would have produced (BR-1: first blocking platform in config order
# governs).
if [ "$compare_mode" -eq 1 ] && [ "${#compare_verdicts[@]}" -gt 0 ]; then
  # Restore aggregate from the first blocking platform, if any.
  if [ -n "$compare_first_blocking_result" ]; then
    aggregate_result="$compare_first_blocking_result"
    aggregate_reason="$compare_first_blocking_reason"
    aggregate_output="$compare_first_blocking_output"
    aggregate_status=$compare_first_blocking_status
  fi
  # aggregate_result is now clean/skipped (if no platform blocked) or the result
  # of the first blocking platform in config order.

  # Emit compare-mode key=value output lines.
  print_kv COMPARE_MODE 1
  local_compare_index=0
  _idx=0
  while [ "$_idx" -lt "${#compare_verdicts[@]}" ]; do
    _cvname="${compare_verdicts[$_idx]}"
    _cvtoken="${compare_verdicts[$((_idx + 1))]}"
    local_compare_index=$((local_compare_index + 1))
    print_kv "COMPARE_VERDICT_${local_compare_index}_PLATFORM" "$_cvname"
    print_kv "COMPARE_VERDICT_${local_compare_index}_RESULT" "$_cvtoken"
    _idx=$((_idx + 2))
  done

fi

# --- Unresolved review thread gate ---
# When all platforms returned clean or skipped, check whether any bot-authored
# review threads remain unresolved before declaring the aggregate result clean.
# This catches Nitpick/Trivial/Minor severity threads that individual platform
# handlers do not classify as blocking but that still need explicit resolution.
# unresolved_bot_logins is declared here (outside the if-block) so the
# post-clean recheck below can safely reference it regardless of code path.
declare -a unresolved_bot_logins=()
for _platform in "${platforms[@]}"; do
  _login="$(bot_login_for_platform "$_platform")"
  # REST API returns bot logins WITH the "[bot]" suffix; GraphQL API returns
  # them WITHOUT it. Strip it here so check_unresolved_threads, which queries
  # GraphQL, compares against the correct login form.
  # (e.g. "chatgpt-codex-connector[bot]" → "chatgpt-codex-connector")
  _login="${_login%\[bot\]}"
  [ -n "$_login" ] && unresolved_bot_logins+=("$_login")
done

if [ "$aggregate_result" = "needs_fixes" ] \
    && [ "$total_blocking_count" -gt 0 ] \
    && [ "${#aggregate_blocking_findings[@]}" -gt 0 ]; then
  small_findings_paths="$(printf '%s\n' "${aggregate_blocking_paths[@]}" | sort -u)"
  _sf_content_json="$(printf '%s\n' "${aggregate_blocking_findings[@]}" | reviewer_loop_small_findings_content_analysis)"
  if [ "$(printf '%s' "$_sf_content_json" | jq -r '.all_small // false')" = "true" ]; then
    small_findings_only=1
    small_findings_paths_inline="$(printf '%s\n' "$small_findings_paths" | awk 'BEGIN { sep = "" } { printf "%s%s", sep, $0; sep = ", " } END { printf "\n" }')"
  else
    # Content causes: set SMALL_FINDINGS_BLOCKED_BY by within-group precedence.
    # Currency causes are unreachable when findings are not all small.
    small_findings_blocked_by="$(printf '%s' "$_sf_content_json" | jq -r '.blocked_by // empty')"
    small_findings_shipped_detail="$(printf '%s' "$_sf_content_json" | jq -r '.shipped_paths // [] | join(", ")')"
    small_findings_surfaces_detail="$(printf '%s' "$_sf_content_json" | jq -r '.contract_surfaces // [] | join(", ")')"
  fi
  unset _sf_content_json
fi

if [ "$aggregate_result" = "clean" ] || [ "$aggregate_result" = "skipped" ] \
    || [ "$small_findings_only" -eq 1 ]; then

  unresolved_thread_count=0
  if [ "${#unresolved_bot_logins[@]}" -gt 0 ]; then
    # Do NOT use 2>&1 — stderr (WARN/ERROR messages) must remain on stderr so that only
    # the integer count appears on stdout for clean capture into unresolved_thread_count.
    # Bot logins are passed as individual positional args to avoid glob expansion.
    # Retry up to THREAD_AUDIT_MAX_RETRIES times on transient GraphQL failures (exit 3)
    # before escalating. Never degrade to treating the audit as clean on failure.
    thread_audit_max_retries="$(thread_audit_max_retries_value)"
    thread_audit_attempt=0
    thread_check_output=""
    thread_check_status=0
    while true; do
      thread_audit_attempt=$((thread_audit_attempt + 1))
      set +e
      # mode=strict: this is the aggregate RESULT=clean gate and must never be
      # relaxed by a reply-without-resolve (see check_unresolved_threads).
      thread_check_output="$(check_unresolved_threads "$pr_number" "$(repo_slug)" strict "${unresolved_bot_logins[@]}")"
      thread_check_status=$?
      set -e
      if [ "$thread_check_status" -eq 3 ] && [ "$thread_audit_attempt" -le "$thread_audit_max_retries" ]; then
        echo "WARN: check_unresolved_threads GraphQL failure (aggregate gate, attempt $thread_audit_attempt/$thread_audit_max_retries) — retrying" >&2
        sleep 5
        continue
      fi
      break
    done
    if [ "$thread_check_status" -eq 2 ]; then
      # Exit 2 = page-cap exceeded. Escalate: the audit was incomplete so we cannot
      # confirm threads past page 10 are resolved. This is not a fixable finding —
      # sending it through the fixer loop is pointless. Hard-stop for human inspection.
      echo "WARN: check_unresolved_threads exceeded page cap — escalating for manual inspection" >&2
      aggregate_result="escalate"
      aggregate_reason="unresolved_thread_check_incomplete"
      unresolved_thread_count=-1
    elif [ "$thread_check_status" -ne 0 ]; then
      # Exit 3 after all retries (or any other non-zero) = GraphQL audit failure.
      # Escalate: we cannot confirm threads are resolved, so RESULT=clean must not be
      # emitted. Never degrade gracefully — a silent bypass of the thread audit can
      # allow PRs with unresolved review threads to be labeled ready-for-human-review.
      echo "ERROR: check_unresolved_threads failed (exit $thread_check_status, $thread_audit_attempt attempts / $thread_audit_max_retries retries) — escalating (thread audit required)" >&2
      aggregate_result="escalate"
      aggregate_reason="review_thread_audit_failed"
      unresolved_thread_count=-1
    else
      unresolved_thread_count="$thread_check_output"
    fi
  fi
  print_kv UNRESOLVED_THREAD_COUNT "$unresolved_thread_count"

  if [ "$unresolved_thread_count" -gt 0 ]; then
    aggregate_result="needs_fixes"
    aggregate_reason="unresolved_review_threads"
    small_findings_stop=0
    if [ "$phase_after_clean_enabled" -eq 1 ] && [ "$phase_after_clean_started" -eq 1 ]; then
      phase_after_clean_net_new_blocker=1
      phase_after_clean_blocking_platform="${phase_after_clean_blocking_platform:-review_threads}"
    fi
    # Increment total_blocking_count so BLOCKING_COUNT reflects the unresolved threads.
    # No BLOCKING_N_* entries are emitted for thread findings — callers must use
    # REASON=unresolved_review_threads and UNRESOLVED_THREAD_COUNT to handle this case.
    total_blocking_count=$((total_blocking_count + unresolved_thread_count))
  elif [ "$aggregate_result" = "needs_fixes" ] \
      && [ "$unresolved_thread_count" -eq 0 ] \
      && [ "$small_findings_only" -eq 1 ]; then
    reviewer_loop_latest_summary_body="$(reviewer_loop_fetch_latest_summary_body "$pr_number")"
    _sf_terminal_json="$(
      printf '%s\n' "${aggregate_blocking_findings[@]}" \
        | reviewer_loop_evaluate_small_findings_terminal \
            "$reviewer_loop_latest_summary_body" \
            "${loop_head_sha:-}" \
            "$small_findings_required_rounds" \
            "$unresolved_thread_count" \
            "${platform_reviewed_heads[@]:-}"
    )"
    aggregate_result="$(printf '%s' "$_sf_terminal_json" | jq -r '.result // "needs_fixes"')"
    aggregate_reason="$(printf '%s' "$_sf_terminal_json" | jq -r '.reason // empty')"
    small_findings_rounds="$(printf '%s' "$_sf_terminal_json" | jq -r '.small_findings_rounds // 0')"
    small_findings_blocked_by="$(printf '%s' "$_sf_terminal_json" | jq -r '.small_findings_blocked_by // empty')"
    small_findings_currency_detail="$(printf '%s' "$_sf_terminal_json" | jq -r '.currency_detail // empty')"
    if [ "$(printf '%s' "$_sf_terminal_json" | jq -r '.small_findings_stop // false')" = "true" ]; then
      aggregate_status=0
      small_findings_stop=1
      echo "INFO: small-findings stop — ${small_findings_rounds}/${small_findings_required_rounds} consecutive rounds only touched small non-shipped findings on the current head; strict thread audit found zero unresolved threads" >&2
    fi
    unset reviewer_loop_latest_summary_body _sf_terminal_json
  fi
else
  print_kv UNRESOLVED_THREAD_COUNT 0
fi

# --- Post-clean recheck ---
# After the reviewer loop exits clean and the immediate thread gate passes,
# wait a short interval and re-query reviewThreads. This catches bot review
# threads (e.g. CodeRabbit) that are posted asynchronously and arrive after
# the platform handlers and thread gate have already completed. Without this
# recheck, Step 5.1 must catch these late threads — at the cost of a full
# reviewer-loop redispatch cycle. The recheck adds a single ~30-second wait
# in exchange for avoiding that more expensive recovery path.
#
# The recheck only runs when:
#   - aggregate_result is "clean" after the immediate thread gate
#   - compare_mode is not active (recheck is not meaningful in evaluation mode)
#   - SKIP_POST_CLEAN_RECHECK is not set to "1" (allows callers to suppress
#     on re-dispatch after a prior late-thread fix cycle, so the recheck does
#     not run again on the corrective invocation)
#
# Configurable via POST_CLEAN_WAIT env var (default: 30 seconds).
# Emits POST_CLEAN_RECHECK=1 when the wait-and-recheck runs, and
# LATE_THREADS_FOUND=<N> with the count of newly-discovered unresolved threads.
# Take the longest settle configuration across every configured platform: any
# of them can be the one that posts late, so the window must accommodate the
# slowest rather than whichever happened to run last.
settle_window=0
settle_quiet=0
settle_poll=0
settle_require_review=0
for _sp in "${platforms[@]}"; do
  read -r _sw _sq _spoll _srr <<<"$(_settle_config_for_platform "$_sp")"
  [ "${_sw:-0}" -gt "$settle_window" ] && settle_window="$_sw"
  [ "${_sq:-0}" -gt "$settle_quiet" ] && settle_quiet="$_sq"
  [ "${_srr:-0}" -eq 1 ] && settle_require_review=1
  if [ "$settle_poll" -eq 0 ] || { [ "${_spoll:-0}" -gt 0 ] && [ "${_spoll:-0}" -lt "$settle_poll" ]; }; then
    settle_poll="${_spoll:-30}"
  fi
done
[ "$settle_window" -gt 0 ] || settle_window=180
[ "$settle_quiet" -gt 0 ] || settle_quiet=60
[ "$settle_poll" -gt 0 ] || settle_poll=30
unset _sp _sw _sq _spoll _srr

if [ "$aggregate_result" = "clean" ] \
    && [ "$compare_mode" -eq 0 ] \
    && [ "${SKIP_POST_CLEAN_RECHECK:-0}" != "1" ] \
    && [ "${#unresolved_bot_logins[@]}" -gt 0 ] \
    && [ -n "$pr_number" ]; then
  print_kv POST_CLEAN_RECHECK 1
  print_kv POST_CLEAN_SETTLE_WINDOW_SECONDS "$settle_window"
  print_kv POST_CLEAN_SETTLE_QUIET_SECONDS "$settle_quiet"
  print_kv POST_CLEAN_REQUIRE_REVIEW "$settle_require_review"
  if [ "$settle_require_review" -eq 1 ]; then
    echo "INFO: post-clean settle — awaiting a submitted review for this HEAD, then ${settle_quiet}s of silence (max ${settle_window}s), polling every ${settle_poll}s" >&2
  else
    echo "INFO: post-clean settle — requiring ${settle_quiet}s of platform silence (max ${settle_window}s), polling every ${settle_poll}s" >&2
  fi
  # since_iso for the settle probes is the HEAD commit time, not "now": a review
  # submitted between the loop starting and the settle beginning still counts as
  # this HEAD's review, and anchoring to "now" would wait for a second one.
  # Anchor to the head this run reviewed, captured before dispatch. The
  # previous form read head_sha with a HEAD fallback, and head_sha is only
  # ever function-local, so at this scope it asked the API for commits/HEAD —
  # which GitHub resolves to the DEFAULT BRANCH head. Measured on PR #1575:
  # that anchor was nine days old, so any review CodeRabbit had ever
  # submitted satisfied "a submitted review for this HEAD" and the
  # require-review settle waited for nothing. When the head is unknown, the
  # anchor is now: a review must land after this point (conservative —
  # Check 0.6 refuses the unbound verdict anyway).
  settle_head_iso=""
  if [ -n "$loop_head_sha" ]; then
    settle_head_iso="$(gh api "repos/$(repo_slug)/commits/${loop_head_sha}" --jq '.commit.committer.date // empty' 2>/dev/null)" || settle_head_iso=""
  fi
  if [ -z "$settle_head_iso" ]; then
    settle_head_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "WARN: post-clean settle — head commit time unavailable; a submitted review must land after ${settle_head_iso} to count" >&2
  fi
  settle_review_seen=0
  # The head this settle is about. Emitted as POST_CLEAN_HEAD_SHA so Protocol
  # 91 Check 0.6 can refuse telemetry that describes a commit the PR has since
  # moved past (a fix pushed between Step 7 and Step 8a) — issue #1574.
  settle_head_sha="$loop_head_sha"

  late_thread_count=0
  settle_elapsed=0
  settle_quiet_elapsed=0
  settle_activity_seen=0
  settle_probe_failed=0
  settle_since="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  settle_repo="$(repo_slug)"

  while [ "$settle_elapsed" -lt "$settle_window" ] \
     && [ "$settle_quiet_elapsed" -lt "$settle_quiet" ]; do
    _interruptible_sleep "$settle_poll"
    settle_elapsed=$((settle_elapsed + settle_poll))

    # Threads first: a late unresolved thread is the outcome we are hunting,
    # and finding one ends the wait immediately.
    late_thread_check_output=""
    late_thread_check_status=0
    set +e
    # mode=strict: this decides RESULT=clean and must never be relaxed by a
    # reply-without-resolve (see check_unresolved_threads).
    late_thread_check_output="$(check_unresolved_threads "$pr_number" "$settle_repo" strict "${unresolved_bot_logins[@]}")"
    late_thread_check_status=$?
    set -e

    if [ "$late_thread_check_status" -eq 2 ]; then
      echo "WARN: post-clean settle: check_unresolved_threads exceeded page cap — escalating" >&2
      aggregate_result="escalate"
      aggregate_reason="post_clean_recheck_thread_check_incomplete"
      late_thread_count=-1
      break
    elif [ "$late_thread_check_status" -ne 0 ]; then
      echo "WARN: post-clean settle: check_unresolved_threads failed (exit $late_thread_check_status) — escalating" >&2
      aggregate_result="escalate"
      aggregate_reason="post_clean_recheck_thread_audit_failed"
      late_thread_count=-1
      break
    fi

    late_thread_count="$late_thread_check_output"
    if [ "$late_thread_count" -gt 0 ]; then
      echo "INFO: post-clean settle — found $late_thread_count late unresolved thread(s) after ${settle_elapsed}s; switching to needs_fixes" >&2
      aggregate_result="needs_fixes"
      aggregate_reason="late_review_threads"
      reviewer_loop_append_late_thread_missed_findings "$pr_number" "$settle_repo"
      if [ "$phase_after_clean_enabled" -eq 1 ] && [ "$phase_after_clean_started" -eq 1 ]; then
        phase_after_clean_net_new_blocker=1
        phase_after_clean_blocking_platform="${phase_after_clean_blocking_platform:-late_review_threads}"
      fi
      total_blocking_count=$((total_blocking_count + late_thread_count))
      break
    fi

    # No unresolved thread yet — but the platform may still be mid-write, and a
    # comment posted without a review thread (or a walkthrough edited in place)
    # is exactly the signal that more is coming. Any activity resets the quiet
    # timer rather than merely being noted.
    settle_activity="$(_bot_activity_since "$settle_repo" "$pr_number" "$settle_since" "${unresolved_bot_logins[@]}")"
    if [ "$settle_activity" = "-1" ]; then
      # A failed probe is not silence. Do not let it satisfy the quiet period.
      settle_probe_failed=1
      echo "WARN: post-clean settle: activity probe failed; not counting this interval as quiet" >&2
    elif [ "${settle_activity:-0}" -gt 0 ]; then
      settle_activity_seen=1
      settle_quiet_elapsed=0
      settle_since="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      echo "INFO: post-clean settle — $settle_activity new platform action(s) at ${settle_elapsed}s; quiet timer reset" >&2
    elif [ "$settle_require_review" -eq 1 ] && [ "$settle_review_seen" -eq 0 ]; then
      # Silence before the review lands is the platform thinking, not finishing.
      # Do not let it accumulate toward the quiet period.
      settle_review_probe="$(_bot_review_submitted_since "$settle_repo" "$pr_number" "$settle_head_iso" "$settle_head_sha" "${unresolved_bot_logins[@]}")"
      if [ "$settle_review_probe" = "1" ]; then
        settle_review_seen=1
        echo "INFO: post-clean settle — submitted review detected at ${settle_elapsed}s; quiet period starts now" >&2
      elif [ "$settle_review_probe" = "-1" ]; then
        settle_probe_failed=1
        echo "WARN: post-clean settle: review probe failed; not counting this interval as quiet" >&2
      else
        echo "INFO: post-clean settle — no submitted review yet at ${settle_elapsed}s of ${settle_window}s; still waiting" >&2
      fi
    else
      settle_quiet_elapsed=$((settle_quiet_elapsed + settle_poll))
    fi
  done

  if [ "$aggregate_result" = "clean" ]; then
    if [ "$settle_quiet_elapsed" -ge "$settle_quiet" ]; then
      print_kv POST_CLEAN_SETTLED 1
      echo "INFO: post-clean settle — platform quiet for ${settle_quiet_elapsed}s; result remains clean" >&2
    else
      # The window ran out before the quiet period was satisfied. The verdict is
      # still clean (no unresolved thread was ever found) but it is weaker than
      # a settled one, and saying so is the difference between a caller that
      # knows to look and one that does not.
      print_kv POST_CLEAN_SETTLED 0
      print_kv POST_CLEAN_SETTLE_TIMEOUT 1
      if [ "$settle_require_review" -eq 1 ] && [ "$settle_review_seen" -eq 0 ]; then
        print_kv POST_CLEAN_NO_SUBMITTED_REVIEW 1
        echo "WARN: post-clean settle — window (${settle_window}s) exhausted and the platform never submitted a review for this HEAD." >&2
        echo "  Its walkthrough comment alone does not mean it finished. Verdict is clean but UNSETTLED — re-query threads before labelling." >&2
      else
        echo "WARN: post-clean settle — window (${settle_window}s) exhausted before ${settle_quiet}s of silence; the platform was still active. Verdict is clean but UNSETTLED." >&2
      fi
    fi
    [ "$settle_probe_failed" -eq 1 ] && print_kv POST_CLEAN_ACTIVITY_PROBE_FAILED 1
    [ "$settle_activity_seen" -eq 1 ] && print_kv POST_CLEAN_ACTIVITY_SEEN 1
  fi

  # The instant the verdict was established. A caller that inserts a long poll
  # between this timestamp and the readiness label is acting on a stale check —
  # see the "adjacent to the readiness decision" note in the reviewer-loop docs.
  print_kv POST_CLEAN_SETTLED_AT "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  print_kv POST_CLEAN_HEAD_SHA "$settle_head_sha"
  print_kv LATE_THREADS_FOUND "$late_thread_count"
else
  print_kv POST_CLEAN_RECHECK 0
  # Say WHY the recheck did not run (issue #1574). Protocol 91's readiness
  # checklist treats no_thread_posting_platforms as "nothing could arrive late"
  # and every other reason as "the verdict was never settled — re-run Step 7".
  if [ "$aggregate_result" != "clean" ]; then
    print_kv POST_CLEAN_RECHECK_SKIP_REASON not_clean
  elif [ "$compare_mode" -ne 0 ]; then
    print_kv POST_CLEAN_RECHECK_SKIP_REASON compare_mode
  elif [ "${SKIP_POST_CLEAN_RECHECK:-0}" = "1" ]; then
    print_kv POST_CLEAN_RECHECK_SKIP_REASON skip_env
  elif [ "${#unresolved_bot_logins[@]}" -eq 0 ]; then
    print_kv POST_CLEAN_RECHECK_SKIP_REASON no_thread_posting_platforms
  else
    print_kv POST_CLEAN_RECHECK_SKIP_REASON no_pr_number
  fi
  # Emit LATE_THREADS_FOUND=0 on skipped paths so consumers can always rely on
  # the field being present, regardless of whether the recheck ran.
  print_kv LATE_THREADS_FOUND 0
  # The head binding applies to every clean verdict, not only settled ones:
  # a no-thread-platform run is just as stale once the PR moves.
  print_kv POST_CLEAN_HEAD_SHA "$loop_head_sha"
fi

# Head-move guard (#1574): a push that lands while the reviewers run leaves
# the clean verdict describing a commit the PR no longer sits on. Refuse it
# here, before the summary records it, rather than letting Check 0.6 compare
# a head that was read after the fact.
if [ "$aggregate_result" = "clean" ] && [ -n "$pr_number" ] && [ -n "$loop_head_sha" ]; then
  live_head_sha=""
  if live_head_sha="$(gh pr view "$pr_number" --json headRefOid --jq '.headRefOid' 2>/dev/null)" \
    && [ -n "$live_head_sha" ] && [ "$live_head_sha" != "$loop_head_sha" ]; then
    echo "WARN: PR head moved from ${loop_head_sha} to ${live_head_sha} while this loop ran; the clean verdict describes the old head — re-run the loop for the current HEAD" >&2
    aggregate_result="needs_fixes"
    aggregate_reason="head_moved_during_run"
  fi
fi

if [ "$aggregate_result" != "clean" ]; then
  small_findings_stop=0
fi

if [ "$phase_after_clean_enabled" -eq 1 ] && [ "$phase_after_clean_started" -eq 0 ]; then
  phase_after_clean_skip_reason="$aggregate_result"
fi
print_kv SMALL_FINDINGS_ONLY "$small_findings_only"
print_kv SMALL_FINDINGS_STOP "$small_findings_stop"
print_kv SMALL_FINDINGS_ROUNDS "$small_findings_rounds"
print_kv SMALL_FINDINGS_REQUIRED_ROUNDS "$small_findings_required_rounds"
[ -n "$small_findings_paths_inline" ] && print_kv SMALL_FINDINGS_PATHS "$small_findings_paths_inline"
[ -n "${small_findings_blocked_by:-}" ] && print_kv SMALL_FINDINGS_BLOCKED_BY "$small_findings_blocked_by"
print_kv PHASE_AFTER_CLEAN_STARTED "$phase_after_clean_started"
print_kv READY_PHASE_STARTED "$phase_after_clean_started"
if [ "$phase_after_clean_enabled" -eq 1 ]; then
  if [ "$phase_after_clean_started" -eq 1 ]; then
    print_kv READY_PHASE_GATE_RESULT "$phase_after_clean_gate_result"
    print_kv PHASE_AFTER_CLEAN_GATE_RESULT "$phase_after_clean_gate_result"
  else
    print_kv READY_PHASE_SKIP_REASON "$phase_after_clean_skip_reason"
    print_kv PHASE_AFTER_CLEAN_SKIP_REASON "$phase_after_clean_skip_reason"
  fi
  print_kv READY_PHASE_NET_NEW_BLOCKER "$phase_after_clean_net_new_blocker"
  print_kv PHASE_AFTER_CLEAN_NET_NEW_BLOCKER "$phase_after_clean_net_new_blocker"
  [ -n "$phase_after_clean_blocking_platform" ] && \
    print_kv READY_PHASE_BLOCKING_PLATFORM "$phase_after_clean_blocking_platform"
  [ -n "$phase_after_clean_blocking_platform" ] && \
    print_kv PHASE_AFTER_CLEAN_BLOCKING_PLATFORM "$phase_after_clean_blocking_platform"
fi

# Reviewer cycle cap enforcement (#1502, dual-cap): the just-pushed fix (if
# any) has already been given its chance to be verified above — this run
# completed a full review pass like any other. Only now, with the settled
# aggregate result in hand, do we check whether either cap has been
# reached. A "clean" result is never overridden. An already-"escalate"
# result keeps its own (more specific) reason rather than being relabeled.
# This MUST run before the persistence step, compare-mode metrics-row
# append, and the single RESULT= print below: --compare mode's own
# contract is "the overall exit code and RESULT are identical to what
# normal mode would produce" (see the script's usage doc), and these
# overrides are unconditional (they also apply in --compare mode) — so the
# metrics row and the printed RESULT must reflect the post-override
# result, not a stale pre-cap value.
#
# Order: unavailable (fail-closed) first, then the per-run cap
# (max_cycles_exceeded — the Protocol-91-aligned, more specific signal),
# then the lifetime ceiling (max_total_cycles_exceeded — the structural
# backstop). Both counts fail together (-1/-1) when the ledger could not be
# read, so the unavailable check only needs to inspect one of them.
if [ "$aggregate_reason" = "head_moved_during_run" ]; then
  # Not a fixer cycle: the reviewers were clean, the PR simply moved. The
  # caller re-runs the loop; neither cap applies and the ledger does not
  # count it (reviewer_loop_history_entries_count excludes this reason).
  :
elif reviewer_loop_cycle_count_unavailable_should_escalate "$lifetime_cycle_count" "$aggregate_result"; then
  echo "WARN: reviewer cycle counts could not be read (ledger unavailable after retries) with aggregate_result=$aggregate_result — escalating (cycle_count_unavailable) rather than allowing an unbounded number of unverifiable retries" >&2
  aggregate_result="escalate"
  aggregate_reason="cycle_count_unavailable"
elif reviewer_loop_cap_exceeded "$cycle_count" "$max_cycles" "$aggregate_result"; then
  echo "WARN: reviewer per-run cycle count ($cycle_count) reached max_cycles ($max_cycles) for run_id=$current_run_id with aggregate_result=$aggregate_result — escalating (max_cycles_exceeded)" >&2
  aggregate_result="escalate"
  aggregate_reason="max_cycles_exceeded"
elif reviewer_loop_cap_exceeded "$lifetime_cycle_count" "$max_total_cycles" "$aggregate_result"; then
  echo "WARN: reviewer lifetime cycle count ($lifetime_cycle_count) reached max_total_cycles ($max_total_cycles) with aggregate_result=$aggregate_result — escalating (max_total_cycles_exceeded)" >&2
  aggregate_result="escalate"
  aggregate_reason="max_total_cycles_exceeded"
fi

advisory_checks_section="$(run_project_advisory_checks "$pr_number")"

aggregate_possible_issue_eval_outcome="$(kv_value_default POSSIBLE_ISSUE_EVAL_OUTCOME "$aggregate_output" "")"
if [ "${#phase_after_clean_platforms[@]}" -gt 0 ]; then
  phase_after_clean_platform_list="$(IFS=,; printf '%s' "${phase_after_clean_platforms[*]}")"
else
  phase_after_clean_platform_list=""
fi

# Build per-platform result list for the PR summary comment.
# Format: "pr-agent (clean), haystack (unavailable), claude-code-action (escalated (timeout))"
_summary_platform_list=""
if [ "${#platform_result_tokens[@]}" -gt 0 ]; then
  for _sprt in "${platform_result_tokens[@]}"; do
    _spname="${_sprt%%:*}"
    _spdisp="${_sprt#*:}"
    [ -n "$_summary_platform_list" ] && _summary_platform_list="${_summary_platform_list}, "
    _summary_platform_list="${_summary_platform_list}${_spname} (${_spdisp})"
  done
fi
[ -z "$_summary_platform_list" ] && _summary_platform_list="none"

# Compatibility flag retained for older orchestrators; summaries now post on
# every needs_fixes exit regardless of this value.
: "$post_final_summary"

# Persist this cycle's reviewer_loop_history.v1 ledger entry BEFORE
# printing RESULT/REASON or appending the compare-mode metrics row (#1502
# dual-cap follow-up, single-RESULT-line fix). Previously this call and its
# ledger_persist_failed correction happened INSIDE the case statement
# below, AFTER RESULT/REASON had already been printed once for the
# pre-correction value — producing a SECOND, contradictory RESULT= line.
# This script's own kv_value helper returns the FIRST matching key (`{...
# exit }` on first match), not the last, so a caller using that same
# convention would read the stale, pre-correction RESULT and could dispatch
# another fixer despite the script exiting escalated (found in review of
# PR #1507). Persisting first and correcting aggregate_result BEFORE any
# print_kv call guarantees exactly one RESULT= / REASON= line is ever
# emitted, valid under either "first wins" or "last wins" parsing.
#
# Skipped for "skipped" (no ledger entry is ever written for that result —
# see the not-configured early-exit path above, which never reaches here).
if [ "$aggregate_result" != "skipped" ]; then
  _post_summary_exit=0
  _post_review_summary "$aggregate_result" "$aggregate_reason" \
    "$_summary_platform_list" \
    "$total_blocking_count" "$total_suggestion_count" \
    "$aggregate_advisory_labels" \
    "$aggregate_possible_issue_eval_outcome" \
    "$phase_after_clean_enabled" "$phase_after_clean_platform_list" \
    "$phase_after_clean_started" "$phase_after_clean_net_new_blocker" \
    "$phase_after_clean_blocking_platform" "$pre_after_clean_only" \
    "$advisory_checks_section" || _post_summary_exit=$?
  if reviewer_loop_persist_failure_should_escalate "$_post_summary_exit" "$aggregate_result" "$aggregate_reason"; then
    echo "WARN: reviewer-loop summary comment could not be persisted for a dispatch-triggering result ($aggregate_result) — escalating (ledger_persist_failed) rather than letting an uncounted fixer/retry dispatch happen" >&2
    aggregate_result="escalate"
    aggregate_reason="ledger_persist_failed"
  fi
fi

# Append compare-mode metrics row after the thread gate, the cap checks,
# AND the persistence step above, so the recorded aggregate_result always
# matches the single RESULT= line printed below — including the
# ledger_persist_failed correction, which (unlike the earlier cap-override
# checks) can only be known once _post_review_summary's persistence
# attempt has actually been made. This makes the previous "supplementary
# corrected row" workaround for that specific case unnecessary; a reader
# of docs/workflow/retro-metrics-platforms.md now always sees the single,
# final, correct outcome for this cycle.
_compare_metrics_appended=0
if [ "$compare_mode" -eq 1 ] && [ "${#compare_verdicts[@]}" -gt 0 ]; then
  set +e
  _metrics_args=("$pr_number" "$branch_name" "$aggregate_result")
  _idx=0
  while [ "$_idx" -lt "${#compare_verdicts[@]}" ]; do
    _metrics_args+=("${compare_verdicts[$_idx]}" "${compare_verdicts[$((_idx + 1))]}")
    _idx=$((_idx + 2))
  done
  append_compare_metrics_row "${_metrics_args[@]}" 2>/dev/null && \
    _compare_metrics_appended=1 || \
    echo "WARN: append_compare_metrics_row failed — metrics row not written" >&2
  set -e
fi

if reviewer_failed_label_required_for_result "$aggregate_result" "$aggregate_reason"; then
  reviewer_failed_required=1
fi
sync_reviewer_failed_label "$pr_number" "$reviewer_failed_required"

print_kv LOCAL_SECOND_PASS "${local_second_pass:-0}"
print_kv LOCAL_SECOND_PASS_REASON "${local_second_pass_reason:-not_required}"
print_kv RESULT "$aggregate_result"
print_kv PLATFORM "$last_platform"
[ -n "$aggregate_reason" ] && print_kv REASON "$aggregate_reason"
print_kv COMMENT_COUNT "$total_comment_count"
print_kv BLOCKING_COUNT "$total_blocking_count"
print_kv SUGGESTION_COUNT "$total_suggestion_count"

if [ -n "$aggregate_output" ]; then
  review_comment_id="$(kv_value REVIEW_COMMENT_ID "$aggregate_output")"
  [ -n "$review_comment_id" ] && print_kv REVIEW_COMMENT_ID "$review_comment_id"
fi

reviewer_loop_emit_local_ai_head_evidence_keys

# _post_review_summary has already run above (using the pre-correction
# aggregate_result as its own "result"/"reason" arguments intentionally —
# the persisted ledger entry and the rendered comment reflect what this
# cycle's review actually found; only the SCRIPT'S OWN reported RESULT/
# REASON are corrected to escalate/ledger_persist_failed on a persistence
# failure). This case statement now only selects the exit code for the
# final (possibly corrected) aggregate_result.
case "$aggregate_result" in
  clean)
    exit 0
    ;;
  skipped)
    exit 0
    ;;
  needs_fixes)
    exit 1
    ;;
  needs_rerun)
    # PR-Agent "Possible Issue" evaluation pushed a fix; orchestrator must
    # re-invoke the loop on the new HEAD. This completed iteration was
    # already persisted above so retrospective retry metrics do not lose
    # the fix-pushed run.
    exit 3
    ;;
  waiting_on_reviewer)
    exit 4
    ;;
  escalate)
    exit 2
    ;;
  *)
    exit "${aggregate_status:-2}"
    ;;
esac

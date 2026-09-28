#!/usr/bin/env bash
# Helper-gated readiness labels (issue #1408).
#
# Readiness labels (`ready-for-human-review`, `ready-for-regression`) are input
# to the merge gates (`run-epic-delegated-gate.sh`, `batch-merge.sh`,
# `workflow-next-action.sh`), not cosmetics. Delegated runners have applied them
# by hand before the ready-phase reviewer finished, asserting readiness no
# reviewer verdict supports (PR #2097 on a downstream repo; PR #77 on another).
# This script is the only sanctioned way to apply them: it refuses unless every
# configured ready-phase reviewer check run is `completed` for the *current* head
# SHA, the reviewer posted no blocking findings on that SHA, and no
# non-reviewer check is still pending or failing.
#
# An absent reviewer check run is treated as NOT clean — Cursor "Restrict
# Access" can make Bugbot refuse to run, and "no check run" must never read as
# "reviewer clean".
#
# Findings are read from `pulls/N/comments` (inline review comments) and
# `pulls/N/reviews`, never from issue comments: Bugbot reports through a
# `COMMENTED` PR review with inline comments, the same surface
# `run_bugbot_review()` in pr-review-loop.sh reads.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'USAGE'
Usage: apply-readiness-labels.sh --pr <number> [--repo <owner/repo>] \
  --label <ready-for-human-review|ready-for-regression> [--json]

Refuses to apply the label unless every configured ready-phase reviewer check
run is `completed` for the current head SHA, the reviewer posted no blocking
findings on that SHA, and no other check is pending or failing.

Prints RESULT=<labeled|refused|escalate> and REASON=<slug>.
Exit codes: 0 labeled, 1 refused, 2 escalate (state could not be read).
USAGE
}

pr_number=""
repo=""
label=""
json_output="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr)
      [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { printf 'ERROR: missing value for --pr\n' >&2; exit 2; }
      [ -z "$pr_number" ] || { printf 'ERROR: repeated option: --pr\n' >&2; exit 2; }
      pr_number="$2"
      shift 2
      ;;
    --repo)
      [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { printf 'ERROR: missing value for --repo\n' >&2; exit 2; }
      [ -z "$repo" ] || { printf 'ERROR: repeated option: --repo\n' >&2; exit 2; }
      repo="$2"
      shift 2
      ;;
    --label)
      [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { printf 'ERROR: missing value for --label\n' >&2; exit 2; }
      [ -z "$label" ] || { printf 'ERROR: repeated option: --label\n' >&2; exit 2; }
      label="$2"
      shift 2
      ;;
    --json) json_output="true"; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

if [ -z "$pr_number" ] || [ -z "$label" ]; then
  usage >&2
  exit 2
fi
case "$label" in
  ready-for-human-review|ready-for-regression) ;;
  *) printf 'ERROR: --label must be ready-for-human-review or ready-for-regression\n' >&2; exit 2 ;;
esac
case "$pr_number" in
  ''|*[!0-9]*) printf 'ERROR: --pr must be a number\n' >&2; exit 2 ;;
esac

require_gh
cd_workflow_repo_root
[ -n "$repo" ] || repo="$(repo_slug)"

# Readiness gate verdict.
result="refused"
reason=""
head_sha=""
reviewer_report=""
blocking_count=0
pending_count=0
failing_count=0

# configured_ready_reviewer_platforms — the platforms whose check run gates
# readiness. Mirrors item-completion-self-check.sh's configured_review_platforms:
# the repo-local override file wins when it declares the list.
configured_ready_reviewer_platforms() {
  local config_file
  config_file="$(workflow_effective_config_file 2>/dev/null || workflow_config_file)"
  if [ "$config_file" = "$(workflow_config_file)" ]; then
    WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 workflow_config_review_on_ready_github "$config_file"
  else
    workflow_config_review_on_ready_github "$config_file"
  fi
}

# reviewer_check_name_for_platform <platform> — the check-run name a ready-phase
# reviewer publishes. Same mapping configured_reviewer_check_names_json applies
# (workflow-lib.sh), narrowed to the ready-phase list and kept separate so that
# helper's existing behavior is left untouched (#1559 audits its consumers).
reviewer_check_name_for_platform() {
  case "$1" in
    haystack) printf '%s\n' "${HAYSTACK_CHECK_NAME:-Haystack / Review}" ;;
    bugbot) printf '%s\n' "${BUGBOT_CHECK_NAME:-Cursor Bugbot}" ;;
    ronda) printf '%s\n' "${RONDA_CHECK_NAME:-Ronda review}" ;;
    *) printf '\n' ;;
  esac
}

emit_verdict() {
  print_kv RESULT "$result"
  print_kv REASON "$reason"
  print_kv PR_NUMBER "$pr_number"
  print_kv REPO "$repo"
  print_kv LABEL "$label"
  print_kv HEAD_SHA "$head_sha"
  print_kv REVIEWER_REPORT "$reviewer_report"
  print_kv BLOCKING_FINDING_COUNT "$blocking_count"
  print_kv PENDING_CHECK_COUNT "$pending_count"
  print_kv FAILING_CHECK_COUNT "$failing_count"
  if [ "$json_output" = "true" ]; then
    python3 -c 'import json,sys; print(json.dumps(dict(result=sys.argv[1], reason=sys.argv[2], prNumber=sys.argv[3], repo=sys.argv[4], label=sys.argv[5], headSha=sys.argv[6], reviewerReport=sys.argv[7], blockingFindingCount=int(sys.argv[8]), pendingCheckCount=int(sys.argv[9]), failingCheckCount=int(sys.argv[10]))))' \
      "$result" "$reason" "$pr_number" "$repo" "$label" "$head_sha" "$reviewer_report" "$blocking_count" "$pending_count" "$failing_count"
  fi
}

escalate() {
  result="escalate"
  reason="$1"
  emit_verdict
  exit 2
}

# --- 1. PR state -----------------------------------------------------------
pr_json=""
if ! pr_json="$(gh pr view "$pr_number" --repo "$repo" --json headRefOid,labels,statusCheckRollup 2>/dev/null)" || [ -z "$pr_json" ]; then
  escalate pr-state-unavailable
fi
head_sha="$(printf '%s\n' "$pr_json" | jq -r '.headRefOid // ""' 2>/dev/null)" || escalate pr-state-parse-failed
if [ -z "$head_sha" ]; then
  escalate head-sha-unavailable
fi

# --- 2. Ready-phase reviewer check runs for the current head ----------------
reviewer_blocking=0
verdict_blocking=0
applied_notified=0
reviewer_names_seen=""
platform=""
while IFS= read -r platform; do
  [ -n "$platform" ] || continue
  check_name="$(reviewer_check_name_for_platform "$platform")"
  [ -n "$check_name" ] || continue
  bot_login="$(bot_login_for_platform "$platform")"
  reviewer_names_seen="${reviewer_names_seen}${reviewer_names_seen:+,}${check_name}"

  check_runs_json=""
  if ! check_runs_json="$(gh api "repos/$repo/commits/$head_sha/check-runs" --paginate 2>/dev/null)" || [ -z "$check_runs_json" ]; then
    escalate check-run-fetch-failed
  fi
  if ! check_state="$(printf '%s\n' "$check_runs_json" | jq -r --arg name "$check_name" '
        [ .check_runs[]? | select(.name == $name) ]
        | sort_by(.started_at // .completed_at // "")
        | last
        | (if . == null then " " else ((.status // "") + " " + (.conclusion // "")) end)
      ' 2>/dev/null)"; then
    escalate check-run-parse-failed
  fi
  status_val="${check_state%% *}"
  conclusion="${check_state#* }"

  # Absent check run is not clean: the reviewer may have refused to run.
  if [ -z "$status_val" ] || [ "$status_val" = "null" ] || [ "$status_val" = " " ]; then
    result="refused"
    reason="reviewer-check-absent"
    emit_verdict
    exit 1
  fi
  if [ "$status_val" != "completed" ]; then
    result="refused"
    reason="reviewer-check-not-completed"
    emit_verdict
    exit 1
  fi
  # A non-success conclusion is itself a blocking verdict, even when no inline
# finding survives classification — the loop applies the same rule. `neutral`,
# `cancelled`, `skipped` and `success` are informational.
case "$conclusion" in
    failure|action_required|timed_out|startup_failure)
      verdict_blocking=$((verdict_blocking + 1))
      ;;
  esac

  # The reviewer already flagged this SHA. Read the PR's existing labels so the
  # verdict can name the still-owed work without a second fetch below. Must run
  # before any exit-1 path, hence its position ahead of the finding reads.
  if [ "$verdict_blocking" -gt 0 ] && [ "$applied_notified" -eq 0 ]; then
    applied_notified=1
    applied_labels="$(printf '%s\n' "$pr_json" | jq -r '.labels[]?.name' 2>/dev/null)" || applied_labels=""
    if ! printf '%s\n' "$applied_labels" | grep -qx 'needs-fixes'; then
      gh pr edit "$pr_number" --repo "$repo" --add-label 'needs-fixes' >/dev/null 2>&1 || true
    fi
  fi

  # Read findings only where a login exists (haystack reviews through its own
  # CLI and publishes no GitHub review surface).
  [ -n "$bot_login" ] || continue
  comments_json=""
  reviews_json=""
  if ! comments_json="$(gh api "repos/$repo/pulls/$pr_number/comments" --paginate 2>/dev/null)"; then
    escalate review-comment-fetch-failed
  fi
  if ! reviews_json="$(gh api "repos/$repo/pulls/$pr_number/reviews" --paginate 2>/dev/null)"; then
    escalate review-fetch-failed
  fi

  # Inline comments on this SHA, posted top-level by the reviewer bot.
  inline_json=""
  if ! inline_json="$(printf '%s\n' "${comments_json:-[]}" | jq -c --arg bot "$bot_login" --arg sha "$head_sha" '
        [ .[]?
          | select(
              (.user.login == $bot or (.user.login // "") == ($bot | sub("\\[bot\\]$"; "")) or (.user.login // "") == ($bot + "[bot]"))
              and .commit_id == $sha
              and (.in_reply_to_id // null) == null
            )
          | { body: (.body // "") }
        ]
      ' 2>/dev/null)"; then
    escalate review-comment-parse-failed
  fi
  inline_count="$(printf '%s\n' "$inline_json" | jq 'length' 2>/dev/null)" || escalate review-comment-parse-failed

  # Reviews submitted against this SHA. `CHANGES_REQUESTED` is always blocking;
  # a `COMMENTED` review is blocking when it carries inline findings on this SHA
  # (the umbrella review Bugbot posts) or Bugbot's own finding markers.
  review_json=""
  if ! review_json="$(printf '%s\n' "${reviews_json:-[]}" | jq -c --arg bot "$bot_login" --arg sha "$head_sha" --argjson inline "$inline_count" '
        [ .[]?
          | select(
              ((.user.login == $bot) or ((.user.login // "") == ($bot | sub("\\[bot\\]$"; ""))) or ((.user.login // "") == ($bot + "[bot]")))
              and ((.commit_id // .commitId // "") == $sha)
            )
          | { state: (.state // ""), body: (.body // ""), inline: $inline }
        ]
      ' 2>/dev/null)"; then
    escalate review-parse-failed
  fi

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    body="$(printf '%s\n' "$entry" | jq -r '.body')"
    state="$(printf '%s\n' "$entry" | jq -r '.state')"
    inline="$(printf '%s\n' "$entry" | jq -r '.inline')"
    if [ "$state" = "CHANGES_REQUESTED" ]; then
      reviewer_blocking=$((reviewer_blocking + 1))
      continue
    fi
    [ -n "$body" ] || continue
    if is_soft_suggestion "$body" || is_bugbot_clean_review "$body" || is_bugbot_explicit_skip_message "$body"; then
      continue
    fi
    if [ "$state" = "COMMENTED" ] && [ "$inline" -eq 0 ] && ! printf '%s\n' "$body" | grep -q "BUGBOT_REVIEW\|BUGBOT_BUG_ID\|LOCATIONS"; then
      continue
    fi
    reviewer_blocking=$((reviewer_blocking + 1))
  done < <(printf '%s\n' "$review_json" | jq -c '.[]' 2>/dev/null)

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    body="$(printf '%s\n' "$entry" | jq -r '.body')"
    [ -n "$body" ] || continue
    if is_soft_suggestion "$body" || is_bugbot_clean_review "$body" || is_bugbot_explicit_skip_message "$body"; then
      continue
    fi
    reviewer_blocking=$((reviewer_blocking + 1))
  done < <(printf '%s\n' "$inline_json" | jq -c '.[]' 2>/dev/null)
done < <(configured_ready_reviewer_platforms)

reviewer_report="${reviewer_names_seen:-none}"

if [ "$reviewer_blocking" -gt 0 ] || [ "$verdict_blocking" -gt 0 ]; then
  result="refused"
  reason="blocking-findings"
  blocking_count="$reviewer_blocking"
  [ "$blocking_count" -ge 1 ] || blocking_count=1
  emit_verdict
  exit 1
fi

# --- 3. Non-reviewer checks must not be pending or failing ------------------
normalized=""
if ! normalized="$(printf '%s\n' "$pr_json" | normalize_status_check_rollup 2>/dev/null)" || [ -z "$normalized" ]; then
  escalate check-rollup-parse-failed
fi

baseline_json=""
if ! baseline_json="$(printf '%s\n' "$normalized" | jq -c --argjson names "$(printf '%s\n' "$reviewer_names_seen" | tr ',' '\n' | jq -R . | jq -s '.')" '
      [ .[]
        | (.name // .context // .workflowName // "unknown") as $n
        | select(($names | index($n)) | not)
      ]
    ' 2>/dev/null)"; then
  escalate check-rollup-parse-failed
fi

pending_count="$(printf '%s\n' "$baseline_json" | jq '
  [ .[] | select(
      (((.status // "") != "") and ((.status // "") != "COMPLETED"))
      or (((.state // "") | ascii_upcase) == "EXPECTED")
      or (((.state // "") | ascii_upcase) == "PENDING")
      or (((.state // "") | ascii_upcase) == "IN_PROGRESS")
      or (((.state // "") | ascii_upcase) == "QUEUED")
    ) ] | length
' 2>/dev/null)" || escalate check-rollup-parse-failed

failing_count="$(printf '%s\n' "$baseline_json" | jq '
  [ .[] | select(
      (((.conclusion // "") | ascii_upcase) == "FAILURE")
      or (((.conclusion // "") | ascii_upcase) == "CANCELLED")
      or (((.conclusion // "") | ascii_upcase) == "TIMED_OUT")
      or (((.conclusion // "") | ascii_upcase) == "ACTION_REQUIRED")
      or (((.conclusion // "") | ascii_upcase) == "STARTUP_FAILURE")
      or (((.state // "") | ascii_upcase) == "FAILURE")
      or (((.state // "") | ascii_upcase) == "ERROR")
    ) ] | length
' 2>/dev/null)" || escalate check-rollup-parse-failed

if [ "$pending_count" -gt 0 ]; then
  result="refused"
  reason="ci-pending"
  emit_verdict
  exit 1
fi
if [ "$failing_count" -gt 0 ]; then
  result="refused"
  reason="ci-failing"
  emit_verdict
  exit 1
fi

# --- 4. Apply ---------------------------------------------------------------
if ! gh pr edit "$pr_number" --repo "$repo" --add-label "$label" >/dev/null 2>&1; then
  escalate label-apply-failed
fi

# Re-read so a silently-dropped label is not reported as applied.
applied_labels="$(gh pr view "$pr_number" --repo "$repo" --json labels --jq '.labels[].name' 2>/dev/null)" || escalate label-verify-failed
if ! printf '%s\n' "$applied_labels" | grep -qx "$label"; then
  escalate label-not-applied
fi

result="labeled"
reason="gate-passed"
emit_verdict
exit 0
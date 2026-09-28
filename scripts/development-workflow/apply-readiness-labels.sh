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
# "reviewer clean". The same applies to a `neutral` check run that accompanies a
# Bugbot usage/spend-limit notice: the reviewer never actually reviewed.
#
# The reviewer leg applies to implementation branches only (`feature/*`,
# `fix/*`, `refactor/*`, `hotfix/*`, `backport/hotfix/*`) — the same boundary
# Protocol 91 draws for `IS_IMPLEMENTATION_PR` and for its Step 7b label
# derivation table. Ready-phase reviewers are not dispatched on `spec/*`,
# `implementation-plan/*`, graduation (`develop-<slug>`), or `release/*` PRs, so
# no check run can exist for them; gating on one would refuse every doc-stage and
# release PR. The CI leg still applies on those branches.
#
# `ready-for-regression` blocks on failing non-reviewer checks but permits
# pending ones: that label is what *starts* the configured regression workflow,
# so requiring green CI before it is applied would make Step 7b depend on checks
# the label itself triggers. `ready-for-human-review` — the merge-gate input —
# blocks on pending as well.
#
# Findings are read from `pulls/N/comments` (inline review comments) and
# `pulls/N/reviews`, never from issue comments: Bugbot reports through a
# `COMMENTED` PR review with inline comments, the same surface
# `run_bugbot_review()` in pr-review-loop.sh reads.
#
# Issue comments are read for exactly one purpose: when a reviewer check run
# finishes `neutral`, `cancelled`, or `skipped`, Bugbot's own usage/spend-limit
# and restricted-access notices arrive as a `cursor[bot]` issue comment for that
# head. A bare `neutral` therefore reads as clean only when no such notice
# exists — otherwise the verdict is `refused` / `reviewer-unavailable`. Same
# rule as `run_bugbot_review()` (pr-review-loop.sh ~3838).
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
findings on that SHA, and no other check is pending or failing. A `neutral`
reviewer check run with a Bugbot usage/spend-limit notice is refused as well:
the reviewer never reviewed.

Prints RESULT=<labeled|refused|escalate> and REASON=<slug>.
Exit codes: 0 labeled, 1 refused, 2 escalate (state could not be read).
Refusal reasons: reviewer-check-absent, reviewer-check-not-completed,
reviewer-unavailable, reviewer-check-name-unresolved, blocking-findings,
ci-pending, ci-failing, head-changed-before-apply. Escalation reasons:
head-revalidate-failed, head-changed-after-apply, ready-config-unreadable.
The ready-phase reviewer list is read from the PR head's own
.ai-dev-workflow.yaml; an unreadable head configuration escalates (fail-closed)
rather than falling back to this checkout's configuration.
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

# pr_head_config_ready_platforms <repo> <sha> — `review.on_ready.github` read
# from the PR's own head commit, not this checkout. The target PR may itself
# modify `.ai-dev-workflow.yaml` (drop the configured ready reviewer, add
# one); reading the local file would gate the label on a list the PR's own
# configuration no longer declares. Fail closed: a fetch/parse failure
# escalates rather than falling back to the local checkout silently — the
# reviewer set is the gate, so an unreadable one is an unreadable gate.
pr_head_config_ready_platforms() {
  local repo_arg="$1" sha_arg="$2"
  local content_b64 config_body head_config_file
  content_b64="$(gh api "repos/$repo_arg/contents/.ai-dev-workflow.yaml?ref=$sha_arg" \
      --jq '.content // ""' 2>/dev/null)" || return 1
  [ -n "$content_b64" ] || return 1
  config_body="$(printf '%s\n' "$content_b64" | tr -d '\n' | base64 -d 2>/dev/null)" || return 1
  [ -n "$config_body" ] || return 1
  head_config_file="$(mktemp)" || return 1
  printf '%s\n' "$config_body" >"$head_config_file"
  workflow_config_review_on_ready_github "$head_config_file"
  local rc=$?
  rm -f "$head_config_file"
  return "$rc"
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
if ! pr_json="$(gh pr view "$pr_number" --repo "$repo" --json headRefOid,headRefName,labels,statusCheckRollup 2>/dev/null)" || [ -z "$pr_json" ]; then
  escalate pr-state-unavailable
fi
head_sha="$(printf '%s\n' "$pr_json" | jq -r '.headRefOid // ""' 2>/dev/null)" || escalate pr-state-parse-failed
if [ -z "$head_sha" ]; then
  escalate head-sha-unavailable
fi
head_ref_name="$(printf '%s\n' "$pr_json" | jq -r '.headRefName // ""' 2>/dev/null)" || escalate pr-state-parse-failed

# Implementation branches are the ones that carry a ready-phase reviewer check
# run and a required `ready-for-regression` label (Protocol 91's label derivation
# table). Doc-stage, graduation, and release PRs are not reviewer-gated.
case "$head_ref_name" in
  feature/*|fix/*|refactor/*|hotfix/*|backport/hotfix/*) is_implementation_pr="true" ;;
  *) is_implementation_pr="false" ;;
esac

# --- 2. Ready-phase reviewer check runs for the current head ----------------
reviewer_blocking=0
verdict_blocking=0
applied_notified=0
reviewer_names_seen=""
platform=""
if [ "$is_implementation_pr" = "true" ]; then
  # The PR's own head configuration is the source of truth (see
  # pr_head_config_ready_platforms). An explicit AI_DEV_WORKFLOW_CONFIG_FILE
  # (test harness or deliberate override) short-circuits the head fetch; a
  # head fetch/parse failure escalates — fail closed — instead of silently
  # gating on this checkout's configuration, which the PR may have changed.
  if [ -n "${AI_DEV_WORKFLOW_CONFIG_FILE:-}" ]; then
    ready_platforms="$(configured_ready_reviewer_platforms)"
  elif ! ready_platforms="$(pr_head_config_ready_platforms "$repo" "$head_sha" 2>/dev/null)"; then
    escalate ready-config-unreadable
  fi
else
  ready_platforms=""
fi
while IFS= read -r platform; do
  [ -n "$platform" ] || continue
  check_name="$(reviewer_check_name_for_platform "$platform")"
  # Fail closed: a configured ready-phase reviewer with no check-name mapping
  # (e.g. codex-github, this repo's documented default) must not be silently
  # skipped — that would gate the label on zero reviewer verdicts. Refuse so a
  # human extends the mapping instead of the label going out unreviewed.
  if [ -z "$check_name" ]; then
    result="refused"
    reason="reviewer-check-name-unresolved"
    reviewer_report="$platform"
    emit_verdict
    exit 1
  fi
  bot_login="$(bot_login_for_platform "$platform")"
  reviewer_names_seen="${reviewer_names_seen}${reviewer_names_seen:+,}${check_name}"
  # Set here, not after the loop: the in-loop refusal paths below still emit a
  # verdict, and an empty REVIEWER_REPORT there would read as "no reviewer".
  reviewer_report="$reviewer_names_seen"

  # `--slurp` merges the paginated responses into one array; without it `gh`
  # emits one JSON object per page and the jq below runs once per page, making
  # `check_state` multiline (a first-page "completed failure" then reads
  # conclusion "failure\n " and misses the blocking case).
  check_runs_json=""
  if ! check_runs_json="$(gh api "repos/$repo/commits/$head_sha/check-runs" --paginate --slurp 2>/dev/null)" || [ -z "$check_runs_json" ]; then
    escalate check-run-fetch-failed
  fi
  if ! check_state="$(printf '%s\n' "$check_runs_json" | jq -r --arg name "$check_name" '
        [ .[].check_runs[]? | select(.name == $name) ]
        | sort_by(.started_at // .completed_at // "")
        | last
        | (if . == null then " " else ((.status // "") + " " + (.conclusion // "")) end)
      ' 2>/dev/null)"; then
    escalate check-run-parse-failed
  fi
  status_val="${check_state%% *}"
  conclusion="${check_state#* }"

  # started_at of the selected (latest) check run. Findings are time-bounded
  # to it: a stale same-SHA review comment from an *earlier* reviewer run must
  # not block forever — same rule pr-review-loop.sh applies (~3704-3729),
  # where `.created_at > $since` scopes the verdict read.
  reviewer_started_at="$(printf '%s\n' "$check_runs_json" | jq -r --arg name "$check_name" '
        [ .[].check_runs[]? | select(.name == $name) ]
        | sort_by(.started_at // .completed_at // "")
        | last
        | (.started_at // .completed_at // .created_at // "")
      ' 2>/dev/null)" || escalate check-run-parse-failed

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
  # finding survives classification — the loop applies the same rule.
  case "$conclusion" in
    failure|action_required|timed_out|startup_failure)
      verdict_blocking=$((verdict_blocking + 1))
      ;;
  esac

  # `neutral` / `cancelled` / `skipped` are informational ONLY when the reviewer
  # did not also post an unavailable notice for this head. Bugbot reports a
  # usage/spend limit and a restricted-access refusal through a `neutral` check
  # run plus an issue comment, so a bare `neutral` must never read as clean —
  # that is the exact shape of "reviewer did not actually run" this gate exists
  # to catch. `run_bugbot_review()` applies the same rule (pr-review-loop.sh
  # ~3838). This is the only issue-comment read in this helper, and it is an
  # availability probe, not a finding source: findings come from
  # `pulls/N/comments` and `pulls/N/reviews`.
  # Only Bugbot reports unavailability this way, and only through an issue
  # comment authored by its own bot login, so the probe is scoped to both.
  case "$conclusion" in
    neutral|cancelled|skipped)
      if [ "$platform" = "bugbot" ] && [ -n "$bot_login" ]; then
        reviewer_started_at="$(printf '%s\n' "$check_runs_json" | jq -r --arg name "$check_name" '
              [ .[].check_runs[]? | select(.name == $name) ]
              | sort_by(.started_at // .completed_at // "")
              | last
              | (.started_at // .completed_at // .created_at // "")
            ' 2>/dev/null)" || escalate check-run-parse-failed
        issue_comments_json=""
        if ! issue_comments_json="$(gh api "repos/$repo/issues/$pr_number/comments" --paginate --slurp 2>/dev/null)"; then
          escalate issue-comment-fetch-failed
        fi
        unavailable_bodies=""
        if ! unavailable_bodies="$(printf '%s\n' "${issue_comments_json:-[]}" | jq -r --arg bot "$bot_login" --arg since "$reviewer_started_at" '
              [ .[]?[]
                | select(
                    ((.user.login // "") == $bot or (.user.login // "") == ($bot + "[bot]"))
                    and (($since == "") or ((.created_at // "") > $since))
                  )
                | .body // ""
              ] | .[]
            ' 2>/dev/null)"; then
          escalate issue-comment-parse-failed
        fi
        while IFS= read -r notice; do
          [ -n "$notice" ] || continue
          if is_bugbot_disabled_message "$notice" || is_bugbot_usage_limit_message "$notice"; then
            result="refused"
            reason="reviewer-unavailable"
            emit_verdict
            exit 1
          fi
        done <<< "$unavailable_bodies"
      fi
      ;;
  esac

  # The reviewer already flagged this SHA. Read the PR's existing labels so the
  # verdict can name the still-owed work without a second fetch below. Must run
  # before any exit-1 path, hence its position ahead of the finding reads.
  if [ "$verdict_blocking" -gt 0 ] && [ "$applied_notified" -eq 0 ]; then
    applied_notified=1
    applied_labels="$(printf '%s\n' "$pr_json" | jq -r '.labels[]?.name' 2>/dev/null)" || applied_labels=""
    if ! printf '%s\n' "$applied_labels" | grep -qx 'needs-fixes'; then
      gh pr edit "$pr_number" --repo "$repo" --add-label 'needs-fixes' >/dev/null 2>&1 || true  # workflow-shell-guard: allow SH001 - best-effort annotation; a failure here must not mask the blocking verdict about to be emitted.
    fi
  fi

  # Read findings only where a login exists (haystack reviews through its own
  # CLI and publishes no GitHub review surface).
  [ -n "$bot_login" ] || continue
  comments_json=""
  reviews_json=""
  # Findings/comment fetches use `--paginate --slurp` and flatten in jq: an
  # unslurped paginated response is one JSON document per page, so a jq
  # pipeline runs per page and a downstream consumer sees a multiline
  # concatenation instead of one array (same defect class as the check-runs
  # read above).
  if ! comments_json="$(gh api "repos/$repo/pulls/$pr_number/comments" --paginate --slurp 2>/dev/null)"; then
    escalate review-comment-fetch-failed
  fi
  if ! reviews_json="$(gh api "repos/$repo/pulls/$pr_number/reviews" --paginate --slurp 2>/dev/null)"; then
    escalate review-fetch-failed
  fi

  # Inline comments on this SHA, posted top-level by the reviewer bot.
  inline_json=""
  if ! inline_json="$(printf '%s\n' "${comments_json:-[]}" | jq -c --arg bot "$bot_login" --arg sha "$head_sha" --arg since "$reviewer_started_at" '
        [ .[]?[]
          | select(
              ((.user.login // "") == $bot or (.user.login // "") == ($bot | sub("\\[bot\\]$"; "")) or (.user.login // "") == ($bot + "[bot]"))
              and ((.commit_id // "") == $sha)
              and ((.in_reply_to_id // null) == null)
              and ((.created_at // "") >= $since)
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
  if ! review_json="$(printf '%s\n' "${reviews_json:-[]}" | jq -c --arg bot "$bot_login" --arg sha "$head_sha" --arg since "$reviewer_started_at" --argjson inline "$inline_count" '
        [ .[]?[]
          | select(
              (((.user.login // "") == $bot) or ((.user.login // "") == ($bot | sub("\\[bot\\]$"; ""))) or ((.user.login // "") == ($bot + "[bot]")))
              and ((.commit_id // .commitId // "") == $sha)
              and (((.submitted_at // "") >= $since))
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
done < <(printf '%s\n' "$ready_platforms")

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

# `ready-for-regression` is applied at Step 7b — *before* the Step 8 CI loop — so
# a pending check is normal there and must not block. `ready-for-human-review` is
# the merge-gate input and has no such excuse: pending refuses.
if [ "$pending_count" -gt 0 ] && [ "$label" != "ready-for-regression" ]; then
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
# `--add-label` binds nothing to a commit: a push landing between the state
# read at the top and this mutation would leave every reviewer/CI verdict
# describing the old head while the label certifies the new one. Re-fetch the
# head immediately before the mutation and refuse on any drift.
current_head="$(gh pr view "$pr_number" --repo "$repo" --json headRefOid --jq '.headRefOid' 2>/dev/null)" || escalate head-revalidate-failed
if [ -z "$current_head" ]; then
  escalate head-revalidate-failed
fi
if [ "$current_head" != "$head_sha" ]; then
  result="refused"
  reason="head-changed-before-apply"
  emit_verdict
  exit 1
fi

if ! gh pr edit "$pr_number" --repo "$repo" --add-label "$label" >/dev/null 2>&1; then
  escalate label-apply-failed
fi

# Re-read so a silently-dropped label is not reported as applied, and so a
# push that landed during the mutation is still caught: the label then
# certifies a head no verdict describes.
post_apply_json="$(gh pr view "$pr_number" --repo "$repo" --json labels,headRefOid 2>/dev/null)" || escalate label-verify-failed
applied_labels="$(printf '%s\n' "$post_apply_json" | jq -r '.labels[].name' 2>/dev/null)" || escalate label-verify-failed
if ! printf '%s\n' "$applied_labels" | grep -qx "$label"; then
  escalate label-not-applied
fi
applied_head="$(printf '%s\n' "$post_apply_json" | jq -r '.headRefOid // ""' 2>/dev/null)" || escalate label-verify-failed
if [ "$applied_head" != "$head_sha" ]; then
  # The label now certifies a head no verdict describes. Remove it before
  # escalating so the new, unreviewed head does not carry a readiness label
  # between this refusal and whatever re-runs the gate. Best-effort only: a
  # failed removal logs a WARN and still escalates, so the human sees the
  # drift either way.
  if ! gh pr edit "$pr_number" --repo "$repo" --remove-label "$label" >/dev/null 2>&1; then
    printf 'WARN: %s\n' "failed to remove $label after head drift on PR #$pr_number — remove it manually" >&2
  fi
  escalate head-changed-after-apply
fi

result="labeled"
reason="gate-passed"
emit_verdict
exit 0
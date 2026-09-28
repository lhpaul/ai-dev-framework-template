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
# `fix/*`, `refactor/*`, `backport/hotfix/*`) — the same boundary Protocol 91
# draws for `IS_IMPLEMENTATION_PR` and for its Step 7b label derivation table.
# Ready-phase reviewers are not dispatched on `spec/*`,
# `implementation-plan/*`, graduation (`develop-<slug>`), `release/*`, or
# `hotfix/*` PRs, so no check run can exist for them; gating on one would
# refuse every doc-stage, release, and hotfix PR. `hotfix/*` is exempt the
# same way `release/*` is because pr-review-loop.sh's `_check_release_pr_guard`
# skips the reviewer loop for `release/*` AND `hotfix/*` head branches — no
# reviewer check is ever dispatched on a hotfix, so requiring one would
# permanently refuse both readiness labels `reviewer-check-absent`. Hotfix PRs
# still get what release PRs get: the CI leg applies unchanged (PR #1818
# finding 1, round 7). The CI leg still applies on those branches.
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
reviewer-unavailable, reviewer-check-name-unresolved,
reviewer-check-unknown-conclusion, reviewer-policy-empty, blocking-findings,
reviewer-state-changed, ci-pending, ci-failing, head-changed-before-apply.
Escalation reasons:
head-revalidate-failed, head-changed-after-apply, ready-config-unreadable,
base-config-unreadable, revalidation-unreadable.
The ready-phase reviewer list is read from the PR head's own
.ai-dev-workflow.yaml; an unreadable head configuration escalates (fail-closed)
rather than falling back to this checkout's configuration. The required
reviewer set is the BASE branch policy — the loop dispatches ready-phase
platforms from the base configuration, so head-only additions are never
required, but a head cannot waive a base-configured reviewer. The base policy
is resolved with local review overrides applied (the same effective policy
the loop dispatches); an absent .ai-dev-workflow.local.yaml falls back to the
shared policy. hotfix/* branches are exempt from the reviewer leg exactly as
release/* branches are — the reviewer loop is never dispatched on them — but
the CI leg still applies.
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
# When called for the BASE sha (loop_dispatched_base=1), the effective policy
# is resolved the same way pr-review-loop.sh resolves its base snapshot
# (WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 on workflow_config_review_platforms,
# pr-review-loop.sh ~12423-12449): a local `.ai-dev-workflow.local.yaml` that
# declares `review.on_ready.github` REPLACES the shared list, and the loop
# dispatches that replaced list — so this helper must gate on it too, or a
# local ronda-over-bugbot override would have the helper wait forever for a
# Bugbot check the loop never runs (PR #1818 finding 2, round 7). The override
# file is gitignored and absent from agent worktrees; an absent file falls
# back to the shared policy exactly as the loop itself does in a worktree
# (workflow_config_review_local_list_if_declared returns 1 when the local
# file is absent) — never fail, never resolve a different policy than the
# loop dispatched.
pr_head_config_ready_platforms() {
  local repo_arg="$1" sha_arg="$2"
  local content_b64 config_body head_config_file rc
  content_b64="$(gh api "repos/$repo_arg/contents/.ai-dev-workflow.yaml?ref=$sha_arg" \
      --jq '.content // ""' 2>/dev/null)" || return 1
  [ -n "$content_b64" ] || return 1
  config_body="$(printf '%s\n' "$content_b64" | tr -d '\n' | base64 -d 2>/dev/null)" || return 1
  [ -n "$config_body" ] || return 1
  head_config_file="$(mktemp)" || return 1
  printf '%s\n' "$config_body" >"$head_config_file"
  if [ "${loop_dispatched_base:-0}" = "1" ]; then
    WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 workflow_config_review_on_ready_github "$head_config_file"
  else
    workflow_config_review_on_ready_github "$head_config_file"
  fi
  rc=$?
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

# refuse <reason> — the single pre-apply refusal exit (PR #1818 finding 1,
# round 8). When the PR ALREADY carried the requested label when this run
# started (label_initially_present=1), the refusal verdict means that label
# no longer certifies a verified state — remove it best-effort so the
# delegated/batch merge gates cannot consume a stale readiness label on the
# strength of a refusal. WARN-and-refuse on removal failure. No removal when
# the label was not already present.
refuse() {
  reason="$1"
  if [ "$label_initially_present" = "1" ]; then
    remove_readiness_label_best_effort "$label"
  fi
  result="refused"
  emit_verdict
  exit 1
}

# remove_readiness_label_best_effort <label> — after a post-apply escalation,
# the label no longer certifies a verified state, so strip it before
# escalating so no unreviewed/undrifting head carries it between the refusal
# and whatever re-runs the gate. Best-effort only: a failed removal logs a
# WARN and the caller still escalates, so a human sees the problem either way.
remove_readiness_label_best_effort() {
  local label_to_remove="$1"
  if ! gh pr edit "$pr_number" --repo "$repo" --remove-label "$label_to_remove" >/dev/null 2>&1; then
    printf 'WARN: %s\n' "failed to remove $label_to_remove on PR #$pr_number — remove it manually" >&2
  fi
}

# reviewer_check_conclusion_is_clean <conclusion> — shared conclusion→verdict
# logic for the main reviewer gate and the pre-apply revalidation (PR #1818
# finding 2, round 5). The allow-list is explicit: `success` is clean; the
# four blocking conclusions are not; `neutral`/`cancelled`/`skipped` are not
# (they carry the unavailable handling in the main loop and are simply "no
# longer a clean completed run" at revalidation); ANY other non-empty
# conclusion is not (mirrors run_ronda_review()'s fail-closed default arm).
reviewer_check_conclusion_is_clean() {
  case "$1" in
    success) return 0 ;;
    *) return 1 ;;
  esac
}

# bugbot_unavailable_notice_present <bot_login> <since> — returns 0 (true)
# when a Bugbot usage/spend-limit or restricted-access notice was posted by
# the bot at/after <since> (inclusive, PR #1818 finding 3, round 8: a notice
# created in the SAME second as the check run's start belongs to that run;
# a strict > dropped it and read the non-review as clean). Shared by the main
# gate's unavailable handling and the pre-apply revalidation (PR #1818
# finding 2, round 6), so a rerun's quota refusal is caught at revalidation
# too. Escalates fail-closed on a fetch or parse failure.
bugbot_unavailable_notice_present() {
  local bot_login_arg="$1" since_arg="$2"
  local issue_comments_json unavailable_bodies notice
  issue_comments_json=""
  if ! issue_comments_json="$(gh api "repos/$repo/issues/$pr_number/comments" --paginate --slurp 2>/dev/null)"; then
    escalate issue-comment-fetch-failed
  fi
  unavailable_bodies=""
  if ! unavailable_bodies="$(printf '%s\n' "${issue_comments_json:-[]}" | jq -r --arg bot "$bot_login_arg" --arg since "$since_arg" '
        [ .[]?[]
          | select(
              ((.user.login // "") == $bot or (.user.login // "") == ($bot + "[bot]"))
              and (($since == "") or ((.created_at // "") >= $since))
            )
          | .body // ""
        ] | .[]
      ' 2>/dev/null)"; then
    escalate issue-comment-parse-failed
  fi
  while IFS= read -r notice; do
    [ -n "$notice" ] || continue
    if is_bugbot_disabled_message "$notice" || is_bugbot_usage_limit_message "$notice"; then
      return 0
    fi
  done <<< "$unavailable_bodies"
  return 1
}

# count_reviewer_blocking_findings <bot_login> <since> — fetches the PR review
# surfaces (inline comments + reviews) and classifies the reviewer bot's
# findings on the current head at/after <since>, setting the global
# scan_blocking_count. Shared by the main gate and the pre-apply revalidation
# (PR #1818 finding 2, round 6): a same-SHA rerun that completes between the
# initial scan and the label mutation can post findings the first scan never
# saw, so the revalidation rescans the same surfaces with the same filters
# against the reselected run's timestamp instead of trusting the earlier
# pass. Escalates fail-closed on a fetch or parse failure.
count_reviewer_blocking_findings() {
  local bot_login_arg="$1" since_arg="$2"
  local comments_json reviews_json inline_json review_json inline_count entry body state inline
  scan_blocking_count=0
  comments_json=""
  reviews_json=""
  # Findings/comment fetches use `--paginate --slurp` and flatten in jq: an
  # unslurped paginated response is one JSON document per page, so a jq
  # pipeline runs per page and a downstream consumer sees a multiline
  # concatenation instead of one array (same defect class as the check-runs
  # read in the main loop).
  if ! comments_json="$(gh api "repos/$repo/pulls/$pr_number/comments" --paginate --slurp 2>/dev/null)"; then
    escalate review-comment-fetch-failed
  fi
  if ! reviews_json="$(gh api "repos/$repo/pulls/$pr_number/reviews" --paginate --slurp 2>/dev/null)"; then
    escalate review-fetch-failed
  fi

  # Inline comments on this SHA, posted top-level by the reviewer bot.
  inline_json=""
  if ! inline_json="$(printf '%s\n' "${comments_json:-[]}" | jq -c --arg bot "$bot_login_arg" --arg sha "$head_sha" --arg since "$since_arg" '
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
  if ! review_json="$(printf '%s\n' "${reviews_json:-[]}" | jq -c --arg bot "$bot_login_arg" --arg sha "$head_sha" --arg since "$since_arg" --argjson inline "$inline_count" '
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
      scan_blocking_count=$((scan_blocking_count + 1))
      continue
    fi
    [ -n "$body" ] || continue
    if is_soft_suggestion "$body" || is_bugbot_clean_review "$body" || is_bugbot_explicit_skip_message "$body"; then
      continue
    fi
    if [ "$state" = "COMMENTED" ] && [ "$inline" -eq 0 ] && ! printf '%s\n' "$body" | grep -q "BUGBOT_REVIEW\|BUGBOT_BUG_ID\|LOCATIONS"; then
      continue
    fi
    scan_blocking_count=$((scan_blocking_count + 1))
  done < <(printf '%s\n' "$review_json" | jq -c '.[]' 2>/dev/null)

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    body="$(printf '%s\n' "$entry" | jq -r '.body')"
    [ -n "$body" ] || continue
    if is_soft_suggestion "$body" || is_bugbot_clean_review "$body" || is_bugbot_explicit_skip_message "$body"; then
      continue
    fi
    scan_blocking_count=$((scan_blocking_count + 1))
  done < <(printf '%s\n' "$inline_json" | jq -c '.[]' 2>/dev/null)
}

# --- 1. PR state -----------------------------------------------------------
pr_json=""
if ! pr_json="$(gh pr view "$pr_number" --repo "$repo" --json headRefOid,headRefName,baseRefOid,labels,statusCheckRollup 2>/dev/null)" || [ -z "$pr_json" ]; then
  escalate pr-state-unavailable
fi
head_sha="$(printf '%s\n' "$pr_json" | jq -r '.headRefOid // ""' 2>/dev/null)" || escalate pr-state-parse-failed
if [ -z "$head_sha" ]; then
  escalate head-sha-unavailable
fi
head_ref_name="$(printf '%s\n' "$pr_json" | jq -r '.headRefName // ""' 2>/dev/null)" || escalate pr-state-parse-failed
base_ref_oid="$(printf '%s\n' "$pr_json" | jq -r '.baseRefOid // ""' 2>/dev/null)" || escalate pr-state-parse-failed
# Whether the requested label is already on the PR at the START of this run
# (PR #1818 finding 1, round 8): a rerun (same-SHA reviewer rerun, new push)
# can hit a refusal path while the PR still carries the label from an earlier
# successful gate — that stale label is a merge-gate input, so every refusal
# below removes it (refuse()); a clean rerun re-adds it.
label_initially_present="0"
if printf '%s\n' "$pr_json" | jq -e --arg l "$label" '[.labels[]?.name | select(. == $l)] | length > 0' >/dev/null 2>&1; then
  label_initially_present="1"
fi

# Implementation branches are the ones that carry a ready-phase reviewer check
# run and a required `ready-for-regression` label (Protocol 91's label derivation
# table). Doc-stage, graduation, and release PRs are not reviewer-gated.
# `hotfix/*` is exempt from the reviewer leg — same handling as `release/*`
# (PR #1818 finding 1, round 7): `_check_release_pr_guard` in
# pr-review-loop.sh skips the reviewer loop for `release/*` AND `hotfix/*`
# head branches, so no ready-phase reviewer check run can ever exist on a
# hotfix and requiring one would permanently refuse both readiness labels
# `reviewer-check-absent`. The CI leg below still applies unchanged — that is
# the release-branch handling this mirrors.
case "$head_ref_name" in
  feature/*|fix/*|refactor/*|backport/hotfix/*) is_implementation_pr="true" ;;
  *) is_implementation_pr="false" ;;
esac

# --- 2. Ready-phase reviewer check runs for the current head ----------------
reviewer_blocking=0
verdict_blocking=0
applied_notified=0
reviewer_names_seen=""
platform=""
# Per-platform record of the first finding scan: "platform:started_at" and
# "platform:bot_login" lines, newline-separated. The pre-apply revalidation
# compares the reselected check run's timestamp against these (PR #1818
# finding 2, round 6).
first_scan_started_at=""
first_scan_bot_logins=""
scan_blocking_count=0
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
  # An empty resolved platform list would waive every reviewer gate: the
  # while loop below would run zero times and the label would apply with
  # REVIEWER_REPORT=none (PR #1818 Codex finding 1, round 4). A PR that drops
  # the ready-phase reviewer from its own `.ai-dev-workflow.yaml` must not be
  # able to un-gate its own readiness label: an empty head list is only
  # legitimate when the base branch declares no ready-phase reviewers either.
  # For implementation PRs the base-branch policy is ALWAYS fetched (an
  # unreadable one escalates `base-config-unreadable`) and the gate validates
  # the BASE policy (PR #1818 finding 3, round 6): the required reviewer set
  # is exactly what the base branch declares — pr-review-loop.sh dispatches
  # ready-phase platforms from the BASE configuration, so a head-only ADDED
  # reviewer never runs and requiring its check run would permanently refuse
  # `reviewer-check-absent`. The head cannot waive what the base requires:
  # a head that removes or replaces a base reviewer still has every base
  # platform gated (a base platform absent from the head list is required
  # regardless), so `reviewer-policy-empty` / `reviewer-check-absent` fire
  # instead of the base reviewer being dropped. Head-only additions are
  # validated only when they happen to carry a completed clean check run
  # alongside the base set; they are never required. (An explicit
  # AI_DEV_WORKFLOW_CONFIG_FILE is a deliberate override surface and is
  # trusted as resolved; no base policy is fetched there.)
  if [ -z "${AI_DEV_WORKFLOW_CONFIG_FILE:-}" ]; then
    _base_ready_platforms=""
    # loop_dispatched_base=1: apply the local review override when resolving the
    # BASE policy, the same effective-policy resolution pr-review-loop.sh uses
    # when it dispatches ready-phase platforms from the base configuration
    # (PR #1818 finding 2, round 7).
    if ! _base_ready_platforms="$(loop_dispatched_base=1 pr_head_config_ready_platforms "$repo" "$base_ref_oid" 2>/dev/null)"; then
      escalate base-config-unreadable
    fi
    if [ -z "$(printf '%s\n' "$ready_platforms" | tr -d '[:space:]')" ]; then
      # Round-4 semantics: an empty head list is a dropped reviewer, refused
      # unless the base policy is empty too (CI-only gate then applies).
      if [ -n "$(printf '%s\n' "$_base_ready_platforms" | tr -d '[:space:]')" ]; then
        result="refused"
        reason="reviewer-policy-empty"
        reviewer_report="base-declares:$(printf '%s\n' "$_base_ready_platforms" | paste -sd, -)"
        refuse "reviewer-policy-empty"
      fi
    else
      # Nonempty head list: gate on the base policy alone (see the comment
      # block above). Head-only additions are not required.
      ready_platforms="$_base_ready_platforms"
    fi
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
    refuse "reviewer-check-name-unresolved"
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
    refuse "reviewer-check-absent"
  fi
  if [ "$status_val" != "completed" ]; then
    result="refused"
    reason="reviewer-check-not-completed"
    refuse "reviewer-check-not-completed"
  fi
  # A non-success conclusion is itself a blocking verdict, even when no inline
  # finding survives classification — the loop applies the same rule. The
  # allow-list lives in reviewer_check_conclusion_is_clean (shared with the
  # pre-apply revalidation): `success` is clean, the four blocking conclusions
  # and neutral/cancelled/skipped are handled below, and ANY other non-empty
  # conclusion (e.g. `stale`) refuses fail-closed instead of falling through
  # as clean — mirrors run_ronda_review()'s default arm
  # (pr-review-loop.sh ~2894-2905).
  if ! reviewer_check_conclusion_is_clean "$conclusion"; then
    case "$conclusion" in
      failure|action_required|timed_out|startup_failure)
        verdict_blocking=$((verdict_blocking + 1))
        ;;
      neutral|cancelled|skipped) ;;
      *)
        result="refused"
        reason="reviewer-check-unknown-conclusion"
        reviewer_report="$check_name conclusion:$conclusion"
        refuse "reviewer-check-unknown-conclusion"
        ;;
    esac
  fi

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
  # The probe itself is shared (bugbot_unavailable_notice_present) with the
  # pre-apply revalidation, so a rerun that concluded `neutral` with a quota
  # notice is caught at revalidation too.
  case "$conclusion" in
    neutral|cancelled|skipped)
      if [ "$platform" = "bugbot" ] && [ -n "$bot_login" ]; then
        if bugbot_unavailable_notice_present "$bot_login" "$reviewer_started_at"; then
          result="refused"
          reason="reviewer-unavailable"
          refuse "reviewer-unavailable"
        fi
      else
        # Non-Bugbot platforms report nothing through issue comments, so a
        # `neutral`/`cancelled`/`skipped` completed run cannot be cleared by
        # any notice: the reviewer never finished a successful review. Fail
        # closed — same refusal shape as the notice path above. Mirrors
        # `run_ronda_review()`'s escalation of these conclusions
        # (pr-review-loop.sh ~2894-2905).
        result="refused"
        reason="reviewer-unavailable"
        refuse "reviewer-unavailable"
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
  # CLI and publishes no GitHub review surface). The scan itself is shared
  # (count_reviewer_blocking_findings) with the pre-apply revalidation. The
  # per-platform timestamp the first scan ran against is recorded
  # (first_scan_started_at) so the revalidation can detect a *newer* selected
  # run — one whose findings the first scan never saw (PR #1818 finding 2,
  # round 6).
  [ -n "$bot_login" ] || continue
  count_reviewer_blocking_findings "$bot_login" "$reviewer_started_at"
  reviewer_blocking=$((reviewer_blocking + scan_blocking_count))
  first_scan_started_at="${first_scan_started_at}${first_scan_started_at:+
}${platform}:${reviewer_started_at}"
  first_scan_bot_logins="${first_scan_bot_logins}${first_scan_bot_logins:+
}${platform}:${bot_login}"
done < <(printf '%s\n' "$ready_platforms")

reviewer_report="${reviewer_names_seen:-none}"

if [ "$reviewer_blocking" -gt 0 ] || [ "$verdict_blocking" -gt 0 ]; then
  result="refused"
  reason="blocking-findings"
  blocking_count="$reviewer_blocking"
  [ "$blocking_count" -ge 1 ] || blocking_count=1
  refuse "blocking-findings"
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
  refuse "ci-pending"
fi
if [ "$failing_count" -gt 0 ]; then
  result="refused"
  reason="ci-failing"
  refuse "ci-failing"
fi

# --- 4. Apply ---------------------------------------------------------------
# `--add-label` binds nothing to a commit: a push landing between the state
# read at the top and this mutation would leave every reviewer/CI verdict
# describing the old head while the label certifies the new one. Re-fetch the
# head immediately before the mutation and refuse on any drift. A *rerun*
# check is equally stale: if the reviewer check run was re-triggered on this
# same head (success → pending/failure) after the verdicts above were read,
# the verdicts describe a superseded run, and re-checking only `headRefOid`
# would apply the label from stale success data (PR #1818 finding 2, round 5).
# A failed or empty revalidation fetch escalates fail-closed as
# `revalidation-unreadable` — never success (PR #1818 finding 1, round 6) —
# and a rerun that completes between the first scan and the revalidation is
# rescanned for findings and availability notices against the newly selected
# run's timestamp, because a same-SHA rerun can conclude `success` while
# posting blocking comments (PR #1818 finding 2, round 6). The same applies
# to CI: a statusCheckRollup re-read must still satisfy the pending/failing
# rules applied at the main gate. The same conclusion→verdict logic is
# reused (reviewer_check_conclusion_is_clean) so the two gates cannot drift
# apart.
revalidate_reviewer_state() {
  local platform_arg check_name_arg check_runs_arg status_arg conclusion_arg
  local started_at_arg first_scan_login
  while IFS= read -r platform_arg; do
    [ -n "$platform_arg" ] || continue
    check_name_arg="$(reviewer_check_name_for_platform "$platform_arg")"
    [ -n "$check_name_arg" ] || continue
    # Fail closed (PR #1818 finding 1, round 6): a failed or EMPTY re-fetch of
    # the check runs cannot confirm the earlier verdict still describes this
    # head — treat it as an unreadable state, never as "unchanged" success.
    if ! check_runs_arg="$(gh api "repos/$repo/commits/$head_sha/check-runs" --paginate --slurp 2>/dev/null)" || [ -z "$check_runs_arg" ]; then
      escalate revalidation-unreadable
    fi
    if ! check_state_arg="$(printf '%s\n' "$check_runs_arg" | jq -r --arg name "$check_name_arg" '
          [ .[].check_runs[]? | select(.name == $name) ]
          | sort_by(.started_at // .completed_at // "")
          | last
          | (if . == null then " " else ((.status // "") + " " + (.conclusion // "")) end)
        ' 2>/dev/null)" || [ -z "$check_state_arg" ]; then
      escalate revalidation-unreadable
    fi
    status_arg="${check_state_arg%% *}"
    conclusion_arg="${check_state_arg#* }"
    # started_at of the reselected (latest) check run — the notice probe and
    # the finding rescan below are both time-bounded to it.
    started_at_arg="$(printf '%s\n' "$check_runs_arg" | jq -r --arg name "$check_name_arg" '
          [ .[].check_runs[]? | select(.name == $name) ]
          | sort_by(.started_at // .completed_at // "")
          | last
          | (.started_at // .completed_at // .created_at // "")
        ' 2>/dev/null)" || escalate revalidation-unreadable
    # Same conclusion classes the main gate treats as a live verdict: `success`
    # plus Bugbot's `neutral`/`cancelled`/`skipped` — for those, a Bugbot
    # availability notice at/after the run timestamp must ALSO be absent (the
    # notice probe is the same one the main gate uses, so a rerun that hit a
    # quota limit mid-window is caught here too). Non-Bugbot
    # neutral/cancelled/skipped and every other non-success conclusion mean the
    # verdict no longer reads clean, so the state is stale.
    if [ "$status_arg" != "completed" ]; then
      return 1
    fi
    case "$conclusion_arg:$platform_arg" in
      success:*) ;;
      neutral:bugbot|cancelled:bugbot|skipped:bugbot)
        if bugbot_unavailable_notice_present "$(bot_login_for_platform bugbot)" "$started_at_arg"; then
          return 1
        fi
        ;;
      *) return 1 ;;
    esac
    # Rescan guard (PR #1818 finding 2, round 6): the first scan's findings
    # may belong to a superseded run — a same-SHA rerun can conclude success
    # while posting blocking comments, and the earlier scan never saw them.
    # Even when the reselected run is the same one, comment bodies are
    # mutable, so rescan unconditionally against the selected run's
    # timestamp, reusing the same fetch + filter functions as the main gate,
    # and refuse when anything blocks.
    first_scan_login="$(printf '%s\n' "$first_scan_bot_logins" | sed -n "s/^${platform_arg}://p" | head -1)"
    if [ -n "$first_scan_login" ]; then
      count_reviewer_blocking_findings "$first_scan_login" "$started_at_arg"
      [ "$scan_blocking_count" -eq 0 ] || return 1
    fi
  done <<<"$ready_platforms"
  return 0
}

revalidate_ci_state() {
  local revalidate_pr_json normalized_arg baseline_arg pending_arg failing_arg
  if ! revalidate_pr_json="$(gh pr view "$pr_number" --repo "$repo" --json headRefOid,headRefName,baseRefOid,labels,statusCheckRollup 2>/dev/null)" || [ -z "$revalidate_pr_json" ]; then
    return 1
  fi
  normalized_arg=""
  if ! normalized_arg="$(printf '%s\n' "$revalidate_pr_json" | normalize_status_check_rollup 2>/dev/null)" || [ -z "$normalized_arg" ]; then
    return 1
  fi
  baseline_arg=""
  if ! baseline_arg="$(printf '%s\n' "$normalized_arg" | jq -c --argjson names "$(printf '%s\n' "$reviewer_names_seen" | tr ',' '\n' | jq -R . | jq -s '.')" '
        [ .[]
          | (.name // .context // .workflowName // "unknown") as $n
          | select(($names | index($n)) | not)
        ]
      ' 2>/dev/null)"; then
    return 1
  fi
  pending_arg="$(printf '%s\n' "$baseline_arg" | jq '
    [ .[] | select(
        (((.status // "") != "") and ((.status // "") != "COMPLETED"))
        or (((.state // "") | ascii_upcase) == "EXPECTED")
        or (((.state // "") | ascii_upcase) == "PENDING")
        or (((.state // "") | ascii_upcase) == "IN_PROGRESS")
        or (((.state // "") | ascii_upcase) == "QUEUED")
      ) ] | length
  ' 2>/dev/null)" || return 1
  failing_arg="$(printf '%s\n' "$baseline_arg" | jq '
    [ .[] | select(
        (((.conclusion // "") | ascii_upcase) == "FAILURE")
        or (((.conclusion // "") | ascii_upcase) == "CANCELLED")
        or (((.conclusion // "") | ascii_upcase) == "TIMED_OUT")
        or (((.conclusion // "") | ascii_upcase) == "ACTION_REQUIRED")
        or (((.conclusion // "") | ascii_upcase) == "STARTUP_FAILURE")
        or (((.state // "") | ascii_upcase) == "FAILURE")
        or (((.state // "") | ascii_upcase) == "ERROR")
      ) ] | length
  ' 2>/dev/null)" || return 1
  if [ "$failing_arg" -gt 0 ]; then
    return 1
  fi
  if [ "$pending_arg" -gt 0 ] && [ "$label" != "ready-for-regression" ]; then
    return 1
  fi
  return 0
}

current_head="$(gh pr view "$pr_number" --repo "$repo" --json headRefOid --jq '.headRefOid' 2>/dev/null)" || escalate head-revalidate-failed
if [ -z "$current_head" ]; then
  escalate head-revalidate-failed
fi
if [ "$current_head" != "$head_sha" ]; then
  refuse "head-changed-before-apply"
fi
if [ "$is_implementation_pr" = "true" ] && ! revalidate_reviewer_state; then
  refuse "reviewer-state-changed"
fi
if ! revalidate_ci_state; then
  refuse "reviewer-state-changed"
fi

# Final pre-mutation guard (PR #1818 finding 2, round 8): the two
# revalidation functions above make several API calls before the mutation,
# and a push landing DURING those calls leaves every verdict describing the
# old head while the label would certify the new one. Re-fetch headRefOid
# immediately before `gh pr edit` — after revalidation, not before — and
# refuse on any drift (removal of the label is already handled by refuse():
# the mutation has not happened). The revalidation rescan itself is repeated
# here against the same window it just validated: a same-SHA rerun that posts
# a blocking comment after the revalidation rescan (during these very calls)
# must not slip through to the mutation.
current_head="$(gh pr view "$pr_number" --repo "$repo" --json headRefOid --jq '.headRefOid' 2>/dev/null)" || escalate head-revalidate-failed
if [ -z "$current_head" ]; then
  escalate head-revalidate-failed
fi
if [ "$current_head" != "$head_sha" ]; then
  refuse "head-changed-before-apply"
fi
if [ "$is_implementation_pr" = "true" ] && ! revalidate_reviewer_state; then
  refuse "reviewer-state-changed"
fi

if ! gh pr edit "$pr_number" --repo "$repo" --add-label "$label" >/dev/null 2>&1; then
  escalate label-apply-failed
fi

# Re-read so a silently-dropped label is not reported as applied, and so a
# push that landed during the mutation is still caught: the label then
# certifies a head no verdict describes.
post_apply_json="$(gh pr view "$pr_number" --repo "$repo" --json labels,headRefOid 2>/dev/null)" || {
  # `--add-label` may have succeeded while this read failed: the label is on
  # the PR but unverified, so strip it before escalating (PR #1818 finding 3,
  # round 5) — never leave an unverified readiness label attached.
  remove_readiness_label_best_effort "$label"
  escalate label-verify-failed
}
applied_labels="$(printf '%s\n' "$post_apply_json" | jq -r '.labels[].name' 2>/dev/null)" || {
  remove_readiness_label_best_effort "$label"
  escalate label-verify-failed
}
if ! printf '%s\n' "$applied_labels" | grep -qx "$label"; then
  remove_readiness_label_best_effort "$label"
  escalate label-not-applied
fi
applied_head="$(printf '%s\n' "$post_apply_json" | jq -r '.headRefOid // ""' 2>/dev/null)" || {
  remove_readiness_label_best_effort "$label"
  escalate label-verify-failed
}
if [ "$applied_head" != "$head_sha" ]; then
  # The label now certifies a head no verdict describes. Remove it before
  # escalating so the new, unreviewed head does not carry a readiness label
  # between this refusal and whatever re-runs the gate. Best-effort only: a
  # failed removal logs a WARN and still escalates, so the human sees the
  # drift either way.
  remove_readiness_label_best_effort "$label"
  escalate head-changed-after-apply
fi

result="labeled"
reason="gate-passed"
emit_verdict
exit 0
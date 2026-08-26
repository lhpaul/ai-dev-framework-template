#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/development-workflow/pr-ci-loop.sh <pr-number> [--repo owner/repo|product-name] [--product-repo name] [--repo-root path] [--poll-interval seconds] [--max-wait seconds]

Polls GitHub required status checks for a PR until they are green, failing, or timed out.
Outputs stable key=value lines and exits with:
  0 -> green
  1 -> red
  2 -> timeout
EOF
}

if [ "$#" -lt 1 ]; then
  usage >&2
  exit 64
fi

pr_number=""
poll_interval=60
max_wait=1800
repo_selector=""
repo_root="$(workflow_repo_root)"

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
    --poll-interval)
      require_option_value "$@"
      poll_interval="$2"
      shift 2
      ;;
    --max-wait)
      require_option_value "$@"
      max_wait="$2"
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

if [ -z "$pr_number" ]; then
  usage >&2
  exit 64
fi

require_gh
cd "$repo_root"

elapsed=0
if [ -n "$repo_selector" ] && workflow_is_valid_github_repo_slug "$repo_selector"; then
  repo="$repo_selector"
elif [ -n "$repo_selector" ]; then
  repo_context="$(workflow_repository_context "$repo_selector" "$repo_root")"
  repo="$(workflow_github_repo_from_context "$repo_context")"
else
  repo="$(repo_slug)"
fi
if [ -z "$repo" ]; then
  echo "ERROR: could not resolve GitHub repository for PR CI loop; pass --repo owner/repo or --product-repo <name>." >&2
  exit 64
fi
export WORKFLOW_TARGET_GITHUB_REPO="$repo"
export GH_REPO="$repo"
min_no_checks_wait=$((poll_interval * 2))

configured_reviewer_check_names_json() {
  local config_file="${1:-}"
  local platform=""
  local -a names=()

  if [ -z "$config_file" ]; then
    config_file="$(workflow_effective_config_file 2>/dev/null || workflow_config_file)"
  fi

  if [ -f "$config_file" ]; then
    while IFS= read -r platform; do
      platform="$(printf '%s' "$platform" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [ -z "$platform" ] && continue
      case "$platform" in
        haystack)
          names+=("${HAYSTACK_CHECK_NAME:-Haystack / Review}")
          ;;
        bugbot)
          names+=("${BUGBOT_CHECK_NAME:-Cursor Bugbot}")
          ;;
      esac
    done < <(
      if [ "$config_file" = "$(workflow_config_file)" ]; then
        WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 workflow_config_review_platforms "$config_file"
      else
        workflow_config_review_platforms "$config_file"
      fi
    )
  fi

  if [ "${#names[@]}" -eq 0 ]; then
    printf '[]\n'
    return 0
  fi

  printf '%s\n' "${names[@]}" | jq -R . | jq -s .
}

# is_devin_status_stale <pr_number> <repo>
#
# Returns 0 (stale — safe to skip) when:
#   - The PR HEAD has no blocking Devin inline comments (no bot-authored inline
#     comments posted after the HEAD commit that are not prefixed with ✅), AND
#   - The PR has no Devin CHANGES_REQUESTED or blocking COMMENTED review from
#     the Devin bot for the current HEAD.
#
# Returns 1 (not stale — findings still exist) otherwise.
#
# This mirrors the Phase 1 pre-check in pr-review-loop.sh::run_devin_review()
# and is used to bypass a stale `error` Devin commit status that has not been
# refreshed since all findings were resolved (see issue #404).
is_devin_status_stale() {
  local pr_num="$1"
  local repo_slug="$2"
  local bot_login="devin-ai-integration[bot]"
  local head_sha=""
  local since_iso=""
  local blocking_count=0
  local inline_count=0
  local comment_json=""
  local review_json=""
  local body=""
  local review_state=""

  head_sha="$(gh api "repos/$repo_slug/pulls/$pr_num" --jq '.head.sha' 2>/dev/null || true)"
  if [ -z "$head_sha" ]; then
    # Cannot determine HEAD — treat as not stale (conservative).
    return 1
  fi

  since_iso="$(gh api "repos/$repo_slug/commits/$head_sha" --jq '.commit.committer.date // empty' 2>/dev/null || true)"
  if [ -z "$since_iso" ]; then
    since_iso="1970-01-01T00:00:00Z"
  fi

  # Check for blocking inline comments from Devin on the current HEAD.
  # Emit each comment body as a compact JSON object (one per line) to survive multi-line bodies.
  # Capture output first so API failures return 1 (not stale / conservative) rather than
  # silently feeding an empty string to the while loop and returning 0 (stale).
  local raw_comments=""
  raw_comments="$(
    gh api "repos/$repo_slug/pulls/$pr_num/comments" --paginate 2>/dev/null \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
          .[]
          | select(.user.login == $bot and .created_at > $since and .in_reply_to_id == null)
          | {body: (.body // "")} | @json
        '
  )" || return 1  # API or jq failure — treat as not stale (conservative)

  while IFS= read -r comment_json; do
    [ -z "${comment_json:-}" ] && continue
    body="$(printf '%s\n' "$comment_json" | jq -r '.body')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then continue; fi
    if printf '%s\n' "$body" | grep -q "^✅"; then continue; fi
    inline_count=$((inline_count + 1))
    blocking_count=$((blocking_count + 1))
  done <<< "$raw_comments"

  # Check for blocking review-level findings from Devin on the current HEAD.
  # Use "review without body" fallback (matching pr-review-loop.sh) so that
  # CHANGES_REQUESTED reviews with null bodies are never silently skipped.
  local raw_reviews=""
  raw_reviews="$(
    gh api "repos/$repo_slug/pulls/$pr_num/reviews" --paginate 2>/dev/null \
      | jq -r --arg bot "$bot_login" --arg since "$since_iso" '
          .[]
          | select(
              .user.login == $bot and
              .submitted_at > $since and
              (.state == "CHANGES_REQUESTED" or .state == "COMMENTED")
            )
          | {body: (.body // "review without body"), state: .state}
          | @json
        '
  )" || return 1  # API or jq failure — treat as not stale (conservative)

  while IFS= read -r review_json; do
    [ -z "${review_json:-}" ] && continue
    body="$(printf '%s\n' "$review_json" | jq -r '.body // ""')"
    review_state="$(printf '%s\n' "$review_json" | jq -r '.state // ""')"
    [ -z "$body" ] && continue
    if printf '%s\n' "$body" | grep -qi "No Issues Found"; then continue; fi
    if printf '%s\n' "$body" | grep -q "^✅"; then continue; fi
    # COMMENTED reviews are only blocking when the body starts with "**Devin Review**"
    # OR when there are unresolved inline comments (mirrors pr-review-loop.sh logic).
    if [ "$review_state" = "COMMENTED" ]; then
      if printf '%s\n' "$body" | grep -qi "^\\*\\*Devin Review\\*\\*"; then
        : # blocking
      elif [ "$inline_count" -gt 0 ]; then
        : # COMMENTED review with inline findings — blocking
      else
        continue  # COMMENTED review with no inline comments — not blocking
      fi
    fi
    blocking_count=$((blocking_count + 1))
  done <<< "$raw_reviews"

  if [ "$blocking_count" -gt 0 ]; then
    return 1  # still has findings — not stale
  fi
  return 0  # no findings — stale error status, safe to skip
}

# previous_head_check_names <repo> <pr_number> <current_head_sha>
# Prints the WORKFLOW names that ran on the PR's most recent EARLIER head, one
# per line (empty when the PR has a single commit or the lookup fails).
#
# Why this exists (#1514, #1580): "no failing and no pending checks" is not
# evidence that CI ran. A head can carry zero checks, or only a subset, and
# read as green:
#   - GitHub builds no merge ref for a CONFLICTING PR, so `pull_request`
#     workflows do not start at all — measured on PR #1577, where two pushes
#     after it went DIRTY ran 4 checks instead of 16 and the loop said green;
#   - a workflow whose path filter or branch filter stops matching silently
#     drops out of the set.
# Comparing against the previous head turns "a workflow that used to run is
# absent" into a red result instead of a vacuous pass.
#
# Deliberately WORKFLOW-granular, not check/job-granular (review finding on
# #1588 itself): `workflow-tests.yml` runs one job per selected suite, and the
# selected set is diff-driven (select-test-suites.sh) — it legitimately grows
# or shrinks as commits land, by design (see that workflow's own comment: "The
# matrix job names change with the selection, so they cannot be required
# directly"). Comparing individual check-run names (e.g.
# `scripts/.../tests/test-foo.sh`) would treat that expected churn as a missing
# check and block a PR that should pass — verified live: PR #1588's own head
# carries 6 such matrix leaves under one workflow, `actions/runs?head_sha=`
# collapses them to a single "workflow test harnesses" entry. Using
# `actions/runs` also naturally excludes plain commit statuses (CodeRabbit,
# Devin Review, PR-Agent's bot review) from this comparison, which is correct:
# those are not GitHub Actions workflow runs and are not what disappears when
# a PR goes CONFLICTING.
# workflow_run_names_for_sha <repo> <sha>
# Prints the distinct workflow-run names for <sha>, one per line. Returns
# non-zero when the lookup itself failed, so the caller can tell "this head
# ran no workflows" from "we do not know what it ran" — a gate that exists to
# stop a false green must not be satisfied by its own lookup erroring out.
#
# --slurp is required with --paginate: without it jq runs per page, so a
# multi-page response yields one result per page instead of one aggregate.
workflow_run_names_for_sha() {
  local repo="$1" sha="$2"
  [ -n "$sha" ] || return 1
  gh api "repos/$repo/actions/runs?head_sha=$sha&per_page=100" --paginate --slurp 2>/dev/null \
    | jq -r '[.[].workflow_runs[]?.name] | unique | .[]'
}

# previous_head_check_names <repo> <pr_number> <current_head_sha>
# Prints the previous head's workflow-run names. Exit 0 with no output means
# "no previous head" (single-commit PR, or the same SHA); exit 1 means the
# lookup failed and the expectation is unknown.
previous_head_check_names() {
  local repo="$1" pr_number="$2" current_sha="$3" prev_sha=""
  # --slurp: with --paginate alone, `.[-2]` is evaluated per page, so a PR
  # with more than one page of commits emits one SHA per page.
  prev_sha="$(
    gh api "repos/$repo/pulls/$pr_number/commits?per_page=100" --paginate --slurp 2>/dev/null \
      | jq -r '[.[][].sha] | .[-2] // empty'
  )" || return 1
  [ -n "$prev_sha" ] || return 0
  [ "$prev_sha" != "$current_sha" ] || return 0
  workflow_run_names_for_sha "$repo" "$prev_sha"
}

while :; do
  if ! head_sha="$(gh pr view "$pr_number" --repo "$repo" --json headRefOid --jq '.headRefOid' 2>/dev/null)"; then
    head_sha=""
  fi
  # Only a real object name identifies a head. Anything else (an older gh, a
  # harness whose stub ignores --jq) means the head is UNKNOWN, which is a
  # different thing from "the run lookup failed" below: the evidence gate
  # simply cannot apply, so it is skipped and the result is marked
  # CI_EVIDENCE=unknown for the readiness gate to refuse.
  case "$head_sha" in
    *[!0-9a-fA-F]*|"") head_sha="" ;;
    *) [ "${#head_sha}" -ge 7 ] || head_sha="" ;;
  esac
  if ! checks_json="$(gh pr view "$pr_number" --repo "$repo" --json statusCheckRollup 2>/dev/null)"; then
    print_kv RESULT red
    print_kv PR_NUMBER "$pr_number"
    print_kv REPO "$repo"
    print_kv REASON pr_status_fetch_failed
    print_kv TOTAL_CHECK_COUNT 0
    print_kv FAILING_CHECK_COUNT 1
    print_kv FAILING_CHECKS pr_status_fetch_failed
    print_kv PENDING_CHECK_COUNT 0
    print_kv PENDING_CHECKS ""
    print_kv REVIEWER_CHECK_COUNT 0
    print_kv REVIEWER_CHECKS ""
    print_kv REVIEWER_CHECKS_JSON "[]"
    exit 1
  fi
  # statusCheckRollup can include historical duplicates for the same check.
  # Keep only the latest entry per check name to avoid stale conclusions.
  if ! normalized_checks_json="$(
    printf '%s\n' "$checks_json" | jq '
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
    '
  )"; then
    print_kv RESULT red
    print_kv PR_NUMBER "$pr_number"
    print_kv REPO "$repo"
    print_kv REASON check_json_parse_failed
    print_kv TOTAL_CHECK_COUNT 0
    print_kv FAILING_CHECK_COUNT 1
    print_kv FAILING_CHECKS check_json_parse_failed
    print_kv PENDING_CHECK_COUNT 0
    print_kv PENDING_CHECKS ""
    print_kv REVIEWER_CHECK_COUNT 0
    print_kv REVIEWER_CHECKS ""
    print_kv REVIEWER_CHECKS_JSON "[]"
    exit 1
  fi
  reviewer_check_names="$(
    configured_reviewer_check_names_json ""
  )"
  if ! ci_checks_json="$(
    printf '%s\n' "$normalized_checks_json" | jq --argjson reviewer_names "$reviewer_check_names" '
      [
        .[]
        | select(
            (.name // .context // .workflowName // "unknown") as $check_name
            | ($reviewer_names | index($check_name) | not)
          )
      ]
    '
  )"; then
    print_kv RESULT red
    print_kv PR_NUMBER "$pr_number"
    print_kv REPO "$repo"
    print_kv REASON check_json_parse_failed
    print_kv TOTAL_CHECK_COUNT 0
    print_kv FAILING_CHECK_COUNT 1
    print_kv FAILING_CHECKS check_json_parse_failed
    print_kv PENDING_CHECK_COUNT 0
    print_kv PENDING_CHECKS ""
    print_kv REVIEWER_CHECK_COUNT 0
    print_kv REVIEWER_CHECKS ""
    print_kv REVIEWER_CHECKS_JSON "[]"
    exit 1
  fi
  reviewer_check_count="$(
    printf '%s\n' "$normalized_checks_json" | jq --argjson reviewer_names "$reviewer_check_names" '
      [
        .[]
        | select(
            (.name // .context // .workflowName // "unknown") as $check_name
            | ($reviewer_names | index($check_name))
          )
      ]
      | length
    '
  )"
  reviewer_check_list="$(
    printf '%s\n' "$normalized_checks_json" | jq -r --argjson reviewer_names "$reviewer_check_names" '
      [
        .[]
        | select(
            (.name // .context // .workflowName // "unknown") as $check_name
            | ($reviewer_names | index($check_name))
          )
        | (.name // .context // .workflowName // "unknown")
      ]
      | join(",")
    '
  )"
  reviewer_checks_json="$(
    printf '%s\n' "$normalized_checks_json" | jq -c --argjson reviewer_names "$reviewer_check_names" --arg pr_number "$pr_number" '
      [
        .[]
        | (.name // .context // .workflowName // "unknown") as $check_name
        | select($reviewer_names | index($check_name))
        | {
            name: $check_name,
            provider: $check_name,
            status: (.status // ""),
            conclusion: (.conclusion // ""),
            state: (.state // ""),
            detailsUrl: (.detailsUrl // .details_url // .targetUrl // .target_url // ""),
            startedAt: (.startedAt // ""),
            completedAt: (.completedAt // ""),
            createdAt: (.createdAt // ""),
            pullRequest: ($pr_number | tonumber? // $pr_number)
          }
      ]
    '
  )"
  total_check_count="$(
    printf '%s\n' "$ci_checks_json" | jq 'length'
  )"
  pending_count="$(
    printf '%s\n' "$ci_checks_json" | jq '
      .
      | map(select(
          ((.status // "") != "" and (.status != "COMPLETED"))
          or (.state == "EXPECTED")
          or (.state == "PENDING")
          or (.state == "IN_PROGRESS")
          or (.state == "QUEUED")
        ))
      | length
    '
  )"
  pending_list="$(
    printf '%s\n' "$ci_checks_json" | jq -r '
      .
      | map(select(
          ((.status // "") != "" and (.status != "COMPLETED"))
          or (.state == "EXPECTED")
          or (.state == "PENDING")
          or (.state == "IN_PROGRESS")
          or (.state == "QUEUED")
        ))
      | map(.name // .context // .workflowName // "unknown")
      | join(",")
    '
  )"
  failing_count="$(
    printf '%s\n' "$ci_checks_json" | jq '
      .
      | map(select(
          (.conclusion == "FAILURE")
          or (.conclusion == "CANCELLED")
          or (.conclusion == "TIMED_OUT")
          or (.conclusion == "ACTION_REQUIRED")
          or (.conclusion == "STARTUP_FAILURE")
          or (.state == "FAILURE")
          or (.state == "ERROR")
        ))
      | length
    '
  )"
  failing_list="$(
    printf '%s\n' "$ci_checks_json" | jq -r '
      .
      | map(select(
          (.conclusion == "FAILURE")
          or (.conclusion == "CANCELLED")
          or (.conclusion == "TIMED_OUT")
          or (.conclusion == "ACTION_REQUIRED")
          or (.conclusion == "STARTUP_FAILURE")
          or (.state == "FAILURE")
          or (.state == "ERROR")
        ))
      | map(.name // .context // .workflowName // "unknown")
      | join(",")
    '
  )"

  # --- Stale Devin error status bypass ---
  # When all failing checks are Devin commit-status contexts in state=ERROR,
  # and no blocking Devin review findings exist for the current PR HEAD, the
  # `error` status is stale (Devin has not re-run since findings were resolved).
  # In that case, treat Devin's error as green so the CI loop is not blocked
  # waiting for a manual re-trigger. A diagnostic line is emitted instead.
  #
  # Only activates when every failing check is a Devin-pattern status context.
  # Any non-Devin failure still causes the loop to report red as usual.
  if [ "$failing_count" -gt 0 ]; then
    devin_error_count="$(
      printf '%s\n' "$normalized_checks_json" | jq '
        .
        | map(select(
            .state == "ERROR" and
            ((.context // "") | test("devin"; "i"))
          ))
        | length
      '
    )"
    if [ "$devin_error_count" -gt 0 ] && [ "$devin_error_count" -eq "$failing_count" ]; then
      # All failures are Devin error contexts. Check whether the error is stale.
      if is_devin_status_stale "$pr_number" "$repo"; then
        echo "INFO: Devin commit status is ERROR but no blocking Devin review findings exist for the current HEAD. Treating as stale — bypassing Devin error check." >&2
        failing_count=0
        failing_list=""
      fi
    fi
  fi

  if [ "$failing_count" -gt 0 ]; then
    print_kv RESULT red
    print_kv PR_NUMBER "$pr_number"
    print_kv REPO "$repo"
    print_kv TOTAL_CHECK_COUNT "$total_check_count"
    print_kv FAILING_CHECK_COUNT "$failing_count"
    print_kv FAILING_CHECKS "$failing_list"
    print_kv PENDING_CHECK_COUNT "$pending_count"
    print_kv PENDING_CHECKS "$pending_list"
    print_kv REVIEWER_CHECK_COUNT "$reviewer_check_count"
    print_kv REVIEWER_CHECKS "$reviewer_check_list"
    print_kv REVIEWER_CHECKS_JSON "$reviewer_checks_json"
    exit 1
  fi

  if [ "$pending_count" -eq 0 ]; then
    if [ "$total_check_count" -eq 0 ] && [ "$elapsed" -lt "$min_no_checks_wait" ]; then
      sleep "$poll_interval"
      elapsed=$((elapsed + poll_interval))
      continue
    fi

    # CI-evidence gate (#1514, #1580): green must mean "the checks that belong
    # on this head ran and passed", not "nothing failed". Compare the current
    # head's WORKFLOW names (not job/check names — see previous_head_check_names)
    # against the PR's previous head; a whole workflow that ran before and is
    # absent now is reported rather than silently accepted.
    missing_checks=""
    evidence_lookup_failed=0
    if [ -n "$head_sha" ] && [ "${CI_LOOP_SKIP_EVIDENCE_GATE:-0}" != "1" ]; then
      # Both sides come from actions/runs so the comparison is symmetric: the
      # rollup also carries plain commit statuses (CodeRabbit, Devin) and
      # per-job matrix leaves, which have no counterpart in the previous head's
      # workflow-run list and would make the two sets incomparable.
      prev_names=""
      if ! current_names="$(workflow_run_names_for_sha "$repo" "$head_sha")"; then
        evidence_lookup_failed=1
      elif ! prev_names="$(previous_head_check_names "$repo" "$pr_number" "$head_sha")"; then
        evidence_lookup_failed=1
      else
        while IFS= read -r prev_name; do
          [ -n "$prev_name" ] || continue
          if ! printf '%s\n' "$current_names" | grep -Fxq "$prev_name"; then
            missing_checks="${missing_checks:+$missing_checks,}$prev_name"
          fi
        done <<< "$prev_names"
      fi
    fi
    if [ "$evidence_lookup_failed" -eq 1 ]; then
      # Fail closed: a gate that exists to stop a false green must not be
      # satisfied by its own lookup failing (CodeRabbit on PR #1588).
      print_kv RESULT red
      print_kv PR_NUMBER "$pr_number"
      print_kv REPO "$repo"
      print_kv HEAD_SHA "$head_sha"
      print_kv REASON ci_evidence_lookup_failed
      print_kv CI_EVIDENCE unknown
      print_kv TOTAL_CHECK_COUNT "$total_check_count"
      print_kv FAILING_CHECK_COUNT 0
      print_kv FAILING_CHECKS ""
      print_kv PENDING_CHECK_COUNT 0
      print_kv PENDING_CHECKS ""
      print_kv REVIEWER_CHECK_COUNT "$reviewer_check_count"
      print_kv REVIEWER_CHECKS "$reviewer_check_list"
      print_kv REVIEWER_CHECKS_JSON "$reviewer_checks_json"
      echo "ERROR: could not read workflow-run evidence for $head_sha; refusing to report green on an unverified head." >&2
      echo "  Retry, or set CI_LOOP_SKIP_EVIDENCE_GATE=1 to proceed without the check." >&2
      exit 1
    fi
    if [ -n "$missing_checks" ]; then
      print_kv RESULT red
      print_kv PR_NUMBER "$pr_number"
      print_kv REPO "$repo"
      print_kv HEAD_SHA "$head_sha"
      print_kv REASON expected_checks_missing
      print_kv TOTAL_CHECK_COUNT "$total_check_count"
      print_kv FAILING_CHECK_COUNT 0
      print_kv FAILING_CHECKS ""
      print_kv MISSING_CHECKS "$missing_checks"
      print_kv PENDING_CHECK_COUNT 0
      print_kv PENDING_CHECKS ""
      print_kv REVIEWER_CHECK_COUNT "$reviewer_check_count"
      print_kv REVIEWER_CHECKS "$reviewer_check_list"
      print_kv REVIEWER_CHECKS_JSON "$reviewer_checks_json"
      echo "ERROR: workflow(s) that ran on the PR's previous head are absent on $head_sha: $missing_checks" >&2
      echo "  A conflicting PR gets no pull_request workflows at all; resolve the conflict (or the filter change) and let CI re-run." >&2
      exit 1
    fi
    if [ -z "$head_sha" ]; then
      print_kv CI_EVIDENCE unknown
      echo "WARNING: could not resolve the PR head SHA; the CI-evidence comparison did not run." >&2
    elif [ "$total_check_count" -eq 0 ]; then
      print_kv CI_EVIDENCE none
      echo "WARNING: no checks ran on $head_sha; 'green' here means 'nothing failed', not 'CI passed'." >&2
    else
      print_kv CI_EVIDENCE present
    fi

    print_kv HEAD_SHA "$head_sha"
    print_kv RESULT green
    print_kv PR_NUMBER "$pr_number"
    print_kv REPO "$repo"
    print_kv TOTAL_CHECK_COUNT "$total_check_count"
    print_kv FAILING_CHECK_COUNT 0
    print_kv FAILING_CHECKS ""
    print_kv PENDING_CHECK_COUNT 0
    print_kv PENDING_CHECKS ""
    print_kv REVIEWER_CHECK_COUNT "$reviewer_check_count"
    print_kv REVIEWER_CHECKS "$reviewer_check_list"
    print_kv REVIEWER_CHECKS_JSON "$reviewer_checks_json"
    exit 0
  fi

  if [ "$elapsed" -ge "$max_wait" ]; then
    print_kv RESULT timeout
    print_kv PR_NUMBER "$pr_number"
    print_kv REPO "$repo"
    print_kv TOTAL_CHECK_COUNT "$total_check_count"
    print_kv FAILING_CHECK_COUNT "$failing_count"
    print_kv FAILING_CHECKS "$failing_list"
    print_kv PENDING_CHECK_COUNT "$pending_count"
    print_kv PENDING_CHECKS "$pending_list"
    print_kv REVIEWER_CHECK_COUNT "$reviewer_check_count"
    print_kv REVIEWER_CHECKS "$reviewer_check_list"
    print_kv REVIEWER_CHECKS_JSON "$reviewer_checks_json"
    exit 2
  fi

  sleep "$poll_interval"
  elapsed=$((elapsed + poll_interval))
done

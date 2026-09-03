#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/item-completion-self-check.sh \
    --issue <issue> --branch <branch> --stage <stage> --worktree-path <path> \
    [--repo-root <path>] [--pr <number>] [--expected-base <branch>] \
    [--expected-label <label>] [--forbid-label <label>] \
    [--require-clean true|false] [--require-ci-green true|false] \
    [--require-review-summary true|false] [--require-review-threads true|false] \
    [--tracker-required true|false] [--expected-tracker-status <status>] \
    [--changed-file-prefix <prefix>] [--claim <name|required|evidence>]

Prints a stable Markdown section headed "## Ground-Truth Completion Verification".
Rows are marked verified, not_applicable, unavailable_optional,
unavailable_required, or discrepancy. Any discrepancy or unavailable_required
surface exits non-zero.

For tests or constrained runners, WORKFLOW_SELF_CHECK_TRACKER_STATUS can provide
the tracker status directly. Set it to __FAIL__ to simulate an unavailable
tracker read.
EOF
}

require_option_value() {
  local option="$1"
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
    echo "$option requires a value." >&2
    usage >&2
    exit 64
  fi
}

issue=""
expected_branch=""
stage=""
worktree_path=""
repo_root=""
pr_number=""
expected_base=""
require_clean="true"
require_ci_green="true"
require_review_summary="false"
require_review_threads="false"
tracker_required="false"
expected_tracker_status=""
changed_file_prefix=""
expected_labels=()
forbidden_labels=()
claims=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --issue)
      require_option_value "$@"
      issue="$2"
      shift 2
      ;;
    --branch)
      require_option_value "$@"
      expected_branch="$2"
      shift 2
      ;;
    --stage)
      require_option_value "$@"
      stage="$2"
      shift 2
      ;;
    --worktree-path)
      require_option_value "$@"
      worktree_path="$2"
      shift 2
      ;;
    --repo-root)
      require_option_value "$@"
      repo_root="$2"
      shift 2
      ;;
    --pr)
      require_option_value "$@"
      pr_number="$2"
      shift 2
      ;;
    --expected-base)
      require_option_value "$@"
      expected_base="$2"
      shift 2
      ;;
    --expected-label)
      require_option_value "$@"
      expected_labels+=("$2")
      shift 2
      ;;
    --forbid-label)
      require_option_value "$@"
      forbidden_labels+=("$2")
      shift 2
      ;;
    --require-clean)
      require_option_value "$@"
      require_clean="$2"
      shift 2
      ;;
    --require-ci-green)
      require_option_value "$@"
      require_ci_green="$2"
      shift 2
      ;;
    --require-review-summary)
      require_option_value "$@"
      require_review_summary="$2"
      shift 2
      ;;
    --require-review-threads)
      require_option_value "$@"
      require_review_threads="$2"
      shift 2
      ;;
    --tracker-required)
      require_option_value "$@"
      tracker_required="$2"
      shift 2
      ;;
    --expected-tracker-status)
      require_option_value "$@"
      expected_tracker_status="$2"
      tracker_required="true"
      shift 2
      ;;
    --changed-file-prefix)
      require_option_value "$@"
      changed_file_prefix="$2"
      shift 2
      ;;
    --claim)
      require_option_value "$@"
      claims+=("$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

is_true() {
  case "${1:-}" in
    true|1|yes) return 0 ;;
    false|0|no|"") return 1 ;;
    *)
      echo "Boolean option must be true or false, got '$1'." >&2
      exit 64
      ;;
  esac
}

validate_bool_option() {
  local option="$1"
  local value="$2"
  case "${value:-}" in
    true|1|yes|false|0|no|"") ;;
    *)
      echo "$option must be true or false, got '$value'." >&2
      exit 64
      ;;
  esac
}

if [ -z "$issue" ] || [ -z "$expected_branch" ] || [ -z "$stage" ] || [ -z "$worktree_path" ]; then
  usage >&2
  exit 64
fi

validate_bool_option "--require-clean" "$require_clean"
validate_bool_option "--require-ci-green" "$require_ci_green"
validate_bool_option "--require-review-summary" "$require_review_summary"
validate_bool_option "--require-review-threads" "$require_review_threads"
validate_bool_option "--tracker-required" "$tracker_required"

if [ -z "$repo_root" ]; then
  repo_root="$worktree_path"
fi

rows=()
failure_count=0
discrepancy_count=0
unavailable_required_count=0

md_escape() {
  printf '%s' "${1:-}" | tr '\n' ' ' | sed 's/|/\\|/g; s/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//'
}

add_row() {
  local surface="$1"
  local result="$2"
  local observed="$3"
  local evidence="$4"
  rows+=("| $(md_escape "$surface") | $(md_escape "$result") | $(md_escape "$observed") | $(md_escape "$evidence") |")
  case "$result" in
    discrepancy)
      discrepancy_count=$((discrepancy_count + 1))
      failure_count=$((failure_count + 1))
      ;;
    unavailable_required)
      unavailable_required_count=$((unavailable_required_count + 1))
      failure_count=$((failure_count + 1))
      ;;
  esac
}

json_field() {
  local json="$1"
  local filter="$2"
  local output=""
  if ! output="$(printf '%s\n' "$json" | jq -r "$filter" 2>&1)"; then
    printf '%s\n' "$output"
    return 1
  fi
  printf '%s\n' "$output"
}

bot_login_for_platform() {
  case "$1" in
    coderabbit) printf 'coderabbitai\n' ;;
    devin) printf 'devin-ai-integration\n' ;;
    greptile) printf 'greptile-apps\n' ;;
    haystack) printf '%s\n' "${HAYSTACK_BOT_LOGIN:-haystack[bot]}" ;;
    codex-github) printf '%s\n' "${CODEX_GITHUB_BOT_LOGIN:-chatgpt-codex-connector[bot]}" ;;
    claude-code-action) printf '%s\n' "${CLAUDE_CODE_ACTION_BOT_LOGIN:-claude[bot]}" ;;
    copilot) printf '%s\n' "${COPILOT_BOT_LOGIN:-copilot-pull-request-reviewer[bot]}" ;;
    bugbot) printf '%s\n' "${BUGBOT_BOT_LOGIN:-cursor[bot]}" ;;
    *) printf '\n' ;;
  esac
}

thread_bot_login_variants() {
  local bot_login="$1"
  [ -n "$bot_login" ] || return 0

  printf '%s\n' "$bot_login"
  case "$bot_login" in
    *"[bot]") printf '%s\n' "${bot_login%"[bot]"}" ;;
    *) printf '%s[bot]\n' "$bot_login" ;;
  esac
}

configured_review_platforms() {
  local config_file="$1"

  if [ "$config_file" = "$(workflow_config_file)" ]; then
    WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES=1 workflow_config_review_platforms "$config_file"
  else
    workflow_config_review_platforms "$config_file"
  fi
}

configured_thread_bot_logins_json() {
  local config_file=""
  local platform=""
  local bot_login=""
  local -a bot_logins=()

  config_file="$(workflow_effective_config_file)"
  while IFS= read -r platform; do
    [ -n "$platform" ] || continue
    bot_login="$(bot_login_for_platform "$platform")"
    [ -n "$bot_login" ] || continue
    while IFS= read -r bot_login_variant; do
      [ -n "$bot_login_variant" ] || continue
      bot_logins+=("$bot_login_variant")
    done < <(thread_bot_login_variants "$bot_login")
  done < <(configured_review_platforms "$config_file")

  if [ "${#bot_logins[@]}" -eq 0 ]; then
    printf '[]\n'
    return 0
  fi

  printf '%s\n' "${bot_logins[@]}" | jq -R . | jq -s 'unique'
}

fetch_review_threads_json() {
  local owner="$1"
  local name="$2"
  local number="$3"
  local cursor=""
  local response=""
  local combined="[]"
  local nodes=""
  local has_next=""
  local end_cursor=""
  local query='
    query($owner: String!, $name: String!, $number: Int!, $cursor: String) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          reviewThreads(first: 100, after: $cursor) {
            nodes { isResolved isOutdated comments(first: 1) { nodes { databaseId author { login } body } } }
            pageInfo { hasNextPage endCursor }
          }
        }
      }
    }'

  while :; do
    if [ -n "$cursor" ]; then
      response="$(gh api graphql -F owner="$owner" -F name="$name" -F number="$number" -F cursor="$cursor" -f query="$query" 2>&1)" || {
        printf '%s\n' "$response"
        return 1
      }
    else
      response="$(gh api graphql -F owner="$owner" -F name="$name" -F number="$number" -f query="$query" 2>&1)" || {
        printf '%s\n' "$response"
        return 1
      }
    fi

    nodes="$(printf '%s\n' "$response" | jq -c '.data.repository.pullRequest.reviewThreads.nodes // []' 2>&1)" || {
      printf '%s\n' "$nodes"
      return 1
    }
    combined="$(jq -c --argjson existing "$combined" --argjson nodes "$nodes" '$existing + $nodes' <<< '{}')" || return 1

    has_next="$(printf '%s\n' "$response" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.hasNextPage // false' 2>&1)" || {
      printf '%s\n' "$has_next"
      return 1
    }
    [ "$has_next" = "true" ] || break

    end_cursor="$(printf '%s\n' "$response" | jq -r '.data.repository.pullRequest.reviewThreads.pageInfo.endCursor // ""' 2>&1)" || {
      printf '%s\n' "$end_cursor"
      return 1
    }
    if [ -z "$end_cursor" ] || [ "$end_cursor" = "null" ]; then
      printf 'reviewThreads pagination reported hasNextPage=true without endCursor\n'
      return 1
    fi
    cursor="$end_cursor"
  done

  printf '%s\n' "$combined"
}

fetch_latest_review_summary() {
  local repo="$1"
  local number="$2"
  local records=""
  local latest=""

  records="$(gh api "repos/$repo/issues/$number/comments" --paginate --jq '
    .[]
    | select((.body // "") | test("Automated Reviewer Loop Summary|Reviewer Loop Summary|No blocking PR feedback"))
    | {body: (.body // ""), updated_at: (.updated_at // ""), created_at: (.created_at // "")}
  ' 2>&1)" || {
    printf '%s\n' "$records"
    return 1
  }

  latest="$(printf '%s\n' "$records" | jq -s -r 'sort_by(.updated_at // .created_at // "") | last | .body // ""' 2>&1)" || {
    printf '%s\n' "$latest"
    return 1
  }

  printf '%s\n' "$latest"
}

extract_reviewer_loop_history_json() {
  awk '
    index($0, "<!-- reviewer-loop-history:v1 -->") > 0 {
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

local_ai_reviewer_configured() {
  local config_file
  local platform

  config_file="$(workflow_effective_config_file)"
  while IFS= read -r platform; do
    [ "$platform" = "local-ai-reviewer" ] && return 0
  done < <(configured_review_platforms "$config_file")
  return 1
}

fetch_unreplied_rest_review_comments_count() {
  local repo="$1"
  local number="$2"
  local bot_logins_json="$3"
  local graph_thread_comment_ids_json="$4"
  local result=""

  result="$(
    gh api "repos/$repo/pulls/$number/comments" --paginate 2>/dev/null \
      | jq -s --argjson botLogins "$bot_logins_json" --argjson graphThreadCommentIds "$graph_thread_comment_ids_json" '
          [ .[][]? ] as $comments
          | (
              [
                $comments[]
                | select(
                    .in_reply_to_id != null and
                    (.user.login as $author | ($botLogins | index($author)) == null) and
                    ((.user.login // "") | test("\\[bot\\]$") | not)
                  )
                | .in_reply_to_id
              ]
              | unique
            ) as $human_replied_ids
          | [
              $comments[]
              | select(.in_reply_to_id == null)
              | select((.body // "") | contains("✅ Addressed") | not)
              | select(.user.login as $author | ($botLogins | index($author)) != null)
              | select(.id as $id | ($human_replied_ids | index($id)) == null)
              | select(.id as $id | ($graphThreadCommentIds | index($id)) == null)
            ]
          | length
        '
  )" || {
    printf '%s\n' "$result"
    return 1
  }

  printf '%s\n' "${result:-0}"
}

reviewer_check_name_for_platform() {
  case "$1" in
    haystack) printf '%s\n' "${HAYSTACK_CHECK_NAME:-Haystack / Review}" ;;
    bugbot) printf '%s\n' "${BUGBOT_CHECK_NAME:-Cursor Bugbot}" ;;
    *) printf '\n' ;;
  esac
}

reviewer_check_names_json() {
  local config_file=""
  local platform=""
  local check_name=""
  local -a check_names=()

  config_file="$(workflow_effective_config_file)"
  while IFS= read -r platform; do
    [ -n "$platform" ] || continue
    check_name="$(reviewer_check_name_for_platform "$platform")"
    [ -n "$check_name" ] || continue
    check_names+=("$check_name")
  done < <(configured_review_platforms "$config_file")

  if [ "${#check_names[@]}" -eq 0 ]; then
    printf '[]\n'
    return 0
  fi

  printf '%s\n' "${check_names[@]}" | jq -R . | jq -s 'unique'
}

# worktree_path_for_branch <branch> <git-worktree-list---porcelain-output>
#
# Parses `git worktree list --porcelain` output and prints the worktree path
# whose checked-out branch is <branch>, or nothing if no linked worktree has
# that branch checked out. `git worktree list` enumerates every worktree
# linked to the repository regardless of which one it is invoked from, so
# this works even when $repo_root/$worktree_path is the wrong path.
worktree_path_for_branch() {
  local branch="$1"
  local list_output="$2"
  printf '%s\n' "$list_output" | awk -v want="refs/heads/$branch" '
    /^worktree / { path = substr($0, 10) }
    /^branch / { if ($0 == "branch " want) { print path; exit } }
  '
}

cd "$repo_root"

resolved_repo_root="$(pwd -P)"
resolved_worktree_path="$(CDPATH='' cd -- "$worktree_path" 2>/dev/null && pwd -P || printf '%s' "$worktree_path")"

worktree_list=""
worktree_list_available="true"
if ! worktree_list="$(git worktree list --porcelain 2>&1)"; then
  worktree_list_available="false"
fi

# Detect the "caller passed the wrong --worktree-path" pattern: the expected
# branch IS checked out somewhere in this repository's worktrees, just not at
# the path the caller supplied (e.g. the main clone instead of the actual
# item worktree, or a sibling item's worktree). When true, a branch mismatch
# below is a caller path error, not evidence of branch contamination, and
# gets its own distinct diagnostic row instead of being folded into the
# generic repository.branch discrepancy.
expected_branch_worktree_path=""
resolved_expected_branch_worktree_path=""
caller_worktree_path_mismatch="false"
if [ "$worktree_list_available" = "true" ]; then
  expected_branch_worktree_path="$(worktree_path_for_branch "$expected_branch" "$worktree_list")"
  if [ -n "$expected_branch_worktree_path" ]; then
    resolved_expected_branch_worktree_path="$(CDPATH='' cd -- "$expected_branch_worktree_path" 2>/dev/null && pwd -P || printf '%s' "$expected_branch_worktree_path")"
    if [ "$resolved_expected_branch_worktree_path" != "$resolved_worktree_path" ]; then
      caller_worktree_path_mismatch="true"
    fi
  fi
fi

current_branch=""
returned_to_expected_base="false"
if current_branch="$(git rev-parse --abbrev-ref HEAD 2>&1)"; then
  if [ -n "$pr_number" ] && [ -n "$expected_base" ] && [ "$current_branch" = "$expected_base" ]; then
    returned_to_expected_base="true"
  fi
  if [ "$current_branch" = "$expected_branch" ]; then
    add_row "repository.branch" "verified" "$current_branch" "git rev-parse --abbrev-ref HEAD"
  elif is_true "$returned_to_expected_base"; then
    add_row "repository.branch" "verified" "$current_branch" "local checkout returned to expected base; PR head check verifies item branch"
  else
    add_row "repository.branch" "discrepancy" "expected=$expected_branch observed=$current_branch" "git rev-parse --abbrev-ref HEAD"
    if [ "$caller_worktree_path_mismatch" = "true" ]; then
      add_row "caller.worktree_path" "discrepancy" "expected branch $expected_branch is checked out at $resolved_expected_branch_worktree_path, not the supplied --worktree-path $resolved_worktree_path; re-run this check with --worktree-path $resolved_expected_branch_worktree_path" "git worktree list --porcelain"
    fi
  fi
else
  add_row "repository.branch" "unavailable_required" "$current_branch" "git rev-parse --abbrev-ref HEAD"
fi

head_sha=""
if head_sha="$(git rev-parse --short HEAD 2>&1)" && [ -n "$head_sha" ]; then
  add_row "repository.head" "verified" "$head_sha" "git rev-parse --short HEAD"
else
  add_row "repository.head" "unavailable_required" "unable to read HEAD" "$head_sha"
fi

if [ "$resolved_repo_root" = "$resolved_worktree_path" ]; then
  add_row "workspace.path" "verified" "$resolved_worktree_path" "pwd -P"
else
  add_row "workspace.path" "discrepancy" "expected=$resolved_worktree_path observed=$resolved_repo_root" "pwd -P"
fi

status_short=""
if status_short="$(git status --short 2>&1)"; then
  if [ -z "$status_short" ]; then
    add_row "workspace.status" "verified" "clean" "git status --short"
  elif is_true "$require_clean"; then
    add_row "workspace.status" "discrepancy" "$status_short" "git status --short"
  else
    add_row "workspace.status" "verified" "$status_short" "git status --short (dirty allowed)"
  fi
else
  add_row "workspace.status" "unavailable_required" "$status_short" "git status --short"
fi

if [ "$worktree_list_available" = "true" ]; then
  if printf '%s\n' "$worktree_list" | grep -Fq "branch refs/heads/$expected_branch"; then
    add_row "workspace.worktrees" "verified" "expected branch present; path=$resolved_worktree_path" "git worktree list --porcelain"
  elif is_true "$returned_to_expected_base"; then
    add_row "workspace.worktrees" "verified" "local checkout returned to expected base; PR head check verifies item branch" "git worktree list --porcelain"
  else
    add_row "workspace.worktrees" "discrepancy" "expected branch $expected_branch not found in worktree list" "git worktree list --porcelain"
  fi
else
  add_row "workspace.worktrees" "unavailable_required" "$worktree_list" "git worktree list --porcelain"
fi

if [ -n "$pr_number" ]; then
  pr_repo=""
  if ! pr_repo="$(repo_slug 2>&1)"; then
    add_row "pull_request" "unavailable_required" "$pr_repo" "repo_slug"
  elif pr_json="$(gh pr view "$pr_number" --repo "$pr_repo" --json number,baseRefName,headRefName,headRefOid,isDraft,labels,files,statusCheckRollup,comments 2>&1)"; then
    if ! command -v jq >/dev/null 2>&1; then
      add_row "pull_request" "unavailable_required" "jq not found" "jq is required to parse gh pr view JSON"
    elif ! printf '%s\n' "$pr_json" | jq -e . >/dev/null 2>&1; then
      add_row "pull_request" "unavailable_required" "invalid JSON from gh pr view" "gh pr view $pr_number"
    elif ! pr_head="$(json_field "$pr_json" '.headRefName')" \
      || ! pr_base="$(json_field "$pr_json" '.baseRefName')" \
      || ! pr_head_oid="$(json_field "$pr_json" '.headRefOid // ""')" \
      || ! pr_draft="$(json_field "$pr_json" '.isDraft')" \
      || ! pr_labels="$(json_field "$pr_json" '[(.labels // [])[].name] | join(",")')" \
      || ! pr_files="$(json_field "$pr_json" '[(.files // [])[].path] | join(",")')"; then
      add_row "pull_request" "unavailable_required" "failed to parse PR JSON fields" "gh pr view $pr_number --json ..."
    else

      if [ "$pr_head" = "$expected_branch" ]; then
        add_row "pull_request.head" "verified" "$pr_head" "gh pr view $pr_number --json headRefName"
      else
        add_row "pull_request.head" "discrepancy" "expected=$expected_branch observed=$pr_head" "gh pr view $pr_number --json headRefName"
      fi

      if [ -n "$pr_head_oid" ] && [ "$current_branch" = "$expected_branch" ]; then
        local_head_oid="$(git rev-parse HEAD 2>&1)" || local_head_oid=""
        if [ "$local_head_oid" = "$pr_head_oid" ]; then
          add_row "repository.head.pr_tip" "verified" "${head_sha:-$local_head_oid}" "git rev-parse HEAD matches gh pr view headRefOid"
        else
          add_row "repository.head.pr_tip" "discrepancy" "local=${local_head_oid:-unavailable} pr=$pr_head_oid" "git rev-parse HEAD vs gh pr view headRefOid"
        fi
      elif [ -n "$pr_head_oid" ] && is_true "$returned_to_expected_base"; then
        add_row "repository.head.pr_tip" "verified" "${pr_head_oid:0:12}" "local checkout returned to expected base; PR headRefOid verifies item tip"
      fi

      if [ -z "$expected_base" ] || [ "$pr_base" = "$expected_base" ]; then
        add_row "pull_request.base" "verified" "$pr_base" "gh pr view $pr_number --json baseRefName"
      else
        add_row "pull_request.base" "discrepancy" "expected=$expected_base observed=$pr_base" "gh pr view $pr_number --json baseRefName"
      fi

      if [ "$pr_draft" = "false" ]; then
        add_row "pull_request.readiness" "verified" "isDraft=false" "gh pr view $pr_number --json isDraft"
      else
        add_row "pull_request.readiness" "discrepancy" "isDraft=$pr_draft" "gh pr view $pr_number --json isDraft"
      fi

      if [ "${#expected_labels[@]}" -gt 0 ]; then
        for label in "${expected_labels[@]}"; do
          if printf ',%s,' "$pr_labels" | grep -Fq ",$label,"; then
            add_row "pull_request.label.$label" "verified" "present" "gh pr view $pr_number --json labels"
          else
            add_row "pull_request.label.$label" "discrepancy" "missing; observed=$pr_labels" "gh pr view $pr_number --json labels"
          fi
        done
      fi

      if [ "${#forbidden_labels[@]}" -gt 0 ]; then
        for label in "${forbidden_labels[@]}"; do
          if printf ',%s,' "$pr_labels" | grep -Fq ",$label,"; then
            add_row "pull_request.label.$label" "discrepancy" "forbidden label present; observed=$pr_labels" "gh pr view $pr_number --json labels"
          else
            add_row "pull_request.label.$label" "verified" "absent" "gh pr view $pr_number --json labels"
          fi
        done
      fi

      if [ -n "$changed_file_prefix" ]; then
        if outside_files="$(printf '%s\n' "$pr_json" | jq -r --arg prefix "$changed_file_prefix" '[(.files // [])[].path | select(startswith($prefix) | not)] | join(",")' 2>&1)"; then
          if [ -z "$outside_files" ]; then
            add_row "pull_request.changed_files" "verified" "$pr_files" "all files match prefix $changed_file_prefix"
          else
            add_row "pull_request.changed_files" "discrepancy" "outside_prefix=$outside_files" "gh pr view $pr_number --json files"
          fi
        else
          add_row "pull_request.changed_files" "unavailable_required" "$outside_files" "gh pr view $pr_number --json files"
        fi
      else
        add_row "pull_request.changed_files" "verified" "$pr_files" "gh pr view $pr_number --json files"
      fi

      reviewer_checks="$(reviewer_check_names_json)"
      if normalized_checks="$(printf '%s\n' "$pr_json" | jq '
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
      ' 2>&1)" \
        && check_summary="$(printf '%s\n' "$normalized_checks" | jq -r --argjson reviewerChecks "$reviewer_checks" '
        .
        | map(select(([.name // "", .context // "", .workflowName // ""] | any(. as $n | ($reviewerChecks | index($n)) != null)) | not))
        | map({
            name: (.name // .context // .workflowName // "unknown"),
            state: (.state // ""),
            status: (.status // ""),
            conclusion: (.conclusion // "")
          })
        | map(.name + ":" + (if .conclusion != "" then .conclusion elif .state != "" then .state else .status end))
        | join(",")
      ' 2>&1)" \
        && blocking_checks="$(printf '%s\n' "$normalized_checks" | jq -r --argjson reviewerChecks "$reviewer_checks" '
          [
            .[]
            | select(([.name // "", .context // "", .workflowName // ""] | any(. as $n | ($reviewerChecks | index($n)) != null)) | not)
            | {state: (.state // ""), status: (.status // ""), conclusion: (.conclusion // "")}
            | select(
                ((.state != "") and (.state != "SUCCESS"))
                or
                ((.status != "") and (.status != "COMPLETED"))
                or
                ((.conclusion != "") and (.conclusion != "SUCCESS") and (.conclusion != "SKIPPED") and (.conclusion != "NEUTRAL"))
              )
          ]
          | length
        ' 2>&1)"; then
        if [ "$blocking_checks" = "0" ]; then
          add_row "pull_request.ci" "verified" "${check_summary:-no checks}" "gh pr view $pr_number --json statusCheckRollup"
        elif is_true "$require_ci_green"; then
          add_row "pull_request.ci" "discrepancy" "${check_summary:-blocking checks present}" "gh pr view $pr_number --json statusCheckRollup"
        else
          add_row "pull_request.ci" "verified" "${check_summary:-blocking checks allowed}" "CI green not required for this claim"
        fi
      else
        add_row "pull_request.ci" "unavailable_required" "$check_summary $blocking_checks" "gh pr view $pr_number --json statusCheckRollup"
      fi

      if latest_review_summary="$(fetch_latest_review_summary "$pr_repo" "$pr_number" 2>&1)"; then
        if [ -n "$latest_review_summary" ]; then
          normalized_review_summary="$(printf '%s\n' "$latest_review_summary" | tr -d '*')"
          if grep -Eq 'Result:[[:space:]]*(clean|skipped)|RESULT=(clean|skipped)|No blocking PR feedback' <<<"$normalized_review_summary"; then
            add_row "pull_request.review_summary" "verified" "clean_or_skipped" "paginated issue comments sorted by updated_at"
          elif is_true "$require_review_summary"; then
            add_row "pull_request.review_summary" "discrepancy" "summary present but not clean/skipped" "paginated issue comments sorted by updated_at"
          else
            add_row "pull_request.review_summary" "verified" "non_clean_summary_observed" "review summary clean state not required for this terminal claim"
          fi
        elif is_true "$require_review_summary"; then
          add_row "pull_request.review_summary" "unavailable_required" "missing reviewer-loop summary" "gh api repos/$pr_repo/issues/$pr_number/comments --paginate"
        else
          add_row "pull_request.review_summary" "unavailable_optional" "not claimed" "review summary not required for this terminal claim"
        fi
      else
        if is_true "$require_review_summary"; then
          add_row "pull_request.review_summary" "unavailable_required" "$latest_review_summary" "gh api repos/$pr_repo/issues/$pr_number/comments --paginate"
        else
          add_row "pull_request.review_summary" "unavailable_optional" "$latest_review_summary" "review summary not required for this terminal claim"
        fi
      fi

      if ! is_true "$require_review_summary"; then
        add_row "pull_request.local_reviewer_head" "unavailable_optional" "not claimed" "--require-review-summary not set"
      elif ! local_ai_reviewer_configured; then
        add_row "pull_request.local_reviewer_head" "unavailable_optional" "local-ai-reviewer not configured" "resolved platform list"
      elif latest_review_summary="$(fetch_latest_review_summary "$pr_repo" "$pr_number" 2>&1)"; then
        if [ -n "$latest_review_summary" ]; then
          ledger_json="$(printf '%s\n' "$latest_review_summary" | extract_reviewer_loop_history_json)"
          if [ -z "$ledger_json" ] \
              || ! ledger_payload="$(printf '%s\n' "$ledger_json" | jq -c '.' 2>&1)"; then
            add_row "pull_request.local_reviewer_head" "unavailable_required" "ledger unreadable" "reviewer_loop_history.v1 in summary comment"
          elif ! printf '%s\n' "$ledger_payload" | jq -e '[.entries[]? | select(.reviewed_heads? | type == "array")] | length > 0' >/dev/null 2>&1; then
            add_row "pull_request.local_reviewer_head" "unavailable_required" "pre-field ledger entry" "reviewed_heads missing from ledger entries"
          elif ledger_local_record="$(printf '%s\n' "$ledger_payload" | jq -c '
              [
                .entries[]? as $entry
                | select(($entry.reviewed_heads? | type) == "array")
                | select(($entry.platform_results? | type) == "array")
                | ($entry.platform_results[]? | select(.platform == "local-ai-reviewer")) as $local_result
                | ($entry.reviewed_heads[]? | select(.platform == "local-ai-reviewer")) as $local_head
                | {result: ($local_result.result // ""), reviewed_head: ($local_head.reviewed_head // "")}
              ]
              | last
              | select(.result == "clean")
              | {reviewed_head}
              // empty
            ')"; then
            if [ -z "$ledger_local_record" ]; then
              add_row "pull_request.local_reviewer_head" "unavailable_required" "local-ai-reviewer head not recorded" "latest local-ai-reviewer reviewed_heads entry"
            elif ! ledger_local_head="$(printf '%s\n' "$ledger_local_record" | jq -r '.reviewed_head // ""')"; then
              add_row "pull_request.local_reviewer_head" "unavailable_required" "ledger parse failed" "reviewer_loop_history.v1 reviewed_heads"
            elif [ -z "${pr_head_oid:-}" ]; then
              add_row "pull_request.local_reviewer_head" "unavailable_required" "live headRefOid unavailable" "gh pr view headRefOid"
            elif [ "$ledger_local_head" = "$pr_head_oid" ]; then
              add_row "pull_request.local_reviewer_head" "verified" "ledger head matches live headRefOid" "reviewer_loop_history.v1 reviewed_heads"
            else
              add_row "pull_request.local_reviewer_head" "discrepancy" "ledger head ${ledger_local_head} != live ${pr_head_oid}" "reviewer_loop_history.v1 reviewed_heads"
            fi
          else
            add_row "pull_request.local_reviewer_head" "unavailable_required" "ledger parse failed" "reviewer_loop_history.v1 reviewed_heads"
          fi
        elif is_true "$require_review_summary"; then
          add_row "pull_request.local_reviewer_head" "unavailable_required" "missing reviewer-loop summary" "gh api repos/$pr_repo/issues/$pr_number/comments --paginate"
        else
          add_row "pull_request.local_reviewer_head" "unavailable_optional" "not claimed" "review summary not required for this terminal claim"
        fi
      else
        add_row "pull_request.local_reviewer_head" "unavailable_required" "$latest_review_summary" "gh api repos/$pr_repo/issues/$pr_number/comments --paginate"
      fi

      if is_true "$require_review_threads"; then
        owner="${pr_repo%%/*}"
        name="${pr_repo#*/}"
        thread_bot_logins_json="$(configured_thread_bot_logins_json)"
        threads_json=""
        thread_count=""
        graph_thread_comment_ids="[]"
        if [ "$(printf '%s\n' "$thread_bot_logins_json" | jq -r 'length')" = "0" ]; then
          add_row "pull_request.review_threads" "unavailable_required" "no configured bot logins" "configured review platforms"
        elif threads_json="$(fetch_review_threads_json "$owner" "$name" "$pr_number" 2>&1)" \
          && thread_count="$(printf '%s\n' "$threads_json" | jq -r --argjson botLogins "$thread_bot_logins_json" '
            [
              .[]
              | select(.isResolved == false)
              | select((.isOutdated // false) == false)
              | select((.comments.nodes[0].body // "") | contains("✅ Addressed") | not)
              | select(.comments.nodes[0].author.login as $author | ($botLogins | index($author)) != null)
            ]
            | length
          ' 2>&1)" \
          && graph_thread_comment_ids="$(printf '%s\n' "$threads_json" | jq -c '
            [
              .[]
              | .comments.nodes[0].databaseId // empty
            ]
          ' 2>&1)"; then
          if rest_comment_count="$(fetch_unreplied_rest_review_comments_count "$pr_repo" "$pr_number" "$thread_bot_logins_json" "$graph_thread_comment_ids" 2>&1)"; then
            review_thread_total=$((thread_count + rest_comment_count))
            if [ "$review_thread_total" = "0" ]; then
              add_row "pull_request.review_threads" "verified" "unresolved=0" "gh api graphql reviewThreads; gh api pulls comments"
            else
              add_row "pull_request.review_threads" "discrepancy" "unresolved=$review_thread_total graph=$thread_count rest=$rest_comment_count" "gh api graphql reviewThreads; gh api pulls comments"
            fi
          else
            add_row "pull_request.review_threads" "unavailable_required" "$rest_comment_count" "gh api pulls comments"
          fi
        else
          add_row "pull_request.review_threads" "unavailable_required" "$thread_count" "gh api graphql reviewThreads"
        fi
      else
        add_row "pull_request.review_threads" "unavailable_optional" "not claimed" "review thread check not required for this terminal claim"
      fi
    fi
  else
    add_row "pull_request" "unavailable_required" "$pr_json" "gh pr view $pr_number"
  fi
else
  add_row "pull_request" "not_applicable" "no PR supplied" "--pr omitted"
fi

if [ -n "$issue" ]; then
  tracker_status=""
  tracker_result=0
  if [ "${WORKFLOW_SELF_CHECK_TRACKER_STATUS:-}" = "__FAIL__" ]; then
    tracker_status="tracker read failed by WORKFLOW_SELF_CHECK_TRACKER_STATUS"
    tracker_result=1
  elif [ -n "${WORKFLOW_SELF_CHECK_TRACKER_STATUS:-}" ]; then
    tracker_status="$WORKFLOW_SELF_CHECK_TRACKER_STATUS"
  else
    set +e
    tracker_status="$(get_tracker_status_for_issue "$issue" 2>&1)"
    tracker_result=$?
    set -e
  fi

  if printf '%s\n' "$tracker_status" | grep -q '^TRACKER_ACTION_REQUIRED='; then
    if is_true "$tracker_required"; then
      add_row "tracker.status" "unavailable_required" "$tracker_status" "get_tracker_status_for_issue $issue"
    else
      add_row "tracker.status" "unavailable_optional" "$tracker_status" "tracker status read deferred"
    fi
  elif [ "$tracker_result" -eq 0 ] && [ -n "$tracker_status" ]; then
    if [ -z "$expected_tracker_status" ] || [ "$tracker_status" = "$expected_tracker_status" ]; then
      add_row "tracker.status" "verified" "$tracker_status" "get_tracker_status_for_issue $issue"
    else
      add_row "tracker.status" "discrepancy" "expected=$expected_tracker_status observed=$tracker_status" "get_tracker_status_for_issue $issue"
    fi
  elif is_true "$tracker_required"; then
    add_row "tracker.status" "unavailable_required" "$tracker_status" "get_tracker_status_for_issue $issue"
  else
    add_row "tracker.status" "unavailable_optional" "${tracker_status:-not claimed}" "tracker status not required for this terminal claim"
  fi
fi

if [ "${#claims[@]}" -gt 0 ]; then
  for claim in "${claims[@]}"; do
    claim_name="${claim%%|*}"
    claim_rest="${claim#*|}"
    if [ "$claim_rest" = "$claim" ]; then
      claim_rest=""
    fi
    claim_required="${claim_rest%%|*}"
    claim_evidence="${claim_rest#*|}"
    if [ "$claim_evidence" = "$claim_rest" ]; then
      claim_evidence=""
    fi
    claim_name="${claim_name:-external_claim}"
    claim_required="${claim_required:-false}"
    claim_evidence="${claim_evidence:-}"
    if [ -n "$claim_evidence" ]; then
      add_row "external.$claim_name" "verified" "$claim_evidence" "--claim $claim_name"
    elif is_true "$claim_required"; then
      add_row "external.$claim_name" "unavailable_required" "missing evidence" "--claim $claim_name"
    else
      add_row "external.$claim_name" "unavailable_optional" "missing optional evidence" "--claim $claim_name"
    fi
  done
fi

if [ "$unavailable_required_count" -gt 0 ]; then
  overall_result="unavailable_required"
elif [ "$discrepancy_count" -gt 0 ]; then
  overall_result="discrepancy"
elif [ "$failure_count" -eq 0 ]; then
  overall_result="verified"
else
  overall_result="discrepancy"
fi

cat <<EOF
## Ground-Truth Completion Verification

- Item: #$issue
- Stage: $stage
- Branch: $expected_branch
- Worktree: $resolved_worktree_path
- Result: $overall_result

| Surface | Result | Observed | Evidence |
| --- | --- | --- | --- |
EOF

printf '%s\n' "${rows[@]}"
printf '\n'

if [ "$failure_count" -eq 0 ]; then
  exit 0
fi

exit 1

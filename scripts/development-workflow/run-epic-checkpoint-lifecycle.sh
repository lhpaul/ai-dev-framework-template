#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

CHECKPOINT_MARKER="<!-- run-epic:checkpoint-status -->"
SATISFIED_MARKER_PREFIX="<!-- run-epic:checkpoint-satisfied:"
WAIVED_MARKER_PREFIX="<!-- run-epic:checkpoint-waived:"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/run-epic-checkpoint-lifecycle.sh stage-from-branch --branch <name>
  ./scripts/development-workflow/run-epic-checkpoint-lifecycle.sh evaluate-blocking --item <number> --branch <name> --checkpoints-file <json-array>
  ./scripts/development-workflow/run-epic-checkpoint-lifecycle.sh detect-satisfaction --item <number> --branch <name> --checkpoints-file <json-array> [--pr <number>]
  ./scripts/development-workflow/run-epic-checkpoint-lifecycle.sh render-pr-checkpoint-comment --input <file>
  ./scripts/development-workflow/run-epic-checkpoint-lifecycle.sh sync-pr-labels --pr <number> --item <number> --branch <name> --checkpoints-file <json-array> [--write-checkpoints-file <path>]

Evaluates human-checkpoint policy for a PR, detects satisfaction from human
review/comment signals, applies or removes human-checkpoint-required, and
records checkpoint state in a stable PR comment.
EOF
}

command="${1:-}"
if [ "$#" -gt 0 ]; then
  shift
fi

pr_number=""
item_number=""
branch_name=""
checkpoints_file=""
write_checkpoints_file=""
input_file=""

error_exit() {
  echo "ERROR: $*" >&2
  exit 1
}

require_value() {
  local option="$1"
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ] || [ "${2#--}" != "$2" ]; then
    echo "$option requires a value." >&2
    usage >&2
    exit 64
  fi
}

is_positive_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0*) return 1 ;;
    *) return 0 ;;
  esac
}

load_checkpoints_json() {
  local file="$1"
  local json
  if [ ! -f "$file" ]; then
    error_exit "checkpoints file not found: $file"
  fi
  if ! json="$(jq -c '.' "$file" 2>/dev/null)"; then
    error_exit "checkpoints file is not valid JSON: $file"
  fi
  if ! printf '%s\n' "$json" | jq -e 'type == "array"' >/dev/null; then
    error_exit "checkpoints file must contain a JSON array"
  fi
  printf '%s\n' "$json"
}

checkpoint_jq_filter='
  def stage_rank($stage):
    if $stage == "spec" then 1
    elif $stage == "plan" then 2
    elif $stage == "implementation" then 3
    else 0 end;
  def stage_from_branch($branch):
    if ($branch | test("^spec/")) then "spec"
    elif ($branch | test("^implementation-plan/")) then "plan"
    elif ($branch | test("^(feature|fix|refactor|hotfix|backport/hotfix)/")) then "implementation"
    else "implementation" end;
  def checkpoint_key($cp): "\($cp.item_number):\($cp.stage):\($cp.domain)";
  def checkpoint_applies($cp; $item; $prStage):
    ($cp.item_number | tonumber) == ($item | tonumber)
    and ($cp.satisfaction_state // "pending") == "pending"
    and (stage_rank($cp.stage) > 0)
    and (stage_rank($cp.stage) <= stage_rank($prStage));
'

stage_from_branch() {
  local branch="$1"
  jq -r --arg branch "$branch" -n "$checkpoint_jq_filter"'stage_from_branch($branch)'
}

evaluate_blocking_json() {
  local item="$1"
  local branch="$2"
  local checkpoints_json="$3"
  printf '%s\n' "$checkpoints_json" | jq -c --arg item "$item" --arg branch "$branch" "$checkpoint_jq_filter"'
    stage_from_branch($branch) as $prStage |
    [.[] | select(checkpoint_applies(.; $item; $prStage))]
  '
}

detect_satisfaction_json() {
  local item="$1"
  local branch="$2"
  local checkpoints_json="$3"
  local pr="${4:-}"

  local reviews_json comments_json head_sha
  reviews_json='[]'
  comments_json='[]'
  head_sha=""

  if [ -n "$pr" ] && is_positive_int "$pr"; then
    require_gh
    if ! reviews_json="$(gh pr view "$pr" --json reviews --jq '.reviews // []' 2>/dev/null)"; then
      error_exit "failed to read reviews for PR #$pr"
    fi
    if ! head_sha="$(gh pr view "$pr" --json headRefOid --jq '.headRefOid // ""' 2>/dev/null)"; then
      error_exit "failed to read head SHA for PR #$pr"
    fi
    local repo
    repo="$(repo_slug)"
    if ! comments_json="$(gh api --paginate --slurp "repos/${repo}/issues/${pr}/comments?per_page=100" 2>/dev/null | jq -c '[.[].[]? | {author: (.user.login // ""), body: (.body // ""), createdAt: (.created_at // "")}]' 2>/dev/null)"; then
      error_exit "failed to read comments for PR #$pr"
    fi
  fi

  printf '%s\n' "$checkpoints_json" | jq -c \
    --arg item "$item" \
    --arg branch "$branch" \
    --arg head_sha "$head_sha" \
    --argjson reviews "$reviews_json" \
    --argjson comments "$comments_json" \
    "$checkpoint_jq_filter"'
    def bot_login($login):
      ($login // "") as $l |
      ($l | test("^(coderabbitai|cursor\\[bot\\]|devin-ai-integration|greptile-apps|github-actions|dependabot|renovate|copilot|bot)$"; "i"))
      or ($l | endswith("[bot]"));
    def marker_match($body; $prefix; $item; $stage; $domain):
      ($body // "") | contains($prefix + ($item|tostring) + ":" + $stage + ":" + $domain + " -->");
    def parse_waiver_rationale($body; $prefix; $item; $stage; $domain):
      ($body // "")
      | capture($prefix + ($item|tostring) + ":" + $stage + ":" + $domain + " -->\\s*(?<rationale>.*)$"; "s")
      | (.rationale // "") | gsub("\\s+$"; "");
    def latest_human_review:
      ($reviews // [])
      | map(select(bot_login(.author.login) | not))
      | map(select(
          ($head_sha | length) == 0
          or ((.commit.oid // "") == $head_sha)
          or ((.commit // {}).oid? // "" | length) == 0
        ))
      | sort_by(.submittedAt // "")
      | last // null;
    def review_satisfies($cp):
      (latest_human_review) as $latest |
      ($latest != null) and (($latest.state // "") == "APPROVED");
    def human_comments: ($comments // []) | map(select(bot_login(.author) | not));
    def waiver_rationale_valid($body; $item; $stage; $domain):
      (parse_waiver_rationale($body; "'"$WAIVED_MARKER_PREFIX"'"; ($item|tostring); $stage; $domain) | gsub("\\s"; "") | length) > 0;
    stage_from_branch($branch) as $prStage |
    map(
      . as $cp |
      if ($cp.item_number | tonumber) != ($item | tonumber) then .
      elif (stage_rank($cp.stage) > stage_rank($prStage)) then .
      else
        ($cp | del(.satisfaction_state, .satisfied_by, .satisfied_at, .waiver_rationale) | .satisfaction_state = "pending") as $base |
        $base |
        human_comments as $commentList |
        (
          ($commentList
            | map(select(
                marker_match(.body; "'"$WAIVED_MARKER_PREFIX"'"; ($cp.item_number|tostring); $cp.stage; $cp.domain)
              ))
            | map(select(waiver_rationale_valid(.body; ($cp.item_number|tostring); $cp.stage; $cp.domain)))
            | last) as $waivedComment
          | if $waivedComment then
              .satisfaction_state = "waived"
              | .satisfied_by = ($waivedComment.author // "")
              | .satisfied_at = ($waivedComment.createdAt // "")
              | .waiver_rationale = (parse_waiver_rationale($waivedComment.body; "'"$WAIVED_MARKER_PREFIX"'"; ($cp.item_number|tostring); $cp.stage; $cp.domain))
            elif
              ($commentList
                | map(select(
                    marker_match(.body; "'"$SATISFIED_MARKER_PREFIX"'"; ($cp.item_number|tostring); $cp.stage; $cp.domain)
                  ))
                | length) > 0
            then
              ($commentList
                | map(select(marker_match(.body; "'"$SATISFIED_MARKER_PREFIX"'"; ($cp.item_number|tostring); $cp.stage; $cp.domain)))
                | last) as $satisfiedComment
              | .satisfaction_state = "satisfied"
              | .satisfied_by = ($satisfiedComment.author // "")
              | .satisfied_at = ($satisfiedComment.createdAt // "")
            elif ($cp.stage == $prStage) and review_satisfies($cp) then
              .satisfaction_state = "satisfied"
              | .satisfied_by = (latest_human_review | .author.login // "pr_review_approved")
              | .satisfied_at = (latest_human_review | .submittedAt // "")
            else .
            end
        )
      end
    )
  '
}

render_pr_checkpoint_comment() {
  local json="$1"
  {
    printf '%s\n' "$CHECKPOINT_MARKER"
    printf '## Human Checkpoint Status\n\n'
    printf '%s\n' "$json" | jq -r '
      "- Item: #" + (.item.number | tostring),
      "- PR: #" + (.pr.number | tostring),
      "- Branch: `" + (.pr.branch | tostring) + "`",
      "- PR workflow stage: " + (.pr.stage | tostring),
      "- Label required: " + ((.label_required // false) | tostring),
      "- Label present: " + ((.label_present // false) | tostring)
    '
    printf '\n### Checkpoints\n\n'
    if [ "$(printf '%s\n' "$json" | jq '(.checkpoints // []) | length')" -eq 0 ]; then
      printf 'No checkpoints recorded for this PR.\n'
    else
      printf '| Item | Stage | Domain | State | Reason | Required human action | Satisfied by |\n'
      printf '| --- | --- | --- | --- | --- | --- | --- |\n'
      printf '%s\n' "$json" | jq -r '
        def cell:
          tostring
          | gsub("\\|"; "\\\\|")
          | gsub("\\r?\\n"; "<br>")
          | gsub("\\t"; " ");
        (.checkpoints // [])[] |
        "| #" + (.item_number | tostring) +
        " | " + ((.stage // "") | cell) +
        " | " + ((.domain // "") | cell) +
        " | " + ((.satisfaction_state // "pending") | cell) +
        " | " + ((.reason // "") | cell) +
        " | " + ((.required_human_action // "") | cell) +
        " | " + ((.satisfied_by // "-") | cell) + " |"
      '
    fi
    printf '\n### Blocking checkpoints\n\n'
    if [ "$(printf '%s\n' "$json" | jq '(.blocking // []) | length')" -eq 0 ]; then
      printf 'None — delegated review/merge may proceed when other gates pass.\n'
    else
      printf '%s\n' "$json" | jq -r '(.blocking // [])[] | "- #" + (.item_number|tostring) + " " + .stage + "/" + .domain + ": " + (.required_human_action // "")'
    fi
    printf '\n### Satisfaction signals\n\n'
    printf '%s\n' "$json" | jq -r '
      "- Explicit comment: `" + (.satisfaction_signals.comment_marker | tostring) + "`",
      "- Explicit waiver: `" + (.satisfaction_signals.waiver_marker | tostring) + "`",
      "- PR review approval on matching stage also satisfies the checkpoint."
    '
  }
}

find_marker_comment_id() {
  local target="$1"
  local marker="$2"
  local repo comments

  repo="$(repo_slug)"
  if ! comments="$(gh api --paginate --slurp "repos/${repo}/issues/${target}/comments?per_page=100" 2>/dev/null)"; then
    error_exit "failed to read comments for issue/PR #$target"
  fi
  printf '%s\n' "$comments" |
    jq -r --arg marker "$marker" '[.[][]? | select((.body // "") | contains($marker))] | last | .id // empty'
}

apply_checkpoint_comment() {
  local pr="$1"
  local body="$2"
  local repo comment_id

  require_gh
  repo="$(repo_slug)"
  comment_id="$(find_marker_comment_id "$pr" "$CHECKPOINT_MARKER")"
  if [ -n "$comment_id" ]; then
    jq -n --arg body "$body" '{body: $body}' |
      gh api -X PATCH "repos/${repo}/issues/comments/${comment_id}" --input - >/dev/null
    printf 'UPDATED_COMMENT_ID=%s\n' "$comment_id"
  else
    jq -n --arg body "$body" '{body: $body}' |
      gh api -X POST "repos/${repo}/issues/${pr}/comments" --input - >/dev/null
    printf 'CREATED_COMMENT=1\n'
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pr)
      require_value "$@"
      pr_number="$2"
      shift 2
      ;;
    --item)
      require_value "$@"
      item_number="$2"
      shift 2
      ;;
    --branch)
      require_value "$@"
      branch_name="$2"
      shift 2
      ;;
    --checkpoints-file)
      require_value "$@"
      checkpoints_file="$2"
      shift 2
      ;;
    --write-checkpoints-file)
      require_value "$@"
      write_checkpoints_file="$2"
      shift 2
      ;;
    --input)
      require_value "$@"
      input_file="$2"
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

case "$command" in
  stage-from-branch|evaluate-blocking|detect-satisfaction|render-pr-checkpoint-comment|sync-pr-labels)
    ;;
  *)
    echo "ERROR: unknown or missing subcommand." >&2
    usage >&2
    exit 64
    ;;
esac

case "$command" in
  stage-from-branch)
    [ -n "$branch_name" ] || error_exit "--branch is required"
    stage_from_branch "$branch_name"
    ;;
  evaluate-blocking)
    [ -n "$item_number" ] && is_positive_int "$item_number" || error_exit "--item must be a positive integer"
    [ -n "$branch_name" ] || error_exit "--branch is required"
    [ -n "$checkpoints_file" ] || error_exit "--checkpoints-file is required"
    checkpoints_json="$(load_checkpoints_json "$checkpoints_file")"
    evaluate_blocking_json "$item_number" "$branch_name" "$checkpoints_json"
    ;;
  detect-satisfaction)
    [ -n "$item_number" ] && is_positive_int "$item_number" || error_exit "--item must be a positive integer"
    [ -n "$branch_name" ] || error_exit "--branch is required"
    [ -n "$checkpoints_file" ] || error_exit "--checkpoints-file is required"
    checkpoints_json="$(load_checkpoints_json "$checkpoints_file")"
    updated_json="$(detect_satisfaction_json "$item_number" "$branch_name" "$checkpoints_json" "$pr_number")"
    if [ -n "$write_checkpoints_file" ]; then
      printf '%s\n' "$updated_json" | jq '.' > "$write_checkpoints_file"
    fi
    printf '%s\n' "$updated_json"
    ;;
  render-pr-checkpoint-comment)
    [ -n "$input_file" ] || error_exit "--input is required"
    if [ ! -f "$input_file" ]; then
      error_exit "input file not found: $input_file"
    fi
    render_pr_checkpoint_comment "$(jq -c '.' "$input_file")"
    ;;
  sync-pr-labels)
    [ -n "$pr_number" ] && is_positive_int "$pr_number" || error_exit "--pr must be a positive integer"
    [ -n "$item_number" ] && is_positive_int "$item_number" || error_exit "--item must be a positive integer"
    [ -n "$branch_name" ] || error_exit "--branch is required"
    [ -n "$checkpoints_file" ] || error_exit "--checkpoints-file is required"
    require_gh
    checkpoints_json="$(load_checkpoints_json "$checkpoints_file")"
    updated_checkpoints="$(detect_satisfaction_json "$item_number" "$branch_name" "$checkpoints_json" "$pr_number")"
    if [ -n "$write_checkpoints_file" ]; then
      printf '%s\n' "$updated_checkpoints" | jq '.' > "$write_checkpoints_file"
    fi
    blocking_json="$(evaluate_blocking_json "$item_number" "$branch_name" "$updated_checkpoints")"
    pr_stage="$(stage_from_branch "$branch_name")"
    label_required="false"
    if [ "$(printf '%s\n' "$blocking_json" | jq 'length')" -gt 0 ]; then
      label_required="true"
    fi
    item_checkpoints_json="$(printf '%s\n' "$updated_checkpoints" | jq -c --arg item "$item_number" '[.[] | select((.item_number | tonumber) == ($item | tonumber))]')"
    if [ "$label_required" = "true" ]; then
      if ! gh pr edit "$pr_number" --add-label "human-checkpoint-required" >/dev/null 2>&1; then
        error_exit "failed to apply human-checkpoint-required label on PR #$pr_number"
      fi
      printf 'LABEL_APPLIED=human-checkpoint-required\n'
    else
      if ! has_label="$(gh pr view "$pr_number" --json labels --jq '[.labels[].name | select(. == "human-checkpoint-required")] | length' 2>/dev/null)"; then
        error_exit "failed to read labels for PR #$pr_number"
      fi
      if [ "$has_label" -gt 0 ]; then
        if ! gh pr edit "$pr_number" --remove-label "human-checkpoint-required" >/dev/null 2>&1; then
          error_exit "failed to remove human-checkpoint-required label on PR #$pr_number"
        fi
        printf 'LABEL_REMOVED=human-checkpoint-required\n'
      else
        printf 'LABEL_ABSENT=human-checkpoint-required\n'
      fi
    fi
    if ! has_label_after="$(gh pr view "$pr_number" --json labels --jq '[.labels[].name | select(. == "human-checkpoint-required")] | length' 2>/dev/null)"; then
      error_exit "failed to read labels for PR #$pr_number after label sync"
    fi
    label_present="false"
    if [ "$has_label_after" -gt 0 ]; then
      label_present="true"
    fi
    comment_payload="$(jq -n \
      --argjson item "$(jq -n --argjson n "$item_number" '{number: ($n|tonumber)}')" \
      --argjson pr "$(jq -n --argjson n "$pr_number" --arg branch "$branch_name" --arg stage "$pr_stage" '{number: ($n|tonumber), branch: $branch, stage: $stage}')" \
      --argjson checkpoints "$item_checkpoints_json" \
      --argjson blocking "$blocking_json" \
      --argjson label_required "$label_required" \
      --argjson label_present "$label_present" \
      --arg satisfied_marker "${SATISFIED_MARKER_PREFIX}${item_number}:<stage>:<domain> -->" \
      --arg waiver_marker "${WAIVED_MARKER_PREFIX}${item_number}:<stage>:<domain> --> <rationale>" \
      '{
        item: $item,
        pr: $pr,
        checkpoints: $checkpoints,
        blocking: $blocking,
        label_required: $label_required,
        label_present: $label_present,
        satisfaction_signals: {
          comment_marker: $satisfied_marker,
          waiver_marker: $waiver_marker
        }
      }')"
    comment_body="$(render_pr_checkpoint_comment "$comment_payload")"
    apply_checkpoint_comment "$pr_number" "$comment_body"
    printf 'BLOCKING_COUNT=%s\n' "$(printf '%s\n' "$blocking_json" | jq 'length')"
    ;;
esac

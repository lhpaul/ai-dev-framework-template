#!/usr/bin/env bash

set -euo pipefail

workflow_script_dir() {
  if [[ -z "${BASH_SOURCE[0]:-}" ]]; then
    printf 'ERROR: BASH_SOURCE[0] is unset — source workflow-lib.sh from a Bash script or via:\n  bash -c "source scripts/development-workflow/workflow-lib.sh"\n' >&2
    return 1
  fi
  CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
}

workflow_repo_root() {
  CDPATH='' cd -- "$(workflow_script_dir)/../.." && pwd
}

workflow_config_file() {
  printf '%s/.ai-dev-workflow.yaml\n' "$(workflow_repo_root)"
}

# workflow_effective_config_file
# Honors AI_DEV_WORKFLOW_CONFIG_FILE when it points to an existing file;
# otherwise falls back to the repository default .ai-dev-workflow.yaml when present.
workflow_effective_config_file() {
  local default
  if [ -n "${AI_DEV_WORKFLOW_CONFIG_FILE:-}" ] && [ -f "${AI_DEV_WORKFLOW_CONFIG_FILE}" ]; then
    printf '%s\n' "${AI_DEV_WORKFLOW_CONFIG_FILE}"
    return 0
  fi
  default="$(workflow_config_file)"
  if [ -f "$default" ]; then
    printf '%s\n' "$default"
    return 0
  fi
  return 1
}

workflow_local_review_override_root() {
  local override_root="${WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT:-}"

  if [ -n "$override_root" ]; then
    if [ ! -d "$override_root" ]; then
      echo "ERROR: configured local reviewer override source is unavailable." >&2
      return 1
    fi
    printf '%s\n' "$override_root"
    return 0
  fi

  workflow_repo_root
}

workflow_local_config_file() {
  local override_root

  if ! override_root="$(workflow_local_review_override_root)"; then
    return 1
  fi
  printf '%s/.ai-dev-workflow.local.yaml\n' "$override_root"
}

workflow_is_default_config_file() {
  local config_file="$1"
  [ "$config_file" = "$(workflow_config_file)" ] || [ "${WORKFLOW_APPLY_LOCAL_REVIEW_OVERRIDES:-}" = "1" ]
}

workflow_config_resolver_script() {
  printf '%s/workflow-config-resolver.py\n' "$(workflow_script_dir)"
}

workflow_config_exists() {
  [ -f "$(workflow_config_file)" ]
}

cd_workflow_repo_root() {
  cd -- "$(workflow_repo_root)"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

gh_available() {
  have_cmd gh && gh auth status >/dev/null 2>&1
}

require_gh() {
  if ! gh_available; then
    echo "GitHub CLI authentication is required for this script." >&2
    exit 2
  fi
}

repo_slug() {
  if [ -n "${WORKFLOW_TARGET_GITHUB_REPO:-}" ]; then
    if ! workflow_is_valid_github_repo_slug "$WORKFLOW_TARGET_GITHUB_REPO"; then
      echo "ERROR: WORKFLOW_TARGET_GITHUB_REPO must be an owner/repo GitHub repository slug." >&2
      return 1
    fi
    printf '%s\n' "$WORKFLOW_TARGET_GITHUB_REPO"
    return 0
  fi
  gh repo view --json nameWithOwner --jq '.nameWithOwner'
}

gh_api_timeout_seconds() {
  local value="${WORKFLOW_GH_API_TIMEOUT_SECONDS:-30}"
  if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
    value=30
  fi
  printf '%s\n' "$value"
}

gh_api_bounded() {
  local timeout_seconds
  timeout_seconds="$(gh_api_timeout_seconds)"
  if command -v timeout >/dev/null 2>&1 && timeout --help 2>&1 | grep -q -- '--kill-after'; then
    local status
    status=0
    timeout --kill-after=1 "$timeout_seconds" gh api "$@" || status=$?
    if [ "$status" -eq 137 ]; then
      return 124
    fi
    return "$status"
  fi

  local output_file pid elapsed status process_group
  output_file="$(mktemp)" || return 1
  process_group=0
  if command -v setsid >/dev/null 2>&1; then
    setsid gh api "$@" >"$output_file" &
    process_group=1
  else
    gh api "$@" >"$output_file" &
  fi
  pid=$!
  elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout_seconds" ]; then
      if [ "$process_group" -eq 1 ]; then
        kill -TERM "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
      else
        kill "$pid" 2>/dev/null || true
      fi
      sleep 1
      if kill -0 "$pid" 2>/dev/null; then
        if [ "$process_group" -eq 1 ]; then
          kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
        else
          kill -KILL "$pid" 2>/dev/null || true
        fi
      fi
      wait "$pid" 2>/dev/null || true
      rm -f "$output_file"
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  status=0
  wait "$pid" || status=$?
  cat "$output_file"
  rm -f "$output_file"
  if ! [[ "$status" =~ ^[0-9]+$ ]]; then
    status=1
  fi
  return "$status"
}

workflow_context_value() {
  local key="$1"
  local context="${2:-}"

  printf '%s\n' "$context" | awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }'
}

workflow_github_repo_from_git_url() {
  local git_url="$1"
  local remote_path=""

  case "$git_url" in
    https://github.com/*)
      remote_path="${git_url#https://github.com/}"
      ;;
    https://*@github.com/*)
      remote_path="${git_url#https://*@github.com/}"
      ;;
    git@github.com:*)
      remote_path="${git_url#git@github.com:}"
      ;;
    ssh://git@github.com/*)
      remote_path="${git_url#ssh://git@github.com/}"
      ;;
  esac

  remote_path="${remote_path%.git}"
  if [ -n "$remote_path" ] && workflow_remote_path_has_single_repo "$remote_path"; then
    printf '%s\n' "$remote_path"
  fi
}

workflow_github_repo_from_context() {
  local context="$1"
  local github_repo
  local git_url

  github_repo="$(workflow_context_value TARGET_GITHUB_REPO "$context")"
  if [ -n "$github_repo" ]; then
    printf '%s\n' "$github_repo"
    return 0
  fi

  git_url="$(workflow_context_value TARGET_GIT_URL "$context")"
  if [ -n "$git_url" ]; then
    workflow_github_repo_from_git_url "$git_url"
  fi
}

workflow_product_repo_name_for_github_slug() {
  local root="$1"
  local slug="$2"
  local name context github

  if [ -z "$root" ] || [ -z "$slug" ]; then
    return 1
  fi

  while IFS= read -r name; do
    [ -n "$name" ] || continue
    if ! context="$(workflow_repository_context "$name" "$root" 2>/dev/null)"; then
      continue
    fi
    github="$(workflow_github_repo_from_context "$context")"
    if [ "$github" = "$slug" ]; then
      printf '%s\n' "$name"
      return 0
    fi
  done < <(python3 "$(workflow_config_resolver_script)" list-product-repos --repo-root "$root" 2>/dev/null)

  return 1
}

workflow_hub_root_for_ci_policy() {
  local root="$1"
  local github_slug="${2:-}"
  local mode context candidate parent repo_name

  if [ -z "$root" ]; then
    return 1
  fi

  if [ -n "${WORKFLOW_HUB_REPO_ROOT:-}" ] && [ -f "${WORKFLOW_HUB_REPO_ROOT}/.ai-dev-workflow.yaml" ]; then
    mode="$(python3 "$(workflow_config_resolver_script)" mode --repo-root "$WORKFLOW_HUB_REPO_ROOT" --json 2>/dev/null | jq -r '.WORKFLOW_MODE // ""')"
    if [ "$mode" = "workflow_hub" ]; then
      printf '%s\n' "$WORKFLOW_HUB_REPO_ROOT"
      return 0
    fi
  fi

  mode="$(python3 "$(workflow_config_resolver_script)" mode --repo-root "$root" --json 2>/dev/null | jq -r '.WORKFLOW_MODE // ""')"
  if [ "$mode" != "product_repo" ]; then
    return 1
  fi

  if [ -z "$github_slug" ]; then
    context="$(workflow_repository_context "" "$root" 2>/dev/null)" || return 1
    github_slug="$(workflow_github_repo_from_context "$context")"
  fi
  [ -n "$github_slug" ] || return 1

  parent="$(dirname "$root")"
  for candidate in "$parent"/*; do
    [ -e "$candidate/.ai-dev-workflow.yaml" ] || continue
    mode="$(python3 "$(workflow_config_resolver_script)" mode --repo-root "$candidate" --json 2>/dev/null | jq -r '.WORKFLOW_MODE // ""')"
    if [ "$mode" = "workflow_hub" ]; then
      repo_name="$(workflow_product_repo_name_for_github_slug "$candidate" "$github_slug" 2>/dev/null || true)"
      if [ -n "$repo_name" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  done

  return 1
}

workflow_merge_ci_policy_into_json() {
  local json="$1"
  local root="${2:-}"
  local repo_name="${3:-}"
  local trust_repo_name=0

  if [ -z "$root" ]; then
    printf '%s\n' "$json"
    return 0
  fi

  if [ -n "$(printf '%s\n' "$json" | jq -r '.ciPolicy // .ci_policy // ""' 2>/dev/null)" ]; then
    printf '%s\n' "$json"
    return 0
  fi

  if [ -n "$repo_name" ]; then
    trust_repo_name=1
  else
    repo_name="$(printf '%s\n' "$json" | jq -r '
      .productRepo.name //
      .productRepoName //
      .repository.productRepoName //
      .repository.product_repo //
      ""
    ' 2>/dev/null)"
    if [ -n "$repo_name" ]; then
      trust_repo_name=1
    fi
  fi

  local github_slug resolve_root="$root" context ci_policy mode
  github_slug="$(printf '%s\n' "$json" | jq -r '.github_repo // ""' 2>/dev/null)"

  mode="$(python3 "$(workflow_config_resolver_script)" mode --repo-root "$root" --json 2>/dev/null | jq -r '.WORKFLOW_MODE // ""')"
  if [ "$mode" = "product_repo" ]; then
    local hub_root
    hub_root="$(workflow_hub_root_for_ci_policy "$root" "$github_slug" 2>/dev/null || true)"
    if [ -n "$hub_root" ]; then
      resolve_root="$hub_root"
      if [ -z "$repo_name" ] && [ -n "$github_slug" ]; then
        repo_name="$(workflow_product_repo_name_for_github_slug "$hub_root" "$github_slug" 2>/dev/null || true)"
      fi
    fi
  elif [ -z "$repo_name" ] && [ -n "$github_slug" ]; then
    repo_name="$(workflow_product_repo_name_for_github_slug "$resolve_root" "$github_slug" 2>/dev/null || true)"
  fi

  if [ -n "$github_slug" ] && [ -z "$repo_name" ]; then
    printf '%s\n' "$json"
    return 0
  fi

  if ! context="$(workflow_repository_context "$repo_name" "$resolve_root" 2>/dev/null)"; then
    printf '%s\n' "$json"
    return 0
  fi

  local resolved_github
  resolved_github="$(workflow_github_repo_from_context "$context")"
  if [ "$trust_repo_name" != 1 ] && [ -n "$github_slug" ] && [ -n "$resolved_github" ] && [ "$github_slug" != "$resolved_github" ]; then
    printf '%s\n' "$json"
    return 0
  fi

  if [ -z "$github_slug" ]; then
    github_slug="$resolved_github"
  fi

  ci_policy="$(workflow_context_value TARGET_CI_POLICY "$context")"
  if [ -z "$ci_policy" ]; then
    printf '%s\n' "$json"
    return 0
  fi

  printf '%s\n' "$json" | jq --arg ci_policy "$ci_policy" '
    if ((.ciPolicy // .ci_policy // "") | length) > 0 then .
    else . + {ciPolicy: $ci_policy}
    end
  ' 2>/dev/null || printf '%s\n' "$json"
}

branch_prefix() {
  case "$1" in
    spec/*) printf 'spec\n' ;;
    implementation-plan/*) printf 'implementation-plan\n' ;;
    feature/*) printf 'feature\n' ;;
    refactor/*) printf 'refactor\n' ;;
    fix/*) printf 'fix\n' ;;
    hotfix/*) printf 'hotfix\n' ;;
    release/*) printf 'release\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

reviewer_for_branch() {
  case "$(branch_prefix "$1")" in
    spec) printf 'spec-reviewer\n' ;;
    implementation-plan) printf 'implementation-plan-reviewer\n' ;;
    feature|refactor|fix|hotfix) printf 'code-reviewer\n' ;;
    *) printf 'none\n' ;;
  esac
}

print_kv() {
  printf '%s=%s\n' "$1" "$2"
}

print_kv_escaped() {
  local value="$2"
  value="${value//\\/\\\\}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\t'/\\t}"
  printf '%s=%s\n' "$1" "$value"
}

soft_suggestion_prefixes() {
  cat <<'EOF'
Consider
You might
An alternative
Optionally
It could be cleaner to
Perhaps
Maybe
You could
One option is
Alternatively
EOF
}

is_soft_suggestion() {
  local body="$1"
  local line
  local prefix
  local normalized_line
  local saw_content=0
  local matched=0
  local in_code_block=0

  while IFS= read -r line; do
    normalized_line="${line%$'\r'}"
    normalized_line="${normalized_line#"${normalized_line%%[![:space:]]*}"}"
    normalized_line="${normalized_line#'**'}"
    normalized_line="${normalized_line%'**'}"
    [ -z "$normalized_line" ] && continue
    case "$normalized_line" in
      '```'*)
        in_code_block=$((1 - in_code_block))
        continue
        ;;
    esac
    [ "$in_code_block" -eq 1 ] && continue
    saw_content=1

    matched=0
    while IFS= read -r prefix; do
      [ -z "$prefix" ] && continue
      case "$normalized_line" in
        "$prefix"*) matched=1; break ;;
      esac
    done < <(soft_suggestion_prefixes)

    [ "$matched" -eq 0 ] && return 1
  done <<< "$body"

  [ "$saw_content" -eq 1 ]
}

is_bugbot_clean_review() {
  local body="$1"
  local line
  local normalized_line
  local reviewed_commit
  local review_footer_prefix='<sup>Reviewed by [Cursor Bugbot](https://cursor.com/bugbot) for commit '
  local review_footer_suffix='. Configure [here](https://www.cursor.com/dashboard/bugbot).</sup>'
  local saw_clean_phrase=0

  case "$body" in
    *BUGBOT_BUG_ID*|*"LOCATIONS START"*|*"DESCRIPTION START"*|*"Triggered by project rule"*|*'**High Severity**'*|*'**Medium Severity**'*|*'**Low Severity**'*)
      return 1
      ;;
  esac
  case "$body" in
    *"found 1 potential issue"*|*"found 2 potential issue"*|*"found 3 potential issue"*|*"found 4 potential issue"*|*"found 5 potential issue"*)
      return 1
      ;;
  esac
  while IFS= read -r line; do
    normalized_line="${line%$'\r'}"
    normalized_line="${normalized_line#"${normalized_line%%[![:space:]]*}"}"
    normalized_line="${normalized_line%"${normalized_line##*[![:space:]]}"}"
    [ -z "$normalized_line" ] && continue
    case "$normalized_line" in
      "Cursor Bugbot found no new issues in this pull request."|"Cursor Bugbot found no potential issues in this pull request."|"Cursor Bugbot found no issues in this pull request."|"✅ Bugbot reviewed your changes and found no new issues!")
        [ "$saw_clean_phrase" -eq 0 ] || return 1
        saw_clean_phrase=1
        continue
        ;;
      '<!-- BUGBOT_REVIEW -->'|'_Comment `@cursor review` or `bugbot run` to trigger another review on this PR_')
        continue
        ;;
    esac
    case "$normalized_line" in
      "$review_footer_prefix"*"$review_footer_suffix")
        reviewed_commit="${normalized_line#"$review_footer_prefix"}"
        reviewed_commit="${reviewed_commit%"$review_footer_suffix"}"
        if [[ "$reviewed_commit" =~ ^[0-9a-f]{40}$ ]]; then
          continue
        fi
        ;;
    esac
    return 1
  done <<< "$body"
  [ "$saw_clean_phrase" -eq 1 ]
}

is_bugbot_disabled_message() {
  local body="$1"

  case "$body" in
    *"Bugbot is disabled"*|*"Bugbot has not been enabled"*|*"Bugbot isn't enabled"*)
      return 0
      ;;
  esac
  return 1
}

is_bugbot_explicit_skip_message() {
  if [ "$#" -ne 1 ]; then
    echo "ERROR: is_bugbot_explicit_skip_message requires exactly 1 argument." >&2
    return 1
  fi

  local body="$1"

  case "$body" in
    *"Skipping Bugbot:"*|*"Bugbot skipped"*|*"Bugbot was skipped"*)
      return 0
      ;;
  esac
  return 1
}

is_bugbot_usage_limit_message() {
  local body="$1"

  printf '%s\n' "$body" | grep -Eiq 'usage or spend limit|usage[/-]spend[ -]?limit|usage[ -]?limit|spend[ -]?limit'
}

open_pr_number_for_branch() {
  require_gh
  gh pr list --head "$1" --state open --limit 100 --json number --jq '.[0].number // empty'
}

workflow_config_review_nested_list() {
  local config_file="$1"
  local phase="$2"
  local bucket="$3"

  [ -f "$config_file" ] || return 0

  awk -v phase="$phase" -v bucket="$bucket" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^["'"'"']|["'"'"']$/, "", value)
      return value
    }

    function emit_inline(value, count, idx, entries) {
      gsub(/[[:space:]]+#.*$/, "", value)
      gsub(/^[^[]*\[/, "", value)
      gsub(/\].*$/, "", value)
      count = split(value, entries, ",")
      for (idx = 1; idx <= count; idx++) {
        entries[idx] = trim(entries[idx])
        if (entries[idx] != "") print entries[idx]
      }
    }

    /^review:[[:space:]]*(#.*)?$/ {
      in_review = 1
      in_phase = 0
      in_bucket = 0
      next
    }

    in_review && /^[^[:space:]#].*:[[:space:]]*/ {
      in_review = 0
      in_phase = 0
      in_bucket = 0
    }

    in_review && $0 ~ ("^[[:space:]][[:space:]]" phase ":[[:space:]]*(#.*)?$") {
      in_phase = 1
      in_bucket = 0
      next
    }

    in_review && in_phase && /^[[:space:]][[:space:]][A-Za-z0-9_-]+:[[:space:]]*/ {
      if ($0 !~ ("^[[:space:]][[:space:]]" phase ":")) {
        in_phase = 0
        in_bucket = 0
      }
    }

    in_review && in_phase && $0 ~ ("^[[:space:]][[:space:]][[:space:]][[:space:]]" bucket ":[[:space:]]*\\[") {
      line = $0
      emit_inline(line)
      in_bucket = 0
      next
    }

    in_review && in_phase && $0 ~ ("^[[:space:]][[:space:]][[:space:]][[:space:]]" bucket ":[[:space:]]*(#.*)?$") {
      in_bucket = 1
      next
    }

    in_review && in_phase && in_bucket && /^[[:space:]][[:space:]][[:space:]][[:space:]][A-Za-z0-9_-]+:[[:space:]]*/ {
      in_bucket = 0
    }

    in_review && in_phase && in_bucket && /^[[:space:]][[:space:]][[:space:]][[:space:]][[:space:]][[:space:]]-[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      print trim(line)
      next
    }

    in_review && in_phase && in_bucket && !/^[[:space:]][[:space:]][[:space:]][[:space:]][[:space:]][[:space:]]-[[:space:]]*/ && !/^[[:space:]]*#/ && !/^[[:space:]]*$/ {
      in_bucket = 0
    }
  ' "$config_file"
}

workflow_config_review_legacy_list() {
  local config_file="$1"
  local key="$2"

  [ -f "$config_file" ] || return 0

  awk -v key="$key" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^["'"'"']|["'"'"']$/, "", value)
      return value
    }

    function emit_inline(value, count, idx, entries) {
      gsub(/[[:space:]]+#.*$/, "", value)
      gsub(/^[^[]*\[/, "", value)
      gsub(/\].*$/, "", value)
      count = split(value, entries, ",")
      for (idx = 1; idx <= count; idx++) {
        entries[idx] = trim(entries[idx])
        if (entries[idx] != "") print entries[idx]
      }
    }

    /^review:[[:space:]]*(#.*)?$/ {
      in_review = 1
      in_list = 0
      next
    }

    in_review && /^[^[:space:]#].*:[[:space:]]*/ {
      in_review = 0
      in_list = 0
    }

    in_review && $0 ~ ("^[[:space:]][[:space:]]" key ":[[:space:]]*\\[") {
      line = $0
      emit_inline(line)
      in_list = 0
      next
    }

    in_review && $0 ~ ("^[[:space:]][[:space:]]" key ":[[:space:]]*(#.*)?$") {
      in_list = 1
      next
    }

    in_review && in_list && /^[[:space:]][[:space:]][A-Za-z0-9_-]+:[[:space:]]*/ {
      in_list = 0
    }

    in_review && in_list && /^[[:space:]][[:space:]][[:space:]][[:space:]]-[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      print trim(line)
      next
    }

    in_review && in_list && !/^[[:space:]][[:space:]][[:space:]][[:space:]]-[[:space:]]*/ && !/^[[:space:]]*#/ && !/^[[:space:]]*$/ {
      in_list = 0
    }
  ' "$config_file"
}

workflow_config_review_nested_list_declared() {
  local config_file="$1"
  local phase="$2"
  local key="$3"

  [ -f "$config_file" ] || return 1

  awk -v phase="$phase" -v key="$key" '
    BEGIN { found = 0 }

    /^review:[[:space:]]*(#.*)?$/ {
      in_review = 1
      in_phase = 0
      in_list = 0
      next
    }

    in_review && /^[^[:space:]#].*:[[:space:]]*/ {
      in_review = 0
      in_phase = 0
      in_list = 0
    }

    in_review && $0 ~ ("^[[:space:]][[:space:]]" phase ":[[:space:]]*(#.*)?$") {
      in_phase = 1
      in_list = 0
      next
    }

    in_phase && /^[[:space:]][[:space:]][A-Za-z0-9_-]+:[[:space:]]*/ && $0 !~ ("^[[:space:]][[:space:]]" phase ":[[:space:]]*") {
      in_phase = 0
      in_list = 0
    }

    in_phase && $0 ~ ("^[[:space:]][[:space:]][[:space:]][[:space:]]" key ":[[:space:]]*\\[") {
      found = 1
      exit
    }

    in_phase && $0 ~ ("^[[:space:]][[:space:]][[:space:]][[:space:]]" key ":[[:space:]]*(#.*)?$") {
      in_list = 1
      next
    }

    in_list && /^[[:space:]][[:space:]][[:space:]][[:space:]][A-Za-z0-9_-]+:[[:space:]]*/ {
      in_list = 0
    }

    in_list && /^[[:space:]][[:space:]][[:space:]][[:space:]][[:space:]][[:space:]]-[[:space:]]*/ {
      found = 1
      exit
    }

    END { exit found ? 0 : 1 }
  ' "$config_file"
}

workflow_config_review_local_list_if_declared() {
  local config_file="$1"
  local phase="$2"
  local key="$3"
  local local_file

  workflow_is_default_config_file "$config_file" || return 1
  local_file="$(workflow_local_config_file)"
  workflow_config_review_nested_list_declared "$local_file" "$phase" "$key" || return 1
  workflow_config_review_nested_list "$local_file" "$phase" "$key"
}

workflow_config_review_on_draft_runner() {
  local config_file="${1:-$(workflow_config_file)}"

  [ -f "$config_file" ] || return 0

  if workflow_config_review_local_list_if_declared "$config_file" on_draft runner; then
    return 0
  fi

  if workflow_config_review_nested_list "$config_file" on_draft runner | grep -q .; then
    workflow_config_review_nested_list "$config_file" on_draft runner
  else
    workflow_config_review_legacy_list "$config_file" internal_reviewers
  fi
}

workflow_config_review_on_draft_github() {
  local config_file="${1:-$(workflow_config_file)}"

  [ -f "$config_file" ] || return 0

  if workflow_config_review_local_list_if_declared "$config_file" on_draft github; then
    return 0
  fi

  if workflow_config_review_nested_list "$config_file" on_draft github | grep -q .; then
    workflow_config_review_nested_list "$config_file" on_draft github
    return 0
  fi

  if workflow_config_review_legacy_list "$config_file" phase_after_clean | grep -q .; then
    awk '
      NR == FNR {
        exclude[$0] = 1
        next
      }

      !($0 in exclude)
    ' \
      <(workflow_config_review_legacy_list "$config_file" phase_after_clean) \
      <(workflow_config_review_legacy_list "$config_file" platforms)
  fi
}

workflow_config_review_on_ready_github() {
  local config_file="${1:-$(workflow_config_file)}"

  [ -f "$config_file" ] || return 0

  if workflow_config_review_local_list_if_declared "$config_file" on_ready github; then
    return 0
  fi

  if workflow_config_review_nested_list "$config_file" on_ready github | grep -q .; then
    workflow_config_review_nested_list "$config_file" on_ready github
  elif workflow_config_review_legacy_list "$config_file" phase_after_clean | grep -q .; then
    workflow_config_review_legacy_list "$config_file" phase_after_clean
  else
    workflow_config_review_legacy_list "$config_file" platforms
  fi
}

workflow_config_review_platforms() {
  local config_file="${1:-$(workflow_config_file)}"

  [ -f "$config_file" ] || return 0

  workflow_config_review_on_draft_github "$config_file"
  workflow_config_review_on_ready_github "$config_file"
}

workflow_config_review_phase_after_clean_platforms() {
  local config_file="${1:-$(workflow_config_file)}"

  [ -f "$config_file" ] || return 0

  workflow_config_review_on_ready_github "$config_file"
}

workflow_repository_mode() {
  local repo_root="${1:-$(workflow_repo_root)}"

  python3 "$(workflow_config_resolver_script)" mode --repo-root "$repo_root"
}

workflow_repository_context() {
  local target_repo="${1:-}"
  local repo_root="${2:-$(workflow_repo_root)}"
  local args=(resolve --repo-root "$repo_root")

  if [ -n "$target_repo" ]; then
    args+=(--repo "$target_repo")
  fi

  python3 "$(workflow_config_resolver_script)" "${args[@]}"
}

workflow_validate_repository_context() {
  local target_repo="${1:-}"
  local repo_root="${2:-$(workflow_repo_root)}"
  local require_local="${3:-}"
  local args=(validate --repo-root "$repo_root")

  if [ -n "$target_repo" ]; then
    args+=(--repo "$target_repo")
  fi
  if [ "$require_local" = "--require-local" ] || [ "$require_local" = "require-local" ]; then
    args+=(--require-local)
  fi

  python3 "$(workflow_config_resolver_script)" "${args[@]}"
}

workflow_review_override_context() {
  local repo_root="${1:-$(workflow_repo_root)}"

  python3 "$(workflow_config_resolver_script)" review-overrides --repo-root "$repo_root"
}

workflow_config_provider() {
  local section="$1"
  local config_file="${2:-$(workflow_config_file)}"

  [ -f "$config_file" ] || return 0

  awk -v section="$section" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^["'"'"']|["'"'"']$/, "", value)
      return value
    }

    $0 ~ ("^" section ":[[:space:]]*$") {
      in_section = 1
      next
    }

    in_section && /^[^[:space:]#].*:[[:space:]]*$/ {
      exit
    }

    in_section && /^[[:space:]][[:space:]]provider:[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*provider:[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      print trim(line)
      exit
    }
  ' "$config_file"
}

workflow_config_field() {
  local section="$1"
  local field="$2"
  local config_file="${3:-$(workflow_config_file)}"

  [ -f "$config_file" ] || return 0

  awk -v section="$section" -v field="$field" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^["'"'"']|["'"'"']$/, "", value)
      return value
    }

    $0 ~ ("^" section ":[[:space:]]*$") {
      in_section = 1
      next
    }

    in_section && /^[^[:space:]#].*:[[:space:]]*/ {
      exit
    }

    in_section {
      # Match "  <field>: <value>" — two-space indent, exact field name, optional comment
      pattern = "^[[:space:]][[:space:]]" field ":[[:space:]]*"
      if ($0 ~ pattern) {
        line = $0
        sub(/^[[:space:]]*[^[:space:]]*:[[:space:]]*/, "", line)
        sub(/[[:space:]]+#.*$/, "", line)
        print trim(line)
        exit
      }
    }
  ' "$config_file"
}

workflow_issue_tracker_project_number() {
  workflow_config_field issue_tracker project_number
}

# workflow_resolve_github_project_owner
#
# Resolves the GitHub project owner through a tiered fallback chain.
# Prints the resolved owner name, or an empty string when all tiers fail.
# Returns 0 in all cases (non-blocking).
#
# Resolution order:
#   1. GITHUB_PROJECT_OWNER env var (fastest; always preferred)
#   2. gh repo view API call
#   3. Parse owner from git remote get-url origin (SSH or HTTPS format)
#
# Rationale for Tier 3: when workflow-lib.sh is sourced directly in a
# subagent shell (not invoked via a wrapper script), GITHUB_TOKEN may be
# absent and gh repo view fails silently. The git remote URL is available
# in any cloned repository regardless of gh authentication state.
#
# Emits a warning to stderr only when all three tiers fail, so callers can
# surface the failure visibly rather than silently skipping tracker updates.
workflow_resolve_github_project_owner() {
  # Tier 1: explicit env var
  if [ -n "${GITHUB_PROJECT_OWNER:-}" ]; then
    printf '%s' "$GITHUB_PROJECT_OWNER"
    return 0
  fi

  # Tier 2: gh repo view API
  local owner
  owner="$(gh repo view --json owner --jq '.owner.login' 2>/dev/null || true)"
  if [ -n "$owner" ]; then
    printf '%s' "$owner"
    return 0
  fi

  # Tier 3: parse owner from git remote URL
  # Supports common GitHub remote URL formats:
  #   HTTPS:             https://github.com/owner/repo.git
  #   Credentialed HTTPS: https://user@github.com/owner/repo.git
  #   SCP-style SSH:     git@github.com:owner/repo.git
  #   SSH URL:           ssh://git@github.com/owner/repo.git
  local remote_url
  remote_url="$(git remote get-url origin 2>/dev/null || true)"
  if [ -n "$remote_url" ]; then
    case "$remote_url" in
      https://*github.com/*)
        # Strip protocol and optional user@ prefix, then extract owner segment
        owner="${remote_url#https://}"
        owner="${owner#*@}"          # remove optional user@ for credentialed HTTPS
        owner="${owner#github.com/}" # remove host
        owner="${owner%%/*}"
        ;;
      git@github.com:*)
        owner="${remote_url#git@github.com:}"
        owner="${owner%%/*}"
        ;;
      ssh://git@github.com/*)
        owner="${remote_url#ssh://git@github.com/}"
        owner="${owner%%/*}"
        ;;
    esac
    if [ -n "$owner" ]; then
      printf '%s' "$owner"
      return 0
    fi
  fi

  # All tiers failed — emit a visible warning so the caller knows why the
  # tracker update was skipped, rather than silently swallowing the failure.
  echo "Warning: could not resolve GITHUB_PROJECT_OWNER from env var, 'gh repo view', or git remote URL. Set GITHUB_PROJECT_OWNER to enable tracker status updates." >&2
  printf ''
  return 0
}

workflow_resolve_github_repo_owner() {
  local owner
  if ! owner="$(gh repo view --json owner --jq '.owner.login' 2>/dev/null)"; then
    owner=""
  fi
  if [ -n "$owner" ]; then
    printf '%s' "$owner"
    return 0
  fi

  local remote_url
  if ! remote_url="$(git remote get-url origin 2>/dev/null)"; then
    remote_url=""
  fi
  if [ -n "$remote_url" ]; then
    local remote_path
    remote_path=""
    case "$remote_url" in
      https://github.com/*)
        remote_path="${remote_url#https://github.com/}"
        ;;
      https://*@github.com/*)
        remote_path="${remote_url#https://*@github.com/}"
        ;;
      git@github.com:*)
        remote_path="${remote_url#git@github.com:}"
        ;;
      ssh://git@github.com/*)
        remote_path="${remote_url#ssh://git@github.com/}"
        ;;
    esac
    owner="${remote_path%%/*}"
    if workflow_is_valid_github_owner "$owner" && workflow_remote_path_has_single_repo "$remote_path"; then
      printf '%s' "$owner"
      return 0
    fi
  fi

  echo "Warning: could not resolve GitHub repository owner from 'gh repo view' or git remote URL." >&2
  printf ''
  return 0
}

workflow_resolve_github_repo_name() {
  local repo_name
  if ! repo_name="$(gh repo view --json name --jq '.name' 2>/dev/null)"; then
    repo_name=""
  fi
  if [ -n "$repo_name" ]; then
    printf '%s' "$repo_name"
    return 0
  fi

  local remote_url
  if ! remote_url="$(git remote get-url origin 2>/dev/null)"; then
    remote_url=""
  fi
  if [ -n "$remote_url" ]; then
    local remote_path path_remainder
    remote_path=""
    case "$remote_url" in
      https://github.com/*)
        remote_path="${remote_url#https://github.com/}"
        ;;
      https://*@github.com/*)
        remote_path="${remote_url#https://*@github.com/}"
        ;;
      git@github.com:*)
        remote_path="${remote_url#git@github.com:}"
        ;;
      ssh://git@github.com/*)
        remote_path="${remote_url#ssh://git@github.com/}"
        ;;
    esac
    path_remainder="${remote_path#*/}"
    repo_name="${path_remainder%.git}"
    if workflow_remote_path_has_single_repo "$remote_path" && workflow_is_valid_github_repo_name "$repo_name"; then
      printf '%s' "$repo_name"
      return 0
    fi
  fi

  echo "Warning: could not resolve GitHub repository name from 'gh repo view' or git remote URL." >&2
  printf ''
  return 0
}

workflow_remote_path_has_single_repo() {
  local remote_path="$1"
  local path_remainder

  case "$remote_path" in
    ''|*'?'*|*'#'*)
      return 1
      ;;
  esac
  case "$remote_path" in
    */*)
      ;;
    *)
      return 1
      ;;
  esac

  path_remainder="${remote_path#*/}"
  case "$path_remainder" in
    ''|*/*)
      return 1
      ;;
  esac

  return 0
}

workflow_is_valid_github_owner() {
  local owner="$1"
  case "$owner" in
    ''|-*|*-|*[!A-Za-z0-9-]*)
      return 1
      ;;
  esac
  return 0
}

workflow_is_valid_github_repo_name() {
  local repo_name="$1"
  case "$repo_name" in
    ''|'.'|'..'|*[!A-Za-z0-9._-]*)
      return 1
      ;;
  esac
  return 0
}

workflow_is_valid_github_repo_slug() {
  local repo_slug="$1"
  local owner="${repo_slug%%/*}"
  local repo_name="${repo_slug#*/}"

  [ "$owner/$repo_name" = "$repo_slug" ] || return 1
  workflow_is_valid_github_owner "$owner" || return 1
  workflow_is_valid_github_repo_name "$repo_name" || return 1
  return 0
}

# workflow_issue_tracker_custom_field <key> [config_file]
#
# Reads issue_tracker.custom_fields.<key> from .ai-dev-workflow.yaml.
# Prints the value, or empty string when:
#   - The config file is absent
#   - The custom_fields subsection is absent
#   - The key is absent within custom_fields
# Returns 0 in all cases (non-blocking).
workflow_issue_tracker_custom_field() {
  local key="$1"
  local config_file="${2:-$(workflow_config_file)}"

  [ -f "$config_file" ] || return 0

  awk -v key="$key" '
    function trim(value) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      gsub(/^["'"'"']|["'"'"']$/, "", value)
      return value
    }

    /^issue_tracker:[[:space:]]*(#.*)?$/ {
      in_section = 1
      in_custom = 0
      next
    }

    in_section && /^[^[:space:]#]/ {
      in_section = 0
      in_custom = 0
    }

    in_section && /^[[:space:]][[:space:]]custom_fields:[[:space:]]*(#.*)?$/ {
      in_custom = 1
      next
    }

    in_section && in_custom && /^[[:space:]][[:space:]][A-Za-z0-9_-]/ {
      if ($0 !~ /^[[:space:]][[:space:]][[:space:]][[:space:]]/) {
        in_custom = 0
      }
    }

    in_section && in_custom && /^[[:space:]][[:space:]][[:space:]][[:space:]]/ {
      pattern = "^[[:space:]][[:space:]][[:space:]][[:space:]]" key ":[[:space:]]*"
      if ($0 ~ pattern) {
        line = $0
        sub(/^[[:space:]]*[^[:space:]]*:[[:space:]]*/, "", line)
        sub(/[[:space:]]+#.*$/, "", line)
        print trim(line)
        exit
      }
    }
  ' "$config_file"
}

workflow_issue_tracker_provider_raw() {
  workflow_config_provider issue_tracker
}

workflow_normalize_issue_tracker_provider() {
  local raw="$1"
  printf '%s' "$raw" | tr '[:upper:]' '[:lower:]' | tr '-' '_'
}

# emit_linear_deferred_action <action_type> <issue_id> [key=value]
#
# Prints a structured TRACKER_ACTION_REQUIRED= line to stdout so the orchestrator
# can collect and apply the deferred Linear action via MCP.
#
# Used for set_status and read_status actions only. The create_item action is
# emitted directly by add-backlog-item.sh with "title=<title>" instead of
# "issue=<id>", because for new items there is no issue ID yet.
#
# The third argument must be a single "key=value" pair. When the value portion
# contains spaces, it is single-quoted in the output so that parsers can
# unambiguously extract the value (e.g. `target_status='Plan in Review'`).
# Linear status names do not contain single quotes, so this quoting is safe for
# all controlled-vocabulary values produced by the workflow.
#
# Examples:
#   emit_linear_deferred_action set_status ENG-123 "target_status=Plan in Review"
#   emit_linear_deferred_action read_status ENG-123
#
# Output format: TRACKER_ACTION_REQUIRED=<action_type> issue=<issue_id>[ key='value']
emit_linear_deferred_action() {
  local action_type="$1"
  local issue_id="$2"
  local extra="${3:-}"
  if [ -z "$extra" ]; then
    printf 'TRACKER_ACTION_REQUIRED=%s issue=%s\n' "$action_type" "$issue_id"
    return 0
  fi
  # Split at the first '=' to separate the key from the value.
  local _ela_key _ela_val
  _ela_key="${extra%%=*}"
  _ela_val="${extra#*=}"
  # Single-quote values that contain spaces so downstream parsers can
  # unambiguously extract the value without splitting on internal whitespace.
  case "$_ela_val" in
    *' '*)
      printf "TRACKER_ACTION_REQUIRED=%s issue=%s %s='%s'\n" \
        "$action_type" "$issue_id" "$_ela_key" "$_ela_val"
      ;;
    *)
      printf 'TRACKER_ACTION_REQUIRED=%s issue=%s %s=%s\n' \
        "$action_type" "$issue_id" "$_ela_key" "$_ela_val"
      ;;
  esac
}

# workflow_emit_deferred_tracker_action — public alias for emit_linear_deferred_action
workflow_emit_deferred_tracker_action() {
  emit_linear_deferred_action "$@"
}

# Prints a coarse destination bucket for backlog creation: github | linear | other | none
# none: missing provider, none, or empty string
workflow_backlog_destination_kind() {
  local raw normalized
  raw="$(workflow_issue_tracker_provider_raw)"
  normalized="$(workflow_normalize_issue_tracker_provider "$raw")"
  if [ -z "$normalized" ] && [ -z "$raw" ]; then
    printf 'none\n'
    return 0
  fi
  case "$normalized" in
    ''|'none')
      printf 'none\n'
      ;;
    linear)
      printf 'linear\n'
      ;;
    github_issues|github-issues|github_projects|github-projects)
      printf 'github\n'
      ;;
    *)
      printf 'other\n'
      ;;
  esac
}

workflow_status_order() {
  case "$1" in
    Backlog) printf '0\n' ;;
    "Writing Spec") printf '1\n' ;;
    "Spec in Review") printf '2\n' ;;
    "Spec Ready") printf '3\n' ;;
    "Writing Plan") printf '4\n' ;;
    "Plan in Review") printf '5\n' ;;
    "Plan Ready") printf '6\n' ;;
    "In Development") printf '7\n' ;;
    "Development in Review") printf '8\n' ;;
    Merged) printf '9\n' ;;
    Released) printf '10\n' ;;
    *) printf -- '-1\n' ;;
  esac
}

# is_terminal_tracker_status <status>
#
# Returns 0 (true) if the status is a terminal state that means no further
# workflow work is needed: Released, Merged, or Cancelled.
# Returns 1 (false) for any other status (including empty/unknown).
is_terminal_tracker_status() {
  local status="$1"
  case "$status" in
    Released|Merged|Cancelled) return 0 ;;
    *) return 1 ;;
  esac
}

# Script-level cache for GitHub Projects Status field metadata.
__workflow_github_project_id_cache_owner=""
__workflow_github_project_id_cache_number=""
__workflow_github_project_id_cache_id=""
__workflow_project_status_field_cache_project_id=""
__workflow_project_status_field_cache_json=""
__workflow_project_type_field_cache_project_id=""
__workflow_project_type_field_cache_preferred=""
__workflow_project_type_field_cache_json=""
# Cache for named single-select fields (Priority, Size, etc.) — indexed by
# "<project_id>:<field_name>" stored in parallel arrays.
__workflow_project_named_field_cache_keys=()
__workflow_project_named_field_cache_vals=()
__workflow_last_gh_stdout=""
__workflow_last_gh_stderr=""

workflow_run_gh_capture_stderr() {
  local stderr_file
  __workflow_last_gh_stdout=""
  __workflow_last_gh_stderr=""

  if ! stderr_file="$(mktemp "${TMPDIR:-/tmp}/workflow-gh-stderr.XXXXXX")"; then
    if __workflow_last_gh_stdout="$(gh "$@")"; then
      return 0
    fi
    return 1
  fi

  if __workflow_last_gh_stdout="$(gh "$@" 2>"$stderr_file")"; then
    rm -f "$stderr_file"
    return 0
  fi

  if [ -f "$stderr_file" ]; then
    if ! __workflow_last_gh_stderr="$(cat "$stderr_file")"; then
      __workflow_last_gh_stderr="could not read captured gh stderr file '${stderr_file}'"
    fi
  else
    __workflow_last_gh_stderr="captured gh stderr file '${stderr_file}' is missing"
  fi
  rm -f "$stderr_file"
  return 1
}

workflow_print_captured_gh_stderr() {
  if [ -n "$__workflow_last_gh_stderr" ]; then
    printf '%s\n' "$__workflow_last_gh_stderr" | sed 's/^/  gh: /' >&2
  fi
}

workflow_github_project_id() {
  local project_owner="$1"
  local project_number="$2"
  local response project_id user_lookup_stderr org_lookup_stderr

  if [ -z "$project_owner" ] || [ -z "$project_number" ]; then
    printf ''
    return 0
  fi

  if [ "$__workflow_github_project_id_cache_owner" != "$project_owner" ] || \
     [ "$__workflow_github_project_id_cache_number" != "$project_number" ] || \
     [ -z "$__workflow_github_project_id_cache_id" ]; then
    # shellcheck disable=SC2016 # GraphQL variables are expanded by GitHub, not by Bash.
    if workflow_run_gh_capture_stderr api graphql \
      -f owner="$project_owner" \
      -F projectNumber="$project_number" \
      -f query='
        query($owner: String!, $projectNumber: Int!) {
          user(login: $owner) { projectV2(number: $projectNumber) { id } }
        }
      '; then
      response="$__workflow_last_gh_stdout"
    else
      user_lookup_stderr="$__workflow_last_gh_stderr"
      response=""
    fi

    project_id="$(printf '%s' "$response" | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read(), strict=False)
except Exception:
    sys.exit(0)
project = ((data.get('data') or {}).get('user') or {}).get('projectV2') or {}
print(project.get('id') or '', end='')
" 2>/dev/null || true)"

    if [ -z "$project_id" ]; then
      # shellcheck disable=SC2016 # GraphQL variables are expanded by GitHub, not by Bash.
      if workflow_run_gh_capture_stderr api graphql \
        -f owner="$project_owner" \
        -F projectNumber="$project_number" \
        -f query='
          query($owner: String!, $projectNumber: Int!) {
            organization(login: $owner) { projectV2(number: $projectNumber) { id } }
          }
        '; then
        response="$__workflow_last_gh_stdout"
      else
        org_lookup_stderr="$__workflow_last_gh_stderr"
        response=""
      fi

      project_id="$(printf '%s' "$response" | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read(), strict=False)
except Exception:
    sys.exit(0)
project = ((data.get('data') or {}).get('organization') or {}).get('projectV2') or {}
print(project.get('id') or '', end='')
" 2>/dev/null || true)"
    fi

    if [ -z "$project_id" ] && { [ -n "${user_lookup_stderr:-}" ] || [ -n "${org_lookup_stderr:-}" ]; }; then
      echo "Warning: GraphQL project ID lookup failed for project owner '${project_owner}' and project #${project_number}." >&2
      if [ -n "${user_lookup_stderr:-}" ]; then
        printf '%s\n' "$user_lookup_stderr" | sed 's/^/  gh user: /' >&2
      fi
      if [ -n "${org_lookup_stderr:-}" ]; then
        printf '%s\n' "$org_lookup_stderr" | sed 's/^/  gh org: /' >&2
      fi
    fi

    __workflow_github_project_id_cache_owner="$project_owner"
    __workflow_github_project_id_cache_number="$project_number"
    __workflow_github_project_id_cache_id="$project_id"
  fi

  printf '%s' "$__workflow_github_project_id_cache_id"
}

# workflow_github_project_item_for_issue <issue_number> <project_number>
#
# Prints compact JSON with project item details for one issue in one project:
#   {"item_id":"...","project_id":"...","status":"...","type":"..."}
#
# This intentionally uses repository.issue(...).projectItems instead of
# `gh project item-list` so single-item status reads/updates do not paginate the
# entire board and drain the GraphQL budget.
workflow_github_project_item_for_issue() {
  local issue_number="$1"
  local project_number="$2"
  local project_owner project_id repo_owner repo_name response
  local cursor page_state item_json has_next end_cursor page_count line missing_fields type_field_name
  local -a graphql_args

  case "$issue_number" in
    ''|*[!0-9]*)
      echo "Warning: issue number '${issue_number}' is not numeric; tracker status not read." >&2
      printf ''
      return 0
      ;;
  esac
  case "$project_number" in
    ''|*[!0-9]*)
      echo "Warning: project number '${project_number}' is not numeric; tracker status not read." >&2
      printf ''
      return 0
      ;;
  esac

  project_owner="$(workflow_resolve_github_project_owner)"
  project_id="$(workflow_github_project_id "$project_owner" "$project_number")"
  repo_owner="$(workflow_resolve_github_repo_owner)"
  repo_name="$(workflow_resolve_github_repo_name)"
  if [ -z "$project_id" ] || [ -z "$repo_owner" ] || [ -z "$repo_name" ]; then
    printf ''
    return 0
  fi
  type_field_name="$(workflow_issue_tracker_custom_field type_field "$(workflow_effective_config_file || true)")"

  cursor=""
  page_count=0
  while :; do
    graphql_args=(
      api graphql
      -f owner="$repo_owner"
      -f repo="$repo_name"
      -F issueNumber="$issue_number"
      -f typeFieldName="$type_field_name"
    )
    if [ -n "$cursor" ]; then
      graphql_args+=(-f after="$cursor")
    fi
    # shellcheck disable=SC2016 # GraphQL variables are expanded by GitHub, not by Bash.
    graphql_args+=(
      -f query='
        query($owner: String!, $repo: String!, $issueNumber: Int!, $typeFieldName: String!, $after: String) {
          repository(owner: $owner, name: $repo) {
            issue(number: $issueNumber) {
              projectItems(first: 100, after: $after) {
                nodes {
                  id
                  project { id number }
                  content {
                    ... on Issue { issueType { name } }
                  }
                  status: fieldValueByName(name: "Status") {
                    ... on ProjectV2ItemFieldSingleSelectValue { name }
                  }
                  configuredType: fieldValueByName(name: $typeFieldName) {
                    ... on ProjectV2ItemFieldSingleSelectValue { name }
                  }
                  customType: fieldValueByName(name: "Custom Type") {
                    ... on ProjectV2ItemFieldSingleSelectValue { name }
                  }
                  compactCustomType: fieldValueByName(name: "CustomType") {
                    ... on ProjectV2ItemFieldSingleSelectValue { name }
                  }
                  type: fieldValueByName(name: "Type") {
                    ... on ProjectV2ItemFieldSingleSelectValue { name }
                  }
                }
                pageInfo { hasNextPage endCursor }
              }
            }
          }
        }
      '
    )

    if ! workflow_run_gh_capture_stderr "${graphql_args[@]}"; then
      echo "Warning: GraphQL project item lookup failed for issue #${issue_number}; tracker status not read." >&2
      workflow_print_captured_gh_stderr
      printf ''
      return 0
    fi
    response="$__workflow_last_gh_stdout"

    if ! page_state="$(printf '%s' "$response" | python3 -c "
import json, sys
project_id = sys.argv[1]
preferred = sys.argv[2]
try:
    data = json.loads(sys.stdin.read(), strict=False)
except Exception:
    sys.exit(2)
issue = (((data.get('data') or {}).get('repository') or {}).get('issue') or {})
project_items = issue.get('projectItems') or {}
match = ''
missing_fields = ''
for item in project_items.get('nodes') or []:
    project = item.get('project') or {}
    if project.get('id') == project_id:
        status_value = item.get('status') or item.get('fieldValueByName') or {}
        content = item.get('content') or {}
        native_type = content.get('issueType') if isinstance(content, dict) else None
        type_candidates = []
        if preferred:
            type_candidates.append(item.get('configuredType') or {})
        type_candidates.extend([
            native_type or {},
            item.get('customType') or {},
            item.get('compactCustomType') or {},
            item.get('type') or {},
        ])
        type_value = {}
        for candidate in type_candidates:
            if candidate.get('name'):
                type_value = candidate
                break
        missing = []
        if not status_value.get('name'):
            missing.append('Status')
        if not type_value.get('name'):
            missing.append('Type')
        missing_fields = ','.join(missing)
        match = json.dumps({
            'item_id': item.get('id') or '',
            'project_id': project.get('id') or '',
            'status': status_value.get('name') or '',
            'type': type_value.get('name') or '',
        }, separators=(',', ':'))
        break
page_info = project_items.get('pageInfo') or {}
has_next = 'true' if page_info.get('hasNextPage') else 'false'
end_cursor = page_info.get('endCursor') or ''
print('ITEM=' + match)
print('MISSING_FIELDS=' + missing_fields)
print('HAS_NEXT=' + has_next)
print('END_CURSOR=' + end_cursor)
" "$project_id" "$type_field_name" 2>/dev/null)"; then
      echo "Warning: could not parse GraphQL project item response for issue #${issue_number}; tracker status not read." >&2
      printf ''
      return 0
    fi

    item_json=""
    has_next="false"
    end_cursor=""
    missing_fields=""
    while IFS= read -r line; do
      case "$line" in
        ITEM=*) item_json="${line#ITEM=}" ;;
        MISSING_FIELDS=*) missing_fields="${line#MISSING_FIELDS=}" ;;
        HAS_NEXT=*) has_next="${line#HAS_NEXT=}" ;;
        END_CURSOR=*) end_cursor="${line#END_CURSOR=}" ;;
      esac
    done <<EOF
$page_state
EOF
    if [ -n "$item_json" ]; then
      case ",$missing_fields," in
        *",Status,"*)
          echo "Warning: project item for issue #${issue_number} has no Status value. The workflow expects a single-select field named exactly 'Status'." >&2
          ;;
      esac
      case ",$missing_fields," in
        *",Type,"*)
          echo "Warning: project item for issue #${issue_number} has no Type value. The workflow expects a single-select field named exactly 'Type'." >&2
          ;;
      esac
      printf '%s' "$item_json"
      return 0
    fi
    if [ "$has_next" != "true" ] || [ -z "$end_cursor" ]; then
      break
    fi
    page_count=$((page_count + 1))
    if [ "$page_count" -ge 20 ]; then
      echo "Warning: project item lookup exceeded pagination limit for issue #${issue_number}; tracker status not read." >&2
      break
    fi
    cursor="$end_cursor"
  done

  printf ''
}

workflow_github_project_status_field_json() {
  local project_id="$1"
  local response cursor page_state field_json has_next end_cursor page_count line
  local -a graphql_args

  if [ -z "$project_id" ]; then
    printf ''
    return 0
  fi

  if [ "$__workflow_project_status_field_cache_project_id" != "$project_id" ] || \
     [ -z "$__workflow_project_status_field_cache_json" ]; then
    __workflow_project_status_field_cache_json=""
    cursor=""
    page_count=0
    while :; do
      graphql_args=(
        api graphql
        -f projectId="$project_id"
      )
      if [ -n "$cursor" ]; then
        graphql_args+=(-f after="$cursor")
      fi
      # shellcheck disable=SC2016 # GraphQL variables are expanded by GitHub, not by Bash.
      graphql_args+=(
        -f query='
          query($projectId: ID!, $after: String) {
            node(id: $projectId) {
              ... on ProjectV2 {
                fields(first: 100, after: $after) {
                  nodes {
                    ... on ProjectV2SingleSelectField {
                      id
                      name
                      options { id name }
                    }
                  }
                  pageInfo { hasNextPage endCursor }
                }
              }
            }
          }
        '
      )

      if ! workflow_run_gh_capture_stderr "${graphql_args[@]}"; then
        echo "Warning: GraphQL project Status field lookup failed for project '${project_id}'." >&2
        workflow_print_captured_gh_stderr
        printf ''
        return 0
      fi
      response="$__workflow_last_gh_stdout"

      if ! page_state="$(printf '%s' "$response" | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read(), strict=False)
except Exception:
    sys.exit(2)
field_connection = (((data.get('data') or {}).get('node') or {}).get('fields') or {})
fields = field_connection.get('nodes') or []
field_json = ''
for field in fields:
    if field.get('name') == 'Status':
        field_json = json.dumps({
            'field_id': field.get('id') or '',
            'options': {option.get('name') or '': option.get('id') or '' for option in field.get('options') or []},
        }, separators=(',', ':'))
        break
page_info = field_connection.get('pageInfo') or {}
has_next = 'true' if page_info.get('hasNextPage') else 'false'
end_cursor = page_info.get('endCursor') or ''
print('FIELD_JSON=' + field_json)
print('HAS_NEXT=' + has_next)
print('END_CURSOR=' + end_cursor)
" 2>/dev/null)"; then
        echo "Warning: could not parse GraphQL project Status field response for project '${project_id}'." >&2
        printf ''
        return 0
      fi

      field_json=""
      has_next="false"
      end_cursor=""
      while IFS= read -r line; do
        case "$line" in
          FIELD_JSON=*) field_json="${line#FIELD_JSON=}" ;;
          HAS_NEXT=*) has_next="${line#HAS_NEXT=}" ;;
          END_CURSOR=*) end_cursor="${line#END_CURSOR=}" ;;
        esac
      done <<EOF
$page_state
EOF
      if [ -n "$field_json" ]; then
        __workflow_project_status_field_cache_json="$field_json"
        break
      fi
      if [ "$has_next" != "true" ] || [ -z "$end_cursor" ]; then
        break
      fi
      page_count=$((page_count + 1))
      if [ "$page_count" -ge 20 ]; then
        echo "Warning: project Status field lookup exceeded pagination limit for project '${project_id}'." >&2
        break
      fi
      cursor="$end_cursor"
    done
    __workflow_project_status_field_cache_project_id="$project_id"
  fi

  printf '%s' "$__workflow_project_status_field_cache_json"
}

# workflow_github_project_type_field_json <project_id>
#
# Prints compact JSON for the GitHub Projects Type field metadata. Returns
# non-zero when the project ID is missing, the GraphQL fetch fails, the response
# cannot be parsed, pagination exceeds the guard limit, or the Type field is
# absent. Callers must treat those cases as explicit lookup failures.
workflow_github_project_type_field_json() {
  local project_id="$1"
  local preferred_field response cursor page_state field_json field_rank best_field_json best_field_rank has_next end_cursor page_count line
  local -a graphql_args

  preferred_field="$(workflow_issue_tracker_custom_field type_field "$(workflow_effective_config_file || true)")"

  if [ -z "$project_id" ]; then
    echo "Warning: project ID is empty; project Type field lookup cannot run." >&2
    printf ''
    return 1
  fi

  if [ "$__workflow_project_type_field_cache_project_id" != "$project_id" ] || \
     [ "$__workflow_project_type_field_cache_preferred" != "$preferred_field" ] || \
     [ -z "$__workflow_project_type_field_cache_json" ]; then
    __workflow_project_type_field_cache_json=""
    best_field_json=""
    best_field_rank=999
    cursor=""
    page_count=0
    while :; do
      graphql_args=(
        api graphql
        -f projectId="$project_id"
      )
      if [ -n "$cursor" ]; then
        graphql_args+=(-f after="$cursor")
      fi
      # shellcheck disable=SC2016 # GraphQL variables are expanded by GitHub, not by Bash.
      graphql_args+=(
        -f query='
          query($projectId: ID!, $after: String) {
            node(id: $projectId) {
              ... on ProjectV2 {
                fields(first: 100, after: $after) {
                  nodes {
                    ... on ProjectV2SingleSelectField {
                      id
                      name
                      options { id name }
                    }
                  }
                  pageInfo { hasNextPage endCursor }
                }
              }
            }
          }
        '
      )

      if ! workflow_run_gh_capture_stderr "${graphql_args[@]}"; then
        echo "Warning: GraphQL project Type field lookup failed for project '${project_id}'." >&2
        workflow_print_captured_gh_stderr
        printf ''
        return 1
      fi
      response="$__workflow_last_gh_stdout"

      if ! page_state="$(printf '%s' "$response" | python3 -c "
import json, sys
preferred = sys.argv[1]
try:
    data = json.loads(sys.stdin.read(), strict=False)
except Exception:
    sys.exit(2)
field_connection = (((data.get('data') or {}).get('node') or {}).get('fields') or {})
fields = field_connection.get('nodes') or []
field_json = ''
field_rank = 999
fields_by_name = {}
for field in fields:
    name = field.get('name') or ''
    if name:
        fields_by_name[name] = field
for rank, candidate in enumerate([preferred, 'Custom Type', 'CustomType', 'Type'], start=1):
    if not candidate:
        continue
    field = fields_by_name.get(candidate)
    if field:
        field_rank = rank
        field_json = json.dumps({
            'field_id': field.get('id') or '',
            'field_name': field.get('name') or '',
            'options': {option.get('name') or '': option.get('id') or '' for option in field.get('options') or []},
        }, separators=(',', ':'))
        break
page_info = field_connection.get('pageInfo') or {}
has_next = 'true' if page_info.get('hasNextPage') else 'false'
end_cursor = page_info.get('endCursor') or ''
print('FIELD_JSON=' + field_json)
print('FIELD_RANK=' + str(field_rank))
print('HAS_NEXT=' + has_next)
print('END_CURSOR=' + end_cursor)
" "$preferred_field" 2>/dev/null)"; then
        echo "Warning: could not parse GraphQL project Type field response for project '${project_id}'." >&2
        printf ''
        return 1
      fi

      field_json=""
      field_rank=999
      has_next="false"
      end_cursor=""
      while IFS= read -r line; do
        case "$line" in
          FIELD_JSON=*) field_json="${line#FIELD_JSON=}" ;;
          FIELD_RANK=*) field_rank="${line#FIELD_RANK=}" ;;
          HAS_NEXT=*) has_next="${line#HAS_NEXT=}" ;;
          END_CURSOR=*) end_cursor="${line#END_CURSOR=}" ;;
        esac
      done <<EOF
$page_state
EOF
      if [ -n "$field_json" ]; then
        if [ "$field_rank" -lt "$best_field_rank" ]; then
          best_field_json="$field_json"
          best_field_rank="$field_rank"
        fi
        if [ "$best_field_rank" -eq 1 ] || { [ -z "$preferred_field" ] && [ "$best_field_rank" -eq 2 ]; }; then
          break
        fi
      fi
      if [ "$has_next" != "true" ] || [ -z "$end_cursor" ]; then
        break
      fi
      page_count=$((page_count + 1))
      if [ "$page_count" -ge 20 ]; then
        echo "Warning: project Type field lookup exceeded pagination limit for project '${project_id}'." >&2
        printf ''
        return 1
      fi
      cursor="$end_cursor"
    done
    __workflow_project_type_field_cache_json="$best_field_json"
    if [ -z "$__workflow_project_type_field_cache_json" ]; then
      echo "Warning: project Type field not found for project '${project_id}'." >&2
      printf ''
      return 1
    fi
    __workflow_project_type_field_cache_project_id="$project_id"
    __workflow_project_type_field_cache_preferred="$preferred_field"
  fi

  printf '%s' "$__workflow_project_type_field_cache_json"
}

# get_tracker_status_for_issue <issue_number>
#
# Queries the configured issue tracker for the current Status of the given issue.
# Prints the status string (e.g. "Merged", "Released", "In Development").
# Prints an empty string when:
#   - provider is 'linear' (Linear status reads require MCP/API; not available in shell)
#   - project_number is unset in both GITHUB_PROJECT_NUMBER and .ai-dev-workflow.yaml
#   - The issue is not found in the project
#   - Any API call fails
# Returns 0 in all cases (non-blocking).
# Repository owner/name are resolved from `gh repo view` with a git-remote
# fallback; project ownership is not needed for the targeted item lookup.
# project_number falls back to issue_tracker.project_number in .ai-dev-workflow.yaml.
get_tracker_status_for_issue() {
  local issue_number="$1"
  local project_number item_json current_status

  # Provider routing: Linear status reads require MCP/API and cannot be
  # performed by this shell function. Emit a structured
  # TRACKER_ACTION_REQUIRED=read_status line so the orchestrator knows the
  # read was deferred (not silently empty). Callers that assign this function's
  # output to a variable must filter lines beginning with TRACKER_ACTION_REQUIRED=
  # to avoid treating the signal as a status string.
  local _gts_provider
  _gts_provider="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"
  if [ "$_gts_provider" = "linear" ]; then
    emit_linear_deferred_action "read_status" "$issue_number"
    return 0
  fi

  project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
  if [ -z "$project_number" ]; then
    printf ''
    return 0
  fi

  item_json="$(workflow_github_project_item_for_issue "$issue_number" "$project_number")"
  if [ -z "$item_json" ]; then
    printf ''
    return 0
  fi

  current_status=$(printf '%s' "$item_json" | python3 -c "
import json, sys
item = json.loads(sys.stdin.read(), strict=False)
print(item.get('status') or '', end='')
" 2>/dev/null || true)
  printf '%s' "${current_status:-}"
}

# get_tracker_type_for_issue <issue_number>
#
# Queries the configured GitHub Projects tracker for the current Type of the
# given issue. Prints an empty string for unsupported providers, missing project
# configuration, or a missing project item. Returns non-zero when project item
# JSON exists but cannot be parsed.
get_tracker_type_for_issue() {
  local issue_number="$1"
  local project_number item_json current_type

  local _gtt_provider
  _gtt_provider="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"
  if [ "$_gtt_provider" != "github_projects" ]; then
    printf ''
    return 0
  fi

  project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
  if [ -z "$project_number" ]; then
    printf ''
    return 0
  fi

  item_json="$(workflow_github_project_item_for_issue "$issue_number" "$project_number")"
  if [ -z "$item_json" ]; then
    printf ''
    return 0
  fi

  if ! current_type=$(printf '%s' "$item_json" | python3 -c "
import json, sys
item = json.loads(sys.stdin.read(), strict=False)
print(item.get('type') or '', end='')
"); then
    echo "Warning: could not parse project item Type for issue #${issue_number}." >&2
    printf ''
    return 1
  fi
  printf '%s' "${current_type:-}"
}

# ensure_on_project_board <issue_number> <initial_status>
#
# Idempotently ensures a GitHub issue is registered on the configured project board.
# - If the issue is already on the board, logs "already present" and returns 0.
# - If the issue is not on the board, adds it and sets its status to <initial_status>.
# - On any API or permissions failure, logs a warning and returns 0 (fail-open).
# - Must be called before update_tracker_status_best_effort in each agent completion
#   sequence so that the issue is board-registered before a status update is attempted.
ensure_on_project_board() {
  local issue_number="$1"
  local initial_status="$2"
  local owner project_number item_json repo_owner repo_name repo_url

  project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
  if [ -z "$project_number" ]; then
    echo "Warning: GITHUB_PROJECT_NUMBER not set and no project_number in .ai-dev-workflow.yaml; skipping board-membership check for issue #${issue_number}."
    return 0
  fi
  item_json="$(workflow_github_project_item_for_issue "$issue_number" "$project_number")"
  if [ -n "$item_json" ]; then
    echo "Board membership check: issue #${issue_number} already on project board."
    return 0
  fi

  # Issue is not on the board — add it.
  repo_owner="$(workflow_resolve_github_repo_owner)"
  repo_name="$(workflow_resolve_github_repo_name)"
  if [ -z "$repo_owner" ] || [ -z "$repo_name" ]; then
    echo "Warning: could not resolve repo URL; skipping board-add for issue #${issue_number}."
    return 0
  fi
  repo_url="https://github.com/${repo_owner}/${repo_name}"
  owner="$(workflow_resolve_github_project_owner)"
  if [ -z "$owner" ]; then
    owner="$repo_owner"
  fi

  if ! gh project item-add "$project_number" --owner "$owner" \
    --url "${repo_url}/issues/${issue_number}" 2>/dev/null; then
    echo "Warning: gh project item-add failed for issue #${issue_number}; continuing."
    return 0
  fi

  echo "Board membership check: issue #${issue_number} added to project board."

  # Set initial status for the newly added item.
  update_tracker_status_best_effort "$issue_number" "$initial_status"
}

# update_tracker_status_best_effort <issue_number> <status_label> [required_current_status] [allow-backward]
#
# Best-effort update for the configured issue tracker's Status field.
# Supports GitHub Projects (provider: github_projects) and emits actionable
# guidance for Linear (provider: linear), which requires MCP/API access.
# - Returns 0 in all warning/failure cases to avoid blocking caller flows.
# - Respects status progression ordering and never rolls status backward
#   (GitHub Projects path only; ordering is not enforced for Linear).
# - Owner is resolved via workflow_resolve_github_project_owner (see that function
#   for the tiered fallback chain: env var → gh repo view → git remote URL).
# - project_number falls back to issue_tracker.project_number in .ai-dev-workflow.yaml.
update_tracker_status_best_effort() {
  local issue_number="$1"
  local status_label="$2"
  local required_current_status="${3:-}"
  local allow_backward="${4:-false}"
  local project_number project_id field_json field_id option_id item_json item_id current_status
  local target_order current_order

  # Provider routing: Linear status updates require MCP/API and cannot be
  # performed automatically by this shell function. Emit a structured
  # TRACKER_ACTION_REQUIRED= deferred-action line so the orchestrator can
  # apply this transition via MCP.
  local _utsbe_provider
  _utsbe_provider="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"
  if [ "$_utsbe_provider" = "linear" ]; then
    emit_linear_deferred_action "set_status" "$issue_number" \
      "target_status=${status_label}"
    return 0
  fi

  project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
  if [ -z "$project_number" ]; then
    echo "Warning: GITHUB_PROJECT_NUMBER not set and no project_number in .ai-dev-workflow.yaml; skipping tracker status update."
    return 0
  fi

  item_json="$(workflow_github_project_item_for_issue "$issue_number" "$project_number")"
  item_id=$(printf '%s' "$item_json" | python3 -c "
import json, sys
item = json.loads(sys.stdin.read(), strict=False)
print(item.get('item_id') or '', end='')
" 2>/dev/null || true)
  project_id=$(printf '%s' "$item_json" | python3 -c "
import json, sys
item = json.loads(sys.stdin.read(), strict=False)
print(item.get('project_id') or '', end='')
" 2>/dev/null || true)
  if [ -z "$item_id" ]; then
    echo "Warning: issue #${issue_number} not found in project #${project_number}; skipping tracker status update."
    return 0
  fi
  if [ -z "$project_id" ]; then
    echo "Warning: could not resolve project ID for issue #${issue_number}; skipping tracker status update."
    return 0
  fi

  field_json="$(workflow_github_project_status_field_json "$project_id")"
  field_id=$(printf '%s' "$field_json" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read(), strict=False)
print(data.get('field_id') or '', end='')
" 2>/dev/null || true)
  option_id=$(printf '%s' "$field_json" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read(), strict=False)
print((data.get('options') or {}).get(sys.argv[1]) or '', end='')
" "$status_label" 2>/dev/null || true)
  if [ -z "$field_id" ] || [ -z "$option_id" ]; then
    echo "Warning: could not resolve Status field or option '${status_label}'; skipping tracker status update."
    return 0
  fi

  current_status=$(printf '%s' "$item_json" | python3 -c "
import json, sys
item = json.loads(sys.stdin.read(), strict=False)
print(item.get('status') or '', end='')
" 2>/dev/null || true)
  if [ -n "$required_current_status" ] && [ "$current_status" != "$required_current_status" ]; then
    echo "Issue #${issue_number} current status '${current_status:-unknown}' does not match required source status '${required_current_status}'; skipping update."
    return 0
  fi
  target_order="$(workflow_status_order "$status_label")"
  current_order="$(workflow_status_order "$current_status")"
  if [ -n "$current_status" ] && [ "$current_order" -eq -1 ] && [ -z "$required_current_status" ]; then
    echo "Warning: Issue #${issue_number} current status '${current_status}' is unrecognized; skipping update to '${status_label}' to avoid silent state corruption. Provide required_current_status to proceed anyway."
    return 0
  fi
  if [ "$target_order" -ge 0 ] && [ "$current_order" -gt "$target_order" ] && [ "$allow_backward" != "allow-backward" ]; then
    echo "Issue #${issue_number} is already at status '${current_status}' (more advanced than '${status_label}'); skipping rollback."
    return 0
  fi

  echo "Updating tracker status for issue #${issue_number} to '${status_label}'..."
  # shellcheck disable=SC2016 # GraphQL variables are expanded by GitHub, not by Bash.
  if workflow_run_gh_capture_stderr api graphql \
    -f projectId="$project_id" \
    -f itemId="$item_id" \
    -f fieldId="$field_id" \
    -f optionId="$option_id" \
    -f query='
      mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
        updateProjectV2ItemFieldValue(input: {
          projectId: $projectId
          itemId: $itemId
          fieldId: $fieldId
          value: { singleSelectOptionId: $optionId }
        }) {
          projectV2Item { id }
        }
      }
    '; then
    printf '%s' "$__workflow_last_gh_stdout"
  else
    echo "Warning: GraphQL mutation failed for issue #${issue_number}; tracker status not updated."
    workflow_print_captured_gh_stderr
  fi
}

# workflow_github_milestone_number <version>
#
# Prints the GitHub milestone number whose title exactly matches <version>, or
# empty when absent/unreadable.
workflow_github_milestone_number() {
  local version="$1"
  local repo_owner repo_name milestones

  repo_owner="$(workflow_resolve_github_repo_owner)"
  repo_name="$(workflow_resolve_github_repo_name)"
  if [ -z "$repo_owner" ] || [ -z "$repo_name" ]; then
    return 1
  fi

  if ! workflow_run_gh_capture_stderr api --paginate --slurp "repos/${repo_owner}/${repo_name}/milestones?state=all&per_page=100"; then
    echo "Warning: could not list GitHub milestones for release '${version}'." >&2
    workflow_print_captured_gh_stderr
    return 1
  fi
  milestones="$__workflow_last_gh_stdout"

  printf '%s' "$milestones" | python3 -c '
import json
import sys

version = sys.argv[1]
raw = sys.stdin.read()
try:
    pages = json.loads(raw)
except Exception:
    pages = []

if isinstance(pages, dict):
    pages = [pages]
if pages and all(isinstance(item, dict) for item in pages):
    items = pages
else:
    items = []
    for page in pages if isinstance(pages, list) else []:
        if isinstance(page, list):
            items.extend(item for item in page if isinstance(item, dict))

for item in items:
    if item.get("title") == version:
        print(item.get("number") or "", end="")
        break
' "$version"
}

# workflow_ensure_github_release_milestone <version>
#
# Creates the release milestone when absent and prints its number when known.
workflow_ensure_github_release_milestone() {
  local version="$1"
  local repo_owner repo_name milestone_number created_number

  if ! milestone_number="$(workflow_github_milestone_number "$version")"; then
    return 1
  fi
  if [ -n "$milestone_number" ]; then
    printf '%s' "$milestone_number"
    return 0
  fi

  repo_owner="$(workflow_resolve_github_repo_owner)"
  repo_name="$(workflow_resolve_github_repo_name)"
  if [ -z "$repo_owner" ] || [ -z "$repo_name" ]; then
    echo "Warning: could not resolve GitHub repository for release milestone '${version}'." >&2
    return 1
  fi

  if ! workflow_run_gh_capture_stderr api -X POST "repos/${repo_owner}/${repo_name}/milestones" \
    -f title="$version" \
    -f description="Release ${version}"; then
    echo "Warning: could not create GitHub release milestone '${version}'." >&2
    workflow_print_captured_gh_stderr
    return 1
  fi

  created_number=$(printf '%s' "$__workflow_last_gh_stdout" | python3 -c '
import json
import sys

try:
    data = json.loads(sys.stdin.read())
except Exception:
    data = {}
print(data.get("number") or "", end="")
'
)
  if [ -z "$created_number" ]; then
    echo "Warning: GitHub milestone create response did not include a milestone number for '${version}'." >&2
    return 1
  fi
  printf '%s' "$created_number"
}

# record_release_for_issue_best_effort <issue> <version>
#
# Provider-routed, fail-soft release stamp. Emits exactly one stable result line:
#   RELEASE_STAMPED issue=<issue> version=<version> provider=<provider>
#   RELEASE_STAMP_SKIPPED issue=<issue> version=<version> provider=<provider> reason=<reason>
#   RELEASE_STAMP_FAILED issue=<issue> version=<version> provider=<provider> reason=<reason>
record_release_for_issue_best_effort() {
  local issue="$1"
  local version="$2"
  local provider milestone_number repo_owner repo_name

  provider="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"
  case "$provider" in
    github_projects|github-projects|github_issues|github-issues)
      milestone_number="$(workflow_ensure_github_release_milestone "$version")"
      if [ -z "$milestone_number" ]; then
        echo "RELEASE_STAMP_FAILED issue=${issue} version=${version} provider=${provider} reason=milestone_unavailable"
        return 0
      fi
      repo_owner="$(workflow_resolve_github_repo_owner)"
      repo_name="$(workflow_resolve_github_repo_name)"
      if [ -z "$repo_owner" ] || [ -z "$repo_name" ]; then
        echo "Warning: could not resolve GitHub repository for milestone stamping of issue '${issue}'." >&2
        echo "RELEASE_STAMP_FAILED issue=${issue} version=${version} provider=${provider} reason=repo_unresolvable"
        return 0
      fi
      # Use the GitHub Issues REST API with the resolved milestone number. This works for
      # both open and closed milestones; 'gh issue edit --milestone <title>' fails when the
      # milestone is already closed (e.g. after a previous release).
      if workflow_run_gh_capture_stderr api -X PATCH \
          "repos/${repo_owner}/${repo_name}/issues/${issue}" \
          -F milestone="$milestone_number"; then
        echo "RELEASE_STAMPED issue=${issue} version=${version} provider=${provider}"
      else
        echo "Warning: could not assign GitHub milestone '${version}' to issue '${issue}'." >&2
        workflow_print_captured_gh_stderr
        echo "RELEASE_STAMP_FAILED issue=${issue} version=${version} provider=${provider} reason=assignment_failed"
      fi
      ;;
    ''|none)
      echo "RELEASE_STAMP_SKIPPED issue=${issue} version=${version} provider=${provider:-none} reason=provider_none"
      ;;
    linear)
      local release_field release_label_prefix
      release_field="$(workflow_issue_tracker_custom_field release_field)"
      release_label_prefix="$(workflow_issue_tracker_custom_field release_label_prefix)"
      release_label_prefix="${release_label_prefix:-release/}"
      if [ -n "$release_field" ]; then
        echo "RELEASE_STAMP_SKIPPED issue=${issue} version=${version} provider=linear reason=mcp_required release_field=${release_field}"
      else
        echo "RELEASE_STAMP_SKIPPED issue=${issue} version=${version} provider=linear reason=mcp_required release_label=${release_label_prefix}${version}"
      fi
      ;;
    *)
      echo "RELEASE_STAMP_SKIPPED issue=${issue} version=${version} provider=${provider} reason=unsupported_provider"
      ;;
  esac
  return 0
}

# finalize_release_marker_best_effort <version>
#
# Lifecycle finalizer. GitHub providers must close the release milestone
# successfully; other providers currently no-op.
finalize_release_marker_best_effort() {
  local version="$1"
  local provider repo_owner repo_name milestone_number

  provider="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"
  case "$provider" in
    github_projects|github-projects|github_issues|github-issues)
      if ! milestone_number="$(workflow_github_milestone_number "$version")"; then
        echo "Warning: could not read release milestone '${version}'; skipping finalization."
        return 1
      fi
      if [ -z "$milestone_number" ]; then
        echo "Warning: release milestone '${version}' not found; skipping finalization."
        return 1
      fi
      repo_owner="$(workflow_resolve_github_repo_owner)"
      repo_name="$(workflow_resolve_github_repo_name)"
      if [ -z "$repo_owner" ] || [ -z "$repo_name" ]; then
        echo "Warning: could not resolve GitHub repository for release marker finalization."
        return 1
      fi
      if workflow_run_gh_capture_stderr api -X PATCH "repos/${repo_owner}/${repo_name}/milestones/${milestone_number}" -f state=closed; then
        echo "Release marker finalized: ${version}"
      else
        echo "Warning: could not close GitHub release milestone '${version}'."
        workflow_print_captured_gh_stderr
        return 1
      fi
      ;;
    *)
      echo "Release marker finalization skipped for provider '${provider:-none}'."
      ;;
  esac
  return 0
}

# update_tracker_type_best_effort <issue_number> <type_label>
#
# Best-effort update for the GitHub Projects Type field. This intentionally
# mirrors update_tracker_status_best_effort while avoiding status-order logic.
update_tracker_type_best_effort() {
  local issue_number="$1"
  local type_label="$2"
  local project_number project_id field_json field_id option_id item_json item_id

  local _uttbe_provider
  _uttbe_provider="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"
  if [ "$_uttbe_provider" != "github_projects" ]; then
    echo "Warning: issue tracker provider '${_uttbe_provider:-unknown}' does not support GitHub Projects Type updates via this helper."
    return 0
  fi

  project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
  if [ -z "$project_number" ]; then
    echo "Warning: GITHUB_PROJECT_NUMBER not set and no project_number in .ai-dev-workflow.yaml; skipping tracker Type update."
    return 0
  fi

  item_json="$(workflow_github_project_item_for_issue "$issue_number" "$project_number")"
  if ! item_id=$(printf '%s' "$item_json" | python3 -c "
import json, sys
item = json.loads(sys.stdin.read(), strict=False)
print(item.get('item_id') or '', end='')
"); then
    echo "Warning: could not parse project item ID for issue #${issue_number}; skipping tracker Type update."
    return 0
  fi
  if ! project_id=$(printf '%s' "$item_json" | python3 -c "
import json, sys
item = json.loads(sys.stdin.read(), strict=False)
print(item.get('project_id') or '', end='')
"); then
    echo "Warning: could not parse project ID for issue #${issue_number}; skipping tracker Type update."
    return 0
  fi
  if [ -z "$item_id" ]; then
    echo "Warning: issue #${issue_number} not found in project #${project_number}; skipping tracker Type update."
    return 0
  fi
  if [ -z "$project_id" ]; then
    echo "Warning: could not resolve project ID for issue #${issue_number}; skipping tracker Type update."
    return 0
  fi

  if ! field_json="$(workflow_github_project_type_field_json "$project_id")"; then
    echo "Warning: could not read project Type field metadata; skipping tracker Type update."
    return 0
  fi
  if ! field_id=$(printf '%s' "$field_json" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read(), strict=False)
print(data.get('field_id') or '', end='')
"); then
    echo "Warning: could not parse Type field metadata; skipping tracker Type update."
    return 0
  fi
  if ! option_id=$(printf '%s' "$field_json" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read(), strict=False)
print((data.get('options') or {}).get(sys.argv[1]) or '', end='')
" "$type_label"); then
    echo "Warning: could not parse Type option '${type_label}'; skipping tracker Type update."
    return 0
  fi
  if [ -z "$field_id" ] || [ -z "$option_id" ]; then
    echo "Warning: could not resolve Type field or option '${type_label}'; skipping tracker Type update."
    return 0
  fi

  echo "Updating tracker Type for issue #${issue_number} to '${type_label}'..."
  # shellcheck disable=SC2016 # GraphQL variables are expanded by GitHub, not by Bash.
  if workflow_run_gh_capture_stderr api graphql \
    -f projectId="$project_id" \
    -f itemId="$item_id" \
    -f fieldId="$field_id" \
    -f optionId="$option_id" \
    -f query='
      mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
        updateProjectV2ItemFieldValue(input: {
          projectId: $projectId
          itemId: $itemId
          fieldId: $fieldId
          value: { singleSelectOptionId: $optionId }
        }) {
          projectV2Item { id }
        }
      }
    '; then
    printf '%s' "$__workflow_last_gh_stdout"
  else
    echo "Warning: GraphQL mutation failed for issue #${issue_number}; tracker Type not updated."
    workflow_print_captured_gh_stderr
  fi
}

# workflow_github_project_named_field_json <project_id> <field_name>
#
# Prints compact JSON {"field_id":"...","options":{"Name":"optionId",...}} for
# any single-select field whose name matches <field_name> exactly (case-sensitive).
# Uses an in-process parallel-array cache keyed by "<project_id>:<field_name>".
# Returns non-zero when the project ID is empty, the GraphQL fetch fails, or the
# named field is not found. Callers must treat those cases as lookup failures.
workflow_github_project_named_field_json() {
  local project_id="$1"
  local field_name="$2"
  local cache_key response cursor page_state field_json has_next end_cursor page_count line
  local -a graphql_args
  local _i _found_val

  if [ -z "$project_id" ]; then
    echo "Warning: project ID is empty; '${field_name}' field lookup cannot run." >&2
    printf ''
    return 1
  fi
  if [ -z "$field_name" ]; then
    echo "Warning: field_name is empty; named field lookup cannot run." >&2
    printf ''
    return 1
  fi

  cache_key="${project_id}:${field_name}"
  _found_val=""
  for _i in "${!__workflow_project_named_field_cache_keys[@]}"; do
    if [ "${__workflow_project_named_field_cache_keys[$_i]}" = "$cache_key" ]; then
      _found_val="${__workflow_project_named_field_cache_vals[$_i]}"
      break
    fi
  done
  if [ -n "$_found_val" ]; then
    printf '%s' "$_found_val"
    return 0
  fi

  cursor=""
  page_count=0
  field_json=""
  while :; do
    graphql_args=(
      api graphql
      -f projectId="$project_id"
    )
    if [ -n "$cursor" ]; then
      graphql_args+=(-f after="$cursor")
    fi
    # shellcheck disable=SC2016 # GraphQL variables are expanded by GitHub, not by Bash.
    graphql_args+=(
      -f query='
        query($projectId: ID!, $after: String) {
          node(id: $projectId) {
            ... on ProjectV2 {
              fields(first: 100, after: $after) {
                nodes {
                  ... on ProjectV2SingleSelectField {
                    id
                    name
                    options { id name }
                  }
                }
                pageInfo { hasNextPage endCursor }
              }
            }
          }
        }
      '
    )

    if ! workflow_run_gh_capture_stderr "${graphql_args[@]}"; then
      echo "Warning: GraphQL project '${field_name}' field lookup failed for project '${project_id}'." >&2
      workflow_print_captured_gh_stderr
      printf ''
      return 1
    fi
    response="$__workflow_last_gh_stdout"

    if ! page_state="$(printf '%s' "$response" | python3 -c "
import json, sys
try:
    data = json.loads(sys.stdin.read(), strict=False)
except Exception:
    sys.exit(2)
target = sys.argv[1]
field_connection = (((data.get('data') or {}).get('node') or {}).get('fields') or {})
fields = field_connection.get('nodes') or []
field_json = ''
for field in fields:
    if field.get('name') == target:
        field_json = json.dumps({
            'field_id': field.get('id') or '',
            'options': {option.get('name') or '': option.get('id') or '' for option in field.get('options') or []},
        }, separators=(',', ':'))
        break
page_info = field_connection.get('pageInfo') or {}
has_next = 'true' if page_info.get('hasNextPage') else 'false'
end_cursor = page_info.get('endCursor') or ''
print('FIELD_JSON=' + field_json)
print('HAS_NEXT=' + has_next)
print('END_CURSOR=' + end_cursor)
" "$field_name" 2>/dev/null)"; then
      echo "Warning: could not parse GraphQL '${field_name}' field response for project '${project_id}'." >&2
      printf ''
      return 1
    fi

    has_next="false"
    end_cursor=""
    while IFS= read -r line; do
      case "$line" in
        FIELD_JSON=*) field_json="${line#FIELD_JSON=}" ;;
        HAS_NEXT=*)   has_next="${line#HAS_NEXT=}" ;;
        END_CURSOR=*) end_cursor="${line#END_CURSOR=}" ;;
      esac
    done <<EOF
$page_state
EOF
    if [ -n "$field_json" ]; then
      break
    fi
    if [ "$has_next" != "true" ] || [ -z "$end_cursor" ]; then
      break
    fi
    page_count=$((page_count + 1))
    if [ "$page_count" -ge 20 ]; then
      echo "Warning: project '${field_name}' field lookup exceeded pagination limit for project '${project_id}'." >&2
      printf ''
      return 1
    fi
    cursor="$end_cursor"
  done

  if [ -z "$field_json" ]; then
    echo "Warning: project '${field_name}' field not found for project '${project_id}'." >&2
    printf ''
    return 1
  fi

  __workflow_project_named_field_cache_keys+=("$cache_key")
  __workflow_project_named_field_cache_vals+=("$field_json")
  printf '%s' "$field_json"
}

# _workflow_tracker_priority_field_json
#
# Internal helper shared by workflow_tracker_priority_resolvable and
# workflow_tracker_default_priority_value. Resolves and prints the
# project's Priority field JSON (id + options map, see
# workflow_github_project_named_field_json) when the tracker provider is
# github_projects, a project is configured, and the field was successfully
# read. Performs no issue-specific lookups and triggers no mutation, so it
# is safe to call before an issue exists. Prints nothing and returns 1 in
# every other case — provider mismatch, no project configured, or the
# lookup itself failed — which both callers treat uniformly as "nothing to
# validate/adapt against" (the same "genuinely does not apply" / "uncertain"
# carve-out update_tracker_named_field_best_effort always treats
# permissively).
_workflow_tracker_priority_field_json() {
  local _wtpfj_provider project_owner project_number project_id field_json

  _wtpfj_provider="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"
  if [ "$_wtpfj_provider" != "github_projects" ]; then
    return 1
  fi

  project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
  if [ -z "$project_number" ]; then
    return 1
  fi

  project_owner="$(workflow_resolve_github_project_owner)"
  if [ -z "$project_owner" ]; then
    project_owner="$(workflow_resolve_github_repo_owner)"
  fi
  if [ -z "$project_owner" ]; then
    return 1
  fi

  project_id="$(workflow_github_project_id "$project_owner" "$project_number" 2>/dev/null)"
  if [ -z "$project_id" ]; then
    return 1
  fi

  if ! field_json="$(workflow_github_project_named_field_json "$project_id" "Priority" 2>/dev/null)"; then
    return 1
  fi

  printf '%s' "$field_json"
}

# workflow_tracker_priority_resolvable <priority_value>
#
# Pre-flight check: does <priority_value> resolve against the project's
# actual Priority field options? Unlike update_tracker_priority_best_effort,
# this triggers no mutation, so it is safe to call before an issue exists —
# e.g. before `gh issue create` — to avoid the partial-success window where
# an issue is created but a required follow-up Priority write then fails
# (see issue #1501 code review: a caller that retries on non-zero exit
# without inspecting stdout could otherwise create a duplicate issue).
#
# Returns 0 (resolvable / not blocking) whenever
# _workflow_tracker_priority_field_json cannot produce a confirmed field
# reading (provider mismatch, no project configured, or an inconclusive
# lookup) — this pre-check must not block issue creation on an
# environmental failure the authoritative post-creation required check will
# re-attempt anyway. Returns 1 only when the Priority field was
# successfully read from a configured project and <priority_value> does not
# match any of its options — a confirmed, actionable bad value.
workflow_tracker_priority_resolvable() {
  local priority_value="$1"
  local field_json option_id

  if ! field_json="$(_workflow_tracker_priority_field_json)"; then
    return 0
  fi

  option_id="$(printf '%s' "$field_json" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read(), strict=False)
print((data.get('options') or {}).get(sys.argv[1]) or '', end='')
" "$priority_value" 2>/dev/null)"

  [ -n "$option_id" ]
}

# workflow_tracker_default_priority_value
#
# Resolves the runtime default Priority value used when --priority is
# omitted, adapting to what the configured board actually supports instead
# of assuming a single universal literal (issue #1501 code review, P1
# finding "Preserve compatibility with Normal-priority boards"): prefers
# "Medium" (this repo's own board), falls back to "Normal" for boards still
# configured per the framework's pre-#1501 setup docs.
#
# When _workflow_tracker_priority_field_json cannot produce a confirmed
# field reading (provider mismatch, no project configured, or an
# inconclusive lookup), prints "Medium" unchanged — matching the
# pre-existing best-effort behavior for those cases; there is nothing more
# specific to fall back to, and the post-creation update remains a
# best-effort no-op for a provider that does not support it.
#
# Only prints nothing (empty) when the Priority field was successfully read
# from a configured project and CONFIRMED to contain neither "Medium" nor
# "Normal". At that point, forcing a hard default would make every routine
# backlog-item creation on that board fail until manually migrated, so the
# caller should leave Priority unset instead — the same way an omitted
# --size or --type is left unset.
workflow_tracker_default_priority_value() {
  local field_json resolved

  if ! field_json="$(_workflow_tracker_priority_field_json)"; then
    printf 'Medium'
    return 0
  fi

  resolved="$(printf '%s' "$field_json" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read(), strict=False)
options = data.get('options') or {}
for candidate in ('Medium', 'Normal'):
    if options.get(candidate):
        print(candidate, end='')
        break
" 2>/dev/null)"

  printf '%s' "$resolved"
}

# update_tracker_named_field_best_effort <issue_number> <field_name> <option_value> [required]
#
# Update for any single-select GitHub Projects field by name. Resolves
# <option_value> against the project's actual field options (see
# workflow_github_project_named_field_json) rather than a hardcoded list.
# Supports github_projects provider only; emits warnings for all other
# providers.
#
# When the tracker provider is not github_projects, or no GitHub Project is
# configured, the field genuinely does not apply — there is nothing to
# resolve <option_value> against — so those two cases always return 0
# regardless of the [required] argument.
#
# For every other failure (item not found on the board, field/option not
# found, GraphQL read or write failure, etc.): when [required] is the
# literal string "required", the failure is a hard error (non-zero return,
# message prefixed "Error:") so an explicitly-requested value that cannot be
# applied to a configured board does not fail silently. When [required] is
# omitted (the default), those failures remain best-effort (return 0,
# message prefixed "Warning:") to avoid blocking caller flows for fields the
# caller does not depend on.
update_tracker_named_field_best_effort() {
  local issue_number="$1"
  local field_name="$2"
  local option_value="$3"
  local required="${4:-}"
  local project_number project_id field_json field_id option_id item_json item_id

  local _utnfbe_provider
  _utnfbe_provider="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"
  if [ "$_utnfbe_provider" != "github_projects" ]; then
    echo "Warning: issue tracker provider '${_utnfbe_provider:-unknown}' does not support GitHub Projects '${field_name}' updates via this helper."
    return 0
  fi

  project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
  if [ -z "$project_number" ]; then
    echo "Warning: GITHUB_PROJECT_NUMBER not set and no project_number in .ai-dev-workflow.yaml; skipping tracker '${field_name}' update."
    return 0
  fi

  item_json="$(workflow_github_project_item_for_issue "$issue_number" "$project_number")"
  if ! item_id=$(printf '%s' "$item_json" | python3 -c "
import json, sys
item = json.loads(sys.stdin.read(), strict=False)
print(item.get('item_id') or '', end='')
"); then
    if [ "$required" = "required" ]; then
      echo "Error: could not parse project item ID for issue #${issue_number}; tracker '${field_name}' not updated." >&2
      return 1
    fi
    echo "Warning: could not parse project item ID for issue #${issue_number}; skipping tracker '${field_name}' update."
    return 0
  fi
  if ! project_id=$(printf '%s' "$item_json" | python3 -c "
import json, sys
item = json.loads(sys.stdin.read(), strict=False)
print(item.get('project_id') or '', end='')
"); then
    if [ "$required" = "required" ]; then
      echo "Error: could not parse project ID for issue #${issue_number}; tracker '${field_name}' not updated." >&2
      return 1
    fi
    echo "Warning: could not parse project ID for issue #${issue_number}; skipping tracker '${field_name}' update."
    return 0
  fi
  if [ -z "$item_id" ]; then
    if [ "$required" = "required" ]; then
      echo "Error: issue #${issue_number} not found in project #${project_number}; tracker '${field_name}' not updated." >&2
      return 1
    fi
    echo "Warning: issue #${issue_number} not found in project #${project_number}; skipping tracker '${field_name}' update."
    return 0
  fi
  if [ -z "$project_id" ]; then
    if [ "$required" = "required" ]; then
      echo "Error: could not resolve project ID for issue #${issue_number}; tracker '${field_name}' not updated." >&2
      return 1
    fi
    echo "Warning: could not resolve project ID for issue #${issue_number}; skipping tracker '${field_name}' update."
    return 0
  fi

  if ! field_json="$(workflow_github_project_named_field_json "$project_id" "$field_name")"; then
    if [ "$required" = "required" ]; then
      echo "Error: could not read project '${field_name}' field metadata; tracker '${field_name}' not updated." >&2
      return 1
    fi
    echo "Warning: could not read project '${field_name}' field metadata; skipping tracker '${field_name}' update."
    return 0
  fi
  if ! field_id=$(printf '%s' "$field_json" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read(), strict=False)
print(data.get('field_id') or '', end='')
"); then
    if [ "$required" = "required" ]; then
      echo "Error: could not parse '${field_name}' field metadata; tracker '${field_name}' not updated." >&2
      return 1
    fi
    echo "Warning: could not parse '${field_name}' field metadata; skipping tracker '${field_name}' update."
    return 0
  fi
  if ! option_id=$(printf '%s' "$field_json" | python3 -c "
import json, sys
data = json.loads(sys.stdin.read(), strict=False)
print((data.get('options') or {}).get(sys.argv[1]) or '', end='')
" "$option_value"); then
    if [ "$required" = "required" ]; then
      echo "Error: could not parse '${field_name}' option '${option_value}'; tracker '${field_name}' not updated." >&2
      return 1
    fi
    echo "Warning: could not parse '${field_name}' option '${option_value}'; skipping tracker '${field_name}' update."
    return 0
  fi
  if [ -z "$field_id" ] || [ -z "$option_id" ]; then
    if [ "$required" = "required" ]; then
      echo "Error: could not resolve '${field_name}' field or option '${option_value}'; tracker '${field_name}' not updated." >&2
      return 1
    fi
    echo "Warning: could not resolve '${field_name}' field or option '${option_value}'; skipping tracker '${field_name}' update."
    return 0
  fi

  echo "Updating tracker '${field_name}' for issue #${issue_number} to '${option_value}'..."
  # shellcheck disable=SC2016 # GraphQL variables are expanded by GitHub, not by Bash.
  if workflow_run_gh_capture_stderr api graphql \
    -f projectId="$project_id" \
    -f itemId="$item_id" \
    -f fieldId="$field_id" \
    -f optionId="$option_id" \
    -f query='
      mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
        updateProjectV2ItemFieldValue(input: {
          projectId: $projectId
          itemId: $itemId
          fieldId: $fieldId
          value: { singleSelectOptionId: $optionId }
        }) {
          projectV2Item { id }
        }
      }
    '; then
    printf '%s' "$__workflow_last_gh_stdout"
  else
    if [ "$required" = "required" ]; then
      echo "Error: GraphQL mutation failed for issue #${issue_number}; tracker '${field_name}' not updated." >&2
      workflow_print_captured_gh_stderr
      return 1
    fi
    echo "Warning: GraphQL mutation failed for issue #${issue_number}; tracker '${field_name}' not updated."
    workflow_print_captured_gh_stderr
  fi
}

# update_tracker_priority_best_effort <issue_number> <priority_value>
#
# Update for the GitHub Projects Priority field. Resolves <priority_value>
# against the project's actual Priority field options (see
# workflow_github_project_named_field_json) — there is no hardcoded alias
# table. Priority is always explicitly set by add-backlog-item.sh (either
# user-supplied via --priority, or defaulted), so an unresolvable value is a
# hard error (non-zero return) whenever the tracker provider and project are
# configured — see update_tracker_named_field_best_effort's "required" mode.
# When the provider/project genuinely does not apply, this remains
# best-effort (returns 0), matching update_tracker_named_field_best_effort.
update_tracker_priority_best_effort() {
  local issue_number="$1"
  local priority_value="$2"
  update_tracker_named_field_best_effort "$issue_number" "Priority" "$priority_value" "required"
}

# update_tracker_size_best_effort <issue_number> <size_value>
#
# Best-effort update for the GitHub Projects Size field.
# Valid values: XS, S, M, L, XL
# Returns 0 in all failure cases (fail-open).
update_tracker_size_best_effort() {
  local issue_number="$1"
  local size_value="$2"
  update_tracker_named_field_best_effort "$issue_number" "Size" "$size_value"
}

# list_open_workflow_type_issues
#
# Prints a JSON array of open GitHub issues whose project Type is Workflow.
# Discovery is intentionally open-issues-first, then one project item-list
# cross-reference, so callers avoid per-item full-board scans.
list_open_workflow_type_issues() {
  local project_number owner open_issues project_items repo_owner repo_name repo_slug

  local _lowti_provider
  _lowti_provider="$(workflow_normalize_issue_tracker_provider "$(workflow_issue_tracker_provider_raw)")"
  if [ "$_lowti_provider" != "github_projects" ]; then
    printf '[]\n'
    return 0
  fi

  project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
  if [ -z "$project_number" ]; then
    echo "Warning: GITHUB_PROJECT_NUMBER not set and no project_number in .ai-dev-workflow.yaml; cannot discover Workflow Type issues." >&2
    printf '[]\n'
    return 0
  fi
  case "$project_number" in
    *[!0-9]*)
      echo "Warning: project number '${project_number}' is not numeric; cannot discover Workflow Type issues." >&2
      printf '[]\n'
      return 0
      ;;
  esac

  owner="$(workflow_resolve_github_project_owner)"
  if [ -z "$owner" ]; then
    owner="$(workflow_resolve_github_repo_owner)"
  fi
  if [ -z "$owner" ]; then
    echo "Warning: could not resolve GitHub Project owner; cannot discover Workflow Type issues." >&2
    printf '[]\n'
    return 0
  fi

  repo_owner="$(workflow_resolve_github_repo_owner)"
  repo_name="$(workflow_resolve_github_repo_name)"
  if [ -z "$repo_owner" ] || [ -z "$repo_name" ]; then
    echo "Warning: could not resolve GitHub repository; cannot discover Workflow Type issues." >&2
    printf '[]\n'
    return 0
  fi
  repo_slug="${repo_owner}/${repo_name}"

  if ! open_issues="$(gh issue list --repo "$repo_slug" --state open --limit 1000 --json number,title,labels,createdAt,url 2>/dev/null)"; then
    echo "Warning: failed to list open GitHub issues; cannot discover Workflow Type issues." >&2
    printf '[]\n'
    return 0
  fi
  if [ -z "$open_issues" ]; then
    printf '[]\n'
    return 0
  fi

  if ! project_items="$(gh project item-list "$project_number" --owner "$owner" --limit 1000 --format json 2>/dev/null)"; then
    echo "Warning: failed to list GitHub Project items; cannot discover Workflow Type issues." >&2
    printf '[]\n'
    return 0
  fi

  if ! printf '%s' "$project_items" | jq --argjson open "$open_issues" '
    def terminal($status):
      ($status // "") as $s
      | ($s == "Done" or $s == "Merged" or $s == "Released" or $s == "Cancelled");

    [ .items[]
      | select((.type // "") == "Workflow")
      | . as $item
      | ($open[] | select(.number == $item.content.number)) as $issue
      | select(terminal($item.status) | not)
      | {
          number: $issue.number,
          title: $issue.title,
          url: $issue.url,
          createdAt: $issue.createdAt,
          status: ($item.status // ""),
          priority: ($item.priority // ""),
          type: ($item.type // "")
        }
    ]
  ' 2>/dev/null; then
    echo "Warning: failed to parse GitHub Project items while discovering Workflow Type issues." >&2
    printf '[]\n'
  fi
}

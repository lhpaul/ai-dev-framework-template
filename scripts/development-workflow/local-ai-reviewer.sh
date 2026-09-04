#!/usr/bin/env bash
# local-ai-reviewer.sh - local-only reviewer for Step 7.
#
# Builds a bounded PR review context, invokes LOCAL_AI_REVIEWER_COMMAND, and
# emits the companion-script key=value contract consumed by pr-review-loop.sh.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat >&2 <<'EOF'
Usage: local-ai-reviewer.sh <pr_number> <owner> <repo> [--timeout <seconds>] [--repo-root <path>]

Options:
  --timeout <seconds>  Maximum seconds to wait for LOCAL_AI_REVIEWER_COMMAND.
                       Defaults to LOCAL_AI_REVIEWER_TIMEOUT or 300.
  --repo-root <path>   Repository checkout to review. When supplied, HEAD must
                       match the pull request head SHA before review runs.

Environment:
  LOCAL_AI_REVIEWER_COMMAND         Optional. When unset, defaults from
                                    LOCAL_AI_REVIEWER_BACKEND (codex or
                                    openai_compat) unless
                                    LOCAL_AI_REVIEWER_DISABLE_DEFAULT=1.
                                    The command receives CONTEXT_BUNDLE_PATH,
                                    PR_NUMBER, OWNER, REPO, BASE_BRANCH,
                                    HEAD_BRANCH, REVIEWED_HEAD,
                                    REVIEW_STAGE, REVIEW_STAGE_SOURCE,
                                    REVIEW_CHECKLISTS, REVIEW_DOCTRINE_STATE,
                                    REVIEW_DOCTRINE_PATTERN_COUNT,
                                    REVIEW_DOCTRINE_VERSION, and
                                    LOCAL_AI_REVIEWER_MODE (ordinary|strict) in env.
  LOCAL_AI_REVIEWER_BACKEND         codex (default) or openai_compat. Used only
                                    when LOCAL_AI_REVIEWER_COMMAND is unset.
  LOCAL_AI_REVIEWER_DISABLE_DEFAULT=1
                                    Do not apply a bundled preset default.
  LOCAL_AI_REVIEWER_DISABLED=1      Emit RESULT=skipped / disabled_by_config.
  LOCAL_AI_REVIEWER_EVIDENCE_FILE   Optional path for a JSON evidence artifact.
  LOCAL_AI_REVIEWER_GRAPH_STRATEGY  none|auto|code-review-graph|graphify.
  LOCAL_CODEX_REVIEWER_BIN          Codex binary for the bundled preset (default: codex).
  LOCAL_CODEX_REVIEWER_MODEL        Optional model for the bundled preset.
  LOCAL_CODEX_REVIEWER_PROMPT       Override the ordinary-pass Codex prompt only.
  LOCAL_CODEX_REVIEWER_STRICT_PROMPT
                                    Override the strict-pass Codex prompt only.
  LOCAL_AI_REVIEWER_MODEL           Model id for the openai_compat preset
                                    (example: deepseek-v4-pro).
  LOCAL_AI_REVIEWER_API_BASE_URL   OpenAI-compatible base URL for openai_compat
                                    (example: https://api.deepseek.com).
  LOCAL_AI_REVIEWER_API_KEY         API key for openai_compat. Falls back to
                                    DEEPSEEK_API_KEY or OPENAI_API_KEY.

Strict contract checks (#1650 spec, #1655 plan):
  Two registry entries (spec and plan) each report STRICT_<entry>_STATE on every
  review. At most one entry dispatches a second LOCAL_AI_REVIEWER_COMMAND
  invocation per review. The pass shares the reviewer's --timeout budget.

  Spec entry: STRICT_SPEC_* keys; response marker strict_spec_checks.
  Plan entry: STRICT_PLAN_* keys (includes STRICT_PLAN_APPLIED when applied);
  response marker strict_plan_checks; supplies plan documents via git show at
  the reviewed head.

  Strict findings are emitted as STRICT_<n>_CHECK/PATH/LINE/BODY and never
  change RESULT or BLOCKING_<n>_*.
EOF
}

resolve_local_ai_reviewer_command() {
  if [ -n "${LOCAL_AI_REVIEWER_COMMAND:-}" ]; then
    return 0
  fi
  if [ "${LOCAL_AI_REVIEWER_DISABLE_DEFAULT:-0}" = "1" ]; then
    return 0
  fi

  local backend="${LOCAL_AI_REVIEWER_BACKEND:-codex}"
  local default_command=""
  local preset_label=""
  case "$backend" in
    openai_compat|openai-compatible|openai)
      default_command="$SCRIPT_DIR/local-openai-review-command.sh"
      preset_label="openai-compatible"
      ;;
    codex|'')
      default_command="$SCRIPT_DIR/local-codex-review-command.sh"
      preset_label="Codex"
      ;;
    *)
      echo "ERROR: unknown LOCAL_AI_REVIEWER_BACKEND '$backend' (expected codex or openai_compat)" >&2
      return 0
      ;;
  esac

  if [ -f "$default_command" ]; then
    LOCAL_AI_REVIEWER_COMMAND="$default_command"
    export LOCAL_AI_REVIEWER_COMMAND
    echo "INFO: LOCAL_AI_REVIEWER_COMMAND defaulted to bundled ${preset_label} preset: $default_command" >&2
  fi
}

print_result() {
  local result="$1"
  local comment_count="$2"
  local blocking_count="$3"
  local suggestion_count="$4"
  local reason="${5:-}"
  local display_result="${6:-}"

  print_kv RESULT "$result"
  print_kv COMMENT_COUNT "$comment_count"
  print_kv BLOCKING_COUNT "$blocking_count"
  print_kv SUGGESTION_COUNT "$suggestion_count"
  [ -n "$reason" ] && print_kv REASON "$reason"
  [ -n "$display_result" ] && print_kv DISPLAY_RESULT "$display_result"
  return 0
}

valid_slug_component() {
  case "$1" in
    ''|*[!A-Za-z0-9._-]*) return 1 ;;
    *) return 0 ;;
  esac
}

normalize_github_remote_slug() {
  local raw="$1"
  local slug="$raw"

  slug="${slug#git@github.com:}"
  slug="${slug#ssh://git@github.com/}"
  slug="${slug#https://github.com/}"
  slug="${slug#http://github.com/}"
  slug="${slug#https://*@github.com/}"
  slug="${slug#http://*@github.com/}"
  slug="${slug%.git}"
  printf '%s\n' "$slug"
}

redact_github_remote_slug() {
  local raw="$1"
  local slug
  case "$raw" in
    http://*@github.com/*|https://*@github.com/*)
      printf '<redacted-remote>\n'
      return 0
      ;;
  esac
  slug="$(normalize_github_remote_slug "$raw")"
  case "$slug" in
    http://*|https://*|*@*) printf '<redacted-remote>\n' ;;
    *) printf '%s\n' "$slug" ;;
  esac
}

run_with_timeout() {
  local timeout_seconds="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  shift 3

  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_seconds" "$@" >"$stdout_file" 2>"$stderr_file"
    return $?
  fi

  # macOS and other hosts without GNU timeout: start a new process group so
  # descendant reviewer processes die with the leader (Codex P2 / #1635).
  local child_pid
  if command -v setsid >/dev/null 2>&1; then
    setsid "$@" >"$stdout_file" 2>"$stderr_file" &
    child_pid=$!
  else
    perl -e 'setpgrp; exec @ARGV' -- "$@" >"$stdout_file" 2>"$stderr_file" &
    child_pid=$!
  fi
  local elapsed=0
  while kill -0 "$child_pid" 2>/dev/null && [ "$elapsed" -lt "$timeout_seconds" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
  done
  if [ "$elapsed" -ge "$timeout_seconds" ]; then
    kill -TERM -- "-$child_pid" 2>/dev/null || kill -TERM "$child_pid" 2>/dev/null || true
    wait "$child_pid" 2>/dev/null || true
    kill -KILL -- "-$child_pid" 2>/dev/null || true
    return 124
  fi
  wait "$child_pid"
}

# ---------------------------------------------------------------------------
# Strict contract checks registry (#1650 spec, #1655 plan)
# ---------------------------------------------------------------------------

STRICT_SPEC_CHECKLIST_RELPATH="docs/workflow/development-workflow/strict-spec-checks.md"
STRICT_PLAN_CHECKLIST_RELPATH="docs/workflow/development-workflow/strict-plan-checks.md"
STRICT_REGISTRY_ENTRIES="spec plan"

strict_entry_checklist_relpath() {
  case "$1" in
    spec) printf '%s\n' "$STRICT_SPEC_CHECKLIST_RELPATH" ;;
    plan) printf '%s\n' "$STRICT_PLAN_CHECKLIST_RELPATH" ;;
    *) return 1 ;;
  esac
}

strict_entry_key_prefix() {
  case "$1" in
    spec) printf 'STRICT_SPEC\n' ;;
    plan) printf 'STRICT_PLAN\n' ;;
    *) return 1 ;;
  esac
}

strict_entry_bundle_checklist_key() {
  case "$1" in
    spec) printf 'strict_spec_checks\n' ;;
    plan) printf 'strict_plan_checks\n' ;;
    *) return 1 ;;
  esac
}

strict_entry_target_stage() {
  case "$1" in
    spec) printf 'spec\n' ;;
    plan) printf 'plan\n' ;;
    *) return 1 ;;
  esac
}

strict_entry_reports_na_reason() {
  case "$1" in
    plan) return 0 ;;
    *) return 1 ;;
  esac
}

strict_plan_source_path_for_plan() {
  local plan_path="$1"
  local spec_path
  if [[ "$plan_path" =~ ^docs/specs/developments/.+/2_.+_implementation-plan(\.doc)?\.md$ ]]; then
    spec_path="${plan_path%/*}/1_${plan_path##*/2_}"
    case "$spec_path" in
      *_implementation-plan.doc.md)
        printf '%s\n' "${spec_path/_implementation-plan.doc.md/_specs.doc.md}"
        ;;
      *_implementation-plan.md)
        printf '%s\n' "${spec_path/_implementation-plan.md/_specs.md}"
        ;;
    esac
  fi
}

strict_changed_plan_paths() {
  local path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    if workflow_is_plan_document_path "$path"; then
      printf '%s\n' "$path"
    fi
  done < <(printf '%s\n' "$changed_files_json" | jq -r '.[]?' 2>/dev/null)
}

extract_strict_checklist_known_checks() {
  local checklist="$1"
  local status=0
  local declared=0
  local ids=""
  local known=""
  local length=0
  local unique=0

  if [ ! -f "$checklist" ] || [ ! -r "$checklist" ]; then
    return 1
  fi

  status=0
  declared="$(grep -c '^### ' "$checklist")" || status=$?
  if [ "$status" -eq 1 ]; then
    declared=0
  elif [ "$status" -ne 0 ]; then
    return 1
  fi

  ids="$(sed -n 's/^### \([a-z][a-z0-9_]*\)[[:space:]]*$/\1/p' "$checklist")" || return 1
  known="$(printf '%s\n' "$ids" | jq -R -s 'split("\n") | map(select(length > 0))')" || return 1

  length="$(printf '%s\n' "$known" | jq -e 'length')" || return 1
  if [ "$length" -eq 0 ]; then
    return 1
  fi
  if [ "$length" -ne "$declared" ]; then
    return 1
  fi
  unique="$(printf '%s\n' "$known" | jq -e 'unique | length')" || return 1
  if [ "$length" -ne "$unique" ]; then
    return 1
  fi

  printf '%s\n' "$known"
  return 0
}

extract_strict_spec_known_checks() {
  extract_strict_checklist_known_checks "$1"
}

extract_strict_plan_sections() {
  local checklist="$1"
  local status=0
  local pairs=""
  local ids=""
  local sections=""

  if [ ! -f "$checklist" ] || [ ! -r "$checklist" ]; then
    return 1
  fi

  status=0
  pairs="$(awk '
    /^### / {
      if (id != "" && n != 1) { bad = 1 }
      id = $2; n = 0; next
    }
    /^Source: *required$/     { print id "\trequired";     n++; next }
    /^Source: *not required$/ { print id "\tnot_required"; n++; next }
    END { if (id == "" || n != 1 || bad) exit 3 }
  ' "$checklist")" || status=$?
  if [ "$status" -ne 0 ]; then
    return 1
  fi

  if ! ids="$(extract_strict_checklist_known_checks "$checklist")"; then
    return 1
  fi

  if [ "$(printf '%s\n' "$pairs" | cut -f1 | jq -R -s -r 'split("\n") | map(select(length > 0)) | sort | join(",")')" != "$(printf '%s\n' "$ids" | jq -r 'sort | join(",")')" ]; then
    return 1
  fi

  sections="$(printf '%s\n' "$pairs" | jq -R -s '
    split("\n")
    | map(select(length > 0))
    | map(split("\t"))
    | map(select(length == 2) | {id: .[0], source: .[1]})
  ')" || return 1

  printf '%s\n' "$sections"
  return 0
}

parse_strict_checks_response() {
  local response_json="$1"
  local admission_checks_json="$2"
  local response_marker="$3"

  printf '%s\n' "$response_json" | jq -c --argjson admission_checks "$admission_checks_json" --arg marker "$response_marker" '
    def ident:
      ((.check? // null) | if type == "string" then ascii_downcase else null end);
    def known($c): $c != null and ($admission_checks | index($c) != null);
    def text_value:
      [.body?, .message?, .description?, .title?, .summary?, .comment?, .text?]
      | map(select(type == "string" and length > 0)) | .[0] // "";
    def path_value:
      [.path?, .file?, .filename?, .filepath?, .location.path?]
      | map(select(type == "string" and length > 0)) | .[0] // "";
    def line_value:
      [.line?, .startLine?, .start_line?, .location.line?]
      | map(select((type == "number") or (type == "string" and length > 0)))
      | .[0] // "";
    if (.mode? // null) != $marker then
      { malformed: true, count: 0, checks: "", unknown_count: 0, findings: [] }
    else
      (if   has("findings") then .findings
       elif has("comments") then .comments
       elif has("issues")   then .issues
       else null end) as $f
      | if ($f | type) != "array" then
          { malformed: true, count: 0, checks: "", unknown_count: 0, findings: [] }
        else
          ($f | map(select(known(ident)))) as $named
          | ($f | map(select(known(ident) | not))) as $unnamed
          | {
              malformed: false,
              count: ($named | length),
              checks: ($named | map(ident) | unique | join(",")),
              unknown_count: ($unnamed | length),
              findings: ($f | map({
                check: (if known(ident) then ident else "unknown" end),
                path: path_value,
                line: (line_value | tostring),
                body: (text_value | gsub("\n"; "\\n"))
              }))
            }
        end
    end
  ' 2>/dev/null
}

parse_strict_spec_response() {
  parse_strict_checks_response "$1" "$2" "strict_spec_checks"
}

parse_strict_plan_response() {
  parse_strict_checks_response "$1" "$2" "strict_plan_checks"
}

# Drop source-dependent findings reported against plan documents that have no
# sibling spec at the reviewed head. Review-level admission may include those
# checks when any changed plan has a source; each document still gets only the
# checks that apply to it (AC-13 / AC-19a).
filter_strict_plan_parsed_response() {
  local parsed="$1"
  local sections_json="$2"
  local sources_json="$3"
  local documents_json="${4:-[]}"

  printf '%s\n' "$parsed" | jq -c --argjson sections "$sections_json" --argjson sources "$sources_json" --argjson documents "$documents_json" '
    ($sections | map(select(.source == "required") | .id)) as $required
    | ($sources | map(.plan_path)) as $with_source
    | ($documents | map(.path)) as $plan_docs
    | .findings as $all
    | ($all | map(
        . as $f
        | if ($f.check != "unknown")
            and (($f.path | type) != "string" or ($f.path | length) == 0
                 or ($plan_docs | index($f.path)) == null) then
            $f + {check: "unknown", remapped: true}
          elif ($f.check != "unknown")
            and ($required | index($f.check)) != null
            and ($with_source | index($f.path)) == null then
            $f + {check: "unknown", remapped: true}
          else
            $f
          end
      )) as $processed
    | ($processed | map(select(.remapped == true)) | length) as $remapped
    | ($processed | map(del(.remapped))) as $kept
    | . + {
        count: ($kept | map(select(.check != "unknown")) | length),
        checks: ($kept | map(select(.check != "unknown") | .check) | unique | join(",")),
        unknown_count: ((.unknown_count // 0) + $remapped),
        findings: $kept
      }
  ' 2>/dev/null
}

emit_strict_entry_output() {
  local prefix="$1"
  local state="$2"
  local count="${3:-}"
  local checks="${4:-}"
  local unknown_count="${5:-0}"
  local reason="${6:-}"
  local applied="${7:-}"
  local findings_json="${8:-[]}"

  print_kv "${prefix}_STATE" "$state"
  case "$state" in
    applied)
      print_kv "${prefix}_COUNT" "$count"
      print_kv "${prefix}_CHECKS" "$checks"
      if [ -n "$applied" ]; then
        print_kv "${prefix}_APPLIED" "$applied"
      fi
      if [ "${unknown_count:-0}" -gt 0 ]; then
        print_kv "${prefix}_UNKNOWN_COUNT" "$unknown_count"
      fi
      ;;
    unavailable|not_applicable)
      [ -n "$reason" ] && print_kv "${prefix}_REASON" "$reason"
      ;;
  esac

  if [ "$state" = "applied" ]; then
    local idx=0
    local finding_count
    finding_count="$(printf '%s\n' "$findings_json" | jq -e 'length' 2>/dev/null)" || finding_count=0
    while [ "$idx" -lt "$finding_count" ]; do
      local check path line body
      check="$(printf '%s\n' "$findings_json" | jq -r --argjson i "$idx" '.[$i].check // "unknown"')"
      path="$(printf '%s\n' "$findings_json" | jq -r --argjson i "$idx" '.[$i].path // ""')"
      line="$(printf '%s\n' "$findings_json" | jq -r --argjson i "$idx" '.[$i].line // ""')"
      body="$(printf '%s\n' "$findings_json" | jq -r --argjson i "$idx" '.[$i].body // ""')"
      idx=$((idx + 1))
      print_kv "STRICT_${idx}_CHECK" "$check"
      print_kv "STRICT_${idx}_PATH" "$path"
      print_kv "STRICT_${idx}_LINE" "$line"
      print_kv "STRICT_${idx}_BODY" "$body"
    done
  fi
}

emit_strict_spec_output() {
  emit_strict_entry_output "STRICT_SPEC" "$@"
}

emit_strict_plan_output() {
  emit_strict_entry_output "STRICT_PLAN" "$@"
}

strict_git_show_at_head() {
  local relpath="$1"
  local git_dir="${REPO_ROOT:-.}"
  git -C "$git_dir" show "${HEAD_SHA}:${relpath}" 2>/dev/null
}

strict_build_plan_bundle_extras() {
  local plan_paths="$1"
  local sections_json="$2"
  local any_source=0
  local documents_json="[]"
  local sources_json="[]"
  local plan_path source_path text doc_has_source

  while IFS= read -r plan_path; do
    [ -n "$plan_path" ] || continue
    if ! text="$(strict_git_show_at_head "$plan_path")"; then
      return 1
    fi
    doc_has_source=false
    source_path="$(strict_plan_source_path_for_plan "$plan_path")"
    if [ -n "$source_path" ] && text="$(strict_git_show_at_head "$source_path")"; then
      any_source=1
      doc_has_source=true
      sources_json="$(jq -n --argjson srcs "$sources_json" --arg plan_path "$plan_path" \
        --arg source_path "$source_path" --arg text "$text" \
        '$srcs + [{plan_path:$plan_path, source_path:$source_path, text:$text}]')"
      if ! text="$(strict_git_show_at_head "$plan_path")"; then
        return 1
      fi
    fi
    documents_json="$(jq -n --argjson docs "$documents_json" --arg path "$plan_path" --arg text "$text" \
      --argjson has_source "$doc_has_source" \
      '$docs + [{path:$path, text:$text, has_source:$has_source}]')"
  done <<< "$plan_paths"

  strict_plan_sections_json="$sections_json"
  strict_plan_applied_set="$(printf '%s\n' "$sections_json" | jq -r --arg any_source "$any_source" '
    map(select(($any_source == "1") or .source == "not_required") | .id) | join(",")
  ')"
  strict_plan_admission_checks_json="$(printf '%s\n' "$strict_plan_applied_set" | jq -R 'split(",") | map(select(length > 0))')"

  strict_plan_documents_json="$documents_json"
  strict_plan_sources_json="$sources_json"
  return 0
}

strict_dispatch_pass() {
  local checklist_path="$1"
  local checklist_key="$2"
  local admission_json="$3"
  local pass_kind="$4"
  local remaining="$5"
  local strict_context_file_local=""
  local strict_stdout_file_local=""
  local strict_stderr_file_local=""
  local strict_exit=0
  local strict_stdout=""
  local strict_parsed=""
  local result_state=""
  local result_reason=""
  local result_count=""
  local result_checks=""
  local result_unknown=0
  local result_findings="[]"

  strict_context_file_local="$(mktemp)"
  strict_stdout_file_local="$(mktemp)"
  strict_stderr_file_local="$(mktemp)"

  if [ "$pass_kind" = "plan" ]; then
    if ! jq --rawfile checks "$checklist_path" \
        --argjson documents "$strict_plan_documents_json" \
        --argjson sources "$strict_plan_sources_json" \
        --arg checklist_key "$checklist_key" \
        '. + { ($checklist_key): $checks, strict_plan_documents: $documents, strict_plan_sources: $sources }' \
        "$context_file" >"$strict_context_file_local"; then
      result_state="unavailable"
      result_reason="strict_pass_failed"
      rm -f "$strict_context_file_local" "$strict_stdout_file_local" "$strict_stderr_file_local"
      printf '%s\n' "$result_state" "$result_reason" "$result_count" "$result_checks" "$result_unknown" "$result_findings"
      return 0
    fi
  elif ! jq --rawfile checks "$checklist_path" \
      --arg checklist_key "$checklist_key" \
      '. + { ($checklist_key): $checks }' \
      "$context_file" >"$strict_context_file_local"; then
    result_state="unavailable"
    result_reason="strict_pass_failed"
    rm -f "$strict_context_file_local" "$strict_stdout_file_local" "$strict_stderr_file_local"
    printf '%s\n' "$result_state" "$result_reason" "$result_count" "$result_checks" "$result_unknown" "$result_findings"
    return 0
  fi

  set +e
  LOCAL_AI_REVIEWER_MODE=strict \
  CONTEXT_BUNDLE_PATH="$strict_context_file_local" \
  PR_NUMBER="$PR_NUMBER" \
  OWNER="$OWNER" \
  REPO="$REPO" \
  BASE_BRANCH="$BASE_BRANCH" \
  HEAD_BRANCH="$HEAD_BRANCH" \
  REVIEWED_HEAD="$HEAD_SHA" \
  REVIEW_STAGE="$review_stage" \
  REVIEW_STAGE_SOURCE="$review_stage_source" \
  REVIEW_CHECKLISTS="$review_checklists_csv" \
  REVIEW_DOCTRINE_STATE="$review_doctrine_state" \
  REVIEW_DOCTRINE_PATTERN_COUNT="$review_doctrine_pattern_count" \
  REVIEW_DOCTRINE_VERSION="$review_doctrine_version" \
    run_with_timeout "$remaining" "$strict_stdout_file_local" "$strict_stderr_file_local" \
      sh -c "$LOCAL_AI_REVIEWER_COMMAND"
  strict_exit=$?
  set -e
  strict_stdout="$(cat "$strict_stdout_file_local" 2>/dev/null || true)"
  rm -f "$strict_context_file_local" "$strict_stdout_file_local" "$strict_stderr_file_local"

  if [ "$strict_exit" -ne 0 ] \
      || [ -z "$(printf '%s' "$strict_stdout" | tr -d '[:space:]')" ] \
      || ! printf '%s\n' "$strict_stdout" | jq -e . >/dev/null 2>&1; then
    result_state="unavailable"
    result_reason="strict_pass_failed"
  else
    case "$pass_kind" in
      plan) strict_parsed="$(parse_strict_plan_response "$strict_stdout" "$admission_json")" || strict_parsed="" ;;
      *) strict_parsed="$(parse_strict_spec_response "$strict_stdout" "$admission_json")" || strict_parsed="" ;;
    esac
    if [ -z "$strict_parsed" ] \
        || [ "$(printf '%s\n' "$strict_parsed" | jq -r '.malformed')" = "true" ]; then
      result_state="unavailable"
      result_reason="strict_pass_failed"
    else
      result_state="applied"
      result_count="$(printf '%s\n' "$strict_parsed" | jq -r '.count')"
      result_checks="$(printf '%s\n' "$strict_parsed" | jq -r '.checks')"
      result_unknown="$(printf '%s\n' "$strict_parsed" | jq -r '.unknown_count')"
      result_findings="$(printf '%s\n' "$strict_parsed" | jq -c '.findings')"
    fi
  fi

  printf '%s\n' "$result_state" "$result_reason" "$result_count" "$result_checks" "$result_unknown" "$result_findings"
}

strict_run_registry_entry() {
  local entry="$1"
  local target_stage checklist_path checklist_key
  local state="" reason="" count="" checks="" applied="" unknown_count=0
  local findings_json="[]"
  local admission_json="[]"
  local sections_json=""
  local plan_paths=""
  local remaining=0
  local now_epoch=""
  local dispatch_out=""

  target_stage="$(strict_entry_target_stage "$entry")"
  checklist_path="$(strict_entry_checklist_relpath "$entry")"
  checklist_key="$(strict_entry_bundle_checklist_key "$entry")"

  if [ -z "$HEAD_BRANCH" ]; then
    state="unavailable"
    reason="stage_unresolved"
  elif [ "$review_stage" != "$target_stage" ]; then
    state="not_applicable"
    if strict_entry_reports_na_reason "$entry"; then
      reason="stage_not_plan"
    fi
  elif [ "$entry" = "plan" ]; then
    plan_paths="$(strict_changed_plan_paths)"
    if [ -z "$plan_paths" ]; then
      state="not_applicable"
      reason="no_plan_document_changed"
    elif ! sections_json="$(extract_strict_plan_sections "$checklist_path")"; then
      state="unavailable"
      reason="checklist_unreadable"
    elif ! strict_build_plan_bundle_extras "$plan_paths" "$sections_json"; then
      state="unavailable"
      reason="strict_pass_failed"
    else
      applied="$strict_plan_applied_set"
      admission_json="$strict_plan_admission_checks_json"
      now_epoch="$(date +%s)"
      remaining=$((TIMEOUT - (now_epoch - round_start_epoch)))
      if [ "$remaining" -le 0 ]; then
        state="unavailable"
        reason="strict_pass_failed"
      else
        dispatch_out="$(strict_dispatch_pass "$checklist_path" "$checklist_key" "$admission_json" plan "$remaining")"
        state="$(printf '%s\n' "$dispatch_out" | sed -n '1p')"
        reason="$(printf '%s\n' "$dispatch_out" | sed -n '2p')"
        count="$(printf '%s\n' "$dispatch_out" | sed -n '3p')"
        checks="$(printf '%s\n' "$dispatch_out" | sed -n '4p')"
        unknown_count="$(printf '%s\n' "$dispatch_out" | sed -n '5p')"
        findings_json="$(printf '%s\n' "$dispatch_out" | sed -n '6p')"
        if [ "$state" = "applied" ] && [ -n "$strict_plan_sections_json" ]; then
          strict_parsed="$(jq -nc \
            --argjson count "${count:-0}" \
            --arg checks "${checks:-}" \
            --argjson unknown_count "${unknown_count:-0}" \
            --argjson findings "${findings_json:-[]}" \
            '{count:$count, checks:$checks, unknown_count:$unknown_count, findings:$findings}')"
          if strict_parsed="$(filter_strict_plan_parsed_response "$strict_parsed" "$strict_plan_sections_json" "$strict_plan_sources_json" "$strict_plan_documents_json")"; then
            count="$(printf '%s\n' "$strict_parsed" | jq -r '.count')"
            checks="$(printf '%s\n' "$strict_parsed" | jq -r '.checks')"
            unknown_count="$(printf '%s\n' "$strict_parsed" | jq -r '.unknown_count')"
            findings_json="$(printf '%s\n' "$strict_parsed" | jq -c '.findings')"
          fi
        fi
      fi
    fi
  elif [ "$entry" = "spec" ]; then
    if ! admission_json="$(extract_strict_checklist_known_checks "$checklist_path")"; then
      state="unavailable"
      reason="checklist_unreadable"
    else
      now_epoch="$(date +%s)"
      remaining=$((TIMEOUT - (now_epoch - round_start_epoch)))
      if [ "$remaining" -le 0 ]; then
        state="unavailable"
        reason="strict_pass_failed"
      else
        dispatch_out="$(strict_dispatch_pass "$checklist_path" "$checklist_key" "$admission_json" spec "$remaining")"
        state="$(printf '%s\n' "$dispatch_out" | sed -n '1p')"
        reason="$(printf '%s\n' "$dispatch_out" | sed -n '2p')"
        count="$(printf '%s\n' "$dispatch_out" | sed -n '3p')"
        checks="$(printf '%s\n' "$dispatch_out" | sed -n '4p')"
        unknown_count="$(printf '%s\n' "$dispatch_out" | sed -n '5p')"
        findings_json="$(printf '%s\n' "$dispatch_out" | sed -n '6p')"
      fi
    fi
  fi

  case "$entry" in
    spec)
      strict_spec_state="$state"
      strict_spec_count="$count"
      strict_spec_checks="$checks"
      strict_spec_unknown_count="$unknown_count"
      strict_spec_reason="$reason"
      strict_spec_findings_json="$findings_json"
      ;;
    plan)
      strict_plan_state="$state"
      strict_plan_count="$count"
      strict_plan_checks="$checks"
      strict_plan_applied="$applied"
      strict_plan_unknown_count="$unknown_count"
      strict_plan_reason="$reason"
      strict_plan_findings_json="$findings_json"
      ;;
  esac
}

strict_run_all_registry_entries() {
  local entry
  for entry in $STRICT_REGISTRY_ENTRIES; do
    strict_run_registry_entry "$entry"
  done
}

# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Stage-specific review checklist selection (#1653)
# ---------------------------------------------------------------------------

# Branch tier. Literal prefixes, never a regex: `specification/foo` must not
# match `spec/*`.
reviewer_stage_for_branch() {
  case "${1:-}" in
    spec/*) printf 'spec\n' ;;
    implementation-plan/*) printf 'plan\n' ;;
    feature/*|refactor/*|fix/*|hotfix/*) printf 'implementation\n' ;;
    *) printf 'default\n' ;;
  esac
}

# File tier. Reads newline-delimited paths on stdin — NOT the JSON array.
# NOTE: this list is not #1652's reviewer_loop_path_is_normative_document and
# must not be merged with it — that one decides whether a finding may be
# cleared as cosmetic, this one decides which checklist applies.
reviewer_changed_files_touch_workflow_policy() {
  local path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      REVIEW.md|AGENTS.md|CLAUDE.md|GEMINI.md|LLM_RULES.md|.ai-dev-workflow.yaml)
        return 0 ;;
      docs/workflow/*|docs/best-practices/*|scripts/development-workflow/*)
        return 0 ;;
      .claude/*|.cursor/*|.codex/*|.agents/*)
        return 0 ;;
    esac
  done
  return 1
}

# Decode the compact JSON array into newline-delimited paths, buffered.
reviewer_decode_changed_files() {
  local decoded
  if ! decoded="$(printf '%s' "${1:-}" | jq -r '.[]?' 2>/dev/null)"; then
    echo "WARN: could not decode changed_files_json; workflow-policy checklist not applied" >&2
    decoded=""
  fi
  printf '%s\n' "$decoded"
}

# The merge. The file tier only ever appends, and never runs for `default`.
reviewer_resolve_review_stage() {
  local head_branch="$1" changed_files_json="$2"
  local stage checklists source

  stage="$(reviewer_stage_for_branch "$head_branch")"
  case "$stage" in
    spec) checklists="Spec Review Checklist" ;;
    plan) checklists="Plan Review Checklist" ;;
    implementation) checklists="Code Review Checklist" ;;
    default) checklists="" ;;
  esac

  source="branch"
  if [ -z "$checklists" ]; then
    source="none"
  elif reviewer_changed_files_touch_workflow_policy \
    <<< "$(reviewer_decode_changed_files "$changed_files_json")"; then
    checklists="${checklists},Workflow Policy Review Checklist"
    source="branch+files"
  fi

  printf '%s\n%s\n%s\n' "$stage" "$source" "$checklists"
}

# ---------------------------------------------------------------------------
# Review doctrine supply (#1654)
# ---------------------------------------------------------------------------

reviewer_doctrine_version() {
  local snapshot="$1"
  local digest_cmd=""

  if command -v sha256sum >/dev/null 2>&1; then
    digest_cmd="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then
    digest_cmd="shasum -a 256"
  else
    return 1
  fi

  local full_hash
  full_hash="$($digest_cmd "$snapshot" 2>/dev/null | awk '{print $1}')" || return 1
  [ -n "$full_hash" ] || return 1
  printf '%s\n' "${full_hash:0:12}"
}

reviewer_doctrine_supply() {
  local path="docs/workflow/development-workflow/review-doctrine.md"
  local snapshot bytes version count status
  local unreadable='{"state":"unreadable","text":"","pattern_count":0,"version":""}'

  [ -f "$path" ] || { printf '{"state":"absent","text":"","pattern_count":0,"version":""}\n'; return 0; }

  snapshot="$(mktemp)" || { printf '%s\n' "$unreadable"; return 0; }
  cp "$path" "$snapshot" 2>/dev/null || { rm -f "$snapshot"; printf '%s\n' "$unreadable"; return 0; }

  bytes="$(wc -c <"$snapshot" 2>/dev/null)" || { rm -f "$snapshot"; printf '%s\n' "$unreadable"; return 0; }
  bytes="${bytes//[[:space:]]/}"
  [ -n "$bytes" ] || { rm -f "$snapshot"; printf '%s\n' "$unreadable"; return 0; }

  version="$(reviewer_doctrine_version "$snapshot")" || {
    rm -f "$snapshot"; printf '%s\n' "$unreadable"; return 0; }

  if [ "$bytes" -gt "$REVIEW_DOCTRINE_MAX_BYTES" ]; then
    rm -f "$snapshot"
    jq -n --arg v "$version" '{state:"oversized", text:"", pattern_count:0, version:$v}'
    return 0
  fi

  status=0
  count="$(grep -c '^### ' "$snapshot" 2>/dev/null)" || status=$?
  if [ "$status" -eq 1 ]; then
    count=0
  elif [ "$status" -ne 0 ]; then
    rm -f "$snapshot"; printf '%s\n' "$unreadable"; return 0
  fi

  jq -n --rawfile t "$snapshot" --arg v "$version" --argjson c "${count:-0}" \
    '{state:"supplied", text:$t, pattern_count:$c, version:$v}' 2>/dev/null || {
    rm -f "$snapshot"; printf '%s\n' "$unreadable"; return 0; }
  rm -f "$snapshot"
}

# Effective harness mode: only when HARNESS_MODE=1 AND the script is sourced.
_HARNESS_MODE_EFFECTIVE=0
if [ "${HARNESS_MODE:-0}" -eq 1 ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then
  _HARNESS_MODE_EFFECTIVE=1
fi

if [ "$_HARNESS_MODE_EFFECTIVE" -eq 1 ]; then
  return 0 2>/dev/null || true
fi

if [ "$#" -lt 3 ]; then
  usage
  exit 2
fi

PR_NUMBER="$1"
OWNER="$2"
REPO="$3"
shift 3

case "$PR_NUMBER" in
  ''|0|*[!0-9]*)
    echo "ERROR: PR number '$PR_NUMBER' is not a valid positive integer" >&2
    exit 2
    ;;
esac
if ! valid_slug_component "$OWNER"; then
  echo "ERROR: owner '$OWNER' contains invalid characters" >&2
  exit 2
fi
if ! valid_slug_component "$REPO"; then
  echo "ERROR: repo '$REPO' contains invalid characters" >&2
  exit 2
fi

TIMEOUT="${LOCAL_AI_REVIEWER_TIMEOUT:-300}"
REPO_ROOT=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --timeout)
      [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { echo "ERROR: --timeout requires a value" >&2; exit 2; }
      TIMEOUT="$2"
      shift 2
      ;;
    --repo-root)
      [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { echo "ERROR: --repo-root requires a value" >&2; exit 2; }
      REPO_ROOT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option '$1'" >&2
      usage
      exit 2
      ;;
  esac
done

case "$TIMEOUT" in
  ''|0|*[!0-9]*)
    echo "ERROR: --timeout value '$TIMEOUT' is not a positive integer" >&2
    exit 2
    ;;
esac

if [ -n "${LOCAL_AI_REVIEWER_EVIDENCE_FILE:-}" ]; then
  case "$LOCAL_AI_REVIEWER_EVIDENCE_FILE" in
    /*) ;;
    *) LOCAL_AI_REVIEWER_EVIDENCE_FILE="$PWD/$LOCAL_AI_REVIEWER_EVIDENCE_FILE" ;;
  esac
  export LOCAL_AI_REVIEWER_EVIDENCE_FILE
fi

if [ "${LOCAL_AI_REVIEWER_DISABLED:-0}" = "1" ]; then
  print_result skipped 0 0 0 disabled_by_config disabled_by_config
  exit 3
fi

resolve_local_ai_reviewer_command

if [ -z "${LOCAL_AI_REVIEWER_COMMAND:-}" ]; then
  echo "ERROR: LOCAL_AI_REVIEWER_COMMAND is not configured" >&2
  print_result escalate 0 0 0 missing_command missing_command
  exit 2
fi

BASE_BRANCH=""
HEAD_BRANCH=""
HEAD_SHA=""
PR_BODY=""
changed_files_json="[]"
diff_name_status=""
diff_stat=""
diff_fetch_failed=0
if command -v gh >/dev/null 2>&1; then
  pr_json=""
  if pr_json="$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json baseRefName,headRefName,headRefOid,body 2>/dev/null)"; then
    BASE_BRANCH="$(printf '%s\n' "$pr_json" | jq -r '.baseRefName // empty' 2>/dev/null || true)"
    HEAD_BRANCH="$(printf '%s\n' "$pr_json" | jq -r '.headRefName // empty' 2>/dev/null || true)"
    HEAD_SHA="$(printf '%s\n' "$pr_json" | jq -r '.headRefOid // empty' 2>/dev/null || true)"
    PR_BODY="$(printf '%s\n' "$pr_json" | jq -r '.body // empty' 2>/dev/null || true)"
  fi
  if ! diff_output="$(gh pr diff "$PR_NUMBER" --repo "$OWNER/$REPO" --name-only 2>/dev/null)"; then
    diff_output=""
    diff_fetch_failed=1
  fi
  if [ -n "$diff_output" ]; then
    changed_files_json="$(printf '%s\n' "$diff_output" | jq -R -s -c 'split("\n") | map(select(length > 0))')"
  fi
fi
if [ -z "$BASE_BRANCH" ]; then
  echo "ERROR: could not resolve pull request base branch for #$PR_NUMBER" >&2
  print_result escalate 0 0 0 base_branch_unavailable base_branch_unavailable
  exit 2
fi
if [ -z "$HEAD_SHA" ]; then
  echo "ERROR: could not resolve pull request head SHA for #$PR_NUMBER" >&2
  print_result escalate 0 0 0 head_sha_unavailable head_sha_unavailable
  exit 2
fi
if [ "$diff_fetch_failed" -ne 0 ]; then
  echo "ERROR: could not fetch pull request diff for #$PR_NUMBER" >&2
  print_result escalate 0 0 0 diff_unavailable diff_unavailable
  exit 2
fi

if [ -n "$REPO_ROOT" ]; then
  if [ ! -d "$REPO_ROOT/.git" ] && ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    echo "ERROR: --repo-root is not a Git checkout: $REPO_ROOT" >&2
    print_result escalate 0 0 0 invalid_repo_root invalid_repo_root
    exit 2
  fi
  if ! repo_root_origin="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null)"; then
    repo_root_origin=""
  fi
  repo_root_slug="$(normalize_github_remote_slug "$repo_root_origin")"
  if [ "$repo_root_slug" != "$OWNER/$REPO" ]; then
    echo "ERROR: --repo-root origin does not match expected repository ($(redact_github_remote_slug "$repo_root_origin") != $OWNER/$REPO)" >&2
    print_result escalate 0 0 0 repo_root_mismatch repo_root_mismatch
    exit 2
  fi
  if ! CURRENT_SHA="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null)"; then
    CURRENT_SHA=""
  fi
  if [ "$CURRENT_SHA" != "$HEAD_SHA" ]; then
    echo "ERROR: checkout HEAD does not match PR head ($CURRENT_SHA != $HEAD_SHA)" >&2
    print_result escalate 0 0 0 head_mismatch head_mismatch
    exit 2
  fi
  cd "$REPO_ROOT"
fi

if git rev-parse --verify "origin/$BASE_BRANCH" >/dev/null 2>&1; then
  if diff_name_status_full="$(git diff --name-status --find-renames --find-copies "origin/$BASE_BRANCH...HEAD" 2>/dev/null)"; then
    diff_name_status="${diff_name_status_full:0:12000}"
  fi
  if diff_stat_full="$(git diff --stat --find-renames --find-copies "origin/$BASE_BRANCH...HEAD" 2>/dev/null)"; then
    diff_stat="${diff_stat_full:0:12000}"
  fi
fi

if [ ! -f REVIEW.md ]; then
  echo "ERROR: REVIEW.md is required for local review" >&2
  print_result escalate 0 0 0 review_contract_missing review_contract_missing
  exit 2
fi

review_stage_resolved="$(reviewer_resolve_review_stage "$HEAD_BRANCH" "$changed_files_json")"
review_stage="$(printf '%s\n' "$review_stage_resolved" | sed -n '1p')"
review_stage_source="$(printf '%s\n' "$review_stage_resolved" | sed -n '2p')"
review_checklists_csv="$(printf '%s\n' "$review_stage_resolved" | sed -n '3p')"
if [ -n "$review_checklists_csv" ]; then
  review_checklists_json="$(jq -n --arg csv "$review_checklists_csv" '$csv | split(",") | map(select(length > 0))')"
else
  review_checklists_json="[]"
fi

doctrine_supply_json="$(reviewer_doctrine_supply)"
review_doctrine_state="$(printf '%s\n' "$doctrine_supply_json" | jq -r '.state // "unreadable"')"
review_doctrine_pattern_count="$(printf '%s\n' "$doctrine_supply_json" | jq -r '.pattern_count // 0')"
review_doctrine_version="$(printf '%s\n' "$doctrine_supply_json" | jq -r '.version // ""')"

graph_strategy="${LOCAL_AI_REVIEWER_GRAPH_STRATEGY:-none}"
graph_context="none"
case "$graph_strategy" in
  none|'') graph_context="none" ;;
  auto)
    if command -v code-review-graph >/dev/null 2>&1; then
      graph_context="code-review-graph"
    elif command -v graphify >/dev/null 2>&1; then
      graph_context="graphify"
    else
      graph_context="skipped"
    fi
    ;;
  code-review-graph)
    command -v code-review-graph >/dev/null 2>&1 && graph_context="code-review-graph" || graph_context="skipped"
    ;;
  graphify)
    command -v graphify >/dev/null 2>&1 && graph_context="graphify" || graph_context="skipped"
    ;;
  *)
    echo "ERROR: invalid LOCAL_AI_REVIEWER_GRAPH_STRATEGY '$graph_strategy'" >&2
    print_result escalate 0 0 0 malformed_output malformed_output
    exit 2
    ;;
esac

context_file="$(mktemp)"
stdout_file="$(mktemp)"
stderr_file="$(mktemp)"
# cleanup/trap redefined after BASE_BRANCH print once strict temp paths exist

jq -n \
  --arg pr_number "$PR_NUMBER" \
  --arg owner "$OWNER" \
  --arg repo "$REPO" \
  --arg base_branch "$BASE_BRANCH" \
  --arg head_branch "$HEAD_BRANCH" \
  --arg reviewed_head "$HEAD_SHA" \
  --arg graph_context "$graph_context" \
  --arg pr_body "$PR_BODY" \
  --arg diff_name_status "$diff_name_status" \
  --arg diff_stat "$diff_stat" \
  --arg review_stage "$review_stage" \
  --arg review_stage_source "$review_stage_source" \
  --argjson doctrine_supply "$doctrine_supply_json" \
  --argjson changed_files "$changed_files_json" \
  --argjson review_checklists "$review_checklists_json" \
  '{
    schema_version: "local_ai_reviewer_context.v1",
    pr_number: ($pr_number | tonumber),
    owner: $owner,
    repo: $repo,
    base_branch: $base_branch,
    head_branch: $head_branch,
    reviewed_head: $reviewed_head,
    changed_files: $changed_files,
    pr_body: ($pr_body[0:20000]),
    diff_name_status: $diff_name_status,
    diff_stat: $diff_stat,
    review_contract: "REVIEW.md",
    graph_context: $graph_context,
    review_stage: $review_stage,
    review_stage_source: $review_stage_source,
    review_checklists: $review_checklists,
    review_doctrine: $doctrine_supply.text,
    review_doctrine_state: $doctrine_supply.state,
    review_doctrine_pattern_count: $doctrine_supply.pattern_count,
    review_doctrine_version: $doctrine_supply.version
  }' >"$context_file"

print_kv BASE_BRANCH "$BASE_BRANCH"
[ -n "$HEAD_BRANCH" ] && print_kv HEAD_BRANCH "$HEAD_BRANCH"
print_kv REVIEWED_HEAD "$HEAD_SHA"
print_kv GRAPH_CONTEXT "$graph_context"
print_kv REVIEW_STAGE "$review_stage"
print_kv REVIEW_STAGE_SOURCE "$review_stage_source"
[ -n "$review_checklists_csv" ] && print_kv REVIEW_CHECKLISTS "$review_checklists_csv"
print_kv REVIEW_DOCTRINE_STATE "$review_doctrine_state"
print_kv REVIEW_DOCTRINE_PATTERN_COUNT "$review_doctrine_pattern_count"
print_kv REVIEW_DOCTRINE_VERSION "$review_doctrine_version"

# Strict registry state (always emitted after a completed ordinary parse).
strict_spec_state=""
strict_spec_count=""
strict_spec_checks=""
strict_spec_unknown_count=0
strict_spec_reason=""
strict_spec_findings_json="[]"
strict_plan_state=""
strict_plan_count=""
strict_plan_checks=""
strict_plan_applied=""
strict_plan_unknown_count=0
strict_plan_reason=""
strict_plan_findings_json="[]"
strict_plan_applied_set=""
strict_plan_admission_checks_json="[]"
strict_plan_sections_json="[]"
strict_plan_documents_json="[]"
strict_plan_sources_json="[]"

cleanup() {
  rm -f "${context_file:-}" "${stdout_file:-}" "${stderr_file:-}"
}
trap cleanup EXIT

round_start_epoch="$(date +%s)"

set +e
LOCAL_AI_REVIEWER_MODE=ordinary \
CONTEXT_BUNDLE_PATH="$context_file" \
PR_NUMBER="$PR_NUMBER" \
OWNER="$OWNER" \
REPO="$REPO" \
BASE_BRANCH="$BASE_BRANCH" \
HEAD_BRANCH="$HEAD_BRANCH" \
REVIEWED_HEAD="$HEAD_SHA" \
REVIEW_STAGE="$review_stage" \
REVIEW_STAGE_SOURCE="$review_stage_source" \
REVIEW_CHECKLISTS="$review_checklists_csv" \
REVIEW_DOCTRINE_STATE="$review_doctrine_state" \
REVIEW_DOCTRINE_PATTERN_COUNT="$review_doctrine_pattern_count" \
REVIEW_DOCTRINE_VERSION="$review_doctrine_version" \
  run_with_timeout "$TIMEOUT" "$stdout_file" "$stderr_file" sh -c "$LOCAL_AI_REVIEWER_COMMAND"
command_exit=$?
set -e

command_stdout="$(cat "$stdout_file" 2>/dev/null || true)"
command_stderr="$(cat "$stderr_file" 2>/dev/null || true)"

if [ "$command_exit" -eq 124 ]; then
  echo "WARN: local AI reviewer timed out after ${TIMEOUT}s" >&2
  print_result escalate 0 0 0 timeout timeout
  exit 2
fi

combined_output="${command_stdout}
${command_stderr}"
setup_probe_output=""
if [ "$command_exit" -ne 0 ]; then
  setup_probe_output="$command_stderr"
fi
if ! printf '%s\n' "$command_stdout" | jq -e . >/dev/null 2>&1; then
  setup_probe_output="$combined_output"
fi
if [ -n "$setup_probe_output" ] && grep -Eiq 'missing[[:space:]_-]+model|model[[:space:]_-]+access|model.*unavailable' <<< "$setup_probe_output"; then
  print_result escalate 0 0 0 missing_model_access missing_model_access
  exit 2
fi
if [ -n "$setup_probe_output" ] && grep -Eiq 'missing[[:space:]_-]+credentials|credentials[[:space:]_-]+missing|unauthori[sz]ed|forbidden|(^|[^[:alnum:]_])(401|403)([^[:alnum:]_]|$)' <<< "$setup_probe_output"; then
  print_result escalate 0 0 0 missing_credentials missing_credentials
  exit 2
fi
if [ -z "$(printf '%s' "$command_stdout" | tr -d '[:space:]')" ]; then
  echo "WARN: local AI reviewer produced no machine output" >&2
  print_result escalate 0 0 0 malformed_output malformed_output
  exit 2
fi

parse_result="$(
  printf '%s\n' "$command_stdout" | jq -r --arg expected_head "$HEAD_SHA" '
    def findings:
      if (.findings? | type) == "array" then .findings
      elif (.comments? | type) == "array" then .comments
      elif (.issues? | type) == "array" then .issues
      else [] end;
    def text_value:
      [.body?, .message?, .description?, .title?, .summary?, .comment?, .text?]
      | map(select(type == "string" and length > 0)) | .[0] // "";
    def path_value:
      [.path?, .file?, .filename?, .filepath?, .location.path?]
      | map(select(type == "string" and length > 0)) | .[0] // "";
    def line_value:
      [.line?, .startLine?, .start_line?, .location.line?]
      | map(select((type == "number") or (type == "string" and length > 0))) | .[0] // "";
    def severity_text:
      [.severity?, .level?, .priority?, .type?, .classification?, .kind?, .result?]
      | map(select(type == "string")) | join(" ") | ascii_downcase;
    def scope_text:
      [.scope?, .disposition?, .policy?, .category?]
      | map(select(type == "string")) | join(" ") | ascii_downcase;
    def explicit_advisory:
      ((.advisory? == true) or (.decision_bound? == true) or (.scope_expanding? == true))
      or (scope_text | test("advisory|scope.expanding|decision.bound|optional|polish"));
    def blocking:
      (severity_text | test("critical|blocker|blocking|important|error|bug|security|vulnerability|high|major|must.fix|needs.fixes|changes.requested"))
      or (.clear_in_scope? == true)
      or (scope_text | test("clear.in.scope|in.scope|must.fix|needs.fixes"));
    def advisory:
      explicit_advisory or (severity_text | test("minor|low|nit|nitpick|trivial|info|informational|advisory|optional"));
    . as $root
    | ($root.result // "") as $raw_result
    | ($raw_result | tostring | ascii_downcase | gsub("-"; "_")) as $result
    | ($root.reviewed_head // $root.head_sha // $root.head // $expected_head) as $reviewed
    | if $reviewed != $expected_head then
        "PARSE_STATUS=head_mismatch"
      elif ($result != "" and (["clean","needs_fixes","needs_rerun","skipped","escalate"] | index($result) | not)) then
        "PARSE_STATUS=malformed"
      else
        (findings) as $findings
        | ($findings | length) as $comments
        | ($findings | map(select(blocking)) | length) as $blocking
        | ($findings | map(select((blocking | not) and advisory)) | length) as $advisory
        | ($findings | map(select((blocking | not) and (advisory | not))) | length) as $unknown
        | ($findings | map(select(blocking or ((blocking | not) and (advisory | not))))) as $blocking_findings
        | ($blocking_findings
            | to_entries
            | map(
                [
                  "BLOCKING_\(.key + 1)_PATH=\(.value | path_value)",
                  "BLOCKING_\(.key + 1)_LINE=\(.value | line_value)",
                  "BLOCKING_\(.key + 1)_BODY=\(.value | text_value | gsub("\n"; "\\n"))"
                ]
              )
            | flatten
            | join("\n")) as $blocking_lines
        | if $unknown > 0 then
            "PARSE_STATUS=ok\nRESULT=needs_fixes\nCOMMENT_COUNT=\($comments)\nBLOCKING_COUNT=\($blocking + $unknown)\nSUGGESTION_COUNT=\($advisory)\n\($blocking_lines)"
          elif $result == "clean" and $blocking > 0 then
            "PARSE_STATUS=ok\nRESULT=needs_fixes\nCOMMENT_COUNT=\($comments)\nBLOCKING_COUNT=\($blocking)\nSUGGESTION_COUNT=\($advisory)\n\($blocking_lines)"
          elif $result == "" then
            (if $blocking > 0 then "needs_fixes" else "clean" end) as $inferred
            | "PARSE_STATUS=ok\nRESULT=\($inferred)\nCOMMENT_COUNT=\($comments)\nBLOCKING_COUNT=\($blocking)\nSUGGESTION_COUNT=\($advisory)\n\(if $blocking > 0 then $blocking_lines else "" end)"
          else
            "PARSE_STATUS=ok\nRESULT=\($result)\nREASON=\($root.reason // "")\nCOMMENT_COUNT=\($comments)\nBLOCKING_COUNT=\($blocking)\nSUGGESTION_COUNT=\($advisory)\n\(if $result == "needs_fixes" then $blocking_lines else "" end)"
          end
      end
  ' 2>/dev/null
)" || parse_result=""

parse_status="$(printf '%s\n' "$parse_result" | awk -F= '$1 == "PARSE_STATUS" { print $2; exit }')"
case "$parse_status" in
  ok) ;;
  head_mismatch)
    print_result escalate 0 0 0 head_mismatch head_mismatch
    exit 2
    ;;
  *)
    echo "WARN: local AI reviewer output was malformed" >&2
    print_result escalate 0 0 0 malformed_output malformed_output
    exit 2
    ;;
esac

result="$(printf '%s\n' "$parse_result" | awk -F= '$1 == "RESULT" { print $2; exit }')"
reason="$(printf '%s\n' "$parse_result" | awk -F= '$1 == "REASON" { print $2; exit }')"
comment_count="$(printf '%s\n' "$parse_result" | awk -F= '$1 == "COMMENT_COUNT" { print $2; exit }')"
blocking_count="$(printf '%s\n' "$parse_result" | awk -F= '$1 == "BLOCKING_COUNT" { print $2; exit }')"
suggestion_count="$(printf '%s\n' "$parse_result" | awk -F= '$1 == "SUGGESTION_COUNT" { print $2; exit }')"

comment_count="${comment_count:-0}"
blocking_count="${blocking_count:-0}"
suggestion_count="${suggestion_count:-0}"
reason="${reason:-}"

# --- Strict registry passes (at most one dispatches; never merges into blocking) ---
strict_run_all_registry_entries

strict_build_strict_evidence_json() {
  local state="$1"
  local count="$2"
  local checks="$3"
  local applied="$4"
  local unknown_count="$5"
  local reason="$6"

  case "$state" in
    applied)
      if [ -n "$applied" ]; then
        if [ "${unknown_count:-0}" -gt 0 ]; then
          jq -n \
            --arg state "$state" \
            --argjson count "$count" \
            --arg checks "$checks" \
            --arg applied "$applied" \
            --argjson unknown_count "$unknown_count" \
            '{state:$state, count:$count, checks:($checks | if . == "" then [] else (split(",") | map(select(length > 0))) end), applied:($applied | if . == "" then [] else (split(",") | map(select(length > 0))) end), unknown_count:$unknown_count}'
        else
          jq -n \
            --arg state "$state" \
            --argjson count "$count" \
            --arg checks "$checks" \
            --arg applied "$applied" \
            '{state:$state, count:$count, checks:($checks | if . == "" then [] else (split(",") | map(select(length > 0))) end), applied:($applied | if . == "" then [] else (split(",") | map(select(length > 0))) end)}'
        fi
      elif [ "${unknown_count:-0}" -gt 0 ]; then
        jq -n \
          --arg state "$state" \
          --argjson count "$count" \
          --arg checks "$checks" \
          --argjson unknown_count "$unknown_count" \
          '{state:$state, count:$count, checks:($checks | if . == "" then [] else (split(",") | map(select(length > 0))) end), unknown_count:$unknown_count}'
      else
        jq -n \
          --arg state "$state" \
          --argjson count "$count" \
          --arg checks "$checks" \
          '{state:$state, count:$count, checks:($checks | if . == "" then [] else (split(",") | map(select(length > 0))) end)}'
      fi
      ;;
    unavailable|not_applicable)
      if [ -n "$reason" ]; then
        jq -n --arg state "$state" --arg reason "$reason" '{state:$state, reason:$reason}'
      else
        jq -n --arg state "$state" '{state:$state}'
      fi
      ;;
    *)
      jq -n '{}'
      ;;
  esac
}

write_evidence_file() {
  local final_result="$1"
  local final_reason="$2"
  local final_comment_count="$3"
  local final_blocking_count="$4"
  local final_suggestion_count="$5"

  [ -n "${LOCAL_AI_REVIEWER_EVIDENCE_FILE:-}" ] || return 0

  local strict_spec_json strict_plan_json
  strict_spec_json="$(strict_build_strict_evidence_json "$strict_spec_state" "$strict_spec_count" \
    "$strict_spec_checks" "" "$strict_spec_unknown_count" "$strict_spec_reason")"
  strict_plan_json="$(strict_build_strict_evidence_json "$strict_plan_state" "$strict_plan_count" \
    "$strict_plan_checks" "$strict_plan_applied" "$strict_plan_unknown_count" "$strict_plan_reason")"

  if ! jq -n \
    --arg schema_version "local_ai_reviewer_evidence.v1" \
    --arg result "$final_result" \
    --arg reason "$final_reason" \
    --arg pr_number "$PR_NUMBER" \
    --arg owner "$OWNER" \
    --arg repo "$REPO" \
    --arg base_branch "$BASE_BRANCH" \
    --arg head_branch "$HEAD_BRANCH" \
    --arg reviewed_head "$HEAD_SHA" \
    --arg graph_context "$graph_context" \
    --arg pr_body "$PR_BODY" \
    --arg diff_name_status "$diff_name_status" \
    --arg diff_stat "$diff_stat" \
    --arg review_stage "$review_stage" \
    --arg review_stage_source "$review_stage_source" \
    --arg review_checklists "$review_checklists_csv" \
    --arg review_doctrine_state "$review_doctrine_state" \
    --argjson review_doctrine_pattern_count "$review_doctrine_pattern_count" \
    --arg review_doctrine_version "$review_doctrine_version" \
    --argjson changed_files "$changed_files_json" \
    --argjson comment_count "$final_comment_count" \
    --argjson blocking_count "$final_blocking_count" \
    --argjson suggestion_count "$final_suggestion_count" \
    --argjson strict_spec "$strict_spec_json" \
    --argjson strict_plan "$strict_plan_json" \
    '{
      schema_version: $schema_version,
      result: $result,
      reason: $reason,
      pr_number: ($pr_number | tonumber),
      owner: $owner,
      repo: $repo,
      base_branch: $base_branch,
      head_branch: $head_branch,
      reviewed_head: $reviewed_head,
      graph_context: $graph_context,
      counts: {
        comments: $comment_count,
        blocking: $blocking_count,
        suggestions: $suggestion_count
      },
      context_summary: {
        changed_files: $changed_files,
        pr_body: ($pr_body[0:20000]),
        diff_name_status: $diff_name_status,
        diff_stat: $diff_stat
      },
      review_stage: {
        stage: $review_stage,
        source: $review_stage_source,
        checklists: ($review_checklists | if . == "" then [] else (split(",") | map(select(length > 0))) end)
      },
      review_doctrine: {
        state: $review_doctrine_state,
        pattern_count: $review_doctrine_pattern_count,
        version: $review_doctrine_version
      },
      strict_spec: $strict_spec,
      strict_plan: $strict_plan
    }' >"$LOCAL_AI_REVIEWER_EVIDENCE_FILE"; then
    echo "WARN: could not write local AI reviewer evidence file: $LOCAL_AI_REVIEWER_EVIDENCE_FILE" >&2
  fi
}

emit_ordinary_and_strict() {
  # Emit RESULT block then STRICT block. Ordinary verdict is never influenced
  # by strict findings.
  local final_result="$1"
  local final_comment_count="$2"
  local final_blocking_count="$3"
  local final_suggestion_count="$4"
  local final_reason="${5:-}"
  local final_display="${6:-}"

  print_result "$final_result" "$final_comment_count" "$final_blocking_count" \
    "$final_suggestion_count" "$final_reason" "$final_display"
  if [ "$final_result" = "needs_fixes" ]; then
    printf '%s\n' "$parse_result" | awk '/^BLOCKING_[0-9]+_(PATH|LINE|BODY)=/ { print }'
  fi
  emit_strict_spec_output "$strict_spec_state" "$strict_spec_count" \
    "$strict_spec_checks" "$strict_spec_unknown_count" "$strict_spec_reason" "" \
    "$strict_spec_findings_json"
  emit_strict_plan_output "$strict_plan_state" "$strict_plan_count" \
    "$strict_plan_checks" "$strict_plan_unknown_count" "$strict_plan_reason" "$strict_plan_applied" \
    "$strict_plan_findings_json"
}

case "$result" in
  clean)
    if [ "$command_exit" -ne 0 ]; then
      write_evidence_file escalate malformed_output "$comment_count" "$blocking_count" "$suggestion_count"
      emit_ordinary_and_strict escalate "$comment_count" "$blocking_count" "$suggestion_count" malformed_output malformed_output
      exit 2
    fi
    write_evidence_file clean "" "$comment_count" 0 "$suggestion_count"
    emit_ordinary_and_strict clean "$comment_count" 0 "$suggestion_count"
    exit 0
    ;;
  needs_fixes)
    [ "$blocking_count" -eq 0 ] && blocking_count=1
    [ "$comment_count" -eq 0 ] && comment_count=1
    write_evidence_file needs_fixes local_ai_review_findings "$comment_count" "$blocking_count" "$suggestion_count"
    emit_ordinary_and_strict needs_fixes "$comment_count" "$blocking_count" "$suggestion_count" local_ai_review_findings
    exit 1
    ;;
  needs_rerun)
    write_evidence_file needs_rerun "${reason:-needs_rerun}" "$comment_count" "$blocking_count" "$suggestion_count"
    emit_ordinary_and_strict needs_rerun "$comment_count" "$blocking_count" "$suggestion_count" "${reason:-needs_rerun}"
    exit 1
    ;;
  skipped)
    write_evidence_file skipped "${reason:-disabled_by_config}" "$comment_count" "$blocking_count" "$suggestion_count"
    emit_ordinary_and_strict skipped "$comment_count" "$blocking_count" "$suggestion_count" "${reason:-disabled_by_config}" "${reason:-disabled_by_config}"
    exit 3
    ;;
  escalate)
    write_evidence_file escalate "${reason:-malformed_output}" "$comment_count" "$blocking_count" "$suggestion_count"
    emit_ordinary_and_strict escalate "$comment_count" "$blocking_count" "$suggestion_count" "${reason:-malformed_output}" "${reason:-malformed_output}"
    exit 2
    ;;
  *)
    write_evidence_file escalate malformed_output 0 0 0
    emit_ordinary_and_strict escalate 0 0 0 malformed_output malformed_output
    exit 2
    ;;
esac

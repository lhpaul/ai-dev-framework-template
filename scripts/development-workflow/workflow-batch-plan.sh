#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/workflow-batch-plan.sh [development-path ...]

Classifies development folders into batch-planning candidates for the batch
orchestrator. If no paths are given, scans docs/specs/developments/*.
EOF
}

batch_hint_for_action() {
  case "$1" in
    write-plan) printf 'plan-creation\n' ;;
    implement) printf 'implementation\n' ;;
    resolve-development-pr) printf 'resume-development-pr\n' ;;
    *) printf 'manual-review\n' ;;
  esac
}

parallel_safe_for_action() {
  case "$1" in
    write-plan) printf 'yes\n' ;;
    implement|resolve-development-pr) printf 'conditional\n' ;;
    *) printf 'no\n' ;;
  esac
}

# Canonical tool file list for tool-fix classification.
# Each entry is checked with a delimiter-aware regex to reject superstrings.
CANONICAL_EXACT_PATHS=(
  "scripts/development-workflow/pr-review-loop.sh"
  "scripts/development-workflow/pr-ci-loop.sh"
  "scripts/development-workflow/batch-merge.sh"
  "scripts/development-workflow/post-merge-cleanup.sh"
  ".ai-dev-workflow.yaml"
)
PROTOCOLS_PREFIX="docs/workflow/development-workflow/protocols/"

# classify_tool_fix <development-folder-path>
#
# Scans ALL *.md files in the development folder for exact-path references to
# the canonical tool file list.  Uses delimiter-aware regex boundaries to reject
# superstrings (e.g., pr-review-loop.sh.bak must NOT match pr-review-loop.sh).
#
# Prints one of:
#   unknown           — no *.md file found in the folder
#   no                — *.md files found but no canonical path matched
#   yes<newline><comma-list>  — at least one canonical path matched; <comma-list>
#                               is the matched paths separated by commas
classify_tool_fix() {
  local dev_path="$1"
  local doc_files=()

  # Collect all *.md files in the folder (maxdepth 1 — do not recurse).
  while IFS= read -r f; do
    doc_files+=("$f")
  done < <(find "$dev_path" -maxdepth 1 -name '*.md' | sort)

  if [ "${#doc_files[@]}" -eq 0 ]; then
    printf 'unknown\n'
    return 0
  fi

  local matched_paths=()

  # DELIMITER BOUNDARY RATIONALE: grep -F does substring matching, so a naive
  # grep -qF "$path" would match "pr-review-loop.sh" against a line containing
  # "pr-review-loop.sh.bak".  We use an extended-regex with explicit
  # non-path-character boundaries on both sides to reject superstrings.
  local boundary_lead='(^|[^[:alnum:]_./-])'
  local boundary_trail='([^[:alnum:]_./-]|$)'

  for path in "${CANONICAL_EXACT_PATHS[@]}"; do
    # Escape regex metacharacters that could appear in the canonical path.
    local path_regex
    path_regex="$(printf '%s' "$path" | sed 's/[][\\.^$*+?(){}|]/\\&/g')"
    if grep -qE "${boundary_lead}${path_regex}${boundary_trail}" "${doc_files[@]}"; then
      matched_paths+=("$path")
    fi
  done

  # Glob-equivalent: any docs/workflow/development-workflow/protocols/*.md reference,
  # anchored on both sides to reject .md.bak and other superstrings.
  # Both the detection (grep -qE) and the extraction (grep -oE) use the full
  # boundary-anchored regex so superstrings like foo.md.bak are never captured.
  # After -o extracts the full boundary match (which may include a leading
  # non-path delimiter character), grep -oE again pulls out only the path.
  local protocols_regex
  protocols_regex="${boundary_lead}${PROTOCOLS_PREFIX}[^/[:space:]]+\\.md${boundary_trail}"
  if grep -qE "$protocols_regex" "${doc_files[@]}"; then
    while IFS= read -r match; do
      matched_paths+=("$match")
    done < <(grep -hoE "$protocols_regex" "${doc_files[@]}" \
               | grep -oE "${PROTOCOLS_PREFIX}[^/[:space:]]+\\.md" \
               | sort -u)
  fi

  if [ "${#matched_paths[@]}" -gt 0 ]; then
    local IFS=','
    printf 'yes\n%s\n' "${matched_paths[*]}"
  else
    printf 'no\n'
  fi
}

# extract_github_issue_number <development-folder-path>
#
# Extracts the GitHub issue number from the spec or plan markdown files in a
# development folder.  Looks for lines matching:
#   **Issue**: #NNN
#   **Issue**: [#NNN](...)
# and also tries the folder slug prefix pattern (e.g. "291-some-slug" -> 291).
#
# Prints the bare numeric issue number, or an empty string when not found.
extract_github_issue_number() {
  local dev_path="$1"
  local doc_files=() issue_number="" line

  while IFS= read -r f; do
    doc_files+=("$f")
  done < <(find "$dev_path" -maxdepth 1 -name '*.md' | sort)

  # Scan markdown files for "**Issue**: #NNN" or "**Issue**: [#NNN](...)"
  for f in "${doc_files[@]}"; do
    while IFS= read -r line; do
      # Match: **Issue**: #123  or  **Issue**: [#123](url)
      if printf '%s\n' "$line" | grep -qE '^\*\*Issue\*\*:[[:space:]]*\[?#[0-9]+'; then
        issue_number="$(printf '%s\n' "$line" | grep -oE '#[0-9]+' | head -1 | tr -d '#')"
        break 2
      fi
    done < "$f"
  done

  # Fallback: extract leading issue number from folder slug (e.g. "291-some-slug").
  if [ -z "$issue_number" ]; then
    local slug
    slug="$(basename "$dev_path" | sed 's/^[0-9]\{14\}_//')"
    if printf '%s\n' "$slug" | grep -qE '^[0-9]+-'; then
      issue_number="$(printf '%s\n' "$slug" | grep -oE '^[0-9]+')"
    fi
  fi

  printf '%s' "${issue_number:-}"
}

cd_workflow_repo_root

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -gt 0 ]; then
  development_paths=("$@")
else
  if [ -d "docs/specs/developments" ]; then
    development_paths=()
    while IFS= read -r path; do
      development_paths+=("$path")
    done < <(find "docs/specs/developments" -mindepth 1 -maxdepth 1 -type d | sort)
  else
    development_paths=()
  fi
fi

if [ "${#development_paths[@]}" -eq 0 ]; then
  echo "(none)"
  exit 0
fi

# Refresh remote refs once before looping so workflow-next-action.sh skips redundant fetches.
if [ -z "${WORKFLOW_SKIP_FETCH:-}" ]; then
  if ! git fetch --prune origin 2>/dev/null; then
    echo "workflow-batch-plan.sh: warning: git fetch --prune origin failed; branch refs may be stale" >&2
  fi
  export WORKFLOW_SKIP_FETCH=1
fi

for development_path in "${development_paths[@]}"; do
  if [ ! -d "$development_path" ]; then
    echo "Skipping missing development path: $development_path" >&2
    continue
  fi

  slug="$(basename "$development_path" | sed 's/^[0-9]\{14\}_//')"

  # Skip development folders whose tracker status is terminal (Released, Merged,
  # Cancelled).  When GitHub Projects is configured (GITHUB_PROJECT_NUMBER env var
  # or issue_tracker.project_number in .ai-dev-workflow.yaml), query the tracker
  # for each candidate and skip stale folders early — before running the more
  # expensive workflow-next-action.sh call.
  # get_tracker_status_for_issue returns empty string gracefully when no project
  # is configured, so we can call it unconditionally.
  issue_number="$(extract_github_issue_number "$development_path")"
  if [ -n "$issue_number" ]; then
    tracker_status="$(get_tracker_status_for_issue "$issue_number")"
    if is_terminal_tracker_status "$tracker_status"; then
      echo "Skipping $development_path: tracker status is terminal ('$tracker_status') for issue #$issue_number" >&2
      continue
    fi
  fi

  # Classify tool-fix BEFORE workflow-next-action.sh so TOOL_FIX is always
  # emitted, even for folders where next-action exits non-zero (e.g., no
  # spec/plan yet).
  tool_fix_output="$(classify_tool_fix "$development_path")"
  tool_fix="$(printf '%s\n' "$tool_fix_output" | head -1)"
  tool_fix_files=""
  if [ "$tool_fix" = "yes" ]; then
    tool_fix_files="$(printf '%s\n' "$tool_fix_output" | sed -n '2p')"
  fi

  if ! next_action_output="$("$SCRIPT_DIR/workflow-next-action.sh" --development "$development_path" 2>&1)"; then
    # next-action failed (e.g., no merged spec/plan PR yet).  Emit an abbreviated
    # block so the orchestrator still sees TOOL_FIX for this folder.
    echo "Skipping $development_path: $next_action_output" >&2
    print_kv TARGET "development:$development_path"
    print_kv DEVELOPMENT_PATH "$development_path"
    print_kv SLUG "$slug"
    print_kv TOOL_FIX "$tool_fix"
    [ "$tool_fix" = "yes" ] && print_kv TOOL_FIX_FILES "$tool_fix_files"
    echo
    continue
  fi

  status=""
  next_action=""
  linear_issue=""
  while IFS='=' read -r key value; do
    case "$key" in
      STATUS) status="$value" ;;
      NEXT_ACTION) next_action="$value" ;;
      LINEAR_ISSUE) linear_issue="$value" ;;
    esac
  done <<< "$next_action_output"

  print_kv TARGET "development:$development_path"
  print_kv DEVELOPMENT_PATH "$development_path"
  print_kv SLUG "$slug"
  [ -n "$linear_issue" ] && print_kv LINEAR_ISSUE "$linear_issue"
  print_kv STATUS "$status"
  print_kv NEXT_ACTION "$next_action"
  print_kv BATCH_HINT "$(batch_hint_for_action "$next_action")"
  print_kv PARALLEL_SAFE "$(parallel_safe_for_action "$next_action")"
  print_kv TOOL_FIX "$tool_fix"
  [ "$tool_fix" = "yes" ] && print_kv TOOL_FIX_FILES "$tool_fix_files"
  echo
done

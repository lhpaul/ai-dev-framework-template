#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/workflow-batch-plan.sh [--repo <name>] [--repo-root <path>] [development-path ...]

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

# classify_local_runtime <development-folder-path>
#
# Heuristic classifier for implementation items that likely require an
# exclusive local dev server, database, or port-bound resource. Scans the
# implementation plan (when present) for runtime-contention signals.
#
# Prints: none | exclusive
classify_local_runtime() {
  local dev_path="$1"
  local plan_file
  plan_file="$(find "$dev_path" -maxdepth 1 -name '2_*_implementation-plan.md' | head -1)"
  if [ -z "$plan_file" ]; then
    printf 'none\n'
    return 0
  fi

  if grep -qiE \
    '(local[[:space:]]+dev[[:space:]]+server|dev[[:space:]]+server|localhost|127\.0\.0\.1|port[[:space:]]*[0-9]{2,5}|database[[:space:]]+migration|schema[[:space:]]+migration|exclusive[[:space:]]+runtime|shared[[:space:]]+database|docker[[:space:]]+compose|supabase[[:space:]]+local)' \
    "$plan_file"; then
    printf 'exclusive\n'
    return 0
  fi

  printf 'none\n'
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

# extract_file_set <development-folder-path>
#
# Extracts the declared file set from a development folder's implementation plan.
# Looks for a heading matching /files\s+(to\s+(be\s+)?)?modified/i and extracts
# paths from the subsequent fenced code block or bullet list.
#
# Emits:
#   unknown                         — no plan found, or no extractable file list
#   <comma-separated sorted paths>  — normalized repo-root-relative paths
extract_file_set() {
  local dev_path="$1"
  local plan_file
  plan_file="$(find "$dev_path" -maxdepth 1 -name '2_*_implementation-plan.md' | head -1)"
  if [ -z "$plan_file" ]; then
    printf 'unknown\n'
    return 0
  fi

  local paths
  paths="$(python3 - "$plan_file" <<'PYEOF'
import sys, re
text = open(sys.argv[1]).read()
# Find heading matching "files (to (be )?)?modified" (case-insensitive)
# Must not match headings like "files that will be modified later"
heading_re = re.compile(r'#+\s+files\s+(to\s+(be\s+)?)?modified\s*$', re.IGNORECASE)
paths = []
lines = text.splitlines()
i = 0
while i < len(lines):
    if heading_re.search(lines[i]):
        i += 1
        # Skip blank lines between heading and content block
        while i < len(lines) and not lines[i].strip():
            i += 1
        # Try fenced code block
        if i < len(lines) and lines[i].startswith('```'):
            i += 1
            while i < len(lines) and not lines[i].startswith('```'):
                p = lines[i].strip()
                if p:
                    paths.append(p.lstrip('/').replace('\\', '/'))
                i += 1
            if i < len(lines):
                i += 1  # skip closing backticks
        else:
            # Bullet list: consume consecutive "- " or "* " lines (blank lines skipped)
            while i < len(lines):
                stripped = lines[i].strip()
                if not stripped:
                    i += 1
                    continue
                if lines[i].startswith('- ') or lines[i].startswith('* '):
                    p = lines[i][2:].strip()
                    if p:
                        paths.append(p.lstrip('/').replace('\\', '/'))
                    i += 1
                else:
                    break
    else:
        i += 1
seen = set()
deduped = [p for p in paths if not (p in seen or seen.add(p))]
print(','.join(sorted(deduped)) if deduped else 'unknown')
PYEOF
  )"
  printf '%s\n' "$paths"
}

# detect_file_conflicts
#
# Detects file-level conflicts between implementation items in a proposed
# parallel batch.  Accepts arguments in the form:
#   <item-id>:<comma-separated file set>
# where file set may be "unknown".
#
# CONSTRAINT: item-ids must not contain colons.  In practice, Protocol 90 passes
# development folder slugs (e.g. "324-parallel-batch-file-conflict-detection") or
# branch names (e.g. "feature/324-foo").  Neither format includes colons.
# The colon is the separator between item-id and file-set; a colon in the item-id
# would cause silently wrong parsing.
#
# Items whose file set is "unknown" are not automatically serialized but are
# flagged via CONFLICT_UNKNOWN output lines.
#
# For each conflicting pair of items (both with known file sets that share at
# least one path), emits:
#   CONFLICT_PAIR=<higher-priority-id>,<lower-priority-id>
#   CONFLICT_FILES=<comma-separated overlapping paths>
#   SERIALIZE=<lower-priority-id>
#
# For each item with an unknown file set, emits:
#   CONFLICT_UNKNOWN=<item-id>
#
# Serialization tiebreaker implemented here (BR-5 tier 3):
#   Lexicographically earlier item-id stays (earlier = higher priority).
#
# BR-4/BR-5 tiers 1-2 (priority level and creation date) are the responsibility
# of the Protocol 90 orchestrator, which has access to tracker data.  The
# orchestrator must apply tiers 1-2 before calling this helper and may override
# SERIALIZE decisions when tracker data indicates a higher-priority item was
# incorrectly serialized by the lexicographic tiebreaker.
#
# Implementation note: uses parallel indexed arrays (item_ids / item_file_sets)
# instead of associative arrays to remain compatible with bash 3.x (macOS default).
detect_file_conflicts() {
  local -a item_ids=()
  local -a item_file_sets=()

  for arg in "$@"; do
    local item_id="${arg%%:*}"
    local file_set="${arg#*:}"
    item_ids+=("$item_id")
    item_file_sets+=("$file_set")
  done

  local total="${#item_ids[@]}"

  # Emit CONFLICT_UNKNOWN for unknown-set items
  local idx
  for ((idx = 0; idx < total; idx++)); do
    if [ "${item_file_sets[$idx]}" = "unknown" ]; then
      print_kv CONFLICT_UNKNOWN "${item_ids[$idx]}"
    fi
  done

  # Pairwise conflict detection for items with known file sets.
  # Build index lists for known-set items.
  local -a known_indices=()
  for ((idx = 0; idx < total; idx++)); do
    if [ "${item_file_sets[$idx]}" != "unknown" ]; then
      known_indices+=("$idx")
    fi
  done

  local n="${#known_indices[@]}"
  local i j
  for ((i = 0; i < n; i++)); do
    for ((j = i + 1; j < n; j++)); do
      local ix_a="${known_indices[$i]}"
      local ix_b="${known_indices[$j]}"
      local id_a="${item_ids[$ix_a]}"
      local id_b="${item_ids[$ix_b]}"
      local set_a="${item_file_sets[$ix_a]}"
      local set_b="${item_file_sets[$ix_b]}"

      # Compute intersection
      local overlap
      overlap="$(python3 - "$set_a" "$set_b" <<'PYEOF'
import sys
a = set(sys.argv[1].split(',')) if sys.argv[1] else set()
b = set(sys.argv[2].split(',')) if sys.argv[2] else set()
common = sorted(a & b)
print(','.join(common))
PYEOF
      )"

      if [ -n "$overlap" ]; then
        # Determine which item to serialize (lower priority).
        # Compare by lexicographic branch name as tiebreaker (BR-5).
        # The lexicographically smaller (earlier) branch name has higher priority
        # and stays in the current batch; the larger (later) name is serialized.
        local serialize_id higher_id
        if [[ "$id_a" > "$id_b" ]]; then
          serialize_id="$id_a"
          higher_id="$id_b"
        else
          serialize_id="$id_b"
          higher_id="$id_a"
        fi

        print_kv CONFLICT_PAIR "${higher_id},${serialize_id}"
        print_kv CONFLICT_FILES "$overlap"
        print_kv SERIALIZE "$serialize_id"
      fi
    done
  done
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

target_repo=""
repo_root="$(workflow_repo_root)"
development_paths=()

option_value_or_exit() {
  local option="$1"
  local value="${2:-}"
  if [ -z "$value" ] || [[ "$value" == --* ]]; then
    echo "$option requires a value." >&2
    usage >&2
    exit 64
  fi
  printf '%s\n' "$value"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      option="$1"
      shift
      target_repo="$(option_value_or_exit "$option" "${1:-}")"
      shift
      ;;
    --repo-root)
      option="$1"
      shift
      repo_root="$(option_value_or_exit "$option" "${1:-}")"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      development_paths+=("$1")
      shift
      ;;
  esac
done

cd "$repo_root" || exit 1

if [ "${#development_paths[@]}" -eq 0 ]; then
  if [ -d "docs/specs/developments" ]; then
    while IFS= read -r path; do
      development_paths+=("$path")
    done < <(find "docs/specs/developments" -mindepth 1 -maxdepth 1 -type d | sort)
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
  # For the Linear provider, it emits TRACKER_ACTION_REQUIRED=read_status instead
  # of a status string; we detect this and emit TRACKER_STATUS_DEFERRED so the
  # portfolio orchestrator can supply the Linear status from its own context.
  issue_number="$(extract_github_issue_number "$development_path")"
  _project_number="${GITHUB_PROJECT_NUMBER:-$(workflow_issue_tracker_project_number)}"
  if [ -n "$_project_number" ] && [ -z "$issue_number" ]; then
    # GitHub Projects is configured but no issue number found — cannot cross-check
    # tracker.  Treat as Done/skip to avoid false Plan Ready noise from folders
    # with spec+plan but no linked issue.
    echo "Skipping $development_path: no issue number found (no tracker cross-check possible; treating as done)" >&2
    tool_fix_output="$(classify_tool_fix "$development_path")"
    tool_fix="$(printf '%s\n' "$tool_fix_output" | head -1)"
    tool_fix_files=""
    if [ "$tool_fix" = "yes" ]; then
      tool_fix_files="$(printf '%s\n' "$tool_fix_output" | sed -n '2p')"
    fi
    print_kv TARGET "development:$development_path"
    print_kv DEVELOPMENT_PATH "$development_path"
    print_kv SLUG "$slug"
    print_kv STATUS "Done"
    print_kv NEXT_ACTION "skip"
    print_kv SKIP_REASON "no issue number found"
    print_kv BATCH_HINT "manual-review"
    print_kv PARALLEL_SAFE "no"
    print_kv TOOL_FIX "$tool_fix"
    [ "$tool_fix" = "yes" ] && print_kv TOOL_FIX_FILES "$tool_fix_files"
    echo
    continue
  fi
  tracker_status="$(get_tracker_status_for_issue "$issue_number")"
  # Detect the Linear deferred-read signal: filter it out and record that
  # the status read was deferred so the item block can emit
  # TRACKER_STATUS_DEFERRED, signalling the portfolio orchestrator to supply
  # the Linear status from its pre-resolved context.
  _tracker_status_deferred=no
  case "$tracker_status" in
    TRACKER_ACTION_REQUIRED=read_status*)
      _tracker_status_deferred=yes
      tracker_status=""
      ;;
  esac
  if is_terminal_tracker_status "$tracker_status"; then
    echo "Skipping $development_path: tracker status is terminal ('$tracker_status') for issue #$issue_number" >&2
    continue
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

  next_action_args=(--development "$development_path" --repo-root "$repo_root")
  [ -n "$target_repo" ] && next_action_args+=(--repo "$target_repo")
  if ! next_action_output="$("$SCRIPT_DIR/workflow-next-action.sh" "${next_action_args[@]}" 2>&1)"; then
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
  workflow_mode=""
  action_repository_kind=""
  action_repository=""
  action_github_repo=""
  action_local_path=""
  while IFS='=' read -r key value; do
    case "$key" in
      STATUS) status="$value" ;;
      NEXT_ACTION) next_action="$value" ;;
      LINEAR_ISSUE) linear_issue="$value" ;;
      WORKFLOW_MODE) workflow_mode="$value" ;;
      ACTION_REPOSITORY_KIND) action_repository_kind="$value" ;;
      ACTION_REPOSITORY) action_repository="$value" ;;
      ACTION_GITHUB_REPO) action_github_repo="$value" ;;
      ACTION_LOCAL_PATH) action_local_path="$value" ;;
    esac
  done <<< "$next_action_output"

  # Extract file set and local-runtime class for implementation-stage items only (BR-1).
  file_set=""
  local_runtime=""
  case "$next_action" in
    implement|resolve-development-pr)
      file_set="$(extract_file_set "$development_path")"
      local_runtime="$(classify_local_runtime "$development_path")"
      ;;
  esac

  # Spec/plan stage carve-out: TOOL_FIX=unknown at the spec or plan writing stage
  # does NOT indicate a serialization hazard.  Spec/* and implementation-plan/*
  # PRs only write documentation; their reviewer loops do not invoke canonical tool
  # files.  Downgrade 'unknown' to 'no' so the item is not incorrectly serialized.
  # (Protocol 90 § "Spec/plan stage carve-out for TOOL_FIX=unknown")
  case "$next_action" in
    write-plan|run-spec-review-and-open-pr|run-plan-review-and-open-pr)
      if [ "$tool_fix" = "unknown" ]; then
        tool_fix="no"
      fi
      ;;
  esac

  print_kv TARGET "development:$development_path"
  print_kv DEVELOPMENT_PATH "$development_path"
  print_kv SLUG "$slug"
  [ -n "$linear_issue" ] && print_kv LINEAR_ISSUE "$linear_issue"
  [ "$_tracker_status_deferred" = "yes" ] && print_kv TRACKER_STATUS_DEFERRED "$issue_number"
  print_kv STATUS "$status"
  print_kv NEXT_ACTION "$next_action"
  [ -n "$workflow_mode" ] && print_kv WORKFLOW_MODE "$workflow_mode"
  [ -n "$action_repository_kind" ] && print_kv ACTION_REPOSITORY_KIND "$action_repository_kind"
  [ -n "$action_repository" ] && print_kv ACTION_REPOSITORY "$action_repository"
  [ -n "$action_github_repo" ] && print_kv ACTION_GITHUB_REPO "$action_github_repo"
  [ -n "$action_local_path" ] && print_kv ACTION_LOCAL_PATH "$action_local_path"
  print_kv BATCH_HINT "$(batch_hint_for_action "$next_action")"
  print_kv PARALLEL_SAFE "$(parallel_safe_for_action "$next_action")"
  print_kv TOOL_FIX "$tool_fix"
  [ "$tool_fix" = "yes" ] && print_kv TOOL_FIX_FILES "$tool_fix_files"
  [ -n "$file_set" ] && print_kv FILE_SET "$file_set"
  [ -n "$local_runtime" ] && print_kv LOCAL_RUNTIME "$local_runtime"
  echo
done

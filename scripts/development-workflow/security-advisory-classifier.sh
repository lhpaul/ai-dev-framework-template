#!/usr/bin/env bash
# security-advisory-classifier.sh - BR1 two-part (content-category AND
# file-location) classifier for reviewer-platform advisory findings.
#
# See docs/specs/developments/20260811131628_1432-security-advisory-human-decision/
# for the spec and implementation plan this script implements.

set -euo pipefail

error_exit() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/security-advisory-classifier.sh classify \
    --finding-text <text-or-@file> --file-path <path|""> [--diff-hunk <text-or-@file|"">]

Classifies a single advisory finding against BR1's two-part
(content-category AND file-location) security-sensitive test. Prints a JSON
object: {"securitySensitive": bool, "matchedCategory": "a".."e"|null,
"matchedFile": <path>|null}. Read-only: makes no gh/network calls, mutates
nothing.
EOF
}

# Resolves a --finding-text/--diff-hunk value that may be literal text or
# "@<file>" (read the file's contents), mirroring common CLI conventions for
# potentially-large text inputs.
resolve_text_value() {
  local value="$1"
  if [[ "$value" == @* ]]; then
    local file="${value#@}"
    if [ ! -f "$file" ]; then
      error_exit "referenced file not found: $file"
    fi
    cat -- "$file"
  else
    printf '%s' "$value"
  fi
}

# match_re distinguishes "no match" (grep exit 1) from a genuine command
# error (grep exit >=2, e.g. a malformed pattern or an I/O failure) so a
# `grep` failure is never silently treated as a normal non-match. It also
# normalizes embedded newlines to spaces before matching: `grep -qiE`
# evaluates a multiline string one line at a time, so a category regex whose
# two halves land on different lines (a real shape for Markdown-formatted PR
# review-comment bodies) would otherwise never match even though the finding
# text, read as prose, clearly describes the category. Normalizing here --
# not in each call site -- keeps every category test (a)-(e) multiline-safe
# by construction.
match_re() {
  local text="$1" pattern="$2" status normalized
  normalized="${text//$'\n'/ }"
  set +e
  printf '%s' "$normalized" | grep -qiE "$pattern"
  status=$?
  set -e
  if [ "$status" -ge 2 ]; then
    error_exit "internal error: grep failed evaluating pattern"
  fi
  return "$status"
}

# Part A: ordered, first-match content-category test (a)-(e) from BR1.
# Category (a) is tested (and matches) order-independently: "auth ...
# bypass" and "bypass ... auth" both match, so it is checked before the more
# generic category (e) bypass/guard pattern, regardless of which token
# appears first in the finding text.
classify_category() {
  local finding_text="$1"
  if match_re "$finding_text" 'auth(entication|orization)?.*(bypass|skip|spoof)|(bypass|skip|spoof).*auth(entication|orization)?'; then
    printf 'a'
    return 0
  fi
  if match_re "$finding_text" '(secret|credential|token|password).*(expos|log|leak|plaintext)'; then
    printf 'b'
    return 0
  fi
  # Category (c) requires BOTH an unsafe force/history-rewrite keyword AND
  # the absence of a "force-with-lease" (or equivalent safety-lease) phrase
  # -- BR1c is explicitly "a force operation without a safety lease", so a
  # finding that itself states the operation is lease-protected must NOT
  # match. POSIX ERE has no negative lookahead, so this is a positive-match-
  # AND-NOT-safe-phrase check across two match_re calls, not a single regex.
  if match_re "$finding_text" '(force[- ]?push|--force\b|hard reset|history rewrite)' \
    && ! match_re "$finding_text" '(force[- ]?with[- ]?lease|--force-with-lease|with (a |an |the )?(safety[- ]?)?lease)'; then
    printf 'c'
    return 0
  fi
  if match_re "$finding_text" '(injection|unsanitized|eval\(|path.traversal)'; then
    printf 'd'
    return 0
  fi
  if match_re "$finding_text" '(bypass|weaken|disable|circumvent).*(guard|gate|policy|check)'; then
    printf 'e'
    return 0
  fi
  return 1
}

# Part B: explicit 10-entry enforcement-surface allowlist (exact path match,
# no prefix/glob matching except the single .github/workflows/*.yml case).
ENFORCEMENT_SURFACE_FILES=(
  "scripts/development-workflow/checkpoint-resume-gate.sh"
  "scripts/development-workflow/run-epic-delegated-gate.sh"
  "scripts/development-workflow/run-nested-artifact-guard.sh"
  "scripts/development-workflow/scope-residual-gate.sh"
  "scripts/development-workflow/workflow-branch-push-guard.sh"
  "scripts/development-workflow/worktree-cwd-guard.sh"
  "scripts/development-workflow/validate-branch-reuse.sh"
  "scripts/development-workflow/validate-workflow-branch-name.sh"
  "scripts/development-workflow/run-epic-risk-classifier.sh"
  "scripts/development-workflow/run-epic-audit-trail.sh"
)

is_enforcement_surface_file() {
  local file_path="$1" candidate
  for candidate in "${ENFORCEMENT_SURFACE_FILES[@]}"; do
    if [ "$file_path" = "$candidate" ]; then
      return 0
    fi
  done
  return 1
}

is_workflow_yaml_file() {
  local file_path="$1"
  [[ "$file_path" == .github/workflows/*.yml ]] || [[ "$file_path" == .github/workflows/*.yaml ]]
}

# The .github/workflows/*.yml special case additionally requires the finding
# text OR the diff-hunk (when non-empty) to mention a permissions: or
# secrets: YAML key -- this covers a finding comment that discusses the risk
# without quoting the YAML itself, where the key only appears in the diff
# hunk CodeRabbit/PR-Agent attach to the comment.
workflow_yaml_matches_part_b() {
  local finding_text="$1" diff_hunk="$2"
  if match_re "$finding_text" '(permissions|secrets)\s*:'; then
    return 0
  fi
  if [ -n "$diff_hunk" ] && match_re "$diff_hunk" '(permissions|secrets)\s*:'; then
    return 0
  fi
  return 1
}

matches_part_b() {
  local file_path="$1" finding_text="$2" diff_hunk="$3"
  if [ -z "$file_path" ]; then
    return 1
  fi
  if is_workflow_yaml_file "$file_path"; then
    workflow_yaml_matches_part_b "$finding_text" "$diff_hunk"
    return $?
  fi
  is_enforcement_surface_file "$file_path"
}

classify() {
  local finding_text="$1" file_path="$2" diff_hunk="$3"
  local matched_category="" security_sensitive="false" matched_file="null" matched_category_json="null"

  if [ -z "$finding_text" ]; then
    error_exit "--finding-text is required and must be non-empty"
  fi

  if matches_part_b "$file_path" "$finding_text" "$diff_hunk"; then
    if matched_category="$(classify_category "$finding_text")"; then
      security_sensitive="true"
      matched_category_json="\"${matched_category}\""
      matched_file="$(printf '%s' "$file_path" | jq -R '.')"
    fi
  fi

  printf '{"securitySensitive": %s, "matchedCategory": %s, "matchedFile": %s}\n' \
    "$security_sensitive" "$matched_category_json" "$matched_file"
}

command="${1:-}"
if [ "$#" -gt 0 ]; then
  shift
fi

finding_text_arg=""
file_path_arg=""
diff_hunk_arg=""
have_finding_text=0
have_file_path=0

# NOTE: unlike other workflow scripts' require_value(), this one deliberately
# does not reject an empty-string value: --file-path "" and --diff-hunk ""
# are legitimate, expected inputs (PR-level issue comments have no inline
# path or diff-hunk context), not caller-side evidence-assembly noise. It
# still rejects a missing value or one that looks like another flag.
require_value() {
  local option="$1"
  if [ "$#" -lt 2 ] || [ "${2#--}" != "$2" ]; then
    echo "$option requires a value." >&2
    usage >&2
    exit 64
  fi
}

case "$command" in
  classify)
    ;;
  -h|--help|"")
    usage
    exit 0
    ;;
  *)
    echo "ERROR: unknown subcommand: $command" >&2
    usage >&2
    exit 64
    ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --finding-text)
      require_value "$@"
      finding_text_arg="$2"
      have_finding_text=1
      shift 2
      ;;
    --file-path)
      require_value "$@"
      file_path_arg="$2"
      have_file_path=1
      shift 2
      ;;
    --diff-hunk)
      require_value "$@"
      diff_hunk_arg="$2"
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

if [ "$have_finding_text" -ne 1 ]; then
  error_exit "--finding-text is required"
fi
if [ "$have_file_path" -ne 1 ]; then
  error_exit "--file-path is required (pass \"\" for PR-level issue comments with no inline path)"
fi

resolved_finding_text="$(resolve_text_value "$finding_text_arg")"
resolved_file_path="$file_path_arg"
resolved_diff_hunk=""
if [ -n "$diff_hunk_arg" ]; then
  resolved_diff_hunk="$(resolve_text_value "$diff_hunk_arg")"
fi

classify "$resolved_finding_text" "$resolved_file_path" "$resolved_diff_hunk"

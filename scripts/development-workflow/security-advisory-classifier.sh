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
    --finding-text <text> --file-path <path|""> [--diff-hunk <text|"">]
  ./scripts/development-workflow/security-advisory-classifier.sh classify \
    --finding-text-file <file> --file-path <path|""> [--diff-hunk-file <file>]

Classifies a single advisory finding against BR1's two-part
(content-category AND file-location) security-sensitive test. Prints a JSON
object: {"securitySensitive": bool, "matchedCategory": "a".."e"|null,
"matchedFile": <path>|null}. Read-only: makes no gh/network calls, mutates
nothing.

--finding-text/--diff-hunk take the value literally -- never treat it as a
file reference. A real unified-diff hunk header starts with "@@", and a
finding's prose can legitimately start with an "@mention", so any
leading-"@" convenience convention would misclassify genuine input as a
file path. Use --finding-text-file/--diff-hunk-file instead when the value
is large enough to prefer a file.
EOF
}

# Reads a --finding-text-file/--diff-hunk-file value's file contents
# literally. Distinct from the plain --finding-text/--diff-hunk options,
# which always take their value literally and never read a file -- see the
# usage() note above for why an "@file" convenience convention on those
# flags would be unsafe (a real diff-hunk header or an @mention in prose
# both legitimately start with "@").
resolve_text_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    error_exit "referenced file not found: $file"
  fi
  cat -- "$file"
}

# match_re distinguishes "no match" (exit 1) from "match" (exit 0) from a
# genuine command error (exit 3, e.g. a malformed pattern or an I/O failure
# surfaced as grep exit >=2) so a `grep` failure is never silently treated
# as a normal non-match. It deliberately does NOT call error_exit itself:
# classify_category (below) runs inside a command substitution
# (`matched_category="$(classify_category ...)"`), and `exit` from inside a
# command substitution only terminates that subshell -- the parent `if`
# reads any non-zero subshell status as "false" indistinguishably, so a
# genuine internal error would silently classify as "no category matched"
# rather than aborting loudly. Returning a value classify_category can
# itself detect and propagate (and that classify()'s caller can distinguish
# from ordinary "no match") is what keeps the error from being swallowed.
# It also normalizes embedded newlines to spaces before matching: `grep -qiE`
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
    echo "classify: internal error: grep failed evaluating pattern" >&2
    return 3
  fi
  return "$status"
}

# Part A: ordered, first-match content-category test (a)-(e) from BR1.
# Category (a) is tested (and matches) order-independently: "auth ...
# bypass" and "bypass ... auth" both match, so it is checked before the more
# generic category (e) bypass/guard pattern, regardless of which token
# appears first in the finding text.
#
# Every match_re call's status is captured explicitly (never `if match_re
# ...; then`) so a real internal error (status 3) is detected and
# propagated immediately as classify_category's own exit status, instead of
# falling through to the next category check or being indistinguishable
# from "no match" (status 1). See match_re's comment above for why this
# matters specifically inside the command-substitution call chain.
classify_category() {
  local finding_text="$1" status

  # Under `set -e`, a bare `match_re ...` statement followed by `status=$?`
  # on the next line would abort the whole script the instant match_re
  # returns non-zero (an ordinary "no match", status 1, is by far the most
  # common outcome) -- `errexit` only skips a command's exit status when
  # that command sits inside a conditional context (if/while/&&/||), not a
  # plain statement. `... && status=0 || status=$?` keeps every call inside
  # such a context so `set -e` never fires here, while still capturing the
  # exact status (0, 1, or 3) for the explicit checks below.
  match_re "$finding_text" 'auth(entication|orization)?.*(bypass|skip|spoof)|(bypass|skip|spoof).*auth(entication|orization)?' && status=0 || status=$?
  if [ "$status" -ge 2 ]; then return 3; fi
  if [ "$status" -eq 0 ]; then printf 'a'; return 0; fi

  match_re "$finding_text" '(secret|credential|token|password).*(expos|log|leak|plaintext)' && status=0 || status=$?
  if [ "$status" -ge 2 ]; then return 3; fi
  if [ "$status" -eq 0 ]; then printf 'b'; return 0; fi

  # Category (c) requires BOTH an unsafe force/history-rewrite keyword AND
  # the absence of a "force-with-lease" (or equivalent safety-lease) phrase
  # -- BR1c is explicitly "a force operation without a safety lease", so a
  # finding that itself states the operation is lease-protected must NOT
  # match. POSIX ERE has no negative lookahead, so this is a positive-match-
  # AND-NOT-safe-phrase check across two match_re calls, not a single regex.
  match_re "$finding_text" '(force[- ]?push|--force\b|hard reset|history rewrite)' && status=0 || status=$?
  if [ "$status" -ge 2 ]; then return 3; fi
  if [ "$status" -eq 0 ]; then
    match_re "$finding_text" '(force[- ]?with[- ]?lease|--force-with-lease|with (a |an |the )?(safety[- ]?)?lease)' && status=0 || status=$?
    if [ "$status" -ge 2 ]; then return 3; fi
    if [ "$status" -eq 1 ]; then printf 'c'; return 0; fi
  fi

  match_re "$finding_text" '(injection|unsanitized|eval\(|path.traversal)' && status=0 || status=$?
  if [ "$status" -ge 2 ]; then return 3; fi
  if [ "$status" -eq 0 ]; then printf 'd'; return 0; fi

  match_re "$finding_text" '(bypass|weaken|disable|circumvent).*(guard|gate|policy|check)' && status=0 || status=$?
  if [ "$status" -ge 2 ]; then return 3; fi
  if [ "$status" -eq 0 ]; then printf 'e'; return 0; fi

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
  local finding_text="$1" diff_hunk="$2" status
  # See classify_category's comment for why these use `&& status=0 ||
  # status=$?` rather than a bare statement followed by `status=$?`.
  match_re "$finding_text" '(permissions|secrets)\s*:' && status=0 || status=$?
  if [ "$status" -ge 2 ]; then return 3; fi
  if [ "$status" -eq 0 ]; then return 0; fi
  if [ -n "$diff_hunk" ]; then
    match_re "$diff_hunk" '(permissions|secrets)\s*:' && status=0 || status=$?
    if [ "$status" -ge 2 ]; then return 3; fi
    if [ "$status" -eq 0 ]; then return 0; fi
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
  local part_b_status category_status

  if [ -z "$finding_text" ]; then
    error_exit "--finding-text is required and must be non-empty"
  fi

  # Both status captures below are explicit (never `if matches_part_b ...;
  # then` / `if matched_category="$(...)"; then`) so a real internal error
  # (status 3, see match_re) is distinguished from an ordinary "no match"
  # (status 1) and aborts loudly via error_exit instead of silently
  # classifying as not-security-sensitive. `&& part_b_status=0 ||
  # part_b_status=$?` (not a bare statement) is required here for the same
  # `set -e` reason documented on classify_category's match_re calls.
  matches_part_b "$file_path" "$finding_text" "$diff_hunk" && part_b_status=0 || part_b_status=$?
  if [ "$part_b_status" -ge 2 ]; then
    error_exit "internal error: enforcement-surface classification failed"
  fi

  if [ "$part_b_status" -eq 0 ]; then
    category_status=0
    matched_category="$(classify_category "$finding_text")" || category_status=$?
    if [ "$category_status" -ge 2 ]; then
      error_exit "internal error: content-category classification failed"
    fi
    if [ "$category_status" -eq 0 ]; then
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
finding_text_file_arg=""
file_path_arg=""
diff_hunk_arg=""
diff_hunk_file_arg=""
have_finding_text=0
have_finding_text_file=0
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
    --finding-text-file)
      require_value "$@"
      finding_text_file_arg="$2"
      have_finding_text_file=1
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
    --diff-hunk-file)
      require_value "$@"
      diff_hunk_file_arg="$2"
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

if [ "$have_finding_text" -eq 1 ] && [ "$have_finding_text_file" -eq 1 ]; then
  error_exit "--finding-text and --finding-text-file are mutually exclusive"
fi
if [ "$have_finding_text" -ne 1 ] && [ "$have_finding_text_file" -ne 1 ]; then
  error_exit "--finding-text or --finding-text-file is required"
fi
if [ -n "$diff_hunk_arg" ] && [ -n "$diff_hunk_file_arg" ]; then
  error_exit "--diff-hunk and --diff-hunk-file are mutually exclusive"
fi
if [ "$have_file_path" -ne 1 ]; then
  error_exit "--file-path is required (pass \"\" for PR-level issue comments with no inline path)"
fi

if [ "$have_finding_text_file" -eq 1 ]; then
  resolved_finding_text="$(resolve_text_file "$finding_text_file_arg")"
else
  resolved_finding_text="$finding_text_arg"
fi
resolved_file_path="$file_path_arg"
resolved_diff_hunk=""
if [ -n "$diff_hunk_file_arg" ]; then
  resolved_diff_hunk="$(resolve_text_file "$diff_hunk_file_arg")"
elif [ -n "$diff_hunk_arg" ]; then
  resolved_diff_hunk="$diff_hunk_arg"
fi

classify "$resolved_finding_text" "$resolved_file_path" "$resolved_diff_hunk"

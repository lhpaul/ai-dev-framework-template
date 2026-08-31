#!/usr/bin/env bash
# local-codex-review-command.sh - LOCAL_AI_REVIEWER_COMMAND preset for Codex.

set -euo pipefail

codex_bin="${LOCAL_CODEX_REVIEWER_BIN:-codex}"
output_file="$(mktemp)"
cleanup() {
  rm -f "${output_file:-}"
}
trap cleanup EXIT

mode="${LOCAL_AI_REVIEWER_MODE:-ordinary}"

if [ "$mode" = "strict" ]; then
  prompt="${LOCAL_CODEX_REVIEWER_STRICT_PROMPT:-}"
  if [ -z "$prompt" ]; then
    prompt="Apply the strict spec contract checks from the JSON context at ${CONTEXT_BUNDLE_PATH:?} (field strict_spec_checks). Inspect the specification under review against origin/${BASE_BRANCH:-develop}...HEAD. Return only a compact JSON object with fields: mode (must be the string strict_spec_checks), findings array. Each finding must include check (one of the checklist identifiers), path, line, and body (or message). Do not return a review verdict, result, severity, or clear_in_scope. If no strict check fires, return {\"mode\":\"strict_spec_checks\",\"findings\":[]}."
  fi
else
  prompt="${LOCAL_CODEX_REVIEWER_PROMPT:-}"
  if [ -z "$prompt" ]; then
    prompt="Review this PR change using REVIEW.md and the JSON context at ${CONTEXT_BUNDLE_PATH:?}. Inspect the changed files against origin/${BASE_BRANCH:-develop}...HEAD, using the context bundle diff metadata as a guide. Return only a compact JSON object with fields: result (clean or needs_fixes), reviewed_head, findings array. Each finding should include severity, path, line, message, and clear_in_scope. Use needs_fixes only for clear in-scope blocking issues; advisory or nit findings should not block."
  fi
fi

codex_args=(exec --sandbox read-only -C "$PWD" -o "$output_file")
if [ -n "${LOCAL_CODEX_REVIEWER_MODEL:-}" ]; then
  codex_args+=(-m "$LOCAL_CODEX_REVIEWER_MODEL")
fi
codex_args+=("$prompt")

"$codex_bin" "${codex_args[@]}" >/dev/null
cat "$output_file"

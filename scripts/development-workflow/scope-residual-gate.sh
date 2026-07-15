#!/usr/bin/env bash
# scope-residual-gate.sh - Read-only residual verification gate.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scope-residual-gate.sh classify --issue-title <title> [--issue-body-file <file>]
  scope-residual-gate.sh verify --issue-title <title> [--issue-body-file <file>] --evidence <json-file>

Classifies broad-scope sweep, batch, helper-extraction, and pattern-completeness
work and validates explicit residual evidence before workflow readiness. The
helper is read-only: it never edits labels, trackers, PRs, issues, branches, or
files outside caller owned temporary fixtures.
USAGE
}

command="${1:-}"
if [ "$#" -gt 0 ]; then
  shift
fi

issue_title=""
issue_body_file=""
evidence_file=""

error_exit() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 64
}

require_value() {
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ]; then
    printf 'ERROR: %s requires a value\n' "${1:-<unknown>}" >&2
    usage >&2
    exit 64
  fi
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --issue-title)
      require_value "$@"
      issue_title="$2"
      shift 2
      ;;
    --issue-body-file)
      require_value "$@"
      issue_body_file="$2"
      shift 2
      ;;
    --evidence)
      require_value "$@"
      evidence_file="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      error_exit "unknown argument: $1"
      ;;
  esac
done

case "$command" in
  classify|verify) ;;
  *) usage >&2; exit 64 ;;
esac

if [ -z "$issue_title" ]; then
  error_exit "--issue-title is required"
fi
if [ -n "$issue_body_file" ] && [ ! -f "$issue_body_file" ]; then
  error_exit "issue body file not found: $issue_body_file"
fi
if [ "$command" = "verify" ] && [ -n "$evidence_file" ] && [ ! -f "$evidence_file" ]; then
  error_exit "evidence file not found: $evidence_file"
fi

issue_body=""
if [ -n "$issue_body_file" ]; then
  issue_body="$(sed -n '1,240p' "$issue_body_file")"
fi

combined_text="$issue_title
$issue_body"
normalized_text="$(printf '%s\n' "$combined_text" | tr '[:upper:]' '[:lower:]')"

matches_regex() {
  local pattern="$1"
  printf '%s\n' "$normalized_text" | grep -Eq -- "$pattern"
}

extract_numeric_target() {
  printf '%s\n' "$normalized_text" |
    sed -nE 's/.*(^|[^0-9])([1-9][0-9]*)[[:space:]-]+([[:alnum:]_.()/-]+[[:space:]-]+){0,4}(occurrences?|files?|helpers?|callers?|console\.log|debug\(\)|logs?).*/\2/p' |
    sed -n '1p'
}

classification="not_applicable"
classification_reason="no broad sweep, batch, numeric target, or helper-extraction signal detected"
target_count="$(extract_numeric_target)"

if matches_regex '\b(extract|create|add|move|refactor)[[:alnum:] _./()-]*(helper|helpers|shared helper|utility|utilities)\b'; then
  classification="helper_extraction"
  classification_reason="helper extraction signal detected"
elif matches_regex '\b(pattern-completeness|pattern completeness|pattern-based completeness|pattern based completeness|all matches|all occurrences|every occurrence|all references|every reference|live-search|live search)\b'; then
  classification="pattern_completeness"
  classification_reason="pattern-completeness signal detected"
elif [ -n "$target_count" ] && matches_regex '\b(clean|cleanup|remove|delete|replace|refactor|extract|migrate|fix|update)\b'; then
  classification="numeric_sweep"
  classification_reason="numeric sweep or batch target detected"
elif matches_regex '\b(clean|cleanup|remove|delete|replace|refactor|migrate|fix|update)\b' &&
     matches_regex '\b(all|across|codebase-wide|codebase wide|entire|every|multiple|batch)\b'; then
  classification="sweep"
  classification_reason="broad sweep language detected"
elif matches_regex '\b(migrate|clean|cleanup|remove|delete|replace|refactor|fix|update|run|execute)\b' &&
     matches_regex '\b(batch|multiple named targets|several targets)\b'; then
  classification="batch"
  classification_reason="batch work signal detected"
fi

if [ "$command" = "classify" ]; then
  result="not_applicable"
  if [ "$classification" != "not_applicable" ]; then
    result="requires_verification"
  fi
  printf 'RESULT=%s\n' "$result"
  printf 'SCOPE_CLASSIFICATION=%s\n' "$classification"
  printf 'TARGET_COUNT=%s\n' "${target_count:-}"
  printf 'RESIDUAL_GROUPS=0\n'
  printf 'FOLLOW_UPS=0\n'
  printf 'SUMMARY=%s\n' "$classification_reason"
  exit 0
fi

if [ "$classification" = "not_applicable" ]; then
  printf 'RESULT=not_applicable\n'
  printf 'SCOPE_CLASSIFICATION=%s\n' "$classification"
  printf 'TARGET_COUNT=%s\n' "${target_count:-}"
  printf 'RESIDUAL_GROUPS=0\n'
  printf 'FOLLOW_UPS=0\n'
  printf 'SUMMARY=%s\n' "$classification_reason"
  exit 0
fi

if [ -z "$evidence_file" ]; then
  printf 'RESULT=escalate\n'
  printf 'SCOPE_CLASSIFICATION=%s\n' "$classification"
  printf 'TARGET_COUNT=%s\n' "${target_count:-}"
  printf 'RESIDUAL_GROUPS=0\n'
  printf 'FOLLOW_UPS=0\n'
  printf 'SUMMARY=Residual evidence is required before readiness for this broad-scope item.\n'
  exit 1
fi

if ! jq -e 'type == "object"' "$evidence_file" >/dev/null 2>&1; then
  printf 'RESULT=block\n'
  printf 'SCOPE_CLASSIFICATION=%s\n' "$classification"
  printf 'TARGET_COUNT=%s\n' "${target_count:-}"
  printf 'RESIDUAL_GROUPS=0\n'
  printf 'FOLLOW_UPS=0\n'
  printf 'SUMMARY=Residual evidence is missing or is not a JSON object.\n'
  exit 1
fi

if ! validation_json="$(jq -c --arg classification "$classification" '
  def follow_ref:
    tostring | test("(^|[[:space:],;])(#|[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#)[0-9]+($|[[:space:],;])|https://[^[:space:]]+/issues/[0-9]+"; "i");
  def residual_groups: (.residual_groups // .residualGroups // []);
  def helper_outputs: (.helper_outputs // .helperOutputs // []);
  def has_remaining($g): ($g | has("remaining_count") or has("remainingCount"));
  def remaining($g): (($g.remaining_count // $g.remainingCount // 0) | tonumber);
  def disposition($g): ($g.disposition // "");
  def follow($g): ($g.follow_up // $g.followUp // $g.follow_up_issue // $g.followUpIssue // "");
  def helper_name($h): ($h.path // $h.name // $h.summary // "unnamed helper");
  def callers($h): ($h.apparent_callers // $h.apparentCallers // $h.callers // null);
  residual_groups as $groups |
  helper_outputs as $helpers |
  [
    $groups[]? |
    select(has_remaining(.) | not) |
    "residual missing remaining_count: " + ((.summary // .name // "unnamed residual") | tostring)
  ] as $schema_blockers |
  [
    $groups[]? |
    select(has_remaining(.)) |
    select(remaining(.) > 0) |
    select(
      (disposition(.) == "out_of_scope") or
      (disposition(.) == "follow_up" and (follow(.) | follow_ref))
      | not
    ) |
    "undisposed residual: " + ((.summary // .name // "unnamed residual") | tostring)
  ] as $residual_blockers |
  [
    $groups[]? |
    select(has_remaining(.)) |
    select(remaining(.) > 0 and disposition(.) == "follow_up" and (follow(.) | follow_ref))
  ] as $followups |
  [
    if ($classification == "helper_extraction") and (($helpers | length) == 0) then
      "helper caller evidence is missing"
    else empty end,
    $helpers[]? |
    (callers(.) as $callers |
      select(
        (($callers | type) != "array" or ($callers | length) == 0) and
        (
          (disposition(.) == "out_of_scope") or
          (disposition(.) == "follow_up" and (follow(.) | follow_ref))
        | not)
      ) |
      "unused helper without disposition: " + (helper_name(.))
    )
  ] as $helper_blockers |
  {
    residual_count: ($groups | map(select(has_remaining(.) and (remaining(.) > 0))) | length),
    follow_up_count: ($followups | length),
    helper_count: ($helpers | length),
    blockers: ($schema_blockers + $residual_blockers + $helper_blockers)
  }
' "$evidence_file")"; then
  printf 'RESULT=block\n'
  printf 'SCOPE_CLASSIFICATION=%s\n' "$classification"
  printf 'TARGET_COUNT=%s\n' "${target_count:-}"
  printf 'RESIDUAL_GROUPS=0\n'
  printf 'FOLLOW_UPS=0\n'
  printf 'HELPER_OUTPUTS=0\n'
  printf 'SUMMARY=Residual evidence fields could not be parsed.\n'
  exit 1
fi

blocker_count="$(printf '%s\n' "$validation_json" | jq '.blockers | length')"
residual_count="$(printf '%s\n' "$validation_json" | jq '.residual_count')"
follow_up_count="$(printf '%s\n' "$validation_json" | jq '.follow_up_count')"
helper_count="$(printf '%s\n' "$validation_json" | jq '.helper_count')"

if [ "$blocker_count" -gt 0 ]; then
  printf 'RESULT=block\n'
  printf 'SCOPE_CLASSIFICATION=%s\n' "$classification"
  printf 'TARGET_COUNT=%s\n' "${target_count:-}"
  printf 'RESIDUAL_GROUPS=%s\n' "$residual_count"
  printf 'FOLLOW_UPS=%s\n' "$follow_up_count"
  printf 'HELPER_OUTPUTS=%s\n' "$helper_count"
  printf 'SUMMARY=Residual gate blocked readiness: %s\n' "$(printf '%s\n' "$validation_json" | jq -r '.blockers | join("; ")')"
  exit 1
fi

printf 'RESULT=pass\n'
printf 'SCOPE_CLASSIFICATION=%s\n' "$classification"
printf 'TARGET_COUNT=%s\n' "${target_count:-}"
printf 'RESIDUAL_GROUPS=%s\n' "$residual_count"
printf 'FOLLOW_UPS=%s\n' "$follow_up_count"
printf 'HELPER_OUTPUTS=%s\n' "$helper_count"
if [ "$residual_count" -eq 0 ]; then
  printf 'SUMMARY=Residual gate passed: no residuals were found for the checked scope.\n'
else
  printf 'SUMMARY=Residual gate passed: remaining residuals have explicit completed, out-of-scope, or linked follow-up disposition.\n'
fi

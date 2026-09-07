#!/usr/bin/env bash
# review-doctrine-lint.sh
#
# Validates docs/workflow/development-workflow/review-doctrine.md:
#   1. Well-formed entries (AC-2a)
#   2. No mechanically detectable incident references in entries (AC-5)
#   3. Size at or below REVIEW_DOCTRINE_MAX_BYTES (AC-11)
#
# Usage:
#   ./scripts/lint/review-doctrine-lint.sh [review-doctrine.md]
#
# Arguments:
#   FILE   Path to the catalogue (default: docs/workflow/development-workflow/review-doctrine.md)
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/../development-workflow/workflow-lib.sh"

FILE="${1:-docs/workflow/development-workflow/review-doctrine.md}"

if [ ! -f "$FILE" ]; then
  echo "ERROR: file not found: $FILE" >&2
  exit 1
fi

failures=0

report_fail() {
  echo "$1"
  failures=$((failures + 1))
}

# ---------------------------------------------------------------------------
# Check 3: Size (run first — cheap)
# ---------------------------------------------------------------------------
file_bytes="$(wc -c <"$FILE" | tr -d '[:space:]')"
if [ "$file_bytes" -gt "$REVIEW_DOCTRINE_MAX_BYTES" ]; then
  report_fail "review-doctrine size check FAILED: $file_bytes bytes exceeds bound $REVIEW_DOCTRINE_MAX_BYTES"
else
  echo "review-doctrine size check passed: $file_bytes bytes (bound $REVIEW_DOCTRINE_MAX_BYTES)"
fi

# ---------------------------------------------------------------------------
# Parse entries: from each ### heading to the next ### or EOF
# ---------------------------------------------------------------------------
entry_starts=()
while IFS= read -r line; do
  entry_starts+=("$line")
done < <(grep -n '^### ' "$FILE" | cut -d: -f1)

check_entry_well_formed() {
  local entry_text="$1"
  local name="$2"
  local shape_count example_count detect_count
  local shape_line example_line detect_line
  local section_label

  shape_count="$(printf '%s\n' "$entry_text" | grep -c '^\*\*Shape\*\*:' || true)"
  example_count="$(printf '%s\n' "$entry_text" | grep -c '^\*\*Example\*\*:' || true)"
  detect_count="$(printf '%s\n' "$entry_text" | grep -c '^\*\*Detect\*\*:' || true)"

  if [ "$shape_count" -ne 1 ] || [ "$example_count" -ne 1 ] || [ "$detect_count" -ne 1 ]; then
    report_fail "review-doctrine well-formedness FAILED: entry \"$name\" must have exactly one **Shape**:, one **Example**: and one **Detect**: (found shape=$shape_count example=$example_count detect=$detect_count)"
    return 1
  fi

  shape_line="$(printf '%s\n' "$entry_text" | grep -n '^\*\*Shape\*\*:' | head -1 | cut -d: -f1)"
  example_line="$(printf '%s\n' "$entry_text" | grep -n '^\*\*Example\*\*:' | head -1 | cut -d: -f1)"
  detect_line="$(printf '%s\n' "$entry_text" | grep -n '^\*\*Detect\*\*:' | head -1 | cut -d: -f1)"
  if [ "$shape_line" -gt "$example_line" ] || [ "$example_line" -gt "$detect_line" ]; then
    report_fail "review-doctrine well-formedness FAILED: entry \"$name\" must order **Shape**:, **Example**:, **Detect**: (found shape@$shape_line example@$example_line detect@$detect_line)"
    return 1
  fi
  for section_label in Shape Example Detect; do
    if ! section_has_content "$entry_text" "$section_label"; then
      report_fail "review-doctrine well-formedness FAILED: entry \"$name\" section **$section_label**: must contain non-whitespace guidance"
      return 1
    fi
  done
  return 0
}

section_has_content() {
  local entry_text="$1"
  local label="$2"
  awk -v label="$label" '
    BEGIN { marker = "**" label "**:" }
    index($0, marker) == 1 {
      in_section = 1
      rest = substr($0, length(marker) + 1)
      if (rest ~ /[^[:space:]]/) {
        content = 1
      }
      next
    }
    in_section && $0 ~ /^\*\*(Shape|Example|Detect)\*\*:/ { exit }
    in_section && $0 ~ /^### / { exit }
    in_section && $0 ~ /[^[:space:]]/ { content = 1 }
    END { exit content ? 0 : 1 }
  ' <<<"$entry_text"
}

check_entry_incident_refs() {
  local entry_text="$1"
  local name="$2"
  local line_num=0
  local line

  while IFS= read -r line || [ -n "$line" ]; do
    line_num=$((line_num + 1))
    if printf '%s\n' "$line" | grep -Eq '#[0-9]+'; then
      report_fail "review-doctrine incident-reference FAILED: entry \"$name\" line $line_num contains hash-number reference"
    fi
    if printf '%s\n' "$line" | grep -Eq 'github\.com/[^[:space:]]+'; then
      report_fail "review-doctrine incident-reference FAILED: entry \"$name\" line $line_num contains forge URL"
    fi
    if printf '%s\n' "$line" | grep -Eiq '\<(PR|pull request|issue)[[:space:]]+#?[0-9]+'; then
      report_fail "review-doctrine incident-reference FAILED: entry \"$name\" line $line_num contains spelled-out reference"
    fi
    if printf '%s\n' "$line" | grep -Fq 'docs/specs/developments/'; then
      report_fail "review-doctrine incident-reference FAILED: entry \"$name\" line $line_num contains development-folder path"
    fi
  done <<< "$entry_text"
}

if [ "${#entry_starts[@]}" -eq 0 ]; then
  echo "review-doctrine well-formedness passed: no pattern entries (empty catalogue)"
  echo "review-doctrine incident-reference passed: no entries to scan"
else
  well_formed_ok=0
  incident_ok=0
  total_lines="$(awk 'END { print NR }' "$FILE")"
  idx=0
  while [ "$idx" -lt "${#entry_starts[@]}" ]; do
    start="${entry_starts[$idx]}"
    if [ "$idx" -lt $((${#entry_starts[@]} - 1)) ]; then
      end=$((entry_starts[idx + 1] - 1))
    else
      end="$total_lines"
    fi
    entry_name="$(sed -n "${start}p" "$FILE" | sed 's/^### //')"
    entry_text="$(sed -n "${start},${end}p" "$FILE")"
    if check_entry_well_formed "$entry_text" "$entry_name"; then
      well_formed_ok=$((well_formed_ok + 1))
    fi
    check_entry_incident_refs "$entry_text" "$entry_name"
    incident_ok=$((incident_ok + 1))
    idx=$((idx + 1))
  done
  if [ "$well_formed_ok" -eq "${#entry_starts[@]}" ]; then
    echo "review-doctrine well-formedness passed: ${#entry_starts[@]} entries"
  fi
  if [ "$failures" -eq 0 ]; then
    echo "review-doctrine incident-reference passed: ${#entry_starts[@]} entries scanned"
  fi
fi

if [ "$failures" -gt 0 ]; then
  echo ""
  echo "review-doctrine lint FAILED: $failures check(s) failed for $FILE"
  exit 1
fi

echo "review-doctrine lint passed: $FILE"
exit 0

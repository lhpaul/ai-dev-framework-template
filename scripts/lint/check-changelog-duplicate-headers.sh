#!/usr/bin/env bash
# check-changelog-duplicate-headers.sh
#
# Detects duplicate ### sub-headers (e.g., "### Fixed", "### Added") within
# any ## section of CHANGELOG.md.
#
# A duplicate is defined as the same ### heading text appearing more than once
# within the same ## section block.  The check is section-scoped: a ### heading
# that appears once in ## [Unreleased] and once in ## [1.2.3] is NOT a duplicate.
#
# Usage:
#   ./scripts/lint/check-changelog-duplicate-headers.sh [CHANGELOG.md]
#
# Arguments:
#   FILE   Path to the changelog file (default: CHANGELOG.md in the current
#          working directory).
#
# Exit codes:
#   0 — no duplicate sub-headers found
#   1 — one or more duplicate sub-headers found (details printed to stdout)

set -euo pipefail

FILE="${1:-CHANGELOG.md}"

if [ ! -f "$FILE" ]; then
  echo "ERROR: file not found: $FILE" >&2
  exit 1
fi

awk_output=$(awk '
  /^## / {
    # New level-2 section: clear the seen-headers map
    for (k in seen) delete seen[k]
    current_section = $0
  }
  /^### / && current_section != "" {
    # Extract heading text (everything after "### ")
    heading = substr($0, 5)
    # Strip leading/trailing whitespace
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", heading)
    if (seen[heading]++) {
      print "DUPLICATE: \"### " heading "\" appears more than once under section: " current_section
      violations++
    }
  }
  END { print "VIOLATIONS=" violations + 0 }
' "$FILE")

# Extract the violation count from the last marker line
violation_count=$(echo "$awk_output" | grep "^VIOLATIONS=" | sed 's/^VIOLATIONS=//')

# Print only the DUPLICATE lines (not the VIOLATIONS= line)
duplicate_lines=$(echo "$awk_output" | grep "^DUPLICATE:" || true)

if [ "${violation_count:-0}" -gt 0 ]; then
  echo "$duplicate_lines"
  echo ""
  echo "CHANGELOG duplicate-header check FAILED: $violation_count duplicate(s) found in $FILE"
  echo "Fix: merge the duplicate ### sections so each category header appears at most once"
  echo "     per ## section block."
  exit 1
fi

echo "CHANGELOG duplicate-header check passed: no duplicate sub-headers found in $FILE"
exit 0

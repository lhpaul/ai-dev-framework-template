#!/usr/bin/env bash
# check-changelog-duplicate-headers.sh
#
# Two checks are performed:
#
# 1. Duplicate ### sub-headers
#    Detects duplicate ### sub-headers (e.g., "### Fixed", "### Added") within
#    any ## section of CHANGELOG.md.
#    A duplicate is defined as the same ### heading text appearing more than once
#    within the same ## section block.  The check is section-scoped: a ### heading
#    that appears once in ## [Unreleased] and once in ## [1.2.3] is NOT a duplicate.
#
# 2. Missing link reference definitions
#    Every versioned ## [X.Y.Z] section heading must have a corresponding
#    [X.Y.Z]: https://... link reference definition line somewhere in the file.
#    Keep a Changelog convention requires these definitions so that the version
#    headings render as clickable compare links in Markdown renderers.
#    [Unreleased] is also checked when a versioned section exists (it links to
#    the HEAD compare URL).
#
# Usage:
#   ./scripts/lint/check-changelog-duplicate-headers.sh [CHANGELOG.md]
#
# Arguments:
#   FILE   Path to the changelog file (default: CHANGELOG.md in the current
#          working directory).
#
# Exit codes:
#   0 — no violations found
#   1 — one or more violations found (details printed to stdout)

set -euo pipefail

FILE="${1:-CHANGELOG.md}"

if [ ! -f "$FILE" ]; then
  echo "ERROR: file not found: $FILE" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Check 1: Duplicate ### sub-headers within the same ## section
# ---------------------------------------------------------------------------
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

exit_code=0

if [ "${violation_count:-0}" -gt 0 ]; then
  echo "$duplicate_lines"
  echo ""
  echo "CHANGELOG duplicate-header check FAILED: $violation_count duplicate(s) found in $FILE"
  echo "Fix: merge the duplicate ### sections so each category header appears at most once"
  echo "     per ## section block."
  exit_code=1
else
  echo "CHANGELOG duplicate-header check passed: no duplicate sub-headers found in $FILE"
fi

# ---------------------------------------------------------------------------
# Check 2: Missing link reference definitions for ## [X.Y.Z] section headings
#
# Every ## [X.Y.Z] heading (versioned section) must have a corresponding
# [X.Y.Z]: https://... link reference definition line in the file.
# [Unreleased] is also checked when at least one versioned section exists.
# ---------------------------------------------------------------------------
link_ref_violations=0

# Collect all versioned section labels from ## [X.Y.Z] headings.
# Also detect whether [Unreleased] section heading is present.
has_unreleased=false
# Use a newline-delimited string instead of an array for bash 3.2 compatibility
version_labels_str=""
while IFS= read -r line; do
  # Match ## [Unreleased]
  if echo "$line" | grep -qE '^## \[Unreleased\]'; then
    has_unreleased=true
  # Match ## [X.Y.Z] or ## [X.Y.Z] - DATE (semver pattern)
  elif echo "$line" | grep -qE '^## \[[0-9]+\.[0-9]+\.[0-9]+'; then
    label=$(echo "$line" | sed -E 's/^## \[([^]]+)\].*/\1/')
    version_labels_str="${version_labels_str}${label}
"
  fi
done < "$FILE"

# Check [Unreleased] link ref only when versioned sections exist
if $has_unreleased && [ -n "$version_labels_str" ]; then
  if ! grep -qE '^\[Unreleased\]:' "$FILE"; then
    echo "MISSING_LINK_REF: \"[Unreleased]\" section heading has no corresponding link reference definition"
    echo "  Expected a line like: [Unreleased]: https://github.com/owner/repo/compare/vX.Y.Z...HEAD"
    link_ref_violations=$((link_ref_violations + 1))
  fi
fi

# Check each versioned label
while IFS= read -r label; do
  [ -z "$label" ] && continue
  escaped_label=$(printf '%s\n' "$label" | sed 's/[.[\*^$]/\\&/g')
  if ! grep -qE "^\[${escaped_label}\]:" "$FILE"; then
    echo "MISSING_LINK_REF: \"## [${label}]\" section heading has no corresponding link reference definition"
    echo "  Expected a line like: [${label}]: https://github.com/owner/repo/compare/vPREV...v${label}"
    link_ref_violations=$((link_ref_violations + 1))
  fi
done <<< "$version_labels_str"

if [ "$link_ref_violations" -gt 0 ]; then
  echo ""
  echo "CHANGELOG link-reference check FAILED: $link_ref_violations missing definition(s) in $FILE"
  echo "Fix: add a [X.Y.Z]: https://... line at the bottom of the file for each flagged version."
  exit_code=1
else
  echo "CHANGELOG link-reference check passed: all section headings have link reference definitions in $FILE"
fi

exit "$exit_code"

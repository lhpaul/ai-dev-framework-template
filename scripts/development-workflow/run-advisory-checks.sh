#!/usr/bin/env bash

set -euo pipefail

# Optional project extension point for pr-review-loop.sh.
#
# Usage:
#   run-advisory-checks.sh <pr-number>
#
# Downstream projects may replace this no-op body with diff-scoped checks. When
# emitting output, write a complete Markdown-ready advisory section to stdout,
# for example:
#
#   printf '\n\n**Advisory checks** _(informational - never blocks merge)_\n'
#   printf -- '- Dead exports: none found\n'
#
# Stderr is intentionally ignored by the caller, and this script's exit status
# never changes the reviewer-loop result. Keep project-specific tooling bounded
# and fail-open so advisory checks remain informational.

_pr_number="${1:?Usage: $0 <pr-number>}"
: "$_pr_number"

exit 0

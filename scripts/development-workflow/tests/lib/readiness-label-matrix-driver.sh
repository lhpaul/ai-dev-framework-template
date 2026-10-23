# shellcheck shell=bash
# shellcheck source=scripts/development-workflow/tests/lib/readiness-label-fixture.sh
source "$SCRIPT_DIR/lib/readiness-label-fixture.sh"
# shellcheck source=scripts/development-workflow/tests/lib/readiness-label-matrix-setup.sh
source "$SCRIPT_DIR/lib/readiness-label-matrix-setup.sh"
READINESS_MATRIX_INDEX=0
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
READINESS_CASE_SELECTED=0
# shellcheck source=scripts/development-workflow/tests/lib/readiness-label-matrix-cases.sh
source "$SCRIPT_DIR/lib/readiness-label-matrix-cases.sh"
if [ "$READINESS_MATRIX_INDEX" -ne 564 ]; then
  printf '%s\n' 'FAIL: readiness matrix invocation count changed' >&2
  exit 1
fi
if [ -z "${READINESS_MATRIX_RECORD_FILE:-}" ]; then
  expected_assertions="$(python3 - "$SCRIPT_DIR/lib/readiness-label-matrix-manifest.json" "$READINESS_MATRIX_PART" <<'COUNTS'
import json
import sys
print(json.load(open(sys.argv[1]))["part_assertions"][int(sys.argv[2]) - 1])
COUNTS
)"
  # shellcheck disable=SC2154 # Provided by the shared readiness fixture or its caller.
  if [ "$pass" -ne "$expected_assertions" ]; then
    printf '%s\n' 'FAIL: readiness matrix assertion count changed' >&2
    exit 1
  fi
fi
# shellcheck disable=SC2154 # Provided by the shared readiness fixture or its caller.
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

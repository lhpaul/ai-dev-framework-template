# shellcheck shell=bash
set -euo pipefail
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT
build_fake_root() {
  local root="$1"
  local is_template="$2"

  mkdir -p "$root/scripts/development-workflow/tests" "$root/.github/workflows"
  cp "$REPO_ROOT/scripts/development-workflow/workflow-lib.sh" \
    "$root/scripts/development-workflow/workflow-lib.sh"
  printf '%s\n' 'template:' "  is_template: $is_template" > "$root/.ai-dev-workflow.yaml"
}
portable_root="$TMP_ROOT/portable-consumer"
# shellcheck source=scripts/development-workflow/tests/lib/consumer-readiness-fixture.sh
source "$SCRIPT_DIR/lib/consumer-readiness-fixture.sh"
cd "$portable_root"
bash "scripts/development-workflow/tests/test-readiness-label-matrix-part-$READINESS_MATRIX_PART.sh"

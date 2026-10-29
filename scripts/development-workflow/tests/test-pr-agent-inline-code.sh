#!/usr/bin/env bash
# covers: scripts/development-workflow/pr-agent-runtime.py
# covers: scripts/development-workflow/tests/test_pr_agent_inline_code.py
# covers: scripts/development-workflow/tests/test-pr-agent-inline-code.sh
set -euo pipefail
case "${1:-}" in
  ''|--image-smoke) ;;
  *) echo "Usage: $0 [--image-smoke]" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { echo "Usage: $0 [--image-smoke]" >&2; exit 2; }
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
if [ "${1:-}" != --image-smoke ]; then
  python3 "$SCRIPT_DIR/test_pr_agent_inline_code.py"
  exit
fi
IMAGE="$(python3 "$REPO_ROOT/scripts/development-workflow/pr-agent-runtime.py" --image)"
run_image() {
  docker run --rm --network none --entrypoint python \
    --mount "type=bind,src=$REPO_ROOT,dst=/workspace,readonly" \
    --env PR_AGENT_IMAGE_SMOKE=1 --env PYTHONPATH=/app \
    "$IMAGE" /workspace/scripts/development-workflow/tests/test_pr_agent_inline_code.py "$@"
}
run_image
SYNTHETIC_TMP="$(mktemp -d)"
trap 'rm -rf "$SYNTHETIC_TMP"' EXIT
run_image --emit-record > "$SYNTHETIC_TMP/record.json"
jq -ej '.body' "$SYNTHETIC_TMP/record.json" > "$SYNTHETIC_TMP/body"
RESULT="$(bash "$REPO_ROOT/scripts/development-workflow/apply-readiness-labels.sh" --inspect-pr-agent < "$SYNTHETIC_TMP/body")"
printf '%s\n' "$RESULT" | jq -e '.verdict == "clean" and .verification_only == false' >/dev/null
FOCUS="$(bash "$REPO_ROOT/scripts/development-workflow/apply-readiness-labels.sh" --pr-agent-focus-labels < "$SYNTHETIC_TMP/body")"
[ "$FOCUS" = 'Possible Issue' ]
echo 'PASS: pinned renderer -> publication -> independent readback -> unchanged host classifier'

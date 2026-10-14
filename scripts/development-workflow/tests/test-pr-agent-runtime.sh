#!/usr/bin/env bash
# covers: scripts/development-workflow/pr-agent-runtime.py
# covers: scripts/development-workflow/tests/test_pr_agent_runtime.py
# covers: .github/workflows/pr-agent.yml
set -euo pipefail

case "${1:-}" in
  ''|--image-smoke) ;;
  *) echo "Usage: $0 [--image-smoke]" >&2; exit 2 ;;
esac
if [ "$#" -gt 1 ]; then
  echo "Usage: $0 [--image-smoke]" >&2
  exit 2
fi

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
if [ "${1:-}" = --image-smoke ]; then
  IMAGE="$(python3 "$REPO_ROOT/scripts/development-workflow/pr-agent-runtime.py" --image)"
  docker run --rm --network none --entrypoint python \
    --mount "type=bind,src=$REPO_ROOT,dst=/workspace,readonly" \
    --env PR_AGENT_IMAGE_SMOKE=1 --env PYTHONPATH=/app \
    "$IMAGE" /workspace/scripts/development-workflow/tests/test_pr_agent_runtime.py
else
  python3 "$SCRIPT_DIR/test_pr_agent_runtime.py"
fi

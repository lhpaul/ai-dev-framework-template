#!/usr/bin/env bash
# covers: scripts/development-workflow/pr-agent-runtime.py
# covers: scripts/development-workflow/pr-review-loop.sh
# covers: scripts/development-workflow/apply-readiness-labels.sh
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
  D15_TMP="$(mktemp -d)"
  trap 'rm -rf "$D15_TMP"' EXIT
  docker run --rm --network none --entrypoint python \
    --mount "type=bind,src=$REPO_ROOT,dst=/workspace,readonly" \
    --env PR_AGENT_IMAGE_SMOKE=1 --env PYTHONPATH=/app \
    "$IMAGE" /workspace/scripts/development-workflow/tests/test_pr_agent_runtime.py \
      --emit-synthetic-d15-record >"$D15_TMP/record.json"
  jq -e '.creates == 1 and .readbacks == 1' "$D15_TMP/record.json" >/dev/null
  jq -j '.body' "$D15_TMP/record.json" >"$D15_TMP/body"
  # Execute the unmodified consumer predicate on the host. Both negative
  # controls must fail even though the hidden state still names the real SHA.
  HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"
  D15_HEAD="$(jq -r '.head' "$D15_TMP/record.json")"
  pr_agent_summary_marker_names_head "$(cat "$D15_TMP/body")" "$D15_HEAD"
  if pr_agent_summary_marker_names_head "$(cat "$D15_TMP/body")" bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; then
    echo 'FAIL: producer D15 accepted a different head' >&2
    exit 1
  fi
  python3 - "$D15_TMP/record.json" "$D15_TMP/no-visible-marker" <<'PY_D15'
import json
import re
import sys
from pathlib import Path
body = json.loads(Path(sys.argv[1]).read_text())['body']
without_marker, changed = re.subn(r'^#### \(Review updated until commit https://[^\n]+\)\n', '', body, flags=re.M)
assert changed == 1
assert '"head_sha"' in without_marker  # Hidden identity alone is insufficient.
Path(sys.argv[2]).write_text(without_marker)
PY_D15
  if pr_agent_summary_marker_names_head "$(cat "$D15_TMP/no-visible-marker")" "$D15_HEAD"; then
    echo 'FAIL: producer D15 accepted hidden state without a visible marker' >&2
    exit 1
  fi
  echo 'PASS: pinned producer -> host D15; wrong-head and hidden-only controls refused'
else
  python3 "$SCRIPT_DIR/test_pr_agent_runtime.py"
fi

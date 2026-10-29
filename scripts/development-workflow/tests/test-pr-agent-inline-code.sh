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
run_image --emit-records > "$SYNTHETIC_TMP/records.json"
# Python drives actual host entrypoints; it does not reproduce classifier policy.
python3 - "$REPO_ROOT" "$SYNTHETIC_TMP" <<'PY_HOST'
import json
from pathlib import Path
import re
import subprocess
import sys
root, scratch = map(Path, sys.argv[1:])
records = json.loads((scratch / 'records.json').read_text())
for index, record in enumerate(records):
    body = record['body']
    def consumer(flag):
        return subprocess.run(['bash', str(root / 'scripts/development-workflow/apply-readiness-labels.sh'), flag],
                              input=body, text=True, capture_output=True, check=True).stdout.strip()
    observed = json.loads(consumer('--inspect-pr-agent'))
    assert observed == {k: record[k] for k in ('verdict', 'verification_only')}, (record['name'], observed)
    if 'focus' in record:
        assert consumer('--pr-agent-focus-labels') == record['focus'], record['name']
    if record['d15']:
        assert record['creates'] == 1 and record['readbacks'] == 2
        (scratch / ('body-' + str(index))).write_text(body)
        hidden_only, count = re.subn(r'^#### \(Review updated until commit https://[^\n]+\)\n', '', body, flags=re.M)
        assert count == 1 and '"head_sha"' in hidden_only
        (scratch / ('hidden-' + str(index))).write_text(hidden_only)
        print('PASS:', record['name'], observed)
    else:
        print('PASS:', record['name'], observed)
PY_HOST
HARNESS_MODE=1 source "$REPO_ROOT/scripts/development-workflow/pr-review-loop.sh"
for BODY_FILE in "$SYNTHETIC_TMP"/body-*; do
  RECORD_INDEX="${BODY_FILE##*body-}"
  pr_agent_summary_marker_names_head "$(cat "$BODY_FILE")" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  if pr_agent_summary_marker_names_head "$(cat "$BODY_FILE")" bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb; then
    echo 'FAIL: D15 accepted wrong head' >&2
    exit 1
  fi
  if pr_agent_summary_marker_names_head "$(cat "$SYNTHETIC_TMP/hidden-$RECORD_INDEX")" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; then
    echo 'FAIL: D15 accepted hidden-only identity' >&2
    exit 1
  fi
done
echo 'PASS: pinned renderer -> publication/readback -> host classifier/focus/verification/D15 controls'

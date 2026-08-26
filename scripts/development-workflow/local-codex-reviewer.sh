#!/usr/bin/env bash
# local-codex-reviewer.sh - short Codex preset wrapper for local-ai-reviewer.sh.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage: local-codex-reviewer.sh <pr_number> <owner> <repo> [local-ai-reviewer options] [--evidence-file <path>]

Runs local-ai-reviewer.sh with LOCAL_AI_REVIEWER_COMMAND preset to the Codex
read-only command in local-codex-review-command.sh.

Environment:
  LOCAL_CODEX_REVIEWER_BIN     Codex binary to execute. Defaults to codex.
  LOCAL_CODEX_REVIEWER_MODEL   Optional model passed as `codex exec -m`.
  LOCAL_CODEX_REVIEWER_PROMPT  Optional prompt override.
EOF
}

args=()
while [ "$#" -gt 0 ]; do
  case "$1" in
    --evidence-file)
      [ "$#" -ge 2 ] && [ -n "${2:-}" ] || { echo "ERROR: --evidence-file requires a value" >&2; exit 2; }
      export LOCAL_AI_REVIEWER_EVIDENCE_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

export LOCAL_AI_REVIEWER_COMMAND="$SCRIPT_DIR/local-codex-review-command.sh"
exec "$SCRIPT_DIR/local-ai-reviewer.sh" "${args[@]}"

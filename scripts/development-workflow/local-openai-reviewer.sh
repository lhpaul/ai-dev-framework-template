#!/usr/bin/env bash
# local-openai-reviewer.sh - short OpenAI-compatible preset wrapper for
# local-ai-reviewer.sh.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat >&2 <<'EOF'
Usage: local-openai-reviewer.sh <pr_number> <owner> <repo> [local-ai-reviewer options] [--evidence-file <path>]

Runs local-ai-reviewer.sh with LOCAL_AI_REVIEWER_COMMAND preset to the
OpenAI-compatible HTTP command in local-openai-review-command.sh.

Environment:
  LOCAL_AI_REVIEWER_MODEL            Required model id (example: deepseek-v4-pro).
  LOCAL_AI_REVIEWER_API_BASE_URL    Required OpenAI-compatible base URL
                                     (example: https://api.deepseek.com).
  LOCAL_AI_REVIEWER_API_KEY          API key. Falls back to DEEPSEEK_API_KEY or
                                     OPENAI_API_KEY.
  LOCAL_AI_REVIEWER_API_KEY_COMMAND  Optional command that prints the API key.
  LOCAL_AI_REVIEWER_PROMPT           Optional ordinary-pass prompt override.
  LOCAL_AI_REVIEWER_STRICT_PROMPT    Optional strict-pass prompt override.
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

export LOCAL_AI_REVIEWER_COMMAND="$SCRIPT_DIR/local-openai-review-command.sh"
exec "$SCRIPT_DIR/local-ai-reviewer.sh" "${args[@]}"

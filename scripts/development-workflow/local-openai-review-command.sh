#!/usr/bin/env bash
# local-openai-review-command.sh - LOCAL_AI_REVIEWER_COMMAND preset for an
# OpenAI-compatible HTTP backend (DeepSeek, Qwen, GLM, and similar).
#
# Unlike the Codex preset, this command inlines REVIEW.md, the context bundle,
# and a bounded diff because the remote model cannot read the local filesystem.

set -euo pipefail

DIFF_MAX_BYTES="${LOCAL_AI_REVIEWER_DIFF_MAX_BYTES:-200000}"
payload_file="$(mktemp)"
body_file="$(mktemp)"
diff_err="$(mktemp)"
user_file="$(mktemp)"
cleanup() {
  rm -f "${payload_file:-}" "${body_file:-}" "${diff_err:-}" "${user_file:-}"
}
trap cleanup EXIT

mode="${LOCAL_AI_REVIEWER_MODE:-ordinary}"
model="${LOCAL_AI_REVIEWER_MODEL:-}"
base_url="${LOCAL_AI_REVIEWER_API_BASE_URL:-${OPENAI_BASE_URL:-}}"
api_key="${LOCAL_AI_REVIEWER_API_KEY:-}"
curl_bin="${LOCAL_AI_REVIEWER_CURL_BIN:-curl}"
# Keep curl under the companion timeout. DeepSeek often needs 3–4 minutes,
# so callers should raise LOCAL_AI_REVIEWER_TIMEOUT (and optionally
# LOCAL_AI_REVIEWER_HTTP_TIMEOUT) rather than relying on the 300s default.
companion_timeout="${LOCAL_AI_REVIEWER_TIMEOUT:-300}"
case "$companion_timeout" in
  ''|*[!0-9]*) companion_timeout=300 ;;
esac
http_timeout="${LOCAL_AI_REVIEWER_HTTP_TIMEOUT:-}"
case "$http_timeout" in
  ''|*[!0-9]*)
    if [ "$companion_timeout" -gt 30 ]; then
      http_timeout=$((companion_timeout - 30))
    else
      http_timeout="$companion_timeout"
    fi
    ;;
esac
if [ "$http_timeout" -gt "$companion_timeout" ]; then
  http_timeout="$companion_timeout"
fi
json_object="${LOCAL_AI_REVIEWER_JSON_OBJECT:-1}"

if [ -z "$api_key" ] && [ -n "${LOCAL_AI_REVIEWER_API_KEY_COMMAND:-}" ]; then
  api_key="$(sh -c "$LOCAL_AI_REVIEWER_API_KEY_COMMAND")"
fi
if [ -z "$api_key" ]; then
  api_key="${DEEPSEEK_API_KEY:-}"
fi
if [ -z "$api_key" ]; then
  api_key="${OPENAI_API_KEY:-}"
fi

if [ -z "$model" ]; then
  echo "ERROR: LOCAL_AI_REVIEWER_MODEL is not set (missing model)" >&2
  exit 1
fi
if [ -z "$base_url" ]; then
  echo "ERROR: LOCAL_AI_REVIEWER_API_BASE_URL is not set" >&2
  exit 1
fi
if [ -z "$api_key" ]; then
  echo "ERROR: missing credentials — set LOCAL_AI_REVIEWER_API_KEY, DEEPSEEK_API_KEY, OPENAI_API_KEY, or LOCAL_AI_REVIEWER_API_KEY_COMMAND" >&2
  exit 1
fi
if [ -z "${CONTEXT_BUNDLE_PATH:-}" ] || [ ! -f "$CONTEXT_BUNDLE_PATH" ]; then
  echo "ERROR: CONTEXT_BUNDLE_PATH is missing or unreadable" >&2
  exit 1
fi

if [ "$mode" = "strict" ]; then
  prompt="${LOCAL_AI_REVIEWER_STRICT_PROMPT:-}"
  if [ -z "$prompt" ]; then
    if jq -e 'has("strict_plan_checks")' "$CONTEXT_BUNDLE_PATH" >/dev/null 2>&1; then
      prompt="Apply the strict plan contract checks from the JSON context (field strict_plan_checks). Use strict_plan_documents and strict_plan_sources for the full plan and spec text at the reviewed head. Return only a compact JSON object with fields: mode (must be the string strict_plan_checks), findings array. Each finding must include check (one of the applied checklist identifiers), path (the plan document under review), line, and body (or message). Do not return a review verdict, result, severity, or clear_in_scope. If no strict check fires, return {\"mode\":\"strict_plan_checks\",\"findings\":[]}."
    else
      prompt="Apply the strict spec contract checks from the JSON context (field strict_spec_checks). Inspect the specification under review against origin/${BASE_BRANCH:-develop}...HEAD. Return only a compact JSON object with fields: mode (must be the string strict_spec_checks), findings array. Each finding must include check (one of the checklist identifiers), path, line, and body (or message). Do not return a review verdict, result, severity, or clear_in_scope. If no strict check fires, return {\"mode\":\"strict_spec_checks\",\"findings\":[]}."
    fi
  fi
else
  prompt="${LOCAL_AI_REVIEWER_PROMPT:-}"
  if [ -z "$prompt" ]; then
    stage_sentence=""
    if [ -n "${REVIEW_CHECKLISTS:-}" ]; then
      stage_sentence="This change is at the ${REVIEW_STAGE:-unknown} stage. Apply REVIEW.md in full, including its Core Rules, and give particular weight to these sections: ${REVIEW_CHECKLISTS}. "
    fi
    prompt="${stage_sentence}Review this PR change using REVIEW.md and the JSON context included below. Inspect the changed files against origin/${BASE_BRANCH:-develop}...HEAD, using the context bundle diff metadata and the bounded unified diff as a guide. Return only a compact JSON object with fields: result (clean or needs_fixes), reviewed_head, findings array. Each finding should include severity, path, line, message, and clear_in_scope. Use needs_fixes only for clear in-scope blocking issues; advisory or nit findings should not block."
  fi
fi

bundle_json="$(cat "$CONTEXT_BUNDLE_PATH")"
review_md=""
if [ -f "REVIEW.md" ]; then
  review_md="$(cat "REVIEW.md")"
fi
if [ -z "${BASE_BRANCH:-}" ]; then
  echo "ERROR: BASE_BRANCH is not set" >&2
  exit 1
fi
set +e
diff_text="$(git diff --find-renames --find-copies "origin/${BASE_BRANCH}...HEAD" 2>"$diff_err")"
diff_exit=$?
set -e
if [ "$diff_exit" -ne 0 ]; then
  echo "ERROR: git diff origin/${BASE_BRANCH}...HEAD failed (exit ${diff_exit})" >&2
  cat "$diff_err" >&2
  exit 1
fi
if [ "${#diff_text}" -gt "$DIFF_MAX_BYTES" ]; then
  diff_text="${diff_text:0:$DIFF_MAX_BYTES}
... [truncated]"
fi

{
  printf '%s\n\n--- CONTEXT BUNDLE ---\n%s\n\n--- REVIEW.md ---\n%s\n\n--- BOUNDED DIFF ---\n%s\n' \
    "$prompt" "$bundle_json" "$review_md" "$diff_text"
} >"$user_file"

system_content="You are a repository review tool. Return only compact JSON matching the requested schema. Do not wrap the JSON in markdown."

# Read the user prompt from a file. Passing REVIEW.md + the context bundle + a
# bounded diff through jq --arg puts the whole payload on the process argument
# list and can fail with ARG_MAX on typical PRs.
jq_args=(
  -n
  --arg model "$model"
  --arg system "$system_content"
  --rawfile user "$user_file"
)
if [ "$json_object" = "1" ]; then
  jq_args+=(
    '{
      model: $model,
      temperature: 0,
      response_format: {type: "json_object"},
      messages: [
        {role: "system", content: $system},
        {role: "user", content: $user}
      ]
    }'
  )
else
  jq_args+=(
    '{
      model: $model,
      temperature: 0,
      messages: [
        {role: "system", content: $system},
        {role: "user", content: $user}
      ]
    }'
  )
fi
jq "${jq_args[@]}" >"$payload_file"

base_url="${base_url%/}"
url="${base_url}/chat/completions"

set +e
http_code="$("$curl_bin" -sS -o "$body_file" -w '%{http_code}' \
  --max-time "$http_timeout" \
  -H 'Content-Type: application/json' \
  -H "Authorization: Bearer ${api_key}" \
  --data-binary "@${payload_file}" \
  "$url")"
curl_exit=$?
set -e

if [ "$curl_exit" -ne 0 ]; then
  echo "ERROR: openai-compatible reviewer HTTP request failed (curl exit ${curl_exit})" >&2
  exit 1
fi

if [ "$http_code" = "401" ] || [ "$http_code" = "403" ]; then
  echo "ERROR: missing credentials or unauthorized (${http_code})" >&2
  exit 1
fi
if [ "$http_code" != "200" ]; then
  echo "ERROR: openai-compatible reviewer HTTP ${http_code}" >&2
  if grep -Eiq 'missing[[:space:]_-]+model|model[[:space:]_-]+access|model.*unavailable' "$body_file"; then
    echo "ERROR: missing model access" >&2
  fi
  head -c 2000 "$body_file" >&2 || true
  echo >&2
  exit 1
fi

content="$(jq -r '.choices[0].message.content // empty' "$body_file")"
if [ -z "$content" ]; then
  echo "ERROR: openai-compatible reviewer returned empty message content" >&2
  head -c 2000 "$body_file" >&2 || true
  echo >&2
  exit 1
fi

if ! printf '%s\n' "$content" | python3 -c '
import json, re, sys
text = sys.stdin.read().strip()

def emit(obj):
    json.dump(obj, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")

try:
    emit(json.loads(text))
    raise SystemExit(0)
except Exception:
    pass
fence = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.S)
if fence:
    try:
        emit(json.loads(fence.group(1)))
        raise SystemExit(0)
    except Exception:
        pass
brace = re.search(r"\{.*\}", text, re.S)
if brace:
    try:
        emit(json.loads(brace.group(0)))
        raise SystemExit(0)
    except Exception:
        pass
raise SystemExit(1)
'; then
  echo "ERROR: openai-compatible reviewer produced malformed JSON output" >&2
  exit 1
fi

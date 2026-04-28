#!/usr/bin/env bash
# codex-github-reviewer.sh — Codex GitHub App reviewer path for Step 7a
#
# Implements the trigger/poll/parse loop for the Codex GitHub bot reviewer.
# Classifies as universally reachable: requires only gh CLI access (no Codex
# CLI runtime), so it works from Claude Code, Cursor, headless CI, and any
# context where `gh` is authenticated.
#
# Usage:
#   codex-github-reviewer.sh <pr_number> <owner> <repo> [options]
#
# Options:
#   --trigger-phrase <phrase>   Trigger phrase to post. Default: "@codex review"
#                               Also overridable via CODEX_GITHUB_TRIGGER_PHRASE env var.
#   --bot-login     <login>     GitHub login of the Codex bot account.
#                               Default: "codex-ai[bot]"
#                               Also overridable via CODEX_GITHUB_BOT_LOGIN env var.
#                               Verify the actual bot login from your GitHub App settings.
#   --poll-interval <seconds>   Seconds between polling attempts. Default: 30
#   --max-wait      <seconds>   Maximum total wait time for bot response. Default: 300
#
# Exit codes:
#   0 — APPROVED   (bot responded with no blocking findings)
#   1 — NEEDS_REVISION (bot responded with blocking findings)
#   2 — TIMED_OUT  (no bot response within max-wait; treat as unavailable under
#                   configured internal_reviewers_unavailable_policy)
#
# Verdict parsing:
#   The script looks for blocking markers in the bot response body. If any
#   blocking marker is found, the result is NEEDS_REVISION. Otherwise APPROVED.
#   Blocking markers (case-insensitive): "changes requested", "blocking",
#   "must fix", "required:", "action required", "❌".
#   On unrecognized format, the script safe-fails to NEEDS_REVISION.
#
# Idempotency (BR-10):
#   Before posting a trigger comment, the script queries existing PR comments
#   for a trigger comment authored by a human/runner user (not the bot) that
#   contains the current commit SHA. If found, the trigger post is skipped and
#   polling proceeds from the existing trigger timestamp.

set -euo pipefail

# ── Argument parsing ──────────────────────────────────────────────────────────

if [ $# -lt 3 ]; then
  echo "Usage: $0 <pr_number> <owner> <repo> [--trigger-phrase <phrase>] [--bot-login <login>] [--poll-interval <seconds>] [--max-wait <seconds>]" >&2
  exit 2
fi

PR_NUMBER="$1"
OWNER="$2"
REPO="$3"
shift 3

# Defaults (overridable by flags or env vars)
TRIGGER_PHRASE="${CODEX_GITHUB_TRIGGER_PHRASE:-@codex review}"
BOT_LOGIN="${CODEX_GITHUB_BOT_LOGIN:-codex-ai[bot]}"
POLL_INTERVAL=30
MAX_WAIT=300

while [ $# -gt 0 ]; do
  case "$1" in
    --trigger-phrase)
      if [ $# -lt 2 ]; then echo "ERROR: --trigger-phrase requires a value" >&2; exit 2; fi
      TRIGGER_PHRASE="$2"; shift 2;;
    --bot-login)
      if [ $# -lt 2 ]; then echo "ERROR: --bot-login requires a value" >&2; exit 2; fi
      BOT_LOGIN="$2"; shift 2;;
    --poll-interval)
      if [ $# -lt 2 ]; then echo "ERROR: --poll-interval requires a value" >&2; exit 2; fi
      POLL_INTERVAL="$2"; shift 2;;
    --max-wait)
      if [ $# -lt 2 ]; then echo "ERROR: --max-wait requires a value" >&2; exit 2; fi
      MAX_WAIT="$2"; shift 2;;
    *)
      echo "ERROR: unknown option '$1'" >&2; exit 2;;
  esac
done

# ── Pre-flight: verify gh CLI authentication ──────────────────────────────────

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh CLI not authenticated. Run 'gh auth login' before using codex-github-reviewer.sh" >&2
  echo "VERDICT: TIMED_OUT — gh CLI authentication failed (treated as unavailable)"
  exit 2
fi

# ── Resolve current HEAD commit SHA ──────────────────────────────────────────

CURRENT_SHA=$(gh pr view "$PR_NUMBER" --repo "$OWNER/$REPO" --json headRefOid --jq '.headRefOid' | cut -c1-12)
if [ -z "$CURRENT_SHA" ]; then
  echo "ERROR: could not resolve PR #$PR_NUMBER HEAD SHA" >&2
  exit 2
fi

echo "INFO: PR #$PR_NUMBER HEAD commit: $CURRENT_SHA"
echo "INFO: Bot login: $BOT_LOGIN"
echo "INFO: Trigger phrase: $TRIGGER_PHRASE"
echo "INFO: Poll interval: ${POLL_INTERVAL}s, Max wait: ${MAX_WAIT}s"

# ── Idempotency guard (BR-10) ─────────────────────────────────────────────────
# Check whether a trigger comment for the current commit SHA already exists.
# We look for a comment body containing both the trigger phrase prefix and the SHA.

TRIGGER_COMMENT_INFO=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" --paginate \
  --jq ".[] | select(.body | test(\"$(echo "$CURRENT_SHA" | sed 's/[[\\.^$()|?*+{}]/\\\\&/g')\")) | {id: .id, created_at: .created_at, body: .body}" \
  2>/dev/null | head -c 2000 || true)

TRIGGER_TIME=""
if [ -n "$TRIGGER_COMMENT_INFO" ]; then
  TRIGGER_TIME=$(echo "$TRIGGER_COMMENT_INFO" | grep -o '"created_at":"[^"]*"' | head -1 | sed 's/"created_at":"//;s/"//')
  if [ -n "$TRIGGER_TIME" ]; then
    echo "INFO: trigger comment already posted for commit $CURRENT_SHA (at $TRIGGER_TIME) — skipping duplicate post"
  fi
fi

# ── Post trigger comment (if no duplicate found) ──────────────────────────────

if [ -z "$TRIGGER_TIME" ]; then
  echo "INFO: posting trigger comment to PR #$PR_NUMBER..."
  gh pr comment "$PR_NUMBER" --repo "$OWNER/$REPO" \
    --body "$TRIGGER_PHRASE (review triggered by workflow runner, commit: $CURRENT_SHA)"
  # Capture the timestamp of the trigger comment we just posted
  TRIGGER_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "INFO: trigger comment posted at $TRIGGER_TIME"
fi

# ── Poll for bot response ─────────────────────────────────────────────────────

echo "INFO: polling for response from '$BOT_LOGIN' (trigger time: $TRIGGER_TIME)..."

ELAPSED=0
while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  sleep "$POLL_INTERVAL"
  ELAPSED=$((ELAPSED + POLL_INTERVAL))

  echo "INFO: polling... elapsed ${ELAPSED}s / ${MAX_WAIT}s"

  # Query comments authored by the bot that appeared after the trigger comment timestamp.
  # The bot login may include "[bot]" suffix — use exact string match on user.login.
  BOT_RESPONSE=$(gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" --paginate \
    --jq ".[] | select(.user.login == \"$BOT_LOGIN\") | select(.created_at > \"$TRIGGER_TIME\") | .body" \
    2>/dev/null | head -c 10000 || true)

  if [ -n "$BOT_RESPONSE" ]; then
    echo "INFO: bot response detected"

    # ── Verdict parsing ───────────────────────────────────────────────────────
    # Safe-fail: default to NEEDS_REVISION when the response format is unrecognized.
    # APPROVED only when none of the blocking markers are present.
    #
    # Blocking markers (case-insensitive):
    #   - "changes requested"
    #   - "blocking"
    #   - "must fix"
    #   - "required:"
    #   - "action required"
    #   - the ❌ emoji (literal or Unicode escape)
    #
    # Approval signals:
    #   - "approved" or "lgtm" or "looks good" present AND no blocking markers
    #   - no blocking markers at all (conservative: treat silence as approval)

    if echo "$BOT_RESPONSE" | grep -qiE "(changes[[:space:]]+requested|must[[:space:]]+fix|action[[:space:]]+required|required:[[:space:]]|❌)"; then
      echo "VERDICT: NEEDS_REVISION"
      echo "---BEGIN BOT RESPONSE---"
      echo "$BOT_RESPONSE"
      echo "---END BOT RESPONSE---"
      exit 1
    else
      echo "VERDICT: APPROVED"
      echo "---BEGIN BOT RESPONSE---"
      echo "$BOT_RESPONSE"
      echo "---END BOT RESPONSE---"
      exit 0
    fi
  fi
done

# ── Timeout ───────────────────────────────────────────────────────────────────

echo "VERDICT: TIMED_OUT — no response from '$BOT_LOGIN' within ${MAX_WAIT}s after trigger"
echo "INFO: remediation — verify the Codex GitHub App is installed on $OWNER/$REPO."
echo "INFO: You can manually trigger the review by posting: $TRIGGER_PHRASE"
exit 2

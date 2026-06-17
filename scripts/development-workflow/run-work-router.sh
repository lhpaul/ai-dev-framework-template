#!/usr/bin/env bash
# run-work-router.sh — Deterministic routing classifier for /run-work.
#
# Classifies a /run-work invocation into one of five routing modes:
#   no_target_scan | single_item | explicit_list | epic | ambiguous
#
# The script is READ-ONLY: it must not update tracker status, create branches,
# open/edit/merge PRs, close issues, delete branches, or post comments.
#
# Usage:
#   ./scripts/development-workflow/run-work-router.sh [<target>...] [--json]
#   ./scripts/development-workflow/run-work-router.sh --epic <n> [--json]
#
# Outputs stable key=value lines to stdout, followed by a JSON object when
# --json is supplied.
#
# Exit codes:
#   0 — routing mode determined (including ambiguous)
#   1 — script error (bad invocation, missing required env)
#   64 — usage error

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

MODE_NO_TARGET="no_target_scan"
MODE_SINGLE="single_item"
MODE_LIST="explicit_list"
MODE_EPIC="epic"
MODE_AMBIGUOUS="ambiguous"

LABEL_NO_TARGET="No-target scan"
LABEL_SINGLE="Single item"
LABEL_LIST="Explicit list"
LABEL_EPIC="Epic"
LABEL_AMBIGUOUS="Ambiguous"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/run-work-router.sh [<target>...] [--json]
  ./scripts/development-workflow/run-work-router.sh --epic <n> [--json]

Classifies a /run-work invocation into one routing mode:
  no_target_scan  No target supplied; scanner proposes the largest safe plan.
  single_item     Exactly one non-epic item resolved.
  explicit_list   Two or more explicit targets (hard bounded scope).
  epic            Target is epic-like or --epic flag used.
  ambiguous       Cannot deterministically resolve; no mutation allowed.

Flags:
  --epic <n>   Treat <n> as an explicit epic target (skips is_epic_issue check).
  --json       Emit the routing-decision record as a JSON object after key=value lines.

The script is read-only: it performs no tracker updates, branch operations,
PR mutations, or comment posts.
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

json_output=0
epic_flag=""
raw_tokens=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --json)
      json_output=1
      shift
      ;;
    --epic)
      if [ "$#" -lt 2 ] || [ -z "${2:-}" ] || [ "${2#--}" != "$2" ]; then
        echo "--epic requires an issue number." >&2
        usage >&2
        exit 64
      fi
      epic_flag="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        raw_tokens+=("$1")
        shift
      done
      ;;
    --*)
      echo "Unknown flag: $1" >&2
      usage >&2
      exit 64
      ;;
    *)
      raw_tokens+=("$1")
      shift
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Helper: check if a string is a positive integer
# ---------------------------------------------------------------------------

is_positive_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0*) return 1 ;;
    *) return 0 ;;
  esac
}

# ---------------------------------------------------------------------------
# Helper: read guardrails config from .ai-dev-workflow.yaml (read-only)
# ---------------------------------------------------------------------------

read_guardrails_config() {
  local config_file
  config_file="$(workflow_config_file 2>/dev/null)" || true

  GUARDRAILS_SECTION="absent"
  GUARDRAILS_MODE="manual"
  GUARDRAILS_BACKLOG_START="false"

  if [ -z "${config_file:-}" ] || [ ! -f "$config_file" ]; then
    return 0
  fi

  # Use python3 to safely parse YAML (avoid jq YAML limitations)
  local py_result
  py_result="$(python3 - "$config_file" <<'PYEOF' 2>/dev/null || true
import sys, json

try:
    # Try to import yaml; fall back to basic parsing if unavailable.
    try:
        import yaml
        with open(sys.argv[1], 'r') as f:
            cfg = yaml.safe_load(f) or {}
    except ImportError:
        # Minimal YAML-subset reader for flat key: value pairs
        cfg = {}
        with open(sys.argv[1], 'r') as f:
            for line in f:
                line = line.rstrip()
                if ':' in line and not line.lstrip().startswith('#'):
                    key, _, val = line.partition(':')
                    key = key.strip()
                    val = val.strip()
                    cfg[key] = val

    guardrails = cfg.get('guardrails') if isinstance(cfg, dict) else None
    if not isinstance(guardrails, dict):
        print(json.dumps({"section": "absent", "mode": "manual", "backlog_start": False}))
        sys.exit(0)

    mode = guardrails.get('mode', 'manual')
    if mode not in ('manual', 'assisted', 'delegated', 'autonomous'):
        mode = 'manual'

    backlog_start_cfg = guardrails.get('backlog_start', {})
    if isinstance(backlog_start_cfg, dict):
        allow = backlog_start_cfg.get('allow_without_confirmation', False)
    else:
        allow = False
    if not isinstance(allow, bool):
        allow = str(allow).lower() == 'true'

    print(json.dumps({"section": "present", "mode": mode, "backlog_start": allow}))
except Exception as e:
    print(json.dumps({"section": "absent", "mode": "manual", "backlog_start": False}))
PYEOF
)"

  if [ -n "$py_result" ]; then
    local section mode backlog
    section="$(printf '%s\n' "$py_result" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["section"])')" || section="absent"
    mode="$(printf '%s\n' "$py_result" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["mode"])')" || mode="manual"
    backlog="$(printf '%s\n' "$py_result" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(str(d["backlog_start"]).lower())')" || backlog="false"
    GUARDRAILS_SECTION="$section"
    GUARDRAILS_MODE="$mode"
    GUARDRAILS_BACKLOG_START="$backlog"
  fi
}

# ---------------------------------------------------------------------------
# Helper: check whether an issue number refers to an epic-like issue (read-only)
#
# Returns 0 (true) when the issue has sub-issues / child items.
# Returns 1 (false) otherwise.
# When gh is unavailable or the call fails, returns 1 (conservative: not epic).
# ---------------------------------------------------------------------------

is_epic_issue() {
  local issue_num="$1"

  if ! have_cmd gh; then
    return 1
  fi

  # Try to list sub-issues. An exit-0 with at least one entry signals epic-like.
  local sub_count
  sub_count="$(gh issue view "$issue_num" --json subIssues \
    --jq '.subIssues | length' 2>/dev/null)" || return 1

  # Also check if the issue has the "Epic" type label (common convention).
  local issue_type
  issue_type="$(gh issue view "$issue_num" --json 'labels' \
    --jq '[.labels[].name] | map(ascii_downcase) | map(select(. == "epic")) | length' \
    2>/dev/null)" || issue_type="0"

  if [ "${sub_count:-0}" -gt 0 ] || [ "${issue_type:-0}" -gt 0 ]; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Helper: check whether a token resolves to a concrete workflow artifact
#
# Sets RESOLVED_KIND to one of: issue | branch | pr | dev_folder | none
# Returns 0 when resolved, 1 when unresolvable.
# ---------------------------------------------------------------------------

RESOLVED_KIND=""

resolve_token() {
  local token="$1"
  RESOLVED_KIND="none"

  # --- Development folder ---
  if [ -d "$token" ] && [[ "$token" == docs/specs/developments/* ]]; then
    RESOLVED_KIND="dev_folder"
    return 0
  fi

  # --- PR token: #NNN or bare NNN when gh confirms it's a PR ---
  local pr_num="${token#\#}"
  if is_positive_int "$pr_num"; then
    # Try as a PR first; if that fails, try as an issue
    if have_cmd gh; then
      local pr_state
      pr_state="$(gh pr view "$pr_num" --json state --jq '.state' 2>/dev/null)" || true
      if [ -n "$pr_state" ]; then
        RESOLVED_KIND="pr"
        return 0
      fi
      # Try as issue
      local issue_state
      issue_state="$(gh issue view "$pr_num" --json state --jq '.state' 2>/dev/null)" || true
      if [ -n "$issue_state" ]; then
        RESOLVED_KIND="issue"
        return 0
      fi
    fi
    # gh unavailable — treat positive integers as unresolvable in live mode
    # (tests override gh via mock; see test-run-work-router.sh)
    RESOLVED_KIND="none"
    return 1
  fi

  # --- Branch token: known workflow branch prefix patterns ---
  case "$token" in
    feature/*|fix/*|refactor/*|hotfix/*|spec/*|implementation-plan/*|plan/*)
      RESOLVED_KIND="branch"
      return 0
      ;;
  esac

  RESOLVED_KIND="none"
  return 1
}

# ---------------------------------------------------------------------------
# Token normalization: split comma-separated tokens and trim whitespace
# ---------------------------------------------------------------------------

normalized_tokens=()
for t in "${raw_tokens[@]+"${raw_tokens[@]}"}"; do
  # Split on commas
  IFS=',' read -ra parts <<< "$t"
  for p in "${parts[@]}"; do
    # Trim leading/trailing whitespace
    p="${p#"${p%%[![:space:]]*}"}"
    p="${p%"${p##*[![:space:]]}"}"
    if [ -n "$p" ]; then
      normalized_tokens+=("$p")
    fi
  done
done

# Deduplicate tokens (preserve order, keep first occurrence)
deduped_tokens=()
seen_tokens=()
for t in "${normalized_tokens[@]+"${normalized_tokens[@]}"}"; do
  found=0
  for s in "${seen_tokens[@]+"${seen_tokens[@]}"}"; do
    if [ "$s" = "$t" ]; then
      found=1
      break
    fi
  done
  if [ "$found" -eq 0 ]; then
    deduped_tokens+=("$t")
    seen_tokens+=("$t")
  fi
done

# ---------------------------------------------------------------------------
# Read guardrails config (always, for reporting)
# ---------------------------------------------------------------------------

read_guardrails_config

# ---------------------------------------------------------------------------
# Core routing logic
# ---------------------------------------------------------------------------

MODE=""
MODE_LABEL=""
RESOLVED_SCOPE=""
HELD_BACK="(none)"
OUT_OF_SCOPE="(none)"
STOP_REASON=""
RAW_TARGET="(none)"

# Build RAW_TARGET string
if [ -n "$epic_flag" ]; then
  RAW_TARGET="--epic $epic_flag"
elif [ "${#raw_tokens[@]}" -gt 0 ]; then
  RAW_TARGET="${raw_tokens[*]}"
fi

# --------------- Case 1: --epic flag supplied (explicit epic target) -------
if [ -n "$epic_flag" ]; then
  if ! is_positive_int "$epic_flag"; then
    MODE="$MODE_AMBIGUOUS"
    MODE_LABEL="$LABEL_AMBIGUOUS"
    STOP_REASON="--epic value '$epic_flag' is not a valid issue number"
  else
    MODE="$MODE_EPIC"
    MODE_LABEL="$LABEL_EPIC"
    RESOLVED_SCOPE="$epic_flag"
  fi

# --------------- Case 2: no tokens supplied (no-target scan) ---------------
elif [ "${#deduped_tokens[@]}" -eq 0 ]; then
  MODE="$MODE_NO_TARGET"
  MODE_LABEL="$LABEL_NO_TARGET"
  RESOLVED_SCOPE="(none)"

# --------------- Case 3: exactly one token ---------------------------------
elif [ "${#deduped_tokens[@]}" -eq 1 ]; then
  token="${deduped_tokens[0]}"

  # Try to resolve the token
  set +e
  resolve_token "$token"
  resolve_exit=$?
  set -e

  if [ "$resolve_exit" -ne 0 ]; then
    # Unresolvable token → ambiguous
    MODE="$MODE_AMBIGUOUS"
    MODE_LABEL="$LABEL_AMBIGUOUS"
    STOP_REASON="Token '$token' could not be resolved to a known issue, branch, PR, or development folder"
  elif [ "$RESOLVED_KIND" = "issue" ]; then
    # Check if it's an epic-like issue
    issue_num="${token#\#}"
    set +e
    is_epic_issue "$issue_num"
    epic_check=$?
    set -e

    if [ "$epic_check" -eq 0 ]; then
      # single_item → epic upgrade
      MODE="$MODE_EPIC"
      MODE_LABEL="$LABEL_EPIC"
      RESOLVED_SCOPE="$issue_num"
    else
      MODE="$MODE_SINGLE"
      MODE_LABEL="$LABEL_SINGLE"
      RESOLVED_SCOPE="$token"
    fi
  else
    # branch, pr, dev_folder → single_item
    MODE="$MODE_SINGLE"
    MODE_LABEL="$LABEL_SINGLE"
    RESOLVED_SCOPE="$token"
  fi

# --------------- Case 4: two or more tokens --------------------------------
else
  # Resolve each token; any unresolvable → ambiguous
  all_resolved=1
  resolved_list=()
  first_unresolvable=""

  for t in "${deduped_tokens[@]}"; do
    set +e
    resolve_token "$t"
    res_exit=$?
    set -e

    if [ "$res_exit" -ne 0 ]; then
      all_resolved=0
      first_unresolvable="$t"
      break
    fi
    resolved_list+=("$t")
  done

  if [ "$all_resolved" -eq 0 ]; then
    MODE="$MODE_AMBIGUOUS"
    MODE_LABEL="$LABEL_AMBIGUOUS"
    STOP_REASON="Token '$first_unresolvable' in the list could not be resolved to a known issue, branch, PR, or development folder"
  else
    MODE="$MODE_LIST"
    MODE_LABEL="$LABEL_LIST"
    # Build comma-separated resolved scope
    scope_str=""
    for t in "${resolved_list[@]}"; do
      if [ -z "$scope_str" ]; then
        scope_str="$t"
      else
        scope_str="$scope_str,$t"
      fi
    done
    RESOLVED_SCOPE="$scope_str"
  fi
fi

# ---------------------------------------------------------------------------
# Emit routing-decision record (key=value lines)
# ---------------------------------------------------------------------------

echo "MODE=$MODE"
echo "MODE_LABEL=$MODE_LABEL"
echo "RAW_TARGET=$RAW_TARGET"
echo "RESOLVED_SCOPE=${RESOLVED_SCOPE:-(none)}"
echo "HELD_BACK=$HELD_BACK"
echo "OUT_OF_SCOPE=$OUT_OF_SCOPE"
if [ -n "$STOP_REASON" ]; then
  echo "STOP_REASON=$STOP_REASON"
fi
echo "GUARDRAILS_SECTION=$GUARDRAILS_SECTION"
echo "GUARDRAILS_MODE=$GUARDRAILS_MODE"
echo "GUARDRAILS_BACKLOG_START=$GUARDRAILS_BACKLOG_START"

# ---------------------------------------------------------------------------
# Emit JSON record when --json is supplied
# ---------------------------------------------------------------------------

if [ "$json_output" -eq 1 ]; then
  # Build resolved_scope JSON array
  scope_json="[]"
  if [ -n "${RESOLVED_SCOPE:-}" ] && [ "$RESOLVED_SCOPE" != "(none)" ]; then
    scope_json="$(printf '%s\n' "$RESOLVED_SCOPE" | \
      python3 -c '
import json, sys
tokens = [t.strip() for t in sys.stdin.read().strip().split(",") if t.strip()]
print(json.dumps(tokens))
')"
  fi

  stop_reason_json="null"
  if [ -n "${STOP_REASON:-}" ]; then
    stop_reason_json="$(printf '%s\n' "$STOP_REASON" | \
      python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))')"
  fi

  raw_target_json="$(printf '%s\n' "$RAW_TARGET" | \
    python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))')"

  backlog_bool="false"
  if [ "${GUARDRAILS_BACKLOG_START:-false}" = "true" ]; then
    backlog_bool="true"
  fi

  # Build the full JSON record using python3 with --arg style injection to
  # avoid shell-expansion quoting issues inside the heredoc.
  python3 - \
    "$MODE" \
    "$MODE_LABEL" \
    "$raw_target_json" \
    "$scope_json" \
    "$stop_reason_json" \
    "$GUARDRAILS_SECTION" \
    "$GUARDRAILS_MODE" \
    "$backlog_bool" \
    <<'PYJSON'
import json, sys
args = sys.argv[1:]
mode, mode_label, raw_target_json_str, scope_json_str, stop_reason_json_str, \
    guardrails_section, guardrails_mode, backlog_bool_str = args

record = {
    "mode": mode,
    "modeLabel": mode_label,
    "rawTarget": json.loads(raw_target_json_str),
    "resolvedScope": json.loads(scope_json_str),
    "heldBack": [],
    "outOfScope": [],
    "stopReason": json.loads(stop_reason_json_str),
    "guardrails": {
        "section": guardrails_section,
        "mode": guardrails_mode,
        "backlogStart": backlog_bool_str == "true"
    }
}
print(json.dumps(record, indent=2))
PYJSON
fi

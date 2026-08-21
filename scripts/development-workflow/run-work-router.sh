#!/usr/bin/env bash
# run-work-router.sh — Deterministic routing classifier for /run-work.
#
# Classifies a /run-work invocation into one routing mode:
#   no_target_scan | redirect_items | redirect_item | redirect_epic | ambiguous
#   | tracker_unavailable
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
MODE_REDIRECT_ITEM="redirect_item"
MODE_REDIRECT_ITEMS="redirect_items"
MODE_REDIRECT_EPIC="redirect_epic"
MODE_AMBIGUOUS="ambiguous"
MODE_TRACKER_UNAVAILABLE="tracker_unavailable"

LABEL_NO_TARGET="No-target scan"
LABEL_REDIRECT_ITEM="Redirect (item)"
LABEL_REDIRECT_ITEMS="Redirect (items)"
LABEL_REDIRECT_EPIC="Redirect (epic)"
LABEL_AMBIGUOUS="Ambiguous"
LABEL_TRACKER_UNAVAILABLE="Tracker unavailable"

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/run-work-router.sh [<target>...] [--json]
  ./scripts/development-workflow/run-work-router.sh --epic <n> [--json]

Classifies a /run-work invocation into one routing mode:
  no_target_scan   No target supplied; portfolio scan and batch proposal only (no dispatch).
  redirect_items   Two or more explicit targets; redirect to /run-items (no mutation).
  redirect_item    Single non-epic target; redirect to /run-item (no mutation).
  redirect_epic    Epic-like target; redirect to /run-epic (no mutation).
  ambiguous        Cannot deterministically resolve; no mutation allowed.
  tracker_unavailable
                   A gh probe failed (rate limit, auth, network, or GitHub
                   outage) rather than confirming the target does not exist;
                   retry once the underlying cause clears. No mutation allowed.

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
    0) return 1 ;;
    *) return 0 ;;
  esac
}

# ---------------------------------------------------------------------------
# Helper: read guardrails config from .ai-dev-workflow.yaml (read-only)
# ---------------------------------------------------------------------------

read_guardrails_config() {
  GUARDRAILS_SECTION="absent"
  GUARDRAILS_MODE="manual"
  GUARDRAILS_BACKLOG_START="false"

  local config_file _cfg_exit
  _cfg_exit=0
  if [ -n "${AI_DEV_WORKFLOW_CONFIG_FILE:-}" ]; then
    config_file="${AI_DEV_WORKFLOW_CONFIG_FILE}"
  else
    config_file="$(workflow_config_file 2>/dev/null)" || _cfg_exit=$?
    if [ "$_cfg_exit" -ne 0 ]; then
      echo "run-work-router: warning: workflow_config_file lookup failed (exit $_cfg_exit); using guardrails defaults" >&2
      return 0
    fi
  fi

  if [ -z "${config_file:-}" ] || [ ! -f "$config_file" ]; then
    return 0
  fi

  # Use the repo's stdlib-only workflow config parser so the router does not
  # depend on PyYAML being installed in the runner environment.
  # Capture exit code explicitly — do not use || true to suppress failures.
  local py_result _py_exit
  _py_exit=0
  py_result="$(python3 - "$config_file" "$SCRIPT_DIR/workflow-config-resolver.py" <<'PYEOF'
import sys, json
import importlib.util
from pathlib import Path

try:
    sys.dont_write_bytecode = True
    config_path = Path(sys.argv[1])
    resolver_path = Path(sys.argv[2])
    spec = importlib.util.spec_from_file_location("workflow_config_resolver", resolver_path)
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load workflow-config-resolver.py")
    resolver = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(resolver)
    cfg = resolver.parse_yaml_subset(config_path)

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
    sys.stderr.write("run-work-router: warning: YAML parse error: {}\n".format(e))
    print(json.dumps({"section": "absent", "mode": "manual", "backlog_start": False}))
PYEOF
  )" || _py_exit=$?

  if [ "$_py_exit" -ne 0 ]; then
    echo "run-work-router: warning: guardrails config parsing failed (exit $_py_exit); using defaults" >&2
    return 0
  fi

  if [ -n "$py_result" ]; then
    local section mode backlog _sec_exit _mod_exit _bl_exit
    _sec_exit=0; _mod_exit=0; _bl_exit=0
    section="$(printf '%s\n' "$py_result" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["section"])')" || _sec_exit=$?
    mode="$(printf '%s\n' "$py_result" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["mode"])')" || _mod_exit=$?
    backlog="$(printf '%s\n' "$py_result" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(str(d["backlog_start"]).lower())')" || _bl_exit=$?
    if [ "$_sec_exit" -ne 0 ] || [ "$_mod_exit" -ne 0 ] || [ "$_bl_exit" -ne 0 ]; then
      echo "run-work-router: warning: guardrails field extraction failed; using defaults" >&2
      return 0
    fi
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

  # Try sub-issues first; if that API field is unavailable, still check the epic label.
  local sub_count issue_type
  sub_count="$(gh issue view "$issue_num" --json subIssues \
    --jq '.subIssues.totalCount' 2>/dev/null)" || sub_count=""
  case "${sub_count:-}" in
    ''|*[!0-9]*) sub_count="0" ;;
  esac

  issue_type="$(gh issue view "$issue_num" --json 'labels' \
    --jq '[.labels[].name] | map(ascii_downcase) | map(select(. == "epic")) | length' \
    2>/dev/null)" || issue_type="0"

  # Validate issue_type is a non-negative integer.
  case "${issue_type:-}" in
    ''|*[!0-9]*) issue_type="0" ;;
  esac

  if [ "$sub_count" -gt 0 ] || [ "$issue_type" -gt 0 ]; then
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
# Set by resolve_token when it returns 1 to provide a specific failure reason.
# Caller should use this to populate STOP_REASON when the generic message is
# insufficient (e.g., gh CLI missing vs. item not found).
RESOLVE_FAIL_REASON=""
# Set by resolve_token alongside RESOLVE_FAIL_REASON when the failure is a
# probe failure (gh call errored) rather than a confirmed not-found. Callers
# use this to route to MODE_TRACKER_UNAVAILABLE instead of MODE_AMBIGUOUS.
# Values: "" (default — genuine not-found / other unresolvable) |
#         "tracker_unavailable"
RESOLVE_FAIL_KIND=""

# ---------------------------------------------------------------------------
# Helper: run a gh probe capturing stdout, stderr, and exit code separately.
#
# Unlike `gh ... 2>/dev/null || true`, this lets callers distinguish a probe
# failure (rate limit, auth, network, GitHub outage) from a successful call
# that simply found nothing. Sets PROBE_OUT, PROBE_ERR, PROBE_EXIT. Never
# triggers `set -e` regardless of the underlying gh exit status, and restores
# the caller's original errexit state on return rather than forcing it back
# on — callers (resolve_token's call sites) rely on `set +e` remaining in
# effect around the whole resolve_token() call, and unconditionally
# re-enabling errexit here would make a later `return 1` from resolve_token
# terminate the script immediately instead of letting the caller inspect $?.
# ---------------------------------------------------------------------------

PROBE_OUT=""
PROBE_ERR=""
PROBE_EXIT=0

gh_probe() {
  local err_file errexit_was_set
  errexit_was_set=0
  case "$-" in *e*) errexit_was_set=1 ;; esac
  set +e
  # If temp-file setup itself fails, do not let a resulting empty PROBE_ERR
  # be misread downstream as gh's own empty-stderr not-found case (exit 1).
  # Use exit code 125 (a value gh itself never returns) with a diagnostic
  # PROBE_ERR so classify_gh_probe_error() correctly treats this as an
  # infrastructure failure (github_unavailable), not a not-found.
  if ! err_file="$(mktemp)"; then
    PROBE_OUT=""
    PROBE_ERR="gh_probe: mktemp failed while preparing to capture gh stderr"
    PROBE_EXIT=125
    if [ "$errexit_was_set" -eq 1 ]; then
      set -e
    fi
    return 0
  fi
  PROBE_OUT="$(gh "$@" 2>"$err_file")"
  PROBE_EXIT=$?
  # Capture stderr and clean up the temp file while errexit is still
  # disabled — a failing `cat` (e.g. the temp file became unreadable) must
  # not itself trigger `set -e` and terminate the script ahead of the
  # caller's own `$?` check, once errexit is restored below.
  if ! PROBE_ERR="$(cat "$err_file")"; then
    PROBE_OUT=""
    PROBE_ERR="gh_probe: failed to read captured gh stderr"
    PROBE_EXIT=125
  fi
  rm -f "$err_file" 2>/dev/null
  if [ "$errexit_was_set" -eq 1 ]; then
    set -e
  fi
}

# ---------------------------------------------------------------------------
# Helper: classify a gh probe's stderr (and exit code) into a failure cause.
#
# Echoes one of: not_found | rate_limited | auth_failed | network_error |
# github_unavailable
#
# A confirmed "not found" response (gh's own "could not resolve to a
# PullRequest/Issue" message) is classified as not_found so genuinely unknown
# targets keep resolving to MODE_AMBIGUOUS exactly as before. An empty stderr
# is only treated as not_found when the exit code is gh's normal API-error
# exit code (1) — this repo's probes have historically seen exit 1 with no
# captured stderr for a genuine not-found. An empty stderr paired with any
# other exit code (a signal death, an OOM kill, a shell-level launch failure,
# etc.) is NOT assumed to be a not-found — it falls back to
# github_unavailable, since gh crashing or being killed is a probe failure,
# not evidence the target doesn't exist. Any other non-empty, unrecognized
# stderr also falls back to github_unavailable so opaque outages are treated
# as probe failures rather than silently swallowed as not-found. This
# deliberately includes gh's "no default remote repository has been set"
# message — that is a local repository-configuration error (gh cannot
# determine which repository to query), not confirmation that the PR or
# issue does not exist, so it must NOT be classified as not_found.
# ---------------------------------------------------------------------------

classify_gh_probe_error() {
  local err="$1" exit_code="${2:-1}"
  local err_lc
  err_lc="$(printf '%s' "$err" | tr '[:upper:]' '[:lower:]')"

  if [ -z "$err_lc" ]; then
    if [ "$exit_code" = "1" ]; then
      echo "not_found"
    else
      echo "github_unavailable"
    fi
    return 0
  fi

  case "$err_lc" in
    *"could not resolve to a pullrequest"*|*"could not resolve to an issue"*|*"no pull requests found"*)
      echo "not_found"
      return 0
      ;;
  esac

  case "$err_lc" in
    *"api rate limit"*|*"rate limit exceeded"*|*"secondary rate limit"*)
      echo "rate_limited"
      return 0
      ;;
  esac

  case "$err_lc" in
    *"gh auth login"*|*"gh auth refresh"*|*"not logged into"*|*"bad credentials"*|*"requires authentication"*|*"http 401"*|*"401 unauthorized"*|*"authentication required"*)
      echo "auth_failed"
      return 0
      ;;
  esac

  case "$err_lc" in
    *"could not resolve host"*|*"connection refused"*|*"connection reset"*|*"network is unreachable"*|*"no such host"*|*"context deadline exceeded"*|*"timed out"*|*"dial tcp"*)
      echo "network_error"
      return 0
      ;;
  esac

  echo "github_unavailable"
}

# ---------------------------------------------------------------------------
# Helper: best-effort rate-limit reset time for the reason string.
#
# Queries `gh api rate_limit` for the GraphQL quota reset epoch and formats
# it as UTC. Never fails the caller — an unavailable/erroring rate_limit call
# just omits the timestamp from the reason string.
# ---------------------------------------------------------------------------

gh_rate_limit_reset_info() {
  local reset_epoch
  reset_epoch="$(gh api rate_limit --jq '.resources.graphql.reset' 2>/dev/null)" || reset_epoch="" # workflow-shell-guard: allow SH001 - best-effort diagnostic lookup, failure just omits the reset timestamp
  case "${reset_epoch:-}" in
    ''|*[!0-9]*) return 0 ;;
  esac

  local reset_human=""
  if date -u -d "@$reset_epoch" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
    reset_human="$(date -u -d "@$reset_epoch" '+%Y-%m-%dT%H:%M:%SZ')"
  elif date -u -r "$reset_epoch" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
    reset_human="$(date -u -r "$reset_epoch" '+%Y-%m-%dT%H:%M:%SZ')"
  fi

  if [ -n "$reset_human" ]; then
    printf 'retry after %s UTC (rate limit resets then)' "$reset_human"
  fi
}

# ---------------------------------------------------------------------------
# Helper: build the RESOLVE_FAIL_REASON text for a classified probe failure.
# ---------------------------------------------------------------------------

build_probe_fail_reason() {
  local kind="$1" token="$2" err="$3"
  case "$kind" in
    rate_limited)
      local reset_info
      reset_info="$(gh_rate_limit_reset_info)"
      if [ -n "$reset_info" ]; then
        printf "GitHub API rate limit exceeded while resolving target '%s'; %s" "$token" "$reset_info"
      else
        printf "GitHub API rate limit exceeded while resolving target '%s'; retry after the rate limit resets" "$token"
      fi
      ;;
    auth_failed)
      printf "GitHub authentication failed while resolving target '%s'; run 'gh auth login' (or 'gh auth refresh') and retry" "$token"
      ;;
    network_error)
      printf "Network error contacting GitHub while resolving target '%s'; check connectivity and retry" "$token"
      ;;
    github_unavailable)
      printf "GitHub appears unavailable while resolving target '%s' (gh reported: %s); retry shortly" "$token" "$(printf '%s' "$err" | head -n1)"
      ;;
    *)
      printf "gh probe failed while resolving target '%s'" "$token"
      ;;
  esac
}

resolve_token() {
  local token="$1"
  local REPO_ROOT
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  RESOLVED_KIND="none"
  RESOLVE_FAIL_REASON=""
  RESOLVE_FAIL_KIND=""

  # Normalize: strip leading ./ so ./docs/specs/developments/... matches correctly
  token="${token#./}"

  # --- Development folder ---
  # Only check when we have a confirmed git repo root; never use CWD as a proxy
  # for the repo root since the script may be invoked from a subdirectory.
  if [ -n "$REPO_ROOT" ] && [ -d "$REPO_ROOT/$token" ] && [[ "$token" == docs/specs/developments/* ]]; then
    RESOLVED_KIND="dev_folder"
    return 0
  fi

  # --- PR token: #NNN or bare NNN when gh confirms it's a PR ---
  local pr_num="${token#\#}"
  if is_positive_int "$pr_num"; then
    # Try as a PR first; if that fails, try as an issue
    if have_cmd gh; then
      local pr_class issue_class

      gh_probe pr view "$pr_num" --json state --jq '.state'
      if [ "$PROBE_EXIT" -eq 0 ] && [ -n "$PROBE_OUT" ]; then
        RESOLVED_KIND="pr"
        return 0
      fi
      if [ "$PROBE_EXIT" -ne 0 ]; then
        pr_class="$(classify_gh_probe_error "$PROBE_ERR" "$PROBE_EXIT")"
        if [ "$pr_class" != "not_found" ]; then
          # gh call itself failed (rate limit, auth, network, outage) rather
          # than confirming the target is not a PR — do not fall through to
          # the issue probe and do not treat this as a genuine not-found.
          RESOLVE_FAIL_KIND="tracker_unavailable"
          RESOLVE_FAIL_REASON="$(build_probe_fail_reason "$pr_class" "$token" "$PROBE_ERR")"
          RESOLVED_KIND="none"
          return 1
        fi
      fi

      # Try as issue
      gh_probe issue view "$pr_num" --json state --jq '.state'
      if [ "$PROBE_EXIT" -eq 0 ] && [ -n "$PROBE_OUT" ]; then
        RESOLVED_KIND="issue"
        return 0
      fi
      if [ "$PROBE_EXIT" -ne 0 ]; then
        issue_class="$(classify_gh_probe_error "$PROBE_ERR" "$PROBE_EXIT")"
        if [ "$issue_class" != "not_found" ]; then
          RESOLVE_FAIL_KIND="tracker_unavailable"
          RESOLVE_FAIL_REASON="$(build_probe_fail_reason "$issue_class" "$token" "$PROBE_ERR")"
          RESOLVED_KIND="none"
          return 1
        fi
      fi

      # gh available, both probes succeeded, and token is neither an open PR
      # nor an open issue — a genuine not-found.
      RESOLVED_KIND="none"
      return 1
    else
      # gh is unavailable — cannot resolve a numeric token without it.
      # Emit a clear, actionable reason so the ambiguous stop-reason is useful.
      RESOLVE_FAIL_REASON="gh CLI is required to resolve numeric target '$token'; install gh and run 'gh auth login'"
      RESOLVED_KIND="none"
      return 1
    fi
  fi

  # --- Branch token: known workflow branch prefix patterns ---
  case "$token" in
    feature/*|fix/*|refactor/*|hotfix/*|spec/*|implementation-plan/*|plan/*)
      # Verify the branch exists locally or on the remote before accepting it.
      if git show-ref --verify --quiet "refs/remotes/origin/$token" 2>/dev/null || \
         git show-ref --verify --quiet "refs/heads/$token" 2>/dev/null; then
        RESOLVED_KIND="branch"
        return 0
      fi
      RESOLVE_FAIL_REASON="branch '$token' matches a workflow prefix pattern but does not exist locally or on origin"
      RESOLVED_KIND="none"
      return 1
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
REDIRECT_COMMAND=""

build_redirect_command_item() {
  local scope="$1"
  printf '/run-item %s' "$scope"
}

build_redirect_command_items() {
  # scope is a comma-separated list of resolved targets; convert to space-separated
  local scope="$1"
  local targets_space
  targets_space="$(printf '%s\n' "$scope" | tr ',' ' ')"
  printf '/run-items %s' "$targets_space"
}

build_redirect_command_epic() {
  local scope="$1"
  printf '/run-epic --epic %s' "$scope"
}

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
    MODE="$MODE_REDIRECT_EPIC"
    MODE_LABEL="$LABEL_REDIRECT_EPIC"
    RESOLVED_SCOPE="$epic_flag"
    REDIRECT_COMMAND="$(build_redirect_command_epic "$epic_flag")"
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
    # Unresolvable token → ambiguous, unless the failure was a gh probe
    # failure (rate limit, auth, network, outage) rather than a confirmed
    # not-found, in which case it is distinctly tracker_unavailable.
    if [ "${RESOLVE_FAIL_KIND:-}" = "tracker_unavailable" ]; then
      MODE="$MODE_TRACKER_UNAVAILABLE"
      MODE_LABEL="$LABEL_TRACKER_UNAVAILABLE"
    else
      MODE="$MODE_AMBIGUOUS"
      MODE_LABEL="$LABEL_AMBIGUOUS"
    fi
    if [ -n "${RESOLVE_FAIL_REASON:-}" ]; then
      STOP_REASON="$RESOLVE_FAIL_REASON"
    else
      STOP_REASON="Token '$token' could not be resolved to a known issue, branch, PR, or development folder"
    fi
  elif [ "$RESOLVED_KIND" = "issue" ]; then
    # Check if it's an epic-like issue
    issue_num="${token#\#}"
    set +e
    is_epic_issue "$issue_num"
    epic_check=$?
    set -e

    if [ "$epic_check" -eq 0 ]; then
      MODE="$MODE_REDIRECT_EPIC"
      MODE_LABEL="$LABEL_REDIRECT_EPIC"
      RESOLVED_SCOPE="$issue_num"
      REDIRECT_COMMAND="$(build_redirect_command_epic "$issue_num")"
    else
      MODE="$MODE_REDIRECT_ITEM"
      MODE_LABEL="$LABEL_REDIRECT_ITEM"
      RESOLVED_SCOPE="$token"
      REDIRECT_COMMAND="$(build_redirect_command_item "$token")"
    fi
  else
    # branch, pr, dev_folder → redirect_item
    MODE="$MODE_REDIRECT_ITEM"
    MODE_LABEL="$LABEL_REDIRECT_ITEM"
    RESOLVED_SCOPE="$token"
    REDIRECT_COMMAND="$(build_redirect_command_item "$token")"
  fi

# --------------- Case 4: two or more tokens --------------------------------
else
  # Resolve each token; any unresolvable → ambiguous
  all_resolved=1
  resolved_list=()
  first_unresolvable=""
  first_unresolvable_fail_kind=""

  for t in "${deduped_tokens[@]}"; do
    set +e
    resolve_token "$t"
    res_exit=$?
    set -e

    if [ "$res_exit" -ne 0 ]; then
      all_resolved=0
      first_unresolvable="$t"
      first_unresolvable_fail_kind="${RESOLVE_FAIL_KIND:-}"
      break
    fi
    resolved_list+=("$t")
  done

  if [ "$all_resolved" -eq 0 ]; then
    # Unresolvable token → ambiguous, unless the failure was a gh probe
    # failure (rate limit, auth, network, outage) rather than a confirmed
    # not-found, in which case it is distinctly tracker_unavailable.
    if [ "$first_unresolvable_fail_kind" = "tracker_unavailable" ]; then
      MODE="$MODE_TRACKER_UNAVAILABLE"
      MODE_LABEL="$LABEL_TRACKER_UNAVAILABLE"
    else
      MODE="$MODE_AMBIGUOUS"
      MODE_LABEL="$LABEL_AMBIGUOUS"
    fi
    if [ -n "${RESOLVE_FAIL_REASON:-}" ]; then
      STOP_REASON="$RESOLVE_FAIL_REASON"
    else
      STOP_REASON="Token '$first_unresolvable' in the list could not be resolved to a known issue, branch, PR, or development folder"
    fi
  else
    # Epic-like issues are not portfolio explicit-list targets; redirect or stop.
    epic_in_list=0
    epic_issue_num=""
    for t in "${resolved_list[@]}"; do
      set +e
      resolve_token "$t"
      set -e
      if [ "$RESOLVED_KIND" = "issue" ]; then
        num="${t#\#}"
        set +e
        is_epic_issue "$num"
        epic_check=$?
        set -e
        if [ "$epic_check" -eq 0 ]; then
          epic_in_list=1
          epic_issue_num="$num"
        fi
      fi
    done

    if [ "$epic_in_list" -eq 1 ]; then
      MODE="$MODE_AMBIGUOUS"
      MODE_LABEL="$LABEL_AMBIGUOUS"
      STOP_REASON="Epic-like issue #${epic_issue_num} cannot be advanced via /run-work; use /run-epic --epic ${epic_issue_num}"
    else
    MODE="$MODE_REDIRECT_ITEMS"
    MODE_LABEL="$LABEL_REDIRECT_ITEMS"
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
    REDIRECT_COMMAND="$(build_redirect_command_items "$scope_str")"
    fi
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
if [ -n "${REDIRECT_COMMAND:-}" ]; then
  echo "REDIRECT_COMMAND=$REDIRECT_COMMAND"
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

  redirect_json="null"
  if [ -n "${REDIRECT_COMMAND:-}" ]; then
    redirect_json="$(printf '%s\n' "$REDIRECT_COMMAND" | \
      python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().rstrip("\n")))')"
  fi

  # Build the full JSON record using python3 with --arg style injection to
  # avoid shell-expansion quoting issues inside the heredoc.
  python3 - \
    "$MODE" \
    "$MODE_LABEL" \
    "$raw_target_json" \
    "$scope_json" \
    "$stop_reason_json" \
    "$redirect_json" \
    "$GUARDRAILS_SECTION" \
    "$GUARDRAILS_MODE" \
    "$backlog_bool" \
    <<'PYJSON'
import json, sys
args = sys.argv[1:]
mode, mode_label, raw_target_json_str, scope_json_str, stop_reason_json_str, \
    redirect_json_str, guardrails_section, guardrails_mode, backlog_bool_str = args

record = {
    "mode": mode,
    "modeLabel": mode_label,
    "rawTarget": json.loads(raw_target_json_str),
    "resolvedScope": json.loads(scope_json_str),
    "heldBack": [],
    "outOfScope": [],
    "stopReason": json.loads(stop_reason_json_str),
    "redirectCommand": json.loads(redirect_json_str),
    "guardrails": {
        "section": guardrails_section,
        "mode": guardrails_mode,
        "backlogStart": backlog_bool_str == "true"
    }
}
print(json.dumps(record, indent=2))
PYJSON
fi

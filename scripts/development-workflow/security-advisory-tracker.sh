#!/usr/bin/env bash
# security-advisory-tracker.sh - BR7 cross-push reconciliation and
# <!-- security-sensitive-advisory-findings --> tracking-comment persistence
# for security-sensitive advisory findings.
#
# See docs/specs/developments/20260811131628_1432-security-advisory-human-decision/
# for the spec and implementation plan this script implements.
#
# Finding identifiers (`sec-<12-hex-char sha256 prefix of
# platform|commentIdOrUrl|matchedCategory>`) are computed by the caller
# (Protocol 93's reviewer-loop procedure) before invoking `reconcile`; this
# script treats `id` as an opaque, already-computed string on `--current`
# entries and never derives it itself.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=scripts/development-workflow/workflow-lib.sh
source "$SCRIPT_DIR/workflow-lib.sh"

MARKER="<!-- security-sensitive-advisory-findings -->"

error_exit() {
  echo "ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/development-workflow/security-advisory-tracker.sh reconcile \
    --prior <file|"none"> --current <file> --head-sha <sha> \
    [--decision-events <file|"none">] [--now <iso8601-timestamp>]
  ./scripts/development-workflow/security-advisory-tracker.sh render --input <file>
  ./scripts/development-workflow/security-advisory-tracker.sh apply --input <file> --pr <number>

reconcile: implements BR7's re-evaluation of tracked security-sensitive
advisory findings across pushes. Pure function (no gh calls); prints the
reconciled entries array as JSON to stdout and non-fatal WARN lines (e.g.
conflicting decision events) to stderr.

render: renders the <!-- security-sensitive-advisory-findings --> marker
comment body from a reconciled entries array. Pure function (no gh calls).

apply: upserts the marker comment via `gh api` (find-by-marker-then-PATCH-
or-POST). The only subcommand that mutates.
EOF
}

require_value() {
  local option="$1"
  if [ "$#" -lt 2 ] || [ -z "${2:-}" ] || [ "${2#--}" != "$2" ]; then
    echo "$option requires a value." >&2
    usage >&2
    exit 64
  fi
}

is_positive_int() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    0*) return 1 ;;
    *) return 0 ;;
  esac
}

load_json_arg() {
  # Loads either "none" (-> empty array) or a JSON file path.
  local value="$1" label="$2"
  if [ "$value" = "none" ]; then
    printf '[]\n'
    return 0
  fi
  if [ ! -f "$value" ]; then
    error_exit "$label file not found: $value"
  fi
  if [ ! -s "$value" ]; then
    error_exit "$label file is empty: $value"
  fi
  jq -c '.' "$value" 2>/dev/null || error_exit "$label file is not valid JSON: $value"
}

load_input_json() {
  local file="$1"
  if [ ! -f "$file" ]; then
    error_exit "input file not found: $file"
  fi
  if [ ! -s "$file" ]; then
    error_exit "input file is empty: $file"
  fi
  jq -c '.' "$file" 2>/dev/null || error_exit "input file is not valid JSON: $file"
}

gh_api_timeout_seconds() {
  local value="${WORKFLOW_GH_API_TIMEOUT_SECONDS:-30}"
  if ! [[ "$value" =~ ^[1-9][0-9]*$ ]]; then
    value=30
  fi
  printf '%s\n' "$value"
}

gh_api_bounded() {
  local timeout_seconds
  timeout_seconds="$(gh_api_timeout_seconds)"
  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_seconds" gh api "$@"
    return $?
  fi

  local output_file pid elapsed status process_group
  output_file="$(mktemp)" || return 1
  process_group=0
  if command -v setsid >/dev/null 2>&1; then
    setsid gh api "$@" >"$output_file" &
    process_group=1
  else
    gh api "$@" >"$output_file" &
  fi
  pid=$!
  elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$timeout_seconds" ]; then
      if [ "$process_group" -eq 1 ]; then
        kill -TERM "-$pid" 2>/dev/null || kill "$pid" 2>/dev/null || true
      else
        kill "$pid" 2>/dev/null || true
      fi
      sleep 1
      if kill -0 "$pid" 2>/dev/null; then
        if [ "$process_group" -eq 1 ]; then
          kill -KILL "-$pid" 2>/dev/null || kill -KILL "$pid" 2>/dev/null || true
        else
          kill -KILL "$pid" 2>/dev/null || true
        fi
      fi
      wait "$pid" 2>/dev/null || true
      rm -f "$output_file"
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  status=0
  wait "$pid" || status=$?
  cat "$output_file"
  rm -f "$output_file"
  if ! [[ "$status" =~ ^[0-9]+$ ]]; then
    status=1
  fi
  return "$status"
}

table_cell_filter='
  def cell:
    tostring
    | gsub("\\|"; "\\\\|")
    | gsub("\\r?\\n"; "<br>")
    | gsub("\\t"; " ");
'

# reconcile() implements BR7: matches prior entries to fresh findings by
# (matchedCategory, matchedFile), pairing multiple entries sharing a key in
# stable first-listed-to-first-listed order (same-push collision handling);
# resets a matched entry to pending with audit reason
# "superseded_by_new_commit" (clearing all resolution-provenance fields)
# when its recorded headSha differs from the current head, for every prior
# status including pending (AC12/AC13); drops an entry entirely when no
# fresh finding matches it this push, from any prior status; leaves a
# same-head matched entry byte-for-byte untouched except where
# --decision-events resolves it. Never emits a fifth "stale" status.
reconcile() {
  local prior_json="$1" current_json="$2" head_sha="$3" decision_events_json="$4" now="$5"
  local result

  result="$(jq -c -n \
    --argjson prior "$prior_json" \
    --argjson current "$current_json" \
    --argjson decisionEvents "$decision_events_json" \
    --arg headSha "$head_sha" \
    --arg now "$now" '
    # Accepts both "category" (the canonical resolved-entry field name used
    # by --prior/reconcile output) and "matchedCategory" (the field name
    # security-advisory-classifier.sh classify actually emits) on --current
    # entries, so a caller can pass classify output straight through without
    # a separate rename step -- passing matchedCategory unchanged would
    # otherwise silently key every entry on an empty category and break
    # BR7 cross-push matching.
    def entry_category($e): ($e.category // $e.matchedCategory // "");
    def keyof($e): (entry_category($e) | tostring) + "\u0000" + (($e.matchedFile // "") | tostring);

    # Assigns a stable, order-preserving sequence number within each
    # (category, matchedFile) group so multiple findings sharing a key in
    # one array are paired first-listed-to-first-listed, never collapsed.
    def with_seq($arr):
      (reduce $arr[] as $e
        ({counts: {}, out: []};
          (.counts[keyof($e)] // 0) as $n |
          {
            counts: (.counts + {($e | keyof(.)): ($n + 1)}),
            out: (.out + [$e + {_seq: $n}])
          }
        )).out;

    def composite_key($e): keyof($e) + "\u0000" + ($e._seq | tostring);

    def to_map($seqArr):
      reduce $seqArr[] as $e ({}; . + {(composite_key($e)): $e});

    with_seq($prior) as $priorSeq |
    with_seq($current) as $currentSeq |
    to_map($priorSeq) as $priorMap |
    to_map($currentSeq) as $currentMap |
    (($priorSeq | map(composite_key(.))) + ($currentSeq | map(composite_key(.))) | unique) as $allKeys |

    # --- decision-events: group by findingId; fail closed on duplicates ---
    (reduce $decisionEvents[] as $ev
      ({}; . + {($ev.findingId | tostring): ((.[$ev.findingId | tostring] // []) + [$ev])})
    ) as $eventsByFinding |
    ($eventsByFinding | to_entries | map(select((.value | length) > 1))) as $conflictingGroups |
    ($eventsByFinding | with_entries(select((.value | length) == 1)) | map_values(.[0])) as $singleEventByFinding |
    ($conflictingGroups | map({
      findingId: .key,
      events: (.value | map({sourceEventId: (.sourceEventId // ""), sourceEventType: (.sourceEventType // "")}))
    })) as $conflictWarningsRaw |

    $allKeys | map(
      ($priorMap[.]) as $p |
      ($currentMap[.]) as $c |
      if ($p != null and $c != null) then
        if ($p.headSha == $headSha) then
          ($p | del(._seq))
        else
          {
            id: $c.id,
            category: entry_category($p),
            matchedFile: $p.matchedFile,
            status: "pending",
            headSha: $headSha,
            firstTrackedAt: $p.firstTrackedAt,
            auditReason: "superseded_by_new_commit"
          }
        end
      elif ($p != null and $c == null) then
        empty
      else
        {
          id: $c.id,
          category: entry_category($c),
          matchedFile: $c.matchedFile,
          status: "pending",
          headSha: $headSha,
          firstTrackedAt: $now
        }
      end
    ) as $reconciled |

    # Apply verified decision events to entries that are currently pending
    # after the head-sha reconciliation step above, using only
    # non-conflicting (singly-occurring findingId) events.
    ($reconciled | map(
      . as $entry |
      if ($entry.status == "pending") and ($singleEventByFinding[$entry.id | tostring] != null) then
        ($singleEventByFinding[$entry.id | tostring]) as $ev |
        ($entry + {
          status: $ev.decision,
          decider: $ev.decider,
          decidedAt: $ev.decidedAt,
          rationale: $ev.rationale
        })
      else
        $entry
      end
    )) as $withDecisions |

    {
      entries: $withDecisions,
      warnings: (
        $conflictWarningsRaw | map(
          "conflicting decision events for finding " + .findingId + ": " +
          ((.events | map("sourceEventId=" + .sourceEventId + " sourceEventType=" + .sourceEventType)) | join(", ")) +
          " (entry left pending; ambiguity must be resolved by a single unambiguous human decision comment)"
        )
      )
    }
  ' 2>/dev/null)" || error_exit "failed to reconcile security advisory findings (jq parse error)"

  if [ -z "$result" ]; then
    error_exit "failed to reconcile security advisory findings (empty result)"
  fi

  printf '%s\n' "$result" | jq -r '.warnings[]? | "WARN: " + .' >&2
  printf '%s\n' "$result" | jq -c '.entries'
}

render() {
  local json="$1"

  {
    printf '%s\n' "$MARKER"
    printf '## Security-Sensitive Advisory Findings\n\n'
    if [ "$(printf '%s\n' "$json" | jq 'length')" -eq 0 ]; then
      printf 'None currently tracked.\n'
    else
      printf '| ID | Category | File | Status | Decider | Decided At | Rationale | Fix Commit |\n'
      printf '| --- | --- | --- | --- | --- | --- | --- | --- |\n'
      printf '%s\n' "$json" | jq -r "$table_cell_filter"'
        .[] |
        "| " + ((.id // "") | cell) +
        " | " + ((.category // "") | cell) +
        " | " + ((.matchedFile // "") | cell) +
        " | " + ((.status // "") | cell) +
        " | " + ((.decider // "") | cell) +
        " | " + ((.decidedAt // "") | cell) +
        " | " + ((.rationale // "") | cell) +
        " | " + ((.fixCommit // "") | cell) + " |"
      '
    fi
  }
}

find_marker_comment_id() {
  local target="$1"
  local repo comments

  repo="$(repo_slug)"
  if ! comments="$(gh_api_bounded --paginate --slurp "repos/${repo}/issues/${target}/comments?per_page=100" 2>/dev/null)"; then
    error_exit "failed to read comments for issue/PR #$target"
  fi
  printf '%s\n' "$comments" |
    jq -r --arg marker "$MARKER" '[.[][]? | select((.body // "") | contains($marker))][0].id // empty'
}

patch_marker_comment() {
  local repo="$1"
  local comment_id="$2"
  local target="$3"
  local payload="$4"
  local output status

  status=0
  output="$(gh_api_bounded -X PATCH "repos/${repo}/issues/comments/${comment_id}" --input "$payload" 2>&1 >/dev/null)" || status=$?
  if [ "$status" -eq 124 ]; then
    error_exit "timed out updating marker comment ${comment_id} for issue/PR #$target"
  fi
  if [ "$status" -ne 0 ]; then
    error_exit "failed to update marker comment ${comment_id} for issue/PR #$target: $output"
  fi
}

post_marker_comment() {
  local repo="$1"
  local target="$2"
  local payload="$3"
  local output status

  status=0
  output="$(gh_api_bounded -X POST "repos/${repo}/issues/${target}/comments" --input "$payload" 2>&1 >/dev/null)" || status=$?
  if [ "$status" -eq 124 ]; then
    error_exit "timed out creating marker comment for issue/PR #$target"
  fi
  if [ "$status" -ne 0 ]; then
    error_exit "failed to create marker comment for issue/PR #$target: $output"
  fi
}

apply_marker_comment() {
  local target="$1"
  local body="$2"
  local repo comment_id payload

  require_gh
  repo="$(repo_slug)"
  comment_id="$(find_marker_comment_id "$target")"
  payload="$(mktemp)" || error_exit "failed to create comment payload"
  if [ -n "$comment_id" ]; then
    if ! jq -n --arg body "$body" '{body: $body}' >"$payload"; then
      rm -f "$payload"
      error_exit "failed to write marker comment payload"
    fi
    patch_marker_comment "$repo" "$comment_id" "$target" "$payload"
    rm -f "$payload"
    printf 'UPDATED_COMMENT_ID=%s\n' "$comment_id"
  else
    rm -f "$payload"
    comment_id="$(find_marker_comment_id "$target")"
    payload="$(mktemp)" || error_exit "failed to create comment payload"
    if ! jq -n --arg body "$body" '{body: $body}' >"$payload"; then
      rm -f "$payload"
      error_exit "failed to write marker comment payload"
    fi
    if [ -n "$comment_id" ]; then
      patch_marker_comment "$repo" "$comment_id" "$target" "$payload"
      rm -f "$payload"
      printf 'UPDATED_COMMENT_ID=%s\n' "$comment_id"
      return 0
    fi
    post_marker_comment "$repo" "$target" "$payload"
    rm -f "$payload"
    printf 'CREATED_COMMENT=1\n'
  fi
}

command="${1:-}"
if [ "$#" -gt 0 ]; then
  shift
fi

prior_arg=""
current_arg=""
decision_events_arg="none"
head_sha_arg=""
now_arg=""
input_file=""
pr_number=""

case "$command" in
  reconcile|render|apply)
    ;;
  -h|--help|"")
    usage
    exit 0
    ;;
  *)
    echo "ERROR: unknown subcommand: $command" >&2
    usage >&2
    exit 64
    ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --prior)
      require_value "$@"
      prior_arg="$2"
      shift 2
      ;;
    --current)
      require_value "$@"
      current_arg="$2"
      shift 2
      ;;
    --head-sha)
      require_value "$@"
      head_sha_arg="$2"
      shift 2
      ;;
    --decision-events)
      require_value "$@"
      decision_events_arg="$2"
      shift 2
      ;;
    --now)
      require_value "$@"
      now_arg="$2"
      shift 2
      ;;
    --input)
      require_value "$@"
      input_file="$2"
      shift 2
      ;;
    --pr)
      require_value "$@"
      pr_number="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

case "$command" in
  reconcile)
    [ -n "$prior_arg" ] || error_exit "--prior is required"
    [ -n "$current_arg" ] || error_exit "--current is required"
    [ -n "$head_sha_arg" ] || error_exit "--head-sha is required"
    prior_json="$(load_json_arg "$prior_arg" "--prior")"
    current_json="$(load_json_arg "$current_arg" "--current")"
    decision_events_json="$(load_json_arg "$decision_events_arg" "--decision-events")"
    if [ -z "$now_arg" ]; then
      now_arg="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fi
    reconcile "$prior_json" "$current_json" "$head_sha_arg" "$decision_events_json" "$now_arg"
    ;;
  render)
    [ -n "$input_file" ] || error_exit "--input is required"
    input_json="$(load_input_json "$input_file")"
    render "$input_json"
    ;;
  apply)
    [ -n "$input_file" ] || error_exit "--input is required"
    if [ -z "$pr_number" ] || ! is_positive_int "$pr_number"; then
      error_exit "--pr must be a positive integer"
    fi
    input_json="$(load_input_json "$input_file")"
    body="$(render "$input_json")" || error_exit "failed to render security advisory findings (see error above)"
    apply_marker_comment "$pr_number" "$body"
    ;;
esac

#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: actions-cost-audit.sh [--limit <count>] [--repo <owner/repo>] [--since <iso-date>] [--format markdown]

Summarize recent GitHub Actions workflow run volume and wall time by workflow.

Options:
  --limit <count>      Number of recent runs to inspect. Default: 100.
  --repo <owner/repo>  Repository to inspect. Defaults to gh's current repository.
  --since <iso-date>   Include runs created at or after this ISO-8601 UTC timestamp.
  --format markdown    Output format. Only markdown is currently supported.
  -h, --help           Show this help.
USAGE
}

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

LIMIT=100
REPO=""
SINCE=""
FORMAT="markdown"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --limit)
      [ "$#" -ge 2 ] || fail "--limit requires a value"
      LIMIT="$2"
      shift 2
      ;;
    --repo)
      [ "$#" -ge 2 ] || fail "--repo requires a value"
      REPO="$2"
      shift 2
      ;;
    --since)
      [ "$#" -ge 2 ] || fail "--since requires a value"
      SINCE="$2"
      shift 2
      ;;
    --format)
      [ "$#" -ge 2 ] || fail "--format requires a value"
      FORMAT="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

case "$LIMIT" in
  ''|*[!0-9]*)
    fail "--limit must be a positive integer"
    ;;
esac
[ "$LIMIT" -gt 0 ] || fail "--limit must be greater than 0"

[ "$FORMAT" = "markdown" ] || fail "unsupported --format '$FORMAT'; only markdown is supported"

command -v gh >/dev/null 2>&1 || fail "gh CLI is required"
command -v jq >/dev/null 2>&1 || fail "jq is required"

if [ -n "$SINCE" ]; then
  jq -n --arg since "$SINCE" '$since | fromdateiso8601' >/dev/null \
    || fail "--since must be an ISO-8601 UTC timestamp, for example 2026-07-01T00:00:00Z"
fi

FIELDS="databaseId,workflowName,workflowDatabaseId,status,conclusion,createdAt,startedAt,updatedAt,event,headBranch,url"
GH_ARGS=(run list --limit "$LIMIT" --json "$FIELDS")
if [ -n "$REPO" ]; then
  GH_ARGS+=(--repo "$REPO")
fi

if ! RUNS_JSON=$(gh "${GH_ARGS[@]}" 2>&1); then
  printf 'ERROR: gh run list failed. Confirm gh authentication and repository Actions read visibility.\n' >&2
  printf '%s\n' "$RUNS_JSON" >&2
  exit 1
fi

if ! printf '%s\n' "$RUNS_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
  fail "gh run list returned unexpected non-array JSON"
fi

jq -r --arg repo "$REPO" --arg since "$SINCE" --argjson limit "$LIMIT" '
  def parse_time:
    if . == null or . == "" then null
    else try fromdateiso8601 catch null
    end;

  def minutes($seconds):
    if $seconds == null then "n/a"
    else (((($seconds / 60) * 10 | round) / 10) | tostring) + "m"
    end;

  def safe_cell:
    tostring | gsub("\\|"; "\\|") | gsub("\n"; " ");

  def run_key:
    if (.workflowName // "") != "" then .workflowName
    elif (.workflowDatabaseId // "") != "" then "workflow:" + (.workflowDatabaseId | tostring)
    else "unknown-workflow"
    end;

  def run_url:
    if (.url // "") != "" then .url
    elif (.databaseId // "") != "" then "#" + (.databaseId | tostring)
    else "unknown"
    end;

  def event_summary:
    map(.event // "unknown")
    | group_by(.)
    | map({event: .[0], count: length})
    | sort_by(-.count, .event)
    | .[0:3]
    | map(.event + " (" + (.count | tostring) + ")")
    | join(", ");

  def run_id_summary:
    map(run_url)
    | .[0:5]
    | join(", ");

  def normalize:
    . as $run
    | ($run.createdAt | parse_time) as $created
    | ($run.startedAt | parse_time) as $started
    | ($run.updatedAt | parse_time) as $updated
    | (($started // $created) as $start
      | if ($run.status == "completed" and $start != null and $updated != null and $updated >= $start)
        then ($updated - $start)
        else null
        end) as $duration
    | $run + {
        workflowKey: ($run | run_key),
        createdEpoch: $created,
        durationSeconds: $duration,
        durationIncomplete: ($duration == null)
      };

  def recommendation_outcomes:
    "## Recommendation outcomes\n\n" +
    "| Outcome | Use when |\n" +
    "| --- | --- |\n" +
    "| keep | The workflow is high-signal: CI, reviewer gate, release gate, real regression, or real deploy value. |\n" +
    "| narrow | The workflow is valuable but runs on more events, branches, or paths than necessary. |\n" +
    "| make opt-in | The workflow is a placeholder or occasional diagnostic that should not run automatically downstream. |\n" +
    "| replace | The workflow is useful but should move to a cheaper or more targeted mechanism. |\n" +
    "| disable | The workflow no longer provides enough value to justify even low-cost automatic runs. |\n" +
    "| investigate | More data is needed before changing triggers or defaults. |\n";

  def cost_framing:
    "## Public/private cost-risk framing\n\n" +
    "- Public template repositories using standard GitHub-hosted runners are generally zero-billable for Actions minutes.\n" +
    "- Private downstream repositories can consume included or paid runner minutes for the same inherited workflow defaults.\n" +
    "- Larger runners, self-hosted runners, storage, and account-specific plan terms may differ; use billing dashboards for exact cost.\n" +
    "- This audit reports workflow-run wall time, not exact billable minutes or dollar cost.\n";

  def scope_line:
    "Scope: " + (if $repo == "" then "current repository" else $repo end) +
    ", recent run limit " + ($limit | tostring) +
    (if $since == "" then "" else ", since " + $since end) + ".\n\n";

  def render_empty:
    "# GitHub Actions Cost Audit\n\n" +
    scope_line +
    "No workflow run data was available for the selected scope. This can mean the repository has no matching runs, the inspected limit is too small, or the current account lacks workflow-run visibility.\n\n" +
    cost_framing + "\n" +
    recommendation_outcomes;

  def render_report($runs):
    ($runs | length) as $filtered_count
    | ($runs | map(select(.durationIncomplete)) | length) as $incomplete_count
    | ($runs
      | group_by(.workflowKey)
      | map(
          . as $items
          | ($items | map(.durationSeconds // 0) | add) as $total
          | ($items | map(select(.durationSeconds != null)) | length) as $duration_count
          | {
              workflow: $items[0].workflowKey,
              runs: ($items | length),
              completed: ($items | map(select(.status == "completed")) | length),
              incomplete: ($items | map(select(.durationIncomplete)) | length),
              totalSeconds: (if $duration_count > 0 then $total else null end),
              sortSeconds: $total,
              averageSeconds: (if $duration_count > 0 then ($total / $duration_count) else null end),
              events: ($items | event_summary),
              recentRuns: ($items | run_id_summary)
            }
        )
      | sort_by(-.sortSeconds, -.runs, .workflow)) as $summary
    | "# GitHub Actions Cost Audit\n\n" +
      scope_line +
      "Runs included: " + ($filtered_count | tostring) + ". Incomplete duration records: " + ($incomplete_count | tostring) + ".\n\n" +
      "## Workflow summary\n\n" +
      "| Workflow | Runs | Completed | Incomplete duration | Total wall time | Avg wall time | Dominant events | Recent runs |\n" +
      "| --- | ---: | ---: | ---: | ---: | ---: | --- | --- |\n" +
      ($summary
       | map("| " + (.workflow | safe_cell) +
             " | " + (.runs | tostring) +
             " | " + (.completed | tostring) +
             " | " + (.incomplete | tostring) +
             " | " + minutes(.totalSeconds) +
             " | " + minutes(.averageSeconds) +
             " | " + (.events | safe_cell) +
             " | " + (.recentRuns | safe_cell) + " |")
       | join("\n")) +
      "\n\n## Data limitations\n\n" +
      "- Runs without complete start/end timestamps are counted but excluded from wall-time totals.\n" +
      "- The inspected run limit can hide older high-volume workflows; increase `--limit` or use `--since` for a wider review.\n" +
      "- GitHub workflow-run visibility is repository-permission scoped. Billing-admin data is intentionally not required.\n\n" +
      cost_framing + "\n" +
      "## Recommendation worksheet\n\n" +
      "| Workflow | Suggested outcome | Rationale |\n" +
      "| --- | --- | --- |\n" +
      ($summary
       | map("| " + (.workflow | safe_cell) + " | investigate | Review volume, wall time, trigger scope, and quality/release value before changing defaults. |")
       | join("\n")) +
      "\n\n" +
      recommendation_outcomes;

  map(normalize)
  | if $since == "" then .
    else map(select(.createdEpoch != null and .createdEpoch >= ($since | fromdateiso8601)))
    end
  | sort_by(.createdEpoch // 0)
  | reverse
  | if length == 0 then render_empty else render_report(.) end
' <<<"$RUNS_JSON"

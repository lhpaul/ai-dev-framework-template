#!/usr/bin/env bash
# Synthetic durable retry/dispatch fixture shared by cycle and adapter tests.
# Globals are read/written by the sourced production reservation helper.
# shellcheck disable=SC2034,SC2154
_retry2061_exercise() (
  local axis="$1" tmp dispatches=0 i reason="" body counts
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  loop_head_sha=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  retry_local_review_head="$loop_head_sha"
  pr_number=2061
  current_run_id=run-A
  local MOCK_RETRY_WRITE_FAIL=0
  [ "$axis" != write_failure ] || MOCK_RETRY_WRITE_FAIL=1
  max_cycles=3
  max_total_cycles=99
  [ "$axis" != lifetime ] || { max_cycles=99; max_total_cycles=3; }
  reviewer_loop_repo_configured_platforms() { printf 'local-ai-reviewer\n'; }
  run_platform_review() { printf 'dispatch\n' >>"$tmp/dispatches"; }
  repo_slug() { printf 'synthetic/repo\n'; }
  reviewer_loop_history_current_head_sha() { printf '%s\n' "$loop_head_sha"; }
  reviewer_loop_history_recorded_at() { printf '2026-01-01T00:00:00Z\n'; }
  # Historical duplicates count once, exactly as before this change.
  body="$(jq -cn --arg head "$loop_head_sha" '{schema:"reviewer_loop_history.v1",entries:
    [range(0;2) | {head_sha:$head,classification_head:$head,run_id:"run-A",result:"needs_fixes",local_second_pass_failed_head:$head}]}')"
  if [ "$axis" = run_after_cap ]; then
    body="$(printf '%s' "$body" | jq --arg head "$loop_head_sha" '.entries += [{head_sha:$head,classification_head:$head,run_id:"run-A",result:"escalate",reason:"max_cycles_exceeded",local_second_pass_failed_head:$head}]')"
    current_run_id=run-B
  fi
  printf '### Automated Reviewer Loop Summary\n<!-- reviewer-loop-history:v1 -->\n```json\n%s\n```\n*Posted automatically by `pr-review-loop.sh`.*\n' "$body" >"$tmp/body"
  jq -n --rawfile body "$tmp/body" '{id:42,body:$body,created_at:"2026-01-01"}' >"$tmp/comment"
  gh() {
    if [ "$2" = --method ]; then
      [ "${MOCK_RETRY_WRITE_FAIL:-0}" -eq 0 ] || return 1
      cp "$6" "$tmp/written"
      jq '. + {id:42,created_at:"2026-01-01"}' "$tmp/written" >"$tmp/comment"
      [ "$axis" != uncertain_write ] || return 1
    elif [ "$2" = repos/synthetic/repo/issues/2061/comments ]; then
      jq -s '.' "$tmp/comment"
    elif [ "$2" = repos/synthetic/repo/issues/comments/42 ]; then
      if [ "$axis" = readback_mismatch ]; then printf '{"body":"not the saved reservation"}\n'; else cat "$tmp/comment"; fi
    else return 1; fi
  }
  for i in 1 2 3; do
    [ "$axis" != lifetime ] || current_run_id="run-$i"
    reviewer_loop_prepare_local_retry 2061
    if [ "$local_retry_preparation_failed" -eq 0 ]; then
      run_platform_review local-ai-reviewer 2061 feature/2061-test 1 1
      dispatches=$((dispatches + 1))
      [ "$axis" != reserved_only ] || continue
      # Completing a reservation with the same ID must not spend twice.
      body="$(jq -r .body "$tmp/comment")"
      reviewer_loop_history_append_to_summary $'### Automated Reviewer Loop Summary\n*Posted automatically by `pr-review-loop.sh`.*' "$body" needs_fixes proof_pending local-ai-reviewer 1 0 >"$tmp/body"
      jq -n --rawfile body "$tmp/body" '{id:42,body:$body,created_at:"2026-01-01"}' >"$tmp/comment"
    else reason="$local_review_retry_failure_reason"; break; fi
  done
  body="$(jq -r .body "$tmp/comment")"
  counts="$(reviewer_loop_history_entries_count "$body" "$current_run_id")"
  printf '%s|%s|%s\n' "$dispatches" "$reason" "$counts"
)

#!/usr/bin/env bash
# Synthetic durable retry/dispatch fixture shared by cycle and adapter tests.
# Globals are read/written by the sourced production reservation helper.
# shellcheck disable=SC2034,SC2154
_retry2061_exercise() (
  local axis="$1" retry_fixture_dir dispatches=0 i reason="" body counts
  retry_fixture_dir="$(mktemp -d)"
  trap 'rm -rf "$retry_fixture_dir"' EXIT
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
  run_platform_review() { printf 'dispatch\n' >>"$retry_fixture_dir/dispatches"; }
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
  printf '### Automated Reviewer Loop Summary\n<!-- reviewer-loop-history:v1 -->\n```json\n%s\n```\n*Posted automatically by `pr-review-loop.sh`.*\n' "$body" >"$retry_fixture_dir/body"
  jq -n --rawfile body "$retry_fixture_dir/body" '{id:42,body:$body,created_at:"2026-01-01"}' >"$retry_fixture_dir/comment-42.json"
  printf '42' >"$retry_fixture_dir/next-id"
  if [ "$axis" = forked ]; then
    jq --arg head "$loop_head_sha" '.entries = [.entries[0] + {
      local_review_retry_attempt:{id:"00000000-0000-4000-8000-000000009001",head_sha:$head,run_id:"run-A"}}]' \
      < <(printf '%s' "$body") >"$retry_fixture_dir/fork-payload"
    printf '### Automated Reviewer Loop Summary\n%s\n```json\n%s\n```\n%s\n' \
      "$REVIEWER_LOOP_HISTORY_MARKER" "$(cat "$retry_fixture_dir/fork-payload")" \
      '*Posted automatically by `pr-review-loop.sh`.*' >"$retry_fixture_dir/fork-body"
    jq -n --rawfile body "$retry_fixture_dir/fork-body" '{id:43,body:$body,created_at:"2026-01-02"}' >"$retry_fixture_dir/comment-43.json"
    printf '43' >"$retry_fixture_dir/next-id"
  fi
  gh() {
    if [ "$2" = --method ]; then
      [ "$3" = POST ] || return 99
      [ "${MOCK_RETRY_WRITE_FAIL:-0}" -eq 0 ] || return 1
      local next
      next=$(( $(cat "$retry_fixture_dir/next-id") + 1 ))
      printf '%s' "$next" >"$retry_fixture_dir/next-id"
      jq --argjson id "$next" '. + {id:$id,created_at:"2026-01-02"}' "$6" >"$retry_fixture_dir/comment-$next.json"
      [ "$axis" != uncertain_write ] || return 1
      cat "$retry_fixture_dir/comment-$next.json"
    elif [ "$2" = repos/synthetic/repo/issues/2061/comments ]; then
      jq -s '.' "$retry_fixture_dir"/comment-*.json
    elif [[ "$2" == repos/synthetic/repo/issues/comments/* ]]; then
      if [ "$axis" = readback_mismatch ]; then printf '{"body":"not the saved reservation"}\n'; else cat "$retry_fixture_dir/comment-${2##*/}.json"; fi
    else return 1; fi
  }
  fixture_latest_body() {
    jq -s '.' "$retry_fixture_dir"/comment-*.json | reviewer_loop_history_select_latest_summary_record | jq -r .body
  }
  for i in 1 2 3; do
    [ "$axis" != lifetime ] || current_run_id="run-$i"
    reviewer_loop_prepare_local_retry 2061
    if [ "$local_retry_preparation_failed" -eq 0 ]; then
      run_platform_review local-ai-reviewer 2061 feature/2061-test 1 1
      dispatches=$((dispatches + 1))
      [ "$axis" != reserved_only ] || continue
      # Completing a reservation with the same ID must not spend twice.
      body="$(fixture_latest_body)"
      reviewer_loop_history_append_to_summary $'### Automated Reviewer Loop Summary\n*Posted automatically by `pr-review-loop.sh`.*' "$body" needs_fixes proof_pending local-ai-reviewer 1 0 >"$retry_fixture_dir/body"
      reviewer_loop_history_publish synthetic/repo 2061 "$retry_fixture_dir/body"
    else reason="$local_review_retry_failure_reason"; break; fi
  done
  body="$(fixture_latest_body)"
  counts="$(reviewer_loop_history_entries_count "$body" "$current_run_id")"
  printf '%s|%s|%s\n' "$dispatches" "$reason" "$counts"
)

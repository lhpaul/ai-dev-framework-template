# shellcheck shell=bash
# Exact synthetic producer inputs captured at the original matrix boundary.
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_BASE_CONFIG='review:
  on_ready:
    github:
      - pr-agent'
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_BASE_CONFIG_EXIT=0
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_BASE_SHA=dddd444000000000000
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_CHECK_RUNS='{"check_runs":[]}'
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_CHECK_RUNS_EXIT=0
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_COMMENTS='[]'
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_DROP_LABEL=0
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_FINAL_REVALIDATE_HEAD=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_GH_USER=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_GREPTILE_REACTION='[{"user":{"login":"greptile-apps[bot]"},"content":"+1"}]'
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_HEAD_COMMIT_JSON=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_HEAD_CONFIG='review:
  on_ready:
    github:
      - pr-agent'
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_HEAD_CONFIG_EXIT=0
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_LABELS='{"labels":[]}'
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_LATE_CI_PR_JSON=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_OCC_TIMELINE=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_OCC_TIMELINE_EXIT=0
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_OCC_TIMELINE_PAGE2=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_OWNERSHIP_PR_JSON=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_PERMS=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_POST_APPLY_HEAD=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_POST_VIEW_EXIT=0
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_PR_JSON='{"headRefOid":"aaaa111000000000000","headRefName":"fix/1408-demo","baseRefOid":"dddd444000000000000","labels":[],"statusCheckRollup":[]}'
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_PR_JSON_EXIT=0
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_REMOVE_LABEL_EXIT=0
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_RERUN_COMMENTS=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_REVALIDATE_CHECK_RUNS=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_REVALIDATE_CHECK_RUNS_EXIT=0
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_REVALIDATE_COMMENTS=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_REVALIDATE_HEAD=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_REVALIDATE_PR_JSON=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_REVIEWS='[]'
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_REVIEW_THREADS=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_REVIEW_THREADS_EXIT=0
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_RUN_LOG=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_RUN_LOG_EXIT=0
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
MOCK_WORKFLOW_RUNS=''
# shellcheck disable=SC2034 # Assigned for functions in the sourced readiness fixture.
PR_AGENT_BOT_LOGIN='github-actions[bot]'
_codex_config="$TMP_ROOT/codex-github-config"
mkdir -p "$_codex_config"
printf 'review:\n  on_ready:\n    github:\n      - codex-github\n' >"$_codex_config/workflow.yaml"

#!/usr/bin/env bash
# covers: .github/workflows/deploy.yml .github/workflows/e2e-regression.yml
# covers: docs/workflow/development-workflow/integrations/*.md
# covers: docs/workflow/development-workflow/protocols/*.md

set -euo pipefail

ROOT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
DEPLOY_WORKFLOW="$ROOT_DIR/.github/workflows/deploy.yml"
REGRESSION_WORKFLOW="$ROOT_DIR/.github/workflows/e2e-regression.yml"
DEPLOY_DOC="$ROOT_DIR/docs/workflow/development-workflow/integrations/ci-cd-deployment.md"
REGRESSION_DOC="$ROOT_DIR/docs/workflow/development-workflow/integrations/e2e-regression.md"
CI_DOC="$ROOT_DIR/docs/workflow/development-workflow/integrations/ci-enforcement.md"
PROTOCOL_05="$ROOT_DIR/docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md"
PROTOCOL_90="$ROOT_DIR/docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md"
PROTOCOL_91="$ROOT_DIR/docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md"
PROTOCOL_92="$ROOT_DIR/docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  grep -Eq "$pattern" "$file" || fail "$message"
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local message="$3"

  if grep -Eq "$pattern" "$file"; then
    fail "$message"
  fi
}

assert_contains "$DEPLOY_WORKFLOW" '^[[:space:]]*workflow_dispatch:' \
  "deploy placeholder must remain manually runnable via workflow_dispatch"
assert_contains "$DEPLOY_WORKFLOW" 'confirm_placeholder:' \
  "deploy placeholder must expose an explicit confirmation input"
assert_contains "$DEPLOY_WORKFLOW" 'inputs\.confirm_placeholder == true' \
  "deploy placeholder jobs must require explicit confirmation"
assert_not_contains "$DEPLOY_WORKFLOW" '^[[:space:]]*push:' \
  "deploy placeholder must not declare a default push trigger"
assert_not_contains "$DEPLOY_WORKFLOW" "github\\.event_name == 'push'" \
  "deploy placeholder jobs must not contain push-event activation clauses"

assert_contains "$REGRESSION_WORKFLOW" "ready-for-regression" \
  "regression placeholder must preserve ready-for-regression label semantics"
assert_contains "$REGRESSION_WORKFLOW" '^[[:space:]]*workflow_dispatch:' \
  "regression placeholder must support explicit dispatch from pr-policy"
assert_contains "$REGRESSION_WORKFLOW" 'pr_number:' \
  "regression placeholder dispatch must accept the PR number"
assert_contains "$REGRESSION_WORKFLOW" 'head_sha:' \
  "regression placeholder dispatch must accept the PR head SHA"
assert_contains "$REGRESSION_WORKFLOW" "github\\.event_name == 'workflow_dispatch'" \
  "regression placeholder must run when explicitly dispatched"
assert_contains "$REGRESSION_WORKFLOW" 'inputs\.head_sha' \
  "regression placeholder checkout must use the dispatched PR head SHA"
assert_contains "$REGRESSION_WORKFLOW" "ENABLE_TEMPLATE_PLACEHOLDER_REGRESSION" \
  "regression placeholder must document the explicit opt-in variable in workflow logic"
assert_contains "$REGRESSION_WORKFLOW" "vars\\.ENABLE_TEMPLATE_PLACEHOLDER_REGRESSION == 'true'" \
  "regression placeholder job must require the opt-in variable to be true"
assert_contains "$REGRESSION_WORKFLOW" 'npx playwright install --with-deps chromium' \
  "regression placeholder still needs the browser install step for explicitly enabled placeholders"

regression_if_line="$(grep -n "ENABLE_TEMPLATE_PLACEHOLDER_REGRESSION" "$REGRESSION_WORKFLOW" | head -1 | cut -d: -f1)"
install_line="$(grep -n "npx playwright install" "$REGRESSION_WORKFLOW" | head -1 | cut -d: -f1)"
[ -n "$regression_if_line" ] || fail "could not locate regression opt-in guard"
[ -n "$install_line" ] || fail "could not locate Playwright install step"
if [ "$regression_if_line" -ge "$install_line" ]; then
  fail "regression opt-in guard must appear before expensive browser install step"
fi

assert_contains "$DEPLOY_DOC" 'inactive by default|does not run on push by default' \
  "deployment docs must explain the inactive default"
assert_contains "$DEPLOY_DOC" 'confirm_placeholder' \
  "deployment docs must name the placeholder confirmation input"
assert_contains "$REGRESSION_DOC" 'ENABLE_TEMPLATE_PLACEHOLDER_REGRESSION' \
  "regression docs must name the opt-in variable"
assert_contains "$REGRESSION_DOC" 'inactive by default|disabled by default' \
  "regression docs must explain the inactive default"
assert_contains "$CI_DOC" 'inactive placeholder|explicitly enabled placeholder' \
  "CI enforcement docs must distinguish readiness labels from placeholder activation"
assert_contains "$PROTOCOL_05" 'configured real regression|explicitly enabled placeholder' \
  "release protocol must preserve label-gated guidance for configured regression"
assert_contains "$PROTOCOL_90" 'configured real regression|explicitly enabled placeholder' \
  "batch orchestration protocol must preserve label-gated guidance for configured regression"
assert_contains "$PROTOCOL_91" 'configured real regression|explicitly enabled placeholder' \
  "orchestration protocol must preserve label-gated guidance for configured regression"
assert_contains "$PROTOCOL_92" 'configured real regression|explicitly enabled placeholder' \
  "readiness protocol must preserve label-gated guidance for configured regression"

printf 'placeholder workflow opt-in checks passed\n'

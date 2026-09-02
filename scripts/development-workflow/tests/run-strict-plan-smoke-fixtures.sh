#!/usr/bin/env bash
# Smoke helper for #1655 scenarios 20-21: run strict plan pass on fixture plans
# with the bundled Codex preset. Not invoked from CI.
set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(CDPATH='' cd -- "$SCRIPT_DIR/../../.." && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures/strict-plan-plans"
FIXTURES_PASS="$SCRIPT_DIR/fixtures/strict-plan-plans-pass"
CHECKLIST="$REPO_ROOT/docs/workflow/development-workflow/strict-plan-checks.md"
TIMEOUT="${LOCAL_AI_REVIEWER_TIMEOUT:-120}"
PR_NUM="${SMOKE_PR_NUMBER:-999}"

if ! command -v codex >/dev/null 2>&1; then
  echo "ERROR: codex CLI required for smoke fixtures" >&2
  exit 1
fi

run_fixture() {
  local name="$1"
  local variant="${2:-fail}"
  local tmp mock_bin head plan fixture_dir
  tmp="$(mktemp -d)"
  mock_bin="$(mktemp -d)/bin"
  mkdir -p "$mock_bin"
  plan="docs/specs/developments/strict-fixture-${name}/2_${name}_implementation-plan.md"
  case "$variant" in
    fail) fixture_dir="$FIXTURES/$name" ;;
    pass) fixture_dir="$FIXTURES_PASS/$name" ;;
    *) echo "ERROR: unknown variant $variant (expected fail or pass)" >&2; return 1 ;;
  esac

  git -C "$tmp" init -q
  git -C "$tmp" config user.email "smoke@example.com"
  git -C "$tmp" config user.name "Smoke"
  printf '# Review\n' >"$tmp/REVIEW.md"
  mkdir -p "$tmp/docs/workflow/development-workflow"
  cp "$CHECKLIST" "$tmp/docs/workflow/development-workflow/strict-plan-checks.md"
  mkdir -p "$tmp/docs/specs/developments/strict-fixture-${name}"
  cp "$fixture_dir/"*.md "$tmp/docs/specs/developments/strict-fixture-${name}/"
  git -C "$tmp" add -A
  git -C "$tmp" commit -q -m "fixture $name"
  git -C "$tmp" remote add origin "git@github.com:owner/repo.git"
  head="$(git -C "$tmp" rev-parse HEAD)"

  cat >"$mock_bin/gh" <<MOCK
#!/usr/bin/env bash
case "\$*" in
  *"pr view ${PR_NUM}"*"baseRefName,headRefName,headRefOid"*)
    printf '{"baseRefName":"develop","headRefName":"implementation-plan/smoke-${name}","headRefOid":"${head}"}\n'
    exit 0
    ;;
  *"pr diff ${PR_NUM}"*"--name-only"*)
    printf '%s\nREVIEW.md\n' "${plan}"
    exit 0
    ;;
  *"pr view ${PR_NUM}"*"baseRefName"*)
    printf '{"baseRefName":"develop"}\n'
    exit 0
    ;;
  *) command gh "\$@" ;;
esac
MOCK
  chmod +x "$mock_bin/gh"

  echo "=== fixture: $name [$variant] (head ${head:0:12}) ==="
  set +e
  PATH="$mock_bin:$PATH" \
    LOCAL_AI_REVIEWER_COMMAND="$REPO_ROOT/scripts/development-workflow/local-codex-review-command.sh" \
    bash "$REPO_ROOT/scripts/development-workflow/local-ai-reviewer.sh" \
      "$PR_NUM" owner repo --timeout "$TIMEOUT" --repo-root "$tmp" \
      2>"$tmp/stderr.txt" | tee "$tmp/stdout.txt" | rg '^STRICT_PLAN_' || true
  set -e
  echo "--- findings ---"
  rg '^STRICT_[0-9]+_' "$tmp/stdout.txt" || echo "(none)"
  if [ -s "$tmp/stderr.txt" ]; then
    echo "--- stderr ---"
    tail -3 "$tmp/stderr.txt"
  fi
  rm -rf "$tmp"
  echo
}

positives=(source_declaration unspecified_step spec_traceability ac_test_coverage phase_ordering dependency_state reversal_risk)
negatives=(declared_addition irreversible_declared all_falsifying_tests refactor_brief)

if [ -n "${SMOKE_FIXTURE_ONLY:-}" ]; then
  positives=("$SMOKE_FIXTURE_ONLY")
  negatives=()
fi

SMOKE_VARIANT="${SMOKE_VARIANT:-both}"

echo "Running strict-plan smoke fixtures (timeout ${TIMEOUT}s each)"
for n in "${positives[@]}"; do
  case "$SMOKE_VARIANT" in
    fail) run_fixture "$n" fail ;;
    pass) run_fixture "$n" pass ;;
    *) run_fixture "$n" fail; run_fixture "$n" pass ;;
  esac
done
if [ "${#negatives[@]}" -gt 0 ]; then
  echo "=== negative controls ==="
  for n in "${negatives[@]}"; do
    run_fixture "$n"
  done
fi
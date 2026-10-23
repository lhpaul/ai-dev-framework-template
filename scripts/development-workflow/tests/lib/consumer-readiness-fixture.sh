# shellcheck shell=bash
# Synthetic consumer tree used by the core and independent matrix suites.
# shellcheck disable=SC2154 # Provided by the shared readiness fixture or its caller.
build_fake_root "$portable_root" false
cp -R "$REPO_ROOT/scripts/." "$portable_root/scripts/"
cp -R "$REPO_ROOT/.github/." "$portable_root/.github/"
for surface in docs .claude .cursor template sync-manifest.yaml REVIEW.md; do
  ln -s "$REPO_ROOT/$surface" "$portable_root/$surface"
done
git -C "$portable_root" init -q
cat > "$portable_root/.ai-dev-workflow.yaml" <<'YAML'
template:
  is_template: false
review:
  on_ready:
    github:
      - pr-agent
YAML
cat > "$portable_root/.ai-dev-workflow.local.yaml" <<'YAML'
review:
  on_ready:
    github:
      - local-ai-reviewer
YAML
printf '%s\n' 'name: Consumer Markdown' 'on:' '  workflow_dispatch:' \
  > "$portable_root/.github/workflows/markdown-lint.yml"
for legacy in apply-regression-label remove-regression-label-on-push reviewer-loop-guard; do
  printf '%s\n' 'name: Consumer legacy policy' 'on:' '  workflow_dispatch:' \
    > "$portable_root/.github/workflows/$legacy.yml"
done

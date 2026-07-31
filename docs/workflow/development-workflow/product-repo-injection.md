# Product Repository Injection

Use this guide from a product repository checkout when the repository should
receive the minimal workflow integration surface for hub-routed work.

Related references:

- [Repository modes](repository-modes.md)
- [Workflow hub setup](workflow-hub-setup.md)
- [Sync-template command](../../../.claude/commands/sync-template.md)
- [Sync manifest](../../../sync-manifest.yaml)
- [Product repository injection skeleton](../../../template/product-repo-injection/README.md)

## Product Repo Mode

Run location: product repository checkout.

The versioned `.ai-dev-workflow.yaml` identifies the product repository and its
hub. Keep it free of machine-local paths and secret material.

```yaml
schema_version: 2
mode: product_repo

product_repo:
  workflow_hub:
    github_repo: example/faind-workflow-hub
```

Local checkout paths and credential references belong in the hub operator's
`.ai-dev-workflow.local.yaml`, not in product repository versioned config.

## Role-Aware Sync Selection

Run location: product repository checkout.

When sync-template reads `sync-manifest.yaml`, product repositories select:

- `shared`
- `product_repo_injection`

Product repositories skip:

- `hub_only`

Preview the manifest selection before applying a template sync:

```bash
python3 scripts/development-workflow/select-sync-manifest-entries.py \
  --manifest sync-manifest.yaml \
  --role product_repo
```

Then run sync-template in dry-run mode:

```text
/sync-template --local=../ai-dev-framework-template --dry-run
```

The dry-run summary should show selected and skipped entries before any file is
applied.

## What Product Repos Must Not Receive

Product repositories must not receive hub-owned workflow state unless a future
workflow contract explicitly marks a specific file as product-repo injection:

- Hub tracker state.
- Historical specs.
- Implementation plans.
- Workflow protocols.
- Hub orchestration scripts.
- Hub-only runbooks.

Product repositories may receive shared docs, local integration wrappers, config
schema comments, and injection-safe files declared with
`product_repo_injection`.

For product-owned release work, product repositories may also receive the
minimum runtime helpers needed to validate non-secret release configuration,
run product PR reviewer and CI loops, and record product branch or PR cleanup
evidence:

- `scripts/development-workflow/workflow-config-resolver.py`
- `scripts/development-workflow/validate-workflow-config.sh`
- `scripts/development-workflow/workflow-lib.sh`
- `scripts/development-workflow/pr-review-loop.sh`
- `scripts/development-workflow/pr-ci-loop.sh`
- `scripts/development-workflow/post-merge-cleanup.sh`

These files are product release runtime surfaces, not hub coordination state.
Historical specs, implementation plans, workflow protocols, hub orchestration
scripts, delivery coordination runbooks, and hub tracker state remain excluded.

## Apply Injection Safely

Run location: product repository checkout.

1. Confirm the product repository is on the intended base branch.
2. Run sync-template dry-run and inspect selected/skipped scopes.
3. Apply approved changes only after reviewing divergent local files.
4. Commit the injected files through the product repository's normal PR flow.
5. Keep `.ai-dev-workflow.local.yaml` and any credential material untracked.

## Troubleshooting

### Unexpected Hub Files In Product Repo Output

Symptom: dry-run output includes `docs/workflow/development-workflow/protocols/`
or `scripts/development-workflow/` as selected entries.

Confirm from the product repository checkout:

```bash
python3 scripts/development-workflow/select-sync-manifest-entries.py \
  --manifest sync-manifest.yaml \
  --role product_repo
```

Safe repair:

- Verify the repository declares `mode: product_repo`.
- Verify the manifest entry is not incorrectly marked
  `product_repo_injection`.
- Stop before applying if hub-owned files are selected unexpectedly.

### Divergent Local Files

Symptom: sync-template dry-run reports local differences for selected files.

Safe repair:

- Review the diff before applying.
- Preserve product-specific content.
- Apply only the template-owned sections for mixed-content files.

### Missing Local Config

Symptom: validation cannot resolve the hub or local product checkout.

Safe repair:

- Keep product identity in `.ai-dev-workflow.yaml`.
- Put machine-local paths only in `.ai-dev-workflow.local.yaml` in the hub
  operator environment.

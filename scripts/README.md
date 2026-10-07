# Repository scripts

Scripts intended to be run from the repository root or from CI/CD.

## Development workflow

AI development workflow helpers (orchestrator, Codex skills, PR/CI loops) live in **`scripts/development-workflow/`**. See [development-workflow/README.md](development-workflow/README.md) for usage.

Repositories created from this template can add their own scripts alongside this directory (e.g. `scripts/build.sh`, `scripts/deploy.sh`) without mixing them with the template’s workflow scripts.

## Template Sync Preservation

`development-workflow/sync-template-merge.py` previews and applies selected
always-sync paths from a pinned committed template tree. It reuses the manifest
selector and coverage matcher, preserving role selection and exact project-owned
exclusions. Consumer changes combine with verified upstream history through
`git merge-file -p`; conflicts stop the entire selected batch before writes.

Preview requires `--template-root`, `--consumer-root`, full `--template-ref`,
normalized `--template-id` (repository name), `--role`, and `--plan`. Keep plans
in private scratch outside both checkouts: they contain prepared file bytes.
Optional `--base-ref` and `--base-source template|consumer` assert maintainer-verified
prior-sync/bootstrap provenance. A version or guessed SHA is insufficient.
Without a base, only equality is safe; differing and uncertain missing paths block.

The consumer-owned `.ai-dev-workflow.sync-state.json` stores schema version,
template identity and per-path upstream commit/source/blob/mode. Null blob/mode
records verified absence. Baseline bytes come from those Git objects, never from
merged consumer content. Missing historical objects must be made available in
private source preparation or consumer history before preview. Existing ledger
entries override an explicit base; missing entries remain unknown unless verified
history is supplied. Corrupt state never becomes a legacy fallback.

When the committed manifest is absent, `--selection-file` supplies protocol-derived
fallback JSON with `role`, exact `paths`, and `project_specific`. It binds the
existing fallback policy; it does not invent a new category. Named `--decline`
paths are excluded and require a fresh preview/approval. Declines and role-skipped
paths retain their previous baseline.

Apply requires `--plan` and `--approved-digest`, the SHA-256 value captured
independently when the maintainer approved the exact preview. It cannot derive
authority from the plan itself. Apply acquires `.ai-dev-workflow.sync-lock` before
freshness/backup checks, holds it through validation/persistence/rollback, and
advances per-path state only after the data batch validates. No conflict-side or
delete override exists. Symlinks are atomic targets validated within the final
consumer tree; executable-bit changes are compared independently of text.

Preview prints `RESULT=ready|blocked`, `SELECTED_COUNT`, `COUNTS`, dispositions
and `PREVIEW_DIGEST`; apply succeeds with `RESULT=applied` and completed
dispositions. Counts partition the approved selected paths; declined paths are
listed separately. Preview exits 0 when ready, 1 for classified blockers, or 2
for invalid/unreadable inputs. Apply exits 0 on success or 2 on refused/failed
input or transaction. Consumer files and baseline metadata are restored on
handled failures. The journal stores original bytes privately before writes.

An interrupted process or failed restoration retains the lock/recovery journal.
Preserve `.ai-dev-workflow.sync-lock/recovery.json`, inspect each named original
snapshot and repair the consumer/ledger under maintainer supervision before
clearing the lock. Do not auto-clear a leftover lock or retry an old approval.
Git commits/PR/CI remain the canonical sync protocol's responsibility; failure
there does not authorize reapplying a stale preview.

Behavioral tests: `bash development-workflow/tests/test-sync-template-merge.sh`
from `scripts/`, or `bash scripts/development-workflow/tests/test-sync-template-merge.sh`
from the repository root. They use isolated synthetic Git histories and include
failure/correction proofs without modifying live consumers.

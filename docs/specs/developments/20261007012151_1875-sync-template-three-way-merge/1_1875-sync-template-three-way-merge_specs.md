# Preserve Local Template Patches During Sync — Spec

**Issue**: [#1875](https://github.com/lhpaul/ai-dev-framework-template/issues/1875)

---

## Overview

Template consumers sometimes patch framework-owned files before the upstream
template includes those fixes. Template sync must preserve that work while
bringing in upstream changes. Maintainers receive a preview that distinguishes
safe updates, preserved local patches, conflicts, and files whose history is
unknown. A sync cannot silently replace locally modified content.

## Brief Objective List

1. Remember the exact upstream baseline used by a successful sync.
2. Detect consumer modifications since the last sync or a verified bootstrap.
3. Update unmodified files directly and combine independent local and upstream
   changes; conflicting changes require resolution before applying the batch.
4. Show locally modified template files and counts in the Step 3 summary.
5. Preserve local patches or present explicit conflicts; name every affected
   file instead of silently overwriting it.
6. Degrade safely for legacy consumers without recorded baseline evidence.

## Use Cases

### Use Case 1: Sync with independent local patches

**Actor**: Consumer maintainer operating template sync through an agent.
**Preconditions**: The template source is resolved, selected always-sync paths
are known, and trustworthy baseline evidence is available for the files.

**Steps**:

1. The maintainer requests a preview or sync.
2. The agent compares each file with its baseline and the incoming template.
3. The preview names locally modified files and shows whether their changes
   can be combined with the incoming template without conflict.
4. The maintainer approves the existing sync mode and any discretionary plan.
5. The agent applies direct updates and clean combinations, preserving local
   changes, then records baseline evidence for the files actually synchronized.

**Postconditions**: Independent consumer patches and upstream changes are both
present; a later sync can identify the upstream baseline of each applied file.

**Information shown**: Baseline provenance, direct updates, clean combinations,
local-only retained changes, and per-file dispositions with category counts.

**Actions available**: Inspect the preview, approve the existing sync mode,
decline individual files under the existing policy, or cancel the sync.

**Considerations**: A local-only change is retained even when upstream has not
changed that file. A declined file does not acquire an unapplied baseline.

### Use Case 2: Resolve a conflict or unavailable baseline

**Actor**: Consumer maintainer.
**Preconditions**: A selected file has incompatible changes or lacks sufficient
evidence to distinguish local content from an upstream update.

**Steps**:

1. The preview names each conflict or uncertain file with its reason.
2. The agent stops before applying the always-sync batch, without changing
   consumer files or successful-sync metadata.
3. The maintainer resolves the conflict or supplies trustworthy baseline
   evidence, then requests a fresh preview.
4. Sync proceeds through the usual approval flow only when the new preview
   contains no unresolved conflict or uncertain file.

**Postconditions**: No patch is discarded by the failed attempt. Failed or
partial attempts do not falsely advertise a complete new baseline.

**Information shown**: Exact paths, conflict or baseline-unavailable reason,
provenance when known, counts, and the action needed before retrying.

**Actions available**: Resolve content, supply baseline evidence, decline the
affected path explicitly and re-preview the remaining approved set, or cancel.

**Considerations**: Bulk approval, either primary sync mode, and the advanced
always-sync-only mode cannot authorize an unresolved overwrite. An unavailable
baseline does not make differing consumer content safe to replace.

### Use Case 3: Safely upgrade a legacy or bootstrapped consumer

**Actor**: Consumer maintainer.
**Preconditions**: No exact baseline has been recorded by a prior sync.

**Steps**:

1. The agent uses verified prior-sync or bootstrap evidence when it can establish
   the actual upstream baseline; ambiguity is surfaced instead of guessed.
2. If that evidence is unavailable, identical files are left untouched and
   genuinely new files can be added under the existing approval flow.
3. Differing existing files and deletions whose intent cannot be determined
   are named as baseline unavailable and block the affected batch.
4. A successful sync records trustworthy baseline evidence for its applied
   files without assuming that skipped or declined files were synchronized.

**Postconditions**: Older consumers remain protected even without migration
metadata; subsequent syncs reuse the evidence recorded for applied files.

**Information shown**: Whether baseline evidence is recorded, recovered from
verified history, or unavailable, plus the files requiring attention.

**Actions available**: Verify historical evidence, review uncertain files,
approve safe additions, decline named paths and re-preview, or cancel.

## Business Rules

- BR1: A trustworthy baseline represents upstream content, separately from
  consumer patches. A version label alone is insufficient when it does not
  establish the exact content actually used by the consumer.
- BR2: Unmodified consumer files may receive direct upstream updates. Locally
  modified files retain their modifications through a clean combination or an
  explicit conflict. Content equality with the incoming template needs no edit.
- BR3: Conflicts, unsupported content, unreadable evidence, and unknown local
  change history fail safely. All affected paths are named before mutation;
  unresolved cases prevent the selected always-sync batch from being applied.
- BR4: A consumer deletion of a previously synchronized file is a local change,
  not permission to recreate it silently. A file absent from both the baseline
  and consumer is a new addition. Consumer-only files are never deleted.
- BR5: Preview and apply use the same selected paths and evidence. Changes to
  consumer content, incoming content, selection, or baseline between preview
  and apply require a fresh preview and approval before mutation.
- BR6: Dry-run remains read-only. An unsuccessful attempt leaves consumer content
  and successful-sync metadata unchanged. Baselines advance only for files
  actually synchronized; declined, excluded, and unresolved paths retain their
  prior evidence or unknown status.
- BR7: Repository-role selection, project-specific exclusions, special-handling
  approvals, rename cleanup, placeholder safeguards, and reviewer/CI gates
  continue to apply. Always-sync approval does not waive a local conflict.
- BR8: Canonical and mirrored Claude, Cursor, and Codex sync entrypoints agree
  on classification, preservation, summary, approval, and stop behavior.

## Decision-Gate Consistency Matrix

Rows are evaluated in order for each selected path using current preview
evidence. Apply revalidates that evidence before any batch write.

| Gate inputs | Outcome | Required next action | Mirror surfaces | Example |
| --- | --- | --- | --- | --- |
| Unsupported or unreadable content/evidence | Hard stop | Name path and repair before fresh preview | All sync entrypoints | Unreadable selected file |
| Consumer equals incoming content | No change | Preserve content; record verified evidence only after successful sync | All sync entrypoints | Already updated file |
| No baseline and existing differing consumer file | Baseline unavailable | Name path; obtain evidence or decline explicitly and re-preview | All sync entrypoints | Legacy consumer patch |
| No baseline and absent consumer file | Baseline unavailable | Distinguish a new upstream file from a consumer deletion using verified history; otherwise stop | All sync entrypoints | Missing legacy workflow |
| Baseline proves path new and consumer absent | Add | Apply only after normal approval | All sync entrypoints | Newly introduced helper |
| Baseline available and consumer equals baseline | Direct update | Apply incoming content after normal approval | All sync entrypoints | Untouched protocol |
| Baseline available; consumer changed; incoming equals baseline | Local change retained | Name path and preserve consumer content | All sync entrypoints | Consumer-only fix |
| Baseline available; both changed; combination clean | Clean merge | Name path and apply reviewed combination after normal approval | All sync entrypoints | Independent edits |
| Baseline available; both changed; combination conflicts | Hard stop | Name path and resolve before fresh preview | All sync entrypoints | Same lines edited |
| Previously synchronized file absent in consumer | Local deletion | Name path; preserve deletion if upstream unchanged, otherwise stop for resolution | All sync entrypoints | Intentionally removed helper |
| Evidence changes after approval | Stale preview | Stop without applying; generate fresh preview and obtain approval | All sync entrypoints | Patch edited after preview |

Content equality takes precedence over other content rows; unsupported evidence
never reaches an apply row. The local-deletion row specializes the consumer
changed rows. Baseline-unavailable cases always stop unless the path is explicitly
declined and a fresh approved set is previewed; no approval mode bypasses them.

## Operational Visibility

- Step 3 includes **Locally modified template files** with counts and exact paths
  for clean merges, retained local-only changes, local deletions, conflicts, and
  baseline-unavailable files (unknown history is labeled, not claimed as proven).
- Existing always-sync counts reconcile with these dispositions; a locally
  modified file is not counted as an ordinary overwrite.
- The completed sync summary and PR describe preservation outcomes and baseline
  provenance without exposing credentials or machine-local configuration.

## Acceptance Criteria

- [ ] AC1: An unmodified previously synchronized file receives upstream changes
      under the existing approval flow.
- [ ] AC2: Independent local and upstream changes survive a sync together; every
      clean merge is listed by path in Step 3 and the completed summary.
- [ ] AC3: A same-content conflict blocks the selected always-sync batch before
      writes; all consumer files and successful-sync metadata remain unchanged.
- [ ] AC4: With no trustworthy baseline, every differing existing file is named
      as baseline unavailable and remains unchanged; absent files are not
      recreated unless evidence proves they are new additions.
- [ ] AC5: Verified bootstrap or previous-sync evidence permits preservation
      without requiring a prior run of the new sync behavior.
- [ ] AC6: A second sync preserves a patch retained by the first sync and uses
      the actual upstream baseline recorded for each applied file. Declining a
      file does not advance that file's baseline.
- [ ] AC7: Dry-run and a stale approved preview leave consumer content and
      successful-sync metadata unchanged; stale evidence requires re-preview.
- [ ] AC8: Local-only changes and deletions are reported and retained when
      upstream is unchanged; deletion versus upstream modification stops for
      resolution. Consumer-only files remain untouched.
- [ ] AC9: Role selection and project-specific exclusions still hold; all sync
      mirrors use the same preservation rules and existing approvals/CI gates.
- [ ] AC10: Step 3 reports affected paths and mutually reconcilable category
      counts, including conflicts and unknown-baseline cases, even when stopped.

## Coverage Matrix

| Brief objective | Acceptance criteria |
| --- | --- |
| 1. Record exact upstream baseline | AC5, AC6 |
| 2. Detect local changes since sync/bootstrap | AC1, AC2, AC5, AC8 |
| 3. Direct updates, clean merges, conflict hard stops | AC1, AC2, AC3, AC8 |
| 4. Step 3 local-modification counts | AC2, AC10 |
| 5. Preserve patches and name affected files | AC2, AC3, AC4, AC8, AC10 |
| 6. Safe legacy fallback | AC4, AC5, AC6, AC7 |

## Out of Scope (MVP)

- Automatically choosing conflict resolutions or overwriting unknown content.
- Changing category membership, discretionary approval modes, release handling,
  or the downstream review policy.
- Synchronizing application source or deleting consumer-only files.
- Repairing the advisory post-merge closing-keyword workflow reported separately.

All brief objectives are covered; none are deferred. Exact baseline storage,
history verification, and merge mechanics belong in the implementation plan.

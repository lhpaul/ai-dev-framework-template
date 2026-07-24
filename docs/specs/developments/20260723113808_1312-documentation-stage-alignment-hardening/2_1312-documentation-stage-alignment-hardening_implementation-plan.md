# Portable Documentation-Stage Alignment Hardening - Implementation Plan

**Spec**: [1_1312-documentation-stage-alignment-hardening_specs.md](1_1312-documentation-stage-alignment-hardening_specs.md)
**Smoke test runbook**: [1312-documentation-stage-alignment-hardening.smoke-test.md](../../../testing/workflow/1312-documentation-stage-alignment-hardening.smoke-test.md)

---

## Summary

**Approach**: Harden the existing documentation-stage checker at its two unsafe
boundaries. Reject any changed path containing an exact `..` segment before
running the stage allowlist regexes. Replace help-text-based base64 flag
detection with an explicit known-payload capability probe, cache the selected
decoder form, and check every real decode so unsupported environments or
malformed payloads exit through the existing infrastructure-failure contract
instead of reaching the alignment classifier.

**Estimated complexity**: S

**Rationale**: The behavior is localized to one shell helper and its test
harness. The implementation preserves the existing stage allowlists and exit
codes while closing the traversal bypass and making decode behavior
deterministic across the required command families.

**Dependencies**: Existing Bash, `jq`, and `base64` command dependencies only.
No new package or service is introduced.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `21f23e3` |
| Template-fit check | Read `.ai-dev-workflow.yaml`, issue #1312, and the approved spec | Template-generic workflow hardening; no downstream-specific product behavior |
| Unsafe path boundary | `rg -n "path_allowed_for_stage|smoke-test" scripts/development-workflow/check-documentation-stage-alignment.sh` | Plan-stage smoke tests currently use `^docs/testing/.+\.smoke-test\.md$` without a prior traversal-segment rejection |
| Decoder boundary | `rg -n "base64_decode|@base64" scripts/development-workflow/check-documentation-stage-alignment.sh` | The checker selects `--decode` from help text and otherwise assumes macOS `-D`; the decode assignment does not add an actionable failure reason |
| Existing result contract | `rg -n "MISMATCH_EXIT|INFRASTRUCTURE_EXIT" scripts/development-workflow/check-documentation-stage-alignment.sh` | Mismatch remains exit `8`; evaluation/infrastructure failure remains exit `10` |
| Current test surface | Read `scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh` | One shell harness already covers fixture/live modes, path allowlists, warning updates, and infrastructure errors; extend it rather than adding a parallel harness |
| Readiness guidance | `rg -n "documentation-stage alignment checker infrastructure failure|GitHub/diff read failure" docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Protocol 91 handles exit `10`, but its recovery text names only GitHub/diff reads and must include decode/capability failures |
| Runner mirrors | `rg -l "documentation-stage alignment checker" .agents/skills .codex/skills .claude/agents .cursor/agents | sort` | Existing runner surfaces delegate to Protocol 91 and do not duplicate decoder or allowlist details |

---

## Layer-by-Layer Changes

### Documentation-Stage Alignment Helper

- [ ] Add a small predicate that splits repository-relative paths on `/` and
      returns unsafe when any complete segment equals `..`.
- [ ] Run the traversal predicate before every stage-specific allowlist match.
      A path such as
      `docs/testing/../specs/example.smoke-test.md` must be rejected even though
      its prefix and suffix resemble an allowed smoke-test artifact.
- [ ] Keep canonical direct paths under `docs/testing/` accepted. Do not
      normalize away `..`, resolve paths against the filesystem, or expand the
      current spec/plan allowlists.
- [ ] Keep traversal rejection in the ordinary `mismatch` result. Include the
      original unnormalized path in `unexpected_files` so human-readable and
      JSON evidence show the artifact that must be corrected.
- [ ] Replace `base64 --help | grep` detection with a one-time ordered
      capability probe over the representative payload `Zg==`, whose expected
      decoded value is `f`.
- [ ] Probe the supported decoder forms without relying on help text:
      GNU `--decode`, portable GNU/BusyBox `-d`, and macOS `-D`. Cache only the
      first form that exits successfully and produces exactly the expected
      bytes.
- [ ] If no decoder form passes the probe, emit an actionable message naming
      the unavailable base64 capability and return the existing infrastructure
      exit `10`.
- [ ] Check the status of every real changed-path decode. A non-zero decoder
      exit must return infrastructure failure `10`; it must not pass an empty
      path to `path_allowed_for_stage` or be converted to `mismatch`.
- [ ] Preserve the current `@base64` transport from `jq`, which keeps
      line-oriented shell iteration safe. Limit this item to decoder
      portability rather than redesigning the state/fixture schema.
- [ ] Add a test-only way for the existing fixture harness to feed an encoded
      path value into the same decoder path. Keep it unavailable in live PR
      mode and document it as fixture-only so malformed-payload coverage does
      not become a production input surface.
- [ ] Keep successful human-readable and JSON output fields unchanged. For
      evaluation failures, write an actionable error to stderr and exit `10`
      without emitting an `aligned` or `mismatch` result.

### Work Item Runner Readiness Guidance

- [ ] Update Protocol 91's documentation-stage checker error branch and exit
      `10` troubleshooting text to name changed-file decoding and unsupported
      decoder capability alongside GitHub/diff read failures.
- [ ] Preserve the existing readiness behavior: exit `8` is an artifact
      mismatch that can add/update the warning and `needs-fixes`; exit `10` is
      an evaluation failure that stops readiness without pretending the PR diff
      was classified.
- [ ] Leave readiness labels, tracker transitions, comment markers, and
      checker invocation order unchanged.

### Tests

- [ ] Extend
      `scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh`.
- [ ] Add a canonical `docs/testing/workflow/*.smoke-test.md` assertion to
      protect the allowed plan-stage path.
- [ ] Add traversal fixtures after an allowed prefix, at a deeper directory,
      and in a lookalike segment such as `...` to prove segment-boundary
      behavior.
- [ ] Add mock base64 commands for macOS (`-D`), GNU (`--decode`/`-d`), and
      BusyBox (`-d`) and run the same representative encoded path through each.
- [ ] Assert each supported mock produces byte-identical decoded content and
      the same `aligned` classification.
- [ ] Add a mock that passes the capability probe and fails on the real payload
      to verify per-decode status handling.
- [ ] Add fixture-only malformed encoded content and assert exit `10`, an
      actionable decoding error, and no JSON `aligned`/`mismatch` verdict.
- [ ] Add a mock with no supported decoder flag and assert exit `10` identifies
      the environment capability failure.
- [ ] Preserve all existing warning-marker, live GitHub, auth, empty-diff, and
      non-documentation branch tests as regressions.

### Database / Data Layer

- [ ] Not applicable. No product data, schema, migration, or seed changes.

### Backend / API

- [ ] Not applicable. No product service or network API changes.

### Shared Packages / Libraries

- [ ] Not applicable. The changed shared surface is the existing workflow shell
      helper.

### Frontend / UI

- [ ] Not applicable. No product UI changes.

### Infrastructure / Configuration

- [ ] No new dependencies, containers, secrets, or CI services.
- [ ] Environment-family coverage uses deterministic command shims in the
      existing shell harness, so the repository test suite does not require
      separate macOS, GNU, and BusyBox workers.

---

## Files to Modify

### Required Implementation Files

- [ ] `scripts/development-workflow/check-documentation-stage-alignment.sh` -
      traversal predicate, explicit decoder probe, checked decode path, and
      fixture-only malformed-payload seam.
- [ ] `scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh`
      - traversal, portability, invalid-payload, and unsupported-capability
      cases.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      - broaden exit `10` evidence and recovery guidance.

### Explicitly Not Required

- [ ] `.agents/skills/run-item/SKILL.md`,
      `.agents/skills/run-items/SKILL.md`,
      `.codex/skills/workflow-item-orchestrator/SKILL.md`, and
      `.codex/skills/workflow-orchestrator/SKILL.md` already delegate the
      documentation-stage decision to Protocol 91. They do not duplicate
      allowlist, decoder, or exit `10` details.
- [ ] `docs/workflow/development-workflow/protocols/92-pr-readiness-signal-protocol.md`
      retains the same aligned-versus-blocked contract and needs no change.
- [ ] `REVIEW.md` keeps the same stage-alignment requirement; no review category
      or checklist semantics change.
- [ ] `CHANGELOG.md` is exempt from this plan PR. The implementation PR adds
      the exact entry listed in **Implementation Order**.
- [ ] Downstream template-sync PRs and product repositories are outside this
      item.

---

## Workflow Decision-Gate Consistency Matrix

| Gate inputs | Allowed outcome | Required next action | Mirror surfaces | Example / test |
| --- | --- | --- | --- | --- |
| Plan stage plus canonical direct smoke-test path; decode succeeds | `aligned` | Continue normal readiness | Checker JSON/text output; Protocol 91; existing runner delegates | `plan_canonical_smoke_test_remains_aligned` |
| Plan stage plus path with exact `..` segment after allowed prefix | `mismatch`, exit `8` | Show original path, correct diff, rerun | Checker output/warning; Protocol 91 mismatch branch | `plan_parent_traversal_is_mismatch` |
| Plan stage plus lookalike `...` segment | Existing allowlist decision | Do not reject merely as parent traversal | Checker output and tests | `triple_dot_segment_is_not_parent_traversal` |
| Valid encoded path with GNU decoder | Existing aligned/mismatch classification | Continue based on decoded path | Decoder probe; checker output; tests | `gnu_decode_matches_reference` |
| Valid encoded path with macOS decoder | Existing aligned/mismatch classification | Continue based on decoded path | Decoder probe; checker output; tests | `macos_decode_matches_reference` |
| Valid encoded path with BusyBox decoder | Existing aligned/mismatch classification | Continue based on decoded path | Decoder probe; checker output; tests | `busybox_decode_matches_reference` |
| Invalid encoded path or selected decoder fails during real decode | Evaluation failure, exit `10` | Stop readiness, report decode failure, repair payload/environment, retry | Checker stderr/exit; Protocol 91 infrastructure branch | `invalid_payload_fails_evaluation`, `decode_failure_after_probe_fails_evaluation` |
| No decoder form passes the known-payload probe | Evaluation failure, exit `10` | Stop readiness, report unsupported capability, repair environment, retry | Checker stderr/exit; Protocol 91 infrastructure branch | `unsupported_decoder_fails_evaluation` |

---

## Cross-Cutting Checklist Coverage

This item hardens an existing gate; it does not add a new planning, review,
safety, compliance, or quality checklist category.

- [ ] Existing enforcement remains in Protocol 91.
- [ ] Existing runner skills and agents remain correct because they delegate to
      the protocol and checker result contract.
- [ ] Existing review and readiness categories remain unchanged.
- [ ] The full changed decision matrix is covered in the helper's existing
      shell harness.

---

## Parser-Risk Addendum

This plan is parser-risk because it changes regex-adjacent repository-path
classification and encoded structured-text handling.

### Edge-Case Enumeration

1. Canonical accepted paths:
   - `docs/testing/workflow/example.smoke-test.md`
   - `docs/testing/mobile/nested/example.smoke-test.md`
2. Exact parent traversal:
   - `docs/testing/../specs/example.smoke-test.md`
   - `docs/testing/workflow/../../src/example.smoke-test.md`
   - `../docs/testing/workflow/example.smoke-test.md`
3. Boundary lookalikes:
   - `docs/testing/.../example.smoke-test.md`
   - `docs/testing/..hidden/example.smoke-test.md`
   - `docs/testing/parent../example.smoke-test.md`
4. Valid representative payload:
   - `ZG9jcy90ZXN0aW5nL3dvcmtmbG93L2V4YW1wbGUuc21va2UtdGVzdC5tZA==`
     decodes to `docs/testing/workflow/example.smoke-test.md`
5. Invalid payload:
   - `%%%not-base64%%%`
   - truncated padding
6. Decoder families:
   - GNU accepts `--decode` and/or `-d`
   - BusyBox accepts `-d`
   - macOS accepts `-D`
7. Failure timing:
   - no probe form succeeds
   - probe succeeds but real payload decode fails
8. Output boundary:
   - mismatch JSON includes the original traversal path
   - decode failure emits no aligned/mismatch JSON result

### Unit Test Mapping

Extend
`scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh`
with at least:

1. `plan_canonical_smoke_test_remains_aligned` covers Edge case 1.
2. `plan_parent_traversal_is_mismatch`,
   `deep_parent_traversal_is_mismatch`, and
   `leading_parent_traversal_is_mismatch` cover Edge case 2.
3. `triple_dot_segment_is_not_parent_traversal`,
   `dotdot_prefix_is_not_parent_traversal`, and
   `dotdot_suffix_is_not_parent_traversal` cover Edge case 3.
4. `gnu_decode_matches_reference`,
   `busybox_decode_matches_reference`, and
   `macos_decode_matches_reference` cover Edge cases 4 and 6.
5. `invalid_payload_fails_evaluation` covers Edge case 5.
6. `unsupported_decoder_fails_evaluation` and
   `decode_failure_after_probe_fails_evaluation` cover Edge case 7.
7. `traversal_evidence_preserves_original_path` and
   `decode_failure_emits_no_alignment_verdict` cover Edge case 8.

### Suppression Semantics

No traversal or decode suppression is introduced. An exact `..` segment always
fails the stage allowlist, and an unverified decode always fails evaluation.

---

## Concurrency Safety

No concurrent event source is introduced.

- **Shared mutable state guards**: Not applicable; classification is local and
  read-only until existing warning logic handles a confirmed mismatch.
- **Re-entrancy / in-flight tracking**: The decoder selection is scoped to one
  process invocation and may be recomputed safely on rerun.
- **Event deduplication**: Existing stable warning-marker behavior remains
  unchanged.
- **Listener and resource cleanup**: Test shims live under the harness temporary
  directory and are removed by the existing trap.
- **Race conditions at initialization**: The decoder probe completes before any
  path classification.
- **Race conditions at teardown**: Not applicable; no background work is
  started.
- **Error propagation across async boundaries**: Not applicable; decoder and
  classifier exits are synchronous.

---

## Testing Strategy

**Test types**: Shell unit harness with fixture inputs and command shims,
existing live-mode mock regressions, shell lint, markdown lint, and smoke
runbook.

**Key scenarios to test**:

1. Exact traversal segments cannot bypass the plan allowlist. Maps to AC1, AC6,
   and AC8.
2. Canonical smoke-test documentation remains aligned. Maps to AC2 and AC7.
3. The same valid payload classifies identically under GNU, BusyBox, and macOS
   decoder forms. Maps to AC3 and AC6.
4. Invalid encoded content exits `10` and never becomes clean, empty, or
   mismatch. Maps to AC4, AC6, and AC8.
5. Missing decoder capability exits `10` with repair guidance. Maps to AC5,
   AC6, and AC8.
6. Existing non-traversal fixture and live-mode outcomes remain unchanged.
   Maps to AC7.

**Regression suite**:

- `bash scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh`
- `shellcheck scripts/development-workflow/check-documentation-stage-alignment.sh scripts/development-workflow/tests/test-check-documentation-stage-alignment.sh`
- `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`

**Smoke test runbook**:
`docs/testing/workflow/1312-documentation-stage-alignment-hardening.smoke-test.md`

---

## Seed Data

No database seed data is required.

| Entity | Values / Scenario | File |
| --- | --- | --- |
| Alignment fixtures | Canonical, traversal, lookalike, valid encoded, and invalid encoded paths | Generated in `test-check-documentation-stage-alignment.sh` |
| Decoder shims | GNU, BusyBox, macOS, unsupported, and fails-after-probe behaviors | Generated under the harness temporary directory |

---

## Documentation Updates

- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      - include decoder/payload evaluation failures in exit `10` evidence and
      recovery guidance.
- [ ] Other workflow protocols, runner skills/agents, `REVIEW.md`,
      `AGENTS.md`, and `docs/project/*` need no changes because the public gate,
      labels, status transitions, and stage policies remain unchanged.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Traversal check rejects harmless lookalike names | Medium | Medium | Compare complete `/`-delimited segments and test `...`, `..hidden`, and `parent..` |
| Probe accepts a decoder form that later hides failures | Low | High | Validate known bytes during probing and check every real decode status |
| Decoder failure is converted to an ordinary mismatch | Medium | High | Route decode errors directly to infrastructure exit `10` before allowlist classification |
| Environment mocks do not reflect supported CLI dialects | Low | Medium | Model only documented flag/output contracts and use one identical payload across all shims |
| Fixture-only encoded input leaks into live behavior | Low | Medium | Accept the seam only in `--input` mode and reject/ignore it in live PR state |
| Readiness guidance remains GitHub-specific | Medium | Low | Update both Protocol 91 exit `10` references to name decoding/capability failures |

---

## Code Samples

No code samples are included. The implementation PR should make the focused
shell and test changes directly.

---

## Implementation Order

1. Add the exact-segment traversal predicate and call it before stage regex
   matching.
2. Add canonical, traversal, and boundary-lookalike tests, then run the checker
   harness.
3. Replace help-text detection with the known-payload decoder capability probe
   and cache the selected GNU/BusyBox/macOS flag form.
4. Make every real decode status-checked and route failure to infrastructure
   exit `10` with actionable stderr context.
5. Add the fixture-only malformed-encoded-path seam and the GNU, BusyBox,
   macOS, invalid-payload, unsupported-capability, and post-probe-failure tests.
6. Run the complete checker harness and confirm all prior cases still pass.
7. Update both Protocol 91 exit `10` references with decode/capability recovery
   guidance.
8. Add the implementation changelog entry under `[Unreleased]` using this exact
   format:
   `- **Harden Documentation-Stage Alignment Portability** (#1312): Reject parent-directory traversal and fail visibly when changed-path decoding is unsupported or invalid.`
9. Run ShellCheck and
   `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`.
10. Run markdown lint on changed Markdown files.
11. Execute
    `docs/testing/workflow/1312-documentation-stage-alignment-hardening.smoke-test.md`
    and record the evidence in the implementation PR.

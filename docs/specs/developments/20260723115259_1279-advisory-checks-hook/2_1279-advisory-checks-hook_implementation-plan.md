# Advisory Checks Hook for Reviewer Loop - Implementation Plan

**Spec**: [1_1279-advisory-checks-hook_specs.md](1_1279-advisory-checks-hook_specs.md)
**Smoke test runbook**: [1279-advisory-checks-hook.smoke-test.md](../../../testing/workflow/1279-advisory-checks-hook.smoke-test.md)

---

## Summary

**Approach**: Add one fail-open shell extension function to the reviewer loop,
invoke it once after the normal platform/thread result has settled, and pass its
rendered Markdown through a new trailing summary argument. Ship an executable
no-op extension file as the project customization point and document the
stdout-only advisory contract.

**Estimated complexity**: M

**Rationale**: The code footprint is small, but the hook touches a large
workflow script with multiple terminal paths. The implementation must prove
ordering, one-time invocation, multiline rendering, non-zero-exit containment,
and unchanged reviewer results across clean and blocking outcomes.

**Dependencies**: None.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse HEAD` | `21f23e3bbd3edc537381901bd08c9c4b11e28609` |
| Authoritative spec directory | `find docs/specs/developments -maxdepth 2 -type f \| rg "1279"` | The merged spec is under `docs/specs/developments/20260723115259_1279-advisory-checks-hook/`; this plan uses that existing directory rather than the issue creation timestamp. |
| Merged spec link target | `git show origin/develop:docs/specs/developments/20260723115259_1279-advisory-checks-hook/1_1279-advisory-checks-hook_specs.md` and the matching GitHub contents API query | The relative Spec links in this plan and runbook resolve to the merged file on `develop` (Git blob `c5e4c5d96094e2d98b164bde0c2eb2bbae8cc0fc`). |
| Current summary signature | `rg -n "^_post_review_summary\\(\\)|pre_after_clean_only_mode" scripts/development-workflow/pr-review-loop.sh` | `_post_review_summary()` currently accepts 13 parameters; parameter 13 is `pre_after_clean_only_mode`. The new advisory fragment is therefore trailing parameter 14. |
| Current summary ordering | `rg -n "phase_section.*compare_section.*advisory_section.*regression_label_section" scripts/development-workflow/pr-review-loop.sh` | Findings render phase details, compare details, platform advisory findings, then the regression annotation. The project advisory fragment belongs after existing platform advisory findings and before the regression annotation. |
| Current terminal dispatch | `rg -n "_post_review_summary " scripts/development-workflow/pr-review-loop.sh` | Five call sites exist: one early no-platform skip plus four post-platform terminal paths (`clean`, `needs_fixes`, `needs_rerun`, and `escalate`). The hook should feed the four post-platform paths; the early no-platform skip remains unchanged. |
| Current aggregate finalization | `rg -n "sync_reviewer_failed_label|print_kv RESULT|case \\"\\$aggregate_result\\"" scripts/development-workflow/pr-review-loop.sh` | Thread checks, compare metrics, and reviewer-failed label reconciliation settle the platform-derived result before summary dispatch. The extension can run once after that settlement and before final result output/summary dispatch without participating in aggregation. |
| Existing test seams | `rg -n "HARNESS_MODE=1 source\\|_post_summary_source" scripts/development-workflow/tests/test-pr-review-loop.sh` | The harness loads pre-main helper functions directly and evaluates `_post_review_summary()` separately, supporting deterministic hook guards and rendered-comment assertions. |
| Live downstream reference | `gh api repos/mome-cl/mome-platform/contents/scripts/development-workflow/pr-review-loop.sh?ref=develop` and the corresponding `run-advisory-checks.sh` query | Downstream `develop` currently has reviewer-loop blob `574455792fc628817641cdd37b18a630b41fc86e` and advisory script blob `23cde513ce44cdbf4b8a5b8689c11596d8d57e90`. It uses trailing summary parameter 14 and runs the local script before terminal summary dispatch; its concrete Knip and migration checks remain project-specific and are not copied into the template. |
| Sync coverage | `rg -n "path: scripts/development-workflow/" sync-manifest.yaml` | The manifest already syncs the full workflow-script directory, so the no-op entry point needs no manifest entry or sync-engine change. |
| Documentation surfaces | `rg -n "Automated Reviewer Loop Summary\\|Advisory findings" docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md scripts/development-workflow/README.md` | Protocol 93 owns summary/advisory operator semantics; the script README owns helper usage. Both need the new project-hook contract and its distinction from platform advisory dispositions. |
| Design assets | Issue body plus `find docs/specs/developments/20260723115259_1279-advisory-checks-hook -maxdepth 2 -type d -name assets` | No design assets or UI surface exist; no fidelity step applies. |
| Template fit | `.ai-dev-workflow.yaml` → `template.is_template` | Passes. This is framework-agnostic workflow tooling intended for downstream customization. |

---

## Technical Contract

### Extension Runner

Add a small helper in
`scripts/development-workflow/pr-review-loop.sh` with the stable internal
interface:

`run_project_advisory_checks <pr_number> [script_path]`

- The default `script_path` is
  `$SCRIPT_DIR/run-advisory-checks.sh`; the optional argument exists so the
  shell harness can test missing and failing extensions without moving the
  shipped file.
- An empty pull-request identifier or a path that is not a regular file returns
  success with empty stdout before any subprocess is started. The explicit
  argument/file guards enforce the no-inference and missing-extension
  guarantees. Maps to BR-3, BR-4, AC4, and AC5.
- When both guards pass, execute the extension with exactly the PR identifier as
  its first positional argument. Capture stdout even when the subprocess exits
  non-zero; discard its stderr from the PR summary and always return zero from
  the wrapper. The wrapper's unconditional success return is the mechanism that
  contains optional-extension failures. Maps to BR-7, AC6, and AC7.
- Empty stdout remains empty. Non-empty stdout is passed through as a complete
  Markdown-ready section. The extension contract requires a distinct heading,
  with `**Advisory checks** _(informational — never blocks merge)_` as the
  documented example. Keeping the extension output intact preserves
  compatibility with the live downstream implementation while the loop owns
  only placement. Maps to BR-5, AC1, and AC3.
- Preserve multiline stdout byte-for-byte except for normal command-substitution
  removal of trailing newlines. Do not parse advisory text into finding counts,
  labels, history fields, or result enums.

### Supplied No-Op Entry Point

Add executable
`scripts/development-workflow/run-advisory-checks.sh`.

- Document usage as
  `run-advisory-checks.sh <pr-number>` and stdout as a complete
  Markdown-ready advisory section.
- Leave the supplied implementation intentionally empty and successful. It must
  emit no heading, placeholder, or diagnostic on stdout.
- Include comments showing where a downstream project may run its own
  diff-scoped tools and the expected section-heading shape, while avoiding
  MOME-specific Knip, Supabase, package manager, or migration logic.
- Keep the entry point project-customizable; the framework defines only the
  invocation and output contract.

### Invocation and Summary Placement

- Invoke `run_project_advisory_checks` exactly once after platform aggregation,
  review-thread checks, compare-mode settlement, and reviewer-failed label
  reconciliation, but before the final `RESULT` record and terminal summary
  dispatch. The single call outside the terminal `case` enforces at-most-once
  execution for a reviewer-loop invocation. Maps to BR-2, AC1, AC6, and AC7.
- Store the returned fragment in `advisory_checks_section` and pass it as
  trailing argument 14 to each post-platform terminal summary path:
  `clean`, `needs_fixes`, `needs_rerun`, and `escalate`.
- Keep the no-platform/release early exits unchanged. They do not reach the
  project hook because no platform-review phase produced a normal terminal
  summary path.
- Render `${advisory_checks_section}` after `${phase_section}`,
  `${compare_section}`, and existing `${advisory_section}`, and before
  `${regression_label_section}`. Maps to BR-6 and AC2.
- Never assign advisory output to `aggregate_result`, `aggregate_reason`,
  blocker/suggestion counts, readiness labels, or the shell exit status. The
  existing terminal `case` remains the sole result/exit mechanism. Maps to BR-7
  through BR-9 and AC6 through AC7.

---

## Workflow Decision-Gate Consistency Matrix

| PR context | Extension state/output | Platform-derived outcome | Allowed outcome | Required next action | Mirror surfaces / example |
| --- | --- | --- | --- | --- | --- |
| Valid PR | Available, exits zero, non-empty multiline stdout | `clean` | `clean` | Append one project advisory section, then use the existing clean exit | Loop helper, summary renderer, tests; dead-export notes |
| Valid PR | Available, exits zero, empty stdout (including default stub) | Any post-platform terminal result | Unchanged | Omit the section and dispatch the existing summary/result | Stub, README, empty-output test |
| Valid PR | Script path missing | Any post-platform terminal result | Unchanged | Skip silently; do not create an empty section | Helper file guard and missing-extension test |
| Empty PR identifier | Available or missing | Existing harness/non-PR state | Unchanged | Do not invoke a subprocess or infer a PR | Helper argument guard and marker-file test |
| Valid PR | Exits non-zero with stdout | `clean` | `clean` | Preserve stdout as informational and return the existing clean exit | Failure-containment test and Protocol 93 example |
| Valid PR | Exits non-zero without stdout | `clean` | `clean` | Omit section and return the existing clean exit | Failure-containment test |
| Valid PR | Non-empty stdout | `needs_fixes`, `needs_rerun`, or `escalate` | Existing blocking/rerun/escalated result | Show the advisory section without changing counts, reason, or exit status | Terminal dispatch tests |
| No configured platform or release guard | Extension is irrelevant | Existing early `skipped` result | `skipped` | Preserve current early-exit behavior; do not run the project extension | Existing early guards; not an advisory-summary path |

---

## Layer-by-Layer Changes

### Workflow Script Layer

- [ ] Update `scripts/development-workflow/pr-review-loop.sh` with the helper,
  single post-aggregation invocation, trailing summary parameter, four
  post-platform call-site updates, and required output ordering. Maps to AC1
  through AC7 and AC9.
- [ ] Add executable
  `scripts/development-workflow/run-advisory-checks.sh` as the minimal,
  framework-agnostic no-op customization point. Maps to AC3 and AC8.

### Test Layer

- [ ] Extend
  `scripts/development-workflow/tests/test-pr-review-loop.sh` with direct helper
  tests for empty PR context, missing script, empty output, multiline output,
  non-zero-with-output, and at-most-once execution.
- [ ] Add rendered-summary assertions that project advisory content follows
  phase/compare/platform-advisory content and precedes the regression warning.
- [ ] Add terminal-path assertions proving the same platform-derived
  `clean`, `needs_fixes`, `needs_rerun`, and `escalate` results/counts/exits are
  preserved with and without advisory output.
- [ ] Test the shipped no-op entry point directly for exit zero and empty stdout.

### Documentation Layer

- [ ] Update `scripts/development-workflow/README.md` with the extension
  location, invocation contract, Markdown-section stdout format, no-op default,
  and a small framework-neutral customization example.
- [ ] Update
  `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
  to explain when project advisory checks run, where they appear, and why they
  never change reviewer-loop or readiness decisions. Explicitly distinguish
  project advisory checks from platform `ADVISORY_LABELS`: the existing
  mandatory platform-advisory disposition flow does not make these
  project-provided informational notes blocking.
- [ ] Update
  `docs/testing/workflow/1279-advisory-checks-hook.smoke-test.md` during
  implementation if the final helper/header names differ from this plan.
- [ ] Add the implementation PR's entry under `[Unreleased]` in
  `CHANGELOG.md`; do not modify the changelog in this plan PR.

### Database / API / UI / Infrastructure

- [ ] None. The feature introduces no persistent data, network API, interface,
  environment variable, workflow configuration key, or UI.
- [ ] `sync-manifest.yaml` needs no edit because its recursive
  `scripts/development-workflow/` entry already distributes the new stub.

---

## Testing Strategy

**Test types**: Shell unit/integration harness, rendered-comment regression
tests, smoke verification, ShellCheck, workflow shell guard, and markdown lint.

**Key scenarios to test**:

1. Default stub emits nothing and does not change a clean summary. Maps to AC3.
2. Empty PR context does not execute a marker-writing extension. Maps to AC5.
3. Missing extension path exits cleanly with no summary fragment. Maps to AC4.
4. Non-empty multiline output renders once under the project advisory heading
   in the required position. Maps to AC1, AC2, and AC9.
5. Non-zero extension output is retained, while an empty non-zero result stays
   silent. Maps to AC6.
6. Clean remains clean, and needs-fixes/rerun/escalate results retain their
   existing counts, reasons, and exit codes. Maps to AC6, AC7, and AC9.
7. A counter fixture proves the helper is invoked at most once per normal
   reviewer-loop execution. Maps to BR-2.
8. README and Protocol 93 describe the customizable Markdown-section stdout
   contract and advisory-only semantics. Maps to AC8.

**Smoke test runbook**:
`docs/testing/workflow/1279-advisory-checks-hook.smoke-test.md`

### Parser-Risk Classification

Not applicable. The implementation renders opaque stdout as Markdown and does
not add a parser, scanner, regex rule engine, or structured-text classifier.
Tests still cover empty and multiline boundaries because they are part of the
shell extension contract.

### Concurrent-Event-Source Classification

Not applicable. The extension runs synchronously once in the existing reviewer
process and adds no listener, timer callback, async queue, or shared mutable
state across execution contexts.

### Cross-Cutting Checklist Classification

Not applicable. The feature adds an optional output hook, not a new safety,
quality, or compliance checklist that every implementation must satisfy.

### Commands

- `bash scripts/development-workflow/tests/test-pr-review-loop.sh`
- `bash scripts/development-workflow/run-advisory-checks.sh 123`
- `shellcheck scripts/development-workflow/pr-review-loop.sh scripts/development-workflow/run-advisory-checks.sh scripts/development-workflow/tests/test-pr-review-loop.sh`
- `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
- `npx markdownlint-cli2 "docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md" "docs/testing/workflow/1279-advisory-checks-hook.smoke-test.md" "scripts/development-workflow/README.md" "CHANGELOG.md"`

---

## Seed Data

No application seed data is required. The shell harness should create temporary
executable fixtures for successful, empty, multiline, marker-writing, and
non-zero extensions, plus a temporary comment-body capture file. Cleanup traps
must remove every fixture.

---

## Documentation Updates

- [ ] `scripts/development-workflow/README.md` - document the project extension
  contract and customization example.
- [ ] `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
  - document lifecycle, summary placement, and advisory-only semantics.
- [ ] `docs/testing/workflow/1279-advisory-checks-hook.smoke-test.md` - keep
  implementation names and assertions synchronized.
- [ ] `CHANGELOG.md` - add the implementation entry under `[Unreleased]`.
- [ ] `AGENTS.md`, project architecture docs, agent files, skill files, and
  `sync-manifest.yaml` need no changes because the extension does not alter
  orchestration responsibilities and the script directory is already synced.

---

## Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Optional script failure changes the reviewer exit | Medium | High | Wrapper always returns zero; terminal result/exit stays in the existing aggregate `case`; test non-zero scripts across outcomes. |
| Hook output obscures platform findings or regression warning | Medium | Medium | Require a distinct heading and use a fixed render slot after platform detail and before regression annotation; assert marker order. |
| Hook runs twice on one terminal path | Low | Medium | Invoke once outside the terminal dispatch `case`; use a counter fixture. |
| Empty/unconfigured projects gain summary noise | Medium | Medium | Default stub and empty-output wrapper return empty; renderer omits empty fragments. |
| Template imports downstream-specific tooling | Low | High | Ship only the generic entry point; leave Knip, package manager, and migration checks downstream-owned. |
| Maintainers confuse project notes with platform advisory dispositions | Medium | Medium | Document the distinction in Protocol 93 and use a separate heading. |

---

## Implementation Order

1. Add `run_project_advisory_checks` before the harness-mode return in
   `pr-review-loop.sh`, using explicit PR/file guards and an unconditional
   success return. Verify direct helper tests for empty, missing, empty-output,
   multiline, and non-zero scripts.
2. Add the executable no-op `run-advisory-checks.sh` with the complete
   Markdown-section stdout contract. Verify a direct invocation exits zero with
   empty stdout.
3. Invoke the helper once after aggregate settlement and before final result
   reporting. Pass the returned fragment as parameter 14 to all four
   post-platform summary dispatches.
4. Update `_post_review_summary()` to render the fragment after existing
   phase/compare/platform-advisory detail and before the regression annotation.
   Verify marker ordering in the captured comment body.
5. Add terminal-result integrity tests for clean, needs-fixes, needs-rerun, and
   escalate paths, plus the one-invocation counter test.
6. Update the script README and Protocol 93 with the exact customization and
   advisory-only contract. Reconcile the smoke runbook with final names.
7. Run the focused shell tests, ShellCheck, workflow shell guard, and markdown
   lint commands from **Testing Strategy**.
8. Add this literal entry under `[Unreleased]`:

   `- **Add project advisory checks hook** (#1279): Let downstream projects append diff-scoped informational checks to reviewer summaries without changing reviewer results or readiness.`

9. Run the implementation protocol's pre-submission review, reviewer loop, CI,
   alignment/readiness checks, and ground-truth completion self-check.

---

## Cross-Section Consistency Self-Check

- The helper is consistently named `run_project_advisory_checks`.
- The shipped entry point is consistently
  `scripts/development-workflow/run-advisory-checks.sh`.
- The extension receives exactly one positional PR identifier and emits a
  complete Markdown-ready advisory section on stdout.
- The extension owns its distinct heading; the reviewer loop owns only the
  section's placement.
- The summary fragment is consistently trailing parameter 14.
- The fragment order is consistently phase, compare, platform advisory,
  project advisory, then regression annotation.
- The hook is consistently advisory-only and outside every aggregate result,
  count, label, readiness, and exit decision.

---

## Document Quality Gate

- Spec coverage: Checked - AC1 through AC9 map to technical steps, automated
  scenarios, and smoke assertions.
- Implementation-order consistency: Checked - helper, script, parameter,
  heading, render order, tests, and documentation names agree throughout.
- Verification support: Checked - current function/call surfaces, test seams,
  sync coverage, and downstream reference behavior cite live commands.
- Behavioral guarantees: Checked - explicit input/file guards prevent inferred
  targets; a single pre-dispatch call enforces at-most-once execution; the
  wrapper's unconditional zero return and untouched aggregate `case` preserve
  result/exit behavior.
- Complex workflow decision-gate matrix: Checked - valid/missing input,
  available/missing/failing extensions, empty/non-empty output, clean/blocking
  outcomes, early exits, actions, mirrors, and examples are covered.
- Parser/API/concurrency checklist: Checked - the shell extension contract and
  multiline boundaries are explicit; parser, filter-schema, snapshot, and
  concurrent-event classifications are not applicable with rationale.
- CHANGELOG literal format: Checked - the implementation order uses the required
  bold-title issue format.
- Stage purity: Checked - the plan PR contains only this plan and its plan-stage
  smoke runbook.

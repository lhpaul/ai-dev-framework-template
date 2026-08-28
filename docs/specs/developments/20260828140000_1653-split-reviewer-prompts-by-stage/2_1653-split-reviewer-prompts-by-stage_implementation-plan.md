# Split Local Reviewer Prompts by Workflow Stage — Implementation Plan

**Spec**: None — Refactor item. Source brief:
[issue #1653](https://github.com/lhpaul/ai-dev-framework-template/issues/1653)
(epic [#1647](https://github.com/lhpaul/ai-dev-framework-template/issues/1647))
**Smoke test runbook**:
[1653-split-reviewer-prompts-by-stage.smoke-test.md](../../../testing/workflow/1653-split-reviewer-prompts-by-stage.smoke-test.md)

---

## Summary

**Approach**: `REVIEW.md` already carries three stage checklists — Spec, Plan
and Code — under a shared Core Rules section. The local reviewer does not use
that structure. The bundled preset's prompt says only *"Review this PR change
using REVIEW.md"*, so on every PR the reviewer receives a 414-line contract
containing three checklists and has to infer, unaided, which one governs. There
is no fourth checklist for changes to the workflow's own policy surface —
`REVIEW.md`, the protocols, the best-practices set, `.ai-dev-workflow.yaml`,
`scripts/development-workflow/**` — which is what most of this epic's own pull
requests change.

This plan resolves a **review stage** from the head branch, derives an
**additional checklist** from the changed files, names the selected sections in
the prompt, and emits the selection as evidence. It adds the missing Workflow
Policy checklist to `REVIEW.md`.

The whole design rests on one property, and every other decision follows from
it: **checklist selection is additive and monotone**. `REVIEW.md` as a whole and
its Core Rules always apply; naming a stage section directs attention to it and
removes nothing. The file-derived class can only *add* a checklist to the one
the branch implied, never replace or drop it. An unrecognised branch selects
nothing and produces today's prompt byte-for-byte. Every degradation path —
unknown branch, unreadable diff, empty changed-file list — therefore lands on
behavior that is at worst identical to today's and never narrower.

**Estimated complexity**: M

**Rationale**: The code is small — one resolver, three new bundle fields,
three new evidence keys, one prompt sentence — and concentrated in two scripts that
this epic already touches. What makes it more than small is that it changes what
a reviewer is *told to look for*, and the failure mode is silent: a stage
selection that narrows attention produces a confident `clean` on a PR whose
defect lives in a section the prompt did not name. That failure leaves no trace
in any log, so the monotonicity property has to be enforced by construction and
demonstrated by planted proof rather than asserted.

**Dependencies**: None. This item touches `local-ai-reviewer.sh` and
`local-codex-review-command.sh`; #1648, #1649, #1651 and #1652 all touch
`pr-review-loop.sh`. The only shared file is `REVIEW.md`, and this item appends
a section rather than editing existing ones. See **Risks** for the deliberate
near-duplication with #1652's normative-path list.

---

## Verification Log

| Check | Command / query | Result |
| --- | --- | --- |
| Repo revision | `git rev-parse --short origin/develop-internal-reviewer-effectiveness` | `3901d6e1` — after #1660, #1661, #1662 and #1663 merged. Every line-number reference below was re-read at this revision |
| `REVIEW.md` already has stage checklists | `awk '/^## /{print NR": "$0}' REVIEW.md` | Five level-2 sections: `Core Rules` (14), `Spec Review Checklist` (64), `Plan Review Checklist` (113), `Code Review Checklist` (198), `Tool Guidance` (379). **Three** stage checklists exist; there is no workflow-policy checklist |
| The prompt is stage-agnostic today | `sed -n '15p' scripts/development-workflow/local-codex-review-command.sh` | The default prompt names `REVIEW.md` once, as a whole, with no section reference. It is the only prompt the bundled preset builds |
| The context bundle carries no stage | `sed -n '339,366p' scripts/development-workflow/local-ai-reviewer.sh` | `local_ai_reviewer_context.v1` has thirteen fields; none describes the branch type or the kind of change. `head_branch` is present, so the raw input for a resolver already reaches the command — nothing derived from it does |
| The loop forwards unknown keys unchanged | `sed -n '754,772p' scripts/development-workflow/pr-review-loop.sh` | `emit_prefixed_platform_output` re-emits **every** key it reads as `PLATFORM_<n>_<KEY>`, skipping only `RESULT`, `PR_NUMBER`, `BRANCH`, `FIX_AGENT` and `PLATFORM`. New evidence keys surface in the loop summary with no change to `pr-review-loop.sh` |
| A branch→stage map already exists, and is narrower | `sed -n '114,120p' scripts/development-workflow/check-documentation-stage-alignment.sh` | `stage_for_head` maps `spec/*`→`spec`, `implementation-plan/*`→`plan`, everything else→`not_applicable`. It covers two of the four stages this item needs and is used for a different question — whether the *changed files* match the stage — so it is a naming precedent, not reusable logic |
| The authoritative branch table | `sed -n '10,16p' docs/workflow/development-workflow/protocols/03-implement-development-protocol.md` | Four implementation paths: `feature/`, `refactor/`, `fix/`, `hotfix/`. With `spec/` and `implementation-plan/` from protocols 01 and 02, the workflow defines **six** branch prefixes |
| Those prefixes are the ones actually used | `grep -rhoE '\b(spec\|implementation-plan\|feature\|fix\|refactor\|hotfix)/[a-z0-9<{-]+' docs/workflow/development-workflow/protocols/*.md \| sed -E 's#/.*#/#' \| sort \| uniq -c` | `feature/` 31, `spec/` 17, `fix/` 7, `refactor/` 5, `implementation-plan/` 2. Every prefix in the table appears in the protocols; no seventh prefix appears |
| The preset prompt is overridable | `sed -n '13,18p' scripts/development-workflow/local-codex-review-command.sh` | `LOCAL_CODEX_REVIEWER_PROMPT` short-circuits the built prompt entirely. A caller that sets it receives the stage in the environment and the bundle but not in the prompt text — see **Risks** |

**What this log does not establish.** It does not show that a stage-specific
prompt finds more defects than a generic one; no such measurement exists in this
repository yet, and producing it is #1651's and #1657's work, not this item's.
What it establishes is narrower and sufficient: the structure this item selects
from already exists, the reviewer is currently given no way to use it, and the
plumbing to carry and report a selection is already in place.

---

## Cross-Cutting Operational Assumption Check

### Applicable

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Approved base branch for this item | `develop-internal-reviewer-effectiveness` | `integration-branch:internal-reviewer-effectiveness` label on #1653; Protocol 91 § Integration-branch base override | 2026-08-28, repo SHA `3901d6e1` | Epic #1647 items; #1660, #1661, #1662 and #1663 are merged into this base, and no epic PR is open against it | `Verified` |
| The set of branch prefixes the workflow defines | Six: `spec/`, `implementation-plan/`, `feature/`, `refactor/`, `fix/`, `hotfix/` | Protocol 03 § branch table; protocols 01 and 02 | 2026-08-28, repo SHA `3901d6e1` | `docs/workflow/development-workflow/protocols/*.md` | `Verified` |
| Ownership of `REVIEW.md` | Repository-owned, not template-owned | No `TEMPLATE-OWNED` marker in `REVIEW.md` | 2026-08-28, repo SHA `3901d6e1` | `REVIEW.md` | `Verified` — the new section can be added directly |

### Not applicable

**Result**: `Not applicable` — no database, no runtime service, no user-facing
surface, no scheduled job. The change is confined to two review scripts, one
contract document and two workflow documents.

---

## Layer-by-Layer Changes

### Database / Data Layer

Not applicable.

### Backend / API

Not applicable — this repository ships workflow tooling, not a service.

### Shared Packages / Libraries

- [ ] **Add the missing fourth checklist to `REVIEW.md`.** A new level-2
      section, `## Workflow Policy Review Checklist`, placed after
      `## Code Review Checklist` and before `## Tool Guidance`. It governs
      changes to the documents and scripts that define how the workflow itself
      behaves, and it asks the questions the Code checklist does not:

      1. Does every stated count match what the document actually contains, by
         extraction rather than by reading?
      2. Does every gate name its inputs, its decision for each combination of
         them, and its behavior when an input is missing or malformed?
      3. Does a rule asserted as fail-closed have a path that reaches the
         permissive branch — an allow-list stated as a deny-list, an empty set
         treated as satisfied, an absent value treated as a match?
      4. Does every new or modified check carry a planted-violation proof at a
         concrete file and line, and can the plant actually change the check's
         answer? A proof whose plant is masked by an earlier rule is not a
         proof.
      5. Does the change alter a `key=value` contract, a JSON schema version, or
         a stdout surface another script parses, and if so is every consumer
         named?
      6. Do the protocol document, the integration document and the `--help`
         output describe the same behavior as the code?

      Each item is phrased as a question with a verifiable answer, matching the
      existing checklists' style. The section is **additive**: Core Rules,
      including the Verification Discipline and Severity rules, continue to
      apply to workflow-policy changes exactly as they do to code.

- [ ] **Add a source-only harness guard to `local-ai-reviewer.sh`.** The script
      has none today: line 145 is `if [ "$#" -lt 3 ]; then usage; exit 2; fi`,
      so sourcing it exits before any function is callable, and the resolvers
      below cannot be unit-tested at all. `pr-review-loop.sh` already solved
      this at its lines 12-19, and the same guard is copied verbatim rather
      than invented:

      ```bash
      _HARNESS_MODE_EFFECTIVE=0
      if [ "${HARNESS_MODE:-0}" -eq 1 ] && [ "${BASH_SOURCE[0]}" != "$0" ]; then
        _HARNESS_MODE_EFFECTIVE=1
      fi
      ```

      Both conditions are required, and the second is the safety one:
      `HARNESS_MODE=1` in the environment of a **direct** run must not skip
      argument validation, or an exported variable in someone's shell would
      turn a real review into a no-op. The guard wraps the argument block and
      everything after it; the three resolver functions are defined **above**
      it, beside the existing helpers, so a sourced script defines them and
      stops.

      This is a structural change to a script this item otherwise only adds to,
      and it is the one part of the plan not implied by the brief. It is here
      because the alternative — testing eleven branch inputs by running the
      whole reviewer eleven times through its mock harness — buys nothing and
      costs a slow suite. Scenario 0 tests the guard itself in both directions.

- [ ] **Resolve the review stage in `local-ai-reviewer.sh`.** Three functions
      and one merge step, placed with the other pre-invocation helpers, above
      the harness guard.

      1. `reviewer_stage_for_branch <head_branch>` — the branch tier. Six
         recognised prefixes mapping to three stages, and `default` for
         everything else:

         | Head branch | Stage | Checklist named |
         | --- | --- | --- |
         | `spec/*` | `spec` | Spec Review Checklist |
         | `implementation-plan/*` | `plan` | Plan Review Checklist |
         | `feature/*`, `refactor/*`, `fix/*`, `hotfix/*` | `implementation` | Code Review Checklist |
         | anything else, or an empty branch name | `default` | none |

         The mapping is a `case` over the literal prefixes, not a regular
         expression, so a branch named `specification/foo` does not match
         `spec/*` by accident.

      2. `reviewer_changed_files_touch_workflow_policy` — the file tier. It
         reads **newline-delimited paths on stdin**, one per line, and returns
         success when **any** of them matches the workflow-policy set.

         **The input is not the JSON array.** `changed_files_json` is a compact
         JSON array — the value `jq -R -s -c` produces and the bundle embeds —
         so a path never appears as a bare string in it. The caller decodes it
         with `jq -r '.[]?'` before piping; the predicate itself never parses
         JSON. Two reasons for the split: the predicate stays testable from a
         heredoc without `jq`, and the decode happens exactly once, at the one
         call site, rather than being re-derived by every future caller.
         Scenario 5a exercises the decode through the caller with a real
         `changed_files_json` value, because a predicate that is correct on
         newlines and a caller that feeds it JSON is a defect no test of either
         one alone can see. The matched set:

         | Pattern | Why it is workflow policy |
         | --- | --- |
         | `REVIEW.md` | the review contract itself |
         | `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `LLM_RULES.md` | the agent instruction surfaces |
         | `.ai-dev-workflow.yaml` | the workflow's configuration contract |
         | `docs/workflow/*` | the protocols |
         | `docs/best-practices/*` | the implementer-facing rules the protocols cite |
         | `scripts/development-workflow/*` | the scripts that enforce all of the above |

         Six rows, written as **nine `case` entries** — six literal filenames
         and three directory prefixes. `.github/workflows/*` is deliberately **excluded**: CI
         configuration is ordinary code, reviewed by the Code checklist, and
         including it would pull every dependency bump into the policy stage.

      3. The merge, which is where the monotonicity property lives. The
         checklist set is the branch-implied checklist **union** the
         file-derived one:

         | Branch stage | Any policy file changed? | Stage reported | Checklists named |
         | --- | --- | --- | --- |
         | `spec` | no | `spec` | Spec |
         | `spec` | yes | `spec` | Spec, Workflow Policy |
         | `plan` | no | `plan` | Plan |
         | `plan` | yes | `plan` | Plan, Workflow Policy |
         | `implementation` | no | `implementation` | Code |
         | `implementation` | yes | `implementation` | Code, Workflow Policy |
         | `default` | no | `default` | none |
         | `default` | yes | `default` | none |

         Eight rows, every combination of the two inputs, no row omitted. Two
         of them carry the load and both are counter-intuitive enough to state
         outright:

         - **`default` + policy files → still nothing.** The brief's third
           scope bullet requires unknown branch types to keep their current
           behavior, and the current behavior is a prompt that names no
           section. Adding a checklist there would change it. `default` is the
           one stage whose prompt must stay byte-identical to today's, so the
           file tier is not consulted for it. This is the only asymmetry in the
           table and it is required by the brief.
         - **The file tier never subtracts.** An `implementation` branch whose
           changed files are *entirely* workflow policy still gets the Code
           checklist, plus Workflow Policy. The alternative — letting the files
           override the branch — was rejected: it makes the two tiers
           disagreeable, forces a precedence rule, and its only benefit is a
           shorter prompt. Union has no precedence question to get wrong.

      4. `review_stage_source` records which tiers contributed: `branch` when
         only the branch matched, `branch+files` when the file tier added the
         policy checklist, and `none` for `default`. Three values, one per
         reachable state of the table above.

- [ ] **Carry the selection in the context bundle.** Three fields added to the
      `jq -n` object, and the schema version left at
      `local_ai_reviewer_context.v1`:

      ```text
      review_stage:            "spec" | "plan" | "implementation" | "default"
      review_stage_source:     "branch" | "branch+files" | "none"
      review_checklists:       ["Spec Review Checklist", ...]   # ordered, may be empty
      ```

      `review_checklists` holds the **exact level-2 heading text** from
      `REVIEW.md`, not a line number and not a slug. Headings are stable and
      greppable; line numbers move whenever the contract is edited, which this
      very item does.

      **Why the version stays at `.v1`.** Bumping it would be the more
      conventional choice, and it is wrong here. The only two references to
      `local_ai_reviewer_context.v1` in the repository are the producer at
      `local-ai-reviewer.sh:352` and a prose description in the integration
      document; nothing validates it, and a custom `LOCAL_AI_REVIEWER_COMMAND`
      that *does* check it would break on a bump while working fine with three
      added fields it ignores. The change is purely additive: every v1 field
      keeps its name, type and meaning. Scenario 12 asserts exactly that, field
      by field, so the claim is tested rather than promised.

- [ ] **Emit the selection as evidence.** Three `print_kv` calls beside the
      existing `BASE_BRANCH` / `REVIEWED_HEAD` / `GRAPH_CONTEXT` block:
      `REVIEW_STAGE`, `REVIEW_STAGE_SOURCE` and `REVIEW_CHECKLISTS` — the last
      as a comma-separated list of the same heading strings, chosen over JSON
      because the `key=value` contract is line-oriented and every consumer of it
      splits on the first `=` only.

      No change is needed in `pr-review-loop.sh`: `emit_prefixed_platform_output`
      forwards any key it does not explicitly skip, so these arrive in the loop
      summary as `PLATFORM_<n>_REVIEW_STAGE` and siblings. Scenario 13 asserts
      that, because "no change needed elsewhere" is exactly the kind of claim
      that is true until it is not.

      The same three values are added to the evidence JSON written by
      `write_evidence_file`, under a `review_stage` object, so an evidence file
      answers *which checklist produced this verdict* without re-deriving it
      from the branch name.

- [ ] **Name the checklists in the bundled preset's prompt.** In
      `local-codex-review-command.sh`, one sentence inserted into the default
      prompt when `REVIEW_CHECKLISTS` is non-empty:

      > This change is at the `<stage>` stage. Apply `REVIEW.md` in full,
      > including its Core Rules, and give particular weight to its
      > `<checklist>` section(s).

      **"In full, including its Core Rules" is load-bearing, not padding.** It
      is what makes the selection additive rather than substitutive, and it is
      the single sentence proof P4 removes. When `REVIEW_CHECKLISTS` is empty —
      stage `default` — no sentence is inserted and the prompt is the current
      string, unchanged character for character.

      The preset reads `REVIEW_STAGE` and `REVIEW_CHECKLISTS` from the
      environment, which `local-ai-reviewer.sh` exports alongside the existing
      `CONTEXT_BUNDLE_PATH` / `PR_NUMBER` / `OWNER` / `REPO` / `BASE_BRANCH` /
      `HEAD_BRANCH` / `REVIEWED_HEAD` set.

### Frontend / UI

Not applicable.

### Infrastructure / Configuration

- [ ] Document `REVIEW_STAGE`, `REVIEW_STAGE_SOURCE` and `REVIEW_CHECKLISTS` in
      the `local-ai-reviewer.sh` `--help` usage block, in the same environment
      table that already documents `LOCAL_AI_REVIEWER_*`.

---

## Testing Strategy

**Test types**: Unit (shell harness), plus the smoke test runbook.

**Key scenarios to test**:

0. The harness guard, in both directions. Sourcing the script with
   `HARNESS_MODE=1` defines `reviewer_stage_for_branch`,
   `reviewer_changed_files_touch_workflow_policy` and
   `reviewer_resolve_review_stage`, and exits nothing. Executing it **directly**
   with `HARNESS_MODE=1` in the environment and no arguments still prints usage
   and exits 2. The second half is the safety property: a guard that keyed on
   the variable alone would let a stray export disable argument validation on a
   real run.
1. `reviewer_stage_for_branch` returns the mapped stage for each of the six
   recognised prefixes, one case per prefix.
2. It returns `default` for five controls: an empty branch name, `main`,
   `develop`, `develop-internal-reviewer-effectiveness`, and
   `specification/foo` — the last because a prefix `case` must not match a
   longer word that merely starts with it.
3. `reviewer_changed_files_touch_workflow_policy` returns success for one path
   per `case` entry — **nine** cases, six literal filenames and three directory
   prefixes — and failure for four controls:
   `docs/specs/developments/x/1_x_specs.md`, `docs/project/1-business-domain.md`,
   `.github/workflows/ci.yml` and `src/app/main.ts`.
4. It returns success when **one** path of many matches, and failure when none
   does. The predicate is `any`, not `all`.
5. It returns failure for an **empty** changed-file list, so an unreadable or
   empty diff degrades to the branch-implied checklist rather than adding one.
5a. The **decode** is exercised through `reviewer_resolve_review_stage` with a
    real `changed_files_json` value — the compact JSON array `jq -R -s -c`
    produces, such as `["REVIEW.md","src/app/main.ts"]` — and with the two
    degenerate values `[]` and `""`. The first must add the Workflow Policy
    checklist; the other two must not. A predicate that is correct on
    newline-delimited input and a caller that hands it the raw array is a
    defect neither a predicate test nor a merge test can see on its own, and
    the raw array matches no `case` arm, so the checklist would simply never be
    added.
6. The merge produces each of the eight rows of the decision table, one case
   per row, asserting stage, source and checklist list together — not stage
   alone, because the stage is the value least able to reveal a wrong merge.
7. The `default` rows produce an **empty** checklist list under both file
   conditions. This is the asymmetry the brief requires and the one a later
   editor is most likely to "fix".
8. `implementation` with policy files names **both** Code and Workflow Policy,
   in that order — branch-implied first. Order is asserted because the prompt
   renders the list in order and a reader weights the first named section most.
9. Every checklist name the resolver can emit exists in `REVIEW.md` as a
   level-2 heading, tested by grepping the contract for the exact string. This
   is the scenario that fails if someone renames a section without touching the
   resolver, which is the most likely way this feature silently degrades.
10. The prompt built by the preset contains the words "in full" and "Core Rules"
    whenever it names any checklist. The monotonicity property, asserted at the
    only place it is expressible.
11. With stage `default`, the preset's prompt is **byte-identical** to the
    current default prompt string, compared against a fixture copy of it rather
    than against a regenerated one.
12. The context bundle retains all thirteen `local_ai_reviewer_context.v1`
    fields with unchanged names and types, and adds exactly three. Asserted
    field by field against an enumerated list, not by a count.
13. `emit_prefixed_platform_output` forwards `REVIEW_STAGE`,
    `REVIEW_STAGE_SOURCE` and `REVIEW_CHECKLISTS` as `PLATFORM_1_*` keys,
    exercised through the real function rather than assumed from its source.
14. The evidence JSON contains the `review_stage` object with all three values,
    and remains valid `local_ai_reviewer_evidence.v1`.
15. A `LOCAL_CODEX_REVIEWER_PROMPT` override still wins: the stage sentence is
    not appended to it. The override contract is unchanged, and a caller who set
    it before this item gets exactly what they got before.

**Files**:

- `scripts/development-workflow/tests/test-local-ai-reviewer.sh` — scenarios 1
  through 9, including 5a, and 11 through 15, as new cases in the existing
  harness.
- `scripts/development-workflow/tests/test-local-codex-review-command.sh` —
  scenarios 10, 11 and 15, the prompt-construction cases. This suite already
  exists and already declares
  `# covers: scripts/development-workflow/local-codex-review-command.sh`, so
  the preset's new behavior belongs here rather than in the reviewer suite.
- `scripts/development-workflow/tests/test-pr-review-loop.sh` — scenario 13
  only, which needs the loop's own harness to call
  `emit_prefixed_platform_output` for real.

  All three suites already declare `# covers:` headers, so no
  `select-test-suites.sh` change is needed: the naming-convention fallback is
  already disabled for each of them and each already declares the file this
  item edits.

**Smoke test runbook**:
`docs/testing/workflow/1653-split-reviewer-prompts-by-stage.smoke-test.md`

**Regression suite**: the repository's regression surface for workflow scripts
is the two shell harnesses named above; both are extended in this item.

---

## Seed Data

| Fixture | Contents | Location |
| --- | --- | --- |
| Branch fixture | The six recognised prefixes of scenario 1 and the five controls of scenario 2 | inline in `scripts/development-workflow/tests/test-local-ai-reviewer.sh` |
| Changed-file fixture | One path per workflow-policy pattern — six — the four non-matching controls of scenario 3, a mixed list for scenario 4, and the empty list of scenario 5 | inline in the same suite |
| Prompt fixture | A verbatim copy of the current default prompt string, for scenario 11's byte-comparison | inline in the same suite, as a single-quoted heredoc so no expansion occurs |
| Bundle field fixture | The thirteen `local_ai_reviewer_context.v1` field names, enumerated | inline in the same suite |

---

## Documentation Updates

- `REVIEW.md` — the new `## Workflow Policy Review Checklist` section.
- `docs/workflow/development-workflow/integrations/local-ai-reviewer.md` — the
  three new bundle fields, the three new evidence keys, the decision table, and
  the statement that a custom command may ignore the stage.
- `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`
  — the `PLATFORM_<n>_REVIEW_STAGE` keys now visible in loop summaries.
- The `--help` block of `local-ai-reviewer.sh`.

All four must describe the same behavior; scenario 9 and runbook Step 8 check
the pair that can drift silently.

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| A stage selection **narrows** what the reviewer reads | Med | **High** — a defect in an unnamed section produces a confident `clean`, and nothing in any log shows why | Selection is additive by construction: the prompt says "apply `REVIEW.md` in full, including its Core Rules" whenever it names a section, and the file tier unions rather than overrides. Scenario 10 asserts the sentence, and proof **P4** removes it and requires a Core-Rules defect to go unreported |
| A `REVIEW.md` section is renamed and the resolver keeps naming the old heading | **High** — the contract is edited often, including by this item | Med — the prompt names a section that does not exist, and the reviewer falls back to reading everything, which is today's behavior | Scenario 9 greps `REVIEW.md` for every emitted heading string, so a rename fails the suite in the same PR that makes it. Degradation is toward today's behavior, not below it |
| The workflow-policy pattern list drifts from #1652's normative-path list | Med | Low — the two lists answer different questions, but a reader seeing near-duplicates assumes one is stale | Deliberate and recorded: #1652's list answers *may this finding be cleared as cosmetic*, this one answers *which checklist applies*. They overlap but differ on purpose — `docs/specs/developments/**` and `docs/testing/workflow/**` are normative but are the *subject* of the Spec and Plan checklists, and `scripts/development-workflow/**` is shipped code yet is workflow policy. A comment in each names the other and states why they are not shared |
| A custom `LOCAL_AI_REVIEWER_COMMAND` ignores the stage entirely | **High** — it is a free-form command | Low — that command gets today's behavior | Stated in the integration document rather than mitigated. The gate cannot force a third-party command to use the stage; it can only make the stage available in the bundle and the environment, and report which stage it selected. The evidence keys make the omission visible |
| The `default` asymmetry is "fixed" by a later editor | Med | Med — unknown branch types stop behaving as they do today, silently | The asymmetry is a row in the decision table with its rationale beside it, scenario 7 asserts both `default` rows, and proof **P3** plants the "fix" and requires scenario 7 to fail |
| `REVIEW_CHECKLISTS` contains a comma or `=` and breaks the line contract | Low | Med — a malformed evidence line | The emitted values are drawn from a fixed, enumerated set of four heading strings, none of which contains a comma or an `=`. Scenario 9 pins the set against `REVIEW.md`; the constraint is stated in the integration document as a rule for anyone adding a fifth |

---

## Code Samples

The branch tier, and the merge that carries the monotonicity property:

```bash
# Branch tier. Literal prefixes, never a regex: `specification/foo` must not
# match `spec/*`.
reviewer_stage_for_branch() {
  case "${1:-}" in
    spec/*) printf 'spec\n' ;;
    implementation-plan/*) printf 'plan\n' ;;
    feature/*|refactor/*|fix/*|hotfix/*) printf 'implementation\n' ;;
    *) printf 'default\n' ;;
  esac
}

# File tier. Reads newline-delimited paths on stdin — NOT the JSON array.
# `any`, not `all`: one policy file is enough to add the checklist.
# NOTE: this list is not #1652's reviewer_loop_path_is_normative_document and
# must not be merged with it — that one decides whether a finding may be
# cleared as cosmetic, this one decides which checklist applies. The overlap is
# coincidental, not structural.
reviewer_changed_files_touch_workflow_policy() {
  local path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "$path" in
      REVIEW.md|AGENTS.md|CLAUDE.md|GEMINI.md|LLM_RULES.md|.ai-dev-workflow.yaml)
        return 0 ;;
      docs/workflow/*|docs/best-practices/*|scripts/development-workflow/*)
        return 0 ;;
    esac
  done
  return 1
}

# The merge. The file tier only ever appends, and never runs for `default`.
reviewer_resolve_review_stage() {
  # $2 is changed_files_json, the compact JSON array the bundle embeds.
  local head_branch="$1" changed_files_json="$2"
  local stage checklists source

  stage="$(reviewer_stage_for_branch "$head_branch")"
  case "$stage" in
    spec) checklists="Spec Review Checklist" ;;
    plan) checklists="Plan Review Checklist" ;;
    implementation) checklists="Code Review Checklist" ;;
    default) checklists="" ;;
  esac

  source="branch"
  if [ -z "$checklists" ]; then
    source="none"
  elif printf '%s' "$changed_files_json" \
    | jq -r '.[]?' \
    | reviewer_changed_files_touch_workflow_policy; then
    checklists="${checklists},Workflow Policy Review Checklist"
    source="branch+files"
  fi

  printf '%s\n%s\n%s\n' "$stage" "$source" "$checklists"
}
```

The prompt sentence, in `local-codex-review-command.sh`:

<!-- workflow-shell-contract: bash -->

```bash
stage_sentence=""
if [ -n "${REVIEW_CHECKLISTS:-}" ]; then
  stage_sentence="This change is at the ${REVIEW_STAGE:-unknown} stage. Apply REVIEW.md in full, including its Core Rules, and give particular weight to these sections: ${REVIEW_CHECKLISTS}. "
fi
```

`stage_sentence` is prefixed to the built prompt only, never to a
`LOCAL_CODEX_REVIEWER_PROMPT` override.

---

## Planted-Violation Proofs

`REVIEW.md` → Core Rules → Verification Discipline requires two demonstrated
runs per proof, each citing a concrete file and line. The nine proofs fall into
three groups:

| Group | Count | Proofs | What the plant reproduces |
| --- | --- | --- | --- |
| Narrowing | **4** | P1, P3, P4, P8 | attention removed from something the reviewer reads today |
| Misclassification | **4** | P2, P5, P6, P9 | the wrong checklist named, or the right one missed |
| Contract | **1** | P7 | the evidence or bundle contract broken |

| # | Violation to plant | Where | Check that must fail, then pass |
| --- | --- | --- | --- |
| P1 | Make the file tier **replace** the branch checklist instead of appending to it | a scratch copy of `reviewer_resolve_review_stage` | scenario 8 fails: an `implementation` branch touching `REVIEW.md` names only Workflow Policy, so the Code checklist is dropped on a PR that changes code. This is the narrowing failure the union exists to prevent; restoring the append passes |
| P2 | Replace the literal `case` prefixes with a substring match | a scratch copy of `reviewer_stage_for_branch` | scenario 2 fails on `specification/foo`, which resolves to `spec` and gets the Spec checklist on a branch that is not a spec branch; restoring the prefix `case` passes |
| P3 | Consult the file tier for stage `default` too | a scratch copy of the merge | scenario 7 fails: an unrecognised branch touching `REVIEW.md` now names a checklist, so its prompt is no longer today's. This is the brief's third scope bullet; restoring the `default` short-circuit passes |
| P4 | Remove "Apply `REVIEW.md` in full, including its Core Rules" from the prompt sentence | a scratch copy of the preset | scenario 10 fails. The sentence is the whole of the additive guarantee: without it the prompt names a section and nothing else, and a Severity or Verification-Discipline violation in Core Rules is outside what the reviewer was told to check; restoring it passes |
| P5 | Change the file tier from `any` to `all` | a scratch copy of the predicate | scenario 4 fails: a PR changing `REVIEW.md` **and** one source file no longer gets the Workflow Policy checklist, which is precisely the mixed change most likely to break a workflow contract; restoring `any` passes |
| P6 | Treat an empty changed-file list as matching | same scratch copy | scenario 5 fails: an unreadable or empty diff adds the policy checklist to every PR, so the signal stops distinguishing anything. Note the direction — this plant is *additive*, and it is still wrong, because a checklist named on every PR is a checklist named on none; restoring the empty-list failure passes |
| P7 | Emit `REVIEW_CHECKLISTS` as a JSON array instead of a comma-separated list | a scratch copy of the `print_kv` block | scenario 13 fails: the `key=value` contract splits on the first `=` and the array's quoting survives into the loop summary as `PLATFORM_1_REVIEW_CHECKLISTS=["Spec Review Checklist"...`, which no consumer parses; restoring the comma form passes |
| P9 | Drop the `jq -r '.[]?'` decode and pipe `changed_files_json` straight into the predicate | a scratch copy of the merge | scenario 5a fails: the compact array `["REVIEW.md","src/app/main.ts"]` arrives as one line matching no `case` arm, so the Workflow Policy checklist is never added on any PR. The predicate's own tests still pass, and so does every merge test that stubs the file tier — this is only visible where the two meet; restoring the decode passes |
| P8 | Rename `## Code Review Checklist` in `REVIEW.md` without touching the resolver | a scratch copy of the contract | scenario 9 fails, because the resolver emits a heading that no longer exists. Without this proof the feature degrades silently — the prompt names a missing section and the reviewer falls back to reading everything, which looks like success; restoring the heading passes |

Four proofs plant the **narrowing** direction, which is the one with no
observable symptom, and each is required: P1 drops a checklist through the
merge, P3 drops the `default` guarantee, P4 drops the additive sentence, and P8
drops the link between the resolver and the contract. P6 is worth reading
twice — it plants an *over*-selection and is still a defect, because the
Workflow Policy checklist named on every PR carries no information.

---

## Implementation Order

1. Add `## Workflow Policy Review Checklist` to `REVIEW.md`, after
   `## Code Review Checklist`. **Verify**: the section exists, has six numbered
   questions, and the four heading strings the resolver will emit are all
   present as level-2 headings — the grep scenario 9 will run.
1a. Add the harness guard, copied from `pr-review-loop.sh` lines 12-19, wrapping
   the argument block. **Verify**: scenario 0 — sourced defines the functions,
   direct execution with `HARNESS_MODE=1` still exits 2.
2. Add `reviewer_stage_for_branch` and
   `reviewer_changed_files_touch_workflow_policy` to `local-ai-reviewer.sh`.
   **Verify**: scenarios 1 through 5, including the `specification/foo` control
   and the empty-list case. The predicate's contract is newline-delimited stdin;
   the JSON decode belongs to step 3.
3. Add `reviewer_resolve_review_stage` and call it after `changed_files_json` is
   built and before the bundle is written. **Verify**: scenarios 5a, 6, 7 and 8 — the `jq -r '.[]?'` decode against a
   real `changed_files_json` value, all eight rows of the decision table, both
   `default` rows empty, and the Code-before-Workflow-Policy order.
4. Add the three fields to the context bundle, leaving `schema_version` at
   `local_ai_reviewer_context.v1`. **Verify**: scenario 12, field by field
   against the enumerated thirteen.
5. Add the three `print_kv` calls and the `review_stage` object in
   `write_evidence_file`. **Verify**: scenarios 13 and 14, the first through the
   real `emit_prefixed_platform_output`.
6. Export `REVIEW_STAGE` and `REVIEW_CHECKLISTS` to the command, and add the
   stage sentence to the preset. **Verify**: scenarios 10, 11 and 15 — the
   sentence's wording, the byte-identical `default` prompt, and the override.
7. Update the `--help` block, the integration document and Protocol 93.
   **Verify**: runbook Step 8 reads all four surfaces against each other.
8. Produce the nine planted-violation proofs (P1-P9) and record them in the PR
   with the command, file, line and both outcomes for each.

---

## Rollback

Revert the implementation PR. The change is additive: three bundle fields, three
evidence keys, one prompt sentence and one `REVIEW.md` section. Reverting
restores the stage-agnostic prompt for every branch type, and no other script
reads the new keys.

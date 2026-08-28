# Smoke Test: Split Local Reviewer Prompts by Workflow Stage (#1653)

**Item**: [#1653](https://github.com/lhpaul/ai-dev-framework-template/issues/1653)
**Plan**: [2_1653-split-reviewer-prompts-by-stage_implementation-plan.md](../../specs/developments/20260828140000_1653-split-reviewer-prompts-by-stage/2_1653-split-reviewer-prompts-by-stage_implementation-plan.md)

Every step is run from the repository root against the implementation branch.
Steps 1 through 5 source the reviewer with `HARNESS_MODE=1` and call the
resolvers directly; steps 6 through 9 exercise the assembled behavior.

---

## Step 0: The harness guard, in both directions

**Maps to**: the structural prerequisite for Steps 1 through 3.

<!-- workflow-shell-contract: bash -->

```bash
HARNESS_MODE=1 source scripts/development-workflow/local-ai-reviewer.sh
declare -F reviewer_stage_for_branch \
  reviewer_changed_files_touch_workflow_policy \
  reviewer_resolve_review_stage
HARNESS_MODE=1 scripts/development-workflow/local-ai-reviewer.sh; echo "exit=$?"
```

**Expected result**: the source defines all three functions and returns without
exiting; `declare -F` lists three names. The direct run still prints usage and
reports `exit=2`.

The second half is the safety property, and it is why the guard tests
`BASH_SOURCE[0] != $0` as well as the variable. A guard keyed on `HARNESS_MODE`
alone would let a stray export in someone's shell skip argument validation on a
real review. `pr-review-loop.sh` lines 12-19 already carry this exact pair; this
item copies it rather than inventing a second convention.

Before this item the script had no guard at all — line 145 validates argument
count and exits — so sourcing it was impossible and Steps 1 through 3 had no
test path.

## Step 1: The branch tier maps every recognised prefix

**Maps to**: brief scope bullet 1, the branch half.

The functions are already loaded from Step 0.

1. Call `reviewer_stage_for_branch` on the six recognised prefixes:
   `spec/x`, `implementation-plan/x`, `feature/x`, `refactor/x`, `fix/x`,
   `hotfix/x`.
2. Call it on five controls: `""` (empty), `main`, `develop`,
   `develop-internal-reviewer-effectiveness`, and `specification/foo`.

**Expected result**: `spec`, `plan`, `implementation`, `implementation`,
`implementation`, `implementation` for step 1; `default` for all five controls.

`specification/foo` is the control that matters. A prefix `case` returns
`default` for it; a substring or regex match would return `spec` and put a spec
checklist on a branch that is not a spec branch. Proof P2 plants exactly that.

## Step 2: The file tier recognises the policy surface and nothing else

**Maps to**: brief scope bullet 1, the changed-files half.

1. Call `reviewer_changed_files_touch_workflow_policy` with one path per `case`
   entry — nine: `REVIEW.md`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`,
   `LLM_RULES.md`, `.ai-dev-workflow.yaml`, `docs/workflow/x.md`,
   `docs/best-practices/x.md`, `scripts/development-workflow/x.sh`.
2. Call it with four controls: `docs/specs/developments/x/1_x_specs.md`,
   `docs/project/1-business-domain.md`, `.github/workflows/ci.yml`, and
   `src/app/main.ts`.
3. Call it with a mixed list — `REVIEW.md` and `src/app/main.ts` together.
4. Call it with an **empty** list.
5. Call `reviewer_resolve_review_stage 'feature/x' '["REVIEW.md","src/app/main.ts"]'`,
   then again with `[]` and with `""` as the second argument.

**Expected result**: all nine entries match; none of the four controls does;
step 3 matches; step 4 does **not**. Step 5's first call names both Code and
Workflow Policy; the other two name Code alone.

Step 5 is the one that catches the seam. The predicate reads newline-delimited
paths; `changed_files_json` is a compact JSON array, so the caller must decode
it with `jq -r '.[]?'` first. Hand the array straight to the predicate and it
arrives as a single line matching no `case` arm — the Workflow Policy checklist
is then never added on any PR, while the predicate's own tests and every
stubbed merge test still pass. Proof P9.

Steps 3 and 4 are the two directions the predicate can be got wrong. `all`
instead of `any` breaks step 3 — the mixed change, which is the one most likely
to break a workflow contract while also touching code. Treating the empty list
as a match breaks step 4, and that error is *additive*: it names the policy
checklist on every PR, which carries no more information than naming it on none.
Proofs P5 and P6.

`.github/workflows/ci.yml` is a deliberate control, not an oversight: CI
configuration is ordinary code and belongs to the Code checklist.

## Step 3: The merge produces all eight rows

**Maps to**: brief scope bullet 1, the combination.

Call `reviewer_resolve_review_stage` once per row and read all three outputs —
stage, source, checklists:

| Head branch | Policy file changed | Stage | Source | Checklists |
| --- | --- | --- | --- | --- |
| `spec/x` | no | `spec` | `branch` | Spec Review Checklist |
| `spec/x` | yes | `spec` | `branch+files` | Spec Review Checklist, Workflow Policy Review Checklist |
| `implementation-plan/x` | no | `plan` | `branch` | Plan Review Checklist |
| `implementation-plan/x` | yes | `plan` | `branch+files` | Plan Review Checklist, Workflow Policy Review Checklist |
| `feature/x` | no | `implementation` | `branch` | Code Review Checklist |
| `feature/x` | yes | `implementation` | `branch+files` | Code Review Checklist, Workflow Policy Review Checklist |
| `main` | no | `default` | `none` | *(empty)* |
| `main` | yes | `default` | `none` | *(empty)* |

**Expected result**: exactly as tabulated, including the order of the two
checklists in the `branch+files` rows — branch-implied first.

The last two rows are the asymmetry the brief requires: an unrecognised branch
gets today's behavior whatever its files contain. They are also the rows a later
editor is most likely to "correct" into consistency, so proof P3 plants that
correction and requires this step to fail.

The `feature/x` + yes row is the one P1 breaks: replacing instead of appending
drops the Code checklist from a PR that changes code.

## Step 4: Every emitted heading exists in the contract

**Maps to**: the "renamed section" risk.

1. Collect the four checklist strings the resolver can emit.
2. For each, `grep -Fx "## <string>" REVIEW.md`.

**Expected result**: four matches, four exit codes of 0.

This is the step that keeps the feature from degrading silently. If a section is
renamed and the resolver is not updated, the prompt names a heading that does
not exist; the reviewer then falls back to reading the whole contract, which is
today's behavior and looks like success. Nothing else in this runbook would
notice. Proof P8 plants the rename.

## Step 5: The bundle keeps its v1 contract and adds exactly three fields

**Maps to**: the schema decision.

1. Run the reviewer against a fixture PR with `LOCAL_AI_REVIEWER_COMMAND` set to
   a stub that copies `CONTEXT_BUNDLE_PATH` aside and prints a minimal clean
   result.
2. Read the copied bundle. Assert each of the thirteen
   `local_ai_reviewer_context.v1` field names is present with its original
   type: `schema_version`, `pr_number`, `owner`, `repo`, `base_branch`,
   `head_branch`, `reviewed_head`, `changed_files`, `pr_body`,
   `diff_name_status`, `diff_stat`, `review_contract`, `graph_context`.
3. Assert the three added fields: `review_stage`, `review_stage_source`,
   `review_checklists`.
4. Assert `schema_version` still reads `local_ai_reviewer_context.v1`.

**Expected result**: all thirteen present and unchanged, three added, version
unchanged.

Step 4 is the assertion the version decision rests on. The change is additive,
so a consumer that reads v1 fields keeps working; a consumer that *validates*
the version string would have broken on a bump and does not break here. Asserted
field by field rather than by counting, so an accidental rename cannot be masked
by an accidental addition.

## Step 6: The prompt names the sections and keeps the whole contract

**Maps to**: brief scope bullet 1, and the monotonicity property.

1. With `REVIEW_STAGE=plan` and
   `REVIEW_CHECKLISTS='Plan Review Checklist'` in the environment, build the
   preset's prompt without invoking the model — run the preset with a stub
   binary that prints its final argument.
2. Read the prompt.
3. Repeat with `REVIEW_CHECKLISTS` **empty**.
4. Repeat with `LOCAL_CODEX_REVIEWER_PROMPT` set to a fixed string.

**Expected result**: step 2's prompt names the stage, names
`Plan Review Checklist`, and contains both *"in full"* and *"Core Rules"*.
Step 3's prompt is **byte-identical** to the current default prompt string,
compared against a verbatim fixture copy rather than a regenerated one. Step 4's
prompt is the override, with no stage sentence prefixed.

Step 2's two required phrases are the whole additive guarantee, and they are the
only place it is expressible — everything else about this feature is selection.
Without them the prompt names one section and nothing else, and a Severity or
Verification-Discipline violation from Core Rules is outside what the reviewer
was asked to check. Proof P4 removes the phrase.

Step 3 must compare against a fixture, not against the prompt the code builds:
comparing the code's output to itself passes no matter what the string is.

## Step 7: The selection reaches the loop summary

**Maps to**: brief scope bullet 2.

1. Read the reviewer's `key=value` stdout for the run in Step 5. Confirm
   `REVIEW_STAGE`, `REVIEW_STAGE_SOURCE` and `REVIEW_CHECKLISTS`.
2. Pass that stdout through the loop's own `emit_prefixed_platform_output` with
   index 1.
3. Read the evidence JSON written with `LOCAL_AI_REVIEWER_EVIDENCE_FILE`.

**Expected result**: step 2 yields `PLATFORM_1_REVIEW_STAGE`,
`PLATFORM_1_REVIEW_STAGE_SOURCE` and `PLATFORM_1_REVIEW_CHECKLISTS` with the
same values; step 3's JSON carries a `review_stage` object with all three and
still validates as `local_ai_reviewer_evidence.v1`.

Step 2 runs the **real** function rather than reading its source. The plan
claims no change is needed in `pr-review-loop.sh`, and that claim is exactly the
kind that holds until a key collides with the skip list.

`REVIEW_CHECKLISTS` is comma-separated, not JSON. The `key=value` contract is
line-oriented and its consumers split on the first `=`; a JSON array's quoting
survives into the summary as an unparsed literal. Proof P7 plants the array.

## Step 8: All four documentation surfaces agree

**Maps to**: the documentation-drift risk.

1. Read the new `## Workflow Policy Review Checklist` in `REVIEW.md`.
2. Read the stage section of
   `docs/workflow/development-workflow/integrations/local-ai-reviewer.md`.
3. Read the small-findings-adjacent evidence section of
   `docs/workflow/development-workflow/protocols/93-automated-reviewer-loop-protocol.md`.
4. Run `scripts/development-workflow/local-ai-reviewer.sh --help`.

**Expected result**: all four describe the same four stages, the same three
evidence keys, and the same additive rule. **None may state that a stage
replaces the contract**, and none may claim the file tier can override the
branch tier. Reading them against Steps 1 through 3 must surface no
contradiction.

## Step 9: Static checks

1. Run `shellcheck` on `scripts/development-workflow/local-ai-reviewer.sh` and
   `scripts/development-workflow/local-codex-review-command.sh`.
2. Run

   <!-- workflow-shell-contract: bash -->

   ```bash
   python3 scripts/lint/workflow-shell-guard-lint.py \
     --base-ref origin/develop-internal-reviewer-effectiveness
   ```

   Both changed scripts are under `scripts/development-workflow/`, which the
   guard's path filter matches, and the guard runs on added diff lines only.
3. Run `markdownlint-cli2` on the changed documentation: `REVIEW.md`, the
   integration document, Protocol 93, this runbook and the implementation plan.

**Expected result**: all three tools exit 0.

## Step 10: Planted-violation proofs

**Maps to**: `REVIEW.md` → Core Rules → Verification Discipline.

1. Read the implementation PR's `Planted-Violation Proofs` heading.
2. Confirm P1 through P9 each record the command, the file and line of the
   planted violation, and both outcomes.

**Expected result**: nine proofs in three groups — **four** narrowing, **four**
misclassification, **one** contract, per the plan's proof-group table.

The narrowing group carries the weight, because narrowing is the failure mode
with no symptom: P1 drops a checklist through the merge and requires Step 3's
`feature/x` + yes row to fail; P3 drops the `default` guarantee and requires
Step 3's last two rows to fail; P4 drops the additive sentence and requires Step
6 to fail; P8 renames a contract section and requires Step 4 to fail. P6 is the
one to read twice — it plants an *over*-selection, and it is still a defect,
because a checklist named on every PR distinguishes nothing.

---

## Rollback verification

Revert the implementation PR and re-run Steps 1 and 6. Both must fail to find
the resolvers and must produce the current stage-agnostic prompt for every
branch type.

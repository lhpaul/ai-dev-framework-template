# Smoke Test Runbook: Step 7a Capability-Based Reviewer Reachability

**Feature**: Step 7a capability-based reviewer reachability
**Spec**: [`1_1495-step-7a-capability-based-reachability_specs.md`](../../specs/developments/20260909163304_1495-step-7a-capability-based-reachability/1_1495-step-7a-capability-based-reachability_specs.md)
**Implementation plan**: [`2_1495-step-7a-capability-based-reachability_implementation-plan.md`](../../specs/developments/20260909163304_1495-step-7a-capability-based-reachability/2_1495-step-7a-capability-based-reachability_implementation-plan.md)
**Created in**: Plan Ready stage
**Updated in**: In Development stage

---

## Prerequisites

This feature is workflow tooling, not an application. There is no server to start and no database to
seed.

- [ ] You are on the implementation branch for #1495 with the change applied.
- [ ] `gh` is installed and authenticated (`gh auth status` succeeds).
- [ ] `python3`, `git`, and `bash` are available.
- [ ] **No `.ai-dev-workflow.local.yaml` exists in this checkout** for Steps 1 to 7. If you have one,
      move it aside first and restore it at the end:

      ```bash
      mv .ai-dev-workflow.local.yaml /tmp/ai-dev-workflow.local.yaml.bak 2>/dev/null || true
      ```

- [ ] A scratch directory for fixture checkouts:

      ```bash
      export SMOKE_TMP="$(mktemp -d)"
      ```

- [ ] Note which of `claude`, `cursor-agent`, and `codex` are on your `PATH`. Several steps below
      depend on it:

      ```bash
      for b in claude cursor-agent codex; do printf '%s: %s\n' "$b" "$(command -v "$b" || echo absent)"; done
      ```

No design assets exist for this item — it changes no user interface — so this runbook contains no
design-fidelity step.

---

## Test Data

| Item | Value |
| --- | --- |
| Repository root | the checkout you are testing in |
| Availability resolver | `scripts/development-workflow/resolve-reviewer-availability.sh` |
| Config resolver | `scripts/development-workflow/workflow-config-resolver.py` |
| Owner / repo | your fork or the template repository, as `--owner <owner> --repo <repo>` |
| Fixture root | `$SMOKE_TMP` |
| Shipped default list | `claude, cursor, codex` |

Throughout, "the verdict block" means the `KEY=value` summary the availability resolver prints after
its `REVIEWER` records.

---

## Smoke Test Steps

### Step 0: Confirm the starting state

1. Run `git status --porcelain` and confirm the output is empty.
2. Run `grep -n "runner:" -A 4 .ai-dev-workflow.yaml` and confirm the shipped list is
   `claude`, `cursor`, `codex`.
3. Run `grep -rn "universally reachable" --include="*.md" --include="*.sh" . | grep -v node_modules`
   and confirm no live surface appears — only the CHANGELOG entry and the 2026-05 development
   artifact, both historical records.

**Expected result**: a clean tree, the new shipped default, and no live surface claiming
unconditional reachability.

### Step 1: The shipped default reaches a reviewer on this machine

**Maps to**: *The shipped default never traps* — "A repository using the shipped default
configuration unchanged, with no machine-local override file, reaches a dispatched reviewer and a
gate verdict on every supported runner."

1. Run the resolver once for each supported runner kind:

   ```bash
   for kind in claude cursor codex; do
     scripts/development-workflow/resolve-reviewer-availability.sh \
       --repo-root "$(pwd -P)" --owner "<owner>" --repo "<repo>" --runner-kind "$kind"
     echo "exit=$?"
   done
   ```

2. Read each verdict block.

**Expected result**: for every one of the three runs, `OUTCOME` is `proceeded` or
`proceeded-reduced`, the exit status is `0`, and `REACHABLE` contains at least the reviewer matching
`--runner-kind`. No run reports `OUTCOME=blocked`. If all three runtimes are on your `PATH`, every
run reports `proceeded` with all three reachable.

### Step 2: Identity alone never makes a reviewer unreachable

**Maps to**: *Reachability follows capability* — "A configured reviewer is not classified Unreachable
solely because a different runner is driving the gate."

1. Run the resolver with `--runner-kind claude` while `codex` is on your `PATH`.
2. Find the `REVIEWER codex` record.

**Expected result**: `REVIEWER codex reachable -`. The record carries no reason, and no line anywhere
in the output mentions the driving runner as a cause. This is the exact condition the previous
identity table classified as unreachable.

### Step 3: An absent runtime is Unreachable with the runtime reason

**Maps to**: *Reachability follows capability* and *The operator can tell why*.

1. Build a hermetic `PATH` that deliberately omits `codex`:

   ```bash
   mkdir -p "$SMOKE_TMP/bin"
   for c in awk bash cat cut date dirname git grep gh head jq mktemp printf python3 rm sed sleep sort tr wc; do
     src="$(command -v "$c" || true)"
     [ -n "$src" ] && ln -sf "$src" "$SMOKE_TMP/bin/$c"
   done
   PATH="$SMOKE_TMP/bin" scripts/development-workflow/resolve-reviewer-availability.sh \
     --repo-root "$(pwd -P)" --owner "<owner>" --repo "<repo>" --runner-kind claude
   echo "exit=$?"
   ```

**Expected result**: `REVIEWER codex unreachable runtime-absent <detail>` and
`REVIEWER cursor unreachable runtime-absent <detail>`, while `REVIEWER claude reachable -` holds by
identity. `OUTCOME=proceeded-reduced`, exit `0`. The reason is `runtime-absent`, never
`prerequisite-missing` and never `check-inconclusive`.

### Step 4: The verdict is determined fresh on each run

**Maps to**: *Reachability follows capability* — "making a runtime available between two runs flips
the verdict … and removing it flips the verdict back."

1. From Step 3's hermetic `PATH`, add a stub `codex` that answers `--version`:

   ```bash
   printf '#!/bin/sh\necho "codex-cli 0.0.0-stub"\n' > "$SMOKE_TMP/bin/codex"
   chmod +x "$SMOKE_TMP/bin/codex"
   PATH="$SMOKE_TMP/bin" scripts/development-workflow/resolve-reviewer-availability.sh \
     --repo-root "$(pwd -P)" --owner "<owner>" --repo "<repo>" --runner-kind claude
   ```

2. Remove the stub and run the identical command again:

   ```bash
   rm "$SMOKE_TMP/bin/codex"
   PATH="$SMOKE_TMP/bin" scripts/development-workflow/resolve-reviewer-availability.sh \
     --repo-root "$(pwd -P)" --owner "<owner>" --repo "<repo>" --runner-kind claude
   ```

**Expected result**: the first run reports `REVIEWER codex reachable`, the second reports
`REVIEWER codex unreachable runtime-absent`. No configuration file changed between the two runs, and
nothing was cached.

### Step 5: Determining availability changes nothing

**Maps to**: *Reachability follows capability* — "Determining availability posts no comment, changes
no pull request state, and modifies no tracked file … leaves the checkout clean", and "Determining
availability invokes no reviewer."

1. Run `git status --porcelain` and note the output.
2. Run the resolver once.
3. Run `git status --porcelain` again.
4. Watch the elapsed time of the run and check the repository's open pull requests for any new
   comment.

**Expected result**: the two `git status` outputs are identical. No pull request comment was posted,
no pull request changed draft state, and no review started — the run finishes in seconds, far short
of the minutes a real review takes.

### Step 6: The gate reaches a verdict within the availability budget

**Maps to**: *Configuration inputs that are absent, empty, malformed, or unsupported* — "the gate
reaches that verdict within ten seconds of starting to resolve the list, without operator
intervention."

1. Build a fixture whose reviewer binaries all hang:

   ```bash
   mkdir -p "$SMOKE_TMP/slow"
   cp -R "$SMOKE_TMP/bin/." "$SMOKE_TMP/slow/"
   for b in claude cursor-agent codex; do
     printf '#!/bin/sh\nsleep 120\n' > "$SMOKE_TMP/slow/$b"
     chmod +x "$SMOKE_TMP/slow/$b"
   done
   time PATH="$SMOKE_TMP/slow" scripts/development-workflow/resolve-reviewer-availability.sh \
     --repo-root "$(pwd -P)" --owner "<owner>" --repo "<repo>" --runner-kind unknown
   echo "exit=$?"
   ```

**Expected result**: the command returns in well under fifteen seconds — the ten-second budget plus
process overhead — rather than hanging. Every reviewer is classified, the hanging ones as
`unreachable check-inconclusive`, `ELAPSED_SECONDS` is printed, and the run exits `1` with
`OUTCOME=blocked` and `BLOCK_CAUSE=zero-reachable`. Read `ELAPSED_SECONDS` and confirm it does not
exceed `BUDGET_SECONDS`.

### Step 7: An unsupported value is reported by name

**Maps to**: *Configuration inputs* — "A configured entry that is not a supported reviewer value is
classified Unreachable with the reason Not a supported reviewer, and the offending value is named."

1. Make a fixture checkout with a bad entry:

   ```bash
   mkdir -p "$SMOKE_TMP/badvalue"
   awk '{ if ($0 == "      - claude") print "      - not-a-reviewer"; print }' \
     .ai-dev-workflow.yaml > "$SMOKE_TMP/badvalue/.ai-dev-workflow.yaml"
   grep -n -A 4 '^    runner:$' "$SMOKE_TMP/badvalue/.ai-dev-workflow.yaml"
   scripts/development-workflow/resolve-reviewer-availability.sh \
     --repo-root "$SMOKE_TMP/badvalue" --owner "<owner>" --repo "<repo>" --runner-kind claude
   ```

   Read the `grep` output first and confirm the list now reads `not-a-reviewer`, `claude`, `cursor`,
   `codex` before trusting the resolver's verdict.

**Expected result**: `REVIEWER not-a-reviewer unreachable value-not-supported` names the value
verbatim, `claude` is still `reachable`, and `OUTCOME=proceeded-reduced` with exit `0`. The entry was
reported, not silently dropped.

### Step 8: An absent list falls back to the driving runner's own stage reviewer

**Maps to**: *Configuration inputs* — "With no reviewer list defined in either configuration file,
the gate runs the stage-appropriate default reviewer once and records in its summary that the
fallback applied", and "The reviewer the fallback runs is the driving runner's own reviewer."

1. Make a fixture with the `runner` key removed entirely, then run once per supported runner kind:

   ```bash
   mkdir -p "$SMOKE_TMP/nolist"
   grep -v '^      - \(claude\|cursor\|codex\)$' .ai-dev-workflow.yaml \
     | grep -v '^    runner:$' > "$SMOKE_TMP/nolist/.ai-dev-workflow.yaml"
   for kind in claude cursor codex; do
     scripts/development-workflow/resolve-reviewer-availability.sh \
       --repo-root "$SMOKE_TMP/nolist" --owner "<owner>" --repo "<repo>" --runner-kind "$kind"
     echo "exit=$?"
   done
   ```

**Expected result**: every run reports `CONFIG_LIST_STATE=absent`, `FALLBACK_APPLIED=true`,
`OUTCOME=proceeded`, exit `0`. No run blocks, on any runner kind. Confirm the file you generated
really has no `runner:` key before trusting the result.

### Step 9: A malformed list blocks instead of falling back

**Maps to**: *Configuration inputs* — "With a reviewer list that is defined but cannot be read as a
list of values, the gate blocks … It does not fall back to the default reviewer."

1. Make a fixture where `runner` is a scalar:

   ```bash
   mkdir -p "$SMOKE_TMP/scalar"
   grep -v '^      - \(claude\|cursor\|codex\)$' .ai-dev-workflow.yaml \
     | sed 's/^    runner:$/    runner: codex/' > "$SMOKE_TMP/scalar/.ai-dev-workflow.yaml"
   grep -n '^    runner' "$SMOKE_TMP/scalar/.ai-dev-workflow.yaml"
   scripts/development-workflow/resolve-reviewer-availability.sh \
     --repo-root "$SMOKE_TMP/scalar" --owner "<owner>" --repo "<repo>" --runner-kind claude
   echo "exit=$?"
   ```

   Read the `grep` output first and confirm the single remaining line is `    runner: codex` — a
   scalar where a list is required.

**Expected result**: `CONFIG_LIST_STATE=malformed`, `OUTCOME=blocked`,
`BLOCK_CAUSE=list-malformed`, `FALLBACK_APPLIED=false`, exit `1`, and the output names the file that
could not be read.

### Step 10: An unsupported policy blocks before the list is looked at

**Maps to**: *Policy behavior is preserved* — "With the policy unsupported or unreadable and the
reviewer list absent, empty, or malformed at the same time, the gate blocks on the policy and reports
it as the cause. It does not reach the fallback reviewer."

1. Take the Step 8 fixture (no list at all) and set a bad policy value by uncommenting the policy
   key the shipped file already carries, so the key lands inside the `review:` mapping at the right
   indentation rather than at the end of the file:

   ```bash
   mkdir -p "$SMOKE_TMP/badpolicy"
   sed 's/^  # internal_reviewers_unavailable_policy: warn$/  internal_reviewers_unavailable_policy: maybe/' \
     "$SMOKE_TMP/nolist/.ai-dev-workflow.yaml" > "$SMOKE_TMP/badpolicy/.ai-dev-workflow.yaml"
   grep -n '^  internal_reviewers_unavailable_policy' "$SMOKE_TMP/badpolicy/.ai-dev-workflow.yaml"
   scripts/development-workflow/resolve-reviewer-availability.sh \
     --repo-root "$SMOKE_TMP/badpolicy" --owner "<owner>" --repo "<repo>" --runner-kind claude
   echo "exit=$?"
   ```

   The `grep` must print exactly one line reading `  internal_reviewers_unavailable_policy: maybe`.
   If it prints nothing, the commented template line was reworded during implementation — add the
   key by hand under `review:` at two-space indentation instead.

**Expected result**: `POLICY_STATE=unsupported`, `BLOCK_CAUSE=policy-unsupported`,
`CONFIG_LIST_STATE=not-evaluated`, `FALLBACK_APPLIED=false`, exit `1`, and the offending value
`maybe` is named. The `not-evaluated` value is the visible proof that the policy was read first.

### Step 11: A machine-local override narrows without warning about what it removed

**Maps to**: *The operator can tell why* — "A reviewer removed by the machine-local override is
reported as Excluded by override and produces no unreachability warning."

1. Write an override that keeps only the reviewer matching your session, then run:

   ```bash
   printf 'review:\n  on_draft:\n    runner:\n      - claude\n' > .ai-dev-workflow.local.yaml
   scripts/development-workflow/resolve-reviewer-availability.sh \
     --repo-root "$(pwd -P)" --owner "<owner>" --repo "<repo>" --runner-kind claude
   echo "exit=$?"
   ```

**Expected result**: `OVERRIDE_EXCLUDED` lists `cursor` and `codex`; each has a
`REVIEWER <name> override-excluded -` record with no reason; `UNREACHABLE` is empty;
`OUTCOME=proceeded`, exit `0`. `LOCAL_OVERRIDE_STATE` names the override file and its origin, taken
from the resolver rather than guessed.

### Step 12: Retiring an override that only existed to unblock the gate

**Maps to**: *The shipped default never traps* — the operator is not asked to write an override file.

1. Delete the override you created in Step 11 (or, if you moved a real one aside in Prerequisites,
   decide whether you still need it):

   ```bash
   rm -f .ai-dev-workflow.local.yaml
   scripts/development-workflow/resolve-reviewer-availability.sh \
     --repo-root "$(pwd -P)" --owner "<owner>" --repo "<repo>" --runner-kind claude
   ```

**Expected result**: `LOCAL_OVERRIDE_STATE=none`, the shipped three-entry list is in `CONFIGURED`,
and the run still reaches `OUTCOME=proceeded` or `proceeded-reduced` with exit `0`. This is the
demonstration that an override written only to get past the gate can be deleted: an operator who
wants to keep narrowing coverage keeps theirs, and an operator who wrote one to unblock removes the
`review.on_draft.runner` key (and the file, if it holds nothing else).

### Step 13: End-to-end on a real pull request

**Maps to**: *Reachability follows capability* first criterion, and *The operator can tell why* —
"The gate summary lists every configured reviewer with its verdict, including reviewers that ran."

1. Open a throwaway draft pull request on this branch, or reuse the implementation pull request for
   #1495.
2. Run Protocol 91 Step 7a against it from a runner whose kind is **not** `codex`, with the shipped
   default configuration and no local override.
3. Read the Step 7a summary comment.

**Expected result**: the gate dispatched at least one reviewer and produced a verdict without a human
choosing a workaround, without an override file being written, and without a second runner being
started. The summary comment lists every configured reviewer with its display label — Reachable,
Unreachable, or Excluded by override — and, for each Unreachable one, its reason category and a
remedy. No message in the comment attributes any reviewer's unavailability to the identity of the
driving runner.

### Last Step: Validate and clean up

1. Work through the Assertions Checklist below.
2. Remove the fixtures and restore any override you moved aside:

   ```bash
   rm -rf "$SMOKE_TMP"
   mv /tmp/ai-dev-workflow.local.yaml.bak .ai-dev-workflow.local.yaml 2>/dev/null || true
   ```

3. Run `git status --porcelain` and confirm the only entries are your intended implementation
   changes — in particular that `.ai-dev-workflow.local.yaml` does not appear.

---

## Assertions Checklist

Each checkbox maps to one or more acceptance criteria from the spec.

- [ ] A configured reviewer whose runtime is present is dispatched even when a different supported
      runner is driving the gate — no block, no escalation, no override file (Step 1, Step 2,
      Step 13).
- [ ] No reviewer is classified Unreachable solely because a different runner is driving the gate
      (Step 2).
- [ ] An absent runtime yields Unreachable with reason `runtime-absent` (Step 3).
- [ ] The verdict is determined fresh on each run and flips both ways with the environment (Step 4).
- [ ] Determining availability posts no comment, changes no pull request state, modifies no tracked
      file, and invokes no reviewer (Step 5).
- [ ] The gate always reaches a verdict within the availability budget, even with an unresponsive
      reviewer (Step 6).
- [ ] The four reason categories are reported distinctly and never in place of one another
      (Steps 3, 6, 7, and the CodeRabbit note under Known Limitations).
- [ ] An unsupported configured value is classified Unreachable with reason `value-not-supported` and
      named in the report (Step 7).
- [ ] An absent or empty list falls back to the driving runner's own stage reviewer and records that
      the fallback applied, on every supported runner (Step 8).
- [ ] A malformed list blocks, names the file, and does not fall back (Step 9).
- [ ] An unsupported or unreadable policy blocks before the list is resolved and names the offending
      value (Step 10).
- [ ] Override-excluded reviewers are reported as such, produce no unreachability warning, and the
      override state is reported from what was resolved (Step 11).
- [ ] The shipped default reaches a dispatched reviewer on every supported runner with no override
      file present (Step 1, Step 12).
- [ ] The gate summary lists every configured reviewer with its verdict, including the ones that ran
      (Step 13).
- [ ] No reported message attributes a reviewer's unavailability to the identity of the driving
      runner (Step 3, Step 13, and Step 0's grep).

---

## Seed Data Reference

| Entity | Scenario | How to load |
| --- | --- | --- |
| Hermetic `PATH` without `codex` | Runtime absent | Step 3 |
| Stub `codex` answering `--version` | Runtime present | Step 4 |
| Hanging reviewer binaries | Availability check does not complete | Step 6 |
| Config with an unsupported entry | Value not supported | Step 7 |
| Config with no `runner` key | Fallback | Step 8 |
| Config with a scalar `runner` | Malformed list | Step 9 |
| Config with `internal_reviewers_unavailable_policy: maybe` and no list | Unsupported policy | Step 10 |
| `.ai-dev-workflow.local.yaml` keeping one reviewer | Override exclusion | Step 11 |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| Every run reports `OUTCOME=blocked` with `BLOCK_CAUSE=zero-reachable` | A `.ai-dev-workflow.local.yaml` you forgot to move aside names reviewers this machine cannot reach | Check `LOCAL_OVERRIDE_STATE` in the verdict block; move the file aside and re-run |
| `LOCAL_OVERRIDE_STATE` reports `present but unpropagated` | You are in a linked git worktree and the override lives in the main clone | Re-run with `--repo-root "$(pwd -P)"` from the worktree; do not copy the file in |
| Hosted reviewers report `check-inconclusive` | `gh` is missing from the hermetic `PATH`, or not authenticated | Symlink `gh` into the fixture `bin` directory and confirm `gh auth status` succeeds |
| `codex-github` or `coderabbit` reports `prerequisite-missing` on a repository where the app is installed | The app has never commented on this repository, so the activity signal finds nothing | Expected — see Known Limitations. Trigger the app once on any pull request, or leave the reviewer out of the list |
| A Step 7, 9, or 10 fixture edit changes nothing | The line the `awk` or `sed` pattern matches was reworded during implementation | Each of those steps prints the edited region with `grep` before running the resolver — read that output and adjust the pattern before trusting the verdict |
| Step 6 takes noticeably longer than the budget | `timeout` is unavailable and the poll fallback is running at one-second granularity | Expected overhead; confirm `ELAPSED_SECONDS` in the output rather than wall-clock `time` |

---

## Known Limitations

- The hosted-service availability probe reads recent repository comment activity. An app that is
  installed but has never commented on the repository classifies as `prerequisite-missing`. The
  remedy the report offers is correct either way, and neither hosted reviewer is in the shipped
  default.
- Step 13 requires a real pull request and a real runner, so it cannot be scripted. Every other step
  runs offline against fixtures.
- This runbook exercises the availability decision, not review quality. What a dispatched reviewer
  then says about the change is out of scope for both the spec and this runbook.

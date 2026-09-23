# Smoke Test Runbook: Cursor Dispatch Profiles

**Feature**: Cursor dispatch profiles (#1462)
**Spec**: [Cursor Dispatch Profiles](../../specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md)
**Plan**: [Implementation plan](../../specs/developments/20260911230512_1462-cursor-dispatch-profiles/2_1462-cursor-dispatch-profiles_implementation-plan.md)
**Created in**: Plan Ready stage

---

## Prerequisites

- [ ] Implementation PR for #1462 is checked out locally
- [ ] `origin/develop` is fetched
- [ ] You can open the template repository in Cursor (Desktop and, if available, Remote Control)
- [ ] For the required live steps (8, 13 Part B, 14 Part B): the **disposable sandbox** below is provisioned and its pre-flight check passes. **Never run the live steps against the real repository or its real backlog.**

---

## Test Data

| Item | Value |
| --- | --- |
| Canonical doc | `docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md` |
| Sandbox repository | A private, disposable repository (for example `<owner>/ai-dev-framework-sandbox-1462`) seeded from the implementation PR head; see **Controlled test artifacts** |
| Sandbox Project | A dedicated GitHub Project **M** owned by the sandbox repository's owner, titled `[SANDBOX-1462] board`, with sandbox-only `Status` and `Type` fields (required names and values below); it is **never** the real repository's configured project |
| Sample item (single) | Sandbox issue **C** `[SANDBOX-1462] single doc-only item` (label `sandbox-test`); confirm with `./scripts/development-workflow/run-work-router.sh <C>` returning `MODE=redirect_item`, run from the sandbox clone |
| Explicit-list batch | Sandbox issues **A** and **B** `[SANDBOX-1462] batch doc-only item A` / `B`; confirm `./scripts/development-workflow/run-work-router.sh <A> <B>` returns `MODE=redirect_items`. The router accepts only positive-integer issue/PR numbers (optionally `#`-prefixed), existing workflow-prefixed branches (`feature/`, `fix/`, `refactor/`, `hotfix/`, `spec/`, `implementation-plan/`, `plan/`) and existing `docs/specs/developments/` folders, splits every argument on commas and removes duplicates. Tracker IDs and comma-containing targets yield `MODE=ambiguous` before any declaration gate, so they are covered as documented-unreachable cases in the fixtures only |
| Epic | Sandbox epic **E** `[SANDBOX-1462] epic` with two native sub-issues **D1** and **D2** (`[SANDBOX-1462] epic child D1` / `D2`, doc-only); confirm `./scripts/development-workflow/run-work-router.sh --epic <E>` returns `MODE=redirect_epic` |

### Controlled test artifacts (sandbox, authorized disposable targets)

The live steps run `/run-item`, `/run-items` and `/run-epic`, which create
branches, commits, pull requests, tracker updates and worktrees. They must
therefore run **only** against disposable test artifacts created for this
sign-off, never against real backlog items, real branches or the real
repository. The operator (not an agent) provisions and removes the sandbox and
records each action; an agent must not create or delete repositories.

**Provisioning (operator checklist)**

0. **Record the real values first** (in the real checkout, before anything
   else) so the sandbox can be proven different from them:
   `REAL_OWNER=$(gh repo view --json owner --jq .owner.login)`,
   `REAL_REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)`, and
   `REAL_NUM=$(python3 -c 'import yaml; print(yaml.safe_load(open(".ai-dev-workflow.yaml"))["issue_tracker"]["project_number"])')`
   (today `lhpaul`, `lhpaul/ai-dev-framework-template`, `1`).
1. Create a **private sandbox repository** dedicated to this sign-off (name it
   with `sandbox` and `1462`) and push the implementation PR head **H**
   (`git rev-parse HEAD` of the implementation PR) to it as its `develop`
   branch (the **safe base branch**; the real repository's `develop` and `main`
   are never targeted).
1a. **Create the sandbox Project** (why: the tracker helpers read
   `GITHUB_PROJECT_NUMBER` or `issue_tracker.project_number` and resolve the
   owner from `GITHUB_PROJECT_OWNER`, then `gh repo view`, then the git remote,
   **regardless of provider**; the status and type reads, `run-epic`'s scope
   resolver and every tracker status update go through that project. Status is
   read from the Project item, and an item with no recognized `Status` is
   classified ambiguous). Create it under the sandbox repository's owner with
   `gh project create --owner <SANDBOX_OWNER> --title "[SANDBOX-1462] board"`,
   record its number **M**, link it to the sandbox repository
   (`gh project link <M> --owner <SANDBOX_OWNER> --repo <sandbox repo>`), and
   give it exactly these fields (a new Project comes with a default `Status`
   whose options must be edited to this list in the Project settings UI or with
   the `updateProjectV2Field` GraphQL mutation; create `Type` with
   `gh project field-create <M> --owner <SANDBOX_OWNER> --name Type --data-type SINGLE_SELECT --single-select-options "Feature,Bug,Refactor,Workflow"`):
   - `Status` (single select) with exactly the 12 options `Backlog`, `Writing
     Spec`, `Spec in Review`, `Spec Ready`, `Writing Plan`, `Plan in Review`,
     `Plan Ready`, `In Development`, `Development in Review`, `Merged`,
     `Released`, `Cancelled` (the values the tracker helpers and the epic scope
     resolver recognize; the real project uses the same set);
   - `Type` (single select) with exactly `Feature`, `Bug`, `Refactor`,
     `Workflow` (read only when the provider is `github_projects`).
   No other fields are required (`Priority` and `Size` are optional). After the
   issues exist (step 3), add **only** the sandbox issues to the project
   (`gh project item-add <M> --owner <SANDBOX_OWNER> --url <issue url>`) and set
   each item's `Status` to `Backlog` and its `Type` to `Feature` with
   `gh project item-edit`, using the field and option ids from
   `gh project field-list <M> --owner <SANDBOX_OWNER> --format json`.
1b. Item worktrees are created from `origin/develop`, so a local uncommitted
   edit would not reach them. Therefore make **one dedicated commit S on the
   sandbox's `develop`**, pushed **only to the sandbox**, that changes **only**
   `.ai-dev-workflow.yaml`, and changes **only these keys**:
   (a) `issue_tracker.project_number: <M>` (the sandbox Project number; the
   provider stays `github_projects` so status and type reads use that Project;
   the file has no owner, field-id, repository-slug or `custom_fields` key, so
   nothing else in it references the real repository or project);
   (b) `guardrails.mode: assisted` (the mode whose baseline is that agents never
   merge, so no invocation override can grant merge authority: an override may
   never grant what the mode forbids); (c)
   `guardrails.stages.spec.may_merge_pr`, `.plan.may_merge_pr` and
   `.implementation.may_merge_pr` all `false`. The repository's
   `backlog_start.allow_without_confirmation: true` is kept so the sandbox
   Backlog items can start after the prelude confirmation. Every worktree and PR
   base created afterwards inherits this config. S is never pushed, merged or
   cherry-picked anywhere else.
2. Create the label `sandbox-test` (`gh label create sandbox-test`).
3. Create the test issues with the repo's tracker tooling (`/add-backlog-item`,
   or `gh issue create --label sandbox-test`), each titled with the prefix
   `[SANDBOX-1462]` and each a doc-only change (for example "add one line to a
   sandbox-only doc"): **C** (single), **A** and **B** (batch), epic **E**, and
   its children **D1** and **D2** linked as native sub-issues (GitHub UI, or the
   `addSubIssue` GraphQL mutation via `gh api graphql`).
4. **Pre-flight check** in the clone the Remote Control session will use
   (every check must pass, otherwise **stop**: the live steps must not run):
   - `git remote get-url origin` is the sandbox repository, and
     `gh repo view --json nameWithOwner` names it (neither names the real
     repository);
   - `git rev-parse origin/develop` equals **S**, and
     `git merge-base --is-ancestor H S` succeeds (S sits directly on the
     implementation head);
   - `git diff H S --stat` lists **only** `.ai-dev-workflow.yaml`, and
     `git diff --name-only H S` prints exactly that one path, so the
     implementation-head evidence is preserved (the code under test is
     byte-identical to H except for the config keys below);
   - the changed **keys** are exactly the expected five, checked structurally:

     ```bash
     python3 - "$H" "$S" <<'PY'
     import subprocess, sys, yaml
     def load(rev): return yaml.safe_load(subprocess.check_output(["git","show",f"{rev}:.ai-dev-workflow.yaml"]))
     def leaves(o,p=()):
         if isinstance(o,dict):
             for k,v in o.items(): yield from leaves(v,p+(k,))
         else: yield p,o
     a=dict(leaves(load(sys.argv[1]))); b=dict(leaves(load(sys.argv[2])))
     print(sorted(".".join(k) for k in set(a)|set(b) if a.get(k)!=b.get(k)))
     PY
     ```

     which must print exactly `['guardrails.mode',
     'guardrails.stages.implementation.may_merge_pr',
     'guardrails.stages.plan.may_merge_pr',
     'guardrails.stages.spec.may_merge_pr', 'issue_tracker.project_number']`;
   - `git show S:.ai-dev-workflow.yaml | python3 -c 'import sys,yaml; d=yaml.safe_load(sys.stdin); print(d["issue_tracker"]["provider"], d["issue_tracker"]["project_number"], d["guardrails"]["mode"], [d["guardrails"]["stages"][k]["may_merge_pr"] for k in ("spec","plan","implementation")])'`
     prints exactly `github_projects <M> assisted [False, False, False]`
     (the repository default `True` is gone), so delegated merge is impossible
     in the sandbox;
   - **the sandbox Project is not the production project** (fail on any
     equality; `REAL_*` are the values recorded in step 0):

     ```bash
     SANDBOX_OWNER=$(gh repo view --json owner --jq .owner.login)
     SANDBOX_REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
     SANDBOX_NUM=$(git show "$S:.ai-dev-workflow.yaml" | python3 -c 'import sys,yaml; print(yaml.safe_load(sys.stdin)["issue_tracker"]["project_number"])')
     [ "$SANDBOX_REPO" != "$REAL_REPO" ] && [ "$SANDBOX_OWNER/$SANDBOX_NUM" != "$REAL_OWNER/$REAL_NUM" ] && echo PROJECT-DISTINCT || echo FAIL
     ```

     must print `PROJECT-DISTINCT` (the owner and number pair is what the
     helpers resolve, so equality means the sandbox would drive the real
     Project; a same-owner sandbox needs a number different from `REAL_NUM`);
   - **no override reaches a different project**: in the session's environment
     `printenv GITHUB_PROJECT_NUMBER GITHUB_PROJECT_OWNER WORKFLOW_TARGET_GITHUB_REPO`
     prints nothing (exit `1`; each variable, if set, would override the
     config: `GITHUB_PROJECT_NUMBER` beats `project_number`, and
     `GITHUB_PROJECT_OWNER` beats the repository owner), or each printed value
     equals the sandbox value; and `test ! -e .ai-dev-workflow.local.yaml`
     succeeds in the sandbox clone (a local override file must not exist);
   - **the sandbox Project is sandbox-only and well formed**:

     ```bash
     gh project view "$SANDBOX_NUM" --owner "$SANDBOX_OWNER" --format json --jq .title
     gh project field-list "$SANDBOX_NUM" --owner "$SANDBOX_OWNER" --format json --jq '[.fields[]|select(.name=="Status")|.options[].name]|sort == ["Backlog","Cancelled","Development in Review","In Development","Merged","Plan Ready","Plan in Review","Released","Spec Ready","Spec in Review","Writing Plan","Writing Spec"]'
     gh project field-list "$SANDBOX_NUM" --owner "$SANDBOX_OWNER" --format json --jq '[.fields[]|select(.name=="Type")|.options[].name]|sort == ["Bug","Feature","Refactor","Workflow"]'
     gh project item-list "$SANDBOX_NUM" --owner "$SANDBOX_OWNER" --limit 1000 --format json --jq '[.items[] | select(.content.repository != "'"$SANDBOX_REPO"'")] | length'
     gh project item-list "$SANDBOX_NUM" --owner "$SANDBOX_OWNER" --limit 1000 --format json --jq '[.items[] | select((.title // "") | startswith("[SANDBOX-1462]") | not)] | length'
     ```

     must print a title beginning `[SANDBOX-1462]`, then `true`, `true`, `0`
     and `0` (exact `Status` and `Type` option sets; every item belongs to the
     sandbox repository and carries the sandbox title prefix, so no real item is
     on the board).
5. Confirm the three router checks in the table above return the stated MODEs.
6. **Real-repository baseline** (in the real checkout, before any live step):
   record `T0=$(date -u +%Y-%m-%dT%H:%M:%SZ)`;
   `git ls-remote --heads origin | sort > real-heads-before.txt`; and a snapshot
   of the real Project rows for the **numbers the sandbox issues will have**
   (small numbers such as `1`-`8` collide with real issue numbers, which is
   exactly what a mis-pointed project number would mutate). With `NUMS` set to
   the JSON array of the sandbox issue numbers C, A, B, E, D1, D2 (for example
   `NUMS='[1,2,3,4,5,6]'`):
   `gh project item-list "$REAL_NUM" --owner "$REAL_OWNER" --limit 1000 --format json --jq "[.items[] | select(.content.number as \$n | $NUMS | index(\$n)) | [.id,.status]] | sort" > real-project-before.json`.
   Keep the files outside the repository tree, for example in a temp directory.

**Live invocations and the no-merge policy.** Every live invocation selects a
no-merge policy explicitly, in addition to S's config:

| Step | Invocation (from the sandbox clone) |
| --- | --- |
| 8 | `/run-item <C> --no-delegate-review --no-may-merge --max-risk low` |
| 13 Part B | `/run-items <A> <B> --no-delegate-review --no-may-merge --max-risk low` |
| 14 Part B | `/run-epic --epic <E> --no-delegate-review --no-may-merge --max-risk low` |

**Why every flag is needed** (read from `run-bounded-prelude.sh`, and confirmed
by a read-only dry run of the script for each invocation against a config
shaped like S): with `guardrails.mode: assisted` the prelude resolves **delegated
review to enabled** unless `--no-delegate-review` is supplied, even though
assisted mode never merges; merge authority resolves to false from S's
`may_merge_pr: false`, and `--no-may-merge` makes that explicit. The script's
usage and argument parser accept `--delegate-review|--no-delegate-review` and
`--may-merge|--no-may-merge` for every scope (`--epic`, `--items` and the item
targets), and the commands forward policy flags to it; `/run-items` and
`/run-epic` document only the positive flags in their front matter, which does
not limit the script. `--max-risk low` is explicit so the risk ceiling is the
lowest even though no merge is possible.

**Prelude gate**: before accepting the bounded prelude's policy confirmation,
read `policyRecommendation.confirmationSummary`; its policy lines must be
exactly:

```text
- May start Backlog: true (guardrails)
- Delegated review: false (explicit)
- May merge: false (explicit)
- Max risk: low (explicit)
```

(the dry run printed these lines for the `/run-item` invocation; the
`effectivePolicy` for `/run-items` and `/run-epic` is the same: `delegateReview`
false, `mayMerge` false, `maxRisk` low, `mayStartBacklog` true). If **Delegated
review** is `true` or **May merge** is `true`, **decline and stop**: do not run
the live step (without `--no-delegate-review` the summary shows `Delegated
review: true`, which fails this gate).

**Expected mutations (all confined to the sandbox)**, enumerated per
invocation given S's config:

- **All three commands**: bounded-prelude run-state and policy-binding records
  in the sandbox clone; local worktrees and branches per item
  (`feature/...`, `spec/...`, `implementation-plan/...`); commits and pushes of
  those branches to the sandbox; pull requests targeting the sandbox `develop`
  (whose tip is S); PR labels the scripts create or apply (for example
  `ready-for-human-review`, `ready-for-regression`, `needs-fixes`) and any labels
  they create in the sandbox repository; reviewer-loop and audit comments and
  resolved review threads on those PRs; issue comments and label changes on the
  sandbox items; **item status and type edits on the sandbox Project M only**
  (`Status` transitions such as `Backlog` to `Writing Spec`, and `Type` reads and
  updates through `update_tracker_status_best_effort` and the Type helpers,
  which resolve project number M from S's config); changelog
  fragments; and GitHub Actions workflow runs triggered in the sandbox by the
  pushes and PRs (no external review apps are installed there, so a
  reviewer-unavailable or `failing_ci` stop is an acceptable named stop).
- **`/run-items`** additionally: batch-level tracker updates before dispatch,
  the batch summary comment, and held-back item comments.
- **`/run-epic`** additionally: epic ledger and per-PR disposition audit
  comments on **E** and its children. No `integration-branch:<slug>` label is
  set on E, so no `develop-<slug>` branch is created; if one appears, cleanup
  deletes it.
- **Not performed** (prevented by S and the flags): merging any PR, closing an
  issue as merged, branch deletion by post-merge cleanup, any read or write of
  the real Project `REAL_OWNER/REAL_NUM`, and any change to the real
  repository. The only sandbox-only commit that exists before the runs is
  S. Runs stop at `ready-for-human-review`, a blocked state, an escalation, or a
  named stop.

**Cleanup / rollback checklist (run after Steps 8, 13 and 14, before recording
sign-off)**

1. Close every sandbox pull request and delete its branch
   (`gh pr close <n> --delete-branch`); delete any remaining remote branch other
   than `develop` and `main` (including any `develop-<slug>` branch).
2. Close every issue labelled `sandbox-test` (children, batch items, epic).
3. In the sandbox clone remove worktrees and local branches
   (`git worktree remove <path>`, `git branch -D <branch>`), then
   `git worktree prune`.
4. Delete the **sandbox Project** (`gh project delete <M> --owner <SANDBOX_OWNER>`,
   which needs the `project` scope) or, if the sandbox is kept, at least
   remove every item from it. Then, if the sandbox is kept: delete the `sandbox-test` label and every label the
   scripts created (`gh label list` in the sandbox), delete the workflow runs
   (`gh run list` / `gh run delete`), and remove local run-state and policy
   records in the sandbox clone; otherwise delete the whole sandbox repository,
   which removes all of these (requires the operator's own `delete_repo`
   authorization).
5. Verify the **real repository is untouched**, using the baseline from
   provisioning step 6 (a `SANDBOX-1462` text search is **not** used: the
   feature's own plan pull request legitimately contains that text):
   `git ls-remote --heads origin | sort | diff - real-heads-before.txt` prints
   nothing (no branch added or removed); the **real Project rows for the
   sandbox issue numbers** are unchanged (re-run the step 6 `gh project
   item-list "$REAL_NUM" ...` command into `real-project-after.json`;
   `diff real-project-before.json real-project-after.json` prints nothing, so no
   real item's `Status` was touched by a mis-pointed project number); in the real repository
   `gh pr list --state all --author "@me" --search "created:>=$T0"` and
   `gh issue list --state all --author "@me" --search "created:>=$T0"` print no
   rows (the operator's account created nothing in the real repository during
   the sign-off window; unrelated rows by others are ignored, and any row by
   the operator must be explained in the evidence);
   `gh pr list --state all --search "SANDBOX-1462 in:title"` and
   `gh issue list --state all --search "SANDBOX-1462 in:title"` print nothing
   (no sandbox-titled item leaked); `git status` is clean in the real checkout; and the
   sandbox config commit S is unknown to the real repository: in the real
   checkout `git fetch origin`, then `git cat-file -e S^{commit}` must **fail**
   (`Not a valid object name`, exit `128`) and
   `git branch -r --contains S` must **error** (`no such commit`, exit `129`);
   if either resolves S or lists a branch, S leaked and sign-off is blocked.

**Cleanup is complete when**: the sandbox has no open issue, no open pull
request, no branch other than `develop`/`main`, no worktree, no leftover
script-created label or workflow run, and the sandbox Project is deleted or
empty, or the sandbox repository and Project are deleted; and the real-repository check in item 5 is empty.
Record the command outputs as evidence. If the run is interrupted, perform the
checklist before any retry; leftover sandbox artifacts block sign-off.

**Prohibited**: running Step 8, 13 Part B or 14 Part B against a real backlog
issue, a real epic, or the real repository's branches or base branch. A run that
did so is a FAIL and must be reported, and the mutations rolled back by the
repository owner. Pushing or merging the sandbox config commit S into the real
repository is likewise prohibited.

---

## Smoke Test Steps

### Step 1: Canonical doc completeness

**Maps to**: AC1–AC8, AC17

1. Open the canonical integration doc.
2. Confirm three profile code values and display labels match the spec enum table.
3. Confirm portfolio / epic / item layers each have perform / hand off / prohibit entries with links to role contracts (not restatements).
4. Confirm at least one worked example per profile exists.

**Expected result**: Doc stands alone for an operator new to Remote Control.

### Step 2: Mirror surface link parity

**Maps to**: AC18

1. Open each bounded command adapter (`.cursor/commands/run-item.md`, `run-item-work.md`, `run-items.md`, `run-epic.md`, `run-work.md`, plus Claude and `.agents/skills` parity paths).
2. Confirm each references `integrations/cursor-dispatch-profiles.md` and names the declaration requirement, and states that the requirement applies only in a Cursor environment (other runners unchanged).
3. Confirm no adapter restates the contract itself — evaluation order, stop
   conditions, postures and boundaries live only in the canonical document, so
   an adapter that reproduces them has reintroduced the drift class the pointer
   structure removes.

**Expected result**: every adapter carries the pointer and the Cursor-only
scoping; none restates the contract. See the plan's Test-Scope Deviation Record
for why no surface guard ships.

### Step 3: Guardrails stop conditions

**Maps to**: AC10–AC11

1. Open `docs/workflow/development-workflow/guardrails-enforcement.md` section 4.
2. Confirm rows exist for `dispatch_profile_declaration_missing` and `dispatch_handoff_unavailable`.
3. Confirm `dispatch_profile_declaration_missing` documents `explicit_list_invocation_targets=<t1>,<t2>,...` for pre-branch explicit-list `/run-items` stops, with targets exactly as the router's normalized list holds them (issue or PR numbers with or without `#`, workflow-prefixed branch names, development-folder paths; the router does not accept tracker IDs such as `ENG-123`, and a comma cannot occur inside a target because the router splits on commas), `%`, whitespace and control characters percent-encoded, and duplicates already removed by the router.
4. Confirm the human unblocking action for `dispatch_profile_declaration_missing` requires a **fresh invocation** (the stopped run is not resumed or corrected in place) supplying a valid profile (the facts-assigned one after a mismatch), a named accountable role, and a posture valid for the checkpoint; that `dispatch_handoff_unavailable` gives the move-to-confirmed-environment or accept-read-only action plus the stage-role reachability exception; and that `missing_required_secret_or_permission` gives the grant-and-rerun action plus the structural-restriction path.
5. Confirm coarse-facts mismatch guidance rejects declarations that are either
   more permissive or less permissive than the assigned decision-gate outcome.

**Expected result**: Stop names match spec matrix exactly; mismatch check is bidirectional.

### Step 4: Orchestration role no-handoff behavior

**Maps to**: AC13

1. Open `.cursor/agents/orchestrator.md` and `.cursor/agents/item-orchestrator.md`.
2. Confirm both state: when onward handoff is unavailable, return control to the invoking context and perform no inline product work.

**Expected result**: Wording aligns with canonical doc; no contradiction with parent-orchestrated absorb path.

### Step 5: Agent model configuration

**Maps to**: AC15

1. Open `docs/workflow/development-workflow/agent-model-config.md`.
2. Confirm Cursor Desktop vs Remote Control vs Cloud Agents profile **and model** assignments per layer: Desktop native handoff; Remote Control parent orchestrated at every layer; Cloud Agents inline fallback at every layer (initial handoff unconfirmed).
3. Confirm every cell carries exactly one marker, `confirmed by observation` or `explicit assumption`, for both the profile and the model assignment: `confirmed by observation` only for Desktop at every layer and Remote Control at the item layer; `explicit assumption` for Remote Control portfolio and epic, all Cloud Agents cells, and every model cell.

**Expected result**: Remote Control defaults to Parent orchestrated at every layer (item layer observed; portfolio and epic layers explicit assumptions); Cloud Agents defaults to Inline fallback as an explicit assumption (read-only, `dispatch_handoff_unavailable` on a mutating run) until initial handoff is confirmed by observation; no environment defaults to parent orchestrated without confirmed initial handoff.

### Step 6: Read-only portfolio scan

**Maps to**: AC11, AC12, Use Case 5

1. Read `/run-work` command doc and protocol 90 scan-mode guidance, and run `./scripts/development-workflow/run-work-router.sh` with no target: expect `MODE=no_target_scan`.
2. Confirm scan declares **observing** posture and never escalates into execution.
3. Confirm the command surface states that acting on scan results requires a
   **new bounded run with its own declaration**.

**Expected result**: Acting on scan output requires a new bounded run with its own declaration.

### Step 7: Native handoff desktop path (manual, optional)

**Maps to**: AC6, Use Case 2

1. In Cursor Desktop, invoke `/run-item <C>` (the sandbox single-item issue from Test Data; optional steps also use the sandbox, never real items). The bounded prelude prints read-only scope and policy first.
2. Confirm run output includes the dispatch profile declaration immediately before the first mutating action.

**Expected result**: Declaration visible; orchestration handed off when subagents work.

### Step 8: Parent orchestrated Remote Control `/run-item` (live, REQUIRED at sign-off)

**Maps to**: AC6, AC17, Use Case 3

This is the **required live step for `/run-item`** (Step 13 Part B and Step 14
Part B are the required live steps for `/run-items` and `/run-epic`): it
exercises the behavioral guarantee of AC17 (an operator in a constrained
environment runs a bounded command to a terminal condition without human
rescue) that the decision-matrix simulation in Steps 12-14 cannot exercise. It must run in a **real Cursor Remote
Control session**, not a simulated one, on the **implementation PR head**.

1. Record the **implementation head H** and the **sandbox config commit S**
   (with the output of `git diff H S --stat`, which must list only
   `.ai-dev-workflow.yaml`) and the sandbox Project number **M** and the environment (Cursor Remote Control session
   identifier or a note of how it was reached).
2. From the sandbox clone (pre-flight check passed), start `/run-item <C> --no-delegate-review --no-may-merge --max-risk low` on the sandbox single-item issue from Test Data, after the prelude gate (effective policy shows no merge authority).
3. Confirm the declaration block names Parent orchestrated, the accountable
   role and the `absorbed` posture before the first mutating action, that
   orchestration is absorbed by the current context, and that every stage of
   product work is delegated to its stage role with handoff metadata (not
   authored inline by the orchestrating context).
4. Let the run continue **without any human intervention mid-orchestration**
   (answering the bounded prelude's policy confirmation before the run starts is
   allowed; rescuing the run afterwards is not).
5. Record the terminal state reached: a real terminal condition (waiting on
   human review or merge, blocked dependency, or escalation) or a named stop
   from the decision matrix, plus the transcript excerpt or PR link.

**Expected result**: The run reaches a terminal condition or a named stop with no human rescue mid-orchestration; evidence names the implementation head H, the sandbox config commit S and the Remote Control environment. **NOT RUN is not acceptable for this step at implementation sign-off**, and a run that needed a human rescue is a FAIL.

### Step 9: Inline fallback (manual, optional)

**Maps to**: Use Case 4

1. In an environment with no subagent handoff, or one whose initial handoff cannot be confirmed (the Cloud Agents default), invoke `/run-item <C>` (a mutating bounded command).
2. Confirm the run declares **Inline fallback** (`cursor-inline-fallback`) with a
   valid accountable role and **observing** posture at the read-only checkpoint,
   then reaches the first mutating action.
3. Confirm the run stops with named condition `dispatch_handoff_unavailable`
   (not `dispatch_profile_declaration_missing`).

**Expected result**: No artifact mutation; stop reason matches a valid inline-fallback declaration, not a missing declaration.

### Step 10: Parent-orchestrated inline prohibition + #1746 honesty

**Maps to**: AC19

1. Open the canonical doc, `.cursor/agents/item-orchestrator.md`, and any
   protocol/role surface that mentions inline fallback or stage permission denial.
2. Confirm no document relaxes the parent-orchestrated prohibition on inline
   product work by the absorbing orchestration context.
3. Confirm #1746 remains an explicit Out-of-Scope / unresolved-gap callout (not
   solved by this feature).
4. Confirm `SUBAGENT_PERMISSION_DENIAL` is described as only observably similar
   to stage-role harness denial (Work Item Runner boundary), not as a recovery
   path for stage roles.

**Expected result**: AC19 content present; removing any of the four checks would fail this step.

### Step 11: Accountability postures

**Maps to**: AC20

1. Open the canonical doc accountability-posture section (and declaration
   contract if postures are defined there).
2. Confirm three named postures exist (absorbed / handed-off / observing — exact
   labels per spec).
3. Confirm `observing` is valid only at read-only checkpoints.
4. Confirm posture mismatch (e.g. `observing` at a mutating action, or
   absorbed/handoff at a read-only checkpoint) is treated the same as a missing
   declaration (`dispatch_profile_declaration_missing`).

**Expected result**: AC20 content present; posture mismatch maps to the missing-declaration stop.

---

> **Steps 12-14 rule**: two independent kinds of evidence are **both mandatory**
> for the three bounded commands at implementation sign-off.
>
> - **Simulation** (`simulate_bounded_paths`, Steps 12, 13 Part A, 14 Part A):
>   validates the **decision matrix** (every row, both mismatch directions,
>   recovery, unconfirmed handoff). It does not execute the command flows.
> - **Live Cursor Remote Control execution** (Step 8 for `/run-item`, Step 13
>   Part B for `/run-items`, Step 14 Part B for `/run-epic`): validates the
>   **behavioral guarantee** (AC17) that an operator in a constrained
>   environment runs each bounded command to a terminal condition without human
>   rescue. It cannot exercise the recovery, mismatch, or unconfirmed-handoff
>   rows.
>
> Neither substitutes for the other, and NOT RUN blocks sign-off for either.

### Step 12: `/run-item` terminal behavior at current head

**Maps to**: AC6, AC9, AC10, AC17, AC20

1. Record the current head SHA (`git rev-parse HEAD`).
2. **Mandatory**: walk the canonical document's Decision-gate section by hand
   against **every** `/run-item` scenario marked Y in the plan's scenario table
   (S1, S3, S5, S7-S10, S10b, S11-S19), confirming each produces the outcome
   and next action the gate states — including unconfirmed initial/onward
   handoff, profile/fact mismatch in both directions, mid-run recovery, and
   reachable-stage credential denial. Record any scenario the document does not
   resolve unambiguously.
3. The live `/run-item` evidence is Step 8 (required, real Remote Control).
   Step 12 covers the walkthrough only; it never replaces Step 8.

**Expected result**: every `/run-item` scenario resolves to exactly one outcome
and next action; evidence names the head SHA. This walkthrough is manual by
design — see the plan's Test-Scope Deviation Record.

### Step 13: `/run-items` explicit-list terminal behavior at current head

**Maps to**: AC9, AC10, AC14, AC17

1. Record the implementation head H, the sandbox config commit S, the sandbox Project number M, and the `git diff H S --stat` output (only `.ai-dev-workflow.yaml`).
2. In the sandbox clone, use the sandbox issues `<A> <B>` (Test Data) and run
   `./scripts/development-workflow/run-work-router.sh <A> <B>`; proceed only on
   `MODE=redirect_items`. (Any other MODE, including `ambiguous`, stops before
   the declaration gate; fix the sandbox items, never substitute real ones.)

**Part A (mandatory, simulation)**: run the `simulate_bounded_paths` branch for
**every** `/run-items` scenario marked Y in the plan's scenario table (same set
as `/run-item`, with pre-branch stops asserting the single invocation-level
affected-item string over router-accepted target forms: numbers with and
without `#`, a workflow-prefixed branch, a development-folder path; tracker IDs
and comma-containing targets are documented-unreachable cases, not accepted
forms). Confirm exactly **one** `dispatch_profile_declaration_missing` stop is
reported for the whole invocation with affected item
`explicit_list_invocation_targets=<A>,<B>` (targets as they appear in the
router's normalized list: comma-split, trimmed, deduplicated, in order, no `#`
rewriting), before any branch or artifact is created.

**Part B (mandatory, live Cursor Remote Control)**: in a **real Remote Control
session** on the implementation PR head, run `/run-items <A> <B> --no-delegate-review --no-may-merge --max-risk low` (prelude gate as in Controlled test artifacts) with a valid
Parent orchestrated declaration (the current context absorbs the portfolio layer
and, per item in turn, the item layer; no Work Item Runner is dispatched; the
items run one at a time per Protocol 90 Step 4 as amended, and only stage work
is delegated), and do not intervene mid-run
(answering the bounded prelude's policy confirmation up front is allowed).
Record the environment, the declaration block, and the terminal state. The
terminal condition is, precisely: **either** the completed one-at-a-time run,
meaning every listed item has reached a real terminal condition (waiting on
human review or merge, blocked dependency, or escalation) in sequence, **or** a
named stop from the decision matrix reported with the affected work item. A run
that needed a human rescue mid-orchestration is a FAIL.

**Part C (optional)**: run `/run-items <A> <B>` in a throwaway clone with the
declaration deliberately withheld and confirm the single invocation-level
`dispatch_profile_declaration_missing` stop.

**Expected result**: The simulation passes every scenario for this path (Part
A), and the live Remote Control run reaches the completed one-at-a-time run or a
named stop with no human rescue (Part B); evidence names H, S and the
Remote Control environment. NOT RUN is not acceptable for Part A or Part B.

### Step 14: `/run-epic` terminal behavior at current head

**Maps to**: AC9, AC10, AC17

1. Record the implementation head H, the sandbox config commit S, the sandbox Project number M, and the `git diff H S --stat` output (only `.ai-dev-workflow.yaml`).
2. With the sandbox epic `<E>` (Test Data) confirm `./scripts/development-workflow/run-work-router.sh --epic <E>`
   returns `MODE=redirect_epic`. (`--items` is internal-only and is not a
   user-facing option per Protocol 95.)

**Part A (mandatory, simulation)**: run the `simulate_bounded_paths` branch for
**every** `/run-epic` scenario marked Y in the plan's scenario table (S1, S3, S5,
S7-S10, S10b, S11-S19), confirming the epic layer is declared absorbed, stage
work is delegated with handoff metadata, and an invalid or missing declaration
stops with `dispatch_profile_declaration_missing` (affected work item per
`guardrails-enforcement.md` section 4).

**Part B (mandatory, live Cursor Remote Control)**: in a **real Remote Control
session** on the implementation PR head, run `/run-epic --epic <E> --no-delegate-review --no-may-merge --max-risk low` (prelude gate as in Controlled test artifacts) under a
valid Parent orchestrated declaration and do not intervene mid-run. Record the
environment, the declaration block, and the terminal state. The terminal
condition is, precisely: the epic resolver's `continuation` outcome, either
`complete`, or `needs_resolution` with its named `stopCondition` and
`humanAction`, **or** a named stop from the decision matrix reported with the
affected work item; a run that stalled or needed a human rescue
mid-orchestration is a FAIL.

**Expected result**: The simulation passes every scenario for this path (Part
A), and the live Remote Control run reaches a `continuation` terminal outcome or
a named stop with no human rescue (Part B); evidence names H, S and the
Remote Control environment. NOT RUN is not acceptable for Part A or Part B.

---

## Pass criteria

- Steps 1-6 and 10-11 must **PASS** (documentation and automated assertions; no
  live Cursor environment required).
- **Live Cursor Remote Control evidence is required for all three bounded
  commands** at implementation sign-off, run **only** against the disposable
  sandbox artifacts (never real backlog items or the real repository), with the
  cleanup checklist completed and its completion criteria met and recorded
  before sign-off (leftover sandbox artifacts, or any mutation of the real
  repository, block sign-off). Every live invocation selects the no-merge
  policy from the runbook (`--no-delegate-review --no-may-merge --max-risk low` for
  `/run-item`, `/run-items` and `/run-epic`), on top of the sandbox config commit S that
  sets the sandbox `project_number`, `mode: assisted` and `may_merge_pr: false`; a live run whose prelude
  summary showed delegated review or any merge authority, that merged any pull request, or that
  read or changed the real Project (`REAL_OWNER/REAL_NUM`), is a FAIL. The evidence fields are the implementation head
  **H** plus the sandbox config commit **S**, with `git diff H S --stat` proving
  S touches only `.ai-dev-workflow.yaml` and the structural key diff proving it
  changes only the five expected keys, plus the sandbox Project number **M** and
  the pre-flight results proving M is not the production project; evidence without H, S and that diff
  is invalid, and evidence against a sandbox `develop` other than S is stale, each on the implementation PR head in a
  **real** Remote Control session with no human rescue mid-orchestration:
  Step 8 (`/run-item`), Step 13 Part B (`/run-items`, terminal condition = the
  completed one-at-a-time run or a named stop), and Step 14 Part B
  (`/run-epic --epic <E>`, terminal condition = a `continuation` outcome of
  `complete`, or `needs_resolution` with its named `stopCondition` and
  `humanAction`, or a named stop). **NOT RUN is not acceptable** for any of the
  three: if a real Remote Control session is unavailable, sign-off is blocked
  rather than waived. A live run that needed a human rescue is a FAIL.
- **The simulation is also mandatory**: Step 12, Step 13 Part A and Step 14 Part
  A (`simulate_bounded_paths`, every scenario the plan's table marks Y for the
  path) validate the **decision matrix** (every row, both mismatch directions,
  recovery, unconfirmed handoff). They do not execute the command flows, so a
  passing simulation alone leaves the AC17 behavioral guarantee unproved, and
  live runs alone cannot exercise the recovery, mismatch, and
  unconfirmed-handoff rows. Neither substitutes for the other.
- Manual live Steps 7 (Desktop) and 9 (inline fallback / Cloud Agents) and
  Step 13 Part C are optional and may be documented **NOT RUN** with a reason,
  provided the required live evidence above and all simulation parts passed at
  the same head SHA.
- Evidence recorded against an older head than the one being merged is stale and
  must be re-run.

# Cursor Dispatch Profiles — Implementation Plan

**Spec**: [Cursor Dispatch Profiles](1_1462-cursor-dispatch-profiles_specs.md)
**Smoke test runbook**: [Cursor Dispatch Profiles](../../../testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md)

---

## Summary

**Approach**: Add a canonical integration guide (`cursor-dispatch-profiles.md`) that
defines the three profiles, orchestration layers, decision matrix, declaration
contract, handoff metadata, and worked examples. Mirror that contract onto every
bounded-command entrypoint, portfolio and item orchestration role documents,
Protocols 90/91/95, `agent-model-config.md`, and `.cursor/rules/workflow.mdc`.
Extend `guardrails-enforcement.md` section 4 with the two new named stop
conditions. Resolve the spec's pre-branch `/run-items` affected-item gap in this
plan and propagate it through the canonical doc and stop-message guidance.

**Estimated complexity**: L

**Rationale**: The change is documentation-heavy but must stay internally
consistent across many mirror surfaces, reproduce the full decision matrix
without restating role contracts, and give operators a self-service path under
Cursor Remote Control. Wrong or drifted wording drops gates in production runs.

**Dependencies**: Spec PR [#1732](https://github.com/lhpaul/ai-dev-framework-template/pull/1732)
is merged to `develop`. No other feature must merge first. Related gaps **#1745**
(batch-context marker enforcement) and **#1746** (stage-role harness permission
denial) remain out of scope and must be referenced, not solved, here.
Verified `2026-09-18` via `gh issue view 1745 --json state` / `gh issue view 1746
--json state`: both **OPEN**. Consequence if either closes before or during
implementation: re-check the issue resolution text, then either (a) keep the
canonical-doc / guardrails / role-agent "out of scope" callouts only if the
closed issue did not land a conflicting contract, or (b) update those surfaces
in the same implementation PR so they no longer assert an unresolved gap.

**Design assets**: None. Workflow documentation only.

---

## Verification Log

Re-run `2026-09-21` against verified head **`4357b3bf`** (the plan content
commit; full SHA `4357b3bf60785078ef64d9d35224678918e23232`). The commit that
carries this log is the **child** of `4357b3bf` and changes **only** this
Verification Log and the Document Quality Gate lines that cite it; no plan
content, checklist, or smoke-runbook text changed in the child. Every
command in the table is in the **Literal commands** block below, run exactly as
written at the verified head with its observed output recorded (patterns are
extended-regex; nothing depends on the shadowed local `rg`). Checks that need the
implementation are marked **Deferred to implementation**, not Pass.

| Check | Command / query | Result at `4357b3bf` |
| --- | --- | --- |
| Repo revision | `git rev-parse --short HEAD` | `4357b3bf`. `origin/develop` is `f1d5021a`; this plan branch is 20 commits behind it. That is **informational only**, not an A1 failure: the implementation is never cut from the plan branch. A1's check runs after its remediation sequence (plan PR merged, `git fetch origin develop`, implementation worktree created from `origin/develop`), so `git merge-base --is-ancestor origin/develop HEAD` then holds by construction; the ancestry check itself is **Deferred to implementation start** |
| Canonical doc absent pre-impl | L1 | `absent` (Pass) |
| Profile strings outside development folder | L2 | `docs/testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md` only (Pass) |
| Bounded command adapters | L3 and L3b | **18** hits (Pass): **14** command/`SKILL.md` (`5` `.cursor/commands` + `4` `.claude/commands` + `5` `SKILL.md`) + **4** `agents/openai.yaml` (`14+4=18`). The four yaml files are not edited; `.claude/commands/run-epic.md` is in Files to modify but **not** in the 18 (no `run-item` substring). |
| Orchestration role agents | L4 | `4` (all four present) (Pass) |
| Files-to-modify paths | L5 | `31 E` / `4 M`: 31 existing paths present; the 4 **Create** entries (canonical doc, surface guard, fixtures directory, changelog fragment) are absent as expected (Pass) |
| Spec merge gate | A1 (`gh pr view 1732 --json state,baseRefName`) | `{"baseRefName":"develop","state":"MERGED"}` (Pass) |
| Related gap #1745 | A5 (`gh issue view 1745 --json state`) | `{"state":"OPEN"}` — batch-context marker enforcement; out of scope here (Pass) |
| Related gap #1746 | A5 (`gh issue view 1746 --json state`) | `{"state":"OPEN"}` — stage-role harness permission denial; out of scope here (Pass) |
| Stop conditions pre-impl | L6 | prints `0` and exits `1` (grep exits 1 when the count is 0), expected until implementation (Pass) |
| Markdown lint (plan + smoke runbook) | `npx markdownlint-cli2` and `python3 scripts/lint/markdown-heuristic-lint.py` on both files | 0 issues on both files (Pass) |
| Spec matrix row count | L7 | prints `20` table lines = **18** normative rows plus the header and separator (Pass); the plan's 21 scenarios map to them via the row-to-scenario table; the C1-C4 assertions themselves are **Deferred to implementation** |
| Fixture manifest | L8 | prints `158 158 True ['158']`: 158 rows, 158 unique filenames, numbered 1-158, `MANIFEST_COUNT` 158 (Pass); no `<id>` placeholder or unresolved `N`; the on-disk equality self-test is **Deferred to implementation** |
| Router grammar | Ran `scripts/development-workflow/run-work-router.sh` read-only at `4357b3bf` with representative inputs (comma-joined arguments, duplicates, `./` prefix, edge whitespace, empty pieces, `#` and bare numbers, tab, CR, space, non-ASCII, `%`, an interior line feed, tracker ID, `--epic`) and compared with the serialization contract | Observed results match the contract's observation table: comma split, trim, empty drop, first-occurrence exact-string dedup (`1462` and `#1462` distinct), `./` kept, tab/CR/space/non-ASCII/`%` kept inside a token, an interior line feed drops everything after the first line, tracker IDs ambiguous (Pass) |
| Protocol 90 Step 4 current text | L9 | prints `1`, so the existing generic Step 4 paragraph quoted in Decision 7 is verbatim (Pass); the paragraph insertion and the `protocol90_step4_condition`, `protocol95_execution_arrangement`, `protocol91_absorbed_layer_sentence` and `canonical_dispatch_decision` checks are **Deferred to implementation** |
| Assumption records A1-A6 (pre-edit checks that exist now) | A1, A2, A3a, A3b, A4, A5 in the Literal commands block (the same commands as the Assumption Records table) | A1: `git fetch origin develop` succeeds and `git ls-remote --exit-code origin develop` exits `0`; #1732 `MERGED` on `develop`; #1771 still `OPEN` (expected until it merges; the remediation sequence's worktree and ancestry steps are **Deferred to implementation start**). A2: `git grep -nE '^mode:' -- .ai-dev-workflow.yaml` prints nothing and exits `1` (anchored at column 0, so the nested `guardrails.mode: delegated` on line 273 is not matched), and the structural check prints `<absent>`, so the default `single_repo` holds. A3: (a) prints `<spec path>:1`; (b) prints nothing, exit `1`; (c) the router returns `RESOLVED_SCOPE` as the comma-joined, deduplicated, ordered list (run separately: `bash scripts/development-workflow/run-work-router.sh <branch> <folder> <branch>`). A4: prints `0`. A5: both `{"state":"OPEN"}`. A6: same as the Spec merge gate row. All Pass; the canonical/guardrails parity is **not** an assumption and is verified post-edit by `explicit_list_format_parity` (**Deferred to implementation**) |
| Tracker-config keys inherited by the sandbox commit | L10 | Only three leaves in `.ai-dev-workflow.yaml` mention project, owner, repo, slug, field or a path: `issue_tracker.provider = 'github_projects'`, `issue_tracker.project_number = 1` and `template.repository = ''`. The only real-repository reference is `project_number: 1`; there is no owner, field-id, repository-slug or `custom_fields` key (Pass) |
| Sandbox-Project pre-flight expressions (read-only) | P0, P5, P6, P7 | `P5` `FAIL` (the distinctness guard fails on equal owner/number), `P6` empty environment and no local override file, `P7` `[]` (structural key-diff of identical revisions). The Project queries themselves (Status options `true`, Type options `true`, items outside the repo `0`, sandbox-title check non-zero on the real Project) were validated read-only against the real Project earlier in this session at `87f2d2be`; they are not re-run here because the shared GitHub GraphQL rate limit was exhausted, and running them against the actual sandbox Project is **Deferred to implementation** |
| Live-invocation prelude gate (read-only dry run) | L11a-L11d | Against a config shaped like S (assisted mode, `may_merge_pr: false`) via `AI_DEV_WORKFLOW_CONFIG_FILE`: without the negative flags `delegateReview` resolves to `true` (L11a: fails the runbook's gate); with `--no-delegate-review --no-may-merge --max-risk low`, `/run-item`, `/run-items` and `/run-epic` each resolve to `delegateReview: false`, `mayMerge: false`, `mayStartBacklog: true`, `maxRisk: low`, and the `/run-item` confirmation summary prints exactly the four policy lines the runbook requires; the repository stayed clean (`0` porcelain lines) (Pass) |
| Selector baseline | SEL (`--report-gaps`) and the fixtures-path `--changed-files` probe (run earlier: prints `INFO: full run triggered by ...`) | `UNREACHABLE_SUITE_COUNT=0` before this suite exists (Pass). Observed: a changed path under `scripts/development-workflow/tests/fixtures/` prints `INFO: full run triggered by <path> (matches scripts/development-workflow/tests/fixtures/**)` and emits every suite (Pass), so the fixtures directory is a full-run trigger and gets a positive check only. The `--print-map` and per-surface `--changed-files` planted checks (with the unselected-when-removed step for non-fixtures paths) for the new suite are **Deferred to implementation** |
| Shell-script lint (new `.sh`) | `bash -n`; `shellcheck --severity=warning`; `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop` | **Deferred to implementation** (script not yet created; `shellcheck` and the guard linter are available locally) |
| Surface guard (link, profile string, E1-E6 clauses, canonical-doc checks) | `bash scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh` | **Deferred to implementation** (script not yet created) |
| Scanner fixtures + `--self-test` (Parser-Risk cases, fence semantics) | `... --self-test` | **Deferred to implementation** |
| Planted-violation proofs (cycles 1-16 plus per-class repeats) | see Layer-by-Layer Changes → Workflow tooling | **Deferred to implementation** |
| `simulate_bounded_paths`; smoke Steps 7-14 (live Remote Control Steps 8, 13 Part B and 14 Part B are required at sign-off) | smoke runbook | **Deferred to implementation** (needs the implementation head and a real Remote Control session) |


**Literal commands** (run exactly as written from the repository root at the
verified head; `L#` and `A#` are the labels used in the table):

```bash
PLAN=docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/2_1462-cursor-dispatch-profiles_implementation-plan.md
SPEC=docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md
echo "L1"; test ! -f docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md && echo absent
echo "L2"; grep -rlE 'cursor-native-handoff|cursor-parent-orchestrated|cursor-inline-fallback' . --exclude-dir=.git --exclude-dir=node_modules | grep -v 20260911230512_1462
echo "L3"; grep -rl 'run-item' .cursor/commands .claude/commands .agents/skills/run-item .agents/skills/run-item-work .agents/skills/run-items .agents/skills/run-epic .agents/skills/run-work | wc -l
echo "L3b"; grep -rl 'run-item' .cursor/commands .claude/commands .agents/skills/run-item .agents/skills/run-item-work .agents/skills/run-items .agents/skills/run-epic .agents/skills/run-work | grep -c 'openai.yaml'
echo "L4"; ls .cursor/agents/orchestrator.md .cursor/agents/item-orchestrator.md .claude/agents/orchestrator.md .claude/agents/item-orchestrator.md | wc -l
echo "L5"; grep -o '^| `[^`]*` |' "$PLAN" | sed 's/^| `//; s/` |$//' | grep -E '^(docs|\.cursor|\.claude|\.agents|\.codex|scripts|changelog)' | sort -u | while read -r f; do [ -e "$f" ] && echo E || echo M; done | sort | uniq -c
echo "L6"; grep -cE 'dispatch_profile_declaration_missing|dispatch_handoff_unavailable' docs/workflow/development-workflow/guardrails-enforcement.md; echo "rc=$?"
echo "L7"; awk '/^## Decision-Gate Consistency Matrix/{f=1} /^\*\*Mirror surfaces\*\*/{f=0} f && /^\| /' "$SPEC" | wc -l
echo "L9"; grep -cF 'If the runner does **not** support Work Item Runner handoff natively, continue in the current session by following `91-orchestrate-work-protocol.md` for each item one at a time.' docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md
echo "A1"; git fetch origin develop 2>&1 | tail -1; git ls-remote --exit-code origin develop >/dev/null; echo "ls-remote rc=$?"; gh pr view 1732 --json state,baseRefName; gh pr view 1771 --json state
echo "A2"; git grep -nE '^mode:' -- .ai-dev-workflow.yaml; echo "rc=$?"; python3 -c 'import yaml; d=yaml.safe_load(open(".ai-dev-workflow.yaml")); print(d.get("mode","<absent>"))'
echo "A3a"; git grep -c "does not define what it names for a pre-branch" -- "$SPEC"
echo "A3b"; git grep -l explicit_list_invocation_targets | grep -v -e 20260911230512_1462 -e docs/testing/workflow/1462; echo "rc=$?"
echo "A4"; gh pr list --state open --limit 100 --json number,files --jq '[.[] | select([.files[].path] | any(test("protocols/(90|91|95)-|guardrails-enforcement|agent-model-config|integrations/cursor-dispatch|\\.cursor/commands/run-|\\.claude/commands/run-|\\.agents/skills/run-|\\.cursor/agents/|\\.claude/agents/|\\.codex/skills/workflow-(item-)?orchestrator|\\.cursor/rules/workflow"))) | .number] | length'
echo "A5"; gh issue view 1745 --json state; gh issue view 1746 --json state
echo "SEL"; bash scripts/development-workflow/select-test-suites.sh --report-gaps 2>&1 | grep '^UNREACHABLE_SUITE_COUNT='
echo "L8"; python3 - "$PLAN" <<'PY'
import re,sys
s=open(sys.argv[1]).read()
r=re.findall(r"^\| (\d+) \| `([^`]+\.fixture\.md)` \|",s,re.M)
print(len(r),len(set(x[1] for x in r)),[int(x[0]) for x in r]==list(range(1,len(r)+1)),re.findall(r"MANIFEST_COUNT = (\d+)",s))
PY
echo "L10"; python3 - <<'PY'
import re, yaml
d = yaml.safe_load(open(".ai-dev-workflow.yaml"))
def leaves(o, p=()):
    if isinstance(o, dict):
        for k, v in o.items(): yield from leaves(v, p + (k,))
    elif isinstance(o, list):
        for i, v in enumerate(o): yield from leaves(v, p + (str(i),))
    else: yield ".".join(p), o
for p, v in leaves(d):
    if re.search(r"project|owner|repo|slug|field|/", p + " " + str(v), re.I): print(p, "=", repr(v))
PY
echo "P0"; REAL_OWNER=$(gh repo view --json owner --jq .owner.login); REAL_REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner); REAL_NUM=$(python3 -c 'import yaml; print(yaml.safe_load(open(".ai-dev-workflow.yaml"))["issue_tracker"]["project_number"])'); echo "$REAL_OWNER $REAL_REPO $REAL_NUM"
echo "P5 (distinct guard fails on equal values)"; SANDBOX_OWNER=$REAL_OWNER; SANDBOX_REPO=$REAL_REPO; SANDBOX_NUM=$REAL_NUM; [ "$SANDBOX_REPO" != "$REAL_REPO" ] && [ "$SANDBOX_OWNER/$SANDBOX_NUM" != "$REAL_OWNER/$REAL_NUM" ] && echo PROJECT-DISTINCT || echo FAIL
echo "P6 (no env override, no local override file)"; printenv GITHUB_PROJECT_NUMBER GITHUB_PROJECT_OWNER WORKFLOW_TARGET_GITHUB_REPO; echo "printenv rc=$?"; test ! -e .ai-dev-workflow.local.yaml && echo no-local-override
echo "P7 (structural key diff of two revisions, expression validity)"; python3 - HEAD HEAD <<'PY'
import subprocess, sys, yaml
def load(rev): return yaml.safe_load(subprocess.check_output(["git","show",f"{rev}:.ai-dev-workflow.yaml"]))
def leaves(o,p=()):
    if isinstance(o,dict):
        for k,v in o.items(): yield from leaves(v,p+(k,))
    else: yield p,o
a=dict(leaves(load(sys.argv[1]))); b=dict(leaves(load(sys.argv[2])))
print(sorted(".".join(k) for k in set(a)|set(b) if a.get(k)!=b.get(k)))
PY
echo "L11"; SLIKE="${TMPDIR:-/tmp}/s-like.yaml"; python3 - "$SLIKE" <<'PY'
import re, sys
s = open(".ai-dev-workflow.yaml").read()
s = s.replace("  mode: delegated", "  mode: assisted", 1)
s = re.sub(r"(      may_merge_pr: )true", r"\1false", s)
open(sys.argv[1], "w").write(s)
PY
show() { python3 -c 'import sys,json; d=json.load(sys.stdin); r=d["policyRecommendation"]; print(json.dumps({k:r["effectivePolicy"].get(k) for k in ("delegateReview","mayMerge","mayStartBacklog","maxRisk")}))'; }
PRE=./scripts/development-workflow/run-bounded-prelude.sh
echo "L11a run-items WITHOUT the negative flags (previous runbook text)"; AI_DEV_WORKFLOW_CONFIG_FILE="$SLIKE" bash $PRE --original-command "/run-items 1462 1496 --max-risk low" --items "1462,1496" --max-risk low --json | show
echo "L11b /run-item (policy, then the confirmation-summary policy lines)"; AI_DEV_WORKFLOW_CONFIG_FILE="$SLIKE" bash $PRE --original-command "/run-item 1462 --no-delegate-review --no-may-merge --max-risk low" --issue 1462 --no-delegate-review --no-may-merge --max-risk low --json > "${TMPDIR:-/tmp}/l11b.json"; show < "${TMPDIR:-/tmp}/l11b.json"; python3 -c 'import sys,json; print("\n".join(json.load(sys.stdin)["policyRecommendation"]["confirmationSummary"]["policyLines"]))' < "${TMPDIR:-/tmp}/l11b.json"
echo "L11c /run-items"; AI_DEV_WORKFLOW_CONFIG_FILE="$SLIKE" bash $PRE --original-command "/run-items 1462 1496 --no-delegate-review --no-may-merge --max-risk low" --items "1462,1496" --no-delegate-review --no-may-merge --max-risk low --json | show
echo "L11d /run-epic"; AI_DEV_WORKFLOW_CONFIG_FILE="$SLIKE" bash $PRE --original-command "/run-epic --epic 1462 --no-delegate-review --no-may-merge --max-risk low" --epic 1462 --no-delegate-review --no-may-merge --max-risk low --json | show
git status --porcelain | wc -l
```

**Observed output** (same labels, verbatim):

```text
L1
absent
L2
./docs/testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md
L3
      18
L3b
4
L4
       4
L5
  31 E
   4 M
L6
0
rc=1
L7
      20
L9
1
A1
 * branch              develop    -> FETCH_HEAD
ls-remote rc=0
{"baseRefName":"develop","state":"MERGED"}
{"state":"OPEN"}
A2
rc=1
<absent>
A3a
docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md:1
A3b
rc=1
A4
0
A5
{"state":"OPEN"}
{"state":"OPEN"}
SEL
UNREACHABLE_SUITE_COUNT=0
L8
158 158 True ['158']
L10
issue_tracker.provider = 'github_projects'
issue_tracker.project_number = 1
template.repository = ''
P0
lhpaul lhpaul/ai-dev-framework-template 1
P5 (distinct guard fails on equal values)
FAIL
P6 (no env override, no local override file)
printenv rc=1
no-local-override
P7 (structural key diff of two revisions, expression validity)
[]
L11
L11a run-items WITHOUT the negative flags (previous runbook text)
{"delegateReview": true, "mayMerge": false, "mayStartBacklog": true, "maxRisk": "low"}
L11b /run-item (policy, then the confirmation-summary policy lines)
{"delegateReview": false, "mayMerge": false, "mayStartBacklog": true, "maxRisk": "low"}
- May start Backlog: true (guardrails)
- Delegated review: false (explicit)
- May merge: false (explicit)
- Max risk: low (explicit)
L11c /run-items
{"delegateReview": false, "mayMerge": false, "mayStartBacklog": true, "maxRisk": "low"}
L11d /run-epic
{"delegateReview": false, "mayMerge": false, "mayStartBacklog": true, "maxRisk": "low"}
       0
```

---

## Cross-Cutting Operational Assumption Check

| Assumption surface | Recorded value | Authoritative source | Verified at | Bounded cross-check scope | Result |
| --- | --- | --- | --- | --- | --- |
| Integration / artifact base branch | `develop` | `.ai-dev-workflow.yaml` + batch handoff | See the Verification Log (A1-A6 re-run at the log's verified head) | Current invocation `#1462`; batch peers `#1757,#1462,#1496,#1515,#1561,#1583,#1529`; same-surface open PRs none | `Verified` |
| Repository mode | `single_repo` | Batch handoff `WORKFLOW_MODE` | See the Verification Log (A1-A6 re-run at the log's verified head) | Peers touch adjacent workflow docs but do not change base branch or mode for this item | `Verified` |

Peer item `#1529` references dispatch profiles in its plan narrative only; it
does not alter the integration branch or artifact ownership for `#1462`.

---

## Plan-Stage Gap Resolution (spec § Known gaps)

**Gap**: Pre-branch, explicit-list `/run-items` declaration stops lack an
affected-work-item representation when no branch, PR, or development folder
exists yet.

**Decision (recorded here, propagated in implementation)**:

- For a declaration stop on an explicit-list `/run-items` invocation **before
  any item-scoped artifact exists**, the affected work item is a **single**
  string: `explicit_list_invocation_targets=<t1>,<t2>,...`, one `<ti>` per
  target of the router's **normalized target list**, in that order. The
  serialization is defined over what `run-work-router.sh` actually accepts, read
  from `resolve_token` and the token normalization step (the router, not the
  Protocol 90 detection prose, is authoritative at this gate):
  - **Router grammar.** Arguments are split on commas, edge whitespace is
    trimmed, empty pieces are dropped, and duplicates are removed keeping the
    first occurrence (`normalized_tokens`, `deduped_tokens`). Each remaining
    token must resolve as one of: a positive integer, optionally `#`-prefixed,
    that `gh` confirms as a PR or an issue; an existing directory under
    `docs/specs/developments/` (a leading `./` is stripped only for the
    existence test); or a branch that starts with a workflow prefix
    (`feature/`, `fix/`, `refactor/`, `hotfix/`, `spec/`,
    `implementation-plan/`, `plan/`) and exists locally or on `origin`. Anything
    else, including a **tracker identifier such as `ENG-123`** (named in
    Protocol 90's detection prose but not resolved by the router), stops at
    `MODE=ambiguous` before the declaration gate, so the serialization is not
    defined for it and the canonical doc says so.
  - Each `<ti>` is the token **exactly as it appears in the router's
    normalized list** (the router keeps the token as typed after comma
    splitting and trimming). **No rewriting**: a `#` is never added or removed,
    case is preserved, a `/` in a branch name is kept, and a leading `./` on a
    development-folder path is kept.
  - The delimiter is a single comma with no surrounding spaces. Because the
    router splits every argument on commas, a comma **cannot occur inside an
    accepted target** (an input like `feature/x,y` becomes the two tokens
    `feature/x` and `y` before resolution). The `,` to `%2C` rule below is
    therefore a **defensive, unreachable-at-the-gate** rule kept only so the
    output stays unambiguously decodable; no worked example, live step, or
    accepted-target fixture contains a comma inside a target.
  - Escaping (percent-encoding, applied per target, `%` first so it is not
    double-encoded): `%` becomes `%25`, `,` becomes `%2C`, and any ASCII
    whitespace or control character inside a target becomes `%XX` (uppercase
    hex of the UTF-8 byte). All other bytes are emitted unchanged. Which bytes
    the router can actually deliver (observed by running it, see the table
    below): `%` and non-ASCII characters can occur in a branch name (git
    allows both); space, tab, CR and other control characters survive router
    normalization inside a token but git refs and numbers cannot contain them,
    so they are deliverable only by an unconventional development-folder name
    (the workflow names folders `<timestamp>_<slug>`), which makes those
    encodings **defensive**; a **line feed can never appear inside a target**
    (see the newline bullet); a comma cannot occur at all.
  - **Duplicates never reach the gate**: the router removes them before
    resolution (first occurrence kept), so the serialization renders the
    deduplicated list, never a repeated target. Deduplication is by exact
    string, so `1462` and `#1462` are **distinct** tokens (observed:
    `RESOLVED_SCOPE=1462,#1462`) and both are rendered as typed; the
    serialization never merges them. Order is the router's
    normalized order; at least two targets are present (the `/run-items`
    minimum).
  - **Newlines are unreachable, so output is always one line**: the router
    normalizes each argument with `IFS=',' read -ra parts <<< "$t"`, which reads
    only through the first newline. Anything after the first line of an argument
    is silently dropped before resolution (observed: an argument
    `feature/a<LF>feature/b` yields the single token `feature/a`). A line feed
    therefore cannot appear inside a target and is never percent-encoded; the
    canonical doc states this instead of showing a `%0A` case. A carriage return
    is not a line separator for `read`, so it stays inside the token and, on the
    defensive path above, would be encoded as `%0D`. The value is one line
    because LF cannot occur and CR and other control characters are encoded.
  - Encoding is **not idempotent by design**: a target that already contains
    `%25` text is encoded again (`%` becomes `%25`), so decoding once always
    returns the original bytes; the `%`-first ordering is what guarantees this.
  - A single target and an empty target are **unreachable** at this gate (the
    router stops at `MODE=redirect_item` or `MODE=ambiguous` before any
    declaration gate), so the serialization is undefined for them; the
    canonical doc says so and never renders a one-target or empty form.
  - Example: invoked as `/run-items #1462 feature/cursor-dispatch,1771 #1462`
    (the comma-separated argument is split and the repeated `#1462` removed by
    the router) yields
    `explicit_list_invocation_targets=#1462,feature/cursor-dispatch,1771`.
  - **Observed router behavior** (read-only runs of
    `run-work-router.sh` in this worktree at head `a2113081`, no mutation; each
    row is one invocation, the first target an existing branch or development
    folder so only the row's variable target decides the result):

    | Input | Observed |
    | --- | --- |
    | one argument `<branch>,<folder>` | split into two tokens; `MODE=redirect_items`; `RESOLVED_SCOPE=<branch>,<folder>` |
    | `<branch> <branch> <folder>` | duplicate removed, first kept; `RESOLVED_SCOPE=<branch>,<folder>` |
    | `./<folder> <branch>` | `RESOLVED_SCOPE` keeps the leading `./` (`./<folder>,<branch>`) |
    | `" <branch> " "<folder> "` | edge whitespace trimmed; `RESOLVED_SCOPE=<branch>,<folder>` |
    | `<branch>,,<folder>,` | empty pieces dropped; `RESOLVED_SCOPE=<branch>,<folder>` |
    | `<branch> #1462` | `#` kept (`RESOLVED_SCOPE=<branch>,#1462`) |
    | `1462 #1462` | not deduplicated (exact-string dedup): `RESOLVED_SCOPE=1462,#1462` |
    | interior tab in a token (`feat<TAB>x`) | token kept with the tab; unresolved, `MODE=ambiguous` |
    | interior CR in a token (`feature/a<CR>b`) | token kept with the CR; unresolved (no such branch) |
    | interior space (`feature/a b`) | token kept; unresolved |
    | non-ASCII (`feature/ñandú`) | token kept byte-for-byte; unresolved only because the branch is absent |
    | `feature/100%-done` | token kept; unresolved only because the branch is absent; `git check-ref-format` accepts it |
    | interior LF (`feature/a<LF>feature/b`) | only `feature/a` survives; the second line is dropped |
    | a valid first line then LF then junk | junk silently dropped; the valid first line resolves |
    | `ENG-123` | `MODE=ambiguous`, "could not be resolved" |
    | `feature/a,b` | split into `feature/a` and `b` (git accepts the ref, the router never delivers it whole) |
    | `--epic 1462` | `MODE=redirect_epic`, `RESOLVED_SCOPE=1462` |

    `git check-ref-format --branch` rejects space, tab, CR, LF, `0x1F` and
    `0x7F` in a branch name and accepts `%`, `%25`, non-ASCII and `,`.
- Report **once** for the whole invocation; do not emit one stop per target.
- Mirror this rule in:
  - `integrations/cursor-dispatch-profiles.md` (Named stop reporting subsection),
  - `guardrails-enforcement.md` section 4 row text for
    `dispatch_profile_declaration_missing`,
  - Protocol 90 explicit-list preamble (declaration checkpoint before item
    resolution / first mutation),
  - The merged spec's Named Stop-Condition Mapping table (implementation PR
    updates the spec file to close the documented gap).

---

## Architecture and Decision Boundary

### Decision 1: Canonical guide owns the matrix; mirrors link back

All profile rules, evaluation order, transitions, and examples live in
`docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md`.
Every mirror surface states the requirement and links to that file rather than
restating the matrix (AC1–AC3, AC10, AC18–AC19).

### Decision 2: Declared, not detected

Implementation adds **documentation and runner instructions only**. No shell
helper auto-detects Cursor environment capabilities (spec Out of Scope item 3).
Commands and orchestration protocols require a visible declaration block before
the first mutating action (or before reporting for read-only checkpoints).

### Decision 3: Standard declaration block

The canonical doc defines one markdown-friendly block operators and agents
copy into run output. The four field names and the profile value spellings
below are **normative** (the canonical doc reproduces the block verbatim; only
the values change per run):

```markdown
**Dispatch profile**: Native handoff (`cursor-native-handoff`)
**Accountable orchestration role**: Work Item Runner (item layer)
**Accountability posture**: handed off intact
**Canonical reference**: docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md
```

Re-declarations repeat the block with a **Reason** line when the profile
changes mid-run.

### Decision 4: Prelude vs declaration ordering

The shared bounded prelude (`bounded-run-prelude.md`) may complete read-only
scope and policy resolution first. The dispatch-profile declaration still must
appear **immediately before the first mutating action** (branch create, file
edit that changes tracked artifacts, tracker mutation, PR open). For
`/run-work`, declaration precedes reporting scan results.

### Decision 5: Parent-orchestrated absorbs full role contract

Under `cursor-parent-orchestrated`, the current context performs every
orchestration obligation from the absorbed role's agent + protocol surfaces and
**delegates** spec/plan/implement/review work to stage roles with full handoff
metadata (`BATCH_CONTEXT`, isolation, **worktree path**, branch, base, artifact repo root,
mutation class). No inline product work (AC4, AC19).

### Decision 6: Cursor environment defaults in agent-model-config

Add a **Cursor dispatch profiles** subsection listing, per environment ×
orchestration layer, the profile, the **model assignment**, and the evidence
class (AC15), each marked with exactly one of the two markers
`confirmed by observation` (only where the spec itself cites the fact for that
environment and layer) or `explicit assumption` (everything else, with its
rationale). Every profile is justified by a row of the spec's Decision-Gate
Consistency Matrix applied to the facts the spec supports; no evidence is
invented.

**What the spec actually cites** (re-read from its background, BO-6 and
Business Rules): (1) On the Cursor desktop application the assumption that a
runner can hand work to a specialist role (it lists the portfolio
orchestrator, the epic runner, the work item runner and the stage roles) holds.
(2) Under Remote Control "the orchestration context a command hands off to
frequently cannot hand off again": an environment-level statement, hedged with
"frequently", covering commands generally. (3) One **recorded case** under
Remote Control in which one context ended up doing orchestration and
implementation at once, which is an **item-layer** incident. (4) BO-6 requires
`/run-item`, `/run-items` and `/run-epic` to be operable under Remote Control.
(5) Nothing is recorded for Cursor Cloud Agents, and the spec's Business Rule
says an unobserved environment or layer is an explicit assumption that takes
the more restrictive profile until confirmed. The spec does **not** record the
fact separately for the portfolio or epic layer under Remote Control, and cites
no observation about which model a role runs on.

| Environment | Layer | Profile | Matrix row applied | Evidence marker | Rationale |
| --- | --- | --- | --- | --- | --- |
| Cursor Desktop | Portfolio | Native handoff | Initial and onward handoff available (S1) | `confirmed by observation` | Spec citation (1): the two-hop handoff holds on desktop, and the citation names the portfolio orchestrator |
| Cursor Desktop | Epic | Native handoff | S1 | `confirmed by observation` | Spec citation (1), which names the epic runner |
| Cursor Desktop | Item | Native handoff | S1 | `confirmed by observation` | Spec citation (1), which names the work item runner |
| Cursor Remote Control | Portfolio | Parent orchestrated | Onward-handoff capability unconfirmed, initial handoff available (S5 mutating, S6 scan): the conservative default | `explicit assumption` | The spec cites the onward failure only environment-wide ("frequently") and records no portfolio-layer case, so onward capability at this layer cannot be confirmed; the matrix assigns parent orchestrated as the conservative default. At this layer it means Decision 7: the current context absorbs the portfolio and item layers and runs items one at a time (requires the Protocol 90 Step 4 Cursor-scoped paragraph) |
| Cursor Remote Control | Epic | Parent orchestrated | S5 (the conservative default) | `explicit assumption` | Same: no epic-layer case is recorded; onward capability is unconfirmed, so the conservative default applies (BO-6 requires the command to be operable) |
| Cursor Remote Control | Item | Parent orchestrated | Initial handoff available, onward unavailable (S3) | `confirmed by observation` | Spec citation (3): the recorded case is an item-layer incident, together with citation (2) |
| Cursor Cloud Agents | Portfolio | Inline fallback | Initial handoff cannot be confirmed (S11 read-only, S12 mutating stop `dispatch_handoff_unavailable`) | `explicit assumption` | Citation (5): nothing observed, so initial handoff is unconfirmed and the matrix assigns inline fallback; parent orchestrated is valid only after initial handoff is confirmed |
| Cursor Cloud Agents | Epic | Inline fallback | S11 / S12 | `explicit assumption` | Same |
| Cursor Cloud Agents | Item | Inline fallback | S11 / S12 | `explicit assumption` | Same |

Consequence for Cloud Agents: a
mutating bounded run stops with `dispatch_handoff_unavailable` recording that
initial handoff is unconfirmed, rather than absorbing a role. An operator who
observes and records in run output that initial handoff is available makes the
**next** run declare afresh against the confirmed facts (parent orchestrated if
onward handoff is unavailable or unconfirmed, native handoff if both are
available); a run never upgrades in place. The same applies to a Remote
Control portfolio or epic layer once an operator observes and records the onward
fact for that layer: the next run declares afresh against it. The
agent-model-config table records these cells with the `explicit assumption`
marker, not `confirmed by observation`.

**Model assignments** (explicit, so implementation does not invent them). The
tiers come from the existing role table in `agent-model-config.md`: Portfolio
Orchestrator `economy` / `fast`; Work Item Runner `balanced` / `auto`. The
epic layer has no dedicated agent file; it is a coordination loop that makes
delegated merge decisions, so it takes the Work Item Runner tier (`balanced`)
as its floor. Stage roles (spec, plan, implement, review) always keep their own
configured models under every profile.

| Environment | Portfolio layer model | Epic layer model | Item layer model | Model evidence |
| --- | --- | --- | --- | --- |
| Cursor Desktop | Portfolio Orchestrator agent's own model: `economy` / `fast` | Epic-layer role's model: `balanced` / `auto` | Work Item Runner agent's own model: `balanced` / `auto` | `explicit assumption`: the framework documents that a Cursor subagent's frontmatter `model` applies on native handoff, but the spec cites no observation of which model a role runs on |
| Cursor Remote Control | The floor is the highest tier among the layers the run absorbs: a `/run-work` scan absorbs nothing (`observing`), so the `economy` floor applies (`fast` where selectable); `/run-items` absorbs the portfolio **and** item layers, so the `balanced` floor applies (`auto` where selectable) | Absorbing current context must run at `balanced` or higher, `auto` where selectable | Absorbing current context must run at `balanced` or higher, `auto` where selectable | `explicit assumption` at every layer (the remote session's model is not switched by role frontmatter, and the spec cites no model observation) |
| Cursor Cloud Agents | No role absorbed (inline fallback, read-only): the session's own model reports findings; no role floor applies | Same as Cloud portfolio | Same as Cloud portfolio | `explicit assumption` (profile and model). When an operator later confirms initial handoff, the next run uses the Remote Control or Desktop row that the confirmed facts assign, including its model floor |

Under `cursor-parent-orchestrated`, the absorbing context never uses `inherit`
as a substitute for the floor: if the session model is below the absorbed
role's tier, the declaration records the shortfall and the operator switches
the session model before the first mutating action. Under
`cursor-inline-fallback` no orchestration role is absorbed, so no role floor
applies. Unobserved environments use the more restrictive applicable profile
until an operator confirms otherwise in run output.

### Decision 7: Exact dispatch decision under each profile

The spec's layer rule (Use Case 3: the portfolio layer for an explicit
multi-item batch, the epic layer for an epic run, the item layer for a single
item, with nested layers absorbed together when a run spans more than one)
makes ownership explicit. Per command and profile:

| Command | Native handoff | Parent orchestrated (current context absorbs) | Inline fallback |
| --- | --- | --- | --- |
| `/run-item` | Hands the item to the Work Item Runner (`item-orchestrator`), which dispatches stage roles | Absorbs the **item layer** (Protocol 91); dispatches **no** Work Item Runner; delegates each stage to its stage role with full handoff metadata | Read-only; stops at the first mutation with `dispatch_handoff_unavailable` |
| `/run-items` | Absorbs nothing beyond its own routing; dispatches one Work Item Runner per item (Protocol 90 Step 4, parallel where the runner supports it) | Absorbs the **portfolio layer** (Protocol 90) **and**, per item in turn, the **item layer** (Protocol 91); dispatches **no** Work Item Runner; runs the listed items **one at a time**; delegates every stage to its stage role | Read-only; stops at the first mutation with `dispatch_handoff_unavailable` |
| `/run-epic` | Hands each advanceable item to a Work Item Runner | Absorbs the **epic layer** (Protocol 95) **and**, per item in turn, the **item layer** (Protocol 91), one item at a time; dispatches **no** Work Item Runner; delegates every stage | Read-only; stops at the first mutation with `dispatch_handoff_unavailable` |
| `/run-work` | Read-only scan in the current context, `observing` | Same | Same |

Why absorbing both layers: under parent-orchestrated the receiving role (the
Work Item Runner) is reachable but **cannot hand stage work onward**, so
dispatching it risks the recorded environment-level failure (onward handoff frequently unavailable). Its item-layer work is
therefore performed by the absorbing context, and only stage work is handed
off.

**Protocol 90 Step 4 change (exact edit, required so the protocol matches).**
File:
`docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`,
section `## Step 4: Dispatch Work Item Runners`. The existing generic fallback
paragraph is **preserved separately and unchanged**; it says nothing about
stage-role handoff and its behavior for non-Cursor runners is out of scope:

```text
If the runner does **not** support Work Item Runner handoff natively, continue in the current session by following `91-orchestrate-work-protocol.md` for each item one at a time.
```

The change is a **new paragraph inserted immediately after it** (before the
`---` that ends Step 4), which applies **only** when a Cursor dispatch profile
is declared:

```text
When the declared dispatch profile is `cursor-parent-orchestrated` (see `integrations/cursor-dispatch-profiles.md`: a Work Item Runner can be reached but cannot hand stage work onward), do not dispatch Work Item Runners: the current context, having absorbed the portfolio layer, follows `91-orchestrate-work-protocol.md` for each item one at a time, absorbs the item layer for each item in turn, and hands every stage of product work to its stage role with the full handoff metadata (never inline). Under `cursor-native-handoff`, dispatch as above. Under `cursor-inline-fallback`, stop per the dispatch-profile decision gate. This paragraph applies only when a Cursor dispatch profile is declared; it does not alter the paragraph above.
```

The stage-only-delegation rule therefore attaches **only** to
`cursor-parent-orchestrated`. A runner that merely lacks native Work Item Runner
handoff keeps the generic behavior above with no added claim that it can hand
stage work to stage roles.

Equivalent execution-arrangement edit in Protocol 95: add an **"Execution
arrangement"** paragraph at the end of `## Step 6: Handoff` (before
`Recommend Missing Autonomy Policy`): "Before advancing any `remainingItems`,
establish the execution arrangement per `integrations/cursor-dispatch-profiles.md`.
Under `cursor-parent-orchestrated`, the current context absorbs the epic layer
and, for each item in turn, the item layer (Protocol 91), dispatches no Work
Item Runner, and delegates every stage to its stage role; under
`cursor-native-handoff`, hand each item to a Work Item Runner. This paragraph
applies only when a Cursor dispatch profile is declared." Protocol 91 gains
one sentence at its execution-arrangement point stating that when the item
layer is absorbed by the invoking context this protocol is followed by that
context, unchanged, with stage delegation as the only handoff, and only when a
Cursor dispatch profile is declared.

This feature adds no concurrent-scheduling behavior: parent-orchestrated batch
and epic runs are sequential by construction (AC17). The Step 4 paragraph insertion
is a protocol change, so it is in Files to modify, the surface guard's
protocol-condition check, its planted proofs and fixtures.

---

## Workflow Decision-Gate Consistency Matrix

This feature is a **complex workflow decision gate** (REVIEW.md). The **normative
matrix is the merged spec** — do not maintain a shortened copy in this plan.

**Authoritative sources** (implementation must match verbatim):

- Spec [Decision-Gate Consistency Matrix](1_1462-cursor-dispatch-profiles_specs.md#decision-gate-consistency-matrix) — all input rows, evaluation order, mirror-surfaces list, examples requirement, and out-of-scope note for #1746.
- Spec [Named Stop-Condition Mapping](1_1462-cursor-dispatch-profiles_specs.md#named-stop-condition-mapping) — including the plan-resolved pre-branch explicit-list affected-item format.

**Implementation mapping** (where each authoritative row lands):

| Spec matrix row (summary) | Canonical doc section | Guardrails / protocols |
| --- | --- | --- |
| Native handoff + mutating command | § Decision gate — full row text | Protocols 90/91/95 declaration + handoff |
| Native handoff + read-only portfolio scan | § Decision gate + § Scan exception | `/run-work` mirrors |
| Parent orchestrated + mutating command | § Decision gate + § Absorbed contract | Role agents + protocols |
| Parent orchestrated + read-only scan | § Decision gate + § Scan exception | `/run-work` mirrors |
| Unconfirmed onward-handoff capability (initial handoff confirmed) + mutating / scan | § Decision gate + § Conservative defaults | `agent-model-config.md` assumptions |
| Native → parent re-declaration (mid-run orchestration failure, initial handoff still available) | § Transitions | Protocol 91 run summary |
| Native → inline re-declaration (mid-run failure + initial handoff lost) | § Transitions | Stop `dispatch_handoff_unavailable` |
| Parent → inline re-declaration (stage handoff unavailable) | § Transitions | Stop `dispatch_handoff_unavailable` |
| Parent orchestrated + reachable stage credential/permission denial | § Delegation failures | Reuse `missing_required_secret_or_permission` |
| No handoff / unconfirmed initial handoff + read-only | § Decision gate | Inline fallback observing posture |
| No handoff / unconfirmed initial handoff + would mutate | § Decision gate | Stop `dispatch_handoff_unavailable` |
| Declaration missing at first mutating action | § Declaration contract | `dispatch_profile_declaration_missing` |
| Invalid profile value / missing accountable role | § Declaration contract | Same stop |
| Declaration invalid at read-only checkpoint (scan / inline-fallback) | § Declaration contract | Same stop |
| Posture mismatch (`observing` at mutation or absorbed/handoff at read-only checkpoint) | § Accountability postures | Same stop |
| Profile/fact mismatch (more or less permissive than assigned outcome) | § Declaration contract + § Evaluation order | Same stop; excludes mid-run recovery rows per spec |
| Pre-branch explicit-list `/run-items` declaration stop | § Named stop reporting | Plan gap `explicit_list_invocation_targets=<t1>,<t2>,...` (verbatim, percent-encoded) |

**Examples (required in canonical doc)**: one worked example per profile for the
item layer; at minimum Native handoff `/run-item`, Parent orchestrated
`/run-item` under Remote Control, Inline fallback mutating `/run-item`, and
read-only `/run-work` under each profile label.

---

## Layer-by-Layer Changes

### Documentation — canonical

- [ ] `docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md`
      — new file: the per-command dispatch decision table (Decision 7), profiles (code + display labels), three layers (portfolio /
      epic / item), perform / hand off / prohibit matrix by layer, detection
      heuristics (declared not detected), absorbing context (contract + scope +
      handoff arrangement), parent-orchestrated stage handoff metadata,
      workflow_hub artifact/tracker/cleanup notes, inline-fix prohibition and
      delegation outcomes (#1746 out of scope), batch-context marker honesty
      (#1745 out of scope), worked examples, pointer precedence (role contract
      wins). Maps to AC1–AC8, AC10–AC11, AC17–AC20.

### Documentation — mirror surfaces

**Mirror content contract (applies to every command/skill mirror below).** A
link to the canonical doc plus a bare "declare a profile" sentence is **not
sufficient** — AC10, AC11 and AC20 require each mirror to state the decisions
themselves, because a constrained Cursor run may have only the mirror in
context. Every mirror in the three bullets that follow must state, in its own
words and not by pointer alone:

1. **Evaluation order (AC10)**: initial handoff is evaluated first;
   onward-handoff capability is evaluated **only once** initial handoff is
   confirmed available; a profile decision never evaluates onward-handoff
   capability before initial handoff is confirmed.
2. **Unconfirmed-handoff outcomes (AC10)** — **both** cases, stated separately:
   (a) onward-handoff capability that cannot be confirmed, once initial handoff
   is confirmed available, is treated as **unavailable** and declared
   **parent-orchestrated** as the conservative default until confirmed;
   (b) **initial handoff availability that itself cannot be confirmed** is
   treated the same as no handoff of any kind, declared
   **cursor-inline-fallback**, and the run stays **read-only** for the
   remainder of that run. A later confirmation never upgrades a run in place;
   the next run declares afresh.
3. **Exact named stop conditions (AC11)**, spelled verbatim:
   `dispatch_profile_declaration_missing`, `dispatch_handoff_unavailable`, and
   the reused `missing_required_secret_or_permission` for a reachable stage role
   reporting a specific delegated action refused for a missing credential,
   GitHub permission, or access token. For **every** stop the mirror also states
   (a) the **affected work item** (including the single
   `explicit_list_invocation_targets=<t1>,<t2>,...` form for pre-branch
   explicit-list stops, targets verbatim and percent-encoded per the plan gap
   rule) and (b) the **concrete human unblocking action**, which must cover every
   cause the stop fires for (for `dispatch_profile_declaration_missing`: a fresh
   invocation supplying a valid profile, a named accountable role, and a
   posture valid for the checkpoint; not only a profile value). The
   mirror further states the **no-named-stop** treatment: a reachable stage
   role's harness tool or local file-path permission denial on a specific
   delegated action is **not** a named stop condition,
   `missing_required_secret_or_permission` does not apply to it, it is only
   observably similar to `SUBAGENT_PERMISSION_DENIAL` (which governs solely a
   Work Item Runner reporting to the Portfolio Orchestrator), and it is Out of
   Scope, tracked as #1746.
4. **Invalid-declaration boundaries (AC10, AC11, AC20)**: a profile value
   outside the three defined profiles, a declaration naming no accountable
   orchestrator role (including an empty value), a posture mismatched to the
   checkpoint, and a **coarse-fact mismatch in both directions** (more
   permissive and less permissive than the assigned outcome) each equal a
   missing declaration and stop with `dispatch_profile_declaration_missing`,
   reporting which part was invalid. The mirror also states the boundary: the
   coarse check governs the initial declaration and re-declarations of the
   coarse facts only, and does **not** govern the mid-run recovery transitions
   (delegation-failure unreachable-stage-role branch, parent-orchestrated to
   inline-fallback on stage-handoff loss, native-handoff mid-run-failure
   transitions), each of which stays a valid re-declaration.
5. **The three accountability postures (AC20)**: personally accountable
   (absorbed), handed off intact, and observing (not absorbed, not handed off).
   `observing` is valid **only** at a read-only checkpoint (a portfolio scan under
   any profile, or any command under inline-fallback before it stops or
   completes); a mutating action always declares absorbed or handed off. The
   required posture follows the run's **current** checkpoint, never its earlier
   mutation history. Both mismatches (`observing` at a mutating action;
   absorbed or handed off at a read-only checkpoint) and a declaration naming no
   role under any posture are missing declarations.

6. **Cursor scoping (spec Out of Scope 6)**: the requirement and every rule
   above apply **only when the run is in a Cursor environment**; behavior of
   other runners (Claude Code, Codex) is unchanged, and a non-Cursor mirror
   states the requirement as Cursor-conditional rather than requiring a Cursor
   dispatch profile from a runner that has not been shown to have the
   limitation. The parent-orchestrated stage-delegation rule likewise attaches
   only to a declared `cursor-parent-orchestrated` profile, never to a runner
   that merely lacks native Work Item Runner handoff.

A mirror that carries the link and omits any of the six does not satisfy the
acceptance criteria, and the surface guard below must fail it.

The same contract applies, scoped to the layer each surface covers, to the
orchestration role documents (`orchestrator`, `item-orchestrator`, Codex
workflow skills), Protocols 90/91/95, `agent-model-config.md`, and
`.cursor/rules/workflow.mdc`. Each of those entries below must reference the
mirror content contract and carry the elements relevant to its layer (a
protocol states evaluation order and stop names at its declaration checkpoint;
a role document states the postures and unconfirmed-handoff outcome for its
layer; `workflow.mdc` states all six compactly).

- [ ] `.cursor/commands/run-item.md`, `run-item-work.md`, `run-items.md`, `run-epic.md`, `run-work.md`
      — full mirror content contract above; `/run-work` additionally states
      scanning is read-only under every profile and that acting on scan results
      requires a **new bounded run with its own declaration**. Maps to AC9, AC10,
      AC11, AC12, AC18, AC20.
- [ ] `.claude/commands/run-item.md`, `run-item-work.md`, `run-items.md`, `run-epic.md`, `run-work.md`
      — same parity as Cursor commands, including the full content contract and
      the `/run-work` AC12 scan posture. Maps to AC10, AC11, AC12, AC18, AC20.
- [ ] `.agents/skills/run-item/SKILL.md`, `run-item-work/SKILL.md`, `run-items/SKILL.md`, `run-epic/SKILL.md`,
      `run-work/SKILL.md` — same parity for Codex discovery path, including the
      full content contract, the deprecated `/run-item-work` alias, and the
      `/run-work` AC12 clause. Maps to AC10, AC11, AC12, AC18, AC20.
- [ ] `.cursor/agents/orchestrator.md` and `.claude/agents/orchestrator.md` —
      no-onward-handoff behavior: return to invoking context; no inline product
      work; profile declaration when absorbing portfolio layer; portfolio-layer
      mirror content (contract elements 1-6, in particular the three postures
      and the unconfirmed-handoff outcome). Maps to AC10, AC11, AC13, AC20.
- [ ] `.cursor/agents/item-orchestrator.md` and
      `.claude/agents/item-orchestrator.md` — same for item layer; clarify
      parent-orchestrated stage delegation vs `SUBAGENT_PERMISSION_DENIAL`
      (Work Item Runner only); item-layer mirror content (contract elements 1-6). Maps to
      AC10, AC11, AC13, AC19, AC20.
- [ ] `.codex/skills/workflow-item-orchestrator/SKILL.md` — canonical-doc
      reference for the Codex item-orchestrator alias, plus the item-layer
      no-onward-handoff behavior mirrored from the agents above, including the item-layer mirror content
      contract. Maps to AC10, AC11, AC13, AC18, AC20.
- [ ] `.codex/skills/workflow-orchestrator/SKILL.md` — **portfolio** layer for
      the Codex discovery path, matching `.cursor/agents/orchestrator.md` and
      `.claude/agents/orchestrator.md`. Required because a Codex user can enter
      portfolio orchestration through this canonical skill directly; omitting it
      would leave that entrypoint with no dispatch-profile declaration contract
      while the plan claims coverage of every orchestration-role entrypoint.
      Carries the portfolio-layer mirror content contract. Maps to AC10, AC11,
      AC13, AC18, AC20.
- [ ] `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md`
      — reference canonical doc when establishing execution arrangement;
      explicit-list declaration checkpoint; pre-branch affected-item string;
      the **Step 4 paragraph insertion** specified in Decision 7 (existing
      generic paragraph unchanged, new Cursor-scoped paragraph added, exact text); mirror content contract
      elements 1-6 at the declaration checkpoint (evaluation order, unconfirmed
      outcomes, exact stop names, invalid cases, postures). Maps to AC5, AC10,
      AC11, AC14, AC17, AC20, plan gap resolution.
- [ ] `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md`
      — reference at execution arrangement; declaration before first mutation;
      parent-orchestrated item-runner obligations; run summary fields (profile,
      transitions, absorbed layers, stage handoffs); one sentence at the
      execution-arrangement point stating that an absorbing invoking context
      follows this protocol unchanged with stage delegation as the only
      handoff (Decision 7); mirror content contract elements 1-6 at the declaration
      checkpoint. Maps to AC5, AC9, AC10, AC11, AC14, AC20.
- [ ] `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md`
      — the **Execution arrangement** paragraph at the end of Step 6 (Decision
      7: epic layer plus per-item item layer absorbed, no Work Item Runner
      dispatch, sequential), with mirror content contract elements 1-6. Maps to AC5, AC10, AC11, AC14, AC20.
- [ ] `docs/workflow/development-workflow/agent-model-config.md` — Cursor
      environment × orchestration-layer table carrying **three** values per
      combination, per AC15: (a) the applicable profile, (b) the applicable
      **model assignment**, and (c) whether that assignment is confirmed by
      observation or an explicit assumption, using exactly the markers
      `confirmed by observation` and `explicit assumption` per cell as fixed in
      Decision 6 (observed only for Desktop at every layer and Remote Control
      at the item layer; every other profile cell and every model cell is an
      explicit assumption). The exact values are fixed in
      Decision 6 (Desktop: native handoff, role's own model; Remote Control epic
      and item: parent orchestrated with a `balanced` floor, portfolio: parent
      orchestrated, with an `economy` floor for a `/run-work` scan and a
      `balanced` floor for `/run-items` (which also absorbs the item layer); Cloud Agents: inline fallback at every layer, an explicit
      assumption for both profile and model, because initial handoff cannot be
      confirmed for an unobserved environment);
      implementation copies them, it does not choose them. The model assignment is not
      optional and is not covered by the existing role-level model table, which
      does not say which assignment an **absorbing current context** uses under
      parent-orchestrated Remote Control (and states that inline fallback absorbs
      no role, so under Cloud Agents no role floor applies) — every
      combination must be answered explicitly. Maps to AC15.
- [ ] `.cursor/rules/workflow.mdc` — profile declaration requirement + canonical
      link + compact mirror content contract (elements 1-6). Maps to AC10, AC11,
      AC16, AC20.
- [ ] `docs/workflow/development-workflow/guardrails-enforcement.md` section 4 —
      add `dispatch_profile_declaration_missing` and
      `dispatch_handoff_unavailable`. Each stop message must name (a) the stop
      condition string, (b) the affected work item, and (c) the human action to
      unblock, covering **every cause** the stop can fire for (spec Named
      Stop-Condition Mapping): for `dispatch_profile_declaration_missing`,
      the stopped run is **not resumed or corrected in place**; the human
      starts a **fresh invocation** supplying (i) a valid profile, one of
      `cursor-native-handoff`, `cursor-parent-orchestrated`, or
      `cursor-inline-fallback`, and, when the prior run was rejected for a
      profile/fact mismatch, the profile the known facts assign, (ii) a named
      accountable orchestrator role, and (iii) a posture valid for the
      checkpoint (absorbed or handed off intact for a mutating action,
      observing for a read-only checkpoint); for `dispatch_handoff_unavailable`,
      move the run to an environment where initial handoff is confirmed
      available and re-run, or explicitly accept the read-only result reported
      for that invocation, and for the parent-orchestrated stage-handoff row
      first confirm the specific stage role the action needed is reachable in
      the target environment; for `missing_required_secret_or_permission`,
      grant the specific credential, GitHub permission, or access token the
      stage role's report named and re-run the same delegated action, or, for a
      structural restriction that will not be granted, reassign the action to a
      context acting as that same stage role or explicitly accept and record
      that the action does not proceed (the absorbing context never performs it
      inline, and this path never extends to a harness or local-path denial). Extend `dispatch_profile_declaration_missing` affected-item
      text for `explicit_list_invocation_targets=<t1>,<t2>,...` (verbatim,
      percent-encoded serialization over the router-accepted target forms); document reuse of
      `missing_required_secret_or_permission` for reachable stage credential
      denial. Maps to AC10–AC11, AC19.
- [ ] `docs/workflow/development-workflow/README.md` — add integration doc to
      integrations list. Maps to discoverability (AC17).
- [ ] `docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md`
      — update Named Stop-Condition Mapping affected-item row for pre-branch
      explicit-list stops per plan gap resolution (spec already merged; align
      text with implementation). Maps to plan gap + AC10.

### Documentation — ordering note (required)

- [ ] `docs/workflow/development-workflow/bounded-run-prelude.md` — **required**:
      one paragraph on ordering: prelude read-only work may precede declaration; declaration
      still required before first mutation. Maps to Decision 4.

### Workflow tooling / tests

- [ ] `scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh`
      (**plan-added**; not named in the merged spec) — regression guard with
      **three independent check branches** over the mirror surfaces (bounded
      command adapters, deprecated `run-item-work` aliases, orchestration role
      agents and Codex workflow skills, protocols 90/91/95,
      `agent-model-config.md`, `workflow.mdc`):
      1. **Link branch**: the surface links to
         `integrations/cursor-dispatch-profiles.md`.
      2. **Profile-string branch**: the surface names the profile code values
         it is required to carry (`cursor-native-handoff`,
         `cursor-parent-orchestrated`, `cursor-inline-fallback`).
      3. **Mirror-content branch (one assertion per contract clause)**: every
         clause in **Mirror content contract** must be present, each checked
         by its own assertion so a failure names the missing clause ID.
         Per-clause required tokens (all fixed strings, matched by the scanner
         rules in **Parser-risk addendum**):
         - E1 evaluation order: `initial handoff`,
           `only once initial handoff is confirmed`, and
           `never evaluates onward-handoff capability before initial handoff`.
         - E2a onward unconfirmed: `treated as unavailable` and
           `cursor-parent-orchestrated` in the same paragraph as
           `conservative default`.
         - E2b **initial handoff unconfirmed**: `initial handoff availability
           that itself cannot be confirmed` (or the fixed synonym recorded in
           the token list), `cursor-inline-fallback`, and `read-only` in the
           same paragraph, plus `never upgrades a run in place`.
         - E3a stop names: `dispatch_profile_declaration_missing`,
           `dispatch_handoff_unavailable`, and
           `missing_required_secret_or_permission`.
         - E3b **affected work item**: `affected work item`, and on the
           surfaces the table assigns it to, `explicit_list_invocation_targets=`, and on
           the surfaces that carry that token the serialization tokens
           `verbatim` and `percent-encoded`.
         - E3c **human unblocking action**: `human unblocking action` (or the
           fixed synonym), plus per-stop **cause-complete** tokens (each stop's
           action must cover every cause that stop fires for):
           - `dispatch_profile_declaration_missing`: `fresh invocation`,
             `not resumed or corrected in place`, `valid profile`,
             `named accountable role`, `posture valid for the checkpoint`, and
             `profile the known facts assign` (the three elements are each
             required, so missing-role, invalid-posture and profile/fact
             mismatch causes are all unblocked, not only an invalid value).
           - `dispatch_handoff_unavailable`: `environment where initial handoff
             is confirmed available`, `explicitly accept the read-only result`,
             and, for the parent-orchestrated stage row, `specific stage role`
             with `reachable`.
           - `missing_required_secret_or_permission`: `grant`,
             `re-run the same delegated action`, and the structural-restriction
             path tokens `same stage role` and `does not proceed`, plus
             `never performs` (inline) and the harness/local-path exclusion.
         - E3d **no-named-stop denial treatment**: `is not a named stop
           condition`, `SUBAGENT_PERMISSION_DENIAL`, `observably similar`,
           and `#1746` in the same paragraph.
         - E4a invalid values: `invalid profile`, `invalid accountable role`,
           `invalid posture`.
         - E4b coarse-fact mismatch both directions: `coarse-fact mismatch`,
           `more permissive`, and `less permissive`.
         - E4c boundary exemption: `mid-run recovery` and `does not govern`.
         - E5 postures: `personally accountable`, `handed off intact`,
           `observing`, `only at a read-only checkpoint`, and `current
           checkpoint`.
         - E6 **Cursor scoping**: `only in a Cursor environment` and
           `other runners are unchanged` in the same paragraph.
         Which clauses a surface class must carry is a table inside the
         script (rows are surface classes, columns are clauses), fixed as:

         | Surface class | E1 | E2a | E2b | E3a | E3b | E3c | E3d | E4a | E4b | E4c | E5 | E6 |
         | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
         | Command / skill mirrors (15) | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
         | Role agents (4) and Codex workflow skills (2) | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
         | Protocols 90, 91, 95 | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
         | `.cursor/rules/workflow.mdc` | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
         | `guardrails-enforcement.md` section 4 | - | - | - | Y | Y | Y | Y | Y | Y | - | - | Y |
         | `agent-model-config.md` | the exact Decision 6 profile, model assignment and evidence marker for every environment x layer cell (Desktop native; Remote Control parent orchestrated at every layer; Cloud Agents inline fallback everywhere; markers `confirmed by observation` for Desktop at every layer and Remote Control item only, `explicit assumption` for every other profile cell and every model cell) | | | | | | | | | | |

         Layer scoping is by wording, not by omission: a portfolio-layer
         surface states the clause for the portfolio layer and an item-layer
         surface for the item layer, but every clause token must be present.
         E3b's `explicit_list_invocation_targets=` token is required on
         Protocol 90, `run-items` mirrors, and guardrails only; the generic
         `affected work item` token is required everywhere E3b is `Y`.
         Exact phrases live in one shared token list at the top of the script so
         canonical wording changes touch one place.
      **Script conventions (REVIEW.md shell checks, ShellCheck-clean)**: validate
      option values before `shift`; emit structured errors consistent with the
      script's output contract (failing clause ID, surface path, expectation);
      validate any path argument against the known surface list before reading;
      no `|| true` masking of `grep`/`git` failures the caller needs; file mode
      executable like sibling `test-*.sh`. Fixtures are `.md` only (never `.sh`)
      so the ShellCheck find over `scripts/development-workflow` does not pick
      them up, and they sit outside the markdownlint globs by design because
      fail fixtures intentionally violate content rules.
      Rationale: AC18 mirror parity is easy to break across 15+ surfaces and a
      link alone does not satisfy AC10/AC11/AC20; a cheap shell guard catches
      drift without requiring live Cursor Remote Control. Maps to AC10, AC11,
      AC18, AC20 regression safety.
- [ ] **Executable path simulation** (same test file, branch
      `simulate_bounded_paths`; supports smoke Steps 12-14). The simulation is a
      data table `scenario x path -> expected next action`; it asserts every
      row of the spec's Decision-Gate Consistency Matrix (below) for every path
      it applies to, by (a) checking the canonical doc's decision-gate row for
      that input carries the expected profile outcome, next action and stop
      name in one block (scanner rules R2-R5), and (b) checking
      `guardrails-enforcement.md` section 4 maps each stop to its affected work
      item and human unblocking action. The **completeness assertions** compare
      against the spec's **normative rows**, not against the scenario count. The
      spec's Decision-Gate Consistency Matrix has **18 normative rows**
      (R1-R18, listed below in spec order); the plan defines **21 scenarios**
      because R17 (two posture-mismatch directions) and R18 (two permissiveness
      directions) are each split into two scenarios, R17 into S17a/S17b and R18
      into S18/S19, and S10b is a **subcase**, not a row: it covers the spec's
      Out-of-scope prose (harness/local-path denial) that sits beside the
      matrix. The assertions are: **(C1)** the canonical doc's decision-gate
      table has exactly 18 rows and that equals the row count read from the
      merged spec's matrix at test time, so a canonical doc that matches the spec
      always satisfies it and a row added or dropped on either side fails;
      **(C2)** every row R1-R18 maps to at least one scenario; **(C3)** every
      scenario maps to exactly one row, or is flagged `subcase (non-row)`, and
      S10b is the only allowed subcase; **(C4)** canonical row *n* carries the
      expected tokens of the scenarios mapped to R*n*. A scenario may never be
      counted as a row, and a row never requires more than its mapped scenarios. Paths: `/run-item` (item layer), `/run-items`
      explicit list (item layer, pre-branch stops use the
      `explicit_list_invocation_targets=<t1>,<t2>,...` form over a target list of
      router-accepted forms: issue or PR numbers with and without `#`, a
      workflow-prefixed branch name, a development-folder path), `/run-epic` (epic layer, invoked as `--epic <N>`; `--items` is internal-only per
      Protocol 95), and `/run-work` (portfolio layer, read-only scan rows only).
      Tracker IDs (`ENG-123`) and comma-containing targets are **not
      router-accepted targets** (the router resolves only numbers, workflow-prefixed
      branches and development folders, and splits every argument on commas), so
      they stop at `MODE=ambiguous` before any declaration gate and appear only as
      documented-unreachable cases in the serialization fixtures; the
      `%`/whitespace/control encodings are exercised in the fixtures with
      router-accepted carriers (a branch containing `%`, a development-folder
      path containing whitespace). Smoke Step 13 uses real, resolvable targets.

      | ID | Spec matrix input | Expected outcome and next action | run-item | run-items | run-epic | run-work | Spec row |
      | --- | --- | --- | --- | --- | --- | --- | --- |
      | S1 | Handoff available, onward available, not a scan | Native handoff; declare, handed off intact, follow protocol | Y | Y | Y | N/A | R1 |
      | S2 | Same, read-only scan | Native handoff; observing, scan in current context | N/A | N/A | N/A | Y | R2 |
      | S3 | Handoff available, onward unavailable, not a scan | Parent orchestrated; declare absorbed layers, absorb full contract, delegate every stage | Y | Y | Y | N/A | R3 |
      | S4 | Same, read-only scan | Parent orchestrated; observing, scan in current context | N/A | N/A | N/A | Y | R4 |
      | S5 | Initial confirmed, onward **unconfirmed**, not a scan | Parent orchestrated (conservative default); record unconfirmed, absorb, delegate only | Y | Y | Y | N/A | R5 |
      | S6 | Same, read-only scan | Parent orchestrated; record unconfirmed, observing | N/A | N/A | N/A | Y | R6 |
      | S7 | Mid-run: native, role unreliable, initial handoff still available | Re-declare parent orchestrated with reason; earlier mutations preserved | Y | Y | Y | N/A | R7 |
      | S8 | Mid-run: native, role unreliable, initial handoff lost or unconfirmed | Re-declare inline fallback; stop next mutation with `dispatch_handoff_unavailable` | Y | Y | Y | N/A | R8 |
      | S9 | Mid-run: parent orchestrated, stage handoff for one action lost | Re-declare inline fallback; stop that action with `dispatch_handoff_unavailable` | Y | Y | Y | N/A | R9 |
      | S10 | Parent orchestrated, reachable stage role, credential/permission/token denial | Unchanged profile; stop that action with `missing_required_secret_or_permission`, naming denied target | Y | Y | Y | N/A | R10 |
      | S10b | Reachable stage role, harness tool or local-path denial (Out of Scope, #1746) | **No named stop and no outcome defined**; must not map to `missing_required_secret_or_permission` or `dispatch_handoff_unavailable`; #1746 callout present | Y | Y | Y | N/A | subcase (non-row) |
      | S11 | No handoff, or **initial handoff unconfirmed**, read-only checkpoint | Inline fallback; observing, complete read-only work, report; record unconfirmed | Y | Y | Y | Y | R11 |
      | S12 | No handoff, or **initial handoff unconfirmed**, would mutate | Inline fallback; observing, report; stop `dispatch_handoff_unavailable`; record unconfirmed | Y | Y | Y | N/A | R12 |
      | S13 | Declaration missing at first mutating action | Stop `dispatch_profile_declaration_missing` before mutating | Y | Y | Y | N/A | R13 |
      | S14 | Profile value outside the three | Same stop; report invalid value and the three valid values | Y | Y | Y | Y | R14 |
      | S15 | No accountable role (incl. empty) | Same stop; report missing role | Y | Y | Y | Y | R15 |
      | S16 | Missing/invalid declaration at a read-only checkpoint | Same stop before reporting or the next action | Y | Y | Y | Y | R16 |
      | S17a | Posture `observing` at a mutating action | Same stop; report invalid posture | Y | Y | Y | N/A | R17 (observing at a mutating action) |
      | S17b | Posture absorbed/handed off at a read-only checkpoint | Same stop; report invalid posture | Y | Y | Y | Y | R17 (absorbed/handed off at a read-only checkpoint) |
      | S18 | Declared **more permissive** than facts assign (native while onward unavailable/unconfirmed or initial unavailable; parent while initial unavailable) | Same stop; report fact and required outcome | Y | Y | Y | Y | R18 (more permissive) |
      | S19 | Declared **less permissive** than facts assign (parent or inline while facts assign native; inline while facts assign parent) | Same stop; report fact and required outcome | Y | Y | Y | Y | R18 (less permissive) |

      **Row identities (spec order)**: R1 native handoff, mutating; R2 native
      handoff, read-only scan; R3 parent orchestrated, mutating; R4 parent
      orchestrated, scan; R5 onward unconfirmed, mutating; R6 onward
      unconfirmed, scan; R7 mid-run native to parent orchestrated; R8 mid-run
      native to inline fallback; R9 mid-run parent orchestrated to inline
      fallback; R10 reachable stage credential/permission/token denial; R11 no
      or unconfirmed initial handoff, read-only; R12 no or unconfirmed initial
      handoff, would mutate; R13 declaration missing at first mutating action;
      R14 profile value outside the three; R15 no accountable role; R16 missing
      or invalid declaration at a read-only checkpoint; R17 posture mismatch
      (both directions in one row); R18 profile/fact mismatch (both directions
      in one row).

      Each expected outcome names its terminal state (proceed, re-declare, or
      stop with the exact stop string) and, for stops, the affected work item and
      human unblocking action from guardrails section 4. S7-S9 and S10 are
      **recovery** rows: they are validated against their own action-specific
      fact and are explicitly **not** rejected by S18/S19 (E4c exemption); the
      simulation includes a scenario proving a S7 re-declaration is not
      treated as a coarse mismatch. Pre-branch `/run-items` stops (S13-S19) also
      assert the single invocation-level affected-item string.
      This is the executable equivalent when live Remote Control is unavailable.
- [ ] **Planted-violation proofs — one per guard branch** (same implementation
      PR). Each branch can go inert while the others keep the suite green, so
      every branch needs its own proof. For each cycle: apply the edit to a
      mirror, run the guard and confirm non-zero exit **and that the failure
      message names that branch/element**, restore, confirm exit 0. Keep every
      other branch intact in each cycle so a non-zero exit proves the targeted
      check fired.
      1. **Link branch**: remove the canonical link from
         `.cursor/commands/run-item.md`.
      2. **Profile-string branch**: corrupt one profile code string in a mirror
         whose link is intact.
      3. **E1 evaluation order**: delete the `only once initial handoff is
         confirmed` sentence from `.claude/commands/run-items.md`.
      4. **E2a onward unconfirmed**: delete the `conservative default` sentence
         from `.agents/skills/run-epic/SKILL.md`.
      5. **E2b initial handoff unconfirmed**: delete the sentence stating that
         unconfirmed initial handoff selects read-only `cursor-inline-fallback`
         from `.cursor/commands/run-item.md` while leaving E2a intact (proves
         E2b is checked independently of E2a); repeat on
         `.cursor/rules/workflow.mdc`.
      6. **E3a stop names**: remove `missing_required_secret_or_permission`
         from `.cursor/commands/run-work.md`; repeat removing
         `dispatch_handoff_unavailable` from Protocol 91.
      7. **E3b affected work item**: remove `explicit_list_invocation_targets=`
         from Protocol 90 (and `guardrails-enforcement.md` row text) while the
         stop names remain.
         Separately remove only the `percent-encoded` token (then only
         `verbatim`) from Protocol 90 and from `run-items` mirrors.
      8. **E3c human unblocking action** (per stop and per cause): from
         `.claude/commands/run-item.md`, remove the unblocking action for
         `dispatch_handoff_unavailable` only while its name and the other two
         actions remain (per-stop checking); then, separately, remove each of
         the three `dispatch_profile_declaration_missing` elements (valid
         profile / named accountable role / posture valid for the checkpoint)
         and the `profile the known facts assign` clause, the
         `explicitly accept the read-only result` alternative and the
         `specific stage role` exception for `dispatch_handoff_unavailable`,
         and the structural-restriction path for
         `missing_required_secret_or_permission`; each removal must fail
         naming the stop and the cause.
      9. **E3d no-named-stop denial treatment**: remove the harness/local-path
         denial paragraph from `.cursor/agents/item-orchestrator.md`, and
         separately remove only the `#1746` token from it.
      10. **E4a/E4b/E4c invalid boundaries**: delete the `coarse-fact mismatch`
          sentence from `.cursor/rules/workflow.mdc`; delete only the
          `less permissive` direction from `.claude/commands/run-epic.md`;
          delete the mid-run-recovery exemption from
          `.agents/skills/run-item/SKILL.md`.
      11. **E5 postures**: delete the `observing` posture line (and,
          separately, the `only at a read-only checkpoint` qualifier, and
          separately the `current checkpoint` sentence) from
          `.cursor/commands/run-item.md`.
      12. **Guardrails clause coverage**: in `guardrails-enforcement.md`
          section 4, separately remove each of E3b, E3d, and the `more
          permissive` direction of E4b, leaving the stop names.
      13. **Protocol E3d**: remove the harness/local-path denial paragraph from
          each of Protocols 90, 91, and 95 in turn (three cycles), leaving the
          stop names, E3b and E3c.
      14. **`agent-model-config.md` rows**: remove one environment row (and,
          separately, the model-assignment cell of one row); expect non-zero.
          Also flip one profile cell to a value Decision 6 does not assign
          (Cloud Agents item layer to `cursor-parent-orchestrated`; Remote
          Control portfolio to `cursor-native-handoff`); expect non-zero, since
          the guard asserts the exact Decision 6 profile per environment and
          layer. Also flip an evidence marker to an overclaim (Remote Control
          epic profile to `confirmed by observation`; Desktop model to
          `confirmed by observation`) and drop one marker; expect non-zero for
          each.
      15. **Canonical-doc checks**: one cycle per check name in Testing Strategy
          (`canonical_layers`, `canonical_matrix`,
          `canonical_declared_not_detected`, one per
          `canonical_handoff_metadata` field including worktree path,
          `canonical_workflow_hub`).
      16. **`simulate_bounded_paths`**: for each **row-backed** scenario (every
          scenario in S1-S19 except S10b, each mapped to a spec row R1-R18),
          alter that decision-gate row in the canonical doc so its expected
          outcome or stop name changes; expect non-zero naming the scenario ID
          and each applicable path. **S10b is excluded from row mutation**: it is
          a subcase with no matrix row, no outcome and no named stop, so its
          proofs mutate the canonical doc's out-of-scope prose instead, one
          mutation per cycle: (a) remove the `#1746` token from the out-of-scope
          paragraph, (b) delete the sentence stating that the harness/local-path
          denial `is not a named stop condition`, and (c) add a statement that
          maps the harness/local-path denial to
          `missing_required_secret_or_permission` or
          `dispatch_handoff_unavailable`; each must fail naming S10b. Separately, for C1-C4: delete
          one canonical row (C1 and C2 fail), add an unmatched extra canonical
          row (C1 fails), remove a scenario's mapping (C3 fails), map S10b to a
          row (C3 fails), and swap two rows' tokens (C4 fails); restore each.

      17. **Selector wiring / header consistency**: remove one path from the
          `# covers:` header, in turn for: one mirror, the merged spec path,
          the canonical guide, and the smoke runbook; expect the guard's
          header-consistency check to fail **and** the selector verification
          (step 3 of Testing Strategy) to show this suite absent from the
          selector output for that path (other suites may still be selected for
          it); restore. **Fixtures-directory glob is different**: removing its
          `# covers:` entry cannot make the suite unselected, because
          `select-test-suites.sh` both auto-covers a suite's own fixture
          directory (`tests/fixtures/<suite-name>/**`) and lists
          `scripts/development-workflow/tests/fixtures/**` in
          `FULL_RUN_TRIGGER_PATTERNS`, so any fixture change short-circuits
          selection to a full run. For that glob the cycle removes the entry,
          expects only the guard's header-consistency check to fail (no
          unselected check), and restores. Also make the guard read one
          undeclared path (a stray file) and expect `read_path()` to fail.

      18. **Dispatch decision (Decision 7)**: in Protocol 90 Step 4 delete the
          new Cursor-scoped paragraph, then (separately) merge its
          parent-orchestrated and stage-delegation clause into the generic
          paragraph, then (separately) alter the generic paragraph, then
          (separately) drop only the `only when a Cursor dispatch profile is
          declared` scoping sentence; expect `protocol90_step4_condition` to
          fail each time; delete
          the Protocol 95 Step 6 Execution arrangement paragraph and expect
          `protocol95_execution_arrangement` to fail; delete the Protocol 91
          absorbed-layer sentence and expect `protocol91_absorbed_layer_sentence`
          to fail; delete the `/run-items` row of the canonical dispatch table
          and expect `canonical_dispatch_decision` to fail; restore each.

      19. **Explicit-list format parity (post-edit)**: change the format string in
          each of the four files in turn (canonical guide, guardrails row,
          Protocol 90, merged spec row) and expect `explicit_list_format_parity`
          to fail naming the file; restore each.

      20. **Cursor scoping (E6)**: delete the `only in a Cursor environment` /
          `other runners are unchanged` sentence from `.claude/commands/run-item.md`,
          then (separately) from `.agents/skills/run-items/SKILL.md`, then from
          Protocol 91; expect non-zero naming E6 each time; also make a
          non-Cursor mirror state the profile as mandatory for every runner and
          expect non-zero.

      **Coverage rules (every branch must have a real cycle).** Each multi-token
      clause is proved token by token: one cycle deletes only one token while
      the rest of the clause remains. Each of cycles 3-11 is repeated once per
      surface class in the table above that carries the clause (command / skill
      mirror, role agent or Codex skill, protocol, `workflow.mdc`), using a
      representative surface of that class; the named surface above is one such
      representative, not the only one. Guardrails classes are covered by cycle
      12. The PR test plan records the resulting clause-by-class matrix with
      the before/after command output of **every** cycle (non-zero exit naming
      the branch or clause, then restore and exit 0). There is no substitute
      for an actual fail/pass cycle: a guard branch that cannot be proved by
      one is **removed from the guard** in the implementation PR rather than
      shipped unproved, and the plan's coverage table is updated to match.

### Database / Backend / Frontend / Infrastructure

- [ ] Not applicable — documentation and a doc-surface test only.

---

## Files to modify (implementation checklist)

Adapter/skill documentation mirrors to edit: **15** paths (5 `.cursor/commands` +
5 `.claude/commands` + 5 `.agents/skills/*/SKILL.md`). The Verification Log `rg`
returns **18** hits = **14** of those mirrors (it misses `.claude/commands/run-epic.md`)
+ **4** `agents/openai.yaml` files that are **not** edited (`14+4=18`).

| Path | Change |
| --- | --- |
| `docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md` | **Create** canonical guide |
| `docs/workflow/development-workflow/guardrails-enforcement.md` | Add stop conditions + affected-item guidance |
| `docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md` | Reference + declaration gate + explicit-list stop + Step 4 condition change (Decision 7) |
| `docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md` | Reference + declaration + summary fields + absorbed-layer sentence (Decision 7) |
| `docs/workflow/development-workflow/protocols/95-run-epic-protocol.md` | Reference + declaration + Step 6 Execution arrangement paragraph (Decision 7) |
| `docs/workflow/development-workflow/agent-model-config.md` | Cursor profile table |
| `docs/workflow/development-workflow/bounded-run-prelude.md` | Ordering note (required, Decision 4) |
| `docs/workflow/development-workflow/README.md` | Integrations list entry |
| `.cursor/commands/run-item.md` | Mirror |
| `.cursor/commands/run-item-work.md` | Mirror (deprecated alias) |
| `.cursor/commands/run-items.md` | Mirror |
| `.cursor/commands/run-epic.md` | Mirror |
| `.cursor/commands/run-work.md` | Mirror |
| `.claude/commands/run-item.md` | Mirror |
| `.claude/commands/run-item-work.md` | Mirror (deprecated alias) |
| `.claude/commands/run-items.md` | Mirror |
| `.claude/commands/run-epic.md` | Mirror |
| `.claude/commands/run-work.md` | Mirror |
| `.agents/skills/run-item/SKILL.md` | Mirror |
| `.agents/skills/run-item-work/SKILL.md` | Mirror (deprecated alias) |
| `.agents/skills/run-items/SKILL.md` | Mirror |
| `.agents/skills/run-epic/SKILL.md` | Mirror |
| `.agents/skills/run-work/SKILL.md` | Mirror |
| `.cursor/agents/orchestrator.md` | No-handoff + profile |
| `.cursor/agents/item-orchestrator.md` | No-handoff + profile |
| `.claude/agents/orchestrator.md` | Parity |
| `.claude/agents/item-orchestrator.md` | Parity |
| `.codex/skills/workflow-item-orchestrator/SKILL.md` | Canonical reference + item-layer no-onward-handoff |
| `.codex/skills/workflow-orchestrator/SKILL.md` | Canonical reference + portfolio-layer no-onward-handoff |
| `.cursor/rules/workflow.mdc` | Requirement + link |
| `docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md` | Named stop affected-item alignment |
| `scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh` | **Create** surface guard (link, profile string, clauses E1-E6, canonical-doc checks, path simulation, `--self-test`) with `# covers:` header for every protected surface |
| `scripts/development-workflow/tests/fixtures/cursor-dispatch-profile-surfaces/` | **Create** scanner self-test fixtures: exactly the fixture manifest, one `*.fixture.md` file per manifest row (`MANIFEST_COUNT`) |
| `changelog.d/1462.added.cursor-dispatch-profiles.md` | **Create** release-note fragment (implementation PR only) |
| `docs/testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md` | Created in Plan Ready; Steps 12-14, real-command invocations (router-resolvable targets, `--epic <N>`) and tightened Pass criteria added in plan review (no further edit expected) |

**Explicitly not in scope**: `REVIEW.md` checklist categories (no new review
gate category); `--dispatch-profile` CLI flag (BO-9); automated environment
detection; stage-role permission denial recovery (#1746); enforcing
`BATCH_CONTEXT` marker absence as a stage stop (#1745).

---

## Parser-Risk Addendum (surface-guard scanner)

The surface guard is a structured-Markdown scanner: it reads Markdown files,
extracts scoped content, and decides pass/fail by fixed-string and same-paragraph
matches. Scanner rules: (R1) read UTF-8 text; (R2) strip fenced code blocks and
HTML comments before matching (the Decision 3 declaration block and worked
examples are illustrative and must not satisfy a clause). Fence semantics
follow CommonMark: an opening fence is a run of **3 or more** backticks or of
**3 or more** tildes, preceded by **at most 3 spaces** of indentation (4+
spaces is an indented code block or list continuation, not a fence; a fence
inside a list item may be indented relative to that item's content); a
backtick fence's info string may not contain a backtick. The closing fence
must use the **same character** as the opener, be a run **at least as long**
as the opener (longer closers are valid), be indented at most 3 spaces, and
carry no info string. A fence of the other character, or a shorter run, is
content, not a closer. An **unclosed** fence runs to **end of file** and
everything after the opener is stripped. HTML comments run from `<!--` to
`-->`, or to end of file if unclosed;
(R2b) **indented code blocks are stripped too**, per CommonMark: a line indented
**4 or more spaces (or a tab)** relative to the enclosing container starts an
indented code block only when it is **not** a paragraph continuation (an
indented line directly after a paragraph line, with no blank line between,
cannot interrupt the paragraph and is prose) and is **not** a list-item
continuation (inside a list item the threshold is the item's content offset
plus 4, so a line indented only to the content offset, or 4+ spaces under a
list marker that has not yet reached that offset plus 4, is item prose). The
block continues through further lines indented 4+ (blank lines between such
lines stay inside the block) and ends at the first non-blank line indented
less than 4; it also starts after a heading, thematic break, fenced block, or
blank line. Blockquote content is evaluated after removing `>` markers, so
code inside a quote is stripped by the same rules;
(R2c) other constructs, each decided explicitly. **Counts as prose**:
blockquote text, table cells (a row is one block for R3), list items, headings,
link text, and inline HTML tag *text* (tags removed). **Counts for identifier
tokens only** (R4): inline code spans, because stop names and profile codes are
conventionally written as code; a prose phrase (E1-E6 sentences, `treated as
unavailable`, and similar) that appears only inside an inline code span does
**not** count. **Never counts**: link-reference definitions (`[label]: url
"title"`, whole line), link and image destinations and titles, image alt text,
autolinks, `<pre>` and `<code>` HTML blocks, and backslash-escaped identifiers
(`dispatch\_handoff\_unavailable` is not the token; entities are not decoded);
(R3) normalize each
paragraph by joining soft-wrapped lines and collapsing whitespace, so phrases
wrapped across lines still match and "same paragraph" means one blank-line-
delimited block (each list item, each blockquote paragraph, and each **table
row** counts as one block). **Table block boundary, decided once**: a table
row is one block, with its cells joined by a single space (the header row and
the `---` separator row are not blocks). Justification: the decision-gate
matrix and the simulation's C4 check need a row's input, outcome, next action
and stop name, which live in separate cells of one row, to satisfy a
same-block assertion together. Tokens in different rows are never in the same
block, and cells are never separate blocks; (R4) identifier tokens (stop names, profile codes) match only with
non-identifier characters or edges on both sides; prose phrases match
case-sensitively as fixed strings; (R5) every assertion runs on the surface's
own content, never a concatenation of files.

Each manifest row below maps to one fixture file under
`scripts/development-workflow/tests/fixtures/cursor-dispatch-profile-surfaces/`
and to a self-test (`test-cursor-dispatch-profile-surfaces.sh --self-test`,
also invoked by the default run). Each fail fixture must exit non-zero with a
message naming its clause ID; each pass fixture must exit 0. These are separate
from, and in addition to, the planted-deletion proofs on real surfaces.

**Fixture manifest (`MANIFEST_COUNT = 158`).** This is the literal, complete
list of scanner fixtures: one row per file, exact filename, expected result,
and the rule or clause covered. It is derived by counting the rows below and
is stated here **once**; every other mention refers to "the manifest count".
Every fixture is a single Markdown file in
`scripts/development-workflow/tests/fixtures/cursor-dispatch-profile-surfaces/`
named after its manifest ID with the suffix `.fixture.md`. The surface class the scanner applies is derived from
the ID prefix: `class-protocol-*` is a protocol, `class-guardrails-*` and
`e3c-*` are guardrails, `class-model-config-*` is `agent-model-config.md`,
`sim-*`, `ser-*`, `serialization-*` and `canonical-*` are the canonical doc,
`proto90-*`, `proto91-*` and `proto95-*` are the corresponding protocol, `parity-*` are the canonical doc, and
every other prefix is a command mirror. Expected `pass` means exit 0; expected
`fail: <check>` means non-zero exit whose message names `<check>` (a scanner
rule, clause ID, scenario ID, simulation check, or serialization rule).
Independent alternatives are separate rows (no row combines alternatives).

| # | Fixture file | Expected | Covers | Case |
| --- | --- | --- | --- | --- |
| 1 | `boundary-token-first-byte.fixture.md` | pass | R1, R4 | Required token at the first byte of the file |
| 2 | `boundary-token-last-byte-no-newline.fixture.md` | pass | R1, R4 | Required token at the last byte, no trailing newline |
| 3 | `boundary-wrapped-phrase.fixture.md` | pass | R1, R3, R4 | Required phrase soft-wrapped across two lines |
| 4 | `boundary-token-punctuation.fixture.md` | pass | R4 | Identifier token followed by a comma or period |
| 5 | `boundary-token-backtick.fixture.md` | pass | R4, R2c | Identifier token wrapped in backticks |
| 6 | `boundary-empty-file.fixture.md` | fail: E1-E6 each named | E1-E6 | Empty file |
| 7 | `boundary-link-only.fixture.md` | fail: E1-E6 each named | E1-E6 | File containing only the canonical link |
| 8 | `lookalike-longer-stop-name.fixture.md` | fail: R4 | R4 | `dispatch_handoff_unavailable_x` in place of the stop name |
| 9 | `lookalike-longer-profile-code.fixture.md` | fail: R4 | R4 | `cursor-native-handoffs` in place of the profile code |
| 10 | `lookalike-case-posture.fixture.md` | fail: E5 | R4, E5 | `Observing` in place of the posture label |
| 11 | `lookalike-case-stop-name.fixture.md` | fail: E3a | R4, E3a | `DISPATCH_HANDOFF_UNAVAILABLE` in place of the stop name |
| 12 | `lookalike-fenced-block.fixture.md` | fail: R2 | R2 | Required token only inside a fenced code block |
| 13 | `lookalike-html-comment.fixture.md` | fail: R2 | R2 | Required token only inside an HTML comment |
| 14 | `lookalike-observing-word.fixture.md` | fail: E5 | R2-R5 | `observing` only as an unrelated word (`observing the output`) without posture phrase |
| 15 | `lookalike-split-paragraph.fixture.md` | fail: R3 | R2-R5 | E2b tokens present but in different paragraphs (read-only in one, inline-fallback in another) |
| 16 | `multi-token-many-clause-met.fixture.md` | pass | R5 | Token appears many times; the clause it belongs to is met |
| 17 | `multi-token-many-clause-unmet.fixture.md` | fail: the unmet clause | R5 | Same file; a different clause is unmet |
| 18 | `multi-cross-surface-a-present.fixture.md` | pass | R5 | Surface A carries the token |
| 19 | `multi-cross-surface-b-absent.fixture.md` | fail: R5 | R5 | Surface B lacks the token that A carries |
| 20 | `multi-partial-actions.fixture.md` | fail: E3c | R5 | Two of three stop actions present, one missing |
| 21 | `multi-duplicate-link.fixture.md` | pass | R5 | Duplicate canonical link lines |
| 22 | `nested-clause-list-item.fixture.md` | pass | R3 | Clause inside a list item |
| 23 | `nested-clause-blockquote.fixture.md` | pass | R3 | Clause inside a blockquote |
| 24 | `nested-clause-table-cell.fixture.md` | pass | R3 | Clause inside a table cell (row block) |
| 25 | `nested-fenced-in-list.fixture.md` | fail: R2 | R3, R2 | Required phrase inside a fenced block nested in a list item |
| 26 | `fence-tilde.fixture.md` | fail: R2 | R2 | Required token only inside a tilde (`~~~`) fence |
| 27 | `fence-tilde-longer-closer.fixture.md` | pass | R2 | Tilde fence closed by a longer tilde run; token after the closer |
| 28 | `fence-backtick-longer-closer.fixture.md` | pass | R2 | Backtick fence (3) closed by a longer backtick run (5); token after closer |
| 29 | `fence-shorter-closer-inside.fixture.md` | fail: R2 | R2 | 4-backtick opener; inner 3-backtick line does not close; token after inner line still inside |
| 30 | `fence-mismatched-char-closer.fixture.md` | fail: R2 | R2 | Backtick fence closed by a tilde run (mismatched character); token after it still inside |
| 31 | `fence-unclosed-eof.fixture.md` | fail: R2 | R2 | Unclosed fence at EOF with required token after opener |
| 32 | `fence-unclosed-token-before.fixture.md` | pass | R2 | Unclosed fence at EOF, required token **before** the opener |
| 33 | `fence-indent-3.fixture.md` | fail: R2 | R2 | Fence opener indented 3 spaces (is a fence) with token inside |
| 34 | `fence-indent-4.fixture.md` | pass | R2 | Opener line indented 4 spaces after a blank line (indented code, not a fence); token on a later **unindented** line |
| 35 | `indented-code-token.fixture.md` | fail: R2b | R2b | Required token on a line indented 4 spaces after a blank line |
| 36 | `indented-code-tab.fixture.md` | fail: R2b | R2b | Same, indented with a tab |
| 37 | `indented-code-after-heading.fixture.md` | fail: R2b | R2b | Indented block after a heading |
| 38 | `indented-code-multi-blank.fixture.md` | fail: R2b | R2b | Blank line inside an indented block; token in the second chunk |
| 39 | `indented-code-paragraph-continuation.fixture.md` | pass | R2b | 4-space-indented line directly after a paragraph line (no blank): paragraph continuation |
| 40 | `indented-code-list-continuation.fixture.md` | pass | R2b | Line indented to a list item's content offset (not +4) |
| 41 | `indented-code-in-list.fixture.md` | fail: R2b | R2b | Line indented content offset + 4 inside a list item after a blank line |
| 42 | `indented-code-blockquote.fixture.md` | fail: R2b | R2b | Indented code inside a blockquote (`>` plus 4 spaces) |
| 43 | `construct-blockquote-prose.fixture.md` | pass | R2c, R3 | Clause sentence inside a blockquote |
| 44 | `construct-table-cell.fixture.md` | pass | R2c, R3 | Clause sentence in a table cell (one row is one block) |
| 45 | `table-row-spans-cells.fixture.md` | pass | R2c, R3 | E2b tokens split across two cells of the same table row |
| 46 | `table-rows-split.fixture.md` | fail: R3 | R2c, R3 | E2b tokens in two adjacent table rows |
| 47 | `table-header-separator.fixture.md` | fail: R3 | R2c, R3 | Token only in a table header or `---` separator row |
| 48 | `construct-linkref-def.fixture.md` | fail: R2c | R2c, R3 | Token only in a link-reference definition title |
| 49 | `construct-link-destination.fixture.md` | fail: R2c | R2c | Token only in a link destination |
| 50 | `construct-image-alt.fixture.md` | fail: R2c | R2c | Token only in image alt text |
| 51 | `construct-code-span-identifier.fixture.md` | pass | R2c, R3 | Identifier token in an inline code span |
| 52 | `construct-code-span-phrase.fixture.md` | fail: R2c | R2c, R3 | Prose phrase only inside an inline code span |
| 53 | `construct-pre-block.fixture.md` | fail: R2c | R2c, R3 | Token only inside a `<pre>` HTML block |
| 54 | `construct-escaped-identifier.fixture.md` | fail: R2c, R4 | R2c, R3 | Backslash-escaped identifier (`dispatch\_handoff\_unavailable`) |
| 55 | `fence-closer-indent-4.fixture.md` | fail: R2 | R2 | Closer indented 4 spaces does not close; token after it still inside |
| 56 | `comment-unclosed-eof.fixture.md` | fail: R2 | R2 | Unclosed HTML comment at EOF with token after `<!--` |
| 57 | `overlap-substring.fixture.md` | fail: E1 | R3, R2 | Overlapping phrases (`initial handoff` inside `only once initial handoff is confirmed`) with only the shorter present |
| 58 | `overlap-e2a-deleted.fixture.md` | fail: E2a | E2a, E2b | E2a sentence deleted, E2b intact, shared tokens |
| 59 | `overlap-e2b-deleted.fixture.md` | fail: E2b | E2a, E2b | E2b sentence deleted, E2a intact, shared tokens |
| 60 | `sim-row-count-matches-spec.fixture.md` | pass | Simulation C1-C4 | Canonical-doc fixture that matches the spec's 18 rows exactly (no per-scenario extras) |
| 61 | `sim-missing-row-r5.fixture.md` | fail: C1, C2 | Simulation C1-C4 | Canonical-doc fixture missing the R5 row (onward unconfirmed) |
| 62 | `sim-extra-row.fixture.md` | fail: C1 | Simulation C1-C4 | Canonical-doc fixture with a 19th row added |
| 63 | `sim-unmapped-scenario.fixture.md` | fail: C3 | C3 | A scenario with no row mapping and not flagged subcase |
| 64 | `sim-s10b-mapped-to-row.fixture.md` | fail: C3 | C3 | S10b (subcase) mapped to a matrix row |
| 65 | `sim-rows-swapped.fixture.md` | fail: C4 | Simulation C1-C4 | Two rows' tokens swapped |
| 66 | `sim-wrong-stop-s12.fixture.md` | fail: S12 | Simulation C1-C4 | Fixture whose S12 row says `dispatch_profile_declaration_missing` instead of `dispatch_handoff_unavailable` |
| 67 | `sim-recovery-rejected-s7.fixture.md` | fail: E4c | Simulation C1-C4 | Fixture where S7 recovery re-declaration is described as a coarse mismatch |
| 68 | `sim-harness-denial-mapped-s10b.fixture.md` | fail: S10b | Simulation C1-C4 | Fixture mapping harness denial (S10b) to `missing_required_secret_or_permission` |
| 69 | `serialization-mixed-forms.fixture.md` | pass | Serialization | Router-accepted forms shown as typed (`#1462`, `feature/x`, `1771`, and a development-folder path) |
| 70 | `serialization-hash-added.fixture.md` | fail: verbatim | Serialization | Example adds `#` to `1771` |
| 71 | `serialization-hash-stripped.fixture.md` | fail: verbatim | Serialization | Example strips `#` from `#1462` |
| 72 | `class-protocol-missing-e3d.fixture.md` | fail: E3d | Surface-class table | Protocol fixture lacking only E3d (all other clauses present) |
| 73 | `class-guardrails-exempt-clauses.fixture.md` | pass | Surface-class table | Guardrails fixture carrying only its `Y` clauses (no E1, E2, E4c, E5) |
| 74 | `class-guardrails-missing-e4b.fixture.md` | fail: E4b | Surface-class table | Guardrails fixture lacking E4b `less permissive` direction |
| 75 | `class-model-config-missing-row.fixture.md` | fail: model-config rows | Surface-class table | `agent-model-config.md` fixture missing one environment row |
| 76 | `class-model-config-rc-epic-overclaimed.fixture.md` | fail: evidence-marker | Surface-class table | `agent-model-config.md` fixture marking the Remote Control epic profile `confirmed by observation` |
| 77 | `class-model-config-desktop-model-overclaimed.fixture.md` | fail: evidence-marker | Surface-class table | `agent-model-config.md` fixture marking the Desktop model `confirmed by observation` |
| 78 | `class-model-config-marker-absent.fixture.md` | fail: evidence-marker | Surface-class table | `agent-model-config.md` fixture with a cell that carries neither marker |
| 79 | `e3c-stop1-profile-only.fixture.md` | fail: E3c stop 1 | E3c | Stop-1 action mentions only "declare one of the three profiles" (no role, posture, or facts-assigned profile) |
| 80 | `e3c-stop1-no-posture.fixture.md` | fail: E3c stop 1 | E3c | Stop-1 action lacking only the posture element |
| 81 | `e3c-stop1-no-role.fixture.md` | fail: E3c stop 1 | E3c | Stop-1 action lacking only the named-accountable-role element |
| 82 | `e3c-stop1-no-facts-profile.fixture.md` | fail: E3c stop 1 | E3c | Stop-1 action lacking the `profile the known facts assign` clause |
| 83 | `e3c-stop2-no-stage-role-exception.fixture.md` | fail: E3c stop 2 | E3c | Stop-2 action lacks the `specific stage role` exception |
| 84 | `e3c-stop2-no-accept-read-only.fixture.md` | fail: E3c stop 2 | E3c | Stop-2 action lacks the accept-read-only alternative |
| 85 | `e3c-stop3-no-structural-path.fixture.md` | fail: E3c stop 3 | E3c | Stop-3 action lacking the structural-restriction path |
| 86 | `e3c-all-causes-present.fixture.md` | pass | E3c | All three stop actions cause-complete |
| 87 | `ser-percent-alone.fixture.md` | pass | Serialization | Branch `feature/100%-done` encoded `feature/100%25-done` |
| 88 | `ser-percent-preexisting.fixture.md` | pass | Serialization | Branch `feature/a%25b` encoded `feature/a%2525b` (no double-encode skip) |
| 89 | `ser-interior-tab.fixture.md` | pass | Serialization | Defensive: interior tab in a development-folder path encoded `%09` |
| 90 | `ser-interior-space.fixture.md` | pass | Serialization | Defensive: interior space in a development-folder path encoded `%20` |
| 91 | `ser-newline-unreachable-stated.fixture.md` | pass | Serialization | Doc states a line feed cannot appear inside a target (the router keeps only the first line of an argument) and is never encoded |
| 92 | `ser-newline-encoded-shown.fixture.md` | fail: router-grammar | Serialization | Doc shows an interior newline encoded `%0A` as a reachable case |
| 93 | `ser-interior-cr.fixture.md` | pass | Serialization | Defensive: interior CR in a development-folder path encoded `%0D` (the router keeps CR inside the token) |
| 94 | `ser-control-0x1f.fixture.md` | pass | Serialization | Defensive: control character 0x1F in a development-folder path encoded `%1F` |
| 95 | `ser-control-0x7f.fixture.md` | pass | Serialization | Defensive: control character 0x7F in a development-folder path encoded `%7F` |
| 96 | `ser-lowercase-hex.fixture.md` | fail: uppercase-hex | Serialization | Lowercase hex (`%2c`, `%0a`) in the example |
| 97 | `ser-non-ascii-unchanged.fixture.md` | pass | Serialization | Non-ASCII UTF-8 byte sequence emitted unchanged |
| 98 | `ser-edge-trim-only.fixture.md` | pass | Serialization | Leading and trailing whitespace trimmed, interior kept and encoded |
| 99 | `ser-interior-trimmed.fixture.md` | fail: edge-trim-only | Serialization | Interior whitespace trimmed away (over-trim) |
| 100 | `ser-edge-encoded.fixture.md` | fail: edge-trim-only | Serialization | Edge whitespace encoded instead of trimmed |
| 101 | `ser-order-preserved.fixture.md` | pass | Serialization | Router-normalized order preserved (`feature/b,1771,#1462` for that input order) |
| 102 | `ser-order-sorted.fixture.md` | fail: order-preserved | Serialization | Targets sorted instead of kept in router order |
| 103 | `ser-delimiter-space.fixture.md` | fail: delimiter | Serialization | Delimiter with a space (`a, b`) |
| 104 | `ser-single-target-rendered.fixture.md` | fail: unreachable-forms | Serialization | Single-target form rendered in the doc |
| 105 | `ser-empty-target-rendered.fixture.md` | fail: unreachable-forms | Serialization | Empty target rendered (`a,,b`) |
| 106 | `ser-unreachable-stated.fixture.md` | pass | Serialization | Doc states single and empty targets are unreachable |
| 107 | `ser-case-rewritten.fixture.md` | fail: verbatim | Serialization | `feature/Cursor-Dispatch` rewritten in lowercase |
| 108 | `ser-slash-rewritten.fixture.md` | fail: verbatim | Serialization | `/` in a branch name rewritten |
| 109 | `ser-comma-not-in-target.fixture.md` | pass | Serialization | Doc states a comma cannot occur inside an accepted target (router splits on commas) and the `%2C` rule is defensive only |
| 110 | `ser-comma-target-rendered.fixture.md` | fail: router-grammar | Serialization | Doc example shows a comma inside an accepted target (`feature/x%2Cy`) |
| 111 | `ser-percent-not-reencoded.fixture.md` | fail: percent-encoding | Serialization | Doc shows `feature/a%25b` emitted unchanged |
| 112 | `ser-duplicates-deduped-first-kept.fixture.md` | pass | Serialization | Doc example: repeated `#1462` in the input rendered once, first occurrence kept |
| 113 | `ser-duplicates-rendered.fixture.md` | fail: router-grammar | Serialization | Doc example renders a repeated target (`#1462,...,#1462`) |
| 114 | `ser-hash-and-bare-distinct.fixture.md` | pass | Serialization | Doc example renders `1462` and `#1462` as two distinct targets, as typed |
| 115 | `ser-hash-and-bare-deduped.fixture.md` | fail: router-grammar | Serialization | Doc example merges `1462` and `#1462` into one target |
| 116 | `ser-tracker-id-accepted.fixture.md` | fail: router-grammar | Serialization | Doc shows a tracker ID such as `ENG-123` as an accepted target |
| 117 | `ser-tracker-id-unreachable-stated.fixture.md` | pass | Serialization | Doc states a tracker ID stops at `MODE=ambiguous` before the gate and has no serialization |
| 118 | `ser-router-grammar-stated.fixture.md` | pass | Serialization | Doc states the router grammar: comma split, trim, drop empties, first-occurrence dedup, and the accepted forms |
| 119 | `ser-dot-slash-kept.fixture.md` | pass | Serialization | Development-folder path typed `./docs/specs/developments/x` kept with its leading `./` |
| 120 | `ser-dot-slash-stripped.fixture.md` | fail: verbatim | Serialization | Leading `./` stripped from a development-folder path |
| 121 | `clause-all-present.fixture.md` | pass | E1-E6 | All E1-E6 clauses present on a command mirror |
| 122 | `clause-missing-e1.fixture.md` | fail: E1 | Clause completeness | Exactly clause E1 removed from an otherwise complete mirror |
| 123 | `clause-missing-e2a.fixture.md` | fail: E2a | Clause completeness | Exactly clause E2a removed from an otherwise complete mirror |
| 124 | `clause-missing-e2b.fixture.md` | fail: E2b | Clause completeness | Exactly clause E2b removed from an otherwise complete mirror |
| 125 | `clause-missing-e3a.fixture.md` | fail: E3a | Clause completeness | Exactly clause E3a removed from an otherwise complete mirror |
| 126 | `clause-missing-e3b.fixture.md` | fail: E3b | Clause completeness | Exactly clause E3b removed from an otherwise complete mirror |
| 127 | `clause-missing-e3c.fixture.md` | fail: E3c | Clause completeness | Exactly clause E3c removed from an otherwise complete mirror |
| 128 | `clause-missing-e3d.fixture.md` | fail: E3d | Clause completeness | Exactly clause E3D removed from an otherwise complete mirror |
| 129 | `clause-missing-e4a.fixture.md` | fail: E4a | Clause completeness | Exactly clause E4a removed from an otherwise complete mirror |
| 130 | `clause-missing-e4b.fixture.md` | fail: E4b | Clause completeness | Exactly clause E4b removed from an otherwise complete mirror |
| 131 | `clause-missing-e4c.fixture.md` | fail: E4c | Clause completeness | Exactly clause E4c removed from an otherwise complete mirror |
| 132 | `clause-missing-e5.fixture.md` | fail: E5 | Clause completeness | Exactly clause E5 removed from an otherwise complete mirror |
| 133 | `clause-missing-e6.fixture.md` | fail: E6 | Clause completeness | Exactly clause E6 removed from an otherwise complete mirror |
| 134 | `scope-non-cursor-behavior-changed.fixture.md` | fail: E6 | Clause completeness | A Claude Code or Codex mirror that requires a Cursor dispatch profile from non-Cursor runs (no Cursor scoping) |
| 135 | `r1-utf8-bom.fixture.md` | pass | R1 | UTF-8 file with a BOM before the token |
| 136 | `r1-utf8-multibyte.fixture.md` | pass | R1 | Multibyte characters around the token |
| 137 | `r1-invalid-utf8.fixture.md` | fail: R1 | R1 | File that is not valid UTF-8 |
| 138 | `r3-whitespace-collapse.fixture.md` | pass | R3 | Tabs and repeated spaces inside a required phrase |
| 139 | `r4-prefix-identifier.fixture.md` | fail: R4 | R4 | Identifier preceded by an identifier character (`xdispatch_handoff_unavailable`) |
| 140 | `construct-list-item.fixture.md` | pass | R2c | Clause in a list item |
| 141 | `construct-heading.fixture.md` | pass | R2c | Clause in a heading |
| 142 | `construct-link-text.fixture.md` | pass | R2c | Clause in link text |
| 143 | `construct-inline-html-text.fixture.md` | pass | R2c | Token in inline HTML tag text (`<em>...</em>`) |
| 144 | `construct-autolink.fixture.md` | fail: R2c | R2c | Token only in an autolink |
| 145 | `construct-code-html-block.fixture.md` | fail: R2c | R2c | Token only in a `<code>` HTML block |
| 146 | `construct-entity-not-decoded.fixture.md` | fail: R2c, R4 | R2c | HTML entity for an underscore in a stop name (entities not decoded) |
| 147 | `sim-path-applicability-not-asserted.fixture.md` | pass | Simulation | N/A scenario/path pair is not asserted |
| 148 | `sim-path-applicability-asserted-na.fixture.md` | fail: applicability | Simulation | N/A scenario/path pair is asserted |
| 149 | `proto90-step4-condition-present.fixture.md` | pass | Protocol Step 4 | Protocol 90 Step 4 keeps the generic paragraph unchanged and carries the new Cursor-scoped paragraph (all tokens in one block) |
| 150 | `proto90-step4-native-only.fixture.md` | fail: protocol90_step4_condition | Protocol Step 4 | Protocol 90 Step 4 block with only the generic `does not support Work Item Runner handoff natively` paragraph (new Cursor-scoped paragraph absent) |
| 151 | `proto90-step4-generic-merged.fixture.md` | fail: protocol90_step4_condition | Protocol Step 4 | Generic paragraph merged with the parent-orchestrated and stage-delegation clause (one combined condition) |
| 152 | `proto90-step4-generic-altered.fixture.md` | fail: protocol90_step4_condition | Protocol Step 4 | Generic paragraph altered or removed |
| 153 | `proto90-step4-unscoped-stage-rule.fixture.md` | fail: protocol90_step4_condition | Protocol Step 4 | New paragraph lacks the `only when a Cursor dispatch profile is declared` scoping |
| 154 | `proto95-arrangement-missing.fixture.md` | fail: protocol95_execution_arrangement | Protocol Step 4 | Protocol 95 Step 6 without the Execution arrangement paragraph |
| 155 | `proto91-absorbed-sentence-missing.fixture.md` | fail: protocol91_absorbed_layer_sentence | Protocol Step 4 | Protocol 91 without the absorbed-layer sentence |
| 156 | `canonical-dispatch-table-missing.fixture.md` | fail: canonical_dispatch_decision | Protocol Step 4 | Canonical doc without the per-command dispatch table row for `/run-items` |
| 157 | `parity-explicit-list-format-match.fixture.md` | pass | Explicit-list parity | Canonical guide, guardrails row, Protocol 90 and spec row all carry the identical format string |
| 158 | `parity-guardrails-mismatch.fixture.md` | fail: explicit_list_format_parity | Explicit-list parity | Guardrails row carries a different format string than the canonical guide |

**Coverage completeness map.** Every enumerated contract list has a fixture or
proof. The self-test asserts that the on-disk fixture set **equals the
manifest exactly**: (a) the number of `*.fixture.md` files equals the manifest
count, (b) every manifest filename exists on disk, (c) no file exists on disk
that is not in the manifest, and (d) no filename appears twice; the manifest is
embedded in the guard script and its row count is asserted against the constant
`MANIFEST_COUNT` from the manifest heading. A removed, renamed, added or
duplicated fixture fails the self-test. The family prefixes in the map below
(`clause-`, `ser-`, and so on) are prefix filters over manifest rows; the
self-test also asserts each prefix matches at least one manifest row and every
manifest row matches at least one prefix family.

| Enumerated list | Covered by |
| --- | --- |
| Mirror contract E1, E2a, E2b, E3a-E3d, E4a-E4c, E5, E6 | `clause-*` and `e3c-*` fixtures plus proof cycles 3-11, 12-14 and 20 |
| Serialization rules (router grammar and normalization, verbatim tokens, delimiter, comma unreachable, percent-first, defensive whitespace and control encoding, line feed unreachable, uppercase hex, non-ASCII, router dedup, order, one line, single/empty unreachable, tracker ID not accepted) | `ser-*` and `serialization-*` fixtures |
| Scanner rules R1, R2, R2b, R2c, R3, R4, R5 | `r1-*`, `fence-*`, `indented-code-*`, `construct-*`, `boundary-*`, `lookalike-*`, `multi-*`, `nested-*`, `overlap-*`, `r3-*`, `r4-*`, `table-*`, `comment-*` fixtures (table row is the single R3 block boundary) |
| Spec matrix rows R1-R18 and scenarios S1-S19 (21 scenarios incl. S10b subcase) | assertions C1-C4 (row count against the spec, row-to-scenario mapping), proof cycle 16 (one mutation per scenario plus C1-C4 cycles), `sim-*` fixtures |
| Surface classes | `class-*` fixtures and proof cycles 12-14 |
| Dispatch decision (Decision 7): Protocol 90 Step 4 condition, Protocol 91 sentence, Protocol 95 Execution arrangement, canonical dispatch table | `proto90-*`, `proto91-*`, `proto95-*`, `canonical-*` fixtures and proof cycle 18 |
| Explicit-list format parity across canonical guide, guardrails, Protocol 90 and spec row | `parity-*` fixtures and proof cycle 19 |
| CI wiring header and complete read set (including the merged spec and fixtures glob) | proof cycle 17, header-consistency check (`covers == read set + selection-only`) |


Fixture-only self-tests are the regression net for the scanner itself; the
exact-equality assertion above (manifest count and names) is what fails when a
fixture is removed, renamed, or added without a manifest row.

---

## Testing Strategy

**Test types**: Shell surface guard, markdown lint, manual smoke (documentation).

**Key scenarios**:

1. Every mirror surface links to `cursor-dispatch-profiles.md`, names the three
   profile code values consistently (AC18), and carries each required
   mirror-content element E1-E6 (AC10, AC11, AC20); each element has a
   planted-violation proof.
2. Guardrails section 4 lists both new stop conditions with definitions matching
   the spec matrix (AC10–AC12), including coarse-facts mismatch rejection in both
   directions (more and less permissive than assigned outcome).
3. Orchestration role agents instruct return-to-invoker when onward handoff is
   unavailable (AC13).
4. Agent-model-config states, for each Cursor environment and layer, the
   profile, the model assignment (Decision 6 values), and confirmed vs
   assumption (AC15).
5. Smoke runbook walks Native handoff desktop, Parent orchestrated Remote
   Control, Inline fallback, and read-only scan paths (AC6, AC17); Step 8 (a
   real Remote Control `/run-item` to a terminal state) is **required live
   evidence** for `/run-item`, and Step 13 Part B (`/run-items`, terminal
   condition = the completed one-at-a-time run or a named stop) and Step 14 Part
   B (`/run-epic --epic <E>`, terminal condition = a `continuation` outcome of
   `complete` or `needs_resolution` with its named stop, or a named stop) are
   required live Remote Control evidence for the other two bounded commands
   (AC17 behavioral guarantee; NOT RUN blocks sign-off). Steps 12, 13 Part A and
   14 Part A additionally require current-head evidence that the
   `simulate_bounded_paths` result validates the **decision matrix** for
   `/run-item`, `/run-items`, and `/run-epic` (AC9, AC10, AC14, AC17); the
   simulation is mandatory but never substitutes for the live parts, and the
   live parts never substitute for it. The live parts run **only** against the
   smoke runbook's disposable sandbox artifacts (sandbox repository, `[SANDBOX-1462]`
   test issues and epic, sandbox `develop` as the safe base) with a completed
   cleanup checklist; the evidence is the implementation head **H** plus a
   single sandbox-only config commit **S** whose diff against H touches only
   `.ai-dev-workflow.yaml` (`git diff H S --stat`; it changes only five keys: the sandbox
   `issue_tracker.project_number`, `guardrails.mode: assisted` and the three
   `may_merge_pr: false`, so worktrees created from sandbox `develop` inherit a
   no-merge policy and a sandbox-only tracker Project); running them against real backlog items or the real
   repository is prohibited.
6. Smoke Step 10 (AC19): parent-orchestrated inline-product-work prohibition is
   not relaxed by any other document; #1746 remains Out of Scope;
   `SUBAGENT_PERMISSION_DENIAL` is worded as observably similar only (Work Item
   Runner boundary).
7. Smoke Step 11 (AC20): three accountability postures are defined; `observing`
   is valid only at read-only checkpoints; posture mismatch is treated as a
   missing declaration.

**Canonical-document coverage for AC2, AC3, AC5, AC7, AC8**: the surface guard
gains a canonical-doc branch, and each requirement has a named check that
fails when unmet (each with a planted-violation cycle: delete the section,
confirm non-zero exit naming the check, restore):

| AC | Check name in guard | Fails when the canonical doc lacks |
| --- | --- | --- |
| AC2 | `canonical_layers` | the three layer headings (portfolio, epic, item) each stating governing contract, entering commands, and constrained-environment behavior |
| AC3 | `canonical_matrix` | the perform / hand off / prohibit matrix with one row per layer, each row linking a role contract or protocol |
| AC5 | `canonical_declared_not_detected` | the decision-indicator list and the sentence that the decision is declared rather than automatically detected |
| AC7 | `canonical_handoff_metadata` | one assertion per handoff field, failing if any is absent (each field gets a planted-violation cycle, including worktree path): `BATCH_CONTEXT`, isolation classification (`isolation`), **expected worktree path** (spec AC7 and Protocol 91 isolation handoff), expected branch, approved base, artifact repository root, mutation class |
| Decision 7 | `protocol90_step4_condition`, `protocol95_execution_arrangement`, `protocol91_absorbed_layer_sentence`, `canonical_dispatch_decision` | Canonical doc lacks the per-command dispatch table (Decision 7; tokens `absorbs the portfolio layer`, `dispatches no Work Item Runner`, one row per `/run-item`, `/run-items`, `/run-epic`, `/run-work`); Protocol 90 Step 4 fails `protocol90_step4_condition` when any of: the existing generic paragraph (`If the runner does **not** support Work Item Runner handoff natively, ...`) is absent or altered, or contains `stage role`, `cursor-parent-orchestrated` or `Cursor` (it must stay separate and unchanged); the new paragraph is absent; the new paragraph lacks any of `cursor-parent-orchestrated`, `do not dispatch Work Item Runners`, `one at a time`, `absorbed the portfolio layer`, `stage role`, `only when a Cursor dispatch profile is declared` in one block; Protocol 95 Step 6 lacks the Execution arrangement paragraph (`absorbs the epic layer`, `dispatches no Work Item Runner`); Protocol 91 lacks the absorbed-layer sentence (these three checks read Protocols 90, 91 and 95, already in the read set) |
| Plan gap | `explicit_list_format_parity` | Any of the canonical guide, guardrails section 4, Protocol 90 declaration checkpoint or the merged spec's Named Stop-Condition Mapping row lacks the identical `explicit_list_invocation_targets=<t1>,<t2>,...` format string |
| AC8 | `canonical_workflow_hub` | the workflow_hub artifact-ownership, tracker, and post-merge cleanup notes |

Smoke Step coverage remains the human-facing check for the same ACs.

**Smoke test runbook**:
`docs/testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md`

**Regression suite and CI wiring**: Add
`scripts/development-workflow/tests/test-cursor-dispatch-profile-surfaces.sh`.
File discovery alone is **not** sufficient. `.github/workflows/workflow-tests.yml`
is deliberately not path-filtered, and `select-test-suites.sh` decides which
suites a PR runs: a suite with no `# covers:` header covers only
`scripts/development-workflow/<name>.sh` / `.py` by naming convention (plus its
own file and fixture directory). This suite guards docs, commands, skills,
agents, protocols and a rule file, so it is a cross-cutting suite and **must
declare** what it covers, within the first `COVERS_HEADER_LINES` (60) lines of
the file, one `# covers:` line per group:

```text
# covers: .cursor/commands/run-item.md .cursor/commands/run-item-work.md .cursor/commands/run-items.md .cursor/commands/run-epic.md .cursor/commands/run-work.md
# covers: .claude/commands/run-item.md .claude/commands/run-item-work.md .claude/commands/run-items.md .claude/commands/run-epic.md .claude/commands/run-work.md
# covers: .agents/skills/run-item/SKILL.md .agents/skills/run-item-work/SKILL.md .agents/skills/run-items/SKILL.md .agents/skills/run-epic/SKILL.md .agents/skills/run-work/SKILL.md
# covers: .cursor/agents/orchestrator.md .cursor/agents/item-orchestrator.md .claude/agents/orchestrator.md .claude/agents/item-orchestrator.md
# covers: .codex/skills/workflow-orchestrator/SKILL.md .codex/skills/workflow-item-orchestrator/SKILL.md
# covers: docs/workflow/development-workflow/protocols/90-batch-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md docs/workflow/development-workflow/protocols/95-run-epic-protocol.md
# covers: docs/workflow/development-workflow/guardrails-enforcement.md docs/workflow/development-workflow/agent-model-config.md
# covers: docs/workflow/development-workflow/integrations/cursor-dispatch-profiles.md .cursor/rules/workflow.mdc
# covers: docs/specs/developments/20260911230512_1462-cursor-dispatch-profiles/1_1462-cursor-dispatch-profiles_specs.md
# covers: scripts/development-workflow/tests/fixtures/cursor-dispatch-profile-surfaces/**
# covers: docs/testing/workflow/1462-cursor-dispatch-profiles.smoke-test.md
```

**Complete read set (so the "every path the guard reads" guarantee is
literally true).** The guard, its `--self-test`, and `simulate_bounded_paths`
read exactly: (1) the 15 command and skill mirrors; (2) the 4 role agents and 2
Codex workflow skills; (3) Protocols 90, 91, 95; (4) `guardrails-enforcement.md`
and `agent-model-config.md`; (5) `.cursor/rules/workflow.mdc`; (6) the canonical
guide `cursor-dispatch-profiles.md`; (7) the **merged spec** (C1 reads its
Decision-Gate matrix row count at test time, so the spec path above is in the
header); (8) the fixture directory `.../fixtures/cursor-dispatch-profile-surfaces/`
(the header lists it as a `**` glob even though the selector also auto-covers a
suite's own fixture directory, so the claim does not depend on that rule); and
(9) its own script file (always covered). The smoke runbook is a
**selection-only** path: the guard does not read it, but a change to it must
still run the guard, so it stays in the header and is excluded from the read
set. The guard does **not** read the plan file (the scenario table, row
mapping and token list live inside the script). All reads go through one
`read_path()` helper that fails on any path outside the declared read set, and
the header-consistency check asserts `covers == read set + selection-only
paths` in both directions.

Every path the guard reads must be listed, so the header and the guard's
surface table are kept in step by a header-consistency check inside the guard
(the declared read set plus the selection-only smoke runbook must equal the
`# covers:` paths, in both directions). Other CI-wiring assumptions checked in this plan:

- **Path filters**: `workflow-tests.yml` has no `paths:` filter (selector only);
  no workflow edit is needed. `markdown-lint.yml` is path-filtered but the
  plan/smoke/changelog `.md` files are already inside its globs; fixtures are
  intentionally outside them.
- **Registration**: none in the workflow file; the `# covers:` header is the
  registration, verified below.
- **Time budget**: each suite is capped by `SUITE_TIMEOUT_SECONDS` (600s) inside
  a shard, and the guard runs `--self-test` over the whole fixture set every
  time; the guard must complete in well under that cap (target under 60s, no
  network, no `gh`). The manual planted-violation cycles are not part of the CI
  suite run.
- **Selector verification (implementation-time, planted check)**:
  1. `select-test-suites.sh --print-map` lists this suite against every path in
     the header above (assert one row per protected path).
  2. For each protected surface and for the merged spec file, write that
     single path to a temp changed-files list and run
     `select-test-suites.sh --changed-files <list>`; confirm the output
     contains `test-cursor-dispatch-profile-surfaces.sh`. This is the planted
     check: a touched mirror path must select the suite.
  2a. **Fixtures directory, exact selector behavior** (read from
     `select-test-suites.sh`, and observed by running it): a changed path under
     `scripts/development-workflow/tests/fixtures/` matches the
     `FULL_RUN_TRIGGER_PATTERNS` entry `scripts/development-workflow/tests/fixtures/**`;
     the selector prints `INFO: full run triggered by <path> (matches
     <pattern>)` to stderr and emits **every** suite, which includes this one.
     The check is therefore positive only: confirm that INFO line and that the
     output contains `test-cursor-dispatch-profile-surfaces.sh`. No
     "unselected" planted check exists for this path, and none is claimed. The selector's own suite already asserts this trigger behavior for
     every full-run trigger pattern (`test-select-test-suites.sh`, the
     `full_run_trigger_*` cases), so step 5 also covers it.
  3. For the non-fixtures paths of step 2, remove one `# covers:` path from
     the header, rerun step 2 for that path, and confirm this suite is **not**
     in the output (other suites may be; only this suite's absence is
     asserted), which proves the check is live; restore.
  4. `select-test-suites.sh --report-gaps` shows no gap for this suite (it is
     selectable by a PR change set).
  5. Run `bash scripts/development-workflow/tests/test-select-test-suites.sh`
     to confirm the selector suite still passes with the new header.

---

## Seed Data

Not applicable — no runtime data.

---

## Documentation Updates (post-implementation, developer checklist)

- [ ] `changelog.d/1462.added.cursor-dispatch-profiles.md` — **plan-added
      release-note fragment; traces to no AC**. Rationale: repository
      convention (`AGENTS.md` CHANGELOG & Versioning) requires a
      `changelog.d/` fragment for feature PRs, and Prepare Release assembles
      those fragments. It is a process addition, not a scope expansion.
      Implementation PR only; body:
      `- **Cursor dispatch profiles** (#1462): Document native-handoff, parent-orchestrated, and inline-fallback profiles for Cursor bounded commands with consistent declaration gates and named stop conditions.`
      Do **not** edit `CHANGELOG.md` directly in the implementation PR.
- [ ] `AGENTS.md` — **not modified** by this feature: discoverability is
      delivered by the `README.md` integrations entry and by the mirror links
      on every entrypoint (AC17); `AGENTS.md` is a shared symlinked project file
      and adding a link there is out of scope.

---

## Document Quality Gate (plan stage)

| Check | Result | Notes |
| --- | --- | --- |
| Evidence currency | Pass | Verification Log re-run `2026-09-21` at verified head `4357b3bf`; its child commit changes only the log and these gate lines. Every command is recorded literally with its observed output (Literal commands block), including the tracker-config key scan (L10), the sandbox pre-flight guard checks (P0, P5-P7) and the prelude dry runs for the three live invocations (L11). Implementation-time checks are marked Deferred, not Pass |
| Spec coverage | Pass | Plan maps to AC1–AC20 via layer checklist; BO-9/BO-10 deferred per spec |
| Implementation-order consistency | Pass | Canonical doc before mirrors; guardrails before surface guard |
| Verification support | Pass (plan-stage design; execution deferred) | Verification Log + required live Remote Control evidence for `/run-item`, `/run-items` and `/run-epic` (Steps 8, 13B, 14B; AC17 behavior) run only against controlled disposable sandbox artifacts with a cleanup checklist and real-repository-untouched verification + surface guard (link, profile string, E1-E6 clauses, canonical-doc checks, fixtures) + per-branch planted-violation proofs + smoke runbook |
| Decision-gate applicability | Pass | Complex gate — authoritative spec matrix + implementation mapping table |
| CI wiring | Pass (design; execution deferred) | `# covers:` header for every protected surface, selector planted check (unselected-when-removed for non-fixtures paths; a fixtures change is a full-run trigger, checked positively only) and `--report-gaps`, per-suite time cap, no path filter change; see Testing Strategy |
| Shell-script lint | Pass (design; execution deferred) | New `.sh` verified by `bash -n`, `shellcheck --severity=warning`, and `workflow-shell-guard-lint.py --base-ref origin/develop` per REVIEW.md; Implementation Order step 9 |
| Parser-risk addendum | Pass | Surface guard is a structured-Markdown scanner; boundary, lookalike, multiple-occurrence and nested/overlap cases each mapped to a fixture and self-test (see Parser-Risk Addendum) |
| Concurrent-event-source addendum | N/A | No concurrent event handlers |
| Cross-cutting checklist addendum | N/A | No new REVIEW.md checklist category |

---

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| Mirror surfaces drift from canonical doc | High | High | Surface guard test + smoke runbook cross-check |
| Operators confuse prelude with declaration | Medium | Medium | bounded-run-prelude ordering note + examples |
| Restating role contracts causes drift | Medium | High | Matrix links to protocols/agents only (spec Out of Scope 4) |
| Batch explicit-list stop wording inconsistent | Medium | Medium | Plan gap decision + spec row update in same PR |
| Conflicts with #1745 / #1746 scope creep | Medium | High | Explicit out-of-scope callouts in canonical doc |

---

## Implementation Order

1. **Canonical doc** — create `integrations/cursor-dispatch-profiles.md` with
   full matrix, examples, and gap references (#1745, #1746). Commit.
2. **Guardrails** — add named stop conditions and pre-branch affected-item text.
   Commit.
3. **Protocols 90, 91, 95** — reference canonical doc at execution
   arrangement; add declaration checkpoints and summary fields. Commit.
4. **Command + skill mirrors** — Cursor, Claude, Codex `.agents/skills` adapters.
   Commit.
5. **Role agents** — orchestrator + item-orchestrator (Cursor + Claude), plus
   both Codex workflow skills: `.codex/skills/workflow-orchestrator/SKILL.md`
   (portfolio entrypoint) and `.codex/skills/workflow-item-orchestrator/SKILL.md`
   (item entrypoint), each carrying its layer's mirror content contract
   (AC10, AC11, AC13, AC18, AC20). Commit.
6. **agent-model-config + workflow rule + README + bounded-prelude ordering note** —
   Commit.
7. **Spec alignment** — update merged spec Named Stop-Condition Mapping row for
   explicit-list affected item. Commit. **Order note / reversal risk**: do not
   run this before step 2 (guardrails) or before the plan-gap wording is stable
   in the canonical doc (step 1). Reversing step 7 ahead of guardrails risks
   shipping a merged-spec row that disagrees with section 4 stop text, or
   rewriting the spec twice when guardrail wording settles. Spec alignment may
   land in the same commit as guardrails if both use the identical
   `explicit_list_invocation_targets=...` string; otherwise keep this after
   step 2.
8. **Surface guard test** — add the shell guard (link, profile-string, E1-E6
   clause, canonical-doc, and `simulate_bounded_paths` branches), the scanner
   fixtures directory containing exactly the fixture manifest (`MANIFEST_COUNT`
   rows, including the fence-semantics rows), and the `--self-test` mode; with the `# covers:` header
   declared (Testing Strategy: discovery alone does not wire it into PR suite
   selection) and the selector verification run. Run locally. Commit.
9. **Verify** — run every repo lint that applies to the files the PR adds:
   markdown lint commands from `AGENTS.md` (`npx markdownlint-cli2` over
   specs, testing runbook, and `changelog.d`; `markdown-heuristic-lint.py`;
   `check-changelog-duplicate-headers.sh` only if `CHANGELOG.md` changed),
   `python3 scripts/lint/workflow-shell-snippet-lint.py --base-ref origin/develop`
   (protocol/mirror `.md` edits), and for the new shell script
   `bash -n`, `shellcheck --severity=warning`, and
   `python3 scripts/lint/workflow-shell-guard-lint.py --base-ref origin/develop`
   (also run `bash scripts/lint/tests/test-workflow-shell-guard-lint.sh`
   when the guard linter's inputs change), then run the selector verification
   (`--print-map`, per-surface `--changed-files` planted check,
   `--report-gaps`, `test-select-test-suites.sh`), then run the surface guard, run
   the scanner `--self-test`, and execute the smoke runbook: Steps 1-6 and
   10-14 must PASS at the implementation head, with **live Remote Control
   evidence for all three bounded commands** (Step 8 `/run-item`, Step 13 Part B
   `/run-items`, Step 14 Part B `/run-epic`, each to a terminal condition or
   named stop with no human rescue; NOT RUN blocks sign-off); Steps 12, 13 Part
   A and 14 Part A require the mandatory `simulate_bounded_paths` result (it
   validates the decision matrix, not the live behavior); only optional live
   Steps 7 and 9 and Step 13 Part C may be documented NOT RUN, per the
   runbook's Pass criteria. The live steps run **only** in the disposable
   sandbox (operator-provisioned repository, `[SANDBOX-1462]` issues and epic,
   sandbox `develop` base at S, whose config disables merging), after the
   pre-flight `origin`, `git diff H S` and no-merge-config checks, with each live
   invocation selecting an explicit no-merge, no-delegated-review policy
   (`--no-delegate-review --no-may-merge --max-risk low`, needed because
   `mode: assisted` resolves delegated review on by default) and passing the
   prelude gate (the summary prints `Delegated review: false` and `May merge:
   false`), and are
   followed by the runbook's cleanup checklist; sign-off is blocked until the
   completion criteria are met and the real repository is verified untouched.
10. **Changelog fragment** — create `changelog.d/1462.added.cursor-dispatch-profiles.md`
      with the literal bullet from **Documentation Updates** (implementation PR only).
11. **Planted-violation proofs** — run every fail/pass cycle (link, profile
      string, E1-E6 clauses, and canonical-doc checks) plus the scanner self-tests documented in
      **Layer-by-Layer Changes → Workflow tooling** and **Testing Strategy**.

---

## Reversal / Rollback

The change publishes a workflow contract (declaration gate, two new named stop
conditions) across many mirror surfaces. It is documentation-only with no data
or runtime state, so reversal is a plain `git revert` of the implementation PR
merge commit (or of its per-step commits in reverse order, keeping the
step 2 / step 7 ordering constraint). Consequences to note in the revert PR:
runs started during the window may have emitted declaration blocks and stop
names that no longer exist; those are informational text in past run output and
need no cleanup. If only the surface guard is faulty, revert or fix the script
alone; docs stand independently. Partial reversal of the guardrails stop
conditions without the mirrors leaves mirrors naming unknown stops, so revert
guardrails and mirrors together.

---

## Cross-Cutting Operational Assumption Records (for implementer)

Protocol 03 requires, before the first file edit, re-reading each authoritative
source and recording `Still valid` or `Stale or conflicting`. Every check below
runs **before any edit** and only against something that **exists now** (the
existing config, the merged spec, existing scripts, tracker and PR state). The
artifacts this feature creates (canonical doc, guardrails rows, Protocol edits)
do not exist yet and are therefore verified **after** editing by the surface
guard, never as an assumption check.

| ID | Assumption | Authoritative source (exists now) | Pre-edit check | Valid when |
| --- | --- | --- | --- | --- |
| A1 | Artifact and integration base branch is `develop` | `.ai-dev-workflow.yaml`, batch handoff, `origin/develop` | Run this **remediation sequence first**, then the check: (i) confirm plan PR #1771 and spec PR #1732 are merged (`gh pr view <n> --json state` prints `{"state":"MERGED"}` for each); (ii) `git fetch origin develop`; (iii) create the implementation worktree and branch **from `origin/develop`** per Protocol 91's worktree recipe (the implementation is never cut from the plan branch, so the plan branch being behind `develop` is irrelevant); (iv) then `git ls-remote --exit-code origin develop` and `git merge-base --is-ancestor origin/develop HEAD` in the new worktree | Both succeed. If step (iv) fails because `develop` moved during setup, repeat (ii)-(iii) once; if it still fails, record `Stale or conflicting` |
| A2 | `single_repo`: the hub owns all artifacts | `.ai-dev-workflow.yaml` (its documented default when the **top-level** `mode` key is omitted) and the batch handoff `WORKFLOW_MODE` | `git grep -nE '^mode:' -- .ai-dev-workflow.yaml` (anchored at column 0, so it does **not** match the nested `guardrails.mode`), corroborated structurally by `python3 -c 'import yaml; d=yaml.safe_load(open(".ai-dev-workflow.yaml")); print(d.get("mode","<absent>"))'` | The grep prints nothing and exits `1`, and the structural check prints `<absent>` (default `single_repo`); or the top-level key is `mode: single_repo`; and the handoff says `single_repo`. The nested `guardrails.mode` is a different key and is excluded by the anchor |
| A3 | The pre-branch explicit-list affected-item format in this plan's Plan-Stage Gap Resolution has no competing definition and matches the router | Merged spec Known-gaps item 1; `run-work-router.sh`; the repository tree | (a) `git grep -c "does not define what it names for a pre-branch" -- <merged spec>` prints `<merged spec path>:1` (the gap is still recorded, not since resolved another way); (b) `git grep -l explicit_list_invocation_targets | grep -v -e 20260911230512_1462 -e docs/testing/workflow/1462` prints nothing and exits `1` (no competing definition; run **before** any edit, because the implementation legitimately adds the format to the canonical guide, guardrails and Protocol 90); (c) run `run-work-router.sh` read-only on two existing targets and confirm `RESOLVED_SCOPE` is the comma-joined, deduplicated, ordered list the serialization is defined over | (a) prints `<merged spec path>:1`, (b) empty with exit `1`, (c) comma-joined normalized list |
| A4 | No open PR changes the same surfaces | Tracker and PR state | `gh pr list --state open --limit 100 --json number,files --jq '[.[] | select([.files[].path] | any(test("protocols/(90|91|95)-|guardrails-enforcement|agent-model-config|integrations/cursor-dispatch|\\.cursor/commands/run-|\\.claude/commands/run-|\\.agents/skills/run-|\\.cursor/agents/|\\.claude/agents/|\\.codex/skills/workflow-(item-)?orchestrator|\\.cursor/rules/workflow"))) | .number] | length'` (the same literal command as A4 in the Verification Log) | Prints `0` (or only this feature's own PRs) |
| A5 | Related gaps #1745 and #1746 are still open and out of scope | Tracker state | `gh issue view 1745 --json state` and `gh issue view 1746 --json state` | Each prints `{"state":"OPEN"}`; if either is closed, apply the Dependencies consequence (re-check its resolution text before editing) |
| A6 | The spec PR is merged, so the spec is the normative source | Tracker state | `gh pr view 1732 --json state,baseRefName` | Prints `{"baseRefName":"develop","state":"MERGED"}` |

**Post-edit parity (not an assumption check).** That the canonical guide, the
guardrails `dispatch_profile_declaration_missing` row, Protocol 90's
declaration checkpoint and the merged spec's Named Stop-Condition Mapping row all
carry the identical `explicit_list_invocation_targets=<t1>,<t2>,...` format is
verified after the edits by the surface guard check
`explicit_list_format_parity` (reads those four files, all in the read set;
planted proof cycle 19; fixtures `parity-explicit-list-format-match` and
`parity-guardrails-mismatch`).

Implementer must record `Still valid` or `Stale or conflicting` for A1-A6
before file edits per Protocol 03 assumption check.

# Provider Contingency and Runner Failover

Long orchestration runs (`/run-work`, `/run-epic`, `/run-item-work`, `/run-reviewer-loop`) can be interrupted when a model quota is exhausted, a stream times out, or the primary runner becomes unavailable. PR-level state persists across these failures — use the playbooks below instead of manually re-labeling PRs or restarting from scratch.

Related docs:

- [`agent-model-config.md`](agent-model-config.md) — tier assignments, resume checklist, timed-out run detection
- [`protocols/91-orchestrate-work-protocol.md`](protocols/91-orchestrate-work-protocol.md) — item-orchestrator Step 7 / Step 8 contract
- [`protocols/93-automated-reviewer-loop-protocol.md`](protocols/93-automated-reviewer-loop-protocol.md) — standalone reviewer + CI loop
- [`integrations/llm-router.md`](integrations/llm-router.md) — optional tier-based model fallback (experimental)

---

## Failure mode 1: Model quota or rate limit

**Symptoms:** HTTP 429, “rate limit”, “quota exceeded”, or the runner refuses to start a turn on the configured model.

**Same runner — swap model or enable router fallback:**

1. Stop retrying the same premium model in a tight loop.
2. For Cursor: confirm `.cursor/agents/<agent>.md` uses tier-appropriate pinned models (see [`agent-model-config.md`](agent-model-config.md)); temporarily downgrade only when the task is mechanical.
3. For optional router setups, switch the runner to a router combo for the agent’s tier (see [`integrations/llm-router.md`](integrations/llm-router.md)).
4. Resume at PR level — the in-flight session may abort mid-turn, but branch commits and PR comments remain.

**Do not:** Manually apply `ready-for-human-review` or remove `needs-fixes` without completing the reviewer loop.

### Codex GitHub App Review Quota

When `pr-review-loop.sh` runs the `codex-github` platform and the Codex GitHub
App replies with a review-capacity message such as “You have reached your Codex
usage limits for code reviews,” the loop reports:

```text
RESULT=escalate
REASON=codex-github-usage-limit
PLATFORM=codex-github
COMMENT_COUNT=0
BLOCKING_COUNT=0
SUGGESTION_COUNT=0
```

This is reviewer unavailability, not a code-review finding. Do not dispatch a
fixer agent and do not label the PR `needs-fixes` solely for this result. Wait
for quota reset or add review capacity, then rerun the reviewer loop against the
same PR head.

---

## Failure mode 2: Stream timeout or API error

**Symptoms:** “Stream idle timeout”, connection reset, or the agent stops mid-step with no terminal PR summary.

**When to retry the same agent vs resume via item orchestration:**

| Situation | Action |
| --------- | ------ |
| Failure before any commit or PR update | Re-invoke the same stage agent from a clean checkout of the item branch |
| Failure after commits landed on the PR branch | Inspect PR state (checklist below), run `workflow-next-action.sh`, then `/run-item-work --pr <n>` or `/run-reviewer-loop` |
| Reviewer loop interrupted (labels present, no loop summary) | `/run-reviewer-loop` or item-orchestrator — see [Resume checklist](#resume-checklist) |

Typical timeout thresholds for long agents are documented in [`agent-model-config.md`](agent-model-config.md#expected-run-durations).

---

## Failure mode 3: Runner unavailable

**Symptoms:** Cursor, Codex, or Claude Code cannot run agents (auth failure, extension outage, CI runner offline).

**Migrate to an alternate runner:**

1. Use the **same repository** and **same PR** — do not fork state into a new PR unless the protocol requires it.
2. Pull latest on the item branch or integration branch as appropriate.
3. Run the [Resume checklist](#resume-checklist).
4. Re-invoke the workflow entrypoint your alternate runner supports (`/run-item-work`, `/run-reviewer-loop`, Codex skills, or Claude Code agents) using the **same PR number**.
5. Do **not** manually apply readiness labels; let the item-orchestrator apply them in protocol 91 Steps 7b and 8a after Step 7 (reviewer loop), Step 8 (CI), and Step 8c verification succeed.

Tool-specific agent files (`.cursor/agents/`, `.claude/agents/`, `.codex/skills/`) share the same protocols — only the invocation surface changes.

### Local reviewer overrides across temporary worktrees

When reviewer execution moves into a temporary worktree, the review loop resolves
the local reviewer-policy fields from the initiating checkout and applies that
effective policy to the temporary target-branch configuration. It records only
whether the policy source is `local_override` or `shared`; it does not copy,
commit, or print local configuration contents or paths.

If the initiating local policy cannot be resolved, the loop stops with an
actionable error rather than silently choosing a different shared reviewer. When
there is no local reviewer override, the shared-policy path remains unchanged.

Worktrees created outside the loop — `git worktree add` from Protocol 90's
isolation manifest or Protocol 91 Step 3.5 — never contain the gitignored
override either. For those, the config resolver and `workflow-lib.sh` fall
back to the main clone's `.ai-dev-workflow.local.yaml` when the linked worktree
has none of its own (#1560). A worktree's own file and
`WORKFLOW_LOCAL_REVIEW_OVERRIDE_ROOT` still take precedence, in that order.

---

## Resume checklist

Run from the repository root (or selected product repo in `workflow_hub` mode):

```bash
gh pr view <pr_number> --json isDraft,labels,comments,statusCheckRollup
./scripts/development-workflow/workflow-next-action.sh --pr <pr_number>
```

Interpret signals (full table in [`agent-model-config.md`](agent-model-config.md#detection-checklist)):

- **`ready-for-human-review` + no reviewer loop summary** → likely incomplete Step 7; run `/run-item-work --pr <n>` or `/run-reviewer-loop` (**exception:** Step 7 `skipped` when no review platforms are configured — no summary is posted by design).
- **`ready-for-regression` only + no reviewer loop summary** → not automatically incomplete; Step 7 can exit `skipped` (no platforms), then Step 7b applies the label with no summary. Use `workflow-next-action.sh` before rerunning `/run-reviewer-loop`.
- **`needs-fixes` present** → address blocking findings or rerun fixer path before readiness labels.
- **CI failing or pending** → complete Step 8 (`pr-ci-loop.sh`) after Step 7 is clean or legitimately skipped.

Then re-invoke:

```bash
# Item still in flight
/run-item-work --pr <pr_number>

# Reviewer/CI only
/run-reviewer-loop
```

---

## Do-not list

- Do **not** apply `ready-for-human-review` when the PR lacks an “Automated Reviewer Loop Summary” (or equivalent) comment unless Step 7 was explicitly skipped (no platforms configured).
- Do **not** remove `needs-fixes` without a clean reviewer loop and CI evidence.
- Do **not** force-push or amend published PR commits during recovery. Follow the [published branch update rule](../../best-practices/2-version-control.md#published-branch-updates): preserve shared history and use focused follow-up commits; ask for human direction when no safe recovery path is clear.
- Do **not** assume the latest bot comment is the only active blocker — audit all open review threads on the current HEAD.

---

## When to escalate to a human

Escalate when:

- `workflow-next-action.sh` returns an ambiguous or blocked state you cannot resolve in one fix pass
- Checkpoint or setup labels (`human-checkpoint-required`, `needs-setup`) block delegated merge
- Repeated quota failures affect `premium`-tier spec/plan work and product decisions are needed
- Runner migration requires credentials or repo access you do not have in the alternate environment

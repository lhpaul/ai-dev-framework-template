# AI Agent Model Configuration

This document explains the _model tier_ assigned to each agent, the rationale behind each choice, and how to override them when needed.

This template is designed to be **LLM-provider agnostic**. The concrete model IDs you use will depend on:

- Which provider(s) you have access to (Anthropic, OpenAI, Google, etc.)
- Which agent runner you use (Claude Code, Codex, Cursor, CI runner, etc.)
- Your cost/latency targets and context-window needs

---

## Model Tiers

Use a small set of tiers and map them to your provider’s current model lineup.

- **`economy`**: fast + cheap; good for mechanical coordination and checklist-style work
- **`balanced`**: general-purpose; best cost/quality default for most writing + coding tasks
- **`premium`**: highest reasoning reliability; reserve for architecture and high-leverage planning

If you prefer different names (`small/medium/large`, `fast/standard/pro`, etc.), keep the same intent.

---

## Agent Assignments (Tier-Based)

| Agent                          | Tier       | Rationale                                                                                                                                                                                                                                                                                                                                                  |
| ------------------------------ | ---------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `orchestrator`                 | `economy`  | **Portfolio Orchestrator**. Reads state, builds batches, and dispatches Work Item Runners; mechanical coordination that should stay fast and cheap.                                                                                                                                                                                                        |
| `item-orchestrator`            | `balanced` | **Work Item Runner**. Single-item control loop supervises review-fix-review cycles where parsing findings, determining correct fixes, and verifying them requires capable reasoning. Economy models struggle with multi-step reasoning in fix loops; balanced (sonnet minimum) is required.                                                                |
| `automated-reviewer-loop`      | `economy`  | Runs review + CI loop for a PR; mechanical coordination like the orchestration agents, no deep reasoning required.                                                                                                                                                                                                                                         |
| `product-manager`              | `premium`  | Spec writing is the highest-leverage task in the pipeline — a weak spec cascades into worse plans and worse implementations. While the spec template provides scaffolding, the creative and judgment-heavy work of capturing requirements, edge cases, and acceptance criteria benefits from deeper reasoning that a premium model provides more reliably. |
| `spec-reviewer`                | `balanced` | Review against a checklist. A balanced model is well within the capability required.                                                                                                                                                                                                                                                                       |
| `tech-lead`                    | `premium`  | Architecture decisions and implementation planning are the highest-reasoning tasks in the workflow. A weak plan is expensive to fix downstream — this is where a premium model pays for itself.                                                                                                                                                            |
| `implementation-plan-reviewer` | `balanced` | Validating a plan against a spec and codebase is review work; no architectural invention required.                                                                                                                                                                                                                                                         |
| `developer`                    | `balanced` | Code generation at scale. A balanced model is typically the cost/quality sweet spot for coding tasks, especially with a strong spec + plan.                                                                                                                                                                                                                |
| `code-reviewer`                | `balanced` | Code review against known standards and a completed spec. A balanced model is capable here.                                                                                                                                                                                                                                                                |
| `project-setup`                | `balanced` | Structured onboarding conversation with clear protocol guidance. A balanced model is sufficient.                                                                                                                                                                                                                                                           |
| `smoke-tester`                 | `balanced` | Executes the smoke test runbook using browser automation. A balanced model is sufficient for following step-by-step testing instructions.                                                                                                                                                                                                                  |
| `retrospective`                | `balanced` | **Retrospective Analyst**. Reads PR metadata and git history, synthesizes findings across multiple PRs, and identifies workflow patterns; the synthesis and pattern-recognition work requires a capable model — economy tier produces shallow, low-signal retrospectives.                                                                                  |

### Runner Notes

Use the tier names as stable policy and map them to whatever your current runner and provider support.

- In Claude Code, map the tier to the model family or explicit model ID configured in `.claude/agents/*.md`.
- In Cursor, pin explicit model IDs in `.cursor/agents/*.md` for every long-running or review-loop agent. Use `fast` for `economy` tier agents only.
- In any runner, prefer keeping the tier intent stable even when provider model names change.

### Cursor model defaults (template)

Pin models in `.cursor/agents/*.md` so subagents do not inherit the parent Composer model during long orchestration or review-fix loops. **`inherit` is acceptable only for ad-hoc, single-turn invocations** where you intentionally want the current Composer model — not for orchestrators, item runners, fixer agents, or reviewer-loop agents.

| Agent | Tier | Cursor `model` (template default) |
| ----- | ---- | ----------------------------------- |
| `orchestrator` | `economy` | `fast` |
| `automated-reviewer-loop` | `economy` | `fast` |
| `item-orchestrator` | `balanced` | `claude-sonnet-4-6` |
| `developer` | `balanced` | `claude-sonnet-4-6` |
| `code-reviewer` | `balanced` | `claude-sonnet-4-6` |
| `spec-reviewer` | `balanced` | `claude-sonnet-4-6` |
| `implementation-plan-reviewer` | `balanced` | `claude-sonnet-4-6` |
| `smoke-tester` | `balanced` | `claude-sonnet-4-6` |
| `retrospective` | `balanced` | `claude-sonnet-4-6` |
| `project-setup` | `balanced` | `claude-sonnet-4-6` |
| `design-reviewer` | `balanced` | `claude-sonnet-4-6` |
| `product-manager` | `premium` | `claude-opus-4-7` |
| `tech-lead` | `premium` | `claude-opus-4-7` |

Claude Code equivalents live in `.claude/agents/*.md` (Haiku for economy, Sonnet for balanced, Opus for premium). Update pinned IDs when your provider deprecates a model; keep the tier intent stable.

See also:

- [`provider-contingency-runner-failover.md`](provider-contingency-runner-failover.md) — quota, timeout, and runner-switch recovery
- [`integrations/llm-router.md`](integrations/llm-router.md) — optional tier-based fallback chains (experimental)

---

## Tool Restrictions

Agents only get `Bash` when they need it to carry a stage through branch creation, commits, pushes, PR creation, or readiness loops. Agents only get `Agent` when they need to dispatch sub-agents to handle stage-specific work.

| Agent                          | Has Bash? | Has Agent? | Reason                                                                                                                                                                        |
| ------------------------------ | --------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `orchestrator`                 | ✅        | ✅         | Portfolio Orchestrator: needs `git branch`, `git status`, helper scripts, and issue / PR inspection to build and supervise batches; dispatches `item-orchestrator` sub-agents |
| `item-orchestrator`            | ✅        | ✅         | Work Item Runner: needs helper scripts, git / PR inspection, and readiness loops to keep one item moving end to end; dispatches stage agents (developer, code-reviewer, etc.) |
| `automated-reviewer-loop`      | ✅        | ✅         | Runs pr-review-loop.sh, pr-ci-loop.sh, git; dispatches fixer agents (spec-reviewer, implementation-plan-reviewer, code-reviewer) when needs_fixes                             |
| `product-manager`              | ✅        | ❌         | Creates spec branches / PRs and may run readiness helpers                                                                                                                     |
| `spec-reviewer`                | ✅        | ❌         | May commit, push, and re-run fixes during spec review loops                                                                                                                   |
| `tech-lead`                    | ✅        | ❌         | May need to run commands to understand the codebase before planning                                                                                                           |
| `implementation-plan-reviewer` | ✅        | ❌         | May commit, push, and re-run fixes during plan review loops                                                                                                                   |
| `developer`                    | ✅        | ❌         | Runs build, lint, and test commands as part of implementation                                                                                                                 |
| `code-reviewer`                | ✅        | ❌         | May run lint or tests to verify applied fixes                                                                                                                                 |
| `project-setup`                | ✅        | ❌         | May need to initialize git, run project commands during setup                                                                                                                 |
| `smoke-tester`                 | ✅        | ❌         | Runs browser automation and test scripts; needs Bash for execution                                                                                                            |
| `retrospective`                | ✅        | ❌         | Needs `gh` CLI for PR metadata queries, `git` for history analysis, and `gh issue create` for backlog items; does not dispatch sub-agents                                     |

---

## Overriding the Model for a Task

If a specific task is unusually complex and you want a `premium` model for the `developer` agent — or you want to cut costs and use `economy` for a trivial spec — override the model temporarily.

**Option 1 — In-session override (runner-specific):**
Use your runner’s “one-off model override” mechanism.

Claude Code example (if applicable):

```bash
claude --agent developer --model claude-opus-4-7
```

**Cursor:**
Cursor subagents use the `model` field in `.cursor/agents/<agent>.md`. To override for a single run:

- Switch your Composer's model before invoking the subagent (e.g., `/developer`), or
- Create a duplicate agent file (e.g., `developer-premium.md`) with a different `model` value

**Option 2 — Permanent change:**
Edit the model configuration for the agent:

- **Claude Code**: Edit the `model` field in `.claude/agents/*.md`
- **Cursor**: Edit the `model` field in `.cursor/agents/*.md` (values: `fast`, `inherit`, or a specific model ID)

This affects all future invocations until changed back.

**Cursor model field values:**

- `fast`: Uses Cursor's fast model (recommended for `economy`-tier agents only)
- Pinned model ID: Uses that exact model (recommended for `balanced` and `premium` agents, e.g. `claude-sonnet-4-6`, `claude-opus-4-7`)
- `inherit`: Uses the current Composer model — **discouraged** for orchestrators, item runners, fixer agents, and reviewer-loop agents because it leaks parent-session cost into long runs; reserve for intentional one-off overrides

**Precedence**: When multiple agent locations exist (`.cursor/agents/`, `.claude/agents/`, `.codex/agents/`), Cursor uses `.cursor/agents/` first, then `.claude/agents/`, then `.codex/agents/`.

---

## Expected Run Durations

The table below shows the typical and maximum expected wall-clock duration for the two agents most likely to be interrupted by an API stream timeout. Use these values to decide whether an agent run is still in progress or has likely timed out.

| Agent                     | Typical run | Consider timed out if no progress after |
| ------------------------- | ----------- | --------------------------------------- |
| `item-orchestrator`       | 5–15 min    | ~25 min                                 |
| `automated-reviewer-loop` | 2–10 min    | ~20 min                                 |

These estimates assume a single development item with a normal review-fix cycle. Runs that encounter multiple fixer cycles, slow CI, or rate-limited external reviewers can exceed the typical range — escalate to human only when the maximum threshold is crossed with no visible progress.

---

## Resume a Timed-Out Agent Run

Long-running item-orchestrator agents can be interrupted mid-run (e.g., "API Error: Stream idle timeout" after ~20 minutes), leaving a PR in a partially-advanced state. This section explains how to detect and safely resume an interrupted run.

### Detection checklist

Inspect the PR with:

```bash
gh pr view <pr_number> --json isDraft,labels,comments,statusCheckRollup
```

| Signal                                                                                                               | Interpretation                                                                                                                                                                               |
| -------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| PR is non-draft                                                                                                      | The internal review gate (Step 7a) and `gh pr ready` completed                                                                                                                               |
| `ready-for-regression` present                                                                                       | Step 7b applied the label                                                                                                                                                                    |
| `ready-for-human-review` present **but** no reviewer loop summary comment                                            | **Incomplete** — the label was applied before Step 7 completed; the PR is not actually ready (**skip this check only when Step 7 was `skipped` because no review platforms are configured**) |
| No comment containing `"Automated Reviewer Loop Summary"`, `"Reviewer Loop Summary"`, or `"No blocking PR feedback"` | Step 7 (external automated reviewers) did not finish (**skip this check only when no review platforms are configured**)                                                                      |
| CI checks absent or in PENDING/FAILURE state                                                                         | Step 8 (CI loop) did not finish                                                                                                                                                              |
| `needs-fixes` label present                                                                                          | A prior run detected issues but the fix loop did not complete                                                                                                                                |

A PR that has readiness labels but **no reviewer loop summary comment** is the canonical sign of an interrupted run. The label alone is not a reliable completion signal.

### Resume command

```bash
# Determine the correct next step
./scripts/development-workflow/workflow-next-action.sh --pr <pr_number>

# Then re-invoke the item-orchestrator (or automated-reviewer-loop agent) for the PR
# Example (Claude Code):
#   /run-item --pr <pr_number>   (or deprecated /run-item-work)
```

The item-orchestrator uses the Step 8c independent verification gate to detect any missing labels or comments and automatically re-enters the correct resume point (Step 7a, Step 7, or Step 8).

For quota exhaustion, stream timeouts, and runner failover (Cursor ↔ Codex ↔ Claude Code), see [`provider-contingency-runner-failover.md`](provider-contingency-runner-failover.md).

### Cursor `/run-item` Handoff

Cursor users should start single-item work with `/run-item <target>`. After the
bounded prelude confirms scope, guardrails, policy, and checkpoints, Cursor may
route internally through `item-orchestrator` and the configured stage subagents
(`product-manager`, `tech-lead`, `developer`, `code-reviewer`, and related
roles). This keeps role-specific model assignments active without asking users
to invoke `item-orchestrator` directly. The internal handoff must preserve the
confirmed item/policy binding and must not duplicate the bounded prelude or
re-prompt for the same policy.

### Warning

**Do NOT manually apply `ready-for-human-review` to a PR that is missing the reviewer loop summary comment.** Doing so marks the PR as ready when the automated review step was never completed, defeating the purpose of the review loop. Always resume via the item-orchestrator and let it complete Step 7 and Step 8 before the label is applied.

---

## Updating Model IDs Over Time

Models change frequently across providers. When your provider releases new models (or deprecates old ones), update:

- The model IDs in your agent configuration (e.g. `.claude/agents/*.md` if you use Claude Code)
- Any docs where you’ve pinned concrete model IDs (prefer keeping docs tier-based)

Guideline: keep the **tier intent** stable (economy/balanced/premium) and swap in the closest current equivalents from your provider.

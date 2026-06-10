# Integration: Haystack Editor (Git Hooks)

This document describes [Haystack Editor](https://haystackeditor.com/) (`@haystackeditor/cli`) local git hooks as an **adopted optional complement** to this framework's default PR and review workflow.

## Adoption Decision (Option B — Recommended)

After evaluating the hooks in production use (2026-05-23/24), this template ships **Option B**:

| Component | Adopted? | Notes |
| --------- | -------- | ----- |
| **Truncation checker** (`hooks/truncation-checker/`) | Yes | Silent gate on staged AI-agent code; no external binary dependency |
| **LLM_RULES.md gate** (`hooks/pre-commit`) | Yes | Two-step commit with bypass token; shows rules and staged stat on first blocked attempt |
| **Conventional Commit gate** (`hooks/commit-msg`) | Yes | Deterministic local validation of the repository commit-message contract |
| Entire session tracking | No | Removed — adds `~/.haystack/bin/entire` binary dependency that downstream consumers may not want |

The hooks retained for Entire (`prepare-commit-msg`, `post-commit`, `pre-push`) are kept as no-op entry points so downstream teams that want to extend them have the scaffolding. `commit-msg` is repurposed for Conventional Commit validation because that rule is deterministic and already part of the repository contract.

**What this means for downstream consumers**: Run `haystack hooks install` once per clone to activate the two high-value gates. The Entire binary is not required — this template does not ship or reference it.

---

Haystack is **not** the same product as deepset's [Hayhooks](https://github.com/deepset-ai/hayhooks) (Haystack pipeline deployment). Haystack Editor focuses on AI-assisted development: PR triage, agent-session attribution, and local guardrails on agent commits.

The canonical workflow in this template still uses **`gh pr create`** and the automated reviewer loop (`pr-review-loop.sh`, protocol 93) with platforms declared in `.ai-dev-workflow.yaml` (for example CodeRabbit, PR-Agent). Haystack does not replace those unless your team explicitly adopts it end-to-end.

---

## What Haystack Adds

### Local git hooks (`hooks/`)

Installed via `haystack hooks install`:

| Hook | Purpose |
| ---- | ------- |
| `pre-commit` | Detects active AI agent sessions (Claude Code, Codex, Gemini CLI, OpenCode); runs truncation checks on staged agent/prompt code; enforces review of `LLM_RULES.md` on agent commits (two-step commit with bypass token) |
| `prepare-commit-msg` | No-op entry point (Entire session tracking not adopted — Option B) |
| `commit-msg` | Validates Conventional Commit subject format and first-line length; allows normal merge, revert, fixup, squash, and amend commits |
| `post-commit` | No-op entry point (Entire session tracking not adopted — Option B) |
| `pre-push` | No-op entry point (Entire session tracking not adopted — Option B) |

Human commits skip the agent-specific enforcement path in `pre-commit` and pass through immediately. `commit-msg` applies to all commits because the Conventional Commits contract is repository-wide.

### Optional PR triage and review (Haystack cloud)

When using the full Haystack product:

- **`haystack submit`** — push branch, open PR, run pre-PR triage
- **`haystack triage <pr-number>`** — risk rating, findings, fix prompts (`--json` for automation)
- Review UI that surfaces agent conversation and verification alongside diffs

This can run **in parallel** with CodeRabbit/Greptile/Devin configured in `.ai-dev-workflow.yaml`; they address different layers (local commit hygiene vs. hosted PR review).

**Native review platform**: `haystack triage` is also supported as a native automated review platform in `pr-review-loop.sh`. Declare `haystack` under `review.on_ready.github` in `.ai-dev-workflow.yaml` to include Haystack triage in the Step 7 automated reviewer loop after draft reviewers clear. See [`haystack-triage.md`](haystack-triage.md) for setup instructions, severity mapping, and troubleshooting.

### Operating model

Use Haystack in three layers, each with a different failure mode:

| Layer | Files | Use for | Do not rely on it for |
| ----- | ----- | ------- | --------------------- |
| Local deterministic hooks | `hooks/`, `LLM_RULES.md` | Cheap checks before a commit leaves the workstation: agent truncation checks, agent rule re-injection, commit-message format | Hosted PR review, semantic correctness, checks that require repository-wide context |
| Haystack PR rules | `.haystack/pr-rules.yml`, `.haystack/review-policy.md` | Semantic review prompts and risk prioritization for PRs that Haystack analyzes | Hard guarantees where a script or CI check can validate the invariant |
| Reviewer loop integration | `scripts/development-workflow/haystack-reviewer.sh`, `.ai-dev-workflow.yaml` | Folding `haystack triage` into Step 7 with the same key-value contract as other reviewers | GitHub inline-thread audits; the MVP reports findings locally and does not post GitHub review threads |

Prefer deterministic checks for rules that can be expressed mechanically. Keep `.haystack/pr-rules.yml` focused on judgement calls: shell control-flow risk, review-state freshness, unsafe API payload construction, and workflow-contract drift. When Haystack reports a non-blocking finding, record the disposition in the reviewer-loop summary instead of silently ignoring it.

For repositories that open implementation PRs as drafts, configure Haystack in
`review.on_ready.github` instead of the draft phase. The reviewer loop will
mark the PR ready before running ready-phase platforms; Haystack triage may stay
`pending` indefinitely while a PR remains draft.

### Hardening roadmap

Use small PRs when expanding this integration:

1. Promote deterministic invariants out of `.haystack/pr-rules.yml` when they can be checked without LLM judgement.
2. Extend local hooks only for repo-wide contracts with low false-positive risk.
3. Keep `haystack triage` visible in reviewer-loop summaries, especially `unavailable`, `pending_timeout`, and advisory-only outcomes.
4. Add agent detection only for tools that the team actively uses. Cursor is not detected by the stock parsers today; those commits behave like human commits unless detection is extended.

---

## Installation

### One-time CLI

```bash
# Install Haystack CLI (see https://haystackeditor.com/ for current install instructions)
haystack setup
```

### Per-repository hooks

From the repo root:

```bash
haystack hooks install
```

This:

1. Copies hook scripts into `hooks/` and installs `hooks/package.json` dependencies (tree-sitter for truncation AST checks)
2. Sets `core.hooksPath` to `hooks/` (local git config)
3. Creates `LLM_RULES.md` (if not already present)

**Teammates** must run `haystack hooks install` on each clone so `core.hooksPath` points at `hooks/`. Commit `hooks/` and `LLM_RULES.md`; do not commit `hooks/node_modules/` (covered by root `node_modules/` ignore).

After install, run `npm install` in `hooks/` only if the installer did not already install dependencies.

> **Note**: This template does not ship `.entire/settings.json` or the `.entire/` directory (Option B — Entire session tracking not adopted). If you later adopt full Entire integration, run `haystack hooks install` again and commit the generated `.entire/settings.json` and the corresponding `.gitignore` entry for `.entire/metadata/`.

---

## Alignment With This Framework

| Concern | Default in this template | With Haystack hooks |
| ------- | ------------------------ | ------------------- |
| Open PRs | `gh pr create --draft` per protocol 03 | Optional `haystack submit` when team adopts Haystack PR flow |
| Automated review | `review.on_draft.github` / `review.on_ready.github` in `.ai-dev-workflow.yaml` + protocol 93 | Unchanged; Haystack triage is separate unless you standardize on Haystack review |
| Agent rules at commit | `AGENTS.md`, `REVIEW.md`, protocols | Additional `LLM_RULES.md` enforced on **agent** commits via pre-commit |
| Truncation in agent code | Best practice in docs | Automated scan on staged paths matching `agent/`, `prompts/`, `pipeline/`, etc. |

Customize `LLM_RULES.md` for your project. The template version keeps **`gh pr create`** as the default PR path and documents `haystack submit` as optional.

---

## Customizing `LLM_RULES.md`

`LLM_RULES.md` is shown to agents on the first blocked commit attempt, then a bypass token allows the second attempt with the same staged tree.

Recommended sections to tune:

1. **Creating Pull Requests** — match your VCS workflow (`gh` vs. Haystack-only teams)
2. **No Truncation Without Permission** — keep for agent/prompt-heavy repos; narrow `CHECKED_PATH_PATTERNS` in `hooks/truncation-checker/index.ts` if needed
3. **No Hardcoded Repo Knowledge in Prompts** — useful for template/framework repos

To disable Haystack's mandatory PR wording entirely, edit the PR section in `LLM_RULES.md`; the pre-commit hook only **displays** the file, it does not hardcode Haystack-specific logic beyond the default generated text.

---

## Agent Commit Flow (What Agents Experience)

1. Agent runs `git commit`
2. `pre-commit` detects session (e.g. Claude Code) and prints agent context to stderr
3. Truncation checker runs on relevant staged paths
4. First attempt: commit blocked; full `LLM_RULES.md` + staged stat shown
5. Second attempt (same staged tree): bypass token consumed; commit proceeds

Agents using Cursor are not detected by the stock agent-context parsers today; those commits behave like human commits unless detection is extended.

---

## Disabling or Removing

- **Temporarily skip hooks**: `git commit --no-verify` (human decision; do not use routinely for agent work)
- **Uninstall hooks path**: `git config --unset core.hooksPath` and remove or stop using `hooks/`
- **Remove from repo**: delete `hooks/` and `LLM_RULES.md`; document the change in `CHANGELOG.md`

---

## Related Files

| Path | Role |
| ---- | ---- |
| `hooks/pre-commit` | Agent detection, truncation check, LLM rules gate |
| `hooks/commit-msg` | Conventional Commit format gate |
| `hooks/truncation-checker/` | Pattern and AST-based truncation detection |
| `hooks/agent-context/` | Parsers for Claude, Codex, Gemini, OpenCode sessions |
| `LLM_RULES.md` | Project rules injected on agent commits |
| `docs/best-practices/2-version-control.md` | Default PR conventions (`gh`) |
| `docs/workflow/development-workflow/integrations/haystack-triage.md` | Haystack triage as a native Step 7 review platform |
| `scripts/development-workflow/haystack-reviewer.sh` | Companion script wrapping `haystack triage --json` |

---

## See Also

- [`pr-review-platform.md`](pr-review-platform.md) — Step 7 multi-platform review loop
- [`haystack-triage.md`](haystack-triage.md) — Haystack triage as a native review platform
- [`coderabbit.md`](coderabbit.md) — CodeRabbit integration (common default reviewer)
- Protocol 93 — [`../protocols/93-automated-reviewer-loop-protocol.md`](../protocols/93-automated-reviewer-loop-protocol.md)
- Protocol 03 — [`../protocols/03-implement-development-protocol.md`](../protocols/03-implement-development-protocol.md) (`gh pr create` steps)

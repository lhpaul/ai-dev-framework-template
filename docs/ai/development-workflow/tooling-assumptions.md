# Tooling Assumptions

This document defines the tools the AI development workflow depends on, distinguishes required from optional tools, and defines fallbacks for each.

---

## Required Tools

These tools are non-negotiable. The workflow cannot function without them.

### Git + Remote Repository (e.g., GitHub, GitLab, Bitbucket)

- Agents must be able to create branches, commit, push, and open pull requests
- Pull requests are the primary mechanism for human review and approval
- CI checks on PRs serve as the automated merge gate

**Fallback**: If the remote repository CLI is unavailable, the agent creates the branch and commits locally, then instructs the human to push and open the PR manually.

### CI / Automated Checks

- At minimum, a CI pipeline that runs build + lint + tests on every PR
- A failing CI check blocks merge
- If no CI is configured, the agent must run build/lint/test locally and report results in the PR description

---

## Recommended Tools

These tools significantly improve the workflow but have fallbacks.

### Repository CLI (e.g., GitHub CLI `gh`, GitLab CLI `glab`)

**Used for**: creating PRs, adding labels, adding comments from the terminal without leaving the development environment.

**Fallback**: Agent provides the PR URL and all necessary information for the human to open the PR via the web UI.

### Automated PR Review Tool (e.g., Greptile, CodeRabbit)

**Used for**: automated code review that catches issues before human review, closing the feedback loop faster.

**Fallback**: Agent skips the automated review step and goes directly to human review. See the agent's protocol for how to handle this case.

For Greptile-specific setup, see [`integrations/greptile.md`](integrations/greptile.md).

---

## Optional Tools

### Issue Tracker (e.g., Linear, GitHub Issues, Jira)

**Used for**: tracking work items, prioritization, status updates. The orchestrator reads the issue tracker to determine what to work on next.

**Without it**: The orchestrator requires human input to determine the next item to work on, and prioritization logic cannot be automated.

See [`integrations/linear.md`](integrations/linear.md) for Linear-specific setup.

### Browser Automation (e.g., Playwright, Puppeteer, MCP browser tools)

**Used for**: running smoke test runbooks automatically.

**Without it**: Smoke tests in `docs/testing/` are run manually by a human following the runbook.

---

## Safety Guardrails (Non-Negotiable)

Regardless of which tools are available, the following rules always apply:

- **No `git push --force`** or `git push --force-with-lease` without explicit human approval
- **No `git reset --hard`** without explicit human approval
- **No `git rebase`** on a branch that has already been pushed to the remote, without explicit human approval
- **No merging PRs** — agents open PRs; humans merge them

If any of these actions seem necessary, **stop and ask the human** rather than proceeding. Explain why you think the action is needed and what alternatives exist.

---
name: prepare-release
description: Command-style Codex alias for preparing a release. Use when the user asks for /prepare-release or wants to run the repository release preparation protocol.
---

# Prepare Release

This is the Codex command-style alias for Claude Code `/prepare-release`.

1. Read `AGENTS.md` for repository-wide rules.
2. Read `docs/workflow/development-workflow/protocols/05-prepare-release-protocol.md`.
3. Follow the protocol exactly.
4. In `workflow_hub` mode, resolve the selected product repository with
   `component-release-target.sh` and persist `component_release_evidence.v1`
   before mutating product changelog, release branch, tag, GitHub Release,
   deployment evidence, cleanup evidence, or tracker state. Stop on any
   non-mutation routing outcome instead of guessing from the hub checkout.
5. Continue through release PR creation, release-branch reviewer-loop skip handling, regression readiness, and CI readiness until the protocol reaches a real terminal condition.
6. After both release PRs merge, run post-merge cleanup with `--from-changelog`
   or an explicit `--issues` scope, then complete any emitted tracker handoff
   such as `TRACKER_ACTION=linear_mcp_or_api_required` before calling the
   release done. For workflow-hub component releases, include `--repo`,
   `--repo-root`, and `--evidence-file` so cleanup validates the persisted
   binding before touching product-owned release branches.
7. For workflow-hub component releases, run
   `component-milestone-reconciliation.sh` after component release evidence and
   cleanup are complete. The evidence must include `hub_tracker_ref`,
   `hub_tracker_reconciliation_outcome` of `complete` or `deferred`,
   `cleanup_outcome` of `complete`, and `child_release_state` of `released` or
   `merged`. Apply namespaced component milestones only to matching component
   child issues, and use delivery-bundle parent inspection/apply paths for
   parent release status without stamping parent or delivery issues.
8. For first-time or changed workflow-hub multi-repository adoption, collect
   self-review evidence with the multi-repository release adoption guide before
   release mutation. Continue only when adoption assurance is validated, or stop
   with the emitted owner action.

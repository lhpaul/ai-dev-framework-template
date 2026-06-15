# Review Policies

## Review workflow automation scripts by hand
- **Paths**: `scripts/development-workflow/**`, `scripts/lint/**`
- **Severity**: high
- **Reason**: Small shell logic changes can silently alter review gates, retries, and failure handling in ways tests may miss.

## Review GitHub workflow changes manually
- **Paths**: `.github/workflows/**`
- **Severity**: critical
- **Reason**: Workflow trigger, permission, or concurrency changes can weaken security or skip required checks across pull requests.

## Review protocol and agent guidance docs
- **Paths**: `docs/workflow/**`, `docs/specs/**`, `docs/testing/workflow/**`, `.claude/commands/**`, `.cursor/commands/**`, `.claude/agents/**`, `.cursor/agents/**`, `.codex/skills/**`, `REVIEW.md`, `AGENTS.md`
- **Severity**: medium
- **Reason**: Instruction wording changes can redirect automation behavior even when code checks still pass.

## Review release and changelog automation
- **Paths**: `CHANGELOG.md`, `.github/workflows/auto-tag-release.yml`
- **Severity**: critical
- **Reason**: Version parsing or changelog structure mistakes can create incorrect release tags that are hard to undo.

## Review reviewer config coverage settings
- **Paths**: `.coderabbit.yaml`, `.ai-dev-workflow.yaml`
- **Severity**: high
- **Reason**: Config changes can silently reduce reviewer coverage or alter draft pull request gating.

## Instructions
- If a change removes or reorders lock, unlock, retry, or other safety guards, a human must confirm failure recovery is still safe.
- If a change switches behavior between fail open, fail closed, warning, skip, clean, or escalate, a human must approve the risk tradeoff.
- If a change remaps reviewer failures or timeouts to outcomes, a human must verify the operational impact is intended.
- If retry counts, polling intervals, or wait budgets change, a human must confirm the balance between speed and missed findings.
- If a change alters when readiness or regression labels are applied or removed, a human must confirm workflow gates still match team intent.
- If reviewer availability drops or warn-only behavior is used, a human must decide whether reduced coverage is acceptable for that pull request.
- If automation cannot post review summary output and manual recovery is used, a human must confirm the evidence is sufficient to proceed.
- If a pull request expands beyond approved scope or defers advisory findings, a human must decide whether the remaining risk is acceptable.
- If Haystack mirror guidance changes, verify the live agent-doc surface map first. Treat tool-specific front matter differences and absent `.cursor/skills` surfaces as advisory-only unless a real mirrored workflow body mismatch remains.

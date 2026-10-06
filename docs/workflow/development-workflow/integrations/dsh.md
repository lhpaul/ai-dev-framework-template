# Integration: DeepSeek Harness (DSH)

DSH is a first-class **local-runtime** runner for this template’s staged workflow:
command matrices, Protocol 91 Step 7a draft review, shared reviewer skills against
[`REVIEW.md`](../../../../REVIEW.md), model-tier guidance, and provider failover.

The shipped `review.on_draft.runner` list remains Claude-only (`[claude]`). Opt DSH
into Step 7a with a machine-local override — do not change the shared template
default for clones that do not install DSH.

Minimum CLI verified for the contracts below: `dsh` `0.2.0-rc.2` (`dsh --version`).
Re-verify headless and permission-preset wiring after major DSH upgrades.

---

## Install

1. Install the DeepSeek Harness CLI so the `dsh` binary is on `PATH`.
2. Confirm the probe used by Step 7a availability:

   ```bash
   dsh --version
   ```

3. Boot a profile once to complete provider auth / settings for your machine
   (interactive `web` is the usual first path; see Profiles).

This template does **not** package or distribute the DSH binary. Availability
probing is `dsh --version` via the same local-runtime path as Claude / Cursor /
Codex (`scripts/development-workflow/resolve-reviewer-availability.sh`).

---

## Profiles

A **profile** is what `dsh --profile <name>` boots (an ordered stack of plugin-bundle
layers under local overrides). Common shipped profiles:

| Profile | Use |
| ------- | --- |
| `web` | Interactive browser UI (loopback). |
| `headless` | One-shot task: print the final answer to stdout and exit. |

Examples:

```bash
dsh web
dsh --profile headless "Summarize the open PR"
```

`dsh headless …` is accepted as a short form of `dsh --profile headless …`.

---

## Provider routes

DSH composes model routes from the active profile’s bundle and the user’s local
settings (not from in-repo agent frontmatter). The base bundle’s default route is
provider/model configuration owned by the DSH install — operators pin or swap
routes in DSH settings / profile overlays, then keep workflow **tier intent**
stable (see [`agent-model-config.md`](../agent-model-config.md)).

Commercial API keys and org credentials stay outside the repository (1Password or
the harness’s own credential store). This guide does not invent vendor-specific
setup beyond “configure a working route before relying on headless review.”

---

## Subagent model selection

DSH has **no** in-repo per-role agent tree analogous to `.claude/agents/` or
`.cursor/agents/`. Stage reviews dispatch the shared workflow skills Codex uses:

| Stage | Skill (against `REVIEW.md`) |
| ----- | --------------------------- |
| Spec | `workflow-spec-reviewer` |
| Plan | `workflow-plan-reviewer` |
| Implementation | `workflow-code-reviewer` |

Pin provider/model for a review at **dispatch time** (CLI / profile / env for that
invocation), not by editing a checked-in role file. Map the skill’s recommended
tier (`economy` / `balanced` / `premium`) to the DSH route you assign for that run
— see [`agent-model-config.md`](../agent-model-config.md).

---

## Headless mode (cross-runner read-only review)

For one-shot reviews from another runner or automation, use the headless profile
and compose the shipped base-bundle **`read-only` permission preset** through
`DSH_PERMISSION_MODE`. Prompt-only “do not write files” instructions are **not**
sufficient for Step 7a cross-runner parity with Codex’s read-only sandbox.

```bash
DSH_PERMISSION_MODE=read-only dsh --profile headless \
  "Read-only review against REVIEW.md for <stage>. Emit exactly one line: VERDICT: APPROVED or VERDICT: NEEDS REVISION."
```

- Final answer goes to **stdout**; diagnostics go to stderr.
- Exit `0` with exactly one valid terminal verdict is required for approval
  (same parent-owned fix / re-run contract as other local-runtime CLIs in
  Protocol 91 Step 7a).
- Never add permission-bypass flags.

Protocol reference: Step 7a “Reviewer dispatch map” cross-runner CLI paragraph in
[`91-orchestrate-work-protocol.md`](../protocols/91-orchestrate-work-protocol.md).

---

## Opt into Step 7a draft review

In `.ai-dev-workflow.local.yaml` (gitignored):

```yaml
review:
  on_draft:
    runner:
      - claude
      - dsh
```

Under the shipped `warn` availability policy, a configured-but-absent `dsh`
binary is `runtime-absent` with the shared install-or-remove remedy; it does not
invent a harder DSH-only failure mode. With only `dsh` configured and the binary
missing, the gate still hard-fails as `zero-reachable`.

Draft-restriction: **Never** — DSH reviews draft PRs without requiring
draft-to-ready conversion solely for DSH eligibility.

---

## Parent-orchestrated dispatch

**Default contract for DSH:** parent-orchestrated.

The driving session (Work Item Runner / Protocol 91) absorbs item orchestration
and hands stage review work to the shared reviewer skill for the active branch
prefix. DSH does **not** rely on a separate two-hop native handoff profile
document (unlike Cursor’s [`cursor-dispatch-profiles.md`](cursor-dispatch-profiles.md)).

Implications:

1. Do not create a `dsh-dispatch-profiles.md` (or similar) sibling document for
   this feature — dispatch guidance lives in **this section only**.
2. The parent owns deterministic fixes, commits, pushes, and required review
   re-runs after a cross-runner headless verdict (Protocol 91).
3. Failover to Claude / Cursor / Codex uses the same protocols and shared skills;
   only the invocation surface changes — see
   [`provider-contingency-runner-failover.md`](../provider-contingency-runner-failover.md).

---

## Related surfaces

| Surface | Role |
| ------- | ---- |
| [`REVIEW.md`](../../../../REVIEW.md) | Canonical review contract |
| Protocol 91 Step 7a | Availability, draft-restriction, dispatch map |
| [`agent-model-config.md`](../agent-model-config.md) | Tier mapping + DSH pinning notes |
| [`provider-contingency-runner-failover.md`](../provider-contingency-runner-failover.md) | Runner-unavailable failover |
| `.ai-dev-workflow.yaml` / `.ai-dev-workflow.local.yaml` | Supported values vs local opt-in |

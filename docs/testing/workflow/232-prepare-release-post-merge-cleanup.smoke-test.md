# Smoke Test Runbook: prepare-release post-merge cleanup (#232)

**Feature**: Post-merge release branch deletion and `Merged` → `Released` tracker transitions after both release PRs merge  
**Spec**: [`1_prepare-release-post-merge-cleanup_specs.md`](../../specs/developments/20260420182725_prepare-release-post-merge-cleanup/1_prepare-release-post-merge-cleanup_specs.md)  
**Created in**: Plan Ready stage  
**Updated in**: In Development stage

---

## Prerequisites

Before running this smoke test:

- [ ] Repository root: `cd` to your clone of this template
- [ ] `gh` CLI authenticated (`gh auth status`)
- [ ] **Implementation landed**: protocol `05-prepare-release-protocol.md` documents post-merge steps; `prepare-release-post-merge-cleanup.sh` (or equivalent from the implementation plan) exists and is executable
- [ ] For tracker steps (optional): `GITHUB_PROJECT_OWNER`, `GITHUB_PROJECT_NUMBER` set; project has Status options including **Merged** and **Released** (or configured equivalents)

> **Note**: Steps 1–3 validate documentation and refusal paths without mutating `origin`. Steps 4–5 perform destructive git remote operations — use a fork or test repo unless you intentionally want to delete a real `release/v*` branch.

---

## Test Data

| Item | Value |
|---|---|
| Example version | `0.99.0` (replace with a non-production test version when using a fork) |
| Release branch | `release/v0.99.0` |
| Script path | `./scripts/development-workflow/prepare-release-post-merge-cleanup.sh` (adjust if final name differs) |

---

## Smoke Test Steps

### Step 1: Protocol documents branch-delete precondition

**Maps to**: Acceptance Criterion — “no step tells them to delete the release branch before both PRs are merged”

1. Open `docs/ai/development-workflow/protocols/05-prepare-release-protocol.md`.
2. Search for the post-merge / cleanup section added for this feature.
3. Confirm the text states branch deletion is allowed **only after** both the production (`main`) and backport (`develop`) PRs for that release branch are merged.

**Expected result**: Precondition is explicit and appears **before** the `git push origin --delete` instruction.

---

### Step 2: Protocol documents tracker transition and configuration

**Maps to**: Acceptance Criterion — tracker transition uses GitHub Projects / GraphQL class of mechanism; configurable terminal status

1. In the same protocol section (or linked integration doc), confirm documented steps reference `gh project` / GraphQL-style updates consistent with `post-merge-cleanup.sh`.
2. Confirm documentation explains how to configure the terminal shipped status when it is not literally named **Released** (env var or config key as implemented).

**Expected result**: Operator can find configuration instructions without reading source-only comments.

---

### Step 3: Script / protocol — only one PR merged

**Maps to**: Acceptance Criterion — edge case “only one PR merged”

1. With **no** fully merged pair (or using a stub version where the backport is still open), run the cleanup script for that version (exact CLI from implementation).
2. Observe exit code and stderr/stdout.

**Expected result**: Non-success exit or explicit “blocked” message; **no** `git push origin --delete` is executed (verify with `git log` / shell trace if script supports `--dry-run`, or read script behavior).

---

### Step 4: Happy path — branch cleanup (fork / disposable branch only)

**Maps to**: Use Case 1 (release branch cleanup)

1. Ensure both PRs for `release/vX.Y.Z` are merged on your test remote.
2. Run the cleanup script for `X.Y.Z`.
3. Run `git ls-remote --heads origin "refs/heads/release/vX.Y.Z"` — expect empty after remote delete.
4. If a local `release/vX.Y.Z` existed: confirm it is removed or instructions printed for manual delete when checked out.

**Expected result**: Remote branch absent; local cleanup succeeded or documented retry path.

---

### Step 5: Tracker transition (GitHub Projects)

**Maps to**: Use Case 2; Operational visibility

1. Pick a test issue on the board in **Merged** that is in scope for the fake release (per implementation’s scoping rules).
2. Run the script’s tracker mode per implementation (flags as documented).
3. In GitHub Projects UI, confirm the issue Status is now **Released** (or configured equivalent).
4. Confirm another **Merged** issue *not* in scope remains **Merged**.

**Expected result**: Scoped transition only; console logs show success or skip with reason.

---

### Last Step: Validate & Shut Down

- Verify every checkbox in **Assertions Checklist** below
- No lingering test branches on shared `origin` unless intentional

---

## Assertions Checklist

- [ ] Protocol lists remote and local release branch cleanup after both PRs merge (**AC**).
- [ ] Protocol documents `Merged` → shipped terminal status transition using same integration approach as `post-merge-cleanup.sh` (**AC**).
- [ ] “Only one PR merged” is explicitly called out; automation refuses early branch delete (**AC**).
- [ ] Smoke test runbook paths remain valid relative links after any file renames.

---

## Seed Data Reference

Not applicable (no DB seeds). GitHub test issues and project board state are the live “fixtures.”

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Warning: GITHUB_PROJECT_NUMBER not set` | Env not exported | Export vars or skip tracker steps |
| `cannot delete branch` checked out | Current branch is release branch | `git switch develop` then rerun |
| Script says PR not merged | Query mismatch / wrong version | Re-check `gh pr list --head release/vX.Y.Z` |

---

## Known Limitations

- Full remote-delete validation requires a repository where you are allowed to delete `release/*` branches.

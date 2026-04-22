---
description: >
  Sync framework updates from the upstream template into this project.
  Compares template files (local path or remote ref) against this project,
  shows a categorized diff for review, applies approved changes, and generates
  ready-to-use git instructions (branch + commit + PR). Run from the project root.
  Usage: /sync-template [--local=/path/to/template] [--ref=<branch|tag>]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(git rev-parse:*), Bash(git status:*), Bash(git branch:*), Bash(git clone:*), Bash(git diff:*), Bash(git add:*), Bash(git commit:*), Bash(git checkout:*), Bash(git push:*), Bash(cat:*), Bash(cp:*), Bash(find:*), Bash(ls:*), Bash(mkdir:*), Bash(rm:*), Bash(date:*), Bash(jq:*), Bash(diff:*), Bash(chmod:*)
---

Follow this workflow exactly when invoked. Do not skip steps or reorder them.

---

## Step 0 — Parse arguments and determine template source

Parse the user's arguments:

- `--local=/path/to/template` → use that local directory as the template source
- `--ref=<branch|tag>` → fetch remote at that ref (e.g., `--ref=main`, `--ref=v0.4.0`)
- No arguments → check `.tmp/template-config.json` in the current project

**If `.tmp/template-config.json` exists**, read it and use the saved source:
```json
{ "templatePath": "../ai-dev-framework-template" }
```
or
```json
{ "templateUrl": "https://github.com/org/repo" }
```

**If no arguments and no config file**, ask the user:
> "I need to know where to find the upstream template. Do you want to use a local path (e.g., `../ai-dev-framework-template`) or a remote GitHub URL? I'll save your answer to `.tmp/template-config.json` for future runs."

Save the user's answer to `.tmp/template-config.json` before continuing (create the `.tmp` directory if needed; it is gitignored).

**Remote fetch** (when a URL source is used):

```bash
TEMPLATE_TEMP_DIR="/tmp/template-sync-$(date +%s)"
git clone --depth=1 --branch=<ref> <url> "$TEMPLATE_TEMP_DIR"
```

Store the exact path in `TEMPLATE_TEMP_DIR` — you must clean up this specific directory at the end (never use a wildcard).
If `--ref` is not specified for a remote source, use the default branch (`main`).

Once the template source is resolved, read its `CHANGELOG.md` and extract the latest version number (first `[X.Y.Z]` entry after `[Unreleased]` if present, otherwise the first versioned entry). Store it as `TEMPLATE_VERSION`.

**Manifest check**: After resolving the template source, check for `sync-manifest.yaml` at the template root.

- If found: read it and store its contents as `SYNC_MANIFEST`. The manifest is the authoritative file list (BR-1).
- If absent: set `SYNC_MANIFEST=absent`. The graceful fallback (BR-4 / AC-4) activates in Step 2 — the embedded lists below are used and a warning is shown.

---

## Step 1 — Pre-flight checks on the current project

Run these checks **before touching anything**. If any check fails, report the problem clearly and abort.

1. **Is this a git repository?**
   ```bash
   git rev-parse --is-inside-work-tree
   ```

2. **Is the working directory clean?**
   ```bash
   git status --porcelain
   ```
   Must return empty output. If there are staged, unstaged, or untracked changes, abort with:
   > "Your working directory has uncommitted changes. Please commit or stash them before syncing."

3. **Is the project on the correct base branch?**
   ```bash
   git branch --list develop
   git branch --show-current
   ```
   - If `develop` branch exists → must be on `develop`
   - If `develop` does not exist → must be on `main`

   If on the wrong branch, abort with:
   > "You must be on the `develop` branch (or `main` if `develop` doesn't exist) before syncing. Please switch branches and try again."

---

## Step 2 — Compare files

Use `SYNC_MANIFEST` to determine the file lists. If `SYNC_MANIFEST=absent`, fall back to the embedded lists in each section below and display this warning before continuing:

> "Warning: sync manifest not found in upstream template. Using embedded file list — results may be incomplete."

### Always sync (apply automatically after approval)

**If `SYNC_MANIFEST` is loaded**: read `categories.always_sync` from the manifest and enumerate those paths from the template. Each entry may specify a `path` (single file or directory prefix) and an optional `glob` pattern for recursive enumeration.

**If `SYNC_MANIFEST=absent`** (fallback): use the embedded list below.

```
REVIEW.md                         <- canonical review contract for spec, plan, and code review gates
docs/workflow/                          <- full tree, all files recursively
.claude/agents/                   <- all *.md files
.claude/commands/                 <- all *.md files
.claude/skills/                   <- all *.md files (including this skill itself)
.codex/skills/                    <- Codex skill trees shipped with the template (SKILL.md and assets)
.cursor/commands/                 <- all *.md files
.cursor/agents/                   <- all *.md files
.cursor/rules/                    <- all *.mdc files
scripts/development-workflow/     <- workflow helper scripts (discover state, PR/CI loops, etc.)
scripts/README.md                 <- purpose and usage of scripts in scripts/
docs/best-practices/1-general.md
docs/best-practices/2-version-control.md
docs/best-practices/3-testing.md
```

**Comparison method:** For each path in the always-sync list, enumerate files with `find` (or equivalent) and compare each path to the template using `cmp` or `diff -q`. Do not rely on ad-hoc agent inspection alone — a missed directory is a silent sync gap.

For each file in these paths:
- **Exists in template, not in project** → classify as **Add**
- **Exists in both, content differs** → classify as **Update** (prepare a concise diff summary)
- **Exists in both, content identical** → classify as **No change** (list but don't highlight)
- **Exists in project, not in template** → **ignore** (never delete project-only files)

### Special handling (show full diff, user decides per file)

**If `SYNC_MANIFEST` is loaded**: read `categories.special_handling` from the manifest.

**If `SYNC_MANIFEST=absent`** (fallback): use the embedded list below.

```
.claude/settings.json                          <- may have project-specific permissions
.claude/settings.local.json.example
.github/workflows/auto-tag-release.yml         <- automated release tagging; add if CI is set up
.github/workflows/deploy.yml                   <- placeholder deployment workflow; customize with project-specific deploy logic
.github/workflows/e2e-regression.yml           <- label-gated e2e/regression placeholder; customize with project-specific test logic
e2e/                                           <- placeholder e2e/regression test project (Playwright); customize with project-specific tests
```

For each of these: show the full diff and ask the user explicitly whether to apply it.

### Project-specific files (review for additive updates — never overwrite)

These paths are project-specific and must **not** be overwritten by the template. The agent should still **read and compare** the template versions with the project's versions. Many of these files in downstream projects will have come from this template, so template improvements (new sections, clarified wording, updated links) may be useful. When the template has content that could benefit the project, the agent may **propose additive updates**: suggest adding or merging that content while **preserving all project-specific information** and avoiding inconsistencies.

**Critical:** Do not remove or replace content that is specific to the project. Only suggest additions or merges that clearly originate from the template and do not conflict with project-only content. When in doubt, list the difference under "Optional additive update" and let the user decide.

**If `SYNC_MANIFEST` is loaded**: read `categories.project_specific` from the manifest. For entries with `mixed_content: true`, also read the `annotation_scheme` field and apply the mixed-content extraction logic described below.

**If `SYNC_MANIFEST=absent`** (fallback): use the embedded list below.

```
AGENTS.md
README.md
CHANGELOG.md
.ai-dev-workflow.yaml
docs/project/
docs/best-practices/STACK-SPECIFIC.md
docs/best-practices/stack/
.gitignore
CLAUDE.md
GEMINI.md
```

For each of these: if template and project differ, show what the template has that the project might want to add; classify as **Optional additive update** (user decides). Do not apply changes to these paths without explicit user approval.

Everything else not listed above (application code, project configs, etc.) is also never overwritten.

### Mixed-content extraction logic

When a file has `mixed_content: true` and `annotation_scheme: html_comments` in the manifest, use the following extraction logic when comparing to the upstream template:

**Detection by file extension:**

- For `.md` files: match lines that are exactly `<!-- TEMPLATE-OWNED-START -->` and `<!-- TEMPLATE-OWNED-END -->`.
- For `.yaml` / `.yml` files: match lines that are exactly `# <!-- TEMPLATE-OWNED-START -->` and `# <!-- TEMPLATE-OWNED-END -->` (YAML comment prefix required).

**Extraction behaviour:**

- Extract only the content between `TEMPLATE-OWNED-START` and `TEMPLATE-OWNED-END` marker pairs for comparison and diffing.
- Show only the extracted template-owned sections in the diff. Label all other sections as "preserved — no change" in the summary (UX Rule 2).
- If markers are absent or malformed in the downstream copy of the file, flag the file as "unstructured — full review required" and show a full diff instead. Do NOT attempt an automatic merge in this case (UX Rule 3).

---

## Step 3 — Present the change summary

Show a structured summary before asking for confirmation. Include file counts per category before the file lists so the maintainer can quickly detect an unexpectedly small always-sync list (UX Rule 1 / AC-5). Example format:

```
## Template Sync Summary
Template version: v0.4.0  |  Project branch: develop
Manifest: loaded from sync-manifest.yaml  (or: "not found — using embedded fallback list")

### Always-sync files: N total (A to add, U to update, C up-to-date)

#### New files (will be added): A
  .claude/skills/sync-template.md

#### Modified files (will be updated): U
  .claude/agents/developer.md
    Line 3: model: claude-sonnet-4-5 -> model: claude-sonnet-4-6

  docs/workflow/development-workflow/protocols/91-orchestrate-work-protocol.md
    [diff summary]

#### Already up to date (no changes): C
  docs/best-practices/1-general.md
  .cursor/rules/code.mdc
  ... (N files)

### Requires manual review (you decide)
  .claude/settings.json
    [full diff shown here]

### Optional additive updates (project-specific — you decide)
  AGENTS.md — template has [brief description]; project keeps its own content; suggest adding: ...
  README.md — no template additions suggested
  ...
```

After applying changes, show a final disposition summary with separate counts (AC-5 / UX Rule 4):

```
### Sync complete

Always-sync disposition:
  Updated:              N files
  Up-to-date (skipped): N files
  Declined by maintainer: N files
```

Then ask:
> "Ready to apply the changes above? For paths listed under **New files** and **Modified files** in the **always-sync** section only, I can apply them in one batch when you confirm. Special-handling and optional additive-update sections always need explicit per-path approval — bulk phrases like \"apply all\" never include those categories."

**Do not modify any files until you have explicit confirmation.**

---

## Step 4 — Apply changes (only after approval)

Apply approved changes:

- Copy/overwrite all **Add** and **Update** files **from the always-sync Step 3 section only** when the user confirms that batch. Phrases such as "apply all", "apply everything", or "yes to all" mean **always-sync files only** — they **never** authorize applying **special-handling** paths (`.github/workflows/deploy.yml`, `e2e-regression.yml`, `e2e/`, `.claude/settings.json`, etc.) or **optional additive updates**; those require the user to name each approved path (or `none`).
- **Placeholder guard for workflow YAML** (`.github/workflows/deploy.yml`, `.github/workflows/e2e-regression.yml`): Before overwriting the project copy with the template, compare line counts. If the **project** file has **more lines** than the template and the template has **fewer than 70%** of the project's line count, treat this as likely "real implementation → template placeholder" and **refuse** unless the user sends a **second** explicit confirmation naming that exact file.
- For files requiring manual review: apply only those the user explicitly approved (including any optional additive updates to project-specific files — merge or add only, never remove project-specific content)
- Do **not** delete any file
- Do **not** overwrite project-specific files; for those paths only additive/merge changes are allowed, and only with explicit approval

If the template source was a remote clone, clean up the exact temp directory recorded in Step 0:

```bash
rm -rf "$TEMPLATE_TEMP_DIR"   # use the exact path, not a wildcard
```

---

## Step 5 — Generate git instructions

Print ready-to-use git instructions (do not execute them — let the user run them after reviewing the changes):

```bash
# 1. Create a sync branch
git checkout -b feature/sync-template-v{TEMPLATE_VERSION}

# 2. Review the changes
git diff --stat

# 3. Stage and commit (only after you've reviewed the changes)
# Stage only approved paths — avoid 'git add .' so unapproved files never enter the commit.
git add REVIEW.md docs/workflow/ .claude/agents/ .claude/commands/ .claude/skills/ .codex/skills/ .cursor/ \
  scripts/development-workflow/ scripts/README.md \
  docs/best-practices/1-general.md \
  docs/best-practices/2-version-control.md \
  docs/best-practices/3-testing.md
# If sync-manifest.yaml was updated, stage it as well:
git add sync-manifest.yaml
# If the user explicitly approved additional paths in Step 4, 'git add' those paths too.
git commit -m "chore(template): sync framework updates from template v{TEMPLATE_VERSION}"

# 4. Push and open PR
git push -u origin feature/sync-template-v{TEMPLATE_VERSION}
```

**Suggested PR description:**
```
## Template sync: v{TEMPLATE_VERSION}

Sync framework-level files from [ai-dev-framework-template](TEMPLATE_URL) v{TEMPLATE_VERSION}.

### Changes included
[Paste the relevant section from the template's CHANGELOG.md here]

### What was NOT overwritten
Project-specific files (AGENTS.md, README.md, CHANGELOG.md, docs/project/, etc.)
were not overwritten; optional additive updates from the template may have been applied where you approved them, with project-specific content preserved.
```

Paste the relevant section from the template's `CHANGELOG.md` into the PR description placeholder.

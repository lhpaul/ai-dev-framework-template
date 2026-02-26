---
description: >
  Sync framework updates from the upstream template into this project.
  Compares template files (local path or remote ref) against this project,
  shows a categorized diff for review, applies approved changes, and generates
  ready-to-use git instructions (branch + commit + PR). Run from the project root.
  Usage: /sync-template [--local=/path/to/template] [--ref=<branch|tag>]
---

Follow this workflow exactly when invoked. Do not skip steps or reorder them.

---

## Step 0 — Parse arguments and determine template source

Parse the user's arguments:

- `--local=/path/to/template` → use that local directory as the template source
- `--ref=<branch|tag>` → fetch remote at that ref (e.g., `--ref=main`, `--ref=v0.4.0`)
- No arguments → check `.claude/template-config.json` in the current project

**If `.claude/template-config.json` exists**, read it and use the saved source:
```json
{ "templatePath": "../ai-dev-framework-template" }
```
or
```json
{ "templateUrl": "https://github.com/org/repo" }
```

**If no arguments and no config file**, ask the user:
> "I need to know where to find the upstream template. Do you want to use a local path (e.g., `../ai-dev-framework-template`) or a remote GitHub URL? I'll save your answer to `.claude/template-config.json` for future runs."

Save the user's answer to `.claude/template-config.json` before continuing.

**Remote fetch** (when a URL source is used):
```bash
git clone --depth=1 --branch=<ref> <url> /tmp/template-sync-$(date +%s)
```
Remember the temp path — you must clean it up at the end.
If `--ref` is not specified for a remote source, use the default branch (`main`).

Once the template source is resolved, read its `CHANGELOG.md` and extract the latest version number (first `[X.Y.Z]` entry after `[Unreleased]` if present, otherwise the first versioned entry). Store it as `TEMPLATE_VERSION`.

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
   > "⚠️ Your working directory has uncommitted changes. Please commit or stash them before syncing."

3. **Is the project on the correct base branch?**
   ```bash
   git branch --list develop
   git branch --show-current
   ```
   - If `develop` branch exists → must be on `develop`
   - If `develop` does not exist → must be on `main`

   If on the wrong branch, abort with:
   > "⚠️ You must be on the `develop` branch (or `main` if `develop` doesn't exist) before syncing. Please switch branches and try again."

---

## Step 2 — Compare files

Compare the following **framework-level paths** from the template against the current project.

### Always sync (apply automatically after approval)

```
docs/ai/                          ← full tree, all files recursively
.claude/agents/                   ← all *.md files
.claude/skills/                   ← all *.md files (including this skill itself)
.cursor/commands/                 ← all *.md files
.cursor/rules/                    ← all *.mdc files
docs/best-practices/1-general.md
docs/best-practices/2-version-control.md
docs/best-practices/3-testing.md
```

For each file in these paths:
- **Exists in template, not in project** → classify as ✅ **Add**
- **Exists in both, content differs** → classify as 📝 **Update** (prepare a concise diff summary)
- **Exists in both, content identical** → classify as ⏭ **No change** (list but don't highlight)
- **Exists in project, not in template** → **ignore** (never delete project-only files)

### Special handling (show full diff, user decides per file)

```
.claude/settings.json             ← may have project-specific permissions
.claude/settings.local.json.example
```

For each of these: show the full diff and ask the user explicitly whether to apply it.

### Never touch (project-specific — always skip, no mention needed)

```
AGENTS.md
README.md
CHANGELOG.md
docs/project/
docs/best-practices/STACK-SPECIFIC.md
docs/best-practices/stack/
.gitignore
CLAUDE.md
GEMINI.md
```

Everything else not listed above (application code, project configs, etc.) is also never touched.

---

## Step 3 — Present the change summary

Show a structured summary before asking for confirmation. Example format:

```
## Template Sync Summary
Template version: v0.4.0  |  Project branch: develop

### ✅ New files (will be added)
  .claude/skills/sync-template.md

### 📝 Modified files (will be updated)
  .claude/agents/developer.md
    Line 3: model: claude-sonnet-4-5 → model: claude-sonnet-4-6

  docs/ai/development-workflow/protocols/90-orchestrate-work-protocol.md
    [diff summary]

### ⏭ Already up to date (no changes)
  docs/best-practices/1-general.md
  .cursor/rules/code.mdc
  ... (N files)

### ⚠️ Requires manual review (you decide)
  .claude/settings.json
    [full diff shown here]

### 🚫 Skipped (project-specific — never overwritten)
  AGENTS.md, README.md, CHANGELOG.md, docs/project/, ...
```

Then ask:
> "Ready to apply the changes above? For the files marked ✅ and 📝, I'll apply them automatically. For ⚠️ files, please tell me which ones to apply."

**Do not modify any files until you have explicit confirmation.**

---

## Step 4 — Apply changes (only after approval)

- Copy/overwrite all ✅ (Add) and 📝 (Update) files from the template source into the project
- For ⚠️ files: apply only those the user explicitly approved
- Do **not** delete any file
- Do **not** modify any path in the "Never touch" list

If the template source was a remote clone, clean it up now:
```bash
rm -rf /tmp/template-sync-*
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
git add docs/ai/ .claude/agents/ .claude/skills/ .cursor/ \
  docs/best-practices/1-general.md \
  docs/best-practices/2-version-control.md \
  docs/best-practices/3-testing.md
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

### What was NOT changed
Project-specific files (AGENTS.md, README.md, CHANGELOG.md, docs/project/, etc.)
are intentionally excluded from this sync.
```

Paste the relevant section from the template's `CHANGELOG.md` into the PR description placeholder.

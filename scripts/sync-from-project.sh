#!/usr/bin/env bash
# sync-from-project.sh
#
# Backports framework improvements from a project back to this template.
# Use when you've improved a protocol, agent, or best practice while working
# on a project and want to update the upstream template.
#
# Usage:
#   ./scripts/sync-from-project.sh /path/to/your-project
#   ./scripts/sync-from-project.sh /path/to/your-project --dry-run
#
# Only syncs framework-level files (same set as sync-to-project.sh).
# Review the diff carefully before committing — project-specific content
# should NOT end up in the template.

set -euo pipefail

# ── Helpers ────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${CYAN}▸ $*${RESET}"; }
success() { echo -e "${GREEN}✓ $*${RESET}"; }
warn()    { echo -e "${YELLOW}⚠ $*${RESET}"; }
error()   { echo -e "${RED}✗ $*${RESET}" >&2; }

# ── Args ───────────────────────────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <source-project-path> [--dry-run]"
  exit 1
fi

SOURCE="$1"
DRY_RUN=false
if [[ "${2:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

TEMPLATE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ── Validate ───────────────────────────────────────────────────────────────────

if [[ ! -d "$SOURCE" ]]; then
  error "Source directory not found: $SOURCE"
  exit 1
fi

# ── Files and directories to sync (same as sync-to-project.sh) ───────────────

SYNC_DIRS=(
  "docs/ai"
  ".claude/agents"
  ".cursor/rules"
  ".cursor/commands"
)

SYNC_FILES=(
  "docs/best-practices/1-general.md"
  "docs/best-practices/2-version-control.md"
  "docs/best-practices/3-testing.md"
)

# ── Preview ───────────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}AI Dev Framework — Backport from Project${RESET}"
echo -e "  Source   : ${SOURCE}"
echo -e "  Template : ${TEMPLATE_ROOT}"
if $DRY_RUN; then
  echo -e "  Mode     : ${YELLOW}DRY RUN — no changes will be made${RESET}"
fi
echo ""
warn "Review the diff carefully after syncing."
warn "Project-specific content should NOT end up in the template."
echo ""

# ── Sync directories ──────────────────────────────────────────────────────────

echo -e "${BOLD}Directories:${RESET}"
for dir in "${SYNC_DIRS[@]}"; do
  src="${SOURCE}/${dir}"
  dest="${TEMPLATE_ROOT}/${dir}"

  if [[ ! -d "$src" ]]; then
    warn "Source directory not found, skipping: ${dir}/"
    continue
  fi

  if $DRY_RUN; then
    info "[dry-run] Would sync: ${dir}/"
  else
    rm -rf "$dest"
    mkdir -p "$(dirname "$dest")"
    cp -r "$src" "$dest"
    success "Synced: ${dir}/"
  fi
done

echo ""

# ── Sync individual files ─────────────────────────────────────────────────────

echo -e "${BOLD}Files:${RESET}"
for file in "${SYNC_FILES[@]}"; do
  src="${SOURCE}/${file}"
  dest="${TEMPLATE_ROOT}/${file}"

  if [[ ! -f "$src" ]]; then
    warn "Source file not found, skipping: ${file}"
    continue
  fi

  if $DRY_RUN; then
    info "[dry-run] Would sync: ${file}"
  else
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
    success "Synced: ${file}"
  fi
done

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
if $DRY_RUN; then
  warn "Dry run complete. Run without --dry-run to apply changes."
else
  success "Backport complete."
  echo ""
  echo -e "${BOLD}IMPORTANT — Before committing:${RESET}"
  echo "  Review the diff to ensure no project-specific content was imported:"
  echo "  cd \"${TEMPLATE_ROOT}\" && git diff"
  echo ""
  echo "  If the changes look good:"
  echo "  git add -A && git commit -m 'feat: backport improvements from [project-name]'"
  echo "  git push"
fi
echo ""

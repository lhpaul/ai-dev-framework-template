#!/usr/bin/env bash
#
# Cloud Agent install script for the AI dev framework template.
#
# Idempotent, non-interactive repository bootstrap. Prepares everything the
# repository's lint tooling and workflow test harnesses need:
#   - Node dependencies for markdownlint (npm ci from the committed lockfile)
#   - shellcheck  (ShellCheck static analysis of scripts/development-workflow)
#   - zsh         (cross-shell snippet-lint test suite)
#   - PyYAML      (workflow test suites that parse workflow YAML with Python)
#
# Safe to run repeatedly: apt install is a no-op when packages are present and
# npm ci reconciles node_modules to the lockfile.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

log() { printf '[cloud-agent-install] %s\n' "$*"; }

install_system_packages() {
  local missing=()
  command -v shellcheck >/dev/null 2>&1 || missing+=(shellcheck)
  command -v zsh >/dev/null 2>&1 || missing+=(zsh)
  # python3-yaml backs `import yaml` for the workflow test harnesses.
  python3 -c 'import yaml' >/dev/null 2>&1 || missing+=(python3-yaml)

  if [ "${#missing[@]}" -eq 0 ]; then
    log "system packages already present: shellcheck, zsh, python3-yaml"
    return 0
  fi

  local sudo=""
  if [ "$(id -u)" -ne 0 ]; then
    command -v sudo >/dev/null 2>&1 && sudo="sudo"
  fi

  log "installing system packages: ${missing[*]}"
  DEBIAN_FRONTEND=noninteractive $sudo apt-get update -o Acquire::Retries=3
  DEBIAN_FRONTEND=noninteractive $sudo apt-get install --yes --no-install-recommends "${missing[@]}"
}

install_node_dependencies() {
  if [ ! -f package-lock.json ]; then
    log "no package-lock.json found; skipping npm ci"
    return 0
  fi
  log "installing Node dependencies (npm ci)"
  npm ci
}

install_system_packages
install_node_dependencies

log "verifying toolchain"
node --version
npm --version
python3 --version
python3 -c 'import yaml; print("PyYAML", yaml.__version__)'
shellcheck --version | sed -n '2p'
zsh --version
./node_modules/.bin/markdownlint-cli2 --version

log "install complete"

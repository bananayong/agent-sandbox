#!/bin/bash
set -euo pipefail

# Build smoke test: verify key tools are present and runnable.
# Run after docker build to catch missing or broken binaries.
#
# Usage:
#   smoke-test.sh              # full test (runtime)
#   smoke-test.sh --build      # skip docker/socket-dependent checks (build time)

FAILED=0
SKIP_DOCKER=false
if [[ "${1:-}" == "--build" ]]; then
  SKIP_DOCKER=true
fi

check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  OK   $name"
  else
    echo "  FAIL $name ($*)"
    FAILED=1
  fi
}

echo "=== Agent Sandbox Smoke Test ==="
echo ""
echo "--- Coding Agents ---"
check "claude"    claude --version
check "codex"     codex --version
check "gemini"    gemini --version
check "opencode"  opencode --version

echo ""
echo "--- Core Tools ---"
check "git"       git --version
if [[ "$SKIP_DOCKER" == false ]]; then
  check "docker"  docker --version
fi
check "gh"        gh --version
check "node"      node --version
check "bun"       bun --version
check "python3"   python3 --version

echo ""
echo "--- Shell Tools ---"
check "bat"       bat --version
check "eza"       eza --version
check "fd"        fd --version
check "fzf"       fzf --version
check "rg"        rg --version
check "dust"      dust --version
check "procs"     procs --version
check "btm"       btm --version
check "xh"        xh --version
check "mcfly"     mcfly --version
check "zoxide"    zoxide --version
check "starship"  starship --version
check "micro"     micro --version
check "delta"     delta --version
check "lazygit"   lazygit --version
check "gitui"     gitui --version
check "tokei"     tokei --version
check "yq"        yq --version
check "jq"        jq --version
check "tmux"      tmux -V
check "direnv"    direnv version

echo ""
echo "--- Security/Quality Tools ---"
check "pre-commit"  pre-commit --version
check "gitleaks"    gitleaks version
check "hadolint"    hadolint --version
check "shellcheck"  shellcheck --version

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "All checks passed!"
else
  echo "Some checks FAILED. See above."
  exit 1
fi

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

resolve_shared_skills_root() {
  local skills_root="/opt/agent-sandbox/skills"
  if [[ ! -d "$skills_root" ]] && [[ -d "skills" ]]; then
    # Fallback for local repository runs (outside built container image).
    skills_root="skills"
  fi
  echo "$skills_root"
}

check_shared_skills_bundle() {
  local skills_root
  skills_root="$(resolve_shared_skills_root)"

  if [[ ! -d "$skills_root" ]]; then
    echo "  FAIL shared-skills-dir ($skills_root missing)"
    FAILED=1
    return
  fi

  local skill_dir_count
  local skill_md_count
  skill_dir_count="$(find "$skills_root" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  skill_md_count="$(find "$skills_root" -mindepth 2 -maxdepth 2 -type f -name SKILL.md | wc -l | tr -d ' ')"

  if [[ "$skill_dir_count" -gt 0 ]]; then
    echo "  OK   shared-skills-bundle (${skill_dir_count} skills)"
  else
    echo "  FAIL shared-skills-bundle (no skills discovered)"
    FAILED=1
  fi

  if [[ "$skill_md_count" -eq "$skill_dir_count" ]]; then
    echo "  OK   shared-skills-structure (every skill has SKILL.md)"
  else
    echo "  FAIL shared-skills-structure (dirs=${skill_dir_count}, skill_md=${skill_md_count})"
    FAILED=1
  fi
}

check_shared_skills_metadata() {
  local skills_root
  skills_root="$(resolve_shared_skills_root)"

  local upstream_file="$skills_root/UPSTREAM.txt"
  if [[ ! -f "$upstream_file" ]]; then
    echo "  FAIL shared-skills-upstream-metadata ($upstream_file missing)"
    FAILED=1
    return
  fi

  if grep -Eq '^commit: [0-9a-f]{40}$' "$upstream_file"; then
    echo "  OK   shared-skills-upstream-metadata"
  else
    echo "  FAIL shared-skills-upstream-metadata (missing valid commit hash)"
    FAILED=1
  fi
}

check_shared_skills_install_policy() {
  local start_script="/usr/local/bin/start.sh"

  if [[ ! -f "$start_script" ]]; then
    echo "  FAIL shared-skills-install-policy (start.sh not found)"
    FAILED=1
    return
  fi

  local codex_ok=0
  local gemini_ok=0
  local claude_ok=0
  local managed_sync_ok=0
  local managed_sync_value=""

  if grep -Fq "install_shared_skills \"\$SHARED_SKILLS_ROOT\" \"\$HOME_DIR/.codex/skills\" \"skill-creator\"" "$start_script"; then
    codex_ok=1
  fi
  if grep -Fq "install_shared_skills \"\$SHARED_SKILLS_ROOT\" \"\$HOME_DIR/.gemini/skills\" \"skill-creator\"" "$start_script"; then
    gemini_ok=1
  fi

  local claude_line=""
  claude_line="$(grep -F "install_shared_skills \"\$SHARED_SKILLS_ROOT\" \"\$HOME_DIR/.claude/skills\"" "$start_script" | head -n 1 || true)"
  if [[ -n "$claude_line" ]] && [[ "$claude_line" != *'"skill-creator"'* ]]; then
    claude_ok=1
  fi

  managed_sync_value="$(
    grep -E '^[[:space:]]*FORCE_SYNC_SHARED_SKILLS=' "$start_script" \
      | head -n 1 \
      | sed -E 's/^[[:space:]]*FORCE_SYNC_SHARED_SKILLS="?([^"]*)"?/\1/'
  )"

  if [[ -n "$managed_sync_value" ]]; then
    local managed_sync_name
    IFS=',' read -r -a managed_sync_list <<< "$managed_sync_value"
    for managed_sync_name in "${managed_sync_list[@]}"; do
      managed_sync_name="${managed_sync_name//[[:space:]]/}"
      if [[ "$managed_sync_name" == "playwright-efficient-web-research" ]]; then
        managed_sync_ok=1
        break
      fi
    done
  fi

  if [[ "$codex_ok" -eq 1 ]] && [[ "$gemini_ok" -eq 1 ]] && [[ "$claude_ok" -eq 1 ]] && [[ "$managed_sync_ok" -eq 1 ]]; then
    echo "  OK   shared-skills-install-policy"
  else
    echo "  FAIL shared-skills-install-policy (codex=${codex_ok}, gemini=${gemini_ok}, claude=${claude_ok}, managed_sync=${managed_sync_ok})"
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
echo "--- Agent Productivity Tools ---"
check "beads"     bd --version

echo ""
echo "--- Shared Skills ---"
check_shared_skills_bundle
check_shared_skills_metadata
check_shared_skills_install_policy

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
check "playwright-cli" playwright-cli --version

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

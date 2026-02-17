#!/bin/bash
set -euo pipefail

# Build smoke test: verify key tools are present and runnable.
# Run after docker build to catch missing or broken binaries.
#
# Usage:
#   smoke-test.sh              # full test (runtime)
#   smoke-test.sh --build      # skip docker/socket-dependent checks (build time)
#   SMOKE_TEST_SOURCE=repo smoke-test.sh --build  # validate repo files explicitly

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

resolve_codex_default_check_paths() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local start_script="/usr/local/bin/start.sh"
  local codex_skel_config="/etc/skel/.codex/config.toml"

  case "$source_mode" in
    installed)
      ;;
    repo)
      start_script="scripts/start.sh"
      codex_skel_config="configs/codex/config.toml"
      ;;
    auto)
      # Prefer installed paths so build/runtime tests validate image contents.
      # Fallback to repository paths only when both installed paths are absent.
      # If one installed path is missing, treat it as a failure signal.
      if [[ ! -f "$start_script" ]] && [[ ! -f "$codex_skel_config" ]]; then
        start_script="scripts/start.sh"
        codex_skel_config="configs/codex/config.toml"
      fi
      ;;
    *)
      echo "  FAIL codex-default-config (invalid SMOKE_TEST_SOURCE=${source_mode})"
      FAILED=1
      return 1
      ;;
  esac

  if [[ ! -f "$start_script" ]]; then
    echo "  FAIL codex-default-config ($start_script missing)"
    FAILED=1
    return 1
  fi

  if [[ ! -f "$codex_skel_config" ]]; then
    echo "  FAIL codex-default-config ($codex_skel_config missing)"
    FAILED=1
    return 1
  fi

  CODEX_DEFAULT_START_SCRIPT="$start_script"
  CODEX_DEFAULT_CONFIG="$codex_skel_config"
}

extract_codex_status_line_items() {
  local config_path="$1"
  awk '
    BEGIN {
      in_tui = 0
      in_status_line = 0
    }
    /^[[:space:]]*\[tui\][[:space:]]*(#.*)?$/ {
      in_tui = 1
      in_status_line = 0
      next
    }
    /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/ {
      in_tui = 0
      in_status_line = 0
      next
    }
    in_tui {
      if ($0 ~ /^[[:space:]]*status_line[[:space:]]*=/) {
        in_status_line = 1
      }
      if (in_status_line == 1) {
        line = $0
        while (match(line, /"[^"]+"/)) {
          print substr(line, RSTART + 1, RLENGTH - 2)
          line = substr(line, RSTART + RLENGTH)
        }
        if ($0 ~ /\]/) {
          exit
        }
      }
    }
  ' "$config_path"
}

check_codex_default_config() {
  local start_script
  local codex_skel_config
  local expected_items
  local actual_items
  local status_items_ok=1
  local i

  if ! resolve_codex_default_check_paths; then
    return
  fi

  start_script="$CODEX_DEFAULT_START_SCRIPT"
  codex_skel_config="$CODEX_DEFAULT_CONFIG"

  local has_start_hook=0

  # shellcheck disable=SC2016
  if grep -Eq 'ensure_codex_status_line[[:space:]]+/etc/skel/.codex/config.toml[[:space:]]+"\$HOME_DIR/.codex/config.toml"' "$start_script"; then
    has_start_hook=1
  fi

  mapfile -t actual_items < <(extract_codex_status_line_items "$codex_skel_config")
  expected_items=(
    "model-with-reasoning"
    "current-dir"
    "git-branch"
    "context-used"
    "total-input-tokens"
    "total-output-tokens"
    "five-hour-limit"
    "weekly-limit"
  )

  if [[ "${#actual_items[@]}" -ne "${#expected_items[@]}" ]]; then
    status_items_ok=0
  else
    for i in "${!expected_items[@]}"; do
      if [[ "${actual_items[$i]}" != "${expected_items[$i]}" ]]; then
        status_items_ok=0
        break
      fi
    done
  fi

  if [[ "$has_start_hook" -eq 1 ]] && [[ "$status_items_ok" -eq 1 ]]; then
    echo "  OK   codex-default-config"
  else
    echo "  FAIL codex-default-config (status_items_ok=${status_items_ok}, start_hook=${has_start_hook})"
    FAILED=1
  fi
}

check_tmux_plugin_bootstrap() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local start_script="/usr/local/bin/start.sh"
  local tmux_conf="/etc/skel/.default.tmux.conf"

  case "$source_mode" in
    installed)
      ;;
    repo)
      start_script="scripts/start.sh"
      tmux_conf="configs/tmux.conf"
      ;;
    auto)
      if [[ ! -f "$start_script" ]] && [[ ! -f "$tmux_conf" ]]; then
        start_script="scripts/start.sh"
        tmux_conf="configs/tmux.conf"
      fi
      ;;
    *)
      echo "  FAIL tmux-plugin-bootstrap (invalid SMOKE_TEST_SOURCE=${source_mode})"
      FAILED=1
      return
      ;;
  esac

  if [[ ! -f "$start_script" ]]; then
    echo "  FAIL tmux-plugin-bootstrap ($start_script missing)"
    FAILED=1
    return
  fi

  if [[ ! -f "$tmux_conf" ]]; then
    echo "  FAIL tmux-plugin-bootstrap ($tmux_conf missing)"
    FAILED=1
    return
  fi

  local has_tpm_config=0
  local has_plugin_install=0
  local has_tmux_env_bootstrap=0

  if grep -Fq "set -g @plugin 'tmux-plugins/tpm'" "$tmux_conf" \
    && grep -Fq "set -g @plugin 'tmux-plugins/tmux-resurrect'" "$tmux_conf" \
    && grep -Fq "set -g @plugin 'tmux-plugins/tmux-continuum'" "$tmux_conf"; then
    has_tpm_config=1
  fi

  if grep -Fq "install_plugins" "$start_script"; then
    has_plugin_install=1
  fi

  if grep -Fq "tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH" "$start_script"; then
    has_tmux_env_bootstrap=1
  fi

  if [[ "$has_tpm_config" -eq 1 ]] && [[ "$has_plugin_install" -eq 1 ]] && [[ "$has_tmux_env_bootstrap" -eq 1 ]]; then
    echo "  OK   tmux-plugin-bootstrap"
  else
    echo "  FAIL tmux-plugin-bootstrap (config=${has_tpm_config}, install=${has_plugin_install}, tmux_env=${has_tmux_env_bootstrap})"
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
echo "--- Agent Defaults ---"
check_codex_default_config
check_tmux_plugin_bootstrap

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
check "actionlint"  actionlint --version
check "trivy"       trivy --version
check "yamllint"    yamllint --version

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "All checks passed!"
else
  echo "Some checks FAILED. See above."
  exit 1
fi

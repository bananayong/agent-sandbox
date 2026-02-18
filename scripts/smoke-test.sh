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

extract_shell_function_definition() {
  local script_path="$1"
  local function_name="$2"

  awk -v fn="$function_name" '
    $0 ~ "^" fn "\\(\\)[[:space:]]*\\{" {
      in_fn = 1
    }
    in_fn {
      print
      if ($0 ~ "^}[[:space:]]*$") {
        found = 1
        exit 0
      }
    }
    END {
      if (found != 1) {
        exit 1
      }
    }
  ' "$script_path"
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

resolve_templates_root() {
  local templates_root="/etc/skel/.agent-sandbox/templates"
  if [[ ! -d "$templates_root" ]] && [[ -d "configs/templates" ]]; then
    # Fallback for local repository runs (outside built container image).
    templates_root="configs/templates"
  fi
  echo "$templates_root"
}

check_templates_bundle() {
  local templates_root
  templates_root="$(resolve_templates_root)"

  if [[ ! -d "$templates_root" ]]; then
    echo "  FAIL shared-templates-dir ($templates_root missing)"
    FAILED=1
    return
  fi

  local required_files=(
    "prompt-template.md"
    "command-checklist.md"
    "config-snippet.md"
  )

  local missing=0
  local required_file
  for required_file in "${required_files[@]}"; do
    if [[ ! -f "$templates_root/$required_file" ]]; then
      echo "  FAIL shared-templates-file ($required_file missing)"
      FAILED=1
      missing=1
    fi
  done

  local template_count
  template_count="$(find "$templates_root" -type f | wc -l | tr -d ' ')"

  if [[ "$missing" -eq 0 ]] && [[ "$template_count" -ge 3 ]]; then
    echo "  OK   shared-templates-bundle (${template_count} files)"
  elif [[ "$template_count" -lt 3 ]]; then
    echo "  FAIL shared-templates-bundle (expected at least 3 files, got ${template_count})"
    FAILED=1
  fi
}

check_templates_install_policy() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local start_script="/usr/local/bin/start.sh"

  case "$source_mode" in
    installed)
      ;;
    repo)
      start_script="scripts/start.sh"
      ;;
    auto)
      if [[ ! -f "$start_script" ]] && [[ -f "scripts/start.sh" ]]; then
        start_script="scripts/start.sh"
      fi
      ;;
    *)
      echo "  FAIL shared-templates-install-policy (invalid SMOKE_TEST_SOURCE=${source_mode})"
      FAILED=1
      return
      ;;
  esac

  if [[ ! -f "$start_script" ]]; then
    echo "  FAIL shared-templates-install-policy ($start_script missing)"
    FAILED=1
    return
  fi

  local has_function=0
  local has_install_call=0

  if grep -Fq "install_default_templates()" "$start_script"; then
    has_function=1
  fi

  if grep -Eq 'install_default_templates[[:space:]]+/etc/skel/.agent-sandbox/templates[[:space:]]+"[$]HOME_DIR/.agent-sandbox/templates"' "$start_script"; then
    has_install_call=1
  fi

  if [[ "$has_function" -eq 1 ]] && [[ "$has_install_call" -eq 1 ]]; then
    echo "  OK   shared-templates-install-policy"
  else
    echo "  FAIL shared-templates-install-policy (function=${has_function}, install_call=${has_install_call})"
    FAILED=1
  fi
}

check_agent_settings_install_policy() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local start_script="/usr/local/bin/start.sh"
  local claude_template="/etc/skel/.claude/settings.json"
  local codex_template="/etc/skel/.codex/settings.json"
  local gemini_template="/etc/skel/.gemini/settings.json"

  case "$source_mode" in
    installed)
      ;;
    repo)
      start_script="scripts/start.sh"
      claude_template="configs/claude/settings.json"
      codex_template="configs/codex/settings.json"
      gemini_template="configs/gemini/settings.json"
      ;;
    auto)
      if [[ ! -f "$start_script" ]] && [[ -f "scripts/start.sh" ]]; then
        start_script="scripts/start.sh"
      fi
      if [[ ! -f "$claude_template" ]] && [[ -f "configs/claude/settings.json" ]]; then
        claude_template="configs/claude/settings.json"
      fi
      if [[ ! -f "$codex_template" ]] && [[ -f "configs/codex/settings.json" ]]; then
        codex_template="configs/codex/settings.json"
      fi
      if [[ ! -f "$gemini_template" ]] && [[ -f "configs/gemini/settings.json" ]]; then
        gemini_template="configs/gemini/settings.json"
      fi
      ;;
    *)
      echo "  FAIL agent-settings-install-policy (invalid SMOKE_TEST_SOURCE=${source_mode})"
      FAILED=1
      return
      ;;
  esac

  if [[ ! -f "$start_script" ]]; then
    echo "  FAIL agent-settings-install-policy ($start_script missing)"
    FAILED=1
    return
  fi

  if [[ ! -f "$claude_template" ]] || [[ ! -f "$codex_template" ]] || [[ ! -f "$gemini_template" ]]; then
    echo "  FAIL agent-settings-install-policy (missing settings template files)"
    FAILED=1
    return
  fi

  local claude_managed=0
  local codex_managed=0
  local gemini_managed=0
  local runtime_behavior_ok=0

  # shellcheck disable=SC2016
  if grep -Eq 'update_managed[[:space:]]+/etc/skel/.claude/settings.json[[:space:]]+"[$]HOME_DIR/.claude/settings.json"' "$start_script"; then
    claude_managed=1
  fi
  # shellcheck disable=SC2016
  if grep -Eq 'update_managed[[:space:]]+/etc/skel/.codex/settings.json[[:space:]]+"[$]HOME_DIR/.codex/settings.json"' "$start_script"; then
    codex_managed=1
  fi
  # shellcheck disable=SC2016
  if grep -Eq 'update_managed[[:space:]]+/etc/skel/.gemini/settings.json[[:space:]]+"[$]HOME_DIR/.gemini/settings.json"' "$start_script"; then
    gemini_managed=1
  fi

  # Execute update_managed directly against real templates to verify behavior.
  local update_managed_definition
  if update_managed_definition="$(extract_shell_function_definition "$start_script" "update_managed" 2>/dev/null)"; then
    local tmp_root
    tmp_root="$(mktemp -d)"
    runtime_behavior_ok=1

    if ! eval "$update_managed_definition"; then
      runtime_behavior_ok=0
    fi

    if [[ "$runtime_behavior_ok" -eq 1 ]]; then
      local agent template_file missing_dest existing_dest
      for agent in claude codex gemini; do
        case "$agent" in
          claude) template_file="$claude_template" ;;
          codex) template_file="$codex_template" ;;
          gemini) template_file="$gemini_template" ;;
        esac

        missing_dest="$tmp_root/home/.${agent}/missing-settings.json"
        existing_dest="$tmp_root/home/.${agent}/settings.json"

        if ! update_managed "$template_file" "$missing_dest" >/dev/null 2>&1; then
          runtime_behavior_ok=0
          break
        fi
        if ! cmp -s "$template_file" "$missing_dest"; then
          runtime_behavior_ok=0
          break
        fi

        mkdir -p "$(dirname "$existing_dest")"
        printf '{ "user": true }\n' > "$existing_dest"
        if ! update_managed "$template_file" "$existing_dest" >/dev/null 2>&1; then
          runtime_behavior_ok=0
          break
        fi
        if ! cmp -s "$template_file" "$existing_dest"; then
          runtime_behavior_ok=0
          break
        fi
      done
    fi

    rm -rf "$tmp_root"
    unset -f update_managed || true
  fi

  if [[ "$claude_managed" -eq 1 ]] && [[ "$codex_managed" -eq 1 ]] && [[ "$gemini_managed" -eq 1 ]] && [[ "$runtime_behavior_ok" -eq 1 ]]; then
    echo "  OK   agent-settings-install-policy"
  else
    echo "  FAIL agent-settings-install-policy (claude_managed=${claude_managed}, codex_managed=${codex_managed}, gemini_managed=${gemini_managed}, runtime=${runtime_behavior_ok})"
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

check_tealdeer_update_bootstrap() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local start_script="/usr/local/bin/start.sh"

  case "$source_mode" in
    installed)
      ;;
    repo)
      start_script="scripts/start.sh"
      ;;
    auto)
      if [[ ! -f "$start_script" ]] && [[ -f "scripts/start.sh" ]]; then
        start_script="scripts/start.sh"
      fi
      ;;
    *)
      echo "  FAIL tealdeer-update-bootstrap (invalid SMOKE_TEST_SOURCE=${source_mode})"
      FAILED=1
      return
      ;;
  esac

  if [[ ! -f "$start_script" ]]; then
    echo "  FAIL tealdeer-update-bootstrap ($start_script missing)"
    FAILED=1
    return
  fi

  local has_helper=0
  local has_invocation=0
  local runtime_behavior_ok=0

  if grep -Fq "update_tealdeer_cache()" "$start_script"; then
    has_helper=1
  fi

  # Require async invocation so startup does not block on network/update retries.
  if grep -Eq '^[[:space:]]*update_tealdeer_cache[[:space:]]*&[[:space:]]*$' "$start_script"; then
    has_invocation=1
  fi

  # Execute the helper with a stub tldr binary to verify retry + cache cleanup.
  local tealdeer_definition
  if tealdeer_definition="$(extract_shell_function_definition "$start_script" "update_tealdeer_cache" 2>/dev/null)"; then
    local tmp_root
    tmp_root="$(mktemp -d)"
    local stub_bin="$tmp_root/bin"
    local attempt_file="$tmp_root/attempts"
    local custom_cache="$tmp_root/custom-cache"
    local xdg_cache_home="$tmp_root/xdg-cache"
    local xdg_data_home="$tmp_root/xdg-data"

    mkdir -p "$stub_bin" "$custom_cache" "$xdg_cache_home/tealdeer" "$xdg_data_home/tealdeer"
    printf 'cache\n' > "$custom_cache/cache.txt"
    printf 'cache\n' > "$xdg_cache_home/tealdeer/cache.txt"
    printf 'cache\n' > "$xdg_data_home/tealdeer/cache.txt"

    cat > "$stub_bin/tldr" <<'EOF'
#!/bin/bash
set -euo pipefail
attempt_file="${TLDR_TEST_ATTEMPT_FILE:?}"
attempt=0
if [[ -f "$attempt_file" ]]; then
  attempt="$(cat "$attempt_file")"
fi
attempt=$((attempt + 1))
printf '%s\n' "$attempt" > "$attempt_file"
if [[ "$attempt" -eq 1 ]]; then
  echo "InvalidArchive: simulated failure" >&2
  exit 1
fi
echo "updated"
exit 0
EOF
    chmod +x "$stub_bin/tldr"

    if (
      set -euo pipefail
      export PATH="$stub_bin:$PATH"
      export TLDR_TEST_ATTEMPT_FILE="$attempt_file"
      export TLDR_CACHE_DIR="$custom_cache"
      export XDG_CACHE_HOME="$xdg_cache_home"
      export XDG_DATA_HOME="$xdg_data_home"
      export HOME_DIR="$tmp_root/home"
      eval "$tealdeer_definition"
      update_tealdeer_cache >/dev/null 2>&1
    ); then
      if [[ -f "$attempt_file" ]] && [[ "$(cat "$attempt_file")" == "2" ]] \
        && [[ ! -d "$custom_cache" ]] \
        && [[ ! -d "$xdg_cache_home/tealdeer" ]] \
        && [[ ! -d "$xdg_data_home/tealdeer" ]]; then
        runtime_behavior_ok=1
      fi
    fi

    rm -rf "$tmp_root"
  fi

  if [[ "$has_helper" -eq 1 ]] && [[ "$has_invocation" -eq 1 ]] && [[ "$runtime_behavior_ok" -eq 1 ]]; then
    echo "  OK   tealdeer-update-bootstrap"
  else
    echo "  FAIL tealdeer-update-bootstrap (helper=${has_helper}, invocation=${has_invocation}, runtime=${runtime_behavior_ok})"
    FAILED=1
  fi
}

check_editor_defaults() {
  local source_mode="${SMOKE_TEST_SOURCE:-auto}"
  local start_script="/usr/local/bin/start.sh"
  local vim_config="/etc/skel/.default.vimrc"
  local nvim_config="/etc/skel/.config/nvim/init.lua"

  case "$source_mode" in
    installed)
      ;;
    repo)
      start_script="scripts/start.sh"
      vim_config="configs/vimrc"
      nvim_config="configs/nvim/init.lua"
      ;;
    auto)
      if [[ ! -f "$start_script" ]] && [[ ! -f "$vim_config" ]] && [[ ! -f "$nvim_config" ]]; then
        start_script="scripts/start.sh"
        vim_config="configs/vimrc"
        nvim_config="configs/nvim/init.lua"
      fi
      ;;
    *)
      echo "  FAIL editor-default-config (invalid SMOKE_TEST_SOURCE=${source_mode})"
      FAILED=1
      return
      ;;
  esac

  if [[ ! -f "$start_script" ]]; then
    echo "  FAIL editor-default-config ($start_script missing)"
    FAILED=1
    return
  fi

  if [[ ! -f "$vim_config" ]]; then
    echo "  FAIL editor-default-config ($vim_config missing)"
    FAILED=1
    return
  fi

  if [[ ! -f "$nvim_config" ]]; then
    echo "  FAIL editor-default-config ($nvim_config missing)"
    FAILED=1
    return
  fi

  local has_vim_hook=0
  local has_nvim_hook=0

  # shellcheck disable=SC2016
  if grep -Eq 'copy_default[[:space:]]+/etc/skel/.default.vimrc[[:space:]]+"[$]HOME_DIR/.vimrc"' "$start_script"; then
    has_vim_hook=1
  fi

  # shellcheck disable=SC2016
  if grep -Eq 'copy_default[[:space:]]+/etc/skel/.config/nvim/init.lua[[:space:]]+"[$]HOME_DIR/.config/nvim/init.lua"' "$start_script"; then
    has_nvim_hook=1
  fi

  if [[ "$has_vim_hook" -eq 1 ]] && [[ "$has_nvim_hook" -eq 1 ]]; then
    echo "  OK   editor-default-config"
  else
    echo "  FAIL editor-default-config (vim_hook=${has_vim_hook}, nvim_hook=${has_nvim_hook})"
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
echo "--- Shared Templates ---"
check_templates_bundle
check_templates_install_policy

echo ""
echo "--- Agent Defaults ---"
check_agent_settings_install_policy
check_codex_default_config
check_tmux_plugin_bootstrap
check_tealdeer_update_bootstrap
check_editor_defaults

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
check "vim"       vim --version
check "nvim"      nvim --version

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
check "tldr"      tldr --version
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

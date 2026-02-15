#!/bin/bash
set -euo pipefail

HOME_DIR="/home/sandbox"

# ============================================================
# First-run initialization
# ============================================================
# This script runs as container ENTRYPOINT.
# Goal: prepare user environment safely, then start requested command.
#
# Important behavior:
# - It copies defaults only when files are missing (first run).
# - It does not overwrite existing user config in persisted home volume.

# Copy one default config file only if destination does not exist.
# src: file baked in image (from /etc/skel)
# dest: file inside persisted user home
copy_default() {
  local src="$1"
  local dest="$2"
  if [[ ! -f "$dest" ]]; then
    echo "[init] Copying default: $dest"
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
  fi
}

# Install shared skills from image into one agent's skill directory.
# Behavior is additive: existing skills are never overwritten.
# Optional 3rd arg is a comma-separated exclude list by skill folder name.
install_shared_skills() {
  local source_root="$1"
  local target_root="$2"
  local exclude_csv="${3:-}"

  if [[ ! -d "$source_root" ]]; then
    return
  fi

  mkdir -p "$target_root"

  local source_skill
  for source_skill in "$source_root"/*; do
    if [[ ! -d "$source_skill" ]] || [[ ! -f "$source_skill/SKILL.md" ]]; then
      continue
    fi

    local skill_name
    local target_skill
    skill_name="$(basename "$source_skill")"
    target_skill="$target_root/$skill_name"

    if [[ -n "$exclude_csv" ]]; then
      local exclude_name
      local should_skip=0
      IFS=',' read -r -a exclude_list <<< "$exclude_csv"
      for exclude_name in "${exclude_list[@]}"; do
        if [[ "$skill_name" == "$exclude_name" ]]; then
          should_skip=1
          break
        fi
      done
      if [[ "$should_skip" -eq 1 ]]; then
        continue
      fi
    fi

    # Respect user-managed/customized skills with the same name.
    if [[ -e "$target_skill" ]]; then
      continue
    fi

    echo "[init] Installing shared skill: $target_skill"
    cp -r "$source_skill" "$target_skill"
  done
}

copy_default /etc/skel/.default.zshrc        "$HOME_DIR/.zshrc"
copy_default /etc/skel/.default.zimrc         "$HOME_DIR/.zimrc"
copy_default /etc/skel/.default.tmux.conf     "$HOME_DIR/.tmux.conf"
copy_default /etc/skel/.config/starship.toml  "$HOME_DIR/.config/starship.toml"
copy_default /etc/skel/.default.pre-commit-config.yaml "$HOME_DIR/.pre-commit-config.yaml.template"
copy_default /etc/skel/.config/agent-sandbox/TOOLS.md  "$HOME_DIR/.config/agent-sandbox/TOOLS.md"
copy_default /etc/skel/.config/agent-sandbox/auto-approve.zsh "$HOME_DIR/.config/agent-sandbox/auto-approve.zsh"

# Existing users may already have a persisted ~/.zshrc from older images.
# Add a one-time source hook so new auto-approve wrappers are loaded without
# forcing users to reset their sandbox home or manually edit dotfiles.
AUTO_APPROVE_HOOK='[[ -f ~/.config/agent-sandbox/auto-approve.zsh ]] && source ~/.config/agent-sandbox/auto-approve.zsh'
if [[ -f "$HOME_DIR/.zshrc" ]] && ! grep -Fq "$AUTO_APPROVE_HOOK" "$HOME_DIR/.zshrc"; then
  {
    echo ""
    echo "# Agent auto-approve wrappers (managed by agent-sandbox)."
    echo "$AUTO_APPROVE_HOOK"
  } >> "$HOME_DIR/.zshrc"
fi

# Claude CLI reads this file very early. Ensure it exists to avoid repeated
# ENOENT exceptions during startup when home was freshly initialized/reset.
if [[ ! -f "$HOME_DIR/.claude/remote-settings.json" ]]; then
  mkdir -p "$HOME_DIR/.claude"
  printf '{}\n' > "$HOME_DIR/.claude/remote-settings.json"
fi

# Copy Claude Code slash commands if the commands directory is empty/missing.
if [[ ! -d "$HOME_DIR/.claude/commands" ]] || [[ -z "$(ls -A "$HOME_DIR/.claude/commands" 2>/dev/null)" ]]; then
  echo "[init] Installing Claude Code slash commands..."
  mkdir -p "$HOME_DIR/.claude/commands"
  cp -r /etc/skel/.claude/commands/* "$HOME_DIR/.claude/commands/" 2>/dev/null || true
fi

# Copy Claude Code skills if the skills directory is empty/missing.
if [[ ! -d "$HOME_DIR/.claude/skills" ]] || [[ -z "$(ls -A "$HOME_DIR/.claude/skills" 2>/dev/null)" ]]; then
  echo "[init] Installing Claude Code skills..."
  mkdir -p "$HOME_DIR/.claude/skills"
  cp -r /etc/skel/.claude/skills/* "$HOME_DIR/.claude/skills/" 2>/dev/null || true
fi

# Install vendored shared skills for coding agents.
# Codex/Gemini keep their native "skill-creator" to avoid overriding
# built-in workflow behavior with a third-party variant.
SHARED_SKILLS_ROOT="/opt/agent-sandbox/skills"
install_shared_skills "$SHARED_SKILLS_ROOT" "$HOME_DIR/.claude/skills"
install_shared_skills "$SHARED_SKILLS_ROOT" "$HOME_DIR/.codex/skills" "skill-creator"
install_shared_skills "$SHARED_SKILLS_ROOT" "$HOME_DIR/.gemini/skills" "skill-creator"

# Copy MCP server config template if not already present.
copy_default /etc/skel/.claude/.mcp.json "$HOME_DIR/.claude/.mcp.json"

# Runtime safety defaults for Claude network stability.
# Keep these here (entrypoint) as a final fallback so they still apply even
# when container is launched via a path that bypasses run.sh defaults.
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-1}"
export DISABLE_ERROR_REPORTING="${DISABLE_ERROR_REPORTING:-1}"
export DISABLE_TELEMETRY="${DISABLE_TELEMETRY:-1}"
# Enable agent auto-approve mode by default (can be disabled with 0).
export AGENT_SANDBOX_AUTO_APPROVE="${AGENT_SANDBOX_AUTO_APPROVE:-1}"
export AGENT_SANDBOX_NODE_TLS_COMPAT="${AGENT_SANDBOX_NODE_TLS_COMPAT:-1}"
if [[ "${AGENT_SANDBOX_NODE_TLS_COMPAT}" == "1" ]]; then
  if [[ "${NODE_OPTIONS:-}" != *"--tls-max-v1.2"* ]]; then
    export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--tls-max-v1.2"
  fi
  if [[ "${NODE_OPTIONS:-}" != *"--tls-min-v1.2"* ]]; then
    export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--tls-min-v1.2"
  fi
  if [[ "${NODE_OPTIONS:-}" != *"--dns-result-order=ipv4first"* ]]; then
    export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--dns-result-order=ipv4first"
  fi
fi

# ============================================================
# Zimfw bootstrap
# ============================================================
ZIM_HOME="$HOME_DIR/.zim"

# Download only zimfw core script.
# We intentionally avoid full installer because it can overwrite .zshrc.
if [[ ! -f "$ZIM_HOME/zimfw.zsh" ]]; then
  echo "[init] Downloading zimfw..."
  mkdir -p "$ZIM_HOME"
  curl -fsSL "https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh" \
    -o "$ZIM_HOME/zimfw.zsh"
fi

# Install modules only once.
# init.zsh is generated by zimfw install and indicates bootstrap completion.
if [[ -f "$ZIM_HOME/zimfw.zsh" ]]; then
  if [[ ! -f "$ZIM_HOME/init.zsh" ]]; then
    echo "[init] Installing zim modules..."
    # Keep startup resilient: do not fail entire container start on transient network errors.
    zim_home_path="$ZIM_HOME"
    ZIM_HOME="$zim_home_path" zsh "$zim_home_path/zimfw.zsh" install -q || true
  fi
fi

# ============================================================
# One-time tool setup
# ============================================================
# These are idempotent checks: safe across repeated container starts.

# Configure git-delta as pager when available.
# We avoid re-writing config every run by checking existing value first.
if command -v delta &>/dev/null; then
  if [[ "$(git config --global core.pager 2>/dev/null)" != "delta" ]]; then
    echo "[init] Configuring git-delta..."
    git config --global core.pager delta
    git config --global interactive.diffFilter 'delta --color-only'
    git config --global delta.navigate true
    git config --global delta.side-by-side true
    git config --global delta.line-numbers true
    git config --global merge.conflictstyle diff3
    git config --global diff.colorMoved default
  fi
fi

# Set default git editor to micro when available and unset.
if command -v micro &>/dev/null; then
  if [[ -z "$(git config --global core.editor 2>/dev/null)" ]]; then
    git config --global core.editor micro
  fi
fi

# Install gh-copilot extension in user scope (inside persisted home).
# This happens once because extension directory is checked first.
if command -v gh &>/dev/null; then
  if [[ ! -d "$HOME_DIR/.local/share/gh/extensions/gh-copilot" ]]; then
    echo "[init] Installing GitHub Copilot CLI..."
    gh extension install github/gh-copilot || true
  fi
fi

# TODO: Re-enable tealdeer cache bootstrap after fixing intermittent
# "InvalidArchive" failures during `tldr --update` in this environment.

# Install broot shell launcher script if broot exists.
if command -v broot &>/dev/null; then
  if [[ ! -f "$HOME_DIR/.config/broot/launcher/bash/br" ]]; then
    echo "[init] Initializing broot..."
    broot --install || true
  fi
fi

# Ensure history file exists for zsh sessions.
touch "$HOME_DIR/.zsh_history"

# ============================================================
# Docker socket access check
# ============================================================
# Warn early if Docker socket is mounted but not accessible.
# This catches the common misconfiguration where --group-add is missing.
if [[ -S /var/run/docker.sock ]]; then
  if docker version >/dev/null 2>&1; then
    echo "[init] Docker socket: accessible"
  else
    local_sock_gid="$(stat -c '%g' /var/run/docker.sock 2>/dev/null || echo '?')"
    local_user_groups="$(id -G 2>/dev/null || echo '?')"
    echo "[init] WARNING: Docker socket mounted but not accessible!"
    echo "  Socket GID: $local_sock_gid"
    echo "  Your groups: $local_user_groups"
    echo "  Fix: relaunch with --group-add $local_sock_gid"
    echo "  Or set DOCKER_GID=$local_sock_gid in docker-compose.yml"
  fi
fi

echo "[init] Agent sandbox ready!"
echo ""

# ============================================================
# Execute CMD
# ============================================================
# Hand control to Docker CMD (default: /bin/zsh).
# Using exec keeps correct signal handling and process tree.
exec "$@"

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
# - Most configs are copied only when files are missing (first run).
# - "Managed" configs (e.g. settings.json) are always overwritten to keep
#   runtime defaults in sync with the image. A diff is printed
#   before overwriting so users can see what changed.

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

# Copy shared templates from image defaults into persisted home.
# Behavior is additive and idempotent: existing user files are never overwritten.
install_default_templates() {
  local source_root="$1"
  local target_root="$2"

  if [[ ! -d "$source_root" ]]; then
    return
  fi

  mkdir -p "$target_root"

  local source_file
  local relative_path
  local target_file
  while IFS= read -r -d '' source_file; do
    relative_path="${source_file#"$source_root"/}"
    target_file="$target_root/$relative_path"

    if [[ -e "$target_file" ]]; then
      continue
    fi

    echo "[init] Installing default template: $target_file"
    mkdir -p "$(dirname "$target_file")"
    cp "$source_file" "$target_file"
  done < <(find "$source_root" -type f -print0 | sort -z)
}

# Update a managed config file, overwriting even if it already exists.
# Prints a unified diff before replacing so users can see what changed
# and restore manually if needed. Skips when contents are identical.
update_managed() {
  local src="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [[ ! -f "$dest" ]]; then
    echo "[init] Installing managed config: $dest"
    cp "$src" "$dest"
    return
  fi
  if diff -q "$src" "$dest" >/dev/null 2>&1; then
    return
  fi
  echo "[init] Updating managed config: $dest"
  echo "[init]   Previous content diff (- old / + new):"
  diff -u "$dest" "$src" --label "old: $dest" --label "new: $dest" | sed 's/^/[init]   /' || true
  cp "$src" "$dest"
}

# Ensure Codex config contains the managed default status line items.
# - If config does not exist: install the image default as-is.
# - If config exists and already has status_line: keep user customization.
# - If config exists but lacks status_line: insert only status_line into [tui].
ensure_codex_status_line() {
  local src="$1"
  local dest="$2"
  local tmp_file
  local status_block

  mkdir -p "$(dirname "$dest")"

  if [[ ! -f "$dest" ]]; then
    echo "[init] Installing Codex default config: $dest"
    cp "$src" "$dest"
    return
  fi

  if awk '
    BEGIN {
      in_tui = 0
    }
    /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/ {
      if ($0 ~ /^[[:space:]]*\[tui\][[:space:]]*(#.*)?$/) {
        in_tui = 1
      } else {
        in_tui = 0
      }
      next
    }
    in_tui && $0 ~ /^[[:space:]]*status_line[[:space:]]*=/ {
      found = 1
      exit 0
    }
    END {
      if (found == 1) {
        exit 0
      }
      exit 1
    }
  ' "$dest"; then
    return
  fi

  echo "[init] Updating Codex config with default status line: $dest"

  status_block='status_line = [
  "model-with-reasoning",
  "current-dir",
  "git-branch",
  "context-used",
  "total-input-tokens",
  "total-output-tokens",
  "five-hour-limit",
  "weekly-limit",
]'

  tmp_file="$(mktemp)"

  # Insert status_line inside existing [tui] section when present.
  # If [tui] does not exist, append a new [tui] block at the end.
  awk -v status_block="$status_block" '
    BEGIN {
      in_tui = 0
      tui_seen = 0
      inserted = 0
    }
    {
      if ($0 ~ /^[[:space:]]*\[[^]]+\][[:space:]]*(#.*)?$/) {
        if (in_tui && inserted == 0) {
          print status_block
          inserted = 1
        }
        if ($0 ~ /^[[:space:]]*\[tui\][[:space:]]*(#.*)?$/) {
          in_tui = 1
          tui_seen = 1
        } else {
          in_tui = 0
        }
      }
      print $0
    }
    END {
      if (tui_seen == 1 && inserted == 0) {
        print status_block
      }
      if (tui_seen == 0) {
        print ""
        print "[tui]"
        print status_block
      }
    }
  ' "$dest" > "$tmp_file"

  mv "$tmp_file" "$dest"
}

# Install shared skills from image into one agent's skill directory.
# By default behavior is additive: existing skills are never overwritten.
# Optional 3rd arg is a comma-separated exclude list by skill folder name.
# Optional 4th arg is a comma-separated force-sync list: matching skills are
# overwritten from image defaults every startup to keep managed guidance fresh.
install_shared_skills() {
  local source_root="$1"
  local target_root="$2"
  local exclude_csv="${3:-}"
  local force_sync_csv="${4:-}"

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
    local should_force_sync=0
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

    if [[ -n "$force_sync_csv" ]]; then
      local force_sync_name
      IFS=',' read -r -a force_sync_list <<< "$force_sync_csv"
      for force_sync_name in "${force_sync_list[@]}"; do
        if [[ "$skill_name" == "$force_sync_name" ]]; then
          should_force_sync=1
          break
        fi
      done
    fi

    # Respect user-managed/customized skills with the same name unless this
    # skill is explicitly managed via force-sync list.
    if [[ -e "$target_skill" ]] && [[ "$should_force_sync" -ne 1 ]]; then
      continue
    fi

    if [[ "$should_force_sync" -eq 1 ]] && [[ -e "$target_skill" ]]; then
      echo "[init] Updating managed shared skill: $target_skill"
      rm -rf "$target_skill"
    else
      echo "[init] Installing shared skill: $target_skill"
    fi

    cp -r "$source_skill" "$target_skill"
  done
}

copy_default /etc/skel/.default.zshrc        "$HOME_DIR/.zshrc"
copy_default /etc/skel/.default.zimrc         "$HOME_DIR/.zimrc"
copy_default /etc/skel/.default.tmux.conf     "$HOME_DIR/.tmux.conf"
update_managed /etc/skel/.config/starship.toml "$HOME_DIR/.config/starship.toml"
copy_default /etc/skel/.default.pre-commit-config.yaml "$HOME_DIR/.pre-commit-config.yaml.template"
copy_default /etc/skel/.config/agent-sandbox/TOOLS.md  "$HOME_DIR/.config/agent-sandbox/TOOLS.md"
update_managed /etc/skel/.config/agent-sandbox/auto-approve.zsh "$HOME_DIR/.config/agent-sandbox/auto-approve.zsh"
install_default_templates /etc/skel/.agent-sandbox/templates "$HOME_DIR/.agent-sandbox/templates"

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

# Copy Claude Code agents if the agents directory is empty/missing.
if [[ ! -d "$HOME_DIR/.claude/agents" ]] || [[ -z "$(ls -A "$HOME_DIR/.claude/agents" 2>/dev/null)" ]]; then
  echo "[init] Installing Claude Code agents..."
  mkdir -p "$HOME_DIR/.claude/agents"
  cp -r /etc/skel/.claude/agents/* "$HOME_DIR/.claude/agents/" 2>/dev/null || true
fi

# Install vendored shared skills for coding agents.
# Codex/Gemini keep their native "skill-creator" to avoid overriding
# built-in workflow behavior with a third-party variant.
SHARED_SKILLS_ROOT="/opt/agent-sandbox/skills"
# Keep this list narrow: only skills that should be centrally managed and
# always updated even for existing persisted homes.
FORCE_SYNC_SHARED_SKILLS="playwright-efficient-web-research"
install_shared_skills "$SHARED_SKILLS_ROOT" "$HOME_DIR/.claude/skills" "" "$FORCE_SYNC_SHARED_SKILLS"
install_shared_skills "$SHARED_SKILLS_ROOT" "$HOME_DIR/.codex/skills" "skill-creator" "$FORCE_SYNC_SHARED_SKILLS"
install_shared_skills "$SHARED_SKILLS_ROOT" "$HOME_DIR/.gemini/skills" "skill-creator" "$FORCE_SYNC_SHARED_SKILLS"

# Claude Code settings are managed: always kept in sync with image defaults.
# This ensures managed runtime defaults reach existing users on image update.
# WARNING: this overwrites user edits to settings.json (e.g. model choice).
# The diff printed above lets users recover previous values if needed.
update_managed /etc/skel/.claude/settings.json "$HOME_DIR/.claude/settings.json"

# Copy MCP server config template if not already present.
copy_default /etc/skel/.claude/.mcp.json "$HOME_DIR/.claude/.mcp.json"

# Copy LSP settings for coding agents (Claude Code, Codex, Gemini CLI).
copy_default /etc/skel/.claude/settings.json  "$HOME_DIR/.claude/settings.json"
copy_default /etc/skel/.codex/settings.json   "$HOME_DIR/.codex/settings.json"
copy_default /etc/skel/.gemini/settings.json   "$HOME_DIR/.gemini/settings.json"

# Codex CLI uses config.toml for TUI/runtime preferences.
# Keep existing user config, but ensure the default status line exists.
ensure_codex_status_line /etc/skel/.codex/config.toml "$HOME_DIR/.codex/config.toml"

# Runtime safety defaults for Claude network stability.
# Keep these here (entrypoint) as a final fallback so they still apply even
# when container is launched via a path that bypasses run.sh defaults.
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
export DISABLE_ERROR_REPORTING="1"
export DISABLE_TELEMETRY="1"
export DISABLE_AUTOUPDATER="1"
if [[ "${NODE_OPTIONS:-}" != *"--tls-max-v1.2"* ]]; then
  export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--tls-max-v1.2"
fi
if [[ "${NODE_OPTIONS:-}" != *"--tls-min-v1.2"* ]]; then
  export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--tls-min-v1.2"
fi
if [[ "${NODE_OPTIONS:-}" != *"--dns-result-order=ipv4first"* ]]; then
  export NODE_OPTIONS="${NODE_OPTIONS:+$NODE_OPTIONS }--dns-result-order=ipv4first"
fi

# Quick DNS sanity check for Claude API hostname.
# This catches common cases where container DNS points to unreachable stubs.
print_dns_diagnostics() {
  if getent hosts api.anthropic.com >/dev/null 2>&1; then
    return
  fi

  local nameservers
  nameservers="$(awk '/^nameserver[[:space:]]+/ {printf "%s ", $2}' /etc/resolv.conf 2>/dev/null)"
  nameservers="${nameservers% }"

  echo "[init] WARNING: DNS lookup failed for api.anthropic.com"
  if [[ -n "$nameservers" ]]; then
    echo "  /etc/resolv.conf nameservers: $nameservers"
  else
    echo "  /etc/resolv.conf has no nameserver entries."
  fi
  echo "  Tip: restart with AGENT_SANDBOX_DNS_SERVERS='<ipv4_dns1>,<ipv4_dns2>' ./run.sh ."
}

print_dns_diagnostics

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
    timeout --kill-after=10 30 gh extension install github/gh-copilot </dev/null || true
  fi
fi

# TODO: Re-enable tealdeer cache bootstrap after fixing intermittent
# "InvalidArchive" failures during `tldr --update` in this environment.

# Install TPM (Tmux Plugin Manager) and ensure default tmux plugins are present.
# Retry on later startups when plugin install fails transiently.
TPM_PLUGIN_ROOT="$HOME_DIR/.tmux/plugins"
TPM_DIR="$TPM_PLUGIN_ROOT/tpm"
REQUIRED_TMUX_PLUGINS=(tmux-resurrect tmux-continuum)

if [[ ! -d "$TPM_DIR" ]]; then
  echo "[init] Installing TPM (Tmux Plugin Manager)..."
  if ! timeout --kill-after=10 30 git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR" </dev/null; then
    echo "[init]   WARNING: TPM clone failed or timed out (non-blocking)" >&2
    rm -rf "$TPM_DIR"
  fi
fi

if [[ -d "$TPM_DIR" ]] && command -v tmux &>/dev/null; then
  missing_tmux_plugins=()
  for plugin_name in "${REQUIRED_TMUX_PLUGINS[@]}"; do
    if [[ ! -d "$TPM_PLUGIN_ROOT/$plugin_name" ]]; then
      missing_tmux_plugins+=("$plugin_name")
    fi
  done

  if [[ "${#missing_tmux_plugins[@]}" -gt 0 ]]; then
    echo "[init] Installing tmux plugins: ${missing_tmux_plugins[*]}..."

    # TPM's install script reads TMUX_PLUGIN_MANAGER_PATH from tmux server env.
    # Set it explicitly so install works in non-interactive startup contexts.
    tmux -f "$HOME_DIR/.tmux.conf" start-server >/dev/null 2>&1 || true
    tmux set-environment -g TMUX_PLUGIN_MANAGER_PATH "$TPM_PLUGIN_ROOT" >/dev/null 2>&1 || true

    if ! timeout --kill-after=10 60 "$TPM_DIR/bin/install_plugins" </dev/null; then
      echo "[init]   WARNING: tmux plugin install failed or timed out (non-blocking)" >&2
    fi
  fi
fi

# Install broot shell launcher script if broot exists.
if command -v broot &>/dev/null; then
  if [[ ! -f "$HOME_DIR/.config/broot/launcher/bash/br" ]]; then
    echo "[init] Initializing broot..."
    broot --install || true
  fi
fi

# Superpowers skills (obra/superpowers) for Claude Code and Codex.
# Installs on first run; sentinel files prevent repeated installs.
#
# IMPORTANT: all commands use </dev/null to prevent interactive prompts from
# blocking the entrypoint (no TTY during container startup). --kill-after
# sends SIGKILL after grace period because Node.js (claude CLI) may ignore
# SIGTERM and hang indefinitely.
SUPERPOWERS_REPO="https://github.com/obra/superpowers.git"

# Check if Superpowers marketplace exists in Claude plugin storage.
claude_has_superpowers_marketplace() {
  local marketplace_dir="$HOME_DIR/.claude/plugins/marketplaces/superpowers-marketplace"
  [[ -d "$marketplace_dir" ]] && [[ -n "$(ls -A "$marketplace_dir" 2>/dev/null)" ]]
}

# Check if Claude already has Superpowers installed.
# We validate both metadata and on-disk plugin cache to avoid false positives
# from stale installed_plugins.json entries.
claude_has_superpowers_plugin() {
  local plugins_json="$HOME_DIR/.claude/plugins/installed_plugins.json"
  local plugin_cache_dir="$HOME_DIR/.claude/plugins/cache/superpowers-marketplace/superpowers"

  [[ -f "$plugins_json" ]] \
    && grep -Fq '"superpowers@superpowers-marketplace"' "$plugins_json" \
    && [[ -d "$plugin_cache_dir" ]] \
    && [[ -n "$(ls -A "$plugin_cache_dir" 2>/dev/null)" ]]
}

# Claude Code: install via plugin marketplace.
# The CLAUDECODE env var must be unset so `claude plugin` works outside a session.
CLAUDE_SP_SENTINEL="$HOME_DIR/.claude/plugins/.superpowers-installed"
if command -v claude &>/dev/null && [[ ! -f "$CLAUDE_SP_SENTINEL" ]]; then
  if claude_has_superpowers_plugin; then
    echo "[init] Superpowers plugin already present for Claude Code."
    mkdir -p "$(dirname "$CLAUDE_SP_SENTINEL")"
    touch "$CLAUDE_SP_SENTINEL"
  else
    echo "[init] Installing Superpowers plugin for Claude Code..."
    claude_marketplace_ready=0
    claude_marketplace_log="$(mktemp)"
    claude_marketplace_exit=0
    if ! timeout --kill-after=10 30 env -u CLAUDECODE claude plugin marketplace add obra/superpowers-marketplace </dev/null >"$claude_marketplace_log" 2>&1; then
      claude_marketplace_exit=$?
    fi

    # Determine readiness from filesystem state instead of CLI error strings.
    if claude_has_superpowers_marketplace; then
      claude_marketplace_ready=1
    fi

    if [[ "$claude_marketplace_ready" -ne 1 ]]; then
      echo "[init]   WARNING: Superpowers marketplace add failed or timed out (non-blocking)" >&2
      echo "[init]   Exit code: $claude_marketplace_exit" >&2
      sed 's/^/[init]   /' "$claude_marketplace_log" >&2 || true
    fi
    rm -f "$claude_marketplace_log"

    if [[ "$claude_marketplace_ready" -eq 1 ]]; then
      claude_install_log="$(mktemp)"
      claude_install_exit=0
      if ! timeout --kill-after=10 30 env -u CLAUDECODE claude plugin install superpowers@superpowers-marketplace </dev/null >"$claude_install_log" 2>&1; then
        claude_install_exit=$?
      fi

      # Validate post-state from metadata so we can mark completion idempotently.
      if claude_has_superpowers_plugin; then
        mkdir -p "$(dirname "$CLAUDE_SP_SENTINEL")"
        touch "$CLAUDE_SP_SENTINEL"
      else
        echo "[init]   WARNING: Superpowers plugin install failed or timed out (non-blocking)" >&2
        echo "[init]   Exit code: $claude_install_exit" >&2
        sed 's/^/[init]   /' "$claude_install_log" >&2 || true
      fi
      rm -f "$claude_install_log"
    fi
  fi
fi

# Codex: clone repo and symlink skills into Codex skill discovery path.
CODEX_SP_SENTINEL="$HOME_DIR/.codex/.superpowers-installed"
if command -v codex &>/dev/null && [[ ! -f "$CODEX_SP_SENTINEL" ]]; then
  echo "[init] Installing Superpowers skills for Codex..."
  if [[ ! -d "$HOME_DIR/.codex/superpowers" ]]; then
    # Timeout + kill-after prevents a hanging clone from blocking container startup.
    if ! timeout --kill-after=10 30 git clone --depth 1 "$SUPERPOWERS_REPO" "$HOME_DIR/.codex/superpowers" </dev/null; then
      echo "[init]   WARNING: Superpowers clone failed or timed out for Codex (non-blocking)" >&2
      # Remove partial clone so the next startup retries cleanly.
      rm -rf "$HOME_DIR/.codex/superpowers"
    fi
  fi
  if [[ -d "$HOME_DIR/.codex/superpowers/skills" ]]; then
    mkdir -p "$HOME_DIR/.agents/skills"
    ln -sfn "$HOME_DIR/.codex/superpowers/skills" "$HOME_DIR/.agents/skills/superpowers"
    mkdir -p "$(dirname "$CODEX_SP_SENTINEL")"
    touch "$CODEX_SP_SENTINEL"
  fi
fi

# bkit (Vibecoding Kit) plugin for Claude Code.
# Installs via marketplace on first run; sentinel prevents repeated installs.
#
# Same pattern as Superpowers above: </dev/null prevents interactive prompts,
# timeout --kill-after sends SIGKILL after grace period, env -u CLAUDECODE
# allows `claude plugin` to work outside a session.
BKIT_SENTINEL="$HOME_DIR/.claude/plugins/.bkit-installed"

# Check if bkit marketplace exists in Claude plugin storage.
claude_has_bkit_marketplace() {
  local marketplace_dir="$HOME_DIR/.claude/plugins/marketplaces/bkit-marketplace"
  [[ -d "$marketplace_dir" ]] && [[ -n "$(ls -A "$marketplace_dir" 2>/dev/null)" ]]
}

# Check if Claude already has bkit installed.
claude_has_bkit_plugin() {
  local plugins_json="$HOME_DIR/.claude/plugins/installed_plugins.json"
  local plugin_cache_dir="$HOME_DIR/.claude/plugins/cache/bkit-marketplace/bkit"

  [[ -f "$plugins_json" ]] \
    && grep -Fq '"bkit@bkit-marketplace"' "$plugins_json" \
    && [[ -d "$plugin_cache_dir" ]] \
    && [[ -n "$(ls -A "$plugin_cache_dir" 2>/dev/null)" ]]
}

if command -v claude &>/dev/null && [[ ! -f "$BKIT_SENTINEL" ]]; then
  if claude_has_bkit_plugin; then
    echo "[init] bkit plugin already present for Claude Code."
    mkdir -p "$(dirname "$BKIT_SENTINEL")"
    touch "$BKIT_SENTINEL"
  else
    echo "[init] Installing bkit plugin for Claude Code..."
    bkit_marketplace_ready=0
    bkit_marketplace_log="$(mktemp)"
    bkit_marketplace_exit=0
    # Source repo is bkit-claude-code; Claude resolves this to marketplace id bkit-marketplace.
    if ! timeout --kill-after=10 30 env -u CLAUDECODE claude plugin marketplace add popup-studio-ai/bkit-claude-code </dev/null >"$bkit_marketplace_log" 2>&1; then
      bkit_marketplace_exit=$?
    fi

    if claude_has_bkit_marketplace; then
      bkit_marketplace_ready=1
    fi

    if [[ "$bkit_marketplace_ready" -ne 1 ]]; then
      echo "[init]   WARNING: bkit marketplace add failed or timed out (non-blocking)" >&2
      echo "[init]   Exit code: $bkit_marketplace_exit" >&2
      sed 's/^/[init]   /' "$bkit_marketplace_log" >&2 || true
    fi
    rm -f "$bkit_marketplace_log"

    if [[ "$bkit_marketplace_ready" -eq 1 ]]; then
      bkit_install_log="$(mktemp)"
      bkit_install_exit=0
      if ! timeout --kill-after=10 30 env -u CLAUDECODE claude plugin install bkit@bkit-marketplace </dev/null >"$bkit_install_log" 2>&1; then
        bkit_install_exit=$?
      fi

      if claude_has_bkit_plugin; then
        mkdir -p "$(dirname "$BKIT_SENTINEL")"
        touch "$BKIT_SENTINEL"
      else
        echo "[init]   WARNING: bkit plugin install failed or timed out (non-blocking)" >&2
        echo "[init]   Exit code: $bkit_install_exit" >&2
        sed 's/^/[init]   /' "$bkit_install_log" >&2 || true
      fi
      rm -f "$bkit_install_log"
    fi
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

# Start a tmux session for Claude Code agent teams support.
# Claude Code teammate mode spawns each teammate as a split pane inside
# the tmux session, so the shell must already be running inside tmux.
# CMD arguments are forwarded as the tmux session shell command so custom
# commands like `docker run agent-sandbox claude` are not silently dropped.
if [[ -z "${TMUX:-}" ]] && command -v tmux &>/dev/null; then
  exec tmux new-session -s main "$@"
else
  exec "$@"
fi

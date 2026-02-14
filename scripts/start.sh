#!/bin/bash
set -euo pipefail

HOME_DIR="/home/sandbox"

# ============================================================
# First-run initialization
# ============================================================

# Copy default config files if they don't exist yet
copy_default() {
  local src="$1"
  local dest="$2"
  if [[ ! -f "$dest" ]]; then
    echo "[init] Copying default: $dest"
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest"
  fi
}

copy_default /etc/skel/.default.zshrc        "$HOME_DIR/.zshrc"
copy_default /etc/skel/.default.zimrc         "$HOME_DIR/.zimrc"
copy_default /etc/skel/.default.tmux.conf     "$HOME_DIR/.tmux.conf"
copy_default /etc/skel/.config/starship.toml  "$HOME_DIR/.config/starship.toml"

# ============================================================
# Zimfw bootstrap
# ============================================================
ZIM_HOME="$HOME_DIR/.zim"

# Download zimfw.zsh directly (NOT the full installer which overwrites .zshrc)
if [[ ! -f "$ZIM_HOME/zimfw.zsh" ]]; then
  echo "[init] Downloading zimfw..."
  mkdir -p "$ZIM_HOME"
  curl -fsSL "https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh" \
    -o "$ZIM_HOME/zimfw.zsh"
fi

# Install zim modules if needed
if [[ -f "$ZIM_HOME/zimfw.zsh" ]]; then
  if [[ ! -f "$ZIM_HOME/init.zsh" ]]; then
    echo "[init] Installing zim modules..."
    ZIM_HOME="$ZIM_HOME" zsh "$ZIM_HOME/zimfw.zsh" install -q || true
  fi
fi

# ============================================================
# One-time tool setup
# ============================================================

# Docker socket access is handled by --group-add in run.sh (no sudo needed)

# Git delta integration (only if delta is available and not yet configured)
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

# Set micro as default editor (only if not already set)
if command -v micro &>/dev/null; then
  if [[ -z "$(git config --global core.editor 2>/dev/null)" ]]; then
    git config --global core.editor micro
  fi
fi

# GitHub Copilot extension (installed per-user, so must be in $HOME)
if command -v gh &>/dev/null; then
  if [[ ! -d "$HOME_DIR/.local/share/gh/extensions/gh-copilot" ]]; then
    echo "[init] Installing GitHub Copilot CLI..."
    gh extension install github/gh-copilot || true
  fi
fi

# TODO: Re-enable tealdeer cache bootstrap after fixing intermittent
# "InvalidArchive" failures during `tldr --update` in this environment.

# broot shell function
if command -v broot &>/dev/null; then
  if [[ ! -f "$HOME_DIR/.config/broot/launcher/bash/br" ]]; then
    echo "[init] Initializing broot..."
    broot --install || true
  fi
fi

# Ensure .zsh_history exists
touch "$HOME_DIR/.zsh_history"

echo "[init] Agent sandbox ready!"
echo ""

# ============================================================
# Execute CMD
# ============================================================
exec "$@"

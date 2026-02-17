# shellcheck shell=bash
# Agent sandbox editor defaults (managed).
# Keep this sourced late in ~/.zshrc so it can override stale older defaults.

if command -v nvim &>/dev/null; then
  export EDITOR='nvim'
  export VISUAL='nvim'
  export GIT_EDITOR='nvim'
elif command -v micro &>/dev/null; then
  export EDITOR='micro'
  export VISUAL='micro'
  export GIT_EDITOR='micro'
fi

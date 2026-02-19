# shellcheck shell=bash
# Agent sandbox Java defaults (managed).
# Keep this sourced late in ~/.zshrc so jenv shims/JAVA_HOME are always active.

export JENV_ROOT="$HOME/.jenv"

if command -v jenv &>/dev/null; then
  # Prefer zsh-mode init; fall back to generic init for older jenv builds.
  eval "$(jenv init - zsh 2>/dev/null || jenv init -)" 2>/dev/null || true

  # Ensure JAVA_HOME is set when a managed jenv version is active.
  if [[ -z "${JAVA_HOME:-}" ]]; then
    _agent_sandbox_jenv_prefix="$(jenv prefix 2>/dev/null || true)"
    if [[ -n "$_agent_sandbox_jenv_prefix" ]] && [[ -d "$_agent_sandbox_jenv_prefix" ]]; then
      export JAVA_HOME="$_agent_sandbox_jenv_prefix"
    fi
    unset _agent_sandbox_jenv_prefix
  fi
fi

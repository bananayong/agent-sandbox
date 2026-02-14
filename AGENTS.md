# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## What This Is

A Docker sandbox for coding agents (Claude Code, Codex CLI, Gemini CLI, OpenCode, GitHub Copilot). It provides an isolated container with a modern zsh/starship terminal and CLI tools. The host mounts a project directory as `/workspace` and persists the entire sandbox `$HOME` at `~/.agent-sandbox/home/`.

## Build & Run

```bash
# Build the image
docker build -t agent-sandbox:latest .

# Run with current directory as workspace
./run.sh .

# Build + run
./run.sh -b .

# Run with specific project
./run.sh ~/projects/myapp

# Stop container
./run.sh -s

# Reset persisted home (wipes all auth/config)
./run.sh -r
```

## Architecture

**Dockerfile (`runtime` stage):**
- Base: `debian:bookworm-slim`
- Installs core packages via apt, Node.js 22, Bun, GitHub CLI
- Installs additional CLI tools from pinned GitHub release binaries
- Installs coding agents via npm

**Mount strategy (two volumes):**
- `$TARGET_DIR` -> `/workspace` (the user's project)
- `~/.agent-sandbox/home` -> `/home/sandbox` (persists all agent auth, shell history, caches, and configs across container restarts)

**Entrypoint flow (`scripts/start.sh`):**
1. Copies default configs from `/etc/skel/` to `$HOME` only if they don't already exist (first-run)
2. Bootstraps zimfw and installs zsh modules if missing
3. Applies first-run shell/git bootstrap steps
4. `exec "$@"` -> runs CMD (`/bin/zsh`)

**Config files in `configs/`** are baked into the image at `/etc/skel/` and copied to the user's persisted home on first run. After that, the user's copies take precedence.

## Project Memory

- Long-lived decisions and change history are tracked in `MEMORY.md`.
- Add major decisions to `MEMORY.md` with date, context, decision, and impact.
- Keep this file focused on stable operational guidance; do not duplicate full history here.

## Key Conventions

- Container runs as non-root user `sandbox` (UID/GID 1000) with passwordless sudo
- API keys are passed via environment variables, never baked into the image
- `run.sh` auto-builds the image if it doesn't exist, and attaches to a running container instead of creating a new one
- Shell aliases in `configs/zshrc` replace standard commands (cat->bat, ls->eza, find->fd, etc.) but only when the binary is available
- The `configs/zimrc` has ordering constraints: `zsh-completions` must come before `completion`, `zsh-syntax-highlighting` must come after `completion`, `zsh-history-substring-search` must come after `syntax-highlighting`

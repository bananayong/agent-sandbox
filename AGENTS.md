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
- Installs core packages via apt, Node.js 22, Bun, GitHub CLI, Docker CLI (docker-ce-cli, docker-compose-plugin, docker-buildx-plugin)
- Installs additional CLI tools from pinned GitHub release binaries
- Installs coding agents via bun (Claude Code, Codex, Gemini, OpenCode)

**Mount strategy (three volumes):**
- `$TARGET_DIR` -> `/workspace` (the user's project)
- `~/.agent-sandbox/home` -> `/home/sandbox` (persists all agent auth, shell history, caches, and configs across container restarts)
- Host Docker socket -> `/var/run/docker.sock` (DooD — enables `docker`, `docker compose`, `docker buildx` inside the container)

**Docker-out-of-Docker (DooD):**
- Container mounts host Docker socket instead of running its own daemon — lightweight, shares host image cache
- `run.sh` auto-detects socket from: `DOCKER_HOST` env var (unix://), `/var/run/docker.sock`, `/run/user/<uid>/docker.sock` (rootless), `~/.docker/run/docker.sock`
- Socket access is granted via `--group-add <GID>` (kernel-level group assignment), not `sudo chmod`
- **IMPORTANT:** `run.sh` sets `--security-opt no-new-privileges:true`, which blocks all setuid binaries including `sudo`. Never use `sudo` in `start.sh`. Handle all permission needs in `run.sh` via Docker flags (`--group-add`, `--user`, `--cap-add`)

**Entrypoint flow (`scripts/start.sh`):**
1. Copies default configs from `/etc/skel/` to `$HOME` only if they don't already exist (first-run)
2. Bootstraps zimfw and installs zsh modules if missing
3. Applies first-run shell/git bootstrap steps
4. `exec "$@"` -> runs CMD (`/bin/zsh`)

**Config files in `configs/`** are baked into the image at `/etc/skel/` and copied to the user's persisted home on first run. After that, the user's copies take precedence.

## Task Management

- All pending and completed tasks are tracked in `TODO.md`.
- Before starting work, check `TODO.md` for pending tasks related to the current request.
- When a new task is identified but not immediately actionable, add it to the **Pending** section of `TODO.md`.
- When a task is completed, mark it with `[x]` and move it to the **Done** section.
- Do not duplicate task details across `TODO.md` and `MEMORY.md` — use `TODO.md` for actionable items and `MEMORY.md` for decision history.

## Project Memory

- Long-lived decisions and change history are tracked in `MEMORY.md`.
- Add major decisions to `MEMORY.md` with date, context, decision, and impact.
- Keep this file focused on stable operational guidance; do not duplicate full history here.

## Key Conventions

- Container runs as non-root user `sandbox` (UID/GID 1000). `sudo` is configured (NOPASSWD) but blocked at runtime by `no-new-privileges` — do not rely on `sudo` in entrypoint or runtime scripts
- API keys are passed via environment variables, never baked into the image
- All commits must be signed. Always create commits with a verified signature (for example, `git commit -S`)
- `run.sh` auto-builds the image if it doesn't exist, and attaches to a running container instead of creating a new one
- Shell aliases in `configs/zshrc` replace standard commands (cat->bat, ls->eza, find->fd, etc.) but only when the binary is available
- The `configs/zimrc` has ordering constraints: `zsh-completions` must come before `completion`, `zsh-syntax-highlighting` must come after `completion`, `zsh-history-substring-search` must come after `syntax-highlighting`
- For shell scripts and Docker-related files (`Dockerfile`, `docker-compose.yml`, `run.sh`, `scripts/*.sh`), prioritize beginner-friendly comments that explain purpose, execution flow, and safety/permission implications.
- Git signing metadata must be configured in `$HOME` global Git config (`~/.gitconfig`, `~/.config/git/allowed_signers`) and never created in repository paths.

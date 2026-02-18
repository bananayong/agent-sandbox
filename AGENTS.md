# AGENTS.md

This file provides guidance to coding agents when working with code in this repository.

## What This Is

A Docker sandbox for coding agents (Claude Code, Codex CLI, Gemini CLI, OpenCode, GitHub Copilot). Provides an isolated container with a modern zsh/starship terminal and CLI tools. The host mounts a project directory as `/workspace` and persists `$HOME` under `~/.agent-sandbox/.../home/` (container-specific when using `--name`).

## Build & Run

```bash
docker build -t agent-sandbox:latest .
./run.sh .          # Run with current directory as workspace
./run.sh -b .       # Build + run
./run.sh ~/myapp    # Run with specific project
./run.sh -n codex . # Run with custom container name (isolated home path)
./run.sh --home ~/.agent-sandbox/team/home .  # Explicit home path
./run.sh -s         # Stop container
./run.sh -r         # Reset persisted home (wipes all auth/config)
```

## Architecture

**Dockerfile (`runtime` stage):**
- Base: `debian:bookworm-slim`
- Installs: Node.js 22, Bun, GitHub CLI, Docker CLI, LSP servers, 20+ pinned CLI tools from GitHub releases
- Installs coding agents via bun (Claude Code, Codex, Gemini, OpenCode)

**Mount strategy (three volumes):**
- `$TARGET_DIR` -> `/workspace` (user's project)
- sandbox home (`~/.agent-sandbox/home` for default container, `~/.agent-sandbox/<name>/home` for `--name <name>`) -> `/home/sandbox`
- Host Docker socket -> `/var/run/docker.sock` (Docker-out-of-Docker)

**Docker-out-of-Docker (DooD):**
- Mounts host Docker socket — lightweight, shares host image cache
- Socket access via `--group-add <GID>`, not `sudo chmod`
- `sandbox` user in root group (GID 0) for Docker Desktop compatibility
- **IMPORTANT:** `--security-opt no-new-privileges:true` blocks `sudo` at runtime. Handle permissions via Docker flags (`--group-add`, `--user`, `--cap-add`)

**Entrypoint flow (`scripts/start.sh`):**
1. Copies default configs from `/etc/skel/` if missing (first-run). Managed configs (e.g. `settings.json`) are always synced with diff output before overwriting.
2. Installs skills, slash commands, and agents into agent config directories
3. Applies runtime safety defaults (telemetry, TLS compat, auto-approve)
4. Bootstraps zimfw and installs zsh modules
5. One-time tool setup (git-delta pager, gh-copilot extension, Superpowers skills)
6. Checks Docker socket accessibility
7. Starts tmux session (`main`) for agent teams support (falls back to `exec "$@"` if already inside tmux)

**Config files:** `configs/` -> baked into image at `/etc/skel/` -> copied to `$HOME` on first run. User copies take precedence except managed configs which are always overwritten to keep runtime defaults current.

## Task Management

- Tracked in `TODO.md` (Pending / Done sections).
- Check `TODO.md` before starting work.
- New tasks go to **Pending**; completed tasks get `[x]` and move to **Done**.
- Do not duplicate between `TODO.md` and `MEMORY.md` — use `TODO.md` for actionable items, `MEMORY.md` for decision history.

## Project Memory

- Decision history in `MEMORY.md` with date, context, decision, and impact.
- Stable guidance only — no task tracking here.

## Key Conventions

- Non-root user `sandbox` (UID/GID 1000). `sudo` blocked at runtime — never use in `start.sh`
- API keys via environment variables, never baked into the image
- Human-maintainer commits should be signed (`git commit -S`); GitHub Actions bot commits may remain unsigned by workflow policy
- `run.sh` auto-builds the image if missing, attaches to running container instead of creating new
- Shell aliases replace standard commands when binaries available (cat->bat, ls->eza, find->fd)
- `configs/zimrc` ordering: `zsh-completions` -> `completion` -> `fzf-tab` -> `zsh-you-should-use` -> `fast-syntax-highlighting` -> `zsh-history-substring-search`
- Shell scripts and Docker files: prioritize beginner-friendly comments
- Git signing metadata: `$HOME` global config only (`~/.gitconfig`, `~/.config/git/allowed_signers`), never in repo paths
- No new `AGENT_SANDBOX_*` env flags. New `start.sh` features install unconditionally with idempotency guards

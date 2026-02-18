# MEMORY.md

Long-lived decisions and recurring caveats for this repository.
This is intentionally compact: only currently relevant guidance is kept.

## Usage Rules
- Record only stable technical decisions with clear operational impact.
- Prefer short entries over narrative history.
- When direction changes, replace outdated guidance with the new baseline.

## Current Baseline (2026-02-17)
- Runtime behavior is fixed by default, not host-side feature flags:
  - `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`
  - `DISABLE_ERROR_REPORTING=1`
  - `DISABLE_TELEMETRY=1`
  - `DISABLE_AUTOUPDATER=1`
  - Node TLS compat options are always applied (`--tls-max-v1.2 --tls-min-v1.2 --dns-result-order=ipv4first`).
- Auto-approve wrappers (Codex/Claude/Gemini/Copilot) are always enabled in sandbox shells.
- Managed configs are source-of-truth defaults (`configs/*` -> `/etc/skel` -> synced on startup where managed).
- `auto-approve.zsh` is managed and sync-updated for existing persisted homes.

## Network/Docker Defaults
- Container runtime always includes:
  - `host.docker.internal` mapping (when Docker supports `host-gateway`)
  - IPv6 disabled in container net namespace
  - custom bridge MTU default `1280`
- `run.sh` supports DNS override via `--dns` / `AGENT_SANDBOX_DNS_SERVERS` (IPv4-first).
- Rootless/user-owned Docker sockets are handled via host UID/GID matching logic (`AGENT_SANDBOX_MATCH_HOST_USER`).
- `run.sh` supports container-specific persisted homes: default container keeps `~/.agent-sandbox/home`, custom `--name <name>` defaults to `~/.agent-sandbox/<name>/home` (or explicit `--home` override).

## Skills/Agent Behavior
- Vendored shared skills are auto-installed for Claude/Codex/Gemini.
- `skill-creator` is excluded for Codex/Gemini to avoid overriding native behavior.
- `playwright-efficient-web-research` is force-synced as a managed shared skill.
- Web exploration baseline is `playwright-cli` session workflow (Chromium-pinned runtime).
- Playwright Chromium companion is fail-closed by default: build-time payload/executable assert + startup self-heal to `~/.cache/ms-playwright` with lock/TMPDIR isolation.
- Codex defaults enable `undo`, `multi_agent`, `apps` with `[agents].max_threads=12`; missing keys are auto-merged into existing `~/.codex/config.toml`.

## Automation Security Baseline
- GitHub automation is fail-closed on allowlist (`AGENT_ALLOWED_ACTORS` required).
- Foreign-fork PR review paths are skipped by default.
- External GitHub Actions are SHA-pinned.
- Automation bot commits may be unsigned; human maintainer commits should be signed.
- Agent workflows always publish their outputs (PR/review comments/artifacts), no secret-based visibility toggles.

## Known Constraints
- `broot` remains disabled in current image path due install stability concerns.
- Host-side Docker storage pressure can break builds even when `/workspace` has free space; use reclaimable-threshold cleanup (`scripts/docker-storage-guard.sh`) as operational baseline.

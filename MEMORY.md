# MEMORY.md

Long-lived decisions, important implementation history, and recurring caveats for this repository.

## Usage Rules
- Record significant technical decisions here with a date, rationale, and impact.
- Keep `AGENTS.md` and `CLAUDE.md` concise; they should reference this file instead of duplicating decision history.
- When a decision changes, append a new entry instead of rewriting old history.

## Decision Log

### 2026-02-15 - Stabilize Claude startup for telemetry/TLS edge cases
- Context: Even after API connectivity hardening, some users still saw `ERR_SSL_TLSV1_ALERT_DECRYPT_ERROR` while `curl` and plain Node HTTPS requests succeeded.
- Decision:
  - Updated `scripts/start.sh` to create `~/.claude/remote-settings.json` (`{}`) on first run when missing, preventing repeated startup `ENOENT` exceptions.
  - Added default Node TLS compatibility guard in `scripts/start.sh` (`AGENT_SANDBOX_NODE_TLS_COMPAT=1`) to apply `NODE_OPTIONS=--tls-max-v1.2 --tls-min-v1.2 --dns-result-order=ipv4first` for unstable TLS 1.3 paths.
  - Updated `run.sh` env forwarding to include `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` and `DISABLE_ERROR_REPORTING` so host-side troubleshooting flags can reach containerized Claude CLI.
  - Updated `run.sh` env forwarding to include `NODE_OPTIONS` and `AGENT_SANDBOX_NODE_TLS_COMPAT` so users can explicitly control Node TLS behavior from host.
  - Added README troubleshooting note for running with `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` when only Claude fails.
- Impact:
  - Reduced noisy startup exceptions from missing `remote-settings.json`.
  - Enabled quick host-driven mitigation when nonessential telemetry/event export traffic hits TLS edge failures.
  - Improved reliability on networks where Node TLS 1.3 sessions intermittently fail with `bad record mac`.

### 2026-02-15 - Harden network handling for Node CLI API connectivity
- Context: Users saw recurring `Unable to connect to API (UND_ERR_SOCKET)` when running agent CLIs (notably Claude) in the container.
- Decision:
  - Updated `run.sh` to forward proxy/trust environment variables (`HTTP[S]_PROXY`, `NO_PROXY`, `ALL_PROXY`, `SSL_CERT_FILE`, `SSL_CERT_DIR`, `NODE_EXTRA_CA_CERTS`).
  - Updated `run.sh` network logic to reconcile MTU drift: if `agent-sandbox-net` exists with non-1400 MTU, recreate it with MTU 1400.
  - Moved network ensure step to after stale container removal to reduce "active endpoint" failures during network recreation.
  - Added troubleshooting guidance to `README.md` for `UND_ERR_SOCKET`.
- Impact:
  - Corporate proxy and custom CA environments now work without manual `docker run -e ...` overrides.
  - Existing users with old network settings receive MTU fix automatically on next run.
  - Reduced frequency of TLS/socket-level API connectivity failures in Node-based agent CLIs.

### 2026-02-15 - Keep Git SSH signing config out of repository files
- Context: `allowed_signers` was briefly created in repository root, which could be accidentally committed via broad staging commands.
- Decision:
  - Moved signing configuration to HOME-global Git settings (`~/.gitconfig` + `~/.config/git/allowed_signers`).
  - Added repository guardrail by ignoring `.git_allowed_signers`.
  - Documented rule in `AGENTS.md`, `CLAUDE.md`, and `README.md`.
- Impact:
  - Signing remains reusable across future sessions.
  - Repository now avoids accidental inclusion of local signing metadata.

### 2026-02-15 - Prioritize beginner-friendly comments in shell/Docker files
- Context: Repository is used by a broad range of users, including beginners who need clearer operational understanding of scripts and container behavior.
- Decision:
  - Expanded explanatory comments in `run.sh`, `scripts/start.sh`, `Dockerfile`, and `docker-compose.yml`.
  - Added explicit convention to `AGENTS.md`, `CLAUDE.md`, and `README.md` to keep beginner-friendly comments as a standing rule.
- Impact:
  - Onboarding and maintenance are easier because execution flow, safety flags, and permission handling are documented inline.
  - Future code changes are expected to update comments together with logic changes.

### 2026-02-14 - Drop `cargo-binstall` in Docker build
- Context: Docker builds repeatedly failed or stalled due to `cargo-binstall` resolution issues (version mismatches, architecture artifact errors, GitHub API/rate-limit behavior).
- Decision: Removed `cargo-binstall`/Rust builder approach and switched to stable install paths only:
  - apt packages for base tooling
  - pinned GitHub release binaries for CLI tools
- Impact:
  - Build reliability improved in this environment.
  - Tool set may be adjusted by direct binary URLs instead of cargo crate install behavior.
- Follow-up: Keep release URLs pinned and verify arm64/x86_64 artifact naming when updating versions.

### 2026-02-14 - Re-enable `broot`
- Context: `broot` is useful for interactive tree navigation and was requested to be restored.
- Decision: Re-added `broot` installation in `Dockerfile` using `cargo install --locked --version ${BROOT_VERSION} broot` as a targeted exception.
- Impact:
  - `broot` remains available even when GitHub release asset naming is inconsistent across architectures.
  - Build time may increase due to source compilation for this one tool.

### 2026-02-14 - Defer `broot` install (TODO)
- Context: `broot` source build failed in this image because Debian bookworm `rustc` is too old (`1.63`, while dependency `rav1e` requires `>=1.70`), and release asset paths were not stable for arm64.
- Decision: Removed `broot` from the active build path and left a TODO in `Dockerfile` to re-enable with a reliable cross-arch install strategy.
- Impact:
  - Docker image build/test is stable again.
  - `broot` is currently excluded until toolchain/install path is upgraded.

### 2026-02-14 - Fill missing core CLI/agent tools
- Context: Initial build passed, but key requested tools were missing (`starship`, `bat`, `eza`, `opencode`), and agent verification was incomplete.
- Decision:
  - Added `bat`, `zoxide`, `tealdeer` via apt.
  - Added pinned `eza` and `starship` via GitHub release binaries with arch fallback logic.
  - Added `opencode-ai` npm package and build-time command verification (`command -v opencode`).
  - Added `npm@11.10.0` global update to keep npm current.
- Impact:
  - Requested core shell UX tools are now present by default.
  - Agent CLI availability is validated during image build.

### 2026-02-14 - Fix zimfw bootstrap invocation
- Context: First-run init printed `zimfw: Unknown action`, so modules were not installed correctly.
- Decision: Switched bootstrap call from `source ...; zimfw install` to direct invocation: `ZIM_HOME=... zsh .../zimfw.zsh install -q`.
- Impact:
  - First run now produces `~/.zim/init.zsh` correctly (`ZIM_OK` verified).
  - Startup remains non-interactive and resilient (`|| true` preserved).

### 2026-02-14 - Defer `tldr --update` bootstrap (TODO)
- Context: First-run `tldr --update` intermittently failed with `InvalidArchive("Could not find central directory end")` and produced noisy panic logs.
- Decision: Removed automatic `tldr --update` from `scripts/start.sh` and left a TODO comment for re-enablement after root-cause fix.
- Impact:
  - Container startup is cleaner and more predictable.
  - `tealdeer` remains installed, but cache warm-up is currently manual/on-demand.

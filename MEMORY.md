# MEMORY.md

Long-lived decisions, important implementation history, and recurring caveats for this repository.

## Usage Rules
- Record significant technical decisions here with a date, rationale, and impact.
- Keep `AGENTS.md` and `CLAUDE.md` concise; they should reference this file instead of duplicating decision history.
- When a decision changes, append a new entry instead of rewriting old history.

## Decision Log

### 2026-02-15 - Add repository-wide pinned-version maintenance script
- Context: This repository pins many tool/action versions across Dockerfile ARGs and GitHub workflows, but manual updates are error-prone and easy to miss.
- Decision:
  - Added `scripts/update-versions.sh` with three modes:
    - `scan`: list current pins without network calls
    - `check`: compare local pins with latest upstream releases/tags
    - `update`: rewrite Dockerfile ARG versions, workflow action SHA pins, and workflow `@openai/codex` npm pin
  - Included `--dry-run` mode for safe preview before file edits.
  - Added README usage guidance under `Version Maintenance`.
- Impact:
  - Maintainers can run a single command to audit and refresh pinned versions consistently.
  - Reduces drift risk in security-sensitive action SHA pins and tool version pins.

### 2026-02-15 - Disable public artifact upload by default and reduce log exposure
- Context: In a public repository, workflow artifacts can still expose intermediate bot output even when auto-publish and full PR comment modes are disabled.
- Decision:
  - Added `AGENT_PUBLIC_ARTIFACTS` secret gate for issue/PR workflows.
    - default (`false`/unset): do not upload patch/review artifacts
    - opt-in (`true`): upload short-lived artifacts (retention 1 day)
  - Updated issue intake -> worker secret mapping to pass `AGENT_PUBLIC_ARTIFACTS`.
  - Reduced Codex step log exposure by redirecting CLI output to temporary files instead of workflow console logs.
  - Updated issue/PR redacted comments to clearly indicate whether artifact upload is enabled.
- Impact:
  - Public exposure surface is reduced further in default mode.
  - Maintainers still have explicit opt-in controls for artifact-based workflows when needed.

### 2026-02-15 - Default to non-public output mode for automation in public repo
- Context: Even with allowlist controls, automatically publishing bot output (new branches/PRs and full review comments) can expose intermediate agent results in a public repository.
- Decision:
  - Added `AGENT_AUTO_PUBLISH` secret gate in issue worker:
    - default (`false`/unset): do not auto-push/create PR; upload patch artifact only
    - opt-in (`true`): allow branch push and PR creation
  - Added `AGENT_PUBLIC_REVIEW_COMMENT` secret gate in PR reviewer:
    - default (`false`/unset): post redacted public comment only and keep full review in artifact
    - opt-in (`true`): post full review content in PR comment
  - Added `actions/upload-artifact` (SHA-pinned) for patch/review outputs with short retention.
  - Kept allowlist checks and fork-PR guard in place.
- Impact:
  - Public exposure is minimized by default while preserving opt-in automation for maintainers.
  - Review and change outputs are no longer immediately broadcast in issue/PR comments unless explicitly enabled.

### 2026-02-15 - Simplify bot commits by removing CI GPG signing requirement
- Context: Signed bot commits using `AGENT_GPG_PRIVATE_KEY_B64` added operational complexity (key provisioning, rotation, failure handling) that outweighed value for this personal/public repository.
- Decision:
  - Removed `AGENT_GPG_PRIVATE_KEY_B64` from workflow secret contracts and intake -> worker secret mapping.
  - Deleted CI signing/import steps from `agent-issue-worker.yml`.
  - Switched automated bot commit command from `git commit -S` to unsigned `git commit`.
  - Updated README and operator guide to remove GPG secret setup requirements.
- Impact:
  - Automation setup is simpler and has fewer secret management requirements.
  - Bot commits are now unsigned by design; signed-commit policy should not be enforced for bot-authored automation branches.

### 2026-02-15 - Harden GitHub agent workflows for public personal repo operations
- Context: Initial allowlist-based automation still had residual risks: reusable workflow inherited all secrets, actions were tag-pinned (not SHA-pinned), Codex install was unpinned, AI execution could attempt premature push, and signed commits were not enforced in CI.
- Decision:
  - Removed `secrets: inherit` from issue intake -> worker call and switched to explicit secret mapping only.
  - Added reusable workflow secret schema in `agent-issue-worker.yml` and retained fail-closed allowlist behavior.
  - Pinned all external actions to commit SHA (`actions/checkout`, `actions/setup-node`, `actions/github-script`, `anthropics/claude-code-action`).
  - Pinned Codex CLI install version to `@openai/codex@0.101.0`.
  - Added timeout controls (`route: 5m`, `issue worker: 45m`, `PR reviewer: 30m`).
  - Added defense-in-depth allowlist checks inside worker/reviewer jobs (not only in routing jobs).
  - Added git push hardening before agent execution (`persist-credentials: false`, push URL disabled), and explicit guarded push only to `agent/issue-*` refs.
  - Enforced signed commits in automation with `AGENT_GPG_PRIVATE_KEY_B64` secret and `git commit -S`.
  - Added dedicated operator guide `GITHUB_AGENT_AUTOMATION_GUIDE.md` for secret setup, signing key setup, and safe trigger usage.
- Impact:
  - Secret blast radius is reduced to explicitly required credentials.
  - Supply-chain and drift risks are reduced via immutable action pinning and version pinning.
  - Public-repo abuse window is tightened through layered allowlist checks and branch/push safeguards.
  - Automated commits now align with signed-commit enforcement expectations.

### 2026-02-15 - Rebuild GitHub agent automation with actor allowlist and OAuth/login-cache auth
- Context: Initial automation used a single `.github/workflows/claude.yml` with API key auth and broad trigger conditions. User requirement changed to (1) support Claude via OAuth token, (2) support Codex via persisted login cache (`auth.json`) injection, and (3) prevent arbitrary users from triggering workflows.
- Decision:
  - Replaced single workflow with split architecture:
    - `agent-issue-intake.yml`: trigger routing and safety checks
    - `agent-issue-worker.yml`: issue-to-branch/commit/PR execution
    - `agent-pr-reviewer.yml`: automated PR review comments
  - Added fail-closed allowlist gate via `AGENT_ALLOWED_ACTORS` secret (comma-separated GitHub logins).
  - Added explicit actor verification for issue author/comment author/PR author and label sender before any automation run.
  - Switched Claude auth to `CLAUDE_CODE_OAUTH_TOKEN` (no Anthropic API key required in workflow).
  - Added Codex login-cache restoration path using `CODEX_AUTH_JSON_B64` -> `~/.codex/auth.json`, then non-interactive `codex exec`/`codex review`.
- Impact:
  - Automation now runs only for explicitly allowlisted users, reducing abuse risk from public issue comments or unauthorized label events.
  - Claude and Codex workflows can run without storing provider API keys directly in repository secrets, while preserving non-interactive CI execution.
  - Routing and worker responsibilities are separated, making future policy changes (approval gates, agent selection rules) easier to maintain.

### 2026-02-15 - Harden Docker socket access across platforms
- Context: Docker socket permission handling had two issues: (1) `run.sh` used macOS `stat -f` before Linux `stat -c`, but on Linux `stat -f` means `--file-system` and outputs filesystem info to stdout even on failure, corrupting the captured GID value; (2) Docker Desktop (macOS/Windows) sockets are always `root:root`, so sandbox user needed GID 0 membership to access them without `--group-add`.
- Decision:
  - Swapped `stat` fallback order in `run.sh` to try Linux `-c` first, then macOS `-f` (two locations: `sock_gid` and `sock_uid`).
  - Added `-G 0` (root supplementary group) to `useradd` in Dockerfile so Docker Desktop socket access works out of the box.
  - Added Docker socket access diagnostic in `scripts/start.sh` — on startup, checks if `/var/run/docker.sock` is mounted but inaccessible, and prints socket GID, user groups, and fix instructions.
- Impact:
  - Fixes silent GID corruption on Linux hosts that caused `--group-add` to receive garbage values.
  - Docker Desktop users no longer need manual `--group-add 0`.
  - Misconfigured socket permissions are diagnosed at container startup instead of failing silently when user first runs `docker`.

### 2026-02-15 - Enforce telemetry-off defaults on all runtime paths
- Context: Claude debug logs still showed `BigQuery metrics export failed ... bad record mac` and `Metrics opt-out API response: enabled=true` even after partial mitigations, indicating telemetry paths were still active in some launch paths.
- Decision:
  - Added `DISABLE_TELEMETRY` forwarding/defaults in `run.sh` alongside `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` and `DISABLE_ERROR_REPORTING`.
  - Added `DISABLE_TELEMETRY=${DISABLE_TELEMETRY:-1}` to `docker-compose.yml`.
  - Added `DISABLE_TELEMETRY` default export in `scripts/start.sh` as entrypoint fallback (applies even when launch bypasses `run.sh`).
  - Updated `README.md` environment/troubleshooting docs to include the telemetry flag.
- Impact:
  - Reduces TLS failure surface by disabling additional metrics export endpoints by default.
  - Keeps behavior consistent across `run.sh`, compose, and alternate container launch paths.

### 2026-02-15 - Harden Docker permission handling in run/compose paths
- Context: Users could still hit `permission denied while trying to connect to the docker API` depending on host socket type (rootful vs rootless) and UID/GID mismatch.
- Decision:
  - Added `run.sh` preflight check (`ensure_host_docker_access`) with actionable diagnostics before running Docker commands.
  - Added rootless socket auto-detection in `run.sh` (`/run/user/<uid>/docker.sock`).
  - Added host UID/GID compatibility mode in `run.sh` for user-owned sockets (`AGENT_SANDBOX_MATCH_HOST_USER`, default `auto`).
  - Updated `docker-compose.yml` with host user mapping support and explicit `DOCKER_HOST=unix:///var/run/docker.sock`.
  - Expanded README troubleshooting and compose examples for rootless Docker.
- Impact:
  - Fewer opaque docker permission failures.
  - Faster recovery with clear host-side actions and safer defaults across socket variants.

### 2026-02-15 - Switch agent installs from npm to bun
- Context: bun is already present in the image and is faster than npm for global package installs.
- Decision:
  - Replaced `npm install -g` with `bun install -g` for all agent CLIs (Claude Code, Codex, Gemini CLI, OpenCode, typescript, oh-my-opencode).
  - Dropped `npm@11.10.0` upgrade (no longer needed).
  - Added `$HOME/.local/bin` to PATH in `configs/zshrc` so runtime Claude updates (`~/.local/bin/claude`) are found.
  - Removed duplicate Node TLS compat logic from `start.sh` (single source of truth is `run.sh`).
  - Added default compose env values for TLS compatibility (`AGENT_SANDBOX_NODE_TLS_COMPAT=1`, default `NODE_OPTIONS` TLS flags) to align compose behavior with `run.sh`.
- Impact:
  - Faster image builds (bun vs npm).
  - Cleaner Dockerfile with fewer unnecessary layers.

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
  - Updated `run.sh` network logic to reconcile MTU drift: if `agent-sandbox-net` exists with non-1280 MTU, recreate it with MTU 1280.
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

### 2026-02-15 - Add missing tool binaries, security tools, Claude Code config, direnv, smoke test, and GH Actions
- Context: zshrc had aliases for dust, procs, btm, xh, mcfly but no binaries installed. Security tools (pre-commit, gitleaks, hadolint, shellcheck) were absent. Claude Code had no custom slash commands, skills, or MCP config. direnv was missing. No build-time tool verification existed. No GitHub Actions automation for issue-to-PR workflow.
- Decision:
  - **Batch 1 (Dockerfile):** Added dust v1.2.4, procs v0.14.10, bottom v0.12.3, xh v0.25.3, mcfly v0.9.4 from pinned GitHub release binaries. Key gotchas: procs uses zip, bottom tags have no `v` prefix, xh/mcfly use musl builds, dust needs `--strip-components=1`.
  - **Batch 2 (Dockerfile + configs):** Added shellcheck via apt, pre-commit via pip3, gitleaks v8.30.0 and hadolint v2.14.0 from GitHub releases. Created `configs/pre-commit-config.yaml` template with gitleaks, shellcheck, hadolint hooks. Template deployed to `~/.pre-commit-config.yaml.template` at first run.
  - **Batch 3 (configs + Dockerfile + start.sh):** Created 4 Claude Code slash commands (commit, review, test, debug) in `configs/claude/commands/`, 1 skill (sandbox-setup) in `configs/claude/skills/`, and MCP config (`configs/claude/mcp.json`) with filesystem server for /workspace. TOOLS.md deployed to container at `~/.config/agent-sandbox/TOOLS.md` via `/etc/skel/` pattern. Added `!TOOLS.md` exception to `.dockerignore`.
  - **Batch 4 (Dockerfile + zshrc + scripts):** Added direnv v2.37.1 from GitHub binary. Added direnv hook to zshrc. Created `scripts/smoke-test.sh` with `--build` flag to skip docker checks during image build. Smoke test runs during `docker build` and catches missing tools.
  - **Batch 5 (.github):** Created `.github/workflows/claude.yml` using `anthropics/claude-code-action@v1` for automated issue-to-PR workflow (triggered by `@claude` mentions or `claude` label).
- Impact:
  - All zshrc aliases now have corresponding binaries.
  - Security scanning infrastructure (gitleaks, shellcheck, hadolint) available out of the box.
  - Claude Code users get pre-configured slash commands and MCP server on first run.
  - Build-time smoke test catches missing tools before image ships.
  - Estimated image size increase: ~63 MB.

FROM debian:bookworm-slim AS runtime

LABEL maintainer="agent-sandbox"
LABEL description="Coding agent Docker sandbox with modern CLI tools"

ENV DEBIAN_FRONTEND=noninteractive

# Base OS package install.
# - Keep to --no-install-recommends to reduce image size/noise.
# - Remove apt list cache after install to keep layers smaller.
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git git-lfs gnupg sudo \
    unzip zip xz-utils \
    build-essential \
    python3 python3-pip python3-venv \
    zsh tmux locales \
    nnn ncdu jq ripgrep \
    bat zoxide tealdeer \
    dnsutils iputils-ping net-tools openssh-client \
    less file man-db htop \
    procps \
    shellcheck \
    && rm -rf /var/lib/apt/lists/*

# Enable UTF-8 locale so shells/tools behave consistently.
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install Node.js 22 (required by agent CLIs and bun global installs).
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI from official apt repo.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install Docker client tools in container.
# This image does not run docker daemon itself; it uses host socket mount (DooD).
RUN curl -fsSL https://download.docker.com/linux/debian/gpg \
    | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/debian bookworm stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends \
       docker-ce-cli docker-compose-plugin docker-buildx-plugin \
    && rm -rf /var/lib/apt/lists/*

ENV BUN_INSTALL=/usr/local
# Install Bun runtime/package manager.
RUN curl -fsSL https://bun.sh/install | bash

# Pinned versions make builds reproducible and easier to debug.
ARG FZF_VERSION=0.57.0
ARG EZA_VERSION=0.20.14
ARG STARSHIP_VERSION=1.22.1
ARG MICRO_VERSION=2.0.14
ARG DUF_VERSION=0.8.1
ARG GPING_VERSION=1.18.0
ARG FD_VERSION=10.2.0
ARG LAZYGIT_VERSION=0.44.1
ARG GITUI_VERSION=0.26.3
ARG TOKEI_VERSION=12.1.2
ARG YQ_VERSION=4.44.6
ARG DELTA_VERSION=0.18.2
ARG DUST_VERSION=1.2.4
ARG PROCS_VERSION=0.14.10
ARG BOTTOM_VERSION=0.12.3
ARG XH_VERSION=0.25.3
ARG MCFLY_VERSION=0.9.4
ARG GITLEAKS_VERSION=8.30.0
ARG HADOLINT_VERSION=2.14.0
ARG DIRENV_VERSION=2.37.1
ARG PRE_COMMIT_VERSION=4.5.1

# Install fzf from release artifact.
# Architecture names differ by project; map debian arch -> release arch.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then FZF_ARCH="arm64"; else FZF_ARCH="amd64"; fi \
    && curl -fsSL "https://github.com/junegunn/fzf/releases/download/v${FZF_VERSION}/fzf-${FZF_VERSION}-linux_${FZF_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin/

# Install eza with fallback between gnu and musl artifact names.
# Some releases publish one but not the other.
RUN set -eux; \
    ARCH="$(dpkg --print-architecture)"; \
    if [ "$ARCH" = "arm64" ]; then EZA_ARCH="aarch64"; else EZA_ARCH="x86_64"; fi; \
    FOUND=""; \
    for URL in \
      "https://github.com/eza-community/eza/releases/download/v${EZA_VERSION}/eza_${EZA_ARCH}-unknown-linux-gnu.tar.gz" \
      "https://github.com/eza-community/eza/releases/download/v${EZA_VERSION}/eza_${EZA_ARCH}-unknown-linux-musl.tar.gz"; do \
      if curl -fsSL "$URL" -o /tmp/eza.tar.gz; then FOUND="$URL"; break; fi; \
    done; \
    test -n "$FOUND"; \
    tar -xzf /tmp/eza.tar.gz -C /tmp; \
    EZA_BIN="$(find /tmp -maxdepth 4 -type f -name eza | head -n 1)"; \
    test -n "$EZA_BIN"; \
    install -m 0755 "$EZA_BIN" /usr/local/bin/eza; \
    rm -rf /tmp/eza.tar.gz /tmp/eza*

# Install starship with gnu/musl fallback logic.
RUN set -eux; \
    ARCH="$(dpkg --print-architecture)"; \
    if [ "$ARCH" = "arm64" ]; then STARSHIP_ARCH="aarch64"; else STARSHIP_ARCH="x86_64"; fi; \
    FOUND=""; \
    for URL in \
      "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-${STARSHIP_ARCH}-unknown-linux-gnu.tar.gz" \
      "https://github.com/starship/starship/releases/download/v${STARSHIP_VERSION}/starship-${STARSHIP_ARCH}-unknown-linux-musl.tar.gz"; do \
      if curl -fsSL "$URL" -o /tmp/starship.tar.gz; then FOUND="$URL"; break; fi; \
    done; \
    test -n "$FOUND"; \
    tar -xzf /tmp/starship.tar.gz -C /tmp; \
    install -m 0755 /tmp/starship /usr/local/bin/starship; \
    rm -rf /tmp/starship /tmp/starship.tar.gz

# Install micro editor.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then MICRO_ARCH="-arm64"; else MICRO_ARCH="64"; fi \
    && curl -fsSL "https://github.com/zyedidia/micro/releases/download/v${MICRO_VERSION}/micro-${MICRO_VERSION}-linux${MICRO_ARCH}.tar.gz" \
    | tar -xz --strip-components=1 -C /usr/local/bin/ "micro-${MICRO_VERSION}/micro"

# Install duf via .deb package.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then DUF_ARCH="arm64"; else DUF_ARCH="amd64"; fi \
    && curl -fsSL "https://github.com/muesli/duf/releases/download/v${DUF_VERSION}/duf_${DUF_VERSION}_linux_${DUF_ARCH}.deb" -o /tmp/duf.deb \
    && dpkg -i /tmp/duf.deb && rm /tmp/duf.deb

# Install gping.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then GPING_ARCH="aarch64"; else GPING_ARCH="x86_64"; fi \
    && curl -fsSL "https://github.com/orf/gping/releases/download/gping-v${GPING_VERSION}/gping-${GPING_ARCH}-unknown-linux-gnu.tar.gz" \
    | tar -xz -C /usr/local/bin/

# Install fd binary.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then FD_ARCH="aarch64"; else FD_ARCH="x86_64"; fi \
    && curl -fsSL "https://github.com/sharkdp/fd/releases/download/v${FD_VERSION}/fd-v${FD_VERSION}-${FD_ARCH}-unknown-linux-gnu.tar.gz" \
    | tar -xz --strip-components=1 -C /usr/local/bin/ "fd-v${FD_VERSION}-${FD_ARCH}-unknown-linux-gnu/fd"

# Install lazygit.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then LG_ARCH="arm64"; else LG_ARCH="x86_64"; fi \
    && curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_${LG_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin/ lazygit

# Install gitui.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then GITUI_ARCH="aarch64"; else GITUI_ARCH="x86_64"; fi \
    && curl -fsSL "https://github.com/gitui-org/gitui/releases/download/v${GITUI_VERSION}/gitui-linux-${GITUI_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin/

# Install tokei.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then TOKEI_ARCH="aarch64"; else TOKEI_ARCH="x86_64"; fi \
    && curl -fsSL "https://github.com/XAMPPRocky/tokei/releases/download/v${TOKEI_VERSION}/tokei-${TOKEI_ARCH}-unknown-linux-gnu.tar.gz" \
    | tar -xz -C /usr/local/bin/

# TODO: Re-enable broot after adopting a reliable install path across arm64/x86_64
# and a modern Rust toolchain in build steps.

# Install yq (single static binary).
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then YQ_ARCH="arm64"; else YQ_ARCH="amd64"; fi \
    && curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${YQ_ARCH}" -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq

# Install git-delta.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then DELTA_ARCH="aarch64"; else DELTA_ARCH="x86_64"; fi \
    && curl -fsSL "https://github.com/dandavison/delta/releases/download/${DELTA_VERSION}/delta-${DELTA_VERSION}-${DELTA_ARCH}-unknown-linux-gnu.tar.gz" \
    | tar -xz --strip-components=1 -C /usr/local/bin/ "delta-${DELTA_VERSION}-${DELTA_ARCH}-unknown-linux-gnu/delta"

# Debian package may expose bat as batcat. Create bat symlink for consistency.
RUN if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then ln -s /usr/bin/batcat /usr/local/bin/bat; fi

# Install dust (better du replacement).
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then DUST_ARCH="aarch64"; else DUST_ARCH="x86_64"; fi \
    && curl -fsSL "https://github.com/bootandy/dust/releases/download/v${DUST_VERSION}/dust-v${DUST_VERSION}-${DUST_ARCH}-unknown-linux-gnu.tar.gz" \
    | tar -xz --strip-components=1 -C /usr/local/bin/ "dust-v${DUST_VERSION}-${DUST_ARCH}-unknown-linux-gnu/dust"

# Install procs (better ps replacement).
# procs uses zip archives, not tar.gz.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then PROCS_ARCH="aarch64"; else PROCS_ARCH="x86_64"; fi \
    && curl -fsSL "https://github.com/dalance/procs/releases/download/v${PROCS_VERSION}/procs-v${PROCS_VERSION}-${PROCS_ARCH}-linux.zip" -o /tmp/procs.zip \
    && unzip -o /tmp/procs.zip -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/procs \
    && rm /tmp/procs.zip

# Install bottom (btm — better top replacement).
# NOTE: bottom release tags do NOT have a 'v' prefix.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then BTM_ARCH="aarch64"; else BTM_ARCH="x86_64"; fi \
    && curl -fsSL "https://github.com/ClementTsang/bottom/releases/download/${BOTTOM_VERSION}/bottom_${BTM_ARCH}-unknown-linux-gnu.tar.gz" \
    | tar -xz -C /usr/local/bin/ btm

# Install xh (better curl/httpie replacement for API testing).
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then XH_ARCH="aarch64"; else XH_ARCH="x86_64"; fi \
    && curl -fsSL "https://github.com/ducaale/xh/releases/download/v${XH_VERSION}/xh-v${XH_VERSION}-${XH_ARCH}-unknown-linux-musl.tar.gz" \
    | tar -xz --strip-components=1 -C /usr/local/bin/ "xh-v${XH_VERSION}-${XH_ARCH}-unknown-linux-musl/xh"

# Install mcfly (intelligent shell history search, overrides Ctrl+R).
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then MCFLY_ARCH="aarch64"; else MCFLY_ARCH="x86_64"; fi \
    && curl -fsSL "https://github.com/cantino/mcfly/releases/download/v${MCFLY_VERSION}/mcfly-v${MCFLY_VERSION}-${MCFLY_ARCH}-unknown-linux-musl.tar.gz" \
    | tar -xz -C /usr/local/bin/ mcfly

# Install pre-commit (code quality hook framework).
# --break-system-packages is safe in container context (no venv needed).
RUN pip3 install --break-system-packages "pre-commit==${PRE_COMMIT_VERSION}"

# Install gitleaks (detect secrets in git commits).
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then GL_ARCH="arm64"; else GL_ARCH="x64"; fi \
    && curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GL_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin/ gitleaks

# Install hadolint (Dockerfile linter, single static binary).
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then HL_ARCH="arm64"; else HL_ARCH="x86_64"; fi \
    && curl -fsSL "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-${HL_ARCH}" -o /usr/local/bin/hadolint \
    && chmod +x /usr/local/bin/hadolint

# Install direnv (auto-load .envrc per-directory environment variables).
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then DIRENV_ARCH="arm64"; else DIRENV_ARCH="amd64"; fi \
    && curl -fsSL "https://github.com/direnv/direnv/releases/download/v${DIRENV_VERSION}/direnv.linux-${DIRENV_ARCH}" -o /usr/local/bin/direnv \
    && chmod +x /usr/local/bin/direnv

# Create non-root runtime user.
# sudo is configured for compatibility, but run.sh also sets no-new-privileges.
# sandbox is added to root group (GID 0) so Docker socket access works on
# Docker Desktop (macOS/Windows) where the socket is always root:root.
# On Linux the socket is typically owned by a "docker" group with a different
# GID — run.sh handles that via --group-add at container launch time.
RUN groupadd -g 1000 sandbox \
    && useradd -m -u 1000 -g 1000 -G 0 -s /bin/zsh sandbox \
    && echo "sandbox ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/sandbox \
    && chmod 0440 /etc/sudoers.d/sandbox

# Install coding-agent CLIs globally via bun (faster than npm).
# BUN_INSTALL=/usr/local means global binaries land in /usr/local/bin/.
RUN bun install -g \
    @anthropic-ai/claude-code \
    @openai/codex \
    @google/gemini-cli \
    opencode-ai \
    typescript \
    oh-my-opencode

# Install LSP servers for code intelligence.
# These provide autocomplete, go-to-definition, and diagnostics for coding agents.
RUN bun install -g \
    typescript-language-server \
    bash-language-server \
    dockerfile-language-server-nodejs \
    vscode-langservers-extracted \
    yaml-language-server \
    pyright

# Build-time sanity check: fail early if key CLIs are missing.
# Each check is separate so the error message identifies the missing binary.
RUN command -v claude || { echo "ERROR: claude not found"; exit 1; } \
    && command -v codex || { echo "ERROR: codex not found"; exit 1; } \
    && command -v gemini || { echo "ERROR: gemini not found"; exit 1; } \
    && command -v opencode || { echo "ERROR: opencode not found"; exit 1; } \
    && command -v dust || { echo "ERROR: dust not found"; exit 1; } \
    && command -v procs || { echo "ERROR: procs not found"; exit 1; } \
    && command -v btm || { echo "ERROR: btm not found"; exit 1; } \
    && command -v xh || { echo "ERROR: xh not found"; exit 1; } \
    && command -v mcfly || { echo "ERROR: mcfly not found"; exit 1; } \
    && command -v pre-commit || { echo "ERROR: pre-commit not found"; exit 1; } \
    && command -v gitleaks || { echo "ERROR: gitleaks not found"; exit 1; } \
    && command -v hadolint || { echo "ERROR: hadolint not found"; exit 1; } \
    && command -v shellcheck || { echo "ERROR: shellcheck not found"; exit 1; } \
    && command -v direnv || { echo "ERROR: direnv not found"; exit 1; } \
    && command -v ps || { echo "ERROR: ps not found"; exit 1; } \
    && command -v pkill || { echo "ERROR: pkill not found"; exit 1; } \
    && command -v typescript-language-server || { echo "ERROR: typescript-language-server not found"; exit 1; } \
    && command -v bash-language-server || { echo "ERROR: bash-language-server not found"; exit 1; } \
    && command -v docker-langserver || { echo "ERROR: docker-langserver not found"; exit 1; } \
    && command -v vscode-json-language-server || { echo "ERROR: vscode-json-language-server not found"; exit 1; } \
    && command -v yaml-language-server || { echo "ERROR: yaml-language-server not found"; exit 1; } \
    && command -v pyright || { echo "ERROR: pyright not found"; exit 1; }

# Default dotfiles are copied to /etc/skel.
# start.sh later copies them into user home only when missing.
COPY configs/zshrc /etc/skel/.default.zshrc
COPY configs/zimrc /etc/skel/.default.zimrc
COPY configs/tmux.conf /etc/skel/.default.tmux.conf
COPY configs/starship.toml /etc/skel/.config/starship.toml

# Pre-commit config template for initializing hooks in projects.
COPY configs/pre-commit-config.yaml /etc/skel/.default.pre-commit-config.yaml

# Claude Code slash commands, skills, agents, settings, and MCP server config.
COPY configs/claude/commands/ /etc/skel/.claude/commands/
COPY configs/claude/skills/ /etc/skel/.claude/skills/
COPY configs/claude/agents/ /etc/skel/.claude/agents/
COPY configs/claude/settings.json /etc/skel/.claude/settings.json
COPY configs/claude/mcp.json /etc/skel/.claude/.mcp.json
COPY configs/claude/settings.json /etc/skel/.claude/settings.json

# Deploy LSP config to Codex and Gemini CLI as well.
# start.sh will copy these to user home on first run.
RUN mkdir -p /etc/skel/.codex /etc/skel/.gemini \
    && cp /etc/skel/.claude/settings.json /etc/skel/.codex/settings.json \
    && cp /etc/skel/.claude/settings.json /etc/skel/.gemini/settings.json

# Shared skills bundle (Anthropic skills repo vendored under ./skills).
# start.sh installs these into each agent's user skill directory on startup.
COPY skills/ /opt/agent-sandbox/skills/

# TOOLS.md reference for agents working on other projects.
# .dockerignore needs !TOOLS.md exception (after *.md) to include this file.
COPY TOOLS.md /etc/skel/.config/agent-sandbox/TOOLS.md
# Auto-approve wrapper config for agent CLIs in interactive zsh sessions.
COPY configs/agent-auto-approve.zsh /etc/skel/.config/agent-sandbox/auto-approve.zsh

# Smoke test script for build-time and runtime tool verification.
COPY scripts/smoke-test.sh /usr/local/bin/smoke-test.sh
RUN chmod +x /usr/local/bin/smoke-test.sh

# Entry script handles first-run bootstrap, then exec CMD.
COPY scripts/start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

# Run smoke test during build (--build skips docker socket checks).
RUN /usr/local/bin/smoke-test.sh --build

ENV STARSHIP_CONFIG=/home/sandbox/.config/starship.toml

# Runtime defaults:
# - run as non-root user
# - work in mounted project path
USER sandbox
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/start.sh"]
CMD ["/bin/zsh"]

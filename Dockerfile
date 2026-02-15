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
    && rm -rf /var/lib/apt/lists/*

# Enable UTF-8 locale so shells/tools behave consistently.
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install Node.js 22 (required by modern agent CLIs and npm global tools).
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

# Create non-root runtime user.
# sudo is configured for compatibility, but run.sh also sets no-new-privileges.
RUN groupadd -g 1000 sandbox \
    && useradd -m -u 1000 -g 1000 -s /bin/zsh sandbox \
    && echo "sandbox ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/sandbox \
    && chmod 0440 /etc/sudoers.d/sandbox

# Install remaining coding-agent CLIs globally via npm.
RUN npm install -g \
    npm@11.10.0 \
    @openai/codex \
    @google/gemini-cli \
    opencode-ai \
    typescript \
    oh-my-opencode

# Install Claude Code via native installer (npm package is deprecated).
# The installer runs as root, placing binary in /root/.local/bin and data
# in /root/.local/share/claude. Move both to system-wide /usr/local/ paths
# so the sandbox user can use claude without depending on /root paths.
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && mv /root/.local/bin/claude /usr/local/bin/claude \
    && if [ -d /root/.local/share/claude ]; then \
         mkdir -p /usr/local/share/claude \
         && cp -a /root/.local/share/claude/. /usr/local/share/claude/ \
         && rm -rf /root/.local/share/claude; \
       fi

# Build-time sanity check: fail early if key CLIs are missing.
RUN command -v claude && command -v codex && command -v gemini && command -v opencode

# Default dotfiles are copied to /etc/skel.
# start.sh later copies them into user home only when missing.
COPY configs/zshrc /etc/skel/.default.zshrc
COPY configs/zimrc /etc/skel/.default.zimrc
COPY configs/tmux.conf /etc/skel/.default.tmux.conf
COPY configs/starship.toml /etc/skel/.config/starship.toml

# Entry script handles first-run bootstrap, then exec CMD.
COPY scripts/start.sh /usr/local/bin/start.sh
RUN chmod +x /usr/local/bin/start.sh

ENV STARSHIP_CONFIG=/home/sandbox/.config/starship.toml

# Runtime defaults:
# - run as non-root user
# - work in mounted project path
USER sandbox
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/start.sh"]
CMD ["/bin/zsh"]

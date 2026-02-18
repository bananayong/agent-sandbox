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
    vim \
    nnn ncdu \
    dnsutils iputils-ping net-tools openssh-client \
    less file man-db help2man htop \
    procps \
    # Playwright Chromium runtime dependencies.
    libasound2 libatk-bridge2.0-0 libatk1.0-0 libatspi2.0-0 \
    libcairo2 libcups2 libdbus-1-3 libdrm2 libgbm1 libglib2.0-0 \
    libnspr4 libnss3 libpango-1.0-0 libx11-6 libxcb1 libxcomposite1 \
    libxdamage1 libxext6 libxfixes3 libxkbcommon0 libxrandr2 \
    libfontconfig1 libfreetype6 xvfb xfonts-scalable \
    fonts-noto-color-emoji fonts-unifont fonts-liberation \
    fonts-ipafont-gothic fonts-wqy-zenhei fonts-tlwg-loma-otf \
    fonts-freefont-ttf \
    && rm -rf /var/lib/apt/lists/*

# Debian slim은 /usr/share/man/*를 기본 제외하므로,
# 필요한 apt CLI의 man 페이지만 선택적으로 추출해 /usr/local/share/man에 둔다.
RUN set -eux; \
    apt-get update; \
    mkdir -p /tmp/apt-man/extract /usr/local/share/man; \
    cd /tmp/apt-man; \
    # zsh man pages are shipped by zsh-common, not zsh binary package.
    for pkg in curl zsh zsh-common htop nnn ncdu; do \
      apt-get download "$pkg"; \
    done; \
    for deb in ./*.deb; do \
      dpkg-deb --fsys-tarfile "$deb" \
      | tar -x -C /tmp/apt-man/extract --wildcards './usr/share/man/*'; \
    done; \
    cp -a /tmp/apt-man/extract/usr/share/man/. /usr/local/share/man/; \
    rm -rf /tmp/apt-man /var/lib/apt/lists/*

# Enable UTF-8 locale so shells/tools behave consistently.
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Install Node.js 22 (required by agent CLIs and bun global installs).
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install GitHub CLI from official apt repo.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends gh \
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
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
# Install Bun runtime/package manager.
RUN curl -fsSL https://bun.sh/install | bash

# Pinned versions make builds reproducible and easier to debug.
ARG FZF_VERSION=0.67.0
ARG EZA_VERSION=0.23.4
ARG STARSHIP_VERSION=1.24.2
ARG TEALDEER_VERSION=1.8.1
ARG NEOVIM_VERSION=0.11.5
ARG MICRO_VERSION=2.0.15
ARG DUF_VERSION=0.9.1
ARG GPING_VERSION=1.20.1
ARG FD_VERSION=10.3.0
ARG LAZYGIT_VERSION=0.59.0
ARG GITUI_VERSION=0.28.0
ARG TOKEI_VERSION=14.0.0
ARG YQ_VERSION=4.52.4
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
ARG PLAYWRIGHT_CLI_VERSION=0.1.1
ARG ACTIONLINT_VERSION=1.7.11
ARG TRIVY_VERSION=0.69.1
ARG RIPGREP_VERSION=15.1.0
ARG RIPGREP_SHA256_AMD64=1c9297be4a084eea7ecaedf93eb03d058d6faae29bbc57ecdaf5063921491599
ARG RIPGREP_SHA256_ARM64=2b661c6ef508e902f388e9098d9c4c5aca72c87b55922d94abdba830b4dc885e
ARG BAT_VERSION=0.26.1
ARG BAT_SHA256_AMD64=726f04c8f576a7fd18b7634f1bbf2f915c43494c1c0f013baa3287edb0d5a2a3
ARG BAT_SHA256_ARM64=422eb73e11c854fddd99f5ca8461c2f1d6e6dce0a2a8c3d5daade5ffcb6564aa
ARG ZOXIDE_VERSION=0.9.9
ARG ZOXIDE_SHA256_AMD64=4ff057d3c4d957946937274c2b8be7af2a9bbae7f90a1b5e9baaa7cb65a20caa
ARG ZOXIDE_SHA256_ARM64=96e6ea2e47a71db42cb7ad5a36e9209c8cb3708f8ae00f6945573d0d93315cb0
ARG JQ_VERSION=1.8.1
ARG JQ_SHA256_AMD64=020468de7539ce70ef1bceaf7cde2e8c4f2ca6c3afb84642aabc5c97d9fc2a0d
ARG JQ_SHA256_ARM64=6bc62f25981328edd3cfcfe6fe51b073f2d7e7710d7ef7fcdac28d4e384fc3d4
ARG SHELLCHECK_VERSION=0.11.0
ARG SHELLCHECK_SHA256_AMD64=8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198
ARG SHELLCHECK_SHA256_ARM64=12b331c1d2db6b9eb13cfca64306b1b157a86eb69db83023e261eaa7e7c14588
ARG UV_VERSION=0.10.4
ARG UV_SHA256_AMD64=6b52a47358deea1c5e173278bf46b2b489747a59ae31f2a4362ed5c6c1c269f7
ARG UV_SHA256_ARM64=c84a6e6405715caa6e2f5ef8e5f29a5d0bc558a954e9f1b5c082b9d4708c222e

# Install Neovim from upstream release (newer than Debian stable package).
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then NVIM_ARCH="arm64"; else NVIM_ARCH="x86_64"; fi \
    && curl -fsSL "https://github.com/neovim/neovim/releases/download/v${NEOVIM_VERSION}/nvim-linux-${NVIM_ARCH}.tar.gz" -o /tmp/nvim.tar.gz \
    && tar -xzf /tmp/nvim.tar.gz -C /opt \
    && ln -sf "/opt/nvim-linux-${NVIM_ARCH}/bin/nvim" /usr/local/bin/nvim \
    && update-alternatives --install /usr/bin/editor editor /usr/local/bin/nvim 120 \
    && update-alternatives --set editor /usr/local/bin/nvim \
    && rm -f /tmp/nvim.tar.gz

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

# Install tealdeer (tldr client) from upstream release.
# Debian bookworm ships tealdeer 1.5.0, which uses an outdated update URL and
# can panic with InvalidArchive on first cache refresh.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then TEALDEER_ARCH="aarch64"; else TEALDEER_ARCH="x86_64"; fi \
    && curl -fsSL "https://github.com/dbrgn/tealdeer/releases/download/v${TEALDEER_VERSION}/tealdeer-linux-${TEALDEER_ARCH}-musl" -o /usr/local/bin/tldr \
    && chmod +x /usr/local/bin/tldr

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

# Install ripgrep and ship upstream man page.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then RG_ARCH="aarch64-unknown-linux-gnu"; RG_SHA256="${RIPGREP_SHA256_ARM64}"; else RG_ARCH="x86_64-unknown-linux-musl"; RG_SHA256="${RIPGREP_SHA256_AMD64}"; fi \
    && mkdir -p /tmp/rg /usr/local/share/man/man1 \
    && curl -fsSL "https://github.com/BurntSushi/ripgrep/releases/download/${RIPGREP_VERSION}/ripgrep-${RIPGREP_VERSION}-${RG_ARCH}.tar.gz" -o /tmp/rg.tar.gz \
    && echo "${RG_SHA256}  /tmp/rg.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/rg.tar.gz -C /tmp/rg --strip-components=1 \
    && install -m 0755 /tmp/rg/rg /usr/local/bin/rg \
    && install -m 0644 /tmp/rg/doc/rg.1 /usr/local/share/man/man1/rg.1 \
    && rm -rf /tmp/rg /tmp/rg.tar.gz

# Install bat and upstream man page.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then BAT_ARCH="aarch64-unknown-linux-gnu"; BAT_SHA256="${BAT_SHA256_ARM64}"; else BAT_ARCH="x86_64-unknown-linux-gnu"; BAT_SHA256="${BAT_SHA256_AMD64}"; fi \
    && mkdir -p /tmp/bat /usr/local/share/man/man1 \
    && curl -fsSL "https://github.com/sharkdp/bat/releases/download/v${BAT_VERSION}/bat-v${BAT_VERSION}-${BAT_ARCH}.tar.gz" -o /tmp/bat.tar.gz \
    && echo "${BAT_SHA256}  /tmp/bat.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/bat.tar.gz -C /tmp/bat --strip-components=1 \
    && install -m 0755 /tmp/bat/bat /usr/local/bin/bat \
    && install -m 0644 /tmp/bat/bat.1 /usr/local/share/man/man1/bat.1 \
    && rm -rf /tmp/bat /tmp/bat.tar.gz

# Install zoxide and all upstream man pages.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then ZOXIDE_ARCH="aarch64"; ZOXIDE_SHA256="${ZOXIDE_SHA256_ARM64}"; else ZOXIDE_ARCH="x86_64"; ZOXIDE_SHA256="${ZOXIDE_SHA256_AMD64}"; fi \
    && mkdir -p /tmp/zoxide /usr/local/share/man/man1 \
    && curl -fsSL "https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-${ZOXIDE_ARCH}-unknown-linux-musl.tar.gz" -o /tmp/zoxide.tar.gz \
    && echo "${ZOXIDE_SHA256}  /tmp/zoxide.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/zoxide.tar.gz -C /tmp/zoxide \
    && install -m 0755 /tmp/zoxide/zoxide /usr/local/bin/zoxide \
    && install -m 0644 /tmp/zoxide/man/man1/*.1 /usr/local/share/man/man1/ \
    && rm -rf /tmp/zoxide /tmp/zoxide.tar.gz

# Install jq binary and prebuilt man page.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then JQ_ARCH="arm64"; JQ_SHA256="${JQ_SHA256_ARM64}"; else JQ_ARCH="amd64"; JQ_SHA256="${JQ_SHA256_AMD64}"; fi \
    && mkdir -p /usr/local/share/man/man1 /tmp/jq-src \
    && curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${JQ_ARCH}" -o /usr/local/bin/jq \
    && echo "${JQ_SHA256}  /usr/local/bin/jq" | sha256sum -c - \
    && chmod +x /usr/local/bin/jq \
    && curl -fsSL "https://github.com/jqlang/jq/archive/refs/tags/jq-${JQ_VERSION}.tar.gz" \
    | tar -xz -C /tmp/jq-src --strip-components=1 "jq-jq-${JQ_VERSION}/jq.1.prebuilt" \
    && install -m 0644 /tmp/jq-src/jq.1.prebuilt /usr/local/share/man/man1/jq.1 \
    && rm -rf /tmp/jq-src

# Install shellcheck from upstream release artifact.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then SC_ARCH="aarch64"; SC_SHA256="${SHELLCHECK_SHA256_ARM64}"; else SC_ARCH="x86_64"; SC_SHA256="${SHELLCHECK_SHA256_AMD64}"; fi \
    && mkdir -p /tmp/shellcheck \
    && curl -fsSL "https://github.com/koalaman/shellcheck/releases/download/v${SHELLCHECK_VERSION}/shellcheck-v${SHELLCHECK_VERSION}.linux.${SC_ARCH}.tar.xz" -o /tmp/shellcheck.tar.xz \
    && echo "${SC_SHA256}  /tmp/shellcheck.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/shellcheck.tar.xz -C /tmp/shellcheck --strip-components=1 \
    && install -m 0755 /tmp/shellcheck/shellcheck /usr/local/bin/shellcheck \
    && rm -rf /tmp/shellcheck /tmp/shellcheck.tar.xz

# Install uv (Python package manager) from upstream release artifact.
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then UV_ARCH="aarch64"; UV_SHA256="${UV_SHA256_ARM64}"; else UV_ARCH="x86_64"; UV_SHA256="${UV_SHA256_AMD64}"; fi \
    && mkdir -p /tmp/uv \
    && curl -fsSL "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${UV_ARCH}-unknown-linux-gnu.tar.gz" -o /tmp/uv.tar.gz \
    && echo "${UV_SHA256}  /tmp/uv.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/uv.tar.gz -C /tmp/uv --strip-components=1 \
    && install -m 0755 /tmp/uv/uv /usr/local/bin/uv \
    && install -m 0755 /tmp/uv/uvx /usr/local/bin/uvx \
    && rm -rf /tmp/uv /tmp/uv.tar.gz

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

# Install actionlint (GitHub Actions workflow linter, single static binary).
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then AL_ARCH="arm64"; else AL_ARCH="amd64"; fi \
    && curl -fsSL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${AL_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin/ actionlint

# Install trivy (container image and filesystem vulnerability scanner).
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then TRIVY_ARCH="ARM64"; else TRIVY_ARCH="64bit"; fi \
    && curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${TRIVY_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin/ trivy

# Generate fallback man pages for tools that do not ship upstream man files.
RUN mkdir -p /usr/local/share/man/man1 \
    && export SOURCE_DATE_EPOCH=1704067200 TZ=UTC LC_ALL=C \
    && for cmd in uv uvx shellcheck; do \
      if ! man -w "$cmd" >/dev/null 2>&1; then \
        help2man --no-info --no-discard-stderr "$cmd" > "/usr/local/share/man/man1/${cmd}.1"; \
      fi; \
    done \
    && find /usr/local/share/man -type f -name '*.1' -exec gzip -nf {} + \
    && mandb -q

# Install pre-commit (code quality hook framework).
# --break-system-packages is safe in container context (no venv needed).
RUN pip3 install --break-system-packages --no-cache-dir "pre-commit==${PRE_COMMIT_VERSION}" yamllint

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

# Install Playwright CLI and pin browser payload to Chromium.
# PLAYWRIGHT_BROWSERS_PATH makes browser binaries available to all users.
RUN npm install -g "@playwright/cli@${PLAYWRIGHT_CLI_VERSION}" \
    && mkdir -p /tmp/playwright-bootstrap/.playwright \
    && printf '{\n  "browser": {\n    "browserName": "chromium"\n  }\n}\n' > /tmp/playwright-bootstrap/.playwright/cli.config.json \
    && cd /tmp/playwright-bootstrap \
    && playwright-cli install \
    && cd / \
    && rm -rf /tmp/playwright-bootstrap \
    && chmod -R a+rX "$PLAYWRIGHT_BROWSERS_PATH" \
    # Keep this cleanup in the same layer so build-time caches do not inflate image size.
    && npm cache clean --force \
    && rm -rf /root/.npm /tmp/node-compile-cache /tmp/bunx-*

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
    oh-my-opencode \
    # opencode and oh-my-opencode ship both glibc and musl optional binaries.
    # Debian runtime only needs glibc binaries, so drop musl variants.
    && ARCH="$(dpkg --print-architecture)" \
    && if [ "$ARCH" = "arm64" ]; then BIN_ARCH="arm64"; else BIN_ARCH="x64"; fi \
    && rm -rf \
      "/usr/local/install/global/node_modules/opencode-linux-${BIN_ARCH}-musl" \
      "/usr/local/install/global/node_modules/oh-my-opencode-linux-${BIN_ARCH}-musl" \
    # Bun global installs duplicate package tarballs in /usr/local/install/cache.
    # Clearing in the same RUN layer reclaims substantial space in final image.
    && rm -rf /usr/local/install/cache /root/.cache /tmp/node-compile-cache /tmp/bunx-*

# Install agent productivity tools via bun.
RUN bun install -g @beads/bd \
    && rm -rf /usr/local/install/cache /root/.cache /tmp/node-compile-cache /tmp/bunx-*

# beads package downloads its native runtime via postinstall.
# Bun blocks postinstall scripts by default, so explicitly trust this package.
RUN printf 'y\n' | bun pm -g trust @beads/bd \
    && ARCH="$(dpkg --print-architecture)" \
    && if [ "$ARCH" = "arm64" ]; then BIN_ARCH="arm64"; else BIN_ARCH="x64"; fi \
    && rm -rf \
      "/usr/local/install/global/node_modules/opencode-linux-${BIN_ARCH}-musl" \
      "/usr/local/install/global/node_modules/oh-my-opencode-linux-${BIN_ARCH}-musl" \
      /usr/local/install/cache /root/.cache /tmp/node-compile-cache /tmp/bunx-*

# Install LSP servers for code intelligence.
# These provide autocomplete, go-to-definition, and diagnostics for coding agents.
RUN bun install -g \
    typescript-language-server \
    bash-language-server \
    dockerfile-language-server-nodejs \
    vscode-langservers-extracted \
    yaml-language-server \
    pyright \
    && rm -rf /usr/local/install/cache /root/.cache /tmp/node-compile-cache /tmp/bunx-*

# Build-time sanity check: fail early if key CLIs are missing.
# Each check is separate so the error message identifies the missing binary.
RUN command -v claude || { echo "ERROR: claude not found"; exit 1; } \
    && command -v codex || { echo "ERROR: codex not found"; exit 1; } \
    && command -v gemini || { echo "ERROR: gemini not found"; exit 1; } \
    && command -v opencode || { echo "ERROR: opencode not found"; exit 1; } \
    && command -v nvim || { echo "ERROR: nvim not found"; exit 1; } \
    && command -v dust || { echo "ERROR: dust not found"; exit 1; } \
    && command -v procs || { echo "ERROR: procs not found"; exit 1; } \
    && command -v btm || { echo "ERROR: btm not found"; exit 1; } \
    && command -v xh || { echo "ERROR: xh not found"; exit 1; } \
    && command -v mcfly || { echo "ERROR: mcfly not found"; exit 1; } \
    && command -v pre-commit || { echo "ERROR: pre-commit not found"; exit 1; } \
    && command -v tldr || { echo "ERROR: tldr not found"; exit 1; } \
    && command -v gitleaks || { echo "ERROR: gitleaks not found"; exit 1; } \
    && command -v hadolint || { echo "ERROR: hadolint not found"; exit 1; } \
    && command -v shellcheck || { echo "ERROR: shellcheck not found"; exit 1; } \
    && command -v uv || { echo "ERROR: uv not found"; exit 1; } \
    && command -v direnv || { echo "ERROR: direnv not found"; exit 1; } \
    && command -v actionlint || { echo "ERROR: actionlint not found"; exit 1; } \
    && command -v trivy || { echo "ERROR: trivy not found"; exit 1; } \
    && command -v yamllint || { echo "ERROR: yamllint not found"; exit 1; } \
    && command -v playwright-cli || { echo "ERROR: playwright-cli not found"; exit 1; } \
    && command -v ps || { echo "ERROR: ps not found"; exit 1; } \
    && command -v pkill || { echo "ERROR: pkill not found"; exit 1; } \
    && command -v typescript-language-server || { echo "ERROR: typescript-language-server not found"; exit 1; } \
    && command -v bash-language-server || { echo "ERROR: bash-language-server not found"; exit 1; } \
    && command -v docker-langserver || { echo "ERROR: docker-langserver not found"; exit 1; } \
    && command -v vscode-json-language-server || { echo "ERROR: vscode-json-language-server not found"; exit 1; } \
    && command -v yaml-language-server || { echo "ERROR: yaml-language-server not found"; exit 1; } \
    && command -v pyright || { echo "ERROR: pyright not found"; exit 1; } \
    && command -v bd || { echo "ERROR: bd (beads) not found"; exit 1; }

# Default dotfiles are copied to /etc/skel.
# start.sh later copies them into user home only when missing.
COPY configs/zshrc /etc/skel/.default.zshrc
COPY configs/zimrc /etc/skel/.default.zimrc
COPY configs/tmux.conf /etc/skel/.default.tmux.conf
COPY configs/vimrc /etc/skel/.default.vimrc
COPY configs/nvim/ /etc/skel/.config/nvim/
COPY configs/starship.toml /etc/skel/.config/starship.toml

# Pre-commit config template for initializing hooks in projects.
COPY configs/pre-commit-config.yaml /etc/skel/.default.pre-commit-config.yaml

# Shared prompt/snippet templates seeded into user home on first run.
COPY configs/templates/ /etc/skel/.agent-sandbox/templates/

# Claude Code slash commands, skills, agents, settings, and MCP server config.
COPY configs/claude/commands/ /etc/skel/.claude/commands/
COPY configs/claude/skills/ /etc/skel/.claude/skills/
COPY configs/claude/agents/ /etc/skel/.claude/agents/
COPY configs/claude/settings.json /etc/skel/.claude/settings.json
COPY configs/claude/mcp.json /etc/skel/.claude/.mcp.json

# Agent-specific settings templates for first-run defaults.
COPY configs/codex/settings.json /etc/skel/.codex/settings.json
COPY configs/gemini/settings.json /etc/skel/.gemini/settings.json
COPY configs/codex/config.toml /etc/skel/.codex/config.toml

# Shared skills bundle (Anthropic skills repo vendored under ./skills).
# start.sh installs these into each agent's user skill directory on startup.
COPY skills/ /opt/agent-sandbox/skills/

# TOOLS.md reference for agents working on other projects.
# .dockerignore needs !TOOLS.md exception (after *.md) to include this file.
COPY TOOLS.md /etc/skel/.config/agent-sandbox/TOOLS.md
# Auto-approve wrapper config for agent CLIs in interactive zsh sessions.
COPY configs/agent-auto-approve.zsh /etc/skel/.config/agent-sandbox/auto-approve.zsh
# Managed default editor env hook (nvim-first).
COPY configs/editor-defaults.zsh /etc/skel/.config/agent-sandbox/editor-defaults.zsh

# Smoke test script for build-time and runtime tool verification.
COPY --chmod=755 scripts/smoke-test.sh /usr/local/bin/smoke-test.sh

# Entry script handles first-run bootstrap, then exec CMD.
COPY --chmod=755 scripts/start.sh /usr/local/bin/start.sh

# Run smoke test during build (--build skips docker socket checks).
RUN /usr/local/bin/smoke-test.sh --build

ENV STARSHIP_CONFIG=/home/sandbox/.config/starship.toml \
    EDITOR=nvim \
    VISUAL=nvim \
    GIT_EDITOR=nvim

# Runtime defaults:
# - run as non-root user
# - work in mounted project path
USER sandbox
WORKDIR /workspace

ENTRYPOINT ["/usr/local/bin/start.sh"]
CMD ["/bin/zsh"]

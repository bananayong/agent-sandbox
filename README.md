# agent-sandbox

> AI 코딩 에이전트를 위한 로컬 Docker 샌드박스  
> 빠르게 띄우고, 안전하게 격리하고, 설정은 계속 유지합니다.

## Why This?

`agent-sandbox`는 Claude Code, Codex CLI, Gemini CLI, OpenCode, Copilot CLI 같은 에이전트를
호스트 환경과 분리된 컨테이너에서 실행하기 위한 개발용 런타임입니다.

- 프로젝트는 `/workspace`로 마운트
- 에이전트 로그인/히스토리/쉘 설정은 컨테이너별 홈(`~/.agent-sandbox/.../home`)에 영구 저장
- Docker socket을 연결해 컨테이너 안에서도 `docker` 명령 사용 가능 (DooD)

## TL;DR (30초 시작)

### 1) 준비물

- Docker Desktop 또는 Docker Engine
- macOS/Linux 쉘 환경

### 2) 실행

```bash
# 현재 폴더를 워크스페이스로 실행
./run.sh .
```

이미지가 없으면 자동으로 빌드하고, 이미 실행 중이면 새 컨테이너를 만들지 않고 바로 attach 합니다.

## Quick Start

```bash
# 이미지 빌드
docker build -t agent-sandbox:latest .

# 현재 폴더 실행
./run.sh .

# 빌드 후 실행
./run.sh -b .

# 특정 프로젝트 폴더 실행
./run.sh ~/projects/myapp

# 컨테이너 이름 지정 (기본 홈도 컨테이너별로 자동 분리)
./run.sh --name codex-main .

# 홈 경로 직접 지정
./run.sh --name codex-main --home ~/.agent-sandbox/team-a/home .

# 컨테이너 중지
./run.sh -s

# 특정 컨테이너 중지
./run.sh -s --name codex-main

# 샌드박스 홈 초기화 (로그인/히스토리/설정 삭제)
./run.sh -r

# 특정 컨테이너 홈만 초기화
./run.sh -r --name codex-main
```

## Runtime Flow

컨테이너 시작 시 `scripts/start.sh`가 자동 실행됩니다.

1. 기본 dotfiles를 `$HOME`으로 복사(첫 실행), agent managed config(`~/.claude/settings.json`, `~/.codex/settings.json`, `~/.gemini/settings.json`)는 diff 출력 후 동기화
2. shared skills, 공용 templates, Claude slash commands/skills/agents를 에이전트 디렉토리에 설치
3. 런타임 안정화 기본값(telemetry/TLS/auto-approve) 적용 + DNS 진단
4. `zimfw` 부트스트랩 및 모듈 설치
5. git delta, 기본 에디터(vim/neovim/micro), gh-copilot, Superpowers/bkit 등 1회성 세팅
6. Docker 소켓 접근성 확인 (마운트되었으나 권한 부족 시 진단 메시지 출력)
7. tmux 세션(`main`) 시작 후 셸 실행 (`TMUX` 내부면 `exec "$@"`로 fallback)

참고: 시작 시 `tldr --update`를 백그라운드에서 timeout/retry(최대 3회)로 시도하며, `InvalidArchive`가 감지되면 tealdeer 캐시를 정리 후 재시도합니다. 실패해도 시작은 계속 진행됩니다.

## Shared Skills (Anthropic)

루트 `skills/` 폴더에는 `https://github.com/anthropics/skills/tree/main/skills`의 스킬이 포함되어 있습니다.

컨테이너 시작 시 `scripts/start.sh`가 아래 경로에 스킬을 자동 설치합니다.

- `~/.claude/skills`
- `~/.codex/skills`
- `~/.gemini/skills`

동작 원칙:

- 같은 이름의 스킬 폴더가 이미 있으면 기본적으로 덮어쓰지 않습니다(사용자 커스텀 보존).
- 아직 없는 스킬만 추가 설치됩니다.
- Codex/Gemini는 내장 스킬 충돌 방지를 위해 `skill-creator`만 자동 설치에서 제외됩니다.
- `playwright-efficient-web-research`는 운영 가이드 일관성을 위해 시작 시 강제 동기화됩니다.
- 현재 벤더링 기준 upstream 정보는 `skills/UPSTREAM.txt`에 기록합니다.

## Playwright CLI 기반 웹 탐색

웹 조사/탐색에서 전체 페이지를 반복 fetch하는 대신, 이 저장소는 `playwright-cli` 기반 워크플로우를 권장합니다.

- 기본 경로: `playwright-cli` + 스킬(`skills/playwright-efficient-web-research`)
- 핵심 원칙: 세션 재사용(`-s=<name>`), `snapshot` ref 기반 조작, `eval`로 필요한 필드만 추출
- 권장 브라우저: `--browser=chromium` (이미지 빌드 시 사전 설치되는 런타임과 일치)
- MCP 사용 시점: 장시간 상태 유지/자율 루프가 필요한 경우만 fallback

예시:

```bash
playwright-cli -s=research open https://example.com --browser=chromium
playwright-cli -s=research snapshot
playwright-cli -s=research eval "() => ({ title: document.title })"
playwright-cli -s=research close
```

## Mount & Persistence

기본 마운트는 아래 3가지입니다.

- `WORKSPACE_DIR` -> `/workspace`
- sandbox home -> `/home/sandbox`
  - 기본 컨테이너(`agent-sandbox`): `~/.agent-sandbox/home`
  - 커스텀 컨테이너(`--name <name>`): `~/.agent-sandbox/<name>/home` (단, `--home` 미지정 시)
- host Docker socket -> `/var/run/docker.sock` (존재 시 자동 연결)

핵심 포인트:

- 컨테이너를 지워도 해당 컨테이너의 sandbox home은 유지됩니다.
- 따라서 CLI 로그인 상태, shell history, 개인 설정이 살아있습니다.

## Shared Templates

공용 템플릿은 이미지 기본값에서 사용자 홈으로 first-run 시 자동 시드됩니다.

- 이미지 기본 경로: `/etc/skel/.agent-sandbox/templates`
- 사용자 경로: `~/.agent-sandbox/templates`
- 설치 정책: 없는 파일만 추가(기존 사용자 파일은 덮어쓰지 않음)

## Agent Settings Templates

에이전트별 `settings.json` 기본값은 `/etc/skel`에 분리 템플릿으로 포함됩니다.

- Claude: `configs/claude/settings.json` -> `/etc/skel/.claude/settings.json` (managed sync)
- Codex: `configs/codex/settings.json` -> `/etc/skel/.codex/settings.json` (managed sync)
- Gemini: `configs/gemini/settings.json` -> `/etc/skel/.gemini/settings.json` (managed sync)

주의: 세 파일 모두 entrypoint에서 managed sync로 유지되므로 기존 사용자 설정이 이미지 기본값으로 덮어써질 수 있습니다(동기화 전 diff 출력).

기본 포함 파일:
- `prompt-template.md`
- `command-checklist.md`
- `config-snippet.md`

## Codex Multi-Agent Defaults

`configs/codex/config.toml` 기본값에 아래 항목이 포함됩니다.

- `[features].multi_agent = true` (실험 기능)
- `[features].undo = true` (작업 복구 편의)
- `[features].apps = true` (ChatGPT Apps/Connectors)
- `[agents].max_threads = 12` (Codex 기본 6에서 상향)

추가로 `start.sh`는 기존 사용자 홈(`~/.codex/config.toml`)에도 아래 키가 비어 있으면 자동 보강합니다.

- `[tui].status_line`
- `[features].multi_agent`
- `[features].undo`
- `[features].apps`
- `[agents].max_threads`

Built-in 에이전트 role:

- `default` (mixed tasks)
- `explorer` (코드베이스 조사/리스크 확인, no edits)
- `worker` (구현/버그 수정/테스트)

예시 프롬프트:

```text
spawn default agent to debug the failure and propose fix
spawn explorer to map payment flow and check risks, no edits
spawn worker for src/auth/* and implement token refresh & run tests
```

커스텀 role은 `config.toml`의 `[agents.<name>]` + 별도 `config_file` 조합으로 추가할 수 있습니다.

## Vim / Neovim Defaults

컨테이너 기본 설정에 `vim`과 `neovim` 추천 플러그인/테마가 포함됩니다.

- 기본 에디터 환경변수: `EDITOR=nvim`, `VISUAL=nvim`, `GIT_EDITOR=nvim`
- Debian `editor` 대안 경로도 `nvim`으로 설정됩니다.

- `vim`:
  - 플러그인 매니저: `vim-plug`
  - 기본 설정 파일: `~/.vimrc` (이미지 기본값: `configs/vimrc`)
  - 포함 플러그인: `fzf`, `nerdtree`, `vim-fugitive`, `vim-gitgutter`, `ale`, `vim-surround`, `vim-commentary` 등
  - 테마 세트: `everforest`(기본), `gruvbox-material`, `dracula`
- `neovim`:
  - 플러그인 매니저: `lazy.nvim`
  - 기본 설정 파일: `~/.config/nvim/init.lua` (이미지 기본값: `configs/nvim/init.lua`)
  - 포함 플러그인: `telescope`, `nvim-treesitter`, `nvim-lspconfig + mason`, `nvim-cmp`, `gitsigns`, `lualine`, `which-key`, `conform` 등
  - 테마 세트: `tokyonight`(기본), `catppuccin`, `kanagawa`, `rose-pine`

첫 실행 후 동기화 명령:

```bash
# vim
vim +PlugInstall +qall

# neovim
nvim --headless "+Lazy! sync" +qa
```

## Environment Variables

`run.sh`와 `docker-compose.yml`은 공통 키를 전달하고, 일부 키는 실행 경로별 전용입니다.
호스트에 설정된 값은 그대로 전달되며, 안정화/보안 성격의 항목은 토글 없이 고정 기본 동작으로 적용됩니다.

**API 키:**
- `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GITHUB_TOKEN`, `OPENCODE_API_KEY`

**프록시 / TLS:**
- `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` (및 소문자/`ALL_PROXY`)
- `SSL_CERT_FILE`, `SSL_CERT_DIR`, `NODE_EXTRA_CA_CERTS`

**런타임 고정 정책 (환경변수 토글 없음):**
- Node TLS 호환 옵션(`--tls-max-v1.2 --tls-min-v1.2 --dns-result-order=ipv4first`)을 항상 적용
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`
- `DISABLE_ERROR_REPORTING=1`
- `DISABLE_TELEMETRY=1`
- `DISABLE_AUTOUPDATER=1`
- Codex/Claude/Gemini/Copilot 자동 승인 wrapper를 항상 활성화

**Claude 기본 튜닝 값:**
- `configs/claude/settings.json`의 managed `env` 블록으로 고정 적용
- (예: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, `ENABLE_TOOL_SEARCH=auto:5`, `CLAUDE_CODE_EFFORT_LEVEL=high`)

**`run.sh` 전용 키:**
- `AGENT_SANDBOX_DNS_SERVERS` — 컨테이너 DNS 서버 목록 (IPv4 권장, 쉼표/공백 구분, 예: `10.0.0.2,1.1.1.1`)
- `AGENT_SANDBOX_MATCH_HOST_USER` — rootless Docker에서 host UID/GID로 컨테이너 실행 (`auto` | `1` | `0`, 기본 `auto`)
- `AGENT_SANDBOX_NET_MTU` — Docker 네트워크 MTU (기본 `1280`)

**`run.sh` 주요 옵션:**
- `--name`, `-n` — 컨테이너 이름 지정 (기본: `agent-sandbox`)
- `--home` — `/home/sandbox`에 마운트할 host 경로 지정

**`docker-compose.yml` 전용 키:**
- `DOCKER_SOCK` — Docker 소켓 경로 오버라이드 (기본 `/var/run/docker.sock`)
- `DOCKER_GID` — Docker 소켓 GID (기본 `0`)

## GitHub Agent Automation

이 저장소는 이슈/PR 자동화와 Claude 전용 워크플로우를 함께 제공합니다.

**Agent 명령 기반 자동화 (`agent:*` 라벨, `/agent ...` 코멘트):**
- `.github/workflows/agent-issue-intake.yml`
- `.github/workflows/agent-issue-worker.yml`
- `.github/workflows/agent-pr-reviewer.yml`

**Claude 전용 자동화 (`@claude` 멘션, Claude 코드리뷰):**
- `.github/workflows/claude.yml`
- `.github/workflows/claude-code-review.yml`

**PR 품질 게이트 (build/lint/smoke):**
- `.github/workflows/pr-build-lint-smoke.yml` (PR 이벤트에서 `shellcheck`, `hadolint`, `actionlint`, Docker build + repo-mode smoke test 실행)

### Required Secrets

- `AGENT_ALLOWED_ACTORS` — 자동화를 허용할 GitHub 로그인 목록 (쉼표 구분, 예: `myid,teammate`)
- `CLAUDE_CODE_OAUTH_TOKEN` — Claude Code OAuth 토큰 (`claude.yml`, `claude-code-review.yml`, `agent:*`의 Claude 경로에서 사용)
- `CODEX_AUTH_JSON_B64` — `~/.codex/auth.json`을 base64로 인코딩한 값 (`agent:*`의 Codex 경로에서 사용)

보안 기본값: `AGENT_ALLOWED_ACTORS`가 비어 있으면 워크플로우는 자동 실행을 거부합니다(fail-closed).

### Secret 등록 예시

```bash
# 1) 자동화 허용 사용자 지정 (본인만 허용하려면 본인 ID만 입력)
gh secret set AGENT_ALLOWED_ACTORS --body "<your-github-login>"

# 2) Claude OAuth 토큰 등록
gh secret set CLAUDE_CODE_OAUTH_TOKEN --body "<claude-oauth-token>"

# 3) Codex 로그인 캐시(auth.json)를 base64로 등록
base64 < ~/.codex/auth.json | tr -d '\n' | gh secret set CODEX_AUTH_JSON_B64
```

### Trigger Rules

- 이슈 자동 작업:
  - 라벨: `agent:auto` + 선택 라벨 `agent:claude` 또는 `agent:codex`
  - 코멘트: `/agent run [claude|codex] [추가 지시사항]`
  - `@claude` 멘션: 이슈 제목/본문 또는 코멘트에 `@claude` 포함 시 자동으로 이슈 해결 및 PR 생성 (`claude.yml`)
- PR 자동 리뷰:
  - 라벨: `agent:review` + 선택 라벨 `agent:claude` 또는 `agent:codex`
  - 코멘트: `/agent review [claude|codex] [추가 지시사항]`
- Claude Code Review 자동 실행:
  - PR 이벤트: `opened`, `synchronize`, `ready_for_review`, `reopened`
  - allowlist에 포함된 actor일 때만 실행 (`claude-code-review.yml`)

### Safety Guards

- allowlist(`AGENT_ALLOWED_ACTORS`)에 포함된 사용자 작성 이벤트에만 반응
- `github-actions[bot]`가 만든 이벤트에는 반응하지 않음
- 이슈/PR 라벨 기반 실행에서도 라벨을 단 사용자까지 allowlist 검증
- PR 리뷰 경로는 foreign fork PR을 기본적으로 스킵해 외부 포크 맥락에서의 자동 실행을 차단
- 외부 액션은 commit SHA로 고정(pin)해 공급망 변동 위험을 줄임
- 이슈 작업 결과(브랜치/PR), 리뷰 코멘트, artifact 업로드는 기본 활성화

## Included Tools (요약)

- Base: Debian bookworm-slim, zsh, tmux, git, python3, node 22, bun
- Dev CLI: gh, docker cli/compose/buildx, jq, ripgrep, fd, fzf, yq, uv
- UX: starship, eza, bat, zoxide, vim, neovim, micro, delta, lazygit, gitui, tokei
- Agents: claude, codex, gemini, opencode

참고: `broot`는 현재 빌드 안정성 이슈로 비활성화되어 있습니다.
추가로 slim 이미지의 man 제외 정책은 유지하되, 핵심 CLI(`curl`,`zsh`,`htop`,`nnn`,`ncdu` 및 바이너리 설치 툴) man 페이지를 선택 설치해 `man` 조회를 보장합니다.

## Security Notes

- 컨테이너는 `sandbox` 사용자(UID/GID 1000)로 동작
- `--security-opt no-new-privileges:true` 적용
- `sudo`에 의존하는 엔트리포인트/런타임 스크립트는 동작하지 않도록 설계됨
- Codex/Claude/Gemini/Copilot 권한 프롬프트 자동 승인 wrapper가 기본 내장되어 있습니다(신뢰된 로컬 개발 샌드박스 전제)
- API 키는 이미지에 bake 하지 않고 환경변수로만 전달
- Git 서명 설정(`allowed_signers`, `user.signingkey`)은 저장소 파일이 아닌 `$HOME` 글로벌 경로(예: `~/.config/git/allowed_signers`)에만 둡니다.

## Troubleshooting

### Docker 명령이 컨테이너 안에서 권한 오류가 날 때

- `run.sh`가 socket GID를 자동으로 `--group-add` 하므로, 일반적으로 재실행으로 해결됩니다.
- 그래도 실패하면 host Docker socket 경로(`DOCKER_HOST` 또는 `/var/run/docker.sock`)를 확인하세요.
- rootless Docker(사용자 소유 소켓, 예: `/run/user/<uid>/docker.sock`)에서는 UID 불일치로 실패할 수 있습니다.
  - `run.sh`는 이 경우 host UID/GID로 자동 실행을 시도합니다.
  - 수동 강제: `AGENT_SANDBOX_MATCH_HOST_USER=1 ./run.sh .`
- host 자체에서 `docker` 명령이 권한 오류라면 먼저 host 권한을 해결해야 합니다.
  - Linux 예: `sudo usermod -aG docker "$USER" && newgrp docker`

### Claude에서 `Unable to connect to API (UND_ERR_SOCKET)`가 날 때

- 가장 먼저 컨테이너를 재시작하세요: `./run.sh -s` 후 `./run.sh .` (커스텀 컨테이너는 같은 `--name` 사용)
- 프록시/VPN 환경이라면 host에 `HTTPS_PROXY`/`HTTP_PROXY`/`NO_PROXY`를 설정한 뒤 다시 실행하세요.
- 사내 CA를 쓰면 host에 `NODE_EXTRA_CA_CERTS` 또는 `SSL_CERT_FILE`을 설정한 뒤 다시 실행하세요.
- DNS 이슈가 의심되면 컨테이너 DNS를 명시하세요.
  - 예: `./run.sh --dns "10.0.0.2,1.1.1.1" .`
  - 또는: `AGENT_SANDBOX_DNS_SERVERS="10.0.0.2,1.1.1.1" ./run.sh .`
- `run.sh`/`docker-compose.yml`은 기본으로 `host.docker.internal` 매핑을 추가하고, 컨테이너 내부 IPv6를 비활성화해 IPv6 경로 지연을 줄입니다.
- `run.sh`는 실행 시 `agent-sandbox-net`을 MTU 1280으로 자동 보정해 TLS 소켓 오류 가능성을 줄입니다.
- `curl`/`node fetch`는 정상인데 Claude만 TLS/소켓 오류가 나면, 이 샌드박스는 이미 텔레메트리 차단 + TLS 호환 옵션을 기본 적용합니다. 먼저 컨테이너 재생성(`./run.sh -s` 후 `./run.sh .`)으로 런타임 옵션 재적용 여부를 확인하세요. 커스텀 컨테이너는 같은 `--name`으로 재생성해야 합니다.

### 설정을 완전히 초기화하고 싶을 때

```bash
./run.sh -r
```

주의: 현재 대상 컨테이너 이름 기준의 sandbox home이 삭제되어 로그인/히스토리/설정이 모두 초기화됩니다.

## Optional: docker compose

`docker-compose.yml`도 포함되어 있어 compose 기반 실행이 가능합니다.
Docker socket, 프록시/TLS 환경변수, MTU 1280 네트워크를 `run.sh`와 동일하게 지원합니다.
rootless Docker를 쓸 때는 아래처럼 host UID/GID와 소켓 경로를 함께 넘기세요.

```bash
# 기본 실행
docker compose up

# Docker socket GID 지정 (Linux에서 권한 오류 시)
DOCKER_GID=$(stat -c '%g' /var/run/docker.sock) docker compose up

# Rootless Docker 예시
HOST_UID=$(id -u) HOST_GID=$(id -g) \
DOCKER_SOCK=/run/user/$(id -u)/docker.sock \
DOCKER_GID=$(stat -c '%g' /run/user/$(id -u)/docker.sock) \
docker compose up
```

다만 `run.sh`는 자동 빌드/attach/socket GID 감지 등 추가 편의 기능이 있어 기본 사용을 권장합니다.

## Project Files

- `run.sh`: 메인 실행/정지/초기화 스크립트
- `docker-compose.yml`: compose 기반 실행 설정
- `Dockerfile`: 런타임 이미지 정의
- `scripts/start.sh`: 컨테이너 시작 시 초기화 로직
- `scripts/update-versions.sh`: pinned 버전 점검/업데이트 도우미
- `skills/`: 공유 스킬 번들(Anthropic skills vendored)
- `skills/UPSTREAM.txt`: 벤더링 기준 upstream repo/path/commit 기록
- `configs/`: 기본 zsh/zim/tmux/starship/vim/nvim 설정
- `configs/templates/`: 공용 프롬프트/커맨드/설정 템플릿 시드 파일
- `CLAUDE.md`: Claude Code 에이전트 가이드
- `AGENTS.md`: 범용 에이전트 작업 규칙
- `TODO.md`: 작업 목록 (모든 에이전트가 공유)
- `MEMORY.md`: 장기 의사결정 기록

## Version Maintenance

고정 버전 점검/갱신은 아래 스크립트로 실행할 수 있습니다.
이 스크립트는 컨테이너 내부 실행을 기본 전제로 합니다.

```bash
# 현재 고정 버전만 출력 (네트워크 없음)
scripts/update-versions.sh scan

# 최신 릴리스/태그와 비교
scripts/update-versions.sh check

# 업데이트 예정 변경만 출력
scripts/update-versions.sh update --dry-run

# 실제 파일 갱신
scripts/update-versions.sh update
```

자동화가 필요하면 GitHub Actions 워크플로우 `.github/workflows/update-pinned-versions.yml`를 사용하세요.
- 매주 월요일 05:17 UTC에 실행되며, Actions 탭에서 `workflow_dispatch`로 수동 실행할 수도 있습니다.
- 내부에서 `bash scripts/update-versions.sh update`를 실행하고 실제 diff가 있을 때만 PR을 생성/업데이트합니다.

## Documentation Convention (주석 원칙)

- Shell script와 Docker 관련 파일은 초보자도 이해할 수 있도록 "왜 필요한지", "어떤 순서로 동작하는지", "권한/보안에 어떤 영향이 있는지"를 주석으로 명확히 남깁니다.
- 기능 수정 시 로직 변경뿐 아니라 관련 주석도 함께 업데이트하는 것을 기본 규칙으로 사용합니다.

## Additional Guide

- 개인/public 저장소 기준 GitHub 자동화 상세 운영 가이드: `GITHUB_AGENT_AUTOMATION_GUIDE.md`

---

빠른 한 줄:

```bash
./run.sh .
```

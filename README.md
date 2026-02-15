# agent-sandbox

> AI 코딩 에이전트를 위한 로컬 Docker 샌드박스  
> 빠르게 띄우고, 안전하게 격리하고, 설정은 계속 유지합니다.

## Why This?

`agent-sandbox`는 Claude Code, Codex CLI, Gemini CLI, OpenCode, Copilot CLI 같은 에이전트를
호스트 환경과 분리된 컨테이너에서 실행하기 위한 개발용 런타임입니다.

- 프로젝트는 `/workspace`로 마운트
- 에이전트 로그인/히스토리/쉘 설정은 `~/.agent-sandbox/home`에 영구 저장
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

# 컨테이너 중지
./run.sh -s

# 샌드박스 홈 초기화 (로그인/히스토리/설정 삭제)
./run.sh -r
```

## Runtime Flow

컨테이너 시작 시 `scripts/start.sh`가 자동 실행됩니다.

1. 첫 실행일 때만 기본 dotfiles를 `$HOME`으로 복사
2. `zimfw` 부트스트랩 및 모듈 설치
3. git delta, 기본 에디터(micro), gh-copilot 등 1회성 세팅
4. Docker 소켓 접근성 확인 (마운트되었으나 권한 부족 시 진단 메시지 출력)
5. `/bin/zsh` 실행

## Mount & Persistence

기본 마운트는 아래 3가지입니다.

- `WORKSPACE_DIR` -> `/workspace`
- `~/.agent-sandbox/home` -> `/home/sandbox`
- host Docker socket -> `/var/run/docker.sock` (존재 시 자동 연결)

핵심 포인트:

- 컨테이너를 지워도 `~/.agent-sandbox/home`은 유지됩니다.
- 따라서 CLI 로그인 상태, shell history, 개인 설정이 살아있습니다.

## Environment Variables

`run.sh`/`docker-compose.yml`은 아래 키가 호스트에 설정되어 있으면 컨테이너로 전달합니다.

**API 키:**
- `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GITHUB_TOKEN`, `OPENCODE_API_KEY`

**프록시 / TLS:**
- `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` (및 소문자/`ALL_PROXY`)
- `SSL_CERT_FILE`, `SSL_CERT_DIR`, `NODE_EXTRA_CA_CERTS`

**샌드박스 설정 (기본값 자동 적용):**
- `AGENT_SANDBOX_NODE_TLS_COMPAT` — Node TLS 호환 모드 (기본 `1`, `0`으로 비활성화)
- `AGENT_SANDBOX_AUTO_APPROVE` — Codex/Claude/Gemini/Copilot 권한 확인 프롬프트 자동 승인 모드 (기본 `1`, `0`으로 비활성화)
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` — Claude 텔레메트리 비활성화 (기본 `1`)
- `DISABLE_ERROR_REPORTING` — 에러 리포팅 비활성화 (기본 `1`)
- `DISABLE_TELEMETRY` — 추가 텔레메트리/메트릭 전송 비활성화 (기본 `1`)
- `DOCKER_SOCK` — Docker 소켓 경로 오버라이드 (docker-compose 전용, 기본 `/var/run/docker.sock`)
- `AGENT_SANDBOX_MATCH_HOST_USER` — rootless Docker에서 host UID/GID로 컨테이너 실행 (`auto` | `1` | `0`, 기본 `auto`)
- `AGENT_SANDBOX_NET_MTU` — Docker 네트워크 MTU (기본 `1280`)
- `DOCKER_GID` — Docker 소켓 GID (docker-compose 전용, 기본 `0`)

## GitHub Agent Automation

이 저장소는 이슈 기반 자동 작업과 PR 리뷰 자동화를 위한 GitHub Actions를 포함합니다.

- `.github/workflows/agent-issue-intake.yml`
- `.github/workflows/agent-issue-worker.yml`
- `.github/workflows/agent-pr-reviewer.yml`

### Required Secrets

- `AGENT_ALLOWED_ACTORS` — 자동화를 허용할 GitHub 로그인 목록 (쉼표 구분, 예: `myid,teammate`)
- `CLAUDE_CODE_OAUTH_TOKEN` — Claude Code OAuth 토큰
- `CODEX_AUTH_JSON_B64` — `~/.codex/auth.json`을 base64로 인코딩한 값

### Optional Secrets (공개 제어)

- `AGENT_AUTO_PUBLISH` — `true`일 때만 이슈 작업 결과를 브랜치/PR로 자동 공개 (기본: 비활성)
- `AGENT_PUBLIC_REVIEW_COMMENT` — `true`일 때만 PR에 상세 리뷰 본문 공개 코멘트 (기본: 비활성)
- `AGENT_PUBLIC_ARTIFACTS` — `true`일 때만 patch/review artifact 업로드 (기본: 비활성)

보안 기본값: `AGENT_ALLOWED_ACTORS`가 비어 있으면 워크플로우는 자동 실행을 거부합니다(fail-closed).

### Secret 등록 예시

```bash
# 1) 자동화 허용 사용자 지정 (본인만 허용하려면 본인 ID만 입력)
gh secret set AGENT_ALLOWED_ACTORS --body "<your-github-login>"

# 2) Claude OAuth 토큰 등록
gh secret set CLAUDE_CODE_OAUTH_TOKEN --body "<claude-oauth-token>"

# 3) Codex 로그인 캐시(auth.json)를 base64로 등록
base64 < ~/.codex/auth.json | tr -d '\n' | gh secret set CODEX_AUTH_JSON_B64

# 4) (선택) 자동 브랜치/PR 공개를 켜려면
gh secret set AGENT_AUTO_PUBLISH --body "true"

# 5) (선택) PR 상세 리뷰 공개 코멘트를 켜려면
gh secret set AGENT_PUBLIC_REVIEW_COMMENT --body "true"

# 6) (선택) patch/review artifact 업로드를 켜려면
gh secret set AGENT_PUBLIC_ARTIFACTS --body "true"
```

### Trigger Rules

- 이슈 자동 작업:
  - 라벨: `agent:auto` + 선택 라벨 `agent:claude` 또는 `agent:codex`
  - 코멘트: `/agent run [claude|codex] [추가 지시사항]`
- PR 자동 리뷰:
  - 라벨: `agent:review` + 선택 라벨 `agent:claude` 또는 `agent:codex`
  - 코멘트: `/agent review [claude|codex] [추가 지시사항]`

### Safety Guards

- allowlist(`AGENT_ALLOWED_ACTORS`)에 포함된 사용자 작성 이벤트에만 반응
- `github-actions[bot]`가 만든 이벤트에는 반응하지 않음
- 이슈/PR 라벨 기반 실행에서도 라벨을 단 사용자까지 allowlist 검증
- 기본값으로 결과 공개를 최소화 (자동 publish/상세 리뷰 코멘트/artifact 업로드 모두 opt-in)

## Included Tools (요약)

- Base: Debian bookworm-slim, zsh, tmux, git, python3, node 22, bun
- Dev CLI: gh, docker cli/compose/buildx, jq, ripgrep, fd, fzf, yq
- UX: starship, eza, bat, zoxide, micro, delta, lazygit, gitui, tokei
- Agents: claude, codex, gemini, opencode

참고: `broot`는 현재 빌드 안정성 이슈로 비활성화되어 있습니다.

## Security Notes

- 컨테이너는 `sandbox` 사용자(UID/GID 1000)로 동작
- `--security-opt no-new-privileges:true` 적용
- `sudo`에 의존하는 엔트리포인트/런타임 스크립트는 동작하지 않도록 설계됨
- 기본값으로 `AGENT_SANDBOX_AUTO_APPROVE=1` (Codex/Claude/Gemini/Copilot 권한 프롬프트 자동 승인). 보수 모드가 필요하면 `AGENT_SANDBOX_AUTO_APPROVE=0`으로 실행
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

- 가장 먼저 컨테이너를 재시작하세요: `./run.sh -s` 후 `./run.sh .`
- 프록시/VPN 환경이라면 host에 `HTTPS_PROXY`/`HTTP_PROXY`/`NO_PROXY`를 설정한 뒤 다시 실행하세요.
- 사내 CA를 쓰면 host에 `NODE_EXTRA_CA_CERTS` 또는 `SSL_CERT_FILE`을 설정한 뒤 다시 실행하세요.
- `run.sh`는 실행 시 `agent-sandbox-net`을 MTU 1280으로 자동 보정해 TLS 소켓 오류 가능성을 줄입니다.
- `curl`/`node fetch`는 정상인데 Claude만 TLS/소켓 오류가 나면 텔레메트리 경로를 함께 끄고 실행해 보세요.
  - 예: `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_ERROR_REPORTING=1 DISABLE_TELEMETRY=1 ./run.sh .`
- 같은 증상에서 Node TLS `bad record mac`가 보이면 TLS 호환 모드를 사용하세요.
  - 기본값: `AGENT_SANDBOX_NODE_TLS_COMPAT=1` (run.sh가 `NODE_OPTIONS=--tls-max-v1.2 --tls-min-v1.2 --dns-result-order=ipv4first` 적용)
  - 비활성화: `AGENT_SANDBOX_NODE_TLS_COMPAT=0 ./run.sh .`

### 설정을 완전히 초기화하고 싶을 때

```bash
./run.sh -r
```

주의: `~/.agent-sandbox/home`이 삭제되어 로그인/히스토리/설정이 모두 초기화됩니다.

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
- `configs/`: 기본 zsh/zim/tmux/starship 설정
- `CLAUDE.md`: Claude Code 에이전트 가이드
- `AGENTS.md`: 범용 에이전트 작업 규칙
- `TODO.md`: 작업 목록 (모든 에이전트가 공유)
- `MEMORY.md`: 장기 의사결정 기록

## Version Maintenance

고정 버전 점검/갱신은 아래 스크립트로 실행할 수 있습니다.

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

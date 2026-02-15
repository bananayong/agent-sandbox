# Agent Sandbox 기능 보강 구현 계획

> 작성일: 2026-02-15
> 상태: 구현 완료
> 근거: TODO.md 백로그 분석 결과, P1/P2 항목 중 영향력 높은 태스크를 선별하여 5개 배치로 구성

## Context

TODO.md에 51개 미완료 태스크가 있고, 현재 zshrc에 alias만 있고 바이너리가 없는 도구들(dust, procs, btm, xh, mcfly)이 있어 실제 사용 시 동작하지 않는 상태. 보안 도구(pre-commit, gitleaks), Claude Code 커스텀 설정(slash commands, skills, MCP), 개발 도구(direnv, hadolint, shellcheck) 등이 누락되어 있음. 이 계획은 P1/P2 태스크 중 가장 영향력 있는 항목들을 구현함.

---

## Batch 1: 미설치 도구 바이너리 추가 (P1)

> TODO 항목: `zshrc에 alias된 미설치 도구 추가 — dust, procs, btm, xh, mcfly 바이너리 설치`

zshrc에 alias가 있지만 바이너리가 없는 5개 도구를 Dockerfile에 추가.

**수정 파일:** `Dockerfile`

| 도구 | 용도 | 설치 방식 |
|------|------|-----------|
| dust | du 대체 (디스크 사용량) | GitHub release tar.gz |
| procs | ps 대체 (프로세스 목록) | GitHub release zip |
| bottom (btm) | top 대체 (시스템 모니터) | GitHub release tar.gz |
| xh | curl 대체 (HTTP 클라이언트) | GitHub release tar.gz (musl) |
| mcfly | 스마트 셸 히스토리 (Ctrl+R) | GitHub release tar.gz (musl) |

### 변경사항

1. 기존 ARG 블록(line 57-68)에 5개 버전 ARG 추가:

```dockerfile
ARG DUST_VERSION=1.2.4
ARG PROCS_VERSION=0.14.10
ARG BOTTOM_VERSION=0.12.3
ARG XH_VERSION=0.25.3
ARG MCFLY_VERSION=0.9.4
```

2. 기존 delta 설치(line 165) 뒤에 5개 RUN 블록 추가:

```dockerfile
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
```

3. 기존 build-time sanity check(line 193-196)에 5개 도구 검증 추가:

```dockerfile
    && command -v dust || { echo "ERROR: dust not found"; exit 1; } \
    && command -v procs || { echo "ERROR: procs not found"; exit 1; } \
    && command -v btm || { echo "ERROR: btm not found"; exit 1; } \
    && command -v xh || { echo "ERROR: xh not found"; exit 1; } \
    && command -v mcfly || { echo "ERROR: mcfly not found"; exit 1; }
```

### 주의사항

- `procs`는 `.zip` 형식 사용 (unzip은 이미 apt에서 설치됨)
- `bottom` 릴리스 태그에 `v` 접두어 없음 (`0.12.3`, not `v0.12.3`)
- `xh`와 `mcfly`는 Linux에서 `musl` 빌드만 제공 (bookworm에서 정상 동작)
- `dust` tar.gz는 중첩 디렉토리 구조이므로 `--strip-components=1` 필요

---

## Batch 2: 보안 도구 — pre-commit + gitleaks + lint (P1+P2)

> TODO 항목: `커밋 전 보안 민감 정보 유출 방지 장치 도입`, `pre-commit 프레임워크 자동 구성`, `Dockerfile/shell script lint 및 검증 도구 도입`

**수정 파일:** `Dockerfile`, `scripts/start.sh`
**신규 파일:** `configs/pre-commit-config.yaml`

### 2a. 도구 설치 (Dockerfile)

| 도구 | 용도 | 설치 방식 | 크기 |
|------|------|-----------|------|
| shellcheck | 셸 스크립트 린터 | apt (기존 apt 블록에 추가) | ~3MB |
| pre-commit | 코드 품질 hook 프레임워크 | `pip3 install --break-system-packages` | ~30MB |
| gitleaks | Git 커밋 내 비밀 정보 탐지 | GitHub release tar.gz | ~7MB |
| hadolint | Dockerfile 린터 | GitHub release 단일 바이너리 | ~5MB |

```dockerfile
# shellcheck — 기존 apt-get install 블록(line 11-21)에 추가
# ... shellcheck \

# pre-commit
RUN pip3 install --break-system-packages pre-commit

# gitleaks
ARG GITLEAKS_VERSION=8.30.0
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then GL_ARCH="arm64"; else GL_ARCH="x64"; fi \
    && curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GL_ARCH}.tar.gz" \
    | tar -xz -C /usr/local/bin/ gitleaks

# hadolint
ARG HADOLINT_VERSION=2.14.0
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then HL_ARCH="arm64"; else HL_ARCH="x86_64"; fi \
    && curl -fsSL "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-${HL_ARCH}" -o /usr/local/bin/hadolint \
    && chmod +x /usr/local/bin/hadolint
```

### 2b. pre-commit 설정 템플릿 (신규 파일)

`configs/pre-commit-config.yaml`:

```yaml
# Default pre-commit hooks for agent-sandbox projects.
# Copy to your project root as .pre-commit-config.yaml
# Run: pre-commit install
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: trailing-whitespace
      - id: end-of-file-fixer
      - id: check-yaml
      - id: check-json
      - id: check-merge-conflict
      - id: check-added-large-files
        args: ['--maxkb=500']

  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.30.0
    hooks:
      - id: gitleaks

  - repo: https://github.com/shellcheck-py/shellcheck-py
    rev: v0.9.0.6
    hooks:
      - id: shellcheck

  - repo: https://github.com/hadolint/hadolint
    rev: v2.14.0
    hooks:
      - id: hadolint-docker
```

### 2c. 배포 (Dockerfile + start.sh)

Dockerfile:
```dockerfile
COPY configs/pre-commit-config.yaml /etc/skel/.default.pre-commit-config.yaml
```

start.sh (기존 copy_default 패턴 사용):
```bash
copy_default /etc/skel/.default.pre-commit-config.yaml "$HOME_DIR/.pre-commit-config.yaml.template"
```

워크스페이스가 아닌 홈 디렉토리에 `.template` 확장자로 배치. 사용자가 프로젝트에 직접 복사하여 사용.

### 주의사항

- Debian bookworm은 PEP 668을 적용하므로 `--break-system-packages` 필요 (컨테이너이므로 안전)
- gitleaks의 x86_64 아키텍처 이름은 `x64` (다른 도구들과 다름)

---

## Batch 3: Claude Code 설정 — Slash Commands + Skills + MCP (P1)

> TODO 항목: `Claude Code custom slash commands 자동 구성`, `Claude skills 자동 구성`, `유용한 스킬 만들기`, `MCP 서버 설정 자동 구성`

**수정 파일:** `Dockerfile`, `scripts/start.sh`
**신규 파일:** 6개 (아래 참조)

### 3a. Slash Commands

`configs/claude/commands/commit.md`:
```markdown
---
description: Create a well-formatted git commit with conventional commit style
---
Review all staged changes (git diff --cached) and unstaged changes (git diff).
Create a conventional commit message following this format:
- type(scope): description
- Types: feat, fix, docs, style, refactor, test, chore, build, ci, perf
- Keep the first line under 72 characters
- Add a body if the change needs explanation

Stage appropriate files and create the commit. Ask me to confirm before committing.
```

`configs/claude/commands/review.md`:
```markdown
---
description: Review code changes and provide feedback
---
Review the current changes in this repository:
1. Run `git diff` to see unstaged changes
2. Run `git diff --cached` to see staged changes
3. If on a branch, run `git log --oneline main..HEAD` to see all branch commits

Analyze for:
- Bugs or logic errors
- Security issues (hardcoded secrets, injection risks)
- Performance concerns
- Code style and readability
- Missing error handling
- Test coverage gaps

Provide specific, actionable feedback organized by severity (critical, warning, suggestion).
```

`configs/claude/commands/test.md`:
```markdown
---
description: Discover and run the project's test suite
---
Detect the project's test framework by checking for:
- package.json (npm test, jest, vitest, mocha)
- pytest.ini / pyproject.toml / setup.cfg (pytest)
- Cargo.toml (cargo test)
- go.mod (go test ./...)
- Makefile (make test)

Run the appropriate test command and analyze results.
If tests fail, provide a summary of failures with suggested fixes.
```

`configs/claude/commands/debug.md`:
```markdown
---
description: Systematically debug an error or issue
argument-hint: [error message or description]
---
Debug the issue: $ARGUMENTS

Steps:
1. Reproduce: identify the exact error and its context
2. Locate: find the relevant source files and the failing code path
3. Analyze: determine root cause by reading the code and any stack traces
4. Fix: propose a minimal, targeted fix
5. Verify: explain how to test that the fix works

Be systematic. Show your reasoning at each step.
```

### 3b. Skills

`configs/claude/skills/sandbox-setup/SKILL.md`:
````markdown
---
name: sandbox-setup
description: Set up and configure the agent-sandbox development environment
---

# Agent Sandbox Setup

This skill helps configure the agent-sandbox Docker development environment.

## Available Tools
The sandbox includes: bat, eza, fd, dust, procs, btm, xh, mcfly, fzf, zoxide, starship, micro, lazygit, gitui, tokei, yq, delta, gping, duf, ripgrep, jq, tmux, pre-commit, gitleaks, hadolint, shellcheck.

## Common Tasks

### Initialize pre-commit in a project
```bash
cp ~/.pre-commit-config.yaml.template .pre-commit-config.yaml
pre-commit install
pre-commit run --all-files
```

### Check Docker access
```bash
docker version
docker compose version
```

### Verify tool availability
```bash
for tool in claude codex gemini opencode bat eza fd dust procs btm xh mcfly fzf delta rg jq yq; do
  command -v "$tool" && echo "OK: $tool" || echo "MISSING: $tool"
done
```
````

### 3c. MCP 서버 설정

`configs/claude/mcp.json`:
```json
{
  "mcpServers": {
    "filesystem": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
    }
  }
}
```

### 3d. 배포 (Dockerfile + start.sh)

Dockerfile:
```dockerfile
COPY configs/claude/commands/ /etc/skel/.claude/commands/
COPY configs/claude/skills/ /etc/skel/.claude/skills/
COPY configs/claude/mcp.json /etc/skel/.claude/.mcp.json
# TOOLS.md는 .dockerignore의 *.md에 의해 제외되므로 !TOOLS.md 예외 추가 필요.
COPY TOOLS.md /etc/skel/.config/agent-sandbox/TOOLS.md
```

`.dockerignore`에 예외 추가 (`*.md` 규칙 바로 뒤에 배치해야 override가 적용됨):
```
*.md
!TOOLS.md
```

start.sh (디렉토리 단위 복사):
```bash
# Copy Claude Code slash commands if the commands directory is empty/missing.
if [[ ! -d "$HOME_DIR/.claude/commands" ]] || [[ -z "$(ls -A "$HOME_DIR/.claude/commands" 2>/dev/null)" ]]; then
  echo "[init] Installing Claude Code slash commands..."
  mkdir -p "$HOME_DIR/.claude/commands"
  cp -r /etc/skel/.claude/commands/* "$HOME_DIR/.claude/commands/" 2>/dev/null || true
fi

# Copy Claude Code skills if the skills directory is empty/missing.
if [[ ! -d "$HOME_DIR/.claude/skills" ]] || [[ -z "$(ls -A "$HOME_DIR/.claude/skills" 2>/dev/null)" ]]; then
  echo "[init] Installing Claude Code skills..."
  mkdir -p "$HOME_DIR/.claude/skills"
  cp -r /etc/skel/.claude/skills/* "$HOME_DIR/.claude/skills/" 2>/dev/null || true
fi

# Copy MCP server config template if not already present.
copy_default /etc/skel/.claude/.mcp.json "$HOME_DIR/.claude/.mcp.json"

# Copy TOOLS.md to user home so agents can reference available tools
# even when working on projects other than agent-sandbox itself.
copy_default /etc/skel/.config/agent-sandbox/TOOLS.md "$HOME_DIR/.config/agent-sandbox/TOOLS.md"
```

### 주의사항

- `.dockerignore`의 `*.md`는 루트 레벨만 매치하므로 `configs/claude/commands/*.md`는 빌드 컨텍스트에 포함됨
- `.dockerignore`의 `.claude`는 리포지토리 루트의 `.claude/`만 제외하며 `configs/claude/`는 영향 없음

---

## Batch 4: 개발 도구 — direnv + smoke test (P2)

> TODO 항목: `direnv 설치`, `이미지 빌드 smoke test`

**수정 파일:** `Dockerfile`, `configs/zshrc`
**신규 파일:** `scripts/smoke-test.sh`

### 4a. direnv 설치

Dockerfile:
```dockerfile
ARG DIRENV_VERSION=2.37.1

# Install direnv (auto-load .envrc per-directory environment variables).
RUN ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then DIRENV_ARCH="arm64"; else DIRENV_ARCH="amd64"; fi \
    && curl -fsSL "https://github.com/direnv/direnv/releases/download/v${DIRENV_VERSION}/direnv.linux-${DIRENV_ARCH}" -o /usr/local/bin/direnv \
    && chmod +x /usr/local/bin/direnv
```

zshrc (zoxide 블록 뒤에 추가):
```bash
# direnv (auto-load .envrc per-directory env vars)
if command -v direnv &>/dev/null; then
  eval "$(direnv hook zsh)"
fi
```

### 4b. 빌드 smoke test 스크립트

`scripts/smoke-test.sh`:
```bash
#!/bin/bash
set -euo pipefail

# Build smoke test: verify key tools are present and runnable.
# Run after docker build to catch missing or broken binaries.
#
# Usage:
#   smoke-test.sh              # full test (runtime)
#   smoke-test.sh --build      # skip docker/socket-dependent checks (build time)

FAILED=0
SKIP_DOCKER=false
if [[ "${1:-}" == "--build" ]]; then
  SKIP_DOCKER=true
fi

check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  OK   $name"
  else
    echo "  FAIL $name ($*)"
    FAILED=1
  fi
}

echo "=== Agent Sandbox Smoke Test ==="
echo ""
echo "--- Coding Agents ---"
check "claude"    claude --version
check "codex"     codex --version
check "gemini"    gemini --version
check "opencode"  opencode --version

echo ""
echo "--- Core Tools ---"
check "git"       git --version
if [[ "$SKIP_DOCKER" == false ]]; then
  check "docker"  docker --version
fi
check "gh"        gh --version
check "node"      node --version
check "bun"       bun --version
check "python3"   python3 --version

echo ""
echo "--- Shell Tools ---"
check "bat"       bat --version
check "eza"       eza --version
check "fd"        fd --version
check "fzf"       fzf --version
check "rg"        rg --version
check "dust"      dust --version
check "procs"     procs --version
check "btm"       btm --version
check "xh"        xh --version
check "mcfly"     mcfly --version
check "zoxide"    zoxide --version
check "starship"  starship --version
check "micro"     micro --version
check "delta"     delta --version
check "lazygit"   lazygit --version
check "gitui"     gitui --version
check "tokei"     tokei --version
check "yq"        yq --version
check "jq"        jq --version
check "tmux"      tmux -V
check "direnv"    direnv version

echo ""
echo "--- Security/Quality Tools ---"
check "pre-commit"  pre-commit --version
check "gitleaks"    gitleaks version
check "hadolint"    hadolint --version
check "shellcheck"  shellcheck --version

echo ""
if [ "$FAILED" -eq 0 ]; then
  echo "All checks passed!"
else
  echo "Some checks FAILED. See above."
  exit 1
fi
```

Dockerfile:
```dockerfile
COPY scripts/smoke-test.sh /usr/local/bin/smoke-test.sh
RUN chmod +x /usr/local/bin/smoke-test.sh

# Run smoke test during build with --build flag to skip docker socket checks.
RUN /usr/local/bin/smoke-test.sh --build
```

### 주의사항

- `--build` 플래그로 빌드 시 docker 소켓 의존 체크를 스킵하여 불필요한 WARNING 노이즈 방지
- 런타임에서는 플래그 없이 `smoke-test.sh`를 실행하면 docker 포함 전체 체크 수행

---

## Batch 5: GitHub Actions 자동화 (P1)

> TODO 항목: `GitHub Issues 기반 자동 작업 환경 구축`

**신규 파일:** `.github/workflows/claude.yml`

```yaml
name: Claude Code Assistant

on:
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [opened, assigned, labeled]
  pull_request_review:
    types: [submitted]

jobs:
  claude:
    if: |
      (github.event_name == 'issue_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review_comment' && contains(github.event.comment.body, '@claude')) ||
      (github.event_name == 'pull_request_review' && contains(github.event.review.body, '@claude')) ||
      (github.event_name == 'issues' && contains(github.event.issue.labels.*.name, 'claude'))
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
      issues: write
    steps:
      - name: Run Claude Code
        uses: anthropics/claude-code-action@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
```

### 주의사항

- `ANTHROPIC_API_KEY`를 GitHub repository secrets에 등록 필요
- `.dockerignore`에서 `.github` 제외 대상이므로 Docker 이미지에 포함되지 않음 (의도된 동작)

---

## 구현 순서

```
Batch 1 (미설치 바이너리)  ← 의존성 없음, 먼저 실행
    ↓
Batch 2 (보안 도구)        ← Batch 1 완료 후
    ↓
Batch 3 (Claude 설정)      ← Batch 2와 병렬 가능
    ↓
Batch 4 (direnv + smoke)   ← Batch 1+2 완료 후 (smoke test에 전체 도구 포함)
    ↓
Batch 5 (GH Actions)       ← 독립적, 마지막에 실행
```

---

## 수정/생성 파일 전체 목록

| 파일 | 작업 | Batch |
|------|------|-------|
| `Dockerfile` | 수정: 도구 설치, COPY 추가, shellcheck apt 추가, smoke test | 1,2,3,4 |
| `scripts/start.sh` | 수정: Claude commands/skills/mcp, pre-commit 템플릿 복사 로직 | 2,3 |
| `configs/zshrc` | 수정: direnv hook 추가 | 4 |
| `configs/pre-commit-config.yaml` | 신규 | 2 |
| `configs/claude/commands/commit.md` | 신규 | 3 |
| `configs/claude/commands/review.md` | 신규 | 3 |
| `configs/claude/commands/test.md` | 신규 | 3 |
| `configs/claude/commands/debug.md` | 신규 | 3 |
| `configs/claude/skills/sandbox-setup/SKILL.md` | 신규 | 3 |
| `configs/claude/mcp.json` | 신규 | 3 |
| `scripts/smoke-test.sh` | 신규 | 4 |
| `.github/workflows/claude.yml` | 신규 | 5 |
| `TOOLS.md` | 수정: 컨테이너 내부 배포용 COPY 추가 | 3 |
| `TODO.md` | 수정: 완료 항목 체크 | 전체 완료 후 |
| `MEMORY.md` | 수정: 결정 기록 추가 | 전체 완료 후 |

---

## 이미지 크기 영향

| 추가 항목 | 크기 |
|-----------|------|
| dust, procs, btm, xh, mcfly | ~11 MB |
| pre-commit + Python deps | ~30 MB |
| gitleaks | ~7 MB |
| hadolint | ~5 MB |
| shellcheck (apt) | ~3 MB |
| direnv | ~7 MB |
| 설정 파일들 | <1 MB |
| **합계** | **~63 MB** |

---

## 이번에 명시적으로 제외하는 항목

- **Agent helper tools (speckit, superpowers, beads)** — 안정성 미확인, 별도 조사 필요
- **Image size optimization** — 도구 추가 완료 후 별도 작업
- **Agent-specific config templates (.codex/, .gemini/)** — 낮은 우선순위
- **run.sh --status** — 핵심 기능이 아님
- **Container healthcheck** — compose 배포 시 추가
- **.env file support** — 이미 환경변수 전달 동작 중
- **Starship prompt / Claude statusline** — 외형 개선, 낮은 우선순위
- **P3 전체** — CI, dry-run, 취약점 스캔, 커스터마이징 가이드, tldr 수정

---

## 검증 방법

1. `docker build -t agent-sandbox:latest .` — 빌드 성공 확인
2. 빌드 중 smoke test 자동 실행 (docker 관련 체크 제외)
3. 컨테이너 실행 후 수동 검증:
   ```bash
   # Batch 1 — 바이너리 동작 확인
   dust --version && procs --version && btm --version && xh --version && mcfly --version

   # Batch 2 — 보안 도구 확인
   pre-commit --version && gitleaks version && hadolint --version && shellcheck --version
   cat ~/.pre-commit-config.yaml.template

   # Batch 3 — Claude 설정 확인
   ls ~/.claude/commands/
   ls ~/.claude/skills/
   cat ~/.claude/.mcp.json
   cat ~/.config/agent-sandbox/TOOLS.md | head -5

   # Batch 4 — direnv 확인
   direnv version

   # Batch 5 — GH Actions 파일 확인
   cat .github/workflows/claude.yml
   ```

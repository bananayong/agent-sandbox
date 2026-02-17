# TOOLS.md

이 문서는 Agent Sandbox 컨테이너에 설치된 모든 도구의 목록, 설명, 주요 사용법을 정리한다.
코딩 에이전트(Claude Code, Codex CLI, Gemini CLI, OpenCode)는 이 파일을 참조하여 활용 가능한 도구를 파악할 수 있다.

> **참고:** 이 파일은 리포지토리 루트에 있으므로 agent-sandbox 프로젝트 자체를 /workspace에 마운트할 때만 보인다.
> 다른 프로젝트 작업 시에도 에이전트가 도구 목록을 인지하도록 하려면, 컨테이너 내부의
> `~/.config/agent-sandbox/TOOLS.md`에 복사본이 배치된다 (start.sh first-run 시 자동 복사).

---

## Coding Agents

| 도구 | 명령어 | 설명 |
|------|--------|------|
| Claude Code | `claude` | Anthropic의 AI 코딩 에이전트 CLI |
| Codex CLI | `codex` | OpenAI의 AI 코딩 에이전트 CLI |
| Gemini CLI | `gemini` | Google의 AI 코딩 에이전트 CLI |
| OpenCode | `opencode` | 오픈소스 AI 코딩 에이전트 CLI |
| Oh My OpenCode | `oh-my-opencode` | OpenCode 셸 프레임워크/플러그인 |

```bash
# Claude Code — 현재 디렉토리에서 대화형 세션 시작
claude

# Claude Code — 단일 프롬프트 실행
claude -p "이 프로젝트의 구조를 설명해줘"

# Claude Code — 파이프로 입력 전달
git diff | claude -p "이 변경사항을 리뷰해줘"

# Codex — 대화형 세션
codex

# Gemini — 대화형 세션
gemini
```

---

## Agent Productivity Tools

코딩 에이전트의 생산성을 높이는 보조 도구들이다.

### beads (bd) — Git-native 이슈/태스크 트래커

```bash
# 프로젝트에 beads 초기화
bd init

# 태스크 생성
bd create --title "기능 구현" --type task --priority P2

# 태스크 목록 확인
bd list

# 준비된 작업 자동 탐지 (우선순위 기반)
bd ready --json

# 작업 할당 (원자적, race condition 방지)
bd claim <bead-id>

# 오래된 이슈 요약으로 컨텍스트 압축
bd compact
```

> git-native 태스크 관리 시스템. `.beads/` 디렉토리에 저장되어 git으로 추적되므로 모든 에이전트(Claude, Codex, Gemini 등)가 CLI로 공유할 수 있다. 에픽→태스크→서브태스크 계층 구조, P0-P4 우선순위, 의존성 DAG를 지원한다.

### superpowers — 에이전트 스킬 플러그인 (기설치)

```bash
# Claude Code에서 사용 가능한 스킬 확인 (대화형 세션 내에서)
# TDD, 코드리뷰, 디버깅, 브레인스토밍 등의 구조화된 워크플로우 제공
```

> obra/superpowers 플러그인. Claude Code 마켓플레이스와 Codex git clone 방식으로 설치되어 있다.

### bkit — Vibecoding Kit (Claude Code 전용)

```bash
# Claude Code 대화형 세션 내에서 PDCA 방법론 기반 개발 워크플로우 사용
# Plan-Do-Check-Act 사이클, 16 전문 에이전트, Gap Analysis 등
```

> popup-studio-ai/bkit-claude-code 소스를 통해 설치되는 플러그인(`bkit@bkit-marketplace`). PDCA(Plan-Do-Check-Act) 방법론 프레임워크로, 자동 Gap Analysis 및 Fix 사이클을 제공한다. Claude Code 전용.

---

## Version Control

### git — 분산 버전 관리

```bash
# 상태 확인
git status

# 변경사항 보기 (delta가 기본 pager로 설정됨 — side-by-side diff)
git diff

# 브랜치 생성 및 전환
git switch -c feature/my-feature

# 커밋 로그 (그래프 형태)
git log --oneline --graph --decorate

# stash로 임시 저장
git stash && git stash pop
```

### git-lfs — 대용량 파일 관리

```bash
# LFS 추적 설정
git lfs track "*.psd"

# 추적 중인 파일 확인
git lfs ls-files
```

### gh — GitHub CLI

```bash
# 인증
gh auth login

# PR 생성
gh pr create --title "feat: add feature" --body "설명"

# 이슈 목록
gh issue list

# 이슈 생성
gh issue create --title "버그 리포트" --body "설명"

# PR 리뷰
gh pr review --approve

# 리포지토리 클론
gh repo clone owner/repo

# GitHub Copilot CLI (gh 확장)
gh copilot suggest "find large files in git history"
gh copilot explain "git rebase -i HEAD~3"
```

### lazygit — 터미널 Git UI

```bash
# 현재 리포에서 실행
lazygit

# 특정 경로에서 실행
lazygit -p /path/to/repo
```

> 키보드로 stage/commit/push/rebase 등을 직관적으로 수행할 수 있다. `?`로 단축키 도움말 확인.

### gitui — 경량 터미널 Git UI

```bash
# 현재 리포에서 실행
gitui
```

> lazygit보다 가볍고 빠르다. 간단한 stage/commit 작업에 적합.

### delta — Git diff 하이라이터

```bash
# git diff에서 자동 적용 (기본 pager로 설정됨)
git diff
git log -p

# 두 파일 비교
delta file_a.txt file_b.txt
```

> side-by-side, line-numbers 모드가 기본 활성화되어 있다.

---

## Docker

### docker — 컨테이너 관리 (DooD)

호스트 Docker 소켓을 마운트하여 호스트의 Docker 엔진을 사용한다.

```bash
# 컨테이너 목록
docker ps

# 이미지 빌드
docker build -t myapp .

# 컨테이너 실행
docker run -it --rm myapp

# 로그 확인
docker logs -f container_name
```

### docker compose — 멀티 컨테이너 오케스트레이션

```bash
# 서비스 시작
docker compose up -d

# 서비스 중지 및 정리
docker compose down

# 로그 확인
docker compose logs -f
```

### docker buildx — 멀티 플랫폼 빌드

```bash
# 멀티 아키텍처 빌드
docker buildx build --platform linux/amd64,linux/arm64 -t myapp .
```

---

## File & Search

### bat — cat 대체 (구문 강조)

```bash
# 파일 보기 (구문 강조 + 줄 번호)
bat src/main.py

# 일반 텍스트 모드 (장식 없이)
bat --plain file.txt

# 특정 줄 범위
bat --line-range 10:20 file.py

# 여러 파일 비교
bat file_a.py file_b.py
```

> `cat` 명령이 `bat --paging=never`로 alias되어 있다.

### eza — ls 대체 (아이콘 + 트리)

```bash
# 기본 목록 (아이콘 포함)
eza --icons

# 상세 목록
eza -la --icons --group-directories-first

# 트리 구조 (2레벨)
eza --tree --level=2

# Git 상태 표시
eza -la --git
```

> `ls`, `ll`, `lt`, `la` 명령이 eza alias로 설정되어 있다.

### fd — find 대체 (빠른 파일 검색)

```bash
# 파일 이름으로 검색
fd "main.py"

# 확장자로 검색
fd -e ts

# 숨김 파일 포함
fd -H ".env"

# 특정 디렉토리에서 검색
fd "test" src/

# 검색 결과로 명령 실행
fd -e log -x rm {}
```

> `find` 명령이 `fd`로 alias되어 있다. fzf의 기본 검색 백엔드로도 사용된다.

### ripgrep (rg) — grep 대체 (빠른 텍스트 검색)

```bash
# 텍스트 검색
rg "TODO"

# 특정 파일 타입에서 검색
rg "function" -t js

# 대소문자 무시
rg -i "error"

# 컨텍스트 라인 포함 (앞뒤 3줄)
rg -C 3 "panic"

# 파일 이름만 출력
rg -l "import"

# 특정 디렉토리 제외
rg "api" --glob '!node_modules'

# 정규식 검색
rg "fn\s+\w+\(" -t rust
```

### fzf — 퍼지 파인더

```bash
# 파일 퍼지 검색
fzf

# 명령 출력을 퍼지 필터링
git branch | fzf

# 미리보기 포함
fzf --preview 'bat --color=always {}'

# 파일 선택 후 편집
micro $(fzf)
```

> 셸에서 `Ctrl+T`(파일 검색), `Alt+C`(디렉토리 이동)으로 사용 가능.

### nnn — 터미널 파일 매니저

```bash
# 현재 디렉토리에서 실행
nnn

# 자세한 모드
nnn -d

# 숨김 파일 표시
nnn -H
```

> 가볍고 빠른 파일 매니저. `q`로 종료.

---

## Text Editor

### micro — 터미널 텍스트 에디터

```bash
# 파일 편집
micro file.py

# 새 파일 생성
micro newfile.txt
```

> 기본 Git 에디터로 설정되어 있다. `Ctrl+S` 저장, `Ctrl+Q` 종료. 마우스 지원, 구문 강조 내장.

---

## System Monitoring

### htop — 인터랙티브 프로세스 모니터

```bash
# 실행
htop

# 특정 사용자 프로세스만
htop -u sandbox
```

> `F5` 트리 보기, `F6` 정렬 변경, `F9` 프로세스 종료.

### ncdu — 디스크 사용량 분석

```bash
# 현재 디렉토리 분석
ncdu

# 특정 디렉토리 분석
ncdu /workspace

# 결과를 파일로 내보내기 (ncdu 자체 형식)
ncdu -o report.ncdu /workspace
```

> 용량이 큰 디렉토리/파일을 빠르게 찾을 수 있다. `d`로 삭제 가능.

### duf — 디스크 여유 공간 확인

```bash
# 전체 디스크 상태
duf

# 특정 마운트만 표시
duf /workspace
```

> `df`보다 보기 좋은 테이블 형태로 마운트별 사용량을 보여준다.

---

## Data Processing

### jq — JSON 프로세서

```bash
# JSON 포맷팅
cat data.json | jq .

# 특정 필드 추출
jq '.name' package.json

# 배열 필터링
jq '.items[] | select(.status == "active")' data.json

# 키 목록 추출
jq 'keys' data.json

# 여러 필드를 새 객체로 매핑
jq '.[] | {name: .name, version: .version}' packages.json
```

### yq — YAML 프로세서

```bash
# YAML 읽기
yq '.services' docker-compose.yml

# 값 수정
yq -i '.version = "2.0"' config.yaml

# YAML → JSON 변환
yq -o json config.yaml

# JSON → YAML 변환
yq -P config.json
```

### tokei — 코드 통계

```bash
# 프로젝트 코드 통계
tokei

# 특정 디렉토리
tokei src/

# 특정 언어만
tokei -t Python,JavaScript
```

> 언어별 파일 수, 코드 줄 수, 주석 줄 수, 빈 줄 수를 요약해준다.

---

## Shell & Terminal

### zsh + zimfw — 셸 환경

```bash
# 설치된 zim 모듈 확인
zimfw list

# 모듈 업데이트
zimfw update

# 캐시 재빌드
zimfw compile
```

> 자동완성, 구문 강조, 히스토리 검색(substring-search), 자동제안이 기본 활성화되어 있다.

### tmux — 터미널 멀티플렉서

```bash
# 새 세션 시작
tmux new -s work

# 세션 목록
tmux ls

# 세션 연결
tmux attach -t work

# 세션 분리: Ctrl+A, d
```

> 프리픽스는 `Ctrl+A`. 패널 분할: `|`(가로), `-`(세로). Alt+화살표로 패널 이동.

### starship — 셸 프롬프트

```bash
# 현재 설정 확인
starship config

# 사용 가능한 모듈 목록
starship module --list
```

> 디렉토리, Git 브랜치/상태, 언어 버전, 명령 실행 시간을 표시한다.

### zoxide — 스마트 디렉토리 이동

```bash
# 자주 가는 디렉토리로 점프
z workspace

# 부분 매칭
z proj

# 대화형 선택 (fzf 연동)
zi
```

> `cd` 대신 `z`를 사용하면 방문 기록 기반으로 빠르게 이동한다.

### tealdeer (tldr) — 명령어 사용법 요약

```bash
# 명령어 사용법
tldr tar
tldr git-rebase
tldr docker-run
```

> man page보다 간결하고 실용적인 예제 중심 도움말.

---

## Networking

### curl — HTTP 클라이언트

```bash
# GET 요청
curl https://api.example.com/data

# POST JSON
curl -X POST -H "Content-Type: application/json" \
  -d '{"key":"value"}' https://api.example.com/data

# 응답 헤더 포함
curl -i https://example.com

# 파일 다운로드
curl -fsSL -o file.tar.gz https://example.com/file.tar.gz
```

### wget — 파일 다운로드

```bash
# 파일 다운로드
wget https://example.com/file.zip

# 재귀 다운로드
wget -r -l 1 https://example.com/docs/
```

### dnsutils — DNS 진단

```bash
# DNS 조회
dig example.com

# 간단한 조회
nslookup example.com

# 특정 DNS 서버 사용
dig @8.8.8.8 example.com
```

### gping — 그래프 ping

```bash
# 호스트에 ping (실시간 그래프)
gping google.com

# 여러 호스트 동시 비교
gping google.com cloudflare.com
```

> 터미널에서 실시간 레이턴시 그래프를 보여준다. 네트워크 문제 진단에 유용.

### net-tools — 네트워크 유틸리티

```bash
# 네트워크 인터페이스 정보
ifconfig

# 열린 포트/연결 확인
netstat -tlnp

# 라우팅 테이블
route -n
```

### ping — 네트워크 연결 확인

```bash
# 호스트 연결 확인
ping -c 4 google.com
```

### openssh — SSH 클라이언트

```bash
# SSH 접속
ssh user@host

# SSH 키 생성
ssh-keygen -t ed25519 -C "comment"

# SSH 에이전트에 키 추가 (호스트에서 포워딩된 에이전트 사용)
ssh-add -l
```

> 컨테이너는 호스트의 SSH 에이전트를 포워딩받아 사용한다. 키 복사 불필요.

---

## Language Runtimes

### Node.js 22 + npm

```bash
node --version
npm --version

# 패키지 설치
npm install

# 스크립트 실행
npm run build
npm test
```

### Bun — 빠른 JavaScript 런타임/패키지 매니저

```bash
bun --version

# 패키지 설치 (npm 호환)
bun install

# 스크립트 실행
bun run build

# TypeScript 직접 실행
bun run script.ts

# 글로벌 패키지 설치
bun install -g package-name
```

### Python 3 + pip

```bash
python3 --version

# 가상환경 생성 및 활성화
python3 -m venv .venv
source .venv/bin/activate

# 패키지 설치
pip install -r requirements.txt

# 스크립트 실행
python3 script.py
```

### TypeScript

```bash
# 타입 체크
tsc --noEmit

# 컴파일
tsc

# bun으로 직접 실행 (컴파일 불필요)
bun run file.ts
```

---

## Build Tools

### build-essential — C/C++ 컴파일러 및 빌드 도구

```bash
# GCC 컴파일
gcc -o app main.c

# Make
make
make install
```

### gnupg — GPG 암호화/서명

```bash
# 키 목록
gpg --list-keys

# 파일 서명
gpg --sign file.txt

# Git 커밋 서명에 사용
git commit -S -m "signed commit"
```

---

## Utility

### man — 매뉴얼 페이지

```bash
# 명령어 매뉴얼 보기
man git
man docker

# 섹션 지정
man 5 crontab
```

> 상세한 공식 문서. 간단한 사용법은 `tldr`이 더 편리하다.

### less — 페이저

```bash
# 파일 보기
less largefile.log

# 검색: /keyword, n(다음), N(이전)
# 끝으로: G, 처음으로: g
```

### file — 파일 타입 확인

```bash
file unknown_file
file *.bin
```

### Archive (zip, unzip, xz-utils)

```bash
# ZIP 압축/해제
zip -r archive.zip directory/
unzip archive.zip

# XZ 압축/해제
xz file.tar
unxz file.tar.xz
```

---

## Security / Quality Scanning

### actionlint — GitHub Actions 워크플로우 린터

```bash
# 현재 리포의 워크플로우 검증
actionlint

# 특정 파일만 검사
actionlint .github/workflows/ci.yml

# JSON 출력
actionlint -format '{{json .}}'
```

> `.github/workflows/*.yml` 파일의 구문, 타입, 표현식 오류를 정적 분석한다.

### trivy — 컨테이너/파일시스템 취약점 스캐너

```bash
# Docker 이미지 CVE 스캔
trivy image agent-sandbox:latest

# 파일시스템 스캔
trivy fs /workspace

# 심각도 필터 (CRITICAL, HIGH만)
trivy image --severity CRITICAL,HIGH myimage:latest

# SBOM 생성
trivy image --format spdx-json -o sbom.json myimage:latest
```

> Aqua Security의 종합 보안 스캐너. OS 패키지, 언어 의존성(npm, pip, go 등), IaC, 시크릿을 검사한다.

### yamllint — YAML 린터

```bash
# YAML 파일 검증
yamllint config.yaml

# 디렉토리 전체 검사
yamllint .github/workflows/

# 엄격 모드
yamllint -s config.yaml
```

> 구문 오류, 들여쓰기, 중복 키, 줄 길이 등 YAML 스타일 규칙을 검사한다.

---

## Alias 참조표

zshrc에 설정된 주요 alias 목록:

| alias | 원래 명령 | 설명 |
|-------|-----------|------|
| `cat` | `bat --paging=never` | 구문 강조 파일 보기 |
| `catp` | `bat --plain --paging=never` | 장식 없는 파일 보기 |
| `ls` | `eza --icons --group-directories-first` | 아이콘 포함 파일 목록 |
| `ll` | `eza --icons --group-directories-first -la` | 상세 파일 목록 |
| `lt` | `eza --icons --tree --level=2` | 트리 구조 |
| `la` | `eza --icons --group-directories-first -a` | 숨김 파일 포함 |
| `find` | `fd` | 빠른 파일 검색 |
| `g` | `git` | Git 단축 |
| `gs` | `git status` | 상태 확인 |
| `ga` | `git add` | 스테이징 |
| `gc` | `git commit` | 커밋 |
| `gp` | `git push` | 푸시 |
| `gl` | `git pull` | 풀 |
| `gd` | `git diff` | 변경사항 |
| `glog` | `git log --oneline --graph --decorate` | 커밋 그래프 |
| `z` | `zoxide` | 스마트 디렉토리 이동 |
| `cls` | `clear` | 화면 지우기 |
| `mkdir` | `mkdir -p` | 중간 디렉토리 자동 생성 |
| `..` | `cd ..` | 상위 디렉토리 |
| `...` | `cd ../..` | 2단계 상위 |
| `....` | `cd ../../..` | 3단계 상위 |

---

## 미설치 도구 (현재)

아래 항목만 미설치 상태다.

| 도구 | alias | 용도 | 비고 |
|------|-------|------|------|
| broot | `br` | 파일 트리 탐색기 | arm64/x86_64 크로스 빌드 이슈 |
